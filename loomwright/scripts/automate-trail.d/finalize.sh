# --------------------------------------------------------------------------- #
# finalize-empty (SKILL §1.5 / §3 "`done`" / §4 step 1 — `resume-glob --finalize`)
# --------------------------------------------------------------------------- #
# finalize-empty <runfile> — the second writer of `## Status: done` (the first is
# the §6 "Termination" exit of a live loop). `closeout` never writes `done`, even
# when it checks off the last Queue item: it leaves `## Status: paused`,
# `pause_reason: awaiting_go`, `## Current` item `status: done` (§3 "After a
# close-out"). This finalizes exactly that state and nothing else. Fires ONLY when
# ALL hold: `## Status: paused`, `pause_reason: awaiting_go`, `remaining` 0 (no
# `- [ ]` row), and the `## Current` item line's `status: done` — re-checked under
# the lock. Then, in order: `run-lock.sh acquire --owner automate-finalize:<run_id>`
# (held ⇒ one skipped line, nothing written); ONE validated rewrite through
# `runfile-write` (`## Status: done`, `## Current` `- pause_reason: null` — that
# line authored by `current-set --pause-reason null` on the staged copy; every
# other byte unchanged); `progress-append "<ts> auto-finalized: queue empty after
# closeout"`; `trail-pr <runfile> --reason done` (the SAME call the Queue-resolved
# termination makes) and its line appended; ONE `<ts> sweep (dry run): <summary>`
# Progress line (sweep_run, dry — af/39a); branch mode OFF only, `trail-unstage
# <runfile>` (this is usually a FOREIGN run finalized from the current run's RESUME:
# its staged trail blobs would ride into the current run's next commit and make
# `_sync_primary` see a dirty index); the lock released in a trap.
# Prints `finalize-empty: finalized <runfile>` + the trail (+ unstage) lines, or ONE
# `finalize-empty: skipped — <reason>` line. Always exit 0 (fail-SAFE emitter).
FE_ROOT=""
FE_OWNER=""
FE_LOCKED=0
fe_release() {
  if [ "$FE_LOCKED" -eq 1 ] && [ -n "$FE_OWNER" ]; then
    _run_lock_in "$FE_ROOT" release --owner "$FE_OWNER" >/dev/null 2>&1
  fi
  FE_LOCKED=0
  return 0
}

# _fe_ineligible <runfile> — prints why the run is NOT a finalize candidate
# (nothing when it is). Read-only; the `skipped — <reason>` text.
_fe_ineligible() {
  local rf="$1" st reason n cl cs
  st="$(sed -n 's/^## Status:[[:space:]]*\([A-Za-z_]*\).*/\1/p' "$rf" 2>/dev/null | head -n1)"
  if [ "$st" != "paused" ]; then echo "not paused"; return 0; fi
  reason="$(awk '/^## Current/{c=1;next} /^## /{c=0} c && /^- pause_reason:/{sub(/^- pause_reason:[[:space:]]*/,""); sub(/[[:space:]]+$/,""); print; exit}' "$rf" 2>/dev/null)"
  if [ "$reason" != "awaiting_go" ]; then echo "pause_reason ${reason:-absent}, not awaiting_go"; return 0; fi
  n="$(grep -c '^- \[ \] ' "$rf" 2>/dev/null)"; n="${n:-0}"
  if [ "$n" != "0" ]; then echo "$n unchecked item(s) remain"; return 0; fi
  cl="$(awk '/^## Current/{c=1;next} /^## /{c=0} c && /^- item: /{print; exit}' "$rf" 2>/dev/null)"
  cs="$(printf '%s\n' "$cl" | awk 'BEGIN{FS=" [|] "} {for(i=1;i<=NF;i++) if (index($i, "status: ")==1) {print substr($i, 9); exit}}')"
  if [ "$cs" != "done" ]; then echo "## Current status ${cs:-absent}, not done"; return 0; fi
  return 0
}

# _in_lane_clone <root> — succeeds when <root> is a lane clone of `/automate
# --parallel N` (parallel-automate/05, D2): its `.supervisor/lane.json` marker is
# present (the file `automate-lanes.sh lane-info` prints; absent ⇒ not a lane —
# never guessed from the path or the run id).
_in_lane_clone() { [ -f "$1/.supervisor/lane.json" ]; }

# _lane_run_id <root> — the lane marker's `run_id`, or empty when absent/unreadable.
_lane_run_id() {
  [ -f "$1/.supervisor/lane.json" ] || return 0
  jq -r '.run_id // empty | strings' "$1/.supervisor/lane.json" 2>/dev/null | head -n1
}

