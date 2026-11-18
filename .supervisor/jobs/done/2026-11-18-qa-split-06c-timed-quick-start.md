# Supervisor Job: Selvedge quick start a new user can follow to a first verdict in 15 minutes or less, with `selvedge doctor`, a one-command sample app and a recorded timed run

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** dirty (2 untracked dirs: `reports/`, `research_notes/`, unrelated), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 2 (dirty tree — unrelated untracked dirs; 5 linked worktrees exist, none for this item)
- **Source requirement:** .supervisor/requirements/qa-split/06c-timed-quick-start-to-first-verdict.md
- **Base commit:** 18fb95ca592522e545177eb71a5168d55c0f0875

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Selvedge is bash 3.2 (`bin/selvedge`) + Node >= 18 ES modules (`lib/*.mjs`); doctor and sample-app use both, no new stack |
| 2 | Dependency Availability | GO | No new dependency. Doctor reuses `resolvePlaywright` (`lib/snapshot-playwright.mjs`), `loadConfig` (`lib/env-config.mjs`), `approvalState` (`lib/env-approvals.mjs`), `PLANNER_ENV` / `CLAUDE_BIN` (`lib/plan-planner.mjs`); the sample app is the existing `tests/fixtures/app-server.mjs` |
| 3 | Architecture Fit | GO | Same dispatch as every other verb: a `case` arm in `bin/selvedge` running a `lib/<command>.mjs` |
| 4 | Scope vs Supervisor Capability | GO | 7 modify + 4 create (11 files), under the context-bound bound; single subtask |
| 5 | Hard Blockers | CAUTION | (a) The requirement's timed run on a fresh macOS user account cannot be done by an agent: owner decision (LP-CLARIFY, 2026-11-18) — the worker records a fresh-HOME rehearsal, the owner records the fresh-account run before merge. (b) The plan needs four files outside the requirement's Touches (`selvedge/bin/selvedge` for the `doctor` / `sample-app` dispatch; the release trio `selvedge/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `selvedge/CHANGELOG.md`) — asked once at Phase 6 (LP-SCOPE) |

**Overall Verdict:** CAUTION

## Task
**Goal:** A new user reaches a first Selvedge verdict on the bundled sample app by following `selvedge/README.md`'s quick start, `selvedge doctor` names the one fix for every missing prerequisite, and the timed run is recorded in `selvedge/docs/quick-start-timing.md`.

**Problem Statement:**
A developer trying Selvedge needs to get from install to a first verdict in ≤ 15 minutes with no sign-up beyond their Claude login, because onboarding friction is the top reason teams drop an AI QA tool after a trial (product rule P1, `00-plan.md` §8 measure "fresh-machine time to first verdict").
Currently, the README is a reference manual (825 lines, no quick start), the sample app is a test fixture that starts on a random port with a 15-minute watchdog and nothing points a user to it, and a missing prerequisite (no Playwright, no browser, no `selvedge.json`, no planner) is discovered only when a command fails.
Success looks like: one copy-pasteable path from install to a verdict table, a `selvedge doctor` that prints one fix per failed check, and a timing record showing the path takes ≤ 15 minutes.

**Owner decisions (LP-CLARIFY, 2026-11-18):**
1. The timed run: the worker rehearses the README with a fresh `HOME` on this Mac and fixes what it finds; the doc records that run, labelled a rehearsal; the owner then runs it on a fresh macOS account and adds those times before merging. The PR stays open until the owner's run is recorded.
2. The sample app starts with a new verb, `selvedge sample-app [--port N]`.

## Design decisions
- decision: where `selvedge doctor`'s checks live (T2: CREATE `selvedge/lib/doctor.mjs`)
  chosen: a new `selvedge/lib/doctor.mjs` that imports the existing check helpers (`resolvePlaywright`, `loadConfig`, `approvalState`, `PLANNER_ENV` / `CLAUDE_BIN`), run through `cmd_node`-style dispatch; the Node presence/version check runs in bash in `bin/selvedge`'s `doctor` arm before `exec node`, because a missing Node cannot run a `.mjs`
  rejected: all checks as bash in `bin/selvedge` — blast radius no (re-implements Playwright resolution and the selvedge.json schema validation in bash, a second copy that drifts from what `run` / `snapshot` actually do); fits stack partial
  rejected: fold the checks into `selvedge env check` — reversibility no (changes an existing command's output and exit code, which `tests/test-env.sh` pins), and the requirement names `selvedge doctor` and `selvedge/lib/doctor*`
  evidence: `grep -n "^export" selvedge/lib/*.mjs` → `export async function resolvePlaywright(` (snapshot-playwright.mjs), `export function loadConfig(` (env-config.mjs), `export function approvalState(` (env-approvals.mjs), `export const PLANNER_ENV = 'SELVEDGE_PLANNER';` and `export const CLAUDE_BIN = 'claude';` (plan-planner.mjs); `bin/selvedge` `cmd_node()` dies with `the $name commands need Node.js >= 18 on PATH (node not found)` when node is absent
  revisit when: Selvedge grows a non-Node runtime path (then the bash pre-check becomes the whole doctor)
  status: confirmed

## Acceptance Criteria
- [ ] **AC1 (quick start).** Given `selvedge/README.md`, when a new user reads it, then a `## Quick start` section (right after the intro, before `## Install`) walks, in order: `/plugin install selvedge@atelier` → `selvedge install-cli` (stated as required; the README's existing `## Install` evidence for why stays) → a demo folder (`mkdir`, `git init`, `npm init -y`, `npm i -D playwright`) → `npx playwright install chromium` → `selvedge env init --port 4173` → `selvedge doctor` (expected output: every check `ok`; the README says that any `FAIL` line names its own fix) → `selvedge sample-app --port 4173` (in a second terminal) → `/selvedge:verify` with three example criteria pasted as text that target the sample app's pages (e.g. `/cart`: opening the cart shows a Total of 6; `/echo`: typing a name shows "Hello, <name>"; `/slow`: Load price shows 42) → reading the verdict table. Every command sits in its own copy-pasteable fenced block and the expected output (or its key line) is shown after it.
- [ ] **AC2 (sample app, one command).** Given the CLI on PATH, when the user runs `selvedge sample-app [--port N]` (default port 4173), then the bundled fixture app (`selvedge/tests/fixtures/app-server.mjs`) serves on `http://localhost:N` in the foreground until Ctrl-C (no 15-minute watchdog in this mode), and prints its origin and the `selvedge env init --port N` line to use; a port already in use exits 1 with a one-line message naming the port. `startAppServer()` called with no argument still binds a random port, so every existing test caller is unchanged. `selvedge/tests/test-sample-app.sh` starts it in the background on a free port with stdout/stderr redirected to a temp file (never the suite's stdout), stops it from an EXIT trap, fetches `/cart` and asserts the "Shop" heading, fetches `/echo` and `/api/price` and asserts the literals the README's example criteria rely on (`Hello, `, `42`), occupies a second free port first and asserts that `selvedge sample-app --port <that port>` exits 1 with the port number in its message, and asserts after the stop that the server process is gone. The 4173 default and the absence of the watchdog in sample mode are documented in the README and the file header; they are not pinned (a test would have to bind 4173 or wait 15 minutes).
- [ ] **AC3 (doctor).** Given a machine missing one prerequisite, when the user runs `selvedge doctor` inside a repo, then it prints one line per check — Node >= 18, Playwright library (found exactly as `run` finds it: `SELVEDGE_PLAYWRIGHT_MODULE`, else the repo's own `node_modules`), Chromium browser installed for that Playwright, `selvedge.json` present and valid, hook approvals (only when `selvedge.json` has hooks; "no hooks" otherwise), and the planner (`SELVEDGE_PLANNER` set, or `claude` on PATH) — each `ok <check>` or `FAIL <check>: <one-line fix>`, and exits 0 when all pass, 1 when any fails. The fix lines contain these literals: Node → `install Node.js >= 18`; Playwright library → `npm i -D playwright`; browser → `npx playwright install chromium`; `selvedge.json` → `selvedge env init --port`; approvals → `selvedge env approve`; planner → `or set SELVEDGE_PLANNER`. With Node absent, the bash arm prints the Node `FAIL` line and one line `skipped: the other checks need Node` (no per-check names in bash, so `lib/doctor.mjs` stays the only list of checks), then exits 1 rather than crashing. `selvedge/tests/test-doctor.sh` (hermetic: temp HOME, temp git repo, stub Playwright through `SELVEDGE_PLAYWRIGHT_MODULE`, a PATH built without `node` / `claude` where needed) removes each prerequisite one at a time and asserts that check's `FAIL` line with its fix literal, plus an all-present run that exits 0.
- [ ] **AC4 (honest limits).** Given the README, when a user reads the quick start, then a `## Honest limits` section states: Selvedge checks web apps only (native targets come later); what BLOCKED means (the check could not run — a named reason, linking the existing `## BLOCKED and config reasons` table) and what NOT_VERIFIABLE means (the check ran but could not decide the criterion — a named reason, same table); D11's secret limit (an agent with shell access can read any file you can — linking the existing `auth` section's honest-limit paragraph rather than restating it); and that no accuracy numbers are published until the Phase 2 measurement exists.
- [ ] **AC5 (timed rehearsal — the worker's run).** Given the finished README, when the worker follows it exactly on this Mac with a fresh `HOME` (empty npm cache, an empty `PLAYWRIGHT_BROWSERS_PATH`, no `~/.local/bin/selvedge`, no approvals file) and times each step (`date +%s` before and after), then the committed evidence file `selvedge/docs/quick-start-timing.md` contains a `## Rehearsal (worker, fresh HOME)` section with: the date; the machine (`uname -sm`, macOS version, Node version); one row per README step with its seconds; the total as measured (the target is ≤ 15 minutes; when the honest total is over it, the file names the dominant step and the README change attempted, and AC5 still passes — the ≤ 15-minute pass/fail belongs to AC6's owner run; never trim a number); every place the README was wrong or unclear and the fix made; and a plain list of what was NOT fresh (the Claude login and Claude Code install, Node/Homebrew already present, and — if `/selvedge:verify` could not run headless under `claude -p` — that the verify step used the equivalent CLI commands, named). No vendor sign-up beyond the existing Claude login is used, and the file says so.
- [ ] **AC6 — superseded 2026-11-18 by owner decision:** the owner chose an agent-run timed quick start on a real project (Sportify, fresh `HOME`, 107 s command time, 3/3 PASS), recorded as `## Real-app run (agent, Sportify, fresh HOME)` in `selvedge/docs/quick-start-timing.md`, in place of the fresh-macOS-account run below. Original text: **AC6 (owner's fresh-account run — owner step, not the worker's).** Given the rehearsal is recorded, when the PR is opened, then `selvedge/docs/quick-start-timing.md` also carries a `## Owner run (fresh macOS account)` section with the same columns and the line `Status: pending owner run — the owner fills this section in on a fresh macOS account before merging`. (The PR body repeats this as a courtesy; it is not part of this criterion.) The source requirement's first acceptance line (≤ 15 minutes from a fresh account) is met only when the owner records that run; the worker does not fill it.
- [ ] **AC7 (release).** Given Selvedge releases on its own, when the change is complete, then `selvedge/.claude-plugin/plugin.json` `version` and the `selvedge` entry's `version` in `.claude-plugin/marketplace.json` are `0.7.0`, `selvedge/CHANGELOG.md` has a new first heading `## 0.7.0 — <YYYY-MM-DD>` describing `selvedge doctor`, `selvedge sample-app` and the quick start, the CLI help (`selvedge` with no arguments) and the README `## CLI` block list `doctor` and `sample-app`, and `bash selvedge/tests/run.sh` passes. No `changelog.d/` fragment and no `scripts/bump-version.sh` run (CLAUDE.md: selvedge releases on its own).

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
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

Applied here: the quick start and the timing doc never state the plugin version (the timing doc may record `selvedge --version` output as a dated observation); the honest-limits section links the reasons table and the auth honest limit instead of copying them.

## Touched-file invariants

> Grounded at base `18fb95ca592522e545177eb71a5168d55c0f0875`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`selvedge/README.md`** — keep: no new table row of the form `` | `<lowercase_word>` | `` outside the reasons table, because `selvedge/tests/test-env.sh` scans the whole README and fails on any such row that is not a `REASONS` key (`README sync: every REASONS key has exactly one row in README's reasons table, and no row is unknown`) — write the doctor checks and the limits as bullets or a table whose first cell is not a backticked lowercase word; every existing `## ` heading and section stays (the `` ## `plan` commands `` section bounded by the next `## ` is pinned by `selvedge/tests/test-plan.sh`); the auth honest-limit paragraph (`**Honest limit.** An agent with shell access can read any file you can`) stays verbatim and is linked, not moved. pinned by: `selvedge/tests/test-env.sh`, `test-plan.sh`, `test-plan-validate.sh`, `test-replay.sh`, `test-auth-run.sh` (each greps README literals) — run all five.
- **`selvedge/bin/selvedge`** — keep: bash 3.2 + BSD/GNU userland only, no jq, no `readlink -f` (`Runs on user machines, so it needs nothing beyond bash 3.2 + BSD/GNU userland: no jq, no`); `set -uo pipefail`; the exit-code contract (`# Exit codes: 0 ok, 1 an operation failed, 2 usage error or BLOCKED`); an unknown verb still exits 2 (`*) printf 'selvedge: unknown command: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;`). reuse: the existing `cmd_node` dispatch (`exec node "$BIN_DIR/../lib/$module.mjs" "$@"`) and `BIN_DIR` for locating `../tests/fixtures/app-server.mjs`; mirror: the header comment's verb list (`# The \`env\`, \`auth\`, \`criteria\`, \`snapshot\`, \`plan\`, \`run\`, \`verdict\` and \`comment\` commands run`) and `usage()`'s command list gain `doctor` and `sample-app`. pinned by: `selvedge/tests/test-cli.sh` (`grep -qE '^ +install-cli '` on the no-argument help; `unknown command exits 2`).
- **`selvedge/tests/fixtures/app-server.mjs`** — keep: `export async function startAppServer() {` with no argument binds a random port (`server.listen(0, '127.0.0.1', resolve);`) — callers in `tests/lib/run-helpers.sh`, `test-snapshot.sh`, `test-plan.sh`, `test-run.sh`, `test-replay.sh`, `test-auth-run.sh` depend on it; the `serve <info.json>` command and its watchdog (`watchdog: exiting after 15 minutes`) stay for tests; every page stays self-contained (`scripts are inline, nothing loads from elsewhere`). reuse: the same handler for the sample mode — a port option on `startAppServer` (default 0) rather than a second server. mirror: the file's header page list is the sample app's page documentation the quick-start criteria cite; `selvedge/docs/evidence/verify-adapter-equivalence.md` cites `startAppServer()` and the watchdog (no change needed if both stay).
- **`selvedge/tests/test-cli.sh`** — keep: hermetic temp HOME per `install-cli` run (`Hermetic: every install-cli run gets a fresh temp HOME; the user's ~/.local/bin is never touched.`); extend the no-argument help assertion to `doctor` and `sample-app` in the same `grep -qE '^ +<verb> '` form.
- **`selvedge/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `selvedge/CHANGELOG.md`** — keep: the three bump together (`selvedge/README.md` §"Releasing"); `selvedge/tests/check-release.sh` requires the first `## <X.Y.Z> — <YYYY-MM-DD>` heading to equal `plugin.json`'s version (`changelog_version_mismatch`); `scripts/validate-version.sh` checks plugin.json against the marketplace entry. Description stays a summary with no `vX.Y.Z` token (CLAUDE.md anti-rebloat; ≤ 600 chars).

## Closed enumerations touched

> Sibling grep at base `18fb95ca592522e545177eb71a5168d55c0f0875`: `grep -rnF 'verdict) shift' selvedge` → 1 hit; `grep -rnF '`verdict` and `comment`' selvedge` → 2 hits; `grep -rnF 'help, -h, --help' selvedge` → 1 hit.

- **`doctor`, `sample-app`** (sibling verb: `comment` / `verdict`) — must be named in:
  - `selvedge/bin/selvedge` — the dispatch `case` arms (`verdict) shift; cmd_node verdict "$@" ;;`) — extend (two arms).
  - `selvedge/bin/selvedge` — `usage()`'s `Commands:` list (`help, -h, --help     print this help`) — extend.
  - `selvedge/bin/selvedge` — header comment verb list (`` The `env`, `auth`, `criteria`, `snapshot`, `plan`, `run`, `verdict` and `comment` commands run ``) — extend with `doctor` (Node part; its Node pre-check is bash) and `sample-app` (Node).
  - `selvedge/README.md` — `## CLI` block and its sentence (`` **The `env`, `auth`, `criteria`, `snapshot`, `plan`, `run`, `verdict` and `comment` commands ``) — extend.
  - `selvedge/agents/verifier.md` — its prohibited-command line (`Never run \`selvedge comment\``) — no change: that is a list of commands the verifier must not run, not a list of every verb; `doctor` and `sample-app` are neither posting, approvals nor sign-in.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `selvedge/tests/test-doctor.sh` — Playwright library missing ⇒ `npm i -D playwright` | delete `npm i -D playwright` in `selvedge/lib/doctor.mjs` |
| `selvedge/tests/test-doctor.sh` — browser missing ⇒ `npx playwright install chromium` | delete `npx playwright install chromium` in `selvedge/lib/doctor.mjs` |
| `selvedge/tests/test-doctor.sh` — no selvedge.json ⇒ `selvedge env init --port` | delete `selvedge env init --port` in `selvedge/lib/doctor.mjs` |
| `selvedge/tests/test-doctor.sh` — unapproved hooks ⇒ `selvedge env approve` | delete `selvedge env approve` in `selvedge/lib/doctor.mjs` |
| `selvedge/tests/test-doctor.sh` — no planner ⇒ `or set SELVEDGE_PLANNER` | delete `or set SELVEDGE_PLANNER` in `selvedge/lib/doctor.mjs` |
| `selvedge/tests/test-doctor.sh` — Node absent ⇒ `install Node.js >= 18` | delete `install Node.js >= 18` in `selvedge/bin/selvedge` |
| `selvedge/tests/test-sample-app.sh` — `/cart` serves "Shop" on the given port | delete `sample-app)` in `selvedge/bin/selvedge` |
| `selvedge/tests/test-sample-app.sh` — the server process is gone after the stop | make the sample mode in `selvedge/tests/fixtures/app-server.mjs` ignore SIGTERM and SIGINT (replace its signal handlers with no-ops) |
| `selvedge/tests/test-sample-app.sh` — `/echo` shows `Hello, ` and `/api/price` answers `42` | flip `"42"` → `"43"` in the `/api/price` handler of `selvedge/tests/fixtures/app-server.mjs` |
| `selvedge/tests/test-sample-app.sh` — a port already in use exits 1 naming the port | make `probeInUse` in `selvedge/tests/fixtures/app-server.mjs` treat an accepted connection as free (`finish('in-use')` → `finish(null)`) — amended 2026-11-18 by owner decision: the pre-listen probe, not the listen's `EADDRINUSE`, is what detects a held port; this mutation fails the [::1]-only and wildcard cases (13 passed, 2 failed), verified |
| `selvedge/tests/test-doctor.sh` — all present exits 0, any `FAIL` exits 1 | make `selvedge/lib/doctor.mjs` always exit 0 |
| `selvedge/tests/test-doctor.sh` — Node absent prints `skipped: the other checks need Node` | delete `skipped: the other checks need Node` in `selvedge/bin/selvedge` |
| `selvedge/tests/test-cli.sh` — no-argument help lists `doctor` | delete `  doctor ` in `selvedge/bin/selvedge` (the usage line) |
| `selvedge/tests/test-cli.sh` — no-argument help lists `sample-app` | delete `  sample-app ` in `selvedge/bin/selvedge` (the usage line) |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Quick start, `selvedge doctor`, `selvedge sample-app`, timed rehearsal, release 0.7.0 | all (AC6 is a stub the owner completes) | 7 modify, 4 create | `skills/quality-checklist/SKILL.md` | LAUNCHABLE |

### File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| docs | `selvedge/README.md` (825 — the plugin's single user doc; the quick start and honest limits must be its first sections, and `## CLI` is the closed verb list) | `selvedge/docs/quick-start-timing.md` | HIGH |
| doctor | `selvedge/bin/selvedge` (140) | `selvedge/lib/doctor.mjs` (new responsibility's home), `selvedge/tests/test-doctor.sh` | HIGH |
| sample app | `selvedge/tests/fixtures/app-server.mjs` (360) | `selvedge/tests/test-sample-app.sh` | HIGH |
| CLI pins | `selvedge/tests/test-cli.sh` (105) | — | HIGH |
| release | `selvedge/.claude-plugin/plugin.json` (15), `.claude-plugin/marketplace.json` (140), `selvedge/CHANGELOG.md` (206) | — | HIGH |

Module layout: the doctor's checks get one home (`selvedge/lib/doctor.mjs`), importing the existing helpers — no copy of Playwright resolution, config validation or approval-state logic. The sample mode extends `app-server.mjs`'s own `startAppServer` (one port parameter) — no second server. `README.md` (825) is past the threshold; appending is deliberate (reason above).

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "selvedge/lib/doctor.mjs"}
  - {kind: "file", path: "selvedge/tests/test-doctor.sh"}
  - {kind: "file", path: "selvedge/tests/test-sample-app.sh"}
  - {kind: "file", path: "selvedge/docs/quick-start-timing.md"}
  - {kind: "symbol", path: "selvedge/docs/quick-start-timing.md", name: "## Rehearsal (worker, fresh HOME)"}
  - {kind: "symbol", path: "selvedge/docs/quick-start-timing.md", name: "## Owner run (fresh macOS account)"}
  - {kind: "symbol", path: "selvedge/README.md", name: "## Quick start"}
  - {kind: "symbol", path: "selvedge/README.md", name: "## Honest limits"}
  - {kind: "symbol", path: "selvedge/bin/selvedge", name: "sample-app)"}
  - {kind: "symbol", path: "selvedge/bin/selvedge", name: "doctor)"}
  - {kind: "symbol", path: "selvedge/CHANGELOG.md", name: "## 0.7.0"}
requires: []
lanes:
  - "selvedge/README.md"
  - "selvedge/docs/quick-start-timing.md"
  - "selvedge/bin/selvedge"
  - "selvedge/lib/doctor.mjs"
  - "selvedge/tests/**"
  - "selvedge/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - "selvedge/CHANGELOG.md"
external_requires:
  - "Node.js >= 18 and network access to npm and the Playwright CDN for the timed rehearsal"
  - "the owner's existing Claude login (claude CLI) for the rehearsal's verify step"
  - "the owner, for AC6's fresh macOS account run before merge"
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/quality-checklist/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): the requirement's fresh-macOS-account timed run cannot be done by an agent | HIGH | Owner decision: the worker records a fresh-HOME rehearsal (AC5) and leaves a `Status: pending owner run` section (AC6); the PR stays open until the owner records the fresh-account run. Do not report the requirement's ≤ 15 min fresh-account criterion as met from the rehearsal |
| Feasibility (Phase 2.5): four files outside the requirement's Touches (`bin/selvedge`, release trio) | MEDIUM | Accepted at Launch Pad Phase 6 (LP-SCOPE); recorded in `## Scope widening` |
| `/selvedge:verify` may not run headless under `claude -p` with a fresh HOME (plugin install and login live in the real HOME) | MEDIUM | The rehearsal may run the verify step with the equivalent CLI chain (`criteria from-text` → `plan` → `run` → `verdict`) and must say so in the not-fresh list; the owner's run covers `/selvedge:verify` itself |
| A rehearsal under a fresh HOME downloads Chromium (~150 MB); a slow network inflates the total past 15 min | MEDIUM | Record the download time as its own row; if the total exceeds 15 min, record it honestly and say which step dominated — never trim the number |
| Sample mode has no watchdog, so a `test-sample-app.sh` that dies between start and stop could leave a server running and, holding the suite's stdout, hang a piped `run.sh` / `ci-local.sh` after the last PASS | MEDIUM | AC2: background start with output redirected to a temp file, EXIT-trap stop, and an assertion that the process is gone |
| Changing `startAppServer` breaks the six test callers that rely on a random port | MEDIUM | Port parameter defaults to 0; run `bash selvedge/tests/run.sh` (the full selvedge gate) before hand-back |
| The doctor's browser check misreads the stub Playwright in tests | LOW | Use `chromium.executablePath()` + an existence check, and give the stub a controllable executable path in the test, not a special case in `doctor.mjs` |
| Concurrent agents on this checkout (project memory) | LOW | Work in the Supervisor worktree; snapshot the timing notes outside the repo while the rehearsal runs |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-18-qa-split-06c-timed-quick-start.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-11-18T06:39:52Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/939
- **Branch:** feature/qa-split-06c-timed-quick-start
- **Files changed:** 11
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** needs_human
- **Heal remaining issues:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** armed
- **Summary:** selvedge doctor, selvedge sample-app [--port N], README Quick start + Honest limits, fresh-HOME rehearsal (63 s command time, 3/3 PASS) in selvedge/docs/quick-start-timing.md, release 0.7.0. Three heal rounds fixed sample-app port-in-use detection ([::1] then dual-stack '::' via a pre-listen connect check), the README step-7 recovery, a test PID leak and untested branches. Escalated: pin row 10 (listen EADDRINUSE fallback) is no longer reached by any test — owner picks Linux-only test / test-only switch / amend the pin row; the round-3 timeout-test fix was not re-reviewed. AC6 owner fresh-account run still pending — do not merge before it is recorded.

## Not verified
- **/selvedge:verify slash command and its verdict table (README steps 8-9)** — needs an interactive Claude Code session to approve the verifier's commands; the rehearsal used the CLI chain (subtask 1)
- **/plugin marketplace add vikashruhilgit/loomwright from GitHub** — 0.7.0 is not on GitHub main until merge; the rehearsal added this checkout by path (subtask 1)
- **install-cli 'not on your PATH' note and the export PATH step** — the rehearsal PATH already included the fresh HOME's .local/bin (subtask 1)
- **fresh macOS account run (AC6, the 15-minute target)** — owner step; section left with the pending Status line (subtask 1)

## Owner decisions (2026-11-18, after the PR opened)
- **Pin row 10 amended** (the escalated needs-ruling finding): its mutation now targets the pre-listen `probeInUse` check, which the existing [::1]-only and wildcard cases catch; no code change, no new test.
- **AC6 replaced** by a timed real-app run on Sportify done by the agent (see AC6 above); no fresh macOS account run will be done.
