# Supervisor Job: Measure whether v17.2.0 ended the 3/3 Phase 4.5 heal rounds, and what Plan Review attempts cost

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-15-163325/L18 (lane L18 clone of loomwright)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/automate-speed/23-measure-review-gates.md
- **Base commit:** 3a03dfa66d7de22ff93b0327affa60aa752948d2

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Markdown evidence file + bash/jq one-liners; the repo already ships `jq`-based readers and `docs/evidence/*.md` files of the same shape (e.g. `docs/evidence/as13-diet-launch-pad-autonomous.md`). |
| 2 | Dependency Availability | GO | Every data source exists locally: `.supervisor/postmortem/results.jsonl` (190 rows at base; 186 carry `plugin_version`, 179 `pr_url`, only 75 `self_heal_rounds` — every post-v17.2.0 row carries `self_heal_rounds`, most pre-v17.2.0 rows do not), the `.supervisor/automate/*.md` run files (pulled from `loomwright-meta` by `meta-entry`) and their `<run_id>.supervisor-result.md` sidecars, and `loomwright/scripts/read-token-ledger.sh --per-item` (item 03). |
| 3 | Architecture Fit | GO | Requirement scope says "no new tool": the evidence file holds the commands inline; nothing in `loomwright/` changes. |
| 4 | Scope vs Supervisor Capability | GO | One evidence file + one changelog fragment: single-agent default. |
| 5 | Hard Blockers | CAUTION | Some per-item fields are not recorded for every run (e.g. `read-token-ledger.sh --per-item` prints `not recorded` for the Launch Pad / Phase 4.5 phase rows of lane run automate-2026-10-15-163325-L14). The file must say `not recorded` with the reason for such a cell, never invent a value. |

**Overall Verdict:** CAUTION

## Task
**Goal:** Commit `docs/evidence/review-gate-rounds.md`, which reports — for every `/automate` item merged on plugin v17.2.0 or later, compared with the items before v17.2.0 — Phase 4.5 rounds and duration, termination reason, Plan Review attempts and Launch Pad duration, with the exact commands that print each table.

**Problem Statement:**
The owner needs to know whether automate-speed/02 (v17.2.0, PR #538, release commit `3925a632339077ad6229c5a7c41512cb624e403b`) actually reduced Phase 4.5 heal rounds, and what Plan Review attempts cost, because both are quality gates that must not be capped on a guess.
Currently, every `/automate` item since 2026-10-12 was observed using all 3 Phase 4.5 rounds (PR #533: 85m, ESCALATED) and nobody has measured the items built after v17.2.0. This causes later automate-speed items to argue from an unmeasured premise.
Success looks like a committed evidence file whose commands re-run on this checkout and print the same tables, a before/after comparison, and — only if ≥ half of the post-v17.2.0 items still hit 3/3 — a propose-only draft explaining why.

## Acceptance Criteria
- [ ] AC1: Given the postmortem ledger `.supervisor/postmortem/results.jsonl` and the `/automate` run files under `.supervisor/automate/`, when the worker builds the report, then a committed evidence file `docs/evidence/review-gate-rounds.md` lists every `/automate` item whose PR merged on plugin v17.2.0 or later (one row each: PR, item, plugin version, Phase 4.5 rounds, Phase 4.5 duration, termination reason, Plan Review attempts, Launch Pad duration), and the PR body links to it. A cell whose source does not record the value reads `not recorded (<which source was read>)` — never a guessed number.
- [ ] AC2: Given the same file, when a reader looks for the comparison, then it contains a table (or summary rows) for the items before v17.2.0 with the same columns where available, and a before/after comparison line stating the count and share of items that hit 3/3 Phase 4.5 rounds in each group (e.g. `post-v17.2.0: k of n items at 3/3`).
- [ ] AC3: Given the evidence file's `## Commands` section, when its commands are re-run from the repo root on this checkout, then they print the same tables: every command is written inline (no new script — requirement scope "no new tool"), reads only local files, and is pinned to a frozen cutoff (a fixed `ts` upper bound or a fixed PR list) so rows added to the ledger later do not change the output. The file states the frozen cutoff and that `.supervisor/` data is local (gitignored; carried on the `loomwright-meta` branch), so it re-runs only on a checkout that pulled that branch.
- [ ] AC4: Given fewer than 3 post-v17.2.0 items exist, then the file says so (and the item parks); given ≥ 3 exist (the ledger shows more), this branch does not apply and the file states the count.
- [ ] AC5: Given the post-v17.2.0 group, when ≥ half of its items still hit 3/3 rounds, then the worker reads those items' Phase 4.5 iteration findings, classifies each new HIGH as (a) present before round 1 and missed, (b) introduced by a fix, or (c) found by a check earlier rounds did not run, and writes the result as a propose-only draft in `.supervisor/requirements/proposed/` (gitignored — NOT in the PR diff); the evidence file names the draft path. When fewer than half hit 3/3, no draft is written and the evidence file states the share and that the draft condition did not fire.
- [ ] AC6: Given the PR's diff, then it adds a changelog fragment `changelog.d/as23-measure-review-gates.md` whose first line is `<!-- bump: patch -->` (the requirement's `<!-- bump: patch -->` Goal marker), and it does NOT edit `CHANGELOG.md`, `loomwright/.claude-plugin/plugin.json` or `.claude-plugin/marketplace.json` and does NOT run `bash scripts/bump-version.sh` (this is a `--parallel` lane: lanes write fragments only, the wave branch carries the bump — `changelog.d/README.md` §"Who runs the bump").
- [ ] AC7: Given the change, when `bash scripts/check-doc-currency.sh` runs, then it exits 0; the evidence file records that run's last line, and the `<passed>/<total>` of any test the worker ran.

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

Note on the rules: the evidence file's version strings (`v17.2.0`, each row's `plugin_version`) are frozen historical measurements of past runs, not live claims about the current version — the same convention as the existing `docs/evidence/*.md` files, and `docs/evidence/` is outside `check-doc-currency.sh`'s `FILES` list.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Build the review-gate rounds evidence file and changelog fragment | AC1–AC7 | 0 modify, 2 create | `skills/context-setup/SKILL.md` | LAUNCHABLE |

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "docs/evidence/review-gate-rounds.md"}
  - {kind: "symbol", path: "docs/evidence/review-gate-rounds.md", name: "Commands"}
  - {kind: "file", path: "changelog.d/as23-measure-review-gates.md"}
