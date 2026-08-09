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
# THE PENDING COUNT AND THE CONSUMPTION WINDOW MUST SPEAK THE SAME UNIT. v15.29.0
# shipped three different units for one quantity — readiness counted "log FILES
# newer than a wall-clock stamp", consumption took "the N most-recent files"
# (`--sessions`, default 5), and `record` stored "wall-clock now" — and nothing
# asserted a relationship between them, so every conversion lost information.
# The three fixes below are one fix; see `count_unconsumed_dreaming` (set, not
# watermark), the reflection-signal predicates (signal, not file count), and
# `cmd_status`'s window line (the count now names the window that will drain it).
# `test-curation-status.sh` pins the window against commands/dreaming.md's
# Parameters table mechanically — that cross-file assertion is what was missing.
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
# `--json` holds the same line: EVERY degraded path (jq absent, or jq present but
# the render threw) emits the FULL `commands` tree with `"unknown"` values —
# never a stub document that would hand a consumer `null` instead. Both paths
# share one constant, CURATION_JSON_UNKNOWN_BODY, so they cannot drift apart.
#
# LOCAL-ONLY NUDGE. `nudge` makes NO network call (no gh, no curl) — it runs
# inside a SessionStart hook and a network round-trip there is a latency hazard
# on every session start. The "merged PRs absent from the ledger" count is
# computed ONLY on an explicit `status` invocation (and only when `gh` is present
# and the repo has an `origin` remote); the nudge always reports it as `unknown`.
#
#   THEREFORE `status` MAY MAKE ONE `gh pr list` CALL — documented, not a
#   surprise. That single round-trip feeds ONLY the /pr-postmortem `pending`
#   column, so a caller that reads just the /dreaming or /insights row should set
#   LOOMWRIGHT_CURATION_REMOTE=0 and skip it (measured: ~0.3 s vs ~1.1 s). Both
#   /dreaming's and /insights' Step 0 snippets do exactly that; /pr-postmortem
#   leaves the valve unset because it is the one caller that consumes the count.
#   `nudge` and `record` NEVER touch the network on any path.
#
#   THAT CALL IS WINDOWED AT THE 50 MOST RECENT MERGED PRs (`--limit 50`), and
#   the window is a documented cap, not a total. On a repo with more than 50
#   merged PRs the /pr-postmortem `pending` count ("merged PRs absent from the
#   ledger") is therefore a LOWER BOUND on the real backlog — an older merged PR
#   that was never postmortem'd falls outside the window and is not counted. The
#   cap is deliberate (one bounded round-trip, no pagination on an advisory
#   probe); widening it trades latency for completeness. This repo is already
#   past PR #134, so the undercount is a live condition here, not a hypothetical.
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

# /dreaming's DEFAULT consumption window — the `--sessions N` default.
# NOT AUTHORITATIVE HERE: commands/dreaming.md's Parameters table owns this
# number; this is a mirror so `status` can name the window its count will be
# drained by. test-curation-status.sh greps that table and fails if the two
# drift, which is the assertion whose absence let the gate and the window ship
# as unrelated numbers in the first place.
DREAMING_DEFAULT_WINDOW=5

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
# malformed, or the value is not a non-negative integer. NEVER writes config.json.
#
# A CONFIGURED `0` IS MEANINGFUL AND HONOURED — it is not rejected. Decision, of
# the two options a review raised: `0` means "always ready, never decline"
# (readiness() compares `pending >= threshold`, and every real count is >= 0), so
# it is the documented way to keep the readiness REPORTING while switching the
# declining gate off for a command — the standing counterpart to the per-run
# `--force` flag. Silently substituting the in-script default for an explicitly
# configured `0` would be the same class of dishonesty this script forbids
# everywhere else: overriding a value the user actually wrote, without saying so.
# NEGATIVE and non-integer values are still rejected (is_uint fails on both) —
# they express no coherent threshold, so the labelled default is the honest
# answer there.
read_threshold() {
  local key="${1:-}" fallback="${2:-0}" v
  [ -r "$CONFIG_FILE" ] || { printf '%s' "$fallback"; return 0; }
  have_jq || { printf '%s' "$fallback"; return 0; }
  v="$(jq -r --arg k "$key" '.curation.thresholds[$k] // empty' "$CONFIG_FILE" 2>/dev/null || true)"
  if is_uint "$v"; then
    printf '%s' "$v"
  else
    printf '%s' "$fallback"
  fi
}

