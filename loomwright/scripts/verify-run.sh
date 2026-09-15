#!/usr/bin/env bash
# verify-run.sh — the MECHANIZED main-thread steps of `/verify <ticket>`: the deterministic work the
# command layer and the qa-executor `--verify` mode shell out to, so the tested code IS the executed
# code. Schema authority: `docs/RESULT_SCHEMAS.md` §VERIFY_EVIDENCE (every line this script records)
# and §VERIFY_RESULT (the block the agent emits from `finish`'s printed counts row). Modelled on
# `verify-helpers.sh` / `automate-helpers.sh` (subcommand dispatch, `set -uo pipefail`, diag to stderr,
# jq-only JSON construction, siblings located relative to this file — vendor-neutral core, never a
# plugin-root variable).
#
# WHY THIS EXISTS. Nothing verified a ticket against the RUNNING app: `## Executable Acceptance` is
# cmd/corpus-task only, `/qa-executor` crawls from discovery and forbids form submission, review reads
# the diff. This script owns the browser-less half of a `/verify` run — reading the ticket's acceptance
# criteria, refusing to touch anything not proven non-prod, minting the run dir, and recording the
# verdicts that need NO observation (`NOT_VERIFIABLE` / `BLOCKED`). It NEVER writes `evidence.jsonl`
# itself — every line goes through `verify-helpers.sh evidence-append` (the store's only writer) — and
# it NEVER records a `PASS` or a `FAIL`: those two verdicts come ONLY from the Playwright ingest in
# `walk` (an observation), never from a hand-typed argument (`pass_requires_observation`).
#
# Subcommands:
#   acs        <ticket>                                              # print {"ticket_kind": …, "acs": [{"ac_id":"AC1","text":"…"}, …]}
#   preflight  <ticket> [--branch <name>] [--repo <dir>]             # contract read → run dir + run_start → assert-non-prod → env line; prints `run_dir=<path>` LAST
#   auth-check <run_dir> [--repo <dir>]                              # auth.method none ⇒ no-op exit 0; else probe — authenticated ⇒ one `auth` line exit 0; else `auth`+`pause` lines, exit 4
#   pause      <run_dir> --reason <needs_auth|session_expired>       # append ONE `pause` line (the only place a pause line is ever written) + rebuild summary.md
#   walk       <run_dir> [--repo <dir>] [--base-url <url>]           # generate the per-run Playwright config, run the `[ACn]` specs, ingest the reporter into `ac` lines
#   verdict    <run_dir> <ac_id> <NOT_VERIFIABLE|BLOCKED> --reason <text> [--classification <c>]   # append one browser-less `ac` line
#   finish     <run_dir> [--status completed|aborted]                # append run_end (NO counts), rebuild summary.md, print its counts row
#
# Exit codes: 0 ok · 1 refused / failed (non-prod assertion failed, append refused) · 2 usage / ticket
# unresolved / a verdict that needs observation · 3 preflight stop (no contract at .agent/verify.json,
# contract unreadable — nothing created, nothing called) / walk stop (the Playwright harness is not
# resolvable from the target repo, or it produced no reporter file — every AC still without a verdict
# gets a BLOCKED line first) · 4 auth-check: the run needs a human sign-in (a `pause --reason needs_auth`
# line was appended; the caller prints the codegen instruction and stops) · 5 walk: a session expired
# mid-run (a real 401/403 observed on an authenticated route forced BLOCKED/ENVIRONMENT_ISSUE onto that
# AC and every later one, and a `pause --reason session_expired` line was appended).
# Dependencies: bash 3.2+, jq, git, python3 (through verify-helpers.sh's validator gate),
# `shasum -a 256` or `sha256sum` (the run_start contract hash); `walk` additionally needs `npx` and a
# `@playwright/test` resolvable FROM THE TARGET REPO (`npx --no-install playwright`) — the plugin never
# installs it, the project under test owns its harness.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HELPERS="$HERE/verify-helpers.sh"
READER="$HERE/read-verify.sh"
EXECUTOR="$HERE/verify-env.sh"
BOOTSTRAP="$HERE/propose-verify.sh"

# The one scratch file a subcommand may hold (stderr captures); SCRIPT-LEVEL on purpose — the EXIT
# trap that removes it fires after the function's locals are gone, and `set -u` would name it unbound.
rerr=""

# Set by `walk_ingest` (via `walk_apply_expiry_override`) when AC5's expiry override fired; read by
# `walk_cmd` AFTER the function returns to decide its exit code. SCRIPT-LEVEL for the same reason as
# `rerr` above — a function-local would not survive the call boundary.
walk_session_expired=0

diag()  { echo "verify-run: $*" >&2; }
die()   { diag "$*"; exit 1; }
usage() { diag "usage: $*"; exit 2; }

now_ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# sha256_of <file> — `shasum -a 256` first (macOS ships no sha256sum), `sha256sum` fallback; empty
# when neither exists (the run_start hash is then recorded as null, never as a made-up value).
sha256_of() {
  local f="$1" h=""
  if command -v shasum >/dev/null 2>&1; then
    h="$(shasum -a 256 "$f" 2>/dev/null | cut -d' ' -f1)"
  elif command -v sha256sum >/dev/null 2>&1; then
    h="$(sha256sum "$f" 2>/dev/null | cut -d' ' -f1)"
  fi
  printf '%s' "$h"
}

# resolve_repo <dir|""> — absolute repo dir: the flag, else the cwd's git top-level, else the cwd.
resolve_repo() {
  local d="${1:-}"
  if [ -z "$d" ]; then
    d="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi
  [ -d "$d" ] || usage "--repo '$d' is not a directory"
  (cd "$d" && pwd)
}

