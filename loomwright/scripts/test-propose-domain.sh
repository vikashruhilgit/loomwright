#!/usr/bin/env bash
# test-propose-domain.sh - self-tests for propose-domain.sh, the DOMAIN basis of `/propose`.
#
# HERMETIC BY CONSTRUCTION, and that is the load-bearing property of this file. `.gitignore`
# ignores `.supervisor/*`, and this plugin repo deliberately ships NO product store of its own
# (`.agent/product.json` is written per-project at runtime by propose-product.sh, never by the
# plugin). So propose-domain.sh's two real inputs are both absent from every fresh clone and
# every CI runner, while `loomwright/scripts/test-*.sh` IS auto-globbed by
# `.github/workflows/ci.yml` and gated on. A test driven off the real tree would take the
# fail-safe "no product context" path, write nothing, exit 0 - and PASS, with the producer
# deleted. It would go SILENTLY GREEN.
#
# Every assertion below therefore runs against the COMMITTED fixtures in
# `fixtures/propose-domain/`, copied into a `mktemp -d` OUTSIDE the repo root, and is parsed
# OUT OF THE EMITTED FILES - never read off the script under test.
#
# THE HARNESS ITSELF HARD-FAILS IF jq IS MISSING. Only propose-domain.sh may skip on a missing
# jq; a harness that skipped too would reintroduce exactly the silent CI pass this file exists
# to prevent.
#
# Cases - one per acceptance criterion, plus the controls each one needs:
#   AC1  bare `/propose` (the ledger basis, propose-work.sh) makes ZERO external calls, asserted
#        by installing a counting, network-denying fetcher stub and observing an EMPTY call log,
#        with a positive control proving the counter can record
#   AC2  absent store: the named "no product context" message + the propose-product.sh bootstrap
#        offer on stderr, zero files written, exit 0
#   AC3  emission: >=1 gap, and the emitted file's classification, evidence classes, surfaces
#        searched WITH THE EXACT TERMS USED, and each cited source's url and fetch date are all
#        parsed out of it and re-derived independently from the fixture store
#   AC4  unverified is NOT absent - with a MUTATION CONTROL that collapses the unverified branch
#        and asserts the case then fails
#   AC5  stance: `product` vs `tool` produce IDENTICAL classifications and DIFFERENT default
#        actions, asserted by diffing the two runs; and neither action string is computed in
#        propose-domain.sh (read-product.sh's `def STANCE_ACTIONS` is its only home)
#   AC6  a NOT-FOR-US gap recorded in a `## Status: done` requirement file is not re-emitted and
#        the suppression NAMES the file - with a MUTATION CONTROL deleting the check
#   AC7  PROPOSE_DOMAIN_MAX_FETCHES=1 against a 3-competitor store: EXACTLY ONE external call in
#        the stub's log, and partial coverage naming what was not reached
#   AC8  staleness: the deliberately-old source is named STALE; and the separate `null`
#        last_fetched case renders as NEVER FETCHED - never as a date, never as stale
#   AC9  namespacing: both bases into ONE directory; every domain candidate is `domain--*.md`
#        and neither basis overwrote the other's file
#   AC10 blast radius: hashed on the FILESYSTEM tree (never a git reading, with the proof that a
#        git reading would be vacuous here) - with a MUTATION CONTROL that deletes the
#        write-path guard and plants a REAL stray write through a symlink
#   AC11 no score/rank/priority/top-N/ordering field in any emitted file, on a run that emitted
#        >=1 file, with a POSITIVE CONTROL proving the grep can fire
#   AC12 determinism: two independent runs into two separate empty dirs, byte for byte
#
# EVERY temp tree is materialised OUTSIDE the repo root via mktemp -d. Staging a fixture
# anywhere under the repo would make AC10 fail on this test's own scratch files.
#
# Local traps this file deliberately avoids, each of which silently makes an assertion vacuous
# while everything stays green:
#   * `producer | grep -q` returns 141 under `pipefail` EVEN ON A MATCH - so `grep -q` is only
#     ever run directly against a FILE here, never as the right-hand side of a pipe. (The one
#     pipe into grep, the git-blindness probe in AC10, uses `grep -c`, which drains stdin and so
#     cannot SIGPIPE, and its status is discarded by the assignment anyway.)
#   * `local x="$(...)"` discards the command's exit status - assignment and status check are
#     always separate statements below.
#   * `... || echo 0` APPENDS a second line rather than replacing - counts come from an awk END.
#   * `stat -f %m` is BSD and SUCCEEDS WITH GARBAGE on GNU/Linux - so this file takes no mtime
#     dependency at all. There is no `date -d` (GNU-only) and no `timeout` (absent on stock
#     macOS) either, and the staleness "now" is PINNED from the fixture store's own
#     `written_at` through jq, so no case here can age into a different verdict after the
#     commit that added it.
#   * bash 3.2: no associative arrays, no `${var^^}`.
#
# Exit 0 = all pass, 1 = any failure. Registered automatically by ci.yml's test-*.sh glob.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/propose-domain.sh"
LEDGER_SUT="$HERE/propose-work.sh"
READ_PRODUCT="$HERE/read-product.sh"
FIXSRC="$HERE/fixtures/propose-domain"
LEDGER_FIX="$HERE/fixtures/propose-work/floor-golden.json"

pass=0; fail=0; skip=0
ok()   { echo "  ok: $1";       pass=$((pass+1)); }
no()   { echo "  FAIL: $1";     fail=$((fail+1)); }
skipn(){ echo "  SKIPPED - $1"; skip=$((skip+1)); }

# The harness's own hard preconditions. These are NOT skips.
if ! command -v jq >/dev/null 2>&1; then
  echo "FATAL: jq is not on PATH - the harness itself requires it to re-derive every"
  echo "       expectation from the fixture store independently of the script under test."
  echo "       Only propose-domain.sh may skip on a missing jq; this file may not."
  exit 1
fi
for f in "$SUT" "$LEDGER_SUT" "$READ_PRODUCT" "$LEDGER_FIX" \
         "$FIXSRC/product.json" "$FIXSRC/product-tool.json" "$FIXSRC/fetch-stub.sh" \
         "$FIXSRC/source-acme.txt" "$FIXSRC/source-bolt.txt" "$FIXSRC/source-cursive.txt" \
         "$FIXSRC/README.md" "$FIXSRC/inventory/src/search_service.py"; do
  [ -f "$f" ] || { echo "FATAL: required fixture or script missing: $f"; exit 1; }
done

ROOT="$(mktemp -d)"   # OUTSIDE the repo root, deliberately - see the header note on AC10.
trap 'chmod -R u+rwX "$ROOT" >/dev/null 2>&1; rm -rf "$ROOT" 2>/dev/null' EXIT
mktmp() { mktemp -d "$ROOT/d.XXXXXX"; }

LOGOUT="$ROOT/last.out"
LOGERR="$ROOT/last.err"

# The fixtures are used from a COPY outside the repo: the stub is invoked as
# PROPOSE_DOMAIN_FETCH_CMD and resolved with `command -v`, so it must be executable regardless
# of the mode bit a checkout happened to produce.
FIX="$ROOT/fixtures"
mkdir -p "$FIX"
# Mutants live in their own directory WITH A COPY OF read-product.sh beside them, because
# propose-domain.sh resolves the reader as `$(dirname $0)/read-product.sh`. A mutant dropped
# anywhere else takes the reader-missing skip path, emits nothing, and every mutation control
# then "passes" for the wrong reason - the exact vacuity these controls exist to rule out.
MUTDIR="$ROOT/mutants"
mkdir -p "$MUTDIR"
cp "$READ_PRODUCT" "$MUTDIR/read-product.sh" 2>/dev/null
[ -f "$MUTDIR/read-product.sh" ] \
  && ok "staged read-product.sh beside the mutants, so a mutant runs the same reader the real script does" \
  || no "could not stage the reader beside the mutants - every mutation control would skip and pass vacuously"
