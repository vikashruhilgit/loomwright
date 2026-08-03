#!/usr/bin/env bash
# stamp-requirement-status.sh — mechanically close out source requirements whose job landed.
#
# WHY THIS EXISTS (measured, not hypothetical). Supervisor's Phase 4.5 completion tail is
# SUPPOSED to stamp `## Status: done` on the originating requirement file in Beads-absent mode.
# Measured 2026-08-03 across `.supervisor/requirements/final-state/`: only 2 of 6 shipped
# requirements carried the stamp (01 and 03 stamped; 02, 04, 05, 08 shipped unstamped). That is
# the same failure mode this repo already measured for `phase_transition` events (560 hook-written
# `token_ledger` records vs 6 agent-written phase transitions across 11+ sessions) and codified as
# a lesson in `skills/state-management/SKILL.md`: **prompt-instructed bookkeeping is unreliable.**
#
# The durable fix is the one `reconcile-resume-state.sh` already applies to resume state — key on
# a BYPRODUCT of the work (a brief landing in `.supervisor/jobs/done/`), never on something an
# agent must remember to write. This script is that reconciler for requirement close-out.
#
# CONTRACT
#   - SUCCESS-ONLY: reads `.supervisor/jobs/done/` exclusively. A brief in `failed/` or
#     `in-progress/` never stamps anything (matches the completion-tail's own success-only rule).
#   - RECORDS WHAT IT CAN PROVE: stamps `## Status: brief-shipped`, never `done`. A landed job
#     proves the work ran, not that every acceptance criterion was met (see the append site).
#   - IDEMPOTENT: a requirement already carrying a `## Status` heading is left untouched, so
#     re-running (or running alongside a completion tail that DID fire) never double-stamps.
#   - FAIL-SAFE: ALWAYS exits 0. This is a runtime side-effect emitter, not a correctness gate —
#     inverting that would violate the bimodal invariant (CLAUDE.md §"Failure-Mode Invariants").
#   - bash-3.2 safe: no mapfile, no associative arrays, no GNU-only sed/stat/date flags.
#
# PATH CONTAINMENT (the security-relevant part). The requirement path is read out of a brief —
# generated text, therefore UNTRUSTED input, not a constant. A brief that named
# `../../../../etc/passwd` or an absolute path would otherwise make this script append markdown to
# an arbitrary file. Every candidate must therefore: be relative, contain no `..` segment, and sit
# under `.supervisor/requirements/`. Anything else is skipped with a message, never written.
#
# USAGE
#   stamp-requirement-status.sh [--project-root <dir>] [--dry-run]
#     --project-root  repo root to operate on (default: git toplevel, else $PWD). Exists for
#                     hermetic testing; production callers pass nothing.
#     --dry-run       report what WOULD be stamped, write nothing.

set -uo pipefail   # `set -e` intentionally omitted — fail-safe, always exit 0.

say() { echo "stamp-requirement-status: $1"; }
err() { echo "stamp-requirement-status: $1" >&2; }

ROOT=""
DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --project-root)
      if [ $# -ge 2 ]; then ROOT="$2"; shift; else err "--project-root needs a value (ignored)"; fi ;;
    --dry-run) DRY_RUN=1 ;;
    *) err "unknown argument: $1 (ignored)" ;;
  esac
  shift
done

if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
[ -d "$ROOT" ] || { err "project root '$ROOT' is not a directory — nothing done (fail-safe)"; exit 0; }
cd "$ROOT" 2>/dev/null || { err "cannot enter '$ROOT' — nothing done (fail-safe)"; exit 0; }

DONE_DIR=".supervisor/jobs/done"
REQ_PREFIX=".supervisor/requirements/"

if [ ! -d "$DONE_DIR" ]; then
  say "no $DONE_DIR — nothing to reconcile"
  exit 0
fi

STAMPED=0
SKIPPED=0
SCANNED=0

