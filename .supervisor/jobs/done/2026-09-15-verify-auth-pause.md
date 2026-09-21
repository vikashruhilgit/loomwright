# Supervisor Job: Auth pause-for-human-sign-in, save session, resume (`/verify` auth handling)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — version-free by design; plugin.json is 15.76.1)
- **Git:** clean, branch: main @ 16bf327 == origin/main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (several idle `.claude/worktrees/*` desktop/agent worktrees present — not ours, do not touch)
- **Source requirement:** .supervisor/requirements/verify-walkthrough/04-verify-auth-pause.md
- **Base commit:** 16bf32733a80536b62166c1dea8a5cc257fdf805

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Same substrate as items 01–03: bash 3.2 + `jq` in `scripts/verify-run.sh` / `scripts/verify-helpers.sh` / `scripts/verify-env.sh`, python3 stdlib for the fixture app and `validate-qa-result.py`. No new runtime. |
| 2 | Dependency Availability | GO | `verify-env.sh auth-probe` already exists and is called today (`agents/qa-executor.md:195`); the `VERIFY_EVIDENCE.auth.state` enum already carries `needs_auth` and `expired` (`docs/RESULT_SCHEMAS.md:2608`) and the `pause`/`resume` events are already schema'd (`:2624-2627`) and already accepted by `validate-verify-evidence.py` / rendered by `summary_build` (`verify-helpers.sh:169-170`). This item wires orchestration around already-shipped primitives — no new external dependency. |
| 3 | Architecture Fit | GO | Applies V1 (no 15th agent — qa-executor's existing `--verify` mode grows), V5 (own store — reuses item 02's evidence-append/summary-build), V6 (advisory — pausing is a `VERIFY_RESULT.status` value, never a gate), V7 (no new mutation carve-out needed — auth pause happens *before* any mutating When), V8 (the plugin still never sees a credential — it only reads the storage-state file Playwright wrote). "Tested code IS the executed code": all new logic lands in `verify-run.sh` subcommands, never in agent prose. |
| 4 | Scope vs Supervisor Capability | GO (split) | ~9 modify (`verify-run.sh`, `verify-helpers.sh`, `verify-fixture-app.py`, `docs/RESULT_SCHEMAS.md`, `validate-qa-result.py`, `scripts/check-contract-parity.sh`, `commands/verify.md`, `agents/qa-executor.md`, `skills/verify-walkthrough/SKILL.md`) + 4 doc/count modify (`CHANGELOG.md`, `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `docs/prompt-token-budgets.json` only on a measured breach) + 2 test-file modify (`test-verify-walkthrough.sh`, `scripts/test-result-validators.sh`), 0 create. This crosses the 800-changed-line `context-bound` threshold once the fixture app, schema, validator, two agent-prose surfaces and their tests are all touched — split reason `context-bound` → 2 sequential subtasks: (1) the deterministic substrate (script + schema + validator + fixture + tests), (2) the prompt surfaces that consume it (command, agent, skill, docs/counts). |
| 5 | Hard Blockers | GO | No migrations, no credentials (V8 unchanged — the new code paths only ever read `auth.storage_state_path`, never a password), no new agent (V1), no hook-row change (`hooks.json` command strings untouched — the validator grows a branch on an existing schema, hook count stays 36), no `state.md` write, no gate/`heal_decision`/merge-path change (VERIFY_RESULT.status stays advisory). Root `scripts/check-contract-parity.sh` gets ONE ENUMS-row edit (add `paused` alongside the existing `completed,aborted`) — Subtask 2, together with the template that emits the new token. |

**Overall Verdict:** GO (split — context-bound, 2 sequential subtasks)

## Task
**Goal:** Ship the auth-pause/resume half of `/verify`: when a `--verify` run needs an authenticated session it does not have, it appends a named `pause` evidence line and returns `VERIFY_RESULT.status: paused` (never an anonymous continue, never a silent BLOCKED-and-stop) instead of today's unconditional `BLOCKED --reason "auth-probe: anonymous"` per AC; the command layer (`commands/verify.md`, the only layer that can address a human — qa-executor is a subagent with no `AskUserQuestion`) prints the ONE exact `playwright codegen --save-storage=...` instruction; `/verify --resume <run_id>` re-probes, and on success appends a `resume` line and continues at the first AC with no verdict line yet (never re-verdicting one that already ran); a session that dies mid-walk (a 401/403 response observed on any AC's page) is detected from the same evidence the specs already capture, forces that AC and every AC after it (in ticket order) to `BLOCKED`/`ENVIRONMENT_ISSUE`/`session_expired` — overriding whatever Playwright itself reported for them — and pauses the run the same way. The plugin never types, stores, or logs a credential at any point; it only ever reads the file Playwright's own `codegen` wrote.

**Problem Statement:**
Item 03 shipped `/verify` with a resigned-to-anonymous auth story: `agents/qa-executor.md:195` calls `auth-probe` unconditionally (even when the app has no auth at all — `auth.method: none` — which makes `verify-env.sh do_auth_probe` print the literal string `anonymous` with no request made, so today's code records a spurious `auth: anonymous` line for auth-less apps too), and `:204` turns any AC that needed a session into a permanent `BLOCKED --reason "auth-probe: anonymous"` with no path forward. The owner's ask explicitly named this gap ("ask and save if any login is required") and the `verify-walkthrough` skill itself flags it at `skills/verify-walkthrough/SKILL.md:171` — *"item 04 adds the pause-for-auth"*. Without this item every authenticated ticket either reports false BLOCKED verdicts forever or requires re-running `/verify` from scratch after every manual sign-in, re-walking ACs that already passed. The primitives are already shipped (item 02's `pause`/`resume` events, the `needs_auth`/`expired` states in `VERIFY_EVIDENCE.auth.state`) — nothing yet emits or reacts to them.
Success looks like: a `--verify` run on an app requiring `storage_state` auth that has none pauses immediately (before authoring any spec) with a printed sign-in instruction naming the real path and URL; after the human signs in and runs `/verify --resume <run_id>`, the run picks up exactly where it left off; and a session that expires mid-walk is caught from evidence the app itself produced (a real 401/403), never inferred, never silently swallowed into a wrong PASS or a wrong FAIL.

## Acceptance Criteria
- [ ] AC1 Given `.agent/verify.json` with `auth.method: "storage_state"` and no file at `auth.storage_state_path` (or a file whose cookie the target's `probe_path` rejects), when `verify-run.sh auth-check <run_dir> --repo <dir>` runs, then it (a) appends exactly one `{event: auth, state: needs_auth}` line, (b) appends exactly one `{event: pause, reason: needs_auth}` line via the new `verify-run.sh pause <run_dir> --reason needs_auth` subcommand (the ONE place that ever writes a `pause` line — auth-check and the `walk` expiry path in AC5 both call it, never appending `{event: pause, ...}` inline themselves), (c) rebuilds `summary.md`, and (d) exits `4` (a new, distinct exit code — never reused from `preflight`'s `1`/`2`/`3`). No `ac` line is written and no spec is authored as a result of this call.
- [ ] AC2 Given `.agent/verify.json` with `auth.method: "none"`, when `auth-check` runs, then it makes **zero** calls to `verify-env.sh auth-probe` (asserted via a stub `verify-env.sh` call-log, exactly like `test-verify-seam.sh`'s pattern), appends **no** evidence line of any kind, and exits `0` — a deliberate behavior change from today's `agents/qa-executor.md:195`, which calls `auth-probe` unconditionally and would record a spurious `auth: anonymous` line for an app with no auth concept at all (`verify-env.sh do_auth_probe`'s own `auth.method is none` branch prints the literal string `anonymous` — never `authenticated` — so today's step 5 cannot distinguish "no auth" from "needs auth" and item 04 must read `auth.method` itself before ever calling probe).
- [ ] AC3 Given `.agent/verify.json` with `auth.method: "storage_state"` and a storage-state file whose cookie the target's `probe_path` accepts, when `auth-check` runs, then it appends exactly one `{event: auth, state: authenticated}` line and exits `0` — no `pause` line, no `resume` line.
- [ ] AC4 Given a fresh `--verify` run against an app requiring auth with no session, when `agents/qa-executor.md`'s VERIFY MODE runs to the point where `auth-check` (AC1) signals a pause, then the executor does **not** author any spec, does **not** call `verify-run.sh walk`, does **not** call `verify-run.sh finish`, still runs `verify-env.sh stop` for cleanup (the app was started at step 3), and emits `VERIFY_RESULT` with `status: paused`, `pause_reason: needs_auth` (the schema addition in AC7) instead of `status: completed|aborted` — `commands/verify.md` then prints exactly ONE instruction line containing `npx playwright codegen --save-storage=<the contract's real storage_state_path> <the contract's real base_url>`, followed by `sign in, close the window`, followed by `/verify --resume <run_id>`; the plugin process never opens a browser itself and never echoes anything it read from the storage-state file.
- [ ] AC5 (**mutation control — proves expiry comes from an observed response, not an inference**) Given the fixture app (extended per AC9) serving a page whose one authenticated route answers `401` once its session cookie is invalidated mid-test, a 3-AC fixture ticket whose specs are placed in ordinal order (AC1, AC2, AC3), and a spec for AC2 that triggers the 401 (the existing `page.on('response')` non-2xx attach from item 03 names the attachment `response-401`), when `verify-run.sh walk <run_dir>` ingests the batch, then: AC1 (which ran before the 401 and never saw one) keeps whatever verdict Playwright reported for it; AC2 is forced to `verdict: BLOCKED, classification: ENVIRONMENT_ISSUE, reason: session_expired` **regardless of Playwright's own result** for AC2 (assert this by making AC2's own assertions PASS despite the 401 — the override must win over a spec that happens to still succeed); AC3 is forced to `verdict: BLOCKED, classification: ENVIRONMENT_ISSUE, reason: run_paused_session_expired` even though AC3's spec never ran or ran clean; exactly one `{event: auth, state: expired}` line and one `{event: pause, reason: session_expired}` line are appended (not one pair per AC); `walk` exits `5` (distinct from the existing `3` = harness-unavailable). The AC-ordinal used for "before/after" is the numeric value parsed from each spec's `[ACn]` title, never Playwright's file-discovery order (a 10-AC ticket must not let `AC10` sort before `AC2`). The test proves the positive case first — the SAME specs against a healthy (never-expiring) fixture must show all three as their real verdicts with no `expired`/`pause` lines — so a stub `walk` that always pauses cannot pass this AC.
- [ ] AC6 Given a run dir whose `evidence.jsonl` already has `ac` lines for AC1 and AC2 (either verdict) but none for AC3+, when `verify-helpers.sh first-unverdicted <run_dir>` runs, then it prints `AC3` on stdout and exits `0`; given every `ac_id` in `acs.json` already has an `ac` line, it prints nothing and exits `0` (a distinct, documented "nothing left" signal — never a nonzero exit, since "fully verdicted" is a normal state, not an error).
- [ ] AC7 Given `docs/RESULT_SCHEMAS.md` §VERIFY_RESULT, when `status` gains the `paused` enum value and a new `pause_reason: string|null` field (`REQUIRED KEY, NULLABLE VALUE` — non-null and one of `needs_auth`|`session_expired` iff `status == paused`; `null` iff `status` is `completed`|`aborted`), then `validate-qa-result.py`'s VERIFY_RESULT branch enforces the pairing (paused+null pause_reason ⇒ invalid; non-paused+non-null pause_reason ⇒ invalid; paused+an unrecognized `pause_reason` string ⇒ invalid) and `scripts/test-result-validators.sh` §E2 grows ≥4 new cases (valid paused+needs_auth, valid paused+session_expired, paused+null invalid, completed+non-null-pause_reason invalid) without touching any existing E-block case; root `scripts/check-contract-parity.sh`'s `agents/qa-executor.md|status|...` ENUMS row gains `paused` alongside the existing `completed,aborted`, and its VERIFY_RESULT MANIFEST row's field list gains `pause_reason`; the gate is green.
- [ ] AC8 Given `agents/qa-executor.md`'s VERIFY MODE steps, when this item lands, then: step 5 (`agents/qa-executor.md:195`) is replaced by a call to `verify-run.sh auth-check <run_dir> --repo <dir>`, branching on its exit code (`0` ⇒ continue to spec authoring; `4` ⇒ skip spec authoring/walk/finish, run `verify-env.sh stop`, emit `VERIFY_RESULT` paused per AC4); the old `:204` per-AC `BLOCKED --reason "auth-probe: anonymous"` fallback is removed (that case can no longer occur — an anonymous probe now pauses the whole run at step 5, never reaches per-AC verdicting); a resumed invocation (the run dir already has a `run_start` line AND a prior passing `env:{step:start}` line) skips re-running `verify-env.sh start`/`seed` and instead re-runs ONLY `auth-check`, then authors specs for `verify-helpers.sh first-unverdicted`'s remaining AC set (AC6) rather than every AC in `acs.json`; a `walk` exit of `5` (AC5) skips `finish` and emits `VERIFY_RESULT` paused with `pause_reason: session_expired` exactly like the AC4 shape. `grep -cE 'Claude_Browser|computer-use|mcp__' agents/qa-executor.md commands/verify.md skills/verify-walkthrough/SKILL.md scripts/verify-run.sh` stays `0`; `bash scripts/check-token-budget.sh` is green (raise `docs/prompt-token-budgets.json` + the mirrored `ARCHITECTURE_CONTRACTS.md` row together, with a measured figure, ONLY on a breach).
- [ ] AC9 Given `scripts/verify-fixture-app.py`, when `/login` (`POST`, sets a session cookie on any body), `/probe` (`200` with a valid cookie, `302` to `/login` without one or with an invalid one), and `/protected` (same auth check as `/probe`, renders a page whose one interactive element requires the session) are added, then the existing `/`, `/submit`, `/health` routes and the `--broken` flag (item 03's echo mutation, unrelated to auth) are byte-behavior-unchanged (item 03's AC3/AC4 arms in `test-verify-walkthrough.sh` still pass unmodified), and a NEW `--auth-expire-after N` flag invalidates the session cookie after the Nth request to `/protected` (used by AC5 to make a live session die mid-walk without any code-level fakery).
- [ ] AC10 Given `commands/verify.md`, when `--resume <run_id>` is added, then: it resolves `run_dir=.supervisor/verify/<run_id>` and errors if the dir does not exist (never silently starting a new run under the same id); it runs `verify-run.sh auth-check <run_dir> --repo <dir>` — exit `4` ⇒ print the SAME codegen instruction as AC4 verbatim (no new run dir, no `resume` line appended) and stop; exit `0` ⇒ append `{event: resume, reason: human_signed_in}` via `verify-helpers.sh evidence-append`, then `Task`-spawn `loomwright:qa-executor --verify <run_dir>` exactly as a fresh run (no special resume flag needed on the agent boundary — AC8's resume-detection lives inside the agent, keyed off the run dir's own contents). Separately, `commands/verify.md`'s preflight-success path now checks whether `auth.storage_state_path` (when `auth.method: storage_state`) is git-ignored in the target repo (`git check-ignore -q <path>`) and, if not, prints ONE warning naming the path (it contains session cookies) — this check runs once, on the first pause (AC4), not on every resume.

## Outcomes Rubric
- Needs-auth is a named pause, never an anonymous continue
- Human signs in; the plugin only reads the file Playwright wrote
- Expiry mid-run detected and recorded as BLOCKED, not FAIL
- Resume position derived from evidence lines
- No credential ever touches the plugin's files or logs

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Configuration
- **Mode:** sequential (Batch 2 is BLOCKED by Batch 1 -- no genuine parallelism to offer)
- **Recommended workers:** 1
- **Split reason:** context-bound (Feasibility row 4 -- ~9 modify + 4 doc/count + 2 test-file across script/schema/validator/fixture/two agent-prose surfaces exceeds the single-subtask default)
- **Base Branch:** main

## Risk Assessment

| # | Risk | Severity | Mitigation |
|---|------|----------|------------|
| 1 | `walk`'s expiry-override (AC5) forces BLOCKED onto every AC after a detected 401/403 -- a false-positive 401 from an unrelated app route (not actually a session-expiry signal) would wrongly cascade BLOCKED across the rest of the ticket's ACs. | MEDIUM | AC5's mutation control requires the positive case (a healthy, non-expiring fixture run) to show all real verdicts with zero `expired`/`pause` lines, so the override path is proven to fire only on a genuine repeated-401 signal, never unconditionally; scoped to `response-40[13]` attachments only (never a bare non-2xx). |
| 2 | Resume-detection (AC8) skips `verify-env.sh start`/`seed` when it sees a prior passing `env:{step:start}` line -- a partially-written or truncated `evidence.jsonl` (e.g. a crash between `run_start` and the `start` line) could misread as "already started" and skip a seed step that never actually ran. | LOW | `evidence.jsonl` is append-only, validated line-by-line on write (item 02); a truncated/malformed line fails the JSONL parse and the guard degrades to the safe default (treat as fresh -- re-run `start`/`seed`), never the unsafe one. Subtask 2's implementation notes call this out explicitly for the worker. |
| 3 | The storage-state gitignore warning (AC10) is a one-shot check that fires only on the FIRST pause, not on every `--resume` -- a later regression (someone un-ignores the path between pause and resume) would go unwarned. | LOW | Accepted: the storage-state file's existence is itself proof a human already ran `codegen` once; a second warning on every resume would be noise for a rare edge case, and V8's actual invariant (the plugin never reads/logs credentials) is unaffected by this gap -- only the advisory hygiene warning is scoped narrower. |

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-09-15-verify-auth-pause.md

## Skill References
- `skills/quality-checklist/SKILL.md` -- pre/post-task quality gates (both subtasks)
- `skills/error-handling/SKILL.md` -- Subtask 1's new exit-code branches (4, 5) and fail-safe/fail-closed posture in `verify-run.sh`
- `skills/playwright-e2e/SKILL.md` -- Subtask 1's fixture-app auth routes and the AC5 mutation-control spec
- `skills/qa-test-patterns/SKILL.md` -- Subtask 2's `agents/qa-executor.md` resume-detection and pause-emission wiring

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | `verify-run.sh` (`auth-check` / `pause`, `walk`'s expiry-override ingest) + `verify-helpers.sh first-unverdicted` + fixture-app auth routes + `## VERIFY_RESULT` schema (paused/pause_reason) + `validate-qa-result.py` branch + seam test arms (incl. AC5's mutation control) | AC1, AC2, AC3, AC5, AC6, AC7, AC9 | 7 modify, 0 create | `skills/quality-checklist/SKILL.md`, `skills/error-handling/SKILL.md`, `skills/playwright-e2e/SKILL.md` | LAUNCHABLE |
| 2 | `commands/verify.md` (`--resume`, gitignore warning) + `agents/qa-executor.md` auth-check/resume wiring + `skills/verify-walkthrough/SKILL.md` (resolve the item-04 forward reference, document pause/resume) + contract-parity rows + token-budget check + prompt-surface seam-test arms + docs/counts/release | AC4, AC8, AC10 | 11 modify (2 of them — the budget JSON + its mirror row — only on a breach), 0 create | `skills/qa-test-patterns/SKILL.md`, `skills/quality-checklist/SKILL.md` | BLOCKED (by #1) |

### Subtask Contracts

```yaml
# Subtask 1 — deterministic substrate + schema + validator + fixture + tests (LAUNCHABLE)
provides:
  - {kind: "symbol", path: "loomwright/scripts/verify-run.sh", name: "auth-check)"}
  - {kind: "symbol", path: "loomwright/scripts/verify-run.sh", name: "pause)"}
  - {kind: "symbol", path: "loomwright/scripts/verify-helpers.sh", name: "first_unverdicted()"}
  - {kind: "symbol", path: "loomwright/scripts/verify-fixture-app.py", name: "--auth-expire-after"}
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "pause_reason"}
  - {kind: "symbol", path: "loomwright/scripts/validate-qa-result.py", name: "pause_reason"}
  - {kind: "file", path: "loomwright/scripts/test-verify-walkthrough.sh"}
requires: []
lanes:
  - "loomwright/scripts/verify-run.sh"
  - "loomwright/scripts/verify-helpers.sh"
  - "loomwright/scripts/verify-fixture-app.py"
  - "loomwright/scripts/test-verify-walkthrough.sh"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/scripts/validate-qa-result.py"
  - "loomwright/scripts/test-result-validators.sh"
external_requires:
  - "jq, python3 (already hard requirements of verify-helpers.sh / the validators); the persistent Playwright test cache item 03 already set up ($LOOMWRIGHT_VERIFY_TEST_CACHE)"

# Subtask 2 — prompt surfaces + docs/counts (BLOCKED by #1)
provides:
  - {kind: "symbol", path: "loomwright/commands/verify.md", name: "--resume"}
  - {kind: "symbol", path: "loomwright/agents/qa-executor.md", name: "auth-check"}
  - {kind: "symbol", path: "loomwright/skills/verify-walkthrough/SKILL.md", name: "pause"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/verify-run.sh", name: "auth-check)"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/verify-run.sh", name: "pause)"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/verify-helpers.sh", name: "first_unverdicted()"}
  - {from: "1", kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "pause_reason"}
  - {from: "1", kind: "file", path: "loomwright/scripts/test-verify-walkthrough.sh"}
lanes:
  - "loomwright/commands/verify.md"
  - "loomwright/agents/qa-executor.md"
  - "loomwright/skills/verify-walkthrough/SKILL.md"
  - "loomwright/skills/SKILLS_INDEX.md"
  - "loomwright/scripts/test-verify-walkthrough.sh"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "scripts/check-contract-parity.sh"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
external_requires: []
```

**Shared-file notes:** `verify-run.sh` and `test-verify-walkthrough.sh` are shared by the two sequentially-ordered subtasks (reachable in the `requires` DAG), so the sharing is legal — Subtask 2 does not touch either file's Subtask-1 content, it only reads/exercises it. Subtask 1 must NOT emit the literal `auth-check)`/`pause)` dispatch-case bodies in a way that collides with any future subcommand name; keep the usage header's existing `walk`/`verdict`/`finish` entries untouched and simply insert the two new lines alphabetically-adjacent to the dispatch `case` block at `scripts/verify-run.sh:595-599`.

## Implementation notes (per subtask — the precedent to copy, not re-invent)

**Subtask 1**
- `verify-run.sh auth-check <run_dir> [--repo <dir>]`: read the contract via `"$HERE/read-verify.sh" --repo <dir>` (capture stdout; if empty, this subcommand is only ever reached after `preflight` already proved the contract exists, so treat an empty read defensively as `method: none`-equivalent — diag + exit 0, never crash). `method="$(printf '%s' "$contract" | jq -r '.auth.method')"`. `method == "none"` ⇒ exit 0, **no evidence line, no `verify-env.sh` call at all** (AC2 — this is the behavior change from today's unconditional probe call). Else call `"$HERE/verify-env.sh" auth-probe --repo <dir>`, capturing stdout and `$?` in two separate statements (memory `exit-status-lost-across-subshell-and-or-true`) — `verify-env.sh`'s own `do_auth_probe` already returns non-zero for `storage_state_absent`/`auth_probe_unreachable`/`auth_probe_unexpected:<code>`, so auth-check's branch is simply: stdout `authenticated` AND rc 0 ⇒ append `{event:auth, state:authenticated}` via `evidence-append`, exit 0 (AC3); anything else (stdout `anonymous`, or any nonzero rc) ⇒ append `{event:auth, state:needs_auth}`, then call `"$HERE/verify-run.sh" pause "$run_dir" --reason needs_auth` (below), exit 4 (AC1).
- `verify-run.sh pause <run_dir> --reason <needs_auth|session_expired>`: appends `{event:pause, reason:<reason>}` via `evidence-append`, calls `summary_build` (rebuild for visibility), exits 0. This is the ONLY place a `pause` line is ever written — both `auth-check` (AC1) and `walk`'s expiry path (AC5) call it rather than constructing the line themselves.
- `verify-run.sh walk` expiry override (extends the existing per-spec ingest loop at `scripts/verify-run.sh` around line 526): after computing each spec's normal verdict, additionally scan its ingested `attachments[]` for a name matching `^response-40[13]`. Collect the set of AC ordinals (parsed as the integer in each spec's `[ACn]` title — never file order) that show this signal; if the set is non-empty, take the MINIMUM such ordinal `N`: force `acs.json`'s `AC<N>` to `{verdict: BLOCKED, classification: ENVIRONMENT_ISSUE, reason: session_expired}` (discarding whatever verdict the normal mapping computed for it) and force every `AC<k>` with `k > N` to `{verdict: BLOCKED, classification: ENVIRONMENT_ISSUE, reason: run_paused_session_expired}` regardless of their own Playwright result or presence; ACs with `k < N` keep their normally-computed verdict untouched. Append exactly one `{event:auth, state:expired}` line and call `pause <run_dir> --reason session_expired` exactly once (not per forced AC). `walk` then exits `5` instead of its normal exit code.
- `verify-helpers.sh first_unverdicted <run_dir>`: read `<run_dir>/acs.json` for the ordered `ac_id` list; read `evidence.jsonl`, collect the SET of `ac_id`s that have at least one `{event:ac}` line (existence, not "latest" — any prior line means it ran); print the first `ac_id` from the ordered list that is NOT in that set; print nothing if all are covered. Exit 0 in both cases (mirror the `latest_by` jq idiom already in `summary_build`, `verify-helpers.sh:110-189`).
- `verify-fixture-app.py`: add `/login` (`POST`, any body ⇒ `Set-Cookie: session=<random-or-fixed-token>`, redirect or 200), `/probe` and `/protected` (both: valid `session` cookie ⇒ 200, else 302 to `/login`), and `--auth-expire-after N` (a module-level counter incremented on each `/protected` hit; after the Nth, the cookie is treated as invalid — subsequent requests 401 rather than 302, matching AC5's "the app itself answers 401" requirement, distinct from the anonymous-redirect 302 case). Keep `/`, `/submit`, `/health`, `--broken` byte-unchanged (AC9).
- `docs/RESULT_SCHEMAS.md` §VERIFY_RESULT: add `paused` to the `status` enum and a new `pause_reason: string|null` field per the AC7 pairing rule, following the file's existing frozen-example-value convention; add a dated `### Version History` bullet.
- `validate-qa-result.py`: extend the VERIFY_RESULT branch with the AC7 pairing check; keep the always-exit-0 invariant and the five untouched QA_RESULT rules.
- `test-verify-walkthrough.sh`: new arms for AC1/AC2/AC3 (auth-check via the stub-`verify-env.sh` call-log pattern already used for `preflight`), AC6 (`first_unverdicted`), and AC5's full mutation control (positive gate first — prove the fixture's `--auth-expire-after` really produces a 401 on request N+1, else `UNPROVEN`; then run `walk` and assert the AC-ordinal forcing rule, including a 10+-AC fixture to prove ordinal parsing beats file-discovery order). `test-result-validators.sh` §E2 gains the AC7 cases.

**Subtask 2**
- `commands/verify.md`: add `--resume <run_id>` per AC10; the codegen-instruction print (AC4) is a NEW step inserted right after the `preflight`/executor-Task-spawn return, reading `VERIFY_RESULT.status`/`pause_reason` — `paused` ⇒ print the instruction (reading the real `storage_state_path`/`base_url` from `read-verify.sh`, never hard-coded) and stop; the `git check-ignore` warning (AC10) runs once at this point too.
- `agents/qa-executor.md`: replace step 5 and the `:204` fallback per AC8; add the resume-detection guard before steps 3-4 (skip `start`/`seed` when `evidence.jsonl` already has a passing `env:{step:start}` line) and the `first_unverdicted`-scoped spec-authoring loop (step 6/7 iterate only over the unverdicted subset on a resumed run, all ACs on a fresh one); add the `walk` exit-`5` branch beside the existing exit-`3` branch; update the `VERIFY_RESULT` emission template with `pause_reason`; update the Error Handling table and `## Integration Notes`. Re-run `bash scripts/check-token-budget.sh` after editing.
- `skills/verify-walkthrough/SKILL.md`: replace the `skills/verify-walkthrough/SKILL.md:171` forward-reference row (auth-required ⇒ "item 04 adds the pause-for-auth") with the actual pause/needs_auth/session_expired semantics; bump the skill's `version` frontmatter (`check-skills-index-sync.sh` pins the cell) and `SKILLS_INDEX.md`'s version cell to match.
- Root `scripts/check-contract-parity.sh`: extend the existing `agents/qa-executor.md|status|...` ENUMS row and the existing VERIFY_RESULT MANIFEST row per AC7; run the gate.
- Docs/counts: bump `loomwright/.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` `version` (15.76.1 → 15.77.0 if still current at execution time — read the LIVE file, do not hard-code) — **no count-phrase change** (no new agent/command/skill, only existing files modified) — and ONE `**vX.Y.Z — …:**` `CHANGELOG.md` paragraph naming the auth-pause/resume feature, ending `Counts: 14 agents, 24 commands, 42 skills, 36 hooks.` Run `bash scripts/check-doc-currency.sh`, `check-skills-index-sync.sh`, `check-command-sync.sh`, `check-contract-parity.sh`, `check-token-budget.sh`, `check-vendor-coupling.sh`, `check-shared-prefix.sh`, `validate-version.sh`, root `scripts/test-*.sh`, and the FULL `for t in loomwright/scripts/test-*.sh` loop before declaring done (memory `run-full-ci-suite-loop-before-push`).

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | `verify-run.sh` (read-only for #2), `test-verify-walkthrough.sh` | YES (ordered by `requires`) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after Subtask 1)

## Outcome
- **Completed:** 2026-09-15T14:20:00Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/226
- **Branch:** feature/verify-auth-pause
- **heal_loop_ran:** true
- **heal_decision:** PASS
- **heal_iterations:** 2
- **heal_fixable_issues_fixed:** 2 (HIGH: session-expiry resume no-op; MEDIUM: stale commands/agent-help.md)
- **heal_remaining_issues:** 1 LOW (non-blocking, disclosed: no dedicated 10+-AC ordinal-order test for the expiry-override's numeric comparison — implementation independently verified correct by inspection)
- **rubric_score:** 5/5
- **risk_classification:** {"high_risk": true, "reasons": ["auth/security/secret/token/payment keyword matches", "agents/commands/skills paths touched", "changed_lines 1014 > 400", "changed_files 17 > 15"]}
- **until_mergeable_dispatched:** false (auto_review suppressed by /automate; owned drain to follow)
