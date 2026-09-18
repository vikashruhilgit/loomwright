#!/usr/bin/env bash
# provider-cursor.sh — lens-run.sh PROVIDER-TABLE ENTRY for `cursor-agent`.
# Sourced by lens-run.sh; never invoked directly. See lens-run.sh's header for
# the full per-provider-file contract.
#
# INVOCATION — verified against a real `cursor-agent --help` on this dev
# machine (2026-09-18; `cursor-agent` is installed but NOT authenticated —
# `cursor-agent status` -> "Not logged in", see the source requirement's
# "Probe result — 2026-09-18, DEFERRED" section):
#   cursor-agent -p --output-format json [--model <model>] --workspace <dir> "<composed prompt>"
# `--workspace <path>` IS a real, confirmed flag (`--help`: "Workspace
# directory to use (defaults to current working directory)"), so
# PROVIDER_WORKSPACE_FLAG=1 and provider_build_argv passes it explicitly, in
# addition to lens-run.sh's unconditional cwd=worktree — belt and suspenders.
#
# DELIBERATELY NOT PASSING -f/--force ("Force allow commands unless
# explicitly denied"). The deny-by-default probe this flag's existence
# implies is DEFERRED — unauthenticated, see the source requirement file. Not
# passing -f is the conservative choice: it leaves cursor-agent's own
# possible command-deny behavior as an UNVERIFIED extra layer, never relied
# upon as "enforced" (the throwaway-worktree-plus-mutation-check in
# lens-run.sh is the one CONFIRMED lever — see its header and
# docs/ARCHITECTURE_CONTRACTS.md §"Portability").
#
# OUTPUT ENVELOPE — DOCUMENTED ASSUMPTION. The real `--output-format json`
# response shape is UNCONFIRMED (no authenticated invocation was possible on
# this machine). Guessed to follow the same top-level string-envelope
# convention `claude -p --output-format json`'s `.result` field uses (a
# common CLI convention for "final assistant message as JSON"), with
# `.text`/`.output` as defensive fallbacks per the
# verify-invocation-shapes-from-the-file memory lesson. Re-verify against a
# real authenticated response before trusting this in production; until then,
# a shape mismatch degrades honestly to `lens_unparseable` (never a crash).
# `provider_unavailable` (this machine has no authenticated cursor-agent) is
# the ONLY exercised, tested path for the happy-invocation branch here — the
# well-formed-output test case below runs against a STUB, per this repo's
# sanctioned stub-testing convention (see loomwright/scripts/adapters/orca/).

PROVIDER_CLI_NAME="cursor-agent"
PROVIDER_WORKSPACE_FLAG=1
PROVIDER_HOME_SCRUB=1

provider_build_argv() {
  PROVIDER_ARGV=("-p" "--output-format" "json")
  if [ -n "${MODEL:-}" ]; then
    PROVIDER_ARGV+=("--model" "$MODEL")
  fi
  PROVIDER_ARGV+=("--workspace" "$WORKSPACE_DIR")
  PROVIDER_ARGV+=("$PROMPT_CONTENT")
}

provider_extract_text() {
  local raw_file="$1"
  PROVIDER_EXTRACTED=""
  [ -s "$raw_file" ] || return 1
  "$JQ" -e 'type == "object"' "$raw_file" >/dev/null 2>&1 || return 1
  PROVIDER_EXTRACTED="$("$JQ" -r '.result // .text // .output // empty' "$raw_file" 2>/dev/null)"
  [ -n "$PROVIDER_EXTRACTED" ] || return 1
  return 0
}
