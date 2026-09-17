#!/usr/bin/env bash
# test-orca-mirror.sh — stub-backed self-tests for orca-mirror.sh. `orca` is NOT
# installed on this dev machine (2026-09-11), so every case runs against a STUB
# `orca` placed on PATH that records its own argv (as one JSON array per line,
# via jq -n --args, so embedded newlines/quotes in an arg — e.g. a composed
# multi-line comment — never corrupt the log) and returns canned/controllable
# output for `status --json` and `worktree current --json`.
#
# Covers:
#   A. orca ABSENT on PATH -> exit 0, zero orca invocations attempted at all
#   B. orca present, probe FAILS -> exit 0, only the ONE probe call, no mapped action
#   C. probe-once-per-run: N invocations sharing one cache file -> exactly 1
#      `orca status` call; MUTATION CONTROL proves this is load-bearing (a
#      broken cache-read forces N calls)
#   D. phase_transition argv mapping (default in-progress, to=SELF_HEAL -> in-review)
#   E. pr_created argv mapping (in-review workspace-status + comment containing the URL;
#      real `url` key is primary, legacy `pr_url` key still works as a fallback)
#   F. worker_checkpoint argv mapping (worktree set --comment "<text>")
#   G. session_end argv mapping (completed/completed_with_escalation -> completed, else todo)
#   H. comment preservation: a seeded existing comment survives alongside new content
#   I. unrecognized event type -> silent no-op (no mapped-action calls beyond the probe)
#   J. malformed JSON / missing jq -> exit 0, zero orca invocations
#   K. injection safety: shell-metacharacter-laden text/pr_url survive as ONE argv
#      element verbatim, never executed
#   L. core-cleanliness: grep -rl orca loomwright/ --exclude-dir=adapters returns docs only
#
# Exit 0 = all pass, 1 = any failure. Mirrors this repo's stub-on-PATH testing
# convention (test-webhook.sh's curl stub) and its mutation-control convention
# (test-classify-risk.sh's gated copy-mutate-diff pattern).

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIRROR="$HERE/orca-mirror.sh"
REPO_ROOT="$(cd "$HERE/../../../.." && pwd)"
BASH_BIN="$(command -v bash)"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then ok "$label"; else no "$label (expected [$expected] got [$actual])"; fi
}
assert_true() {
  local label="$1" cond="$2"
  if [ "$cond" = "1" ]; then ok "$label"; else no "$label (condition false)"; fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "test-orca-mirror.sh: jq is required to run this suite"; echo "RESULT: 0 passed, 1 failed"; exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---- stub orca ----------------------------------------------------------------
STUB_DIR="$TMP/stubbin"
mkdir -p "$STUB_DIR"
cat > "$STUB_DIR/orca" <<'STUB'
#!/usr/bin/env bash
# orca stub: records EVERY invocation's argv as one JSON array per line
# (JSONL) in $ORCA_STUB_LOG, and answers known subcommands.
LOG="${ORCA_STUB_LOG:-}"
if [ -n "$LOG" ]; then
  jq -nc '$ARGS.positional' --args -- "$@" >> "$LOG" 2>/dev/null
fi

case "${1:-} ${2:-}" in
  "status --json")
    if [ -n "${ORCA_STUB_STATUS_CALLS:-}" ]; then
      printf '1\n' >> "$ORCA_STUB_STATUS_CALLS"
    fi
    if [ -n "${ORCA_STUB_STATUS_FAIL:-}" ] && [ -f "${ORCA_STUB_STATUS_FAIL}" ]; then
      exit 1
    fi
    printf '{"ok":true}\n'
    exit 0
    ;;
  "worktree current")
    if [ -n "${ORCA_STUB_CURRENT_JSON_FILE:-}" ] && [ -f "$ORCA_STUB_CURRENT_JSON_FILE" ]; then
      cat "$ORCA_STUB_CURRENT_JSON_FILE"
    else
      printf '{}\n'
    fi
    exit 0
    ;;
esac
exit 0
STUB
chmod +x "$STUB_DIR/orca"

run_mirror() {
  # run_mirror <event-json> [extra env assignments already exported by caller]
  PATH="$STUB_DIR:$PATH" "$BASH_BIN" "$MIRROR" "$1"
}

argv_count() {
  # argv_count <log-file> -> number of recorded invocations
  [ -f "$1" ] || { printf '0'; return; }
  wc -l < "$1" | tr -d '[:space:]'
}

