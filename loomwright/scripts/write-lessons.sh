#!/usr/bin/env bash
# write-lessons.sh — sole sanctioned WRITER for advisory project LESSONS.
# (Bounded sole-writer introduced v14.5.0; provenance + freshness parity added on the v14.24.x line.)
#
# Appends a (human-approved) durable lesson to .supervisor/memory/LESSONS.md, grouped under a
# `## <category-slug>` heading, enforces a per-category bound of <=3 active entries via
# write-time eviction of the OLDEST entry in that category, and writes atomically (temp + mv).
# It also appends a hash-chained provenance entry to .supervisor/memory/.lessons-provenance.jsonl
# and stamps each lesson with machine-readable freshness metadata (last_verified + confidence).
#
# ADVISORY only — subordinate to the human-authored CLAUDE.md; NEVER an enforcement boundary.
# Promotion is human-gated: callers write only lessons a human has approved.
#
# SAFETY INVARIANT (closes red-team F1): refuses to run from a git worktree. Workers run in
# worktrees whose CWD is NOT the repo root; a write there would diverge and be lost on
# `git worktree remove`. Only callers at the repo root may write. The worktree check is the
# real enforcement, regardless of caller.
#
# PROVENANCE NOTE (deferred at v14.5.0; SHIPPED on the v14.24.x line, parity with PROJECT_MEMORY):
# hash-chain provenance is no longer deferred. Each add/evict appends a chained entry to a LESSONS-SPECIFIC chain file,
# `.supervisor/memory/.lessons-provenance.jsonl` (kept separate from PROJECT_MEMORY's
# `.provenance.jsonl` — interleaving two chains would break both walks), rooted at GENESIS, with
# one `evict` entry per evicted lesson. The matching sole-READER and read-side provenance gate is
# `read-lessons.sh` (drops out-of-band / un-provenanced poison lines, distrusts everything after a
# broken chain link). The remaining load-bearing properties are unchanged: the worktree guard, the
# atomic temp-in-dir + mv write (now of BOTH files, provenance FIRST), and the per-category <=3
# bound + oldest-eviction.
#
# FRESHNESS NOTE (SHIPPED on the v14.24.x line): each stored lesson carries a machine-readable
# `last_verified` ISO-8601 timestamp and a `confidence` value, appended as a parseable HTML-comment
# trailer (`<!-- last_verified=... confidence=... -->`) so markdown rendering and substring greps are
# unaffected and content_hash is NOT changed (the trailer never enters the hash). `read-lessons.sh`
# applies a read-side stale-lint (skips lessons older than LESSON_STALE_DAYS, default 90).
#
# RETRACT NOTE (curation verb): `retract` tombstones an existing lesson. It verifies the target is
# (1) present in LESSONS.md AND (2) chain-trusted — the LAST chain-valid action for its
# content_hash is `add` (last-action-wins: a prior retract untrusts, a later re-add re-trusts) —
# then appends a chain-valid `action:"retract"` provenance entry (the auditable tombstone; NEVER a
# silent deletion) and atomically rewrites LESSONS.md with the one entry line removed. The
# `## <category>` heading is left in place — read-lessons.sh already skips headings with no
# emitted entries. Unlike the fail-safe readers, retract is a gate-side tool and FAILS LOUD.
#
# Usage:  write-lessons.sh --category "<cat>" --lesson "<text>" \
#                          [--source "<id>"] [--last-verified "<iso8601Z>"] [--confidence "<value>"]
#         write-lessons.sh retract <category> <lesson-text> [--source "<id>"]
#         write-lessons.sh retract --hash <content_hash>    [--source "<id>"]
# Exit:   0 on success or safe no-op (e.g. no sha tool); non-zero only on a disallowed /
#         would-corrupt condition (so a bad call can never half-write state). retract exits 4
#         when the target is absent from LESSONS.md or not chain-trusted (fail loud, never
#         tombstone a nonexistent lesson silently).

set -uo pipefail

