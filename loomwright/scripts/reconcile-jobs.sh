#!/usr/bin/env bash
# reconcile-jobs.sh — reconcile `.supervisor/jobs/in-progress/` against on-disk
# ground truth, and (with --repair) finish the lifecycle move the Supervisor's
# completion tail never made.
#
# WHY THIS EXISTS
# ---------------
# The brief lifecycle move `in-progress/` -> `done/` is completion-tail step 2,
# and the originating-requirement stamp is step 2.5 (authority:
# skills/self-heal-advisory/SKILL.md). Both are PROMPT-INSTRUCTED steps executed
# by the agent, not code. When the agent dies before reaching them — e.g. a
# Phase 4.5 reviewer failing with a server error, observed 2026-08-30 on PR #160
# — the brief is stranded in `in-progress/` even though its PR merged and
# shipped. Nothing else reconciles that, so the strand is permanent until a
# human moves the file by hand.
#
# No prompt change can fix this: you cannot make an instruction atomic against
# the agent dying before it is read. Reconciliation after the fact is the only
# durable repair, which is what this script is.
#
# NOT THE FIRST RECONCILER — AND DELIBERATELY DOWNSTREAM OF NOTHING
# -----------------------------------------------------------------
# The repo already reconciles the OTHER half. `stamp-requirement-status.sh`
# (2026-08-04, wired at SessionStart and SubagentStop) closes out step 2.5 by
# keying on a byproduct — a brief landing in `.supervisor/jobs/done/` — for
# exactly the reason argued above, and its header states the general lesson:
# prompt-instructed bookkeeping is unreliable.
#
# But it reads `.supervisor/jobs/done/` EXCLUSIVELY. A brief stranded in
# `in-progress/` is therefore invisible to it: the strand does not merely skip
# step 2, it structurally blocks the existing step-2.5 reconciler from ever
# firing. This script repairs the move that unblocks it. The two compose and do
# NOT overlap — this one never stamps a requirement, that one never moves a
# brief — and both run from the same SessionStart, so a repair here is picked up
# there on the next session.
#
# Note their verdicts differ on purpose: that script stamps
# `## Status: brief-shipped`, never `done`, because a landed brief proves the
# work ran and not that every acceptance criterion was met. This script's
# `stranded_closed` arm treats only `done`/`done_with_escalation` as closed, so
# a `brief-shipped` requirement is correctly NOT read as terminal.
#
# HONEST LIMITS (read before trusting a classification)
# -----------------------------------------------------
# * NO NETWORK, EVER. This script never calls `gh` and never resolves a PR over
#   the wire. It runs from the SessionStart hook on every resume, where a network
#   round-trip would be a latency and offline-correctness problem. Every verdict
#   below is derived from files already on disk.
# * A stranded brief carries NO PR URL of its own — the `## Outcome` block that
#   would carry one is precisely what did not get written. So evidence has to
#   come from elsewhere, and for a plain `/supervisor` run started outside the
#   automation engine there may be NONE. That case is reported `unknown`, never
#   guessed at and never repaired.
# * `unknown` means UNVERIFIED, not "fine" and not "stale". It is the honest
#   answer when the disk cannot settle the question.
#
# CLASSIFICATION (offline, per brief in .supervisor/jobs/in-progress/)
# --------------------------------------------------------------------
#   stranded_merged  An automate run file records this brief's source requirement
#                    as `status: merged` with a PR URL. Strong evidence: that
#                    status is written only after the engine reconciled the merge
#                    against `gh`/`git`. REPAIRABLE.
#   stranded_closed  The source requirement is already stamped done, but the
#                    brief is still in `in-progress/`. That combination can only
#                    mean a partially-executed completion tail (step 2.5 ran,
#                    step 2 did not, or a human stamped it). REPAIRABLE, and the
#                    emitted `## Outcome` says the PR was not determinable.
#   unknown          No offline evidence either way. Reported, NEVER repaired.
#
# EXIT CODES
#   0  always, on every path, including a repair that failed. This is a
#      fail-SAFE reporting/repair tool per the CLAUDE.md bimodal-failure
#      invariant: it is read by a SessionStart hook that must never break a
#      session. Failures are reported on stderr and in the output rows; nothing
#      gates on this script's status. Callers MUST NOT treat exit 0 as "repaired".
#
# USAGE
#   reconcile-jobs.sh                 human-readable report (read-only)
#   reconcile-jobs.sh --porcelain     STATE<TAB>BRIEF<TAB>EVIDENCE, one per line
#   reconcile-jobs.sh --repair        repair every repairable brief, then report
#
# Deliberately vendor-neutral (CORE-classified): names no harness-specific
# variable or path, so `scripts/check-vendor-coupling.sh` holds it at allowance 0.

