#!/usr/bin/env bash
# session-resume.sh — SessionStart hook helper for crash/compact recovery.
#
# Fires on SessionStart events. When `source` is `resume`, `clear`, or `compact`,
# emits a bounded (~8 KB; MAX_CHARS=8000) structured summary as `additionalContext` so the
# agent re-entering the session has immediate visibility into:
#   - in-progress Supervisor jobs (.supervisor/jobs/in-progress/)
#   - recent failed jobs (.supervisor/jobs/failed/)
#   - last 5 lines of .supervisor/state.md
#   - last 3 entries from the most recent .supervisor/logs/*.jsonl
# Stays under SessionStart's documented 10,000-char additionalContext cap.
#
# When `source` is `startup` (fresh session) → silent no-op. Startup context
# injection would create noise on every Claude Code launch even when no plugin
# work is in flight.
#
# Also runs an observability health probe (observability_probe, ST3): when
# telemetry is configured in ~/.claude/settings.json, a 1-second curl checks
# the OTLP endpoint and appends a bounded warning (with the docker-compose
# restart command) to the context output if the stack is down. Strictly
# gated — when telemetry is unconfigured the hook's output is byte-for-byte
# identical to the pre-probe behavior. Warnings are debounced via a 24h
# marker file. The probe NEVER starts docker itself.
#
# Also folds in a no-house-rules nudge (rules enforcement slice #3b-ii): when a
# plugin-active repo (.supervisor/ present) has NO applicable house rules — gated
# on the sibling read-rules.sh emitting EMPTY stdout, not on bare file presence,
# so it also fires for a store holding only invalid rules — it appends ONE
# advisory line pointing at `/rules suggest` / `/rules add`. Debounced via a 24h
# mtime-windowed marker (.supervisor/.rules-nudge-shown), mirroring the
# observability probe. A team that has deliberately opted out of house rules can
# silence it permanently with LOOMWRIGHT_RULES_NUDGE=0|off|false|no (an env-block
# gate mirroring the observability probe's opt-out — the 24h marker only
# re-suppresses per-window). Fail-safe: never fires on an error, never on a repo with
# ≥1 valid rule, and never in a truly fresh repo (that's `/setup twin`'s job, so
# it sits after the .supervisor/ bail). Adds NO new hook — hooks stay 21.
#
# INVARIANT: ALWAYS exits 0. Hook output is JSON via stdout. Silent-pass
# on any failure (no .supervisor/, no state, missing tools) so the session
# starts normally without diagnostic noise.

set -u
# Intentionally NO `set -e` / pipefail.

# ---- Read stdin -------------------------------------------------------------
INPUT="$(cat 2>/dev/null || true)"
if [ -z "$INPUT" ]; then
  exit 0
fi

# ---- Extract source field via jq (required) --------------------------------
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi
SOURCE="$(printf '%s' "$INPUT" | jq -r '.source // empty' 2>/dev/null || true)"

# Only fire on resume / clear / compact. Startup is a fresh session — no
# need to inject prior-state context.
case "$SOURCE" in
  resume|clear|compact) ;;
  *) exit 0 ;;
esac

# ---- Bail if no plugin state at all ----------------------------------------
if [ ! -d ".supervisor" ]; then
  exit 0
fi

# ---- Build the summary -----------------------------------------------------
# Compose into a temporary buffer. Hard cap at 8000 chars (well under
# Claude Code's 10K SessionStart additionalContext limit).
SUMMARY=""

append() {
  SUMMARY="$SUMMARY$1"
}

