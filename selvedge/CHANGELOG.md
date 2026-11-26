# Changelog

All notable changes to the selvedge plugin. Selvedge releases on its own: each release bumps
`selvedge/.claude-plugin/plugin.json`, its entry in `.claude-plugin/marketplace.json` and this
file together, never through the repository's `changelog.d/` fragments (those fold into
Loomwright's version only).

Format: each release is a heading `## <X.Y.Z> — <YYYY-MM-DD>`; the first such heading is the
current release, and `selvedge/tests/run.sh` checks it equals `plugin.json`'s `version`.

## 0.12.1 — 2026-11-25

- **`response_json_each` never reads a missing field as `null`.** When any element lacks the item,
  the read has no value (NOT_VERIFIABLE `no_value_read`). Before, "the key is returned as `null`"
  and "the key is left out" read the same text, so a "never returns X" criterion PASSed on the
  buggy commit of the 0.12.0 tuning run's one false-PASS (seeded data held no X).
- **An empty item pointer reads the whole elements** (`response_json_each:/posts|`), so "the reply
  never returns `contactEmail`" is `absent "\"contactEmail\""` on it. The planner is told not to
  judge "never returns X" by X's value being null.
- **A reply cut at 64 KiB has no body value.** `response_text`, `response_json…` reads of a
  truncated reply read no value (NOT_VERIFIABLE `no_value_read`); before, `contains` judged only the
  kept part (a false FAIL in a 0.12.1 tuning pass: a Next.js page whose name came past the cut) and
  `absent` could PASS on a text that sits past it. Status and headers stay readable; the planner is
  told to read a large page with `text`.
- **With no test accounts listed, the planner signs in with values a snapshot proved.** It tries
  made-up values (or a demo account the app shows) in a snapshot prefix and writes them into the
  plan only when that snapshot reached the signed-in page; otherwise it keeps `{{NAME}}` values.
  In a 0.12.1 tuning pass the 0.12.0 rule ("always `{{NAME}}`") left 5 criteria on an app that
  accepts any sign-in BLOCKED `placeholder_unset`; 0.12.0 had judged them with `demo`.
- 0.12.0 tuning report (129 cases, test accounts on): false-PASS 1/45, false-FAIL 0/84, abstention
  8/129 (6.2%). Kept out of `results.json`, like the 0.11.2 one.

## 0.12.0 — 2026-11-24

Engine revision 2 (Phase 2's second and last counted revision): the causes the 0.11.2 tuning run
showed for abstention and false-FAIL, read on the tuning side only.

- **Verdicts.** A criterion with a `material: true` assumption is NOT_VERIFIABLE
  `material_assumption` whether its `expect` matched or not: a guessed premise decides neither
  PASS nor FAIL.
- **New check `absent`**: the value read does not contain a text. A `matches` whose pattern hides
  an absence in a whole-text negative lookahead (`(?![\s\S]*x)`) is now `existence_only_expect`,
  as is `absent` with a blank text.
- **One bad criterion no longer blocks the rest.** The bare `selvedge plan` sets aside each
  criterion whose own steps break the lint (`not_planned`, new reason `criterion_plan_invalid`,
  NOT_VERIFIABLE, its problem lines as the detail) and freezes the others. `--freeze` and
  `--validate` stay strict.
- **The default planner lints its own plan** before returning it: `plan --validate /dev/stdin`
  is its second allowed tool.
- **Reads.** `response_text` is trimmed like `text`. `at_load: true` on a read judges it as
  taken, without the stable wait, for a criterion about a page's first state (allowed only before
  any action, in a positive criterion, with `equals`/`contains`/`matches`; new plan problem
  `at_load_misused`). New: `response_header:<name>`, `cookie_attribute:<name>:<attribute>`
  (HttpOnly, Secure, SameSite, path, domain; never the value), `focused` (the element holding
  keyboard focus), `response_json_each:<array>|<item>` (one field of every element, as JSON
  text) and `response_json_length:<array>`.
- **Requests.** A `request` may carry a raw `body` instead of `json`, and `headers` (headers
  `fetch` forbids page code to set are refused). A snapshot prefix may send a non-GET request to a
  **local** origin, counted as a plan-time action as a click is; to a remote origin it stays
  `prefix_mutation_refused`.
- **Sign-ins.** `planner-input.json` lists `env_names` (the `auth.env` names, never values), and
  the planner is told to use only those as `{{NAME}}` and that a 401 without credentials is a
  sign-in, not `side_effect_not_observable`. The eval harness gives a commit target the test
  accounts named in `SELVEDGE_EVAL_CREDENTIALS` (a file outside the repo; new token
  `credentials_invalid`).
- Tuning report on 0.11.2 (129 cases, before these changes): false-PASS 0/45, false-FAIL 3/84,
  abstention 37/129 (28.7%). Kept out of `results.json`: it is the diagnosis these changes answer.

## 0.11.2 — 2026-11-24

- A held-out eval report no longer gives a planted group's FAIL/PASS split or error counts. Its
  `per_group` row holds only `group_id`, `criteria` and `abstained`: the group's criteria are
  committed, so the split would narrow each withheld answer and the error counts would point at the
  groups Selvedge got wrong. Real-bug and non-defect groups keep every field, and so does every
  group in a tuning report.
- First held-out report (0.11.1, 235 cases): false-PASS 0/85, abstention 107/235; gate not met.

## 0.11.1 — 2026-11-23

- `node selvedge/eval/harness.mjs run` now checks the browser before it brings any target up or
  makes any planner call: it loads the Playwright every `selvedge run` child would load (the CLI's
  own resolver, with the child's environment and a workspace as root and working directory, so
  `SELVEDGE_PLAYWRIGHT_MODULE` is honoured exactly as the child honours it), launches chromium
  headless and closes it. When either step fails it prints `harness: FAIL browser_unavailable:
  <the error's first line> — …`, exits 1 and writes nothing to the work dir or `results.json`.
  Before, a Playwright whose browser build was not in the cache (1.56.1 wants build 1194; the cache
  held only 1255) still planned every target and ended every criterion `BLOCKED
  playwright_unavailable`: about 4.5M planner tokens and 30 minutes for a 72/72-abstained report.
  New harness reason token `browser_unavailable` (`selvedge/eval/README.md`). The engine is
  unchanged.

