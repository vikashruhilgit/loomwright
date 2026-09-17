#!/usr/bin/env bash
# checkpoint.sh — tiny, fail-safe, ADVISORY emitter for the `worker_checkpoint` event
# (`.supervisor/requirements/orca-derived/03-worker-checkpoints.md`).
#
# A worker calls this DIRECTLY via Bash, mid-task, to leave a short structured trail at
# one of five named moments: hypothesis_confirmed | hypothesis_refuted | blocker |
# transition | slice_done. Never required, never gates anything — see agents/worker.md.
#
# Usage:  checkpoint.sh <ledger_path> <kind> <text> [paths...]
#
#   <ledger_path>  REQUIRED, FIRST POSITIONAL ARGUMENT — the session-log JSONL path to
#                  append to (typically `.supervisor/logs/{session_id}.jsonl`, handed to
#                  the worker via the spawn-template session-log pointer). This mirrors
#                  automate-helpers.sh's `learning-emit <ledger_path> <flags...>` — the
#                  in-repo precedent for an explicitly-passed, VALIDATED ledger path
#                  (memory `learning-emit-ledger-path-positional`: that exact positional
#                  argument was silently omitted twice, writing to a junk file both
#                  times — see test-checkpoint.sh for the regression case this guards).
#   <kind>         REQUIRED — one of hypothesis_confirmed|hypothesis_refuted|blocker|
#                  transition|slice_done. Any other value is a silent no-op (never a
#                  gate, never a crash — an unrecognized kind is simply not emitted).
#   <text>         REQUIRED — free text, first line = the action (advisory convention,
#                  ≤200 chars intended; defensively truncated here as a safety net, not
#                  a validation gate).
#   [paths...]     OPTIONAL — zero or more file paths touched, carried as a JSON array.
#
# Emits ONE JSONL line to <ledger_path>:
#   {"event":"worker_checkpoint","kind":"<kind>","text":"<text>","cc_session_id":"<id>","paths":[...]}
# `paths` is OMITTED from the object when no paths were given (never an empty-array
# placeholder for "nothing to say" — matches this repo's "absent evidence is an omitted
# key, never a default" convention, docs/RESULT_SCHEMAS.md).
#
# `cc_session_id` is DERIVED, never guessed: the basename of <ledger_path> minus its
# `.jsonl` suffix (the session log is named `.supervisor/logs/{session_id}.jsonl`, so the
# id is literally encoded in the path the worker was already handed). This is required for
# build-floor.sh's session classifier to count the line at all — every session-log line
# lacking `cc_session_id` is filtered out of that projector's session view before it is
# ever grouped, which would otherwise make the line invisible to `last_checkpoint`
# (docs/RESULT_SCHEMAS.md §"worker_checkpoint"). OMITTED (never a fabricated placeholder)
# if the ledger basename doesn't look like a plausible session id.
#
# FAIL-SAFE (same posture as automate-helpers.sh's learning-emit): this script must
# NEVER die/abort — a missing/invalid ledger path, a missing/invalid kind, or jq being
# unavailable all degrade to a silent no-op (write NOTHING) and exit 0. Unlike the
# hook-triggered emit-lifecycle.sh/emit-progress-event.sh (stdin payload, self-resolving
# via git-worktree anchoring), this script is invoked DIRECTLY by the worker, so it takes
# an explicit caller-supplied ledger path instead — no anchoring logic needed.
#
# Exit: 0 always.

set +e   # FAIL-SAFE: never die/abort — a failing command degrades to no-op, exit 0.

JQ="${LOOMWRIGHT_JQ_BIN:-jq}"

ledger="${1:-}"
kind="${2:-}"
text="${3:-}"
shift 3 2>/dev/null

# Missing ledger path → no-op (never write to a junk default path).
[ -n "$ledger" ] || exit 0

# Reject a kind we don't recognize — no-op rather than writing garbage.
case "$kind" in
  hypothesis_confirmed|hypothesis_refuted|blocker|transition|slice_done) ;;
  *) exit 0 ;;
esac

# Missing text → nothing meaningful to record.
[ -n "$text" ] || exit 0

# Defensive truncation (safety net, not a validation gate): keep the ledger line small
# even if a caller passes far more than the advisory ≤200-char convention.
if [ "${#text}" -gt 200 ]; then
  text="${text:0:200}"
fi

# jq-absent guard: degrade to no-op (NO write) if jq isn't runnable.
command -v "$JQ" >/dev/null 2>&1 || exit 0

# Remaining args (if any) become the `paths` array.
paths_json="$("$JQ" -cn '$ARGS.positional' --args -- "$@" 2>/dev/null)"
[ -n "$paths_json" ] || paths_json="[]"

# Derive cc_session_id from the ledger filename (see header note above). A plausible
# session id is non-empty and free of path separators / whitespace; anything else is
# left out entirely rather than emitted as a bogus value.
sess_id="$(basename "$ledger" .jsonl 2>/dev/null)"
case "$sess_id" in
  ""|*/*|*[[:space:]]*) sess_id="" ;;
esac

line="$("$JQ" -cn \
  --arg kind "$kind" --arg text "$text" --arg sid "$sess_id" --argjson paths "$paths_json" '
  {event: "worker_checkpoint", kind: $kind, text: $text}
  + (if ($sid | length) > 0 then {cc_session_id: $sid} else {} end)
  + (if ($paths | length) > 0 then {paths: $paths} else {} end)
' 2>/dev/null)"

# If the record didn't build (jq error), degrade to a no-op rather than write junk.
[ -n "$line" ] || exit 0

# Best-effort parent-dir creation (mirrors learning_emit's own convention) — the ledger
# is normally an ALREADY-EXISTING session log, so this is a defensive no-op in practice.
mkdir -p "$(dirname "$ledger")" 2>/dev/null

# Append. An invalid/unwritable ledger path (e.g. it names an existing directory, or an
# ancestor path component is a plain file) fails silently here — write NOTHING, exit 0.
printf '%s\n' "$line" >> "$ledger" 2>/dev/null

exit 0
