#!/usr/bin/env bash
# wait-for-checks.sh — foreground, BLOCKING, bounded wait for a PR's scoped CI
# checks to settle for a SPECIFIC sha. Mechanizes skills/review-heal/SKILL.md
# §U2 (required-check discovery, fail-closed) + §U2.5 (scoped wait, bounded) —
# read those sections before changing this script; do not re-derive the loop
# logic, this script exists so the prose can point at it instead of restating
# it as `sleep(poll_interval)` pseudocode.
#
# WHY THIS EXISTS (red-team-hardening item 04)
# ---------------------------------------------------------------------------
# Before this script, the wait was pseudocode the MODEL executed directly.
# Under `claude -p` (a headless, non-interactive session) the model's habit
# was to start a background poll and end its turn — but under `-p`, turn-end
# IS process exit. The drain process died mid-wait, and the dispatcher's
# cleanup trap salvaged + removed the worktree/lock as if the run had
# completed normally, leaving no record that no result was ever produced.
# Foreground, blocking script calls the model cannot background (and
# cannot "wait for a notification" on, because there is no other turn left to
# receive one) close that hole. See the call sites in
# skills/review-heal/SKILL.md and agents/review-pr.md, each marked with:
#   "Never run this wait in the background and never end the turn while
#    waiting — under `claude -p` ending the turn ends the process and the
#    drain dies with no result."
#
# USAGE
#   wait-for-checks.sh <pr_url> --sha <sha> --bound <seconds> \
#       [--interval <s>] [--required-only | --review-check-pattern <glob>] \
#       [--names] [--call-max <s> [--continue | --restart]]
#
#   <pr_url>       the PR being waited on (any bare positional argument).
#   --sha <sha>    the commit the caller is waiting for. A rollup reported
#                  for a DIFFERENT sha is NEVER treated as settled — this was
#                  implicit in the prior pseudocode (see §"Termination-only
#                  severity floor"'s `headRefOid` guard) and is now explicit
#                  and load-bearing for BOTH call-site shapes (§U2.5's scoped
#                  wait and the confirming required-check pass).
#   --bound <s>    hard wall-clock ceiling on the wait, in seconds.
#   --interval <s> poll interval, in seconds (default 15, matching
#                  review-heal/SKILL.md's documented poll_interval).
#   --required-only
#                  scope = required checks ONLY (used by the confirming
#                  required-check pass — it never waits on review-producing
#                  checks, per §"Termination-only severity floor").
#   --review-check-pattern <glob>[,<glob>...]
#                  scope = required checks (always) UNION checks whose name
#                  matches any of these comma-separated globs (used by
#                  §U2.5's scoped wait). Default when NEITHER flag is passed:
#                  `*review*,claude*` (skills/review-heal/SKILL.md's own
#                  documented default).
#   --names        OPT-IN (automate-followups/31). Appends two trailing fields
#                  to the ONE output line, covering the SAME scoped set
#                  (required ∪ review-producing, or required only):
#                    pending_names=<comma-list|none>  every scoped check not
#                      yet completed — required checks INCLUDED (today's
#                      `pending=` lists review-pattern checks only), and a
#                      required context absent from the rollup counts as
#                      pending; `sha_mismatch` when the rollup's sha differs.
#                    red_names=<name@run_id,...|none>  every scoped check
#                      completed non-success/non-neutral/non-skipped; run_id
#                      parsed from `detailsUrl` with the `/actions/runs/(N)/`
#                      regex skills/review-heal/SKILL.md §U4 uses, `-` absent.
#                  WITHOUT the flag the output line is byte-unchanged. Consumer:
#                  `automate-helpers.sh escalation-cause`.
#   --call-max <s> OPT-IN RESUMABLE MODE (implementation-quality/02 T03). A
#                  per-CALL ceiling (positive integer, clamped to 570) so no
#                  single foreground call outlives the host's 600 s foreground
#                  cap, while --bound stays the TOTAL budget across calls. The
#                  total is a persisted absolute deadline (epoch seconds,
#                  `date +%s`) in ${CHECK_WAIT_DIR:-.supervisor/check-wait}/
#                  <key-hash>.json, key = (pr_url, --sha, scope), hashed like
#                  drain-rounds.sh's pr_hash. A call WITHOUT --continue starts a
#                  fresh deadline (now + --bound) — UNLESS an unexpired deadline
#                  for the same key is already persisted: then it KEEPS that
#                  deadline and warns on stderr (a caller that drops --continue
#                  mid-loop must never earn a fresh total; fail-CLOSED toward
#                  the bound). --restart deliberately replaces an unexpired
#                  deadline; an expired or unreadable one is always replaced. A
#                  call WITH --continue reads the deadline and NEVER rewrites it
#                  (--restart is ignored there) — missing/garbage state there is
#                  fail-CLOSED: `ELAPSED … pending=unreadable_deadline`, never a
#                  fresh budget. A different --sha is a different key. The state
#                  file is removed on SETTLED/ELAPSED. A non-numeric --call-max
#                  or --bound in this mode ⇒ `pending=bad_usage`.
#                  WITHOUT --call-max: output byte-unchanged, no state written,
#                  CONTINUE never printed.
#
# CONTRACT
#   - Foreground and BLOCKING. This script NEVER backgrounds itself — that is
#     the entire point (see "WHY THIS EXISTS" above).
#   - Bash 3.2 / BSD-safe: NO `timeout` binary dependency (per this repo's
#     documented macOS/BSD portability convention — `timeout` may be absent).
#     The bound is tracked via the bash builtin `$SECONDS` (reset to 0 at
#     script start), never a `date`-diff or a subprocess timer. Exception:
#     under --call-max the per-call ceiling uses `$SECONDS` and the TOTAL
#     bound is the persisted `date +%s` deadline (it must survive calls).
#   - ALWAYS exits 0 — mirrors dispatch-pr-review.sh / send-webhook.sh's
#     fire-and-forget convention. A malformed invocation or an unreadable `gh`
#     read degrades to an ELAPSED-shaped line, never a non-zero exit the
#     caller would have to special-case.
#   - Prints EXACTLY ONE final line to stdout:
#       SETTLED sha=<sha> required=<green|red|unknown> review_producing=<settled|elapsed>
#       ELAPSED sha=<sha> required=<green|red|pending|unknown> review_producing=<settled|elapsed> pending=<comma-list|none>
#       CONTINUE sha=<sha> remaining=<s> pending=<comma-list|none>   (--call-max only)
#     CONTINUE is NOT a result: the per-call ceiling was reached with total
#     budget left — the caller calls again at once, same --sha, with
#     --continue, as a new foreground call, and never ends its turn on it.
#     The caller (the model, per the skill prose) is responsible for turning
#     this line into a READY/ESCALATED decision — this script only reports
#     scoped-settlement fact, it never decides drain readiness itself.
#     `required=unknown` means the branch-protection read that would name the
#     required contexts FAILED for a reason other than a verified "genuinely
#     unprotected" 404 (403/5xx/network/garbage) — per skills/review-heal/
#     SKILL.md §U2's fail-CLOSED rule, the caller MUST treat `unknown`
#     exactly like an unresolved/in-flight check, never like `green`.
#
# GH STUB SEAM (tests)
#   The `gh` binary is invoked via "${GH:-gh}" throughout — a test exports
#   GH=/path/to/stub-gh to script a deterministic sequence of rollup
#   responses across polls without any network call. See
#   test-wait-for-checks.sh.

