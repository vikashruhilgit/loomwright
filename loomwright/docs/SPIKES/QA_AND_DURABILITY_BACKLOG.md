# QA & Durability Backlog (ideas preserved from `temp/` cleanup)

> **Status:** backlog / not-yet-shipped ideas. Captured 2026-06-05 from old `temp/` draft docs **before deleting them**,
> so genuinely-useful unshipped designs aren't lost. These are NOT committed plans — they're a parking lot.
> Validate against current shipped state (v14.13.0) before acting; some parts may have partially shipped.
>
> Provenance (source `temp/` drafts these ideas were extracted from): `Dual-Agent QA Architecture.md`,
> `QA Executor.md`, `qa-level-up.md`, `Durable Autonomous Upgrade.md`, `self-learning.md`.

---

## 1. QA maturity ladder — make L1/L2/L3 explicit

Today's QA (QA Strategist + QA Executor, 13-phase) is an **L1 baseline**. The drafts proposed an explicit ladder so future QA work has a named target. Worth adding a short "maturity level" stanza to `docs/QA_SYSTEM_BLUEPRINT.md`.

- **L1 (shipped):** app discovery, UI/API test generation, negative tests, single Strategist gate audit.
- **L2 (next):** state modeling + user-journey graphs; fuzz tests; **multi-round** Strategist↔Executor debate (see §2); explicit loop-termination rules.
- **L3 (later):** security tests, performance (e.g. k6), visual-regression, flaky-test self-healing, release-readiness scoring.

## 2. Multi-round Strategist ↔ Executor debate loop
Current QA runs the Strategist as a *one-time gate audit* (Phase 11/13). The draft proposed a **continuous debate during generation** (≈ Phases 7–10): the Strategist challenges the Executor's coverage decisions, rejects shallow patterns, and forces deeper testing per risk tier, with explicit termination rules (max rounds, convergence). *Partially* present (a "debate loop protocol" exists in the `qa-strategy` skill) — the unshipped part is the *multi-round, during-generation* challenge loop, not just the post-hoc audit.

## 3. App-topology detection + GraphQL coverage (QA Executor)
- **Orthogonal topology dimensions:** `ui_present` (bool), `api_style` (enum: rest/graphql/grpc/…), `client_platform` — detected at discovery, driving which test families generate.
- **GraphQL discovery fallback chain (5 steps):** SDL file → resolvers → codegen artifacts → persisted queries → introspection.
- **Strategist risk overrides:** a `GRAPHQL_RISK_OVERRIDES` table in Strategist output; merge GraphQL ops into `api-calls.json` with risk metadata.
- **Gate 10 — GraphQL coverage audit**, tier-based (≤20 ops: full; 21–50: sampled; >50: top-20 by risk).

## 4. Autonomous durability framework (5 phases)
A reliability hardening pass for the autonomous/Supervisor loop. **Some has shipped** (Phase 1.5 PRE-FLIGHT SYNC does branch/remote drift detection; `.supervisor/logs/*.jsonl` session logging exists; `LAUNCH_PAD_RESULT` + validator). The **unshipped** parts worth keeping:
1. **State sidecar + atomic read-after-write** for Context-Keeper (verify the write landed before proceeding).
2. **Resume reconciliation** — on `--continue`, detect branch/worktree drift vs. recorded state and reconcile (beyond what Phase 1.5 covers).
3. **Failure taxonomy** — a closed enum of failure classes in `FAILURE_ESCALATION.md` + the result schemas (today failures are free-text).
4. **Idempotency guards** in EXECUTE/WORKER prompts (re-running a half-done subtask is safe).
5. **Session event envelope** — a consistent event schema across `.supervisor/logs/` entries.

## 5. Self-learning / observability (from `self-learning.md`)
The telemetry core shipped (GitHub-Issues scoring, `/telemetry`, `scripts/send-telemetry-core.sh`), but two ideas are **unshipped** and not captured elsewhere:
- **`/agent-health` command** — read accumulated telemetry/insights to surface **per-agent quality profiles** (which agents underperform, on which task types), so weak spots become visible over time. Complements `/insights` (per-run/session) with a per-agent lens.
- **Difficulty-aware / dynamic model routing** — route each subtask's model tier by estimated complexity (file count, prior failures, risk) instead of the blunt global `--cheap` flag. (Also flagged as a cost/scale open question in `SYSTEM_TWIN_ROADMAP.md §7` and as a frontier enabler.)

---

## How this relates to the roadmaps
- §1–§3 (QA leveling) is the **QA axis** — complementary to, not part of, the System Twin ladder in `SYSTEM_TWIN_ROADMAP.md`. (Though L3 perf/visual + the Twin's "provable-done / ground-truth verification" milestone M2 overlap — wire them together when M2 lands.)
- §4 (durability) supports **M1/M3** of the Twin roadmap (a trustworthy hard signal needs a durable, idempotent loop underneath it).

Discard this doc if you decide these directions aren't worth keeping — it's a parking lot, not a commitment.
