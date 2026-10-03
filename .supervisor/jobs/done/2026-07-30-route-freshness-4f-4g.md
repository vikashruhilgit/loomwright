# Supervisor Job: Route supervisor-runner's preloaded skills (4f) + brief staleness anchor (4g)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — modified 2026-07-30)
- **Git:** clean, branch: main @ f672954 — **re-verified at Plan Review attempt 3** with
  `git status --porcelain` returning empty. (A prior review round flagged this as false because it
  was reading the session-start status snapshot, which predated the user's own `f672954` commit of
  an uncommitted CLAUDE.md edit. The tree is genuinely clean; nothing stray will be swept by
  `git add -A`.)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Worktrees:** none orphaned
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/final-state/07-route-freshness-tools.md

## Task

**Goal:** Execute item 07's 4f and 4g halves. **4f:** stop `supervisor-runner` paying for seven
frontmatter-preloaded skills when the recommended inline `/supervisor` path preloads none and reads
what it needs at phase entry — route them, or explicitly retain the double-pay with the argued
rationale. **4g:** give brief staleness an anchor — Launch Pad stamps the base commit, and
preflight-sync gains a churn signal over it.

**4c is OUT OF SCOPE for this PR — deferral already PERFORMED, not promised.** The requirement
itself mandates it: *"4c gets its own PR (plugin-wide frontmatter change)"*. The deferral record
exists on disk as of PLAN time:

- `.supervisor/requirements/final-state/12-4c-unified-tools-lists.md` — **created**, carrying 4c's
  problem / scope / acceptance criteria plus the 14-row `tools:` table verified on disk.
- The `## Queue` line for item 12 — **appended** to
  `.supervisor/automate/automate-2026-07-28-132741.md` (the run file is engine-owned; the engine
  performed this write during PLAN).

**The worker must NOT create, edit, or delete either artifact** — they already exist and are outside
this PR's diff. This bullet is provenance, not a work item.

### Verified premises (checked against source at Phase 3 + Plan Review — do not re-derive)

- **4f asymmetry is real.** `agents/supervisor.md` frontmatter `skills:` lists exactly seven:
  `workflow-management`, `async-orchestration`, `state-management`, `context-summarization`,
  `supervisor-readiness`, `commit`, `quality-checklist`. `commands/supervisor.md` frontmatter
  carries only `description` — no `skills:` field. The inline path is the existing proof that
  preloading is not required.
- **`self-heal-advisory` is NOT a 4f target** and never was — absent from that seven, already
  read-on-demand at Phase 4.5 entry on both paths. 4f's actual double-pay target is
  `async-orchestration` (~9,078 proxy tokens). The requirement's UNBLOCKED note (2026-07-29) already
  retired the false "strictly after item 03" dependency; independently re-verified.
- **The budget gate measures this, and the direction is DOWN.** `scripts/check-token-budget.sh`
  counts the agent `.md` PLUS every frontmatter-preloaded skill (its SCOPE comment says so; only
  preloaded skills count, being injected at spawn time). Removing skills from frontmatter therefore
  lowers the summed total, and the gate breaches only on `total -gt budget` — **so a drop can never
  fail the ratchet.** The `raise_rule` in `prompt-token-budgets.json` governs raises and does not
  apply here. `supervisor` currently declares `budget: 52568, measured: 51814` **with** the seven.
- **4g(a) stamp is genuinely absent.** `agents/launch-pad.md` Phase 5 step 3a currently emits only
  `- **Source requirement:** {path}` under `## Environment`. That step is the insertion point.
- **4g(b): the churn signal is the THIRD signal, not the 4th.** `skills/preflight-sync/SKILL.md`
  §Protocol step 4 declares exactly TWO required signals — **(a)** same-file overlap and **(b)**
  already-merged equivalent — plus an "Otherwise → CLEAR" fallthrough. The new churn signal is
  **(c)**. (The "4th" phrasing in `FINAL_STATE_GOAL.md` and in the source requirement was inherited
  without being re-checked against the skill; it is wrong. Insert **(c)** — do not hunt for three
  existing signals.)

### Reconciliation with twin-remediation item 06 (performed here at PLAN — not a work item)

`twin-remediation/06-derived-artifact-freshness.md` and 4g share a *pattern* but no *surface*, so
they overlap conceptually and must not be duplicated in code:

