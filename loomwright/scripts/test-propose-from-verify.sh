#!/usr/bin/env bash
# test-propose-from-verify.sh - self-tests for propose-from-verify.sh, the VERIFY basis of
# `/propose`. HERMETIC: every fixture is built in a mktemp -d tree OUTSIDE the repo root; nothing
# here depends on a real `.supervisor/verify/` run existing. Exit 0 = all pass, 1 = any failure.
# Registered automatically by ci.yml's test-*.sh glob.

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

RUN_ID="verify-20260915T000000Z-example"

# make_evidence <dir> - writes evidence.jsonl with run_start + 2 FAIL(REAL_BUG) + 1 BLOCKED +
# 1 DISCOVERY_GAP FAIL (must NOT draft) + 1 issue line. Returns the run dir.
make_run() {
  mr_dir="$(mktmp)/$RUN_ID"
  mkdir -p "$mr_dir"
  cat > "$mr_dir/evidence.jsonl" << EOF
{"schema_version":1,"ts":"2026-09-15T00:00:00Z","run_id":"$RUN_ID","event":"run_start","ticket_path":".supervisor/requirements/example/01.md","ticket_kind":"requirement","branch":"feature/x","head_sha":"abc123","base_sha":"def456","env_contract_hash":null}
{"schema_version":1,"ts":"2026-09-15T00:00:01Z","run_id":"$RUN_ID","event":"ac","ac_id":"AC1","text":"AC1 text here","scope":"ticket","verdict":"FAIL","classification":"REAL_BUG","reason":"observed bug one","steps":[],"artifacts":["artifacts/AC1/a.png"]}
{"schema_version":1,"ts":"2026-09-15T00:00:02Z","run_id":"$RUN_ID","event":"ac","ac_id":"AC2","text":"AC2 text here","scope":"ticket","verdict":"BLOCKED","classification":"ENVIRONMENT_ISSUE","reason":"env broke","steps":[],"artifacts":[]}
{"schema_version":1,"ts":"2026-09-15T00:00:03Z","run_id":"$RUN_ID","event":"ac","ac_id":"AC3","text":"AC3 text here","scope":"ticket","verdict":"FAIL","classification":"DISCOVERY_GAP","reason":"could not author a spec in time","steps":[],"artifacts":[]}
{"schema_version":1,"ts":"2026-09-15T00:00:04Z","run_id":"$RUN_ID","event":"ac","ac_id":"AC4","text":"AC4 text here","scope":"ticket","verdict":"FAIL","classification":"REAL_BUG","reason":"observed bug two","steps":[],"artifacts":[]}
{"schema_version":1,"ts":"2026-09-15T00:00:05Z","run_id":"$RUN_ID","event":"issue","text":"A standalone issue found during the walk","severity":"MEDIUM","artifacts":["artifacts/console.txt"]}
{"schema_version":1,"ts":"2026-09-15T00:00:06Z","run_id":"$RUN_ID","event":"run_end","status":"completed"}
EOF
  printf '%s' "$mr_dir"
}

run_sut() {
  rs_dir="$1"; rs_out="$2"; rs_scr="${3:-$SUT}"
  PROPOSE_FROM_VERIFY_OUT_DIR="$rs_out" bash "$rs_scr" "$rs_dir" >"$ROOT/last.out" 2>"$ROOT/last.err"
  return $?
}

count_props() { find "$1" -maxdepth 1 -type f -name '*.md' 2>/dev/null | awk 'END{print NR+0}'; }

echo "== AC1/AC5/AC10: 2 FAIL(REAL_BUG) + 1 BLOCKED + 1 FAIL(DISCOVERY_GAP) + 1 issue => exactly 3 drafts =="
RD="$(make_run)"
OUT="$(mktmp)/out"
run_sut "$RD" "$OUT"; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0" || no "exit $rc"
np="$(count_props "$OUT")"
[ "$np" -eq 3 ] && ok "exactly 3 drafts written ($np)" || no "expected 3 drafts, got $np: $(ls "$OUT" 2>/dev/null)"

