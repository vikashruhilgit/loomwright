# System Twin — Execution Roadmap

> **Status:** living roadmap (authored 2026-06-05, plugin at **v14.13.0**). The "you are here → north star
> → milestone ladder" anchor for the System Twin product direction.
>
> **Relationship to other docs (no duplication):**
> - North-star thesis + the three pillars: the `system-twin-product-direction` project memory.
> - Knowledge-axis plan (memory / flywheel / notifications): `ENHANCEMENT_PLAN_v15_DRAFT.md` (this doc is the **execution axis** that extends it).
> - This doc owns: *current state*, *the destination*, and *the ordered milestones to get there* (each milestone = a future Launch Pad brief).

---

## 0. Purpose

So we always know **what we have**, **where we're going**, and **the next safe step** — without re-deriving it each session. Update the "Status" column as milestones land.

The one-line product thesis:
> *Everyone else rents you a coder who starts cold every morning. We grow you an engineer who's been on the team for years and gets better every week.*

The endgame, in four words: **point at repo → "own this."**

---

## 1. North star (the keystone + three pillars)

**Keystone — the System Twin:** a living, structured, agent-maintained, continuously-verified model of *this specific codebase* (architecture graph, contracts/invariants, data flows, behavioral specs, known failure modes, decision history). Not prose docs (prose rots) — a structured artifact that planning reads, verification checks against, and the flywheel writes to. **The moat:** after N runs the Twin *is* the customer's encoded system understanding — uncopyable, the only asset that appreciates, and the thing the platform structurally won't build for you.

**Three pillars stand on it (one system, not pick-one):**
1. **Predict-before-touch** — blast-radius/impact analysis from the Twin's dependency graph + incident history, at planning time.
2. **Provable-done** — outcome contracts written first; converge until green against the *running* app; ship a reproducible proof bundle. Evidence, not confidence-theater.
3. **Compounding-expertise** — the OBSERVE→DISTILL→PROMOTE→APPLY→MEASURE flywheel re-grounded so MEASURE keys on a **hard** signal (executable outcomes + benchmark), not the soft `rubric_score`.

---

## 2. Where we are today  ·  **YOU ARE HERE**

The **foundation + first compounding are SHIPPED to `main` (v14.13.0)** and the Twin has written its first real contracts. Everything is **advisory / propose-only / subordinate to CLAUDE.md** — nothing gates or self-applies yet (by design).

| Shipped | PR | What it gave us |
|---|---|---|
| v14.9.0 | #25 | `/capability-check --strategy` — product-direction strategist (this roadmap's outward-looking scout) |
| v14.10.0 | #26 | **Twin foundation** — per-subsystem `SYSTEM_CONTRACT` artifacts, sole-writer (`write-system-contract.sh`) + hash-chained provenance + read-side gate, Phase 4.5 conformance check, benchmark, Launch Pad blast-radius read — all advisory |
| v14.11.0 | #27 | `/obsidian` vault projection + **first live Twin write** (2 contracts) |
| v14.12.0 | #28 | Twin inline-delta — hard-signal line in the SELF_HEAL completion tail (+2 contracts) |
| v14.13.0 | #29 | clickable desktop notifications (adjacent; not Twin) |

**Twin store today:** 7 hash-chained, gate-valid contracts under `.supervisor/twin/` (gitignored, local) — accruing ~1–2 per run (was 4 at authoring).

**Each pillar — what exists vs. what's missing:**

| Pillar | In miniature today (advisory) | Not yet |
|---|---|---|
| **1 Predict** | Launch Pad reads contract → blast-radius prediction **+ incident history + derived dependents graph** (M1 ✅, v14.15.0); first consume has fired | Predictions proven *useful* across many runs (maturity, not a feature gap) |
| **2 Prove** | Phase 4.5 conformance check (advisory, never blocks) + a **canary** benchmark (`selftest_pass_count`, fixed corpus) + the **eval instrument** (`run-eval.sh` over a task corpus, `pass_rate` fitness signal — M2a ✅, v14.17.0) + a **generic ground-truth execution** step (`run-ground-truth.sh` runs a brief's declared `## Executable Acceptance` `cmd:`/`corpus-task:` checks in Phase 4.5, advisory — M2b slice 1a ✅, v14.19.0) | The QA Executor Playwright muscle auto-dispatched for web-app repos (M2b **slice 1b**, deferred); the fitness instruments + self-tests now run in CI advisorily (M2b **part-2a ✅**, v14.20.0); auto-running the full agent loop / **headless `claude` generation** in CI against the eval corpus remains (M2b **part-2b**, deferred) |
| **3 Compound** | Hard-signal fields written to `SUPERVISOR_RESULT` + `session_end` JSONL; `build-insights.sh` aggregates; inline delta surfaces; `/dreaming` can read drift | MEASURE keys partly on soft `rubric_score`; the hard signal exists but is **not yet trusted/load-bearing** |

**Net (as of v14.21.0):** the *spine* is in and advisory; **M0 + M1 shipped, M2a (the eval instrument) shipped**, **M2b slice 1a shipped** — a generic executable-acceptance **ground-truth execution** step (`run-ground-truth.sh`) is now wired into Phase 4.5 (advisory), so the gate can run a brief's declared `cmd:`/`corpus-task:` checks and report a hard pass/fail — and **M2b part-2a shipped** (v14.20.0): CI now auto-runs the three deterministic fitness instruments (advisory, written to the Step Summary) plus the full self-test suite (hard gate) on every push/PR to `main`. The Twin is accumulating (7 contracts) with incident-history + a derived blast-radius graph. We have predict + prove + compound — none of it gating yet. **Next rung: M2b slice 1b** (auto-dispatch the QA Executor's Playwright muscle for web-app repos) **+ M2b part-2b** (drive `claude` headless in CI to *generate* solutions / run the full agent loop against the corpus).

