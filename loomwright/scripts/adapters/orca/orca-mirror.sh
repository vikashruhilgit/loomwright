#!/usr/bin/env bash
# orca-mirror.sh — ADAPTER (loomwright/scripts/adapters/orca/). Mirrors this
# plugin's own recorded lifecycle/checkpoint events into `orca` (a SEPARATE CLI
# tool — https://onorca.dev), ONLY when `orca` happens to be installed and
# configured. Never a dependency, never touches core (agents/skills/commands),
# never breaks anything when `orca` is absent — which it is on this dev
# machine as of 2026-09-11 (source requirement
# .supervisor/requirements/orca-derived/06-orca-adapter.md). See
# loomwright/docs/ARCHITECTURE_CONTRACTS.md §"Portability" for the core/adapter
# rule this file implements.
#
# INVOCATION (two shapes, caller's choice — documented rather than picked
# silently):
#   orca-mirror.sh '<event-json>'         # positional $1 — the PRIMARY shape.
#                                          # Mirrors checkpoint.sh's direct-call
#                                          # convention: a caller that already
#                                          # holds the event as a shell variable
#                                          # (e.g. close-stranded-run.sh's own
#                                          # $LINE, built just before it appends
#                                          # to the session log) passes it
#                                          # straight through with no extra
#                                          # process for a pipe.
#   echo '<event-json>' | orca-mirror.sh  # stdin fallback, used ONLY when $1 is
#                                          # empty/absent — for a caller that
#                                          # already has the payload on a pipe
#                                          # (e.g. a future hook-style call site
#                                          # that reads a hook payload from
#                                          # stdin, the close-stranded-run.sh /
#                                          # hook-dispatch-on-pr-create.sh
#                                          # convention).
#
# FAIL-SAFE: this script exits 0 on EVERY path — missing `orca`, a failed
# `orca status` probe, malformed/empty event JSON, an unrecognized event type,
# an `orca` invocation itself failing. Nothing here ever blocks or fails the
# caller. Same posture as checkpoint.sh / close-stranded-run.sh: `set +e`, no
# `set -e`, every failure mode absorbed to a silent no-op.
#
# CHEAPEST GATE FIRST: `command -v orca` is checked BEFORE anything else —
# before even reading $1/stdin — so an `orca`-less machine (today's actual
# state here) pays no cost beyond one `command -v` call and attempts no
# subprocess, ever.
#
# PROBE-ONCE-PER-RUN (cached, not per-event)
#   Once `orca` is confirmed on PATH, `orca status --json` is the liveness /
#   configuration probe (a real-but-broken/unconfigured `orca` must no-op just
#   like an absent one). Because this script is invoked ONCE PER EVENT (it is
#   not a long-running daemon — there is no in-process state to cache in), the
#   only way to make the probe fire at most once across a whole RUN's worth of
#   events is a file-backed cache the CALLER can scope:
#
#     LOOMWRIGHT_ORCA_STATUS_CACHE   — RECOMMENDED: the caller (e.g. a
#       Supervisor run) sets this ONCE, to a path scoped to that run/session
#       (e.g. .supervisor/logs/<session_id>.orca-probe-cache), so every
#       orca-mirror.sh invocation within that run shares one cache file and
#       therefore one probe.
#     (unset)                       — falls back to a single machine-wide file
#       under $TMPDIR (or /tmp). This still gives per-burst caching to a
#       caller that never sets the env var, bounded by a TTL
#       (LOOMWRIGHT_ORCA_PROBE_TTL_SECONDS, default 300s) so a transient
#       "orca is broken" verdict cannot freeze mirroring off forever once
#       orca comes back — the same fail-toward-recoverable asymmetry
#       close-stranded-run.sh documents for its own status choice.
#
#   Cache file format: one line, "<epoch_ts> ok|fail". No file locking: a race
#   between two concurrent processes can cause an extra probe — this is an
#   EFFICIENCY cache, not a correctness gate, so that is an accepted,
#   documented limitation, not a bug.
#
# EVENT MAPPING (four recognized event types; anything else is a silent
# no-op). See also loomwright/docs/ARCHITECTURE_CONTRACTS.md §"Portability".
#
# EVENT TYPE KEY: `pr_created` / `worker_checkpoint` / `session_end` lines are
# written with an `"event":` key (cross-checked against build-floor.sh,
# test-build-floor.sh, and test-curation-status.sh fixtures). `phase_transition`
# is the ONE outlier: docs/TELEMETRY.md (search "phase_transition events")
# documents it as agent-written with a `"type":"phase_transition"` key, not
# `"event"` — confirmed by a real fixture line from this repo's own history
# (pre-v15.16.0 `skills/state-management/SKILL.md`):
# `{"ts":"2026-03-09T14:30:00Z","type":"phase_transition","from":"INIT","to":"ACQUIRE","task_id":"user-auth"}`
# — the target phase lives in `to`, not `phase`. So the event-type dispatch
# key below is read as `.event // .type`, which resolves either convention
# without a per-event special case.
#
#   phase_transition {type, from, to}
#     to == SELF_HEAL (case-insensitive)                -> orca --workspace-status in-review
#     anything else (incl. absent/unrecognized)          -> orca --workspace-status in-progress
#     Orca's model is two-state (in-progress/in-review); this plugin's own
#     lifecycle has more phases than that (ACQUIRE, PRE_FLIGHT_SYNC, PLAN,
#     EXECUTE, FINALIZE, SELF_HEAL, LOOP — agents/supervisor.md's current 7
#     phases; there is no `review` phase in the live prompt), so this is a
#     DELIBERATE, documented many-to-two collapse: only the SELF_HEAL
#     (review/heal) phase reads as "in review" to Orca; every other phase
#     defaults to "in-progress" — showing active work as in-progress is less
#     misleading than prematurely marking it ready for review.
#
#   pr_created {event, url}
#     -> orca --workspace-status in-review
#     -> a read-before-write comment post containing the PR URL (see COMMENT
#        PRESERVATION below); skipped entirely if the URL is absent/empty.
#     The PR-URL field is read as `.url // .pr_url`, matching the real
#     session-log `pr_created` event's own convention — NOT
#     SUPERVISOR_RESULT.pr_url (docs/RESULT_SCHEMAS.md), a different,
#     top-level Supervisor result schema this event is not. Confirmed by two
#     independent fixtures that both spell the key `url`:
#     test-curation-status.sh's live `pr_created` fixture
#     (`{"event":"pr_created","url":"x"}`) and the pre-v15.16.0
#     `state-management/SKILL.md` fixture (recoverable via `git show
#     a799b33:loomwright/skills/state-management/SKILL.md`, the same fixture
#     cited above for the phase_transition shape fix):
#     `{"ts":"2026-03-09T14:33:00Z","type":"pr_created","task_id":"user-auth","pr_number":42,"url":"https://github.com/org/repo/pull/42"}`.
#     `pr_url` is kept as a fallback only, for forward-compat with a future
#     writer that adopts the SUPERVISOR_RESULT spelling.
#
#   worker_checkpoint {event, kind, text, cc_session_id?, paths?}
#     (checkpoint.sh's own shape — loomwright/scripts/checkpoint.sh, item 03)
#     -> a read-before-write comment post containing `text` (defensively
#        truncated to 200 chars, mirroring checkpoint.sh's own safety-net
#        truncation — not a validation gate).
#
#   session_end {event, status, reason?, ...}
#     (close-stranded-run.sh / docs/RESULT_SCHEMAS.md's session_end
#     hard-signal fields; status is one of the closed set documented there —
#     running|paused|completed|completed_with_escalation|failed for the
#     on-disk state.md enum, and close-stranded-run.sh itself only ever
#     writes "failed")
#     status in {completed, completed_with_escalation}  -> orca --workspace-status completed
#     status in {failed} or anything else/absent         -> orca --workspace-status todo
#     A failed or unrecognized run maps to "todo" (needs attention) rather
#     than a false "completed" — the same fail-toward-visible-follow-up
#     asymmetry close-stranded-run.sh documents for its own `failed` choice.
#
# COMMENT PRESERVATION (Orca's own "read before write" rule, per the source
# requirement)
#   Before EVERY comment post, reads the existing comment via `orca worktree
#   current --json`. ASSUMED response shape: {"comment": "<existing text or
#   empty>"} — a documented assumption: `orca` is not installed on this dev
#   machine to verify against, so a stub simulates this shape in tests
#   (test-orca-mirror.sh). Existing non-empty text is kept as the FIRST
#   line(s) of the new comment and the new content is APPENDED after it —
#   never the reverse, never a replace. If the read itself fails (orca errors,
#   empty/malformed JSON), the mirror SKIPS the comment post entirely rather
#   than risk clobbering text it could not read: an un-posted comment is
#   recoverable (retried on the next event), an overwritten human comment is
#   not — the same asymmetry close-stranded-run.sh applies to a live-run false
#   positive.
#
# INJECTION SAFETY
#   Every value read out of the event JSON goes through `jq -r` (never
#   grep/sed string-slicing of the raw JSON), and every `orca` invocation is
#   built as a bash ARRAY / direct argv (never a single interpolated command
#   string, never `eval`), so an event field containing shell metacharacters
#   (quotes, `$()`, backticks, `;`) can only ever become ONE argv element and
#   can never break out into a second command.
#
# CORE STAYS ORCA-FREE: this file and its test are the ONLY files under
# loomwright/ that name `orca` outside documentation — see
# loomwright/docs/ARCHITECTURE_CONTRACTS.md §"Portability" and the
# `grep -rl orca loomwright/ --exclude-dir=adapters` check
# test-orca-mirror.sh runs.
#
# Exit: 0, always.

