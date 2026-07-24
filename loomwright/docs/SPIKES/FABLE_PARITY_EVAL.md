# Fable-Parity Eval — pre-registered protocol

**Status:** pre-registered — runs pending (post-merge)
**Date:** 2026-07-07
**Provenance:** Fable-parity job (v15.8.0). This is the measurement half of the fable-parity spike —
the same north-star discipline as `ADVISORY_LOOP_EVAL.md` ("earn every bit of surface area with
evidence" — `NORTH_STAR_DIRECTION.md`): the spike shipped a quarantined SDK runner
(`loomwright/sdk-spike/`, opt-in via `--sdk-runner`) and an opt-in multi-voter Phase 4.5
verification (`--multi-voter-heal`); this doc pre-registers HOW we will measure whether either layer
— or the Loomwright orchestration stack itself — earns its keep, BEFORE any run is executed.
Sibling records: `SDK_RUNNER_SPIKE.md` (the capability-parity half + provisional GO/NO-GO),
`ADVISORY_LOOP_EVAL.md` (the pre-register-then-run precedent), `CODE_GRAPH_OWNERSHIP.md`
(build the harness, let the numbers decide).

---

## Question

Does the Loomwright stack measurably beat bare Claude Code on real requirements — and do the two
new opt-in layers (SDK runner, multi-voter heal) measurably beat the Loomwright default? Or is any
of these layers orchestration weight with no effect?

## Decision rule (pre-committed, stated before any run — verbatim from the requirement)

**5 requirements × 3 arms** — (1) bare Claude Code, (2) Loomwright default, (3) Loomwright +
`--sdk-runner` + `--multi-voter-heal`; **metrics:** review rounds to READY, heal_iterations,
post-merge defect findings from an independent `/code-reviewer` pass, wall tokens.

- **The SDK runner graduates to v16 ONLY if arm 3 beats arm 2 on defects or rounds without >1.5×
  token cost.** Otherwise the spike is cut (`sdk-spike/` deleted, `--sdk-runner` seam removed —
  per `SDK_RUNNER_SPIKE.md`'s provisional GO/NO-GO).
- **Loomwright must beat arm 1 (bare Claude Code) or the losing layers get cut** — per-layer: a
  layer that does not move its metric is removed, not defended.

No third outcome. "It feels better" does not count; only the metrics below count.

## Pre-registered metrics (declared BEFORE any run)

| Metric | Source | Direction |
|---|---|---|
| Review rounds to READY | POSTMORTEM_RESULT `review_rounds` / `REVIEW_HEAL_RESULT` `fix_cycles` (arm 1: manual count of review→fix cycles on the scratch branch) | lower is better |
| Phase 4.5 `heal_iterations` | SUPERVISOR_RESULT / `session_end` JSONL (arm 1: n/a — record `-`) | lower is better |
| Post-merge defect findings | ONE independent `/code-reviewer` pass on each arm's final scratch-branch diff (same reviewer configuration for all 3 arms of a requirement); count of BLOCKING + HIGH `new` findings | lower is better |
| Wall tokens | Session usage totals (session JSONL for arms 2–3; the session's own usage reporting for arm 1) | lower is better; arm 3 vs arm 2 capped at 1.5× by the decision rule |

Secondary observables (recorded, not decision inputs): `heal_decision`, `rubric_score` where the
brief has an `## Outcomes Rubric`, arm-3 `findings_raised`/`findings_refuted`/`findings_fixed`
counters (from `SUPERVISOR_RESULT.summary`), wall-clock notes.
**No metric may be added after the first run;** a metric may only be dropped with a written reason
in this file.

> **Amendment (amended 2026-07-18, before any run — additive):** **token-cost-per-subtask** is
> added as a RECORDED secondary observable for arm-3 runs: the additive per-subtask `token_usage`
> object on the SDK runner's EXECUTE_RESULT-equivalent output (worker + reviewer `usage` fields
> aggregated per subtask, plus `total_cost_usd` / `num_turns`; `proxy: true` labels synthesized
> dry-run values — real token counts are never invented). This observable is **explicitly NOT a
> decision input** — the pre-committed decision rule above (including the 1.5× arm-3-vs-arm-2
> wall-token cap) is byte-unchanged by this amendment, and the Results table below was verified
> still EMPTY at amendment time. Recorded per the pre-registration discipline: amendments are
> additive, datestamped, and made strictly before the first run.

## Protocol

1. **Corpus selection:** pick **5 requirements** (small-to-medium, orchestration-shaped — multi-file
   with at least one dependency between subtasks, so the Phase 3 loop is actually exercised); reuse
   completed historical requirements from `.supervisor/jobs/done/` where possible. **At least ONE of
   the 5 MUST have a REAL cross-subtask file dependency** (a dependent subtask that reads/imports a
   file the producer subtask creates) — the SDK runner's known live-mode gap is that `requires` only
   delays SPAWN ORDER: dependents branch from the feature branch and do NOT see producer commits
   (no Step 2a dependency materialization; `SDK_RUNNER_SPIKE.md` residual divergence 3). The corpus
   must surface that gap in the measured arm-3 comparison, not leave it theoretical.
2. **Arms (3 per requirement, 15 runs total):**
   - **Arm 1 — bare Claude Code:** the requirement text given directly to a plain session (no
     Loomwright commands), implemented on a scratch branch.
   - **Arm 2 — Loomwright default:** in-session `/autonomous` (or `/launch-pad` + `/supervisor`) with
     default flags.
   - **Arm 3 — Loomwright + `--sdk-runner` + `--multi-voter-heal`:** same as arm 2 with both opt-in
     layers ON (requires the spike runner built: `cd loomwright/sdk-spike && npm install && npm run
     build`).
3. **Isolation:** scratch branches only — **NO PRs to main from eval runs**; same base commit for
   all 3 arms of a requirement; eval branches deleted after metric extraction.
4. **Harness choice:** prefer **in-session `/autonomous`** over any API-based harness — the
   OAuth-token constraint precedent (the plugin runs on the operator's OAuth session; a headless API
   harness would need a separate API key that is not assumed to exist; same rationale as
   `ADVISORY_LOOP_EVAL.md` protocol step 5).
5. **Part-B demonstration (folded into arm-3 runs):** across the five arm-3 runs, capture **≥1 real
   refuted-finding-not-fixed demonstration** — a BLOCKING/HIGH `new` finding raised by one voter,
   refuted by the other lens, and verifiably LOGGED-not-fixed (the `findings_refuted` counter in
   `SUPERVISOR_RESULT.summary` + the finding's absence from the fix commits). This is the
   requirement's deferred "≥1 real run showing a refuted finding NOT fixed" evidence for
   `--multi-voter-heal`; if no organic refutation occurs in 5 runs, record that fact — do not
   manufacture one. **Confirm item:** for every refuted finding captured, also verify it
   **surfaced to a human** — either the run ended `ESCALATED` or the finding is logged in the PR
   record (Outcome block / `SUPERVISOR_RESULT.summary`), never silently dropped. A refuted-but-
   genuine finding vanishing without a human-visible trace is the specific failure mode the
   refute rule introduces; a demonstration that only shows "not fixed" without showing "still
   surfaced" is incomplete evidence.
6. **Budget:** **15 runs = 5 requirements × 3 arms, hard cap.** If the cap is hit before the corpus
   completes, report what exists — do not extend silently.
7. **Recording:** one row per run in the results table below, filled at run time, never
   retroactively edited (append a correction row instead).

## Corpus

Five requirements selected from `.supervisor/jobs/done/`. Selection criteria per §Protocol step 1:
small-to-medium, orchestration-shaped (multi-subtask, Phase 3 loop exercised), at least one with a
real cross-subtask file dependency. All base commits verified reachable via `git cat-file -t`.

| # | Slug | Brief | Base commit | PR | Subtasks | Cross-subtask dependency | Selection rationale |
|---|------|-------|-------------|-----|----------|--------------------------|---------------------|
| 1 | curation-anti-rot | `2026-07-23-curation-anti-rot.md` | `f55380b` | #106 | 6 (3 LAUNCHABLE batch 1 + 3 batch 2) | **YES — ST-4 requires ST-3's `write-lessons.sh supersede` verb** (kind: subcommand); ST-5a requires ST-1/ST-2 interface shapes for docs | Most recent (v15.14.0), multi-batch, largest subtask count; dependency-materialization gap will surface if arm-3's SDK runner cannot merge ST-3 into ST-4's worktree |
| 2 | rules-enforcement | `2026-07-01-rules-enforcement.md` | `872cc81` | #88 | 4 (ST-2 BLOCKED by ST-1) | **YES — ST-2 shares `commands/rules.md` with ST-1** (kind: symbol); ST-3/ST-4 advisory wiring reads ST-1's `add-rule.sh` | Multi-seam wiring (3 advisory integration points across agents/commands/scripts); BLOCKED subtask exercises dependency ordering |
| 3 | learning-loop-phase1-2 | `auto-2026-06-17-040909-learning-loop-phase1-2.md` | `516687a` | #61 | 4 (all LAUNCHABLE) | No — parallel independent subtasks | Tests fully parallel orchestration (4 independent agent-prompt edits); no dependency ordering needed; baseline for "does the orchestration add value over sequential?" |
| 4 | review-drain-worktree-isolation | `2026-06-21-review-drain-worktree-isolation.md` | `142319e` | #75 | 3 (ST-3 BLOCKED by ST-1+ST-2) | **YES — ST-3 depends on ST-1+ST-2 for accurate version bump** | Multi-dependency (ST-3 requires TWO providers); 8-file modification in ST-1 with lifecycle/cleanup/failure-injection gates |
| 5 | handoff-digest | `2026-06-28-handoff-digest.md` | `49868b1` | #82 | 4 (ST-2 BLOCKED by ST-1) | YES — ST-2 tests ST-1's `build-handoff.sh` output | Create-then-test pattern (engine + fixture-driven test); new file creation (not just modification); mirrors the `/insights` deterministic-assembler idiom |

**Dependency-materialization gap coverage (§Protocol step 1 hard requirement):** corpus entries #1
(curation-anti-rot) and #2 (rules-enforcement) each have a real cross-subtask file dependency where
a dependent subtask reads/invokes a file the producer subtask creates or modifies. Under arm 3 (SDK
runner), the known residual divergence 3 (`SDK_RUNNER_SPIKE.md`) means these dependents will branch
from the feature branch without the producer's commits — the eval must surface whether this causes
test failures or incorrect output in the measured comparison.

## Execution Runbook

Step-by-step instructions for executing each arm. All runs use the same base commit per requirement
(column "Base commit" in the Corpus table above).

### Scratch branch naming

```
eval/<slug>/arm-<N>[-<variant>]
```

Examples: `eval/curation-anti-rot/arm-1-bare`, `eval/rules-enforcement/arm-2-default`,
`eval/handoff-digest/arm-3-extras`, `eval/curation-anti-rot/arm-ablation-a-no-qa-rules`.

### Per-requirement arm execution

For each of the 5 corpus requirements, execute 3 arms from the same base commit:

**Arm 1 — Bare Claude Code (no Loomwright)**

```bash
git checkout -b eval/<slug>/arm-1-bare <base-commit>
# Start a plain Claude Code session (no plugin commands):
claude
# Paste the requirement text from the brief's ## Task / ## Goal section.
# Implement on this branch. Do NOT use /supervisor, /launch-pad, or any Loomwright commands.
# When done, record metrics (see Recording Protocol below) and exit.
```

**Arm 2 — Loomwright default**

```bash
git checkout -b eval/<slug>/arm-2-default <base-commit>
# Start a Claude Code session with the plugin:
claude
# Run the standard Loomwright flow:
/autonomous --single-iteration --requirement .supervisor/jobs/done/<brief-file>
# Or equivalently:
/launch-pad
# (paste the requirement, let it produce a brief, then:)
/supervisor job: .supervisor/jobs/pending/<saved-brief>
# Record metrics and exit.
```

**Arm 3 — Loomwright + SDK runner + multi-voter heal**

```bash
# Pre-requisite: build the SDK spike runner (once per machine):
cd loomwright/sdk-spike && npm install --no-audit --no-fund && npm run build && cd -

git checkout -b eval/<slug>/arm-3-extras <base-commit>
claude
/autonomous --single-iteration --requirement .supervisor/jobs/done/<brief-file>
# When the /supervisor step runs, pass both experimental flags:
/supervisor job: <brief> --sdk-runner --multi-voter-heal
# Record metrics and exit.
```

> **Known gap (arm 3):** the SDK runner's residual divergence 3 (`SDK_RUNNER_SPIKE.md`) means
> dependent subtasks branch from the feature branch, not from producer output. For corpus entries
> #1 and #2 (which have real cross-subtask file dependencies), arm-3 runs may surface test failures
> or incorrect output that the default path (arm 2) avoids via sequential worktree merges. This is
> the gap the eval is designed to measure.

### Ablation arms (additive amendment — budgeted separately per §Protocol step 6)

Each ablation arm modifies ONE lever. Execute from the same base commit as the corresponding
requirement's base arms. Use arm-2 (Loomwright default) as the baseline — the ablation removes one
layer from the default stack.

**Ablation (a) — minus QA rule libraries**

Replace `qa-test-patterns/SKILL.md`, `qa-gates/SKILL.md`, and `qa-strategy/SKILL.md` (combined
~1,900 lines) with a single ~50-line intent document that states the testing goals without
prescriptive patterns. The QA Executor agent prompt and Phase 3 execution are unchanged.

```bash
git checkout -b eval/<slug>/arm-ablation-a-no-qa-rules <base-commit>
# Before starting the session, create the replacement intent doc:
cat > loomwright/skills/qa-intent/SKILL.md << 'INTENT'
---
name: qa-intent
version: 1.0.0
description: Lightweight QA intent (ablation — replaces qa-test-patterns + qa-gates + qa-strategy)
---
# QA Intent
Test the implementation against the acceptance criteria. Use Playwright for E2E tests where
applicable. Verify: (1) golden path works, (2) edge cases don't crash, (3) no regressions in
existing tests. Prefer integration tests over unit tests for orchestration-shaped requirements.
INTENT
# Update qa-executor agent frontmatter to preload qa-intent instead of the three libraries.
# Then run the standard Loomwright flow:
claude
/autonomous --single-iteration --requirement .supervisor/jobs/done/<brief-file>
```

**Incident-class regression check (ablation a):** the QA rule libraries encode test-isolation
patterns, infrastructure-aware fixtures (Mailpit/MailHog), and budget zones (80/110/60). Watch for:
tests that leak state across runs, missing infrastructure detection, or budget exhaustion causing
premature test-suite termination.

**Ablation (c) — minus magic budgets/caps**

Convert hardcoded numeric budgets (Supervisor 50-call, Execute Manager 60-call, QA Executor
80/110/60, worker turn limits) to soft defaults the model may override with stated reasoning.
Modify the agent prompts to present each budget as "default N, override with justification."

```bash
git checkout -b eval/<slug>/arm-ablation-c-soft-budgets <base-commit>
# Before starting the session, edit agent prompts to soften budgets:
# - agents/supervisor.md: "budget: 50 tool calls" → "default budget: 50 tool calls (override with
#   stated reasoning if a phase requires more)"
# - agents/execute-manager.md: similar for 60-call budget
# - agents/qa-executor.md: similar for 80/110/60 zones
# Then run:
claude
/autonomous --single-iteration --requirement .supervisor/jobs/done/<brief-file>
```

**Incident-class regression check (ablation c):** magic budgets prevent runaway token spend and
context exhaustion. Watch for: sessions that consume >2× the default arm's wall tokens, phases
that loop without terminating, or context-window exhaustion causing mid-task failures.

### Recording protocol

After each arm completes, extract and record the pre-registered metrics:

| Metric | Arm 1 (bare) source | Arm 2/3 (Loomwright) source |
|--------|--------------------|-----------------------------|
| `review_rounds_to_READY` | Manual count of review→fix cycles on the scratch branch (count commits that are fix responses to review feedback) | `POSTMORTEM_RESULT.review_rounds` in `.supervisor/logs/{session_id}.jsonl` (event `postmortem_complete`), OR `REVIEW_HEAL_RESULT.fix_cycles` from the drain log |
| `heal_iterations` | N/A — record `-` | `SUPERVISOR_RESULT.heal_iterations` in `.supervisor/logs/{session_id}.jsonl` (event `session_end`) |
| `post_merge_defects` | Run ONE independent `/code-reviewer` pass on the arm's final branch diff (`git diff <base>..<arm-branch>`) — count BLOCKING + HIGH `new` findings | Same — run the SAME `/code-reviewer` configuration on each arm's diff for a fair comparison |
| `wall_tokens` | Session usage total (Claude Code reports this at session end) | `token_ledger` event in `.supervisor/logs/{session_id}.jsonl` (field `token_proxy_transcript_bytes` when `proxy: true`, or real token counts when available) |

**Secondary observables** (recorded, not decision inputs): `heal_decision`, `rubric_score` (where
the brief has an `## Outcomes Rubric`), arm-3 `findings_raised`/`findings_refuted`/`findings_fixed`
counters (from `SUPERVISOR_RESULT.summary`), wall-clock notes,
`token-cost-per-subtask` (arm-3 only, per the 2026-07-18 amendment).

### Isolation protocol

1. All eval work happens on scratch branches — **NO PRs to main from eval runs**.
2. Same base commit for all 3 arms of a requirement (enforced by the Corpus table above).
3. After metrics are extracted and recorded in the Results table, delete eval branches:
   ```bash
   git branch -D eval/<slug>/arm-1-bare eval/<slug>/arm-2-default eval/<slug>/arm-3-extras
   ```
4. Eval session logs in `.supervisor/logs/` and `.supervisor/jobs/` artifacts are retained for
   audit but are not merged to main.

### Re-run protocol (standing — per original requirement §Scope item 4)

Re-run the ablation set on every major model release (e.g., Claude 5 → Claude 6). Use the same
corpus, same base commits, same metrics. Compare cross-model results to detect release-dependent
verdicts. If a layer that was CUT on model N becomes competitive on model N+1, record the finding
but do NOT re-add the layer without a fresh eval cycle (pre-register the re-add hypothesis first).
A `model-capability` configuration knob is a possible follow-up ONLY if re-run results show
release-dependent verdicts — do not build it speculatively.

## Results (per-run — EMPTY until runs execute; no metric added after first run)

| requirement | arm | review_rounds_to_READY | heal_iterations | post_merge_defects | wall_tokens | notes |
|---|---|---|---|---|---|---|
| | | | | | | |

## Outcome

_Pending. To be filled after the 15 runs, followed by the decision-rule verdict per layer:
SDK runner graduates to v16 OR is cut; each Loomwright layer that fails to beat arm 1 is cut._
