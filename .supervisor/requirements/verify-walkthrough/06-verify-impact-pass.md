# 06 — Impact pass: what else the change could have broken

## Problem
A ticket's own ACs prove the ticket; they say nothing about the neighbour the diff touched. The owner asked
for "other impacted areas related to that". Three sources of "impacted" already exist and none is consumed
after the run: the diff itself; Launch Pad's **File Impact Map + indirect blast radius** computed per brief
(`agents/launch-pad.md` step 8) and then thrown away; and — once 03 ships — earlier verify runs' `ac` lines,
each tied to routes it exercised.

## Goal
`/verify` walks, in addition to the ticket's ACs, a bounded set of surfaces the change plausibly affects, and
records those verdicts with `scope: impact` so they never inflate the ticket's own score.

## Scope
1. **Diff → surfaces.** From `git diff --name-only origin/<base>...<branch>`, map changed files to routes /
   API endpoints / components using the same route-handler reading qa-executor Phase 9 already does
   (Next.js `app/`/`pages/`, NestJS controllers, Express routers, Vue/Svelte routes — the existing detector
   list). Output: `impact_surfaces` line in `evidence.jsonl` (`file → surface` pairs, `source: diff`).
   Unmapped files are listed as `unmapped`, never guessed.
2. **Brief impact map (advisory).** If the ticket is a brief, or a requirement whose run produced a brief in
   `.supervisor/jobs/done/` (match by requirement path in the brief header), read its File Impact Map +
   blast-radius section and add those subsystems' surfaces with `source: brief`. Absent ⇒ skip silently
   (advisory read-path, same as `brain-context`).
3. **Prior-AC regression.** From earlier runs' `evidence.jsonl` (`.supervisor/verify/*/`), select `ac` lines
   with verdict `PASS` whose recorded routes intersect `impact_surfaces`; re-run those ACs, `scope: impact`,
   `source: prior_ac:<run_id>/<ac_id>`. Cap at `--impact-limit N` (default 10, most-recent first).
4. **Smoke per surface** with no prior AC: navigate, assert 2xx and no console/network 5xx, one primary
   action if the surface is a form (submit with seed values) — `PASS`/`FAIL` with `scope: impact`,
   classification as in 03. This is deliberately shallow; depth comes only from prior ACs.
5. **Summary**: `summary-build` (02) renders ticket and impact tables separately and never sums them; the
   ticket verdict line is unaffected by impact results.
6. **Tests.** Fixture repo with two routes where the diff touches a shared component: `impact_surfaces` names
   both; a prior run's PASS AC on route B is re-run and recorded with `source: prior_ac`; an unmappable file
   (`README.md`) lands in `unmapped`; `--impact-limit 1` re-runs exactly one prior AC; the ticket count in
   `summary.md` is identical with and without `--no-impact`. Mutation control: break route B in the fixture —
   the impact FAIL must appear and the ticket score must NOT change.

## Non-goals
No whole-app crawl (that is `/qa-executor`). No dependency graph beyond the existing detectors + the brief's
map — no graphify, no repo-map (D9 amendment retired the graph tier). No claim of completeness: the summary
prints the bound it used.

## Acceptance criteria
- `evidence.jsonl` has one `impact_surfaces` line naming every changed file with either a surface or `unmapped`.
- Impact verdicts carry `scope: impact` and are absent from the ticket's counts.
- A brief with a blast-radius section contributes surfaces tagged `source: brief`; a ticket with no brief
  contributes none and the run does not fail.
- Prior-AC re-runs are bounded by `--impact-limit` and ordered most-recent first.
- `summary.md` states the bound ("impact pass: N surfaces from diff, M from brief, K prior ACs, limit L").

## Outcomes Rubric
- Diff mapped to surfaces; unmapped named, never guessed
- Brief impact map consumed advisorily
- Prior PASS ACs on touched routes re-run, bounded
- Impact never inflates or deflates the ticket score
- Bound stated in the summary

## Status: done
