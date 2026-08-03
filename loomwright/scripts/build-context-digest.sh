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
# BASE-10 NORMALIZATION — load-bearing, not cosmetic. The digits-only test above ACCEPTS a
# leading zero, and bash reads a leading-zero numeral inside `$(( ))` as OCTAL. Two distinct
# failures followed, both reproduced against this script before the fix:
#   1. HARD CRASH, breaking the "ALWAYS exits 0" contract in this file's own header.
#      `--max-chars 0089` -> `$(( MAX - OVERHEAD ))` dies with "value too great for base
#      (error token is 0089)" because 8 and 9 are not octal digits, and the failed assignment
#      then cascades into `POOL: unbound variable` under `set -u`. Observed exit status: 1.
#      A fatal arithmetic parse error is NOT suppressible by omitting `set -e`.
#   2. SILENT MISCALCULATION on a well-formed octal numeral. `--max-chars 020000` is read as
#      8192, not 20000 — measured: a 7943-byte digest written under a cap the caller believed
#      was 20000. No error, no warning, wrong bound.
# Both are reachable through the DOCUMENTED public interface, not just a hypothetical future
# caller: `CONTEXT_DIGEST_MAX_CHARS=0089` reproduces the crash exactly. `10#` forces base 10,
# so `0089` -> 89 and falls through to the floor checks below like any other too-small cap.
MAX=$(( 10#$MAX ))
if [ "$MAX" -le 0 ] 2>/dev/null; then
  err "--max-chars must be > 0 — using default 6000"
  MAX=6000
fi
# A cap smaller than the truncation marker itself cannot honor the "total file
# fits the cap INCLUDING the marker" contract — treat as invalid, fall back.
# NOTE: this is only an early sanity floor, NOT the real cap check. The binding
# check is the CAP-vs-OVERHEAD reconciliation further down, which compares MAX
# against the digest's ACTUAL fixed overhead (~900 bytes, title-dependent) — it
# cannot run here because the overhead depends on the brief's own title.
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
elif [ ! -t 0 ]; then
  # --brief - (explicit stdin) OR no --brief given — either way stdin must be a pipe.
  # The tty check is UNCONDITIONAL, deliberately: gating it on `[ -n "$BRIEF_ARG" ] ||` let the
  # first disjunct short-circuit, so `--brief -` with no piped input ran `cat` against the
  # terminal and blocked forever — a hang, which this script's fail-safe contract ("any internal
  # error => write nothing, message to stderr, exit 0") does not permit. An explicit `-` still
  # differs from omitting `--brief`: it produces the clearer message below.
  cat > "$BRIEF_FILE" 2>/dev/null || true
elif [ -n "$BRIEF_ARG" ]; then
  err "--brief - given but stdin is a terminal, not a pipe — nothing to read (fail-safe)"
  exit 0
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
# UNCLOSED-FENCE RECOVERY (bot review, v15.20.0). `infence` is a raw toggle, so a brief with an
# ODD number of fence markers — an example block someone forgot to close, entirely possible in
# generated markdown — leaves it stuck open for the rest of the file. Every heading after that
# point becomes invisible and extraction silently blanks or misattributes each later section, with
# no error. Reproduced: a brief whose `## File Impact Map` sat after an unclosed fence produced the
# "no File Impact Map section" fallback while `## Subtask Structure` swallowed the file to EOF.
#
# The fix is a WHOLE-FILE parity pre-pass, deliberately NOT a per-line heuristic. The obvious
# heuristic — "an ATX heading at column 0 proves the fence was never closed" — was tried and
# REGRESSED the primary case: real briefs carry `# Subtask 1 — ...` at column 0 INSIDE the
# contract YAML fence (measured in 2026-06-17-review-pr-until-mergeable.md:74), which is exactly
# the line fence-awareness exists to protect, and treating it as a heading truncated the whole
# Cross-lane contracts section. Counting instead lets us neutralize ONLY the final unmatched
# opener, leaving every well-formed brief byte-identical.
_fence_parity_line() {
  # Echoes the line number of the LAST fence marker when the count is odd, else 0.
  awk '/^(```|~~~)/ { n++; last = NR } END { print (n % 2) ? last : 0 }' "$1" 2>/dev/null
}
UNMATCHED_FENCE_LINE="$(_fence_parity_line "$BRIEF_FILE")"
case "$UNMATCHED_FENCE_LINE" in ''|*[!0-9]*) UNMATCHED_FENCE_LINE=0 ;; esac
[ "$UNMATCHED_FENCE_LINE" -gt 0 ] && \
  err "brief has an unclosed code fence at line ${UNMATCHED_FENCE_LINE} — ignoring it so later headings stay visible"

extract_section() {
  awk -v want="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" \
      -v badfence="$UNMATCHED_FENCE_LINE" '
    BEGIN { on = 0; infence = 0 }
    {
      line = $0
      if (line ~ /^(```|~~~)/) {
        # Skip the toggle for the single unmatched opener identified by the parity pre-pass;
        # it is content, not a fence. Every other fence behaves exactly as before.
        if (badfence > 0 && NR == badfence) { if (on) { print } ; next }
        infence = !infence
        if (on) { print }
        next
      }
      if (!infence && match(line, /^#{1,4}[ \t]+/)) {
        heading = substr(line, RLENGTH + 1)
        # Strip a leading section NUMBER ("## 5. File Impact Map" -> "File Impact Map").
        # The prefix test below is index()==1, so an unstripped "5. " never matches and the
        # WHOLE digest comes back `_(none found)_` -- measured on
        # 2026-04-25-github-issues-telemetry-system.md: a 660-byte digest with all five
        # sections empty despite the brief carrying every one of them.
        sub(/^[0-9]+\.[ \t]*/, "", heading)
        htl = tolower(heading)
        if (on) { exit }
        # WORD-BOUNDARY GUARD on the prefix test. A bare `index()==1` also matches a heading
        # that merely STARTS with the target text, so a decoy such as
        # `## File Impact Mapping (draft, ignore)` appearing BEFORE the real
        # `## File Impact Map` steals the section outright: extraction starts on the decoy, and
        # the `if (on) exit` above then terminates at the very next heading -- which IS the real
        # target -- so the section ships the body of the decoy and the real one is never reached.
        # (No apostrophes in this comment: the whole awk program is a single-quoted shell string,
        # so one would terminate it and produce a syntax error at the next paren.)
        # Require the character following the matched prefix to be a non-alphanumeric (or end of
        # heading), so `File Impact Map`, `File Impact Map:` and `File Impact Map (v2)` still
        # match while `File Impact Mapping` does not. Prefix tolerance is deliberately kept --
        # it is what absorbs the trailing-qualifier drift this builder exists to tolerate.
        if (index(htl, want) == 1) {
          rest = substr(htl, length(want) + 1)
          if (rest == "" || rest !~ /^[a-z0-9]/) { on = 1; next }
        }
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
        # Do NOT re-embed the Subtask Structure table here: `## Sibling-subtask summary`
        # already reproduces it verbatim, so embedding it made 34/73 digests carry the same
        # table TWICE, each copy drawing its own allocation from the one 6000-byte pool. On
        # the worst case that squeeze left this very section as a bare `_(truncated)_` marker
        # with zero content. Point at the sibling section instead and spend the budget on the
        # File Overlap Matrix, which appears nowhere else.
        printf '_No `## File Impact Map` section in this brief — see `## Sibling-subtask summary` below for the per-subtask file breakdown; the File Overlap Matrix (if any) follows here._\n'
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
# KEY-ORDER-INDEPENDENT by construction. The previous form anchored on the literal
# `{kind:` -- i.e. it required `kind:` to be the FIRST key -- which silently dropped
# EVERY `requires` entry, because the documented schema leads those with `from:`
# (`{from: "1", kind: "symbol", path: ..., name: ...}`). The effect was that the one
# section a worker most wants -- a sibling's public surface it must consume -- only
# ever listed same-subtask `provides`, never a single cross-subtask interface. It was
# invisible in testing because the fixture's requires-side symbol was ALSO provided by
# a sibling, so dedup made the two indistinguishable.
INTERFACES="$(
  awk '
    {
      line = $0
      # Walk every {...} brace item on the line independently.
      while (match(line, /\{[^{}]*\}/)) {
        item = substr(line, RSTART, RLENGTH)
        line = substr(line, RSTART + RLENGTH)
        if (item !~ /kind:[[:space:]]*"?(symbol|type)"?/) continue
        k = item; sub(/.*kind:[[:space:]]*"?/, "", k); sub(/"?[,}].*/, "", k)
        p = item; if (p !~ /path:/) continue
        sub(/.*path:[[:space:]]*"?/, "", p); sub(/"?[,}].*/, "", p)
        n = item; if (n !~ /name:/) continue
        sub(/.*name:[[:space:]]*"?/, "", n); sub(/"?[,}].*/, "", n)
        gsub(/^[ \t]+|[ \t]+$/, "", k); gsub(/^[ \t]+|[ \t]+$/, "", p); gsub(/^[ \t]+|[ \t]+$/, "", n)
        if (k != "" && p != "" && n != "") print p " :: " n " (" k ")"
      }
    }
  ' "$BRIEF_FILE" 2>/dev/null | sort -u
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
    # Case-INSENSITIVE fence marker (```yaml / ```YAML / ```Yml). This is the LAST-RESORT
    # tier: a brief reaching here matched no heading rule at all, so a case-sensitive miss
    # here means the section renders `_(none found)_` with no further fallback -- the exact
    # "heading present, no data behind it" failure this tier exists to close.
    tolower($0) ~ /^```ya?ml[[:space:]]*$/ { inf=1; n=0; has=0; next }
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
TRUNC_NOTE_LONG='_(truncated to fit the digest cap — read the brief for the full section)_'
TRUNC_NOTE_SHORT='_(truncated)_'
TRUNC_NOTE="$TRUNC_NOTE_LONG"

# clip <body> <budget> -> prints body, clipped on a line boundary when over budget,
# followed by the per-section truncation marker. Never emits a partial trailing line.
#
# <budget> is a CONTENT budget and deliberately EXCLUDES the marker: OVERHEAD below
# already reserves `5 * ${#TRUNC_NOTE}` outside the pool, once per possible section, so
# subtracting the marker again here would double-charge it. That double-charge is not
# cosmetic -- it is what turned a section granted a small-but-real budget into a bare
# marker with zero content (room went negative and clamped to 0), which is the
# "heading with no data behind it" failure this whole builder exists to avoid.
# blen <string> -> BYTE length. Deliberately NOT `${#var}`: under a UTF-8 locale that is a
# CHARACTER count, while the `--max-chars` cap is enforced against `wc -c` BYTES further down.
# This repo's briefs are dense with multi-byte punctuation (— ≤ §), so the two diverge by
# hundreds of bytes on a real brief: measured on 2026-05-16-v14-autonomous-continuous-mode.md
# the assembled digest was 5973 chars but 6004 BYTES, overshooting a 6000 cap and firing the
# whole-file backstop — which clips the TAIL, i.e. deletes from `## Cross-lane producer/consumer
# contracts`, the exact section the priority ordering below exists to protect. Every length that
# feeds the pool arithmetic must therefore be measured in the same unit the cap is.
blen() { printf '%s' "$1" | wc -c | tr -d '[:space:]'; }

clip() {
  _c_body="$1"; _c_budget="$2"
  if [ "$(blen "$_c_body")" -le "$_c_budget" ]; then
    printf '%s\n' "$_c_body"
    return 0
  fi
  if [ "$_c_budget" -ge 1 ]; then
    _c_kept="$(printf '%s' "$_c_body" | head -c "$_c_budget" | sed '$d' 2>/dev/null || true)"
    # WORD-BOUNDARY FALLBACK. The line-boundary clip above yields NOTHING when the section's
    # very first line is itself longer than the budget -- common for a markdown table row or a
    # long prose bullet at a tight cap -- leaving a heading above a bare marker, the
    # "heading with no data behind it" outcome this builder exists to avoid. Fall back to
    # clipping mid-line at the last SPACE within the budget. That is still UTF-8 safe by
    # construction: the cut lands on an ASCII space, never inside a multi-byte sequence.
    if [ -z "$_c_kept" ]; then
      _c_kept="$(printf '%s' "$_c_body" | head -c "$_c_budget" | sed 's/[^ ]*$//' 2>/dev/null || true)"
      # Strip the trailing space run so the marker does not read as part of the clipped text.
      _c_kept="${_c_kept% }"
    fi
    [ -n "$_c_kept" ] && printf '%s\n' "$_c_kept"
  fi
  printf '%s\n' "$TRUNC_NOTE"
}

CROSS_LANE_EXPLAINER_FULL='_provides / requires / lanes / external_requires together, verbatim from the brief — this IS the producer/consumer + lane-ownership data; lane-collision logic is NOT re-derived here (see skills/supervisor-readiness/SKILL.md §"Lane Declaration Schema")._'
CROSS_LANE_EXPLAINER="$CROSS_LANE_EXPLAINER_FULL"

# Fixed overhead: title, generated line, five headings, the cross-lane explainer,
# blank lines, and headroom for the five possible per-section markers.
# DERIVED, not guessed. `260` was a hand-estimated constant and it was ~21 bytes SHORT of the
# real frame (title line + generated line + five headings + their blank lines), which is what
# actually produced the one measured cap overshoot -- the whole-file backstop then fired and
# clipped the TAIL, i.e. the Cross-lane contracts section this budgeting exists to protect.
# A magic number that drifts every time a heading is reworded is the wrong shape here, so the
# frame is measured from THE SAME literal strings the emit block below prints. `_FRAME_HEADINGS`
# is asserted against those printfs by scripts/test-context-digest.sh, so a reworded heading
# cannot silently desynchronize the two.
_FRAME_HEADINGS='## File Impact Map
## Interfaces touched
## Conventions
## Sibling-subtask summary
## Cross-lane producer/consumer contracts'
# Title line ("# Context Digest — " + title + "\n\n"), the generated line with its 20-byte
# ISO-8601 timestamp, each heading followed by "\n\n" and each section by a trailing "\n",
# plus clip()'s own trailing newline per populated section.
_FRAME_TITLE_LIT='# Context Digest — '
_FRAME_GEN_LIT='_Generated 0000-00-00T00:00:00Z — bounded, pointer-handed to every worker on this job. Read only the sections you need._'
compute_pool() {
  # 5 headings x (2 newlines after + 1 section-trailing newline + 1 clip newline) = 20 bytes,
  # + 2 newlines after the title line, + 2 after the generated line.
  _frame=$(( $(blen "$_FRAME_HEADINGS") + $(blen "$_FRAME_TITLE_LIT") + $(blen "$_FRAME_GEN_LIT") + 20 + 4 ))
  OVERHEAD=$(( _frame + $(blen "$TITLE") + $(blen "$CROSS_LANE_EXPLAINER") + 5 * $(blen "$TRUNC_NOTE") ))
  POOL=$(( MAX - OVERHEAD ))
  [ "$POOL" -lt 0 ] && POOL=0
}
compute_pool

# ---------------------------------------------------------------------------
# CAP-vs-OVERHEAD RECONCILIATION.
#
# The fixed overhead above is ~900 bytes with the long marker and the full explainer.
# Nothing previously checked MAX against it -- the only guard was `_min_cap=60`, ~15x
# too low -- so ANY cap below roughly 1200 produced a digest of headings and truncation
# markers with ZERO section content, and reported success. Measured before this fix:
# --max-chars 900/1000/1500 all yielded three markers and no content at all, including
# `## Cross-lane producer/consumer contracts`, the highest-priority section, which is
# allocated FIRST. The contentless output was indistinguishable from a real build.
#
# Tier 1 (above) is the full-fidelity form. Tier 2 shrinks the FIXED overhead -- short
# marker, no explainer -- rather than the content, because at a tight cap the caller
# wants the brief's data, not the builder's own prose. Tier 3 refuses: a cap that
# cannot fund even a floor of content produces nothing, on stderr, exit 0. An ABSENT
# digest is honest and every consumer already handles it (contextDigestPointer returns
# undefined; the spawn contracts all say "proceed without it") -- a contentless one
# claims to carry analysis it does not have.
# ---------------------------------------------------------------------------
# The floor is DERIVED, not guessed: five sections each need at least one useful line, so the
# minimum fundable pool is `5 * _FLOOR_MIN_USEFUL`. The old pair (`_CONTENT_FLOOR=300` shrink
# trigger + a bare `POOL < 1` refusal) let tier 2's overhead shrink push POOL just above zero,
# after which tier 3 happily wrote a digest whose sections were ALL bare markers — measured at
# --max-chars 700/800/900: 4 of 5 sections contentless, the exact output tier 3 exists to refuse.
# Tying both thresholds to the same constant closes that window by construction.
_FLOOR_MIN_USEFUL=80
_CONTENT_FLOOR=$(( 5 * _FLOOR_MIN_USEFUL ))
if [ "$POOL" -lt "$_CONTENT_FLOOR" ]; then
  TRUNC_NOTE="$TRUNC_NOTE_SHORT"
  CROSS_LANE_EXPLAINER=""
  compute_pool
fi
if [ "$POOL" -lt "$_CONTENT_FLOOR" ]; then
  err "--max-chars ${MAX} is below the digest's own fixed overhead (${OVERHEAD}) — every section would be an empty truncation marker; nothing written (fail-safe). Use --max-chars >= $(( OVERHEAD + _CONTENT_FLOOR ))."
  exit 0
fi

# TWO-PASS ALLOCATION: floors first, then priority surplus.
#
# WHY the floor pass exists: strict priority order with no reserve lets the FIRST
# section consume the ENTIRE pool, leaving every later section a budget of 0 -- which
# renders as a bare `_(truncated)_` marker with ZERO content. That is the very
# "heading with no data behind it" failure this builder's every other guard exists to
# prevent, and the one the tier-3 cap reconciliation above REFUSES TO WRITE for.
# Measured across all 72 archived briefs before this fix: 15 produced a digest with at
# least one contentless section, worst case 4 of 5 (2026-07-31-worker-context-digest-
# lanes.md, this feature's own brief). Priority ordering is still honored -- it now
# governs the SURPLUS, not the whole pool.
#
# grant <outvar> <need> <cap> -> pass 1. Gives min(need, cap, POOL); a short or absent
# section returns its unused floor to the pool immediately, so floors are never wasted.
# top_up <outvar> <need>      -> pass 2. Tops the section up toward its full need from
# whatever remains, in priority order.
#
# Both are deliberately NOT command-substitution helpers: `X="$(grant ...)"` would run
# the function in a SUBSHELL, so the `POOL=` decrement would be discarded and every
# section would be granted the full pool -- which is exactly the bug that made the
# first cut of this budgeting no-op (assembled size still overshot MAX, the
# whole-file backstop fired, and the last section was deleted again).
grant() {
  _g_out="$1"; _g_give="$2"
  [ "$_g_give" -gt "$3" ] && _g_give="$3"
  [ "$_g_give" -gt "$POOL" ] && _g_give="$POOL"
  POOL=$(( POOL - _g_give ))
  eval "$_g_out=\$_g_give"
}
top_up() {
  _u_out="$1"; _u_need="$2"
  eval "_u_have=\$$_u_out"
  _u_want=$(( _u_need - _u_have ))
  [ "$_u_want" -lt 0 ] && _u_want=0
  [ "$_u_want" -gt "$POOL" ] && _u_want="$POOL"
  POOL=$(( POOL - _u_want ))
  eval "$_u_out=\$(( _u_have + _u_want ))"
}

# Priority order (highest first). File Impact Map is intentionally LAST.
# `INTERFACES` is rendered with a "- " prefix per line, so budget for that growth.
INTERFACES_RENDERED="$(printf '%s\n' "$INTERFACES" | while IFS= read -r line; do
  [ -n "$line" ] && printf -- '- %s\n' "$line"
done)"
L_CONTRACTS="$(blen "$CONTRACTS")"
L_INTERFACES="$(blen "$INTERFACES_RENDERED")"
L_SUBTASKS="$(blen "$SUBTASK_SUMMARY")"
L_CONVENTIONS="$(blen "$CONVENTIONS")"
L_IMPACT="$(blen "$FILE_IMPACT")"

# Each of the five sections may reserve up to 10% of the pool, so floors claim at most half of
# it and the priority sweep still controls the other half. `clip` cuts on a LINE boundary, so a
# floor too small to hold one whole line would yield nothing but a marker -- hence the clamp UP
# to `_FLOOR_MIN_USEFUL`. The clamp is always affordable: the tier-3 refusal above guarantees
# `POOL >= 5 * _FLOOR_MIN_USEFUL`, so five floors always fit. (The earlier form zeroed the floor
# below that threshold and fell back to pure priority order -- which reintroduced the very
# starvation the floor exists to prevent, at exactly the tight caps where it bites hardest.)
_FLOOR=$(( POOL / 10 ))
[ "$_FLOOR" -lt "$_FLOOR_MIN_USEFUL" ] && _FLOOR="$_FLOOR_MIN_USEFUL"

grant B_CONTRACTS   "$L_CONTRACTS"   "$_FLOOR"
grant B_INTERFACES  "$L_INTERFACES"  "$_FLOOR"
grant B_SUBTASKS    "$L_SUBTASKS"    "$_FLOOR"
grant B_CONVENTIONS "$L_CONVENTIONS" "$_FLOOR"
grant B_IMPACT      "$L_IMPACT"      "$_FLOOR"

top_up B_CONTRACTS   "$L_CONTRACTS"
top_up B_INTERFACES  "$L_INTERFACES"
top_up B_SUBTASKS    "$L_SUBTASKS"
top_up B_CONVENTIONS "$L_CONVENTIONS"
top_up B_IMPACT      "$L_IMPACT"

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
  # Dropped entirely under the tier-2 tight-cap shrink above — at that cap the budget
  # belongs to the brief's contract data, not to the builder's own explanatory prose.
  [ -n "$CROSS_LANE_EXPLAINER" ] && printf '%s\n\n' "$CROSS_LANE_EXPLAINER"
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
  # `sed '$d'` drops the partial trailing line `head -c` leaves behind — without it the
  # backstop could end the file mid-marker (observed: a bare `_(truncated to fit the digest `
  # with no closing underscore, directly above the file-level marker below).
  head -c "$ALLOWED" "$CONTENT" | sed '$d' > "$TMPOUT" 2>/dev/null || true
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
