## `agent_lifecycle` JSONL event records (waiting / working / failed)

> **Not a result-block schema** — like the `session_end` hard-signal fields above, this is a JSONL
> event shape, not something an agent emits as a structured result block. Added v15.79.0 —
> `.supervisor/requirements/orca-derived/01-agent-lifecycle-ledger.md` — to close the gap between
> "what an agent PRODUCED" (`WORKER_RESULT`, `subtask_complete`, `token_ledger`) and "what state it
> is IN". Emitted fail-SAFE by `scripts/emit-lifecycle.sh` into the SAME per-session log
> `.supervisor/logs/{session_id}.jsonl` that `emit-progress-event.sh`/`emit-agent-identity.sh` write
> to — same two-source session-id resolution, same worktree-safe anchoring, same run-ownership gate.

Three states, one per `emit-lifecycle.sh` subcommand:

```jsonl
{"event":"agent_lifecycle","state":"waiting","session_id":"<id>","cc_session_id":"<id>","agent_id":"agent-fixture-full","agent_scope":"subagent","agent_type":"loomwright:worker","reason":"ask_user","branch":"main","ts":"2026-09-17T00:00:00Z"}
{"event":"agent_lifecycle","state":"working","session_id":"<id>","cc_session_id":"<id>","agent_id":"agent-fixture-full","agent_scope":"subagent","branch":"main","ts":"2026-09-17T00:00:00Z"}
{"event":"agent_lifecycle","state":"failed","session_id":"<id>","cc_session_id":"<id>","agent_id":"agent-fixture-full","agent_scope":"subagent","reason":"rate_limit","branch":"main","ts":"2026-09-17T00:00:00Z"}
```

> **Illustrative field values above are frozen, not current claims** — same convention as the
> `session_end`/`POSTMORTEM_RESULT` blocks elsewhere in this file (see that section's own note).
> `check-doc-currency.sh` deliberately does not scan these; do not "fix" them on a future release.

**Common fields (all three states):**
- `event` — always the literal string `"agent_lifecycle"`.
- `state` — one of `waiting` / `working` / `failed`. This is the ONLY vocabulary this file writes;
  `stalled` and `ended_without_result` are NEVER written by any emitter — they are DERIVED by a
  reader (`build-floor.sh` / `build-state.sh`) from these rows plus `agent_identity.recorded_at` and
  `subtask_complete.result_block_present` (below), never by a writer. A future writer emitting either
  derived name directly would be a regression of this section's own design.
- `session_id` — the log-file join key (prefers the active plugin session id from `.supervisor/state.md`
  when `status: running`/`checkpoint`, else the Claude Code `session_id`) — identical resolution to
  every other emitter in this family.
- `cc_session_id` — the Claude Code session UUID, additive, present whenever the payload carried one.
- `agent_id` / `agent_type` — **PAYLOAD ONLY, else the key is OMITTED ENTIRELY** — never invented, never
  an empty string, never null. Same discipline as `emit-agent-identity.sh` / `emit-progress-event.sh`.
- `agent_scope` — `"subagent"` when the payload carries `agent_id`; **OMITTED** (never guessed) on
  `waiting` and `working` when `agent_id` is absent — there is no grounded main-thread fallback for
  those two seams. `failed` is the ONE state with a grounded fallback (see below).
- `branch` / `ts` — additive, identical semantics to every other emitter in this family (omitted when
  the branch/timestamp cannot be resolved).

**`waiting`-specific:** `reason` is one of `ask_user` (hardcoded by the `PreToolUse[AskUserQuestion]`
hook wiring — see `docs/HOOKS.md`) or whatever the `Notification` hook payload's own subtype field
resolves to (`.notification_type` tried first, then `.type`, else the literal string `"unknown"` —
never crashes, never invents a value it did not actually read). Whether `agent_id` is ever present on
the `Notification` seam for a subagent is **UNVERIFIED** (no live sample observed —
`.supervisor/requirements/orca-derived/01-agent-lifecycle-ledger.md` `## §0 Probe Results`); the
`PreToolUse[AskUserQuestion]` seam's `agent_id` presence for a subagent IS documented (Claude Code
hooks reference) and empirically expected. **One `ask_user` row per `tool_use_id`:** a resumed
session replays the same tool call (same `tool_use_id`) to deliver the answer and the hook fires
again; the emitter skips an id already listed in its own `.supervisor/logs/.lifecycle-asked-ids`
ledger (newest 200 ids, recorded only after the row was appended), so a replay writes no second
row. A payload without `tool_use_id`, and every `Notification`-seam row, is never de-duplicated.
Rationale and the separate-ledger rule: `emit-lifecycle.sh`'s header (`waiting` paragraph).

