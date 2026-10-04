# 10 — Items the planner can actually parallelise: backfill `Touches` / `Depends on`, lint them at intake, explain every conflict

## Status: pending

## Depends on
none

## Touches
loomwright/scripts/automate-helpers.sh
loomwright/scripts/test-automate-helpers.sh
loomwright/scripts/automate-dismissed.sh
loomwright/scripts/test-automate-dismissed.sh
loomwright/commands/propose.md
loomwright/skills/user-story-writing/SKILL.md
loomwright/skills/automate-loop/SKILL.md
loomwright/commands/automate.md
changelog.d/parallel-automate-10-touches-backfill-lint-and-explain.md

## Problem
Owner goal: 5–10 lanes at once. The wave planner (item 04, `plan-waves`, merged 2026-10-03 in `7b1d71c`) decides
which items may share a wave. Run over **every open item on 2026-10-04 (26 items), it produced 24 waves, the largest holding 2 items**, so
almost nothing could run in parallel. The causes, counted:
- **16 of 26 open items have no `## Touches` section.** As the owner noted, these items were written BEFORE item 04 added
  the sections, so this is history, not careless authoring. The planner reads a missing section as unknown and runs
  the item ALONE, by design.
- **Several of the 10 that have one carry prose in it** ("(only if a test exposes a defect)", "- a, b" lists,
  "(part B)"). The strict grammar makes the WHOLE section unknown, so those also run alone, silently.
- **16 of 26 have no `## Depends on`**, which the planner reads as "depends on every earlier item".
- **New items still default to run-alone:** the authoring template in `skills/user-story-writing/SKILL.md` ships
  `## Touches` / `unknown`, and two writers add no sections at all: `/propose` drafts and the dismissed-finding
  drafts from `automate-dismissed.sh`. Items written by hand in a session also skip them.
- **Nobody can see why two items conflict.** `plan-waves` prints the waves, not the reason.

## Goal
The current backlog gets real `Touches` / `Depends on` once; every writer emits them from then on; a malformed
section is caught when it is written or enqueued, not discovered as a silent run-alone; and the planner can say
exactly which path (or companion rule) put two items in different waves.

## Scope
1. **`plan-waves --explain`** (read-only, same inputs): after the waves, one block per item that is not in wave 1
   naming the reason — `conflicts with <item> on <path> (declared | companion: <rule>)`, `depends on <item>`,
   `runs alone: Touches unknown (missing | unparsable line N: "<text>")`, `runs alone: Depends on missing ⇒ depends
   on every earlier item`.
2. **`plan-waves --lint <item|dir>`** (read-only): per item, `ok` or the exact unparsable line and why. Exit 1 when
   any item would run alone because of a MISSING or UNPARSABLE section (an explicit sole `unknown` is legal and
   reported as `ok (declared unknown)`).
3. **Intake shows it:** `/automate` folder/backlog intake with `--parallel N>1` (item 05) prints the lint summary
   before the Queue is confirmed (`7 of 12 items will run alone: …`). Sequential runs are unchanged (no new gate).
4. **Writers emit real sections:**
   - `skills/user-story-writing/SKILL.md`: the writer FILLS `## Touches` from its own file-impact reasoning (paths it
     names in Scope) and uses `unknown` only when it truly cannot; no prose inside the section, ever (put
     conditions in Scope instead); `## Depends on` is always written (`none` when none).
   - `/propose` drafts and `automate-dismissed.sh` drafts carry both sections: `Depends on` = `none`; `Touches` =
     the file(s) the finding names when it names them, else `unknown`.
5. **One-time backfill of the existing backlog** (an operator step this item's PR does NOT do itself, because the
   requirement files live on `loomwright-meta`): `plan-waves --lint .supervisor/requirements/` lists every item to
   fix; for each, add `## Depends on` and a parsable `## Touches` from its own Scope (prose conditions move to
   Scope). Record before/after `plan-waves --max 10` wave counts in this item's Evidence.
6. **Tests:** `--explain` names the declared path, the companion rule, the unknown reason and the missing Depends
   on; `--lint` passes a good item, flags each malformed shape seen in today's backlog (parenthetical, comma list,
   `- ` bullet), reports a declared `unknown` as ok; a dismissed draft and a `/propose` draft both parse.

## Non-goals
- No change to the planner's safety rules (unknown still runs alone; a missing Depends on still serialises).
- No automatic guessing of Touches for existing items (the backfill is a reviewed edit).

## Acceptance criteria
- After the backfill, `plan-waves --max 10` over the pending backlog yields at least one wave of 5 or more items
  (or `--explain` shows, path by path, why it cannot — that output is then the input to item 11).
- `plan-waves --lint .supervisor/requirements/` exits 0 on the backfilled backlog.

## Validation (must pass before merge)
1. **Baseline:** full loop on base and branch, `<passed>/<total>` and `SKIP` counts.
2. **Unchanged path:** `plan-waves` without the new flags prints byte-identical output on the existing fixtures.
3. **Running system:** paste `--lint` and `--explain` over today's real backlog.
4. **A failure this must catch:** make `--lint` accept a parenthetical line ⇒ its test fails.
5. **Rollback:** `git revert`; the backfilled sections stay valid input to the old planner.

## Verified premises (re-check before starting)
- Counts above: open = a requirement file under `.supervisor/requirements/*/[0-9]*.md` (not `operator-run/`, not `00-`) with NO `## Status: done|abandoned` line anywhere (closeout APPENDS the done stamp at the end of the file, so the first `## Status:` line still says pending — a count by first line wrongly gave 39). `plan-waves <open list> --max 10` → 24 waves, max 2 items per wave, 2026-10-04.
- `skills/user-story-writing/SKILL.md` template ends with `## Depends on` / `none` and `## Touches` / `unknown`.
- `loomwright/agents/product-owner.md` still shows an older `- Depends on: [Other stories]` bullet inside its prose
  template; check whether it conflicts with the H2 rule and align it in the same PR if so.

## Evidence
2026-10-04 planner run over the backlog (this session); owner note that the items predate item 04.
- **Backfill done by hand, 2026-10-04 (this session, ahead of the tooling):** 20 items fixed. 15 had neither section: agnostic-phase1/01–05, automate-followups/14/16/17/20/21, churn-ledger/01–02, token-economy/07, twin-remediation/06/10. 5 had prose in Touches: meta-sync-followups/01–05, whose conditions moved to a `## Notes on the touched files` section (the heading must NOT start with `## Touches`, or a prefix match sees a duplicate section). Four read-only research agents proposed the lists; every path was checked to exist, or to be a declared new file or a `changelog.d` fragment, before writing. Requirement docs (`.supervisor/...`) were kept OUT of Touches: they change on the metadata branch, not in the code PR, and listing them creates false conflicts. A grammar-check lint (`plan-waves` rules) now passes on all 37 open items. Planner over the 31 dispatchable ones: **24 waves / largest 2 → 20 waves / largest 7**. What still serialises is shared files (item 11), not missing metadata. The scope note in Scope 5 ("operator step after this PR") is therefore already satisfied; the PR only needs the tools and the writer changes.

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-04T11:44:25Z
- **Brief:** .supervisor/jobs/done/2026-10-04-touches-lint-and-explain.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/377
