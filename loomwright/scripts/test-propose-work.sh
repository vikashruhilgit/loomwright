#!/usr/bin/env bash
# test-propose-work.sh - self-tests for propose-work.sh, the advisory findings->proposals reader.
#
# HERMETIC BY CONSTRUCTION, and that is the load-bearing property of this file. `.gitignore`
# ignores `.supervisor/*`, so the script's ONLY input - `.supervisor/floor/floor.json` - is
# absent from every fresh clone and from every CI runner, while `loomwright/scripts/test-*.sh`
# IS auto-globbed by `.github/workflows/ci.yml` and gated on. A test driven off the real
# `.supervisor/` would therefore exercise nothing but the fail-safe skip path and go SILENTLY
# GREEN. Every assertion below runs against the COMMITTED fixtures in
# `fixtures/propose-work/`, restamped fresh at test time. The real-`floor.json` run at the end
# is a LOCAL-ONLY corroboration with THREE outcomes (assert / stale-skip / absent-skip), and
# its skips are reported separately - never counted as passes.
#
# THE HARNESS ITSELF HARD-FAILS IF jq IS MISSING. Only the script under test may skip on a
# missing jq; a harness that skipped too would turn AC1a into the same silent CI pass that
# AC1b was split off to prevent.
#
# Cases (one per acceptance criterion, plus the mutation controls each one needs):
#   AC1a hermetic emission from the golden fixture; every count quoted inside the proposal is
#        independently recomputed from the fixture, including every cited ledger coordinate
#   AC1b live `.supervisor/floor/floor.json` - present+fresh asserts, present+stale skips
#        loudly naming the age, absent skips loudly naming the absence
#   AC2  the `## Evidence` section, parsed OUT OF THE EMITTED FILE, never read off the script
#   AC3  below-threshold class not emitted and NAMED, with an above-threshold sibling that IS
#        emitted (the positive control proving the run could emit at all), plus the
#        clears-threshold-but-uncitable arm (absent evidence is omitted, never defaulted)
#   AC4a a second run into a populated dir emits nothing new and reports the suppression
#   AC4b a `## Status: done` requirement file supersedes the candidate, with a MUTATION CONTROL
#        that deletes the supersession check and asserts this case then FAILS
#   AC5  a stale basis proposes nothing, names the age, exits 0 - with a mutation control
#   AC6  jq absent / basis missing / basis malformed - each names its reason and exits 0, with
#        a mutation control on the malformed arm
#   AC7  determinism: two INDEPENDENT runs into two SEPARATE EMPTY dirs, byte-for-byte; plus
#        the discriminating permutation control and a sort-deleted MUTATION CONTROL
#   AC8  blast radius: the FILESYSTEM tree (not a git reading) outside proposed/ is unchanged,
#        with a proof that a git reading would be vacuous and a guard-deleted MUTATION CONTROL
#        that plants a real stray write
#   AC9  no score/rank/priority/ordering field in any emitted proposal, on a run that emitted
#        >=1 proposal, with a positive control proving the grep can fire
#   AC10 the emitted README states the directory contract, and the SAME sentence is present in
#        propose-work.sh's committed header (the README is a gitignored runtime artefact)
#
# EVERY temp tree is materialised OUTSIDE the repo root via mktemp -d. Staging a fixture
# anywhere under the repo would make AC8 fail on this test's own scratch files.
#
# Local traps this file deliberately avoids, each of which silently makes an assertion vacuous
# while everything stays green:
#   * `producer | grep -q` returns 141 under `pipefail` EVEN ON A MATCH - so `grep -q` is only
#     ever run directly against a FILE here, never as the right-hand side of a pipe. (The one
#     pipe into grep, the git-blindness probe below, uses `grep -c`, which drains stdin and so
#     cannot SIGPIPE, and its status is discarded by the assignment anyway.)
#   * `local x="$(...)"` discards the command's exit status - assignment and status check are
#     always separate statements below.
#   * `... || echo 0` APPENDS a second line rather than replacing - counts come from awk END.
#
# Exit 0 = all pass, 1 = any failure. Registered automatically by ci.yml's test-*.sh glob.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/propose-work.sh"
FIX="$HERE/fixtures/propose-work"
GOLD="$FIX/floor-golden.json"
GOLD_PERM="$FIX/floor-golden-permuted.json"
BELOW="$FIX/floor-below-threshold.json"
STALE="$FIX/floor-stale.json"
MALFORMED="$FIX/floor-malformed.json"
DONE_FIX="$FIX/done-requirement.md"

pass=0; fail=0; skip=0
ok()   { echo "  ok: $1";       pass=$((pass+1)); }
no()   { echo "  FAIL: $1";     fail=$((fail+1)); }
skipn(){ echo "  SKIPPED - $1"; skip=$((skip+1)); }

# The harness's own hard preconditions. These are NOT skips.
if ! command -v jq >/dev/null 2>&1; then
  echo "FATAL: jq is not on PATH - the harness itself requires it to recompute every"
  echo "       expectation independently of the script under test. Only propose-work.sh"
  echo "       may skip on a missing jq; this file may not."
  exit 1
fi
for f in "$SUT" "$GOLD" "$GOLD_PERM" "$BELOW" "$STALE" "$MALFORMED" "$DONE_FIX"; do
  [ -f "$f" ] || { echo "FATAL: required fixture or script missing: $f"; exit 1; }
done

ROOT="$(mktemp -d)"   # OUTSIDE the repo root, deliberately - see the header note on AC8.
trap 'chmod -R u+rwX "$ROOT" >/dev/null 2>&1; rm -rf "$ROOT" 2>/dev/null' EXIT
mktmp() { mktemp -d "$ROOT/d.XXXXXX"; }

LOGOUT="$ROOT/last.out"
LOGERR="$ROOT/last.err"

NOW="$(date -u +%s)"
case "$NOW" in ''|*[!0-9]*) echo "FATAL: could not read the clock"; exit 1 ;; esac

# Restamp a committed fixture fresh relative to the 24h staleness threshold AT TEST TIME.
# Baking an absolute epoch into the fixture would age it into staleness and turn every
# emission case into a silent no-op some time after the commit that added it.
fresh_basis() {
  jq --argjson n "$NOW" '.generated_at_epoch = $n' "$1" > "$2" 2>/dev/null
}

