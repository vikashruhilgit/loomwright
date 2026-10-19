# ==================================================================================================
# WAVE CLOSE (parallel-automate/21 Part A). Nothing in THIS file merges or pushes anything:
# `wave-plan` only PRINTS the integration commands, and `fleet-closeout` closes a wave out AFTER the
# owner merged the wave PR, through the existing sanctioned paths (lane-convert-ready, queue-checkoff,
# lane-remove, run-lock.sh release). The ONE writer of a wave branch is the sibling automate-wave.sh
# (`wave-build`, owner decision 2026-10-11): it sources this file for _lanes_wave_resolve, so it builds
# exactly the plan `wave-plan` prints, pushes only the wave branch and opens the wave PR; merging that
# PR stays the owner's.

# _lanes_base_of <checkout> — the base branch (origin/HEAD's name; `main` when unset).
_lanes_base_of() {
  local b; b="$(git -C "$1" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"; b="${b#origin/}"
  printf '%s' "${b:-main}"
}

# _lanes_rf_done <runfile> — 0 when the run file's `## Status:` line reads done.
_lanes_rf_done() { grep -qE '^## Status:[[:space:]]*done([^A-Za-z0-9_]|$)' "${1:-/dev/null}" 2>/dev/null; }

# _lanes_sync_primary <primary> — `git pull --ff-only` of the primary on its base branch; prints
# `pulled <base>` or `skipped — <reason>`. The refusal set mirrors automate-trail.sh's `_sync_primary`
# (closeout's step-4 sync): detached HEAD, another branch, tracked modifications, a failed fetch,
# already synced, a refused pull — never a reset, a stash, a checkout or a commit.
_lanes_sync_primary() {
  local p="$1" base cur st
  base="$(_lanes_base_of "$p")"
  cur="$(git -C "$p" symbolic-ref -q --short HEAD 2>/dev/null)"
  if [ -z "$cur" ]; then echo "skipped — primary checkout is on a detached HEAD"; return 0; fi
  if [ "$cur" != "$base" ]; then echo "skipped — primary checkout is on $cur, not $base"; return 0; fi
  if ! st="$(git -C "$p" status --porcelain --untracked-files=no 2>/dev/null)"; then echo "skipped — git status unreadable"; return 0; fi
  if [ -n "$st" ]; then echo "skipped — uncommitted tracked changes ($(printf '%s\n' "$st" | cut -c4- | head -3 | paste -sd ',' - | sed 's/,/, /g'))"; return 0; fi
  if ! git -C "$p" fetch -q origin >/dev/null 2>&1; then echo "skipped — git fetch failed"; return 0; fi
  if [ "$(git -C "$p" rev-parse -q --verify HEAD 2>/dev/null)" = "$(git -C "$p" rev-parse -q --verify "refs/remotes/origin/$base" 2>/dev/null)" ]; then
    echo "skipped — already synced ($base at origin/$base)"; return 0
  fi
  if ! git -C "$p" pull -q --ff-only origin "$base" >/dev/null 2>&1; then echo "skipped — git pull --ff-only refused (no reset attempted)"; return 0; fi
  echo "pulled $base"
}

# _lanes_append_once <runfile> <line> — progress-append unless that exact `- <line>` is already there
# (fleet-closeout re-runs on every --resume; its wave-level lines are recorded once). Fail-SAFE.
_lanes_append_once() {
  grep -qxF -- "- $2" "$1" 2>/dev/null && return 0
  bash "$HELPERS" progress-append "$1" "$2" >/dev/null 2>&1 || return 1
}

