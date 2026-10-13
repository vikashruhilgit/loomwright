#!/usr/bin/env bash
# drain-gh-read.sh — the ONLY GitHub API surface the detached review drain may
# call. Every operation below is READ-ONLY BY CONSTRUCTION: the script builds
# the full `gh api` call itself (fixed endpoint, fixed GET method or a fixed
# GraphQL `query`), and the caller can supply only validated identifiers.
#
# ============================== CONTRACT (PIN) ================================
# WHY: the drain runs headless under `--permission-mode dontAsk` with a pinned
# `--allowedTools` list (dispatch-pr-review.sh build_allowed_tools). A
# permission rule matches the COMMAND TEXT, so a rule broad enough to let the
# drain read review threads — `Bash(gh api graphql:*)` — also allows
# `gh api graphql -f query='mutation{mergePullRequest(...)}'`, and any rule
# admitting `gh api repos/...` also admits `gh api -X PUT repos/.../pulls/N/merge`.
# A prompt injection in a PR comment on a public repo could use either to merge,
# bypassing the single sanctioned merge executor (CLAUDE.md §"Failure-Mode
# Invariants"). No allow/deny pattern can tell a query from a mutation, so the
# drain gets no raw `gh api` at all — only this script, whose rule names the
# operation, not the endpoint.
#
# USAGE:
#   drain-gh-read.sh issue-comments    <owner>/<repo> <pr_number>      [--jq <expr>]
#   drain-gh-read.sh review-threads    <owner>/<repo> <pr_number>      [--jq <expr>]
#   drain-gh-read.sh check-annotations <owner>/<repo> <check_run_id>   [--jq <expr>]
#   drain-gh-read.sh required-checks   <owner>/<repo> <base_branch>    [--jq <expr>]
#
# These are exactly the reads skills/review-heal/SKILL.md §U1 (b)/(c)/(d) and
# §U2 need; adding an operation means adding a READ here, never a write.
#
# OUTPUT: gh's JSON on stdout, unchanged (or filtered through gh's own --jq).
#
# EXIT: gh's own exit status. NOT fail-safe, on purpose — the drain treats a
# failed read as an UNKNOWN channel and must not claim READY on it (review-heal
# §U1 "PR issue comments" / §U2 fail CLOSED). A reader that exited 0 with empty
# output on failure would read as "no findings" to that gate. Bad arguments
# exit 2 without calling gh.
#
# TEST SEAM: GH=<path> overrides the gh binary (test-drain-gh-read.sh).

set -u

GH="${GH:-gh}"

usage() {
  printf 'usage: drain-gh-read.sh {issue-comments|review-threads|check-annotations|required-checks} <owner>/<repo> <id> [--jq <expr>]\n' >&2
  exit 2
}

[ "$#" -ge 3 ] || usage
op="$1"; slug="$2"; id="$3"; shift 3

jq_args=()
if [ "$#" -gt 0 ]; then
  [ "$#" -eq 2 ] && [ "$1" = "--jq" ] || usage
  jq_args=(--jq "$2")
fi

# Identifiers are validated so a crafted value cannot smuggle extra gh flags
# (`-X PUT`, `-f ...`) or path segments into the fixed endpoint.
case "$slug" in
  */*/*|-*|"") usage ;;
esac
[[ "$slug" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || usage

owner="${slug%%/*}"; repo="${slug#*/}"

case "$op" in
  issue-comments|review-threads|check-annotations)
    [[ "$id" =~ ^[0-9]+$ ]] || usage ;;
  required-checks)
    # A git ref name: no leading dash, no whitespace, no `..`.
    case "$id" in -*|*..*|"") usage ;; esac
    [[ "$id" =~ ^[A-Za-z0-9._/-]+$ ]] || usage ;;
  *) usage ;;
esac

case "$op" in
  issue-comments)
    exec "$GH" api --method GET "repos/$owner/$repo/issues/$id/comments?per_page=100" ${jq_args[@]+"${jq_args[@]}"} ;;
  check-annotations)
    exec "$GH" api --method GET "repos/$owner/$repo/check-runs/$id/annotations" ${jq_args[@]+"${jq_args[@]}"} ;;
  required-checks)
    exec "$GH" api --method GET "repos/$owner/$repo/branches/$id/protection/required_status_checks" ${jq_args[@]+"${jq_args[@]}"} ;;
  review-threads)
    # A fixed `query` document — never a caller-supplied one, so this can never
    # carry a mutation.
    exec "$GH" api graphql -f query='
  query($owner:String!,$repo:String!,$number:Int!){
    repository(owner:$owner,name:$repo){
      pullRequest(number:$number){
        reviewThreads(first:100){
          pageInfo{ hasNextPage }
          nodes{
            isResolved
            comments(first:1){ nodes{ author{ login __typename } body } }
          }
        }
      }
    }
  }' -f owner="$owner" -f repo="$repo" -F number="$id" ${jq_args[@]+"${jq_args[@]}"} ;;
esac