**v14.21.0 — self-heal hardening (Pillar 2 sharpening, advisory):** Phase 4.5 now reviews the integrated PR with a sharper lens: the `consistency_audit` directive mainly makes the Code Reviewer's existing auto-expand explicit for the plugin repo, while the genuinely new cross-repo lever is a repo-agnostic **Self-Heal Miss-Class Checklist** (validation parity, numeric-falsy coercion, positional-arg call sites, branch coverage, count/cross-ref drift) — the fixer sweeps the whole *class* of a flagged finding rather than the single instance, and Launch Pad emits `## Executable Acceptance` for plugin-self doc-surface briefs so `ground_truth` runs the doc/version invariants instead of `skipped`. Closes the "heal reports PASS yet the PR still takes 3–6 post-PR review rounds" blind spot. No milestone flip — still advisory.

---

## 3. Where we want to reach (the endgame)

Point the system at a repo and say **"own this."** It then: maintains a live Twin (background sync after every merge); proactively watches for dependency rot / security advisories / drift / perf regressions; proposes the roadmap from what it knows about the system; executes with **provable** outcomes; and the human moves from *reviewer-of-code* to *director-of-an-engineer* — set intent, approve outcomes, stop babysitting diffs. **A permanent AI engineer on staff who accumulates seniority.**

---

## 4. The milestone ladder (M0 → M5)

Each milestone is a future Launch Pad brief (or a few). The **advance-gate** column is the evidence required before climbing to the next rung — *trust is earned on the benchmark, not granted by calendar.*