set -uo pipefail

JOBS_IN=".supervisor/jobs/in-progress"
JOBS_DONE=".supervisor/jobs/done"
AUTOMATE_DIR=".supervisor/automate"
REQ_ROOT=".supervisor/requirements"

PORCELAIN=0
REPAIR=0
for arg in "$@"; do
  case "$arg" in
    --porcelain) PORCELAIN=1 ;;
    --repair)    REPAIR=1 ;;
    -h|--help)   sed -n '2,60p' "$0"; exit 0 ;;
    *) echo "reconcile-jobs: unknown flag '$arg' (see --help)" >&2; exit 0 ;;
  esac
done

# is_done — mirrors automate-helpers.sh's matcher deliberately, including the
# `done_with_escalation` arm: an escalated run still shipped, so its requirement
# must not be re-picked.
is_done() {
  grep -qE '^## Status:[[:space:]]*done(_with_escalation)?\b' "$1" 2>/dev/null
}

# requirement_status <requirement> — echo the terminal value on the `## Status:`
# heading: `done` or `done_with_escalation`. Empty when neither is present.
# is_done() deliberately matches BOTH (an escalated run still shipped), so the
# classification cannot tell them apart on its own — but the file it just read
# still holds the answer, and discarding it would make the emitted `## Outcome`
# assert a cleaner result than the evidence supports.
# NOTE: two greps, not one sed alternation. BSD sed (macOS) does not support
# `\|` in a basic regex, so the sed form returned EMPTY here and silently
# flattened every escalated close-out back to `completed` — caught by executing
# it, not by reading it. Same family as the repo's recorded stat -f/-c flavour
# trap: macOS-green is not the same as portable.
requirement_status() {
  if grep -qE '^## Status:[[:space:]]*done_with_escalation\b' "$1" 2>/dev/null; then
    printf 'done_with_escalation'
  elif grep -qE '^## Status:[[:space:]]*done\b' "$1" 2>/dev/null; then
    printf 'done'
  fi
}

# brief_source_requirement <brief> — the `- **Source requirement:** <path>`
# pointer Launch Pad stamps under `## Environment`. Empty when absent (a direct
# /supervisor run that never had one). Only the FIRST match is honoured.
brief_source_requirement() {
  sed -n 's/^- \*\*Source requirement:\*\*[[:space:]]*//p' "$1" 2>/dev/null | head -1
}