cp -R "$FIXSRC/." "$FIX/" 2>/dev/null
chmod +x "$FIX/fetch-stub.sh" 2>/dev/null
[ -x "$FIX/fetch-stub.sh" ] && ok "the committed fetch stub is staged executable outside the repo root" \
  || no "could not stage an executable fetch stub - every fetching case below is inconclusive"
FETCHER="$FIX/fetch-stub.sh"

# The staleness "now", PINNED from the fixture store's own written_at. A wall-clock now would
# age Acme Docs past the 90d threshold some weeks after this commit and silently flip AC8.
PIN="$(jq -r '.written_at | fromdateiso8601' "$FIX/product.json" 2>/dev/null)"
case "$PIN" in
  ''|*[!0-9]*) echo "FATAL: could not derive a pinned epoch from the fixture store's written_at"; exit 1 ;;
esac
ok "staleness clock pinned to the fixture store's own written_at (epoch $PIN) - no case here can age"

# ---------------------------------------------------------------------------
# A counting, NETWORK-DENYING shim. The fetch stub counts calls made through the ONE named
# seam; this shim catches anything that tried to reach the network around it. Both are
# observations of behaviour, never of source text.
# ---------------------------------------------------------------------------
SHIM="$ROOT/shim"
NETLOG="$ROOT/network-attempts.txt"
mkdir -p "$SHIM"
: > "$NETLOG"
for tool in curl wget nc ncat telnet ftp scp ssh; do
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "%%s %%s\\n" "%s" "$*" >> "%s"\n' "$tool" "$NETLOG"
    printf 'exit 1\n'
  } > "$SHIM/$tool"
  chmod +x "$SHIM/$tool"
done

# ---------------------------------------------------------------------------
# Helpers. Assignment and status check stay separate statements throughout.
# ---------------------------------------------------------------------------
lines() { [ -f "$1" ] || { echo 0; return 0; }; awk 'END{print NR+0}' "$1"; }

count_domain() { find "$1" -maxdepth 1 -type f -name 'domain--*.md' 2>/dev/null | awk 'END{print NR+0}'; }
count_md()     { find "$1" -maxdepth 1 -type f -name '*.md'         2>/dev/null | awk 'END{print NR+0}'; }

csum() {
  if   command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" 2>/dev/null | cut -d' ' -f1
  elif command -v shasum    >/dev/null 2>&1; then shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
  else cksum "$1" 2>/dev/null | cut -d' ' -f1; fi
}

# new_project <store-fixture> - a throwaway git repo OUTSIDE the repo root holding the fixture
# inventory tree and a product store at the default location. Its PHYSICAL path is printed:
# propose-domain.sh resolves its root through `git rev-parse --show-toplevel`, which is
# physical, and a logical path here would stop the store being excluded from its own inventory.
new_project() {
  np="$(mktmp)"
  mkdir -p "$np/.agent"
  cp -R "$FIX/inventory/." "$np/" 2>/dev/null
  cp "$1" "$np/.agent/product.json"
  mkdir -p "$np/.supervisor/requirements/archive" "$np/.supervisor/floor"
  printf 'pre-existing requirement\n' > "$np/.supervisor/requirements/archive/old.md"
  printf 'state\n' > "$np/.supervisor/state.md"
  ( cd "$np" && printf '.supervisor/*\n' > .gitignore \
      && git init -q && git config user.email t@t && git config user.name t \
      && git add -A && git commit -qm init ) >/dev/null 2>&1
  ( cd "$np" && pwd -P )
}

# run_domain - every knob is a global, so a case sets only what it means to change.
D_PROJ=""; D_STORE=""; D_OUT=""; D_REQ=""; D_FETCH=""; D_CALLS=""; D_MAXF=""; D_SCRIPT=""
reset_domain() { D_STORE=""; D_OUT=""; D_REQ=""; D_FETCH="$FETCHER"; D_CALLS=""; D_MAXF=""; D_SCRIPT="$SUT"; }
run_domain() {
  ( cd "$D_PROJ" 2>/dev/null || exit 9
    export PATH="$SHIM:$PATH"
    export PROPOSE_DOMAIN_SOURCE_DATE_EPOCH="$PIN"
    [ -n "$D_STORE" ] && export PROPOSE_DOMAIN_STORE="$D_STORE"
    [ -n "$D_OUT" ]   && export PROPOSE_DOMAIN_OUT_DIR="$D_OUT"
    [ -n "$D_REQ" ]   && export PROPOSE_DOMAIN_REQUIREMENTS_DIR="$D_REQ"
    [ -n "$D_FETCH" ] && export PROPOSE_DOMAIN_FETCH_CMD="$D_FETCH"
    [ -n "$D_CALLS" ] && export PROPOSE_DOMAIN_FETCH_CALLS="$D_CALLS"
    [ -n "$D_MAXF" ]  && export PROPOSE_DOMAIN_MAX_FETCHES="$D_MAXF"
    bash "$D_SCRIPT" ) >"$LOGOUT" 2>"$LOGERR"
  return $?
}

# The canonical project every content case runs against. One project, many output dirs: the
# emitted bytes name the project root, so two runs that must be comparable have to share it.
PROJ="$(new_project "$FIX/product.json")"
[ -d "$PROJ/.git" ] && ok "built the fixture project as a throwaway git repo outside the repo root: $PROJ" \
  || no "could not build the fixture project - every case below is inconclusive"

echo
echo "== AC1: bare /propose (the ledger basis) makes ZERO external calls =="
# Asserted by OBSERVING the stub and the network shim, never by grepping propose-work.sh.
A1="$(mktmp)"
A1_CALLS="$A1/calls.txt"; : > "$A1_CALLS"
NOW="$(date -u +%s)"
case "$NOW" in ''|*[!0-9]*) echo "FATAL: could not read the clock"; exit 1 ;; esac
jq --argjson n "$NOW" '.generated_at_epoch = $n' "$LEDGER_FIX" > "$A1/floor.json" 2>/dev/null
[ -s "$A1/floor.json" ] && ok "the ledger basis fixture was restamped fresh (the ledger run must actually emit, or an empty call log proves nothing)" \
  || no "could not restamp the ledger fixture"
: > "$NETLOG"
( cd "$PROJ" && PATH="$SHIM:$PATH" \
    PROPOSE_FLOOR_JSON="$A1/floor.json" PROPOSE_OUT_DIR="$A1/out" PROPOSE_REQUIREMENTS_DIR="$A1/req" \
    PROPOSE_DOMAIN_FETCH_CMD="$FETCHER" PROPOSE_DOMAIN_FETCH_CALLS="$A1_CALLS" \
    bash "$LEDGER_SUT" ) >"$LOGOUT" 2>"$LOGERR"; rc=$?
[ "$rc" -eq 0 ] && ok "the ledger basis exited 0 with a fetcher installed" || no "the ledger basis exited $rc"
a1_props="$(count_md "$A1/out")"
[ "$a1_props" -ge 1 ] \
  && ok "the ledger run actually did its work ($a1_props file(s) emitted) - so an empty call log is a fact about fetching, not about a run that did nothing" \
  || no "the ledger run emitted nothing; 'it made no calls' would then prove nothing
$(cat "$LOGERR" 2>/dev/null)"
a1_calls="$(lines "$A1_CALLS")"
[ "$a1_calls" -eq 0 ] \
  && ok "the fetch stub's call log is EMPTY - bare /propose attempted no call through the fetch seam" \
  || no "the fetch stub recorded $a1_calls call(s) from the ledger basis:
$(cat "$A1_CALLS")"
a1_net="$(lines "$NETLOG")"
[ "$a1_net" -eq 0 ] \
  && ok "the network-denying shim (curl/wget/nc/ncat/telnet/ftp/scp/ssh) recorded no attempt around the seam either" \
  || no "the ledger basis tried to reach the network outside the fetch seam:
