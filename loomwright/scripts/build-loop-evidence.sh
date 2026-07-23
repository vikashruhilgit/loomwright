#!/usr/bin/env bash
# build-loop-evidence.sh — READ-ONLY loop-evidence builder: the unattended-quality funnel.
#
# ADVISORY / READ-ONLY / FAIL-SAFE — this script NEVER gates anything. It computes, per
# PR/run, the funnel  landed → clean → durable → cheap  from EXISTING .supervisor/ data
# plus a read-only `git log` of the repo containing the state dir. It writes NOTHING
# (except mktemp scratch), mutates NOTHING, and ALWAYS exits 0 — mirroring the
# read-postmortem.sh / read-bridge.sh advisory-reader convention in this directory.
# Absent or malformed inputs degrade to labeled `insufficient_data` cells; numbers are
# NEVER invented (proxy token counts are always labeled as proxy).
#
# FUNNEL STAGES (per run = one session_end event in $STATE_DIR/logs/*.jsonl):
#   landed  — the PR's landing commit is found in git history (squash "(#N)" subject or
#             "Merge pull request #N" merge commit).
#   clean   — no substantive human correction. FALSE-ZERO RULE (mandatory): a PR with
#             0 GitHub review rounds is still NOT clean when drain-internal signals fire:
#             fix_cycles>0 (review_heal_done events), heal_iterations>1, or >=3
#             consecutive <=6-line "drain cycle"-style commits on the PR branch (only
#             detectable for true merge commits — squash merges collapse the branch, in
#             which case that one signal is unavailable and noted under Data quality).
#   durable — no revert / follow-up fix commit touching the same files within 14 days of
#             landing (from git history; "pending(<14d)" until the window closes).
#   cheap   — token spend: real ledger usage preferred; labeled transcript-byte proxy fallback.
#             Ledger sums are FILE-level: shown on every run of a multi-run file for display,
#             but attributed to exactly ONE run per file when summing era totals (no N-fold
#             inflation). A log file the extraction jq cannot process is LABELED under Data
#             quality ("log file <name> unparseable ...") — never silently dropped.
#
# ERA BUCKETS: runs grouped by per-run `plugin_version` (fallback: ship-date eras, labeled
# date_fallback) into pre/post advisory surfaces: rules seams (>=15.1.0, shipped
# ~2026-07-03) and orientation memos (>=15.12.0, shipped ~2026-07-20).
#
# RUBRIC: bucketed auto-authored vs human-approved ONLY when the data distinguishes them
# (rubric_source / rubric_human_approved fields); otherwise the whole column is labeled
# self_graded_unverified.
#
# FLAGS:
#   --state-dir <abs path>   root of all data reads (default ./.supervisor)
#   --jsonl                  machine-readable JSONL to stdout instead of markdown
#   --help                   usage
#
# PORTABILITY: macOS bash 3.2 + Linux CI. No associative arrays, no ${var,,}, no stat(1)
# at all (git commit epochs + `date +%s` only — sidesteps the BSD `stat -f` vs GNU
# `stat -c` flavor trap entirely), numeric-validated before any $(( )) under set -u, and
# NO ${var//...} pattern-substitution over corpus-sized strings (jq/awk stream instead —
# the bash-3.2 O(n^2) multibyte trap).
#
# Exit: ALWAYS 0. Diagnostics to stderr only; degradations listed in ## Data quality.

set -uo pipefail   # `set -e` intentionally omitted — an advisory read must NEVER fail its caller.

# ---------------------------------------------------------------------------- flags
STATE_DIR="./.supervisor"
JSONL=0

usage() {
  cat <<'EOF'
build-loop-evidence.sh — READ-ONLY unattended-quality funnel builder (advisory, never gates)

Usage: build-loop-evidence.sh [--state-dir <abs path>] [--jsonl] [--help]

  --state-dir <path>  Directory holding logs/, postmortem/, heal-signal/ (default ./.supervisor).
                      The repo containing this dir's PARENT is read via `git log` (read-only).
  --jsonl             Emit machine-readable JSONL lines instead of markdown.
  --help              This help.

Always exits 0. Absent/malformed inputs degrade to labeled insufficient_data cells.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --state-dir)
      if [ "$#" -ge 2 ] && [ -n "${2:-}" ]; then
        STATE_DIR="$2"; shift
      else
        echo "build-loop-evidence: --state-dir given without a value — keeping default ($STATE_DIR)" >&2
      fi
      ;;
    --jsonl) JSONL=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "build-loop-evidence: unknown flag '$1' ignored (fail-safe)" >&2 ;;
  esac
  shift
done

