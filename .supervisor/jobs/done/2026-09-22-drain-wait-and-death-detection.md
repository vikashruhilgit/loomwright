# Supervisor Job: Mechanized scoped wait + detection of a drain that exited without a result

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: worktree-automate-hardening-2026-09-22 (synced to origin/main @ 8dbb1d5)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/red-team-hardening/04-drain-wait-and-death-detection.md

## Feasibility (optional — Launch Pad v10.3+)

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Bash + jq + `gh`, same stack as `dispatch-pr-review.sh` and its siblings; bash 3.2/BSD-safe per requirement (no `timeout`, bound via `$SECONDS`) |
| 2 | Dependency Availability | GO | `gh api`, `notify-desktop.sh`, `send-webhook.sh` all already exist and are used elsewhere |
| 3 | Architecture Fit | GO | Extends the existing dispatcher's trap + marker convention; mechanizes prose the model currently executes unreliably |
| 4 | Scope vs Supervisor Capability | GO | One cohesive reliability fix (new wait script + death detection + surfacing); fits Single-Agent Path |
| 5 | Hard Blockers | GO | No migration framework, no credentials beyond what already exists, no missing modules |

**Overall Verdict:** GO

## Task
**Goal:** Turn the drain's "wait for CI checks to settle" step from model-executed pseudocode into a single foreground, blocking script call with a hard bound, and detect + record a runner that exits without ever producing a terminal `REVIEW_HEAL_RESULT` — so a drain that silently died from a backgrounded wait is never mistaken for a completed one.

**Problem Statement:**
`skills/review-heal/SKILL.md`'s "Wait-For-Settled-Checks" section is pseudocode (`sleep(poll_interval); re-read statusCheckRollup`) that the model itself executes. Under `claude -p`, the model's habit is to start a background poll and end its turn — but turn-end IS process exit under `-p`, so the drain process dies mid-wait. The dispatcher's wrapper trap then salvages and removes the worktree/lock as if the run completed normally, and nothing records that no `REVIEW_HEAL_RESULT` was ever produced. Measured on this checkout: 35 dispatch markers, only 4 reached `READY`, 5 reached `ESCALATED`, and 26 have no decision at all — five logs from a single day (2026-09-17) end mid-wait. The marker file still reads as "dispatched," so every downstream consumer (`/automate`'s owned drain, `session-resume.sh`, the postmortem gather) believes a drain ran when it silently died. Success looks like: the wait is one deterministic script call the model cannot accidentally background; a died drain is recorded with a `.died` marker, a log line, a best-effort notification, and surfaced at SessionStart; and the re-dispatch policy allows exactly one automatic retry, never an unbounded loop.

