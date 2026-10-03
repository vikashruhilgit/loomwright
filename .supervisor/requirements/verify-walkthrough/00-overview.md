# 00 — Verify-walkthrough queue overview (index/policy doc — NOT an implementable item)

## Status: done (index document — nothing to implement; this stamp is the ONLY thing `resolve-folder` honours, so it is what keeps `/automate` from enqueuing this file)

**Origin:** 2026-09-11/12 `/product-owner` discovery for the owner's ask: *"an agent which analyses the
requirement for an application and then checks/validates the work done by the ticket — by running the app,
walking through it, asking for and saving login when required, seeding data, filling forms; notifying and
recording issues; adding everything to a result summary; working through multiple tickets from requirement
files like /automate; keeping its state separately from automate/executor."*
**Authority above this queue:** `loomwright/docs/SPIKES/FINAL_STATE_GOAL.md` (D1–D11) and
`NORTH_STAR_DIRECTION.md` §"Explicit NOs". If an item and either file disagree, the file wins and the item is amended.

## The one-line product
`/verify <ticket>` proves that **this ticket landed in the running app and did not break its neighbours** —
by driving the app with **Playwright from Bash** (own headless Chromium; no desktop/screen control, no
Desktop-only browser MCPs), one verdict per acceptance criterion, with evidence. It complements, never
replaces: unit tests prove the code; `/qa-executor` proves the app broadly; Phase 4.5 + CI review prove the diff.

## Decisions taken (owner accepted the recommendations on 2026-09-12 — "lets create automate requirement")
| # | Decision | Why |
|---|---|---|
| V1 | **Command + skill; the executor is `qa-executor` in a new `--verify` mode. NO 15th agent.** | NORTH_STAR "No speculative new agents"; D2 (prompt-orchestration agents are the layer the SDK runner replaces); D3 single-agent default. Reuses qa-executor's discovery, Playwright patterns, failure classification. |
| V2 | **Env contract is a committed `.agent/verify.json`** with a propose-only, `--confirm`-gated bootstrap and a fail-safe reader — the exact `product.json` pattern. | Nothing today starts the app, seeds, resets, or proves non-prod. Per-run flags re-type it every run; a CLAUDE.md section is unvalidatable. |
| V3 | **A FAILED criterion becomes an evidence-carrying draft in `.supervisor/requirements/proposed/`** (the `/propose` contract: cites evidence or is not written; never enqueues). | The QA lane found 25 blocking bugs that nothing consumed (memory `qa-l1-validated-on-sports-management`). Recording without a consumer repeats that. |
| V4 | **v1 ticket sources: PO requirement files (`.supervisor/requirements/**/*.md`) and Supervisor briefs (`.supervisor/jobs/done/*.md`).** Jira/Linear/PR-URL are Phase 2. | Both carry structured acceptance criteria today. |
| V5 | **State store is its own: `.supervisor/verify/<run_id>/`** — `run.md` (queue/current/progress, automate conventions) + **append-only `evidence.jsonl`**; every summary/roll-up is **derived by script**, never agent-written. | D5 (one writer, derived state). The QA store's agent-written `coverage.json` reported a `failed` scope as `completed`. |
| V6 | **Advisory, never gating.** `/verify` output is a verdict a human reads; it changes no `heal_decision`, blocks no PR, merges nothing. | NORTH_STAR "Nothing gating"; CLAUDE.md §Failure-Mode Invariants. |
| V7 | **Mutations (form submit, create, delete) are allowed ONLY in `--verify` mode, ONLY when `non_prod_assert` passes, with declared seed/reset.** L1's "never submit forms during discovery" stays byte-identical for every other qa-executor mode. | Loosening L1 silently is the wrong fix; a separate mode with its own rule is the right one. |
| V8 | **The plugin never handles credentials.** Login = the human signs in themselves in a headed browser; Playwright saves `storageState`; the run only ever reads that file. | Hard rule of the harness. Also: subagents cannot `AskUserQuestion`, so the pause lives in the command layer. |

## Order (load-bearing)
01 → 02 → 03 → 04 → 05 · 06 after 03 · 07 after 03 + 04 · `operator-run/08` after 05 (dogfood). 01 and 02 are
independent of each other and may run in parallel; everything else consumes them.

| Item | Delivers | Closes |
|---|---|---|
| 01 verify-env-contract | `.agent/verify.json` schema + `propose-verify.sh` + `read-verify.sh` + seam test | app never started / seeded / reset by the plugin; no non-prod proof |
| 02 verify-evidence-store | `VERIFY_EVIDENCE` schema, `verify-helpers.sh` (append / derive), validator, derived `summary.md` | agent-written roll-ups that lie; no cumulative report |
| 03 verify-command-and-mode | `/verify <ticket>` command, `verify-walkthrough` skill, qa-executor `--verify` mode, 4 verdicts | no ticket-driven verification exists (ground_truth is `cmd:` only) |
| 04 verify-auth-pause | `needs_auth` park → human sign-in → resume; session-expiry re-detect | qa-executor only warns and crawls unauthenticated |
| 05 verify-fail-sink-and-notify | FAIL → `proposed/verify-*.md` drafts; `--notify` on FAIL | nothing consumes found issues |
| 06 verify-impact-pass | diff → surfaces + brief File Impact Map + prior-AC regression | "other impacted areas" |
| 07 verify-queue-and-resume | `--folder`, `run.md`, reconcile-vs-truth, `--limit`, `--cheap` | multi-ticket like /automate, own state |
| `operator-run/08` dogfood | run 01–05 against a real app, record what lied | the L1 lesson: field evidence before the next rung |

