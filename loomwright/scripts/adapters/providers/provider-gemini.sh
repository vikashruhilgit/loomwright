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

# ---- PROBE ENTRIES (read by loomwright/scripts/setup-providers.sh `check`;
# lens-run.sh ignores them). Contract: setup-providers.sh's header,
# §"PROBE-ENTRY CONTRACT". STILL NOT INSTALLED ON THIS MACHINE (re-checked
# 2026-10-27), so every field below except the install hint is a DOCUMENTED
# ASSUMPTION, never run here:
#   - version: `--version` (the near-universal CLI convention; unverified).
#   - auth: no auth-status command is documented in the README this entry
#     consulted, so none is declared — the auth column starts `unknown` and is
#     decided by the smoke (a passing smoke proves auth; output matching
#     PROBE_AUTH_NOT_LOGGED_IN_RE marks it not_logged_in).
#   - permissions: no pin flag set is verified, so PROBE_PERM_PIN_FLAGS is
#     empty and the column reports `unknown` (never a write seat).
#   - smoke: the lens invocation above with the fixed probe prompt. The
#     README (below) documents `-p` and `--output-format json`; the lens shape
#     above does not pass the latter, so the smoke reports what the CLI's
#     default output really is.
# Install hint and login step: https://raw.githubusercontent.com/google-gemini/gemini-cli/main/README.md
# (read 2026-10-27: "npm install -g @google/gemini-cli"; login is "Sign in
# with Google" in an interactive run).
PROBE_VERSION_ARGV=("--version")
PROBE_AUTH_ARGV=()
PROBE_AUTH_OK_RE=''
PROBE_AUTH_NOT_LOGGED_IN_RE='[Nn]ot (logged|signed) in|[Ll]og ?in required|[Uu]nauthori[sz]ed|authentication method'
PROBE_HELP_ARGV=("--help")
PROBE_PERM_PIN_FLAGS=""
PROBE_BROWSER="unknown"
PROBE_INSTALL_HINT="npm install -g @google/gemini-cli"
PROBE_LOGIN_HINT="run gemini interactively and choose Sign in with Google"

# probe_smoke_argv — reads PROBE_PROMPT, sets PROBE_ARGV; prompt LAST. Reuses
# provider_build_argv so the smoke and the lens share one assumed shape.
probe_smoke_argv() {
  MODEL=""
  PROMPT_CONTENT="$PROBE_PROMPT"
  provider_build_argv
  PROBE_ARGV=("${PROVIDER_ARGV[@]}")
}
