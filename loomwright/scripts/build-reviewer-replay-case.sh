#!/usr/bin/env bash
# build-reviewer-replay-case.sh — the phase45-reviewer corpus builder: proposes Phase 4.5 reviewer-miss
# cases and clean controls from this repo's own merged PRs, and writes ONE case only when the owner confirms.
#
#   build-reviewer-replay-case.sh --list [--since <date>] [--ledger <results.jsonl>]
#   build-reviewer-replay-case.sh --pr <N> [--floor BLOCKING|HIGH|MEDIUM|LOW] [--file <path>] [--control] [--confirm]
#
# Source of truth is LOCAL GIT; the postmortem ledger (.supervisor/postmortem/results.jsonl, gitignored) is
# read only to annotate `--list` rows with that PR's recorded `self_heal_misses`, never to pick a case.
#
# WHAT A CANDIDATE IS. Only first-parent merges of this repo's base branch (see below) whose subject is
# `Merge pull request #<N> from …` are considered (a squash merge has no second-parent chain and is never a
# candidate). The PR's commits are `<merge>^1..<merge>^2`. Its PRE-DRAIN HEAD is the newest of them whose
# subject is Phase 4.5's own fix-commit subject, `fix: address review feedback (iteration <n>)`
# (skills/self-heal-advisory/SKILL.md) — a PR without one never went through Phase 4.5 and is skipped. Its
# BASE is `git merge-base <merge>^1 <pre-drain head>`, so `base..pre-drain head` is exactly the diff the
# Phase 4.5 reviewer last saw. LATER commits are the PR's commits after the pre-drain head, minus any whose
# subject starts `chore(release)`.
#   miss     some LATER non-merge commit changes a file the pre-drain diff also changes. The proposed
#            expected file is the overlapping file the most later commits changed (ties: the first in
#            byte order); `--file` overrides it with any file of the pre-drain diff.
#   control  NO later commit at all (merges included), and no revert of the PR on the base branch (a commit whose
#            message says `This reverts commit <merge sha>` or starts `Revert` and names `#<N>`).
# Paths the stager keeps out of every sandbox (the suite dir and docs/evidence/phase45-reviewer-*) are
# never proposed as an expected file. This is a heuristic: the builder only PROPOSES, and the owner confirms
# each case. `later` in the list makes a noisy candidate (dozens of base-merge commits) visible.
#
# MODES
#   --list        prints a markdown table of every candidate (kind, pr, merge, base, pre-drain head, later
#                 commit count, overlapping files, expected file, ledger note), newest merge first, then a
#                 `candidates:` tally. `--since` is passed to `git log --since`. Writes nothing.
#   --pr <N>      prints `base:`, `pre_drain_head:` and `expected: {file: <path>, severity_floor: <floor>}`
#                 (with --control: `expected: none (control)`) plus the case id it would write, then
#                 `dry run — nothing written; re-run with --confirm`. Writes NOTHING (no temp file either).
#   … --confirm   writes exactly ONE case dir, loomwright/evals/phase45-reviewer/<NN>-<kind>-pr<N>/
#                 (case.env with PR= / BASE_SHA= / HEAD_SHA= only; case.yaml = the suite's
#                 case-template.yaml with only its name, description and tags lines filled in; a one-line
#                 scaffold.sh that runs lib/stage-case.sh), and appends exactly ONE row to the repo-root
#                 docs/evidence/phase45-reviewer-corpus.tsv, creating it with its header line if absent.
#                 The expected file and floor go ONLY into that table, never into the case dir.
# REFUSES (exit 1, nothing written): the base branch does not resolve; no such merge on it; no pre-drain head; base or pre-drain head not a
# commit; a miss with no overlapping later change (and no --file), or a --file outside the pre-drain diff; a
# --control that has later commits or was reverted; an existing case dir or corpus row for the PR; a corpus
# table whose header is not the expected one; a template whose three placeholder lines are not each present
# exactly once. Exit 2 = usage error.
#
# The repo is found from BASH_SOURCE (this file is <repo>/loomwright/scripts/). The base branch comes from the
# sibling resolve-base-branch.sh --repo <repo> (the ONE resolver; `main` for this repo) and is read as
# origin/<base> when that ref exists, else the local <base>; an unresolved or invalid base fails closed with the
# resolver's status token. bash 3.2 + BSD userland + git; jq only for the optional ledger note.
# Self-test: loomwright/scripts/test-build-reviewer-replay-case.sh.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUITE="$REPO/loomwright/evals/phase45-reviewer"
TEMPLATE="$SUITE/case-template.yaml"
CORPUS="$REPO/docs/evidence/phase45-reviewer-corpus.tsv"
TAB="$(printf '\t')"
HEADER="case_id${TAB}pr${TAB}kind${TAB}expected_file${TAB}severity_floor"
FIX_SUBJECT_ERE='^fix: address review feedback \(iteration [0-9]+\)$'
RELEASE_ERE='^chore\(release\)'
KEEP_OUT_ERE='^(loomwright/evals/phase45-reviewer/|docs/evidence/phase45-reviewer-)'

