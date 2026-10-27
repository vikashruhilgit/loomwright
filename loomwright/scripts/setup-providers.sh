#!/usr/bin/env bash
# setup-providers.sh — read-only probe of the provider table
# (loomwright/scripts/adapters/providers/provider-<name>.sh). It reports, from
# commands it actually ran on this machine, whether each provider's CLI is
# installed, logged in, usable headless with parseable output,
# permission-pinnable and browser-capable, and ends each row with a one-line
# verdict. It routes nothing and changes nothing.
#
# USAGE
#   setup-providers.sh check
#
# This file names no vendor CLI. Every vendor string (binary name, flags,
# patterns, hints) lives in a provider-<name>.sh file as PROBE ENTRIES (below);
# adding a provider means adding one file there, never editing this one.
#
# ENV (optional)
#   LOOMWRIGHT_PROVIDERS_DIR             directory holding provider-<name>.sh
#                                        files (default: adapters/providers/
#                                        beside this script; tests point it at
#                                        a temp dir).
#   LOOMWRIGHT_PROVIDER_SMOKE_TIMEOUT    positive integer seconds bounding the
#                                        headless smoke (default 120).
#   LOOMWRIGHT_PROVIDER_QUICK_TIMEOUT    positive integer seconds bounding each
#                                        version / auth / help call (default 20).
#   A non-numeric, zero or empty value falls back to the default.
#   LOOMWRIGHT_JQ_BIN                    jq binary (default `jq`).
#
# COLUMNS (in this order)
#   installed    `installed <version>` | `installed: no`. An absent binary gets
#                the provider's install hint and NO other column is run.
#   auth         `auth ok` | `auth: not_logged_in` | `auth: unknown`, from the
#                provider's auth-check command and its ok / not-logged-in
#                patterns (the command's output is pattern-matched and never
#                printed). A provider with no auth-check command starts
#                `unknown` and the smoke decides: a passing smoke proves auth
#                (`auth ok (via smoke)`); a failing smoke whose output matches
#                the not-logged-in pattern gives `auth: not_logged_in (via
#                smoke)`. A failing auth column prints the provider's login hint.
#   headless     `headless pass` | `headless: fail:timeout` |
#                `headless: fail:unparseable` | `headless: fail:exit<rc>` |
#                `headless: not run`. The smoke sends a FIXED prompt (no repo
#                content) asking for a fixed JSON reply, from a throwaway
#                `mktemp -d` cwd (never the repo), under the REAL HOME (login
#                state lives there), stdin from /dev/null, bounded by
#                LOOMWRIGHT_PROVIDER_SMOKE_TIMEOUT. It is NOT run when auth is
#                not_logged_in. Its stdout is unwrapped with the provider's own
#                lens-contract provider_extract_text, so a pass also proves the
#                lens envelope. `fail:timeout` means the bound fired and the
#                smoke's whole process group was signalled TERM, then KILL.
#   permissions  `permissions pinnable` | `permissions: unpinnable` |
#                `permissions: unknown`. A provider declaring `none` (its only
#                non-interactive mode auto-approves every tool) is unpinnable;
#                one declaring nothing is unknown; otherwise its `--help`-style
#                output must contain every declared token or it is unpinnable.
#   browser      `browser yes` | `browser: no` | `browser: unknown`, as declared
#                (`unknown` until a probe has shown it).
#   A ':' after a column name marks a column that did not pass.
#
# VERDICT (exactly one per row, after `=>`)
#   `not usable: <first failing column>`, columns checked installed -> auth ->
#   headless; otherwise `usable for write seats` when permissions are pinnable,
#   else `usable for read-only seats`.
#
# PROBE-ENTRY CONTRACT (data a provider-<name>.sh file declares beside the
# lens contract in lens-run.sh's header; a file that does not define
# probe_smoke_argv declares no probe entries and is skipped — never reported,
# never run — which is what keeps test-only provider files out of the report):
#   PROBE_VERSION_ARGV           array  — argv (after the binary) printing the version.
#   PROBE_AUTH_ARGV              array  — argv of the auth-check command; empty = none.
#   PROBE_AUTH_OK_RE             string — ERE meaning logged in; empty = exit 0 means ok.
#   PROBE_AUTH_NOT_LOGGED_IN_RE  string — ERE meaning not logged in (checked first;
#                                         also applied to a failing smoke's output).
#   PROBE_HELP_ARGV              array  — argv printing the help text the pin tokens are read from.
#   PROBE_PERM_PIN_FLAGS         string — space-separated tokens that must ALL appear
#                                         in that help text, or `none`, or empty (unknown).
#   PROBE_BROWSER                yes | no | unknown
#   PROBE_INSTALL_HINT           string — the exact install command to show.
#   PROBE_LOGIN_HINT             string — the exact login command to show.
#   probe_smoke_argv()           reads PROBE_PROMPT (and PROBE_CWD); sets array
#                                PROBE_ARGV (argv after the binary), prompt LAST.
#
# SAFETY — what this script does and does not do:
#   - writes nothing outside its own `mktemp -d` scratch dir, removed on exit
#     (test-setup-providers.sh asserts the repo tree and a temp HOME's tool
#     config tree are unchanged). A vendor CLI run by the smoke MAY write its
#     own session/state files under the real HOME — that is the CLI's write,
#     not this script's, and the report header says so.
#   - never installs anything, never reads, prints or stores an API key or
#     token, never sends repo content.
#   - provider files are sourced (one subshell each, so no provider's globals
#     leak into the next) only when their <name> passes the same
#     `[a-zA-Z0-9_-]` allowlist lens-run.sh applies; every CLI call is built
#     as an argv array, never a string, never eval.
#   - every CLI call (version, auth, help, smoke) is bounded: it runs as its
#     own process group (perl setpgrp, python3 fallback — the launcher
#     lens-run.sh uses), and on expiry the group gets TERM, then KILL.
#   - unlike lens-run.sh there is no `env -i` / HOME scrub: login state lives
#     in the real HOME, and a scrubbed HOME breaks at least one provider's login.
#
# Exit: ALWAYS 0 for `check` (fail-safe report). A usage error (no or unknown
# subcommand) prints usage to stderr and exits 64.

