#!/usr/bin/env bash
# read-rules.sh — fail-safe ADVISORY reader for the committed .agent/rules/ house-rules substrate.
# (New file — north-star slice #3b-i SUBSTRATE reader side; parity with read-bridge.sh /
#  read-lessons.sh advisory-reader convention. Pure-READ, NO side effects, NEVER executes a check.)
#
# Reads .agent/rules/*.json — each a JSON ARRAY of rule objects — merges them in a deterministic
# order, validates each object independently (fail-safe-SKIP, never crash), and emits the surviving
# valid rules as an advisory markdown block subordinate to CLAUDE.md. The schema + contract authority
# is skills/rules/SKILL.md; this reader conforms to it, never the reverse.
#
# SCHEMA (per skills/rules/SKILL.md §1) — each rule object MUST have:
#   id          (string)              UNIQUE across the merged set (first-seen wins — §2).
#   category    (string)
#   statement   (string)
#   enforcement (enum)                EXACTLY "advisory" | "must"; any other value ⇒ SKIP.
#   check       (string | null)       A runnable shell string OR null. EMITTED AS DATA ONLY — NEVER RUN.
#   provenance  (object)
#   applies_to  (optional)            RESERVED for slice 3b-ii enforcement filtering — INERT in v1.
#
# v1 "applicable = ALL valid rules" (§3): no path/scope filtering. Positional args are accepted but
# are informational / forward-compat ONLY — they do NOT change v1 output. `applies_to` is inert in v1.
#
# DETERMINISTIC MERGE ORDER (§2): glob .agent/rules/*.json, process files in LC_ALL=C
# repo-relative-path-sorted order; within a file, array elements by index. The FIRST valid occurrence
# of an `id` wins; any later duplicate `id` is SKIPPED.
#
# PER-OBJECT VALIDATION (§2, fail-safe-skip): SKIP — never crash on — any object that is malformed,
# missing a required field, carries an unknown `enforcement`, or duplicates an already-seen `id`.
# A skipped object is dropped from output + gets a ONE-LINE diagnostic to .supervisor/logs/ (never
# stdout). The reader STILL exits 0 and STILL emits every remaining valid rule.
#
# INPUT CONTRACT (§4, no-hang — mirrors read-bridge.sh): accepts OPTIONAL positional args. ARGS TAKE
# PRECEDENCE: when args are present, STDIN is NEVER read. If no args AND stdin is not a TTY, the reader
# does NOT block on stdin (v1 ignores stdin content entirely). So a future hook / agent caller (whose
# stdin is an open-but-idle pipe) can never hang it.
#
# THE INVARIANT (§9): the reader emits each rule's `check` as DATA (text) only — there is NO code path
# that runs, evals, sources, or `bash -c`s a `check` value. This is what makes the reader safe to call
# from a future unattended seam with zero code-execution risk. Unattended `check` execution is DEFERRED
# to slice 3b-ii and is NOT this reader's concern.
#
# INJECTION SAFETY (jq-only): untrusted rule text (ids, statements, checks, categories, provenance)
# crosses the boundary via jq's --rawfile / --slurpfile / --argjson / --arg ONLY — it is NEVER
# string-interpolated into a shell command or into a jq program. A malformed *.json file is fail-safe
# (its bad objects / the whole file are skipped; never crash; exit 0).
#
# FAIL-SAFE (hard requirement): ALWAYS exit 0 — a read must never break its caller.
#   - .agent/rules/ absent / no *.json files  → emit nothing, exit 0
#   - jq unavailable                            → log_skip diagnostic, emit nothing, exit 0
#   - malformed JSON                            → fail-safe skip, exit 0
#   - zero valid rules survive                  → EMPTY (no banner), exit 0
#
# Usage:  read-rules.sh [path ...]   (args informational in v1; prints valid rules to stdout)
# Exit:   always 0; diagnostics go to stderr + .supervisor/logs/memory.log.

set -uo pipefail   # `set -e` intentionally omitted — a read must NEVER fail its caller.

GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$GITROOT" 2>/dev/null || true

RULES_DIR=".agent/rules"
LOG=".supervisor/logs/memory.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

log_skip() {
  # $1 = message; emit to stderr + memory.log, never to stdout.
  echo "$1" >&2
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" "$1" >> "$LOG" 2>/dev/null || true
}