AC1_FILE="$(find "$OUT" -maxdepth 1 -name "verify-${RUN_ID}-AC1-*.md" | head -1)"
AC4_FILE="$(find "$OUT" -maxdepth 1 -name "verify-${RUN_ID}-AC4-*.md" | head -1)"
ISSUE_FILE="$(find "$OUT" -maxdepth 1 -name "verify-${RUN_ID}-issue-1-*.md" | head -1)"
AC2_FILE="$(find "$OUT" -maxdepth 1 -name "verify-${RUN_ID}-AC2-*.md" | head -1)"
AC3_FILE="$(find "$OUT" -maxdepth 1 -name "verify-${RUN_ID}-AC3-*.md" | head -1)"

[ -n "$AC1_FILE" ] && ok "AC1 (FAIL/REAL_BUG) drafted" || no "AC1 draft missing"
[ -n "$AC4_FILE" ] && ok "AC4 (FAIL/REAL_BUG) drafted" || no "AC4 draft missing"
[ -n "$ISSUE_FILE" ] && ok "issue #1 drafted" || no "issue draft missing"
[ -z "$AC2_FILE" ] && ok "AC2 (BLOCKED) NOT drafted" || no "AC2 (BLOCKED) was drafted - defect"
[ -z "$AC3_FILE" ] && ok "AC3 (FAIL/DISCOVERY_GAP) NOT drafted" || no "AC3 (FAIL/DISCOVERY_GAP) was drafted - defect"

echo "== AC1: all four required sections, and ## Evidence cites a real line resolving to that ac_id =="
for f in "$AC1_FILE" "$AC4_FILE" "$ISSUE_FILE"; do
  [ -n "$f" ] && [ -f "$f" ] || { no "cannot check sections - file missing"; continue; }
  b="$(basename "$f")"
  for sec in '## Problem' '## Evidence' '## Suggested acceptance' '## Status: proposed'; do
    grep -Fq "$sec" "$f" 2>/dev/null && ok "$b carries '$sec'" || no "$b missing '$sec'"
  done
done

if [ -n "$AC1_FILE" ]; then
  ln1="$(grep -o 'evidence.jsonl line [0-9]*' "$AC1_FILE" | grep -o '[0-9]*' | head -1)"
  if [ -n "$ln1" ]; then
    resolved="$(sed -n "${ln1}p" "$RD/evidence.jsonl" | jq -r '.ac_id // empty' 2>/dev/null)"
    [ "$resolved" = "AC1" ] && ok "AC1's cited evidence.jsonl line $ln1 resolves to ac_id AC1" \
      || no "AC1's cited line $ln1 resolves to ac_id '$resolved', not AC1"
  else
    no "AC1 draft cites no evidence.jsonl line number"
  fi
  grep -Fq 'artifacts/AC1/a.png' "$AC1_FILE" && ok "AC1 draft cites its artifact path" || no "AC1 draft omits its artifact path"
  grep -Fq '.supervisor/requirements/example/01.md' "$AC1_FILE" && ok "AC1 draft cites the ticket path" || no "AC1 draft omits the ticket path"
  grep -Fq 'abc123' "$AC1_FILE" && ok "AC1 draft cites head_sha" || no "AC1 draft omits head_sha"
  grep -Fq 'classification: REAL_BUG' "$AC1_FILE" && ok "AC1 draft cites classification REAL_BUG" || no "AC1 draft omits classification"
fi
if [ -n "$ISSUE_FILE" ]; then
  lni="$(grep -o 'evidence.jsonl line [0-9]*' "$ISSUE_FILE" | grep -o '[0-9]*' | head -1)"
  if [ -n "$lni" ]; then
    ev="$(sed -n "${lni}p" "$RD/evidence.jsonl" | jq -r '.event // empty' 2>/dev/null)"
    [ "$ev" = "issue" ] && ok "issue draft's cited line $lni resolves to an issue event" \
      || no "issue draft's cited line $lni resolves to event '$ev', not issue"
  else
    no "issue draft cites no evidence.jsonl line number"
  fi
fi

