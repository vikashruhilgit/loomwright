# 00 — Orca-derived queue overview (index/policy doc — NOT an implementable item)

## Status: done (index document — nothing to implement; this stamp is the ONLY thing `resolve-folder` honours, so it is what keeps `/automate` from enqueuing this file)

**Origin:** 2026-09-11 analysis of Orca (onorca.dev, MIT, stablyai/orca) against the Floor UI and the
plugin's recorded incidents. **Authority above this queue:** `loomwright/docs/SPIKES/FINAL_STATE_GOAL.md`
(D1–D11, never re-litigated here) and `NORTH_STAR_DIRECTION.md` §"Explicit NOs". If an item and either
file disagree, the file wins and the item is amended.

## What was taken from Orca, and what was refused
Orca is an Electron IDE that HOSTS CLI agents (terminals, worktrees, browser, SSH, mobile). The plugin
runs inside it unchanged (verified from their docs: real `claude` PTY, `~/.claude` picked up, repo hooks
run, slash commands listed). **Refused — vendor parity:** terminals, editor, embedded browser, Design
Mode, SSH, mobile, account hot-swap, native chat, hibernation, "race three agents".
**Taken — five mechanisms + one strategic option + the owner's multi-model ask:**

| Item | Orca source | Closes |
|---|---|---|
| 01 agent-lifecycle-ledger | "runs agents, not terminals" — working/waiting/done/failed state machine fed by hooks | dead-worker silent no-op · drain marker ≠ completed · turn-limit unnoticed (all three in project memory) |
| 02 completion-authority | "provider *done* alone is not enough while children are still attached"; `worker_done` carries task+dispatch ids | self-reported `outputs_verified`; FINALIZE on a lead with unsettled children |
| 03 worker-checkpoints | `orca worktree set --comment` at named moments | `/handoff` + `/dreaming` see only end-of-run summaries; refuted hypotheses are lost |
| 04 rate-limit-park | "know how close you are before an agent stalls" | unattended `/automate` treats a rate-limit hit as a dead worker |
| `operator-run/04b` rate-limit-proximity-probe | same | operator-run probe: does a proximity source exist at all (split out of 04 §3 on 2026-09-12) |
| 05 floor-attention-and-feed | Agent Dashboard columns + Agents feed | Floor shows counts, never "needs you" or "what happened" |
| 06 orca-adapter | Orca CLI (`orca status --json`, `worktree set`, skills) | portability seam (adapter, never core) — the mirror script only |
| `operator-run/06b` orca-shell-evaluation | Orca as the D2 shell | step-10 D2 shell decision INPUTS, operator-run inside Orca (split out of 06 §B on 2026-09-12) |
| 07 provider-lens | "different agents make different mistakes" | a second review lens with genuinely different information (D4) |
| `operator-run/08` multi-model-steps | Orca orchestration `worker-start --agent codex` | owner ask: different models for different steps — planning/eval item, gated on 07 |

## Order (load-bearing)
01 → 02 → 05 (05 renders 01; 02 consumes 01) · 03 independent (shares only the emitter *conventions* with 01 —
its helper is a separate file, so it may run in parallel) · 04 independent · 07 independent · 06 after 03
(mirrors the checkpoint event) · 04b and 06b operator-run, any time · 08 blocked on 07's measurement.

## /automate handling
- 01, 02, 03, 04, 05, 06, 07 are normal code-change items — one file = one item, nothing inside them is operator-only.
- 04b, 06b and 08 are **operator-run planning/eval items** and live in `operator-run/`. **That subfolder is the
  skip mechanism** (verified 2026-09-12): `automate-helpers.sh resolve-folder` globs `"$dir"/*.md`
  non-recursively and honours exactly ONE stamp, `## Status: done` — it has no notion of `blocked`,
  `operator-run`, or "planning item", so a file with any other status in THIS folder WOULD be enqueued. Never
  move them back up; promote a finished probe by writing its findings into the code item it unblocks.
  They were split out on 2026-09-12 because `/automate` processes a FILE as one item and cannot skip a section.
- Every emitter added here is fail-SAFE (`exit 0`, `|| true`), every gate fail-CLOSED with a named reason —
  CLAUDE.md §"Failure-Mode Invariants" applies unchanged.
- D5 applies: new events are LOG lines; nothing here writes `state.md` directly.

## Verified facts this queue rests on (2026-09-11; re-verified and corrected 2026-09-12)
Corrections on 2026-09-12 came from reading `hooks.json`, the emitters, and the live `.supervisor/logs/`
(20,388 JSONL lines, 35 `StopFailure` lines) — not from memory. Items 01/02/04/05 were amended to match.

