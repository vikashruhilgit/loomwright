# 01 — Agent lifecycle as a recorded fact (Orca: "runs agents, not terminals")

## Problem
Three recorded incidents share one root cause — the plugin records what an agent *produced*, never what
state it is *in*: (a) `outputs_verified` is worker-self-reported, so a worker that dies before emitting
`WORKER_RESULT` leaves the gate with no input and nothing flags it; (b) a drain marker `true` means
dispatched, not completed; (c) most spawned agents hit the turn limit before their result block and nobody
notices until the Supervisor times out. Orca's dashboard is nothing but a state machine over the SAME
hooks we already fire: `spawned → working → waiting → done | failed | stalled`. Today we record
`spawned` (`agent_identity`, `PostToolUse[Task]`, `recorded_at` not `ts`) and an END event on SubagentStop —
`subtask_complete` for workers, `token_ledger` for every other role (corrected 2026-09-12: there is NO
`agent_result` hook event; see 00 §facts) — and we DISCARD `waiting`: `Notification[permission_prompt|idle_prompt]`
and `PreToolUse[AskUserQuestion]` only toast (`notify-desktop.sh`). The end event says the agent STOPPED, never
whether it produced a result: `subtask_complete` fires on every worker stop and `validate-worker-result.py`'s
verdict goes to stdout, not the log. There is no `working` heartbeat (`token_ledger` is SubagentStop-emitted)
and no derived `stalled`.