$(cat "$NETLOG")"
# POSITIVE CONTROL: a counter that cannot count would make the two assertions above vacuous.
reset_domain
D_PROJ="$PROJ"; D_OUT="$A1/dout"; D_REQ="$A1/dreq"; D_CALLS="$A1_CALLS"
run_domain >/dev/null 2>&1
a1_after="$(lines "$A1_CALLS")"
[ "$a1_after" -gt 0 ] \
  && ok "POSITIVE CONTROL: the same stub and the same log DO record $a1_after call(s) when the --domain basis runs, so the empty log above is a measurement" \
  || no "POSITIVE CONTROL FAILED: the call log stays empty even for the --domain basis - the counter records nothing and AC1 proves nothing"

echo
echo "== AC2: no product store - name it, offer the bootstrap, write nothing, exit 0 =="
A2="$(mktmp)"
: > "$A2/calls.txt"
reset_domain
D_PROJ="$PROJ"; D_STORE="$A2/definitely-absent-product.json"; D_OUT="$A2/out"; D_REQ="$A2/req"; D_CALLS="$A2/calls.txt"
run_domain; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0 with no store" || no "exit $rc with no store - an advisory reader must never break its caller"
grep -Fq 'No product context' "$LOGERR" 2>/dev/null \
  && ok "the absence is NAMED ('No product context'), not silently skipped" \
  || no "the run did not name the missing product context:
$(cat "$LOGERR" 2>/dev/null)"
grep -Fq 'propose-product.sh' "$LOGERR" 2>/dev/null \
  && ok "the bootstrap offer names propose-product.sh" || no "no propose-product.sh bootstrap offer on stderr"
grep -Fq '${CLAUDE_PLUGIN_ROOT}' "$LOGERR" 2>/dev/null \
  && ok "the bootstrap offer is written in the runtime plugin-root form, not a maintainer-only repo path" \
  || no "the bootstrap offer does not use \${CLAUDE_PLUGIN_ROOT} - it would not resolve for a plugin user"
grep -Fq -- '--stance' "$LOGERR" 2>/dev/null \
  && ok "the offer names the one field the bootstrap cannot guess (--stance)" \
  || no "the offer does not mention --stance"
a2_files="$(find "$A2/out" -type f 2>/dev/null | awk 'END{print NR+0}')"
[ "$a2_files" -eq 0 ] && ok "ZERO files were written (the output directory was not even created)" \
  || no "$a2_files file(s) were written despite there being no store"
a2_calls="$(lines "$A2/calls.txt")"
[ "$a2_calls" -eq 0 ] && ok "nothing was fetched either - the store is read before any call is made" \
  || no "$a2_calls fetch(es) happened with no store to name a competitor"

echo
echo "== AC3: emission - classification, evidence classes, surfaces + exact terms, url + date =="
A3="$(mktmp)"; A3O="$A3/out"; A3R="$A3/req"
: > "$A3/calls.txt"
reset_domain
D_PROJ="$PROJ"; D_OUT="$A3O"; D_REQ="$A3R"; D_CALLS="$A3/calls.txt"
run_domain; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0 on the fixture store with the stub fetcher" || no "exit $rc
$(cat "$LOGERR" 2>/dev/null)"
n3="$(count_domain "$A3O")"
[ "$n3" -ge 1 ] && ok "the run emitted $n3 gap file(s) - every assertion below runs against a NON-EMPTY set" \
  || no "the run emitted no gap files; AC3/AC4/AC8/AC11/AC12 would all pass vacuously
$(cat "$LOGERR" 2>/dev/null)"

F3="$A3O/domain--audit-log.md"
if [ ! -f "$F3" ]; then
  no "expected gap file domain--audit-log.md was not emitted - AC3 cannot be evaluated
$(ls -1 "$A3O" 2>/dev/null)"
else
  ok "a gap file was emitted for a capability the fixture project lacks: $(basename "$F3")"

  # -- classification -----------------------------------------------------------------------
  cls3="$(grep -m1 '^- classification: ' "$F3" 2>/dev/null | sed 's/^- classification: //')"
  case "$cls3" in
    TABLE-STAKES|DIFFERENTIATOR|NOT-FOR-US) ok "the file carries its classification, and it is one of the three permitted values ($cls3)" ;;
    *) no "the file carries no valid classification (read: '$cls3')" ;;
  esac

  # -- evidence classes ---------------------------------------------------------------------
  grep -Fq 'evidence class: derived' "$F3" 2>/dev/null \
    && ok "the derived evidence class is named on its own section" || no "no 'evidence class: derived' section"
  grep -Fq 'evidence class: external/judgment' "$F3" 2>/dev/null \
    && ok "the external/judgment evidence class is named, and separately from the derived one" \
    || no "no 'evidence class: external/judgment' section - the two classes are not visibly different"
  grep -Fq 'the weakest input' "$F3" 2>/dev/null \
    && ok "the external class is stated as the weakest input" || no "the external class is not marked as the weakest input"

  # -- the surfaces searched, with counts re-derived independently ---------------------------
  # The globs are PARSED OUT OF THE FILE and used to recount, so this cannot drift against a
  # second copy of the glob list living here.
  code_line="$(grep -m1 '^- code surface: ' "$F3" 2>/dev/null)"
  doc_line="$(grep -m1 '^- doc surface: ' "$F3" 2>/dev/null)"
  ori_line="$(grep -m1 '^- orientation memos: ' "$F3" 2>/dev/null)"
  claim_code="$(printf '%s' "$code_line" | sed 's/^- code surface: \([0-9][0-9]*\) file(s).*$/\1/')"
  claim_doc="$(printf '%s' "$doc_line"  | sed 's/^- doc surface: \([0-9][0-9]*\) file(s).*$/\1/')"
  claim_ori="$(printf '%s' "$ori_line"  | sed 's/^- orientation memos: \([0-9][0-9]*\) file(s).*$/\1/')"
  code_globs="$(printf '%s' "$code_line" | sed 's/^.*matching `\([^`]*\)`.*$/\1/')"
  doc_globs="$(printf '%s' "$doc_line"   | sed 's/^.*matching `\([^`]*\)`.*$/\1/')"

  # count_surface <root> <globs> <path-to-exclude> - noglob is on for the pattern loop, or the
  # unquoted `*.sh` patterns would be pathname-expanded before they are ever used as patterns.
  # The intermediate lists go through FILES, not a nested command substitution: bash 3.2
  # mis-parses a `case` pattern's closing `)` inside `$( ... )` and takes it as the end of the
  # substitution, which failed loudly here rather than silently - but only once.
  count_surface() {
    cs_root="$1"; cs_globs="$2"; cs_excl="$3"
    find "$cs_root" \( -name .git -o -name node_modules -o -name .supervisor -o -name vendor \) -prune -o \
      -type f -print 2>/dev/null | LC_ALL=C sort > "$ROOT/surface.all"
    : > "$ROOT/surface.hit"
    set -f
    while IFS= read -r cs_p; do
      [ "$cs_p" = "$cs_excl" ] && continue
      cs_b="${cs_p##*/}"
      case "$cs_b" in domain--*.md) continue ;; esac
      for cs_g in $cs_globs; do
        case "$cs_b" in $cs_g) printf '%s\n' "$cs_p" >> "$ROOT/surface.hit"; break ;; esac
      done
    done < "$ROOT/surface.all"
    set +f
    lines "$ROOT/surface.hit"
  }
  real_code="$(count_surface "$PROJ" "$code_globs" "$PROJ/.agent/product.json")"
  real_doc="$(count_surface "$PROJ" "$doc_globs" "$PROJ/.agent/product.json")"
  real_ori="$(find "$PROJ/.agent/orientation" -type f -name '*.md' 2>/dev/null | awk 'END{print NR+0}')"
  [ "$claim_code" = "$real_code" ] \
    && ok "the code surface it says it searched is real: $claim_code file(s), independently recounted with the globs the file itself names" \
    || no "the file claims $claim_code code file(s); an independent recount with its own globs finds $real_code"
  [ "$claim_doc" = "$real_doc" ] \
    && ok "the doc surface it says it searched is real: $claim_doc file(s), independently recounted" \
    || no "the file claims $claim_doc doc file(s); an independent recount finds $real_doc"
  [ "$claim_ori" = "$real_ori" ] \
    && ok "the orientation memos it says it read are real: $claim_ori file(s) under .agent/orientation/" \
    || no "the file claims $claim_ori orientation memo(s); the fixture project has $real_ori"

  # -- the EXACT TERMS used, verified by re-running the search with them ---------------------
  terms_line="$(grep -m1 '^- exact terms used' "$F3" 2>/dev/null)"
  printf '%s\n' "$terms_line" | tr ',' '\n' | sed -n 's/^[^`]*`\([^`]*\)`.*$/\1/p' > "$A3/terms.txt"
  n_terms="$(lines "$A3/terms.txt")"
  [ "$n_terms" -ge 1 ] \
    && ok "the file quotes the exact terms it searched for ($n_terms of them: $(tr '\n' ' ' < "$A3/terms.txt"))" \
    || no "the file does not quote the terms it used - 'we don't have it' is then unbacked"
  # The claim under test: those terms, run against the code surface it named, really do find
  # nothing. Word-bounded, as the file says it matched.
  awk '{ printf "(^|[^[:alnum:]])%s([^[:alnum:]]|$)\n", $0 }' "$A3/terms.txt" > "$A3/terms.pat"
  set -f
  find "$PROJ" \( -name .git -o -name .supervisor \) -prune -o -type f \
    \( -name '*.sh' -o -name '*.py' -o -name '*.yml' -o -name '*.json' \) -print 2>/dev/null \
    | LC_ALL=C sort > "$A3/code.list"
  set +f
  : > "$A3/termhits.txt"
  while IFS= read -r cf; do
    [ -f "$cf" ] || continue
    [ "$cf" = "$PROJ/.agent/product.json" ] && continue
    if grep -q -I -i -E -f "$A3/terms.pat" "$cf" 2>/dev/null; then printf '%s\n' "$cf" >> "$A3/termhits.txt"; fi
  done < "$A3/code.list"
  th="$(lines "$A3/termhits.txt")"
  [ "$th" -eq 0 ] \
    && ok "re-running the file's own terms over the code surface independently finds nothing, exactly as it reports" \
    || no "the file says the code surface matched nothing, but its own terms match $th file(s):