# --------------------------------------------------------------------------- #
# acs <ticket>
# --------------------------------------------------------------------------- #
# ticket_kind by PATH: under `.supervisor/requirements/` ⇒ requirement; under `.supervisor/jobs/` ⇒
# brief; anything else ⇒ [ticket_unresolved]. Extraction is the SAME for both kinds: the top-level
# `- ` bullets between the first `## Acceptance Criteria` header (case-insensitive) and the next `## `
# header; an indented continuation line is folded into its bullet; a leading `[ ]`/`[x]` checkbox and
# a leading `AC<n>` label (with an optional `:`/`-`) are stripped; empty bullets are skipped; `ac_id`
# is the 1-based ordinal in file order. The object is jq-built with --arg / -R, never concatenated.
ticket_kind_of() {
  case "$1" in
    *.supervisor/requirements/*) printf 'requirement' ;;
    *.supervisor/jobs/*)         printf 'brief' ;;
    *)                           printf '' ;;
  esac
}

# acs_bullets <ticket> — one raw bullet per stdout line (continuations folded); exit 4 when the
# header is absent. Captured by the caller with its status in a separate statement.
acs_bullets() {
  awk '
    function flush() { if (cur != "") print cur; cur = "" }
    BEGIN { on = 0; found = 0; cur = "" }
    /^## / {
      if (on) { flush(); on = 0; exit }
      h = tolower($0); sub(/^##[ \t]+/, "", h); gsub(/[ \t\r]+$/, "", h)
      if (h ~ /^acceptance criteria/) { on = 1; found = 1 }
      next
    }
    on && /^- / { flush(); cur = substr($0, 3); next }
    on && /^[ \t]+[^ \t]/ && cur != "" { line = $0; sub(/^[ \t]+/, "", line); cur = cur " " line; next }
    on && /^[ \t\r]*$/ { next }
    on { flush() }
    END { flush(); if (!found) exit 4 }
  ' "$1"
}

acs_json() {
  local ticket="${1:-}" kind raw rc
  [ -n "$ticket" ] || usage "acs <ticket>"
  kind="$(ticket_kind_of "$ticket")"
  if [ -z "$kind" ]; then
    diag "'$ticket' is neither under .supervisor/requirements/ nor .supervisor/jobs/ [ticket_unresolved]"
    return 2
  fi
  if [ ! -f "$ticket" ]; then
    diag "ticket not found at '$ticket' [ticket_unresolved]"
    return 2
  fi
  raw="$(acs_bullets "$ticket")"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    diag "'$ticket' has no '## Acceptance Criteria' header [ticket_unresolved]"
    return 2
  fi
  raw="$(printf '%s\n' "$raw" \
    | tr -d '\r' \
    | sed -E 's/^[[:space:]]*\[[ xX]\][[:space:]]*//; s/^AC[0-9]+[[:space:]]*[:—–-]?[[:space:]]*//; s/[[:space:]]+$//' \
    | grep -v '^[[:space:]]*$')"
  if [ -z "$raw" ]; then
    diag "'$ticket' has an acceptance-criteria header but no bullets under it [ticket_unresolved]"
    return 2
  fi
  printf '%s\n' "$raw" | jq -R . | jq -sc --arg kind "$kind" '
    {ticket_kind: $kind,
     acs: (to_entries | map({ac_id: ("AC" + ((.key + 1) | tostring)), text: .value}))}'
}

acs_cmd() {
  local out rc
  out="$(acs_json "$@")"
  rc=$?
  [ "$rc" -eq 0 ] || exit "$rc"
  printf '%s\n' "$out"
}

