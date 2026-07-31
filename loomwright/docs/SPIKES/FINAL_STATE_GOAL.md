# FINAL STATE GOAL — the track we do not divert from

**Date fixed:** 2026-07-28 (owner + assistant session, post tree-and-find eval)
**Purpose:** the single durable record of the diagnosis, the owner's decisions, and the target
end-state. Everything here was already researched, measured, or decided — **do not re-research or
re-litigate it.** If a future session disagrees with something here, it must cite new evidence and
amend this file, not silently work around it.

**Evidence base (do not re-derive):** `EVAL_FINDINGS_AND_FIXES.md` (Fixes 1–7, every claim
`file:line`-cited), `FABLE_PARITY_EVAL.md` (pre-registered protocol + arm 1/2/3 rows),
`SDK_RUNNER_SPIKE.md`, PRs #109–#113 (all merged), `NORTH_STAR_DIRECTION.md`.

---

## The root cause, in one paragraph

The plugin encodes **2024-era distrust of the model as mandatory structure** — forced subtask
fan-out, 4 stacked review passes, 258k+ tokens of preloaded prompt inventory, six prompt-instructed
bookkeeping mechanisms, model-call hooks doing presence checks — and **nothing anywhere asks whether
a step is needed for THIS task.** Claude Code and the model have since absorbed most of what that
structure compensated for. Measured consequence: **6.4× cost and 4× wall clock vs bare Claude Code
for the same defect outcome (0/0)** on corpus entry #1. The fix direction everywhere is the same:
**counter-pressure and thresholds, not deletion** — keep isolation/review/validation as insurance
that activates above a stated bound; default to the cheap path below it.

---

## Owner decisions (standing — cite this section instead of re-asking)

