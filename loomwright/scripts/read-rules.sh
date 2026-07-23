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
#   supersedes  (optional string)     Curation/anti-rot (ST-1). Names the `id` of ANOTHER rule this one
#                                     replaces. See "SUPERSESSION" below.
#
# SUPERSESSION (curation/anti-rot ST-1, normative encoding contract — PINNED, do not redesign):
#   A LIVE (validation-surviving) rule's `supersedes` field HIDES the rule it names from this reader's
#   output — single-hop only, NEVER transitive/chased (rule 3: "A supersedes B hides B; it does not
#   chase B's own supersedes"). A `supersedes` value is a hiding edge ONLY when it is a non-null STRING,
#   not equal to the rule's own id (excludes self-referential), and resolves to another rule that ALSO
#   survived per-object validation (excludes dangling — a target that doesn't exist, or that only exists
#   as a SKIPped/invalid object, cannot be hidden). ANY other shape (missing key, non-string, empty,
#   self-referential, dangling) is a no-op: the field is IGNORED and the CARRYING entry is still emitted
#   normally — demote-never-crash (rule 2), this reader NEVER hides an entry due to its OWN malformed
#   `supersedes`.
#
#   CYCLE DETECTION IS GENERAL, NOT PAIRWISE-ONLY (bot-review HIGH-1 fix): because each rule carries at
#   most ONE `supersedes` value, the declared edges form a "functional graph" (out-degree <= 1 per node),
#   so every cycle — of ANY length, not just a mutual 2-entry pair — is found by, for each node with an
#   outgoing edge, walking that single edge chain for a number of steps bounded by the total edge count
#   and checking whether the walk returns to its own starting node. Any node whose walk returns to itself
#   is a cycle member; EVERY edge originating from a cycle member is dropped (never used to hide anything)
#   — this generalizes the old 2-node-only mutual check, which only special-cased A<->B and left an
#   n>2 cycle (e.g. A supersedes B, B supersedes C, C supersedes A) with every member holding a live
#   "incoming hider", silently hiding ALL of them. Hiding every member of a cycle would silently drop N
#   rules from one misconfiguration, which contradicts the fail-safe "read it anyway, never hide it"
#   default (rule 2 lists "cyclic" alongside the other ignored shapes). A node OUTSIDE the cycle whose
#   OWN supersedes points INTO a cycle (e.g. D supersedes A, where A->B->C->A) is NOT itself a cycle
#   member (nothing points back to D), so D's edge is a normal, live, single-hop hiding edge — D still
#   hides A per the ordinary rule; only the cycle's OWN internal edges (A->B, B->C, C->A) are dropped, so
#   B and C remain visible and A is hidden by D exactly as an ordinary single-hop supersession would be.
#   This computation is a single BOUNDED, non-recursive pass (a fixed `range(0; edge_count)` walk per
#   node — never an open-ended/recursive graph traversal), so an arbitrarily malformed / cyclic
#   `supersedes` graph can never loop or hang the reader (rule 3: "Cycles cannot loop by construction").
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
# from an unattended seam with zero code-execution risk. Unattended `check` execution is now GATED in the
# separate rules-check.sh --no-cmd helper and is NOT this reader's concern — this reader still never
# executes a check.
#
# INJECTION SAFETY (jq-only): untrusted rule text (ids, statements, checks, categories, provenance)
# enters jq ONLY by jq reading the rule file as a POSITIONAL FILE-PATH argument (the path itself comes
# from `find`, never from rule content) — it is NEVER string-interpolated into a shell command or into
# a jq program, and the jq program text is fixed (the only flag-passed value is `--argjson fi`, the
# trusted integer file index). A malformed *.json file is fail-safe (its bad objects / the whole file
# are skipped; never crash; exit 0).
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

# 1. Input contract (no-hang). The reader NEVER reads its OWN stdin (fd 0) in v1: positional args (if
#    any) are purely informational/forward-compat (§4) and v1 output is always "all valid rules"
#    regardless. The `while read` loops further below all consume REDIRECTED temp files
#    (`done < "$files_list"`, `< "$valid_lines"`, `< "$skip_lines"`, `< "$render"`) — never the inherited
#    fd 0 — so a caller's open-but-idle stdin pipe (a hook/agent in a non-TTY context) can never hang
#    this reader. (No guard branch is needed to enforce this; the absence of any read FROM fd 0 IS the
#    contract.)

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

