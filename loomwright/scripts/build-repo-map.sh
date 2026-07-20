#!/usr/bin/env bash
# build-repo-map.sh — owned FLAT repo-map builder (advisory artifact, fail-safe).
#
# Produces a small, bounded, human/agent-readable orientation map of a repo:
#   1. `## Directory skeleton`  — depth-capped directory tree (dirs first, then shallow files),
#      built with `find` honoring the load-bearing exclusion list from the code-graph spike
#      (docs/SPIKES/CODE_GRAPH_OWNERSHIP.md — "the exclusion list ... must ship with the builder,
#      not be discovered per repo").
#   2. `## Exported symbols`    — a language-agnostic best-effort grep scan of exported/top-level
#      symbols, one `path: symbol1, symbol2, ...` line per file, files ordered by symbol count
#      DESCENDING via simple sort. Deliberately NOT PageRank / NOT a ranker: the spike's PageRank
#      ranking FAILED independent validation (0/10 top-hub overlap) — only the flat
#      signature-extraction idea is carried here. This map biases *where attention goes*; it must
#      never be treated as ground truth or gate anything.
#
# TIERS
#   Tier A (best-effort, optional): if a `tree-sitter` CLI is on PATH *and* has configured
#     grammars, attempt `tree-sitter tags` signature extraction per file. On ANY error / empty
#     result it silently degrades to Tier B. NOTHING is ever installed to make Tier A work.
#     UNVERIFIED against a live tree-sitter install (CLI absent in dev/CI): the
#     `dump-languages`/`tags` subcommand names may not match every CLI version — if they
#     don't, Tier A just always degrades to Tier B (safe). Verify on a real install before
#     relying on Tier A output.
#   Tier B (zero-dep floor, the deliverable): pure find + grep -E + sed. Always available.
#
# USAGE
#   build-repo-map.sh [--repo <dir>] [--out <file>] [--max-chars N]
#     --repo       repo root to map           (default: git root of cwd, else cwd)
#     --out        output file                (default: <repo>/.supervisor/repo-map.md;
#                                              env REPO_MAP_OUT overrides the default)
#     --max-chars  hard cap on output size    (default: 8000; env REPO_MAP_MAX_CHARS overrides
#                                              the default; measured in bytes as a chars proxy)
#   Precedence: explicit flag > env var > built-in default.
#
# OUTPUT FORMAT
#   # Repo map (generated <UTC ts> — advisory, regenerate on demand)
#   ## Directory skeleton
#   ## Exported symbols
#   If the assembled map exceeds max-chars it is truncated so the TOTAL file (marker included)
#   fits the cap, with final line: [repo-map truncated at N chars]
#
# FAIL-SAFE CONTRACT (mirrors read-rules.sh / read-bridge.sh conventions)
#   - ALWAYS exits 0: any internal error ⇒ write nothing (or leave the previous map untouched),
#     message to stderr, exit 0. A map build must never break its caller.
#   - No network. NEVER installs anything.
#   - bash-3.2 safe: no mapfile, no associative arrays, no GNU-only stat/sed/date flags.
#   - Gitignored dirs (e.g. .supervisor/) are ABSENT in fresh worktrees ⇒ the output dir is
#     `mkdir -p`-created at runtime.
#   - Writes via temp file + atomic `mv` in the output dir (same filesystem).

set -uo pipefail   # `set -e` intentionally omitted — fail-safe, always exit 0.

err() { echo "build-repo-map: $1" >&2; }

# ---------------------------------------------------------------------------
# Argument parsing (flag > env > default)
# ---------------------------------------------------------------------------
REPO=""
OUT="${REPO_MAP_OUT:-}"
MAX="${REPO_MAP_MAX_CHARS:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)
      if [ $# -ge 2 ]; then REPO="$2"; shift; else err "--repo needs a value (ignored)"; fi ;;
    --out)
      if [ $# -ge 2 ]; then OUT="$2"; shift; else err "--out needs a value (ignored)"; fi ;;
    --max-chars)
      if [ $# -ge 2 ]; then MAX="$2"; shift; else err "--max-chars needs a value (ignored)"; fi ;;
    *)
      err "unknown argument: $1 (ignored)" ;;
  esac
  shift
done

# Resolve repo root: --repo, else git root of cwd, else cwd. Canonicalize; fail-safe on absence.
if [ -z "$REPO" ]; then
  REPO="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
REPO="$(cd "$REPO" 2>/dev/null && pwd || true)"
if [ -z "$REPO" ] || [ ! -d "$REPO" ]; then
  err "repo dir not found — nothing written (fail-safe)"
  exit 0
