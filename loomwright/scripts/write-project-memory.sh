#!/usr/bin/env bash
# write-project-memory.sh — sole sanctioned WRITER for advisory project memory (v14.3.0).
#
# Appends a (human-approved) durable fact to .supervisor/memory/PROJECT_MEMORY.md plus a
# hash-chained provenance entry to .supervisor/memory/.provenance.jsonl, enforces the
# <=200-line cap via write-time eviction, and writes atomically (temp + mv).
#
# ADVISORY memory only — subordinate to the human-authored CLAUDE.md; NEVER an enforcement
# boundary. Promotion is human-gated: callers write only facts a human has approved.
#
# SAFETY INVARIANT (closes red-team F1): refuses to run from a git worktree. Workers run in
# worktrees whose CWD is NOT the repo root; a memory write there would diverge and be lost on
# `git worktree remove`. Only callers at the repo root (Launch Pad, Context-Keeper, main
# thread) may write. The worktree check is the real enforcement, regardless of caller.
#
# Usage:  write-project-memory.sh --fact "<durable fact>" --source "<session_id|agent|user>"
# Exit:   0 on success or safe no-op (e.g. no sha tool); non-zero only on a disallowed /
#         would-corrupt condition (so a bad call can never half-write state).

set -uo pipefail

FACT=""; SOURCE="unknown"
while [ $# -gt 0 ]; do
  case "$1" in
    --fact)     FACT="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --fact=*)   FACT="${1#--fact=}"; shift ;;
    --source)   SOURCE="${2:-unknown}"; shift; [ $# -gt 0 ] && shift ;;
    --source=*) SOURCE="${1#--source=}"; shift ;;
    *) shift ;;
  esac
done
[ -n "$FACT" ] || { echo "write-project-memory: --fact is required" >&2; exit 2; }
# Sanitize the source label of quotes/backslashes so the no-jq provenance fallback
# (printf-built JSON) can never emit malformed JSONL even if a caller widens --source.
SOURCE="$(printf '%s' "$SOURCE" | tr -d '"\\[:cntrl:]')"
[ -n "$SOURCE" ] || SOURCE="unknown"

# ---- Worktree guard -------------------------------------------------------
GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$GITROOT" ] || { echo "write-project-memory: not inside a git repo — refusing" >&2; exit 2; }
# A linked worktree's top-level has a `.git` FILE ("gitdir: ..."); the main checkout has a dir.
if [ -f "$GITROOT/.git" ]; then
  echo "write-project-memory: refusing to write from a git worktree ($GITROOT) — memory is written only from the repo root (red-team F1)." >&2
  exit 3
fi
cd "$GITROOT" || { echo "write-project-memory: cannot cd to repo root" >&2; exit 2; }

# ---- sha tool (fail-safe: no tool -> no write) ----------------------------
if command -v sha256sum >/dev/null 2>&1; then   sha() { sha256sum | cut -d' ' -f1; }
elif command -v shasum  >/dev/null 2>&1; then   sha() { shasum -a 256 | cut -d' ' -f1; }
else
  echo "write-project-memory: no sha256 tool (sha256sum/shasum) — writes disabled, fail-safe no-op" >&2
  exit 0
fi

MEM_DIR=".supervisor/memory"
MEM="$MEM_DIR/PROJECT_MEMORY.md"
PROV="$MEM_DIR/.provenance.jsonl"
MAX_LINES="${PROJECT_MEMORY_MAX_LINES:-200}"   # overridable for tests; default = Memory Core Principle cap
GENESIS="GENESIS"

mkdir -p "$MEM_DIR" 2>/dev/null || { echo "write-project-memory: cannot create $MEM_DIR" >&2; exit 2; }
[ -f "$MEM" ]  || printf '# Project Memory (advisory — subordinate to CLAUDE.md; written only via write-project-memory.sh)\n' > "$MEM"
[ -f "$PROV" ] || : > "$PROV"

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
fact_oneline="$(printf '%s' "$FACT" | tr '\n' ' ')"
content_hash="$(printf '%s' "$fact_oneline" | sha)"
id="$(printf '%s' "$content_hash" | cut -c1-8)"
# Dedup guard: the id is content-derived, so an identical fact yields an identical entry.
# If it's already present in the live index, skip (avoids silent duplicate-fact accumulation).
if grep -qF -- "- [$id] $fact_oneline" "$MEM" 2>/dev/null; then
  echo "write-project-memory: fact already present ([$id]) — skipping"
  exit 0
