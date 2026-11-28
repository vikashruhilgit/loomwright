# --help usage (the `#:  ` lines): this family's segment of automate-helpers.sh --help, assembled
# by the dispatcher's _ah_usage in _AH_HELP_SEGMENTS order; fixture: fixtures/automate-helpers-help/meta.golden.
#:  meta-entry       [--root <checkout>]                # §"Branch mode": the FIRST action of every /automate entry (a bare/empty/option-shaped --root value ⇒ `failed`) — reads `setup-memory.sh mode` itself (no caller input can assert the mode) and, when on, runs `meta-sync.sh pull`; ONE line `meta-entry: off|pulled <branch>|failed — <reason>`; writes nothing itself; the meta-sync pull it runs may update managed .supervisor/automate/ files; always exits 0
#:  meta-push-failed <runfile>                          # §"Branch mode": read-only — prints the first line of this run's gitignored `<run_id>.meta-push-failed` marker (a failed mode-on trail push), or nothing; always exits 0
#:  meta-publish     --paths-from <file> [--root <checkout>]  # §"Branch mode": publish-on-write for /product-owner and /orchestrator — reads `setup-memory.sh mode` itself; mode on and not an /automate lane ⇒ refuses a path that is not a `.supervisor/requirements/*.md` run-history path of `meta-sync.sh list-managed --run-history`, scrubs, then `meta-sync.sh push --paths-from` (exactly the listed paths, never a whole set); ONE `meta-publish: skipped|refused|blocked|pushed|no_changes|FAILED …` line first, then any scrub-hit lines; never undoes a write; always exits 0

# --------------------------------------------------------------------------- #
# §"Branch mode" — meta-entry (pull BEFORE the first read) + meta-push-failed + meta-publish
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
# It writes nothing itself; the meta-sync pull it runs may update the managed .supervisor/automate/
# run-history files it syncs. The SKILL maps `failed` to ABORT (no run file targeted) or a
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