fi

[ -n "$OUT" ] || OUT="$REPO/.supervisor/repo-map.md"

# Validate max-chars: positive integer, else fall back to 8000 (fail-safe, noted on stderr).
case "$MAX" in
  ''|*[!0-9]*)
    [ -n "$MAX" ] && err "non-numeric --max-chars '$MAX' — using default 8000"
    MAX=8000 ;;
esac
if [ "$MAX" -le 0 ] 2>/dev/null; then
  err "--max-chars must be > 0 — using default 8000"
  MAX=8000
fi
# A cap smaller than the truncation marker itself cannot honor the "total file
# fits the cap INCLUDING the marker" contract — treat as invalid, fall back.
_min_cap=40
if [ "$MAX" -lt "$_min_cap" ] 2>/dev/null; then
  err "--max-chars must be >= ${_min_cap} (truncation marker must fit) — using default 8000"
  MAX=8000
fi

OUTDIR="$(dirname "$OUT")"
if ! mkdir -p "$OUTDIR" 2>/dev/null; then
  err "cannot create output dir '$OUTDIR' — nothing written (fail-safe)"
  exit 0
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/repo-map.XXXXXX" 2>/dev/null || true)"
if [ -z "$WORKDIR" ] || [ ! -d "$WORKDIR" ]; then
  err "mktemp failed — nothing written (fail-safe)"
  exit 0
fi
TMPOUT=""
trap 'rm -rf "$WORKDIR" 2>/dev/null; [ -n "${TMPOUT:-}" ] && rm -f "$TMPOUT" 2>/dev/null; exit 0' EXIT

# ---------------------------------------------------------------------------
# Exclusion list (load-bearing — carried from the spike; ships WITH the builder)
# ---------------------------------------------------------------------------
EXCLUDE_DIRS=(
  node_modules .git dist build vendor venv .venv __pycache__ coverage .next target
  .supervisor graphify-out .claude .dart_tool Pods
)
# find(1) prune expression: \( -type d \( -name a -o -name b ... \) \) -prune
PRUNE=( "(" -type d "(" )
_first=1
for _d in "${EXCLUDE_DIRS[@]}"; do
  if [ "$_first" -eq 1 ]; then _first=0; else PRUNE+=( -o ); fi
  PRUNE+=( -name "$_d" )
done
PRUNE+=( ")" ")" -prune )

# File-level exclusions: minified bundles, lockfiles, generated files, media/binary extensions.
FILE_EXCLUDES=(
  ! -name "*.min.*" ! -name "*.lock" ! -name "package-lock.json" ! -name "pnpm-lock.yaml"
  ! -name "npm-shrinkwrap.json" ! -name "*.g.dart" ! -name "*.d.ts" ! -name "*.map"
  ! -name "*.png" ! -name "*.jpg" ! -name "*.jpeg" ! -name "*.gif" ! -name "*.svg"
  ! -name "*.ico" ! -name "*.webp" ! -name "*.avif" ! -name "*.pdf"
  ! -name "*.zip" ! -name "*.tar" ! -name "*.gz" ! -name "*.tgz" ! -name "*.bz2"
  ! -name "*.xz" ! -name "*.7z" ! -name "*.mp3" ! -name "*.mp4" ! -name "*.mov"
  ! -name "*.avi" ! -name "*.wav" ! -name "*.woff" ! -name "*.woff2" ! -name "*.ttf"
  ! -name "*.otf" ! -name "*.eot" ! -name "*.jar" ! -name "*.class" ! -name "*.o"
  ! -name "*.so" ! -name "*.dylib" ! -name "*.dll" ! -name "*.exe" ! -name "*.bin"
  ! -name "*.dat" ! -name "*.sqlite" ! -name "*.db"
)

# Source-file name filter for the symbol scan.
SRC_NAMES=(
  "(" -name "*.sh" -o -name "*.bash" -o -name "*.js" -o -name "*.jsx" -o -name "*.ts"
      -o -name "*.tsx" -o -name "*.mjs" -o -name "*.cjs" -o -name "*.py" -o -name "*.rb"
      -o -name "*.go" -o -name "*.rs" -o -name "*.java" -o -name "*.kt" -o -name "*.cs"
      -o -name "*.php" -o -name "*.swift" -o -name "*.dart" -o -name "*.c" -o -name "*.h"
      -o -name "*.cc" -o -name "*.cpp" -o -name "*.hpp" -o -name "*.scala" -o -name "*.lua" ")"
)

