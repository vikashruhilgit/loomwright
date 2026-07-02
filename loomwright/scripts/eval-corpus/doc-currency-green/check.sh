#!/usr/bin/env bash
# check.sh — doc-currency-green eval task.
# Dogfoods the repo-root doc-currency CI gate: the plugin's doc/count claims
# must stay consistent with the authoritative sources. Pass iff the gate is green.
# Deterministic (same repo state => same result) and read-only.
set -uo pipefail

# The runner cd's into this task dir first, so resolve the repo root robustly.
repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "doc-currency-green: not inside a git repo" >&2
  exit 1
}

# Run from the repo root so the gate resolves its inputs deterministically.
cd "$repo_root" && bash scripts/check-doc-currency.sh
exit $?
