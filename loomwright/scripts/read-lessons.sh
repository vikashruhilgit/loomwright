#!/usr/bin/env bash
# read-lessons.sh — sole sanctioned READER / the read-side provenance + freshness gate.
# (New file — shipped on the v14.24.x line; parity with read-project-memory.sh, deferred at v14.5.0.)
#
# Emits ONLY LESSONS.md lines that are backed by a chain-valid `add` provenance entry in the
# LESSONS-SPECIFIC chain file .supervisor/memory/.lessons-provenance.jsonl. Any line that is
# unverified — an out-of-band poisoned append, or anything beyond a broken point in the hash
# chain — is DROPPED and logged to .supervisor/logs/memory.log. This is the read-side enforcement
# the red-team (W1) required: write-side provenance alone is theater. Mirrors read-project-memory.sh.
#
# FRESHNESS (Tier A read side): each verified lesson carries a `last_verified=<iso8601Z>` trailer.
# A verified lesson older than LESSON_STALE_DAYS (env, default 90) is SKIPPED (not emitted) and
# logged as STALE. A lesson with a missing/unparseable last_verified is treated as FRESH (fail-open
# for the lint — the provenance gate is the real security boundary; the stale-lint is advisory).
#
# RETRACT (curation verb — write side in write-lessons.sh): the chain walk honors last-action-wins.
# A chain-valid `action:"retract"` entry REMOVES its content_hash from the trusted set (a later
# re-add re-trusts). A LESSONS.md line whose hash was retracted is dropped like an unverified line
# but logged with a distinct RETRACTED label for auditability. A malformed retract entry
# (missing or empty content_hash) contributes nothing and never crashes the walk (fail-safe:
# malformed curation metadata ⇒ the targeted entries stay live).
#
# Output is ADVISORY and prefixed with a subordinate-to-CLAUDE.md banner. Agents call this instead
# of `cat`-ing the file. Fail-safe: if no sha tool, emit nothing.
#
# Usage:  read-lessons.sh           (prints verified+fresh lessons to stdout, grouped by `## <cat>`)
# Exit:   always 0 (a read must never break the caller); diagnostics go to stderr + memory.log.

set -uo pipefail   # `set -e` intentionally omitted — a read must NEVER fail its caller.

GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$GITROOT" 2>/dev/null || true

MEM_DIR=".supervisor/memory"
LESSONS="$MEM_DIR/LESSONS.md"
PROV="$MEM_DIR/.lessons-provenance.jsonl"
LOG=".supervisor/logs/memory.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

LESSON_STALE_DAYS="${LESSON_STALE_DAYS:-90}"

[ -f "$LESSONS" ] || exit 0   # no lessons yet → emit nothing

if command -v sha256sum >/dev/null 2>&1; then   sha() { sha256sum | cut -d' ' -f1; }
elif command -v shasum  >/dev/null 2>&1; then   sha() { shasum -a 256 | cut -d' ' -f1; }
else echo "read-lessons: no sha256 tool — lessons unverifiable, emitting nothing (fail-safe)" >&2; exit 0; fi

field() { printf '%s' "$1" | sed -E "s/.*\"$2\":\"([^\"]*)\".*/\1/"; }

# Portable ISO-8601 (Z) → epoch seconds. Tries GNU date, then BSD/macOS date. Echoes nothing on
# failure (caller treats empty as "unparseable → fresh").
iso_to_epoch() {
  local iso="$1" e=""
  e="$(date -d "$iso" +%s 2>/dev/null || true)"
  if [ -z "$e" ]; then
    e="$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null || true)"
  fi
  printf '%s' "$e"
}