| | **item 06** | **4g (this PR)** |
|---|---|---|
| Artifact | DERIVED artifacts (`graphify-out/graph.json`, bridge output, agent-memory dirs) | A **brief** — a planning input, not a derived artifact |
| Producer | `graphify` / `build-bridge.sh` stamp at build time | Launch Pad Phase 5 PACKAGE stamps at brief-assembly time |
| Consumer | `/insights` `## Freshness`, `brain-context` age line, SessionStart nudge | Supervisor Phase 1.5 PRE-FLIGHT SYNC signal (c) |
| Signal | commits-behind + age, via a new `check-derived-freshness.sh` probe | commits-behind over the ALREADY-computed anticipated-path set, inline |

**Boundary:** 4g does **not** build item 06's probe, touch its surfaces, or generalize into a shared
freshness framework. It reuses only the *convention* — stamp an as-of sha at build time, compute
drift at read time, advisory-only — so a later consolidation stays cheap. Zero file overlap between
the two items. This reconciliation is recorded as a premise; it is NOT an acceptance criterion.

## Acceptance Criteria

- [ ] Given `agents/supervisor.md`, when the agent is spawned, then it no longer pays at spawn time
      for skills it does not need — the frontmatter `skills:` list is reduced to only those with a
      written retention rationale.
- [ ] Given the routing change, when `agents/supervisor.md` is read, then it contains **a named
      subsection** that states, for EACH skill removed from the frontmatter `skills:` list, the
      phase-entry `Read` that replaces it — and, for each skill deliberately RETAINED, the reason.
      The subsection must engage the documented "refresh guarantee for compressed contexts"
      rationale in `agents/supervisor.md` Phase 4 §"Protocol authority (read at phase entry)"
      (cite by SECTION NAME, never by line number — the former `:336` pin already drifted to `:361`)
      and state where a compaction-refresh Read is preserved because that rationale holds.
- [ ] Given `scripts/check-token-budget.sh`, when it runs after the routing change, then the
      `supervisor` row in `docs/prompt-token-budgets.json` is re-declared as **new measured weight
      plus a stated NON-ZERO margin**, and the row's `note` field records **which margin convention
      was chosen and why**. **Do NOT set `budget == measured`:** zero headroom fails the gate CLOSED
      on the very next byte added to `agents/supervisor.md`, including a Phase 4.5 heal edit inside
      this same PR.
      **Convention is deliberately left to the worker — BOTH are live in this repo, so pick one and
      justify it:** (i) the initial-budget convention, measured + ~10% (`prompt-token-budgets.json`
      `raise_rule`); or (ii) a compressed margin, which is what **this specific row's own prior
      restores actually used** — its note twice explicitly REJECTED resetting to measured + ~10%
      and restored ~1.5% / ~1.454% instead. Since 4f is a structural re-baseline (a large drop),
      not a marginal raise, the measured + ~10% convention is the more defensible default here —
      but say so in the note rather than inheriting a precedent silently.
      **Near-miss precedent, stated correctly:** four DIFFERENT rows have been bitten by thin
      headroom — `context-keeper` (12 proxy tokens), `orchestrator` (23), `plan-reviewer` (42), and
      `supervisor` (114). Only the 114 belongs to this row. (An earlier draft of this brief
      mis-attributed all four figures to the supervisor row.)
