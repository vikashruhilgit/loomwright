#!/usr/bin/env bash
# test-propose-from-verify.sh - self-tests for propose-from-verify.sh, the VERIFY basis of
# `/propose`, which reads one Selvedge run folder's `verdict.json` (schema_version 1) as data.
# HERMETIC: every fixture is built in a mktemp -d tree OUTSIDE the repo root; nothing here depends
# on a real run folder existing. Exit 0 = all pass, 1 = any failure.
# Registered automatically by ci.yml's test-*.sh glob.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/propose-from-verify.sh"
COMMON="$HERE/propose-common.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "FATAL: jq is not on PATH - the harness itself requires it"
  exit 1
fi
for f in "$SUT" "$COMMON"; do
  [ -f "$f" ] || { echo "FATAL: required script missing: $f"; exit 1; }
done

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT" 2>/dev/null' EXIT
mktmp() { mktemp -d "$ROOT/d.XXXXXX"; }

RUN_ID="20261119T120000Z-a1b2c3"
PLAN_SHA="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
C_FAIL="c-aaaaaaaaaaaa"; C_PASS1="c-bbbbbbbbbbbb"; C_PASS2="c-cccccccccccc"
C_BLOCKED="c-dddddddddddd"; C_NV="c-eeeeeeeeeeee"; C_LATE="c-ffffffffffff"

# crit <verdict> <expected-json> <failed_step-json> <interpretation-json> <steps-json> - one
# criterion carrying the schema's full required key set (selvedge/schemas/verdict.schema.json).
crit() {
  jq -nc --arg v "$1" --argjson e "$2" --argjson fs "$3" --argjson i "$4" --argjson s "$5" '
    {verdict: $v, evidence_class: "structured-read", read_value: null, matched: null, expected: $e,
     reason: (if ($v == "BLOCKED" or $v == "NOT_VERIFIABLE") then "app_unreachable" else null end),
     failed_step: $fs, interpretation: $i, unverified_assumptions: [], steps: $s}'
}
# The FAIL criterion lists steps[] OUT of index order: position 1 holds step 0 (goto) while step 1
# is a `read` at position 2, so a positional `.steps[failed_step]` lookup names the wrong type.
FAIL_STEPS='[{"step":2,"type":"expect","outcome":"mismatched","duration_ms":3},{"step":0,"type":"goto","outcome":"ok","duration_ms":1},{"step":1,"type":"read","outcome":"failed","duration_ms":2}]'
OK_STEPS='[{"step":0,"type":"goto","outcome":"ok","duration_ms":1},{"step":1,"type":"expect","outcome":"matched","duration_ms":1}]'
crit_fail() { crit FAIL '{"op":"equals","value":"4"}' 1 "$(jq -nc --arg t "${1:-The cart total shows 4 items after adding one}" '$t')" "$FAIL_STEPS"; }
crit_pass() { crit PASS '{"op":"contains","value":"Welcome"}' null '"The home page greets the user"' "$OK_STEPS"; }

# make_verdict <run_dir> <criteria-json> [schema_version-json] - writes <run_dir>/verdict.json with
# every top-level field the schema requires.
make_verdict() {
  mkdir -p "$1"
  jq -n --argjson c "$2" --argjson sv "${3:-1}" --arg p "$PLAN_SHA" '
    {schema_version: $sv, target: "web", plan_sha256: $p, playwright_version: "1.50.0",
     plan_revision: 1, prior_revisions: [], replay_of: null, data_state: "managed", hooks_run: [],
     criteria: $c}' > "$1/verdict.json"
}
# make_run - the AC3 fixture: 1 FAIL + 2 PASS. Prints the run dir.
make_run() {
  mr_dir="$(mktmp)/$RUN_ID"
  make_verdict "$mr_dir" "$(jq -nc --argjson f "$(crit_fail)" --argjson p "$(crit_pass)" \
    --arg a "$C_FAIL" --arg b "$C_PASS1" --arg c "$C_PASS2" '{($b): $p, ($a): $f, ($c): $p}')"
  printf '%s' "$mr_dir"
}

run_sut() {
  rs_dir="$1"; rs_out="$2"; rs_scr="${3:-$SUT}"
  PROPOSE_FROM_VERIFY_OUT_DIR="$rs_out" bash "$rs_scr" "$rs_dir" >"$ROOT/last.out" 2>"$ROOT/last.err"
  return $?
}

count_props() { find "$1" -maxdepth 1 -type f -name '*.md' 2>/dev/null | awk 'END{print NR+0}'; }

