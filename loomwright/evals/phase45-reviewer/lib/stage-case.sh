#!/usr/bin/env bash
# stage-case.sh — the phase45-reviewer suite's ONE shared scaffold.
#
#   bash stage-case.sh <case dir>
#
# Run by each case's scaffold.sh with the eval sandbox's working directory as cwd (`claude plugin eval
# --scaffold` runs it there, as the operator):
#     exec bash "$(dirname "${BASH_SOURCE[0]}")/../lib/stage-case.sh" "$(dirname "${BASH_SOURCE[0]}")"
# The case id is the case dir's basename. <case dir>/case.env holds ONLY the staging inputs, one KEY=value per
# line: PR=<number>, BASE_SHA=<sha>, HEAD_SHA=<sha> (the pre-drain head). It is read, never sourced.
#
# The source repo is found from BASH_SOURCE (this file is <repo>/loomwright/evals/phase45-reviewer/lib/), the
# way coordinator-model's stage-golden.sh finds its plugin. NOTHING is written into the source repo; the
# sandbox gets:
#   .eval/case-id, .eval/base_sha, .eval/head_sha   always (lib/summarize.sh maps a kept sandbox by case-id)
#   .eval/unstageable                               when BASE_SHA or HEAD_SHA is not a commit of the source
#                                                   repo (`git cat-file -e <sha>^{commit}`); then exit 0 and
#                                                   nothing else is staged — the case grades UNSTAGEABLE
#   .eval/review-prompt.md                          the Phase 4.5 round-1 prompt, rendered by render-prompt.sh
#                                                   from the plugin under test (never copied into a case)
#   a scratch git repo in cwd                       root commit = `git archive` of BASE_SHA on branch `replay`,
#                                                   refs/remotes/origin/main = that commit, then ONE commit with
#                                                   `git diff --binary BASE_SHA HEAD_SHA` applied — so the
#                                                   reviewer's `git diff "origin/main...HEAD"` is exactly the
#                                                   pre-drain diff. `.eval/` is in .git/info/exclude.
# The sandbox NEVER gets an expectation: no corpus table, no expected file, no severity floor. Grading happens
# after the run, outside the sandbox (lib/summarize.sh + lib/grade.sh). Because a BASE_SHA newer than this
# suite would carry the suite and its table, both the archive and the replayed diff EXCLUDE (pathspec
# `:(exclude)`) every path in KEEP_OUT below: the suite dir and docs/evidence/phase45-reviewer-* (the corpus
# table and the replay evidence). A replayed PR's changes to those paths are therefore not replayed.
#
# Exit codes: 0 staged, or marked unstageable; 1 a usage / case.env / render / git failure (named on stderr) —
# any failure after the reachability check is a hard error, never `unstageable`. bash 3.2 + BSD userland + git.
set -uo pipefail

CASE_DIR="${1:-}"
die() { echo "stage-case: $1" >&2; exit 1; }
[ -n "$CASE_DIR" ] && [ -d "$CASE_DIR" ] || die "usage: stage-case.sh <case dir>"
CASE_DIR="$(cd "$CASE_DIR" && pwd)"
CASE_ID="$(basename "$CASE_DIR")"
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$LIB/../../.." && pwd)"
REPO="$(cd "$PLUGIN/.." && pwd)"
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || die "source repo $REPO is not a git repository"

W="$(pwd -P)"; E="$W/.eval"
case "$W/" in "$(cd "$REPO" && pwd -P)/"*) die "refusing to stage inside the source repo ($W)" ;; esac
[ ! -e "$W/.git" ] || die "refusing to stage over an existing git repo in $W"

# ---- the staging inputs (case.env, read — never sourced) ---------------------------------------------------
[ -f "$CASE_DIR/case.env" ] || die "$CASE_DIR/case.env missing"
env_val() { sed -n "s/^$1=//p" "$CASE_DIR/case.env" | tr -d '\r' | tail -n 1; }
PR="$(env_val PR)"; BASE_SHA="$(env_val BASE_SHA)"; HEAD_SHA="$(env_val HEAD_SHA)"
printf '%s\n' "$PR" | grep -qE '^[0-9]+$' || die "$CASE_ID: case.env PR= is not a number"
for v in "$BASE_SHA" "$HEAD_SHA"; do
  printf '%s\n' "$v" | grep -qE '^[0-9a-f]{7,40}$' || die "$CASE_ID: case.env BASE_SHA= / HEAD_SHA= is not a hex sha ('$v')"