# meta-publish --paths-from <file> [--root <checkout>] — publish-on-write for the planning agents
# (/product-owner, /orchestrator): push EXACTLY the paths listed in <file> (one repo-relative path
# per line; blank and `#` lines ignored, as meta-sync reads it) to the metadata branch. Callers
# pass --root "$(git rev-parse --show-toplevel)": without it the root is _meta_root's (the PRIMARY
# checkout), which in a linked worktree is not where the agent wrote. ALWAYS exit 0 — a publish
# never undoes a write; the files stay in the checkout whatever the verdict. The verdict set (this
# comment is its one home; callers quote the printed line, never re-list it):
#   - meta-publish: skipped — branch mode off: requirement files stay in this checkout
#   - meta-publish: skipped — branch mode unknown (<reason>)
#   - meta-publish: skipped — /automate lane: published at wave end (lane-convert-ready / lane-remove --abandon)
#   - meta-publish: refused — not a requirement file: <path>[; <path>…]   (nothing pushed; `(missing)` marks a listed path absent here)
#   - meta-publish: refused — --paths-from <file> lists no path
#   - meta-publish: blocked — scrub hit (nothing pushed; files kept locally)   then meta-sync's scrub lines
#   - meta-publish: pushed <branch> <sha> (<n> path(s))
#   - meta-publish: no_changes <branch>
#   - meta-publish: FAILED — <reason>; retry: bash <meta-sync.sh> push --branch <b> --paths-from <file> --root <checkout>   (each value shell-quoted, printf %q)
#   - meta-publish: FAILED — <misinvocation>   (a missing/option-shaped --root or --paths-from value)
# Order: mode (setup-memory.sh mode — the one reader), lane check (automate-lanes.sh lane-info exit
# 0 ⇒ skip: a lane publishes at wave end), scope check — every listed path must be a planning
# file, `.supervisor/requirements/*.md` (any depth), AND in `meta-sync.sh list-managed --run-history`
# (meta-sync itself would skip a non-managed path SILENTLY; the scope keeps run files, job briefs
# and the learning stores off this route — trail-pr's evidence gate and the consent-gated
# whole-set push own those), scrub dry run, then the push.
# LOOMWRIGHT_META_SYNC_BIN (the dispatcher's TEST SEAM) selects the meta-sync script for all three.
meta_publish() {
  local root="" pf="" here mode branch ms out rc reason managed p bad="" n=0 sha cnt
  while [ $# -gt 0 ]; do
    case "$1" in
      --root|--paths-from)
        case "${2:-}" in
          ""|-*) echo "meta-publish: FAILED — $1 requires a value (got '${2:-}')"; return 0 ;;
        esac
        if [ "$1" = --root ]; then root="$2"; else pf="$2"; fi
        shift 2 ;;
      *) shift ;;
    esac
  done
  [ -n "$pf" ] || { echo "meta-publish: FAILED — --paths-from <file> is required"; return 0; }
  [ -f "$pf" ] || { echo "meta-publish: FAILED — --paths-from '$pf' is not a file"; return 0; }
  here="$(cd "$(dirname "$0")" && pwd)"
  root="$(_meta_root "$root")"
  mode="$(bash "$here/setup-memory.sh" --root "$root" mode 2>/dev/null | head -n1 || true)"
  case "$mode" in
    off) echo "meta-publish: skipped — branch mode off: requirement files stay in this checkout"; return 0 ;;
    "on "?*) branch="${mode#on }" ;;
    "unknown "*) echo "meta-publish: skipped — branch mode unknown (${mode#unknown })"; return 0 ;;
    *) echo "meta-publish: skipped — branch mode unknown (setup-memory.sh mode printed '${mode}')"; return 0 ;;
  esac
  if bash "$here/automate-lanes.sh" lane-info --root "$root" >/dev/null 2>&1; then echo "meta-publish: skipped — /automate lane: published at wave end (lane-convert-ready / lane-remove --abandon)"; return 0; fi
  ms="${LOOMWRIGHT_META_SYNC_BIN:-$here/meta-sync.sh}"
  rc=0
  managed="$(bash "$ms" list-managed --run-history --root "$root" 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ]; then
    reason="$(printf '%s\n' "$managed" | sed -n 's/^meta_sync: //p' | awk 'NF { printf "%s%s", (n++ ? "; " : ""), $0 }')"
    echo "meta-publish: FAILED — list-managed: ${reason:-meta-sync.sh list-managed exited $rc} (nothing pushed)"
    return 0
  fi
  while IFS= read -r p || [ -n "$p" ]; do
    case "$p" in ""|"#"*) continue ;; esac
    n=$((n + 1))
    case "$p" in
      .supervisor/requirements/*.md) grep -qxF -- "$p" <<<"$managed" && continue ;;
    esac
    bad="${bad:+$bad; }$p$([ -e "$root/$p" ] || echo ' (missing)')"
  done < "$pf"
  [ "$n" -gt 0 ] || { echo "meta-publish: refused — --paths-from $pf lists no path"; return 0; }
  [ -z "$bad" ] || { echo "meta-publish: refused — not a requirement file: $bad"; return 0; }
  rc=0
  out="$(bash "$ms" scrub --paths-from "$pf" --root "$root" 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ]; then
    if [ "$rc" -eq 2 ]; then
      echo "meta-publish: blocked — scrub hit (nothing pushed; files kept locally)"
      printf '%s\n' "$out" | grep '^meta_sync: scrub-hit ' || true
    else
      reason="$(printf '%s\n' "$out" | sed -n 's/^meta_sync: //p' | awk 'NF { printf "%s%s", (n++ ? "; " : ""), $0 }')"
      echo "meta-publish: FAILED — scrub: ${reason:-meta-sync.sh scrub exited $rc} (nothing pushed)"
    fi
    return 0  # scrub refused: never reach the push
  fi
  rc=0
  out="$(bash "$ms" push --branch "$branch" --paths-from "$pf" --root "$root" --message "chore(supervisor): publish planning file(s) on write" 2>&1)" || rc=$?
  if [ "$rc" -eq 0 ]; then
    case "$out" in *"meta_sync: no_changes"*) echo "meta-publish: no_changes $branch"; return 0 ;; esac
    sha="$(printf '%s\n' "$out" | sed -n 's/^meta_sync: pushed \([0-9a-f]*\) (\([0-9]*\) path(s))$/\1/p' | head -n1 || true)"
    cnt="$(printf '%s\n' "$out" | sed -n 's/^meta_sync: pushed \([0-9a-f]*\) (\([0-9]*\) path(s))$/\2/p' | head -n1 || true)"
    echo "meta-publish: pushed $branch ${sha:-unknown} (${cnt:-$n} path(s))"
    return 0
  fi
  if [ "$rc" -eq 2 ]; then
    echo "meta-publish: blocked — scrub hit (nothing pushed; files kept locally)"
    printf '%s\n' "$out" | grep '^meta_sync: scrub' || true
    return 0
  fi
  reason="$(printf '%s\n' "$out" | sed -n 's/^meta_sync: //p' | awk 'NF { printf "%s%s", (n++ ? "; " : ""), $0 }')"
  [ -n "$reason" ] || reason="meta-sync.sh push exited $rc"
  echo "meta-publish: FAILED — $reason; retry: $(printf 'bash %q push --branch %q --paths-from %q --root %q' "$ms" "$branch" "$pf" "$root")"
  return 0  # push failed: named above, the write stands
}

