# automate-lanes.d/scope.sh — sourced by automate-lanes.sh (see its header). SCOPE: the files a brief plans
# outside its item's `## Touches`, read deterministically so no model computes the set difference
# (lane-scope-regate Part A). Reuses readiness.sh's declared-set readers — _lanes_declared (the Touches read:
# `plan-waves --touches`, companions included), _lanes_brief_paths (the brief grammar) and _lanes_is_declared
# (the matcher wave-build's overlap check and the scope fence use) — and copies none of them.
#
# scope-outside <item> <brief> [--root <dir>] — READ-ONLY. <item> is the requirement file (repo-relative, or
# absolute under the root); <brief> any readable brief file (Launch Pad passes its scratch brief). The root
# is --root, else `git rev-parse --show-toplevel`, else $PWD. The brief's paths are its Subtask Contracts
# `path:` values and `lanes:` entries (_lanes_brief_paths is key-aware: `external_requires:` entries are
# package names and prose, never read); `changelog.d/` paths are exempt, as the scope fence exempts them. Prints
# ONE first line, exit 0:
# A path the brief's own `## Scope widening` already records (accepted or pending-coordinator) is never listed again,
# so re-entering Launch Pad's Phase 6 asks only about new paths.
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
  # changelog.d/ is exempt (the fence's rule); external_requires never reaches here (the reader is key-aware)
  _lanes_brief_paths "$brief" 2>/dev/null | awk '!/^changelog\.d\//' | env LC_ALL=C sort -u > "$tmp/brief"
  _lanes_sg_widening "$brief" all > "$tmp/recorded"
  if [ "$LD_TOUCHES_READ" = failed ]; then
    n="$(grep -c . "$tmp/brief")"; echo "unreadable ${n:-0}"; cat "$tmp/brief"
  elif [ "$LD_TOUCHES" = unknown ]; then
    echo unknown
  else
    : > "$tmp/out"
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      _lanes_is_declared "$f" "$tmp/touches" || _lanes_is_declared "$f" "$tmp/recorded" || printf '%s\n' "$f" >> "$tmp/out"
    done < "$tmp/brief"
    n="$(grep -c . "$tmp/out")"
    if [ "${n:-0}" -eq 0 ]; then echo inside; else echo "outside $n"; cat "$tmp/out"; fi
  fi
  rm -rf "$tmp"
}