## 0.11.0 — 2026-11-23

- A new plan step, `request` (requirement qa-split/08b; owner decisions of 2026-11-23: D6 gains the
  step, it is part of the web adapter rather than a new target, and it spends Phase 2's first engine
  revision). `{"type": "request", "method": "GET"|"POST"|"PUT"|"PATCH"|"DELETE", "url", "json"?}`
  sends one request to the origin of the page the criterion is on (its last `goto`; the lint refuses
  any other origin as `origin_not_allowed`). `json` is a plain object whose string leaves may be
  `{{NAME}}`; there is no headers field and no raw body. A non-GET request is an action, so the
  read-after-the-last-action and negative-baseline rules apply to it.
- The runner sends it as a `fetch` from inside the page: one fixed, runner-owned function run by
  `page.evaluate`, with the method, URL and body passed as arguments. So both guard layers check it,
  and a refusal is BLOCKED with the guard's reason (`host_not_allowed`, `remote_mutation_refused`, …).
  Playwright's `context.request` is never used: a probe with Playwright 1.65.1 showed it bypasses
  `context.route`, so the route layer's checks would not apply to it. Neither is a Node HTTP client.
- New reads with no locator: `response_status`, `response_text` (the reply kept up to 64 KiB) and
  `response_json:<RFC 6901 pointer>` of the criterion's last reply, and `cookie:<name>`, a fingerprint
  of the context's cookie (`sha256:` and 16 hex digits), never its value. New lint codes:
  `response_without_request` (a reply read with no request before it) and `prefix_mutation_refused`
  (a snapshot prefix request that is not GET). An expect on a cookie read must be `changed_from`
  against a baseline read of the same cookie (`existence_only_expect` otherwise).
- Evidence: a request step line carries `request: {method, url, json_keys, status}`, never the body.
  The comment shows a request's method and path, and never publishes a read value for a criterion
  whose plan reads a cookie. `selvedge snapshot` accepts a GET request in a prefix and prints each
  reply's status and first 2 KiB under `replies`.
- The planner prompt has a section on the request step, with one positive and one negative example;
  `side_effect_not_observable` is now for an effect that neither a page nor a reply shows.
- `tests/test-request-step.sh` pins all of it, including the probe as a fixture: a request step to an
  unlisted origin and a remote POST without `allow_remote_mutation` are refused by the route layer,
  and `context.request` is not seen by it. Every arm was checked red under its own mutation. The
  tuning-set eval run that would measure group A (requirement acceptance, last bullet) has not been
  run in this release.

## 0.10.2 — 2026-11-23