argv_matches() {
  # argv_matches <log-file> <jq-filter-testing-one-line-array> -> "1" if ANY
  # recorded line satisfies the filter, else "0"
  [ -f "$1" ] || { printf '0'; return; }
  jq -s "any(.[]; $2)" "$1" 2>/dev/null | grep -q '^true$' && printf '1' || printf '0'
}

echo "==== A: orca ABSENT on PATH -> exit 0, zero attempts ===="
OUT_A="$(PATH="/nonexistent-orca-a" "$BASH_BIN" "$MIRROR" '{"event":"session_end","status":"completed"}' 2>&1)"
RC_A=$?
assert_eq "A rc=0" "0" "$RC_A"
assert_eq "A no stdout/stderr" "" "$OUT_A"

echo ""
echo "==== B: orca present, probe FAILS -> exit 0, only the probe call ===="
LOG_B="$TMP/argv-b.jsonl"
FAIL_MARKER_B="$TMP/fail-b"
: > "$FAIL_MARKER_B"
CACHE_B="$TMP/cache-b"
ORCA_STUB_LOG="$LOG_B" ORCA_STUB_STATUS_FAIL="$FAIL_MARKER_B" LOOMWRIGHT_ORCA_STATUS_CACHE="$CACHE_B" \
  run_mirror '{"event":"session_end","status":"completed"}' >/dev/null 2>&1
RC_B=$?
assert_eq "B rc=0" "0" "$RC_B"
assert_eq "B exactly one orca invocation (the probe)" "1" "$(argv_count "$LOG_B")"
assert_eq "B that one call was status --json" "1" "$(argv_matches "$LOG_B" '.[0]=="status" and .[1]=="--json"')"

echo ""
echo "==== C: probe-once-per-run (cached across N invocations) ===="
CACHE_C="$TMP/cache-c"
CALLS_C="$TMP/status-calls-c"
: > "$CALLS_C"
for i in 1 2 3 4 5; do
  ORCA_STUB_STATUS_CALLS="$CALLS_C" LOOMWRIGHT_ORCA_STATUS_CACHE="$CACHE_C" \
    run_mirror '{"event":"worker_checkpoint","kind":"transition","text":"step '"$i"'"}' >/dev/null 2>&1
done
assert_eq "C: 5 invocations, 1 status call (cached)" "1" "$(argv_count "$CALLS_C")"

echo ""
echo "==== C-mutation: broken cache-read forces N probes (mutation control) ===="
MUT_SCRIPT="$TMP/orca-mirror-mutated.sh"
sed -e '/MUTATION-TEST-ANCHOR: cache-read-gate/{' -e 'n' -e 's/.*/if false; then/' -e '}' "$MIRROR" > "$MUT_SCRIPT"
if [ -s "$MUT_SCRIPT" ] && ! diff -q "$MIRROR" "$MUT_SCRIPT" >/dev/null 2>&1 && bash -n "$MUT_SCRIPT" 2>/dev/null; then
  CACHE_CM="$TMP/cache-cm"
  CALLS_CM="$TMP/status-calls-cm"
  : > "$CALLS_CM"
  for i in 1 2 3; do
    ORCA_STUB_STATUS_CALLS="$CALLS_CM" LOOMWRIGHT_ORCA_STATUS_CACHE="$CACHE_CM" \
      PATH="$STUB_DIR:$PATH" "$BASH_BIN" "$MUT_SCRIPT" '{"event":"worker_checkpoint","kind":"transition","text":"x"}' >/dev/null 2>&1
  done
  assert_eq "C-mutation: broken cache-read -> 3 probes for 3 invocations" "3" "$(argv_count "$CALLS_CM")"
else
  no "C-mutation: mutated script build failed sanity gate (empty/identical/invalid) — mutation control not exercised"
fi

echo ""
echo "==== D: phase_transition mapping ===="
# Real on-disk shape uses the "type" key (not "event") and the target phase
# lives in "to" (not "phase") — see orca-mirror.sh's EVENT TYPE KEY comment
# and the fixture cited there.
LOG_D1="$TMP/argv-d1.jsonl"
ORCA_STUB_LOG="$LOG_D1" LOOMWRIGHT_ORCA_STATUS_CACHE="$TMP/cache-d1" \
  run_mirror '{"type":"phase_transition","from":"EXECUTE","to":"PLAN"}' >/dev/null 2>&1
assert_eq "D1 default phase -> in-progress" "1" "$(argv_matches "$LOG_D1" '.[0]=="--workspace-status" and .[1]=="in-progress"')"

