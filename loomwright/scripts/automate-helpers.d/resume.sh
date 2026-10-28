# --help usage (the `#:  ` lines): this family's segment of automate-helpers.sh --help, assembled
# by the dispatcher's _ah_usage in _AH_HELP_SEGMENTS order; fixture: fixtures/automate-helpers-help/resume.golden.
#:  resume-glob      <automate_dir> [--finalize]        # §4 (--finalize: run finalize-empty on each candidate first, list the rest; finalize lines on stderr) list run files (is_run_file: a "# Automate Run:" title line anywhere — BOM/0-3-space indent/whitespace/case tolerant, RUN_TITLE_ERE) not "## Status: done"; §6 result sidecars never listed because they carry no such line
#:  reconcile-item   <pr_url> <belief>                  # §4 belief vs gh/git truth -> corrected state
#:  park-ask-gate    <runfile> <item> <pr_url> [--wait <s>]  # §6 "Dismissed-findings decision step (before the park)" park-first READY park: READ-ONLY; `ask — fix-now allowed: …` only when ## Current names this item+PR at status awaiting_merge, a <run_id>.merge-watch marker carries this PR (polled every 1s for up to --wait <s>, default 0) and `gh pr view --json state` reads exactly OPEN; `ask — fix-now unavailable: …` on MERGED/CLOSED/other/unreadable or a closed-out (done) item; else one `refuse — <reason>` line (ask nothing); exit 0 (usage error 1)

# --------------------------------------------------------------------------- #
# §4 — resume: glob + reconcile (run-file is BELIEF; git/gh is TRUTH)
# --------------------------------------------------------------------------- #

# resume-glob <automate_dir> — list RUN FILES (is_run_file: they carry the
# `# Automate Run:` title line) that are NOT marked "## Status: done". A *.md
# without that title — the §6 steps 2-3 result sidecars
# (`<run_id>.review-heal-result.md`, `<run_id>.supervisor-result.md`), transient
# or committed — is skipped BEFORE the done check, so it is never reported as an
# incomplete run (it has no `## Status:` line, so `is_done` alone would list it,
# and >1 listed run fails RESUME closed as `resume_ambiguous`).
#
# resume-glob <automate_dir> --finalize — SKILL §4 step 1: first runs
# `finalize-empty` (automate-trail.sh — the git/PR mutator carve-out; this helper
# only dispatches it) on every candidate the plain glob lists, then lists only the
# ones still not `## Status: done`. stdout keeps the plain form's shape (one path
# per line, sorted) so a caller's list parse is unchanged; diagnostics go to
# stderr: a finalized run's output lines verbatim (the first names the run), and
# `resume-glob: <path> not finalized — <line>` for a candidate that WAS eligible
# but was not finalized (run lock held, a refused write). An ineligible candidate
# (not paused / another pause_reason / an unchecked row / ## Current not done)
# prints nothing extra and is listed exactly as the plain form lists it.
#
# LANE RUNS (parallel-automate/05, D3): a lane's run file (title run-id token
# `<parent_run_id>-L<digits>`) reaches the primary on the next metadata pull, so
# both forms skip it (`_resume_lane_skip`) — finished or not — EXCEPT the run
# named by a present `<dir>/../lane.json` (`.supervisor/lane.json`: this checkout
# IS that lane, and a lane must still resume itself). Inside a lane clone (a
# present lane.json) both forms list ONLY that lane's own run file, so `--finalize`
# never offers finalize-empty another run's file (the coordinator closes those out,
# once, in the primary); an unreadable lane.json run_id lists nothing. With no
# lane.json and no `-L<n>` run files the output is unchanged.
resume_glob() {
  local dir="" fin=0 a f
  for a in "$@"; do
    case "$a" in --finalize) fin=1 ;; *) [ -z "$dir" ] && dir="$a" ;; esac
  done
  [ -d "$dir" ] || return 0
  if [ "$fin" = 0 ]; then
    _resume_glob_list "$dir"; return 0
  fi
  local cands out
  cands="$(_resume_glob_list "$dir")"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    out="$(bash "$(dirname "$0")/automate-trail.sh" finalize-empty "$f" 2>/dev/null)"
    case "$out" in
      "finalize-empty: finalized "*) printf '%s\n' "$out" >&2 ;;
      "finalize-empty: skipped — not paused"|"finalize-empty: skipped — pause_reason "*|\
      "finalize-empty: skipped — "[0-9]*" unchecked item(s) remain"|"finalize-empty: skipped — ## Current status "*) ;;
      *) printf 'resume-glob: %s not finalized — %s\n' "$f" "$(printf '%s\n' "$out" | head -n1)" >&2 ;;
    esac
  done <<EOF