# ==================================================================================================================
# THE SCOPE RE-GATE (lane-scope-regate Part B). Inside a `--parallel N > 1` lane, automate-next-step.sh parks the lane
# `scope_hold` right after its Launch Pad phase saved a brief (the pinned `launch-pad saved <brief>` line first), before
# the Supervisor phase writes any code. The coordinator then compares the lane's FINAL file set with every other live
# lane of the wave (lane-scope-check) and decides (lane-scope-decide). Every save holds, so the check is two-way by
# construction: lane X compared against lane Y's reserved Touches (Y not saved yet) is compared again when Y saves.
#
# lane-scope-check <lane_dir|L<n>> — READ-ONLY, exit 0 (exit 1 only on usage / not a lane). The lane's set is
# _lanes_declared (Touches as the planner reserved it + the saved brief's `path:` / `lanes:` entries, changelog.d/
# dropped; never an `external_requires:` entry); each other live lane of the wave (a lane-table row not removed / abandoned whose item the
# parent `## Current` `- wave:` line names — every row when there is none) is read the same way when it has a saved
# brief this pass, else by its reserved Touches alone. Files are matched with _lanes_is_declared in BOTH directions
# (the matcher wave-build's _lanes_wave_overlap uses). Prints, in this order:
#   unreadable — <what>                    one per set that cannot be read (no saved brief, an unreadable brief,
#                                          `plan-waves --touches` failed, no lane-table row) — fail CLOSED: never clear
#   overlap — <file> shared with <L> (saved brief|reserved Touches)[, …]   one per shared file, sorted
#   clear                                  only when neither line above was printed
#   widening — <path>                      one per path of the brief's `## Scope widening` section marked
#                                          `- decision: pending-coordinator` (a lane's Launch Pad never asks LP-SCOPE)
#
# lane-scope-decide <lane_dir|L<n>> <continue|serialize|defer|drop|revise> [--after L<m>] [--gate AUT-OVERLAP|LP-SCOPE]
#                   [--owner-command '<cmd>'] — the coordinator's ONE writer for a held lane (the lane's run file
# must read `pause_reason: scope_hold` and no lane process may run; else refused, exit 1, nothing written). It re-runs
# the check itself. `--gate` names the question the owner answered; `serialize`, `defer`, `drop` and `revise` always need it,
# `continue` needs `--gate AUT-OVERLAP` when the check is not `clear` and a gate when a widening is pending (refused
# otherwise — the coordinator never continues past an overlap on its own). Launching decisions need
# `--owner-command` (the launch authority: missing ⇒ `lane-scope-decide: BLOCKED — <lane> — no owner-invoked command
# — need the owner`, exit 3, nothing written).
#   continue   accepts a pending widening (`- decision: pending-coordinator` ⇒ `- accepted: <gate> <YYYY-MM-DD>` in the
#              lane's brief), releases the park (ONE validated runfile-write: `## Status: running` + `pause_reason:
#              null`), one lane line `scope re-gate released (continue)`, one parent line `scope re-gate: <lane> clear`
#              or `scope re-gate: <lane> continue in parallel — shares <files> with <lanes>` (`— unreadable: …` for an
#              unreadable set), then `lane-launch <lane_dir> --continue --owner-command '<cmd>'`: the lane's driver
#              resumes at RUN on the brief its `launch-pad saved` line names — never PICK, never a second Launch Pad.
#   serialize  --after L<m> (a live lane of the wave): records `scope re-gate: scope_wait L<m> (serialize)` (lane) and
#              `scope re-gate: <lane> serialize — scope_wait: L<m>` (parent) once, and stays held until L<m> reads
#              ready_for_release / awaiting_merge / merged — re-run it then. Refused, nothing written, when L<m> already
#              waits (directly or through others) for this lane: the wait could never end. Refused too when L<m> has
#              ended (escalated, failed, died, gone, no_pr_stop, removed …; a rate_limit park has not ended, it can be resumed): it
#              will never read ready without the owner, and a lane already waiting
#              on it reads undecided again (_lanes_scope_held), so the Stop guard and AUT-OVERLAP return. It reads L<m>'s PR head (`gh pr view
#              --json headRefOid,headRefName`), fetches that branch from origin into the held lane and checks the
#              fetched head IS that sha, then PRINTS the `git merge --no-ff <sha>` to run in the held lane's checked-out
#              branch — its base, since the Supervisor phase has not created a feature branch yet (ACQUIRE's `git pull
#              --ff-only` of an ahead base is a no-op, so the feature branch starts from the merge). This script runs
#              no merge (no lane subcommand merges); a conflict is the owner's, never force-resolved. Re-run once the
#              head is in HEAD: then the release and relaunch as `continue`.
#   defer      the item leaves this wave: refused on a dirty tree or a local commit not on origin; else one lane line,
#              salvage (`<lane>-deferred-…` under salvage/), the parent `- wave:` line rewritten without the item
#              (`current-wave`), the clone removed and its table state set `abandoned` — so no lane claims the item
#              (backlog's in_flight, pick-guard) — and two parent lines. The parent Queue row stays `- [ ]`, so the
#              next `plan-waves` plans it into a later wave. No ABANDONED stamp, no metadata push (nothing ran).
#              Keeps lane-remove's process, question and merge-watcher refusals, not its metadata one: a held lane's
#              run file is always unpushed in branch mode (that refusal would block every defer); salvage keeps it.
#   drop       `--gate LP-SCOPE` only (the owner's Stop): removed exactly like defer, then the parent Queue row is
#              checked off `# skipped:` so no later wave re-plans it. Prints `remaining: <n>`; the coordinator then runs
#              `trail-pr <parent run file> --reason skipped`, as for any skip check-off.
#   revise     releases with `scope re-gate released (revise) — keep off: <files>`: the driver re-plans (a new Launch
#              Pad phase whose prompt names those files) and the new save holds again.
# A lane parked `no_pr_stop` (its plan stopped with no PR, no brief saved) takes `defer` and `drop` here too, with no
# --gate and no scope check, and nothing else: they are the one way such a lane leaves the wave for a later re-plan.
# A relaunch that is HELD or BLOCKED is printed after the release line; the release stands (`lane-status` reads it).
# The coordinator's writes into a held lane: its run file (the release / serialize lines), its brief's widening line,
# serialize's fetch of the other lane's head and its removal (defer).

