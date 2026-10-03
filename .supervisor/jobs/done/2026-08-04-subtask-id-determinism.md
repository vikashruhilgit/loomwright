# Supervisor Job: Pin a single deterministic subtask-id scheme (producer rule + parser normalization + regression test)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — 2026-08-04, v15.22.0 banner matches `loomwright/.claude-plugin/plugin.json`)
- **Git:** clean (0 files), branch: main @ 9756a62 (synced with origin/main)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (two pre-existing `.claude/worktrees/` entries from unrelated Claude sessions — they do not collide with a `feature/*` Supervisor worktree)
- **Source requirement:** .supervisor/requirements/final-state/11-subtask-id-determinism.md

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | TypeScript (`loomwright/sdk-spike/src/runner.ts`) + bash test harness (`test/self-test.sh`) + markdown prompt surfaces — all already in the repo's stack |
| 2 | Dependency Availability | GO | No new dependency. `sdk-spike` has its own `package.json` / `tsconfig.json`; the test harness is plain bash |
| 3 | Architecture Fit | GO | Producer(prompt)→consumer(parser) seam is exactly the shape CLAUDE.md describes; the change adds a rule at the producer and a normalization at the consumer, no new surface |
| 4 | Scope vs Supervisor Capability | GO | Below the Decomposition Threshold — one coherent change, ~10 files, well under 800 changed lines, no zero-overlap parallel groups |
| 5 | Hard Blockers | GO | Every target file verified present on disk (see File Impact below) |

**Overall Verdict:** GO

## Task
**Goal:** Pin the subtask-id scheme to plain numeric as an explicit producer rule, normalize legacy alpha-suffixed ids at the parser on both sides of every dependency edge, and lock both with a regression test wired into the existing self-test suite.

**Problem Statement:**
The SDK-spike runner needs a stable subtask-id contract because Launch Pad's brief format does not pin one. Currently Launch Pad emits `1, 2, 3` for some briefs and `1a, 1b, 2` for others from byte-identical input, and the parser retains whichever it parsed verbatim. This causes real breakage — the in-file comment at `loomwright/sdk-spike/src/runner.ts` (the "Ids are matched as `\d+[a-z]?`" block above the Subtask Structure table regex) records that this is "how arm 3 ended up with every dependency edge missing." Success looks like: one scheme stated as a rule at the producer, alpha-suffixed ids normalized consistently at the parser so no `from:` edge dangles, natural ordering preserved for 10+ subtasks, and a fixture test that fails if any of that drifts back.

> **Path note (load-bearing).** The source requirement writes paths plugin-root-relative (`sdk-spike/src/runner.ts`, `skills/…`, `agents/…`, `commands/…`). In this repo those all live under the `loomwright/` plugin directory. Every path in this brief is **repo-root-relative** and therefore carries the `loomwright/` prefix. Do not create a top-level `sdk-spike/`.

> **Line-ref note (load-bearing).** The source requirement cites absolute line numbers (`runner.ts:340`, `:378`, `:407`, `:421-423`, `:336-339`). Those have **already drifted** — the file grew when item 08 (worker-context-digest-lanes) landed. Verified current anchors are listed in the File Impact section below. Locate every edit site by **descriptive anchor / grep**, never by the requirement's line numbers.

