# 18b — Right-size check: flag an item too small to pay a full run or too big for one PR, name what to merge it into, and merge items mechanically

## Status: pending

## Split from
`parallel-automate/18-backlog-board-and-right-size.md` Part B, split 2026-10-22 by the owner (/product-owner
session, re-verified read-only against main 7b7cb08 / v17.14.1). Part C shipped in #488; Part A is
`18a-backlog-board.md`, which waits on this item (the board's right-size column calls `right-size`). Part B's text
is carried VERBATIM under `## Source text`; where it and this header differ, this header wins.

## Problem
Item size is still counted by hand: `skills/user-story-writing/SKILL.md` §"Shape decision" says "No mechanical size
check ships yet: count by hand". Items written one finding at a time come out too small to pay a full run; merged
ones come out too big for one PR (pa/18 itself reached ~50 files and had to be split again on 2026-10-22).

## Goal
One `automate-helpers.sh right-size <item>` verdict (`small` / `ok` / `large`) computed from the item's declared,
companion-expanded Touches, with merge candidates for `small`, a split remedy for `large`, a mechanical
`merge-items` helper, and the verdict shown where items are written and where they are queued.

## Scope
Everything in the Source text's Part B Scope (B1–B6), with these corrections from the 2026-10-22 re-verification:
1. **B1 size signal:** reuse `plan-waves <item> --touches` (#586, the companion-expanded Touches set); never
   re-parse `## Touches`. New config keys in `automate-helpers.d/config.sh`, with defaults from Owner decisions.
2. **B3 where it runs:** the writer seam is `pc_guarded_write` in `propose-common.sh` (also used by
   `automate-dismissed.sh`). At intake, `plan-waves --lint` runs only under `--parallel N>1`
   (`skills/automate-loop/intake.md` §14) and `automate-next-step.sh` never calls `plan-waves`: print the size line
   where intake actually runs, and do not add a new call site to the driver. The `--explain` `small` note prints
   for every placed item, not only items outside wave 1.
3. **Part C's leftover:** the plan-doc section check (C5) and the `## Measurements` check (C6, right-size half) are
   one more line of `right-size` output, per the 2026-10-06 "How the parts join" decision.
4. **B5 skill text:** replace "No mechanical size check ships yet: count by hand" in `user-story-writing/SKILL.md`
   with the `right-size` call, and keep the Product Owner agent and command mirror in step (same commit).
5. **B4 `merge-items`:** the af/33 originals (17, 25) are already stamped `parked` on the metadata branch; the
   round-trip fixture rebuilds them as they were before the merge in a temp tree. No test reads the live backlog.
6. Stale paths in the Source text: `fixtures/automate-helpers-help.golden` is now one golden per family under
   `fixtures/automate-helpers-help/`; `test-automate-helpers.sh` is split into `test-automate-helpers.d/`.

Hotspot ownership for wave 1: this item owns `loomwright/docs/prompt-token-budgets.json` and
`loomwright/docs/ARCHITECTURE_CONTRACTS.md` (budget re-measure for the PO prompt and touched skill docs, plus the
mirror rows). No other wave-1 item edits them.

## Non-goals
The backlog board (18a). Changing `plan-waves` wave assignment. Auto-merging items without the owner (merge-items
is a helper the owner or PO invokes). Anything in Part C that #488 shipped.

## Owner decisions (from _BACKLOG.md)
- 2026-10-22: `small` = 3 or fewer files in the companion-expanded Touches set, configurable by a `right_size_small`
  key; `large` stays "over ~30 files or more than 7 Parts" (2026-10-09 amendment). A `Touches unknown` item reads
  `unknown`, never `small`.

## Acceptance criteria
- Every Part B acceptance criterion in the Source text holds, with the 2026-10-09-snapshot checks rewritten as
  hermetic fixtures (built in a temp requirements tree; a test never reads the live backlog).
- Given an item whose expanded Touches has 3 files, when `right-size` runs, then the verdict is `small` and at
  least one merge candidate that shares a Touches path is named (never a `parked` or `done` item, never a cycle).
- Given an item with 31 Touches files or 8 Parts, then the verdict is `large` with "split by Part" in the message.
- Given `right_size_small=5` in config, then a 4-file item reads `small`.
- `user-story-writing/SKILL.md` no longer says "count by hand", and the PO agent/command mirror match it.
- Mutation controls: dropping companion expansion fails a fixture leg; dropping the parked/done exclusion from merge
  candidates fails a fixture leg.
- `bash scripts/check-version-bump.sh` passes with the `changelog.d/pa18b-right-size-check.md` fragment.

## Validation (must pass before merge)
1. Targeted tests: `test-automate-helpers.d/17-right-size.sh`, `13-plan-waves.sh`, `01-config.sh`,
   `test-propose-common.sh`, `test-automate-dismissed.sh`, `test-requirement-shape.sh`, the help-golden check, plus
   `check-doc-currency.sh`, `test-citation-drift.sh`, `check-token-budget.sh`. Full `ci-local` runs on GitHub CI
   (owner rule 2026-10-12).
2. Running system: `right-size` on three hand-built items (2, 12, 35 Touches files) in a temp tree — paste the
   three verdict lines into the PR body.
3. Rollback: `git revert`.

## Depends on
none

## Touches
loomwright/scripts/automate-helpers.d/right-size.sh
loomwright/scripts/automate-helpers.sh
loomwright/scripts/fixtures/automate-helpers-help/right-size.golden
loomwright/scripts/fixtures/automate-helpers-help/plan-waves.golden
loomwright/scripts/fixtures/right-size/
loomwright/scripts/test-automate-helpers.d/17-right-size.sh
loomwright/scripts/automate-helpers.d/plan-waves.sh
loomwright/scripts/test-automate-helpers.d/13-plan-waves.sh
loomwright/scripts/automate-helpers.d/config.sh
loomwright/scripts/test-automate-helpers.d/01-config.sh
loomwright/scripts/automate-helpers.d/intake.sh
loomwright/scripts/propose-common.sh
loomwright/scripts/test-propose-common.sh
loomwright/scripts/automate-dismissed.sh
loomwright/scripts/test-automate-dismissed.sh
loomwright/scripts/test-requirement-shape.sh
loomwright/skills/automate-loop/intake.md
loomwright/skills/automate-loop/helpers.md
loomwright/skills/user-story-writing/SKILL.md
loomwright/skills/SKILLS_INDEX.md
loomwright/agents/product-owner.md
loomwright/commands/product-owner.md
loomwright/docs/prompt-token-budgets.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
changelog.d/pa18b-right-size-check.md

## Source text (verbatim from 18 Part B — superseded where the header above differs)

### Part B — 17 — Right-size check: flag items too small to pay a full run, name what to merge them into, and merge them mechanically

#### Problem
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

#### Goal
When an item is written or enqueued, the plugin says whether it is small relative to the run's fixed cost and which
pending items it could merge into. A helper performs a merge the owner chooses, mechanically and losslessly. Advisory
only: nothing is blocked, nothing is merged without the owner's choice.

#### Scope
1. **Size signal.** `automate-helpers.sh right-size <item|dir|item-list> [--root <checkout>] [--json]` reports per item:
   Touches count (after companion expansion, the planner's own reading), Scope bullet count, acceptance-criteria count,
   and a verdict `small | ok | large`. Thresholds are configurable defaults (`.supervisor/config.json` keys, documented),
   seeded from S2 and re-tuned from S3's lane costs; the defaults and their evidence are stated in the skill.
   **Amended 2026-10-09 — `large` means "will not fit one PR", not just "big":** `large` when the companion-expanded
   Touches count is over `right_size_large_files` (default 30: of 138 past agent PRs in the postmortem ledger, median 13 files, 90% at 29 or fewer) OR the item has
   more Parts than `right_size_max_parts` (default 7: Plan Review FAILs a brief with more than 7 subtasks, and one Part
   per subtask is the comfortable form). The line names the cause and the remedy, e.g. `implementation-quality/02:
   large (83 files, 10 parts) — will not fit one PR: split by Part`. Splitting stays a human or agent edit.
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

#### Non-goals
Merging anything automatically, blocking intake or a writer, changing the planner's wave placement, or re-sizing items
already in flight. No split helper (`large` names the remedy; the split is written by hand).

#### Acceptance criteria
- `right-size` over the S3 queue as it stood on 2026-10-06 flags `meta-sync-followups/09` and `/10` as small and names
  each other as the top candidate.
- `merge-items` reproduces `automate-followups/33-children-settled-gate.md` from its two originals with zero lost lines.
- `right-size` on `implementation-quality/02` as it stood on 2026-10-09 prints `large` with both causes (files and parts)
  and "split by Part".

#### Validation (must pass before merge)
1. Baseline full loop, `<passed>/<total>` and `SKIP` counts, base and branch.
2. Unchanged path: `plan-waves` output for an existing queue is byte-identical apart from the added `small` notes;
   writers still write the same item.
3. Running system: run `right-size` over the real pending queues and paste the report; perform one real merge the owner
   chooses with `merge-items` and paste the post-check.
4. A failure this must catch: the two mutation controls in Scope 6.
5. Rollback: `git revert`.

#### Evidence
S2 lane logs (costs above); S3 record `operator-run/S3-stabilization-wave-spike.md`; the three hand merges of
2026-10-05; owner request 2026-10-06: "I don't want to run automate for small requirements — not worth it … do we have
any check while writing a requirement whether it's good to run the full process?" Answer: no.


<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-24T03:29:23Z
- **Brief:** .supervisor/jobs/done/2026-10-22-pa18b-right-size-check.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/675
