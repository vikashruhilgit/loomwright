#!/usr/bin/env bash
# setup-statusline.sh — deterministic engine for the `/setup statusline` module: wire
# `status-line.sh` into the host's user-scope settings file, opt-in, backup-first, and without
# ever destroying a status line the user already had.
#
# WHAT IT WRITES — and the whole list is one file:
#   the user-scope settings JSON (default `$HOME/.claude/settings.json`, overridable with
#   `--settings` for tests). Nothing else, anywhere. No project file, no sibling directory, no
#   state file of its own — the restore record for `remove` lives INSIDE that same document
#   under the namespaced key `loomwrightStatusLinePrior`, precisely so this module's write
#   domain stays one path rather than sprawling.
#
# THE PRE-EXISTING STATUS LINE IS THE POINT.
#   A user who already has a status line configured has one because they wanted it. A naive
#   deep-merge would silently destroy it — the AC this module was written against originally
#   protected only keys UNRELATED to the status line, which is exactly the key this module
#   overwrites. So `apply` is CONSENT-BEARING in the write dimension too: a status line this
#   plugin did not write is REPORTED and PRESERVED, and replacing it requires the explicit
#   `--replace` flag. The replaced value is recorded so `remove` restores it verbatim.
#
#   Ownership is decided by one rule, stated with its limit: a status line is OURS when its
#   `.command` string contains `status-line.sh`. That is a heuristic, not a proof — a user with
#   an unrelated script of the same basename would read as ours. It is the honest trade against
#   the alternative (a marker key nested inside `statusLine`, which is a host-owned schema this
#   module must not extend). The limit is stated here rather than hidden.
#
# FAIL-SAFE CONTRACT (mirrors setup-memory.sh): every branch exits 0. "Fails closed" here means
# REFUSE-TO-WRITE plus a machine-readable named-reason status line — never a non-zero exit,
# which would regress every non-blocking caller. Concretely: an unparseable settings document
# ABORTS with nothing written and no backup; a missing `jq` ABORTS the same way; a foreign
# status line WITHHOLDS. All of them exit 0.
#
# SUBCOMMANDS
#   check   read-only. Reports the settings path, its parse state, whether a status line is
#           present and whose, the restore record, and a readiness verdict. Writes nothing.
#   apply   install the status line. Backup-first, parse-gated, atomic, byte-compare idempotent.
#   remove  restore the pre-existing status line (or delete ours when there was none) and drop
#           the restore record. Refuses to touch a status line that is not ours.
#
# FLAGS
#   --settings <path>   override the settings document (self-test fixtures only)
#   --command <path>    override the status-line command (self-test fixtures only)
#   --replace           explicit opt-in to replace a status line this plugin did not write
#
# Portability: bash 3.2 / BSD userland safe. `jq` is a hard dependency and is `command -v`
# guarded rather than assumed. No GNU-only date/stat/sed flags, no associative arrays.

set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"

SUBCMD="${1:-check}"
[ $# -gt 0 ] && shift

SETTINGS="$HOME/.claude/settings.json"
# The status line ships next to this script in both a dev checkout and an installed plugin, so
# resolving it as a sibling needs no harness variable and cannot point at the wrong copy.
SL_COMMAND="$script_dir/status-line.sh"
REPLACE=0
PRIOR_KEY="loomwrightStatusLinePrior"

while [ $# -gt 0 ]; do
  case "$1" in
    --settings) shift; SETTINGS="${1:-}" ;;
    --command)  shift; SL_COMMAND="${1:-}" ;;
    --replace)  REPLACE=1 ;;
    *) echo "setup-statusline: unknown argument '$1' (ignored)" >&2 ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Probes
# ---------------------------------------------------------------------------

# jq PRESENCE is not jq FUNCTION: a jq on PATH that exits non-zero (wrong arch, broken install,
# a shim) would make every probe below "fail" and read as an unparseable document. Probe it
# functionally, and treat broken exactly like absent.
jq_works() {
  command -v jq >/dev/null 2>&1 || return 1
  printf '{}' | jq -e . >/dev/null 2>&1 || return 1
  return 0
}