# ---- Observability health probe (ST3) ---------------------------------------
# Warns (bounded, debounced) when the user has telemetry configured but the
# OTLP observability stack is unreachable. Design constraints:
#   - Gate: BOTH .env.CLAUDE_CODE_ENABLE_TELEMETRY and
#     .env.OTEL_EXPORTER_OTLP_ENDPOINT must be present and non-empty in
#     ~/.claude/settings.json, and CLAUDE_CODE_ENABLE_TELEMETRY must not be
#     an explicit-off value ("0" / "false" — treated as unconfigured). If
#     either is absent/empty/off — or the settings file, jq, or curl is
#     missing — return immediately with ZERO output delta (AC5:
#     byte-for-byte identical to the pre-probe hook output).
#   - Probe: `curl --max-time 1` against the base of the configured OTLP
#     endpoint (any HTTP response, even 404, means the collector is up;
#     connection refused / timeout means down — hence no `-f`).
#   - Down → append a warning section to SUMMARY (so it inherits the
#     MAX_CHARS cap and stays under the 10K additionalContext bound), fire
#     notify-desktop.sh best-effort, and write a 24h debounce marker. A
#     fresh (<24h) marker suppresses the whole warning, including the
#     notification.
#   - Healthy → silent.
#   - NEVER invokes docker / docker compose — it only PRINTS the restart
#     command for the user. Every failure path returns 0 (graceful
#     degradation per skills/error-handling).
observability_probe() {
  # Gate — unconfigured / missing tooling → strict no-op.
  command -v jq >/dev/null 2>&1 || return 0
  command -v curl >/dev/null 2>&1 || return 0
  local settings="${HOME:-}/.claude/settings.json"
  [ -n "${HOME:-}" ] || return 0
  [ -f "$settings" ] || return 0
  local telemetry endpoint
  telemetry="$(jq -r '.env.CLAUDE_CODE_ENABLE_TELEMETRY // empty' "$settings" 2>/dev/null || true)"
  endpoint="$(jq -r '.env.OTEL_EXPORTER_OTLP_ENDPOINT // empty' "$settings" 2>/dev/null || true)"
  # Explicit-off ("0" / "false") is treated the same as unconfigured — a user
  # who deliberately disabled telemetry must not get down-stack warnings.
  case "$telemetry" in ""|0|false) return 0 ;; esac
  [ -n "$endpoint" ] || return 0

  # Derive the health URL: strip a trailing slash and any OTLP signal path
  # (/v1/traces|metrics|logs), then probe the base. The OTLP HTTP collector
  # answers ANY path with an HTTP response when up; curl without -f exits 0
  # on any response and non-zero only on connect failure / timeout.
  local base="$endpoint"
  base="${base%/}"
  base="${base%/v1/traces}"
  base="${base%/v1/metrics}"
  base="${base%/v1/logs}"
  # --connect-timeout bounds DNS/connect separately from --max-time (total
  # response); both keep this SessionStart probe from ever stalling startup.
  if curl -s -o /dev/null --connect-timeout 1 --max-time 1 "$base/" 2>/dev/null; then
    return 0 # healthy → silent
  fi

  # Down. 24h debounce: a fresh marker suppresses the entire warning.
  local obs_dir="${HOME}/.claude/loomwright/observability"
  local marker="$obs_dir/.last-warned"
  if [ -f "$marker" ] && [ -n "$(find "$marker" -mmin -1440 2>/dev/null)" ]; then
    return 0
  fi

  # Restart command convention: ALWAYS carry -p loomwright-observability —
  # the project name the init flow uses. Belt-and-braces with the
  # COMPOSE_PROJECT_NAME baked into the stack's generated .env: a command
  # without BOTH would derive project "observability" from the directory
  # basename and start a SECOND parallel stack on fresh empty volumes
  # (orphaning existing traces + port conflicts). Explicit -p is correct on
  # any compose version, from any cwd.
  append "### Observability stack unreachable"$'\n'
  append "Telemetry is configured (OTEL_EXPORTER_OTLP_ENDPOINT=$endpoint) but the endpoint did not respond within 1s."$'\n'
  append "- Restart it: \`docker compose -p loomwright-observability -f ~/.claude/loomwright/observability/docker-compose.yml up -d\`"$'\n'
  append "- Or run \`/setup observability\` to repair the stack."$'\n\n'

  # Best-effort desktop notification via the sibling helper. Never fails the
  # hook; notify-desktop.sh itself always exits 0.
  local script_dir
  script_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo .)"
  if [ -r "$script_dir/notify-desktop.sh" ]; then
    printf '{"hook_event_name":"Notification","notification_type":"observability_down","message":"Observability stack is down — restart: docker compose -p loomwright-observability -f ~/.claude/loomwright/observability/docker-compose.yml up -d"}' \
      | bash "$script_dir/notify-desktop.sh" >/dev/null 2>&1 || true
  fi

  mkdir -p "$obs_dir" 2>/dev/null || true
  : > "$marker" 2>/dev/null || true
  return 0
}

