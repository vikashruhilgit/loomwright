#!/usr/bin/env bash
# check.sh — version-consistent eval task.
# Dogfoods the repo-root version/manifest validation gate: plugin.json version must
# be valid and consistent across manifests. Pass iff validate-version.sh passes.
# Deterministic (same repo state => same result) and read-only.
set -uo pipefail

# The runner cd's into this task dir first, so resolve the repo root robustly.
repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "version-consistent: not inside a git repo" >&2
  exit 1
}

# validate-version.sh reads manifest paths relative to CWD, so run it from the repo root.
cd "$repo_root" && bash scripts/validate-version.sh
exit $?