## Acceptance Criteria
- [ ] Given the producer surfaces, when a reader looks for the id scheme, then plain numeric (`1, 2, 3, …`) is stated as an explicit **rule** (not merely illustrated) in `loomwright/skills/supervisor-readiness/SKILL.md` §"Subtask Structure", and mirrored in `loomwright/agents/launch-pad.md` Phase 4 DECOMPOSE and its brief template.
- [ ] Given `loomwright/commands/launch-pad.md` carries subtask-table prose/examples, when the producer rule changes, then that command body is synced in the SAME change (agent↔command mirror drift is a known trap and `check-command-sync.sh` does NOT cover Parameters-table prose).
- [ ] Given every illustrated example on the producer surfaces, when compared against the new rule, then all of them use the pinned numeric scheme (no example contradicts the rule it sits beside).
- [ ] Given a legacy `1a`/`1b` brief (`loomwright/sdk-spike/test/fixtures/launchpad-brief.md`), when `parseBrief` runs, then it still parses (the accepted-input regexes are NOT narrowed) **and** every id is normalized to the pinned numeric scheme.
- [ ] Given that same brief, when normalization is applied, then it is applied to **both sides of every edge** — the Subtask Structure table id, the `subtask_N:` / `# Subtask N` / `S<N>:` / `ST<N>:` contract-key forms, the `### Subtask N — Title` heading form, the `from:` field inside brace items, and the `from:` entries in the indented list form — so that **every `from:` resolves to a real subtask id after normalization** (zero dangling edges).
- [ ] Given a brief with 10 or more subtasks, when subtasks are ordered, then ordering is still natural (`2` before `10`) — verified by a test, not by inspection. The `10` row in `launchpad-brief.md` remains the guard and must keep passing.
- [ ] Given the new regression test, when `bash loomwright/sdk-spike/test/self-test.sh` is run, then the new test executes as part of that suite and the entire pre-existing suite stays green.
- [ ] Given the shared id-normalization helper introduced in `loomwright/sdk-spike/src/runner.ts`, when it is named, then it is named **exactly `normalizeSubtaskIds`** — this is a binding requirement, not a suggestion, because the `provides` contract below is checked against it by the `outputs_verified` gate.
- [ ] Given the repo-root gate set enumerated **from disk** (`ls scripts/check-*.sh scripts/validate-*.sh` — currently `check-command-sync.sh`, `check-contract-parity.sh`, `check-doc-currency.sh`, `check-shared-prefix.sh`, `check-skills-index-sync.sh`, `check-token-budget.sh`, `validate-version.sh`; re-enumerate at execution time rather than trusting this list), when each is run, then all pass.

## Outcomes Rubric
- Plain-numeric subtask ids are stated as an explicit RULE (not just an illustration) in `loomwright/skills/supervisor-readiness/SKILL.md`, and mirrored in `loomwright/agents/launch-pad.md`; `loomwright/commands/launch-pad.md` is synced in the same diff.
- `loomwright/sdk-spike/src/runner.ts` normalizes alpha-suffixed ids and applies the SAME mapping to table ids, contract-key ids, heading ids, and every `from:` reference — no accepted-input regex is narrowed.
- A new fixture test asserting legacy-`1a`-brief normalization with zero dangling `from:` edges exists and is invoked from `loomwright/sdk-spike/test/self-test.sh`.
- A test asserts natural ordering on a 10+ subtask brief (`2` before `10`); the existing `launchpad-brief.md` `10` row still passes.
- The PR diff contains no change to the `provides`/`requires` contract schema itself and no `schema_version` bump.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Design note — which numeric id an alpha id maps to (read before implementing)

The requirement says "convert an alpha-suffixed id to the pinned numeric scheme" but does not say *to which number*. Naive truncation (`1a → 1`, `1b → 1`) **collides** — two subtasks would share id `1` and the wave scheduler's `completed.has(r.from)` check would resolve edges to the wrong node. The collision-free, order-preserving choice is to assign each subtask its **1-based position in the existing natural sort order**:

```
1a, 1b, 2, 10   →   1, 2, 3, 4
1, 2, 3         →   1, 2, 3      (identity — already-numeric briefs are untouched)
```

This is a *recommendation, not a mandate* — if the implementer finds a better mapping, it must still satisfy: (a) injective (no two source ids collide), (b) identity on already-numeric briefs, (c) order-preserving under the existing natural sort, and (d) applied through ONE shared mapping table so both sides of every edge agree. Whatever is chosen, build the id→id map **once, after the full parse and sort**, then rewrite ids and `from:` references from that single map — do not normalize at each parse site independently, or the two sides will diverge.

