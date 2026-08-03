#!/usr/bin/env bash
# test-stamp-requirement-status.sh — hermetic tests for the requirement close-out reconciler.
#
# Auto-registered by CI's `loomwright/scripts/test-*.sh` glob. Fully offline, operates only inside
# a mktemp sandbox via `--project-root`, never touches the real `.supervisor/`.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="$SCRIPT_DIR/stamp-requirement-status.sh"
PASS=0; FAIL=0

ok() { echo "PASS: $1"; PASS=$((PASS+1)); }
no() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# sandbox <name> -> creates $SB with the .supervisor skeleton, echoes the path
sandbox() {
  SB="$(mktemp -d)"
  mkdir -p "$SB/.supervisor/jobs/done" "$SB/.supervisor/requirements/final-state"
  echo "$SB"
}

mkbrief() {  # mkbrief <sandbox> <briefname> <requirement-path-text>
  printf '# Supervisor Job: test\n\n## Environment\n\n- **Source requirement:** %s\n' "$3" \
    > "$1/.supervisor/jobs/done/$2"
}

mkreq() {    # mkreq <sandbox> <relpath> [extra-content]
  mkdir -p "$(dirname "$1/$2")"
  printf '# Requirement\n\n## Acceptance criteria\n- something\n%s\n' "${3:-}" > "$1/$2"
}

# ── 1. happy path: a done brief stamps its requirement ───────────────────────
SB="$(sandbox)"
mkreq "$SB" ".supervisor/requirements/final-state/08-thing.md"
mkbrief "$SB" "2026-07-31-thing.md" ".supervisor/requirements/final-state/08-thing.md"
bash "$TARGET" --project-root "$SB" >/dev/null 2>&1
if grep -qE '^## Status: brief-shipped' "$SB/.supervisor/requirements/final-state/08-thing.md"; then
  ok "stamps a requirement whose brief landed in done/"
else
  no "stamps a requirement whose brief landed in done/"
fi

# The reconciler must never assert `done` — a landed job does not prove the ACs were met.
grep -qE '^## Status: done' "$SB/.supervisor/requirements/final-state/08-thing.md" \
  && no "must NOT claim '## Status: done' (acceptance is not machine-verified)" \
  || ok "records 'brief-shipped', never claims 'done'"

# ── 2. idempotent: second run does not double-stamp ──────────────────────────
bash "$TARGET" --project-root "$SB" >/dev/null 2>&1
COUNT="$(grep -cE '^## Status' "$SB/.supervisor/requirements/final-state/08-thing.md")"
[ "$COUNT" -eq 1 ] && ok "idempotent — re-run leaves exactly one ## Status heading" \
                   || no "idempotent — expected 1 ## Status heading, found $COUNT"
rm -rf "$SB"

# ── 3. pre-existing stamp (completion tail DID fire) is left untouched ───────
SB="$(sandbox)"
mkreq "$SB" ".supervisor/requirements/final-state/01-done.md" "$(printf '\n## Status: done\n')"
mkbrief "$SB" "b.md" ".supervisor/requirements/final-state/01-done.md"
BEFORE="$(cat "$SB/.supervisor/requirements/final-state/01-done.md")"
bash "$TARGET" --project-root "$SB" >/dev/null 2>&1
AFTER="$(cat "$SB/.supervisor/requirements/final-state/01-done.md")"
[ "$BEFORE" = "$AFTER" ] && ok "already-stamped requirement is byte-identical after a run" \
                         || no "already-stamped requirement was modified"
rm -rf "$SB"

# ── 4. SUCCESS-ONLY: a brief in failed/ or in-progress/ stamps nothing ───────
SB="$(sandbox)"
mkdir -p "$SB/.supervisor/jobs/failed" "$SB/.supervisor/jobs/in-progress"
mkreq "$SB" ".supervisor/requirements/final-state/09-nope.md"
printf '# J\n- **Source requirement:** .supervisor/requirements/final-state/09-nope.md\n' \
  > "$SB/.supervisor/jobs/failed/f.md"
printf '# J\n- **Source requirement:** .supervisor/requirements/final-state/09-nope.md\n' \
  > "$SB/.supervisor/jobs/in-progress/p.md"
