# ---- the ONE managed-set declaration ----
is_managed() {
  case "$1" in
    *"$TAB"*) return 1 ;;
    # Non-canonical paths are never managed (paths from a branch tree are untrusted; `*` in a case
    # pattern also matches `/`, so a dot segment would otherwise pass the globs below and climb out
    # of .supervisor/ when joined to the root).
    /*|./*|../*|*/./*|*/../*|*//*|*/.|*/..|*/) return 1 ;;
    .supervisor/requirements/*.md)
      case "$1" in
        .supervisor/requirements/.supervisor/*|.supervisor/requirements/*/.supervisor/*) return 1 ;;
      esac
      return 0 ;;
    .supervisor/jobs/done/*/*|.supervisor/jobs/failed/*/*|.supervisor/automate/*/*) return 1 ;;
    .supervisor/twin/contracts/*/*|.supervisor/agent-memory-proposals/*/*) return 1 ;;
    .supervisor/jobs/done/*.md|.supervisor/jobs/failed/*.md|.supervisor/automate/*.md) return 0 ;;
    .supervisor/automate/?*.dismissed-decisions) return 0 ;;
    .supervisor/postmortem/results.jsonl) return 0 ;;
    # learning stores (is_learning_path below names the class)
    .supervisor/twin/contracts/*.md|.supervisor/twin/.provenance.jsonl) return 0 ;;
    .supervisor/agent-memory-proposals/*.md) return 0 ;;
    .supervisor/eval/results.jsonl|.supervisor/eval/brain-baseline.jsonl) return 0 ;;
  esac
  return 1
}

# is_twin_path / is_learning_path <MANAGED path> — the two classes inside the managed set (called
# only on paths is_managed accepted, so its exclusions — nesting, non-canonical — already ran).
# The TWIN SET syncs as a whole (header: TWIN SET); every LEARNING-STORE path is published only
# with consent (header: CONSENT) and is left out of status's first line. Everything else is run
# history.
is_twin_path() {
  case "$1" in
    .supervisor/twin/contracts/*.md|.supervisor/twin/.provenance.jsonl) return 0 ;;
  esac
  return 1
}
is_learning_path() {
  is_twin_path "$1" && return 0
  case "$1" in
    .supervisor/agent-memory-proposals/*.md) return 0 ;;
    .supervisor/eval/results.jsonl|.supervisor/eval/brain-baseline.jsonl) return 0 ;;
  esac
  return 1
}

# ---- symlink containment (a symlink can redirect a write out of .supervisor/ or hide a file) ----
# symlink_hazard <repo-relative path of a local symlink> — 0 when a symlink there could redirect
# or hide managed run history: a managed path itself, a directory on the way to a managed folder,
# or a symlink under .supervisor/requirements/ that could hold managed .md files — one that
# resolves to a DIRECTORY, or a DANGLING one (its target may become a directory; it cannot be ruled
# out). A symlink resolving to a regular file at a non-managed path (requirements/q/design.png) can
# neither hide managed files nor be written through: it is not a hazard (and never synced).
symlink_hazard() {
  case "$1" in
    .supervisor|.supervisor/requirements|.supervisor/jobs|.supervisor/jobs/done|.supervisor/jobs/failed|.supervisor/automate|.supervisor/postmortem) return 0 ;;
    .supervisor/twin|.supervisor/twin/contracts|.supervisor/agent-memory-proposals|.supervisor/eval) return 0 ;;
  esac
  is_managed "$1" && return 0
  if [ -d "$ROOT/$1" ] || [ ! -e "$ROOT/$1" ]; then is_managed "$1/x.md"; else return 1; fi
}
# path_has_no_symlink <managed path> — 0 when no EXISTING component of the path, from .supervisor
# down to the leaf, is a symlink.
path_has_no_symlink() {
  local rest="$1" acc="" comp
  while :; do
    comp="${rest%%/*}"
    acc="${acc:+$acc/}$comp"
    [ -L "$ROOT/$acc" ] && return 1
    [ "$rest" = "$comp" ] && return 0
    rest="${rest#*/}"
  done
}
# parent_inside <managed path> — 0 when the path's (existing) parent directory resolves PHYSICALLY
# under <physical root>/.supervisor/.
parent_inside() {
  local phys
  phys="$(cd -P "$(dirname "$ROOT/$1")" 2>/dev/null && pwd -P)" || return 1
  case "$phys/" in "$ROOT_P/.supervisor/"*) return 0 ;; esac
  return 1
}

