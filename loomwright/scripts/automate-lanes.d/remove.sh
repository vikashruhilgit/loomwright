# ==================================================================================================
# lane-remove <lane_dir> [--stop] [--abandon]
_lanes_stop_pid() { # <pid> <label> — TERM, then KILL after the grace period
  local p="$1" g="${LOOMWRIGHT_LANES_STOP_GRACE_S:-60}" i=0
  case "$g" in ''|*[!0-9]*) g=60 ;; esac
  kill -TERM "$p" 2>/dev/null
  while kill -0 "$p" 2>/dev/null && [ "$i" -lt $((g * 5)) ]; do sleep 0.2; i=$((i + 1)); done
  kill -0 "$p" 2>/dev/null && kill -KILL "$p" 2>/dev/null
  echo "lane-remove: stopped $2 (pid $p)"
}

# _lanes_live_watchers <lane_dir> — prints "<pid>\t<pr_url>" for each live merge watcher of the lane
# (its marker's pid still runs automate-merge-watch for that marker's PR — a recycled pid is not live).
_lanes_live_watchers() {
  local m mp mu
  for m in "$1"/.supervisor/automate/*.merge-watch; do
    [ -f "$m" ] || continue
    mp="$(awk -F'\t' '$1 == "pid" { print $2 }' "$m")"; mu="$(awk -F'\t' '$1 == "pr_url" { print $2 }' "$m")"
    case "$mp" in ''|*[!0-9]*) continue ;; esac
    case "$(ps -ww -o command= -p "$mp" 2>/dev/null)" in
      *automate-merge-watch*"$mu"*) printf '%s\t%s\n' "$mp" "$mu" ;;
    esac
  done
}

# _lanes_status_named <meta-sync status --paths output> — `(<first line>)`, plus ` — paths: <p>, …` when
# indented path lines follow (at most five named, then `+<k> more`). A status with no path lines (an
# older meta-sync) reads exactly as before: `(<first line>)`.
_lanes_status_named() {
  local first n
  first="$(printf '%s\n' "$1" | head -1)"
  n="$(printf '%s\n' "$1" | sed 1d | grep -c '^  [^ ]')"
  [ "$n" -gt 0 ] || { printf '(%s)' "$first"; return 0; }
  printf '(%s) — paths: %s' "$first" "$(printf '%s\n' "$1" | sed 1d | grep '^  [^ ]' | sed 's/^  //' | head -5 \
    | awk -v k="$((n - 5))" '{ printf "%s%s", (NR > 1 ? ", " : ""), $0 } END { if (k > 0) printf ", +%d more", k }')"
}

# _lanes_event <step> <outcome> <code> [--count k=n] — #618: an opt-in telemetry script event
# (docs/TELEMETRY.md "What the engine reports") rooted at the PRIMARY, never the lane dir (a lane is
# about to be salvaged and removed, and the wrapper writes <root>/.supervisor/logs/). Fire-and-forget.
_lanes_event() {
  [ -n "${LN_PRIMARY:-}" ] && [ -d "$LN_PRIMARY" ] || return 0
  bash "$HERE/emit-script-event.sh" --root "$LN_PRIMARY" automate-lanes "$@" >/dev/null 2>&1 </dev/null || true
}
# _lanes_remove_event <refusal reason> — the reason as a fixed token, ONLY for a refusal that means
# something is stuck (unpushed metadata, a dirty tree, unpushed commits, an unreadable status, a
# failed salvage). The normal waits — a live process or watcher, an open question, a gone PR — send
# nothing: fleet-closeout re-runs lane-remove on every --resume and they clear by themselves.
_lanes_remove_event() {
  local c
  case "$1" in
    "metadata not pushed"*) c=metadata_not_pushed ;;
    "meta-push failure marker"*) c=meta_push_failed ;;
    "dirty working tree"*) c=dirty_tree ;;
    "branch "*" commit(s) not on origin"*) c=unpushed_commits ;;
    "metadata mode unknown"*|"metadata status unreadable"*|*"unreadable"*) c=status_unreadable ;;
    "salvage "*) c=salvage_failed ;;
    *"still alive after --stop") c=stop_failed ;;
    # --abandon's own record: an owner typed it, but a failed stamp / move / push leaves the lane stuck
    "could not write the ABANDONED stamp"*|"could not move "*) c=abandon_record_failed ;;
    "metadata push failed"*|"evidence-gated trail push failed"*) c=abandon_push_failed ;;
    *) return 0 ;;
  esac
  _lanes_event lane-remove fail "$c"
}

# _lanes_only_bad_sidecars <meta-sync status --paths output> — issue #616: 0 when EVERY unpushed path
# is one of this lane's own result sidecars (`<run_id>.supervisor-result.md` / `.review-heal-result.md`)
# that sidecar-check fails — the file trail-pr's evidence gate excluded, which no push will ever carry,
# so `local_ahead` alone held the lane forever. Sets `exempt` (space-separated basenames) for the
# salvage check and the removed line. No path lines (an older meta-sync), any other path, a sidecar
# that passes, or an unreadable check ⇒ 1 (the refusal stands — fail CLOSED).
_lanes_only_bad_sidecars() {
  local p n=0 sc
  exempt=""
  while IFS= read -r p; do
    case "$p" in "  "*) ;; *) continue ;; esac
    p="${p#  }"; n=$((n + 1))
    case "$p" in
      ".supervisor/automate/$LN_RUN.supervisor-result.md"|".supervisor/automate/$LN_RUN.review-heal-result.md") ;;
      *) return 1 ;;
    esac
    [ -f "$LN_DIR/$p" ] || return 1
    sc="$(bash "$HELPERS" sidecar-check "$LN_DIR/$p" 2>/dev/null | tail -n 1)"
    case "$sc" in "fail $LN_DIR/$p: "*) exempt="${exempt:+$exempt }${p##*/}" ;; *) return 1 ;; esac
  done <<<"$(printf '%s\n' "$1" | sed 1d)"
  [ "$n" -gt 0 ]
}

