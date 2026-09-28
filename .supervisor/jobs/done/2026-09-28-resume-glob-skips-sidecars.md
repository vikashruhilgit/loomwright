# Supervisor Job: `resume-glob` lists only run files — per-run result sidecars are never reported as incomplete runs

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** code tree clean apart from `.supervisor/` run-trail edits (run file, postmortem ledger, requirement stamps for items 01/02); branch: main == origin/main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0 (runtime plugin cache 15.108.1 == repo 15.108.1)
- **Source requirement:** .supervisor/requirements/automate-followups/03-resume-glob-lists-sidecar-artifacts.md
- **Base commit:** c8ad7a8dddb24b9930b20ab43c76fb79b0db0414

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Bash edit to one function in `automate-helpers.sh` + its self-test; markdown doc edits. |
| 2 | Dependency Availability | GO | `grep` only; no new dependency. |
| 3 | Architecture Fit | GO | Mirrors the existing `is_done`/`is_not_ready` one-line predicate style; the helper stays the one implementation of `resume-glob` (SKILL §1.5). |
| 4 | Scope vs Supervisor Capability | GO | 6 files, one coherent change ⇒ single subtask. |
| 5 | Hard Blockers | GO | None. |

**Overall Verdict:** GO

## Task
**Goal:** `automate-helpers.sh resume-glob <dir>` prints only `/automate` run files. The per-run sidecars `<run_id>.review-heal-result.md` and `<run_id>.supervisor-result.md` (SKILL `automate-loop` §6 steps 2–3) are never printed, whether transient or committed.

