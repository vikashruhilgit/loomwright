# Supervisor Job: Children-settled gate — every SubagentStop settles, and the check runs before anything is published

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes-v2/s3-j
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/automate-followups/33-children-settled-gate.md
- **Base commit:** f4b0732b8f3e6a7b64fc960073e8ab680d5af9f0

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + jq hook scripts and markdown prose, the plugin's existing stack |
| 2 | Dependency Availability | GO | jq, git, gh already required by the sibling scripts; no new dependency |
| 3 | Architecture Fit | GO | Part A extends the existing fail-SAFE `emit-lifecycle.sh` emitter and the one join `check-children-settled.sh`; Part B follows the shipped fail-CLOSED `guard-test-integrity.sh` PreToolUse[Bash] precedent |
| 4 | Scope vs Supervisor Capability | CAUTION | Two parts on one branch; they share `check-children-settled.sh`, `hooks/hooks.json`, `docs/HOOKS.md` and the agent-lifecycle schema doc (file-conflict ⇒ one subtask), ~12 files + 2 new scripts |
| 5 | Hard Blockers | CAUTION | Whether Claude Code fires `SubagentStop` when a subagent hits `maxTurns`, and what the payload carries then, is unverified from the repo alone — must be probed (CLAUDE.md "probe the runtime once and pin the documented shape") |

**Overall Verdict:** CAUTION

## Task
**Goal:** Make `check-children-settled.sh --all` read a finished non-plugin (`general-purpose`, `Explore`) spawn and a turn-limit-stopped child as settled (Part A), and make a Supervisor run unable to `git push` its feature branch or `gh pr create` until FINALIZE point 5 has passed for the current session and HEAD (Part B).