- [ ] Given `docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets", when the supervisor row is
      updated, then **all three** of its data cells are corrected by hand — **budget**, **measured**,
      and **preloaded-skill count** (currently `7`; becomes the retained count). Only the **budget**
      cell is gate-enforced (`check-token-budget.sh` compares that field alone), so the other two
      will drift GREEN if left stale — a green CI run is necessary but not sufficient here.
- [ ] Given that same section, when the supervisor row changes, then **BOTH** of its two narrative
      anchors are updated — they are separate blocks and editing only one leaves the contradiction
      alive:
      1. **Footnote ¹** — which is about the `Measured` cells. Add one sentence recording this
         re-measure (measured before → after), consistent with the existing ¹-marked exception
         convention.
      2. **The §-closing bolded frozen-metadata paragraph** — which is the block that actually says
         `measured` **and the "Preloaded skills" column** are frozen, decorative authoring-time
         metadata with the exception scoped only to the ¹-marked rows' `measured`. Add the
         `7 → N` preloaded-count carve-out **here**, because a 4f routing change is a sanctioned
         exception event (the column's *subject matter* changed, not just incidental drift).
      **Do not assume footnote ¹ carries the frozen-column statement — it does not.** Editing only
      footnote ¹ leaves the closing paragraph still asserting the column is frozen, which is
      precisely the contradiction this criterion exists to resolve.
- [ ] Given the version bump, when it lands, then **every one of the six version-annotation
      surfaces** is updated — this repo's doc-currency and version-parity gates BOTH fail CLOSED on
      these, and enumerating them partially is the exact defect that failed an earlier item's Plan
      Review in this same run:
      1. `loomwright/.claude-plugin/plugin.json` — the `version` field **and** the `vX.Y.Z` string
         inside `description` (update the version string **in place**; never append another version
         clause — anti-rebloat rule)
      2. `.claude-plugin/marketplace.json` — the `version` field **and** the `vX.Y.Z` string inside
         `description`. **This is MANDATORY on any bump, not conditional:** `validate-version.sh`
         enforces marketplace↔plugin version parity and `check-doc-currency.sh` scans the headline.
      3. `CLAUDE.md` — the `plugin.json (vX.Y.Z)` manifest annotation **and** the one-paragraph
         current-version summary
      4. `.claude-plugin/README.md` — the `plugin.json  # Plugin manifest (vX.Y.Z)` annotation
      5. `loomwright/commands/agent-help.md` — the `plugin.json  # Plugin metadata (vX.Y.Z)` annotation
      6. `CHANGELOG.md` — the release entry (full release notes belong HERE, not in CLAUDE.md)
- [ ] Given the version bump, when the doc surfaces are updated, then **historical version
      attributions are left ALONE.** `CLAUDE.md` carries `v15.18.0` in at least two places that are
      dated Fix-7 attributions ("no paired review subtask is generated at any threshold (Fix 7,
      v15.18.0)"), NOT current-version claims. Bumping those would rewrite history and is wrong.
      Likewise leave frozen the illustrative `plugin_version` / `session_end` sample values in
      `docs/RESULT_SCHEMAS.md` and `agents/supervisor.md` — they are deliberately version-agnostic.
- [ ] Given the counts, when the bump lands, then they are **UNCHANGED at 14 agents / 21 commands /
      41 skills / 24 hooks** — this change adds no agent, command, skill, or hook. Do not touch the
      count claims.
- [ ] Given Launch Pad Phase 5 PACKAGE step 3a, when a brief is assembled, then it stamps
      `- **Base commit:** {sha}` beside the existing `- **Source requirement:**` line under
      `## Environment`.
- [ ] Given a brief carrying a base-commit stamp, when Phase 1.5 PRE-FLIGHT SYNC runs, then
      `skills/preflight-sync/SKILL.md` §Protocol step 4 carries a **third signal (c)** computing
      churn over the file set it ALREADY computes:
      `git log --oneline $BRIEF_BASE_SHA..origin/$BASE_BRANCH -- $ANTICIPATED_PATHS | wc -l`.
- [ ] **Signal (c) is ADVISORY and MUST NOT, by itself, change the `CLEAR | OVERLAP | SUPERSEDED`
      classification.** This is load-bearing and is the single most likely way to get 4g wrong.
      Step 4 is literally *"Classify CLEAR | OVERLAP | SUPERSEDED using these required signals"* —
      every existing member of that list maps to a classification, and an OVERLAP verdict triggers
      a soft-gate `AskUserQuestion` that fails CLOSED with `preflight_overlap_detected` under
      `--non-interactive`. So a worker who adds (c) as a fourth *classification input* creates
      exactly the new gate the source requirement's Non-goals forbid. Signal (c) records its churn
      count in the pre-flight summary / Decisions Log for the human to read, and stops there.
- [ ] Given a stamped brief with HIGH churn but clean signals (a) and (b), when PRE-FLIGHT SYNC
      classifies, then the verdict is still **CLEAR**. Falsify it: construct that case and confirm
      no OVERLAP, no gate, no `preflight_overlap_detected`.
- [ ] Given a brief with a missing, empty, or unparseable `Base commit` stamp (every brief written
      before this change), when signal (c) runs, then it degrades **silently and fail-safe** — no
      new gate, no classification change, no error. Falsify this: hand-corrupt a stamp and confirm
      PRE-FLIGHT SYNC still classifies normally. (Requirement Non-goals: *"No new gates."*)