**`working`-specific (heartbeat):** no additional fields beyond the common set above. Debounced PER
DERIVED `agent_id` (never per matcher block) — at most one `working` line per
`LOOMWRIGHT_LIFECYCLE_HEARTBEAT_DEBOUNCE`-second window (default 60 seconds; a non-integer override
falls back to the default rather than tripping `set -u` arithmetic — same override-env-var convention
as `LOOMWRIGHT_STALE_RUN_SECONDS` in `build-state.sh`) regardless of which of the three registered
`PostToolUse` matchers (`Bash` / `Write|Edit` / `Task`) fired the call.

**`failed`-specific:** `reason` is the payload's own top-level `error` string, copied **VERBATIM** —
never parsed or derived from message text. Observed real values in this repo's own
`.supervisor/logs/failures.log`: `rate_limit`, `server_error`, `authentication_failed`,
`model_not_found`; `reason: "unknown"` when the payload carries no `error` key at all. `agent_scope`
is the ONE lifecycle field with a grounded main-thread fallback here: `"subagent"` when `agent_id` is
present (empirically confirmed on 17 of 37 real captures in this repo's own `failures.log`), else
`"main"` — a corrected assumption from the source requirement's original text, which had wrongly
assumed every `StopFailure` was main-thread-only. This is an ADDITIVE emitter on the existing
`StopFailure` hook — the raw `.supervisor/logs/failures.log` append (`STOP_FAILURE $(cat)`) stays
byte-identical; `emit-lifecycle.sh failed` is a second consumer of the same re-fanned payload, never a
replacement.

**`result_block_present` (additive, on `subtask_complete` — added v15.79.0):** `emit-progress-event.sh`
gains one boolean field, present only when the SubagentStop payload carries a `last_assistant_message`
key: whether the worker's resolved output contains a `WORKER_RESULT` fence, using the exact same
resolution (`result_block_parser.resolve_payload_text` — which prefers the subagent's last
`SubagentHandback` message when `last_assistant_message` is only a prose recap without a block) and
detection (`result_block_parser.find_last_block`) `validate-worker-result.py` runs, never a second regex.
**PRESENCE, not truthiness, decides the key** — a `last_assistant_message` key that is present but not
a string, or whose fence-scan raises for any reason (e.g. `result_block_parser.py` unavailable), OMITS
the key entirely (a detection-FAILED case, never a guessed `false`); only an actual scan may assert
`false`. A reader derives `ended_without_result` from `result_block_present: false` on a
`subtask_complete` (worker) row, and `unknown` — **never** either terminal state — when the key is
absent (pre-v15.79.0 lines, or no `last_assistant_message` in the payload at all). The equivalent
derivation over a `token_ledger` (other roles) row is a **forward-reference to unshipped emitter
work, not current behavior**: this change wires `result_block_present` into
`emit-progress-event.sh`'s `subtask_complete` path only — `emit-token-ledger.sh` was NOT touched and
never writes this field, so no `token_ledger` row can support this derivation yet.

**`rejected` and `stop_hook_active` (additive, on `subtask_complete` — added v15.83.0):**
`emit-progress-event.sh` is wired on the SAME `loomwright:worker` SubagentStop matcher as
`validate-worker-result.py`, and since that validator prints the documented command-hook decision
shape (`{"decision": "block", "reason": …}` on a malformed `WORKER_RESULT` — CHANGELOG v15.82.0,
`docs/HOOKS.md` §"Command-validator decision shape") a rejected stop makes the runtime feed the reason
back to the worker, which CONTINUES and stops again (SubagentStop re-fires with `stop_hook_active:
true`, bounded only by the runtime's consecutive-continuation cap — 8 on Claude Code v2.1.278). The
emitter fires on EVERY such firing and cannot see its sibling's stdout, so unqualified it left a
`subtask_complete` row for the rejected first stop while the worker was still running. Two fields
close that:
- `rejected` — the sibling validator's decision on THIS payload, re-derived by running the real
  `validate-worker-result.py` (a subprocess of the same file, same bytes, same cwd — never a restated
  copy of its rules): `true` iff it printed `decision: "block"`; `false` iff it printed a parseable
  JSON object with no block decision (`{}`, or the legacy `{"ok": …}` shape — that shape never blocked
  the runtime, so a stop it was printed on IS terminal). **OMITTED** (never guessed) when the
  validator is absent, cannot run, times out, or prints anything that is not a JSON object — a reader
  derives `unknown`, and every consumer treats an absent key exactly as a pre-v15.83.0 row (terminal),
  because a missing sibling validator cannot have blocked anything either.
  **A `subtask_complete` row with `rejected: true` is NOT a terminal row.** `check-children-settled.sh`
  skips it entirely (it neither settles the agent nor decides `ended_without_result`, so the
  `result_block_present` on a rejected row is never read) and `build-floor.sh` excludes it from the
  terminal set (it can never derive `done`). `build-state.sh` is deliberately unchanged — a rejected
  stop is still evidence the run is in EXECUTE and `running`.
- `stop_hook_active` — PAYLOAD ONLY, copied when present and boolean, else OMITTED (never coerced).
  `true` marks a re-fire after a sibling hook blocked the previous stop. It is a reader aid for
  telling a first stop from a post-rejection retry; it is **not** the rejection signal — the firing
  that got rejected carries `false` (it was the first stop), and a retry can be rejected again.

```jsonl
{"event":"subtask_complete","type":"subtask_complete","session_id":"<id>","cc_session_id":"<id>","agent_type":"loomwright:worker","agent_id":"agent-fixture-full","result_block_present":true,"stop_hook_active":false,"rejected":true,"branch":"main","ts":"2026-09-21T00:00:00Z"}
{"event":"subtask_complete","type":"subtask_complete","session_id":"<id>","cc_session_id":"<id>","agent_type":"loomwright:worker","agent_id":"agent-fixture-full","result_block_present":true,"stop_hook_active":true,"rejected":false,"branch":"main","ts":"2026-09-21T00:00:05Z"}
```

> Frozen illustrative values (same convention as the `agent_lifecycle` block above) — the probe-B
> sequence from `scripts/fixtures/subagentstop-decision-shape-probe.json`: the first stop rejected,
> the retry accepted. Only the second row is terminal.

**Reader-derived states (NOT written here — documented for completeness, not implemented by this
schema section):** `stalled` = the newest `working` row for an `agent_id` is older than a reader's own
staleness threshold; `ended_without_result` = a NON-REJECTED terminal row (`subtask_complete` today;
`token_ledger` once `emit-token-ledger.sh` gains the same field — see the forward-reference note above)
for that `agent_id` whose `result_block_present` is `false` (absent ⇒ `unknown`, never either terminal
state). Spawn time for either derivation comes from the EXISTING `agent_identity.recorded_at` field
(that row deliberately carries no `ts` — see `emit-agent-identity.sh`'s header note). Building
`build-floor.sh`/`build-state.sh` support for these two derived names is explicitly OUT OF SCOPE for
this schema section and the emitters above — a documentation/schema-completeness note, not a
forward-reference to unshipped code.

### `worker_checkpoint` (JSONL session-log event, not a result-block schema)

> `.supervisor/requirements/orca-derived/03-worker-checkpoints.md` — a worker leaves a short,
> structured trail of what it concluded and why at the moments that matter (a hypothesis confirmed
> or refuted, a blocker hit, an investigate→fix transition, a slice done) — context previously
> reconstructed from the final diff or lost entirely. Like `agent_lifecycle` above, this is a
> session-log EVENT SHAPE, not something an agent emits as a `WORKER_RESULT`-style structured result
> block. Emitted fail-SAFE by `scripts/checkpoint.sh`, invoked DIRECTLY by the worker via Bash mid-
> task (unlike the hook-triggered `emit-lifecycle.sh`/`emit-progress-event.sh`, which self-resolve
> their session log via git-worktree anchoring, `checkpoint.sh` takes an explicit, VALIDATED,
> caller-supplied ledger path as its first positional argument — the worker's spawn prompt carries a
> session-log pointer for this purpose, see `agents/execute-manager.md` Step 3 and
> `skills/async-orchestration/SKILL.md` §"Subagent Spawn Contracts"). Appended to the SAME per-session
> log `.supervisor/logs/{session_id}.jsonl` that `emit-progress-event.sh`/`emit-lifecycle.sh` write to.
> ADVISORY ONLY — never required, never gates anything (`outputs_verified`, `heal_decision`, and every
> other gate are unaffected by checkpoint presence or absence; see `agents/worker.md`).

```jsonl
{"event":"worker_checkpoint","kind":"hypothesis_confirmed","text":"reproduced the auth failure","cc_session_id":"sess-abc123"}
{"event":"worker_checkpoint","kind":"blocker","text":"flaky test env — retrying with a fixed seed","cc_session_id":"sess-abc123"}
{"event":"worker_checkpoint","kind":"slice_done","text":"shipped the credential-chain fix","cc_session_id":"sess-abc123","paths":["src/auth/chain.ts"]}
```

> **Illustrative field values above are frozen, not current claims** — same convention as the
> `agent_lifecycle`/`session_end`/`POSTMORTEM_RESULT` blocks elsewhere in this file. `check-doc-
> currency.sh` deliberately does not scan these; do not "fix" them on a future release.

**Fields:**
- `event` — always the literal string `"worker_checkpoint"`.
- `kind` — one of `hypothesis_confirmed` / `hypothesis_refuted` / `blocker` / `transition` /
  `slice_done`. `checkpoint.sh` validates this against the closed set and silently no-ops (writes
  nothing) on any other value — never writes a line with an unrecognized `kind`.
- `text` — free text, first line = the action; ≤200 chars is the advisory authoring convention, and
  `checkpoint.sh` additionally truncates defensively as a safety net (not a validation gate).
- `cc_session_id` — DERIVED, never guessed: the basename of the `<ledger_path>` argument minus its
  `.jsonl` suffix (the session log is named `.supervisor/logs/{session_id}.jsonl`, so the id is
  literally encoded in the path the worker was handed via the session-log pointer). **Required for
  this line to be visible to `scripts/build-floor.sh`'s session view at all** — that projector's
  classifier drops every session-log line lacking `cc_session_id` before any grouping happens, so
  without this field a `worker_checkpoint` line would be silently invisible to
  `sessions.detail.current.agents[].last_checkpoint` (below). OMITTED (never a fabricated
  placeholder) when the ledger basename doesn't look like a plausible session id.
- `paths` — OPTIONAL array of file paths touched. **OMITTED entirely when no paths were given** —
  never an empty-array placeholder for "nothing to say", matching this file's general "absent
  evidence is an omitted key, never a default" convention.

**Deliberately absent from this event, unlike its `agent_lifecycle`/`agent_identity` siblings:**
no `agent_id`, `session_id` (the `state.md`-preferred plugin-session variant), `agent_type`, `branch`,
or `ts`. The worker calling `checkpoint.sh` directly has no way to learn its own harness-assigned
`agent_id` — that identifier is known only to the Task-spawning context and to a hook process
receiving the SubagentStop payload, neither of which `checkpoint.sh` is. Consequently, per-lane
attribution of a `worker_checkpoint` line (`scripts/build-floor.sh`'s additive
`sessions.detail.current.agents[].last_checkpoint`, above) is a FILE-POSITION-WINDOW heuristic within
the shared session, not an agent_id-keyed join — see that field's own entry in the additive-fields
list above for the exact/best-effort split between the Single-Agent/Sequential and Parallel paths.

**Consumers:**
- `scripts/build-handoff.sh` renders `worker_checkpoint` lines under a job's "Tried / rejected"
  facet, scoped to the ACTIVE in-progress job only (the one join-able to `.supervisor/state.md`'s
  current `session_id`), with the session id rendered inline as provenance.
- `scripts/build-floor.sh` additively carries the LAST `worker_checkpoint` text per lane (see the
  additive-fields entry above); it does not render it — a later, separate item does.
- `scripts/build-state.sh` (filters `session_end` / `subtask_complete` only) and
  `scripts/read-postmortem.sh` (reads the unrelated `.supervisor/postmortem/results.jsonl`, keyed on
  `changed_paths`) are both UNAFFECTED by this event type — verified against their actual filter
  logic, not assumed.
- **Honest limit (not part of this section's contract):** the source requirement's own D11
  pre-registration asks for an emission-rate measurement (checkpoints per worker, workers with zero)
  over the first five real runs after this ships. That data does not exist yet and is deliberately
  NOT fabricated here — it is a necessarily-later observation, out of scope for the PR that added
  this event type.

### Completion authority join (`scripts/check-children-settled.sh`, added v15.80.0)

> `.supervisor/requirements/orca-derived/02-completion-authority.md` — closes the gap between "the
> `provides` artefacts this agent was supposed to produce exist on disk" (`verify-provides.sh`, above)
> and "the agent that was supposed to produce them actually terminated". Neither condition alone is
> sufficient: disk alone can be a partial/interrupted run, a stale artifact, or a still-running worker
> whose files land early; a terminal event alone says nothing about what ended up on disk (that's
> `verify-provides.sh`'s job, unchanged by this addition).

`scripts/check-children-settled.sh` is the ONE implementation of the join between an `agent_identity`
row (spawn-time fact, above) and a **terminal row** for that same `agent_id` — a `subtask_complete`
event (worker role) **that does not carry `rejected: true`** (v15.83.0 — a validator-rejected stop is
not terminal, the worker was told to continue; see `rejected` under `## agent_lifecycle` above), a
`token_ledger` event (non-worker roles — see the `token_ledger` note above this section; it carries no
`result_block_present` field yet, so presence alone settles it), or an `agent_lifecycle` event with
`state: "failed"`. Fail-SAFE emitter (always exits 0, JSON on stdout); consumers fail CLOSED on its
verdict, exactly as they do on `verify-provides.sh`'s `missing` / `unverifiable`. Two modes:

- **`--agent-id <id>`** (per-subtask join): `{"agent_id":"<id>","status":"settled"|"unsettled","ended_without_result":true|false,"rejected_stops":N,"source":"check-children-settled.sh"}`. Consumed by `agents/execute-manager.md`'s v12 outputs_verified gate (per-subtask, Parallel path) and `agents/supervisor.md`'s Single-Agent Path step 3b / Sequential Path (per-subtask, inline). `unsettled` (provides present on disk, no terminal row yet) records `record_decision(... "provides_present_agent_unsettled: ...")` — **distinct from `provides_mismatch`** (disk/self-report disagreement, unchanged) — and does NOT mark the subtask complete; this is the expected transient state for a worker whose files land before its result message does, not an error or an escalation. `rejected_stops` (additive, v15.83.0, DIAGNOSTIC ONLY — always present, `0` when none) counts the `subtask_complete` rows with `rejected: true` for that id: an `unsettled` verdict with `rejected_stops > 0` means the worker's stop was rejected by `validate-worker-result.py` and it is still running (or was forced to stop at the runtime's continuation cap with a malformed result) — readable from the join output instead of only from the subagent transcript. Consumers decide on `status` alone; this never changes the verdict.
- **`--all`** (per-session aggregate): `{"status":"settled"|"unsettled"|"no_identity_rows","unsettled_agent_ids":[...],"ended_without_result_ids":[...],"rejected_stop_ids":[...],"source":"check-children-settled.sh"}`. `rejected_stop_ids` (additive, v15.83.0, diagnostic only) names every identity-row id with at least one rejected row, settled or not. Consumed by `agents/supervisor.md`'s Phase 4 FINALIZE pre-merge safety gate as its 5th checklist point (`skills/async-orchestration/SKILL.md` §"Phase 4 FINALIZE procedure" step 1, Point 5). `no_identity_rows` (zero `agent_identity` rows this session — pre-2026-09-07 logs, or a session that never spawned a Task) PASSES and is reported `children_check: no_identity_rows` — **never** `settled`. `unsettled` FAILS the gate: interactively `AskUserQuestion`; under `--non-interactive` / CI / stdin-not-a-TTY, fails CLOSED with `SUPERVISOR_RESULT.error = "children_unsettled: {unsettled_agent_ids}"` — same shape as `preflight_overlap_detected` below. The **`--skip-children-check`** flag (mirrors `--skip-preflight-sync`) short-circuits this one point, recording `record_decision(phase: FINALIZE, decision: "user_skipped_children_check")` and `children_check: skipped` in the run summary.

`ended_without_result` / `ended_without_result_ids` (the same reader-derived state defined above: a
NON-REJECTED terminal row that is a `subtask_complete` with `result_block_present: false`, or an
`agent_lifecycle: failed` row) is surfaced by BOTH consumers alongside the settled/unsettled verdict so
an operator can `SendMessage` that `agent_id` to resume it (memory
`subagents-hit-turn-limit-resume-via-sendmessage`) instead of re-running the subtask cold — this join
only surfaces the id; it does not implement the resume. Schema_version of `WORKER_RESULT` /
`EXECUTE_RESULT` / `SUPERVISOR_RESULT` is unaffected — this is a session-log JSONL read, not a
result-block field.

**Honest limit — rejected at the cap (v15.83.0):** a worker whose EVERY stop was rejected (the runtime
forces the stop at its consecutive-continuation cap) leaves only `rejected: true` rows and stays
`unsettled` forever: the join cannot tell "rejected, retrying" from "rejected at the cap" and does not
guess. This is fail CLOSED toward "not done" — its result genuinely IS malformed — and is bounded by
each consumer's existing path (Execute Manager's `max_iterations` re-poll, the Single-Agent /
Sequential bounded-retry-then-pause, FINALIZE's `--skip-children-check`); `rejected_stops` /
`rejected_stop_ids` make the cause visible so the operator resumes the child (`SendMessage`) with the
validator's reason from its transcript rather than re-running cold.

---

