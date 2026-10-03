# Supervisor Job: Doc hygiene — SKILLS_INDEX parity CI check + roadmap de-staling (small)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh, v15.2.2)
- **Git:** clean, branch: main @ e374f2a (up to date with origin)
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **legacy_brief:** true (single-subtask — inter-subtask contracts vacuous)
- **Source requirement:** .supervisor/requirements/review-remediation/03-doc-hygiene-index-roadmap.md

## Task
**Goal:** Kill two recurring drift sources: (1) SKILLS_INDEX.md per-row `version:` cells (a documented doc-currency-gate blind spot; supervisor-readiness row currently reads 1.1.1 vs actual 1.1.2) get a structural CI parity check; (2) IMPROVEMENTS_ROADMAP.md gets a dated verdict banner + per-item verdict lines so nobody re-litigates solved work. Plus a one-line `/setup` pointer in both Quick Starts.

## Acceptance Criteria
- [ ] Given a new repo-root `scripts/check-skills-index-sync.sh` (bash-3.2-safe, no network), when run, then for every `loomwright/skills/*/SKILL.md` bearing a `version:` frontmatter field it asserts SKILLS_INDEX.md has a row for that skill whose version cell matches (fail with a per-skill diff list), AND asserts no index row references a nonexistent skill dir; it reads ONLY frontmatter vs index rows (structural — never dated changelog entries or example blocks). It is wired into .github/workflows/ci.yml next to the other validators as a hard gate, and the PR includes proof it fails on a deliberately-wrong version cell (one-shot negative test in a temp copy or self-test).
- [ ] Given SKILLS_INDEX.md at merge time, when the new check runs, then zero drifted rows (re-verify ALL rows against frontmatter at execution time, not just supervisor-readiness → 1.1.2; never touch a SKILL.md `lastUpdated` to make the index fit — index follows skill).
- [ ] Given loomwright/docs/IMPROVEMENTS_ROADMAP.md, when read, then a dated top banner marks it a pre-hooks.json-centralization planning snapshot with a verdict summary covering ALL 18 items, AND each item header carries an inline `**[VERDICT: RESOLVED/DEFERRED/OPEN — evidence]**` line whose verdict was RE-VERIFIED against the repo; every OPEN verdict cites a file path. **ID discipline (Plan Review finding):** the doc's real headers are globally-numbered `### 1.`–`### 18.` under `## P0/P1/P2/P3` sections — there are NO literal `P#-#` IDs. Stamp verdicts using the real header numbers (optionally annotating the tier). The requirement's composite IDs map as: P0=1–2, P1=3–8, P2=9–14, P3=15–18; its enumeration OMITS items 12 (Differentiate from /batch) and 14 (QA Failure Escalation docs) — classify those too (re-verify; likely RESOLVED/DEFERRED), and note the requirement's "19 items" vs actual 18 discrepancy in the PR description. Expected shape (each re-verified, not copied): RESOLVED ≈ items 1, 2, 7, 16, 17; DEFERRED ≈ 3, 5, 8, 9, 10, 11, 18 (+12/14 as verified); OPEN = 4 (Red Team effort), 6 (WorktreeRemove hook), 13 (RED_TEAM_RESULT schema), 15 (AGENT_GUIDELINES sweep). Current-state authority note: CLAUDE.md + hooks.json + plugin.json. Edits additive only — no item bodies deleted.
- [ ] Given README.md and .claude-plugin/README.md Quick Start sections, when read, then each contains one line: "Optional next: run `/setup` for a status dashboard and guided configuration of optional capabilities (observability, telemetry, notifications, Twin bootstrap)."
- [ ] Patch version bump 15.2.2 → 15.2.3 + CHANGELOG entry + README/CLAUDE.md banner rotation (two-most-recent convention); counts unchanged 14/21/57/21 (a repo-root script is uncounted); check-doc-currency.sh + check-command-sync.sh + validate-version.sh + the NEW check + full test-*.sh suite all green.

## Verified Evidence (Phase 3)
- SKILLS_INDEX.md:11 Supervisor Readiness row shows 1.1.1; skills/supervisor-readiness/SKILL.md frontmatter is version "1.1.2" (drift live). automate-loop row aligned at 1.2.0 (proves recurrence).
- Repo-root scripts/ hosts the 4 existing validators; ci.yml wires them as hard gates (plus the nullglob test-*.sh loop for plugin-internal self-tests — the new check is repo-root, so it needs explicit ci.yml wiring like check-doc-currency.sh, NOT the nullglob loop).
- IMPROVEMENTS_ROADMAP.md: 422 lines, ~23 item headers. CLAUDE.md already lists index version cells as a doc-currency blind spot (this closes it).
- Quick Start anchors: README.md:43, .claude-plugin/README.md:72.

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | check-skills-index-sync.sh + ci.yml wiring + index row fixes + roadmap banner/verdicts + /setup lines + version bump | 1 create, ~9 modify (SKILLS_INDEX, ci.yml, IMPROVEMENTS_ROADMAP, README, .claude-plugin/README, plugin.json, marketplace.json, CHANGELOG, CLAUDE.md) | LAUNCHABLE |

## Parallelism Analysis
- Single subtask, fast-path, 1 worker (script + the rows it validates must land atomically).

## Skills
- quality-checklist, unit-testing (negative-test discipline). Reference: scripts/check-doc-currency.sh as the style template for the new validator.

## Configuration
- base branch: main; heal iterations: default 3.

## Risk Assessment
| Risk | Severity | Mitigation |
|------|----------|------------|
| New validator false-positives on naming mismatches (index "Supervisor Readiness" vs dir `supervisor-readiness/`) | HIGH | Key rows on the dir-path cell (`` `supervisor-readiness/` ``), not the display name; structural parse of the markdown table |
| Verdict lines wrong because copied instead of re-verified | MEDIUM | AC mandates per-item re-verification with file-path evidence for OPEN items |
| bash-3.2 vs Linux CI (stat/sed flavors) | MEDIUM | Pure grep/awk like check-doc-currency.sh; run under bash locally |
| Roadmap items whose IDs don't match the requirement's list (stale numbering) | MEDIUM | Re-verify each item header against the actual doc before stamping; note discrepancies in PR |

## Test Plan
- `bash scripts/check-skills-index-sync.sh` green; negative test proof (wrong cell → non-zero + per-skill diff).
- All existing validators + full `test-*.sh` suite green; ci.yml wiring visible in the PR diff.

## Out of Scope
Closing the 4 OPEN roadmap items (item 06 covers two), SKILLS_INDEX category restructuring (item 07).

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-07-06-doc-hygiene-index-roadmap.md

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/93
- **heal_loop_ran:** true
- **heal_decision:** PASS
- **heal_iterations:** 1
- **heal_remaining_issues:** 0
- **rubric_score:** null (no Outcomes Rubric)
- **Until-mergeable dispatched:** false (default dispatch suppressed by /automate engine; owned inline drain follows)
