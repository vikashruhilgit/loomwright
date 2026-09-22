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
#   the wire. It runs from the SessionStart hook on every resume/clear/compact
#   AND, stranded-only, on every fresh startup, where a network round-trip would
#   be a latency and offline-correctness problem. Every verdict below is derived
#   from files already on disk.
# * A stranded brief carries NO PR URL of its own — the `## Outcome` block that
#   would carry one is precisely what did not get written. So evidence has to
#   come from elsewhere, and for a plain `/supervisor` run started outside the
#   automation engine there may be NONE. That case is reported `unknown`, never
#   guessed at and never repaired.
# * `unknown` means UNVERIFIED, not "fine" and not "stale". It is the honest
#   answer when the disk cannot settle the question.
#
# ENGINE-SUPPLIED EVIDENCE (--evidence)
# -------------------------------------
# The one caller that DOES hold online evidence is the `/automate` engine: its
# `--auto-merge` gate just merged the PR, or its RESUME reconcile just found an
# item parked `awaiting_merge` now merged (skills/automate-loop/SKILL.md §6
# steps 1 and 5, via `automate-helpers.sh brief-repair`). It hands that evidence
# in with a repeatable `--evidence <requirement_path>=<pr_url>` argument, OFF by
# default. This script still makes no forge call — it TRUSTS the caller's claim
# and records it verbatim in the `## Outcome` so a reader can falsify it.
# * The key is compared by EXACT string equality against the brief's extracted
#   pointer token (what `brief_requirement_pointer` returns), never against the
#   resolved path: this arm writes nothing keyed off the pointer, so the
#   existence/containment guards that protect a requirement WRITE do not apply,
#   and the seam keeps working in a checkout where the requirement file is
#   absent (a git worktree). No normalisation: `./x` and `/abs/x` never match.
# * Values are validated LEXICALLY only (key under `.supervisor/requirements/`,
#   not absolute, no `..`; url `^https?://…/pull/<n>$`); a bad value — or a key
#   already supplied (the first `--evidence` for a key wins) — is ignored with
#   one stderr line and the script continues.
# * `--evidence` SCOPES `--repair`: the moment ANY `--evidence` flag is parsed —
#   accepted or rejected — only evidence-matched briefs are repaired; every
#   other brief is classified and reported exactly as before and NOT moved.
#   A rejected list therefore repairs NOTHING rather than falling back to the
#   unscoped sweep. Without `--evidence`, `--repair` is unchanged.
# * AMBIGUITY: a key matched by MORE than one in-progress brief (a stranded
#   earlier attempt plus the one just merged) must not attribute the new PR to
#   the old brief — every brief matching that key is reported `unknown` with an
#   `ambiguous: …` evidence and nothing is moved for that key.
#
# CLASSIFICATION (offline, per brief in .supervisor/jobs/in-progress/)
# --------------------------------------------------------------------
#   stranded_merged  An automate run file records this brief's source requirement
#                    as `status: merged` with a PR URL. Strong evidence: that
#                    status is written only after the engine reconciled the merge
#                    against `gh`/`git`. REPAIRABLE.
#                    OR (--evidence) the automate engine supplied merge evidence
#                    for this brief's pointer token: the engine verified the PR
#                    merged against the forge; this reconciler stayed offline.
#                    REPAIRABLE, and the only repair when --evidence is given.
#                    OR (vcs) the LOCAL remote-tracking base ref carries exactly
#                    one merge commit `Merge pull request #N from <owner>/…/<slug>`
#                    dated on/after the brief, where <slug> is the brief's
#                    filename minus its `YYYY-MM-DD-` date prefix, and #N is not
#                    already claimed by a `done/` brief's `- **PR:** … /pull/N`
#                    line. This is the arm that covers a plain `/supervisor` or
#                    `/autonomous` run — the engine never held evidence for
#                    those, so before it they stranded permanently (measured
#                    2026-09-21: three briefs from PRs #177/#181/#185, merged
#                    2026-09-04..05, still in in-progress/ 16 days later).
#                    Reads git's on-disk refs only — NO fetch, NO forge call —
#                    so it sees a merge exactly when the operator has pulled.
#                    Off outside a git repo, when the base ref is missing, when
#                    the filename carries no date, when the slug matches zero or
#                    more than one merge, or when two in-progress briefs share
#                    the slug (reported `unknown … ambiguous`). Attribution is by
#                    NAME, so the `## Outcome` records the commit SHA, subject
#                    and rule for a reader to falsify. REPAIRABLE. Measured
#                    recall on this repo's own done/ corpus: 23 of the 40 most
#                    recent briefs match their merge subject exactly; the rest
#                    stay `unknown`, never guessed.
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
#   reconcile-jobs.sh --repair-merged repair ONLY `stranded_merged` briefs (a merge
#                                     proven on disk); `stranded_closed` is reported
#                                     and left for --repair. This is the arm the
#                                     SessionStart hook runs mechanically.
#   reconcile-jobs.sh --repair --evidence <requirement_path>=<pr_url> [--evidence …]
#                                     engine-supplied evidence (repeatable, off by
#                                     default); repair ONLY the matching brief(s)
#   reconcile-jobs.sh --print-base-ref
#                                     print `vcs_base_ref`'s resolved remote-tracking
#                                     base ref (origin/HEAD, else origin/main, else
#                                     origin/development) and exit — nothing else in
#                                     this script runs. The sanctioned REUSE seam for
#                                     a sibling that needs the same base-ref
#                                     resolution (worktree-audit.sh's merged column,
#                                     queue-hygiene/01) without re-deriving the
#                                     fallback ladder. Exit 1 and prints nothing when
#                                     no base ref resolves.
#
# Deliberately vendor-neutral (CORE-classified): names no harness-specific
# variable or path, so `scripts/check-vendor-coupling.sh` holds it at allowance 0.