# 1. Walk the provenance chain; collect content_hashes of chain-valid `add` entries. Last action
#    wins: a chain-valid `retract` entry removes its hash from the trusted set (and records it in
#    the retracted set so the drop below can carry a distinct RETRACTED label); a later re-add
#    re-trusts.
trusted="$(mktemp)"; retracted="$(mktemp)"
trap 'rm -f "$trusted" "$trusted.n" "$retracted" 2>/dev/null' EXIT
prev="GENESIS"; n=0
if [ -f "$PROV" ]; then
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    n=$((n+1))
    if [ "$(field "$p" prev_hash)" != "$prev" ]; then
      echo "read-lessons: provenance chain broken at entry $n (prev_hash mismatch — tampering, or a value that defeated field extraction) — distrusting it and everything after" >&2
      break
    fi
    act="$(field "$p" action)"
    if [ "$act" = "add" ]; then
      ch="$(field "$p" content_hash)"; [ -n "$ch" ] && printf '%s\n' "$ch" >> "$trusted"
    elif [ "$act" = "retract" ]; then
      # Key-presence check FIRST (nullable-required discipline): `field` echoes the WHOLE entry
      # when the key is absent, so gate on the literal key before extracting. A malformed retract
      # (missing/empty content_hash) contributes nothing — fail-safe, the walk continues.
      ch=""
      case "$p" in *'"content_hash":"'*) ch="$(field "$p" content_hash)" ;; esac
      if [ -n "$ch" ]; then
        grep -vxF -- "$ch" "$trusted" > "$trusted.n" 2>/dev/null || true
        mv "$trusted.n" "$trusted"
        printf '%s\n' "$ch" >> "$retracted"
      fi
    fi
    prev="$(printf '%s' "$p" | sha)"
  done < "$PROV"
fi

now_epoch="$(date -u +%s 2>/dev/null || echo 0)"
stale_secs=$(( LESSON_STALE_DAYS * 86400 ))

# 2. Emit lesson entries whose sha("<cat> <text>") is in the trusted set; drop+log the rest.
#    Track the current `## <cat>` heading; emit the heading before its first emitted entry so
#    grouping is preserved. Apply the stale-lint after provenance verification.
printf '%s\n' "## Advisory project lessons — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)"
emitted=0; dropped=0; stale=0; retr=0
cur_cat=""; cur_cat_emitted=0
while IFS= read -r line; do
  case "$line" in
    "## "*)
      # New category heading — defer emitting it until its first verified+fresh entry.
      cur_cat="${line#'## '}"; cur_cat_emitted=0
      continue ;;
    "- ["*) ;;        # a lesson entry
    *) continue ;;    # banner / blanks / file header
  esac

  # Extract lesson text: the part after `] ` up to (but not including) the `  <!--` trailer.
  text="$(printf '%s' "$line" | sed -E 's/^- \[[^]]*\] //; s/[[:space:]]*<!-- last_verified=.*-->[[:space:]]*$//')"
  fh="$(printf '%s' "$cur_cat $text" | sha)"
  if ! grep -qxF "$fh" "$trusted" 2>/dev/null; then
    # Distinct label for auditability: a line whose hash was TOMBSTONED via a chain-valid retract
    # is logged RETRACTED; anything else untrusted stays DROPPED (out-of-band poison / post-break).
    if grep -qxF "$fh" "$retracted" 2>/dev/null; then
      printf '[%s] RETRACTED lessons line (tombstoned via provenance): %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" "$line" >> "$LOG"
      retr=$((retr+1))
    else
      printf '[%s] DROPPED unverified lessons line: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" "$line" >> "$LOG"
      dropped=$((dropped+1))
    fi
    continue
  fi

  # Stale-lint: parse last_verified from the trailer; skip if older than the threshold.
  lv="$(printf '%s' "$line" | sed -nE 's/.*<!--.*last_verified=([^ ]+).*-->.*/\1/p')"
  if [ -n "$lv" ]; then
    lv_epoch="$(iso_to_epoch "$lv")"
    if [ -n "$lv_epoch" ] && [ "$now_epoch" -gt 0 ] && [ $(( now_epoch - lv_epoch )) -gt "$stale_secs" ]; then
      printf '[%s] STALE (>%sd) lessons line: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" "$LESSON_STALE_DAYS" "$line" >> "$LOG"
      stale=$((stale+1))
      continue
    fi
  fi

  # Verified + fresh: emit the category heading (once) then the full original line incl. trailer.
  if [ "$cur_cat_emitted" -eq 0 ] && [ -n "$cur_cat" ]; then
    printf '## %s\n' "$cur_cat"; cur_cat_emitted=1
  fi
  printf '%s\n' "$line"; emitted=$((emitted+1))
done < "$LESSONS"

[ "$emitted" -eq 0 ] && printf '%s\n' "(no verified lessons entries)"
[ "$dropped" -gt 0 ] && echo "read-lessons: dropped $dropped unverified line(s) — see $LOG" >&2
[ "$retr" -gt 0 ] && echo "read-lessons: dropped $retr retracted (tombstoned) line(s) — see $LOG" >&2
[ "$stale" -gt 0 ] && echo "read-lessons: skipped $stale stale (>${LESSON_STALE_DAYS}d) line(s) — see $LOG" >&2
exit 0
