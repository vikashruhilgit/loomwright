---
name: verify-walkthrough
description: Protocol authority for `/verify <ticket>` and the QA Executor's `--verify <run_dir>` mode — AC extraction, AC → Playwright spec derivation, the four observation-derived verdicts (PASS / FAIL / BLOCKED / NOT_VERIFIABLE), the V7 mutation carve-out, evidence-per-AC, and budget. Read on demand at mode entry, deliberately not preloaded.
version: "1.1.0"
lastUpdated: "2026-09-15"
---

# Verify Walkthrough Protocol (`/verify` + qa-executor `--verify` mode)

**What this is.** The rules for walking ONE ticket's acceptance criteria through the RUNNING app and
recording one evidenced verdict per criterion. The mechanized steps live in `scripts/verify-run.sh`
(`acs` / `preflight` / `walk` / `verdict` / `finish`) and the store in `scripts/verify-helpers.sh`
(`evidence-append` is the ONLY writer of `<run_dir>/evidence.jsonl`); this skill owns the JUDGEMENT
those scripts cannot make — which ACs are observable, how an AC becomes a spec, and what each verdict
means. Schema authority: `docs/RESULT_SCHEMAS.md` §VERIFY_EVIDENCE (every recorded line) and
§VERIFY_RESULT (the block the agent emits, incl. the `### Specs and reporter ingest` contract).

**Advisory only (decision V6).** A verify run changes no `heal_decision`, blocks no PR, merges nothing.
Its output is `<run_dir>/summary.md` + a `VERIFY_RESULT` block for a human to read.

**Playwright-from-Bash only.** The walkthrough is `npx playwright test --reporter=json` driven by
`verify-run.sh walk` from the target repo — the same runner `agents/qa-executor.md` Phase 12 already
uses. No harness-specific browser tool, no desktop automation, no bespoke DSL: the only browser seam
is the project's own `@playwright/test`, which is what keeps this protocol portable across harnesses
(the command layer is the adapter; this skill and the scripts are the neutral core).

---

## 1. AC extraction

`verify-run.sh acs <ticket>` is the extractor — do not re-derive by hand. It prints
`{"ticket_kind": "requirement" | "brief", "acs": [{"ac_id": "AC1", "text": "…"}, …]}`:

- `ticket_kind` is decided by PATH (`.supervisor/requirements/` ⇒ `requirement`, `.supervisor/jobs/`
  ⇒ `brief`; anything else ⇒ exit 2 `ticket_unresolved`).
- The ACs are the top-level `- ` bullets under the first `## Acceptance Criteria` header
  (case-insensitive) up to the next `## `; a leading `[ ]` / `[x]` checkbox and a leading `ACn`
  label are stripped from `text`.
- **`ac_id` is the ORDINAL** — `AC<n>` by position in the file, 1-based — even when the ticket's own
  labels are sparse or missing. Every later surface (spec titles, `verdict`, `summary.md`) keys on it.

`preflight` writes the same object to `<run_dir>/acs.json`; the executor reads THAT file, never the
ticket again.

## 2. AC → spec derivation

ONE spec file per verifiable AC at `<run_dir>/specs/<ac_id>.spec.ts`, whose test title is
`[<ac_id>] <AC text>` — the `[ACn]` prefix is the ingest key (§VERIFY_RESULT "Title convention"); a
title without it is never counted, and one naming an id outside `acs.json` is skipped as
`ac_id_unknown`.

Derivation rules (authoring detail lives in `qa-test-patterns` and `playwright-e2e` — apply them, do
not restate them here):

