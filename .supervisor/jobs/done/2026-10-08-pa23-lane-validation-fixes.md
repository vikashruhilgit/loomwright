# Supervisor Job: pa/05 Validation 4/5 fixes A — the seven lane-coordinator release blockers

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (extra worktree `ai-agent-manager-pa05-engine` — detached at #426's old head `8226dfe`; not used by this job, do not touch it)
- **Source requirement:** .supervisor/requirements/parallel-automate/23-pa05-validation-fixes-a.md
- **Base commit:** 91adff5a584c1596294a72a4351cb3d0d51429bf

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2-compatible shell + jq, the same stack `automate-lanes.sh` already uses |
| 2 | Dependency Availability | GO | no new dependency; `meta-sync.sh`, `run-lock.sh`, `automate-helpers.sh` already on `main` |
| 3 | Architecture Fit | GO | every fix stays inside the lane seam pa/05 (#426, merged `91adff5`) created; sequential path untouched |
| 4 | Scope vs Supervisor Capability | CAUTION | 7 independent defects in one 1572-line script; single-agent by the Decomposition Threshold (all share `automate-lanes.sh`), but a long worker run — see Risk Assessment |
| 5 | Hard Blockers | GO | none; a real `--parallel` re-validation needs the owner's typed command (operator step, not the worker's) |

**Overall Verdict:** CAUTION

## Task
**Goal:** Fix the seven lane-coordinator defects (F1, F2, F4, F5, F9, F10, F11) that pa/05's Validation 4/5 run found, so a `--parallel` wave runs §14 exactly as written with no hand steps, and nothing a lane or the coordinator pushes makes a done claim for unmerged work.

**Problem Statement:**
The owner needs `/automate --parallel N` safe to release because pa/05 (#426) is merged but its release bump is held until this fix and item 24 merge.
Currently, the real `--parallel 2` validation run (`automate-2026-10-08-033739`, PRs #428/#429 closed unmerged) needed five hand interventions and pushed false done claims to `loomwright-meta` (corrected by hand at meta `b8697aa`). This blocks any real parallel run.
Success looks like: each defect has a hermetic test that fails on `91adff5` and passes on the branch, and §14 + `ARCHITECTURE_CONTRACTS.md` `## Lanes` describe exactly what the code does.

The full defect descriptions, with the exact code lines and the run evidence, are in the source requirement's `## Problem` (read it first); this brief does not restate them. Per-defect locations on `main` (`loomwright/scripts/automate-lanes.sh`):
- **F1** — `lanes_status` returns `no lane table … no lanes` before reaching `lanes_leaks` when `_lanes_table_for` finds no `<run_id>.lanes`; §14 "The per-wave loop" step 5 runs `--leaks --snapshot` BEFORE step 6's `lane-create`.
- **F2** — `lanes_answer` runs `_lanes_gate` (authority + admission) before writing `$af`; a HELD admission (exit 4) records nothing.
- **F4** — `_lanes_launch_go`'s `--resume-run` branch calls `_lanes_spawn "/loomwright:automate --resume $LN_RUN" ""` — an EMPTY session id, so a fresh session; the lane's `run.lock` (session-id re-entrant only, reclaim only at dead-pid AND age ≥ 1800 s in `run-lock.sh`) then stalls the resume. `_lanes_session_id` already yields the lane's last session.
- **F5** — `lanes_readiness`'s report group ends `echo "- $eline"; [ -n "$erows" ] && printf '%s' "$erows"` → exits 1 on empty `erows`, skipping `&& mv`.
- **F9** — `_lanes_leak_sections` lists `ls -1 "$p-lanes"`; `lanes_remove` salvages to `$LN_ROOT/salvage` and the stream logs live in `$LN_ROOT` (= `<primary>-lanes/<run_id>/`), so a removed lane always reads `lanes-dir: changed`.
- **F10** — `lanes_remove --abandon` progress-appends `salvaged to $sv` (an absolute path) to the PARENT run file, and its `state ${state:-unknown}` is the lane-table column, not the lane's real state.
- **F11** — `lanes_convert_ready` pushes only `.supervisor/automate/$LN_RUN.md`; `_lanes_remove_refusals` then refuses `metadata not pushed (local_ahead N)` via `meta-sync.sh status`; a whole-lane `meta-sync push --root <lane>` (the only hand workaround) bypasses `trail-pr`'s evidence gate.

## Acceptance Criteria
- [ ] Given no `<run_id>.lanes` table exists yet, when the coordinator runs `lane-status <parent_runfile> --leaks --snapshot`, then the snapshot is written (deriving the parent run id and primary from `<parent_runfile>`) — never a silent `no lanes`. A snapshot request that cannot be written exits non-zero naming why (the ONE exception to `lane-status`'s fail-SAFE exit 0, carved out in `ARCHITECTURE_CONTRACTS.md` `## Lanes` "Failure posture"), and the F1 test covers both the no-table write and the unwritable branch (F1)
- [ ] Given admission says `load busy` (or HELD for any admission reason), when the owner's answer is sent with `lane-answer`, then: (a) the answer is validated against the question's labels exactly as today, and a coordinator-side pending file in the primary's `.supervisor/automate/` stores ONLY the validated answers, the note and `via` — never an owner command; (b) plain `lane-status` (observation, fail-SAFE, no `--owner-command`) only SHOWS the lane as `answer_pending` and never spawns anything; (c) delivery happens only under an owner command typed in the CURRENT session — the coordinator's `/automate --resume <run_id>` poll passes it as `--owner-command` to a delivery form of `lane-answer` (e.g. `lane-answer <lane> --deliver-pending --owner-command '<cmd>'`) that re-runs the full `_lanes_gate`; (d) at delivery the stored answers are re-checked against the recorded question's labels AND the lane's still-deferred `tool_use_id`, and a mismatch refuses delivery; nothing is written into the lane before delivery. A test proves a pending file with no current-session owner command is NOT delivered (F2)
- [ ] Given a lane that `died` after its PICK took the lane run lock, when `lane-launch <lane> --resume-run <lane run_id>` runs, then the resume does not wait on that lock (preferred: it resumes the lane's last session id so the lock is re-entrant; a fallback fresh session is used only when that session cannot be resumed). The path taken is recorded in the lane's `## Progress` by the LANE's own engine on entry — never by the coordinator, which never writes the lane's run file or lock after launch; `--force-unlock` stays human-only (F4)
- [ ] Given an item whose `## Validation` names no headline repro (and/or empty `vrows`/`crows`/`frows`), when `lane-readiness` runs, then the report IS written and no stray `*.tmp.*` file is left; a genuine write failure still prints `report not written (unwritable)` (F5)
- [ ] Given a clean wave whose lanes were all removed (salvage kept), when `lane-status --leaks` runs against the wave-start snapshot, then it reads `leaks: none`, and the salvage plus stream logs are still kept and findable at a documented location (F9)
- [ ] Given any lane subcommand, when it writes to a run file, then no line it writes contains an absolute path (no token starting with `/` — paths are repo-relative or the `<primary>-lanes/…` form), so in particular no `$HOME` path, and `lane-remove --abandon`'s line reports the lane's real state (e.g. `gone`) from the same reader `lane-status` uses (F10)
- [ ] Given a lane whose item carries a done stamp for an UNMERGED PR, when the §14 wave end runs (convert, then a PR closed unmerged, then `lane-remove --abandon`), then the lane is removable with no hand step AND nothing pushed to the metadata branch carries a done claim or a `jobs/done/` brief for unmerged work; a closed-unmerged lane gets the `done_with_escalation — ABANDONED (<row>)` stamp shape `reconcile-status` writes (F11)
- [ ] Given each of F1, F2, F4, F5, F9, F10, F11, when its new hermetic test runs, then it fails against the pre-fix code at `91adff5` and passes on the branch (proof recorded in the PR body). `91adff5` stands in for the requirement's `8226dfe` (the merge of that head — identical lane code)
- [ ] Given no `--parallel` flag, when a sequential `/automate` runs, then nothing changes: `pick-guard` prints `ok` with no `*.lanes`, and the existing no-flag tests are untouched
- [ ] Given §14 of `skills/automate-loop/SKILL.md` and `## Lanes` of `docs/ARCHITECTURE_CONTRACTS.md`, when the change lands, then both describe steps 5–6, the wave end, the `answer_pending` state, the F2 delivery form and the salvage/log location exactly as the code does, updated in the same change — including the `## Lanes` "Location", "Single write", "Launch authority" and "Failure posture" rows where they are affected. No other SKILL section changes EXCEPT §13 "Honest limits" item 1, which must name the F11 wave-end path (requirement Scope 7)
- [ ] Given the requirement's Validation 3 (a live `--parallel 2` run on two new throwaway items, on the owner's typed command), when the PR is otherwise READY, then the PR body lists it under "Not verified" as an operator step and the PR is NOT treated as merge-ready until the owner's run evidence is pasted — the worker never starts that run

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Fix F1/F2/F4/F5/F9/F10/F11 in the lane coordinator, with tests and contract docs | all | 6 modify, 1 create | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "changelog.d/parallel-automate-23-pa05-validation-fixes-a.md"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "answer_pending"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-lanes.sh", name: "Validation 4/5 fixes"}
requires: []
lanes:
  - "loomwright/scripts/automate-lanes.sh"
  - "loomwright/scripts/test-automate-lanes.sh"
  - "loomwright/scripts/run-lock.sh"
  - "loomwright/scripts/test-run-lock.sh"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "changelog.d/parallel-automate-23-pa05-validation-fixes-a.md"
external_requires: []
```

The `Validation 4/5 fixes` symbol is the new test-group header in `test-automate-lanes.sh`, following that file's existing `# ---- <Letter>: <title> ----` convention (e.g. `# ---- Z: Validation 4/5 fixes (parallel-automate/23) ----`). `run-lock.sh` / `test-run-lock.sh` are in the lane only in case the F4 fallback needs a lock change; the preferred F4 fix (resume the lane's last session id) needs none — leave them untouched if unused.

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` |

## House Rules

> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Scope: 7 independent fixes in one 1572-line script is a long single-worker run (Feasibility (Phase 2.5), check 4) | MEDIUM | Work and commit defect by defect (one commit per F-number, test + fix together); if the worker runs out of turns it is resumed, never respawned |
| F4 preferred fix depends on `claude -p --resume <sid>` working for a session that was KILLED (no terminal result). Seen working for resume-after-answer; not yet for a killed session | MEDIUM | Keep the fresh-session fallback; the hermetic test stubs `claude`, so record "killed-session resume not verified live" under Not verified unless the operator's re-validation run proves it |
| F11 is security-adjacent: a wave-end push that skips the evidence gate re-creates the false-done incident (meta `b8697aa`) | HIGH | Push only an evidence-gated list (reuse `trail-pr`'s gate or the same predicate); a test with an unmerged done stamp must prove no done claim is pushed; never `meta-sync push` without `--paths-from` |
| F2 must not weaken launch authority. `_lanes_gate`'s authority check is only "the owner string is non-empty", so a STORED owner command replayed later would always pass and becomes a forgeable authority token (any process that can write the primary's `.supervisor/automate/` — a lane session with Bash included — could plant one) | HIGH | The pending file never holds an owner command. Delivery requires an owner command typed in the current session (the coordinator's `/automate --resume <run_id>` poll), passed fresh as `--owner-command` to the delivery form, which re-runs the full `_lanes_gate`; plain `lane-status` stays observation-only. Delivery re-validates the stored answers against the question's labels and the lane's still-deferred `tool_use_id`. Test: a pending file with no current-session owner command is not delivered. The no-write-into-the-lane rule is unchanged |
| Contract restatement drift: §14 and `ARCHITECTURE_CONTRACTS.md` `## Lanes` restate each other (house rules above) | MEDIUM | Update both in the same commit as the code; grep both for `--snapshot`, `lane-convert-ready`, `salvage`, `L<n>.*` before committing |
| Release bump convention: the normal sequential PR runs `bump-version.sh` as its last commit | HIGH | **Do NOT run `scripts/bump-version.sh`.** Owner decision 2026-10-08: the pa/05 release is held until items 23 and 24 merge; this PR adds only its `changelog.d/` fragment (`<!-- bump: patch -->`) beside the still-pending `parallel-automate-05-lane-coordinator.md` |
| bash 3.2 / BSD traps on macOS (project memory `ead04b14`; repo lessons) | LOW | `"${arr[@]}"` guarded under `set -u`; no GNU-only flags; validate with `bash scripts/ci-local.sh` |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-08-pa23-lane-validation-fixes.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-10-08T08:54:18Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/434
- **Branch:** feature/pa23-lane-validation-fixes
- **Files changed:** 5
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** All seven lane-coordinator defects (F1 F2 F4 F5 F9 F10 F11) fixed, one commit each with a Z-group test failing on 91adff5; docs in sync; changelog fragment only (release held). Phase 4.5 PASS (consistency_audit) with 6 dismissed findings (3 MEDIUM, 3 LOW) left for the owner's decision; ground_truth 2/2 pass; rules gate none; risk_classification high_risk=true (advisory).

## Not verified
- **Validation 3: live /automate --parallel 2 run on two new throwaway items** — operator step on the owner's typed command; PR not merge-ready until its evidence is pasted (subtask 1)
- **F4: claude -p --resume of a KILLED session** — claude is a stub in the hermetic tests (subtask 1)
- **F4 fallback fresh session vs the dead session's run.lock** — run-lock.sh unchanged; the fallback may still wait for the TTL reclaim (subtask 1)
- **F11 against the real meta-sync.sh status after the wave-end push** — test stub models the managed set (subtask 1)
- **Lane engine writing 'lane resume:' to its own ## Progress** — §14 instruction to the lane LLM; no script enforces it (subtask 1)
