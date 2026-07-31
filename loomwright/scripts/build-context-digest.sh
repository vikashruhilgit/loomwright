#!/usr/bin/env bash
# build-context-digest.sh — bounded per-job CONTEXT_DIGEST builder (D6: worker shared-context
# digest + explicit file lanes).
#
# WHAT: extracts Launch Pad's already-computed analysis out of an assembled Supervisor-Ready
# Brief (File Impact Map, subtask contracts w/ `provides`/`requires`/`lanes`, Subtask Structure,
# Environment + Skill References) into ONE small, bounded, pointer-handed markdown artifact so every
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
#   ## File Impact Map                        (verbatim `## File Impact Map` when the brief has one
#                                                — measured 10/73 briefs; the other 63 fall back to
#                                                the brief's `## Subtask Structure` table (72/73) +
#                                                `### File Overlap Matrix` (28/73) when present —
#                                                a bounded proxy for "what files does this job
#                                                touch", never a hard failure when both are absent)
#   ## Interfaces touched                      (deduped `path :: name (kind)` list, derived from
#                                                every `{kind: symbol|type, ...}` provides/requires
#                                                entry across all subtasks)
#   ## Conventions                             (`## Environment` (71/73) + `## Skill References`
#                                                (54/73) — measured 2026-07-31: the prior
#                                                `**Tech Stack:**`/`**Architecture:**` bold-line
#                                                grep matched 0/73 real briefs and was dead code)
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
# 1. File Impact Map — verbatim `## File Impact Map` when present (measured 10/73 briefs).
#    Real Launch Pad briefs overwhelmingly do NOT carry this exact section (63/73 don't), so a
#    bare `_(none found)_` on the common case defeats the section's purpose. Fall back to the
#    brief's `## Subtask Structure` table (72/73) plus `### File Overlap Matrix` (28/73) when
#    present — together the closest bounded proxy this repo's brief templates actually carry for
#    "what files does this job touch, and where might they collide". Still `_(none found)_` when
#    none of the three sections exist (single-subtask legacy briefs).
# ---------------------------------------------------------------------------
FILE_IMPACT="$(extract_section "file impact map")"
if [ -z "$FILE_IMPACT" ]; then
  _STRUCT_FALLBACK="$(extract_section "subtask structure")"
  _OVERLAP_FALLBACK="$(extract_section "file overlap matrix")"
  if [ -n "$_STRUCT_FALLBACK" ] || [ -n "$_OVERLAP_FALLBACK" ]; then
    FILE_IMPACT="$(
      {
        printf '_No `## File Impact Map` section in this brief — derived from Subtask Structure / File Overlap Matrix instead._\n'
        if [ -n "$_STRUCT_FALLBACK" ]; then
          printf '\n'
          printf '%s\n' "$_STRUCT_FALLBACK"
        fi
        if [ -n "$_OVERLAP_FALLBACK" ]; then
          printf '\n**File Overlap Matrix:**\n\n'
          printf '%s\n' "$_OVERLAP_FALLBACK"
        fi
      }
    )"
  fi
  unset _STRUCT_FALLBACK _OVERLAP_FALLBACK
fi

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
# 3. Conventions — `## Environment` (71/73) + `## Skill References` (54/73). The prior
#    `**Tech Stack:**` / `**Architecture:**` bold-line grep matched 0/73 real briefs (measured
#    2026-07-31 across .supervisor/jobs/{done,in-progress}/) — those lines are never emitted by
#    the current brief templates, so that grep was dead code kept alive only by its own docstring.
# ---------------------------------------------------------------------------
_ENV_SECTION="$(extract_section "environment")"
_SKILLS_SECTION="$(extract_section "skill references")"
CONVENTIONS="$(
  {
    [ -n "$_ENV_SECTION" ] && printf '%s\n' "$_ENV_SECTION"
    if [ -n "$_SKILLS_SECTION" ]; then
      [ -n "$_ENV_SECTION" ] && printf '\n'
      printf '**Skill References:**\n\n%s\n' "$_SKILLS_SECTION"
    fi
  }
)"
unset _ENV_SECTION _SKILLS_SECTION

