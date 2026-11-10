# PR scorecard: a hand-run builder that posts one comment, edits it in place, and opens with a one-line internal header

## Status: pending

**As the** owner (Vikash) reviewing a PR that Loomwright opened,
**I want** one hand-run command that gathers the signals Loomwright already records for that PR (merge-gate outcome, risk class, rubric score, `/verify` result, review rounds, token count) into one card, and posts it as ONE comment on the PR, opening with a one-line internal and advisory header and edited in place on every later call,
**so that** I can judge the PR from its first visible line, or from one card, without opening run files, session logs and drain ledgers, and without anything on the PR that reads as a public score or a merge decision.

Merged from two approved archive items: scorecard v1 item 1 (`2026-10-27-063930-pr-scorecard-builder-and-single-comment-upsert.md`) and batch I item I3 (`2026-11-09-045115-the-pr-scorecard-comment-opens-with-a-one-line-internal-header-summarising-its-rows.md`). One PR. Scorecard v1 item 2 (automatic posting) is deferred and is not part of this story.

**Naming.** This is the **PR scorecard**. It is not the **feature scorecard** (`loomwright/scripts/build-feature-scorecard.sh`, `loomwright/docs/feature-scorecard.json`, `/insights` §"Feature scorecard", `/propose --from-scorecard`), which scores the plugin's own optional features and is never posted on a PR. Prose, the schema heading, the marker and the script name all say "PR scorecard" or `pr-scorecard`, never bare "scorecard".

## Problem

Every signal the card needs is recorded today, but each lives in a different local file and none of them reaches the PR (verified on main `8ec200e`, plugin 17.35.1):

| Signal | Where it lives |
|---|---|
| Merge-gate outcome | Only under `/automate --auto-merge`. `automate-next-step.sh` (`ns_gate_eval`) appends `<ts> gate-eval: MERGE` to the run file's `## Progress`. A park is appended as `<ts> parked awaiting_merge <pr> — gate-eval PARK: <reason>`, and `--merge-parked` writes `<ts> merge-parked <pr> — PARK: <reason> (<detail>)` (`docs/result-schemas/automate-run.md`). **None of these lines records the head SHA the gate judged, and the MERGE line does not name the PR.** A plain `/supervisor` or default `/automate` PR has no gate outcome. |
| Risk class | `scripts/classify-risk.sh <base_ref> <head_ref> [--root]` prints one JSON object (`high_risk` true/false/null, `reasons[]` capped at 20 plus `+N more`, `changed_files`, `changed_lines`, `source`), read-only, always exit 0. Gate condition 6 now calls it as `classify-risk.sh origin/<base> <live head_sha>`, where `<base>` is the PR's own base branch, not a hardcoded `main`. |
| Rubric score, Phase 4.5 iterations | Flat `rubric_score` (`"N/M"` or null) and `heal_iterations` on the `session_end` line in `.supervisor/logs/<session>.jsonl` (`build-insights.sh` reads both there). `session_end` also carries `pr_url`. |
| `/verify` result | `.supervisor/verify/<run_id>/evidence.jsonl` (`run_start` carries `ticket_path`, `branch`, `head_sha`) and the derived `summary.md`, whose counts row reads `PASS: n · FAIL: n · BLOCKED: n · NOT_VERIFIABLE: n · total: n`. Keyed by branch, not by PR. A run can be paused (`pause` event, no `run_end`) with partial counts. Advisory only. |
| Drain rounds | `drain-rounds.sh read <pr>` prints the per-PR ledger JSON, or `{}` when absent. |
| Tokens | `read-token-ledger.sh --session <id>` prints `INPUT= OUTPUT= CACHE_READ= CACHE_CREATE= TOTAL= EVENTS= [LEDGER_UNREADABLE=1]`. An unreadable input prints all-zero sums plus `LEDGER_UNREADABLE=1`. No price table, so no dollar figure. |
| PR ↔ session join | `session_end.pr_url`; the `pr_created` event (`url`, `session_id`) that `hook-dispatch-on-pr-create.sh` appends; under `/automate`, the run file's `session_id <id> (<item>)` Progress lines and `## Current`. |

No PR comment carries any of these. The comments Loomwright posts today (`<!-- loomwright:dismissed round=<n> -->`, `<!-- loomwright:clean round=<n> -->`, the red-team advisory) are append-only event records.

## Scope

### Part A — `build <pr_url>` (read-only)

