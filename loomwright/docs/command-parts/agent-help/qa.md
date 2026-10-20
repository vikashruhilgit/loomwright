### 5️⃣ /qa-strategist — Risk-Based QA Strategy

**Purpose:** Plan risk-based test strategy and audit QA Executor results

**Usage:**
```
/qa-strategist src/                              # Analyze source for risk
/qa-strategist --audit .qa-summary.md            # Audit Executor results
/qa-strategist src/auth/ --focus auth             # Focus on auth flows
```

**What it does:**
- **Strategy Mode:** Discovers routes/endpoints, classifies risk (HIGH/MEDIUM/LOW), sets coverage targets, produces test priority matrix
- **Audit Mode:** Reviews QA Executor summary, evaluates coverage against targets, emits STRATEGIST_VERDICT (approved/rejected)

**Risk Classification:**
- **HIGH:** Auth flows, data mutation, payment/billing (target: 85%)
- **MEDIUM:** CRUD operations, standard API endpoints (target: 70%)
- **LOW:** Static pages, informational content (target: 50%)

**Key Constraints:**
- Read-only — never writes files, never runs tests
- Verdict is final on conflict (defaults to deeper testing)
- Level-aware — only demands current maturity level capabilities

**When to Use:**
- Before QA execution to define test priorities
- After QA execution to audit coverage and quality
- When you need risk-based testing decisions

**Learn More:** `/qa-strategist --help`

---

### 6️⃣ /qa-executor — Automated QA Testing

**Purpose:** Discover app structure, generate and run Playwright tests, orchestrate debate loop

**Usage:**
```
/qa-executor                                      # Auto-detect URL + topology, full run
/qa-executor --url http://localhost:3000            # Explicit URL
/qa-executor --auth-state ./auth.json              # Pre-authenticated (OAuth/SSO apps)
/qa-executor --skip-strategy                       # Quick run, skip Strategist
/qa-executor --coverage 90                         # Override coverage target (risk-based default)
/qa-executor --strict-discovery                    # Require human approval of discovery
# Note: --rounds only meaningful at L2+. L1 runs 1 round (hard cap).
```

**What it does:**
1. Auto-detects app topology (UI, API style, platform) + probes test infrastructure
2. Runs 4-phase discovery engine (static analysis → runtime crawl → selective vision → merge & gate)
3. Gets risk strategy from QA Strategist (or uses defaults)
4. Generates Playwright tests appropriate to detected topology (UI/API/GraphQL/WebSocket)
5. Executes tests, tracks coverage, reports bugs
6. Runs Strategist audit (debate loop)
7. Emits QA_RESULT

**Discovery Engine:**
```
Static Analysis → Routes from source code (Glob/Grep)
Runtime Crawl   → Playwright DOM/network/a11y extraction (max 30 pages, depth 3)
Selective Vision → Screenshots for complex pages only
Merge & Gate    → Confidence scoring (HIGH/MEDIUM/LOW)
```

**Level 1 Boundaries:**
- Happy paths + basic errors + negative tests (no state modeling / fuzz → L2)
- No performance tests (→ L3)
- No adversarial/penetration security tests (→ L3)
- L1 INCLUDES non-destructive security boundary probes: IDOR, role escalation,
  session invalidation, XSS/SQLi input-rejection checks, cookie security flags
- Single debate round
- Inventory-level coverage tracking
- Auto-detects: REST, GraphQL, mixed APIs, web UI, mobile backends
- Generates tests appropriate to detected topology (skips UI tests for API-only apps)

**Requirements:**
- Application must be running at base URL
- Playwright browsers installed
- `playwright.config.ts`: required for UI apps; auto-generated for API-only apps if missing
- For OAuth/SSO apps: `--auth-state ./auth.json` recommended

**When to Use:**
- Automated QA after feature implementation
- Regression testing before release
- Quick smoke tests (with --skip-strategy)

**Learn More:** `/qa-executor --help`

---

### 🔎 /verify — Walk a ticket through the running app

**Purpose:** Verify ONE ticket against the RUNNING app — no other surface does this (`## Executable Acceptance` is `cmd:` / `corpus-task:` only, `/qa-executor` crawls the whole app from discovery and forbids form submission, Phase 4.5 / CI review read the diff). Reads the ticket's acceptance criteria, refuses to touch anything not proven non-prod, starts the app from the committed `.agent/verify.json` contract, walks each AC with Playwright, and appends exactly one of four verdicts per AC — `PASS` / `FAIL` / `BLOCKED` / `NOT_VERIFIABLE` — with evidence. `PASS` is recorded ONLY when the Then was observed; `NOT_VERIFIABLE` says so when it cannot be. When the app needs an authenticated session it does not have (or one dies mid-run), the run PAUSES rather than recording a false verdict — see "Auth pause / resume" below.

> **Advisory only** — a verify run changes no `heal_decision`, blocks no PR, and merges nothing. Its outputs are `<run_dir>/summary.md` (derived from `evidence.jsonl`, never hand-edited) and the executor's `VERIFY_RESULT` block.