| # | Decision | Consequence |
|---|---|---|
| D1 | **The SDK runner is the chosen substrate, not an experiment.** "If it's not working, we fix it" — no more GO/NO-GO framing. The arm-3 CUT stands as an honest eval record of an unfinished artifact; both blockers are already fixed (PR #111, merged). | Fix it forward; re-run arm 3 as a second row. Never delete `sdk-spike/`. |
| D2 | **End state is a standalone application** wrapped around the SDK runner (post-SDK completion). The plugin's judgment layers (Twin, lessons, rules, review lenses) ride on top of it. | Ports-and-adapters: 82% of scripts are already vendor-neutral; the runner replaces the prompt-orchestration core. |
| D3 | **Single-agent is the default; fan-out is the exception** and needs a stated reason (file conflict, exceeds one context, genuine parallelism). Sizing intelligence lives at **Launch Pad/Orchestrator** (they decide subtask count today — verified; Supervisor only executes). | Fix 1(a)(b)(c). Kills the 6.4×. |
| D4 | **Two review lenses, not four+ passes.** Keep Phase 4.5 (sees working tree + brief + rubric) and CI review (independent context). Per-subtask review dies with D3; the drain becomes heal-only (its channel-draining role is NOT duplicative — it heals CI findings). **SHIPPED 2026-07-30 in v15.18.0 — amended, not deviated:** "the drain becomes heal-only" landed as **heal-only by default PLUS an evidence-gated "Earned Fallback Review"** (`skills/review-heal/SKILL.md` §"Until-Mergeable Mode"), not an unconditional cut. Reason for the amendment: the live verification this decision itself called for (see Execution order item 4) found PR #117 (a workflow-touching PR) got a `claude-review` check green in 14s with **zero** posted comments — `claude-code-action` self-skips on any workflow-touching PR and still exits 0 — so an unconditional heal-only cut would have left such a PR with exactly ONE LLM lens, the opposite of this decision's intent. The fallback runs at most one diff review per drain run, only when no review-producing lens has actually posted (read from the issue-comment channel, never `--json reviews`), fails CLOSED toward running the review. Per-subtask review dying with D3 shipped as planned, unconditionally. | Fix 7 + 4b. Checks must be *earned*, never repeated by default. |
| D5 | **One writer for progress state, and it is a hook.** `state.md` becomes derived from the append-only log; the five other prompt-instructed mechanisms are deleted, not deprecated. (Measured: 560 hook events vs 6 agent events; state.md lied about a fully-merged job.) | Fix 3. Read-side guard already shipped (PR #110). |
| D6 | **Workers get shared context + explicit lanes.** Launch Pad's file-impact analysis is handed to workers as a per-job digest instead of thrown away; each worker gets explicit file-ownership boundaries so it cannot impact siblings' work. Cold-start re-acquisition is where the 6.4× goes. | New work; the SDK runner is the natural carrier (it composes each spawn's prompt). |
| D7 | **Session-start token floor gets attacked via the SDK**, plus 4c (unify `tools:` lists — 13 distinct lists = zero shared cache prefix) and 4f (route skills instead of preloading; note the documented "refresh guarantee" rationale must be argued, not ignored). **4f SHIPPED 2026-07-31 in v15.19.0** (see execution-order item 07) — the refresh-guarantee rationale was argued rather than discarded: it is preserved at Phase 4 as a genuine second Read, with Phase 2 PLAN now the first load. **4c REMAINS OPEN** — deferred to its own PR; record at `.supervisor/requirements/final-state/12-4c-unified-tools-lists.md`. | Composed per-spawn prompts replace 14 static ones. |
| D8 | **Everything generated must be verifiably current.** Brief staleness measured by **churn over the anticipated file set, never elapsed time** (4g: Launch Pad stamps base commit; preflight gains a **third** signal — SHIPPED v15.19.0. The original "4th" was inherited without checking the skill: `preflight-sync` §Protocol step 4 declared only TWO required signals (a)/(b), so the advisory churn signal is (c), the third). Derived-artifact freshness = twin-remediation item 06. | Data-freshness is a gate input, not a hope. |
| D9 | **Memory/CLAUDE.md curation is `/dreaming`'s job.** Store curation shipped (v15.14.0: supersede/retract/decay flags). **CLAUDE.md diet** = twin-remediation item 04, extended so `/dreaming` proposes CLAUDE.md prunes as human-gated candidates. | Nothing auto-deletes; flag-only remains the rule. |
| D10 | **Centralized user identity: parked** ("maybe later"). Recorded so it isn't re-proposed as urgent. | No work now. |
| D11 | **Eval honesty is non-negotiable.** Abort rows stay; re-runs are second rows; no metric added after first run without a loud amendment; cost (not `wall_tokens`) is the comparator for multi-agent arms; `exit 0` is not a completion signal — poll branch/PR. | Fix 5/6 rules. |

---

## Target end-state (what "done" looks like)

1. **A small task costs bare-Claude money.** One agent reads the codebase once, implements, gets
   one integrated review + CI. Target: arm-1-like cost/wall-clock on tree-and-find re-run, keeping
   the plan review, PR, and doc-drift catch.
2. **A large task earns its fan-out** past a stated threshold, executed by the **SDK runner** with
   wave materialization, shared context digest, and per-worker file lanes.
3. **State never lies:** one hook writer, derived `state.md`, resume reconciled against git ground
   truth (already shipped) — and nothing left that *can* write the lie.
4. **Two review lenses total**, each with different information; every additional pass must state
   what the earlier one couldn't see.
5. **Prompt inventory routed, not preloaded**; unified tools superset; validation hooks are scripts
   (4e: 5 of 6 prompt hooks → `type: command`; the code-reviewer hook may stay prompt if its
   severity-cap logic earns it).
6. **Freshness is checked mechanically** (base-commit stamps + churn signals + derived-artifact
   gates), and `/dreaming` curates memory AND CLAUDE.md on a human-gated loop.
7. **Standalone app** wrapping the runner + judgment layers — the Twin thesis productized.

---

## Execution order (agreed; deviations need a written reason here)

| Step | Work | Source of truth |
|---|---|---|
| 1 | **Fix 1** — decomposition threshold + true single-agent path (D3) | `EVAL_FINDINGS_AND_FIXES.md` Fix 1 |
| 2 | **Fix 3** — one writer, derived state (D5) + `.supervisor/requirements/one-writer-derived-state.md` | Fix 3 |
| 3 | **Fix 4a/4b/4e** — cheap verified batch (leaf budgets, anti-overlap sentence, prompt-hooks → scripts). **4d (split self-heal-advisory) was evaluated and REJECTED 2026-07-29** — its premise was falsified on measurement; see `EVAL_FINDINGS_AND_FIXES.md` §4d | Fix 4 |
| 4 | **Fix 7** — collapse to two lenses; drain → heal-only AFTER confirming its CI-healing role live via posted comments (D4). **SHIPPED 2026-07-30 in v15.18.0** — confirmed live first (four PRs, `reviews` empty on all, #117's 14s self-skip with zero comments), then shipped heal-only + the evidence-gated Earned Fallback Review D4's amendment records; see `EVAL_FINDINGS_AND_FIXES.md` Fix 7 "Baseline (pre-change)" for the measurement. | Fix 7 |
| 5 | **Arm-3 re-run** on tree-and-find, same base `5df1ded`, second row (D1, D11); also fix Launch Pad id non-determinism | Fix 2 remainder |
| 6 | **Fix 5** — one arm-2 run on corpus entry 3 (~$60) to learn whether the corpus can measure quality layers at all | Fix 5 |
| 7 | **Fix 4f/4g/4c** — route-not-preload (**no precondition**; the former "after 4d" dependency was void — see below), staleness stamps (D8), unify tools lists (D7). **4f + 4g SHIPPED 2026-07-31 in v15.19.0** — all 7 preloaded skills routed out of `agents/supervisor.md` (measured 51814 → 21029 spawn-time weight; 3 replaced by phase-entry Reads, 4 removed outright), Launch Pad stamps `Base commit`, preflight-sync gains advisory-only signal (c). **4c REMAINS OPEN** — deferred to its own PR per this doc's own instruction; record at `.supervisor/requirements/final-state/12-4c-unified-tools-lists.md`. | Fix 4 |
| 8 | **D6 worker context digest + lanes**, carried by the SDK runner | this file |
| 9 | **D9 CLAUDE.md diet via /dreaming** (twin-remediation 04) + remaining automate queue 03/05/06 | twin-remediation folder |
| 10 | **D2 standalone app** — planned only after 5 proves the runner end-to-end | this file |

**Load-bearing orderings:** Fix 1 before Fix 2/7 (if most runs collapse to one agent, both the
runner's fan-out path and review pass 1 shrink — decide with that knowledge, not before).

> **Correction (2026-07-29) — the "4d before 4f" ordering is REMOVED; it never existed.** This
> previously read *"4d before 4f (routing an unsplit 110k-byte skill changes when it's paid, not how
> much)"*, which treated `self-heal-advisory` as a step-7 routing target. It is not one:
> `agents/supervisor.md` frontmatter preloads exactly seven skills and `self-heal-advisory` is not
> [**state as of 2026-07-29, pre-4f** — kept in the past tense it was written in, because it is the
> evidence for the ordering correction. 4f SHIPPED in v15.19.0 and removed all seven: the
> frontmatter `skills:` key is now omitted entirely. The `self-heal-advisory`-is-absent point the
> correction turns on is unaffected.]
> among them — it is already read-on-demand at Phase 4.5 entry on both the agent and the inline
> path. 4f's real double-pay is `async-orchestration` (9,078 proxy tokens), which 4d would not have
> touched. 4d itself was separately evaluated and rejected on measurement. **Step 7 / item 07 is
> therefore unblocked and always was.** This corrects an ordering *rationale* only — no D-decision
> is renumbered or re-litigated. Detail: `EVAL_FINDINGS_AND_FIXES.md` §4d and §4f.

## Deliberately NOT doing (re-affirmed)

- Finishing the 5-requirement corpus as-is (5a unresolved → rows of zeros at $200–400).
- Cutting `--multi-voter-heal` (never ran; per-layer rule).
- Deleting `sdk-spike/` (D1).
- Generating the 6 CI-gate surfaces from one source (right idea, a quarter's work — not a fix).
- Centralized identity now (D10).