set -uo pipefail

JOBS_IN=".supervisor/jobs/in-progress"
JOBS_DONE=".supervisor/jobs/done"
AUTOMATE_DIR=".supervisor/automate"

# evidence_index_for <pointer_token> — echo the index of the accepted --evidence
# entry whose key equals the token EXACTLY (no normalisation). Return 1 if none.
evidence_index_for() {
  local tok="$1" i=0
  [ -n "$tok" ] || return 1
  while [ "$i" -lt "${#EV_KEYS[@]}" ]; do
    if [ "${EV_KEYS[$i]}" = "$tok" ]; then printf '%s' "$i"; return 0; fi
    i=$((i+1))
  done
  return 1
}

PORCELAIN=0
REPAIR=0
REPAIR_MERGED_ONLY=0
PRINT_BASE_REF=0
# EVIDENCE_MODE flips to 1 the moment ANY --evidence flag is PARSED — before its
# value is validated. Scoping (see the main loop) keys on this, not on whether a
# value was accepted: a supplied-but-rejected evidence list must repair NOTHING,
# never fall back to the unscoped sweep. Accepted entries live in two parallel
# indexed arrays (bash 3.2 has no associative arrays); EV_COUNT is filled once
# the briefs are known (ambiguity gate).
EVIDENCE_MODE=0
EV_KEYS=()
EV_URLS=()
EV_COUNT=()
while [ "$#" -gt 0 ]; do
  arg="$1"
  case "$arg" in
    --porcelain) PORCELAIN=1 ;;
    --repair)    REPAIR=1 ;;
    --repair-merged) REPAIR=1; REPAIR_MERGED_ONLY=1 ;;
    --print-base-ref) PRINT_BASE_REF=1 ;;
    --evidence)
      EVIDENCE_MODE=1
      shift
      val="${1:-}"
      key="${val%%=*}"
      url="${val#*=}"
      reason=""
      case "$val" in
        *=*) ;;
        *) reason="no '=' separator" ;;
      esac
      if [ -z "$reason" ]; then
        # The same three lexical guards brief_requirement_path runs first — spelled
        # again because this key is a comparison key the ENGINE supplies, not a
        # path anything writes to, so the filesystem guards do not apply.
        case "$key" in
          /*)                          reason="key is absolute" ;;
          *..*)                        reason="key contains '..'" ;;
          .supervisor/requirements/?*) ;;
          *)                           reason="key is outside .supervisor/requirements/" ;;
        esac
      fi
      if [ -z "$reason" ]; then
        # Built-in ERE match, not `printf | grep -q` (SIGPIPE-under-pipefail trap).
        [[ "$url" =~ ^https?://[^[:space:]]+/pull/[0-9]+$ ]] || reason="url is not a pull-request URL"
      fi
      if [ -z "$reason" ] && evidence_index_for "$key" >/dev/null; then
        # A repeated key would otherwise append a second entry that
        # evidence_index_for (first match wins) could never reach — silently
        # dropping the later URL. Refuse it out loud instead.
        reason="duplicate key (first --evidence for it wins)"
      fi
      if [ -n "$reason" ]; then
        echo "reconcile-jobs: ignoring --evidence '$val' ($reason)" >&2
      else
        EV_KEYS[${#EV_KEYS[@]}]="$key"
        EV_URLS[${#EV_URLS[@]}]="$url"
      fi
      ;;
    # Print the whole header, including the USAGE block: everything after the
    # shebang up to the `set` line. (The previous fixed line range stopped above
    # USAGE once the header grew.)
    -h|--help)   awk 'NR==1{next} /^set -uo pipefail/{exit} {print}' "$0"; exit 0 ;;
    *) echo "reconcile-jobs: unknown flag '$arg' (see --help)" >&2; exit 0 ;;
  esac
  [ "$#" -gt 0 ] && shift
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

# THE SOURCE-REQUIREMENT POINTER IS PARSED IN EXACTLY ONE PLACE — brief-pointer.sh.
#
# This script used to strip the label and nothing else, so a pointer wrapped in
# backticks (2 of the 3 real briefs measured 2026-09-10) failed the very first
# containment guard and the brief was classified `unknown`; the sibling
# reconciler carried a second, differently-wrong parse of the same field. Both
# are gone: `brief_requirement_pointer` reads the field, `brief_requirement_path`
# gates it, and this script GAINED the two symlink guards it previously lacked
# rather than the shared rule losing them.
#
# The helper is found by a PLAIN SIBLING lookup — no harness-specific plugin-root
# variable, because this file is held at allowance 0 by
# scripts/check-vendor-coupling.sh (see the vendor-neutrality note at the end of
# the header above) and that gate carries no `|| true`.
#
# ABSENT HELPER = SILENT SKIP, DELIBERATELY. There is no fail-CLOSED load guard
# here. Without the helper this script performs no reclassification and no move,
# i.e. no write at all, so skipping already IS the safe outcome — and this script
# runs on EVERY SessionStart, where an error exit would wedge every new session.
# See brief-pointer.sh's header, divergence 2.
_bp_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo .)"
# shellcheck source=brief-pointer.sh
[ -r "$_bp_dir/brief-pointer.sh" ] && . "$_bp_dir/brief-pointer.sh"
if ! command -v brief_requirement_path >/dev/null 2>&1; then
  brief_requirement_pointer() { return 1; }
  brief_requirement_path() { return 1; }
fi

# The containment root a relative pointer is interpreted against. This script
# never `cd`s, so that is simply its cwd — resolved ONCE, physically, and handed
# to brief_requirement_path explicitly. Deliberately NOT derived from the VCS
# CLI: that would put a subprocess on the SessionStart resume path, which the
# offline-by-construction contract above forbids.
ROOT_P="$(pwd -P 2>/dev/null || pwd)"

# Reporting-only mirror of the helper's containment root, for the evidence
# string below. Derived rather than re-spelled so the prefix has ONE literal
# home (brief-pointer.sh). It is empty EXACTLY AND ONLY when the helper failed
# to load, which makes it the discriminator classify() uses to report that
# degraded state honestly — see the guard on its final arm. Without that guard
# the stub reader returns nothing for every brief and classify() lands on the
# "no source requirement pointer" arm, telling the operator that briefs which
# demonstrably carry a pointer have none. A record misstating reality is the
# exact failure this reconciler exists to correct; it must not emit one itself.
REQ_ROOT="${BRIEF_REQUIREMENT_PREFIX:-}"
REQ_ROOT="${REQ_ROOT%/}"

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


# vcs_merge_for_brief <brief> — echo "<sha>\t<pr_number>\t<subject>" for the ONE
# merge commit on the local base ref that names this brief's slug, or return 1
# (no evidence). Return 2 with "<count>" on stdout when the evidence is
# ambiguous (several merges, or several in-progress briefs share the slug) —
# the caller reports that as `unknown`, never as a repair.
#
# Every failure mode is a silent `return 1`: not a git repo, no remote-tracking
# base ref, filename without a date prefix, a slug with characters outside
# [a-z0-9-] (it is interpolated into an ERE — refuse rather than escape), git
# absent. Nothing here fetches; the ref is whatever the last pull left on disk.
# vcs_base_ref — resolve the remote-tracking base ref ONCE into the global
# VCS_BASE_REF and return 0; return 1 when there is none. Callers invoke it
# directly and read the global — NOT `$(vcs_base_ref)`: a command substitution
# runs in a subshell, so an assignment made there never reaches the caller and
# the probes re-run for every brief (PR #243 review, finding 5).
#
# RECALL LIMIT, stated: the ref is origin/HEAD when the clone recorded it, else
# origin/main, else origin/development. A repo whose PRs merge into a branch
# other than the remote's default (e.g. default `main`, PRs into
# `development`) is not seen by this arm — those briefs stay `unknown`.
# Squash merges are seen only if the squash subject keeps the
# `Merge pull request #N from …` shape (GitHub's default squash subject does
# NOT), which is the same limit.
VCS_BASE_REF=""
VCS_BASE_REF_PROBED=0
vcs_base_ref() {
  if [ "$VCS_BASE_REF_PROBED" -eq 1 ]; then [ -n "$VCS_BASE_REF" ]; return; fi
  VCS_BASE_REF_PROBED=1
  command -v git >/dev/null 2>&1 || return 1
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  local ref
  # origin/HEAD names the remote's default branch when the clone recorded it;
  # otherwise fall back through the two bases this plugin's projects use.
  # NOTE: on an unset origin/HEAD, `rev-parse --abbrev-ref` exits 128 AND
  # echoes the literal `origin/HEAD` to stdout — so the name it returns is
  # verified before it is trusted, or the fallback below would never run.
  ref="$(git rev-parse --abbrev-ref origin/HEAD 2>/dev/null || true)"
  case "$ref" in
    origin/HEAD|"") ref="" ;;
    origin/?*) git rev-parse -q --verify "$ref" >/dev/null 2>&1 || ref="" ;;
    *) ref="" ;;
  esac
  if [ -z "$ref" ]; then
    for ref in origin/main origin/development; do
      git rev-parse -q --verify "$ref" >/dev/null 2>&1 && break
      ref=""
    done
  fi
  [ -n "$ref" ] || return 1
  git rev-parse -q --verify "$ref" >/dev/null 2>&1 || return 1
  VCS_BASE_REF="$ref"
  return 0
}

# --print-base-ref is a standalone REUSE seam: resolve and print vcs_base_ref's
# result, then exit — nothing else below (the in-progress/ scan, --repair, the
# report loop) runs. Placed here, right after vcs_base_ref is defined, so no
# other function this flag doesn't need has to load first.
if [ "$PRINT_BASE_REF" -eq 1 ]; then
  if vcs_base_ref; then printf '%s\n' "$VCS_BASE_REF"; exit 0; fi
  exit 1
fi

vcs_merge_for_brief() {
  local brief="$1" base slug since ref re line sha subj n=0 hit="" others=0 f
  base="$(basename "$brief" .md)"
  case "$base" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-?*) since="${base:0:10}"; slug="${base:11}" ;;
    *) return 1 ;;
  esac
  case "$slug" in *[!a-z0-9-]*) return 1 ;; esac
  vcs_base_ref || return 1
  ref="$VCS_BASE_REF"

  # Two in-progress briefs with the same slug cannot both own one merge.
  for f in "$JOBS_IN"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-"$slug".md; do
    [ -f "$f" ] && others=$((others+1))
  done
  if [ "$others" -gt 1 ]; then printf '%s' "$others"; return 2; fi

  re="^Merge pull request #([0-9]+) from [^/[:space:]]+/([^[:space:]]+/)?${slug}\$"
  # Read the whole log first, then match: no `git | grep -q` (SIGPIPE under
  # pipefail). --since is the committer-date floor: a merge older than the brief
  # cannot be this brief's.
  while IFS=$'\t' read -r sha subj; do
    [ -n "${sha:-}" ] || continue
    [[ "$subj" =~ $re ]] || continue
    # A PR number a done/ brief already records as its own is not ours.
    if grep -rqsE -- "^- \*\*PR:\*\* .*/pull/${BASH_REMATCH[1]}([^0-9]|\$)" "$JOBS_DONE" 2>/dev/null; then
      continue
    fi
    n=$((n+1)); hit="${sha}"$'\t'"${BASH_REMATCH[1]}"$'\t'"${subj}"
  done <<EOF