**Ordering-vs-normalization hazard (Scope item 3).** The natural sort exists precisely so `1 < 1a < 1b < 2 < 10`. If ids are rewritten to `1,2,3,4` *before* sorting, the `10`-before-`2` bug returns. Normalize **after** the sort, or keep sorting on the original id.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Pin numeric subtask ids at the producer, normalize at the parser, lock with a regression test | all | 10 modify (1 conditional) + 2 conditional docs impacts declared in `lanes`, 1 create | `skills/supervisor-readiness/SKILL.md`, `skills/unit-testing/SKILL.md`, `skills/quality-checklist/SKILL.md` | LAUNCHABLE |

### Subtask contracts

```yaml
subtask_1:
provides:
  - {kind: "symbol", path: "loomwright/sdk-spike/src/runner.ts", name: "normalizeSubtaskIds"}
  - {kind: "file", path: "loomwright/sdk-spike/test/fixtures/legacy-alpha-ids-brief.md"}
  - {kind: "file", path: "loomwright/skills/supervisor-readiness/SKILL.md"}
requires: []
lanes:
  - "loomwright/sdk-spike/src/runner.ts"
  - "loomwright/sdk-spike/test/self-test.sh"
  - "loomwright/sdk-spike/test/fixtures/legacy-alpha-ids-brief.md"
  - "loomwright/sdk-spike/test/fixtures/launchpad-brief.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/skills/supervisor-readiness/SKILL.md"
  - "loomwright/agents/launch-pad.md"
  - "loomwright/commands/launch-pad.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - "CHANGELOG.md"
  - "CLAUDE.md"
external_requires: []
```

> **`normalizeSubtaskIds` is a MANDATED name, not a placeholder.** The `outputs_verified` gate is worker-*self-reported* (`loomwright/sdk-spike/src/runner.ts` pastes the `provides` list into the worker prompt; `loomwright/agents/execute-manager.md` escalates on any non-empty `outputs_gap`), so an unbound name would either halt this 1-subtask job into adjudication over a cosmetic naming choice, or be silently absorbed by the worker — defeating the gate. The §"Design note" section (above) already requires exactly ONE shared mapping helper, so pinning its name costs nothing. Do **not** amend this contract to match a different name you chose; name the helper `normalizeSubtaskIds`.
>
> The `supervisor-readiness/SKILL.md` entry is deliberately `{kind: file}` rather than a symbol: AC1 places the numeric rule *inside* the existing §"Subtask Structure" and does not require creating a new heading, so there is no identifier for a symbol entry to bind to.

## Parallelism Analysis

single-agent (no fan-out)

Below the Decomposition Threshold: the producer rule, the parser normalization, and the test are one causal chain (the test asserts the parser behavior that the rule describes), the change is ~10 files / well under 800 changed lines, and there are no two groups with zero file overlap each ≥ 3 files. No `Split reason:` applies.

### Batch Plan
- **Recommended workers:** 1

## File Impact

**Verified anchors in `loomwright/sdk-spike/src/runner.ts`** (confirmed by grep on main @ 9756a62 — locate by anchor text, not by these line numbers):

| Anchor | Current line | What it is |
|---|---|---|
| `const m = line.match(/^\|\s*(\d+[a-z]?)\s*\|…` | 374 | Subtask Structure table id |
| `const from = body.match(/\bfrom:\s*"?(?:subtask[_-]\|ST-?\|S-?)?(\d+[a-z]?)"?/i)` | 405 | `from:` inside a brace contract item |
| `const subtaskHeading = line.match(/^#{2,4}\s+Subtask\s+(\d+[a-z]?)\b/i)` | 520 | `### Subtask N — Title` heading form |
| `line.match(/^subtask_(\d+[a-z]?):/)` and the 3 alternates below it | 567–570 | contract-key id forms |
| `/^\s+-\s+"?(?:subtask[_-]\|ST-?\|S-?)?(\d+[a-z]?)"?\s*(?:#.*)?$/i` | 712 | `from:` entries in the indented list form |
| `subtasks: subtasksList.sort(…)` + the "Natural order" comment | 800–807 | the natural sort that must not regress |

