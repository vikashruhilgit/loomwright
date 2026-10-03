# Supervisor Job: Rename `.supervisor/notify-config.json` → `.supervisor/config.json` (back-compatible)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: feature/phase2b-knowledge-sources-insights (brief planned against `main`)
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (version sequencing vs the other two pending briefs — see Risk Assessment)

## Feasibility (Launch Pad Phase 2.5)

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure bash path-resolution + markdown reference sweep |
| 2 | Dependency Availability | GO | jq (already used in the 3 reader scripts) |
| 3 | Architecture Fit | GO | The file now holds general run-behavior config (7 keys), only 1 of which is "notify" — the rename corrects a misnomer. Back-compat fallback keeps the change additive |
| 4 | Scope vs Supervisor Capability | GO | 3 subtasks (scripts / docs / migration+version), 30–45 min each |
| 5 | Hard Blockers | GO | `.supervisor/config.json` does not exist — no collision |

**Overall Verdict:** GO

## Task
**Goal:** Rename the run-behavior config file `.supervisor/notify-config.json` → `.supervisor/config.json` **with a back-compatible read fallback** (prefer the new path, fall back to the old), so existing installs that already have `notify-config.json` keep working, then sweep all current-state references.

**Problem Statement:**
The file is named `notify-config.json` but now holds **general run-behavior** config — verified keys: `auto_review`, `auto_until_mergeable`, `check_wait_timeout`, `review_check_pattern`, `auto_postmortem`, `postmortem_churn_threshold`, and only `webhook_url` is notify-related. The name misleads readers into thinking it only configures notifications. `.supervisor/config.json` is the honest name. Because the file is referenced across 18 files (and existing installs have it on disk), a bare `git mv` would silently break every reader and every doc — so this must be a **back-compatible** rename, not a raw move.

**Design decisions (Plan Review + Phase 6 should confirm):**
1. **Back-compat read, never a hard cutover.** Each reader resolves the path as: use `.supervisor/config.json` if it exists, **else** `.supervisor/notify-config.json`. No existing install breaks. (Document the precedence; the new name wins when both exist.)
2. **Writes go to the NEW path.** Any code that *writes* the config writes `.supervisor/config.json`. (Verify during ANALYZE whether `/setup` or any module writes it — the grep found no production write site; the config appears user-authored, with only the test scripts writing fixtures.)
3. **Freeze historical/draft docs.** Do **NOT** retroactively rewrite the old name in `CHANGELOG.md` (it describes what shipped under the old name) or `docs/SPIKES/ENHANCEMENT_PLAN_v15_DRAFT.md` (a frozen planning draft). Only **current-state** docs are swept. This mirrors the CLAUDE.md "frozen illustrative/historical values are not drift" rule.
4. **No new agent/command/skill/hook** — counts stay 14/18/55/19. This is a config-file rename + doc sweep + version bump only.

## Acceptance Criteria

