#!/usr/bin/env bash
# test-non-interactive-gates-seam.sh — static seam test for the question gates' CAN'T-ASK branches
# (agnostic-phase1/04): every gate that may run where nobody can answer — a `--non-interactive` run,
# or a spawned subagent (the host removes the ask tool from every subagent's tool set) — must fail
# CLOSED with a NAMED status string instead of hanging or improvising.
#
# Every surface here is MARKDOWN — prompt text an agent executes — so there is nothing to run; a
# grep is the only thing that can hold the wiring. Modelled on test-brief-conformance-seam.sh:
# ok()/no() helpers DEFINED here, a "RESULT: N passed, M failed" tail, exit 1 on any failure, paths
# from $BASH_SOURCE so it runs from any CWD under ci.yml's `loomwright/scripts/test-*.sh` glob.
# Static only: no gh, no network. bash 3.2 / BSD userland safe.
#
# Asserts (Product Owner + /automate prompt intake):
#   (a) agents/product-owner.md carries the can't-ask branch line INSIDE the Context Setup step 4
#       soft gate, and the line names: the `--non-interactive` flag, the subagent case, that the
#       TTY probe is never the sole signal, that nothing is persisted, and the machine-readable
#       `po_gate: needs_owner (<n> flags)` line.
#   (b) commands/product-owner.md (which embeds a copy of the agent) carries the SAME branch line,
#       byte-for-byte, also inside its soft gate — the agent<->command mirror.
#   (c) `po_gate: needs_owner` appears in both PO files (the requirement's literal grep).
#   (d) /product-owner's `## Parameters` documents `--non-interactive` with the needs_owner outcome.
#   (e) skills/automate-loop/SKILL.md §2 `### Prompt source` subsection names `needs_owner` and
#       passes `--non-interactive` to /product-owner.
#   (f) commands/automate.md's `"<prompt>"` and `--non-interactive-fallback` parameter rows each
#       reference `needs_owner`.
#   (g) every other gate in docs/ARCHITECTURE_CONTRACTS.md §"Question-gate inventory" reachable in a
#       non-interactive / subagent / headless context names its can't-ask status (Launch Pad + its
#       agent<->command rule mirror, Supervisor, supervisor-config, autonomous-loop, automate-loop,
#       qa-executor); the inventory sits right before ## Failure Escalation Summary and no row's NEW
#       behaviour cell is "undefined".
#       The RESUME gate names `resume_requires_flag_non_interactive` (skill, command, inventory) and
#       the withdrawn auto-continue status `resume_continued_non_interactive` appears on no surface;
#       Launch Pad also names `save_requires_flag_non_interactive` (no flag ⇒ no save).
#   (h) re-check: subtask 1's PO / automate strings still resolve.
#   (m) MUTATION CONTROL: delete the can't-ask branch line from a COPY of agents/product-owner.md;
#       gate the mutant on non-empty + differs-from-original; the (a) predicate MUST fail on it.
#       Without this, (a) could be green while asserting nothing.
#
# EXTENDING: further gates append their own section ABOVE the `---- (m)` block using
# `gate_has_status <label> <file> <status-string>` (one named status per gate) — keep each gate's
# predicate a silent function if it also gets a mutation control.
#
# EXPLICIT LIMIT: this pins the WIRING (the branch text exists, sits where the gate is, names its
# status). It cannot prove an agent takes the branch — that is prompt behaviour, observable only in a
# real non-interactive or subagent run. No PO fixture-level test exists (the PO flow has no harness);
# this suite is seam-only for it.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HERE/.." && pwd)"

PO_AGENT="$PLUGIN_ROOT/agents/product-owner.md"
PO_CMD="$PLUGIN_ROOT/commands/product-owner.md"
AUTO_SKILL="$PLUGIN_ROOT/skills/automate-loop/SKILL.md"
AUTO_CMD="$PLUGIN_ROOT/commands/automate.md"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

for f in "$PO_AGENT" "$PO_CMD" "$AUTO_SKILL" "$AUTO_CMD"; do
  [ -f "$f" ] || no "MISSING surface: $f"
done
if [ "$fail" -ne 0 ]; then
  echo
  echo "RESULT: $pass passed, $fail failed"
  exit 1
fi