# ---- remote probing ----
# remote_probe — sets REMOTE_STATE (present|absent|unreachable) and REMOTE_SHA.
REMOTE_STATE=""; REMOTE_SHA=""
remote_probe() {
  local out rc
  out="$(g ls-remote --exit-code origin "refs/heads/$BRANCH" 2>/dev/null)"; rc=$?
  REMOTE_SHA=""
  case "$rc" in
    0) REMOTE_STATE="present"; REMOTE_SHA="$(printf '%s\n' "$out" | awk -v r="refs/heads/$BRANCH" '$2==r{print $1; exit}')"
       [ -n "$REMOTE_SHA" ] || REMOTE_STATE="unreachable" ;;
    2) REMOTE_STATE="absent" ;;
    *) REMOTE_STATE="unreachable" ;;
  esac
}

no_remote_branch_msg() {
  printf '%s\n' "meta_sync: no_remote_branch — '$BRANCH' does not exist on origin. Run 'meta-sync.sh init' once to create it. A common cause is a clone whose origin is a LOCAL PATH (another checkout) rather than the forge: that remote never carries the metadata branch. This is never treated as success." >&2
}

# fetch_remote — probe + fetch; sets R (commit) and RT (tree). Returns 0 ok, 1 fetch failure,
# 3 branch absent.
R=""; RT=""
fetch_remote() {
  remote_probe
  case "$REMOTE_STATE" in
    absent) return 3 ;;
    unreachable) return 1 ;;
  esac
  # --no-write-fetch-head: the gitdir (and its FETCH_HEAD) is shared with the user's own fetches
  # and every worktree; git < 2.29 rejects the flag, so fall back to a plain fetch there.
  if ! g fetch -q --no-tags --no-write-fetch-head origin "refs/heads/$BRANCH" >/dev/null 2>"$WORK/fetch.err"; then
    grep -q 'no-write-fetch-head' "$WORK/fetch.err" 2>/dev/null || return 1
    g fetch -q --no-tags origin "refs/heads/$BRANCH" >/dev/null 2>"$WORK/fetch.err" || return 1
  fi
  g cat-file -e "$REMOTE_SHA^{commit}" 2>/dev/null || return 1
  R="$REMOTE_SHA"
  RT="$(g rev-parse "$R^{tree}")" || return 1
  return 0
}

# ---- tables (path<TAB>sha, sorted) ----
# Every producer below FAILS CLOSED (non-zero) when its git read fails: an empty table is a
# decision input (an R or B table that silently came out empty turns every path into a deletion
# or a re-add), so a failed read must never look like an empty tree. The filter loops use
# `if`, not `&&`, so a non-managed LAST entry does not make the loop — and the pipeline — fail.
# no_newline_in <NUL-delimited raw listing> <what> — 0 when the listing holds no newline byte.
# Records are NUL-terminated and these -z listings emit no other newline, so any newline is INSIDE
# a name; the line-oriented parsing below would split it into fabricated records. Refuse on sight.
no_newline_in() {
  local n
  n="$(wc -l < "$1" | tr -d ' ')" || return 1
  [ "$n" = "0" ] && return 0
  warn "newline_in_path $2"
  warn "refusing — $2 holds a name containing a newline (it cannot be parsed safely); nothing was changed, meta-base untouched"
  return 1
}

# list_tree <tree-ish> <out> — managed blob entries of a tree.
list_tree() {
  g ls-tree -r -z --full-tree "$1" > "$WORK/lt.raw" 2>/dev/null || return 1
  no_newline_in "$WORK/lt.raw" "tree $1" || return 1
  tr '\0' '\n' < "$WORK/lt.raw" \
    | awk -F'\t' '{ split($1, a, " "); if (a[2] == "blob" && index($2, ".supervisor/") == 1) print $2 "\t" a[3] }' \
    | while IFS="$TAB" read -r p s; do if is_managed "$p"; then printf '%s\t%s\n' "$p" "$s"; fi; done \
    | env LC_ALL=C sort > "$2"
}

