# automate-helpers.d/escalation.sh — sourced by automate-helpers.sh (escalation-cause).
# Family file (parallel-automate/11 layout): the dispatcher sources it by name and
# owns $GH / $JQ (the LOOMWRIGHT_GH_BIN / LOOMWRIGHT_JQ_BIN seams).

# escalation-cause <pr_url> --sha <sha> — automate-followups/31. Names WHY an
# until-mergeable drain ended ESCALATED, so the park can record it and the merge
# watcher can re-check a temporary cause. A READER/CLASSIFIER: it never merges,
# pushes, approves, or reruns anything, and ALWAYS exits 0 with EXACTLY ONE line:
#   escalation_cause: <cause> check=<name|null> run_id=<id|null> attempt=<n|null> sha=<sha>
# Causes (fail-CLOSED throughout — any doubt resolves to `check_red`):
#   check_pending        NO scoped check is red and a scoped (required ∪ review-producing)
#                        check has not completed (red is examined first — a red check
#                        beside a pending one is classified as red).
#   check_red_unrelated  every red scoped check's every failed step ran ONLY
#                        `bash <path>/test-*.sh` commands (every script line of each failed
#                        step's `##[group]Run` block in `gh run view <id> --log-failed`,
#                        _esc_failing_tests) and every such test file is unrelated to the
#                        PR: neither it nor its tested script `<dir>/<stem>.sh` (for
#                        `<dir>/test-<stem>.sh`) is among the PR's changed files.
#   check_red            anything else red — and every unreadable case: a snapshot
#                        that is not a sha-matched `--names` line, `required=unknown`
#                        (the required set is then unknown), a red check with no run
#                        id, an unreadable log, a failed step with no `Run` block or
#                        running any non-test command (e.g. a step's second command
#                        `bash scripts/<x>.sh`), an
#                        unreadable/incomplete PR file list (_rs_pr_changed_paths —
#                        called, not copied), or any other `gh` failure.
#   other                nothing pending, nothing red — the escalation was not check-driven.
# The snapshot is wait-for-checks.sh --bound 0 --names (review-check pattern defaults).
escalation_cause() {
  _esc_classify "$@" || true
  return 0
}

