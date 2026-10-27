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
# upon as "enforced" (the throwaway-isolated-clone-plus-mutation-check in
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

# ---- PROBE ENTRIES (read by loomwright/scripts/setup-providers.sh `check`;
# lens-run.sh ignores them). Contract: setup-providers.sh's header,
# §"PROBE-ENTRY CONTRACT". Verified against a real `cursor-agent --help` and
# `cursor-agent status` on this dev machine (2026-10-27, CLI
# 2026.09.18-9a7762b; the CLI updated itself to 2026.10.22-27dcf5f during the
# same session and its --help still matched every flag named here).
# `cursor-agent` was LOGGED IN that day, and the smoke
# below was run once by hand: it returned the fixed reply inside a top-level
# `.result` string, so the `.result` guess in provider_extract_text above held
# for this build.
#
# AUTH — `status` prints a "Logged in as <account>" line or "Not logged in".
# setup-providers.sh only pattern-matches that output; it never prints it
# (the account name is not echoed into the report).
#
# PERMISSIONS — `none`, i.e. reported `unpinnable`. `--help` (2026-10-27) says
# print mode "Has access to all tools, including write and shell", and offers
# no per-invocation allowlist flag; its only overrides are `-f`/`--force`/
# `--yolo` (allow everything) and the read-only `--mode plan|ask`. This entry
# follows the reasoning of the DELIBERATELY NOT PASSING -f/--force note above:
# `-f` is never adopted, and a read-only mode is not an allowlist, so this
# provider cannot pin tool permissions for a write seat.
#
# SMOKE — print mode with the JSON envelope, `--mode ask` (read-only Q&A, so
# the smoke can run no edit or shell tool), and `--trust`: without it print
# mode exits 1 with "Workspace Trust Required" for any directory it has not
# seen (observed 2026-10-27), and the smoke's cwd is always a fresh throwaway
# directory. `--trust` trusts only that empty directory; the CLI may record it
# in its own state under the real HOME (a vendor-side write).
#
# HINTS — install command from https://cursor.com/docs/cli/installation (read
# 2026-10-27); login is the CLI's own `login` subcommand (in its --help).
PROBE_VERSION_ARGV=("--version")
PROBE_AUTH_ARGV=("status")
PROBE_AUTH_OK_RE='Logged in as'
PROBE_AUTH_NOT_LOGGED_IN_RE='Not logged in'
PROBE_HELP_ARGV=("--help")
PROBE_PERM_PIN_FLAGS="none"
PROBE_BROWSER="unknown"
PROBE_INSTALL_HINT="curl https://cursor.com/install -fsS | bash"
PROBE_LOGIN_HINT="cursor-agent login"

# probe_smoke_argv — reads PROBE_PROMPT, sets PROBE_ARGV; prompt LAST.
probe_smoke_argv() {
  PROBE_ARGV=("-p" "--output-format" "json" "--mode" "ask" "--trust" "$PROBE_PROMPT")
}