# safe_requirement_path <path> — echo the path only when it resolves UNDER
# .supervisor/requirements/ and exists. Mirrors completion-tail step 2.5's
# traversal guard: a brief is a file we parse, so its fields are untrusted input.
safe_requirement_path() {
  local p="$1"
  [ -n "$p" ] || return 1
  case "$p" in
    "$REQ_ROOT"/*) ;;
    *) return 1 ;;
  esac
  case "$p" in
    *..*) return 1 ;;
  esac
  [ -f "$p" ] || return 1
  printf '%s' "$p"
}

# automate_pr_for_requirement <requirement_path> — scan run files for a
# `## Current` item line naming this requirement with `status: merged`, and echo
# its PR URL. Fields are `|`-separated `key: value` pairs; we parse them rather
# than pattern-matching the whole line so field ORDER is not load-bearing.
automate_pr_for_requirement() {
  local req="$1" f
  [ -d "$AUTOMATE_DIR" ] || return 1
  for f in "$AUTOMATE_DIR"/*.md; do
    [ -f "$f" ] || continue
    REQ="$req" awk -F'|' '
      /^- item:/ {
        item=""; status=""; pr=""
        for (i = 1; i <= NF; i++) {
          field = $i
          sub(/^[[:space:]]*-?[[:space:]]*/, "", field)
          sub(/[[:space:]]+$/, "", field)
          if (field ~ /^item:[[:space:]]*/)   { sub(/^item:[[:space:]]*/, "", field);   item = field }
          if (field ~ /^status:[[:space:]]*/) { sub(/^status:[[:space:]]*/, "", field); status = field }
          if (field ~ /^pr:[[:space:]]*/)     { sub(/^pr:[[:space:]]*/, "", field);     pr = field }
        }
        if (item == ENVIRON["REQ"] && status == "merged" && pr != "") { print pr; exit 0 }
      }
    ' "$f" 2>/dev/null | head -1 | grep . && return 0
  done
  return 1
}

# classify <brief> -> "STATE<TAB>EVIDENCE" on stdout
classify() {
  local brief="$1" req raw_req pr
  raw_req="$(brief_source_requirement "$brief")"
  req="$(safe_requirement_path "$raw_req" || true)"

  if [ -n "$req" ]; then
    if pr="$(automate_pr_for_requirement "$req")"; then
      printf 'stranded_merged\tautomate run file records %s merged (%s)\n' "$req" "$pr"
      return 0
    fi
    if is_done "$req"; then
      printf 'stranded_closed\tsource requirement %s is stamped %s\n' \
        "$req" "$(requirement_status "$req")"
      return 0
    fi
    printf 'unknown\tsource requirement %s carries no done stamp and no merged run file\n' "$req"
    return 0
  fi

  if [ -n "$raw_req" ]; then
    printf 'unknown\tsource requirement pointer %s did not resolve under %s/\n' "$raw_req" "$REQ_ROOT"
    return 0
  fi
  printf 'unknown\tno source requirement pointer on brief\n'
}

