# 00 — Final-state queue overview (index/policy doc — NOT an implementable item)

**Authority:** `loomwright/docs/SPIKES/FINAL_STATE_GOAL.md` (merged PR #114). Every item here is one
step of that file's execution order and cites its decisions (D1–D11). If an item and the goal file
disagree, the goal file wins and the item is amended.

## Order (load-bearing, from the goal file)
01 → 02 → 03 → 04 → then 05/06 (operator-run evals) → 07 → 08 → 09 → 10.
- **01 before 05 and 04:** if most runs collapse to one agent, both the SDK runner's fan-out path
  and review pass 1 shrink — decide those with that knowledge.
- ~~**03 (contains 4d) before 07 (contains 4f):** routing an unsplit 110k-byte skill changes when it
  is paid, not how much.~~ **VOID (2026-07-29)** — kept, not deleted, so the queue order is
  auditable. 4d was evaluated and **REJECTED** (Part 2 invokes all ten Part 1 sections; the Read is
  once at phase entry), and it was never a 4f precondition anyway: `self-heal-advisory` is not a 4f
  routing target — 4f's double-pay is `async-orchestration`. **07 has no precondition.** See
  `loomwright/docs/SPIKES/EVAL_FINDINGS_AND_FIXES.md` §4d and §4f.
- **10 is blocked on 05** (standalone app planned only after the runner is proven end-to-end).

## /automate handling
- Items **05, 06** are OPERATOR-RUN eval sessions (multi-session, external repo) — `/automate`
  cannot drive them (same NO-GO as twin-remediation 07). Skip/escalate them; do not force a brief.
- Item **10** is planning-only and blocked; skip until 05 is recorded.
- Everything else is a normal code-change item.

## Supersession of the twin-remediation queue (recorded so nobody resumes it blind)
- twin-remediation **05** (orchestration-simplification-audit): **SUPERSEDED** — the eval produced
  the verdicts it was meant to propose; items 01+04 here are the executable form.
- twin-remediation **07** (parity-ablation-eval): **REDUCED** to items 05+06 here (two targeted
  runs), per the goal file's "not doing: finishing the 5-requirement corpus as-is."
- twin-remediation **04** (claude-md-diet): carried here as item 09 (extended with /dreaming hook).
- twin-remediation **03, 06, 08, 09, 10**: unaffected; 06 partially overlaps item 07 here (4g) —
  reconcile at that item's PLAN, don't duplicate.