CATEGORY=""; LESSON=""; SOURCE="unknown"; LAST_VERIFIED=""; CONFIDENCE="medium"
# Subcommand detection: a leading `retract` selects the tombstone flow (default action is add).
ACTION="add"; HASH=""
if [ "${1:-}" = "retract" ]; then ACTION="retract"; shift; fi
while [ $# -gt 0 ]; do
  case "$1" in
    --category)        CATEGORY="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --category=*)      CATEGORY="${1#--category=}"; shift ;;
    --lesson)          LESSON="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --lesson=*)        LESSON="${1#--lesson=}"; shift ;;
    --source)          SOURCE="${2:-unknown}"; shift; [ $# -gt 0 ] && shift ;;
    --source=*)        SOURCE="${1#--source=}"; shift ;;
    --last-verified)   LAST_VERIFIED="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --last-verified=*) LAST_VERIFIED="${1#--last-verified=}"; shift ;;
    --confidence)      CONFIDENCE="${2:-medium}"; shift; [ $# -gt 0 ] && shift ;;
    --confidence=*)    CONFIDENCE="${1#--confidence=}"; shift ;;
    --hash)            HASH="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --hash=*)          HASH="${1#--hash=}"; shift ;;
    *) # retract accepts positional <category> <lesson-text> (in that order); add ignores strays.
       if [ "$ACTION" = "retract" ] && [ -z "$CATEGORY" ]; then CATEGORY="$1"
       elif [ "$ACTION" = "retract" ] && [ -z "$LESSON" ]; then LESSON="$1"
       fi
       shift ;;
  esac
done
if [ "$ACTION" = "retract" ]; then
  if [ -n "$HASH" ]; then
    # --hash identifies the target directly; must be a full lowercase sha256 (it feeds the
    # content-derived [id] grep below, so a partial/garbage value could mis-target an entry).
    case "$HASH" in
      *[!a-f0-9]*) echo "write-lessons: --hash must be lowercase sha256 hex" >&2; exit 2 ;;
    esac
    [ "${#HASH}" -eq 64 ] || { echo "write-lessons: --hash must be a full 64-char sha256" >&2; exit 2; }
  else
    { [ -n "$CATEGORY" ] && [ -n "$LESSON" ]; } || { echo "write-lessons: retract requires <category> <lesson-text> (or --hash <content_hash>)" >&2; exit 2; }
  fi
else
  [ -n "$CATEGORY" ] || { echo "write-lessons: --category is required" >&2; exit 2; }
  [ -n "$LESSON" ]   || { echo "write-lessons: --lesson is required" >&2; exit 2; }
fi

# Sanitize --source of quotes/backslashes/control chars so the no-jq provenance fallback
# (printf-built JSON) can never emit malformed JSONL even if a caller widens --source.
SOURCE="$(printf '%s' "$SOURCE" | tr -d '"\\<>[:cntrl:]')"
[ -n "$SOURCE" ] || SOURCE="unknown"

# Sanitize --confidence the same way --source is sanitized (it lands in the markdown trailer and
# is passed to awk via -v, so it must have no quotes/backslashes/ctrl). `<`/`>` are also dropped so
# a value like `high-->evil` can't inject comment delimiters into the `<!-- ... -->` trailer
# (defense-in-depth for the trailer shape the reader anchors to). NOTE: spaces are intentionally
# NOT stripped (a value like `high verified` is kept verbatim) — confidence is store-only,
# future-facing metadata; read-lessons.sh gates ONLY on last_verified and never parses confidence,
# so a space cannot distort the trailer strip or any gate.
CONFIDENCE="$(printf '%s' "$CONFIDENCE" | tr -d '"\\<>[:cntrl:]')"
[ -n "$CONFIDENCE" ] || CONFIDENCE="medium"

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
PROV="$MEM_DIR/.lessons-provenance.jsonl"
MAX_PER_CAT=3
GENESIS="GENESIS"