# gate_has_status <label> <file> <status-string> — the generic per-gate assertion: the gate's file
# names its fail-closed status string (fixed-string match).
gate_has_status() {
  if grep -qF -- "$3" "$2"; then
    ok "$1 names its can't-ask status \`$3\`"
  else
    no "$1 does not name its can't-ask status \`$3\` ($2)"
  fi
}

# po_branch_line <file> — prints the PO can't-ask branch line found INSIDE the soft gate (from the
# `**Soft gate with user confirmation` line up to Context Setup step 5 `**Load Product Context**`);
# empty when absent. Silent: used on the real files AND the mutant.
po_branch_line() {
  awk '
    { t = $0; sub(/^[[:space:]]+/, "", t) }
    index(t, "**Soft gate with user confirmation") == 1 { in_gate = 1; next }
    in_gate && index(t, "**Load Product Context**") > 0 { in_gate = 0 }
    in_gate && index(t, "**Can'\''t-ask branch") == 1 { print t; exit }
  ' "$1"
}

# po_branch_ok <file> — exit 0 iff the soft gate carries a can't-ask branch line naming every
# required element. Silent (no ok/no side effects) so the mutation control can reuse it.
po_branch_ok() {
  line="$(po_branch_line "$1")"
  [ -n "$line" ] || return 1
  case "$line" in *'`--non-interactive`'*) ;; *) return 1 ;; esac
  case "$line" in *'subagent'*'the ask tool is absent'*) ;; *) return 1 ;; esac
  case "$line" in *'never from a stdin-TTY probe alone'*) ;; *) return 1 ;; esac
  case "$line" in *'create no Beads tasks and persist no requirements file'*) ;; *) return 1 ;; esac
  case "$line" in *'`po_gate: needs_owner (<n> flags)`'*) ;; *) return 1 ;; esac
  return 0
}

# section_body <file> <heading-prefix> — prints the lines of the `### ` subsection whose heading
# starts with <heading-prefix>, up to the next `### ` / `## ` heading.
section_body() {
  awk -v h="$2" '
    index($0, h) == 1 { in_sec = 1; next }
    in_sec && (/^### / || /^## /) { in_sec = 0 }
    in_sec { print }
  ' "$1"
}

# ---- (a) PO agent: the can't-ask branch inside the soft gate -------------------------------------
if po_branch_ok "$PO_AGENT"; then
  ok "(a) agents/product-owner.md soft gate carries the full can't-ask branch"
else
  no "(a) agents/product-owner.md soft gate lacks the can't-ask branch (or it misses a required element: --non-interactive / subagent + absent ask tool / TTY-not-alone / persist nothing / po_gate line)"
fi

# ---- (b) agent<->command mirror: same branch text, same place ------------------------------------
if po_branch_ok "$PO_CMD"; then
  ok "(b) commands/product-owner.md soft gate carries the full can't-ask branch"
else
  no "(b) commands/product-owner.md soft gate lacks the can't-ask branch"
fi
agent_line="$(po_branch_line "$PO_AGENT")"
cmd_line="$(po_branch_line "$PO_CMD")"
if [ -n "$agent_line" ] && [ "$agent_line" = "$cmd_line" ]; then
  ok "(b) the branch line is byte-identical in agent and command (mirror)"
else
  no "(b) the branch line differs between agents/product-owner.md and commands/product-owner.md (mirror drift)"
fi

# ---- (c) the requirement's literal grep -----------------------------------------------------------
gate_has_status "(c) agents/product-owner.md" "$PO_AGENT" 'po_gate: needs_owner'
gate_has_status "(c) commands/product-owner.md" "$PO_CMD" 'po_gate: needs_owner'

# ---- (d) /product-owner ## Parameters documents --non-interactive --------------------------------
params="$(awk '
  /^## Parameters/ { in_sec = 1; next }
  in_sec && /^## / { in_sec = 0 }
  in_sec { print }
' "$PO_CMD")"
ni_param="$(printf '%s\n' "$params" | grep -F -- '**--non-interactive**' | head -1 || true)"
case "$ni_param" in
  *'po_gate: needs_owner'*) ok "(d) ## Parameters documents --non-interactive with the needs_owner outcome" ;;
  '') no "(d) ## Parameters does not document --non-interactive" ;;
  *) no "(d) ## Parameters --non-interactive entry does not name po_gate: needs_owner" ;;
esac

