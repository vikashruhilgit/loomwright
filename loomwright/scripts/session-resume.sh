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
# ≥1 valid rule, and never in a truly fresh repo (that's `/setup rules`' job, so
# it sits after the .supervisor/ bail). Adds NO new hook entry (the authoritative
# hook count is computed from hooks.json — it is deliberately NOT restated here).
#
# Also folds in a CURATION CADENCE nudge (curation-status.sh): ONE advisory line
# carrying a real count of session logs accumulated since /dreaming and /insights
# last ran, so "is what we wrote down still true?" stops depending on the user
# remembering. Debounced via a 24h mtime-windowed marker
# (.supervisor/.curation-nudge-shown) and silenced permanently by
# LOOMWRIGHT_CURATION_NUDGE=0|off|false|no — both mirroring the rules nudge.
#
#   SEAM NOTE (load-bearing, do not "simplify"): unlike the rules nudge, the
#   curation nudge ALSO fires on `source=startup` — a fresh session is exactly
#   when a cadence reminder matters most. It gets a DEDICATED `startup)` arm in
#   the `case "$SOURCE"` below rather than a widened shared gate, because
#   widening that gate would expose EVERY fresh session to the observability
#   probe's `curl` and desktop notification, the prior-session header, Sections
#   1–5, and the unconditional recovery hints. Because that arm `exit`s from
#   inside the case — ABOVE the shared `[ ! -d ".supervisor" ]` bail and ABOVE
#   the emit at the bottom — the startup arm must cover three things for itself:
#   a `.supervisor/` presence check (or it would nudge in every repo the user
#   opens — that check lives in `curation_nudge_line`, which BOTH call sites go
#   through, so it is deliberately not repeated in
#   `curation_nudge_startup_only`), its OWN `hookSpecificOutput` envelope (a bare
#   printf is dropped or shown as raw JSON), and it must be DEFINED ABOVE the
#   case (every other helper here is defined below it, which would make the call
#   rc=127).
#   The rules nudge's firing surface is UNCHANGED by this: it stays below the
#   gate and still does NOT fire on startup.
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

# ---- Curation cadence nudge (DEFINED ABOVE THE CASE ON PURPOSE) -------------
# These two functions must be defined here, above the `case "$SOURCE"` below,
# because the `startup)` arm calls one of them and then exits from inside the
# case. Every other helper in this file is defined *after* the case; a helper
# defined there would be `command not found` (rc 127) at startup — swallowed by
# the following `exit 0` and hidden by the `|| true` on the hook command.
#
# curation_nudge_line: returns the ONE advisory line on stdout, or nothing.
# Fail-safe on every path — a missing/erroring probe means NO nudge (never fire
# on an error). Order of the gates mirrors rules_nudge(): permanent env opt-out,
# then the plugin-active check, then the 24h mtime-windowed debounce marker, then
# the probe. The marker is stamped ONLY when a line is actually emitted, so a
# suppressed run does not burn the window.
curation_nudge_line() {
  case "${LOOMWRIGHT_CURATION_NUDGE:-}" in 0|off|false|no) return 0 ;; esac

  # OWN plugin-active check. The shared `[ ! -d ".supervisor" ]` bail sits BELOW
  # the case, so the startup arm never reaches it; without this the nudge would
  # fire in every repo the user opens.
  [ -d ".supervisor" ] || return 0

  # TWO RESOLUTION RULES THAT MUST STAY RECONCILED: this marker path is
  # CWD-RELATIVE, exactly like the `[ -d ".supervisor" ]` gate directly above it,
  # so the two always agree — we only ever stamp a directory we just confirmed
  # exists here. The sibling probe (curation-status.sh) resolves ITS .supervisor/
  # differently: cwd first, then a `git rev-parse --show-toplevel` fallback. If
  # the cwd-relative gate above is ever relaxed to match the probe's git-root
  # rule, THIS path must be relaxed in the same edit — otherwise the debounce
  # marker lands in a `./.supervisor` the probe never reads, and the nudge fires
  # on every single session start with the window silently never taken.
  local marker=".supervisor/.curation-nudge-shown"
  if [ -f "$marker" ] && [ -n "$(find "$marker" -mmin -1440 2>/dev/null)" ]; then
    return 0
  fi

  local script_dir probe line
  script_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo .)"
  probe="$script_dir/curation-status.sh"
  [ -r "$probe" ] || return 0

  # The probe is LOCAL-ONLY by construction: `nudge` never calls gh or curl, so
  # this adds no network latency to session start.
  line="$(bash "$probe" nudge 2>/dev/null || true)"
  [ -n "$line" ] || return 0

  # BRACES ARE LOAD-BEARING: on a bare `: > "$marker" 2>/dev/null`, the shell
  # reports a failed redirection (e.g. a read-only .supervisor/) BEFORE the
  # `2>/dev/null` on that same simple command takes effect, so "Permission
  # denied" still reaches stderr — violating this file's silent-pass invariant.
  # Wrapping in `{ ...; }` puts the redirection on the group, which does capture
  # it. Same shape at rules_nudge's marker write.
  { : > "$marker"; } 2>/dev/null || true
  printf '%s' "$line"
  return 0
}

