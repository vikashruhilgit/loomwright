# Supervisor Job: Selvedge sign-in is scripted by the CLI, stored outside the repo, and never loops (qa-split item 05)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** dirty (2 untracked dirs: `reports/`, `research_notes/`, unrelated), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 2 (untracked dirs; 5 linked worktrees on unrelated branches)
- **Source requirement:** .supervisor/requirements/qa-split/05-scripted-auth-outside-the-repo-and-the-model.md
- **Base commit:** 92c19d928df3b40df65b0c7c88a3e86296632616

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Selvedge is Node >= 18, standard library only, Playwright resolved at run time (`selvedge/lib/snapshot-playwright.mjs` `resolvePlaywright`). Playwright's `browser.newContext({ storageState })` and `context.storageState({ path })` cover the whole feature; nothing new is added. |
| 2 | Dependency Availability | GO | No new dependency. Hooks, approvals and the guarded browser already exist (items 02 and 04). |
| 3 | Architecture Fit | GO | `hooks.auth_setup` is already an accepted hook key (`HOOK_KEYS` in `selvedge/lib/env-config.mjs`), and `selvedge/lib/runner/run.mjs` already says "auth_setup is item 05's". Approvals stay user-scoped (`selvedge/lib/env-approvals.mjs`). |
| 4 | Scope vs Supervisor Capability | CAUTION | 19 files (14 modify, 5 create), above the 12-file single-worker bound: split `context-bound` into 2 sequential subtasks. |
| 5 | Hard Blockers | CAUTION | Not a blocker, but the plan needs files outside the requirement's `## Touches` (config validator + schema, the CLI entry, `env-approvals.mjs`, and selvedge's own release surfaces). Asked once at Phase 6 (`LP-SCOPE`). A headed browser cannot run in CI, so `auth setup --headed` is proven against the stub Playwright only. |

**Overall Verdict:** CAUTION

## Task
**Goal:** Add `selvedge auth setup [--headed]` (runs the approved `hooks.auth_setup` with credentials only from the env vars `selvedge.json` names, or lets a human sign in in a headed guarded browser, and keeps the Playwright storage state at `~/.local/state/selvedge/<repo-id>/auth/storageState.json`, dir 0700, file 0600, never inside the repo), make `selvedge run` load that state and check `auth.signed_in_check` once before the first criterion, and make a failed check BLOCKED `needs_auth` at once when nobody can sign in, with no retry loop.

**Problem Statement:**
Selvedge's owner (and later the item 06 CI adapter) needs walled pages verified without a model ever seeing a credential, because agents loop at login walls and leak what they type into traces.
Currently, `hooks.auth_setup` is accepted in `selvedge.json` but nothing runs it, `run` opens every criterion in an anonymous context, and a walled page becomes a pile of `step_failed` criteria that look like app bugs. This makes every signed-in criterion unverifiable, and there is no rule for where a session lives or what happens when it expires.
Success looks like: an approved hook writes the session to a 0600 file outside the repo, `run` uses it, a missing or expired session makes every criterion BLOCKED `needs_auth` after exactly one check (exit 2) when non-interactive, and no credential value appears in `evidence.jsonl`, `verdict.json` or the planner prompt, each proven by a test in `selvedge/tests/` against the fixture app.