## /automate handling
- 01–07 are normal code-change items — one file = one item.
- `operator-run/08` is operator-run and lives in the subfolder — **the subfolder IS the skip mechanism**
  (`automate-helpers.sh resolve-folder` globs `"$dir"/*.md` non-recursively and honours only `## Status: done`).
- Every new emitter/reader is fail-SAFE (`exit 0`, empty stdout on absence, reason to stderr); every guard that
  refuses to touch the app fails CLOSED with a named reason. CLAUDE.md §"Failure-Mode Invariants" unchanged.
- Counts move: +1 command (03), +1 skill (03). `plugin.json` / `marketplace.json` description counts in place,
  `SKILLS_INDEX.md`, `commands/agent-help.md`, CHANGELOG — `scripts/check-doc-currency.sh` is the gate. Growing
  `agents/qa-executor.md` (03) means re-measuring `docs/prompt-token-budgets.json .agents["qa-executor"]`
  (`scripts/check-token-budget.sh` fails CLOSED) and syncing `commands/qa-executor.md` flag prose in the same
  commit (`scripts/check-command-sync.sh` does NOT cover Parameters-table prose — memory `agent-command-mirror-drift-on-fixes`).

## Verified facts this queue rests on (read 2026-09-11 from the files, not memory)
- `agents/qa-executor.md` Phase 3 DETECT URL: reads `playwright.config.ts` / `.env`, else **asks the user**, then
  `curl`s — it **requires the app to already be running** and never starts it. Phase 2 only installs deps.
- Auth: Phase 4 classifies `oauth:{provider}|session|api-key|none`; on OAuth without `--auth-state` it **logs a
  warning and crawls unauthenticated**. `--auth-state ./auth.json` is the only auth input. No ask-and-save.
- Seed: Phase 5 *inventories* seed data into `discovery/seed-data.json` (entity counts + sample IDs). Nothing creates data.
- L1 Critical Rules: "Never submit forms during discovery, never click delete/logout/payment buttons";
  "No production testing". Env detection: `localhost → local`, `*.vercel.app → preview`.
- Failure classification `REAL_BUG | DISCOVERY_GAP | ENVIRONMENT_ISSUE` exists (Phase 13). QA_RESULT is validated
  by `scripts/validate-qa-result.py`; the per-scope `.qa-session/results/*.json` files have **no schema**.
- qa-executor frontmatter tools: `Read, Write, Edit, Glob, Grep, Bash, Task, LSP` (+ disallowed) — **no
  `AskUserQuestion`**; a subagent cannot pause on a human question. Only the main-thread command layer can.
- `## Executable Acceptance` (`skills/supervisor-readiness/SKILL.md`) → `run-ground-truth.sh` in Phase 4.5:
  bullets are `cmd:` / `corpus-task:` only; machine-authored briefs may emit only `corpus-task:`. No UI walk.
- `agents/launch-pad.md` step 8 computes a **File Impact Map + indirect blast radius** per brief. No consumer
  re-reads it after the run.
- `/propose` (`scripts/propose-work.sh`) writes ONLY under `.supervisor/requirements/proposed/` through
  `guarded_write()`, requires a mandatory `## Evidence` section, and `proposed/` is deliberately NOT an
  `/automate --folder` target.
- `.agent/product.json` pattern: `propose-product.sh` (sole writer, propose-only, `--confirm`), `read-product.sh`
  (advisory, exit 0, **empty stdout on absence**, reason to stderr), schema in `RESULT_SCHEMAS.md` §PRODUCT_CONTEXT
  (no `schema_version` by documented exception), `test-product-seam.sh`.
- `automate-loop` §3–4: single run file, `## Progress` append-only, atomic temp+rename writes, resume = glob +
  reconcile belief vs `gh`/git truth. Helpers: `runfile-write`, `progress-append`, `queue-checkoff`, `remaining`.
  Memory `runfile-write-accepts-empty-stdin`: guard line counts before any rewrite.
- `scripts/send-webhook.sh` is the notify emitter (fail-SAFE, exit 0); `/automate --notify` is a passthrough
  flag NOT persisted in `## Run Config`.
- Field evidence for the QA lane (memory `qa-l1-validated-on-sports-management`): 887 tests, 52 bugs / 25 blocking;
  `coverage.json` agent-written → `store` scope `failed` in its own file, `completed` in the roll-up;
  `.qa-summary.md` overwritten per scope; `BUG-NC-001` unfixed 5 months on because nothing consumed it.
- Tool-call budget for qa-executor: 80 default / 110 `--scope|--continue` / 60 `--plan`; `maxTurns: 120`.

## Honest limits (named here so no item claims otherwise)
- AC → Playwright steps is LLM judgment, not mechanical; some ACs are not checkable through the app. The
  `NOT_VERIFIABLE` verdict exists so that is said, never faked as PASS.
- The impact pass (06) is bounded to diff-mapped surfaces + the brief's impact map + prior ACs on overlapping
  routes. It will not find a break in a subsystem none of those name.
- A verdict says the app behaved as the AC describes on this run; it is not a proof of correctness and it is
  not a merge signal (V6).
