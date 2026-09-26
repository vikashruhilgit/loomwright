# Supervisor Job: Not-ready stamp honoured by /automate intake (`proposed` / `parked` skip)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: automate-hardening-2026-09-22 (worktree; the run's isolation branch, base main @ a58c991)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/harness-port/02-not-ready-stamp.md

## Feasibility (optional — Launch Pad v10.3+)

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Bash helper edit + bash test fixture + two markdown doc paragraphs — matches the plugin's existing tech stack exactly. |
| 2 | Dependency Availability | GO | No new dependency; uses `grep -qE` already used by the sibling `is_done()` this item mirrors. |
| 3 | Architecture Fit | GO | Directly extends `automate-helpers.sh`'s existing intake resolvers (`resolve_folder`/`resolve_backlog_dir`) with a second, deliberately SEPARATE predicate from `is_done` (decision H2 — `is_not_ready` must not be folded into `is_done`, since `is_done` is shared with `resume-glob`, whose run files use a different vocabulary `running\|paused\|done`). |
| 4 | Scope vs Supervisor Capability | GO | Single, coherent change (one helper function + two call sites + doc sync); no genuine-parallelism/file-conflict/context-bound reason to split. |
| 5 | Hard Blockers | GO | No migration framework, no credentials, no missing modules. |

**Overall Verdict:** GO

