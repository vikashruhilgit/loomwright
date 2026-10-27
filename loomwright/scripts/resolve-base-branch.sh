#!/usr/bin/env bash
# resolve-base-branch.sh — the ONE place the base (integration) branch is resolved.
#
# Every stage that branches from, targets or diffs against the base — Supervisor, the /automate
# lanes, waves and trail PRs, verify, reconcile, resume, self-heal — asks this script instead of
# re-deriving it, so a repo whose integration branch is not the GitHub default (for example
# `development`) gets the same answer everywhere. There is deliberately NO hardcoded fallback
# branch: when nothing below answers, the script fails CLOSED with `base_branch_unresolved`
# rather than guessing.
#
# PRECEDENCE (first step that yields a value wins):
#   1. flag        --flag <value>, when non-empty (e.g. /autonomous --base-branch for stacked runs)
#   2. brief       --brief <path>: the `- **Base Branch:** <value>` line under the brief's
#                  `## Configuration` section (backticks stripped, first word), when present
#   3. config      <repo>/.supervisor/config.json `.base_branch` (a string; absent key or JSON
#                  null is "not configured"; written by `/setup base-branch set <branch>`)
#   4. origin-head refs/remotes/origin/HEAD's target (the `origin/` prefix stripped). When it is
#                  unset or dangling and an `origin` remote exists, ONE
#                  `git remote set-head origin -a` is attempted and origin/HEAD re-read
#   5. gh          `gh repo view --json defaultBranchRef` run in <repo>, only when `gh` is on PATH
#   otherwise      fail: `base_branch_unresolved`
#
# VALIDATION (fail CLOSED for explicit values): a value from steps 1–3 must pass
# `git check-ref-format --branch` unchanged (so `@{-N}` shorthands and names starting with `-`
# are refused). An invalid explicit value stops with `base_branch_invalid:<flag|brief|config>` and
# NEVER falls through to a lower step — an operator's explicit choice is never silently replaced.
# The same holds for an explicit source that cannot be read: an unreadable --brief path, an
# unparseable / non-object config.json, a non-string `.base_branch`, or jq missing while a
# config.json exists. Values DISCOVERED by steps 4–5 that fail validation are skipped (the next
# step is tried).
#
# USAGE
#   resolve-base-branch.sh [--flag <value>] [--brief <path>] [--repo <dir>] [--explain]
#     --flag <value>   explicit base; empty means "not given"
#     --brief <path>   job brief to read `Base Branch:` from; empty means "not given"
#     --repo <dir>     repository to resolve in; the config is read from
#                      <dir>/.supervisor/config.json. Default: the git top-level of the current
#                      directory (the current directory itself when it is not inside a work tree)
#     --explain        print `<branch> (source: <step>)` instead of the bare branch, where <step>
#                      is one of flag | brief | config | origin-head | gh (the form
#                      `/setup base-branch status` shows)
#     -h, --help       print this header
#
# OUTPUT CONTRACT (stable — consumers rely on it)
#   success  stdout: exactly one line, the bare branch name (never an `origin/` prefix added by
#            this script), or the --explain form; stderr: empty; exit 0.
#   failure  stdout: EMPTY. stderr: the FIRST line is exactly the status token, a second line
#            `resolve-base-branch: <detail>` explains it:
#              base_branch_unresolved              exit 1 — no step yielded a valid branch
#              base_branch_invalid:flag|brief|config  exit 2 — an explicit value was refused
#            A usage error (unknown argument, missing value, --repo not a directory) exits 2
#            with a `resolve-base-branch: usage …` line and no status token.
#   A consumer captures stdout for the branch and treats any non-zero exit as "no base" — a
#   correctness consumer stops with the status token, a fail-SAFE reader degrades.
#
# Side effect: step 4 may run `git remote set-head origin -a` (it writes only
# refs/remotes/origin/HEAD, and its output is discarded so stdout stays one line).
# Bash 3.2 / BSD-safe; `set -u` only. jq via "${JQ:-jq}" (test seam).

set -u

JQ_BIN="${JQ:-jq}"
ME="resolve-base-branch"

FLAG=""
BRIEF=""
REPO=""
REPO_GIVEN=0
EXPLAIN=0

usage_die() {
  printf '%s: usage error: %s\n' "$ME" "$1" >&2
  printf '%s: usage: resolve-base-branch.sh [--flag <value>] [--brief <path>] [--repo <dir>] [--explain]\n' "$ME" >&2
  exit 2
}

# fail_invalid <flag|brief|config> <detail> — an explicit value was refused; never falls through.
fail_invalid() {
  printf 'base_branch_invalid:%s\n' "$1" >&2
  printf '%s: %s\n' "$ME" "$2" >&2
  exit 2
}

fail_unresolved() {
  printf 'base_branch_unresolved\n' >&2
  printf '%s: no flag, brief, .supervisor/config.json .base_branch, origin/HEAD or gh default branch — set one with `/setup base-branch set <branch>` or `git remote set-head origin <branch>`\n' "$ME" >&2
  exit 1
}

# emit <branch> <source> — the single success exit.
emit() {
  if [ "$EXPLAIN" -eq 1 ]; then
    printf '%s (source: %s)\n' "$1" "$2"
  else
    printf '%s\n' "$1"
  fi
  exit 0
}

