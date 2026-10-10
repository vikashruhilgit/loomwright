# Supervisor Job: Completion-evidence integrity — no vacuous FINALIZE pass; one worker spawn shape

## Environment
- **Project:** ai-agent-manager-lanes lane clone L3 (repo `vikashruhilgit/loomwright`)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (source requirement is gitignored run history kept on the `loomwright-meta` branch — branch mode; provenance comes from the meta pull at run start, not from a tracked commit)
- **Source requirement:** .supervisor/requirements/agnostic-phase1/02-completion-evidence-integrity.md
- **Base commit:** e41f657bbd4a29488db42ed3ceb902b15af4a598

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + jq script, markdown prompts/skills/docs — the repo's own stack |
| 2 | Dependency Availability | GO | jq only (already required by the script) |
| 3 | Architecture Fit | GO | Extends the existing ONE join (`check-children-settled.sh`) and its FINALIZE consumer; no new state file |
| 4 | Scope vs Supervisor Capability | GO | ~12 files, small diffs — single-agent default |
| 5 | Hard Blockers | GO | None |

**Overall Verdict:** GO

## Task
**Goal:** Make Supervisor FINALIZE Point 5 report `settled` / `no_identity_rows` only when the session log actually evidences it (expected worker ids are checked even when their `agent_identity` rows never landed), and make `loomwright:worker` the one documented worker spawn shape.

**Problem Statement:**
The Supervisor needs its whole-session completion check to fail closed on missing evidence, because today a run that spawned workers whose `PostToolUse[Task]` identity rows never landed (hook not fired, log dir unresolvable, non-Claude host) gets `status: "no_identity_rows"` — the same answer as a run that spawned nothing — and FINALIZE Point 5 PASSES it. The per-subtask gates (`--agent-id`) already fail closed on the same absence, so the two checks disagree. Separately, two skill examples spawn workers as `general-purpose`, which no worker hook (`validate-worker-result.py`, `emit-progress-event.sh`, `guard-arm.sh arm-from-payload`) fires on.
Success looks like: `--all --expect-id <id>` returns `unsettled` naming every expected id with no terminal row (including a missing/empty log), Point 5 and the mechanized finalize-gate marker writer both pass the ids this run spawned, and no worker-spawn example uses `general-purpose`.