set -u
# Intentionally NO `set -e` / pipefail — every gh/jq read is individually
# guarded so a single unreadable poll degrades gracefully instead of
# aborting the whole bounded wait.

log() { printf 'wait-for-checks: %s\n' "$1" >&2; }

GH_BIN="${GH:-gh}"
JQ_BIN="${JQ:-jq}"

# ---- Parse args --------------------------------------------------------------
PR_URL=""
SHA=""
BOUND=""
INTERVAL="15"
REQUIRED_ONLY=0
REVIEW_PATTERN=""
HAVE_PATTERN=0
NAMES=0
CALL_MAX=""
CONTINUE=0
RESTART=0

while [ $# -gt 0 ]; do
  case "$1" in
    --sha)
      SHA="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --sha=*)
      SHA="${1#--sha=}"; shift ;;
    --bound)
      BOUND="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --bound=*)
      BOUND="${1#--bound=}"; shift ;;
    --interval)
      INTERVAL="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --interval=*)
      INTERVAL="${1#--interval=}"; shift ;;
    --required-only)
      REQUIRED_ONLY=1; shift ;;
    --names)
      NAMES=1; shift ;;
    --call-max)
      CALL_MAX="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --call-max=*)
      CALL_MAX="${1#--call-max=}"; shift ;;
    --continue)
      CONTINUE=1; shift ;;
    --restart)
      RESTART=1; shift ;;
    --review-check-pattern)
      REVIEW_PATTERN="${2:-}"; HAVE_PATTERN=1; shift; [ $# -gt 0 ] && shift ;;
    --review-check-pattern=*)
      REVIEW_PATTERN="${1#--review-check-pattern=}"; HAVE_PATTERN=1; shift ;;
    --*)
      # Unknown flag — ignore (forward compat, mirrors dispatch-pr-review.sh).
      shift ;;
    *)
      [ -z "$PR_URL" ] && PR_URL="$1"
      shift ;;
  esac