bash "$TARGET" --project-root "$SB" >/dev/null 2>&1
grep -qE '^## Status' "$SB/.supervisor/requirements/final-state/09-nope.md" \
  && no "success-only — failed/in-progress brief must NOT stamp" \
  || ok "success-only — a brief in failed/ or in-progress/ stamps nothing"
rm -rf "$SB"

# ── 5. CONTAINMENT: traversal, absolute, and out-of-tree paths are refused ───
# The requirement path is read out of generated brief text, so it is untrusted input.
for evil in "../../../../tmp/pwned.md" \
            "/tmp/pwned-abs.md" \
            ".supervisor/../../outside.md" \
            "README.md"; do
  SB="$(sandbox)"
  VICTIM="$SB/victim.md"; printf 'untouched\n' > "$VICTIM"
  printf 'untouched\n' > "$SB/README.md"
  mkbrief "$SB" "evil.md" "$evil"
  bash "$TARGET" --project-root "$SB" >/dev/null 2>&1
  BAD=0
  grep -qE '^## Status' "$SB/README.md" 2>/dev/null && BAD=1
  [ -f /tmp/pwned.md ] && BAD=1
  [ -f /tmp/pwned-abs.md ] && BAD=1
  [ "$(cat "$VICTIM")" = "untouched" ] || BAD=1
  [ "$BAD" -eq 0 ] && ok "containment — refuses '$evil'" \
                   || no "containment — '$evil' caused a write outside .supervisor/requirements/"
  rm -f /tmp/pwned.md /tmp/pwned-abs.md
  rm -rf "$SB"
done

# ── 5b. CONTAINMENT: symlinks (the lexical checks above cannot see these) ────
# The four lexical checks all pass for a symlink sitting inside .supervisor/requirements/, and
# `-f` follows symlinks — so before the physical-resolution guard this wrote to the link target
# OUTSIDE the containment root (reproduced). Two shapes, because they fail differently:
#   (a) symlinked FINAL component  -> caught by `-L`
#   (b) symlinked PARENT directory -> invisible to `-L`, caught only by physical resolution
SB="$(sandbox)"
mkdir -p "$SB/outside"
printf 'ORIGINAL\n' > "$SB/outside/victim.md"
ln -s "$SB/outside/victim.md" "$SB/.supervisor/requirements/link.md"
mkbrief "$SB" "sym-final.md" ".supervisor/requirements/link.md"
bash "$TARGET" --project-root "$SB" >/dev/null 2>&1
if [ "$(cat "$SB/outside/victim.md")" = "ORIGINAL" ]; then
  ok "containment — symlinked FINAL component does not write to its target outside the root"
else
  no "containment — symlink escape: wrote into $SB/outside/victim.md"
fi
rm -rf "$SB"

SB="$(sandbox)"
mkdir -p "$SB/outside/reqdir"
printf 'ORIGINAL\n' > "$SB/outside/reqdir/x.md"
ln -s "$SB/outside/reqdir" "$SB/.supervisor/requirements/sub"
mkbrief "$SB" "sym-parent.md" ".supervisor/requirements/sub/x.md"
bash "$TARGET" --project-root "$SB" >/dev/null 2>&1
if [ "$(cat "$SB/outside/reqdir/x.md")" = "ORIGINAL" ]; then
  ok "containment — symlinked PARENT directory does not write outside the root"
else
  no "containment — symlinked-parent escape: wrote into $SB/outside/reqdir/x.md"
fi
rm -rf "$SB"

# The guard must not over-reach: a REAL file at a real path under the prefix still stamps.
SB="$(sandbox)"
mkreq "$SB" ".supervisor/requirements/final-state/13-real.md"
mkbrief "$SB" "real.md" ".supervisor/requirements/final-state/13-real.md"
bash "$TARGET" --project-root "$SB" >/dev/null 2>&1
grep -qE '^## Status: brief-shipped' "$SB/.supervisor/requirements/final-state/13-real.md" \
  && ok "symlink guard does not over-reach — a genuine nested requirement still stamps" \
  || no "symlink guard over-reached — a legitimate nested requirement was refused"
rm -rf "$SB"

