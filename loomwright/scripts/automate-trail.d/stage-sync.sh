# --------------------------------------------------------------------------- #
# trail-unstage
# --------------------------------------------------------------------------- #
# trail-unstage <runfile> — PICK-time (SKILL §6 step 1, after RECONCILE's
# closeout, before RUN). Drops the index entries trail-pr staged under the
# checkout contract (`git restore --staged -- <path>`, working copies untouched)
# so the next item's `git checkout -b` + commit cannot sweep them into its PR.
# Only this run's trail paths (+ its two sidecars, + every path in its
# `<run_id>.trail-staged` record) that differ from HEAD in the index are touched. Safe to drop: the committed bytes live on the trail branch,
# and trail-pr records them in `<run_id>.trail-staged`, from which closeout
# re-stages a landed blob right before its pull. One line; always exit 0.
trail_unstage() {
  local runfile="${1:-}" S="trail-unstage: skipped —"
  if [ -z "$runfile" ] || [ ! -f "$runfile" ]; then echo "$S run file not found"; return 0; fi
  if ! command -v git >/dev/null 2>&1; then echo "$S git unavailable"; return 0; fi
  local rf_dir rf_abs root rf_rel run_id
  rf_dir="$(cd "$(dirname "$runfile")" 2>/dev/null && pwd -P)" || { echo "$S run file not found"; return 0; }
  rf_abs="$rf_dir/$(basename "$runfile")"
  root="$(git -C "$rf_dir" rev-parse --show-toplevel 2>/dev/null)"
  if [ -z "$root" ]; then echo "$S not a git checkout"; return 0; fi
  root="$(cd "$root" && pwd -P)"
  case "$rf_abs" in "$root"/*) rf_rel="${rf_abs#"$root"/}" ;; *) echo "$S run file outside the checkout"; return 0 ;; esac
  run_id="$(basename "$runfile" .md)"
  cd "$root" || { echo "$S cannot enter checkout"; return 0; }
  # Branch mode stages nothing (trail-pr pushes to the metadata branch), so there is nothing to drop.
  case "$(_branch_mode "$root")" in "on "*) echo "$S branch mode"; return 0 ;; esac
  # Today's candidates ∪ sidecars ∪ the trail-staged record (_trail_owned).
  _trail_owned "$rf_rel" "$run_id"
  local p paths="$TRAIL_OWNED" staged="" n=0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    _in_list "$p" "$staged" && continue
    [ -n "$(git diff --cached --name-only -- "$p" 2>/dev/null)" ] || continue
    staged="${staged:+$staged$'\n'}$p"
  done <<EOF
$paths
EOF
  if [ -z "$staged" ]; then echo "$S nothing staged"; return 0; fi
  local done_l="" fail_l=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if git restore --staged -- "$p" >/dev/null 2>&1 && [ -z "$(git diff --cached --name-only -- "$p" 2>/dev/null)" ]; then
      done_l="${done_l:+$done_l, }$p"; n=$((n + 1))
    else
      fail_l="${fail_l:+$fail_l, }$p"
    fi
  done <<EOF
$staged
EOF
  if [ -n "$fail_l" ]; then
    echo "trail-unstage: unstaged $n path(s)${done_l:+ — $done_l}; FAILED $fail_l"
  else
    echo "trail-unstage: unstaged $n path(s) — $done_l"
  fi
  return 0
}

# --------------------------------------------------------------------------- #
# trail-gate (PICK, after RECONCILE, before trail-unstage — SKILL §8)
# --------------------------------------------------------------------------- #
# trail-gate <runfile> — the single-open-PR invariant counts this run's own
# trail PR. One line, always exit 0:
#   trail-gate: PARK — trail PR open <url>[, <url>…] (merge or close it, then --resume)
#   trail-gate: PARK — <why the trail PR state could not be read>
#   trail-gate: clear — no open trail PR; synced — <base> at <sha>
#   trail-gate: clear — no open trail PR; sync skipped — <reason>
# WHY: closeout opens the trail PR after the item's merge; when the owner gave
# the next go first and merged the trail PR while the next item's PR was open,
# that merge moved the base under it, and with `strict` required checks the
# item PR read BEHIND and could not merge (run automate-2026-10-01-142337,
# trail PR #345 under PR #347). With the trail PR merged before the PICK, the
# next item branches off a base that already carries it. A PARK is fail-CLOSED:
# anything that stops the read (gh/jq/git missing, a failed `gh pr list`, a
# run file it cannot resolve) parks — the gate cannot tell an open trail PR
# from none. Once clear, it syncs the primary onto the base branch with
# closeout's own _sync_primary (re-staging the recorded trail blobs that landed
# first), so the merged trail fast-forwards and the next item branches off a
# base that carries it — before this gate nothing synced at PICK and a hand
# pull after trail-unstage refused. A sync refusal is reported, never a park.
trail_gate() {
  local runfile="${1:-}" K="trail-gate: PARK —" C="trail-gate: clear — no open trail PR;"
  if [ -z "$runfile" ] || [ ! -f "$runfile" ]; then echo "$K run file not found"; return 0; fi
  if ! command -v git >/dev/null 2>&1; then echo "$K git unavailable"; return 0; fi
  if ! command -v "$GH" >/dev/null 2>&1; then echo "$K gh unavailable"; return 0; fi
  if ! command -v "$JQ" >/dev/null 2>&1; then echo "$K jq unavailable"; return 0; fi
  local rf_dir rf_abs root rf_rel run_id
  rf_dir="$(cd "$(dirname "$runfile")" 2>/dev/null && pwd -P)" || { echo "$K run file not found"; return 0; }
  rf_abs="$rf_dir/$(basename "$runfile")"
  root="$(git -C "$rf_dir" rev-parse --show-toplevel 2>/dev/null)"
  if [ -z "$root" ]; then echo "$K not a git checkout"; return 0; fi
  root="$(cd "$root" && pwd -P)"
  case "$rf_abs" in "$root"/*) rf_rel="${rf_abs#"$root"/}" ;; *) echo "$K run file outside the checkout"; return 0 ;; esac
  run_id="$(basename "$runfile" .md)"
  cd "$root" || { echo "$K cannot enter checkout"; return 0; }

  # The same lookup trail-pr uses to find (and reuse) this run's trail PRs.
  local prefix="chore/$run_id-trail-" list open
  list="$("$GH" pr list --state open --search "head:chore/$run_id-trail" --limit 100 --json url,state,headRefName 2>/dev/null)"
  if [ $? -ne 0 ] || ! printf '%s' "$list" | "$JQ" -e 'type == "array"' >/dev/null 2>&1; then
    echo "$K trail PR state unreadable (gh pr list failed)"; return 0
  fi
  if ! open="$(printf '%s' "$list" | "$JQ" -r --arg p "$prefix" '[.[] | select((.state // "") == "OPEN") | select((.headRefName // "") | startswith($p)) | select((.headRefName | ltrimstr($p)) | test("^[0-9]+$")) | .url] | join(", ")' 2>/dev/null)"; then
    echo "$K trail PR state unreadable (jq failed)"; return 0
  fi
  if [ -n "$open" ]; then
    echo "$K trail PR open $open (merge or close it, then --resume)"; return 0
  fi

  # The base comes from the ONE resolver (resolve-base-branch.sh). Unresolved/invalid skips ONLY the
  # sync: the status token rides the `sync skipped` line, the resolver's diagnostic goes to stderr.
  local base_branch bm=off
  if ! base_branch="$(bash "$HERE/resolve-base-branch.sh" --repo "$root" 2>&1 </dev/null)"; then
    printf '%s\n' "$base_branch" >&2
    echo "$C sync skipped — ${base_branch%%$'\n'*}"; return 0
  fi
  case "$(_branch_mode "$root")" in "on "*) bm=on ;; esac
  if _sync_primary "$rf_rel" "$run_id" "$base_branch" "" "$bm"; then
    echo "$C synced — $base_branch at $(git rev-parse --short HEAD 2>/dev/null)"
  else
    echo "$C sync skipped — $SYNC_SKIP"
  fi
  return 0
}

# _restage_landed <record> <ref> — closeout step 4, immediately before the pull:
# for each recorded trail blob (path/mode/blob, written by trail-pr) that <ref>
# (the fetched origin/<base>) now carries at that path, and that HEAD does not,
# set the index entry to that blob — the checkout contract, re-applied at the
# one moment it is needed, only for bytes this run itself committed and that
# have landed upstream. Never touches the working copy. Always returns 0.
# Every entry it overwrites is remembered in RESTAGE_PRIOR (path TAB mode TAB
# blob, or path TAB - TAB - when the index had no stage-0 entry), so a refused
# pull can put the index back exactly as it was (_restore_prior).
RESTAGE_PRIOR=""
_restage_landed() {
  local rec="$1" ref="$2" path mode blob up prior tab=$'\t'
  RESTAGE_PRIOR=""
  [ -f "$rec" ] || return 0
  while IFS=$'\t' read -r path mode blob; do
    [ -n "$path" ] && [ -n "$blob" ] || continue
    up="$(git rev-parse -q --verify "$ref:$path" 2>/dev/null)"
    [ "$up" = "$blob" ] || continue
    [ "$(git rev-parse -q --verify "HEAD:$path" 2>/dev/null)" = "$blob" ] && continue
    prior="$(git ls-files -s -- "$path" 2>/dev/null | awk '$3 == "0" {print $1 "\t" $2; exit}')"
    [ -n "$prior" ] && [ "${prior#*"$tab"}" = "$blob" ] && continue
    if git update-index --add --cacheinfo "$mode,$blob,$path" >/dev/null 2>&1; then
      [ -n "$prior" ] || prior="-${tab}-"
      RESTAGE_PRIOR="${RESTAGE_PRIOR:+$RESTAGE_PRIOR$'\n'}$path$tab$prior"
    fi
  done < "$rec"
  return 0
}

# _restore_prior — undo _restage_landed after a refused `git pull --ff-only`
# (git refuses before it touches the index): each overwritten entry goes back
# to its recorded mode/blob, and an entry that did not exist is dropped from
# the index again (`--force-remove`, index only — the working copy is never
# touched). Returns 0; prints nothing.
_restore_prior() {
  local path mode blob
  [ -n "$RESTAGE_PRIOR" ] || return 0
  while IFS=$'\t' read -r path mode blob; do
    [ -n "$path" ] || continue
    if [ "$mode" = "-" ]; then
      git update-index --force-remove -- "$path" >/dev/null 2>&1
    else
      git update-index --cacheinfo "$mode,$blob,$path" >/dev/null 2>&1
    fi
  done <<EOF
$RESTAGE_PRIOR
EOF
  RESTAGE_PRIOR=""
  return 0
}

# _sync_primary <rf_rel> <run_id> <base_branch> <head_ref|""> <branch_mode on|off>
# — switch the primary checkout (cwd) onto <base_branch> and `git pull
# --ff-only` it. Shared by closeout step 4 and trail-gate (the PICK-time sync).
# Returns 0 when it pulled; 1 with SYNC_SKIP set to the reason otherwise (an
# `already synced` answer is a skip too). <head_ref> is the one other branch
# the primary may be on (closeout: the merged PR's head; trail-gate: none).
# This run's own trail paths (_trail_owned — the SAME set trail-unstage drops:
# today's candidates ∪ sidecars ∪ every path _stage_tip staged in this index,
# recorded in `<run_id>.trail-staged`) never count as "uncommitted changes";
# anything else tracked and modified refuses the sync. Untracked files do not
# refuse it (git itself refuses a pull that would overwrite one). Never a
# reset, a stash or a commit.
SYNC_SKIP=""
_sync_primary() {
  local rf_rel="$1" run_id="$2" base_branch="$3" head_ref="$4" bm="$5" cur outside p
  SYNC_SKIP=""
  cur="$(git symbolic-ref -q --short HEAD 2>/dev/null)"
  _trail_owned "$rf_rel" "$run_id"
  outside=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    p="${p:3}"; p="${p#\"}"; p="${p%\"}"
    _in_list "$p" "$TRAIL_OWNED" || outside="${outside:+$outside, }$p"
  done <<STATUS
$(git status --porcelain --untracked-files=no 2>/dev/null)
STATUS
  if [ -z "$cur" ]; then
    SYNC_SKIP="primary checkout is on a detached HEAD"
  elif [ "$cur" != "$base_branch" ] && [ -z "$head_ref" ]; then
    SYNC_SKIP="primary checkout is on $cur, not $base_branch"
  elif [ "$cur" != "$base_branch" ] && [ "$cur" != "$head_ref" ]; then
    SYNC_SKIP="primary checkout is on $cur (neither $base_branch nor the PR head)"
  elif [ -n "$outside" ]; then
    SYNC_SKIP="uncommitted changes outside the trail paths ($outside)"
  elif ! git fetch -q origin >/dev/null 2>&1; then
    SYNC_SKIP="git fetch failed"
  elif [ "$cur" = "$base_branch" ] && [ "$(git rev-parse -q --verify HEAD 2>/dev/null)" = "$(git rev-parse -q --verify "refs/remotes/origin/$base_branch" 2>/dev/null)" ]; then
    SYNC_SKIP="already synced ($base_branch at origin/$base_branch)"
  elif [ "$cur" != "$base_branch" ] && ! git checkout -q "$base_branch" >/dev/null 2>&1; then
    SYNC_SKIP="git checkout $base_branch refused"
  # Two-command elif list, deliberately: `_restage_landed` runs only once every
  # guard above has passed (never on a refused sync), and its status is ignored
  # (`;`) — only the pull's status decides this branch.
  # Branch mode: trail-pr never staged anything (no .trail-staged record), so nothing is re-staged.
  elif { [ "$bm" = on ] || _restage_landed "$(dirname "$rf_rel")/$run_id.trail-staged" "refs/remotes/origin/$base_branch"; };
       ! git pull -q --ff-only origin "$base_branch" >/dev/null 2>&1; then
    # A refused pull must not leave the re-staged trail blobs in the index
    # (they would ride along in the next commit made from the primary).
    _restore_prior
    SYNC_SKIP="git pull --ff-only refused (no reset attempted)"
  else
    return 0
  fi
  return 1
}

