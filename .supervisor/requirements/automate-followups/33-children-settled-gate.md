# 33 — Children-settled gate: non-plugin spawns settle, and the check runs before anything is published


## Merged from (2026-10-05, owner decision before the S3 wave spike)
- Part A: `17-children-settled-non-plugin-spawns.md` — `check-children-settled.sh` treats a non-plugin (`general-purpose`) spawn as never settled
- Part B: `25-children-settled-before-publish.md` — 25 — The children-settled check runs before anything is published, by mechanism, not by prose order

The originals are parked with a pointer here. Their text is kept below VERBATIM as parts (headings
demoted, their Status / Depends on / Touches folded into this file's own sections). Nothing was paraphrased.

## Goal
One change set over `check-children-settled.sh` and its hook: a non-plugin (`general-purpose`) spawn and a turn-limit stop are read as settled correctly (A), and the check runs before anything is published, by mechanism (B).

## Acceptance criteria
- Every part's own acceptance criteria hold, on one branch and one PR.

## Validation (must pass before merge)
1. Baseline full loop once for the merged branch, `<passed>/<total>` and `SKIP` counts, base and branch.
2. Every part's own Validation steps, labelled by part in the PR body. A part with no Validation section is
   checked by running its acceptance criteria, and the PR body says so.
3. Any "Running system" step a part names is run, or listed under "Not verified" with the reason.
4. Rollback: `git revert`.

## Parts

### Part A — `check-children-settled.sh` treats a non-plugin (`general-purpose`) spawn as never settled

#### Evidence
- `.supervisor/logs/<session>.jsonl`: each of the three agents has an `agent_identity` row (agent_type
  `general-purpose`) and only `agent_lifecycle` `state: working` rows — no `subtask_complete` / `token_ledger` /
  `agent_lifecycle: failed` terminal row. The `loomwright:loomwright:worker` in the same session has `subtask_complete`
  rows and settles.
- `check-children-settled.sh --all` joins EVERY `agent_identity` row against a terminal row, so any Launch Pad
  discovery / research spawn of a non-plugin type in the same session makes point 5 fail (interactive ⇒ ask;
  `--non-interactive` ⇒ fail CLOSED `children_unsettled`), even though nothing is unfinished.

#### Scope (recommendation — trace before fixing)
- Confirm which hook writes the terminal row and why it does not fire (or is filtered) for `general-purpose`
  SubagentStop payloads (identity rows ARE written for them, so the asymmetry is the defect).
- Either emit a terminal `agent_lifecycle` row for every SubagentStop that has an identity row, or scope `--all` to
  agent types whose stop is observed — never silently drop the check. Fixture: a session log with a settled
  general-purpose spawn must read `settled`.

#### Second cause seen (2026-10-04, wave w1 lane w1-08) — widens this item
The children-settled gate also failed on two **plugin** agents: `loomwright:loomwright:context-keeper` runs that hit
Context-Keeper's 3-turn limit AFTER their writes landed (verified in the lane's `state.md`: the pre-flight decision
and the worker-result row). Each had only `agent_identity` + `working` rows, no terminal row. So the gap is not only
"non-plugin agent types have no SubagentStop matcher": **any child that ends by hitting its turn limit leaves no
terminal lifecycle row**, and the gate cannot tell it from a hung child. The fix must cover both: a terminal row
(e.g. `agent_lifecycle: ended reason=max_turns`) for every SubagentStop, whatever the agent type and however it
ended. Both lanes' owners answered "proceed anyway", so this gate is producing human questions that carry no signal. **Third occurrence (wave w2, lane w2-30):** a `worker` stopped at its 40-turn limit after committing; a continuation worker finished. Again no terminal row, again "proceed anyway". That makes three false gate questions in one day (S1 v2: an `Explore` agent; w1-08: two `context-keeper`s; w2-30: a `worker`), so this item should be scheduled early.


### Part B — 25 — The children-settled check runs before anything is published, by mechanism, not by prose order

#### Problem
FINALIZE's pre-merge safety gate (`skills/async-orchestration/SKILL.md` §"Phase 4 FINALIZE procedure", checklist
point 5 "Every spawned child settled", run with `loomwright/scripts/check-children-settled.sh`) is meant to pass
BEFORE any merge, push or PR. In S1 v2 (2026-10-04) lane v2-b disclosed: "I ran this check AFTER pushing and opening
PR #372; the spec puts it before." Nothing enforces the order; it is a numbered list in prose, so a gate meant to
block publication can silently become an after-the-fact advisory. (v1's lane B hit the same gate for a different
reason, a worker killed by the 600 s background ceiling.)

