#!/usr/bin/env bash
# curation-status.sh — curation-cadence probe for /dreaming, /insights and
# /pr-postmortem.
#
# WHY: the plugin writes continuously (session logs, worker summaries, PR churn)
# but only *checks* what it wrote when a human personally types /dreaming,
# /insights or /pr-postmortem. None of the three left a last-run trace, so
# nobody — user or agent — could tell whether running one now was worthwhile.
# This script is the one durable, fail-safe record of that cadence.
#
# INVARIANT — ALWAYS exits 0, on EVERY path. This is a runtime advisory emitter
# under CLAUDE.md's bimodal failure philosophy, never a correctness gate. It
# never blocks a session, never fails a hook, and never returns non-zero. If you
# add an `exit` here it must be `exit 0` (pinned by test-curation-status.sh).
#
# SUBCOMMANDS
#   status [--json]   per-command last_run / age_days / pending / threshold / ready
#   record dreaming   stamp /dreaming's last run (the ONLY legal record target)
#   nudge             print the ONE advisory cadence line, or NOTHING at all
#
# ONE STORED VALUE, TWO DERIVED (deliberate — a derived value cannot go stale):
#   /dreaming       ⇐ .dreaming.last_run in .supervisor/curation-state.json  (STORED)
#   /insights       ⇐ mtime of .supervisor/insights/dashboard.md            (derived)
#   /pr-postmortem  ⇐ max .ts over .supervisor/postmortem/results.jsonl
#                     records with .source != "automate_drain"              (derived)
#
#   Why /dreaming is the exception: it writes only through the memory writers, so
#   .supervisor/memory/ mtime reports the last run *that accepted something* and
#   is structurally blind to the ran-but-accepted-nothing case — which is exactly
#   what this record exists to capture. (.agent/rules/process.json's
#   derive-don't-restate rule is an ANALOGOUS PRECEDENT here, not the governing
#   authority: it is scoped to count/version claims, and this is a timestamp.)
#   RETIREMENT CONDITION: if /dreaming ever gains its own durable artifact,
#   retire .supervisor/curation-state.json and derive from that artifact instead.
#
# WHY THE LEDGER FILTER IS LOAD-BEARING: since v15.28.0
# .supervisor/postmortem/results.jsonl is a unified corpus with TWO producers,
# discriminated by .source — /pr-postmortem command runs, and engine-native
# `automate_drain` lines appended by automate-helpers.sh `learning-emit`, which
# no human ever "ran". Drain and command records interleave chronologically, so a
# bare `map(.ts)|max` reads an engine line as "you ran /pr-postmortem".
#
# THRESHOLDS ARE UNVALIDATED STARTING GUESSES. The in-script defaults
# (dreaming 15, insights 10) are guesses, not measured values; they are labelled
# as unvalidated everywhere they surface (here, in both command docs, and in the
# decline message itself). Override them in .supervisor/config.json under
# .curation.thresholds.{dreaming,insights}. This script READS config.json and
# NEVER rewrites it — that file is live (webhook_url, setup_memory.repo_allowlist,
# and transiently `auto_review`, a key the /automate single-drain invariant owns).
#
# UNREADABLE INPUT ⇒ THE STRING `unknown`, NEVER A FABRICATED `0`. A fabricated
# zero would SUPPRESS the nudge, i.e. fail silent on exactly the input we could
# not read. `unknown` means "do not suppress, but do not claim a number".
# An input that is genuinely ABSENT is a different answer: `never` / 0.
#
# LOCAL-ONLY NUDGE. `nudge` makes NO network call (no gh, no curl) — it runs
# inside a SessionStart hook and a network round-trip there is a latency hazard
# on every session start. The "merged PRs absent from the ledger" count is
# computed ONLY on an explicit `status` invocation (and only when `gh` is present
# and the repo has an `origin` remote); the nudge always reports it as `unknown`.
#
# .supervisor/curation-state.json is OPERATIONAL CADENCE, not curated judgment:
# it stays gitignored (covered by the existing `.supervisor/*` rule) and is NOT
# part of the committed-twin surface /setup memory manages.

set -u
# Intentionally NO `set -e` / pipefail — every failure here degrades, none aborts.