# ---------------------------------------------------------------------------
# 4. Sibling-subtask summary — verbatim Subtask Structure table.
# ---------------------------------------------------------------------------
SUBTASK_SUMMARY="$(extract_section "subtask structure")"

# ---------------------------------------------------------------------------
# 5. Cross-lane producer/consumer contracts — verbatim Subtask Contracts YAML block. Try the
#    now-canonical heading first, then the legacy capitalized form some templates still show.
# ---------------------------------------------------------------------------
# Contract extraction must accept EVERY layout real briefs use -- the same set
# `sdk-spike/src/runner.ts` parseBrief accepts. A single-heading lookup was the
# third instance of this PR's recurring root cause (extractor written against ONE
# template): measured over the 72 archived briefs, `subtask contracts` alone left
# this section `_(none found)_` on 54 of them -- including briefs that plainly
# carry contracts -- so the digest shipped a heading with no data behind it.
CONTRACTS="$(extract_section "subtask contracts")"
[ -n "$CONTRACTS" ] || CONTRACTS="$(extract_section "provides / requires contracts")"
[ -n "$CONTRACTS" ] || CONTRACTS="$(extract_section "provides / requires schema")"
[ -n "$CONTRACTS" ] || CONTRACTS="$(extract_section "subtask detail")"

# Fallback: per-subtask INLINE contracts with no umbrella heading at all -- keys sit
# at column 0 under `### Subtask N — Title` markdown headings (e.g.
# 2026-07-30-fix7-two-review-lenses.md). Collect each subtask heading followed by its
# provides/requires/lanes/external_requires block.
if [ -z "$CONTRACTS" ]; then
  CONTRACTS="$(awk '
    /^###[[:space:]]+([Ss]ubtask|ST|St)[[:space:]]*[0-9]/ { hdr=$0; pending=1; inblk=0; next }
    /^(provides|requires|lanes|external_requires):/ {
      if (pending) { if (seen) print ""; print hdr; seen=1; pending=0 }
      if (seen)    { print; inblk=1; next }
    }
    inblk && /^[[:space:]]+-[[:space:]]/ { print; next }
    inblk && /^[^[:space:]]/            { inblk=0 }
  ' "$BRIEF_FILE" 2>/dev/null || true)"
fi

# TERMINAL fallback -- STRUCTURAL, not heading-dependent. Some briefs put contracts in
# ```yaml fences with no adjacent recognizable subtask heading at all, so no heading rule
# can reach them. Collect every fenced block that actually contains a contract key at
# column 0. Scoping to `provides:`/`requires:` keeps unrelated YAML examples out; and
# because this section is ADVISORY (the worker still has the brief one Read away), an
# occasional extra block is far cheaper than the alternative this PR shipped twice --
# a heading with no data behind it.
if [ -z "$CONTRACTS" ]; then
  CONTRACTS="$(awk '
    /^```ya?ml[[:space:]]*$/ { inf=1; n=0; has=0; next }
    inf && /^```[[:space:]]*$/ {
      if (has) { for (i=1;i<=n;i++) print buf[i]; print "" }
      inf=0; n=0; has=0; next
    }
    inf {
      buf[++n]=$0
      if ($0 ~ /^(provides|requires|lanes|external_requires):/) has=1
      if ($0 ~ /^subtask_[0-9]/) has=1
    }
  ' "$BRIEF_FILE" 2>/dev/null || true)"
fi

# ---------------------------------------------------------------------------
# Title — first `# ` (H1) line, else the brief's own basename.
# ---------------------------------------------------------------------------
TITLE="$(grep -m1 -E '^# ' "$BRIEF_FILE" 2>/dev/null | sed -E 's/^#[[:space:]]*//')"
[ -n "$TITLE" ] || TITLE="$( [ -n "$BRIEF_ARG" ] && [ "$BRIEF_ARG" != "-" ] && basename "$BRIEF_ARG" || echo "context digest" )"

