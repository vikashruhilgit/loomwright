# --------------------------------------------------------------------------- #
# closeout
# --------------------------------------------------------------------------- #
# closeout <runfile> <item> <pr_url> [--session-id <sid>] [--no-trail]
# The post-merge close-out (SKILL §6 "Post-merge close-out"). Deterministic,
# idempotent, fail-SAFE. Every output line is `closeout: <verb> — <detail>`
# (verb ∈ removed|synced|stamped|checked|reconciled|skipped), except the
# brief-repair and trail-pr lines, which are passed through verbatim. Execution
# order: evidence gate → brief repair → [run lock] 3a worktrees → 4 sync → 3b
# branch → 5 stamp → check off → 7b reconcile ## Current → ## Progress →
# trail-pr → [release]. It never ticks `_BACKLOG.md` (human-owned; the step-5
# stamp is what `resolve-backlog` reads — SKILL §2). The check-off runs BEFORE
# the trail so the trail PR records the closed-out item; the trail line is
# printed but never appended to ## Progress (appending it would leave the run
# file one line ahead of the trail, so every re-run would push again). The step
# lines reach ## Progress only when an ITEM step changed something (removed /
# stamped / checked / reconciled, or a non-skip brief repair); a `synced` line
# alone never appends, so a re-run after the trail PR merged leaves the run
# file byte-identical and its trail reads `skipped — trail already up to date`.
# NEVER: commits in the primary checkout, `git reset`, `git stash`, `git branch
# -d` / ancestry inference, touches another branch or worktree, merges anything.
# --no-trail (automate-followups/38; parsed like --session-id, any position):
# every step runs exactly as above except the trail, whose line reads
# `trail-pr: skipped — --no-trail` — not a `closeout:` line, so closeout-classify
# ignores it. For the callers where a trail PR would park the run (`--auto-merge`
# SYNC, SKILL §6 step 5) or where the caller pushes itself (a merged lane's
# lane-convert-ready re-run, SKILL §14); the run's trail ships at the next
# existing trigger.
# _run_lock_in <checkout> <run-lock.sh args…> — every run-lock.sh call that closes or
# finalizes a run (closeout, finalize-empty) goes through here. It runs run-lock.sh from
# INSIDE the run file's checkout with NO --root, so the lock dir is the one run-lock.sh's
# own default resolution picks — the MAIN worktree root of that checkout — exactly the dir
# the engine's PICK / post-release windows take (they pass no --root either). Passing
# `--root <run file's toplevel>` instead diverged in a linked worktree: the engine locked
# <main>/.supervisor/run.lock, closeout <linked>/.supervisor/run.lock, and both acquires
# succeeded (the post-release mutual exclusion and PICK/RECONCILE re-entry did not hold).
# A lane clone is its own main worktree, so its lock dir is unchanged; the merge watcher's
# cwd does not matter (the checkout comes from the run file). A failed cd returns
# non-zero, which an acquire reads as refused (fail CLOSED).
_run_lock_in() {
  local dir="$1"; shift
  ( cd "$dir" 2>/dev/null && bash "$HERE/run-lock.sh" "$@" )
}

CO_ROOT=""
CO_OWNER=""
CO_LOCKED=0
co_release() {
  if [ "$CO_LOCKED" -eq 1 ] && [ -n "$CO_OWNER" ]; then
    # --owner ONLY: never forward --session-id to release (run-lock.sh releases on
    # EITHER match, which would drop an outer PICK lock we merely re-entered).
    _run_lock_in "$CO_ROOT" release --owner "$CO_OWNER" >/dev/null 2>&1
  fi
  CO_LOCKED=0
  return 0
}