## Design decisions
- decision: Where the auth command and the storage-state rules live (T2 new modules, T4 cross-cutting auth)
  chosen: two new modules: `selvedge/lib/auth-state.mjs` (the state path from the repo identity, the 0700 / 0600 modes, the outside-the-repo check, `hasState`) and `selvedge/lib/auth.mjs` (the `selvedge auth setup` command), reusing `repoIdentity` and an exported `insideRepo` from `selvedge/lib/env-approvals.mjs` and running the hook through the CLI's own `selvedge env hook auth_setup`, the same way `runHooks` in `selvedge/lib/runner/run.mjs` runs `reset` / `seed`
  rejected: add `auth setup` to `selvedge/lib/env.mjs` — it is a separate command family (`env` is config and hooks) and `env.mjs` is already 356 lines; blast radius no
  rejected: a copy of `insideRepo` / `repoIdentity` / the 0700-0600 modes in the new module — a second copy of the user-scoped-store rules that item 02 owns; reversibility no
  evidence: `grep -n "function insideRepo\|export function repoIdentity\|const FILE_MODE\|const DIR_MODE" selvedge/lib/env-approvals.mjs` → `function insideRepo(file, root)` (not exported; it uses the private `realpathOrResolve`, kept unchanged), `export function repoIdentity(root)`, `const FILE_MODE = 0o600;` and `const DIR_MODE = 0o700;` (both private, used by `writeApproval`'s `mkdirSync` + `chmodSync`). So `env-approvals.mjs` exports `insideRepo`, `FILE_MODE` and `DIR_MODE` (no behaviour change) and `auth-state.mjs` imports all three, so the two user-scoped stores share one mode rule; `grep -n "SELVEDGE_BIN, 'env', 'hook'" selvedge/lib/runner/run.mjs` → the `runHooks` spawn
  revisit when: a second user-scoped store (beyond approvals and auth state) needs the same path rules
  status: confirmed
- decision: Where the login-wall check runs (T2 new module)
  chosen: a new `selvedge/lib/runner/auth-check.mjs` exporting `checkSignedIn` (one guarded context with the stored state, `goto` the check URL, the locator must match at least one element) and `signedInGate` (the interactive / non-interactive branch, with `readLine` and `interactive` injectable so a test drives both without a TTY); `run.mjs` only calls it, after the hooks and before Playwright-per-criterion
  rejected: inline the check in `selvedge/lib/runner/run.mjs` — it is 495 lines at base, just under the module-layout threshold, and the check would push it past; blast radius partial
  evidence: `wc -l selvedge/lib/runner/run.mjs` → 495; `grep -n "export function locate\|export async function navigate" selvedge/lib/runner/steps.mjs` → both exist and are reused
  revisit when: a second pre-run check (beyond sign-in) is added and the two want one "preflight" module
  status: confirmed
- decision: What `selvedge auth setup --headed` does
  chosen: selvedge opens the guarded browser headed (`headless: false`, only on this path) at `auth.signed_in_check.url`, waits up to `SELVEDGE_AUTH_TIMEOUT_MS` (default 300000) for the signed-in locator while the human signs in, then saves `context.storageState()` to the state path with the same modes; no hook and no credential pass through selvedge
  rejected: hand `--headed` to the `auth_setup` hook as an env var — needs a hook the user may not have, and the hook would need its own browser; fits-stack partial, test cost no
  evidence: `grep -n "export function buildLaunchOptions" -A4 selvedge/lib/runner/route-guard.mjs` → returns only `{ proxy: … }` today, so a headed launch is one optional key; `selvedge/tests/test-route-guard.sh` AC16 pins the default shape, which stays unchanged
  revisit when: a target needs SSO the guarded browser's origin allowlist cannot reach (an identity provider on another origin)
  status: confirmed

## Acceptance Criteria
- [ ] AC1 — Given `selvedge.json` with `"auth": {"env": ["APP_USER", "APP_PASS"], "signed_in_check": {"url": "<an allowed origin URL>", "locator": {<one plan-step locator form>}}}`, when any command loads it (`loadConfig`), then it is accepted; `auth` is in `CONFIG_KEYS` and in `selvedge/schemas/selvedge-config.schema.json` (the existing key-set equality test in `selvedge/tests/test-env.sh` still passes); and `loadConfig` itself (so `env check`, `auth setup` and `run` alike) refuses with `config_schema_violation` (exit 2) an unknown `auth` or `signed_in_check` sub-key, a non-string or non-`[A-Z_][A-Z0-9_]*` env name, a `signed_in_check.url` whose origin the config does not list (`isOriginAllowed`, already in `env-config.mjs`), and a `locator` that is not a plain object; the locator's FORM (exactly one plan-step locator form, never CSS / XPath) is checked where it is used — by `validateSignedInCheck` in `selvedge/lib/auth-state.mjs`, which reuses `validateSteps` from `selvedge/lib/plan-steps.mjs` and maps any problem it reports to `config_schema_violation` — and `selvedge auth setup --headed` and `selvedge run` both call it before opening a browser, so a CSS locator makes each of them exit 2 `config_schema_violation` with nothing launched (`env-config.mjs` cannot import `plan-steps.mjs`: `plan-steps.mjs` imports `env-config.mjs`).
- [ ] AC2 — Given a temp git repo with an approved `hooks.auth_setup` that writes a JSON file to `$SELVEDGE_STORAGE_STATE`, and `APP_USER` / `APP_PASS` set, when `selvedge auth setup` runs, then it exits 0 and the file exists at `$HOME/.local/state/selvedge/<repo-id>/auth/storageState.json` (`<repo-id>` = the sha256 hex of `repoIdentity(root)`), the `auth` directory is mode 0700, the file is mode 0600 (set by selvedge after the hook, whatever umask the hook had), and `git status --porcelain` in the repo is byte-identical before and after.
- [ ] AC3 — Given an `auth_setup` hook with no approval (or an approval of other hook text), when `selvedge auth setup` runs, then stdout has the line `BLOCKED env_hooks_unapproved`, exit 2, the hook did not run (its marker file is absent) and no state file was written.
- [ ] AC4 — Given `auth.env` names a variable that is unset, when `selvedge auth setup` runs, then stdout has `BLOCKED placeholder_unset`, stderr names the variable (never any value), exit 2 and the hook did not run; given a hook that exits 0 without writing `$SELVEDGE_STORAGE_STATE`, then exit 1 and no state file exists; given `selvedge.json` with no `auth_setup` hook and no `--headed`, then a usage error (exit 2) that names `--headed` and `hooks.auth_setup`.
- [ ] AC5 — Given the fixture app's login-walled page, a frozen plan whose criteria read it, `auth.signed_in_check` pointing at it, no storage state, and `selvedge run --non-interactive <run-dir>` (or stdin not a TTY), when the run starts, then every criterion is BLOCKED `needs_auth` in `verdict.json`, stdout ends `verdict BLOCKED …`, exit 2, the fixture app counted exactly ONE request to the check URL (no retry loop), no criterion's steps ran (no `step` evidence lines), and `run_end` is written.
- [ ] AC6 — Given a valid storage state for the fixture app's signed-in user, when the same walled criterion runs, then it is PASS: every criterion context and the check context were opened with that state (`newContext` receives `storageState: <the state path>`), and with no state file `newContext` still receives exactly `{ serviceWorkers: "block" }` (the AC19 pin in `selvedge/tests/test-route-guard.sh` stays green).
- [ ] AC7 — Given an expired or otherwise rejected storage state (the fixture app no longer accepts its cookie), when `selvedge run --non-interactive` runs, then it is the AC5 outcome (`needs_auth`, exit 2, one check request) and `run` never runs `auth_setup` itself (its marker file is absent).
- [ ] AC8 — Given an interactive run (`signedInGate` driven with `interactive: true` and an injected `readLine`) whose first check fails, when the gate runs, then it prints on stderr what is needed, naming `selvedge auth setup --headed`, reads exactly one line, checks exactly once more, and either proceeds (second check passes) or returns `needs_auth` (second check fails); `readLine` is never called when `interactive` is false, and the check is never run a third time.
- [ ] AC9 — Given `APP_PASS` set to a distinct fixture password and an app page that shows that password in its DOM after sign-in, when a run with storage state executes a criterion that reads that page, then `grep -rF "$APP_PASS"` over the run folder (`evidence.jsonl`, `verdict.json`, screenshots aside), `.selvedge/runs.jsonl` and the run's stdout / stderr finds nothing (every `auth.env` value is added to the run's redaction list and written back as `{{APP_PASS}}`); and given the same `APP_PASS`, when `selvedge plan <criteria.json>` runs the default planner against a PATH-stub `claude` that records its argv and stdin, then the recorded planner prompt does not contain the password.
- [ ] AC10 — Given `auth.signed_in_check` and the stub Playwright (`SELVEDGE_PLAYWRIGHT_MODULE=selvedge/tests/fixtures/stub-playwright.mjs`), when `selvedge auth setup --headed` runs, then the launch receives `headless: false`, the context's `storageState` is written to the state path with mode 0600 once the locator matches, exit 0; without `signed_in_check` it is a usage error (exit 2) naming `auth.signed_in_check`; and `buildLaunchOptions({ proxyPort })` with no `headed` is still exactly `{ proxy: { server: … } }` (AC16 in `selvedge/tests/test-route-guard.sh`).
- [ ] AC11 — Given the change, when `bash selvedge/tests/run.sh` runs, then it passes: `selvedge/README.md` documents `selvedge auth setup [--headed]`, the `auth` config key, where the state lives, the `needs_auth` behaviour, and carries the honest-limit paragraph stating that an agent with shell access can read any file the user can, so selvedge keeps secrets out of plans, evidence, PR comments and model prompts and does not claim they are out of reach; its reasons table has a `needs_auth` BLOCKED row; and selvedge is released as 0.5.0 (`selvedge/.claude-plugin/plugin.json`, its `.claude-plugin/marketplace.json` entry and a `## 0.5.0 — <date>` heading in `selvedge/CHANGELOG.md`, which `selvedge/tests/check-release.sh` checks).

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| config + reasons | `selvedge/lib/env-config.mjs` (320), `selvedge/schemas/selvedge-config.schema.json` (36), `selvedge/tests/test-env.sh` (424 — two needles extended in place: the `want` reasons list and the schema key-set check) | — | HIGH |
| auth setup | `selvedge/lib/env-approvals.mjs` (165 — export `insideRepo`, `FILE_MODE`, `DIR_MODE`; no behaviour change), `selvedge/bin/selvedge` (130 — one `auth` dispatch arm + usage line) | `selvedge/lib/auth-state.mjs`, `selvedge/lib/auth.mjs`, `selvedge/tests/test-auth.sh` | HIGH |
| guarded browser options | `selvedge/lib/runner/route-guard.mjs` (390 — optional `storageState` / `headed` passed through to `newContext` / launch), `selvedge/tests/fixtures/stub-playwright.mjs` (58 — log launch / `newContext` options, a `storageState()` that writes a file, a `count()` controllable per locator) | — | HIGH |
| run login-wall check | `selvedge/lib/runner/run.mjs` (495 — only the call wiring, the `--non-interactive` flag and the usage / header lines; the check itself is the new module), `selvedge/lib/runner/execute.mjs` (277 — pass the state through to `openGuardedContext`) | `selvedge/lib/runner/auth-check.mjs`, `selvedge/tests/test-auth-run.sh` | HIGH |
| fixture app | `selvedge/tests/fixtures/app-server.mjs` (273 — a `/login` form, a walled `/account` page, a hit counter for it, a control to expire sessions) | — | HIGH |
| docs + release | `selvedge/README.md` (632 — the single user doc of the CLI; the auth section and the honest-limit paragraph belong beside `run`; Subtask 1 adds only the `needs_auth` reasons-table row and the `auth` bullet in the `selvedge.json` key list, Subtask 2 everything else), `selvedge/CHANGELOG.md` (132), `selvedge/.claude-plugin/plugin.json` (15), `.claude-plugin/marketplace.json` (140) | — | HIGH |