# clock_shim <fixed-output> - a PATH dir whose `date` prints <fixed-output> whatever its args.
# The first AC3 run and its idempotence re-run happen inside the same second, so a real clock
# never differs between them; each runs under its OWN fixed clock so any clock-derived byte in
# the candidate differs and the byte-identity pin turns red. Scoped to one command's env.
clock_shim() {
  cs_dir="$(mktmp)"
  printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$1" > "$cs_dir/date"
  chmod +x "$cs_dir/date"
  printf '%s' "$cs_dir"
}
CLOCK_FIRST="$(clock_shim 'Sat Jan  1 00:00:00 UTC 2000')"
CLOCK_RERUN="$(clock_shim 'Thu Dec 31 23:59:59 UTC 2099')"
# run_sut_clock <clock-dir> <run_dir> <out_dir> - run_sut with the clock shim first on PATH.
run_sut_clock() {
  rsc_clock="$1"; shift
  PATH="$rsc_clock:$PATH" run_sut "$@"
}

echo "== AC3: verdict.json with 1 FAIL + 2 PASS => exit 0, exactly one candidate =="
RD="$(make_run)"
OUT="$(mktmp)/out"
run_sut_clock "$CLOCK_FIRST" "$RD" "$OUT"; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0" || no "exit $rc: $(cat "$ROOT/last.err")"
np="$(count_props "$OUT")"
[ "$np" -eq 1 ] && ok "exactly one candidate written ($np)" || no "expected 1 candidate, got $np: $(ls "$OUT" 2>/dev/null)"
F="$OUT/verify-${RUN_ID}-${C_FAIL}.md"
[ -f "$F" ] && ok "the candidate is named verify-<run_id>-<criterion_id>.md (derived, never counted)" || no "candidate $F missing: $(ls "$OUT" 2>/dev/null)"
[ ! -e "$OUT/verify-${RUN_ID}-${C_PASS1}.md" ] && [ ! -e "$OUT/verify-${RUN_ID}-${C_PASS2}.md" ] \
  && ok "PASS criteria are never drafted" || no "a PASS criterion was drafted"

echo "== AC3: the candidate cites criterion, interpretation, expected, failed step, run id, plan_sha256 =="
has_line() { grep -qxF -- "$1" "${F:-/dev/null}"; }
has_line "- criterion: $C_FAIL" && ok "cites the criterion id" || no "criterion id not cited"
has_line "- interpretation: The cart total shows 4 items after adding one" && ok "cites the interpretation" || no "interpretation not cited"
has_line '- expected: equals "4"' && ok "cites the expected value as op + value" || no "expected op/value not cited"
has_line "- failed step: 1 (type: read)" && ok "cites failed_step 1 with ITS step's type (read), looked up by .step, not array position (goto)" \
  || no "failed step not cited by .step lookup: $(grep -F 'failed step' "${F:-/dev/null}")"
has_line "Criterion $C_FAIL failed: The cart total shows 4 items after adding one" && ok "the ## Problem line carries the interpretation" || no "## Problem line does not carry the interpretation"
has_line "- [ ] Criterion $C_FAIL passes on a fresh run of the same plan: The cart total shows 4 items after adding one" \
  && ok "the ## Suggested acceptance item carries the interpretation" || no "## Suggested acceptance item does not carry the interpretation"
has_line "- run: $RUN_ID" && ok "cites the run id (the run folder's basename)" || no "run id not cited"
has_line "- plan_sha256: $PLAN_SHA" && ok "cites plan_sha256" || no "plan_sha256 not cited"
for sec in '## Depends on' '## Touches' '## Problem' '## Evidence' '## Suggested acceptance' '## Status: proposed'; do
  has_line "$sec" && ok "carries '$sec'" || no "missing '$sec'"
done

# parallel-automate/10 (AC-7): the draft carries the planner's sections and `plan-waves --lint` accepts it.
pw_lint_out="$(bash "$HERE/automate-helpers.sh" plan-waves "$F" --lint --root "$(dirname "$F")" 2>&1)"; pw_lint_rc=$?
if [ "$pw_lint_rc" -eq 0 ] && grep -qxF '## Depends on' "$F" && grep -qxF '## Touches' "$F" \
  && grep -qF ': Touches ok (declared unknown); Depends on ok' <<<"${pw_lint_out%%$'\n'*}"; then
  ok "AC-7 propose-from-verify draft: ## Depends on none + ## Touches unknown (it names no change-site file); plan-waves --lint ok (declared unknown), exit 0"
else no "AC-7 propose-from-verify draft lint (rc=$pw_lint_rc): $(printf '%s' "$pw_lint_out" | head -n1)"; fi