| File | Action | Confidence |
|---|---|---|
| `loomwright/sdk-spike/src/runner.ts` | modify — add the shared id-normalization map, apply to all six anchors above | HIGH |
| `loomwright/sdk-spike/test/self-test.sh` | modify — wire in the new test (697 lines; follow the existing `# ---` section convention and the `LP_BRIEF` pattern) | HIGH |
| `loomwright/sdk-spike/test/fixtures/legacy-alpha-ids-brief.md` | **create** — legacy `1a`/`1b` + 10-subtask ordering fixture | HIGH |
| `loomwright/sdk-spike/test/fixtures/launchpad-brief.md` | modify (only if needed) — existing `1a`/`1b`/`2`/`10` fixture; it is the ordering guard, prefer leaving it as the legacy-input case | MEDIUM |
| `loomwright/skills/supervisor-readiness/SKILL.md` | modify — state the numeric rule in §"Subtask Structure"; §"Provides / Requires Schema" and §"Lane Declaration Schema" examples must agree | HIGH |
| `loomwright/agents/launch-pad.md` | modify — Phase 4 DECOMPOSE rule + brief template + worked example | HIGH |
| `loomwright/commands/launch-pad.md` | modify — mirror sync (Phase 4 prose + the `## Example Output` subtask table) | MEDIUM |
| `loomwright/.claude-plugin/plugin.json` | modify — version bump from 15.22.0 (counts unchanged: no new agent/command/skill/hook) | HIGH |
| `.claude-plugin/marketplace.json` | modify — version string in the description card (edit in place, never append a clause) | HIGH |
| `CHANGELOG.md` | modify — new release entry | HIGH |
| `CLAUDE.md` | modify — one-paragraph current-version banner only | HIGH |
| `loomwright/docs/prompt-token-budgets.json` | modify **only if** `check-token-budget.sh` reports a launch-pad breach (see Risk Assessment) | LOW |
| `loomwright/docs/ARCHITECTURE_CONTRACTS.md` | modify **only if** the budget file above changes — the §"Prompt Token Budgets" mirror row must move in the same commit | LOW |

