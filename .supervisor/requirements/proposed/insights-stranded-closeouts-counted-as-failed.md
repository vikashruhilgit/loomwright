# `/insights` counts SessionEnd stranded close-outs as failed runs

## Status: proposed

> **Origin (2026-10-02).** `/insights` rebuild in session 1378d676 reported 43 completed / 36 failed, a **48%
> completion rate**. Checked against the logs, every one of the 36 is a synthetic record. None is a run that failed.

## Evidence
- The last `session_end` per log across `.supervisor/logs/*.jsonl` breaks down as:
  - 36 × `failed` / `session_ended_without_completion` / no `plugin_version`
  - 26 × `completed` with a version, 17 × `completed` without one
  - 4 × `done`, 2 × `completed_with_escalation`
  - 3 × `aborted`
- **No session in the corpus reports a genuine failure.**
- All 36 are written by `loomwright/scripts/close-stranded-run.sh`, the SessionEnd close-out emitter. By design it writes
  `status: failed, reason: session_ended_without_completion` for any session that ended without its own `session_end`.
  The header comment explains why: it stops a stale `running` status from drawing every later session's events into that
  run's log.
- Several of the 36 did real work. Examples: `44bb7cc2` has 18 `subtask_complete` events, and `3aea253b` has 4.
  These are interactive or driver sessions whose result was recorded under another ID (an `auto-*` log or a PR). They
  are not failures.
- The emitter writes no `plugin_version`, so these records land in the Per-version table's `unknown` row (60 runs at a
  26% heal-PASS rate), which drags that row down as well.

## Scope (recommendation)
- `build-insights.sh`: report `reason: session_ended_without_completion` as its own **stranded** bucket. Exclude it from
  `Failed` and from the completion-rate denominator, and show the count on a separate line so it is visible but not
  counted as failure.
- `close-stranded-run.sh`: stamp `plugin_version` (read the same way the other emitters do; omit the field if it can't
  be read, never invent a value). Keep it fail-SAFE (always exit 0).
- Check the other readers of `session_end.status` for the same conflation: `build-loop-evidence.sh` (the "landed" stage),
  `/handoff`, and the Floor.
- Fixtures: a corpus with stranded close-outs reports them as stranded, not failed, and the completion rate excludes
  them. A real `failed` record with another reason still counts as failed.
