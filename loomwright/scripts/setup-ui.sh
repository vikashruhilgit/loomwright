#!/usr/bin/env bash
# setup-ui.sh — deterministic engine for the `/setup ui` module: install and serve The Floor,
# a local, read-only, loopback-only view of `.supervisor/floor/floor.json`.
#
# WHAT IT WRITES — and this is the whole list:
#   1. THE UI DIRECTORY, default `$HOME/.claude/loomwright/ui` and overridable with
#      `--ui-dir` (which is how every self-test runs inside a `mktemp -d`). Into it go exactly
#      the three bundle files copied from `<script dir>/floor-ui/`, the ownership marker
#      `.loomwright-ui-module`, an optional `serve.pid`, a COPY of `floor.json`, THE SERVED
#      INDEX `index.json`, and one `projects/<slug>/floor.json` per registered project.
#      `index.json` is written by `serve` alone and is the page's ONLY source for the project
#      picker, the module's own state and per-project freshness: the page is a reader, so
#      everything it can show has to be a file the static server can already hand it.
#   2. `.supervisor/floor/floor.json` UNDER THE CURRENT PROJECT ROOT, AND UNDER EACH REGISTERED
#      PROJECT ROOT that `serve` regenerates — and only ever by running `build-floor.sh` in
#      that directory, never by writing that path itself. `serve --no-regen` makes even that
#      write impossible. A project reaches this list only because a human ran `add`.
#   3. THE PROJECT REGISTRY — `projects.json` sitting BESIDE the ui directory (that is, in
#      its parent), overridable with `--registry`. Only `add`, `forget` and a CONFIRMED `scan`
#      write it; `check`, `list` and an unconfirmed `scan` only read it. Its being a SIBLING of
#      the ui directory rather than a file inside it is load-bearing, not incidental: `remove`
#      deletes the ui directory, and the list of the user's projects has to outlive that.
#      Registering a project writes NOTHING into the project itself, and `forget` is a registry
#      edit only — it never touches the directory it is forgetting.
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
# ONE SELECTED PROJECT PER TICK, AND THE REST ON A SLOWER CADENCE. This is a measured
# constraint, not a preference: one `build-floor.sh` run costs ~1 s on a repo of this size, and
# `serve`'s default interval is 2 s, so regenerating EVERY registered project on every tick
# starves the loop at TWO projects and leaves every project permanently stale. The loop
# therefore regenerates exactly ONE project per tick unconditionally — the SELECTED project,
# which is the one `serve` was launched inside — and at most one OTHER project every
# SLOW_FACTOR ticks, round-robin, so the per-tick cost is bounded at two projector runs no
# matter how many projects are registered. The page cannot change that selection and does not
# try to: it switches which already-regenerated project it DISPLAYS, and shows every project's
# own age, so a project on the slow cadence reads as exactly that instead of as a fresh floor.
#
# SUBCOMMANDS
#   check   read-only. Reports the ui dir, the marker, per-file bundle drift against the
#           plugin's copy, the availability of python3 / jq / build-floor.sh, and a readiness
#           verdict. Writes nothing.
#   apply   copy the three bundle files and write the marker. Byte-compares first: an apply
#           that would change nothing reports `apply: no-op — already configured`.
#   serve   regenerate `floor.json` on an interval (unless `--no-regen`), copy it into the ui
#           dir, and serve that directory on 127.0.0.1. Foreground by default. With projects
#           registered it also regenerates them on the SLOWER cadence below and writes the
#           served index every tick.
#   stop    kill the pids in `<ui dir>/serve.pid`, and ONLY if their command line names
#           `http.server` or `setup-ui.sh`.
#   remove  delete the ui directory, marker-gated (see above). The registry is NOT touched.
#   add     register a project (the current directory, or `add <path>`) in the registry.
#   list    print every registered project with its slug, path and last-regenerated age.
#   forget  drop one project from the registry BY SLUG. Deliberately not called `remove`: one
#           word meaning both "tear down the module" and "drop a project" is a data-loss shape.
#   scan    walk a directory for candidate projects and print them as a PROPOSAL. It writes
#           nothing until re-run with `--confirm`.
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
#   --registry <file> override the project registry (default: projects.json beside the ui
#                     directory). `--ui-dir` CANNOT redirect the registry - the registry is a
#                     sibling of the ui dir, not a file in it - so this is the only override,
#                     and it is what lets a test run without going near a real config tree
#   --confirm         `scan` only: actually register the candidates it proposed
#
# Portability: bash 3.2 / BSD userland safe. No GNU-only date/stat/sed flags, no associative
# arrays, no `timeout`.
#
# THE jq POSTURE, stated here because the registry is JSON and this paragraph used to say flatly
# that jq was not a dependency of this script. That is still true of everything the module did
# before the registry existed: `apply`, `stop`, `remove` and `check`'s module half all
# behave identically with jq absent. jq IS a dependency of the registry-touching paths -
# `add`, `list`, `forget`, `scan`, `check`'s registry section, and now `serve`'s multi-project
# half - and it is GUARDED rather than assumed: with jq unfindable each of them refuses to read
# or write, names jq as the reason, and exits 0 like every other branch in this file. `serve`
# is the newest member of that list and the cheapest to guard, because jq is ALREADY what
# `build-floor.sh` needs: without it no project can be regenerated at all, so a jq-less `serve`
# loses nothing it could otherwise have done. It still starts, still serves, and still writes a
# served index - one that says the registry is unreadable and names jq, rather than rendering a
# page with no projects on it and no reason why. Hand-rolling JSON with sed and awk
# was the alternative, and it was rejected: it would silently mangle a registry the user
# hand-edited, and a mangled registry is strictly worse than a named refusal. `python3 >= 3.7`
# is still required only by `serve`, and only there.

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

