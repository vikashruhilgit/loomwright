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
#   auth         `auth ok` | `auth: not_logged_in` |
#                `auth: not_logged_in_isolated (ok in your shell)` |
#                `auth: unknown`, from the provider's auth-check command and its
#                ok / not-logged-in patterns (the command's output is
#                pattern-matched and never printed), run under the ISOLATED
#                HOME like every graded call (see LAUNCH below). A provider with
#                no auth-check command starts
#                `unknown` and the smoke decides: a passing smoke proves auth
#                (`auth ok (via smoke)`); a failing smoke whose output matches
#                the not-logged-in pattern gives `auth: not_logged_in (via
#                smoke)`; a smoke failing any other way leaves
#                `auth: unknown (smoke failed: <reason>)` (and
#                `auth: unknown (smoke not run)` when jq is missing).
#                `not_logged_in` prints the provider's login hint as
#                `login: <hint>`; `unknown` prints it qualified, as
#                `login (only if not logged in): <hint>`, because an unknown
#                auth state may well be a logged-in CLI.
#                When the isolated auth check (or, with no auth-check command,
#                the isolated smoke) reports no login, the same call is re-run
#                ONCE under the real HOME (`shell` home mode) as a diagnosis
#                only: logged in there => `not_logged_in_isolated` (the login
#                exists but does not cross isolation, so a routed step would
#                fail) with a `fix:` line naming the provider's declared login
#                files / env vars; not logged in there either =>
#                `not_logged_in`. The rerun never grades anything `ok`.
#   AC6 SCOPE    "logged out => the smoke is NOT run" holds only for a provider
#                that declares an auth-check command (PROBE_AUTH_ARGV). A
#                provider with none (no vendor auth-status command exists to
#                call) has the smoke as its ONLY auth signal, so a logged-out
#                CLI of that kind does get its smoke run; that smoke is what
#                reports it not_logged_in. This is a deliberate trade-off in
#                favour of real auth/headless values for such providers.
#   headless     `headless pass` | `headless: fail:timeout` |
#                `headless: fail:unparseable` | `headless: fail:exit<rc>` |
#                `headless: not run`. The smoke sends a FIXED prompt (no repo
#                content) asking for a fixed JSON reply, from a throwaway
#                `mktemp -d` cwd (never the repo), under the ISOLATED HOME
#                (the launch a routed step gets), stdin from /dev/null, bounded
#                by LOOMWRIGHT_PROVIDER_SMOKE_TIMEOUT. It is NOT run when auth
#                is not_logged_in or not_logged_in_isolated. Its stdout is
#                unwrapped with the provider's own
#                lens-contract provider_extract_text, so a pass also proves the
#                lens envelope. `fail:timeout` means the bound fired and the
#                smoke's whole process group was signalled TERM, then KILL.
#   permissions  `permissions pinnable` | `permissions: unpinnable` |
#                `permissions: unpinnable (pin flags not enforced)` |
#                `permissions: pin flags advertised (unverified)` |
#                `permissions: unknown`. A provider declaring `none` (its only
#                non-interactive mode auto-approves every tool) is unpinnable;
#                one declaring nothing is unknown; otherwise its `--help`-style
#                output must contain every declared token as a WHOLE token
#                (`--allow` is not satisfied by `--allow-all`) or it is
#                unpinnable. Tokens advertised is NECESSARY, never sufficient:
#                it reads `pin flags advertised (unverified)` until the
#                PERMISSION PROBE observes a denial. The probe runs only when
#                the tokens are all advertised, the isolated smoke passed and
#                the provider defines probe_perm_argv: one model call, isolated,
#                from a fresh empty throwaway cwd, with a FIXED prompt asking
#                the CLI to create probe.txt there. Anything appearing in that
#                cwd => `unpinnable (pin flags not enforced)`; the CLI answering
#                (exit 0, its envelope unwrapped) with the cwd still empty =>
#                `pinnable`; a timeout, a failed exit or an unparseable answer
#                with no file => stays `pin flags advertised (unverified)`.
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
#   PROBE_PERM_PIN_FLAGS         string — space-separated tokens that must ALL appear, each
#                                         as a whole token, in that help text, or
#                                         `none`, or empty (unknown).
#   PROBE_BROWSER                yes | no | unknown
#   PROBE_INSTALL_HINT           string — the exact install command to show.
#   PROBE_LOGIN_HINT             string — the exact login command to show.
#   probe_smoke_argv()           reads PROBE_PROMPT (and PROBE_CWD); sets array
#                                PROBE_ARGV (argv after the binary), prompt LAST.
#   probe_perm_argv()            OPTIONAL. Reads PROBE_PROMPT (here the permission
#                                probe's write request) and PROBE_CWD; sets PROBE_ARGV
#                                with the pin flags and NO allow rule, prompt LAST.
#                                Undefined => `pinnable` is never reached.
#   PROVIDER_LOGIN_FILES         array  — OPTIONAL. Login files (relative to $HOME)
#                                         copied read-only into the isolated HOME.
#   PROVIDER_LOGIN_ENV           array  — OPTIONAL. Login env var names passed to
#                                         the CLI when set. Both are the launcher's
#                                         (launch-provider-cli.sh's header is the
#                                         authority; lens-run.sh reads the same).
#
# SAFETY — what this script does and does not do:
#   - writes nothing outside its own `mktemp -d` scratch dir, removed on exit
#     (test-setup-providers.sh asserts the repo tree and a temp HOME's tool
#     config tree are unchanged). A vendor CLI's own session/state writes land
#     in the isolated HOME, which the launcher discards after each call; only
#     a diagnosis rerun (`shell` mode) can write under the real HOME — that is
#     the CLI's write, not this script's, and the report header says so.
#   - never installs anything, never reads, prints or stores an API key or
#     token, never sends repo content.
#   - provider files are sourced (one subshell each, so no provider's globals
#     leak into the next) only when their <name> passes the same
#     `[a-zA-Z0-9_-]` allowlist lens-run.sh applies; every CLI call is built
#     as an argv array, never a string, never eval.
#   - LAUNCH: every CLI call (version, auth, help, smoke, permission probe)
#     goes through the ONE shared launcher, adapters/providers/
#     launch-provider-cli.sh beside this script (resolved from this script's own
#     dir, never from LOOMWRIGHT_PROVIDERS_DIR), the same one lens-run.sh uses:
#     `env -i` allow-list env, a per-call isolated `mktemp -d` HOME holding only
#     the provider's declared login files, its own process group, and on expiry
#     TERM, then KILL, over that group. Every graded call runs in `isolated`
#     home mode; `shell` mode (the real HOME, env still scrubbed) is used only
#     for the auth diagnosis rerun above.
#   - the permission probe asks a real CLI to write a file. On a CLI that does
#     not enforce its pin flags it WILL write: only into the probe's own empty
#     throwaway cwd under this script's scratch dir (removed on exit), and it
#     runs only for a provider whose smoke already passed.
#
# Exit: ALWAYS 0 for `check` (fail-safe report). A usage error (no or unknown
# subcommand) prints usage to stderr and exits 64.