# ---- Locate the .supervisor/ root -------------------------------------------
# Prefer the cwd (this is how session-resume.sh and the command shells invoke us);
# fall back to the git toplevel so an invocation from a subdirectory still works.
if [ -d "$PWD/.supervisor" ]; then
  SUP_ROOT="$PWD"
else
  _git_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "${_git_root:-}" ] && [ -d "$_git_root/.supervisor" ]; then
    SUP_ROOT="$_git_root"
  else
    SUP_ROOT="$PWD"
  fi
fi

SUP_DIR="$SUP_ROOT/.supervisor"
STATE_FILE="$SUP_DIR/curation-state.json"
LEDGER_FILE="$SUP_DIR/postmortem/results.jsonl"
DASHBOARD_FILE="$SUP_DIR/insights/dashboard.md"
CONFIG_FILE="$SUP_DIR/config.json"
LOGS_DIR="$SUP_DIR/logs"

DEFAULT_THRESHOLD_DREAMING=15
DEFAULT_THRESHOLD_INSIGHTS=10

have_jq() { command -v jq >/dev/null 2>&1; }

# ---- Portable, fail-safe primitives -----------------------------------------

# is_uint <value> — true only for a non-empty run of digits.
is_uint() {
  case "${1:-}" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

# file_mtime <path> — epoch seconds, or the literal string `unknown`.
#
# `stat -c %Y` (GNU) is tried FIRST and `stat -f %m` (BSD) only as a fallback,
# and the result is validated numeric BEFORE any arithmetic. This ordering is
# NOT cosmetic: BSD's `-f` means --file-system on GNU coreutils, so `stat -f %m`
# there SUCCEEDS WITH GARBAGE rather than failing — and an empty/garbage value
# inside `$(( ))` under `set -u` silently empties the probe. This repo shipped
# exactly that bug once (macOS-green, Linux-CI-red).
file_mtime() {
  local f="${1:-}" m=""
  [ -n "$f" ] || { printf 'unknown'; return 0; }
  [ -e "$f" ] || { printf 'unknown'; return 0; }
  m="$(stat -c %Y "$f" 2>/dev/null || true)"
  if ! is_uint "$m"; then
    m="$(stat -f %m "$f" 2>/dev/null || true)"
  fi
  if ! is_uint "$m"; then
    printf 'unknown'
    return 0
  fi
  printf '%s' "$m"
}

now_epoch() {
  local n
  n="$(date +%s 2>/dev/null || true)"
  is_uint "$n" || { printf 'unknown'; return 0; }
  printf '%s' "$n"
}

# epoch_to_iso <epoch> — ISO-8601 UTC, or `unknown`. Uses jq's `todate` rather
# than date(1) because `date -d @N` (GNU) and `date -r N` (BSD) are mutually
# incompatible, while jq is already this script's hard dependency for JSON.
epoch_to_iso() {
  local e="${1:-}" out
  is_uint "$e" || { printf 'unknown'; return 0; }
  have_jq || { printf 'unknown'; return 0; }
  out="$(jq -rn --argjson e "$e" '$e | todate' 2>/dev/null || true)"
  case "$out" in
    ????-??-??T??:??:??Z) printf '%s' "$out" ;;
    *) printf 'unknown' ;;
  esac
}

# iso_to_epoch <iso8601> — epoch seconds, or `unknown` (same portability reason).
iso_to_epoch() {
  local s="${1:-}" out
  [ -n "$s" ] || { printf 'unknown'; return 0; }
  have_jq || { printf 'unknown'; return 0; }
  out="$(jq -rn --arg s "$s" '($s | fromdateiso8601)? // empty' 2>/dev/null || true)"
  is_uint "$out" || { printf 'unknown'; return 0; }
  printf '%s' "$out"
}

# age_days <epoch> — whole days since <epoch>, or `unknown`.
age_days() {
  local e="${1:-}" n d
  is_uint "$e" || { printf 'unknown'; return 0; }
  n="$(now_epoch)"
  is_uint "$n" || { printf 'unknown'; return 0; }
  if [ "$n" -lt "$e" ]; then printf '0'; return 0; fi
  d=$(( (n - e) / 86400 ))
  printf '%s' "$d"
}

