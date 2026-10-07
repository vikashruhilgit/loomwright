# --------------------------------------------------------------------------- #
# §"Branch mode" — meta-entry (pull BEFORE the first read) + meta-push-failed
# --------------------------------------------------------------------------- #

# _meta_root [<root>] — the checkout meta-sync.sh resolves: the given root, else the FIRST
# `git worktree list --porcelain` entry (the primary checkout), else $PWD. Mirrors meta-sync.sh's
# own "resolve root" block so the mode is read from the same .gitignore meta-sync syncs.
_meta_root() {
  local r="${1:-}" top
  if [ -z "$r" ]; then
    r="$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
    if [ -n "$r" ] && [ -d "$r" ]; then
      top="$(git -C "$r" rev-parse --path-format=absolute --show-toplevel 2>/dev/null || true)"
      [ "$top" = "$r" ] || r=""
    fi
    [ -n "$r" ] || r="$PWD"
  fi
  printf '%s\n' "$r"
}

# meta-entry [--root <checkout>] — ONE verdict line, ALWAYS exit 0:
#   meta-entry: off                              mode off — proceed exactly as today, no network
#   meta-entry: pulled <branch>                  mode on, `meta-sync.sh pull --branch <branch>` exited 0
#   meta-entry: failed — <reason>                mode on, pull exited non-zero (meta-sync's own text:
#                                                no_remote_branch / conflict <path> / fetch_failed …)
#   meta-entry: failed — mode unknown (<reason>) `setup-memory.sh mode` said unknown
# It creates and writes NOTHING under .supervisor/automate/ (meta-sync's pull writes only the
# managed run-history files it syncs). The SKILL maps `failed` to ABORT (no run file targeted) or a
# `meta_unreachable` park (an existing local run file targeted by --resume <id>).
meta_entry() {
  local root="" here mode branch out rc reason ms
  while [ $# -gt 0 ]; do
    case "$1" in
      --root)
        # A missing, empty or option-shaped value is a misinvocation, never "use the default root":
        # `--root --x` would otherwise read the mode of a non-existent checkout as `off` and skip
        # the pull silently. Fail-safe like every other path here: one `failed` line, exit 0.
        case "${2:-}" in
          ""|-*) echo "meta-entry: failed — --root requires a checkout path (got '${2:-}')"; return 0 ;;
        esac
        root="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  here="$(cd "$(dirname "$0")" && pwd)"
  root="$(_meta_root "$root")"
  mode="$(bash "$here/setup-memory.sh" --root "$root" mode 2>/dev/null | head -n1 || true)"
  case "$mode" in
    off) echo "meta-entry: off"; return 0 ;;
    "on "?*) branch="${mode#on }" ;;
    "unknown "*) echo "meta-entry: failed — mode unknown (${mode#unknown })"; return 0 ;;
    *) echo "meta-entry: failed — mode unknown (setup-memory.sh mode printed '${mode}')"; return 0 ;;
  esac
  ms="${LOOMWRIGHT_META_SYNC_BIN:-$here/meta-sync.sh}"
  rc=0
  out="$(bash "$ms" pull --branch "$branch" --root "$root" 2>&1)" || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "meta-entry: pulled $branch"
    return 0
  fi
  # meta-sync's own lines (conflict <path> / no_remote_branch / fetch_failed …), joined.
  reason="$(printf '%s\n' "$out" | sed -n 's/^meta_sync: //p' | awk 'NF { printf "%s%s", (n++ ? "; " : ""), $0 }')"
  [ -n "$reason" ] || reason="meta-sync.sh pull exited $rc"
  echo "meta-entry: failed — $reason"
  return 0
}

# meta-push-failed <runfile> — read-only. Prints the first line (UTC timestamp + reason) of this
# run's gitignored `<run_id>.meta-push-failed` marker, written by a failed mode-on trail-pr push
# and removed by the next successful one; prints nothing when absent. ALWAYS exit 0.
meta_push_failed() {
  local rf="${1:-}" m
  [ -n "$rf" ] || return 0
  # An option-shaped <runfile> is a misinvocation (dirname/basename would read it as a flag).
  case "$rf" in -*) return 0 ;; esac
  m="$(dirname "$rf")/$(basename "$rf" .md).meta-push-failed"
  [ -f "$m" ] || return 0
  head -n1 "$m" 2>/dev/null || true
  return 0
}

