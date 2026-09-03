#!/usr/bin/env bash
# setup-ui.sh — deterministic engine for the `/setup ui` module: install and serve The Floor,
# a local, read-only, loopback-only view of `.supervisor/floor/floor.json`.
#
# WHAT IT WRITES — and this is the whole list:
#   1. THE UI DIRECTORY, default `$HOME/.claude/loomwright/ui` and overridable with
#      `--ui-dir` (which is how every self-test runs inside a `mktemp -d`). Into it go exactly
#      the three bundle files copied from `<script dir>/floor-ui/`, the ownership marker
#      `.loomwright-ui-module`, an optional `serve.pid`, and a COPY of `floor.json`.
#   2. `.supervisor/floor/floor.json` UNDER THE CURRENT PROJECT ROOT — and only ever by
#      running `build-floor.sh`, never by writing that path itself. `serve --no-regen` makes
#      even that write impossible.
#   Nothing else, anywhere. It never writes the user-scope settings file (that is the
#   statusline module's one write domain and this module has no business in it), and it never
#   runs a history-touching git command — no add, no commit, no checkout, no stash.
#
# THE MARKER IS THE OWNERSHIP PROOF, AND `remove` NEEDS IT.
#   `apply` writes `.loomwright-ui-module` into the ui directory; `remove` deletes the
#   directory ONLY when that marker is present AND the path it is about to delete is the
#   resolved ui directory itself. A directory without the marker is REPORTED and PRESERVED,
#   because `--ui-dir` is user-supplied and a typo pointing at a real directory must not cost
#   the user that directory. `remove` additionally refuses `/`, `$HOME`, and anything at or
#   under the plugin's own install directory — each compared against the PHYSICAL path
#   (`cd -P` / `pwd -P`), because bash's logical pwd hands back the path you typed and those
#   three refusals would then never see a target reached through a symlinked parent. A
#   `--ui-dir` that is ITSELF a symlink is refused outright: unlinking it would leave every
#   byte of the target in place under a report saying it was removed.
#
# FAIL-SAFE CONTRACT (mirrors setup-statusline.sh and setup-memory.sh): EVERY branch exits 0.
# "Fails closed" here means REFUSE-TO-WRITE plus a named-reason headline status line — never a
# non-zero exit, which would regress every non-blocking caller. A missing `python3`, a missing
# `build-floor.sh`, a busy port and an unowned directory all ABORT or WITHHOLD, and all exit 0.
#
# LOOPBACK ONLY. `serve` always passes `--bind 127.0.0.1` to `python3 -m http.server`. There is
# no flag to change that and no code path that omits it. `floor.json` carries branch names,
# session ids and agent ids: it is local-only by construction, so the bind address is the whole
# security posture and it is not negotiable at the command line.
#
# SUBCOMMANDS
#   check   read-only. Reports the ui dir, the marker, per-file bundle drift against the
#           plugin's copy, the availability of python3 / jq / build-floor.sh, and a readiness
#           verdict. Writes nothing.
#   apply   copy the three bundle files and write the marker. Byte-compares first: an apply
#           that would change nothing reports `apply: no-op — already configured`.
#   serve   regenerate `floor.json` on an interval (unless `--no-regen`), copy it into the ui
#           dir, and serve that directory on 127.0.0.1. Foreground by default.
#   stop    kill the pids in `<ui dir>/serve.pid`, and ONLY if their command line names
#           `http.server` or `setup-ui.sh`.
#   remove  delete the ui directory, marker-gated (see above).
#
# FLAGS
#   --ui-dir <dir>    override the ui directory (default $HOME/.claude/loomwright/ui)
#   --port <n>        listen port for `serve` (default 7734); a busy port is REPORTED, never
#                     silently changed — a moved port is a page that loads stale bytes
#   --interval <n>    seconds between regenerations (default 2, minimum 1). The page cannot
#                     see this flag - it judges freshness against 3x its own fixed 2 s poll -
#                     so `serve` prints the `?stale=` URL to open whenever this outgrows it
#   --no-regen        serve whatever `floor.json` is already in the ui dir; run nothing
#   --detach          `serve` returns immediately and records its pids in <ui dir>/serve.pid
#
# Portability: bash 3.2 / BSD userland safe. No GNU-only date/stat/sed flags, no associative
# arrays, no `timeout`. `jq` is NOT a dependency of this script (only of build-floor.sh, which
# guards it itself); `python3 >= 3.7` is required only by `serve`, and only there.

