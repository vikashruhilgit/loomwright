# 17 — Right-size check: flag items too small to pay a full run, name what to merge them into, and merge them mechanically

## Status: pending

## Problem
Every requirement item that `/automate` runs pays a fixed cost whatever its size: Launch Pad, Plan Review, Supervisor,
Phase 4.5 review, the owned drain, CI and `claude-review` on every push, and the owner's gate questions. S2's five lanes
(2026-10-05, lane logs archived under `~/Documents/work/AI/ai-agent-manager-lanes-v2/archive/s2-*`; the logged
`total_cost_usd` is cumulative per session, so each session's final value is counted once):

| Lane | Item size | ~Cost | Owner questions |
|---|---|---|---|
| s2-c | small fix (`automate-followups/24`) | ~$17 | 4 |
| s2-e | tests only (`meta-sync-followups/01`) | ~$19 | 5 |
| s2-d | medium (`automate-followups/26`) | ~$26 | 6 |
| s2-b | medium (`automate-followups/16`) | ~$36 | 6 |
| s2-a | large (`agnostic-phase1/01`) | ~$40 | 8 |

Plus roughly 2–4 h wall-clock and ~25 min per `claude-review` round each. The floor (~$17–20 and four or more owner
questions) is paid even by a one-file change.

Nothing in the plugin looks at this when an item is written or enqueued:
- `plan-waves --lint` checks only that `## Touches` / `## Depends on` are present and parseable.
- Launch Pad Phase 2.5 FEASIBILITY asks whether the goal is achievable, not whether it is worth a run.
- Plan Review judges the brief's quality; the Decomposition Threshold splits one brief into subtasks and never batches
  across requirements.
- `skills/user-story-writing/SKILL.md` pushes the other way: INVEST "Small" and "Multiple features … Split into
  separate stories", so the writers produce exactly the many small items that each pay the floor.

On 2026-10-05/06 the operator merged items by hand three times (`automate-followups/32` = 14 + 28 + 29, `/33` = 17 + 25,
`meta-sync-followups/08` = 02 + 03 + 06) and the owner chose four more (ms/09 + ms/10, pa/13 into pa/06, af/22 + af/23,
ms/05 Part D into ms/07). Each hand merge needed the same steps: copy the originals verbatim as parts, park them with a
pointer, re-point every dependent, check that no original line was lost.

## Goal
When an item is written or enqueued, the plugin says whether it is small relative to the run's fixed cost and which
pending items it could merge into. A helper performs a merge the owner chooses, mechanically and losslessly. Advisory
only: nothing is blocked, nothing is merged without the owner's choice.

## Scope
1. **Size signal.** `automate-helpers.sh right-size <item|dir|item-list> [--root <checkout>] [--json]` reports per item:
   Touches count (after companion expansion, the planner's own reading), Scope bullet count, acceptance-criteria count,
   and a verdict `small | ok | large`. Thresholds are configurable defaults (`.supervisor/config.json` keys, documented),
   seeded from S2 and re-tuned from S3's lane costs; the defaults and their evidence are stated in the skill.
2. **Merge candidates.** For a `small` item, list pending items it could fold into, ranked by: shared Touches (declared
   or companion), being in the same `## Depends on` chain, and same requirement folder. Never propose a candidate whose
   merge would create a dependency cycle or pull a parked / operator-run / done item. Output names the shared files.
   Example: `meta-sync-followups/09: small (4 files, 2 scope items) — merge candidates: meta-sync-followups/10 (3 shared
   files, same folder)`.
3. **Where it runs (advisory, never blocking):**
   - the requirement writers — Product Owner's persist step (agent + `commands/product-owner.md` mirror), the `/propose`
     writers (`propose-*.sh`), the dismissed-finding drafts (`automate-dismissed.sh`) — print the line for the item they
     just wrote;
   - folder / backlog intake prints it beside `plan-waves --lint` before the Queue is confirmed;
   - `plan-waves --explain` adds a `small` note to a placed item.
4. **`automate-helpers.sh merge-items <out.md> --title <t> --goal <text> <Part:item>...`** — the hand procedure made
   mechanical: originals copied VERBATIM as parts (headings demoted; their Status / Depends on / Touches folded into the
   merged item's own sections; Touches unioned, changelog fragment renamed), originals' `## Status` set to `parked
   (merged <date> into <out> as Part <X> — do not run this file)`, every dependent's `## Depends on` re-pointed, and a
   post-check that every non-heading line of every original appears in the output (exit 1 and nothing written
   otherwise). Refuses a done, operator-run or already-merged original, and a merge that would create a cycle.
5. **Skill wording.** `user-story-writing`: "small enough to review in one PR, large enough to pay the run's fixed cost;
   when two stories touch the same files, prefer one story with parts." Same note in Product Owner's persist step.
6. **Tests:** fixtures for each verdict; a small item with a sibling sharing files gets that sibling first; no cycle or
   parked candidate is ever proposed; `merge-items` round trip on the three real 2026-10-05 merges (output equals the
   committed merged files modulo the generated header); the lost-line post-check fails when a line is removed.
   **Mutation controls:** dropping companion expansion from the size count, and dropping the post-check, must each fail
   a test.

## Non-goals
Merging anything automatically, blocking intake or a writer, changing the planner's wave placement, or re-sizing items
already in flight.

## Acceptance criteria
- `right-size` over the S3 queue as it stood on 2026-10-06 flags `meta-sync-followups/09` and `/10` as small and names
  each other as the top candidate.
- `merge-items` reproduces `automate-followups/33-children-settled-gate.md` from its two originals with zero lost lines.

## Validation (must pass before merge)
1. Baseline full loop, `<passed>/<total>` and `SKIP` counts, base and branch.
2. Unchanged path: `plan-waves` output for an existing queue is byte-identical apart from the added `small` notes;
   writers still write the same item.
3. Running system: run `right-size` over the real pending queues and paste the report; perform one real merge the owner
   chooses with `merge-items` and paste the post-check.
4. A failure this must catch: the two mutation controls in Scope 6.
5. Rollback: `git revert`.

## Evidence
S2 lane logs (costs above); S3 record `operator-run/S3-stabilization-wave-spike.md`; the three hand merges of
2026-10-05; owner request 2026-10-06: "I don't want to run automate for small requirements — not worth it … do we have
any check while writing a requirement whether it's good to run the full process?" Answer: no.

## Depends on
04-wave-planner.md
10-touches-backfill-lint-and-explain.md

## Touches
loomwright/scripts/automate-helpers.sh
loomwright/scripts/test-automate-helpers.sh
loomwright/scripts/automate-dismissed.sh
loomwright/scripts/propose-common.sh
loomwright/skills/automate-loop/SKILL.md
loomwright/skills/user-story-writing/SKILL.md
loomwright/agents/product-owner.md
loomwright/commands/product-owner.md
loomwright/docs/RESULT_SCHEMAS.md
changelog.d/parallel-automate-17-right-size-check-and-merge-items.md