# _esc_classify — the classifier body, run in a SUBSHELL with errexit/pipefail off so
# no gh/jq failure can abort the dispatcher's `set -euo pipefail` before the one line prints.
_esc_classify() (
  set +e +o pipefail
  local url="" sha="" snap w first req="" pnames="" rnames="" have_pn=0 have_rn=0 pend_field=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --sha) sha="${2:-}"; shift; [ "$#" -gt 0 ] && shift ;;
      --sha=*) sha="${1#--sha=}"; shift ;;
      -*) shift ;;
      *) [ -z "$url" ] && url="$1"; shift ;;
    esac
  done
  case "$sha" in ''|*[!0-9A-Za-z]*) sha="${sha:-null}"; _esc_out check_red null null null "$sha"; exit 0 ;; esac
  [ -n "$url" ] || { _esc_out check_red null null null "$sha"; exit 0; }

  snap="$(GH="$GH" JQ="$JQ" bash "$(dirname "$0")/wait-for-checks.sh" "$url" --sha "$sha" --bound 0 --interval 1 --names 2>/dev/null | tail -n 1)"
  first="${snap%% *}"
  set -f
  for w in $snap; do
    case "$w" in
      required=*) req="${w#required=}" ;;
      pending=*) pend_field="${w#pending=}" ;;
      pending_names=*) pnames="${w#pending_names=}"; have_pn=1 ;;
      red_names=*) rnames="${w#red_names=}"; have_rn=1 ;;
    esac
  done
  set +f
  if { [ "$first" != SETTLED ] && [ "$first" != ELAPSED ]; } || [ "$have_pn" = 0 ] || [ "$have_rn" = 0 ] \
     || [ "$req" = unknown ] || [ -z "$req" ] || [ "$pnames" = sha_mismatch ] || [ "$pend_field" = sha_mismatch ]; then
    _esc_out check_red null null null "$sha"; exit 0
  fi

  local c rid att
  # Red is examined BEFORE pending (the more severe signal wins): check_pending only
  # when NO scoped check is red — a red check beside a pending one is classified as red.
  if [ -z "$rnames" ] || [ "$rnames" = none ]; then
    if [ -n "$pnames" ] && [ "$pnames" != none ]; then
      c="${pnames%%,*}"
      rid="$(_esc_run_id_for "$url" "$c")"
      att=null; [ "$rid" != null ] && att="$(_esc_attempt "$rid")"
      _esc_out check_pending "$c" "$rid" "$att" "$sha"; exit 0
    fi
    # Nothing pending, nothing red: a required=red claim with no named red check is inconsistent.
    if [ "$req" = red ]; then _esc_out check_red null null null "$sha"; else _esc_out other null null null "$sha"; fi
    exit 0
  fi

  local first_c="${rnames%%,*}" first_name first_rid first_att paths view entry name log tests t verdict=check_red_unrelated
  first_name="${first_c%@*}"; first_rid="${first_c##*@}"
  case "$first_rid" in ''|-|*[!0-9]*) first_rid=null ;; esac
  first_att=null; [ "$first_rid" != null ] && first_att="$(_esc_attempt "$first_rid")"

  view="$("$GH" pr view "$url" --json changedFiles,files 2>/dev/null)"
  if [ -z "$view" ] || ! paths="$(_rs_pr_changed_paths "$url" "$view")" || [ -z "$paths" ]; then
    _esc_out check_red "$first_name" "$first_rid" "$first_att" "$sha"; exit 0
  fi

  local oldIFS="$IFS"
  IFS=','
  set -f
  set -- $rnames
  set +f
  IFS="$oldIFS"
  for entry in "$@"; do
    name="${entry%@*}"; rid="${entry##*@}"
    case "$rid" in ''|-|*[!0-9]*) verdict=check_red; break ;; esac
    log="$("$GH" run view "$rid" --log-failed 2>/dev/null)" || { verdict=check_red; break; }
    tests="$(_esc_failing_tests "$log")" || { verdict=check_red; break; }
    [ -n "$tests" ] || { verdict=check_red; break; }
    while IFS= read -r t; do
      [ -n "$t" ] || continue
      if _esc_related "$t" "$paths"; then verdict=check_red; break; fi
    done <<ESC_TESTS
$tests
ESC_TESTS
    [ "$verdict" = check_red ] && break
  done
  _esc_out "$verdict" "$first_name" "$first_rid" "$first_att" "$sha"
  exit 0
)

# _esc_out <cause> <check> <run_id> <attempt> <sha> — the ONE output line.
_esc_out() {
  printf 'escalation_cause: %s check=%s run_id=%s attempt=%s sha=%s\n' "$1" "${2:-null}" "${3:-null}" "${4:-null}" "${5:-null}"
}

# _esc_run_id_for <pr_url> <check_name> — the run id parsed from the named check's
# rollup detailsUrl (`/actions/runs/(N)/`, review-heal §U4's regex), or `null`.
_esc_run_id_for() {
  local v id
  v="$("$GH" pr view "$1" --json statusCheckRollup 2>/dev/null)"
  id="$(printf '%s' "$v" | ESC_NAME="$2" "$JQ" -r '
    [ (.statusCheckRollup // [])[] | select((.name // .context // "") == env.ESC_NAME)
      | (.detailsUrl // .targetUrl // "") ][0] // ""' 2>/dev/null \
    | sed -nE 's#.*/actions/runs/([0-9]+)(/.*)?$#\1#p')"
  case "$id" in ''|*[!0-9]*) echo null ;; *) echo "$id" ;; esac
}

# _esc_attempt <run_id> — `gh run view <id> --json attempt`, digits only, else `null`.
_esc_attempt() {
  local a
  a="$("$GH" run view "$1" --json attempt 2>/dev/null | "$JQ" -r '.attempt // empty' 2>/dev/null)"
  case "$a" in ''|*[!0-9]*) echo null ;; *) echo "$a" ;; esac
}

