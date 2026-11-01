# Feature scorecard: which optional gates and lenses earn their cost, and which to retire

## Status: pending

> From the 2026-11-01 review of Anthropic's code-review post and the follow-up question "how do we know what works
> and what doesn't?". Loomwright measures outcomes per run (`/insights`), per PR (`/pr-postmortem`) and per lesson
> (`/dreaming`), but not per feature. So nothing says whether a gate, lens or advisory pays for the minutes and
> tokens it costs. This item reuses those surfaces; it adds no new command.

**As a** plugin owner deciding what to enhance and what to remove,
**I want** one read-only scorecard of every optional gate, lens and advisory: how often it ran, how often it caught
something, and what it cost,
**so that** keep / enhance / retire decisions rest on recorded evidence, and `/propose` can draft the work for the
ones I pick.

## Evidence (measured 2026-11-01, re-verify: main moves)

1. **No per-feature fields in the run log.** The latest `session_end` event in `.supervisor/logs/*.jsonl` has the
   keys `branch, event, files_changed, heal_decision, heal_iterations, pr_url, rubric_score, session_id, status,
   subtasks_completed, task, ts`. None of them name a feature.
2. **But most feature signals already exist on disk, scattered:**
   - Supervisor result sidecars (`.supervisor/automate/*.supervisor-result.md`): `risk_classification`,
     `rubric_score`, `contract_conformance`, `heal_*`. The schema also defines optional `red_team_advisory` and
     multi-voter counters (`docs/result-schemas/supervisor-result.md`).
   - review-heal next-step files (`.supervisor/review-heal/*.next-step.json`): `fallback_review_ran`.
   - pin-mutation caches (`.supervisor/pin-mutations/*.tsv`): one verdict per row per code state.
   - `.supervisor/postmortem/results.jsonl`: `self_heal_rounds`, `self_heal_misses`, CI `review_rounds`, root-cause
     `categories`, `flow_stages`.
3. **The existing catch-rate instrument is stale.** `.supervisor/heal-signal/` was last written 2026-08-14, and its
   last ledger rows name temporary repos (`tmp.L5nsgKJnWb`, `tmp.b13ufHtALK`) with `n: 0`. `/insights` reads that
   ledger and never refreshes it, so the dashboard's "Heal-signal catch-rate" section shows nothing usable.

## Scope

### Part A — a feature registry and a read-only scorecard builder
- `loomwright/docs/feature-scorecard.json` is the ONE authority for which features are scored. Per feature: `id`,
  where its record lives (path glob + field), what counts as **ran**, what counts as **caught** (for example: red-team
  advisory raised ≥ 1 finding the run then fixed; a pin-mutation row that survived; the earned fallback review
  produced a fixed finding; multi-voter verification overturned a verdict), and where its cost comes from
  (durations, or `token_ledger` events). Every other surface points at this file and never restates the list or its
  length (house rule: a count lives in one place).
- A feature whose record does not exist yet stays in the registry with `record: none`. The scorecard prints it as
  `no record`, never as zero, and names it under "needs an emitter". Adding emitters is follow-up work, not this
  item.
- `loomwright/scripts/build-feature-scorecard.sh [--since <date|sha>] [--json]` reads only those records and prints,
  per feature: runs available, ran, caught, catch rate, cost (total and per catch), last fired, and a **suggested
  verdict** from fixed rules in the registry:
  - `keep`: caught at least once in the window.
  - `review: costs without catching`: ran ≥ the registry's minimum sample, caught 0.
  - `review: never ran`: ran 0 in the window (never enabled, or dead).
  - `insufficient data`: below the minimum sample.
  The verdict is a suggestion. The script decides nothing and changes no config.
- Fail-SAFE (always exit 0). An unreadable record makes that feature `unreadable: <reason>`, never `keep`.

### Part B — show it in `/insights`
- `build-insights.sh` adds a "Feature scorecard" section to `.supervisor/insights/dashboard.md` from Part A's
  `--json` output, guarded like the "Loop evidence" section (it can never fail the dashboard build).
- The "Heal-signal catch-rate" section prints the ledger's age and its newest row's repos. When the newest row is
  older than 14 days or names a repo that is not this checkout, it says `stale` and prints the refresh command
  instead of numbers.
- Find out why the newest heal-signal rows name temporary repos. If a test or script wrote to the real
  `.supervisor/heal-signal/`, fix that write so it can't recur, and add a test that fails on the old behaviour.
  If the cause is a one-off manual run, record that in the PR and change nothing.

### Part C — `/propose --from-scorecard`
- A new basis for `/propose`: reads Part A's `--json` and writes one draft per feature whose suggested verdict
  starts with `review:` to `.supervisor/requirements/proposed/scorecard--<feature-id>.md`. Each draft carries the
  feature's numbers, the record paths, and two options for the owner: enhance (with what the numbers suggest) or
  retire (with the surfaces that would have to change, found by grepping the feature id).