| # | Milestone | Requires | Status | Advance-gate |
|---|---|---|---|---|
| **M0** | **Twin foundation** | contracts written/read, advisory | ✅ **DONE** (v14.10–14.12) | — |
| **M1** | **Twin becomes *trustworthy*** | (a) accumulate contracts to cover the system; (b) enrich the contract schema with a real dependency graph + **incident-history** field; (c) first real *consume* — a run that touches a contracted subsystem fires the conformance check AND a blast-radius prediction | ✅ **DONE** (v14.15.0 #31 — `incident_history` + `twin-graph.sh`; first consume fired on PR #30 = `advisory_violations:1`; Twin at 7 contracts) | met |
| **M2** | **Ground-truth verification** (Pillar 2 real) | wire QA Executor's Playwright/app-execution into Phase 4.5; outcome contracts as **executable acceptance tests**; evolve the benchmark from *canary* → real **outcome fitness function** | 🟡 **M2a SHIPPED** (v14.17.0 — the eval **instrument**: `scripts/run-eval.sh` runner/scorer + corpus format + 4-task seed corpus + `EVAL_RESULT` schema + `scripts/test-run-eval.sh` self-test; `pass_rate` M/N is the real fitness signal). **M2b slice 1a SHIPPED** (v14.19.0 — the **generic executable-acceptance ground-truth path**: `scripts/run-ground-truth.sh` runs a brief's declared `## Executable Acceptance` `cmd:`/`corpus-task:` checks in Phase 4.5 and emits a `GROUND_TRUTH_JSON` hard signal, advisory; `scripts/test-run-ground-truth.sh` self-test). **M2b part-2a SHIPPED** (v14.20.0 — CI now auto-runs the three deterministic fitness instruments (`run-eval.sh`/`run-ground-truth.sh`/`run-benchmark.sh`) advisorily into the Step Summary, plus the full self-test suite as a hard gate, on every push/PR to `main`). **DEFERRED:** M2b **slice 1b** (auto-dispatch QA Executor's Playwright app-execution for web-app repos; `qa-executor:` checks are recognized-but-skipped today) and M2b **part-2b** (drive `claude` headless in CI to *generate* solutions — the full Launch Pad→Supervisor agent loop against the corpus). | The gate can *run the software* and produce a hard pass/fail on real behavior, reproducibly |
| **M3** | **Promote advisory → enforcing** | flip conformance/benchmark from advisory to **gating** (block a bad PR) | 🔴 NOT STARTED — a deliberate, evidence-gated human flip | The hard signal has demonstrably caught real regressions on the benchmark without false-positives over a defined window |
| **M4** | **Proactive driver** | a scheduled/triggered watcher that opens PRs *unprompted*, behind **four guardrails** (durable cadence < 7-day expiry, per-run budget, circuit-breaker, heartbeat) | 🔴 NOT STARTED — explicitly **deferred to P5** in the v15 draft | M3 trustworthy + the four guardrails designed in from day one |
| **M5** | **Director model** | human sets intent + approves **outcomes**, stops reviewing diffs | 🔴 NOT STARTED — emerges from M1–M4 | Outcomes trustworthy enough that diff-review is redundant |

### Frontier-AI enablers (cross-cutting accelerants)
Each makes a milestone cheaper/stronger; adopt opportunistically, not as standalone goals:
- **Test-time compute + verifiers (best-of-N):** fan out N solutions in worktrees, executable verifier picks the winner → strengthens **M2/M3**.
- **Persistent long-horizon agents + cheap structured extraction:** keep the Twin continuously synced as a background pass → **M1**.
- **Learning from execution traces (process reward):** the benchmark + outcome contracts are a reward signal for routing/prompt/lesson selection → **M3**.
- **Adversarial self-play:** Red Team ↔ Code Reviewer co-evolve; a found failure-class becomes a permanent gate → **M2**.

---

## 5. Non-negotiable principles (what keeps "own this" *safe*)

The single most dangerous idea in this whole vision is **a system that acts on its own writes** (auto-trusted memory, unsupervised PRs — v15 draft §7). These principles are what make the climb safe; none are optional:

1. **Advisory-first → earn trust → promote.** Never flip straight to autonomous. Advisory signal must *prove* itself on the benchmark before it's allowed to gate (M3) or act unprompted (M4).
2. **Human-gated / propose-only / subordinate to CLAUDE.md.** Memory and the Twin are advisory; on any conflict, the human layer wins. The system may *propose* changes to its own gates/agents; a human applies them.
3. **Decoupling.** Projections (insights, vault) are read-only and never become dependencies of the engine.
4. **Sole-writer + provenance** for any accumulated state (contracts, memory) — tamper-evident, read-side-gated.
5. **Thin vertical slices.** Every milestone is independently useful; no big-bang.
6. **Anti-rebloat.** Deepen existing agents/phases; minimize new commands/agents (counts are watched: 14/16/51/19).
7. **Build the benchmark *before* wiring APPLY.** The reward signal must be hard before the system reinforces on it — else it compounds noise.

---

## 6. Immediate queue (next 1–3 moves)

1. **Run the polish brief** `2026-06-05-polish-gate-and-delta.md` (bump its version target to **v14.14.0** — main has moved to v14.13.0). Bonus: it touches the contracted `format-twin-delta.sh`, so it should be the **first run to *consume* the Twin** (blast-radius prediction + a real conformance check) — the M1 "first consume" signal to watch for.
2. **M1 enrichment brief:** extend the `SYSTEM_CONTRACT` schema with an explicit dependency graph + **incident-history** field, and seed incident facts from `failed/` briefs / self-heal findings / red-team. (Small, advisory.)
3. **M2b slice 1b + part-2b (the big remaining build):** M2a (eval instrument), M2b slice 1a (the generic `run-ground-truth.sh` executable-acceptance path wired into Phase 4.5, advisory), and M2b **part-2a** (CI auto-runs the three deterministic fitness instruments advisorily + the full self-test suite as a hard gate) have shipped (v14.17.0 / v14.19.0 / v14.20.0). Next: **slice 1b** — auto-dispatch the QA Executor's Playwright/app-execution muscle for web-app repos (today `qa-executor:` checks are recognized-but-skipped) — and **part-2b** — drive `claude` headless in CI to *generate* solutions for generative corpus tasks (the full Launch Pad→Supervisor agent loop against the corpus; needs `ANTHROPIC_API_KEY`, a per-run token budget, a circuit-breaker). This is the structural unlock for "provable-done" and the prerequisite for every milestone above it.

---

## 7. Open decisions / risks to resolve as we climb

- **`cmd:` trust mitigation — interim valve shipped (v14.19.0); prompt-level control owed by M2b slice 1b, hard prerequisite before any gating.** The M2b slice 1a ground-truth runner executes arbitrary `bash -c` from a brief's `## Executable Acceptance` `cmd:` bullets, automatically and unattended in Phase 4.5 (incl. under `/autonomous`, where the brief is machine-authored). **Interim guard now in place:** Supervisor Phase 4.5 passes `run-ground-truth.sh --no-cmd` on the `--non-interactive`/`/autonomous` path, so machine-authored `cmd:` bullets are NOT executed unattended (skipped as `unverified`/`cmd_disabled`; `corpus-task:` still runs). This is a safety valve; the prompt-level controls now back it. The documented "review `cmd:` bullets at Plan Review" mitigation is **no longer prose-only** — `plan-reviewer.md` Criterion 14 inspects the `## Executable Acceptance` section and `launch-pad.md` / `supervisor-readiness/SKILL.md` carry the authoring convention. Status of the slice-1b work (the first two are **hard prerequisites before M3 flips advisory → gating**):
  - [x] **Plan Reviewer check** — Criterion 14 (`agents/plan-reviewer.md`) classifies `## Executable Acceptance` bullets and emits a LOW `executable_acceptance` issue listing any `cmd:`/bare bullets (advisory today; escalates to NEEDS_HUMAN/FAIL at M3). Skips silently when the section is absent.
  - [x] **Launch Pad authoring convention** — machine-authored briefs emit `corpus-task:` bullets only, never `cmd:`/bare shell (`agents/launch-pad.md` Phase 5 + `skills/supervisor-readiness/SKILL.md` §"`## Executable Acceptance`"). `cmd:` is reserved for human authorship.
  - [ ] Re-evaluate whether the interactive path should also default to `--no-cmd` now that the Plan Reviewer control exists (left open — decide after this detection layer has soak time).
- **part-2b harness token constraint (④) — defaults to a no-paid-credit OAuth token, must report per-run usage.** The future M2b **part-2b** synthetic / headless-`claude` eval harness (driving the full Launch Pad→Supervisor agent loop in CI against the corpus) **defaults to `CLAUDE_CODE_OAUTH_TOKEN`** — a Claude Code subscription token that requires **no paid API credits** — rather than a pay-per-token `ANTHROPIC_API_KEY`, and it **must report per-run token usage** so cost is observable before any gating decision. This refines the "needs `ANTHROPIC_API_KEY`, a per-run token budget, a circuit-breaker" notes in §4/§6: the OAuth token is the default; `ANTHROPIC_API_KEY` is only a fallback.
- **Trustworthiness threshold for M3:** what benchmark evidence (catch-rate, false-positive ceiling, window) justifies flipping advisory → enforcing? Define it *before* M3, not during.
- **Benchmark evolution:** today it's a canary on the hard-signal pipeline, not a measure of real output quality. M2 must turn it into a real fitness function (fixed task corpus with known-good outcomes, dogfooded on this repo).
- **(2026-06-19 direction) The M3 trust-threshold instrument is the own-run confusion matrix.** Catch-rate / false-positive evidence is computed by harvesting the heal signal from done-brief `## Outcome` blocks across all repos + backfilling outcome labels via `/pr-postmortem` on the live PRs, joined on PR URL — *not* a separate hand-authored corpus. Relatedly, the Twin's knowledge substrate is the **local brain** (graphify graph + the plugin's own `.supervisor/` findings as the rationale layer), built **local-first per repo**; `personal-brain` is the optional cross-repo *federation* tier, not the substrate. Full statement: `BRAIN_INTEGRATION_EVOLUTION.md` §"⚑ DIRECTION UPDATE — 2026-06-19 (local-first Twin)"; the ordered, gated execution path (and the step↔milestone mapping for M2b/M3/M4/M5) is `LOCAL_TWIN_PATH.md`.
- **Incident-history source:** where do "what broke last time" facts come from, and how are they provenance-gated against poisoning?
- **M4 guardrails:** the proactive driver is the highest-risk rung — do not start it until the four guardrails are designed in.
- **Cost/scale:** continuous Twin sync + best-of-N fan-out have real token cost; gate behind difficulty-aware routing.

---

## 8. Provenance

Authored 2026-06-05 from the System Twin sessions (PRs #25–#28 shipped the foundation + first compounding). Extends `ENHANCEMENT_PLAN_v15_DRAFT.md` (knowledge axis) and the `system-twin-product-direction` memory (north star). Update the Status columns (§2, §4) and the queue (§6) as milestones land.
