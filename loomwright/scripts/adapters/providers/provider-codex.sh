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
#
# LOGIN PASS-THROUGH — NOT PROBED: the CLI is not installed here, so where its
# login lives was never observed, and nothing is declared. Nothing crosses
# launch-provider-cli.sh's isolated HOME until someone probes a real install
# and declares it.

PROVIDER_CLI_NAME="codex"
PROVIDER_WORKSPACE_FLAG=0
PROVIDER_HOME_SCRUB=1
PROVIDER_LOGIN_FILES=()
PROVIDER_LOGIN_ENV=()

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

# ---- PROBE ENTRIES (read by loomwright/scripts/setup-providers.sh `check`;
# lens-run.sh ignores them). Contract: setup-providers.sh's header,
# §"PROBE-ENTRY CONTRACT". STILL NOT INSTALLED ON THIS MACHINE (re-checked
# 2026-10-27), so every field below except the install hint is a DOCUMENTED
# ASSUMPTION, never run here:
#   - version: `--version` (the near-universal CLI convention; unverified).
#   - auth: no auth-status command is documented anywhere this entry could
#     consult, so none is declared — the auth column starts `unknown` and is
#     decided by the smoke itself (setup-providers.sh: a passing smoke proves
#     auth; a smoke whose output matches PROBE_AUTH_NOT_LOGGED_IN_RE marks it
#     not_logged_in).
#   - permissions: no pin flag set is verified, so PROBE_PERM_PIN_FLAGS is
#     empty and the column reports `unknown` (never a write seat).
#   - smoke: the lens invocation above with the fixed probe prompt, so the
#     first real run tests the assumed lens shape too.
# Install hint: https://raw.githubusercontent.com/openai/codex/main/README.md
# (read 2026-10-27: "npm install -g @openai/codex"; that README's login step
# is "Run `codex` and select Sign in with ChatGPT").
PROBE_VERSION_ARGV=("--version")
PROBE_AUTH_ARGV=()
PROBE_AUTH_OK_RE=''
PROBE_AUTH_NOT_LOGGED_IN_RE='[Nn]ot (logged|signed) in|[Ll]og ?in required|[Uu]nauthori[sz]ed'
PROBE_HELP_ARGV=("--help")
PROBE_PERM_PIN_FLAGS=""
PROBE_BROWSER="unknown"
PROBE_INSTALL_HINT="npm install -g @openai/codex"
PROBE_LOGIN_HINT="run codex interactively and choose Sign in with ChatGPT"

# probe_smoke_argv — reads PROBE_PROMPT, sets PROBE_ARGV; prompt LAST. Reuses
# provider_build_argv so the smoke and the lens share one assumed shape.
probe_smoke_argv() {
  MODEL=""
  PROMPT_CONTENT="$PROBE_PROMPT"
  provider_build_argv
  PROBE_ARGV=("${PROVIDER_ARGV[@]}")
}