**Problem Statement:**
Supervisor operators need the FINALIZE children-settled gate to carry signal because it currently asks false questions and can be run out of order.
Currently, terminal lifecycle rows (`subtask_complete` / `token_ledger` / `agent_lifecycle: failed`) are written only by the per-type `SubagentStop` matchers in `hooks/hooks.json` (all `loomwright:*`), while `agent_identity` rows are written for EVERY Task spawn by `PostToolUse[Task]` → `emit-agent-identity.sh`. A `general-purpose`/`Explore` spawn therefore never settles, and plugin agents that stopped at their turn limit (context-keeper at 3, worker at 40) have been observed with no terminal row — four occurrences (S1 v2, w1-08, w2-30, S3 #408 with 7 agents), every one answered "proceed anyway". Separately, point 5 is a numbered list in prose: lane v2-b ran it AFTER pushing and opening PR #372, and nothing refused that.
Success looks like: a session log with a settled general-purpose spawn and with a turn-limit stop reads `settled`; a hung child (identity row, no stop) still reads `unsettled`; and in a Supervisor session a push/PR before a passing point 5 is refused by a hook.

## Acceptance Criteria

### Part A — every SubagentStop leaves a terminal row
- [ ] A1. Given any subagent stop (any `agent_type`, plugin or not), when `SubagentStop` fires, then exactly one terminal `agent_lifecycle` row is appended to the session log for that `agent_id` (proposed shape: `{"event":"agent_lifecycle","state":"ended","agent_id":…,"agent_type":…,"reason":…}` — `reason` copied verbatim from the payload when it carries a stop reason such as a turn-limit marker, else `stop`; never derived from message text, never invented). Emitted by a new `emit-lifecycle.sh ended` subcommand wired as a matcher-less (catch-all) `SubagentStop` hook leaf with `|| true` (fail-SAFE emitter, always exit 0).
- [ ] A2. Given a session log whose only rows for an `agent_id` are `agent_identity` + `agent_lifecycle: working` + `agent_lifecycle: ended`, when `check-children-settled.sh --all` (and `--agent-id`) runs, then that id reads `settled`.
- [ ] A3. Given an `ended` row whose reason marks a turn-limit stop, or a plugin `worker` whose `ended` row is its only terminal row (no `subtask_complete`), then `ended_without_result` is `true` for that id (surfaced for SendMessage resume), while a plain `ended` for a non-worker reads `ended_without_result: false`. The precise rule is documented in the script header and `docs/result-schemas/agent-lifecycle-jsonl.md`.
- [ ] A4. Given an `agent_identity` row with NO stop row at all (a hung or still-running child), then `--all` still reads `unsettled` — the check is never silently dropped or scoped away.
- [ ] A3b. **Accepted semantic change (stated, not hidden):** `ended_without_result` is record-only at every consumer today (execute-manager `outputs_verified`, supervisor Single-Agent step 3b and the Sequential Path only surface it). So after this change a worker stopped at its turn limit reads `settled` and completes through `outputs_verified` whenever its `provides` are on disk — the SAME class as `result_block_present: false` today, still gated by `verify-provides.sh`. This is accepted and documented in `docs/result-schemas/agent-lifecycle-jsonl.md`; every restated definition of `ended_without_result` (grep repo-wide — execute-manager.md, supervisor.md, async-orchestration SKILL.md, the schema doc) gains the new cause.
- [ ] A3c. `scripts/build-floor.sh`'s lifecycle reader (state allowlist documented as "the three the emitter ever writes") is updated to admit `ended` so a finished spawn stops showing as `working`, with a `test-build-floor.sh` case; its comment is corrected.
- [ ] A5. Given a `subtask_complete` row with `rejected: true` followed by an `ended` row for the same SubagentStop firing, the rejected-stop semantics (v15.83.0: a rejected worker stop is NOT terminal) are preserved — the worker's catch-all `ended` row must not settle a validator-rejected stop. The worker traces the hook firing order and states how this is guaranteed (e.g. `ended` carries no settle effect for an id whose latest `subtask_complete` is `rejected: true`, or the emitter re-runs the validator the way `emit-progress-event.sh` does and skips when it blocked), with a fixture. Non-worker validated roles (code-reviewer, qa-executor, execute-manager, supervisor-runner, plan-reviewer, launch-pad-runner) whose stop a validator rejects are settled by the `ended` row exactly as their `token_ledger` row already settles them today — a pre-existing gap, accepted and noted in the schema doc, not widened.
- [ ] A6. The runtime facts the design depends on (does `SubagentStop` fire on a `maxTurns` stop; does the payload carry `agent_type` / a stop reason for a `general-purpose` spawn) are probed once on this Claude Code version and pinned as a fixture under `loomwright/scripts/fixtures/` (precedent: `subagentstop-decision-shape-probe.json`); anything not observable is listed under "Not verified" with its reason, never asserted.

### Part B — the check runs before anything is published, by mechanism
- [ ] B1. The marker is written ONLY by a script, never by prose: a thin writer (a new mode/wrapper — `check-children-settled.sh` itself stays fail-SAFE and read-only, per its header) that itself runs `check-children-settled.sh --log .supervisor/logs/<plugin_session_id>.jsonl --all` (or records an explicit `--skip-children-check`) and, ONLY on `status: settled` (or `no_identity_rows`, documented) or the skip, writes `.supervisor/logs/<plugin_session_id>.finalize-gate` holding `{children_check: "settled"|"skipped", head_sha, ts}`. Any other outcome writes nothing and removes a stale marker. The marker is keyed by the PLUGIN session_id (the `## Session` block's `- session_id:` in `.supervisor/state.md`), not the Claude Code session UUID.
- [ ] B2. Session join (the two ids differ): the guard reads the plugin `session_id` from `.supervisor/state.md`'s `## Session` block (non-terminal status), opens `.supervisor/logs/<plugin_session_id>.jsonl`, and treats the run as THIS session's Supervisor run only when that log's owner `cc_session_id` equals the hook payload's `session_id` — REUSING `emit-lifecycle.sh`'s run-ownership rule (`loom_log_owner`, extracted to a shared sourceable helper if needed), never restating it. When that join holds and there is no marker, or the marker's `head_sha` ≠ current HEAD, a `git push` or `gh pr create` Bash call is denied by a new `PreToolUse[Bash]` fail-CLOSED hook (exit 2 + `permissionDecision: "deny"`, reason "run FINALIZE point 5 first"), with NO `|| true` on its hooks.json leaf. **Resumed session** (`/supervisor --continue` in a new Claude Code session, so the log owner is a different `cc_session_id`): the worker decides deny-vs-allow, documents it in the guard header and HOOKS.md, and covers it with a V3 test — preferred: treat a non-terminal `## Session` whose log owner differs as a resumed run of the same checkout and still require the marker (fail CLOSED), since `--continue` is a documented Supervisor path that also reaches FINALIZE.
- [ ] B3. Given a marker for the current session whose `head_sha` equals HEAD, then the push / PR create is allowed.
- [ ] B4. Given a non-Supervisor session (no `## Session` block, or a different/terminal session), a drain fix push, or a human push, then the hook allows without reading further (cheap-first evaluation, no `jq` on the inert path, mirroring `guard-test-integrity.sh`).
- [ ] B5. FINALIZE point 5 prose (`skills/async-orchestration/SKILL.md` §"Phase 4 FINALIZE procedure" and `agents/supervisor.md` Point 5) states that the push and PR are blocked until the marker exists, and how the marker is written.
- [ ] B6. `CLAUDE.md` §"Plugin Hooks" and `docs/HOOKS.md` are updated so they no longer claim the test-integrity guard's two leaves are the ONLY command-hook leaves without `|| true`; the new guard's arm/allow/deny contract gets its own row. No literal hook count is restated (house rule: counts live in `hooks.json`).

### Validation (from the requirement — PR body, labelled by part)
- [ ] V1. Baseline full loop once for base and branch: `<passed>/<total>` and `SKIP` counts (`bash scripts/ci-local.sh`).
- [ ] V2. Part A: the fixture "settled general-purpose spawn ⇒ settled" and "turn-limit stop ⇒ settled" pass; mutation control: removing the `ended` arm from the terminal join makes them fail.
- [ ] V3. Part B tests: push before the check ⇒ blocked; after a passing check ⇒ allowed; HEAD moved after the check ⇒ blocked; `--skip-children-check` ⇒ allowed and recorded; non-Supervisor session / drain push / human push ⇒ untouched; the session join uses the log-owner `cc_session_id` (a fixture where state.md's plugin id ≠ payload id but the log owner matches ⇒ guard ACTIVE); resumed session per B2's documented choice; the marker writer refuses on `unsettled` (no marker); mutation control: removing the marker check makes the "push before check" test fail.
- [ ] V4. Running system: this very Supervisor run is the "one real single-agent Supervisor run" — paste the marker and the push order from its own session log into the PR body; anything not run goes under "Not verified" with the reason.
- [ ] V5. Rollback: `git revert` (the marker file is inert without the guard; the `ended` row is additive).

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Children-settled gate: terminal row for every SubagentStop + pre-publish guard | A1–A6, B1–B6, V1–V5 | 14 modify, 4 create (+ conditional budget surfaces) | `skills/async-orchestration/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |

## Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/scripts/emit-lifecycle.sh", name: "ended"}
  - {kind: "symbol", path: "loomwright/scripts/check-children-settled.sh", name: "ended"}
  - {kind: "file", path: "loomwright/scripts/guard-finalize-publish.sh"}
  - {kind: "file", path: "loomwright/scripts/test-guard-finalize-publish.sh"}
  - {kind: "symbol", path: "loomwright/hooks/hooks.json", name: "guard-finalize-publish.sh"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/agent-lifecycle-jsonl.md", name: "ended"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/supervisor-result.md", name: "finalize-gate"}
  - {kind: "symbol", path: "loomwright/skills/async-orchestration/SKILL.md", name: "finalize-gate"}
  - {kind: "symbol", path: "loomwright/agents/supervisor.md", name: "finalize-gate"}
  - {kind: "symbol", path: "loomwright/docs/HOOKS.md", name: "guard-finalize-publish.sh"}
  - {kind: "symbol", path: "CLAUDE.md", name: "guard-finalize-publish.sh"}
  - {kind: "symbol", path: "loomwright/scripts/build-floor.sh", name: "ended"}
  - {kind: "file", path: "changelog.d/automate-followups-33-children-settled-gate.md"}
requires: []
lanes:
  - "loomwright/scripts/emit-lifecycle.sh"
  - "loomwright/scripts/test-emit-lifecycle.sh"
  - "loomwright/scripts/check-children-settled.sh"
  - "loomwright/scripts/test-check-children-settled.sh"
  - "loomwright/scripts/guard-finalize-publish.sh"
  - "loomwright/scripts/test-guard-finalize-publish.sh"
  - "loomwright/scripts/fixtures/**"
  - "loomwright/hooks/hooks.json"
  - "loomwright/docs/HOOKS.md"
  - "loomwright/docs/result-schemas/agent-lifecycle-jsonl.md"
  - "loomwright/docs/result-schemas/supervisor-result.md"
  - "loomwright/skills/async-orchestration/SKILL.md"
  - "loomwright/agents/supervisor.md"
  - "loomwright/agents/execute-manager.md"
  - "loomwright/scripts/build-floor.sh"
  - "loomwright/scripts/test-build-floor.sh"
  - "loomwright/docs/result-schemas/schema-versioning.md"
  - "loomwright/docs/FLOOR_UI.md"
  - "loomwright/scripts/guard-test-integrity.sh"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "CLAUDE.md"
  - "changelog.d/automate-followups-33-children-settled-gate.md"
external_requires:
  - "Claude Code SubagentStop / PreToolUse[Bash] hook runtime (payload shape probed, not assumed)"
```

## Parallelism Analysis
single-agent (no fan-out)

- **Batch 1:** Subtask 1
- **Recommended workers:** 1
- **Estimated batches:** 1

## File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| Part A — emitter + join + readers | `loomwright/scripts/emit-lifecycle.sh`, `loomwright/scripts/test-emit-lifecycle.sh`, `loomwright/scripts/check-children-settled.sh`, `loomwright/scripts/test-check-children-settled.sh`, `loomwright/agents/execute-manager.md` (restated `ended_without_result` definition), `loomwright/scripts/build-floor.sh`, `loomwright/scripts/test-build-floor.sh` (lifecycle state allowlist) | `loomwright/scripts/fixtures/subagentstop-maxturns-probe.json` (name is the worker's call) | HIGH |
| Part B — publish guard | `loomwright/skills/async-orchestration/SKILL.md`, `loomwright/agents/supervisor.md` | `loomwright/scripts/guard-finalize-publish.sh`, `loomwright/scripts/test-guard-finalize-publish.sh` | HIGH |
| Shared — hooks + docs | `loomwright/hooks/hooks.json`, `loomwright/docs/HOOKS.md`, `loomwright/docs/result-schemas/agent-lifecycle-jsonl.md`, `loomwright/docs/result-schemas/supervisor-result.md`, `CLAUDE.md` | `changelog.d/automate-followups-33-children-settled-gate.md` | HIGH |
| Validator-owned surfaces | `loomwright/docs/prompt-token-budgets.json` + `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" ONLY if `agents/supervisor.md` grows past its declared budget (`check-token-budget.sh`); any doc surface `scripts/check-doc-currency.sh` scans if a hook count claim exists there | — | MEDIUM |

## Implementation Notes (from Phase 3 analysis — data, verify before relying)
- `agent_identity` rows: `hooks.json` `PostToolUse[Task]` → `scripts/emit-agent-identity.sh` (every Task spawn, any type). Terminal rows today: `SubagentStop[loomwright:worker]` → `emit-progress-event.sh` (`subtask_complete`); every other `loomwright:*` SubagentStop matcher → `emit-token-ledger.sh` (`token_ledger`); `StopFailure` → `emit-lifecycle.sh failed`. There is NO matcher for non-plugin agent types — that is Part A's asymmetry. Why the context-keeper/worker turn-limit stops left no row despite having matchers is to be TRACED (A6) — candidates: SubagentStop not fired on `maxTurns`, or `emit-token-ledger.sh` / `emit-progress-event.sh` no-op'ing on that payload (session-id resolution, run-ownership gate, empty transcript). The fix must hold either way: the catch-all `ended` row is the floor.
- `emit-lifecycle.sh` already owns `waiting` / `heartbeat` / `failed` with the shared session-id resolution + run-ownership gate + worktree-safe anchoring — `ended` follows the same discipline (`set -u`, no `set -e`, `trap 'exit 0' EXIT`, additive-if-present fields only).
- `check-children-settled.sh` is the ONE join consumed at four call sites (execute-manager outputs_verified, supervisor Single-Agent step 3b, Sequential path, FINALIZE `--all`) — extend `terminal_for`, do not restate the OR elsewhere. Per-subtask (`--agent-id`): an `ended` row with no `subtask_complete` settles the agent and reports `ended_without_result: true`. This is NOT fail-closed — `ended_without_result` is record-only at every consumer — and is the accepted change stated in A3b.
- Part B pattern: `scripts/guard-test-integrity.sh` (fail-CLOSED PreToolUse[Bash], exit 2 + `hookSpecificOutput.permissionDecision: "deny"`, bash 3.2, cheap-first evaluation, `CLAUDE_PROJECT_DIR`-anchored). The marker writer is a SCRIPT that runs the check itself (B1) — never prose and never a hand `Write` by the Supervisor, which would let the same agent forge the marker. Keep `check-children-settled.sh` itself fail-SAFE and read-only (its header invariant: "never writes"); a thin wrapper or a mode of the new guard script is fine.
- Match `git push` / `gh pr create` conservatively on the command string (including `&&`-chained and `cd … &&` forms); a non-match allows. Never block a push to a branch other than the session's recorded feature branch (drain fix pushes run in their own sessions/worktrees; the session-id match is the primary scope).
- Do NOT bump the version — the PR carries only the `changelog.d/` fragment (`changelog.d/README.md`); the wave bump is run separately.
- Pre-push test run: `bash scripts/ci-local.sh` and nothing else (CLAUDE.md §"Pre-push test run?").

## Skill References
- `skills/async-orchestration/SKILL.md` (FINALIZE point 5 prose)
- `skills/unit-testing/SKILL.md` (static co-located `test-*.sh`, stubbed deps, mutation controls)

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

## Risk Assessment
| Risk | Impact | Mitigation |
|------|--------|------------|
| Runtime may not fire `SubagentStop` on a `maxTurns` stop (source: Feasibility (Phase 2.5)) | HIGH | Probe first (A6). If it does not fire, the turn-limit half of Part A cannot be fixed by a SubagentStop row — document the limit, keep the general-purpose half, and do NOT widen the join to treat silence as settled |
| A catch-all `ended` row settles a validator-rejected worker stop, re-opening the v15.83.0 bug | HIGH | A5 fixture; `ended` must not override a latest `rejected: true` stop |
| A fail-CLOSED PreToolUse[Bash] hook that mis-scopes blocks every push in every session (human, drain, other repos using the plugin) | HIGH | Cheap-first inert path (no `.supervisor/state.md` `## Session` match ⇒ allow, no jq); tests for non-Supervisor / drain / human push; deny only on a positive Supervisor-session match |
| The new guard blocks this very Supervisor run's own FINALIZE push if the marker is not written first (the guard ships in the PR, but hooks load from the installed plugin) | MEDIUM | The installed plugin (15.124.0) is unaffected; note in the PR that V4's "real run" uses the installed plugin, so the guard's live effect is verified by its tests, not by this run — list under "Not verified" if so |
| Hook-count / "ONLY two leaves without `\|\| true`" claims elsewhere (CLAUDE.md, HOOKS.md, ARCHITECTURE_CONTRACTS.md) go stale (source: verified lesson 0d7865dc) | MEDIUM | grep the old claim text repo-wide, not only the doc-currency gate |
| Subtask size vs the worker's 40-turn limit — two parts, ~18 files in one subtask (source: Feasibility (Phase 2.5), check 4) | MEDIUM | Do Part A first and commit it, then Part B, then docs; commit after each so a turn-limit stop loses nothing and a continuation worker resumes cleanly; list anything unfinished in the PR |
| `agents/supervisor.md` prose growth trips `check-token-budget.sh` | LOW | Keep point-5 prose additions terse; adjust the budget row only if the measured weight requires it |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-10-07-automate-followups-33-children-settled-gate.md

## Outcome
- **Status:** completed
- **Completed:** 2026-10-07T06:49:46Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/410
- **Branch:** feature/automate-followups-33-children-settled-gate
- **Files changed:** 29
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Part A: `agent_lifecycle` `ended` row from a catch-all SubagentStop leaf and from PostToolUse[Task] on a blocking return (maxTurns does not fire SubagentStop on 2.1.286, pinned fixture); join reads it as a lower-tier terminal row. Part B: guard-finalize-publish.sh — script-only finalize-gate marker writer + fail-CLOSED PreToolUse[Bash] push/PR guard. Phase 4.5: review iter 1 FAIL (V1 base baseline missing from PR body) → fixed inline in the PR body → iter 2 PASS; 6 MEDIUM/LOW findings dismissed below the fix floor. Ground truth 2/2.

## Not verified
- **live PreToolUse[Bash] guard firing in a real Supervisor session** — hooks load from the installed plugin 15.124.0; verified by test-guard-finalize-publish.sh and a direct run on this run's real state (subtask 1)
- **background child stopped at its turn limit** — neither hook seam observed to fire; documented honest limit, stays unsettled (subtask 1)
- **general-purpose / Explore SubagentStop payload agent_type on 2.1.286** — committed evidence is a custom non-plugin type on an earlier runtime (subtask 1)