# _co_current <rf_rel> <item> <pr_url> — closeout step 7b. Prints ONE line.
# Rewrites `## Current` for the item just closed out — the `- item:` line's
# `status:` field to `done`, the `- pause_reason:` line to `awaiting_go` when
# `## Status: paused` (`null` otherwise: a running loop is not paused) — ONLY
# when that line names THIS item AND THIS pr, and only after the Queue reads
# `- [x] <item>` (a failed check-off must not leave Current saying done while
# the Queue says queued). A `## Current` naming another item/PR is never
# touched: the merge watcher can fire after the owner already --resumed and a
# later item was picked. Every other line is byte-unchanged; `## Status` is
# never rewritten. The write goes through `automate-helpers.sh current-set`
# (validated atomic rename through runfile-write's `_runfile_install … full`,
# SKILL §3) — never a `generator | runfile-write` pipe, whose failing generator
# the helper cannot see.
_co_current() {
  local rf="$1" item="$2" pr="$3" S="closeout: skipped —"
  if ! grep -qxF -- "- [x] $item" "$rf" 2>/dev/null; then
    echo "$S ## Current not reconciled ($item not checked off)"; return 0
  fi
  local cur_line cur_raw cur_item cur_pr cur_status cur_reason run_status want
  cur_line="$(awk '/^## Current/{c=1;next} /^## /{c=0} c && /^- item: /{print; exit}' "$rf" 2>/dev/null)"
  if [ -z "$cur_line" ]; then echo "$S no ## Current item line"; return 0; fi
  _co_field() { printf '%s\n' "$cur_line" | awk -v k="$1" 'BEGIN{FS=" [|] "} {sub(/^- /,""); for(i=1;i<=NF;i++) if (index($i, k ": ")==1) {print substr($i, length(k)+3); exit}}'; }
  cur_raw="$(_co_field item)"; cur_item="${cur_raw#./}"
  cur_pr="$(_co_field pr)"; cur_status="$(_co_field status)"
  if [ "$cur_item" != "$item" ] || [ "$cur_pr" != "$pr" ]; then
    echo "$S ## Current is ${cur_item:-?} (${cur_pr:-no pr}), not this item/PR"; return 0
  fi
  run_status="$(sed -n 's/^## Status:[[:space:]]*\([A-Za-z_]*\).*/\1/p' "$rf" | head -n1)"
  if [ "$run_status" = "paused" ]; then want="awaiting_go"; else want="null"; fi
  cur_reason="$(awk '/^## Current/{c=1;next} /^## /{c=0} c && /^- pause_reason:/{sub(/^- pause_reason:[[:space:]]*/,""); sub(/[[:space:]]+$/,""); print; exit}' "$rf" 2>/dev/null)"
  if [ "$cur_status" = "done" ] && [ "$cur_reason" = "$want" ]; then
    echo "$S ## Current already done"; return 0
  fi
  # The write goes through `automate-helpers.sh current-set` (SKILL §3 "`## Current`
  # moves only through `current-set`"): the RAW stored item of the CURRENT line (not
  # the `./`-stripped comparison value), status done, the wanted pause_reason — the
  # item is unchanged, so current-set keeps the line's pr/branch and every other line.
  if bash "$HERE/automate-helpers.sh" current-set "$rf" --item "$cur_raw" --status done --pause-reason "$want" >/dev/null 2>&1; then
    echo "closeout: reconciled — ## Current $item status done, pause_reason $want"
  else
    echo "$S ## Current runfile-write refused"
  fi
  return 0
}

# _co_stamped <requirement> — closeout step 5's "already stamped" check. True
# only for a REAL close-out block: a line that is exactly the sentinel
# `<!-- loomwright:requirement-closeout -->` (a trailing CR tolerated), whose
# NEXT line is a `## Status: done` / `## Status: done_with_escalation` heading —
# the shape the step-5 printf writes. A sentinel quoted inline in prose, or on a
# line of its own followed by anything else, does not count (automate-followups/38:
# af/37's own requirement quotes it in `## Problem`, and a plain substring match
# read that as stamped, so closeout never stamped it).
_co_stamped() {
  awk 'BEGIN { s = "<!-- loomwright:requirement-closeout -->" }
    { sub(/\r$/, "") }
    prev && /^## Status:[[:space:]]*done(_with_escalation)?([^A-Za-z0-9_]|$)/ { f = 1; exit }
    { prev = ($0 == s) }
    END { exit !f }' "$1" 2>/dev/null
}