# ---- (e) automate-loop §2 Prompt source ----------------------------------------------------------
prompt_src="$(section_body "$AUTO_SKILL" '### Prompt source')"
if [ -z "$prompt_src" ]; then
  no "(e) skills/automate-loop/SKILL.md has no '### Prompt source' subsection"
else
  case "$prompt_src" in
    *'needs_owner'*) ok "(e) §2 Prompt source names needs_owner" ;;
    *) no "(e) §2 Prompt source does not name needs_owner" ;;
  esac
  case "$prompt_src" in
    *'/product-owner "<prompt>" --non-interactive'*) ok "(e) §2 Prompt source passes --non-interactive to /product-owner" ;;
    *) no "(e) §2 Prompt source does not pass --non-interactive to /product-owner" ;;
  esac
fi

# ---- (f) commands/automate.md parameter rows -----------------------------------------------------
prompt_row="$(grep -E '^\| `"<prompt>"` \|' "$AUTO_CMD" | head -1 || true)"
case "$prompt_row" in
  *'needs_owner'*) ok "(f) commands/automate.md \"<prompt>\" row references needs_owner" ;;
  *) no "(f) commands/automate.md \"<prompt>\" row does not reference needs_owner" ;;
esac
nif_row="$(grep -E '^\| `--non-interactive-fallback` \|' "$AUTO_CMD" | head -1 || true)"
case "$nif_row" in
  *'needs_owner'*) ok "(f) commands/automate.md --non-interactive-fallback row references needs_owner" ;;
  *) no "(f) commands/automate.md --non-interactive-fallback row does not reference needs_owner" ;;
esac

# ---- (g) every other gate the inventory marks reachable in MN / SA / HP (subtask 2) -------------
# One assertion per changed gate: its file names its can't-ask status string.
LP_AGENT="$PLUGIN_ROOT/agents/launch-pad.md"
LP_CMD="$PLUGIN_ROOT/commands/launch-pad.md"
SV_AGENT="$PLUGIN_ROOT/agents/supervisor.md"
SV_CFG="$PLUGIN_ROOT/skills/supervisor-config/SKILL.md"
AL_SKILL="$PLUGIN_ROOT/skills/autonomous-loop/SKILL.md"
QA_AGENT="$PLUGIN_ROOT/agents/qa-executor.md"
ARCH="$PLUGIN_ROOT/docs/ARCHITECTURE_CONTRACTS.md"
for f in "$LP_AGENT" "$LP_CMD" "$SV_AGENT" "$SV_CFG" "$AL_SKILL" "$QA_AGENT" "$ARCH"; do
  [ -f "$f" ] || no "MISSING surface: $f"
done
for s in clarification_needed_non_interactive no_go_non_interactive needs_human_non_interactive \
         saved_on_pass_non_interactive save_requires_flag_non_interactive \
         plan_review_fail_non_interactive memory_candidates_deferred_non_interactive; do
  gate_has_status "(g) agents/launch-pad.md" "$LP_AGENT" "$s"
done
# agent<->command mirror: the Can't-ask rule bullet is byte-identical in both Launch Pad files.
lp_rule() { grep -F -- "- **Can't-ask rule:**" "$1" | head -1; }
lp_a="$(lp_rule "$LP_AGENT")"; lp_c="$(lp_rule "$LP_CMD")"
if [ -n "$lp_a" ] && [ "$lp_a" = "$lp_c" ]; then
  ok "(g) Launch Pad Can't-ask rule is byte-identical in agent and command (mirror)"
else
  no "(g) Launch Pad Can't-ask rule missing or differs between agents/ and commands/launch-pad.md"
fi
case "$lp_a" in
  *'executing as a subagent'*'never from a stdin-TTY probe alone'*) ok "(g) Launch Pad rule keys on flag + subagent, not the TTY probe alone" ;;
  *) no "(g) Launch Pad rule does not name the subagent signal / TTY-not-alone" ;;
esac
gate_has_status "(g) commands/launch-pad.md NO-GO" "$LP_CMD" 'no_go_non_interactive'
for s in init_input_missing_non_interactive adjudication_required_non_interactive \
         preflight_overlap_detected gh_unavailable_non_interactive children_unsettled; do
  gate_has_status "(g) agents/supervisor.md" "$SV_AGENT" "$s"