LOG_D2="$TMP/argv-d2.jsonl"
ORCA_STUB_LOG="$LOG_D2" LOOMWRIGHT_ORCA_STATUS_CACHE="$TMP/cache-d2" \
  run_mirror '{"type":"phase_transition","from":"FINALIZE","to":"SELF_HEAL"}' >/dev/null 2>&1
assert_eq "D2 SELF_HEAL phase -> in-review" "1" "$(argv_matches "$LOG_D2" '.[0]=="--workspace-status" and .[1]=="in-review"')"

LOG_D3="$TMP/argv-d3.jsonl"
ORCA_STUB_LOG="$LOG_D3" LOOMWRIGHT_ORCA_STATUS_CACHE="$TMP/cache-d3" \
  run_mirror '{"event":"phase_transition","phase":"SELF_HEAL"}' >/dev/null 2>&1
assert_eq "D3 legacy {event,phase} shape does not match .type -> falls to in-progress default (proves the key/field fix is load-bearing)" "1" "$(argv_matches "$LOG_D3" '.[0]=="--workspace-status" and .[1]=="in-progress"')"

echo ""
echo "==== E: pr_created mapping ===="
# Real on-disk shape spells the URL field "url" (see orca-mirror.sh's EVENT
# TYPE KEY comment and the test-curation-status.sh / SKILL.md fixtures cited
# there) — this is the PRIMARY case.
LOG_E="$TMP/argv-e.jsonl"
ORCA_STUB_LOG="$LOG_E" LOOMWRIGHT_ORCA_STATUS_CACHE="$TMP/cache-e" \
  run_mirror '{"event":"pr_created","url":"https://github.com/org/repo/pull/42"}' >/dev/null 2>&1
assert_eq "E workspace-status in-review" "1" "$(argv_matches "$LOG_E" '.[0]=="--workspace-status" and .[1]=="in-review"')"
assert_eq "E comment set contains the PR URL" "1" "$(argv_matches "$LOG_E" '.[0]=="worktree" and .[1]=="set" and (.[3] | contains("https://github.com/org/repo/pull/42"))')"
# read-before-write: the `worktree current` read must appear in the log too.
assert_eq "E read-before-write: worktree current was called" "1" "$(argv_matches "$LOG_E" '.[0]=="worktree" and .[1]=="current"')"

LOG_E2="$TMP/argv-e2.jsonl"
ORCA_STUB_LOG="$LOG_E2" LOOMWRIGHT_ORCA_STATUS_CACHE="$TMP/cache-e2" \
  run_mirror '{"event":"pr_created","pr_url":"https://github.com/org/repo/pull/99"}' >/dev/null 2>&1
assert_eq "E2 legacy pr_url-only shape still resolves via fallback (proves the .url // .pr_url fix is load-bearing)" "1" "$(argv_matches "$LOG_E2" '.[0]=="worktree" and .[1]=="set" and (.[3] | contains("https://github.com/org/repo/pull/99"))')"

echo ""
echo "==== F: worker_checkpoint mapping ===="
LOG_F="$TMP/argv-f.jsonl"
ORCA_STUB_LOG="$LOG_F" LOOMWRIGHT_ORCA_STATUS_CACHE="$TMP/cache-f" \
  run_mirror '{"event":"worker_checkpoint","kind":"blocker","text":"stuck on X"}' >/dev/null 2>&1
assert_eq "F worktree set --comment with checkpoint text" "1" "$(argv_matches "$LOG_F" '.[0]=="worktree" and .[1]=="set" and .[2]=="--comment" and (.[3] | contains("stuck on X"))')"

echo ""
echo "==== G: session_end mapping ===="
LOG_G1="$TMP/argv-g1.jsonl"
ORCA_STUB_LOG="$LOG_G1" LOOMWRIGHT_ORCA_STATUS_CACHE="$TMP/cache-g1" \
  run_mirror '{"event":"session_end","status":"completed"}' >/dev/null 2>&1
assert_eq "G1 completed -> completed" "1" "$(argv_matches "$LOG_G1" '.[0]=="--workspace-status" and .[1]=="completed"')"

LOG_G2="$TMP/argv-g2.jsonl"
ORCA_STUB_LOG="$LOG_G2" LOOMWRIGHT_ORCA_STATUS_CACHE="$TMP/cache-g2" \
  run_mirror '{"event":"session_end","status":"completed_with_escalation"}' >/dev/null 2>&1
assert_eq "G2 completed_with_escalation -> completed" "1" "$(argv_matches "$LOG_G2" '.[0]=="--workspace-status" and .[1]=="completed"')"

