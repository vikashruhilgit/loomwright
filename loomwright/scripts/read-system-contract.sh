#!/usr/bin/env bash
# read-system-contract.sh — sole sanctioned READER / the read-side provenance gate for the
# System Twin contract store (v14.10.0).
#
# Emits ONLY contract files in .supervisor/twin/contracts/ whose content is backed by a
# chain-valid `add` provenance entry in .supervisor/twin/.provenance.jsonl. Any contract that is
# unverified — an out-of-band poisoned file, or anything beyond a broken point in the hash chain —
# is DROPPED and logged to .supervisor/logs/twin.log. This is the read-side enforcement: write-side
# provenance alone is theater (mirrors read-project-memory.sh / red-team W1).
#
# Output is ADVISORY and prefixed with a subordinate-to-CLAUDE.md banner. Consumers (ST2 read-path,
# ST3 conformance) call this instead of `cat`-ing files. Fail-safe: no sha tool → emit nothing.
#
# Usage:  read-system-contract.sh                  (emit all verified contracts)
#         read-system-contract.sh --subsystem "<id>"   (emit that one contract if verified)
# Exit:   always 0 (a read must never break the caller); diagnostics go to stderr + twin.log.

set -uo pipefail   # `set -e` intentionally omitted — a read must NEVER fail its caller.

SUBSYSTEM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --subsystem)   SUBSYSTEM="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --subsystem=*) SUBSYSTEM="${1#--subsystem=}"; shift ;;
    *) shift ;;
  esac
done

GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$GITROOT" 2>/dev/null || true

TWIN_DIR=".supervisor/twin"
CONTRACT_DIR="$TWIN_DIR/contracts"
PROV="$TWIN_DIR/.provenance.jsonl"
LOG=".supervisor/logs/twin.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

[ -d "$CONTRACT_DIR" ] || exit 0   # no contracts yet → emit nothing

if command -v sha256sum >/dev/null 2>&1; then   sha() { sha256sum | cut -d' ' -f1; }
elif command -v shasum  >/dev/null 2>&1; then   sha() { shasum -a 256 | cut -d' ' -f1; }
else echo "read-system-contract: no sha256 tool — contracts unverifiable, emitting nothing (fail-safe)" >&2; exit 0; fi

# Extracts a STRING-valued JSON field only (value in double quotes). All provenance fields walked
# by the chain logic (prev_hash, content_hash, source, action) are strings, so this is sufficient.
# A future NUMERIC provenance field would need jq (or a different extractor) — sed would misread it.
field() { printf '%s' "$1" | sed -E "s/.*\"$2\":\"([^\"]*)\".*/\1/"; }

# Resolve --subsystem to the same sanitized filename the writer uses.
safe_id() { printf '%s' "$1" | tr '/' '-' | sed -E 's/[^A-Za-z0-9._-]/-/g; s/-+/-/g; s/^-+//; s/-+$//'; }

# 1. Walk the provenance chain; collect content_hashes of chain-valid `add` entries.
trusted="$(mktemp)"; body_out="$(mktemp)"
trap 'rm -f "$trusted" "$body_out" 2>/dev/null' EXIT
prev="GENESIS"; n=0
if [ -f "$PROV" ]; then
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    n=$((n+1))
    if [ "$(field "$p" prev_hash)" != "$prev" ]; then
      echo "read-system-contract: provenance chain broken at entry $n (prev_hash mismatch — tampering, or a value that defeated field extraction) — distrusting it and everything after" >&2
      break
    fi
    if [ "$(field "$p" action)" = "add" ]; then
      ch="$(field "$p" content_hash)"; [ -n "$ch" ] && printf '%s\n' "$ch" >> "$trusted"
    fi
    prev="$(printf '%s' "$p" | sha)"
  done < "$PROV"
fi

# 2. Emit contracts whose sha(body) is in the trusted set; drop + log the rest.
printf '%s\n' "## Advisory System Twin contracts — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)"
emitted=0; dropped=0

emit_one() {
  f="$1"
  [ -f "$f" ] || return 0
  fh="$(cat "$f" | sha)"
  id="$(basename "$f" .md)"
  if grep -qxF "$fh" "$trusted" 2>/dev/null; then
    # Buffered, not printed: the store-health block below is computed from the FINAL counters and
    # has to precede the contract bodies, so the bodies cannot go straight to stdout from here.
    { printf '\n### contract: %s\n' "$id"; cat "$f"; } >> "$body_out"
    emitted=$((emitted+1))
  else
    printf '[%s] DROPPED unverified contract: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" "$f" >> "$LOG"
    dropped=$((dropped+1))
  fi
}

