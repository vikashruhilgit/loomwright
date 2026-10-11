#!/usr/bin/env bash
# guard-lane-wait-armed.sh — Stop hook: the `/automate --parallel` coordinator cannot end a turn with
# its lane watcher disarmed (lane-guardrails part 1).
#
# WHY: a lane that needs the owner records its question and exits; only the COORDINATOR session (the
# one that typed `/automate --parallel`) can relay it. `automate-lanes.sh lane-wait` is the token-free
# watcher whose exit wakes the coordinator, and the coordinator must RE-ARM it after every event
# (skills/automate-loop/SKILL.md §14 per-wave step 8). That re-arm was prose only: when the model
# forgot it, lane questions sat unseen (wave W3, 2026-10-11: 22–24 min waits). This hook makes the
# forgotten re-arm visible at the one moment it matters — the coordinator's turn end.
#
# CONTRACT: `type: command` Stop hook; ALWAYS exits 0; prints exactly ONE JSON object on stdout:
#   {}                                            allow (the default, and every error path)
#   {"decision":"block","reason":"…"}             the documented Stop block shape (docs/HOOKS.md
#                                                 "Command-validator decision shape"); the runtime
#                                                 feeds `reason` back as the next instruction
# It BLOCKS only when ALL hold:
#   1. the payload's continuation flag is not true (a turn already continued by a Stop block is never
#      blocked again, so this hook cannot loop);
#   2. the payload has no top-level `agent_type` (a plain main thread — an agent / lane session is never
#      the coordinator; docs/HOOKS.md "Stop payload identity");
#   3. the payload `cwd` (or its git toplevel) holds `.supervisor/run.lock` owned by
#      `automate-lanes:<run_id>` whose recorded `session_id` EQUALS the payload `session_id` — only the
#      coordinator session is ever nudged; every other session working in the repo is allowed;
#   4. `<run_id>.lanes` exists and `<run_id>.md` does not read `## Status: done`;
#   5. some lane is LIVE (its quick state is in automate-lanes.sh's `_LANES_WAIT_LIVE` — the very set
#      lane-wait uses, read from there, never restated) OR holds an unanswered question that lane-wait
#      has not yet reported (its `question <lane> <id>` key is absent from `<run_id>.lane-wait-seen`;
#      a REPORTED question is the coordinator's to relay, and re-blocking on it would ping-pong: the
#      re-armed watcher exits idle at once when no lane is live);
#   6. no live lane-wait: the marker `<run_id>.lane-wait.pid` is absent, or its pid fails `kill -0`, or
#      `ps -ww -o command=` of that pid does not name both `lane-wait` and the run id (pid reuse), AND
#      no running `background_tasks[]` entry mentions `lane-wait` (the watcher was just launched and has
#      not written its marker yet). On that path the marker is re-read once after 0.1 s.
# The lane states come from `_lanes_quick_state` (automate-lanes.sh, sourced): the lane table, lane
# process liveness (`lanes_proc_alive`) and the lane inbox only — no gh, no ci-slot, no full
# `lane-status` reconcile — so the hook stays fast at every turn end of every session.
#
# FAIL SAFE: this is a reminder, not a correctness gate (a wedged main thread is worse than a missed
# nudge): missing jq, an unparseable payload, an unreadable lock / table, a missing automate-lanes.sh —
# every one prints `{}`. The `|| true` on its hooks.json leaf is therefore correct (CLAUDE.md "Plugin
# Hooks"): it never blocks through its exit code.
#
# Writes nothing. Reads: the payload, `.supervisor/run.lock/meta`, `.supervisor/automate/<run_id>.{md,
# lanes,lane-wait.pid,lane-wait-seen,<lane>.answer-pending.json}`, each lane's `.supervisor/inbox/`.
set -u

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || HOOK_DIR=""
LANES_SH="${HOOK_DIR:+$HOOK_DIR/}automate-lanes.sh"

allow() { printf '{}\n'; exit 0; }

command -v jq >/dev/null 2>&1 || allow
IN="$(cat 2>/dev/null)" || allow
[ -n "$IN" ] || allow

