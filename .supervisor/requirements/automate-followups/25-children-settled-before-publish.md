# 25 — The children-settled check runs before anything is published, by mechanism, not by prose order

## Status: parked (merged 2026-10-05 into `automate-followups/33-children-settled-gate.md` as Part B — do not run this file; work the merged item)

## Problem
FINALIZE's pre-merge safety gate (`skills/async-orchestration/SKILL.md` §"Phase 4 FINALIZE procedure", checklist
point 5 "Every spawned child settled", run with `loomwright/scripts/check-children-settled.sh`) is meant to pass
BEFORE any merge, push or PR. In S1 v2 (2026-10-04) lane v2-b disclosed: "I ran this check AFTER pushing and opening
PR #372; the spec puts it before." Nothing enforces the order; it is a numbered list in prose, so a gate meant to
block publication can silently become an after-the-fact advisory. (v1's lane B hit the same gate for a different
reason, a worker killed by the 600 s background ceiling.)

## Goal
A Supervisor run cannot push its feature branch or open its PR until the children-settled check has passed (or
been explicitly skipped with `--skip-children-check`, recorded) for that session, and an out-of-order attempt is
refused with a clear reason.

## Scope
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

## Non-goals
- The false positive for finished non-plugin agents (`Explore`) is `automate-followups/17`; this item only fixes
  the ORDER.

## Acceptance criteria
- In a real Supervisor run, the log shows the children check strictly before the first `git push` of the branch.

## Validation (must pass before merge)
1. Baseline full loop, `<passed>/<total>` and `SKIP` counts, base and branch.
2. Unchanged path: drain pushes and human pushes are unaffected (test).
3. Running system: one real single-agent Supervisor run; paste the marker and the push order from the log.
4. A failure this must catch: remove the marker check ⇒ the "push before check" test passes when it must fail.
5. Rollback: `git revert` (the marker file is inert without the check).

## Evidence
S1 run record, relay 5; archived lane log `ai-agent-manager-lanes-v2/archive/v2-b/s1h-lane.log`.

## Depends on
none

## Touches
loomwright/hooks/hooks.json
loomwright/scripts/check-children-settled.sh
loomwright/scripts/test-check-children-settled.sh
loomwright/skills/async-orchestration/SKILL.md
loomwright/agents/supervisor.md
loomwright/docs/HOOKS.md
changelog.d/automate-followups-25-children-settled-before-publish.md