# _lanes_sg_brief <lane_dir> <runfile> — the brief the lane's current pass saved, as an absolute path: the last
# `launch-pad saved <brief>` line after the last `picked` line (a `scope re-gate released (revise` line starts the
# plan over — the driver's ns_segment_brief rule); empty when there is none. Supervisor moves a brief out of
# jobs/pending/ when it starts, so a recorded path that is gone is looked for by name under the other job folders;
# found nowhere, the recorded path is returned and reads unreadable (fail CLOSED).
_lanes_sg_brief() {
  local b
  b="$(awk '/^## / { sec = $0; next } sec == "## Progress" && /^- / { x = substr($0, 3); if (x ~ /^[0-9][0-9][0-9][0-9]-/) sub(/^[^ ]+ /, "", x)
      if (index(x, "picked ") == 1 || index(x, "scope re-gate released (revise") == 1) b = ""
      else if (index(x, "launch-pad saved ") == 1) b = substr(x, 18) } END { if (b != "") print b }' "$2" 2>/dev/null)"
  [ -n "$b" ] || return 0
  case "$b" in /*) ;; *) b="$1/${b#./}" ;; esac
  if [ ! -f "$b" ]; then
    local d; for d in in-progress done failed; do
      [ -f "$1/.supervisor/jobs/$d/${b##*/}" ] && { printf '%s' "$1/.supervisor/jobs/$d/${b##*/}"; return 0; }
    done
  fi
  printf '%s' "$b"
}
# _lanes_sg_set <lane_dir> <item> <brief|""> <out> — _lanes_declared's set without changelog.d/ (the scope-outside
# rule); returns 1 when the Touches read failed
_lanes_sg_set() {
  _lanes_declared "$1" "$2" "$3" "$4.raw"
  awk '!/^changelog\.d\//' "$4.raw" > "$4" 2>/dev/null; rm -f "$4.raw"
  [ "$LD_TOUCHES_READ" = ok ]
}
# _lanes_sg_widening <brief> [all] — the paths of a `## Scope widening` section's `- decision: pending-coordinator`
# batches (the first word of each path line, backticks dropped; a batch is its path lines and the decision line after
# them, so a later batch's answer never re-asks an accepted one). With `all`, every path the section records.
_lanes_sg_widening() {
  awk -v all="${2:-}" '/^## / { s = ($0 == "## Scope widening"); next }
    s && /^- decision: pending-coordinator[[:space:]]*$/ { for (i = 1; i <= b; i++) L[++n] = B[i]; b = 0; next }
    s && /^- accepted:/ { if (all == "") b = 0; next }
    s && /^- decision:/ { next }
    s && /^- / { v = substr($0, 3); gsub(/`/, "", v); sub(/[[:space:]].*/, "", v); if (v ~ /[\/.]/) B[++b] = v }
    END { for (i = 1; i <= n; i++) print L[i]; if (all != "") for (i = 1; i <= b; i++) print B[i] }' "$1" 2>/dev/null
}
# _lanes_sg_wave_rows <lane> — `lane<TAB>path<TAB>item<TAB>run_id` of every OTHER live lane of <lane>'s wave
# (after _lane_ctx: LN_TABLE, LN_PRIMARY, LN_PARENT), the last table row per lane
_lanes_sg_wave_rows() {
  local items
  items="$(awk '/^## / { sec = $0; next } sec == "## Current" && /^- wave: / { print; exit }' "$LN_PRIMARY/.supervisor/automate/$LN_PARENT.md" 2>/dev/null \
    | sed -n 's/^- wave: [^|]*| *items: *//p' | tr ',' '\n' | sed 's/^ *//; s/ *$//; /^$/d')"
  SG_ITEMS="$items" awk -F'\t' -v me="$1" '
    BEGIN { n = split(ENVIRON["SG_ITEMS"], a, "\n"); for (i = 1; i <= n; i++) if (a[i] != "") W[a[i]] = 1 }
    $1 ~ /^L[0-9][0-9]?$/ && $1 != me { if (!($1 in R)) O[++k] = $1; R[$1] = $0 }
    END { for (i = 1; i <= k; i++) { split(R[O[i]], c, "\t")
            if (c[8] != "removed" && c[8] != "abandoned" && (n == 0 || (c[3] in W))) print c[1] "\t" c[2] "\t" c[3] "\t" c[4] } }' "$LN_TABLE" 2>/dev/null
}
# _lanes_sg_check — after _lane_ctx: the comparison lane-scope-check prints. Sets SG_KIND (clear | overlap |
# unreadable), SG_OUT (the printed lines), SG_FILES / SG_LANES (the shared files / the other lanes, comma-joined),
# SG_UNREAD (the unreadable parts, `; `-joined), SG_WIDEN (the pending widening, comma-joined), SG_BRIEF.
_lanes_sg_check() {
  local tmp tab item sl sp si sr sb src f un="" ov rows
  tab="$(printf '\t')"; SG_KIND=""; SG_OUT=""; SG_FILES=""; SG_LANES=""; SG_UNREAD=""; SG_WIDEN=""
  tmp="$(mktemp -d 2>/dev/null)" || { SG_KIND=unreadable; SG_UNREAD="no temp dir"; SG_OUT="unreadable — no temp dir"; return 0; }
  item="$(_lt_get "$LN_TABLE" "$LN_LANE" 3 2>/dev/null)"
  SG_BRIEF="$(_lanes_sg_brief "$LN_DIR" "$LN_DIR/.supervisor/automate/$LN_RUN.md")"
  if [ -z "$item" ] || [ "$item" = - ]; then un="$LN_LANE has no lane-table row in $LN_PARENT.lanes"
  elif [ -z "$SG_BRIEF" ]; then un="$LN_LANE has no saved brief this pass (no launch-pad saved line in its run file)"
  elif [ ! -f "$SG_BRIEF" ] || [ ! -r "$SG_BRIEF" ]; then un="$LN_LANE brief ${SG_BRIEF#"$LN_DIR"/}"
  elif ! _lanes_sg_set "$LN_DIR" "$item" "$SG_BRIEF" "$tmp/me"; then un="$LN_LANE Touches (plan-waves --touches failed)"
  fi
  : > "$tmp/sh"; : > "$tmp/un"
  [ -z "$un" ] || printf '%s\n' "$un" >> "$tmp/un"
  if [ -z "$un" ]; then
    rows="$(_lanes_sg_wave_rows "$LN_LANE")"
    while IFS="$tab" read -r sl sp si sr; do
      [ -n "$sl" ] || continue
      sb="$(_lanes_sg_brief "$sp" "$sp/.supervisor/automate/$sr.md")"
      if [ -n "$sb" ] && { [ ! -f "$sb" ] || [ ! -r "$sb" ]; }; then printf '%s brief %s\n' "$sl" "${sb#"$sp"/}" >> "$tmp/un"; continue; fi
      if [ -n "$sb" ]; then src="saved brief"; else src="reserved Touches"; fi
      if [ ! -d "$sp" ] || ! _lanes_sg_set "$sp" "$si" "$sb" "$tmp/o"; then printf '%s Touches (plan-waves --touches failed)\n' "$sl" >> "$tmp/un"; continue; fi
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        if _lanes_is_declared "$f" "$tmp/o"; then printf '%s\t%s (%s)\n' "$f" "$sl" "$src" >> "$tmp/sh"; fi
      done < "$tmp/me"
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        if _lanes_is_declared "$f" "$tmp/me"; then printf '%s\t%s (%s)\n' "$f" "$sl" "$src" >> "$tmp/sh"; fi
      done < "$tmp/o"
    done <<<"$rows"
  fi
  ov="$(env LC_ALL=C sort -u "$tmp/sh" | awk -F'\t' '{ if (!($1 in L)) { P[++n] = $1; L[$1] = $2 } else L[$1] = L[$1] ", " $2 }
    END { for (i = 1; i <= n; i++) print "overlap — " P[i] " shared with " L[P[i]] }')"
  SG_FILES="$(cut -f1 "$tmp/sh" | env LC_ALL=C sort -u | paste -sd ',' - | sed 's/,/, /g')"
  SG_LANES="$(cut -f2 "$tmp/sh" | sed 's/ (.*//' | env LC_ALL=C sort -u | paste -sd ',' - | sed 's/,/, /g')"
  if [ -n "$SG_BRIEF" ] && [ -r "$SG_BRIEF" ]; then SG_WIDEN="$(_lanes_sg_widening "$SG_BRIEF" | paste -sd ',' - | sed 's/,/, /g')"; fi
  if [ -s "$tmp/un" ]; then SG_KIND=unreadable; SG_UNREAD="$(paste -sd ';' "$tmp/un" | sed 's/;/; /g')"
  elif [ -n "$ov" ]; then SG_KIND=overlap
  else SG_KIND=clear; fi
  SG_OUT="$(sed 's/^/unreadable — /' "$tmp/un"; [ -z "$ov" ] || printf '%s\n' "$ov"; [ "$SG_KIND" != clear ] || echo clear)"
  if [ -n "$SG_WIDEN" ]; then
    SG_OUT="$(printf '%s\n' "$SG_OUT"; printf '%s\n' "$SG_WIDEN" | tr ',' '\n' | sed 's/^ *//; /^$/d; s/^/widening — /')"
  fi
  rm -rf "$tmp"
  return 0
}

lanes_scope_check() {
  local target="${1:-}" dir
  [ "$#" -eq 1 ] || die "lane-scope-check: usage: lane-scope-check <lane_dir|L<n>>"
  dir="$(_lanes_resolve "$target")"
  _lane_ctx "$dir" || die "lane-scope-check: not a lane: $target"
  _lanes_sg_check
  printf '%s\n' "$SG_OUT"
}

# _lanes_sg_release <lane runfile> <release tail> — `## Status: running` + `pause_reason: null` in ONE validated
# runfile-write of a staged copy, then the lane line `scope re-gate released <tail>`; 1 with SG_WHY on a failure
_lanes_sg_release() {
  local stg out=""
  stg="$(mktemp "${TMPDIR:-/tmp}/lane-scope.XXXXXX" 2>/dev/null)" || { SG_WHY="no temp file"; return 1; }
  if ! awk '!d && /^## Status:/ { print "## Status: running"; d = 1; next } { print }' "$1" > "$stg" 2>/dev/null \
     || ! out="$(bash "$HELPERS" current-set "$stg" --pause-reason null 2>&1 </dev/null)" \
     || ! out="$(bash "$HELPERS" runfile-write "$1" < "$stg" 2>&1)"; then
    rm -f "$stg"; SG_WHY="the release write failed: $(printf '%s\n' "${out:-awk}" | head -1)"; return 1
  fi
  rm -f "$stg"
  bash "$HELPERS" progress-append "$1" "$(now_utc) scope re-gate released $2" >/dev/null 2>&1 </dev/null \
    || { SG_WHY="the release line could not be appended"; return 1; }
}
# _lanes_sg_launch <owner command> — the existing decision-free relaunch (LOOMWRIGHT_LANES_SCOPE_LAUNCH: test seam)
_lanes_sg_launch() {
  local out
  if [ -n "${LOOMWRIGHT_LANES_SCOPE_LAUNCH:-}" ]; then
    # shellcheck disable=SC2086
    out="$($LOOMWRIGHT_LANES_SCOPE_LAUNCH "$LN_DIR" --continue --owner-command "$1" 2>&1 </dev/null)"
  else out="$(bash "$SELF" lane-launch "$LN_DIR" --continue --owner-command "$1" 2>&1 </dev/null)"; fi
  printf '%s\n' "$out" | sed '/^$/d' | head -1
}
_lanes_sg_parent() { bash "$HELPERS" progress-append "$LN_PRIMARY/.supervisor/automate/$LN_PARENT.md" "$(now_utc) scope re-gate: $1" >/dev/null 2>&1 </dev/null; }

lanes_scope_decide() {
  local target="" dec="" after="" gate="" own="" dir rf pause pid st line="" tail="" keep tab r ap ai ar ast pr num j sha hr fh br m
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --after|--gate|--owner-command) [ "$#" -ge 2 ] || die "lane-scope-decide: $1 needs a value"
        case "$1" in --after) after="$2" ;; --gate) gate="$2" ;; *) own="$2" ;; esac; shift 2 ;;
      -*) die "lane-scope-decide: unknown option $1" ;;
      *) if [ -z "$target" ]; then target="$1"; elif [ -z "$dec" ]; then dec="$1"; else die "lane-scope-decide: unexpected argument $1"; fi; shift ;;
    esac
  done
  case "$dec" in continue|serialize|defer|drop|revise) ;; *) die "lane-scope-decide: usage: lane-scope-decide <lane_dir|L<n>> <continue|serialize|defer|drop|revise> [--after L<m>] [--gate AUT-OVERLAP|LP-SCOPE] [--owner-command '<cmd>']" ;; esac
  case "$gate" in ''|AUT-OVERLAP|LP-SCOPE) ;; *) die "lane-scope-decide: --gate must be AUT-OVERLAP or LP-SCOPE" ;; esac
  dir="$(_lanes_resolve "$target")"
  _lane_ctx "$dir" || die "lane-scope-decide: not a lane: $target"
  _sgr() { echo "lane-scope-decide: refused — $LN_LANE — $1"; return 1; }
  rf="$LN_DIR/.supervisor/automate/$LN_RUN.md"; tab="$(printf '\t')"
  pause="$(_lanes_runfile_fields "$rf" | cut -f2)"
  case "$pause" in
    scope_hold) ;;
    no_pr_stop) case "$dec" in defer|drop) gate=no_pr_stop ;; *) _sgr "parked no_pr_stop — only defer or drop apply: there is no brief to continue from; nothing written"; return 1 ;; esac ;;
    *) _sgr "not held (pause_reason ${pause:--}) — nothing written"; return 1 ;;
  esac
  pid="$(_lt_get "$LN_TABLE" "$LN_LANE" 5)"; st="$(_lt_get "$LN_TABLE" "$LN_LANE" 6)"
  if lanes_proc_alive "$pid" "$st" "$LN_DIR"; then _sgr "a lane process runs (pid $pid) — nothing written"; return 1; fi
  [ "$dec" != drop ] || [ "$gate" = LP-SCOPE ] || [ "$gate" = no_pr_stop ] || { _sgr "drop answers only LP-SCOPE — pass --gate LP-SCOPE; nothing written"; return 1; }
  case "$dec" in serialize|defer|drop|revise)
    [ -n "$gate" ] || { _sgr "$dec is the owner's answer — name the question with --gate AUT-OVERLAP|LP-SCOPE; nothing written"; return 1; } ;; esac
  case "$dec" in continue|serialize|revise)
    [ -n "$own" ] || { echo "lane-scope-decide: BLOCKED — $LN_LANE — no owner-invoked command — need the owner"; return 3; } ;; esac
  [ "$pause" = no_pr_stop ] || _lanes_sg_check
  case "$dec" in
    continue)
      if [ "$SG_KIND" != clear ] && [ "$gate" != AUT-OVERLAP ]; then
        _sgr "the re-check reads $SG_KIND ($(printf '%s\n' "$SG_OUT" | head -1)) — continue needs the owner's AUT-OVERLAP answer (--gate AUT-OVERLAP); nothing written"; return 1
      fi
      if [ -n "$SG_WIDEN" ] && [ -z "$gate" ]; then
        _sgr "the brief's widening is pending ($SG_WIDEN) — continue needs the owner's LP-SCOPE answer (--gate LP-SCOPE); nothing written"; return 1
      fi
      case "$SG_KIND" in
        clear) line="$LN_LANE clear" ;;
        overlap) line="$LN_LANE continue in parallel — shares $SG_FILES with $SG_LANES" ;;
        *) line="$LN_LANE continue in parallel — unreadable: $SG_UNREAD${SG_FILES:+; shares $SG_FILES with $SG_LANES}" ;;
      esac
      tail="(continue)" ;;
    revise)
      keep="$SG_FILES"; [ -n "$keep" ] || keep="$SG_WIDEN"
      tail="(revise)${keep:+ — keep off: $keep}"; line="$LN_LANE revise — re-runs its Launch Pad phase ($gate)" ;;
    serialize)
      case "$after" in L[0-9]|L[0-9][0-9]) ;; *) _sgr "serialize needs --after L<m> (the lane it waits for); nothing written"; return 1 ;; esac
      r="$(_lanes_sg_wave_rows "$LN_LANE" | awk -F'\t' -v a="$after" '$1 == a')"
      [ -n "$r" ] || { _sgr "$after is no other live lane of this wave; nothing written"; return 1; }
      IFS="$tab" read -r _ ap ai ar <<<"$r"
      if _lanes_sg_wait_cycle "$LN_LANE" "$after"; then
        _sgr "serializing after $after would deadlock: $after already waits for $LN_LANE — nothing written; choose Continue in parallel, Defer to next wave or Revise"; return 1
      fi
      ast="$(_lanes_state_of "$after")"
      case "$ast" in escalated|failed|died|lost_to_reset|gone|drain_died|no_pr_stop|abandoned|removed|missing)
        _sgr "$after ended $ast, so it will never read ready_for_release — nothing written; ask AUT-OVERLAP again"; return 1 ;;
      esac
      if ! awk -v a="$after" '/^- / { x = substr($0, 3); if (x ~ /^[0-9][0-9][0-9][0-9]-/) sub(/^[^ ]+ /, "", x)
            if (index(x, "scope_hold — ") == 1) w = 0; else if (x == "scope re-gate: scope_wait " a " (serialize)") w = 1 } END { exit !w }' "$rf" 2>/dev/null; then
        bash "$HELPERS" progress-append "$rf" "$(now_utc) scope re-gate: scope_wait $after (serialize)" >/dev/null 2>&1 </dev/null \
          || { _sgr "the scope_wait line could not be appended"; return 1; }
        _lanes_sg_parent "$LN_LANE serialize — scope_wait: $after${SG_FILES:+ (shares $SG_FILES)}" \
          || echo "lane-scope-decide: WARNING — the parent ## Progress line could not be appended" >&2
      fi
      case "$ast" in ready_for_release|awaiting_merge|merged) ;;
        *) echo "lane-scope-decide: held — $LN_LANE waits for $after ($ast); re-run this command once lane-wait reports $after ready_for_release"; return 0 ;;
      esac
      pr="$(_lanes_dash "$(_lanes_runfile_fields "$ap/.supervisor/automate/$ar.md" | cut -f3)")"; num="${pr##*/}"
      case "$num" in ''|*[!0-9]*) _sgr "$after records no PR in its run file — nothing merged, still held"; return 1 ;; esac
      j="$("$LANES_GH" pr view "$pr" --json headRefOid,headRefName 2>/dev/null </dev/null)"
      sha="$(jq -r '.headRefOid // empty' <<<"$j" 2>/dev/null)"; hr="$(jq -r '.headRefName // empty' <<<"$j" 2>/dev/null)"
      if [ "${#sha}" != 40 ] || [ -n "$(printf '%s' "$sha" | tr -d '0-9a-f')" ] || [ -z "$hr" ]; then
        _sgr "$after's PR #$num head unreadable — nothing merged, still held"; return 1
      fi
      [ -z "$(git -C "$LN_DIR" status --porcelain 2>/dev/null)" ] || { _sgr "dirty working tree — nothing merged, still held"; return 1; }
      br="$(git -C "$LN_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)"
      if ! git -C "$LN_DIR" merge-base --is-ancestor "$sha" HEAD 2>/dev/null; then
        git -C "$LN_DIR" fetch -q origin "$hr" </dev/null 2>/dev/null || { _sgr "git fetch origin $hr failed — nothing merged, still held"; return 1; }
        fh="$(git -C "$LN_DIR" rev-parse -q --verify FETCH_HEAD 2>/dev/null)"
        [ "$fh" = "$sha" ] || { _sgr "origin $hr is at ${fh:-nothing}, not PR #$num's exact head $sha — nothing merged, still held"; return 1; }
        # automate-lanes.sh executes no merge (the AG6 static guard: no lane subcommand merges): the merge of the exact
        # head is PRINTED, run by hand in the held lane (a conflict is the owner's, never force-resolved), then this
        # same command re-run sees the head in HEAD and releases
        m="$(printf 'Merge lane %s (%s) PR #%s — serialized before %s (scope re-gate)' "$after" "$ai" "$num" "$LN_LANE")"
        echo "lane-scope-decide: integrate — $LN_LANE stays held; $after's PR #$num head is fetched: in $LN_DIR run the next line (a conflict stops: the owner resolves it, never forced), then re-run this command"
        echo "git merge --no-ff $sha -m \"$m\""
        return 0
      fi
      tail="(serialized after $after — merged PR #$num head ${sha:0:12})"
      line="$LN_LANE serialized after $after — merged $after's PR #$num exact head ${sha:0:12} into $br" ;;
    defer|drop)
      m="$(_lanes_pending_question "$LN_INBOX")" && { _sgr "awaiting_input — unanswered question $m; nothing written"; return 1; }
      m="$(_lanes_live_watchers "$LN_DIR")"; [ -z "$m" ] || { _sgr "live merge watcher (pid ${m%%"$tab"*}); nothing written"; return 1; }
      [ -z "$(git -C "$LN_DIR" status --porcelain 2>/dev/null)" ] || { _lanes_remove_event "dirty working tree"; _sgr "dirty working tree — nothing written"; return 1; }
      for br in $(git -C "$LN_DIR" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null); do
        m="$(git -C "$LN_DIR" rev-list --count "$br" --not --remotes=origin 2>/dev/null)" || m=""
        case "$m" in 0) ;; *) _lanes_remove_event "branch $br: ${m:-an unreadable count of} commit(s) not on origin"; _sgr "branch $br: ${m:-an unreadable count of} commit(s) not on origin — nothing written"; return 1 ;; esac
      done
      _lanes_sg_defer "$dec"; return $? ;;
  esac
  if [ -n "$SG_WIDEN" ] && [ -n "$gate" ] && [ "$dec" != revise ] && [ -n "$SG_BRIEF" ]; then
    if awk -v g="$gate" -v d="$(date -u +%Y-%m-%d)" '/^## / { s = ($0 == "## Scope widening") }
        s && /^- decision: pending-coordinator[[:space:]]*$/ { print "- accepted: " g " " d; next } { print }' "$SG_BRIEF" > "$SG_BRIEF.tmp.$$" 2>/dev/null; then
      mv "$SG_BRIEF.tmp.$$" "$SG_BRIEF"; line="$line; widening accepted ($gate): $SG_WIDEN"
    else rm -f "$SG_BRIEF.tmp.$$"; _sgr "the brief's widening line could not be rewritten — nothing released"; return 1; fi
  fi
  _lanes_sg_release "$rf" "$tail" || { _sgr "$SG_WHY"; return 1; }
  _lanes_sg_parent "$line" || echo "lane-scope-decide: WARNING — the parent ## Progress line could not be appended" >&2
  echo "lane-scope-decide: released $LN_LANE $tail"
  echo "lane-scope-decide: relaunch — $(_lanes_sg_launch "$own")"
}

