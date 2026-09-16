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
#   preflight  <ticket> [--branch <name>] [--repo <dir>] [--notify]  # contract read → run dir + run_start → assert-non-prod → env line; `--notify` touches <run_dir>/.notify-enabled (read by verify-helpers.sh's notify dispatch); prints `run_dir=<path>` LAST
#   auth-check <run_dir> [--repo <dir>]                              # auth.method none ⇒ no-op exit 0; else probe — authenticated ⇒ one `auth` line exit 0; else `auth`+`pause` lines, exit 4
#   pause      <run_dir> --reason <needs_auth|session_expired>       # append ONE `pause` line (the only place a pause line is ever written) + rebuild summary.md
#   notify-enable <run_dir>                                          # touch <run_dir>/.notify-enabled — the ONLY other place that marker is created (besides preflight --notify); used by the `--resume --notify` path, which never calls preflight
#   walk       <run_dir> [--repo <dir>] [--base-url <url>]           # generate the per-run Playwright config, run the `[ACn]` specs, ingest the reporter into `ac` lines
#   verdict    <run_dir> <ac_id> <NOT_VERIFIABLE|BLOCKED> --reason <text> [--classification <c>]   # append one browser-less `ac` line
#   finish     <run_dir> [--status completed|aborted]                # append run_end (NO counts), rebuild summary.md, print its counts row
#   impact diff            <run_dir> [--repo <dir>]                                 # mechanical: git diff --name-only base_sha...head_sha (from run_start) -> a JSON array of changed files
#   impact brief-surfaces  <run_dir> [--repo <dir>]                                 # best-effort: subsystem names from a matching .supervisor/jobs/done/ brief's Blast-Radius section - NEVER fails, [] when absent/omitted
#   impact record-surfaces <run_dir> <json|-> [--repo <dir>] [--impact-limit N] [--no-impact]
#                                                                                    # agent supplies {"surfaces":{"<name>":[file,...]},"unmapped":[file,...]}; recomputes `files` and
#                                                                                    # `brief_surfaces` itself and appends ONE impact_surfaces evidence line; --no-impact short-circuits
#                                                                                    # to a no-op (exit 0, nothing appended) - the whole impact pass skipped
#   impact prior-acs       <run_dir> [--repo <dir>] [--impact-limit N]              # mechanical: scans sibling .supervisor/verify/*/evidence.jsonl for latest-per-ac_id PASS lines whose
#                                                                                    # `surfaces` intersects this run's impact_surfaces, most-recent-first, bounded by the limit; a JSON array;
#                                                                                    # zero prior runs (fresh clone/worktree/CI) silently prints [], never fails
#   walk       <run_dir> [--repo <dir>] [--base-url <url>] [--scope ticket|impact] [--specs-dir <dir>] [--manifest <path>] [--report-name <name>]
#                                                                                    # generates the per-run config, runs the specs, ingests the reporter into `ac` lines (PASS/FAIL/BLOCKED);
#                                                                                    # --scope impact + --manifest <path> (array of {id, text, source, surfaces}) re-runs impact-scope specs
#                                                                                    # (prior-AC regression / smoke checks) instead of the ticket's own acs.json entries - every default is
#                                                                                    # backward-compatible with a plain ticket-scope walk
#   queue-reconcile-item <run_dir> --branch <name> [--repo <dir>]                   # item 07: reconciles ONE `/verify --folder` queue item's run dir against ground
#                                                                                    # truth — belief (the queue checkbox) is never trusted without this. Lives HERE
#                                                                                    # (not verify-helpers.sh) because it needs `git rev-parse` / --repo, which that
#                                                                                    # script deliberately does not have. Prints ONE compact JSON object and (bar
#                                                                                    # usage/missing-dir errors) ALWAYS exits 0 — this is an advisory read, never a
#                                                                                    # gate: {"status":"stale|done|paused|crashed|not_started","pause_reason":str|null,
#                                                                                    # "resume_ac_id":str|null,"old_sha":str|null,"new_sha":str|null}
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
  local ticket="" branch="" repo_arg="" notify=0 repo acs kind contract tokens
  local run_id run_dir base head_sha base_sha hash ts out rc reason
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --branch) [ "$#" -ge 2 ] || usage "--branch needs a value"; branch="$2"; shift 2 ;;
      --repo)   [ "$#" -ge 2 ] || usage "--repo needs a value";   repo_arg="$2"; shift 2 ;;
      --notify) notify=1; shift ;;
      -*)       usage "preflight <ticket> [--branch <name>] [--repo <dir>] [--notify] (unknown flag $1)" ;;
      *)        if [ -z "$ticket" ]; then ticket="$1"; shift; else usage "preflight takes ONE ticket"; fi ;;
    esac
  done
  [ -n "$ticket" ] || usage "preflight <ticket> [--branch <name>] [--repo <dir>] [--notify]"
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
  # `--notify` enablement is a FILESYSTEM marker, not an env var — see verify-helpers.sh's Notify
  # section header for why (the qa-executor's VERIFY MODE runs in a separate Task-spawned process
  # with no shared shell state with this main-thread invocation). Best-effort: a failed `touch`
  # degrades to no notifications, never to a preflight failure.
  [ "$notify" -eq 1 ] && { : > "$run_dir/.notify-enabled" 2>/dev/null || diag "could not create $run_dir/.notify-enabled — notifications will not fire for this run"; }
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
# notify-enable <run_dir>
# --------------------------------------------------------------------------- #
# The ONLY other place `<run_dir>/.notify-enabled` is created (besides `preflight --notify`).
# Exists for `/verify --resume <run_id> --notify` — the resume flow never calls `preflight` (a
# fresh run dir is never minted for a resume), so there is no other point where a `--notify` passed
# on that invocation could reach the marker verify-helpers.sh's notify dispatch reads. Idempotent —
# touching an already-enabled run is a no-op, not an error.
notify_enable_cmd() {
  local run_dir="${1:-}"
  [ -n "$run_dir" ] || usage "notify-enable <run_dir>"
  [ -d "$run_dir" ] || { diag "run dir not found at $run_dir [run_dir_missing]"; exit 2; }
  run_dir="$(cd "$run_dir" && pwd)"
  : > "$run_dir/.notify-enabled" || die "could not create $run_dir/.notify-enabled"
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
# impact <diff|brief-surfaces|record-surfaces|prior-acs> ...
# --------------------------------------------------------------------------- #
# The mechanical half of the impact pass (item 06) - the diff->surfaces CLASSIFICATION itself is
# agent-judgment work done by qa-executor's VERIFY MODE (reusing Phase 4 APP TOPOLOGY DETECTION
# prose, see Risk Assessment of the owning brief); this script owns only the raw facts: the diff
# listing, the brief's Blast-Radius text (when populated), recording the one `impact_surfaces`
# evidence line, and the bounded prior-AC scan across sibling run dirs.

# run_start_field <run_dir> <field> - the run_start line's <field>, empty when absent/unreadable.
run_start_field() {
  local run_dir="$1" field="$2"
  [ -f "$run_dir/evidence.jsonl" ] || { printf ''; return 0; }
  jq -r --arg f "$field" 'select(.event == "run_start") | .[$f] // empty' "$run_dir/evidence.jsonl" 2>/dev/null | head -1
}

# impact_diff_cmd <run_dir> [--repo <dir>] - git diff --name-only base_sha...head_sha from the run's
# own run_start line; prints a JSON array (possibly empty) - NEVER fails on an unresolvable diff, an
# empty array is printed instead (same fail-safe-advisory convention as preflight's own diff.stat).
impact_diff_cmd() {
  local run_dir="" repo_arg="" repo base head files
  local u="impact diff <run_dir> [--repo <dir>]"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --repo) [ "$#" -ge 2 ] || usage "--repo needs a value"; repo_arg="$2"; shift 2 ;;
      -*)     usage "$u (unknown flag $1)" ;;
      *)      if [ -z "$run_dir" ]; then run_dir="$1"; shift; else usage "impact diff takes ONE run dir"; fi ;;
    esac
  done
  [ -n "$run_dir" ] || usage "$u"
  [ -d "$run_dir" ] || { diag "run dir not found at $run_dir [run_dir_missing]"; exit 2; }
  run_dir="$(cd "$run_dir" && pwd)"
  repo="$(resolve_repo "$repo_arg")" || exit 2
  base="$(run_start_field "$run_dir" base_sha)"
  head="$(run_start_field "$run_dir" head_sha)"
  files="[]"
  if [ -n "$base" ] && [ -n "$head" ]; then
    files="$(git -C "$repo" diff --name-only "$base...$head" 2>/dev/null | jq -R . 2>/dev/null | jq -sc . 2>/dev/null)"
    [ -n "$files" ] || files="[]"
  fi
  printf '%s\n' "$files"
}