mkdir -p "$MEM_DIR" 2>/dev/null || { echo "write-lessons: cannot create $MEM_DIR" >&2; exit 2; }
# Only `add` bootstraps the store — `retract` on an absent store has nothing to tombstone and
# must fail loud below without creating files (a refused retract leaves state byte-identical).
if [ "$ACTION" = "add" ]; then
  [ -f "$LESSONS" ] || printf '# Project Lessons (advisory — bounded <=3 active per category; written only via write-lessons.sh)\n' > "$LESSONS"
  [ -f "$PROV" ] || : > "$PROV"
fi

# Freshness metadata: default last_verified to write time (same expression used elsewhere).
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
# An explicit --last-verified is accepted ONLY if it is a well-formed ISO-8601 UTC stamp
# (YYYY-MM-DDThh:mm:ssZ); anything else falls back to the write-time default. This keeps
# LAST_VERIFIED a clean [0-9T:Z-] value with NO spaces / backslashes / angle-brackets — so it
# can neither distort the `<!-- ... -->` trailer the reader anchors on (e.g. `--last-verified
# "x --> y"`) nor be reinterpreted by the `awk -v lv=` pass below (which treats backslash escapes).
# This restores the symmetry with the --source/--confidence sanitizers and makes the awk -v
# backslash-safety note accurate for lv even when the caller passes the flag explicitly.
if [ -n "$LAST_VERIFIED" ]; then
  case "$LAST_VERIFIED" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) : ;;
    *) echo "write-lessons: --last-verified '$LAST_VERIFIED' is not ISO-8601 UTC (YYYY-MM-DDThh:mm:ssZ) — using write time" >&2
       LAST_VERIFIED="" ;;
  esac
fi
[ -n "$LAST_VERIFIED" ] || LAST_VERIFIED="$ts"

# Trim TRAILING whitespace from the one-lined lesson so the stored text and the hashed text agree
# (command substitution strips trailing newlines but NOT trailing spaces; the reader's trailer
# strip eats trailing spaces before the trailer, so a divergence here silently drops the lesson).
# This trims ONLY trailing whitespace — interior backslashes / spaces are untouched. The SAME
# value feeds both content_hash and the awk-stored line below.
lesson_oneline="$(printf '%s' "$LESSON" | tr '\n' ' ' | sed -E 's/[[:space:]]+$//')"
# retract --hash targets the lesson directly by its content_hash; otherwise (add, or retract by
# <category> <lesson-text>) the hash is computed EXACTLY as add computes it: sha("<cat> <text>").
if [ "$ACTION" = "retract" ] && [ -n "$HASH" ]; then
  content_hash="$HASH"
else
# CRITICAL: content_hash is over category + lesson text ONLY — the freshness trailer never enters
# it. This is a FORWARD-LOOKING property: a future re-verification path (refreshing last_verified)
# could update the trailer without changing the hash or breaking the chain. No such path exists
# today — the dedup guard below short-circuits an identical lesson before any update, so a stored
# last_verified is effectively write-once until the entry is evicted.
content_hash="$(printf '%s' "$CATSLUG $lesson_oneline" | sha)"
fi
id="$(printf '%s' "$content_hash" | cut -c1-8)"

# Dedup guard (add only): id is content-derived (category + lesson), so an identical lesson in the
# same category yields an identical entry. The appended trailer is OUTSIDE this substring, so the
# match still works. Skip (touching nothing — no provenance work) if already present.
if [ "$ACTION" = "add" ] && grep -qF -- "- [$id] $lesson_oneline" "$LESSONS" 2>/dev/null; then
  echo "write-lessons: lesson already present ([$id] in $CATSLUG) — skipping"
  exit 0
fi

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