- `Notification[permission_prompt|idle_prompt|elicitation_*]` and `PreToolUse[AskUserQuestion]` run ONLY `notify-desktop.sh`
  (+ `send-webhook.sh`) — no JSONL line is written. `hooks.json`.
- **What SubagentStop actually records (corrected):** `token_ledger` (`emit-token-ledger.sh`; every role EXCEPT
  worker; 13,374 live lines) and `subtask_complete` (`emit-progress-event.sh`; the `loomwright:worker` matcher;
  6,803 live lines; fires on EVERY worker stop — it never parses `WORKER_RESULT`). **There is NO `agent_result`
  hook event** — 0 of 20,388 lines; it was a prompt-instructed event (4 total ever, `EVAL_FINDINGS_AND_FIXES.md`
  §measured miss rate), i.e. the class D5 deleted. Any item that said "agent_result" now means these two.
- **Result-block presence is recorded nowhere.** `validate-worker-result.py` prints its verdict to STDOUT (to the
  model), not to the log. "Ended without a result" is therefore NOT derivable from today's log; item 01 adds the field.
- `token_ledger` is SubagentStop-emitted, not per tool call — it is NOT a heartbeat.
- `PostToolUse` fires for a subagent's tool call with the MAIN session id (memory `subagentstop-payload-shape`).
  Untyped payloads hit MORE THAN ONE matcher block (measured 4,376 untyped → 2 lines each, comment in
  `emit-token-ledger.sh`); a matcher never identifies an agent.
- **Which thread a payload belongs to** is derived from the transcript basename, never the matcher:
  `agent_transcript_path` = `…/subagents/agent-<agent_id>.jsonl` ⇒ `agent_scope: subagent`; `transcript_path` =
  `<cc_session_id>.jsonl` ⇒ `main` (`emit-progress-event.sh` / `emit-token-ledger.sh`). `emit-agent-identity.sh`
  uses a DIFFERENT key — `tool_response.agentId` — which exists ONLY in `PostToolUse[Task]` payloads. Whether a
  `Notification` / `PreToolUse` payload raised INSIDE a subagent carries a subagent transcript path is
  **UNVERIFIED** (0 samples) — item 01 probes it first.
- `agent_identity` (74 live lines, all since 2026-09-07) carries `recorded_at`, deliberately NOT `ts`
  (`RESULT_SCHEMAS.md` §FLOOR_PROJECTION `identified_at`). A `ts`-keyed reader silently drops it.
- **`StopFailure` (corrected):** the hook appends `[ts] STOP_FAILURE <payload>` to `.supervisor/logs/failures.log`
  (plain text, NOT the session JSONL). The payload ALREADY carries a structured class:
  `"error": "rate_limit" | "server_error" | "authentication_failed" | "model_not_found" | "unknown"`
  (live counts 2 / 22 / 5 / 3 / 3) plus `session_id`, `transcript_path`, `last_assistant_message`. It carries
  **no `agent_id`**, and all 35 live lines are MAIN-session transcripts — `StopFailure` has never been observed
  for a subagent turn; whether it fires for one is UNVERIFIED.
- No local rate-limit-window file exists under `~/.claude` (`stats-cache.json` = usage history, last written
  2026-04-30; `policy-limits.json` = policy, mtime 2026-09-11). Orca's claim of reading one is UNVERIFIED for Claude.
- Installed agent CLIs on this machine: `claude`, `cursor-agent` (v2025.12.17-996666f, `-p --output-format json
  --model gpt-5|sonnet-4…`, print mode "has access to all tools, including write and bash" — NO read-only or sandbox
  flag; it DOES have `-f, --force  "Force allow commands unless explicitly denied"`, which implies print mode may
  deny shell commands by default — UNVERIFIED, item 07 probes it). `codex`, `gemini`, `grok`, `opencode`, `orca`:
  NOT installed.
- Claude Code subagent `model:` frontmatter routes to Claude models only; a non-Anthropic model is reachable
  from the plugin ONLY by shelling out to that vendor's CLI (the same shape as `claude -p` dispatchers).
- `--multi-voter-heal` has never executed: 0 `multi_voter` lines in any live JSONL (FINAL_STATE "NOT doing" keeps it).
- Anchors that do NOT exist yet and are CREATED by the item that names them: `loomwright/scripts/adapters/`
  (06, 07), `ARCHITECTURE_CONTRACTS.md` §"Portability" (06), config key `.voter_provider` (07),
  `checkpoint.sh` / `emit-lifecycle.sh` / `lens-run.sh` (03 / 01 / 07). `grep -rli orca loomwright/` is 0 hits today.