# impact_brief_surfaces_cmd <run_dir> [--repo <dir>] - best-effort, NEVER fails: finds a
# .supervisor/jobs/done/*.md brief whose `**Source requirement:**` line names this run's ticket_path
# (the header back-reference), extracts the `- ` bullets under a Blast-Radius/Blast Radius heading
# (case-insensitive) up to the next `## `/`### ` header, and prints them as a JSON array of
# subsystem-name strings. No matching brief, or an omitted/absent section -> `[]`.
impact_brief_surfaces_cmd() {
  local run_dir="" repo_arg="" repo ticket brief names
  local u="impact brief-surfaces <run_dir> [--repo <dir>]"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --repo) [ "$#" -ge 2 ] || usage "--repo needs a value"; repo_arg="$2"; shift 2 ;;
      -*)     usage "$u (unknown flag $1)" ;;
      *)      if [ -z "$run_dir" ]; then run_dir="$1"; shift; else usage "impact brief-surfaces takes ONE run dir"; fi ;;
    esac
  done
  [ -n "$run_dir" ] || usage "$u"
  [ -d "$run_dir" ] || { diag "run dir not found at $run_dir [run_dir_missing]"; exit 2; }
  run_dir="$(cd "$run_dir" && pwd)"
  repo="$(resolve_repo "$repo_arg")" || exit 2
  ticket="$(run_start_field "$run_dir" ticket_path)"
  names="[]"
  if [ -n "$ticket" ] && [ -d "$repo/.supervisor/jobs/done" ]; then
    brief="$(grep -rlF -- "**Source requirement:** $ticket" "$repo/.supervisor/jobs/done" 2>/dev/null | head -1)"
    if [ -n "$brief" ] && [ -f "$brief" ]; then
      names="$(awk '
        function flush() { if (cur != "") print cur; cur = "" }
        BEGIN { on = 0 }
        /^##+ / {
          if (on) { flush(); on = 0; exit }
          h = tolower($0); sub(/^##+[ \t]+/, "", h); gsub(/[ \t\r]+$/, "", h)
          if (h ~ /blast.radius/) { on = 1 }
          next
        }
        on && /^- / { flush(); cur = substr($0, 3); next }
        on && /^[ \t]+[^ \t]/ && cur != "" { line = $0; sub(/^[ \t]+/, "", line); cur = cur " " line; next }
        on && /^[ \t\r]*$/ { next }
        on { flush() }
        END { flush() }
      ' "$brief" 2>/dev/null | tr -d '\r' | sed -E 's/^[[:space:]]*//; s/[[:space:]]+$//' | grep -v '^[[:space:]]*$' \
        | jq -R . 2>/dev/null | jq -sc . 2>/dev/null)"
      [ -n "$names" ] || names="[]"
    fi
  fi
  printf '%s\n' "$names"
}

