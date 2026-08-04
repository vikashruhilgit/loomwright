#!/usr/bin/env bash
# drain-rounds.sh — the MECHANIZED shared drain-round ceiling for the §U4
# bounded drain loop (skills/review-heal/SKILL.md). Single ledger
# implementation consumed by BOTH entry paths (inline `/review-pr` and the
# detached `review-pr-runner`) — see AC1/AC2. Neither path may keep a private
# counter; both call this script for the SAME PR's ledger.
#
# The hard ceiling value is NEVER hardcoded here — callers pass it explicitly
# to `init`. The authoritative default (5) lives at ONE place,
# the `max_rounds` default in skills/review-heal/SKILL.md §"Step U4 — The bounded
# drain loop" (`--max-rounds N` overrides it); this script
# only stores and checks whatever integer it is given (Claim Duplication Rule).
#
# Subcommands:
#   init  <pr> <max_rounds>   Create/reset the per-PR ledger to rounds=0.
#                             Idempotent — always safe to call once at drain
#                             start; a stale ledger from a prior run on the
#                             same PR is overwritten.
#   bump  <pr>                Increment rounds by 1. FAILS CLOSED (prints
#                             "ESCALATED: unreadable_round_ledger", exit 2) if
#                             the ledger is missing/garbage — `init` must run
#                             first.
#   check <pr>                Prints exactly one of:
#                               OK                          (exit 0 — continue)
#                               BOUND_HIT                   (exit 1 — ceiling
#                                                             reached, do NOT
#                                                             start another
#                                                             round)
#                               ESCALATED: unreadable_round_ledger (exit 2 —
#                                                             fail CLOSED,
#                                                             AC5)
#   read  <pr>                 Prints the raw ledger JSON, or `{}` if absent.
#                              Introspection only; always exit 0.
#
# Ledger location: .supervisor/drain-rounds/<pr_hash>.json — gitignored
# scratch, keyed by the SAME shasum -> sha1sum -> cksum -> sanitized-URL
# fallback chain dispatch-pr-review.sh uses for its per-PR marker, so both
# scripts key identically off the PR URL/identifier.
#
# Portability (machine lesson): macOS bash 3.2 + BSD userland safe — no
# `stat -c`, no `timeout`, no GNU `sed -i`, no associative arrays. Also
# ubuntu-clean: this script and its test are auto-included by ci.yml's
# `loomwright/scripts/test-*.sh` whole-suite glob. `set -u` safe throughout
# (every positional is defaulted via `${n:-}` before use).
set -u

DIR=".supervisor/drain-rounds"

usage() {
  echo "usage: drain-rounds.sh {init|bump|check|read} <pr> [max_rounds]" >&2
  exit 2
}

# pr_hash <pr> — deterministic hash of the PR identifier (URL or any stable
# string). Mirrors dispatch-pr-review.sh's PR_HASH derivation exactly so a
# future consolidation can share it without a behavior change.
pr_hash() {
  local pr="$1" h=""
  if command -v shasum >/dev/null 2>&1; then
    h="$(printf '%s' "$pr" | shasum 2>/dev/null | cut -d' ' -f1 || true)"
  elif command -v sha1sum >/dev/null 2>&1; then
    h="$(printf '%s' "$pr" | sha1sum 2>/dev/null | cut -d' ' -f1 || true)"
  elif command -v cksum >/dev/null 2>&1; then
    h="$(printf '%s' "$pr" | cksum 2>/dev/null | cut -d' ' -f1 || true)"
  fi
  if [ -z "$h" ]; then
    h="$(printf '%s' "$pr" | tr -c 'A-Za-z0-9' '-')"
  fi
  printf '%s' "$h"
}

ledger_path() {
  printf '%s/%s.json' "$DIR" "$(pr_hash "$1")"
}

# read_field <ledger-file> <field-name> — dependency-free (no jq requirement)
# best-effort non-negative-or-negative integer extraction. Prints "" (empty)
# on ANY failure (missing file, missing field, garbage content) so callers can
# fail CLOSED on an empty result — never silently defaults to 0.
read_field() {
  local f="$1" field="$2" line
  [ -r "$f" ] || { printf ''; return 0; }
  line="$(grep -oE "\"$field\"[[:space:]]*:[[:space:]]*-?[0-9]+" "$f" 2>/dev/null | head -1)"
  [ -n "$line" ] || { printf ''; return 0; }
  printf '%s' "$line" | grep -oE -- '-?[0-9]+$' 2>/dev/null
}

cmd_init() {
  local pr="${1:-}" max="${2:-}"
  [ -n "$pr" ] && [ -n "$max" ] || usage
  case "$max" in
    ''|*[!0-9]*) echo "drain-rounds: init requires a non-negative integer max_rounds, got: '$max'" >&2; exit 2 ;;
    0[0-9]*) echo "drain-rounds: init rejects leading zeros in max_rounds, got: '$max' (bash arithmetic would read it as OCTAL -- '010' would silently mean 8, and '08'/'09' would abort with 'value too great for base', breaking this script's fail-closed contract)" >&2; exit 2 ;;
  esac
  mkdir -p "$DIR" 2>/dev/null || { echo "ESCALATED: ledger_dir_uncreatable"; exit 2; }
  local f; f="$(ledger_path "$pr")"
  if ! printf '{"rounds":0,"max_rounds":%s}\n' "$max" > "$f" 2>/dev/null; then
    echo "ESCALATED: ledger_write_failed"; exit 2
  fi
  echo "OK"
  exit 0
}

cmd_bump() {
  local pr="${1:-}"
  [ -n "$pr" ] || usage
  local f rounds max
  f="$(ledger_path "$pr")"
  rounds="$(read_field "$f" rounds)"
  max="$(read_field "$f" max_rounds)"
  if [ -z "$rounds" ] || [ -z "$max" ]; then
    echo "ESCALATED: unreadable_round_ledger"; exit 2
  fi
  rounds=$((10#$rounds + 1))
  if ! printf '{"rounds":%s,"max_rounds":%s}\n' "$rounds" "$max" > "$f" 2>/dev/null; then
    echo "ESCALATED: ledger_write_failed"; exit 2
  fi
  echo "$rounds"
  exit 0
}

cmd_check() {
  local pr="${1:-}"
  [ -n "$pr" ] || usage
  local f rounds max
  f="$(ledger_path "$pr")"
  rounds="$(read_field "$f" rounds)"
  max="$(read_field "$f" max_rounds)"
  if [ -z "$rounds" ] || [ -z "$max" ]; then
    echo "ESCALATED: unreadable_round_ledger"; exit 2
  fi
  if [ "$rounds" -ge "$max" ]; then
    echo "BOUND_HIT"; exit 1
  fi
  echo "OK"
  exit 0
}

cmd_read() {
  local pr="${1:-}"
  [ -n "$pr" ] || usage
  local f; f="$(ledger_path "$pr")"
  if [ -r "$f" ]; then
    cat "$f"
  else
    echo "{}"
  fi
  exit 0
}

sub="${1:-}"
shift 2>/dev/null || true
case "$sub" in
  init)  cmd_init "$@" ;;
  bump)  cmd_bump "$@" ;;
  check) cmd_check "$@" ;;
  read)  cmd_read "$@" ;;
  *) usage ;;
esac