# ---- Last-run derivations ---------------------------------------------------

# /dreaming — the ONE STORED value.
#   absent state file            ⇒ never    (a real answer: there is no record)
#   unreadable state file        ⇒ unknown  (decision (f): never a fabricated answer)
#   truncated/empty/not-JSON     ⇒ unknown  (present, but we could not read it)
#   parses, but no .dreaming.last_run ⇒ never (read it, and it holds no record)
#   parses, .dreaming.last_run unparseable as a timestamp ⇒ unknown
#
# WHY THE UNPARSEABLE CASES ARE `unknown`, NOT `never`: `never` is a CLAIM — it
# flows into pending_for() as "every log counts", which makes /dreaming's
# readiness `yes`/`no` on a real number and lets the decline message assert
# "N new session log(s) since its last run" about a file the script never
# managed to parse. `unknown` refuses to claim: readiness() maps it to `unknown`,
# which by decision (f) never declines and never suppresses the nudge. Only the
# genuinely-absent file, and a state file we DID parse that simply carries no
# record, are honest `never`s.
derive_dreaming_last_run() {
  [ -e "$STATE_FILE" ] || { printf 'never'; return 0; }
  [ -r "$STATE_FILE" ] || { printf 'unknown'; return 0; }
  have_jq || { printf 'unknown'; return 0; }
  # Parse-check FIRST, so a corrupt/truncated/non-JSON file is distinguishable
  # from a well-formed one that simply has no .dreaming.last_run. Extracting the
  # field alone cannot tell those apart — both yield an empty string.
  jq -e 'type == "object"' "$STATE_FILE" >/dev/null 2>&1 || { printf 'unknown'; return 0; }
  local v
  v="$(jq -r '.dreaming.last_run // empty' "$STATE_FILE" 2>/dev/null || true)"
  [ -n "$v" ] || { printf 'never'; return 0; }
  local e
  e="$(iso_to_epoch "$v")"
  is_uint "$e" || { printf 'unknown'; return 0; }
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

# ---- Reflection-signal predicates -------------------------------------------
#
# WHY A COUNT OF FILES IS THE WRONG NUMBER. Measured on this repo 2026-08-09
# (62 logs): 29 carried ONLY `token_ledger` and `subtask_complete` events —
# 1.64 MB of a 1.70 MB corpus, i.e. ~96% of the bytes carrying 0% of the
# reflection signal, with one log alone holding 5108 events, all of them noise.
# A raw file count therefore overstated /dreaming's real backlog by 1.9x (62/33).
#
# MEASURE THIS UNDER bash, NOT THE ZSH THE AGENT SHELL RUNS. The first census of
# these figures came out exactly inverted (29 signal / 33 noise) because it used
# `jq ... | grep -qv`, and under zsh that pipeline reports the producer's SIGPIPE
# rather than grep's verdict. Any recount here must avoid `producer | grep -q`
# entirely, or run under `bash file.sh`.
#
# THE TWO PREDICATES DIFFER BECAUSE THE TWO CONSUMERS DIFFER — read out of the
# consumers, not assumed:
#   /dreaming  reflects BROADLY over log content (commands/dreaming.md step 1),
#              so its predicate is a DENYLIST: a log counts unless every line is
#              one of the two known noise events.
#   /insights  build-insights.sh consumes EXACTLY ONE event type — one
#              `session_end` record per log (its step-1 collection loop) — so a
#              log with no session_end contributes literally nothing to a run.
#              Measured: 27 of 62 logs qualify.
#
# BOTH FAIL OPEN, AND THE ANCHOR IS CHOSEN SO THAT THEY MUST. The denylist is
# anchored at `^{"event":"`, so if the writer ever stops emitting `event` as the
# first key a noise line STOPS matching the noise pattern and the log counts as
# signal. Over-counting is the safe direction — it can only make the nudge fire
# when it needn't, never suppress it on a log we misread. Same rule as
# `unknown`-never-a-fabricated-`0` above, applied to content instead of to
# readability. An unreadable file, and any grep failure that is not a clean
# "no match" (exit 1), likewise count as signal.
DREAMING_NOISE_RE='^\{"event":"(token_ledger|subtask_complete)"'
INSIGHTS_SIGNAL_FIXED='"event":"session_end"'

# log_has_signal <file> <dreaming|insights> — 0 (true) when the log could matter
# to that consumer. grep is used rather than jq deliberately: this runs over the
# whole corpus inside a SessionStart hook, and the anchored pattern measures
# 0.07 s across 62 logs / 3.8 MB versus 0.41 s for an unanchored one.
# ONE mechanism decides readability, not two. An earlier draft also carried a
# `[ -r "$f" ] || return 0` pre-guard, which made the rc>1 arm below dead code:
# grep exits 2 on precisely the unreadable file the guard had already caught, so
# the fail-open branch could never run and no test could reach it (a mutation
# flipping it to fail-closed survived the whole suite). Letting grep's own exit
# status answer keeps the two cases in one place and makes the behaviour
# testable. The `[ -n "$f" ]` guard stays and is NOT redundant — grep with no
# file operand reads stdin, which inside a SessionStart hook would hang.
log_has_signal() {
  local f="${1:-}" kind="${2:-dreaming}" rc=0
  [ -n "$f" ] || return 0
  case "$kind" in
    insights) grep -qF "$INSIGHTS_SIGNAL_FIXED" "$f" 2>/dev/null ;;
    *)        grep -qvE "$DREAMING_NOISE_RE" "$f" 2>/dev/null ;;
  esac
  rc=$?
  # Exactly 1 is grep's "no match" — a real, examined answer, the only one that
  # may drop a log from the count. 0 is a match; anything >1 (unreadable file,
  # I/O error) is a failure to examine. Both count as signal: over-counting can
  # only make the nudge fire when it needn't, while under-counting would silently
  # suppress it on a log we never managed to read.
  [ "$rc" -eq 1 ] && return 1
  return 0
}