# _lanes_fc_finalize <parent_runfile> <primary> <meta branch, empty = mode off> — fleet-closeout's last
# write, run only once the parent `## Queue` has no `- [ ]` left and only while the wave lock is still
# held (the caller releases it right after, whatever this printed). It finalizes the parent exactly as
# the sequential loop's §6 "Termination" does, through the existing helpers (never a hand write):
# ONE validated `runfile-write` of a staged copy on which `current-wave --wave null` cleared the
# `- wave:` line, the first `## Status:` line became `## Status: done` and `current-set --pause-reason
# null` authored `pause_reason: null` (finalize-empty's staging — a failure at any step leaves the run
# file byte-unchanged); then `<ts> wave closed — Queue empty, run finalized`; then `trail-pr <rf>
# --reason done` (through the TRAIL seam, with this script's meta-sync, in the primary) printed and
# appended like finalize-empty's; then ONE `fleet closeout sweep (dry run): <sweep summary>` line (the
# caller's wave-end DRY sweep, af/39a — recorded here and nowhere else, so exactly one lands at done and
# it is this final wave's); then, branch mode OFF only, `trail-unstage <rf>`. Lines:
# `fleet-closeout: finalize — <outcome>` (one per step) | `fleet-closeout: finalize — skipped (already
# done)` (nothing written: a re-run never repeats the trail) | `fleet-closeout: finalize FAILED —
# <reason>` (nothing written — a refused write, or the run lock held by an owner other than
# `automate-lanes:<run_id>`; a FREE lock is taken first, so the write is always under it). Returns 0.
_lanes_fc_finalize() {
  local rf="$1" primary="$2" mb="$3" sw="${4:-}" tmp out ts l F="fleet-closeout: finalize FAILED —"
  if _lanes_rf_done "$rf"; then echo "fleet-closeout: finalize — skipped (already done)"; return 0; fi
  if grep -q '^- \[ \] ' "$rf" 2>/dev/null; then echo "fleet-closeout: finalize — skipped (Queue items remain)"; return 0; fi
  grep -q '^## Status:' "$rf" 2>/dev/null || { echo "$F the parent run file has no ## Status: line"; return 0; }
  # The write happens under the wave lock: held by this wave ⇒ go; free (a FAILED finalize's call already
  # released it) ⇒ take it, the caller's release drops it; held by anyone else ⇒ nothing written.
  local lk_st lk_own="automate-lanes:${rf##*/}"; lk_own="${lk_own%.md}"
  lk_st="$(bash "$RUN_LOCK" status --root "$primary" 2>/dev/null </dev/null | head -1)"
  case "$lk_st" in
    "LOCKED owner=$lk_own "*) ;;
    UNLOCKED)
      out="$(bash "$RUN_LOCK" acquire --owner "$lk_own" --root "$primary" 2>&1 </dev/null)" \
        || { echo "$F the wave lock could not be taken — $(printf '%s\n' "$out" | head -1) (nothing written)"; return 0; } ;;
    LOCKED*) l="${lk_st#LOCKED owner=}"; echo "$F the run lock is held by ${l%% *}, not $lk_own (nothing written)"; return 0 ;;
    *) echo "$F run lock status unreadable (nothing written)"; return 0 ;;
  esac
  tmp="$(mktemp "$rf.fc.XXXXXX" 2>/dev/null)" || { echo "$F cannot stage the rewrite"; return 0; }
  if ! awk '!st && /^## Status:/ { print "## Status: done"; st = 1; next } { print }' "$rf" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"; echo "$F cannot stage the rewrite"; return 0
  fi
  if ! out="$(bash "$HELPERS" current-wave "$tmp" --wave null 2>&1 </dev/null)" \
     || ! out="$(bash "$HELPERS" current-set "$tmp" --pause-reason null 2>&1 </dev/null)" \
     || ! out="$(bash "$HELPERS" runfile-write "$rf" < "$tmp" 2>&1)"; then
    rm -f "$tmp" "$tmp".*
    echo "$F $(printf '%s\n' "$out" | sed '/^$/d' | head -1 | cut -c1-200) (the run file is unchanged)"; return 0
  fi
  rm -f "$tmp"
  ts="$(now_utc)"
  bash "$HELPERS" progress-append "$rf" "$ts wave closed — Queue empty, run finalized" >/dev/null 2>&1 \
    || echo "fleet-closeout: WARNING — the finalize ## Progress line could not be appended" >&2
  echo "fleet-closeout: finalize — finalized (## Status: done, pause_reason: null, wave line cleared)"
  l="$(cd "$primary" && LOOMWRIGHT_META_SYNC_BIN="$META_SYNC" bash "$TRAIL" trail-pr "$rf" --reason done 2>/dev/null </dev/null | tail -n1)"
  l="${l:-trail-pr: skipped — no output}"
  echo "fleet-closeout: finalize — $l"
  bash "$HELPERS" progress-append "$rf" "$ts $l" >/dev/null 2>&1
  [ -n "$sw" ] || sw="sweep: summary — skipped: no summary line (sweep failed or printed nothing)"
  bash "$HELPERS" progress-append "$rf" "fleet closeout sweep (dry run): $sw" >/dev/null 2>&1 \
    || echo "fleet-closeout: WARNING — the sweep line could not be appended" >&2
  if [ -z "$mb" ]; then
    l="$(cd "$primary" && bash "$TRAIL" trail-unstage "$rf" 2>/dev/null </dev/null | tail -n1)"
    echo "fleet-closeout: finalize — ${l:-trail-unstage: skipped — no output}"
  fi
  return 0
}

