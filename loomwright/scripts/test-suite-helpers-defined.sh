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
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"

PASS=0
FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS + 1)); }
no()  { echo "FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

# Helper-SHAPED call names. Deliberately narrow: these are the assertion vocabularies actually
# used by this repo's suites. A broad "any bare word" scan would drown in shell builtins.
HELPER_RE='^[[:space:]]*(assert[a-zA-Z0-9_]*|ok|no|pass|fail|check[a-zA-Z0-9_]*|expect[a-zA-Z0-9_]*|require[a-zA-Z0-9_]*)[[:space:]]'

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

# Collect suites: plugin scripts, the sdk-spike suites, and wrapper-root test scripts.
SUITES="$(
  { ls "$REPO_ROOT"/loomwright/scripts/test-*.sh 2>/dev/null
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
  calls="$(printf '%s\n' "$stripped" | grep -oE "$HELPER_RE" | tr -d ' \t' | sort -u)"

  for c in $calls; do
    [ -n "$c" ] || continue
    printf '%s\n' "$defs" | grep -qx "$c" && continue      # defined in-file
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
cat > "$TMPD/loomwright/scripts/test-canary.sh" <<'CANARY'
#!/usr/bin/env bash
assert_pass() { echo ok; }
assert_ok "this helper is not defined — the gate must catch it"
python3 - <<'PY'
ok = True
not_a_helper = 1
PY
CANARY
_c_defs="$(strip_heredocs "$TMPD/loomwright/scripts/test-canary.sh" | grep -oE '^[a-zA-Z_][a-zA-Z0-9_]*\(\)' | tr -d '()' | sort -u)"
_c_calls="$(strip_heredocs "$TMPD/loomwright/scripts/test-canary.sh" | grep -oE "$HELPER_RE" | tr -d ' \t' | sort -u)"
_c_dead=0
for c in $_c_calls; do
  printf '%s\n' "$_c_defs" | grep -qx "$c" && continue
  command -v "$c" >/dev/null 2>&1 && continue
  _c_dead=$((_c_dead + 1))
done
if [ "$_c_dead" -eq 1 ]; then
  ok "self-test: the gate catches a dead helper AND ignores heredoc-embedded 'ok ='/'not ' lines (found exactly 1)"
else
  no "self-test: expected exactly 1 dead helper in the canary fixture, found $_c_dead — the gate is mis-tuned (false positives or fail-open)"
fi

echo "----"
echo "test-suite-helpers-defined: $PASS passed, $FAIL failed ($SCANNED suites scanned)"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