requires: []
lanes:
  - "docs/evidence/review-gate-rounds.md"
  - "changelog.d/as23-measure-review-gates.md"
external_requires:
  - "jq (already used by the repo's readers)"
  - "Local .supervisor/ data pulled from the loomwright-meta branch (results.jsonl, .supervisor/automate/*.md and their sidecars)"
  - "Claude Code session transcripts under ~/.claude/projects (read by read-token-ledger.sh --per-item) — optional source for durations"
```

### Data sources and how to read them (guidance for the worker — verify each, do not trust this list blindly)
- **Phase 4.5 rounds:** `.supervisor/postmortem/results.jsonl` — `self_heal_rounds` per row, keyed by `pr_url`, with `plugin_version` (the installed plugin version when the PR's drain/postmortem ran). Every post-v17.2.0 row carries `self_heal_rounds`; most pre-v17.2.0 rows have NO `self_heal_rounds` key at all — for those, take the value from the item's `<run_id>.supervisor-result.md` sidecar (`heal_iterations`) when one exists, else write `not recorded (<source>)` (AC1/AC2). Rows with `null`/`unknown` `plugin_version` or `null` `self_heal_rounds`: name them, do not drop them silently. The `ts` field is the row write time.
- **Which rows are `/automate` items, and de-duplication (BOTH groups):** count only ledger rows with `source == "automate_drain"` (the ledger's own marker of an `/automate` drain), naming each item by its `automate_key`. Exclude `manual_postmortem` rows (rows like PRs #92–#101 repeat a PR that already has an `automate_drain` row) and rows with no `source` or no `pr_url`. Keep exactly ONE row per `pr_url` (state which one is kept, e.g. the latest `ts`). List every excluded row in the file with its reason. The pre-v17.2.0 comparison group uses the same filter.
- **Comparison denominator (AC2):** the before/after 3/3 share counts only items whose Phase 4.5 rounds are recorded (ledger `self_heal_rounds`, else the sidecar `heal_iterations`); list the excluded items and why.
- **Which items count as "merged on ≥ v17.2.0":** decide one rule, state it in the file, and apply it to every row — e.g. the ledger row's `plugin_version` ≥ 17.2.0 (semantic-version compare, `sort -V`, not string compare). v17.2.0's release commit is `3925a632339077ad6229c5a7c41512cb624e403b` (2026-10-14).
- **Merged-state check is a one-off live read, NOT a re-runnable command (keeps AC3 local-only):** verify each listed PR is merged ONCE with `gh pr view <n> --json state,mergedAt`, record that command, its run date and its output in a clearly labelled "recorded live read (not re-run)" subsection, and freeze the result as an explicit PR list. The re-runnable commands in the `## Commands` section then filter on that frozen PR list and read only local files — no `gh` call inside `## Commands`. If `gh` is unavailable, say so and mark merged state `not verified`.
- **Termination reason:** the run file's `ran /autonomous → PR <url> (SUPERVISOR_RESULT …)` `## Progress` line and the `<run_id>.supervisor-result.md` sidecar (`heal_decision`, `heal_iterations`, `escalation_reason`).
- **Plan Review attempts and Launch Pad timing:** the run files' dated `## Progress` lines (`picked …`, `launch pad: brief saved … (Plan Review PASS 3/3 …)`, `launch-pad saved … (Plan Review FAIL→PASS 2/3 …)`); Launch Pad duration = `picked` → `brief saved` line timestamps when both exist.
- **Phase 4.5 duration:** derive from what is recorded (run-file Progress lines, the per-item report `bash loomwright/scripts/read-token-ledger.sh --per-item <runfile>` phase rows); when a source reads `not recorded`, write `not recorded (<source>)`. `--per-item` reads this machine's Claude Code transcripts (`~/.claude/projects/...`), which are NOT on `loomwright-meta` and can be deleted by retention: any value taken from it goes into the "recorded live read (not re-run)" subsection with its run date, never into `## Commands` as a re-runnable command (keeps AC3 true on another machine or later).
- **Frozen cutoff:** use a fixed ledger `ts` upper bound (or an explicit PR list) so later ledger rows do not change the printed tables.

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 (independent)
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | — | none | NO |