fi
last_line="$(tail -n1 "$PROV" 2>/dev/null || true)"
if [ -n "$last_line" ]; then prev_hash="$(printf '%s' "$last_line" | sha)"; else prev_hash="$GENESIS"; fi

# prov_line <id> <prev_hash> <content_hash> <source> <action>
# Emits the JSON with NO trailing newline; callers add exactly one via printf '%s\n'.
# (jq -nc would otherwise append its own newline → blank lines that break the hash chain.)
prov_line() {
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg id "$1" --arg ph "$2" --arg ch "$3" --arg src "$4" --arg act "$5" --arg ts "$ts" \
      '{id:$id,prev_hash:$ph,content_hash:$ch,source:$src,action:$act,written_at:$ts}' | tr -d '\n'
  else
    printf '{"id":"%s","prev_hash":"%s","content_hash":"%s","source":"%s","action":"%s","written_at":"%s"}' "$1" "$2" "$3" "$4" "$5" "$ts"
  fi
}

# Temps live IN the memory dir (not $TMPDIR) so the commit `mv` is a same-filesystem,
# truly-atomic rename — a tmpfs /tmp (Linux/CI) would otherwise make `mv` a non-atomic
# cross-device copy+unlink, risking a truncated .provenance.jsonl on interruption.
mem_tmp="$(mktemp "$MEM_DIR/.mtmp.XXXXXX")"; prov_tmp="$(mktemp "$MEM_DIR/.ptmp.XXXXXX")"
trap 'rm -f "$mem_tmp" "$prov_tmp" "$mem_tmp.e" 2>/dev/null' EXIT
cat "$MEM" > "$mem_tmp"
printf -- '- [%s] %s\n' "$id" "$fact_oneline" >> "$mem_tmp"
cat "$PROV" > "$prov_tmp"
printf '%s\n' "$(prov_line "$id" "$prev_hash" "$content_hash" "$SOURCE" "add")" >> "$prov_tmp"

# ---- Write-time eviction (cap; never silent) ------------------------------
# NOTE: .provenance.jsonl is append-only (one line per add AND per evict), so each read
# walks the full chain (O(n)). Provenance compaction / re-genesis once the log exceeds
# N x cap is a P4 follow-up — fine at the v1 200-entry scale.
count="$(grep -cE '^- \[' "$mem_tmp" 2>/dev/null)"
while [ "$count" -gt "$MAX_LINES" ]; do
  victim="$(grep -nE '^- \[' "$mem_tmp" | head -n1)"
  vid="$(printf '%s' "$victim" | sed -E 's/^[0-9]+:- \[([^]]+)\].*/\1/')"
  awk 'BEGIN{d=0} /^- \[/ && d==0 {d=1; next} {print}' "$mem_tmp" > "$mem_tmp.e" && mv "$mem_tmp.e" "$mem_tmp"
  eph="$(printf '%s' "$(tail -n1 "$prov_tmp")" | sha)"
  printf '%s\n' "$(prov_line "$vid" "$eph" "" "eviction" "evict")" >> "$prov_tmp"
  count="$(grep -cE '^- \[' "$mem_tmp" 2>/dev/null)"
done

# Commit both files. Provenance FIRST: if the second rename fails, the worst case is a
# provenance entry with no matching memory line — which the read-side gate silently ignores
# (no orphaned, repeatedly-logged memory line). A failed first rename leaves state untouched.
mv "$prov_tmp" "$PROV" && mv "$mem_tmp" "$MEM" || {
  echo "write-project-memory: atomic rename failed — write aborted; read gate ignores any unmatched provenance" >&2
  exit 2
}
echo "write-project-memory: stored [$id] (source=$SOURCE)"
exit 0