## Acceptance Criteria
- [ ] AC1 — Given no log, when `check-children-settled.sh --log /nonexistent --all --expect-id a1` runs, then it prints `"status":"unsettled"` and `"unsettled_agent_ids":["a1"]` and exits 0.
- [ ] AC2 — Given no `--expect-id`, when `check-children-settled.sh --log /nonexistent --all` runs, then it prints `"status":"no_identity_rows"` (byte-for-byte today's output, exit 0); the same holds for an existing empty log.
- [ ] AC3 — Given `--expect-id` values (repeatable), when `--all` runs on a log, then every expected id must have a terminal row by the SAME `terminal_for` join single-agent mode uses (non-rejected `subtask_complete` | `token_ledger` | `agent_lifecycle{state:failed}` | the existing lower-tier `ended` rule), else `status: "unsettled"` with that id in `unsettled_agent_ids` — regardless of whether any `agent_identity` rows exist; an expected id with only an `agent_identity` row is unsettled; an expected id with a terminal row is settled; ids from `agent_identity` rows are still checked as today (union, deduped). The script header's Usage + Output-shape block documents `--expect-id`.
- [ ] AC4 — Given the Supervisor reaches FINALIZE, when Point 5 runs, then `agents/supervisor.md` Point 5 passes `--expect-id` for every worker id this run spawned and already joined in the per-subtask gates (Single-Agent step 3b, Sequential per-subtask join, Execute Manager per-worker join), read from ONE existing surface (recommended: the `## Worker Results` `### {worker-id} ({subtask-id})` headings Context-Keeper already writes via `record_worker_result` in `.supervisor/state.md`; no new state file), and the Point 5 prose states that `no_identity_rows` passes only when the run spawned nothing. `grep -n 'expect-id' loomwright/agents/supervisor.md` hits Point 5.
- [ ] AC5 — Given the finalize-gate marker is the mechanism that actually gates publish, when `scripts/guard-finalize-publish.sh write-marker` runs, then it passes the same expected ids to `check-children-settled.sh --all` (derived from the same surface as AC4 and/or explicit repeatable `--expect-id` args; `--skip-children-check` keeps working in any argument position), so an expected id with no terminal row refuses the marker (`children_unsettled`) instead of recording `no_identity_rows`; a run with no recorded worker ids behaves exactly as today.
- [ ] AC6 — Given the mirrors of Point 5, when this change lands, then `skills/async-orchestration/SKILL.md` §FINALIZE (the `--all` call near its `no_identity_rows` bullet) and `docs/FAILURE_ESCALATION.md` (its children-unsettled FINALIZE gate) state the same rule; `docs/ARCHITECTURE_CONTRACTS.md` / `docs/result-schemas/supervisor-result.md` / `docs/HOOKS.md` are updated only where they restate Point 5's or `write-marker`'s pass rule.
- [ ] AC7 — Given the two worker-spawn examples, when this change lands, then `skills/async-orchestration/SKILL.md` §"Spawning a Worker" and `skills/workflow-management/SKILL.md` §"Worker Dispatch" use `subagent_type: "loomwright:worker"` (every other field kept), and `grep -rn 'subagent_type: "general-purpose"' loomwright/skills/async-orchestration/SKILL.md loomwright/skills/workflow-management/SKILL.md` returns no worker-spawn example. Any other worker spawn in `agents/`, `skills/`, `commands/` that is not `loomwright:worker` is fixed (any file fixed outside this brief's lanes is reported in WORKER_RESULT `deviations`) or justified in the PR body; the non-worker `general-purpose` spawns (review-heal fixers `skills/review-heal/SKILL.md`, the `/autonomous` EVALUATE review step `skills/autonomous-loop/SKILL.md`, self-heal-advisory fix tasks, `agents/review-pr.md`'s fix worker) are left untouched and LISTED in the PR body as considered-and-out-of-scope.
- [ ] AC8 — Tests: `scripts/test-check-children-settled.sh` gains: expected id + no log ⇒ unsettled; expected id + identity row only ⇒ unsettled; expected id + terminal row ⇒ settled; no expected ids + empty log ⇒ `no_identity_rows` (unchanged); a seam test greps Point 5 prose in `agents/supervisor.md` for `--expect-id`; a seam test asserts no `subagent_type: "general-purpose"` remains in a worker-spawn example of the two skills (grep scoped narrowly so the fixer spawns do not trip it); MUTATION CONTROL — a COPY of the script with `--expect-id` ignored must make the no-log case fail its assertion (gate the mutant on non-empty + differs-from-original + `bash -n` before trusting it). `scripts/test-guard-finalize-publish.sh` gains a case: a recorded expected worker id with no terminal row ⇒ `write-marker` refuses, no marker written.
- [ ] AC9 — Docs/release: one `changelog.d/agnostic-phase1-02-completion-evidence-integrity.md` fragment (`<!-- bump: minor -->`); NO `bump-version.sh` run and no edit of `plugin.json` / `marketplace.json` / `CHANGELOG.md` (this runs as a `--parallel` lane — the release lane bumps once for the wave, `changelog.d/README.md` §"Who runs the bump"); `docs/prompt-token-budgets.json` (+ the mirror row in `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets") raised only if `check-token-budget.sh` breaches; `docs/vendor-coupling-manifest.json` updated only if its ratchet check requires it. `bash scripts/ci-local.sh` is green.

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

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Touched-file invariants

> Grounded at base `e41f657bbd4a29488db42ed3ceb902b15af4a598`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/check-children-settled.sh`** — keep: fail-SAFE emitter, ALWAYS exit 0 and one JSON object on stdout (`always exit 0`); unknown args warn and are ignored (`unexpected argument %s (ignored)`) — `--expect-id` must become a parsed arg, not fall into that branch; `bad_args`/`jq_missing` ⇒ `{"status":"unverifiable",...}`; the no-flag `--all` outputs stay byte-identical (`no_identity_rows`); bash 3.2 / BSD safe (`bash 3.2 / BSD userland safe`); reuse: the existing `terminal_for` / `rejected_stops_for` functions for expected ids — never a second copy of the join (header: `Restating the OR condition in four places is exactly the drift class`); every JSON built with `jq --arg` / `--argjson`; fired by: Supervisor Single-Agent step 3b and the Sequential per-subtask join (`--agent-id {worker_id}`), Execute Manager's per-worker join (`--agent-id {worker_id}`), FINALIZE Point 5 (`--all`), and `guard-finalize-publish.sh write-marker` (`check-children-settled.sh" --log "$SESSION_LOG" --all`) — every caller must stay in step with the new flag; pinned by: `scripts/test-check-children-settled.sh` (`--all with missing log -> no_identity_rows, never unverifiable/settled`, `empty (but existing) log -> no_identity_rows`).
- **`loomwright/scripts/guard-finalize-publish.sh`** — keep: `write-marker` is the ONLY marker writer and refuses `session_log_missing` before running the join (`refuse "session_log_missing"`); `no_identity_rows` recorded verbatim, never as `settled` (`settled|no_identity_rows) check="$children_status"`); stale marker removed first (`rm -f "$MARKER"`); atomic temp+rename write; the guard (PreToolUse) mode stays fail-CLOSED with NO `|| true` on its `hooks.json` leaf; `--skip-children-check` today is read positionally (`[ "${2:-}" = "--skip-children-check" ]`) — a new arg parser must keep that invocation working; reuse: `read_session_block` / `resolve_root` / `LOG_DIR` for locating state.md; fired by: the `hooks.json` `PreToolUse[Bash]` leaf (guard mode, no argument — recorded by `build-capabilities.sh` as `w guard-finalize-publish.sh -`) and, in `write-marker` mode, FINALIZE Point 5 in `agents/supervisor.md` and `skills/async-orchestration/SKILL.md` plus every Phase 4.5 heal push in `skills/self-heal-advisory/SKILL.md` (`write-marker`) — any new `write-marker` argument must keep those invocations valid; pinned by: `scripts/test-guard-finalize-publish.sh` (`write_marker()` helper, `F2: write-marker never turns 'nothing to check' or 'no log' into settled`).
- **`loomwright/scripts/test-check-children-settled.sh`, `loomwright/scripts/test-guard-finalize-publish.sh`** — keep: every existing assertion unchanged and green (e.g. `--all with missing log -> no_identity_rows, never unverifiable/settled`, `F2: write-marker never turns 'nothing to check' or 'no log' into settled`); the static-only rule — fixtures in `mktemp -d`, no gh, no network (`gh/network/Docker. bash 3.2 / BSD userland safe.`, fixtures under `mktemp -d`); the `RESULT: N passed, M failed` tail and exit 1 on any failure; reuse: the files' own `ok`/`no` helpers, the `get` JSON reader, and the `write_marker()` / `$REALBASH` harness rather than new ones; fired by: `scripts/ci-local.sh` / `run-self-tests.sh` (weights in `scripts/fixtures/self-test-weights.tsv`).
- **`loomwright/agents/supervisor.md`** — keep: Point 5's `--skip-children-check` escape hatch, the interactive `AskUserQuestion` (proceed anyway / investigate / abort), the non-interactive `children_unsettled` fail-closed shape and the `children_check: no_identity_rows` report value; mirror: `skills/async-orchestration/SKILL.md` Point 5 (`children_check: no_identity_rows`) and `docs/FAILURE_ESCALATION.md` (`scripts/check-children-settled.sh --all finds ≥1 agent_identity row`); pinned by: `scripts/test-check-children-settled.sh` seam greps over Point 5 (`--all`, `children_unsettled`) and the `prompt-token-budgets.json` `supervisor` row (`"budget": 27488`).
- **`loomwright/skills/async-orchestration/SKILL.md`, `loomwright/skills/workflow-management/SKILL.md`** — keep: every field of the two worker `Task(...)` examples except `subagent_type` (`run_in_background: true`); the non-worker fixer spawns elsewhere stay `general-purpose`; async-orchestration is preloaded by `execute-manager` (its token budget `"budget": 38646` counts this file).

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Expected-id join + FINALIZE/marker wiring + one worker spawn shape | all | 11 modify, 1 create | `skills/unit-testing/SKILL.md`, `skills/async-orchestration/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/scripts/check-children-settled.sh", name: "--expect-id"}
  - {kind: "symbol", path: "loomwright/scripts/test-check-children-settled.sh", name: "expect-id"}
  - {kind: "symbol", path: "loomwright/scripts/guard-finalize-publish.sh", name: "expect-id"}
  - {kind: "symbol", path: "loomwright/agents/supervisor.md", name: "--expect-id"}
  - {kind: "symbol", path: "loomwright/skills/workflow-management/SKILL.md", name: 'subagent_type: "loomwright:worker"'}
  - {kind: "file", path: "changelog.d/agnostic-phase1-02-completion-evidence-integrity.md"}
requires: []
lanes:
  - "loomwright/scripts/check-children-settled.sh"
  - "loomwright/scripts/test-check-children-settled.sh"
  - "loomwright/scripts/guard-finalize-publish.sh"
  - "loomwright/scripts/test-guard-finalize-publish.sh"
  - "loomwright/agents/supervisor.md"
  - "loomwright/agents/execute-manager.md"
  - "loomwright/agents/context-keeper.md"
  - "loomwright/skills/async-orchestration/SKILL.md"
  - "loomwright/skills/workflow-management/SKILL.md"
  - "loomwright/skills/state-management/SKILL.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/docs/result-schemas/supervisor-result.md"
  - "loomwright/docs/FAILURE_ESCALATION.md"
  - "loomwright/docs/HOOKS.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "changelog.d/agnostic-phase1-02-completion-evidence-integrity.md"
external_requires:
  - "jq (already required by check-children-settled.sh)"
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Batch 1:** Subtask 1
- **Recommended workers:** 1
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/async-orchestration/SKILL.md` |

### Cited-line premise check

| ref | resolves | premise | deciding line | as of |
|-----|----------|---------|----------------|-------|
| `agents/supervisor.md:444` | yes | HOLDS (moved to 445) | `**Point 5 — children settled …** \`status: "no_identity_rows"\` … PASSES this point` | tip 30 minutes ago, fetched <1h |
| `agents/execute-manager.md:442` | yes | HOLDS | `settle = Bash(\`bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-children-settled.sh" --log {session_log_path} --agent-id {worker_id}\`)` | tip 30 minutes ago, fetched <1h |
| `skills/async-orchestration/SKILL.md:172` | yes | HOLDS | `subagent_type: "general-purpose",` (§"Spawning a Worker") | tip 30 minutes ago, fetched <1h |
| `skills/workflow-management/SKILL.md:232` | yes | HOLDS | `subagent_type: "general-purpose",` (§"Worker Dispatch") | tip 30 minutes ago, fetched <1h |
| `agents/execute-manager.md:185` | yes | HOLDS | `subagent_type: "loomwright:worker",` | tip 30 minutes ago, fetched <1h |
| `async-orchestration/SKILL.md:773` | yes | HOLDS (moved to 774) | `subagent_type: "loomwright:worker",` | tip 30 minutes ago, fetched <1h |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| `guard-finalize-publish.sh write-marker` is the mechanism that actually gates publish; changing only the Point 5 prose would leave the marker recording `no_identity_rows` on zero evidence | HIGH | AC5 — wire the expected ids into `write-marker` too; test it in `test-guard-finalize-publish.sh` |
| A `## Worker Results` heading id that is not the Task-returned agent id (older/hand-edited state.md) would now fail Point 5 closed | MEDIUM | Fail-closed is the intended posture; `--skip-children-check` stays the escape hatch; document the source surface and its id contract in the Point 5 prose and the PR body |
| Changing the default no-flag `--all` output would break pre-existing callers / old logs | MEDIUM | AC2 — no `--expect-id` ⇒ byte-identical; keep the existing tests unchanged and green |
| `supervisor.md` / `async-orchestration/SKILL.md` growth breaches `check-token-budget.sh` (supervisor 26181/27488, execute-manager 37027/38646 measured) | MEDIUM | Keep prose tight; if it breaches, raise per the raise rule in the same PR (+ ARCHITECTURE_CONTRACTS mirror row) |
| Mutation control silently invalid (empty or unchanged mutant) | MEDIUM | Lesson fa32a308 — gate the mutant on non-empty + differs-from-original + `bash -n` |
| Sibling lanes of this wave also edit `agents/supervisor.md` / `ARCHITECTURE_CONTRACTS.md` / `prompt-token-budgets.json` | LOW | Edits are local to Point 5 / the two spawn examples; merge order resolved at the wave's release |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-09-agnostic-phase1-02-completion-evidence-integrity.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-10-09T19:13:44Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/445
- **Branch:** feature/agnostic-phase1-02-completion-evidence-integrity
- **Files changed:** 16
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** check-children-settled.sh --all gains repeatable --expect-id (fails closed on missing evidence; no-flag output unchanged); FINALIZE Point 5 and guard-finalize-publish.sh write-marker pass the ## Worker Results heading ids; both skill worker-spawn examples use loomwright:worker. Phase 4.5 code review PASS on iteration 1 with 3 MEDIUM findings dismissed below the fix floor; ground truth 2/2.

## Not verified
- **live multi-worker Supervisor FINALIZE Point 5 / write-marker on a real run** — only static fixtures and this run's single-worker FINALIZE exercised it (subtask 1)
