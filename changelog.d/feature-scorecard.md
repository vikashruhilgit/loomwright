<!-- bump: minor -->
Feature scorecard: which optional gates, lenses and advisories earn their cost
Keep, enhance or retire decisions on optional features had no recorded evidence behind them: outcomes were
measured per run, per PR and per lesson, never per feature. `loomwright/docs/feature-scorecard.json` is now the one
registry of scored features. For each feature it names the record that feature already leaves under `.supervisor/`
(a SUPERVISOR_RESULT sidecar field, review-heal drain state, pin-mutation TSVs or token-ledger cost), what counts as
ran and caught, whether the feature is critical, and a `min_sample` threshold. A feature with no emitter is
declared `record: none`. `scripts/build-feature-scorecard.sh [--since <date|sha>] [--json] [--state-dir <dir>]`
is a read-only builder that always exits 0. For each feature it prints runs available, ran, caught, catch rate,
cost total, cost per catch and last fired, plus a suggested verdict from a fixed precedence. A critical feature is
never suggested below `keep (critical)`, a missing cost is `unknown` and never 0, and a malformed record makes only
its own feature `unreadable`. It also lists the features that need an emitter and any optional SUPERVISOR_RESULT
fields the registry does not cover. `/insights` gains a "Feature scorecard" section rendered from the builder's
`--json` output; it reads "unavailable" when the registry or builder fails, never an empty all-clear. The
heal-signal section now prints the ledger's age and the newest row's repos, and says `stale` with the refresh
command when that row is older than 14 days or names another repo. `/propose --from-scorecard` drafts one
owner-promotable enhance-or-retire proposal under `proposed/` for each `review:` feature, with its numbers and
record paths. The scorecard's verdicts are suggestions only: nothing in this change disables or retires a feature.