## Acceptance Criteria
- [ ] Given `scripts/wait-for-checks.sh <pr_url> --sha <sha> --bound <seconds> [--interval <s>] [--required-only | --review-check-pattern <glob>]`, when run against four scripted `$GH`-stub rollup sequences (pending→green, pending→red, wrong-sha→right-sha, never-settles), then it produces exactly the specified `SETTLED sha=<sha> required=<green|red> review_producing=<settled|elapsed>` or `ELAPSED ...` final line for each case, always exits 0, and a rollup reported for a DIFFERENT sha than the one being waited on is never treated as settled.
- [ ] Given the wait's `--bound <seconds>`, when the scripted rollup never settles, then the script's blocking wait is honoured within one poll interval of the bound (never unbounded) and it is bash 3.2/BSD-safe (no `timeout` binary dependency, bound tracked via `$SECONDS`).
- [ ] Given `skills/review-heal/SKILL.md`, when grepped for `sleep(poll_interval)`, then it returns 0 hits (every pseudocode wait block is replaced by a call to `wait-for-checks.sh`), and grepped for `wait-for-checks.sh` returns ≥3 hits; the exact sentence "Never run this wait in the background and never end the turn while waiting — under `claude -p` ending the turn ends the process and the drain dies with no result" appears beside each call site and `background_wait` is added to the Anti-Patterns list. The same sentence appears in `agents/review-pr.md` (with its token budget re-measured and raised if needed).
- [ ] Given a stubbed `claude` process that exits without ever printing a `REVIEW_HEAL_RESULT` block, when `dispatch-pr-review.sh`'s wrapper trap runs after the runner exits, then it writes `<hash>.died` beside the existing marker with `ts`, `pr_url`, `exit_code`, `last_log_line` (tab-separated, via `printf`), appends a `DRAIN_DIED` line to the run log, and fires `notify-desktop.sh` + `send-webhook.sh` best-effort (fail-safe — neither failure blocks the trap).
- [ ] Given a stubbed `claude` process that DOES print a terminal `REVIEW_HEAL_RESULT`, when the same trap runs, then no `.died` marker is written.
- [ ] Given a PR that has already died once (a `.died` marker exists), when the `PostToolUse[Bash]` hook backstop (`hook-dispatch-on-pr-create.sh`, fired on `gh pr create`) considers re-dispatching, then it treats `<hash>` marker + `<hash>.died` together as "not dispatched" and allows exactly ONE automatic re-dispatch; given a SECOND death for the same PR, then a `.died` marker with `attempt=2` is written and a third dispatch is NOT automatically triggered (bounded retry, never unbounded).
- [ ] Given `session-resume.sh` runs with a fixture containing two `.died` files, then its output shows a "Drains that died without a result" heading listing both PR URLs, bounded to 5 entries, and the whole SessionStart advisory stays inside its existing 8 KB cap.
- [ ] Given `/automate`'s RECONCILE step (§4) encounters a `.died` marker for the current item's PR, then it treats `owned_drain_result: died` and PARKs the run with `pause_reason: drain_died` — explicitly NEVER `awaiting_merge`, since a died drain never produced a READY/ESCALATED verdict to park on.
- [ ] **Mutation control (BLOCKING).** Given the `grep -q 'REVIEW_HEAL_RESULT' "$_log"` check inside the wrapper trap is deleted, when the no-result stub case is re-run, then the `.died`-marker test must FAIL — proving death detection is genuinely driven by that grep, not merely asserted.
- [ ] Given the full `loomwright/scripts/test-*.sh` loop plus root `scripts/check-*.sh`, when run after this change, then all suites are green with zero regressions.

