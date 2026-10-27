#!/usr/bin/env bash
# provider-claude.sh — lens-run.sh PROVIDER-TABLE ENTRY for `claude` (Anthropic's
# own CLI, in `-p`/--print headless mode — the SAME shell-out shape
# dispatch-pr-review.sh already uses for `claude -p --agent ...`). Sourced by
# lens-run.sh; never invoked directly. See that file's header for the full
# per-provider-file contract (the globals/functions every provider file must
# define).
#
# INVOCATION — verified against a real `claude --help` on this dev machine
# (2026-09-18):
#   claude -p --output-format json [--model <model>] "<composed prompt>"
# `claude --help` has no `--workspace`-shaped flag, so PROVIDER_WORKSPACE_FLAG=0
# below tells lens-run.sh this provider relies on `cd`-into-worktree (cwd) for
# workspace scoping instead of an explicit flag — the "or that provider's
# equivalent flag" allowance the source requirement's Scope 2 anticipates.
# lens-run.sh ALWAYS runs the subprocess with cwd = the throwaway sandbox
# clone regardless of provider, so this is satisfied unconditionally, not
# skipped.
#
# OUTPUT ENVELOPE — a real `claude -p --output-format json` response wraps the
# agent's final text reply in a top-level `.result` string field. Since
# lens-run.sh's composed prompt instructs the model to answer with ONLY the
# canonical `{"issues":[...]}` JSON object, provider_extract_text only needs to
# unwrap `.result` — validating THAT text against the canonical issues[] shape
# is centralized in lens-run.sh itself (shared across every provider), not
# duplicated here.
#
# HOME SCRUB — PROVIDER_HOME_SCRUB=1 (lens-run.sh redirects HOME to a
# throwaway temp dir before exec). Whether `claude`'s own auth survives a
# scrubbed HOME is UNVERIFIED here (no live authenticated invocation was
# attempted by this adapter); scrubbing is the conservative default per the
# source requirement's "verify per-provider, don't assume" note — a
# documented assumption, not a confirmed fact.

PROVIDER_CLI_NAME="claude"
PROVIDER_WORKSPACE_FLAG=0
PROVIDER_HOME_SCRUB=1

# provider_build_argv — inputs (globals lens-run.sh sets before calling):
#   MODEL           provider-qualified model string, or "" if none given
#   PROMPT_CONTENT  the fully composed prompt (role + prompt file + diff +
#                   output contract) as a single string
#   WORKSPACE_DIR   absolute path to the throwaway sandbox clone (unused
#                   here — this provider relies on cwd, not a flag)
# Output: sets the global array PROVIDER_ARGV to the full argv AFTER the
# binary name. PROMPT_CONTENT MUST be the LAST element (lens-run.sh's test
# stub locates test directives by reading the last positional argv element).
provider_build_argv() {
  PROVIDER_ARGV=("-p" "--output-format" "json")
  if [ -n "${MODEL:-}" ]; then
    PROVIDER_ARGV+=("--model" "$MODEL")
  fi
  PROVIDER_ARGV+=("$PROMPT_CONTENT")
}

# provider_extract_text <raw_stdout_file> — sets PROVIDER_EXTRACTED to the
# unwrapped candidate JSON text; returns 1 (PROVIDER_EXTRACTED empty) when the
# envelope itself is structurally missing/malformed — the caller then reports
# `lens_unparseable` without treating it as a crash.
provider_extract_text() {
  local raw_file="$1"
  PROVIDER_EXTRACTED=""
  [ -s "$raw_file" ] || return 1
  "$JQ" -e 'type == "object"' "$raw_file" >/dev/null 2>&1 || return 1
  PROVIDER_EXTRACTED="$("$JQ" -r '.result // empty' "$raw_file" 2>/dev/null)"
  [ -n "$PROVIDER_EXTRACTED" ] || return 1
  return 0
}

# ---- PROBE ENTRIES (read by loomwright/scripts/setup-providers.sh `check`;
# lens-run.sh ignores them). Contract: setup-providers.sh's header,
# §"PROBE-ENTRY CONTRACT". Every field below was verified against a real
# `claude --help` / `claude auth status --help` run on this dev machine
# (2026-10-27, CLI 2.1.309), and the smoke was run once by hand there and
# returned the fixed reply inside the `.result` envelope provider_extract_text
# unwraps.
#
# PERMISSIONS — the SAME probe dispatch-pr-review.sh runs before it dispatches
# a headless drain (its PERMISSION_REGIME_UNPINNABLE refusal): `--help` must
# advertise `--permission-mode` with the `dontAsk` choice plus `--allowedTools`
# and `--disallowedTools`. Mirrored here as data so the two cannot disagree on
# what "pinnable" means for this CLI.
#
# SMOKE — print mode with the JSON envelope, plus flags (all present in this
# build's --help) that keep the smoke from touching anything:
# `--no-session-persistence` (no transcript saved), `--safe-mode` (no user
# hooks, plugins, CLAUDE.md or MCP servers load; auth still works — `--bare`
# was rejected because it never reads OAuth/keychain auth), `--tools ""` (no
# built-in tools at all) and `--permission-mode dontAsk` (anything not
# pre-approved is denied rather than prompted).
#
# BROWSER — `--help` lists a `--chrome` integration flag, but no probe has shown
# it driving a browser headless, so the value stays `unknown`.
#
# HINTS — install command from https://code.claude.com/docs/en/setup (read
# 2026-10-27); login is the CLI's own `auth login` subcommand (in its --help).
PROBE_VERSION_ARGV=("--version")
PROBE_AUTH_ARGV=("auth" "status" "--json")
PROBE_AUTH_OK_RE='"loggedIn": *true'
PROBE_AUTH_NOT_LOGGED_IN_RE='"loggedIn": *false'
PROBE_HELP_ARGV=("--help")
PROBE_PERM_PIN_FLAGS="--permission-mode dontAsk --allowedTools --disallowedTools"
PROBE_BROWSER="unknown"
PROBE_INSTALL_HINT="curl -fsSL https://claude.ai/install.sh | bash"
PROBE_LOGIN_HINT="claude auth login"

# probe_smoke_argv — reads PROBE_PROMPT (the fixed probe prompt) and sets
# PROBE_ARGV (argv after the binary name); the prompt is the LAST element.
probe_smoke_argv() {
  PROBE_ARGV=("-p" "--output-format" "json" "--no-session-persistence" "--safe-mode" \
    "--tools" "" "--permission-mode" "dontAsk" "$PROBE_PROMPT")
}