- One new script, `loomwright/scripts/pr-scorecard.sh`, with a `build <pr_url>` mode that prints the card to stdout and writes nothing. It resolves `.supervisor/` the way `read-token-ledger.sh` does (the main worktree root), with a `--root <dir>` override for tests.
- **Rows** (one per signal, six in total): merge gate, risk class, rubric, `/verify`, review rounds (Phase 4.5 iterations and drain rounds as two separate numbers, each with its own status), tokens. Each row has a status: `available`, `not_run`, `not_evaluated`, `unavailable (<reason>)`, `stale`, or a signal-specific state named below. A missing or unreadable signal is never shown as `0`, `false`, `pass` or blank (the fail-SAFE-reader corollary in CLAUDE.md §"Failure-Mode Invariants").
- **Merge gate:** copies a recorded gate outcome line verbatim. It never calls `gate-eval`, never runs `gh pr merge`, and never evaluates, re-derives or names a gate condition. A row that needs to point at the conditions points to `skills/automate-loop/SKILL.md` §10 and does not list or count them. A line is used only when the run file's own text ties it to this PR; the attribution rule is written in the schema doc and tested. With no attributable line the row is `not_evaluated`. Because no recorded gate line carries a head SHA, an available gate row is always marked `head unpinned` and never `current` (Owner decisions, PO default 2).
- **Risk class:** runs `classify-risk.sh origin/<PR baseRefName> <PR live headRefOid>` (base and head read from `gh pr view`), with no `git fetch`. It shows `high_risk` and the reasons as the classifier printed them. `null` reads `unclassifiable` with the classifier's reason, never as low risk. The row is the classifier's output, labelled as such. It is never labelled as a gate condition result.
- **Rubric:** `N/M` from the joined `session_end`; `no rubric` when the field is null (a status distinct from `unavailable`); `unavailable (no session_end)` when no joined `session_end` exists.
- **`/verify`:** the newest verify run whose `run_start.branch` equals the PR head branch. It shows the `summary.md` counts row byte for byte (never re-tallied), plus `current` or `stale` (whether `run_start.head_sha` equals the live head). A run with no `run_end` event is also marked `incomplete`. With no matching run the row reads `not_run`.
- **Review rounds:** `heal_iterations` from the joined `session_end`, and `rounds` from `drain-rounds.sh read <pr>`. `{}` reads `not_run`.
- **Tokens:** `TOTAL` and its four parts from `read-token-ledger.sh --session` for the joined sessions. The row always carries a coverage note naming what the ledger leaves out (main thread, CI-side review, detached drain sessions the join cannot see). `LEDGER_UNREADABLE=1` reads `unavailable`. A readable ledger with `EVENTS=0`, or only proxy lines, reads `not recorded`, never `0 tokens`. No dollar figure and no estimate.
- **Loomwright-opened check:** the PR URL appears in a joined `session_end.pr_url`, a `pr_created` event under `.supervisor/logs/`, or an `/automate` run file's `## Current` / `## Progress`. Otherwise `build` prints one `not_loomwright_pr` line on stderr, prints no card, and exits 0. Under `LOOMWRIGHT_HOST_MODE=1` it prints `host_mode_unsupported` the same way (Owner decisions, PO default 4).
- **Machine block:** a new schema, `PR_SCORECARD` `schema_version: 1`, documented in `loomwright/docs/result-schemas/pr-scorecard.md` and indexed in `loomwright/docs/RESULT_SCHEMAS.md` under its own `## PR_SCORECARD` heading with the standard `See [result-schemas/pr-scorecard.md](result-schemas/pr-scorecard.md).` line. Indexing it changes the generated `loomwright/capabilities.json`, which is regenerated with `build-capabilities.sh` in the same PR and never hand-edited. The block holds the PR URL, the head SHA the card was built at, a build timestamp, and one object per signal holding `status` plus its value fields. It is built with `jq --arg`/`--argjson`, never by templating text into JSON. Its placement in the comment (fenced JSON, an HTML comment, or `<details>`) is the implementer's choice, pinned by the schema doc. Changes within `schema_version: 1` are additive only. The doc also states that a consumer must trust only a card authored by the identity that runs Loomwright, because anyone can type the marker.

### Part B — the header line (rendering only)

