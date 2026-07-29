#!/usr/bin/env bash
# check-contract-parity.sh — CI gate: hook ↔ agent-prompt contract parity.
#
# Two mechanical checks, deliberately conservative (high-confidence only, same
# philosophy as check-doc-currency.sh):
#
#   1. FIELD PRESENCE — for each SubagentStop validator in hooks.json, every
#      hook-required result-block field name (pinned in the MANIFEST below)
#      must (a) still appear in that validator's RULE SOURCE — the `type:
#      prompt` prompt string, or (since v15.17.0, for validators converted to
#      `type: command`) the source of the referenced validate-<x>-result.py
#      script WITH ITS DOCSTRINGS STRIPPED, so that a rule transcribed in prose
#      cannot stand in for the executable check (pin-drift guard: if the hook
#      changes, the manifest must change with it) — and (b) appear in the
#      matched agent's prompt file (an agent
#      told to emit a block must name every hook-required field somewhere in
#      its emit instructions).
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

# Sentinel emitted by hook_prompt() when a matcher's rule source cannot be
# resolved unambiguously. Callers MUST treat it as a hard pin-drift error —
# never as "no rule to check".
PARITY_UNRESOLVED="__PARITY_UNRESOLVED__"

# Resolve a matcher's RUNTIME RULE SOURCE — the text the pin-drift guard greps
# for hook-required field names (python for reliable JSON parsing; jq is not
# guaranteed on every dev machine).
#
# Two sources, in order:
#   1. `type: prompt` hooks — the historical source; their prompt strings.
#   2. FALLBACK (v15.17.0): when the matcher has no prompt hook, the SOURCE of
#      the `validate-<x>-result.py` script referenced by one of its `type:
#      command` hooks. Five SubagentStop validators were converted from prompt
#      strings to deterministic scripts; the rule source moved from a prompt
#      into a .py file, so the guard follows it there. Field names appear
#      literally in those scripts (as dict keys / constants), which is what
#      makes the pin-drift grep still meaningful.
#
# The fallback's SELECTION RULE is load-bearing and deliberately fails CLOSED:
# exactly ONE command entry may reference a validate-*-result.py script, and it
# must name exactly one such script. Zero or more than one is a hard error.
# Three affected matchers carry ADDITIONAL command entries after the
# conversion — loomwright:worker also has emit-progress-event.sh,
# loomwright:qa-executor also has the telemetry fan-out, and
# loomwright:supervisor-runner has both the telemetry fan-out and
# send-webhook.sh — so "the matcher's command entry" is not well defined and
# both naive readings are wrong:
#   * concatenating every command entry's source fails OPEN —
#     send-telemetry-core.sh alone mentions pr_url / heal_decision /
#     heal_loop_ran / summary / schema_version, so a pin-drift grep would PASS
#     on a field the real validator had dropped, leaving the gate green while
#     enforcing nothing;
#   * taking the first entry fails CLOSED with spurious red CI and couples the
#     gate to hook ordering that nothing asserts.
#
# DOCSTRINGS ARE STRIPPED from the resolved validator source before it is
# returned, and that is load-bearing too. Every ST-1 validator opens with a
# module docstring transcribing its numbered rules VERBATIM ("(4) if tests were
# run, coverage_estimate is present"), and several function docstrings quote
# field names as well. Grepping the raw source therefore lets PROSE satisfy the
# pin-drift guard: deleting the executable rule-4 block from
# validate-qa-result.py leaves zero coverage_estimate mentions outside the
# docstring, yet an unstripped guard still prints ✓ and exits 0 — the same
# fail-open class as the concat reading above, one layer deeper. Since the five
# prompt strings this guard used to grep are gone, it is the only thing between
# a silently-weakened validator and CI, so it must grep CODE, not commentary.
#
# Removal is by AST NODE SPAN, and both obvious shortcuts are wrong:
#   * `src.replace(ast.get_docstring(tree), "")` removes the docstring TEXT
#     wherever it occurs, not the node — a short docstring whose wording recurs
#     in a string constant would be over-stripped;
#   * that same call also silently does NOTHING for indented function/class
#     docstrings, because get_docstring() dedents (clean=True) so its result is
#     not present verbatim in the source. Verified: the cleaned text of
#     validate-worker-result.py's module docstring is found in the source, its
#     _non_empty_list() docstring's is not.
# ALL docstrings are stripped, not just the module's: files_modified survives
# only in _non_empty_list()'s docstring and worktrees only in
# _check_worktree_paths()'s if their executable checks are deleted, so a
# module-only strip would narrow this hole rather than close it.
hook_prompt() { # $1 = matcher substring; prints rule source, or PARITY_UNRESOLVED + reason
  python3 - "$HOOKS" "$1" "$PLUGIN" "$PARITY_UNRESOLVED" <<'PY'
import ast,json,os,re,sys
hooks_path, needle, plugin, sentinel = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
h=json.load(open(hooks_path))

def bail(msg):
    print("%s %s" % (sentinel, msg))
    sys.exit(0)

def _is_str_const(node):
    # py3.8+ spells a string literal ast.Constant; py<=3.7 spells it ast.Str.
    # The name is compared instead of referencing ast.Str, which is deprecated
    # (and warns) on py3.12+.
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return True
    return node.__class__.__name__ == "Str"

def strip_docstrings(src, path):
    """Blank every module/class/function docstring, by node span.

    Fails CLOSED (bail) rather than returning prose-bearing source: an
    unparseable validator cannot be verified, and a validator that does not
    parse is itself dead at runtime (its traceback is swallowed by the hook's
    `|| true`), so red CI is the correct signal.
    """
    try:
        tree = ast.parse(src)
    except (SyntaxError, ValueError) as exc:
        bail("validator source '%s' does not parse as Python (%s: %s) — the "
             "pin-drift guard cannot distinguish its executable checks from "
             "its prose, and an unparseable validator is dead at runtime"
             % (path, type(exc).__name__, exc))
    spans=[]
    for node in ast.walk(tree):
        if not isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        body = getattr(node, "body", None) or []
        if not body:
            continue
        first = body[0]
        if not (isinstance(first, ast.Expr) and _is_str_const(first.value)):
            continue
        s = first.value
        if getattr(s, "end_lineno", None) is None or getattr(s, "end_col_offset", None) is None:
            bail("python %d.%d cannot report AST end positions (added in 3.8), so "
                 "docstrings in '%s' cannot be stripped by span — the pin-drift "
                 "guard would let prose satisfy it; run this gate on python >= 3.8"
                 % (sys.version_info[0], sys.version_info[1], path))
        spans.append((s.lineno, s.col_offset, s.end_lineno, s.end_col_offset))
    lines = src.splitlines(True)
    # Docstring spans are disjoint; edit right-to-left so earlier offsets stay valid.
    for (l1, c1, l2, c2) in sorted(spans, reverse=True):
        if l1 == l2:
            lines[l1-1] = lines[l1-1][:c1] + lines[l1-1][c2:]
        else:
            lines[l1-1] = lines[l1-1][:c1] + "\n"
            for i in range(l1, l2-1):
                lines[i] = "\n"
            lines[l2-1] = lines[l2-1][c2:]
    return "".join(lines)

prompts=[]; commands=[]
for ev in h.get("hooks",{}).values():
    for e in ev if isinstance(ev,list) else []:
        if needle in str(e.get("matcher","")):
            for hk in e.get("hooks",[]):
                if hk.get("type")=="prompt":
                    prompts.append(hk.get("prompt",""))
                elif hk.get("type")=="command":
                    commands.append(str(hk.get("command","")))

if prompts:
    for p in prompts:
        print(p)
    sys.exit(0)

# ── fallback: the rule source moved into a validator script ──────────────────
REF=re.compile(r'[\w./${}-]*\bvalidate-[A-Za-z0-9_-]+-result\.py')
matching=[c for c in commands if REF.search(c)]
if len(matching)!=1:
    bail("matcher '%s' has no type:prompt hook and %d of its %d type:command "
         "entries reference a validate-*-result.py script (exactly 1 required) "
         "— the rule source is ambiguous; fix hooks.json or the MANIFEST"
         % (needle, len(matching), len(commands)))
refs=sorted(set(REF.findall(matching[0])))
if len(refs)!=1:
    bail("matcher '%s': its validator command entry references %d distinct "
         "validate-*-result.py scripts (exactly 1 required) — the rule source "
         "is ambiguous" % (needle, len(refs)))

path=refs[0]
for var in ("${CLAUDE_PLUGIN_ROOT}", "$CLAUDE_PLUGIN_ROOT"):
    path=path.replace(var, plugin)
if not os.path.isabs(path):
    path=os.path.join(plugin, path)
try:
    with open(path, encoding="utf-8") as fh:
        src=fh.read()
except (OSError, UnicodeDecodeError) as exc:
    bail("matcher '%s': cannot read validator source '%s' (%s)" % (needle, path, exc))
# Prose must not satisfy the pin-drift grep — see the comment block above.
sys.stdout.write(strip_docstrings(src, path))
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
  # An unresolvable rule source is a HARD error, never a silent pass: falling
  # through to an unrelated script (or to "no rule") is exactly how this guard
  # would go green while enforcing nothing.
  case "$prompt" in
    "$PARITY_UNRESOLVED"*) err pin-drift "${prompt#"$PARITY_UNRESOLVED" }"; continue ;;
  esac
  [ -n "$prompt" ] || { err pin-drift "no prompt-type hook and no validator command hook found for matcher '$matcher' in hooks.json — update the MANIFEST"; continue; }
  IFS=',' read -ra fl <<<"$fields"
  for f in "${fl[@]}"; do
    # (a) pin-drift guard: the matcher's rule source (prompt string, or the
    #     referenced validator script's source) must still require this field
    if ! grep -qw -- "$f" <<<"$prompt"; then
      err pin-drift "hooks.json [$matcher] rule source no longer mentions '$f' — update the MANIFEST in this script"
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
skills/preflight-sync/SKILL.md|status|checkpoint,failed,enum
skills/supervisor-config/SKILL.md|status|failed,enum
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