# valid_branch <value> — true when git accepts <value> as a branch name AS GIVEN (check-ref-format
# --branch expands `@{-N}`, so its output must equal the input).
valid_branch() {
  local out
  case "$1" in ''|-*) return 1 ;; esac
  out="$(git check-ref-format --branch "$1" 2>/dev/null)" || return 1
  [ "$out" = "$1" ]
}

# brief_value <brief> — the `- **Base Branch:**` value under `## Configuration`, or nothing.
brief_value() {
  RBB_F='- **Base Branch:**' awk 'BEGIN { f = ENVIRON["RBB_F"] }
    { sub(/\r$/, "") }
    /^## / { s = ($0 == "## Configuration"); next }
    s && index($0, f) == 1 { v = substr($0, length(f) + 1); gsub(/`/, "", v); sub(/^[ \t]+/, "", v); sub(/[ \t].*/, "", v); print v; exit }' "$1" 2>/dev/null
}

step_flag() {
  [ -n "$FLAG" ] || return 0
  valid_branch "$FLAG" || fail_invalid flag "--flag '$FLAG' is not a valid branch name"
  emit "$FLAG" flag
}

step_brief() {
  [ -n "$BRIEF" ] || return 0
  { [ -f "$BRIEF" ] && [ -r "$BRIEF" ]; } || fail_invalid brief "cannot read brief: $BRIEF"
  local v
  v="$(brief_value "$BRIEF")"
  [ -n "$v" ] || return 0
  valid_branch "$v" || fail_invalid brief "$BRIEF Base Branch '$v' is not a valid branch name"
  emit "$v" brief
}

step_config() {
  local cfg="$REPO/.supervisor/config.json" kind v
  [ -f "$cfg" ] || return 0
  command -v "$JQ_BIN" >/dev/null 2>&1 || fail_invalid config "jq not found; cannot read $cfg"
  # Slurped so the WHOLE file must parse as exactly one object (trailing junk is refused).
  kind="$("$JQ_BIN" -rse 'if length == 1 and (.[0] | type) == "object"
      then (.[0].base_branch | if . == null then "null" elif type == "string" then "s:" + . else "bad" end)
      else "notobject" end' "$cfg" 2>/dev/null)" || fail_invalid config "$cfg is not valid JSON"
  case "$kind" in
    null) return 0 ;;
    s:*)
      v="${kind#s:}"
      valid_branch "$v" || fail_invalid config "$cfg .base_branch '$v' is not a valid branch name"
      emit "$v" config ;;
    notobject) fail_invalid config "$cfg is not a single JSON object" ;;
    *) fail_invalid config "$cfg .base_branch is not a string" ;;
  esac
}

# origin_head_branch — origin/HEAD's branch when it is set AND points at an existing ref.
origin_head_branch() {
  local r
  r="$(git -C "$REPO" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)" || return 1
  git -C "$REPO" rev-parse -q --verify 'refs/remotes/origin/HEAD^{commit}' >/dev/null 2>&1 || return 1
  r="${r#origin/}"
  valid_branch "$r" || return 1
  printf '%s' "$r"
}

step_origin_head() {
  local b
  git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || return 0
  if b="$(origin_head_branch)"; then emit "$b" origin-head; fi
  git -C "$REPO" remote get-url origin >/dev/null 2>&1 || return 0
  # Re-read even when set-head failed: a concurrent resolver in the same repo may hold the ref
  # lock and have just set it.
  GIT_TERMINAL_PROMPT=0 git -C "$REPO" remote set-head origin -a >/dev/null 2>&1
  if b="$(origin_head_branch)"; then emit "$b" origin-head; fi
}

step_gh() {
  local b
  command -v gh >/dev/null 2>&1 || return 0
  b="$(cd "$REPO" 2>/dev/null && GH_PROMPT_DISABLED=1 gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null)" || return 0
  valid_branch "$b" || return 0
  emit "$b" gh
}

while [ $# -gt 0 ]; do
  case "$1" in
    --flag) [ $# -ge 2 ] || usage_die "--flag needs a value"; FLAG="$2"; shift 2 ;;
    --brief) [ $# -ge 2 ] || usage_die "--brief needs a value"; BRIEF="$2"; shift 2 ;;
    --repo) [ $# -ge 2 ] || usage_die "--repo needs a value"; REPO="$2"; REPO_GIVEN=1; shift 2 ;;
    --explain) EXPLAIN=1; shift ;;
    -h|--help) sed -n '2,/^$/{s/^# \{0,1\}//;p;}' "$0"; exit 0 ;;
    *) usage_die "unknown argument: $1" ;;
  esac
done

if [ "$REPO_GIVEN" -eq 1 ]; then
  [ -n "$REPO" ] && [ -d "$REPO" ] || usage_die "--repo '$REPO' is not a directory"
else
  REPO="$(git rev-parse --show-toplevel 2>/dev/null)" || REPO=""
  [ -n "$REPO" ] || REPO="$(pwd)"
fi

step_flag
step_brief
step_config
step_origin_head
step_gh
fail_unresolved
