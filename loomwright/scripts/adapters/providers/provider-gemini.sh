#!/usr/bin/env bash
# provider-gemini.sh — lens-run.sh PROVIDER-TABLE ENTRY for `gemini`. Sourced
# by lens-run.sh; never invoked directly. See lens-run.sh's header for the
# full per-provider-file contract.
#
# NOT INSTALLED ON THIS MACHINE (re-verified 2026-09-18: `command -v gemini`
# -> absent). Every field below is a DOCUMENTED ASSUMPTION written
# defensively against the `gemini -p` one-shot prompt-mode convention named
# in the source requirement's own Mechanism section — NOT verified against a
# real `gemini --help` (memory lesson verify-invocation-shapes-from-the-file).
# `provider_unavailable` is the ONLY exercised, tested path for this provider
# on this machine — this command template and parser are never run for real
# here.
#
# INVOCATION (assumed): gemini -p [--model <model>] "<composed prompt>"
# (PROMPT_CONTENT is last, matching lens-run.sh's provider_build_argv contract;
# `--model` is appended before the prompt when a model is set.)
# No workspace-equivalent flag is assumed to exist — PROVIDER_WORKSPACE_FLAG=0,
# relying on lens-run.sh's unconditional cwd=sandbox-clone for workspace
# scoping instead of guessing a possibly-wrong flag name.
#
# OUTPUT ENVELOPE (assumed): guessed to follow the same
# object-with-a-top-level-text-field convention the other providers use,
# trying a `.response` key first (a common CLI convention distinct from the
# `.result`-first guess used elsewhere, since this provider's real shape is
# equally unconfirmed and there is no basis to prefer one guess over another);
# a shape mismatch degrades honestly to `lens_unparseable`.

PROVIDER_CLI_NAME="gemini"
PROVIDER_WORKSPACE_FLAG=0
PROVIDER_HOME_SCRUB=1

provider_build_argv() {
  PROVIDER_ARGV=("-p")
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
  PROVIDER_EXTRACTED="$("$JQ" -r '.response // .result // .text // empty' "$raw_file" 2>/dev/null)"
  [ -n "$PROVIDER_EXTRACTED" ] || return 1
  return 0
}