# _esc_failing_tests <log> — the unique test-file paths the failed steps ran. A
# `--log-failed` line is `<job>\t<step>\t<ts> <text>`; each failed (job, step) must
# carry a `##[group]Run …` header whose script lines (the `ESC[36;1m…ESC[0m` lines, ESC or `^[`,
# before `##[endgroup]` — ALL of a multi-command step's commands) are EVERY one a
# `bash <path>/test-*.sh [args]` command, the args plain words only (no shell
# operator, substitution, quote or redirect — the whole line is matched). Exit 1 (⇒ check_red) when any failed
# (job, step) has no header or no script line, or any script line is anything else
# (a non-test `bash scripts/<x>.sh`, another command) — never a partial answer.
_esc_failing_tests() {
  local r
  r="$(printf '%s\n' "$1" | awk -F'\t' -v esc="$(printf '\033')" '
    BEGIN { bad = 0; n = 0 }
    NF < 3 { next }
    {
      k = $1 FS $2; t = $3; for (i = 4; i <= NF; i++) t = t FS $i
      sub(/\r$/, "", t); sub(/^[^ ]* /, "", t)
      if (!(k in seen)) { seen[k] = 1; ord[++n] = k }
      if (index(t, "##[group]Run ") == 1) { hdr[k] = 1; grp[k] = 1; next }
      if (index(t, "##[endgroup]") == 1) { grp[k] = 0; next }
      if (!grp[k]) next
      # the ESC byte, or its caret form `^[` (as some log captures carry it)
      if (index(t, esc "[36;1m") == 1) { e = esc } else if (index(t, "^[[36;1m") == 1) { e = "^[" } else next
      l = substr(t, length(e) + 7); suf = e "[0m"
      if (length(l) >= length(suf) && substr(l, length(l) - length(suf) + 1) == suf) l = substr(l, 1, length(l) - length(suf))
      gsub(/^[ ]+|[ ]+$/, "", l)
      if (l == "") next
      cnt[k]++
      # the WHOLE line is the test command: its arguments are plain words only (a
      # shell operator / substitution / quote / redirect after the path — e.g.
      # `bash scripts/test-x.sh && bash scripts/x.sh` — is a non-test command ⇒ bad)
      if (l ~ /^bash (\.\/)?([A-Za-z0-9._-]+\/)*test-[A-Za-z0-9._-]+\.sh( +[A-Za-z0-9._\/=:,@%+-]+)*$/) {
        p = l; sub(/^bash (\.\/)?/, "", p); sub(/ .*$/, "", p); out[p] = 1
      } else bad = 1
    }
    END {
      for (i = 1; i <= n; i++) if (!hdr[ord[i]] || !cnt[ord[i]]) bad = 1
      if (bad || n == 0) exit 1
      for (p in out) print p
    }')" || return 1
  printf '%s\n' "$r" | sort -u
}

# _esc_related <test_path> <pr_paths> — 0 when the test file OR its tested script
# (<dir>/<stem>.sh for <dir>/test-<stem>.sh) is among the PR's changed files. A PR
# path ENDING in `/<path>` also counts (the CI step may run from a subdirectory) —
# the over-match errs toward `check_red`, never toward `check_red_unrelated`.
_esc_related() {
  local t="$1" paths="$2" base script p
  while :; do case "$t" in ./*) t="${t#./}" ;; *) break ;; esac; done
  # a `.`/`..` segment cannot be resolved against the PR's repo-relative paths ⇒
  # treated as related (fail CLOSED toward check_red)
  case "/$t/" in */./*|*/../*) return 0 ;; esac
  base="${t##*/}"
  # a bare `test-<stem>.sh` (no `/`) tests the bare `<stem>.sh` — never `${t%/*}`,
  # which is the whole name when no `/` is present
  case "$t" in */*) script="${t%/*}/${base#test-}" ;; *) script="${base#test-}" ;; esac
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in
      "$t"|*/"$t"|"$script"|*/"$script") return 0 ;;
    esac
  done <<ESC_PATHS
$paths
ESC_PATHS
  return 1
}
