# 05 — Lane coordinator: `/automate --parallel N`

## Status: parked (waits on S1 — write the spike's answers under "Spike findings" below, then set `## Status: pending`)

## Depends on
03, 04

## Touches
`loomwright/scripts/automate-lanes.sh` (new), `loomwright/scripts/test-automate-lanes.sh` (new),
`loomwright/scripts/automate-helpers.sh` (dispatch rows), `loomwright/skills/automate-loop/SKILL.md`,
`loomwright/commands/automate.md`, `loomwright/commands/agent-help.md`, `loomwright/docs/RESULT_SCHEMAS.md`
(§AUTOMATE_RUN), `loomwright/docs/ARCHITECTURE_CONTRACTS.md`

## Problem
One `/automate` run processes one item at a time: RUN took 1h14–4h37 per item across the last four run files, and
nothing else starts until that item's PR is merged and the owner resumes. Items that are independent (item 04 can
now say which) still wait in line.

## Goal
`/automate --parallel N` runs up to N independent items at once. Each item runs in its own isolated lane using
today's per-item loop unchanged; one coordinator plans, launches and tracks the lanes. `--parallel 1` (the
default) is byte-for-byte today's behaviour.

## Design (decisions P2, P4, P6 in 00-overview)
- **Parallelism sits ABOVE the engine, not inside it.** A lane is an ordinary single-item, safe-mode `/automate`
  run. Nothing in §6–§10 of the skill changes for a lane.
- **A lane is a local clone** at `<primary>-lanes/<run_id>/<n>/` — its own primary checkout, so the run lock,
  `state.md`, the `auto_review` toggle, the owned drain and the result sidecars are all lane-local with no edit to
  the 12 primary-anchored scripts.
- **The coordinator only READS lanes** (their run files, `.died` markers, `gh`). It never writes into a lane.

## Scope
1. **`automate-lanes.sh`** (sibling of `automate-trail.sh`, dispatched from `automate-helpers.sh`):
   - `lane-create <runfile> <item>` — clone, set `origin`, `meta-sync.sh pull` (fail CLOSED), write the lane's
     one-item queue; prints the lane path. Deterministic path; a leftover dir is salvaged then refused, never
     silently reused.
   - `lane-launch <lane>` — detached headless launch mirroring `dispatch-pr-review.sh` (nohup wrapper, `claude -p`,
     namespaced `/loomwright:automate`, pinned `--permission-mode` / `--allowedTools` / `--disallowedTools`,
     `--non-interactive-fallback`, `CLAUDE_PID`/`CLAUDECODE` unset, a `.died` marker when the process exits without
     a terminal state). Refuses to launch when the CLI does not advertise a pinnable permission regime.
   - `lane-status <runfile>` — one line per lane: item, lane path, status (`running` / `awaiting_merge` /
     `escalated` / `parked:<reason>` / `died` / `merged`), PR URL — read from the lane's run file and reconciled
     against `gh` (belief vs truth, same posture as §4).
   - `lane-remove <lane>` — only after `meta-sync.sh push` from that lane reports nothing left to push and the
     lane has no unpushed commits; salvage first (`worktree-salvage.sh` precedent). Never `rm -rf` on a dirty lane.
2. **Parent run file.** `## Run Config` gains `parallel: N`. The lane table is an UNTRACKED sidecar
   (`<run_id>.lanes`, a non-`.md` name so the gitignore block already excludes it and `resume-glob` never lists
   it). `## Queue` / `## Progress` keep their contracts; `## Current` names the wave, not one item.
3. **The loop, per wave:** acquire the run lock → `meta-sync pull` → RECONCILE every lane → `plan-waves --max N`
   → `lane-create` + `lane-launch` per item → release the lock → poll `lane-status` until every lane is terminal.
   The primary checkout stays on `main` throughout; the primary's lock is NOT held while lanes run (each lane holds
   its own).
4. **Parks are per lane.** A human gate that fails closed, a rate-limit park, `escalated`, `died` — each parks
   that lane only and is shown in `lane-status`; the other lanes continue. The owner resolves a parked lane by
   opening a session in that lane and running `/automate --resume` there. Rate-limit in one lane does NOT stop
   others automatically — record it and let the owner decide (the cap is account-wide; say so in the notify).
5. **Pre-flight and sibling PRs.** Implement whatever S1 question 2 shows is needed — if siblings trip OVERLAP only
   on files item 01 removed from feature PRs, nothing; otherwise the smallest change that keeps Phase 1.5
   fail-CLOSED for real overlap. Do NOT add a blanket skip.
6. **`--auto-merge` with `--parallel N>1` is refused** in this item (`PARK`-style refusal at INIT). Item 06 adds
   the merge train; until then a parallel run is safe-mode only.