usage() {
  { echo "usage:"; sed -n '5,6p' "${BASH_SOURCE[0]}" | sed 's/^# */  /'; } >&2
  exit 2
}
die() { echo "build-reviewer-replay-case: $1" >&2; exit 1; }
G() { git -C "$REPO" -c color.ui=never -c diff.noprefix=false "$@"; }

MODE=""; PR=""; FLOOR="HIGH"; FILE=""; KIND="miss"; SINCE=""
CONFIRM=0
LEDGER="$REPO/.supervisor/postmortem/results.jsonl"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --list) [ "$MODE" != pr ] || usage; MODE=list; shift ;;
    --pr) [ "$#" -ge 2 ] && [ "$MODE" != list ] || usage; MODE=pr; PR="$2"; shift 2 ;;
    --floor) [ "$#" -ge 2 ] || usage; FLOOR="$2"; shift 2 ;;
    --file) [ "$#" -ge 2 ] || usage; FILE="$2"; shift 2 ;;
    --control) KIND=control; shift ;;
    --confirm) CONFIRM=1; shift ;;
    --since) [ "$#" -ge 2 ] || usage; SINCE="$2"; shift 2 ;;
    --ledger) [ "$#" -ge 2 ] || usage; LEDGER="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "build-reviewer-replay-case: unknown argument: $1" >&2; usage ;;
  esac
done
[ -n "$MODE" ] || usage
G rev-parse --git-dir >/dev/null 2>&1 || die "$REPO is not a git repository"
# MAIN — the base-branch ref every candidate is read from. Resolver contract: success = one stdout line and an
# empty stderr; failure = empty stdout and the status token as stderr's first line, so one 2>&1 capture is enough
# (and a dry run stays write-free: no temp file).
RBB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resolve-base-branch.sh"
[ -f "$RBB" ] || die "the base-branch resolver $RBB is missing"
BASE_BRANCH="$(bash "$RBB" --repo "$REPO" 2>&1)" \
  || die "cannot resolve the base branch: $(printf '%s\n' "$BASE_BRANCH" | head -n 1)"
if G rev-parse --verify -q "refs/remotes/origin/$BASE_BRANCH^{commit}" >/dev/null; then MAIN="origin/$BASE_BRANCH"
elif G rev-parse --verify -q "refs/heads/$BASE_BRANCH^{commit}" >/dev/null; then MAIN="$BASE_BRANCH"
else die "the base branch '$BASE_BRANCH' resolves to no commit (neither origin/$BASE_BRANCH nor $BASE_BRANCH) in $REPO"; fi

# ---- per-merge analysis -------------------------------------------------------------------------------------
# analyse <merge sha> — sets PRE, BASE, LATER (count, merges included), PRE_FILES, OVERLAP ("<n> <path>" lines,
# most-touched first) and EXPECTED. Returns 1 when the PR has no pre-drain head.
analyse() {
  local m="$1" c s f
  PRE=""; BASE=""; LATER=0; PRE_FILES=""; OVERLAP=""; EXPECTED=""
  while IFS="$TAB" read -r c s; do
    if grep -qE "$FIX_SUBJECT_ERE" <<<"$s"; then PRE="$c"; break; fi
  done <<EOF
$(G log --topo-order --format="%H${TAB}%s" "$m^1..$m^2")
EOF
  [ -n "$PRE" ] || return 1
  BASE="$(G merge-base "$m^1" "$PRE")" || return 1
  PRE_FILES="$(G diff --name-only --no-renames "$BASE" "$PRE" | grep -vE "$KEEP_OUT_ERE")"
  local later_list touched=""
  later_list="$(G log --format="%H${TAB}%P${TAB}%s" "$m^2" "^$PRE" "^$m^1")"
  while IFS="$TAB" read -r c p s; do
    [ -n "$c" ] || continue
    grep -qE "$RELEASE_ERE" <<<"$s" && continue
    LATER=$((LATER + 1))
    case "$p" in *" "*) continue ;; esac            # a merge (base-merge) counts as later, never as a fix
    touched="$touched$(G diff-tree --no-commit-id --name-only -r --no-renames "$c")