done

# Default scope (§U2.5): required ∪ *review*/claude* when neither
# --required-only nor --review-check-pattern was passed.
if [ "$REQUIRED_ONLY" -eq 0 ] && [ "$HAVE_PATTERN" -eq 0 ]; then
  REVIEW_PATTERN='*review*,claude*'
  HAVE_PATTERN=1
fi

if [ -z "$PR_URL" ] || [ -z "$SHA" ] || [ -z "$BOUND" ]; then
  log "usage: wait-for-checks.sh <pr_url> --sha <sha> --bound <seconds> [--interval <s>] [--required-only | --review-check-pattern <glob>]"
  printf 'ELAPSED sha=%s required=pending review_producing=elapsed pending=bad_usage\n' "${SHA:-unknown}"
  exit 0
fi

if ! command -v "$JQ_BIN" >/dev/null 2>&1; then
  log "jq not found — cannot parse gh output"
  printf 'ELAPSED sha=%s required=pending review_producing=elapsed pending=no_jq\n' "$SHA"
  exit 0
fi

# ---- Resumable mode (--call-max): validate, then resolve the TOTAL deadline.
# Everything here is skipped without --call-max (byte-unchanged default path).
DEADLINE=""
STATE_FILE=""
if [ -n "$CALL_MAX" ]; then
  case "$CALL_MAX" in ''|*[!0-9]*) CALL_MAX="bad" ;; esac
  case "$BOUND" in ''|*[!0-9]*) CALL_MAX="bad" ;; esac
  if [ "$CALL_MAX" = "bad" ] || [ "$CALL_MAX" -lt 1 ] 2>/dev/null; then
    log "--call-max and --bound must be non-negative integers (call-max >= 1)"
    printf 'ELAPSED sha=%s required=pending review_producing=elapsed pending=bad_usage\n' "$SHA"
    exit 0
  fi
  [ "$CALL_MAX" -gt 570 ] && CALL_MAX=570   # stay under the host's 600 s foreground cap
  _scope="required"
  [ "$REQUIRED_ONLY" -eq 0 ] && _scope="review:$REVIEW_PATTERN"
  _key="$PR_URL|$SHA|$_scope"
  _h=""
  if command -v shasum >/dev/null 2>&1; then
    _h="$(printf '%s' "$_key" | shasum 2>/dev/null | cut -d' ' -f1 || true)"
  elif command -v sha1sum >/dev/null 2>&1; then
    _h="$(printf '%s' "$_key" | sha1sum 2>/dev/null | cut -d' ' -f1 || true)"
  elif command -v cksum >/dev/null 2>&1; then
    _h="$(printf '%s' "$_key" | cksum 2>/dev/null | cut -d' ' -f1 || true)"
  fi
  [ -n "$_h" ] || _h="$(printf '%s' "$_key" | tr -c 'A-Za-z0-9' '-')"
  _dir="${CHECK_WAIT_DIR:-.supervisor/check-wait}"
  STATE_FILE="$_dir/$_h.json"
  _now="$(date +%s)"
  if [ "$CONTINUE" -eq 1 ]; then
    # Continuation: read the persisted deadline, NEVER rewrite it. Missing or
    # garbage state is fail-CLOSED — never a fresh (unbounded) budget.
    DEADLINE="$("$JQ_BIN" -r '.deadline | select(type == "number" and . == floor) | tostring' "$STATE_FILE" 2>/dev/null || true)"
    case "$DEADLINE" in
      ''|*[!0-9]*)
        log "no readable deadline for this (pr, sha, scope) — refusing a fresh budget"
        printf 'ELAPSED sha=%s required=pending review_producing=elapsed pending=unreadable_deadline\n' "$SHA"
        exit 0 ;;
    esac
  else
    # A first call. An UNEXPIRED deadline already persisted for this key means
    # a resumable wait is in flight (most likely the caller dropped --continue):
    # keep it — a fresh total would make the wait unbounded. Only --restart
    # replaces it; an expired or unreadable one is replaced as before.
    _kept=""
    if [ "$RESTART" -eq 0 ]; then
      _kept="$("$JQ_BIN" -r '.deadline | select(type == "number" and . == floor) | tostring' "$STATE_FILE" 2>/dev/null || true)"
      case "$_kept" in ''|*[!0-9]*) _kept="" ;; esac
      [ -n "$_kept" ] && [ "$_kept" -le "$_now" ] && _kept=""
    fi
    if [ -n "$_kept" ]; then
      DEADLINE="$_kept"
      log "an unexpired deadline for this (pr, sha, scope) is in flight — keeping it ($((DEADLINE - _now)) s left); pass --continue to resume, --restart to replace it"
    else
      DEADLINE=$((_now + BOUND))
      mkdir -p "$_dir" 2>/dev/null || true
      # jq -n --arg, never printf: --sha and the review pattern are free text, and a quote or
      # backslash in either made the file unreadable — every --continue then failed closed and the
      # TOTAL budget shrank to a single call.
      "$JQ_BIN" -nc --argjson d "$DEADLINE" --arg sha "$SHA" --arg scope "$_scope" \
          '{deadline: $d, sha: $sha, scope: $scope}' > "$STATE_FILE" 2>/dev/null \
        || log "could not persist the deadline to $STATE_FILE (a --continue call will fail closed)"
    fi
  fi
