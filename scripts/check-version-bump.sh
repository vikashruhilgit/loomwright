#!/usr/bin/env bash
# check-version-bump.sh — the release-content gate (#512, decision P7 in changelog.d/README.md).
#
# usage: bash scripts/check-version-bump.sh [--base <ref>]
#
# The version files must be exactly what scripts/bump-version.sh produces from the merge base plus
# this branch's changelog.d/ fragments, at ANY commit — not only when the bump is the last commit.
# The rule and its implementation live in ONE place, `bump-version.sh --check` (it shares the
# fragment parser and the entry fold with the bump itself); this wrapper exists only so the gate
# has a read-only name in .github/workflows/ci.yml: scripts/ci-local.sh turns every
# `bash scripts/<x>.sh` line there into a local gate and drops other arguments, so the mutating
# script's own name must never appear on such a line.
#
# Exit: 0 consistent, 1 violated, 2 cannot check (no base ref, shallow clone) — fail CLOSED in CI.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bump-version.sh" --check "$@"