- **Placement.** The card's Markdown is: line 1 the marker `<!-- loomwright:pr-scorecard -->` (no leading whitespace, so `classify-bot-review.sh`'s default `SKIP_MARKER_PREFIX` `<!-- loomwright:` keeps dropping the comment); line 2 the header; then the rows and the machine block. Rows are not collapsed.
- **Content.** One line. It starts with a fixed label saying the card is internal, advisory and not a merge decision (working text: `Loomwright PR scorecard — internal, advisory, not a merge decision`). Next comes the short head SHA, then one token per signal in a fixed order: merge gate, risk, rubric, `/verify`, review rounds. Tokens are not in the header; the tokens row is unchanged.
- **Every header token is rendered from the machine block, never from a source file.** A signal that is not `available` shows its status verbatim. Available signals are shortened only like this: gate `MERGE` or `PARK: <reason code>` (the reason up to its first space or `(`), followed by its `head unpinned` mark; risk `high` / `not high` / `unclassifiable` (no reasons, no paths); rubric `N/M`; `/verify` the PASS, FAIL and total numbers plus `current` / `stale` and `incomplete` when set; rounds the two numbers, separately labelled. No slot is ever left out.
- **No aggregate.** No combined score, percentage, grade, rank, badge, image or link.
- **One home for the header's order and token rule:** a "Header line" subsection in the schema doc. The builder's ordered list is the code copy, and the suite checks that the two match.
- The machine block gets no `header` field. The header is a pure rendering of the block.

### Part C — `post <pr_url>` (the only write)

- `post` builds the card and **upserts** exactly one comment. If a comment whose first line is the marker exists and was authored by the current `gh` identity, it is edited in place (`gh api` PATCH on the issue comment). Otherwise one is created. A marker comment by any other author is never edited and never treated as the card. With two of the current user's cards (left by an earlier race), the oldest is edited, none is created, and the duplicate is named on stderr. No comment is ever deleted.
- **Fail-SAFE emitter:** every `gh` failure, unreadable signal, refusal or missing `jq` prints one stderr line and exits 0. No half-built card is ever posted.
- **Off-switch:** `.supervisor/config.json` key `pr_scorecard_post` (boolean). Absent or `true` means posting is on. `false` means no `gh` write call is made, and stderr says posting is off. An unreadable or malformed config also means no post, named on stderr (Owner decisions, PO default 5). The key is documented in the schema doc.
- `gh` is resolved through `LOOMWRIGHT_GH_BIN` when set, as `review-heal-next-step.sh` does, so the suite can stub it.
- Nothing calls `post` automatically. It is run by hand: `bash "<plugin root>/scripts/pr-scorecard.sh" post <pr_url>`.

## Acceptance Criteria

All cases live in `loomwright/scripts/test-pr-scorecard.sh` (fixtures under `loomwright/scripts/fixtures/pr-scorecard/`) unless another suite is named. The fixture tree is a `.supervisor/` holding a `session_end` with `pr_url`, a `pr_created` event, `token_ledger` lines, a drain-rounds ledger, a verify run dir and an `/automate` run file. A stub `gh` (via `LOOMWRIGHT_GH_BIN`) serves the PR's `headRefOid`, `headRefName`, `baseRefName`, the current user and the comment list, and records every call. There is no network.