- `selvedge/eval/eval-set.mjs import-planted <out-dir>` adds the planted-defect session's output to
  the known-answer set. That output is `out/cases.jsonl` plus one `out/pd-<slug>/` variant folder
  per bug, holding exactly `app-server.mjs` and `servers.mjs`. A slug names its bug, so the import
  gives each group an opaque id (`pd-` and 10 hex of `sha256("planted:" + slug)`) and keeps the
  slug-to-id list in the session's own folder. The cases go in through `split`, so a refusal writes
  nothing. Each variant is then copied to its side: tuning variants into the repo, held-out ones to
  the outside folder only. A malformed output is refused as `planted_import_invalid`.
  `tests/test-eval-set.sh` pins the import, its refusals and the opaque ids, and each refusal's arm
  was checked red under a mutation. The exception is the guard against two slugs hashing to one id,
  which no practical test input can reach.
- `selvedge/eval/planted-session-brief.md` is the committed brief for that session. It is given as
  the session's first message, since the start folder may hold only the two app files. The eval
  README gives the start command and the import steps.

## 0.10.1 — 2026-11-23

- `selvedge/eval/target-driver.sh`: the font step asks Google again, up to five tries in all, when it
  serves a next/font/google CSS URL as `fonts.gstatic.com/l/` files, which Turbopack refuses. It
  happened for about 1 request in 15 (MuseoModerno, measured 2026-11-23), with any user agent, and
  stopped the tuning run twice with `target_unavailable`. A failed step now reports the error line
  itself instead of the last three lines of the stack trace, which hid the cause. A new `fonts
  <clone> <out.js>` subcommand runs the step alone, through the same `fonts_step` (retry and
  error line) that `up` uses, and `tests/test-target-driver-fonts.sh` pins both with a fake `curl`.
  The `CHROME_UA` comment now says a newer user agent alone does not stop the `/l/` form.
- `selvedge/eval/results.json` carries the first tuning report (engine 0.10.0, planner sonnet, one
  plan and one run per target): 72 cases, PASS 27, FAIL 2, BLOCKED 15, NOT_VERIFIABLE 28;
  false-PASS 0/12, false-FAIL 0/60, abstention 43/72. `side_effect_not_observable` is 16 of 72.
  The planner notes for those 16 name the same cause: each criterion checks an HTTP status, a POST
  response or a session cookie, which no browser step can read. There is no 0.9.0 tuning report
  to compare with.

## 0.10.0 — 2026-11-22

- The planner prompt (`prompts/planner.md`, rule 3) now tells the planner to look for the page
  that shows a negative criterion's side effect before giving up on it: a list or count, a
  counter or total, the touched record's detail page, a history page, or the same page opened
  again. It shows the cross-page shape (read the baseline on that page, `goto` the action's page
  and act, `goto` back and read again), which the lint already accepted because `goto` is not an
  action. On the 0.9.0 held-out run, 49 of 126 criteria were `side_effect_not_observable`; this
  change has not been measured against that set yet.
- Stricter lint: a `not_planned` entry with reason `side_effect_not_observable` needs a non-empty
  `detail` naming the pages looked at, or the plan is rejected `invalid_not_planned`. A plan that
  omitted it was accepted before. README, the plan schema's description and
  `tests/test-plan-validate.sh` say so, and the cross-page negative shape is pinned as accepted.
- The PR comment now shows that note. For a criterion under `not_planned`, `lib/comment-render.mjs`
  adds a `Planner note` line (the `detail`) and a `Suggested rewrite` line (the `rewrite`) under
  its reason, each redacted like a read value. Before, both stayed in `plan.json` inside the run
  folder, and the comment showed only the generic hint.

## 0.9.1 — 2026-11-22

- `selvedge/eval/harness.mjs`: a target whose plan does not freeze is no longer replayed. Its
  cases keep BLOCKED main verdicts (they still count as abstention), but no made-up BLOCKED replays
  are written for it, and its `runs[]` entry says nothing ran (`run`, `run_id`, `planner_tokens`
  and `duration_ms` all null; tokens were reported as 0 before). Each target result records
  `frozen` per plan; a result written before that field existed is read back from the target's
  logs on `--resume`.
- `selvedge/eval/stats.mjs` `buildReport` takes `not_replayed` and leaves those cases out of the
  runner repeatability series, so a missing replay is never counted as a runner flip; the runner
  `cases` count can now be lower than the case count. `eval/README.md` says so.
- The work-dir containment check resolves symlinks in both paths, including a path that does not
  exist yet (its nearest existing parent), so a symlinked prefix such as `/tmp` → `/private/tmp`
  cannot hide a work dir inside the repository. It reuses `realpathOrResolve` from
  `lib/env-approvals.mjs` (now exported) instead of a second copy.

## 0.9.0 — 2026-11-21

