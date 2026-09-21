# 05 — Archive views: the accumulated judgement, made browsable

## Problem

Item 04 answers "what is happening now". The larger and more neglected asset is what the
system has already **learned**, and it is currently readable only by opening files:

- `.agent/rules/*.json` — the committed house-rules store, one JSON array per category.
  Machine-readable, human-hostile: ids are long slugs derived verbatim from the statement text.
- `.supervisor/postmortem/results.jsonl` — per-PR review-churn analysis, each line with a
  root-cause class and flow-stage attribution. This is the single best record of *why* this
  system produces churn, and nothing displays it.
- `.supervisor/drain-rounds/*.json` — per-round review findings.
- `.supervisor/worker-summaries/*.md` — first-person accounts of what workers did.
- `.supervisor/history/` — dated release narratives.

> **Sizes are deliberately not written here.** Every one of these stores is appended to by
> the loop that reads this file — a literal count is stale before the item is picked up
> (measured 2026-09-03: the four counts an earlier draft pinned had each drifted within two
> days). The repo's own `process-a-count-or-version-claim-lives-i` rule says a count claim
> lives in exactly one place; for these stores that place is the store itself. AC1 below
> requires the views to recompute independently, which is the check that matters.

`/insights` aggregates some of this into rates. `/obsidian` links it for reading. Neither
lets you ask "which rule keeps getting violated" or "what class of finding dominates our
review rounds" — the questions that would actually change how the system is run.

## Goal

Three read-only views over the same `floor.json` contract from item 03, extending the
existing surfaces rather than adding new stores.

## Scope

1. **Rules browser** — `.agent/rules/` by category and `applies-to` path, showing each
   rule's statement, its provenance, and any `--supersedes` chain. Where the postmortem
   ledger and drain rounds can be correlated to a rule, show that correlation **as an
   observation with its evidence**, never as a score — a correlation presented as a metric
   invites acting on it as if it were measured causation.
2. **Churn view** — the postmortem ledger by root-cause class and flow stage over time.
   The value is the distribution, not the total.
3. **Run snapshot** — extend `/handoff` to optionally publish its digest as a shareable
   page: what shipped, what was decided, what was tried and rejected, with provenance and
   freshness. Snapshot, not live.

## Non-goals

- **No new store, no new ledger, no new emitter.** Every input already exists. This item
  consumes existing signals only — which is also what keeps it clear of the advisory-surface
  freeze recorded in `.supervisor/requirements/twin-remediation/00-overview.md` (a freeze now
  lifted: items 01 and 02 there are both stamped `## Status: done`, and "consumers of
  EXISTING signals" were exempt regardless).
- **No scoring, ranking or automated curation of rules.** Curation stays human-gated through
  `/rules` and `/dreaming`. A view that ranks rules becomes a view that retires them.
- No write path of any kind. Retraction and supersession remain `add-rule.sh` /
  `curate-postmortem.sh` operations.

## Depends on

**03 merged** (hard). Independent of 01, 02 and 04 — it has no live half and can land any
time after the projector exists.

## Acceptance criteria

- [ ] Given this repo's real stores, each view renders with counts matching the on-disk
      truth, recomputed independently.
- [ ] Given a rule with a `--supersedes` chain, the chain renders in order; given one with
      no `applies-to`, it renders as project-wide rather than as blank.
      **Measured 2026-09-03, so the halves are verified differently:** `supersedes` is a
      genuinely OPTIONAL member `add-rule.sh` OMITS entirely when the flag was not given, and
      the live store holds **zero** rules carrying it — so that half is provable only against
      a fixture, and a check written against the real store alone would pass vacuously. The
      `applies-to` half IS live-verifiable: one real rule carries `applies_to: null`. Note the
      third state — `null` present, versus the key absent — and follow item 04's tri-state
      discipline rather than collapsing them.
- [ ] Given a malformed rule file, that file is named as unparseable and the rest still
      renders — "could not examine" is displayed as such and never as "examined and clean".
- [ ] Every correlation shown carries the evidence it was derived from, and no correlation
      is presented as a rate, score or ranking.
- [ ] `/handoff`'s existing default output is byte-identical before and after — the publish
      path is strictly additive and opt-in, proven by diffing real output.
- [ ] No view writes to `.agent/`, `.supervisor/postmortem/`, or any other store — asserted
      by hashing the trees before and after.

## Outcomes Rubric

- The system's accumulated judgement is browsable by the questions worth asking of it.
- Nothing is scored, ranked, or auto-curated; every correlation shows its evidence.
- Unparseable input is named, never silently treated as clean.
- Strictly additive: existing outputs and stores are provably untouched.

## Status: brief-shipped

Job `.supervisor/jobs/done/2026-09-03-archive-views.md` completed (reconciled from the job lifecycle, not self-reported).
Acceptance criteria are NOT machine-verified here — review them before promoting this to `## Status: done`.

## Status: done (PR #177, merge d81e826)
- **Completed:** 2026-09-04T10:22:06Z
- **Brief:** .supervisor/jobs/done/2026-09-03-archive-views.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/177
- **Reconciled:** 2026-09-21 by hand from the merged PR — the PR was merged outside the /automate loop, so nothing wrote this stamp at merge time.