> **No automated gate covers the producer-rule half.** With `supervisor-readiness/SKILL.md` declared `{kind: file}`, the deterministic `outputs_verified` gate passes whether or not the numeric rule was actually written (the file already exists). The real gates for AC1–AC3 are the Outcomes Rubric and Phase 4.5 review — confirm the rule text in the PR diff by eye.

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/supervisor-readiness/SKILL.md` (the producer authority being edited), `skills/unit-testing/SKILL.md`, `skills/quality-checklist/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Normalization applied at only some of the six parse anchors → dangling `from:` edges (the ORIGINAL arm-3 failure mode, reintroduced by the fix) | HIGH | One shared map built after parse+sort, applied to all six anchors; the new test asserts **zero dangling edges**, not merely "it parsed" |
| Naive truncation (`1a→1`, `1b→1`) collides two subtasks onto one id | HIGH | See §"Design note" — the mapping must be injective; assert distinct-id count in the test |
| Normalizing before the natural sort reintroduces the `10`-before-`2` bug | HIGH | Normalize after the sort (or sort on original ids); the 10+ ordering assertion is an explicit acceptance criterion |
| Narrowing the accepted-input regexes to force the new scheme hard-fails every existing `1a` brief | HIGH | Explicit non-goal in the source requirement — tolerance is a compatibility requirement; the test uses a legacy brief as INPUT |
| The requirement's cited line numbers are already stale (item 08 moved them) | MEDIUM | Anchors table above; locate by grep. Do not re-cite absolute line numbers in new prose — use descriptive anchors |
| Agent↔command mirror drift: `agents/launch-pad.md` edited without `commands/launch-pad.md` | MEDIUM | Explicit acceptance criterion; `check-command-sync.sh` does NOT cover this prose, so it needs a manual diff check |
| Doc-currency / version-consistency gates fail on the version bump (the ~8-surface lockstep) | MEDIUM | `corpus-task: doc-currency-green` + `version-consistent` declared in `## Executable Acceptance`; grep the OLD version string repo-wide before finalizing |
| Editing BOTH `agents/launch-pad.md` and `skills/supervisor-readiness/SKILL.md` grows launch-pad's spawn weight on two axes (it preloads that skill via frontmatter), possibly breaching its declared token budget | LOW | Headroom is ~3.5k proxy tokens (live re-measure 35157 vs budget 38673 — NOT the frozen decorative `measured` field); `check-token-budget.sh`, in the gate set enumerated by the final acceptance criterion, catches a breach. If it fires, update `loomwright/docs/prompt-token-budgets.json` **and** the mirror row in `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" in the same commit — both are declared in `lanes` as conditional impacts |
| Existing `sdk-spike` suite is 697 lines with its own conventions; an appended test could break shared state | LOW | Follow the existing `# ---` section + `LP_BRIEF` fixture-var pattern; run the FULL suite, not just the new case |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-08-04-subtask-id-determinism.md
```

---

## Outcome

- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/124
- **Branch:** feature/subtask-id-determinism (base: main @ 9756a62)
- **Version:** 15.22.0 → 15.23.0 (counts UNCHANGED: 14 agents / 21 commands / 41 skills / 24 hooks)
- **heal_loop_ran:** true
- **heal_decision:** PASS
- **heal_iterations:** 2
- **heal_remaining_issues:** 0
- **rubric_score:** 5/5
- **Until-mergeable dispatched:** false (deliberately suppressed by the /automate engine per automate-loop §7 — verified: no `.supervisor/review-dispatch/` marker for PR #124 and no live `review-pr-runner`, so the engine's ONE inline drain is the only drain)

### Verification (run by the Supervisor, not taken from the worker)

- `sdk-spike` build: clean (`tsc -p tsconfig.json`, exit 0)
- `sdk-spike/test/self-test.sh`: **85 assertions, 0 failures** (6 new normalization assertions + 1 gapped-id assertion added during heal)
- All 7 repo-root gates enumerated from disk and run: check-command-sync, check-contract-parity, check-doc-currency, check-shared-prefix, check-skills-index-sync, check-token-budget, validate-version — **all PASS**

### Heal iterations

1. **FAIL** — 1 HIGH + 2 MEDIUM. The HIGH was an AC3 violation: `agents/launch-pad.md`'s Complete Example used `from: "subtask_1"` / `"subtask_3"`, a prefixed form forbidden by the rule this same PR adds, in the same file that states it. MEDIUMs: un-bumped skill frontmatter; no gapped-numeric-id coverage. All three fixed and validated on branch before accepting.
2. **PASS** — all three fixes verified as landed (not merely claimed); one new non-gating MEDIUM (id-traceability documentation), applied.

### Findings worth carrying past this PR

- **Third sighting of the self-violating-rule pattern.** Two producer surfaces initially numbered the new anti-alpha-suffix rule `1a.` — literally the forbidden form, inside the enumeration it governs — and the worked example's `from:` values violated it too. This follows item 09's rule-forbidding-hardcoded-counts that contained a hardcoded count. No gate detects a rule violated by its own surrounding text; all three were caught only by reading. This is now a recurring class, not an incident.
- **The worker never emitted a `WORKER_RESULT` block.** It exhausted its turns twice. Every verification recorded above was performed by the Supervisor directly. The deterministic `outputs_verified`/`outputs_gap` self-report — which is what the per-subtask gate consumes — simply did not exist for this run, and nothing in the flow flagged its absence. On the Single-Agent Path that gate is silently a no-op when the worker dies before reporting.
- **The requirement was wrong in two load-bearing ways** and both were caught at Launch Pad, not execution: every path was plugin-relative (would have created a top-level `sdk-spike/`), and all five cited line numbers were already stale.