# A draft whose interpretation names an existing repo file carries it as Touches (a missing one and
# an absolute path are dropped) and lints `ok` — the cwd's checkout is the root names resolve against.
VT_DIR="$(mktmp)/proj"; mkdir -p "$VT_DIR/src"; ( cd "$VT_DIR" && git init -q . ); : > "$VT_DIR/src/app.ts"
VT_RD="$(mktmp)/20261119T120000Z-0000a1"
make_verdict "$VT_RD" "$(jq -nc --argjson f "$(crit_fail 'Crash in src/app.ts (not src/none.ts, not /etc/hosts).')" --arg a "$C_FAIL" '{($a): $f}')"
( cd "$VT_DIR" && PROPOSE_FROM_VERIFY_OUT_DIR="$VT_DIR/out" bash "$SUT" "$VT_RD" ) >/dev/null 2>&1
VT_F="$(find "$VT_DIR/out" -maxdepth 1 -name "verify-*-${C_FAIL}.md" 2>/dev/null | head -1)"
vt_sec="$(awk '/^## Touches$/{p=1; next} p && /^## /{exit} p && NF' "${VT_F:-/dev/null}")"
vt_lint="$(bash "$HERE/automate-helpers.sh" plan-waves "${VT_F:-/nonexistent.md}" --lint --root "$VT_DIR" 2>&1)"; vt_rc=$?
[ "$vt_sec" = "src/app.ts" ] && [ "$vt_rc" -eq 0 ] && grep -qF ': Touches ok; Depends on ok' <<<"${vt_lint%%$'\n'*}" \
  && ok "AC-7 propose-from-verify: Touches = the existing file the interpretation names (src/app.ts), lint ok" \
  || no "AC-7 named-file draft: Touches '$vt_sec', lint rc=$vt_rc: $(printf '%s' "$vt_lint" | head -n1)"
# vt_touches' CONTAINMENT rule (extractor-only — the planner's --lint grammar is unaffected, so the
# test-automate-helpers.sh X7 drift test does not cover it; this block and A12 in
# test-automate-dismissed.sh do, with the same fixture set). Decision under test for an in-repo
# symlink: a symlinked DIRECTORY resolving inside the root is accepted as written (indir/app.ts); a
# symlinked FILE is rejected wherever it points, inside (inlink.ts) or outside (flink.txt).
CT_DIR="$(mktmp)/proj"; CT_OUT="$(mktmp)/outside"; mkdir -p "$CT_DIR/src" "$CT_OUT"
( cd "$CT_DIR" && git init -q . ); : > "$CT_DIR/src/app.ts"; : > "$CT_OUT/secret.txt"
ln -s "$CT_OUT" "$CT_DIR/lnk"; ln -s "$CT_OUT/secret.txt" "$CT_DIR/flink.txt"
ln -s src/app.ts "$CT_DIR/inlink.ts"; ln -s src "$CT_DIR/indir"
git -C "$CT_DIR" add lnk flink.txt inlink.ts indir src/app.ts >/dev/null 2>&1
CT_RD="$(mktmp)/20261119T120000Z-0000c7"
make_verdict "$CT_RD" "$(jq -nc --argjson f "$(crit_fail 'bug: src/app.ts lnk/secret.txt flink.txt inlink.ts indir/app.ts .git/config .GIT/config .git/HEAD')" --arg a "$C_FAIL" '{($a): $f}')"
( cd "$CT_DIR" && PROPOSE_FROM_VERIFY_OUT_DIR="$CT_DIR/out" bash "$SUT" "$CT_RD" ) >/dev/null 2>&1
CT_F="$(find "$CT_DIR/out" -maxdepth 1 -name "verify-*-${C_FAIL}.md" 2>/dev/null | head -1)"
ct_sec="$(awk '/^## Touches$/{p=1; next} p && /^## /{exit} p && NF' "${CT_F:-/dev/null}")"
ct_has() { grep -qxF -- "$1" <<<"$ct_sec"; }
[ -n "$CT_F" ] || no "containment draft not written"
ct_has src/app.ts && ok "containment (e): a normal existing path is still accepted" || no "containment (e): normal path dropped: Touches '$ct_sec'"
! ct_has lnk/secret.txt && ok "containment (a): a file under a symlink to an OUTSIDE dir is rejected" || no "containment (a): lnk/secret.txt leaked into Touches: '$ct_sec'"
! ct_has flink.txt && ok "containment (b): a symlinked FILE pointing outside is rejected" || no "containment (b): flink.txt leaked into Touches: '$ct_sec'"
! ct_has inlink.ts && ct_has indir/app.ts && ok "containment (c): in-repo symlinked file rejected, in-repo symlinked dir accepted as written" || no "containment (c): in-repo symlink handling: '$ct_sec'"
! ct_has .git/config && ! ct_has .GIT/config && ! ct_has .git/HEAD && ok "containment (d): .git/ paths are rejected (any case)" || no "containment (d): .git path leaked into Touches: '$ct_sec'"
[ "$ct_sec" = "$(printf 'indir/app.ts\nsrc/app.ts')" ] && ok "containment: Touches is exactly the two contained paths" || no "containment Touches set: '$(tr '\n' '|' <<<"$ct_sec")'"