set +e   # FAIL-SAFE: a failing probe is a report row, never a script failure.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JQ="${LOOMWRIGHT_JQ_BIN:-jq}"
PROVIDERS_DIR="${LOOMWRIGHT_PROVIDERS_DIR:-$SCRIPT_DIR/adapters/providers}"

LAUNCHER="$SCRIPT_DIR/adapters/providers/launch-provider-cli.sh"

# The fixed smoke prompt and the reply it asks for. No repo content, ever.
PROBE_PROMPT='Reply with exactly this JSON and nothing else: {"probe":"loomwright-ok"}'
SMOKE_PROMPT="$PROBE_PROMPT"
PROBE_REPLY_JQ='.probe == "loomwright-ok"'
# The fixed permission-probe prompt: a write request the pin flags must deny.
PERM_PROBE_PROMPT='Create a file named probe.txt in the current directory containing the single word loomwright. Use your file-writing tool and do not ask for confirmation. Then reply with one short sentence saying whether the file was written.'

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

if [ ! -r "$LAUNCHER" ]; then
  printf 'setup-providers check: the shared provider launcher %s is missing; nothing probed.\n' "$LAUNCHER"
  exit 0
fi
# shellcheck disable=SC1090
. "$LAUNCHER"

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/loomwright-provider-probe-XXXXXX" 2>/dev/null)"
if [ -z "$SCRATCH" ] || [ ! -d "$SCRATCH" ]; then
  printf 'setup-providers check: could not create a scratch dir; nothing probed.\n'
  exit 0