# ---- RETRACT flow (tombstone verb) -----------------------------------------
# Gate-side curation: FAILS LOUD (exit 4) rather than silently tombstoning a nonexistent lesson.
# The `retract` provenance entry IS the auditable tombstone; the LESSONS.md rewrite removes ONLY
# the target entry line (every other line is preserved byte-for-byte; the `## <category>` heading
# is left in place — read-lessons.sh skips headings with no emitted entries).
if [ "$ACTION" = "retract" ]; then
  if [ ! -f "$LESSONS" ] || [ ! -f "$PROV" ]; then
    echo "write-lessons: retract [$id] — no lessons store yet ($LESSONS / $PROV missing) — refusing" >&2
    exit 4
  fi
  # (1) The target entry line must currently exist. [id] is content-derived (first 8 hex of
  #     sha("<cat> <text>")), so an id-prefix match identifies exactly the pair being retracted.
  if ! grep -qF -- "- [$id] " "$LESSONS" 2>/dev/null; then
    echo "write-lessons: retract target [$id] not found in $LESSONS — refusing (never tombstone silently)" >&2
    exit 4
  fi
  # (2) ...and its hash must be chain-trusted: walk the chain exactly like read-lessons.sh, with
  #     last-action-wins (add → trusted, later retract → untrusted, re-add → re-trusted). A broken
  #     link distrusts everything after it, so a poisoned/out-of-band line can never be laundered
  #     into a legitimate-looking tombstone.
  field() { printf '%s' "$1" | sed -E "s/.*\"$2\":\"([^\"]*)\".*/\1/"; }
  target_trusted=0; prev="$GENESIS"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ "$(field "$p" prev_hash)" = "$prev" ] || break   # chain broken → distrust the rest
    # Key-presence check first (nullable-required discipline): `field` echoes the WHOLE entry when
    # the key is absent, so gate on the literal key before extracting the value.
    ch=""
    case "$p" in *'"content_hash":"'*) ch="$(field "$p" content_hash)" ;; esac
    if [ -n "$ch" ] && [ "$ch" = "$content_hash" ]; then
      case "$(field "$p" action)" in
        add)     target_trusted=1 ;;
        retract) target_trusted=0 ;;
      esac
    fi
    prev="$(printf '%s' "$p" | sha)"
  done < "$PROV"
  if [ "$target_trusted" -ne 1 ]; then
    echo "write-lessons: retract target [$id] is not chain-trusted (never added, already retracted, or beyond a chain break) — refusing" >&2
    exit 4
  fi

  # (3) Append the chained retract tombstone + rewrite LESSONS.md without the entry line.
  #     Same atomic discipline and commit ORDER as add: temps IN the memory dir, provenance FIRST.
  mem_tmp="$(mktemp "$MEM_DIR/.ltmp.XXXXXX")"
  prov_tmp="$(mktemp "$MEM_DIR/.lptmp.XXXXXX")"
  trap 'rm -f "$mem_tmp" "$prov_tmp" 2>/dev/null' EXIT
  awk -v pfx="- [$id] " 'index($0, pfx) != 1 { print }' "$LESSONS" > "$mem_tmp"
  cat "$PROV" > "$prov_tmp"
  prev_hash="$(printf '%s' "$(tail -n1 "$prov_tmp")" | sha)"
  printf '%s\n' "$(prov_line "$id" "$prev_hash" "$content_hash" "$SOURCE" "retract")" >> "$prov_tmp"
  mv "$prov_tmp" "$PROV" && mv "$mem_tmp" "$LESSONS" || {
    echo "write-lessons: atomic rename failed — retract aborted; read gate ignores any unmatched provenance" >&2
    exit 2
  }
  echo "write-lessons: retracted [$id] (source=$SOURCE) — provenance tombstone appended, entry line removed"
  exit 0
fi

# Temps live IN the memory dir (not $TMPDIR) so the commit `mv` is a same-filesystem, truly
# atomic rename — a tmpfs /tmp would otherwise make `mv` a non-atomic cross-device copy+unlink.
mem_tmp="$(mktemp "$MEM_DIR/.ltmp.XXXXXX")"
prov_tmp="$(mktemp "$MEM_DIR/.lptmp.XXXXXX")"
evict_file="$(mktemp "$MEM_DIR/.levict.XXXXXX")"
trap 'rm -f "$mem_tmp" "$prov_tmp" "$evict_file" 2>/dev/null' EXIT
: > "$evict_file"