# fleet-closeout <parent_runfile> — the wave close, run in the coordinator's PRIMARY checkout on every
# `/automate --resume` (stepwise, idempotent: each call does every step it can; nothing waits in-session).
# One `fleet-closeout: <step> — <detail>` line per lane and per step, in order:
#   1. pull        branch mode: `meta-sync.sh pull --branch <mode branch>`; failure (or mode unknown) ⇒
#                  `fleet-closeout: pull FAILED — <reason>`, exit 2, nothing else runs. Mode off: skipped.
#   2. per lane    (lane-status): already `## Status: done` ⇒ closed out. A `.meta-push-failed` marker ⇒
#                  `human — <lane> meta-push-failed: <reason>`. `merged` (or closeout's `awaiting_go`)
#                  with no live lane process and no live merge watcher ⇒ BACKSTOP: `lane-convert-ready
#                  <lane_dir>` — the existing sanctioned coordinator→lane closeout path (closeout
#                  --no-trail + A1 finalize + pushes), run again once when that call only converted a
#                  ready_for_release lane. `gone` ⇒ `human — <lane> gone (PR closed unmerged): lane-remove
#                  <lane_dir> --abandon` (never auto-abandoned). Anything else ⇒ `waiting — <lane> <state>`.
#   3. check-off   each closed-out lane whose item is still `- [ ]` in the parent `## Queue`:
#                  `queue-checkoff <parent_runfile> <item>` + `fleet closeout: <lane> <item> done (PR <url>)`.
#   4. sync        `git pull --ff-only` of the primary (_lanes_sync_primary's refusals are `skipped — …`).
#   5. remove      single-lane parent (`## Run Config` `- parallel: 1`) only, first: `fleet closeout: <lane>
#                  tokens TOTAL=<n|unknown>` appended once per lane (`fleet-closeout: tokens — <lane> TOTAL=<n>`);
#                  then `lane-remove <lane_dir>` per closed-out lane (no --stop: a live watcher or process
#                  refuses — `waiting — <lane> <refusal>`, re-checked on the next call). An unpushed-
#                  metadata refusal names its paths (`… (local_ahead <n>) — paths: <p>, …`).
#   6. wave end    only once EVERY lane reads removed/abandoned: `rmdir <primary>-lanes/<run_id>/` when
#                  empty, else `kept <dir> — contents: <names>`; `lane-status --leaks` (its first line
#                  appended as `fleet closeout leaks: <line>`, the primary's path written `<primary>`);
#                  a DRY `automate-trail.sh sweep --root <primary>` (never --apply): its summary line printed
#                  as `sweep — <summary>` on every wave end, and appended to the parent Progress as
#                  `fleet closeout sweep (dry run): <summary>` ONLY by the parent finalize below (so the one
#                  line at `## Status: done` is the final wave's; a failed / silent sweep reads `skipped: …`,
#                  exit unchanged); main health — the `ci` check of
#                  origin/<base> HEAD via gh: `failure` ⇒ `wave_paused: main_red after <sha>` appended and
#                  printed (no revert, no block); then, when the parent Queue has no `- [ ]` left,
#                  the parent FINALIZE under the still-held wave lock (_lanes_fc_finalize: `current-wave
#                  --wave null` + `## Status: done` + `pause_reason: null` in ONE validated runfile-write,
#                  `<ts> wave closed — Queue empty, run finalized`, `trail-pr --reason done`, branch mode
#                  off `trail-unstage`; `finalize — skipped (already done)` on a re-run, nothing written;
#                  `finalize FAILED — <reason>`, nothing written, exit unchanged), then — on every finalize
#                  outcome — `run-lock.sh release --owner "automate-lanes:<run_id>"` ⇒ `wave closed — lock
#                  released`. A Queue item left (the next wave) ⇒ no finalize, `lock kept — …`.
# Exit: 0 (done, or waiting — the lines say which) · 1 refused (bad parent run file) · 2 pull failed.
lanes_fleet_closeout() {
  local rf="${1:-}"
  [ -n "$rf" ] && [ "$#" -le 1 ] || die "usage: fleet-closeout <parent_runfile>"
  _lanes_parent_of "$rf" || { echo "fleet-closeout: refused — $LP_WHY"; return 1; }
  local parent="$LP_PARENT" primary="$LP_PRIMARY" table mb out rc tab doc closed="" n
  local lane path item run state lrf mk w pid st lpr detail single=0 tk
  tab="$(printf '\t')"
  rf="$primary/.supervisor/automate/$parent.md"; table="$primary/.supervisor/automate/$parent.lanes"
  _lanes_single_parent "$rf" && single=1   # `- parallel: 1` ⇒ the per-lane tokens line (step 5)
  _fc() { echo "fleet-closeout: $*"; }
  # #618: script events — a fixed code per failure line; `pass` (which closes the open threads of this
  # step) only when this call reported nothing worse. Lane-level lines are lane-remove's own events.
  local fc_bad=0
  _fc_ev() { [ "$1" = pass ] || fc_bad=1; LN_PRIMARY="$primary" _lanes_event fleet-closeout "$@"; }
  [ -f "$table" ] || { _fc "skipped — no lane table ($parent.lanes): no lane to close out"; return 0; }
  # 1. pull
  if ! mb="$(_lanes_meta_branch "$primary")"; then _fc "pull FAILED — metadata mode unknown"; _fc_ev fail pull_failed; return 2; fi
  if [ -n "$mb" ]; then
    out="$(bash "$META_SYNC" pull --branch "$mb" --root "$primary" 2>&1 </dev/null)"; rc=$?
    if [ "$rc" != 0 ]; then
      _fc "pull FAILED — $(printf '%s\n' "$out" | sed '/^$/d' | head -1 | cut -c1-200)${out:+ }(meta-sync exit $rc)"; _fc_ev fail pull_failed; return 2
    fi
    _fc "pull — pulled $mb"
  else _fc "pull — skipped (metadata mode off)"; fi
  # 2. per lane
  doc="$(_lanes_status_doc "$table" "$parent" "$primary")"
  while IFS="$tab" read -r lane path item run state; do
    [ -n "$lane" ] || continue
    lrf="$path/.supervisor/automate/$run.md"; mk="$path/.supervisor/automate/$run.meta-push-failed"
    case "$state" in removed|abandoned) _fc "lane — $lane $state"; continue ;; esac
    if [ -f "$mk" ]; then _fc "human — $lane meta-push-failed: $(head -1 "$mk" 2>/dev/null | cut -c1-200)"; continue; fi
    if _lanes_rf_done "$lrf"; then
      _fc "lane — $lane closed out (## Status: done)"; closed="$closed$lane$tab$path$tab$item$tab$run