**Happy path**
- [ ] Given the full fixture (`session_end` with `rubric_score: "4/5"`, `heal_iterations: 2`; a drain ledger with `rounds: 3`; `token_ledger` lines), when `pr-scorecard.sh build <url>` runs, then stdout has one row per signal with rubric `4/5`, Phase 4.5 iterations `2`, drain rounds `3`, and a token TOTAL equal to `read-token-ledger.sh --session <id>`'s TOTAL, and the exit code is 0.
- [ ] Given the same fixture with a git repo whose `origin/<base>` and head exist, when `build` runs, then the risk row's `high_risk` and `reasons` equal `classify-risk.sh origin/<base> <head>` run directly on the same refs (the suite compares the two outputs).
- [ ] Given a run file whose `## Progress` holds `<ts> parked awaiting_merge <url> — gate-eval PARK: rubric_unsatisfied`, when `build` runs, then the merge-gate row shows that line verbatim, is marked `head unpinned`, and is never marked `current`.
- [ ] Given a verify run whose `run_start` has `branch` equal to the PR head branch and `head_sha` equal to the live head, a `run_end` event, and the counts row `PASS: 3 · FAIL: 1 · BLOCKED: 0 · NOT_VERIFIABLE: 1 · total: 5`, when `build` runs, then the verify row shows that counts row byte for byte and `current`.
- [ ] Given `build`'s machine block, when it is extracted and parsed with `jq`, then it is one object with `schema_version: 1`, the PR URL, the build head SHA, a build timestamp and one object per signal holding `status`. Its field list equals the one in `docs/result-schemas/pr-scorecard.md` (the suite reads that doc's field list).
- [ ] Given the full fixture, when `build` runs, then line 1 is the marker and line 2 equals the committed golden `fixtures/pr-scorecard/<case>/expected.header` byte for byte. In order, it holds the label, the short head SHA, `PARK: rubric_unsatisfied` with its `head unpinned` mark, `high`, `4/5`, the verify `3` / `1` / `5` with `current`, and `2` and `3` as the two round counts.
- [ ] Given the machine block, when the suite renders each signal's expected token from it using the schema doc's "Header line" rule, then every header token matches. Given the builder's ordered signal list and the doc's ordered list, then they are equal; a fixture that reorders the builder list fails.
- [ ] Given no card exists, when `post <url>` runs with the stub `gh`, then exactly one comment is created whose first line is the marker and second line is the header. Given it then runs again after a signal changed, the same comment is edited in place, no second comment is created, and the header and rows show the new value.

**Edge cases**
- [ ] Given a PR with no attributable gate line, no verify run, `rubric_score: null` and no drain ledger, when `build` runs, then the rows and header slots read `not_evaluated`, `not_run`, `no rubric` and `not_run`. Every slot is present, and none reads `MERGE`, `pass`, `0` or blank.
- [ ] Given a run file holding a gate line for a different PR only (including a bare `gate-eval: MERGE` that the run file does not tie to this PR), when `build` runs, then the gate row is `not_evaluated`, never the other PR's outcome.
- [ ] Given the builder's source and the stub `gh`, when the suite runs, then a grep finds no `gate-eval` and no `pr merge` invocation in `pr-scorecard.sh`, and the stub fails the test on any `pr merge` argv, any `gh pr edit`, or any PATCH to `…/pulls/<n>` (no PR title or body edit).
- [ ] Given a verify run for the head branch whose `head_sha` differs from the live head, when `build` runs, then the row and its header slot read `stale`. Given a matching run with no `run_end`, they are marked `incomplete`.
- [ ] Given `classify-risk.sh` returns `high_risk: null` (for example the head commit is absent locally), when `build` runs, then the risk row reads `unclassifiable` with the classifier's reason, and the header slot reads `unclassifiable`. Given `high_risk: false`, the slot reads `not high`, never `low` or `safe`.
- [ ] Given `read-token-ledger.sh` prints `LEDGER_UNREADABLE=1`, when `build` runs, then the token row reads `unavailable`, never `0`. Given a readable ledger with `EVENTS=0`, or only `"proxy":true` lines, the row reads `not recorded`, never `0 tokens`.
- [ ] Given a URL named by no `session_end`, no `pr_created` event and no run file, when `build` or `post` runs, then stderr holds `not_loomwright_pr`, nothing is printed or posted, and the exit code is 0. Given `LOOMWRIGHT_HOST_MODE=1`, the same happens with `host_mode_unsupported`.
- [ ] Given a marker comment authored by a different user, when `post` runs, then that comment is untouched, and the current user's own card is created or edited. Given two cards by the current user, the oldest is edited, none is created, the duplicate is named on stderr, and no delete call is made.
- [ ] Given a changed path with Markdown or HTML metacharacters (a backtick, `-->`, `](`, `![`) in the risk reasons, and a gate reason holding `-->`, `](`, `![`, a backtick and a newline, when `build` runs, then the marker stays the only first line, the header stays one line, the machine block still parses with `jq`, and no link, image or comment-close is produced.
- [ ] Given any fixture, when the header is checked, then it contains none of `%`, `/100`, `grade`, `score:` followed by a number, `![`, `http://`, `https://`, `certified`, `passed all` (case-insensitive), and it is one line.
- [ ] Given a card body with the header present, when `classify-bot-review.sh` classifies it as a PR comment, then it is dropped and never counted as a finding (a new case in `loomwright/scripts/test-classify-bot-review.sh`).

