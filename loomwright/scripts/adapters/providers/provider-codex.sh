#!/usr/bin/env bash
# provider-codex.sh — lens-run.sh PROVIDER-TABLE ENTRY for `codex`. Sourced by
# lens-run.sh; never invoked directly. See lens-run.sh's header for the full
# per-provider-file contract.
#
# NOT INSTALLED ON THIS MACHINE (re-verified 2026-09-18: `command -v codex` ->
# absent). Every field below is a DOCUMENTED ASSUMPTION written defensively
# against the `codex exec` one-shot headless-mode convention named in the
# source requirement's own Mechanism section — NOT verified against a real
# `codex --help` (memory lesson verify-invocation-shapes-from-the-file: since
# this CLI cannot be inspected on this machine, the template is written
# defensively rather than asserted as fact). `provider_unavailable` is the
# ONLY exercised, tested path for this provider on this machine — this
# command template and parser are never run for real here.
#
# INVOCATION (assumed): codex exec --json [--model <model>] "<composed prompt>"
# No workspace-equivalent flag is assumed to exist (none is documented
# anywhere this adapter could consult) — PROVIDER_WORKSPACE_FLAG=0, relying on
# lens-run.sh's unconditional cwd=sandbox-clone for workspace scoping instead
# of guessing a possibly-wrong flag name that could error out a real
# invocation.
#
# OUTPUT ENVELOPE (assumed): guessed to follow the same
# object-with-a-top-level-text-field convention the other providers use; if
# `codex exec --json` actually streams JSONL events instead, this parser
# degrades honestly to `lens_unparseable` rather than guessing further.

PROVIDER_CLI_NAME="codex"
PROVIDER_WORKSPACE_FLAG=0
PROVIDER_HOME_SCRUB=1

provider_build_argv() {
  PROVIDER_ARGV=("exec" "--json")
  if [ -n "${MODEL:-}" ]; then
    PROVIDER_ARGV+=("--model" "$MODEL")
  fi
  PROVIDER_ARGV+=("$PROMPT_CONTENT")
}

provider_extract_text() {
  local raw_file="$1"
  PROVIDER_EXTRACTED=""
  [ -s "$raw_file" ] || return 1
  "$JQ" -e 'type == "object"' "$raw_file" >/dev/null 2>&1 || return 1
  PROVIDER_EXTRACTED="$("$JQ" -r '.result // .text // .output // .message // empty' "$raw_file" 2>/dev/null)"
  [ -n "$PROVIDER_EXTRACTED" ] || return 1
  return 0
}
