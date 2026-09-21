# 04 — CLAUDE.md diet: cut the largest fixed context tax + slow the doc treadmill

## Problem
CLAUDE.md loads into every session and has grown into a near-complete mirror of the docs/skills it points at (release notes, full hook table, agent invariant table, telemetry detail, pitfalls). The project caps every advisory reader at ~3000 chars while its own instruction file dwarfs them — context bloat the learning loop was meant to prevent. Every capability also carries a permanent multi-surface documentation liability (doc-currency, mirrors, count claims), which is the meta-maintenance treadmill.

## Goal
Cut CLAUDE.md to the minimum a fresh session actually needs, with one-line pointers to authoritative homes for everything else. Target: ≥50% size reduction, measured.

## Scope
1. **Move, don't delete:** release-note banners → CHANGELOG.md only (keep a 3-line "current version + counts" line); full hook table → keep in docs/ (it's already called authoritative here — relocate authority to `loomwright/docs/` and leave a pointer); telemetry section → TELEMETRY.md pointer; per-agent invariants column → agent prompts/ARCHITECTURE_CONTRACTS pointer; Common Pitfalls → a `docs/PITFALLS.md` (or lessons store) pointer, keeping only the 3–4 that bite every session.
2. **Keep:** project overview (5 lines), layout, repo-path-vs-runtime-path rule, bimodal failure philosophy, the add-agent checklist, doc-currency expectations, references.
3. **Gate compatibility:** `check-doc-currency.sh` and friends must stay green — where a scanned claim moves, confirm the gate scans its new home or adjust the scanner in the same PR (agent-command-mirror lesson: sync in one commit).
4. **Treadmill reduction — DELETE-over-gate (2026-07-23 outcome-data amendment):** the postmortem data shows doc-self-maintenance dominates review churn (12 PRs averaging 4.2 rounds; top classes = count reconciliation, SKILLS_INDEX cells, banner/version lockstep across ~8 surfaces), and the existing response — four CI gates (doc-currency / skills-index-sync / token-budget / contract-parity) — ENFORCES the duplication rather than removing it. New rule, in priority order: (a) a count/claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, the dirs themselves); (b) every other surface either derives it at build/read time or drops the number entirely (prose can say "see plugin.json", not restate "22 hooks"); (c) a sync-checking gate is the LAST resort, kept only where a consumer genuinely needs a second static copy. Concretely: audit each of the four gates — for every claim a gate checks, first try deleting the duplicated claim so the gate has nothing to check; shrink or retire gates whose scanned surface goes to zero. A number that lives in one place cannot drift. Document the resulting rule in AGENT_GUIDELINES.
5. Record before/after byte and estimated-token size in the PR description.

## Non-goals
No behavior changes, no gate weakening, no removing information from the repo (relocation only), no touching the frozen version-agnostic example values (deliberately unscanned — leave them).

## Acceptance criteria
- CLAUDE.md ≥50% smaller by bytes; every moved section reachable via an explicit pointer.
- All CI validators green; a deliberate seeded stale-claim still trips doc-currency (gate not neutered).
- Consistency sweep done in ONE pass (thorough-review lesson): repo-wide grep for each moved section's old anchors/links.

## Outcomes Rubric
- ≥50% size reduction, measured and stated
- Zero orphaned references to moved content
- Doc-currency gate verified still-effective post-move
- Duplication rule (≤2 surfaces per claim) documented

## Status: superseded-by final-state/09-claude-md-diet-dreaming.md