# repair <brief> <state> <evidence> — move to done/ and append an ## Outcome.
# Refuses to clobber an existing destination or to re-stamp a brief that already
# carries an ## Outcome heading. Never repairs `unknown`.
repair() {
  local brief="$1" state="$2" evidence="$3"
  local base dest tmp pr
  base="$(basename "$brief")"
  dest="$JOBS_DONE/$base"

  case "$state" in
    stranded_merged|stranded_closed) ;;
    *) echo "reconcile-jobs: refusing to repair '$base' (state=$state)" >&2; return 1 ;;
  esac
  if [ -e "$dest" ]; then
    echo "reconcile-jobs: refusing to repair '$base' — destination already exists" >&2
    return 1
  fi
  if grep -qE '^## Outcome[[:space:]]*$' "$brief" 2>/dev/null; then
    echo "reconcile-jobs: refusing to repair '$base' — brief already carries an ## Outcome block" >&2
    return 1
  fi
  mkdir -p "$JOBS_DONE" 2>/dev/null || { echo "reconcile-jobs: cannot create $JOBS_DONE" >&2; return 1; }

  pr="$(printf '%s' "$evidence" | sed -n 's/.*(\(http[^)]*\)).*/\1/p')"
  [ -n "$pr" ] || pr="not determinable offline"

  # Mirror the completion tail's own two-value vocabulary rather than flattening
  # an escalated close-out into a clean one. Only the stranded_closed arm can
  # know this: its evidence IS a requirement stamp. A stranded_merged brief was
  # classified from a merged PR, which proves the work shipped and says nothing
  # about the heal decision — so it keeps `completed`, and the caveat line below
  # is what records that the heal outcome was not recoverable.
  local status_line="completed" esc_note="" req_for_status req_status
  if [ "$state" = "stranded_closed" ]; then
    req_for_status="$(safe_requirement_path "$(brief_source_requirement "$brief")" || true)"
    if [ -n "$req_for_status" ]; then
      req_status="$(requirement_status "$req_for_status")"
      if [ "$req_status" = "done_with_escalation" ]; then
        status_line="completed_with_escalation"
        esc_note="- **Heal:** escalated — the source requirement closed out as \`done_with_escalation\`; the specific heal reason and remaining-issue count are NOT recoverable here.\n"
      fi
    fi
  fi

  tmp="$(mktemp "${brief}.XXXXXX")" || { echo "reconcile-jobs: mktemp failed" >&2; return 1; }
  cat "$brief" > "$tmp" || { rm -f "$tmp"; return 1; }
  {
    printf '\n---\n\n## Outcome\n'
    printf -- '- **Status:** %s\n' "$status_line"
    [ -n "$esc_note" ] && printf -- "$esc_note"
    printf -- '- **PR:** %s\n' "$pr"
    printf -- '- **Reconciled:** lifecycle move completed by reconcile-jobs.sh, not by the completion tail\n'
    printf -- '- **Evidence:** %s\n' "$evidence"
    printf -- '- **Caveat:** fields the completion tail would have recorded (files changed, heal decision and iterations, red-team advisory) are NOT recoverable after the fact and are deliberately omitted rather than invented.\n'
  } >> "$tmp" || { rm -f "$tmp"; return 1; }

  mv -f "$tmp" "$brief" || { rm -f "$tmp"; return 1; }
  mv "$brief" "$dest" || return 1
  return 0
}

[ -d "$JOBS_IN" ] || { [ "$PORCELAIN" -eq 1 ] || echo "reconcile-jobs: no $JOBS_IN/ — nothing to reconcile."; exit 0; }

shopt -s nullglob
briefs=("$JOBS_IN"/*.md)
shopt -u nullglob

if [ "${#briefs[@]}" -eq 0 ]; then
  [ "$PORCELAIN" -eq 1 ] || echo "reconcile-jobs: $JOBS_IN/ is empty — nothing to reconcile."
  exit 0
fi

n_repaired=0; n_repairable=0; n_unknown=0
for brief in "${briefs[@]}"; do
  line="$(classify "$brief")"
  state="${line%%	*}"
  evidence="${line#*	}"

  if [ "$REPAIR" -eq 1 ] && [ "$state" != "unknown" ]; then
    if repair "$brief" "$state" "$evidence"; then
      n_repaired=$((n_repaired+1))
      [ "$PORCELAIN" -eq 1 ] && printf 'repaired\t%s\t%s\n' "$brief" "$evidence"
      [ "$PORCELAIN" -eq 1 ] || printf '  repaired  %s\n            %s\n' "$brief" "$evidence"
      continue
    fi
  fi

  case "$state" in
    unknown) n_unknown=$((n_unknown+1)) ;;
    *)       n_repairable=$((n_repairable+1)) ;;
  esac

  if [ "$PORCELAIN" -eq 1 ]; then
    printf '%s\t%s\t%s\n' "$state" "$brief" "$evidence"
  else
    printf '  %-16s %s\n                   %s\n' "$state" "$brief" "$evidence"
  fi
done

if [ "$PORCELAIN" -eq 0 ]; then
  echo
  echo "reconcile-jobs: ${n_repaired} repaired, ${n_repairable} repairable, ${n_unknown} unknown."
  [ "$n_repairable" -gt 0 ] && [ "$REPAIR" -eq 0 ] && \
    echo "  Run with --repair to finish the lifecycle move for the repairable ones."
  [ "$n_unknown" -gt 0 ] && \
    echo "  'unknown' means UNVERIFIED offline, not stale — check those by hand before acting."
fi
exit 0
