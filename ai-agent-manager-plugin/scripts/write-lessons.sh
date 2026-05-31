#!/usr/bin/env bash
# write-lessons.sh — sole sanctioned WRITER for advisory project LESSONS (v14.5.0).
#
# Appends a (human-approved) durable lesson to .supervisor/memory/LESSONS.md, grouped under a
# `## <category-slug>` heading, enforces a per-category bound of <=3 active entries via
# write-time eviction of the OLDEST entry in that category, and writes atomically (temp + mv).
#
# ADVISORY only — subordinate to the human-authored CLAUDE.md; NEVER an enforcement boundary.
# Promotion is human-gated: callers write only lessons a human has approved.
#
# SAFETY INVARIANT (closes red-team F1): refuses to run from a git worktree. Workers run in
# worktrees whose CWD is NOT the repo root; a write there would diverge and be lost on
# `git worktree remove`. Only callers at the repo root may write. The worktree check is the
# real enforcement, regardless of caller.
#
# PROVENANCE NOTE (v1): unlike write-project-memory.sh, LESSONS intentionally has NO hash-chain
# provenance in v1. Lessons are human-approved at write time AND bounded per category. The
# load-bearing safety properties are: the worktree guard, the atomic temp-in-dir + mv write,
# and the per-category <=3 bound. Provenance parity with PROJECT_MEMORY (tamper-detection /
# poison-drop) is a possible P5 hardening, not shipped in v1.
#
# Usage:  write-lessons.sh --category "<cat>" --lesson "<text>" [--source "<id>"]
# Exit:   0 on success or safe no-op (e.g. no sha tool); non-zero only on a disallowed /
#         would-corrupt condition (so a bad call can never half-write state).

set -uo pipefail

CATEGORY=""; LESSON=""; SOURCE="unknown"
while [ $# -gt 0 ]; do
  case "$1" in
    --category)   CATEGORY="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --category=*) CATEGORY="${1#--category=}"; shift ;;
    --lesson)     LESSON="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --lesson=*)   LESSON="${1#--lesson=}"; shift ;;
    --source)     SOURCE="${2:-unknown}"; shift; [ $# -gt 0 ] && shift ;;
    --source=*)   SOURCE="${1#--source=}"; shift ;;
    *) shift ;;
  esac
done
[ -n "$CATEGORY" ] || { echo "write-lessons: --category is required" >&2; exit 2; }
[ -n "$LESSON" ]   || { echo "write-lessons: --lesson is required" >&2; exit 2; }

# Sanitize --source of quotes/backslashes/control chars (label only — kept for future use).
SOURCE="$(printf '%s' "$SOURCE" | tr -d '"\\[:cntrl:]')"
[ -n "$SOURCE" ] || SOURCE="unknown"

# Slugify --category: lowercase, strip control chars, spaces/punct -> hyphens, collapse + trim
# hyphens. Keeps it safe as a markdown `##` heading and stable for grouping.
CATSLUG="$(printf '%s' "$CATEGORY" \
  | tr -d '[:cntrl:]' \
  | tr '[:upper:]' '[:lower:]' \
  | tr -c 'a-z0-9' '-' \
  | sed -E 's/-+/-/g; s/^-+//; s/-+$//')"
[ -n "$CATSLUG" ] || CATSLUG="uncategorized"

# ---- Worktree guard (red-team F1) -----------------------------------------
GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$GITROOT" ] || { echo "write-lessons: not inside a git repo — refusing" >&2; exit 2; }
# A linked worktree's top-level has a `.git` FILE ("gitdir: ..."); the main checkout has a dir.
if [ -f "$GITROOT/.git" ]; then
  echo "write-lessons: refusing to write from a git worktree ($GITROOT) — lessons are written only from the repo root (red-team F1)." >&2
  exit 3
fi
cd "$GITROOT" || { echo "write-lessons: cannot cd to repo root" >&2; exit 2; }

