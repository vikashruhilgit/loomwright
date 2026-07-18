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

> **Amendment (amended 2026-07-19, before any run — additive):** **token-cost-per-subtask** is
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

## Results (per-run — EMPTY until runs execute; no metric added after first run)

| requirement | arm | review_rounds_to_READY | heal_iterations | post_merge_defects | wall_tokens | notes |
|---|---|---|---|---|---|---|
| | | | | | | |

## Outcome

_Pending. To be filled after the 15 runs, followed by the decision-rule verdict per layer:
SDK runner graduates to v16 OR is cut; each Loomwright layer that fails to beat arm 1 is cut._