Module layout: each new responsibility has one home — state path and modes → `selvedge/lib/auth-state.mjs`; the `auth setup` command → `selvedge/lib/auth.mjs`; the login-wall check → `selvedge/lib/runner/auth-check.mjs`; the outside-the-repo rule → reuse `insideRepo` from `selvedge/lib/env-approvals.mjs` (exported, never copied); the hook spawn → reuse `selvedge env hook <name>` through `SELVEDGE_BIN`, as `runHooks` does. `run.mjs` (495, just under the 500-line threshold, and past it after this change) and `README.md` (632, past it) gain only call wiring / user docs (`run.mjs`: the single run sequence, which must call the check in order; `README.md`: the single CLI doc). New tests go in new files (`test-auth.sh`, `test-auth-run.sh`), not in `test-run.sh` (391) or `test-env.sh` (424, which only has two existing needles extended).

> **Validator-owned surfaces:** acceptance depends on `selvedge/tests/check-release.sh` (version == CHANGELOG top heading == marketplace entry) and Loomwright's `scripts/check-doc-currency.sh` (description length of the marketplace entries). Both release surfaces are in the map.

### File Overlap Detection

| Group A | Group B | Overlapping Files | Serialization Required |
|---------|---------|-------------------|----------------------|
| Subtask 1 | Subtask 2 | `selvedge/README.md` (Subtask 1: the `needs_auth` reasons row and the `auth` key bullet only; Subtask 2: the auth section, honest-limit paragraph, `run` text — sequential, legal) — Subtask 2 also consumes `auth-state.mjs`, `needs_auth` and the `openGuardedContext` options Subtask 1 adds) | YES — `requires` edges |