LOG_G3="$TMP/argv-g3.jsonl"
ORCA_STUB_LOG="$LOG_G3" LOOMWRIGHT_ORCA_STATUS_CACHE="$TMP/cache-g3" \
  run_mirror '{"event":"session_end","status":"failed","reason":"session_ended_without_completion"}' >/dev/null 2>&1
assert_eq "G3 failed -> todo" "1" "$(argv_matches "$LOG_G3" '.[0]=="--workspace-status" and .[1]=="todo"')"

LOG_G4="$TMP/argv-g4.jsonl"
ORCA_STUB_LOG="$LOG_G4" LOOMWRIGHT_ORCA_STATUS_CACHE="$TMP/cache-g4" \
  run_mirror '{"event":"session_end"}' >/dev/null 2>&1
assert_eq "G4 absent status -> todo (fail-toward-visible)" "1" "$(argv_matches "$LOG_G4" '.[0]=="--workspace-status" and .[1]=="todo"')"

echo ""
echo "==== H: comment preservation ===="
CURRENT_JSON_H="$TMP/current-h.json"
printf '{"comment":"USER WROTE THIS EARLIER"}\n' > "$CURRENT_JSON_H"
LOG_H="$TMP/argv-h.jsonl"
ORCA_STUB_LOG="$LOG_H" LOOMWRIGHT_ORCA_STATUS_CACHE="$TMP/cache-h" ORCA_STUB_CURRENT_JSON_FILE="$CURRENT_JSON_H" \
  run_mirror '{"event":"worker_checkpoint","kind":"blocker","text":"new checkpoint text"}' >/dev/null 2>&1
assert_eq "H: seeded user text survives" "1" "$(argv_matches "$LOG_H" '.[0]=="worktree" and .[1]=="set" and (.[3] | contains("USER WROTE THIS EARLIER"))')"
assert_eq "H: new text also present" "1" "$(argv_matches "$LOG_H" '.[0]=="worktree" and .[1]=="set" and (.[3] | contains("new checkpoint text"))')"

echo ""
echo "==== H2: comment preservation when the read itself FAILS -> no write at all ===="
LOG_H2="$TMP/argv-h2.jsonl"
BROKEN_CURRENT_H2="$TMP/broken-current-h2.json"
printf 'not json' > "$BROKEN_CURRENT_H2"
ORCA_STUB_LOG="$LOG_H2" LOOMWRIGHT_ORCA_STATUS_CACHE="$TMP/cache-h2" ORCA_STUB_CURRENT_JSON_FILE="$BROKEN_CURRENT_H2" \
  run_mirror '{"event":"worker_checkpoint","kind":"blocker","text":"should not be posted"}' >/dev/null 2>&1
assert_eq "H2: no 'worktree set' call when the read is unparseable" "0" "$(argv_matches "$LOG_H2" '.[0]=="worktree" and .[1]=="set"')"

echo ""
echo "==== I: unrecognized event type -> silent no-op ===="
LOG_I="$TMP/argv-i.jsonl"
ORCA_STUB_LOG="$LOG_I" LOOMWRIGHT_ORCA_STATUS_CACHE="$TMP/cache-i" \
  run_mirror '{"event":"some_totally_unknown_event","data":"x"}' >/dev/null 2>&1
assert_eq "I: only the probe call, no mapped action" "1" "$(argv_count "$LOG_I")"

echo ""
echo "==== J: malformed JSON / missing jq -> exit 0, zero orca invocations ===="
LOG_J1="$TMP/argv-j1.jsonl"
OUT_J1="$(ORCA_STUB_LOG="$LOG_J1" LOOMWRIGHT_ORCA_STATUS_CACHE="$TMP/cache-j1" run_mirror 'not valid json {{{' 2>&1)"
RC_J1=$?
assert_eq "J1 rc=0 on malformed JSON" "0" "$RC_J1"
assert_eq "J1 zero orca invocations on malformed JSON" "0" "$(argv_count "$LOG_J1")"

LOG_J2="$TMP/argv-j2.jsonl"
OUT_J2="$(ORCA_STUB_LOG="$LOG_J2" LOOMWRIGHT_ORCA_STATUS_CACHE="$TMP/cache-j2" LOOMWRIGHT_JQ_BIN=/nonexistent-jq-binary \
  run_mirror '{"event":"session_end","status":"completed"}' 2>&1)"
RC_J2=$?
assert_eq "J2 rc=0 when jq is unavailable" "0" "$RC_J2"
assert_eq "J2 zero orca invocations when jq is unavailable" "0" "$(argv_count "$LOG_J2")"

