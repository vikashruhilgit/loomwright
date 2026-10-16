# Supervisor Job: /automate Step 0 reads the lanes, resume, branch-mode and intake split files only when the run needs them

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-15-163325/L1
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (source requirement is gitignored run history — branch mode keeps it on the `loomwright-meta` metadata branch, pulled by `meta-entry` at this run's start; provenance is that branch, not `main`)
- **Source requirement:** .supervisor/requirements/automate-speed/25-automate-load-by-mode.md
- **Base commit:** f5c2d0e23fb717d385047340d7ddb5862153b6e0

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Markdown-only change to two plugin doc surfaces plus one changelog fragment |
| 2 | Dependency Availability | GO | No new dependency; validation uses existing repo scripts |
| 3 | Architecture Fit | GO | Edits stay inside `<!-- index-only -->` blocks, the sanctioned mutable region of the parallel-automate/22 split |
| 4 | Scope vs Supervisor Capability | GO | 2 modify + 2 create, single worker |
| 5 | Hard Blockers | GO | None; `test-automate-loop-split.sh` baseline 39/39 green on the base commit |

**Overall Verdict:** GO

## Task
**Goal:** Make `commands/automate.md` Step 0 read only the split files every run needs, and name, for each other split file, the observable trigger at which the run reads it — changing WHEN a file is read, never what any file says.

**Problem Statement:**
The inline `/automate` main thread needs a protocol load sized to the run it is driving, because it carries everything it reads for the whole item.
Currently, Step 0's index-only block says to read every automate-loop split file "each in full, in this order", so a one-item sequential fresh run reads `lanes.md`, `command-lanes.md`, `resume.md` and `branch-mode.md` (about 78K chars) that it never uses. This causes the coordinator context to dwarf the worker's (82M vs 2.8M context tokens on vendsy/hub PR #445).
Success looks like a Step 0 whose "only when" files each name a trigger the run can observe (a flag or a helper's printed line), with the `SKILL.md` index pointing at Step 0 instead of restating the list.

## Acceptance Criteria
- [ ] AC1 — Given `loomwright/commands/automate.md` Step 0's index-only block, when it is read, then it lists all eight skill split files in the documented order (`intake.md`, `resume.md`, `per-item-loop.md`, `modes-and-merge-gate.md`, `invariants.md`, `branch-mode.md`, `lanes.md`, `command-lanes.md`), each labelled either **Always** (exactly `per-item-loop.md`, `modes-and-merge-gate.md`, `invariants.md` — read now, with the three reads in the code block above) or **Only when** followed by its trigger, and the only-when group is exactly `intake.md`, `resume.md`, `branch-mode.md`, `lanes.md`, `command-lanes.md`.
- [ ] AC2 — Given each **Only when** row, when its trigger is read, then it names something the run observes: `intake.md` — the start resolves to a NEW run (no incomplete run listed, or the owner chose Start new), never on a `--resume` continue; `resume.md` — `--resume` was passed, or the start's `resume-glob --finalize` lists at least one incomplete run to offer, or a PICK's RECONCILE finds something to reconcile (a `## Current` item that is not `done` with a non-null `pr:`, a `closeout-others` `leftover` row, or a Queue row a human checked `# skipped:`/`# abandoned:`) — so a fresh multi-item run (e.g. `--auto-merge`) loads it at the first PICK that has an in-flight item, before that RECONCILE runs; `branch-mode.md` — `meta-entry` prints anything but `meta-entry: off` (equivalently `setup-memory.sh mode` prints `on <branch>`), or a helper line names branch mode (`trail-unstage: skipped — branch mode`, `trail-pr: meta-pushed …`, `meta-push FAILED`); `lanes.md` and `command-lanes.md` — `--parallel` was passed, or `automate-helpers.sh lane-info` exits 0 (this checkout is a lane), or a helper reports a lane (`pick-guard` prints `refuse: live_lane …`, or any `lane-*` subcommand's output is being acted on).
- [ ] AC3 — Given Step 0's index-only block, when it is read, then it carries one line saying to read plugin files with the Read tool, one file per call, never `cat` several in one Bash call (an oversized Bash result is saved to a file and read back, loading the same text twice), and one line saying to run `automate-helpers.sh lane-info` once at start so a lane (exit 0) reads the lanes files before its first PICK.
- [ ] AC4 — Given the `SKILL.md` split-layout index note (its first index-only block), when it is read, then the sentence "`commands/automate.md` Step 0 reads every split file, so the inline engine still loads the whole protocol." is replaced by a pointer to `commands/automate.md` Step 0 as the one authority for which split file is read when, restating no file list and no trigger.
- [ ] AC5 — Given the diff, when it is compared with the base commit, then every changed line of both doc files sits inside an existing `<!-- index-only:begin -->` … `<!-- index-only:end -->` block (no heading, no code-block line and no moved-section byte changes), `loomwright/scripts/test-automate-loop-split.sh` itself is unchanged, and it reports `RESULT: <n> passed, 0 failed` with check F's `Step 0 names all 8 skill split files, in documented order` line green.
- [ ] AC6 — Given `loomwright/commands/automate.md`, when `bash scripts/check-vendor-coupling.sh` runs, then it passes with the file's allowance unchanged (no new `CLAUDE_PLUGIN_ROOT`, `.claude/`, `AskUserQuestion` or other counted vendor token is added), and `bash scripts/check-doc-currency.sh` and `bash loomwright/scripts/test-citation-drift.sh` pass.
- [ ] AC7 — Given `changelog.d/as25-automate-load-by-mode.md`, when it is read, then its first line is `<!-- bump: patch -->`, its headline names the conditional Step 0 load, and no version file (`plugin.json`, `marketplace.json`, `CHANGELOG.md`, `capabilities.json`) is edited (this is a lane of a parallel wave: fragment only, the wave runs the bump).
- [ ] AC8 — Given `docs/evidence/as25-automate-load-by-mode.md`, when it is read, then it holds a `## Validation 1` section with the fenced result lines of the four checks named in `## Validation` step 1 (written by the worker) and a `## Validation 2` section (appended by the main thread before the PR is opened), and the PR body links to it.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

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

Applied here: Step 0 is the authority for the conditional read list; the `SKILL.md` note becomes a pointer (AC4) — no second list. The Step 0 block states no file count (AC1 names the files, the block itself need not say "eight").

## Touched-file invariants

> Grounded at base `f5c2d0e23fb717d385047340d7ddb5862153b6e0`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/commands/automate.md`** — keep: the Step 0 heading `### Step 0 — Load Canonical Workflow Bodies + Protocol Skill (always)` and the three-line code block (`Read ${CLAUDE_PLUGIN_ROOT}/skills/automate-loop/SKILL.md`, `.../commands/autonomous.md`, `.../commands/review-pr.md`) byte-unchanged — they sit outside the index-only block; keep exactly one `${CLAUDE_PLUGIN_ROOT}/skills/automate-loop/` inside Step 0's index-only block (the code block's `SKILL.md` read is a second, separate one, and check F's second assertion — `Step 0 resolves them under the plugin install root's skills/automate-loop/` — greps the whole Step 0 section), so the file's counted total stays 8; add no other counted vendor token (allowance `"loomwright/commands/automate.md": 8` in `loomwright/docs/vendor-coupling-manifest.json`); mirror: check F's extractor `step0_names` takes every backticked `*.md` name (`SKILL.md` excepted) between `### Step 0` and the next `### ` inside the index-only block and `cmp`s it with `assemble.sh --files` order — so each of the eight split-file names appears backticked EXACTLY ONCE in that block, in documented order, and no other backticked `*.md` name (not `autonomous.md`, not `review-pr.md`, not `lanes.md` twice) may appear there; pinned by: `loomwright/scripts/test-automate-loop-split.sh` (`F: Step 0 names all`, mutation control `MUTATION CONTROL: Step 0 missing`).
- **`loomwright/skills/automate-loop/SKILL.md`** — keep: every line outside its index-only blocks byte-unchanged, including the split markers `<!-- split:begin intake.md -->` and the `See [intake.md](intake.md).` entries (checks B, C, D, G read them); the edit is confined to the first index-only block, the one opening `> **Split layout (parallel-automate/22, move-only).**`; keep `scripts/test-automate-loop-split.sh keeps this index and the files in step` or equivalent pointer to the test; mirror: `drop_index_only` in the test strips index-only blocks before hashing, so an edit there never changes the assembly; pinned by: `loomwright/scripts/test-automate-loop-split.sh` (checks B–E, G).

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Conditional Step 0 read list + SKILL.md pointer + changelog fragment | all | 2 modify, 2 create | `skills/quality-checklist/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/commands/automate.md"}
  - {kind: "file", path: "loomwright/skills/automate-loop/SKILL.md"}
  - {kind: "file", path: "changelog.d/as25-automate-load-by-mode.md"}
  - {kind: "file", path: "docs/evidence/as25-automate-load-by-mode.md"}
requires: []
lanes:
  - "loomwright/commands/automate.md"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "changelog.d/as25-automate-load-by-mode.md"
  - "docs/evidence/as25-automate-load-by-mode.md"
external_requires: []
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/quality-checklist/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Two separately ordered "always" and "only when" lists break check F, which requires the eight backticked names in documented order inside the block — and the always files (positions 3–5) split the only-when files | HIGH | One list in documented order, each row labelled **Always** or **Only when …** (AC1). Do NOT change check F to a set comparison: it is the AC5 pin of parallel-automate/22 and this item's AC5 forbids touching the test |
| A fresh run that skips `resume.md` loses §4's start order (meta-entry → closeout-others → resume-glob --finalize → pick-guard) | MEDIUM | The command's own "Short overview" step 1 and `SKILL.md` §1.5's helper table already carry that order for a fresh start; the `resume.md` trigger fires on the first sign of an existing run (`--resume`, or `resume-glob --finalize` listing one), which is where §4's reconcile detail is first needed |
| Inside a lane, a run that skips `lanes.md` would miss §14's READY park (`ready_for_release`) | HIGH | The lanes trigger includes `automate-helpers.sh lane-info` exiting 0, observed at run-id minting on a new lane run and at the GATE on every lane run (`per-item-loop.md` routes the lane GATE through `lane-park`), so `lanes.md` loads before the §14 park; Step 0 also tells the run to call `automate-helpers.sh lane-info` once at start so a resumed lane learns it early |
| A fresh multi-item run (`--auto-merge`, or a skip) reaches a later PICK's §4 RECONCILE without `resume.md` | MEDIUM | AC2's third `resume.md` trigger: any PICK whose RECONCILE has an in-flight `## Current` item with a PR, a leftover row, or a human skip/abandon row loads it first |
| A new install-root or ask-tool token in the command trips `check-vendor-coupling.sh` (allowance 8) | MEDIUM | Name helpers bare (`setup-memory.sh mode`, `automate-helpers.sh lane-info`), say "the ask" not the tool name (AC6) |
| Editing outside an index-only block retires nothing today (E already SKIPs) but breaks this item's own invariant | LOW | AC5's diff check: every changed line inside an index-only block |
| Validation step 2 needs a headless `/automate` run in a scratch repo with THIS branch's plugin, not the installed cache | MEDIUM | Main thread runs it before PR creation with `--plugin-dir` pointing at this branch's `loomwright/`, a turn cap, and reads the Read tool's `file_path`s from the session transcript; the evidence must show paths under the branch, else it is not evidence |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1

## Validation (must pass before merge)
Evidence lives in the diff: the committed Markdown file `docs/evidence/as25-automate-load-by-mode.md` (never `*.log`) holds both steps' fenced output; the PR body quotes the same fenced blocks under `validation 1` / `validation 2` lines (what `validation-gate` reads) and links to the file.
1. `bash loomwright/scripts/test-automate-loop-split.sh`, `bash scripts/check-doc-currency.sh`, `bash loomwright/scripts/test-citation-drift.sh`, `bash scripts/check-vendor-coupling.sh`; the worker records each `<passed>/<total>` (or the OK line) fenced under `## Validation 1` in the evidence file.
2. Running system (main thread, after the worker and BEFORE FINALIZE's merge-safety / finalize-gate step — the evidence commit must land before `guard-finalize-publish.sh`'s finalize-gate marker is written, since that marker must match HEAD at `git push` / `gh pr create`; if the commit lands later, re-run the finalize-gate writer so the marker matches the new HEAD): one sequential `/automate` run on a one-item backlog in a scratch repo (no `--parallel`, no incomplete run, branch mode off) loading this branch's plugin via `--plugin-dir`; the main thread appends to the evidence file, under `## Validation 2`, the `--plugin-dir` used and the fenced list of plugin `file_path`s the session read (from its transcript), commits it, and quotes it in the PR body — the list must show paths under this branch's `loomwright/` and must not contain `lanes.md`, `command-lanes.md`, `resume.md` or `branch-mode.md`.

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-15-automate-load-by-mode.md
```

## Plan Review: PASS (attempt 3/3)
| # | Severity | Section | Description | Resolution |
|---|----------|---------|-------------|------------|
| 1 | LOW | Feasibility | Row 1 omits the evidence-file create (rows 4/Subtask/lanes correct) | deferred |

## Outcome
- **Status:** completed
- **Completed:** 2026-10-15T16:45:08Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/562
- **Branch:** feature/as25-automate-load-by-mode
- **Files changed:** 4
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Step 0 of /automate reads per-item-loop, modes-and-merge-gate and invariants always and the other five split files only on an observable trigger; always-run meta-entry and lane-info start steps; mkdir before pick-guard; SKILL.md note points at Step 0. Validation 2 (headless fresh run) read none of lanes/command-lanes/resume/branch-mode. Phase 4.5: 3 reviews, 2 fix iterations (meta-entry producer + coordinator --resume lanes trigger; changelog pointer), final PASS with LOW-only findings. risk_classification high_risk=true (advisory). ground_truth 2/2 pass; contract_conformance skipped (no contracts).

## Not verified
- **the start-time closeout-others record-line trigger for the resume split file** — needs another run with a merged in-flight PR (subtask 1)
- **branch-mode-on and coordinator-resume run shapes** — Validation 2 covered the fresh sequential branch-mode-off shape only; the later reads depend on the model following Step 0 (subtask 1)