# list_local <out> <write:0|1> — managed files in the working folder, hashed as stored bytes.
# Enumerates ONLY the managed roots (requirements/ minus nested .supervisor/ trees; the top level
# of jobs/done, jobs/failed, automate, postmortem, twin, twin/contracts, agent-memory-proposals and
# eval), so churn or unreadable entries elsewhere
# under .supervisor/ (logs, worktrees) can never block a sync. Fails closed when a managed root or
# a folder on the way to one cannot be searched or fully enumerated, or when a symlink sits where
# managed run history lives (find does not descend a symlinked directory, so its files would read
# as locally ABSENT — a push would delete them from the branch — and a pull would write through it).
list_local() {
  local p d hz="$WORK/local.symlinks" present=" " roots=""
  : > "$WORK/local.paths" || return 1
  : > "$WORK/local.found" || return 1
  : > "$hz" || return 1
  if [ -L "$ROOT/.supervisor" ]; then
    warn "symlink .supervisor"
    warn "refusing — .supervisor is a symlink; run history must live inside the checkout (nothing was changed)"
    return 1
  fi
  # Parents first: a child is only looked at when its parent is a searchable real directory, so an
  # absent child is truly absent (never an EACCES on the parent read as "no such folder").
  for d in .supervisor .supervisor/requirements .supervisor/jobs .supervisor/jobs/done \
           .supervisor/jobs/failed .supervisor/automate .supervisor/postmortem \
           .supervisor/twin .supervisor/twin/contracts .supervisor/agent-memory-proposals .supervisor/eval; do
    case "$d" in
      .supervisor) : ;;
      *) case "$present" in *" ${d%/*} "*) : ;; *) continue ;; esac ;;
    esac
    if [ -L "$ROOT/$d" ]; then printf '%s\n' "$d" >> "$hz"; continue; fi
    [ -d "$ROOT/$d" ] || continue
    [ -x "$ROOT/$d" ] || { warn "cannot search $d/ (permission denied); nothing was changed"; return 1; }
    present="$present$d "
    case "$d" in .supervisor|.supervisor/jobs) : ;; *) roots="$roots $d" ;; esac
  done
  : > "$WORK/local.found.z" || return 1
  for d in $roots; do
    if [ "$d" = ".supervisor/requirements" ]; then
      (cd "$ROOT" && find "$d" -type d -name .supervisor -prune -o \( -type f -o -type l \) -print0) >> "$WORK/local.found.z"
    else
      (cd "$ROOT" && find "$d" -maxdepth 1 \( -type f -o -type l \) -print0) >> "$WORK/local.found.z"
    fi || { warn "could not enumerate every file under $d/ (find failed); nothing was changed"; return 1; }
  done
  no_newline_in "$WORK/local.found.z" "the local files under the managed roots" || return 1
  tr '\0' '\n' < "$WORK/local.found.z" > "$WORK/local.found" || return 1
  while IFS= read -r p; do
    p="${p#./}"
    if [ -L "$ROOT/$p" ]; then
      if symlink_hazard "$p"; then printf '%s\n' "$p" >> "$hz"; fi
    elif is_managed "$p"; then
      printf '%s\n' "$p"
    fi
  done < "$WORK/local.found" | env LC_ALL=C sort > "$WORK/local.paths" || return 1
  if [ -s "$hz" ]; then
    sed 's/^/meta_sync: symlink /' "$hz" >&2
    warn "refusing — the symlink(s) above sit where managed run history lives (a write could leave .supervisor/, and files behind them read as deleted); replace them with real directories/files. Nothing was changed."
    return 1
  fi
  : > "$1"
  [ -s "$WORK/local.paths" ] || return 0
  local wflag=""
  [ "$2" = "1" ] && wflag="-w"
  (cd "$ROOT" && git hash-object $wflag --no-filters --stdin-paths < "$WORK/local.paths") > "$WORK/local.shas" \
    || return 1
  [ "$(wc -l < "$WORK/local.paths")" -eq "$(wc -l < "$WORK/local.shas")" ] || return 1
  paste "$WORK/local.paths" "$WORK/local.shas" > "$1"
}

# list_history <commit> <out> — every (path, blob) a managed path ever held in R's history.
list_history() {
  g log --no-renames --format= --raw --no-abbrev -z "$1" -- .supervisor > "$WORK/lh.raw" 2>/dev/null || return 1
  no_newline_in "$WORK/lh.raw" "the history of $1" || return 1
  tr '\0' '\n' < "$WORK/lh.raw" \
    | awk '
        /^:/ { split($0, f, " "); old = f[3]; new = f[4]; getline p
               if (old != "" && old !~ /^0+$/) print p "\t" old
               if (new != "" && new !~ /^0+$/) print p "\t" new }' \
    | while IFS="$TAB" read -r p s; do if is_managed "$p"; then printf '%s\t%s\n' "$p" "$s"; fi; done \
    | env LC_ALL=C sort -u > "$2"
}