# ---- No-house-rules nudge (rules enforcement slice #3b-ii) ------------------
# Advisory, fail-safe, debounced nudge that fires ONLY in a plugin-active repo
# (`.supervisor/` present — guaranteed past the bail above) that has NO
# applicable house rules, telling the user to author some. Cold-start onboarding
# of a truly-fresh repo is `/setup twin`'s job, NOT this nudge — that is why the
# nudge lives strictly AFTER the `[ ! -d ".supervisor" ]` bail. Design:
#   - Gate on the READER'S OUTPUT being EMPTY (not on bare file existence): the
#     sibling read-rules.sh emits ALL valid rules and EMPTY stdout when zero
#     valid rules survive — covering an absent .agent/rules/ dir, an empty dir,
#     AND a store that holds ONLY invalid rules (all-skipped ⇒ zero valid ⇒
#     empty). So gating on empty output correctly fires the nudge for an
#     all-invalid store, and NEVER fires when ≥1 valid rule is present.
#   - read-rules.sh always exits 0 and is fail-safe (absent reader / jq missing /
#     malformed store ⇒ treated as "no nudge or safe skip", never an error). A
#     failure to even run the reader ⇒ skip the nudge (do NOT fire on an error).
#   - Debounced via an mtime-windowed marker under the already-present
#     .supervisor/ (mirrors the observability-probe 24h debounce mechanism): a
#     fresh (<24h) marker suppresses the nudge; when shown, the marker is touched
#     so it fires at most once per window.
#   - Appends exactly ONE advisory line to SUMMARY (so it inherits the MAX_CHARS
#     cap and stays under the 10K additionalContext bound).
# Every path returns 0 (graceful degradation per skills/error-handling +
# skills/monitoring-observability fail-safe idioms).
rules_nudge() {
  # Permanent opt-out: a team that has DELIBERATELY chosen not to adopt house
  # rules can silence the nudge for good via LOOMWRIGHT_RULES_NUDGE=0|off|false
  # (mirrors the observability probe's env-block gate — the 24h marker only
  # re-suppresses per-window, so without this the nudge would recur forever for
  # a rules-averse repo). Set ⇒ silent no-op.
  case "${LOOMWRIGHT_RULES_NUDGE:-}" in 0|off|false|no) return 0 ;; esac

  # Locate the sibling reader. If it's not readable, safe-skip (no nudge).
  local script_dir reader
  script_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo .)"
  reader="$script_dir/read-rules.sh"
  [ -r "$reader" ] || return 0

  # Run the reader; gate on EMPTY stdout. A non-zero exit or any read error is
  # treated as "cannot determine ⇒ no nudge" (never fire on an error path).
  local rules_out
  rules_out="$(bash "$reader" 2>/dev/null || true)"
  # Non-empty ⇒ ≥1 valid rule present ⇒ NEVER nudge.
  [ -z "$rules_out" ] || return 0

  # Debounce: a fresh (<24h) marker suppresses the nudge. The marker lives under
  # the guaranteed-present .supervisor/ (we are past the bail).
  local marker=".supervisor/.rules-nudge-shown"
  if [ -f "$marker" ] && [ -n "$(find "$marker" -mmin -1440 2>/dev/null)" ]; then
    return 0
  fi

  # Fire: append exactly ONE advisory line, then stamp the debounce marker.
  append "### House rules"$'\n'
  append "No committed house rules found — run \`/rules suggest\` to propose some, or \`/rules add\` to author."$'\n\n'
  : > "$marker" 2>/dev/null || true
  return 0
}

append "## Loomwright — prior-session context ($SOURCE)"$'\n\n'

# Section 0: observability health probe (appends only when configured + down,
# and not debounced; placed right after the header so the warning survives the
# tail-truncating MAX_CHARS cap) ----
observability_probe

# Section 0.5: no-house-rules nudge (advisory, debounced, fail-safe) ----
rules_nudge