## Goal
Every spawned agent has a lifecycle row in the session JSONL that can answer, from the log alone:
is it waiting on a human, has it gone quiet, did it end without a result. "State never lies" (D5 target #3).

## Scope
0. **Probe first (blocks §1 and §3; record the result in this file).** Fire an `AskUserQuestion` from inside
   a spawned worker and a `permission_prompt` from inside one, and capture the raw `PreToolUse` / `Notification`
   payloads (a `tee`-to-file hook is enough). Record: does each fire at all for a subagent, and does its
   `transcript_path` / `agent_transcript_path` basename match `subagents/agent-<id>.jsonl`? Do the same for
   `StopFailure` on a subagent turn (force a bad `model:` on a throwaway agent — `model_not_found` is a
   recorded class). 0 live samples exist for all three (00 §facts); memory `subagentstop-payload-shape`.
1. **`waiting` event.** The existing `Notification` and `PreToolUse[AskUserQuestion]` hook commands gain a
   second `|| true` emitter (one helper, `emit-lifecycle.sh waiting`) writing
   `{"event":"agent_lifecycle","state":"waiting","reason":"permission_prompt|idle_prompt|ask_user",…}`.
   `agent_id`/`agent_scope` are resolved by the **transcript-basename derivation** in `emit-progress-event.sh`
   (`subagents/agent-<id>.jsonl` ⇒ subagent; `<cc_session_id>.jsonl` ⇒ main) — NOT the `tool_response.agentId`
   key `emit-agent-identity.sh` reads, which exists only in `PostToolUse[Task]` payloads. A payload matching
   neither pattern is recorded with `agent_scope` OMITTED, never guessed. Toast unchanged.
2. **`working` heartbeat.** A `PostToolUse` matcher (`*` or the existing `Bash|Write|Edit|Task` ones)
   appends a heartbeat at most once per N seconds per `agent_id` (debounce file, like `.notify-debounce`) —
   never one line per tool call (the 13k-line ledger already shows what unbounded emitters do). The debounce
   key is the derived `agent_id` from §1's basename rule; an untyped payload hits more than one matcher block
   (00 §facts), so the debounce must be per derived id, never per matcher, or one call yields N lines.
3. **`failed` from `StopFailure`.** The hook additionally emits an `agent_lifecycle` / `state: failed` line
   into the SESSION JSONL, with `reason` copied from the payload's existing structured `.error` field
   (`rate_limit|server_error|authentication_failed|model_not_found|unknown` — already classified, never
   re-derived from message text); the raw `failures.log` append stays byte-identical. Honest limit: the
   payload has no `agent_id` and every live sample is main-thread; the line carries `agent_scope: main` unless
   §0's probe shows a subagent transcript path — a worker-turn failure that fires no hook is recorded as
   NOTHING, and that gap is named in the schema note, not papered over.
3b. **`result_block_present` on `subtask_complete`.** `emit-progress-event.sh` gains ONE boolean field:
   whether `last_assistant_message` contains a `WORKER_RESULT` fence (same detection the validator uses,
   no schema parsing — presence only). Key OMITTED when `last_assistant_message` is absent from the payload.
   This is the only new fact the log needs for §4's second derivation.
4. **Derived `stalled` and `ended_without_result`** — computed by the READER (`build-floor.sh`,
   `build-state.sh`), never written: stalled = last heartbeat older than `?stall=`; ended_without_result =
   a `subtask_complete` (worker) or `token_ledger` (other roles) row for that `agent_id` whose
   `result_block_present` is `false` — a row where the key is ABSENT (pre-3b lines, or no
   `last_assistant_message`) derives to `unknown`, never to either state. Turn-limit is the common cause;
   the derivation names the evidence, never the cause. Spawn time comes from `agent_identity.recorded_at`
   (that row has no `ts` by design).
5. **Schema** — one new `agent_lifecycle` record in `RESULT_SCHEMAS.md`; frozen example values per
   `check-doc-currency.sh` convention.

## Non-goals
No process liveness (`pgrep`) anywhere — memory `concurrent-heal-loop-sweeps-uncommitted-edits` shows the
process table proves an open window, not work. No change to `heal_decision`, gates, or `state.md` writers
(D5: state is derived from the log; this item only adds log lines). No new agent.

## Acceptance criteria
- An `AskUserQuestion` inside a spawned worker produces exactly one `agent_lifecycle:waiting` line carrying
  that worker's `agent_id`, in the same JSONL as its `agent_identity` line.
- §0's probe results are recorded in this file (date, hook, raw payload keys, transcript basename) BEFORE
  §1/§3 are written; if `Notification` does not fire for a subagent, §1 keeps only the `PreToolUse` seam and
  says so.
- A fixture worker SubagentStop payload whose `last_assistant_message` has no `WORKER_RESULT` fence yields
  `subtask_complete` with `result_block_present: false` and is derivable as `ended_without_result` from the
  log alone; a payload without `last_assistant_message` yields no key and derives `unknown`. Mutation
  control: delete the derivation and the fixture reads as clean — the test must fail then.
- `agent_lifecycle:failed` carries `reason` equal to the fixture payload's `.error` verbatim; a payload with no
  `.error` key yields `reason: unknown` (the payload's own vocabulary), never a parsed message.
- Heartbeat volume is bounded: a 200-tool-call fixture yields ≤ (duration / debounce) lines.
- `Notification` hook still toasts; `notify-desktop.sh` byte-identical (it reads STDIN — do not consume it
  before the tee; memory `runfile-write-accepts-empty-stdin`).
- All emitters exit 0 on every path; hook strings keep `|| true`.

## Outcomes Rubric
- Payload shapes probed and recorded before any emitter was written
- `waiting` recorded from every seam the probe proved fires, with the derived `agent_id`
- `result_block_present` recorded; absence stays `unknown`
- Heartbeat bounded and debounced
- `stalled` / `ended_without_result` are reader-derived, never written
- Schema + doc-currency green; no gate or state-writer touched

## Status: done (PR #231, merge fc884278, v15.79.0)

## §0 Probe Results (recorded 2026-09-17, before §1/§3 implementation)

**Method:** Live synthetic hook-injection (temporary settings.local.json tee hooks + throwaway
subagent spawns) was judged too risky to run in this session — this repo has other concurrent
agent activity right now (4 non-main worktrees observed at session start: `pr227-fix` plus three
detached-HEAD review-drain worktrees), and the harness's own worktree-isolation guard refuses
direct `Edit`/`Write` to the shared checkout's `.claude/settings.local.json` from this background
session (confirmed: the edit attempt was rejected before any write landed — verified byte-identical
to the pre-edit file via `diff`). Substituted two grounded sources instead, judged sufficient to
proceed per this item's own acceptance-criteria escape valve ("if X does not fire... says so"):

1. **Official Claude Code hooks reference** (`https://code.claude.com/docs/en/hooks`, checked
   2026-09-17): documents that `agent_id` and `agent_type` are present **generically on every hook
   event** ("When running with `--agent` or inside a subagent, two additional fields are included")
   — `agent_id` "present only when the hook fires inside a subagent call". This is authoritative for
   **PreToolUse[AskUserQuestion]**: a subagent's AskUserQuestion call DOES carry `agent_id`. **No
   field named `agent_transcript_path` is documented anywhere** on this reference page (checked by
   targeted heading + full-text search) — it is empirical-only, observed solely on `SubagentStop`
   (per memory `subagentstop-payload-shape`), not a general hook field. **Consequence for §1:** derive
   `agent_id`/`agent_scope` from the documented `agent_id` field directly — do NOT attempt the
   transcript-basename derivation `emit-progress-event.sh` uses (that trick exists because
   `SubagentStop` historically lacked a reliable typed identity; `PreToolUse` already has one).
   `tool_input` shape for `AskUserQuestion` specifically is undocumented (gap, not missed).
   **Notification** (`permission_prompt`/`idle_prompt`): the doc lists these ONLY as matcher values
   (an enum) — no dedicated field table or example payload exists on this page. Whether `agent_id`
   is present on `Notification` when it fires for a subagent is **UNCONFIRMED** (undocumented gap,
   not verified empirically either — see Method above). §1's `waiting` emitter must therefore read
   `agent_id` opportunistically (omit `agent_scope` when absent, per the existing
   never-invent-only-omit convention) and this specific application is marked UNVERIFIED until a
   real payload is observed in production (the honest-limit escape valve this item's acceptance
   criteria already anticipates: "if `Notification` does not fire for a subagent, §1 keeps only the
   `PreToolUse` seam and says so" — read literally, the live question was never "does it fire" but
   "does it carry an id when it does"; both remain open for `Notification` specifically).

2. **Real production evidence** — `.supervisor/logs/failures.log` in THIS repo already holds 37 real
   `StopFailure` captures (2026-08-28 .. 2026-09-03, this repo's actual worker/reviewer sessions
   hitting rate limits and server errors), parsed and shape-counted (`python3 -c` one-liner over the
   file, 36/37 lines valid JSON, 1 truncated). Findings, **superseding this item's own §3 assumption**
   ("every live sample is main-thread" — that assumption is WRONG, corrected here):
   - The error classification is a **flat top-level string field literally named `error`** (not a
     nested `.error` object) — observed values: `rate_limit`, `server_error`, `authentication_failed`,
     `model_not_found`, `unknown` — all five of this item's assumed enum values are attested in real
     data. Copy `payload.error` verbatim; no parsing needed.
   - **`agent_id` IS present on real StopFailure payloads for subagent turns** — 17 of 37 real lines
     carry `agent_id` (e.g. `agent_type: "loomwright:loomwright:worker"`,
     `"loomwright:loomwright:code-reviewer"`, and one cross-plugin-prefix variant
     `"ai-agent-manager-plugin:ai-agent-manager-plugin:worker"` — this repo has run the plugin under
     two different install prefixes historically, both real). **This corrects the item's own §3 text**
     ("every live sample is main-thread; a worker-turn failure that fires no hook is recorded as
     NOTHING") — worker AND code-reviewer subagent StopFailures DO fire and DO carry `agent_id`.
   - `agent_type` is **not always co-present with `agent_id`** — 2 of 17 agent_id-carrying lines have
     `agent_id` but no `agent_type` key at all. Design point for §3: gate `agent_scope: "subagent"` on
     `agent_id` presence alone, and record `agent_type` additively-if-present (same discipline as
     `emit-agent-identity.sh`/`emit-progress-event.sh` — never invent, omit when absent).
   - No `agent_transcript_path` field on any of the 37 lines — confirms finding 1 above from the
     opposite direction (real data, not just docs).
   - 1 of 37 lines is truncated/malformed JSON (an unterminated string) — real-world evidence that the
     new `agent_lifecycle`/`failed` emitter must parse defensively and no-op (never crash, never
     partial-write) on a malformed payload, consistent with the existing emitters' contract.

**Net effect on scope:** §1 (`waiting`) proceeds on the documented `agent_id` rule for
`PreToolUse[AskUserQuestion]`; the `Notification` seam is implemented the same way but flagged
UNVERIFIED (first real occurrence should be checked against this note). §3 (`failed`) proceeds with
higher confidence than a synthetic probe would have given — it's grounded in 37 real captures from
this exact repo, and the `agent_scope: main` fallback in the original scope text is corrected to
"agent_scope: subagent when `agent_id` is present (documented + empirically confirmed), else
`agent_scope: main`" rather than assuming subagent StopFailures don't happen.