for brief in "$DONE_DIR"/*.md; do
  [ -f "$brief" ] || continue
  SCANNED=$((SCANNED + 1))

  # Provenance anchor written by Launch Pad Phase 2 step 0 for requirement-file inputs:
  #   - **Source requirement:** .supervisor/requirements/<...>.md
  # Briefs from a literal-string goal carry no such line and are correctly skipped (measured:
  # 28 of 72 archived briefs carry it — the requirement-sourced subset).
  raw="$(grep -m1 -iE '^[[:space:]]*-?[[:space:]]*\*\*Source requirement:\*\*' "$brief" 2>/dev/null)"
  [ -n "$raw" ] || continue

  # Strip everything through the label, then surrounding markdown/whitespace.
  req="$(printf '%s' "$raw" | sed -E 's/.*\*\*[Ss]ource [Rr]equirement:\*\*[[:space:]]*//')"
  req="$(printf '%s' "$req" | sed -E 's/^[`"'"'"' ]+//; s/[`"'"'"' ]+$//')"
  [ -n "$req" ] || continue

  # --- containment checks (untrusted input) ---
  case "$req" in
    /*)      err "skip: absolute requirement path in $(basename "$brief") — '$req'"; SKIPPED=$((SKIPPED+1)); continue ;;
    *..*)    err "skip: '..' segment in requirement path from $(basename "$brief") — '$req'"; SKIPPED=$((SKIPPED+1)); continue ;;
    "$REQ_PREFIX"*) : ;;
    *)       err "skip: requirement path outside $REQ_PREFIX in $(basename "$brief") — '$req'"; SKIPPED=$((SKIPPED+1)); continue ;;
  esac

  if [ ! -f "$req" ]; then
    err "skip: requirement file not found — '$req' (referenced by $(basename "$brief"))"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Idempotency: any existing `## Status` heading means this requirement is already closed out,
  # whether by a completion tail that DID fire or by a previous run of this script.
  if grep -qE '^## Status' "$req" 2>/dev/null; then
    continue
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    say "WOULD stamp: $req (from $(basename "$brief"))"
    STAMPED=$((STAMPED + 1))
    continue
  fi

  # Append. Deliberately `brief-shipped`, NOT `done`.
  #
  # A brief landing in `done/` proves the JOB completed. It does NOT prove every acceptance
  # criterion was satisfied, and this script has no way to check: requirement ACs are prose
  # bullets, not checkboxes (verified across `.supervisor/requirements/` — zero `- [ ]` markers),
  # so there is nothing mechanical to evaluate. Two live counterexamples found on the first real
  # run: `final-state/08-worker-context-digest-lanes.md` shipped with its measurement AC
  # explicitly deferred by owner decision, and `twin-remediation/07-parity-ablation-eval.md`
  # would be closed by `2026-07-24-parity-eval-prep.md` — a brief that shipped the PREP while the
  # eval itself remains owed. Stamping either `done` would launder an unmet requirement into a
  # satisfied one, which is precisely the record-overstates-reality failure this script exists to
  # correct. Promotion to `## Status: done` stays a human judgement; the idempotency guard above
  # keys on `^## Status`, so a later hand-written `done` is never overwritten or duplicated.
  {
    printf '\n## Status: brief-shipped\n'
    printf '\nJob `%s/%s` completed (reconciled from the job lifecycle, not self-reported).\n' \
      "$DONE_DIR" "$(basename "$brief")"
    printf 'Acceptance criteria are NOT machine-verified here — review them before promoting this to `## Status: done`.\n'
  } >> "$req" 2>/dev/null || {
    err "skip: cannot append to '$req' (not writable)"
    SKIPPED=$((SKIPPED + 1))
    continue
  }
  say "stamped: $req (from $(basename "$brief"))"
  STAMPED=$((STAMPED + 1))
done

say "scanned $SCANNED done-brief(s): $STAMPED stamped, $SKIPPED skipped"
exit 0