# 1. Input contract (no-hang). ARGS TAKE PRECEDENCE: when positional args are present, STDIN is NEVER
#    read, so an args-bearing call can never block on an open-but-idle stdin in a non-TTY context. When
#    no args are given AND stdin is not a TTY, we still do NOT read stdin — v1 ignores stdin content
#    entirely (output is always "all valid rules"). This whole block is therefore purely defensive
#    against a future caller's idle pipe; it changes nothing about v1 output.
if [ "$#" -eq 0 ] && [ ! -t 0 ]; then
  : # intentionally do nothing — v1 ignores stdin; never block on it.
fi

# 2. Tooling presence (fail-safe, quiet). jq is REQUIRED by this reader (parsing + injection-safe
#    boundary). Mirror read-bridge.sh: jq unavailable → diagnostic + emit nothing + exit 0.
if ! command -v jq >/dev/null 2>&1; then
  log_skip "read-rules: jq unavailable — rules unreadable, emitting nothing (fail-safe)"
  exit 0
fi

# 3. Collect rule files in LC_ALL=C repo-relative-path-sorted order (deterministic merge order).
#    No matching files (or absent dir) → emit nothing, exit 0.
files_list="$(mktemp)"; trap 'rm -f "$files_list" 2>/dev/null' EXIT
# Use find (not a glob) so an empty/absent dir is a clean no-match, and sort under LC_ALL=C.
LC_ALL=C find "$RULES_DIR" -maxdepth 1 -type f -name '*.json' 2>/dev/null \
  | LC_ALL=C sort > "$files_list" 2>/dev/null || true
[ -s "$files_list" ] || exit 0   # no *.json rule files → nothing to emit

# 4. Merge + validate in a SINGLE jq program. Files are passed via --slurpfile in sorted order; jq
#    flattens them by file index then by array index, validates each object, drops duplicate ids
#    (first-seen wins), and emits:
#      - valid rules as tab-delimited lines (sorted by category then id) for the shell to render,
#      - skip diagnostics on a separate channel so the shell can log them WITHOUT them reaching stdout.
#    Untrusted text never leaves the jq data model; the program is fixed text, and the only thing that
#    crosses into the jq invocation is the FILE PATH (a positional argument, sourced from `find` — never
#    rule content). A malformed file makes the jq read fail for that file → fail-safe quiet.
#
#    To keep injection safety AND ordering, we read each file in turn (as a positional jq argument) into
#    one combined array, tagging each element with its (file_index, elem_index) so the "first-seen id"
#    is deterministic.
combined="$(mktemp)"; trap 'rm -f "$files_list" "$combined" 2>/dev/null' EXIT
: > "$combined"
fidx=0
while IFS= read -r rf; do
  [ -n "$rf" ] || continue
  # Each file must be a JSON ARRAY of objects. Read it injection-safely as a positional jq file
  # argument (the path comes from `find`, never rule content), tagging each element with file/elem
  # indices for deterministic first-seen ordering. A non-array or malformed file yields no rows
  # (fail-safe-skip the whole file) and a diagnostic.
  rows="$(jq -c \
            --argjson fi "$fidx" '
            if type == "array" then
              to_entries
              | map({ fi: $fi, ei: .key, obj: .value })
              | .[]
            else
              empty
            end' "$rf" 2>/dev/null)"
  if [ -z "$rows" ]; then
    # Distinguish "valid but empty array" (no diagnostic needed) from "malformed / non-array".
    if ! jq -e 'type == "array"' "$rf" >/dev/null 2>&1; then
      log_skip "read-rules: skipping malformed or non-array rule file: $rf"
    fi
  else
    printf '%s\n' "$rows" >> "$combined"
  fi
  fidx=$((fidx + 1))
done < "$files_list"

[ -s "$combined" ] || exit 0   # no parseable rows at all → emit nothing

# 5. Validate every tagged row, dedup by first-seen id, and produce two outputs:
#      stdout of jq  → tab-delimited VALID rule lines (already sorted category,id) for rendering.
#      "SKIP\t..."   → diagnostic lines, separated so the shell logs them (never to real stdout).
#    All untrusted fields stay inside jq; emitted cells were sanitized through the jq data model
#    (newlines/tabs in a value can't break the framing because we gsub them out of rendered cells).
valid_lines="$(mktemp)"; skip_lines="$(mktemp)"
trap 'rm -f "$files_list" "$combined" "$valid_lines" "$skip_lines" 2>/dev/null' EXIT