echo "== AC3: only FAIL criteria are drafted — PASS / BLOCKED / NOT_VERIFIABLE never =="
MIX_RD="$(mktmp)/20261119T120000Z-00b10c"
make_verdict "$MIX_RD" "$(jq -nc \
  --argjson f "$(crit FAIL null null null '[]')" \
  --argjson b "$(crit BLOCKED null null '"Login page"' '[]')" \
  --argjson n "$(crit NOT_VERIFIABLE null null '"Email arrives"' '[]')" \
  --argjson p "$(crit_pass)" \
  --arg a "$C_FAIL" --arg bb "$C_BLOCKED" --arg nn "$C_NV" --arg pp "$C_PASS1" \
  '{($nn): $n, ($bb): $b, ($pp): $p, ($a): $f}')"
MIX_OUT="$(mktmp)/out-mix"
run_sut "$MIX_RD" "$MIX_OUT"; rc_mix=$?
MIX_F="$MIX_OUT/verify-$(basename "$MIX_RD")-${C_FAIL}.md"
[ "$rc_mix" -eq 0 ] && [ "$(count_props "$MIX_OUT")" -eq 1 ] && [ -f "$MIX_F" ] \
  && ok "FAIL + BLOCKED + NOT_VERIFIABLE + PASS => only the FAIL is drafted" \
  || no "mixed verdicts: rc=$rc_mix, files: $(ls "$MIX_OUT" 2>/dev/null | tr '\n' ' ')"
grep -qxF -- '- expected: none' "$MIX_F" 2>/dev/null && grep -qxF -- '- failed step: none' "$MIX_F" 2>/dev/null \
  && grep -qxF -- '- interpretation: none' "$MIX_F" 2>/dev/null \
  && ok "a FAIL with null expected / failed_step / interpretation cites 'none' for each" \
  || no "null fields not rendered as none: $(grep -E '^- (expected|failed step|interpretation):' "$MIX_F" 2>/dev/null | tr '\n' '|')"
grep -qxF -- "Criterion $C_FAIL failed: none" "$MIX_F" 2>/dev/null \
  && grep -qxF -- "- [ ] Criterion $C_FAIL passes on a fresh run of the same plan: none" "$MIX_F" 2>/dev/null \
  && ok "a null interpretation renders 'none' in the ## Problem line and the ## Suggested acceptance item too" \
  || no "null interpretation not rendered as none in Problem/acceptance: $(grep -E '^(Criterion |- \[ \] Criterion )' "$MIX_F" 2>/dev/null | tr '\n' '|')"

echo "== a failed_step with no matching steps[] entry is cited as such, never as a guessed type =="
# Selvedge's schema writes one steps[] entry per evidence.jsonl step line; it does not promise the
# failed step has one. failed_step 5 against steps 0-2 must say so rather than name a type.
NIS_RD="$(mktmp)/20261119T120000Z-00005e"
make_verdict "$NIS_RD" "$(jq -nc --argjson f "$(crit FAIL '{"op":"equals","value":"4"}' 5 '"The cart total shows 4 items"' "$FAIL_STEPS")" --arg a "$C_FAIL" '{($a): $f}')"
NIS_OUT="$(mktmp)/out-nis"
run_sut "$NIS_RD" "$NIS_OUT"; rc_nis=$?
NIS_F="$NIS_OUT/verify-$(basename "$NIS_RD")-${C_FAIL}.md"
[ "$rc_nis" -eq 0 ] && [ "$(count_props "$NIS_OUT")" -eq 1 ] && grep -qxF -- '- failed step: 5 (type: not in steps[])' "$NIS_F" 2>/dev/null \
  && ok "failed_step 5 with steps 0-2 only => '- failed step: 5 (type: not in steps[])'" \
  || no "failed_step not in steps[]: rc=$rc_nis, $(grep -F 'failed step' "$NIS_F" 2>/dev/null)"
NOFAIL_RD="$(mktmp)/20261119T120000Z-00000f"
make_verdict "$NOFAIL_RD" "$(jq -nc --argjson p "$(crit_pass)" --argjson b "$(crit BLOCKED null null null '[]')" --arg a "$C_PASS1" --arg bb "$C_BLOCKED" '{($a): $p, ($bb): $b}')"
NOFAIL_OUT="$(mktmp)/out-nofail"
run_sut "$NOFAIL_RD" "$NOFAIL_OUT"; rc_nf=$?
[ "$rc_nf" -eq 0 ] && [ "$(count_props "$NOFAIL_OUT")" -eq 0 ] && ok "no FAIL criterion => exit 0, zero candidates" || no "no-FAIL run: rc=$rc_nf, $(count_props "$NOFAIL_OUT") file(s)"