echo "== AC2: summary.md's derived ## Proposals section states the expectation (evidence-driven) =="
HELPERS="$HERE/verify-helpers.sh"
if [ -f "$HELPERS" ]; then
  bash "$HELPERS" summary-build "$RD" >/dev/null 2>&1
  if [ -f "$RD/summary.md" ]; then
    grep -Fq 'draft(s) expected' "$RD/summary.md" && ok "summary.md's ## Proposals states drafts are expected" \
      || no "summary.md's ## Proposals does not state drafts are expected"
  else
    no "summary-build did not produce summary.md"
  fi
  BLK="$(mktmp)/rd2"; mkdir -p "$BLK"
  cat > "$BLK/evidence.jsonl" << EOF
{"schema_version":1,"ts":"2026-09-15T00:00:00Z","run_id":"verify-blocked-only","event":"run_start","ticket_path":"t.md","ticket_kind":"requirement","branch":"b","head_sha":"h","base_sha":"d","env_contract_hash":null}
{"schema_version":1,"ts":"2026-09-15T00:00:01Z","run_id":"verify-blocked-only","event":"ac","ac_id":"AC1","text":"t1","scope":"ticket","verdict":"BLOCKED","classification":"ENVIRONMENT_ISSUE","reason":"r","steps":[],"artifacts":[]}
EOF
  bash "$HELPERS" summary-build "$BLK" >/dev/null 2>&1
  BLK_OUT="$(mktmp)/out2"
  run_sut "$BLK" "$BLK_OUT"
  [ "$(count_props "$BLK_OUT")" -eq 0 ] && ok "a BLOCKED-only run writes no draft" || no "a BLOCKED-only run wrote a draft"
  grep -Fq 'no draft is expected' "$BLK/summary.md" 2>/dev/null && ok "summary.md states no draft was written for a BLOCKED-only run" \
    || no "summary.md does not state 'no draft is expected' for a BLOCKED-only run"
else
  no "verify-helpers.sh not found - AC2 cannot be evaluated"
fi

echo "== AC-supersede: a later PASS for the same ac_id must suppress a re-verified FAIL's draft =="
# The script computes latest_by(.ac_id) BEFORE filtering (VERIFY_EVIDENCE's own "latest-per-ac_id"
# rule) - a FAIL that was later re-verified as PASS must never still produce a draft from the
# superseded FAIL line. Two ac lines for the SAME ac_id: first FAIL/REAL_BUG, then a later PASS.
SUPERSEDE_RUN_ID="verify-20260915T000000Z-supersede"
SUP_DIR="$(mktmp)/$SUPERSEDE_RUN_ID"
mkdir -p "$SUP_DIR"
cat > "$SUP_DIR/evidence.jsonl" << EOF
{"schema_version":1,"ts":"2026-09-15T00:00:00Z","run_id":"$SUPERSEDE_RUN_ID","event":"run_start","ticket_path":".supervisor/requirements/example/01.md","ticket_kind":"requirement","branch":"feature/x","head_sha":"abc123","base_sha":"def456","env_contract_hash":null}
{"schema_version":1,"ts":"2026-09-15T00:00:01Z","run_id":"$SUPERSEDE_RUN_ID","event":"ac","ac_id":"AC1","text":"AC1 text here","scope":"ticket","verdict":"FAIL","classification":"REAL_BUG","reason":"observed bug one","steps":[],"artifacts":["artifacts/AC1/a.png"]}
{"schema_version":1,"ts":"2026-09-15T00:00:02Z","run_id":"$SUPERSEDE_RUN_ID","event":"ac","ac_id":"AC1","text":"AC1 text here","scope":"ticket","verdict":"PASS","classification":null,"reason":"resumed and verified for real","steps":[],"artifacts":["artifacts/AC1/pass.png"]}
{"schema_version":1,"ts":"2026-09-15T00:00:03Z","run_id":"$SUPERSEDE_RUN_ID","event":"run_end","status":"completed"}
EOF
SUP_OUT="$(mktmp)/out-supersede"
run_sut "$SUP_DIR" "$SUP_OUT"; rc_sup=$?
[ "$rc_sup" -eq 0 ] && ok "AC-supersede: exit 0" || no "AC-supersede: exit $rc_sup"
SUP_AC1_FILE="$(find "$SUP_OUT" -maxdepth 1 -name "verify-${SUPERSEDE_RUN_ID}-AC1-*.md" 2>/dev/null | head -1)"
[ -z "$SUP_AC1_FILE" ] && ok "AC-supersede: no draft for AC1 - the later PASS supersedes the earlier FAIL" \
  || no "AC-supersede: a draft was written for AC1 despite its later PASS - $SUP_AC1_FILE"