"; continue
    fi
    case "$state" in
      merged|awaiting_go|done)
        pid="$(_lt_get "$table" "$lane" 5)"; st="$(_lt_get "$table" "$lane" 6)"
        if lanes_proc_alive "$pid" "$st" "$path"; then _fc "waiting — $lane live lane process (pid $pid)"; continue; fi
        w="$(_lanes_live_watchers "$path" | head -1)"
        if [ -n "$w" ]; then _fc "waiting — $lane live merge watcher (pid ${w%%"$tab"*})"; continue; fi
        out="$(bash "$SELF" lane-convert-ready "$path" 2>&1 </dev/null)"; rc=$?
        case "$(printf '%s\n' "$out" | tail -1)" in
          "lane-convert-ready: converted $lane to awaiting_merge"*)   # a ready_for_release lane: the merged re-run follows
            out="$(bash "$SELF" lane-convert-ready "$path" 2>&1 </dev/null)"; rc=$? ;;
        esac
        detail="$(printf '%s\n' "$out" | grep -E '^lane-convert-ready: (finalize|refused|FAILED)' | head -1)"
        [ -n "$detail" ] || detail="$(printf '%s\n' "$out" | grep '^lane-convert-ready: ' | tail -1)"
        if _lanes_rf_done "$lrf"; then
          _fc "backstop — $lane lane-convert-ready (exit $rc) — ${detail:-no output}; now ## Status: done"
          closed="$closed$lane$tab$path$tab$item$tab$run
"
        else
          case "$detail" in
            *"finalize skipped"*) _fc "human — $lane not finalized (exit $rc): $detail" ;;
            *) _fc "waiting — $lane backstop lane-convert-ready (exit $rc) — ${detail:-no output}" ;;
          esac
        fi ;;
      gone) _fc "human — $lane gone (PR closed unmerged): lane-remove $path --abandon" ;;
      *) _fc "waiting — $lane $state" ;;
    esac
  done <<EOF
$(jq -r '.lanes[] | [.lane, .path, .item, .run_id, .state] | @tsv' <<<"$doc" 2>/dev/null)
EOF
  # 3. parent check-off
  while IFS="$tab" read -r lane path item run; do
    [ -n "$lane" ] || continue
    if ! grep -qxF -- "- [ ] $item" "$rf" 2>/dev/null; then _fc "check-off — $lane $item already checked off"; continue; fi
    lpr="$(_lanes_dash "$(_lanes_runfile_fields "$path/.supervisor/automate/$run.md" | cut -f3)")"
    if out="$(bash "$HELPERS" queue-checkoff "$rf" "$item" 2>&1 </dev/null)" && ! grep -qxF -- "- [ ] $item" "$rf" 2>/dev/null; then
      bash "$HELPERS" progress-append "$rf" "fleet closeout: $lane $item done (PR ${lpr:-none recorded})" >/dev/null 2>&1 \
        || echo "fleet-closeout: WARNING — the ## Progress line for $lane could not be appended" >&2
      _fc "check-off — $lane $item"
    else
      _fc "check-off FAILED — $lane $item: $(printf '%s\n' "$out" | head -1)"; _fc_ev fail checkoff_failed
    fi
  done <<EOF
$closed
EOF
  # 4. primary sync
  _fc "sync — $(_lanes_sync_primary "$primary")"
  # 5. lane removal (closed-out lanes only; a refusal waits for the next call — never --stop, never a wait)
  while IFS="$tab" read -r lane path item run; do
    [ -n "$lane" ] || continue
    if [ "$single" = 1 ]; then   # BEFORE the removal: the TOTAL is read from the lane directory
      tk="$(_lanes_tokens_record "$rf" "$lane" "$path" "$run")"; [ -z "$tk" ] || _fc "tokens — $tk"
    fi
    out="$(bash "$SELF" lane-remove "$path" 2>&1 </dev/null)"; rc=$?
    if [ "$rc" = 0 ]; then _fc "remove — $lane removed (salvage kept under <primary>-lanes/$parent/salvage/)"
    else
      detail="$(printf '%s\n' "$out" | sed -n "s/^lane-remove: refused — $lane — //p" | head -1)"
      _fc "waiting — $lane ${detail:-$(printf '%s\n' "$out" | head -1)}"
    fi
  done <<EOF