settings_parses() {
  [ -f "$SETTINGS" ] || return 1
  jq empty "$SETTINGS" >/dev/null 2>&1
}

# statusline_json -> the current `.statusLine` value as JSON (`null` when absent).
statusline_json() {
  jq -c '.statusLine // null' "$SETTINGS" 2>/dev/null || printf 'null'
}

statusline_command() {
  jq -r '.statusLine.command // ""' "$SETTINGS" 2>/dev/null || printf ''
}

is_ours() {
  local cmd
  cmd="$(statusline_command)"
  [ -n "$cmd" ] || return 1
  case "$cmd" in *status-line.sh*) return 0 ;; esac
  return 1
}

# unique_backup_path — a second-granular timestamp alone means two writes in the same second
# resolve to ONE path and the second copy destroys the pristine original, which is the only
# thing a backup exists to protect. Suffix by pid, then by counter, then give up (an apply that
# cannot back up must ABORT, never write unbacked-up).
unique_backup_path() {
  local base="$SETTINGS.backup.$(date +%Y%m%d-%H%M%S)" cand i
  cand="$base"
  [ ! -e "$cand" ] && { printf '%s' "$cand"; return 0; }
  cand="$base.p$$"
  [ ! -e "$cand" ] && { printf '%s' "$cand"; return 0; }
  i=1
  while [ "$i" -le 50 ]; do
    cand="$base.p$$.$i"
    [ ! -e "$cand" ] && { printf '%s' "$cand"; return 0; }
    i=$((i + 1))
  done
  return 1
}

# ---------------------------------------------------------------------------
# check
# ---------------------------------------------------------------------------
do_check() {
  echo "== statusline =="
  echo "settings: $SETTINGS"
  echo "command:  $SL_COMMAND"

  if [ ! -f "$SL_COMMAND" ]; then
    echo "command file: MISSING (apply would abort — refusing to point a status line at a script that does not exist)"
  else
    echo "command file: present"
  fi

  if ! jq_works; then
    echo "settings parse: not probed (jq unavailable or non-functional)"
    echo "Statusline readiness: unknown (jq unavailable — nothing could be probed)"
    return 0
  fi

  if [ ! -f "$SETTINGS" ]; then
    echo "settings parse: absent (apply would create it)"
    echo "statusLine: absent"
    echo "Statusline readiness: not configured"
    return 0
  fi

  if ! settings_parses; then
    echo "settings parse: UNPARSEABLE — apply would ABORT and write nothing"
    echo "Statusline readiness: unknown (settings document is not valid JSON)"
    return 0
  fi
  echo "settings parse: ok"

  local sl prior
  sl="$(statusline_json)"
  prior="$(jq -c --arg k "$PRIOR_KEY" '.[$k] // null' "$SETTINGS" 2>/dev/null || printf 'null')"

  if [ "$sl" = "null" ]; then
    echo "statusLine: absent"
    echo "restore record: ${prior}"
    echo "Statusline readiness: not configured"
    return 0
  fi

  if is_ours; then
    echo "statusLine: present — installed by this plugin ($(statusline_command))"
    echo "restore record: ${prior}"
    echo "Statusline readiness: configured"
    return 0
  fi

  echo "statusLine: present — NOT installed by this plugin: $sl"
  echo "restore record: ${prior}"
  echo "Statusline readiness: foreign (a status line this plugin did not write is already configured; apply will PRESERVE it unless --replace is given)"
  return 0
}

