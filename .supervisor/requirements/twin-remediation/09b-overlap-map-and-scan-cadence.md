# 09b — Native overlap entries for the poll loop and native worktree isolation, KEEP verdicts for the rest, and a scan reminder on every minor bump

## Status: pending

## Split from
`twin-remediation/09-native-flow-adoption.md` items 2–5, re-verified read-only 2026-10-22 against main 7b7cb08 /
v17.14.1 and scoped by the owner. Item 1 (baseline refresh) shipped in #489; item 4's named safe adoption
(`onFailure: "block"`) shipped in #494; 2f (Remote Control, PreCompact) is already recorded keep-deferred in
`CAPABILITY_BASELINE.json` `known_not_adopted` (re-checked 2026-10-12).

## Problem
`/capability-check` last scanned at plugin 15.132.0; the plugin is now at 17.14.1 — two major versions with no
scan, because nothing triggers one (item 09 tied the cadence to item 07's per-release ritual, which was abandoned).
Two overlaps carry real deletion or prerequisite value and are undocumented: the Execute Manager's hand-rolled poll
loop (`agents/execute-manager.md` still runs `TaskOutput(... timeout=poll_interval)`, 2s green interval; the new
`supervisor-next-step.sh` leaves that loop alone) and native `isolation: worktree` (its old blocker, the plugin's
`WorktreeCreate` hook, was removed in v15.66.0, but the 2026-10-12 scan found the native worktree branches from the
default branch, not from the run's feature branch).

## Goal
A short committed overlap doc with two evidenced entries and recorded KEEP verdicts, and a scan reminder that fires
on every minor version bump.

## Scope
1. NEW `loomwright/docs/NATIVE_OVERLAP.md`:
   - **2b** Execute Manager poll loop ↔ background Agent execution with completion notification: what each does,
     cited from the plugin's files and from the platform docs/changelog as recorded in `CAPABILITY_BASELINE.json`
     (read-before-write: no capability asserted from recollection; anything not in the baseline is marked
     "unverified"). Verdict KEEP OURS / ADOPT NATIVE / HYBRID / BLOCKED, with the port it maps to in
     `CORE_CONTRACT.md` §3.3 (native primitives go in the Claude adapter, never the core). An ADOPT or HYBRID verdict
     gets a follow-up draft under `.supervisor/requirements/proposed/`; no orchestration behaviour changes here.
   - **2d** worker worktrees ↔ `isolation: worktree`: verdict BLOCKED on the branch-base mismatch, with the doc
     evidence; the empirical re-probe stays owner-run and manual (needs a session with the plugin reinstalled) and
     is named as the trigger to revisit.
   - **2c** (Workflow tool / nested spawning) and **2e** (Agent Teams): recorded KEEP OURS, one line each with the
     reason; the seven 2026-10-12 CANDIDATEs stay `awaiting owner decision` in the baseline, untouched.
2. `loomwright/skills/agent-teams/SKILL.md`: replace the stale "As of 2026-05-10, 3 of 6" graduation line with the
   2e KEEP verdict and a pointer to `NATIVE_OVERLAP.md`, staying within the skill's current token ceiling.
3. Cadence: `scripts/bump-version.sh` prints one reminder line on a minor or major bump —
   `capability baseline last scanned at <plugin_version_at_last_scan>; run /capability-check` — read from
   `CAPABILITY_BASELINE.json`. Fail-SAFE: an unreadable baseline prints nothing and never fails the bump. Record the
   cadence in the baseline's `_comment` and in `NATIVE_OVERLAP.md`; do not edit `commands/capability-check.md`.

## Non-goals
Running `/capability-check` or updating the baseline's scan fields (owner-run). Any orchestration or review-flow
change. The 2d re-probe. Deciding the seven CANDIDATEs.

## Owner decisions (from _BACKLOG.md)
- 2026-10-22: queue only 2b and 2d; record 2c and 2e as KEEP; the scan cadence is a `bump-version.sh` reminder on
  each minor bump.

## Acceptance criteria
- `NATIVE_OVERLAP.md` has the 2b and 2d entries with cited evidence and a verdict each, and one KEEP line each for
  2c and 2e; every platform claim cites the baseline entry or says "unverified".
- `agent-teams/SKILL.md` no longer carries the 2026-05-10 graduation line.
- Given a minor bump in `test-bump-version.sh`'s fixture, the reminder line prints with the baseline's version; given
  a patch bump, it does not; given a missing baseline, nothing prints and the bump succeeds.
- `bash scripts/check-version-bump.sh` passes with the `changelog.d/tr09b-overlap-map-and-scan-cadence.md` fragment.

## Validation (must pass before merge)
1. `scripts/test-bump-version.sh`, `check-doc-currency.sh`, `test-citation-drift.sh`, `check-token-budget.sh`. Full
   `ci-local` on GitHub CI (owner rule 2026-10-12).
2. Running system: `bash scripts/bump-version.sh --dry-run` (or the script's no-write mode) on the branch — paste the
   reminder line, or the reason it did not print.
3. Rollback: `git revert`.

## Depends on
none

## Touches
loomwright/docs/NATIVE_OVERLAP.md
loomwright/docs/CAPABILITY_BASELINE.json
loomwright/skills/agent-teams/SKILL.md
scripts/bump-version.sh
scripts/test-bump-version.sh
changelog.d/tr09b-overlap-map-and-scan-cadence.md

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-24T03:30:46Z
- **Brief:** .supervisor/jobs/done/2026-10-22-tr09b-overlap-map-and-scan-cadence.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/683
