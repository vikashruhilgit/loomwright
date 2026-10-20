#!/usr/bin/env bash
# read-project-memory.sh — sole sanctioned READER / the read-side provenance gate (v14.3.0).
#
# Emits ONLY PROJECT_MEMORY.md lines that are backed by a chain-valid `add` provenance entry.
# Any line that is unverified — an out-of-band poisoned append, or anything beyond a broken
# point in the hash chain — is DROPPED and logged to .supervisor/logs/memory.log. This is the
# read-side enforcement the red-team (W1) required: write-side provenance alone is theater.
#
# Output is ADVISORY and prefixed with a subordinate-to-CLAUDE.md banner. Agents (Launch Pad
# in v1) call this instead of `cat`-ing the file.
#
# Usage:  read-project-memory.sh            (terse default)
#         read-project-memory.sh --verbose  (the full pre-terse output, byte for byte)
# Default: ONE header line carrying the count — the banner + ` — <E> verified` — then one line per
#   verified entry. With nothing to emit it prints ONLY the header, ending ` — 0 verified (<token>)`,
#   where <token> is exactly one of: no_store | no_sha_tool | no_verified_entries.
# --verbose: the banner, the verified entries, then `(no verified project-memory entries)` when there
#   are none; NOTHING at all when there is no store or no sha tool (fail-safe). build-handoff.sh
#   passes it, so the handoff digest bytes are unchanged.
# Exit:   always 0 (a read must never break the caller); diagnostics go to stderr + memory.log.

set -uo pipefail   # `set -e` intentionally omitted — a read must NEVER fail its caller.

BANNER="## Advisory project memory — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)"
verbose=0
for a in "$@"; do
  case "$a" in
    --verbose) verbose=1 ;;
    *) echo "read-project-memory: unexpected argument $a (ignored)" >&2 ;;
  esac
done
# empty_exit <token> — nothing to emit: the default names why in its one header line; --verbose
# keeps the pre-terse silence.
empty_exit() { [ "$verbose" -eq 1 ] || printf '%s — 0 verified (%s)\n' "$BANNER" "$1"; exit 0; }

GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$GITROOT" 2>/dev/null || true

MEM_DIR=".supervisor/memory"
MEM="$MEM_DIR/PROJECT_MEMORY.md"
PROV="$MEM_DIR/.provenance.jsonl"
LOG=".supervisor/logs/memory.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

[ -f "$MEM" ] || empty_exit no_store   # no memory yet

if command -v sha256sum >/dev/null 2>&1; then   sha() { sha256sum | cut -d' ' -f1; }
elif command -v shasum  >/dev/null 2>&1; then   sha() { shasum -a 256 | cut -d' ' -f1; }
else echo "read-project-memory: no sha256 tool — memory unverifiable, emitting no entries (fail-safe)" >&2; empty_exit no_sha_tool; fi

field() { printf '%s' "$1" | sed -E "s/.*\"$2\":\"([^\"]*)\".*/\1/"; }

# 1. Walk the provenance chain; collect content_hashes of chain-valid `add` entries.
trusted="$(mktemp)"; trap 'rm -f "$trusted" "$trusted.x" 2>/dev/null' EXIT
prev="GENESIS"; n=0
if [ -f "$PROV" ]; then
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    n=$((n+1))
    if [ "$(field "$p" prev_hash)" != "$prev" ]; then
      echo "read-project-memory: provenance chain broken at entry $n (prev_hash mismatch — tampering, or a value that defeated field extraction) — distrusting it and everything after" >&2
      break
    fi
    act="$(field "$p" action)"
    if [ "$act" = "add" ]; then
      ch="$(field "$p" content_hash)"; [ -n "$ch" ] && printf '%s\n' "$ch" >> "$trusted"
    elif [ "$act" = "retract" ]; then
      # A retract REVOKES trust in that exact fact text. This must live on the READ side, not
      # only as a line deletion by the writer: the original `add` stays in the append-only
      # provenance log forever, so without this branch an out-of-band re-append of a retracted
      # (i.e. known-WRONG) fact would still hash-match a trusted `add` and be emitted as
      # verified. Chronological semantics: a later `add` of the same text re-trusts it.
      ch="$(field "$p" content_hash)"
      if [ -n "$ch" ]; then
        grep -vxF "$ch" "$trusted" > "$trusted.x" 2>/dev/null
        mv "$trusted.x" "$trusted" 2>/dev/null || true
      fi
    fi
    prev="$(printf '%s' "$p" | sha)"
  done < "$PROV"
fi

# 2. Emit memory entries whose sha(fact) is in the trusted set; drop + log the rest. Verified lines
#    are buffered so the default header can carry the count before them.
emitted=0; dropped=0; kept=""
while IFS= read -r line; do
  case "$line" in
    "- ["*) ;;        # a memory entry
    *) continue ;;    # header / blanks
  esac
  fact="$(printf '%s' "$line" | sed -E 's/^- \[[^]]*\] //')"
  fh="$(printf '%s' "$fact" | sha)"
  if grep -qxF "$fh" "$trusted" 2>/dev/null; then
    kept="$kept$line
"; emitted=$((emitted+1))
  else
    printf '[%s] DROPPED unverified memory line: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" "$line" >> "$LOG"
    dropped=$((dropped+1))
  fi
done < "$MEM"

[ "$dropped" -gt 0 ] && echo "read-project-memory: dropped $dropped unverified line(s) — see $LOG" >&2
if [ "$verbose" -eq 1 ]; then
  printf '%s\n' "$BANNER"
  printf '%s' "$kept"
  [ "$emitted" -eq 0 ] && printf '%s\n' "(no verified project-memory entries)"
elif [ "$emitted" -eq 0 ]; then
  empty_exit no_verified_entries
else
  printf '%s — %s verified\n' "$BANNER" "$emitted"
  printf '%s' "$kept"
fi
exit 0
