# Supervisor Job: A run that ends must stop owning the log — run ownership and session close-out

## Environment
- **Project:** ~/Documents/work/AI/loomwright-stateloop
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: fix/run-ownership-and-session-close-out
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1
- **Source requirement:** .supervisor/requirements/state-loop-fix/01-run-ownership-and-session-close-out.md

> **Warning (1):** this repository is checked out in three sibling worktrees and a second Claude
> session is active in `~/Documents/work/AI/ai-agent-manager` on
> `feature/floor-ui-redesign`. THIS worktree is isolated and cut from `origin/main` @ `b3ef8f3`
> (0 commits ahead). Do not `cd` outside this worktree; do not use bare `git stash`.

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure bash 3.2 + `jq` + `python3` + JSON/markdown — exactly the repo's existing surface. No new runtime dependency. |
| 2 | Dependency Availability | GO | `jq` (functionally probed, not just `command -v`), `python3`, `git`, `gh`, `awk`, `sed` all present. |
| 3 | Architecture Fit | GO | Strengthens the existing fail-SAFE emitter contract in CLAUDE.md §Failure-Mode Invariants. Adds no gate, changes no schema enum. |
| 4 | Scope vs Supervisor Capability | CAUTION | Six related parts (A–F) that share files. Correctly ONE subtask (see Configuration), but it is a wide single subtask: 16 lanes (14 modify, 2 create). |
| 5 | Hard Blockers | GO | No migration, no credentials, no missing module. Every path named for modification exists on disk; both create targets confirmed absent. |

**Overall Verdict:** GO (1 CAUTION finding carried into Risk Assessment)

## Task
**Goal:** Stop a finished Supervisor run from capturing later sessions' hook events, and make a run that ends without completing say so mechanically.

**Problem Statement:**
The plugin's own state machine needs a run to relinquish its log when it ends, because nothing currently makes it do so.
Currently, `.supervisor/state.md` is pinned at `status: running` / `phase: EXECUTE` from a run started **2026-07-29** whose brief is already in `jobs/done/` and which **never emitted a `session_end`**. Because both emitters adopt the plugin `session_id` whenever status is `running`/`checkpoint`, every SubagentStop firing from every later session is appended to that one run's log — measured at **14,416 lines, 3.9 MB, 140 distinct `cc_session_id`s**. `build-state.sh` then derives status from the last of `{subtask_complete, session_end}` in that same log, which is always a fresh foreign `subtask_complete`, so it re-asserts `running`. The stale status causes the fan-in and the fan-in re-asserts the stale status.
This causes the Floor to render ordinary interactive chat turns as a live Supervisor run (four `identity unknown` lanes, a bogus `QUEUE 1 / EXECUTE` pipeline), corrupts `/insights` and postmortem history with 140 interleaved sessions, and leaves the one on-disk file that answers "is a run in flight?" permanently lying.
Success looks like: a foreign session's firing provably lands in its own log file, `state.md` reaches a terminal status without any agent being told to remember to write one, and the polluted log stops growing.

## Acceptance Criteria
- [ ] Given a payload whose `session_id` equals the log's first-line `cc_session_id`, when either emitter runs, then it still joins on the plugin session id (existing behavior preserved).
- [ ] Given a payload whose `session_id` is a foreign uuid, when either emitter runs, then the line is written to `<foreign-uuid>.jsonl` and the owned log's line count is unchanged.
- [ ] Given an absent, empty, or unreadable log, or a first line carrying no `cc_session_id`, when either emitter runs, then it adopts the plugin session id — all four cases asserted separately.
- [ ] Given a non-terminal `state.md` owned by this session, when `close-stranded-run.sh` runs, then exactly one `session_end` carrying `status: failed` and `reason: session_ended_without_completion` is appended, that record carries BOTH the canonical `event` and the legacy `type` key (the contract `build-insights.sh` filters on), and `state.md` is terminal afterwards.
- [ ] Given a non-owner session, and separately given an already-terminal `state.md`, when `close-stranded-run.sh` runs, then it writes nothing and exits 0 — both cases asserted.
- [ ] Given a log whose newest owner-originated line is older than the threshold, when `build-state.sh` projects, then status is `failed`; and given a log with fresh FOREIGN lines but a stale OWNER line, then status is still `failed`.
- [ ] Given `LOOMWRIGHT_AGENT_TYPE` set and no payload `agent_type`, when either emitter runs, then the line carries the env value; with both present the payload wins; with neither the key is absent (not empty-string, not null).
- [ ] Given unreadable `state.md`, unreadable log, absent `jq`/`python3`, or a malformed first line, when any changed script runs, then it exits 0 — asserted explicitly.
- [ ] Given the ownership gate is reverted, when the ownership tests run, then at least one FAILS, and the reverted hunk plus the name and output of the failing test are recorded verbatim in `WORKER_RESULT` and the PR body (mutation control — a test that passes with the mechanism deleted does not count, and an unrecorded control is self-attested and does not satisfy this).
- [ ] Given Part F has run on the main checkout, when `.supervisor/state.md` is read and `.supervisor/logs/8d43da72-9b5b-4793-8599-d06e27b3a8b3.jsonl` is line-counted twice several minutes apart across ordinary session activity, then the status is terminal and the line count is unchanged.
- [ ] Given the whole change, when `scripts/check-doc-currency.sh`, `loomwright/scripts/test-citation-drift.sh` and every `loomwright/scripts/test-*.sh` run, then all exit 0.
- [ ] Given Part E, when the run reports, then it states either the confirmed duplicate mechanism with its fix, or that the probe was inconclusive and the emitter was left alone.

