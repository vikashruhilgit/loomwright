#!/usr/bin/env bash
# test-suite-helpers-defined.sh — every assertion helper a test suite CALLS must be DEFINED.
#
# WHY THIS EXISTS (measured, twice, in one PR — v15.20.0 / D6):
#   1. `digest-lanes.test.sh` called `ok`/`no` while the suite defined `pass`/`fail`.
#   2. `test-result-validators.sh` called `assert_ok` while the suite defined `assert_pass`.
#
# Both failed the SAME way, and it is the worst failure mode a test can have: bash has no
# compile step, the suites do not `set -e`, and an unknown command writes to stderr and returns
# 127 — which a suite that tallies its own PASS/FAIL counters never observes. So the assertion
# silently no-ops, the counter never increments, and the suite reports SUCCESS. In case (2) the
# three dead calls were the ONLY coverage of `out_of_lane`'s accept path — the optional-additive
# no-schema-bump property the D6 schema decision rests on — so the suite was green while its
# load-bearing claim was untested.
#
# The tell in both cases was the same and was available for free: the pass COUNT did not rise by
# the number of assertions added (313 -> 315 after adding five). This gate makes that tell
# mechanical instead of a thing a careful reader has to notice.
#
# HEREDOC-AWARE BY NECESSITY. These suites embed Python/awk fixtures in heredocs containing lines
# like `ok = True` and `not R.is_null(...)`. A naive scan reports those as dead helper calls — I
# measured 3 such false positives against 1 true one on the first pass. Heredoc bodies are
# therefore stripped before scanning; without that this gate is noise and would be ignored.
#
# Fail-CLOSED: a dead helper call exits 1. This is a correctness gate, not a fail-safe emitter.
# CI runs it automatically via the existing `loomwright/scripts/test-*.sh` self-test loop, so it
# needs no `.github/workflows/` edit (which would make `claude-code-action` self-skip the PR's
# own review — see CLAUDE.md).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"

