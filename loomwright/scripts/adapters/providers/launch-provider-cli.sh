#!/usr/bin/env bash
# launch-provider-cli.sh — SOURCED library (never executed, never named
# `provider-*.sh`: setup-providers.sh globs that pattern and lens-run.sh would
# accept it as a provider). It is the ONE place that starts a provider CLI.
# Callers: lens-run.sh (beside this file) and setup-providers.sh `check` (which
# resolves this file from its OWN script dir, never from
# LOOMWRIGHT_PROVIDERS_DIR).
#
# API
#   launch_provider_cli <home-mode> <timeout-secs> <cwd> <stdout-file> <stderr-file> <cli> [argv...]
#     home-mode     `isolated` — a fresh `mktemp -d` HOME (also the child's
#                   TMPDIR) holding ONLY the caller's declared login files; the
#                   only mode any verdict may be graded from.
#                   `shell` — the real HOME, still env-scrubbed; a diagnosis
#                   rerun only (tells "login cannot cross isolation" apart from
#                   "not logged in at all").
#     timeout-secs  positive integer. On expiry the CLI's process group gets
#                   TERM, then KILL 2s later.
#     cwd           directory the CLI runs in.
#     stdout-file / stderr-file  where the CLI's output goes; stdin is /dev/null.
#     cli [argv...] the binary and its argv, as an array: never a string,
#                   never eval.
#   Returns 0 when the CLI was started and has ended; then LPC_RC is its exit
#   status and LPC_TIMED_OUT is 1 when the bound fired (else 0). Returns 1 when
#   the launch could not be set up (bad argument, no temp dir): LPC_ERROR
#   names why and NO process was started.
#
#   launch_provider_cli_abort
#     For a caller's EXIT / INT / TERM path: kills a still-running CLI's process
#     group (TERM, then KILL), stops the watchdog and removes the isolated HOME.
#     Safe to call when nothing is running.
#
# LOGIN PASS-THROUGH (read from the caller's globals, i.e. the sourced
# provider-<name>.sh file; unset or empty => nothing crosses):
#   PROVIDER_LOGIN_FILES  array of paths RELATIVE to $HOME. In `isolated` mode
#                         each one that exists as a readable regular file is
#                         COPIED (cp, which dereferences a symlinked source;
#                         never a link) to the same relative path under the
#                         isolated HOME and made read-only (0400). An absolute
#                         path, a `.` / `..` / empty segment, or a character
#                         outside [A-Za-z0-9._/-] is refused and never crosses.
#   PROVIDER_LOGIN_ENV    array of env var names ([A-Z_][A-Z0-9_]*). Each one
#                         that is SET in the caller is passed to the child, in
#                         both modes. PATH, HOME and TMPDIR are refused (they
#                         would undo the isolation).
#
# CHILD ENVIRONMENT — `env -i` starts EMPTY, then gets only the allow-list
# PATH, HOME, TMPDIR plus the declared login env vars that are set. No ambient
# variable (GH_TOKEN, another provider's API key, ...) reaches the CLI.
#
# PROCESS GROUP — the CLI is exec'd as the leader of its own process group
# (perl setpgrp, python3 fallback), so the timeout and the abort path kill the
# whole tree. The kill never targets the caller's own group or group 1. With
# neither perl nor python3 the CLI shares the caller's group and only the
# leader and its direct children are signalled. When the leader ends normally,
# any member still left in its group is signalled too, so nothing outlives the
# removal of its HOME.
#
# HONEST LIMITS — this is blast-radius reduction, not a sandbox: the CLI can
# still read and write anything this user can outside the isolated HOME, and
# reach the network. A copied login file is a live credential for the
# duration of the call; the isolated HOME is 0700 and removed on every exit
# path this library sees (normal end, timeout, abort), but a SIGKILL of the
# caller leaves it in TMPDIR.
#
# Bash 3.2 compatible. Never prints, logs or reads the content of a login file.

LPC_RC=0
LPC_TIMED_OUT=0
LPC_ERROR=""
LPC_HOME=""
LPC__PID=""
LPC__WD_PID=""
LPC__FLAG=""
LPC__OWN_PGROUP=0
LPC__SELF_PGID=""