# curation_nudge_startup_only: the `startup)` arm's whole body. Emits its OWN
# SessionStart envelope because it exits above the shared emit at the bottom of
# this file — a bare `printf` of the line is NOT recognized by Claude Code (it is
# dropped, or shown as raw JSON), so the `iconv -c` + `jq -Rs` chain is
# duplicated here deliberately rather than shared.
#
# It deliberately does NOT repeat the `[ -d ".supervisor" ]` check: curation_nudge_line
# opens with that identical predicate, in this same process, at this same cwd,
# with no intervening state change — a second copy could only ever agree with the
# first. (curation-status.sh's own `[ -d "$SUP_DIR" ]` is a THIRD copy and is
# legitimate: different process, and it resolves the root via the git toplevel.)
curation_nudge_startup_only() {
  local line
  line="$(curation_nudge_line)"
  [ -n "$line" ] || return 0
  printf '%s' "$line" \
    | { iconv -c -f UTF-8 -t UTF-8 2>/dev/null || cat; } \
    | jq -Rs '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: .}}' 2>/dev/null \
    || true
  return 0
}

# Only fire the prior-state summary on resume / clear / compact. Startup is a
# fresh session — it gets the curation nudge and NOTHING else (see the SEAM NOTE
# in the header): no observability probe, no prior-session header, no sections,
# no recovery hints, no house-rules nudge.
case "$SOURCE" in
  resume|clear|compact) ;;
  startup) curation_nudge_startup_only; exit 0 ;;
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
# of a truly-fresh repo is `/setup rules`' job, NOT this nudge — that is why the
# nudge lives strictly AFTER the `[ ! -d ".supervisor" ]` bail. Design:
#   - Gate on the READER'S OUTPUT being EMPTY (not on bare file existence): the
#     sibling read-rules.sh emits ALL valid rules and EMPTY stdout when zero
#     valid rules survive — covering an absent .agent/rules/ dir, an empty dir,
#     AND a store that holds ONLY invalid rules (all-skipped ⇒ zero valid ⇒
#     empty). So gating on empty output correctly fires the nudge for an
#     all-invalid store, and NEVER fires when ≥1 valid rule is present.
#   - THE NO-ARG CALL BELOW IS LOAD-BEARING — DO NOT "SCOPE" IT. read-rules.sh
#     routes on each rule's `applies_to` when it is given touched paths, but a
#     ZERO-ARG call fails OPEN and stays REPO-WIDE by contract, precisely so
#     this gate keeps seeing every valid rule. Passing a path set here would
#     make the nudge fire on any repo whose rules all happened to be scoped
#     elsewhere — i.e. tell a repo that HAS house rules that it has none. See
#     "PATH ROUTING" in read-rules.sh's header and skills/rules/SKILL.md §3;
#     pinned by test-read-rules.sh (j4) and test-rules-seams.sh [shape ii].
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
  # Braces load-bearing — see curation_nudge_line's marker write: a bare
  # `: > "$m" 2>/dev/null` still prints the redirection error to stderr.
  { : > "$marker"; } 2>/dev/null || true
  return 0
}

append "## Loomwright — prior-session context ($SOURCE)"$'\n\n'

