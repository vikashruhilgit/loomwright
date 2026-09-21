# Supervisor Job: Close script-test gaps + roadmap remainders (webhook hostile-strings, notify-desktop tests, WorktreeRemove hook, LSP wiring)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh, v15.4.0 banner)
- **Git:** clean, branch: main @ a799b33 (== origin/main)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Worktrees:** none orphaned
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/review-remediation/06-script-test-gaps-and-roadmap-remainders.md

## Task
**Goal:** Close the remaining high-value script-test gaps and cheap roadmap remainders in one sweep — REBASELINED 2026-07-07 against the current repo (the requirement's 2026-07-05 evidence is partially stale):

- **STALE (already done, do NOT redo):** rules-check gate-precedence matrix — `test-rules-check.sh` ALREADY covers `--no-cmd` alone / `--no-cmd`+`--confirm` (no-cmd WINS) / `--confirm`-executes-with-marker / default non-TTY skip / failing-check tally (case b3). Roadmap P1-4 (red-team `effort`) and P2-13 (RED_TEAM_RESULT schema) are ALREADY stamped RESOLVED in `loomwright/docs/IMPROVEMENTS_ROADMAP.md` (items #4, #13). Do not touch these.
- **ADAPTED:** webhook tests EXTEND the existing `loomwright/scripts/test-webhook.sh` (10 cases, incl. a gate injection smoke and unset-URL no-ops) — do NOT create a parallel `test-send-webhook.sh`.
- **VERIFIED 2026-07-07 (claude-code-guide against official docs):** `WorktreeRemove` IS a supported hook event (https://code.claude.com/docs/en/hooks.md, "Worktree Events") → the hook LANDS (count 21→22, full count-surface sweep). `LSP` is the exact canonical frontmatter tool name (https://code.claude.com/docs/en/tools-reference.md) → mirror `code-reviewer.md`'s declaration verbatim.

## Acceptance Criteria
- [ ] `test-webhook.sh` extended with hostile-string round-trip assertions (double quotes, backslashes, newlines, `$(...)`, unicode) through BOTH the gate path and the supervisor_result path, parsed with `jq -e` proving valid JSON + exact round-trip as data; plus format-branch coverage (ntfy plain-text vs JSON webhook vs Slack shape); every failure path asserted exit 0; never a real POST (dry-run mode `LOOMWRIGHT_WEBHOOK_DRY_RUN=1`).
- [ ] New `loomwright/scripts/test-notify-desktop.sh`: platform-guarded (macOS: graceful no-op when terminal-notifier absent via PATH sandbox; Linux: assert the no-op path green), exit 0 on every path, timeout/gtimeout fallback selection asserted. Skippable-green on Linux CI.
- [ ] `WorktreeRemove` hook added to `loomwright/hooks/hooks.json` mirroring WorktreeCreate (type: command, log to `.supervisor/logs/worktrees.log`, `|| true`, always exit 0). Hook count 21→22 with EVERY count surface updated in the same change (plugin.json + marketplace.json descriptions in place, CLAUDE.md banner counts + hooks intro line + hook table row, READMEs) — doc-currency CI (`scripts/check-doc-currency.sh`) must pass.
- [ ] `|| true` appended to hooks.json `type: command` hook strings that lack it (11 identified: 3× send-telemetry, 2× send-webhook, validate-launch-pad-result.py, hook-dispatch-on-pr-create, 2× notify-desktop, session-resume, set-otel-resource-attrs) — FIRST confirm each script's documented always-exit-0 contract before appending (all 11 are documented fail-safe emitters/validators per CLAUDE.md hook table; do not add to any hook whose exit code is load-bearing).
- [ ] `LSP` added to `tools:` frontmatter of `loomwright/agents/worker.md`, `qa-executor.md`, `launch-pad.md` (verbatim name `LSP`, mirroring code-reviewer.md line 4) + ONE usage line each at the natural consumption point (worker: LSP diagnostics self-verify on modified files before emitting WORKER_RESULT; qa-executor: Phase 5 static-analysis leg; launch-pad: Phase 3 ANALYZE impact-map grounding). No new gating behavior. Mirror sweep: `docs/ARCHITECTURE_CONTRACTS.md` capability matrix rows for these 3 agents (currently only Code Reviewer shows "(+ LSP)").
- [ ] Roadmap item #6 (WorktreeCreate/WorktreeRemove) verdict flipped to RESOLVED + the header "OPEN (1)" line updated accordingly.
- [ ] Minor version bump 15.4.0 → 15.5.0 + CHANGELOG entry + CLAUDE.md release-note banner rotation (keep 2 most recent).
- [ ] All existing self-tests + validators green (`for t in loomwright/scripts/test-*.sh; do bash "$t"; done` mirrors CI), including re-run of test-rules-seams.sh + test-add-rule.sh (invariant: reader never executes).

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | Webhook hostile-string + format-branch test extension | 1 modify (test-webhook.sh) | LAUNCHABLE |
| 2 | test-notify-desktop.sh (new) | 1 create | LAUNCHABLE |
| 3 | WorktreeRemove hook + `|| true` sweep in hooks.json | 1 modify (hooks.json) | LAUNCHABLE |
| 4 | LSP wiring (3 agent frontmatters + capability matrix) | 4 modify | LAUNCHABLE |
| 5 | Docs/counts/version sweep (roadmap #6, banner, counts 21→22, CHANGELOG, plugin.json 15.5.0) | 7 modify | BLOCKED (by #3, #4) |

### Subtask contracts
```yaml
S1:
  provides: [{kind: file, path: loomwright/scripts/test-webhook.sh}]   # extended, green
  requires: []
S2:
  provides: [{kind: file, path: loomwright/scripts/test-notify-desktop.sh}]  # new, green
  requires: []
S3:
  provides: [{kind: file, path: loomwright/hooks/hooks.json}]          # 22 hooks: WorktreeRemove + `|| true` sweep
  requires: []
S4:
  provides:
    - {kind: file, path: loomwright/agents/worker.md}                  # LSP in frontmatter + usage line
    - {kind: file, path: loomwright/agents/qa-executor.md}
    - {kind: file, path: loomwright/agents/launch-pad.md}
    - {kind: file, path: loomwright/docs/ARCHITECTURE_CONTRACTS.md}    # capability-matrix rows
  requires: []
S5:
  provides:
    - {kind: file, path: loomwright/.claude-plugin/plugin.json}        # 15.5.0 + counts in place
    - {kind: file, path: .claude-plugin/marketplace.json}
    - {kind: file, path: CLAUDE.md}                                    # banner rotation + hook table + counts
    - {kind: file, path: CHANGELOG.md}
    - {kind: file, path: README.md}
    - {kind: file, path: .claude-plugin/README.md}
    - {kind: file, path: loomwright/docs/IMPROVEMENTS_ROADMAP.md}      # item #6 RESOLVED + header OPEN line
  requires:
    - {kind: file, path: loomwright/hooks/hooks.json, from: S3}        # final hook count (22)
    - {kind: file, path: loomwright/agents/worker.md, from: S4}        # agent-surface accuracy for doc sweep
```

## Skill References
| Subtask | Skills |
|---|---|
| S1 | `quality-checklist` (test gates); follows existing `loomwright/scripts/test-webhook.sh` harness conventions (dry-run, exit-0 assertions) |
| S2 | `quality-checklist`; `unit-testing` (AAA structure adapted to bash self-test conventions of `loomwright/scripts/test-*.sh`) |
| S3 | `quality-checklist`; no framework skill applicable — mirrors the existing WorktreeCreate hook entry shape in `hooks.json` |
| S4 | `quality-checklist`; mirror `agents/code-reviewer.md` LSP declaration + usage-line idiom (verify-invocation-shapes-from-the-file discipline) |
| S5 | `commit` (conventional commit + version linking); `quality-checklist`; CLAUDE.md §"Adding or Modifying Agents" doc-currency rules |

## Parallelism Analysis
- Batch 1: S1, S2, S3, S4 (no file overlap — verified distinct paths)
- Batch 2: S5 (after S3+S4; reads final hook count + agent state)
- Recommended workers: 3
- Confidence: HIGH on all file predictions (every path verified to exist; S2 is a create in an existing conventions-rich directory)

## Configuration
- Base Branch: main
- Branch name suggestion: feature/script-test-gaps-roadmap-remainders
- Version bump: minor → 15.5.0 (hook count changes + new tests)

## Risk Assessment
| Risk | Severity | Mitigation |
|------|----------|------------|
| `|| true` on a hook whose non-zero exit is load-bearing would neuter a gate | MEDIUM | All 11 targets documented always-exit-0 in CLAUDE.md hook table; worker must re-verify each script's exit contract from the script header before appending; skip any that gate |
| Count-surface drift (21→22) breaks doc-currency CI | MEDIUM | S5 does the full sweep; run `bash scripts/check-doc-currency.sh` locally before finalize; grep bare "21" with flexible separators (sweep-grep-gate-variants lesson) |
| bash-3.2 / Linux-CI portability regressions in new tests (stat/date/sed -i; set -u arithmetic) | MEDIUM | Follow existing test-webhook.sh/test-rules-check.sh conventions; validate numerics before `$(( ))`; no `timeout` dependency on macOS (fallback selection is itself under test) |
| notify-desktop.sh test triggering real OS notifications | LOW | PATH-sandbox terminal-notifier/osascript to stub binaries in a temp dir |
| Hostile-string tests accidentally performing a real POST | LOW | `LOOMWRIGHT_WEBHOOK_DRY_RUN=1` on every case (existing harness convention) |

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-07-07-script-test-gaps-and-roadmap-remainders.md

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/96 (base main, self-verified)
- **Branch:** feature/script-test-gaps-roadmap-remainders
- **Subtasks:** 5/5 completed, 5/5 reviews PASS
- **Heal:** loop ran, iterations 1, decision PASS, 0 fixable fixed, 0 remaining (2 LOW nits advisory)
- **Rubric:** null (no Outcomes Rubric in brief)
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false (suppressed — /automate owns the drain)