[ "$(count_props "$SUP_OUT")" -eq 0 ] && ok "AC-supersede: zero drafts written for this run" \
  || no "AC-supersede: expected zero drafts, got $(count_props "$SUP_OUT"): $(ls "$SUP_OUT" 2>/dev/null)"

echo "== AC3/AC10: idempotency - re-running yields the same 3 files, no duplicates =="
before="$(find "$OUT" -type f | LC_ALL=C sort)"
run_sut "$RD" "$OUT"; rc2=$?
after="$(find "$OUT" -type f | LC_ALL=C sort)"
[ "$rc2" -eq 0 ] && ok "exit 0 on re-run" || no "exit $rc2 on re-run"
[ "$(count_props "$OUT")" -eq 3 ] && ok "still exactly 3 files after re-run" || no "file count changed after re-run: $(count_props "$OUT")"
[ "$before" = "$after" ] && ok "the file SET is byte-identical (paths) across the re-run" \
  || no "the file set changed across the re-run"

echo "== AC10: a find diff of the tree before/after proves nothing was written outside proposed/ =="
CONT="$(mktmp)"
mkdir -p "$CONT/.supervisor/requirements/proposed" "$CONT/.supervisor/verify"
RD3="$CONT/.supervisor/verify/$RUN_ID"
mkdir -p "$RD3"
cp "$RD/evidence.jsonl" "$RD3/evidence.jsonl"
printf 'pre-existing\n' > "$CONT/untouched.txt"
hash_tree() {
  ( cd "$1" && find . -not -path './.supervisor/requirements/proposed' -not -path './.supervisor/requirements/proposed/*' \
      -not -path "./.supervisor/verify/$RUN_ID/summary.md" \
      | LC_ALL=C sort )
}
before10="$(hash_tree "$CONT")"
( cd "$CONT" && PROPOSE_FROM_VERIFY_OUT_DIR=".supervisor/requirements/proposed" bash "$SUT" ".supervisor/verify/$RUN_ID" ) >/dev/null 2>&1
after10="$(hash_tree "$CONT")"
n10="$(find "$CONT/.supervisor/requirements/proposed" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
[ "$n10" -ge 1 ] && ok "the containment run actually emitted $n10 draft(s)" || no "the containment run emitted nothing - the diff would prove nothing"
[ "$before10" = "$after10" ] && ok "no path outside .supervisor/requirements/proposed/ (and the excluded summary.md) changed" \
  || no "the tree outside proposed/ changed:
$(diff <(printf '%s\n' "$before10") <(printf '%s\n' "$after10"))"

echo "== AC11: send-webhook.sh is invoked at most 3 times across a run with 5 FAILs (stub counts calls) =="
# verify-helpers.sh resolves its siblings as "$HERE/<script>" where HERE is bash's own
# dirname-of-$0 (NOT a PATH lookup) - so a PATH-only stub is never reached. Instead, invoke a
# COPY of verify-helpers.sh from a stub directory that ALSO holds a real validator symlink (so
# $HERE resolves to the stub dir, and $HERE/send-webhook.sh resolves to the stub) plus the real
# validate-verify-evidence.py (a symlink) so evidence-append still validates correctly.
STUBDIR="$(mktmp)"
CALLLOG="$STUBDIR/calls.log"
: > "$CALLLOG"
cat > "$STUBDIR/send-webhook.sh" << STUBEOF
#!/usr/bin/env bash
echo "\$@" >> "$CALLLOG"
exit 0
STUBEOF
chmod +x "$STUBDIR/send-webhook.sh"
ln -sf "$HERE/validate-verify-evidence.py" "$STUBDIR/validate-verify-evidence.py"
cp "$HERE/verify-helpers.sh" "$STUBDIR/verify-helpers.sh"

