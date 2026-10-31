#!/usr/bin/env bash
# provider-copilot.sh — lens-run.sh PROVIDER-TABLE ENTRY for `copilot` (the
# GitHub Copilot CLI). Sourced by lens-run.sh and by setup-providers.sh; never
# invoked directly. See lens-run.sh's header for the lens contract and
# setup-providers.sh's header for the probe-entry contract.
#
# NOT INSTALLED ON THIS MACHINE (checked 2026-10-27: `command -v copilot` ->
# absent). Every invocation shape below comes from the vendor's docs, read on
# 2026-10-27 — never from memory — and has NOT been run here, so each one is a
# DOCUMENTED ASSUMPTION until `setup-providers.sh check` runs against a real,
# logged-in `copilot`:
#   [C] CLI command reference  https://docs.github.com/en/copilot/reference/cli-command-reference     (read 2026-10-27)
#   [I] Installing Copilot CLI https://docs.github.com/en/copilot/how-tos/set-up/install-copilot-cli  (read 2026-10-27)
#
# INVOCATION (lens, [C] "Command-line options"):
#   copilot -s --no-auto-update --no-color [--model=<model>] -p "<composed prompt>"
# `-p PROMPT, --prompt=PROMPT` executes one prompt and exits (the prompt is
# -p's own VALUE, so `-p` sits immediately before PROMPT_CONTENT, which stays
# the LAST element as the lens contract requires); `-s, --silent` outputs
# "only the agent response (without usage statistics)"; `--no-auto-update`
# and `--no-color` keep a scripted run quiet. `-C DIRECTORY` exists but is not
# passed — PROVIDER_WORKSPACE_FLAG=0 relies on lens-run.sh's cwd = sandbox.
#
# OUTPUT ENVELOPE — `--output-format json` is JSONL (one event per line, [C]),
# whose event shape [C] does not spell out, so the default text mode with
# `--silent` is used instead: stdout is the bare reply. provider_extract_text
# drops a surrounding markdown code fence, if any, and hands back the rest; a
# reply that is not the expected JSON degrades to `lens_unparseable` (lens)
# or `headless: fail:unparseable` (probe).
#
# HOME SCRUB — PROVIDER_HOME_SCRUB=1 like every other entry. [C] says the login
# token lives in the system credential store or a config file under the
# user's home tree, so the launcher's isolated HOME probably has no login.
#
# LOGIN PASS-THROUGH — NOT PROBED: the CLI is not installed here, so where its
# login lives was never observed, and nothing is declared. Nothing crosses the
# launcher's isolated HOME until someone probes a real install and declares it.

PROVIDER_CLI_NAME="copilot"
PROVIDER_WORKSPACE_FLAG=0
PROVIDER_HOME_SCRUB=1
PROVIDER_LOGIN_FILES=()
PROVIDER_LOGIN_ENV=()

provider_build_argv() {
  PROVIDER_ARGV=("-s" "--no-auto-update" "--no-color")
  if [ -n "${MODEL:-}" ]; then
    PROVIDER_ARGV+=("--model=$MODEL")
  fi
  PROVIDER_ARGV+=("-p" "$PROMPT_CONTENT")
}

provider_extract_text() {
  local raw_file="$1"
  PROVIDER_EXTRACTED=""
  [ -s "$raw_file" ] || return 1
  PROVIDER_EXTRACTED="$(sed -e '/^[[:space:]]*```/d' "$raw_file" 2>/dev/null)"
  case "$PROVIDER_EXTRACTED" in
    *[![:space:]]*) return 0 ;;
  esac
  PROVIDER_EXTRACTED=""
  return 1
}

# ---- PROBE ENTRIES (read by setup-providers.sh `check`; lens-run.sh ignores
# them). Every field is a DOCUMENTED ASSUMPTION sourced as cited:
#   - version: `--version` ([C]: "-v, --version  Show version information";
#     the `copilot version` subcommand also checks for updates, so it is not
#     used).
#   - auth: [C] documents `copilot login` and token environment variables but
#     NO non-interactive auth-status command, so none is declared. The auth
#     column starts `unknown` and is decided by the smoke: a passing smoke
#     proves auth; a failing smoke whose output matches
#     PROBE_AUTH_NOT_LOGGED_IN_RE (a guess at the wording) marks it
#     not_logged_in. The probe never reads those environment variables; only
#     the CLI does.
#   - permissions: [C] documents per-invocation `--allow-tool`, `--deny-tool`
#     and `--available-tools` (tools that "will not prompt" / are the only
#     ones available). `copilot --help` advertising all three is necessary,
#     not sufficient; `--allow-all-tools` / `--yolo` alone is not pinning.
#     What print mode does with a tool on neither list is not documented, so
#     `pinnable` also needs probe_perm_argv (below) to observe a denial.
#   - browser: `unknown` until a probe shows it.
#   - install hint: [I] (`npm install -g @github/copilot`; Homebrew and an
#     install script are listed there too).
#   - login hint: [C] (`copilot login`).
#   - smoke: the lens invocation above with the fixed probe prompt.
PROBE_VERSION_ARGV=("--version")
PROBE_AUTH_ARGV=()
PROBE_AUTH_OK_RE=''
PROBE_AUTH_NOT_LOGGED_IN_RE='copilot login|[Nn]ot (logged|signed) in|[Nn]ot authenticated|[Nn]o authentication|[Uu]nauthori[sz]ed'
PROBE_HELP_ARGV=("--help")
PROBE_PERM_PIN_FLAGS="--allow-tool --deny-tool --available-tools"
PROBE_BROWSER="unknown"
PROBE_INSTALL_HINT="npm install -g @github/copilot"
PROBE_LOGIN_HINT="copilot login"

# probe_smoke_argv — reads PROBE_PROMPT, sets PROBE_ARGV; prompt LAST. Reuses
# provider_build_argv so the smoke and the lens share one documented shape.
probe_smoke_argv() {
  MODEL=""
  PROMPT_CONTENT="$PROBE_PROMPT"
  provider_build_argv
  PROBE_ARGV=("${PROVIDER_ARGV[@]}")
}

# probe_perm_argv — the permission-ENFORCEMENT probe (setup-providers.sh
# `check`): reads PROBE_PROMPT (which asks for a file to be written), sets
# PROBE_ARGV, prompt LAST. The lens shape with NO `--allow-tool`, `--deny-tool`
# or `--allow-all-tools`: whether print mode then refuses the write is exactly
# what the probe observes (a DOCUMENTED ASSUMPTION, never run here).
probe_perm_argv() {
  MODEL=""
  PROMPT_CONTENT="$PROBE_PROMPT"
  provider_build_argv
  PROBE_ARGV=("${PROVIDER_ARGV[@]}")
}