# --------------------------------------------------------------------------- #
# preflight <ticket> [--branch <name>] [--repo <dir>]
# --------------------------------------------------------------------------- #
# Order is the contract: (1) acs — exit 2 with nothing created; (2) the contract through the reader —
# EMPTY stdout ⇒ name the absence and the bootstrap line, exit 3 BEFORE any dir exists and BEFORE any
# executor call (an absent contract must never reach `verify-env.sh`, whose every subcommand would
# itself refuse — but the refusal would already be a call); (3) run dir + run_start + acs.json +
# diff.stat; (4) `assert-non-prod` — stdout and `$?` captured in two statements; fail ⇒ the `env`
# fail line with the executor's own bracketed reason, exit 1, and `start` is NEVER called.
preflight_cmd() {
  local ticket="" branch="" repo_arg="" repo acs kind contract tokens
  local run_id run_dir base head_sha base_sha hash ts out rc reason
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --branch) [ "$#" -ge 2 ] || usage "--branch needs a value"; branch="$2"; shift 2 ;;
      --repo)   [ "$#" -ge 2 ] || usage "--repo needs a value";   repo_arg="$2"; shift 2 ;;
      -*)       usage "preflight <ticket> [--branch <name>] [--repo <dir>] (unknown flag $1)" ;;
      *)        if [ -z "$ticket" ]; then ticket="$1"; shift; else usage "preflight takes ONE ticket"; fi ;;
    esac
  done
  [ -n "$ticket" ] || usage "preflight <ticket> [--branch <name>] [--repo <dir>]"
  command -v jq >/dev/null 2>&1 || die "jq is required [jq_unavailable]"
  [ -f "$HELPERS" ] || die "sibling verify-helpers.sh not found at $HELPERS"
  [ -f "$READER" ]  || die "sibling read-verify.sh not found at $READER"
  repo="$(resolve_repo "$repo_arg")" || exit 2

  # (1) the ticket's acceptance criteria — nothing is created on failure.
  acs="$(acs_json "$ticket")"
  rc=$?
  [ "$rc" -eq 0 ] || exit "$rc"
  kind="$(printf '%s' "$acs" | jq -r '.ticket_kind')"

  # (2) the contract, THROUGH the reader (never re-parsed). Empty stdout ⇒ stop before anything.
  rerr="$(mktemp "${TMPDIR:-/tmp}/verify-run.XXXXXX")" || die "mktemp failed"
  trap 'rm -f "$rerr" 2>/dev/null' EXIT
  contract="$(bash "$READER" --repo "$repo" 2>"$rerr")"
  if [ -z "$contract" ]; then
    if grep -qF '[store_absent]' "$rerr" 2>/dev/null; then
      echo "no verification contract at .agent/verify.json — /verify refuses to touch an app it cannot prove is non-prod."
    else
      tokens="$(grep -oE '\[[A-Za-z0-9_.:-]+\]' "$rerr" 2>/dev/null | tr '\n' ' ')"
      echo "verification contract at .agent/verify.json is unreadable (${tokens:-no reason token}) — fix it before running /verify."
    fi
    echo "bootstrap: bash \"$BOOTSTRAP\" --non-prod <regex|env=NAME=VAL|cmd=<shell>> --confirm   # --non-prod is REQUIRED (the bootstrap refuses without it); --confirm writes the store"
    exit 3
  fi

  # (3) the run dir and its first facts.
  # A run dir is NEVER reused: `run-id` has one-second resolution, so two preflights in the same
  # second would mint the same id and the second would append into the first's store — two runs
  # reported as one. Re-mint once after a second; still taken ⇒ refuse rather than merge.
  run_id="$(bash "$HELPERS" run-id "$(basename "$ticket" .md)")" || die "could not mint a run id"
  run_dir="$repo/.supervisor/verify/$run_id"
  if [ -e "$run_dir" ]; then
    sleep 1
    run_id="$(bash "$HELPERS" run-id "$(basename "$ticket" .md)")" || die "could not mint a run id"
    run_dir="$repo/.supervisor/verify/$run_id"
    [ -e "$run_dir" ] && die "run dir already exists at $run_dir — refusing to append into another run [run_dir_exists]"
  fi
  mkdir -p "$run_dir" || die "cannot create $run_dir"
  if [ -z "$branch" ]; then
    branch="$(git -C "$repo" branch --show-current 2>/dev/null)"
    [ -n "$branch" ] || branch="HEAD"
  fi
  head_sha="$(git -C "$repo" rev-parse --verify -q "$branch^{commit}" 2>/dev/null)" \
    || head_sha="$(git -C "$repo" rev-parse --verify -q HEAD 2>/dev/null)" || head_sha=""
  base="$(git -C "$repo" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
  [ -n "$base" ] || base="main"
  base_sha="$(git -C "$repo" rev-parse --verify -q "origin/$base^{commit}" 2>/dev/null)" \
    || base_sha="$(git -C "$repo" rev-parse --verify -q "$base^{commit}" 2>/dev/null)" || base_sha=""
  hash=""
  [ -f "$repo/.agent/verify.json" ] && hash="$(sha256_of "$repo/.agent/verify.json")"
  printf '%s\n' "$acs" > "$run_dir/acs.json" || die "cannot write $run_dir/acs.json"
  # Advisory diff summary — an empty file when the base is unresolvable, never a failure.
  git -C "$repo" diff --stat "origin/$base...$branch" > "$run_dir/diff.stat" 2>/dev/null \
    || : > "$run_dir/diff.stat"
  ts="$(now_ts)"
  jq -cn --arg ts "$ts" --arg run_id "$run_id" --arg ticket "$ticket" --arg kind "$kind" \
     --arg branch "$branch" --arg head "$head_sha" --arg base "$base_sha" --arg hash "$hash" '
    {schema_version: 1, ts: $ts, run_id: $run_id, event: "run_start", ticket_path: $ticket,
     ticket_kind: $kind, branch: $branch, head_sha: $head, base_sha: $base,
     env_contract_hash: (if $hash == "" then null else $hash end)}' \
    | bash "$HELPERS" evidence-append "$run_dir" - >/dev/null || die "run_start line was refused (see $run_dir/rejected.jsonl)"

  # (4) the non-prod gate — the ONLY executor call preflight ever makes.
  out="$(bash "$EXECUTOR" assert-non-prod --repo "$repo" 2>"$rerr")"
  rc=$?
  cat "$rerr" >&2
  ts="$(now_ts)"
  if [ "$rc" -eq 0 ]; then
    jq -cn --arg ts "$ts" --arg run_id "$run_id" \
      '{schema_version: 1, ts: $ts, run_id: $run_id, event: "env", step: "non_prod_assert", outcome: "pass"}' \
      | bash "$HELPERS" evidence-append "$run_dir" - >/dev/null || die "env pass line was refused"
    [ -n "$out" ] && printf '%s\n' "$out"
    echo "run_dir=$run_dir"
    return 0
  fi
  reason="$(grep -oE '\[[A-Za-z0-9_.:-]+\]' "$rerr" 2>/dev/null | tail -1 | tr -d '[]')"
  [ -n "$reason" ] || reason="non_prod_assert_failed"
  jq -cn --arg ts "$ts" --arg run_id "$run_id" --arg reason "$reason" \
    '{schema_version: 1, ts: $ts, run_id: $run_id, event: "env", step: "non_prod_assert", outcome: "fail", reason: $reason}' \
    | bash "$HELPERS" evidence-append "$run_dir" - >/dev/null || die "env fail line was refused"
  echo "non-prod assertion FAILED — nothing was started, nothing will be; reason: $reason"
  echo "run_dir=$run_dir"
  return 1
}

# --------------------------------------------------------------------------- #
# run_id_of <run_dir> — the run_start line's run_id when the store has one, else the dir name
# (preflight names the dir after the run id it minted).
# --------------------------------------------------------------------------- #
run_id_of() {
  local run_dir="$1" id=""
  if [ -f "$run_dir/evidence.jsonl" ]; then
    id="$(jq -r 'select(.event == "run_start") | .run_id' "$run_dir/evidence.jsonl" 2>/dev/null | head -1)"
  fi
  [ -n "$id" ] || id="$(basename "$run_dir")"
  printf '%s' "$id"
}