$(git log --merges --first-parent --since="$since" --format='%H%x09%s' "$ref" 2>/dev/null)
EOF
  if [ "$n" -gt 1 ]; then printf '%s' "$n"; return 2; fi
  [ "$n" -eq 1 ] || return 1
  printf '%s' "$hit"
  return 0
}

# vcs_pr_url <pr_number> — https URL for the PR when origin is a GitHub-shaped
# remote (ssh or https); empty otherwise. Best-effort: repair() falls back to
# "not determinable offline" for the `- **PR:**` line when this is empty, and the
# evidence text still carries `#N` and the commit SHA either way.
vcs_pr_url() {
  local n="$1" url
  url="$(git remote get-url origin 2>/dev/null || true)"
  case "$url" in
    git@github.com:*) url="https://github.com/${url#git@github.com:}" ;;
    ssh://git@github.com/*) url="https://github.com/${url#ssh://git@github.com/}" ;;
    https://github.com/*) ;;
    *) return 0 ;;
  esac
  url="${url%.git}"; url="${url%/}"
  printf '%s/pull/%s' "$url" "$n"
}

# vcs_evidence_line <brief> — echo "stranded_merged<TAB>evidence" or
# "unknown<TAB>ambiguous…" on stdout; return 1 when the arm has nothing to say.
vcs_evidence_line() {
  local brief="$1" out rc sha n subj url ref
  out="$(vcs_merge_for_brief "$brief")"; rc=$?
  case "$rc" in
    2) printf 'unknown\tambiguous: %s candidates share this brief'"'"'s branch slug on the base ref or in in-progress/ — not repaired\n' "$out"; return 0 ;;
    0) ;;
    *) return 1 ;;
  esac
  IFS=$'\t' read -r sha n subj <<< "$out"
  vcs_base_ref || return 1
  ref="$VCS_BASE_REF"
  url="$(vcs_pr_url "$n")"
  # One parenthesised URL and only one, LAST — repair() extracts `- **PR:**`
  # from the last `(http…)` group. Keep the SHA and subject in plain brackets.
  printf 'stranded_merged\tvcs merge commit %s on %s — subject [%s] — attributed by branch-slug match, committed on/after the brief date; git refs on disk only, no fetch, no forge call' \
    "${sha:0:7}" "$ref" "$subj"
  if [ -n "$url" ]; then printf ' (%s)\n' "$url"; else printf ' — PR #%s\n' "$n"; fi
  return 0
}