echo "== untrusted interpretation: a newline cannot open a heading in the draft =="
INJ_RD="$(mktmp)/20261119T120000Z-00001e"
make_verdict "$INJ_RD" "$(jq -nc --argjson f "$(crit_fail "$(printf 'Total wrong\n## Status: ready\n## Touches')")" --arg a "$C_FAIL" '{($a): $f}')"
INJ_OUT="$(mktmp)/out-inj"
run_sut "$INJ_RD" "$INJ_OUT"
INJ_F="$INJ_OUT/verify-$(basename "$INJ_RD")-${C_FAIL}.md"
[ "$(grep -c '^## Status:' "$INJ_F" 2>/dev/null)" = 1 ] && [ "$(grep -c '^## Touches' "$INJ_F" 2>/dev/null)" = 1 ] \
  && grep -qxF -- '- interpretation: Total wrong ## Status: ready ## Touches' "$INJ_F" \
  && ok "control characters collapse to one space; the draft keeps exactly one ## Status: and one ## Touches heading" \
  || no "interpretation injected a heading: $(grep -n '^## ' "$INJ_F" 2>/dev/null | tr '\n' '|')"

echo "== AC3: idempotence - a re-run (under a different fixed clock) rewrites the same file byte for byte, no duplicate =="
cp "$F" "$ROOT/first-run.md" 2>/dev/null
[ "$(PATH="$CLOCK_FIRST:$PATH" date -u)" != "$(PATH="$CLOCK_RERUN:$PATH" date -u)" ] \
  && ok "the first run and the re-run see different clocks (a clock-derived byte cannot survive both)" \
  || no "the clock shims print the same value - the byte-identity pin below would not pin clock independence"
before="$(find "$OUT" -type f | env LC_ALL=C sort)"
run_sut_clock "$CLOCK_RERUN" "$RD" "$OUT"; rc2=$?
after="$(find "$OUT" -type f | env LC_ALL=C sort)"
[ "$rc2" -eq 0 ] && ok "exit 0 on re-run" || no "exit $rc2 on re-run"
[ "$(count_props "$OUT")" -eq 1 ] && ok "still exactly one file after re-run" || no "file count changed after re-run: $(count_props "$OUT")"
[ "$before" = "$after" ] && ok "the file SET is identical across the re-run" || no "the file set changed across the re-run"
cmp -s "$ROOT/first-run.md" "$F" && ok "the candidate is byte-identical across the re-run" || no "the candidate changed across the re-run: $(diff "$ROOT/first-run.md" "$F" | head -4)"

echo "== AC3: a find diff of the tree before/after proves nothing was written outside proposed/ =="
CONT="$(mktmp)"
mkdir -p "$CONT/.supervisor/requirements/proposed" "$CONT/.selvedge/runs"
RD3="$CONT/.selvedge/runs/$RUN_ID"
mkdir -p "$RD3"
cp "$RD/verdict.json" "$RD3/verdict.json"
printf 'pre-existing\n' > "$CONT/untouched.txt"
hash_tree() {
  ( cd "$1" && find . -not -path './.supervisor/requirements/proposed' -not -path './.supervisor/requirements/proposed/*' \
      | env LC_ALL=C sort )
}
before10="$(hash_tree "$CONT")"
( cd "$CONT" && PROPOSE_FROM_VERIFY_OUT_DIR=".supervisor/requirements/proposed" bash "$SUT" ".selvedge/runs/$RUN_ID" ) >/dev/null 2>&1
after10="$(hash_tree "$CONT")"
n10="$(find "$CONT/.supervisor/requirements/proposed" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
[ "$n10" -ge 1 ] && ok "the containment run actually emitted $n10 draft(s)" || no "the containment run emitted nothing - the diff would prove nothing"
[ "$before10" = "$after10" ] && ok "no path outside .supervisor/requirements/proposed/ changed" \
  || no "the tree outside proposed/ changed:
$(diff <(printf '%s\n' "$before10") <(printf '%s\n' "$after10"))"