# Bounds (keep the map cheap + deterministic on huge repos).
DIR_DEPTH=4        # skeleton: directories to this depth
FILE_DEPTH=2       # skeleton: files to this depth
MAX_SKEL_DIRS=200
MAX_SKEL_FILES=100
MAX_SRC_FILES=500  # symbol scan: at most this many source files
MAX_SYMS_PER_FILE=30

# ---------------------------------------------------------------------------
# Section 1: directory skeleton (dirs first, then shallow files)
# ---------------------------------------------------------------------------
SKELETON="$WORKDIR/skeleton"
{
  find "$REPO" -maxdepth "$DIR_DEPTH" "${PRUNE[@]}" -o -type d -print 2>/dev/null \
    | LC_ALL=C sort | head -n "$MAX_SKEL_DIRS" \
    | awk -v root="$REPO" '{
        if ($0 == root) next
        rel = substr($0, length(root) + 2)
        n = split(rel, parts, "/")
        ind = ""
        for (i = 1; i < n; i++) ind = ind "  "
        print ind "- " parts[n] "/"
      }'
  find "$REPO" -maxdepth "$FILE_DEPTH" "${PRUNE[@]}" -o -type f "${FILE_EXCLUDES[@]}" -print 2>/dev/null \
    | LC_ALL=C sort | head -n "$MAX_SKEL_FILES" \
    | awk -v root="$REPO" '{
        rel = substr($0, length(root) + 2)
        n = split(rel, parts, "/")
        ind = ""
        for (i = 1; i < n; i++) ind = ind "  "
        print ind "- " parts[n]
      }'
} > "$SKELETON" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Section 2: exported symbols
# ---------------------------------------------------------------------------
FILES_LIST="$WORKDIR/files"
find "$REPO" -maxdepth 8 "${PRUNE[@]}" -o -type f "${SRC_NAMES[@]}" "${FILE_EXCLUDES[@]}" \
     -size -512k -print 2>/dev/null \
  | LC_ALL=C sort | head -n "$MAX_SRC_FILES" > "$FILES_LIST" || true

# Per-extension grep -E pattern (language-agnostic best effort — exported/top-level decls only).
pattern_for() {
  case "$1" in
    *.py)                                  echo '^(def |class )' ;;
    *.sh|*.bash)                           echo '^(function[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)' ;;
    *.go)                                  echo '^(func |type )' ;;
    *.rs)                                  echo '^(pub |fn |struct |enum |trait )' ;;
    *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs)     echo '^(export |module\.exports|exports\.)' ;;
    *.java|*.cs|*.kt|*.swift|*.scala)      echo '^[[:space:]]*(public |protected |internal |open |abstract |interface |class |enum |struct |func |fun |object )' ;;
    *.rb)                                  echo '^[[:space:]]*(def |class |module )' ;;
    *.php)                                 echo '^[[:space:]]*(function |class |interface |trait )' ;;
    *.dart)                                echo '^(class |enum |mixin |abstract )' ;;
    *.c|*.h|*.cc|*.cpp|*.hpp)              echo '^[A-Za-z_][A-Za-z0-9_[:space:]\*]*\(' ;;
    *.lua)                                 echo '^(function |local function )' ;;
    *)                                     echo '^(export |module\.exports|def |class |func |fn |public |interface |type )' ;;
  esac
}

# Reduce a matched declaration line to a bare identifier (best effort; non-matches filtered out).
KW_STRIP='s/^(export|default|declare|abstract|async|public|protected|private|internal|open|static|final|pub|unsafe|local|function|class|interface|type|enum|struct|trait|mixin|def|func|fun|fn|const|let|var|val|module|object|sealed|data)[[:space:]]+//'
extract_names() {
  sed -E \
    -e 's/^[[:space:]]+//' \
    -e 's/^(module\.)?exports\.([A-Za-z_$][A-Za-z0-9_$]*).*/\2/' \
    -e "$KW_STRIP" -e "$KW_STRIP" -e "$KW_STRIP" -e "$KW_STRIP" \
    -e 's/^([A-Za-z_$][A-Za-z0-9_$]*).*/\1/' \
  | grep -E '^[A-Za-z_$][A-Za-z0-9_$]*$' \
  | grep -vE '^(exports?|module|function|class|def|const|let|var|public|interface|type|enum|struct|if|for|while|return|import|from|require|switch|case)$'
}

SYMTMP="$WORKDIR/syms"          # lines: "<count>\t<relpath>: <sym1, sym2, ...>"
: > "$SYMTMP"

