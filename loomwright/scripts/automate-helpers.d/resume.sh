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

# _resume_glob_list <dir> — the plain glob (byte-identical to the pre-finalize form).
_resume_glob_list() {
  local dir="$1" f
  for f in "$dir"/*.md; do
    [ -e "$f" ] || continue
    is_run_file "$f" || continue
    is_done "$f" && continue
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
# (`-` for an omitted value). Input with no `closeout:` line ⇒ one leftover row
# (step `none`): nothing proves the close-out ran. --record <runfile>: on
# `complete` with no changing step, progress-append `<ts> closeout: nothing to
# close out — <item>` unless that exact line (after its one leading timestamp
# token) is already in ## Progress — at most one per item per run. Exit 0; a
# usage error exits 1 (the caller reads anything but `complete` as a leftover).
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
  local tab=$'\t' line t r cls step n=0 changed=0 rows=""
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
  done
  [ "$n" -gt 0 ] || rows="leftover$tab$run$tab$item$tab$pr${tab}none${tab}no closeout: line in the input"$'\n'
  if [ -n "$rows" ]; then printf '%s' "$rows"; return 0; fi
  echo "complete"
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