> **AC0 (execution precondition — applies to ALL subtasks).** The 18-file reference list below is a **snapshot as of authoring**. At execution start the worker MUST re-run `grep -rln "notify-config.json"` repo-wide and treat the **live** result as authoritative — **including any references added by an earlier-merged PR**, notably the PR-create-hook PR whose On/Off docs reference `notify-config.json`. Every production *read* site in the live result gets the back-compat resolution; every current-state doc is swept; only the historical/draft files in AC7 stay frozen. If the live grep surfaces a file not in the snapshot, handle it under the correct subtask (script→#1, doc→#2/#3) rather than skipping it.

1. **AC1** — Given an install with ONLY `.supervisor/notify-config.json` (legacy), when any of the 3 reader scripts (`dispatch-pr-review.sh`, `dispatch-pr-postmortem.sh`, `send-webhook.sh`) reads config, then it resolves and reads the legacy file unchanged (back-compat preserved).
2. **AC2** — Given an install with `.supervisor/config.json`, when a reader resolves config, then it prefers the new file; when BOTH exist, the new file wins.
3. **AC3** — Given neither file exists, when a reader resolves config, then it behaves exactly as today (defaults apply; fail-safe, no error).
4. **AC4** — Any code that WRITES the config writes `.supervisor/config.json` (the new path).
5. **AC5** — The 2 test scripts (`test-dispatch-pr-review.sh`, `test-dispatch-pr-postmortem.sh`) are updated to exercise BOTH paths: a new-path fixture AND a legacy-path-fallback case; the suites pass.
6. **AC6** — All **current-state** doc references in **subtask 2's scope** (command docs `autonomous.md`/`review-pr.md`/`supervisor.md`/`agent-help.md`, agent `supervisor.md`, skills `autonomous-loop`/`review-heal`, docs `ARCHITECTURE_CONTRACTS.md`/`RESULT_SCHEMAS.md`/`TELEMETRY.md`) name `.supervisor/config.json`, each with a one-line note that the legacy `notify-config.json` is still read as a fallback. **Scope boundaries:** the 3 reader scripts + 2 test scripts are swept in subtask 1 (AC1–5); **`README.md` is owned by subtask 3** (AC8), not subtask 2. When sweeping `skills/review-heal/SKILL.md`, also **correct its line ~558 prose** which wrongly states `notify-config.json` "lives in `state-management/SKILL.md`" — drop/repoint that false cross-pointer. **`state-management/SKILL.md` is NOT swept** (verified: 0 `notify-config` references — adding it would chase a phantom).
7. **AC7** — `CHANGELOG.md` and `docs/SPIKES/ENHANCEMENT_PLAN_v15_DRAFT.md` are left UNCHANGED (historical/draft — frozen).
8. **AC8** — In subtask 3, `README.md` is handled **end-to-end** (so it is touched by exactly ONE subtask): (a) its current-state `notify-config.json` references are renamed to `.supervisor/config.json` with the legacy-fallback note, AND (b) a migration note is added (README/docs): the rename, the back-compat fallback, and how to migrate (rename the file, or let the fallback handle it). Optional: a one-time auto-copy `notify-config.json`→`config.json` when only the legacy file exists.
9. **AC9** — Version bumped; `check-doc-currency.sh` + `validate-version.sh` green; counts unchanged 14/18/55/19.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Back-compat path resolution in readers + tests | AC 1–5 | 5 modify, 0 create | error-handling | LAUNCHABLE |
| 2 | Current-state reference sweep (docs/agents/skills/commands — **excl. README**) | AC 6, 7 | 10 modify, 0 create | quality-checklist | LAUNCHABLE |
| 3 | README (sweep + migration note) + version bump + doc-currency | AC 8, 9 | 4 modify, 0 create | quality-checklist | BLOCKED (by #1, #2) |

### Provides / Requires Contracts

```yaml
# Subtask 1 — Back-compat path resolution in readers + tests (LAUNCHABLE)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/scripts/dispatch-pr-review.sh", name: "config.json"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/scripts/dispatch-pr-postmortem.sh", name: "config.json"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/scripts/send-webhook.sh", name: "config.json"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/scripts/test-dispatch-pr-review.sh", name: "fallback"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/scripts/test-dispatch-pr-postmortem.sh", name: "fallback"}
requires: []
external_requires: []

# Subtask 2 — Current-state reference sweep (LAUNCHABLE; no file overlap with #1)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/commands/supervisor.md", name: "config.json"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/review-heal/SKILL.md", name: "config.json"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/docs/ARCHITECTURE_CONTRACTS.md", name: "config.json"}
requires: []
external_requires: []

# Subtask 3 — Migration note + version bump + doc-currency (BLOCKED by #1, #2)
provides:
  - {kind: "symbol", path: "README.md", name: "config.json migration"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/.claude-plugin/plugin.json", name: "version"}
  - {kind: "symbol", path: "CHANGELOG.md", name: "rename entry"}
requires:
  - {from: "1", kind: "symbol", path: "ai-agent-manager-plugin/scripts/dispatch-pr-review.sh", name: "config.json"}
  - {from: "2", kind: "symbol", path: "ai-agent-manager-plugin/commands/supervisor.md", name: "config.json"}
external_requires: []
```

**Contract note:** subtasks 1 (scripts) and 2 (docs) have **no file overlap** → both LAUNCHABLE in parallel. Subtask 3 (migration note + version + doc-currency) fans in after both — the migration note describes the renamed behavior and doc-currency must validate the integrated tree.

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 (scripts) ─┐
                     ├─→ Subtask 3 (migration + version + doc-currency)
Subtask 2 (docs)    ─┘
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none (scripts vs docs) | NO |
| Subtask 1 | Subtask 3 | none (but #3 requires #1) | YES (dependency) |
| Subtask 2 | Subtask 3 | none (but #3 requires #2) | YES (dependency) |

### Batch Plan
- **Batch 1:** Subtask 1, Subtask 2 (parallel — no overlap)
- **Batch 2:** Subtask 3 (after both)
- **Recommended workers:** 2
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/error-handling/SKILL.md` |
| 2 | `skills/quality-checklist/SKILL.md` |
| 3 | `skills/quality-checklist/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Bare rename breaks existing installs** | HIGH | Back-compat read (new path preferred, legacy fallback) — AC1–AC3 + test cases; never a hard cutover |
| **Retroactively renaming historical docs** (CHANGELOG / SPIKES draft) | MEDIUM | AC7 freezes them — they describe what shipped under the old name; only current-state docs are swept (the "frozen historical values are not drift" rule) |
| **Missed read/write site** leaves a dangling old-name reader with no fallback | MEDIUM | Authoritative site list verified by grep (3 prod readers + 2 tests + 13 prose refs); ANALYZE must re-grep `notify-config.json` at execution time and confirm zero un-migrated *production read* sites remain (docs may still mention the legacy name as the fallback) |
| **Version collision across the 3 pending briefs** (#66=14.33.0, hook brief=14.34.0, this=14.35.0) | MEDIUM | Assign the version at EXECUTION time based on what is on `main`; target **14.35.0** assuming #66 then the hook brief land first. If executing out of order, pick the next free minor and reconcile |
| **Fallback precedence ambiguity** (both files present) | LOW | AC2 pins it: new file wins when both exist; documented in the migration note |

## Configuration
- **Workers:** 2
- **Mode:** parallel
- **Estimated batches:** 2
- **Base Branch:** main
- **Target version:** 14.35.0 (assumes #66 / v14.33.0 + the PR-create-hook brief / v14.34.0 land first — assign at execution time; see Risk Assessment)

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-06-18-rename-notify-config-to-config-backcompat.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-06-18T15:41:21Z
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/68
- **Branch:** feature/rename-notify-config-backcompat
- **Files changed:** 22
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1 (review passed first pass; 0 fix iterations)
- **Red team advisory:** disabled
- **Summary:** Back-compat rename .supervisor/notify-config.json → .supervisor/config.json. 3 subtasks (scripts+tests / doc sweep / README+version). Consistency-audit review PASS, no new BLOCKING/HIGH. Gates green; version 14.35.0; counts 14/18/55/20.
