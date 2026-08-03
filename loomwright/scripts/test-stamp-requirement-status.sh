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
