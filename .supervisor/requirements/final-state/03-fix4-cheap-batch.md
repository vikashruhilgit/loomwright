# 03 — Cheap verified batch: 4a + 4b + 4d + 4e (Fix 4)

## Problem
Four small, independently verified defects (citations in `EVAL_FINDINGS_AND_FIXES.md` Fix 4):
- **4a** leaf agents (worker, code-reviewer) cannot see their own `maxTurns` budget; orchestration
  roles can. Backwards — leaves are what you spawn ten of.
- **4b** the Phase 4.5 heal loop has no rule saying "don't re-derive what a prior gate already
  found."
- **4d** `self-heal-advisory/SKILL.md` is 110,714 bytes / 1,015 lines; Phase 4.5 needs only Part 2
  (starts ~line 508) and reads the whole file per heal iteration.
- **4e** 6 of 8 `type: prompt` hooks are model calls doing presence/shape checks a script does for
  zero tokens (~13–14 firings per measured run). The counter-example already ships:
  `validate-launch-pad-result.py` as `type: command`.

## Goal
Remove waste that needs no experiment to justify, without adding instructions where possible.

## Scope
1. 4a: surface `maxTurns` into worker + code-reviewer prose (state the caveat: advisory, ~90%
   adherence — do not expect behavior change; it is nearly free).
2. 4b: one anti-overlap sentence in the Phase 4.5 protocol (self-heal-advisory Part 2).
3. 4d: split `self-heal-advisory` at the Part 1/Part 2 boundary into two skills (or two files with
   the existing single-hop reader convention); update all Read sites, SKILLS_INDEX, budgets,
   doc-currency surfaces in lockstep.
4. 4e: convert the FIVE mechanical prompt hooks (worker, execute-manager, supervisor-runner,
   qa-executor, plan-reviewer) to `type: command` validator scripts modelled on
   validate-launch-pad-result.py (exit-0-by-contract, decide via stdout JSON — these are
   validators, so per the `|| true` convention note in CLAUDE.md, mirror the launch-pad validator
   exactly). LEAVE the code-reviewer prompt hook (cross-field + severity-cap logic) unless its
   logic is deliberately ported and tested.

## Non-goals
No routing changes (4f is item 07, strictly after 4d). No hook-count changes beyond the type
conversions; no new gates.

## Acceptance criteria
- All 4 sub-fixes landed; hook count/doc surfaces synced (check-doc-currency, skills-index-sync,
  token-budget gates green).
- Each new validator script has a self-test incl. malformed-input and missing-block cases
  (falsify, don't just confirm — nullable/missing-key lesson applies).
- Phase 4.5 reads only Part 2 post-split (verified by the Read call sites).

## Outcomes Rubric
- 4a budgets visible in leaf prose with caveat
- 4b anti-overlap rule present
- 4d split landed, all readers + gates synced
- 4e five hooks converted with self-tests; reviewer hook untouched or deliberately ported

---

## Status (appended 2026-07-29)

> The Scope / Acceptance criteria / Outcomes Rubric above are deliberately **UNCHANGED** — appended
> to, never rewritten, so the original yardstick stays auditable.

**Executed as 4a + 4b + 4e. Sub-fix 4d was DROPPED — its premise was falsified on measurement,
user-approved.**

### Why 4d was dropped

The Problem statement above says *"`self-heal-advisory/SKILL.md` is 110,714 bytes / 1,015 lines;
Phase 4.5 needs only Part 2 (starts ~line 508) and reads the whole file per heal iteration."* Each
load-bearing clause was checked against the file and against the Read call sites:

| Claim | Measured (2026-07-29, post-4b) |
|---|---|
| "Phase 4.5 needs only Part 2" | **False.** Part 2 invokes **all ten** Part 1 sections — steps 1c/1d/1e each say *"run the … step from Part 1 of this skill"*, and Part 2 calls back again at §"System Twin advisory checks", §"Contract builder", §"Advisory Twin delta line", and §"Hard-signal dual emission". No Part 1 material is unused by Phase 4.5. |
| "reads the whole file **per heal iteration**" | **False.** The Read is **once at phase entry** — `agents/supervisor.md` §"Protocol authority (read at phase entry)", Part 2 step 1a, and the same on the inline path in `commands/supervisor.md`. |
| "110,714 bytes / 1,015 lines" | **112,455 bytes / 1,016 lines.** |
| implied saving | Part 2 is **73,142 bytes / 509 lines — 65% of the file**; Part 1 proper is 36,645 B / 463 lines. A clean split would defer a minority of **one** read. |

Consequence: this file's own acceptance criterion *"Phase 4.5 reads only Part 2 post-split (verified
by the Read call sites)"* is **unsatisfiable** without moving the Part 1 procedures Part 2 calls —
i.e. undoing the split. Doing the split anyway would have moved bytes without removing a read.