# read_threshold <dreaming|insights> <default> — from .supervisor/config.json,
# falling back to the in-script default when the file is absent, unreadable,
# malformed, or the value is not a positive integer. NEVER writes config.json.
read_threshold() {
  local key="${1:-}" fallback="${2:-0}" v
  [ -r "$CONFIG_FILE" ] || { printf '%s' "$fallback"; return 0; }
  have_jq || { printf '%s' "$fallback"; return 0; }
  v="$(jq -r --arg k "$key" '.curation.thresholds[$k] // empty' "$CONFIG_FILE" 2>/dev/null || true)"
  if is_uint "$v" && [ "$v" -gt 0 ]; then
    printf '%s' "$v"
  else
    printf '%s' "$fallback"
  fi
}

# ---- Last-run derivations ---------------------------------------------------

# /dreaming — the ONE STORED value.
#   absent state file      ⇒ never
#   unreadable state file  ⇒ unknown   (decision (f): never a fabricated answer)
#   truncated/empty/not-JSON, or no usable .dreaming.last_run ⇒ never
derive_dreaming_last_run() {
  [ -e "$STATE_FILE" ] || { printf 'never'; return 0; }
  [ -r "$STATE_FILE" ] || { printf 'unknown'; return 0; }
  have_jq || { printf 'unknown'; return 0; }
  local v
  v="$(jq -r '.dreaming.last_run // empty' "$STATE_FILE" 2>/dev/null || true)"
  [ -n "$v" ] || { printf 'never'; return 0; }
  # A present-but-unparseable timestamp is content we could read and reject ⇒
  # `never` (there is no usable record), not `unknown` (could not read).
  local e
  e="$(iso_to_epoch "$v")"
  is_uint "$e" || { printf 'never'; return 0; }
  printf '%s' "$v"
}

# /insights — derived from the dashboard's mtime.
#   absent dashboard        ⇒ never
#   unreadable / non-numeric mtime ⇒ unknown (never 0, never 1970)
derive_insights_last_run() {
  [ -e "$DASHBOARD_FILE" ] || { printf 'never'; return 0; }
  local m
  m="$(file_mtime "$DASHBOARD_FILE")"
  is_uint "$m" || { printf 'unknown'; return 0; }
  epoch_to_iso "$m"
}

# /pr-postmortem — derived from the findings ledger.
#
# THE FILTER IS THE POINT: `select(.source != "automate_drain")` excludes the
# engine-native drain lines automate-helpers.sh appends (which no human ran)
# BEFORE taking `max` of `.ts`. `fromjson?` makes it per-line tolerant so one
# malformed line cannot blank the whole derivation, and a source-less legacy
# record (`.source == null`) is correctly KEPT (null != "automate_drain").
#   absent ledger      ⇒ never
#   unreadable ledger  ⇒ unknown
#   no surviving record ⇒ never
derive_postmortem_last_run() {
  [ -e "$LEDGER_FILE" ] || { printf 'never'; return 0; }
  [ -r "$LEDGER_FILE" ] || { printf 'unknown'; return 0; }
  have_jq || { printf 'unknown'; return 0; }
  local out
  out="$(jq -rRn '
      [ inputs
        | fromjson?
        | select(type == "object")
        | select(.source != "automate_drain")
        | .ts // empty
        | select(type == "string" and length > 0)
      ]
      | if length == 0 then "never" else max end
    ' "$LEDGER_FILE" 2>/dev/null || true)"
  [ -n "$out" ] || { printf 'unknown'; return 0; }
  printf '%s' "$out"
}

# ---- Pending counts ---------------------------------------------------------