# The served index the page reads for its project picker, and the background cadence. Both are
# constants rather than flags: the page has no way to send anything back, so a knob here would
# be a second number the reader cannot see. SLOW_FACTOR is the number of TICKS between two
# background regenerations, and it is REPORTED by `serve` and carried in the served index, so a
# project that is deliberately refreshed rarely is explainable rather than merely old.
SERVED_INDEX="index.json"
SLOW_FACTOR=5

# HOME is read ONCE, defensively. `set -u` turns an unset HOME into an abort with a bash
# diagnostic and a non-zero status, which contradicts this file's own EVERY-BRANCH-EXITS-0
# contract - and an unset HOME is not exotic: cron, containers and `env -i` all produce one.
# Everything downstream uses HOME_DIR, so the guard cannot be bypassed by a later reader.
HOME_DIR="${HOME:-}"
# The user-scope loomwright directory is named ONCE. The ui directory and the registry are both
# derived from it, which is what makes their sibling relationship a fact of the code rather than
# a coincidence of two independently spelled paths.
LOOM_HOME=""
[ -n "$HOME_DIR" ] && LOOM_HOME="$HOME_DIR/.claude/loomwright"
DEFAULT_UI_DIR=""
DEFAULT_REGISTRY=""
[ -n "$LOOM_HOME" ] && DEFAULT_UI_DIR="$LOOM_HOME/ui"
[ -n "$LOOM_HOME" ] && DEFAULT_REGISTRY="$LOOM_HOME/projects.json"

UI_DIR="$DEFAULT_UI_DIR"
PORT=7734
INTERVAL=2
REGEN=1
DETACH=0
REGISTRY=""
CONFIRM=0
POSARG=""
# The scan's depth bound is a constant, not a flag: `scan` is a convenience over `add`, and an
# unbounded walk of a home directory is a very long pause with no output. It is STATED in the
# report so a candidate that was never reached is explainable rather than merely absent.
SCAN_MAX_DEPTH=3

SUBCMD="${1:-check}"
[ $# -gt 0 ] && shift

while [ $# -gt 0 ]; do
  case "$1" in
    --ui-dir)   shift; UI_DIR="${1:-}" ;;
    --port)     shift; PORT="${1:-}" ;;
    --interval) shift; INTERVAL="${1:-}" ;;
    --no-regen) REGEN=0 ;;
    --detach)   DETACH=1 ;;
    --registry) shift; REGISTRY="${1:-}" ;;
    --confirm)  CONFIRM=1 ;;
    # The FIRST non-flag argument is positional: a path for `add`/`scan`, a slug for `forget`.
    # Anything beginning with `-` stays an unknown FLAG and is still reported and ignored, so
    # a typo like `--uidir` cannot be silently swallowed as a project path.
    -*) echo "setup-ui: unknown argument '$1' (ignored)" >&2 ;;
    *)  if [ -z "$POSARG" ]; then POSARG="$1"; else echo "setup-ui: extra argument '$1' (ignored)" >&2; fi ;;
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
# The project registry
# ---------------------------------------------------------------------------
# EVERY function below is either read-only or funnels through reg_write, and every one of them
# returns rather than exits: the fail-safe contract at the top of this file is refuse-to-write
# plus a named reason, and a registry verb is not allowed to be the one branch that breaks it.

# registry_path -> the absolute path of the registry file on stdout, or nothing with rc 1 when
# there is no path to name at all (no --registry and no HOME). `--registry` WINS over the
# HOME-derived default, and that precedence is load-bearing for the self-tests: the registry is
# a SIBLING of the ui directory, so `--ui-dir` structurally cannot redirect it and a test that
# relied on `--ui-dir` alone would be writing the developer's own projects.json.
registry_path() {
  if [ -n "$REGISTRY" ]; then printf '%s' "$REGISTRY"; return 0; fi
  [ -n "$DEFAULT_REGISTRY" ] || return 1
  printf '%s' "$DEFAULT_REGISTRY"
  return 0
}

# registry_read <file> -> the registry JSON on stdout. Three distinct outcomes, because the
# caller must treat them differently and "empty output" cannot distinguish them:
#   rc 0  read, and it is an object carrying a `projects` ARRAY
#   rc 1  the file is not there at all - which is the NORMAL state before the first `add`
#   rc 2  the file is there but is not a registry this script will touch
# rc 2 covers both "not JSON" and "JSON of the wrong shape" on purpose: in both cases the only
# safe action is to refuse, because rewriting it would destroy whatever the user actually has.
registry_read() {
  local rp="$1"
  [ -f "$rp" ] || return 1
  jq -e 'type == "object" and ((.projects | type) == "array")' "$rp" >/dev/null 2>&1 || return 2
  cat "$rp"
}