# classify <brief> -> "STATE<TAB>EVIDENCE" on stdout
#
# The engine-evidence arm comes FIRST and is discriminated by its evidence
# PREFIX (`automate engine supplied`), tested with a `case` in the main loop —
# rather than a third TAB field — because the porcelain row format
# STATE<TAB>BRIEF<TAB>EVIDENCE is parsed by session-resume.sh with a fixed
# three-variable `read`, and a hidden column that has to be stripped before
# printing is one more place for the two to drift apart. The prefix is already
# what the `## Outcome` records, so the discriminator and the evidence are the
# same string.
classify() {
  local brief="$1" req raw_req pr ei
  raw_req="$(brief_requirement_pointer "$brief" || true)"

  if ei="$(evidence_index_for "$raw_req")"; then
    if [ "${EV_COUNT[$ei]:-0}" -gt 1 ]; then
      printf 'unknown\tambiguous: %s in-progress briefs point at %s — not repaired\n' \
        "${EV_COUNT[$ei]}" "$raw_req"
      return 0
    fi
    # One parenthesised URL and only one: repair() extracts `- **PR:**` from
    # the LAST `(http…)` group of this string (the sed is greedy) — so keep it the only one.
    printf 'stranded_merged\tautomate engine supplied merge evidence for %s (%s) — the engine verified the PR merged against the forge; this reconciler stayed offline\n' \
      "$raw_req" "${EV_URLS[$ei]}"
    return 0
  fi

  req="$(brief_requirement_path "$raw_req" "$ROOT_P" || true)"

  if [ -n "$req" ]; then
    if pr="$(automate_pr_for_requirement "$req")"; then
      printf 'stranded_merged\tautomate run file records %s merged (%s)\n' "$req" "$pr"
      return 0
    fi
    # The vcs arm sits BETWEEN the engine's run file (which names the PR from
    # the forge) and the done stamp (which cannot name a PR at all): it is the
    # strongest offline evidence that still yields a PR number. ONLY a
    # confirmed match short-circuits. An AMBIGUOUS vcs answer yields no PR
    # number, so it must not outrank a definitive done stamp — PR #243 review:
    # a done-stamped requirement whose slug collides with two merges was
    # reported `unknown` instead of `stranded_closed`. The ambiguous line is
    # held and emitted only when the stamp cannot settle it either.
    local vcs_line=""
    if vcs_line="$(vcs_evidence_line "$brief")"; then
      case "$vcs_line" in stranded_merged*) printf '%s\n' "$vcs_line"; return 0 ;; esac
    else
      vcs_line=""
    fi
    if is_done "$req"; then
      printf 'stranded_closed\tsource requirement %s is stamped %s\n' \
        "$req" "$(requirement_status "$req")"
      return 0
    fi
    if [ -n "$vcs_line" ]; then printf '%s\n' "$vcs_line"; return 0; fi
    printf 'unknown\tsource requirement %s carries no done stamp and no merged run file\n' "$req"
    return 0
  fi

  # No resolvable requirement pointer: the vcs arm needs none — it keys on the
  # brief's own filename — so it still gets to answer before the pointer arms
  # explain why they could not.
  if vcs_evidence_line "$brief"; then return 0; fi
  if [ -n "$raw_req" ]; then
    printf 'unknown\tsource requirement pointer %s did not resolve under %s/\n' "$raw_req" "$REQ_ROOT"
    return 0
  fi
  # REQ_ROOT is empty exactly and only when brief-pointer.sh failed to load, in
  # which case the stub reader returned nothing for reasons that have nothing to
  # do with this brief. Say so, rather than reporting every brief as pointerless.
  if [ -z "$REQ_ROOT" ]; then
    printf 'unknown\tbrief-pointer extractor unavailable — pointer not read\n'
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
  # Consult the requirement for BOTH repairable states, NOT just stranded_closed.
  # classify() checks the automate run file BEFORE is_done(), so a brief can be
  # stranded_merged while its source requirement is ALSO already stamped
  # done_with_escalation — step 2.5 can stamp without step 2 having moved the
  # brief (skills/self-heal-advisory/SKILL.md step 3 says so explicitly: "in
  # done/ when step 2 performed the move; otherwise wherever it remains").
  # Gating this on `state` therefore re-created the exact failure it was added to
  # remove: asserting a cleaner result than a file we can already read supports.
  # Only the MESSAGE differs between the arms.
  local status_line="completed" esc_note="" req_for_status req_status
  req_for_status="$(brief_requirement_path "$(brief_requirement_pointer "$brief" || true)" "$ROOT_P" || true)"
  if [ -n "$req_for_status" ]; then
    req_status="$(requirement_status "$req_for_status")"
    if [ "$req_status" = "done_with_escalation" ]; then
      status_line="completed_with_escalation"
      if [ "$state" = "stranded_merged" ]; then
        esc_note="- **Heal:** escalated — the PR-merge evidence is heal-decision-agnostic, but the source requirement closed out as \`done_with_escalation\`. The specific heal reason and remaining-issue count are NOT recoverable here.\n"
      else
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

  # Move the STAGED copy into done/ first, and only then drop the original. The
  # previous order rewrote the brief in place and then moved it, so a failure of
  # the second step left the source carrying an ## Outcome block — which the
  # "already carries an ## Outcome" guard above then refuses on every later run,
  # wedging the brief permanently. With this order the worst case is a duplicate
  # (dest written, source not removed), which the destination-exists guard
  # reports rather than compounds.
  mv "$tmp" "$dest" || { rm -f "$tmp"; return 1; }
  rm -f "$brief" || {
    echo "reconcile-jobs: repaired '$base' into done/ but could not remove the original" >&2
    return 1
  }
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