# _lanes_sg_defer <defer|drop> — lane-scope-decide defer / drop, in its scope (after the refusals): the lane leaves
# this wave unclaimed; `drop` also checks its Queue row off, so no later wave plans it again
_lanes_sg_defer() {
  local how="$1" prf="$LN_PRIMARY/.supervisor/automate/$LN_PARENT.md" wl k="" items rest item sv out by="the scope re-gate ($gate)"
  [ "$gate" = no_pr_stop ] && by="the owner after its no-PR stop"
  item="$(_lt_get "$LN_TABLE" "$LN_LANE" 3)"
  bash "$HELPERS" progress-append "$rf" "$(now_utc) scope re-gate: $([ "$how" = drop ] && echo dropped || echo 'deferred to the next wave') ($gate)" >/dev/null 2>&1 </dev/null \
    || { _sgr "the lane line could not be appended — nothing removed"; return 1; }
  sv="$(_lanes_salvage "$LN_DIR" "$LN_ROOT/salvage" "$LN_LANE-deferred")" || { _lanes_remove_event "salvage failed"; _sgr "salvage failed — nothing removed"; return 1; }
  wl="$(awk '/^## / { sec = $0; next } sec == "## Current" && /^- wave: / { print; exit }' "$prf" 2>/dev/null)"
  if [ -n "$wl" ]; then
    k="$(printf '%s' "$wl" | sed -n 's/^- wave: *\([0-9][0-9]*\).*/\1/p')"
    items="$(printf '%s' "$wl" | sed -n 's/^- wave: [^|]*| *items: *//p')"
    rest="$(printf '%s\n' "$items" | tr ',' '\n' | sed 's/^ *//; s/ *$//; /^$/d' | grep -vxF -- "$item" | paste -sd ',' -)"
    if [ -n "$rest" ]; then out="$(bash "$HELPERS" current-wave "$prf" --wave "$k" --items "$rest" 2>&1 </dev/null)"
    else out="$(bash "$HELPERS" current-wave "$prf" --wave null 2>&1 </dev/null)"; fi \
      || { _sgr "current-wave failed ($(printf '%s\n' "$out" | head -1)) — the lane is kept (salvage $sv)"; return 1; }
  fi
  rm -rf "$LN_DIR" || { _sgr "could not remove $LN_DIR"; return 1; }
  _lt_set "$LN_TABLE" "$LN_LANE" 8 abandoned || echo "lane-scope-decide: WARNING — the lane table state could not be set" >&2
  bash "$HELPERS" progress-append "$prf" "lane abandoned: $LN_LANE ($LN_RUN) — deferred to the next wave by $by; salvage kept at <primary>-lanes/$LN_PARENT/salvage/${sv##*/}" >/dev/null 2>&1 </dev/null \
    || echo "lane-scope-decide: WARNING — the parent abandon line could not be appended" >&2
  _lanes_event lane-remove pass removed
  if [ "$how" = drop ]; then
    _lanes_sg_parent "$LN_LANE drop — $item checked off, stopped by $by" \
      || echo "lane-scope-decide: WARNING — the parent ## Progress line could not be appended" >&2
    out="$(bash "$HELPERS" queue-checkoff "$prf" "$item" "stopped by $by" skipped 2>&1 </dev/null)" \
      || { _sgr "the lane is removed but $item could not be checked off ($(printf '%s\n' "$out" | head -1)) — check it off by hand"; return 1; }
    echo "lane-scope-decide: dropped $LN_LANE — $item is checked off # skipped; the lane is removed (salvage $sv)"
    echo "remaining: $(bash "$HELPERS" remaining "$prf" 2>/dev/null </dev/null)"
    return 0
  fi
  _lanes_sg_parent "$LN_LANE defer to next wave — $item left unchecked for the next plan-waves${SG_FILES:+ (shared $SG_FILES with $SG_LANES)}" \
    || echo "lane-scope-decide: WARNING — the parent ## Progress line could not be appended" >&2
  echo "lane-scope-decide: deferred $LN_LANE — $item leaves wave ${k:-?} unchecked; the lane is removed (salvage $sv)"
}