# 4. Merge + validate in TWO jq passes. Pass 1: a per-file loop reads each *.json file in sorted order
#    as a POSITIONAL jq argument (tagging every element with its file index then array index). Pass 2: a
#    single `jq -rs` reduce over the accumulated stream validates each object, drops duplicate ids
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
          elif ($o | has("check") | not) then
            {tag: "SKIP", why: ("missing-check id=" + (($o.id // "?")|tostring))}
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
  # --- Supersession (single-hop, non-transitive -- see "SUPERSESSION" in the header docstring). Only a
  #     LIVE (OK) rule supersedes field can hide another rule. A hiding EDGE requires: a non-null
  #     STRING value, not equal to the own id of the rule (excludes self-referential), and a target that
  #     is ALSO in the OK set (excludes dangling).
  | ( [ .[] | select(.kind == "OK") | .obj ] ) as $ok_objs
  | ( $ok_objs | map(.id) ) as $ok_ids
  | (
      $ok_objs
      | map(
          # NOTE: `index(FILTER)` evaluates FILTER against the ARRAY it is piped into, NOT the outer
          # ".", so `.supersedes`/`.id` must be captured into variables BEFORE piping into `$ok_ids |
          # index(...)` below (a bare `$ok_ids | index(.supersedes)` here would try `.supersedes` on
          # the ARRAY itself and error "Cannot index array with string").
          . as $o
          | ($o.supersedes) as $tgt
          | select( ($tgt | type) == "string" )
          | select( $tgt != $o.id )
          | select( ($ok_ids | index($tgt)) != null )
          | { from: $o.id, to: $tgt }
        )
    ) as $edges
  | ( ( $edges | map({ (.from): .to }) | add ) // {} ) as $edge_map
  # Cycle detection, GENERALIZED to any length (bot-review HIGH-1 -- see the "SUPERSESSION" header
  # comment for the full rationale). Since out-degree is <= 1 per node, a node is a cycle member iff
  # following its OWN edge chain returns to itself within a number of steps bounded by the total edge
  # count -- a single fixed-length (non-recursive) `range` walk per candidate node, so this can never
  # loop or hang on a malformed/cyclic graph.
  | ( $edges | map(.from) ) as $edge_from_ids
  | ( $edge_from_ids | length ) as $edge_n
  | (
      $edge_from_ids
      | map(
          . as $start
          | (
              reduce range(0; $edge_n) as $i (
                { cur: $edge_map[$start], hit: false };
                if .hit or (.cur == null) then .
                elif .cur == $start then { cur: .cur, hit: true }
                else { cur: ($edge_map[.cur] // null), hit: false }
                end
              )
            ) as $walk
          | select($walk.hit)
          | $start
        )
    ) as $cycle_members
  # Drop EVERY edge whose origin is a cycle member (this is exactly the set of intra-cycle edges,
  # since a cycle members single outgoing edge IS the edge that closes its own cycle) -- every cycle
  # member therefore keeps zero incoming hiders FROM its own cycle and stays visible. An edge from a
  # node OUTSIDE any cycle (even one that targets a cycle member) is left live -- ordinary single-hop
  # supersession still applies to it.
  | ( $edges | map(select( (.from) as $ef | ($cycle_members | index($ef)) == null )) ) as $edges_live
  | ( $edges_live | map(.to) ) as $hidden_ids
  # Emit SKIP diagnostics first (the shell partitions on the SKIP\t prefix — this now includes a
  # diagnostic line per rule hidden by supersession), then the sorted valid, non-hidden rules. Valid
  # rules are sorted by category then id for stable output. Tabs/newlines inside any rendered cell are
  # neutralized so they cannot break the line framing. (Same `index(...)` capture-before-pipe caveat
  # as above: `.id` is bound to $rid before `$hidden_ids | index($rid)`.)
  | ( [ .[] | select(.kind == "SKIP") | "SKIP\t" + .why ]
      + ( $ok_objs
          | map(select( (.id) as $rid | ($hidden_ids | index($rid)) != null ))
          | map("SKIP\tsuperseded id=" + .id)
        )
      + ( $ok_objs
          | map(select( (.id) as $rid | ($hidden_ids | index($rid)) == null ))
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