if [ -f "$STUBDIR/verify-helpers.sh" ]; then
  RD5="$(mktmp)/rd5"; mkdir -p "$RD5"
  : > "$RD5/.notify-enabled"
  TS="2026-09-15T00:00:00Z"
  jq -cn --arg ts "$TS" '{schema_version:1, ts:$ts, run_id:"verify-fivefail", event:"run_start", ticket_path:"t.md", ticket_kind:"requirement", branch:"b", head_sha:"h", base_sha:"d", env_contract_hash:null}' \
    | LOOMWRIGHT_WEBHOOK_URL=test bash "$STUBDIR/verify-helpers.sh" evidence-append "$RD5" - >/dev/null 2>&1
  i=1
  while [ "$i" -le 5 ]; do
    jq -cn --arg ts "$TS" --arg id "AC$i" '{schema_version:1, ts:$ts, run_id:"verify-fivefail", event:"ac", ac_id:$id, text:"t", scope:"ticket", verdict:"FAIL", classification:"REAL_BUG", reason:"r", steps:[], artifacts:[]}' \
      | LOOMWRIGHT_WEBHOOK_URL=test bash "$STUBDIR/verify-helpers.sh" evidence-append "$RD5" - >/dev/null 2>&1
    i=$((i+1))
  done
  jq -cn --arg ts "$TS" '{schema_version:1, ts:$ts, run_id:"verify-fivefail", event:"run_end", status:"completed"}' \
    | LOOMWRIGHT_WEBHOOK_URL=test bash "$STUBDIR/verify-helpers.sh" evidence-append "$RD5" - >/dev/null 2>&1
  ncalls="$(awk 'END{print NR+0}' "$CALLLOG")"
  [ "$ncalls" -le 3 ] && ok "send-webhook.sh invoked $ncalls time(s) across 5 FAILs (<= 3, proving 'first FAIL only')" \
    || no "send-webhook.sh invoked $ncalls times - expected at most 3"
  [ "$ncalls" -ge 1 ] && ok "the stub actually recorded >=1 call - the <=3 assertion is not vacuous" \
    || no "the stub recorded zero calls - stubbing may not have taken effect"
else
  no "verify-helpers.sh not found - AC11 cannot be evaluated"
fi

echo "== AC8-notify: a needs_auth pause fires BOTH send-webhook.sh and notify-desktop.sh =="
# verify-helpers.sh resolves BOTH siblings the same way (dirname-of-$0, never a PATH lookup), so
# staging fake copies of send-webhook.sh AND notify-desktop.sh beside a copy of verify-helpers.sh
# reaches both call sites verify_notify_once fires for a needs_auth pause.
STUBDIR2="$(mktmp)"
WCALLLOG="$STUBDIR2/webhook-calls.log"; : > "$WCALLLOG"
DCALLLOG="$STUBDIR2/desktop-calls.log"; : > "$DCALLLOG"
cat > "$STUBDIR2/send-webhook.sh" << STUBEOF2
#!/usr/bin/env bash
echo "\$@" >> "$WCALLLOG"
exit 0
STUBEOF2
chmod +x "$STUBDIR2/send-webhook.sh"
cat > "$STUBDIR2/notify-desktop.sh" << STUBEOF2
#!/usr/bin/env bash
cat >> "$DCALLLOG"
exit 0
STUBEOF2
chmod +x "$STUBDIR2/notify-desktop.sh"
ln -sf "$HERE/validate-verify-evidence.py" "$STUBDIR2/validate-verify-evidence.py"
cp "$HERE/verify-helpers.sh" "$STUBDIR2/verify-helpers.sh"

