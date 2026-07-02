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

# The runner cd's into this task dir first, so resolve the repo root robustly.
repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "eval-selftest-green: not inside a git repo" >&2
  exit 1
}

# Run from the repo root so the self-test resolves its paths deterministically.
cd "$repo_root" && bash loomwright/scripts/test-run-eval.sh
exit $?