if [ -n "$SUBSYSTEM" ]; then
  emit_one "$CONTRACT_DIR/$(safe_id "$SUBSYSTEM").md"
else
  for f in "$CONTRACT_DIR"/*.md; do
    [ -e "$f" ] || continue   # nullglob-safe: literal pattern when dir is empty
    emit_one "$f"
  done
fi

# ---------------------------------------------------------------------------
# STORE-HEALTH CLASSIFICATION — the difference between "nothing stored" and "everything dropped".
#
# WHY THIS EXISTS (incident of 2026-09-01, root cause dated 2026-08-12): a tree-wide rebrand `sed`
# rewrote every body under .supervisor/twin/contracts/ in place — outside write-system-contract.sh,
# so no provenance was appended. All 21 contracts then failed the gate. The gate did exactly its
# job, but its OUTPUT was "(no verified System Twin contracts)" — byte-identical to an empty store —
# so every consumer (Phase 4.5 twin enrichment, the Phase 4.5 delta line, /dreaming's contract-drift
# GATHER) recorded `skipped` and nobody noticed for two weeks. The drops WERE recorded, in
# .supervisor/logs/twin.log, which is a file no consumer reads and no human opens unprompted.
#
# So the drop count is now part of the READ RESULT, on stdout, where the consumers already look —
# not only on stderr and in a log. NOTHING here relaxes the gate: an unverified contract is still
# dropped and still emits no content. The change is that its ABSENCE is now speakable.
#
# `twin_store_status:` is the stable machine-readable token; the `!!` block is the human one. The
# legacy `(no verified System Twin contracts)` sentinel below is PINNED — skills/self-heal-advisory
# tests for that exact string — so it is kept verbatim rather than replaced.
# ---------------------------------------------------------------------------
considered=$((emitted + dropped))
if   [ "$considered" -eq 0 ]; then status="empty"
elif [ "$dropped"    -eq 0 ]; then status="healthy"
elif [ "$emitted"    -eq 0 ]; then status="dark"
else                               status="degraded"
fi
printf 'twin_store_status: %s (emitted %s, dropped %s, stored %s)\n' "$status" "$emitted" "$dropped" "$considered"

if [ "$status" = "dark" ] || [ "$status" = "degraded" ]; then
  # Reported relative to this script so the remedy is copy-pasteable from wherever it was invoked.
  HERE_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || printf '%s' ".")"
  if [ "$status" = "dark" ]; then
    printf '%s\n' "!! SYSTEM TWIN READ PATH IS DARK — all $dropped stored contract(s) failed provenance verification, so this read returned NO contract content."
    printf '%s\n' "!! This is NOT an empty store. The contracts exist on disk; their bodies were changed OUTSIDE write-system-contract.sh (a tree-wide edit, a rename or a scrub pass), so their content hashes are absent from $PROV."
  else
    printf '%s\n' "!! SYSTEM TWIN STORE IS DEGRADED — $dropped of $considered stored contract(s) failed provenance verification and were dropped; only $emitted were emitted."
  fi
  printf '%s\n' "!! The gate is behaving as designed — do NOT weaken it. Per-file drop records: $LOG"
  printf '%s\n' "!! Inspect:        bash $HERE_DIR/reprovenance-twin-contracts.sh"
  printf '%s\n' "!! Re-provenance:  bash $HERE_DIR/reprovenance-twin-contracts.sh --confirm   (blesses the CURRENT on-disk bodies — read the report first)"
fi

[ "$emitted" -eq 0 ] && printf '%s\n' "(no verified System Twin contracts)"
cat "$body_out"

if [ "$status" = "dark" ]; then
  echo "read-system-contract: READ PATH DARK — dropped ALL $dropped stored contract(s) as unverified; consumers are receiving nothing. See $LOG and run reprovenance-twin-contracts.sh" >&2
elif [ "$dropped" -gt 0 ]; then
  echo "read-system-contract: dropped $dropped unverified contract(s) — see $LOG" >&2
fi
exit 0