- `selvedge/eval/harness.mjs` measures Selvedge on the known-answer set. `run --set
  held-out|tuning` checks the set first (for held-out: validate, the outside folder's manifest and
  the answers; any problem stops it before a target is brought up or a file is written), then runs
  the normal path on every case: each target is brought up once by `selvedge/eval/target-driver.sh`,
  planned, frozen and run with no model, and taken down. It scores each verdict against the known
  answer and appends a report for the engine version to `selvedge/eval/results.json`: false-PASS,
  false-FAIL and abstention with numerators, denominators and exact Clopper-Pearson 95% intervals;
  `model-judged` criteria counted apart; counts per defect and per app; runner flips (replays of one
  frozen plan) and planner flips (fresh plans) apart from the main denominators; planner tokens and
  duration per run. It prints the Phase 3 gate line: `met` only on a held-out report with a
  known-FAIL denominator at the floor, false-PASS at most 5% and abstention at most 20%. When two
  engine versions' full held-out reports both miss, it says to stop and run the section 8 review; it
  never loosens the gate. `readme` writes the results block in this README from `results.json`, and
  `check-readme` (run by the tests) fails when they differ. `SELVEDGE_PLANNER_TOKEN_BUDGET` is
  removed from every selvedge child the harness starts, so no plan is BLOCKED `budget_exceeded`
  after its tokens were spent.
- `selvedge/eval/target-driver.sh` revives a sports-management commit from the setup lines
  `real-bugs.json` recorded for it (a scratch clone, a read-only copy of the owner's Supabase config
  on its own project id and 553xx ports, `npm ci`, `supabase db reset`, fixture SQL, `.env.local`,
  the Google Fonts stylesheets, a fresh `next dev`); a setup line it does not know, or a step that
  fails, stops the run with `target_unavailable` and the step named. It serves a planted variant with
  `node`.
- The first real held-out report is in `results.json`, and this README's "Measuring Selvedge" section
  shows it; how it was run is in `docs/evidence/qa-split-08-eval-harness.md`.
- `tests/test-eval-harness.sh` covers the interval table, the gate and its floor, the manifest
  refusal, model-judged, repeatability, the two-revision stop, tuning, the README sync and each
  harness reason token, with a stub CLI and a stub driver.

## 0.8.0 — 2026-11-21

- `selvedge/eval/` holds a known-answer set for measuring how often Selvedge says PASS when the
  right answer is FAIL. It is an owner-only tool, not a CLI command. `eval-set.mjs` validates the
  set, splits it by underlying defect into tuning (about 40%) and held-out (about 60%) with a
  recorded seed, checks that no held-out answer or variant is tracked in the repository
  (`check-leak`), keeps the held-out answers in an outside folder (`$SELVEDGE_EVAL_HELD_OUT`,
  default `~/.claude/selvedge-eval/held-out/`) behind a committed sha256 manifest
  (`manifest write|check`), checks the planted-defect author's start folder, and prints each count
  beside its floor (`count`). In this release every held-out answer can still be worked out from
  committed data (a non-defect case is PASS by rule; a real-bug case follows from its commit's role
  in `real-bugs.json`); only the planted variants, once they land, will be withheld. Every failure is a named reason token; `selvedge/eval/README.md`
  lists them. `tests/test-eval-set.sh` covers each one on temp fixtures.
- The set's first data: real sports-management bugs, each revived on localhost at its parent and
  fix commits and recorded in `selvedge/eval/real-bugs.json` (`used`, or `skipped` with the
  reason), with one FAIL case on the parent and one PASS case on the fix, plus non-defect criteria
  taken on the same commits and observed to hold. Planted defects are not in this release: the
  owner writes them in a separate session, and the floors that need them stay `open` until then
  (`node selvedge/eval/eval-set.mjs count` shows which).
- `validate` accepts a commit that is one real bug's `fix_sha` and the next one's `parent_sha` (two
  fixes merged back to back): a case on it takes its role from its own `real-bugs.json` entry
  (`group_id`, default `sm-pr-<pr>`), and with no such entry it is `case_invalid`. Before, the
  later entry overwrote the earlier one's role and good cases were rejected.
- `selvedge/eval/plugin-eval-limits.md` records what `claude plugin eval` could and could not do
  for this set when re-checked.

## 0.7.1 — 2026-11-20

- `selvedge doctor` treats a blank `SELVEDGE_PLANNER` as unset, exactly as `plan` does, so the
  planner line falls back to `claude` on `PATH` instead of reporting a planner that `plan` would
  not use. Tests now also pin the browser line when the Playwright library is missing, a Playwright
  that reports no browser path, and the approvals line with no `selvedge.json`.
- `selvedge sample-app [--port N]`: before it listens it connects to 127.0.0.1:N and [::1]:N
  (`localhost` can resolve to either): a connection accepted on either (a server bound to
  127.0.0.1, to ::1, or to the wildcard, which a bind on 127.0.0.1 alone would sit beside) exits 1
  naming the port, as does the listen's own EADDRINUSE. In 0.7.0 only the listen's own error was
  caught.