# ---- sha tool (fail-safe: no tool -> no write) ----------------------------
if command -v sha256sum >/dev/null 2>&1; then   sha() { sha256sum | cut -d' ' -f1; }
elif command -v shasum  >/dev/null 2>&1; then   sha() { shasum -a 256 | cut -d' ' -f1; }
else
  echo "write-lessons: no sha256 tool (sha256sum/shasum) — writes disabled, fail-safe no-op" >&2
  exit 0
fi

MEM_DIR=".supervisor/memory"
LESSONS="$MEM_DIR/LESSONS.md"
MAX_PER_CAT=3

mkdir -p "$MEM_DIR" 2>/dev/null || { echo "write-lessons: cannot create $MEM_DIR" >&2; exit 2; }
[ -f "$LESSONS" ] || printf '# Project Lessons (advisory — bounded <=3 active per category; written only via write-lessons.sh)\n' > "$LESSONS"

lesson_oneline="$(printf '%s' "$LESSON" | tr '\n' ' ')"
content_hash="$(printf '%s' "$CATSLUG $lesson_oneline" | sha)"
id="$(printf '%s' "$content_hash" | cut -c1-8)"

# Dedup guard: id is content-derived (category + lesson), so an identical lesson in the same
# category yields an identical entry. Skip if already present.
if grep -qF -- "- [$id] $lesson_oneline" "$LESSONS" 2>/dev/null; then
  echo "write-lessons: lesson already present ([$id] in $CATSLUG) — skipping"
  exit 0
fi

# Temps live IN the memory dir (not $TMPDIR) so the commit `mv` is a same-filesystem, truly
# atomic rename — a tmpfs /tmp would otherwise make `mv` a non-atomic cross-device copy+unlink.
tmp="$(mktemp "$MEM_DIR/.ltmp.XXXXXX")"
trap 'rm -f "$tmp" 2>/dev/null' EXIT

# Rebuild the file with awk:
#  - locate the `## <CATSLUG>` section; insert the new line at its end (before the next `##` or EOF)
#  - if the section is absent, append it (heading + line) at EOF
#  - within the target section, enforce <=MAX_PER_CAT entries by evicting the OLDEST (first) ones
awk -v cat="$CATSLUG" -v id="$id" -v lesson="$lesson_oneline" -v maxc="$MAX_PER_CAT" '
  BEGIN { hdr = "## " cat; inserted = 0 }
  # Collect lines into an array so we can post-process the target section in one pass.
  { lines[NR] = $0 }
  END {
    n = NR
    # Find target section bounds.
    sec_start = 0; sec_end = 0
    for (i = 1; i <= n; i++) {
      if (lines[i] == hdr) { sec_start = i; break }
    }
    if (sec_start > 0) {
      sec_end = n
      for (i = sec_start + 1; i <= n; i++) {
        if (lines[i] ~ /^## /) { sec_end = i - 1; break }
      }
    }

    if (sec_start == 0) {
      # No section yet: print everything, then append a fresh section.
      for (i = 1; i <= n; i++) print lines[i]
      print hdr
      print "- [" id "] " lesson
    } else {
      # Print up to (and including) the heading.
      for (i = 1; i <= sec_start; i++) print lines[i]
      # Gather existing entry lines in the section, then append the new one.
      ec = 0
      for (i = sec_start + 1; i <= sec_end; i++) {
        if (lines[i] ~ /^- \[/) { ec++; entries[ec] = lines[i] }
      }
      ec++; entries[ec] = "- [" id "] " lesson
      # Evict the oldest (front) entries until <= maxc remain.
      start = 1
      while ((ec - start + 1) > maxc) start++
      for (j = start; j <= ec; j++) print entries[j]
      # Print the remainder of the file (from the next section onward).
      for (i = sec_end + 1; i <= n; i++) print lines[i]
    }
  }
' "$LESSONS" > "$tmp"

mv "$tmp" "$LESSONS" || {
  echo "write-lessons: atomic rename failed — write aborted" >&2
  exit 2
}
echo "write-lessons: stored [$id] in $CATSLUG (source=$SOURCE)"
exit 0