"
  done <<EOF
$later_list
EOF
  if [ -n "$PRE_FILES" ] && [ -n "$touched" ]; then
    OVERLAP="$(printf '%s' "$touched" | grep -vE '^$' | grep -xF -- "$PRE_FILES" | env LC_ALL=C sort | uniq -c \
      | awk '{ n = $1; sub(/^ *[0-9]+ /, ""); print n " " $0 }' | env LC_ALL=C sort -k1,1nr -s)"
  fi
  [ -z "$OVERLAP" ] || EXPECTED="$(printf '%s\n' "$OVERLAP" | head -n 1 | sed 's/^[0-9]* //')"
  return 0
}

# reverted <merge sha> <pr> — 0 when the base branch carries a revert of this PR after its merge. The log reaches
# grep through a process substitution, never a pipe: grep -q exits on its first match, and under pipefail the
# producer's SIGPIPE/EPIPE would otherwise decide the verdict (test-no-pipefail-grep-q.sh rule 3).
reverted() {
  grep -qE "This reverts commit $1|^Revert .*#$2([^0-9]|$)" < <(G log --format='%B' "$1..$MAIN")
}

# ledger_note <pr> — `shm=<self_heal_misses>` from the newest ledger row for this PR, `-` when none / no jq
LEDGER_MAP=""
load_ledger() {
  [ -f "$LEDGER" ] && command -v jq >/dev/null 2>&1 || return 0
  local origin="" slug=""
  origin="$(G remote get-url origin 2>/dev/null)"
  slug="$(printf '%s\n' "$origin" | sed -E 's#\.git$##; s#^.*[:/]([^/:]+/[^/]+)$#\1#')"
  LEDGER_MAP="$(jq -r --arg r "$slug" 'select((.number|type) == "number")
      | select($r == "" or .repo == null or .repo == $r) | "\(.number)\t\(.self_heal_misses // "?")"' "$LEDGER" 2>/dev/null)"
}
ledger_note() {
  local v
  v="$(printf '%s\n' "$LEDGER_MAP" | awk -F '\t' -v n="$1" '$1 == n { v = $2 } END { print v }')"
  if [ -n "$v" ]; then printf 'shm=%s' "$v"; else printf -- '-'; fi
}

short() { printf '%s' "$1" | cut -c1-12; }

# ---- --list -------------------------------------------------------------------------------------------------
if [ "$MODE" = list ]; then
  [ -z "$PR" ] && [ "$KIND" = miss ] && [ "$CONFIRM" -eq 0 ] && [ -z "$FILE" ] || die "--list takes only --since and --ledger"
  load_ledger
  echo "candidates on $MAIN ($(short "$(G rev-parse "$MAIN")"))${SINCE:+ since $SINCE} — proposals only; the owner confirms each case"
  echo
  echo "| kind | pr | merge | base | pre_drain_head | later | overlap | expected_file | ledger |"
  echo "|---|---|---|---|---|---|---|---|---|"
  scanned=0; nmiss=0; nctl=0
  merges="$(G log --first-parent --merges ${SINCE:+--since="$SINCE"} --format="%H${TAB}%s" "$MAIN")"
  while IFS="$TAB" read -r m s; do
    [ -n "$m" ] || continue
    n="$(printf '%s\n' "$s" | sed -nE 's/^Merge pull request #([0-9]+) from .*/\1/p')"
    [ -n "$n" ] || continue
    scanned=$((scanned + 1))
    analyse "$m" || continue
    if [ -n "$EXPECTED" ]; then
      ov="$(printf '%s\n' "$OVERLAP" | wc -l | tr -d ' ')"
      printf '| miss | %s | %s | %s | %s | %s | %s | `%s` | %s |\n' "$n" "$(short "$m")" "$(short "$BASE")" "$(short "$PRE")" \
        "$LATER" "$ov" "$EXPECTED" "$(ledger_note "$n")"
      nmiss=$((nmiss + 1))
    elif [ "$LATER" -eq 0 ] && ! reverted "$m" "$n"; then
      printf '| control | %s | %s | %s | %s | 0 | 0 | — | %s |\n' "$n" "$(short "$m")" "$(short "$BASE")" "$(short "$PRE")" \
        "$(ledger_note "$n")"
      nctl=$((nctl + 1))
    fi
  done <<EOF