set +e   # FAIL-SAFE: a failing probe is a report row, never a script failure.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JQ="${LOOMWRIGHT_JQ_BIN:-jq}"
PROVIDERS_DIR="${LOOMWRIGHT_PROVIDERS_DIR:-$SCRIPT_DIR/adapters/providers}"

# The fixed smoke prompt and the reply it asks for. No repo content, ever.
PROBE_PROMPT='Reply with exactly this JSON and nothing else: {"probe":"loomwright-ok"}'
PROBE_REPLY_JQ='.probe == "loomwright-ok"'

usage() {
  printf 'usage: setup-providers.sh check\n' >&2
  exit 64
}

case "${1:-}" in
  check) [ $# -eq 1 ] || usage ;;
  *) usage ;;
esac

positive_int_or() { # positive_int_or <value> <default>
  case "$1" in
    ''|*[!0-9]*) printf '%s' "$2" ;;
    *) if [ "$1" -gt 0 ] 2>/dev/null; then printf '%s' "$1"; else printf '%s' "$2"; fi ;;
  esac
}
SMOKE_TIMEOUT="$(positive_int_or "${LOOMWRIGHT_PROVIDER_SMOKE_TIMEOUT:-}" 120)"
QUICK_TIMEOUT="$(positive_int_or "${LOOMWRIGHT_PROVIDER_QUICK_TIMEOUT:-}" 20)"

HAVE_JQ=0
command -v "$JQ" >/dev/null 2>&1 && HAVE_JQ=1

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/loomwright-provider-probe-XXXXXX" 2>/dev/null)"
if [ -z "$SCRATCH" ] || [ ! -d "$SCRATCH" ]; then
  printf 'setup-providers check: could not create a scratch dir; nothing probed.\n'
  exit 0