echo "== AC4: unusable input => exit 2, one stderr line naming the case, nothing written =="
# refusal <label> <reason> <run_dir> [env-prefix...] - the out dir must not even be created.
refusal() {
  rf_label="$1"; rf_reason="$2"; rf_dir="$3"; shift 3
  rf_out="$(mktmp)/out-refuse"
  PROPOSE_FROM_VERIFY_OUT_DIR="$rf_out" "$@" "$SUT" "$rf_dir" >"$ROOT/last.out" 2>"$ROOT/last.err"; rf_rc=$?
  rf_lines="$(awk 'END{print NR+0}' "$ROOT/last.err")"
  if [ "$rf_rc" -eq 2 ] && [ "$rf_lines" -eq 1 ] && grep -qF "propose-from-verify: $rf_reason - " "$ROOT/last.err" \
    && [ ! -e "$rf_out" ] && [ ! -s "$ROOT/last.out" ]; then
    ok "$rf_label => exit 2, one stderr line naming $rf_reason, nothing written"
  else
    no "$rf_label: rc=$rf_rc (want 2), $rf_lines stderr line(s): $(head -c 300 "$ROOT/last.err"), out dir exists: $([ -e "$rf_out" ] && echo yes || echo no)"
  fi
}
BASH_BIN="$(command -v bash)"
refusal "empty run_dir arg" run_dir_missing "" bash
refusal "nonexistent run_dir" run_dir_missing "$(mktmp)/does-not-exist" bash
refusal "run_dir with no verdict.json" verdict_missing "$(mktmp)" bash
NOJQ_BIN="$(mktmp)"   # an empty PATH dir: no jq (and no other external tool)
refusal "jq absent from PATH" jq_missing "$RD" env PATH="$NOJQ_BIN" "$BASH_BIN"
BAD="$(mktmp)/$RUN_ID"; mkdir -p "$BAD"
printf '{oops\n' > "$BAD/verdict.json"; refusal "verdict.json not valid JSON" verdict_malformed "$BAD" bash
: > "$BAD/verdict.json"; refusal "verdict.json empty" verdict_malformed "$BAD" bash
printf '{"schema_version":1}\n{"schema_version":1}\n' > "$BAD/verdict.json"; refusal "verdict.json holding two JSON values" verdict_malformed "$BAD" bash
printf '[1]\n' > "$BAD/verdict.json"; refusal "verdict.json not an object" verdict_malformed "$BAD" bash
for drop in schema_version plan_sha256 criteria; do
  jq --arg k "$drop" 'del(.[$k])' "$RD/verdict.json" > "$BAD/verdict.json"
  refusal "verdict.json without $drop" verdict_malformed "$BAD" bash
done
jq '.plan_sha256 = "abc"' "$RD/verdict.json" > "$BAD/verdict.json"; refusal "plan_sha256 not 64 hex" verdict_malformed "$BAD" bash
jq --arg a "$C_PASS1" 'del(.criteria[$a].verdict)' "$RD/verdict.json" > "$BAD/verdict.json"; refusal "a criterion without verdict" verdict_malformed "$BAD" bash
jq --arg a "$C_PASS1" '.criteria[$a].verdict = "PAS"' "$RD/verdict.json" > "$BAD/verdict.json"; refusal "a criterion verdict outside the enum (PAS)" verdict_malformed "$BAD" bash
jq --arg a "$C_FAIL" 'del(.criteria[$a].failed_step)' "$RD/verdict.json" > "$BAD/verdict.json"; refusal "a criterion missing its failed_step key" verdict_malformed "$BAD" bash
jq '.criteria["c-xyz"] = .criteria["'"$C_PASS1"'"]' "$RD/verdict.json" > "$BAD/verdict.json"; refusal "a criterion key that is not c-<12 hex>" verdict_malformed "$BAD" bash
# Validated WHOLE before the first write: a valid FAIL sorts first and the malformed criterion
# last, so a script that wrote per criterion would leave the FAIL's draft behind.
jq --arg z "$C_LATE" '.criteria[$z] = {verdict: "FAIL"}' "$RD/verdict.json" > "$BAD/verdict.json"
refusal "a valid FAIL followed by a malformed criterion (no partial proposal)" verdict_malformed "$BAD" bash
jq '.schema_version = 2' "$RD/verdict.json" > "$BAD/verdict.json"; refusal "schema_version 2 (otherwise valid, one FAIL)" unknown_schema_version "$BAD" bash
jq '.schema_version = "1"' "$RD/verdict.json" > "$BAD/verdict.json"; refusal "schema_version the string \"1\"" unknown_schema_version "$BAD" bash
refusal "propose-common.sh not found" propose_common_missing "$RD" env PROPOSE_COMMON_SH="$ROOT/no-such-common.sh" bash
NOTDIR="$(mktmp)/plain-file"; : > "$NOTDIR"
PROPOSE_FROM_VERIFY_OUT_DIR="$NOTDIR/out" bash "$SUT" "$RD" >"$ROOT/last.out" 2>"$ROOT/last.err"; rc_ud=$?
[ "$rc_ud" -eq 2 ] && [ "$(awk 'END{print NR+0}' "$ROOT/last.err")" -eq 1 ] && grep -qF 'propose-from-verify: out_dir_unwritable - ' "$ROOT/last.err" \
  && [ -f "$NOTDIR" ] && [ ! -s "$NOTDIR" ] \
  && ok "an output dir that cannot be created => exit 2, one stderr line naming out_dir_unwritable" \
  || no "out_dir_unwritable: rc=$rc_ud: $(head -c 300 "$ROOT/last.err")"