PASS=0
FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS + 1)); }
no()  { echo "FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

# Helper-SHAPED call names. Deliberately narrow on the NAME vocabulary: these are the assertion
# vocabularies actually used by this repo's suites. A broad "any bare word" scan would drown in
# shell builtins.
#
# The POSITION, however, must not be narrow. Anchoring on `^[[:space:]]*` alone caught a helper
# only as the first token of a physical line, which misses the `&&`/`||`/`;` idiom this repo uses
# heavily — measured: `test-add-rule.sh` alone has 20+ call sites of the form
# `[ "$RC" -eq 0 ] && ok "..." || no "..."`, every one of them invisible to the old pattern.
# Since this meta-test exists precisely because the FIRST undefined-helper regression escaped
# detection, a blind spot covering the repo's most common assertion idiom defeats its purpose.
# Accept a helper at line start OR immediately after one of the shell SEPARATORS `&&`, `||`, `;`.
# Deliberately NOT after `(` or `{`: those also open ordinary parenthesised PROSE inside quoted
# assertion messages ("(expected 1 rule file)"), which produced false "undefined helper" reports
# for words like `expected` that are not calls at all. Separators cannot appear inside such prose
# without already being shell syntax, so they are the safe widening.
#
# `grep -oE` has no lookbehind, so the matched text INCLUDES the separator; callers strip the
# leading non-letters (see the `sed` in the two scan sites below) before comparing against the
# set of defined function names.
HELPER_NAMES='(assert[a-zA-Z0-9_]*|ok|no|pass|fail|check[a-zA-Z0-9_]*|expect[a-zA-Z0-9_]*|require[a-zA-Z0-9_]*)'
HELPER_RE="(^|&&|\|\||;)[[:space:]]*${HELPER_NAMES}[[:space:]]"
# Strip the separator/whitespace prefix `grep -oE` necessarily captures with the name.
HELPER_STRIP='s/^[^a-zA-Z]*//'
# Widening the position to accept `&&`/`||`/`;` also made ordinary PROSE reachable: a comment
# like `# ... exits 0 BEFORE writing any marker; assert both.` now matches. Comments are not
# code, so drop whole-line comments before scanning. Deliberately whole-line only — stripping
# from a mid-line `#` would corrupt any `#` inside a quoted assertion message, and every false
# positive this actually produced (4 of them, across 4 suites) was a whole-line comment.
STRIP_COMMENTS="/^[[:space:]]*#/d"
# Blank QUOTED spans too — double AND single. A helper CALL is never inside a quoted string, but
# assertion MESSAGES routinely contain prose like "...normal=[$x]; expected exactly ..." — and
# with the position match widened to accept `;`, that prose reads as a separator followed by a
# helper name. Caught immediately on a real file (test-no-junk-tracked-files.sh) the first time
# both changes met. Single-quoted spans carry the same hazard: a mutation leg's sed program must
# quote the target script's own line verbatim, `|| fail "…"` included (test-worktree-salvage.sh's
# AC-18b sink mutant), and a double-quote-only strip read that text as a call to an undefined
# `fail`. Arguments survive as `helper ""`, which still matches HELPER_RE, so real calls are
# unaffected.
#
# ONE left-to-right pass with an alternation, never two sequential strips: at each position the
# quote that OPENS first owns the span (bash single quotes have no escapes, so `'[^']*'` is the
# whole span). Two passes in either order let one quote kind's stray character pair across the
# other kind's span and blank real code between them: single-first turns the apostrophe in
# "don't" into an opener that swallows everything up to the next `'` on the line; double-first
# does the same with a lone `"` inside 'say "hi'. The canary below pins both directions.
STRIP_QUOTED="s/(\"[^\"]*\"|'[^']*')/\"\"/g"

# scan_calls FILE — the helper-shaped call names FILE makes, one per line, sorted and unique.
# The ONE pipeline both the repo scan and the canary self-test run, so the canary proves the
# code that actually gates the repo.
scan_calls() {
  strip_heredocs "$1" | sed "$STRIP_COMMENTS" | sed -E "$STRIP_QUOTED" | grep -oE "$HELPER_RE" \
    | sed -E "$HELPER_STRIP" | tr -d ' \t' | sort -u
}

# strip_heredocs FILE — echo FILE with every heredoc BODY removed (delimiter lines kept, so line
# structure outside the body is preserved). Handles <<EOF, <<-EOF, <<'EOF', <<"EOF".
strip_heredocs() {
  awk '
    {
      if (inhd) {
        line = $0
        sub(/^[ \t]+/, "", line)          # <<- allows a tab-indented terminator
        if (line == delim) { inhd = 0; print "" ; next }
        print ""                          # blank out the body, keep line numbering
        next
      }
      if (match($0, /<<-?[ \t]*"?'"'"'?[A-Za-z_][A-Za-z0-9_]*"?'"'"'?/)) {
        d = substr($0, RSTART, RLENGTH)
        gsub(/^<<-?[ \t]*/, "", d)
        gsub(/["'"'"']/, "", d)
        delim = d
        inhd = 1
      }
      print
    }
  ' "$1"
}

SCANNED=0
DEAD_TOTAL=0

# Collect suites: plugin scripts, third-party adapter self-tests (one directory deeper than the
# flat glob above reaches — docs/ARCHITECTURE_CONTRACTS.md §"Portability"), the sdk-spike suites,
# and wrapper-root test scripts. The adapters glob mirrors the same fix already made to the
# whole-suite CI runner glob in loomwright/scripts/run-self-tests.sh — without it, a new adapter's test suite
# is invisible to this exact dead-helper-call safety net.
SUITES="$(
  { ls "$REPO_ROOT"/loomwright/scripts/test-*.sh 2>/dev/null
    ls "$REPO_ROOT"/loomwright/scripts/adapters/*/test-*.sh 2>/dev/null
    ls "$REPO_ROOT"/loomwright/sdk-spike/test/*.sh 2>/dev/null
    ls "$REPO_ROOT"/scripts/test-*.sh 2>/dev/null
  } | sort -u
)"

for f in $SUITES; do
  [ -f "$f" ] || continue
  # Never scan this file itself — its documentation names the dead helpers as examples.
  case "$(basename "$f")" in test-suite-helpers-defined.sh) continue ;; esac
  SCANNED=$((SCANNED + 1))

  stripped="$(strip_heredocs "$f")"
  defs="$(printf '%s\n' "$stripped" | grep -oE '^[a-zA-Z_][a-zA-Z0-9_]*\(\)' | tr -d '()' | sort -u)"
  calls="$(scan_calls "$f")"

  for c in $calls; do
    [ -n "$c" ] || continue
    grep -qx "$c" < <(printf '%s\n' "$defs") && continue      # defined in-file
    command -v "$c" >/dev/null 2>&1 && continue            # a real command (e.g. `pass`, `check`)
    no "$(basename "$f"): calls helper '$c' which is NOT defined in the file — bash returns 127, the suite's counter never increments, and the suite still reports success"
    DEAD_TOTAL=$((DEAD_TOTAL + 1))
  done
done

if [ "$SCANNED" -eq 0 ]; then
  no "no test suites found to scan — glob or layout changed; refusing to report success"
elif [ "$DEAD_TOTAL" -eq 0 ]; then
  ok "all assertion helpers called by $SCANNED test suites are defined (no silently-dead assertions)"
fi

# ---------------------------------------------------------------------------
# Self-test: the gate must actually CATCH a dead helper. A guard that cannot fail
# is the same class of defect it exists to prevent, so prove it on a fixture.
# ---------------------------------------------------------------------------
TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
mkdir -p "$TMPD/loomwright/scripts"
# Every helper name below except assert_pass is undefined; each case's NAME says whether the
# gate must report it. Lines are scanned, never run.
cat > "$TMPD/loomwright/scripts/test-canary.sh" <<'CANARY'
#!/usr/bin/env bash
assert_pass() { echo ok; }
assert_ok "this helper is not defined — the gate must catch it"
python3 - <<'PY'
ok = True
not_a_helper = 1
PY
for m in 'sink:s/X="\$(y)" || assert_sq_mutant "cannot list \$Z"/X=1/'; do :; done
sed 's/x/; assert_in_single y/' /dev/null
echo "prefix; assert_in_double here"
echo "don't" ; assert_after_apostrophe "x" ; echo 'tail'
echo 'say "hi' ; assert_after_lone_dq "x"
# it's prose; assert_in_comment here
assert_mid_comment "x" # it's a note; and 'more'
CANARY
_c_defs="$(strip_heredocs "$TMPD/loomwright/scripts/test-canary.sh" | grep -oE '^[a-zA-Z_][a-zA-Z0-9_]*\(\)' | tr -d '()' | sort -u)"
_c_calls="$(scan_calls "$TMPD/loomwright/scripts/test-canary.sh")"
_c_dead=""
for c in $_c_calls; do
  grep -qx "$c" < <(printf '%s\n' "$_c_defs") && continue
  command -v "$c" >/dev/null 2>&1 && continue
  _c_dead="$_c_dead $c"
done
_c_dead="${_c_dead# }"
_c_has() { case " $_c_dead " in *" $1 "*) return 0 ;; esac; return 1; }
# (ii) a real undefined call in bare code is reported; heredoc `ok =` / `not ` lines are not.
_c_has assert_ok && ok "self-test: a dead helper call in bare code is reported" \
  || no "self-test: bare-code dead call assert_ok NOT reported — the gate fails open (dead: [$_c_dead])"
# (i) a helper-shaped call inside a single-quoted string (a mutant's sed program) is not a call.
! _c_has assert_sq_mutant && ! _c_has assert_in_single && ok "self-test: helper text inside single-quoted strings is not reported" \
  || no "self-test: single-quoted text read as a call (dead: [$_c_dead])"
# (iii) unchanged: inside a double-quoted string is not a call.
! _c_has assert_in_double && ok "self-test: helper text inside a double-quoted string is not reported" \
  || no "self-test: double-quoted text read as a call (dead: [$_c_dead])"
# (iv) an apostrophe in a double-quoted string, a lone `"` in a single-quoted one, or an
# apostrophe in a comment never swallows a real call later on the line.
_c_has assert_after_apostrophe && _c_has assert_after_lone_dq && _c_has assert_mid_comment \
  && ok "self-test: a stray quote inside the other kind of string (or a comment) does not hide a real call after it" \
  || no "self-test: a real call after a stray quote was hidden (dead: [$_c_dead])"
! _c_has assert_in_comment && ok "self-test: a whole-line comment with an apostrophe is not scanned" \
  || no "self-test: comment prose read as a call (dead: [$_c_dead])"
# Exact set: no false positive beyond the four expected (heredoc `ok =`/`not ` included).
[ "$_c_dead" = "assert_after_apostrophe assert_after_lone_dq assert_mid_comment assert_ok" ] \
  && ok "self-test: the canary reports exactly the 4 expected dead helpers" \
  || no "self-test: expected exactly [assert_after_apostrophe assert_after_lone_dq assert_mid_comment assert_ok], found [$_c_dead] — the gate is mis-tuned (false positives or fail-open)"

echo "----"
echo "test-suite-helpers-defined: $PASS passed, $FAIL failed ($SCANNED suites scanned)"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