# _lanes_sg_wait_cycle <me> <after> — 0 when <after> already waits, directly or through other held lanes, for <me>
_lanes_sg_wait_cycle() {
  local held cur="$2" w i=0
  held="$(_lanes_scope_held "$LN_TABLE")"
  while [ "$i" -lt 100 ]; do
    w="$(printf '%s\n' "$held" | awk -F'\t' -v l="$cur" '$1 == l { print $5 }')"
    case "$w" in ''|-) return 1 ;; "$1") return 0 ;; esac
    cur="$w"; i=$((i + 1))
  done
  return 0   # a wait chain this long is a cycle among other lanes: fail CLOSED
}
# _lanes_sg_wait_broken <table> <lane> — 0 when the awaited <lane> can never reach ready_for_release: removed,
# abandoned or gone in the table, its clone or run gone, a died marker, or its run parked on a terminal reason
_lanes_sg_wait_broken() {
  local tab path run ts f
  tab="$(printf '\t')"
  IFS="$tab" read -r path run ts <<<"$(awk -F'\t' -v l="$2" '$1 == l { r = $2 "\t" $4 "\t" $8 } END { print r }' "$1" 2>/dev/null)"
  [ -n "$path" ] || return 0
  case "$ts" in removed|abandoned|gone) return 0 ;; esac
  { [ -d "$path" ] && [ ! -e "$path.died" ]; } || return 0
  f="$path/.supervisor/automate/$run.md"
  [ -f "$f" ] || return 1
  grep -qE '^- pause_reason: *(escalated|failed|drain_died|gone|no_pr_stop)[[:space:]]*$' "$f"
}
# _lanes_scope_held <table> — READ-ONLY, fail SAFE: one `lane<TAB>path<TAB>held_at<TAB>decided (0|1)<TAB>scope_wait lane|-`
# row per lane-table lane whose run file parks `pause_reason: scope_hold`. `decided` = a `scope re-gate` line follows
# the lane's last `scope_hold —` line, except a serialize whose awaited lane has ended, which reads undecided again
# (nothing would ever release it). Read by `lane-status --inbox` (_lanes_scope_inbox_rows) and the coordinator's
# Stop hook guard-lane-wait-armed.sh (an undecided hold blocks the turn end).
_lanes_scope_held() {
  local tab lane path item run row rl ra rd rw table="$1"
  tab="$(printf '\t')"
  awk -F'\t' '$1 ~ /^L[0-9][0-9]?$/ { if (!($1 in R)) O[++n] = $1; R[$1] = $0 } END { for (i = 1; i <= n; i++) print R[O[i]] }' "$1" 2>/dev/null \
    | while IFS="$tab" read -r lane path item run _; do
        [ -f "$path/.supervisor/automate/$run.md" ] || continue
        row="$(awk -v l="$lane" -v p="$path" '/^## / { sec = $0; next }
          sec == "## Current" && /^- pause_reason: *scope_hold[[:space:]]*$/ { h = 1 }
          sec == "## Progress" && /^- / { x = substr($0, 3); t = ""
            if (x ~ /^[0-9][0-9][0-9][0-9]-/) { t = x; sub(/ .*/, "", t); sub(/^[^ ]+ /, "", x) }
            if (index(x, "scope_hold — ") == 1) { at = t; d = 0; w = "-" }
            else if (index(x, "scope re-gate") == 1) { d = 1; if (index(x, "scope re-gate: scope_wait ") == 1) { w = substr(x, 27); sub(/ .*/, "", w) } } }
          END { if (h) printf "%s\t%s\t%s\t%d\t%s\n", l, p, (at == "" ? "unknown" : at), d, (w == "" ? "-" : w) }' "$path/.supervisor/automate/$run.md" 2>/dev/null)"
        [ -n "$row" ] || continue
        IFS="$tab" read -r rl _ ra rd rw <<<"$row"
        if [ "$rd" = 1 ] && [ "$rw" != - ] && _lanes_sg_wait_broken "$table" "$rw"; then row="$rl$tab$path$tab$ra${tab}0$tab-"; fi
        printf '%s\n' "$row"
      done
}
# _lanes_scope_inbox_rows <table> — the held lanes as `lane-status --inbox` rows (its JSON shape: at, lane, id, qs):
# an undecided hold is the AUT-OVERLAP decision (its labels read from the catalog), a serialized one names its wait
_lanes_scope_inbox_rows() {
  local tab lane path at d w labels
  tab="$(printf '\t')"
  labels="$(bash "$POLICY" catalog 2>/dev/null </dev/null | awk -F'\t' '$1 == "AUT-OVERLAP" { print $3 }')"
  _lanes_scope_held "$1" | while IFS="$tab" read -r lane path at d w; do
    if [ "$d" = 1 ] && [ "$w" != - ]; then
      jq -n -c --arg at "$at" --arg l "$lane" --arg w "$w" '{at: $at, lane: $l, id: "scope_hold", qs: [{header: "scope_wait",
        question: ($l + " waits for " + $w + " (Serialize): re-run lane-scope-decide " + $l + " serialize --after " + $w + " --gate AUT-OVERLAP --owner-command <cmd> once " + $w + " reads ready_for_release"), options: []}]}'
    else
      jq -n -c --arg at "$at" --arg l "$lane" --arg o "$labels" '{at: $at, lane: $l, id: "scope_hold", qs: [{header: "AUT-OVERLAP",
        question: ($l + " is held before its Supervisor phase (scope_hold): run lane-scope-check " + $l + " — clear ⇒ lane-scope-decide " + $l + " continue; otherwise ask the owner"),
        options: ($o | split("|") | map(select(. != "") | {label: .}))}]}'
    fi
  done
}