# _lanes_remove_refusals — every lane-remove refusal that does not depend on process liveness. Runs
# in lanes_remove's dynamic scope (reads/sets its locals L, abandon, state, rf, q, b, u, mb, ms, exempt).
_lanes_remove_refusals() {
  exempt=""
  rstate="$(_lanes_state_of "$L")"   # the lane's real state, from lane-status's own reader (F10)
  # >>> awaiting-input check
  rf="$LN_DIR/.supervisor/automate/$LN_RUN.md"
  if q="$(_lanes_pending_question "$LN_INBOX")"; then _refuse "awaiting_input — unanswered question $q"; return 1; fi
  if [ -f "$rf" ] && grep -q 'pause_reason: *awaiting_input' "$rf"; then _refuse "awaiting_input — run file is parked on a question"; return 1; fi
  if [ "$(jq -r '.stop_reason // empty' <<<"$(_lanes_last_result "$LN_LOG")" 2>/dev/null)" = "tool_deferred" ]; then
    q="$(jq -r '.deferred_tool_use.id // empty' <<<"$(_lanes_last_result "$LN_LOG")")"
    [ -e "$LN_INBOX/answers/$q.json" ] || { _refuse "awaiting_input — deferred tool call $q"; return 1; }
  fi
  # <<< awaiting-input check
  state="$(_lt_get "$LN_TABLE" "$L" 8)"
  if [ "$abandon" = 0 ]; then
    if [ "$state" = gone ] || { [ -f "$rf" ] && grep -qE '(status|pause_reason): *gone' "$rf"; }; then
      _refuse "gone (PR closed unmerged) — a human runs lane-remove --abandon"; return 1
    fi
  fi
  [ -z "$(git -C "$LN_DIR" status --porcelain 2>/dev/null)" ] || { _refuse "dirty working tree"; return 1; }
  if [ "$abandon" = 1 ] && [ "$ab_ok" = 1 ] && [ "$rstate" = gone ]; then   # F11
    if ! mb="$(_lanes_meta_branch "$LN_DIR")"; then _refuse "metadata mode unknown (cannot record the abandon)"; return 1; fi
    _lanes_abandon_meta || return 1
  fi
  [ -e "$LN_DIR/.supervisor/automate/$LN_RUN.meta-push-failed" ] && { _refuse "meta-push failure marker is set"; return 1; }
  if ! mb="$(_lanes_meta_branch "$LN_DIR")"; then _refuse "metadata mode unknown (cannot prove the metadata was pushed)"; return 1; fi
  if [ -n "$mb" ]; then
    # --paths: the refusal names what is unpushed, so fleet-closeout's `waiting — <lane> …` line says
    # which file to push (wave W4: a worker-filed proposed/ draft found only by a hand list-managed diff).
    ms="$(bash "$META_SYNC" status --branch "$mb" --root "$LN_DIR" --paths 2>/dev/null)" || { _refuse "metadata status unreadable"; return 1; }
    case "$(printf '%s\n' "$ms" | head -1)" in
      conflict*|*conflict*) _refuse "metadata not pushed $(_lanes_status_named "$ms")"; return 1 ;;
      local_ahead*|*local_ahead*)
        _lanes_only_bad_sidecars "$ms" || { _refuse "metadata not pushed $(_lanes_status_named "$ms")"; return 1; } ;;
    esac
  fi
  # >>> unpushed-commit check (fail CLOSED: an unreadable branch list or count refuses, never reads 0)
  local heads; heads="$(git -C "$LN_DIR" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null)" \
    || { _refuse "local branch list unreadable"; return 1; }
  for b in $heads; do
    u="$(git -C "$LN_DIR" rev-list --count "$b" --not --remotes=origin 2>/dev/null)" || u=""
    case "$u" in ''|*[!0-9]*) _refuse "branch $b: unpushed-commit count unreadable"; return 1 ;; esac   # UNPUSHED-UNREADABLE
    [ "$u" -gt 0 ] && { _refuse "branch $b has $u commit(s) not on origin"; return 1; }
  done
  # <<< unpushed-commit check
  return 0
}