# reg_write <json> -> writes REG_FILE atomically (temp file in the SAME directory, then mv, so
# a reader never sees a half-written registry). rc 1 on any failure, with nothing left behind.
reg_write() {
  local dir tmp
  dir="$(dirname "$REG_FILE")"
  [ -d "$dir" ] || mkdir -p "$dir" 2>/dev/null || return 1
  tmp="$REG_FILE.tmp.$$"
  printf '%s\n' "$1" > "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  mv "$tmp" "$REG_FILE" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  return 0
}

# project_slug <path> -> a short, stable, filesystem-agnostic handle for a project directory.
# Lowercased, everything outside [a-z0-9] folded to a single `-`, no leading or trailing `-`.
# A path whose basename folds away entirely still gets a name rather than an empty slug.
project_slug() {
  local p b s
  p="$(strip_slashes "$1")"
  b="$(basename "$p")"
  s="$(printf '%s' "$b" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C sed -e 's/[^a-z0-9]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//')"
  [ -n "$s" ] || s="project"
  printf '%s' "$s"
}

# uniq_slug <json> <base> -> <base>, or <base>-2, <base>-3 ... until it is free in <json>.
# Two projects with the same basename are ordinary (`~/work/api` and `~/play/api`), and a
# COLLIDING slug would make `forget <slug>` ambiguous, which is a data-loss shape.
uniq_slug() {
  local json="$1" base="$2" s n
  s="$base"; n=2
  while printf '%s' "$json" | jq -e --arg s "$s" 'any(.projects[]; .slug == $s)' >/dev/null 2>&1; do
    s="$base-$n"
    n=$((n + 1))
    [ "$n" -gt 999 ] && break
  done
  printf '%s' "$s"
}

# reg_prepare <verb> -> the single place where "there is no path to name", "jq is missing" and
# "this file is not a registry" are decided, so no verb can answer any of them differently.
# On success sets REG_FILE and REG_JSON (an EMPTY registry when the file does not exist yet).
REG_FILE=""
REG_JSON=""
reg_prepare() {
  local verb="$1" rp rc
  REG_FILE=""; REG_JSON=""
  if ! have jq; then
    echo "$verb: ABORTED — jq not found, and the project registry is JSON this script will not parse by hand (doing so would mangle a registry you had hand-edited). Install jq; check's module half, apply, serve, stop and remove do not need it. Nothing was read and nothing was written."
    return 1
  fi
  rp="$(registry_path)" || {
    echo "$verb: ABORTED — HOME is unset or empty and no --registry was given, so there is no registry file to name. Re-run with --registry <file>. Nothing was read and nothing was written."
    return 1
  }
  REG_FILE="$rp"
  REG_JSON="$(registry_read "$rp")"; rc=$?
  case "$rc" in
    0) return 0 ;;
    1) REG_JSON='{"version":1,"projects":[]}'; return 0 ;;
    *)
      echo "$verb: ABORTED — $rp is not valid JSON carrying a \"projects\" array, so this module will not touch it. It has NOT been modified; fix or delete it by hand. Nothing was written."
      return 1 ;;
  esac
}

# file_mtime <file> -> the epoch seconds of its last modification, or rc 1.
# GNU first, BSD second, and the result is VALIDATED NUMERIC before either is believed: BSD's
# `stat -f %m` is GNU's FILESYSTEM stat and succeeds with something that is not an mtime, which
# would then reach arithmetic and, under `set -u`, take the whole script with it.
file_mtime() {
  local m
  m="$(stat -c %Y "$1" 2>/dev/null)" || m=""
  case "$m" in ''|*[!0-9]*) m="$(stat -f %m "$1" 2>/dev/null)" || m="" ;; esac
  case "$m" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$m"
  return 0
}

# age_human <seconds> -> "42s ago" / "7m ago" / "3h ago" / "5d ago".
age_human() {
  local s="$1"
  case "$s" in ''|*[!0-9]*) printf 'unknown'; return 0 ;; esac
  if   [ "$s" -lt 60 ];    then printf '%ss ago' "$s"
  elif [ "$s" -lt 3600 ];  then printf '%sm ago' "$((s / 60))"
  elif [ "$s" -lt 86400 ]; then printf '%sh ago' "$((s / 3600))"
  else                          printf '%sd ago' "$((s / 86400))"
  fi
}

# project_freshness <project path> -> the human age of that project's own floor.json, or the
# reason there is not one. The registry never caches this: a cached age is a claim about a file
# the module does not own and cannot see change.
project_freshness() {
  local d="$1" m now
  if [ ! -d "$d" ]; then printf 'unavailable — the directory is not present'; return 0; fi
  if [ ! -f "$d/.supervisor/floor/floor.json" ]; then printf 'never regenerated (no .supervisor/floor/floor.json yet)'; return 0; fi
  m="$(file_mtime "$d/.supervisor/floor/floor.json")" || { printf 'age unknown (its timestamp could not be read)'; return 0; }
  now="$(date -u +%s 2>/dev/null)"
  case "$now" in ''|*[!0-9]*) printf 'age unknown (this system clock could not be read)'; return 0 ;; esac
  [ "$now" -ge "$m" ] || { printf 'age unknown (its timestamp is in the future)'; return 0; }
  age_human "$((now - m))"
  return 0
}

