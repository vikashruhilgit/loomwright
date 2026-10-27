# --------------------------------------------------------------------------- #
# sweep (SKILL §1.5 — af/39a: squash-safe sweep of plugin leftovers)
# --------------------------------------------------------------------------- #
# sweep [--apply] [--root <checkout>] — reports (dry run, the default: NOTHING is
# written, removed or salvaged) and, ONLY with `--apply`, removes exactly the
# plugin-made linked worktrees and local branches that are provably done under
# CLOSEOUT'S OWN squash-safe rule — no new heuristic: the branch's NEWEST PR
# (`gh pr list --state all --head <B> --json number,state,headRefOid,mergedAt`,
# highest number) is MERGED AND the local tip equals that PR's headRefOid. Squash
# merges hide a merged branch from ancestry, so ancestry is never consulted.
#
# <checkout> (default $PWD) resolves to its PRIMARY checkout (the parent of
# `git rev-parse --git-common-dir`). WORKTREES are judged first, then BRANCHES, so a
# branch checked out in a worktree removed (dry run: that would be removed) this
# run is a candidate in the same run — the dry run reports what --apply would do.
#
# Worktree origin (`git worktree list --porcelain`, never the primary):
#   <primary>/$SW_APP_WT/**          app    — reported only; the app removes them
#   <primary>-lanes/**               lane   — `kept lane <path> — use lane-remove`
#   a `created` path in <primary>/.supervisor/logs/worktrees.log (worktree-audit.sh),
#   or a `<parent>/<project>-<suffix>` sibling of the primary
#                                    worktree — removable under the rule below
#   anything else                    other  — `kept other <path> — origin unknown`
# A plugin-made worktree is removed (`git worktree remove`, NEVER --force, never
# rm -rf) only when ALL hold: not locked/prunable, a branch (detached ⇒ kept: no
# branch to prove) that passes the rule with the WORKTREE's HEAD as the tip, clean
# (`git status --porcelain` empty — checked before the salvage so a dirty tree is
# kept without piling salvage copies, and again after it), every gitignored entry is
# salvaged or regenerable (`worktree-salvage.sh --check-ignored`, read-only, so the
# dry run reports it too: anything else ⇒ `kept worktree <p> — unsalvaged ignored
# content: <entry>`), no live process has its cwd there (`lsof -a -d cwd`, prefix
# match; lsof absent or failing, or a path holding a byte lsof escapes ⇒ kept,
# liveness unverifiable — never a kill), and `worktree-salvage.sh --ignored` printed
# `ignored: ok <n>` as its last line (anything else, or no line ⇒ kept naming it).
#
# Branches (refs/heads/*): the primary's current branch, the base branch
# (resolve-base-branch.sh — unresolved ⇒ nothing is examined and the ONE line is
# `sweep: summary — skipped: base_branch_unresolved`) and a branch checked out
# in any worktree NOT removed this run are never candidates (each a `kept branch` line, no gh call). The rest:
# no PR / newest OPEN / CLOSED unmerged / tip moved after the merge / gh read
# failed ⇒ `kept branch <B> — <that case>`; the rule ⇒ `would-remove` (dry) or
# `git branch -D` ⇒ `removed`.
#
# Output: one `sweep: would-remove|removed|kept <kind> <path-or-branch> — <reason>`
# line per candidate, then exactly ONE `sweep: summary — …` line, last. Always
# exit 0 (fail-SAFE emitter; every read failure fails toward KEEPING). Cost: one
# gh call per examined branch (memoised per run in SW_PR_CACHE, so a removable
# worktree's branch is not re-read in the branch phase) — dry runs only at run end
# (finalize-empty).
SW_APPLY=0
SW_ACT=0
SW_KEPT=0
SW_LIVE_STATE=""
SW_LIVE=""
# The desktop app's own worktree root under the primary — a host-specific path,
# named ONCE here (vendor-coupling ratchet); worktrees below it are the app's.
SW_APP_WT=".claude/worktrees"

