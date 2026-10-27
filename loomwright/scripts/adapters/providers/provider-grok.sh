#!/usr/bin/env bash
# provider-grok.sh — lens-run.sh PROVIDER-TABLE ENTRY for `grok` (xAI's Grok
# Build CLI). Sourced by lens-run.sh and by setup-providers.sh; never invoked
# directly. See lens-run.sh's header for the lens contract and
# setup-providers.sh's header for the probe-entry contract.
#
# NOT INSTALLED ON THIS MACHINE (checked 2026-10-27: `command -v grok` ->
# absent). Every invocation shape below comes from the vendor's docs, read on
# 2026-10-27 — never from memory — and has NOT been run here, so each one is a
# DOCUMENTED ASSUMPTION until `setup-providers.sh check` runs against a real,
# logged-in `grok`:
#   [H] Headless & Scripting  https://docs.x.ai/build/cli/headless-scripting  (read 2026-10-27)
#   [R] CLI Reference         https://docs.x.ai/build/cli/reference           (read 2026-10-27)
#   [P] Permissions           https://docs.x.ai/build/features/permissions    (read 2026-10-27)
#   [E] Enterprise            https://docs.x.ai/build/enterprise              (read 2026-10-27)
#   [O] Get Started           https://docs.x.ai/build/overview                (read 2026-10-27)
#
# INVOCATION (lens, [H]):
#   grok --no-auto-update --output-format json [-m <model>] -p "<composed prompt>"
# [H] lists `-p, --single <PROMPT>` (the prompt is -p's own VALUE, so `-p` is
# placed immediately before PROMPT_CONTENT, which stays the LAST element as the
# lens contract requires), `-m, --model <MODEL>`, `--output-format
# plain|json|streaming-json`, and recommends `--no-auto-update` for headless
# runs in scripts. `--cwd <PATH>` exists ([H]) but is not passed —
# PROVIDER_WORKSPACE_FLAG=0 relies on lens-run.sh's cwd = sandbox, exactly like
# the other cwd-scoped providers.
#
# OUTPUT ENVELOPE — [H] says `json` emits "one JSON object at the end" but
# does not name the field that carries the reply text. provider_extract_text
# therefore tries several common top-level keys; a mismatch degrades to
# `lens_unparseable` (lens) or `headless: fail:unparseable` (probe), which is
# exactly the signal that tells the owner to correct this guess.
#
# HOME SCRUB — PROVIDER_HOME_SCRUB=1 like every other entry (lens-run.sh's
# conservative default). [H]/[O] say headless sessions and config live under
# the user's home tree, so a scrubbed HOME probably has no login; unverified.

PROVIDER_CLI_NAME="grok"
PROVIDER_WORKSPACE_FLAG=0
PROVIDER_HOME_SCRUB=1

provider_build_argv() {
  PROVIDER_ARGV=("--no-auto-update" "--output-format" "json")
  if [ -n "${MODEL:-}" ]; then
    PROVIDER_ARGV+=("-m" "$MODEL")
  fi
  PROVIDER_ARGV+=("-p" "$PROMPT_CONTENT")
}

provider_extract_text() {
  local raw_file="$1"
  PROVIDER_EXTRACTED=""
  [ -s "$raw_file" ] || return 1
  "$JQ" -e 'type == "object"' "$raw_file" >/dev/null 2>&1 || return 1
  PROVIDER_EXTRACTED="$("$JQ" -r '.result // .response // .text // .output // .message // .content // empty' "$raw_file" 2>/dev/null)"
  [ -n "$PROVIDER_EXTRACTED" ] || return 1
  return 0
}

# ---- PROBE ENTRIES (read by setup-providers.sh `check`; lens-run.sh ignores
# them). Every field is a DOCUMENTED ASSUMPTION sourced as cited:
#   - version: `grok version` ([R] subcommand table: "Print version
#     information").
#   - auth: [R] documents `grok login` / `grok logout` but NO auth-status
#     subcommand, so none is declared. The auth column starts `unknown` and is
#     decided by the smoke: a passing smoke proves auth; a failing smoke whose
#     output matches PROBE_AUTH_NOT_LOGGED_IN_RE marks it not_logged_in (the
#     regex is a guess at the wording; [H]'s ACP example says "Run `grok login`
#     first"). RISK: [O] says the interactive first launch opens a browser to
#     authenticate; whether print mode does the same when logged out is
#     undocumented. The smoke runs with stdin from /dev/null and a hard
#     timeout, so at worst it is killed.
#   - permissions: [E] documents a headless `--permission-mode dontAsk`
#     ("Silently deny anything without an explicit allow rule") with
#     `--allow` / `--deny` rules ([R], [P]). The column is `pinnable` only
#     when `grok --help` advertises all of those tokens, each as a whole token
#     (so `--allow-all` / `--deny-<x>` do not count as `--allow` / `--deny`);
#     `--always-approve` /
#     `--yolo` alone ([R]: "Auto-approve all tool executions") is not pinning,
#     so a build without them reports `unpinnable`. [E] files `dontAsk` under
#     enterprise policy, so a consumer build may well report `unpinnable`.
#   - browser: `unknown` until a probe shows it.
#   - install hint: [O] ("curl -fsSL https://x.ai/cli/install.sh | bash").
#   - login hint: [R] (`grok login`; `--device-auth` for headless hosts).
#   - smoke: the lens invocation above with the fixed probe prompt.
PROBE_VERSION_ARGV=("version")
PROBE_AUTH_ARGV=()
PROBE_AUTH_OK_RE=''
PROBE_AUTH_NOT_LOGGED_IN_RE='grok login|[Nn]ot (logged|signed) in|[Nn]ot authenticated|[Uu]nauthori[sz]ed'
PROBE_HELP_ARGV=("--help")
PROBE_PERM_PIN_FLAGS="--permission-mode dontAsk --allow --deny"
PROBE_BROWSER="unknown"
PROBE_INSTALL_HINT="curl -fsSL https://x.ai/cli/install.sh | bash"
PROBE_LOGIN_HINT="grok login   (or: grok login --device-auth)"

# probe_smoke_argv — reads PROBE_PROMPT, sets PROBE_ARGV; prompt LAST. Reuses
# provider_build_argv so the smoke and the lens share one documented shape.
probe_smoke_argv() {
  MODEL=""
  PROMPT_CONTENT="$PROBE_PROMPT"
  provider_build_argv
  PROBE_ARGV=("${PROVIDER_ARGV[@]}")
}
