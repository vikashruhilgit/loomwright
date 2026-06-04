#!/usr/bin/env bash
# write-system-contract.sh — sole sanctioned WRITER for the System Twin contract store (v14.10.0).
#
# Writes a per-subsystem SYSTEM_CONTRACT artifact to
# .supervisor/twin/contracts/<subsystem-id>.md and appends a hash-chained provenance entry to
# .supervisor/twin/.provenance.jsonl. Writes atomically (temp + mv), enforces a contract-file
# cap via write-time eviction, and de-duplicates identical (subsystem + body) writes.
#
# .supervisor/twin/ is an ADVISORY artifact store like .supervisor/memory/ — subordinate to the
# human-authored CLAUDE.md; it is NEVER an enforcement boundary. Contracts are propose-only;
# conformance checks against them are advisory and NEVER block a PR or change a heal decision.
#
# SAFETY INVARIANT (sole-writer / pinned-CWD contract): this is the ONLY writer of
# .supervisor/twin/. It refuses to run from a git worktree (a linked worktree's top-level has a
# `.git` FILE, not a dir) with exit 3 — the ephemeral builder MUST run from the pinned repo-root
# CWD. A twin write inside a worktree would diverge and be lost on `git worktree remove`. The
# worktree check is the real enforcement, regardless of caller. Context-Keeper is NOT in this
# path: it remains the sole writer of state.md only.
#
# Usage:  write-system-contract.sh --subsystem "<id>" --contract-file <path> [--source "<id>"]
#         write-system-contract.sh --subsystem "<id>" --source "<id>"   # body on stdin
#         (the contract body is read from --contract-file if given, otherwise from stdin; the
#          body may be JSON or markdown — the store keeps it verbatim as the artifact.)
# Exit:   0 on success or safe no-op (e.g. no sha tool); 2 on a bad/would-corrupt call;
#         3 when refused from a git worktree (sole-writer/pinned-CWD violation).

set -uo pipefail

SUBSYSTEM=""; CONTRACT_FILE=""; SOURCE="unknown"
while [ $# -gt 0 ]; do
  case "$1" in
    --subsystem)      SUBSYSTEM="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --subsystem=*)    SUBSYSTEM="${1#--subsystem=}"; shift ;;
    --contract-file)  CONTRACT_FILE="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --contract-file=*) CONTRACT_FILE="${1#--contract-file=}"; shift ;;
    --source)         SOURCE="${2:-unknown}"; shift; [ $# -gt 0 ] && shift ;;
    --source=*)       SOURCE="${1#--source=}"; shift ;;
    *) shift ;;
  esac
done
[ -n "$SUBSYSTEM" ] || { echo "write-system-contract: --subsystem is required" >&2; exit 2; }
# Sanitize the source label of quotes/backslashes/control chars so the no-jq provenance fallback
# (printf-built JSON) can never emit malformed JSONL even if a caller widens --source.
SOURCE="$(printf '%s' "$SOURCE" | tr -d '"\\[:cntrl:]')"
[ -n "$SOURCE" ] || SOURCE="unknown"
# Sanitize the subsystem id for JSON the same way --source is, so the no-jq provenance fallback
# (printf-built JSON) can never emit malformed JSONL if a subsystem id contains " or \. The
# ORIGINAL $SUBSYSTEM is still used for the contract filename (SAFE_ID) and dedup logic; only the
# value that lands in provenance JSON is sanitized here.
SUBSYSTEM_JSON="$(printf '%s' "$SUBSYSTEM" | tr -d '"\\[:cntrl:]')"

# Sanitize the subsystem id into a safe filename: collapse path separators and anything that is
# not [A-Za-z0-9._-] into '-'. The logical id is preserved verbatim in the artifact body; this
# only governs the on-disk filename so e.g. "scripts/build-insights.sh" -> "scripts-build-insights.sh".
SAFE_ID="$(printf '%s' "$SUBSYSTEM" | tr '/' '-' | sed -E 's/[^A-Za-z0-9._-]/-/g; s/-+/-/g; s/^-+//; s/-+$//')"
[ -n "$SAFE_ID" ] || { echo "write-system-contract: --subsystem '$SUBSYSTEM' sanitizes to an empty filename" >&2; exit 2; }

# ---- Worktree guard (sole-writer / pinned-CWD enforcement) ----------------
GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$GITROOT" ] || { echo "write-system-contract: not inside a git repo — refusing" >&2; exit 2; }
# A linked worktree's top-level has a `.git` FILE ("gitdir: ..."); the main checkout has a dir.
if [ -f "$GITROOT/.git" ]; then
  echo "write-system-contract: refusing to write from a git worktree ($GITROOT) — the twin store is written only from the pinned repo root (sole-writer/pinned-CWD contract)." >&2
  exit 3
fi
cd "$GITROOT" || { echo "write-system-contract: cannot cd to repo root" >&2; exit 2; }

# ---- Read the contract body (file or stdin) -------------------------------
if [ -n "$CONTRACT_FILE" ]; then
  [ -f "$CONTRACT_FILE" ] || { echo "write-system-contract: --contract-file '$CONTRACT_FILE' not found" >&2; exit 2; }
  BODY="$(cat "$CONTRACT_FILE")"
else
  BODY="$(cat)"   # stdin
fi
[ -n "$BODY" ] || { echo "write-system-contract: empty contract body (provide --contract-file or pipe on stdin)" >&2; exit 2; }