$closed
EOF
  # 6. wave end — only once every lane of the table is removed / abandoned
  local left; left="$(awk -F'\t' '$1 ~ /^L[0-9][0-9]?$/ && $8 != "removed" && $8 != "abandoned" { printf "%s%s", (n++ ? ", " : ""), $1 }' "$table")"
  if [ -n "$left" ]; then _fc "waiting — lane(s) not removed yet: $left (re-run fleet-closeout on the next --resume)"; return 0; fi
  local ld="$primary-lanes/$parent" lk base sha cj concl line
  if [ ! -d "$ld" ]; then _fc "lanes-dir — already gone"
  elif rmdir "$ld" 2>/dev/null; then _fc "lanes-dir — removed (empty) $ld"
  else _fc "lanes-dir — kept $ld — contents: $(ls -1A "$ld" 2>/dev/null | paste -sd ',' - | sed 's/,/, /g')"; fi
  lk="$(bash "$SELF" lane-status "$rf" --leaks 2>/dev/null </dev/null | head -1)"
  lk="${lk:-leaks: unknown — lane-status --leaks printed nothing}"
  case "$lk" in *"$primary"*) lk="$(printf '%s' "$lk" | awk -v p="$primary" '{ while ((i = index($0, p)) > 0) $0 = substr($0, 1, i - 1) "<primary>" substr($0, i + length(p)); print }')" ;; esac
  _lanes_append_once "$rf" "fleet closeout leaks: $lk" || echo "fleet-closeout: WARNING — the leaks line could not be appended" >&2
  _fc "leaks — $lk"
  # af/39a: a DRY sweep (never --apply) of the primary's leftover plugin worktrees and branches — its
  # summary line printed on every wave end; the parent Progress records it ONLY at the parent finalize
  # (_lanes_fc_finalize, below), so a multi-wave run's done-time line is the final wave's, never a
  # frozen wave-1 snapshot. A sweep failure or silence is reported, never an exit-code change.
  local sw sweep_sh="${LOOMWRIGHT_LANES_SWEEP:-$HERE/automate-trail.sh}"
  sw="$(bash "$sweep_sh" sweep --root "$primary" 2>/dev/null </dev/null | tail -n1)"
  case "$sw" in "sweep: summary — "*) ;; *) sw="sweep: summary — skipped: no summary line (sweep failed or printed nothing)" ;; esac
  case "$sw" in *"$primary"*) sw="$(printf '%s' "$sw" | awk -v p="$primary" '{ while ((i = index($0, p)) > 0) $0 = substr($0, 1, i - 1) "<primary>" substr($0, i + length(p)); print }')" ;; esac
  _fc "sweep — $sw"
  base="$(_lanes_base_of "$primary")"
  sha="$(git -C "$primary" rev-parse -q --verify "refs/remotes/origin/$base" 2>/dev/null)"
  if [ -z "$sha" ]; then _fc "main health — unknown (origin/$base unreadable)"
  else
    cj="$(cd "$primary" && "$LANES_GH" api "repos/{owner}/{repo}/commits/$sha/check-runs?check_name=ci" 2>/dev/null </dev/null)" || cj=""
    concl="$(jq -r '[.check_runs[]? | select(.name == "ci")] | sort_by(.started_at // "") | last
      | if . == null then "none" else (.conclusion // "pending") end' <<<"$cj" 2>/dev/null)"
    case "$concl" in
      failure)
        line="wave_paused: main_red after $sha"
        _lanes_append_once "$rf" "$line" || echo "fleet-closeout: WARNING — the main_red line could not be appended" >&2
        _fc "$line"; _fc_ev warn main_red ;;
      "") _fc "main health — unknown (ci check of origin/$base ${sha:0:12} unreadable)" ;;
      *) _fc "main health — ci $concl on origin/$base ${sha:0:12}" ;;
    esac
  fi
  n="$(grep -c '^- \[ \] ' "$rf" 2>/dev/null)"; n="${n:-0}"
  if [ "$n" != 0 ]; then
    _fc "lock kept — $n Queue item(s) remain unchecked (the next wave runs under it)"
    [ "$fc_bad" = 1 ] || _fc_ev pass ok
    return 0
  fi
  # The Queue is empty: finalize the parent UNDER the wave lock, then release it on EVERY outcome —
  # a refused finalize prints its FAILED line and never strands the lock.
  local fo; fo="$(_lanes_fc_finalize "$rf" "$primary" "$mb" "$sw")"
  [ -z "$fo" ] || printf '%s\n' "$fo"
  case "$fo" in *"finalize FAILED"*) _fc_ev fail finalize_failed ;; esac
  if out="$(bash "$RUN_LOCK" release --owner "automate-lanes:$parent" --root "$primary" 2>&1 </dev/null)"; then
    _fc "wave closed — lock released"
    [ "$fc_bad" = 1 ] || _fc_ev pass ok
  else
    _fc "lock release FAILED — $(printf '%s\n' "$out" | head -1)"; _fc_ev fail lock_release_failed
  fi
  return 0
}