fi
cleanup() { rm -rf "$SCRATCH" 2>/dev/null; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

SELF_PGID="$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ')"
RB_OWN_PGROUP=0
if command -v perl >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; then
  RB_OWN_PGROUP=1
fi

# ---- bounded runner ----------------------------------------------------------
# rb_exec <argv...> — exec the argv as the leader of a NEW process group.
# perl's block form of exec never goes through a shell, whatever the argv holds.
rb_exec() {
  if command -v perl >/dev/null 2>&1; then
    exec perl -e 'setpgrp; exec { $ARGV[0] } @ARGV or exit 127' "$@"
  fi
  if command -v python3 >/dev/null 2>&1; then
    exec python3 -c 'import os, sys; os.setpgrp(); os.execvp(sys.argv[1], sys.argv[1:])' "$@"
  fi
  exec "$@"
}

RB_PID=""
# rb_kill <signal> — signal the running call's whole process group (or, with no
# setpgrp helper, the leader and its direct children). Never this script's own
# group, never group 1.
rb_kill() {
  local sig="$1" child
  [ -n "$RB_PID" ] || return 0
  if [ "$RB_OWN_PGROUP" = "1" ] && [ "$RB_PID" != "1" ] && [ "$RB_PID" != "$SELF_PGID" ]; then
    kill -s "$sig" -- -"$RB_PID" 2>/dev/null
    return 0
  fi
  kill -s "$sig" "$RB_PID" 2>/dev/null
  if command -v pgrep >/dev/null 2>&1; then
    for child in $(pgrep -P "$RB_PID" 2>/dev/null); do
      kill -s "$sig" "$child" 2>/dev/null
    done
  fi
}

# run_bounded <secs> <stdout-file> <stderr-file> <cwd> <argv...>
# Sets RB_RC (the call's exit status) and RB_TIMED_OUT (1 when the bound fired).
run_bounded() {
  local secs="$1" out="$2" err="$3" cwd="$4" flag="$SCRATCH/timeout.flag" waited=0
  shift 4
  rm -f "$flag" 2>/dev/null
  RB_RC=0
  RB_TIMED_OUT=0
  ( cd "$cwd" 2>/dev/null || exit 90; rb_exec "$@" ) >"$out" 2>"$err" </dev/null &
  RB_PID=$!
  # Watchdog: polls once a second (never one long sleep). On expiry: flag, TERM
  # the group, then KILL it. Its output goes to /dev/null so a leftover `sleep 1`
  # never holds the caller's stdout open.
  (
    while [ "$waited" -lt "$secs" ]; do
      sleep 1
      kill -0 "$RB_PID" 2>/dev/null || exit 0
      waited=$((waited + 1))
    done
    : > "$flag"
    rb_kill TERM
    sleep 2
    rb_kill KILL
  ) >/dev/null 2>&1 &
  local wd=$!
  wait "$RB_PID" 2>/dev/null
  RB_RC=$?
  if [ -e "$flag" ]; then
    # The bound fired: let the watchdog finish, so the KILL step still reaches
    # group members that ignored TERM.
    RB_TIMED_OUT=1
    wait "$wd" 2>/dev/null
  else
    kill "$wd" 2>/dev/null
    wait "$wd" 2>/dev/null
  fi
  RB_PID=""
}

# one_line <file> — first non-blank line, printable characters only, max 60.
one_line() {
  awk 'NF { print; exit }' "$1" 2>/dev/null | tr -cd '[:print:]' | cut -c1-60
}

# ---- one provider (runs in its own subshell) --------------------------------
probe_provider() {
  local file="$1" name="$2"
  # If this subshell is interrupted mid-call, take the running call's group with it.
  trap 'rb_kill TERM; rb_kill KILL' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  # shellcheck disable=SC1090
  . "$file" 2>/dev/null
  declare -F probe_smoke_argv >/dev/null 2>&1 || return 0   # no probe entries => skip

  local cli="${PROVIDER_CLI_NAME:-}" label="$name"
  [ -n "$cli" ] || return 0
  [ "$cli" = "$name" ] || label="$name ($cli)"
  local work="$SCRATCH/$name"
  mkdir -p "$work/cwd" 2>/dev/null || return 0

  local installed="" auth="unknown" auth_via="" headless="not run" perm="unknown" browser="unknown"

  # -- installed (absent binary: hint, verdict, and no other column) --
  if ! command -v "$cli" >/dev/null 2>&1; then
    printf '%s: installed: no => not usable: installed\n' "$label"
    printf '    install: %s\n' "${PROBE_INSTALL_HINT:-(no install hint declared)}"
    return 0
  fi
  local ver=""
  if [ "${#PROBE_VERSION_ARGV[@]}" -gt 0 ]; then
    run_bounded "$QUICK_TIMEOUT" "$work/version.out" "$work/version.err" "$work/cwd" "$cli" "${PROBE_VERSION_ARGV[@]}"
    if [ "$RB_TIMED_OUT" = "0" ] && [ "$RB_RC" = "0" ]; then
      ver="$(one_line "$work/version.out")"
      [ -n "$ver" ] || ver="$(one_line "$work/version.err")"
    fi
  fi
  installed="installed ${ver:-(version unknown)}"

  # -- auth (output pattern-matched, never printed) --
  if [ "${#PROBE_AUTH_ARGV[@]}" -gt 0 ]; then
    run_bounded "$QUICK_TIMEOUT" "$work/auth.out" "$work/auth.err" "$work/cwd" "$cli" "${PROBE_AUTH_ARGV[@]}"
    if [ "$RB_TIMED_OUT" = "0" ]; then
      cat "$work/auth.out" "$work/auth.err" > "$work/auth.all" 2>/dev/null
      if [ -n "${PROBE_AUTH_NOT_LOGGED_IN_RE:-}" ] && grep -qE -- "$PROBE_AUTH_NOT_LOGGED_IN_RE" "$work/auth.all" 2>/dev/null; then
        auth="not_logged_in"
      elif [ -n "${PROBE_AUTH_OK_RE:-}" ]; then
        grep -qE -- "$PROBE_AUTH_OK_RE" "$work/auth.all" 2>/dev/null && auth="ok"
      elif [ "$RB_RC" = "0" ]; then
        auth="ok"
      fi
    fi
  fi

  # -- headless smoke --
  local skip_smoke=""
  [ "$auth" = "not_logged_in" ] && skip_smoke="auth"
  [ "$HAVE_JQ" = "1" ] || skip_smoke="${skip_smoke:-jq}"
  if [ -z "$skip_smoke" ]; then
    PROBE_CWD="$work/smoke-cwd"
    mkdir -p "$PROBE_CWD" 2>/dev/null
    PROBE_ARGV=()
    probe_smoke_argv
    run_bounded "$SMOKE_TIMEOUT" "$work/smoke.out" "$work/smoke.err" "$PROBE_CWD" "$cli" "${PROBE_ARGV[@]}"
    if [ "$RB_TIMED_OUT" = "1" ]; then
      headless="fail:timeout"
    elif smoke_reply_ok "$work"; then
      headless="pass"
    elif [ "$RB_RC" != "0" ]; then
      headless="fail:exit$RB_RC"
    else
      headless="fail:unparseable"
    fi
    if [ "$auth" = "unknown" ]; then
      if [ "$headless" = "pass" ]; then
        auth="ok"; auth_via=" (via smoke)"
      elif [ -n "${PROBE_AUTH_NOT_LOGGED_IN_RE:-}" ] && [ "$headless" != "fail:timeout" ] \
           && grep -qE -- "$PROBE_AUTH_NOT_LOGGED_IN_RE" "$work/smoke.out" "$work/smoke.err" 2>/dev/null; then
        auth="not_logged_in"; auth_via=" (via smoke)"
      fi
    fi
  fi

  # -- permissions --
  case "${PROBE_PERM_PIN_FLAGS:-}" in
    none) perm="unpinnable" ;;
    "")   perm="unknown" ;;
    *)
      # An empty help argv would launch the CLI's interactive mode: never do that.
      [ "${#PROBE_HELP_ARGV[@]}" -gt 0 ] || PROBE_HELP_ARGV=("--help")
      run_bounded "$QUICK_TIMEOUT" "$work/help.out" "$work/help.err" "$work/cwd" "$cli" "${PROBE_HELP_ARGV[@]}"
      cat "$work/help.out" "$work/help.err" > "$work/help.all" 2>/dev/null
      if [ "$RB_TIMED_OUT" = "1" ] || [ ! -s "$work/help.all" ]; then
        perm="unknown"
      else
        perm="pinnable"
        local tok
        for tok in $PROBE_PERM_PIN_FLAGS; do
          grep -qF -e "$tok" "$work/help.all" 2>/dev/null || perm="unpinnable"
        done
      fi
      ;;
  esac

  # -- browser (declared; unknown until shown) --
  case "${PROBE_BROWSER:-}" in
    yes|no) browser="$PROBE_BROWSER" ;;
    *) browser="unknown" ;;
  esac

  # -- verdict: installed -> auth -> headless, then permissions picks the seat --
  local verdict
  if [ "$auth" != "ok" ]; then
    verdict="not usable: auth"
  elif [ "$headless" != "pass" ]; then
    verdict="not usable: headless"
  elif [ "$perm" = "pinnable" ]; then
    verdict="usable for write seats"
  else
    verdict="usable for read-only seats"
  fi

  local c_auth c_head c_perm c_browser
  if [ "$auth" = "ok" ]; then c_auth="auth ok$auth_via"; else c_auth="auth: $auth$auth_via"; fi
  if [ "$headless" = "pass" ]; then c_head="headless pass"; else c_head="headless: $headless"; fi
  case "$skip_smoke" in
    auth) c_head="$c_head (auth not ok)" ;;
    jq)   c_head="$c_head (jq not found)" ;;
  esac
  if [ "$perm" = "pinnable" ]; then c_perm="permissions pinnable"; else c_perm="permissions: $perm"; fi
  if [ "$browser" = "yes" ]; then c_browser="browser yes"; else c_browser="browser: $browser"; fi

  printf '%s: %s · %s · %s · %s · %s => %s\n' "$label" "$installed" "$c_auth" "$c_head" "$c_perm" "$c_browser" "$verdict"
  if [ "$auth" != "ok" ]; then
    printf '    login: %s\n' "${PROBE_LOGIN_HINT:-(no login hint declared)}"
  fi
  return 0
}

