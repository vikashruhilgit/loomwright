#!/usr/bin/env bash
# build-context-digest.sh — bounded per-job CONTEXT_DIGEST builder (D6: worker shared-context
# digest + explicit file lanes).
#
# WHAT: extracts Launch Pad's already-computed analysis out of an assembled Supervisor-Ready
# Brief (File Impact Map, subtask contracts w/ `provides`/`requires`/`lanes`, Subtask Structure,
# Tech Stack / Architecture) into ONE small, bounded, pointer-handed markdown artifact so every
# spawned worker on the job can read it instead of re-deriving the same codebase understanding
# from scratch. See docs/RESULT_SCHEMAS.md §"CONTEXT_DIGEST" for the artifact contract this
# script implements, and docs/POINTER_AUDIT.md §"Context digest" for the pointer/worktree rule
# consumers apply when handing the resulting path to a spawned worker.
#
# INPUT: the FULL TEXT of an assembled brief (NOT a structured object) — either a file path via
# `--brief <path>` or, when `--brief` is omitted, piped on STDIN. `--brief -` also reads STDIN
# explicitly. This mirrors read-postmortem.sh's args/stdin duality: an explicit `--brief <path>`
# is never overridden by a stray open stdin pipe.
#
# USAGE
#   build-context-digest.sh [--brief <path>|-] [--out <file>] [--max-chars N]
#     --brief      path to the assembled brief text, or `-`/omitted for STDIN
#     --out        output file  (default: .supervisor/jobs/context-digests/context-digest.md;
#                                env CONTEXT_DIGEST_OUT overrides the default)
#                  CALLERS SHOULD pass an explicit path matching the brief's own basename —
#                  `.supervisor/jobs/context-digests/{basename(brief_path)}` — mirroring the
#                  `{pending,in-progress,done,failed}/{basename}` lifecycle-directory convention
#                  (see skills/autonomous-loop/SKILL.md's `{basename(current_brief_path)}`
#                  anchor). The script's own single-file default is a fallback for ad-hoc/manual
#                  invocations only, not the documented per-job path.
#     --max-chars  hard cap on output size (default: 6000; env CONTEXT_DIGEST_MAX_CHARS
#                  overrides the default; measured in bytes as a chars proxy — mirrors
#                  build-repo-map.sh's `--max-chars` contract exactly)
#   Precedence: explicit flag > env var > built-in default.
#
# OUTPUT FORMAT
#   # Context Digest — <brief title, or its basename>
#   ## File Impact Map                        (verbatim from the brief's Phase 3 table)
#   ## Interfaces touched                      (deduped `path :: name (kind)` list, derived from
#                                                every `{kind: symbol|type, ...}` provides/requires
#                                                entry across all subtasks)
#   ## Conventions                             (the brief's `**Tech Stack:**` / `**Architecture:**`
#                                                lines)
#   ## Sibling-subtask summary                 (verbatim copy of the brief's Subtask Structure
#                                                table)
#   ## Cross-lane producer/consumer contracts  (verbatim copy of the brief's Subtask Contracts
#                                                YAML block(s) — provides/requires/lanes/
#                                                external_requires together IS the producer/
#                                                consumer + lane-ownership data; this builder does
#                                                NOT re-derive lane-collision logic)
#   A section with no matching content in the source brief is rendered as `_(none found)_` rather
#   than a hard failure. If the assembled digest exceeds --max-chars it is truncated so the TOTAL
#   file (content + marker) fits within the cap, with a final line:
#     [context-digest truncated at N chars]
#   The digest is NEVER unbounded (AC2).
#
# SECTION EXTRACTION is heading-driven and heading-level-agnostic (matches `##`/`###`/`####`
# headings by case-insensitive text, not by depth) because the exact heading level for a given
# section has drifted across brief-producing surfaces in this repo (e.g. "## Subtask Contracts"
# vs the now-canonical "### Subtask contracts" the SDK runner's parser keys on) — this builder
# tolerates that drift rather than depending on it staying fixed. It is a best-effort, bounded,
# ADVISORY extraction (grep/sed/awk over markdown text), not a strict brief parser — correctness
# enforcement (bound honored, truncation marker present, worktree-absolute pointer form, lane-
# collision flagging) is scripts/test-context-digest.sh's job, not this builder's.
#
# FAIL-SAFE CONTRACT (mirrors build-repo-map.sh / build-handoff.sh — the sibling `build-*.sh`
# advisory-artifact convention)
#   - ALWAYS exits 0: any internal error => write nothing, message to stderr, exit 0. A digest
#     build must never break its caller (Launch Pad's Phase 5 PACKAGE).
#   - No network. NEVER installs anything.
#   - bash-3.2 safe: no mapfile, no associative arrays, no GNU-only stat/sed/date flags.
#   - Gitignored `.supervisor/` is ABSENT in fresh worktrees => the output dir is `mkdir -p`-
#     created at runtime. This script itself always runs at the project root (Launch Pad never
#     runs inside a worktree) — the worktree-absolute-pointer rule governs how the WRITTEN path
#     is later handed to a worktree-resident worker, not how this script itself is invoked.
#   - Writes via temp file + atomic `mv` in the output dir (same filesystem).