# _lanes_wave_resolve <parent_runfile> [<wave branch>] — the ONE wave resolver. `wave-plan` (below) and
# automate-wave.sh's `wave-build` (which sources this file) both read the wave through it, so the
# printed plan and the executed build can never disagree on the lanes, their order, the head shas, the
# base or the branch name. READ-ONLY: it reads the lane table, the parent `## Current` wave line
# (`- wave: <k> | items: …`; absent ⇒ the lane table order, wave 1), each lane's `## Current` pr and
# that PR's head + state (ONE `gh pr view <pr> --json headRefOid,state` read per lane). Sets WV_PARENT,
# WV_PRIMARY, WV_RF, WV_TABLE, WV_BASE, WV_K, WV_WB (default `wave/<run_id>-w<k>`), WV_SRC and WV_ROWS —
# one TSV row per wave entry, in planner order: <kind> <lane> <path> <item> <run_id> <pr> <num> <sha>
# <pr_state>, every empty field `-`. kind: `ok` · `nolane` (a wave item with no lane-table row) · `nopr`
# (no numeric PR in the lane's run file) · `nohead` (the head sha unreadable). Returns 1 with WV_WHY
# when it refuses (bad parent run file, no lane table, bad branch name).
_lanes_wave_resolve() {
  local rf="${1:-}" wb="${2:-}" wl items item v rows="" tab lane path run pr num j sha st
  WV_WHY=""; WV_ROWS=""; WV_SRC=""
  _lanes_parent_of "$rf" || { WV_WHY="$LP_WHY"; return 1; }
  WV_PARENT="$LP_PARENT"; WV_PRIMARY="$LP_PRIMARY"
  WV_RF="$WV_PRIMARY/.supervisor/automate/$WV_PARENT.md"; WV_TABLE="$WV_PRIMARY/.supervisor/automate/$WV_PARENT.lanes"
  tab="$(printf '\t')"
  [ -f "$WV_TABLE" ] || { WV_WHY="no lane table ($WV_PARENT.lanes)"; return 1; }
  WV_BASE="$(_lanes_base_of "$WV_PRIMARY")"
  wl="$(awk '/^## / { sec = $0; next } sec == "## Current" && /^- wave: / { print; exit }' "$WV_RF" 2>/dev/null)"
  WV_K="$(printf '%s' "$wl" | sed -n 's/^- wave: *\([0-9][0-9]*\) *|.*/\1/p; s/^- wave: *\([0-9][0-9]*\) *$/\1/p' | head -1)"
  items="$(printf '%s' "$wl" | sed -n 's/^- wave: [^|]*| *items: *//p' \
    | awk '{ n = split($0, a, /, */); for (i = 1; i <= n; i++) { sub(/ +$/, "", a[i]); if (a[i] != "") print a[i] } }')"
  [ -n "$WV_K" ] || WV_K=1
  [ -n "$wb" ] || wb="wave/$WV_PARENT-w$WV_K"
  git check-ref-format --branch "$wb" >/dev/null 2>&1 || { WV_WHY="'$wb' is not a valid branch name"; return 1; }
  WV_WB="$wb"
  if [ -n "$items" ]; then
    WV_SRC="from ## Current"
    while IFS= read -r item; do
      [ -n "$item" ] || continue
      v="$(awk -F'\t' -v i="$item" '$1 ~ /^L[0-9][0-9]?$/ && $3 == i { r = $1 "\t" $2 "\t" $3 "\t" $4 } END { if (r != "") print r }' "$WV_TABLE")"
      if [ -n "$v" ]; then rows="$rows$v
"; else rows="$rows-$tab-$tab$item$tab-
"; fi
    done <<<"$items"
  else
    WV_SRC="no ## Current wave items — lane table order"
    rows="$(awk -F'\t' '$1 ~ /^L[0-9][0-9]?$/ { print $1 "\t" $2 "\t" $3 "\t" $4 }' "$WV_TABLE")"
  fi
  while IFS="$tab" read -r lane path item run; do
    [ -n "$lane$item" ] || continue
    if [ "$lane" = - ]; then WV_ROWS="${WV_ROWS}nolane$tab-$tab-$tab$item$tab-$tab-$tab-$tab-$tab-
"; continue; fi
    pr="$(_lanes_dash "$(_lanes_runfile_fields "$path/.supervisor/automate/$run.md" | cut -f3)")"
    num="${pr##*/}"
    case "$num" in ''|*[!0-9]*)
      WV_ROWS="${WV_ROWS}nopr$tab$lane$tab$path$tab$item$tab$run$tab${pr:--}$tab-$tab-$tab-