if [ -f "$STUBDIR2/verify-helpers.sh" ]; then
  RD6="$(mktmp)/rd6"; mkdir -p "$RD6"
  : > "$RD6/.notify-enabled"
  TS="2026-09-15T00:00:00Z"
  jq -cn --arg ts "$TS" '{schema_version:1, ts:$ts, run_id:"verify-needsauth", event:"run_start", ticket_path:"t.md", ticket_kind:"requirement", branch:"b", head_sha:"h", base_sha:"d", env_contract_hash:null}' \
    | bash "$STUBDIR2/verify-helpers.sh" evidence-append "$RD6" - >/dev/null 2>&1
  jq -cn --arg ts "$TS" '{schema_version:1, ts:$ts, run_id:"verify-needsauth", event:"pause", reason:"needs_auth"}' \
    | bash "$STUBDIR2/verify-helpers.sh" evidence-append "$RD6" - >/dev/null 2>&1
  rc_a8n=$?
  [ "$rc_a8n" -eq 0 ] && ok "AC8-notify: appending the needs_auth pause line still exits 0" || no "AC8-notify: exit $rc_a8n"
  wcalls="$(awk 'END{print NR+0}' "$WCALLLOG")"
  dcalls="$(awk 'END{print NR+0}' "$DCALLLOG")"
  [ "$wcalls" -eq 1 ] && ok "AC8-notify: send-webhook.sh was invoked exactly once for the needs_auth pause" \
    || no "AC8-notify: send-webhook.sh invoked $wcalls time(s), expected exactly 1"
  grep -Fq 'verify_needs_auth' "$WCALLLOG" 2>/dev/null && ok "AC8-notify: the webhook call carries the verify_needs_auth gate-type" \
    || no "AC8-notify: the webhook call does not name --gate-type verify_needs_auth: $(cat "$WCALLLOG")"
  [ "$dcalls" -eq 1 ] && ok "AC8-notify: notify-desktop.sh was ALSO invoked exactly once for the needs_auth pause" \
    || no "AC8-notify: notify-desktop.sh invoked $dcalls time(s), expected exactly 1"
  grep -Fq 'verify_needs_auth' "$DCALLLOG" 2>/dev/null && ok "AC8-notify: the desktop payload carries notification_type verify_needs_auth" \
    || no "AC8-notify: the desktop payload does not name verify_needs_auth: $(cat "$DCALLLOG")"
else
  no "verify-helpers.sh not found - AC8-notify cannot be evaluated"
fi

echo "== AC9: LOOMWRIGHT_WEBHOOK_URL unset -> exit 0, no webhook call, the run is unaffected =="
# Real send-webhook.sh and notify-desktop.sh (symlinked, not faked) beside a copy of
# verify-helpers.sh, so this exercises the ACTUAL fail-safe no-op path rather than a stub that
# assumes it. A curl/wget/nc-denying shim on PATH proves zero network calls were attempted -
# "no webhook call" is observed, not merely inferred from send-webhook.sh's own header comment.
# Run from a FRESH cwd with no .supervisor/config.json or .supervisor/notify-config.json, so
# send-webhook.sh's repo-local-config fallback (its "URL must come from the legacy file" arm)
# cannot accidentally supply a URL the unset env var was meant to withhold.
STUBDIR3="$(mktmp)"
ln -sf "$HERE/send-webhook.sh" "$STUBDIR3/send-webhook.sh"
ln -sf "$HERE/notify-desktop.sh" "$STUBDIR3/notify-desktop.sh"
ln -sf "$HERE/validate-verify-evidence.py" "$STUBDIR3/validate-verify-evidence.py"
cp "$HERE/verify-helpers.sh" "$STUBDIR3/verify-helpers.sh"

NETSHIM="$(mktmp)"
NETLOG="$NETSHIM/network-attempts.txt"; : > "$NETLOG"
for tool in curl wget nc ncat; do
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "%%s %%s\\n" "%s" "$*" >> "%s"\n' "$tool" "$NETLOG"
    printf 'exit 1\n'
  } > "$NETSHIM/$tool"
  chmod +x "$NETSHIM/$tool"
done
CWD9="$(mktmp)"   # a bare directory - no .supervisor/ of any kind