# run_sut <floor> <outdir> <reqdir> [script] [cwd]
run_sut() {
  rs_scr="${4:-$SUT}"; rs_cwd="${5:-$ROOT}"
  ( cd "$rs_cwd" && PROPOSE_FLOOR_JSON="$1" PROPOSE_OUT_DIR="$2" PROPOSE_REQUIREMENTS_DIR="$3" \
      bash "$rs_scr" ) >"$LOGOUT" 2>"$LOGERR"
  return $?
}

# Proposals only - the directory-contract README is not a proposal.
count_props() {
  find "$1" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' 2>/dev/null \
    | awk 'END{print NR+0}'
}

csum() {
  if   command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" 2>/dev/null | cut -d' ' -f1
  elif command -v shasum    >/dev/null 2>&1; then shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
  else cksum "$1" 2>/dev/null | cut -d' ' -f1; fi
}

echo "== AC1a: hermetic emission from the committed golden fixture =="
G="$(mktmp)"; GJ="$G/floor.json"; GO="$G/out"; GR="$G/req"
fresh_basis "$GOLD" "$GJ"
[ -s "$GJ" ] && ok "golden fixture restamped fresh (generated_at_epoch = $NOW)" \
  || no "could not restamp the golden fixture - every emission case below is inconclusive"
run_sut "$GJ" "$GO" "$GR"; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0 on the golden fixture" || no "exit $rc on the golden fixture"

PROP="$GO/convention_mismatch--worker.md"
if [ -f "$PROP" ]; then
  ok "a convention_mismatch proposal was emitted ($(count_props "$GO") proposals in total)"
else
  no "no convention_mismatch/worker proposal emitted - AC1a/AC2/AC7/AC9 are all inconclusive
$(cat "$LOGERR" 2>/dev/null)"
fi
np="$(count_props "$GO")"
[ "$np" -ge 1 ] && ok "the run emitted a NON-EMPTY set of proposals ($np) - assertions below are not vacuous" \
  || no "the run emitted zero proposals; an assertion over an empty set proves nothing"

# Every count quoted inside the proposal, recomputed here from the fixture. Nothing is read
# back out of the script's own output and compared to itself.
EXP_PAIR="$(jq -r '[.surfaces.postmortem.detail.entries[]|select(.class=="convention_mismatch" and .flow_stage=="worker")]|length' "$GJ")"
EXP_CLASS="$(jq -r '[.surfaces.postmortem.detail.entries[]|select(.class=="convention_mismatch")]|length' "$GJ")"
EXP_TOTAL="$(jq -r '.surfaces.postmortem.detail.entries|length' "$GJ")"
EXP_MTIME="$(jq -r '.surfaces.postmortem.mtime_epoch' "$GJ")"
EXP_SRC="$(jq -r '.surfaces.postmortem.source' "$GJ")"