set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
BUNDLE_DIR="$script_dir/floor-ui"
FLOOR_SCRIPT="$script_dir/build-floor.sh"
MARKER=".loomwright-ui-module"
BUNDLE_FILES="index.html floor.css floor.js"

# The page's OWN clock, mirrored here so `serve` can tell the reader when its `--interval`
# has outgrown it. These two are floor.js's POLL_MS/1000 and its 3x default; they are not
# configurable from this script and this script cannot change them - it can only report the
# `?stale=` value that keeps the page from calling a current document stale.
PAGE_POLL_SEC=2
PAGE_STALE_DEFAULT=6

# HOME is read ONCE, defensively. `set -u` turns an unset HOME into an abort with a bash
# diagnostic and a non-zero status, which contradicts this file's own EVERY-BRANCH-EXITS-0
# contract - and an unset HOME is not exotic: cron, containers and `env -i` all produce one.
# Everything downstream uses HOME_DIR, so the guard cannot be bypassed by a later reader.
HOME_DIR="${HOME:-}"
DEFAULT_UI_DIR=""
[ -n "$HOME_DIR" ] && DEFAULT_UI_DIR="$HOME_DIR/.claude/loomwright/ui"

UI_DIR="$DEFAULT_UI_DIR"
PORT=7734
INTERVAL=2
REGEN=1
DETACH=0

SUBCMD="${1:-check}"
[ $# -gt 0 ] && shift

while [ $# -gt 0 ]; do
  case "$1" in
    --ui-dir)   shift; UI_DIR="${1:-}" ;;
    --port)     shift; PORT="${1:-}" ;;
    --interval) shift; INTERVAL="${1:-}" ;;
    --no-regen) REGEN=0 ;;
    --detach)   DETACH=1 ;;
    *) echo "setup-ui: unknown argument '$1' (ignored)" >&2 ;;
  esac
  shift
done

# Numeric hygiene BEFORE anything uses these in arithmetic or hands them to python3. A
# non-numeric --port would otherwise reach the server as an argv string and fail there, well
# after the user has been told the port is fine.
case "$PORT" in ''|*[!0-9]*) echo "setup-ui: --port must be a positive integer; falling back to 7734"; PORT=7734 ;; esac
case "$INTERVAL" in ''|*[!0-9]*) echo "setup-ui: --interval must be a positive integer; falling back to 2"; INTERVAL=2 ;; esac
[ "$INTERVAL" -lt 1 ] && INTERVAL=1

[ -n "$UI_DIR" ] || UI_DIR="$DEFAULT_UI_DIR"

# No HOME and no --ui-dir means there is no directory to name, let alone read or write. Say
# so by name and exit 0 - the fail-safe contract is refuse-to-write plus a named reason.
if [ -z "$UI_DIR" ]; then
  echo "setup-ui: ABORTED — HOME is unset or empty and no --ui-dir was given, so there is no ui directory to check, install into, serve or remove. Re-run with --ui-dir <dir>. Nothing was read and nothing was written."
  exit 0
fi

# ---------------------------------------------------------------------------
# Probes (all read-only)
# ---------------------------------------------------------------------------

have() { command -v "$1" >/dev/null 2>&1; }

csum() {
  if   have sha256sum; then sha256sum "$1" 2>/dev/null | cut -d' ' -f1
  elif have shasum;    then shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
  else cksum "$1" 2>/dev/null | cut -d' ' -f1; fi
}

# drifted_files -> the names of bundle files whose installed copy differs from the plugin's,
# INCLUDING files that are missing from the ui dir. Empty output means "already configured".
drifted_files() {
  local f out=""
  for f in $BUNDLE_FILES; do
    if [ ! -f "$BUNDLE_DIR/$f" ]; then out="$out $f(source-missing)"; continue; fi
    if [ ! -f "$UI_DIR/$f" ]; then out="$out $f"; continue; fi
    cmp -s "$BUNDLE_DIR/$f" "$UI_DIR/$f" || out="$out $f"
  done
  printf '%s' "${out# }"
}

