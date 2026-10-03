# Supervisor Job: Promote the Read-Before-Write verification rule to a single named guideline + a quality-checklist pre-write gate

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean working tree on tracked files (2 untracked SPIKE docs unrelated to this change), branch: feature/otel-per-project-labeling-hook (squash-merged as PR #80 → `origin/main` commit `a1cd018`; this branch's HEAD `61a1e1d` is NOT an ancestor of `origin/main`. Supervisor should branch a fresh feature branch off `origin/main`, not extend this branch)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (current branch is a squash-merged feature branch; start fresh from origin/main)

## Feasibility (Launch Pad)

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure markdown — the plugin's native medium (guidelines + skill prompts). No code. |
| 2 | Dependency Availability | GO | No new deps. `scripts/validate-version.sh` + `scripts/check-doc-currency.sh` already present. Corpus ids `doc-currency-green` + `version-consistent` confirmed under `ai-agent-manager-plugin/scripts/eval-corpus/`. |
| 3 | Architecture Fit | GO | Advisory / non-gating, mirrors existing `AGENT_GUIDELINES.md` Core Principles + `quality-checklist` patterns. No schema change, no new hook. |
| 4 | Scope vs Supervisor Capability | GO | 3 tightly-coupled subtasks, well under 7; single serial chain (3 sequential batches, one worker). |
| 5 | Hard Blockers | GO | None. |

**Overall Verdict:** GO

## Task
**Goal:** Consolidate the three proven "verify-before-you-assert" feedback lessons into ONE named **Read-Before-Write Verification Gate** rule in `AGENT_GUIDELINES.md`, surfaced as an actionable pre-write gate in the `quality-checklist` skill — making the project's single most recurring failure mode an explicit, always-loaded house rule.

**Problem Statement:**
Agents working in this repo (and the maintainer) need a single authoritative "verify the authoritative source before asserting a detail" rule because that judgment currently lives only as three fragmented, machine-local memory lessons (`verify-invocation-shapes-from-the-file`, `verify-consumer-contract-before-for-free`, `verify-before-claiming-missing`) that are **not in the repo** and therefore never reach an agent's context.
Currently, the rule exists only in `~/.claude/.../memory/` (gitignored, machine-local, absent in worktrees). This causes the same class of error to recur — fabricated invocation shapes, "feeds Y for free" claims that Y never consumes, and "X is missing" claims from a single failed Glob — each surfacing only at review and driving PR churn.
Success looks like: one named rule in the committed shared agent contract + a matching pre-write checklist gate, so every agent that loads `AGENT_GUIDELINES.md` / the `quality-checklist` skill carries the verification habit, and the rule travels with the repo to any clone.

This is north-star **Bet 3 (write-side freshness/verification gate)**, sequencing item #1 — explicitly flagged "cheapest, highest-leverage, fully unblocked" in `ai-agent-manager-plugin/docs/SPIKES/NORTH_STAR_DIRECTION.md`.

## Acceptance Criteria
- [ ] Given `AGENT_GUIDELINES.md`, when read, then it contains exactly ONE named rule — heading **"Read-Before-Write Verification Gate"** — consolidating the three verification facets below plus a one-line targeted-freshness directive, with the unifying rationale that *a fabricated detail feels identical to a recalled fact, so it cannot be self-detected — treat "I'm pretty sure it's X" as a prompt to verify, not to write.*
- [ ] Given that rule, when inspected, then it covers all three facets: (a) **exact-shape** — never assert a command/API/dispatch/spawn shape, flag surface, or `file:line` from memory; open and read the authoritative line; (b) **consumer-contract** — before claiming a producer feeds a consumer "for free"/"X-compatible", read the consumer's WHOLE match/filter predicate (the lines bracketing the one you cite) AND its required-field list; "append-compatible" ≠ "consumed"; (c) **existence/absence** — never claim a file/symbol/reference is missing from a single Glob/Grep; confirm absence with a second tool before using "missing" as an argument.
- [ ] Given that rule, when inspected, then it includes the targeted-freshness directive: *before writing something that depends on another artifact, verify that **specific** dependency's current state — the targeted dependency, not the whole world (generalizes PRE-FLIGHT SYNC).*
- [ ] Given `AGENT_GUIDELINES.md` "Common Anti-Patterns ❌" section, when read, then a one-line anti-pattern entry references the new rule (asserting an unverified shape/contract/absence from memory).
- [ ] Given the `quality-checklist` skill, when an agent loads it, then its Implementation (during-development) checklist contains a **"Read-before-write verification"** gate item that points to the `AGENT_GUIDELINES.md` rule, using the SAME canonical rule name (no wording drift).
- [ ] Given the change is functional, when version surfaces are inspected, then `plugin.json` and `marketplace.json` both equal **14.48.0**, the two `description` vX.Y.Z strings are bumped, `CLAUDE.md` has a new top banner (oldest of the two existing banners moved to `CHANGELOG.md`) and its `plugin.json (vX.Y.Z)` line is updated, `CHANGELOG.md` has a new top entry, and the four counts remain **14 agents / 19 commands / 56 skills / 21 hooks** (UNCHANGED — no new agent/command/skill/hook).
- [ ] Given the `quality-checklist` skill bump, when inspected, then its frontmatter `version` is **"1.2.0"** with `lastUpdated: "2026-06-27"`, and the `SKILLS_INDEX.md` "Quality Checklist" row version/date cells are synced to match (the total stays **56 skills**).
- [ ] Given the completed change, when `scripts/validate-version.sh` and `scripts/check-doc-currency.sh` run, then both exit 0 (green).
- [ ] **Invariant:** the rule is advisory process guidance — it MUST NOT introduce a new gating hook, schema change, `schema_version` bump, or anything that blocks a PR/brief save.

## Outcomes Rubric
- `AGENT_GUIDELINES.md` contains a section heading "Read-Before-Write Verification Gate".
- That section's text names all three verification facets (exact-shape, consumer-contract, existence/absence) and the targeted-freshness directive.
- `ai-agent-manager-plugin/skills/quality-checklist/SKILL.md` contains a checklist item matching "Read-before-write" that references `AGENT_GUIDELINES.md`.
- `ai-agent-manager-plugin/skills/quality-checklist/SKILL.md` frontmatter `version` is "1.2.0".
- `ai-agent-manager-plugin/.claude-plugin/plugin.json` version is "14.48.0" and `.claude-plugin/marketplace.json` version is "14.48.0".
- `CHANGELOG.md` has a new top entry whose first version token is "v14.48.0".
- No new file is added under `ai-agent-manager-plugin/agents/`, `ai-agent-manager-plugin/commands/`, or `ai-agent-manager-plugin/skills/` (counts unchanged 14/19/56).

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Source material (embedded — the memory files are gitignored / machine-local / absent in worktrees, so DO NOT reference their paths)

The rule consolidates three confirmed feedback lessons. Their substance (to be paraphrased into ONE rule, NOT pasted verbatim):

1. **verify-invocation-shapes-from-the-file** — "When stating the exact shape of a command, API call, dispatcher invocation, agent-spawn form, or flag surface, open the file and read the line before asserting it. A fabricated detail feels identical to a recalled fact, so I cannot self-detect it." (Recurred 3× in one session.)
2. **verify-consumer-contract-before-for-free** — "Before claiming a producer feeds a consumer 'for free' / 'Y-compatible', read the consumer's match/filter logic AND its required-field list. Copy the ENTIRE `select(...)` chain when replicating a filter; read the lines bracketing the one you cite. An advisory record written but never matched is worse than none."
3. **verify-before-claiming-missing** — "Never say 'X doesn't exist' / 'reference is broken' from one Glob/Grep — tool results fail silently. Confirm absence with a second tool before using 'missing' as part of an argument."

Plus the north-star Bet 3 write-side framing: *before writing X, verify the freshness of the **specific** thing X depends on; stale basis → refresh or flag before committing (targeted, not a global re-scan — generalizes PRE-FLIGHT SYNC).*

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Add the "Read-Before-Write Verification Gate" rule to AGENT_GUIDELINES.md | AC1–AC4 | 1 modify, 0 create | quality-checklist | LAUNCHABLE |
| 2 | Add the pre-write gate to the quality-checklist skill + bump skill version + sync SKILLS_INDEX | AC5, AC7 | 2 modify, 0 create | quality-checklist | BLOCKED (by #1) |
| 3 | Version bump 14.48.0 + doc-currency propagation + run both gate scripts | AC6, AC8, AC9 | 4 modify, 0 create | commit | BLOCKED (by #1, #2) |

### Subtask Detail

**Subtask 1 — AGENT_GUIDELINES.md rule.** Add a new top-level section **"## Read-Before-Write Verification Gate"** (place it after "## Pre-Task Analysis (REQUIRED)" and before "## Implementation Standards" — verify the exact surrounding headings in the current file before inserting; do not trust a line number). The section states the unifying rationale + the three facets (a/b/c) + the targeted-freshness directive (see AC1–AC3). Also: add a one-line entry to the existing "## Common Anti-Patterns ❌" section referencing the rule (AC4). Optionally add a terse cross-reference from Core Principle #1 ("Quality First") — do NOT renumber the existing six principles. Use descriptive anchors, not absolute line numbers (workers inserting lines invalidate their own line refs).

**Subtask 2 — quality-checklist gate.** In `ai-agent-manager-plugin/skills/quality-checklist/SKILL.md`, add ONE bullet to the "## Implementation Checklist" (during development) list:
`- [ ] **Read-before-write verification** — before asserting any exact shape (command/API/dispatch/spawn/flag/file:line), consumer contract ("feeds Y for free" / "Y-compatible"), or absence ("X is missing"), I opened the authoritative source and confirmed it (whole predicate / required-field list / a second tool for absence). Before writing something that depends on another artifact, I verified that specific dependency's current state. "Pretty sure" → verify. (See AGENT_GUIDELINES.md → "Read-Before-Write Verification Gate".)`
Use the EXACT canonical rule name landed in Subtask 1 (read the landed heading; do not reinvent the name). Bump frontmatter `version: "1.1.0"` → `"1.2.0"` and `lastUpdated: "2026-04-13"` → `"2026-06-27"`. Update the "## Token Cost" line if the additive bullet warrants it (optional). Then sync the `ai-agent-manager-plugin/skills/SKILLS_INDEX.md` "Quality Checklist" row: version cell `1.1.0` → `1.2.0`, date cell → `2026-06-27`. The **Total: 56 skills** count is UNCHANGED.

**Subtask 3 — version + doc-currency.** Bump `ai-agent-manager-plugin/.claude-plugin/plugin.json` `version` 14.47.0 → 14.48.0 and the `vX.Y.Z` token in its `description` (counts in the description stay 14/19/56/21). Bump `.claude-plugin/marketplace.json` `version` to 14.48.0 (must equal plugin.json — enforced by validate-version.sh) and its `description` vX.Y.Z. In `CLAUDE.md`: add a new top banner for v14.48.0 (CLAUDE.md keeps only the TWO most recent banners — **remove** the current v14.46.0 banner from CLAUDE.md, which already has its own entry in CHANGELOG.md, so CLAUDE.md retains only v14.47.0 + the new v14.48.0), update the `plugin.json (vX.Y.Z)` line, leave the File Counts / hook table unchanged. Add a new top entry to `CHANGELOG.md`. Finally RUN `bash scripts/validate-version.sh` and `bash scripts/check-doc-currency.sh` and confirm both exit 0; fix any drift they report before marking done. (Note: the `## Plugin Hooks` table and count surfaces do NOT change — this release adds no hook/agent/command/skill.)

### Provides / Requires Schema

```yaml
# Subtask 1 — AGENT_GUIDELINES.md rule (LAUNCHABLE)
provides:
  - {kind: "symbol", path: "AGENT_GUIDELINES.md", name: "Read-Before-Write Verification Gate"}
requires: []
external_requires: []
```

```yaml
# Subtask 2 — quality-checklist gate + version + index (BLOCKED by #1)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/quality-checklist/SKILL.md", name: "Read-before-write verification"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/quality-checklist/SKILL.md", name: "version: \"1.2.0\""}
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/SKILLS_INDEX.md", name: "Quality Checklist"}
requires:
  - {from: "1", kind: "symbol", path: "AGENT_GUIDELINES.md", name: "Read-Before-Write Verification Gate"}
external_requires: []
```

```yaml
# Subtask 3 — version bump + doc-currency propagation (BLOCKED by #1, #2)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/.claude-plugin/plugin.json", name: "version"}
  - {kind: "symbol", path: ".claude-plugin/marketplace.json", name: "version"}
  - {kind: "symbol", path: "CHANGELOG.md", name: "v14.48.0"}
requires:
  - {from: "1", kind: "symbol", path: "AGENT_GUIDELINES.md", name: "Read-Before-Write Verification Gate"}
  - {from: "2", kind: "symbol", path: "ai-agent-manager-plugin/skills/quality-checklist/SKILL.md", name: "Read-before-write verification"}
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2 ──→ Subtask 3
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| ST1 (AGENT_GUIDELINES.md) | ST2 (quality-checklist/SKILL.md, SKILLS_INDEX.md) | none | Yes — content dependency (ST2 mirrors ST1's canonical rule name) |
| ST2 | ST3 (plugin.json, marketplace.json, CLAUDE.md, CHANGELOG.md) | none | Yes — ST3 banner describes the landed change |

- **Batches:** three sequential batches with one worker (1 → 2 → 3); no two subtasks run concurrently.
- **Recommended workers:** 1 (fast-path eligible — tightly coupled doc change; serial chain guarantees rule-name consistency and correct banner text).

## Skill References
- `quality-checklist` — the skill being extended (ST1, ST2)
- `commit` — conventional commit + version-bump discipline (ST3)

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| Rule name / wording drifts between AGENT_GUIDELINES.md and the quality-checklist gate | MEDIUM | Brief pins the canonical name "Read-Before-Write Verification Gate"; serial chain (ST2 requires ST1) forces ST2 to read the landed heading; Phase 4.5 consistency_audit catches restated-list/cross-reference drift |
| The `quality-checklist` skill is NOT preloaded into the **Worker** agent (the primary code-writer on the parallel path), so the gate item alone won't reach the worker's DO context | LOW | The `AGENT_GUIDELINES.md` rule is the universal shared contract (all agents' Shared Preamble references it); placing it in Core-Principles-adjacent + Common-Anti-Patterns maximizes reach. Re-wiring worker preloads is explicitly OUT OF SCOPE (north-star item #5 / LSP-wiring track) — note, don't fix here. |
| doc-currency / validate-version CI is strict — a missed version surface fails the gate | LOW | ST3 enumerates every surface and RUNS both scripts before marking done (also asserted via the `## Executable Acceptance` corpus tasks at Phase 4.5) |
| Over-scoping the rule into the full Bet-3 freshness machinery (PRE-FLIGHT SYNC generalization is a larger future item) | LOW | Keep the freshness facet to a single "specific dependency" directive line — explicitly NOT a new gate or hook |
| Current branch is a merged feature branch | LOW | Supervisor branches a fresh feature branch off origin/main (standard FINALIZE flow) |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 3
- **Base Branch:** main
- **Self-heal:** default ON (Phase 4.5) — this is a plugin doc-surface change; the consistency_audit + corpus-task ground-truth are exactly the right gates.
- **Heal iterations:** default (3)
- **Cost profile:** default (inherit)
- **Beads:** not required (Supervisor/Launch Pad path)

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-06-27-read-before-write-rule.md

## Outcome
- **Status:** done
- **Completed:** 2026-06-27
- **Branch:** feature/read-before-write-rule
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/81
- **heal_loop_ran:** true
- **heal_decision:** PASS
- **heal_iterations:** 0
- **heal_remaining_issues:** 0
- **rubric_score:** 7/7
- **contract_conformance:** corpus tasks (doc-currency-green, version-consistent) verified green by reviewer (validate-version.sh + check-doc-currency.sh exit 0)
- **Until-mergeable dispatched:** true
- **Until-mergeable log:** .supervisor/logs/review-pr-dispatch-20260627T122057Z-80f178ecdbad244734d6d45e2f2e24fc36ee3f98.log
