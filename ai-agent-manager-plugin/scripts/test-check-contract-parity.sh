#!/usr/bin/env bash
# Self-test for scripts/check-contract-parity.sh (repo-root CI guard).
# Auto-run by CI's test-*.sh loop. Deterministic, no network, no repo writes
# (fixtures live in mktemp -d).

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
GUARD="$REPO_ROOT/scripts/check-contract-parity.sh"
[ -f "$GUARD" ] || { echo "FAIL: guard not found at $GUARD" >&2; exit 1; }

pass=0; total=0
check() { # $1 desc, $2 expected exit (0|1), then the command
  local desc="$1" want="$2"; shift 2
  total=$((total+1))
  local got=0
  "$@" >/dev/null 2>&1 || got=$?
  if [ "$got" -eq "$want" ] || { [ "$want" -eq 1 ] && [ "$got" -ne 0 ]; }; then
    echo "ok    $desc"; pass=$((pass+1))
  else
    echo "FAIL  $desc (exit $got, wanted $want)"
  fi
}

make_fixture() { # $1 = fixture dir; writes a minimal valid tree
  local d="$1"
  mkdir -p "$d/ai-agent-manager-plugin/hooks" "$d/ai-agent-manager-plugin/agents"
  # hooks.json mentioning every manifest field for every matcher (pin guard satisfied)
  python3 - "$d/ai-agent-manager-plugin/hooks/hooks.json" <<'PY'
import json,sys
def prompt(fields): return "Verify block contains " + ", ".join(fields) + " fields."
mk=lambda m,f:{"matcher":f"ai-agent-manager-plugin:{m}","hooks":[{"type":"prompt","prompt":prompt(f),"timeout":30}]}
h={"hooks":{"SubagentStop":[
  mk("worker",["schema_version","task_id","status","files_modified","summary","outputs_verified","outputs_gap"]),
  mk("execute-manager",["schema_version","subtasks_completed","worktrees","merge_order","summary","completed_so_far","remaining","resume_context","reason"]),
  mk("qa-executor",["schema_version","tests_generated","tests_passed","summary","coverage_estimate"]),
  mk("supervisor-runner",["schema_version","status","pr_url","heal_loop_ran","heal_iterations","heal_decision","heal_fixable_issues_fixed","heal_remaining_issues","error","summary"]),
  mk("plan-reviewer",["schema_version","decision","issues","severity","section","description","summary"]),
  mk("code-reviewer",["schema_version","decision","summary","severity","category","review_mode","audit_focus","trigger_paths_detected","scope_expanded","files_checked"]),
]}}
json.dump(h,open(sys.argv[1],"w"))
PY
  # agent prompts naming every required field, with in-enum literals only
  cat >"$d/ai-agent-manager-plugin/agents/worker.md" <<'EOF'
Emit WORKER_RESULT: schema_version, task_id, status: completed, files_modified,
summary, outputs_verified (status: present / status: missing), outputs_gap.
Other statuses: status: failed, status: partial.
EOF
  cat >"$d/ai-agent-manager-plugin/agents/execute-manager.md" <<'EOF'
EXECUTE_RESULT: schema_version, subtasks_completed (status: completed), worktrees,
merge_order, summary. EXECUTE_CHECKPOINT: completed_so_far, remaining (status: pending),
in_progress entries (status: in_progress), resume_context, reason. status: failed too.
EOF
  cat >"$d/ai-agent-manager-plugin/agents/qa-executor.md" <<'EOF'
QA_RESULT fields: schema_version, tests_generated, tests_passed, coverage_estimate, summary.
EOF
  cat >"$d/ai-agent-manager-plugin/agents/supervisor.md" <<'EOF'
SUPERVISOR_RESULT: schema_version, status: completed | status: failed | status: checkpoint
| status: completed_with_escalation, pr_url, heal_loop_ran, heal_iterations,
heal_decision: PASS or heal_decision: ESCALATED or heal_decision: null,
heal_fixable_issues_fixed, heal_remaining_issues, error, summary.
EOF
  cat >"$d/ai-agent-manager-plugin/agents/plan-reviewer.md" <<'EOF'
PLAN_REVIEW_RESULT: schema_version, decision: PASS / decision: FAIL / decision: NEEDS_HUMAN,
issues with severity, section, description; summary.
EOF
  cat >"$d/ai-agent-manager-plugin/agents/code-reviewer.md" <<'EOF'
CODE_REVIEW_RESULT: schema_version, decision: PASS, summary, issues with severity and
category, review_mode, audit_focus, trigger_paths_detected, scope_expanded, files_checked.
decision: FAIL and decision: NEEDS_HUMAN are the other outcomes.
EOF
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 1. Clean fixture passes
make_fixture "$TMP/clean"
check "clean fixture passes" 0 bash "$GUARD" --root "$TMP/clean"

# 2. Missing hook-required field in an agent prompt fails (the qa-executor trap class)
make_fixture "$TMP/missing-field"
sed -i '' -e 's/coverage_estimate, summary/summary/' "$TMP/missing-field/ai-agent-manager-plugin/agents/qa-executor.md" 2>/dev/null \
  || sed -i -e 's/coverage_estimate, summary/summary/' "$TMP/missing-field/ai-agent-manager-plugin/agents/qa-executor.md"
check "missing hook-required field fails" 1 bash "$GUARD" --root "$TMP/missing-field"

# 3. Out-of-enum status literal fails (the `status: paused` class)
make_fixture "$TMP/bad-enum"
printf '\nOn crash: pause the phase (status: paused) and exit.\n' >> "$TMP/bad-enum/ai-agent-manager-plugin/agents/supervisor.md"
check "out-of-enum status literal fails" 1 bash "$GUARD" --root "$TMP/bad-enum"

# 4. Pin-drift: hooks.json drops a field the manifest still pins → fails
make_fixture "$TMP/pin-drift"
python3 - "$TMP/pin-drift/ai-agent-manager-plugin/hooks/hooks.json" <<'PY'
import json,sys
p=sys.argv[1]; h=json.load(open(p))
for e in h["hooks"]["SubagentStop"]:
    if "qa-executor" in e["matcher"]:
        e["hooks"][0]["prompt"]=e["hooks"][0]["prompt"].replace(", coverage_estimate","")
json.dump(h,open(p,"w"))
PY
check "hooks.json pin-drift fails" 1 bash "$GUARD" --root "$TMP/pin-drift"

# 5. The guard passes against the REAL repo tree (post-sweep invariant)
check "real repo tree passes" 0 bash "$GUARD" --root "$REPO_ROOT"

echo "----"
echo "test-check-contract-parity: $pass/$total passed"
[ "$pass" -eq "$total" ]
