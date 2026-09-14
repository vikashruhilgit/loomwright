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
#   acs       <ticket>                                              # print {"ticket_kind": …, "acs": [{"ac_id":"AC1","text":"…"}, …]}
#   preflight <ticket> [--branch <name>] [--repo <dir>]             # contract read → run dir + run_start → assert-non-prod → env line; prints `run_dir=<path>` LAST
#   walk      <run_dir>   (Subtask 2)                               # generate the per-run Playwright config, run the `[ACn]` specs, ingest the reporter into `ac` lines
#   verdict   <run_dir> <ac_id> <NOT_VERIFIABLE|BLOCKED> --reason <text> [--classification <c>]   # append one browser-less `ac` line
#   finish    <run_dir> [--status completed|aborted]                # append run_end (NO counts), rebuild summary.md, print its counts row
#
# Exit codes: 0 ok · 1 refused / failed (non-prod assertion failed, append refused) · 2 usage / ticket
# unresolved / a verdict that needs observation · 3 preflight stop (no contract at .agent/verify.json,
# contract unreadable — nothing created, nothing called).
# Dependencies: bash 3.2+, jq, git, python3 (through verify-helpers.sh's validator gate),
# `shasum -a 256` or `sha256sum` (the run_start contract hash).

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HELPERS="$HERE/verify-helpers.sh"
READER="$HERE/read-verify.sh"
EXECUTOR="$HERE/verify-env.sh"
BOOTSTRAP="$HERE/propose-verify.sh"

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
  local ticket="" branch="" repo_arg="" repo acs kind contract rerr tokens
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

main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    acs)       acs_cmd "$@" ;;
    preflight) preflight_cmd "$@" ;;
    verdict)   verdict_cmd "$@" ;;
    finish)    finish_cmd "$@" ;;
    ""|-h|--help)
      grep -E '^#   [a-z]' "$0" | sed 's/^#   /  /'
      ;;
    *) die "unknown subcommand: $cmd (try --help)" ;;
  esac
}

main "$@"