# ---------------------------------------------------------------------------
# Assemble + cap + atomic write.
# ---------------------------------------------------------------------------
CONTENT="$WORKDIR/content"
# ---------------------------------------------------------------------------
# PER-SECTION BUDGETING (replaces tail-first truncation).
#
# WHY: the digest was assembled in one stream and clipped from the TAIL, so the
# LAST section -- `## Cross-lane producer/consumer contracts`, which IS the
# lane/producer-consumer data this whole feature exists to deliver -- was the
# first thing deleted. Measured over the 72 archived briefs: 16 exceeded the cap
# and 8 lost that section entirely, heading and all. Worst of all, that happened
# on the LARGEST, most-parallel jobs -- exactly where lane ownership matters most
# -- and a worker following the pointer could not tell "the brief declared none"
# from "the cap ate it".
#
# NOW: every heading is emitted UNCONDITIONALLY, and each section carries its own
# marker distinguishing genuinely-absent (`_(none found)_`) from clipped
# (`_(truncated ...)_`). Budget is allocated in PRIORITY order from a shrinking
# pool, so the sections that carry contract/lane semantics are served before the
# big, compressible prose. `## File Impact Map` is deliberately allocated LAST:
# it is the largest and most redundant section (the brief itself remains one Read
# away), so it absorbs the squeeze instead of the contracts.
# ---------------------------------------------------------------------------
TRUNC_NOTE='_(truncated to fit the digest cap — read the brief for the full section)_'

