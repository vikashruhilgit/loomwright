# 04 — Non-interactive question gates (Product Owner pre-persist gate + every gate reachable inside a subagent)

## Problem
The plugin's stated invariant is that question gates fail CLOSED under `--non-interactive` / CI / non-TTY
(CLAUDE.md §"Failure-Mode Invariants"). Two things break it:

1. **Product Owner's pre-persist soft gate has no non-interactive branch.** `agents/product-owner.md:168-184`
   (mirrored in `commands/product-owner.md` around line 342) STOPs and asks via `AskUserQuestion` whenever the
   Assumption Check raises prerequisite flags or architecture conflicts, with the rule "NEVER … persist a
   requirements file … when flags exist without explicit user confirmation". Neither file has a non-interactive
   branch. `/automate "<prompt>"` runs `/product-owner` as its intake (`skills/automate-loop/SKILL.md:87`,
   `commands/automate.md:49`), and `/automate --non-interactive-fallback` is the documented CI mode — so an
   unattended prompt-sourced run either hangs on a question nobody can answer or relies on undefined model
   behaviour when the tool is unavailable.
2. **`AskUserQuestion` does not exist inside subagents.** Claude Code v2.1.284 removes `AskUserQuestion` from every
   subagent's tool set, regardless of its `tools:` list (sub-agents doc, "tools removed from all subagents"). Any
   gate whose prose runs inside a spawned agent therefore cannot ask — its "interactive" branch is unreachable, and
   unless a non-interactive branch exists the agent improvises. `agents/qa-executor.md` already notes it lacks the
   tool; the other agents that mention `AskUserQuestion` (`launch-pad.md` ×13, `product-owner.md` ×5,
   `supervisor.md` ×8) have not been audited for the subagent case.

## Goal
Every question gate in the plugin has a defined, fail-closed behaviour when it cannot ask — because the run is
non-interactive OR because it is executing inside a subagent — and Product Owner's gate stops unattended intake
cleanly instead of hanging or guessing.

## Scope
1. **Gate inventory (deliverable, in the PR body AND as a short table in `docs/ARCHITECTURE_CONTRACTS.md` next to
   the failure-mode invariants):** every `AskUserQuestion` call site in `agents/`, `commands/`, `skills/` with
   columns: gate · file/section · contexts it can run in (main thread interactive / main thread
   `--non-interactive` / subagent / headless `claude -p`) · current can't-ask behaviour · new can't-ask behaviour.
   Determine "can run in a subagent" from the actual spawn sites (e.g. `/qa-executor` Task-spawns
   `loomwright:qa-executor`; `/autonomous` spawns a general-purpose review step), not from the agent's name.
2. **Product Owner gate**: add the can't-ask branch — when flags exist and the run is non-interactive (explicit flag
   passed down from `/automate --non-interactive-fallback` / `/product-owner --non-interactive`) OR PO is executing
   as a subagent: do NOT create Beads tasks or persist requirement files; emit the flags and the draft stories in
   the output with a machine-readable line `po_gate: needs_owner (<n> flags)`. When no flags exist, behaviour is
   unchanged (proceed silently). Add `--non-interactive` to `/product-owner`'s parameter table.
3. **`/automate` prompt intake**: under `--non-interactive-fallback`, pass `--non-interactive` to `/product-owner`;
   a `po_gate: needs_owner` result is handled like today's "0 generated files ⇒ report + stop"
   (`automate-loop/SKILL.md` §2) but the `## Progress` note names the gate and lists the flags — never a wedge,
   never a silent proceed.
4. **Every other gate reachable in a subagent or headless context** (from the inventory): give it an explicit
   can't-ask branch that fails closed with a named status, following the existing precedents
   (`preflight_overlap_detected`, `non_interactive_without_fallback`, `rubric_gate_closed_non_interactive`,
   `resume_ambiguous_non_interactive`). Gates that are main-thread-only by construction get one line saying so.
   Interactive-by-design commands that write nothing without an Accept (`/dreaming`, `/setup`, `/telemetry`) may
   keep "writes nothing" as their can't-ask behaviour — record that in the inventory, no code change required.
5. **Detection signal**: use explicit flags and "am I a subagent" knowledge from the spawn contract, NOT only a TTY
   probe — the stdin-not-a-TTY probe false-positives inside the Claude Code Bash tool (memory
   `autonomous-tty-false-positive`). Where a TTY probe already exists, leave it as an additional signal.
6. **Tests**: seam tests grepping each changed gate for its can't-ask status string; a PO fixture-level test if the
   PO flow has one (else seam only, stated in the PR). **Mutation control:** delete the PO can't-ask branch ⇒ its
   seam test fails.
7. Docs: `commands/product-owner.md` mirrors `agents/product-owner.md` in the SAME commit (memory
   `agent-command-mirror-drift-on-fixes`); CHANGELOG; version bump; token budgets for every grown agent.

## Non-goals
Adding a new question mechanism (file-based park-and-answer is Phase 2's ask-user port). Changing any gate's
interactive options. Changing `/dreaming`'s per-item Accept model. Changing which agents are spawned where.

## Acceptance criteria
- The gate inventory table exists in `ARCHITECTURE_CONTRACTS.md` and covers every `AskUserQuestion` site found by
  `grep -rn AskUserQuestion loomwright/agents loomwright/commands loomwright/skills` (count stated in the PR).
- `grep -n 'po_gate: needs_owner' loomwright/agents/product-owner.md loomwright/commands/product-owner.md` ≥ 1 each.
- `grep -n 'needs_owner' loomwright/skills/automate-loop/SKILL.md` ≥ 1 in §2 prompt source.
- No gate in the inventory has "undefined" as its can't-ask behaviour.
- Full test loop + root checks + token budgets green.

## Verified premises (re-check before starting)
- `agents/product-owner.md:168-184` soft gate + "NEVER run `bd create` (or persist a requirements file …)" rule;
  no non-interactive/TTY/headless match in `commands/product-owner.md`.
- `skills/automate-loop/SKILL.md:87` (prompt source runs `/product-owner`) and the "0 generated files ⇒ report +
  stop" bullet in the same section; `commands/automate.md:58` `--non-interactive-fallback` semantics.
- `AskUserQuestion` mention counts at `a262d00`: launch-pad 13, supervisor 8, product-owner 5, qa-executor 1.
- Claude Code sub-agents doc (read 2026-09-30): `AskUserQuestion` is in the list of tools removed from all
  subagents "even when listed in the `tools` field".

bump = write a `changelog.d/` fragment and run `scripts/bump-version.sh`

## Status: pending

## Depends on
01

## Touches
loomwright/agents/product-owner.md
loomwright/commands/product-owner.md
loomwright/skills/automate-loop/SKILL.md
loomwright/commands/automate.md
loomwright/agents/launch-pad.md
loomwright/commands/launch-pad.md
loomwright/agents/supervisor.md
loomwright/agents/qa-executor.md
loomwright/skills/autonomous-loop/SKILL.md
loomwright/commands/autonomous.md
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/docs/prompt-token-budgets.json
loomwright/docs/vendor-coupling-manifest.json
loomwright/scripts/test-non-interactive-gates-seam.sh
changelog.d/agnostic-phase1-04-non-interactive-gates.md

<!-- loomwright:requirement-closeout -->
## Status: done_with_escalation
- **Completed:** 2026-10-06T18:32:39Z
- **Brief:** .supervisor/jobs/done/2026-10-06-non-interactive-question-gates.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/403
- **Heal:** max_iterations_reached — 1 remaining