### Batch Plan
- **Batch 1:** Subtask 1
- **Recommended workers:** 1
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/context-setup/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Some cells (Phase 4.5 duration, Launch Pad duration) are not recorded for every item — Feasibility (Phase 2.5) | MEDIUM | Write `not recorded (<source read>)`; never infer a duration from an unrelated timestamp. State per column which source it came from. |
| Commands drift: new ledger rows change the printed tables, breaking "re-run prints the same table" | MEDIUM | Pin every command to a frozen `ts` cutoff or explicit PR list, and print that cutoff in the file. |
| `plugin_version` string compare puts `17.10.0` before `17.2.0` | MEDIUM | Compare versions with `sort -V` or split-on-dot numeric compare; show the command. |
| The proposed draft accidentally lands in the PR diff | LOW | `.supervisor/` is gitignored in branch mode; write the draft only under `.supervisor/requirements/proposed/`, and check `git status --short` before committing. |
| Absolute home paths in the evidence file trip the `meta-sync.sh` `home_path` scrub when lane metadata is pushed | LOW | Write `~/.claude/projects/...` or `/Users/<name>/` placeholders, never a literal home path. |
| A lane bump would collide with the wave's release bump | MEDIUM | Fragment only; do not run `bump-version.sh` (AC6). |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-18-measure-review-gates.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-10-18T19:31:24Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/607
- **Branch:** feature/measure-review-gates
- **Files changed:** 2
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Committed docs/evidence/review-gate-rounds.md + patch changelog fragment. Post-v17.2.0: 5 of 16 /automate items at 3/3 Phase 4.5 fix rounds vs 7 of 7 on plugin 16.0.0–17.0.2; AC5 draft condition did not fire. Phase 4.5: review 1 PASS+1 MEDIUM (fixed 54c1601), review 2 FAIL 1 HIGH+1 MEDIUM (fixed f37c871), review 3 PASS with 4 LOW dismissed. Default drain suppressed by /automate (auto_review false); the engine owns the drain.

## Not verified
- **PR body link to docs/evidence/review-gate-rounds.md (AC1)** — the Supervisor opens the PR, not the worker (subtask 1)
- **## Commands re-run on another machine that pulled loomwright-meta** — only this checkout was exercised (subtask 1)