# --------------------------------------------------------------------------- #
# pause <run_dir> --reason <needs_auth|session_expired>
# --------------------------------------------------------------------------- #
# The ONE place a `pause` evidence line is ever written — `auth-check` (AC1) and `walk`'s expiry
# override (AC5) both call THIS function rather than constructing the line themselves. Appends
# {event:pause, reason:<reason>}, rebuilds summary.md for visibility, exits 0.
pause_cmd() {
  local run_dir="${1:-}" reason="" run_id ts
  local u="pause <run_dir> --reason <needs_auth|session_expired>"
  [ -n "$run_dir" ] || usage "$u"
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --reason) [ "$#" -ge 2 ] || usage "--reason needs a value"; reason="$2"; shift 2 ;;
      *)        usage "$u (unknown argument $1)" ;;
    esac
  done
  case "$reason" in
    needs_auth|session_expired) ;;
    *) usage "$u (got --reason '$reason')" ;;
  esac
  [ -d "$run_dir" ] || { diag "run dir not found at $run_dir [run_dir_missing]"; exit 2; }
  run_dir="$(cd "$run_dir" && pwd)"
  run_id="$(run_id_of "$run_dir")"
  ts="$(now_ts)"
  jq -cn --arg ts "$ts" --arg run_id "$run_id" --arg reason "$reason" \
    '{schema_version: 1, ts: $ts, run_id: $run_id, event: "pause", reason: $reason}' \
    | bash "$HELPERS" evidence-append "$run_dir" - >/dev/null || die "pause line was refused (see $run_dir/rejected.jsonl)"
  bash "$HELPERS" summary-build "$run_dir" || die "summary-build failed for $run_dir"
  return 0
}

# --------------------------------------------------------------------------- #
# auth-check <run_dir> [--repo <dir>]
# --------------------------------------------------------------------------- #
# Step 5 of VERIFY MODE: decides whether the run can proceed to spec authoring or must pause for a
# human sign-in. `auth.method: none` (AC2) is a deliberate BEHAVIOR CHANGE from today's unconditional
# `verify-env.sh auth-probe` call — it makes ZERO executor calls and appends NO evidence line at all,
# since an app with no auth concept has nothing to probe and `do_auth_probe`'s own `method: none`
# branch would otherwise record a spurious `auth: anonymous` line. Else the REAL executor call decides:
# stdout `authenticated` AND rc 0 ⇒ one `{event:auth, state:authenticated}` line, exit 0 (AC3); anything
# else (stdout `anonymous`, or any nonzero rc — `storage_state_absent` / unreachable / unexpected code)
# ⇒ `{event:auth, state:needs_auth}` then `pause --reason needs_auth`, exit 4 (AC1).
auth_check_cmd() {
  local run_dir="" repo_arg="" repo contract method out rc run_id ts
  local u="auth-check <run_dir> [--repo <dir>]"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --repo) [ "$#" -ge 2 ] || usage "--repo needs a value"; repo_arg="$2"; shift 2 ;;
      -*)     usage "$u (unknown flag $1)" ;;
      *)      if [ -z "$run_dir" ]; then run_dir="$1"; shift; else usage "auth-check takes ONE run dir"; fi ;;
    esac
  done
  [ -n "$run_dir" ] || usage "$u"
  command -v jq >/dev/null 2>&1 || die "jq is required [jq_unavailable]"
  [ -f "$HELPERS" ] || die "sibling verify-helpers.sh not found at $HELPERS"
  [ -f "$READER" ]  || die "sibling read-verify.sh not found at $READER"
  [ -d "$run_dir" ] || { diag "run dir not found at $run_dir [run_dir_missing]"; exit 2; }
  run_dir="$(cd "$run_dir" && pwd)"
  repo="$(resolve_repo "$repo_arg")" || exit 2
  run_id="$(run_id_of "$run_dir")"

  rerr="$(mktemp "${TMPDIR:-/tmp}/verify-run.XXXXXX")" || die "mktemp failed"
  trap 'rm -f "$rerr" 2>/dev/null' EXIT
  contract="$(bash "$READER" --repo "$repo" 2>"$rerr")"
  if [ -z "$contract" ]; then
    # `preflight` already proved the contract exists before this run dir was ever minted; an empty
    # read here is a defensive fallback, not a fresh refusal — treat it as `auth.method: none`-
    # equivalent and never crash the run over it.
    diag "read-verify.sh returned no contract for auth-check — defaulting to auth.method:none-equivalent (no evidence line, no executor call) [contract_unreadable_defaulting_none]"
    exit 0
  fi
  method="$(printf '%s' "$contract" | jq -r '.auth.method')"
  if [ "$method" = "none" ]; then
    diag "auth.method is none — no evidence line, no verify-env.sh call [auth_method_none]"
    exit 0
  fi

  out="$(bash "$EXECUTOR" auth-probe --repo "$repo" 2>"$rerr")"
  rc=$?
  cat "$rerr" >&2
  ts="$(now_ts)"
  if [ "$out" = "authenticated" ] && [ "$rc" -eq 0 ]; then
    jq -cn --arg ts "$ts" --arg run_id "$run_id" \
      '{schema_version: 1, ts: $ts, run_id: $run_id, event: "auth", state: "authenticated"}' \
      | bash "$HELPERS" evidence-append "$run_dir" - >/dev/null || die "auth authenticated line was refused"
    exit 0
  fi
  jq -cn --arg ts "$ts" --arg run_id "$run_id" \
    '{schema_version: 1, ts: $ts, run_id: $run_id, event: "auth", state: "needs_auth"}' \
    | bash "$HELPERS" evidence-append "$run_dir" - >/dev/null || die "auth needs_auth line was refused"
  pause_cmd "$run_dir" --reason needs_auth || die "pause (needs_auth) failed for $run_dir"
  exit 4
}