# One parse: the continuation flag, agent_type presence, session_id, cwd, a running background lane-wait.
# Fields are joined with US (0x1f), never a tab: IFS whitespace would merge an EMPTY field into the next.
FIELDS="$(jq -r 'if type != "object" then error("not an object") else . end
  | [ (if .stop_hook_active == true then "1" else "0" end),
      (if (has("agent_type") and .agent_type != null and .agent_type != "") then "1" else "0" end),
      ((.session_id // "") | tostring | gsub("[\u001f\n]"; "")),
      ((.cwd // "") | tostring | gsub("[\u001f\n]"; "")),
      (if any((.background_tasks // [])[]?; ((.status // "running") == "running") and (tostring | test("lane-wait"))) then "1" else "0" end)
    ] | join("\u001f")' <<<"$IN" 2>/dev/null)" || allow
IFS="$(printf '\037')" read -r ACTIVE HAS_AGENT SID CWD BG_WAIT <<<"$FIELDS"
[ "${ACTIVE:-1}" = 0 ] || allow
[ "${HAS_AGENT:-1}" = 0 ] || allow
[ -n "${SID:-}" ] || allow
[ -n "${CWD:-}" ] || CWD="${CLAUDE_PROJECT_DIR:-$PWD}"

# The coordinator's checkout: the cwd itself, else the cwd's git toplevel. Fast path: a cwd that IS a
# checkout root (it holds `.git`) with no run lock is allowed after two stats — no git fork.
ROOT=""
if [ -f "$CWD/.supervisor/run.lock/meta" ]; then
  ROOT="$CWD"
elif [ -e "$CWD/.git" ]; then
  allow
else
  top="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)" || allow
  [ -n "$top" ] && [ -f "$top/.supervisor/run.lock/meta" ] || allow
  ROOT="$top"
fi
META="$ROOT/.supervisor/run.lock/meta"
OWNER="$(awk -F'\t' '$1 == "owner" { v = $2 } END { print v }' "$META" 2>/dev/null)" || allow
LOCK_SID="$(awk -F'\t' '$1 == "session_id" { v = $2 } END { print v }' "$META" 2>/dev/null)" || allow
case "$OWNER" in automate-lanes:*) ;; *) allow ;; esac
[ -n "$LOCK_SID" ] && [ "$LOCK_SID" = "$SID" ] || allow
RUN="${OWNER#automate-lanes:}"
case "$RUN" in ''|.*|*/*|*[!A-Za-z0-9._-]*) allow ;; esac

AD="$ROOT/.supervisor/automate"
RF="$AD/$RUN.md"; TABLE="$AD/$RUN.lanes"; MARK="$AD/$RUN.lane-wait.pid"; SEEN="$AD/$RUN.lane-wait-seen"
[ -f "$TABLE" ] && [ -r "$TABLE" ] || allow
grep -qE '^## Status:[[:space:]]*done([^A-Za-z0-9_]|$)' "$RF" 2>/dev/null && allow

# watcher_live — the marker names a live process that is a lane-wait for this run.
watcher_live() {
  local p cmd
  p="$(awk 'NR == 1 { print $1 }' "$MARK" 2>/dev/null)"
  case "$p" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$p" 2>/dev/null || return 1
  cmd="$(ps -ww -o command= -p "$p" 2>/dev/null)"
  case "$cmd" in *lane-wait*"$RUN"*|*"$RUN"*lane-wait*) return 0 ;; esac
  return 1
}
watcher_live && allow
[ "${BG_WAIT:-0}" = 1 ] && allow

# Reuse lane-wait's own definitions: _LANES_WAIT_LIVE, lanes_proc_alive, _lanes_quick_state.
[ -n "$HOOK_DIR" ] && [ -r "$LANES_SH" ] || allow
# shellcheck source=automate-lanes.sh
. "$LANES_SH" >/dev/null 2>&1 || allow
command -v _lanes_quick_state >/dev/null 2>&1 || allow
LIVE_SET="$(jq -r '.[]' <<<"${_LANES_WAIT_LIVE:-[]}" 2>/dev/null)"
[ -n "$LIVE_SET" ] || allow

TAB="$(printf '\t')"; NL="$(printf '\nx')"; NL="${NL%x}"
STATES=""; NEED=0; QNOTE=""
while IFS="$TAB" read -r lane path _item _run pid st _sid ts _rest; do
  case "$lane" in L[0-9]|L[0-9][0-9]) ;; *) continue ;; esac
  s="$(_lanes_quick_state "$path" "$pid" "$st" "$ts" "$AD/$RUN.$lane.answer-pending.json" 2>/dev/null)"
  [ -n "$s" ] || continue
  if grep -qxF -- "$s" <<<"$LIVE_SET"; then
    NEED=1; STATES="$STATES${STATES:+, }$lane $s"
  fi
  # Every unanswered question lane-wait has not reported yet (removed / abandoned lanes never count).
  case "$ts" in removed|abandoned) continue ;; esac
  for q in "$path"/.supervisor/inbox/questions/*.json; do
    [ -f "$q" ] || continue
    qid="$(basename "$q" .json)"
    [ -e "$path/.supervisor/inbox/answers/$qid.json" ] && continue
    grep -qxF -- "question $lane $qid" "$SEEN" 2>/dev/null && continue
    NEED=1
    case ", $STATES" in *", $lane "*) ;; *) STATES="$STATES${STATES:+, }$lane $s" ;; esac
    QNOTE="$QNOTE${QNOTE:+; }$lane $qid"
  done
done < "$TABLE"
[ "$NEED" = 1 ] || allow

# Last look: a watcher launched in the same breath as this turn end may not have written its marker yet.
sleep 0.1
watcher_live && allow

REASON="A --parallel wave is live ($RUN: $STATES) and no lane-wait watcher is running — the owner would not see a lane's question."
[ -n "$QNOTE" ] && REASON="$REASON A lane question is pending and unrelayed ($QNOTE) — relay it to the owner first (bash $LANES_SH lane-status $RF --inbox)."
REASON="$REASON Arm it as a BACKGROUND command: bash $LANES_SH lane-wait $RF (SKILL §14 step 8), then end the turn."
OUT="$(jq -n -c --arg r "$REASON" '{decision: "block", reason: $r}' 2>/dev/null)" || allow
[ -n "$OUT" ] || allow
printf '%s\n' "$OUT"
exit 0
