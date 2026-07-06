#!/usr/bin/env bash
# check-contract-parity.sh — CI gate: hook ↔ agent-prompt contract parity.
#
# Two mechanical checks, deliberately conservative (high-confidence only, same
# philosophy as check-doc-currency.sh):
#
#   1. FIELD PRESENCE — for each prompt-type SubagentStop validator in
#      hooks.json, every hook-required result-block field name (pinned in the
#      MANIFEST below) must (a) still appear in the hooks.json validator prompt
#      (pin-drift guard: if the hook changes, the manifest must change with it)
#      and (b) appear in the matched agent's prompt file (an agent told to emit
#      a block must name every hook-required field somewhere in its emit
#      instructions).
#
#   2. ENUM LITERALS — for result status/decision keys whose hook validator
#      enumerates a closed enum, any literal `key: token` in the agent prompt
#      must be inside the per-file allowlist (the enum plus that file's other
#      legitimate uses of the key, e.g. worktree `status: running`). This is
#      the class that caught the illegal `status: paused` in supervisor.md.
#
# Catches the v14.22.x hook-rejection-trap class mechanically: an agent whose
# documented emit format drops a hook-required field, or instructs an
# out-of-enum status literal, fails CI before it can fail at runtime.
#
# Usage: bash scripts/check-contract-parity.sh [--root <dir>]
#   --root defaults to the repo root (the directory containing
#   loomwright/). The self-test points it at a fixture tree.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ "${1:-}" = "--root" ]; then
  ROOT="${2:?--root requires a directory}"
fi

PLUGIN="$ROOT/loomwright"
HOOKS="$PLUGIN/hooks/hooks.json"
AGENTS="$PLUGIN/agents"

[ -f "$HOOKS" ] || { echo "✗ contract-parity: hooks.json not found at $HOOKS" >&2; exit 1; }

fail=0
err() { echo "  PARITY [$1] $2" >&2; fail=1; }

# Flattened hooks.json text for matcher-scoped prompt extraction (python for
# reliable JSON parsing; jq is not guaranteed on every dev machine).
hook_prompt() { # $1 = matcher substring
  python3 - "$HOOKS" "$1" <<'PY'
import json,sys
h=json.load(open(sys.argv[1]))
needle=sys.argv[2]
for ev in h.get("hooks",{}).values():
    for e in ev if isinstance(ev,list) else []:
        if needle in str(e.get("matcher","")):
            for hk in e.get("hooks",[]):
                if hk.get("type")=="prompt":
                    print(hk["prompt"])
PY
}

# ── MANIFEST ─────────────────────────────────────────────────────────────────
# matcher | agent file | block name | comma-separated hook-required fields
MANIFEST="
worker|worker.md|WORKER_RESULT|schema_version,task_id,status,files_modified,summary,outputs_verified,outputs_gap
execute-manager|execute-manager.md|EXECUTE_RESULT|schema_version,subtasks_completed,worktrees,merge_order,summary
execute-manager|execute-manager.md|EXECUTE_CHECKPOINT|completed_so_far,remaining,resume_context,reason
qa-executor|qa-executor.md|QA_RESULT|schema_version,tests_generated,tests_passed,summary,coverage_estimate
supervisor-runner|supervisor.md|SUPERVISOR_RESULT|schema_version,status,pr_url,heal_loop_ran,heal_iterations,heal_decision,heal_fixable_issues_fixed,heal_remaining_issues,error,summary
plan-reviewer|plan-reviewer.md|PLAN_REVIEW_RESULT|schema_version,decision,issues,severity,section,description,summary
code-reviewer|code-reviewer.md|CODE_REVIEW_RESULT|schema_version,decision,summary,severity,category,review_mode,audit_focus,trigger_paths_detected,scope_expanded,files_checked
"

