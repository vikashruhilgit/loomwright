---
description: Autonomously manage development workflow with parallel execution from task pickup to PR creation
---

> **Execute this workflow inline as the main thread.** Do not delegate to `loomwright:supervisor-runner` via the Agent tool. A delegated runner is a subagent: it has no ask tool, so every question gate takes its can't-ask branch, and it spends a layer of subagent nesting depth — under a lowered host limit the workflow aborts with "Task/Agent tool unavailable" (`docs/ARCHITECTURE_CONTRACTS.md` §"Subagent nesting"). To run the agent in its own session instead, launch with `claude --agent loomwright:supervisor-runner`.

> **Execution contract:** Inline main-thread execution replaces only the top-level `supervisor-runner`. You MUST still spawn first-level child agents via the Task tool for every phase that requires them: `orchestrator` (Phase 2), `execute-manager` or Single-Agent/Sequential-path worker (Phase 3), and the Phase 4.5 `code-reviewer` + fix-task loop. Do NOT collapse the workflow into direct main-thread implementation. Phase 4.5 is mandatory unless `--skip-self-heal` was explicitly passed — reaching the completion tail without invoking `code-reviewer` and without the flag is an internal workflow error (enforced by the Phase 4.5 completion-tail guard, which lives verbatim in `agents/supervisor.md`; the full Phase 4.5 procedure lives in `skills/self-heal-advisory/SKILL.md` Part 2, Read at phase entry).

# Command: /supervisor

## Purpose

The Supervisor agent v4 autonomously manages the complete development workflow. It picks up tasks, delegates Phase 3 execution to the Execute Manager, orchestrates parallel workers via git worktrees, manages quality gates, and creates Pull Requests. Uses `.supervisor/` for all state management.