# --------------------------------------------------------------------------- #
# verdict <run_dir> <ac_id> <NOT_VERIFIABLE|BLOCKED> --reason <text> [--classification <c>]
# --------------------------------------------------------------------------- #
# The browser-less verdicts. `text` comes from <run_dir>/acs.json by ac_id (an unknown id is refused —
# a verdict must be about a criterion the ticket actually has). NOT_VERIFIABLE carries a null
# classification; BLOCKED defaults to ENVIRONMENT_ISSUE. PASS and FAIL are REFUSED here by design.
verdict_cmd() {
  local run_dir="${1:-}" ac_id="${2:-}" verdict="${3:-}" reason="" class="" text run_id ts
  local u="verdict <run_dir> <ac_id> <NOT_VERIFIABLE|BLOCKED> --reason <text> [--classification <c>]"
  { [ -n "$run_dir" ] && [ -n "$ac_id" ] && [ -n "$verdict" ]; } || usage "$u"
  shift 3
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --reason)         [ "$#" -ge 2 ] || usage "--reason needs a value";         reason="$2"; shift 2 ;;
      --classification) [ "$#" -ge 2 ] || usage "--classification needs a value"; class="$2";  shift 2 ;;
      *)                usage "$u (unknown argument $1)" ;;
    esac
  done
  case "$verdict" in
    PASS) diag "a PASS can only come from an observed Then — run the specs through walk [pass_requires_observation]"; exit 2 ;;
    FAIL) diag "a FAIL can only come from an observed, contradicted Then — run the specs through walk [fail_requires_observation]"; exit 2 ;;
    NOT_VERIFIABLE)
      [ -z "$class" ] || { diag "NOT_VERIFIABLE carries no classification (the schema forbids one) [classification_not_allowed]"; exit 2; } ;;
    BLOCKED)
      [ -n "$class" ] || class="ENVIRONMENT_ISSUE"
      case "$class" in
        REAL_BUG|DISCOVERY_GAP|ENVIRONMENT_ISSUE) ;;
        *) diag "classification must be one of REAL_BUG, DISCOVERY_GAP, ENVIRONMENT_ISSUE; got '$class' [classification_unknown]"; exit 2 ;;
      esac ;;
    *) diag "verdict must be NOT_VERIFIABLE or BLOCKED; got '$verdict' [verdict_unknown]"; exit 2 ;;
  esac
  [ -n "$reason" ] || { diag "a non-PASS verdict needs a non-empty --reason [reason_required]"; exit 2; }
  [ -d "$run_dir" ] || { diag "run dir not found at $run_dir [run_dir_missing]"; exit 2; }
  [ -f "$run_dir/acs.json" ] || { diag "no acs.json in $run_dir — run preflight first [acs_missing]"; exit 2; }
  text="$(jq -r --arg id "$ac_id" '.acs[] | select(.ac_id == $id) | .text' "$run_dir/acs.json" 2>/dev/null | head -1)"
  [ -n "$text" ] || { diag "'$ac_id' is not an acceptance criterion of this run (see $run_dir/acs.json) [ac_id_unknown]"; exit 2; }
  run_id="$(run_id_of "$run_dir")"
  ts="$(now_ts)"
  jq -cn --arg ts "$ts" --arg run_id "$run_id" --arg ac_id "$ac_id" --arg text "$text" \
     --arg verdict "$verdict" --arg reason "$reason" --arg class "$class" '
    {schema_version: 1, ts: $ts, run_id: $run_id, event: "ac", ac_id: $ac_id, text: $text,
     scope: "ticket", verdict: $verdict,
     classification: (if $class == "" then null else $class end),
     steps: [], artifacts: [], reason: $reason}' \
    | bash "$HELPERS" evidence-append "$run_dir" - >/dev/null
}

# --------------------------------------------------------------------------- #
# finish <run_dir> [--status completed|aborted]
# --------------------------------------------------------------------------- #
# Appends `run_end` (status only — the validator rejects any counts key on it), rebuilds summary.md,
# and prints the derived counts row. That printed row is what the agent COPIES into
# VERIFY_RESULT.counts; it never tallies.
finish_cmd() {
  local run_dir="${1:-}" status="completed" run_id ts row
  [ -n "$run_dir" ] || usage "finish <run_dir> [--status completed|aborted]"
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --status) [ "$#" -ge 2 ] || usage "--status needs a value"; status="$2"; shift 2 ;;
      *)        usage "finish <run_dir> [--status completed|aborted] (unknown argument $1)" ;;
    esac
  done
  case "$status" in
    completed|aborted) ;;
    *) usage "--status must be completed or aborted; got '$status'" ;;
  esac
  [ -d "$run_dir" ] || { diag "run dir not found at $run_dir [run_dir_missing]"; exit 2; }
  run_id="$(run_id_of "$run_dir")"
  ts="$(now_ts)"
  jq -cn --arg ts "$ts" --arg run_id "$run_id" --arg status "$status" \
    '{schema_version: 1, ts: $ts, run_id: $run_id, event: "run_end", status: $status}' \
    | bash "$HELPERS" evidence-append "$run_dir" - >/dev/null || die "run_end line was refused"
  bash "$HELPERS" summary-build "$run_dir" || die "summary-build failed for $run_dir"
  row="$(grep '^PASS: ' "$run_dir/summary.md" 2>/dev/null | head -1)"
  [ -n "$row" ] || die "summary.md carries no counts row"
  printf '%s\n' "$row"
}