set +e   # FAIL-SAFE: never die/abort — every failure mode degrades to no-op.

# ---- cheapest gate first: orca must be on PATH, before ANY other work -------
command -v orca >/dev/null 2>&1 || exit 0

# ---- read the event: $1 if given, else stdin --------------------------------
EVENT_JSON="${1:-}"
if [ -z "$EVENT_JSON" ]; then
  EVENT_JSON="$(cat 2>/dev/null)"
fi
[ -n "$EVENT_JSON" ] || exit 0

JQ="${LOOMWRIGHT_JQ_BIN:-jq}"
command -v "$JQ" >/dev/null 2>&1 || exit 0

# Malformed/non-object JSON -> no-op.
printf '%s' "$EVENT_JSON" | "$JQ" -e 'type == "object"' >/dev/null 2>&1 || exit 0

# ---- probe (cached per run) --------------------------------------------------
CACHE_FILE="${LOOMWRIGHT_ORCA_STATUS_CACHE:-${TMPDIR:-/tmp}/loomwright-orca-probe.cache}"
TTL="${LOOMWRIGHT_ORCA_PROBE_TTL_SECONDS:-300}"
case "$TTL" in ''|*[!0-9]*) TTL=300 ;; esac

now_epoch="$(date -u +%s 2>/dev/null || printf '0')"
case "$now_epoch" in ''|*[!0-9]*) now_epoch=0 ;; esac

