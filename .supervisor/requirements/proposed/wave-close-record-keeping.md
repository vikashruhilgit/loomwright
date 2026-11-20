# Wave close keeps its records current: `wave-build` records a hand-opened wave PR, `fleet-closeout` re-pulls after its pushes

## Status: proposed

> Propose-only. Raised by run `automate-2026-11-01-195532` (wave 1, PR #793, 2026-11-02). Two small bookkeeping
> gaps in the same wave-close path. Not enqueued.

## Problem A — a wave PR opened by hand never reaches the run file (read against `main` at `38eb8e4`)
`wave-build` STOPPED on local-CI timeouts. The documented manual fallback (`skills/automate-loop/lanes.md`
§"The per-wave loop" step 9) was then followed: bump on the kept branch, push, `gh pr create` (#793), then re-run
`wave-build`. The re-run printed `wave-build: done — wave PR … already open`, exit 0. Its done path
(`loomwright/scripts/automate-wave.sh`, header step 3 `done`: "exit 0, nothing written") appends nothing to the
parent `## Progress`. Only the normal path (step 11 `record`) writes the `wave built: <branch> — PR <url> (…)` line.
So the run file of a hand-finished wave never names its wave PR. The coordinator appended the line itself to keep
the record.

### Suggested direction
On the `done` path, when the parent `## Progress` has no `wave built:` line naming that PR, append one through
`progress-append`:
`wave built: <branch> — PR <url> (finished outside wave-build; ci <unknown|pass>; release <v|skipped>)`.
Idempotent: a later re-run finds the line and writes nothing. Keep "nothing created" otherwise.

## Problem B — `fleet-closeout` leaves the primary's lane run files stale
`fleet-closeout` (`loomwright/scripts/automate-lanes.d/wave.sh`, `lanes_fleet_closeout`) pulls the metadata branch
once, at step 1. In step 2 it runs each lane's backstop `lane-convert-ready`, and that pushes the lane's finalized
run file (`## Status: done`) to the metadata branch from the lane clone. There is no later pull. The primary's own
copy of each lane run file therefore stays at its earlier state (`## Status: paused`). Observed for both
`automate-2026-11-01-195532-L1.md` and `automate-2026-11-02-071559-L1.md`. `/backlog` then listed them as
`stale_run` until a manual `meta-entry` pull.

### Suggested direction
After step 2, when any backstop pushed (and before the parent finalize's own `trail-pr`), run one more
`meta-sync.sh pull --branch <mode branch>`. A failure is reported as `fleet-closeout: pull FAILED — …` exactly like
step 1. Mode off: skipped.

## Invariants to keep
- `wave-build` never merges, never force-pushes, and the coordinator never writes into a lane (both fixes write only
  the parent run file or pull).
- Every `meta-sync` call passes `--branch` explicitly.
- Fail-closed pull semantics stay as step 1's.

## Tests
- A: re-run with an already-open wave PR and no `wave built:` line ⇒ one line appended; a second re-run ⇒ unchanged.
- B: a fixture where the backstop pushes a lane finalize ⇒ after `fleet-closeout`, the primary's lane run file reads
  `## Status: done`.
- Mutation control for each: drop the new step ⇒ its leg turns red.

## Likely touches
`loomwright/scripts/automate-wave.sh`, `loomwright/scripts/automate-lanes.d/wave.sh`,
`loomwright/scripts/test-wave-build.sh`, `loomwright/scripts/test-automate-lanes.d/` (fleet-closeout parts),
`loomwright/skills/automate-loop/lanes.md` (step 9 / "Wave close")