is_ours() { [ -f "$UI_DIR/$MARKER" ]; }

# resolved_ui_dir -> the absolute PHYSICAL path, or empty when the directory does not exist.
# `remove` compares against this so a relative --ui-dir cannot make the deletion target
# ambiguous. `cd -P` + `pwd -P`, never bash's logical pwd: the logical form hands back the
# path you typed with its symlinks intact, so a --ui-dir reached through a symlinked parent
# resolves to the LINK path and the `/`, $HOME and plugin-install-dir refusals below compare
# against something that is not the directory about to be deleted. Those three refusals exist
# to protect the real target, so they have to be given the real target.
resolved_ui_dir() {
  [ -d "$UI_DIR" ] || return 1
  ( cd -P "$UI_DIR" 2>/dev/null && pwd -P )
}

# strip_slashes -> the path with trailing slashes removed, because `[ -L "$p/" ]` FOLLOWS the
# link and answers false: a symlink test on a path with a trailing slash tests the target.
strip_slashes() {
  local p="$1"
  while [ "$p" != "/" ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
  printf '%s' "$p"
}

port_free() {
  have python3 || return 0
  python3 - "$1" <<'PY' >/dev/null 2>&1
import socket, sys
p = int(sys.argv[1])
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    s.bind(("127.0.0.1", p))
except OSError:
    sys.exit(1)
finally:
    s.close()
PY
}

# ---------------------------------------------------------------------------
# check
# ---------------------------------------------------------------------------
do_check() {
  echo "== ui =="
  echo "ui dir:  $UI_DIR"
  echo "bundle:  $BUNDLE_DIR"

  local missing="" f
  for f in $BUNDLE_FILES; do
    [ -f "$BUNDLE_DIR/$f" ] || missing="$missing $f"
  done
  if [ -n "$missing" ]; then
    echo "plugin bundle: INCOMPLETE —$missing missing from $BUNDLE_DIR"
  else
    echo "plugin bundle: present (3 files)"
  fi

  if have python3; then echo "python3: present"; else echo "python3: MISSING (serve would abort)"; fi
  if have jq;      then echo "jq: present"; else echo "jq: MISSING (build-floor.sh skips, so floor.json will not regenerate)"; fi
  if [ -f "$FLOOR_SCRIPT" ]; then echo "build-floor.sh: present"; else echo "build-floor.sh: MISSING at $FLOOR_SCRIPT (serve would abort unless --no-regen)"; fi

  if [ ! -d "$UI_DIR" ]; then
    echo "installed: absent"
    echo "UI readiness: not configured"
    return 0
  fi
  if ! is_ours; then
    echo "installed: a directory exists at $UI_DIR but carries no $MARKER marker"
    echo "UI readiness: WITHHELD (this module did not create that directory; apply and remove will refuse it)"
    return 0
  fi

  local drift
  drift="$(drifted_files)"
  if [ -n "$drift" ]; then
    echo "installed: marker present, bundle DRIFTED — $drift"
    echo "UI readiness: stale (run apply)"
  else
    echo "installed: marker present, bundle matches the plugin byte for byte"
    if [ -f "$UI_DIR/floor.json" ]; then
      echo "floor.json: present in the ui dir"
    else
      echo "floor.json: not yet copied into the ui dir (serve copies it)"
    fi
    echo "UI readiness: configured"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# apply
# ---------------------------------------------------------------------------
do_apply() {
  local f missing="" drift first=0

  for f in $BUNDLE_FILES; do
    [ -f "$BUNDLE_DIR/$f" ] || missing="$missing $f"
  done
  if [ -n "$missing" ]; then
    echo "apply: ABORTED — the plugin bundle is incomplete ($missing missing from $BUNDLE_DIR). Nothing was written."
    return 0
  fi

  if [ -d "$UI_DIR" ] && ! is_ours; then
    echo "apply: WITHHELD — $UI_DIR exists but carries no $MARKER marker, so this module did not create it. Nothing was written."
    echo "  If you want the UI there, remove or rename that directory yourself first."
    return 0
  fi

  if [ ! -d "$UI_DIR" ]; then
    first=1
    mkdir -p "$UI_DIR" 2>/dev/null || {
      echo "apply: ABORTED — could not create $UI_DIR. Nothing was written."
      return 0
    }
  fi

  drift="$(drifted_files)"
  if [ -z "$drift" ] && is_ours; then
    echo "apply: no-op — already configured"
    echo "  ui dir: $UI_DIR"
    return 0
  fi

  local wrote=""
  for f in $drift; do
    cp "$BUNDLE_DIR/$f" "$UI_DIR/$f" 2>/dev/null && wrote="$wrote $f" || {
      echo "apply: ABORTED — could not write $UI_DIR/$f. Partial state: written so far:$wrote"
      return 0
    }
  done

  if [ ! -f "$UI_DIR/$MARKER" ]; then
    printf 'loomwright ui module. Deleting this file makes `setup-ui.sh remove` refuse to delete this directory.\n' \
      > "$UI_DIR/$MARKER" 2>/dev/null || {
      echo "apply: ABORTED — the files were copied but the $MARKER marker could not be written, so remove would refuse to clean up. Write it yourself or delete $UI_DIR by hand."
      return 0
    }
  fi

  if [ "$first" -eq 1 ]; then
    echo "apply: installed —$wrote"
  else
    echo "apply: updated —$wrote"
  fi
  echo "  ui dir: $UI_DIR"
  return 0
}

# ---------------------------------------------------------------------------
# serve
# ---------------------------------------------------------------------------

# regen_once — run build-floor.sh in the CURRENT project root, then copy its artefact into the
# ui dir. Synchronous on purpose: overlapping regenerations cannot occur, so the ui dir never
# holds a half-written document.
regen_once() {
  [ -f "$FLOOR_SCRIPT" ] || return 0
  bash "$FLOOR_SCRIPT" >/dev/null 2>&1
  [ -f ".supervisor/floor/floor.json" ] || return 0
  cp ".supervisor/floor/floor.json" "$UI_DIR/floor.json.tmp" 2>/dev/null || return 0
  mv "$UI_DIR/floor.json.tmp" "$UI_DIR/floor.json" 2>/dev/null || return 0
  return 0
}

do_serve() {
  if ! have python3; then
    echo "serve: ABORTED — python3 not found"
    echo "  The Floor is served by python3's own http.server; there is no bundled server and no other dependency to fall back to."
    return 0
  fi

  if [ ! -d "$UI_DIR" ]; then
    echo "serve: ABORTED — $UI_DIR does not exist. Run 'setup-ui.sh apply' first. Nothing was started."
    return 0
  fi
  if [ ! -f "$UI_DIR/index.html" ]; then
    echo "serve: note — no index.html in $UI_DIR; the directory will be served as-is (run apply to install the bundle)."
  fi

  if [ "$REGEN" -eq 1 ]; then
    if [ ! -f "$FLOOR_SCRIPT" ]; then
      echo "serve: ABORTED — build-floor.sh not found at $FLOOR_SCRIPT, so floor.json cannot be regenerated. Re-run with --no-regen to serve the copy already in the ui dir. Nothing was started."
      return 0
    fi
    if ! have jq; then
      echo "serve: note — jq not found, so build-floor.sh will skip and floor.json will NOT be regenerated. The page will render whatever copy is already in the ui dir, and will say how stale it is."
    fi
  fi

  if ! port_free "$PORT"; then
    echo "serve: ABORTED — port $PORT is already in use. Re-run with --port <n>; this module never moves the port for you, because a silently moved port is a browser tab reading bytes from something else. Nothing was started."
    return 0
  fi

  [ "$REGEN" -eq 1 ] && regen_once

  echo "serve: 127.0.0.1:$PORT — loopback only, this listener is not reachable from any other host"
  echo "  ui dir:   $UI_DIR"
  if [ "$REGEN" -eq 1 ]; then
    echo "  regen:    build-floor.sh every ${INTERVAL}s from $(pwd)"
  else
    echo "  regen:    disabled (--no-regen); serving the floor.json already in the ui dir"
  fi

  # THE PAGE CANNOT SEE --interval. floor.js judges freshness against 3x its OWN fixed 2 s
  # poll, so any interval above that page default makes every render older than the threshold
  # and the page would report a document that is being regenerated exactly as configured as
  # stale. The page states only what it measured (the age and the threshold) and never a
  # cause; the missing half is this number, and only `serve` knows it - so `serve` prints it.
  # The URL is printed on ONE line so it can be copied whole.
  local stale_hint
  stale_hint=$((INTERVAL * 3))
  if [ "$stale_hint" -gt "$PAGE_STALE_DEFAULT" ]; then
    echo "  open:     http://127.0.0.1:$PORT/?stale=$stale_hint"
    echo "            (--interval ${INTERVAL}s regenerates less often than the page's built-in ${PAGE_STALE_DEFAULT}s freshness threshold, which is 3x its own ${PAGE_POLL_SEC}s poll and cannot see this flag; without ?stale=$stale_hint the page would call a perfectly current file stale)"
  else
    echo "  open:     http://127.0.0.1:$PORT/"
  fi

  python3 -m http.server --bind 127.0.0.1 --directory "$UI_DIR" "$PORT" >/dev/null 2>&1 &
  local srv=$!
  printf '%s\n' "$srv" > "$UI_DIR/serve.pid" 2>/dev/null

  local loop=""
  if [ "$REGEN" -eq 1 ]; then
    ( while kill -0 "$srv" 2>/dev/null; do sleep "$INTERVAL"; regen_once; done ) >/dev/null 2>&1 &
    loop=$!
    printf '%s\n' "$loop" >> "$UI_DIR/serve.pid" 2>/dev/null
  fi

  if [ "$DETACH" -eq 1 ]; then
    echo "  detached: pids recorded in $UI_DIR/serve.pid — stop it with 'setup-ui.sh stop --ui-dir $UI_DIR'"
    return 0
  fi

  # shellcheck disable=SC2064
  trap "kill $srv $loop 2>/dev/null; rm -f '$UI_DIR/serve.pid' 2>/dev/null" EXIT INT TERM
  echo "  foreground: Ctrl-C to stop"
  wait "$srv" 2>/dev/null
  return 0
}

# ---------------------------------------------------------------------------
# stop
# ---------------------------------------------------------------------------
do_stop() {
  local pf="$UI_DIR/serve.pid" pid cmd killed=0 refused=""
  if [ ! -f "$pf" ]; then
    echo "stop: no-op — no $pf, so this module has no recorded server to stop."
    return 0
  fi
  while IFS= read -r pid; do
    case "$pid" in ''|*[!0-9]*) continue ;; esac
    cmd="$(ps -o command= -p "$pid" 2>/dev/null || true)"
    if [ -z "$cmd" ]; then
      refused="$refused $pid(gone)"
      continue
    fi
    # Kill ONLY a process whose command line names one of ours. A pidfile can outlive its
    # process and the pid can be recycled onto something the user cares about.
    case "$cmd" in
      *http.server*|*setup-ui.sh*) kill "$pid" 2>/dev/null && killed=$((killed + 1)) ;;
      *) refused="$refused $pid(not-ours)" ;;
    esac
  done < "$pf"
  rm -f "$pf" 2>/dev/null
  echo "stop: $killed process(es) stopped"
  [ -n "$refused" ] && echo "  not killed:$refused (the pidfile named them but their command line is not this module's)"
  return 0
}