**Error scenarios**
- [ ] Given `gh` is missing, unauthenticated, or the create/edit call fails, when `post` runs, then it prints one stderr line naming the failure and exits 0.
- [ ] Given `jq` is missing, when `build` or `post` runs, then it prints one stderr line, prints no card or header, posts nothing, and exits 0.
- [ ] Given `.supervisor/config.json` holds `"pr_scorecard_post": false`, when `post` runs, then no `gh` write call is recorded and stderr says posting is off. Given a malformed config, the same happens with stderr naming the malformed config.
- [ ] Given mutation copies of the script (a missing signal rendered as `0` or `pass`; a non-`available` header slot dropped; an aggregate number added; `post` always creating a new comment), when the suite runs each, then at least one case fails per mutation.

**No public claim**
- [ ] Given the PR's diff, when `git diff --name-only <base>...HEAD` is listed, then it holds no `README.md`, `loomwright/README.md`, `.claude-plugin/` or `loomwright/.claude-plugin/` path, and the `changelog.d/` fragment describes the mechanism only (no score, pass rate or outcome claim).

## Non-goals
- Automatic posting from Phase 4.5, the drain's terminal result or `/automate`'s gate step (scorecard v1 item 2, deferred by the owner).
- Any row whose source is not built: mandate status, credentials and connectors, replay score history, plugin pin.
- Any public claim: no README, marketplace or plugin `description`, docs page, badge, release note, PR title or PR body asserting a score, pass rate or quality level. The card lives only in its own PR comment.
- Invoking, changing or re-deriving `gate-eval`, its conditions, its order or its park reasons; touching the sole `gh pr merge --squash` executor; any gating effect. The card changes no `heal_decision`, blocks nothing and merges nothing.
- A per-condition gate table, and changing `automate-next-step.sh` to record the gate's head SHA.
- A composite "PR score", or any new signal, measurement, estimate or dollar figure.
- Lane and wave PRs under `/automate --parallel` beyond rendering their missing signals `unavailable`; host mode beyond the `host_mode_unsupported` refusal.
- A slash command, a hook, or a Studio-side reader.
- Posting on PRs Loomwright did not open.
- Any change to the feature scorecard (`build-feature-scorecard.sh`, `feature-scorecard.json`, `propose-scorecard.sh`).
- Any change to the existing append-only marker comments (`dismissed`, `clean`, red-team advisory).

## Owner decisions
- 2026-11-09 (Vikash, in chat): APPROVED from the archive review; refreshed against main 8ec200e / v17.35.1.
- 2026-11-09 (Vikash, in chat): scorecard v1 item 1 (`build` + `post`, one comment edited in place, fail-SAFE, off-switch) and batch I item I3 (the one-line internal header) ship as ONE PR. Item 2 (automatic posting at Phase 4.5 / drain / gate call sites) is DEFERRED. Rows that depend on unbuilt items (mandate, credentials, replay score, plugin pin) are out.
- 2026-11-09 (Vikash, in chat, hard constraint): no public scorecard claims (README / marketplace / badge / PR body). The builder never invokes `gate-eval` and never re-derives gate conditions.
- Inherited, RESOLVED 2026-10-27 (Vikash GO, PO defaults): the gate row copies the recorded line only (item 1 OQ-1 (a)); posting is on by default with a `.supervisor/config.json` off-switch, and tokens are shown as numbers with no dollar figure (OQ-2); the card is edited in place (OQ-3); lane and wave PRs render missing signals `unavailable` (OQ-4); `PR_SCORECARD` is additive-only within `schema_version: 1`, and consumers trust only the Loomwright identity's card (OQ-5).
- Inherited from I3 (PO defaults, now approved with I3): no aggregate number (OQ-I16); rows not collapsed (OQ-I17); no tokens in the header (OQ-I18); a later row joins the header only when its own story names it and updates the "Header line" subsection (OQ-I20).
- PO default, pending owner review — 1. The marker is `<!-- loomwright:pr-scorecard -->`, not the sources' working form `<!-- loomwright:scorecard -->`, so it cannot be read as the feature scorecard.
- PO default, pending owner review — 2. No recorded gate line carries a head SHA, so an available gate row is always marked `head unpinned` and never `current` or `stale`. The alternatives were reading the driver's internal `<run_id>.next-step.json` sidecar (`ready_sha`), which is not a documented contract, or changing `automate-next-step.sh` to record the SHA, which edits the driver next to the merge gate. Both are rejected for this PR.
- PO default, pending owner review — 3. The risk row uses the PR's own `baseRefName` (`origin/<base>`), as gate condition 6 now does, and never runs `git fetch`. An absent head commit therefore reads `unclassifiable`.
- PO default, pending owner review — 4. Under `LOOMWRIGHT_HOST_MODE=1` (session logs move to the gate state dir), `build` and `post` refuse with `host_mode_unsupported` and exit 0.
- PO default, pending owner review — 5. The off-switch key is `pr_scorecard_post`. An unreadable or malformed `.supervisor/config.json` means no post: for an emitter that writes to a possibly public PR, the safe direction is not posting.
- PO default, pending owner review — 6. A verify run with no `run_end` is marked `incomplete`; its partial counts are never shown as a finished run.
- PO default, pending owner review — 7. No slash command; the script is run by hand. A command would need its own token budget and docs, and item 2's call sites are the planned way the card reaches users.