# clip <body> <budget> -> prints body, clipped on a line boundary when over budget,
# followed by the per-section truncation marker. Never emits a partial trailing line.
clip() {
  _c_body="$1"; _c_budget="$2"
  if [ "${#_c_body}" -le "$_c_budget" ]; then
    printf '%s\n' "$_c_body"
    return 0
  fi
  _c_room=$(( _c_budget - ${#TRUNC_NOTE} - 2 ))
  [ "$_c_room" -lt 0 ] && _c_room=0
  printf '%s' "$_c_body" | head -c "$_c_room" | sed '$d' 2>/dev/null || true
  printf '%s\n' "$TRUNC_NOTE"
}

CROSS_LANE_EXPLAINER='_provides / requires / lanes / external_requires together, verbatim from the brief — this IS the producer/consumer + lane-ownership data; lane-collision logic is NOT re-derived here (see skills/supervisor-readiness/SKILL.md §"Lane Declaration Schema")._'

# Fixed overhead: title, generated line, five headings, the cross-lane explainer,
# blank lines, and headroom for the five possible per-section markers.
OVERHEAD=$(( 260 + ${#TITLE} + ${#CROSS_LANE_EXPLAINER} + 5 * ${#TRUNC_NOTE} ))
POOL=$(( MAX - OVERHEAD ))
[ "$POOL" -lt 0 ] && POOL=0

# take <outvar> <len> -> assigns the granted budget to <outvar> and DECREMENTS the
# pool. Deliberately NOT a command-substitution helper: `X="$(take N)"` would run
# the function in a SUBSHELL, so the `POOL=` decrement would be discarded and every
# section would be granted the full pool -- which is exactly the bug that made the
# first cut of this budgeting no-op (assembled size still overshot MAX, the
# whole-file backstop fired, and the last section was deleted again).
take() {
  _t_out="$1"; _t_need="$2"
  if [ "$_t_need" -le "$POOL" ]; then _t_give="$_t_need"; else _t_give="$POOL"; fi
  POOL=$(( POOL - _t_give ))
  eval "$_t_out=\$_t_give"
}

# Priority order (highest first). File Impact Map is intentionally LAST.
# `INTERFACES` is rendered with a "- " prefix per line, so budget for that growth.
INTERFACES_RENDERED="$(printf '%s\n' "$INTERFACES" | while IFS= read -r line; do
  [ -n "$line" ] && printf -- '- %s\n' "$line"
done)"
take B_CONTRACTS   ${#CONTRACTS}
take B_INTERFACES  ${#INTERFACES_RENDERED}
take B_SUBTASKS    ${#SUBTASK_SUMMARY}
take B_CONVENTIONS ${#CONVENTIONS}
take B_IMPACT      ${#FILE_IMPACT}

{
  printf '# Context Digest — %s\n\n' "$TITLE"
  printf '_Generated %s — bounded, pointer-handed to every worker on this job. Read only the sections you need._\n\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"

  printf '## File Impact Map\n\n'
  if [ -n "$FILE_IMPACT" ]; then clip "$FILE_IMPACT" "$B_IMPACT"; else printf '_(none found)_\n'; fi
  printf '\n'

  printf '## Interfaces touched\n\n'
  if [ -n "$INTERFACES" ]; then
    clip "$INTERFACES_RENDERED" "$B_INTERFACES"
  else
    printf '_(none found)_\n'
  fi
  printf '\n'

  printf '## Conventions\n\n'
  if [ -n "$CONVENTIONS" ]; then clip "$CONVENTIONS" "$B_CONVENTIONS"; else printf '_(none found)_\n'; fi
  printf '\n'

  printf '## Sibling-subtask summary\n\n'
  if [ -n "$SUBTASK_SUMMARY" ]; then clip "$SUBTASK_SUMMARY" "$B_SUBTASKS"; else printf '_(none found)_\n'; fi
  printf '\n'

  printf '## Cross-lane producer/consumer contracts\n\n'
  printf '%s\n\n' "$CROSS_LANE_EXPLAINER"
  if [ -n "$CONTRACTS" ]; then clip "$CONTRACTS" "$B_CONTRACTS"; else printf '_(none found)_\n'; fi
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

# Backstop only. Per-section budgeting above should keep the total under MAX; this
# whole-file clip remains so AC2 ("never unbounded") holds even if an overhead
# estimate drifts. It is expected NOT to fire in normal operation.
TRUNCATED=0
if [ "$SIZE" -le "$MAX" ]; then
  cat "$CONTENT" > "$TMPOUT" 2>/dev/null || true
else
  MARKER="[context-digest truncated at ${MAX} chars]"
  ALLOWED=$(( MAX - ${#MARKER} - 2 ))
  [ "$ALLOWED" -lt 0 ] && ALLOWED=0
  head -c "$ALLOWED" "$CONTENT" > "$TMPOUT" 2>/dev/null || true
  printf '\n%s\n' "$MARKER" >> "$TMPOUT" 2>/dev/null || true
  TRUNCATED=1
fi

# Report the size actually written to disk, not the pre-truncation assembled size — those two
# differ by construction whenever TRUNCATED=1, and reporting the pre-truncation figure next to
# "wrote <path>" previously read as (and was) the on-disk size, which it was not.
WRITTEN_SIZE="$(wc -c < "$TMPOUT" 2>/dev/null | tr -d '[:space:]')"
case "$WRITTEN_SIZE" in ''|*[!0-9]*) WRITTEN_SIZE="$SIZE" ;; esac

if mv -f "$TMPOUT" "$OUT" 2>/dev/null; then
  TMPOUT=""
else
  err "atomic move to '$OUT' failed — digest not written (fail-safe)"
  rm -f "$TMPOUT" 2>/dev/null || true
  exit 0
fi

if [ "$TRUNCATED" -eq 1 ]; then
  echo "build-context-digest: wrote $OUT ($WRITTEN_SIZE bytes on disk, truncated down from ${SIZE} assembled bytes to fit --max-chars ${MAX})"
else
  echo "build-context-digest: wrote $OUT ($WRITTEN_SIZE bytes)"
fi
exit 0