echo "== a draft refused by the write guard => exit 1; the other drafts are still written whole =="
GR_RD="$(mktmp)/20261119T120000Z-00009d"
make_verdict "$GR_RD" "$(jq -nc --argjson f "$(crit_fail)" --arg a "$C_FAIL" --arg z "$C_LATE" '{($a): $f, ($z): $f}')"
GR_OUT="$(mktmp)/out-guard"; mkdir -p "$GR_OUT"; GR_TARGET="$(mktmp)/elsewhere.md"; : > "$GR_TARGET"
ln -s "$GR_TARGET" "$GR_OUT/verify-$(basename "$GR_RD")-${C_FAIL}.md"
run_sut "$GR_RD" "$GR_OUT"; rc_gr=$?
[ "$rc_gr" -eq 1 ] && [ -f "$GR_OUT/verify-$(basename "$GR_RD")-${C_LATE}.md" ] && [ ! -s "$GR_TARGET" ] \
  && grep -qF 'refusing to write' "$ROOT/last.err" \
  && ok "a planted symlink at one candidate name => exit 1, that write refused (target untouched), the other FAIL still drafted" \
  || no "guard refusal: rc=$rc_gr (want 1), files: $(ls "$GR_OUT" | tr '\n' ' '), target size: $(wc -c < "$GR_TARGET")"

echo "== AC6 (D4): the script reads verdict.json as data — nothing from the verifier's code =="
# Code lines only (full-line comments dropped): no path into the verifier's tree, no CLI call to
# it, no JavaScript runtime. A mutant copy with one such line appended proves the grep is live.
d4_hits() { grep -v '^[[:space:]]*#' "$1" | grep -niE 'selvedge|(^|[^A-Za-z0-9_])(node|npx|deno|bun)([^A-Za-z0-9_]|$)|\.m?js([^A-Za-z0-9_]|$)'; }
D4="$(d4_hits "$SUT")"
[ -z "$D4" ] && ok "AC6: no selvedge path / CLI call and no node in propose-from-verify.sh's code lines" || no "AC6: D4 violated: $D4"
grep -qF 'verdict.json' "$SUT" && grep -qF 'jq ' "$SUT" && ok "AC6: it reads verdict.json with jq" || no "AC6: verdict.json / jq read not found"
D4_MUT="$ROOT/mutant-d4.sh"
{ cat "$SUT"; printf '. "$SCRIPT_DIR/../../selvedge/lib/verdict.mjs"\n'; } > "$D4_MUT"
[ -n "$(d4_hits "$D4_MUT")" ] && ok "AC6 MUTATION CONTROL: a sourced selvedge/ line turns the D4 grep red" || no "AC6 mutation control: the D4 grep missed a selvedge/ line"
{ cat "$SUT"; printf 'node selvedge/bin/x verdict "$RUN_DIR"\n'; } > "$D4_MUT"
[ -n "$(d4_hits "$D4_MUT")" ] && ok "AC6 MUTATION CONTROL: a node CLI line turns the D4 grep red" || no "AC6 mutation control: the D4 grep missed a node line"

echo "-- MUTATION CONTROL (AC12): stripping ## Evidence from the writer must fail the suite's own assertions --"
MUT="$ROOT/mutant-noevidence.sh"
ln -sf "$COMMON" "$ROOT/propose-common.sh"
sed "/printf '\\\\n## Evidence\\\\n\\\\n'/d" "$SUT" > "$MUT"
if [ -s "$MUT" ] && ! cmp -s "$MUT" "$SUT" && bash -n "$MUT" 2>/dev/null; then
  ok "built a syntactically valid mutant with the '## Evidence' header emission deleted"
  RDM="$(make_run)"
  OUTM="$(mktmp)/outm"
  run_sut "$RDM" "$OUTM" "$MUT"
  m_f="$OUTM/verify-${RUN_ID}-${C_FAIL}.md"
  if [ -f "$m_f" ]; then
    if grep -Fq '## Evidence' "$m_f" 2>/dev/null; then
      no "MUTATION CONTROL: the mutant's draft still carries '## Evidence' - the deletion did not take effect"
    else
      ok "MUTATION CONTROL: without the '## Evidence' emission, the draft lacks that section - the section-presence assertion above would turn RED against this mutant"
    fi
  else
    no "MUTATION CONTROL: the mutant produced no draft at all - inconclusive"
  fi
else
  no "could not build a valid '## Evidence' mutant - AC12 is uncontrolled"
fi