## Outcomes Rubric
- The scoped CI-check wait is a single deterministic, bounded script call — never model-executed pseudocode the model could background
- A drain that exits without a terminal `REVIEW_HEAL_RESULT` is recorded as DIED via a `.died` marker, never silently treated as a completed run
- Exactly one automatic re-dispatch is allowed after a death; a second death is recorded but not auto-retried (bounded, never an infinite loop)
- `/automate`'s RECONCILE treats a died drain as `escalated`/`drain_died`, never as `awaiting_merge`
- `session-resume.sh` surfaces died drains at SessionStart, bounded and within the existing size cap
- The mutation control proves death detection is load-bearing (driven by the actual result grep), not merely asserted in prose

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Mechanized wait + death detection + re-dispatch policy + surfacing | AC1-AC9 | 1 create (`loomwright/scripts/wait-for-checks.sh`), 1 create-test (`loomwright/scripts/test-wait-for-checks.sh`), 4 modify (`loomwright/scripts/dispatch-pr-review.sh`, `loomwright/scripts/test-dispatch-pr-review.sh`, `loomwright/skills/review-heal/SKILL.md`, `loomwright/agents/review-pr.md`), 1 modify (`loomwright/docs/prompt-token-budgets.json`, only if `agents/review-pr.md`'s token measurement requires a raise), 3 modify (`loomwright/scripts/session-resume.sh`, `loomwright/skills/automate-loop/SKILL.md`, `loomwright/scripts/status-line.sh`), 3 modify (`loomwright/docs/HOOKS.md`, `loomwright/docs/ARCHITECTURE_CONTRACTS.md`, `loomwright/docs/PITFALLS.md`), 3 modify (CHANGELOG.md, plugin.json, marketplace.json version bump) | `skills/review-heal/SKILL.md`, `skills/automate-loop/SKILL.md` | LAUNCHABLE |

```yaml
# Subtask 1 — mechanized wait + death detection (LAUNCHABLE)
provides:
  - {kind: "file", path: "loomwright/scripts/wait-for-checks.sh"}
  - {kind: "symbol", path: "loomwright/scripts/dispatch-pr-review.sh", name: "DRAIN_DIED"}
  - {kind: "symbol", path: "loomwright/scripts/session-resume.sh", name: "Drains that died without a result"}
requires: []
lanes:
  - "loomwright/scripts/wait-for-checks.sh"
  - "loomwright/scripts/test-wait-for-checks.sh"
  - "loomwright/scripts/dispatch-pr-review.sh"
  - "loomwright/scripts/test-dispatch-pr-review.sh"
  - "loomwright/skills/review-heal/SKILL.md"
  - "loomwright/agents/review-pr.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/scripts/session-resume.sh"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/scripts/status-line.sh"
  - "loomwright/docs/HOOKS.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/PITFALLS.md"
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
| 1 | `skills/review-heal/SKILL.md` (the §U2/§U2.5 recipes the new script implements, and the pseudocode it replaces), `skills/automate-loop/SKILL.md` (§4 RECONCILE's new `drain_died` park reason) |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| The requirement explicitly notes this item is sequenced AFTER red-team-hardening item 01 because "both edit the same two files" (`dispatch-pr-review.sh` and its test) — a merge conflict or semantic clash with item 01's permission-pin changes | MEDIUM | Item 01 already merged (PR #248); this item's worker branches from current `main`, which already includes item 01's changes, so there is no ordering hazard left to manage |
| Mechanizing the wait as a real bounded script could itself hang or loop if the bound/interval logic has an off-by-one, defeating the exact reliability problem this item exists to fix | MEDIUM | AC1/AC2 require four scripted test sequences including a "never settles" case that must terminate at the bound; bash 3.2 `$SECONDS`-based bounding avoids the `timeout` binary dependency that would silently no-op on some environments |
| The re-dispatch policy (exactly one automatic retry after a death) could be implemented as either unbounded or zero-retry by a subtle sign/comparison error, defeating the "bounded, never unbounded" design intent | HIGH | AC6 explicitly requires testing BOTH the first-death re-dispatch-allowed case AND the second-death no-further-auto-dispatch case; this is exactly the class of boundary bug a red-team audit would probe next if left unverified |
| This is a self-hosting run: the worker edits the detached-drain infrastructure this session's own `/automate` engine's OWNED (inline, not detached) drain does not use directly, but `session-resume.sh`'s SessionStart surfacing and `/automate`'s RECONCILE step ARE used by this very run | LOW | The new `drain_died` RECONCILE branch only fires when a `.died` marker exists for the CURRENT item's PR from a DETACHED dispatch — this run's own owned drain is inline and does not go through `dispatch-pr-review.sh` at all, so this item cannot affect this session's own remaining items' drains |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-22-drain-wait-and-death-detection.md
```

## Outcome
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/251
- **Branch:** feature/red-team-04-drain-wait-and-death-detection
- **Commits:** 88b03a8 (implementation, v15.89.0) + 939d3b0 (fix: vendor-coupling-manifest false claim for wait-for-checks.sh, found by Phase 4.5 review round 1)
- **Phase 4.5 code review:** round 1 FAIL (BLOCKING — vendor-coupling-manifest.json falsely claimed wait-for-checks.sh had 0 vendor-token occurrences; it has 2, the `claude -p` shape quoted in its own header comment lines 12/22, tripping `check-vendor-coupling.sh`); fixed directly in 939d3b0 (measured allowance via `--print-allowances`, corrected note prose); round 2 PASS
- **heal_decision:** PASS
- **heal_iterations:** 1
- **rubric_score:** 6/6 (all 6 Outcomes Rubric bullets PASS)
- **Status:** PR open, not yet drained — next step is the owned `/review-pr --until-mergeable` drain