$cands
EOF
  _resume_glob_list "$dir"
}

# _resume_title_run_id <runfile> — the run-id token of the `# Automate Run: <id> — …`
# title (first whitespace-delimited word after the prefix); empty when absent.
_resume_title_run_id() {
  awk '/^# Automate Run:/ { sub(/^# Automate Run:[ ]*/, ""); split($0, w, /[ \t]+/); print w[1]; exit }' "$1" 2>/dev/null
}

# _resume_lane_own <automate_dir> — the `run_id` of `<dir>/../lane.json` (the
# D2 lane marker, `.supervisor/lane.json`), or empty when absent/unreadable.
_resume_lane_own() {
  local lj="$1/../lane.json"
  [ -f "$lj" ] || return 0
  "$JQ" -r '.run_id // empty | strings' "$lj" 2>/dev/null | head -n1
}

# _resume_lane_skip <runfile> <own_run_id> — succeeds (skip the file) when its
# title run-id token is a lane id that is not <own_run_id> (the present
# lane.json's run; empty when this checkout is not a lane). A lane id is
# `<parent_run_id>-L<digits>` (D2/D3) of a REAL parent: either the parent is an
# engine-minted id (`automate-YYYY-MM-DD-HHMMSS`), or a run file titled with the
# parent id sits in the same directory (the coordinator's own run, finished or
# not). A hand-made run whose id merely ends `-L<digits>` (e.g. `nightly-L3`
# with no `nightly` run beside it) is not a lane run and stays listed. A
# non-lane run file is never skipped here.
_resume_lane_skip() {
  local id parent g
  id="$(_resume_title_run_id "$1")"
  grep -Eq -- '-L[0-9]+$' <<<"$id" || return 1
  [ -n "$2" ] && [ "$id" = "$2" ] && return 1
  grep -Eq -- '^automate-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}-L[0-9]+$' <<<"$id" && return 0
  parent="${id%-L*}"
  [ -n "$parent" ] || return 1
  for g in "$(dirname "$1")"/*.md; do
    [ -e "$g" ] && [ "$g" != "$1" ] || continue
    is_run_file "$g" || continue
    [ "$(_resume_title_run_id "$g")" = "$parent" ] && return 0
  done
  return 1
}

# _resume_glob_list <dir> — the plain glob (byte-identical to the pre-finalize form
# when no lane run file is present).
_resume_glob_list() {
  local dir="$1" f own
  own="$(_resume_lane_own "$dir")"
  for f in "$dir"/*.md; do
    [ -e "$f" ] || continue
    is_run_file "$f" || continue
    is_done "$f" && continue
    _resume_lane_skip "$f" "$own" && continue
    if [ -f "$dir/../lane.json" ]; then [ -n "$own" ] && [ "$(_resume_title_run_id "$f")" = "$own" ] || continue; fi
    echo "$f"
  done | env LC_ALL=C sort
}

# reconcile-item <pr_url> <belief> — reconcile a single in-flight item's BELIEF
# (the checkbox/Current status the run file remembers) against GROUND TRUTH via
# gh/git. Prints the CORRECTED state, one of:
#   merged          — PR is MERGED (gh state==MERGED or mergedAt non-null);
#                     item should be "- [x]" regardless of what the file believed.
#   awaiting_merge  — PR is OPEN/unmerged; item stays awaiting_merge even if the
#                     file believed it checked (a premature check-off).
#   gone            — PR is CLOSED-unmerged (neither merged nor open).
# Reconcile ALWAYS prefers ground truth (SKILL §4 / Anti-Pattern: never trust a
# checkbox without reconciling). `gh` is stubbable via the LOOMWRIGHT_GH_BIN
# env override.
#
# SCOPE: this helper resolves the gh-PR-STATE half of reconcile only (merged /
# open / closed-unmerged). The complementary git-branch-LANDED corroboration that
# SKILL §4 lists ("Branch landed? `git branch --contains <sha>`") is performed by
# the loop itself, not here — wiring git into this helper would need stub fixtures
# out of scope for the pure-logic library. So this returning `merged`/`gone` is
# the gh half; it is NOT incomplete.
reconcile_item() {
  # <belief> is accepted for call-site symmetry with the run file's remembered
  # status (SKILL §1.5 signature) but is INTENTIONALLY IGNORED — ground truth
  # (gh/git) always wins (SKILL §4), so it never influences the result.
  local url="$1" belief="${2:-}"
  : "${belief:-}"   # referenced only to mark it deliberately unused
  local view state merged
  if ! view="$("$GH" pr view "$url" --json state,mergedAt 2>/dev/null)"; then
    # Unreadable ⇒ fail closed to the safe non-merged belief.
    echo "awaiting_merge"; return 0
  fi
  state="$(printf '%s' "$view" | "$JQ" -r '.state // empty' 2>/dev/null || true)"
  merged="$(printf '%s' "$view" | "$JQ" -r '.mergedAt // empty' 2>/dev/null || true)"
  if [ "$state" = "MERGED" ] || [ -n "$merged" ]; then
    echo "merged"; return 0
  fi
  if [ "$state" = "OPEN" ]; then
    echo "awaiting_merge"; return 0
  fi
  # CLOSED-unmerged or unknown.
  echo "gone"
}

# park-ask-gate <runfile> <item> <pr_url> [--wait <seconds>] — SKILL §6 "Dismissed-findings
# decision step (before the park)", its "Order — sequential interactive READY park (park
# first, then ask)" list, is the spec (automate-speed/01, owner decisions D2/D3). The engine
# writes the `awaiting_merge` park, arms the merge watcher, notifies and releases the run
# lock FIRST; this gate then says whether the owner's dismissed-findings decisions may be
# asked, and whether `Fix now on this PR` may be offered. READ-ONLY (the run file, the
# marker and the PR are never written). ONE line on stdout:
# - ask — fix-now allowed: PR OPEN, parked awaiting_merge, merge watcher armed
#       ## Current's `- item:` line names <item> (after a leading `./` strip on both sides)
#       and <pr_url> (exactly) at `status: awaiting_merge`, the marker
#       `<runfile dir>/<run_id>.merge-watch` carries `pr_url<TAB><pr_url>`, and this gate's
#       OWN `gh pr view <pr_url> --json state` reads exactly `OPEN`.
# - ask — fix-now unavailable: PR <MERGED|CLOSED|state <s>|state unreadable>
#       the same park, any other state — fail CLOSED toward no fix-now push. NOT
#       `reconcile-item`: it maps an unreadable read to `awaiting_merge` (the safe belief
#       for a merge decision), which is the wrong direction for a push.
# - ask — fix-now unavailable: closed out
#       the item reads `status: done` — the watcher's `closeout` already ran.
# - refuse — <reason>
#       anything else: a missing/unreadable run file, no `## Current` item line, a
#       `## Current` naming another item or PR, a status that is neither `awaiting_merge`
#       nor `done` (e.g. `running`: the park was not written first), or no marker for this
#       PR within --wait. The engine then asks NOTHING; the drafts stay undecided.
# --wait <s> (an integer, default 0 = judge once): the detached watcher writes its marker
# asynchronously — after its single-instance block, up to 60s when it replaces a live
# watcher for another PR — so the gate re-judges every 1s for up to <s>s while the only
# thing missing is the marker (a status that turns `done` meanwhile answers `closed out`).
# The engine passes `--wait 75`. Honest limit: a marker is trusted by its `pr_url` alone
# (the watcher removes it on every exit, so a stale one needs a SIGKILLed watcher), and a
# merge landing after this read is not prevented. Exit 0; a usage error exits 1.
park_ask_gate() {
  local rf="" item="" pr="" wait=0 k=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --wait)
        [ "$#" -ge 2 ] || die "park-ask-gate: --wait needs a value"
        case "$2" in ''|*[!0-9]*) die "park-ask-gate: --wait must be a whole number of seconds: '$2'" ;; esac
        wait="$2"; shift 2 ;;
      -*) die "park-ask-gate: unknown option '$1' (usage: park-ask-gate <runfile> <item> <pr_url> [--wait <seconds>])" ;;
      *) k=$((k + 1))
         case "$k" in 1) rf="$1" ;; 2) item="$1" ;; 3) pr="$1" ;; *) die "park-ask-gate: too many arguments" ;; esac
         shift ;;
    esac
  done
  [ -n "$rf" ] && [ -n "$item" ] && [ -n "$pr" ] \
    || die "park-ask-gate: usage: park-ask-gate <runfile> <item> <pr_url> [--wait <seconds>]"
  local marker verdict i=0
  marker="$(dirname "$rf")/$(basename "$rf" .md).merge-watch"
  while :; do
    verdict="$(_pag_judge "$rf" "$item" "$pr" "$marker")"
    [ "$verdict" = "need_marker" ] || break
    [ "$i" -lt "$wait" ] || break
    sleep 1; i=$((i + 1))
  done
  case "$verdict" in
    need_marker) echo "refuse — no merge-watch marker for this PR within ${wait}s"; return 0 ;;
    judged) ;;
    *) echo "$verdict"; return 0 ;;
  esac
  local view state
  if ! view="$("$GH" pr view "$pr" --json state 2>/dev/null)"; then
    echo "ask — fix-now unavailable: PR state unreadable"; return 0
  fi
  state="$(printf '%s' "$view" | "$JQ" -r '.state // empty | strings' 2>/dev/null || true)"
  case "$state" in
    OPEN) echo "ask — fix-now allowed: PR OPEN, parked awaiting_merge, merge watcher armed" ;;
    MERGED|CLOSED) echo "ask — fix-now unavailable: PR $state" ;;
    "") echo "ask — fix-now unavailable: PR state unreadable" ;;
    *) echo "ask — fix-now unavailable: PR state $state" ;;
  esac
}

# _pag_judge <runfile> <item> <pr_url> <marker> — one read of the run file and marker for
# park_ask_gate: prints a final `ask — …` / `refuse — …` line, `need_marker` (the park is
# written but no marker carries this PR yet) or `judged` (park + marker present: the
# caller reads the PR state).
_pag_judge() {
  local rf="$1" item="$2" pr="$3" marker="$4" line ci cp cs mp
  if [ ! -f "$rf" ] || [ ! -r "$rf" ]; then echo "refuse — run file not found or unreadable: $rf"; return 0; fi
  line="$(_current_item_line "$rf")"
  [ -n "$line" ] || { echo "refuse — no ## Current item line"; return 0; }
  ci="$(_current_field "$line" item)"; cp="$(_current_field "$line" pr)"; cs="$(_current_field "$line" status)"
  if [ "${ci#./}" != "${item#./}" ] || [ "$cp" != "$pr" ]; then
    echo "refuse — ## Current is ${ci:-?} (${cp:-?}), not this item/PR"; return 0
  fi
  case "$cs" in
    done) echo "ask — fix-now unavailable: closed out"; return 0 ;;
    awaiting_merge) ;;
    *) echo "refuse — park not written: ## Current status ${cs:-?}, not awaiting_merge"; return 0 ;;
  esac
  mp="$(awk -F'\t' '$1 == "pr_url" { print $2; exit }' "$marker" 2>/dev/null || true)"
  if [ -n "$mp" ] && [ "$mp" = "$pr" ]; then echo "judged"; else echo "need_marker"; fi
}

# --------------------------------------------------------------------------- #
# §6 step 1 — close-out leftover gate (closeout-classify)
# --------------------------------------------------------------------------- #

# CLOSEOUT_TABLE — EVERY `closeout: …` line automate-trail.sh's closeout can print
# (its guards, _sync_primary's SYNC_SKIP reasons, steps 3a/4/3b/5/7/7b), as
# `<class>|<step>|<bash case pattern over the text after "closeout: ">`, first
# match wins. test-automate-trail.sh extracts every closeout string template from
# automate-trail.sh and fails when one matches no row here (a new string must be
# classified on purpose, never fall through silently). A line matching NO row is a
# leftover (`unknown`), and the partial-removal form `removed — worktree …; kept …` is a leftover even though
# its verb row says complete (closeout_classify applies that precedence); a name that merely contains "kept" is classified by its row like any other line.
# Class `run_lock_held` (automate-followups/36 A1) is neither complete nor a leftover: closeout met
# the run lock held by a LIVE process (its refusal line ends `(live pid <p>)`, probed at refusal
# time); a dead or unreadable holder (`(holder pid <p> not running)`) falls to the leftover row.
CLOSEOUT_TABLE='complete|worktree|removed — worktree *
complete|branch|removed — branch *
complete|sync|synced — *
complete|stamp|stamped — *
complete|checkoff|checked — *
complete|current|reconciled — *
complete|worktree|skipped — already removed (no worktree on *)
complete|sync|skipped — already synced (*)
complete|branch|skipped — already deleted (no local *)
complete|stamp|skipped — already stamped
complete|checkoff|skipped — already checked off
complete|current|skipped — ## Current already done
complete|current|skipped — ## Current is * not this item/PR
leftover|worktree|skipped — kept worktree *
leftover|worktree|skipped — head branch unresolved *
leftover|worktree|skipped — head branch is the base branch
leftover|worktree|skipped — * (base branch unknown; worktree cleanup not attempted)
leftover|sync|skipped — * (base branch unknown; sync not attempted)
leftover|sync|skipped — primary checkout is on *
leftover|sync|skipped — uncommitted changes outside the trail paths *
leftover|sync|skipped — git fetch failed
leftover|sync|skipped — git checkout * refused
leftover|sync|skipped — git pull --ff-only refused *
leftover|branch|skipped — branch unresolved
leftover|branch|skipped — branch checked out in primary *
leftover|branch|skipped — local tip * != merged head *
leftover|branch|skipped — git branch -D * refused *
leftover|stamp|skipped — no done brief
leftover|stamp|skipped — requirement not writable
leftover|stamp|skipped — requirement * not found
leftover|checkoff|skipped — queue-checkoff failed
leftover|checkoff|skipped — * not in ## Queue
leftover|current|skipped — ## Current not reconciled *
leftover|current|skipped — no ## Current item line
leftover|current|skipped — ## Current runfile-write refused
run_lock_held|lock|skipped — run lock held by * (live pid *)
leftover|lock|skipped — run lock held by *
leftover|gate|skipped — pr not merged *
leftover|guard|skipped — gh unavailable
leftover|guard|skipped — git unavailable
leftover|guard|skipped — jq unavailable
leftover|guard|skipped — missing argument
leftover|guard|skipped — run file not found
leftover|guard|skipped — not a git checkout
leftover|guard|skipped — run file outside the checkout
leftover|guard|skipped — cannot enter checkout'

# _co_classify_line <text after "closeout: "> — prints `<class><TAB><step>` from
# the first CLOSEOUT_TABLE row whose pattern matches; `leftover<TAB>unknown` when none.
_co_classify_line() {
  local t="$1" cls step pat
  while IFS='|' read -r cls step pat; do
    [ -n "$cls" ] || continue
    # shellcheck disable=SC2254 # the pattern is the point
    case "$t" in $pat) printf '%s\t%s\n' "$cls" "$step"; return 0 ;; esac
  done <<EOF
$CLOSEOUT_TABLE
EOF
  printf 'leftover\tunknown\n'
}

# closeout-classify [--run <run_id> --item <path> --pr <url>] [--record <runfile>]
# SKILL §1.5 / §6 step 1 "Close-out leftover gate" is the spec. Reads ONE closeout
# invocation's output on stdin and classifies ONLY its `closeout: ` lines (the
# passed-through `brief-repair:` / `trail-pr:` lines are ignored, except that a
# non-skip brief-repair line counts as a change for --record). Prints `complete`
# or one `leftover<TAB><run>\t<item>\t<pr>\t<step>\t<detail>` row per leftover
# (`-` for an omitted value), followed by one `run_lock_held<TAB>…` row (same
# columns, step `lock`) per `run lock held by <owner> (live pid <p>)` line — not a
# leftover and not `complete`: the close-out did not run because a live process
# holds the run lock, so --record appends nothing and the caller retries later. Input with no `closeout:` line ⇒ one leftover row
# (step `none`): nothing proves the close-out ran. --record <runfile>: on
# `complete` with no changing step, progress-append `<ts> closeout: nothing to
# close out — <item>` unless that exact line (after its one leading timestamp
# token) is already in ## Progress — at most one per item per run. Exit 0; a
# usage error exits 1 (the caller reads anything but `complete` — or, at start, `run_lock_held` rows alone — as a leftover).
# _co_event <outcome> <code> [--count k=n] — #618: an opt-in telemetry script event (docs/TELEMETRY.md
# "What the engine reports") from the checkout this classifier runs in; fire-and-forget, never
# changes this function's output or status. No git toplevel ⇒ nothing sent.
_co_event() {
  local root; root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
  bash "$(dirname "$0")/emit-script-event.sh" --root "$root" automate-closeout closeout "$@" >/dev/null 2>&1 </dev/null || true
}
closeout_classify() {
  local run="-" item="-" pr="-" rec=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --run|--item|--pr|--record)
        [ "$#" -ge 2 ] && [ -n "$2" ] || die "closeout-classify: $1 needs a value"
        case "$1" in --run) run="$2" ;; --item) item="$2" ;; --pr) pr="$2" ;; --record) rec="$2" ;; esac
        shift 2 ;;
      *) die "closeout-classify: unknown argument '$1' (usage: closeout-classify [--run <run_id> --item <path> --pr <url>] [--record <runfile>])" ;;
    esac
  done
  local tab=$'\t' line t r cls step n=0 changed=0 rows="" held=""
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "brief-repair: "*) case "$line" in *"skipped —"*) ;; *) changed=1 ;; esac; continue ;;
      "closeout: "*) ;;
      *) continue ;;
    esac
    n=$((n + 1)); t="${line#closeout: }"
    r="$(_co_classify_line "$t")"; cls="${r%%"$tab"*}"; step="${r#*"$tab"}"
    case "$t" in "removed — worktree "*"; kept "*) cls=leftover ;; esac  # partial removal; anchored so a NAME containing "kept" never flips a clean line (S3 wave-1 review)
    case "$t" in "removed — "*|"stamped — "*|"checked — "*|"reconciled — "*) changed=1 ;; esac
    [ "$cls" = leftover ] && rows="${rows}leftover$tab$run$tab$item$tab$pr$tab$step$tab${t//$tab/ }"$'\n'
    [ "$cls" = run_lock_held ] && held="${held}run_lock_held$tab$run$tab$item$tab$pr$tab$step$tab${t//$tab/ }"$'\n'
  done
  [ "$n" -gt 0 ] || rows="leftover$tab$run$tab$item$tab$pr${tab}none${tab}no closeout: line in the input"$'\n'
  if [ -n "$rows" ] || [ -n "$held" ]; then
    printf '%s%s' "$rows" "$held"
    # #618: one warn event per distinct leftover step (the closed step set above — a plugin token,
    # never the detail text); a run_lock_held-only result is a retry, not a leftover, and sends nothing.
    local st
    for st in $(printf '%s' "$rows" | awk -F'\t' 'NF { print $5 }' | env LC_ALL=C sort -u); do
      _co_event warn "leftover_$st" --count "rows=$(printf '%s' "$rows" | awk -F'\t' -v s="$st" '$5 == s' | grep -c .)"
    done
    return 0
  fi
  echo "complete"
  _co_event pass complete
  if [ -n "$rec" ] && [ "$item" != "-" ] && [ "$changed" = 0 ] && [ -f "$rec" ]; then
    local want="closeout: nothing to close out — $item"
    if ! _progress_block "$rec" | AH_W="$want" awk '
        BEGIN { w = ENVIRON["AH_W"] }
        { l = $0; sub(/^- /, "", l); if (l == w) f = 1; else { sub(/^[^ ]+ /, "", l); if (l == w) f = 1 } }
        END { exit !f }'; then
      ( progress_append "$rec" "$(date -u +%Y-%m-%dT%H:%M:%SZ) $want" ) >/dev/null 2>&1 || true
    fi
  fi
  return 0
}