# ---------------------------------------------------------------------------
# apply
# ---------------------------------------------------------------------------
do_apply() {
  if ! jq_works; then
    echo "apply: ABORTED — jq is unavailable or non-functional; nothing was written."
    return 0
  fi
  if [ ! -f "$SL_COMMAND" ]; then
    echo "apply: ABORTED — the status-line command does not exist: $SL_COMMAND (refusing to configure a status line that cannot run); nothing was written."
    return 0
  fi

  local desired sl prior_expr tmp backup
  desired="$(jq -n --arg c "$SL_COMMAND" '{type: "command", command: $c}')"

  if [ ! -f "$SETTINGS" ]; then
    mkdir -p "$(dirname "$SETTINGS")" 2>/dev/null || {
      echo "apply: ABORTED — could not create $(dirname "$SETTINGS"); nothing was written."
      return 0
    }
    tmp="$SETTINGS.tmp.$$"
    jq -n --argjson sl "$desired" --arg k "$PRIOR_KEY" '{statusLine: $sl} + {($k): null}' > "$tmp" 2>/dev/null || {
      rm -f "$tmp"
      echo "apply: ABORTED — could not compose a new settings document; nothing was written."
      return 0
    }
    mv "$tmp" "$SETTINGS" || {
      rm -f "$tmp"
      echo "apply: ABORTED — could not write $SETTINGS; nothing was written."
      return 0
    }
    echo "apply: applied (created $SETTINGS)"
    echo "verify:"
    do_check
    return 0
  fi

  if ! settings_parses; then
    echo "apply: ABORTED — $SETTINGS exists but is not valid JSON. Nothing was written and no backup was made; fix it by hand first."
    return 0
  fi

  sl="$(statusline_json)"

  if [ "$sl" != "null" ] && ! is_ours && [ "$REPLACE" -ne 1 ]; then
    echo "apply: WITHHELD — a statusLine this plugin did not write is already configured, and it has NOT been touched."
    echo "  existing: $sl"
    echo "  Nothing was written. To replace it (the previous value is recorded so \`remove\` can restore it), re-run with --replace."
    return 0
  fi

  # The restore record must survive re-application. When the current status line is already
  # OURS, the pre-existing value was captured on the FIRST apply and must be preserved verbatim
  # — recapturing it here would overwrite the user's original with our own line and silently
  # destroy the thing `remove` exists to give back.
  #
  # THE PRIOR VALUE IS CAPTURED IN THE SHELL, NEVER INSIDE THE jq PIPELINE. `.statusLine = $sl |
  # .[$k] = (.statusLine // null)` reads correct and is WRONG: jq evaluates the pipeline left to
  # right, so the first assignment has already overwritten `.statusLine` by the time the second
  # one reads it, and the "record" ends up being our OWN line. The user's status line is then
  # unrecoverable and `remove` hands back a copy of what it was supposed to undo. Passing the
  # captured value in with --argjson removes the ordering hazard entirely.
  local prior_value
  if is_ours; then
    prior_value="$(jq -c --arg k "$PRIOR_KEY" '.[$k] // null' "$SETTINGS" 2>/dev/null || printf 'null')"
  else
    prior_value="$sl"
  fi
  [ -n "$prior_value" ] || prior_value='null'

  local proposed
  proposed="$(jq --argjson sl "$desired" --arg k "$PRIOR_KEY" --argjson prior "$prior_value" \
    '.statusLine = $sl | .[$k] = $prior' "$SETTINGS" 2>/dev/null)" || {
    echo "apply: ABORTED — could not compose the merged settings document; nothing was written."
    return 0
  }
  [ -n "$proposed" ] || {
    echo "apply: ABORTED — the merge produced an empty document; nothing was written."
    return 0
  }

  # Byte-compare idempotency: compare the document we WOULD write against the one on disk, in
  # the same normalised form, so a second apply writes nothing and makes no second backup.
  local current_norm
  current_norm="$(jq . "$SETTINGS" 2>/dev/null)"
  if [ "$proposed" = "$current_norm" ]; then
    echo "apply: no-op — already configured ($SETTINGS is byte-identical to what apply would write)."
    return 0
  fi

  backup="$(unique_backup_path)" || {
    echo "apply: ABORTED — every candidate backup name for $SETTINGS is taken; refusing to rewrite it unbacked-up. Nothing was written."
    return 0
  }
  cp "$SETTINGS" "$backup" 2>/dev/null || {
    echo "apply: ABORTED — could not write a backup of $SETTINGS; refusing to rewrite it unbacked-up. Nothing was written."
    return 0
  }

  tmp="$SETTINGS.tmp.$$"
  printf '%s\n' "$proposed" > "$tmp" 2>/dev/null || {
    rm -f "$tmp"
    echo "apply: ABORTED — could not stage the new settings document; $SETTINGS is unchanged (backup at $backup)."
    return 0
  }
  mv "$tmp" "$SETTINGS" || {
    rm -f "$tmp"
    echo "apply: ABORTED — could not replace $SETTINGS; it is unchanged (backup at $backup)."
    return 0
  }

  if [ "$sl" != "null" ] && [ "$REPLACE" -eq 1 ]; then
    echo "apply: applied (REPLACED a pre-existing statusLine — the previous value is recorded under .$PRIOR_KEY and \`remove\` restores it)"
    echo "  replaced: $sl"
  else
    echo "apply: applied"
  fi
  echo "  backup: $backup"
  echo "verify:"
  do_check
  return 0
}