**Problem Statement:** `resume_glob()` iterates `"$dir"/*.md` and prints every file failing `is_done`. The sidecars share the directory and extension but carry no `## Status:` line, so they are always reported as incomplete runs. Verified live at base commit: `resume-glob .supervisor/automate` prints 4 sidecars (two runs' worth) plus the one real incomplete run. Consequences: a bare `/automate` offers continue/start-new/archive for non-runs, and under `--non-interactive-fallback` more than one "incomplete run" makes resume ambiguous, so it fails closed (`resume_ambiguous`). Two committed sidecars alone block unattended use.

## Design decisions (settled here so the worker does not choose for the owner)
1. **Option A: a shape check, not a filename rule.** Add a predicate `is_run_file() { grep -qE '^# Automate Run:' "$1" 2>/dev/null; }` next to `is_done`/`is_not_ready`. `resume_glob()` calls it BEFORE `is_done`: `is_run_file "$f" || continue`. It uses no filename assumption (no `*-result.md` pattern), so it also covers any future sidecar.
2. **Line-anchored anywhere-in-file, not "first line only".** All 16 run files on disk (15 committed + this run) carry `# Automate Run:` on line 1 (verified), but a leading blank line or front-matter must not silently hide a real incomplete run from RESUME. Hiding a real run is the worse failure. The sidecars are verbatim `## REVIEW_HEAL_RESULT` / `## SUPERVISOR_RESULT` blocks and contain no `^# Automate Run:` line (verified on all 4 on disk).
3. **Option B (rename sidecars to non-`.md`) is rejected for this item.** It changes the `.gitignore` trail semantics and three writer/reader surfaces (SKILL §6, `gate-eval`'s `review_heal_result_path`/`supervisor_result_path` consumers). The requirement's "decide separately whether committed sidecars belong in the permanent trail" is a non-goal here.
4. **`is_done` is NOT modified**, and `resolve_folder`/`resolve_backlog*` do NOT call `is_run_file`. Requirement files are not run files, and the predicate is `resume_glob`-only (same scoping discipline as decision H2 for `is_not_ready`).
5. **Test-fixture titles must change, and their assertions must not.** The existing `resume-glob` fixtures (§D0 `r1`/`r2`, the harness-port/02 negative control `paused.md`) are written with bare `# r1` / `# r2` / `# paused-run` titles. Under decision 1 the `r1` and `paused` assertions would FAIL (print nothing), inviting a "fix" that weakens them. The quieter hazard is `r2` (`## Status: done`): left with a bare title it would be excluded by `is_run_file` instead of `is_done`, so D0's "r2 done excluded" assertion would silently stop testing `is_done`. The worker retitles EVERY fixture's first line to `# Automate Run: <name>` (r2 included) and keeps every existing expected output byte-identical.

## Acceptance Criteria
- [ ] **AC1**: A fixture dir holding one `## Status: done` run file (title `# Automate Run: …`) plus both sidecars (`<id>.review-heal-result.md` starting `## REVIEW_HEAL_RESULT`, `<id>.supervisor-result.md` starting `## SUPERVISOR_RESULT`, neither with a `## Status:` line) ⇒ `resume-glob` prints nothing (empty output, exit 0).
- [ ] **AC2**: The same fixture with the run file stamped `## Status: paused` ⇒ prints exactly that run file's path.
- [ ] **AC3 (mutation control)**: A sed-built mutant copy of `automate-helpers.sh` with `is_run_file` forced to `return 0` makes AC1's fixture print the two sidecars (exactly those two paths, sorted). Gate the mutant on non-empty + differs-from-original + `bash -n` + override-actually-injected before trusting it, as in the existing harness-port/02 mutation control. Include a positive control: the unmutated script on the same fixture still prints nothing.
- [ ] **AC4 (no regression)**: §D0 and the harness-port/02 `paused` negative control still pass with their fixture titles updated per decision 5 and their expected outputs unchanged. A run file whose title line is preceded by a blank line is still listed (decision 2).
- [ ] **AC5 (docs — every surface restating the resume rule)**: each of these says RESUME lists *run files* (files carrying the `# Automate Run:` title line, checked by `is_run_file`) that are not stamped done, naming the §6 steps 2–3 result sidecars as excluded — the SKILL is the authority, other surfaces reference it rather than re-deriving:
  - `skills/automate-loop/SKILL.md`: the §1.5 `resume-glob` row, §4 step 1, §3's "Find prior runs" sentence, and the frontmatter `description` ("Smart resume = glob `*.md` for not-done"). Also correct §3's "The only other artifact is a *transient* config-backup sidecar" so it names the two §6 result sidecars too (that claim is already false at base).
  - `docs/RESULT_SCHEMAS.md` §"AUTOMATE_RUN": the "Single-file principle" paragraph's "Find prior runs" sentence and its "only other artifact" claim (same corrections), plus a statement that the `# Automate Run:` title line is load-bearing (RESUME keys on it via `is_run_file`).
  - `commands/automate.md`: "What This Does" step 1 ("RESUME first. Glob … for runs not marked `## Status: done`").
  - `scripts/automate-helpers.sh`: the `resume_glob` function header comment AND the top-of-file usage block's `resume-glob` line (`# §4 list *.md not "## Status: done"`).
- [ ] **AC6 (versioning)**: SKILL frontmatter `version` 1.7.0 → 1.7.1 + `lastUpdated`, matching the `SKILLS_INDEX.md` row (check-skills-index-sync). Plugin patch bump 15.108.1 → 15.108.2 in `plugin.json` + `marketplace.json`, plus one CHANGELOG paragraph at the top. Counts unchanged (14 agents / 24 commands / 42 skills; `hooks.json` byte-unchanged).
- [ ] **AC7 (full loop green)**: every `loomwright/scripts/test-*.sh` + root `scripts/test-*.sh` + `scripts/check-vendor-coupling.sh` + `scripts/check-doc-currency.sh` + `scripts/check-skills-index-sync.sh` + `scripts/check-token-budget.sh` + `loomwright/scripts/test-citation-drift.sh`. Run each under `bash`, not the zsh Bash-tool shell.
- [ ] **Invariants**: `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` resolves to the same 5 surfaces. No new agent/command/skill/hook. `resume-glob` still exits 0 on a missing dir.

## Non-goals
- Whether committed sidecars belong in the permanent run trail (`.gitignore` `!.supervisor/automate/*.md`). This is a separate decision per the requirement.
- Renaming or relocating the sidecars (Option B).
- The two sibling readers that also glob `.supervisor/automate/*.md`: `build-handoff.sh` (its automate-run loop) and `build-floor.sh` (`automate_runs` count). They over-count sidecars too, but they are advisory displays, not the fail-closed RESUME gate. Record them as a follow-up in the PR body. Do not edit them here.
- Any change to `is_done`, `is_not_ready`, `resolve-folder`, `resolve-backlog`.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | `is_run_file` predicate in `resume_glob`, fixture + mutation-controlled tests, SKILL/schema/command docs, patch bump | AC1–AC7, Invariants | 9 modify, 0 create | quality-checklist, unit-testing | LAUNCHABLE |

## Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "is_run_file"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-helpers.sh", name: "is_run_file"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/SKILL.md", name: "is_run_file"}
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "is_run_file"}
  - {kind: "symbol", path: "loomwright/commands/automate.md", name: "is_run_file"}
requires: []
lanes:
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/test-automate-helpers.sh"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/skills/SKILLS_INDEX.md"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/commands/automate.md"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
external_requires: []
```

## Parallelism Analysis
single-agent (no fan-out)
- **Recommended workers:** 1
- **Estimated batches:** 1

## Configuration
- **Mode:** single-agent
- **Recommended workers:** 1

## File Impact Map
| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| helper | `loomwright/scripts/automate-helpers.sh` (new `is_run_file` beside `is_done`; `resume_glob()` + its header comment + the top-of-file usage-block `resume-glob` line) | — | HIGH |
| tests | `loomwright/scripts/test-automate-helpers.sh` (§D0 fixture titles, harness-port/02 negative-control title, new sidecar cases + mutation control) | — | HIGH |
| contracts | `loomwright/skills/automate-loop/SKILL.md` (frontmatter description, §1.5 row, §3 "Find prior runs" + "only other artifact", §4 step 1), `loomwright/skills/SKILLS_INDEX.md`, `loomwright/docs/RESULT_SCHEMAS.md` (§AUTOMATE_RUN single-file-principle paragraph), `loomwright/commands/automate.md` ("What This Does" step 1) | — | HIGH |
| release | `CHANGELOG.md`, `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` | — | HIGH |

## Skill References
| Skill | Justification |
|---|---|
| quality-checklist | Standard pre/post-implementation gates. |
| unit-testing | Fixture-driven cases + a validated sed mutant with positive control. |

## Risk Assessment
| Risk | Impact | Source | Mitigation |
|---|---|---|---|
| **Fixture change silently disarms an existing assertion.** Retitling §D0/negative-control fixtures could be "fixed" by relaxing their expected output. | HIGH | Design (lesson: shared-fixture default disarms its own assertion) | Decision 5: expected outputs byte-unchanged; AC4 pins it. |
| **The predicate hides a real incomplete run**, so RESUME never offers it and a second run starts. | HIGH | Design | Decision 2 (anywhere-in-file, line-anchored) + AC4 blank-line case. The run lock still refuses a concurrent run. |
| **Silent no-op**: predicate defined but not called, or called after `echo`. | MEDIUM | Design | AC3 mutation control with a validated mutant + positive control. |
| **Convention mismatch across helper / SKILL §1.5 / §4 / RESULT_SCHEMAS.** Recurring churn class on these exact files per the postmortem ledger. | MEDIUM | Prior churn | AC5 names each surface; the reviewer checks all agree on the same title string `# Automate Run:`. |
| zsh vs bash validation false failures. | LOW | Machine lesson | AC7: run under `bash`. |

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-09-28-resume-glob-skips-sidecars.md

## Outcome
- **Status:** completed
- **Completed:** 2026-09-28T02:24:30Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/288
- **Branch:** feature/automate-followups-03-resume-glob-skips-sidecars
- **Files changed:** 9
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** resume-glob lists only run files via is_run_file ('^# Automate Run:' anywhere); sidecars excluded; tests incl. validated mutant; docs synced; v15.108.2. Phase 4.5 consistency_audit PASS iteration 1 (0 HIGH; 1 MEDIUM title-variant hardening + 1 LOW wording nit, posted as dismissed-marker comment, carried to the owned drain); ground_truth 2/2 pass; risk_classification high_risk=true (*auth*/automation content, commands/ path).

## Not verified
- **README.md / loomwright/commands/agent-help.md / .claude-plugin/README.md resume-glob sentences** — deliberately untouched per advisory A2 (say "runs", still accurate) (subtask 1)
- **build-handoff.sh automate-run loop and build-floor.sh automate_runs count** — brief non-goal; still over-count sidecars in advisory displays (subtask 1)
- **bare /automate RESUME continue/start-new/archive prompt end-to-end** — only the helper's output on the live dir was observed (subtask 1)