done
gate_has_status "(g) skills/supervisor-config/SKILL.md INIT" "$SV_CFG" 'init_input_missing_non_interactive'
for s in non_interactive_without_fallback rubric_gate_closed_non_interactive no_rubric_in_non_interactive \
         review_heal_escalated_non_interactive pr_base_verify_skipped_non_interactive; do
  gate_has_status "(g) skills/autonomous-loop/SKILL.md" "$AL_SKILL" "$s"
done
for s in no_source_non_interactive resume_requires_flag_non_interactive resume_ambiguous; do
  gate_has_status "(g) skills/automate-loop/SKILL.md" "$AUTO_SKILL" "$s"
done
gate_has_status "(g) commands/automate.md bare row" "$AUTO_CMD" 'no_source_non_interactive'
gate_has_status "(g) commands/automate.md bare row" "$AUTO_CMD" 'resume_requires_flag_non_interactive'
gate_has_status "(g) ARCHITECTURE_CONTRACTS.md RESUME row" "$ARCH" 'resume_requires_flag_non_interactive'
# The withdrawn auto-continue branch (a can't-ask path that substituted for --resume) must not come
# back on any surface. Captured, not piped into grep -q (pipefail-safe).
auto_continue_hits="$(grep -rlF -- 'resume_continued_non_interactive' "$PLUGIN_ROOT/agents" "$PLUGIN_ROOT/commands" "$PLUGIN_ROOT/skills" "$PLUGIN_ROOT/docs" 2>/dev/null || true)"
if [ -z "$auto_continue_hits" ]; then
  ok "(g) no surface names the withdrawn auto-continue status resume_continued_non_interactive"
else
  no "(g) the withdrawn auto-continue status resume_continued_non_interactive is still named: $auto_continue_hits"
fi
gate_has_status "(g) agents/qa-executor.md URL fallback" "$QA_AGENT" 'base_url_unresolved'
# The inventory section exists and sits immediately before ## Failure Escalation Summary.
prev_h2="$(awk '/^## /{ if ($0 == "## Failure Escalation Summary") { print last; exit } last = $0 }' "$ARCH")"
if [ "$prev_h2" = "## Question-gate inventory" ]; then
  ok "(g) ARCHITECTURE_CONTRACTS.md has ## Question-gate inventory right before ## Failure Escalation Summary"
else
  no "(g) ## Question-gate inventory missing or not immediately before ## Failure Escalation Summary (got: $prev_h2)"
fi
inv="$(awk '/^## Question-gate inventory/{p=1; next} p && /^## /{exit} p' "$ARCH")"
if grep -qiE '^\|.*\| *undefined *\|$' < <(printf '%s\n' "$inv"); then
  no "(g) an inventory row's NEW can't-ask behaviour cell is 'undefined'"
else
  ok "(g) no inventory row's new can't-ask behaviour is 'undefined'"
fi
# (h) subtask 1's PO / automate strings still resolve after subtask 2's edits (re-check, not preservation).
gate_has_status "(h) re-check agents/product-owner.md" "$PO_AGENT" 'po_gate: needs_owner (<n> flags)'
gate_has_status "(h) re-check commands/product-owner.md" "$PO_CMD" 'po_gate: needs_owner (<n> flags)'
gate_has_status "(h) re-check skills/automate-loop/SKILL.md" "$AUTO_SKILL" 'needs_owner'
gate_has_status "(h) re-check commands/automate.md" "$AUTO_CMD" 'needs_owner'

# ---- (further gates append their sections here, above the mutation control) ---------------------

# ---- (m) MUTATION CONTROL: (a) must go RED when the PO can't-ask branch is deleted ---------------
MUT_DIR="$(mktemp -d)"
trap 'rm -rf "$MUT_DIR" 2>/dev/null' EXIT
MUT="$MUT_DIR/product-owner.md"
grep -vF "**Can't-ask branch" "$PO_AGENT" > "$MUT"
if [ -s "$MUT" ] && ! cmp -s "$PO_AGENT" "$MUT"; then
  ok "(m) mutant is non-empty and differs from the original (a valid mutant)"
  if po_branch_ok "$MUT"; then
    no "(m) PO can't-ask assertion (a) PASSED against the mutant — the assertion is vacuous"
  else
    ok "(m) PO can't-ask assertion (a) fails against the mutant (the assertion is load-bearing)"
  fi
else
  no "(m) mutant invalid (empty, or identical to the original) — the mutation control cannot be trusted"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