## Outcomes Rubric

- The self-reinforcing loop is broken at its cause — a finished run cannot capture a live session's events — not merely patched by resetting `state.md`.
- A run that ends without completing now says so mechanically, with no agent instructed to remember to do it.
- Both emitters still always exit 0, and the unknown-owner path still adopts.
- The ownership assertions are mutation-controlled and demonstrably non-vacuous.
- The Floor stops attributing interactive chat turns to a Supervisor run.
- The known limit (resume under a different session id) is documented rather than hidden.
- Every doc surface that states a count, a status vocabulary, or an assertion total is updated in the same commit.
- Nothing in the change can block a run.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Run ownership gate, SessionEnd close-out, staleness backstop, agent identity, duplicate probe, and the one-time close-out | ALL (AC-1 … AC-12) | 14 modify, 2 create | `state-management`, `quality-checklist`, `unit-testing`, `error-handling` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1 — the whole change (LAUNCHABLE; no siblings)
provides:
  - {kind: "file",   path: "loomwright/scripts/close-stranded-run.sh"}
  - {kind: "file",   path: "loomwright/scripts/test-close-stranded-run.sh"}
  - {kind: "symbol", path: "loomwright/scripts/emit-token-ledger.sh",   name: "loom_log_owner"}
  - {kind: "symbol", path: "loomwright/scripts/emit-progress-event.sh", name: "loom_log_owner"}
  - {kind: "symbol", path: "loomwright/hooks/hooks.json",               name: "SessionEnd"}
  - {kind: "symbol", path: "loomwright/hooks/hooks.json",               name: "LOOMWRIGHT_AGENT_TYPE"}
  - {kind: "symbol", path: "loomwright/scripts/build-state.sh",         name: "LOOMWRIGHT_STALE_RUN_SECONDS"}
  - {kind: "symbol", path: "loomwright/docs/TELEMETRY.md",              name: "Run ownership"}
  - {kind: "symbol", path: "loomwright/docs/HOOKS.md",                  name: "close-stranded-run.sh"}
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md",         name: "session_ended_without_completion"}
requires: []
lanes:
  - "loomwright/scripts/emit-token-ledger.sh"
  - "loomwright/scripts/emit-progress-event.sh"
  - "loomwright/scripts/build-state.sh"
  - "loomwright/scripts/close-stranded-run.sh"
  - "loomwright/scripts/test-close-stranded-run.sh"
  - "loomwright/scripts/test-progress-state.sh"
  - "loomwright/scripts/test-token-ledger.sh"
  - "loomwright/hooks/hooks.json"
  - "loomwright/docs/TELEMETRY.md"
  - "loomwright/docs/HOOKS.md"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/skills/state-management/SKILL.md"
  - ".claude-plugin/README.md"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - "CLAUDE.md"
external_requires:
  - "Claude Code `SessionEnd` hook event (platform-provided; hooks.json registers zero today)"
```

**Exact-name mandate:** the `provides` names above are the literal identifiers the implementation MUST create — `loom_log_owner` (the shared owner-resolution helper, defined identically in both emitters), `LOOMWRIGHT_STALE_RUN_SECONDS` (the env-overridable threshold), `LOOMWRIGHT_AGENT_TYPE` (the hooks.json env prefix), a `### Run ownership` heading in `TELEMETRY.md` (that file uses `###`), a literal `close-stranded-run.sh` cell in `HOOKS.md`'s table (that file's rows already address scripts by bare basename cell — do not invent a heading there), and the literal `session_ended_without_completion` in `RESULT_SCHEMAS.md` §"`session_end` JSONL hard-signal fields", which is the DECLARED schema source for that record and must document the new `reason` key. Renaming any of these silently voids the `outputs_verified` gate.

## Parallelism Analysis

### Dependency Graph
Single subtask — no graph.