- Same propose-only contract as the other bases: never queues, never edits a feature, no external call. The owner
  promotes or deletes each draft.
- `commands/propose.md` and `commands/insights.md` have about 450–490 tokens of budget headroom. New text that would
  exceed it goes to `docs/command-parts/<cmd>/`, the existing split pattern. This item does not edit
  `docs/prompt-token-budgets.json` (item 01 of this set owns that file in the same wave).

## Acceptance criteria

**Happy path**
- [ ] Given this repo's real `.supervisor/` data, when `build-feature-scorecard.sh` runs, then every registry feature
      gets one row with ran / caught / cost / last fired / suggested verdict, or `no record`.
- [ ] Given a feature that ran in at least the minimum sample and never caught, when the scorecard runs, then its
      verdict is `review: costs without catching`.
- [ ] Given `/insights` runs, when the dashboard is written, then it has a "Feature scorecard" section matching the
      script's output.
- [ ] Given `/propose --from-scorecard`, when two features are `review:`, then exactly two drafts are written to
      `proposed/`, each with numbers, record paths and both options, and nothing else changes.

**Edge cases**
- [ ] Given a feature with `record: none`, when the scorecard runs, then it prints `no record` and lists the feature
      under "needs an emitter", never a 0 or a verdict.
- [ ] Given `--since` later than every record, when the scorecard runs, then every feature is `insufficient data`.
- [ ] Given the heal-signal ledger is older than 14 days or names a foreign repo, when `/insights` runs, then the
      section says `stale` and shows the refresh command.

**Error scenarios**
- [ ] Given a malformed sidecar or TSV, when the scorecard runs, then only that feature is `unreadable: <reason>` and
      the script exits 0.
- [ ] Given the registry file is missing or invalid JSON, when the scorecard runs, then it prints one error line,
      emits no rows and exits 0. `/insights` shows the section as unavailable, never as an empty "all clear".

## Validation (must pass before merge)
1. `test-build-feature-scorecard.sh` with fixture records covering every verdict, `no record`, `unreadable`, and a
   mutation control (edit a verdict rule to always `keep`; the test must fail).
2. `test-insights.sh` gains the new section and the stale case. A `test-propose-*.sh` covers `--from-scorecard`
   writing only to `proposed/`.
3. **Pre-release run, no deployment:** on the branch, run the scorecard and `/insights` against this repo's real
   `.supervisor/` data via `claude -p --plugin-dir <branch>/loomwright` (or the scripts directly, which read only
   local files). Paste the scorecard table into the PR body. That table is the first real answer to "what earns
   its cost".
4. `check-token-budget.sh` passes without a budget edit; `bash scripts/check-version-bump.sh` passes;
   `bash scripts/ci-local.sh --affected` is green.

## Non-goals
- Retiring, disabling or changing any feature. Each one is a separate owner decision through a promoted draft.
- New emitters inside agent or skill prompts (that would collide with item 01's files). Features without a record
  are named, not instrumented.
- Telemetry egress. Everything stays in gitignored `.supervisor/`; no project content is copied into any record
  (owner rule: plugin facts only).

## Assumptions
- The existing records are complete enough to score a useful number of features. If most come out `no record`, the
  scorecard still lands, and the "needs an emitter" list becomes the next item.
- A catch is attributable from the record alone (for example, a red-team finding later fixed). Where it isn't, the
  registry marks the feature `caught: unknown` rather than guessing.

## Risks
| Risk | Impact | Mitigation |
|---|---|---|
| A low catch count is read as "useless" for a rare-but-critical gate (security, fail-closed guards) | a safety gate gets retired | the registry can mark a feature `critical: true`; its verdict is never below `keep (critical)` and `/propose` never drafts a retire for it |
| Small samples mislead | wrong retire calls | the minimum-sample rule; `insufficient data` instead of a verdict |
| The registry drifts from the real features | silent gaps | the "needs an emitter" list, and Part A prints any feature id grep-found in `supervisor-result.md`'s optional fields but missing from the registry |

## Depends on
none

## Touches
loomwright/docs/feature-scorecard.json
loomwright/scripts/build-feature-scorecard.sh
loomwright/scripts/test-build-feature-scorecard.sh
loomwright/scripts/build-insights.sh
loomwright/scripts/test-insights.sh
loomwright/scripts/measure-heal-signal.sh
loomwright/scripts/measure-heal-signal.py
loomwright/scripts/test-measure-heal-signal.sh
loomwright/scripts/propose-scorecard.sh
loomwright/scripts/test-propose-scorecard.sh
loomwright/commands/insights.md
loomwright/commands/propose.md
loomwright/docs/command-parts/insights
loomwright/docs/command-parts/propose
changelog.d/feature-scorecard.md