# _lpc_valid_rel <path> — 0 when <path> is a safe path relative to $HOME.
_lpc_valid_rel() {
  case "$1" in
    ""|/*|*//*|*/) return 1 ;;
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-]*) return 1 ;;
  esac
  case "/$1/" in
    */../*|*/./*) return 1 ;;
  esac
  return 0
}

# _lpc_valid_env_name <name> — 0 when <name> may be passed through.
_lpc_valid_env_name() {
  case "$1" in
    ""|[!ABCDEFGHIJKLMNOPQRSTUVWXYZ_]*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*) return 1 ;;
    PATH|HOME|TMPDIR) return 1 ;;
  esac
  return 0
}

# _lpc_exec <argv...> — exec the argv as the leader of a NEW process group.
# perl's block form of exec never goes through a shell, whatever the argv holds.
_lpc_exec() {
  if command -v perl >/dev/null 2>&1; then
    exec perl -e 'setpgrp; exec { $ARGV[0] } @ARGV or exit 127' "$@"
  fi
  if command -v python3 >/dev/null 2>&1; then
    exec python3 -c 'import os, sys; os.setpgrp(); os.execvp(sys.argv[1], sys.argv[1:])' "$@"
  fi
  exec "$@"
}

# _lpc_kill <signal> — the running CLI's whole process group, or (no setpgrp
# helper) its leader and direct children. Never the caller's group, never 1.
_lpc_kill() {
  local sig="$1" child
  [ -n "$LPC__PID" ] || return 0
  if [ "$LPC__OWN_PGROUP" = "1" ] && [ "$LPC__PID" != "1" ] && [ "$LPC__PID" != "$LPC__SELF_PGID" ]; then
    kill -s "$sig" -- -"$LPC__PID" 2>/dev/null
    return 0
  fi
  kill -s "$sig" "$LPC__PID" 2>/dev/null
  if command -v pgrep >/dev/null 2>&1; then
    for child in $(pgrep -P "$LPC__PID" 2>/dev/null); do
      kill -s "$sig" "$child" 2>/dev/null
    done
  fi
}

# _lpc_group_alive — 0 while any process is left in the CLI's own group.
_lpc_group_alive() {
  [ "$LPC__OWN_PGROUP" = "1" ] && [ -n "$LPC__PID" ] && [ "$LPC__PID" != "1" ] \
    && [ "$LPC__PID" != "$LPC__SELF_PGID" ] && kill -0 -- -"$LPC__PID" 2>/dev/null
}

# _lpc_make_home — create the isolated HOME and copy the declared login files.
_lpc_make_home() {
  local rel src dst
  LPC_HOME="$(mktemp -d "${TMPDIR:-/tmp}/loomwright-provider-home-XXXXXX" 2>/dev/null)"
  if [ -z "$LPC_HOME" ] || [ ! -d "$LPC_HOME" ]; then
    LPC_HOME=""
    LPC_ERROR="could not create an isolated HOME temp dir"
    return 1
  fi
  chmod 700 "$LPC_HOME" 2>/dev/null
  for rel in ${PROVIDER_LOGIN_FILES[@]+"${PROVIDER_LOGIN_FILES[@]}"}; do
    _lpc_valid_rel "$rel" || continue
    src="$HOME/$rel"
    [ -f "$src" ] && [ -r "$src" ] || continue
    dst="$LPC_HOME/$rel"
    # Declared twice: the first copy is already there (and read-only) — keep it.
    [ -e "$dst" ] && continue
    mkdir -p "${dst%/*}" 2>/dev/null || continue
    if cp "$src" "$dst" 2>/dev/null; then
      chmod 0400 "$dst" 2>/dev/null
    else
      rm -f "$dst" 2>/dev/null
    fi
  done
  return 0
}

_lpc_finish() {
  if [ -n "$LPC_HOME" ]; then
    # u+w first: a CLI that left a read-only dir behind must not keep it alive.
    chmod -R u+w "$LPC_HOME" 2>/dev/null
    rm -rf "$LPC_HOME" 2>/dev/null
  fi
  [ -n "$LPC__FLAG" ] && rm -f "$LPC__FLAG" 2>/dev/null
  LPC_HOME=""
  LPC__FLAG=""
  LPC__PID=""
  LPC__WD_PID=""
}

launch_provider_cli() {
  local mode="$1" secs="$2" cwd="$3" out="$4" err="$5"
  LPC_RC=0
  LPC_TIMED_OUT=0
  LPC_ERROR=""
  if [ $# -lt 6 ]; then
    LPC_ERROR="usage: launch_provider_cli <isolated|shell> <timeout-secs> <cwd> <stdout-file> <stderr-file> <cli> [argv...]"
    return 1
  fi
  shift 5
  local cli="$1"
  shift
  case "$mode" in
    isolated|shell) ;;
    *) LPC_ERROR="unknown home mode '$mode' (isolated | shell)"; return 1 ;;
  esac
  case "$secs" in
    ''|*[!0-9]*) LPC_ERROR="timeout must be a positive integer"; return 1 ;;
  esac
  if [ "$secs" -le 0 ] 2>/dev/null; then LPC_ERROR="timeout must be a positive integer"; return 1; fi
  # `env` would read a leading `-` as an option and a `=` as an assignment.
  case "$cli" in
    ""|-*|*=*) LPC_ERROR="refused CLI name"; return 1 ;;
  esac
  [ -d "$cwd" ] || { LPC_ERROR="cwd is not a directory"; return 1; }

  local child_home child_tmp
  if [ "$mode" = "isolated" ]; then
    _lpc_make_home || return 1
    child_home="$LPC_HOME"
    child_tmp="$LPC_HOME"
  else
    child_home="$HOME"
    child_tmp="${TMPDIR:-/tmp}"
  fi

  local -a envv
  envv=("PATH=$PATH" "HOME=$child_home" "TMPDIR=$child_tmp")
  local name isset val
  for name in ${PROVIDER_LOGIN_ENV[@]+"${PROVIDER_LOGIN_ENV[@]}"}; do
    _lpc_valid_env_name "$name" || continue
    isset=""
    eval "isset=\${$name+x}"   # name is [A-Z_][A-Z0-9_]* (validated above)
    [ "$isset" = "x" ] || continue
    eval "val=\${$name}"
    envv+=("$name=$val")
  done

  LPC__FLAG="$(mktemp "${TMPDIR:-/tmp}/loomwright-provider-tmo-XXXXXX" 2>/dev/null)"
  if [ -z "$LPC__FLAG" ]; then
    LPC_ERROR="could not allocate a timeout flag file"
    _lpc_finish
    return 1
  fi
  # The flag file is KEPT (mktemp made it 0600, ours, O_EXCL): the watchdog
  # writes into it and the bound reads as fired only when it is non-empty.
  # Deleting it and re-creating it by name later would let an entry planted
  # at that path in the gap be followed (a symlink would be written through)
  # or read as a timeout. _lpc_finish removes it on every exit path.

  LPC__SELF_PGID="$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ')"
  LPC__OWN_PGROUP=0
  if command -v perl >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; then
    LPC__OWN_PGROUP=1
  fi

  ( cd "$cwd" 2>/dev/null || exit 90
    _lpc_exec env -i "${envv[@]}" "$cli" "$@" ) >"$out" 2>"$err" </dev/null &
  LPC__PID=$!

  # Watchdog. Its sleep runs in the background and the TERM trap kills it: a
  # foreground sleep would outlive the kill below and leave one
  # `sleep <secs>` behind per call.
  (
    wd_sleep=""
    trap '[ -n "$wd_sleep" ] && kill "$wd_sleep" 2>/dev/null; exit 0' TERM
    sleep "$secs" & wd_sleep=$!
    wait "$wd_sleep"
    if kill -0 "$LPC__PID" 2>/dev/null; then
      printf '1\n' > "$LPC__FLAG"
      _lpc_kill TERM
      sleep 2
      _lpc_kill KILL
    fi
  ) >/dev/null 2>&1 &
  LPC__WD_PID=$!

  wait "$LPC__PID" 2>/dev/null
  LPC_RC=$?
  if [ -s "$LPC__FLAG" ]; then
    # The bound fired: let the watchdog finish, so its KILL still reaches
    # group members that ignored TERM.
    LPC_TIMED_OUT=1
    wait "$LPC__WD_PID" 2>/dev/null
  else
    kill "$LPC__WD_PID" 2>/dev/null
    wait "$LPC__WD_PID" 2>/dev/null
  fi
  LPC__WD_PID=""
  # The leader is gone; anything it left in its group goes before its HOME does.
  if _lpc_group_alive; then
    _lpc_kill TERM
    local i=0
    while _lpc_group_alive && [ "$i" -lt 10 ]; do sleep 0.2; i=$((i + 1)); done
    _lpc_group_alive && _lpc_kill KILL
  fi
  _lpc_finish
  return 0
}

launch_provider_cli_abort() {
  if [ -n "$LPC__WD_PID" ]; then
    kill "$LPC__WD_PID" 2>/dev/null
    wait "$LPC__WD_PID" 2>/dev/null
  fi
  if [ -n "$LPC__PID" ]; then
    _lpc_kill TERM
    sleep 1
    _lpc_kill KILL
  fi
  _lpc_finish
}