finalize_empty() {
  local runfile="${1:-}" S="finalize-empty: skipped —"
  if [ -z "$runfile" ] || [ ! -f "$runfile" ]; then echo "$S run file not found"; return 0; fi
  local rf_dir rf_abs root rf_rel run_id why
  # Eligibility first (read-only): an ineligible run is a plain skip whatever the
  # checkout looks like, so resume-glob --finalize stays silent about it.
  why="$(_fe_ineligible "$runfile")"
  if [ -n "$why" ]; then echo "$S $why"; return 0; fi
  if ! command -v git >/dev/null 2>&1; then echo "$S git unavailable"; return 0; fi
  rf_dir="$(cd "$(dirname "$runfile")" 2>/dev/null && pwd -P)" || { echo "$S run file not found"; return 0; }
  rf_abs="$rf_dir/$(basename "$runfile")"
  root="$(git -C "$rf_dir" rev-parse --show-toplevel 2>/dev/null)"
  if [ -z "$root" ]; then echo "$S not a git checkout"; return 0; fi
  root="$(cd "$root" && pwd -P)"
  case "$rf_abs" in "$root"/*) rf_rel="${rf_abs#"$root"/}" ;; *) echo "$S run file outside the checkout"; return 0 ;; esac
  run_id="$(basename "$runfile" .md)"
  cd "$root" || { echo "$S cannot enter checkout"; return 0; }
  # parallel-automate/05: inside a lane clone only the lane's OWN run (lane.json
  # run_id) may be finalized; another run's file (or an unreadable run_id) is refused.
  if _in_lane_clone "$root" && [ "$(_lane_run_id "$root")" != "$run_id" ]; then
    echo "$S lane clone (not this lane's run)"; return 0
  fi
  why="$(_fe_ineligible "$rf_rel")"
  if [ -n "$why" ]; then echo "$S $why"; return 0; fi
  local HLP="$HERE/automate-helpers.sh"

  FE_ROOT="$root"; FE_OWNER="automate-finalize:$run_id"
  local lk rc holder
  lk="$(_run_lock_in "$root" acquire --owner "$FE_OWNER" 2>/dev/null)"; rc=$?
  if [ "$rc" -ne 0 ]; then
    holder="$(printf '%s\n' "$lk" | sed -n 's/.*run_lock_held owner=\([^ ]*\).*/\1/p' | head -n1)"
    echo "$S run lock held by ${holder:-unknown}"; return 0
  fi
  FE_LOCKED=1
  trap fe_release EXIT
  # Re-check under the lock: a closeout/PICK may have moved the file in between.
  why="$(_fe_ineligible "$rf_rel")"
  if [ -n "$why" ]; then fe_release; trap - EXIT; echo "$S $why"; return 0; fi

  # ONE validated rewrite of the real file: the first `## Status:` line's `paused`
  # → `done` (any trailing text kept) and `## Current`'s `- pause_reason:` → `null`.
  # The pause_reason line is authored by `current-set --pause-reason null` (the
  # run-level form — SKILL §3: every pause_reason write is a current-set call),
  # run against the STAGED copy so the run file still changes in one atomic
  # `runfile-write`: a failure at any step leaves it byte-unchanged and the run
  # still eligible, so a later `--finalize` retries cleanly. Staged to a file and
  # redirected — never a `generator | runfile-write` pipe (§3).
  local tmp; tmp="$(mktemp "${rf_abs}.fe.XXXXXX")" || { fe_release; trap - EXIT; echo "$S cannot stage the rewrite"; return 0; }
  if ! awk '
      !st && /^## Status:/ { sub(/^## Status:[[:space:]]*paused/, "## Status: done"); st=1; print; next }
      { print }' "$rf_rel" > "$tmp" \
     || ! grep -q '^## Status: done' "$tmp" \
     || ! bash "$HLP" current-set "$tmp" --pause-reason null >/dev/null 2>&1 \
     || ! bash "$HLP" runfile-write "$rf_rel" < "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"; fe_release; trap - EXIT
    echo "$S runfile-write refused"; return 0
  fi
  rm -f "$tmp"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  bash "$HLP" progress-append "$rf_rel" "$ts auto-finalized: queue empty after closeout" >/dev/null 2>&1
  echo "finalize-empty: finalized $runfile"
  # ORDER (automate-followups/36 A4 — kept on purpose): `## Status: done` is written ABOVE,
  # BEFORE trail-pr, because the trail PR is what carries that stamp to main; a trail cut
  # first would record `paused` and leave the done stamp uncommitted. Consequence: a FAILED
  # trail-pr is NOT retried by a later `resume-glob --finalize` (the run is no longer paused,
  # so _fe_ineligible skips it). Its failure line is appended to ## Progress below and printed;
  # the recovery is a hand `automate-helpers.sh trail-pr <runfile> --reason done` (idempotent).
  # The §6 "Termination" exit of a live loop has the same order and the same recovery.
  local l
  l="$(bash "$HLP" trail-pr "$rf_abs" --reason done 2>/dev/null | tail -n1)"
  [ -n "$l" ] || l="trail-pr: skipped — no output"
  echo "$l"
  bash "$HLP" progress-append "$rf_rel" "$ts $l" >/dev/null 2>&1
  # af/39a: ONE dry-run sweep summary per run end, appended AFTER the trail line —
  # never inside the staged runfile rewrite above, never `--apply`. A subshell, so
  # the sweep can neither move this function's cwd nor touch its EXIT trap.
  local sw
  sw="$( (sweep_run --root "$root") 2>/dev/null | tail -n1)"
  case "$sw" in "sweep: summary — "*) ;; *) sw="sweep: summary — skipped: no output" ;; esac
  bash "$HLP" progress-append "$rf_rel" "$ts sweep (dry run): $sw" >/dev/null 2>&1
  if [ "$(_branch_mode "$root")" = "off" ]; then
    l="$(bash "$HLP" trail-unstage "$rf_abs" 2>/dev/null | tail -n1)"
    echo "${l:-trail-unstage: skipped — no output}"
  fi
  fe_release; trap - EXIT
  return 0
}