# Rebuild the LESSONS file with awk:
#  - locate the `## <CATSLUG>` section; insert the new line at its end (before the next `##` or EOF)
#  - if the section is absent, append it (heading + line) at EOF
#  - within the target section, enforce <=MAX_PER_CAT entries by evicting the OLDEST (first) ones,
#    and record each evicted entry's id to EVICT_FILE so bash can emit its `evict` provenance line.
# NOTE: the lesson text is passed via ENVIRON (not `-v`) because `awk -v` interprets backslash
# escape sequences in the value (\n, \t, \\, ...), which would silently corrupt a lesson that
# legitimately contains a backslash (e.g. a Windows path). ENVIRON values are taken literally.
# `cat`/`id` (slug/hex), `lv` (an ISO-8601 stamp VALIDATED above to `[0-9T:Z-]` only), and `conf`
# (a sanitized value, `<>`/quotes/backslashes/ctrl stripped) cannot contain backslashes,
# so they stay on `-v`.
LESSON_ONELINE="$lesson_oneline" awk \
  -v cat="$CATSLUG" -v id="$id" -v maxc="$MAX_PER_CAT" \
  -v lv="$LAST_VERIFIED" -v conf="$CONFIDENCE" -v evictfile="$evict_file" '
  BEGIN {
    hdr = "## " cat
    lesson = ENVIRON["LESSON_ONELINE"]
    trailer = "  <!-- last_verified=" lv " confidence=" conf " -->"
    newline = "- [" id "] " lesson trailer
  }
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
      print ""          # blank separator so the new `## <category>` heading is valid markdown
      print hdr
      print newline
    } else {
      # Print up to (and including) the heading.
      for (i = 1; i <= sec_start; i++) print lines[i]
      # Gather existing entry lines in the section, then append the new one.
      ec = 0
      for (i = sec_start + 1; i <= sec_end; i++) {
        if (lines[i] ~ /^- \[/) { ec++; entries[ec] = lines[i] }
      }
      ec++; entries[ec] = newline
      # Evict the oldest (front) entries until <= maxc remain; record each evicted id.
      start = 1
      while ((ec - start + 1) > maxc) {
        split(entries[start], a, /[][]/); eid = a[2]
        print eid >> evictfile
        start++
      }
      for (j = start; j <= ec; j++) print entries[j]
      # Print the remainder of the file (from the next section onward).
      for (i = sec_end + 1; i <= n; i++) print lines[i]
    }
  }
' "$LESSONS" > "$mem_tmp"

# ---- Build the provenance chain into prov_tmp ------------------------------
# Seed prov_tmp with the existing chain, then append one `add` line, then one chained `evict`
# line per evicted id (each chained off the running provenance tail — exactly like project-memory).
cat "$PROV" > "$prov_tmp"
last_line="$(tail -n1 "$prov_tmp" 2>/dev/null || true)"
if [ -n "$last_line" ]; then prev_hash="$(printf '%s' "$last_line" | sha)"; else prev_hash="$GENESIS"; fi
printf '%s\n' "$(prov_line "$id" "$prev_hash" "$content_hash" "$SOURCE" "add")" >> "$prov_tmp"

if [ -s "$evict_file" ]; then
  while IFS= read -r eid; do
    [ -n "$eid" ] || continue
    eph="$(printf '%s' "$(tail -n1 "$prov_tmp")" | sha)"
    printf '%s\n' "$(prov_line "$eid" "$eph" "" "eviction" "evict")" >> "$prov_tmp"
  done < "$evict_file"
fi

# Commit both files. Provenance FIRST: if the second rename fails, the worst case is a provenance
# entry with no matching memory line — which the read-side gate silently ignores (no orphaned,
# repeatedly-logged memory line). A failed first rename leaves state untouched.
mv "$prov_tmp" "$PROV" && mv "$mem_tmp" "$LESSONS" || {
  echo "write-lessons: atomic rename failed — write aborted; read gate ignores any unmatched provenance" >&2
  exit 2
}
echo "write-lessons: stored [$id] in $CATSLUG (source=$SOURCE, last_verified=$LAST_VERIFIED, confidence=$CONFIDENCE)"
exit 0
