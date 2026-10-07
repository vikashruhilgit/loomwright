## VERIFY_RESULT

The result block the QA Executor emits in **`--verify <run_dir>` mode** (reached through `/verify <ticket>`):
one block per verify run, summarising the run whose facts live in `.supervisor/verify/<run_id>/evidence.jsonl`
(§VERIFY_EVIDENCE). Unlike `VERIFY_EVIDENCE` this **is** an agent-emitted result block and **is hook-validated**:
the existing `SubagentStop (qa-executor)` command hook (`scripts/validate-qa-result.py`, hook command string
unchanged) accepts EITHER a `QA_RESULT` or a `VERIFY_RESULT` block — see the precedence rule below.
**Advisory only:** a `VERIFY_RESULT` never changes a `heal_decision`, never blocks a PR, never merges.

```yaml
VERIFY_RESULT:
  schema_version: 1
  run_id: string                       # required, non-empty — the run's id as minted by `verify-run.sh preflight` (`verify-<YYYYMMDDTHHMMSSZ>-<slug>`)
  run_dir: string                      # required, non-empty — `.supervisor/verify/<run_id>` (the store this block summarises)
  ticket_path: string                  # the requirement / brief that was verified
  status: enum [completed, aborted, paused]   # required — `paused` when the run stopped for a human sign-in (item 04); otherwise the same value `verify-run.sh finish --status` recorded on the run_end line
  pause_reason: enum [needs_auth, session_expired]|null   # nullable — non-null and one of the two enum values IFF status is `paused`; `null` (or ABSENT — treated identically) IFF status is `completed`|`aborted` (hook rule V7)
  counts:                              # required — COPIED VERBATIM from the counts row `verify-run.sh finish` prints; the agent NEVER tallies
    pass: integer
    fail: integer
    blocked: integer
    not_verifiable: integer
    total: integer                     # MUST equal pass + fail + blocked + not_verifiable (hook rule V6)
  artifacts_dir: string                # `<run_dir>/artifacts/` — screenshots / traces / response bodies, one subdir per ac_id
  summary: string                      # required, non-empty — one paragraph: what was walked, what PASSed, what could not be observed and why
  notes: string                        # optional — anything the human should read next (e.g. which NOT_VERIFIABLE needs a non-UI check)
  spec_sources:                        # OPTIONAL (token-economy 07, additive — no schema_version bump, the V7 precedent) — COPIED from the
                                        # `spec sources:` line `verify-helpers.sh summary-build` derives, same rule as `counts`
    replayed: integer                  # non-negative — distinct ac_ids with a spec_replay evidence line
    authored: integer                  # non-negative — ticket-scope ac_ids with NO spec_replay line and a latest verdict other than NOT_VERIFIABLE (a BLOCKED id still counts — honest limit)
    rederived: integer                 # non-negative — count of spec_rederived evidence lines
```

**`paused` is not a completion state.** A `status: paused` block is emitted by the qa-executor's VERIFY MODE the moment `verify-run.sh auth-check` exits `4` (a fresh run needing a human sign-in, `pause_reason: needs_auth`) or `verify-run.sh walk` exits `5` (a session that died mid-run, `pause_reason: session_expired`) — in BOTH cases `counts` still carries whatever the store had accumulated so far (a paused run never calls `finish`, so `counts` is the LAST derived `summary.md` row, not a fresh tally) and `artifacts_dir` / `summary` still describe the run through the point of the pause. A `/verify --resume <run_id>` that completes normally emits a second, ordinary `status: completed` block for the same `run_id` — `pause_reason` is never carried forward onto it.

