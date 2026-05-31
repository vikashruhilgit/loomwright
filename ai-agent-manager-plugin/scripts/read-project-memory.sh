#!/usr/bin/env bash
# read-project-memory.sh — sole sanctioned READER / the read-side provenance gate (v14.3.0).
#
# Emits ONLY PROJECT_MEMORY.md lines that are backed by a chain-valid `add` provenance entry.
# Any line that is unverified — an out-of-band poisoned append, or anything beyond a broken
# point in the hash chain — is DROPPED and logged to .supervisor/logs/memory.log. This is the
# read-side enforcement the red-team (W1) required: write-side provenance alone is theater.
#
# Output is ADVISORY and prefixed with a subordinate-to-CLAUDE.md banner. Agents (Launch Pad
# in v1) call this instead of `cat`-ing the file. Fail-safe: if no sha tool, emit nothing.
#
# Usage:  read-project-memory.sh           (prints verified memory to stdout)
# Exit:   always 0 (a read must never break the caller); diagnostics go to stderr + memory.log.

set -uo pipefail

GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$GITROOT" 2>/dev/null || true

MEM_DIR=".supervisor/memory"
MEM="$MEM_DIR/PROJECT_MEMORY.md"
PROV="$MEM_DIR/.provenance.jsonl"
LOG=".supervisor/logs/memory.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

[ -f "$MEM" ] || exit 0   # no memory yet → emit nothing

if command -v sha256sum >/dev/null 2>&1; then   sha() { sha256sum | cut -d' ' -f1; }
elif command -v shasum  >/dev/null 2>&1; then   sha() { shasum -a 256 | cut -d' ' -f1; }
else echo "read-project-memory: no sha256 tool — memory unverifiable, emitting nothing (fail-safe)" >&2; exit 0; fi

field() { printf '%s' "$1" | sed -E "s/.*\"$2\":\"([^\"]*)\".*/\1/"; }

# 1. Walk the provenance chain; collect content_hashes of chain-valid `add` entries.
trusted="$(mktemp)"; trap 'rm -f "$trusted" 2>/dev/null' EXIT
prev="GENESIS"; n=0
if [ -f "$PROV" ]; then
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    n=$((n+1))
    if [ "$(field "$p" prev_hash)" != "$prev" ]; then
      echo "read-project-memory: provenance chain broken at entry $n — distrusting it and everything after" >&2
      break
    fi
    if [ "$(field "$p" action)" = "add" ]; then
      ch="$(field "$p" content_hash)"; [ -n "$ch" ] && printf '%s\n' "$ch" >> "$trusted"
    fi
    prev="$(printf '%s' "$p" | sha)"
  done < "$PROV"
fi

# 2. Emit memory entries whose sha(fact) is in the trusted set; drop + log the rest.
printf '%s\n' "## Advisory project memory — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)"
emitted=0; dropped=0
while IFS= read -r line; do
  case "$line" in
    "- ["*) ;;        # a memory entry
    *) continue ;;    # header / blanks
  esac
  fact="$(printf '%s' "$line" | sed -E 's/^- \[[^]]*\] //')"
  fh="$(printf '%s' "$fact" | sha)"
  if grep -qxF "$fh" "$trusted" 2>/dev/null; then
    printf '%s\n' "$line"; emitted=$((emitted+1))
  else
    printf '[%s] DROPPED unverified memory line: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" "$line" >> "$LOG"
    dropped=$((dropped+1))
  fi
done < "$MEM"

[ "$emitted" -eq 0 ] && printf '%s\n' "(no verified project-memory entries)"
[ "$dropped" -gt 0 ] && echo "read-project-memory: dropped $dropped unverified line(s) — see $LOG" >&2
exit 0