# registry_report — check's registry half. READ-ONLY, and every outcome is a report rather than
# an error: an absent registry is the normal state of a fresh install, not a fault.
registry_report() {
  local rp rc json n
  echo "== projects =="
  rp="$(registry_path)" || {
    echo "registry: none — HOME is unset or empty and no --registry was given, so there is no registry file to name."
    return 0
  }
  echo "registry: $rp"
  if ! have jq; then
    echo "registry state: UNREADABLE — jq not found, and the registry is JSON this script will not parse by hand. Install jq; nothing else in this module needs it."
    return 0
  fi
  json="$(registry_read "$rp")"; rc=$?
  if [ "$rc" -eq 1 ]; then
    echo "registry state: no projects registered (there is no file there yet — 'setup-ui.sh add' creates it)"
    return 0
  fi
  if [ "$rc" -ne 0 ]; then
    echo "registry state: UNREADABLE — that file is not valid JSON carrying a \"projects\" array. It has NOT been modified and nothing will be written to it until you fix or delete it."
    return 0
  fi
  n="$(printf '%s' "$json" | jq -r '.projects | length' 2>/dev/null)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  if [ "$n" -eq 0 ]; then
    echo "registry state: no projects registered (the file exists but lists none)"
  else
    echo "registry state: $n project(s) registered — 'setup-ui.sh list' prints them"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# add
# ---------------------------------------------------------------------------
do_add() {
  local target abs slug new existing
  target="$POSARG"
  [ -n "$target" ] || target="$(pwd)"
  if [ ! -d "$target" ]; then
    echo "add: ABORTED — $target is not an existing directory, so there is no project there to register. Nothing was written."
    return 0
  fi
  abs="$(cd -P "$target" 2>/dev/null && pwd -P)" || abs=""
  if [ -z "$abs" ]; then
    echo "add: ABORTED — $target could not be resolved to an absolute path. Nothing was written."
    return 0
  fi

  reg_prepare add || return 0

  existing="$(printf '%s' "$REG_JSON" | jq -r --arg p "$abs" '[.projects[] | select(.path == $p) | .slug] | first // ""' 2>/dev/null)"
  if [ -n "$existing" ]; then
    echo "add: no-op — $abs is already registered as '$existing'. Nothing was written."
    echo "  registry: $REG_FILE"
    return 0
  fi

  slug="$(uniq_slug "$REG_JSON" "$(project_slug "$abs")")"
  new="$(printf '%s' "$REG_JSON" | jq --arg p "$abs" --arg s "$slug" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" \
        '.version = 1 | .projects += [{slug: $s, path: $p, added: $t}]' 2>/dev/null)"
  if [ -z "$new" ]; then
    echo "add: ABORTED — the updated registry could not be produced. $REG_FILE has NOT been modified."
    return 0
  fi
  if ! reg_write "$new"; then
    echo "add: ABORTED — could not write $REG_FILE. It has NOT been modified."
    return 0
  fi
  echo "add: registered '$slug' — $abs"
  echo "  registry: $REG_FILE"
  echo "  nothing was written into the project itself; the registry is the only file this touched."
  return 0
}

# ---------------------------------------------------------------------------
# list
# ---------------------------------------------------------------------------
do_list() {
  local n
  reg_prepare list || return 0
  n="$(printf '%s' "$REG_JSON" | jq -r '.projects | length' 2>/dev/null)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  echo "registry: $REG_FILE"
  if [ "$n" -eq 0 ]; then
    echo "list: no projects registered — run 'setup-ui.sh add' from inside a project, or 'setup-ui.sh scan <dir>'."
    return 0
  fi
  echo "list: $n project(s) registered"
  # The loop body only PRINTS, so running it in a pipeline subshell costs nothing. Fields are
  # tab-separated by jq and split on tab alone, because a project path may contain spaces.
  printf '%s' "$REG_JSON" | jq -r '.projects[] | [.slug, .path] | @tsv' 2>/dev/null |
  while IFS="$(printf '\t')" read -r slug path; do
    [ -n "$slug" ] || continue
    printf '  %s\n' "$slug"
    printf '    path:              %s\n' "$path"
    printf '    last regenerated:  %s\n' "$(project_freshness "$path")"
  done
  return 0
}