# Section 1: in-progress Supervisor jobs ----
if compgen -G ".supervisor/jobs/in-progress/*.md" > /dev/null 2>&1; then
  append "### In-progress briefs (Supervisor was mid-run)"$'\n'
  for f in .supervisor/jobs/in-progress/*.md; do
    [ -f "$f" ] || continue
    append "- $f"$'\n'
  done
  append $'\n'
fi

# Section 2: recent failed jobs (last 5 by mtime) ----
if compgen -G ".supervisor/jobs/failed/*.md" > /dev/null 2>&1; then
  append "### Recent failed briefs (last 5)"$'\n'
  # ls -t sorts newest first; head -5 caps the count
  for f in $(ls -t .supervisor/jobs/failed/*.md 2>/dev/null | head -5); do
    append "- $f"$'\n'
  done
  append $'\n'
fi

# Section 3: tail of state.md ----
if [ -f ".supervisor/state.md" ]; then
  append "### Last 5 lines of .supervisor/state.md"$'\n'
  append '```'$'\n'
  TAIL_OUT="$(tail -5 .supervisor/state.md 2>/dev/null || true)"
  if [ -n "$TAIL_OUT" ]; then
    append "$TAIL_OUT"$'\n'
  else
    append "(state.md exists but is empty)"$'\n'
  fi
  append '```'$'\n\n'
fi

# Section 4: last 3 entries from the most recent session log ----
if compgen -G ".supervisor/logs/*.jsonl" > /dev/null 2>&1; then
  # Pick the most-recently-modified log file. The shared session-log
  # convention is .supervisor/logs/{session_id}.jsonl per CLAUDE.md.
  LATEST_LOG="$(ls -t .supervisor/logs/*.jsonl 2>/dev/null | head -1)"
  if [ -n "$LATEST_LOG" ] && [ -f "$LATEST_LOG" ]; then
    append "### Last 3 entries from $LATEST_LOG"$'\n'
    append '```'$'\n'
    LOG_TAIL="$(tail -3 "$LATEST_LOG" 2>/dev/null || true)"
    if [ -n "$LOG_TAIL" ]; then
      append "$LOG_TAIL"$'\n'
    else
      append "(log file is empty)"$'\n'
    fi
    append '```'$'\n\n'
  fi
fi

# Section 5: autonomous loop state (if any recent runs) ----
if compgen -G ".supervisor/autonomous/*/state.json" > /dev/null 2>&1; then
  RECENT_AUTO=""
  for f in .supervisor/autonomous/*/state.json; do
    [ -f "$f" ] || continue
    # Within last 24h?
    if [ -n "$(find "$f" -mmin -1440 2>/dev/null)" ]; then
      RECENT_AUTO="$RECENT_AUTO- $f"$'\n'
    fi
  done
  if [ -n "$RECENT_AUTO" ]; then
    append "### Active /autonomous sessions (state.json modified within 24h)"$'\n'
    append "$RECENT_AUTO"$'\n'
  fi
fi

# Section 6: recovery hints ----
append "### Recovery hints"$'\n'
append "- Read \`.supervisor/state.md\` for full context."$'\n'
append "- Check \`git status\` and \`git worktree list\` for in-flight changes."$'\n'
append "- Resume in-progress Supervisor work: \`/supervisor --continue task: <task_id>\`."$'\n'
append "- Resume an aborted /autonomous run: re-launch with the same requirement; the loop is single-iteration-safe to re-run."$'\n'

# ---- Hard-cap and emit -----------------------------------------------------
# Defensive ceiling well below the documented 10K additionalContext cap.
MAX_CHARS=8000
if [ "${#SUMMARY}" -gt "$MAX_CHARS" ]; then
  SUMMARY="$(printf '%s' "$SUMMARY" | head -c "$((MAX_CHARS - 32))")"
  SUMMARY="$SUMMARY"$'\n'"... [truncated — see .supervisor/ directly]"
fi

# Emit the documented SessionStart context envelope. Claude Code injects
# `hookSpecificOutput.additionalContext` — a bare top-level `additionalContext`
# is NOT recognized (it would be dropped / shown as raw JSON). jq handles safe
# JSON string escaping. Scrub to valid UTF-8 first: the byte-wise `head -c`
# truncation above can split a multibyte char, which would make jq fail and
# drop ALL context; `iconv -c` strips any invalid sequence (|| cat if iconv is
# absent).
printf '%s' "$SUMMARY" \
  | { iconv -c -f UTF-8 -t UTF-8 2>/dev/null || cat; } \
  | jq -Rs '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: .}}' 2>/dev/null \
  || true

exit 0