jq -rs '
  # Input: a stream of {fi, ei, obj} rows, already in file-sorted, then array-index order.
  sort_by([.fi, .ei])
  | reduce .[] as $row ( {seen: {}, out: []};
      ($row.obj) as $o
      | (
          if ($o | type) != "object" then
            {tag: "SKIP", why: "not-an-object"}
          elif ($o.id        | type) != "string" then
            {tag: "SKIP", why: "missing-or-nonstring-id"}
          elif ($o.category  | type) != "string" then
            {tag: "SKIP", why: ("bad-category id=" + (($o.id // "?")|tostring))}
          elif ($o.statement | type) != "string" then
            {tag: "SKIP", why: ("bad-statement id=" + (($o.id // "?")|tostring))}
          elif (($o.enforcement | type) != "string")
               or (($o.enforcement == "advisory") or ($o.enforcement == "must") | not) then
            {tag: "SKIP", why: ("bad-enforcement id=" + (($o.id // "?")|tostring))}
          elif (($o.check | type) != "string") and (($o.check) != null) then
            {tag: "SKIP", why: ("bad-check id=" + (($o.id // "?")|tostring))}
          elif ($o.provenance | type) != "object" then
            {tag: "SKIP", why: ("bad-provenance id=" + (($o.id // "?")|tostring))}
          elif (.seen[$o.id] // false) then
            {tag: "SKIP", why: ("duplicate-id " + $o.id)}
          else
            {tag: "OK", obj: $o}
          end
        ) as $res
      | if $res.tag == "OK" then
          { seen: (.seen + { ($res.obj.id): true }),
            out:  (.out + [ {kind: "OK", obj: $res.obj} ]) }
        else
          { seen: .seen, out: (.out + [ {kind: "SKIP", why: $res.why} ]) }
        end
    )
  | .out
  # Emit SKIP diagnostics first (the shell partitions on the SKIP\t prefix), then the sorted valid
  # rules. Valid rules are sorted by category then id for stable output. Tabs/newlines inside any
  # rendered cell are neutralized so they cannot break the line framing.
  | ( [ .[] | select(.kind == "SKIP") | "SKIP\t" + .why ]
      + ( [ .[] | select(.kind == "OK") | .obj ]
          | sort_by([.category, .id])
          | map(
              "RULE\t"
              + (.id          | gsub("[\t\n]"; " "))      + "\t"
              + (.category    | gsub("[\t\n]"; " "))      + "\t"
              + (.enforcement | gsub("[\t\n]"; " "))      + "\t"
              + (.statement   | gsub("[\t\n]"; " "))      + "\t"
              + ((.check // "(none)") | gsub("[\t\n]"; " "))
            )
        )
    )
  | .[]
' "$combined" 2>/dev/null > "$valid_lines" || true

# Partition jq output into SKIP diagnostics (→ log only) and RULE lines (→ render).
: > "$skip_lines"
rule_count=0
render="$(mktemp)"; : > "$render"
trap 'rm -f "$files_list" "$combined" "$valid_lines" "$skip_lines" "$render" 2>/dev/null' EXIT
while IFS= read -r line; do
  case "$line" in
    SKIP$'\t'*) printf '%s\n' "${line#SKIP$'\t'}" >> "$skip_lines" ;;
    RULE$'\t'*) printf '%s\n' "$line" >> "$render"; rule_count=$((rule_count + 1)) ;;
  esac
done < "$valid_lines"

# Log each skipped object as a one-line diagnostic (never to stdout).
if [ -s "$skip_lines" ]; then
  while IFS= read -r why; do
    [ -n "$why" ] && log_skip "read-rules: skipped rule object ($why)"
  done < "$skip_lines"
fi

# 6. EMPTY on no-valid-rule — zero valid rules survive ⇒ emit NOTHING (no banner), exit 0, so
#    machine consumers can gate enrichment on NON-EMPTY stdout (mirrors read-bridge.sh).
[ "$rule_count" -gt 0 ] || exit 0

# 7. Emit the advisory block. Header is EXACTLY the subordinate-to-CLAUDE.md banner from §5. Each
#    rule shows statement, category, and the `check` as DATA (text); `must` rules are flagged with a
#    [MUST] marker, advisory rules are unflagged. The `check` is printed verbatim as text — there is
#    NO code path here (or anywhere in this reader) that runs, evals, sources, or bash -c's it.
printf '%s\n' "## Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)"
while IFS=$'\t' read -r kind r_id r_cat r_enf r_stmt r_check; do
  [ "$kind" = "RULE" ] || continue
  if [ "$r_enf" = "must" ]; then
    flag="[MUST] "
  else
    flag=""
  fi
  printf '%s\n' "- ${flag}${r_stmt}"
  printf '%s\n' "  - category: ${r_cat}"
  # `check` is emitted as DATA only — NEVER executed (the invariant, §9).
  printf '%s\n' "  - check (data only, NOT executed by this reader): ${r_check}"
done < "$render"

exit 0
