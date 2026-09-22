#!/usr/bin/env bash
# exec-acceptance-hash.sh — prints the content-keyed stamp for a Supervisor-Ready Brief's
# `## Executable Acceptance` section: `sha256:<hex>` of the whitespace-normalized, newline-joined
# list of `cmd:`/bare bullets ONLY (`corpus-task:`/`qa-executor:` bullets excluded), or the literal
# `none` when that filtered list is empty (including when the section itself is absent).
#
# This is the HUMAN-FACING / brief-authoring half of the content-keyed stamp gate (red-team-
# hardening item 05 — "cmd: valve by provenance"): a human (or Launch Pad's Phase 6
# approve-and-stamp flow) runs this script, reviews the printed-verbatim bullets it covers, and
# writes the result as `- **Executable Acceptance Approved:** <output>` under the brief's
# `## Configuration` section. `run-ground-truth.sh` recomputes the SAME hash at Phase 4.5
# execution time (via the SHARED `exec-acceptance-lib.sh` this script also sources — the two can
# never silently diverge) and refuses to execute any `--brief`-sourced `cmd:`/bare bullet unless
# the stamp matches exactly. Editing the bullets after stamping silently invalidates the stamp
# (stale -> `cmd_unapproved`, no execution) — the stamp is keyed to CONTENT, not mere presence.
#
# `--check`/`--checks-file`-sourced bullets are COMPLETELY unaffected by this gate (see
# run-ground-truth.sh's per-line source-provenance tracking) — the stamp only ever governs bullets
# extracted from a brief's `## Executable Acceptance` section.
#
# Usage:  exec-acceptance-hash.sh <brief-path>
# Output: sha256:<hex>  |  none      (stdout, single line, trailing newline)
# Exit:   0 on success (including the `none` case); 1 on usage error, missing brief, or (only when
#         the filtered bullet list is non-empty) no sha256 tool available.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=exec-acceptance-lib.sh
. "$SCRIPT_DIR/exec-acceptance-lib.sh"

if [ $# -lt 1 ] || [ -z "${1:-}" ]; then
  echo "usage: exec-acceptance-hash.sh <brief-path>" >&2
  exit 1
fi

BRIEF="$1"

if [ ! -f "$BRIEF" ]; then
  echo "exec-acceptance-hash: brief not found: $BRIEF" >&2
  exit 1
fi

exec_acceptance_hash "$BRIEF"
