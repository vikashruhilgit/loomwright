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
# INVOCATION SEAMS — TWO, deliberately, because ONE was inert on the default path.
#   1. `SessionStart` (via the `session-resume.sh` entry) — THE LOAD-BEARING ONE. `/supervisor`,
#      `/autonomous` and `/automate` are INLINE main-thread workflows (CLAUDE.md §"Common
#      Pitfalls"), so they never spawn a `loomwright:supervisor-runner` subagent and never emit a
#      `SubagentStop` for that matcher. The first cut of this wiring used ONLY seam 2 below and was
#      therefore inert on exactly the runs whose 8 unstamped requirements motivated it — caught in
#      review, not in testing. SessionStart fires on every session regardless of how Supervisor
#      ran, which is the correct cadence for a reconciler: it catches up on what earlier sessions
#      left behind. Cost is ~0.9s over a 72-brief corpus, once per session.
#   2. `SubagentStop[loomwright:supervisor-runner]` — retained, not redundant: it closes the loop
#      immediately for agent-owned sessions (`claude --agent loomwright:supervisor-runner`) instead
#      of deferring to the next session start. Idempotency (below) makes the overlap harmless.
#
# CONTRACT
#   - SUCCESS-ONLY: reads `.supervisor/jobs/done/` exclusively. A brief in `failed/` or
#     `in-progress/` never stamps anything (matches the completion-tail's own success-only rule).
#   - RECORDS WHAT IT CAN PROVE: stamps `## Status: brief-shipped`, never `done`. A landed job
#     proves the work ran, not that every acceptance criterion was met (see the append site).
#   - IDEMPOTENT: a requirement already carrying a `## Status` heading is left untouched, so
#     re-running (or running alongside a completion tail that DID fire) never double-stamps.
#     Because that guard is check-then-append, concurrent runs are additionally serialized by an
#     `mkdir` lock (see MUTUAL EXCLUSION below) — the two seams above can genuinely overlap.
#   - FAIL-SAFE: ALWAYS exits 0. This is a runtime side-effect emitter, not a correctness gate —
#     inverting that would violate the bimodal invariant (CLAUDE.md §"Failure-Mode Invariants").
#   - bash-3.2 safe: no mapfile, no associative arrays, no GNU-only sed/stat/date flags.
#
# PATH CONTAINMENT (the security-relevant part). The requirement path is read out of a brief —
# generated text, therefore UNTRUSTED input, not a constant. A brief that named
# `../../../../etc/passwd` or an absolute path would otherwise make this script append markdown to
# an arbitrary file. Every candidate must therefore: be relative, contain no `..` segment, sit
# under `.supervisor/requirements/`, NOT be a symlink, and — after physically resolving its parent
# directory — still land under `.supervisor/requirements/`. Anything else is skipped with a
# message, never written. The last two checks are not redundant with the first three: those are
# purely LEXICAL, and `-f` follows symlinks, so a link inside the prefix satisfied all of them
# while writing to its target outside the root (reproduced; see the SYMLINK GUARD below).
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

# MUTUAL EXCLUSION. The idempotency guard below is check-then-append, and with TWO invocation
# seams the overlap is no longer theoretical: a SessionStart in one terminal can race a
# supervisor-runner SubagentStop in another, both pass the `grep`, and both append. `mkdir` is the
# portable atomic test-and-set (bash-3.2 / BSD safe — `flock` is Linux-only and absent on macOS).
# Losing the race is NOT an error: the winner does the identical work, so we exit 0 quietly, in
# keeping with the fail-safe contract. The lock is released by the EXIT trap on every path.
LOCK=".supervisor/.stamp-requirement-status.lock"
if mkdir "$LOCK" 2>/dev/null; then
  trap 'rmdir "$LOCK" 2>/dev/null' EXIT INT TERM
else
  # A stale lock (hard kill between mkdir and the trap) would otherwise wedge this forever. It is
  # only ever held for ~1s, so anything older than 5 minutes is definitionally abandoned; reclaim
  # it rather than skipping every run from here on.
  if [ -d "$LOCK" ] && [ -z "$(find "$LOCK" -maxdepth 0 -mmin -5 2>/dev/null)" ]; then
    err "reclaiming stale lock '$LOCK' (older than 5 min)"
    rmdir "$LOCK" 2>/dev/null
    if mkdir "$LOCK" 2>/dev/null; then
      trap 'rmdir "$LOCK" 2>/dev/null' EXIT INT TERM
    else
      say "another reconciler holds the lock — nothing to do"
      exit 0
    fi
  else
    say "another reconciler holds the lock — nothing to do"
    exit 0
  fi
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

  # SYMLINK GUARD — the lexical checks above are NOT sufficient on their own.
  #
  # All four are string tests, and `-f` FOLLOWS symlinks, so a symlink sitting inside
  # `.supervisor/requirements/` passes every one of them and the append lands on the link's
  # target anywhere on the filesystem. Reproduced before this guard: a sandbox link
  # `.supervisor/requirements/link.md -> <root>/outside/victim.md` was reported "stamped" and
  # `victim.md` — outside the containment root — was modified. The original test group covered
  # traversal (`..`) and absolute paths but not symlinks, which is why it was 17/17 green: it
  # tested the attacks that were thought of, not the class.
  #
  # Two layers, because they catch different things:
  #   (a) `-L` rejects a symlinked FINAL component.
  #   (b) physical resolution of the PARENT catches a symlinked DIRECTORY component, which (a)
  #       cannot see (e.g. `.supervisor/requirements/sub -> /etc`, then `sub/passwd`).
  # Both sides of the comparison are resolved with `pwd -P` so a symlinked project root (on
  # macOS `/tmp` -> `/private/tmp`, routinely) does not produce a spurious mismatch.
  if [ -L "$req" ]; then
    err "skip: requirement path is a symlink — '$req' (a requirement file is never legitimately one)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi
  _req_dir="$(cd "$(dirname "$req")" 2>/dev/null && pwd -P)"
  _root_p="$(cd "$ROOT" 2>/dev/null && pwd -P)"
  if [ -z "$_req_dir" ] || [ -z "$_root_p" ]; then
    err "skip: cannot resolve requirement path physically — '$req'"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi
  case "$_req_dir/" in
    "$_root_p/.supervisor/requirements/"*) : ;;
    *)
      err "skip: '$req' physically resolves outside ${REQ_PREFIX} (${_req_dir}) — refusing to write"
      SKIPPED=$((SKIPPED + 1))
      continue ;;
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

if [ "$DRY_RUN" -eq 1 ]; then
  # Do not report "stamped" for a run that wrote nothing — the tally and the verb must agree.
  say "scanned $SCANNED done-brief(s): $STAMPED would-be-stamped, $SKIPPED skipped (dry run — nothing written)"
else
  say "scanned $SCANNED done-brief(s): $STAMPED stamped, $SKIPPED skipped"
fi
exit 0