# ---------------------------------------------------------------------------
# forget
# ---------------------------------------------------------------------------
do_forget() {
  local slug new gone
  slug="$POSARG"
  if [ -z "$slug" ]; then
    echo "forget: ABORTED — no slug given. Run 'setup-ui.sh list' to see the registered slugs. Nothing was written."
    return 0
  fi

  reg_prepare forget || return 0

  gone="$(printf '%s' "$REG_JSON" | jq -r --arg s "$slug" '[.projects[] | select(.slug == $s) | .path] | first // ""' 2>/dev/null)"
  if [ -z "$gone" ]; then
    echo "forget: no-op — '$slug' is not a registered project slug, so there was nothing to remove. Nothing was written."
    echo "  registry: $REG_FILE"
    return 0
  fi

  new="$(printf '%s' "$REG_JSON" | jq --arg s "$slug" '.projects |= map(select(.slug != $s))' 2>/dev/null)"
  if [ -z "$new" ]; then
    echo "forget: ABORTED — the updated registry could not be produced. $REG_FILE has NOT been modified."
    return 0
  fi
  if ! reg_write "$new"; then
    echo "forget: ABORTED — could not write $REG_FILE. It has NOT been modified."
    return 0
  fi
  echo "forget: removed '$slug' from the registry"
  echo "  the project directory itself was NOT touched: $gone is exactly as it was. This verb edits one JSON file and nothing else — 'remove' is the verb that deletes something."
  echo "  registry: $REG_FILE"
  return 0
}

# ---------------------------------------------------------------------------
# scan
# ---------------------------------------------------------------------------
# A candidate is a directory containing `.git`. The walk is bounded at SCAN_MAX_DEPTH levels
# below the scan root, and the bound is PRINTED: a project that was never reached has to be
# explainable, not merely missing from a list that looks complete.
do_scan() {
  local root abs g d slug proposed=0 already=0 lines="" new_json
  root="$POSARG"
  [ -n "$root" ] || root="$(pwd)"
  if [ ! -d "$root" ]; then
    echo "scan: ABORTED — $root is not an existing directory. Nothing was scanned and nothing was written."
    return 0
  fi
  abs="$(cd -P "$root" 2>/dev/null && pwd -P)" || abs=""
  if [ -z "$abs" ]; then
    echo "scan: ABORTED — $root could not be resolved to an absolute path. Nothing was written."
    return 0
  fi

  reg_prepare scan || return 0

  echo "scan: $abs (maximum depth $SCAN_MAX_DEPTH directory levels below the scan root)"
  new_json="$REG_JSON"
  # `find -maxdepth` first, before any other primary: GNU find warns when it comes later, and
  # the depth is +1 because the marker found is `<project>/.git`, one level below the project.
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    d="${g%/.git}"
    [ -n "$d" ] || continue
    if printf '%s' "$new_json" | jq -e --arg p "$d" 'any(.projects[]; .path == $p)' >/dev/null 2>&1; then
      already=$((already + 1))
      continue
    fi
    slug="$(uniq_slug "$new_json" "$(project_slug "$d")")"
    new_json="$(printf '%s' "$new_json" | jq --arg p "$d" --arg s "$slug" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" \
          '.version = 1 | .projects += [{slug: $s, path: $p, added: $t}]' 2>/dev/null)"
    if [ -z "$new_json" ]; then
      echo "scan: ABORTED — the proposed registry could not be produced. $REG_FILE has NOT been modified."
      return 0
    fi
    proposed=$((proposed + 1))
    lines="$lines
  $slug  $d"
  done < <(find "$abs" -maxdepth $((SCAN_MAX_DEPTH + 1)) -name .git 2>/dev/null | LC_ALL=C sort)

  if [ "$proposed" -eq 0 ]; then
    echo "scan: found no unregistered project here (a candidate is a directory containing .git). Nothing was written."
    [ "$already" -gt 0 ] && echo "  $already candidate(s) were skipped because they are already registered."
    return 0
  fi

  echo "scan: PROPOSAL — $proposed candidate(s):$lines"
  [ "$already" -gt 0 ] && echo "  ($already further candidate(s) skipped: already registered.)"
  if [ "$CONFIRM" -ne 1 ]; then
    echo "scan: nothing was written. Re-run the same command with --confirm to register the $proposed candidate(s) above."
    echo "  registry: $REG_FILE"
    return 0
  fi
  if ! reg_write "$new_json"; then
    echo "scan: ABORTED — could not write $REG_FILE. It has NOT been modified."
    return 0
  fi
  echo "scan: registered $proposed project(s) (--confirm was given)"
  echo "  registry: $REG_FILE"
  return 0
}

# ---------------------------------------------------------------------------
# check
# ---------------------------------------------------------------------------
# `check` is ONE report covering both halves of the module: the bundle/ui state and the
# registry state. They are separate functions only because the module half has several early
# returns, and a registry section that hung off one of them would silently disappear whenever
# the ui directory happened to be absent - which is precisely the fresh-install case.
do_check() {
  check_module
  echo
  registry_report
  return 0
}