# Section 0: observability health probe (appends only when configured + down,
# and not debounced; placed right after the header so the warning survives the
# tail-truncating MAX_CHARS cap) ----
observability_probe

# Section 0.5: no-house-rules nudge (advisory, debounced, fail-safe) ----
rules_nudge

# Section 0.6: curation cadence nudge (advisory, debounced, fail-safe) ----
# Same line the startup arm emits; here it is appended to SUMMARY so it inherits
# the MAX_CHARS cap. Emits NOTHING when nothing is pending (no empty header).
CURATION_LINE="$(curation_nudge_line)"
if [ -n "$CURATION_LINE" ]; then
  append "$CURATION_LINE"$'\n\n'
fi

# Section 1: in-progress Supervisor briefs — RECONCILED, not asserted ----
#
# HISTORY (do not regress): this section used to list every file in
# .supervisor/jobs/in-progress/ under the heading "In-progress briefs
# (Supervisor was mid-run)". That heading is an ASSERTION the hook cannot
# make. The brief lifecycle move to done/ is a PROMPT-INSTRUCTED completion-tail
# step (skills/self-heal-advisory/SKILL.md step 2), so an agent that dies before
# reaching it — e.g. a Phase 4.5 reviewer failing with a server error, observed
# 2026-08-30 on PR #160 — strands a brief whose PR has already merged and
# shipped. The old wording then pointed the reader at `/supervisor --continue`
# for work that was already on the base branch, and repeated that lie every
# session until a human moved the file by hand.
#
# We now classify via the sibling reconcile-jobs.sh and report only what the
# disk can evidence. That script is OFFLINE BY CONSTRUCTION (it never calls the
# forge CLI) precisely because this hook runs on every resume, where a network
# round-trip would be a latency and offline-correctness problem.
#
# Fail-safe: an absent, unreadable or silent reconciler falls back to a NEUTRAL
# listing — never back to the old claim. Nothing here can fail the hook.
HAS_UNKNOWN_BRIEF=0
if compgen -G ".supervisor/jobs/in-progress/*.md" > /dev/null 2>&1; then
  SR_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo .)"
  RECONCILER="$SR_DIR/reconcile-jobs.sh"
  PORCELAIN=""
  [ -r "$RECONCILER" ] && PORCELAIN="$(bash "$RECONCILER" --porcelain 2>/dev/null || true)"

  if [ -z "$PORCELAIN" ]; then
    append "### In-progress briefs (state UNVERIFIED — reconciler unavailable)"$'\n'
    for f in .supervisor/jobs/in-progress/*.md; do
      [ -f "$f" ] || continue
      append "- $f"$'\n'
    done
    append $'\n'
    HAS_UNKNOWN_BRIEF=1
  else
    STRANDED=""
    UNKNOWN=""
    while IFS=$'\t' read -r st path ev; do
      [ -n "${st:-}" ] || continue
      case "$st" in
        unknown) UNKNOWN="${UNKNOWN}- ${path}"$'\n' ;;
        *)       STRANDED="${STRANDED}- ${path}"$'\n'"  - evidence: ${ev}"$'\n' ;;
      esac
    done <<< "$PORCELAIN"

    if [ -n "$STRANDED" ]; then
      append "### Stranded briefs — lifecycle move never ran (NOT resumable)"$'\n'
      append "These briefs sit in in-progress/ but the disk says their work already completed."$'\n'
      append "Do NOT resume them. Finish the move with: \`bash $RECONCILER --repair\`"$'\n'
      append "$STRANDED"
      append $'\n'
    fi
    if [ -n "$UNKNOWN" ]; then
      append "### In-progress briefs (possibly mid-run — UNVERIFIED)"$'\n'
      append "No offline evidence either way; unverified is not the same as stale."$'\n'
      append "$UNKNOWN"
      append $'\n'
      HAS_UNKNOWN_BRIEF=1
    fi
  fi
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
if [ "${HAS_UNKNOWN_BRIEF:-0}" -eq 1 ]; then
  append "- Resume in-progress Supervisor work: \`/supervisor --continue task: <task_id>\` (only for briefs listed UNVERIFIED above — never for stranded ones)."$'\n'
fi
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
