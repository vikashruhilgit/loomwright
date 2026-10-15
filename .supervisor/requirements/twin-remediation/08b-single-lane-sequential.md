# tr/08b — Fresh session per sequential `/automate` item: one lane for `--parallel 1`

## Status: pending

## Split from
`twin-remediation/08-session-segmentation.md` items 1 and 4, rewritten 2026-10-13 (owner asked for the remaining
work as one item). Items 2–3 shipped in #487 (v15.133.0). The `/autonomous` multi-iteration half of item 1 is DROPPED
(owner-visible estimate: a second lane-like system for little gain; most long loops already run through `/automate`).

## Depends on
none

## Touches
loomwright/scripts/automate-lanes.sh
loomwright/scripts/test-automate-lanes.sh
loomwright/scripts/automate-helpers.sh
loomwright/scripts/test-automate-helpers.sh
loomwright/scripts/fixtures/automate-helpers-help/
loomwright/skills/automate-loop/
loomwright/commands/automate.md
loomwright/docs/result-schemas/automate-run.md
changelog.d/tr08b-single-lane-sequential.md

## Problem
Large sessions hold most transcript bytes (2026-10-13, last 14 days of this project: 74 of 339 sessions over 3 MB
hold 53% of 699 MB; ~200 MB of that is in sessions that touched 2+ `/automate` items). Lanes (`--parallel N`) already
run every item in its own fresh `claude -p` session with the question relay, launch authority and resume — but
`--parallel 1` deliberately takes no lane path, so a sequential run keeps every item in one growing session.
Honest limit: about half the large-session bytes are single items that are large on their own; this does not help them.

## Goal
`/automate --parallel 1` runs each Queue item in ONE fresh lane, and that lane behaves like a sequential item at the
gate: it parks `awaiting_merge` with a normal merge watcher and close-out — no `ready_for_release`, no wave PR, no
wave-build local CI. Default behaviour (no `--parallel`) is unchanged.

## Scope
1. `init-check` / the lane path accept N = 1 as "single-lane mode"; `--auto-merge` stays refused with lanes.
2. In single-lane mode the lane's READY gate writes `awaiting_merge` (not `ready_for_release`), arms the merge watcher,
   and its close-out runs through the existing evidence-gated `closeout` / `lane-convert-ready` path; `wave-build` is
   never called; the coordinator picks the next item only on the owner's go (same as sequential).
3. **Guard (item 4):** the lane still owns exactly ONE inline drain per pass — no detached `dispatch-pr-review.sh`
   artifact for its PR, the `auto_review` suppress window wraps RUN inside the lane, the config backup is restored
   inside the lane. Reconcile by markers, never by control-flow belief.
4. Docs: `automate.md` flag table, `skills/automate-loop/lanes.md` + `command-lanes.md` (N = 1 no longer "no lane
   code path" — state single-lane mode exactly), the run-file schema.

## Acceptance criteria
- `--parallel 1` on a 2-item Queue: item 1 runs in lane L1, parks `awaiting_merge`, no wave PR exists; after merge and
  `--resume`, item 2 runs in a NEW lane (fresh session id).
- No `--parallel`: output and run file byte-unchanged vs. today (existing tests pass unedited).
- Guard: a fixture lane run leaves no detached dispatch artifact; one `owned_drain_started` per pass.
- Mutation control: forcing the lane park back to `ready_for_release` fails the first leg.

## Validation (must pass before merge)
1. Targeted tests (`test-automate-lanes.sh`, `test-automate-helpers.sh`) + doc-currency + citation-drift
   (+ token-budget, vendor ratchet after `git add`). Full `ci-local` runs on GitHub CI.
2. Running system: one real `--parallel 1` run of a trivial item; paste the lane's `## Current` at the park and the
   absence of a wave PR. If not possible inside the run, list it under "Not verified".
3. Rollback: `git revert`.

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-15T02:41:11Z
- **Brief:** .supervisor/jobs/done/2026-10-14-tr08b-single-lane-sequential.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/548