## Task
**Goal:** Make `## Status: proposed` / `## Status: parked` a real skip for `/automate`'s folder and backlog-dir intake resolvers, so a worker's (or human's) not-ready marker is actually honoured instead of silently picked and run — while leaving `is_done`, `resume-glob`, and all `## Status: done` semantics completely untouched.

**Problem Statement:**
`automate-helpers.sh`'s `is_done()` matches only a terminal `done`/`done_with_escalation` stamp; `resolve_folder` and `resolve_backlog_dir` enqueue every OTHER `*.md` in a folder. The intake is a denylist on `done`, not an allowlist on "ready" — there is currently no marker a queue reads as ready, so a file stamped `## Status: proposed` or `## Status: parked` gets picked and run anyway. The only working skip today is the `proposed/` subfolder convention (`"$dir"/*.md` does not recurse), which `/propose` relies on. Without this item, "parked ⇒ skipped" is false, and a design-only story sitting anywhere outside `proposed/` would be executed by mistake.

## Acceptance Criteria
- [ ] Given a folder containing files stamped `## Status: proposed`, `## Status: parked`, `## Status: done`, `## Status: done_with_escalation`, and one unstamped file, when `resolve-folder <dir>` runs, then it prints exactly the unstamped file.
- [ ] Given the same fixture directory, when `resolve-backlog <missing-doc-pointing-at-that-dir>` runs (the dir-fallback path), then it also prints exactly the unstamped file.
- [ ] Given a `.supervisor/automate/` directory containing a run file stamped `## Status: paused`, when `resume-glob` runs over it, then that file is STILL listed (negative control proving `is_done` itself was never widened to match `proposed`/`parked`).
- [ ] Given `is_not_ready` mutated to return 1 (false) unconditionally, when the proposed/parked fixture cases re-run, then those assertions FAIL (mutation control proving the new check is load-bearing).
- [ ] `grep -n 'is_not_ready' loomwright/scripts/automate-helpers.sh` shows exactly one definition plus exactly two call sites (inside `resolve_folder` and `resolve_backlog_dir`).
- [ ] `grep -n 'is_done()' loomwright/scripts/automate-helpers.sh` shows the regex byte-for-byte UNCHANGED vs `git show origin/main:loomwright/scripts/automate-helpers.sh` (decision H2 — `is_not_ready` is never folded into `is_done`).
- [ ] `automate-loop/SKILL.md` §2 documents both skips (the `proposed/` subfolder, not scanned; and the `## Status: proposed|parked` heading stamp, scanned and skipped) and states a skipped-by-stamp file is NOT checked off and does not count toward the run's own `## Status: done`.
- [ ] `commands/propose.md`'s "Promote" paragraph gains one sentence cross-referencing the stamp: a file may also be kept un-runnable in place with `## Status: proposed`; moving out of `proposed/` AND removing/changing the stamp are BOTH needed to run it.
- [ ] `resolve_backlog` (the `- [ ]`/`- [x]` checklist-line parser) is explicitly left unchanged — the implementer records, in a code comment at the top of `resolve_backlog`, that a checklist-pointed-to file's own `## Status:` stamp is honoured only on the dir-fallback path (`resolve_backlog_dir`), not when a checklist line directly names an existing file.
- [ ] The `resolve-folder`/`resume-glob` usage comment lines at the top of `automate-helpers.sh` are updated to reflect the new "not done and not proposed|parked" behavior for `resolve-folder` specifically (never for `resume-glob`, which is unaffected — different vocabulary, decision H2).
- [ ] CHANGELOG.md gains one paragraph; `plugin.json` + `marketplace.json` version bump (patch — additive, non-breaking). README.md/CLAUDE.md are NOT touched (memory: `release-surfaces-readme-claude-md-no-longer-bump`).
- [ ] Full test loop (`loomwright/scripts/test-*.sh` + root `scripts/test-*.sh` + `scripts/check-vendor-coupling.sh` + `scripts/check-doc-currency.sh`) green.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | `is_not_ready` intake skip (proposed/parked) + fixture tests + mutation control + doc sync | all | 6 modify, 0 create | quality-checklist | LAUNCHABLE |

```yaml
# Subtask 1 — is_not_ready intake skip + tests + docs (LAUNCHABLE)
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "is_not_ready"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-helpers.sh", name: "is_not_ready"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/SKILL.md", name: "proposed|parked"}
  - {kind: "symbol", path: "loomwright/commands/propose.md", name: "## Status: proposed"}
requires: []
lanes:
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/test-automate-helpers.sh"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/commands/propose.md"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 (single subtask — one cohesive helper function + its call sites + tests + doc sync)
```

### File Overlap Matrix
N/A — single subtask, no sibling to overlap with.

### Batch Plan
- **Batch 1:** Subtask 1
- **Recommended workers:** 1
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/quality-checklist/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| A naive implementation could fold `is_not_ready` into `is_done` (they're both simple `grep -qE` one-liners, tempting to merge) — decision H2 explicitly forbids this because `is_done` is shared with `resume-glob`, whose run files use `running\|paused\|done`, a DIFFERENT vocabulary than requirement files' `proposed\|parked\|pending\|done`. | MEDIUM | Explicit acceptance criterion requires `is_done()`'s regex stay byte-for-byte unchanged vs `origin/main`, verified by grep-diff, not by inspection alone. |
| `resolve_backlog` (the checklist-line parser) reads `- [ ] <path>` lines directly — it is easy to assume the same stamp-check should apply there too, but the source requirement explicitly leaves this as an implementer's call with a instruction to document whichever way it's decided. | LOW | Brief's own acceptance criteria requires the decision be recorded in a code comment either way, not silently decided. Given the requirement's own emphasis on minimal surface area and that `resolve_backlog`'s checklist already carries an explicit `[x]`/`✅`/inline-`Status: done` vocabulary of its own (a human editing the backlog doc directly controls readiness per-line), the safer default is: leave `resolve_backlog` unchanged and document why (a checklist line is a human's explicit inclusion decision, distinct from a file's own internal stamp) — record this decision, don't silently make it. |
| The mutation control (`is_not_ready` returning 1 unconditionally) needs to prove the check is load-bearing without accidentally leaving a stale copy of the real function behind if the source shape changes later. | LOW | Mirror the established sed-based code-mutation pattern already used elsewhere in `test-automate-helpers.sh` — the gate cond-6 mutation control (~line 919) or the I7 ceiling-check mutation control (~line 1905), both of which build a mutant copy of `automate-helpers.sh` via `sed`, confirm it still parses with `bash -n`, and diff behavior against a positive control on the unmutated script — rather than inventing a new mechanism. (Plan Reviewer PASS finding: an earlier draft of this row cited the H2/H3 tests at ~line 1724, which mutate a fixture value, not the script's code — corrected here.) |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-24-harness-port-02-not-ready-stamp.md
```