"; continue ;;
    esac
    j="$("$LANES_GH" pr view "$pr" --json headRefOid,state 2>/dev/null </dev/null)"
    sha="$(jq -r '.headRefOid // empty' <<<"$j" 2>/dev/null)"; st="$(jq -r '.state // empty' <<<"$j" 2>/dev/null)"
    case "$sha" in [0-9a-f]*) ;; *) sha="" ;; esac
    if [ "${#sha}" != 40 ] || [ -n "$(printf '%s' "$sha" | tr -d '0-9a-f')" ]; then
      WV_ROWS="${WV_ROWS}nohead$tab$lane$tab$path$tab$item$tab$run$tab$pr$tab$num$tab-$tab${st:--}
"; continue
    fi
    WV_ROWS="${WV_ROWS}ok$tab$lane$tab$path$tab$item$tab$run$tab$pr$tab$num$tab$sha$tab${st:--}
"
  done <<EOF
$rows
EOF
  return 0
}

# _lanes_wave_overlap — after _lanes_wave_resolve: which files more than one lane of THIS wave changed.
# Lanes of one wave share one base and never see each other, so a file two of them changed ends either
# in a STOPPED wave-build (a textual conflict) or in a clean merge nobody reviewed as one change; drift
# into a file no other wave lane changed is harmless here (a later wave starts from the merged base).
# Advisory and WARN-ONLY (owner decision 2026-10-17): it never refuses, holds or reorders a lane.
# READ-ONLY: per `ok` row ONE `gh pr diff <pr> --name-only` read (changelog.d/ dropped) and the lane's
# declared set through readiness.sh's _lanes_declared + _lanes_is_declared — the SAME reader and matcher
# lane-readiness's scope fence uses (Touches as the planner reserved it + the lane's brief `path:` lines),
# so a file is "declared" in one exactly when it is in the other. Sets WO_N (the number of shared files) and
# WO_LINES, one `<kind> — <detail>` line each, in this order:
#   overlap — <file> changed by L1 (outside its Touches), L3 (declared)   one per shared file, by path
#   drift — <lane> changed <n> file(s) outside its Touches; no other lane of this wave changed them
#           (`with its Touches unknown` in place of `outside its Touches` for an unknown-Touches lane)
#   overlap — NOT-RUN — <lane> PR #<n> diff unreadable                   that lane is left out
#   overlap — none — no file is changed by more than one lane of this wave   (no shared file, every diff read)
# A lane's annotation is `declared` (Touches or brief), `outside its Touches`, or `Touches unknown` (its
# Touches section is unknown to the planner, which ran it alone — so it should share no file). Returns 0.
_lanes_wave_overlap() {
  local tab kind lane path item run pr num sha st tmp f fs unread=""
  WO_LINES=""; WO_N=0; tab="$(printf '\t')"
  tmp="$(mktemp -d 2>/dev/null)" || { WO_LINES="overlap — NOT-RUN — no temp dir"; return 0; }
  : > "$tmp/all"
  while IFS="$tab" read -r kind lane path item run pr num sha st; do
    [ "$kind" = ok ] || continue
    if ! "$LANES_GH" pr diff "$pr" --name-only > "$tmp/f" 2>/dev/null </dev/null; then
      unread="${unread}overlap — NOT-RUN — $lane PR #$num diff unreadable
"; continue
    fi
    _lanes_declared "$path" "$item" "$(_lanes_brief_of "$path" "$item")" "$tmp/d"
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      case "$f" in changelog.d/*) continue ;; esac
      if _lanes_is_declared "$f" "$tmp/d"; then fs=declared
      elif [ "$LD_TOUCHES" = known ]; then fs="outside its Touches"
      else fs="Touches unknown"; fi
      printf '%s\t%s\t%s\n' "$f" "$lane" "$fs" >> "$tmp/all"
    done < "$tmp/f"
  done <<EOF
$WV_ROWS
EOF
  # Shared files: one line per path (path order), its lanes in planner order (the order of $tmp/all).
  env LC_ALL=C awk -F'\t' '{ if (!($1 in C)) P[++np] = $1; C[$1]++; L[$1] = L[$1] (C[$1] > 1 ? ", " : "") $2 " (" $3 ")" }
    END { for (i = 1; i <= np; i++) if (C[P[i]] > 1) print P[i] "\t" L[P[i]] }' "$tmp/all" | env LC_ALL=C sort > "$tmp/shared"
  WO_N="$(grep -c . "$tmp/shared" | tr -d ' ')"
  {
    [ "$WO_N" != 0 ] || [ -n "$unread" ] || echo "overlap — none — no file is changed by more than one lane of this wave"
    awk -F'\t' '{ print "overlap — " $1 " changed by " $2 }' "$tmp/shared"
    # Harmless drift: per lane (planner order), the files outside its Touches no other lane changed.
    WO_SF="$tmp/shared" env LC_ALL=C awk -F'\t' '
      BEGIN { while ((getline x < ENVIRON["WO_SF"]) > 0) { split(x, a, "\t"); S[a[1]] = 1 } }
      $3 != "declared" && !($1 in S) { if (!($2 in N)) O[++no] = $2; N[$2]++; if ($3 == "Touches unknown") U[$2] = 1 }
      END { for (i = 1; i <= no; i++) printf "drift — %s changed %d file(s) %s; no other lane of this wave changed them\n", O[i], N[O[i]],
              (O[i] in U) ? "with its Touches unknown" : "outside its Touches" }' "$tmp/all"
    printf '%s' "$unread"
  } > "$tmp/out"
  WO_LINES="$(cat "$tmp/out")"
  rm -rf "$tmp"
  return 0
}

# wave-plan <parent_runfile> [--wave-branch <name>] — Part S, READ-ONLY (owner decision 2026-10-10: the
# operator merges; since then `wave-build` in automate-wave.sh runs these same steps, and this stays the
# read-only preview and the manual fallback). Executes no git mutation, no push and no gh write: it
# resolves the wave with _lanes_wave_resolve (above — the lane table, the parent `## Current` wave line,
# each lane's `## Current` pr and that PR's head sha, a `gh pr view` read) and PRINTS the operator's
# commands: fetch, `git checkout -b <wave branch, default wave/<run_id>-w<k>> origin/<base>`, one
# `git merge --no-ff <exact head sha> -m "Merge lane <L> (<item>) PR #<n>"` per lane in planner order
# (an unreadable sha ⇒ `# <lane>: head unreadable — resolve before integrating`, that lane skipped),
# `bash scripts/ci-local.sh`, the release step (`bash scripts/bump-version.sh` only when the repo has
# it, else `# run this project's release step`), the push and `gh pr create`, then the conflict rules.
# Before the conflict rules it prints the same-wave overlap check (_lanes_wave_overlap above) as `# overlap
# — …` / `# drift — …` comment lines — the files more than one lane of this wave changed, warn-only.
# Exit 0 printed · 1 refused (bad parent run file, no lane table, bad branch name).
lanes_wave_plan() {
  local rf="" wb=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --wave-branch) _lanes_need "$#" wave-plan "$1"; wb="$2"; shift 2 ;;
      -*) echo "wave-plan: refused — unknown flag '$1'"; return 1 ;;
      *) [ -z "$rf" ] || { echo "wave-plan: refused — unexpected argument '$1'"; return 1; }; rf="$1"; shift ;;
    esac
  done
  _lanes_wave_resolve "$rf" "$wb" || { echo "wave-plan: refused — $WV_WHY"; return 1; }
  local parent="$WV_PARENT" primary="$WV_PRIMARY" base="$WV_BASE" k="$WV_K" tab kind lane path item run pr num sha st msg
  wb="$WV_WB"; tab="$(printf '\t')"
  echo "# wave-plan: $parent wave $k ($WV_SRC) — READ-ONLY: nothing below was run; the operator runs it"
  echo "git fetch origin"
  echo "git checkout -b $wb origin/$base"
  while IFS="$tab" read -r kind lane path item run pr num sha st; do
    case "$kind" in
      nolane) echo "# $item: no lane in $parent.lanes — skipped" ;;
      nopr) echo "# $lane: no PR recorded in its run file — resolve before integrating" ;;
      nohead) echo "# $lane: head unreadable — resolve before integrating" ;;
      ok) msg="$(printf 'Merge lane %s (%s) PR #%s' "$lane" "$item" "$num" | sed 's/[\\"$`]/\\&/g')"
          printf 'git merge --no-ff %s -m "%s"\n' "$sha" "$msg" ;;
    esac
  done <<EOF
$WV_ROWS
EOF
  echo "bash scripts/ci-local.sh"
  if [ -f "$primary/scripts/bump-version.sh" ]; then echo "bash scripts/bump-version.sh"
  else echo "# run this project's release step"; fi
  echo "git push -u origin $wb"
  echo "gh pr create --base $base --head $wb"
  # The same-wave overlap check wave-build prints before it creates anything (warn-only).
  _lanes_wave_overlap
  printf '%s\n' "$WO_LINES" | sed '/^$/d; s/^/# /'
  echo "# Conflict rules (Part S):"
  echo "#   - a marker-only conflict is resolved in the merge commit itself"
  echo "#   - anything larger stops the integration: hand it to the owner"
  echo "#   - never rewrite or push a lane branch"
  echo "#   - a lane broken on the wave branch is fixed on its own PR, and its new head is re-merged"
  return 0
}

