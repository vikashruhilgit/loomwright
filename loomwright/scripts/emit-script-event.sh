#!/usr/bin/env bash
# emit-script-event.sh — report that a plugin SCRIPT's step passed, warned or failed, as
# opt-in telemetry (docs/TELEMETRY.md §"Script events"). Fire-and-forget: it ALWAYS exits 0,
# prints nothing, and never changes what the calling script prints or returns — a failing
# gate still fails in front of the user exactly as before; this only reports it as well.
#
# Usage:
#   emit-script-event.sh --root <checkout> <script> <step> <outcome> <code> \
#       [--count <key>=<int>]... [--kind <group>.<kind>=<int>]... [--caller <script>.<step>]
#
#   <outcome>  pass | fail | warn
#   <code>     a plugin-defined token (`ab_names_mismatch`, `refused`, `ok`) — never message text
#   --count    an integer tally (`a=63`); --kind a per-group count of a managed-file KIND
#              (`b_only.dismissed-decisions=3`)
#
# The payload goes to the existing telemetry wrapper (send-telemetry.sh) from <checkout>, so
# consent, the target repo, the privacy scan and the one-thread-per-code posting are the SAME
# pipeline every agent result uses: with no user-scope consent for that repo nothing is sent.
# The core accepts only allow-listed fields of allow-listed shapes (field selection), so a
# value this script is handed that is not a token or an integer is dropped there, not posted.
#
# Env:
#   LOOMWRIGHT_SCRIPT_EVENTS=0      emit nothing (kill switch)
#   LOOMWRIGHT_SCRIPT_EVENT_TEE=<f> also append the payload JSON line to <f> (test seam)
#
# Portability: bash 3.2 + BSD userland; needs python3 (absent => silent no-op, like the core).

ROOT=""
if [ "${1:-}" = "--root" ] && [ -n "${2:-}" ]; then ROOT="$2"; shift 2; fi
[ "${LOOMWRIGHT_SCRIPT_EVENTS:-1}" = "0" ] && exit 0
[ $# -ge 4 ] || exit 0
[ -n "$ROOT" ] && [ -d "$ROOT" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 0
[ -f "$HERE/send-telemetry.sh" ] || exit 0

SCRIPT="$1" STEP="$2" OUTCOME="$3" CODE="$4"; shift 4
EXTRA=""
while [ $# -gt 0 ]; do
  case "$1" in
    --count|--kind|--caller) [ $# -ge 2 ] || break; EXTRA="$EXTRA$1"$'\t'"$2"$'\n'; shift 2 ;;
    *) shift ;;
  esac
done

EVENT_ID="$(date -u +%Y%m%d%H%M%S 2>/dev/null)-$$-${RANDOM:-0}"
JSON="$(printf '%s' "$EXTRA" | python3 -I -c '
import json, sys
script, step, outcome, code, event_id = sys.argv[1:6]
p = {"kind": "script_event", "schema_version": 1, "script": script, "step": step,
     "outcome": outcome, "code": code, "event_id": event_id, "counts": {}, "kinds": {}}
for line in sys.stdin.read().splitlines():
    flag, _, val = line.partition("\t")
    if flag == "--caller":
        p["caller"] = val
        continue
    key, _, num = val.partition("=")
    try:
        n = int(num)
    except ValueError:
        continue
    if flag == "--count":
        p["counts"][key] = n
    elif flag == "--kind":
        group, _, kind = key.partition(".")
        p["kinds"].setdefault(group, {})[kind] = n
print(json.dumps(p, sort_keys=True))
' "$SCRIPT" "$STEP" "$OUTCOME" "$CODE" "$EVENT_ID" 2>/dev/null)" || exit 0
[ -n "$JSON" ] || exit 0

if [ -n "${LOOMWRIGHT_SCRIPT_EVENT_TEE:-}" ]; then
  printf '%s\n' "$JSON" >> "$LOOMWRIGHT_SCRIPT_EVENT_TEE" 2>/dev/null || true
fi
(cd "$ROOT" && printf '%s' "$JSON" | bash "$HERE/send-telemetry.sh") >/dev/null 2>&1 || true
exit 0