# Ambiguity gate: count, per accepted key, how many in-progress briefs carry
# exactly that pointer token. classify() reports every brief of a key counted
# >1 as `unknown` (ambiguous) so a new PR is never attributed to a stranded
# earlier attempt at the same requirement.
i=0
while [ "$i" -lt "${#EV_KEYS[@]}" ]; do
  EV_COUNT[$i]=0
  i=$((i+1))
done
if [ "${#EV_KEYS[@]}" -gt 0 ]; then
  for brief in "${briefs[@]}"; do
    tok="$(brief_requirement_pointer "$brief" || true)"
    if ei="$(evidence_index_for "$tok")"; then
      EV_COUNT[$ei]=$(( ${EV_COUNT[$ei]} + 1 ))
    fi
  done
fi

n_repaired=0; n_repairable=0; n_unknown=0
for brief in "${briefs[@]}"; do
  line="$(classify "$brief")"
  state="${line%%	*}"
  evidence="${line#*	}"

  # --repair is SCOPED whenever EVIDENCE_MODE=1: only a verdict sourced from an
  # engine evidence match (discriminated by its prefix, see classify()) is
  # repaired; everything else is reported exactly as before and left in place.
  repair_ok=0
  if [ "$REPAIR" -eq 1 ] && [ "$state" != "unknown" ]; then
    if [ "$REPAIR_MERGED_ONLY" -eq 1 ] && [ "$state" != "stranded_merged" ]; then
      : # --repair-merged: a done stamp alone is reported, never moved here
    elif [ "$EVIDENCE_MODE" -eq 1 ]; then
      case "$evidence" in
        "automate engine supplied "*) repair_ok=1 ;;
      esac
    else
      repair_ok=1
    fi
  fi

  if [ "$repair_ok" -eq 1 ]; then
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
  [ "$n_repairable" -gt 0 ] && [ "$REPAIR_MERGED_ONLY" -eq 1 ] && \
    echo "  --repair-merged left the stranded_closed ones in place; run --repair to move those too."
  [ "$n_unknown" -gt 0 ] && \
    echo "  'unknown' means UNVERIFIED offline, not stale — check those by hand before acting."
fi
exit 0
