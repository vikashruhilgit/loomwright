# Supervisor Job: A FAIL goes somewhere — `proposed/` drafts + `--notify` for `/verify`

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/verify-walkthrough/05-verify-fail-sink-and-notify.md

## Task
**Goal:** Every `FAIL` (and every `issue` line) recorded by a `/verify` run becomes a draft requirement a human can promote with one `mv`, carrying the evidence lines it rests on; the human is told immediately at three named events.

**Problem Statement:**
`/verify` walks a ticket's acceptance criteria against the running app and records every fact to `.supervisor/verify/<run_id>/evidence.jsonl` (schema `VERIFY_EVIDENCE`, `docs/RESULT_SCHEMAS.md`), but nothing consumes a `FAIL`. Currently a real QA lane found 25 blocking bugs on a live app and one (`BUG-NC-001`) stayed unfixed five months later because the finding had no consumer (memory `qa-l1-validated-on-sports-management`). This causes verified failures to be recorded and then silently forgotten. Success looks like: every FAIL/issue becomes a citable draft under `.supervisor/requirements/proposed/` (the existing `/propose` sink — never auto-enqueued, a human promotes it), and the human is notified at the moment it matters instead of only when they later re-open the run.

## Acceptance Criteria
- [ ] AC1: After a `/verify` run with exactly one FAIL, exactly one file exists under `.supervisor/requirements/proposed/` matching `verify-<run_id>-*`, containing all four sections `## Problem`, `## Evidence`, `## Suggested acceptance`, `## Status: proposed` — and `## Evidence` names the `evidence.jsonl` line number and artifact path(s) for that `ac` line.
- [ ] AC2: A run whose only non-PASS verdicts are BLOCKED / NOT_VERIFIABLE writes **no** draft, and `<run_dir>/summary.md` states that no draft was written (the derived summary already regenerates on every append — extend its content, do not hand-write a second summary file).
- [ ] AC3: `scripts/propose-from-verify.sh <run_dir>` is idempotent on `(run_id, ac_id)` — running it twice against the same run dir produces the same file set (no duplicates, no second write attempt beyond the guard).
- [ ] AC4: `scripts/propose-from-verify.sh` writes ONLY under `.supervisor/requirements/proposed/`, through the same `guarded_write()` blast-radius guard `propose-work.sh` and `propose-domain.sh` already enforce — extracted to one shared helper (e.g. `scripts/propose-common.sh`) sourced by all three, never copied a third time. If the two existing inline copies have drifted from each other, reconcile deliberately before extracting, and confirm both scripts' own existing self-tests (`test-propose-domain.sh`, `test-propose-work.sh`) still pass unchanged after the refactor.
- [ ] AC5: A `FAIL`/`issue` line classified `DISCOVERY_GAP` or `ENVIRONMENT_ISSUE` (the `ac.classification` enum) never produces a draft — only `REAL_BUG` (and every `issue` line, which carries no classification) is drafted.
- [ ] AC6: `commands/propose.md` gains a `--from-verify <run_id>` flag (documented in its Parameters table, mirroring how `--domain` is documented) that shells out to `propose-from-verify.sh <run_dir>` (resolving `run_dir` from `run_id` the same way `verify-run.sh`/`read-verify.sh` do — `.supervisor/verify/<run_id>`).
- [ ] AC7: `commands/verify.md`'s Report step (main-thread step 5) calls `/propose --from-verify <run_id>` automatically at run end **when the run's evidence has ≥1 FAIL** (`completed`/`aborted` status only — never on a `paused` run, which has no `run_end` line yet).
- [ ] AC8: `--notify` on `/verify` fires `send-webhook.sh --event-type gate ...` (fail-SAFE, always exit 0) at exactly three events — the `needs_auth` pause, the first `FAIL` `ac` line recorded in the run, and `run_end`. Because the first-FAIL event must fire from inside the per-AC recording path (`verify-helpers.sh evidence-append` or `verify-run.sh walk`), not from `commands/verify.md`'s main-thread Report step (which only sees the run's final status, not each `ac` line as it is recorded), guard it so it fires at most once per run. Fold `run_id`, `ticket`, and derived counts into the existing `send-webhook.sh --context <freeform string>` flag (no change to `send-webhook.sh`'s payload schema or the closed `gate_type` enum documented in `docs/TELEMETRY.md`). `notify-desktop.sh` additionally fires at `needs_auth` (the human must act). `--notify` is a passthrough flag, never persisted (same convention as `/automate --notify`).
- [ ] AC9: `LOOMWRIGHT_WEBHOOK_URL` unset with `--notify` passed exits 0 and the run completes unaffected (a silent no-op per event — `/verify` has no INIT gate of its own to warn from).
- [ ] AC10: `scripts/test-propose-from-verify.sh` exercises a fixture run with 2 FAIL + 1 BLOCKED + 1 `issue` line and asserts exactly 3 drafts are written, each containing all four required sections and each `## Evidence` citing a real `evidence.jsonl` line number that resolves to a line carrying that `ac_id` (or, for the issue draft, the issue's own line); the BLOCKED line yields no draft; re-running the script still yields exactly 3 files (idempotency); and a `find` diff of the tree before/after proves nothing was written outside `proposed/`.
- [ ] AC11: The same test asserts `send-webhook.sh` is invoked **at most 3 times** across a run with 5 FAILs (a stub webhook binary counts calls) — proving the "first FAIL only" rule, not "every FAIL".
- [ ] AC12: A mutation-control check: stripping the `## Evidence` section from the writer causes `test-propose-from-verify.sh` to fail (proves the assertion is load-bearing, not vacuous).
- [ ] AC13: The positive-form invariant grep CLAUDE.md documents (`grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "`) still resolves to exactly the five sanctioned surfaces named there — this item adds zero executor surfaces (no merge, no enqueue, no dispatch).

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | `propose-from-verify.sh` writer + shared `guarded_write()` helper + `--from-verify`/`/verify` wiring + 3-event `--notify` + tests | all | 6 modify, 3 create | `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |

## Provides / Requires Schema

```yaml
# Subtask 1 (single subtask — below Decomposition Threshold)
provides:
  - {kind: "file", path: "loomwright/scripts/propose-common.sh"}
  - {kind: "symbol", path: "loomwright/scripts/propose-common.sh", name: "guarded_write"}
  - {kind: "file", path: "loomwright/scripts/propose-from-verify.sh"}
  - {kind: "file", path: "loomwright/scripts/test-propose-from-verify.sh"}
  - {kind: "symbol", path: "loomwright/commands/propose.md", name: "--from-verify"}
requires: []
lanes:
  - "loomwright/scripts/propose-common.sh"
  - "loomwright/scripts/propose-from-verify.sh"
  - "loomwright/scripts/test-propose-from-verify.sh"
  - "loomwright/scripts/propose-domain.sh"
  - "loomwright/scripts/propose-work.sh"
  - "loomwright/commands/propose.md"
  - "loomwright/commands/verify.md"
  - "loomwright/scripts/verify-run.sh"
  - "loomwright/scripts/verify-helpers.sh"
external_requires: []
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| `guarded_write()` extraction breaks `propose-domain.sh` / `propose-work.sh`'s existing self-tests if the extracted helper's behavior drifts from either inline copy | MEDIUM | Diff both inline copies first (reconcile deliberately if they differ) before extracting; re-run `test-propose-domain.sh` and `test-propose-work.sh` unchanged after the refactor, not just the new test (AC4) |
| "First FAIL" notify must fire from inside the per-AC recording path, not `commands/verify.md`'s main-thread step, since the main thread only sees final run status | MEDIUM | Wire the guarded one-time webhook call inside `verify-helpers.sh evidence-append` (or `verify-run.sh walk`) rather than `commands/verify.md` (AC8) |
| `propose-from-verify.sh` naming collision risk with the existing, unrelated `propose-verify.sh` (proposes the `.agent/verify.json` environment contract — item 01's output) | LOW | Keep the exact name `propose-from-verify.sh` the requirement specifies; do not rename or touch `propose-verify.sh` |
| Auto-dispatching `/propose --from-verify` from `commands/verify.md` at run end could be miscategorized as "enqueuing" | LOW | `proposed/` drafts are explicitly non-enqueuing (D9 regenerability split, cited in the requirement) — confirm no `/automate --folder .../proposed` reference is introduced |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-15-verify-fail-sink-and-notify.md
```


## Outcome
- **heal_loop_ran:** true
- **heal_decision:** PASS
- **heal_iterations:** 0 (Code Reviewer PASSed on first holistic pass; 3 non-blocking doc-drift/coverage findings fixed directly rather than via a fix-worker cycle)
- **heal_remaining_issues:** 0
- **rubric_score:** null (process gap: the source requirement carried a real ## Outcomes Rubric with 5 bullets, but this brief did not copy it verbatim per the Launch Pad Phase 5 preserve-rubric directive — noted honestly; does not block safe-mode /automate, which treats an absent rubric as N/A at the gate)
- **risk_classification:** {"high_risk": true, "reasons": ["content: 23 changed line(s) matched *auth*", "content: 1 changed line(s) matched *security*", "content: 5 changed line(s) matched *token*", "path: loomwright/commands/agent-help.md matched commands/", "path: loomwright/commands/propose.md matched commands/", "path: loomwright/commands/verify.md matched commands/", "size: changed_lines 898 > 400"], "changed_files": 12, "changed_lines": 898}
- **pr_url:** https://github.com/vikashruhilgit/loomwright/pull/227
- **branch:** feature/verify-fail-sink-and-notify