orca_ok=0
use_cache=0

# MUTATION-TEST-ANCHOR: cache-read-gate (test-orca-mirror.sh's C-mutation case replaces the line below with `if false; then` to prove probe-once is load-bearing)
if [ -n "$CACHE_FILE" ] && [ -f "$CACHE_FILE" ] && [ -r "$CACHE_FILE" ]; then
  cache_line="$(head -1 "$CACHE_FILE" 2>/dev/null)"
  cache_ts="${cache_line%% *}"
  cache_status="${cache_line#* }"
  case "$cache_ts" in ''|*[!0-9]*) cache_ts="" ;; esac
  if [ -n "$cache_ts" ] && [ "$now_epoch" -gt 0 ]; then
    age=$((now_epoch - cache_ts))
    if [ "$age" -ge 0 ] && [ "$age" -lt "$TTL" ]; then
      use_cache=1
      [ "$cache_status" = "ok" ] && orca_ok=1
    fi
  fi
fi

if [ "$use_cache" -eq 0 ]; then
  if orca status --json >/dev/null 2>&1; then
    orca_ok=1
    probe_result="ok"
  else
    orca_ok=0
    probe_result="fail"
  fi
  if [ -n "$CACHE_FILE" ]; then
    mkdir -p "$(dirname "$CACHE_FILE")" 2>/dev/null
    printf '%s %s\n' "$now_epoch" "$probe_result" > "$CACHE_FILE" 2>/dev/null
  fi