# _sw_line <act|kept> <kind> <subject> <reason> — one candidate line + the tally.
_sw_line() {
  local verb=kept
  if [ "$1" = act ]; then
    if [ "$SW_APPLY" -eq 1 ]; then verb=removed; else verb=would-remove; fi
    SW_ACT=$((SW_ACT + 1))
  else
    SW_KEPT=$((SW_KEPT + 1))
  fi
  printf 'sweep: %s %s %s — %s\n' "$verb" "$2" "$3" "$4"
}

# _sw_rule <branch> <tip> — closeout's squash-safe rule. Sets SW_RULE (pass|fail)
# and SW_WHY (the reason text). Every read failure is a `fail` naming the case.
# The gh read is memoised per branch in SW_PR_CACHE (`<branch>\t<newest>` lines —
# GATE_CACHE's idiom; a read failure is cached as `!rc <n>` / `!unparseable`), so a
# removable worktree's branch, judged again in the branch phase, costs no second
# read; the rule itself is re-applied to each caller's own tip. sweep_run resets the
# cache, so nothing carries across runs or --roots.
SW_PR_CACHE=""
_sw_rule() {
  local b="$1" tip="$2" js rc newest num="" state="" oid="" tab=$'\t'
  SW_RULE=fail
  newest="$(printf '%s' "$SW_PR_CACHE" | SW_BR="$b" awk 'BEGIN { FS = "\t"; b = ENVIRON["SW_BR"] } $1 == b { print $2; exit }')"
  if [ -z "$newest" ]; then
    js="$(cd "$SW_PRI" 2>/dev/null && "$GH" pr list --state all --head "$b" --json number,state,headRefOid,mergedAt 2>/dev/null)"; rc=$?
    if [ "$rc" -ne 0 ]; then newest="!rc $rc"
    else
      newest="$(printf '%s' "$js" | "$JQ" -r 'if type != "array" then error("not an array")
          elif length == 0 then "none"
          else (max_by(.number) | "\(.number)\u001f\(.state)\u001f\(.headRefOid // "")") end' 2>/dev/null)" || newest=""
      [ -n "$newest" ] || newest="!unparseable"
    fi
    SW_PR_CACHE="$SW_PR_CACHE$b$tab$newest"$'\n'
  fi
  case "$newest" in
    "!rc "*) SW_WHY="gh read failed (pr list --head, rc ${newest#!rc })"; return 0 ;;
    "!unparseable") SW_WHY="gh read failed (unparseable pr list)"; return 0 ;;
    none) SW_WHY="no PR for this branch"; return 0 ;;
  esac
  IFS=$'\037' read -r num state oid <<SWREC
$newest
SWREC
  case "$state" in
    MERGED) ;;
    OPEN) SW_WHY="newest PR #$num is OPEN"; return 0 ;;
    CLOSED) SW_WHY="newest PR #$num is CLOSED unmerged"; return 0 ;;
    *) SW_WHY="newest PR #$num state ${state:-unknown}"; return 0 ;;
  esac
  if [ -z "$oid" ] || [ -z "$tip" ]; then SW_WHY="PR #$num merged but headRefOid/tip unreadable"; return 0; fi
  if [ "$tip" != "$oid" ]; then SW_WHY="tip ${tip:0:12} moved after merge (PR #$num merged head ${oid:0:12})"; return 0; fi
  SW_RULE=pass
  SW_WHY="PR #$num MERGED, tip == merged head ${oid:0:12}"
  return 0
}

# _sw_live_read — reads every process's cwd ONCE per sweep, lazily (only a
# removable candidate needs it), in the CURRENT shell so the cache survives.
# lsof absent, failing or printing nothing ⇒ SW_LIVE_STATE=fail (liveness
# unverifiable ⇒ every candidate is kept).
_sw_live_read() {
  [ -z "$SW_LIVE_STATE" ] || return 0
  SW_LIVE_STATE=fail
  if command -v "$LSOF" >/dev/null 2>&1; then
    SW_LIVE="$("$LSOF" -a -d cwd -F pn 2>/dev/null)" && [ -n "$SW_LIVE" ] && SW_LIVE_STATE=ok
  fi
  return 0
}