$merges
EOF
  echo
  echo "candidates: miss=$nmiss control=$nctl (of $scanned PR merges scanned)"
  exit 0
fi

# ---- --pr <N> -----------------------------------------------------------------------------------------------
# a case pattern tests the WHOLE value; a line-oriented grep would pass '101<newline>x' on its first line
case "$PR" in ''|*[!0-9]*) die "--pr needs a PR number, got '$PR'" ;; esac
case "$FLOOR" in BLOCKING|HIGH|MEDIUM|LOW) ;; *) die "--floor must be BLOCKING, HIGH, MEDIUM or LOW, got '$FLOOR'" ;; esac
[ "$KIND" = miss ] || [ -z "$FILE" ] || die "--file applies to a miss case, not a --control"
[ -z "$SINCE" ] || die "--since applies to --list only"
NL="$(printf '\nx')"; NL="${NL%x}"
case "$FILE" in *"$TAB"*|*"$NL"*) die "--file must not contain a tab or a newline" ;; esac

MERGE="$(G log --first-parent --merges --format="%H${TAB}%s" "$MAIN" \
  | awk -F '\t' -v want="Merge pull request #$PR from " 'index($2, want) == 1 { print $1; exit }')"
[ -n "$MERGE" ] || die "PR #$PR: no merge commit 'Merge pull request #$PR from …' on $MAIN (only first-parent merges of the base branch are considered)"
G cat-file -e "$MERGE^2^{commit}" 2>/dev/null || die "PR #$PR: merge $MERGE has no reachable second parent"
analyse "$MERGE" || die "PR #$PR: no pre-drain head (no 'fix: address review feedback (iteration N)' commit) — not a Phase 4.5 PR"
for v in "$BASE" "$PRE"; do
  G cat-file -e "$v^{commit}" 2>/dev/null || die "PR #$PR: $v is not a reachable commit"
done

if [ "$KIND" = control ]; then
  [ "$LATER" -eq 0 ] || die "PR #$PR is not a clean control: $LATER commit(s) after the pre-drain head besides release"
  ! reverted "$MERGE" "$PR" || die "PR #$PR is not a clean control: $MAIN carries a revert of it"
else
  if [ -n "$FILE" ]; then
    grep -qxF -- "$FILE" <<<"$PRE_FILES" || die "PR #$PR: --file $FILE is not in the pre-drain diff ($(short "$BASE")..$(short "$PRE"))"
    EXPECTED="$FILE"
  fi
  [ -n "$EXPECTED" ] || die "PR #$PR is not a miss candidate: no later commit changes a file of the pre-drain diff"
fi

# the case id: the next free two-digit ordinal; one case per PR
shopt -s nullglob
last=0
for d in "$SUITE"/[0-9][0-9]-*; do
  [ -d "$d" ] || continue
  b="$(basename "$d")"
  case "$b" in *-pr"$PR") die "a case for PR #$PR already exists: $d" ;; esac
  o="$(printf '%s' "$b" | cut -c1-2 | sed 's/^0//')"
  [ "$o" -gt "$last" ] && last="$o"
done
shopt -u nullglob
CASE_ID="$(printf '%02d-%s-pr%s' "$((last + 1))" "$KIND" "$PR")"
CASE_DIR="$SUITE/$CASE_ID"
if [ -f "$CORPUS" ]; then
  [ "$(head -n 1 "$CORPUS")" = "$HEADER" ] || die "$CORPUS: the first line is not the corpus header"
  awk -F '\t' -v n="$PR" 'NR > 1 && $2 == n { found = 1 } END { exit !found }' "$CORPUS" \
    && die "$CORPUS already has a row for PR #$PR"
fi