fi

[ "$orca_ok" -eq 1 ] || exit 0

# ---- helpers ------------------------------------------------------------------
set_workspace_status() {
  # $1 = one of in-progress | in-review | completed | todo
  orca --workspace-status "$1" >/dev/null 2>&1
  return 0
}

# read_existing_comment -> sets EXISTING_COMMENT (possibly empty string);
# returns 1 when the read itself failed/was unparseable (caller must then skip
# the write entirely — see COMMENT PRESERVATION above).
read_existing_comment() {
  EXISTING_COMMENT=""
  local cur
  cur="$(orca worktree current --json 2>/dev/null)"
  [ -n "$cur" ] || return 1
  printf '%s' "$cur" | "$JQ" -e 'type == "object"' >/dev/null 2>&1 || return 1
  EXISTING_COMMENT="$(printf '%s' "$cur" | "$JQ" -r '.comment // empty' 2>/dev/null)"
  return 0
}

# post_comment_appending <new_text> — read-before-write; no-op (never
# clobbers) if the read fails.
post_comment_appending() {
  local new_text="$1" combined
  read_existing_comment || return 0
  if [ -n "$EXISTING_COMMENT" ]; then
    combined="$(printf '%s\n%s' "$EXISTING_COMMENT" "$new_text")"
  else
    combined="$new_text"
  fi
  orca worktree set --comment "$combined" >/dev/null 2>&1
  return 0
}

# ---- dispatch on event type ---------------------------------------------------
# `.event` covers pr_created/worker_checkpoint/session_end; `.type` covers
# phase_transition (see EVENT TYPE KEY above) — the fallback resolves both
# on-disk key conventions without a per-event special case.
EVENT_TYPE="$(printf '%s' "$EVENT_JSON" | "$JQ" -r '.event // .type // empty' 2>/dev/null)"

case "$EVENT_TYPE" in
  phase_transition)
    # Real shape has no `phase` field — the target phase is `to` (see fixture
    # cited in EVENT TYPE KEY above). Only SELF_HEAL (the one phase that
    # actually exists in agents/supervisor.md and represents review/heal work)
    # maps to in-review; every other/unrecognized value is in-progress.
    phase="$(printf '%s' "$EVENT_JSON" | "$JQ" -r '.to // empty' 2>/dev/null)"
    phase_lc="$(printf '%s' "$phase" | tr '[:upper:]' '[:lower:]')"
    case "$phase_lc" in
      self_heal) set_workspace_status "in-review" ;;
      *)         set_workspace_status "in-progress" ;;
    esac
    ;;
  pr_created)
    # Real on-disk shape spells the URL field `url` (see EVENT TYPE KEY
    # above and the fixtures cited there); `pr_url` is a forward-compat
    # fallback only, mirroring the `.event // .type` dispatch-key fallback.
    pr_url="$(printf '%s' "$EVENT_JSON" | "$JQ" -r '.url // .pr_url // empty' 2>/dev/null)"
    set_workspace_status "in-review"
    if [ -n "$pr_url" ]; then
      post_comment_appending "PR created: $pr_url"
    fi
    ;;
  worker_checkpoint)
    text="$(printf '%s' "$EVENT_JSON" | "$JQ" -r '.text // empty' 2>/dev/null)"
    if [ -n "$text" ]; then
      if [ "${#text}" -gt 200 ]; then
        text="${text:0:200}"
      fi
      post_comment_appending "$text"
    fi
    ;;
  session_end)
    status="$(printf '%s' "$EVENT_JSON" | "$JQ" -r '.status // empty' 2>/dev/null)"
    case "$status" in
      completed|completed_with_escalation) set_workspace_status "completed" ;;
      *)                                   set_workspace_status "todo" ;;
    esac
    ;;
  *)
    : # unrecognized event type -> silent no-op
    ;;
esac

exit 0