# ---------------------------------------------------------------------------
# remove
# ---------------------------------------------------------------------------
do_remove() {
  if ! jq_works; then
    echo "remove: ABORTED — jq is unavailable or non-functional; nothing was written."
    return 0
  fi
  if [ ! -f "$SETTINGS" ]; then
    echo "remove: no-op — $SETTINGS does not exist; nothing was written."
    return 0
  fi
  if ! settings_parses; then
    echo "remove: ABORTED — $SETTINGS exists but is not valid JSON. Nothing was written and no backup was made."
    return 0
  fi

  local sl prior proposed current_norm tmp backup
  sl="$(statusline_json)"
  prior="$(jq -c --arg k "$PRIOR_KEY" '.[$k] // null' "$SETTINGS" 2>/dev/null || printf 'null')"

  if [ "$sl" != "null" ] && ! is_ours; then
    echo "remove: REFUSED — the configured statusLine was not written by this plugin, so it is not this module's to remove."
    echo "  existing: $sl"
    echo "  Nothing was written."
    return 0
  fi

  proposed="$(jq --arg k "$PRIOR_KEY" \
    'if (.[$k] // null) == null then del(.statusLine) else .statusLine = .[$k] end | del(.[$k])' \
    "$SETTINGS" 2>/dev/null)" || {
    echo "remove: ABORTED — could not compose the restored settings document; nothing was written."
    return 0
  }
  [ -n "$proposed" ] || {
    echo "remove: ABORTED — the restore produced an empty document; nothing was written."
    return 0
  }

  current_norm="$(jq . "$SETTINGS" 2>/dev/null)"
  if [ "$proposed" = "$current_norm" ]; then
    echo "remove: no-op — nothing of this module's is present in $SETTINGS."
    return 0
  fi

  backup="$(unique_backup_path)" || {
    echo "remove: ABORTED — every candidate backup name for $SETTINGS is taken; refusing to rewrite it unbacked-up. Nothing was written."
    return 0
  }
  cp "$SETTINGS" "$backup" 2>/dev/null || {
    echo "remove: ABORTED — could not write a backup of $SETTINGS; refusing to rewrite it unbacked-up. Nothing was written."
    return 0
  }

  tmp="$SETTINGS.tmp.$$"
  printf '%s\n' "$proposed" > "$tmp" 2>/dev/null || {
    rm -f "$tmp"
    echo "remove: ABORTED — could not stage the restored settings document; $SETTINGS is unchanged (backup at $backup)."
    return 0
  }
  mv "$tmp" "$SETTINGS" || {
    rm -f "$tmp"
    echo "remove: ABORTED — could not replace $SETTINGS; it is unchanged (backup at $backup)."
    return 0
  }

  if [ "$prior" = "null" ]; then
    echo "remove: removed (there was no statusLine before this module applied, so none was restored)"
  else
    echo "remove: removed — the pre-existing statusLine has been RESTORED verbatim"
    echo "  restored: $prior"
  fi
  echo "  backup: $backup"
  echo "verify:"
  do_check
  return 0
}

case "$SUBCMD" in
  check)  do_check ;;
  apply)  do_apply ;;
  remove) do_remove ;;
  *)
    echo "setup-statusline: unknown subcommand '$SUBCMD' (expected check | apply | remove)"
    echo "usage: setup-statusline.sh <check|apply|remove> [--settings <path>] [--command <path>] [--replace]"
    ;;
esac
exit 0