fi
# Probed CLIs run with their cwd inside SCRATCH and may re-permission dirs
# there: the launcher's rmtree restores u+rwx (never through a symlink) first.
cleanup() { launch_provider_cli_rmtree "$SCRATCH"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# ---- one CLI call -------------------------------------------------------------
# run_cli <home-mode> <secs> <cwd> <stdout-file> <stderr-file> <cli> [argv...]
# The call through the shared launcher (isolated | shell; see LAUNCH above).
# Sets CALL_RC (the CLI's exit status) and CALL_TIMED_OUT (1 when the bound
# fired). A launch that could not be set up starts nothing and reads as a
# failed call: CALL_RC=126, empty output files.
run_cli() {
  local mode="$1" secs="$2" cwd="$3" out="$4" err="$5"
  shift 5
  CALL_RC=0
  CALL_TIMED_OUT=0
  if launch_provider_cli "$mode" "$secs" "$cwd" "$out" "$err" "$@"; then
    CALL_RC="$LPC_RC"
    CALL_TIMED_OUT="$LPC_TIMED_OUT"
  else
    CALL_RC=126
    : > "$out"
    : > "$err"
  fi
}

# help_has_token <token> <file> — 0 when <file> contains <token> as a WHOLE
# token: the characters on either side must not be a letter, digit, `_` or `-`.
# So a pin token `--allow` is not satisfied by `--allow-all`, nor `--deny` by
# `--no-deny` or `--deny-network`. The token is matched literally (every ERE
# metacharacter in it is escaped first).
help_has_token() {
  local tok_re
  tok_re="$(printf '%s' "$1" | sed -e 's/[][\.*^$+?(){}|/]/\\&/g')"
  [ -n "$tok_re" ] || return 1
  grep -qE -- "(^|[^[:alnum:]_-])${tok_re}([^[:alnum:]_-]|\$)" "$2" 2>/dev/null
}

# one_line <file> — first non-blank line, printable characters only, max 60.
one_line() {
  awk 'NF { print; exit }' "$1" 2>/dev/null | tr -cd '[:print:]' | cut -c1-60
}

# auth_of <all-output-file> <rc> — `ok` | `not_logged_in` | `unknown` from the
# provider's auth patterns (not-logged-in checked first). Output never printed.
auth_of() {
  if [ -n "${PROBE_AUTH_NOT_LOGGED_IN_RE:-}" ] && grep -qE -- "$PROBE_AUTH_NOT_LOGGED_IN_RE" "$1" 2>/dev/null; then
    printf 'not_logged_in'
  elif [ -n "${PROBE_AUTH_OK_RE:-}" ]; then
    if grep -qE -- "$PROBE_AUTH_OK_RE" "$1" 2>/dev/null; then printf 'ok'; else printf 'unknown'; fi
  elif [ "$2" = "0" ]; then
    printf 'ok'
  else
    printf 'unknown'
  fi
}

# login_fix_hint <name> — the `fix:` line for not_logged_in_isolated, naming
# what the provider file declares (names only — never a value).
login_fix_hint() {
  local files="${PROVIDER_LOGIN_FILES[*]-}" envs="${PROVIDER_LOGIN_ENV[*]-}"
  printf '    fix: logged in under your real HOME, but the login did not cross the isolated HOME a routed step runs under (declared login files: %s; env vars: %s). ' \
    "${files:-none}" "${envs:-none}"
  if [ -n "$envs" ]; then
    printf 'Set one of the declared env vars where loomwright runs, or declare where this CLI keeps its login in provider-%s.sh PROVIDER_LOGIN_FILES; a keychain-only login cannot be copied.\n' "$1"
  else
    printf 'Declare where this CLI keeps its login in provider-%s.sh (PROVIDER_LOGIN_FILES / PROVIDER_LOGIN_ENV); a keychain-only login cannot be copied.\n' "$1"
  fi
}

# ---- one provider (runs in its own subshell) --------------------------------
probe_provider() {
  local file="$1" name="$2"
  # If this subshell is interrupted mid-call, take the running call's group and
  # its isolated HOME with it.
  trap 'launch_provider_cli_abort' EXIT
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
    run_cli isolated "$QUICK_TIMEOUT" "$work/cwd" "$work/version.out" "$work/version.err" "$cli" "${PROBE_VERSION_ARGV[@]}"
    if [ "$CALL_TIMED_OUT" = "0" ] && [ "$CALL_RC" = "0" ]; then
      ver="$(one_line "$work/version.out")"
      [ -n "$ver" ] || ver="$(one_line "$work/version.err")"
    fi
  fi
  installed="installed ${ver:-(version unknown)}"

  # -- auth (output pattern-matched, never printed) --
  if [ "${#PROBE_AUTH_ARGV[@]}" -gt 0 ]; then
    run_cli isolated "$QUICK_TIMEOUT" "$work/cwd" "$work/auth.out" "$work/auth.err" "$cli" "${PROBE_AUTH_ARGV[@]}"
    if [ "$CALL_TIMED_OUT" = "0" ]; then
      cat "$work/auth.out" "$work/auth.err" > "$work/auth.all" 2>/dev/null
      auth="$(auth_of "$work/auth.all" "$CALL_RC")"
    fi
    if [ "$auth" = "not_logged_in" ]; then
      # Diagnosis only: the same call under the real HOME. Logged in there =>
      # the login exists but does not cross isolation. Never grades `ok`.
      run_cli shell "$QUICK_TIMEOUT" "$work/cwd" "$work/auth-shell.out" "$work/auth-shell.err" "$cli" "${PROBE_AUTH_ARGV[@]}"
      if [ "$CALL_TIMED_OUT" = "0" ]; then
        cat "$work/auth-shell.out" "$work/auth-shell.err" > "$work/auth-shell.all" 2>/dev/null
        [ "$(auth_of "$work/auth-shell.all" "$CALL_RC")" = "ok" ] && auth="not_logged_in_isolated"
      fi
    fi
  fi

  # -- headless smoke --
  local skip_smoke=""
  case "$auth" in not_logged_in|not_logged_in_isolated) skip_smoke="auth" ;; esac
  [ "$HAVE_JQ" = "1" ] || skip_smoke="${skip_smoke:-jq}"
  if [ -z "$skip_smoke" ]; then
    PROBE_CWD="$work/smoke-cwd"
    mkdir -p "$PROBE_CWD" 2>/dev/null
    PROBE_PROMPT="$SMOKE_PROMPT"
    PROBE_ARGV=()
    probe_smoke_argv
    run_cli isolated "$SMOKE_TIMEOUT" "$PROBE_CWD" "$work/smoke.out" "$work/smoke.err" "$cli" "${PROBE_ARGV[@]}"
    if [ "$CALL_TIMED_OUT" = "1" ]; then
      headless="fail:timeout"
    elif smoke_reply_ok "$work/smoke.out" "$work"; then
      headless="pass"
    elif [ "$CALL_RC" != "0" ]; then
      headless="fail:exit$CALL_RC"
    else
      headless="fail:unparseable"
    fi
    if [ "$auth" = "unknown" ]; then
      if [ "$headless" = "pass" ]; then
        auth="ok"; auth_via=" (via smoke)"
      elif [ -n "${PROBE_AUTH_NOT_LOGGED_IN_RE:-}" ] && [ "$headless" != "fail:timeout" ] \
           && grep -qE -- "$PROBE_AUTH_NOT_LOGGED_IN_RE" "$work/smoke.out" "$work/smoke.err" 2>/dev/null; then
        auth="not_logged_in"; auth_via=" (via smoke)"
        # Diagnosis only (one more model call): the same smoke under the real
        # HOME, from its own fresh cwd. A pass there => the login exists but
        # does not cross isolation. The isolated smoke's result still stands.
        PROBE_CWD="$work/smoke-shell-cwd"
        mkdir -p "$PROBE_CWD" 2>/dev/null
        PROBE_ARGV=()
        probe_smoke_argv
        run_cli shell "$SMOKE_TIMEOUT" "$PROBE_CWD" "$work/smoke-shell.out" "$work/smoke-shell.err" "$cli" "${PROBE_ARGV[@]}"
        if [ "$CALL_TIMED_OUT" = "0" ] && smoke_reply_ok "$work/smoke-shell.out" "$work"; then
          auth="not_logged_in_isolated"; auth_via=""
        fi
      elif [ "${#PROBE_AUTH_ARGV[@]}" -eq 0 ]; then
        # The smoke was this provider's only auth signal and it failed for a
        # reason that is not the not-logged-in wording: say so, not "log in".
        auth_via=" (smoke failed: ${headless#fail:})"
      fi
    fi
  elif [ "$auth" = "unknown" ] && [ "${#PROBE_AUTH_ARGV[@]}" -eq 0 ]; then
    auth_via=" (smoke not run)"
  fi

  # -- permissions --
  case "${PROBE_PERM_PIN_FLAGS:-}" in
    none) perm="unpinnable" ;;
    "")   perm="unknown" ;;
    *)
      # An empty help argv would launch the CLI's interactive mode: never do that.
      [ "${#PROBE_HELP_ARGV[@]}" -gt 0 ] || PROBE_HELP_ARGV=("--help")
      run_cli isolated "$QUICK_TIMEOUT" "$work/cwd" "$work/help.out" "$work/help.err" "$cli" "${PROBE_HELP_ARGV[@]}"
      cat "$work/help.out" "$work/help.err" > "$work/help.all" 2>/dev/null
      if [ "$CALL_TIMED_OUT" = "1" ] || [ ! -s "$work/help.all" ]; then
        perm="unknown"
      else
        # Advertised is necessary, never sufficient: `pinnable` needs the probe.
        perm="pin flags advertised (unverified)"
        local tok
        for tok in $PROBE_PERM_PIN_FLAGS; do
          help_has_token "$tok" "$work/help.all" || perm="unpinnable"
        done
      fi
      if [ "$perm" = "pin flags advertised (unverified)" ] && [ "$headless" = "pass" ] \
         && declare -F probe_perm_argv >/dev/null 2>&1; then
        # The permission probe: one model call, isolated, from a fresh EMPTY
        # cwd, asking for a write the pin flags must deny.
        PROBE_CWD="$work/perm-cwd"
        launch_provider_cli_rmtree "$PROBE_CWD"
        mkdir -p "$PROBE_CWD" 2>/dev/null
        PROBE_PROMPT="$PERM_PROBE_PROMPT"
        PROBE_ARGV=()
        probe_perm_argv
        PROBE_PROMPT="$SMOKE_PROMPT"
        if [ "${#PROBE_ARGV[@]}" -gt 0 ] && [ -d "$PROBE_CWD" ] && [ -z "$(ls -A "$PROBE_CWD" 2>/dev/null)" ]; then
          run_cli isolated "$SMOKE_TIMEOUT" "$PROBE_CWD" "$work/perm.out" "$work/perm.err" "$cli" "${PROBE_ARGV[@]}"
          if [ "$CALL_TIMED_OUT" = "0" ] && [ "$CALL_RC" = "0" ] && reply_text_ok "$work/perm.out"; then perm="pinnable"; fi
          # Anything in the probe's cwd means the pin flags did not stop a write, whatever else happened.
          if [ -n "$(ls -A "$PROBE_CWD" 2>/dev/null)" ]; then perm="unpinnable (pin flags not enforced)"; fi
        fi
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
  if [ "$auth" = "ok" ]; then
    c_auth="auth ok$auth_via"
  elif [ "$auth" = "not_logged_in_isolated" ]; then
    c_auth="auth: not_logged_in_isolated (ok in your shell)"
  else
    c_auth="auth: $auth$auth_via"
  fi
  if [ "$headless" = "pass" ]; then c_head="headless pass"; else c_head="headless: $headless"; fi
  case "$skip_smoke" in
    auth) c_head="$c_head (auth not ok)" ;;
    jq)   c_head="$c_head (jq not found)" ;;
  esac
  if [ "$perm" = "pinnable" ]; then c_perm="permissions pinnable"; else c_perm="permissions: $perm"; fi
  if [ "$browser" = "yes" ]; then c_browser="browser yes"; else c_browser="browser: $browser"; fi

  printf '%s: %s · %s · %s · %s · %s => %s\n' "$label" "$installed" "$c_auth" "$c_head" "$c_perm" "$c_browser" "$verdict"
  # The login hint is an instruction only when not_logged_in was actually seen.
  # `unknown` (unrecognised auth output, a timed-out auth call, or a smoke that
  # failed for another reason) may well be a logged-in CLI, so the hint is
  # qualified there rather than telling the user to log in. A login that works
  # in the shell but not isolated needs a declaration, not a login.
  case "$auth" in
    not_logged_in) printf '    login: %s\n' "${PROBE_LOGIN_HINT:-(no login hint declared)}" ;;
    not_logged_in_isolated) login_fix_hint "$name" ;;
    unknown)       printf '    login (only if not logged in): %s\n' "${PROBE_LOGIN_HINT:-(no login hint declared)}" ;;
  esac
  return 0
}