# Order: without --stop a live process refuses first (naming it). With --stop, EVERY non-liveness
# refusal runs BEFORE anything is stopped, so a lane that is unremovable for another reason is refused
# with its processes untouched (never left stopped-but-refused); only then are the live processes
# TERMed (KILL after the grace), liveness is re-evaluated, and the non-liveness refusals run once more
# (the stopped process may have changed the lane in between) before salvage and removal.
lanes_remove() {
  local dir="" stop=0 abandon=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --stop) stop=1; shift ;;
      --abandon) abandon=1; shift ;;
      *) [ -z "$dir" ] || die "lane-remove: unexpected argument '$1'"; dir="$1"; shift ;;
    esac
  done
  _lane_ctx "$dir" || die "lane-remove: not a lane: ${dir:-<none>}"
  local L="$LN_LANE" pid st mp mu q state rstate="" rf b u mb ms live_pid="" watchers="" ab_ok=0 exempt="" e kept=""
  _refuse() { echo "lane-remove: refused — $L — $1"; _lanes_remove_event "$1"; return 1; }
  # >>> live-process check
  pid="$(_lt_get "$LN_TABLE" "$L" 5)"; st="$(_lt_get "$LN_TABLE" "$L" 6)"
  if lanes_proc_alive "$pid" "$st" "$LN_DIR"; then
    if [ "$stop" = 1 ]; then live_pid="$pid"; else _refuse "live claude -p process (pid $pid); use --stop"; return 1; fi
  fi
  # <<< live-process check
  watchers="$(_lanes_live_watchers "$LN_DIR")"
  if [ -n "$watchers" ] && [ "$stop" = 0 ]; then
    IFS="$(printf '\t')" read -r mp mu <<<"$watchers"   # the first live watcher
    _refuse "live merge watcher (pid $mp, $mu); use --stop"; return 1
  fi
  [ -z "$live_pid$watchers" ] && ab_ok=1   # the abandon record is written only once nothing runs
  _lanes_remove_refusals || return 1   # REFUSE-BEFORE-STOP
  if [ -n "$live_pid$watchers" ]; then
    [ -n "$live_pid" ] && _lanes_stop_pid "$live_pid" "claude -p"
    while IFS="$(printf '\t')" read -r mp mu; do
      [ -n "$mp" ] && _lanes_stop_pid "$mp" "merge watcher"
    done <<<"$watchers"
    if [ -n "$live_pid" ] && lanes_proc_alive "$pid" "$st" "$LN_DIR"; then
      _refuse "lane process (pid $pid) still alive after --stop"; return 1
    fi
    watchers="$(_lanes_live_watchers "$LN_DIR")"
    if [ -n "$watchers" ]; then
      IFS="$(printf '\t')" read -r mp mu <<<"$watchers"   # the first live watcher
      _refuse "merge watcher (pid $mp, $mu) still alive after --stop"; return 1
    fi
    ab_ok=1
    _lanes_remove_refusals || return 1
  fi
  local sv; sv="$(_lanes_salvage "$LN_DIR" "$LN_ROOT/salvage" "$L-removed")" || { _refuse "salvage failed"; return 1; }
  # An exempted sidecar (#616) exists nowhere else once the lane is gone: prove the salvage holds it
  # byte-for-byte before removing anything (the salvage copy discards its own errors).
  for e in $exempt; do
    cmp -s "$LN_DIR/.supervisor/automate/$e" "$sv/supervisor/automate/$e" \
      || { _refuse "salvage does not hold $e byte-for-byte (an unpushed sidecar would be lost)"; return 1; }
  done
  [ -z "$exempt" ] || kept="; kept in salvage only (failed sidecar-check, never pushed): $exempt"
  # Single-lane parent: the lane's token TOTAL survives its directory as one parent ## Progress line
  # (the whole-run ceiling's only record of a removed lane) — plain and --abandon alike, once per lane.
  local prf="$LN_PRIMARY/.supervisor/automate/$LN_PARENT.md"
  if _lanes_single_parent "$prf"; then _lanes_tokens_record "$prf" "$L" "$LN_DIR" "$LN_RUN" >/dev/null; fi
  rm -rf "$LN_DIR" || { echo "lane-remove: could not remove $LN_DIR" >&2; return 1; }
  _lt_set "$LN_TABLE" "$L" 8 "$([ "$abandon" = 1 ] && echo abandoned || echo removed)"
  if [ "$abandon" = 1 ]; then
    # A run-file line never carries an absolute path (the branch-mode trail push scrubs home paths and
    # would fail the parent's push — F10): the salvage is named in the `<primary>-lanes/…` form.
    bash "$HELPERS" progress-append "$LN_PRIMARY/.supervisor/automate/$LN_PARENT.md" \
      "lane abandoned: $L ($LN_RUN) — state ${rstate:-unknown}; salvage kept at <primary>-lanes/$LN_PARENT/salvage/${sv##*/}" >/dev/null 2>&1 || true
  fi
  _lanes_event lane-remove pass removed
  echo "lane-remove: removed $L ($LN_DIR); salvage $sv$kept"
}