# count_logs_newer_than <epoch|never|unknown> — how many .supervisor/logs/*.jsonl
# files postdate the given last-run epoch.
#   absent logs dir    ⇒ 0        (a real, readable answer: there is no corpus)
#   unreadable logs dir⇒ unknown
#   since == never     ⇒ every log counts
#   since == unknown   ⇒ unknown  (cannot compare against a boundary we lack)
count_logs_newer_than() {
  local since="${1:-unknown}" n=0 f m
  [ -d "$LOGS_DIR" ] || { printf '0'; return 0; }
  { [ -r "$LOGS_DIR" ] && [ -x "$LOGS_DIR" ]; } || { printf 'unknown'; return 0; }
  case "$since" in
    unknown) printf 'unknown'; return 0 ;;
  esac
  for f in "$LOGS_DIR"/*.jsonl; do
    [ -f "$f" ] || continue
    if [ "$since" = "never" ]; then
      n=$((n + 1))
      continue
    fi
    m="$(file_mtime "$f")"
    is_uint "$m" || continue
    if [ "$m" -gt "$since" ]; then
      n=$((n + 1))
    fi
  done
  printf '%s' "$n"
}

# pending_for <last_run-iso|never|unknown> — resolve the last-run value to a
# comparison boundary, then count.
pending_for() {
  local last="${1:-unknown}" e
  case "$last" in
    never)   e="never" ;;
    unknown) e="unknown" ;;
    *)       e="$(iso_to_epoch "$last")" ;;
  esac
  count_logs_newer_than "$e"
}

# derive_postmortem_pending — "merged PRs absent from the ledger".
#
# STATUS-ONLY (decision (e)): this is the ONE place in this script allowed to
# touch the network, and `nudge` never calls it. Degrades to `unknown` whenever
# gh is absent, there is no `origin` remote, the probe fails, or the caller sets
# LOOMWRIGHT_CURATION_REMOTE=0.
derive_postmortem_pending() {
  case "${LOOMWRIGHT_CURATION_REMOTE:-}" in 0|off|false|no) printf 'unknown'; return 0 ;; esac
  command -v gh >/dev/null 2>&1 || { printf 'unknown'; return 0; }
  git remote get-url origin >/dev/null 2>&1 || { printf 'unknown'; return 0; }
  have_jq || { printf 'unknown'; return 0; }
  [ -r "$LEDGER_FILE" ] || { printf 'unknown'; return 0; }
  local merged have missing=0 n
  merged="$(gh pr list --state merged --limit 50 --json number -q '.[].number' 2>/dev/null || true)"
  [ -n "$merged" ] || { printf 'unknown'; return 0; }
  have="$(jq -rRn '[inputs | fromjson? | select(type == "object") | .number // empty] | .[]' \
            "$LEDGER_FILE" 2>/dev/null || true)"
  for n in $merged; do
    is_uint "$n" || continue
    printf '%s\n' "$have" | grep -qx -- "$n" || missing=$((missing + 1))
  done
  printf '%s' "$missing"
}

# ---- Readiness --------------------------------------------------------------

# readiness <pending> <threshold> — yes | no | unknown.
# An `unknown` pending count NEVER declines: decision (f) says unknown means
# "do not suppress, but do not claim a number".
readiness() {
  local pending="${1:-unknown}" threshold="${2:-0}"
  is_uint "$pending" || { printf 'unknown'; return 0; }
  is_uint "$threshold" || { printf 'unknown'; return 0; }
  if [ "$pending" -ge "$threshold" ]; then printf 'yes'; else printf 'no'; fi
}

# decline_message <command-label> <pending> <threshold> — the verbatim decline
# text, or the empty string when the command should proceed. Names the observed
# count, the threshold, AND that the threshold is an unvalidated guess.
decline_message() {
  local label="${1:-}" pending="${2:-}" threshold="${3:-}"
  printf '/%s declined: %s new session log(s) since its last run, below the threshold of %s. That threshold is an UNVALIDATED starting guess, not a measured value — re-run with --force to proceed anyway, or set .curation.thresholds.%s in .supervisor/config.json.' \
    "$label" "$pending" "$threshold" "$label"
}

# ---- Subcommand: status -----------------------------------------------------

cmd_status() {
  local as_json="no"
  case "${1:-}" in
    --json) as_json="yes" ;;
    '') ;;
    *) ;;  # unknown flags are ignored, never an error (advisory emitter)
  esac

  local d_last i_last p_last d_pending i_pending p_pending
  local d_thr i_thr d_ready i_ready d_age i_age p_age
  local d_decline="" i_decline=""

  d_last="$(derive_dreaming_last_run)"
  i_last="$(derive_insights_last_run)"
  p_last="$(derive_postmortem_last_run)"

  d_pending="$(pending_for "$d_last")"
  i_pending="$(pending_for "$i_last")"
  p_pending="$(derive_postmortem_pending)"

  d_thr="$(read_threshold dreaming "$DEFAULT_THRESHOLD_DREAMING")"
  i_thr="$(read_threshold insights "$DEFAULT_THRESHOLD_INSIGHTS")"

  d_ready="$(readiness "$d_pending" "$d_thr")"
  i_ready="$(readiness "$i_pending" "$i_thr")"

  d_age="$(age_days "$(iso_to_epoch "$d_last")")"
  i_age="$(age_days "$(iso_to_epoch "$i_last")")"
  p_age="$(age_days "$(iso_to_epoch "$p_last")")"

  [ "$d_ready" = "no" ] && d_decline="$(decline_message dreaming "$d_pending" "$d_thr")"
  [ "$i_ready" = "no" ] && i_decline="$(decline_message insights "$i_pending" "$i_thr")"

  if [ "$as_json" = "yes" ]; then
    if ! have_jq; then
      # jq absent ⇒ emit a literal all-unknown document rather than fabricating
      # values or crashing. Still valid JSON, still exit 0.
      printf '%s\n' '{"schema_version":1,"jq":false,"thresholds_unvalidated":true,"commands":{"dreaming":{"last_run":"unknown","age_days":"unknown","pending":"unknown","threshold":"unknown","ready":"unknown","decline_message":""},"insights":{"last_run":"unknown","age_days":"unknown","pending":"unknown","threshold":"unknown","ready":"unknown","decline_message":""},"pr_postmortem":{"last_run":"unknown","age_days":"unknown","pending":"unknown","threshold":"none","ready":"always","decline_message":""}}}'
      return 0
    fi
    jq -n \
      --arg dl "$d_last" --arg da "$d_age" --arg dp "$d_pending" --arg dt "$d_thr" --arg dr "$d_ready" --arg dm "$d_decline" \
      --arg il "$i_last" --arg ia "$i_age" --arg ip "$i_pending" --arg it "$i_thr" --arg ir "$i_ready" --arg im "$i_decline" \
      --arg pl "$p_last" --arg pa "$p_age" --arg pp "$p_pending" \
      '
      def num_or_str: if test("^[0-9]+$") then tonumber else . end;
      {
        schema_version: 1,
        jq: true,
        thresholds_unvalidated: true,
        commands: {
          dreaming:      {last_run: $dl, age_days: ($da|num_or_str), pending: ($dp|num_or_str), threshold: ($dt|num_or_str), ready: $dr, decline_message: $dm},
          insights:      {last_run: $il, age_days: ($ia|num_or_str), pending: ($ip|num_or_str), threshold: ($it|num_or_str), ready: $ir, decline_message: $im},
          pr_postmortem: {last_run: $pl, age_days: ($pa|num_or_str), pending: ($pp|num_or_str), threshold: "none", ready: "always", decline_message: ""}
        }
      }' 2>/dev/null || printf '%s\n' '{"schema_version":1,"jq":true,"error":"render_failed"}'
    return 0
  fi

  printf '## Curation readiness\n'
  printf 'Thresholds are UNVALIDATED starting guesses (not measured) — tune .curation.thresholds.{dreaming,insights} in .supervisor/config.json.\n'
  printf -- '- /dreaming       last_run=%s age_days=%s pending=%s threshold=%s ready=%s\n' \
    "$d_last" "$d_age" "$d_pending" "$d_thr" "$d_ready"
  printf -- '- /insights       last_run=%s age_days=%s pending=%s threshold=%s ready=%s\n' \
    "$i_last" "$i_age" "$i_pending" "$i_thr" "$i_ready"
  printf -- '- /pr-postmortem  last_run=%s age_days=%s pending=%s threshold=none ready=always (targeted at one named PR — it never declines)\n' \
    "$p_last" "$p_age" "$p_pending"
  [ -n "$d_decline" ] && printf -- '- decline(/dreaming): %s\n' "$d_decline"
  [ -n "$i_decline" ] && printf -- '- decline(/insights): %s\n' "$i_decline"
  return 0
}

# ---- Subcommand: record -----------------------------------------------------

# `dreaming` is the ONLY legal record target — /insights and /pr-postmortem are
# DERIVED (see the header). Any other argument is rejected with a message and
# still exits 0.
cmd_record() {
  local target="${1:-}"
  case "$target" in
    dreaming) ;;
    *)
      printf 'curation-status: `record` accepts only `dreaming` (got: %s).\n' "${target:-<none>}"
      printf 'curation-status: /insights and /pr-postmortem last-run values are DERIVED (dashboard mtime / ledger max .ts) and must not be restated here.\n'
      return 0
      ;;
  esac

  if ! have_jq; then
    printf 'curation-status: jq is absent — cannot record /dreaming last_run (no value written).\n'
    return 0
  fi

  mkdir -p "$SUP_DIR" 2>/dev/null || {
    printf 'curation-status: could not create %s — /dreaming last_run not recorded.\n' "$SUP_DIR"
    return 0
  }

  local now_iso existing tmp
  now_iso="$(jq -rn 'now | floor | todate' 2>/dev/null || true)"
  if [ -z "$now_iso" ]; then
    printf 'curation-status: could not compute the current timestamp — /dreaming last_run not recorded.\n'
    return 0
  fi

  existing='{}'
  if [ -r "$STATE_FILE" ]; then
    local parsed
    parsed="$(jq -c '.' "$STATE_FILE" 2>/dev/null || true)"
    case "$parsed" in
      '{'*) existing="$parsed" ;;   # only an object survives; anything else resets
    esac
  fi

  tmp="$STATE_FILE.tmp.$$"
  if printf '%s' "$existing" \
     | jq --arg ts "$now_iso" '.dreaming = ((.dreaming // {}) + {last_run: $ts})' > "$tmp" 2>/dev/null \
     && mv "$tmp" "$STATE_FILE" 2>/dev/null; then
    printf 'curation-status: recorded /dreaming last_run=%s\n' "$now_iso"
  else
    rm -f "$tmp" 2>/dev/null || true
    printf 'curation-status: could not write %s — /dreaming last_run not recorded.\n' "$STATE_FILE"
  fi
  return 0
}

# ---- Subcommand: nudge ------------------------------------------------------

# Prints ONE advisory line carrying a real COUNT, or NOTHING AT ALL when nothing
# is pending (no empty header, no blank section). LOCAL-ONLY: it never calls gh
# or curl — /pr-postmortem's pending count is reported as `unknown` here by
# construction and is never probed.
#
# A command is "pending" when its readiness is `yes` (count at/above threshold)
# or `unknown` (we could not read the input — decision (f): do not suppress).
# Only a real, readable, below-threshold count silences it.
#
# jq absent ⇒ silent. Not a fabricated zero: without jq no trustworthy count can
# be produced, and the sole hook caller (session-resume.sh) has already exited at
# its own `command -v jq` gate, so this path is unreachable from the hook.
cmd_nudge() {
  case "${LOOMWRIGHT_CURATION_NUDGE:-}" in 0|off|false|no) return 0 ;; esac
  [ -d "$SUP_DIR" ] || return 0
  have_jq || return 0

  local d_last i_last d_pending i_pending d_thr i_thr d_ready i_ready parts=""

  d_last="$(derive_dreaming_last_run)"
  i_last="$(derive_insights_last_run)"
  d_pending="$(pending_for "$d_last")"
  i_pending="$(pending_for "$i_last")"
  d_thr="$(read_threshold dreaming "$DEFAULT_THRESHOLD_DREAMING")"
  i_thr="$(read_threshold insights "$DEFAULT_THRESHOLD_INSIGHTS")"
  d_ready="$(readiness "$d_pending" "$d_thr")"
  i_ready="$(readiness "$i_pending" "$i_thr")"

  case "$d_ready" in
    yes|unknown) parts="/dreaming $d_pending new session log(s) since $d_last (threshold $d_thr)" ;;
  esac
  case "$i_ready" in
    yes|unknown)
      if [ -n "$parts" ]; then parts="$parts; "; fi
      parts="$parts/insights $i_pending new session log(s) since $i_last (threshold $i_thr)"
      ;;
  esac

  [ -n "$parts" ] || return 0

  printf '**Curation cadence:** %s — thresholds are UNVALIDATED guesses; run the command(s), or set LOOMWRIGHT_CURATION_NUDGE=0 to silence.\n' "$parts"
  return 0
}

# ---- Dispatch ---------------------------------------------------------------

main() {
  local sub="${1:-status}"
  [ "$#" -gt 0 ] && shift
  case "$sub" in
    status) cmd_status "${1:-}" ;;
    record) cmd_record "${1:-}" ;;
    nudge)  cmd_nudge ;;
    -h|--help|help)
      printf 'usage: curation-status.sh [status [--json] | record dreaming | nudge]\n'
      ;;
    *)
      printf 'curation-status: unknown subcommand `%s` (expected status | record | nudge).\n' "$sub"
      ;;
  esac
  return 0
}

main "$@"
exit 0