# _sw_live <path> [<canonical path>] — prints the pid of a live process whose cwd
# is <path> or below; returns 0 live, 1 not live, 2 unverifiable (lsof), 3
# unverifiable (the path). Call _sw_live_read first (this usually runs in a
# command substitution).
#
# Return 3 — FAIL CLOSED on a path lsof cannot print verbatim: lsof escapes every
# byte it deems unprintable in its `n` lines — under a C/POSIX locale (no LANG: the
# Bash tool's default and many hook contexts) every byte >= 0x80, so `proj-café`
# reads `proj-caf\xc3\xa9` — and a backslash is ambiguous with those escapes. Such a
# path could never equal (or prefix) its n-line, so a live process would read "not
# live" and `--apply` would remove the worktree under it. A path of printable ASCII
# other than `\` is printed verbatim in every locale, so its compare is exact.
_sw_live() {
  local s pid
  for s in "$1" "${2:-$1}"; do
    [ "$(printf '%s' "$s" | env LC_ALL=C tr -d '\040-\133\135-\176' | wc -c | tr -d ' ')" = 0 ] || return 3
  done
  [ "$SW_LIVE_STATE" = ok ] || return 2
  pid="$(printf '%s\n' "$SW_LIVE" | SW_A="$1" SW_B="${2:-$1}" awk '
    BEGIN { a = ENVIRON["SW_A"]; b = ENVIRON["SW_B"] }
    /^p/ { pid = substr($0, 2); next }
    /^n/ { n = substr($0, 2)
           if (n == a || n == b || index(n, a "/") == 1 || index(n, b "/") == 1) { print pid; exit } }')"
  [ -n "$pid" ] || return 1
  printf '%s' "$pid"
  return 0
}

# _sw_plugin_made <path> <canonical> — recorded as `created` in worktree-audit.sh's
# log, or a `<parent>/<project>-<suffix>` sibling of the primary.
_sw_plugin_made() {
  local log="$SW_PRI/.supervisor/logs/worktrees.log" hit
  if [ -r "$log" ]; then
    hit="$("$JQ" -n -R -r --arg a "$1" --arg b "$2" \
      'any(inputs | fromjson? | select(type == "object" and .event == "created" and (.path | type) == "string"); .path == $a or .path == $b)' \
      < "$log" 2>/dev/null)"
    [ "$hit" = true ] && return 0
  fi
  [ "$(dirname "$2")" = "$(dirname "$SW_PRI")" ] || return 1
  case "$(basename "$2")" in "$(basename "$SW_PRI")"-?*) return 0 ;; esac
  return 1
}