- [ ] Given the ordering constraint, when both 4g halves land, then (a) the stamp exists before
      (b) consumes it.
- [ ] Given the full repo gate set, when the change is complete, then all gates pass — and the gate
      set is enumerated **FROM DISK** (`ls scripts/check-*.sh scripts/validate-*.sh`), never from
      memory. (A prior run in this repo shipped a CI failure by running six of the seven gates from
      memory; `check-contract-parity.sh` was the one missed and the one that failed.)

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | 4f routing + 4g stamp/churn signal + budget & contract sync + version bump | all | 11 modify, 0 create | supervisor-readiness, preflight-sync, quality-checklist | LAUNCHABLE |

### Subtask contracts

```yaml
subtask_1:
  provides:
    - {kind: file, path: loomwright/agents/supervisor.md}
    - {kind: file, path: loomwright/agents/launch-pad.md}
    - {kind: file, path: loomwright/skills/preflight-sync/SKILL.md}
    - {kind: file, path: loomwright/docs/prompt-token-budgets.json}
    - {kind: file, path: loomwright/docs/ARCHITECTURE_CONTRACTS.md}
    - {kind: file, path: loomwright/.claude-plugin/plugin.json}
    - {kind: file, path: .claude-plugin/marketplace.json}
    - {kind: file, path: CLAUDE.md}
    - {kind: file, path: .claude-plugin/README.md}
    - {kind: file, path: loomwright/commands/agent-help.md}
    - {kind: file, path: CHANGELOG.md}
  requires: []
  external_requires:
    - {kind: tool, name: git}
    - {kind: tool, name: gh}
```

**Version bump IS in scope**, and it is why `provides` lists 11 files rather than 7: this changes
agent prompt behavior and declared budgets, so it takes a minor bump. The six version-annotation
surfaces are enumerated as their own acceptance criterion above — **all six are mandatory**, because
`check-doc-currency.sh` and `validate-version.sh` both fail CLOSED on them. Counts (14 / 21 / 41 /
24) are UNCHANGED.

**Decomposition note:** ONE subtask, per `skills/supervisor-readiness/SKILL.md` §"Decomposition
Threshold" (default one; split only for a named reason). No reason fires — and 4f and 4g both touch
`docs/prompt-token-budgets.json` and `ARCHITECTURE_CONTRACTS.md`, so a split would trip
`file-conflict` and serialize anyway. No `Split reason:` line (correct for a single-subtask brief).

## Parallelism Analysis

single-agent (no fan-out)

- **Batch 1:** Subtask 1
- Recommended workers: 1
- File overlap matrix: N/A (single subtask)

## Skill References

- `skills/supervisor-readiness/SKILL.md` — brief template, Decomposition Threshold, budget rules
- `skills/preflight-sync/SKILL.md` — the Phase 1.5 protocol 4g(b) extends with signal (c)
- `skills/quality-checklist/SKILL.md` — pre/post gates
- `skills/state-management/SKILL.md` — only if the churn signal touches state conventions

## Risk Assessment