$(cat "$A3/termhits.txt")"
  # DISCRIMINATING CONTROL for that recount: the same machinery must find the one capability
  # the fixture project genuinely HAS, or 'it found nothing' is a fact about a broken search.
  printf '(^|[^[:alnum:]])usage analytics([^[:alnum:]]|$)\n' > "$A3/ctl.pat"
  ctl_hits=0
  while IFS= read -r cf; do
    [ -f "$cf" ] || continue
    if grep -q -I -i -E -f "$A3/ctl.pat" "$cf" 2>/dev/null; then ctl_hits=$((ctl_hits+1)); fi
  done < "$A3/code.list"
  [ "$ctl_hits" -ge 1 ] \
    && ok "DISCRIMINATING CONTROL: the same recount DOES find 'usage analytics' in the fixture code ($ctl_hits file(s)), so a no-match above is a real no-match" \
    || no "DISCRIMINATING CONTROL FAILED: the recount finds nothing at all, so it cannot distinguish present from absent"

  # -- every cited source's url and fetch date, checked against the store --------------------
  grep -E '^- .+ - url: .+ - fetch date: .+$' "$F3" > "$A3/cites.txt" 2>/dev/null
  n_cites="$(lines "$A3/cites.txt")"
  [ "$n_cites" -ge 1 ] && ok "the file cites $n_cites source(s), each with a url and a fetch date" \
    || no "the file cites no source with a url and a fetch date"
  cite_bad=0
  while IFS= read -r cline; do
    [ -n "$cline" ] || continue
    cname="$(printf '%s' "$cline" | sed 's/^- \(.*\) - url: .*$/\1/')"
    curl_="$(printf '%s' "$cline" | sed 's/^.* - url: \(.*\) - fetch date: .*$/\1/')"
    cdate="$(printf '%s' "$cline" | sed 's/^.* - fetch date: //')"
    want_url="$(jq -r --arg n "$cname" '.competitors[] | select(.name == $n) | .url' "$FIX/product.json" 2>/dev/null)"
    want_lf="$(jq -r --arg n "$cname" '.competitors[] | select(.name == $n) | (.last_fetched // "null")' "$FIX/product.json" 2>/dev/null)"
    [ "$curl_" = "$want_url" ] || { cite_bad=1; echo "     url mismatch for '$cname': file says '$curl_', store says '$want_url'"; }
    if [ "$want_lf" = "null" ]; then
      case "$cdate" in *"never fetched"*) : ;; *) cite_bad=1; echo "     '$cname' has a null last_fetched but the file renders '$cdate'" ;; esac
    else
      case "$cdate" in *"$want_lf"*) : ;; *) cite_bad=1; echo "     date mismatch for '$cname': file says '$cdate', store says '$want_lf'" ;; esac
    fi
  done < "$A3/cites.txt"
  [ "$cite_bad" -eq 0 ] \
    && ok "every cited source's url and fetch date match the product store, re-read independently with jq" \
    || no "a cited source's url or fetch date does not match the store"
fi

echo
echo "== AC4: unverified is NOT absent - with a mutation control =="
F4="$A3O/domain--single-sign-on.md"
if [ ! -f "$F4" ]; then
  no "no gap file for the ambiguous capability (single-sign-on: named in an orientation memo, unconfirmed in code) - AC4 cannot be evaluated"
else
  grep -Fq -- '- inventory status: unverified' "$F4" 2>/dev/null \
    && ok "the ambiguous capability is emitted as \`unverified\`" \
    || no "the ambiguous capability is not marked unverified: $(grep -m1 '^- inventory status:' "$F4")"
  grep -Fq -- '- inventory status: missing' "$F4" 2>/dev/null \
    && no "the same file also claims the capability is missing" \
    || ok "the file never claims the capability is missing"
  grep -Fq 'conclusion: `missing`' "$F4" 2>/dev/null \
    && no "the evidence section concludes \`missing\` on an unverified capability" \
    || ok "the evidence section's conclusion is not \`missing\`"
  grep -Fq 'does NOT mean the capability is absent' "$F4" 2>/dev/null \
    && ok "the file says in words that unverified does not mean absent" \
    || no "the file does not say what unverified means - a reader can still read it as absent"
  grep -Fq 'documented but unconfirmed' "$F4" 2>/dev/null \
    && ok "it names WHY it could not confirm either way (documented but unconfirmed)" \
    || no "it does not name why the capability could not be confirmed either way"
fi
echo "-- MUTATION CONTROL: collapse the unverified branch and AC4 must go RED --"
MUT4="$MUTDIR/mutant-nounverified.sh"
sed 's/elif \[ -n "\$doc_hits" \]; then/elif false; then/' "$SUT" > "$MUT4" 2>/dev/null
if [ -s "$MUT4" ] && ! cmp -s "$MUT4" "$SUT" && bash -n "$MUT4" 2>/dev/null; then
  ok "built a syntactically valid mutant whose documented-but-unconfirmed branch can never fire"
  M4="$(mktmp)"
  reset_domain
  D_PROJ="$PROJ"; D_OUT="$M4/out"; D_REQ="$M4/req"; D_SCRIPT="$MUT4"
  run_domain >/dev/null 2>&1
  MF4="$M4/out/domain--single-sign-on.md"
  if [ -f "$MF4" ]; then
    grep -Fq -- '- inventory status: missing' "$MF4" 2>/dev/null \
      && ok "MUTATION CONTROL: without that branch the same capability is reported \`missing\` - AC4's assertion genuinely can fail" \
      || no "the mutant still reports it as $(grep -m1 '^- inventory status:' "$MF4") - AC4 passes with the mechanism deleted and proves nothing"
  else
    no "the mutant emitted no single-sign-on file - the AC4 control is inconclusive"
  fi
else
  no "could not build a valid unverified-branch mutant - AC4 is uncontrolled"
fi