check_module() {
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

# The two facts every function below needs and neither may guess: the directory `serve` was
# launched in (the SELECTED project, physically resolved) and its slug if it is registered.
# Declared here rather than inside do_serve because `set -u` makes an unset one an abort.
SERVE_CWD=""
SELECTED_SLUG=""
TAB="$(printf '\t')"

# THE REGISTRY AS `serve` SEES IT. Probed once per TICK rather than once per run, so a project
# added while the server is up appears without a restart — and so does a registry that was
# deleted or corrupted underneath it. Every outcome is a STATE with a reason, never an error:
# `serve` keeps serving whatever the registry is doing, because a page that goes blank because
# a file it does not own became unreadable is the failure this module exists to prevent.
REG_STATE="absent"
REG_REASON=""
REG_PATH=""
reg_probe() {
  local rp rc
  REG_STATE="absent"; REG_REASON=""; REG_PATH=""
  rp="$(registry_path)" || {
    REG_STATE="unnameable"
    REG_REASON="HOME is unset or empty and no --registry was given, so there is no registry file to name"
    return 0
  }
  REG_PATH="$rp"
  if ! have jq; then
    REG_STATE="unreadable"
    REG_REASON="jq not found, and the registry is JSON this script will not parse by hand"
    return 0
  fi
  registry_read "$rp" >/dev/null 2>&1; rc=$?
  case "$rc" in
    0) REG_STATE="ok" ;;
    1) REG_STATE="absent"; REG_REASON="there is no registry file at that path yet — 'setup-ui.sh add' creates it" ;;
    *) REG_STATE="unparseable"; REG_REASON="that file is there but is not valid JSON carrying a \"projects\" array; it has NOT been modified" ;;
  esac
  return 0
}

# reg_rows -> `<slug><TAB><path>` per registered project, and NOTHING for every registry state
# but `ok`. That emptiness is deliberately NOT how the page learns why: ABSENT and UNPARSEABLE
# are different claims about the user's registry and both produce no rows, so the distinction
# is carried by REG_STATE, which is exactly why these are two functions rather than one.
reg_rows() {
  [ "$REG_STATE" = "ok" ] || return 0
  jq -r '.projects[]
         | select((.slug | type) == "string" and (.path | type) == "string")
         | [.slug, .path] | @tsv' "$REG_PATH" 2>/dev/null
}

# selected_slug_for <absolute path> -> the slug the registry gives that exact path, or nothing.
# The SELECTED project is the one `serve` was launched inside, and it is decided HERE, in the
# engine, never by the page: the page is a reader and has no way to send anything back.
selected_slug_for() {
  [ "$REG_STATE" = "ok" ] || return 0
  jq -r --arg p "$1" '[.projects[] | select(.path == $p) | .slug] | first // ""' "$REG_PATH" 2>/dev/null
}

# regen_project <dir> <slug> [also_ui_root] — run the projector INSIDE <dir> and copy its
# artefact into that project's slot under the ui dir. The projector runs in a SUBSHELL that
# cds, so the loop's own working directory is never moved out from under it. Synchronous, like
# the single-project path it generalises: overlapping regenerations cannot occur, so no reader
# ever sees a half-written document. The non-zero returns are DISTINCT because the page renders
# the reason, and "it did not happen" is not one:
#   1 the registered directory is not present (moved or deleted, possibly under a live serve)
#   2 the projector produced no artefact there (jq missing, or it declined)
#   3 the copy into the ui dir failed
#   4 there is no projector to run
regen_project() {
  local dir="$1" slug="$2" root_too="${3:-0}" src dest
  [ -n "$dir" ] || return 1
  [ -d "$dir" ] || return 1
  [ -f "$FLOOR_SCRIPT" ] || return 4
  ( cd "$dir" 2>/dev/null && bash "$FLOOR_SCRIPT" >/dev/null 2>&1 )
  src="$dir/.supervisor/floor/floor.json"
  [ -f "$src" ] || return 2
  if [ -n "$slug" ]; then
    dest="$UI_DIR/projects/$slug"
    [ -d "$dest" ] || mkdir -p "$dest" 2>/dev/null || return 3
    cp "$src" "$dest/floor.json.tmp" 2>/dev/null || return 3
    mv "$dest/floor.json.tmp" "$dest/floor.json" 2>/dev/null || return 3
  fi
  if [ "$root_too" = "1" ]; then
    cp "$src" "$UI_DIR/floor.json.tmp" 2>/dev/null || return 3
    mv "$UI_DIR/floor.json.tmp" "$UI_DIR/floor.json" 2>/dev/null || return 3
  fi
  return 0
}

# regen_once — the single-project path, unchanged in behaviour and now one call of the general
# one: regenerate the project `serve` was launched in, copy the artefact to the ui dir root and
# also into its own slot when it is registered. The root copy stays because it is what a page
# with no served index reads — an older bundle, or a directory holding nothing but a floor.json.
regen_once() {
  regen_project "$SERVE_CWD" "$SELECTED_SLUG" 1
  return 0
}