# ── Check 1: field presence ──────────────────────────────────────────────────
while IFS='|' read -r matcher agent block fields; do
  [ -n "$matcher" ] || continue
  agent_path="$AGENTS/$agent"
  [ -f "$agent_path" ] || { err field-presence "$agent missing at $agent_path"; continue; }
  prompt="$(hook_prompt "$matcher")"
  [ -n "$prompt" ] || { err pin-drift "no prompt-type hook found for matcher '$matcher' in hooks.json — update the MANIFEST"; continue; }
  IFS=',' read -ra fl <<<"$fields"
  for f in "${fl[@]}"; do
    # (a) pin-drift guard: hooks.json must still require this field
    if ! grep -qw -- "$f" <<<"$prompt"; then
      err pin-drift "hooks.json [$matcher] no longer mentions '$f' — update the MANIFEST in this script"
    fi
    # (b) agent prompt must name the field. NOTE guard strength: this is
    #     name-presence anywhere in the file, not emit-block membership — it
    #     catches a field deleted entirely (the v14.22.x trap class) but not
    #     one mentioned in prose yet dropped from the emit format.
    if ! grep -qw -- "$f" "$agent_path"; then
      err field-presence "$agent: hook-required $block field '$f' not found anywhere in the agent prompt"
    fi
  done
done <<<"$MANIFEST"

# ── Check 2: enum literals ───────────────────────────────────────────────────
# path (plugin-root-relative) | key | allowed tokens (enum + that file's other
# legitimate uses). Allowlists are deliberately supersets: they also cover
# sub-object statuses (e.g. supervisor's pass/advisory_failures/unverified/
# skipped — sub-object enums on contract_conformance/ground_truth, not
# SUPERVISOR_RESULT.status values). Skills that carry emit-shaping prose
# extracted from an agent (the v14.23.0 supervisor diet) are IN SCOPE below —
# when a refactor moves status-literal-bearing text into a new skill, add a
# row here so the gate's coverage moves with it.
ENUMS="
agents/supervisor.md|status|completed,completed_with_escalation,failed,checkpoint,enum,pass,advisory_failures,unverified,skipped,running
agents/supervisor.md|heal_decision|PASS,ESCALATED,null,enum
agents/worker.md|status|completed,failed,partial,present,missing,pending,enum
agents/qa-executor.md|status|passed,failed,partial,skipped,needs_human,plan_created,all_scopes_completed,enum
agents/execute-manager.md|status|completed,failed,in_progress,pending,running,missing,checkpoint,enum
agents/code-reviewer.md|decision|PASS,FAIL,NEEDS_HUMAN,enum
agents/plan-reviewer.md|decision|PASS,FAIL,NEEDS_HUMAN,enum
skills/self-heal-advisory/SKILL.md|status|pass,advisory_failures,advisory_violations,unverified,skipped,failed,checkpoint,enum
skills/self-heal-advisory/SKILL.md|heal_decision|PASS,ESCALATED,null,enum
"

while IFS='|' read -r agent key allowed; do
  [ -n "$agent" ] || continue
  agent_path="$PLUGIN/$agent"
  [ -f "$agent_path" ] || { err enum-literal "scoped file $agent missing at $agent_path — update ENUMS"; continue; }
  # bare literals only: `key: token` (quoted strings, {placeholders}, and
  # comparison forms like `key ==` deliberately do not match)
  while read -r tok; do
    [ -n "$tok" ] || continue
    case ",$allowed," in
      *",$tok,"*) ;;
      *) err enum-literal "$agent: '$key: $tok' is outside the allowed set [$allowed] — out-of-enum literals get hook-rejected at runtime" ;;
    esac
  done < <(grep -ohE "\b${key}:[[:space:]]+[A-Za-z_]+" "$agent_path" | sed -E "s/^${key}:[[:space:]]+//" | sort -u)
done <<<"$ENUMS"

if [ "$fail" -ne 0 ]; then
  echo "✗ contract-parity: drift detected — fix the agent prompt, the hook, or the pinned MANIFEST/ENUMS (keep all three in sync)." >&2
  exit 1
fi
echo "✓ contract-parity: all hook-required fields present and all status/decision literals in-enum."