sweep_run() {
  local root="" bad=""
  SW_APPLY=0; SW_ACT=0; SW_KEPT=0; SW_LIVE_STATE=""; SW_LIVE=""; SW_PR_CACHE=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --apply) SW_APPLY=1; shift ;;
      --root)
        if [ "$#" -ge 2 ] && [ -n "$2" ]; then root="$2"; shift 2
        else [ -n "$bad" ] || bad="--root (no value)"; shift
        fi ;;
      *) [ -n "$bad" ] || bad="$1"; shift ;;
    esac
  done
  local S="sweep: summary — skipped:"
  if [ -n "$bad" ]; then echo "$S unknown argument $bad (nothing examined)"; return 0; fi
  if ! command -v git >/dev/null 2>&1; then echo "$S git unavailable"; return 0; fi
  [ -n "$root" ] || root="$PWD"
  local common
  common="$(git -C "$root" rev-parse --git-common-dir 2>/dev/null)"
  if [ -z "$common" ]; then echo "$S not a git checkout ($root)"; return 0; fi
  SW_PRI="$(cd "$root" 2>/dev/null && cd "$common/.." 2>/dev/null && pwd -P)"
  if [ -z "$SW_PRI" ] || [ ! -d "$SW_PRI" ]; then echo "$S cannot resolve the primary checkout"; return 0; fi

  # The base comes from the ONE resolver (resolve-base-branch.sh), resolved in the primary. Unresolved
  # or invalid ⇒ nothing is examined (the base branch must never be a candidate, and it is unknown):
  # the summary line names the status token, exit 0.
  local base cur
  if ! base="$(bash "$HERE/resolve-base-branch.sh" --repo "$SW_PRI" 2>&1 </dev/null)"; then
    echo "$S ${base%%$'\n'*}"; return 0
  fi
  cur="$(git -C "$SW_PRI" symbolic-ref -q --short HEAD 2>/dev/null)"

  # ---- worktrees (judged first) -----------------------------------------------
  local wts
  wts="$(git -C "$SW_PRI" worktree list --porcelain 2>/dev/null | awk '
    function flush() { if (n > 1 && path != "") printf "%s\037%s\037%s\037%s\n", path, head, br, fl
                       path = ""; head = ""; br = ""; fl = "" }
    /^worktree / { flush(); n++; path = substr($0, 10); next }
    /^HEAD /     { head = substr($0, 6); next }
    /^branch /   { br = substr($0, 8); sub(/^refs\/heads\//, "", br); next }
    /^detached/  { fl = fl "detached,"; next }
    /^locked/    { fl = fl "locked,"; next }
    /^prunable/  { fl = fl "prunable,"; next }
    END { flush() }')"
  local nwt=0 nbr=0 held="" p head br fl cp kind v salv sw_verdict dirty pid lrc ic
  while IFS=$'\037' read -r p head br fl; do
    [ -n "$p" ] || continue
    cp="$(cd "$p" 2>/dev/null && pwd -P)"; [ -n "$cp" ] || cp="$p"
    if [ "$cp" = "$SW_PRI" ]; then continue; fi
    nwt=$((nwt + 1))
    case "$cp/" in
      "$SW_PRI/$SW_APP_WT/"*) kind=app ;;
      "$SW_PRI-lanes/"*) kind=lane ;;
      *) if _sw_plugin_made "$p" "$cp"; then kind=worktree; else kind=other; fi ;;
    esac
    # v = the keep reason (empty ⇒ still removable). A worktree that is not
    # removed keeps its branch out of the branch phase (`held`).
    v=""
    case "$kind" in
      lane)  v="use lane-remove" ;;
      other) v="origin unknown" ;;
    esac
    if [ -z "$v" ]; then
      case "$fl" in
        *prunable*) v="directory missing (prunable — git worktree prune clears it)" ;;
        *locked*) v="locked" ;;
      esac
    fi
    if [ -z "$v" ] && [ ! -d "$p" ]; then v="directory missing"; fi
    if [ -z "$v" ] && { [ -z "$br" ] || case "$fl" in *detached*) true ;; *) false ;; esac; }; then
      v="detached HEAD (no branch to prove)"
    fi
    if [ -z "$v" ] && [ "$br" = "$base" ]; then v="on the base branch $base"; fi
    if [ -z "$v" ]; then
      _sw_rule "$br" "$head"
      [ "$SW_RULE" = pass ] || v="branch $br: $SW_WHY"
    fi
    if [ -z "$v" ]; then
      dirty="$(git -C "$p" status --porcelain 2>/dev/null)" || dirty="(git status failed)"
      [ -z "$dirty" ] || v="dirty (uncommitted changes on $br)"
    fi
    if [ "$kind" = app ]; then
      if [ -z "$v" ]; then
        v="clean and merged (branch $br: $SW_WHY) — left in place; the app removes its own worktrees"
      else
        v="$v — left in place; the app removes its own worktrees"
      fi
      _sw_line kept app "$p" "$v"
      [ -z "$br" ] || held="$held$br"$'\037'"$p"$'\n'
      continue
    fi
    if [ -z "$v" ]; then
      # Read-only coverage check (dry run too): gitignored content that is neither on
      # worktree-salvage.sh's salvage list nor regenerable would be deleted with no
      # copy ⇒ kept, naming every such entry. No verdict line ⇒ kept as well.
      ic="$(bash "$HERE/worktree-salvage.sh" "$p" --check-ignored 2>/dev/null | tail -n1)"
      case "$ic" in
        "ignored-check: ok") ;;
        "ignored-check: unsalvaged "*) v="unsalvaged ignored content: ${ic#ignored-check: unsalvaged }" ;;
        *) v="gitignored content unverifiable: ${ic:-no verdict}" ;;
      esac
    fi
    if [ -z "$v" ]; then
      _sw_live_read
      pid="$(_sw_live "$p" "$cp")"; lrc=$?
      if [ "$lrc" -eq 0 ]; then v="live process $pid has its cwd here"
      elif [ "$lrc" -eq 2 ]; then v="liveness unverifiable (lsof absent or failing)"
      elif [ "$lrc" -eq 3 ]; then v="liveness unverifiable (the path holds a byte lsof escapes — non-ASCII or a backslash)"
      fi
    fi
    if [ -n "$v" ]; then
      _sw_line kept "$kind" "$p" "$v"
      [ -z "$br" ] || held="$held$br"$'\037'"$p"$'\n'
      continue
    fi
    if [ "$SW_APPLY" -ne 1 ]; then
      _sw_line act worktree "$p" "branch $br: $SW_WHY; clean; every gitignored entry salvageable or regenerable; no live process (gitignored runtime content is salvaged and verified first)"
      continue
    fi
    salv="$(bash "$HERE/worktree-salvage.sh" "$p" --reason "automate sweep" --ignored 2>/dev/null)"
    sw_verdict="$(printf '%s\n' "$salv" | tail -n1)"
    salv="$(printf '%s\n' "$salv" | head -n1)"
    case "$salv" in "ignored: "*) salv="" ;; esac
    dirty="$(git -C "$p" status --porcelain 2>/dev/null)" || dirty="(git status failed)"
    case "$sw_verdict" in "ignored: ok "*) ;; *) v="gitignored salvage not verified: ${sw_verdict:-no verdict}" ;; esac
    [ -n "$v" ] || [ -z "$dirty" ] || v="still dirty after salvage"
    if [ -z "$v" ] && git -C "$SW_PRI" worktree remove "$p" >/dev/null 2>&1; then
      _sw_line act worktree "$p" "branch $br: $SW_WHY; gitignored salvage verified (${sw_verdict})${salv:+, salvaged to $salv}"
    else
      _sw_line kept worktree "$p" "${v:-git worktree remove refused}${salv:+ (salvaged to $salv)}"
      held="$held$br"$'\037'"$p"$'\n'
    fi
  done <<SWWT