**Rubric item 3 (*"4d split landed, all readers + gates synced"*) therefore FAILS by decision, not by
defect** — expected score 3/4. The rubric text is deliberately not reworded to manufacture a 4/4.

### The ordering claim 4d carried with it was also false

`EVAL_FINDINGS_AND_FIXES.md` §4f ordered item 07 *"strictly after 4d"*, and this file's Non-goals
line repeats it (*"4f is item 07, strictly after 4d"*). That modelled `self-heal-advisory` as a 4f
routing target. It is not one — `agents/supervisor.md` frontmatter preloads exactly seven skills and
`self-heal-advisory` is **absent**; it is already read-on-demand on both the agent and inline paths.
4f's real double-pay is `async-orchestration` (9,078 proxy tokens). **Item 07 is unblocked.**

### Where the correction landed

- `loomwright/docs/SPIKES/EVAL_FINDINGS_AND_FIXES.md` §4d — marked evaluated-and-rejected, original
  text preserved, measurements recorded.
- `loomwright/docs/SPIKES/EVAL_FINDINGS_AND_FIXES.md` §4f — "strictly after 4d" precondition removed
  with the reason.
- `loomwright/docs/SPIKES/EVAL_FINDINGS_AND_FIXES.md` §"Suggested order" — rows 3 and 7 annotated
  (row 3 was `Fix 4a/4b/4d/4e` + *"4d unblocks 4f"*; row 7 was *"Strictly after 4d"*). **Missed in
  the first pass** — the sweep grepped `FINAL_STATE_GOAL.md` only, leaving the void precondition live
  in the file `FINAL_STATE_GOAL.md:76` names as the Fix 4 source of truth.
- `loomwright/docs/SPIKES/EVAL_FINDINGS_AND_FIXES.md` §4e — landed-in-the-Fix-4-batch note (no
  version asserted; v15.17.0 does not exist yet); the as-measured snapshot left frozen.
- `loomwright/docs/SPIKES/EVAL_FINDINGS_AND_FIXES.md` §4f + item 07 — the stale
  `agents/supervisor.md:336` citation for the "refresh guarantee" caveat replaced with the section
  anchor (the sentence had drifted to `:361`).
- `loomwright/docs/SPIKES/FINAL_STATE_GOAL.md` — execution-order rows 3 and 7 plus the "Load-bearing
  orderings" note. No D-decision renumbered or re-litigated.
- `.supervisor/requirements/final-state/07-route-freshness-tools.md` — header precondition and the
  false *"03 did the split"* Non-goal corrected.
- `.supervisor/requirements/final-state/00-overview.md` — the *"03 (contains 4d) before 07"*
  load-bearing ordering struck through and marked VOID. Outside the original four-file scope;
  user-authorised as a scope extension because it is the index `/automate` orders the queue from.

## Status: done (shipped in v15.17.0)
- **Evidence:** CHANGELOG.md "v15.17.0 — Fix 4 cheap batch" (4a maxTurns prose in worker.md/code-reviewer.md; 4b ANTI-OVERLAP in self-heal-advisory Part 2; 4e five prompt hooks → type:command, hooks.json now 36 command / 3 prompt). 4d evaluated and REJECTED 2026-07-29 (EVAL_FINDINGS_AND_FIXES.md §4d).
- **Reconciled:** 2026-09-21 by hand — shipped via feature branch before this queue existed as a folder; nothing wrote this stamp.