| AC part | becomes |
|---|---|
| **Given** | navigation + preconditions inside the test (`page.goto('/…')` relative to the contract's `base_url`; `verify-env.sh seed` when the Given needs data the contract declares) |
| **When** | the interaction — role-based locators only (`getByRole`, `getByLabel`, `getByText`), never CSS chains |
| **Then** | a STRICT assertion on what the user would observe (`toHaveText`, `toBeVisible`, `toHaveURL`) — after ANY mutation (submit / create / update / delete) the Then is asserted on a **follow-up read**: the response page, or a fresh `page.goto` of the route that shows the effect, never on the pre-submit DOM |

A spec asserts exactly its AC's Then; do not fold several ACs into one file, and do not add
assertions the AC does not make (they turn an unrelated defect into a FAIL for the wrong criterion).

### Spec template (verbatim — this is the evidence contract `walk` ingests)

```ts
import { test, expect } from '@playwright/test';

// Attach the page body on failure and any non-2xx response body always — `walk` copies
// every attachment into <run_dir>/artifacts/<ac_id>/ and records it on the `ac` line.
test.afterEach(async ({ page }, testInfo) => {
  if (testInfo.status !== testInfo.expectedStatus) {
    await testInfo.attach('page-body', { body: await page.content(), contentType: 'text/html' });
  }
});

test('[AC2] Given the form page, when "hello" is submitted, then the echo shows "hello"', async ({ page }, testInfo) => {
  page.on('response', async (response) => {
    if (response.status() < 200 || response.status() >= 300) {
      await testInfo.attach(`response-${response.status()}`, { body: await response.text().catch(() => ''), contentType: 'text/plain' });
    }
  });
  await page.goto('/');                                   // Given
  await page.getByLabel('Value').fill('hello');           // When
  await page.getByRole('button', { name: 'Submit' }).click();
  await expect(page.locator('#echo')).toHaveText('hello'); // Then — observed on the follow-up page
});
```

`screenshot: 'on'` and `trace: 'on'` come from the per-run config `walk` generates; the template adds
only what Playwright does not capture by itself (the page body at the failed Then, non-2xx bodies).

## 3. The four verdicts

Exactly four, one line per AC, and WHERE each may come from is part of its meaning:

| verdict | meaning | `classification` | who may write it |
|---|---|---|---|
| `PASS` | every Then of the AC was **observed** by the spec — the reporter's `expected` status for the `[ACn]` test | `null` | **ONLY `verify-run.sh walk`'s ingest.** Never by hand: `verify-run.sh verdict … PASS` is refused (`pass_requires_observation`, exit 2) |
| `FAIL` | the When was reached and the Then was **observed to be contradicted** | `REAL_BUG` — with a non-empty `reason` (the first line of the assertion error) AND ≥1 artifact (screenshot + page body) — all three mandatory | ONLY `walk`'s ingest (`fail_requires_observation`) |
| `BLOCKED` | the When could not be reached — auth, environment, seed, harness (`playwright_unavailable`), no spec (`no_spec`), a connection / navigation error | `ENVIRONMENT_ISSUE` (default) + `reason` | `walk`'s ingest (navigation errors, skips, `no_spec`) or `verify-run.sh verdict <run_dir> <ac_id> BLOCKED --reason …` |
| `NOT_VERIFIABLE` | the Then is **not observable through the app** — load / concurrency / timing claims, internal-only effects, "no regression" statements with no UI surface | `null` — `reason` names WHY it is unobservable | `verify-run.sh verdict <run_dir> <ac_id> NOT_VERIFIABLE --reason …` (no browser launched) |

**The rule that makes the rest honest: a `PASS` is never emitted for an AC whose Then was not
observed.** If a Then is partly observable, the spec asserts the observable part and the verdict is
whatever the reporter says about THAT — the unobservable remainder is named in `VERIFY_RESULT.notes`,
not silently folded into a PASS. If nothing of the Then is observable, the verdict is
`NOT_VERIFIABLE`, not a PASS on a weaker proxy. `summary-build` counts the LATEST line per `ac_id`.

## 4. The mutation carve-out (decision V7)

`agents/qa-executor.md`'s Level-1 rule forbids submitting forms and clicking delete / logout / payment
buttons during discovery. In **`--verify` mode ONLY** that rule is relaxed exactly this far:

- Form submit, create, update and delete interactions that an AC's When names are ALLOWED — the
  walkthrough exists to observe their effect.
- ONLY after `assert-non-prod` PASSED **in this run**: the `env` line
  `{step: non_prod_assert, outcome: pass}` in `<run_dir>/evidence.jsonl` is the proof. `preflight`
  refuses to continue without it (exit 1, `non_prod_assert_failed`), and `verify-env.sh` re-gates every
  subcommand in-process, so a previous run's pass buys nothing.
- When the contract declares them, `verify-env.sh seed` runs BEFORE the walk and `verify-env.sh reset`
  AFTER it (both recorded as `env` lines), so a mutation never leaks into the next run.
- **Payment, logout and account-deletion actions stay forbidden everywhere** — in `--verify` mode too.
  An AC whose When is one of those is recorded `NOT_VERIFIABLE` with the reason
  `forbidden interaction (payment/logout/account-delete)`; it is never performed.

The carve-out is scoped to this skill: the Level-1 rule's text in the agent is unchanged and points
here; discovery / `/qa-executor` runs are not affected.

## 5. Evidence per AC

Every `ac` line carries what a reader needs to re-check the verdict without re-running:

| evidence | source | where |
|---|---|---|
| screenshot at the Then | the per-run config's `screenshot: 'on'` | `artifacts/<ac_id>/*.png` — ≥1 on every ingested line |
| trace | `trace: 'on'` | `artifacts/<ac_id>/trace.zip` |
| non-2xx response bodies | the template's `page.on('response')` attach | `artifacts/<ac_id>/response-<status>.txt` |
| page body on failure | the template's `test.afterEach` attach | `artifacts/<ac_id>/page-body.html` — the seam test's mutation control asserts on it |
| steps | the spec's `test.step()` titles | `steps[]` (may be empty) |
| reason | the first line of the reporter's `errors[0].message`, ANSI-stripped | `reason` on every non-PASS line |

Artifact paths are recorded RELATIVE to `<run_dir>/`; the store's validator rejects absolute or
`..`-bearing entries. `walk` never opens `evidence.jsonl` itself — every line goes through
`evidence-append`, which validates first and writes once.

## 6. Budget and checkpoints

- Reuse the QA Executor's **80-tool-call default**; `--verify` runs no discovery, so the budget is
  spent on spec authoring (about 2–3 calls per AC) plus the fixed shell-outs (`start`, `seed`,
  `auth-probe`, `walk`, `reset`, `stop`, `finish`).
- **The checkpoint IS the evidence already written.** A run that exhausts its budget or aborts mid-way
  still ends with `verify-run.sh finish <run_dir> --status aborted`: the `ac` lines recorded so far are
  counted, every AC without a line is left for the human to see as absent in `summary.md`, and
  `VERIFY_RESULT.counts` copies the printed counts row exactly. Nothing is re-derived from memory.
- Zone rule: on entering the RED zone (92%+), stop authoring, run `walk` on the specs that exist,
  then `finish --status aborted`.

## 7. Derivation fixtures

Worked examples of the judgement in §2–§3 — the seam test pins the concurrency row.

### Derivation fixtures

| AC text | spec? | expected verdict class | why |
|---|---|---|---|
| Given the form page, when it loads, then a Value field and a Submit button are visible | `[AC1]` spec: `goto('/')`, `getByLabel('Value')` + `getByRole('button', {name: 'Submit'})` `toBeVisible()` | `PASS` / `FAIL` by observation | a rendered-state Then, directly observable |
| Given the form page, when `hello` is submitted, then the page echoes `hello` | `[AC2]` spec: fill, submit, `expect(locator('#echo')).toHaveText('hello')` on the follow-up page | `PASS` / `FAIL` by observation (the mutation control flips it to `FAIL` + `REAL_BUG` when the app renders `wrong`) | a form-echo Then — the carve-out permits the submit once `non_prod_assert` passed |
| Given 200 bookings, when submitted under 200 concurrent users, then no double-booking occurs | none | `NOT_VERIFIABLE` — `verdict … NOT_VERIFIABLE --reason "load/concurrency claim not observable through the UI"` | a concurrency / load claim has no single-browser observation; never a PASS on a one-user proxy |
| Given a saved order, when it is confirmed, then the audit table gains a row | none | `NOT_VERIFIABLE` — reason `internal-only effect; no UI surface shows the audit row` | the effect is not observable through the app; a database check is not a walkthrough |
| Given a signed-in admin, when they open `/admin/users`, then the user list renders | `[ACn]` spec, authored once `verify-run.sh auth-check` confirms an authenticated session (exit 0) | `PASS`/`FAIL` by observation like any other AC — a run with no session PAUSES the WHOLE run first (`status: paused, pause_reason: needs_auth`; §8 below), never a per-AC BLOCKED anonymous | authentication is gated at the RUN level before spec authoring, not per AC — a login redirect is never observed as a FAIL of one criterion |
| Given a cart, when checkout is paid, then the receipt page shows the order number | none | `NOT_VERIFIABLE` — reason `forbidden interaction (payment/logout/account-delete)` | payment stays forbidden everywhere (§4) |
| Given the dashboard, when the browser is offline, then a cached page renders within 100 ms | `[ACn]` spec for the offline render only | `PASS` / `FAIL` by observation on the render; the `100 ms` claim named in `notes` | the timing bound is not a reliable single-run observation; the observable half is still asserted |

---

## 8. Auth pause and resume

A run never continues on an anonymous or expired session; it PAUSES instead — a named,
resumable stop, never a silent BLOCKED-forever or an anonymous continue.

- **Needs auth (before any spec is authored).** `verify-run.sh auth-check <run_dir> --repo <dir>`
  runs right after `seed`. `auth.method: none` ⇒ no-op (no evidence line, no probe call at all —
  an app with no auth concept has nothing to check). Otherwise it probes the target: authenticated
  ⇒ one `{event:auth, state:authenticated}` line, continue to spec authoring; anything else
  (no/invalid storage state, unreachable probe) ⇒ `{event:auth, state:needs_auth}` then
  `verify-run.sh pause <run_dir> --reason needs_auth` — the run stops with NO spec authored, NO
  `walk`, NO `finish`; the agent emits `VERIFY_RESULT` `status: paused, pause_reason: needs_auth`.
- **Session expired (mid-walk).** `walk`'s per-spec ingest additionally scans attachments for a
  `response-40[13]` signal; on a hit it takes the MINIMUM affected AC ordinal `N` (parsed from each
  spec's `[ACn]` title, never file-discovery order), forces `AC<N>` to `BLOCKED` /
  `ENVIRONMENT_ISSUE` / `session_expired` (overriding whatever the spec itself reported) and every
  `AC<k>` with `k > N` to `BLOCKED` / `ENVIRONMENT_ISSUE` / `run_paused_session_expired` — ACs
  before `N` keep their real verdict. Exactly one `{event:auth, state:expired}` line and one
  `pause --reason session_expired` line are appended (not one pair per forced AC); `walk` exits `5`
  instead of its normal `0`/`3`. The agent skips `finish` and emits `VERIFY_RESULT`
  `status: paused, pause_reason: session_expired`.
- **`pause` is written in exactly ONE place** — `verify-run.sh pause <run_dir> --reason
  <needs_auth|session_expired>` — called by both paths above, never constructed inline.
- **Resume.** `/verify --resume <run_id>` re-runs `auth-check`; a second `needs_auth` re-prints the
  same sign-in instruction (no new run dir, no `resume` line); success appends
  `{event:resume, reason:human_signed_in}` and re-spawns the executor at the SAME run dir. The
  executor detects the resume from the store itself (a prior passing `env:{step:start}` line) and
  derives its position from `verify-helpers.sh first-unverdicted <run_dir>` — never re-verdicting an
  `ac_id` that already has a line, never re-running `start`/`seed`.
- **The plugin never types, stores, or logs a credential.** It only ever reads the storage-state
  file a human's own `playwright codegen --save-storage=…` run wrote; `commands/verify.md` is the
  only surface that ever prints the sign-in instruction (the executor is a subagent with no
  `AskUserQuestion`).

## Checklist before `finish`

- [ ] every `ac_id` in `acs.json` has EITHER a `[ACn]` spec under `<run_dir>/specs/` OR a `verdict … NOT_VERIFIABLE|BLOCKED` line — none is left to `no_spec` by accident
- [ ] no spec asserts more than its AC's Then; every mutating When is followed by a follow-up read
- [ ] every spec carries the `test.afterEach` page-body attach and the non-2xx response attach
- [ ] no spec performs a payment / logout / account-delete action
- [ ] `seed` ran before and `reset` after the walk when the contract declares them
- [ ] `VERIFY_RESULT.counts` is the printed counts row, copied — never tallied
- [ ] a paused run (`needs_auth` or `session_expired`) never calls `finish`; `counts` comes from `summary.md`'s current row instead