| Risk | Severity | Source | Mitigation |
|---|---|---|---|
| 4f routing removes a skill the agent genuinely needs mid-run, breaking a phase that assumed preload | HIGH | Phase 3 analysis | For every routed skill add the corresponding phase-entry `Read` at the point of use; the inline path is the working reference for which reads are needed where |
| Budget re-declared as `budget == measured`, leaving zero headroom | HIGH | Plan Review (verified) | AC requires a stated NON-ZERO margin with the chosen convention justified in the row `note` (measured + ~10% is the suggested default, NOT mandated — this row's own prior restores used a compressed ~1.45%). Near-miss precedent is four DIFFERENT rows (context-keeper 12, orchestrator 23, plan-reviewer 42, supervisor 114) — only the 114 belongs to this row |
| `ARCHITECTURE_CONTRACTS.md` measured / preloaded-count cells drift green (only budget is gate-checked) | MEDIUM | Plan Review (verified) | AC names all three cells and states which one CI actually enforces |
| The "refresh guarantee for compressed contexts" rationale is discarded rather than argued | MEDIUM | Requirement CAVEAT (verified) | AC requires a named subsection engaging it per-skill, so the claim is diff-checkable rather than prose |
| Absolute line-number references drift as prose is inserted above them | MEDIUM | Recorded repo lesson | Descriptive section anchors only, never `file:NNN` pins (`:336`→`:361` is the worked example) |
| Churn signal turns into a gate on old briefs with no stamp | MEDIUM | Requirement Non-goals | AC requires fail-safe silent degradation AND a falsification test (hand-corrupt the stamp) |
| Version bump updates only some of the six annotation surfaces | HIGH | Plan Review (verified) | All six enumerated as their own AC; `check-doc-currency.sh` + `validate-version.sh` fail CLOSED. This exact defect failed an earlier item's Plan Review in this same run |
| Signal (c) wired as a classification input, creating the gate the Non-goals forbid | HIGH | Plan Review (verified) | AC makes (c) explicitly advisory + adds a high-churn-still-CLEAR falsification |
| Historical `v15.18.0` Fix-7 attributions in CLAUDE.md bumped as if they were current claims | MEDIUM | Phase 3 verification | AC explicitly carves them out; they are dated attributions, not current-version claims |
| Doc-currency gate misses prose the change invalidates | LOW | CLAUDE.md | Grep the OLD value repo-wide; green doc-currency is necessary but not sufficient |
| Example/placeholder version strings "fixed" to the current version | LOW | CLAUDE.md (v14.25.1) | Sample `plugin_version` / `session_end` values are deliberately frozen and version-agnostic — leave them alone |

## Configuration
- **Base Branch:** main
- **Workers:** 1
- **Mode:** single-agent
- **Cost profile:** cheap (Sonnet on execution-shaped roles)

## Outcomes Rubric
- 4f routed with trade-off argued in the PR
- 4g stamp + churn signal, in dependency order
- 4c superset + disallowedTools verification
- Token/budget gates green; measurements recorded

> **Rubric bullet 3 (`4c superset + disallowedTools verification`) will FAIL by design in this PR.**
> 4c is deferred to its own PR per the requirement's own instruction, with the deferral record
> already written (see `## Task`). The rubric is preserved **verbatim** from the source requirement
> rather than trimmed — trimming it would abort the run with `rubric_dropped_from_brief`, and
> rewording it to manufacture a clean 4/4 would be dishonest. The Rubric Grader is advisory and
> never blocks the PR; this run is `--single-iteration`, which short-circuits EVALUATE, so no
> rubric gate can BLOCK it. **One caveat, stated precisely:** the engine still reads
> `SUPERVISOR_RESULT.rubric_score` as condition 5 of its trusted auto-merge gate, so under
> `--auto-merge` a 3/4 fails that condition CLOSED and parks the item. That is the *intended*
> outcome and is identical to safe mode's default `awaiting_merge` park — and `--auto-merge` is
> opt-in, default-OFF, and not in use on this run. **An honest 3/4 is the correct outcome here.**

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-07-30-route-freshness-4f-4g.md --cheap

> `--cheap` is included explicitly so this line matches the declared `## Configuration` cost profile
> when copy-pasted. `--cheap` is passthrough-only and is deliberately NOT persisted in any run
> state, so an invocation that omits it silently runs at the full-cost profile. In this run the
> engine already supplies it via `/automate --cheap → /autonomous --single-iteration --cheap →
> /supervisor --cheap`.

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/120
- **Branch:** feature/route-freshness-4f-4g (base main, self-verified)
- **Commits:** e662244 (feature) + 5830bb7 (heal iteration 1)
- **Heal loop ran:** true
- **Heal iterations:** 1 (review FAIL: 2 HIGH drift + 3 LOW -> fix task -> re-review PASS)
- **Heal decision:** PASS
- **Fixable issues fixed:** 5 | **Remaining issues:** 0
- **Rubric score:** 3/4 (item 3 "4c superset + disallowedTools verification" FAIL BY DESIGN - 4c deferred to its own PR per the source requirement; rubric preserved verbatim rather than trimmed or reworded)
- **Gates:** 7/7 green, enumerated from disk (check-command-sync, check-contract-parity, check-doc-currency, check-shared-prefix, check-skills-index-sync, check-token-budget, validate-version)
- **Cost profile:** cheap (Sonnet on worker, reviewer, fix task)
- **Source requirement:** .supervisor/requirements/final-state/07-route-freshness-tools.md
- **Note:** the brief's own AC forbidding `budget == measured` proved load-bearing within this same PR - the heal commit grew agents/supervisor.md and measured moved 20591 -> 20713, which zero headroom would have failed CLOSED. The declared budget 22651 absorbed it.