# ---- sha tool (fail-safe: no tool -> no write) ----------------------------
if command -v sha256sum >/dev/null 2>&1; then   sha() { sha256sum | cut -d' ' -f1; }
elif command -v shasum  >/dev/null 2>&1; then   sha() { shasum -a 256 | cut -d' ' -f1; }
else
  echo "write-system-contract: no sha256 tool (sha256sum/shasum) — writes disabled, fail-safe no-op" >&2
  exit 0
fi

TWIN_DIR=".supervisor/twin"
CONTRACT_DIR="$TWIN_DIR/contracts"
PROV="$TWIN_DIR/.provenance.jsonl"
MAX_CONTRACTS="${SYSTEM_TWIN_MAX_CONTRACTS:-200}"   # overridable for tests; cap on #contract files
GENESIS="GENESIS"
CONTRACT="$CONTRACT_DIR/$SAFE_ID.md"

mkdir -p "$CONTRACT_DIR" 2>/dev/null || { echo "write-system-contract: cannot create $CONTRACT_DIR" >&2; exit 2; }
[ -f "$PROV" ] || : > "$PROV"

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"

# Temps live IN the twin dir (not $TMPDIR) so the commit `mv` is a same-filesystem, truly-atomic
# rename — a tmpfs /tmp (Linux/CI) would otherwise make `mv` a non-atomic cross-device copy+unlink,
# risking a truncated .provenance.jsonl on interruption.
c_tmp="$(mktemp "$CONTRACT_DIR/.ctmp.XXXXXX")"; prov_tmp="$(mktemp "$TWIN_DIR/.ptmp.XXXXXX")"
trap 'rm -f "$c_tmp" "$prov_tmp" 2>/dev/null' EXIT

# Materialize the exact bytes that will land on disk, THEN hash them. Hashing the file (not the
# in-memory $BODY) keeps the writer's content_hash byte-identical to what the reader recomputes
# via `cat <file> | sha`, regardless of trailing-newline normalization by $(cat ...).
printf '%s\n' "$BODY" > "$c_tmp"
content_hash="$(cat "$c_tmp" | sha)"

# Dedup guard: the content_hash is body-derived. If the current verified contract for this
# subsystem already has the same content_hash, this is a no-op (avoids redundant chain growth).
if [ -f "$CONTRACT" ]; then
  existing_hash="$(cat "$CONTRACT" | sha)"
  if [ "$existing_hash" = "$content_hash" ]; then
    echo "write-system-contract: contract for '$SUBSYSTEM' unchanged (hash $content_hash) — skipping"
    exit 0
  fi
fi

last_line="$(tail -n1 "$PROV" 2>/dev/null || true)"
if [ -n "$last_line" ]; then prev_hash="$(printf '%s' "$last_line" | sha)"; else prev_hash="$GENESIS"; fi

# prov_line <subsystem> <prev_hash> <content_hash> <source> <action>
# Emits JSON with NO trailing newline; callers add exactly one via printf '%s\n'. (jq -nc would
# otherwise append its own newline → blank lines that break the hash chain.)
prov_line() {
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg ss "$1" --arg ph "$2" --arg ch "$3" --arg src "$4" --arg act "$5" --arg ts "$ts" \
      '{subsystem:$ss,prev_hash:$ph,content_hash:$ch,source:$src,action:$act,written_at:$ts}' | tr -d '\n'
  else
    printf '{"subsystem":"%s","prev_hash":"%s","content_hash":"%s","source":"%s","action":"%s","written_at":"%s"}' "$1" "$2" "$3" "$4" "$5" "$ts"
  fi
}

cat "$PROV" > "$prov_tmp"
printf '%s\n' "$(prov_line "$SUBSYSTEM_JSON" "$prev_hash" "$content_hash" "$SOURCE" "add")" >> "$prov_tmp"

# Commit. Provenance FIRST: if the second rename fails, the worst case is a provenance entry with
# no matching contract file — which the read-side gate harmlessly ignores. A failed first rename
# leaves state untouched.
mv "$prov_tmp" "$PROV" && mv "$c_tmp" "$CONTRACT" || {
  echo "write-system-contract: atomic rename failed — write aborted; read gate ignores any unmatched provenance" >&2
  exit 2
}

# ---- Write-time eviction (cap on number of contract files; never silent) --
# NOTE: .provenance.jsonl is append-only (one line per add AND per evict), so each read walks the
# full chain (O(n)). Provenance compaction / re-genesis is a P4 follow-up — fine at the v1 scale.
count="$(find "$CONTRACT_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
while [ "${count:-0}" -gt "$MAX_CONTRACTS" ]; do
  # Evict the oldest contract file by mtime (excluding the one just written when possible).
  victim="$(ls -1tr "$CONTRACT_DIR"/*.md 2>/dev/null | head -n1)"
  [ -n "$victim" ] || break
  vid="$(basename "$victim" .md)"
  rm -f "$victim"
  eph="$(printf '%s' "$(tail -n1 "$PROV")" | sha)"
  printf '%s\n' "$(prov_line "$vid" "$eph" "" "eviction" "evict")" >> "$PROV"
  count="$(find "$CONTRACT_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
done

echo "write-system-contract: stored contract for '$SUBSYSTEM' ($CONTRACT, hash $content_hash, source=$SOURCE)"
exit 0