$wts
SWWT

  # ---- local branches ---------------------------------------------------------
  local refs b tip hp
  refs="$(git -C "$SW_PRI" for-each-ref --format='%(refname)' refs/heads/ 2>/dev/null)"
  while IFS= read -r b; do
    [ -n "$b" ] || continue
    b="${b#refs/heads/}"
    nbr=$((nbr + 1))
    if [ -n "$cur" ] && [ "$b" = "$cur" ]; then _sw_line kept branch "$b" "current branch of the primary"; continue; fi
    if [ "$b" = "$base" ]; then _sw_line kept branch "$b" "base branch"; continue; fi
    hp="$(printf '%s' "$held" | SW_BR="$b" awk 'BEGIN { FS = "\037"; b = ENVIRON["SW_BR"] } $1 == b { print $2; exit }')"
    if [ -n "$hp" ]; then _sw_line kept branch "$b" "checked out in worktree $hp"; continue; fi
    tip="$(git -C "$SW_PRI" rev-parse -q --verify "refs/heads/$b" 2>/dev/null)"
    _sw_rule "$b" "$tip"
    if [ "$SW_RULE" != pass ]; then _sw_line kept branch "$b" "$SW_WHY"; continue; fi
    if [ "$SW_APPLY" -ne 1 ]; then _sw_line act branch "$b" "$SW_WHY"; continue; fi
    if git -C "$SW_PRI" branch -D "$b" >/dev/null 2>&1; then
      _sw_line act branch "$b" "$SW_WHY"
    else
      _sw_line kept branch "$b" "git branch -D refused"
    fi
  done <<SWBR
$refs
SWBR

  local mode="dry run" verb="would-remove"
  [ "$SW_APPLY" -eq 1 ] && { mode="applied"; verb="removed"; }
  printf 'sweep: summary — %s: %s %s, %s kept (%s worktree(s), %s branch(es) examined)\n' \
    "$mode" "$SW_ACT" "$verb" "$SW_KEPT" "$nwt" "$nbr"
  return 0
}