closeout() {
  local runfile="" item="" pr_url="" sid="" no_trail=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --session-id) sid="${2:-}"; shift 2 || shift ;;
      --no-trail) no_trail=1; shift ;;
      *) if [ -z "$runfile" ]; then runfile="$1"; elif [ -z "$item" ]; then item="$1"; elif [ -z "$pr_url" ]; then pr_url="$1"; fi; shift ;;
    esac
  done
  local S="closeout: skipped —"
  if [ -z "$runfile" ] || [ -z "$item" ] || [ -z "$pr_url" ]; then echo "$S missing argument"; return 0; fi
  if [ ! -f "$runfile" ]; then echo "$S run file not found"; return 0; fi
  if ! command -v git >/dev/null 2>&1; then echo "$S git unavailable"; return 0; fi
  if ! command -v "$JQ" >/dev/null 2>&1; then echo "$S jq unavailable"; return 0; fi
  if ! command -v "$GH" >/dev/null 2>&1 || ! "$GH" auth status >/dev/null 2>&1; then echo "$S gh unavailable"; return 0; fi

  local rf_dir rf_abs root rf_rel run_id
  rf_dir="$(cd "$(dirname "$runfile")" 2>/dev/null && pwd -P)" || { echo "$S run file not found"; return 0; }
  rf_abs="$rf_dir/$(basename "$runfile")"
  root="$(git -C "$rf_dir" rev-parse --show-toplevel 2>/dev/null)"
  if [ -z "$root" ]; then echo "$S not a git checkout"; return 0; fi
  root="$(cd "$root" && pwd -P)"
  CO_BRANCH_MODE=off
  case "$(_branch_mode "$root")" in "on "*) CO_BRANCH_MODE=on ;; esac
  case "$rf_abs" in "$root"/*) rf_rel="${rf_abs#"$root"/}" ;; *) echo "$S run file outside the checkout"; return 0 ;; esac
  run_id="$(basename "$runfile" .md)"
  item="${item#./}"
  cd "$root" || { echo "$S cannot enter checkout"; return 0; }
  local HLP="$HERE/automate-helpers.sh"

  # ---- 1. evidence gate (prints only when it stops the close-out) -----------
  local st
  st="$(bash "$HLP" reconcile-item "$pr_url" 2>/dev/null)"
  if [ "$st" != "merged" ]; then echo "$S pr not merged (${st:-unknown})"; return 0; fi

  # ---- 2. brief repair (its own line, passed through) -----------------------
  local lines="" l did=0
  l="$(bash "$HLP" brief-repair "$item" "$pr_url" 2>/dev/null | tail -n1)"
  [ -n "$l" ] || l="brief-repair: skipped — no output"
  echo "$l"; lines="$l"
  case "$l" in *"skipped —"*) ;; *) did=1 ;; esac

  # ---- steps 3–7 under the run lock -----------------------------------------
  # The step numbers are the SKILL's labels (§6 "Post-merge close-out"); the
  # EXECUTION order is 3a → 4 → 3b → 5 → 7 → 7b → 6, and the blocks below follow it.
  CO_ROOT="$root"; CO_OWNER="automate-closeout:$run_id"
  local lk rc
  if [ -n "$sid" ]; then
    lk="$(_run_lock_in "$root" acquire --owner "$CO_OWNER" --session-id "$sid" 2>/dev/null)"; rc=$?
  else
    lk="$(_run_lock_in "$root" acquire --owner "$CO_OWNER" 2>/dev/null)"; rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    # The refusal names the holder's liveness (automate-followups/36 A1). run-lock.sh's
    # refusal carries the same `owner=… pid=… age=…` fields `run-lock.sh status` prints;
    # the verdict is run-lock.sh's OWN (`liveness`, its `holder_alive` rule: kill -0 AND
    # the recorded pid_start — a reused pid reads dead), never a local `kill -0`. It runs
    # through _run_lock_in, so it reads the lock dir the acquire was refused on, and
    # `--pid` binds it to the REFUSED pid: if that holder released and another took the
    # lock in between, the verdict is `dead`, never the newcomer's `alive` (fails toward
    # the leftover). A LIVE holder (often another lane's run in this checkout, met by
    # closeout-others) is busy, not a leftover: closeout-classify reads `(live pid <p>)`
    # as `run_lock_held`. A dead, reused, released or unreadable holder — run-lock.sh
    # reclaims only a dead pid at age >= 1800 s, so a dead-but-young one still refuses —
    # stays a leftover.
    local holder hpid hlive=""
    holder="$(printf '%s\n' "$lk" | sed -n 's/.*run_lock_held owner=\([^ ]*\).*/\1/p' | head -n1)"
    hpid="$(printf '%s\n' "$lk" | sed -n 's/.*run_lock_held owner=[^ ]* pid=\([0-9][0-9]*\).*/\1/p' | head -n1)"
    [ -z "$hpid" ] || hlive="$(_run_lock_in "$root" liveness --pid "$hpid" 2>/dev/null)"
    if [ "$hlive" = alive ]; then
      echo "$S run lock held by ${holder:-unknown} (live pid $hpid)"
    else
      echo "$S run lock held by ${holder:-unknown} (holder pid ${hpid:-unknown} not running)"
    fi
    return 0
  fi
  CO_LOCKED=1
  trap co_release EXIT

  local view head_ref head_oid
  view="$("$GH" pr view "$pr_url" --json headRefName,headRefOid 2>/dev/null)"
  head_ref="$(printf '%s' "$view" | "$JQ" -r '.headRefName // empty' 2>/dev/null)"
  head_oid="$(printf '%s' "$view" | "$JQ" -r '.headRefOid // empty' 2>/dev/null)"

  # The base comes from the ONE resolver (resolve-base-branch.sh). Unresolved/invalid (base_tok set)
  # skips only the base-dependent steps — 3a/3b (they must never touch the base branch, and cannot
  # tell which it is) and the step-4 sync — with the resolver's diagnostic on stderr; every other
  # step runs and the exit contract is unchanged.
  local base_branch base_tok=""
  if ! base_branch="$(bash "$HERE/resolve-base-branch.sh" --repo "$root" 2>&1 </dev/null)"; then
    printf '%s\n' "$base_branch" >&2
    base_tok="${base_branch%%$'\n'*}"; base_branch=""
  fi

  # ---- 3a. worktrees on the PR's head branch (never the primary; runs 1st) --
  local wt_line="" wt_list wt salv dirty wrem="" wkeep="" co_verdict co_ign
  if [ -n "$base_tok" ]; then
    wt_line="$S $base_tok (base branch unknown; worktree cleanup not attempted)"; head_ref=""
  elif [ -z "$head_ref" ] || [ -z "$head_oid" ]; then
    wt_line="$S head branch unresolved (gh pr view headRefName/headRefOid failed)"; head_ref=""
  elif [ "$head_ref" = "$base_branch" ]; then
    wt_line="$S head branch is the base branch"; head_ref=""
  else
    wt_list="$(git worktree list --porcelain 2>/dev/null | awk -v b="refs/heads/$head_ref" '
      /^worktree /{p=substr($0,10); n++} /^branch /{ if (n>1 && substr($0,8)==b) print p }')"
    local wtip
    while IFS= read -r wt; do
      [ -n "$wt" ] || continue
      [ "$(cd "$wt" 2>/dev/null && pwd -P)" = "$root" ] && continue
      # Same squash-safe tip check as 3b: `git worktree remove` (no --force)
      # still deletes GITIGNORED content, which worktree-salvage.sh skips by
      # design — so a worktree whose HEAD is not the merged head (a same-named
      # branch reused for other work) is kept, never salvaged or removed.
      wtip="$(git -C "$wt" rev-parse -q --verify HEAD 2>/dev/null)"
      if [ "$wtip" != "$head_oid" ]; then
        wkeep="${wkeep:+$wkeep, }$wt (tip ${wtip:0:12} != merged head ${head_oid:0:12})"
        continue
      fi
      # --ignored (af/39a): gitignored runtime content (worktree-salvage.sh's salvage
      # list, ign_salvage_list — the drain's records among it) is copied and verified
      # too; ANY last line but `ignored: ok <n>` — a
      # failed entry, or no verdict at all — keeps the worktree (fail closed on a
      # fail-safe emitter). `--allow-unsalvaged`: closeout keeps its prior, tested
      # contract for its OWN merged PR worktree (removed even when it holds gitignored
      # content beyond that list — the M1 `match` leg); only `sweep`, which judges
      # worktrees it did not just drive, fails closed on such content. Honest limit.
      salv="$(bash "$HERE/worktree-salvage.sh" "$wt" --reason "automate closeout" --ignored --allow-unsalvaged 2>/dev/null)"
      co_verdict="$(printf '%s\n' "$salv" | tail -n1)"
      salv="$(printf '%s\n' "$salv" | head -n1)"
      case "$salv" in "ignored: "*) salv="" ;; esac
      dirty="$(git -C "$wt" status --porcelain 2>/dev/null)"
      co_ign=failed
      case "$co_verdict" in "ignored: ok "*) co_ign=ok ;; esac
      if [ -n "$dirty" ]; then
        wkeep="${wkeep:+$wkeep, }$wt still dirty after salvage${salv:+ (salvaged to $salv)}"
      elif [ "$co_ign" != ok ]; then
        wkeep="${wkeep:+$wkeep, }$wt (gitignored salvage not verified: ${co_verdict:-no verdict})"
      elif git worktree remove "$wt" >/dev/null 2>&1; then
        wrem="${wrem:+$wrem, }$wt"
      else
        wkeep="${wkeep:+$wkeep, }$wt (git worktree remove refused)"
      fi
    done <<WTLIST
