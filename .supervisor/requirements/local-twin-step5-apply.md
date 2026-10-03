# Requirement: Local Twin Step 5 — APPLY (wire the findings→community bridge into review + planning)

> Source plan: `ai-agent-manager-plugin/docs/SPIKES/LOCAL_TWIN_PATH.md` §1 Step 5.
> Prereqs DONE: Steps 1–4 (measure → instrument → graph → bridge). Step 4 gate = **PROCEED**
> (retrospective hit-rate ~71% strict: for ~7 of 10 confirmed self-heal misses, prior same-area
> knowledge already existed but was never surfaced to the reviewer). This step surfaces it.

## Goal

Wire the **proven** findings→community bridge into the plugin's **Phase 4.5 self-heal review** and
**Launch Pad risk** so each run can answer *"what do we already know about the areas of code this
change touches?"* — surfacing prior misses/lessons/churn for the touched graph-communities as
**advisory** context. This is the APPLY step that aims to move the self-heal catch-rate **above its
0% baseline**. It is **advisory, non-gating, and fail-safe** throughout.

## Context (what exists)

- `graphify-out/graph.json` (994 nodes / 118 communities, gitignored, per-repo) + the `brain-context`
  read path already detect a graph by file presence.
- The Step-4 bridge builder is a **scratch spike** at `.supervisor/scratch/local-twin-step4/build_bridge.py`
  → emits a per-community index (`bridge.{json,md}`): for each community, its top files + the attached
  findings (prior misses / churn / lessons, with miss-class). Join: `finding.changed_paths →
  graph node.source_file → node.community`.
- The dial (`scripts/measure-heal-signal.*`) measures the catch-rate this step is trying to improve.

## Scope

1. **Graduate the bridge builder** from `.supervisor/scratch/local-twin-step4/` into a shipped,
   re-runnable `ai-agent-manager-plugin/scripts/` tool (engine + thin wrapper) **+ a self-test**,
   mirroring how `measure-heal-signal` was graduated in Step 2b. READ-ONLY toward the graph/findings;
   writes only under a gitignored output dir. Re-runnable over the current graph + findings.

2. **CORE — wire the bridge into Phase 4.5 self-heal review.** Before the integrated-diff review,
   resolve the diff's changed files → their graph-communities → the bridge's attached prior
   findings, and surface that **"area knowledge"** (prior misses + their miss-classes for these
   areas) to the `code-reviewer` as **advisory context** it should weigh. This is the lever for
   the recurring miss-classes (drift / cross-ref / the behavioral ones).

3. **Wire into Launch Pad risk** — at planning, surface prior-churn risk for the areas a goal will
   touch (the same bridge lookup, scoped to predicted file impact), as a Risk Assessment input.

4. Use/extend the **`brain-context`** read path as the integration seam (read-on-demand, NOT
   preloaded; advisory). The bridge read mirrors the graph read.

## Hard constraints (invariants — do not break)

- **Advisory / non-gating:** NEVER changes `heal_decision`, a review verdict, or any gate; NEVER
  blocks a PR. The `CODE_REVIEW_RESULT` stays the sole gating signal.
- **Fail-safe:** no graph / no bridge / missing tooling (no python / no jq) ⇒ **silent no-op**,
  behave EXACTLY as today. Most repos have no graph — they must be entirely unaffected. **A *stale*
  graph is NOT silenced** — per the staleness rule below it still emits, downgraded to a "hint"
  caveat (only an *absent* graph/bridge is the no-op). Silencing on staleness would gut the feature:
  the gitignored graph is rebuilt only on `/graphify` runs, so in an active repo it is almost always
  stale-vs-HEAD, and community-level area knowledge is coarse and robust to minor drift.
- **READ-ONLY** toward the graph + findings; the graph + bridge stay **gitignored** runtime state.
- Keep the two review lenses independent (do not homogenize CI review and self-heal review).
- Honor the staleness rule (graph authoritative for committed structure only; never for files the
  session is editing).

## Measurement / gate (forward-looking)

Success = the dial's **FN/recall trends favorably on PRs created AFTER this wiring** (watched via
`measure-heal-signal` / `/insights`). This step does **NOT** flip anything to gating (that's Step 6).
No new required gate is introduced.

## Acceptance Criteria

- [ ] Given a repo WITH a graph+bridge, when Phase 4.5 reviews a diff touching a community that has prior recorded misses, then the reviewer receives that area-knowledge as advisory context (observable in the review output) — and it never changes the verdict by itself.
- [ ] Given a repo WITHOUT a graph, when any phase runs, then behavior is unchanged (the bridge read is a silent no-op).
- [ ] Given the graduated bridge tool, when run, then it rebuilds the per-community index from the current graph + findings, READ-ONLY, gitignored output, exit 0 on missing graph/python.
- [ ] Given the change, when the bridge self-test + `check-doc-currency.sh` + `validate-version.sh` run, then all green.
- [ ] No `heal_decision` / gate / verdict can be changed or blocked by the bridge (advisory-only verified).

## Non-Goals

- No advisory→gating flip (Step 6). No `/setup brain` / federation (Step 7).
- No new required review gate. No change to the independence of the two review lenses.
- Do not make any plugin behavior *depend* on a graph existing.

## Housekeeping

- Version bump + CHANGELOG + CLAUDE.md banner; doc-currency counts updated for the new script.
- Add the bridge tool's self-test to the suite.

## Status: brief-shipped

Job `.supervisor/jobs/done/2026-06-23-local-twin-step5-apply.md` completed (reconciled from the job lifecycle, not self-reported).
Acceptance criteria are NOT machine-verified here — review them before promoting this to `## Status: done`.