echo ""
echo "==== K: injection safety ===="
LOG_K="$TMP/argv-k.jsonl"
NASTY_TEXT='hello"; rm -rf /tmp/should-not-run; echo `whoami` $(id) $HOME'"'"'x'
EVENT_K="$(jq -nc --arg t "$NASTY_TEXT" '{event:"worker_checkpoint",kind:"blocker",text:$t}')"
ORCA_STUB_LOG="$LOG_K" LOOMWRIGHT_ORCA_STATUS_CACHE="$TMP/cache-k" \
  run_mirror "$EVENT_K" >/dev/null 2>&1
K_CONTAINS="$(jq -s --arg want "$NASTY_TEXT" 'any(.[]; .[0]=="worktree" and .[1]=="set" and (.[3] == $want))' "$LOG_K" 2>/dev/null)"
assert_eq "K: hostile text is EXACTLY the comment argv element (no shell breakout)" "true" "$K_CONTAINS"
assert_eq "K: no evidence of the injected command having run" "0" "$( [ -f /tmp/should-not-run ] && echo 1 || echo 0 )"

echo ""
echo "==== L: core-cleanliness ===="
# KNOWN, PRE-EXISTING false-positive class (not introduced by this change, and
# out of this subtask's lane to fix): the requirements QUEUE this and prior
# items were derived from is itself named `orca-derived`
# (.supervisor/requirements/orca-derived/), and several already-shipped items
# (agent-lifecycle-ledger, completion-authority, worker-checkpoints,
# rate-limit-park) cite that source-requirement path in header
# comments/prose/budget-table keys — e.g. "orca-derived/03-worker-checkpoints.md",
# "orca-03". That is a coincidental substring collision with the CLI tool
# name, not actual Orca coupling: confirmed by inspecting every current hit
# outside adapters/ (loomwright/agents/execute-manager.md,
# loomwright/docs/{ARCHITECTURE_CONTRACTS,RESULT_SCHEMAS,prompt-token-budgets.json},
# loomwright/scripts/{checkpoint,emit-lifecycle,build-floor,check-children-settled,
# test-checkpoint,test-check-children-settled}.sh) — every "orca" occurrence in
# every one of them is part of the literal substring "orca-derived" or
# "orca-03", never a real CLI invocation. Documented in
# ARCHITECTURE_CONTRACTS.md's new Portability section. The refined check below
# asserts the TRUE contract this AC intends (core names no REAL orca CLI
# usage): a `loomwright/docs/*` file is always allowed to mention orca (it is
# documentation, exactly what the AC's "documentation files" carve-out
# means); any OTHER file is allowed ONLY if every "orca" occurrence in it is
# accounted for by the known orca-derived/orca-03 collision.
RAW_HITS="$(grep -rl orca "$REPO_ROOT/loomwright" --exclude-dir=adapters 2>/dev/null || true)"
REAL_HITS=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in
    */loomwright/docs/*) continue ;;  # documentation -- always allowed
  esac
  residue="$(grep -o 'orca' "$f" 2>/dev/null | wc -l | tr -d '[:space:]')"
  known="$(grep -oE 'orca-derived|orca-03' "$f" 2>/dev/null | wc -l | tr -d '[:space:]')"
  case "$residue" in ''|*[!0-9]*) residue=0 ;; esac
  case "$known" in ''|*[!0-9]*) known=0 ;; esac
  if [ "$residue" -gt "$known" ]; then
    REAL_HITS="$REAL_HITS
$f"
  fi
done <<< "$RAW_HITS"
assert_eq "L: no non-doc file outside adapters/ names the real orca CLI (known orca-derived/orca-03 citations excluded)" "" "$REAL_HITS"

echo ""
echo "==== M: stdin invocation shape ===="
LOG_M="$TMP/argv-m.jsonl"
OUT_M_RC=0
printf '{"event":"session_end","status":"completed"}' | \
  env ORCA_STUB_LOG="$LOG_M" LOOMWRIGHT_ORCA_STATUS_CACHE="$TMP/cache-m" PATH="$STUB_DIR:$PATH" \
  "$BASH_BIN" "$MIRROR" >/dev/null 2>&1 || OUT_M_RC=$?
assert_eq "M rc=0 via stdin" "0" "$OUT_M_RC"
assert_eq "M workspace-status completed via stdin" "1" "$(argv_matches "$LOG_M" '.[0]=="--workspace-status" and .[1]=="completed"')"

echo ""
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && exit 0 || exit 1
