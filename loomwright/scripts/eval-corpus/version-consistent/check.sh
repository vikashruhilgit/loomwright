#!/usr/bin/env bash
# check.sh — version-consistent eval task.
# Dogfoods the repo-root version/manifest validation gate: plugin.json version must
# be valid and consistent across manifests. Pass iff validate-version.sh passes.
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
    echo "version-consistent: EVAL_PROJECT_ROOT unset and not inside a git repo" >&2
    exit 1
  }
fi
# Maintainer-side task: the project must BE the loomwright repo (it dogfoods a repo-local gate).
[ -f "$repo_root/scripts/validate-version.sh" ] || {
  echo "version-consistent: $repo_root/scripts/validate-version.sh missing — maintainer-side task; the project root must be the loomwright repo" >&2
  exit 1
}

# validate-version.sh reads manifest paths relative to CWD, so run it from the repo root.
cd "$repo_root" && bash scripts/validate-version.sh
exit $?