## Touched-file invariants

> Grounded at base `92c19d928df3b40df65b0c7c88a3e86296632616`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`selvedge/lib/env-config.mjs`** — keep: `REASONS` is the one closed reason list ("no reason is a string literal anywhere else"), so `needs_auth` is added there (BLOCKED group) and every emitter imports it; `validateSchema` refuses unknown keys (`unknown top-level key`) and must refuse an unknown `auth` sub-key the same way; `validateConfig` returns a frozen normalized config — add `auth` to it (frozen, absent → `null`), and check `signed_in_check.url` there with the module's own `isOriginAllowed` (after the origin list is validated); mirror: `CONFIG_KEYS` and the JSON schema's `properties` are "a real second copy, not a tautology" — both gain `auth`; pinned by: `selvedge/tests/test-env.sh` `eq(Object.keys(s.properties), E.CONFIG_KEYS)`, its `const want = [` reasons list, and its README-sync arm (`ko "README reasons table out of sync` — every `REASONS` key needs exactly one `| \`<reason>\` |` row in `selvedge/README.md`'s reasons table), so the `needs_auth` README row lands in the SAME subtask (Subtask 1) as the `REASONS` entry.
- **`selvedge/schemas/selvedge-config.schema.json`** — keep: `"additionalProperties": false` at the top level and inside the new `auth` object (and inside `signed_in_check`); mirror: `selvedge/lib/env-config.mjs` `CONFIG_KEYS`; pinned by: `selvedge/tests/test-env.sh` `eq(Object.keys(s.properties), E.CONFIG_KEYS)`.
- **`selvedge/lib/env-approvals.mjs`** — keep: `insideRepo(file, root)` behaviour unchanged and still built on the private `realpathOrResolve`; `const FILE_MODE = 0o600;` and `const DIR_MODE = 0o700;` keep their values (only `export` is added to these three, nothing else changes); `approvalState` "Fails closed"; approvals stay at `$HOME/.claude/selvedge/approvals.json` — the auth state is a different file under `$HOME/.local/state/selvedge/`, never mixed into approvals; reuse: `repoIdentity(root)` (strips userinfo: `stripUserinfo`) is the repo identity the state path hashes; pinned by: `selvedge/tests/test-env.sh` approval arms (`BLOCKED env_hooks_unapproved`).
- **`selvedge/bin/selvedge`** — keep: bash 3.2, `set -uo pipefail`, "no jq, no `readlink -f`"; reuse: `cmd_node` (add an `auth) shift; cmd_node auth "$@" ;;` arm, module `lib/auth.mjs`); keep the exit-code contract in the header ("0 ok, 1 an operation failed, 2 usage error or BLOCKED"); keep the `*) printf 'selvedge: unknown command` arm last; pinned by: `selvedge/tests/test-cli.sh` (`unknown command exits 2`, `--version`, the no-argument help naming `install-cli`; an added `auth` usage line breaks none of them).
- **`selvedge/lib/runner/route-guard.mjs`** — keep: `assertLoopbackProxied()` first; `buildLaunchOptions({ proxyPort })` returns exactly `{ proxy: { server: … } }` when not headed; `browser.newContext({ serviceWorkers: 'block' })` gets `storageState` ONLY when a path is given (no `storageState: undefined` key); the route is installed "before its first page is created"; pinned by: `selvedge/tests/test-route-guard.sh` `AC16 buildLaunchOptions is exactly` and `'R.ac19_order.calls.includes("newContext:" + JSON.stringify({ serviceWorkers: "block" }))'`.
- **`selvedge/lib/runner/run.mjs`** — keep: the refusal order in the header (usage, `not_frozen`, `already_run`, `plan_modified`, config reason) and the claim (`claimRun`) before any hook or launch; `RUN_HOOKS = Object.freeze(['reset', 'seed'])` stays — `run` never runs `auth_setup` (update the comment `auth_setup is item 05's` to say it runs only through `selvedge auth setup`); the sign-in check runs after the hooks and the planner-token budget, before step 3's per-criterion checks; it needs a browser, so when (and only when) `config.auth?.signed_in_check` is set, `resolvePlaywright` runs BEFORE the check and the resolved `pw` is reused by step 4 (no second resolution); a resolution failure there sets `blockAll` to that `EnvError`'s own reason (`playwright_unavailable`), never `needs_auth`; a run with no `auth` config keeps today's step order exactly ("Playwright, only when a criterion is left to run"); a failed check sets `blockAll = { outcome: CRITERION_OUTCOMES.blocked, reason: REASONS.needs_auth }` so `run_start`, every `criterion_end`, `run_end`, `verdict.json` and the ONE `runs.jsonl` line are still written; `run_start` keeps its closed field set (`EVIDENCE_FIELDS` in `evidence.mjs` — add no field); every reason from `REASONS`; reuse: `parseCliArgs` for the new `--non-interactive` boolean; the auth values join `secrets` (from `placeholderValues` shape `{ name, value }`) so `appendEvidence`'s redaction covers them; pinned by: `selvedge/tests/test-run.sh` (AC9/AC10/AC17–AC21 arms) and `selvedge/tests/test-replay.sh`.
- **`selvedge/lib/runner/execute.mjs`** — keep: "No cookie, storage or page state carries from one criterion to the next" — each criterion still gets a FRESH context; the stored state is the same starting point for each, never the previous criterion's cookies; keep `openGuardedContext({ chromium, config })` semantics when no state file exists; pinned by: `selvedge/tests/test-run.sh` cookie isolation arm (`/cookie`).
- **`selvedge/tests/fixtures/stub-playwright.mjs`** — keep: `chromium.launch appends the line \`launch\` to $STUB_PW_LOG` (existing tests count launches by that marker; new option logging goes to a separate variable, e.g. `STUB_PW_OPTS_LOG`, never to `STUB_PW_LOG`); `count: async () => 1` stays the default; pinned by: `selvedge/tests/test-run.sh` `launches()` checks.
- **`selvedge/tests/fixtures/app-server.mjs`** — keep: "every page is a complete HTML document; scripts are inline"; the existing routes and their header comment table (add the new routes to it); the `node app-server.mjs serve <info.json> [<log dir>]` command shape (tests read the port from the info file); pinned by: `selvedge/tests/test-snapshot.sh`, `test-plan.sh`, `test-run.sh`, `test-replay.sh`.
- **`selvedge/tests/test-env.sh`** — keep: hermetic temp HOME; only the two needles above are extended; its README-sync arm (`README sync: every REASONS key has exactly one row`) is unchanged and stays green because Subtask 1 adds the README row with the reason.
- **`selvedge/CHANGELOG.md`, `selvedge/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`** — keep: "Selvedge releases on its own", never through `changelog.d/`; the first `## <X.Y.Z> — <YYYY-MM-DD>` heading equals `plugin.json`'s `version`; the plugin and marketplace `description` stay identical and carry no `vX.Y.Z` token; pinned by: `selvedge/tests/check-release.sh`.

## Closed enumerations touched

> Sibling grep at base `92c19d9`: `git grep -n "placeholder_unset" -- . ':!.supervisor'` → 15 hits in 9 files.

- **`needs_auth`** (sibling: `placeholder_unset`) — must be named in:
  - `selvedge/lib/env-config.mjs` — `REASONS` (`placeholder_unset: 'placeholder_unset',`) — extend (BLOCKED group).
  - `selvedge/tests/test-env.sh` — the `const want = [` exact reasons list — extend.
  - `selvedge/README.md` — the `## BLOCKED and config reasons` table (`| \`placeholder_unset\` | BLOCKED |`) — extend, in Subtask 1 (pinned by `selvedge/tests/test-env.sh`'s README-sync arm).
  - `selvedge/CHANGELOG.md` — release notes, not a closed list — the 0.5.0 entry names it.
  - `selvedge/lib/plan-steps.mjs`, `selvedge/lib/runner/run.mjs` (header), `selvedge/tests/test-plan-validate.sh`, `selvedge/tests/test-run.sh`, `selvedge/tests/test-snapshot.sh` — uses of `placeholder_unset` itself — no change: not lists of reasons.
  - `loomwright/agents/qa-executor.md`, `loomwright/commands/verify.md`, root `CHANGELOG.md` — Loomwright's own `needs_auth` (VERIFY_RESULT `pause_reason`) — no change: a different plugin's list; selvedge imports nothing from `loomwright/`.
- **`auth`** (sibling config key: `allow_remote_mutation`) — must be named in:
  - `selvedge/lib/env-config.mjs` — `CONFIG_KEYS` — extend.
  - `selvedge/schemas/selvedge-config.schema.json` — top-level `properties` — extend.
  - `selvedge/README.md` — the `## \`selvedge.json\`` key list ("No other key is accepted") — extend, in Subtask 1 (beside `CONFIG_KEYS`).

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `selvedge/tests/test-env.sh` — reasons `want` list (and the README-sync arm, which then finds a README row with no `REASONS` key) | delete `  needs_auth: 'needs_auth',` in `selvedge/lib/env-config.mjs` |
| `selvedge/tests/test-env.sh` — schema key set equals `CONFIG_KEYS` | flip `'hooks', 'auth'])` → `'hooks'])` in `selvedge/lib/env-config.mjs` |
| `selvedge/tests/test-auth.sh` — AC1 unknown `auth` sub-key refused | in `selvedge/lib/env-config.mjs`, delete the line that fails an `auth` key outside its allowed set |
| `selvedge/tests/test-auth.sh` — AC1 CSS locator refused by `auth setup --headed` | in `selvedge/lib/auth-state.mjs`, delete the line in `validateSignedInCheck` that throws `config_schema_violation` when `validateSteps` reports a problem |
| `selvedge/tests/test-auth.sh` — AC2 file mode 0600 | flip `const FILE_MODE = 0o600;` → `const FILE_MODE = 0o644;` in `selvedge/lib/env-approvals.mjs` |
| `selvedge/tests/test-auth.sh` — AC2 directory mode 0700 | flip `const DIR_MODE = 0o700;` → `const DIR_MODE = 0o755;` in `selvedge/lib/env-approvals.mjs` |
| `selvedge/tests/test-auth.sh` — AC2 nothing new under the repo | in `selvedge/lib/auth-state.mjs`, return a path under the repo root (`path.join(root, '.selvedge', 'auth', …)`) instead of under `$HOME/.local/state/selvedge` |
| `selvedge/tests/test-auth.sh` — AC3 unapproved hook BLOCKED | in `selvedge/lib/auth.mjs`, delete the line that returns the `BLOCKED` result when `selvedge env hook auth_setup` exits 2 (the command then reports success with no state) |
| `selvedge/tests/test-auth.sh` — AC4 unset env name | in `selvedge/lib/auth.mjs`, delete the line that throws `REASONS.placeholder_unset` for an unset `auth.env` name |
| `selvedge/tests/test-auth.sh` — AC10 headed launch | in `selvedge/lib/runner/route-guard.mjs`, delete the line that adds `headless: false` to the launch options when `headed` |
| `selvedge/tests/test-auth-run.sh` — AC5 all BLOCKED `needs_auth` | in `selvedge/lib/runner/run.mjs`, delete the line that sets `blockAll` from a failed sign-in check |
| `selvedge/tests/test-auth-run.sh` — AC5 exactly one check request | in `selvedge/lib/runner/auth-check.mjs`, make the non-interactive branch call `checkSignedIn` a second time before returning |
| `selvedge/tests/test-auth-run.sh` — AC6 walled criterion PASS with state | in `selvedge/lib/runner/execute.mjs`, delete the line that passes `storageState` to `openGuardedContext` |
| `selvedge/tests/test-auth-run.sh` — AC8 interactive branch re-checks once | in `selvedge/lib/runner/auth-check.mjs`, delete the second `checkSignedIn` call after `readLine` |
| `selvedge/tests/test-auth-run.sh` — AC9 no password in evidence | in `selvedge/lib/runner/run.mjs`, delete the line that adds the `auth.env` values to `secrets` |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Config `auth` key, `needs_auth`, state path, `selvedge auth setup [--headed]`, guarded-browser options | AC1, AC2, AC3, AC4, AC10 (+ the README `needs_auth` row and `auth` key bullet that `test-env.sh` / `CONFIG_KEYS` need) | 8 modify, 3 create | `skills/error-handling/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 2 | `run` loads the state, checks the login wall once, `needs_auth`, redaction; README + 0.5.0 release | AC1 (the `run` refusal of a CSS locator), AC5, AC6, AC7, AC8, AC9, AC11 | 7 modify, 2 create | `skills/error-handling/SKILL.md`, `skills/unit-testing/SKILL.md` | BLOCKED (by #1) |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "selvedge/lib/auth-state.mjs"}
  - {kind: "symbol", path: "selvedge/lib/auth-state.mjs", name: "authStatePath"}
  - {kind: "symbol", path: "selvedge/lib/auth-state.mjs", name: "hasState"}
  - {kind: "symbol", path: "selvedge/lib/auth-state.mjs", name: "validateSignedInCheck"}
  - {kind: "file", path: "selvedge/lib/auth.mjs"}
  - {kind: "symbol", path: "selvedge/lib/env-config.mjs", name: "needs_auth"}
  - {kind: "symbol", path: "selvedge/lib/env-approvals.mjs", name: "export function insideRepo"}
  - {kind: "symbol", path: "selvedge/lib/runner/route-guard.mjs", name: "storageState"}
  - {kind: "symbol", path: "selvedge/schemas/selvedge-config.schema.json", name: "signed_in_check"}
  - {kind: "symbol", path: "selvedge/bin/selvedge", name: "cmd_node auth"}
  - {kind: "file", path: "selvedge/tests/test-auth.sh"}
  - {kind: "symbol", path: "selvedge/README.md", name: "needs_auth"}
requires: []
lanes:
  - "selvedge/lib/env-config.mjs"
  - "selvedge/lib/env-approvals.mjs"
  - "selvedge/schemas/selvedge-config.schema.json"
  - "selvedge/bin/selvedge"
  - "selvedge/lib/auth-state.mjs"
  - "selvedge/lib/auth.mjs"
  - "selvedge/lib/runner/route-guard.mjs"
  - "selvedge/tests/fixtures/stub-playwright.mjs"
  - "selvedge/tests/test-env.sh"
  - "selvedge/tests/test-auth.sh"
  - "selvedge/README.md"  # only the needs_auth reasons-table row and the auth key bullet; Subtask 2 (which reaches Subtask 1 via requires) owns the rest of the README
external_requires:
  - "Playwright (resolved at run time by resolvePlaywright; storageState in newContext and context.storageState)"

# Subtask 2
provides:
  - {kind: "file", path: "selvedge/lib/runner/auth-check.mjs"}
  - {kind: "symbol", path: "selvedge/lib/runner/auth-check.mjs", name: "checkSignedIn"}
  - {kind: "symbol", path: "selvedge/lib/runner/auth-check.mjs", name: "signedInGate"}
  - {kind: "symbol", path: "selvedge/lib/runner/run.mjs", name: "non-interactive"}
  - {kind: "file", path: "selvedge/tests/test-auth-run.sh"}
  - {kind: "symbol", path: "selvedge/README.md", name: "selvedge auth setup"}
  - {kind: "symbol", path: "selvedge/CHANGELOG.md", name: "## 0.5.0"}
  - {kind: "symbol", path: "selvedge/.claude-plugin/plugin.json", name: "\"version\": \"0.5.0\""}
requires:
  - {from: "1", kind: "symbol", path: "selvedge/lib/auth-state.mjs", name: "authStatePath"}
  - {from: "1", kind: "symbol", path: "selvedge/lib/auth-state.mjs", name: "validateSignedInCheck"}
  - {from: "1", kind: "symbol", path: "selvedge/lib/env-config.mjs", name: "needs_auth"}
  - {from: "1", kind: "symbol", path: "selvedge/lib/runner/route-guard.mjs", name: "storageState"}
  - {from: "1", kind: "symbol", path: "selvedge/README.md", name: "needs_auth"}
lanes:
  - "selvedge/lib/runner/auth-check.mjs"
  - "selvedge/lib/runner/run.mjs"
  - "selvedge/lib/runner/execute.mjs"
  - "selvedge/tests/fixtures/app-server.mjs"
  - "selvedge/tests/test-auth-run.sh"
  - "selvedge/README.md"
  - "selvedge/CHANGELOG.md"
  - "selvedge/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
external_requires:
  - "Playwright Chromium from selvedge/tests/lib/playwright-cache.sh for the real-browser arms (a SKIP outside CI, a FAIL under CI, as test-run.sh does)"
```

**Notes for the workers:**
- Subtask 1: `selvedge auth setup` order: load config (working tree, or `--base <ref>` as `env hook` takes it) → every origin local, else `BLOCKED env_hooks_remote_origin` (the `env hook` check) → every `auth.env` name set, else `BLOCKED placeholder_unset` naming the names → create `<state dir>` 0700 (refuse, exit 1, if it resolves inside the repo) → run `selvedge env hook auth_setup` with `SELVEDGE_STORAGE_STATE=<path>` in its env (exit 2 + its `BLOCKED <reason>` line passed through; any other non-zero → exit 1) → the file must exist and parse as JSON, else exit 1 and remove any partial file → `chmod 0600` → print the path (never a value). `--headed` instead needs `auth.signed_in_check`, calls `validateSignedInCheck` first, and opens the guarded browser headed (Design decisions). `validateSignedInCheck(config)` (in `auth-state.mjs`) runs `validateSteps` from `selvedge/lib/plan-steps.mjs` on `[{type:'goto', url}, {type:'wait_for', locator, state:'attached'}]` and throws `EnvError(REASONS.config_schema_violation, …)` naming the first problem `validateSteps` reports; `env-config.mjs` does the structural part of AC1 (sub-keys, env names, the URL's origin via `isOriginAllowed`, locator is a plain object) inside `validateConfig`, so every `loadConfig` caller refuses those.
- Subtask 2: `run` calls `validateSignedInCheck(config)` before resolving Playwright (a CSS locator: exit 2 `config_schema_violation`, before the claim, with the other config reasons). interactive = stdin is a TTY and `--non-interactive` not given. The check runs only when `config.auth?.signed_in_check` is set; with no `auth` config `run` behaves byte-for-byte as before. A replay (`--replay`) runs the same check. `data_state` is unchanged by the check. The new tests run the hermetic way `test-run.sh` does (temp HOME, temp git repos, stub `claude` on PATH, real Chromium from `tests/lib/playwright-cache.sh`, sourcing `tests/lib/run-helpers.sh`); the "exactly one check request" assertion reads the fixture app's hit counter, and "no criterion steps ran" reads `evidence.jsonl` (no `kind: "step"` line).

### Dependency Graph

```
Subtask 1 ──→ Subtask 2
```

## Parallelism Analysis
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after Subtask 1 — its `requires` point at Subtask 1)
- **Recommended workers:** 1
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/error-handling/SKILL.md`, `skills/unit-testing/SKILL.md` |
| 2 | `skills/error-handling/SKILL.md`, `skills/unit-testing/SKILL.md`, `skills/playwright-e2e/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): the plan needs files outside the requirement's `## Touches` (`env-config.mjs`, `env-approvals.mjs`, the config schema, `bin/selvedge`, `test-env.sh`, the release surfaces) | MEDIUM | Each is a one-purpose edit named in the File Impact Map; the owner is asked once at Launch Pad Phase 6 (`LP-SCOPE`), and an accepted widening is recorded in a `## Scope widening` section written then. |
| Feasibility (Phase 2.5): a headed browser cannot run in CI | MEDIUM | `--headed` is proven against the stub Playwright (launch options + `storageState` written + mode); the real sign-in is a manual path, stated in the README. |
| Feasibility (Phase 2.5): 19 files, above one worker's bound | MEDIUM | `context-bound` split into 2 sequential subtasks with disjoint lanes. |
| `selvedge snapshot` (the planner's tool) does not load the storage state, so a planner cannot snapshot a walled page | MEDIUM | Out of this item's scope (the requirement says "`run` loads it"); the README states it, and the walled criterion in the tests is planned by hand (the generator in `tests/lib/run-helpers.sh`). |
| The interactive wait could hang an unattended run whose stdin is a TTY but nobody is there | MEDIUM | One read only, one re-check only; `--non-interactive` documented for wrappers; CI (`SELVEDGE_ENTRY=ci`) callers pass `--non-interactive`. |
| A hook could print the credential itself to stdout / stderr | LOW | Hook output is the user's own command; selvedge never prints a value. The README's honest-limit paragraph says secrets are kept out of plans / evidence / prompts, not out of reach. |
| `README.md` (632) and the selvedge description may grow past their limits | LOW | Add only the auth section; keep the description edit to a few words and under Loomwright's 600-char check (`scripts/check-doc-currency.sh`). |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-17-qa-split-05-scripted-auth-outside-repo.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-11-17T16:36:20Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/935
- **Branch:** feature/qa-split-05-scripted-auth-outside-repo
- **Files changed:** 23
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** armed
- **Summary:** Subtasks 1+2 implemented selvedge auth setup [--headed], the auth config key, needs_auth and the one-shot sign-in check in run; released selvedge 0.5.0. Phase 4.5 ran 3 review rounds with fixes 988f0e0, 493c4a0 and ff391c2 (round 2 caught a --trace localStorage-token leak, fixed and confirmed in round 3). Round 3's 2 MEDIUM trace-redaction findings were fixed in ff391c2 but not re-reviewed.

## Not verified
- **selvedge auth setup --headed with a real headed Chromium** — no display in an automated run; proven against the stub Playwright only (subtask 1)
- **selvedge run interactive sign-in prompt on a real terminal** — no pty in the hermetic suite; signedInGate driven with interactive and readLine injected (subtask 2)