Every flag is in §Parameters below; invocation examples: `docs/rationale/supervisor.md`.

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `task:` | No | Specific task ID to work on (e.g., `task: BD-15` or `task: user-auth`) |
| `--max-workers N` | No | Maximum parallel worktrees (default: 2) |
| `--sequential` | No | Force sequential execution — no worktrees or parallelism |
| `--continue` | No | Resume workflow from last checkpoint. Resumed state is **schema-validated fail-closed**: before any loaded state is consumed, the `## Session` block must exist, `phase`/`status` must be in the closed enums, and any asserted `branch:` must `git rev-parse --verify` — per `skills/state-management/SKILL.md` §"Resume validation gate". An invalid file refuses the resume with `error: "resume_state_invalid"` (no override flag — inspect or delete `.supervisor/state.md`; see §"Checkpoints and Resume"). |
| `--dry-run` | No | Preview the workflow phases without executing any actions |
| `job:` | No | Path to Supervisor-Ready Brief from Launch Pad (e.g., `.supervisor/jobs/pending/{file}.md`) — skips Phases 0-2, moves brief through lifecycle (pending → in-progress → done/failed) |
| `--skip-self-heal` | No | **⚠️ Leaves NO semantic review at all — true at EVERY threshold, not just single-subtask jobs.** No Phase 3 path spawns a per-subtask reviewer (`agents/orchestrator.md` §"Review Gate Policy"), so Phase 4.5's Code Reviewer is the ONLY LLM review lens, and this flag bypasses it, leaving only the deterministic `outputs_verified` + tests/lint (plus the worker's own LSP diagnostics) gate. Bypass the Phase 4.5 integration review + fix loop. Phase 4.5 still transitions in state and runs the completion tail, but no review is performed. Use for emergency merges; the heal fields in SUPERVISOR_RESULT will show `heal_loop_ran: false`. **Absence of this flag makes Phase 4.5 mandatory** — reaching the completion tail without having invoked the `code-reviewer` Task is an internal workflow error (the completion-tail guard will emit `status: failed` and leave the job in `in-progress/`). |
| `--heal-iterations N` | No | Maximum self-heal fix iterations before escalating (default: 3). Each iteration is: integration review → fix task → re-review. Lower values escalate sooner; higher values attempt more fixes but risk never passing. |
| `--fix-floor <HIGH\|MEDIUM\|LOW>` | No | Lowest finding severity the Phase 4.5 review-and-fix loop **fixes**; anything below it passes and is recorded as a dismissed follow-up (BLOCKING is always fixed). Default **MEDIUM**; `.supervisor/config.json` `.fix_floor` sets it for every step (Launch Pad plan review, Phase 4.5, `/review-pr`), the flag overrides it for this run. An invalid value stops the run (`fix_floor_invalid`). Resolved by `scripts/fix-floor.sh`. |
| `--cheap` | No | Cost-optimized profile: spawns orchestrator, execute-manager, workers, code-reviewer, Phase 4.5 fix tasks, and — when `--multi-voter-heal` is ON — the multi-voter verification voters/refute spawn with `model: "sonnet"` override at spawn time. **N/A for a `--voter-provider` voter:** that path is a Bash shell-out to `lens-run.sh`, not a Task spawn, so there is no spawn-time `model:` override — the model comes from the `name:model` suffix. Default behavior (`inherit` for all) is unchanged when flag is absent. **Caution:** on Haiku sessions, listed roles upgrade to Sonnet (costs more). See `docs/ARCHITECTURE_CONTRACTS.md` §"Cost Profiles". |
| `--max-tokens N` | No | **Opt-in token-spend ceiling (red-team-hardening/06).** Parsed at Phase 0 INIT and recorded as a Phase Flag (same re-read-after-context-loss convention as `--non-interactive`). At Phase 0 INIT, also acquires `.supervisor/run.lock` (`scripts/run-lock.sh acquire --owner supervisor:<session_id> --session-id <session_id>` — `<session_id>` is the Claude Code runtime session id, matching `/automate` PICK's acquire shape, so a crashed session's lock is reclaimable) — a held lock PARKs the run BEFORE any work begins, printing `run_lock_held owner=<label> pid=<pid> age=<s>`, never proceeding silently (a `run_lock_reentrant owner=<outer> …` line, exit 0, is NOT a park: an enclosing `/automate`/`/autonomous` in the same session holds the lock — proceed; this run's own release is then a no-op; a `run_lock_degraded` stderr line, exit 0, means the lock is TTL-only and is NOT a park either — note it once and proceed); released at the completion tail / any Phase 4 abort. When `--max-tokens` is set, each Phase 3 poll-loop iteration entry sums this session's ledger via `scripts/read-token-ledger.sh --session <session_id>` and compares against N; a breach OR `LEDGER_UNREADABLE=1` ⇒ the run parks with `SUPERVISOR_RESULT.status: failed`, `error: "token_ceiling_reached"` before spawning another worker/reviewer round. Forwarded automatically by `/autonomous` and `/automate` when they were passed the same flag (see their own `--max-tokens` docs). Default: unset (no ceiling, byte-identical behavior). **Honest limit:** the ledger counts only what a SubagentStop hook saw — never this session's own main-thread tokens, never CI-side (`claude-review`) spend. No dollar conversion (no price table). See `docs/ARCHITECTURE_CONTRACTS.md` §"Token ceiling". |
| `--base-branch <name>` | No | Override the resolved base branch for FINALIZE PR creation. Default: the base `scripts/resolve-base-branch.sh` resolves (precedence: `skills/supervisor-config/SKILL.md` step 2.9b). Set by the `/autonomous` loop's multi-iteration mode so iteration N+1 stacks on iteration N's feature branch. The brief's `## Configuration` block may also carry a `Base Branch:` field — when present it MUST match this flag (Plan Reviewer validates the brief field independently). Phase 4 FINALIZE self-verifies the created PR's `baseRefName` matches this value and aborts via Phase 4.5 cleanup on mismatch. |
| `--non-interactive` | No | Suppress `AskUserQuestion` fallbacks; on `gh` failures and ambiguous gates, fail closed with a diagnostic instead of prompting. Executing as a subagent has the same effect (named statuses: `agents/supervisor.md` Can't-ask rule). Set automatically by the `/autonomous` loop when chaining iterations; rarely passed by humans. Recorded as a Phase Flag at Phase 0 so later phases can re-read after context loss. |
| `--skip-preflight-sync` | No | Short-circuit the Phase 1.5 PRE-FLIGHT SYNC gate, which reconciles the requested work against recent `origin/$BASE_BRANCH` commits and open PRs (same-file overlap + already-merged equivalents) and classifies the task CLEAR / OVERLAP / SUPERSEDED. The skip is recorded as a deliberate choice (`record_decision`) and `preflight_sync` is set to `skipped`. Escape hatch for when remote-overlap reconciliation is known-unnecessary or when intentionally re-doing landed work. Under `--non-interactive` / CI this is also the only way to proceed past an OVERLAP/SUPERSEDED classification (which otherwise fails closed). |
| `--skip-children-check` | No | Short-circuit Phase 4 FINALIZE's pre-merge safety-gate "children settled" check: every `agent_identity` row this session wrote, and every worker id recorded under `.supervisor/state.md`'s `## Worker Results` (passed as `--expect-id`), must have a matching terminal lifecycle row (`subtask_complete` / `token_ledger` / `agent_lifecycle: failed` / `agent_lifecycle: ended`) for the same `agent_id`, or the gate fails closed with `error: "children_unsettled: {ids}"` under `--non-interactive` (interactively, `AskUserQuestion`); ids are read from `### {worker-id} ({subtask-id})` headings and `agent_id:` / `worker_id:` keys, and a non-empty section with none refuses `worker_results_unparsed` (this flag bypasses that refusal too). The skip is recorded as a deliberate choice (`record_decision(phase: FINALIZE, decision: "user_skipped_children_check")`) and the run summary carries `children_check: skipped`. Escape hatch for a known-benign unsettled child (already resolved out-of-band) that should not block the merge. |
| `--no-until-mergeable` | No | Opt the auto-dispatched post-completion review drain OUT of `--until-mergeable`. **By default Supervisor auto-dispatches the until-mergeable drain after PR creation** — on a PASS/normal completion that produced a PR, Phase 4.5's completion tail launches a fresh, detached standalone review-and-heal run (`/review-pr` via the `loomwright:review-pr-runner` `--agent` form) and threads the until-mergeable signal (via env vars — see `skills/review-heal/SKILL.md` §"Until-Mergeable Dispatch Signal") so it drains ALL external review channels (required CI checks, bot reviews/threads/comments, check outputs). **The dispatched drain is heal-only by default** — under `--until-mergeable` it spawns no `code-reviewer` diff review of its own (only the `general-purpose` fix worker), with **exactly one earned-fallback exception**: when its own read shows no review lens actually posted (`no_review_lens_posted`), it runs exactly one diff review per drain run before declaring readiness, fail-CLOSED toward running it — see `skills/review-heal/SKILL.md` §"Earned Fallback Review" (semantics owned there, not restated here). **Ownership note:** `--until-mergeable` itself is a `/review-pr` flag, not a `/supervisor` flag — Supervisor never passes it literally; the dispatched runner receives the signal only through those env vars and forwards `--until-mergeable` to its own inline `/review-pr`. Passing `--no-until-mergeable` (or `.auto_until_mergeable: false`) makes the dispatched runner run the plain **diff-only** `/review-pr` loop instead. The drain **NEVER merges** and **NEVER waits on a human** (stops at terminal `READY`/`ESCALATED`, fires a best-effort notification on both). Default for `auto_until_mergeable` is **true**. |
| `--check-wait-timeout N` | No | Forward a scoped check-wait bound (seconds) to the auto-dispatched until-mergeable drain (the §"Wait-For-Settled-Checks" bound). Forwarded ONLY when set; threaded to the runner via `LOOMWRIGHT_CHECK_WAIT_TIMEOUT`. Config equivalent: `.check_wait_timeout`. No effect when the drain is opted out of `--until-mergeable`. |
| `--review-check-pattern <glob>` | No | Forward a review-producing-check selector glob to the auto-dispatched until-mergeable drain (widens the scoped wait/scan set per §"All-Channel Read"). Forwarded ONLY when set; threaded via `LOOMWRIGHT_REVIEW_CHECK_PATTERN`. Config equivalent: `.review_check_pattern`. No effect when the drain is opted out of `--until-mergeable`. |
| `--auto-review` | No | Legacy explicit-enable for the post-completion review-drain dispatch — redundant with the default (the drain dispatches after PR creation) but still honored. Equivalent to `.auto_review: true` in `.supervisor/config.json` (legacy `.supervisor/notify-config.json` is still read as a fallback; the new path wins when both exist). Best-effort and fire-and-forget — the dispatcher always exits 0 and never affects the Supervisor result, the PR, or control flow. Because `/review-pr` never creates a PR, there is no review→review recursion. |
| `--no-auto-review` | No | Suppress the post-completion review-drain dispatch **entirely** (no `/review-pr` run at all — neither until-mergeable nor diff-only), even when `.supervisor/config.json` has `.auto_review: true`. Equivalent to `.auto_review: false`. This is the master opt-out; `--no-until-mergeable` is the narrower opt-out (still dispatches, just without the drain). Wins over `--auto-review` if both are passed. |
| `--red-team` | No | Opt in to an advisory red-team review in Phase 4.5: after the Code Reviewer holistic pass, if the integrated diff is **high-risk** — per `scripts/classify-risk.sh --kind-table`, the ONE heuristic (committed once in `docs/RESULT_SCHEMAS.md` §SUPERVISOR_RESULT; not restated here) — spawn exactly ONE `red-team-reviewer` pass (outside the heal loop) and post its findings to the PR as a clearly-labelled non-gating comment. **OFF by default** and **high-risk-only** (enabled-but-low-risk skips silently). The classification itself runs **unconditionally** in Phase 4.5 and is recorded as `SUPERVISOR_RESULT.risk_classification` (`{high_risk, reasons}`, advisory); only the spawn is opt-in. **Advisory & strictly NON-GATING** — it NEVER changes `heal_decision`, never drives the fix task, never gates, and never blocks the PR; the Code Reviewer's `CODE_REVIEW_RESULT` remains the sole LLM gating signal (a stamped countable `must`-rule failure and a red required check are the deterministic co-gates). **Fail-safe** — any spawn error/timeout or comment failure is a logged no-op and the run continues. Equivalent to setting `.red_team_high_risk: true` in `.supervisor/config.json`. |
| `--no-red-team` | No | Suppress the advisory red-team review even when `.supervisor/config.json` has `.red_team_high_risk: true`. Wins over `--red-team` if both are passed. |
| `--multi-voter-heal` | No | **Opt in (default OFF)** to multi-voter Phase 4.5 verification: the review step spawns TWO independent parallel reviewers on the integrated diff — the existing `code-reviewer` (unchanged contract; its `CODE_REVIEW_RESULT` stays the sole LLM gating signal — a stamped countable `must`-rule failure and a red required check are the deterministic co-gates) plus a `red-team-reviewer` verification vote — and a BLOCKING/HIGH `new` finding is fixed ONLY if it survives the other lens's refute check (refuted findings are logged, not fixed; per-run `findings_raised`/`findings_refuted`/`findings_fixed` counters are carried in the `SUPERVISOR_RESULT` `summary` — additive prose, no schema bump). `heal_decision` (the gate) still derives ONLY from the code-reviewer's `CODE_REVIEW_RESULT` plus those deterministic co-gates; a surviving voter finding can only extend loop continuation within the existing `--heal-iterations` bound (a code-reviewer PASS finalizes once the surviving set is empty or the bound escalates) — the voter can DELAY finalization, never FLIP a decision. `--heal-iterations` bounds, never-merge, and the completion tail are unchanged. ~2× review spawns per iteration. Equivalent to `.multi_voter_heal: true` in `.supervisor/config.json`. **Not the standalone `--red-team` advisory lens** — independent flags, no aliasing (full merge rule + the `--red-team` interaction authority: `skills/self-heal-advisory/multi-voter.md` §"Multi-voter verification"). |
| `--no-multi-voter-heal` | No | Suppress multi-voter Phase 4.5 verification even when `.supervisor/config.json` has `.multi_voter_heal: true`. Wins over `--multi-voter-heal` if both are passed. Does not affect the standalone `--red-team`/`--no-red-team` advisory lens. |
| `--voter-provider <name>[:<model>]` | No | **Only meaningful with `--multi-voter-heal`.** Select which CLI casts the multi-voter verification vote. When absent (and `.supervisor/config.json` `.voter_provider` is absent/empty), the voter is the existing `loomwright:red-team-reviewer` Task — byte-identical default. When set (e.g. `cursor:gpt-5`), Phase 4.5 shells out to `${CLAUDE_PLUGIN_ROOT}/scripts/adapters/providers/lens-run.sh --provider <name>[:<model>]` instead of that Task. Flag wins over config (same precedence as `--multi-voter-heal`). Does not change `heal_decision`, the merge/refute rule, or never-merge. Protocol authority: `skills/supervisor-config/SKILL.md` step 2.9a and `skills/self-heal-advisory/multi-voter.md` §"Multi-voter verification". |
| `--route <seat>=<provider>[:<model>]` | No | Repeatable. Route one seat (read or write) to another provider for THIS run only. Parsed at Phase 0 INIT (`skills/supervisor-config/SKILL.md` step 2.9a) and forwarded unchanged as `--route` to every `resolve-routing.sh seat` call the run makes; it beats `routing.seats.<seat>` in `.supervisor/config.json` and loses to `--voter-provider` for `heal_voter`. A provider runs only when the user has granted it for this repo; absent the flag and any `routing` config, every seat runs on Claude exactly as before. The seat ids, precedence, consent rule and procedure live in `docs/PROVIDER_ROUTING.md` (seat lists: `resolve-routing.sh seats` and `write-seats`). Other commands read config only. |
| `--sdk-runner` | No | **EXPERIMENTAL — opt-in, default OFF.** When passed, Phase 3 EXECUTE shells out to the quarantined spike runner — `node "${CLAUDE_PLUGIN_ROOT}/sdk-spike/dist/runner.js" --brief <brief path> --branch <feature branch>` (cwd stays the user project; CLI contract: `sdk-spike/README.md`) — instead of Task-spawning `execute-manager` (or the inline Single-Agent/Sequential-path worker loop). **Fail CLOSED:** if `node` is unavailable (`command -v node` fails) OR `"${CLAUDE_PLUGIN_ROOT}/sdk-spike/dist/runner.js"` is absent OR the SDK dependency does not resolve (`(cd "${CLAUDE_PLUGIN_ROOT}/sdk-spike" && node -e "require.resolve('@anthropic-ai/claude-agent-sdk')")` fails — catches `node_modules/` pruned after the build) when the flag is passed, the run aborts with `error: "sdk_runner_unavailable"` — it NEVER silently falls back to the default path. Error guidance: `dist/` is gitignored and marketplace installs ship source only — build once with `npm install && npm run build` inside `${CLAUDE_PLUGIN_ROOT}/sdk-spike`. The runner emits an **EXECUTE_RESULT-equivalent** block consumed exactly as if it came from the Execute Manager. **FINALIZE delta:** the runner pre-commits each subtask's work on its `sdk-spike/subtask-N` branch and removes its worktrees on exit, so when consuming a runner-emitted result the Phase 4 FINALIZE procedure (`skills/async-orchestration/SKILL.md` Part 2, steps 1–7) adjusts: **(a)** step 1 verifies BRANCHES instead of worktrees — each `merge_order` branch exists (`git branch --list sdk-spike/subtask-*`) and is ahead of the feature branch (`git log <branch> --not <feature-branch> --oneline` non-empty) — skipping the worktree-exists/dirty checks; **(b)** skip step 2 entirely (work already committed by the runner); **(c)** step 4 tolerates already-removed worktrees and deletes the `sdk-spike/subtask-N` branches after merge (the runner keeps them by contract). Steps 3 and 5–7 are unchanged. The brief's Max-workers and the `--cheap` cost profile are NOT threaded to the runner in this spike (its `--max-workers`/`--model` flags exist but are unforwarded; default 2 concurrent lanes). Zero change to the default path when the flag is absent (byte-identical behavior with flag off). Spike-grade (see `docs/SPIKES/SDK_RUNNER_SPIKE.md`): `hooks.json` validators may not fire for SDK-spawned workers — the runner self-validates result schemas. Both experimental flags (`--sdk-runner`, `--multi-voter-heal`) are **supervisor-only**: deliberately NOT forwarded by `/autonomous` or `/automate` (their forward set stays exactly four flags — `--base-branch` / `--non-interactive` / `--cheap` / `--max-tokens`, red-team-hardening/06); reachable only via a direct `/supervisor` invocation or the eval's arm-3 procedure (`docs/SPIKES/FABLE_PARITY_EVAL.md`). |
| `--legacy` | No | Run Phases 0–4 from the pre-driver prose in `docs/supervisor-legacy-phases.md` instead of `scripts/supervisor-next-step.sh`. Phase 4.5 and Phase 5 are unchanged. The same file serves the runs the driver does not cover — `--continue`, a run with no `job:` brief, `--sdk-runner` — see §"Next-step driver (Phases 0–4)". Supervisor-only: `/autonomous` and `/automate` do not forward it. |

## Next-step driver (Phases 0–4)

Phases 0–4's deterministic sequencing and bookkeeping run through ONE script, `scripts/supervisor-next-step.sh` under the plugin install root, which hands this main thread exactly ONE instruction per call. The judgment stays yours: every spawned agent's work, the Phase 1.5 classification, the merges / commits / push, and every answer to an `ask`.

1. **Entry (Phase 0).** Run the run-lock acquire first (`skills/supervisor-config/SKILL.md` step 5a.0 — a `run_lock_held` line parks the run there), then call `supervisor-next-step.sh --session-id <sid> --job <brief>` ONCE with the run's flags: `--non-interactive` (also when `/autonomous` passed it), `--subagent` when this run executes as a subagent (the Can't-ask rule), `--cheap`, `--max-tokens N`, `--base-branch B`, `--skip-preflight-sync`, `--skip-children-check`, `--sequential`, `--max-workers N`. `<sid>` is this Claude Code session's id — the run lock's `--session-id`. The flags persist in the driver's gitignored sidecar (`.supervisor/logs/<sid>.supervisor-next-step.json`); never re-pass them.
2. **Loop.** Do what the printed instruction says, then call `supervisor-next-step.sh --session-id <sid> --result '<json>'` with its answer. `spawn` ⇒ make that spawn per `skills/async-orchestration/SKILL.md` Part 2 §"Subagent Spawn Contracts" (a `context-keeper` spawn applies its `ops` in order — the driver never writes `.supervisor/state.md`; a `worker` spawn's `gates` are yours before you answer). `ask` ⇒ ask it with its `question`, `options` and `header` verbatim and hand back the chosen label — never pick one yourself; `{"cant_ask": true}` when you cannot ask. `park` ⇒ stop and emit `SUPERVISOR_RESULT` with its `status` / `error`. A call with no `--result` re-prints the pending instruction byte for byte. Exit 2 = the `--result` did not answer what is pending (nothing written — correct it and call again); exit 1 = a write or helper failed (call again with no `--result` to retry that step).
3. **Hand-over.** `done` (`step: handover`) ends Phase 4: go to Phase 4.5 (`skills/self-heal-advisory/SKILL.md` Part 2) with its fields — `base_mismatch_detected: true` ⇒ Phase 4.5's base-mismatch cleanup; `escalation` ⇒ report the failed subtasks as an escalation in this run. Phase 4.5 and Phase 5 are unchanged prose.

Instruction and `--result` shapes, every `step` and `what` value: `docs/result-schemas/supervisor-result.md` §"supervisor next-step instruction" (the authority — not restated here).

**Legacy path.** `/supervisor --legacy` runs Phases 0–4 from `docs/supervisor-legacy-phases.md` — the pre-driver prose — and never calls the driver. The same file serves the runs the driver does not cover: `--continue` (once the Resume validation gate passes, resume the saved phase from it), a run with no `job:` brief (`task:`, interactive or auto-selected), and `--sdk-runner` (the driver does not run the SDK runner). Nothing else changes on that path.

## What This Does

The Supervisor executes a **7-phase parallel workflow** — INIT → ACQUIRE → PRE-FLIGHT SYNC → PLAN → EXECUTE → FINALIZE → SELF_HEAL → LOOP (1.5 and 4.5 are sub-phase gates; overview diagram: `docs/rationale/supervisor.md`).

**Phase 0 (INIT):** the run-lock acquire, the fail-closed Resume validation gate on `--continue`, the config questions a `job:` brief does not pre-answer and the Phase 4.5 flags run from `skills/supervisor-config/SKILL.md` (Read at phase entry — deliberately not preloaded); the rest of INIT — the `.supervisor/` bootstrap, the brief's `pending/` → `in-progress/` move, the run config, the guard arm, the Context-Keeper `initialize` and the Phase Flags — is the driver's `init` step (§"Next-step driver (Phases 0–4)" above). `agents/supervisor.md` "Phase 0: INIT" keeps the short phase stanza. The flag table above is this command's authority for flag syntax.

**Phase 1 (ACQUIRE):** task selection (`agents/supervisor.md` "Phase 1: ACQUIRE" actions 0–3 — a `job:` brief pre-answers 1–3) stays yours; the mandatory feature-branch creation is the driver's `acquire` step — idempotent: an existing same-named branch is reused only when its tip equals the fetched `$BASE_BRANCH` tip, otherwise the run parks `error: "acquire_branch_collision"` and deletes nothing.

**Phase 1.5 (PRE-FLIGHT SYNC):** the driver's `preflight` step has you run `skills/preflight-sync/SKILL.md` actions 2–5 (Read at phase entry) — the bounded CLEAR / OVERLAP / SUPERSEDED reconciliation of the requested work against recent `origin/$BASE_BRANCH` commits and open PRs; the classification is yours — and routes your report: CLEAR proceeds silently, UNVERIFIED proceeds with one warning, OVERLAP / SUPERSEDED asks (proceed-anyway / revise-scope / abort) or, under `--non-interactive`, fails closed with `preflight_overlap_detected`; `--skip-preflight-sync` skips it as a recorded choice.

**Phase 4 (FINALIZE):** the driver runs the gates — pre-merge points 1–4 (`finalize`), point 5's children-settled check (`finalize-children`), the finalize-gate marker (`finalize-marker` → `guard-finalize-publish.sh write-marker`) and the step 6.5 PR-base self-verify with its one retry (`pr-verify`). The merge / commit / push / PR work it hands you as `finalize-merge` and `finalize-publish` spawns follows `skills/async-orchestration/finalize.md` — the async-orchestration **Part 2 — Supervisor FINALIZE Protocol** the driver's `SKILL.md Part 2` strings name (steps 2–6 and the PR Body Template — Read at Phase 4 entry; Phase 2 does not need it) — and `skills/commit/SKILL.md`. `agents/supervisor.md` "Phase 4: FINALIZE" keeps the mandatory gate list (pre-merge safety gate, merge-conflict STOP, salvage before remove, PR-base self-verify).

**Phase 4.5:** After the PR is created, Supervisor runs a holistic Code Reviewer on the full feature-branch diff. If it finds `new` issues at or above the fix floor (`--fix-floor` / `.fix_floor`, default MEDIUM — so BLOCKING, HIGH and MEDIUM), Supervisor spawns a fix task that addresses them and pushes updates to the PR. The loop retries up to `--heal-iterations` times (default 3). Heal rounds ≥ 2 are shaped by `.supervisor/config.json` `.heal_review_scope` (default `shadow`, which reviews exactly as before and only records what a review of the last fix's files would cover; see `skills/supervisor-config/SKILL.md` step 2.11). On PASS the task is marked `completed`; on NEEDS_HUMAN or max iterations the task is marked `completed_with_escalation` with findings posted as a PR comment. The phase always runs (unless `--skip-self-heal` short-circuits the loop); it owns the completion tail (job-file move, state marked completed) so the record captures the heal outcome. **Protocol authority:** `skills/self-heal-advisory/` **Part 2**, split by when each part runs — at Phase 4.5 entry on BOTH the inline and delegated paths `Read("${CLAUDE_PLUGIN_ROOT}/skills/self-heal-advisory/SKILL.md")` (every iteration) and `on-entry.md` from the same directory (on-entry actions, first-iteration enrichments); `escalation.md` only on base-mismatch cleanup or a fix-task crash, `multi-voter.md` only when `MULTI_VOTER_HEAL` is true, `completion-tail.md` once the loop exits or is skipped (none preloaded). `agents/supervisor.md` keeps the short phase stanza plus the verbatim completion-tail guard.

**Until-mergeable review drain (default on):** the SAME completion tail then **auto-dispatches a detached until-mergeable review drain** against the PR (`scripts/dispatch-pr-review.sh` → the `loomwright:review-pr-runner` `--agent` form); it is fire-and-forget, never merges, never waits on a human, and never affects `SUPERVISOR_RESULT` or control flow. Opt out of the drain with `--no-until-mergeable`, or out of the dispatch entirely with `--no-auto-review`. Procedure: `skills/self-heal-advisory/completion-tail.md` step 5.5; readiness: `skills/review-heal/SKILL.md` §"READY redefinition".

> **Timing note — drain is working-tree-isolated (do NOT suppress for the self-heal race).** The hook backstop may dispatch the drain one phase earlier, alongside the inline self-heal — harmless, it runs in its own worktree. **Do NOT write `.supervisor/config.json {"auto_review": false}` for this race — that workaround is retired now that the drain is working-tree-isolated.** Mirrors `skills/self-heal-advisory/completion-tail.md` step 5.5 "Hook backstop" — keep the two in sync.

> **R9 — downstream ordering (branch-dependent work must wait for the drain).** The detached drain may keep pushing after the run completes, so a stacked `/autonomous` iteration or a human merge SHOULD wait for its terminal `READY` / `ESCALATED` (trail: the job `## Outcome` block's `**Until-mergeable dispatched:**` / `**Until-mergeable log:**` lines, plus the drain's notification); a human may proceed earlier, accepting the branch may still change.

**Observability — reconcile `until_mergeable_dispatched` from the MARKER, not from "did I dispatch" (load-bearing on the inline path).** On the inline path the hook backstop dispatches out-of-band and returns no signal, so **NEVER record `until_mergeable_dispatched: false` because you skipped (or are unsure about) the step-5.5 dispatch** — resolve it from the per-PR marker BODY (exact-URL match, no prefix confusion):
```bash
if awk -v url="{PR_URL}" '$0 == url || $2 == url { found=1; exit } END { exit(found ? 0 : 1) }' .supervisor/review-dispatch/* 2>/dev/null; then
  UM_DISPATCHED=true
  UM_LOG="$(grep -rlF "$(printf 'url=%s\t' "{PR_URL}")" .supervisor/logs/review-pr-dispatch-*.log 2>/dev/null | head -1)"
else
  UM_DISPATCHED=false; UM_LOG=
fi
```
Record `until_mergeable_dispatched: {UM_DISPATCHED}` (and `until_mergeable_log: {UM_LOG}` only when true and a log was found) on the job `## Outcome` block + `session_end` JSONL. A marker exists IFF the dispatcher ran for this PR, so `false` is truthful ONLY when no marker exists. Mirrors `skills/self-heal-advisory/completion-tail.md` step 5.5 "Observability (AC8b)" (kept here because the inline path loads this file) — keep the two in sync; best-effort, never gates.

### Inline-path canonical state writes (Phase 1 ACQUIRE + Phase 4.5 completion tail)

> The inline `/supervisor` and `/autonomous` paths run this workflow on the main thread from this file and never load `agents/supervisor.md`, so these directives live here too.

**`.supervisor/state.md`'s `## Session` block (`session_id`/`branch`/`status`/`phase`) is not written by the Supervisor on any path.** It is derived by the hook-triggered `scripts/emit-progress-event.sh` — fired at the `loomwright:worker` `SubagentStop` hook, which fires on the inline path too, since the Single-Agent and Sequential paths both spawn a worker Task — and projected into `.supervisor/state.md` by `scripts/build-state.sh` (`docs/TELEMETRY.md`). Mirrored in `agents/supervisor.md` Phase 1 ACQUIRE step 5 and `skills/self-heal-advisory/completion-tail.md` step 4 — keep the three in sync.

**Phase 1 ACQUIRE — `/autonomous`-only `state.json` write (Fix B producer):** In the SAME ACQUIRE location (after branch creation, before `gh pr create`), **when the inline Supervisor is running under `/autonomous`** — i.e. the autonomous loop inlined this `commands/supervisor.md` at its EXECUTE step and an active `.supervisor/autonomous/{session_id}/state.json` exists for THIS run — additionally update that ONE `state.json` with two **top-level** fields:
- `current_branch`: string — the feature-branch name just created.
- `current_status`: the literal string `"running"` — a POSITIVE, non-terminal active status set at ACQUIRE. The **terminal status set** (the consumer hook treats these as NOT-active) is exactly: `completed`, `completed_with_escalation`, `failed`, `aborted`, `done`, `paused_max_iterations`.

  **Run by the driver's `acquire` step:** the active session is the one whose `current_brief_path` basename matches this `job:` brief (among sessions with `ended_at` null); ambiguous or none ⇒ the write is skipped; a jq temp-file + rename update; best-effort — never gates or fails the run. The pre-driver text of this paragraph is in `docs/supervisor-legacy-phases.md`.

  **Note:** this `state.json` write does NOT help the direct `/supervisor job:` path (there is no autonomous `state.json` there) — the `scripts/emit-progress-event.sh` + `scripts/build-state.sh` projector (pointer above) is the cross-path producer of the session branch the hook reads.

**Phase 4.5 completion tail — terminal status:** `.supervisor/state.md`'s terminal `- status:` (`completed` / `completed_with_escalation` / `failed`) is derived by `scripts/build-state.sh` from the run's `session_end` event (see the pointer above) — it is not flipped here on any path. (The autonomous `state.json` is NOT flipped at completion here — the consumer additionally guards on `ended_at` being null and the `current_brief_path` basename being present in `jobs/in-progress/`, so a stale `state.json` with `current_status:"running"` but a moved-out brief is correctly rejected.)

## Prerequisites

1. **Git repository:** Project must be a git repo
2. **Clean git state:** No uncommitted changes (or approve stashing)
3. **GitHub CLI:** `gh` installed and authenticated (for PR creation)

## Result block

The `SUPERVISOR_RESULT` block (schema v1, validated by the SubagentStop hook) is emitted from Phase 4.5's completion tail — one block per task. Phase 5 LOOP emits nothing. In multi-task sessions, multiple blocks appear in order; the hook validates the last one. See `docs/RESULT_SCHEMAS.md` for the full schema.

## Gate Decisions

Per-subtask, the deterministic `outputs_verified` + tests/lint gate decides:

| Decision | Action |
|----------|--------|
| **PASS** | Continue; launch newly unblocked subtasks |

Phase 4.5's holistic Code Reviewer (the sole LLM review, run once after FINALIZE) decides:

| Decision | Action |
|----------|--------|
| **PASS** | Mark task completed |
| **FAIL** (< `--heal-iterations`) | Spawn fix worker with retry context |
| **FAIL** (max iterations) | Checkpoint, escalate to human |
| **NEEDS_HUMAN** | Checkpoint, pause, exit with resume command |

## State Persistence

```
Active session:   {scratchpad}/supervisor-state.md
Persistent:       {project}/.supervisor/state.md
History:          {project}/.supervisor/history/{date}-{task}.md
Jobs lifecycle:   {project}/.supervisor/jobs/
  ├── pending/      ← Launch Pad saves briefs here
  ├── in-progress/  ← Supervisor moves brief here on ACQUIRE
  ├── done/         ← Phase 4.5 SELF_HEAL completion tail moves here (on PASS, loop-skipped, OR ESCALATED — in all cases, with an `## Outcome` block that records heal_loop_ran, heal_decision, heal_iterations, heal_remaining_issues, test_guard)
  └── failed/       ← Supervisor moves here on hard failure (merge conflict, fix-task crash after retries) before 4.5 completion tail could run
Logs:             {project}/.supervisor/logs/{session_id}.jsonl
```

The `.supervisor/` directory is auto-created and gitignored.

## Checkpoints and Resume

The Supervisor does not checkpoint on every phase transition — `.supervisor/state.md`'s `## Session` block is derived automatically (not agent-written) at each worker completion and at session end (`docs/TELEMETRY.md`), so a pause (NEEDS_HUMAN, merge conflict, context limit) resumes from the most recently derived `state.md`: `/supervisor --continue [task: <id>]`.

**Checkpoint data includes:**
- Current phase and status (`## Session` — derived from the session's event log by `scripts/build-state.sh`, not written by Context-Keeper or the Supervisor; see `skills/state-management/SKILL.md` §"Progress state")
- Branch name and worktree state
- Worker tracking
- All decisions and results

**Resume priority:**
1. Scratchpad state (same session)
2. `.supervisor/state.md` (cross-session)

**Resume refusals (fail-closed — the Supervisor never silently falls back to a fresh start on an invalid file; a *missing* state file still starts fresh):**
- `resume_state_invalid` — the loaded state failed the **resume validation gate** (missing `## Session`, `phase`/`status` outside the closed enums, or an asserted `branch:` that `git rev-parse --verify` rejects; `skills/state-management/SKILL.md` §"Resume validation gate"). Recover: fix the offending field in `.supervisor/state.md`, or delete it and start fresh without `--continue` — deliberately no override flag.
- `resume_state_stale` — the file is schema-valid but behind reality: `scripts/reconcile-resume-state.sh` found subtasks it lists as pending already committed on the branch. Recover: **do NOT delete the state file**; correct the `Status` of each printed `stale_subtask:` row and `--continue` again (or delete it deliberately to start fresh). `VERDICT: UNKNOWN` (ground truth unreadable) also refuses — this gate fails closed.

## Context Management

The Supervisor uses externalized state and tool call budgets:

- **Supervisor:** 50 tool call budget (~400 tokens context)
- **Execute Manager:** 60 tool call budget (isolated context for Phase 3)
- **State file:** `## Decisions Log` / `## Worker Results` / `## Error Log` / `## Phase Flags` managed by Context-Keeper; the `## Session` block is derived (see `skills/state-management/SKILL.md`)
- **Workers:** Run in background with their own isolated context
- **Reviewers:** Run in background with their own isolated context

**Tool call thresholds (Supervisor):**
- 0-30 (60%): GREEN — normal operation
- 30-40 (80%): YELLOW — aggressive compression
- 40-46 (92%): RED — force checkpoint, suggest new session
- 46+: RED — checkpoint + exit with resume command

## Execution Paths

Path selection is by subtask count, per `skills/supervisor-readiness/SKILL.md` §"Decomposition Threshold": exactly 1 subtask → Single-Agent Path; `--sequential` with more than 1 subtask → Sequential Path; otherwise → Parallel Path.

### Single-Agent Path (exactly 1 subtask, default below threshold)
- One worker executes ALL acceptance criteria in a single context (no worktree overhead)
- **No per-subtask Code Reviewer spawned** — Phase 4.5's holistic Code Reviewer is the single review of the integrated result
- Deterministic gate only (`outputs_verified`/`outputs_gap` plus tests/lint on the branch (LSP diagnostics are the worker's own, run during implementation — the Supervisor has no LSP tool))
- Automatic, no flag needed — selected by subtask count, not by `--sequential` (see `agents/supervisor.md` §"Single-Agent Path")

### Sequential Path (`--sequential`, more than 1 subtask)
- All subtasks execute one at a time, no git worktrees created
- **No per-subtask Code Reviewer spawned** — the deterministic `outputs_verified`/tests-lint gate is each subtask's gate, and Phase 4.5's holistic Code Reviewer is the sole LLM review (`agents/orchestrator.md` §"Review Gate Policy"); a distinct path from Single-Agent above, selected by the flag rather than subtask count. **Single-Agent takes precedence at a count of 1:** `--sequential` on a single-subtask brief resolves to the Single-Agent Path
- Useful for debugging or constrained environments

### Parallel Path (multi-subtask, default above threshold)
- Independent subtasks run concurrently in git worktrees
- **No per-subtask Code Reviewer spawned** — same deterministic gate as every other threshold; Phase 4.5's holistic review is the sole LLM review (see `agents/orchestrator.md` §"Review Gate Policy")
- Max `--max-workers` concurrent workers (default: 2)
- Subtasks with dependencies wait for predecessors
- Sequential merge into feature branch after completion

## Permissions

| Phase | Approval |
|-------|----------|
| INIT (config) | Interactive (AskUserQuestion) |
| ACQUIRE (branch) | **[APPROVAL NEEDED]** |
| PRE-FLIGHT SYNC (overlap recon) | Auto on CLEAR; **[APPROVAL NEEDED]** on OVERLAP/SUPERSEDED (AskUserQuestion); fail-closed under `--non-interactive` |
| PLAN (decompose) | Auto (subagent) |
| EXECUTE (implement) | **[APPROVAL NEEDED - batch]** |
| FINALIZE (commit+PR) | **[APPROVAL NEEDED]** |
| LOOP (next) | Auto |

## Error Handling

| Error | Supervisor Action |
|-------|-------------------|
| Review FAIL (3x) | Checkpoint, escalate to human |
| NEEDS_HUMAN | Checkpoint, pause, exit with resume |
| Merge conflict | STOP, report files, exit with resume |
| No ready tasks | Exit gracefully |
| Tool budget exceeded | Checkpoint, exit with resume |
| Worker crash | Retry once, then escalate |
| Worktree fails | Fall back to sequential mode |

**Rule:** Never force-resolve merge conflicts — a merge conflict always STOPs the run and escalates to a human (mirrored from the shared agent prefix; inline command surfaces never load the agents/*.md block).

## More

Dry-run output, the plan-first workflow with Launch Pad, troubleshooting, related commands and further reading: `docs/rationale/supervisor.md`.
