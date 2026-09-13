#!/usr/bin/env bash
# check.sh — doc-currency-green eval task.
# Dogfoods the repo-root doc-currency CI gate: the plugin's doc/count claims
# must stay consistent with the authoritative sources. Pass iff the gate is green.
# Deterministic (same repo state => same result) and read-only.
set -uo pipefail

# Project root — the repo this check VERIFIES. Precedence: $EVAL_PROJECT_ROOT (exported by
# run-eval.sh / run-ground-truth.sh = the CALLER's project), else the git repo enclosing this task
# dir (direct `bash check.sh` on a dev checkout). NEVER derive it from this file's location alone: on
# a marketplace install the corpus lives in the plugin manager's install cache, outside any git repo, and
# the caller's project is the only thing worth verifying (eval-corpus/README.md §"Project root").
repo_root="${EVAL_PROJECT_ROOT:-}"
if [ -z "$repo_root" ]; then
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "doc-currency-green: EVAL_PROJECT_ROOT unset and not inside a git repo" >&2
    exit 1
  }
fi
# Maintainer-side task: the project must BE the loomwright repo (it dogfoods a repo-local gate).
[ -f "$repo_root/scripts/check-doc-currency.sh" ] || {
  echo "doc-currency-green: $repo_root/scripts/check-doc-currency.sh missing — maintainer-side task; the project root must be the loomwright repo" >&2
  exit 1
}

# Run from the repo root so the gate resolves its inputs deterministically.
cd "$repo_root" && bash scripts/check-doc-currency.sh
exit $?