**Usage:**
```bash
/verify <ticket-path>                        # a requirement (.supervisor/requirements/…) or a brief (.supervisor/jobs/…)
/verify <ticket-path> --branch <name>        # verify that branch's HEAD (default: the current branch)
/verify <ticket-path> --cheap                # run the executor on Sonnet (docs/ARCHITECTURE_CONTRACTS.md §"Cost Profiles")
/verify --resume <run_id>                    # resume a run that paused for a human sign-in (needs_auth / session_expired)
/verify <ticket-path> --notify                # POST gate-event webhooks + a desktop banner at needs_auth, first FAIL, and run_end

# Headless (claude -p) — use the NAMESPACED form; bare /verify is "Unknown command" under detached claude -p:
claude -p "/loomwright:verify .supervisor/requirements/checkout/01-coupon.md"
```

**What it does:**
1. Reads the protocol authority `skills/verify-walkthrough/SKILL.md` (AC extraction, AC → spec derivation, the four verdicts, the V7 mutation carve-out, evidence-per-AC, budget)
2. Shells out to `scripts/verify-run.sh preflight` — contract read → non-prod proof (`non_prod_assert` must PASS in THIS run, no override) → run dir minted; exit `3` (no `.agent/verify.json` — prints the `propose-verify.sh --non-prod … --confirm` bootstrap line), `1` (`non_prod_assert_failed`), and `2` (`ticket_unresolved` / usage) all STOP, fail CLOSED, nothing started
3. Spawns the QA Executor in `--verify <run_dir>` mode as the ONLY child — it owns env start / seed / **auth-check** (`scripts/verify-run.sh auth-check`, not a direct probe — `auth.method: none` makes zero executor calls) / spec authoring / `verify-run.sh walk` / reset / stop / `finish`; the main thread never runs the walkthrough itself
4. Reports `<run_dir>/summary.md` (the counts row `PASS: n · FAIL: n · BLOCKED: n · NOT_VERIFIABLE: n · total: n` and the per-AC table) plus the `VERIFY_RESULT` `summary` field; a missing block (turn limit, crash) is named, and the evidence lines already written are the checkpoint — UNLESS the run paused (below), in which case no counts/summary are printed as if it finished
5. On a `completed`/`aborted` run with ≥1 recorded `FAIL` **or** ≥1 `issue` line, auto-dispatches `scripts/propose-from-verify.sh <run_dir>` (same as `/propose --from-verify <run_id>`) — one evidence-carrying draft per `FAIL` `ac` line classified `REAL_BUG` and per `issue` line, written to `.supervisor/requirements/proposed/`, never enqueued; never on a paused run

**Notify (`--notify`).** A passthrough flag, never persisted (re-pass it on `--resume` too) — fires `scripts/send-webhook.sh --event-type gate` at exactly THREE events (`needs_auth` pause, the first `FAIL`, `run_end`), each guarded to fire at most once per run, plus `scripts/notify-desktop.sh` at `needs_auth`. Dispatched from inside `verify-helpers.sh evidence-append` (the store's sole writer) via a filesystem marker (`<run_dir>/.notify-enabled`, created by `preflight --notify` / `verify-run.sh notify-enable`) rather than an env var, because the qa-executor's VERIFY MODE runs in a separate Task-spawned process with no shared shell state. `LOOMWRIGHT_WEBHOOK_URL` unset ⇒ silent no-op, run unaffected.

**Auth pause / resume.** A run that needs a sign-in it does not have (`auth-check` exit `4`), or whose session dies mid-walk (a real 401/403 observed on an authenticated route forces `walk` to exit `5`), STOPS with `VERIFY_RESULT.status: paused` and a `pause_reason` (`needs_auth` | `session_expired`) instead of a false BLOCKED/completed verdict. The command prints exactly ONE instruction: `npx playwright codegen --save-storage=<path> <base_url>`, then `sign in, close the window`, then `/verify --resume <run_id>` — the plugin never opens a browser and never echoes anything read from the storage-state file, only its path. `/verify --resume <run_id>` errors on a missing run dir (never silently starts a fresh run under that id) and on a run dir that already finished (`completed`/`aborted` — nothing paused to resume); otherwise it re-probes auth and, on success, continues at the first AC with no GENUINE verdict yet — the ACs a session-expiry pause force-BLOCKED are re-opened for a fresh spec run, never permanently stranded, while a real PASS/FAIL/BLOCKED from before the pause is never re-run.

**Requirements:** a committed `.agent/verify.json`; `@playwright/test` resolvable from the target repo (`npx --no-install playwright`) — when it is not, every remaining AC is recorded `BLOCKED` / `playwright_unavailable` and the run finishes `aborted`, the plugin never installs it; `jq`, `git`, `python3`, `node`/`npx`.

**Learn More:** see `loomwright/commands/verify.md` for the surface, `loomwright/skills/verify-walkthrough/SKILL.md` for the protocol, and `docs/RESULT_SCHEMAS.md` §VERIFY_ENV / §VERIFY_EVIDENCE / §VERIFY_RESULT for the three schemas a run touches.

---

