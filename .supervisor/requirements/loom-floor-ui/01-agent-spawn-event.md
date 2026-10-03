# 01 — The spawn-side event: `agent_spawn`

## Problem

Every progress event Loomwright writes comes from a `SubagentStop` hook. There is **no
spawn-side hook** — verified 2026-09-01 by grepping `loomwright/hooks/hooks.json` for a
`"Task"` matcher: zero hits across all 24 hook entries. The log therefore records that an
agent *finished*; it can never say that an agent *started*, which agent it was, or what it
was working on.

Measured on this repo's own live log (`.supervisor/logs/8d43da72-…jsonl`, 2026-09-01):

| Measurement | Value | Consequence |
|---|---|---|
| `subtask_complete` events | **3,641** | Against **4** real subtasks in `state.md`. The event fires on every `loomwright:worker` `SubagentStop`, so its name asserts something ~900× stronger than what it observes. |
| Distinct `agent_id` values | **559** | Agents *are* individually addressable — the id is a usable primary key. |
| Fields on the event | **7** (`event`, `type`, `session_id`, `cc_session_id`, `agent_id`, `branch`, `ts`) | No `agent_type`, no subtask title, no status. Nothing downstream can name or colour the agent that just stopped. |

This is the same class of defect the one-writer mechanism was built to delete: the
mechanism itself is sound — hook-triggered, fail-safe, worktree-anchored — it was simply
only ever wired to **one edge** of an agent's life. See the "WHY THIS EXISTS" header of
`loomwright/scripts/emit-progress-event.sh`, which records the 785-hook-written vs
6-agent-written miss rate that motivated it.

**Nothing that reports "who is working right now" can be truthful until this is closed.**
Inferring liveness from a recent `token_ledger` line would be a guess, and guessing is the
exact failure the invariant exists to prevent.

## Goal

Emit a spawn-side event so that spawn↔stop pairing is available to any reader, and correct
the one event name that overstates what it observes.

## Highest risk — settle it FIRST, and be willing to return NO-GO

This repo's own history says a hook payload's shape is verified empirically or not at all:
`emit-progress-event.sh`'s header records that the real `SubagentStop` payload carries
`last_assistant_message` + `agent_transcript_path` and **no** `result_block`, contrary to
what was assumed at design time.

Do the same here **before writing the emitter**:

1. Register a temporary capture hook on `PreToolUse[Task]` that does nothing but append the
   raw stdin JSON to a scratch file.
2. Run a real multi-agent workflow that spawns at least one `loomwright:worker` and one
   other agent type.
3. Commit the captured payload as a fixture under
   `loomwright/scripts/progress-event-fixtures/`, exactly as the `SubagentStop` fixture is
   committed today.

**If the payload does not fire per subagent spawn, or does not carry an id joinable to
`SubagentStop`'s `agent_id`, this item returns NO-GO with the captured evidence** and items
02–05 are re-scoped against whatever the payload actually offers (worst case: `WorktreeCreate`,
which already logs to `.supervisor/logs/worktrees.log`, gives worker-lifecycle liveness only).
A NO-GO with a committed fixture is a **successful** outcome for this item. Do not
substitute a plausible-looking payload shape derived from documentation.

## Scope

1. **`emit-agent-spawn.sh`** — a `PreToolUse[Task]` emitter appending one additive JSONL
   line with `"event":"agent_spawn"` carrying at minimum `agent_id`, `agent_type`,
   `branch`, `ts`, plus `subtask`/`description` if the payload offers it. Modelled
   line-for-line in discipline on `emit-progress-event.sh`: `set -u` with no `set -e`,
   `trap 'exit 0' EXIT`, the same two-source session-id resolution, additive-if-present
   fields, and the worktree-safe anchoring (first porcelain `git worktree list` entry with
   a `--show-toplevel` cross-check — **never** `$PWD`, never `git branch --show-current`).
2. **Name the stop event honestly** — emit `subagent_stop` alongside the existing
   `subtask_complete`, keeping the old key **additively** so `build-insights.sh`,
   `build-state.sh` and every read script stay working unchanged. Do not remove the old
   name in this item.
3. **`agent_type` on the stop side too** — if the `SubagentStop` payload carries it (the
   fixture says it does), add it as an additive field so a stop can be attributed without
   joining back to the spawn.
4. **Self-test** — `test-agent-spawn-event.sh` in the shape of the existing progress-state
   test, fixture-backed rather than only asserted through an inline payload generator.

## Non-goals

- **No new hook event.** If `PreToolUse` already has a matcher list, add to it; introduce a
  new matcher only if `Task` genuinely has none (it does not today).
- **No session segmentation.** `.supervisor/requirements/twin-remediation/08-session-segmentation.md`
  owns fresh-context-per-unit-of-work. That item is about token cost; this one is about
  event shape. Do not do its work here.
- **No log-file rotation.** See the note below — it turned out not to be needed.
- No consumer changes. Nothing reads `agent_spawn` in this item; 02 and 03 do.

## Correction carried forward (do not re-derive the wrong version)

Initial research claimed a session log accumulates unboundedly because its join key is
`state.md`'s `status:`, which has read `running` since 2026-07-29 — and concluded a
rotating key was needed. **That conclusion was wrong.** Re-measured 2026-09-01 over the
same file: `cc_session_id` is present on **100%** of lines (0 missing of 10,271) and
segments into **116** distinct sessions with coherent time spans (e.g. `f2bdc811…`,
525 events, 2026-08-07T02:25 → 10:01).

The file *name* is stale; the *data* is already segmented. A reader groups by
`cc_session_id` and needs no emitter change. Item 03 does exactly that. No work is required
here — this section exists so the wrong conclusion is not rediscovered and implemented.

## Acceptance criteria

- [ ] A real `PreToolUse[Task]` payload is captured from a live run and committed as a
      fixture — not synthesized, not derived from documentation.
- [ ] Given that fixture, when the emitter runs, then exactly one `agent_spawn` line is
      appended carrying an `agent_id` that **joins** to a `SubagentStop` `agent_id` from the
      same run; the join is demonstrated against two real events, not asserted.
- [ ] Given a malformed / empty / non-JSON payload, the emitter writes nothing and exits 0
      — each degenerate input tested separately, not as one case.
- [ ] Given invocation from inside a detached linked worktree with no `.supervisor/`, the
      emitter resolves the main checkout or writes nothing; it never falls back to `$PWD`.
      Verified from a real `git worktree add`, not a simulated cwd.
- [ ] `subagent_stop` is emitted and `subtask_complete` is still emitted; `build-insights.sh`
      and `build-state.sh` produce byte-identical output on the existing corpus before and
      after — proven by diffing real generated files, not by reading the code.
- [ ] Every new test case is mutation-verified: reverting the mechanism it covers fails
      exactly that case and no other.
- [ ] If the payload probe returns NO-GO, the fixture and the measured reason are committed
      and the item closes as NO-GO — this is a pass, not a failure.

## Outcomes Rubric

- The spawn payload is known from evidence on disk, not from reasoning.
- Spawn↔stop pairing is demonstrated on real events from a real run.
- The emitter is indistinguishable in discipline from `emit-progress-event.sh`.
- Existing consumers are provably unaffected.
- A NO-GO, if it happens, is reported as clearly as a GO.

## Status: done

Job `.supervisor/jobs/done/2026-09-01-agent-spawn-event.md` completed (reconciled from the job lifecycle, not self-reported).
Acceptance criteria are NOT machine-verified here — review them before promoting this to `## Status: done`.