# smoke_reply_ok <workdir> — 0 when the smoke's stdout unwraps (provider's own
# provider_extract_text) to the fixed JSON reply; a surrounding markdown code
# fence is tolerated.
smoke_reply_ok() {
  local work="$1"
  declare -F provider_extract_text >/dev/null 2>&1 || return 1
  PROVIDER_EXTRACTED=""
  provider_extract_text "$work/smoke.out" >/dev/null 2>&1 || return 1
  printf '%s\n' "$PROVIDER_EXTRACTED" | sed -e '/^[[:space:]]*```/d' > "$work/reply.txt" 2>/dev/null
  "$JQ" -e "$PROBE_REPLY_JQ" "$work/reply.txt" >/dev/null 2>&1
}

# ---- report ------------------------------------------------------------------
printf 'setup-providers check — read-only probe of the provider table\n'
printf '  date: %s · providers dir: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PROVIDERS_DIR"
printf '  smoke: fixed prompt (no repo content) · cwd: a throwaway mktemp -d dir, never the repo · HOME: the REAL HOME (login state lives there; never scrubbed) · timeout %ss (other calls %ss)\n' "$SMOKE_TIMEOUT" "$QUICK_TIMEOUT"
printf '  writes: only its own mktemp -d scratch dir, removed on exit · never installs anything · never reads, prints or stores an API key or token\n'
printf '  limit: a provider CLI may write its own session/state files under the real HOME while the smoke runs\n'
printf '  legend: a ":" after a column name marks a column that did not pass\n'
if [ "$HAVE_JQ" != "1" ]; then
  printf '  jq not found on PATH (%s): headless smoke not run — its reply cannot be parsed\n' "$JQ"
fi
printf '\n'

reported=0
if [ -d "$PROVIDERS_DIR" ]; then
  for f in "$PROVIDERS_DIR"/provider-*.sh; do
    [ -f "$f" ] || continue
    base="${f##*/}"
    name="${base#provider-}"
    name="${name%.sh}"
    case "$name" in
      ""|*[!a-zA-Z0-9_-]*) continue ;;
    esac
    row="$( probe_provider "$f" "$name" )"
    if [ -n "$row" ]; then
      printf '%s\n' "$row"
      reported=$((reported + 1))
    fi
  done
fi
if [ "$reported" -eq 0 ]; then
  printf 'no provider-table file under %s declares probe entries; nothing probed.\n' "$PROVIDERS_DIR"
fi

exit 0
