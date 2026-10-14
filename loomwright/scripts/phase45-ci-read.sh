#!/usr/bin/env bash
# phase45-ci-read.sh — ONE read of a PR's required checks at Supervisor Phase 4.5 iteration N; every
# red required check becomes ONE BLOCKING finding for that iteration's fix worker.
#
# USAGE
#   phase45-ci-read.sh <pr_url> [--sha <sha>] [--max-probes N]
#
# WHY: Phase 4.5 never read a red required check. PR #533's required `ci` was red on every push and the
# drain spent 2h11m on it after Phase 4.5 had PASSed three times. skills/self-heal-advisory/SKILL.md
# Part 2 runs this once per iteration, AFTER the reviewer returns (right after a push the new head's
# checks are almost always pending; the review takes minutes), and appends each finding to that
# iteration's `fixable_issues` — a red check makes the iteration a fix iteration even on a reviewer PASS.
#
# THE READ (one, never a wait): `wait-for-checks.sh <pr_url> --sha <sha>` with a zero bound,
# `--required-only --names`, parsed ONLY through wait-for-checks-line.sh's `wfc_line_parse` (check names hold spaces;
# never split that line on whitespace). --sha defaults to the PR's `headRefOid`. When <sha> is not the
# PR's head (the line reads `pending_names=sha_mismatch` — e.g. a past head), the required contexts
# (drain-gh-read.sh required-checks) are read against that commit's check-runs
# (`gh api repos/<o>/<r>/commits/<sha>/check-runs`) instead, and the result is written in the same
# line grammar and parsed by the same reader. Honest limit: that fallback reads check-runs only, not
# legacy commit statuses, and the newest run per name.
#
# OUTPUT (stdout), one line each:
#   {"severity":"BLOCKING","category":"new","file":"ci","check":…,"run_id":…,"description":"required
#     check <name> failed on <sha>","log_tail":…}       one JSON line per red required check (jq-built)
#   note<TAB><name><TAB>untrusted_infra — passed to the drain (D3)
#                                       a red check ci-run-probe.sh classifies untrusted_infra (the
#                                       job never ran): NO finding — the owned drain handles it unchanged
#   ci-read: none — <reason>            nothing to fix (D2): required green / pending / unknown, an
#                                       unreadable line, a gh failure, a bad PR URL, no jq
# `log_tail` is the failing step's log tail — `gh run view <run_id> --log-failed`, the ≤40 lines ending
# at the first `##[error]Process completed with exit code` marker (the first failing step's end; the
# log's last lines when there is none — on an aggregating required job those are post-job cleanup),
# job name kept, timestamps and ANSI colour stripped, capped at 4000 bytes, then wrapped by
# wrap-external-text.sh (channel ci-log) as DATA: the log is produced by the PR's own code. A run id of
# `-` or a failed fetch ⇒ `"log_tail":"(log unavailable)"`.
# Probes: ci-run-probe.sh runs for at most --max-probes red checks (default 5); a check beyond the bound
# (or with no run id) is a finding without a probe.
#
# FAILS SAFE: always exits 0; any doubt ⇒ no finding (`ci-read: none — <reason>`).
# TEST SEAMS: GH=<path> overrides gh (as in wait-for-checks.sh / ci-run-probe.sh); PHASE45_CI_READ_WFC
# overrides the wait-for-checks.sh path (test-phase45-ci-read.sh records its arguments).

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GH_BIN="${GH:-gh}"
WFC="${PHASE45_CI_READ_WFC:-$HERE/wait-for-checks.sh}"

none() { printf 'ci-read: none — %s\n' "$1"; exit 0; }

PR_URL=""; SHA=""; MAX_PROBES=5
while [ $# -gt 0 ]; do
  case "$1" in
    --sha) SHA="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --sha=*) SHA="${1#--sha=}"; shift ;;
    --max-probes) MAX_PROBES="${2:-5}"; shift; [ $# -gt 0 ] && shift ;;
    --max-probes=*) MAX_PROBES="${1#--max-probes=}"; shift ;;
    --*) shift ;;
    *) [ -z "$PR_URL" ] && PR_URL="$1"; shift ;;
  esac