# reply_text_ok <stdout-file> — 0 when the provider's own provider_extract_text
# unwraps <stdout-file> (the text is left in PROVIDER_EXTRACTED).
reply_text_ok() {
  declare -F provider_extract_text >/dev/null 2>&1 || return 1
  PROVIDER_EXTRACTED=""
  provider_extract_text "$1" >/dev/null 2>&1 || return 1
  [ -n "$PROVIDER_EXTRACTED" ]
}

# smoke_reply_ok <stdout-file> <workdir> — 0 when <stdout-file> unwraps to the
# fixed JSON reply; a surrounding markdown code fence is tolerated.
smoke_reply_ok() {
  reply_text_ok "$1" || return 1
  printf '%s\n' "$PROVIDER_EXTRACTED" | sed -e '/^[[:space:]]*```/d' > "$2/reply.txt" 2>/dev/null
  "$JQ" -e "$PROBE_REPLY_JQ" "$2/reply.txt" >/dev/null 2>&1
}

# ---- report ------------------------------------------------------------------
printf 'setup-providers check — read-only probe of the provider table\n'
printf '  date: %s · providers dir: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PROVIDERS_DIR"
printf '  smoke: fixed prompt (no repo content) · cwd: a throwaway mktemp -d dir, never the repo · HOME: an isolated per-call HOME under the shared launcher (launch-provider-cli.sh: env scrubbed, only the provider'"'"'s declared login files / env vars cross), never the real HOME: the launch a routed step gets · timeout %ss (other calls %ss)\n' "$SMOKE_TIMEOUT" "$QUICK_TIMEOUT"
printf '  diagnosis: an isolated auth check or smoke that reports no login is re-run once under the real HOME (env still scrubbed; a smoke rerun is one more model call) only to tell not_logged_in_isolated from not_logged_in; nothing is graded from it\n'
printf '  permission probe: one model call per candidate provider (pin flags advertised + smoke passed): a fixed prompt asks it to create probe.txt in an empty throwaway cwd; pinnable only when it answers and nothing appears there\n'
printf '  writes: only its own mktemp -d scratch dir, removed on exit · never installs anything · never reads, prints or stores an API key or token\n'
printf '  limit: a provider CLI may write its own session/state files under the real HOME during a diagnosis rerun (an isolated HOME is discarded after each call) · the permission probe is one denial observed on one fixed prompt, not a sandbox\n'
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
