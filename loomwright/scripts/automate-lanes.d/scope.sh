# automate-lanes.d/scope.sh — sourced by automate-lanes.sh (see its header). SCOPE: the files a brief plans
# outside its item's `## Touches`, read deterministically so no model computes the set difference
# (lane-scope-regate Part A). Reuses readiness.sh's declared-set readers — _lanes_declared (the Touches read:
# `plan-waves --touches`, companions included), _lanes_brief_paths (the brief grammar) and _lanes_is_declared
# (the matcher wave-build's overlap check and the scope fence use) — and copies none of them.
#
# scope-outside <item> <brief> [--root <dir>] — READ-ONLY. <item> is the requirement file (repo-relative, or
# absolute under the root); <brief> any readable brief file (Launch Pad passes its scratch brief). The root
# is --root, else `git rev-parse --show-toplevel`, else $PWD. The brief's paths are its Subtask Contracts
# `path:` and `lanes:` lines; `changelog.d/` paths are exempt, as the scope fence exempts them. Prints ONE
# first line, exit 0:
#   inside           every brief path is inside Touches (a brief naming no path included)
#   unknown          Touches reads `unknown …` (declared unknown, missing, unparsable): the item runs alone, so
#                    no widening is asked about; no list follows
#   outside <n>      then the <n> brief paths outside Touches, one per line, sorted
#   unreadable <n>   `plan-waves --touches` failed (a missing item, malformed companions): then EVERY brief
#                    path, one per line — fail CLOSED, never read as `inside`
# Exit 1 with one `automate-lanes: scope-outside: …` stderr line, nothing on stdout: usage, an unreadable
# brief, a root that is not a directory, no temp dir.
lanes_scope_outside() {
  local item="" brief="" root="" a tmp n f
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root) [ "$#" -ge 2 ] || die "scope-outside: --root needs a value"; root="$2"; shift 2 ;;
      -*) die "scope-outside: unknown option $1 (usage: scope-outside <item> <brief> [--root <dir>])" ;;
      *) if [ -z "$item" ]; then item="$1"; elif [ -z "$brief" ]; then brief="$1"
         else die "scope-outside: unexpected argument $1 (usage: scope-outside <item> <brief> [--root <dir>])"; fi
         shift ;;
    esac
  done
  { [ -n "$item" ] && [ -n "$brief" ]; } || die "scope-outside: usage: scope-outside <item> <brief> [--root <dir>]"
  { [ -f "$brief" ] && [ -r "$brief" ]; } || die "scope-outside: brief unreadable: $brief"
  [ -n "$root" ] || root="$(git rev-parse --show-toplevel 2>/dev/null)" || root=""
  [ -n "$root" ] || root="$PWD"
  root="$(cd "$root" 2>/dev/null && pwd -P)" || die "scope-outside: root is not a directory"
  case "$item" in
    /*) a="$(cd "$(dirname "$item")" 2>/dev/null && pwd -P)" && item="$a/$(basename "$item")"
        item="${item#"$root"/}" ;;   # still absolute (outside the root) ⇒ plan-waves fails ⇒ `unreadable`
  esac
  tmp="$(mktemp -d 2>/dev/null)" || die "scope-outside: no temp dir"
  _lanes_declared "$root" "$item" "" "$tmp/touches"   # no brief: the Touches set alone
  _lanes_brief_paths "$brief" 2>/dev/null | awk '!/^changelog\.d\//' | env LC_ALL=C sort -u > "$tmp/brief"
  if [ "$LD_TOUCHES_READ" = failed ]; then
    n="$(grep -c . "$tmp/brief")"; echo "unreadable ${n:-0}"; cat "$tmp/brief"
  elif [ "$LD_TOUCHES" = unknown ]; then
    echo unknown
  else
    : > "$tmp/out"
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      _lanes_is_declared "$f" "$tmp/touches" || printf '%s\n' "$f" >> "$tmp/out"
    done < "$tmp/brief"
    n="$(grep -c . "$tmp/out")"
    if [ "${n:-0}" -eq 0 ]; then echo inside; else echo "outside $n"; cat "$tmp/out"; fi
  fi
  rm -rf "$tmp"
}