# ---------------------------------------------------------------------------
# remove
# ---------------------------------------------------------------------------
do_remove() {
  if [ ! -d "$UI_DIR" ]; then
    echo "remove: no-op — $UI_DIR is not present."
    return 0
  fi
  # A --ui-dir that is ITSELF a symlink is refused outright. Deleting it would unlink the
  # link and leave every byte of the target - the bundle, the marker and the floor.json copy,
  # which carry branch names, session ids and agent ids - sitting on disk underneath a report
  # saying they are gone. A false "removed" is worse than a refusal, so this refuses.
  local ui_path
  ui_path="$(strip_slashes "$UI_DIR")"
  if [ -L "$ui_path" ]; then
    echo "remove: ABORTED — $ui_path is a symlink, not a directory this module created. Deleting it would unlink the link and leave the real directory it points at fully intact, so 'removed' would not be true. Nothing was deleted."
    echo "  Re-run with --ui-dir pointing at the real directory if that is what you meant to remove."
    return 0
  fi
  if ! is_ours; then
    echo "remove: WITHHELD — $UI_DIR carries no $MARKER marker, so this module did not create it. It has been PRESERVED and nothing was deleted."
    return 0
  fi

  local resolved
  resolved="$(resolved_ui_dir)" || {
    echo "remove: ABORTED — could not resolve $UI_DIR to an absolute path. Nothing was deleted."
    return 0
  }

  # Three assertions, all of which must hold before anything is deleted. Each compares the
  # PHYSICAL path from resolved_ui_dir against a physically resolved candidate, because a
  # refusal that compares two spellings of the same directory is not a refusal at all.
  local home_phys="" script_phys=""
  [ -n "$HOME_DIR" ] && [ -d "$HOME_DIR" ] && home_phys="$(cd -P "$HOME_DIR" 2>/dev/null && pwd -P)"
  script_phys="$(cd -P "$script_dir" 2>/dev/null && pwd -P)"
  # Written as separate `if`s on purpose: `[ A ] || [ B ] && [ C ]` groups as (A||B)&&C in
  # every POSIX shell, which would have quietly let `/` through whenever HOME was set.
  if [ "$resolved" = "/" ]; then
    echo "remove: ABORTED — the resolved ui dir is $resolved, which this module will never delete. Nothing was deleted."
    return 0
  fi
  if [ -n "$HOME_DIR" ] && [ "$resolved" = "$HOME_DIR" ]; then
    echo "remove: ABORTED — the resolved ui dir is $resolved, which this module will never delete. Nothing was deleted."
    return 0
  fi
  if [ -n "$home_phys" ] && [ "$resolved" = "$home_phys" ]; then
    echo "remove: ABORTED — the resolved ui dir is $resolved, which is the home directory ($HOME_DIR) reached through a symlink. Nothing was deleted."
    return 0
  fi
  case "$resolved" in
    "$script_dir"|"$script_dir"/*)
      echo "remove: ABORTED — the resolved ui dir is inside the plugin install directory ($script_dir). Nothing was deleted."
      return 0 ;;
  esac
  if [ -n "$script_phys" ]; then
    case "$resolved" in
      "$script_phys"|"$script_phys"/*)
        echo "remove: ABORTED — the resolved ui dir is inside the plugin install directory ($script_phys). Nothing was deleted."
        return 0 ;;
    esac
  fi
  if [ ! -f "$resolved/$MARKER" ]; then
    echo "remove: ABORTED — the marker is not present at the RESOLVED path $resolved. Nothing was deleted."
    return 0
  fi

  do_stop >/dev/null 2>&1

  rm -r -- "$resolved" 2>/dev/null
  if [ -d "$resolved" ]; then
    echo "remove: ABORTED — $resolved is still present after the delete; check its permissions. It has been left alone."
    return 0
  fi
  echo "remove: removed — $resolved is gone (bundle, marker, pidfile and the floor.json copy)"
  echo "  the plugin's own bundle at $BUNDLE_DIR is untouched, and so is .supervisor/floor/floor.json"
  return 0
}

case "$SUBCMD" in
  check)  do_check ;;
  apply)  do_apply ;;
  serve)  do_serve ;;
  stop)   do_stop ;;
  remove) do_remove ;;
  *)
    echo "setup-ui: unknown subcommand '$SUBCMD' (expected check | apply | serve | stop | remove)"
    echo "usage: setup-ui.sh <check|apply|serve|stop|remove> [--ui-dir <dir>] [--port <n>] [--interval <n>] [--no-regen] [--detach]"
    ;;
esac
exit 0