fi

# ---- owner/repo from the PR URL ----------------------------------------------
OWNER=""
REPO=""
case "$PR_URL" in
  *github.com/*/*/pull/*)
    _rest="${PR_URL#*github.com/}"
    _ownerrepo="${_rest%%/pull/*}"
    OWNER="${_ownerrepo%%/*}"
    REPO="${_ownerrepo#*/}"
    ;;
esac

# review_pattern_match <name> <comma-separated-globs> — bash-native glob
# matching (no jq/regex glob-translation reinvented). Returns 0 on any match.
#
# `set -f` (noglob) is LOAD-BEARING around the `set --` word-split below: an
# unquoted `set -- $patterns` is ALSO subject to pathname expansion, so a
# pattern like `*review*` would silently glob-expand against whatever the
# CURRENT WORKING DIRECTORY happens to contain (e.g. run from
# loomwright/scripts/ itself, `*review*` matches real files like
# `dispatch-pr-review.sh`) INSTEAD of staying the literal glob string this
# function means to match check NAMES against. Without `set -f` this breaks
# silently and non-deterministically depending on the caller's cwd — caught
# by a full-suite run where the caller `cd`'d into loomwright/scripts/ first.
review_pattern_match() {
  local name="$1" patterns="$2" p oldIFS
  [ -n "$patterns" ] || return 1
  oldIFS="$IFS"
  IFS=','
  set -f
  set -- $patterns
  set +f
  IFS="$oldIFS"
  for p in "$@"; do
    case "$name" in
      $p) return 0 ;;
    esac
  done
  return 1
}