done

mkdir -p "$E" || die "cannot create $E"
printf '%s\n' "$CASE_ID" > "$E/case-id" && printf '%s\n' "$BASE_SHA" > "$E/base_sha" && printf '%s\n' "$HEAD_SHA" > "$E/head_sha" \
  || die "cannot write $E"

# ---- reachability: an unreachable sha marks the case UNSTAGEABLE (exit 0), it never fails the run ----------
for v in "$BASE_SHA" "$HEAD_SHA"; do
  if ! git -C "$REPO" cat-file -e "$v^{commit}" 2>/dev/null; then
    printf 'unreachable: %s is not a commit of %s\n' "$v" "$REPO" > "$E/unstageable"
    echo "stage-case: $CASE_ID UNSTAGEABLE — $v is not a commit of the source repo" >&2
    exit 0
  fi
done

# ---- the prompt (from the plugin under test) ---------------------------------------------------------------
bash "$LIB/render-prompt.sh" "$PLUGIN" > "$E/review-prompt.md" || die "$CASE_ID: render-prompt.sh failed"

# ---- the scratch repo --------------------------------------------------------------------------------------
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=phase45-replay GIT_AUTHOR_EMAIL=phase45-replay@example.invalid \
  GIT_COMMITTER_NAME=phase45-replay GIT_COMMITTER_EMAIL=phase45-replay@example.invalid
# user config must not reshape the diff (noprefix, mnemonic prefixes, renames, external diff / textconv, colour)
SRC_GIT() { git -C "$REPO" -c diff.noprefix=false -c diff.mnemonicPrefix=false -c color.ui=never "$@"; }
G() { git -C "$W" -c core.autocrlf=false -c core.safecrlf=false -c commit.gpgSign=false "$@"; }
{ G init -q && G symbolic-ref HEAD refs/heads/replay; } >/dev/null 2>&1 || die "$CASE_ID: git init failed in $W"
{ mkdir -p "$W/.git/info" && printf '.eval/\n' >> "$W/.git/info/exclude"; } || die "$CASE_ID: cannot write .git/info/exclude"
KEEP_OUT=(':(exclude)loomwright/evals/phase45-reviewer' ':(exclude)docs/evidence/phase45-reviewer-*')
SRC_GIT archive --format=tar "$BASE_SHA" -- . "${KEEP_OUT[@]}" | tar -xf - -C "$W" || die "$CASE_ID: git archive $BASE_SHA failed"
{ G add -A && G commit -q --allow-empty -m "replay base: $BASE_SHA (PR #$PR)"; } >/dev/null 2>&1 \
  || die "$CASE_ID: base commit failed"
G update-ref refs/remotes/origin/main HEAD || die "$CASE_ID: cannot set refs/remotes/origin/main"
PATCH="$E/.replay.patch"
SRC_GIT diff --binary --full-index --no-renames --no-ext-diff --no-textconv "$BASE_SHA" "$HEAD_SHA" -- . "${KEEP_OUT[@]}" > "$PATCH" \
  || die "$CASE_ID: git diff $BASE_SHA $HEAD_SHA failed"
if [ -s "$PATCH" ]; then
  G apply --whitespace=nowarn "$PATCH" 2>"$E/.apply.err" || die "$CASE_ID: the pre-drain diff does not apply: $(head -n 3 "$E/.apply.err" | tr '\n' ' ')"
fi
rm -f "$PATCH" "$E/.apply.err"
{ G add -A && G commit -q --allow-empty -m "replay: pre-drain head $HEAD_SHA (PR #$PR)"; } >/dev/null 2>&1 \
  || die "$CASE_ID: replay commit failed"
echo "stage-case: $CASE_ID staged — origin/main = $BASE_SHA, replay = the diff to $HEAD_SHA" >&2
exit 0
