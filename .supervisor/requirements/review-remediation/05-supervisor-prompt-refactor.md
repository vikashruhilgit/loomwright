# 05 — Supervisor prompt refactor: extract phase protocols into skills (P1, large)

## Goal
Shrink `loomwright/agents/supervisor.md` from 1,647 lines to a ≤600-line phase state machine
by extracting phase protocol bodies into on-demand skills — the pattern `review-pr.md`
(133 lines + `review-heal` skill) and `self-heal-advisory` already prove. Reliability, not
aesthetics: prompt size is the instruction-following ceiling, and the historical failure
modes (skipped Phase 4.5, completion-tail misses) are lost-context signatures.

## Evidence
- supervisor.md = 1,647 lines. Phase 0 preamble ~160 lines / ~9 config concerns;
  Phase 1.5 PRE-FLIGHT SYNC ~88 lines; Phase 4.5 ~119 lines orchestrating code-reviewer,
  fix workers, rubric-grader, drain dispatch, churn ledger, Twin contract write.
- Precedent inside the repo: review-pr agent (133 lines) + review-heal skill;
  self-heal-advisory skill already holds part of Phase 4.5 and is "read on demand at
  Phase 4.5 entry, deliberately not preloaded".

## Approach (do a /launch-pad + Plan Review pass before executing — this is the risky one)
Extract, don't rewrite. Each extraction moves a protocol body verbatim-first into a skill,
leaves a short phase stanza in the agent (entry condition, skill to read, exit condition,
failure/error values), then trims duplication inside the skill on a second pass.

Extraction slices (one subtask each; sequential merges):
1. **Phase 1.5 → new skill `preflight-sync`** (CLEAR/OVERLAP/SUPERSEDED classification,
   soft-gate AskUserQuestion, --non-interactive fail-closed, ≤6-call bound,
   --skip-preflight-sync). Skills count 57→58.
2. **Phase 4.5 → complete the move into `self-heal-advisory`** (or a sibling
   `self-heal-loop` skill if advisory-vs-loop separation is cleaner — decide at plan time):
   review spawn, fix loop, rubric-grader spawn conditions, completion tail (job move,
   state-completed, requirement close-out stamp), drain dispatch step 5.5, churn-ledger and
   Twin-contract writes. The completion-tail guard (refuse success when
   skip_self_heal_requested=false ∧ phase45_review_invoked=false) MUST survive — keep the
   guard condition itself in the agent file (it is a gate, gates stay visible), move only
   the procedure.
3. **Phase 0 config resolution → skill `supervisor-config`** (flag parsing/defaults table,
   cost-profile resolution, base-branch handling, env detection). Alternatively fold into
   the existing `workflow-management` skill — decide at plan time; prefer whichever keeps
   preloaded-token cost flat.
4. **Phase 4 FINALIZE merge/PR mechanics → extend `workflow-management` or
   `async-orchestration`** (pre-merge checklist, sequential merge, worktree cleanup,
   push/PR, PR-base self-verify).
Optional slice 5 (same pattern, separate PR): launch-pad.md Phase 3's six advisory-source
reads → one `advisory-context` skill; launch-pad 853→~550 lines.

Preloading decision per skill: Supervisor already preloads 7 skills. New protocol skills
should be READ AT PHASE ENTRY (like self-heal-advisory), NOT preloaded — otherwise the
context cost just moves rather than shrinks. State this explicitly in each skill header.

## Constraints / invariants (all hard)
- **Agent↔command split-brain guard (added 2026-07-06):** `commands/supervisor.md` is
  LOAD-BEARING — it is the workflow body that inline `/supervisor` executes and that
  `/autonomous` Step 0 loads at runtime; `agents/supervisor.md` is the `-runner` authority.
  Every phase extraction MUST update BOTH surfaces in the same slice so they stay
  semantically mirrored (same phase stanza shape, same skill authority pointer, same gate
  conditions). check-command-sync.sh covers only part of this — do a manual side-by-side
  phase-enumeration diff per slice, and add an acceptance check: for every phase, both
  files name the SAME authority skill. A refactor that slims agents/supervisor.md while
  commands/supervisor.md keeps the old inline protocol creates a split-brain Supervisor
  (inline path runs the old logic, runner path the new) — this is the #1 failure mode of
  this item.
- ZERO behavior change. Every gate, error value, bound, and invariant keeps identical
  semantics: bimodal failure philosophy; completion-tail guard; sole-writer contracts;
  never-merge; PR-base verification; tool-call budgets (50 supervisor / 60 execute-manager);
  Phase 4.5 always-runs rule; requirement close-out stamping.
- Prompt-is-program (memory): full multi-iteration dynamic state-trace of the refactored
  agent — fresh run, --continue resume, fast-path single-subtask, parallel path,
  --skip-self-heal, non-interactive — before review.
- SUPERVISOR_RESULT schema untouched (no schema_version bump). SubagentStop validator in
  hooks.json must still pass unchanged.
- Doc surfaces: CLAUDE.md agent table, SKILLS_INDEX.md (+ new rows), skills count 57→58/59
  everywhere the doc-currency gate scans, AND the gate's known blind spots — grep phase
  enumerations in agent-help.md/command docs for stale phase text. Minor version bump.
- Descriptive anchors, not absolute line refs, in all moved prose (memory: line-ref drift).
- One extraction slice per subtask/PR-reviewable unit; run the full test suite + a real
  smoke `/supervisor --dry-run` between slices.

## Acceptance criteria
- [ ] supervisor.md ≤600 lines; every phase stanza names its authority skill.
- [ ] New/extended skills carry version frontmatter + SKILLS_INDEX rows; index-sync CI
      check (item 03) green.
- [ ] Diff-review demonstrates verbatim-move (reviewer can align old/new text); any
      intentional wording change listed explicitly in the PR description.
- [ ] Completion-tail guard, budget numbers, and all error values present post-refactor
      (grep each old error string; count unchanged).
- [ ] A real end-to-end /supervisor run (small task) passes with Phase 4.5 executing.

## Out of scope
Changing flag semantics or defaults, merging agents, execute-manager refactor,
qa-executor L1/L2 rescoping (separate future item if desired).

## Status: done
- Completed: 2026-07-07 via /automate (PR #95, v15.4.0)