# ==================================================================================================
# ---- the lane's metadata at the wave end (F11) --------------------------------------------------
# _lanes_meta_extras <branch> <message> — pushes the lane's own NON-claim metadata, exactly listed:
# its run file, `<run_id>.merge-readiness.md`, `<run_id>.dismissed-decisions` and `<run_id>.brief-draft.md`
# (each when present), plus its Orchestrator task plans and the requirement drafts it filed
# (_lanes_noclaim_files). None of them is a done claim. The brief draft is the revised brief the lane's
# Launch Pad keeps (Plan Review FAIL×3 → "Refine offline", or a PASS that kept a draft): a managed
# `.supervisor/automate/*.md` path no trail-pr candidate carries, so before this list carried it the
# lane read `local_ahead 1` forever and lane-remove refused it (run automate-2026-10-15-163325: L5, L9,
# each hand-pushed). Only this lane's own run id. Prints meta-sync's reason and returns 1 on failure.
_lanes_meta_extras() {
  local mb="$1" msg="$2" list f out rc=0
  list="$(mktemp "${TMPDIR:-/tmp}/lane-meta.XXXXXX" 2>/dev/null)" || { echo "could not stage the push list"; return 1; }
  { for f in "$LN_RUN.md" "$LN_RUN.merge-readiness.md" "$LN_RUN.dismissed-decisions" "$LN_RUN.brief-draft.md"; do
      if [ -f "$LN_DIR/.supervisor/automate/$f" ]; then printf '%s\n' ".supervisor/automate/$f"; fi
    done
    _lanes_noclaim_files
  } > "$list" || { rm -f "$list"; echo "could not stage the push list"; return 1; }
  out="$(bash "$META_SYNC" push --branch "$mb" --root "$LN_DIR" --paths-from "$list" --message "$msg" 2>&1)" || rc=$?
  rm -f "$list"
  if [ "$rc" != 0 ]; then
    printf 'meta-sync exit %s\n%s' "$rc" "$out"; return 1
  fi
  return 0
}