# project_state <dir> <slug> -> PS_STATE / PS_REASON / PS_EPOCH for one registered project,
# decided by looking at the filesystem on every write. Four distinct renders, because they are
# four different claims and collapsing any two of them would put a guess on the page:
#   unavailable        the registered directory is not there. The entry is REPORTED and kept,
#                      never dropped — a project silently missing from the picker is
#                      indistinguishable from one that was never added.
#   never-regenerated  the directory is there but this serve has produced no floor for it yet.
#   unreadable         a slot document exists but its timestamp could not be read, so no age
#                      can be claimed for it.
#   ready              a slot document exists and its generation time is recorded beside it.
PS_STATE=""
PS_REASON=""
PS_EPOCH=""
project_state() {
  local dir="$1" slug="$2" slot m
  PS_STATE=""; PS_REASON=""; PS_EPOCH=""
  if [ ! -d "$dir" ]; then
    PS_STATE="unavailable"
    PS_REASON="the registered directory is not present at that path — it was moved or deleted; nothing has been removed from the registry, so 'forget' is still yours to run"
    return 0
  fi
  slot="$UI_DIR/projects/$slug/floor.json"
  if [ ! -f "$slot" ]; then
    PS_STATE="never-regenerated"
    PS_REASON="this serve has not produced a floor for this project yet; projects other than the selected one are regenerated one at a time on the slower cadence"
    return 0
  fi
  m="$(file_mtime "$slot")" || {
    PS_STATE="unreadable"
    PS_REASON="a floor document is present for this project but its timestamp could not be read, so its age cannot be stated"
    return 0
  }
  PS_STATE="ready"
  PS_EPOCH="$m"
  return 0
}

# write_served_index — the ui dir's `index.json`: the module's own state, the registry's state
# and one row per registered project. It is the page's ONLY source for all three, and it is a
# plain file in the directory already being served, so the picker adds no request the static
# server cannot answer and no write path of any kind. Written atomically (temp file in the same
# directory, then mv) so a poll landing mid-write reads the previous document rather than half
# of this one.
write_served_index() {
  local now dest tmp rows line slug path obj bundle f missing="" marker regen selreg
  [ -d "$UI_DIR" ] || return 1
  now="$(date -u +%s 2>/dev/null)"
  case "$now" in ''|*[!0-9]*) now=0 ;; esac
  for f in $BUNDLE_FILES; do [ -f "$UI_DIR/$f" ] || missing="$missing $f"; done
  bundle="present"; [ -n "$missing" ] && bundle="incomplete"
  marker=false; is_ours && marker=true
  regen=false; [ "$REGEN" -eq 1 ] && regen=true
  dest="$UI_DIR/$SERVED_INDEX"
  tmp="$dest.tmp.$$"

  if ! have jq; then
    # No jq means no registry read AND no projector, so the only honest document is one that
    # says so. It interpolates nothing but integers and fixed words — which is what makes it
    # safe to write with no JSON encoder, since the encoder is the thing that is missing.
    printf '{"schema_version":1,"generated_at_epoch":%s,"module":{"bundle":"%s","marker":%s},"serve":{"interval_seconds":%s,"slow_cadence_ticks":%s,"regen":%s},"registry":{"state":"unreadable","reason":"jq not found, and the registry is JSON this script will not parse by hand. The project list and every project path are omitted rather than guessed, and nothing can be regenerated either: build-floor.sh needs jq too."},"projects":[]}\n' \
      "$now" "$bundle" "$marker" "$INTERVAL" "$SLOW_FACTOR" "$regen" > "$tmp" 2>/dev/null \
      || { rm -f "$tmp" 2>/dev/null; return 1; }
    mv "$tmp" "$dest" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
    return 0
  fi

  rows=""
  while IFS="$TAB" read -r slug path; do
    [ -n "$slug" ] || continue
    project_state "$path" "$slug"
    # Every optional field is OMITTED rather than defaulted, the same rule build-floor.sh
    # follows: a `last_regenerated_epoch: 0` would render as a date in 1970 on the page.
    obj="$(jq -n -c --arg slug "$slug" --arg path "$path" --arg state "$PS_STATE" \
             --arg reason "$PS_REASON" --arg epoch "$PS_EPOCH" --arg sel "$SELECTED_SLUG" \
             '{slug: $slug, path: $path, state: $state, selected: ($sel != "" and $slug == $sel)}
              + (if $reason == "" then {} else {reason: $reason} end)
              + (if $epoch  == "" then {} else {last_regenerated_epoch: ($epoch | tonumber)} end)' 2>/dev/null)"
    [ -n "$obj" ] || continue
    rows="$rows$obj
"
  done <<EOF
$(reg_rows)
EOF

  selreg=false; [ -n "$SELECTED_SLUG" ] && selreg=true
  printf '%s' "$rows" | jq -s -c \
      --argjson gen "$now" \
      --arg bundle "$bundle" \
      --argjson marker "$marker" \
      --arg uidir "$UI_DIR" \
      --argjson interval "$INTERVAL" \
      --argjson slow "$SLOW_FACTOR" \
      --argjson regen "$regen" \
      --argjson selreg "$selreg" \
      --arg selslug "$SELECTED_SLUG" \
      --arg selpath "$SERVE_CWD" \
      --arg regstate "$REG_STATE" \
      --arg regreason "$REG_REASON" \
      --arg regpath "$REG_PATH" \
      '{schema_version: 1,
        generated_at_epoch: $gen,
        module: {ui_dir: $uidir, bundle: $bundle, marker: $marker},
        serve: ({interval_seconds: $interval, slow_cadence_ticks: $slow, regen: $regen,
                 selected_path: $selpath, selected_registered: $selreg}
                + (if $selslug == "" then {} else {selected_slug: $selslug} end)),
        registry: ({state: $regstate}
                + (if $regreason == "" then {} else {reason: $regreason} end)
                + (if $regpath   == "" then {} else {path: $regpath} end)),
        projects: .}' > "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  [ -s "$tmp" ] || { rm -f "$tmp" 2>/dev/null; return 1; }
  mv "$tmp" "$dest" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  return 0
}

