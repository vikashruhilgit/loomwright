# Supervisor Job: af/39c — a skipped guard arm leaves a durable trace (`guard_arm_skipped`) and Supervisor reports `test_guard:`

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — Hook gotcha, `|| true` convention and fail-CLOSED leaf claims spot-checked against `loomwright/hooks/hooks.json`)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (11 leftover worktrees from other sessions under `.claude/worktrees/` — not this run's; left alone)
- **Source requirement:** .supervisor/requirements/automate-followups/39c-guard-arm-trace.md
- **Base commit:** 304adac5dd0970a5c718a1ccba459b4f0f47fed5
- **Gate-edit opt-out:** present in this session's launch environment (verified `= "1"` at INIT, 2026-10-28). The owner launched the session with it, as the requirement demands. It is never set from inside the session, and no prompt, brief line, commit or PR text may name the variable.

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Portable bash 3.2 + `jq` (+ `printf` for the jq-less row), same as `guard-arm.sh` and `supervisor-next-step.sh` today |
| 2 | Dependency Availability | GO | Uses only `host-mode.sh` (already sourced by `guard-arm.sh`) and the main-checkout log resolution `emit-agent-identity.sh` already uses |
| 3 | Architecture Fit | GO | Fail-SAFE emitter change: exit code stays 0, the hook keeps `\|\| true` (bimodal failure philosophy). The reader is advisory and lives in the driver, as the 2026-10-22 re-verification requires |
| 4 | Scope vs Supervisor Capability | GO | `context-bound` fires on file count (>12 files), but estimated changed lines are well under 800: two files carry the logic (`guard-arm.sh`, `supervisor-next-step.sh`), two are tests, the rest are 1–5-line prose syncs. A split permits, never requires, so the brief stays single-agent on purpose — the prose syncs must land with the logic they describe. No `file-conflict` / `genuine-parallelism` reason |
| 5 | Hard Blockers | CAUTION | `guard-arm.sh`, `hooks.json`, `host-mode.sh` and the guard dir are protected by the armed test-integrity guard. Supervisor arms this session at INIT, so the edits work only because the owner's opt-out is in the launch environment. The worker inherits it. A worker that hits a deny records it in `outputs_gap`; it never works around the guard |

**Overall Verdict:** CAUTION

## Task
**Goal:** When `guard-arm.sh arm-from-payload` declines to arm for a role it should arm, it appends one `guard_arm_skipped` JSONL row (to the session log, else to `$GUARD_DIR/arm-skipped.jsonl`, else one stderr line). Supervisor's driver reads the marker plus those rows at hand-over, and the completion tail prints `test_guard: armed | unarmed (<reason>) | not_applicable` in the job's `## Outcome` block. Exit codes and `|| true` stay as they are.

**Problem Statement:**
The test-integrity guard's hook backstop (`PreToolUse[Agent|Task]` → `guard-arm.sh arm-from-payload`, carried with `|| true`) exits 0 without arming when `jq` is missing, the payload has no valid `session_id`, the guard dir is unresolvable, or the marker write fails. It records nothing anywhere.
Currently, `cmd_arm_from_payload` does a bare `exit 0` on every skip branch and `write_marker … || true`. A session can therefore run a Loomwright worker with the guard never armed, and no one can tell afterwards.
Success looks like this: every skipped arm for an armed role leaves one readable row, non-armed roles stay silent, and every Supervisor run's `## Outcome` states whether its own session was guarded.

## Acceptance Criteria

**Scope 3 — the trace (`loomwright/scripts/guard-arm.sh`)**
- [ ] AC1: Given a scratch project and `printf '{"tool_input":{"subagent_type":"loomwright:loomwright:worker"}}' | bash guard-arm.sh arm-from-payload`, when it runs, then it exits 0 and appends exactly ONE row `{"event":"guard_arm_skipped","reason":"no_session_id","subagent_type":"loomwright:loomwright:worker",…}` to `$GUARD_DIR/arm-skipped.jsonl`, and writes nothing under `.supervisor/logs/` (owner decision 3's added acceptance).
- [ ] AC2: Given an armed-role payload with a valid `session_id` and `jq` hidden from PATH, when `arm-from-payload` runs, then it exits 0 and appends one `reason: "jq_missing"` row, written with `printf` (no jq), to `.supervisor/logs/<session_id>.jsonl`. The jq-less path reads `tool_input.subagent_type` and `session_id` without jq (e.g. a `sed`/bash-regex extraction of the two string values), and still checks the role BEFORE any file I/O.
- [ ] AC3: Given an armed-role payload with a valid `session_id` and a guard dir that cannot be written (e.g. `.supervisor/guard` is a regular file, or the dir is `chmod 500`), when `arm-from-payload` runs, then it exits 0 and appends one `reason: "marker_write_failed"` row to the session log.
- [ ] AC4: Given host mode on with a gate dir that is still unresolvable AFTER `write_marker`'s creating form ran (`lw_gate_state_dir_existing` rc 1 — an unsafe or unwritable D1 root — or `lw_gate_state_dir` failing, so `write_marker` returns at its `guard dir unresolvable` line), when `arm-from-payload` runs for an armed role, then the reason is `no_guard_dir`. An empty `GUARD_DIR` at startup is NOT itself a skip: with rc 2 (no D1 root yet, `GUARD_CREATE=1`) `write_marker` creates the root and arms, and no row is written. The `no_guard_dir` decision is taken from `write_marker`'s outcome, never from a pre-check of `GUARD_DIR`. With a valid id the row goes to the session log, and only if that log's dir resolves (`lw_gate_state_dir_existing`, never creating). Otherwise ONE stderr line is printed and nothing is written outside a resolved dir.
- [ ] AC4b: Given host mode on, no D1 root yet (rc 2), a valid id and an armed role, when `arm-from-payload` runs, then the marker is created under the new gate dir, the script exits 0, and no `guard_arm_skipped` row is written anywhere (today's first-arm behaviour, pinned).
- [ ] AC5: Given a non-armed role (`general-purpose`, an un-namespaced `my-worker`), when `arm-from-payload` runs, then it exits 0, writes no row anywhere and creates no file (also with `jq` missing: the jq-less read decides "not an armed role" and exits silently).
- [ ] AC6: Given any skip, when the destination is chosen, then the session log `.supervisor/logs/<session_id>.jsonl` is used when the id is valid AND the log dir resolves the way `emit-agent-identity.sh` resolves it (main checkout = first `git worktree list` entry; host mode → `lw_gate_state_dir_existing`, which never creates a gate root). Otherwise the row goes to `$GUARD_DIR/arm-skipped.jsonl` (beside the markers, never under `logs/`; its `.jsonl` suffix never matches the markers' `*.json` glob, so `prune` and the guard never see it). If neither resolves, one stderr line and nothing written. Directory creation: outside host mode `trace_skip` may `mkdir -p` `$GUARD_DIR` exactly as `write_marker` would (AC1's bare scratch project ends with `.supervisor/guard/arm-skipped.jsonl`) and may create the session-log dir as `emit-agent-identity.sh` does; under host mode it never creates either.
- [ ] AC7: Given every skip path, then the script still always exits 0, `hooks.json`'s `arm-from-payload` and `disarm-session` leaves keep their `|| true` (`grep -c '|| true'` on them unchanged), and the two `guard-test-integrity.sh` leaves still carry none. A row's fields are `event`, `reason`, `subagent_type`, `session_id` and `cc_session_id` (both equal to the payload id when valid, else both omitted — the same pair `emit-agent-identity.sh` writes, so `build-floor.sh` classifies a session-log row as an event of its session instead of the `noid` bucket), `ts` (ISO-8601 UTC). String values are JSON-escaped on the printf path (backslash and double quote at minimum), so a hostile `subagent_type` cannot corrupt the JSONL line.

**Scope 4 — the surface (driver + completion tail)**
- [ ] AC8: Given a Supervisor run reaching `handover`, when the driver emits the `done` instruction, then it carries a `test_guard` field: `armed` when `$GUARD_DIR/<sid>.json` exists for this run's session id; else `unarmed (<reason>)`, where `<reason>` is the latest `guard_arm_skipped` row's `reason` for this session from the session log or `arm-skipped.jsonl` (rows matched by `session_id`), else the INIT arm's recorded failure — the worker ADDS `[ "$gc" -eq 0 ] || st_set guard_armed "$gd"` in `sn_init` step 7 (today `gd` reaches only `sn_op_decision INIT "$gd" …`, nothing is in the sidecar; persisting it only on failure keeps the 27 golden sidecars, whose INIT arm succeeds, byte-identical), and the reason is the text after `guard_armed: failed: ` (e.g. `unarmed (exit 1)` under `SUPERVISOR_NEXT_STEP_GUARD_CMD=false`) — else `marker_missing`; `not_applicable` when host mode is on and the gate dir is unresolvable (`lw_gate_state_dir_existing` rc 1 — an unsafe or unwritable per-user root): the test-integrity guard denies on that same dir, so armed/unarmed does not describe the session. (Every id that reaches `sn_handover` already passed the driver's `session_id_malformed` check, which is stricter than `valid_session_id`, so an invalid id is not a reachable condition and is not used.) A host-mode rc 2 (no root yet) reads as `unarmed (…)` by the normal rules. The read is a plain marker/JSONL read inside `supervisor-next-step.sh`. It is NOT a new `guard-arm.sh` subcommand (the Bash matcher denies those in an armed session), and it never blocks, parks or changes any other field.
- [ ] AC9: Given the completion tail step 2, when it writes the job `## Outcome` block (PASS / loop-skipped AND ESCALATED forms), then it includes `- **Test guard:** {test_guard from the handover instruction}`. `skills/supervisor-config/SKILL.md`'s promised `guard: unarmed` mark and `docs/supervisor-legacy-phases.md`'s copy point to this one line instead of restating it. No key is added to the `SUPERVISOR_RESULT` block (sidecar-check's closed key set).
- [ ] AC9b: Given a run with no handover instruction (`--legacy`, `--continue`, `--sdk-runner`, a run with no `job:` brief — the paths `commands/supervisor.md` §"Next-step driver" says the driver does not cover), when the completion tail writes `## Outcome`, then the line reads `- **Test guard:** unknown (no_driver_handover)`. The tail never computes the value itself; `docs/supervisor-legacy-phases.md` step 7's `guard: unarmed` text points to this rule. The Problem Statement's "every Supervisor run" means every run states a value, driver runs a real one.
- [ ] AC10: Given `docs/result-schemas/supervisor-result.md` §"supervisor next-step instruction", then the `done` (`step: "handover"`) entry lists `test_guard` with its three forms.

**Tests (Scope 5)**
- [ ] AC11: Given `bash loomwright/scripts/test-guard-test-integrity.sh`, then it has one case per skip reason (`no_session_id`, `jq_missing`, `marker_write_failed`, `no_guard_dir`), each asserting exit 0, exactly one `guard_arm_skipped` row with that reason in the expected destination, and none in the other. Plus: the AC4b host-mode first arm (no D1 root yet ⇒ marker created, no row; host-mode fixtures follow `test-host-mode.sh`'s precedent of a scratch `LOOMWRIGHT_HOST_STATE_DIR` / `TMPDIR` so no real per-user root is touched); a non-armed role ⇒ no row and no file; a hostile `subagent_type` containing `"` and `\` (with a `:worker` suffix) ⇒ the row still parses with `jq -e`. Fixtures run with `CLAUDE_PROJECT_DIR` in a `mktemp -d` scratch repo; nothing is written into the real `.supervisor/`.
- [ ] AC12: Given `bash loomwright/scripts/test-supervisor-next-step.sh`, then the handover instruction's `test_guard` is pinned for: `armed` (marker present); `unarmed (marker_write_failed)` (a skip row for THIS session id in the session log; a row for a different id is ignored); `unarmed (exit 1)` (no marker, no row, INIT run with `SUPERVISOR_NEXT_STEP_GUARD_CMD=false`); `unarmed (marker_missing)` (no marker, no row, INIT arm ok); `not_applicable` (host mode on with an unsafe gate root, set up the way `test-host-mode.sh` makes one).

**Docs + release (Scope 6)**
- [ ] AC13: Given the diff, then `guard-arm.sh`'s header documents the trace (reasons, destinations, the fail-safe limit "no resolvable dir ⇒ stderr only"); `docs/HOOKS.md`'s `PreToolUse (Agent|Task)` guard arm-backstop row and its host-mode classification row for `guard-arm.sh` mention the `guard_arm_skipped` row and `arm-skipped.jsonl`; `agents/supervisor.md` / `commands/supervisor.md` change only where they restate the completion-tail Outcome fields or the guard mark (pointer, not a copy); one `changelog.d/af39c-guard-arm-trace.md` fragment.
- [ ] AC14: Given the diff, then `bash scripts/check-doc-currency.sh`, `bash loomwright/scripts/test-citation-drift.sh`, `bash scripts/check-token-budget.sh` (budget raise in `prompt-token-budgets.json` + its `ARCHITECTURE_CONTRACTS.md` mirror row only if a measured surface exceeds its budget), the vendor-coupling ratchet (after `git add`) and `bash scripts/check-version-bump.sh` pass. Targeted tests only; full `ci-local` runs on GitHub CI (owner rule 2026-10-12).

**Running-system evidence (requirement Validation 2)**
- [ ] AC15: Given the opted-out session, then the installed-copy behaviour is shown for the three fixture payloads (jq hidden; no `session_id`; unwritable guard dir) with each exit code and the row it wrote, plus one real completion tail's `test_guard:` line. Recorded in committed `docs/evidence/af39c-guard-arm-trace.md` (repo-root `docs/evidence/` is the convention). The PR body links to it and does not carry the evidence itself. The worker runs the fixtures against the branch's `guard-arm.sh` in a scratch project. The installed-copy run and the completion-tail line are appended by the Supervisor main thread before the PR is opened (the main thread may need the cache refreshed; if the installed copy is the old version, say so plainly rather than claim it).

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

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| trace | `loomwright/scripts/guard-arm.sh` (279 — the existing home of the arm-from-payload skip branches; the row writer is a small helper inside it, since only this script writes the row) | — | HIGH |
| trace tests | `loomwright/scripts/test-guard-test-integrity.sh` (1217 — at/over the module-layout threshold, see Module layout) | — | HIGH |
| reader | `loomwright/scripts/supervisor-next-step.sh` (1308 — `sn_handover` gains `test_guard`; the reader is one function next to it) | — | HIGH |
| reader tests | `loomwright/scripts/test-supervisor-next-step.sh` (1149) | — | HIGH |
| golden fixtures | `loomwright/scripts/fixtures/supervisor-golden/<handover cases>/expected.out` and their `expected/session-logs/*.supervisor-next-step.json` where the pending text carries the handover (regenerated, not hand-edited — see Touched-file invariants) | — | MEDIUM (exact case set found by grep) |
| prose sync | `loomwright/skills/self-heal-advisory/completion-tail.md` (517), `loomwright/skills/supervisor-config/SKILL.md` (92), `loomwright/docs/supervisor-legacy-phases.md` (371), `loomwright/agents/supervisor.md` (651), `loomwright/commands/supervisor.md` (235), `loomwright/docs/HOOKS.md` (127), `loomwright/docs/result-schemas/supervisor-result.md` | — | HIGH (agents/commands: MEDIUM — touched only if they restate the Outcome fields) |
| budgets | `loomwright/docs/prompt-token-budgets.json`, `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (1051 — one mirror row in §"Prompt Token Budgets", extending an existing table; only if a measured surface exceeds its budget — `self-heal-advisory` has ~3.4k headroom, `supervisor` agent ~2k, command ~1k) | — | MEDIUM |
| evidence + release | — | `docs/evidence/af39c-guard-arm-trace.md`, `changelog.d/af39c-guard-arm-trace.md` | HIGH |

**Module layout:** `test-guard-test-integrity.sh` (1217) and `supervisor-next-step.sh` (1308) and its test (1149) are past the threshold. Appending is the right home: the new cases extend the existing `arm-from-payload` block in the guard test (the fixtures and `ARM`/`ARM_D` helpers live there), and the reader belongs beside `sn_handover`, which it feeds. A new file would duplicate the scratch-repo and sidecar helpers. No extract row: no helper here is copied by 2+ siblings. `docs/result-schemas/supervisor-result.md` was added to the requirement's Touches because AC10 requires it (the instruction's authority).

**Total estimated files:** ~4–8 regenerated golden fixtures + 13 modify (4 conditional: `agents/supervisor.md`, `commands/supervisor.md`, `prompt-token-budgets.json`, `ARCHITECTURE_CONTRACTS.md`) + 2 create

## Touched-file invariants

> Grounded at base `304adac5dd0970a5c718a1ccba459b4f0f47fed5`. The worker re-checks these before hand-back.

- **`loomwright/scripts/guard-arm.sh`** — keep: `set -u` only (no `set -e`); `cmd_arm_from_payload` checks `subagent_type` BEFORE any file I/O (header: `any file I/O (this leaf forks on every single Task/Agent spawn in`). keep: the armed-role match `*:worker|*:execute-manager|*:supervisor-runner|*:review-pr-runner)` with the namespace colon required. keep: `valid_session_id` (`*/*) return 1`) and use it for the session-log filename too. keep: the presence gate — `lw_gate_state_dir_existing, which never creates: a non-Loomwright`; only `write_marker` may create the D1 root (`if [ "$GUARD_CREATE" = 1 ] && _gd="$(lw_gate_state_dir "$GUARD_PROJ")"; then` — this rc-2 creating path must keep arming, AC4b), so the trace must never create a gate root or a `.supervisor/` that does not already exist under host mode. keep: `cmd_arm` behaviour and exit codes (`exit 3` on no id) and `cmd_disarm_session` unchanged. keep: `prune` globs `"$GUARD_DIR"/*.json` — the new file must not match it. name: the row writer is one helper `trace_skip <reason> <subagent_type> <sid>` called at each skip site as `trace_skip no_session_id …`, `trace_skip jq_missing …`, `trace_skip marker_write_failed …`, `trace_skip no_guard_dir …` (the Pin mutations below name these call sites). mirror: `emit-agent-identity.sh`'s log resolution (`git worktree list --porcelain … sed -n '1s/^worktree //p'`, `LOG_DIR="$SUP_DIR/logs"`, the session-id charset guard `*[!A-Za-z0-9_-]*`). pinned by: `test-guard-test-integrity.sh` "arm-from-payload arms on namespaced :worker subagent_type" and mutation (h) (`drop the namespace-colon requirement`).
- **`loomwright/scripts/test-guard-test-integrity.sh`** — reuse: the `ok()` / `no()` counters, `ARM="$SCRIPT_DIR/guard-arm.sh"`, and the scratch pattern `ARM_D="$(mktemp -d)"` with `CLAUDE_PROJECT_DIR="$ARM_D" bash "$ARM" arm-from-payload <<<"$(jq -n …)"`; new cases go beside the existing `arm-from-payload arms on namespaced :worker subagent_type` block. keep: the mutation section (`# (h) drop the namespace-colon requirement from arm-from-payload`) passing. For `jq_missing`, hide jq with a PATH of symlinked tools minus jq (never by editing the real PATH dirs). Every new scratch dir is a `git init` repo so the main-checkout log resolution has a toplevel.
- **`loomwright/scripts/test-supervisor-next-step.sh`** — reuse: the hermetic per-case checkout (`cw="$(mktemp -d "$WORK/case.XXXXXX")"`), the env reset line `unset LOOMWRIGHT_GH_BIN SUPERVISOR_NEXT_STEP_FROM SUPERVISOR_NEXT_STEP_GUARD_CMD LOOMWRIGHT_HOST_MODE CLAUDE_PROJECT_DIR`, the stub `export SUPERVISOR_NEXT_STEP_GUARD_CMD="$CASE_BIN/rec guard"` and the per-case env file (`'SUPERVISOR_NEXT_STEP_GUARD_CMD=false' > "$CASE_DIR/b6.env"`). Because the stub never writes a marker, the default handover reads `unarmed (marker_missing)`; the `armed` case writes the marker file itself. keep: the existing `guard_armed: failed: exit 1` assertion.
- **`loomwright/scripts/fixtures/supervisor-golden/`** (27 cases; Leg G "GOLDEN PARITY" in `test-supervisor-next-step.sh` compares each case's `.supervisor/` tree and instruction stream byte for byte with `expected/` and `expected.out`) — the handover cases that reach `step: "handover"` (e.g. `validation-3-drive`, `finalize-pr-base-verified`, `finalize-pr-base-mismatch`, `finalize-pr-base-gh-retry`; the worker greps `expected.out` for `"handover"` to get the exact set) gain `test_guard` in `expected.out` and in any sidecar `pending_text`. Regenerate ONLY those with `SN_CASES=<case> SN_WRITE_EXPECTED=1 bash loomwright/scripts/test-supervisor-next-step.sh`, then review the fixture diff: the only change allowed is the added `test_guard` field (no `guard_armed` key appears, since the golden INIT arms succeed). Any other fixture change is a bug in the reader, not a fixture to regenerate.
- **`loomwright/hooks/hooks.json`** — NOT modified. The `arm-from-payload || true` and `disarm-session || true` command strings and the two `guard-test-integrity.sh` leaves without `|| true` stay byte-identical (AC7).
- **`loomwright/scripts/guard-test-integrity.sh`** — NOT modified (non-goal). Its `is_protected_basename` last arm `guard-test-integrity.sh|guard-arm.sh|hooks.json|host-mode.sh)` stays. Its Bash matcher denies a `guard-arm.sh` subcommand other than `arm`, which is why the reader is in the driver.
- **`loomwright/scripts/supervisor-next-step.sh`** — keep: step 7 `ge="$(bash "$HERE/guard-arm.sh" arm supervisor </dev/null 2>&1 >/dev/null)"` and the `SUPERVISOR_NEXT_STEP_GUARD_CMD` test override; the `guard_armed: ok|failed` decision. add: `[ "$gc" -eq 0 ] || st_set guard_armed "$gd"` right after the `gd=` line (AC8's INIT-failure fallback; today nothing about the arm reaches the sidecar). name: the reader is one function `sn_test_guard` called from `sn_handover` (the Pin mutations below name it). keep: the `sn_handover` field set (`next`, `pr_url`, `base_verify`, `base_mismatch_detected`, `children_check`, `preflight_sync`, optional `preflight_warning` / `escalation`, `message`) — `test_guard` is ADDED. The guard dir resolution must match `guard-arm.sh`'s (`CLAUDE_PROJECT_DIR` or the driver's `ROOT`; host mode via `host-mode.sh`'s `lw_gate_state_dir_existing`, never creating). pinned by: `test-supervisor-next-step.sh` `decision: \"guard_armed: failed: exit 1\"` and the handover assertions.
- **`loomwright/skills/self-heal-advisory/completion-tail.md`** — keep: step 2's Outcome block shape and the ESCALATED form's "plus" list; add one line in each, no step renumbering (step numbers are cited elsewhere).
- **`loomwright/docs/HOOKS.md`** — keep: the deny-wording rule ("Neither variant EVER names the opt-out env var"). The opt-out-name grep pinned in `docs/HOOKS.md` §"Guard contract" ("Opt-out — process env only") must stay empty — no agent/skill/command file may gain the variable's name.

## Closed enumerations touched

> Sibling grep at base `304adac`: `grep -rlF 'agent_identity' loomwright/scripts | grep -v '/test-' | grep -v fixtures` → 6 files.

- **new event `guard_arm_skipped`** (sibling: `agent_identity`, the other per-session row written from a hook):
  - `loomwright/scripts/emit-agent-identity.sh` — the producer of the sibling; no change (it is the resolution precedent, not a list).
  - `loomwright/scripts/build-floor.sh` — classifies every log line by `cc_session_id` (`else "noid" end`, counted into `sess_noid`) and excludes only `agent_identity` from event counts (`map(select((.event // "") != "agent_identity"))`). no change: the row carries `cc_session_id` (AC7), so it is classified under its session and counted as one event of it, which is true — it is something that happened in that session. Rows in `arm-skipped.jsonl` are outside `logs/*.jsonl` and never read.
  - `loomwright/scripts/check-children-settled.sh` — joins `agent_identity` rows to terminal lifecycle rows by `agent_id`. no change: the new row has no `agent_id`, so it is neither an identity nor a terminal row.
  - `loomwright/scripts/guard-finalize-publish.sh` — reads the session log for the children check and liveness. no change: same reason (no `agent_id`, no lifecycle `state`).
  - `loomwright/scripts/phase-timing.sh` — reads `agent_identity` for agent types and events by `ts`. no change: an extra event with a `ts` inside the run's own span cannot move its first/last bounds outside the run; the worker confirms in its hand-back that phase boundaries key on named events only.
  - `loomwright/scripts/emit-lifecycle.sh` — writes `agent_lifecycle` rows and reads `agent_identity` for the type. no change: it never reads other event names.
- **new `reason` values `jq_missing`, `no_session_id`, `marker_write_failed`, `no_guard_dir`** — a new closed set owned by the `guard-arm.sh` header (AC13). Restated, as a pointer only, in `docs/HOOKS.md`'s arm-backstop row; no other surface lists them.
- **new handover field `test_guard`** (sibling: `children_check`; `grep -n 'children_check' loomwright/docs/result-schemas/supervisor-result.md loomwright/skills/self-heal-advisory/completion-tail.md`) — extend `docs/result-schemas/supervisor-result.md`'s `done` entry (AC10) and completion-tail step 2 (AC9). `test_guard` is not a `SUPERVISOR_RESULT` key, so `RESULT_SCHEMAS.md` and sidecar-check are unchanged.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-guard-test-integrity.sh` — no_session_id ⇒ one row in `arm-skipped.jsonl` | delete `trace_skip no_session_id` in `loomwright/scripts/guard-arm.sh` |
| `loomwright/scripts/test-guard-test-integrity.sh` — no_session_id ⇒ nothing under `logs/` | in `loomwright/scripts/guard-arm.sh`, make `trace_skip` write to the session-log path even when the id is invalid |
| `loomwright/scripts/test-guard-test-integrity.sh` — jq_missing ⇒ printf row | delete `trace_skip jq_missing` in `loomwright/scripts/guard-arm.sh` |
| `loomwright/scripts/test-guard-test-integrity.sh` — marker_write_failed ⇒ row | delete `trace_skip marker_write_failed` in `loomwright/scripts/guard-arm.sh` |
| `loomwright/scripts/test-guard-test-integrity.sh` — no_guard_dir ⇒ row / stderr line | delete `trace_skip no_guard_dir` in `loomwright/scripts/guard-arm.sh` |
| `loomwright/scripts/test-guard-test-integrity.sh` — host-mode first arm (rc 2) ⇒ marker, no row | in `loomwright/scripts/guard-arm.sh`, add a `[ -n "$GUARD_DIR" ] \|\| { trace_skip no_guard_dir …; exit 0; }` pre-check before `write_marker` |
| `loomwright/scripts/test-guard-test-integrity.sh` — non-armed role ⇒ no row | in `loomwright/scripts/guard-arm.sh`, move the first `trace_skip` call above the armed-role `case` |
| `loomwright/scripts/test-guard-test-integrity.sh` — hostile subagent_type ⇒ row parses | in `loomwright/scripts/guard-arm.sh`, drop the JSON escaping of `subagent_type` inside `trace_skip` |
| `loomwright/scripts/test-guard-test-integrity.sh` — `\|\| true` count on the guard-arm leaves unchanged, none on the two guard-test-integrity leaves | flip `guard-arm.sh\" arm-from-payload \|\| true` → `guard-arm.sh\" arm-from-payload` in `loomwright/hooks/hooks.json` |
| `loomwright/scripts/test-supervisor-next-step.sh` — handover `test_guard: armed` | in `loomwright/scripts/supervisor-next-step.sh`, make `sn_test_guard` skip the marker-file test |
| `loomwright/scripts/test-supervisor-next-step.sh` — `unarmed (marker_write_failed)` only for this session's row | in `loomwright/scripts/supervisor-next-step.sh`, drop the `session_id` match on skip rows inside `sn_test_guard` |
| `loomwright/scripts/test-supervisor-next-step.sh` — `unarmed (exit 1)` from the INIT failure | delete `\|\| st_set guard_armed "$gd"` in `loomwright/scripts/supervisor-next-step.sh` |
| `loomwright/scripts/test-supervisor-next-step.sh` — `unarmed (marker_missing)` | in `loomwright/scripts/supervisor-next-step.sh`, make `sn_test_guard` return `armed` when no row and no marker |
| `loomwright/scripts/test-supervisor-next-step.sh` — `not_applicable` | in `loomwright/scripts/supervisor-next-step.sh`, drop the host-mode unresolvable-gate-dir branch in `sn_test_guard` |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Guard arm trace in `guard-arm.sh` + `test_guard` reader in the driver + Outcome line + tests + docs + evidence + changelog fragment | all (AC15: the worker runs the scratch-project fixtures; the main thread adds the installed-copy run and the completion-tail line) | 13 modify, 2 create | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/scripts/guard-arm.sh", name: "guard_arm_skipped"}
  - {kind: "symbol", path: "loomwright/scripts/guard-arm.sh", name: "arm-skipped.jsonl"}
  - {kind: "symbol", path: "loomwright/scripts/guard-arm.sh", name: "marker_write_failed"}
  - {kind: "symbol", path: "loomwright/scripts/guard-arm.sh", name: "no_guard_dir"}
  - {kind: "symbol", path: "loomwright/scripts/supervisor-next-step.sh", name: "test_guard"}
  - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/completion-tail.md", name: "**Test guard:**"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/supervisor-result.md", name: "test_guard"}
  - {kind: "symbol", path: "loomwright/docs/HOOKS.md", name: "guard_arm_skipped"}
  - {kind: "file", path: "docs/evidence/af39c-guard-arm-trace.md"}
  - {kind: "file", path: "changelog.d/af39c-guard-arm-trace.md"}
requires: []
lanes:
  - "loomwright/scripts/guard-arm.sh"
  - "loomwright/scripts/test-guard-test-integrity.sh"
  - "loomwright/scripts/supervisor-next-step.sh"
  - "loomwright/scripts/test-supervisor-next-step.sh"
  - "loomwright/scripts/fixtures/supervisor-golden/**"
  - "loomwright/skills/self-heal-advisory/completion-tail.md"
  - "loomwright/skills/supervisor-config/SKILL.md"
  - "loomwright/docs/supervisor-legacy-phases.md"
  - "loomwright/agents/supervisor.md"
  - "loomwright/commands/supervisor.md"
  - "loomwright/docs/HOOKS.md"
  - "loomwright/docs/result-schemas/supervisor-result.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "docs/evidence/af39c-guard-arm-trace.md"
  - "changelog.d/af39c-guard-arm-trace.md"
external_requires:
  - "The owner's gate-edit opt-out in the session's launch environment (present, verified at INIT)"
  - "jq on PATH for the jq-present paths and the tests' row parsing"
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| The edits target guard-protected files; without the opt-out the worker's Write/Edit is denied — Feasibility (Phase 2.5) | HIGH | Verified present at INIT; the worker inherits the session env. A deny ⇒ `outputs_gap`, never a workaround (no heredoc-to-unprotected-name tricks for the guard's own files) |
| The trace writes a new file into the guard dir, which the guard's own Bash matcher treats as protected (`.supervisor/guard` path) | MEDIUM | Only the hook process writes it, never a Bash tool call. The reader in the driver only reads (reads are never denied). Tests write it via `CLAUDE_PROJECT_DIR` in a scratch dir |
| Writing a row could create gate state under host mode, breaking the presence gate | MEDIUM | Destinations resolve via `lw_gate_state_dir_existing` only; an absent root ⇒ stderr line. Pinned by the `no_guard_dir` test |
| A new event in the session log trips a reader with a closed event list | LOW | The row carries `session_id` + `cc_session_id` (AC7) and no `agent_id` or lifecycle `state`; the per-reader list under Closed enumerations shows no reader breaks |
| The jq-less payload read mis-parses a payload (escaped quotes, field order) | LOW | It only decides armed-role membership and extracts an id that `valid_session_id` + the `[A-Za-z0-9_-]` charset then gate; a mis-parse yields a row with reason `jq_missing` or no row — never an arm and never a non-zero exit |
| The installed plugin copy is older than the branch, so "installed `guard-arm.sh`" evidence shows the old behaviour | LOW | AC15: run against the branch copy in a scratch project; state plainly if the installed copy is not yet updated |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-28-af39c-guard-arm-trace.md
```

## Plan Review
- **Status:** PASS (attempt 3 of 3, 2026-10-28)
- **Deferred (below the MEDIUM fix floor):** LOW — an id the driver accepts but the session-log charset guard rejects (contains `.` or `:`) sends its skip row to `arm-skipped.jsonl`, not the session log; `sn_test_guard` reads both files by `session_id`, so the reported value is unchanged. Optional: one AC12 case for it.

## Outcome
- **Status:** completed
- **Completed:** 2026-10-28T08:50:30Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/741
- **Branch:** feature/af39c-guard-arm-trace
- **Files changed:** 22
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Test guard:** armed (read by hand from this session's marker `.supervisor/guard/<session_id>.json` — this run's installed v17.21.1 driver predates the `test_guard` handover field)
- **Until-mergeable dispatched:** true
- **Until-mergeable log:** .supervisor/logs/review-pr-dispatch-20261028T082040Z-3549507983b388c4f845946bd5ea1641411a21da.log
- **Summary:** guard-arm.sh arm-from-payload now writes one guard_arm_skipped row per skipped arm of an armed role (session log → arm-skipped.jsonl → stderr; exit 0 and `|| true` kept); the driver's handover carries test_guard and the completion tail prints it. Iteration 1: reviewer PASS, required CI `ci` red on check-locale-prefix (`LC_ALL=C tr` → `env LC_ALL=C tr`), fixed in 9631303; iteration 2 PASS, CI pending at hand-off (the drain reads it).

## Not verified
- **installed-plugin guard-arm.sh and a real completion tail's Test guard line** — the installed copy (v17.21.1) predates this change; evidence records its old behaviour as the baseline (subtask 1)
- **full scripts/ci-local.sh** — owner rule: targeted tests only; GitHub CI runs the suite (subtask 1)