# --------------------------------------------------------------------------- #
# walk <run_dir> [--repo <dir>] [--base-url <url>]
# --------------------------------------------------------------------------- #
# The ONLY source of PASS and FAIL. (1) base_url from the flag, else the contract through the reader;
# (2) `npx --no-install playwright --version` FROM THE REPO — non-zero ⇒ a BLOCKED
# [playwright_unavailable] line for every AC still without a verdict, exit 3 (the app was reachable,
# the harness was not); (3) no `<run_dir>/specs/*.spec.*` at all ⇒ BLOCKED [no_spec] for those ACs,
# exit 0, no browser launched; (4) generate `<run_dir>/playwright.config.mjs` and run the specs with
# the JSON reporter — the run's EXIT STATUS IS IGNORED, the reporter file is the oracle (stdout/stderr
# kept beside it); (5) ingest: every spec whose title starts `[ACn]` becomes one `ac` line — the LAST
# result of the test, mapped per docs/RESULT_SCHEMAS.md §VERIFY_RESULT "Specs and reporter ingest";
# every attachment is copied (path) or decoded (base64 body — the template's `page-body`) into
# `<run_dir>/artifacts/<ac_id>/` and recorded RELATIVE to the run dir; an AC with neither a spec nor
# an existing `ac` line ⇒ BLOCKED [no_spec]. Every line goes through evidence-append.
walk_cmd() {
  local run_dir="" repo_arg="" base_url="" repo run_id rc contract nspec cfg pw_out pw_err
  local u="walk <run_dir> [--repo <dir>] [--base-url <url>]"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --repo)     [ "$#" -ge 2 ] || usage "--repo needs a value";     repo_arg="$2"; shift 2 ;;
      --base-url) [ "$#" -ge 2 ] || usage "--base-url needs a value"; base_url="$2"; shift 2 ;;
      -*)         usage "$u (unknown flag $1)" ;;
      *)          if [ -z "$run_dir" ]; then run_dir="$1"; shift; else usage "walk takes ONE run dir"; fi ;;
    esac
  done
  [ -n "$run_dir" ] || usage "$u"
  command -v jq >/dev/null 2>&1 || die "jq is required [jq_unavailable]"
  [ -f "$HELPERS" ] || die "sibling verify-helpers.sh not found at $HELPERS"
  [ -d "$run_dir" ] || { diag "run dir not found at $run_dir [run_dir_missing]"; exit 2; }
  [ -f "$run_dir/acs.json" ] || { diag "no acs.json in $run_dir — run preflight first [acs_missing]"; exit 2; }
  run_dir="$(cd "$run_dir" && pwd)"
  repo="$(resolve_repo "$repo_arg")" || exit 2
  run_id="$(run_id_of "$run_dir")"
  rerr="$(mktemp "${TMPDIR:-/tmp}/verify-run.XXXXXX")" || die "mktemp failed"
  trap 'rm -f "$rerr" 2>/dev/null' EXIT

  # (1) base_url — the flag wins; else the contract THROUGH the reader (never re-parsed).
  if [ -z "$base_url" ]; then
    [ -f "$READER" ] || die "sibling read-verify.sh not found at $READER"
    contract="$(bash "$READER" --repo "$repo" 2>"$rerr")"
    [ -n "$contract" ] && base_url="$(printf '%s' "$contract" | jq -r '.base_url // empty' 2>/dev/null)"
    if [ -z "$base_url" ]; then
      cat "$rerr" >&2
      diag "no base_url: pass --base-url or fix .agent/verify.json [base_url_unresolved]"
      exit 2
    fi
  fi

  # (2) the harness, resolved FROM THE REPO exactly as a user project would resolve it.
  ( cd "$repo" && npx --no-install playwright --version ) >/dev/null 2>"$rerr"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    diag "npx playwright is not resolvable from $repo (rc=$rc): $(head -1 "$rerr") [playwright_unavailable]"
    walk_block_remaining "$run_dir" "$run_id" "playwright_unavailable" "ENVIRONMENT_ISSUE"
    exit 3
  fi

  # (3) no specs at all ⇒ nothing to observe; say so per AC and stop WITHOUT launching a browser.
  nspec=0
  [ -d "$run_dir/specs" ] && nspec="$(find "$run_dir/specs" -type f \( -name '*.spec.ts' -o -name '*.spec.js' -o -name '*.spec.mjs' \) 2>/dev/null | grep -c .)"
  if [ "$nspec" -eq 0 ]; then
    diag "no *.spec.* under $run_dir/specs — every remaining AC is BLOCKED [no_spec]"
    walk_block_remaining "$run_dir" "$run_id" "no_spec" "ENVIRONMENT_ISSUE"
    exit 0
  fi

  # (4) the per-run config (paths JSON-quoted, never interpolated raw) and the run.
  cfg="$run_dir/playwright.config.mjs"
  {
    echo "// generated by verify-run.sh walk — one config per run; the reporter file is the oracle."
    echo "export default {"
    echo "  testDir: $(jq -rn --arg v "$run_dir/specs" '$v | @json'),"
    echo "  outputDir: $(jq -rn --arg v "$run_dir/test-results" '$v | @json'),"
    echo "  reporter: [['json', { outputFile: $(jq -rn --arg v "$run_dir/report.json" '$v | @json') }]],"
    echo "  workers: 1,"
    echo "  retries: 0,"
    echo "  timeout: 30000,"
    echo "  use: { baseURL: $(jq -rn --arg v "$base_url" '$v | @json'), screenshot: 'on', trace: 'on', video: 'off' },"
    echo "};"
  } > "$cfg" || die "cannot write $cfg"
  pw_out="$run_dir/playwright.stdout"; pw_err="$run_dir/playwright.stderr"
  rm -f "$run_dir/report.json"
  ( cd "$repo" && npx --no-install playwright test --config "$cfg" ) >"$pw_out" 2>"$pw_err"
  rc=$?
  diag "playwright test exited $rc (ignored — the reporter decides); output beside report.json"
  if [ ! -s "$run_dir/report.json" ]; then
    diag "playwright wrote no report at $run_dir/report.json: $(head -1 "$pw_err") [reporter_missing]"
    walk_block_remaining "$run_dir" "$run_id" "reporter_missing: $(head -1 "$pw_err" | cut -c1-200)" "ENVIRONMENT_ISSUE"
    exit 3
  fi

  # (5) ingest.
  walk_session_expired=0
  walk_ingest "$run_dir" "$run_id" || exit 1
  walk_block_remaining "$run_dir" "$run_id" "no_spec" "ENVIRONMENT_ISSUE"
  echo "report=$run_dir/report.json"
  # AC5: a genuine mid-run session expiry (a repeated response-40[13] signal) was detected and forced
  # onto the affected ACs by walk_ingest — a distinct exit code from the normal 0, so the caller (the
  # qa-executor's VERIFY MODE) can branch to a pause instead of `finish`.
  [ "$walk_session_expired" -eq 1 ] && exit 5
  return 0
}

# walk_append_ac <run_dir> <run_id> <ac_id> <verdict> <class|""> <reason> <steps_json> <artifacts_json>
# — text from acs.json by ac_id (an id the ticket does not have is named and skipped); one
# evidence-append; the verdict echoed on stdout as `<ac_id> <verdict>`.
walk_append_ac() {
  local run_dir="$1" run_id="$2" ac_id="$3" verdict="$4" class="$5" reason="$6" steps="$7" arts="$8" text ts
  text="$(jq -r --arg id "$ac_id" '.acs[] | select(.ac_id == $id) | .text' "$run_dir/acs.json" 2>/dev/null | head -1)"
  if [ -z "$text" ]; then
    diag "spec [$ac_id] names no acceptance criterion of this run (see $run_dir/acs.json) — skipped [ac_id_unknown]"
    return 0
  fi
  ts="$(now_ts)"
  jq -cn --arg ts "$ts" --arg run_id "$run_id" --arg ac_id "$ac_id" --arg text "$text" \
     --arg verdict "$verdict" --arg reason "$reason" --arg class "$class" \
     --argjson steps "$steps" --argjson arts "$arts" '
    {schema_version: 1, ts: $ts, run_id: $run_id, event: "ac", ac_id: $ac_id, text: $text,
     scope: "ticket", verdict: $verdict,
     classification: (if $class == "" then null else $class end),
     steps: $steps, artifacts: $arts}
    + (if $reason == "" then {} else {reason: $reason} end)' \
    | bash "$HELPERS" evidence-append "$run_dir" - >/dev/null \
    || { diag "ac line for $ac_id was refused (see $run_dir/rejected.jsonl) [append_refused]"; return 1; }
  echo "$ac_id $verdict"
}

