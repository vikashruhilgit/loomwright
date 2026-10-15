# Loop inventory — supervisor

This file lists every branch and rule the Supervisor loop states in prose — the `/supervisor` command, the `supervisor-runner` agent prompt, the Phase 4.5 self-heal advisory skill and the async-orchestration skill (worker spawn, poll and FINALIZE protocol) — one row per `###`/`####` heading outside fenced and split-index blocks, and one row per list item (or load-bearing bold paragraph) that states a condition→action branch or a rule. Pure enumerations (flag lists, file lists, illustrative examples) are covered by their section's heading row. It restates prose on purpose so a later move of a branch into a script, or of a story out of the prose, cannot silently drop an edge case. `loomwright/scripts/test-loop-inventory.sh` keeps it in sync with the sources (heading coverage, live anchors, real script subcommands, unique ids, the gap list and the counts below); the counts and the gap list are computed from the table, never hand-maintained.

## Sources
- `agents/supervisor.md`
- `commands/supervisor.md`
- `skills/self-heal-advisory/SKILL.md`
- `skills/async-orchestration/SKILL.md`

## Inventory

| id | file | anchor | condition | action | kind | home | implemented by | test |
|----|------|--------|-----------|--------|------|------|----------------|------|
| SV-001 | agents/supervisor.md | q: **Mission:** deliver the smallest correct thing that advances the | any change | deliver the smallest correct change; existing patterns; no scope creep | rule | prose | - | GAP |
| SV-002 | agents/supervisor.md | q: **Safety:** no destructive actions without explicit approval; never | destructive action or unverified path/API | require explicit approval; verify or ask; no secrets/PII in output | rule | prose | - | GAP |
| SV-003 | agents/supervisor.md | q: **Escalation:** merge conflicts always escalate — never force-resolve. | merge conflict | always escalate, never force-resolve | rule | prose | - | GAP |
| SV-004 | agents/supervisor.md | q: **Output:** default result structure is Context Read → Plan → Work | agent output | Context Read → Plan → Work → Results → Risks unless the role defines its own result contract | rule | prose | - | GAP |
| SV-005 | agents/supervisor.md | h: ### Core Principles | section | core principles of the orchestrator | rule | prose | - | GAP |
| SV-006 | agents/supervisor.md | q: **Pure orchestrator:** Hold only phase, task_id, branch, worker_ids | Supervisor context | hold only phase, task_id, branch, worker_ids | rule | prose | - | GAP |
| SV-007 | agents/supervisor.md | q: **Delegate EXECUTE:** Phase 3 delegated to Execute Manager for | multi-subtask workflow | delegate Phase 3 to Execute Manager | rule | prose | - | GAP |
| SV-008 | agents/supervisor.md | q: **Parallel execution:** Independent subtasks run concurrently in git | independent subtasks | run concurrently in git worktrees | rule | prose | - | GAP |
| SV-009 | agents/supervisor.md | q: **Externalized state:** Context-Keeper manages `## Decisions Log` / `## | state sections | Context-Keeper writes Decisions/Worker Results/Error Log/Phase Flags; `## Session` is derived | rule | prose | script:build-state.sh | test-progress-state.sh |
| SV-010 | agents/supervisor.md | q: **Mandatory branching:** Feature branch created BEFORE any code work | before any code work | create feature branch; idempotent against a crashed same-named branch | rule | prose | - | GAP |
| SV-011 | agents/supervisor.md | q: **Quality gates:** Pause on NEEDS_HUMAN, retry on FAIL (max 3x), | gate verdict NEEDS_HUMAN / FAIL / PASS | pause / retry max 3x / continue | deterministic | prose | - | GAP |
| SV-012 | agents/supervisor.md | q: **Self-healing:** Post-merge holistic review + bounded fix loop (Phase | after merge | run holistic review + bounded fix loop (Phase 4.5) before handoff | rule | prose | - | GAP |
| SV-013 | agents/supervisor.md | q: **Error recovery:** progress state re-derives automatically at each | resume | progress state re-derives at worker completion/session end; validate against git first | rule | prose | script:reconcile-resume-state.sh | test-reconcile-resume-state.sh |
| SV-014 | agents/supervisor.md | q: **Tool call budget:** 50 calls maximum for Supervisor (including Phase | tool-call count | Supervisor max 50 calls incl. Phase 4.5; Execute Manager 60 | rule | prose | - | GAP |
| SV-015 | agents/supervisor.md | h: ### Inputs | section | enumeration of Supervisor inputs (task source, job file, flags) | story | prose | - | GAP |
| SV-016 | agents/supervisor.md | h: ### Outputs | section | enumeration of Supervisor outputs | story | prose | - | GAP |
| SV-017 | agents/supervisor.md | q: **Escalation requests:** When NEEDS_HUMAN or max retries reached | NEEDS_HUMAN or max retries reached | emit an escalation request | deterministic | prose | - | GAP |
| SV-018 | agents/supervisor.md | h: ### Critical Rules | section | critical rules of the Supervisor | rule | prose | - | GAP |
| SV-019 | agents/supervisor.md | q: **Always branch first:** NEVER proceed to PLAN phase without a confirmed | no confirmed feature branch | NEVER proceed to PLAN | deterministic | prose | - | GAP |
| SV-020 | agents/supervisor.md | q: **Context budget:** Supervisor holds < 400 tokens; everything else in | Supervisor context | hold < 400 tokens; everything else in state file | rule | prose | - | GAP |
| SV-021 | agents/supervisor.md | q: **Progress state is derived, not written:** the canonical lowercase `## | `## Session` block in state.md | never agent-written; derived by emit-progress-event.sh, projected by build-state.sh | rule | prose | script:emit-progress-event.sh | test-progress-state.sh |
| SV-022 | agents/supervisor.md | q: **Clean worktrees:** All worktrees removed in FINALIZE (no orphans) | FINALIZE | remove all worktrees (no orphans) | rule | prose | - | GAP |
| SV-023 | agents/supervisor.md | q: **Sequential merge:** Worktree branches merge one at a time into feature | worktree branches | merge one at a time into the feature branch | rule | prose | - | GAP |
| SV-024 | agents/supervisor.md | q: **Exit gracefully:** At tool call budget limit, checkpoint and exit with | tool-call budget limit reached | checkpoint and exit with resume command | deterministic | prose | - | GAP |
| SV-025 | agents/supervisor.md | q: **Inline execution does not waive child-agent spawning:** Running | running inline on the main thread | still spawn execute-manager/worker (Phase 3) and code-reviewer (Phase 4.5) via Task; never hand-implement | rule | prose | - | GAP |
| SV-026 | agents/supervisor.md | q: **Can't-ask rule:** this run cannot ask when `--non-interactive` is set | `--non-interactive` set OR running as a subagent | each question gate fails closed with its named status (init_input_missing_non_interactive, preflight_overlap_detected, adjudication_required_non_interactive, gh_unavailable_non_interactive, children_unsettled) | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| SV-027 | agents/supervisor.md | q: **`async-orchestration` (~9,889 proxy tokens) — ROUTED, replacement | async-orchestration preload audit | routed: Read at Phase 2 entry (first load) and Phase 4 entry (compaction refresh) | story | prose | - | GAP |
| SV-028 | agents/supervisor.md | q: **`commit` (~1,134 proxy tokens) — ROUTED, replacement Read added.** | commit skill preload audit | routed: bundled into the Phase 4 entry Read | story | prose | - | GAP |
| SV-029 | agents/supervisor.md | q: **`state-management` (~6,885 proxy tokens) — ROUTED, replacement Read | state-management preload audit | routed: Read at Phase 4.5 entry | story | prose | - | GAP |
| SV-030 | agents/supervisor.md | q: **Phase 0 resume validation gate — NO replacement Read needed here.** | Phase 0 resume gate | no extra Read; supervisor-config embeds the gate steps | story | prose | - | GAP |
| SV-031 | agents/supervisor.md | q: **Phase 4.5 completion-tail `session_end` JSONL emission — genuine | Phase 4.5 session_end emission | needs state-management Read for the base session_end shape | story | prose | - | GAP |
| SV-032 | agents/supervisor.md | q: **`workflow-management` (~4,267 proxy tokens) — REMOVED, no | workflow-management preload audit | removed; Permission Batching content dropped deliberately | story | prose | - | GAP |
| SV-033 | agents/supervisor.md | q: **`context-summarization` (~1,792 proxy tokens) — REMOVED, no | context-summarization preload audit | removed, no replacement Read | story | prose | - | GAP |
| SV-034 | agents/supervisor.md | q: **`supervisor-readiness` (~6,926 proxy tokens) — REMOVED, no | supervisor-readiness preload audit | removed; Orchestrator applies the decomposition threshold | story | prose | - | GAP |
| SV-035 | agents/supervisor.md | q: **`quality-checklist` (~3,209 proxy tokens) — REMOVED, no replacement | quality-checklist preload audit | removed; Code Reviewer preloads it | story | prose | - | GAP |
| SV-036 | agents/supervisor.md | q: What the budget number does and does NOT claim | quoting the token-budget saving | it is spawn-time weight, not a session total; routed skills redistribute cost | story | prose | - | GAP |
| SV-037 | agents/supervisor.md | q: Phase-numbering convention | phase numbering | 1.5 and 4.5 are sub-phase gates; the "7-Phase" name is unchanged | rule | prose | - | GAP |
| SV-038 | agents/supervisor.md | h: ### Phase 0: INIT (Interactive Configuration) | session start (fresh or --continue) | run Phase 0 INIT via supervisor-config skill Read | deterministic | prose | - | GAP |
| SV-039 | agents/supervisor.md | q: When a `job:` brief is supplied, the planning questions are pre-answered | `job:` brief supplied | skip env validation; move brief pending/ → in-progress/ (skip if not under pending/); jump to Phase 1 | deterministic | prose | - | GAP |
| SV-040 | agents/supervisor.md | q: and execute that protocol: environment auto-detection, resume-state | Phase 0 entry | Read supervisor-config SKILL.md on demand (not preloaded) | rule | prose | - | GAP |
| SV-041 | agents/supervisor.md | q: **Run-lock acquired (red-team-hardening/06 — FIRST action of Phase 0, | Phase 0 first action | `run-lock.sh acquire --owner supervisor:<sid> --session-id <sid>`; held ⇒ status failed, error run_lock_held; reentrant/degraded ⇒ proceed | deterministic | prose | script:run-lock.sh acquire | test-run-lock.sh |
| SV-042 | agents/supervisor.md | q: Resolved config recorded in session memory and echoed for cross-phase | config resolved | echo BASE_BRANCH, NON_INTERACTIVE, RED_TEAM_ENABLED, MAX_TOKENS in Session Configuration | rule | prose | - | GAP |
| SV-043 | agents/supervisor.md | q: `--non-interactive` recorded as a Phase Flag (`set_flag | `--non-interactive` / `--max-tokens N` present | record as Phase Flag; clear stale crash-recovery flags on entry | deterministic | prose | - | GAP |
| SV-044 | agents/supervisor.md | q: `cost_profile` resolved: `--cheap` → `cheap`, else `default` (resume | `--cheap` present | cost_profile = cheap, else default; consumed at every spawn | deterministic | prose | - | GAP |
| SV-045 | agents/supervisor.md | q: Resume path (`--continue`): loaded state MUST pass the fail-closed | `--continue` with state failing the resume gate | status failed, error resume_state_invalid; under-reporting state ⇒ resume_state_stale; never fall back to fresh | deterministic | prose | script:reconcile-resume-state.sh | test-reconcile-resume-state.sh |
| SV-046 | agents/supervisor.md | h: ### Phase 1: ACQUIRE (Task Selection + Branch) | Phase 1 entry | select task and create branch (non-negotiable) | deterministic | prose | - | GAP |
| SV-047 | agents/supervisor.md | q: **Consult project memory (advisory — read-only):** run `bash | Phase 1 action 0 | read project memory; advisory, subordinate to CLAUDE.md; empty ⇒ proceed | rule | prose | script:read-project-memory.sh | test-project-memory.sh |
| SV-048 | agents/supervisor.md | q: **Consult verified lessons (advisory — read-only):** also run `bash | Phase 1 action 0 | read verified lessons; advisory; must never block the run or change a verdict | rule | prose | script:read-lessons.sh | test-read-lessons.sh |
| SV-049 | agents/supervisor.md | q: User describes task via `task:` parameter | `task:` parameter given | use it as the task source | deterministic | prose | - | GAP |
| SV-050 | agents/supervisor.md | q: Or read from `.supervisor/state.md` (resume) — **gated:** the loaded | task from resumed state.md | consume only if it passed the Phase 0 resume gate; else run already refused | deterministic | prose | - | GAP |
| SV-051 | agents/supervisor.md | q: Or user provides description interactively | no task: and no resumable state | take the description interactively | judgment | prose | - | GAP |
| SV-052 | agents/supervisor.md | q: Or load from job file (if `job:` parameter used) | `job:` parameter used | load title and criteria from the job file | deterministic | prose | - | GAP |
| SV-053 | agents/supervisor.md | q: If requirements are vague (no acceptance criteria): spawn Product Owner | requirements vague (no acceptance criteria) | spawn Product Owner (blocking) | judgment | prose | - | GAP |
| SV-054 | agents/supervisor.md | q: If clear criteria exist: proceed | clear criteria exist | proceed | judgment | prose | - | GAP |
| SV-055 | agents/supervisor.md | q: **MANDATORY: Create feature branch** (before ANY code work) — | feature branch already exists | tip == base tip ⇒ reuse; else exit 1 (never delete); absent ⇒ checkout -b | deterministic | prose | - | GAP |
| SV-056 | agents/supervisor.md | q: On `exit 1` above: MUST NOT proceed to Phase 1.5/2 | branch guard exit 1 | do not proceed; status failed, error acquire_branch_collision; leave job file untouched | deterministic | prose | - | GAP |
| SV-057 | agents/supervisor.md | q: HARD RULE (unchanged): | feature branch parent | must be the tip of $BASE_BRANCH; Phase 4 self-verify checks baseRefName | rule | prose | - | GAP |
| SV-058 | agents/supervisor.md | q: Progress state (the canonical lowercase `## Session` block — | progress state at ACQUIRE | not written; derived by hook at worker SubagentStop | rule | prose | script:emit-progress-event.sh | test-progress-state.sh |
| SV-059 | agents/supervisor.md | q: Checkpoint:** none — no progress-state file | after branch creation | no checkpoint file; branch + derived state.md are the only evidence | rule | prose | - | GAP |
| SV-060 | agents/supervisor.md | h: ### Phase 1.5: PRE-FLIGHT SYNC (Remote-State Reconciliation) | after ACQUIRE, before PLAN | run PRE-FLIGHT SYNC via preflight-sync skill Read; classify CLEAR/OVERLAP/SUPERSEDED | deterministic | prose | - | GAP |
| SV-061 | agents/supervisor.md | q: **CLEAR** → proceed to Phase 2 silently (`preflight_sync = clear`). | pre-flight classification CLEAR | proceed to Phase 2 silently; preflight_sync = clear | deterministic | prose | - | GAP |
| SV-062 | agents/supervisor.md | q: **OVERLAP / SUPERSEDED (interactive)** → soft-gate `AskUserQuestion` | OVERLAP / SUPERSEDED, interactive | AskUserQuestion: proceed / revise-scope (checkpoint) / abort with preflight_overlap_detected | judgment | prose | - | GAP |
| SV-063 | agents/supervisor.md | q: **OVERLAP / SUPERSEDED under `--non-interactive` / CI / | OVERLAP / SUPERSEDED under --non-interactive / CI / no TTY | fail closed: status failed, error preflight_overlap_detected | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| SV-064 | agents/supervisor.md | q: **Tooling failure (`gh` / `git fetch` / timeout)** → graceful | gh / git fetch / timeout failure in pre-flight | one warning, preflight_sync unverified, continue — never hard-block | deterministic | prose | - | GAP |
| SV-065 | agents/supervisor.md | q: **`--skip-preflight-sync`** → short-circuit straight to Phase 2 as a | `--skip-preflight-sync` | skip to Phase 2; record decision preflight_skipped; preflight_sync = skipped | deterministic | prose | - | GAP |
| SV-066 | agents/supervisor.md | h: ### Phase 2: PLAN (Decompose + Analyze Parallelism) | Phase 2 entry | Read async-orchestration SKILL.md (first load); decompose and analyze parallelism | deterministic | prose | - | GAP |
| SV-067 | agents/supervisor.md | q: Input: `goal: "{task_id}: {title}"` + brief pointer ({brief_path}, "read | Orchestrator spawn input | pass brief pointer + ≤200-char criteria summary, never pasted brief bodies | rule | prose | - | GAP |
| SV-068 | agents/supervisor.md | q: When `cost_profile=cheap`: include `model: "sonnet"` in the Task call | cost_profile=cheap at Orchestrator spawn | include model: sonnet in the Task call | deterministic | prose | - | GAP |
| SV-069 | agents/supervisor.md | q: Mark each subtask as LAUNCHABLE or BLOCKED | subtask dependencies + file overlap analyzed | mark each subtask LAUNCHABLE or BLOCKED | deterministic | prose | - | GAP |
| SV-070 | agents/supervisor.md | q: If `--sequential` flag: mark all as sequential (no parallelism) | `--sequential` | mark all subtasks sequential (no parallelism) | deterministic | prose | - | GAP |
| SV-071 | agents/supervisor.md | q: Progress state is not written here — see the pointer in Phase 1 | Phase 2 | progress state is not written here | rule | prose | - | GAP |
| SV-072 | agents/supervisor.md | q: Path selection: exactly 1 subtask → Single-Agent Path (skip worktree | subtask count == 1 / --sequential with > 1 / otherwise | Single-Agent Path / Sequential Path / Parallel Path (Execute Manager); never a per-subtask reviewer | deterministic | prose | - | GAP |
| SV-073 | agents/supervisor.md | q: Parallelism rules: | no unresolved depends_on, no file overlap, worktrees < max_workers | LAUNCHABLE; else BLOCKED | deterministic | prose | - | GAP |
| SV-074 | agents/supervisor.md | h: ### Phase 3: EXECUTE (Delegated to Execute Manager) | Phase 3 entry | execute via the selected path | deterministic | prose | - | GAP |
| SV-075 | agents/supervisor.md | h: #### `--sdk-runner` branch (EXPERIMENTAL — opt-in, default OFF) | `--sdk-runner` passed | do not Task-spawn execute-manager; run the spike runner instead | deterministic | prose | - | GAP |
| SV-076 | agents/supervisor.md | q: **Fail-closed probe (run FIRST):** `command -v node` AND `test -f | sdk-runner probe (node, dist/runner.js, SDK resolvable) fails | ABORT with sdk_runner_unavailable; never fall back silently | deterministic | prose | - | GAP |
| SV-077 | agents/supervisor.md | q: Shell out to the quarantined spike runner (cwd stays the user project): | sdk-runner invocation | shell out with --brief/--branch; max-workers and --cheap NOT forwarded | rule | prose | - | GAP |
| SV-078 | agents/supervisor.md | q: The runner prints an **EXECUTE_RESULT-equivalent** block — parse and | runner prints EXECUTE_RESULT-equivalent | consume as Execute Manager result; merge sdk-spike/subtask-N per merge_order | deterministic | prose | - | GAP |
| SV-079 | agents/supervisor.md | q: FINALIZE delta (runner-emitted result): | consuming a runner-emitted result in FINALIZE | verify branches not worktrees; skip step 2; step 4 tolerates removed worktrees and deletes runner branches | deterministic | prose | - | GAP |
| SV-080 | agents/supervisor.md | q: Zero change to the default path when the flag is absent | flag absent | zero change to the default path; hooks may not fire for SDK workers | rule | prose | - | GAP |
| SV-081 | agents/supervisor.md | h: #### Single-Agent Path (exactly 1 subtask) | exactly 1 subtask | one worker, all criteria, no per-subtask reviewer | deterministic | prose | - | GAP |
| SV-082 | agents/supervisor.md | q: Spawn ONE implementation worker (blocking, in project root) — the | Single-Agent worker spawn | blocking, project root, ALL acceptance criteria; spawn shape from async-orchestration | rule | prose | - | GAP |
| SV-083 | agents/supervisor.md | q: When `cost_profile=cheap`: include `model: "sonnet"` in the Task call | cost_profile=cheap at worker spawn | include model: sonnet | deterministic | prose | - | GAP |
| SV-084 | agents/supervisor.md | q: Record result via Context-Keeper — **including the worker's | worker result recorded | record out_of_lane, deviations, not_verified via Context-Keeper; lane report is record-only (no sibling) | rule | prose | - | test-not-verified-transport-seam.sh |
| SV-085 | agents/supervisor.md | q: **Deterministic gate (zero-token, no reviewer spawn):** run `bash | Single-Agent deterministic gate: any provides item missing on disk | adjudication CHECKPOINT flow; provides_mismatch recorded when worker disagreed | deterministic | prose | script:verify-provides.sh | test-verify-provides.sh |
| SV-086 | agents/supervisor.md | q: else record `provides_unverifiable` and fall back to the worker's self-report | verify-provides unverifiable (brief_unreadable / subtask_not_found / jq_missing / bad_args, or no_contracts on job: path without legacy_brief) | checkpoint; else record provides_unverifiable and fall back to the self-report; no WORKER_RESULT ⇒ pause | deterministic | prose | script:verify-provides.sh | test-verify-provides.sh |
| SV-087 | agents/supervisor.md | q: a worker that never emitted a WORKER_RESULT with N/N present on disk | no WORKER_RESULT but N/N present on disk | record worker_result_absent and continue | deterministic | prose | script:verify-provides.sh | test-verify-provides.sh |
| SV-088 | agents/supervisor.md | q: a `partial` worker with an EMPTY `outputs_gap` | worker outputs_gap the disk does not show / partial with empty outputs_gap | disk wins, continue / retry (bounded) or pause | deterministic | prose | - | GAP |
| SV-089 | agents/supervisor.md | q: LSP diagnostics are the worker's own | LSP diagnostics | are the worker's own; Supervisor does not re-run them | rule | prose | - | GAP |
| SV-090 | agents/supervisor.md | q: **Pin-mutation gate (beside step 3, never folded into its adjudication | step 3 did not checkpoint | run run-pin-mutations.sh once; no summary line or exit not 0/1/2 ⇒ record as incomplete (rows not-run, never held) | deterministic | prose | script:run-pin-mutations.sh | test-run-pin-mutations.sh |
| SV-091 | agents/supervisor.md | q: A `not_held` line ⇒ ONE re-spawn of the same worker | a pin-mutation `not_held` line | ONE re-spawn with the not_held lines as Retry context, ONE re-run; record pin_mutations decision; continue (never a pause) | deterministic | prose | - | test-phase45-rounds-seam.sh |
| SV-092 | agents/supervisor.md | q: A missing script, brief or section is recorded, never a block. | missing script, brief or section for the pin gate | record it, never block | deterministic | prose | - | GAP |
| SV-093 | agents/supervisor.md | q: **Terminal-lifecycle-event join (completion authority, v15.80.0) — a | disk N/N present; lifecycle join unsettled | re-run once; still unsettled ⇒ record provides_present_agent_unsettled and pause (never mark complete) | deterministic | prose | script:check-children-settled.sh | test-check-children-settled.sh |
| SV-094 | agents/supervisor.md | q: On `unverifiable` (`jq_missing`/`bad_args`): fail CLOSED | lifecycle join unverifiable (jq_missing / bad_args) | fail closed: checkpoint, do not pass | deterministic | prose | script:check-children-settled.sh | test-check-children-settled.sh |
| SV-095 | agents/supervisor.md | q: in the script's output means this worker's terminal row | settled with ended_without_result: true | proceed; surface agent_id for a SendMessage resume | deterministic | prose | script:check-children-settled.sh | test-check-children-settled.sh |
| SV-096 | agents/supervisor.md | q: Skip all worktree logic and Execute Manager delegation. Proceed directly | Single-Agent path gates pass | skip worktrees and Execute Manager; go to FINALIZE | deterministic | prose | - | GAP |
| SV-097 | agents/supervisor.md | q: leaves NO semantic review — true at EVERY threshold | `--skip-self-heal` with any job shape | no semantic review remains (only outputs_verified + tests/lint); emergency bypass only | rule | prose | - | GAP |
| SV-098 | agents/supervisor.md | h: #### Sequential Path (`--sequential`, more than 1 subtask) | `--sequential` with more than 1 subtask | serial, no worktrees, no per-subtask reviewer | deterministic | prose | - | GAP |
| SV-099 | agents/supervisor.md | q: **Per-iteration token-ceiling check (red-team-hardening/06 — when | MAX_TOKENS set; ledger TOTAL breached or LEDGER_UNREADABLE=1 before a spawn | stop the loop; status failed, error token_ceiling_reached; go to completion tail (release lock) | deterministic | prose | script:read-token-ledger.sh | test-read-token-ledger.sh |
| SV-100 | agents/supervisor.md | q: this check is implemented on the Sequential Path's own per-subtask loop | Parallel Path token ceiling | not re-checked per worker spawn — honest limit | rule | prose | - | GAP |
| SV-101 | agents/supervisor.md | q: Spawn implementation worker (blocking, in project root) | Sequential worker spawn | blocking, in project root, per subtask in order | rule | prose | - | GAP |
| SV-102 | agents/supervisor.md | q: When `cost_profile=cheap`: include `model: "sonnet"` in the Task call | cost_profile=cheap at Sequential spawn | include model: sonnet | deterministic | prose | - | GAP |
| SV-103 | agents/supervisor.md | q: Record result via Context-Keeper — **including the worker's | Sequential worker result recorded | record out_of_lane, deviations, not_verified via Context-Keeper | rule | prose | - | test-not-verified-transport-seam.sh |
| SV-104 | agents/supervisor.md | q: **Lane reports on this path are RECORD-ONLY — no collision escalation, | Sequential lane report | record-only; no collision escalation (serial execution has no concurrent sibling) | rule | prose | - | GAP |
| SV-105 | agents/supervisor.md | q: **Deterministic gate (zero-token, no reviewer spawn):** run `bash | Sequential deterministic gate | verify-provides per subtask; same disk-wins / D1 / adjudication routing as Single-Agent step 3 | deterministic | prose | script:verify-provides.sh | test-verify-provides.sh |
| SV-106 | agents/supervisor.md | q: **Pin-mutation gate:** Single-Agent step 3a above, scoped with | Sequential pin-mutation gate | same as step 3a with --only-paths <lanes:> | deterministic | prose | script:run-pin-mutations.sh | test-run-pin-mutations.sh |
| SV-107 | agents/supervisor.md | q: **Terminal-lifecycle-event join (completion authority, v15.80.0) — | Sequential lifecycle join | same retry-once-then-pause / fail-closed / ended_without_result handling as step 3b | deterministic | prose | script:check-children-settled.sh | test-check-children-settled.sh |
| SV-108 | agents/supervisor.md | q: Skip all worktree logic and Execute Manager delegation | Sequential path done | skip worktree logic and Execute Manager delegation | deterministic | prose | - | GAP |
| SV-109 | agents/supervisor.md | h: #### Parallel Path (multi-subtask) | multi-subtask, not --sequential | delegate Phase 3 to Execute Manager in one Task call | deterministic | prose | - | GAP |
| SV-110 | agents/supervisor.md | q: **`subtasks_failed`: escalation ⇔ `subtasks_failed` is non-empty** | parsing EXECUTE_RESULT | escalation ⇔ subtasks_failed non-empty (no top-level status field) | deterministic | prose | script:validate-execute-result.py | test-result-validators.sh |
| SV-111 | agents/supervisor.md | q: EXECUTE_RESULT, `subtasks_failed` empty (completed) | EXECUTE_RESULT, subtasks_failed empty | extract merge data, proceed to FINALIZE | deterministic | prose | - | GAP |
| SV-112 | agents/supervisor.md | q: EXECUTE_RESULT, `subtasks_failed` non-empty + `subtasks_completed` | subtasks_failed and subtasks_completed both non-empty | FINALIZE the completed subset per merge_order, then report the failed ones as escalation | deterministic | prose | - | GAP |
| SV-113 | agents/supervisor.md | q: EXECUTE_RESULT, `subtasks_completed` empty (all-failed escalation) | subtasks_completed empty | checkpoint, report with resume command; nothing to merge | deterministic | prose | - | GAP |
| SV-114 | agents/supervisor.md | q: EXECUTE_CHECKPOINT (partial) | EXECUTE_CHECKPOINT (partial) | checkpoint; ask user: merge completed subset or continue with a fresh Execute Manager | judgment | prose | - | GAP |
| SV-115 | agents/supervisor.md | q: EXECUTE_CHECKPOINT (`adjudication_required: true`) | EXECUTE_CHECKPOINT adjudication_required: true | pause EXECUTE; 4-option AskUserQuestion (Adjudication Handling) | deterministic | prose | - | GAP |
| SV-116 | agents/supervisor.md | q: Execute Manager crash | Execute Manager crash | checkpoint, report worktree state, exit with resume | deterministic | prose | - | GAP |
| SV-117 | agents/supervisor.md | q: Tool budget warning | tool budget warning during EXECUTE | checkpoint, exit with resume command | deterministic | prose | - | GAP |
| SV-118 | agents/supervisor.md | h: #### Adjudication Handling (CHECKPOINT with adjudication_required) | EXECUTE_CHECKPOINT with adjudication_required | run the adjudication procedure | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| SV-119 | agents/supervisor.md | q: TWO raisers, two option sets | adjudication checkpoint received | branch on adjudication_kind, never on the reason prose | deterministic | prose | - | GAP |
| SV-120 | agents/supervisor.md | q: `requires_gap` (default when the field is ABSENT — every pre-v15.20.0 | adjudication_kind requires_gap or absent | use producer/consumer/requires option set; Option C reason inter_subtask_gap | deterministic | prose | - | GAP |
| SV-121 | agents/supervisor.md | q: `lane_collision` (v15.20.0, D6) | adjudication_kind lane_collision | use writer/lane-owner/declaration option set; Option C reason lane_collision | deterministic | prose | - | GAP |
| SV-122 | agents/supervisor.md | q: Do not adjudicate a lane collision with the `requires_gap` options. | lane collision | never adjudicate with requires_gap options; never emit inter_subtask_gap (it triggers /autonomous re-plan) | rule | prose | - | GAP |
| SV-123 | agents/supervisor.md | q: **Pause the EXECUTE phase** — do not spawn further workers, do not | adjudication pending | pause EXECUTE; spawn nothing, advance nothing until a choice is made | deterministic | prose | - | GAP |
| SV-124 | agents/supervisor.md | q: **Read `adjudication_kind`, the matching evidence array, and | presenting adjudication options | read kind/evidence/options; absent kind ⇒ requires_gap; present options verbatim as emitted | deterministic | prose | - | GAP |
| SV-125 | agents/supervisor.md | q: **Present all four options to the user via `AskUserQuestion`** | adjudication and cannot ask | pick no option; checkpoint; status failed, error adjudication_required_non_interactive; brief stays in in-progress/ | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| SV-126 | agents/supervisor.md | q: **A: Re-queue producer** — Execute Manager re-spawns the producing | requires_gap option A chosen | Execute Manager re-spawns the producer with the missing outputs in its criteria | judgment | prose | - | GAP |
| SV-127 | agents/supervisor.md | q: **B: Insert remediation subtask** — Supervisor inserts a new ad-hoc | requires_gap option B chosen | insert a remediation subtask providing the missing items; consumer blocked on it | judgment | prose | - | GAP |
| SV-128 | agents/supervisor.md | q: **C: Exit to Launch Pad** — Supervisor checkpoints state, marks the | requires_gap option C chosen | checkpoint, mark job failed reason inter_subtask_gap, exit; user reruns /launch-pad | judgment | prose | - | GAP |
| SV-129 | agents/supervisor.md | q: **D: Update consumer brief** — Supervisor edits the in-progress brief | requires_gap option D chosen | edit the in-progress brief to drop the failing requires entry; re-emit consumer | judgment | prose | - | GAP |
| SV-130 | agents/supervisor.md | q: **A: Re-queue writer with the sibling lane excluded** — Execute | lane_collision option A chosen | re-spawn this_subtask with the path named off-limits | judgment | prose | - | GAP |
| SV-131 | agents/supervisor.md | q: **B: Serialize the pair (add a requires edge)** — Supervisor adds a | lane_collision option B chosen | add a requires edge; re-verify the graph stays acyclic before applying | judgment | prose | - | GAP |
| SV-132 | agents/supervisor.md | q: **C: Exit to Launch Pad** — Supervisor checkpoints state, marks the | lane_collision option C chosen | mark job failed reason lane_collision (NOT inter_subtask_gap), exit | judgment | prose | - | GAP |
| SV-133 | agents/supervisor.md | q: **D: Widen the writer's declared lane** — Supervisor edits the | lane_collision option D chosen | add path to this_subtask lanes:; only sound when the pair does not race | judgment | prose | - | GAP |
| SV-134 | agents/supervisor.md | q: **A:** spawn a fresh Execute Manager invocation with the producer | apply requires_gap A | spawn a fresh Execute Manager with the producer re-queued | deterministic | prose | - | GAP |
| SV-135 | agents/supervisor.md | q: **B:** insert the remediation subtask into the plan (update parallelism | apply requires_gap B | insert remediation subtask, update parallelism graph, resume | deterministic | prose | - | GAP |
| SV-136 | agents/supervisor.md | q: **C:** mark the job `failed` with `reason: inter_subtask_gap`, move the | apply requires_gap C | job failed reason inter_subtask_gap; move brief to jobs/failed/; exit | deterministic | prose | - | GAP |
| SV-137 | agents/supervisor.md | q: **D:** edit the in-progress brief in `.supervisor/jobs/in-progress/` to | apply requires_gap D | edit in-progress brief, record_decision, resume with amended consumer | deterministic | prose | - | GAP |
| SV-138 | agents/supervisor.md | q: **A:** spawn a fresh Execute Manager invocation with `this_subtask` | apply lane_collision A | fresh Execute Manager with this_subtask re-queued, path off-limits | deterministic | prose | - | GAP |
| SV-139 | agents/supervisor.md | q: **B:** add the `requires` edge to the in-progress brief, re-check the | apply lane_collision B | add requires edge, re-check cycles, record_decision, resume | deterministic | prose | - | GAP |
| SV-140 | agents/supervisor.md | q: **C:** mark the job `failed` with `reason: lane_collision`, move the | apply lane_collision C | job failed reason lane_collision; brief to jobs/failed/; terminal failed for /autonomous | deterministic | prose | - | GAP |
| SV-141 | agents/supervisor.md | q: **D:** edit the in-progress brief to add `path` to `this_subtask`'s | apply lane_collision D | add path to lanes:, record_decision, resume | deterministic | prose | - | GAP |
| SV-142 | agents/supervisor.md | q: the Supervisor never picks an option silently | any adjudication | never pick an option silently; auto-selection forbidden | rule | prose | - | GAP |
| SV-143 | agents/supervisor.md | h: ### Phase 4: FINALIZE (Merge + Commit + PR) | EXECUTE complete with merge data (incl. partial subset) | run FINALIZE: Read async-orchestration + commit skills; execute Part 2 | deterministic | prose | - | GAP |
| SV-144 | agents/supervisor.md | q: **Pre-merge safety gate:** the 5-point pre-merge checklist (all | any of the 5 pre-merge checklist points fails | abort merge, log, move job to failed/; missing worktree/branch ⇒ checkpoint and exit with resume | deterministic | prose | - | GAP |
| SV-145 | agents/supervisor.md | q: **Point 5 — children settled (completion authority, v15.80.0):** run | Point 5: check-children-settled --all + --expect-id per recorded worker | settled / no_identity_rows (only when nothing spawned) pass; unsettled or unverifiable fail | deterministic | prose | script:check-children-settled.sh | test-check-children-settled.sh |
| SV-146 | agents/supervisor.md | q: error: "children_unsettled: {unsettled_agent_ids}"` | Point 5 unsettled under --non-interactive / CI / no TTY | fail closed: status failed, error children_unsettled; interactive ⇒ ask proceed / investigate / abort | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| SV-147 | agents/supervisor.md | q: short-circuits this ONE point as a deliberate choice | `--skip-children-check` | skip Point 5 only; record user_skipped_children_check; children_check: skipped | deterministic | prose | - | test-check-children-settled.sh |
| SV-148 | agents/supervisor.md | q: Publish is blocked until this point passes | git push / gh pr create in a live run | denied by the PreToolUse guard until the finalize-gate marker names HEAD; write it only via write-marker; unparsed Worker Results ⇒ worker_results_unparsed | deterministic | prose | script:guard-finalize-publish.sh | test-guard-finalize-publish.sh |
| SV-149 | agents/supervisor.md | q: **Merge conflict → STOP:** never force-resolve. Report the conflicting | merge conflict | STOP, never force-resolve; report files; checkpoint merged/unmerged lists; exit with resume | deterministic | prose | - | GAP |
| SV-150 | agents/supervisor.md | q: **Salvage before remove (v15.67.0):** `bash | before each worktree remove | run worktree-salvage.sh as its own statement; dirty refusal reported with salvage path, never force-removed | deterministic | prose | script:worktree-salvage.sh | test-worktree-salvage.sh |
| SV-151 | agents/supervisor.md | q: **PR-base self-verify (REQUIRED):** immediately after `gh pr create | after gh pr create | verify baseRefName == $BASE_BRANCH; mismatch / gh failure ⇒ set base_mismatch_detected once, fall through to Phase 4.5 cleanup (never emit here) | deterministic | prose | - | GAP |
| SV-152 | agents/supervisor.md | q: **Release re-fold before the first push (#512):** at skill step 5.5 — | before the first push (step 5.5) | run release-refold.sh; non-zero ⇒ no push/PR, status failed, error release_refold_refused, lock released | deterministic | prose | script:release-refold.sh | test-release-refold.sh |
| SV-153 | agents/supervisor.md | q: PR created against `$BASE_BRANCH` + base self-verified → exit FINALIZE | PR created and base verified | go to Phase 4.5; do not mark completed or move job here | deterministic | prose | - | GAP |
| SV-154 | agents/supervisor.md | q: Base mismatch / unrecoverable `gh` failure → `base_mismatch_detected` | base mismatch / unrecoverable gh failure | set base_mismatch_detected; status failed emitted in Phase 4.5 only | deterministic | prose | - | GAP |
| SV-155 | agents/supervisor.md | q: Merge conflict or failed pre-merge validation → STOP as above; exit | merge conflict or failed pre-merge validation | STOP; exit with resume command | deterministic | prose | - | GAP |
| SV-156 | agents/supervisor.md | h: ### Phase 4.5: SELF_HEAL (Integration Review + Bounded Fix Loop) | after FINALIZE | Read self-heal-advisory + state-management; run the Part 2 loop protocol | deterministic | prose | - | GAP |
| SV-157 | agents/supervisor.md | q: **Purpose:** Run a holistic Code Reviewer pass on the integrated feature | Phase 4.5 fix scope | auto-fix bounded new issues at or above FIX_FLOOR (default MEDIUM; BLOCKING always); escalate the rest | rule | prose | script:fix-floor.sh meets | test-fix-floor.sh |
| SV-158 | agents/supervisor.md | q: The `--skip-self-heal` flag does NOT skip the phase | `--skip-self-heal` | does NOT skip Phase 4.5; only the review-and-fix loop; transition and completion tail always run | rule | prose | - | GAP |
| SV-159 | agents/supervisor.md | q: Phase 4.5 mandate: | --skip-self-heal false | must Task-spawn code-reviewer on the integrated diff at least once before the completion tail | rule | prose | - | GAP |
| SV-160 | agents/supervisor.md | q: Invariant tracking (initialized at phase entry | Phase 4.5 entry | init skip_self_heal_requested (immutable), phase45_review_invoked=false, red_team_advisory=disabled | rule | prose | - | GAP |
| SV-161 | agents/supervisor.md | q: `heal_decision == PASS` (or loop skipped: `heal_loop_ran=false`, valid | heal_decision PASS (or loop skipped with --skip-self-heal) | task completed; job → done/ | deterministic | prose | - | GAP |
| SV-162 | agents/supervisor.md | q: `heal_decision == ESCALATED` (reviewer NEEDS_HUMAN, max | heal_decision ESCALATED (NEEDS_HUMAN, max iterations, thrash) | completed_with_escalation; findings posted as PR comment; job → done/ with escalation fields | deterministic | prose | - | GAP |
| SV-163 | agents/supervisor.md | q: Hard failure: base-branch mismatch cleanup → `status: failed`, job → | base-mismatch cleanup / fix-task crash or budget / guard violation | failed + failed/ / checkpoint pause / failed, job stays in-progress/ | deterministic | prose | - | GAP |
| SV-164 | agents/supervisor.md | q: **Completion-tail guard (runtime invariant — primary enforcement of | completion tail starts | check both tracked booleans first (guard) | deterministic | prose | - | GAP |
| SV-165 | agents/supervisor.md | q: **Thrash-escalation exception:** if this run reached the completion tail | reached tail via resume-thrash (self_heal_resume_thrash) | guard does not apply; proceed with normal tail | deterministic | prose | - | GAP |
| SV-166 | agents/supervisor.md | q: Otherwise, if `skip_self_heal_requested == false` AND | skip_self_heal_requested false AND phase45_review_invoked false | abort: status failed, Phase 4.5 invariant violation | deterministic | prose | - | GAP |
| SV-167 | agents/supervisor.md | q: Emit a `SUPERVISOR_RESULT` block with `status: failed`, `error: "Phase | guard violated | emit SUPERVISOR_RESULT status failed with the invariant-violation error and summary | deterministic | prose | - | GAP |
| SV-168 | agents/supervisor.md | q: Do NOT mark the task complete. | guard violated | do not mark the task complete | rule | prose | - | GAP |
| SV-169 | agents/supervisor.md | q: Do NOT move the job file to `done/` — leave it in `in-progress/` for | guard violated | do not move the job to done/; leave in in-progress/ | rule | prose | - | GAP |
| SV-170 | agents/supervisor.md | q: Do NOT record PASS / ESCALATED in heal state — record | guard violated | record invariant_violation decision, not PASS/ESCALATED | rule | prose | - | GAP |
| SV-171 | agents/supervisor.md | q: Do NOT reset the resume counter — leave it so a subsequent | guard violated | do not reset the resume counter | rule | prose | - | GAP |
| SV-172 | agents/supervisor.md | q: Exit the phase with `status: failed`. The operator then re-runs either | guard violated | exit with status failed; operator re-runs with --continue or --skip-self-heal | deterministic | prose | - | GAP |
| SV-173 | agents/supervisor.md | q: Otherwise proceed with the normal completion tail below. | guard passes | proceed with the normal completion tail | deterministic | prose | - | GAP |
| SV-174 | agents/supervisor.md | q: This guard exists so that if inline main-thread execution | why the guard exists | inline runs that forgot the reviewer self-report as failed | story | prose | - | GAP |
| SV-175 | agents/supervisor.md | q: **Run-lock release (red-team-hardening/06):** `run-lock.sh release | completion tail (PASS / ESCALATED / guard fail) or any earlier Phase 4 abort | run-lock.sh release --owner supervisor:<sid> | deterministic | prose | script:run-lock.sh release | test-run-lock.sh |
| SV-176 | agents/supervisor.md | q: **Rubric grader spawn condition:** spawn `loomwright:rubric-grader` ONLY | brief has ## Outcomes Rubric AND heal_decision PASS | spawn rubric-grader (advisory); else rubric_score null, never fails the task | deterministic | prose | - | GAP |
| SV-177 | agents/supervisor.md | q: **Until-mergeable drain dispatch (completion-tail step 5.5):** DEFAULT | PASS / normal completion produced a PR | dispatch until-mergeable drain (default on); --no-auto-review suppresses; --no-until-mergeable ⇒ plain /review-pr; never merges | deterministic | prose | script:dispatch-pr-review.sh | test-dispatch-pr-review.sh |
| SV-178 | agents/supervisor.md | q: **`until_mergeable_dispatched` marker-reconcile rule:** resolve from the | recording until_mergeable_dispatched | resolve from the on-disk dispatch marker, never from control flow (hook dispatches invisibly) | rule | prose | - | GAP |
| SV-179 | agents/supervisor.md | q: **Advisory red-team lens:** opt-in (`--red-team` / | `--red-team` / .red_team_high_risk and diff high-risk | one non-gating red-team pass outside the loop; classify-risk always runs; red_team_advisory carried | deterministic | prose | script:classify-risk.sh | test-classify-risk.sh |
| SV-180 | agents/supervisor.md | q: **Multi-voter verification (`--multi-voter-heal`):** opt-in, DEFAULT-OFF | `--multi-voter-heal` enabled | second independent vote; BLOCKING/HIGH new finding fixed only if it survives refute; counters in summary | deterministic | prose | - | GAP |
| SV-181 | agents/supervisor.md | h: ### Phase 5: LOOP (Next Task or Exit) | after Phase 4.5 completion tail | Phase 5 LOOP: next task or exit; no task-completion actions here | deterministic | prose | - | GAP |
| SV-182 | agents/supervisor.md | q: Consume heal outcome from Phase 4.5 (heal_decision, heal_iterations, | Phase 5 | consume heal outcome for reporting; never re-emit SUPERVISOR_RESULT | rule | prose | - | GAP |
| SV-183 | agents/supervisor.md | q: Save session history: | Phase 5 | copy state.md to .supervisor/history/<date>-<task_id>.md | rule | prose | - | GAP |
| SV-184 | agents/supervisor.md | q: Return to the base branch (the one Phase 1 ACQUIRE branched from): | Phase 5 | check out ${BASE_BRANCH:-main} (honors stacked /autonomous base) | rule | prose | - | GAP |
| SV-185 | agents/supervisor.md | q: Ask user if more tasks to work on | Phase 5 | ask user whether more tasks exist | judgment | prose | - | GAP |
| SV-186 | agents/supervisor.md | q: If tasks exist AND tool_calls < 40 (80%): return to Phase 1 (ACQUIRE) | tasks exist AND tool_calls < 40 | return to Phase 1; next task emits its own SUPERVISOR_RESULT | deterministic | prose | - | GAP |
| SV-187 | agents/supervisor.md | q: If tool_calls 40-46: checkpoint and warn, suggest new session | tool_calls 40-46 | checkpoint and warn; suggest new session | deterministic | prose | - | GAP |
| SV-188 | agents/supervisor.md | q: If no tasks: report completion | no tasks | report completion | deterministic | prose | - | GAP |
| SV-189 | agents/supervisor.md | h: ### Tool Call Budget (50 calls, soft guidance) | counting tool calls | per-phase estimates are guidance; only the GREEN/YELLOW/RED bands fire | rule | prose | - | GAP |
| SV-190 | agents/supervisor.md | q: hard cap is ≤6 | Phase 1.5 cost | hard cap ≤6 calls; overruns governed by YELLOW 30 / RED 40 thresholds | rule | prose | - | GAP |
| SV-191 | agents/supervisor.md | q: when Phase 1 did NOT just fetch | cold fetch at Phase 1.5 | may cost the full ≤6; a later overrun checkpoints rather than breaching | rule | prose | - | GAP |
| SV-192 | agents/supervisor.md | q: Normal operation | tool calls 0-30 | GREEN: normal operation | deterministic | prose | - | GAP |
| SV-193 | agents/supervisor.md | q: Aggressive compression (<100 tokens); in Phase 4.5 | tool calls 30-40 | YELLOW: compress <100 tokens; in Phase 4.5 skip remaining advisory steps, gates still run | deterministic | prose | - | GAP |
| SV-194 | agents/supervisor.md | q: Force checkpoint, suggest new session (Phase 5 LOOP picks up no new tasks) | tool calls 40-46 | RED: force checkpoint, suggest new session; LOOP picks up no new tasks | deterministic | prose | - | GAP |
| SV-195 | agents/supervisor.md | q: Checkpoint + exit with resume command | tool calls 46+ | RED: checkpoint + exit with resume command | deterministic | prose | - | GAP |
| SV-196 | agents/supervisor.md | h: ### Supervisor Context Budget (~400 tokens) | Supervisor context | ~400 tokens; all else in state file; poll loop lives in Execute Manager | rule | prose | - | GAP |
| SV-197 | agents/supervisor.md | h: ### Resume Protocol | resume | scratchpad state → .supervisor/state.md → none = fresh start; gate run from supervisor-config | deterministic | prose | script:reconcile-resume-state.sh | test-reconcile-resume-state.sh |
| SV-198 | agents/supervisor.md | q: Override base branch for FINALIZE PR creation | `--base-branch <name>` | override FINALIZE PR base; Phase 4 self-verifies baseRefName; Phase 4.5 cleans up on mismatch | rule | prose | - | GAP |
| SV-199 | agents/supervisor.md | q: Suppress `AskUserQuestion` fallbacks | `--non-interactive` (or running as a subagent) | suppress AskUserQuestion; fail closed with diagnostic; recorded as Phase Flag | rule | prose | - | test-non-interactive-gates-seam.sh |
| SV-200 | agents/supervisor.md | q: No tasks provided | no tasks provided | report and exit gracefully | deterministic | prose | - | GAP |
| SV-201 | agents/supervisor.md | q: Fix task crash in SELF_HEAL | fix task crash in SELF_HEAL | pause, increment resume counter, exit with resume; 3rd pause escalates self_heal_resume_thrash | deterministic | prose | - | GAP |
| SV-202 | agents/supervisor.md | q: SELF_HEAL loop exhausts max iterations | SELF_HEAL loop exhausts max iterations | mark ESCALATED, post PR comment, run completion tail, exit normally | deterministic | prose | - | GAP |
| SV-203 | agents/supervisor.md | q: CODE_REVIEW_RESULT missing from integration review | CODE_REVIEW_RESULT missing from integration review | retry review once; still missing ⇒ pause with resume | deterministic | prose | - | GAP |
| SV-204 | agents/supervisor.md | q: Dirty working tree | dirty working tree | warn user; ask to stash or commit | judgment | prose | - | GAP |
| SV-205 | agents/supervisor.md | h: ### Agents Spawned by Supervisor | spawns | Context-Keeper every phase, PO if vague, Orchestrator Phase 2, Execute Manager or Worker Phase 3 (all blocking) | rule | prose | - | GAP |
| SV-206 | agents/supervisor.md | q: No per-subtask Code Reviewer is spawned on any Phase 3 path | any Phase 3 path | no per-subtask Code Reviewer; Phase 4.5 is the sole LLM review; multi-subtask workers spawned by Execute Manager | rule | prose | - | GAP |
| SV-207 | agents/supervisor.md | h: ### Summary Extraction | after each blocking subagent | extract a minimal summary per the template table | rule | prose | - | GAP |
| SV-208 | agents/supervisor.md | q: Parse CODE_REVIEW_RESULT block; filter issues where category=new | Phase 4.5 CODE_REVIEW_RESULT parsed | fix-task input = issues with category=new AND fix-floor.sh meets prints fix | deterministic | prose | script:fix-floor.sh meets | test-fix-floor.sh |
| SV-209 | agents/supervisor.md | h: ### Subagent Spawn Contracts | spawn shapes | exact Task shapes live in async-orchestration Part 2 §Subagent Spawn Contracts | rule | prose | - | GAP |
| SV-210 | agents/supervisor.md | q: Every spawn honors `cost_profile`: include `model: "sonnet"` ONLY when | any spawn | include model: sonnet ONLY when cost_profile=cheap; omit otherwise | deterministic | prose | - | GAP |
| SV-211 | agents/supervisor.md | q: The Single-Agent and Sequential-path Worker prompts pass the brief's | Single-Agent / Sequential worker prompt | pass the brief's provides: VERBATIM; omitting it no-ops the outputs gate | rule | prose | - | test-verify-provides.sh |
| SV-212 | agents/supervisor.md | q: House-rules injection into the Worker prompt is ADVISORY / fail-safe / | house-rules injection | advisory, fail-safe, never gating; read-rules.sh args never stdin; inject only when non-empty; check is data, never executed | rule | prose | script:read-rules.sh | test-rules-seams.sh |
| SV-213 | agents/supervisor.md | q: one file per session | session logging | JSONL per session in .supervisor/logs/; retention 7 days, cleaned in INIT | rule | prose | - | GAP |
| SV-214 | agents/supervisor.md | q: is REQUIRED:** Phase 4.5's completion tail MUST emit | Phase 4.5 completion tail | MUST emit session_end with FLAT hard-signal fields; never rename (build-insights.sh contract) | rule | prose | - | test-insights.sh |
| SV-215 | agents/supervisor.md | q: Subtask branches AND worktrees are both created by the | subtask branches + worktrees | created by Execute Manager in Phase 3, never by Supervisor in Phase 2 (Phase 2 runs no git) | rule | prose | - | GAP |
| SV-216 | agents/supervisor.md | q: [ ] Feature branch created before any code work | before completing workflow | feature branch created before any code work | rule | prose | - | GAP |
| SV-217 | agents/supervisor.md | q: [ ] All subtasks implemented and reviewed (PASS) | before completing workflow | all subtasks implemented and gated | rule | prose | - | GAP |
| SV-218 | agents/supervisor.md | q: [ ] Pre-merge validation passed (worktrees, branches, changes verified) | before completing workflow | pre-merge validation passed | rule | prose | - | GAP |
| SV-219 | agents/supervisor.md | q: [ ] Worker changes committed in worktrees before merge | before completing workflow | worker changes committed in worktrees before merge | rule | prose | - | GAP |
| SV-220 | agents/supervisor.md | q: [ ] All worktrees cleaned up (none orphaned) | before completing workflow | all worktrees cleaned up | rule | prose | - | GAP |
| SV-221 | agents/supervisor.md | q: [ ] Commits created with task linking | before completing workflow | commits created with task linking | rule | prose | - | GAP |
| SV-222 | agents/supervisor.md | q: [ ] PR created and linked to task | before completing workflow | PR created and linked to task | rule | prose | - | GAP |
| SV-223 | agents/supervisor.md | q: [ ] State file updated with completed status in `.supervisor/` | before completing workflow | state file updated with completed status | rule | prose | - | GAP |
| SV-224 | agents/supervisor.md | q: [ ] Session history saved | before completing workflow | session history saved | rule | prose | - | GAP |
| SV-225 | agents/supervisor.md | q: [ ] Returned to main branch | before completing workflow | returned to the base branch | rule | prose | - | GAP |
| SV-226 | agents/supervisor.md | q: [ ] Clean working tree | before completing workflow | clean working tree | rule | prose | - | GAP |
| SV-227 | agents/supervisor.md | q: [ ] Tool call budget not exceeded | before completing workflow | tool call budget not exceeded | rule | prose | - | GAP |
| SV-228 | agents/supervisor.md | q: **Plugin hooks (`hooks/hooks.json`) pre-validate child output:** | child output | SubagentStop validates WORKER_RESULT / EXECUTE_RESULT; TaskCompleted prevents premature closure | rule | prose | script:validate-worker-result.py | test-result-validators.sh |
| SV-229 | agents/supervisor.md | q: **Agent Teams (alternative parallel strategy):** for | research/exploration tasks | Agent Teams is the alternative; worktrees stay the default | rule | prose | - | GAP |
| SV-230 | agents/supervisor.md | q: Exactly one SUPERVISOR_RESULT block is emitted per task | per task | exactly one SUPERVISOR_RESULT, from the Phase 4.5 completion tail; LOOP emits nothing; hook validates the last block | rule | prose | script:validate-supervisor-result.py | test-result-validators.sh |
| SV-231 | agents/supervisor.md | q: additive field (v14.28.0): | knowledge_sources_used | additive advisory array; never gated; dual shape (nested + flat session_end) | rule | prose | - | GAP |
| SV-232 | agents/supervisor.md | q: System Twin additive fields | System Twin fields | advisory; never change heal_decision or block the PR; flat session_end names are a hard contract | rule | prose | - | GAP |
| SV-233 | agents/supervisor.md | q: `heal_decision=PASS` OR `heal_loop_ran=false` (loop skipped via | heal_decision PASS or heal_loop_ran false | status completed | deterministic | prose | - | GAP |
| SV-234 | agents/supervisor.md | q: `heal_decision=ESCALATED` → `status: completed_with_escalation` | heal_decision ESCALATED | status completed_with_escalation | deterministic | prose | - | GAP |
| SV-235 | agents/supervisor.md | q: Hard failures (merge conflict, fix task crash after retries, resume | hard failure (merge conflict, fix crash after retries, thrash) | status failed or completed_with_escalation depending on the phase | judgment | prose | - | GAP |
| SV-236 | agents/supervisor.md | q: Phase 1.5 PRE-FLIGHT SYNC fail-closed abort (OVERLAP/SUPERSEDED under | Phase 1.5 fail-closed abort | status failed, error preflight_overlap_detected | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| SV-237 | agents/supervisor.md | q: Budget exhaustion (40+ tool calls, phase still running) → `status: | budget exhaustion (40+ calls, phase running) | status checkpoint | deterministic | prose | - | GAP |
| SV-238 | agents/supervisor.md | q: `pr_url` MUST be present when `status in [completed, | status completed / completed_with_escalation | pr_url MUST be present | deterministic | prose | script:validate-supervisor-result.py | test-result-validators.sh |
| SV-239 | agents/supervisor.md | q: When `heal_loop_ran=false`: `heal_iterations=null`, | heal_loop_ran false | heal_iterations null, heal_decision null, fixed 0, remaining 0 exactly | deterministic | prose | script:validate-supervisor-result.py | test-result-validators.sh |
| SV-240 | agents/supervisor.md | q: When `heal_loop_ran=true`: `heal_decision ∈ [PASS, ESCALATED]` (never | heal_loop_ran true | heal_decision PASS or ESCALATED (never SKIPPED); iterations non-negative ≤ max | deterministic | prose | script:validate-supervisor-result.py | test-result-validators.sh |
| SV-241 | agents/supervisor.md | q: `heal_remaining_issues=0` when `heal_decision=PASS`; when | heal_decision PASS / ESCALATED | remaining 0 / remaining ≥1 or error non-empty | deterministic | prose | script:validate-supervisor-result.py | test-result-validators.sh |
| SV-242 | agents/supervisor.md | q: `error` MUST be non-empty when `status=failed` | status failed | error MUST be non-empty | deterministic | prose | script:validate-supervisor-result.py | test-result-validators.sh |
| SV-243 | agents/supervisor.md | q: `summary` is always required and non-empty | any SUPERVISOR_RESULT | summary required and non-empty | deterministic | prose | script:validate-supervisor-result.py | test-result-validators.sh |
| SV-244 | agents/supervisor.md | q: `rubric_score` (optional, v12.2.0+) is `null` OR a string `"N/M"` where | rubric_score present | null or "N/M" with N ≥ 0, M ≥ 1, M ≥ N | deterministic | prose | script:validate-supervisor-result.py | test-result-validators.sh |
| SV-245 | commands/supervisor.md | q: Execute this workflow inline as the main thread. | /supervisor invoked from the main thread | execute inline; never delegate to supervisor-runner via the Agent tool (subagent loses the ask tool and nesting depth) | rule | prose | - | GAP |
| SV-246 | commands/supervisor.md | q: Inline main-thread execution replaces only the top-level | inline execution | still Task-spawn orchestrator, execute-manager/worker, code-reviewer + fix loop; Phase 4.5 mandatory unless --skip-self-heal | rule | prose | - | GAP |
| SV-247 | commands/supervisor.md | q: `--continue` | `--continue` with an invalid state file | refuse with resume_state_invalid; no override flag | deterministic | prose | script:reconcile-resume-state.sh | test-reconcile-resume-state.sh |
| SV-248 | commands/supervisor.md | q: Path to Supervisor-Ready Brief from Launch Pad | `job:` path given | skip Phases 0-2 planning; move brief pending → in-progress → done/failed | deterministic | prose | - | GAP |
| SV-249 | commands/supervisor.md | q: `--skip-self-heal` | `--skip-self-heal` | bypass Phase 4.5 review + fix loop; heal_loop_ran false; absent flag makes Phase 4.5 mandatory | rule | prose | - | GAP |
| SV-250 | commands/supervisor.md | q: `--heal-iterations N` | `--heal-iterations N` | max fix iterations before escalating (default 3) | deterministic | prose | - | GAP |
| SV-251 | commands/supervisor.md | q: `--fix-floor <HIGH | `--fix-floor` / .fix_floor | fix findings at or above the floor (default MEDIUM, BLOCKING always); invalid value ⇒ fix_floor_invalid stops the run | deterministic | prose | script:fix-floor.sh resolve | test-fix-floor.sh |
| SV-252 | commands/supervisor.md | q: N/A for a `--voter-provider` voter: | `--cheap` | sonnet override for listed spawns; N/A for a --voter-provider shell-out | rule | prose | - | GAP |
| SV-253 | commands/supervisor.md | q: `--max-tokens N` | `--max-tokens N` set | record Phase Flag; ledger breach or LEDGER_UNREADABLE ⇒ status failed, token_ceiling_reached before another round | deterministic | prose | script:read-token-ledger.sh | test-read-token-ledger.sh |
| SV-254 | commands/supervisor.md | q: a held lock PARKs the run BEFORE any work begins | Phase 0 run lock | run-lock.sh acquire; held ⇒ park (run_lock_held); reentrant / degraded ⇒ proceed | deterministic | prose | script:run-lock.sh acquire | test-run-lock.sh |
| SV-255 | commands/supervisor.md | q: may also carry a `Base Branch:` field | brief carries Base Branch: | it MUST match --base-branch; Phase 4 aborts via 4.5 cleanup on PR base mismatch | rule | prose | - | GAP |
| SV-256 | commands/supervisor.md | q: Suppress `AskUserQuestion` fallbacks; on `gh` failures | `--non-interactive` (or subagent) | suppress AskUserQuestion; fail closed with diagnostic | rule | prose | - | test-non-interactive-gates-seam.sh |
| SV-257 | commands/supervisor.md | q: `--skip-preflight-sync` | `--skip-preflight-sync` | skip Phase 1.5; record decision; only way past OVERLAP/SUPERSEDED under --non-interactive | deterministic | prose | - | GAP |
| SV-258 | commands/supervisor.md | q: `--skip-children-check` | `--skip-children-check` | skip Point 5 (and the worker_results_unparsed refusal); record user_skipped_children_check | deterministic | prose | script:guard-finalize-publish.sh | test-guard-finalize-publish.sh |
| SV-259 | commands/supervisor.md | q: `--no-until-mergeable` | PR created, `--no-until-mergeable` / .auto_until_mergeable false | dispatched runner runs plain diff-only /review-pr; default true runs the heal-only drain; never merges | deterministic | prose | script:dispatch-pr-review.sh | test-dispatch-pr-review.sh |
| SV-260 | commands/supervisor.md | q: `--check-wait-timeout N` | `--check-wait-timeout N` set | forward via LOOMWRIGHT_CHECK_WAIT_TIMEOUT only when set | deterministic | prose | script:dispatch-pr-review.sh | test-dispatch-pr-review.sh |
| SV-261 | commands/supervisor.md | q: `--review-check-pattern <glob>` | `--review-check-pattern <glob>` set | forward via LOOMWRIGHT_REVIEW_CHECK_PATTERN only when set | deterministic | prose | script:dispatch-pr-review.sh | test-dispatch-pr-review.sh |
| SV-262 | commands/supervisor.md | q: `--auto-review` | `--auto-review` | legacy no-op-equivalent enable; dispatcher always exits 0 | rule | prose | script:dispatch-pr-review.sh | test-dispatch-pr-review.sh |
| SV-263 | commands/supervisor.md | q: `--no-auto-review` | `--no-auto-review` / .auto_review false | suppress the review-drain dispatch entirely; wins over --auto-review | deterministic | prose | script:dispatch-pr-review.sh | test-dispatch-pr-review.sh |
| SV-264 | commands/supervisor.md | q: `--red-team` | `--red-team` and diff high-risk | one non-gating red-team pass; low-risk skips; failure is a logged no-op | deterministic | prose | script:classify-risk.sh | test-classify-risk.sh |
| SV-265 | commands/supervisor.md | q: `--no-red-team` | `--no-red-team` | suppress red-team lens; wins over --red-team | deterministic | prose | - | GAP |
| SV-266 | commands/supervisor.md | q: `--multi-voter-heal` | `--multi-voter-heal` | voter can delay finalization, never flip heal_decision; refuted findings logged not fixed | rule | prose | - | GAP |
| SV-267 | commands/supervisor.md | q: `--no-multi-voter-heal` | `--no-multi-voter-heal` | suppress multi-voter; wins over --multi-voter-heal | deterministic | prose | - | GAP |
| SV-268 | commands/supervisor.md | q: `--voter-provider <name>[:<model>]` | `--voter-provider` set with --multi-voter-heal | shell out to lens-run.sh instead of red-team-reviewer Task; flag wins over config | deterministic | prose | - | GAP |
| SV-269 | commands/supervisor.md | q: Both experimental flags (`--sdk-runner`, `--multi-voter-heal`) are | `--sdk-runner` / `--multi-voter-heal` | supervisor-only; never forwarded by /autonomous or /automate (forward set is four flags) | rule | prose | - | GAP |
| SV-270 | commands/supervisor.md | q: Branch creation is **idempotent** | ACQUIRE finds a same-named branch | reuse only when tip == base tip; else acquire_branch_collision | deterministic | prose | - | GAP |
| SV-271 | commands/supervisor.md | q: CLEAR proceeds silently. | Phase 1.5 classification | CLEAR silent; OVERLAP/SUPERSEDED ask or fail closed; gh/fetch failure ⇒ unverified, continue | deterministic | prose | - | GAP |
| SV-272 | commands/supervisor.md | q: Supervisor spawns a fix task that addresses them | Phase 4.5 review finds new issues at/above the fix floor | spawn fix task, push; retry up to --heal-iterations; PASS ⇒ completed; NEEDS_HUMAN/max ⇒ completed_with_escalation + PR comment | deterministic | prose | - | GAP |
| SV-273 | commands/supervisor.md | q: auto-dispatches a detached until-mergeable review drain | completion tail with a fresh PR | auto-dispatch detached until-mergeable drain; fire-and-forget, exit 0, never merges or waits on a human | deterministic | prose | script:dispatch-pr-review.sh | test-dispatch-pr-review.sh |
| SV-274 | commands/supervisor.md | q: that workaround is retired now that the drain is working-tree-isolated | drain overlaps inline Phase 4.5 | harmless (own worktree); do NOT write auto_review false as a race workaround | rule | prose | - | GAP |
| SV-275 | commands/supervisor.md | q: branch-dependent work must wait for the drain | branch-dependent downstream work (stacked iteration, human merge) | should wait for the drain to reach READY/ESCALATED | judgment | prose | - | GAP |
| SV-276 | commands/supervisor.md | q: NEVER record `until_mergeable_dispatched: false` because you skipped | recording until_mergeable_dispatched on the inline path | resolve from the on-disk dispatch marker (exact URL match), never from control flow | rule | prose | - | GAP |
| SV-277 | commands/supervisor.md | q: A marker exists IFF the dispatcher ran for this PR | dispatch marker found / not found | true with log path / false only when no marker; best-effort, never gates | deterministic | prose | - | GAP |
| SV-278 | commands/supervisor.md | h: ### Inline-path canonical state writes (Phase 1 ACQUIRE + Phase 4.5 completion tail) | inline path | directives the inline path needs live in this command file (it never loads agents/supervisor.md) | rule | prose | - | GAP |
| SV-279 | commands/supervisor.md | q: block (`session_id`/`branch`/`status`/`phase`) is not written by the Supervisor on any path. | `## Session` block | never Supervisor-written on any path; derived by emit-progress-event.sh + build-state.sh | rule | prose | script:build-state.sh | test-progress-state.sh |
| SV-280 | commands/supervisor.md | q: Phase 1 ACQUIRE — `/autonomous`-only `state.json` write | inline Supervisor under /autonomous with an active state.json | at ACQUIRE set top-level current_branch and current_status "running" | deterministic | prose | - | GAP |
| SV-281 | commands/supervisor.md | q: a POSITIVE, non-terminal active status set at ACQUIRE | consumer hook reads current_status | terminal set: completed, completed_with_escalation, failed, aborted, done, paused_max_iterations | rule | prose | - | GAP |
| SV-282 | commands/supervisor.md | q: If that is ambiguous or no such session is identifiable | active session ambiguous or unidentifiable | SKIP the write; jq atomic update; any error ⇒ logged no-op; never gates | deterministic | prose | - | GAP |
| SV-283 | commands/supervisor.md | q: this `state.json` write does NOT help the direct | direct /supervisor job: path | the state.json write does not apply; the projector produces the branch | rule | prose | - | GAP |
| SV-284 | commands/supervisor.md | q: terminal status:** `.supervisor/state.md`'s terminal | Phase 4.5 completion tail | terminal status derived by build-state.sh from session_end; never flipped here; state.json not flipped | rule | prose | script:build-state.sh | test-progress-state.sh |
| SV-285 | commands/supervisor.md | h: ### Architecture | section | architecture sketch (no per-subtask reviewer) | story | prose | - | GAP |
| SV-286 | commands/supervisor.md | h: ### Parallel Execution via Git Worktree | parallel workers | each in its own worktree; branches merge sequentially into the feature branch | rule | prose | - | GAP |
| SV-287 | commands/supervisor.md | q: **Git repository:** Project must be a git repo | prerequisite | project must be a git repo | rule | prose | - | GAP |
| SV-288 | commands/supervisor.md | q: **Clean git state:** No uncommitted changes (or approve stashing) | uncommitted changes present | approve stashing or abort | judgment | prose | - | GAP |
| SV-289 | commands/supervisor.md | q: **GitHub CLI:** `gh` installed and authenticated (for PR creation) | prerequisite | gh installed and authenticated | rule | prose | - | GAP |
| SV-290 | commands/supervisor.md | q: is emitted from Phase 4.5's completion tail — one block per task | SUPERVISOR_RESULT | one per task from the Phase 4.5 tail; LOOP emits nothing; hook validates the last | rule | prose | script:validate-supervisor-result.py | test-result-validators.sh |
| SV-291 | commands/supervisor.md | q: Continue; launch newly unblocked subtasks | per-subtask deterministic gate PASS | continue; launch newly unblocked subtasks | deterministic | prose | - | GAP |
| SV-292 | commands/supervisor.md | q: Mark task completed | Phase 4.5 reviewer PASS | mark task completed | deterministic | prose | - | GAP |
| SV-293 | commands/supervisor.md | q: **FAIL** (< `--heal-iterations`) | Phase 4.5 FAIL below --heal-iterations | spawn fix worker with retry context | deterministic | prose | - | GAP |
| SV-294 | commands/supervisor.md | q: **FAIL** (max iterations) | Phase 4.5 FAIL at max iterations | checkpoint, escalate to human | deterministic | prose | - | GAP |
| SV-295 | commands/supervisor.md | q: **NEEDS_HUMAN** | Phase 4.5 NEEDS_HUMAN | checkpoint, pause, exit with resume command | deterministic | prose | - | GAP |
| SV-296 | commands/supervisor.md | q: Phase 4.5 SELF_HEAL completion tail moves here | Phase 4.5 completion tail (PASS, loop skipped or ESCALATED) | move brief to jobs/done/ with an ## Outcome block | deterministic | prose | - | GAP |
| SV-297 | commands/supervisor.md | q: Supervisor moves here on hard failure | hard failure before the completion tail | move brief to jobs/failed/ | deterministic | prose | - | GAP |
| SV-298 | commands/supervisor.md | q: The Supervisor does not checkpoint on every phase transition | phase transitions | no per-phase checkpoint; --continue reads the most recently derived state.md | rule | prose | script:build-state.sh | test-progress-state.sh |
| SV-299 | commands/supervisor.md | q: Scratchpad state (same session) | resume | scratchpad state (same session) first, then .supervisor/state.md | deterministic | prose | - | GAP |
| SV-300 | commands/supervisor.md | q: **Supervisor:** 50 tool call budget (~400 tokens context) | Supervisor | 50 tool-call budget (~400 tokens) | rule | prose | - | GAP |
| SV-301 | commands/supervisor.md | q: **Execute Manager:** 60 tool call budget (isolated context for Phase 3) | Execute Manager | 60 tool-call budget | rule | prose | - | GAP |
| SV-302 | commands/supervisor.md | q: 0-30 (60%): GREEN — normal operation | 0-30 tool calls | GREEN — normal | deterministic | prose | - | GAP |
| SV-303 | commands/supervisor.md | q: 30-40 (80%): YELLOW — aggressive compression | 30-40 tool calls | YELLOW — aggressive compression | deterministic | prose | - | GAP |
| SV-304 | commands/supervisor.md | q: 40-46 (92%): RED — force checkpoint, suggest new session | 40-46 tool calls | RED — force checkpoint, suggest new session | deterministic | prose | - | GAP |
| SV-305 | commands/supervisor.md | q: 46+: RED — checkpoint + exit with resume command | 46+ tool calls | RED — checkpoint + exit with resume | deterministic | prose | - | GAP |
| SV-306 | commands/supervisor.md | q: Path selection is by subtask count | subtask count / --sequential | 1 ⇒ Single-Agent; --sequential with > 1 ⇒ Sequential; else Parallel | deterministic | prose | - | GAP |
| SV-307 | commands/supervisor.md | h: ### Single-Agent Path (exactly 1 subtask, default below threshold) | exactly 1 subtask | Single-Agent Path | deterministic | prose | - | GAP |
| SV-308 | commands/supervisor.md | q: **No per-subtask Code Reviewer spawned** — Phase 4.5's holistic Code | Single-Agent Path | no per-subtask Code Reviewer | rule | prose | - | GAP |
| SV-309 | commands/supervisor.md | q: Deterministic gate only (`outputs_verified`/`outputs_gap` plus | Single-Agent Path | deterministic gate only; LSP diagnostics are the worker's own | rule | prose | script:verify-provides.sh | test-verify-provides.sh |
| SV-310 | commands/supervisor.md | q: Automatic, no flag needed — selected by subtask count, not by | Single-Agent selection | automatic by subtask count, not by --sequential | deterministic | prose | - | GAP |
| SV-311 | commands/supervisor.md | h: ### Sequential Path (`--sequential`, more than 1 subtask) | `--sequential` with > 1 subtask | Sequential Path | deterministic | prose | - | GAP |
| SV-312 | commands/supervisor.md | q: All subtasks execute one at a time, no git worktrees created | Sequential Path | one at a time, no worktrees | rule | prose | - | GAP |
| SV-313 | commands/supervisor.md | q: Single-Agent takes precedence at a count of 1: | `--sequential` on a single-subtask brief | Single-Agent takes precedence | deterministic | prose | - | GAP |
| SV-314 | commands/supervisor.md | h: ### Parallel Path (multi-subtask, default above threshold) | multi-subtask, no --sequential | Parallel Path | deterministic | prose | - | GAP |
| SV-315 | commands/supervisor.md | q: **No per-subtask Code Reviewer spawned** — same deterministic gate as | Parallel Path | no per-subtask Code Reviewer | rule | prose | - | GAP |
| SV-316 | commands/supervisor.md | q: Max `--max-workers` concurrent workers (default: 2) | Parallel Path | max --max-workers concurrent workers (default 2) | rule | prose | - | GAP |
| SV-317 | commands/supervisor.md | q: Subtasks with dependencies wait for predecessors | subtask has dependencies | wait for predecessors | deterministic | prose | - | GAP |
| SV-318 | commands/supervisor.md | q: Sequential merge into feature branch after completion | Parallel Path complete | sequential merge into the feature branch | rule | prose | - | GAP |
| SV-319 | commands/supervisor.md | q: ACQUIRE (branch) | ACQUIRE (branch) | approval needed | rule | prose | - | GAP |
| SV-320 | commands/supervisor.md | q: PRE-FLIGHT SYNC (overlap recon) | PRE-FLIGHT SYNC permission | auto on CLEAR; approval on OVERLAP/SUPERSEDED; fail-closed under --non-interactive | deterministic | prose | - | GAP |
| SV-321 | commands/supervisor.md | q: EXECUTE (implement) | EXECUTE | batch approval needed | rule | prose | - | GAP |
| SV-322 | commands/supervisor.md | q: FINALIZE (commit+PR) | FINALIZE (commit+PR) | approval needed | rule | prose | - | GAP |
| SV-323 | commands/supervisor.md | q: Review FAIL (3x) | review FAIL 3x | checkpoint, escalate to human | deterministic | prose | - | GAP |
| SV-324 | commands/supervisor.md | q: Checkpoint, pause, exit with resume \| | NEEDS_HUMAN | checkpoint, pause, exit with resume | deterministic | prose | - | GAP |
| SV-325 | commands/supervisor.md | q: STOP, report files, exit with resume | merge conflict | STOP, report files, exit with resume | deterministic | prose | - | GAP |
| SV-326 | commands/supervisor.md | q: No ready tasks | no ready tasks | exit gracefully | deterministic | prose | - | GAP |
| SV-327 | commands/supervisor.md | q: Tool budget exceeded | tool budget exceeded | checkpoint, exit with resume | deterministic | prose | - | GAP |
| SV-328 | commands/supervisor.md | q: Worker crash | worker crash | retry once, then escalate | deterministic | prose | - | GAP |
| SV-329 | commands/supervisor.md | q: Worktree fails | worktree creation fails | fall back to sequential mode | deterministic | prose | - | GAP |
| SV-330 | commands/supervisor.md | q: Never force-resolve merge conflicts | merge conflict | never force-resolve; always STOP and escalate (inline mirror of shared prefix) | rule | prose | - | GAP |
| SV-331 | commands/supervisor.md | q: **Planning context freed** for execution (Supervisor skips Phases 0-2 | job: brief run | Supervisor skips Phases 0-2 planning (pre-answered by the brief) | rule | prose | - | GAP |
| SV-332 | commands/supervisor.md | q: **When to use Plan-First:** | complex task (>3 subtasks), plan review wanted, unfamiliar code | use /launch-pad first | judgment | prose | - | GAP |
| SV-333 | commands/supervisor.md | q: Provide task description directly with `task:` parameter | "No tasks provided" | provide task: or describe interactively | judgment | prose | - | GAP |
| SV-334 | commands/supervisor.md | q: Commit or stash changes before running Supervisor | "Dirty working tree" | commit or stash; Supervisor warns and asks | judgment | prose | - | GAP |
| SV-335 | commands/supervisor.md | q: Supervisor exits with a resume command; `.supervisor/state.md` reflects | "Context limit reached" | exit with resume; state.md reflects the last projection | rule | prose | - | GAP |
| SV-336 | commands/supervisor.md | q: failed the fail-closed **resume validation gate** | resume_state_invalid | missing Session block, phase/status outside the closed enums, or asserted branch gone | deterministic | prose | - | GAP |
| SV-337 | commands/supervisor.md | q: Recover: inspect `.supervisor/state.md` and fix the offending field, or | recovering from resume_state_invalid | fix the field or delete the state file; deliberately no override flag | rule | prose | - | GAP |
| SV-338 | commands/supervisor.md | q: The Supervisor never silently falls back to a fresh start on an invalid | state file invalid / missing | never silently start fresh on invalid; missing still starts fresh | rule | prose | - | GAP |
| SV-339 | commands/supervisor.md | q: Distinct from `resume_state_invalid`, and the recovery is the | state schema-valid but behind committed subtask:/merge: commits | refuse resume_state_stale | deterministic | prose | script:reconcile-resume-state.sh | test-reconcile-resume-state.sh |
| SV-340 | commands/supervisor.md | q: Recover: **do NOT delete the state file** (that is the `invalid` remedy | recovering from resume_state_stale | do NOT delete the state file; fix the stale_subtask rows then --continue | rule | prose | - | GAP |
| SV-341 | commands/supervisor.md | q: `VERDICT: UNKNOWN` (ground truth unreadable — no git, unresolvable | ground truth unreadable (VERDICT: UNKNOWN) | refuse (fail closed) | deterministic | prose | script:reconcile-resume-state.sh | test-reconcile-resume-state.sh |
| SV-342 | commands/supervisor.md | q: Real incident it exists to prevent (2026-07-27): all 5 subtasks merged | 2026-07-27 incident | all subtasks merged while state.md read ACQUIRE / PENDING | story | prose | - | GAP |
| SV-343 | commands/supervisor.md | q: Fix the issue manually | NEEDS_HUMAN escalation | fix manually, then /supervisor --continue | judgment | prose | - | GAP |
| SV-344 | commands/supervisor.md | q: Resolve manually in the feature branch | merge conflict in FINALIZE | resolve manually in the feature branch, then --continue | judgment | prose | - | GAP |
| SV-345 | commands/supervisor.md | q: Supervisor automatically falls back to sequential mode | worktree creation failed | automatically fall back to sequential mode | deterministic | prose | - | GAP |
| SV-346 | skills/self-heal-advisory/SKILL.md | q: **Part 1 (below)** — the **advisory-only machinery**: pre-review | Part 1 machinery | advisory only; never changes heal_decision or blocks the PR | rule | prose | - | GAP |
| SV-347 | skills/self-heal-advisory/SKILL.md | q: **Part 2 (bottom of this file)** — the **Phase 4.5 SELF_HEAL loop | Part 2 | the Phase 4.5 loop protocol, moved verbatim from agents/supervisor.md | rule | prose | - | GAP |
| SV-348 | skills/self-heal-advisory/SKILL.md | q: for the STANDALONE review→fix→re-review machinery | standalone /review-pr loop | authority stays skills/review-heal; Part 2 is the Supervisor-embedded instance | rule | prose | - | GAP |
| SV-349 | skills/self-heal-advisory/SKILL.md | q: nothing in Part 1 ever | any Part 1 step fails or budget is YELLOW/RED | non-fatal: record_decision and continue; Part 1 skips first, gates still run | rule | prose | - | GAP |
| SV-350 | skills/self-heal-advisory/SKILL.md | q: the Supervisor reads it ONCE at Phase 4.5 | Phase 4.5 entry | read this skill once; never preloaded | rule | prose | - | GAP |
| SV-351 | skills/self-heal-advisory/SKILL.md | q: is advisory input to the REVIEW lens ONLY.** | prior_churn | advisory to the reviewer only; never to fixers; never gates; reader always exits 0 | rule | prose | script:read-postmortem.sh | test-read-postmortem.sh |
| SV-352 | skills/self-heal-advisory/SKILL.md | q: emits **EMPTY output on a NO-HIT** | read-postmortem.sh output empty (no hit / no corpus / no jq) | omit the enrichment; never thread a no-prior-churn sentinel | deterministic | prose | script:read-postmortem.sh | test-read-postmortem.sh |
| SV-353 | skills/self-heal-advisory/SKILL.md | q: if touched is non-empty: | touched paths non-empty | call read-postmortem.sh with paths as ARGS, never stdin | deterministic | prose | script:read-postmortem.sh | test-read-postmortem.sh |
| SV-354 | skills/self-heal-advisory/SKILL.md | q: is advisory input to the REVIEW lens ONLY.** | house_rules | advisory to the reviewer only; subordinate to CLAUDE.md; check is DATA, never executed | rule | prose | script:read-rules.sh | test-rules-seams.sh |
| SV-355 | skills/self-heal-advisory/SKILL.md | q: reader emits **EMPTY output on no valid rule** | read-rules.sh output empty | omit the enrichment; never a no-rules sentinel | deterministic | prose | script:read-rules.sh | test-read-rules.sh |
| SV-356 | skills/self-heal-advisory/SKILL.md | q: NEVER pipe the paths on stdin. read-rules.sh self-gates | calling read-rules.sh | call unconditionally with touched paths as args and --with-ids; never stdin | rule | prose | script:read-rules.sh | test-read-rules.sh |
| SV-357 | skills/self-heal-advisory/SKILL.md | q: Everything ambiguous fails OPEN | applies_to malformed or empty path set | fail OPEN: emit the rule repo-wide | deterministic | prose | script:read-rules.sh | test-read-rules.sh |
| SV-358 | skills/self-heal-advisory/SKILL.md | q: pasted VERBATIM, every rule the | threading house_rules into the reviewer prompt | paste VERBATIM, every rule; a paraphrase or subset drops rules (#431) | rule | prose | - | test-rules-seams.sh |
| SV-359 | skills/self-heal-advisory/SKILL.md | h: ### House-rule verdicts line (report line ONLY — #431/#432) | reviewer returned house_rule_verdicts | project into ONE house_rules line (followed/violated/conflicts/not_applicable) | deterministic | prose | - | GAP |
| SV-360 | skills/self-heal-advisory/SKILL.md | q: if given == []:      "house_rules: none applicable" | no rule ids given | house_rules: none applicable | deterministic | prose | - | GAP |
| SV-361 | skills/self-heal-advisory/SKILL.md | q: the reviewer gave no verdicts — UNVERIFIED, never clean | ids given but no verdicts | house_rules: unanswered N (UNVERIFIED, never clean) | deterministic | prose | - | GAP |
| SV-362 | skills/self-heal-advisory/SKILL.md | q: when some given id has no entry (and verdicts != []) | some given id has no verdict entry | append ; unanswered <ids> | deterministic | prose | - | GAP |
| SV-363 | skills/self-heal-advisory/SKILL.md | q: ADVISORY — the line never gates. | house-rule verdict violated / conflicts_with_requirement | never gates, never a fix iteration; only the stamped-check replay gates must rules | rule | prose | - | GAP |
| SV-364 | skills/self-heal-advisory/SKILL.md | q: is advisory input to the REVIEW lens ONLY.** | brief_conformance | advisory input; its findings are ordinary category:new HIGH findings through the existing gate (R2); fixers never see the brief | rule | prose | - | test-brief-conformance-seam.sh |
| SV-365 | skills/self-heal-advisory/SKILL.md | q: no `brief_path` (or the file at brief_path is unreadable) | no brief_path / unreadable / no ## Acceptance Criteria / zero bullets | brief_conformance empty, silently; record_decision still runs | deterministic | prose | - | test-brief-conformance-seam.sh |
| SV-366 | skills/self-heal-advisory/SKILL.md | q: brief_conformance carries at most 25 bullets total | more than the cap of criteria + rubric bullets | keep 25 bullets, criteria first; append (+N bullets omitted — see brief) | deterministic | prose | - | test-brief-conformance-seam.sh |
| SV-367 | skills/self-heal-advisory/SKILL.md | q: which is why a | criterion runtime-only or PR-body-only | reviewer reports cannot_determine with a reason; never a finding | judgment | prose | - | GAP |
| SV-368 | skills/self-heal-advisory/SKILL.md | q: Rubric bullets are orientation only | rubric bullets in brief_conformance | orientation only; never produce findings; /review-pr drain untouched | rule | prose | - | GAP |
| SV-369 | skills/self-heal-advisory/SKILL.md | q: also runs again on | deviations advisory | recompute on EVERY loop iteration (fixer entries arrive per iteration) | deterministic | prose | - | test-deviations-advisory-seam.sh |
| SV-370 | skills/self-heal-advisory/SKILL.md | q: is advisory input to the REVIEW lens ONLY.** | deviations_advisory | reviewer only; findings only when a deviation contradicts a stated criterion/rubric bullet; merely unexpected is NOT a finding | rule | prose | - | test-deviations-advisory-seam.sh |
| SV-371 | skills/self-heal-advisory/SKILL.md | q: a per-run, in-memory list maintained by the review-and-fix loop | fixer FIX_RESULT.deviations | append to fixer_deviations prefixed fix-<n> and record_decision each append (survives compaction) | rule | prose | - | test-deviations-advisory-seam.sh |
| SV-372 | skills/self-heal-advisory/SKILL.md | q: no `state.md` (no state file for this run yet) | no state.md / no ## Worker Results / zero entries | deviations_advisory empty, silently | deterministic | prose | - | test-deviations-advisory-seam.sh |
| SV-373 | skills/self-heal-advisory/SKILL.md | q: CAP: the SAME cap Part 1's brief-conformance advisory uses | deviation entries exceed the cap | truncate with a VISIBLE (+N deviations omitted) marker | deterministic | prose | - | test-deviations-advisory-seam.sh |
| SV-374 | skills/self-heal-advisory/SKILL.md | q: Run the checks in this section after the Code Reviewer loop has completed | post-review checks | run after the loop regardless of heal_decision; rules-check replay runs per iteration; rules audit once | rule | prose | - | GAP |
| SV-375 | skills/self-heal-advisory/SKILL.md | h: ### Contract-conformance check (READ path — runs after the Code Reviewer pass) | after the Code Reviewer loop (any heal_decision) | check the integrated diff against stored System Contracts for touched subsystems | deterministic | prose | script:read-system-contract.sh | test-system-contract.sh |
| SV-376 | skills/self-heal-advisory/SKILL.md | q: this check NEVER changes a gate.** Exactly like the Rubric Grader | contract-conformance findings | advisory only; never change heal_decision, trigger a fix or block the PR; severity info/advisory only | rule | prose | - | GAP |
| SV-377 | skills/self-heal-advisory/SKILL.md | q: twin_store_status = bash ${CLAUDE_PLUGIN_ROOT}/scripts/read-system-contract.sh | store-health probe | read twin_store_status whole-store AND per touched --subsystem; union them; unreadable reader ⇒ treated as not dark | deterministic | prose | script:read-system-contract.sh | test-system-contract.sh |
| SV-378 | skills/self-heal-advisory/SKILL.md | q: if that output's `twin_store_status:` is `dark`: | a touched subsystem read prints dark | touched_contract_withheld = true | deterministic | prose | script:read-system-contract.sh | test-system-contract.sh |
| SV-379 | skills/self-heal-advisory/SKILL.md | q: if twin_store_status == "dark" or touched_contract_withheld: | store dark OR a touched contract withheld | status advisory_violations if violations ≥1 else unverified — never pass/skipped; evaluated FIRST | deterministic | prose | - | GAP |
| SV-380 | skills/self-heal-advisory/SKILL.md | q: elif not contract_conformance.checked: | nothing checked and nothing withheld | status skipped (unverified if tooling unavailable) | deterministic | prose | - | GAP |
| SV-381 | skills/self-heal-advisory/SKILL.md | q: elif contract_conformance.violations == 0: | checked with 0 / ≥1 violations | pass / advisory_violations | deterministic | prose | - | GAP |
| SV-382 | skills/self-heal-advisory/SKILL.md | q: record_decision(phase: SELF_HEAL, decision: "contract_conformance: {status} | withheld contract ids | named in the decision line, never counted as violations | rule | prose | - | GAP |
| SV-383 | skills/self-heal-advisory/SKILL.md | q: Absent contracts (empty `.supervisor/twin/`, or | absent contracts or reader emits nothing | checked false, status skipped (unverified if tooling missing), 0/0; never an error or fix | deterministic | prose | - | GAP |
| SV-384 | skills/self-heal-advisory/SKILL.md | q: **A WITHHELD contract is not an absent one.** Record `status: | whole-store or touched-id probe prints dark | unverified, not skipped; surface the !! repair block; never cat contract files to work around | rule | prose | script:read-system-contract.sh | test-system-contract.sh |
| SV-385 | skills/self-heal-advisory/SKILL.md | q: `status: pass` requires `violations: 0`; `status: advisory_violations` | status pass / advisory_violations | requires violations 0 / ≥1 with non-empty findings | deterministic | prose | - | GAP |
| SV-386 | skills/self-heal-advisory/SKILL.md | q: This is a READ of the twin store via `read-system-contract.sh` only — | contract-conformance | READ only via read-system-contract.sh; never writes the twin store | rule | prose | - | GAP |
| SV-387 | skills/self-heal-advisory/SKILL.md | q: It runs on EVERY Phase 4.5 (PASS or ESCALATED); unlike the Rubric Grader | every Phase 4.5 (PASS or ESCALATED) | run conformance; not gated on PASS | rule | prose | - | GAP |
| SV-388 | skills/self-heal-advisory/SKILL.md | h: ### Benchmark run (populates `benchmark_result`) | Phase 4.5 post-review | run run-benchmark.sh; parse BENCHMARK_JSON; parse miss ⇒ ran false, unverified | deterministic | prose | script:run-benchmark.sh | test-benchmark.sh |
| SV-389 | skills/self-heal-advisory/SKILL.md | q: does not update its baseline on a plain run | benchmark baseline | Phase 4.5 never passes --update-baseline (measure, never move the baseline) | rule | prose | script:run-benchmark.sh | test-benchmark.sh |
| SV-390 | skills/self-heal-advisory/SKILL.md | h: ### Ground-truth execution (M2b slice 1a — runs after the Code Reviewer pass) | after the Code Reviewer loop (any heal_decision) | run declared executable acceptance checks; produce ground_truth | deterministic | prose | script:run-ground-truth.sh | test-run-ground-truth.sh |
| SV-391 | skills/self-heal-advisory/SKILL.md | q: the ground-truth execution is **advisory only** | ground-truth result | advisory only; never changes heal_decision or blocks the PR; runner always exits 0 | rule | prose | - | GAP |
| SV-392 | skills/self-heal-advisory/SKILL.md | q: --brief-sourced `cmd:`/bare bullet executes ONLY when the brief's | --brief cmd:/bare bullet without a matching ## Configuration stamp | not executed; unverified, reason cmd_unapproved | deterministic | prose | script:run-ground-truth.sh | test-run-ground-truth.sh |
| SV-393 | skills/self-heal-advisory/SKILL.md | q: NO_CMD_FLAG = (NON_INTERACTIVE == true) ? "--no-cmd" : "" | NON_INTERACTIVE true | pass --no-cmd: cmd:/bare checks skipped (cmd_disabled) | deterministic | prose | script:run-ground-truth.sh | test-run-ground-truth.sh |
| SV-394 | skills/self-heal-advisory/SKILL.md | q: Parse the single `GROUND_TRUTH_JSON: {...}` line. A parse miss | GROUND_TRUTH_JSON parse miss | checked false, status unverified | deterministic | prose | - | GAP |
| SV-395 | skills/self-heal-advisory/SKILL.md | q: for c in gt.per_check where c.status == "fail": | a per_check entry failed | add advisory finding (never blocking/high) | deterministic | prose | - | GAP |
| SV-396 | skills/self-heal-advisory/SKILL.md | q: The runner resolves checks from the brief's optional `## Executable | no Executable Acceptance section and no ground-truth.json | checked false, skipped, 0/0; never an error | deterministic | prose | script:run-ground-truth.sh | test-run-ground-truth.sh |
| SV-397 | skills/self-heal-advisory/SKILL.md | q: `status: pass` requires zero failing checks (and ≥1 check executed); | ground-truth status | pass needs 0 failing and ≥1 executed; advisory_failures ≥1 failing; unverified on tooling failure / only deferred checks | deterministic | prose | script:run-ground-truth.sh | test-run-ground-truth.sh |
| SV-398 | skills/self-heal-advisory/SKILL.md | q: `qa-executor:` checks are recognized but DEFERRED to M2b slice 1b — | qa-executor: checks / cmd: bullets | qa-executor deferred (unverified, never blocks pass); cmd: runs bash -c with full privileges — trust-sensitive | rule | prose | script:run-ground-truth.sh | test-run-ground-truth.sh |
| SV-399 | skills/self-heal-advisory/SKILL.md | h: ### Rules-check replay (executable-rule-candidates/01; the rules gate replay since automate-followups/07) | stamped FAILING check of a gate-countable must rule | correctness gate: one BLOCKING finding per countable failing id enters the loop | deterministic | prose | script:rules-gate-verdict.sh | test-rules-gate-verdict.sh |
| SV-400 | skills/self-heal-advisory/SKILL.md | q: if $NO_CMD_FLAG is non-empty: export RULES_CHECK_NO_CMD=1 | $NO_CMD_FLAG non-empty | export RULES_CHECK_NO_CMD=1 (same valve as ground truth) | deterministic | prose | script:rules-gate-verdict.sh | test-rules-gate-verdict.sh |
| SV-401 | skills/self-heal-advisory/SKILL.md | q: out.stdout parses as ONE JSON object whose `verdict` is a STRING in | helper output not exit 0 + one JSON object with an allow-listed verdict string | normalise to verdict unreadable (⇒ Part 2 escalates) | deterministic | prose | - | test-rules-gate-seams.sh |
| SV-402 | skills/self-heal-advisory/SKILL.md | q: if rules.verdict == "unreadable":       "rules_check: unreadable" | rules verdict | project rules_check_line (unreadable / unresolved / unstamped / cmd_disabled / passed n/m / none) — first match wins | deterministic | prose | - | GAP |
| SV-403 | skills/self-heal-advisory/SKILL.md | q: rules_check_line += "; rules_advisory: {id} ({reason})" | advisory (non-countable) ids present | append ; rules_advisory: <id> (<reason>) per id | deterministic | prose | - | GAP |
| SV-404 | skills/self-heal-advisory/SKILL.md | q: **The verdict decides; the line reports.** Only `rules.verdict` feeds | verdict fail / passable / unresolved-unreadable | BLOCKING finding / nothing / escalate rules_gate_unresolved (fail closed) | deterministic | prose | script:rules-gate-verdict.sh | test-closed-enum-pins-seam.sh |
| SV-405 | skills/self-heal-advisory/SKILL.md | q: The one exception — a remembered fail | unstamped while rules_failed_seen is non-empty | escalate rules_fail_then_unstamped instead of passing | deterministic | prose | - | test-rules-gate-seams.sh |
| SV-406 | skills/self-heal-advisory/SKILL.md | q: Honest limit: `cmd_disabled` after a `fail` has the same no-replay shape | cmd_disabled after a fail | stays passable — honest limit | rule | prose | - | GAP |
| SV-407 | skills/self-heal-advisory/SKILL.md | q: **Line states:** `passed n/m` (a countable pass, or an advisory-only | rules_check line states | enumerated meanings of passed / unstamped / cmd_disabled / none / unresolved / unreadable | rule | prose | - | GAP |
| SV-408 | skills/self-heal-advisory/SKILL.md | q: **One line, one place:** `rules_check_line` is surfaced in the Phase 4.5 | rules_check_line | prose report only, in the Phase 4.5 report; gating travels via findings; no PR-body writer | rule | prose | - | GAP |
| SV-409 | skills/self-heal-advisory/SKILL.md | q: **The helper always exits 0** — a verdict, including `unreadable`, is | rules-gate-verdict.sh | always exits 0; the consumer decides | rule | prose | script:rules-gate-verdict.sh | test-rules-gate-verdict.sh |
| SV-410 | skills/self-heal-advisory/SKILL.md | q: **Never a second review pass.** It reads no diff and asks no question | rules replay | never a second review pass; once per iteration because a fix can change it | rule | prose | - | GAP |
| SV-411 | skills/self-heal-advisory/SKILL.md | h: ### Rules-store audit (automate-followups/09 — advisory, NEVER gates) | once per Phase 4.5 run | run rules-audit-line.sh; executes nothing | deterministic | prose | script:rules-audit-line.sh | test-rules-audit-line.sh |
| SV-412 | skills/self-heal-advisory/SKILL.md | q: the rules-store audit is **advisory only** | rules-store audit result | advisory only; never gates, escalates or enters findings | rule | prose | - | GAP |
| SV-413 | skills/self-heal-advisory/SKILL.md | q: an absent/garbled helper never reads as clean | helper absent or first line not rules_audit: | rules_audit: unexamined (never reads as clean) | deterministic | prose | script:rules-audit-line.sh | test-rules-audit-line.sh |
| SV-414 | skills/self-heal-advisory/SKILL.md | q: `rules_audit: clean` — the engine examined the store and found no | engine found no BLOCKING finding (or no store) | rules_audit: clean; nothing changes | deterministic | prose | script:rules-audit-line.sh | test-rules-audit-line.sh |
| SV-415 | skills/self-heal-advisory/SKILL.md | q: `rules_audit: findings <n> (<kinds>)` — the engine reported `<n>` | engine reported n BLOCKING store findings | rules_audit: findings n (kinds); NOT synthesized or escalated | deterministic | prose | script:rules-audit-line.sh | test-rules-audit-line.sh |
| SV-416 | skills/self-heal-advisory/SKILL.md | q: `rules_audit: unexamined` — the engine could not examine the store | engine could not examine the store | rules_audit: unexamined; never clean | deterministic | prose | script:rules-audit-line.sh | test-rules-audit-line.sh |
| SV-417 | skills/self-heal-advisory/SKILL.md | q: `rules_gate_trigger: …` (optional second line, any state) — the | must rule with check exists while parked proposed/automate-followups-08 exists | emit rules_gate_trigger line; promotion stays human | deterministic | prose | script:rules-audit-line.sh | test-rules-audit-line.sh |
| SV-418 | skills/self-heal-advisory/SKILL.md | h: ### Contract builder (WRITE path — completion tail only) | completion tail | run the contract builder (WRITE path) | deterministic | prose | script:write-system-contract.sh | test-system-contract.sh |
| SV-419 | skills/self-heal-advisory/SKILL.md | q: On the ESCALATED / base-mismatch / invariant-violation paths, SKIP the builder | heal_decision PASS or loop skipped | run builder; ESCALATED / base-mismatch / invariant-violation ⇒ SKIP | deterministic | prose | - | GAP |
| SV-420 | skills/self-heal-advisory/SKILL.md | q: compute a per-subsystem incident map for THIS run | before spawning the builder | compute this-run incident_map from conformance findings and fix-iteration files | deterministic | prose | - | GAP |
| SV-421 | skills/self-heal-advisory/SKILL.md | q: has **no incident this run** | subsystem absent from incident_map | add no entry; carry prior incident_history unchanged (never fabricate, never backfill) | rule | prose | - | GAP |
| SV-422 | skills/self-heal-advisory/SKILL.md | q: Spawn an **ephemeral, Bash-capable builder Task** | contract builder | ephemeral general-purpose Task (Read/Bash/Glob/Grep), not a permanent agent, not Context-Keeper | rule | prose | - | GAP |
| SV-423 | skills/self-heal-advisory/SKILL.md | q: DEDUPE: do not add an entry identical in kind+summary+source | incident entry identical in kind+summary+source | dedupe; keep the most recent 5 (append at end, drop from front) | deterministic | prose | - | GAP |
| SV-424 | skills/self-heal-advisory/SKILL.md | q: Omit the `incident_history:` key entirely when the merged list is empty. | merged incident list empty | omit the incident_history: key | deterministic | prose | - | GAP |
| SV-425 | skills/self-heal-advisory/SKILL.md | q: It REFUSES (exit 3) from a linked | write-system-contract.sh run from a linked worktree | refuses (exit 3); run only from the repo-root CWD | deterministic | prose | script:write-system-contract.sh | test-system-contract.sh |
| SV-426 | skills/self-heal-advisory/SKILL.md | q: **Context-Keeper is explicitly OUT of this path.** It writes only `## | twin store writes | Context-Keeper is out of the path; write-system-contract.sh is the sole writer | rule | prose | script:write-system-contract.sh | test-system-contract.sh |
| SV-427 | skills/self-heal-advisory/SKILL.md | q: **Pinned repo-root CWD, never a worktree.** `write-system-contract.sh` | builder CWD | pinned repo root, never a worktree | rule | prose | script:write-system-contract.sh | test-system-contract.sh |
| SV-428 | skills/self-heal-advisory/SKILL.md | q: **Failure is non-fatal.** Any writer non-zero exit, missing-sha-tool | writer non-zero / no sha tool / builder crash | log twin_builder decision and proceed; never changes heal_decision | deterministic | prose | - | GAP |
| SV-429 | skills/self-heal-advisory/SKILL.md | h: ### Advisory Twin delta line (informational ONLY) | Phase 4.5 report | echo format-twin-delta.sh line; no signal ⇒ Twin: no signal this run; never gates | deterministic | prose | script:format-twin-delta.sh | test-format-twin-delta.sh |
| SV-430 | skills/self-heal-advisory/SKILL.md | h: ### Hard-signal dual emission (ST3 — written in BOTH shapes) | hard-signal emission | same data in two shapes: nested on SUPERVISOR_RESULT and flat on session_end | rule | prose | - | test-insights.sh |
| SV-431 | skills/self-heal-advisory/SKILL.md | q: **FLAT scalar fields on the `session_end` JSONL event** in | flat session_end field names | hard contract with build-insights.sh — never rename | rule | prose | - | test-insights.sh |
| SV-432 | skills/self-heal-advisory/SKILL.md | q: FLAT ONLY: never a key of the nested `ground_truth` | ground_truth pass_rate | FLAT ONLY (ground_truth_pass_rate); never a nested key | rule | prose | - | GAP |
| SV-433 | skills/self-heal-advisory/SKILL.md | q: sidecar-check` fails any other key set | nested hard-signal objects | exact key sets; /automate sidecar-check fails any other key set | deterministic | prose | script:automate-helpers.sh sidecar-check | test-automate-trail.sh |
| SV-434 | skills/self-heal-advisory/SKILL.md | q: `ground_truth: {checked: <bool>, status: <s>, checks_total: <n>, | ground_truth nested object | checked ALWAYS present, including on status pass | rule | prose | script:automate-helpers.sh sidecar-check | test-automate-trail.sh |
| SV-435 | skills/self-heal-advisory/SKILL.md | q: `benchmark_result: {ran, status, name, metric, value, baseline, delta, | benchmark parse miss | benchmark_result {ran: false, status: unverified} | deterministic | prose | - | GAP |
| SV-436 | skills/self-heal-advisory/SKILL.md | q: **Skip form** (nothing to check): `ground_truth: {checked: false, | nothing to check | skip form {checked: false, status: skipped}; counts may be 0/[] or omitted | rule | prose | - | GAP |
| SV-437 | skills/self-heal-advisory/SKILL.md | q: **Findings-per-item fields (iq02 IQ01, additive, same value in both | heal_first_decision / heal_new_findings | report-only, both shapes, null when heal_loop_ran false; never read by the loop | rule | prose | script:validate-supervisor-result.py | test-result-validators.sh |
| SV-438 | skills/self-heal-advisory/SKILL.md | q: The flat fields are additive — a `session_end` event without them remains valid | session_end without flat fields | still valid; absent ⇒ not reported (ground_truth_* absent ⇒ skipped) | rule | prose | - | GAP |
| SV-439 | skills/self-heal-advisory/SKILL.md | q: this Part is the Supervisor Phase 4.5 | Part 2 provenance | moved verbatim; step numbering preserved so cross-file step references stay valid | rule | prose | - | GAP |
| SV-440 | skills/self-heal-advisory/SKILL.md | q: short-circuits the review-and-fix LOOP only | Phase 4.5 entry | phase ALWAYS runs after FINALIZE; --skip-self-heal skips the loop only | rule | prose | - | GAP |
| SV-441 | skills/self-heal-advisory/SKILL.md | q: Progress state (session phase) is not written here — it is derived by | Phase 4.5 on-entry | progress state not written here (derived) | rule | prose | script:build-state.sh | test-progress-state.sh |
| SV-442 | skills/self-heal-advisory/SKILL.md | q: Confirm the protocol read: | on-entry 1a | confirm the protocol Read of this skill | rule | prose | - | GAP |
| SV-443 | skills/self-heal-advisory/SKILL.md | q: Steps 1b (graph brain consult) and 1d | steps 1b/1d | retired with the graphify tier; letters kept for cross-references | story | prose | - | GAP |
| SV-444 | skills/self-heal-advisory/SKILL.md | q: **Prior-churn advisory (pre-review enrichment — ADVISORY ONLY, | on-entry 1c | compute prior_churn via read-postmortem.sh with args; empty ⇒ skip silently | deterministic | prose | script:read-postmortem.sh | test-read-postmortem.sh |
| SV-445 | skills/self-heal-advisory/SKILL.md | q: **House-rules advisory (committed convention enrichment — pre-review | on-entry 1e | compute house_rules via read-rules.sh --with-ids, UNCONDITIONALLY, kept verbatim; empty ⇒ skip | deterministic | prose | script:read-rules.sh | test-rules-seams.sh |
| SV-446 | skills/self-heal-advisory/SKILL.md | q: **Brief-conformance advisory (acceptance-criteria enrichment — | on-entry 1f | compute brief_conformance; three skip conditions ⇒ empty; reviewer answers with ordinary new/HIGH findings | deterministic | prose | - | test-brief-conformance-seam.sh |
| SV-447 | skills/self-heal-advisory/SKILL.md | q: **Deviations advisory (worker- and fixer-recorded plan drift — | on-entry 1g | compute deviations_advisory on EVERY iteration; three skip conditions ⇒ empty | deterministic | prose | - | test-deviations-advisory-seam.sh |
| SV-448 | skills/self-heal-advisory/SKILL.md | q: `skip_self_heal_requested` — set from INIT-parsed flags (true iff | skip_self_heal_requested | set once from INIT flags, never mutated | rule | prose | - | GAP |
| SV-449 | skills/self-heal-advisory/SKILL.md | q: `phase45_review_invoked` — initialize to `false`. Flip to `true` only | phase45_review_invoked | init false; flip true only when the code-reviewer Task actually executes | rule | prose | - | GAP |
| SV-450 | skills/self-heal-advisory/SKILL.md | q: `red_team_advisory` — initialize to `"disabled"` HERE, BEFORE the | red_team_advisory | init "disabled" BEFORE the early-jump checks so the Outcome line always has a value | rule | prose | - | GAP |
| SV-451 | skills/self-heal-advisory/SKILL.md | q: `Context-Keeper(operation: record_self_heal_resume, increment: true)` | `--continue` run landing in SELF_HEAL | record_self_heal_resume increment: true; read count | deterministic | prose | - | GAP |
| SV-452 | skills/self-heal-advisory/SKILL.md | q: This is the ONLY place the resume counter is incremented: exactly once, | resume counter | incremented ONLY here, exactly once, at Phase 4.5 entry of a --continue run | rule | prose | - | GAP |
| SV-453 | skills/self-heal-advisory/SKILL.md | q: If count ≥ 3: abort the loop, mark task `completed_with_escalation` | resume count ≥ 3 | abort loop; completed_with_escalation, ESCALATED, error self_heal_resume_thrash; do not set phase45_review_invoked | deterministic | prose | - | GAP |
| SV-454 | skills/self-heal-advisory/SKILL.md | q: Check `--skip-self-heal` flag: if set, record `record_decision(phase: | `--skip-self-heal` set | record loop_skipped; jump to completion tail with heal_loop_ran=false | deterministic | prose | - | GAP |
| SV-455 | skills/self-heal-advisory/SKILL.md | q: If `mismatch` is non-null (Phase 4 set the flag | base_mismatch_detected flag non-null | run base-mismatch cleanup instead of the loop | deterministic | prose | - | GAP |
| SV-456 | skills/self-heal-advisory/SKILL.md | q: **Close the orphan PR best-effort** (do not abort on failure — the PR | base-mismatch cleanup | gh pr close best-effort; exit 0 ⇒ closed_by_loop, else close_attempt_failed | deterministic | prose | - | GAP |
| SV-457 | skills/self-heal-advisory/SKILL.md | q: **Move brief to `failed/`:** if `job:` parameter was used, move the | base-mismatch cleanup with job: | move brief to failed/ with an ## Outcome block (base_branch_mismatch) | deterministic | prose | - | GAP |
| SV-458 | skills/self-heal-advisory/SKILL.md | q: **Record the decision:** `record_decision(phase: SELF_HEAL, decision: | base-mismatch cleanup | record_decision base_mismatch_cleanup | rule | prose | - | GAP |
| SV-459 | skills/self-heal-advisory/SKILL.md | q: Progress state is not written here — it is derived (see the pointer in | base-mismatch exit path | no state write; state.md may stay running — known accepted gap (Risk R4) | rule | prose | - | GAP |
| SV-460 | skills/self-heal-advisory/SKILL.md | q: **Clear the flag (REQUIRED before returning, even on `gh pr close` | base-mismatch cleanup | clear base_mismatch_detected before returning, even on gh failure | rule | prose | - | GAP |
| SV-461 | skills/self-heal-advisory/SKILL.md | q: **Reset resume counter:** `Context-Keeper(operation: | base-mismatch cleanup | reset resume counter (increment: false) | rule | prose | - | GAP |
| SV-462 | skills/self-heal-advisory/SKILL.md | q: **Emit single `SUPERVISOR_RESULT` block** with: | base-mismatch cleanup | emit ONE SUPERVISOR_RESULT: failed, heal_loop_ran false, error base_branch_mismatch, pr_state | deterministic | prose | script:validate-supervisor-result.py | test-result-validators.sh |
| SV-463 | skills/self-heal-advisory/SKILL.md | q: **Return** from Phase 4.5 — do NOT run the review-and-fix loop, do NOT | base-mismatch cleanup done | return; skip the loop and the standard completion tail | rule | prose | - | GAP |
| SV-464 | skills/self-heal-advisory/SKILL.md | q: `branch_base` is the BASE_BRANCH we expected the PR to target. It is | branch_base field | expected base, so EVALUATE detects the mode without parsing error | rule | prose | - | GAP |
| SV-465 | skills/self-heal-advisory/SKILL.md | q: `pr_state` is a new optional field on `SUPERVISOR_RESULT` (v14.0.0 — | pr_state field | closed_by_loop / close_attempt_failed / absent | rule | prose | - | GAP |
| SV-466 | skills/self-heal-advisory/SKILL.md | q: On absent `gh` (`actual: null`), report `actual` as `null` in the error | gh absent (actual null) | report actual null; reason disambiguates gh_unavailable_non_interactive vs user_aborted_gh_retry | deterministic | prose | - | GAP |
| SV-467 | skills/self-heal-advisory/SKILL.md | q: Review-and-fix loop (runs only when flag is not set | flag not set, thrash guard passed, no base-mismatch | run the review-and-fix loop | deterministic | prose | - | GAP |
| SV-468 | skills/self-heal-advisory/SKILL.md | q: BLOCKING is always at the floor; an unreadable severity reads as at the floor | finding severity BLOCKING or unreadable | always at the floor (never a silent pass); one fix-floor.sh split per iteration | deterministic | prose | script:fix-floor.sh split | test-fix-floor.sh |
| SV-469 | skills/self-heal-advisory/SKILL.md | q: while heal_iterations < max_heal_iterations: | heal_iterations < max_heal_iterations | run another review-and-fix iteration | deterministic | prose | - | GAP |
| SV-470 | skills/self-heal-advisory/SKILL.md | q: pin_out = Bash(`bash "<plugin root>/scripts/run-pin-mutations.sh" {brief_path} | each iteration, before the reviewer spawn | run run-pin-mutations.sh (cached, --budget 540); verdict lines go to the reviewer as DATA | deterministic | prose | script:run-pin-mutations.sh | test-phase45-rounds-seam.sh |
| SV-471 | skills/self-heal-advisory/SKILL.md | q: Exit 0 / 1 / 2 never pauses the run and never reaches adjudication | pin run exit 0/1/2, missing script/brief, or pin-mutations: none | never pause or adjudicate; record and omit the block | deterministic | prose | - | GAP |
| SV-472 | skills/self-heal-advisory/SKILL.md | q: INCOMPLETE run (no `pin-mutations: <h> held, …` summary line | pin run incomplete (no summary line or other exit) | hand over printed lines; unprinted rows are unverified | deterministic | prose | - | test-phase45-rounds-seam.sh |
| SV-473 | skills/self-heal-advisory/SKILL.md | q: **DIFF-SCOPE OVERRIDE (v14.0.0 stacked-iteration support):** | BASE_BRANCH != main (stacked iteration) | reviewer scope = git diff $BASE_BRANCH...HEAD only; no consistency_audit auto-expand | deterministic | prose | - | GAP |
| SV-474 | skills/self-heal-advisory/SKILL.md | q: **Run `consistency_audit` mode when self-repo trigger paths match.** | BASE_BRANCH == main and diff touches consistency_audit trigger surfaces | reviewer runs review_mode consistency_audit | deterministic | prose | - | GAP |
| SV-475 | skills/self-heal-advisory/SKILL.md | q: **ALWAYS apply the Self-Heal Miss-Class Checklist regardless of repo.** | every non-stacked heal review | also apply the Self-Heal Miss-Class Checklist | rule | prose | - | GAP |
| SV-476 | skills/self-heal-advisory/SKILL.md | q: **ANTI-OVERLAP (every iteration | every iteration | do not re-report already-fixed prior findings; open prior findings stay in scope | rule | prose | - | GAP |
| SV-477 | skills/self-heal-advisory/SKILL.md | q: **EXECUTION DIRECTIVE (every iteration — Phase 4.5 only):** | every Phase 4.5 iteration | reviewer runs scratch-dir adversarial repros of load-bearing claims; working tree stays read-only | rule | prose | - | test-execution-directive-seam.sh |
| SV-478 | skills/self-heal-advisory/SKILL.md | q: **PRIOR-CHURN ADVISORY (non-gating | prior_churn non-empty | include the PRIOR-CHURN ADVISORY line, else omit | deterministic | prose | - | GAP |
| SV-479 | skills/self-heal-advisory/SKILL.md | q: **HOUSE-RULES ADVISORY (non-gating | house_rules non-empty | include HOUSE-RULES ADVISORY verbatim; reviewer answers each id; requirement-driven break ⇒ conflicts_with_requirement | deterministic | prose | - | test-rules-seams.sh |
| SV-480 | skills/self-heal-advisory/SKILL.md | q: **BRIEF-CONFORMANCE ADVISORY (include this line ONLY | brief_conformance non-empty | reviewer judges each criterion from diff text; not_addressed ⇒ one new HIGH finding (file brief sentinel); runtime / PR-body only ⇒ cannot_determine | deterministic | prose | - | test-brief-conformance-seam.sh |
| SV-481 | skills/self-heal-advisory/SKILL.md | q: **DEVIATIONS ADVISORY (include this line ONLY | deviations_advisory non-empty | one new finding per deviation contradicting a criterion/rubric bullet; rule: entries cited as house-rule failures | deterministic | prose | - | test-deviations-advisory-seam.sh |
| SV-482 | skills/self-heal-advisory/SKILL.md | q: **PIN-MUTATION VERDICTS (DATA | pin-mutation verdict lines printed | not_held ⇒ ONE BLOCKING new finding; held ⇒ nothing; reviewer mutates only unverified rows | deterministic | prose | - | test-phase45-rounds-seam.sh |
| SV-483 | skills/self-heal-advisory/SKILL.md | q: this is the FIRST and ONLY LLM review of this work | Phase 4.5 review | first and ONLY LLM review; assume no prior semantic pass | rule | prose | - | GAP |
| SV-484 | skills/self-heal-advisory/SKILL.md | q: model: "sonnet"   # ONLY when cost_profile=cheap; omit entirely when cost_profile=default | cost_profile=cheap | reviewer and fix Task get model: sonnet | deterministic | prose | - | GAP |
| SV-485 | skills/self-heal-advisory/SKILL.md | q: phase45_review_invoked = true | code-reviewer Task returned | set phase45_review_invoked = true | rule | prose | - | GAP |
| SV-486 | skills/self-heal-advisory/SKILL.md | q: if rules.verdict == "fail": | rules verdict fail | one BLOCKING rule finding (file: rule) per countable failing id; advisory ids never become findings | deterministic | prose | - | test-rules-gate-seams.sh |
| SV-487 | skills/self-heal-advisory/SKILL.md | q: if new_seen: | new countable fail ids seen | add to rules_failed_seen; record_decision so it survives resume | deterministic | prose | - | test-rules-gate-seams.sh |
| SV-488 | skills/self-heal-advisory/SKILL.md | q: ci_out = Bash(`bash "<plugin root>/scripts/phase45-ci-read.sh" | after each review | one bounded CI read of required checks on HEAD; red required check ⇒ BLOCKING ci finding; note lines / none ⇒ never a finding | deterministic | prose | script:phase45-ci-read.sh | test-phase45-ci-read.sh |
| SV-489 | skills/self-heal-advisory/SKILL.md | q: if rule_findings != [] and iter_decision == PASS: | rule_findings non-empty and reviewer PASS | iter_decision = FAIL | deterministic | prose | - | test-rules-gate-seams.sh |
| SV-490 | skills/self-heal-advisory/SKILL.md | q: if ci_findings != [] and iter_decision == PASS: | ci_findings non-empty and reviewer PASS | iter_decision = FAIL (fix round) | deterministic | prose | - | GAP |
| SV-491 | skills/self-heal-advisory/SKILL.md | q: if iter_decision == PASS and any(at_floor(i) for i in review.issues): | reviewer PASS but an at_floor finding remains | iter_decision = FAIL; the reviewer's decision is never rewritten | deterministic | prose | - | GAP |
| SV-492 | skills/self-heal-advisory/SKILL.md | q: if heal_first_decision == null: | first iteration | heal_first_decision = iter_decision; heal_new_findings sums new issues (report-only) | deterministic | prose | - | GAP |
| SV-493 | skills/self-heal-advisory/SKILL.md | q: heal_dismissed += [ | review issue not at_floor | itemise into heal_dismissed (reason = category or below_severity_floor, source code_reviewer, severity) | deterministic | prose | - | test-automate-dismissed.sh |
| SV-494 | skills/self-heal-advisory/SKILL.md | q: if rules.verdict not in RULES_PASSABLE and rules.verdict != "fail": | rules verdict neither passable nor fail | ESCALATED, rules_gate_unresolved, post PR comment, break (fail closed) | deterministic | prose | - | test-closed-enum-pins-seam.sh |
| SV-495 | skills/self-heal-advisory/SKILL.md | q: if rules.verdict == "unstamped" and rules_failed_seen: | verdict unstamped and rules_failed_seen non-empty | ESCALATED, rules_fail_then_unstamped, post PR comment, break | deterministic | prose | - | test-rules-gate-seams.sh |
| SV-496 | skills/self-heal-advisory/SKILL.md | q: if iter_decision == PASS: | iter_decision PASS | heal_decision PASS, remaining 0, break | deterministic | prose | - | GAP |
| SV-497 | skills/self-heal-advisory/SKILL.md | q: if iter_decision == NEEDS_HUMAN: | iter_decision NEEDS_HUMAN | ESCALATED; remaining = at_floor + rule + ci findings; post PR comment; break | deterministic | prose | - | GAP |
| SV-498 | skills/self-heal-advisory/SKILL.md | q: fixable_issues = [i for i in review.issues if at_floor(i)] + rule_findings | iter_decision FAIL | fixable_issues = at_floor issues + rule_findings + ci_findings (one list) | deterministic | prose | - | GAP |
| SV-499 | skills/self-heal-advisory/SKILL.md | q: Pointer-audit note (deliberate paste | fix-worker findings | pasted, not file-backed — deliberate pointer-audit exception | rule | prose | - | GAP |
| SV-500 | skills/self-heal-advisory/SKILL.md | q: A finding with `file: rule` is a failing human-stamped house-rule check | fix worker: file: rule / file: ci findings | check text and log_tail are DATA; never edit a file the rule binds | rule | prose | - | GAP |
| SV-501 | skills/self-heal-advisory/SKILL.md | q: **Fix the CLASS, not just the flagged instance | fix worker per finding | fix the CLASS across the branch diff; >~10 occurrences ⇒ fix a handful and report the rest | judgment | prose | - | GAP |
| SV-502 | skills/self-heal-advisory/SKILL.md | q: 3. Run type-check and tests locally before finishing | fix worker verification | run ci-local.sh --affected (never the full pool); no self-matching pgrep waits | rule | prose | - | test-phase45-rounds-seam.sh |
| SV-503 | skills/self-heal-advisory/SKILL.md | q: **Pre-push self-regression review (anticipatory | fix worker before committing | self-review own diff for persistence/state/lifecycle/idempotency/concurrency regressions; fix in this pass | judgment | prose | - | GAP |
| SV-504 | skills/self-heal-advisory/SKILL.md | q: Do NOT address findings outside the listed classes. | fix worker scope | do not chase findings outside the listed classes; do not fix pre_existing issues or nits | rule | prose | - | GAP |
| SV-505 | skills/self-heal-advisory/SKILL.md | q: `deviations` is OPTIONAL elsewhere but **CONDITIONAL-MANDATORY** | FIX_RESULT edits a test assertion with no test: deviation | incomplete fix; must add a test: entry (prompt-contract only, no validator) | deterministic | prose | - | GAP |
| SV-506 | skills/self-heal-advisory/SKILL.md | q: Self-review-note gate (v14.43.0) | FIX_RESULT.summary lacks a self_review: clause | treat as INCOMPLETE; re-prompt the same fix worker once or surface for re-review | deterministic | prose | - | GAP |
| SV-507 | skills/self-heal-advisory/SKILL.md | q: if FIX_RESULT.deviations is non-empty: | FIX_RESULT.deviations non-empty | append to fixer_deviations prefixed fix-<n>; record_decision | deterministic | prose | - | test-deviations-advisory-seam.sh |
| SV-508 | skills/self-heal-advisory/SKILL.md | q: bash "${CLAUDE_PLUGIN_ROOT}/scripts/release-refold.sh"   # non-zero | after each fix, before the push | run release-refold.sh; non-zero ⇒ pause the phase like a failed push | deterministic | prose | script:release-refold.sh | test-release-refold.sh |
| SV-509 | skills/self-heal-advisory/SKILL.md | q: bash "${CLAUDE_PLUGIN_ROOT}/scripts/guard-finalize-publish.sh" write-marker   # append | fix commit moved HEAD | re-run guard-finalize-publish.sh write-marker in its own call before git push; refusal = Point 5 failure | deterministic | prose | script:guard-finalize-publish.sh | test-guard-finalize-publish.sh |
| SV-510 | skills/self-heal-advisory/SKILL.md | q: git push  # update PR (regular push, NEVER --force) | heal push | regular git push, NEVER --force | rule | prose | - | GAP |
| SV-511 | skills/self-heal-advisory/SKILL.md | q: Re-review guarantee (v14.21.0 self-heal hardening) | fix-the-class sweep | re-reviewed by the next iteration, or surfaced via ESCALATED on the final one | rule | prose | - | GAP |
| SV-512 | skills/self-heal-advisory/SKILL.md | q: if heal_iterations == max_heal_iterations AND iter_decision != PASS: | iterations exhausted and iter_decision != PASS | ESCALATED; remaining incl. rule/ci findings; PR comment notes an un-re-reviewed final sweep | deterministic | prose | - | GAP |
| SV-513 | skills/self-heal-advisory/SKILL.md | q: turns it ON; the flag wins over config | --multi-voter-heal or .multi_voter_heal true (no --no-multi-voter-heal) | MULTI_VOTER_HEAL on; false ⇒ loop runs exactly as written | deterministic | prose | - | GAP |
| SV-514 | skills/self-heal-advisory/SKILL.md | q: remains **THE LLM gating signal** | multi-voter on | code-reviewer CODE_REVIEW_RESULT stays THE LLM gating signal; rule/ci findings never voted away | rule | prose | - | GAP |
| SV-515 | skills/self-heal-advisory/SKILL.md | q: a **verification voter** on the same diff scope | verification voter findings | at_floor new-surface findings enter the merge rule; heal_decision never derives from the voter | rule | prose | - | GAP |
| SV-516 | skills/self-heal-advisory/SKILL.md | q: `VOTER_PROVIDER == ""` (the DEFAULT — absent flag AND absent config) | VOTER_PROVIDER empty (default) | spawn red-team-reviewer Task as the voter | deterministic | prose | - | GAP |
| SV-517 | skills/self-heal-advisory/SKILL.md | q: `VOTER_PROVIDER != ""` (e.g. `cursor:gpt-5`) — instead of spawning the | VOTER_PROVIDER set | shell out to lens-run.sh; lens_status ok ⇒ issues[] are voter findings; any other status ⇒ degrade the iteration to single-voter | deterministic | prose | - | GAP |
| SV-518 | skills/self-heal-advisory/SKILL.md | q: **Second-opinion refute check (the merge rule — decides WHICH findings | multi-voter at_floor findings from both lenses | fix only findings surviving the OTHER lens's refute (≤1 refute spawn per lens); refuted ⇒ logged, not fixed; only the code-reviewer refute carries the EXECUTION DIRECTIVE | deterministic | prose | - | GAP |
| SV-519 | skills/self-heal-advisory/SKILL.md | q: **Delay-vs-decide (the precise invariant):** | multi-voter | voter can DELAY finalization within the bound, never FLIP a decision | rule | prose | - | GAP |
| SV-520 | skills/self-heal-advisory/SKILL.md | q: Code-reviewer PASS + zero surviving red-team findings → PASS, exactly | code-reviewer PASS + zero surviving voter findings | PASS | deterministic | prose | - | GAP |
| SV-521 | skills/self-heal-advisory/SKILL.md | q: Code-reviewer PASS + ≥1 surviving red-team `at_floor` finding → | code-reviewer PASS + ≥1 surviving voter at_floor finding | fix task on the surviving set; re-review next iteration (bounded) | deterministic | prose | - | GAP |
| SV-522 | skills/self-heal-advisory/SKILL.md | q: Code-reviewer FAIL with ALL of its findings refuted (surviving set | code-reviewer FAIL with ALL findings refuted | no fix task, no auto-PASS; ESCALATED with refutation log posted | deterministic | prose | - | GAP |
| SV-523 | skills/self-heal-advisory/SKILL.md | q: **Fail-safe degradation:** if the red-team voter (or a refute spawn) | voter or refute spawn errors/times out | log one line; degrade that iteration to single-voter; never abort | deterministic | prose | - | GAP |
| SV-524 | skills/self-heal-advisory/SKILL.md | q: **Per-run counters (additive prose — NO schema bump):** | multi-voter counters | findings_raised/refuted/fixed carried in summary and Outcome; no new field | rule | prose | - | GAP |
| SV-525 | skills/self-heal-advisory/SKILL.md | q: The standalone `--red-team` / `--no-red-team` advisory lens (further | standalone --red-team lens | untouched and independent of multi-voter | rule | prose | - | GAP |
| SV-526 | skills/self-heal-advisory/SKILL.md | q: The flags do NOT alias each other: `--multi-voter-heal` does not enable | flag aliasing | --multi-voter-heal and --red-team never enable/suppress each other | rule | prose | - | GAP |
| SV-527 | skills/self-heal-advisory/SKILL.md | q: When BOTH are active, `red-team-reviewer` may legitimately be spawned | both active | red-team-reviewer may spawn twice with distinct roles; record outcomes distinctly | rule | prose | - | GAP |
| SV-528 | skills/self-heal-advisory/SKILL.md | q: multi-voter is ~2× review spawns per heal iteration | multi-voter cost | ~2× review spawns; graduates to default only if the arm-3 eval earns it | story | prose | - | GAP |
| SV-529 | skills/self-heal-advisory/SKILL.md | q: if heal_decision == PASS and rubric_bullets: | heal_decision PASS and brief has rubric bullets | spawn rubric-grader (no per-call model:); else rubric_score null | deterministic | prose | - | GAP |
| SV-530 | skills/self-heal-advisory/SKILL.md | q: Grader runs **only when `heal_decision == PASS`**. On ESCALATED or | ESCALATED or invariant-violation path | rubric_score null; grader not run | deterministic | prose | - | GAP |
| SV-531 | skills/self-heal-advisory/SKILL.md | q: Grader is **read-only and advisory** — a failing rubric item does NOT | rubric result | read-only and advisory; never changes heal_decision, fixes or blocks | rule | prose | - | GAP |
| SV-532 | skills/self-heal-advisory/SKILL.md | q: If the brief has no `## Outcomes Rubric` section: `rubric_score = null`. | brief has no ## Outcomes Rubric | rubric_score null | deterministic | prose | - | GAP |
| SV-533 | skills/self-heal-advisory/SKILL.md | q: If parsing the grader output fails (no `rubric_score: N/M` line): record | grader output has no rubric_score: N/M line | record rubric_grader_parse_failed; rubric_score null; never fail the task | deterministic | prose | - | GAP |
| SV-534 | skills/self-heal-advisory/SKILL.md | q: Grader output is appended to the PR as a comment alongside the heal | grader output | append to the PR as a comment, best-effort | rule | prose | - | GAP |
| SV-535 | skills/self-heal-advisory/SKILL.md | q: execute the three System Twin advisory steps | after the loop (any heal_decision) | run conformance, benchmark, ground truth (--no-cmd when non-interactive) | deterministic | prose | - | GAP |
| SV-536 | skills/self-heal-advisory/SKILL.md | q: none of these checks ever changes `heal_decision`, triggers a fix iteration | System Twin check fails | non-fatal; record and continue; skip first under YELLOW/RED budget | rule | prose | - | GAP |
| SV-537 | skills/self-heal-advisory/SKILL.md | q: Code Reviewer auto-detects Beads | Beads not active | CODE_REVIEW_RESULT is the sole output channel parsed | deterministic | prose | - | GAP |
| SV-538 | skills/self-heal-advisory/SKILL.md | q: It is a SINGLE pass that lives **OUTSIDE the bounded fix loop** | advisory red-team lens | single pass outside the loop, after the review decision, before the completion tail | rule | prose | - | GAP |
| SV-539 | skills/self-heal-advisory/SKILL.md | q: rc = JSON of `classify-risk.sh "$BASE_BRANCH" HEAD` | every Phase 4.5 reaching the lens | run classify-risk.sh unconditionally (before the enable guard); null ⇒ treated like true | deterministic | prose | script:classify-risk.sh | test-classify-risk.sh |
| SV-540 | skills/self-heal-advisory/SKILL.md | q: if RED_TEAM_ENABLED != true: | RED_TEAM_ENABLED != true | red_team_advisory disabled; silent skip | deterministic | prose | - | GAP |
| SV-541 | skills/self-heal-advisory/SKILL.md | q: if high_risk == false: | enabled and high_risk false | red_team_advisory skipped_low_risk; no spawn | deterministic | prose | - | GAP |
| SV-542 | skills/self-heal-advisory/SKILL.md | q: else:   # true OR null — spawn | enabled and high_risk true or null | spawn exactly ONE advisory red-team pass | deterministic | prose | - | GAP |
| SV-543 | skills/self-heal-advisory/SKILL.md | q: if gh pr comment "$PR_URL" --body | red-team comment post succeeds / fails | ran / record red_team_advisory_comment_failed and error (no bare or-true mask) | deterministic | prose | - | GAP |
| SV-544 | skills/self-heal-advisory/SKILL.md | q: catch (any spawn error / timeout / non-zero): | red-team spawn error / timeout | record red_team_advisory_error; error; continue | deterministic | prose | - | GAP |
| SV-545 | skills/self-heal-advisory/SKILL.md | q: Red-team findings **NEVER change `heal_decision`**, **NEVER directly | red-team findings | never change heal_decision, drive the fix, or block; CODE_REVIEW_RESULT is the sole LLM gate | rule | prose | - | GAP |
| SV-546 | skills/self-heal-advisory/SKILL.md | q: If the Code Reviewer INDEPENDENTLY also flags an issue the red-team | reviewer independently flags a red-team issue | normal class-based fix path, driven by CODE_REVIEW_RESULT; red team never feeds the fixer | rule | prose | - | GAP |
| SV-547 | skills/self-heal-advisory/SKILL.md | q: **FAIL-SAFE (mirrors the CLAUDE.md "side-effect emitters fail SAFE" | red-team spawn or comment failure | logged no-op; never propagates to status, the guard, or aborts the run | rule | prose | - | GAP |
| SV-548 | skills/self-heal-advisory/SKILL.md | q: **Recording (no `schema_version` bump):** carry `red_team_advisory` | recording red_team_advisory / risk_classification | in summary and Outcome; risk_classification absent on bypass paths; no schema bump | rule | prose | - | GAP |
| SV-549 | skills/self-heal-advisory/SKILL.md | q: If the fix Task() returns an error or no FIX_RESULT block: pause the | fix Task errors or returns no FIX_RESULT | emit SUPERVISOR_RESULT status checkpoint and exit with resume; do NOT increment the resume counter now | deterministic | prose | - | GAP |
| SV-550 | skills/self-heal-advisory/SKILL.md | q: **Completion-tail guard — LIVES VERBATIM IN `agents/supervisor.md` | completion tail step 0 | apply the guard verbatim from agents/supervisor.md; violation ⇒ status failed, stop | deterministic | prose | - | GAP |
| SV-551 | skills/self-heal-advisory/SKILL.md | q: `heal_decision == PASS` OR `heal_loop_ran == false` (loop skipped): task | heal_decision PASS or heal_loop_ran false | task succeeds cleanly | deterministic | prose | - | GAP |
| SV-552 | skills/self-heal-advisory/SKILL.md | q: `heal_decision == ESCALATED`: task succeeds with escalation | heal_decision ESCALATED | task succeeds with escalation | deterministic | prose | - | GAP |
| SV-553 | skills/self-heal-advisory/SKILL.md | q: On PASS / loop-skipped: Move brief from `in-progress/` → `done/`, | PASS / loop-skipped with job: | move brief in-progress/ → done/ and append ## Outcome (red-team, until-mergeable lines conditional) | deterministic | prose | - | test-build-handoff.sh |
| SV-554 | skills/self-heal-advisory/SKILL.md | q: On ESCALATED: Move brief from `in-progress/` → `done/`, append outcome | ESCALATED with job: | move brief to done/ with completed_with_escalation, Heal reason (closed set) and remaining issues | deterministic | prose | - | GAP |
| SV-555 | skills/self-heal-advisory/SKILL.md | q: **`## Not verified` section (optional, harness-port/04) — appended to | any worker has not_verified items | append one ## Not verified section to the brief; omitted entirely when none; report-only | deterministic | prose | - | test-not-verified-transport-seam.sh |
| SV-556 | skills/self-heal-advisory/SKILL.md | q: Backward compatibility: If job file is not in `in-progress/`, skip the | job file not in in-progress/ | skip the move (direct /supervisor task:) | deterministic | prose | - | GAP |
| SV-557 | skills/self-heal-advisory/SKILL.md | q: the completion tail writes **nothing** to the originating requirement file | completion tail (any outcome) | write NOTHING to the requirement file; done means merged, PR still open | rule | prose | - | GAP |
| SV-558 | skills/self-heal-advisory/SKILL.md | q: **Who closes it out:** `automate-helpers.sh closeout` | requirement done stamp | sole writer is automate-helpers.sh closeout after the PR reads MERGED | rule | prose | script:automate-helpers.sh closeout | test-automate-trail.sh |
| SV-559 | skills/self-heal-advisory/SKILL.md | q: **Where Phase 4.5's verdict goes:** the brief's `## Outcome` block (step | Phase 4.5 verdict | goes to the brief ## Outcome (and the /automate run file), never the requirement | rule | prose | - | GAP |
| SV-560 | skills/self-heal-advisory/SKILL.md | q: **Record:** `record_decision(phase: SELF_HEAL, decision: | step 2.5 | record requirement_closeout deferred_to_post_merge; fail-safe | rule | prose | - | GAP |
| SV-561 | skills/self-heal-advisory/SKILL.md | q: **Honest limit — one path gets no automatic done stamp:** a plain | plain /supervisor or /autonomous outside /automate | no automatic done stamp; human runs reconcile-status --apply; stamp-requirement-status writes brief-shipped only | rule | prose | script:automate-helpers.sh reconcile-status | test-automate-helpers.sh |
| SV-562 | skills/self-heal-advisory/SKILL.md | q: this step stamped the | before automate-followups/37 | step stamped done while the PR was open (finding F7) | story | prose | - | GAP |
| SV-563 | skills/self-heal-advisory/SKILL.md | q: Runs on the SAME successful outcomes as step 2.5 | PASS / loop-skipped / ESCALATED only | MAY write orientation proposals to gitignored .supervisor/orientation-proposals/ (≤1000 chars each) | deterministic | prose | - | GAP |
| SV-564 | skills/self-heal-advisory/SKILL.md | q: NEVER writes the committed `.agent/orientation/` store. | orientation proposals | NEVER write the committed .agent/orientation/ store; promotion only via /dreaming + add-orientation.sh | rule | prose | script:add-orientation.sh | test-add-orientation.sh |
| SV-565 | skills/self-heal-advisory/SKILL.md | q: This whole step is a **runtime side-effect emitter and MUST fail SAFE** | orientation proposal write fails | silent logged no-op; never blocks the tail | deterministic | prose | - | GAP |
| SV-566 | skills/self-heal-advisory/SKILL.md | q: **Reset resume counter (unconditional — runs on every exit path: PASS, | every exit path (PASS / ESCALATED / skipped) | reset resume counter unconditionally | rule | prose | - | GAP |
| SV-567 | skills/self-heal-advisory/SKILL.md | q: **Record the outcome:** `record_decision(phase: SELF_HEAL, decision: | completion tail step 4 | record PASS / ESCALATED / loop_skipped decision | rule | prose | - | GAP |
| SV-568 | skills/self-heal-advisory/SKILL.md | q: **Terminal status is derived, not flipped here — and it now fires | terminal status | derived by build-state.sh from session_end; reproject-state-on-terminal hook re-projects; never re-add a prompt status flip | rule | prose | script:reproject-state-on-terminal.sh | test-progress-state.sh |
| SV-569 | skills/self-heal-advisory/SKILL.md | q: **Runs only on a PASS outcome** (`heal_decision == PASS` or loop-skipped | PASS or loop-skipped (step 4.5) | run the contract builder; skip on ESCALATED / base-mismatch / invariant-violation | deterministic | prose | - | GAP |
| SV-570 | skills/self-heal-advisory/SKILL.md | q: **Propose-only, advisory, reversible** — writes the advisory twin | contract builder | propose-only, advisory, reversible | rule | prose | - | GAP |
| SV-571 | skills/self-heal-advisory/SKILL.md | q: **Pinned repo-root CWD, never a worktree** — | contract builder | pinned repo-root CWD; writer exits 3 from a worktree | rule | prose | script:write-system-contract.sh | test-system-contract.sh |
| SV-572 | skills/self-heal-advisory/SKILL.md | q: **Context-Keeper is OUT of this path** — sole writer of the twin store | contract builder | Context-Keeper out of the path | rule | prose | - | GAP |
| SV-573 | skills/self-heal-advisory/SKILL.md | q: **Failure is non-fatal** — log `record_decision(phase: SELF_HEAL, | contract builder failure | non-fatal; log twin_builder and continue | rule | prose | - | GAP |
| SV-574 | skills/self-heal-advisory/SKILL.md | q: **Emit SUPERVISOR_RESULT block for this task** (see | completion tail step 5 | emit exactly one SUPERVISOR_RESULT with nested twin objects + knowledge_sources_used; flat fields on session_end | deterministic | prose | script:validate-supervisor-result.py | test-result-validators.sh |
| SV-575 | skills/self-heal-advisory/SKILL.md | q: include when non-empty, omit when empty | heal_dismissed non-empty / empty | include verbatim / omit (empty ⇒ absent) | deterministic | prose | - | test-automate-dismissed.sh |
| SV-576 | skills/self-heal-advisory/SKILL.md | q: When `heal_dismissed` is non-empty, post ONE `gh pr comment` | heal_dismissed non-empty | post ONE dismissed marker comment; round n = heal_iterations+1 on break exits, heal_iterations on exhaustion; none when loop skipped | deterministic | prose | - | GAP |
| SV-577 | skills/self-heal-advisory/SKILL.md | q: Runs ONLY on a PASS / normal completion that produced a PR | PASS / normal completion with PR_URL set | dispatch the until-mergeable drain unless --no-auto-review / .auto_review false; skip on base-mismatch, failed, checkpoint, no PR | deterministic | prose | script:dispatch-pr-review.sh | test-dispatch-pr-review.sh |
| SV-578 | skills/self-heal-advisory/SKILL.md | q: The signal is threaded via **environment variables** | until-mergeable signal | threaded via env vars (never a slash string or positional); per-PR marker ⇒ exactly ONE dispatch | rule | prose | script:dispatch-pr-review.sh | test-dispatch-pr-review.sh |
| SV-579 | skills/self-heal-advisory/SKILL.md | q: The dispatched drain **NEVER merges** and **NEVER waits on a human** | dispatched drain | never merges, never waits on a human; dispatcher always exits 0; never affects status | rule | prose | script:dispatch-pr-review.sh | test-dispatch-pr-review.sh |
| SV-580 | skills/self-heal-advisory/SKILL.md | q: ALSO backstops this dispatch | gh pr create Bash call in a gated session | PostToolUse hook backstops the dispatch (same dispatcher, per-PR marker dedupes) | deterministic | prose | script:hook-dispatch-on-pr-create.sh | test-hook-dispatch-on-pr-create.sh |
| SV-581 | skills/self-heal-advisory/SKILL.md | q: that rationale is retired now that the drain is working-tree-isolated | drain/self-heal timing overlap | harmless (isolated worktree); never write auto_review false as a race workaround | rule | prose | - | GAP |
| SV-582 | skills/self-heal-advisory/SKILL.md | q: reconcile against the MARKER, never from "did I dispatch". | recording until_mergeable_dispatched | from the on-disk marker (exact URL match), never from did-I-dispatch; false only when no marker | rule | prose | - | GAP |
| SV-583 | skills/self-heal-advisory/SKILL.md | q: **Advisory Twin delta line (informational ONLY):** echo one | completion tail step 6 | echo the Twin delta line; never gates | deterministic | prose | script:format-twin-delta.sh | test-format-twin-delta.sh |
| SV-584 | skills/self-heal-advisory/SKILL.md | q: **Rules-check replay line (report line, executable-rule-candidates/01; | completion tail step 7 | surface the LAST iteration's rules_check_line in the report only (not PR body, no schema field) | rule | prose | - | GAP |
| SV-585 | skills/self-heal-advisory/SKILL.md | q: **Rules-store audit line (report line ONLY, automate-followups/09):** | completion tail step 8 | surface rules_audit_line (+ trigger line) in the report only | rule | prose | - | GAP |
| SV-586 | skills/self-heal-advisory/SKILL.md | q: **House-rule verdicts line (report line ONLY, #431/#432):** surface the | completion tail step 9 | surface the LAST house_rules_line in the report only | rule | prose | - | GAP |
| SV-587 | skills/self-heal-advisory/SKILL.md | q: Also stamp the additive `plugin_version` field | session_end emission | stamp plugin_version (manifest unreadable ⇒ "unknown") and flat knowledge_sources_used | deterministic | prose | - | test-insights.sh |
| SV-588 | skills/self-heal-advisory/SKILL.md | q: CODE_REVIEW_RESULT malformed or missing | CODE_REVIEW_RESULT malformed or missing | retry review once; still malformed ⇒ pause with resume | deterministic | prose | - | GAP |
| SV-589 | skills/self-heal-advisory/SKILL.md | q: Fix Task() crashes or returns no FIX_RESULT | fix Task crashes / no FIX_RESULT | pause: SUPERVISOR_RESULT status checkpoint; counter increments next --continue | deterministic | prose | - | GAP |
| SV-590 | skills/self-heal-advisory/SKILL.md | q: `git push` fails inside loop | git push fails inside loop | pause phase; report auth/network error | deterministic | prose | - | GAP |
| SV-591 | skills/self-heal-advisory/SKILL.md | q: `release-refold.sh` exits non-zero before a heal push (#512) | release-refold.sh non-zero before a heal push | pause phase like a failed push; report reason | deterministic | prose | script:release-refold.sh | test-release-refold.sh |
| SV-592 | skills/self-heal-advisory/SKILL.md | q: finalize-gate `write-marker` refuses before a heal push | write-marker refuses before a heal push | pause phase; report children_unsettled / worker_results_unparsed; never hand-write the marker | deterministic | prose | script:guard-finalize-publish.sh | test-guard-finalize-publish.sh |
| SV-593 | skills/self-heal-advisory/SKILL.md | q: `gh pr comment` fails at escalation | gh pr comment fails at escalation | record findings in state.md decisions log; escalation still succeeds | deterministic | prose | - | GAP |
| SV-594 | skills/self-heal-advisory/SKILL.md | q: Resume counter ≥ 3 | resume counter ≥ 3 | abort loop; ESCALATED self_heal_resume_thrash; run completion tail | deterministic | prose | - | GAP |
| SV-595 | skills/self-heal-advisory/SKILL.md | q: Tool budget exceeded mid-loop | tool budget exceeded mid-loop | checkpoint current_phase SELF_HEAL; exit with resume | deterministic | prose | - | GAP |
| SV-596 | skills/async-orchestration/SKILL.md | q: Max concurrent worktrees: `config.max_workers` (default: 2) | parallel dispatch | max concurrent worktrees = config.max_workers (default 2) | rule | prose | - | GAP |
| SV-597 | skills/async-orchestration/SKILL.md | q: Each worker gets its own git worktree (no file conflicts) | parallel dispatch | each worker gets its own git worktree | rule | prose | - | GAP |
| SV-598 | skills/async-orchestration/SKILL.md | q: Only dispatch workers via `run_in_background: true` | parallel dispatch | dispatch workers only via run_in_background: true | rule | prose | - | GAP |
| SV-599 | skills/async-orchestration/SKILL.md | q: Poll with `block: false` first; fall back to `block: true` on idle | polling | block: false first; fall back to block: true on idle | deterministic | prose | - | GAP |
| SV-600 | skills/async-orchestration/SKILL.md | q: Sequential merge into feature branch after all workers complete | all workers complete | merge sequentially into the feature branch | rule | prose | - | GAP |
| SV-601 | skills/async-orchestration/SKILL.md | q: Clean up worktrees immediately after merge | after merge | clean up worktrees immediately | rule | prose | - | GAP |
| SV-602 | skills/async-orchestration/SKILL.md | h: ### Determining LAUNCHABLE vs BLOCKED | subtask deps completed, no file overlap with a LAUNCHABLE sibling, worktrees < max_workers | LAUNCHABLE; else BLOCKED | deterministic | prose | - | GAP |
| SV-603 | skills/async-orchestration/SKILL.md | h: ### File Overlap Detection | two subtasks modify any same file | overlap ⇒ must serialize | deterministic | prose | - | GAP |
| SV-604 | skills/async-orchestration/SKILL.md | h: ### Single-Agent / Sequential Paths: Skip Worktrees | exactly 1 subtask / --sequential with > 1 | execute inline, skip worktrees; no per-subtask reviewer | deterministic | prose | - | GAP |
| SV-605 | skills/async-orchestration/SKILL.md | q: Execute inline, no worktree/background dispatch; ONE worker runs ALL | Single-Agent Path | inline; ONE worker runs ALL criteria | rule | prose | - | GAP |
| SV-606 | skills/async-orchestration/SKILL.md | q: NO per-subtask Code Reviewer — Phase 4.5 holistic review is the single | Single-Agent Path | no per-subtask Code Reviewer; Phase 4.5 is the single review | rule | prose | - | GAP |
| SV-607 | skills/async-orchestration/SKILL.md | q: Skip all worktree lifecycle | Single-Agent Path | skip all worktree lifecycle | rule | prose | - | GAP |
| SV-608 | skills/async-orchestration/SKILL.md | q: Execute all subtasks inline, sequentially; no worktrees, no background | Sequential Path | inline, sequential, no worktrees or background dispatch | rule | prose | - | GAP |
| SV-609 | skills/async-orchestration/SKILL.md | q: **NO per-subtask Code Reviewer** — same as the Single-Agent Path and | Sequential Path | no per-subtask Code Reviewer; deterministic gate is per-subtask; Phase 4.5 is the sole LLM gate | rule | prose | - | GAP |
| SV-610 | skills/async-orchestration/SKILL.md | h: ### Phase 3 (EXECUTE — Execute Manager Step 2a): Create Branches | Phase 3 entry | Execute Manager creates subtask branches (Step 2a); Phase 2 runs no git | rule | prose | - | GAP |
| SV-611 | skills/async-orchestration/SKILL.md | h: ### Phase 3 (EXECUTE): Create Worktrees | worktree creation | sibling path ../{project}-<id> with the LITERAL project name, never $(basename $(pwd)) (audit parses it unexpanded) | rule | prose | script:worktree-audit.sh | test-worktree-audit.sh |
| SV-612 | skills/async-orchestration/SKILL.md | q: **Naming convention:** `{project-dir}-{subtask-id}` | worktree naming | {project-dir}-{subtask-id} | rule | prose | - | GAP |
| SV-613 | skills/async-orchestration/SKILL.md | h: ### Phase 4 (FINALIZE): Merge and Cleanup | FINALIZE merge | merge subtask branches --no-ff in dependency order; salvage, then remove worktrees, then delete branches | deterministic | prose | script:worktree-salvage.sh | test-worktree-salvage.sh |
| SV-614 | skills/async-orchestration/SKILL.md | h: ### Merge Conflict Handling | merge fails | do NOT force-resolve; escalate | deterministic | prose | - | GAP |
| SV-615 | skills/async-orchestration/SKILL.md | q: **Do NOT force resolve** — escalate to human | merge conflict | never force-resolve — escalate to human | rule | prose | - | GAP |
| SV-616 | skills/async-orchestration/SKILL.md | q: Report which files conflict | merge conflict | report which files conflict | rule | prose | - | GAP |
| SV-617 | skills/async-orchestration/SKILL.md | q: Checkpoint current state | merge conflict | checkpoint current state | rule | prose | - | GAP |
| SV-618 | skills/async-orchestration/SKILL.md | q: Provide resume command | merge conflict | provide resume command | rule | prose | - | GAP |
| SV-619 | skills/async-orchestration/SKILL.md | h: ### Spawning a Worker | spawning a worker | Task with subagent_type loomwright:worker and run_in_background: true | rule | prose | - | GAP |
| SV-620 | skills/async-orchestration/SKILL.md | q: A worker is always `loomwright:worker` | worker spawn type | always loomwright:worker — a general-purpose worker runs with none of the worker hooks | rule | prose | - | GAP |
| SV-621 | skills/async-orchestration/SKILL.md | h: ### Worker Prompt Template | worker prompt | pinned main-checkout brief path + ≤200-char summary; ci-local.sh --affected, never the full pool | rule | prose | - | test-phase45-rounds-seam.sh |
| SV-622 | skills/async-orchestration/SKILL.md | q: the acceptance criteria travel as a bounded | worker prompt | pointer, not payload; full spawn shapes live in Part 2 and execute-manager Step 3 | rule | prose | - | GAP |
| SV-623 | skills/async-orchestration/SKILL.md | h: ### Poll Loop Pattern (Execute Manager) | poll loop | runs in Execute Manager with iteration limits/back-off; no per-subtask reviewer | rule | prose | - | GAP |
| SV-624 | skills/async-orchestration/SKILL.md | q: max_iterations = 30 | poll loop | max 30 iterations, start at 2s interval | deterministic | prose | - | GAP |
| SV-625 | skills/async-orchestration/SKILL.md | q: if result.is_complete: | worker complete | reset idle streak/interval; prefer .worker-summary.md, fall back to TaskOutput; record via Context-Keeper | deterministic | prose | - | GAP |
| SV-626 | skills/async-orchestration/SKILL.md | q: No reviewer is spawned here. If the on-disk outputs_verified gate passed | on-disk outputs_verified gate passed | subtask complete; no reviewer spawn, no record_review call | rule | prose | script:verify-provides.sh | test-verify-provides.sh |
| SV-627 | skills/async-orchestration/SKILL.md | q: if active_worktrees < max_workers: | newly launchable subtask and active_worktrees < max_workers | create worktree + spawn worker | deterministic | prose | - | GAP |
| SV-628 | skills/async-orchestration/SKILL.md | q: if not results_found: | no results this iteration (idle) | idle_streak += 1; ≥3 ⇒ double interval (cap 30s); block on the earliest worker | deterministic | prose | - | GAP |
| SV-629 | skills/async-orchestration/SKILL.md | q: if tool_calls >= 55: | tool_calls ≥ 55 | output EXECUTE_CHECKPOINT and EXIT | deterministic | prose | - | GAP |
| SV-630 | skills/async-orchestration/SKILL.md | q: if tool_calls >= 48: | tool_calls ≥ 48 / ≥ 36 | poll interval ≥5s / compress summaries <100 tokens | deterministic | prose | - | GAP |
| SV-631 | skills/async-orchestration/SKILL.md | h: ### Worker Summary File Protocol | worker complete | read .worker-summary.md; missing ⇒ parse full TaskOutput | deterministic | prose | - | GAP |
| SV-632 | skills/async-orchestration/SKILL.md | h: ### Result Collection | after TaskOutput | extract files/tests/outputs_verified and record via record_worker_result; no record_review | rule | prose | - | GAP |
| SV-633 | skills/async-orchestration/SKILL.md | q: Record the extracted data to Context-Keeper via `record_worker_result` | result collection | ## Session is hook-derived; ## Worker Results and ## Subtasks stay this step's responsibility | rule | prose | script:emit-progress-event.sh | test-progress-state.sh |
| SV-634 | skills/async-orchestration/SKILL.md | h: ### Worker Output Format | worker output | MUST emit a structured WORKER_RESULT block | rule | prose | script:validate-worker-result.py | test-result-validators.sh |
| SV-635 | skills/async-orchestration/SKILL.md | h: ### No Per-Subtask Reviewer Output | per-subtask review output | none exists; outputs_verified + tests/lint gate; Phase 4.5 is the sole LLM gate | rule | prose | - | GAP |
| SV-636 | skills/async-orchestration/SKILL.md | h: ### Execute Manager holds (isolated from Supervisor): | Execute Manager context | ~350 tokens (2 workers, no reviewer) | story | prose | - | GAP |
| SV-637 | skills/async-orchestration/SKILL.md | h: ### Supervisor holds during Phase 3: | Supervisor context during Phase 3 | ~50 tokens | story | prose | - | GAP |
| SV-638 | skills/async-orchestration/SKILL.md | q: the Execute Manager must materialize each producer's outputs | spawning a BLOCKED subtask whose producers completed | merge producer branches into the dependent branch, never onto main HEAD | rule | prose | - | GAP |
| SV-639 | skills/async-orchestration/SKILL.md | q: Create the dependent's branch from `feature_branch` **as a ref only — | creating the dependent branch | git branch (ref only); never git checkout -b (moves the main worktree HEAD) | rule | prose | - | GAP |
| SV-640 | skills/async-orchestration/SKILL.md | q: Create a worktree for the dependent subtask: | dependent subtask | create its worktree (or one-shot worktree add -b) | rule | prose | - | GAP |
| SV-641 | skills/async-orchestration/SKILL.md | q: Materialize each producer's outputs by merging the producer branch INTO | each producer in requires | merge --no-ff into the dependent worktree, one merge per producer | deterministic | prose | - | GAP |
| SV-642 | skills/async-orchestration/SKILL.md | q: Only then spawn the worker into the dependent worktree. | materialization done | only then spawn the worker | rule | prose | - | GAP |
| SV-643 | skills/async-orchestration/SKILL.md | q: Merges happen in the dependent worktree only — never on the main repo | materialization merges | dependent worktree only, never main HEAD | rule | prose | - | GAP |
| SV-644 | skills/async-orchestration/SKILL.md | q: The integration feature branch HEAD remains untouched until FINALIZE | integration branch | HEAD untouched until FINALIZE | rule | prose | - | GAP |
| SV-645 | skills/async-orchestration/SKILL.md | q: Each producer is merged exactly once per dependent worktree (idempotent | producer merge | exactly once per dependent worktree (idempotent after clean checkout) | rule | prose | - | GAP |
| SV-646 | skills/async-orchestration/SKILL.md | q: If any merge conflicts during materialization, STOP | merge conflict during materialization | STOP, escalate Dependency Merge Conflict; no auto-resolve, no partial commit; quarantine worktree | deterministic | prose | - | GAP |
| SV-647 | skills/async-orchestration/SKILL.md | q: runs a verification gate that proves each declared `requires` entry | after materialization, before spawn | verify every requires entry exists in the dependent worktree (verify-provides --kind-table rows) | deterministic | prose | script:verify-provides.sh | test-verify-provides.sh |
| SV-648 | skills/async-orchestration/SKILL.md | q: **Pass criterion:** ALL checks for ALL `requires` entries must PASS. | pre-spawn checks | ALL checks for ALL requires entries must PASS | deterministic | prose | script:verify-provides.sh | test-verify-provides.sh |
| SV-649 | skills/async-orchestration/SKILL.md | q: **Fail handling:** If any check fails, the dependent subtask is held | any pre-spawn check fails | hold the subtask (no spawn); EXECUTE_CHECKPOINT adjudication_required: true | deterministic | prose | - | GAP |
| SV-650 | skills/async-orchestration/SKILL.md | q: Without it, a worker would be spawned into a worktree | pre-spawn gate rationale | fail fast instead of a worker fabricating or drifting | story | prose | - | GAP |
| SV-651 | skills/async-orchestration/SKILL.md | q: When pre-spawn verification fails (a producer didn't actually emit | pre-spawn verification fails OR worker outputs_gap non-empty | EXECUTE_CHECKPOINT adjudication_required: true with four options | deterministic | prose | - | GAP |
| SV-652 | skills/async-orchestration/SKILL.md | q: The Execute Manager **NEVER picks an option itself** | adjudication | Execute Manager NEVER picks an option; Supervisor asks the user | rule | prose | - | GAP |
| SV-653 | skills/async-orchestration/SKILL.md | q: **A: Re-queue producer** — retry the producing subtask with the | option A | re-queue producer with missing outputs added (risk: gap recurs on brief drift) | judgment | prose | - | GAP |
| SV-654 | skills/async-orchestration/SKILL.md | q: **B: Insert remediation subtask** — add a new subtask whose sole job | option B | insert remediation subtask (risk: brief diverges from executed plan) | judgment | prose | - | GAP |
| SV-655 | skills/async-orchestration/SKILL.md | q: **C: Exit to Launch Pad** — abort the run; the brief itself is | option C | exit to Launch Pad; brief is incoherent | judgment | prose | - | GAP |
| SV-656 | skills/async-orchestration/SKILL.md | q: **D: Update consumer brief** — consumer no longer needs the missing | option D | remove the consumer's requires entry (risk: silent scope reduction) | judgment | prose | - | GAP |
| SV-657 | skills/async-orchestration/SKILL.md | q: **EXECUTE_CHECKPOINT block fields** (adjudication-specific additions — | adjudication EXECUTE_CHECKPOINT | must also carry hook-required base fields schema_version, completed_so_far, remaining, resume_context, reason | rule | prose | script:validate-execute-result.py | test-result-validators.sh |
| SV-658 | skills/async-orchestration/SKILL.md | q: presents the four options to the user (with the `missing_outputs` list | adjudication checkpoint received | present the four options with missing_outputs and check_run evidence before re-entering Phase 3 | rule | prose | - | GAP |
| SV-659 | skills/async-orchestration/SKILL.md | q: Worker fails (crash/timeout) | worker crash / timeout | record error, retry once, then escalate | deterministic | prose | - | GAP |
| SV-660 | skills/async-orchestration/SKILL.md | q: Worker output unparseable | worker output unparseable | record error, retry with clearer prompt | deterministic | prose | - | GAP |
| SV-661 | skills/async-orchestration/SKILL.md | q: Worktree creation fails | worktree creation fails | fall back to sequential execution | deterministic | prose | - | GAP |
| SV-662 | skills/async-orchestration/SKILL.md | q: Worktree already exists | worktree already exists | remove and recreate, or reuse if clean | deterministic | prose | - | GAP |
| SV-663 | skills/async-orchestration/SKILL.md | q: Disk space concern | disk space concern | limit to 2 concurrent worktrees | rule | prose | - | GAP |
| SV-664 | skills/async-orchestration/SKILL.md | q: Tool budget exceeded | tool budget exceeded | output EXECUTE_CHECKPOINT, exit | deterministic | prose | - | GAP |
| SV-665 | skills/async-orchestration/SKILL.md | q: Summary file missing | summary file missing | parse full TaskOutput | deterministic | prose | - | GAP |
| SV-666 | skills/async-orchestration/SKILL.md | q: Dependency merge conflict | dependency merge conflict | STOP; escalate; never auto-resolve | deterministic | prose | - | GAP |
| SV-667 | skills/async-orchestration/SKILL.md | q: Pre-spawn verification fails | pre-spawn verification fails | hold subtask; EXECUTE_CHECKPOINT adjudication_required | deterministic | prose | - | GAP |
| SV-668 | skills/async-orchestration/SKILL.md | q: Worker reports `outputs_gap` non-empty | worker outputs_gap non-empty | EXECUTE_CHECKPOINT adjudication_required (Scope Expansion Adjudication) | deterministic | prose | - | GAP |
| SV-669 | skills/async-orchestration/SKILL.md | q: [ ] Parallelism analysis correctly identifies LAUNCHABLE vs BLOCKED | before completing async orchestration | parallelism analysis identifies LAUNCHABLE vs BLOCKED | rule | prose | - | GAP |
| SV-670 | skills/async-orchestration/SKILL.md | q: [ ] File overlap detection prevents conflicting workers | before completing async orchestration | file overlap detection prevents conflicting workers | rule | prose | - | GAP |
| SV-671 | skills/async-orchestration/SKILL.md | q: [ ] Worktrees created in sibling directories with correct naming | before completing async orchestration | worktrees in sibling dirs with correct naming | rule | prose | - | GAP |
| SV-672 | skills/async-orchestration/SKILL.md | q: [ ] Workers receive complete prompt with worktree path | before completing async orchestration | workers receive complete prompt with worktree path | rule | prose | - | GAP |
| SV-673 | skills/async-orchestration/SKILL.md | q: [ ] Non-blocking polling handles all worker states | before completing async orchestration | polling handles all worker states | rule | prose | - | GAP |
| SV-674 | skills/async-orchestration/SKILL.md | q: [ ] Sequential merge preserves dependency order | before completing async orchestration | sequential merge preserves dependency order | rule | prose | - | GAP |
| SV-675 | skills/async-orchestration/SKILL.md | q: [ ] All worktrees cleaned up after merge | before completing async orchestration | all worktrees cleaned up after merge | rule | prose | - | GAP |
| SV-676 | skills/async-orchestration/SKILL.md | q: [ ] Error handling covers crash, timeout, conflict | before completing async orchestration | error handling covers crash, timeout, conflict | rule | prose | - | GAP |
| SV-677 | skills/async-orchestration/SKILL.md | q: [ ] No per-subtask reviewer is spawned at any threshold — Single-Agent | any threshold | no per-subtask reviewer; deterministic gate + Phase 4.5 review | rule | prose | - | GAP |
| SV-678 | skills/async-orchestration/SKILL.md | q: the three sections below were moved VERBATIM | Part 2 provenance | moved verbatim; step numbering 1–7 incl. 6.5 preserved for cross-references | rule | prose | - | GAP |
| SV-679 | skills/async-orchestration/SKILL.md | q: **Pre-merge safety gate** (ALL must pass before any merge): | any pre-merge checklist point fails (worker not completed, orphan worktree, branch not ahead, child unsettled) | abort merge, log, move job to failed/; reviewer-PASS point vacuously satisfied | deterministic | prose | - | GAP |
| SV-680 | skills/async-orchestration/SKILL.md | q: **N/A at every threshold** | checklist point 2 (reviewer PASS) | N/A at every threshold; vacuously satisfied | rule | prose | - | GAP |
| SV-681 | skills/async-orchestration/SKILL.md | q: **Point 5 in full — children settled:** run | Point 5 | check-children-settled.sh --all + --expect-id per recorded worker id | deterministic | prose | script:check-children-settled.sh | test-check-children-settled.sh |
| SV-682 | skills/async-orchestration/SKILL.md | q: `status: "no_identity_rows"` — no expected id and zero | status no_identity_rows (nothing spawned) | PASS, reported children_check: no_identity_rows — never settled | deterministic | prose | script:check-children-settled.sh | test-check-children-settled.sh |
| SV-683 | skills/async-orchestration/SKILL.md | q: `status: "settled"` — every `agent_identity` row has a matching | status settled | PASS, children_check: settled | deterministic | prose | script:check-children-settled.sh | test-check-children-settled.sh |
| SV-684 | skills/async-orchestration/SKILL.md | q: `status: "unsettled"` — `unsettled_agent_ids[]` names at least one | status unsettled | interactive: SUP-CHILDREN ask (proceed / investigate / abort); non-interactive: fail closed children_unsettled | deterministic | prose | - | test-non-interactive-gates-seam.sh |
| SV-685 | skills/async-orchestration/SKILL.md | q: `status: "unverifiable"` (`jq_missing`) — treated the same as | status unverifiable (jq_missing) | treated as unsettled; never a silent pass | deterministic | prose | script:check-children-settled.sh | test-check-children-settled.sh |
| SV-686 | skills/async-orchestration/SKILL.md | q: **`--skip-children-check`** (escape hatch, mirrors | `--skip-children-check` | skip Point 5 only; record user_skipped_children_check; children_check: skipped | deterministic | prose | script:guard-finalize-publish.sh | test-guard-finalize-publish.sh |
| SV-687 | skills/async-orchestration/SKILL.md | q: **finalize-gate — publish blocked until this point passes | a publish (push or PR creation) in a live Supervisor run | denied until the finalize-gate marker names HEAD; write-marker only; session_log_missing / worker_results_unparsed refuse; a moved HEAD invalidates it | deterministic | prose | script:guard-finalize-publish.sh | test-guard-finalize-publish.sh |
| SV-688 | skills/async-orchestration/SKILL.md | q: `ended_without_result_ids[]` (agents whose terminal row was a | ended_without_result_ids non-empty | surface alongside unsettled ids for a SendMessage resume | deterministic | prose | script:check-children-settled.sh | test-check-children-settled.sh |
| SV-689 | skills/async-orchestration/SKILL.md | q: `rejected_stop_ids[]` (v15.83.0, diagnostic only) names every child with | rejected_stop_ids non-empty | diagnostic only; surface in the same line; status alone decides | deterministic | prose | script:check-children-settled.sh | test-check-children-settled.sh |
| SV-690 | skills/async-orchestration/SKILL.md | q: A read-only subtask (`WORKER_RESULT.no_changes: true`) is deliberately absent | read-only subtask (no_changes: true) | absent from merge_order; its worktree still cleaned up in step 4 | rule | prose | - | GAP |
| SV-691 | skills/async-orchestration/SKILL.md | q: If any verification fails → checkpoint, report missing worktree/branch | worktree / branch / has-changes verification fails | checkpoint, report missing worktree/branch, exit with resume | deterministic | prose | - | GAP |
| SV-692 | skills/async-orchestration/SKILL.md | q: **Commit worker changes in worktrees** (before merging): | before merging | commit worker changes in each worktree (in merge_order) | rule | prose | - | GAP |
| SV-693 | skills/async-orchestration/SKILL.md | q: **Sequential merge** of each subtask branch into feature branch (in | sequential merge conflict | STOP, never force-resolve; checkpoint merged / not-yet-merged lists; exit with resume | deterministic | prose | - | GAP |
| SV-694 | skills/async-orchestration/SKILL.md | q: **Cleanup worktrees** (ONLY after successful merge): | worktree cleanup | ONLY after successful merge; salvage as its own statement first; dirty refusal ⇒ report with salvage path, never a --force reflex | rule | prose | script:worktree-salvage.sh | test-worktree-salvage.sh |
| SV-695 | skills/async-orchestration/SKILL.md | q: Cleanup is verifiable (v15.66.0) | cleanup verification | PostToolUse observer records add/remove; worktree-audit.sh report lists leftovers (never removes) | rule | prose | script:worktree-audit.sh report | test-worktree-audit.sh |
| SV-696 | skills/async-orchestration/SKILL.md | q: **Create commits** (inline, following `skills/commit/SKILL.md`): | create commits | conventional commit with task linking per skills/commit | rule | prose | - | GAP |
| SV-697 | skills/async-orchestration/SKILL.md | q: **NEVER code-fence the message.** | commit message | NEVER code-fence it; first line is the conventional subject | rule | prose | - | GAP |
| SV-698 | skills/async-orchestration/SKILL.md | q: **Release re-fold (#512) — after step 5 | after step 5 commits, before write-marker and the push | run release-refold.sh; non-zero ⇒ abort with no push/PR, status failed, release_refold_refused, lock released | deterministic | prose | script:release-refold.sh | test-release-refold.sh |
| SV-699 | skills/async-orchestration/SKILL.md | q: **Push and create PR (against `BASE_BRANCH` — defaults to `main`):** | push and PR creation | push the feature branch with upstream, then create the PR with --base "$BASE_BRANCH" (default main) | rule | prose | - | GAP |
| SV-700 | skills/async-orchestration/SKILL.md | q: returns successfully, before declaring Phase 4 complete | PR creation returned | verify PR baseRefName matches BASE_BRANCH before declaring Phase 4 complete | deterministic | prose | - | GAP |
| SV-701 | skills/async-orchestration/SKILL.md | q: **First `gh pr view` non-zero exit** → `sleep 5; retry once`. | first gh pr view non-zero | sleep 5; retry once | deterministic | prose | - | GAP |
| SV-702 | skills/async-orchestration/SKILL.md | q: **Second non-zero exit AND `NON_INTERACTIVE == true`** (read live from | second gh pr view failure and NON_INTERACTIVE (read live from Context-Keeper) | set base_mismatch_detected (gh_unavailable_non_interactive); fall through to Phase 4.5 | deterministic | prose | - | GAP |
| SV-703 | skills/async-orchestration/SKILL.md | q: **Second non-zero exit AND `NON_INTERACTIVE == false`** → | second gh pr view failure, interactive | AskUserQuestion: retry / skip-verify-once / abort | judgment | prose | - | GAP |
| SV-704 | skills/async-orchestration/SKILL.md | q: **retry** — run `gh pr view --json baseRefName` once more; on success | user picks retry | run gh pr view once more; failure ⇒ treat as abort | deterministic | prose | - | GAP |
| SV-705 | skills/async-orchestration/SKILL.md | q: **skip-verify-once** — record `record_decision(phase: FINALIZE, | user picks skip-verify-once | record user_skipped_base_verify; continue as verified | deterministic | prose | - | GAP |
| SV-706 | skills/async-orchestration/SKILL.md | q: **abort** — `set_flag base_mismatch_detected value: {expected: | user picks abort | set base_mismatch_detected (user_aborted_gh_retry); fall through to Phase 4.5 cleanup | deterministic | prose | - | GAP |
| SV-707 | skills/async-orchestration/SKILL.md | q: If `ACTUAL_BASE == BASE_BRANCH`: verification passed, continue to step | ACTUAL_BASE == BASE_BRANCH | verification passed; continue to step 7 | deterministic | prose | - | GAP |
| SV-708 | skills/async-orchestration/SKILL.md | q: If `ACTUAL_BASE != BASE_BRANCH`: this is a real base-branch mismatch | ACTUAL_BASE != BASE_BRANCH | set base_mismatch_detected (phase4_self_verify); do NOT emit SUPERVISOR_RESULT here | deterministic | prose | - | GAP |
| SV-709 | skills/async-orchestration/SKILL.md | q: Phase 4 sets the flag at most once per session | base mismatch | Phase 4 sets the flag at most once and never emits; Phase 4.5 cleanup is the single emission | rule | prose | - | GAP |
| SV-710 | skills/async-orchestration/SKILL.md | q: **Exit FINALIZE.** Task is NOT yet marked completed, and the job file is | exit FINALIZE | task NOT marked completed, job NOT moved (Phase 4.5 completion tail does it) | rule | prose | - | GAP |
| SV-711 | skills/async-orchestration/SKILL.md | q: FINALIZE exits after PR | FINALIZE scope | exits after PR creation; job move and state completion live in Phase 4.5 | rule | prose | - | GAP |
| SV-712 | skills/async-orchestration/SKILL.md | q: Worker code lives in git branches until explicitly merged — can always | safety | worker code stays in branches until merged — always recoverable | rule | prose | - | GAP |
| SV-713 | skills/async-orchestration/SKILL.md | q: Worktrees are removed ONLY after successful merge | safety | worktrees removed ONLY after successful merge | rule | prose | - | GAP |
| SV-714 | skills/async-orchestration/SKILL.md | q: Merge conflicts always escalate to human | safety | merge conflicts always escalate to human | rule | prose | - | GAP |
| SV-715 | skills/async-orchestration/SKILL.md | q: Checkpoint includes which branches were merged and which remain | safety | checkpoint lists which branches were merged and which remain | rule | prose | - | GAP |
| SV-716 | skills/async-orchestration/SKILL.md | q: If EXECUTE_CHECKPOINT (partial): only merge subtasks whose | EXECUTE_CHECKPOINT (partial) | merge only subtasks whose outputs_verified gate passed; leave in-progress worktrees intact | deterministic | prose | - | GAP |
| SV-717 | skills/async-orchestration/SKILL.md | q: section (optional, #511):** one bullet per file the branch adds or modifies | branch adds/modifies files under docs/evidence/ | PR body ## Evidence lists them; omitted entirely when none | deterministic | prose | - | test-pr-body-evidence-seam.sh |
| SV-718 | skills/async-orchestration/SKILL.md | q: section (optional, harness-port/04):** aggregated by reading | any worker not_verified items | PR body ## Not verified aggregates them; omitted entirely when none; report-only | deterministic | prose | - | test-not-verified-transport-seam.sh |
| SV-719 | skills/async-orchestration/SKILL.md | q: ## Subagent Spawn Contracts | spawning any subagent | use the exact Task call shapes below | rule | prose | - | GAP |
| SV-720 | skills/async-orchestration/SKILL.md | q: **Prompt-cache discipline:** | spawn prompts | stable content before volatile interpolations (prefix prompt cache) | rule | prose | - | GAP |
| SV-721 | skills/async-orchestration/SKILL.md | q: **Pointers, not payloads (transport discipline):** | file-backed spawn input | pass path + ≤200-char summary, never the body; worktree-resident consumers get the MAIN-CHECKOUT absolute path | rule | prose | - | GAP |
| SV-722 | skills/async-orchestration/SKILL.md | q: **Context digest pointer (D6, v15.20.0):** | every worker spawn | carry the CONTEXT_DIGEST pointer (absolute for worktree workers); absent digest never blocks a spawn | rule | prose | - | test-context-digest.sh |
| SV-723 | skills/async-orchestration/SKILL.md | q: **Context-Keeper:** | Context-Keeper spawn | Task with state_file / operation / data prompt, subagent_type loomwright:context-keeper | rule | prose | - | GAP |
| SV-724 | skills/async-orchestration/SKILL.md | q: **Orchestrator:** | Orchestrator spawn | brief pointer + bounded summary; Beads mode points at bd show; cheap ⇒ model sonnet | rule | prose | - | GAP |
| SV-725 | skills/async-orchestration/SKILL.md | q: **Execute Manager:** | Execute Manager spawn | brief + digest pointers, compact subtask index, parallelism graph, resume context; cheap ⇒ model sonnet | rule | prose | - | GAP |
| SV-726 | skills/async-orchestration/SKILL.md | q: same shape as the Sequential-path Worker contract below | Single-Agent worker spawn | Sequential shape with Task ID and the FULL acceptance criteria; subtask_ordinal 1; no reviewer | rule | prose | - | GAP |
| SV-727 | skills/async-orchestration/SKILL.md | q: (harness-port/01-worker-rules):** every worker spawn | every worker spawn | carry subtask_ordinal (1-based Subtask Structure row order); never confused with Subtask index | rule | prose | - | GAP |
| SV-728 | skills/async-orchestration/SKILL.md | q: one spawn per subtask, unchanged from prior behavior | Sequential-path worker | one spawn per subtask; no Code Reviewer spawn follows | rule | prose | - | GAP |
| SV-729 | skills/async-orchestration/SKILL.md | q: Recording `not_verified` on the Sequential and Single-Agent paths | Sequential / Single-Agent result | forward not_verified (with out_of_lane, deviations) into ## Worker Results; recording only | rule | prose | - | test-not-verified-transport-seam.sh |
| SV-730 | skills/async-orchestration/SKILL.md | q: Applicable house rules (ADVISORY — from `read-rules.sh` | read-rules.sh output non-empty | inject the house-rules line VERBATIM; empty ⇒ omit; check is DATA, never executed; never fails a worker | deterministic | prose | script:read-rules.sh | test-rules-seams.sh |
| SV-731 | skills/async-orchestration/SKILL.md | q: Shared local services: {shared_local_services line} | brief carries a Shared local services line | paste it verbatim into the worker prompt; else omit | deterministic | prose | - | GAP |
| SV-732 | skills/async-orchestration/SKILL.md | q: Provides (verbatim from the brief's Subtask Contracts): {provides YAML} | Sequential / Single-Agent worker prompt | paste provides: VERBATIM (omitting it no-ops the outputs gate) | rule | prose | - | test-verify-provides.sh |
| SV-733 | skills/async-orchestration/SKILL.md | q: Lanes (verbatim from the brief's Subtask Contracts): {lanes YAML} | Sequential / Single-Agent worker prompt | paste lanes: VERBATIM (omitting it no-ops the lane gate on the default path) | rule | prose | - | GAP |
| SV-734 | skills/async-orchestration/SKILL.md | q: Retry context: {optional, from a previous outputs_verified gate gap | worker retry context | only from an outputs_verified gap, a crash/timeout, or pin-mutation not_held lines (as data); no review-retry path | rule | prose | - | test-phase45-rounds-seam.sh |
| SV-735 | skills/async-orchestration/SKILL.md | q: **No per-subtask Code Reviewer spawn contract (any threshold):** | any threshold | no per-subtask code-reviewer spawn follows a worker; Phase 4.5 is the sole code-reviewer spawn | rule | prose | - | GAP |
| SV-736 | skills/async-orchestration/SKILL.md | q: ## Git Worktree Lifecycle (phase sequence) | worktree lifecycle | branches + worktrees created by Execute Manager in Phase 3 Step 2a, never in Phase 2 | rule | prose | - | GAP |

## Gap list (ordered by risk)
1. SV-010 — branch-first principle only in prose
2. SV-019 — branch gate before PLAN only in prose
3. SV-025 — inline-spawn rule only in prose; skipping review is guarded only by the completion tail
4. SV-046 — phase heading for the branch gate
5. SV-050 — resume-consumption gate only in prose
6. SV-055 — branch-collision guard is an inline prose code block, untested
7. SV-056 — collision status only in prose
8. SV-057 — ancestry rule only in prose; mismatch breaks stacked iterations silently
9. SV-060 — remote-reconciliation gate only in prose
10. SV-072 — path-selection switch only in prose
11. SV-076 — fail-closed probe only in prose
12. SV-081 — default-path heading; most runs take it
13. SV-097 — review-bypass warning only in prose
14. SV-112 — partial-escalation routing only in prose; wrong branch merges failed work
15. SV-115 — adjudication routing only in prose
16. SV-119 — kind-not-prose dispatch only in prose
17. SV-120 — absent-means-requires_gap default only in prose
18. SV-121 — lane-collision option set only in prose
19. SV-122 — control-signal misuse would cause a spurious re-plan; only in prose
20. SV-123 — pause rule only in prose
21. SV-131 — acyclicity check only in prose; a cycle deadlocks execution
22. SV-140 — terminal-vs-replan distinction only in prose
23. SV-142 — no-auto-select rule only in prose
24. SV-143 — phase-entry routing only in prose
25. SV-144 — pre-merge gate only in prose
26. SV-149 — conflict stop only in prose
27. SV-151 — PR-base self-verify only in prose
28. SV-154 — single-emission rule only in prose
29. SV-156 — phase-entry routing only in prose
30. SV-158 — skip semantics only in prose
31. SV-159 — review mandate enforced only by a prose guard
32. SV-163 — hard-failure routing only in prose
33. SV-164 — completion-tail guard only in prose
34. SV-166 — guard abort only in prose; no test drives a skipped review
35. SV-167 — guard output only in prose
36. SV-168 — guard negative action only in prose
37. SV-169 — guard negative action only in prose
38. SV-178 — marker-reconcile rule only in prose; false negatives otherwise
39. SV-182 — single-emission rule only in prose
40. SV-201 — thrash counter only in prose
41. SV-206 — review-lane contract restated only in prose
42. SV-216 — checklist item only in prose
43. SV-233 — status mapping only in prose (validator checks shape, not mapping)
44. SV-234 — status mapping only in prose
45. SV-245 — inline-only rule lives in prose; delegation silently flips every gate to can't-ask
46. SV-246 — execution contract only in prose
47. SV-249 — review-bypass semantics only in prose
48. SV-266 — voter-cannot-flip rule only in prose
49. SV-270 — mirror of the agent branch guard; untested
50. SV-276 — marker-reconcile rule + awk snippet untested
51. SV-278 — placement rule only in prose
52. SV-306 — mirror of path selection; untested
53. SV-308 — review-lane rule only in prose
54. SV-315 — review-lane rule only in prose
55. SV-325 — error table only in prose
56. SV-329 — fallback stated only here and in troubleshooting; untested
57. SV-330 — inline mirror only in prose
58. SV-336 — closed enums restated here; drift risk vs state-management
59. SV-338 — fail-closed distinction only in prose
60. SV-349 — advisory-contract fail-safe only in prose
61. SV-361 — unverified-not-clean branch only in prose
62. SV-363 — advisory-only verdict rule only in prose
63. SV-376 — advisory-only rule only in prose
64. SV-379 — status derivation is pseudo-code; a nested test once hid a 100% capability loss
65. SV-391 — advisory-only rule only in prose
66. SV-412 — advisory-only rule only in prose
67. SV-419 — PASS-only builder gate only in prose
68. SV-440 — entry rule only in prose
69. SV-449 — guard input only in prose
70. SV-452 — single-increment rule only in prose
71. SV-453 — thrash guard only in prose
72. SV-454 — skip branch only in prose
73. SV-455 — cleanup trigger only in prose
74. SV-460 — clear-on-start invariant only in prose
75. SV-463 — single-exit rule only in prose
76. SV-467 — loop entry condition only in prose
77. SV-469 — loop bound is pseudo-code only
78. SV-473 — diff-scope override is prompt text only
79. SV-483 — sole-review framing is prompt text only
80. SV-485 — guard-input flip only in pseudo-code
81. SV-490 — CI conversion is pseudo-code only
82. SV-491 — floor conversion is pseudo-code only
83. SV-496 — loop exit is pseudo-code only
84. SV-497 — loop exit is pseudo-code only
85. SV-498 — fix selection is pseudo-code only
86. SV-500 — data-not-instruction rule is prompt text only
87. SV-503 — self-regression review is prompt text only
88. SV-505 — explicitly unvalidated: no hook enforces it
89. SV-506 — self-review gate is pseudo-code only
90. SV-510 — no-force rule only in pseudo-code
91. SV-512 — max-iteration escalation is pseudo-code only
92. SV-514 — gate-ownership rule only in prose
93. SV-515 — voter scope rule only in prose
94. SV-518 — merge rule only in prose
95. SV-519 — delay-vs-decide invariant only in prose
96. SV-522 — fully-refuted FAIL is a human call; only in prose
97. SV-531 — advisory rule only in prose
98. SV-536 — advisory contract only in prose
99. SV-545 — advisory contract only in prose
100. SV-547 — fail-safe invariant only in prose
101. SV-549 — crash-pause branch only in prose
102. SV-550 — guard pointer only in prose
103. SV-551 — outcome mapping only in prose
104. SV-552 — outcome mapping only in prose
105. SV-557 — no-early-stamp rule only in prose; a false done claim is unrecoverable
106. SV-569 — PASS-only builder gate only in prose
107. SV-582 — marker reconcile snippet untested
108. SV-589 — crash-pause branch only in prose
109. SV-594 — thrash branch only in prose
110. SV-602 — launchability rule is pseudo-code only
111. SV-606 — review-lane rule only in prose
112. SV-609 — review-lane rule only in prose
113. SV-614 — conflict rule only in prose
114. SV-615 — conflict rule only in prose
115. SV-620 — spawn-type rule only in prose; a wrong type silently disables every worker hook
116. SV-629 — hard budget exit is pseudo-code only
117. SV-635 — review-lane rule only in prose
118. SV-638 — materialization rule only in prose
119. SV-639 — HEAD-safety rule only in prose
120. SV-643 — invariant only in prose
121. SV-644 — invariant only in prose
122. SV-646 — conflict policy only in prose
123. SV-649 — hold-and-checkpoint branch only in prose
124. SV-651 — adjudication trigger only in prose
125. SV-652 — no-self-pick rule only in prose
126. SV-661 — fallback only in prose; untested
127. SV-666 — error table only in prose
128. SV-667 — error table only in prose
129. SV-668 — error table only in prose
130. SV-677 — review-lane rule only in prose
131. SV-679 — checklist is pseudo-code only
132. SV-691 — verification branch only in prose
133. SV-693 — conflict stop only in prose
134. SV-697 — fence ban only in prose
135. SV-700 — self-verify only in prose
136. SV-702 — retry policy only in prose
137. SV-708 — mismatch branch only in prose
138. SV-709 — single-emission invariant only in prose
139. SV-713 — safety guarantee only in prose
140. SV-714 — safety guarantee only in prose
141. SV-716 — partial-merge rule only in prose
142. SV-721 — pointer rule only in prose (POINTER_AUDIT lists exceptions)
143. SV-733 — lanes paste requirement only in prose
144. SV-735 — review-lane rule only in prose
145. SV-002 — safety rule only in prose
146. SV-003 — conflict-escalation rule only in prose
147. SV-007 — delegation rule only in prose
148. SV-011 — gate-verdict routing only in prose
149. SV-014 — tool-call budget only in prose; no counter enforces it
150. SV-018 — section heading; rules below carry the branches
151. SV-022 — orphan-worktree rule only in prose
152. SV-023 — sequential-merge rule only in prose
153. SV-024 — budget-exit branch only in prose
154. SV-038 — phase-entry routing only in prose
155. SV-039 — job-brief entry branch only in prose
156. SV-043 — read-on-start/clear-on-start flag handling only in prose
157. SV-044 — cost-profile resolution only in prose
158. SV-053 — vagueness judgment and PO spawn only in prose
159. SV-061 — pre-flight routing only in prose
160. SV-062 — soft-gate options only in prose
161. SV-064 — degradation branch only in prose; an inverted fail-closed would block runs
162. SV-066 — phase-entry Read only in prose
163. SV-067 — pointer-not-payload spawn rule only in prose
164. SV-069 — parallelism classification only in prose
165. SV-073 — parallelism rule is a prose code block, untested
166. SV-074 — phase heading for path routing
167. SV-075 — experimental branch only in prose
168. SV-078 — runner-result consumption only in prose
169. SV-079 — FINALIZE delta only in prose
170. SV-082 — spawn rule only in prose
171. SV-088 — carve-out routing only in prose
172. SV-098 — sequential-path heading only in prose
173. SV-100 — documented limit; parallel runs can overrun MAX_TOKENS
174. SV-104 — record-only lane rule only in prose
175. SV-109 — parallel delegation only in prose
176. SV-111 — result routing table only in prose
177. SV-113 — all-failed routing only in prose
178. SV-114 — checkpoint choice only in prose
179. SV-116 — crash routing only in prose
180. SV-117 — budget-exit routing only in prose
181. SV-124 — verbatim-option rule only in prose
182. SV-126 — option semantics only in prose
183. SV-127 — option semantics only in prose
184. SV-128 — option semantics only in prose
185. SV-129 — brief-mutation option only in prose
186. SV-130 — option semantics only in prose
187. SV-132 — option semantics only in prose
188. SV-133 — signal-suppressing option only in prose
189. SV-134 — apply step only in prose
190. SV-135 — apply step only in prose
191. SV-136 — apply step only in prose
192. SV-137 — apply step only in prose
193. SV-138 — apply step only in prose
194. SV-139 — apply step only in prose
195. SV-141 — apply step only in prose
196. SV-153 — scope-reduction rule only in prose
197. SV-155 — exit routing only in prose
198. SV-160 — invariant tracking only in prose
199. SV-161 — exit routing only in prose
200. SV-162 — exit routing only in prose
201. SV-165 — guard exception only in prose
202. SV-170 — guard record only in prose
203. SV-171 — guard negative action only in prose
204. SV-172 — guard exit only in prose
205. SV-176 — grader spawn condition only in prose
206. SV-180 — multi-voter merge rule only in prose
207. SV-181 — loop heading only in prose
208. SV-184 — return-to-base only in prose
209. SV-186 — loop-continue threshold only in prose
210. SV-187 — budget band only in prose
211. SV-189 — soft budget; no counter enforces it
212. SV-193 — budget band only in prose
213. SV-194 — budget band only in prose
214. SV-195 — budget band only in prose
215. SV-198 — flag semantics only in prose
216. SV-202 — error-table row only in prose
217. SV-203 — missing-result retry only in prose
218. SV-204 — error-table row only in prose
219. SV-209 — pointer heading only in prose
220. SV-215 — ownership rule only in prose
221. SV-217 — checklist item only in prose
222. SV-218 — checklist item only in prose
223. SV-219 — checklist item only in prose
224. SV-220 — checklist item only in prose
225. SV-232 — additive-field rule only in prose
226. SV-235 — phase-dependent mapping is ambiguous and only in prose
227. SV-237 — status mapping only in prose
228. SV-248 — brief lifecycle only in prose
229. SV-250 — iteration bound only in prose
230. SV-252 — cost-profile scope only in prose
231. SV-255 — brief/flag agreement only in prose
232. SV-257 — escape-hatch semantics only in prose
233. SV-269 — forward-set boundary only in prose
234. SV-271 — mirror of the agent pre-flight branches
235. SV-272 — loop summary only in prose
236. SV-274 — retired-workaround rule only in prose
237. SV-275 — ordering advice only in prose; stacking on a mutating branch
238. SV-277 — marker semantics only in prose
239. SV-280 — cross-layer write only in prose
240. SV-281 — closed terminal set only in prose
241. SV-282 — best-effort branch only in prose
242. SV-292 — gate table only in prose
243. SV-293 — gate table only in prose
244. SV-294 — gate table only in prose
245. SV-295 — gate table only in prose
246. SV-296 — lifecycle move only in prose
247. SV-297 — lifecycle move only in prose
248. SV-299 — resume priority only in prose
249. SV-303 — mirror of the agent budget bands
250. SV-304 — mirror of the agent budget bands
251. SV-305 — mirror of the agent budget bands
252. SV-307 — path heading
253. SV-311 — path heading
254. SV-313 — precedence rule only here
255. SV-314 — path heading
256. SV-317 — dependency wait only in prose
257. SV-318 — merge rule only in prose
258. SV-320 — permission table only in prose
259. SV-323 — error table only in prose
260. SV-324 — error table only in prose
261. SV-327 — error table only in prose
262. SV-328 — retry-once rule stated only in this table
263. SV-337 — recovery rule only in prose
264. SV-340 — opposite-remedy rule only in prose
265. SV-344 — troubleshooting advice only
266. SV-345 — fallback restated; untested
267. SV-346 — scope statement only in prose
268. SV-359 — line projection is pseudo-code only
269. SV-360 — projection branch only in prose
270. SV-362 — projection branch only in prose
271. SV-367 — reviewer carve-out only in prose
272. SV-368 — rubric lane rule only in prose
273. SV-374 — ordering rule only in prose
274. SV-380 — status derivation is pseudo-code only
275. SV-381 — status derivation is pseudo-code only
276. SV-382 — naming rule only in prose
277. SV-383 — no-op branch only in prose
278. SV-385 — status invariant only in prose
279. SV-386 — read-only rule only in prose
280. SV-394 — parse-miss branch only in prose
281. SV-402 — line projection is pseudo-code only
282. SV-406 — known gap only in prose
283. SV-408 — surfacing rule only in prose
284. SV-421 — no-fabrication rule only in prose
285. SV-422 — spawn shape only in prose
286. SV-428 — non-fatal branch only in prose
287. SV-432 — flat-only rule only in prose
288. SV-439 — numbering-stability rule only in prose
289. SV-448 — invariant init only in prose
290. SV-450 — init-order rule only in prose
291. SV-451 — resume counter only in prose
292. SV-456 — PR close branch only in prose
293. SV-457 — lifecycle move only in prose
294. SV-459 — documented residual: stale running status uncaught by any check
295. SV-461 — reset only in prose
296. SV-471 — pin-run routing only in prose
297. SV-474 — lens switch is prompt text only
298. SV-475 — checklist application is prompt text only
299. SV-476 — anti-overlap is prompt text only
300. SV-501 — class-sweep and cap are prompt text only
301. SV-504 — scope fence is prompt text only
302. SV-511 — re-review guarantee only in prose
303. SV-513 — flag resolution only in prose
304. SV-516 — provider branch only in prose
305. SV-517 — provider branch only in prose; lens-run.sh test not wired to this seam
306. SV-520 — edge rule only in prose
307. SV-521 — edge rule only in prose
308. SV-523 — fail-safe degradation only in prose
309. SV-525 — independence rule only in prose
310. SV-526 — no-alias rule only in prose
311. SV-529 — grader branch is pseudo-code only
312. SV-530 — grader rule only in prose
313. SV-533 — parse-failure branch only in prose
314. SV-535 — ordering pointer only in prose
315. SV-538 — placement rule only in prose
316. SV-540 — enable guard is pseudo-code only
317. SV-541 — risk branch is pseudo-code only
318. SV-542 — risk branch is pseudo-code only
319. SV-543 — comment branch only in pseudo-code
320. SV-544 — fail-safe branch only in pseudo-code
321. SV-546 — feed rule only in prose
322. SV-548 — recording rule only in prose
323. SV-554 — escalated Outcome shape only in prose
324. SV-559 — routing rule only in prose
325. SV-565 — fail-safe branch only in prose
326. SV-566 — reset only in prose
327. SV-570 — invariant restated only in prose
328. SV-572 — invariant restated only in prose
329. SV-573 — invariant restated only in prose
330. SV-576 — round-number formula only in prose (was wrong twice in review)
331. SV-581 — retired-workaround rule only in prose
332. SV-584 — placement rule only in prose
333. SV-588 — retry-once branch only in prose
334. SV-590 — push-failure branch only in prose
335. SV-593 — comment-failure branch only in prose
336. SV-595 — budget branch only in prose
337. SV-598 — quick rule only in prose
338. SV-600 — quick rule only in prose
339. SV-603 — overlap rule only in prose
340. SV-604 — path rule only in prose
341. SV-605 — path rule only in prose
342. SV-608 — path rule only in prose
343. SV-610 — ownership rule only in prose
344. SV-617 — conflict step only in prose
345. SV-619 — spawn shape only in prose
346. SV-622 — pointer rule only in prose
347. SV-623 — poll-loop ownership only in prose
348. SV-624 — poll bound is pseudo-code only
349. SV-625 — poll branch is pseudo-code only
350. SV-627 — launch branch is pseudo-code only
351. SV-628 — back-off is pseudo-code only
352. SV-631 — summary fallback only in prose
353. SV-632 — collection rule only in prose
354. SV-641 — step only in prose
355. SV-642 — ordering rule only in prose
356. SV-645 — invariant only in prose
357. SV-653 — option semantics only in prose
358. SV-654 — option semantics only in prose
359. SV-655 — option semantics only in prose
360. SV-656 — option semantics only in prose
361. SV-658 — presentation rule only in prose
362. SV-659 — error table only in prose
363. SV-660 — error table only in prose
364. SV-662 — error table only in prose
365. SV-664 — error table only in prose
366. SV-670 — checklist item only in prose
367. SV-674 — checklist item only in prose
368. SV-678 — numbering-stability rule only in prose
369. SV-680 — vacuous-pass rule only in prose
370. SV-690 — no_changes merge rule only in prose
371. SV-692 — commit step only in prose
372. SV-696 — commit format only in prose
373. SV-699 — PR base rule only in prose
374. SV-701 — retry policy only in prose
375. SV-703 — retry options only in prose
376. SV-704 — option only in prose
377. SV-705 — option only in prose
378. SV-706 — option only in prose
379. SV-707 — mismatch branch only in prose
380. SV-710 — scope-reduction rule only in prose
381. SV-711 — scope-reduction rule only in prose
382. SV-712 — safety guarantee only in prose
383. SV-715 — safety guarantee only in prose
384. SV-719 — spawn-contract heading only in prose
385. SV-724 — spawn shape only in prose
386. SV-725 — spawn shape only in prose
387. SV-726 — spawn shape only in prose
388. SV-727 — field rule only in prose
389. SV-728 — spawn rule only in prose
390. SV-736 — ownership rule only in prose
391. SV-001 — shared-prefix mission rule only in prose (mirrored by check-shared-prefix, not behaviour-tested)
392. SV-004 — output-shape default only in prose
393. SV-005 — section heading; principles below carry the branches
394. SV-006 — context-budget principle only in prose
395. SV-008 — parallelism principle only in prose
396. SV-012 — self-heal principle only in prose
397. SV-015 — enumeration heading; low risk
398. SV-016 — enumeration heading; low risk
399. SV-017 — escalation output trigger only in prose
400. SV-020 — context budget unmeasured
401. SV-027 — routing rationale; the Reads it justifies are rows of their own
402. SV-028 — routing rationale only
403. SV-029 — routing rationale only
404. SV-030 — routing rationale only
405. SV-031 — routing rationale only
406. SV-032 — records an accepted content loss; only in prose
407. SV-033 — routing rationale only
408. SV-034 — routing rationale only
409. SV-035 — routing rationale only
410. SV-036 — claim-scoping caveat only in prose
411. SV-037 — naming convention only in prose
412. SV-040 — on-demand Read rule only in prose
413. SV-042 — config echo only in prose
414. SV-049 — task-source branch only in prose
415. SV-051 — task-source branch only in prose
416. SV-052 — task-source branch only in prose
417. SV-054 — complement branch only in prose
418. SV-059 — checkpoint absence documented only in prose
419. SV-065 — skip-flag branch only in prose
420. SV-068 — cheap-profile override only in prose
421. SV-070 — sequential flag branch only in prose
422. SV-071 — pointer rule only in prose
423. SV-077 — known unforwarded flags only in prose
424. SV-080 — spike caveat only in prose
425. SV-083 — cheap-profile override only in prose
426. SV-089 — ownership rule only in prose
427. SV-092 — fail-safe branch only in prose
428. SV-096 — path tail only in prose
429. SV-101 — spawn rule only in prose
430. SV-102 — cheap-profile override only in prose
431. SV-108 — path tail only in prose
432. SV-173 — complement branch only in prose
433. SV-174 — rationale only
434. SV-183 — history save only in prose
435. SV-185 — interactive prompt only in prose
436. SV-188 — exit branch only in prose
437. SV-190 — budget caveat only in prose
438. SV-191 — budget caveat only in prose
439. SV-192 — budget band only in prose
440. SV-196 — context-budget table only in prose
441. SV-200 — error-table row only in prose
442. SV-205 — spawn table only in prose
443. SV-207 — summary templates only in prose
444. SV-210 — cost-profile rule only in prose
445. SV-213 — retention rule only in prose
446. SV-221 — checklist item only in prose
447. SV-222 — checklist item only in prose
448. SV-223 — checklist item only in prose
449. SV-224 — checklist item only in prose
450. SV-225 — checklist item only in prose
451. SV-226 — checklist item only in prose
452. SV-227 — checklist item only in prose
453. SV-229 — integration note only in prose
454. SV-231 — additive-field rule only in prose
455. SV-265 — flag precedence only in prose
456. SV-267 — flag precedence only in prose
457. SV-268 — provider switch only in prose
458. SV-283 — scope note only in prose
459. SV-285 — diagram heading; low risk
460. SV-286 — description heading only in prose
461. SV-287 — prerequisite only in prose
462. SV-288 — prerequisite only in prose
463. SV-289 — prerequisite only in prose
464. SV-291 — gate table only in prose
465. SV-300 — budget unenforced
466. SV-301 — budget unenforced
467. SV-302 — mirror of the agent budget bands
468. SV-310 — selection rule only in prose
469. SV-312 — path rule only in prose
470. SV-316 — concurrency bound only in prose
471. SV-319 — permission table only in prose
472. SV-321 — permission table only in prose
473. SV-322 — permission table only in prose
474. SV-326 — error table only in prose
475. SV-331 — benefit note only in prose
476. SV-332 — usage advice only in prose
477. SV-333 — troubleshooting advice only
478. SV-334 — troubleshooting advice only
479. SV-335 — troubleshooting advice only
480. SV-342 — incident rationale only
481. SV-343 — troubleshooting advice only
482. SV-347 — provenance only in prose
483. SV-348 — scope guard only in prose
484. SV-350 — read-once rule only in prose
485. SV-387 — run-condition only in prose
486. SV-395 — mapping only in prose
487. SV-403 — projection branch only in prose
488. SV-407 — state glossary only in prose
489. SV-410 — rationale only in prose
490. SV-420 — incident-map derivation only in prose
491. SV-423 — bound/dedupe rule only in prose
492. SV-424 — shape rule only in prose
493. SV-435 — shape rule only in prose
494. SV-436 — skip-form rule only in prose
495. SV-438 — reader default only in prose
496. SV-442 — read confirmation only in prose
497. SV-443 — retirement note only
498. SV-458 — record only in prose
499. SV-464 — field semantics only in prose
500. SV-465 — field semantics only in prose
501. SV-466 — reason disambiguation only in prose
502. SV-478 — prompt-line inclusion only in prose
503. SV-484 — cheap override only in prose
504. SV-492 — metric capture only in pseudo-code
505. SV-499 — pointer-audit exception only in prose
506. SV-524 — counter carriage only in prose
507. SV-527 — dual-role note only in prose
508. SV-528 — cost rationale only
509. SV-532 — grader rule only in prose
510. SV-534 — comment rule only in prose
511. SV-537 — channel rule only in prose
512. SV-556 — back-compat branch only in prose
513. SV-560 — record only in prose
514. SV-562 — history only
515. SV-563 — proposal step only in prose
516. SV-567 — record only in prose
517. SV-585 — placement rule only in prose
518. SV-586 — placement rule only in prose
519. SV-596 — quick rule only in prose
520. SV-597 — quick rule only in prose
521. SV-599 — quick rule only in prose
522. SV-601 — quick rule only in prose
523. SV-607 — path rule only in prose
524. SV-612 — naming rule only in prose
525. SV-616 — conflict step only in prose
526. SV-618 — conflict step only in prose
527. SV-630 — budget bands are pseudo-code only
528. SV-636 — budget table only
529. SV-637 — budget table only
530. SV-640 — step only in prose
531. SV-650 — rationale only
532. SV-663 — error table only in prose
533. SV-665 — error table only in prose
534. SV-669 — checklist item only in prose
535. SV-671 — checklist item only in prose
536. SV-672 — checklist item only in prose
537. SV-673 — checklist item only in prose
538. SV-675 — checklist item only in prose
539. SV-676 — checklist item only in prose
540. SV-720 — cache discipline only in prose
541. SV-723 — spawn shape only in prose
542. SV-731 — paste exception only in prose

## Counts
- rows: 736
- deterministic: 381
- judgment: 31
- rule: 303
- story: 21
- GAP: 542