#### Goal
A Supervisor run cannot push its feature branch or open its PR until the children-settled check has passed (or
been explicitly skipped with `--skip-children-check`, recorded) for that session, and an out-of-order attempt is
refused with a clear reason.

#### Scope
1. **A FINALIZE gate marker:** when point 5 passes (or is skipped by the flag), write
   `.supervisor/logs/<session_id>.finalize-gate` holding `{children_check, head_sha, ts}`; any other outcome writes
   nothing.
2. **Enforcement at the publication seam:** the existing `PostToolUse[Bash]` `gh pr create` hook path and the
   FINALIZE push step both read the marker for the current session and HEAD. Pick the enforcement point after
   reading `hooks/hooks.json` and `docs/HOOKS.md` (a `PreToolUse[Bash]` matcher on `git push` / `gh pr create`
   is the natural one; follow the fail-CLOSED blocking-hook rules there, no `|| true`). A missing or stale marker
   (HEAD moved after the check) ⇒ block with "run FINALIZE point 5 first".
3. **Scope the block to Supervisor runs only:** a session with no `.supervisor/state.md` `## Session` block, or a
   push outside FINALIZE (a drain fix push, a human's push), is never affected.
4. **Prose:** point 5's text says the push and PR are blocked until the marker exists.
5. **Tests:** push before the check ⇒ blocked; after a passing check ⇒ allowed; HEAD moved after the check ⇒
   blocked; `--skip-children-check` ⇒ allowed and recorded; a non-Supervisor session ⇒ untouched.

#### Non-goals
- The false positive for finished non-plugin agents (`Explore`) is `automate-followups/17`; this item only fixes
  the ORDER.

#### Acceptance criteria
- In a real Supervisor run, the log shows the children check strictly before the first `git push` of the branch.

#### Validation (must pass before merge)
1. Baseline full loop, `<passed>/<total>` and `SKIP` counts, base and branch.
2. Unchanged path: drain pushes and human pushes are unaffected (test).
3. Running system: one real single-agent Supervisor run; paste the marker and the push order from the log.
4. A failure this must catch: remove the marker check ⇒ the "push before check" test passes when it must fail.
5. Rollback: `git revert` (the marker file is inert without the check).

#### Evidence
S1 run record, relay 5; archived lane log `ai-agent-manager-lanes-v2/archive/v2-b/s1h-lane.log`.


## Depends on
none

## Touches
loomwright/agents/supervisor.md
loomwright/docs/HOOKS.md
loomwright/docs/result-schemas/agent-lifecycle-jsonl.md
loomwright/docs/result-schemas/supervisor-result.md
CLAUDE.md
loomwright/hooks/hooks.json
loomwright/scripts/check-children-settled.sh
loomwright/scripts/emit-lifecycle.sh
loomwright/scripts/test-check-children-settled.sh
loomwright/scripts/test-emit-lifecycle.sh
loomwright/skills/async-orchestration/SKILL.md
changelog.d/automate-followups-33-children-settled-gate.md

## Touches re-pointed 2026-10-07 (S3 operator f849e0cc, after pa/11's split — #408, v15.124.0)
- `RESULT_SCHEMAS.md` → `result-schemas/agent-lifecycle-jsonl.md` (Part A's terminal `agent_lifecycle` row for
  every SubagentStop; this file already documents the children-settled join — `test-check-children-settled.sh`
  reads it as `$SCHEMAS`) + `result-schemas/supervisor-result.md` (documents `error: "children_unsettled: …"`;
  Part B's FINALIZE gate marker).
- **Added (undeclared but obvious, wave-2 lesson):** `CLAUDE.md` — Part B adds a fail-CLOSED blocking
  `PreToolUse[Bash]` hook with no `|| true`, which falsifies CLAUDE.md §"Plugin Hooks"' statement that the
  test-integrity guard's two leaves are "the ONLY two command-hook leaves in `hooks.json` that carry NO `|| true`".

## Amended 2026-10-07 — evidence only (owner, relayed by S3 session 2216aefd)
- **S3 wave 2, #408 (parallel-automate/11, lane s3-f):** at FINALIZE the children-settled check read **7
  turn-limit-stopped agents** as unsettled — 5 `worker`s stopped at 40 turns and 2 `context-keeper`s at 3 — each
  with no terminal lifecycle row. The owner answered "proceed". Fourth occurrence of Part A's "second cause"; still
  a gate question that carries no signal. (S3 record §"Wave 2 result", Questions.)

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-07T06:49:46Z
- **Brief:** .supervisor/jobs/done/2026-10-07-automate-followups-33-children-settled-gate.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/410