### File Overlap Matrix
Not applicable (one subtask). The overlap analysis is what *forced* the single-subtask shape: Parts A and D both edit **both** emitters, Parts B and D both edit `hooks.json`, and Part F depends on Part A having landed. Any split would manufacture a file conflict rather than relieve one.

### Batch Plan
One batch, one worker.

## Skill References

| Skill | Why |
|---|---|
| `skills/state-management/SKILL.md` | State-file schema, the closed `status`/`phase` enums, and the one-writer invariant this change must not break |
| `skills/quality-checklist/SKILL.md` | Pre/post-implementation gates |
| `skills/unit-testing/SKILL.md` | Assertion structure for the three test suites |
| `skills/error-handling/SKILL.md` | Fail-SAFE emitter discipline (always `exit 0`) |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Ownership assertions pass with the mechanism deleted (vacuous test) | HIGH | AC-9 mandates an explicit mutation control: revert the gate alone and confirm a test fails. Source: this repo's recorded "shared fixture default disarms its own assertion" lesson |
| Unknown-owner path made to REFUSE instead of ADOPT | HIGH | Non-negotiable 2 in the requirement; AC-3 asserts all four degenerate inputs separately. Refusing would regress every fresh run's first worker completion |
| An emitter made to exit non-zero on a new failure path | HIGH | CLAUDE.md §Failure-Mode Invariants — emitters fail SAFE. AC-8 asserts exit 0 explicitly across five degenerate inputs |
| `paused` emitted as the close-out status | MEDIUM | Frozen decision D2: `paused` is classified live by `hook-dispatch-on-pr-create.sh` and dead by both emitters. Only `failed` is used |
| Wide single subtask spans 16 lanes (Feasibility CAUTION 4) | MEDIUM | Acceptance criteria are the per-file checklist; Phase 4.5 holistic review is the integration lens |
| Part E's mechanism is unestablished | MEDIUM | AC-11 permits an explicit "inconclusive, emitter untouched" outcome. Guessing is forbidden |
| Hook count 24 → 25 breaks `check-doc-currency.sh` | MEDIUM | Two claims in `.claude-plugin/README.md` (the tree comment and the prose line) must move in the same commit; `corpus-task: doc-currency-green` verifies it advisorily |
| `TELEMETRY.md`'s hard-coded "117 assertions" claim goes stale | LOW | No mechanical gate catches it — the requirement names it explicitly as a release-surface obligation |
| Part A drifts EXISTING pinned citations to the line it edits | HIGH | Verified: root `CLAUDE.md` (the citation-convention rule, which pins `emit-token-ledger.sh:128` to `` `running|checkpoint)` ``) and `emit-progress-event.sh`'s own `checkpoint` note both pin that exact line, and `test-citation-drift.sh` scans root `CLAUDE.md`. Both pin sites are in `lanes` and MUST be re-pinned in the same commit or CI fails closed |
| A NEW bare `file.ext:N` citation fails `test-citation-drift.sh` | LOW | Use `[pins: \`literal\`]` or a descriptive anchor; the bare-citation allowlist holds exactly one grandfathered entry and only ratchets down |
| Concurrent session on the sibling checkout | LOW | This worktree is isolated; never `cd` out of it, never bare `git stash` (the stash stack is shared) |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/auto-2026-09-05-121712-run-ownership-and-session-close-out.md
```

---

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/186
- **Branch:** feature/run-ownership-close-out
- **Commits:** 040a050 (base) → 6a9aaa6 (heal 1) → e76472f (heal 2) → 8b6e6c7 (heal 3)
- **Heal loop ran:** true
- **Heal iterations:** 3
- **Heal decision:** PASS
- **Rubric score:** 8/8
- **Remaining issues:** 1 LOW (comment wrap width in emit-token-ledger.sh)
- **Until-mergeable dispatched:** false
- **Suites:** test-token-ledger 155/0 (8 consecutive), test-progress-state 161/0, test-close-stranded-run 55/0; 69/70 suites green (test-setup-ui k28 environmental — live Floor server rewriting the user-scope ui tree)
- **Part E:** duplicate mechanism CONFIRMED (94/94 typed firings → 1 line; 4,376/4,376 untyped → 2) and fixed; "why 2 and not 3" left as a documented open question rather than guessed
- **Part D outcome — scope REDUCED on measurement:** the agent-identity fix was implemented and then deliberately REMOVED. Grouping untyped events by agent_id gives exactly 2 token_ledger : 1 subtask_complete in every bucket, proving the hook matcher does NOT discriminate, so injecting it would have fabricated identity. Floor lanes still read `identity unknown`; documented as an accepted limit.
- **Part F:** NOT done here — closing out the stale 2026-07-29 run is a one-time data step against the main checkout, not this worktree.