# ---------------------------------------------------------------------------- scratch + helpers
WORK="$(mktemp -d 2>/dev/null || true)"
if [ -z "$WORK" ]; then
  # mktemp unavailable — fall back to a $$+$RANDOM path (not guessable-by-PID alone) and
  # refuse to reuse a pre-existing dir (no -p, no ||-swallow: a squattable path is worse
  # than no output). If even that fails, emit a fully-labeled skeleton and exit 0.
  WORK="/tmp/loop-evidence.$$.$RANDOM"
  if ! mkdir "$WORK" 2>/dev/null; then
    if [ "$JSONL" -eq 1 ]; then
      printf '%s\n' '{"type":"data_quality","notes":["scratch dir unavailable (mktemp and fallback both failed) — builder cannot run, every cell insufficient_data"]}'
    else
      printf '%s\n' "# Loop evidence — unattended-quality funnel (advisory, read-only)"
      printf '%s\n' ""
      printf '%s\n' "## Per-run funnel"
      printf '%s\n' "insufficient_data — scratch dir unavailable, builder cannot run"
      printf '%s\n' ""
      printf '%s\n' "## Data quality"
      printf '%s\n' "- scratch dir unavailable (mktemp and fallback both failed) — builder cannot run, every cell insufficient_data"
    fi
    exit 0
  fi
fi
trap 'rm -rf "$WORK" 2>/dev/null' EXIT

DQ="$WORK/data-quality.txt"; : > "$DQ"
dq() { printf '%s\n' "$1" >> "$DQ" 2>/dev/null || true; }
# de-duplicated dq (for notes that would otherwise repeat per run)
dq_once() { grep -Fqx -- "$1" "$DQ" 2>/dev/null || dq "$1"; }

is_num() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

ROWS="$WORK/rows.tsv"; : > "$ROWS"          # final per-run rows for emission (15 cols)
RUNS_TSV="$WORK/runs.tsv"; : > "$RUNS_TSV"  # jq-joined raw run rows (pre-git)

# ---------------------------------------------------------------------------- preconditions
if ! command -v jq >/dev/null 2>&1; then
  # Without jq nothing is parseable — emit a fully-labeled skeleton and exit 0.
  if [ "$JSONL" -eq 1 ]; then
    printf '%s\n' '{"type":"data_quality","notes":["jq unavailable — all inputs unreadable, every cell insufficient_data"]}'
  else
    printf '%s\n' "# Loop evidence — unattended-quality funnel (advisory, read-only)"
    printf '%s\n' ""
    printf '%s\n' "## Per-run funnel"
    printf '%s\n' "insufficient_data — jq unavailable, inputs unreadable"
    printf '%s\n' ""
    printf '%s\n' "## Data quality"
    printf '%s\n' "- jq unavailable — all inputs unreadable, every cell insufficient_data"
  fi
  exit 0
fi

if [ ! -d "$STATE_DIR" ]; then
  dq "state dir not found at $STATE_DIR — every input absent, all cells insufficient_data"
fi

# Repo containing the state dir's parent (read-only git source). May legitimately not exist.
REPO_ROOT=""
if [ -d "$STATE_DIR" ]; then
  REPO_ROOT="$(cd "$STATE_DIR/.." 2>/dev/null && pwd || true)"
fi
GIT_OK=0
GITLOG="$WORK/gitlog.tsv"; : > "$GITLOG"
if [ -n "$REPO_ROOT" ] && command -v git >/dev/null 2>&1 \
   && git -C "$REPO_ROOT" rev-parse --show-toplevel >/dev/null 2>&1; then
  # One capture reused for all PRs: sha <TAB> commit-epoch <TAB> parents <TAB> subject
  if git -C "$REPO_ROOT" log --format='%H%x09%ct%x09%P%x09%s' >"$GITLOG" 2>/dev/null && [ -s "$GITLOG" ]; then
    GIT_OK=1
  fi
fi
[ "$GIT_OK" -eq 1 ] || dq "git history unavailable for state-dir parent — landed/durable/drain-cycle cells insufficient_data"

NOW_EPOCH="$(date -u +%s 2>/dev/null || true)"
is_num "$NOW_EPOCH" || NOW_EPOCH=0