# --------------------------------------------------------------------------- #
# closeout-others (SKILL §1.5 / §4 "Start order" / §8 — the cross-run close-out)
# --------------------------------------------------------------------------- #
# closeout-others <automate_dir> [--record <runfile>] — at start, BEFORE the PICK
# lock: for every `resume-glob` run file other than --record's whose `## Current`
# item line names a non-null item, a non-null `…/pull/<n>` pr, a status other than
# `done`, and whose PR `reconcile-item` reads `merged`, runs `closeout <that
# runfile> <item> <pr>` through the dispatcher (NO --session-id: its own
# `automate-closeout:<run_id>` lock and its own trail), then — branch mode OFF only
# — `trail-unstage <that runfile>` (a foreign run's staged trail blobs would ride
# into the current run's next commit and make `_sync_primary` see a dirty index).
# Per close-out: `closeout-others: <run_id> <item> <pr>`, that closeout's lines, the
# unstage line, that closeout's own `closeout-classify` answer (`complete`, its
# `leftover` rows, or a `run_lock_held` row — classified per invocation, never
# interleaved), and ONE record line `cross-run closeout <run_id> <item>: <complete |
# leftover <step> — <detail> | run_lock_held — <detail>; retried at the next start>`.
# A `run_lock_held` answer (a LIVE process holds the run lock) is not a leftover: the
# engine's close-out leftover gate never sees it, nothing parks, and the next start's
# closeout-others retries that run (its ## Current still names the merged item)
# — `closeout-others: recorded — …` when appended to --record's run file,
# `closeout-others: record — …` when there is no such file yet. The record line
# carries NO PR URL (a URL in a leftover detail becomes `<url>`), so
# `current-rebuild` can never attach another run's PR. Anything else (OPEN,
# closed-unmerged, unreadable, done, null) ⇒ that run is untouched and prints
# nothing. Never touches another run's Queue beyond closeout's own check-off.
# Always exit 0.
closeout_others() {
  local dir="" rec="" S="closeout-others: skipped —"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --record) rec="${2:-}"; shift 2 || shift ;;
      *) [ -z "$dir" ] && dir="$1"; shift ;;
    esac
  done
  if [ -z "$dir" ] || [ ! -d "$dir" ]; then echo "$S automate dir not found"; return 0; fi
  if ! command -v git >/dev/null 2>&1; then echo "$S git unavailable"; return 0; fi
  local d_abs root rec_abs="" HLP="$HERE/automate-helpers.sh"
  d_abs="$(cd "$dir" 2>/dev/null && pwd -P)" || { echo "$S automate dir not found"; return 0; }
  root="$(git -C "$d_abs" rev-parse --show-toplevel 2>/dev/null)"
  if [ -z "$root" ]; then echo "$S not a git checkout"; return 0; fi
  root="$(cd "$root" && pwd -P)"
  if [ -n "$rec" ] && [ -f "$rec" ]; then
    rec_abs="$(cd "$(dirname "$rec")" 2>/dev/null && pwd -P)/$(basename "$rec")"
  fi
  cd "$root" || { echo "$S cannot enter checkout"; return 0; }
  # parallel-automate/05 (Scope 3 amendment): a lane clone never closes out other
  # runs — the coordinator does that ONCE, in the primary, before the wave launches.
  # A marker `lane-info` rejects (wrong schema_version, no string run_id) still skips —
  # closing other runs out from inside a broken lane clone is the unsafe side — but the
  # line says so, instead of claiming a lane that `lane-info` reports is not one.
  if _in_lane_clone "$root"; then
    if bash "$HERE/automate-lanes.sh" lane-info --root "$root" >/dev/null 2>&1; then echo "$S lane clone"
    else echo "$S lane clone marker .supervisor/lane.json is not valid (lane-info: not a lane) — fix or remove it"; fi
    return 0
  fi
  local bm; bm="$(_branch_mode "$root")"
  local cands f cl item pr st run_id out verdict first held summ rl l tab=$'\t'
  cands="$(bash "$HLP" resume-glob "$d_abs" 2>/dev/null)"
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    if [ -n "$rec_abs" ] && [ "$f" = "$rec_abs" ]; then continue; fi
    cl="$(awk '/^## Current/{c=1;next} /^## /{c=0} c && /^- item: /{print; exit}' "$f" 2>/dev/null)"
    [ -n "$cl" ] || continue
    item="$(printf '%s\n' "$cl" | awk 'BEGIN{FS=" [|] "} {sub(/^- /,""); for(i=1;i<=NF;i++) if (index($i, "item: ")==1) {print substr($i, 7); exit}}')"
    pr="$(printf '%s\n' "$cl" | awk 'BEGIN{FS=" [|] "} {for(i=1;i<=NF;i++) if (index($i, "pr: ")==1) {print substr($i, 5); exit}}')"
    st="$(printf '%s\n' "$cl" | awk 'BEGIN{FS=" [|] "} {for(i=1;i<=NF;i++) if (index($i, "status: ")==1) {print substr($i, 9); exit}}')"
    [ -n "$item" ] && [ "$item" != null ] || continue
    case "$pr" in http://*/pull/*|https://*/pull/*) ;; *) continue ;; esac
    [ "$st" != done ] || continue
    [ "$(bash "$HLP" reconcile-item "$pr" 2>/dev/null | tail -n1)" = merged ] || continue
    run_id="$(basename "$f" .md)"
    echo "closeout-others: $run_id $item $pr"
    out="$(bash "$HLP" closeout "$f" "$item" "$pr" 2>/dev/null)"
    [ -n "$out" ] && printf '%s\n' "$out"
    if [ "$bm" = off ]; then
      l="$(bash "$HLP" trail-unstage "$f" 2>/dev/null | tail -n1)"
      echo "${l:-trail-unstage: skipped — no output}"
    fi
    verdict="$(printf '%s\n' "$out" | bash "$HLP" closeout-classify --run "$run_id" --item "$item" --pr "$pr" 2>/dev/null)"
    [ -n "$verdict" ] || verdict="leftover$tab$run_id$tab$item$tab$pr${tab}classify${tab}closeout-classify printed nothing"
    printf '%s\n' "$verdict"
    first="$(printf '%s\n' "$verdict" | grep -m1 "^leftover$tab")"
    held="$(printf '%s\n' "$verdict" | grep -m1 "^run_lock_held$tab")"
    if [ "$verdict" = complete ]; then
      summ="complete"
    elif [ -z "$first" ] && [ -n "$held" ]; then
      summ="run_lock_held — $(printf '%s' "$held" | cut -f6-); retried at the next start"
      summ="$(printf '%s' "$summ" | sed -E 's#https?://[^[:space:]]+#<url>#g')"
    else
      summ="leftover $(printf '%s' "$first" | cut -f5) — $(printf '%s' "$first" | cut -f6-)"
      summ="$(printf '%s' "$summ" | sed -E 's#https?://[^[:space:]]+#<url>#g')"
    fi
    rl="cross-run closeout $run_id $item: $summ"
    if [ -n "$rec_abs" ] && bash "$HLP" progress-append "$rec_abs" "$(date -u +%Y-%m-%dT%H:%M:%SZ) $rl" >/dev/null 2>&1; then
      echo "closeout-others: recorded — $rl"
    else
      echo "closeout-others: record — $rl"
    fi
  done <<EOF
$cands
EOF
  return 0
}