set -uo pipefail   # `set -e` intentionally omitted — fail-safe, always exit 0.

err() { echo "build-context-digest: $1" >&2; }

# ---------------------------------------------------------------------------
# Argument parsing (flag > env > default)
# ---------------------------------------------------------------------------
BRIEF_ARG=""
OUT="${CONTEXT_DIGEST_OUT:-}"
MAX="${CONTEXT_DIGEST_MAX_CHARS:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --brief)
      if [ $# -ge 2 ]; then BRIEF_ARG="$2"; shift; else err "--brief needs a value (ignored)"; fi ;;
    --out)
      if [ $# -ge 2 ]; then OUT="$2"; shift; else err "--out needs a value (ignored)"; fi ;;
    --max-chars)
      if [ $# -ge 2 ]; then MAX="$2"; shift; else err "--max-chars needs a value (ignored)"; fi ;;
    *)
      err "unknown argument: $1 (ignored)" ;;
  esac
  shift
done

GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$GITROOT" 2>/dev/null || true

[ -n "$OUT" ] || OUT=".supervisor/jobs/context-digests/context-digest.md"

# Validate max-chars: positive integer, else fall back to 6000 (fail-safe, noted on stderr).
case "$MAX" in
  ''|*[!0-9]*)
    [ -n "$MAX" ] && err "non-numeric --max-chars '$MAX' — using default 6000"
    MAX=6000 ;;
esac
if [ "$MAX" -le 0 ] 2>/dev/null; then
  err "--max-chars must be > 0 — using default 6000"
  MAX=6000
fi
# A cap smaller than the truncation marker itself cannot honor the "total file
# fits the cap INCLUDING the marker" contract — treat as invalid, fall back.
_min_cap=60
if [ "$MAX" -lt "$_min_cap" ] 2>/dev/null; then
  err "--max-chars must be >= ${_min_cap} (truncation marker must fit) — using default 6000"
  MAX=6000
fi

OUTDIR="$(dirname "$OUT")"
if ! mkdir -p "$OUTDIR" 2>/dev/null; then
  err "cannot create output dir '$OUTDIR' — nothing written (fail-safe)"
  exit 0
fi

WORKDIR="$(mktemp -d 2>/dev/null || true)"
if [ -z "$WORKDIR" ] || [ ! -d "$WORKDIR" ]; then
  err "cannot create scratch workdir — nothing written (fail-safe)"
  exit 0
fi
trap 'rm -rf "$WORKDIR" 2>/dev/null' EXIT

# ---------------------------------------------------------------------------
# Resolve brief input: --brief <path>, --brief -, or STDIN (ARGS-take-precedence, mirrors
# read-postmortem.sh — an explicit --brief path is NEVER shadowed by an open stdin pipe).
# ---------------------------------------------------------------------------
BRIEF_FILE="$WORKDIR/brief.md"
if [ -n "$BRIEF_ARG" ] && [ "$BRIEF_ARG" != "-" ]; then
  if [ -f "$BRIEF_ARG" ]; then
    cat "$BRIEF_ARG" > "$BRIEF_FILE" 2>/dev/null || true
  else
    err "brief path not found: '$BRIEF_ARG' — nothing written (fail-safe)"
    exit 0
  fi