- `docs/quick-start-timing.md` records the timed rehearsal on the sample app and a timed run on a
  real project (Sportify, its own Playwright 1.56.1, fresh `HOME`: 107 s of command time, 3/3
  criteria PASS), both command time rather than a person reading and typing; the README carries the
  fixes the rehearsal found.

## 0.7.0 — 2026-11-18

- `selvedge doctor` checks, one line each, Node >= 18, the Playwright library (found exactly as `run`
  finds it: `SELVEDGE_PLAYWRIGHT_MODULE`, else the repo's own `node_modules`), that Playwright's
  Chromium on disk, `selvedge.json` (present and valid), hook approvals ("no hooks" when there are
  none) and the planner (`SELVEDGE_PLANNER` set, or `claude` on `PATH`). Each line is `ok <check>`
  or `FAIL <check>: <the one fix>`; exit 0 when all pass, 1 when any fails. The checks live in
  `lib/doctor.mjs` and call the helpers `run`, `snapshot` and `plan` use; the Node check also runs
  in bash first, so a missing or older Node prints its `FAIL` line and
  `skipped: the other checks need Node` instead of crashing.
- `selvedge sample-app [--port N]` serves the bundled fixture app (`tests/fixtures/app-server.mjs`)
  on `http://localhost:N` (default 4173) in the foreground until Ctrl-C, with no watchdog, and prints
  its origin and the `selvedge env init --port N` line; a port already in use exits 1 naming it.
  `startAppServer()` takes an optional port; with none it still binds a random one.
- The README opens with a **Quick start** (install → `install-cli` → a demo folder with Playwright
  → `env init` → `doctor` → `sample-app` → `/selvedge:verify` with three example criteria → the
  verdict table, each command with its expected output) and **Honest limits** (web only, what
  BLOCKED and NOT_VERIFIABLE mean, the secret limit, no accuracy numbers before the Phase 2
  measurement). `docs/quick-start-timing.md` records the timed rehearsal and holds the owner's
  fresh-account run.

## 0.6.0 — 2026-11-18

- `selvedge comment <run-dir> --pr <n> [--yes] [--base <ref>] [--allow-public-values]` posts a run
  folder's verdicts to the PR as ONE comment, found by its `<!-- selvedge:verdict -->` marker on a
  comment authored by the account `gh` is signed in as, and updated in place (`PATCH`); it creates
  one only when no such comment exists, never touches a comment without the marker or one by another
  author, and exits 1 without posting when the signed-in login cannot be read. The body reaches `gh` as a file, never as command-line text. It is
  text only: a summary line, the short plan sha256 and revision, and per criterion the text, verdict,
  interpretation, assumptions, steps as type and locator, the expected value, matched, the evidence
  class and, for BLOCKED / NOT_VERIFIABLE, the reason with an unblock hint. Every URL is cut to its
  path; no `fill` / `select` value, `{{NAME}}` value, header name or evidence file name is shown.
- `selvedge.json` takes a `comment` key: `read_values` (default `false`) and `redact` (default `[]`,
  JavaScript regular expressions). `comment` reads it from the PR's base branch only, never the
  working tree. With the opt-in, a repo that is not `PRIVATE` (or whose visibility cannot be read)
  is refused `read_values_public_repo` unless `--allow-public-values` is given, and every published
  value is redacted (emails, runs of 6+ digits, URL query strings, 32+ character tokens, then the
  configured patterns).
- A later plan revision shows each criterion's own verdict on every earlier plan (`FAIL on plan 1 →
  PASS on plan 2`, `not run on plan <r>`, or the whole run's verdict labelled `(whole run)` when
  the earlier run folder is gone), and the summary counts `PASS after revision` separately.
- New reasons: `read_values_public_repo`, `comment_requires_yes` (no `--yes` and stdin not a
  terminal) and `verdict_missing` (no `verdict.json` in the run folder).
- The Claude Code adapter: `/selvedge:verify [PR number | criteria file | pasted criteria]` resolves
  the source to `selvedge criteria from-pr | from-md | from-text`, spawns the `verifier` subagent
  (tools: Bash and Read only) that runs `criteria`, `plan --init`, `snapshot`, `plan --validate`,
  `plan --freeze`, `run` and `verdict`, reports the table from `verdict.json`, and for a PR posts
  through `selvedge comment … --yes` only after asking. The verifier never edits `plan.json` after
  the freeze and never reads `~/.local/state/selvedge/`.
- `skills/verify/SKILL.md` carries the same workflow, in the same command order, for any agent
  host; `selvedge/tests/test-adapter.sh` pins the tools, the order, the prohibitions, the token
  budget, the posting rule and the plugin description (<= 600 characters, no version token, equal
  to the marketplace entry's). A live session's verdict equals a hand-run `run --replay` of the same
  frozen plan: [`docs/evidence/verify-adapter-equivalence.md`](docs/evidence/verify-adapter-equivalence.md).

## 0.5.0 — 2026-11-17

- `selvedge.json` takes an `auth` key: `env` (the names, never the values, of the environment
  variables the sign-in reads) and `signed_in_check` (`url` on a listed origin, and one plan-step
  locator that matches only when signed in). Every command that loads the config refuses an unknown
  `auth` or `signed_in_check` key, a bad variable name, a check URL on an unlisted origin and a locator
  that is not an object (`config_schema_violation`); `run` and `auth setup --headed` also refuse a
  CSS or XPath locator before anything launches.
- `selvedge auth setup` signs in once, outside any plan or model: it runs the approved
  `hooks.auth_setup` (credentials only from the variables `auth.env` names; an unset one is
  `BLOCKED placeholder_unset` and the hook does not run), and keeps the Playwright storage state it
  writes to `$SELVEDGE_STORAGE_STATE` at `$HOME/.local/state/selvedge/<repo-id>/auth/storageState.json`
  (directories `0700`, file `0600`, never inside the repo). `--headed` lets you sign in yourself in a
  visible guarded browser instead (up to `SELVEDGE_AUTH_TIMEOUT_MS`), with no hook and no credential
  passing through selvedge.
- `selvedge run` loads that session into every criterion's fresh context and checks
  `auth.signed_in_check` once, after the hooks and before the first criterion. A failed check makes
  every criterion BLOCKED `needs_auth` (a new reason) at once when nobody can sign in (stdin not a
  terminal, or the new `--non-interactive` flag), with exactly one check and no retry loop; on a
  terminal it asks for one sign-in, reads one line and checks once more. `run` never runs
  `auth_setup` itself. With no `auth` key, `run` is unchanged.
- Every `auth.env` value is redacted like a `{{NAME}}` value (written back as `{{NAME}}`) in
  `evidence.jsonl`, `verdict.json`, traces and stderr, and in what `selvedge snapshot` prints (the
  page a planner looks at), so a credential a page shows reaches the planner only as `{{NAME}}`.
- `run --trace` with a stored session keeps no session value: the storage state Playwright records
  in the trace's context options reads `[redacted]`, and every cookie and local storage value the
  session holds is replaced by `[redacted]` wherever the trace shows it, as stored and URL-encoded.
  A session value shorter than 8 characters is replaced only inside that storage state, so a `"1"`
  flag neither mangles the kept trace nor drops it. A `{{NAME}}` / `auth.env` value is now also
  redacted in its URL-encoded form.
- A stored session file Playwright would not load (not JSON, a JSON object without a storage
  state's `cookies` / `origins` shape, or a cookie breaking Playwright's rules: `expires` other than
  -1 or a unix time up to year 9999, a `url` that is not `http`/`https`) is BLOCKED `needs_auth`
  before any browser opens, with or without `auth.signed_in_check`; `auth setup` keeps no
  hook-written file of that kind. A session Playwright still refuses when a context opens is
  `needs_auth` too, never `playwright_unavailable`.
- The README documents `auth setup`, where the session lives, the `needs_auth` behaviour, and the
  honest limit: an agent with shell access can read any file you can, so selvedge keeps secrets out
  of plans, evidence, PR comments and model prompts, and does not claim they are out of reach.

## 0.4.1 — 2026-11-17

- `selvedge run` checks a first run's `plan.json` against the folder's own `event: "freeze"` line in
  `.selvedge/runs.jsonl`, as `--replay` already did, so a `plan.json` and `plan.sha256` edited
  together are `plan_modified` and nothing runs.
- `selvedge run` claims the folder (`run.claim`, created exclusively) before any `reset` / `seed`
  hook runs, so of two runs started together on one folder only one runs the hooks; the other is
  `already_run`. The claim is removed when the run ends; a run killed outright leaves it, and the
  folder reads as `already_run` until it is removed.

## 0.4.0 — 2026-11-16

- `selvedge run <run-dir>` executes a frozen `plan.json` in the guarded browser with no model call.
  It refuses, before anything is written or launched, a folder with no `plan.sha256`
  (`not_frozen`), one that already ran (`already_run`) and a `plan.json` whose sha256 changed
  (`plan_modified`). Each criterion runs in a fresh guarded context. The runner writes every line of
  `evidence.jsonl` itself (`run_start`, one `step` line per executed step, `criterion_end`,
  `run_end`; every `{{NAME}}` value written back as `{{NAME}}`) and one end-state screenshot per
  criterion. Every `expect` after a read gets a stable wait (network idle, then a settled DOM, within
  5 s) and one re-read before it is judged, so a check that holds before an in-flight side effect
  lands (`changed_from` false) cannot PASS early. A step that throws is BLOCKED `step_failed` (with its index), three no-change
  actions in a row are BLOCKED `stuck_screen`, and `SELVEDGE_RUN_BUDGET_MS`,
  `SELVEDGE_PLANNER_TOKEN_BUDGET` and `SELVEDGE_STEP_TIMEOUT_MS` bound the run. Approved `reset` /
  `seed` hooks run before the first browser (`data_state: managed`); an unapproved one blocks every
  criterion (`env_hooks_unapproved`). Each run appends exactly one `event: "run"` line to
  `.selvedge/runs.jsonl` (`entry` from `SELVEDGE_ENTRY`: `session`, `ci` or `loomwright`).
- `selvedge verdict <run-dir>` derives PASS / FAIL / BLOCKED / NOT_VERIFIABLE per criterion from
  `evidence.jsonl` and `plan.json` only, into `verdict.json` (schema in
  `schemas/verdict.schema.json`): an empty read is NOT_VERIFIABLE `no_value_read`, never PASS, for
  any `expect` in a criterion, not only the last; any
  mismatched `expect` in a criterion FAILs it, carrying `read_value` and `expected` (`changed_from`
  compares a read with the previous read of the same locator and property); a material assumption is NOT_VERIFIABLE
  `material_assumption`; an interrupted criterion is BLOCKED `run_interrupted`; `prior_revisions`
  lists earlier revisions' verdicts. Exit precedence: 1 FAIL, 2 BLOCKED, 3 NOT_VERIFIABLE, 0. `run`
  calls the same derivation; re-running `verdict` appends nothing.
- `selvedge run --replay <frozen-run-dir>` runs a frozen plan again, byte for byte, in a new run
  folder (`replay_of` the frozen run id, the same `plan_revision`, `planner_tokens` 0). A
  `plan.json` that differs from `plan.sha256` or from the run's freeze line in `runs.jsonl` is
  `plan_modified` and no folder is created; a control the frozen locator no longer matches is
  BLOCKED `step_failed`.
- `selvedge run --trace` keeps a Playwright trace per criterion as `traces/<criterion-id>.zip`, with
  `Cookie` / `Set-Cookie` / `Authorization` values, every cookie value seen and every resolved
  `{{NAME}}` value removed. Selvedge rewrites the zip itself on `node:zlib`; a trace it cannot redact
  whole is dropped, never kept.
- `selvedge env init` first adds `.selvedge/` to the repo's `.gitignore` (once, even when
  `selvedge.json` exists or init fails).
- Ten new reasons: `step_failed`, `stuck_screen`, `budget_exceeded`, `run_interrupted` (BLOCKED),
  `no_value_read`, `material_assumption` (NOT_VERIFIABLE), `plan_modified`, `already_run`,
  `not_frozen`, `evidence_missing` (usage). The plan-step executor moved from `lib/snapshot.mjs` to
  `lib/runner/steps.mjs` (one executor for `snapshot` and `run`).

## 0.3.0 — 2026-11-15

- Criteria become a frozen, validated step plan. `selvedge criteria from-pr|from-md|from-text`
  turns acceptance criteria into `criteria.json` (stable `c-<12 hex>` ids, the same bytes from any
  input; schema in `schemas/criteria.schema.json`), and `criteria check` flags vague criteria with a
  deterministic phrase list and a suggested rewrite.
- `selvedge snapshot <url> [--steps <prefix.json>] --run-dir <dir>`: an allowed page's
  accessibility tree through the browser guard, after an optional prefix of up to 15 action steps.
  Unlisted origins, bad prefixes, unset `{{NAME}}` placeholders and a missing Playwright are refused
  before any browser launches. Each call is recorded in `snapshots.jsonl` (no page text) and
  counts against `SELVEDGE_SNAPSHOT_BUDGET` (default 20 per run folder; past it,
  `NOT_VERIFIABLE exploration_budget`, exit 3). Playwright is resolved at run time from
  `SELVEDGE_PLAYWRIGHT_MODULE` or the target project's own `node_modules`.
- `selvedge plan`: `--init` makes a run folder `.selvedge/runs/<run-id>/`; the planner
  (`SELVEDGE_PLANNER`, or by default `claude -p` with the fixed prompt `prompts/planner.md` and only
  `snapshot` allowed) never receives a vague criterion, which `plan` lists under `not_planned`
  itself; `--validate` lints the plan (the PASS rule — a value read after the last action —,
  existence-only checks, negative baselines, interpretation/polarity/assumptions, coverage,
  `criteria_sha256`, step types, fields, locators, code-like content, goto origins; every problem
  listed); `--freeze` lints, stamps `plan_revision`, and writes `plan.sha256` (the hash of the
  bytes written) and `freeze.json`. A frozen folder is never written again (`already_frozen`); each
  re-plan of the same criteria is the next revision, counted from `.selvedge/runs.jsonl`. Planner
  tokens and the snapshot `plan_time_actions` sum are recorded in `freeze.json` and the
  `runs.jsonl` freeze line. Schema in `schemas/plan.schema.json` (`target: "web"`).
- The planner sees no more than the plan: `plan --base <ref>` hands it `SELVEDGE_BASE` (empty for
  the working tree), so every `snapshot` it runs reads the same allowlist, and a `snapshot` whose
  `--base` or `--run-dir` names another source or folder than `SELVEDGE_BASE` / `SELVEDGE_RUN_DIR`
  is a usage error. A resolved `{{NAME}}` value is printed as `{{NAME}}` (tree, error, stderr; as given
  and as Playwright quotes it); any variable name still resolves (an open item, see the README). The lint
  also rejects a final expect any value meets (`contains` a blank string, `matches` a pattern
  matching the empty string or every one of a fixed set of unlike one-line texts, `read count` then
  `lt`) as `existence_only_expect`.
- Ten new reasons: `playwright_unavailable`, `placeholder_unset` (BLOCKED),
  `criterion_not_testable`, `side_effect_not_observable`, `exploration_budget` (NOT_VERIFIABLE, exit
  3), `already_frozen`, `plan_invalid`, `criteria_invalid`, `criteria_not_found`, `planner_failed`.
- Tests: `test-criteria.sh`, `test-plan-validate.sh`, `test-snapshot.sh` and `test-plan.sh` (the
  last two against real Chromium and a fixture app; the planner and `claude` are stubs).

## 0.2.0 — 2026-11-14

- Target safety. A committed `selvedge.json` (schema in `schemas/selvedge-config.schema.json`)
  lists the exact origins the checker's browser may reach; remote origins need `allow_remote`,
  any method other than GET, HEAD or OPTIONS to a remote origin needs `allow_remote_mutation`.
- `selvedge env check|init|approve|hook` (Node.js >= 18). `--base <ref>` reads the committed
  `<ref>:selvedge.json`, so a pull request cannot widen its own allowlist or change its hooks'
  command text. Env hooks run only under a user-scoped sha256 approval in
  `$HOME/.claude/selvedge/approvals.json`, recorded by `env approve` on a TTY, and never while any
  origin is remote. Limit: the approval pins the command text, not the files a hook runs, so a hook
  that calls a repo script runs that script as it is in the current checkout.
- The browser guard: a runner-owned forward proxy (`lib/runner/proxy.mjs`, exact-origin checks,
  one DNS lookup per remote connection with private, loopback, link-local, unique-local, multicast,
  unspecified or reserved results refused, including
  NAT64 and 6to4 addresses that embed a private IPv4, the validated address dialled) and a
  `context.route` second layer (`lib/runner/route-guard.mjs`, service workers blocked, Playwright
  injected by the caller) that also checks each redirect hop that keeps a non-read method (307/308,
  and 301/302 for any method but POST) when a remote origin is listed without
  `allow_remote_mutation`; a request it sends after the proxy is gone is `proxy_unavailable`. It
  follows such a hop itself only for redirect mode `follow` (an init script tags each non-read
  `fetch` with its redirect and credentials modes), dropping `Authorization` and cookies on a
  cross-origin hop as a browser would; for `manual`, `error` or an untagged `fetch` it never sends
  the hop and hands the page the redirect with its `Location` withheld. Every refusal is a named BLOCKED
  reason; the README's reasons table is checked against the code's list.
- Tests: `test-env.sh`, `test-proxy.sh` and `test-route-guard.sh`, the last against real Chromium
  from a pinned Playwright installed into a selvedge-owned cache (`tests/lib/playwright-cache.sh`).

## 0.1.0 — 2026-11-13

- First release: the plugin scaffold. Manifest, the `selvedge` CLI (`--version`, `install-cli`,
  which links the CLI into `~/.local/bin`), and the plugin's own release gate
  (`selvedge/tests/run.sh`, run by CI's `static` job).
- `docs/cli-discovery.md` records whether a plugin's `bin/` reaches `PATH`.