# ---- Pending counts ---------------------------------------------------------

# count_logs_newer_than <epoch|never|unknown> <dreaming|insights> — how many
# .supervisor/logs/*.jsonl files postdate the given last-run epoch AND carry
# reflection signal for that consumer.
#   absent logs dir    ⇒ 0        (a real, readable answer: there is no corpus)
#   unreadable logs dir⇒ unknown
#   since == never     ⇒ every signal-carrying log counts
#   since == unknown   ⇒ unknown  (cannot compare against a boundary we lack)
#
# A WATERMARK IS CORRECT HERE, and only here. /insights consumes ALL logs on
# every run (build-insights.sh iterates the full list, no window), so "logs newer
# than the last run" is an EXACT statement of what it has yet to see. /dreaming's
# consumption is windowed, which is why it does not use this function — see
# count_unconsumed_dreaming.
count_logs_newer_than() {
  local since="${1:-unknown}" kind="${2:-insights}" n=0 f m
  [ -d "$LOGS_DIR" ] || { printf '0'; return 0; }
  { [ -r "$LOGS_DIR" ] && [ -x "$LOGS_DIR" ]; } || { printf 'unknown'; return 0; }
  case "$since" in
    unknown) printf 'unknown'; return 0 ;;
  esac
  for f in "$LOGS_DIR"/*.jsonl; do
    [ -f "$f" ] || continue
    log_has_signal "$f" "$kind" || continue
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

# pending_for <last_run-iso|never|unknown> <dreaming|insights> — resolve the
# last-run value to a comparison boundary, then count.
pending_for() {
  local last="${1:-unknown}" kind="${2:-insights}" e
  case "$last" in
    never)   e="never" ;;
    unknown) e="unknown" ;;
    *)       e="$(iso_to_epoch "$last")" ;;
  esac
  count_logs_newer_than "$e" "$kind"
}

# consumed_log_ids — the session ids /dreaming has already fed to reflection, one
# per line. Prints the literal `unknown` when the record EXISTS but could not be
# read, and nothing at all when it legitimately holds no ids.
#
# THIS IS THE SAME ABSENT-vs-UNEXAMINABLE LADDER derive_dreaming_last_run walks,
# and for the same reason. Collapsing "we could not parse the record" into "the
# record is empty" would report every log as unreflected — a confident number
# manufactured out of an input we failed to read, which is exactly the fabricated
# answer this script's header forbids. `unknown` refuses to claim instead.
# "Unexaminable" is signalled by a NON-ZERO RETURN, not by a sentinel line: a
# session id is a filename, and a file legitimately named `unknown.jsonl` would
# otherwise be indistinguishable from the could-not-read answer.
#   absent state file         ⇒ rc 0, no output   a real answer: nothing recorded
#   unreadable / not JSON     ⇒ rc 1              could not examine
#   parses, no consumed.logs  ⇒ rc 0, no output   read it, and it holds no ids
consumed_log_ids() {
  [ -e "$STATE_FILE" ] || return 0
  [ -r "$STATE_FILE" ] || return 1
  have_jq || return 1
  jq -e 'type == "object"' "$STATE_FILE" >/dev/null 2>&1 || return 1
  jq -r '(.dreaming.consumed.logs // []) | .[] | select(type == "string" and length > 0)' \
     "$STATE_FILE" 2>/dev/null || true
  return 0
}

# count_unconsumed_dreaming — /dreaming's pending count: session logs that carry
# reflection signal and have NOT already been fed to reflection.
#
# WHY A SET, NOT A WATERMARK. /dreaming consumes the `--sessions N` MOST RECENT
# logs, so what a run leaves behind is the OLDER tail. A watermark answers "how
# many are newer than T", which cannot count an older tail at ANY value of T:
#   T = now              ⇒ pending collapses to ~0 and every older unread log is
#                          retired without ever having been read (v15.29.0 bug)
#   T = newest consumed  ⇒ identical, the newest consumed is ~now
#   T = oldest consumed  ⇒ pending = the batch just read, and the older tail
#                          STILL never counts
# Consumption is a set selection from the top of a sort and pending is its
# complement, so the record has to be set membership. It is also the only shape
# under which a later run can deliberately target the older remainder.
#
# CONSEQUENCE FOR /dreaming: `last_run` no longer feeds this count at all. It
# stays stored, and still drives `age_days` and the "since" phrasing, but the
# backlog is now answered by the set. That is the point — a run's effect on the
# count is now exactly the logs it actually read.
#
# ON UPGRADE from a v15.29.0 state file (a `last_run`, no `consumed` key) the
# count jumps to the full signal-carrying corpus. That is the honest answer:
# nothing has been recorded as consumed, and over-counting is the safe direction.
#
#   absent logs dir          ⇒ 0
#   unreadable logs dir      ⇒ unknown
#   unexaminable consumed set⇒ unknown
count_unconsumed_dreaming() {
  local n=0 f id consumed
  [ -d "$LOGS_DIR" ] || { printf '0'; return 0; }
  { [ -r "$LOGS_DIR" ] && [ -x "$LOGS_DIR" ]; } || { printf 'unknown'; return 0; }
  # Declared first, assigned second, status tested on its own line: a
  # `local consumed="$(...)"` would make $? the status of `local` and silently
  # swallow the unexaminable signal — the same trap derive_postmortem_pending
  # documents on its gh call.
  consumed="$(consumed_log_ids)" || { printf 'unknown'; return 0; }
  for f in "$LOGS_DIR"/*.jsonl; do
    [ -f "$f" ] || continue
    log_has_signal "$f" dreaming || continue
    id="$(basename "$f" .jsonl)"
    # grep -qx against the newline-separated id list: an exact whole-line match,
    # so one session id can never be a prefix of another's.
    printf '%s\n' "$consumed" | grep -qxF -- "$id" && continue
    n=$((n + 1))
  done
  printf '%s' "$n"
}

# pending_from_merged <merged-pr-numbers> — the PURE half of the count below:
# how many of the given merged PR numbers have no matching `.number` record in
# the ledger. Takes the merged list as an ARGUMENT and makes no network call, so
# the set-diff is exercisable independently of `gh`.
#
# An EMPTY list is an honest `0`, not `unknown`: "no merged PRs" and "we could
# not ask" are different answers, and only the caller — which alone sees gh's
# exit status — can tell them apart. This function is reached only after that
# distinction has already been made.
pending_from_merged() {
  local merged="${1:-}" have missing=0 n
  have="$(jq -rRn '[inputs | fromjson? | select(type == "object") | .number // empty] | .[]' \
            "$LEDGER_FILE" 2>/dev/null || true)"
  for n in $merged; do
    is_uint "$n" || continue
    printf '%s\n' "$have" | grep -qx -- "$n" || missing=$((missing + 1))
  done
  printf '%s' "$missing"
}

# derive_postmortem_pending — "merged PRs absent from the ledger".
#
# STATUS-ONLY (decision (e)): this is the ONE place in this script allowed to
# touch the network, and `nudge` never calls it. Degrades to `unknown` whenever
# gh is absent, there is no `origin` remote, the probe fails, or the caller sets
# LOOMWRIGHT_CURATION_REMOTE=0.
#
# GH'S EXIT STATUS IS CAPTURED SEPARATELY FROM ITS OUTPUT, and that separation is
# the whole point. Keying on emptiness alone (`[ -n "$merged" ] || unknown`)
# conflates the two answers this script's header forbids conflating: a SUCCESSFUL
# call on a repo with genuinely zero merged PRs also prints nothing, and reporting
# that as `unknown` is a fabricated could-not-examine for an input we examined
# perfectly well. Non-zero exit ⇒ `unknown`; zero exit with empty output ⇒ the
# honest `0`. `|| true` must NOT be used on the gh line — it is precisely what
# destroys the status. Windowed at 50 (see the header's cap note).
derive_postmortem_pending() {
  case "${LOOMWRIGHT_CURATION_REMOTE:-}" in 0|off|false|no) printf 'unknown'; return 0 ;; esac
  command -v gh >/dev/null 2>&1 || { printf 'unknown'; return 0; }
  git remote get-url origin >/dev/null 2>&1 || { printf 'unknown'; return 0; }
  have_jq || { printf 'unknown'; return 0; }
  # ABSENT vs UNREADABLE, same distinction derive_postmortem_last_run makes above.
  # A ledger that does not exist yet is EXAMINED, not unexaminable: the repo has
  # simply never run /pr-postmortem, and "every merged PR is missing from it" is
  # the honest, computable answer — pending_from_merged already produces it (jq
  # fails on the absent path, `|| true` swallows it, `have` is empty, and every
  # merged number then counts as missing). Short-circuiting to `unknown` here
  # would report a fabricated could-not-examine on a first run. Only a file that
  # EXISTS and cannot be read is a genuine could-not-examine.
  if [ -e "$LEDGER_FILE" ] && [ ! -r "$LEDGER_FILE" ]; then printf 'unknown'; return 0; fi
  # Declared first, assigned second: `local merged="$(...)"` would make $? the
  # status of `local`, not of gh, silently restoring the bug this guards against.
  local merged gh_rc
  merged="$(gh pr list --state merged --limit 50 --json number -q '.[].number' 2>/dev/null)"
  gh_rc=$?
  [ "$gh_rc" -eq 0 ] || { printf 'unknown'; return 0; }
  pending_from_merged "$merged"
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

# decline_message <command-label> <pending> <threshold> <noun> — the verbatim
# decline text, or the empty string when the command should proceed. Names the
# observed count, the threshold, AND that the threshold is an unvalidated guess.
#
# THE NOUN IS PARAMETERISED BECAUSE THE TWO COUNTS NOW MEAN DIFFERENT THINGS.
# /insights counts logs NEWER THAN its last run (a watermark, exact for it —
# it consumes the whole corpus every run). /dreaming counts logs it has never
# fed to reflection (a set, because it consumes a window). Saying "since its
# last run" for /dreaming would be false: an unreflected log is usually OLDER
# than the last run, which is precisely how the v15.29.0 shape hid the backlog.
decline_message() {
  local label="${1:-}" pending="${2:-}" threshold="${3:-}" noun="${4:-new session log(s) since its last run}"
  printf '/%s declined: %s %s, below the threshold of %s. That threshold is an UNVALIDATED starting guess, not a measured value — re-run with --force to proceed anyway, or set .curation.thresholds.%s in .supervisor/config.json.' \
    "$label" "$pending" "$noun" "$threshold" "$label"
}

# The two nouns, named once so the decline line and the nudge cannot drift.
DREAMING_PENDING_NOUN='unreflected session log(s) carrying reflection signal'
INSIGHTS_PENDING_NOUN='new session log(s) since its last run'

# ---- Subcommand: status -----------------------------------------------------

# The all-unknown `--json` document body — every key after the preamble
# (`schema_version` / `jq` / optional `error`).
#
# BOTH degraded `--json` paths emit this VERBATIM: jq absent, and jq present but
# the render itself threw. It is a single constant rather than two literals
# because the two paths previously disagreed — the jq-absent path emitted the
# full `commands` tree while the render-failure path emitted a bare
# `{"error":"render_failed"}` stub, so a consumer reading
# `.commands.dreaming.pending` got the documented `"unknown"` sentinel down one
# route and a silent `null` down the other. Both are the same answer ("we could
# not compute these values"), so both must speak the same sentinel; sharing the
# constant is what keeps that true as the schema grows.
#
# `window` rides in this body too, and as a REAL value rather than "unknown":
# it is a static mirror of commands/dreaming.md's `--sessions` default, not
# something computed from the inputs that just failed to read. Emitting
# "unknown" for it would fabricate a could-not-examine for a constant.
# INTERPOLATED, never a literal: writing `"window":5` here would make this the
# THIRD copy of the `--sessions` default (dreaming.md's table, the constant
# above, and this string), which is the same drift class the window line exists
# to close. It is built from $DREAMING_DEFAULT_WINDOW so there is one source.
CURATION_JSON_UNKNOWN_BODY="$(printf '"thresholds_unvalidated":true,"commands":{"dreaming":{"last_run":"unknown","age_days":"unknown","pending":"unknown","threshold":"unknown","ready":"unknown","window":%s,"decline_message":""},"insights":{"last_run":"unknown","age_days":"unknown","pending":"unknown","threshold":"unknown","ready":"unknown","window":"all","decline_message":""},"pr_postmortem":{"last_run":"unknown","age_days":"unknown","pending":"unknown","threshold":"none","ready":"always","window":"one_pr","decline_message":""}}' "$DREAMING_DEFAULT_WINDOW")"

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

  # /dreaming counts an unconsumed SET; /insights counts newer-than-watermark.
  # The asymmetry is deliberate and load-bearing — see each function's header.
  d_pending="$(count_unconsumed_dreaming)"
  i_pending="$(pending_for "$i_last" insights)"
  p_pending="$(derive_postmortem_pending)"

  d_thr="$(read_threshold dreaming "$DEFAULT_THRESHOLD_DREAMING")"
  i_thr="$(read_threshold insights "$DEFAULT_THRESHOLD_INSIGHTS")"

  d_ready="$(readiness "$d_pending" "$d_thr")"
  i_ready="$(readiness "$i_pending" "$i_thr")"

  d_age="$(age_days "$(iso_to_epoch "$d_last")")"
  i_age="$(age_days "$(iso_to_epoch "$i_last")")"
  p_age="$(age_days "$(iso_to_epoch "$p_last")")"

  [ "$d_ready" = "no" ] && d_decline="$(decline_message dreaming "$d_pending" "$d_thr" "$DREAMING_PENDING_NOUN")"
  [ "$i_ready" = "no" ] && i_decline="$(decline_message insights "$i_pending" "$i_thr" "$INSIGHTS_PENDING_NOUN")"

  if [ "$as_json" = "yes" ]; then
    if ! have_jq; then
      # jq absent ⇒ emit a literal all-unknown document rather than fabricating
      # values or crashing. Still valid JSON, still exit 0.
      printf '{"schema_version":2,"jq":false,%s}\n' "$CURATION_JSON_UNKNOWN_BODY"
      return 0
    fi
    jq -n \
      --arg dl "$d_last" --arg da "$d_age" --arg dp "$d_pending" --arg dt "$d_thr" --arg dr "$d_ready" --arg dm "$d_decline" \
      --arg il "$i_last" --arg ia "$i_age" --arg ip "$i_pending" --arg it "$i_thr" --arg ir "$i_ready" --arg im "$i_decline" \
      --arg pl "$p_last" --arg pa "$p_age" --arg pp "$p_pending" \
      --arg dw "$DREAMING_DEFAULT_WINDOW" \
      '
      def num_or_str: if test("^[0-9]+$") then tonumber else . end;
      {
        schema_version: 2,
        jq: true,
        thresholds_unvalidated: true,
        commands: {
          dreaming:      {last_run: $dl, age_days: ($da|num_or_str), pending: ($dp|num_or_str), threshold: ($dt|num_or_str), ready: $dr, window: ($dw|num_or_str), decline_message: $dm},
          insights:      {last_run: $il, age_days: ($ia|num_or_str), pending: ($ip|num_or_str), threshold: ($it|num_or_str), ready: $ir, window: "all", decline_message: $im},
          pr_postmortem: {last_run: $pl, age_days: ($pa|num_or_str), pending: ($pp|num_or_str), threshold: "none", ready: "always", window: "one_pr", decline_message: ""}
        }
      }' 2>/dev/null || printf '{"schema_version":2,"jq":true,"error":"render_failed",%s}\n' "$CURATION_JSON_UNKNOWN_BODY"
    return 0
  fi

  printf '## Curation readiness\n'
  printf 'Thresholds are UNVALIDATED starting guesses (not measured) — tune .curation.thresholds.{dreaming,insights} in .supervisor/config.json.\n'
  printf -- '- /dreaming       last_run=%s age_days=%s pending=%s threshold=%s ready=%s window=%s\n' \
    "$d_last" "$d_age" "$d_pending" "$d_thr" "$d_ready" "$DREAMING_DEFAULT_WINDOW"
  # THE WINDOW IS PART OF THE ANSWER, not a footnote. `pending` is a backlog of
  # unconsumed logs; `window` is how many of them one default run will actually
  # read. Reporting the backlog alone is what let v15.29.0 say "ready=yes,
  # pending=61" about a run that would consume 5 and silently retire the rest.
  if is_uint "$d_pending" && [ "$d_pending" -gt "$DREAMING_DEFAULT_WINDOW" ]; then
    printf -- '  note(/dreaming): a default run reads the %s most recent of those %s logs; the rest stay pending and are read by later runs (pass --sessions N to widen).\n' \
      "$DREAMING_DEFAULT_WINDOW" "$d_pending"
  fi
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
#
#   record dreaming [<session_id> ...]
#
# THE SESSION IDS ARE THE POINT, not an optional extra. They are the logs the run
# actually fed to reflection (basename minus `.jsonl`), and they are what makes
# the pending count fall by exactly what was read instead of collapsing to zero.
# See count_unconsumed_dreaming for why a wall-clock stamp cannot do this.
#
# ZERO IDS IS STILL LEGAL AND STILL STAMPS `last_run` — a run that read nothing
# (everything rejected, or an empty corpus) is a real run and the cadence record
# exists precisely to capture it. But it WARNS, because a caller that read logs
# and forgot to name them gets a `last_run` that moves while `pending` does not,
# which looks like the probe is stuck. The warning names that explicitly.
#
# The stored set is UNIONED with what is already there. INCOMING ids are checked
# against disk and an unmatchable one is reported rather than stored (it could
# only subtract from a count it can never correspond to); ids ALREADY in the set
# are retained even if their log has since been rotated away — "this log was
# consumed" stays true and costs nothing, while re-deriving it would be wrong.
# The set is therefore bounded by the number of logs ever consumed, not by the
# number of calls. Ids are passed through jq `--args` (never interpolated into
# the filter), so a hostile filename is data, not program text.
cmd_record() {
  local target="${1:-}"
  [ "$#" -gt 0 ] && shift   # leaves "$@" = the session ids
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

  # Keep only ids whose log is actually on disk. An id naming a log that does not
  # exist is reported rather than stored: storing it would permanently subtract
  # from a count it can never correspond to.
  #
  # ROTATE "$@" IN PLACE — never `for id in $consumed_in`. Word-splitting a
  # flattened "$*" breaks any id containing whitespace into fragments, and since
  # no fragment names a file on disk the whole id is then silently dropped: the
  # run is recorded as having consumed nothing and its logs stay pending forever.
  # Popping from the front and pushing survivors to the back preserves each
  # argument whole, whatever it contains.
  local kept_n=0 dropped_n=0 id remaining="$#"
  while [ "$remaining" -gt 0 ]; do
    id="$1"; shift
    remaining=$((remaining - 1))
    if [ -n "$id" ] && [ -f "$LOGS_DIR/$id.jsonl" ]; then
      set -- "$@" "$id"
      kept_n=$((kept_n + 1))
    else
      dropped_n=$((dropped_n + 1))
    fi
  done

  tmp="$STATE_FILE.tmp.$$"
  if printf '%s' "$existing" \
     | jq --arg ts "$now_iso" '
         .dreaming = ((.dreaming // {}) + {last_run: $ts})
         | .dreaming.consumed = (.dreaming.consumed // {})
         | .dreaming.consumed.logs =
             (((.dreaming.consumed.logs // []) + $ARGS.positional)
              | map(select(type == "string" and length > 0))
              | unique)
       ' --args "$@" > "$tmp" 2>/dev/null \
     && mv "$tmp" "$STATE_FILE" 2>/dev/null; then
    printf 'curation-status: recorded /dreaming last_run=%s (consumed logs added: %s)\n' \
      "$now_iso" "$kept_n"
    [ "$dropped_n" -gt 0 ] && printf 'curation-status: %s named log(s) are not on disk and were not recorded.\n' "$dropped_n"
    if [ "$kept_n" -eq 0 ]; then
      printf 'curation-status: NO logs were named, so `pending` will NOT fall — only last_run moved. If this run did read logs, re-run as `record dreaming <session_id>...` naming them; otherwise this is the correct record of a run that consumed nothing.\n'
    fi
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
  d_pending="$(count_unconsumed_dreaming)"
  i_pending="$(pending_for "$i_last" insights)"
  d_thr="$(read_threshold dreaming "$DEFAULT_THRESHOLD_DREAMING")"
  i_thr="$(read_threshold insights "$DEFAULT_THRESHOLD_INSIGHTS")"
  d_ready="$(readiness "$d_pending" "$d_thr")"
  i_ready="$(readiness "$i_pending" "$i_thr")"

  # /dreaming's line names the WINDOW alongside the backlog: the count alone
  # invites "ready=yes, 61 pending" to be read as "one run clears 61".
  case "$d_ready" in
    yes|unknown) parts="/dreaming $d_pending $DREAMING_PENDING_NOUN (threshold $d_thr; a default run reads $DREAMING_DEFAULT_WINDOW, last run $d_last)" ;;
  esac
  case "$i_ready" in
    yes|unknown)
      if [ -n "$parts" ]; then parts="$parts; "; fi
      parts="$parts/insights $i_pending $INSIGHTS_PENDING_NOUN ($i_last, threshold $i_thr)"
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
    # ALL remaining args are forwarded — `record dreaming <id> <id> ...` needs
    # them. Passing only "${1:-}" here would silently drop every session id and
    # restore the exact fail-silent shape this change exists to remove.
    record) cmd_record "$@" ;;
    nudge)  cmd_nudge ;;
    -h|--help|help)
      printf 'usage: curation-status.sh [status [--json] | record dreaming [<session_id>...] | nudge]\n'
      ;;
    *)
      printf 'curation-status: unknown subcommand `%s` (expected status | record | nudge).\n' "$sub"
      ;;
  esac
  return 0
}

main "$@"
exit 0
