# Advisory-Loop Counterfactual Eval — pre-registered protocol

**Status:** pre-registered — paired runs pending (post-merge)
**Date:** 2026-07-07
**Provenance:** Knowledge-corpus curation job (v15.7.0). This is the measurement half of the
north-star discipline ("earn every bit of surface area with evidence" — `NORTH_STAR_DIRECTION.md`):
the advisory seams (prior-churn signal from `read-postmortem.sh`, lessons from `read-lessons.sh`,
project memory, twin/bridge context) now have curation + staleness so the corpora can forget — this
doc pre-registers HOW we will measure whether feeding them back in actually helps, BEFORE any run is
executed. Sibling records: `NORTH_STAR_DIRECTION.md`, `CODE_GRAPH_OWNERSHIP.md` (the validated-then-
parked precedent this protocol imitates: build the harness, let the numbers decide).

---

## Question

Do the advisory seams (prior-churn / lessons / memory context injected into Launch Pad planning and
Supervisor Phase 4.5 self-heal) **measurably reduce review churn** on real requirements — or are they
prompt weight with no effect?

## Decision rule (pre-committed, stated before any run)

- **No measurable benefit** on the pre-registered metrics ⇒ **cut the losing seams** (per-seam: a seam
  that does not move its metric is removed, not defended).
- **Measurable benefit** ⇒ **the number goes in the marketplace description at the next release**
  (e.g. "advisory churn signal: −N review rounds on paired re-runs") — evidence-priced surface area.

No third outcome. "It feels helpful" does not count; only the metrics below count.

## Pre-registered metrics (declared BEFORE any run)

| Metric | Source | Direction |
|---|---|---|
| Review rounds to READY | POSTMORTEM_RESULT `review_rounds` (= the drain's effective review rounds / `REVIEW_HEAL_RESULT` `fix_cycles`; via `/pr-postmortem` or the automate drain) | lower is better |
| Phase 4.5 `heal_iterations` | SUPERVISOR_RESULT / `session_end` JSONL | lower is better |
| `rubric_score` (where the brief has an `## Outcomes Rubric`) | SUPERVISOR_RESULT | higher is better |

Secondary observables (recorded, not decision inputs): `heal_decision`, `self_heal_misses`,
wall-clock notes. No metric may be added after the first paired run; a metric may only be dropped
with a written reason in this file.

## Protocol

1. **Corpus selection:** pick **6–10 completed historical requirements** from `.supervisor/jobs/done/`
   + their merged PRs, restricted to runs that actually exercised the advisory seams (the
   `knowledge_sources_used` field / session logs identify them).
2. **Paired re-runs:** re-run a sample of **3–5** of those requirements via **in-session `/autonomous`**
   on a **scratch branch**, twice each with the SAME requirement text: once with advisory seams
   **disabled**, once **enabled**. Same base commit for both arms of a pair.
3. **Isolation:** scratch-branch only — **NO PRs to main from eval runs**; eval branches are deleted
   after metric extraction.
4. **Budget:** token cost capped at **5 re-runs** total (the 3–5 sample IS the cap; a pair counts as
   two runs of one requirement). If the cap is hit before the sample completes, report what exists —
   do not extend silently.
5. **Harness choice:** prefer **in-session `/autonomous`** over any API-based harness — the
   OAuth-token constraint (the plugin runs on the operator's OAuth session; a headless API harness
   would need a separate API key that is not assumed to exist) is why the synthetic eval harness was
   deferred in the first place; in-session runs use what is already there.
6. **Recording:** one row per run in the results table below, filled at run time, never
   retroactively edited (append a correction row instead).

## Seam-disable switch (design decision — DEFERRED)

The mechanism for the "disabled" arm — a temporary `--no-advisory` master switch vs per-seam env
gates (e.g. `LOOMWRIGHT_DISABLE_CHURN_SEAM=1`) — is **deferred to the eval-execution brief**. Two
constraints are pre-committed regardless of mechanism:

- It must be **default-ON-advisory, opt-out only** — the switch exists for this eval; shipping
  default-OFF seams would invalidate the "enabled" arm as the production configuration.
- It must be inert when unset (no behavior change for every existing caller).

## Results (per-run — empty until paired runs execute)

| requirement | seams | review_rounds_to_READY | heal_iterations | rubric_score | notes |
|---|---|---|---|---|---|
| | | | | | |

## Outcome

_Pending. To be filled after the paired runs, followed by the decision-rule verdict (cut seams OR
publish the number)._