# impact_record_surfaces_cmd <run_dir> <json|-> [--repo <dir>] [--impact-limit N] [--no-impact]
# The agent supplies its own classification (surfaces -> files, unmapped); this recomputes `files`
# (the mechanical diff listing) and `brief_surfaces` (best-effort) ITSELF rather than trusting the
# agent's copy, merges the brief-sourced names into `surfaces` (each an empty file list unless the
# agent's own classification already named files for it), and appends ONE `impact_surfaces` line.
# `--no-impact` is a pure no-op: exit 0, nothing read, nothing appended - the whole pass skipped.
impact_record_surfaces_cmd() {
  local run_dir="" input="" repo_arg="" limit=10 no_impact=0 repo json files brief_names ts run_id merged uncovered
  local u="impact record-surfaces <run_dir> <json|-> [--repo <dir>] [--impact-limit N] [--no-impact]"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --repo)          [ "$#" -ge 2 ] || usage "--repo needs a value";          repo_arg="$2"; shift 2 ;;
      --impact-limit)  [ "$#" -ge 2 ] || usage "--impact-limit needs a value";  limit="$2";    shift 2 ;;
      --no-impact)     no_impact=1; shift ;;
      -)               if [ -z "$run_dir" ]; then run_dir="$1"; shift; else input="$1"; shift; fi ;;
      -*)              usage "$u (unknown flag $1)" ;;
      *)
        if [ -z "$run_dir" ]; then run_dir="$1"; shift;
        elif [ -z "$input" ]; then input="$1"; shift;
        else usage "impact record-surfaces takes ONE run dir and ONE json argument"; fi ;;
    esac
  done
  [ -n "$run_dir" ] || usage "$u"
  if [ "$no_impact" -eq 1 ]; then return 0; fi
  [ -n "$input" ] || usage "$u"
  case "$limit" in ''|*[!0-9]*) usage "--impact-limit must be a non-negative integer, got '$limit'" ;; esac
  if [ "$input" = "-" ]; then json="$(cat)"; else json="$input"; fi
  [ -n "$json" ] || die "impact record-surfaces: empty record"
  [ -d "$run_dir" ] || { diag "run dir not found at $run_dir [run_dir_missing]"; exit 2; }
  run_dir="$(cd "$run_dir" && pwd)"
  repo="$(resolve_repo "$repo_arg")" || exit 2
  run_id="$(run_id_of "$run_dir")"
  files="$(impact_diff_cmd "$run_dir" --repo "$repo")"
  brief_names="$(impact_brief_surfaces_cmd "$run_dir" --repo "$repo")"
  ts="$(now_ts)"
  merged="$(printf '%s' "$json" | jq -c --argjson files "$files" --argjson brief "$brief_names" --argjson limit "$limit" '
    (.surfaces // {}) as $s
    | (.unmapped // []) as $u
    | ($s + (reduce ($brief[]?) as $b ({}; . + {($b): ($s[$b] // [])}))) as $merged
    | {surfaces: $merged, unmapped: $u, files: $files, brief_surfaces: $brief, limit: $limit}' 2>/dev/null)"
  [ -n "$merged" ] || die "impact record-surfaces: could not build the merged record (malformed input JSON?)"
  # Mechanical completeness check — never trust the agent's classification alone:
  # every file in the recomputed diff list ($files) must be covered by either a
  # surface bucket or unmapped. A gap here means a file was silently dropped by
  # the classifier (neither named nor listed as unmapped), which would violate
  # AC1 ("every changed file with either a surface or unmapped, never guessed").
  # Self-heal, don't fail: this pass is advisory/best-effort (SKILL.md §9,
  # RESULT_SCHEMAS.md) and must never block the ticket's own verify score, so a
  # classification gap folds into `unmapped` (deduped) instead of dying — the
  # invariant is never-silently-dropped, not never-imperfectly-classified.
  uncovered="$(printf '%s' "$merged" | jq -c '(.files - (([.surfaces[]?] | add // []) + .unmapped))')"
  if [ "$uncovered" != "[]" ]; then
    merged="$(printf '%s' "$merged" | jq -c --argjson uncovered "$uncovered" '.unmapped = ((.unmapped + $uncovered) | unique)')"
  fi
  printf '%s\n' "$merged" | jq -c --arg ts "$ts" --arg run_id "$run_id" \
    '{schema_version: 1, ts: $ts, run_id: $run_id, event: "impact_surfaces"} + .' \
    | bash "$HELPERS" evidence-append "$run_dir" - >/dev/null || die "impact_surfaces line was refused (see $run_dir/rejected.jsonl)"
}

# impact_prior_acs_cmd <run_dir> [--repo <dir>] [--impact-limit N] - reads this run's OWN
# impact_surfaces line for its surface-name set, scans every SIBLING run dir's evidence.jsonl (never
# this run itself) for the latest-per-ac_id line whose verdict is PASS and whose (optional) `surfaces`
# intersects that set, sorts the matches most-recent-first by run_id (timestamp-prefixed, so a lexical
# sort is a chronological sort), and bounds them to the limit (the flag wins over the value already
# recorded on the impact_surfaces line, which wins over the default of 10). Zero prior runs (a fresh
# clone/worktree/CI, where .supervisor/verify/ never existed) prints `[]` and never fails.
impact_prior_acs_cmd() {
  local run_dir="" repo_arg="" limit="" self_id surfaces_json limit_from_line verify_root d evid rid candidates rc
  local u="impact prior-acs <run_dir> [--repo <dir>] [--impact-limit N]"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --repo)         [ "$#" -ge 2 ] || usage "--repo needs a value";         repo_arg="$2"; shift 2 ;;
      --impact-limit) [ "$#" -ge 2 ] || usage "--impact-limit needs a value"; limit="$2";    shift 2 ;;
      -*)             usage "$u (unknown flag $1)" ;;
      *)              if [ -z "$run_dir" ]; then run_dir="$1"; shift; else usage "impact prior-acs takes ONE run dir"; fi ;;
    esac
  done
  [ -n "$run_dir" ] || usage "$u"
  [ -d "$run_dir" ] || { diag "run dir not found at $run_dir [run_dir_missing]"; exit 2; }
  run_dir="$(cd "$run_dir" && pwd)"
  : "${repo_arg:-}"   # --repo accepted for CLI-shape parity; the scan is local to .supervisor/verify/
  self_id="$(run_id_of "$run_dir")"
  surfaces_json="$([ -f "$run_dir/evidence.jsonl" ] && jq -c 'select(.event == "impact_surfaces") | [.surfaces | keys[]]' "$run_dir/evidence.jsonl" 2>/dev/null | tail -1)"
  [ -n "$surfaces_json" ] || surfaces_json="[]"
  limit_from_line="$([ -f "$run_dir/evidence.jsonl" ] && jq -r 'select(.event == "impact_surfaces") | .limit // empty' "$run_dir/evidence.jsonl" 2>/dev/null | tail -1)"
  [ -n "$limit" ] || limit="${limit_from_line:-10}"
  case "$limit" in ''|*[!0-9]*) usage "--impact-limit must be a non-negative integer, got '$limit'" ;; esac
  verify_root="$(cd "$run_dir/.." && pwd)"
  candidates="$(mktemp "${TMPDIR:-/tmp}/verify-impact.XXXXXX")" || die "mktemp failed"
  : > "$candidates"
  for d in "$verify_root"/*/; do
    [ -d "$d" ] || continue
    d="${d%/}"
    rid="$(basename "$d")"
    [ "$rid" = "$self_id" ] && continue
    evid="$d/evidence.jsonl"
    [ -f "$evid" ] || continue
    jq -sc --argjson want "$surfaces_json" --arg rid "$rid" '
      def latest_by(f): group_by(f) | map(max_by(._i)) | sort_by(._i);
      (to_entries | map(.value + {_i: .key})) as $L
      | ([$L[] | select(.event == "ac")] | latest_by([.ac_id, .scope])) as $latest
      | $latest[]
      | select(.verdict == "PASS" and ((.surfaces // []) | length) > 0)
      | select((.surfaces // []) as $s | ($s | map(. as $one | ($want | index($one)) != null) | any))
      | {run_id: $rid, ac_id: .ac_id, text: .text, surfaces: (.surfaces // [])}
    ' "$evid" 2>/dev/null >> "$candidates"
  done
  jq -sc --argjson limit "$limit" 'sort_by(.run_id) | reverse | .[0:$limit]' "$candidates" 2>/dev/null
  rc=$?
  rm -f "$candidates"
  if [ "$rc" -ne 0 ]; then printf '[]\n'; fi
  return 0
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
# walk <run_dir> [--repo <dir>] [--base-url <url>] [--scope ticket|impact] [--specs-dir <dir>] [--manifest <path>] [--report-name <name>]
# --------------------------------------------------------------------------- #
# The ONLY source of PASS and FAIL. (1) base_url from the flag, else the contract through the reader;
# (2) `npx --no-install playwright --version` FROM THE REPO - non-zero => a BLOCKED
# [playwright_unavailable] line for every AC still without a verdict, exit 3 (the app was reachable,
# the harness was not); (3) no `<run_dir>/<specs_dir>/*.spec.*` at all => BLOCKED [no_spec] for those
# ACs, exit 0, no browser launched; (4) generate `<run_dir>/playwright.config.mjs` and run the specs
# with the JSON reporter - the run's EXIT STATUS IS IGNORED, the reporter file is the oracle
# (stdout/stderr kept beside it); (5) ingest: every spec whose title starts `[<id>]` becomes one `ac`
# line - the LAST result of the test, mapped per docs/RESULT_SCHEMAS.md SECTION VERIFY_RESULT "Specs
# and reporter ingest"; every attachment is copied (path) or decoded (base64 body - the template's
# `page-body`) into `<run_dir>/artifacts/<id>/` and recorded RELATIVE to the run dir; an id with
# neither a spec nor an existing `ac` line => BLOCKED [no_spec]. Every line goes through
# evidence-append.
#
# `--scope impact` + `--manifest <path>` (item 06, the impact pass): the manifest is a JSON array of
# `{id, text, source, surfaces}` objects (prior-AC regression / smoke-check specs authored by the
# qa-executor's VERIFY MODE step) - `text`/`source`/`surfaces` come from the manifest instead of
# acs.json, ids that never get a real spec are BLOCKED [no_spec] exactly as an unauthored ticket AC
# is, and the AC5 session-expiry override (a ticket-only, auth-flow concept) never runs on this path.
# Every other default (`--scope ticket`, `--specs-dir specs`, no `--manifest`, `report.json`) is
# byte-for-byte the pre-item-06 behavior.
walk_cmd() {
  local run_dir="" repo_arg="" base_url="" scope="ticket" specs_dir="specs" manifest="" report_name=""
  local repo run_id rc contract nspec cfg pw_out pw_err
  local u="walk <run_dir> [--repo <dir>] [--base-url <url>] [--scope ticket|impact] [--specs-dir <dir>] [--manifest <path>] [--report-name <name>]"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --repo)        [ "$#" -ge 2 ] || usage "--repo needs a value";        repo_arg="$2";    shift 2 ;;
      --base-url)    [ "$#" -ge 2 ] || usage "--base-url needs a value";    base_url="$2";    shift 2 ;;
      --scope)       [ "$#" -ge 2 ] || usage "--scope needs a value";       scope="$2";       shift 2 ;;
      --specs-dir)   [ "$#" -ge 2 ] || usage "--specs-dir needs a value";   specs_dir="$2";   shift 2 ;;
      --manifest)    [ "$#" -ge 2 ] || usage "--manifest needs a value";    manifest="$2";    shift 2 ;;
      --report-name) [ "$#" -ge 2 ] || usage "--report-name needs a value"; report_name="$2"; shift 2 ;;
      -*)            usage "$u (unknown flag $1)" ;;
      *)             if [ -z "$run_dir" ]; then run_dir="$1"; shift; else usage "walk takes ONE run dir"; fi ;;
    esac
  done
  [ -n "$run_dir" ] || usage "$u"
  case "$scope" in
    ticket|impact) ;;
    *) usage "$u (--scope must be ticket or impact, got '$scope')" ;;
  esac
  if [ -z "$report_name" ]; then
    if [ "$scope" = "impact" ]; then report_name="impact-report.json"; else report_name="report.json"; fi
  fi
  command -v jq >/dev/null 2>&1 || die "jq is required [jq_unavailable]"
  [ -f "$HELPERS" ] || die "sibling verify-helpers.sh not found at $HELPERS"
  [ -d "$run_dir" ] || { diag "run dir not found at $run_dir [run_dir_missing]"; exit 2; }
  if [ "$scope" = "ticket" ]; then
    [ -f "$run_dir/acs.json" ] || { diag "no acs.json in $run_dir - run preflight first [acs_missing]"; exit 2; }
  else
    [ -n "$manifest" ] && [ -f "$manifest" ] || { diag "impact-scope walk needs --manifest <path> naming the specs to run [manifest_missing]"; exit 2; }
  fi
  run_dir="$(cd "$run_dir" && pwd)"
  repo="$(resolve_repo "$repo_arg")" || exit 2
  run_id="$(run_id_of "$run_dir")"
  rerr="$(mktemp "${TMPDIR:-/tmp}/verify-run.XXXXXX")" || die "mktemp failed"
  trap 'rm -f "$rerr" 2>/dev/null' EXIT

  # (1) base_url - the flag wins; else the contract THROUGH the reader (never re-parsed).
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
    walk_block_remaining "$run_dir" "$run_id" "playwright_unavailable" "ENVIRONMENT_ISSUE" "$scope" "$manifest"
    exit 3
  fi

  # (3) no specs at all => nothing to observe; say so per id and stop WITHOUT launching a browser.
  nspec=0
  [ -d "$run_dir/$specs_dir" ] && nspec="$(find "$run_dir/$specs_dir" -type f \( -name '*.spec.ts' -o -name '*.spec.js' -o -name '*.spec.mjs' \) 2>/dev/null | grep -c .)"
  if [ "$nspec" -eq 0 ]; then
    diag "no *.spec.* under $run_dir/$specs_dir - every remaining id is BLOCKED [no_spec]"
    walk_block_remaining "$run_dir" "$run_id" "no_spec" "ENVIRONMENT_ISSUE" "$scope" "$manifest"
    exit 0
  fi

  # (4) the per-run config (paths JSON-quoted, never interpolated raw) and the run.
  cfg="$run_dir/playwright.config.mjs"
  {
    echo "// generated by verify-run.sh walk - one config per run; the reporter file is the oracle."
    echo "export default {"
    echo "  testDir: $(jq -rn --arg v "$run_dir/$specs_dir" '$v | @json'),"
    echo "  outputDir: $(jq -rn --arg v "$run_dir/test-results" '$v | @json'),"
    echo "  reporter: [['json', { outputFile: $(jq -rn --arg v "$run_dir/$report_name" '$v | @json') }]],"
    echo "  workers: 1,"
    echo "  retries: 0,"
    echo "  timeout: 30000,"
    echo "  use: { baseURL: $(jq -rn --arg v "$base_url" '$v | @json'), screenshot: 'on', trace: 'on', video: 'off' },"
    echo "};"
  } > "$cfg" || die "cannot write $cfg"
  pw_out="$run_dir/playwright.stdout"; pw_err="$run_dir/playwright.stderr"
  rm -f "$run_dir/$report_name"
  ( cd "$repo" && npx --no-install playwright test --config "$cfg" ) >"$pw_out" 2>"$pw_err"
  rc=$?
  diag "playwright test exited $rc (ignored - the reporter decides); output beside $report_name"
  if [ ! -s "$run_dir/$report_name" ]; then
    diag "playwright wrote no report at $run_dir/$report_name: $(head -1 "$pw_err") [reporter_missing]"
    walk_block_remaining "$run_dir" "$run_id" "reporter_missing: $(head -1 "$pw_err" | cut -c1-200)" "ENVIRONMENT_ISSUE" "$scope" "$manifest"
    exit 3
  fi

  # (5) ingest.
  walk_session_expired=0
  walk_ingest "$run_dir" "$run_id" "$run_dir/$report_name" "$scope" "$manifest" || exit 1
  walk_block_remaining "$run_dir" "$run_id" "no_spec" "ENVIRONMENT_ISSUE" "$scope" "$manifest"
  echo "report=$run_dir/$report_name"
  # AC5: a genuine mid-run session expiry (a repeated response-40[13] signal) was detected and forced
  # onto the affected ACs by walk_ingest - a distinct exit code from the normal 0, so the caller (the
  # qa-executor's VERIFY MODE) can branch to a pause instead of `finish`. Ticket-scope only.
  [ "$scope" = "ticket" ] && [ "$walk_session_expired" -eq 1 ] && exit 5
  return 0
}

# walk_append_ac <run_dir> <run_id> <ac_id> <verdict> <class|""> <reason> <steps_json> <artifacts_json> [<scope=ticket>] [<manifest>]
# - text (and, for an impact-scope manifest entry, `source`/`surfaces`) from acs.json by ac_id, or
# from the manifest by id when one is given (an id neither names is skipped); one evidence-append;
# the verdict echoed on stdout as `<ac_id> <verdict>`.
walk_append_ac() {
  local run_dir="$1" run_id="$2" ac_id="$3" verdict="$4" class="$5" reason="$6" steps="$7" arts="$8"
  local scope="${9:-ticket}" manifest="${10:-}" text source surfaces_json extra_json ts
  if [ -n "$manifest" ] && [ -f "$manifest" ]; then
    text="$(jq -r --arg id "$ac_id" '.[] | select(.id == $id) | .text' "$manifest" 2>/dev/null | head -1)"
    source="$(jq -r --arg id "$ac_id" '.[] | select(.id == $id) | .source // empty' "$manifest" 2>/dev/null | head -1)"
    surfaces_json="$(jq -c --arg id "$ac_id" '[.[] | select(.id == $id)][0].surfaces // empty' "$manifest" 2>/dev/null)"
    case "$surfaces_json" in ""|null) surfaces_json="" ;; esac
  else
    text="$(jq -r --arg id "$ac_id" '.acs[] | select(.ac_id == $id) | .text' "$run_dir/acs.json" 2>/dev/null | head -1)"
    source=""; surfaces_json=""
  fi
  if [ -z "$text" ]; then
    diag "spec [$ac_id] names no acceptance criterion of this run (scope=$scope; see $run_dir/acs.json or the manifest) - skipped [ac_id_unknown]"
    return 0
  fi
  ts="$(now_ts)"
  extra_json="{}"
  [ -n "$source" ] && extra_json="$(printf '%s' "$extra_json" | jq -c --arg s "$source" '. + {source: $s}')"
  [ -n "$surfaces_json" ] && extra_json="$(printf '%s' "$extra_json" | jq -c --argjson sf "$surfaces_json" '. + {surfaces: $sf}')"
  jq -cn --arg ts "$ts" --arg run_id "$run_id" --arg ac_id "$ac_id" --arg text "$text" \
     --arg verdict "$verdict" --arg reason "$reason" --arg class "$class" --arg scope "$scope" \
     --argjson steps "$steps" --argjson arts "$arts" --argjson extra "$extra_json" '
    {schema_version: 1, ts: $ts, run_id: $run_id, event: "ac", ac_id: $ac_id, text: $text,
     scope: $scope, verdict: $verdict,
     classification: (if $class == "" then null else $class end),
     steps: $steps, artifacts: $arts}
    + (if $reason == "" then {} else {reason: $reason} end)
    + $extra' \
    | bash "$HELPERS" evidence-append "$run_dir" - >/dev/null \
    || { diag "ac line for $ac_id was refused (see $run_dir/rejected.jsonl) [append_refused]"; return 1; }
  echo "$ac_id $verdict"
}

# walk_block_remaining <run_dir> <run_id> <reason> <class> [<scope=ticket>] [<manifest>] - a BLOCKED
# line for every id (acs.json's ac_id list, or the manifest's id list when one is given) that has NO
# `ac` line YET IN THIS SCOPE (a ticket id and an impact id of the same string are tracked
# independently, per item 06's scope split); ids already decided are left alone.
walk_block_remaining() {
  local run_dir="$1" run_id="$2" reason="$3" class="$4" scope="${5:-ticket}" manifest="${6:-}" done_ids ids id
  done_ids="[]"
  [ -f "$run_dir/evidence.jsonl" ] && done_ids="$(jq -cs --arg scope "$scope" '[.[] | select(.event == "ac" and .scope == $scope) | .ac_id]' "$run_dir/evidence.jsonl" 2>/dev/null)"
  [ -n "$done_ids" ] || done_ids="[]"
  if [ -n "$manifest" ] && [ -f "$manifest" ]; then
    ids="$(jq -r --argjson done "$done_ids" '.[].id | select(. as $i | ($done | index($i)) == null)' "$manifest" 2>/dev/null)"
  else
    ids="$(jq -r --argjson done "$done_ids" '.acs[].ac_id | select(. as $i | ($done | index($i)) == null)' "$run_dir/acs.json" 2>/dev/null)"
  fi
  for id in $ids; do
    walk_append_ac "$run_dir" "$run_id" "$id" "BLOCKED" "$class" "$reason" "[]" "[]" "$scope" "$manifest" || return 1
  done
  return 0
}

# walk_ingest <run_dir> <run_id> [<report_path>] [<scope=ticket>] [<manifest>] - report_path (default
# <run_dir>/report.json) -> one `ac` line per `[<id>]` spec. Reporter -> verdict (the LAST result of
# the LAST test of the spec):
#   passed                                        => PASS
#   skipped                                       => BLOCKED ENVIRONMENT_ISSUE  spec_skipped
#   no result at all                              => BLOCKED ENVIRONMENT_ISSUE  spec_not_run
#   failed/timedOut/interrupted, message names a navigation/connection failure
#     (net::ERR_, ECONNREFUSED, a page.goto timeout)=> BLOCKED ENVIRONMENT_ISSUE  <first error line>
#   any other failed/timedOut/interrupted         => FAIL    REAL_BUG           <first error line>
# `reason` is the FIRST line of errors[0].message with ANSI stripped (falls back to `spec_<status>`).
# The AC5 session-expiry override (below) is a ticket-only, auth-flow concept and never runs when
# scope is `impact`.
# walk_apply_expiry_override <run_dir> <run_id> <min_ordinal> - AC5. `min_ordinal` is the SMALLEST
# AC ORDINAL (the integer parsed from `[ACn]`, never file/report order) among the specs whose ingested
# attachments carried a `response-40[13]` signal. Forces `AC<min_ordinal>` to
# BLOCKED/ENVIRONMENT_ISSUE/session_expired - discarding whatever the normal ingest just recorded for
# it (the append-only store makes THIS new line the latest-per-ac_id winner) - and forces every
# `AC<k>` with `k > min_ordinal` (from acs.json's OWN ac_id list, so an AC with no spec at all is
# included) to BLOCKED/ENVIRONMENT_ISSUE/run_paused_session_expired, regardless of any Playwright
# result of its own. ACs with a smaller ordinal are untouched. Appends exactly ONE `{event:auth,
# state:expired}` line and calls `pause_cmd ... --reason session_expired` exactly ONCE, never per AC.
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
  local run_dir="$1" run_id="$2" report_path="${3:-$run_dir/report.json}" scope="${4:-ticket}" manifest="${5:-}"
  local specs spec ac_id rstatus message steps verdict class reason arts n
  local has_expiry min_n num
  specs="$(mktemp "${TMPDIR:-/tmp}/verify-walk.XXXXXX")" || die "mktemp failed"
  jq -c '
    [.. | objects | select(has("specs") and (.specs | type == "array")) | .specs[]]
    | map(select((.title // "") | test("^\\[[A-Za-z0-9_-]+\\]")))
    | map(. as $s | ($s.tests // [] | last) as $t | (($t.results // []) | last) as $r
        | {ac_id: ($s.title | capture("^\\[(?<id>[A-Za-z0-9_-]+)\\]").id),
           rstatus: ($r.status // "missing"),
           message: ((($r.errors // [])[0].message // $r.error.message // "")
                     | gsub("\u001b\\[[0-9;]*[A-Za-z]"; "") | (split("\n")[0] // "")
                     | gsub("^[[:space:]]+|[[:space:]]+$"; "")),
           steps: [($r.steps // [])[] | .title // empty],
           attachments: [($r.attachments // [])[]
                         | {name: (.name // "attachment"), contentType: (.contentType // ""),
                            path: (.path // ""), body: (.body // "")}]})
    | .[]' "$report_path" > "$specs" 2>"$specs.err"
  if [ $? -ne 0 ]; then
    diag "$report_path is not a Playwright JSON report: $(head -1 "$specs.err") [reporter_unreadable]"
    rm -f "$specs" "$specs.err"; return 1
  fi
  n="$(grep -c . "$specs")"
  diag "ingesting $n [id] spec result(s) from $report_path (scope=$scope)"
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
    walk_append_ac "$run_dir" "$run_id" "$ac_id" "$verdict" "$class" "$reason" "$steps" "$arts" "$scope" "$manifest" || { rm -f "$specs" "$specs.err"; return 1; }
    if [ "$scope" = "ticket" ]; then
      # AC5: a `response-40[13]` attachment on THIS spec's result signals a session that died
      # mid-test (distinct from the anonymous-redirect 302 the app also emits). Collect the AC
      # ORDINAL - never this loop's own file/report order - for the override pass below.
      has_expiry="$(printf '%s' "$spec" | jq -r '[(.attachments // [])[].name // ""] | any(test("^response-40[13]"))' 2>/dev/null)"
      if [ "$has_expiry" = "true" ]; then
        num="${ac_id#AC}"
        case "$num" in ''|*[!0-9]*) ;; *) printf '%s\n' "$num" >> "$specs.expiry" ;; esac
      fi
    fi
  done < "$specs"
  if [ "$scope" = "ticket" ] && [ -s "$specs.expiry" ]; then
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

# impact_cmd <diff|brief-surfaces|record-surfaces|prior-acs> ... - dispatches `impact <sub>` to the
# matching impact_*_cmd function (named for the "impact_cmd" provides symbol; mirrors the walk_cmd /
# verdict_cmd / finish_cmd naming convention already used by every other top-level subcommand here).
impact_cmd() {
  local isub="${1:-}"
  shift || true
  case "$isub" in
    diff)            impact_diff_cmd "$@" ;;
    brief-surfaces)  impact_brief_surfaces_cmd "$@" ;;
    record-surfaces) impact_record_surfaces_cmd "$@" ;;
    prior-acs)       impact_prior_acs_cmd "$@" ;;
    *) die "unknown impact subcommand: $isub (try impact diff|brief-surfaces|record-surfaces|prior-acs)" ;;
  esac
}


# --------------------------------------------------------------------------- #
# queue-reconcile-item <run_dir> --branch <name> [--repo <dir>]
# --------------------------------------------------------------------------- #
# Item 07 (`/verify --folder <dir>` multi-ticket queue) — reconciles ONE queue
# item's run dir against ground truth on every queue start (bare `/verify
# --folder`, or `--resume`), per the source requirement's Scope §3. The queue
# file is BELIEF; this is TRUTH. Two independent checks:
#   (a) evidence.jsonl's LAST line: `run_end` => "done" (the item is finished
#       even if the queue checkbox is still unchecked — a crash between finish
#       and check-off must not re-run it); `pause` => "paused" (its `reason`
#       echoed as `pause_reason`); anything else, OR no evidence.jsonl at all
#       for an already-picked item => "crashed" mid-AC — `resume_ac_id` comes
#       from `verify-helpers.sh first-unverdicted`, never re-derived here (one
#       implementation of "what's the next unverdicted AC").
#   (b) `git rev-parse <branch>` vs the `run_start` line's OWN `head_sha`. A
#       MOVED head makes this run dir's verdicts untrustworthy no matter how it
#       stopped, so it is checked FIRST and short-circuits (a) — a stale run is
#       never resumed, only re-queued fresh.
# (c) "verify-env.sh auth-probe before resuming an authenticated item" (the
# source requirement's third belief-vs-truth check) is deliberately NOT done
# here: the caller (the `/verify --folder` queue loop in commands/verify.md)
# already calls THIS script's own `auth-check` subcommand before resuming an
# item exactly as the single-ticket resume flow does — re-probing here would
# be a second, divergent implementation of the same auth-check.
#
# Never mutates the queue file, evidence store, or run dir — a pure read. Bar
# usage errors and a missing run dir (exit 2), this ALWAYS exits 0: it is an
# advisory read for the loop to act on, never a gate of its own.
queue_reconcile_item_cmd() {
  local run_dir="" branch="" repo_arg="" repo
  local u="queue-reconcile-item <run_dir> --branch <name> [--repo <dir>]"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --branch) [ "$#" -ge 2 ] || usage "--branch needs a value"; branch="$2"; shift 2 ;;
      --repo)   [ "$#" -ge 2 ] || usage "--repo needs a value";   repo_arg="$2"; shift 2 ;;
      -*)       usage "$u (unknown flag $1)" ;;
      *)        if [ -z "$run_dir" ]; then run_dir="$1"; shift; else usage "queue-reconcile-item takes ONE run dir"; fi ;;
    esac
  done
  [ -n "$run_dir" ] || usage "$u"
  [ -n "$branch" ]  || usage "$u (--branch is required)"
  command -v jq >/dev/null 2>&1 || die "jq is required [jq_unavailable]"
  [ -f "$HELPERS" ] || die "sibling verify-helpers.sh not found at $HELPERS"
  [ -d "$run_dir" ] || { diag "run dir not found at $run_dir [run_dir_missing]"; exit 2; }
  run_dir="$(cd "$run_dir" && pwd)"
  repo="$(resolve_repo "$repo_arg")" || exit 2

  local evid="$run_dir/evidence.jsonl" old_sha new_sha
  old_sha="$(run_start_field "$run_dir" head_sha)"
  new_sha="$(git -C "$repo" rev-parse --verify -q "$branch^{commit}" 2>/dev/null)"

  # (b) STALE check first — a moved head overrides any (a) status.
  if [ -n "$old_sha" ] && [ -n "$new_sha" ] && [ "$old_sha" != "$new_sha" ]; then
    jq -cn --arg old "$old_sha" --arg new "$new_sha" \
      '{status:"stale", pause_reason:null, resume_ac_id:null, old_sha:$old, new_sha:$new}'
    return 0
  fi

  # (a) evidence-derived status.
  if [ ! -f "$evid" ]; then
    jq -cn '{status:"not_started", pause_reason:null, resume_ac_id:null, old_sha:null, new_sha:null}'
    return 0
  fi
  local last_event last_reason resume_ac
  last_event="$(jq -rs 'if length==0 then "" else (.[-1].event // "") end' "$evid" 2>/dev/null)"
  case "$last_event" in
    run_end)
      jq -cn --arg old "$old_sha" --arg new "$new_sha" \
        '{status:"done", pause_reason:null, resume_ac_id:null, old_sha:(if $old=="" then null else $old end), new_sha:(if $new=="" then null else $new end)}'
      ;;
    pause)
      last_reason="$(jq -rs '.[-1].reason // empty' "$evid" 2>/dev/null)"
      jq -cn --arg r "$last_reason" --arg old "$old_sha" --arg new "$new_sha" \
        '{status:"paused", pause_reason:(if $r=="" then null else $r end), resume_ac_id:null, old_sha:(if $old=="" then null else $old end), new_sha:(if $new=="" then null else $new end)}'
      ;;
    *)
      resume_ac="$(bash "$HELPERS" first-unverdicted "$run_dir" 2>/dev/null)"
      jq -cn --arg ac "$resume_ac" --arg old "$old_sha" --arg new "$new_sha" \
        '{status:"crashed", pause_reason:null, resume_ac_id:(if $ac=="" then null else $ac end), old_sha:(if $old=="" then null else $old end), new_sha:(if $new=="" then null else $new end)}'
      ;;
  esac
}

main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    acs)        acs_cmd "$@" ;;
    auth-check) auth_check_cmd "$@" ;;
    preflight)  preflight_cmd "$@" ;;
    notify-enable) notify_enable_cmd "$@" ;;
    walk)       walk_cmd "$@" ;;
    verdict)    verdict_cmd "$@" ;;
    finish)     finish_cmd "$@" ;;
    pause)      pause_cmd "$@" ;;
    impact)     impact_cmd "$@" ;;
    queue-reconcile-item) queue_reconcile_item_cmd "$@" ;;
    ""|-h|--help)
      grep -E '^#   [a-z]' "$0" | sed 's/^#   /  /'
      ;;
    *) die "unknown subcommand: $cmd (try --help)" ;;
  esac
}

main "$@"