## Priority: MVP
**Rationale:** The owner approved it; it is useful by hand on any sequential Loomwright PR as soon as it lands, and deferred item 2 only calls it.

## Assumptions
- A PR's Loomwright-ness and its session join can be read from local `.supervisor/` state. That state is gitignored, so a card can only be built on the machine that ran the work (a lane clone's PRs read `unavailable`). Accepted for v1.
- Editing a comment in place through `gh api` (PATCH on the issue comment) is acceptable even though Loomwright's other marker comments are append-only by design. The PR scorecard is a current-state summary, not an event record.
- Several joined sessions can name one PR (a resumed run). The newest `session_end` naming the PR supplies the rubric and Phase 4.5 iterations; tokens sum over every joined session. The exact join order is written in the schema doc.
- GitHub shows line 2 of a comment as its first visible text (the line-1 HTML marker is invisible), so the header is what the owner sees first.
- A PR comment on a public repository is publicly readable. The hard constraint is read as "no claims": the header states facts already in the card, labelled internal and advisory, and the off-switch covers repos where the owner wants nothing posted.
- Shared-file sweep: the similar features are the existing `<!-- loomwright:` marker comments and the advisory readers. Registering a new result schema touches `RESULT_SCHEMAS.md` and the generated `capabilities.json` (`build-capabilities.sh --check` runs in CI). `classify-bot-review.sh` needs no code change because its default prefix already covers the marker; only its suite gains a case. New suites are discovered by glob, so no runner list changes. Neither `hooks.json` nor any prompt changes, so no token budget or loop inventory changes.

## Dependencies
- Depends on: none. It reads `classify-risk.sh` output as it is today; any `trusted-root:` or `project:` reason appears in the risk row with no change here.
- Blocks: scorecard v1 item 2 (automatic posting), deferred.
- File overlap with archived, not-approved rows (credentials C2, mandate M2, replay score): if they are ever revived, they edit the same three files and must run after this story.