# _lanes_noclaim_files — prints the lane's other non-claim metadata, one repo-relative path per line:
#   - its Orchestrator task plans: every regular top-level `.supervisor/requirements/<slug>-plan.md` (the
#     one path the Orchestrator's file-fallback mode writes, agents/orchestrator.md §"Persistence Mode")
#     — before this list carried them, lane-remove refused forever on `local_ahead` (operator-run
#     2026-10-10 Phase 0.2);
#   - the requirement drafts it filed: every regular top-level `.supervisor/requirements/proposed/*.md`.
#     A worker whose requirement says to file an out-of-scope follow-up as its own item writes it there
#     (`## Status: proposed`); trail-pr's candidates carry only this run's dismissed drafts from that
#     folder, so before this list carried them the draft stayed local and fleet-closeout waited forever
#     on `local_ahead 1` (wave W4, run automate-2026-10-11-182243: twin-remediation-11, hand-pushed).
# Both sit on meta-managed paths no other wave-end push carries. Excluded, left to trail-pr's evidence
# gate: a path the lane run file's `## Queue` / `## Current` names (that is the item's requirement), and
# any file carrying a `## Status: done…` heading (a done claim). A file the lane only pulled is unchanged,
# so meta-sync pushes nothing for it; a lane clone has exactly one run, so nothing here is another run's.
_lanes_noclaim_files() {
  local f p items nl tab
  nl="$(printf '\nx')"; nl="${nl%x}"; tab="$(printf '\t')"
  items="$(awk '/^## / { sec = $0; next }
    sec == "## Queue" && /^- \[[ xX]\] / { v = $0; sub(/^- \[[ xX]\] /, "", v); sub(/[[:space:]]+#.*$/, "", v); sub(/[[:space:]]+$/, "", v); sub(/^\.\//, "", v); print v }
    sec == "## Current" && /^- item:/ { v = $0; sub(/^- item: */, "", v); sub(/ *\|.*/, "", v); sub(/^\.\//, "", v); print v }' \
    "$LN_DIR/.supervisor/automate/$LN_RUN.md" 2>/dev/null)"
  for f in "$LN_DIR"/.supervisor/requirements/*-plan.md "$LN_DIR"/.supervisor/requirements/proposed/*.md; do
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    p="${f#"$LN_DIR"/}"
    case "$p" in *"$nl"*|*"$tab"*) continue ;; esac   # meta-sync refuses such names; never split a line
    grep -qxF -- "$p" <<<"$items" && continue
    grep -qE '^## Status:[[:space:]]*done' "$f" 2>/dev/null && continue
    printf '%s\n' "$p"
  done
  return 0
}

# _lanes_meta_trail <branch> <lane_runfile> <reason> — the rest of the lane's metadata (requirement,
# done/failed briefs, result sidecars, the postmortem ledger, its dismissed drafts) goes through
# `trail-pr`'s OWN evidence-gated candidate list, run on the lane's run file inside the lane: a done
# stamp or a `jobs/done/` brief rides only when its PR reads MERGED (`; excluded <path> — pr not
# merged` otherwise). Branch mode only. trail-pr reads the mode through its sibling setup-memory.sh;
# when that reader does not say `on <branch>` too, nothing runs (a PR-mode trail must never start
# from here). Prints trail-pr's line; returns 1 unless it reads meta-pushed / meta no_changes.
# Pass-through, not a new seam: META_SYNC is forwarded as trail-pr's LOOMWRIGHT_META_SYNC_BIN so the
# push uses the same meta-sync this script's other calls use — in a real run that is the sibling
# meta-sync.sh (trail-pr's own default); only the LOOMWRIGHT_LANES_META_SYNC test seam changes it.
_lanes_meta_trail() {
  local mb="$1" rf="$2" reason="$3" tm out
  tm="$(bash "$(dirname "$TRAIL")/setup-memory.sh" --root "$LN_DIR" mode 2>/dev/null | head -1)"
  [ "$tm" = "on $mb" ] || { echo "trail-pr's mode reader says '${tm:-nothing}', not 'on $mb' — trail not run"; return 1; }
  out="$(LOOMWRIGHT_META_SYNC_BIN="$META_SYNC" bash "$TRAIL" trail-pr "$rf" --reason "$reason" 2>/dev/null | tail -1)"
  printf '%s' "${out:-trail-pr printed nothing}"
  case "$out" in "trail-pr: meta-pushed "*|"trail-pr: skipped — meta no_changes"*) return 0 ;; esac
  return 1
}

# _lanes_abandon_meta — lane-remove --abandon on a lane lane-status reads `gone` (its PR closed
# unmerged), in lanes_remove's scope. The owner's abandon decision is recorded the way
# `reconcile-status --apply` records an `# abandoned:` Queue row: every done heading of the lane's
# requirement becomes `## Status: done_with_escalation — ABANDONED (- [x] <item>  # abandoned:
# <reason>)` (appended when it has none), and a `jobs/done/` brief pointing at that requirement moves
# to `jobs/failed/`. (Before automate-followups/37, Phase 4.5 stamped the requirement done before any
# merge; it no longer does, but an older requirement may still carry that stamp for the unmerged PR,
# and this is what rewrites it.) Then, in branch mode,
# the lane's metadata is pushed (_lanes_meta_extras + _lanes_meta_trail --reason abandoned), so the
# lane is removable with no hand step and nothing pushed claims the unmerged work done.
_lanes_abandon_meta() {
  local arf="$LN_DIR/.supervisor/automate/$LN_RUN.md" item req row em b ptr out
  item="$(_lanes_current_item "$arf")"; item="${item#./}"
  case "$item" in .supervisor/requirements/*.md) ;; *) item="" ;; esac
  case "$item" in *..*) item="" ;; esac
  if [ -n "$item" ] && [ -f "$LN_DIR/$item" ]; then
    req="$LN_DIR/$item"; em="$(printf '\342\200\224')"
    row="- [x] $item  # abandoned: PR closed unmerged $em lane-remove --abandon"
    if ! AB_HEAD="## Status: done_with_escalation $em ABANDONED ($row)" AB_PFX="## Status: done_with_escalation $em ABANDONED (- [x] " awk '
        /^## Status:[[:space:]]*done(_with_escalation)?([^A-Za-z0-9_]|$)/ && index($0, ENVIRON["AB_PFX"]) != 1 { print ENVIRON["AB_HEAD"]; n++; next }
        index($0, ENVIRON["AB_PFX"]) == 1 { n++ }
        { print }
        END { if (!n) { print ""; print ENVIRON["AB_HEAD"] } }' "$req" > "$req.tmp.$$" || ! mv "$req.tmp.$$" "$req"; then
      rm -f "$req.tmp.$$"; _refuse "could not write the ABANDONED stamp on $item"; return 1
    fi
    if [ -r "$HERE/brief-pointer.sh" ]; then
      # shellcheck source=/dev/null
      . "$HERE/brief-pointer.sh"
      for b in "$LN_DIR"/.supervisor/jobs/done/*.md; do
        [ -f "$b" ] || continue
        ptr="$(brief_requirement_pointer "$b" 2>/dev/null)" || continue
        [ "${ptr#./}" = "$item" ] || continue
        mkdir -p "$LN_DIR/.supervisor/jobs/failed" && mv "$b" "$LN_DIR/.supervisor/jobs/failed/" \
          || { _refuse "could not move $(basename "$b") to jobs/failed/"; return 1; }
      done
    fi
  fi
  [ -n "$mb" ] || return 0
  out="$(_lanes_meta_extras "$mb" "chore(supervisor): $LN_RUN abandoned (lane-remove --abandon)")" || { _refuse "metadata push failed ($(printf '%s\n' "$out" | head -1))"; return 1; }
  out="$(_lanes_meta_trail "$mb" "$arf" abandoned)" || { _refuse "evidence-gated trail push failed: $out"; return 1; }
  echo "lane-remove: $L abandoned — $out"
}

# lane-convert-ready <lane_dir> — the wave-end `ready_for_release` → `awaiting_merge` conversion: the
# coordinator's one run-file write into a launched lane, and it PUSHES the lane's metadata, so the
# primary's next meta pull reads awaiting_merge and lane-remove's metadata check (`meta-sync status`)
# can pass. Under the lane's launch lock (no launch or resume can start mid-conversion). Refusals (exit
# 1, nothing written): a live lane process (lanes_proc_alive), no run file, a `## Current` that reads
# none of the three accepted states below, or an unknown metadata mode. Order, after the refusals:
# `ready_for_release` (both fields) ⇒ current-set converts it to `awaiting_merge` (no closeout — the PR
# is not merged yet). Already `awaiting_merge` (a re-run after a failed push, or after the owner
# merged) ⇒ NO current-set; instead `closeout <the lane's run file> <item> <## Current pr> --no-trail`
# runs inside the lane (automate-followups/38) — the ONE writer of the requirement's done stamp, behind
# its own evidence gate (PR not MERGED ⇒ it writes nothing), which also checks the item off and
# reconciles `## Current` to `done` / `awaiting_go`; its lines are echoed indented, closeout-classify
# reads them and the last line names any leftover (a leftover never changes the exit code); no
# `pr:` in `## Current` ⇒ closeout is not run. Already closed out (`done` / `awaiting_go` — a re-run
# after the merged re-run's push failed) ⇒ neither runs again; a lane finalize-empty already finalized
# (`## Status: done`, ## Current `done` / `null`) is accepted the same way. Whenever ## Current then reads
# `done`, branch mode runs `finalize-empty` inside the lane before the pushes (A1, parallel-automate/21 —
# see the comment at its call). Each then runs the pushes, so a re-run is idempotent. Branch mode (`on <Y>`) then
# pushes (1) the lane's non-claim files by exact list (_lanes_meta_extras: the run file, its
# merge-readiness report, its dismissed-decisions ledger, its kept brief draft, its task plans, the
# requirement drafts it filed under proposed/) and (2) everything else through trail-pr's
# evidence-gated candidate list (_lanes_meta_trail, `--reason wave-end`): a done stamp or a jobs/done/
# brief whose PR is not MERGED is excluded and named, so while the PR is open the lane keeps reading
# `local_ahead` and lane-remove keeps refusing — after the owner merges, the re-run's closeout writes
# the stamp and its pushes carry it; if the PR closes unmerged, `lane-remove --abandon` records it
# (F11). Mode `off` has no metadata
# branch to push. A failed push ⇒ `lane-convert-ready: FAILED — …` and exit 2 (re-run to retry). The
# last line names the state the lane reads afterwards: `converted <lane> to awaiting_merge` on the
# conversion, `<lane> reads <status> / <pause_reason> (a re-run converts nothing)` on a re-run.
_lanes_current_item() { # <runfile> — the `## Current` item path, or nothing
  awk '/^## / { sec = $0; next }
    sec == "## Current" && /^- item:/ { v = $0; sub(/^- item: */, "", v); sub(/ *\|.*/, "", v); print v; exit }' "$1" 2>/dev/null
}
# _lanes_no_host_identity [NAME=VALUE ...] <cmd> [args...] — runs <cmd> (through `exec env`, so
# leading NAME=VALUE pairs apply) with the host's two runtime-identity variables unset AND
# LOOMWRIGHT_HOLDER_PID pinned to <cmd>'s own pid (`bash -c` sets it to `$$`, then `exec env` and
# env's own exec keep that pid, so `$$` IS <cmd>). Guarantee: a fresh run-lock acquire with no
# --session-id inside <cmd> (lane-convert-ready's closeout and finalize-empty) records <cmd> itself
# as holder (`pid_source holder_env`) — never the coordinator session and never a long-lived
# ancestor such as the coordinator's own `claude` (run-lock.sh's ancestor walk is ungated) — so a
# crashed call's lock is reclaimable once <cmd> is dead. Like the merge watcher (automate-loop
# SKILL, "Why … are unset"); resolution order: docs/ARCHITECTURE_CONTRACTS.md §"Run lock".
_lanes_no_host_identity() {
  env -u CLAUDE_PID -u CLAUDECODE \
    bash -c 'LOOMWRIGHT_HOLDER_PID=$$; export LOOMWRIGHT_HOLDER_PID; exec env "$@"' _ "$@"
}
lanes_convert_ready() {
  local dir="${1:-}"
  [ "$#" -le 1 ] || die "lane-convert-ready: unexpected argument '$2'"
  _lane_ctx "$dir" || die "lane-convert-ready: not a lane: ${dir:-<none>}"
  local L="$LN_LANE" rf pid st status pause pr item mb out rc list phase co cv cs="" did fdid
  rf="$LN_DIR/.supervisor/automate/$LN_RUN.md"
  _cr_refuse() { _lanes_launch_unlock; echo "lane-convert-ready: refused — $L — $1"; return 1; }
  _lanes_launch_lock || { echo "lane-convert-ready: refused — $L — launch lock busy (a launch or resume of this lane is in flight)"; return 1; }
  pid="$(_lt_get "$LN_TABLE" "$L" 5)"; st="$(_lt_get "$LN_TABLE" "$L" 6)"
  if lanes_proc_alive "$pid" "$st" "$LN_DIR"; then _cr_refuse "live lane process (pid $pid); convert only after it exits"; return 1; fi
  [ -f "$rf" ] || { _cr_refuse "no run file $LN_RUN.md"; return 1; }
  IFS="$(printf '\t')" read -r status pause pr _ <<<"$(_lanes_runfile_fields "$rf")"
  case "$status/$pause" in
    ready_for_release/ready_for_release) phase=convert ;;
    awaiting_merge/awaiting_merge) phase=closeout; echo "lane-convert-ready: $L already reads awaiting_merge — retrying the metadata push" ;;
    done/awaiting_go) phase=closed; echo "lane-convert-ready: $L already closed out (## Current done / awaiting_go) — retrying the metadata push only" ;;
    # A1: finalize-empty rewrote `## Status: done` + pause_reason null — a re-run after a failed push.
    done/null|done/-)
      if _lanes_rf_done "$rf"; then
        phase=closed; echo "lane-convert-ready: $L already closed out and finalized (## Status: done) — retrying the metadata push only"
      else _cr_refuse "run file reads status ${status:--} / pause_reason ${pause:--}, not ready_for_release"; return 1; fi ;;
    *) _cr_refuse "run file reads status ${status:--} / pause_reason ${pause:--}, not ready_for_release"; return 1 ;;
  esac
  item="$(_lanes_current_item "$rf")"
  case "$item" in ''|null|-) _cr_refuse "run file has no ## Current item"; return 1 ;; esac
  if ! mb="$(_lanes_meta_branch "$LN_DIR")"; then _cr_refuse "metadata mode unknown (the conversion could not be pushed)"; return 1; fi
  if [ "$phase" = convert ]; then
    out="$(bash "$HELPERS" current-set "$rf" --item "$item" --status awaiting_merge --pause-reason awaiting_merge 2>&1)" \
      || { _cr_refuse "current-set failed: $(printf '%s' "$out" | tr '\n' ' ')"; return 1; }
  fi
  # The merged re-run (automate-followups/38): closeout --no-trail inside the lane, under the launch lock,
  # BEFORE the pushes, never followed by current-set (that would revert closeout's ## Current reconcile).
  # Its own evidence gate decides — an unmerged PR prints `skipped — pr not merged` and writes nothing.
  if [ "$phase" = closeout ]; then
    case "$pr" in
      ''|-|null) cs="; closeout not run (## Current has no pr)" ;;
      *)
        # A fresh run-lock acquire (no --session-id): host identity unset, holder pinned to the
        # closeout process (_lanes_no_host_identity).
        co="$(cd "$LN_DIR" && _lanes_no_host_identity bash "$TRAIL" closeout "$rf" "$item" "$pr" --no-trail 2>/dev/null)"
        printf '%s\n' "$co" | sed '/^$/d; s/^/  /'
        cv="$(printf '%s\n' "$co" | bash "$HELPERS" closeout-classify --run "$LN_RUN" --item "${item#./}" --pr "$pr" 2>/dev/null)"
        if [ "$cv" = complete ]; then cs="; closeout complete"
        elif [ -z "$cv" ]; then cs="; closeout leftover: classify — closeout-classify printed nothing"
        elif ! grep -q '^leftover	' <<<"$cv" && grep -q '^run_lock_held	' <<<"$cv"; then
          # automate-followups/36 A1: a LIVE process holds the run lock — not a leftover; nothing ran.
          cs="; closeout deferred: $(printf '%s\n' "$cv" | awk -F'\t' '$1 == "run_lock_held" { printf "%s%s", (n++ ? ", " : ""), $6 }') — re-run lane-convert-ready once it is released"
        else cs="; closeout leftover: $(printf '%s\n' "$cv" | awk -F'\t' '$1 == "leftover" { printf "%s%s — %s", (n++ ? ", " : ""), $5, $6 }')"
        fi ;;
    esac
  fi
  # What the lane now reads — a re-run converts nothing, and its closeout may have reconciled ## Current
  # to done / awaiting_go, so it names the state it read back, never "converted … to awaiting_merge".
  if [ "$phase" = convert ]; then did="converted $L to awaiting_merge"; fdid="converted to awaiting_merge"
  else
    IFS="$(printf '\t')" read -r status pause _ <<<"$(_lanes_runfile_fields "$rf")"
    fdid="reads ${status:--} / ${pause:--} (a re-run converts nothing)"; did="$L $fdid"
  fi
  # A1 (parallel-automate/21): a re-run whose ## Current reads `done` (closeout's done / awaiting_go, or an
  # already-finalized lane) runs `finalize-empty <the lane's run file>` INSIDE the lane, under the launch
  # lock and BEFORE the pushes — so the pushes carry its `## Status: done` and the Progress lines it
  # appends after its own trail push. finalize-empty decides eligibility itself (already `## Status: done`
  # ⇒ `finalize-empty: skipped — not paused`). Its `trail-pr --reason done` runs through the evidence gate
  # with this script's meta-sync (LOOMWRIGHT_META_SYNC_BIN, as _lanes_meta_trail). Branch mode only: with
  # mode off — or when finalize's own mode reader does not say `on <mb>` too — finalize is NOT run (its
  # trail-pr would open a trail PR). One `lane-convert-ready: finalize …` line, printed before the last.
  # The last line keeps naming the state closeout left (`reads done / awaiting_go`) — the finalize line
  # above it names what finalize-empty did to it.
  local fin="" fe fm
  if [ "$phase" != convert ] && [ "$status" = done ]; then
    if [ -z "$mb" ]; then fin="lane-convert-ready: finalize skipped — metadata mode off"
    else
      fm="$(bash "$(dirname "$HELPERS")/setup-memory.sh" --root "$LN_DIR" mode 2>/dev/null | head -1)"
      if [ "$fm" != "on $mb" ]; then
        fin="lane-convert-ready: finalize skipped — finalize-empty's mode reader says '${fm:-nothing}', not 'on $mb'"
      else
        # finalize-empty's run-lock acquire takes no --session-id either: same unset + holder pin as closeout above.
        fe="$(cd "$LN_DIR" && _lanes_no_host_identity LOOMWRIGHT_META_SYNC_BIN="$META_SYNC" \
          bash "$HELPERS" finalize-empty "$rf" 2>/dev/null)"
        fe="$(printf '%s\n' "$fe" | sed '/^$/d' | awk '{ printf "%s%s", (NR > 1 ? "; " : ""), $0 }')"
        fin="lane-convert-ready: finalize — ${fe:-finalize-empty printed nothing}"
      fi
    fi
  fi
  if [ -z "$mb" ]; then
    _lanes_launch_unlock
    if [ -n "$fin" ]; then echo "$fin"; fi
    echo "lane-convert-ready: $did (metadata mode off — no metadata branch to push)$cs"
    return 0
  fi
  if [ -n "$fin" ]; then echo "$fin"; fi
  rc=0; out="$(_lanes_meta_extras "$mb" "chore(supervisor): $LN_RUN ready_for_release -> awaiting_merge (wave end)")" || rc=$?
  if [ "$rc" != 0 ]; then
    _lanes_launch_unlock
    echo "lane-convert-ready: FAILED — $L — $fdid, but the metadata push to $mb failed ($(printf '%s\n' "$out" | head -1)); NOT pushed (lane-remove refuses until it is) — re-run lane-convert-ready $LN_DIR$cs"
    printf '%s\n' "$out" | sed '1d; /^$/d; s/^/  /'
    return 2
  fi
  rc=0; out="$(_lanes_meta_trail "$mb" "$rf" wave-end)" || rc=$?
  _lanes_launch_unlock
  if [ "$rc" != 0 ]; then
    echo "lane-convert-ready: FAILED — $L — $fdid and its non-claim files pushed, but the evidence-gated trail push failed: $out — re-run lane-convert-ready $LN_DIR$cs"
    return 2
  fi
  echo "lane-convert-ready: $did; metadata pushed to $mb — $out$cs"
}