# ---- Required-check discovery (§U2, fail-CLOSED — PR #251 review finding 2)
# A protection read that fails MUST be distinguished from a branch that is
# genuinely unprotected: only a real 404 ("Branch not protected") is a
# VERIFIED empty required set. Any other failure (403/5xx/network/garbage —
# a realistic case for a PR-review bot token lacking admin-level branch-read
# access) sets protection_unknown=1, which forces the `required=` field to
# `unknown` in this script's own output below — never a vacuous `green` — so
# the caller can apply §U2's existing fail-CLOSED rule ("required-check
# metadata unavailable ⇒ MUST NOT claim READY ⇒ ESCALATED") off THIS script's
# line alone, without depending on a later re-scan to catch the gap.
required_contexts_json="[]"
protection_unknown=0
if [ -n "$OWNER" ] && [ -n "$REPO" ]; then
  _base="$("$GH_BIN" pr view "$PR_URL" --json baseRefName 2>/dev/null || true)"
  BASE_REF="$(printf '%s' "$_base" | "$JQ_BIN" -r '.baseRefName // empty' 2>/dev/null || true)"
  [ -n "$BASE_REF" ] || BASE_REF="main"
  # Single call, stdout+stderr merged: on success stdout is the JSON body; on
  # failure gh writes its error (including "HTTP 404"/"Branch not protected"
  # for a genuinely unprotected branch) to stderr and stdout is empty, so the
  # merged capture carries whichever one actually happened.
  _prot="$("$GH_BIN" api "repos/$OWNER/$REPO/branches/$BASE_REF/protection" 2>&1)"
  _prot_rc=$?
  if [ "$_prot_rc" -eq 0 ] && printf '%s' "$_prot" | "$JQ_BIN" -e . >/dev/null 2>&1; then
    required_contexts_json="$(printf '%s' "$_prot" | "$JQ_BIN" -c '
      ((.required_status_checks.contexts // []) + ((.required_status_checks.checks // []) | map(.context))) | unique
    ' 2>/dev/null || echo '[]')"
    [ -n "$required_contexts_json" ] || required_contexts_json="[]"
  else
    case "$_prot" in
      *"Branch not protected"*|*"HTTP 404"*)
        required_contexts_json="[]" ;;  # verified: genuinely no protection
      *)
        protection_unknown=1
        required_contexts_json="[]" ;;  # unreadable — NOT verified empty
    esac
  fi
fi

# compute_names — (--names only) fill names_pending / names_red over the
# scoped set: required contexts (by exact name) ∪ review-pattern matches
# (unless --required-only). A required context ABSENT from the rollup is
# pending (not yet materialized for this sha — never read as green).
names_pending=""
names_red=""
compute_names() {
  local _n _st _sta _con _url _req _up_st _up_sta _up_con _rid _in _nrows _missing _g
  names_pending=""
  names_red=""
  _nrows="$(printf '%s' "$rollup" | "$JQ_BIN" -r --argjson req "$required_contexts_json" '
    .[] | (.name // .context // "") as $n
    | [ $n, (.status // ""), (.state // ""), (.conclusion // ""),
        (.detailsUrl // .targetUrl // ""),
        (if ($req | index($n)) != null then "1" else "0" end) ] | join("\u001f")
  ' 2>/dev/null || true)"
  # \x1f, not a tab: IFS whitespace (tab) would COLLAPSE empty fields and shift columns.
  while IFS=$'\x1f' read -r _n _st _sta _con _url _req; do
    [ -n "$_n" ] || continue
    _in=0
    [ "$_req" = "1" ] && _in=1
    if [ "$_in" -eq 0 ] && [ "$REQUIRED_ONLY" -eq 0 ] && review_pattern_match "$_n" "$REVIEW_PATTERN"; then
      _in=1
    fi
    [ "$_in" -eq 1 ] || continue
    _up_st="$(printf '%s' "$_st" | tr '[:lower:]' '[:upper:]')"
    _up_sta="$(printf '%s' "$_sta" | tr '[:lower:]' '[:upper:]')"
    _up_con="$(printf '%s' "$_con" | tr '[:lower:]' '[:upper:]')"
    if [ "$_up_st" = "QUEUED" ] || [ "$_up_st" = "IN_PROGRESS" ] || [ "$_up_sta" = "PENDING" ] \
       || { [ -z "$_up_st$_up_sta$_up_con" ]; }; then
      names_pending="${names_pending:+$names_pending,}$_n"
      continue
    fi
    # green only when EACH field is exactly a green value (or empty) and one is
    # set — never a prefix of the concatenation (`SUCCESS`+`FAILURE` is red)
    case "$_up_con" in ''|SUCCESS|NEUTRAL|SKIPPED) _g=1 ;; *) _g=0 ;; esac
    case "$_up_sta" in ''|SUCCESS) ;; *) _g=0 ;; esac
    [ -n "$_up_con$_up_sta" ] || _g=0
    if [ "$_g" -eq 0 ]; then
        _rid="$(printf '%s' "$_url" | sed -nE 's#.*/actions/runs/([0-9]+)/.*#\1#p')"
        [ -n "$_rid" ] || _rid="-"
        names_red="${names_red:+$names_red,}$_n@$_rid"
    fi
  done <<EOF_NROWS