# walk_block_remaining <run_dir> <run_id> <reason> <class> — a BLOCKED line for every ac_id in
# acs.json (file order) that has NO `ac` line yet; ACs already decided (a NOT_VERIFIABLE recorded by
# `verdict`, a PASS/FAIL just ingested) are left alone.
walk_block_remaining() {
  local run_dir="$1" run_id="$2" reason="$3" class="$4" done_ids id
  done_ids="[]"
  [ -f "$run_dir/evidence.jsonl" ] && done_ids="$(jq -cs '[.[] | select(.event == "ac") | .ac_id]' "$run_dir/evidence.jsonl" 2>/dev/null)"
  [ -n "$done_ids" ] || done_ids="[]"
  for id in $(jq -r --argjson done "$done_ids" '.acs[].ac_id | select(. as $i | ($done | index($i)) == null)' "$run_dir/acs.json"); do
    walk_append_ac "$run_dir" "$run_id" "$id" "BLOCKED" "$class" "$reason" "[]" "[]" || return 1
  done
  return 0
}

# walk_ingest <run_dir> <run_id> — report.json → one `ac` line per `[ACn]` spec. Reporter → verdict
# (the LAST result of the LAST test of the spec):
#   passed                                        ⇒ PASS
#   skipped                                       ⇒ BLOCKED ENVIRONMENT_ISSUE  spec_skipped
#   no result at all                              ⇒ BLOCKED ENVIRONMENT_ISSUE  spec_not_run
#   failed/timedOut/interrupted, message names a navigation/connection failure
#     (net::ERR_, ECONNREFUSED, a page.goto timeout)⇒ BLOCKED ENVIRONMENT_ISSUE  <first error line>
#   any other failed/timedOut/interrupted         ⇒ FAIL    REAL_BUG           <first error line>
# `reason` is the FIRST line of errors[0].message with ANSI stripped (falls back to `spec_<status>`).
# walk_apply_expiry_override <run_dir> <run_id> <min_ordinal> — AC5. `min_ordinal` is the SMALLEST
# AC ORDINAL (the integer parsed from `[ACn]`, never file/report order) among the specs whose ingested
# attachments carried a `response-40[13]` signal. Forces `AC<min_ordinal>` to
# BLOCKED/ENVIRONMENT_ISSUE/session_expired — discarding whatever the normal ingest just recorded for
# it (the append-only store makes THIS new line the latest-per-ac_id winner) — and forces every
# `AC<k>` with `k > min_ordinal` (from acs.json's OWN ac_id list, so an AC with no spec at all is
# included) to BLOCKED/ENVIRONMENT_ISSUE/run_paused_session_expired, regardless of any Playwright
# result of its own. ACs with a smaller ordinal are untouched. Appends exactly ONE `{event:auth,
# state:expired}` line and calls `pause_cmd … --reason session_expired` exactly ONCE, never per AC.
walk_apply_expiry_override() {
  local run_dir="$1" run_id="$2" min_n="$3" id num ts
  for id in $(jq -r '.acs[].ac_id' "$run_dir/acs.json" 2>/dev/null); do
    num="${id#AC}"
    case "$num" in ''|*[!0-9]*) continue ;; esac
    if [ "$num" -eq "$min_n" ]; then
      walk_append_ac "$run_dir" "$run_id" "$id" "BLOCKED" "ENVIRONMENT_ISSUE" "session_expired" "[]" "[]" \
        || return 1
    elif [ "$num" -gt "$min_n" ]; then
      walk_append_ac "$run_dir" "$run_id" "$id" "BLOCKED" "ENVIRONMENT_ISSUE" "run_paused_session_expired" "[]" "[]" \
        || return 1
    fi
  done
  ts="$(now_ts)"
  jq -cn --arg ts "$ts" --arg run_id "$run_id" \
    '{schema_version: 1, ts: $ts, run_id: $run_id, event: "auth", state: "expired"}' \
    | bash "$HELPERS" evidence-append "$run_dir" - >/dev/null || die "auth expired line was refused"
  pause_cmd "$run_dir" --reason session_expired || die "pause (session_expired) failed for $run_dir"
  return 0
}