echo
echo "== AC5: stance decides the default action and NOTHING else =="
A5="$(mktmp)"
reset_domain
D_PROJ="$PROJ"; D_OUT="$A5/product"; D_REQ="$A5/req"
run_domain >/dev/null 2>&1
cp "$FIX/product-tool.json" "$PROJ/.agent/product.json"
reset_domain
D_PROJ="$PROJ"; D_OUT="$A5/tool"; D_REQ="$A5/req"
run_domain >/dev/null 2>&1
cp "$FIX/product.json" "$PROJ/.agent/product.json"   # restore, so later cases are unaffected
np5="$(count_domain "$A5/product")"; nt5="$(count_domain "$A5/tool")"
[ "$np5" -ge 1 ] && [ "$np5" -eq "$nt5" ] \
  && ok "both stances emitted the same $np5 gap file(s) - the diff below is over a non-empty, aligned pair" \
  || no "the two stances emitted $np5 and $nt5 file(s) - AC5's diff is not comparable"
( cd "$A5/product" && grep -H '^- classification: ' ./*.md 2>/dev/null | LC_ALL=C sort ) > "$A5/cls.product"
( cd "$A5/tool"    && grep -H '^- classification: ' ./*.md 2>/dev/null | LC_ALL=C sort ) > "$A5/cls.tool"
if cmp -s "$A5/cls.product" "$A5/cls.tool"; then
  ok "IDENTICAL classifications under both stances ($(lines "$A5/cls.product") files compared, per file)"
else
  no "the classifications differ between stances - stance must never be a classification input:
$(diff "$A5/cls.product" "$A5/cls.tool")"
fi
p_act="$(grep -h '^- default action: ' "$A5/product"/*.md 2>/dev/null | LC_ALL=C sort -u)"
t_act="$(grep -h '^- default action: ' "$A5/tool"/*.md 2>/dev/null | LC_ALL=C sort -u)"
[ "$p_act" = "- default action: build-highest-priority" ] \
  && ok "stance \`product\` yields exactly one default action, and it is \`build-highest-priority\`" \
  || no "stance product's default action(s): '$p_act'"
[ "$t_act" = "- default action: do-not-build-by-default" ] \
  && ok "stance \`tool\` yields exactly one default action, and it is \`do-not-build-by-default\`" \
  || no "stance tool's default action(s): '$t_act'"
[ "$p_act" != "$t_act" ] && ok "the two default actions DIFFER, which is the whole point of the stance field" \
  || no "the two stances produced the same default action"
# Everything that differs between the two runs must be stance-shaped. Anything else would mean
# stance leaked into a second decision.
diff -r "$A5/product" "$A5/tool" 2>/dev/null | grep -E '^[<>] ' > "$A5/diffl.txt"
nd5="$(lines "$A5/diffl.txt")"
off5=0
while IFS= read -r dl; do
  [ -n "$dl" ] || continue
  case "$dl" in
    *stance*|*build-highest-priority*|*do-not-build-by-default*) : ;;
    *) off5=$((off5+1)); echo "     non-stance difference: $dl" ;;
  esac
done < "$A5/diffl.txt"
[ "$nd5" -gt 0 ] && [ "$off5" -eq 0 ] \
  && ok "all $nd5 differing line(s) between the two runs mention the stance or its action - nothing else moved" \
  || no "$off5 of $nd5 differing line(s) are not stance-shaped"
# The mapping has exactly one home. Comment lines are excluded: propose-domain.sh's header
# discusses the string on purpose (it is why the no-score check must be field-shaped).
grep -vE '^[[:space:]]*#' "$SUT" > "$A5/sut.code" 2>/dev/null
grep -Eq 'build-highest-priority|do-not-build-by-default' "$A5/sut.code" 2>/dev/null \
  && no "propose-domain.sh computes a stance action in executable code - the mapping now has two homes:
$(grep -nE 'build-highest-priority|do-not-build-by-default' "$A5/sut.code")" \
  || ok "no executable line of propose-domain.sh contains either action string - it prints what the reader emitted"
grep -vE '^[[:space:]]*#' "$READ_PRODUCT" > "$A5/rp.code" 2>/dev/null
grep -Fq 'def STANCE_ACTIONS' "$A5/rp.code" 2>/dev/null \
  && ok "POSITIVE CONTROL: read-product.sh's executable \`def STANCE_ACTIONS\` is where both strings do live" \
  || no "POSITIVE CONTROL FAILED: read-product.sh has no executable def STANCE_ACTIONS, so the check above cannot distinguish 'one home' from 'no home'"

echo
echo "== AC6: a recorded NOT-FOR-US gap is not raised again, and the suppression names the file =="
A6="$(mktmp)"; A6R="$A6/req"; mkdir -p "$A6R"
reset_domain
D_PROJ="$PROJ"; D_OUT="$A6/run1"; D_REQ="$A6R"
run_domain >/dev/null 2>&1
NFU="$A6/run1/domain--card-data-vaulting.md"
if [ ! -f "$NFU" ]; then
  no "no NOT-FOR-US gap was emitted on the first run - AC6 cannot be evaluated
$(ls -1 "$A6/run1" 2>/dev/null)"
else
  grep -Fq -- '- classification: NOT-FOR-US' "$NFU" 2>/dev/null \
    && ok "the first run emitted a NOT-FOR-US gap (an adjacent-domain expectation, out of this store's scope)" \
    || no "the expected file is not classified NOT-FOR-US: $(grep -m1 '^- classification:' "$NFU")"
  TOK6="$(grep -m1 '^domain-gap: ' "$NFU" 2>/dev/null)"
  [ -n "$TOK6" ] && ok "the gap carries a dedup token: $TOK6" || no "the gap carries no dedup token - it can never be dismissed durably"
  DONE6="$A6R/2026-09-09-not-for-us.md"
  { printf '# Card-data vaulting: decided NOT-FOR-US\n\n## Status: done\n\n%s\n' "$TOK6"; } > "$DONE6"
  reset_domain
  D_PROJ="$PROJ"; D_OUT="$A6/run2"; D_REQ="$A6R"
  run_domain; rc=$?
  [ "$rc" -eq 0 ] && ok "the second run exited 0" || no "the second run exited $rc"
  [ ! -f "$A6/run2/domain--card-data-vaulting.md" ] \
    && ok "the second run did NOT re-emit the dismissed gap" \
    || no "the dismissed NOT-FOR-US gap was raised again"
  n6="$(count_domain "$A6/run2")"
  [ "$n6" -ge 1 ] \
    && ok "the second run still emitted $n6 other gap file(s) - the suppression is targeted, not a dead run" \
    || no "the second run emitted nothing at all; 'it did not re-emit' would prove nothing"
  grep -Fq 'suppressed' "$LOGERR" 2>/dev/null \
    && ok "the suppression is reported rather than silent" || no "the suppression was silent"
  grep -Fq "$DONE6" "$LOGERR" 2>/dev/null \
    && ok "the report NAMES the file that caused it: $DONE6" \
    || no "the suppression report does not name the file that caused it:
$(grep -i suppress "$LOGERR" 2>/dev/null)"

  echo "-- MUTATION CONTROL: delete the done-supersession check and AC6 must go RED --"
  MUT6="$MUTDIR/mutant-nosupersede.sh"
  sed '/>>> DONE-SUPERSESSION CHECK/,/<<< END DONE-SUPERSESSION CHECK/d' "$SUT" > "$MUT6" 2>/dev/null
  if [ -s "$MUT6" ] && ! cmp -s "$MUT6" "$SUT" && bash -n "$MUT6" 2>/dev/null; then
    ok "built a syntactically valid mutant with the done-supersession check deleted"
    reset_domain
    D_PROJ="$PROJ"; D_OUT="$A6/run3"; D_REQ="$A6R"; D_SCRIPT="$MUT6"
    run_domain >/dev/null 2>&1
    m6="$(count_domain "$A6/run3")"
    if [ "$m6" -eq 0 ]; then
      no "the mutant emitted NOTHING at all, so 'it did not re-emit the gap' is a fact about a dead run - the AC6 control is inconclusive
$(cat "$LOGERR" 2>/dev/null)"
    else
      [ -f "$A6/run3/domain--card-data-vaulting.md" ] \
        && ok "MUTATION CONTROL: without the check the dismissed gap IS raised again (mutant emitted $m6 file(s)) - AC6's assertion genuinely can fail" \
        || no "the mutant emitted $m6 file(s) but still suppressed this one - AC6 passes with the mechanism deleted and proves nothing"
    fi
  else
    no "could not build a valid supersession mutant - AC6 is uncontrolled"
  fi
fi

echo
echo "== AC7: the fetch cap - exactly one external call, and partial coverage names the rest =="
A7="$(mktmp)"
: > "$A7/calls.txt"
store_comps="$(jq -r '.competitors | length' "$FIX/product.json" 2>/dev/null)"
[ "${store_comps:-0}" -ge 3 ] \
  && ok "the fixture store records $store_comps competitors, so a cap of 1 must leave $((store_comps - 1)) unreached" \
  || no "the fixture store records only ${store_comps:-0} competitor(s) - a cap of 1 would prove little"
reset_domain
D_PROJ="$PROJ"; D_OUT="$A7/out"; D_REQ="$A7/req"; D_CALLS="$A7/calls.txt"; D_MAXF=1
run_domain; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0 under a fetch cap of 1" || no "exit $rc under a fetch cap of 1"
c7="$(lines "$A7/calls.txt")"
[ "$c7" -eq 1 ] \
  && ok "EXACTLY ONE external call was made, observed in the stub's own call log: $(cat "$A7/calls.txt")" \
  || no "the stub recorded $c7 call(s) under a cap of 1:
$(cat "$A7/calls.txt")"
n7="$(count_domain "$A7/out")"
[ "$n7" -ge 1 ] && ok "the capped run still emitted $n7 gap file(s) from the one source it reached" \
  || no "the capped run emitted nothing - the coverage assertions below would be vacuous"
F7="$(find "$A7/out" -maxdepth 1 -type f -name 'domain--*.md' 2>/dev/null | LC_ALL=C sort | awk 'NR==1{print}')"
if [ -n "$F7" ] && [ -f "$F7" ]; then
  grep -Fq -- '- coverage: partial' "$F7" 2>/dev/null \
    && ok "the emitted file reports coverage as PARTIAL" || no "the emitted file does not report partial coverage"
  miss7=0
  for name in "Bolt Knowledge" "Cursive Wiki"; do
    grep -Fq "$name" "$F7" 2>/dev/null || { miss7=1; echo "     '$name' is not named as unreached"; }
  done
  [ "$miss7" -eq 0 ] \
    && ok "the file NAMES what was not reached (Bolt Knowledge, Cursive Wiki) rather than only counting it" \
    || no "the file does not name every unreached source"
  grep -Fq -- '- not reached, by name:' "$F7" 2>/dev/null \
    && ok "the Coverage section lists the unreached sources by name" || no "the Coverage section does not list unreached sources by name"
fi
grep -Fq 'external calls made: 1 of a cap of 1' "$LOGERR" 2>/dev/null \
  && ok "the run reports its own call count against the cap on stderr" \
  || no "the run does not report 1 call against a cap of 1:
$(grep -i 'external calls' "$LOGERR" 2>/dev/null)"

echo
echo "== AC8: STALE is named; and a never-fetched source is never a date and never stale =="
# Arm 1 - the deliberately-old source. Its recorded date is read from the store, not restated.
BOLT_LF="$(jq -r '.competitors[] | select(.name == "Bolt Knowledge") | .last_fetched' "$FIX/product.json" 2>/dev/null)"
[ -n "$BOLT_LF" ] && [ "$BOLT_LF" != "null" ] \
  && ok "the store records a real, deliberately-old fetch date for Bolt Knowledge ($BOLT_LF)" \
  || no "the store records no usable old date - AC8's stale arm has no subject"
F8="$A3O/domain--two-factor-authentication.md"
if [ -f "$F8" ]; then
  s8="$(grep -m1 '^- Bolt Knowledge - url: ' "$F8" 2>/dev/null)"
  case "$s8" in
    *STALE*) ok "the old source is NAMED as STALE rather than cited silently: $s8" ;;
    "")      no "the file that cites the old source does not carry a Bolt Knowledge citation line" ;;
    *)       no "the old source is cited with no staleness marker: $s8" ;;
  esac
  case "$s8" in
    *"$BOLT_LF"*) ok "the stale citation still carries its recorded date ($BOLT_LF), so the reader can judge it" ;;
    *) no "the stale citation does not carry the date the store recorded" ;;
  esac
else
  no "no gap file citing the old source was emitted - AC8's stale arm cannot be evaluated"
fi
# Arm 2 - unknown is not old. A `null` last_fetched is a COMPLETE record, and must render as
# its own thing: never as a date, and never as stale.
CURS_LF="$(jq -r '.competitors[] | select(.name == "Cursive Wiki") | (.last_fetched // "null")' "$FIX/product.json" 2>/dev/null)"
[ "$CURS_LF" = "null" ] \
  && ok "the store records a null last_fetched for Cursive Wiki - the never-fetched case has a subject" \
  || no "Cursive Wiki's last_fetched is '$CURS_LF', not null - AC8's never-fetched arm has no subject"
if [ -f "$F4" ]; then
  nf8="$(grep -m1 '^- Cursive Wiki - url: ' "$F4" 2>/dev/null)"
  if [ -z "$nf8" ]; then
    no "the never-fetched source is cited in no emitted gap file - the never-fetched rendering is UNREACHABLE and this arm would be vacuous"
  else
    ok "the never-fetched source is actually cited, so the rendering under test is genuinely produced: $nf8"
    case "$nf8" in
      *"never fetched"*) ok "it renders as NEVER FETCHED" ;;
      *) no "it does not render as never fetched: $nf8" ;;
    esac
    case "$nf8" in
      *STALE*) no "a never-fetched source is reported STALE - unknown is not old" ;;
      *) ok "it is NOT reported stale - unknown is not old" ;;
    esac
    if printf '%s\n' "$nf8" > "$ROOT/nf.line" && grep -Eq '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' "$ROOT/nf.line" 2>/dev/null; then
      no "a never-fetched source is rendered with a date-shaped string: $nf8"
    else
      ok "it is NEVER rendered as a date - there is no date-shaped text on that line"
    fi
  fi
  grep -Fq 'STALE' "$F4" 2>/dev/null \
    && no "the never-fetched file carries a STALE marker somewhere: $(grep -m1 STALE "$F4")" \
    || ok "nothing anywhere in that file is marked STALE (its other source is fresh)"
  # POSITIVE CONTROL: the STALE marker must be capable of appearing at all, or its absence
  # above is a fact about the harness rather than about the never-fetched rule.
  if [ -f "$F8" ]; then
    grep -Fq 'STALE' "$F8" 2>/dev/null \
      && ok "POSITIVE CONTROL: the same marker DOES appear in the file citing the old source" \
      || no "POSITIVE CONTROL FAILED: no emitted file carries a STALE marker, so its absence proves nothing"
  fi
else
  no "no gap file citing the never-fetched source - AC8's second arm cannot be evaluated"
fi

echo
echo "== AC9: namespacing - both bases into ONE directory, neither overwriting the other =="
A9="$(mktmp)"; SHARED="$A9/proposed"; mkdir -p "$SHARED"
( cd "$PROJ" && PROPOSE_FLOOR_JSON="$A1/floor.json" PROPOSE_OUT_DIR="$SHARED" PROPOSE_REQUIREMENTS_DIR="$A9/req" \
    bash "$LEDGER_SUT" ) >/dev/null 2>&1
( cd "$SHARED" && find . -maxdepth 1 -type f -name '*.md' | LC_ALL=C sort ) > "$A9/ledger.names"
nl9="$(lines "$A9/ledger.names")"
[ "$nl9" -ge 1 ] && ok "the ledger basis wrote $nl9 file(s) into the shared directory" \
  || no "the ledger basis wrote nothing - AC9 has only one basis to compare"
: > "$A9/ledger.sums"
while IFS= read -r p; do [ -n "$p" ] && printf '%s  %s\n' "$(csum "$SHARED/$p")" "$p" >> "$A9/ledger.sums"; done < "$A9/ledger.names"
lns9=0
while IFS= read -r p; do
  case "${p#./}" in domain--*) lns9=$((lns9+1)) ;; esac
done < "$A9/ledger.names"
[ "$lns9" -eq 0 ] && ok "no ledger-basis filename is namespaced domain--*, so the two namespaces are genuinely disjoint" \
  || no "$lns9 ledger-basis file(s) already use the domain-- namespace"

reset_domain
D_PROJ="$PROJ"; D_OUT="$SHARED"; D_REQ="$A9/req"
run_domain >/dev/null 2>&1
( cd "$SHARED" && find . -maxdepth 1 -type f -name '*.md' | LC_ALL=C sort ) > "$A9/after.names"
comm -13 "$A9/ledger.names" "$A9/after.names" > "$A9/new.names"
nn9="$(lines "$A9/new.names")"
[ "$nn9" -ge 1 ] && ok "the domain basis added $nn9 new file(s) to the same directory" \
  || no "the domain basis added nothing to the shared directory - AC9 is vacuous"
bad9=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  case "${p#./}" in domain--*.md) : ;; *) bad9=$((bad9+1)); echo "     not namespaced: $p" ;; esac
done < "$A9/new.names"
[ "$bad9" -eq 0 ] && ok "EVERY domain candidate is named domain--<slug>.md" \
  || no "$bad9 domain candidate(s) are not namespaced"
: > "$A9/ledger.sums.after"
while IFS= read -r p; do [ -n "$p" ] && printf '%s  %s\n' "$(csum "$SHARED/$p")" "$p" >> "$A9/ledger.sums.after"; done < "$A9/ledger.names"
cmp -s "$A9/ledger.sums" "$A9/ledger.sums.after" \
  && ok "the domain basis overwrote none of the ledger basis's files (byte-identical after the run)" \
  || no "the domain basis modified a ledger-basis file:
$(diff "$A9/ledger.sums" "$A9/ledger.sums.after")"
# ...and the other direction, or "neither overwrote the other" is only half-checked.
: > "$A9/domain.sums"
while IFS= read -r p; do [ -n "$p" ] && printf '%s  %s\n' "$(csum "$SHARED/$p")" "$p" >> "$A9/domain.sums"; done < "$A9/new.names"
( cd "$PROJ" && PROPOSE_FLOOR_JSON="$A1/floor.json" PROPOSE_OUT_DIR="$SHARED" PROPOSE_REQUIREMENTS_DIR="$A9/req" \
    bash "$LEDGER_SUT" ) >/dev/null 2>&1
: > "$A9/domain.sums.after"
while IFS= read -r p; do [ -n "$p" ] && printf '%s  %s\n' "$(csum "$SHARED/$p")" "$p" >> "$A9/domain.sums.after"; done < "$A9/new.names"
cmp -s "$A9/domain.sums" "$A9/domain.sums.after" \
  && ok "a second ledger-basis run overwrote none of the domain basis's files either" \
  || no "the ledger basis modified a domain-basis file:
$(diff "$A9/domain.sums" "$A9/domain.sums.after")"

echo
echo "== AC10: blast radius, hashed on the FILESYSTEM tree - never on a git reading =="
# Directories and symlinks are in scope: `-type f` alone would make a stray directory or a
# symlink dropped outside the output dir invisible, and a symlink is the cheapest way out of a
# directory allow-list.
hash_set() {
  ( cd "$1" 2>/dev/null || return 1
    find . \( -type f -o -type l -o -type d \) \
        -not -path './.git' -not -path './.git/*' \
        -not -path './.supervisor/requirements/proposed' \
        -not -path './.supervisor/requirements/proposed/*' \
        -print | LC_ALL=C sort \
      | while IFS= read -r p; do
          if [ -f "$p" ] && [ ! -L "$p" ]; then printf '%s  %s\n' "$(csum "$p")" "$p"
          else printf 'DIRLINK  %s\n' "$p"; fi
        done )
}
RK="$(new_project "$FIX/product.json")"
[ -d "$RK/.git" ] && ok "built a second throwaway git repo for the containment run" || no "could not build the containment fixture repo"
# Demonstrate WHY a git reading is unusable here rather than merely asserting it.
mkdir -p "$RK/.supervisor/requirements/proposed"
printf 'probe\n' > "$RK/.supervisor/git-blindness-probe.md"
gsp="$( cd "$RK" && git status --porcelain 2>/dev/null | grep -c 'git-blindness-probe' )"
[ "$gsp" -eq 0 ] \
  && ok "measured: a write under the ignored .supervisor/ is INVISIBLE to git status --porcelain - a git-tracked-tree reading would be vacuous here" \
  || no "git status reported the ignored probe ($gsp hits) - re-check the premise"
rm -f "$RK/.supervisor/git-blindness-probe.md"

before10="$(hash_set "$RK")"
nb10="$(printf '%s\n' "$before10" | awk 'NF{n++} END{print n+0}')"
[ "$nb10" -ge 5 ] && ok "pre-run tree hash is non-empty ($nb10 paths) - the containment assertion is not vacuous" \
  || no "pre-run tree hash has only $nb10 paths"
reset_domain
D_PROJ="$RK"        # no OUT_DIR / REQ_DIR / STORE overrides: the DEFAULTS are what is under test
run_domain; rc=$?
after10="$(hash_set "$RK")"
[ "$rc" -eq 0 ] && ok "the containment run exited 0" || no "the containment run exited $rc"
n10="$(count_domain "$RK/.supervisor/requirements/proposed")"
[ "$n10" -ge 1 ] \
  && ok "the containment run actually emitted $n10 candidate(s) into the DEFAULT output dir - 'the tree did not change' now means something" \
  || no "the containment run emitted nothing
$(cat "$LOGERR" 2>/dev/null)"
[ "$before10" = "$after10" ] \
  && ok "no path outside .supervisor/requirements/proposed/ was created, modified or removed" \
  || no "the tree outside the output dir changed:
$(diff <(printf '%s\n' "$before10") <(printf '%s\n' "$after10"))"

echo "-- MUTATION CONTROL: delete the write-path guard and a real stray write must land --"
# The hostile input cannot come from the store here (slugs are the script's own catalogue), so
# it is injected the same way the sibling test injects a traversal class name: one catalogue
# slug is rewritten to a path, and the output directory holds a symlink out of itself - the
# realistic escape, and the reason hash_set counts symlinks at all. The INTACT script must
# refuse it; only the guard-deleted mutant may escape.
HOST10="$MUTDIR/hostile-slug.sh"
sed 's#^audit-log|#x/stray-propose-domain|#' "$SUT" > "$HOST10" 2>/dev/null
if [ -s "$HOST10" ] && ! cmp -s "$HOST10" "$SUT" && bash -n "$HOST10" 2>/dev/null; then
  ok "built a hostile variant whose catalogue slug is a path rather than a plain name"
  RK2="$(new_project "$FIX/product.json")"
  mkdir -p "$RK2/.supervisor/requirements/proposed"
  ln -s "$RK2" "$RK2/.supervisor/requirements/proposed/domain--x" 2>/dev/null
  [ -L "$RK2/.supervisor/requirements/proposed/domain--x" ] \
    && ok "planted a symlink out of the output directory - the cheapest way past a directory allow-list" \
    || no "could not plant the escape symlink - the AC10 control is inconclusive"
  b2="$(hash_set "$RK2")"
  reset_domain
  D_PROJ="$RK2"; D_SCRIPT="$HOST10"
  run_domain; rc=$?
  a2="$(hash_set "$RK2")"
  [ "$rc" -eq 0 ] && ok "hostile input: the intact script still exits 0" || no "hostile input: exit $rc"
  [ "$b2" = "$a2" ] && ok "hostile input: the intact script wrote nothing outside the output dir" \
    || no "hostile input: the intact script escaped its output dir:
$(diff <(printf '%s\n' "$b2") <(printf '%s\n' "$a2"))"
  grep -Fq 'refusing to write' "$LOGERR" 2>/dev/null \
    && ok "hostile input: the refusal is NAMED rather than dropped silently" \
    || no "hostile input: the candidate was skipped without naming why:
$(cat "$LOGERR" 2>/dev/null)"

  MUT10="$MUTDIR/mutant-noguard.sh"
  sed '/>>> WRITE-PATH GUARD/,/<<< END WRITE-PATH GUARD/d' "$HOST10" > "$MUT10" 2>/dev/null
  if [ -s "$MUT10" ] && ! cmp -s "$MUT10" "$HOST10" && bash -n "$MUT10" 2>/dev/null; then
    ok "built a syntactically valid mutant with the write-path guard deleted"
    RK3="$(new_project "$FIX/product.json")"
    mkdir -p "$RK3/.supervisor/requirements/proposed"
    ln -s "$RK3" "$RK3/.supervisor/requirements/proposed/domain--x" 2>/dev/null
    b3="$(hash_set "$RK3")"
    reset_domain
    D_PROJ="$RK3"; D_SCRIPT="$MUT10"
    run_domain; mrc=$?
    a3="$(hash_set "$RK3")"
    m10="$(count_domain "$RK3/.supervisor/requirements/proposed")"
    [ "$m10" -ge 1 ] \
      && ok "the guard-deleted mutant still did its ordinary work ($m10 in-lane candidate(s)), so it is a live run and not a skip" \
      || no "the guard-deleted mutant emitted nothing in-lane - it never reached the write path and the control below is inconclusive
$(cat "$LOGERR" 2>/dev/null)"
    if [ "$b3" != "$a3" ]; then
      ok "MUTATION CONTROL: without the guard a write lands OUTSIDE the output dir (mutant rc=$mrc) - AC10 turns RED"
      stray="$(diff <(printf '%s\n' "$b3") <(printf '%s\n' "$a3") | sed -n 's/^> .*  //p' | awk 'NR==1{print}')"
      [ -n "$stray" ] && ok "the stray path the mutant created is named: $stray" || no "could not name the stray path"
      [ -f "$RK3/stray-propose-domain.md" ] \
        && ok "and it is a REAL file on disk outside the output directory, not merely a hash difference" \
        || no "the tree changed but the expected stray file is not there - the control is inconclusive"
    else
      no "the guard-deleted mutant left the tree unchanged - AC10 passes with the mechanism deleted and proves nothing
$(cat "$LOGERR" 2>/dev/null)"
    fi
  else
    no "could not build a valid write-guard mutant - AC10 is uncontrolled"
  fi
else
  no "could not build a valid hostile-slug variant - AC10 is uncontrolled"
fi

echo
echo "== AC11: no score, rank, priority, top-N or ordering field in any emitted file =="
n11="$(count_domain "$A3O")"
[ "$n11" -ge 1 ] && ok "AC11 runs against $n11 emitted file(s), not an empty directory" \
  || no "AC11 has no emitted files to grep - it would pass vacuously"
# FIELD-SHAPED, deliberately. The one place an emitted file legitimately contains "priorit" is
# inside the stance default action `build-highest-priority`, read verbatim from read-product.sh;
# a bare word grep would fire on that and be "fixed" by re-deriving the mapping locally, which
# is exactly what AC5 forbids.
FIELD_RE='^[[:space:]]*-?[[:space:]]*(score|scoring|rank|ranking|priority|priorities|order|ordering|weight|weighting|top-?[0-9]+)[[:space:]]*:'
hits11=0
for f in "$A3O"/domain--*.md; do
  [ -f "$f" ] || continue
  if grep -EqiI "$FIELD_RE" "$f" 2>/dev/null; then
    hits11=$((hits11+1))
    echo "     ranking-shaped field in $(basename "$f"): $(grep -EiI -m1 "$FIELD_RE" "$f")"
  fi
done
[ "$hits11" -eq 0 ] && ok "no emitted file carries a score, rank, priority, order, weight or top-N FIELD" \
  || no "$hits11 emitted file(s) carry a ranking-shaped field"
# Belt to that brace: a word-level sweep, with the one legitimate occurrence removed first.
# If ranking language creeps in anywhere else in the prose, this fires.
words11=0
for f in "$A3O"/domain--*.md; do
  [ -f "$f" ] || continue
  sed -e 's/build-highest-priority//g' "$f" > "$ROOT/stripped.md"
  if grep -EqiI '(^|[^a-z])(scor(e|ed|ing)|rank(ed|ing)?|priorit(y|ies|ised|ized)|top-?[0-9]+|ordering|weight(ed|ing)?)([^a-z]|$)' "$ROOT/stripped.md" 2>/dev/null; then
    words11=$((words11+1))
    echo "     ranking-shaped prose in $(basename "$f"): $(grep -EiI -m1 '(scor|rank|priorit|top-?[0-9]|ordering|weight)' "$ROOT/stripped.md")"
  fi
done
[ "$words11" -eq 0 ] \
  && ok "and once the stance action is set aside, no emitted file contains ranking language at all" \
  || no "$words11 emitted file(s) contain ranking language outside the stance default action"
# POSITIVE CONTROL: an assertion that never fires is not an assertion.
SPIKE="$ROOT/ranking-spike.md"
cp "$A3O/domain--audit-log.md" "$SPIKE" 2>/dev/null
printf -- '- priority: 2\n' >> "$SPIKE"
grep -EqiI "$FIELD_RE" "$SPIKE" 2>/dev/null \
  && ok "POSITIVE CONTROL: the same field-shaped grep DOES fire on an emitted file with a priority field appended" \
  || no "POSITIVE CONTROL FAILED: the AC11 grep cannot fire at all, so its silence means nothing"
# ...and the control must not be satisfied by the stance action alone, or it proves the wrong thing.
SPIKE2="$ROOT/ranking-spike-clean.md"
cp "$A3O/domain--audit-log.md" "$SPIKE2" 2>/dev/null
grep -EqiI "$FIELD_RE" "$SPIKE2" 2>/dev/null \
  && no "the unmodified copy also fires - the positive control above is measuring the stance action, not a planted field" \
  || ok "the unmodified copy does NOT fire, so the control is measuring the planted field and nothing else"

echo
echo "== AC12: determinism - two independent runs into two separate EMPTY dirs =="
A12="$(mktmp)"
mkdir -p "$A12/run1" "$A12/run2"
[ "$(count_md "$A12/run1")" -eq 0 ] && [ "$(count_md "$A12/run2")" -eq 0 ] \
  && ok "both output directories start empty, so neither run can be reading the other's work" \
  || no "an output directory was not empty at the start"
reset_domain
D_PROJ="$PROJ"; D_OUT="$A12/run1"; D_REQ="$A12/req1"
run_domain >/dev/null 2>&1
reset_domain
D_PROJ="$PROJ"; D_OUT="$A12/run2"; D_REQ="$A12/req2"
run_domain >/dev/null 2>&1
d1="$(count_domain "$A12/run1")"; d2="$(count_domain "$A12/run2")"
[ "$d1" -ge 1 ] && [ "$d1" -eq "$d2" ] \
  && ok "both runs emitted the same $d1 file(s) - a byte comparison over an empty pair would prove nothing" \
  || no "the two runs emitted $d1 and $d2 file(s)"
if diff -r "$A12/run1" "$A12/run2" >"$ROOT/det.diff" 2>&1; then
  ok "the two runs are BYTE-FOR-BYTE identical - no clock, no run id and no path of the moment reaches an emitted byte"
else
  no "the two runs differ:
$(head -30 "$ROOT/det.diff")"
fi

echo
echo "propose-domain: $pass passed, $fail failed, $skip skipped"
[ "$fail" -eq 0 ] || exit 1
exit 0