$wt_list
WTLIST
    if [ -n "$wrem" ] && [ -n "$wkeep" ]; then wt_line="closeout: removed — worktree $wrem; kept $wkeep"
    elif [ -n "$wrem" ]; then wt_line="closeout: removed — worktree $wrem"
    elif [ -n "$wkeep" ]; then wt_line="$S kept worktree $wkeep"
    else wt_line="$S already removed (no worktree on $head_ref)"
    fi
  fi
  echo "$wt_line"; lines="$lines"$'\n'"$wt_line"
  case "$wt_line" in "closeout: removed"*) did=1 ;; esac

  # ---- 4. sync the primary onto the base branch (runs 2nd, before 3b) -------
  # _sync_primary (shared with trail-gate's PICK-time sync) holds the guards,
  # the .trail-staged re-stage and the ff-only pull.
  local sy
  if [ -n "$base_tok" ]; then
    sy="$S $base_tok (base branch unknown; sync not attempted)"
  elif _sync_primary "$rf_rel" "$run_id" "$base_branch" "$head_ref" "$CO_BRANCH_MODE"; then
    # Deliberately NOT `did=1`: a sync is checkout housekeeping, not close-out
    # progress for THIS item. `main` moves for reasons unrelated to the item —
    # most often this run's own merged trail PR — so counting it made a re-run
    # whose every item step skipped append its skip lines to ## Progress, which
    # gave trail-pr a diff and opened a fresh trail PR holding only those lines
    # (run automate-2026-10-01-142337: #329 merged → RECONCILE re-run → #330),
    # and the next re-run would do it again.
    sy="closeout: synced — $base_branch at $(git rev-parse --short HEAD 2>/dev/null)"
  else
    sy="$S $SYNC_SKIP"
  fi
  echo "$sy"; lines="$lines"$'\n'"$sy"

  # ---- 3b. the local head branch (runs 3rd, after 4; squash-safe tip check) -
  local br tip
  if [ -z "$head_ref" ]; then
    br="$S branch unresolved"
  elif ! git rev-parse -q --verify "refs/heads/$head_ref" >/dev/null 2>&1; then
    br="$S already deleted (no local $head_ref)"
  else
    tip="$(git rev-parse "refs/heads/$head_ref" 2>/dev/null)"
    if [ "$(git symbolic-ref -q --short HEAD 2>/dev/null)" = "$head_ref" ]; then
      br="$S branch checked out in primary ($head_ref)"
    elif [ "$tip" != "$head_oid" ]; then
      br="$S local tip ${tip:0:12} != merged head ${head_oid:0:12} ($head_ref kept)"
    elif git branch -D "$head_ref" >/dev/null 2>&1; then
      br="closeout: removed — branch $head_ref (tip == merged head ${head_oid:0:12})"; did=1
    else
      br="$S git branch -D $head_ref refused (checked out in a kept worktree?)"
    fi
  fi
  echo "$br"; lines="$lines"$'\n'"$br"

  # ---- 5. requirement stamp (runs 4th; the ONLY engine done-stamp writer) ---
  # This printf IS the block's byte-shape authority; Phase 4.5 writes nothing to
  # the requirement (automate-followups/37), so the stamp lands only past step 1.
  local sp done_brief="" b ptr
  if [ ! -f "$item" ]; then
    sp="$S requirement $item not found"
  elif _co_stamped "$item"; then
    sp="$S already stamped"
  else
    if [ -r "$HERE/brief-pointer.sh" ]; then
      # shellcheck source=/dev/null
      . "$HERE/brief-pointer.sh"
      for b in .supervisor/jobs/done/*.md; do
        [ -f "$b" ] || continue
        ptr="$(brief_requirement_pointer "$b" 2>/dev/null)" || continue
        ptr="${ptr#./}"
        [ "$ptr" = "$item" ] || continue
        if [ -z "$done_brief" ] || [ "$b" -nt "$done_brief" ]; then done_brief="$b"; fi
      done
    fi
    if [ -z "$done_brief" ]; then
      sp="$S no done brief"
    elif printf '\n<!-- loomwright:requirement-closeout -->\n## Status: done\n- **Completed:** %s\n- **Brief:** %s\n- **PR:** %s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$done_brief" "$pr_url" >> "$item" 2>/dev/null; then
      sp="closeout: stamped — $item (## Status: done, brief $done_brief)"; did=1
    else
      sp="$S requirement not writable"
    fi
  fi
  echo "$sp"; lines="$lines"$'\n'"$sp"

  # ---- 7. check off (runs 5th, BEFORE 6 so the trail PR records it; NO reason
  #      argument — a reason writes `# skipped: …`) ------------------------------
  local ck
  if grep -qxF -- "- [ ] $item" "$rf_rel" 2>/dev/null; then
    if bash "$HLP" queue-checkoff "$rf_rel" "$item" >/dev/null 2>&1 && grep -qxF -- "- [x] $item" "$rf_rel" 2>/dev/null; then
      ck="closeout: checked — - [x] $item"; did=1
    else
      ck="$S queue-checkoff failed"
    fi
  elif grep -qF -- "- [x] $item" "$rf_rel" 2>/dev/null; then
    ck="$S already checked off"
  else
    ck="$S $item not in ## Queue"
  fi
  echo "$ck"; lines="$lines"$'\n'"$ck"

  # ---- 7b. reconcile ## Current (runs 6th, after the check-off; SKILL §3
  #      "After a close-out") ----------------------------------------------------
  local cu
  cu="$(_co_current "$rf_rel" "$item" "$pr_url")"
  case "$cu" in "closeout: reconciled"*) did=1 ;; esac
  echo "$cu"; lines="$lines"$'\n'"$cu"
  if [ "$did" -eq 1 ]; then
    local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    while IFS= read -r l; do
      [ -n "$l" ] || continue
      bash "$HLP" progress-append "$rf_rel" "$ts closeout $pr_url: $l" >/dev/null 2>&1
    done <<PROGRESS
$lines
PROGRESS
  fi

  # ---- item_timing (iq02 T04): ONE script-written event per PR, appended to the
  # item's session log (a gitignored .supervisor/logs/ file — never a trail path,
  # so trail-pr does not carry it; /insights reads it locally). IDEMPOTENT like
  # every other closeout step: a re-run (AC11, the post-trail-merge RECONCILE)
  # finds this PR's item_timing already in the log and appends nothing. SILENT
  # and fail-SAFE — closeout prints only `closeout:` lines (CLOSEOUT_TABLE), so
  # no output here, and nothing here can change a step's verb or this
  # function's exit status.
  # --item scopes the record to THIS item's Progress segment: without it a multi-item
  # run's second close-out read the first item's pick/park/drains.
  ( _pt="$(bash "$(dirname "$HLP")/phase-timing.sh" --run "$rf_abs" --item "$item" 2>/dev/null)" || exit 0
    _sid="$(printf '%s' "$_pt" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9_-')"
    [ -n "$_sid" ] || exit 0
    _logs="$(dirname "$(dirname "$rf_abs")")/logs"; [ -d "$_logs" ] || exit 0
    _lf="$_logs/$_sid.jsonl"
    [ -f "$_lf" ] && jq -Rne --arg pr "$pr_url" '[inputs | fromjson? | select(type == "object" and .event == "item_timing" and .pr_url == (if $pr == "" then null else $pr end))] | length > 0' < "$_lf" && exit 0   # item_timing-idempotence guard: this PR's row is already logged
    _line="$(printf '%s' "$_pt" | jq -c --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg pr "$pr_url" \
      '{event:"item_timing",ts:$ts,pr_url:(if $pr=="" then null else $pr end)} + .
       | if (.cc_session_id | type) == "string" and .cc_session_id != "" then . else del(.cc_session_id) end' 2>/dev/null)" || exit 0   # a session-log line carries cc_session_id only as a real id (build-floor's recount counts the key)
    [ -n "$_line" ] && { printf '%s\n' "$_line" >> "$_lf"; } 2>/dev/null
  ) >/dev/null 2>&1 || true

  # ---- 6. trail (runs LAST, after 7; via the dispatcher — stub-able, spy-visible)
  # --no-trail: this step alone is skipped; the lock is still released below.
  if [ "$no_trail" -eq 1 ]; then
    echo "trail-pr: skipped — --no-trail"
  else
    l="$(bash "$HLP" trail-pr "$rf_abs" --reason closeout 2>/dev/null | tail -n1)"
    echo "${l:-trail-pr: skipped — no output}"
  fi

  co_release; trap - EXIT
  return 0
}