## Risks
- **The card is read as merge-ready.** Mitigation: the header label says "not a merge decision"; a missing gate reads `not_evaluated`; an available gate line is always `head unpinned`; a non-`MERGE` row never reads as a pass.
- **A second gate implementation creeps in** ("is the rubric satisfied", "are checks green"). Mitigation: the grep and stub-`gh` cases, the risk-row comparison case, and the rule that a row pointing at gate conditions links `skills/automate-loop/SKILL.md` §10 without listing or counting them.
- **Header drifts from the rows.** Mitigation: tokens render from the machine block only, and the suite re-renders them.
- **Hostile text in a public comment** (file names, gate reasons). Mitigation: the hostile-fixture case and `jq`-built JSON.
- **The PR scorecard is confused with the feature scorecard.** Mitigation: the `pr-scorecard` / `PR_SCORECARD` naming everywhere, and the Naming paragraph copied into the schema doc.
- **Repo gates a new script can trip:** `check-test-hermetic.sh` (the new suite's first executable line must source `hermetic-test-env.sh`); `check-vendor-coupling.sh` (the script must not add a manifest token such as `.claude/`); `build-capabilities.sh --check` (the `capabilities.json` regeneration); `check-mkdir-lock.sh` if the script takes a lock; and bash 3.2 portability (no `mapfile`, no `timeout`, no `sed -i`, `shopt -s nullglob` around globs).
- **Size.** This is one cohesive new script with a large suite. If it overruns one PR, the cut is the tokens row (its coverage note and proxy handling are the most intricate rendering), never splitting `build` from `post`.

## Validation (must pass before merge)
1. **Static — PR scorecard suite:** `bash loomwright/scripts/test-pr-scorecard.sh` passes, including the golden-header, token-from-block, all-absent, unattributable-gate, stale/incomplete verify, hostile-text, banned-substring, upsert/duplicate/other-author, off-switch, host-mode and mutation cases.
2. **Static — classifier suite:** `bash loomwright/scripts/test-classify-bot-review.sh` passes with the new PR scorecard card case.
3. **Static — capability contract current:** `bash loomwright/scripts/build-capabilities.sh --check` exits 0 with the regenerated `loomwright/capabilities.json`.
4. **Static — no public surface changed:** `git diff --name-only <base>...HEAD` lists no `README.md`, `loomwright/README.md`, `.claude-plugin/` or `loomwright/.claude-plugin/` path.
5. **Static — repo gates:** `bash scripts/ci-local.sh --affected` passes (hermetic-test, vendor-coupling, doc-currency, citation-drift and prompt-history gates included). The PR adds one `changelog.d/` fragment, never hand-edits `plugin.json`, `marketplace.json` or `CHANGELOG.md`, and `bash scripts/check-version-bump.sh` passes.
6. **Running system — one card, edited in place, on a real PR:** on a real Loomwright-opened PR in this repo, the owner runs `pr-scorecard.sh post <url>`, then changes one signal (for example a later drain round) and runs it again. The PR shows exactly one comment, its first visible line is the header, and the second run edited the comment rather than adding one. The comment is then dropped by the next drain round's `classify-bot-review.sh` pass (no finding is raised for it).

## Depends on
none

## Touches
loomwright/scripts/pr-scorecard.sh
loomwright/scripts/test-pr-scorecard.sh
loomwright/scripts/fixtures/pr-scorecard
loomwright/scripts/test-classify-bot-review.sh
loomwright/docs/result-schemas/pr-scorecard.md
loomwright/docs/RESULT_SCHEMAS.md
loomwright/capabilities.json
changelog.d/pr-scorecard-builder.md

## Changes since the sources were written
- **Merged.** Item 1 and I3 are one story; I3's dependency on item 1 is gone. Item 2 is deferred, so the "part 1 of 2" framing and the `Blocks:` link are dropped.
- **Gate line carries no head SHA (premise false in both sources).** Item 1's AC "a recorded gate line at an older head is `stale`" and I3's matching header AC cannot be met: neither `gate-eval: MERGE` nor the park lines record a SHA, and the MERGE line does not name the PR. They are replaced by `head unpinned` plus an attribution rule (PO default 2).
- **Gate condition 6's base changed.** It is now `origin/<PR base>` resolved by `resolve-base-branch.sh`, not `main`. The risk row uses the PR's `baseRefName` (PO default 3).
- **`session_end` carries `pr_url`.** It is added as the first join, beside `pr_created` and the run file.
- **Host mode exists (`LOOMWRIGHT_HOST_MODE=1`).** `pr_created` and the session logs move to the gate state dir there; the builder refuses by name (PO default 4).
- **`/verify` runs can pause** with partial counts; such a run is marked `incomplete` (PO default 6).
- **Token ledger:** a readable ledger with `EVENTS=0` now also reads `not recorded`, alongside the proxy-only case.
- **Registering a result schema regenerates `loomwright/capabilities.json`** (`build-capabilities.sh --check` is a CI step). It is added to Touches; the sources missed it.
- **Name clashes checked.** No `pr-scorecard`, `PR_SCORECARD` or `loomwright:scorecard` exists on main. "Scorecard" alone means the feature scorecard (#785: `build-feature-scorecard.sh`, `/propose --from-scorecard`), so the marker becomes `loomwright:pr-scorecard` (PO default 1). `GATE_VERDICT` is the QA Strategist's schema, so the gate row is never called a gate verdict. `read-verify.sh` reads the `.agent/verify.json` environment contract, not verify runs; the builder reads the run dir and `summary.md`. The reviewer replay (#783) adds nothing this card reads, and the replay-score row stays out.
- **Rows dropped:** mandate, credentials and connectors, replay score and plugin pin (archived extensions, not built). **Rows kept:** merge gate, risk class, rubric, `/verify`, review rounds (two numbers), tokens.
- **Touches made strict:** `changelog.d/` became a named fragment file; the fixtures directory and `capabilities.json` were added.