**`counts` is derived, never written.** `verify-run.sh finish <run_dir>` appends the `run_end` line, rebuilds
`summary.md` through `verify-helpers.sh summary-build` (the store's ONLY reader), and prints that file's counts
row — `PASS: 2 · FAIL: 0 · BLOCKED: 0 · NOT_VERIFIABLE: 1 · total: 3`. The agent copies those five numbers into
`counts` and nothing else: the latest-per-`ac_id` rule, the `run_end`-carries-no-counts rule and the four-verdict
enum are all enforced upstream by the evidence validator, so a `VERIFY_RESULT` can only restate a total the store
computed. The hook's `total == pass + fail + blocked + not_verifiable` check exists to catch a hand-edited row.

**`spec_sources` is derived the same way (token-economy 07).** `summary-build` also derives a
`spec sources: replayed <n> · authored <n> · re-derived <n>` line in `summary.md` from the evidence
(`spec_replay` / `spec_rederived` events) — the agent copies those three numbers into `spec_sources`
verbatim, same rule as `counts`. `summary.md`'s per-AC ticket table also gains a `replayed` column
(`replayed` for a row with a `spec_replay` line, `—` otherwise) so a replayed spec's FAIL is visibly a
replay, never a silent authored FAIL.

**Where each verdict comes from.** `PASS` and `FAIL` are emitted ONLY by `verify-run.sh walk`'s ingest of the
Playwright reporter (an observed Then, or an observed contradiction — `FAIL` always carries `classification`,
`reason` and an artifact); `verify-run.sh verdict … NOT_VERIFIABLE|BLOCKED` records the two browser-less verdicts
and REFUSES `PASS` / `FAIL` as an argument (`pass_requires_observation` / `fail_requires_observation`, exit 2).
A `PASS` is therefore never a claim — it is always the reporter's `expected` status for an `[ACn]` spec.

**Validation (hook-validated, `scripts/validate-qa-result.py`, the SAME command as `QA_RESULT`):**

| rule | check |
|---|---|
| precedence | **`QA_RESULT` wins whenever it is present, regardless of position** — each block is located BY NAME (`find_last_block(text, 'QA_RESULT')` / `find_last_block(text, 'VERIFY_RESULT')`), never "whichever block occurs last"; a payload with a `QA_RESULT` block is validated exactly by the five `QA_RESULT` rules, and a `VERIFY_RESULT` block beside it is ignored |
| V1 | `schema_version` is the integer `1` |
| V2 | `run_id` and `run_dir` are present, non-empty strings |
| V3 | `summary` is present and non-empty |
| V4 | `status` ∈ `{completed, aborted, paused}` |
| V5 | `counts` is a mapping whose `pass` / `fail` / `blocked` / `not_verifiable` / `total` are all present non-negative integers |
| V6 | `counts.total == pass + fail + blocked + not_verifiable` |
| V7 | `pause_reason` must be non-null and one of `needs_auth`/`session_expired` IFF `status == paused`; it must be `null` IFF `status` is `completed`/`aborted` — either direction of mismatch (`paused` + null, non-`paused` + non-null, or `paused` + an unrecognized string) is rejected. An ABSENT key is treated identically to an explicit `null` (the `classification` null/absent convention of §VERIFY_EVIDENCE), so a pre-item-04 emitter that never sends the key keeps validating unchanged for every non-`paused` status |
| V8 | `spec_sources` (token-economy 07) is OPTIONAL — absent validates unchanged (the V7 additive precedent, no `schema_version` bump). Present: must be a mapping with EXACTLY the keys `replayed`/`authored`/`rederived`, each a non-negative integer |
| neither | no `QA_RESULT` and no `VERIFY_RESULT` block ⇒ the existing `missing QA_RESULT block` reason, unchanged |

The validator keeps its ALWAYS-exit-0 invariant (decision on stdout, in the documented command-hook shape — `{}` allow / `{"decision": "block", "reason": …}` block, per `result_block_parser.emit`); the
`hooks/hooks.json` command string is byte-unchanged. `scripts/test-result-validators.sh` §E2 provokes every rule.

**Frozen example** (fixed sample values per the `check-doc-currency.sh` header convention — not a current claim;
do not "fix" on a version bump):

```yaml
VERIFY_RESULT:
  schema_version: 1
  run_id: verify-20260914T100000Z-01-login
  run_dir: .supervisor/verify/verify-20260914T100000Z-01-login
  ticket_path: .supervisor/requirements/example/01-login.md
  status: completed
  counts: {pass: 2, fail: 0, blocked: 0, not_verifiable: 1, total: 3}
  artifacts_dir: .supervisor/verify/verify-20260914T100000Z-01-login/artifacts
  summary: Walked 3 acceptance criteria against http://localhost:3000 on feature/login. AC1 (login form renders) and AC2 (dashboard after valid credentials) PASS with screenshots at the Then; AC3 (no double-booking under 200 concurrent users) is NOT_VERIFIABLE — a load claim not observable through the UI.
  notes: AC3 needs a load-test harness, not a browser walkthrough.
```
(The markdown bullet form `## VERIFY_RESULT` / `- key: value` is accepted equally by the parser; a nested
`counts` in bullet form is written either as the flow mapping above or as plain indented `key: value` lines.)

### Specs and reporter ingest

How `verify-run.sh walk <run_dir> [--repo <dir>] [--base-url <url>]` turns the agent-authored specs into `ac` lines.
The specs live at `<run_dir>/specs/<ac_id>.spec.ts` (one per AC; `skills/verify-walkthrough/SKILL.md` owns the
derivation rules and the spec template). `walk` writes a per-run `<run_dir>/playwright.config.mjs` (`testDir`
= the specs dir, `outputDir` = `<run_dir>/test-results`, `reporter: [['json', {outputFile: '<run_dir>/report.json'}]]`,
`workers: 1`, `retries: 0`, `timeout: 30000`, `use: {baseURL, screenshot: 'on', trace: 'on', video: 'off'}` — `baseURL`
is the `--base-url` flag, else the contract's `base_url` through `read-verify.sh`), runs `npx --no-install playwright
test --config <that file>` FROM THE TARGET REPO (the project under test owns its Playwright install; the plugin never
installs one), and then reads `report.json`. **The run's exit status is ignored — the reporter file is the oracle**
(stdout / stderr are kept beside it as `playwright.stdout` / `playwright.stderr`).

**Title convention.** A spec is ingested iff its title starts with `[ACn]` (`^\[(AC[0-9]+)\]`); the captured id
must be an `ac_id` of `<run_dir>/acs.json` (a title naming an id the ticket does not have is named on stderr and
skipped — `ac_id_unknown`). The LAST result of the LAST test under that title decides (`retries: 0`, so normally
the only one). Two specs with the same `[ACn]` both append; the latest-per-`ac_id` rule of `summary-build` then
makes the later file's verdict the counted one.

**Reporter → verdict mapping** (the `status` of that last result; `classification` per the `ac` rules of
§VERIFY_EVIDENCE):

| reporter result | verdict | classification | `reason` |
|---|---|---|---|
| `passed` (test `expected`) | `PASS` | `null` | none |
| `failed` / `timedOut` / `interrupted` whose first error line names a navigation or connection failure — `net::ERR_`, `ECONNREFUSED`, a `page.goto` timeout | `BLOCKED` | `ENVIRONMENT_ISSUE` | the first line of `errors[0].message`, ANSI-stripped |
| any other `failed` / `timedOut` / `interrupted` | `FAIL` | `REAL_BUG` | the first line of `errors[0].message`, ANSI-stripped (`spec_<status>` if the reporter carried no message) |
| `skipped` | `BLOCKED` | `ENVIRONMENT_ISSUE` | `spec_skipped` |
| a spec with no result at all | `BLOCKED` | `ENVIRONMENT_ISSUE` | `spec_not_run` |

`steps` is the result's `steps[].title` list (Playwright only reports `test.step()` steps there; it may be empty).

**Attachment → artifact copy rule.** Every attachment of that result lands in `<run_dir>/artifacts/<ac_id>/` and
is recorded in `artifacts[]` RELATIVE to `<run_dir>/`: a `path` attachment (Playwright's own `screenshot` → `.png`,
`trace` → `trace.zip`, `error-context` → `.md`) is COPIED under its basename (an index prefix on a name collision);
a `body` attachment — base64 in the reporter, which is how the template's `testInfo.attach('page-body', {body:
await page.content(), contentType: 'text/html'})` and `response-<status>` arrive — is DECODED to `<name>.<ext>` with
the extension from `contentType`, matched by prefix in the order `walk_copy_attachments`'s `case` statement lists
them: `text/html*` → `.html`, `text/markdown*` → `.md`, any other `text/*` → `.txt`, `application/json*` → `.json`,
`image/png*` → `.png`, `application/zip*` → `.zip`, otherwise `.bin`. With `screenshot: 'on'` every ingested line
therefore carries at least one `.png`; a FAIL from the template additionally carries the `page-body.html` the seam
test's mutation control asserts on.

**BLOCKED rules that need no browser.** Before any config is written, `walk` runs `npx --no-install playwright
--version` from the repo; a non-zero status appends a `BLOCKED` / `ENVIRONMENT_ISSUE` / `playwright_unavailable`
line for every AC in `acs.json` that has NO `ac` line yet and exits **3** (the app was reachable; the harness was
not). A missing reporter file after the run (`reporter_missing: <first stderr line>`) is handled the same way,
exit 3. After ingest, every AC that still has neither a spec-derived line nor a `verdict`-recorded one gets
`BLOCKED` / `ENVIRONMENT_ISSUE` / `no_spec`; a run dir with no `*.spec.*` at all takes that path for every
undecided AC WITHOUT launching a browser (exit 0, no `report.json`). An AC already decided — a `NOT_VERIFIABLE`
recorded through `verdict`, a `BLOCKED` from an earlier pass — is never overwritten by a `no_spec` line. Every line,
in every branch, goes through `verify-helpers.sh evidence-append`; `walk` never opens `evidence.jsonl` itself.

---