7. **Token ceiling.** `--max-tokens` applies to the SUM across lanes: the coordinator records every lane's session
   ids in the parent `## Progress` so `read-token-ledger.sh --run-id` sees them all; checked between waves.
8. **RESUME.** `resume-glob` still lists only the parent. RECONCILE rebuilds lane belief from lane run files +
   `gh`; a lane dir that vanished is `gone` and needs a human, never a silent re-run.
9. **Tests** (`test-automate-lanes.sh`, hermetic, `claude` stubbed): create/launch/status/remove round trip;
   `--parallel 1` produces NO lane and the existing suites pass unchanged; one lane dying does not change another's
   status; `lane-remove` refuses a lane with unpushed metadata; INIT refusal of `--auto-merge --parallel 2`.
   **Mutation control:** a coordinator write into a lane's run file must be detectable by a test.
10. **Docs:** skill §1 non-goals (remove "Parallel / multi-item execution"; restate §8 as "one open PR per lane"),
    new §"Lanes", §11's concurrent-run paragraph, `commands/automate.md` flags, `agent-help.md`,
    `RESULT_SCHEMAS.md` §AUTOMATE_RUN. No new agent; the command count does not change.

## Non-goals
Merging (item 06). More than one wave running at once. Lanes on other machines or in the cloud. A `-runner` agent.
Inferring independence without item 04's declarations.

## Acceptance criteria
- A three-item fixture queue with disjoint `Touches` reaches three READY PRs in one `/automate --parallel 3` run,
  each lane's run file showing its own `owned_drain_result` and `suppressed_default_dispatch: true`.
- `/automate` with no `--parallel` flag: `test-automate-helpers.sh` and `test-automate-trail.sh` pass unchanged and
  no lane directory is created.
- Killing one lane's process leaves the others running and shows that lane as `died`.
- Full test loop + root checks green.

## Validation (must pass before merge)
1. **Baseline:** full loop on the base and on the branch; both `<passed>/<total>` lines in the PR body.
2. **Unchanged path (`--parallel` absent or 1):** `test-automate-helpers.sh`, `test-automate-trail.sh`,
   `test-automate-dismissed.sh` and `test-dispatch-pr-review.sh` pass with ZERO edits to those files in this PR
   (`git diff --stat origin/main -- <those four>` is empty). Then one real single-item `/automate` run on this repo
   without the flag: no lane directory exists afterwards, the run file has no `parallel:` line and no `.lanes`
   sidecar, and its `## Progress` has the same step sequence as the previous sequential run file.
3. **Invariant greps, pasted:** the positive-form `gh pr merge --squash` grep resolves to the same five surfaces;
   `git grep -n 'run-lock.sh' loomwright/scripts/automate-lanes.sh` shows the coordinator never passes `--root`
   pointing into a lane; no coordinator code path writes under a lane directory.
4. **Running system:** `/automate --parallel 2` on two real, disjoint, small items. Paste `lane-status` at launch
   and at the end, each lane's `## Current` (own `owned_drain_result`, `suppressed_default_dispatch: true`), and
   `run-lock.sh status` from the primary and from each lane while both run. Kill one lane's process once and paste
   `lane-status` showing `died` for it and the other unaffected.
5. **Leak check:** after the run, `git worktree list`, `ls <primary>-lanes/`, `pgrep -lf 'claude -p'` and the
   primary's `.supervisor/config.json` are exactly as before the run (or the leftover is named and explained).
6. **Rollback:** `git revert` of the PR. A run in flight with lanes must be finished or abandoned first — the
   steps: `lane-status`, close or merge each lane PR by hand, `meta-sync.sh push` in each lane, remove the lane
   directories. Write these in the PR body.

## Spike findings
_(fill in from S1 before un-parking: isolation, pre-flight classification, headless gate behaviour, merge state)_

## Verified premises (re-check before starting)
- `run-lock.sh` "resolve root" block and `build-state.sh` "Worktree-safe anchoring" block; 12 non-test scripts
  match `git worktree list --porcelain`.
- `dispatch-pr-review.sh` header (headless regime, `PERMISSION_REGIME_UNPINNABLE`, `.died` marker, nohup wrapper).
- `automate-loop/SKILL.md` §1 non-goals, §3 run-file template, §4 RESUME, §8, §11 concurrent-run constraint.
- `autonomous-loop/SKILL.md` INIT step 0 (non-interactive detection) and the `--non-interactive-fallback` gate
  behaviour; project memory notes a TTY false positive here — S1 question 3 settles it.
- Claude Code strips `AskUserQuestion` from subagents — which is why a lane is a separate headless process and
  parks, rather than a subagent that asks.

## Status note
Parked until S1 is run. Do not start from this file as written.
