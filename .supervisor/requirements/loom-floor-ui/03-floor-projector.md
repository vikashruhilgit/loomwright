# 03 — `build-floor.sh`: one projector, one contract

## Problem

The state a UI would need is real and already on disk, but it is scattered across nine
surfaces in four formats (markdown tables, folder membership, JSONL, JSON). Measured in
this checkout, 2026-09-01:

| Surface | Holds | Present |
|---|---|---|
| `.supervisor/state.md` | phase, branch, subtask table with per-subtask review verdict | 4 subtasks |
| `.supervisor/jobs/{pending,in-progress,done,failed}/` | the pipeline — briefs move between folders | 0 / 0 / 88 / 2 |
| `.supervisor/automate/<run>.md` | queue checkboxes + timestamped decision narrative | 1 run file |
| `.supervisor/logs/*.jsonl` | the event stream | 98 files |
| `.supervisor/insights/dashboard.md` | completion rate, heal-PASS rate, rubric by version | 27 runs |
| `.supervisor/postmortem/results.jsonl` | per-PR review-churn ledger with root-cause class | 85 lines |
| `.supervisor/drain-rounds/*.json` | per-round findings from the review→heal drain | 487 files |
| `.supervisor/worker-summaries/*.md` | what each worker did, in its own words | 112 files |
| `.agent/rules/*.json` | the committed house-rules store | 2 files |

If each future view parses these itself, every view re-implements the same nine parsers and
drifts independently. Exactly one thing should read them.

## Goal

One script, `build-floor.sh`, that projects those surfaces into a single `floor.json`.
That file becomes the contract; everything downstream is a view of it and parses nothing
else.

## Scope

1. **`build-floor.sh`** — jq-based, deterministic, read-only on every input, writing only
   `.supervisor/floor/floor.json`. Mirror `build-insights.sh` in structure and discipline:
   `set -uo pipefail` with no `set -e`, a `command -v jq` guard that skips rather than
   fails, and **exit 0 always** — a reporting tool must never break its caller.
2. **Segment by `cc_session_id`, not by filename.** Measured 2026-09-01 on
   `.supervisor/logs/8d43da72-…jsonl`: the file spans 2026-07-29 → 2026-09-01 across 6+
   branches because its name is derived from a `state.md` `status:` that has read `running`
   since July. But `cc_session_id` is present on **100%** of its 10,271 lines and segments
   cleanly into **116** sessions with coherent time spans. Group by that field. **No
   emitter change is required for this** — the field is already additive on every event.
3. **A declared, versioned schema.** `floor.json` carries a `schema_version`, and the
   schema is documented in `loomwright/docs/RESULT_SCHEMAS.md` alongside the existing result
   schemas rather than in a new file.
4. **Evidence-only derivation.** Adopt `build-state.sh`'s rule verbatim: a projector that
   guesses is the same lie in a new place. Every field states what it was derived from;
   absent evidence yields an **omitted** field, never a plausible default. A UI must be able
   to render "unknown" and must never be handed a fabricated zero.
5. **Freshness on the artefact.** `floor.json` records its own generation timestamp and the
   mtime of each input it read, so a consumer can show staleness instead of implying live.

## Non-goals

- **No writes to any existing state.** `build-state.sh` is the sole writer of `state.md`'s
  `## Session` block. This projector writes only its own file, in its own directory.
- No new event, no new hook, no daemon. It is invoked; it does not watch.
- No HTML, no rendering. That is item 04.
- No network. Nothing leaves the machine.

## Depends on

Nothing hard. Ships `agent_spawn` data if 01 landed and omits those fields if it did not —
which is exactly the "absent evidence ⇒ omitted field" rule, applied to itself.

### Amendment 2026-09-02 — item 01 outcome (measured, do not re-derive)

Item 01 ran and closed **NO-GO**, shipping evidence but **no emitter**. Consequences that
change how this item should be read:

1. **There is no `agent_spawn` event in any log today.** The fallback above therefore FIRES,
   and it is correct as written — omit the spawn-derived field rather than inferring one.
   This is not a degraded compromise; it is the accurate state of the data.
2. **The reason differs from what the fallback assumed.** `PreToolUse[Task]` *does* fire once
   per subagent spawn. What it lacks is an `agent_id`: it carries `tool_use_id` (`toolu_…`)
   while `SubagentStop` carries `agent_id` (`a…`). Measured, 2 spawns / 2 captures, fixtures
   committed at `loomwright/scripts/progress-event-fixtures/spawn-probe-2026-09-02/`.
3. **The path to enabling the field later is known and cheap.** The spawn payload carries
   `tool_input.subagent_type` and `tool_input.description`, so a liveness count keyed on
   `tool_use_id` needs no join at all. Correlating with the historical `agent_id` corpus is
   the part that needs a second hook (`PostToolUse[Task]`, whose `tool_response.agentId`
   bridges the two — verified 2/2) and resolves only when an agent *finishes*.
4. **Do not re-run the probe.** The verdict, the raw payloads and three falsified assumptions
   (the matcher is `Task` but the payload reports `tool_name: "Agent"`; `effort` is an object
   in one payload and a string in another; `agent_type` already ships on the stop side) are
   recorded in `loomwright/docs/SPIKES/AGENT_SPAWN_PAYLOAD_PROBE.md`.

## Acceptance criteria

- [ ] Given this repo's real `.supervisor/`, `floor.json` is produced and every count in it
      matches the on-disk truth (jobs folders, log files, drain rounds, ledger lines) —
      verified by independently recomputing each count, not by trusting the script.
- [ ] Given the live log, sessions are grouped by `cc_session_id` and the count matches an
      independent measurement of distinct values in that file.
- [ ] Given a missing input directory, an empty log, and a malformed JSON input (three
      separate cases), the script omits the affected section, names the reason in the
      output, and exits 0. An unreadable input reports **unverified**, never "clean".
- [ ] Given `jq` absent, the script skips with a named reason and exits 0.
- [ ] `floor.json` validates against its documented schema, and the documented schema is
      proven to reject a payload missing a required key.
- [ ] Running twice with no state change produces byte-identical output apart from the
      generation timestamp.
- [ ] No file outside `.supervisor/floor/` is modified — asserted by hashing the tree before
      and after, not by reading the code.

## Outcomes Rubric

- One reader, one schema, one file; no downstream view parses a raw surface.
- Session boundaries are correct today, with no emitter change, using a field already present.
- Absent evidence is visibly absent rather than silently defaulted.
- Byte-identical on re-run; provably writes nothing else.

## Status: done

Job `.supervisor/jobs/done/2026-09-02-floor-projector.md` completed (reconciled from the job lifecycle, not self-reported).
Promoted to `done` by the owner on 2026-09-03 after AC confirmation. Shipped as PR #174 (merged 02:31Z, 7 commits). Final review found no correctness bugs. Two residual observations were adjudicated rather than carried: the unquoted-glob word-splitting concern is NOT a defect (bash does not word-split pathname-expansion results - verified with space, tab and newline in filenames), and add_surface's silent return on an internal jq error is unreachable at all 22 current call sites, deferred to item 04 as a defensive fix to a shared helper.