emit_sym_line() {
  # $1 = absolute file path, stdin = one symbol per line (already unique/sorted/bounded)
  _syms="$(cat)"
  [ -n "$_syms" ] || return 0
  _count="$(printf '%s\n' "$_syms" | grep -c . 2>/dev/null || echo 0)"
  [ "$_count" -gt 0 ] 2>/dev/null || return 0
  _joined="$(printf '%s\n' "$_syms" | paste -s -d , - 2>/dev/null | sed 's/,/, /g')"
  _rel="${1#"$REPO"/}"
  printf '%s\t%s: %s\n' "$_count" "$_rel" "$_joined" >> "$SYMTMP"
}

# Tier A: best-effort tree-sitter signature extraction. Returns non-zero (⇒ Tier B) on ANY
# shortfall: CLI absent, no configured grammars, or zero usable tags. Never installs anything.
tier_a_scan() {
  command -v tree-sitter >/dev/null 2>&1 || return 1
  tree-sitter dump-languages >/dev/null 2>&1 || return 1
  _got=0
  : > "$SYMTMP"
  while IFS= read -r _f; do
    [ -n "$_f" ] || continue
    _tags="$(tree-sitter tags "$_f" 2>/dev/null \
               | awk '{print $1}' \
               | grep -E '^[A-Za-z_$][A-Za-z0-9_$]*$' 2>/dev/null \
               | LC_ALL=C sort -u | head -n "$MAX_SYMS_PER_FILE" || true)"
    [ -n "$_tags" ] || continue
    printf '%s\n' "$_tags" | emit_sym_line "$_f"
    _got=1
  done < "$FILES_LIST"
  [ "$_got" -eq 1 ] || return 1
  return 0
}

# Tier B: zero-dep grep -E floor (the deliverable).
tier_b_scan() {
  : > "$SYMTMP"
  while IFS= read -r _f; do
    [ -n "$_f" ] || continue
    _pat="$(pattern_for "$_f")"
    grep -E "$_pat" "$_f" 2>/dev/null | head -n 60 | extract_names \
      | LC_ALL=C sort -u | head -n "$MAX_SYMS_PER_FILE" | emit_sym_line "$_f"
  done < "$FILES_LIST"
  return 0
}

if ! tier_a_scan; then
  tier_b_scan
fi

# Order files by symbol count DESCENDING (simple sort, NOT PageRank), path as tie-break.
SYMSORTED="$WORKDIR/symsorted"
LC_ALL=C sort -t "$(printf '\t')" -k1,1nr -k2,2 "$SYMTMP" 2>/dev/null | cut -f2- > "$SYMSORTED" || true

# ---------------------------------------------------------------------------
# Assemble + cap + atomic write
# ---------------------------------------------------------------------------
CONTENT="$WORKDIR/content"
{
  printf '# Repo map (generated %s — advisory, regenerate on demand)\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
  printf '\n## Directory skeleton\n\n'
  if [ -s "$SKELETON" ]; then cat "$SKELETON"; else echo "(none)"; fi
  printf '\n## Exported symbols\n\n'
  if [ -s "$SYMSORTED" ]; then cat "$SYMSORTED"; else echo "(none found)"; fi
} > "$CONTENT" 2>/dev/null || true

if [ ! -s "$CONTENT" ]; then
  err "assembled empty map — nothing written (fail-safe)"
  exit 0
fi

SIZE="$(wc -c < "$CONTENT" 2>/dev/null | tr -d '[:space:]')"
case "$SIZE" in ''|*[!0-9]*) SIZE=0 ;; esac

TMPOUT="$(mktemp "$OUTDIR/.repo-map.XXXXXX" 2>/dev/null || true)"
if [ -z "$TMPOUT" ]; then
  err "cannot create temp output file in '$OUTDIR' — nothing written (fail-safe)"
  exit 0
fi

if [ "$SIZE" -le "$MAX" ]; then
  cat "$CONTENT" > "$TMPOUT" 2>/dev/null || true
else
  # Truncate so TOTAL output (content + newline + marker line) fits within MAX bytes.
  MARKER="[repo-map truncated at ${MAX} chars]"
  ALLOWED=$(( MAX - ${#MARKER} - 2 ))
  [ "$ALLOWED" -lt 0 ] && ALLOWED=0
  head -c "$ALLOWED" "$CONTENT" > "$TMPOUT" 2>/dev/null || true
  printf '\n%s\n' "$MARKER" >> "$TMPOUT" 2>/dev/null || true
fi

if mv -f "$TMPOUT" "$OUT" 2>/dev/null; then
  TMPOUT=""
else
  err "atomic move to '$OUT' failed — map not updated (fail-safe)"
  rm -f "$TMPOUT" 2>/dev/null || true
  TMPOUT=""
fi

exit 0