elif [ -n "$BRIEF_ARG" ] || [ ! -t 0 ]; then
  # --brief - (explicit stdin) OR no --brief given and stdin is a pipe (not a terminal).
  cat > "$BRIEF_FILE" 2>/dev/null || true
else
  err "no --brief path given and stdin is a terminal — nothing to read (fail-safe)"
  exit 0
fi

if [ ! -s "$BRIEF_FILE" ]; then
  err "brief content is empty — nothing written (fail-safe)"
  exit 0
fi

# ---------------------------------------------------------------------------
# Heading-driven, heading-level-agnostic section extractor.
#   $1 = heading text to match, case-insensitive, matched as a PREFIX of the heading line's text
#        (after stripping the leading #'s and one space run) — tolerates the "Subtask Contracts"
#        vs "Subtask contracts" / H2-vs-H3 drift documented above.
# Prints every line between the matched heading (exclusive) and the NEXT heading line of any
# depth (exclusive), or end of file. Prints nothing if the heading is never found.
# FENCE-AWARE: a fenced code block (``` or ~~~) toggles a skip-heading-detection state, because
# the Subtask Contracts YAML block legitimately contains lines like `# Subtask 1 — ...` (a YAML
# comment) that would otherwise be misread as a markdown heading and prematurely end extraction.
# ---------------------------------------------------------------------------
extract_section() {
  awk -v want="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" '
    BEGIN { on = 0; infence = 0 }
    {
      line = $0
      if (line ~ /^(```|~~~)/) {
        infence = !infence
        if (on) { print }
        next
      }
      if (!infence && match(line, /^#{1,4}[ \t]+/)) {
        heading = substr(line, RLENGTH + 1)
        htl = tolower(heading)
        if (on) { exit }
        if (index(htl, want) == 1) { on = 1; next }
        next
      }
      if (on) { print }
    }
  ' "$BRIEF_FILE" 2>/dev/null
}

# ---------------------------------------------------------------------------
# 1. File Impact Map — verbatim.
# ---------------------------------------------------------------------------
FILE_IMPACT="$(extract_section "file impact map")"

# ---------------------------------------------------------------------------
# 2. Interfaces touched — deduped `path :: name (kind)` derived from every symbol/type
#    provides/requires entry, quoted or unquoted YAML flow-map style (both appear in this repo's
#    brief-producing templates).
# ---------------------------------------------------------------------------
INTERFACES="$(
  grep -E '\{kind:[[:space:]]*"?(symbol|type)"?,' "$BRIEF_FILE" 2>/dev/null \
    | sed -E 's/.*kind:[[:space:]]*"?(symbol|type)"?,[[:space:]]*path:[[:space:]]*"?([^,"}]*)"?,[[:space:]]*name:[[:space:]]*"?([^,"}]*)"?.*/\2 :: \3 (\1)/' \
    | sort -u
)"

# ---------------------------------------------------------------------------
# 3. Conventions — Tech Stack / Architecture lines from the brief's Phase 3 header.
# ---------------------------------------------------------------------------
CONVENTIONS="$(grep -E '^\*\*(Tech Stack|Architecture):\*\*' "$BRIEF_FILE" 2>/dev/null)"

# ---------------------------------------------------------------------------
# 4. Sibling-subtask summary — verbatim Subtask Structure table.
# ---------------------------------------------------------------------------
SUBTASK_SUMMARY="$(extract_section "subtask structure")"

# ---------------------------------------------------------------------------
# 5. Cross-lane producer/consumer contracts — verbatim Subtask Contracts YAML block. Try the
#    now-canonical heading first, then the legacy capitalized form some templates still show.
# ---------------------------------------------------------------------------
CONTRACTS="$(extract_section "subtask contracts")"

# ---------------------------------------------------------------------------
# Title — first `# ` (H1) line, else the brief's own basename.
# ---------------------------------------------------------------------------
TITLE="$(grep -m1 -E '^# ' "$BRIEF_FILE" 2>/dev/null | sed -E 's/^#[[:space:]]*//')"
[ -n "$TITLE" ] || TITLE="$( [ -n "$BRIEF_ARG" ] && [ "$BRIEF_ARG" != "-" ] && basename "$BRIEF_ARG" || echo "context digest" )"

# ---------------------------------------------------------------------------
# Assemble + cap + atomic write.
# ---------------------------------------------------------------------------
CONTENT="$WORKDIR/content"
{
  printf '# Context Digest — %s\n\n' "$TITLE"
  printf '_Generated %s — bounded, pointer-handed to every worker on this job. Read only the sections you need._\n\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"

  printf '## File Impact Map\n\n'
  if [ -n "$FILE_IMPACT" ]; then printf '%s\n' "$FILE_IMPACT"; else printf '_(none found)_\n'; fi
  printf '\n'

  printf '## Interfaces touched\n\n'
  if [ -n "$INTERFACES" ]; then
    printf '%s\n' "$INTERFACES" | while IFS= read -r line; do
      [ -n "$line" ] && printf -- '- %s\n' "$line"
    done
  else
    printf '_(none found)_\n'
  fi
  printf '\n'

  printf '## Conventions\n\n'
  if [ -n "$CONVENTIONS" ]; then printf '%s\n' "$CONVENTIONS"; else printf '_(none found)_\n'; fi
  printf '\n'

  printf '## Sibling-subtask summary\n\n'
  if [ -n "$SUBTASK_SUMMARY" ]; then printf '%s\n' "$SUBTASK_SUMMARY"; else printf '_(none found)_\n'; fi
  printf '\n'

  printf '## Cross-lane producer/consumer contracts\n\n'
  printf '_provides / requires / lanes / external_requires together, verbatim from the brief — this IS the producer/consumer + lane-ownership data; lane-collision logic is NOT re-derived here (see skills/supervisor-readiness/SKILL.md §"Lane Declaration Schema")._\n\n'
  if [ -n "$CONTRACTS" ]; then printf '%s\n' "$CONTRACTS"; else printf '_(none found)_\n'; fi
} > "$CONTENT" 2>/dev/null || true

if [ ! -s "$CONTENT" ]; then
  err "assembled digest is empty — nothing written (fail-safe)"
  exit 0
fi

SIZE="$(wc -c < "$CONTENT" 2>/dev/null | tr -d '[:space:]')"
case "$SIZE" in ''|*[!0-9]*) SIZE=0 ;; esac

TMPOUT="$(mktemp "$OUTDIR/.context-digest.XXXXXX" 2>/dev/null || true)"
if [ -z "$TMPOUT" ]; then
  err "cannot create temp output file in '$OUTDIR' — nothing written (fail-safe)"
  exit 0
fi

TRUNCATED=0
if [ "$SIZE" -le "$MAX" ]; then
  cat "$CONTENT" > "$TMPOUT" 2>/dev/null || true
else
  # Truncate so TOTAL output (content + newline + marker line) fits within MAX bytes (AC2 — the
  # digest is NEVER unbounded).
  MARKER="[context-digest truncated at ${MAX} chars]"
  ALLOWED=$(( MAX - ${#MARKER} - 2 ))
  [ "$ALLOWED" -lt 0 ] && ALLOWED=0
  head -c "$ALLOWED" "$CONTENT" > "$TMPOUT" 2>/dev/null || true
  printf '\n%s\n' "$MARKER" >> "$TMPOUT" 2>/dev/null || true
  TRUNCATED=1
fi

if mv -f "$TMPOUT" "$OUT" 2>/dev/null; then
  TMPOUT=""
else
  err "atomic move to '$OUT' failed — digest not written (fail-safe)"
  rm -f "$TMPOUT" 2>/dev/null || true
  exit 0
fi

echo "build-context-digest: wrote $OUT ($SIZE bytes$( [ "$TRUNCATED" -eq 1 ] && printf ', truncated to %s' "$MAX" ))"
exit 0