# ── 6. missing requirement file is skipped, not fatal ────────────────────────
SB="$(sandbox)"
mkbrief "$SB" "ghost.md" ".supervisor/requirements/final-state/does-not-exist.md"
bash "$TARGET" --project-root "$SB" >/dev/null 2>&1
[ $? -eq 0 ] && ok "missing requirement file — skipped, exit 0" \
             || no "missing requirement file — non-zero exit"
rm -rf "$SB"

# ── 7. brief with no provenance line is ignored ──────────────────────────────
SB="$(sandbox)"
mkreq "$SB" ".supervisor/requirements/final-state/10-x.md"
printf '# Supervisor Job: literal goal, no requirement\n\n## Task\n- do a thing\n' \
  > "$SB/.supervisor/jobs/done/plain.md"
bash "$TARGET" --project-root "$SB" >/dev/null 2>&1
grep -qE '^## Status' "$SB/.supervisor/requirements/final-state/10-x.md" \
  && no "brief with no Source requirement line must stamp nothing" \
  || ok "brief with no Source requirement line is ignored"
rm -rf "$SB"

# ── 8. --dry-run writes nothing ──────────────────────────────────────────────
SB="$(sandbox)"
mkreq "$SB" ".supervisor/requirements/final-state/11-dry.md"
mkbrief "$SB" "d.md" ".supervisor/requirements/final-state/11-dry.md"
OUT="$(bash "$TARGET" --project-root "$SB" --dry-run 2>&1)"
if grep -qE '^## Status' "$SB/.supervisor/requirements/final-state/11-dry.md"; then
  no "--dry-run must not write"
else
  case "$OUT" in *"WOULD stamp"*) ok "--dry-run reports without writing" ;;
                 *) no "--dry-run did not report the pending stamp" ;; esac
fi
# The summary verb must match what actually happened — "N stamped" for a run that wrote
# nothing misreports the outcome.
case "$OUT" in
  *"would-be-stamped"*) ok "--dry-run summary says 'would-be-stamped', not 'stamped'" ;;
  *) no "--dry-run summary still claims 'stamped' for a run that wrote nothing" ;;
esac
rm -rf "$SB"

# ── 8b. concurrency: a held lock makes a second run a quiet no-op ────────────
# The idempotency guard is check-then-append; with a SessionStart seam AND a SubagentStop seam
# the two can genuinely overlap, so the mkdir lock is what actually prevents a double-append.
SB="$(sandbox)"
mkreq "$SB" ".supervisor/requirements/final-state/12-lock.md"
mkbrief "$SB" "l.md" ".supervisor/requirements/final-state/12-lock.md"
mkdir -p "$SB/.supervisor/.stamp-requirement-status.lock"     # simulate a live holder
OUT="$(bash "$TARGET" --project-root "$SB" 2>&1)"
if grep -qE '^## Status' "$SB/.supervisor/requirements/final-state/12-lock.md"; then
  no "held lock — second run must not write"
else
  case "$OUT" in *"another reconciler holds the lock"*) ok "held lock — second run is a quiet no-op" ;;
                 *) no "held lock — expected the lock-held message, got: $OUT" ;; esac
fi
# Releasing the lock lets the next run proceed (proves the lock is not a permanent wedge).
rmdir "$SB/.supervisor/.stamp-requirement-status.lock"
bash "$TARGET" --project-root "$SB" >/dev/null 2>&1
grep -qE '^## Status: brief-shipped' "$SB/.supervisor/requirements/final-state/12-lock.md" \
  && ok "lock released — the next run stamps normally" \
  || no "lock released — run still did not stamp"
# And the lock must not survive a normal exit (EXIT trap released it).
[ -d "$SB/.supervisor/.stamp-requirement-status.lock" ] \
  && no "lock leaked after a normal run" \
  || ok "lock is released on exit (no leak)"
rm -rf "$SB"

# ── 9. fail-safe: absent .supervisor exits 0 ─────────────────────────────────
SB="$(mktemp -d)"
bash "$TARGET" --project-root "$SB" >/dev/null 2>&1
[ $? -eq 0 ] && ok "absent .supervisor/ — exits 0 (fail-safe)" \
             || no "absent .supervisor/ — non-zero exit"
rm -rf "$SB"

echo "----"
echo "test-stamp-requirement-status: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