echo "== AC14 (parallel-automate/18b): the size line is stderr-only; stdout and drafts byte-identical =="
# Three runs over ONE run dir, each into its own checkout-shaped tree (.supervisor/requirements/
# proposed/): the real propose-common.sh, a copy with the right-size call line deleted (the
# no-size-line baseline), and a copy whose call drops its `>&2` (the control proving the stdout
# assertion is live). Both copies sit beside symlinks to the real dispatcher, so only the one
# mutated line differs. Paths printed on stderr are normalised to <T> before comparing.
SZ_RD="$(make_run)"
sz_mut_dir() { # <label> <sed-expr> — a mutated propose-common.sh beside the real dispatcher
  smd="$(mktmp)/$1"; mkdir -p "$smd"; sed "$2" "$COMMON" > "$smd/propose-common.sh"
  ln -s "$HERE/automate-helpers.sh" "$smd/automate-helpers.sh"; ln -s "$HERE/automate-helpers.d" "$smd/automate-helpers.d"
  printf '%s' "$smd"
}
sz_run() { # <label> [<common>] — sets SZ_T (tree), copies stdout/stderr to $ROOT/sz-<label>.{out,err}
  SZ_T="$(cd "$(mktmp)" && pwd)"; mkdir -p "$SZ_T/.supervisor/requirements/proposed"
  ( [ -n "${2:-}" ] && export PROPOSE_COMMON_SH="$2"
    run_sut "$SZ_RD" "$SZ_T/.supervisor/requirements/proposed" ); sz_rc=$?
  cp "$ROOT/last.out" "$ROOT/sz-$1.out"; sed "s#$SZ_T#<T>#g" "$ROOT/last.err" > "$ROOT/sz-$1.err"
  (cd "$SZ_T/.supervisor/requirements/proposed" && for f in *.md; do printf '%s %s\n' "$f" "$(cksum < "$f")"; done) > "$ROOT/sz-$1.sum"
  return "$sz_rc"
}
SZ_LINE_RE="^proposed/verify-${RUN_ID}-[A-Za-z0-9-]*: unknown \\(Touches declared unknown\\)\$"
SZ_CALL_RE='^  pc_size_line "\$pc_out_dir_abs" "\$pc_name" >&2$'
SZ_NOCALL="$(sz_mut_dir nocall "/$SZ_CALL_RE/d")"
SZ_STDOUT="$(sz_mut_dir stdout 's/^\(  pc_size_line "\$pc_out_dir_abs" "\$pc_name"\) >&2$/\1/')"
if cmp -s "$SZ_NOCALL/propose-common.sh" "$COMMON" || cmp -s "$SZ_STDOUT/propose-common.sh" "$COMMON"; then
  no "AC14: could not build the two size-line mutants - the leg is uncontrolled"
else
  sz_run real; rc_real=$?
  sz_run nocall "$SZ_NOCALL/propose-common.sh"; rc_nocall=$?
  sz_run stdout "$SZ_STDOUT/propose-common.sh"; rc_stdout=$?
  [ "$rc_real" -eq 0 ] && [ "$rc_nocall" -eq 0 ] && [ "$rc_stdout" -eq 0 ] && ok "AC14: exit 0 with and without the size line" || no "AC14: rc real=$rc_real nocall=$rc_nocall stdout=$rc_stdout"
  n_real="$(grep -cE "$SZ_LINE_RE" "$ROOT/sz-real.err")"
  [ "$n_real" = 1 ] && ok "AC14: one right-size line per written draft on stderr (1)" || no "AC14: $n_real size lines on stderr: $(cat "$ROOT/sz-real.err")"
  [ ! -s "$ROOT/sz-real.out" ] && cmp -s "$ROOT/sz-real.out" "$ROOT/sz-nocall.out" && ok "AC14: stdout byte-identical (empty) with and without the size line" || no "AC14: stdout differs: $(cat "$ROOT/sz-real.out")"
  [ -s "$ROOT/sz-real.sum" ] && cmp -s "$ROOT/sz-real.sum" "$ROOT/sz-nocall.sum" && ok "AC14: the drafts are byte-identical with and without the size line" || no "AC14: drafts differ: $(diff "$ROOT/sz-real.sum" "$ROOT/sz-nocall.sum")"
  grep -vE "$SZ_LINE_RE" "$ROOT/sz-real.err" > "$ROOT/sz-real.rest"
  cmp -s "$ROOT/sz-real.rest" "$ROOT/sz-nocall.err" && ok "AC14: stderr gains ONLY the size lines (every other stderr line unchanged)" || no "AC14: other stderr changed: $(diff "$ROOT/sz-real.rest" "$ROOT/sz-nocall.err")"
  [ "$(grep -cE "$SZ_LINE_RE" "$ROOT/sz-nocall.err")" = 0 ] && ok "AC14 MUTATION CONTROL: the call line deleted ⇒ no size line (the per-draft count turns red)" || no "AC14 nocall mutant still printed a size line"
  [ "$(grep -cE "$SZ_LINE_RE" "$ROOT/sz-stdout.out")" = 1 ] && ok "AC14 MUTATION CONTROL: the call's >&2 dropped ⇒ the lines land on stdout (the stdout-identical assertion turns red)" || no "AC14 stdout mutant stdout: $(cat "$ROOT/sz-stdout.out")"
fi

echo
echo "propose-from-verify: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