if [ -f "$PROP" ]; then
  for probe in \
    "- pair entries: $EXP_PAIR (emission threshold 10)" \
    "- entries in class \`convention_mismatch\`: $EXP_CLASS" \
    "- classified entries in the ledger: $EXP_TOTAL" \
    "- ledger mtime_epoch: $EXP_MTIME" \
    "- ledger: \`$EXP_SRC\`" \
    "generated_at_epoch: $NOW"
  do
    if grep -Fq -- "$probe" "$PROP" 2>/dev/null; then
      ok "recomputed and matched in the proposal: '$probe'"
    else
      no "the proposal does not carry the independently recomputed value: '$probe'"
    fi
  done

  # The citation coordinates are counts too. Each one must name a ledger entry that really
  # exists in the fixture with exactly those class/flow_stage/round/line/index values - a
  # citation that resolves to nothing is a fabricated one.
  cites="$(awk -F' - ' '/^- class `/ {
      split($3,a," "); split($4,b," "); split($5,c," ");
      printf "%s %s %s\n", a[2], b[2], c[2] }' "$PROP")"
  ncite=0; bad=0
  while read -r rd ln ix; do
    [ -n "${rd:-}" ] || continue
    ncite=$((ncite+1))
    hits="$(jq -r --argjson ln "$ln" --argjson ix "$ix" --argjson rd "$rd" \
      '[.surfaces.postmortem.detail.entries[]
        | select(.class=="convention_mismatch" and .flow_stage=="worker"
                 and .line==$ln and ((.index//0))==$ix and .round==$rd)] | length' "$GJ" 2>/dev/null)"
    case "$hits" in ''|0|*[!0-9]*) bad=$((bad+1)); echo "     unresolvable citation: round $rd line $ln index $ix" ;; esac
  done <<EOF
$cites
EOF
  [ "$ncite" -ge 3 ] && ok "the proposal cites $ncite ledger entries" \
    || no "the proposal cites only $ncite entries"
  [ "$bad" -eq 0 ] && ok "every cited coordinate resolves to a real entry in the fixture" \
    || no "$bad cited coordinate(s) resolve to no entry in the fixture"

  # The evidence STRING travels with the citation and is not paraphrased.
  first_ev="$(jq -r '[.surfaces.postmortem.detail.entries[]
      | select(.class=="convention_mismatch" and .flow_stage=="worker")]
      | sort_by([.line,(.index//0)]) | .[0].evidence' "$GJ")"
  if grep -Fq -- "  - evidence: $first_ev" "$PROP" 2>/dev/null; then
    ok "the first cited entry's evidence string is reproduced verbatim"
  else
    no "the evidence string of the first cited entry is not reproduced verbatim"
  fi
fi

echo "== AC2: the ## Evidence section, parsed out of the EMITTED FILE =="
for f in "$GO"/*.md; do
  [ -f "$f" ] || continue
  case "$(basename "$f")" in README.md) continue ;; esac
  b="$(basename "$f")"
  grep -q '^## Evidence$' "$f" 2>/dev/null \
    && ok "$b carries a ## Evidence section" || no "$b has no ## Evidence section"
  n="$(awk '/^## Evidence$/{e=1} e && /^- class `/{c++} END{print c+0}' "$f")"
  [ "$n" -ge 3 ] && ok "$b cites $n distinct ledger entries (>= 3)" \
    || no "$b cites only $n ledger entries"
  nfield="$(awk -F' - ' '/^- class `/ && $2 ~ /^flow_stage / && $3 ~ /^round / && $4 ~ /^line /{c++} END{print c+0}' "$f")"
  [ "$nfield" -eq "$n" ] && ok "$b: all $n citations carry class, flow_stage, round and line" \
    || no "$b: only $nfield of $n citations carry the full coordinate set"
  nev="$(awk '/^  - evidence: ..*$/{c++} END{print c+0}' "$f")"
  [ "$nev" -eq "$n" ] && ok "$b: all $n citations carry a non-empty evidence string" \
    || no "$b: $nev non-empty evidence strings for $n citations"
  grep -Fq "generated_at_epoch: $NOW" "$f" 2>/dev/null \
    && ok "$b names the generated_at_epoch it read" || no "$b does not name the generated_at_epoch it read"
done

echo "== AC3: below threshold is named and NOT emitted; a sibling above it IS (positive control) =="
B="$(mktmp)"; BJ="$B/floor.json"; BO="$B/out"; BR="$B/req"
fresh_basis "$BELOW" "$BJ"
EXP_X="$(jq -r '[.surfaces.postmortem.detail.entries[]|select(.class=="plan_gap" and .flow_stage=="worker")]|length' "$BJ")"
EXP_Y="$(jq -r '[.surfaces.postmortem.detail.entries[]|select(.class=="quality_gap" and .flow_stage=="worker")]|length' "$BJ")"
EXP_Z="$(jq -r '[.surfaces.postmortem.detail.entries[]|select(.class=="execution_bug" and .flow_stage=="worker")]|length' "$BJ")"
EXP_Z_CITABLE="$(jq -r '[.surfaces.postmortem.detail.entries[]|select(.class=="execution_bug" and .flow_stage=="worker" and (.evidence|type)=="string")]|length' "$BJ")"
run_sut "$BJ" "$BO" "$BR"; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0 on the below-threshold fixture" || no "exit $rc on the below-threshold fixture"
[ ! -f "$BO/plan_gap--worker.md" ] \
  && ok "class X (plan_gap/worker, $EXP_X entries) was NOT proposed" \
  || no "plan_gap/worker was proposed despite being below the threshold"
# POSITIVE CONTROL: without this, "X was not emitted" is satisfied by a run that emitted nothing.
[ -f "$BO/quality_gap--worker.md" ] \
  && ok "POSITIVE CONTROL: sibling class Y (quality_gap/worker, $EXP_Y entries) WAS proposed - the run was capable of emitting" \
  || no "POSITIVE CONTROL FAILED: the above-threshold sibling was not emitted either, so 'X not emitted' proves nothing
$(cat "$LOGERR" 2>/dev/null)"
grep -Fq "below threshold ($EXP_X < 10): plan_gap/worker" "$LOGERR" 2>/dev/null \
  && ok "the run NAMES plan_gap/worker as below threshold, with its count" \
  || no "the run does not name plan_gap/worker as below threshold
$(cat "$LOGERR" 2>/dev/null)"
# The third arm: clears the threshold, but its evidence is absent rather than defaulted.
[ ! -f "$BO/execution_bug--worker.md" ] \
  && ok "execution_bug/worker clears the threshold ($EXP_Z) but was NOT proposed - only $EXP_Z_CITABLE entries carry citable evidence" \
  || no "execution_bug/worker was proposed on $EXP_Z_CITABLE citable entries - a proposal was written with fabricated or blank evidence"
grep -Fq "only $EXP_Z_CITABLE of its entries carry citable evidence" "$LOGERR" 2>/dev/null \
  && ok "the run NAMES why execution_bug/worker was withheld" \
  || no "the run does not name why execution_bug/worker was withheld"

echo "== AC4a: a second run into a populated dir emits nothing new and reports the suppression =="
before4="$(find "$GO" -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r p; do printf '%s  %s\n' "$(csum "$p")" "$p"; done)"
run_sut "$GJ" "$GO" "$GR"; rc=$?
after4="$(find "$GO" -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r p; do printf '%s  %s\n' "$(csum "$p")" "$p"; done)"
[ "$rc" -eq 0 ] && ok "exit 0 on the second run" || no "exit $rc on the second run"
[ "$before4" = "$after4" ] && ok "the second run added and changed nothing in proposed/" \
  || no "the second run altered proposed/:
$(diff <(printf '%s\n' "$before4") <(printf '%s\n' "$after4"))"
grep -Fq "suppressed convention_mismatch/worker - its evidence set is already covered by $GO/convention_mismatch--worker.md" "$LOGERR" 2>/dev/null \
  && ok "the second run reports the suppression AND names the file it is based on" \
  || no "the second run does not report the suppression with its basis
$(cat "$LOGERR" 2>/dev/null)"

echo "== AC4b: a '## Status: done' requirement file supersedes the candidate =="
D="$(mktmp)"; DO="$D/out"; DR="$D/req"
mkdir -p "$DR/archive"
cp "$DONE_FIX" "$DR/archive/done-requirement.md"
grep -Eq '^##[[:space:]]+Status:[[:space:]]*done[[:space:]]*$' "$DR/archive/done-requirement.md" \
  && ok "premise: the committed fixture really carries a '## Status: done' stamp" \
  || no "premise failed: the fixture has no '## Status: done' stamp - AC4b is uncontrolled"
run_sut "$GJ" "$DO" "$DR"; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0 with a done-stamped requirement present" || no "exit $rc"
ac4b_suppressed=0
[ ! -f "$DO/convention_mismatch--worker.md" ] && ac4b_suppressed=1
[ "$ac4b_suppressed" -eq 1 ] \
  && ok "the candidate covered by the done-stamped file was suppressed" \
  || no "the candidate was written despite a done-stamped file covering its evidence set"
ac4b_named=0
grep -Fq "suppressed convention_mismatch/worker - its evidence set is already covered by $DR/archive/done-requirement.md" "$LOGERR" 2>/dev/null && ac4b_named=1
[ "$ac4b_named" -eq 1 ] \
  && ok "the run names the done-stamped file as the basis of the suppression" \
  || no "the run does not name the done-stamped file as the suppression basis
$(cat "$LOGERR" 2>/dev/null)"
# POSITIVE CONTROL: suppression must be surgical, not a run that emitted nothing at all.
[ -f "$DO/convention_mismatch--unknowable.md" ] \
  && ok "POSITIVE CONTROL: the uncovered sibling candidate was still emitted" \
  || no "POSITIVE CONTROL FAILED: nothing was emitted, so 'suppressed' proves nothing"

echo "-- MUTATION CONTROL: deleting the done-supersession check must turn AC4b RED --"
MUT4="$ROOT/mutant-nosupersede.sh"
sed '/>>> DONE-SUPERSESSION CHECK/,/<<< END DONE-SUPERSESSION CHECK/d' "$SUT" > "$MUT4"
if [ -s "$MUT4" ] && ! cmp -s "$MUT4" "$SUT" && bash -n "$MUT4" 2>/dev/null; then
  ok "built a syntactically valid mutant with the supersession check deleted"
  D2="$(mktmp)"; DO2="$D2/out"
  run_sut "$GJ" "$DO2" "$DR" "$MUT4"; mrc=$?
  if [ "$mrc" -eq 0 ]; then
    [ -f "$DO2/convention_mismatch--worker.md" ] \
      && ok "MUTATION CONTROL: without the check the candidate IS written - the AC4b assertions above turn RED" \
      || no "the mutant also suppressed the candidate - AC4b passes with the mechanism deleted and proves nothing"
  else
    no "the mutant exited $mrc - the mutation control is inconclusive"
  fi
else
  no "could not build a valid supersession mutant (the marker block no longer matches) - AC4b is uncontrolled"
fi

echo "== AC5: a stale basis proposes nothing, names the age, exits 0 =="
S="$(mktmp)"; SO="$S/out"; SR="$S/req"
STALE_EPOCH="$(jq -r '.generated_at_epoch' "$STALE")"
run_sut "$STALE" "$SO" "$SR"; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0 on a stale basis" || no "exit $rc on a stale basis"
[ "$(count_props "$SO")" -eq 0 ] && ok "nothing was proposed from the stale basis" \
  || no "$(count_props "$SO") proposal(s) were written from a stale basis"
grep -Fq "over the 86400s staleness threshold" "$LOGERR" 2>/dev/null \
  && ok "the run names the staleness threshold it applied" || no "the run does not name the staleness threshold"
grep -Eq "basis .* is [0-9]+s old \([0-9]+h\) at generated_at_epoch $STALE_EPOCH" "$LOGERR" 2>/dev/null \
  && ok "the run names the AGE of the basis and the epoch it read" \
  || no "the run does not name the age of the basis
$(cat "$LOGERR" 2>/dev/null)"

echo "-- MUTATION CONTROL: deleting the staleness gate must turn AC5 RED --"
MUT5="$ROOT/mutant-nostale.sh"
awk 'BEGIN{d=0}
     /^if \[ "\$age" -ge "\$STALE_AFTER_SECONDS" \]; then$/{d=1; next}
     d==1 && /^fi$/{d=0; next}
     d==0{print}' "$SUT" > "$MUT5"
if [ -s "$MUT5" ] && ! cmp -s "$MUT5" "$SUT" && bash -n "$MUT5" 2>/dev/null; then
  ok "built a syntactically valid mutant with the staleness gate deleted"
  S2="$(mktmp)"; SO2="$S2/out"
  run_sut "$STALE" "$SO2" "$S2/req" "$MUT5"; mrc=$?
  if [ "$mrc" -eq 0 ] && [ "$(count_props "$SO2")" -ge 1 ]; then
    ok "MUTATION CONTROL: without the gate a stale basis DOES produce $(count_props "$SO2") proposal(s) - AC5 turns RED"
  else
    no "the mutant proposed nothing either (rc=$mrc) - AC5 passes with the gate deleted and proves nothing"
  fi
else
  no "could not build a valid staleness mutant - AC5 is uncontrolled"
fi

echo "== AC6: jq absent / basis missing / basis malformed - named reason, exit 0, in each =="
NOJQ="$ROOT/nojq"; mkdir -p "$NOJQ"
# Everything the script can reach BEFORE its jq guard stays on PATH - otherwise the arm would
# measure a missing shell (exit 127) instead of a missing jq.
for b in bash git date pwd; do
  bp="$(command -v "$b" 2>/dev/null)"
  [ -n "$bp" ] && ln -sf "$bp" "$NOJQ/$b" 2>/dev/null
done
[ -z "$(PATH="$NOJQ" "$NOJQ/bash" -c 'command -v jq' 2>/dev/null)" ] \
  && ok "premise: jq really is unreachable under the stubbed PATH" \
  || no "premise failed: jq is still reachable under the stubbed PATH - the jq-absent arm is uncontrolled"
J="$(mktmp)"; JO="$J/out"
( cd "$ROOT" && PATH="$NOJQ" PROPOSE_FLOOR_JSON="$GJ" PROPOSE_OUT_DIR="$JO" \
    PROPOSE_REQUIREMENTS_DIR="$J/req" bash "$SUT" ) >"$LOGOUT" 2>"$LOGERR"; rc=$?
[ "$rc" -eq 0 ] && ok "jq absent: exit 0" || no "jq absent: exit $rc"
grep -Fq "jq required" "$LOGERR" 2>/dev/null && ok "jq absent: the reason is named" || no "jq absent: no named reason"
[ "$(count_props "$JO")" -eq 0 ] && ok "jq absent: nothing was written" || no "jq absent: something was written"

M1="$(mktmp)"; MO1="$M1/out"
run_sut "$M1/there-is-no-floor.json" "$MO1" "$M1/req"; rc=$?
[ "$rc" -eq 0 ] && ok "basis missing: exit 0" || no "basis missing: exit $rc"
grep -Fq "not found - skipping, nothing proposed" "$LOGERR" 2>/dev/null \
  && ok "basis missing: the reason is named" || no "basis missing: no named reason"
[ "$(count_props "$MO1")" -eq 0 ] && ok "basis missing: nothing was written" || no "basis missing: something was written"

M2="$(mktmp)"; MO2="$M2/out"
run_sut "$MALFORMED" "$MO2" "$M2/req"; rc=$?
[ "$rc" -eq 0 ] && ok "basis malformed: exit 0" || no "basis malformed: exit $rc"
grep -Fq "is not parseable JSON - skipping, nothing proposed" "$LOGERR" 2>/dev/null \
  && ok "basis malformed: the reason is named" || no "basis malformed: no named reason"
[ "$(count_props "$MO2")" -eq 0 ] && ok "basis malformed: nothing was written" || no "basis malformed: something was written"

echo "-- MUTATION CONTROL: deleting the malformed-JSON guard must turn its naming assertion RED --"
MUT6="$ROOT/mutant-noparse.sh"
awk 'BEGIN{d=0}
     /^jq -e \. "\$FLOOR" >\/dev\/null 2>&1 \|\| \{$/{d=1; next}
     d==1 && /^\}$/{d=0; next}
     d==0{print}' "$SUT" > "$MUT6"
if [ -s "$MUT6" ] && ! cmp -s "$MUT6" "$SUT" && bash -n "$MUT6" 2>/dev/null; then
  ok "built a syntactically valid mutant with the malformed-JSON guard deleted"
  M3="$(mktmp)"
  run_sut "$MALFORMED" "$M3/out" "$M3/req" "$MUT6"; mrc=$?
  if grep -Fq "is not parseable JSON" "$LOGERR" 2>/dev/null; then
    no "the mutant still named the parse failure - the AC6 malformed assertion passes with the guard deleted"
  else
    ok "MUTATION CONTROL: without the guard the parse failure is NOT named (mutant rc=$mrc) - that AC6 assertion turns RED"
  fi
else
  no "could not build a valid parse-guard mutant - the malformed arm is uncontrolled"
fi

echo "== AC7: two INDEPENDENT runs into two SEPARATE EMPTY dirs, byte-for-byte =="
D7="$(mktmp)"; BASIS7="$D7/basis.json"; O7A="$D7/a"; O7B="$D7/b"; R7="$D7/req"
cp "$GJ" "$BASIS7"
run_sut "$BASIS7" "$O7A" "$R7"; rc1=$?
run_sut "$BASIS7" "$O7B" "$R7"; rc2=$?
n7a="$(count_props "$O7A")"; n7b="$(count_props "$O7B")"
[ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ] && ok "both independent runs exited 0" || no "runs exited $rc1 / $rc2"
[ "$n7a" -ge 1 ] && [ "$n7b" -ge 1 ] \
  && ok "both runs emitted a NON-EMPTY set of proposals ($n7a / $n7b) - the comparison is not vacuous" \
  || no "one of the runs emitted nothing ($n7a / $n7b); byte-identical empty output proves nothing"
if diff -r "$O7A" "$O7B" >/dev/null 2>&1; then
  ok "two independent runs into two separate empty dirs are byte-for-byte identical"
else
  no "the two independent runs differ:
$(diff -r "$O7A" "$O7B" 2>&1)"
fi

echo "-- the DISCRIMINATING form: identical ledger CONTENT, different serialisation order --"
# Why this is needed: a same-file/same-script comparison cannot tell a sorted implementation
# from an unsorted-but-deterministic one, so the mutation control below would be inconclusive
# against it. Feeding the SAME ledger content in two different array orders THROUGH THE SAME
# BASIS PATH is what makes "output is a function of content, not of serialisation" falsifiable.
P7="$(mktmp)"; PB="$P7/basis.json"; PA_OUT="$P7/a"; PB_OUT="$P7/b"; PR="$P7/req"
GPJ="$P7/perm.json"; fresh_basis "$GOLD_PERM" "$GPJ"
same_content="$(jq -S -r '[.surfaces.postmortem.detail.entries[]]|sort_by([.class,.flow_stage,.line,(.index//0)])' "$GJ" | csum /dev/stdin 2>/dev/null)"
perm_content="$(jq -S -r '[.surfaces.postmortem.detail.entries[]]|sort_by([.class,.flow_stage,.line,(.index//0)])' "$GPJ" | csum /dev/stdin 2>/dev/null)"
[ -n "$same_content" ] && [ "$same_content" = "$perm_content" ] \
  && ok "premise: the permuted fixture carries byte-identical ledger CONTENT in a different array order" \
  || no "premise failed: the permuted fixture is not a pure permutation - the AC7 mutation control is uncontrolled"
raw_order_differs=0
[ "$(jq -c '.surfaces.postmortem.detail.entries' "$GJ")" != "$(jq -c '.surfaces.postmortem.detail.entries' "$GPJ")" ] && raw_order_differs=1
[ "$raw_order_differs" -eq 1 ] && ok "premise: the two arrays really are in different orders" \
  || no "premise failed: the two arrays are in the same order - the AC7 mutation control is uncontrolled"
cp "$GJ"  "$PB"; run_sut "$PB" "$PA_OUT" "$PR"
cp "$GPJ" "$PB"; run_sut "$PB" "$PB_OUT" "$PR"
if diff -r "$PA_OUT" "$PB_OUT" >/dev/null 2>&1 && [ "$(count_props "$PA_OUT")" -ge 1 ]; then
  ok "output is a function of ledger CONTENT, not of its serialisation order"
else
  no "a pure permutation of the ledger changed the emitted proposals:
$(diff -r "$PA_OUT" "$PB_OUT" 2>&1)"
fi

echo "-- MUTATION CONTROL: deleting the sort before emission must turn AC7 RED --"
MUT7="$ROOT/mutant-nosort.sh"
grep -c 'SORT-BEFORE-EMISSION' "$SUT" > "$ROOT/sortcount" 2>/dev/null
nsort="$(awk '{print $1+0}' "$ROOT/sortcount")"
[ "$nsort" -eq 1 ] && ok "premise: exactly one SORT-BEFORE-EMISSION site exists to delete" \
  || no "premise failed: $nsort SORT-BEFORE-EMISSION sites - the mutation may be partial"
sed '/SORT-BEFORE-EMISSION/d' "$SUT" > "$MUT7"
if [ -s "$MUT7" ] && ! cmp -s "$MUT7" "$SUT" && bash -n "$MUT7" 2>/dev/null; then
  ok "built a syntactically valid mutant with the sort deleted"
  M7="$(mktmp)"; MB="$M7/basis.json"; MA_OUT="$M7/a"; MB_OUT="$M7/b"
  cp "$GJ"  "$MB"; run_sut "$MB" "$MA_OUT" "$M7/req" "$MUT7"; mr1=$?
  cp "$GPJ" "$MB"; run_sut "$MB" "$MB_OUT" "$M7/req" "$MUT7"; mr2=$?
  if [ "$mr1" -eq 0 ] && [ "$mr2" -eq 0 ] && [ "$(count_props "$MA_OUT")" -ge 1 ]; then
    if diff -r "$MA_OUT" "$MB_OUT" >/dev/null 2>&1; then
      no "the sort-deleted mutant still produced identical output - AC7 passes with the mechanism deleted"
    else
      ok "MUTATION CONTROL: without the sort the SAME ledger content yields DIFFERENT proposals - AC7 turns RED"
    fi
  else
    no "the sort mutant did not reach a comparable state (rc=$mr1/$mr2) - AC7 is uncontrolled"
  fi
else
  no "could not build a valid sort mutant - AC7 is uncontrolled"
fi

echo "== AC8: blast radius, hashed on the FILESYSTEM tree - never on a git reading =="
# The exclusion is the output dir itself and .git/ - nothing else. Directories and symlinks are
# in scope: `-type f` alone would make a stray directory or a symlink dropped outside the
# output dir invisible, and a symlink is the cheapest way to escape a directory allow-list.
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
new_repo() {
  nr="$(mktmp)"
  ( cd "$nr" && git init -q && git config user.email t@t && git config user.name t \
      && printf '.supervisor/*\n' > .gitignore \
      && printf 'init\n' > f && git add f .gitignore && git commit -qm init ) >/dev/null 2>&1
  mkdir -p "$nr/.supervisor/requirements/archive" "$nr/.supervisor/floor" "$nr/.agent/rules"
  printf 'pre-existing requirement\n' > "$nr/.supervisor/requirements/archive/old.md"
  printf 'state\n' > "$nr/.supervisor/state.md"
  printf '%s' "$nr"
}
RK="$(new_repo)"
[ -d "$RK/.git" ] && ok "built a throwaway git repo OUTSIDE the real repo root for the containment run" \
  || no "could not build the containment fixture repo"
# Demonstrate WHY a git reading is unusable here rather than merely asserting it.
printf 'probe\n' > "$RK/.supervisor/git-blindness-probe.md"
gsp="$( cd "$RK" && git status --porcelain 2>/dev/null | grep -c 'git-blindness-probe' )"
[ "$gsp" -eq 0 ] \
  && ok "measured: a write under the ignored .supervisor/ is INVISIBLE to git status --porcelain - a git-tracked-tree hash would be vacuous here" \
  || no "git status reported the ignored probe ($gsp hits) - re-check the premise"
rm -f "$RK/.supervisor/git-blindness-probe.md"

before8="$(hash_set "$RK")"
nb8="$(printf '%s\n' "$before8" | awk 'NF{n++} END{print n+0}')"
[ "$nb8" -ge 5 ] && ok "pre-run tree hash is non-empty ($nb8 paths) - the containment assertion is not vacuous" \
  || no "pre-run tree hash has only $nb8 paths"
( cd "$RK" && PROPOSE_FLOOR_JSON="$GJ" bash "$SUT" ) >"$LOGOUT" 2>"$LOGERR"; rc=$?
after8="$(hash_set "$RK")"
[ "$rc" -eq 0 ] && ok "the containment run exited 0" || no "the containment run exited $rc"
n8="$(count_props "$RK/.supervisor/requirements/proposed")"
[ "$n8" -ge 1 ] && ok "the containment run actually emitted $n8 proposal(s) into the default output dir" \
  || no "the containment run emitted nothing - 'the tree did not change' would prove nothing
$(cat "$LOGERR" 2>/dev/null)"
[ "$before8" = "$after8" ] \
  && ok "no path outside .supervisor/requirements/proposed/ was created, modified or removed" \
  || no "the tree outside the output dir changed:
$(diff <(printf '%s\n' "$before8") <(printf '%s\n' "$after8"))"

echo "-- MUTATION CONTROL: deleting the write-path guard must turn AC8 RED --"
TRAV="$ROOT/floor-traversal.json"
jq '.surfaces.postmortem.detail.entries |= map(if .class == "convention_mismatch"
      then .class = "../../../stray-propose-work" else . end)' "$GJ" > "$TRAV" 2>/dev/null
[ -s "$TRAV" ] && ok "built a hostile fixture whose class name is a path traversal" \
  || no "could not build the traversal fixture - AC8 is uncontrolled"
# First: the INTACT script must refuse it and leave the tree alone.
RK2="$(new_repo)"
b2="$(hash_set "$RK2")"
( cd "$RK2" && PROPOSE_FLOOR_JSON="$TRAV" bash "$SUT" ) >"$LOGOUT" 2>"$LOGERR"; rc=$?
a2="$(hash_set "$RK2")"
[ "$rc" -eq 0 ] && ok "traversal fixture: the intact script still exits 0" || no "traversal fixture: exit $rc"
[ "$b2" = "$a2" ] && ok "traversal fixture: the intact script wrote nothing outside the output dir" \
  || no "traversal fixture: the intact script escaped its output dir:
$(diff <(printf '%s\n' "$b2") <(printf '%s\n' "$a2"))"
grep -Fq "refusing to write" "$LOGERR" 2>/dev/null \
  && ok "traversal fixture: the refusal is named" || no "traversal fixture: the refusal is not named"
# Then: the same fixture against the guard-deleted mutant must plant a real stray write.
MUT8="$ROOT/mutant-noguard.sh"
sed '/>>> WRITE-PATH GUARD/,/<<< END WRITE-PATH GUARD/d' "$SUT" > "$MUT8"
if [ -s "$MUT8" ] && ! cmp -s "$MUT8" "$SUT" && bash -n "$MUT8" 2>/dev/null; then
  ok "built a syntactically valid mutant with the write-path guard deleted"
  RK3="$(new_repo)"
  b3="$(hash_set "$RK3")"
  ( cd "$RK3" && PROPOSE_FLOOR_JSON="$TRAV" bash "$MUT8" ) >"$LOGOUT" 2>"$LOGERR"; mrc=$?
  a3="$(hash_set "$RK3")"
  if [ "$b3" != "$a3" ]; then
    ok "MUTATION CONTROL: without the guard a write lands OUTSIDE the output dir (mutant rc=$mrc) - AC8 turns RED"
    stray="$(diff <(printf '%s\n' "$b3") <(printf '%s\n' "$a3") | sed -n 's/^> .*  //p' | head -1)"
    [ -n "$stray" ] && ok "the stray path the mutant created is named: $stray" || no "could not name the stray path"
  else
    no "the guard-deleted mutant left the tree unchanged - AC8 passes with the mechanism deleted and proves nothing"
  fi
else
  no "could not build a valid write-guard mutant - AC8 is uncontrolled"
fi

echo "== AC9: no score, rank, priority or ordering field in any emitted proposal =="
n9="$(count_props "$GO")"
[ "$n9" -ge 1 ] && ok "AC9 runs against a set of $n9 emitted proposal(s), not an empty dir" \
  || no "AC9 has no emitted proposals to grep - it would pass vacuously"
hits9=0
for f in "$GO"/*.md; do
  [ -f "$f" ] || continue
  if grep -EqiI '(^|[^a-z])(scor(e|ed|ing)|rank(ed|ing)?|priorit(y|ies|ised|ized)|top-?[0-9]+|ordering|weight(ed|ing)?)([^a-z]|$)' "$f" 2>/dev/null; then
    hits9=$((hits9+1))
    echo "     ranking-shaped text in $(basename "$f"): $(grep -EiI -m1 '(scor|rank|priorit|top-?[0-9]|ordering|weight)' "$f")"
  fi
done
[ "$hits9" -eq 0 ] && ok "no emitted file carries a score, rank, priority, top-N, ordering or weight field" \
  || no "$hits9 emitted file(s) carry ranking-shaped text"
# POSITIVE CONTROL for the grep itself: an assertion that never fires is not an assertion.
SPIKE="$ROOT/ranking-spike.md"
cp "$GO/convention_mismatch--worker.md" "$SPIKE" 2>/dev/null
printf -- '- priority: 2\n' >> "$SPIKE"
grep -EqiI '(^|[^a-z])(scor(e|ed|ing)|rank(ed|ing)?|priorit(y|ies|ised|ized)|top-?[0-9]+|ordering|weight(ed|ing)?)([^a-z]|$)' "$SPIKE" 2>/dev/null \
  && ok "POSITIVE CONTROL: the same grep DOES fire on a proposal with a priority field" \
  || no "POSITIVE CONTROL FAILED: the AC9 grep cannot fire at all, so its silence means nothing"

echo "== AC10: the directory contract, in the emitted README and in committed source =="
README="$GO/README.md"
[ -f "$README" ] && ok "the script emitted proposed/README.md" || no "no README.md was emitted"
SENTENCE='`.supervisor/requirements/proposed/` is deliberately NOT an `/automate --folder` target; promotion is a human moving a file out of it.'
flatten() { tr '\n' ' ' < "$1" | sed 's/#//g' | tr -s ' '; }
if [ -f "$README" ]; then
  r_flat="$(flatten "$README")"
  case "$r_flat" in
    *"$SENTENCE"*) ok "the emitted README states the contract sentence in full" ;;
    *) no "the emitted README does not state the contract sentence
$(cat "$README")" ;;
  esac
  grep -Fq '/automate --folder' "$README" 2>/dev/null \
    && ok "the README names /automate --folder explicitly" || no "the README does not name /automate --folder"
fi
# The README is a runtime artefact under a gitignored directory, so a fresh clone carries no
# record of the contract unless committed source carries it too.
s_flat="$(flatten "$SUT")"
case "$s_flat" in
  *"$SENTENCE"*) ok "propose-work.sh's own header carries the same contract sentence verbatim" ;;
  *) no "propose-work.sh's header does not carry the contract sentence - a fresh clone would have no record of it" ;;
esac

echo "== AC1b: the LIVE .supervisor/floor/floor.json - three outcomes, local-only =="
LIVE=""
REPO_ROOT="$(cd "$HERE/../.." 2>/dev/null && pwd)"
[ -n "$REPO_ROOT" ] && LIVE="$REPO_ROOT/.supervisor/floor/floor.json"
if [ -z "$LIVE" ] || [ ! -f "$LIVE" ]; then
  skipn "AC1b: $LIVE is ABSENT (.gitignore ignores .supervisor/*, so it does not exist on a fresh clone or a CI runner) - the hermetic AC1a arm is what gates CI"
else
  live_gen="$(jq -r '.generated_at_epoch // empty' "$LIVE" 2>/dev/null)"
  case "$live_gen" in
    ''|*[!0-9]*)
      skipn "AC1b: the live floor.json carries no readable generated_at_epoch - nothing to age-check" ;;
    *)
      live_age=$(( NOW - live_gen ))
      [ "$live_age" -lt 0 ] && live_age=0
      if [ "$live_age" -ge 86400 ]; then
        skipn "AC1b: the live floor.json is ${live_age}s old ($(( live_age / 3600 ))h, over the 24h threshold) - proposing nothing from it is AC5's CORRECT behaviour, not a failure. Re-run build-floor.sh to exercise this arm."
      else
        L="$(mktmp)"
        run_sut "$LIVE" "$L/out" "$L/req"; rc=$?
        [ "$rc" -eq 0 ] && ok "AC1b: exit 0 against the live basis (${live_age}s old)" || no "AC1b: exit $rc against the live basis"
        if [ -f "$L/out/convention_mismatch--worker.md" ]; then
          ok "AC1b: a convention_mismatch proposal was emitted from the live basis"
          lp="$(jq -r '[.surfaces.postmortem.detail.entries[]|select(.class=="convention_mismatch" and .flow_stage=="worker")]|length' "$LIVE")"
          lc="$(jq -r '[.surfaces.postmortem.detail.entries[]|select(.class=="convention_mismatch")]|length' "$LIVE")"
          grep -Fq -- "- pair entries: $lp (emission threshold 10)" "$L/out/convention_mismatch--worker.md" 2>/dev/null \
            && ok "AC1b: the live pair count ($lp) is recomputed and matches" || no "AC1b: the live pair count does not match $lp"
          grep -Fq -- "- entries in class \`convention_mismatch\`: $lc" "$L/out/convention_mismatch--worker.md" 2>/dev/null \
            && ok "AC1b: the live class total ($lc) is recomputed and matches" || no "AC1b: the live class total does not match $lc"
        else
          lp="$(jq -r '[.surfaces.postmortem.detail.entries[]|select(.class=="convention_mismatch" and .flow_stage=="worker")]|length' "$LIVE" 2>/dev/null)"
          no "AC1b: the live basis is fresh and holds $lp convention_mismatch/worker entries but no proposal was emitted
$(cat "$LOGERR" 2>/dev/null)"
        fi
      fi ;;
  esac
fi

echo "== AC11: the unknowable note - the brief's MUST, with a mutation control =="
UNK="$GO/convention_mismatch--unknowable.md"
UNK_TEXT='the flow stage could not be attributed'
if [ -f "$UNK" ]; then
  ok "a proposal was emitted for the (convention_mismatch, unknowable) pair"
  grep -Fq "$UNK_TEXT" "$UNK" 2>/dev/null \
    && ok "the unknowable proposal names what the stage means" \
    || no "the unknowable proposal does not name what 'unknowable' means - the brief requires it"
  grep -Fq "$UNK_TEXT" "$GO/convention_mismatch--worker.md" 2>/dev/null \
    && no "the note also appears on the worker-staged proposal - it is unconditional, so AC11 proves nothing" \
    || ok "positive control: the note is absent from the worker-staged proposal, so it is genuinely conditional"
else
  no "no unknowable proposal was emitted - AC11 cannot be evaluated"
fi

MUT11="$ROOT/mutant-nounknowable.sh"
sed "s/^    unknowable_note='.*'\$/    unknowable_note=''/" "$SUT" > "$MUT11" 2>/dev/null
if [ -s "$MUT11" ] && ! cmp -s "$MUT11" "$SUT" && bash -n "$MUT11" 2>/dev/null; then
  ok "built a syntactically valid mutant with the unknowable note emptied"
  M11="$(mktmp)"
  run_sut "$GJ" "$M11/out" "$M11/req" "$MUT11" >/dev/null 2>&1
  if [ -f "$M11/out/convention_mismatch--unknowable.md" ]; then
    grep -Fq "$UNK_TEXT" "$M11/out/convention_mismatch--unknowable.md" 2>/dev/null \
      && no "the mutant still emitted the note - AC11 passes with the mechanism deleted and proves nothing" \
      || ok "mutation control: emptying the note makes AC11's assertion fail, so it is not vacuous"
  else
    no "the mutant emitted no unknowable proposal - the AC11 control is inconclusive"
  fi
else
  no "could not build a valid unknowable-note mutant - AC11 is uncontrolled"
fi

echo "== AC12: deleting a proposal is NOT a durable dismissal, and both surfaces say so =="
# The behaviour claude-review surfaced: the evidence-set token is stable, so a deleted
# proposal returns on the next run. Assert the behaviour, that the documented durable path
# actually works, and that both surfaces say so - guidance that is wrong is worse than none.
D="$(mktmp)"; DO="$D/out"; DR="$D/req"
run_sut "$GJ" "$DO" "$DR" >/dev/null 2>&1
TARGET="$DO/convention_mismatch--worker.md"
if [ -f "$TARGET" ]; then
  tok_before="$(grep -m1 '^evidence-set:' "$TARGET" 2>/dev/null)"
  rm -f "$TARGET"
  [ ! -f "$TARGET" ] \
    && ok "AC12: the proposal was deleted, as a human following 'read it, decide, delete it' would" \
    || no "AC12: could not delete the proposal"
  run_sut "$GJ" "$DO" "$DR" >/dev/null 2>&1
  if [ -f "$TARGET" ]; then
    ok "AC12: it came back on the next run - deletion is not durable"
    tok_after="$(grep -m1 '^evidence-set:' "$TARGET" 2>/dev/null)"
    if [ -n "$tok_before" ] && [ "$tok_before" = "$tok_after" ]; then
      ok "AC12: the evidence-set token is identical across the delete, so suppression could never have matched it"
    else
      no "AC12: the token changed across the delete ($tok_before -> $tok_after) - the documented rationale is wrong"
    fi
  else
    no "AC12: it did NOT come back - the guidance we now emit about durable dismissal is false"
  fi

  # The durable path must actually work, or we are printing a dead end.
  mkdir -p "$DR"
  { printf '# dismissed\n\n## Status: done\n\n%s\n' "$tok_before"; } > "$DR/dismissed.md"
  D2="$(mktmp)"
  run_sut "$GJ" "$D2/out" "$DR" >/dev/null 2>&1
  [ ! -f "$D2/out/convention_mismatch--worker.md" ] \
    && ok "AC12: pasting the token into a '## Status: done' file DOES suppress it - the documented path works" \
    || no "AC12: the documented durable-dismissal path did not suppress the candidate - we would be printing guidance that does not work"
else
  no "AC12: no worker proposal to delete - cannot evaluate"
fi

grep -Fq 'not a durable dismissal' "$GO/README.md" 2>/dev/null \
  && ok "AC12: the emitted README warns that deletion is not durable" \
  || no "AC12: the emitted README does not warn that deletion is not durable"
grep -Fq 'dismissed durably' "$GO/convention_mismatch--worker.md" 2>/dev/null \
  && ok "AC12: the proposal's own acceptance criteria name the durable path" \
  || no "AC12: the proposal still tells the human to delete it with no mention of durability"

echo "== AC13: /propose's documented interface matches the script's actual one =="
# The command doc restates the script's env defaults. A restated value drifts silently, which
# is the defect class this repo records most - so assert the doc against the code, not prose.
CMD_DOC="$HERE/../commands/propose.md"
if [ -f "$CMD_DOC" ]; then
  ok "the /propose command file exists (the invocation seam is present)"
  grep -Fq 'scripts/propose-work.sh' "$CMD_DOC" 2>/dev/null \
    && ok "the command shells out to this script rather than restating its behaviour" \
    || no "the command does not reference propose-work.sh - it documents something else"
  ac13_fail=0
  for pair in \
    "PROPOSE_FLOOR_JSON|.supervisor/floor/floor.json" \
    "PROPOSE_OUT_DIR|.supervisor/requirements/proposed" \
    "PROPOSE_REQUIREMENTS_DIR|.supervisor/requirements" \
    "PROPOSE_THRESHOLD|10" \
    "PROPOSE_MAX_AGE_SECONDS|86400"; do
    var="${pair%%|*}"; want="${pair##*|}"
    grep -Fq "$var" "$CMD_DOC" 2>/dev/null || { ac13_fail=1; continue; }
    grep -Fq "$want" "$CMD_DOC" 2>/dev/null || ac13_fail=1
    grep -Fq "$var" "$SUT" 2>/dev/null || ac13_fail=1
  done
  [ "$ac13_fail" -eq 0 ] \
    && ok "every env var and default the command documents is present in both the doc and the script" \
    || no "the command doc's env table has drifted from the script's actual variables/defaults"
  # Positive control: a default the script does NOT use must be absent, or the check above is
  # satisfied by a doc that merely mentions plausible-looking strings.
  grep -Fq 'PROPOSE_NOT_A_REAL_VAR' "$CMD_DOC" 2>/dev/null \
    && no "positive control failed - the doc names a variable the script has no concept of" \
    || ok "positive control: the doc names no variable the script does not define"
  grep -Fq 'not a durable dismissal' "$CMD_DOC" 2>/dev/null \
    && ok "the command documents that deletion is not a durable dismissal" \
    || no "the command omits the delete-is-not-durable contract - the one thing the emitted files cannot teach"
else
  no "no /propose command file - propose-work.sh is wired to nothing and the loop still cannot propose"
fi

echo
echo "propose-work: $pass passed, $fail failed, $skip skipped"
[ "$fail" -eq 0 ] || exit 1
exit 0