$_nrows
EOF_NROWS
  # Required contexts absent from the rollup entirely => pending.
  _missing="$(printf '%s' "$rollup" | "$JQ_BIN" -r --argjson req "$required_contexts_json" '
    [ .[] | (.name // .context // "") ] as $have | $req[] as $r | select(($have | index($r)) == null) | $r
  ' 2>/dev/null || true)"
  while IFS= read -r _n; do
    [ -n "$_n" ] || continue
    names_pending="${names_pending:+$names_pending,}$_n"
  done <<EOF_NMISS
$_missing
EOF_NMISS
}

# names_suffix — the trailing ` pending_names=… red_names=…` fields, or ""
# when --names was not passed (default output byte-unchanged).
names_suffix() {
  [ "$NAMES" -eq 1 ] || return 0
  printf ' pending_names=%s red_names=%s' "${names_pending:-none}" "${names_red:-none}"
}

# ---- Bounded, foreground poll loop (§U2.5 + confirming-pass, mechanized) ----
SECONDS=0   # bash builtin wall-clock counter — reset here so $SECONDS is the
            # elapsed time since THIS script started, never a `date`-diff
            # (bash 3.2 / BSD safe; no `timeout` binary dependency).

while :; do
  _view="$("$GH_BIN" pr view "$PR_URL" --json headRefOid,statusCheckRollup 2>/dev/null || true)"
  live_sha=""
  rollup='[]'
  if [ -n "$_view" ] && printf '%s' "$_view" | "$JQ_BIN" -e . >/dev/null 2>&1; then
    live_sha="$(printf '%s' "$_view" | "$JQ_BIN" -r '.headRefOid // empty' 2>/dev/null || true)"
    rollup="$(printf '%s' "$_view" | "$JQ_BIN" -c '.statusCheckRollup // []' 2>/dev/null || echo '[]')"
  fi

  required_settled=0
  required_green=1
  rp_settled=1        # vacuously settled when not tracked (--required-only)
  pending_names=""

  if [ "$live_sha" = "$SHA" ]; then
    # Required-check stats: total/materialized/in-flight/not-green, computed
    # in ONE jq pass. Materialization is checked SEPARATELY from in-flight —
    # a required context absent from the rollup entirely (not yet created for
    # this sha) is NOT-settled, never silently read as the prior commit's
    # green (the exact race skills/review-heal/SKILL.md's confirming pass
    # names: "an absent entry is indistinguishable from 'not yet queued'").
    _req_stats="$(printf '%s' "$rollup" | "$JQ_BIN" -r --argjson req "$required_contexts_json" '
      ($req | length) as $total
      | [ .[] | select( (( .name // .context // "" ) as $n | ($req | index($n))) != null ) ] as $rows
      | ($rows | length) as $materialized
      | ( [ $rows[] | select(
            (((.status // "") | ascii_upcase) as $st | ($st=="QUEUED" or $st=="IN_PROGRESS"))
            or (((.state // "") | ascii_upcase) == "PENDING")
          ) ] | length ) as $inflight
      | ( [ $rows[] | select(
            ( ((.conclusion // "") | ascii_upcase) as $c | ((.state // "") | ascii_upcase) as $s
              | ($c=="SUCCESS" or $c=="NEUTRAL" or $s=="SUCCESS") | not )
          ) ] | length ) as $notgreen
      | "\($total)\t\($materialized)\t\($inflight)\t\($notgreen)"
    ' 2>/dev/null || printf '0\t0\t0\t0')"
    IFS=$'\t' read -r _req_total _req_materialized _req_inflight _req_notgreen <<EOF_STATS
$_req_stats
EOF_STATS
    _req_total="${_req_total:-0}"; _req_materialized="${_req_materialized:-0}"
    _req_inflight="${_req_inflight:-0}"; _req_notgreen="${_req_notgreen:-0}"

    if [ "$_req_materialized" -ge "$_req_total" ] 2>/dev/null && [ "$_req_inflight" -eq 0 ] 2>/dev/null; then
      required_settled=1
    fi
    if [ "$_req_notgreen" -gt 0 ] 2>/dev/null; then
      required_green=0
    fi

    # Review-producing scope (§U2.5) — bash-native glob match over the FULL
    # rollup (union with required is harmless: a required check that also
    # matches the pattern is already covered by the required stats above).
    if [ "$REQUIRED_ONLY" -eq 0 ]; then
      rp_settled=1
      _rows_tsv="$(printf '%s' "$rollup" | "$JQ_BIN" -r '
        .[] | [ (.name // .context // ""), (.status // ""), (.state // "") ] | @tsv
      ' 2>/dev/null || true)"
      while IFS=$'\t' read -r _c_name _c_status _c_state; do
        [ -n "$_c_name" ] || continue
        review_pattern_match "$_c_name" "$REVIEW_PATTERN" || continue
        _up_status="$(printf '%s' "$_c_status" | tr '[:lower:]' '[:upper:]')"
        _up_state="$(printf '%s' "$_c_state" | tr '[:lower:]' '[:upper:]')"
        if [ "$_up_status" = "QUEUED" ] || [ "$_up_status" = "IN_PROGRESS" ] || [ "$_up_state" = "PENDING" ]; then
          rp_settled=0
          pending_names="${pending_names:+$pending_names,}$_c_name"
        fi
      done <<EOF_ROWS
$_rows_tsv
EOF_ROWS
    fi
    [ "$NAMES" -eq 1 ] && compute_names
  else
    # Unknown/mismatched sha — never settled. Surface it plainly.
    pending_names="sha_mismatch"
    names_pending="sha_mismatch"
    names_red=""
  fi

  if [ "$required_settled" -eq 1 ] && [ "$rp_settled" -eq 1 ]; then
    _req_field="red"
    [ "$required_green" -eq 1 ] && _req_field="green"
    [ "$protection_unknown" -eq 1 ] && _req_field="unknown"
    [ -n "$STATE_FILE" ] && rm -f "$STATE_FILE" 2>/dev/null   # terminal ⇒ a later --continue fails closed
    printf 'SETTLED sha=%s required=%s review_producing=settled%s\n' "$SHA" "$_req_field" "$(names_suffix)"
    exit 0
  fi

  _elapsed=0
  if [ -n "$DEADLINE" ]; then
    [ "$(date +%s)" -ge "$DEADLINE" ] && _elapsed=1
  elif [ "$SECONDS" -ge "$BOUND" ] 2>/dev/null; then
    _elapsed=1
  fi
  if [ "$_elapsed" -eq 1 ]; then
    _req_field="pending"
    if [ "$required_settled" -eq 1 ]; then
      _req_field="red"
      [ "$required_green" -eq 1 ] && _req_field="green"
    fi
    [ "$protection_unknown" -eq 1 ] && _req_field="unknown"
    _rp_field="elapsed"
    [ "$rp_settled" -eq 1 ] && _rp_field="settled"
    [ -n "$pending_names" ] || pending_names="none"
    [ -n "$STATE_FILE" ] && rm -f "$STATE_FILE" 2>/dev/null
    printf 'ELAPSED sha=%s required=%s review_producing=%s pending=%s%s\n' "$SHA" "$_req_field" "$_rp_field" "$pending_names" "$(names_suffix)"
    exit 0
  fi

  # Resumable mode: per-call ceiling reached with total budget left ⇒ CONTINUE
  # (not a result — the caller calls again with --continue on the same sha).
  if [ -n "$DEADLINE" ] && [ "$SECONDS" -ge "$CALL_MAX" ]; then
    [ -n "$pending_names" ] || pending_names="none"
    printf 'CONTINUE sha=%s remaining=%s pending=%s%s\n' "$SHA" "$((DEADLINE - $(date +%s)))" "$pending_names" "$(names_suffix)"
    exit 0
  fi

  sleep "$INTERVAL" 2>/dev/null || sleep 1
done