walk_ingest() {
  local run_dir="$1" run_id="$2" specs spec ac_id rstatus message steps verdict class reason arts n
  local has_expiry min_n num
  specs="$(mktemp "${TMPDIR:-/tmp}/verify-walk.XXXXXX")" || die "mktemp failed"
  jq -c '
    [.. | objects | select(has("specs") and (.specs | type == "array")) | .specs[]]
    | map(select((.title // "") | test("^\\[AC[0-9]+\\]")))
    | map(. as $s | ($s.tests // [] | last) as $t | (($t.results // []) | last) as $r
        | {ac_id: ($s.title | capture("^\\[(?<id>AC[0-9]+)\\]").id),
           rstatus: ($r.status // "missing"),
           message: ((($r.errors // [])[0].message // $r.error.message // "")
                     | gsub("\u001b\\[[0-9;]*[A-Za-z]"; "") | (split("\n")[0] // "")
                     | gsub("^[[:space:]]+|[[:space:]]+$"; "")),
           steps: [($r.steps // [])[] | .title // empty],
           attachments: [($r.attachments // [])[]
                         | {name: (.name // "attachment"), contentType: (.contentType // ""),
                            path: (.path // ""), body: (.body // "")}]})
    | .[]' "$run_dir/report.json" > "$specs" 2>"$specs.err"
  if [ $? -ne 0 ]; then
    diag "report.json is not a Playwright JSON report: $(head -1 "$specs.err") [reporter_unreadable]"
    rm -f "$specs" "$specs.err"; return 1
  fi
  n="$(grep -c . "$specs")"
  diag "ingesting $n [ACn] spec result(s) from report.json"
  while IFS= read -r spec; do
    [ -n "$spec" ] || continue
    ac_id="$(printf '%s' "$spec" | jq -r '.ac_id')"
    rstatus="$(printf '%s' "$spec" | jq -r '.rstatus')"
    message="$(printf '%s' "$spec" | jq -r '.message')"
    steps="$(printf '%s' "$spec" | jq -c '.steps')"
    case "$rstatus" in
      passed)  verdict="PASS";    class="";                  reason="" ;;
      skipped) verdict="BLOCKED"; class="ENVIRONMENT_ISSUE"; reason="spec_skipped" ;;
      missing) verdict="BLOCKED"; class="ENVIRONMENT_ISSUE"; reason="spec_not_run" ;;
      *)
        [ -n "$message" ] || message="spec_$rstatus"
        if printf '%s' "$message" | grep -qE 'net::ERR_|ECONNREFUSED|page\.goto.*[Tt]imeout|[Tt]imeout.*page\.goto'; then
          verdict="BLOCKED"; class="ENVIRONMENT_ISSUE"
        else
          verdict="FAIL"; class="REAL_BUG"
        fi
        reason="$message" ;;
    esac
    arts="$(walk_copy_attachments "$run_dir" "$ac_id" "$spec")"
    walk_append_ac "$run_dir" "$run_id" "$ac_id" "$verdict" "$class" "$reason" "$steps" "$arts" || { rm -f "$specs" "$specs.err"; return 1; }
    # AC5: a `response-40[13]` attachment on THIS spec's result signals a session that died mid-test
    # (distinct from the anonymous-redirect 302 the app also emits). Collect the AC ORDINAL — never
    # this loop's own file/report order — for the override pass below.
    has_expiry="$(printf '%s' "$spec" | jq -r '[(.attachments // [])[].name // ""] | any(test("^response-40[13]"))' 2>/dev/null)"
    if [ "$has_expiry" = "true" ]; then
      num="${ac_id#AC}"
      case "$num" in ''|*[!0-9]*) ;; *) printf '%s\n' "$num" >> "$specs.expiry" ;; esac
    fi
  done < "$specs"
  if [ -s "$specs.expiry" ]; then
    min_n="$(sort -n "$specs.expiry" | head -1)"
    walk_apply_expiry_override "$run_dir" "$run_id" "$min_n" || { rm -f "$specs" "$specs.err" "$specs.expiry"; return 1; }
    walk_session_expired=1
  fi
  rm -f "$specs" "$specs.err" "$specs.expiry"
  return 0
}

# walk_copy_attachments <run_dir> <ac_id> <spec_json> — every attachment into artifacts/<ac_id>/:
# a `path` attachment is copied under its basename (an index prefix on collision); a `body`
# attachment (base64 in the report — the template's page-body / response-<status>) is decoded to
# `<name>.<ext>` by contentType. Prints the JSON array of RELATIVE paths (what the ac line records).
walk_copy_attachments() {
  local run_dir="$1" ac_id="$2" spec="$3" dest i name ctype path body ext file rel list
  dest="$run_dir/artifacts/$ac_id"
  mkdir -p "$dest" || die "cannot create $dest"
  list="$(mktemp "${TMPDIR:-/tmp}/verify-arts.XXXXXX")" || die "mktemp failed"
  printf '%s' "$spec" | jq -c '.attachments[]' > "$list.in"
  i=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    i=$((i+1))
    name="$(printf '%s' "$line" | jq -r '.name' | tr -d '\n' | tr -c 'A-Za-z0-9._-' '_')"
    ctype="$(printf '%s' "$line" | jq -r '.contentType')"
    path="$(printf '%s' "$line" | jq -r '.path')"
    body="$(printf '%s' "$line" | jq -r '.body')"
    if [ -n "$path" ]; then
      [ -f "$path" ] || { diag "attachment '$name' of $ac_id names a missing file $path — skipped"; continue; }
      file="$(basename "$path")"
      [ -e "$dest/$file" ] && file="$i-$file"
      cp "$path" "$dest/$file" 2>/dev/null || { diag "could not copy $path — skipped"; continue; }
    elif [ -n "$body" ]; then
      case "$ctype" in
        text/html*)        ext="html" ;;
        text/markdown*)    ext="md" ;;
        text/*)            ext="txt" ;;
        application/json*) ext="json" ;;
        image/png*)        ext="png" ;;
        application/zip*)  ext="zip" ;;
        *)                 ext="bin" ;;
      esac
      file="$name.$ext"
      [ -e "$dest/$file" ] && file="$i-$file"
      printf '%s' "$body" | python3 -c 'import sys, base64; sys.stdout.buffer.write(base64.b64decode(sys.stdin.read()))' > "$dest/$file" 2>/dev/null \
        || { diag "could not decode attachment '$name' of $ac_id — skipped"; rm -f "$dest/$file"; continue; }
    else
      continue
    fi
    rel="artifacts/$ac_id/$file"
    printf '%s\n' "$rel" >> "$list"
  done < "$list.in"
  jq -R . "$list" | jq -sc .
  rm -f "$list" "$list.in"
}

main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    acs)        acs_cmd "$@" ;;
    auth-check) auth_check_cmd "$@" ;;
    preflight)  preflight_cmd "$@" ;;
    walk)       walk_cmd "$@" ;;
    verdict)    verdict_cmd "$@" ;;
    finish)     finish_cmd "$@" ;;
    pause)      pause_cmd "$@" ;;
    ""|-h|--help)
      grep -E '^#   [a-z]' "$0" | sed 's/^#   /  /'
      ;;
    *) die "unknown subcommand: $cmd (try --help)" ;;
  esac
}

main "$@"
