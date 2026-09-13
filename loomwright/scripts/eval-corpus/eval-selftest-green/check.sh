#!/usr/bin/env bash
# check.sh — eval-selftest-green eval task.
# Dogfoods the eval harness's own self-test (the "self-test must stay passing"
# shape): a deliberately-broken run-eval.sh would be caught by test-run-eval.sh.
# Pass iff that self-test passes.
#
# Recursion-safety: test-run-eval.sh exercises run-eval.sh against temp-fixture
# corpora (EVAL_CORPUS_DIR override), NOT the real corpus — so running this under
# run-eval.sh over the real corpus does not recurse. We deliberately invoke the
# self-test here, never run-eval.sh against the real corpus.
#
# Deterministic (the self-test is isolated and network-free) and read-only.
set -uo pipefail

# Project root — the repo this check VERIFIES. Precedence: $EVAL_PROJECT_ROOT (exported by
# run-eval.sh / run-ground-truth.sh = the CALLER's project), else the git repo enclosing this task
# dir (direct `bash check.sh` on a dev checkout). NEVER derive it from this file's location alone: on
# a marketplace install the corpus lives under ~/.claude/plugins/cache/..., outside any git repo, and
# the caller's project is the only thing worth verifying (eval-corpus/README.md §"Project root").
repo_root="${EVAL_PROJECT_ROOT:-}"
if [ -z "$repo_root" ]; then
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "eval-selftest-green: EVAL_PROJECT_ROOT unset and not inside a git repo" >&2
    exit 1
  }
fi
# Maintainer-side task: the project must BE the loomwright repo (it dogfoods a repo-local gate).
[ -f "$repo_root/loomwright/scripts/test-run-eval.sh" ] || {
  echo "eval-selftest-green: $repo_root/loomwright/scripts/test-run-eval.sh missing — maintainer-side task; the project root must be the loomwright repo" >&2
  exit 1
}

# Run from the repo root so the self-test resolves its paths deterministically.
cd "$repo_root" && bash loomwright/scripts/test-run-eval.sh
exit $?