done
case "$MAX_PROBES" in ''|*[!0-9]*) MAX_PROBES=5 ;; esac

command -v jq >/dev/null 2>&1 || none "no_jq"
SLUG=""
case "$PR_URL" in
  *github.com/*/*/pull/*) _r="${PR_URL#*github.com/}"; SLUG="${_r%%/pull/*}" ;;
esac
case "$SLUG" in */*/*|""|/*|*/) none "bad_pr_url" ;; esac

if [ -z "$SHA" ]; then
  SHA="$("$GH_BIN" pr view "$PR_URL" --json headRefOid -q .headRefOid 2>/dev/null)" || SHA=""
fi
case "$SHA" in ''|*[!0-9a-fA-F]*) none "gh_unreadable (no head sha)" ;; esac

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/phase45-ci-read.XXXXXX" 2>/dev/null)" || none "no_tmpdir"
trap 'rm -rf "$TMPD"' EXIT

. "$HERE/wait-for-checks-line.sh"

wfc_out="$(bash "$WFC" "$PR_URL" --sha "$SHA" --bound 0 --required-only --names 2>/dev/null)"
wfc_line_parse "${wfc_out##*$'\n'}"

# past_sha_line — the required checks of a commit that is not the PR's head, in wait-for-checks.sh's
# grammar (so the ONE reader parses it). Prints nothing when unreadable.
past_sha_line() {
  local base req runs
  base="$("$GH_BIN" pr view "$PR_URL" --json baseRefName -q .baseRefName 2>/dev/null)" || return 0
  [ -n "$base" ] || return 0
  req="$(bash "$HERE/drain-gh-read.sh" required-checks "$SLUG" "$base" 2>/dev/null)" || return 0
  req="$(printf '%s' "$req" | jq -c '[(.contexts // [])[], ((.checks // [])[] | .context)] | unique' 2>/dev/null)" || return 0
  runs="$("$GH_BIN" api "repos/$SLUG/commits/$SHA/check-runs?per_page=100" 2>/dev/null)" || return 0
  printf '%s' "$runs" | jq -r --argjson req "$req" --arg sha "$SHA" '
    (.check_runs // []) as $all
    | [ $req[] as $c
        | ([ $all[] | select(.name == $c) ] | sort_by(.id) | last) as $r
        | if $r == null or ($r.status // "") != "completed" then {c: $c, s: "pending"}
          elif (($r.conclusion // "") | ascii_downcase) as $k | ($k == "success" or $k == "neutral" or $k == "skipped")
            then {c: $c, s: "green"}
          else {c: $c, s: "red",
                id: ((($r.details_url // "") | capture("/actions/runs/(?<n>[0-9]+)/") | .n) // "-")}
          end ] as $st
    | ([ $st[] | select(.s == "pending") | .c ] | join(",")) as $p
    | ([ $st[] | select(.s == "red") | "\(.c)@\(.id)" ] | join(",")) as $red
    | if $p != "" then "ELAPSED sha=\($sha) required=pending review_producing=settled pending=none pending_names=\($p) red_names=\(if $red == "" then "none" else $red end)"
      elif $red != "" then "SETTLED sha=\($sha) required=red review_producing=settled pending_names=none red_names=\($red)"
      else "SETTLED sha=\($sha) required=green review_producing=settled pending_names=none red_names=none" end
  ' 2>/dev/null
}
if [ "$WFC_PENDING_NAMES" = "sha_mismatch" ]; then
  wfc_line_parse "$(past_sha_line)"
fi

case "$WFC_KIND" in SETTLED|ELAPSED) ;; *) none "unreadable (wait-for-checks line: ${WFC_KIND:-empty})" ;; esac
[ "$WFC_SHA" = "$SHA" ] || none "unreadable (line names sha ${WFC_SHA:-none})"
case "$WFC_REQUIRED" in
  red) ;;
  green|pending|unknown) none "required=$WFC_REQUIRED" ;;
  *) none "required=${WFC_REQUIRED:-unreadable}" ;;
esac
case "$WFC_RED_NAMES" in ''|none) none "required=red but no red check named" ;; esac

# log_tail <run_id> — the failing step's tail, wrapped as EXTERNAL_TEXT, or "(log unavailable)".
log_tail() {
  local rid="$1" w
  case "$rid" in ''|*[!0-9]*) printf '(log unavailable)'; return 0 ;; esac
  "$GH_BIN" run view "$rid" --repo "$SLUG" --log-failed > "$TMPD/log" 2>/dev/null || { printf '(log unavailable)'; return 0; }
  [ -s "$TMPD/log" ] || { printf '(log unavailable)'; return 0; }
  env LC_ALL=C awk '
    {
      l = $0
      gsub(/\033\[[0-9;]*[A-Za-z]/, "", l)
      gsub(/\^\[\[[0-9;]*[A-Za-z]/, "", l)
      n = split(l, f, "\t")
      if (n >= 3) { msg = substr(l, length(f[1]) + length(f[2]) + 3); l = f[1] ": " msg }
      else msg = l
      sub(/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9:.]+Z /, "", l)
      line[NR] = l
      if (!end && index(msg, "##[error]Process completed with exit code")) end = NR
    }
    END { if (!end) end = NR; s = end - 39; if (s < 1) s = 1; for (i = s; i <= end; i++) print line[i] }
  ' "$TMPD/log" > "$TMPD/tail" 2>/dev/null || { printf '(log unavailable)'; return 0; }
  tail -c 4000 "$TMPD/tail" > "$TMPD/tail.cap" 2>/dev/null || { printf '(log unavailable)'; return 0; }
  w="$(jq -Rs '[{body: .}]' < "$TMPD/tail.cap" 2>/dev/null | bash "$HERE/wrap-external-text.sh" --channel ci-log 2>/dev/null)"
  if [ -n "$w" ]; then printf '%s' "$w"; else printf '(log unavailable)'; fi
}

# red_names is `<name>@<run_id|->` joined by `,` — but a check NAME can itself hold `,` (a matrix job:
# `test (ubuntu-latest, 20)@123`). So an entry ends only at a fragment ending `@<digits>` or `@-`; any
# other fragment is joined (with its `,`) onto the next one before name and run id are split.
probes=0
rest="$WFC_RED_NAMES"
while [ -n "$rest" ]; do
  item=""; first=1
  while :; do
    case "$rest" in *,*) frag="${rest%%,*}"; rest="${rest#*,}" ;; *) frag="$rest"; rest="" ;; esac
    if [ "$first" -eq 1 ]; then item="$frag"; first=0; else item="$item,$frag"; fi
    case "$frag" in
      *@-) break ;;
      *@*) case "${frag##*@}" in ''|*[!0-9]*) ;; *) break ;; esac ;;
    esac
    [ -n "$rest" ] || break
  done
  [ -n "$item" ] || continue
  case "$item" in *@*) name="${item%@*}"; rid="${item##*@}" ;; *) name="$item"; rid="-" ;; esac
  verdict=""
  case "$rid" in
    ''|*[!0-9]*) ;;
    *)
      if [ "$probes" -lt "$MAX_PROBES" ]; then
        probes=$((probes + 1))
        verdict="$(GH="$GH_BIN" bash "$HERE/ci-run-probe.sh" --repo "$SLUG" --check "$name" --run-id "$rid" 2>/dev/null | jq -r '.verdict // empty' 2>/dev/null)"
      fi ;;
  esac
  if [ "$verdict" = "untrusted_infra" ]; then
    printf 'note\t%s\tuntrusted_infra — passed to the drain (D3)\n' "$name"
    continue
  fi
  jq -nc --arg check "$name" --arg run_id "$rid" --arg sha "$SHA" --arg tail "$(log_tail "$rid")" \
    '{severity: "BLOCKING", category: "new", file: "ci", check: $check, run_id: $run_id,
      description: ("required check " + $check + " failed on " + $sha), log_tail: $tail}' 2>/dev/null \
    || printf 'ci-read: none — could not build the finding for %s\n' "$name"
done
exit 0