if [ -f "$STUBDIR3/verify-helpers.sh" ]; then
  RD7="$(mktmp)/rd7"; mkdir -p "$RD7"
  : > "$RD7/.notify-enabled"
  TS="2026-09-15T00:00:00Z"
  ( cd "$CWD9" && unset LOOMWRIGHT_WEBHOOK_URL
    jq -cn --arg ts "$TS" '{schema_version:1, ts:$ts, run_id:"verify-nourl", event:"run_start", ticket_path:"t.md", ticket_kind:"requirement", branch:"b", head_sha:"h", base_sha:"d", env_contract_hash:null}' \
      | PATH="$NETSHIM:$PATH" bash "$STUBDIR3/verify-helpers.sh" evidence-append "$RD7" - ) >/dev/null 2>&1
  rc_a9a=$?
  ( cd "$CWD9" && unset LOOMWRIGHT_WEBHOOK_URL
    jq -cn --arg ts "$TS" '{schema_version:1, ts:$ts, run_id:"verify-nourl", event:"pause", reason:"needs_auth"}' \
      | PATH="$NETSHIM:$PATH" bash "$STUBDIR3/verify-helpers.sh" evidence-append "$RD7" - ) >/dev/null 2>&1
  rc_a9b=$?
  [ "$rc_a9a" -eq 0 ] && [ "$rc_a9b" -eq 0 ] && ok "AC9: evidence-append still exits 0 with LOOMWRIGHT_WEBHOOK_URL unset" \
    || no "AC9: rc_a9a=$rc_a9a rc_a9b=$rc_a9b (expected both 0)"
  n_net="$(awk 'END{print NR+0}' "$NETLOG")"
  [ "$n_net" -eq 0 ] && ok "AC9: zero network calls were attempted (no curl/wget/nc invocation) - the webhook call is a true no-op" \
    || no "AC9: $n_net network attempt(s) were made: $(cat "$NETLOG")"
  n_ev="$(awk 'END{print NR+0}' "$RD7/evidence.jsonl" 2>/dev/null)"
  [ "$n_ev" -eq 2 ] && ok "AC9: the run is unaffected - both evidence lines (run_start + pause) were still appended" \
    || no "AC9: expected 2 evidence.jsonl lines, got $n_ev"
  grep -q '"event":"pause"' "$RD7/evidence.jsonl" 2>/dev/null && ok "AC9: the pause/needs_auth line itself is present and intact" \
    || no "AC9: the pause line is missing from evidence.jsonl"
else
  no "verify-helpers.sh not found - AC9 cannot be evaluated"
fi

echo "-- MUTATION CONTROL (AC12): stripping ## Evidence from the writer must fail the suite's own assertions --"
MUT="$ROOT/mutant-noevidence.sh"
ln -sf "$COMMON" "$ROOT/propose-common.sh"
sed "/printf '\\\\n## Evidence\\\\n\\\\n'/d" "$SUT" > "$MUT"
if [ -s "$MUT" ] && ! cmp -s "$MUT" "$SUT" && bash -n "$MUT" 2>/dev/null; then
  ok "built a syntactically valid mutant with the '## Evidence' header emission deleted"
  RDM="$(make_run)"
  OUTM="$(mktmp)/outm"
  run_sut "$RDM" "$OUTM" "$MUT"
  m_ac1="$(find "$OUTM" -maxdepth 1 -name "verify-${RUN_ID}-AC1-*.md" | head -1)"
  if [ -n "$m_ac1" ] && [ -f "$m_ac1" ]; then
    if grep -Fq '## Evidence' "$m_ac1" 2>/dev/null; then
      no "MUTATION CONTROL: the mutant's draft still carries '## Evidence' - the deletion did not take effect"
    else
      ok "MUTATION CONTROL: without the '## Evidence' emission, the draft lacks that section - the AC1 section-presence assertion above would turn RED against this mutant"
    fi
  else
    no "MUTATION CONTROL: the mutant produced no AC1 draft at all - inconclusive"
  fi
else
  no "could not build a valid '## Evidence' mutant - AC12 is uncontrolled"
fi

echo "== usage / fail-safe: missing run_dir, nonexistent run_dir, missing evidence.jsonl all exit 0 =="
run_sut "" "$(mktmp)/o1"; [ $? -eq 0 ] && ok "empty run_dir arg: exit 0" || no "empty run_dir arg: nonzero exit"
run_sut "$(mktmp)/does-not-exist" "$(mktmp)/o2"; [ $? -eq 0 ] && ok "nonexistent run_dir: exit 0" || no "nonexistent run_dir: nonzero exit"
EMPTYRD="$(mktmp)"; run_sut "$EMPTYRD" "$(mktmp)/o3"; [ $? -eq 0 ] && ok "run_dir with no evidence.jsonl: exit 0" || no "run_dir with no evidence.jsonl: nonzero exit"

echo
echo "propose-from-verify: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
