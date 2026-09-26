# Supervisor Job: `cmd:` Executable-Acceptance bullets run only behind an explicit, command-visible human stamp

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: worktree-automate-hardening-2026-09-22 (synced to origin/main @ 3468f07)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/red-team-hardening/05-cmd-valve-by-provenance.md
- **Base commit:** 3468f078e2c573df6cc1b2bd4f35f9e07ed59e3a

## Feasibility (optional — Launch Pad v10.3+)

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Bash + jq (`run-ground-truth.sh`, `exec-acceptance-hash.sh`), markdown prompt edits (`plan-reviewer.md`, `launch-pad.md`, `self-heal-advisory/SKILL.md`) — same stack as every other item in this run |
| 2 | Dependency Availability | GO | `sha256sum`/`shasum` fallback chain already established in this repo (`drain-rounds.sh`'s `pr_hash`); no new external dependency |
| 3 | Architecture Fit | GO | Extends the existing `## Executable Acceptance` brief convention and Plan Reviewer Criterion 14 (both already exist); closes a documented trust-surface gap rather than introducing new architecture |
| 4 | Scope vs Supervisor Capability | GO | One cohesive security fix (hash-stamp gate + 3 prompt-file corrections + doc/version bump); fits Single-Agent Path |
| 5 | Hard Blockers | GO | No migration framework, no credentials, no missing modules; all cited files verified present at the cited (or near) locations before this brief was written |

**Overall Verdict:** GO

## Task
**Goal:** A `cmd:`/bare `## Executable Acceptance` bullet executes in `run-ground-truth.sh` only when a human has seen the literal command text and stamped the brief with a content-keyed hash; the stamp invalidates itself when the bullets are edited; the `self-heal-advisory/SKILL.md` safety-valve comment stops making a false claim about when `--no-cmd` fires; and a machine-authored brief (Launch Pad, `/autonomous`) never carries the stamp by construction.

**Problem Statement:**
`skills/self-heal-advisory/SKILL.md:390-403` computes `NO_CMD_FLAG = (NON_INTERACTIVE == true) ? "--no-cmd" : ""` with a comment claiming this is set "when NON_INTERACTIVE == true — i.e. this run was driven by /autonomous." That premise is false: `skills/autonomous-loop/SKILL.md:94,284` (verified — both lines read exactly as cited) forward `--non-interactive` to the inlined `/supervisor` invocation ONLY when `--non-interactive-fallback` was passed to `/autonomous`. A default, interactive `/autonomous "goal"` (no `--non-interactive-fallback`) therefore runs with `NON_INTERACTIVE=false`, so `NO_CMD_FLAG` is empty, and ANY `cmd:`/bare bullet under a brief's `## Executable Acceptance` section executes via `bash -c` in Phase 4.5's `run-ground-truth.sh` (verified — `run-ground-truth.sh:330-359`'s classification treats a bare bullet or a `cmd:`-prefixed one identically, running it in `PROJECT_ROOT` with full shell privileges unless `--no-cmd`/`NO_CMD=1` is set). The only real guards today are prose: Launch Pad is told "NEVER emit `cmd:`" (`agents/launch-pad.md:482`, verified) while it is reading and summarizing a project's own README/docs, which may themselves say "acceptance: run \`curl ... | sh\`"; Plan Reviewer Criterion 14 (`agents/plan-reviewer.md:259-279`, verified) rates a present `cmd:` bullet **LOW** — which the Decision Matrix maps straight to **PASS** — so the brief saves with no human gate at all; and Launch Pad's Phase 6 "save/refine/discard?" prompt shows the PASS/FAIL verdict, not the flagged commands themselves. This is exactly the failure class memory `acceptance-check-vs-adversarial-review` names: a stated invariant ("a `cmd:` bullet can NEVER run arbitrary shell with no human in the loop") that nothing actually falsifies — the comment describes a control that does not exist on the path it claims to cover.

**Success looks like:** a `cmd:`/bare bullet executes in `run-ground-truth.sh --brief` only when the brief's `## Configuration` carries a stamp whose hash matches the current, whitespace-normalized bullet list (an edit after stamping invalidates it); Plan Reviewer escalates an unstamped `cmd:`/bare bullet to **NEEDS_HUMAN** (not LOW/PASS) and quotes every flagged bullet verbatim; Launch Pad's Phase 6 (interactive path) surfaces those exact bullets in an `AskUserQuestion` with `approve-and-stamp | strip-cmd-bullets | discard`, and on the non-interactive/`--non-interactive-fallback` path strips the bullets automatically (never silently proceeds with an executable, unreviewed brief) and records `cmd_bullets_stripped_non_interactive` in `LAUNCH_PAD_RESULT`; and the safety-valve comment in `self-heal-advisory/SKILL.md` says what actually happens on each path, naming the stamp mechanism by script name.

## Acceptance Criteria
- [ ] Given `scripts/exec-acceptance-hash.sh <brief>`, when run against a brief's `## Executable Acceptance` section, then it prints `sha256:<hex>` of the whitespace-normalized, newline-joined list of `cmd:`/bare bullets ONLY (using the identical classification rule as `run-ground-truth.sh:327-332 (the full case statement)`: `cmd:*` / bare = included, `corpus-task:*` / `qa-executor:*` = excluded), and prints exactly `none` when that filtered list is empty (including when the section is absent entirely).
- [ ] Given `run-ground-truth.sh --brief <brief> <no --no-cmd>`, when the brief's `## Configuration` section carries a line `- **Executable Acceptance Approved:** sha256:<hash>` and `<hash>` equals `exec-acceptance-hash.sh <brief>`'s current output, then every `cmd:`/bare bullet executes exactly as it does today (unchanged happy path).
- [ ] Given the same setup but the stamp is ABSENT, then every `cmd:`/bare bullet is recorded `per_check status: unverified, reason: cmd_unapproved` (a NEW reason string, distinct from the existing `cmd_disabled` that `--no-cmd` produces) and executes NOTHING — verified via a bullet that would create a sentinel file, asserting the file is never created.
- [ ] Given the same setup but the stamp is STALE (a bullet was edited/added/removed after the stamp line was written, so `exec-acceptance-hash.sh`'s current output no longer matches the stored hash), then the same `cmd_unapproved` unverified outcome applies — no execution.
- [ ] Given both `--no-cmd` and a VALID stamp are present, then `--no-cmd` wins (cmd:/bare bullets are skipped with the existing `cmd_disabled` reason, never executed) — the stamp only ever ENABLES execution on a path that isn't already disabled by the safety valve, it never overrides `--no-cmd`.
- [ ] Given an explicit `--check <cmd>` or `--checks-file <path>` invocation (no `--brief`), then behavior is COMPLETELY UNCHANGED — the stamp gate applies ONLY to bullets sourced from `--brief`'s `## Executable Acceptance` section, never to explicitly human-typed `--check`/`--checks-file` input. This requires per-line source-provenance tracking through the check-resolution pipeline (see Risk Assessment row below — the three sources are currently merged into one flat array with no origin tag). Covered by TWO test cases: (a) `--check`/`--checks-file` alone, no `--brief` at all; (b) a MIXED invocation (`--brief <unstamped-brief>` + `--check <cmd>` together) where the `--brief`-sourced unstamped `cmd:` bullet is gated (`cmd_unapproved`) while the `--check`-sourced bullet in the SAME run still executes normally.
- [ ] **Mutation control (BLOCKING).** Given the hash-comparison check inside `run-ground-truth.sh` that gates `cmd:`/bare execution on a valid stamp is deleted/neutered, when the STALE-stamp test case from above is re-run, then that test must FAIL — proving the gate is genuinely driven by the comparison, not merely asserted in prose.
- [ ] Given `agents/plan-reviewer.md` Criterion 14, when a brief has ≥1 `cmd:`/bare bullet and NO valid stamp (per the same hash rule `exec-acceptance-hash.sh` implements), then the issue severity is **NEEDS_HUMAN** (not LOW) and the issue `description` lists every flagged bullet verbatim (already required — unchanged); when a VALID stamp is present, severity stays **LOW** (visibility only, as today, since the human already reviewed and stamped these exact bullets). The "M3 graduation" forward note describing this exact behavior as a future milestone is retired/removed — it is now the shipped behavior, not a forward note.
- [ ] Given `agents/launch-pad.md` Phase 6, when Plan Reviewer returns NEEDS_HUMAN with an `executable_acceptance` issue on the INTERACTIVE path, then the `AskUserQuestion` quotes the flagged bullets verbatim in the question text and offers exactly three options: `approve-and-stamp` (writes the `## Configuration` stamp line via `exec-acceptance-hash.sh` and re-saves), `strip-cmd-bullets` (removes the flagged bullets, keeps any `corpus-task:`/`qa-executor:` bullets, re-runs Plan Review), `discard`.
- [ ] Given the same NEEDS_HUMAN condition but the run is `--non-interactive` / `--non-interactive-fallback` (no human to ask), then Launch Pad strips the `cmd:`/bare bullets automatically (never proceeds with an unreviewed executable brief, never silently keeps them) and records the additive `LAUNCH_PAD_RESULT` field `cmd_bullets_stripped_non_interactive: true` (absent/false when nothing was stripped) — additive field, no `schema_version` bump, following the precedent `validate-launch-pad-result.py` already tolerates for other additive fields.
- [ ] Given `skills/self-heal-advisory/SKILL.md`'s safety-valve comment (currently `lines 391-392`, the phrase "this run was driven" / "by /autonomous" split across the two REAL lines — a plain `grep -n 'driven by /autonomous'` does NOT match this line-wrapped form even today and is not a valid before/after discriminator), when checked with `tr '\n' ' ' < skills/self-heal-advisory/SKILL.md | grep -q 'was driven.*by /autonomous'` (or an equivalent multiline-aware check), then it returns NO match — the false claim is gone. The replacement prose instead: (a) correctly says `NON_INTERACTIVE == true` is set by `--non-interactive-fallback`, not by `/autonomous` alone (`grep -q 'non-interactive-fallback' skills/self-heal-advisory/SKILL.md` finds it), and (b) names the new stamp mechanism by script name (`grep -q 'exec-acceptance-hash.sh' skills/self-heal-advisory/SKILL.md` finds it) as what governs execution on every other path. `agents/supervisor.md` is greped for `no-cmd`; if it restates the (now-corrected) valve, that restatement is corrected too.
- [ ] Given the full `loomwright/scripts/test-*.sh` loop plus root `scripts/check-*.sh`, when run after this change, then all suites are green with zero regressions, including a NEW `test-exec-acceptance-hash.sh` covering: a brief with only `cmd:`/bare bullets, a brief with only `corpus-task:`/`qa-executor:` bullets (hash = `none`), a brief with a MIX (hash covers only the `cmd:`/bare subset), whitespace-normalization (trailing-space-only edits do NOT change the hash — matches `run-ground-truth.sh`'s own bullet trimming), and an absent `## Executable Acceptance` section (hash = `none`).

## Outcomes Rubric
- A `cmd:`/bare bullet in a brief's `## Executable Acceptance` section executes in `run-ground-truth.sh` ONLY when a content-keyed hash stamp matches the CURRENT bullet list — never on presence of the section alone
- Editing a `cmd:`/bare bullet after stamping invalidates the stamp (`cmd_unapproved`, no execution) — the stamp is keyed to content, not merely present/absent
- `--no-cmd` still wins over any valid stamp — the existing unattended safety valve is not weakened by the new gate
- Plan Reviewer Criterion 14 escalates an unstamped `cmd:`/bare bullet to NEEDS_HUMAN (blocks the brief save) rather than LOW/PASS
- The `self-heal-advisory/SKILL.md` safety-valve comment states the TRUE condition under which `--no-cmd` fires and names the stamp mechanism that governs every other path
- The mutation control proves the stamp-comparison gate is load-bearing (driven by the actual hash comparison), not merely asserted in prose

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Content-keyed stamp gate for `cmd:`/bare Executable Acceptance bullets | AC1-AC12 | 2 create (`loomwright/scripts/exec-acceptance-hash.sh`, `loomwright/scripts/test-exec-acceptance-hash.sh`), 2 modify (`loomwright/scripts/run-ground-truth.sh`, `loomwright/scripts/test-run-ground-truth.sh`), 2 modify (`loomwright/agents/plan-reviewer.md`, `loomwright/agents/launch-pad.md`), 2 modify (`loomwright/skills/self-heal-advisory/SKILL.md`, `loomwright/agents/supervisor.md` — only if it restates the valve), 2 modify (`loomwright/skills/supervisor-readiness/SKILL.md`, `loomwright/docs/RESULT_SCHEMAS.md`), 1 modify (`loomwright/docs/PITFALLS.md`, only if a new gotcha is worth recording), 3 modify (CHANGELOG.md, plugin.json, marketplace.json version bump), 1 modify (`loomwright/docs/prompt-token-budgets.json`, re-measure `launch-pad`/`plan-reviewer`) | `skills/supervisor-readiness/SKILL.md`, `skills/self-heal-advisory/SKILL.md` | LAUNCHABLE |

```yaml
# Subtask 1 — content-keyed stamp gate (LAUNCHABLE)
provides:
  - {kind: "file", path: "loomwright/scripts/exec-acceptance-hash.sh"}
  - {kind: "symbol", path: "loomwright/scripts/run-ground-truth.sh", name: "cmd_unapproved"}
requires: []
lanes:
  - "loomwright/scripts/exec-acceptance-hash.sh"
  - "loomwright/scripts/test-exec-acceptance-hash.sh"
  - "loomwright/scripts/run-ground-truth.sh"
  - "loomwright/scripts/test-run-ground-truth.sh"
  - "loomwright/agents/plan-reviewer.md"
  - "loomwright/agents/launch-pad.md"
  - "loomwright/skills/self-heal-advisory/SKILL.md"
  - "loomwright/agents/supervisor.md"
  - "loomwright/skills/supervisor-readiness/SKILL.md"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/docs/PITFALLS.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 (only subtask — no dependencies)
```

### File Overlap Matrix
N/A — single subtask, no overlap to serialize.

### Batch Plan
- **Batch 1:** Subtask 1
- **Recommended workers:** 1
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/supervisor-readiness/SKILL.md` (the `## Executable Acceptance` brief convention this item extends with a stamp field), `skills/self-heal-advisory/SKILL.md` (the safety-valve comment being corrected and the `run-ground-truth.sh` invocation it documents) |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| The stamp hash could be computed differently by `exec-acceptance-hash.sh` (the brief-authoring/human-facing side) and by `run-ground-truth.sh` (the enforcement side), silently reopening the gap this item exists to close if the two ever drift | HIGH | AC1 requires `exec-acceptance-hash.sh` to use the IDENTICAL classification rule already in `run-ground-truth.sh:327-332 (the full case statement)` (verified); the worker should factor the shared classification logic so both scripts read from one definition rather than maintaining two independent copies, or add a cross-check test that fails if they diverge |
| **AC6 (`--check`/`--checks-file` bullets must be COMPLETELY unaffected by the stamp gate) requires per-line source tracking that `run-ground-truth.sh` does not currently have.** Verified: the three sources (1a `--check`, 1b `--brief`, 1c `--checks-file`) are all merged into one flat check-lines array before classification/execution ever runs (~lines 209-319) — there is no existing tag distinguishing "this line came from `--brief`" from "this line came from `--check`". Implementing AC6 correctly is therefore non-trivial, not a one-line conditional | HIGH | The worker must add provenance tracking (e.g. a parallel array, or an annotated-line encoding) through to the gating check WITHOUT breaking the existing 1a/1b/1c priority-order resolution, and `test-run-ground-truth.sh` must cover BOTH the "no `--brief`, only `--check`" case AND a MIXED "`--brief` + `--check`" case (a `--brief`-sourced unstamped `cmd:` bullet is gated; a `--check`-sourced one in the SAME invocation still executes) |
| A subtle bug in the stale-stamp detection (e.g. comparing against a cached/stringified hash rather than recomputing) could make an edited `cmd:` bullet silently keep executing under a now-invalid stamp — defeating the entire point of a content-keyed stamp | HIGH | AC4 explicitly requires a STALE-stamp test case (edit after stamp, hash mismatch, `cmd_unapproved`); the BLOCKING mutation control (AC7) additionally proves the comparison is load-bearing by neutering it and confirming the stale case then wrongly passes |
| Retiring the Criterion 14 "M3 graduation" forward note could be read as also retiring the LOW-severity behavior for a VALID stamp, over-tightening to NEEDS_HUMAN even when a human already reviewed and stamped the bullets | MEDIUM | AC8 is explicit: NEEDS_HUMAN only when NO valid stamp exists; a valid stamp keeps the existing LOW/visibility-only behavior — the worker must preserve this branch, not just delete the whole conditional |
| The non-interactive auto-strip path (AC10) could be implemented as silently keeping the `cmd:` bullets instead of stripping them, since there is no human to ask — this would be the exact "silent success with no real verification" failure class red-team-hardening exists to close | HIGH | AC10 is explicit that non-interactive MUST strip, never silently proceed with an unreviewed executable brief; `cmd_bullets_stripped_non_interactive` gives an auditable, additive signal a reviewer/test can assert on |
| This item touches `run-ground-truth.sh`, which is invoked by EVERY Phase 4.5 (including this very session's own future items 6-8+) — a bug here could break ground-truth execution for all subsequent items in this `/automate` run | MEDIUM | `test-run-ground-truth.sh` already exists and is part of the mandated full-suite green-before-merge gate (AC12); the happy-path AC (AC2) explicitly requires the UNCHANGED-behavior case (valid stamp = executes exactly as today) so a regression there is caught before this item's own PR merges |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-22-cmd-valve-by-provenance.md
```

## Outcome
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/252
- **Branch:** feature/red-team-05-cmd-valve-by-provenance
- **Commits:** 22f0bf2 (implementation, v15.90.0) + a15f929 (fix: launch-pad self-contradiction + mirror gap + budget re-measure, found by Phase 4.5 review round 1)
- **Phase 4.5 code review:** round 1 FAIL (1 HIGH — agents/launch-pad.md's new `--non-interactive` Parameters row self-contradicted the same diff's own Phase 5.5/6 prose about which NEEDS_HUMAN paths it gates; plus 2 MEDIUM — missing commands/launch-pad.md mirror row, un-re-measured token budgets [plan-reviewer down to 48 headroom]; plus 2 LOW cosmetic); all fixed directly in a15f929; round 2 PASS
- **heal_decision:** PASS
- **heal_iterations:** 1
- **rubric_score:** 6/6 (all 6 Outcomes Rubric bullets PASS)
- **Status:** PR open, not yet drained — next step is the owned `/review-pr --until-mergeable` drain