# serve_tick — ONE iteration of the loop, extracted so the cost of a tick is one function
# rather than a shape spread through a `while`. Its whole contract is the bound: the selected
# project ALWAYS, at most one other project every SLOW_FACTOR ticks, and the index. Two
# projector runs per tick at the very most, whatever the registry holds.
serve_tick() {
  local tick="$1" others n_others line o_slug o_path
  reg_probe
  SELECTED_SLUG="$(selected_slug_for "$SERVE_CWD")"
  [ "$REGEN" -eq 1 ] && regen_once
  if [ "$REGEN" -eq 1 ] && [ $((tick % SLOW_FACTOR)) -eq 0 ]; then
    others="$(reg_rows | awk -F"$TAB" -v sel="$SELECTED_SLUG" 'NF && $1 != sel')"
    n_others="$(printf '%s\n' "$others" | awk 'NF{n++} END{print n+0}')"
    case "$n_others" in ''|*[!0-9]*) n_others=0 ;; esac
    if [ "$n_others" -gt 0 ]; then
      BG_CURSOR=$((BG_CURSOR % n_others))
      line="$(printf '%s\n' "$others" | awk -v k="$((BG_CURSOR + 1))" 'NF{n++} n==k{print; exit}')"
      o_slug="${line%%"$TAB"*}"
      o_path="${line#*"$TAB"}"
      [ -n "$o_slug" ] && [ -n "$o_path" ] && regen_project "$o_path" "$o_slug"
      BG_CURSOR=$((BG_CURSOR + 1))
    fi
  fi
  write_served_index
  return 0
}
BG_CURSOR=0

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

  # The two facts the whole multi-project half is built on, resolved ONCE here and refreshed on
  # every tick: which directory this serve was launched in, and whether the registry knows it.
  SERVE_CWD="$(pwd -P 2>/dev/null)" || SERVE_CWD=""
  [ -n "$SERVE_CWD" ] || SERVE_CWD="$(pwd)"
  reg_probe
  SELECTED_SLUG="$(selected_slug_for "$SERVE_CWD")"

  [ "$REGEN" -eq 1 ] && regen_once
  # Written before the listener starts, and written whether or not regeneration is on, so the
  # very first page load has the module's state, the registry's state and the project list
  # rather than an empty picker it would have to explain away.
  write_served_index

  echo "serve: 127.0.0.1:$PORT — loopback only, this listener is not reachable from any other host"
  echo "  ui dir:   $UI_DIR"
  if [ "$REGEN" -eq 1 ]; then
    echo "  regen:    build-floor.sh every ${INTERVAL}s from $(pwd)"
  else
    echo "  regen:    disabled (--no-regen); serving the floor.json already in the ui dir"
  fi

  # THE PROJECT LINE, and it states the cadence rather than only the count. A reader who can
  # see that the others refresh every N seconds can tell a slow project from a broken one,
  # which is the whole distinction the page is built to preserve.
  local n_reg
  n_reg="$(reg_rows | awk 'NF{n++} END{print n+0}')"
  case "$REG_STATE" in
    ok)
      if [ "$n_reg" -eq 0 ]; then
        echo "  projects: none registered — this serve shows only $SERVE_CWD. Run 'setup-ui.sh add' inside a project to put it in the picker."
      else
        echo "  projects: $n_reg registered ($REG_PATH)"
        if [ -n "$SELECTED_SLUG" ]; then
          echo "            selected '$SELECTED_SLUG' regenerates every ${INTERVAL}s; the others one at a time every $((INTERVAL * SLOW_FACTOR))s"
        else
          echo "            $SERVE_CWD is NOT registered, so it is the selected project by virtue of being where this ran; it regenerates every ${INTERVAL}s and the registered projects one at a time every $((INTERVAL * SLOW_FACTOR))s"
        fi
        echo "            one projector run costs about a second, so regenerating every project on every tick would starve this loop — that is why the others are slower, not an oversight"
      fi ;;
    *)
      echo "  projects: registry $REG_STATE — $REG_REASON. This serve shows only $SERVE_CWD; the page says which of the two it is."
      ;;
  esac

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
    ( tick=0
      while kill -0 "$srv" 2>/dev/null; do
        sleep "$INTERVAL"
        tick=$((tick + 1))
        serve_tick "$tick"
      done ) >/dev/null 2>&1 &
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
  add)    do_add ;;
  list)   do_list ;;
  forget) do_forget ;;
  scan)   do_scan ;;
  *)
    echo "setup-ui: unknown subcommand '$SUBCMD' (expected check | apply | serve | stop | remove | add | list | forget | scan)"
    echo "usage: setup-ui.sh <check|apply|serve|stop|remove|add|list|forget|scan> [--ui-dir <dir>] [--registry <file>] [--port <n>] [--interval <n>] [--no-regen] [--detach] [--confirm]"
    ;;
esac
exit 0