echo "pr: $PR"
echo "merge: $MERGE"
echo "base: $BASE"
echo "pre_drain_head: $PRE"
echo "later_commits: $LATER"
echo "case: $CASE_ID"
if [ "$KIND" = control ]; then echo "expected: none (control)"
else echo "expected: {file: $EXPECTED, severity_floor: $FLOOR}"; fi

if [ "$CONFIRM" -ne 1 ]; then
  echo "dry run — nothing written; re-run with --confirm"
  exit 0
fi

# ---- --confirm: one case dir + one corpus row ---------------------------------------------------------------
[ -f "$TEMPLATE" ] || die "$TEMPLATE missing"
for l in 'name: CASE_ID' 'tags: [CASE_KIND]'; do
  [ "$(grep -cxF -- "$l" "$TEMPLATE")" -eq 1 ] || die "$TEMPLATE: the line '$l' is not present exactly once"
done
[ "$(grep -cE '^[[:space:]]+CASE_DESCRIPTION$' "$TEMPLATE")" -eq 1 ] || die "$TEMPLATE: the CASE_DESCRIPTION line is not present exactly once"
if [ "$KIND" = control ]; then
  DESC="Clean control: PR #$PR (merge $(short "$MERGE")) was merged with no commit after its pre-drain head $(short "$PRE") besides release, and was never reverted."
else
  DESC="Miss case: replays PR #$PR's pre-drain diff (merge $(short "$MERGE"), pre-drain head $(short "$PRE")). The expectation lives only in the repo-root corpus table."
fi
YAML="$(awk -v id="$CASE_ID" -v desc="$DESC" -v kind="$KIND" '
  $0 == "name: CASE_ID"        { print "name: " id; next }
  $0 == "tags: [CASE_KIND]"    { print "tags: [" kind "]"; next }
  /^[[:space:]]+CASE_DESCRIPTION$/ { sub(/CASE_DESCRIPTION$/, desc); print; next }
  { print }' "$TEMPLATE")" || die "cannot render $TEMPLATE"
[ "$(printf '%s\n' "$YAML" | awk '/^execution:/ { f = 1 } f')" = "$(awk '/^execution:/ { f = 1 } f' "$TEMPLATE")" ] \
  || die "the rendered case.yaml differs from the template from execution: on"

mkdir -p "$(dirname "$CORPUS")" || die "cannot create $(dirname "$CORPUS")"
mkdir "$CASE_DIR" 2>/dev/null || die "cannot create $CASE_DIR (it exists, or the suite dir is missing)"
cleanup_case() { rm -rf "$CASE_DIR"; die "$1"; }
printf 'PR=%s\nBASE_SHA=%s\nHEAD_SHA=%s\n' "$PR" "$BASE" "$PRE" > "$CASE_DIR/case.env" || cleanup_case "cannot write case.env"
printf '%s\n' "$YAML" > "$CASE_DIR/case.yaml" || cleanup_case "cannot write case.yaml"
{
  echo '#!/usr/bin/env bash'
  echo "# $CASE_ID — stages PR #$PR's pre-drain diff into the eval sandbox (cwd) through the shared stager"
  echo 'exec bash "$(dirname "${BASH_SOURCE[0]}")/../lib/stage-case.sh" "$(dirname "${BASH_SOURCE[0]}")"'
} > "$CASE_DIR/scaffold.sh" && chmod 755 "$CASE_DIR/scaffold.sh" || cleanup_case "cannot write scaffold.sh"
if [ ! -f "$CORPUS" ]; then printf '%s\n' "$HEADER" > "$CORPUS" || cleanup_case "cannot create $CORPUS"; fi
if [ "$KIND" = control ]; then row="$CASE_ID${TAB}$PR${TAB}control${TAB}${TAB}"
else row="$CASE_ID${TAB}$PR${TAB}miss${TAB}$EXPECTED${TAB}$FLOOR"; fi
# an unterminated last line (a hand edit) would glue the new row onto it: terminate it first, never a blank line
if [ -n "$(tail -c 1 "$CORPUS")" ]; then printf '\n' >> "$CORPUS" || cleanup_case "cannot append to $CORPUS"; fi
printf '%s\n' "$row" >> "$CORPUS" || cleanup_case "cannot append to $CORPUS"
echo "wrote: ${CASE_DIR#"$REPO"/}/ (case.env, case.yaml, scaffold.sh)"
echo "appended: ${CORPUS#"$REPO"/} row $CASE_ID"