# ---------------------------------------------------------------------------- phase 1: collect (jq only)
RUNS_RAW="$WORK/runs-raw.jsonl"; : > "$RUNS_RAW"
DRAIN_RAW="$WORK/drain-raw.jsonl"; : > "$DRAIN_RAW"
LOGS_SEEN=0
if [ -d "$STATE_DIR/logs" ]; then
  for f in "$STATE_DIR"/logs/*.jsonl; do
    [ -e "$f" ] || continue
    LOGS_SEEN=1
    base="$(basename "$f")"
    # session_end runs + per-file token-ledger sums (malformed lines skipped element-locally).
    # real_tokens guards EACH usage field BEFORE any arithmetic — a string-typed field
    # degrades to 0 instead of aborting the whole file's jq. Any residual jq abort (e.g. a
    # non-object "usage") is LABELED via the || dq branch below, never silently dropped.
    # ledger_*_attr fields carry the file-level sums on the file's LAST session_end ONLY
    # (0 on the rest) so era aggregation counts each file's tokens exactly once.
    jq -R 'fromjson? // empty' "$f" 2>/dev/null | jq -s -c --arg file "$base" '
      ([ .[] | select(type=="object")
             | select(((.event // .type // "") | tostring) | test("^session_end")) ]) as $ends
      | ([ .[] | select(type=="object") | select((.event // "") == "token_ledger") ]) as $led
      | ($led | map(select(.proxy == true) | (.token_proxy_transcript_bytes // 0)
                    | if type=="number" then . else 0 end) | add // 0) as $proxy_bytes
      | ($led | map(select(.proxy != true)
                    | ((.usage // {}) as $u
                       | ([ $u.input_tokens, $u.output_tokens,
                            $u.cache_read_input_tokens, $u.cache_creation_input_tokens ]
                          | map(if type=="number" then . else 0 end) | add)))
               | add // 0) as $real_tokens
      | ($ends | length) as $n
      | range(0; $n) as $i
      | $ends[$i]
      | . + { log_file: $file, ledger_proxy_bytes: $proxy_bytes,
              ledger_real_tokens: $real_tokens, runs_in_file: $n,
              ledger_proxy_bytes_attr: (if $i == ($n - 1) then $proxy_bytes else 0 end),
              ledger_real_tokens_attr: (if $i == ($n - 1) then $real_tokens else 0 end) }
    ' >> "$RUNS_RAW" 2>/dev/null \
      || dq "log file $base unparseable by the runs-extraction jq — its session_end runs omitted"
    # drain-internal fix_cycles signals (review_heal_done events)
    jq -R 'fromjson? // empty' "$f" 2>/dev/null | jq -c '
      select(type=="object") | select((.event // "") == "review_heal_done")
      | { pr_url: ((.pr_url // "") | tostring),
          fix_cycles: ((.fix_cycles // 0) | if type=="number" then . else 0 end) }
    ' >> "$DRAIN_RAW" 2>/dev/null \
      || dq_once "log file $base: drain-signal extraction aborted — its fix_cycles signals omitted"
  done
fi
[ "$LOGS_SEEN" -eq 1 ] || dq "no session logs at $STATE_DIR/logs/*.jsonl — no runs observable (funnel empty)"

# Postmortem corpus (review rounds, root-cause classes). Curation records skipped.
PM="$STATE_DIR/postmortem/results.jsonl"
PM_JSON="$WORK/pm.jsonl"; : > "$PM_JSON"
if [ -s "$PM" ]; then
  jq -R 'fromjson? // empty' "$PM" 2>/dev/null | jq -c '
    select(type=="object")
    | select((.source // "") != "curation")
    | { key: (((.repo // "") | tostring | ascii_downcase) + "#" + ((.number // "") | tostring)),
        review_rounds: (.review_rounds // null),
        classes: ([ (.categories // [])[] | (.class // empty) ]) }
  ' >> "$PM_JSON" 2>/dev/null || true
  [ -s "$PM_JSON" ] || dq "postmortem/results.jsonl present but yielded no parseable data lines — review-round cells insufficient_data"
else
  dq "postmortem/results.jsonl absent or empty — review-round + root-cause-class cells insufficient_data"
fi

# Heal-signal confusion-matrix trend points.
HS="$STATE_DIR/heal-signal/results.jsonl"
HS_SUMMARY=""
if [ -s "$HS" ]; then
  HS_SUMMARY="$(jq -R 'fromjson? // empty' "$HS" 2>/dev/null | jq -s -r '
    map(select(type=="object")) | if length == 0 then empty else
      (.[0]) as $first | (.[-1]) as $last
      | (length | tostring) + " points; first " + (($first.recorded_at // "?") | tostring)
        + " (n=" + (($first.n // "?")|tostring) + ", recall=" + (($first.recall_pct // "?")|tostring)
        + "%, coverage=" + (($first.coverage_pct // "?")|tostring) + "%) -> last "
        + (($last.recorded_at // "?") | tostring)
        + " (n=" + (($last.n // "?")|tostring) + ", recall=" + (($last.recall_pct // "?")|tostring)
        + "%, fp=" + (($last.false_positive_pct // "?")|tostring)
        + "%, coverage=" + (($last.coverage_pct // "?")|tostring) + "%)"
    end' 2>/dev/null || true)"
fi
if [ -z "$HS_SUMMARY" ]; then
  HS_SUMMARY="insufficient_data (heal-signal/results.jsonl absent, empty, or unparseable)"
  dq "heal-signal/results.jsonl absent/unparseable — heal-signal trend insufficient_data"
fi

# ---------------------------------------------------------------------------- phase 2: dedupe + join (jq)
# Key: pr_url when present, else task_id/session_id/log_file. Latest ts wins.
# RUNS_TSV cols (17): label pr_url pr_num version ts heal_iters rubric fix_cycles pm_key
#                     log_file proxy_bytes real_tokens rubric_bucket runs_in_file status
#                     proxy_bytes_attr real_tokens_attr   (once-per-file era attribution)
RUBRIC_DISTINGUISHABLE=0
if [ -s "$RUNS_RAW" ]; then
  rd="$(jq -s '[ .[] | select(has("rubric_source") or has("rubric_human_approved")) ] | length' "$RUNS_RAW" 2>/dev/null || printf 0)"
  is_num "$rd" && [ "$rd" -gt 0 ] && RUBRIC_DISTINGUISHABLE=1
  jq -s -r --slurpfile drain "$DRAIN_RAW" '
    ($drain // []) as $dr
    | map(select(type=="object"))
    | map(. + { _key: (if ((.pr_url // "") | tostring) != "" then ((.pr_url // "")|tostring)
                       else ("nopr:" + ((.task_id // .session_id // .log_file // "?") | tostring)) end) })
    | group_by(._key) | map(max_by((.ts // "") | tostring))
    | .[]
    | ((.pr_url // "") | tostring) as $purl
    # NOTE: capture()? yields EMPTY (not null) on a non-match, which would swallow the whole
    # record — `// null` restores a null $cap so no-PR runs still flow through.
    | ($purl | (capture("github\\.com/(?<owner>[^/]+)/(?<repo>[^/]+)/pull/(?<num>[0-9]+)")? // null)) as $cap
    | (if $cap then ($cap.num) else "-" end) as $prnum
    | (if $cap then (($cap.owner + "/" + $cap.repo) | ascii_downcase) else "" end) as $prrepo
    | ([ $dr[] | select((.pr_url // "") == $purl and $purl != "") | .fix_cycles ] | max // 0) as $fc
    | [ ((.task_id // .session_id // .log_file // "?") | tostring),
        (if $purl == "" then "-" else $purl end),
        $prnum,
        ((.plugin_version // "-") | tostring),
        ((.ts // "-") | tostring),
        ((.heal_iterations // "-") | tostring),
        ((.rubric_score // "-") | tostring),
        ($fc | tostring),
        ($prrepo + "#" + $prnum),
        ((.log_file // "-") | tostring),
        ((.ledger_proxy_bytes // 0) | tostring),
        ((.ledger_real_tokens // 0) | tostring),
        (if has("rubric_source") or has("rubric_human_approved")
         then (if ((.rubric_source // "") == "human") or (.rubric_human_approved == true)
               then "human_approved" else "auto_authored" end)
         else "-" end),
        ((.runs_in_file // 1) | tostring),
        ((.status // "-") | tostring),
        ((.ledger_proxy_bytes_attr // .ledger_proxy_bytes // 0) | tostring),
        ((.ledger_real_tokens_attr // .ledger_real_tokens // 0) | tostring) ]
    | @tsv
  ' "$RUNS_RAW" > "$RUNS_TSV" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------- phase 3: git enrichment + row build
era_of() {
  # $1 = plugin_version ("-" if absent), $2 = ts. Sets ERA + VER_DISPLAY.
  ERA="unknown"; VER_DISPLAY="unknown"
  _ver="${1:-}"; _ts="${2:-}"
  if [ -n "$_ver" ] && [ "$_ver" != "-" ]; then
    _maj="${_ver%%.*}"; _rest="${_ver#*.}"; _min="${_rest%%.*}"
    if is_num "$_maj" && is_num "$_min"; then
      if [ "$_maj" -gt 15 ] || { [ "$_maj" -eq 15 ] && [ "$_min" -ge 12 ]; }; then ERA="post_orientation_memos"
      elif [ "$_maj" -eq 15 ] && [ "$_min" -ge 1 ]; then ERA="post_rules_seams"
      else ERA="pre_rules"
      fi
      VER_DISPLAY="$_ver"
      return 0
    fi
  fi
  # ship-date fallback (lexicographic on the YYYY-MM-DD prefix — portable, no date parsing)
  _d="${_ts%%T*}"
  case "$_d" in
    20[0-9][0-9]-[0-1][0-9]-[0-3][0-9])
      if [ "$_d" \> "2026-07-19" ]; then ERA="post_orientation_memos"
      elif [ "$_d" \> "2026-07-02" ]; then ERA="post_rules_seams"
      else ERA="pre_rules"
      fi
      VER_DISPLAY="date_fallback:$_d"
      dq_once "one or more runs lack plugin_version — bucketed by ship-date fallback (labeled date_fallback), less precise than a version stamp"
      ;;
    *) dq_once "one or more runs lack BOTH plugin_version and a parseable ts — era bucket unknown" ;;
  esac
  return 0
}

find_landing() {
  # $1 = PR number. Sets L_SHA L_CT L_PARENTS ("" if not found).
  # CAVEAT (heuristic): GITLOG is newest-first and the awk exits on the FIRST subject
  # matching "(#N)" or "Merge pull request #N" — newest reference wins, so a LATER
  # revert/reference commit mentioning (#N) becomes the landing SHA for that PR.
  L_SHA=""; L_CT=""; L_PARENTS=""
  [ "$GIT_OK" -eq 1 ] || return 0
  is_num "${1:-}" || return 0
  _line="$(awk -F'\t' -v n="$1" '
    { s = $4 }
    s ~ ("\\(#" n "\\)") || s ~ ("Merge pull request #" n "( |$)") { print; exit }
  ' "$GITLOG" 2>/dev/null || true)"
  [ -n "$_line" ] || return 0
  L_SHA="$(printf '%s' "$_line" | cut -f1)"
  L_CT="$(printf '%s' "$_line" | cut -f2)"
  L_PARENTS="$(printf '%s' "$_line" | cut -f3)"
  is_num "$L_CT" || L_CT=""
  return 0
}

drain_cycle_check() {
  # $1 = landing sha, $2 = parents. Sets DC = yes|no|unavailable.
  DC="unavailable"
  [ "$GIT_OK" -eq 1 ] || return 0
  case "${2:-}" in
    *" "*) : ;;   # true merge commit — PR-branch commits reachable via parent2
    *)
      dq_once "squash-merged PRs collapse branch history — drain-cycle commit signal unavailable there (clean relies on fix_cycles/heal_iterations for those)"
      return 0 ;;
  esac
  _p1="${2%% *}"; _p2="${2#* }"; _p2="${_p2%% *}"
  DC="no"
  _run_len=0; _max_run=0
  # newest-first order is fine — consecutiveness is preserved either direction
  _shas="$(git -C "$REPO_ROOT" log --format='%H' "$_p1..$_p2" 2>/dev/null | head -200 || true)"
  if [ -z "$_shas" ]; then DC="unavailable"; return 0; fi
  while IFS= read -r _s; do
    [ -n "$_s" ] || continue
    _subj="$(git -C "$REPO_ROOT" log -1 --format='%s' "$_s" 2>/dev/null || true)"
    _lines="$(git -C "$REPO_ROOT" show --format= --numstat "$_s" 2>/dev/null \
      | awk '($1 ~ /^[0-9]+$/) && ($2 ~ /^[0-9]+$/) { t += $1 + $2 } END { print t + 0 }' || printf 0)"
    is_num "$_lines" || _lines=0
    if [ "$_lines" -le 6 ] && printf '%s' "$_subj" | grep -Eiq '(fix|review|round|nit|heal|drain|address|bot)'; then
      _run_len=$((_run_len + 1))
      [ "$_run_len" -gt "$_max_run" ] && _max_run=$_run_len
    else
      _run_len=0
    fi
  done <<EOF
$_shas
EOF
  [ "$_max_run" -ge 3 ] && DC="yes"
  return 0
}

durable_check() {
  # $1 = landing sha, $2 = landing epoch. Sets DURABLE.
  DURABLE="insufficient_data"
  [ "$GIT_OK" -eq 1 ] || return 0
  is_num "${2:-}" || return 0
  _win_end=$(( $2 + 1209600 ))   # 14 days
  _lfiles="$WORK/landing-files.txt"
  git -C "$REPO_ROOT" diff --name-only "${1}^1" "$1" >"$_lfiles" 2>/dev/null \
    || git -C "$REPO_ROOT" diff-tree --no-commit-id --name-only -r "$1" >"$_lfiles" 2>/dev/null \
    || : > "$_lfiles"
  if [ ! -s "$_lfiles" ]; then DURABLE="insufficient_data"; return 0; fi
  # candidate follow-ups: revert/fix-style subjects landed inside the window (bounded 50)
  # CAVEAT (heuristic): the subject regex below is a conventional-prefix heuristic —
  # non-conventional follow-up subjects ("bug:", "correct ...", "repair ...") are missed
  # entirely → possible false durable=yes. Matching behavior is deliberately FROZEN
  # (the published SPIKE verdicts rest on it); this note is documentation only.
  _cands="$(awk -F'\t' -v lo="$2" -v hi="$_win_end" '
    ($2 ~ /^[0-9]+$/) && ($2 + 0 > lo + 0) && ($2 + 0 <= hi + 0) \
      && ($4 ~ /^([Rr]evert|fix|Fix|hotfix)/) { print $1 }
  ' "$GITLOG" 2>/dev/null | head -50 || true)"
  _hit=""
  if [ -n "$_cands" ]; then
    while IFS= read -r _c; do
      [ -n "$_c" ] || continue
      if git -C "$REPO_ROOT" diff-tree --no-commit-id --name-only -r "$_c" 2>/dev/null \
         | grep -Fx -f "$_lfiles" >/dev/null 2>&1; then
        _hit="$_c"; break
      fi
    done <<EOF
$_cands
EOF
  fi
  if [ -n "$_hit" ]; then
    _hit7="$(printf '%s' "$_hit" | cut -c1-7)"
    DURABLE="no (follow-up fix $_hit7 touched same files <14d)"
    dq_once "durable is a file-overlap heuristic and is SENSITIVE to hot shared files — one wide fix/revert commit touching e.g. CLAUDE.md can mark many PRs non-durable at once; read clustered durable=no rows as a prompt to inspect, not a verdict"
  elif [ "$NOW_EPOCH" -ne 0 ] && [ "$NOW_EPOCH" -lt "$_win_end" ]; then
    DURABLE="pending(<14d)"
  else
    DURABLE="yes"
  fi
  return 0
}

while IFS=$'\t' read -r label purl prnum ver ts hi rubric fc pmkey logfile pbytes rtok rbucket ninfile status pbattr rtattr; do
  [ -n "${label:-}" ] || continue
  era_of "$ver" "$ts"

  # postmortem join (exact repo#number key)
  rr="-"; classes="-"
  if [ -s "$PM_JSON" ] && [ "$prnum" != "-" ] && [ "${pmkey%#*}" != "" ]; then
    pmline="$(jq -c --arg k "$pmkey" 'select(.key == $k)' "$PM_JSON" 2>/dev/null | head -1 || true)"
    if [ -n "$pmline" ]; then
      rr="$(printf '%s' "$pmline" | jq -r '.review_rounds // "-"' 2>/dev/null || printf -- -)"
      classes="$(printf '%s' "$pmline" | jq -r '.classes | if length==0 then "-" else join(",") end' 2>/dev/null || printf -- -)"
    fi
  fi

  # git stages
  landed="insufficient_data"
  DC="unavailable"; DURABLE="insufficient_data"
  if [ "$prnum" = "-" ]; then
    landed="insufficient_data(no_pr_url)"
    DURABLE="-"
  elif [ "$GIT_OK" -eq 1 ]; then
    find_landing "$prnum"
    if [ -n "$L_SHA" ]; then
      landed="yes"
      drain_cycle_check "$L_SHA" "$L_PARENTS"
      durable_check "$L_SHA" "$L_CT"
    else
      landed="no(not_in_history)"
      DURABLE="-"
    fi
  fi

  # clean (FALSE-ZERO RULE: drain-internal signals override a 0-GitHub-rounds reading)
  reasons=""; not_clean=0
  if is_num "$rr" && [ "$rr" -gt 0 ]; then not_clean=1; reasons="${reasons}review_rounds=$rr "; fi
  if is_num "$fc" && [ "$fc" -gt 0 ]; then not_clean=1; reasons="${reasons}fix_cycles=$fc "; fi
  if is_num "$hi" && [ "$hi" -gt 1 ]; then not_clean=1; reasons="${reasons}heal_iterations=$hi "; fi
  if [ "$DC" = "yes" ]; then not_clean=1; reasons="${reasons}drain_cycle_commits "; fi
  if [ "$not_clean" -eq 1 ]; then
    clean="no (${reasons% })"
  elif ! is_num "$rr"; then
    clean="insufficient_data(no_postmortem)"
  else
    clean="yes"
  fi

  # cheap
  cheap="insufficient_data"
  if is_num "$rtok" && [ "$rtok" -gt 0 ]; then
    cheap="real:${rtok}t"
  elif is_num "$pbytes" && [ "$pbytes" -gt 0 ]; then
    cheap="proxy:${pbytes}B"
    dq_once "token spend for one or more runs is a transcript-byte PROXY (labeled proxy:), not real usage"
  fi
  if is_num "$ninfile" && [ "$ninfile" -gt 1 ]; then
    dq_once "a session log file holds multiple session_end runs — its token sum is file-level, shared across those runs for per-run display; era totals count each file's sum exactly ONCE (attributed to the file's latest run)"
  fi
  is_num "${pbattr:-}" || pbattr=0
  is_num "${rtattr:-}" || rtattr=0

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$ERA" "$label" "$VER_DISPLAY" "$landed" "$clean" "$DURABLE" "$cheap" \
    "$hi" "$rr" "$fc" "$classes" "$pbytes" "$rtok" "$rubric" "$rbucket" \
    "$pbattr" "$rtattr" >> "$ROWS"
done < "$RUNS_TSV"

# rows.tsv cols (17): era label ver landed clean durable cheap heal_iters review_rounds
#                     fix_cycles classes proxy_bytes real_tokens rubric rubric_bucket
#                     proxy_bytes_attr real_tokens_attr  (summed ONCE per file in era totals)

# ---------------------------------------------------------------------------- phase 4: era aggregation (awk)
ERAS="$WORK/eras.tsv"
awk -F'\t' '
  { era = $1; n[era]++
    if ($4 == "yes") landed[era]++
    if ($5 == "yes") clean[era]++
    if ($6 == "yes") durable[era]++
    if ($8 ~ /^[0-9]+$/) { hi_sum[era] += $8; hi_n[era]++ }
    if ($9 ~ /^[0-9]+$/) { rr_sum[era] += $9; rr_n[era]++ }
    if ($10 ~ /^[0-9]+$/) fc_sum[era] += $10
    if ($11 != "-" && $11 != "") { m = split($11, cl, ","); for (i = 1; i <= m; i++) mix[era SUBSEP cl[i]]++ }
    # token sums use the _attr cols ($16/$17): file-level ledger sums attributed to ONE
    # run per file — summing the per-run display cols ($12/$13) would inflate N-run files N-fold
    if ($16 ~ /^[0-9]+$/) pb[era] += $16
    if ($17 ~ /^[0-9]+$/) rt[era] += $17
  }
  END {
    for (era in n) {
      cm = ""
      for (k in mix) {
        split(k, kk, SUBSEP)
        if (kk[1] == era) cm = cm kk[2] "(" mix[k] ") "
      }
      sub(/ $/, "", cm)
      if (cm == "") cm = "-"
      printf "%s\t%d\t%d\t%d\t%d\t%s\t%s\t%d\t%s\t%s\n",
        era, n[era], landed[era], clean[era], durable[era],
        (hi_n[era] ? sprintf("%.1f", hi_sum[era] / hi_n[era]) : "-"),
        (rr_n[era] ? sprintf("%.1f", rr_sum[era] / rr_n[era]) : "-"),
        fc_sum[era], cm,
        (rt[era] ? "real:" rt[era] "t" : (pb[era] ? "proxy:" pb[era] "B" : "insufficient_data"))
    }
  }
' "$ROWS" 2>/dev/null | sort > "$ERAS" || : > "$ERAS"

RUBRIC_LABEL="self_graded_unverified"
[ "$RUBRIC_DISTINGUISHABLE" -eq 1 ] && RUBRIC_LABEL="bucketed (auto_authored vs human_approved)"

[ -s "$DQ" ] || dq "none — all inputs present and parseable"

# ---------------------------------------------------------------------------- emission
if [ "$JSONL" -eq 1 ]; then
  while IFS=$'\t' read -r era label ver landed clean durable cheap hi rr fc classes pbytes rtok rubric rbucket pbattr rtattr; do
    [ -n "${era:-}" ] || continue
    jq -c -n --arg era "$era" --arg run "$label" --arg version "$ver" --arg landed "$landed" \
      --arg clean "$clean" --arg durable "$durable" --arg cheap "$cheap" --arg heal_iterations "${hi:--}" \
      --arg review_rounds "${rr:--}" --arg fix_cycles "${fc:--}" --arg classes "${classes:--}" \
      --arg rubric "${rubric:--}" --arg rubric_bucket "${rbucket:--}" \
      '{type:"run", era:$era, run:$run, version:$version, landed:$landed, clean:$clean,
        durable:$durable, cheap:$cheap, heal_iterations:$heal_iterations,
        review_rounds:$review_rounds, fix_cycles:$fix_cycles, classes:$classes,
        rubric_score:$rubric, rubric_bucket:$rubric_bucket}' 2>/dev/null || true
  done < "$ROWS"
  while IFS=$'\t' read -r era n landed clean durable ahi arr fc mix tok; do
    [ -n "${era:-}" ] || continue
    jq -c -n --arg era "$era" --arg runs "$n" --arg landed "$landed" --arg clean "$clean" \
      --arg durable "$durable" --arg avg_heal_iterations "${ahi:--}" --arg avg_review_rounds "${arr:--}" \
      --arg fix_cycles "${fc:--}" --arg class_mix "${mix:--}" --arg advisory_tokens "${tok:--}" \
      '{type:"era_bucket", era:$era, runs:$runs, landed:$landed, clean:$clean, durable:$durable,
        avg_heal_iterations:$avg_heal_iterations, avg_review_rounds:$avg_review_rounds,
        fix_cycles:$fix_cycles, class_mix:$class_mix, advisory_tokens:$advisory_tokens}' 2>/dev/null || true
  done < "$ERAS"
  jq -c -n --arg hs "$HS_SUMMARY" --arg rubric "$RUBRIC_LABEL" \
    '{type:"meta", heal_signal_trend:$hs, rubric_column:$rubric}' 2>/dev/null || true
  jq -c -n --rawfile notes "$DQ" \
    '{type:"data_quality", notes: ($notes | split("\n") | map(select(. != "")))}' 2>/dev/null || true
  exit 0
fi

printf '%s\n' "# Loop evidence — unattended-quality funnel (advisory, read-only)"
printf '%s\n' ""
printf '%s\n' "Advisory evidence readout — never gates anything; subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)."
printf '%s\n' "State dir: $STATE_DIR"
printf '%s\n' ""
printf '%s\n' "## Per-run funnel"
if [ -s "$ROWS" ]; then
  printf '%s\n' "| run | version | landed | clean | durable | cheap |"
  printf '%s\n' "|---|---|---|---|---|---|"
  while IFS=$'\t' read -r era label ver landed clean durable cheap hi rr fc classes pbytes rtok rubric rbucket pbattr rtattr; do
    [ -n "${era:-}" ] || continue
    printf '| %s | %s | %s | %s | %s | %s |\n' "$label" "$ver" "$landed" "$clean" "$durable" "$cheap"
  done < "$ROWS"
else
  printf '%s\n' "insufficient_data — no runs observable (no session_end events found under $STATE_DIR/logs/)"
fi
printf '%s\n' ""
printf '%s\n' "## Era buckets (advisory surfaces: rules seams >=15.1.0, orientation memos >=15.12.0)"
if [ -s "$ERAS" ]; then
  printf '%s\n' "| era | runs | landed | clean | durable | avg heal iters | avg review rounds | fix_cycles | root-cause class mix | advisory tokens |"
  printf '%s\n' "|---|---|---|---|---|---|---|---|---|---|"
  while IFS=$'\t' read -r era n landed clean durable ahi arr fc mix tok; do
    [ -n "${era:-}" ] || continue
    printf '| %s | %s | %s/%s | %s/%s | %s/%s | %s | %s | %s | %s | %s |\n' \
      "$era" "$n" "$landed" "$n" "$clean" "$n" "$durable" "$n" "${ahi:--}" "${arr:--}" "${fc:-0}" "${mix:--}" "${tok:--}"
  done < "$ERAS"
else
  printf '%s\n' "insufficient_data — no runs to bucket"
fi
printf '%s\n' ""
printf '%s\n' "## Rubric scores"
printf '%s\n' "Rubric column label: $RUBRIC_LABEL"
if [ "$RUBRIC_DISTINGUISHABLE" -eq 0 ]; then
  printf '%s\n' "(auto-authored vs human-approved rubrics are NOT distinguishable in the recorded data — whole column labeled self_graded_unverified)"
fi
if [ -s "$ROWS" ]; then
  printf '%s\n' "| run | rubric_score | bucket |"
  printf '%s\n' "|---|---|---|"
  while IFS=$'\t' read -r era label ver landed clean durable cheap hi rr fc classes pbytes rtok rubric rbucket pbattr rtattr; do
    [ -n "${era:-}" ] || continue
    b="${rbucket:--}"
    [ "$b" = "-" ] && b="$RUBRIC_LABEL"
    printf '| %s | %s | %s |\n' "$label" "${rubric:--}" "$b"
  done < "$ROWS"
else
  printf '%s\n' "insufficient_data — no runs"
fi
printf '%s\n' ""
printf '%s\n' "## Heal-signal trend"
printf '%s\n' "$HS_SUMMARY"
printf '%s\n' ""
printf '%s\n' "## Data quality"
while IFS= read -r note; do
  [ -n "$note" ] && printf -- '- %s\n' "$note"
done < "$DQ"

exit 0
