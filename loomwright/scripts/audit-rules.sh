#!/usr/bin/env bash
# audit-rules.sh — READ-ONLY, PROPOSE-ONLY correctness audit over the committed `.agent/rules/` store.
#
# WHAT IT IS FOR — THE OVER-TIME HALF OF A WRITE-TIME GATE. `validate-entry.sh` already holds five
# correctness checks and `add-rule.sh` runs all five on every `/rules add`. But it runs them ONCE, AT
# WRITE TIME, AGAINST THE STORE AS IT STOOD THAT DAY. Nothing re-validates a rule as the repo drifts
# underneath it: the path a rule scopes itself to gets renamed, the rule it was written to replace
# gets retracted, a later rule says the opposite. This script re-runs those same five checks against
# every standing rule, adds five STORE-WIDE checks that only make sense over a whole store, and
# reports what it found WITH THE EVIDENCE — never as a bare verdict.
#
# THIS SCRIPT HAS NO WRITE MODE AT ALL. Not "dry-run by default" — dry-run ONLY. It creates no branch,
# no commit, no PR, and it never writes to `.agent/rules/`. That is `harvest-conventions.sh`'s posture
# and the reason is the one that file records: A READ-ONLY ENGINE IS STRICTLY STRONGER THAN AN OPT-IN
# WRITE FLAG — there is no flag here that could be passed by accident, misread from a doc, or reached
# by a future caller that copied an invocation without reading it. Every remedy this script proposes
# is expressed as an EXISTING action a human runs afterwards:
#     /rules add --supersedes <id> ...                          (replace a rule with a corrected one)
#     add-rule.sh --retract --target <id> --reason <text>       (remove a rule outright)
# `add-rule.sh` remains the sole writer. This script proposes; it never authors.
#
# RULES ARE DATA, NEVER EXECUTED (the standing trust boundary, skills/rules/SKILL.md §9). A `check`
# value is arbitrary shell authored by anyone who cloned or PR'd the repo. This script reads `check`
# as a STRING and STATICALLY LINTS IT — is it absent, is it whitespace-only — and there is NO code
# path here that runs, evals, sources, or `bash -c`s a `check`. `rules-check.sh` (human-invoked,
# confirm-gated) stays the SOLE EXECUTOR. `test-audit-rules.sh` proves it with a `check` whose value
# would write a canary file, and asserts the canary never appears.
#
# THE SCHEMA IS FROZEN. This script adds no member to a rule object and writes no sidecar store. Its
# entire output is stdout.
#
# IT REIMPLEMENTS NONE OF THE FIVE SHARED CHECKS. It SOURCES `validate-entry.sh` under the same
# three-clause LOAD GUARD `add-rule.sh` uses (see the LOAD GUARD block below) and calls the five
# functions. A second copy of the correctness logic would drift silently — which is precisely the
# `process` rule this store already holds ("a second copy that drifts silently is the defect").
#
# ---------------------------------------------------------------------------
# THE `--store` SHAPE TRAP, and why the compare corpus below is built the way it is. READ THIS BEFORE
# CHANGING THE CORPUS. `validate_duplicate` / `validate_contradiction` require `--store` shaped as
# ONE LINE PER STORED ENTRY. Handing them a rule file's raw JSON gives them ONE DOCUMENT SPLIT INTO
# LINES, every line smaller than the entry, so no single line can reach the threshold: the loop falls
# out the bottom and the shape guard returns 2 (`REFUSE_DUPLICATE_UNCOMPARABLE_SHAPE` /
# `REFUSE_CONTRADICTION_UNCOMPARABLE_SHAPE`) — "COULD NOT DECIDE". A caller that absorbs rc 2 as rc 0
# audits EVERY rule as a silent false "clean", which is the exact fail-open the validator exists to
# close, reintroduced one layer up. So: the corpus is built one line per rule statement
# (`build_compare_corpus` below — the name and the return-code discipline are `add-orientation.sh`'s
# and `write-agent-memory.sh`'s, deliberately: one precedent, several call sites), and rc 2 from ANY
# shared check is surfaced as UNKNOWN and exits 2. Never as clean.
#
# COULD-NOT-EXAMINE IS NEVER CLEAN, at every layer:
#   . the validator missing / unreadable / truncated / contract-skewed  -> UNEXAMINED, exit 2
#   . jq absent, the store dir unlistable, a rule file unreadable       -> UNEXAMINED, exit 2
#   . rc 2 from any of the three blocking shared checks                 -> UNKNOWN,    exit 2
#   . the repo path list unobtainable (nothing for a glob to match)     -> UNKNOWN,    exit 2
#   . a provenance.added stamp that cannot be ordered                   -> UNKNOWN,    exit 2
# This script is NOT a fail-safe reader — `read-rules.sh` is, and it always exits 0 because a read
# must never break its caller. AN AUDIT THAT CANNOT EXAMINE AND EXITS 0 IS WORSE THAN NO AUDIT, so
# this one takes the opposite posture on purpose.
#
# TWO OF THE FIVE SHARED CHECKS ARE ADVISORY, AND ARE REPORTED AS SUCH. `dead_reference` and
# `cross_repo_reference` were demoted to advisory after SIX consecutive rounds of false refusals over
# free prose (the measurements are in `validate-entry.sh`'s header). An audit inherits that ambiguity
# exactly. So their findings are printed in their own clearly-labelled ADVISORY section, WITH the
# matched text, and are NEVER aggregated into the pass/fail count and NEVER change the exit status.
#
# SMALL N. The live store is tiny. "0 findings" over a handful of rules is a statement about a
# handful of rules, not evidence the store is sound, and this script says so IN ITS OWN OUTPUT rather
# than leaving the caveat in a doc nobody reads next to the number.
#
# Usage:
#   audit-rules.sh [--root <dir>] [--rules-dir <dir>]
#     --root <dir>        repo root paths are resolved against (default: git toplevel, else $PWD)
#     --rules-dir <dir>   the rule store to audit             (default: <root>/.agent/rules)
#   AUDIT_RULES_VALIDATOR=<path>  override the shared validator (used by the suite's degraded-helper
#                                 fixtures; mirrors add-rule.sh's ADD_RULE_VALIDATOR)
#   There is deliberately NO flag that writes anything, and an unknown flag is REFUSED, not ignored.
#
# Exit:
#   0  examined, no blocking / store-wide findings  (advisory findings may still be printed)
#   1  examined, at least one blocking / store-wide finding
#   2  COULD NOT EXAMINE — UNEXAMINED or UNKNOWN. Never reported as clean.

set -uo pipefail   # `set -e` deliberately omitted: this script COLLECTS findings across many checks
                   # and decides an exit status at the end; an early exit on a check's non-zero
                   # verdict would truncate the report at the first finding.

PROG="audit-rules.sh"

# ---------------------------------------------------------------------------
# LOAD GUARD. Copied in SUBSTANCE from add-rule.sh's `_ve_load_validator` — a second implementation
# of the guard would be the same drift this script exists to report. See validate-entry.sh's LOAD
# GUARD CONTRACT. Three clauses, ALL required:
#   (i)   `. validate-entry.sh` must exit 0. `|| true` is FORBIDDEN on that line — discarding the
#         status IS the silent unexamined audit this design does not sanction. The status is CAPTURED
#         instead, and the caller's own errexit state is saved and restored around the source so this
#         block cannot change the shell options the rest of the script runs under.
#   (ii)  ALL SEVEN names must be present — the six in $VALIDATOR_REQUIRED_FUNCS plus the aggregate
#         `validate_entry_all`. NOT five: add-rule.sh's own inline comment says "all five validator
#         functions" and is STALE — its loop is `for _vef in $VALIDATOR_REQUIRED_FUNCS
#         validate_entry_all`, six names plus one. THE CODE IS THE CONTRACT, NOT THE COMMENT. Bash
#         defines every function ABOVE a syntax error before aborting the parse, so a truncated
#         helper leaves SOME validators defined — a one-function probe would report "examined and
#         clean" over half a validator.
#   (iii) $VALIDATE_ENTRY_CONTRACT must equal the HARDCODED literal below. Comparing against a
#         variable the helper exports (VALIDATE_ENTRY_CONTRACT_EXPECTED), or iterating the list it
#         exports ($VALIDATE_ENTRY_FUNCTIONS), would be CIRCULAR: both are assigned ABOVE the
#         sentinel, so a truncated copy could define them and pass its own test.
# Any shortfall is REFUSE_VALIDATOR_UNAVAILABLE, exit 2 (could-not-examine); nothing is reported clean.
# ---------------------------------------------------------------------------
REFUSE_VALIDATOR_UNAVAILABLE="REFUSE_VALIDATOR_UNAVAILABLE"
VALIDATE_ENTRY_CONTRACT_REQUIRED="validate-entry/2"
VALIDATOR_REQUIRED_FUNCS="validate_duplicate validate_contradiction validate_provenance validate_dead_reference validate_cross_repo_reference validate_entry_advisory_notice"

# Resolved BEFORE any `cd`: $0 may be relative and this script cds to the repo root.
VE_HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd || printf '%s' ".")"

_ve_load_validator() {
  VALIDATOR="${AUDIT_RULES_VALIDATOR:-}"
  if [ -z "$VALIDATOR" ]; then
    if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/validate-entry.sh" ]; then
      VALIDATOR="${CLAUDE_PLUGIN_ROOT}/scripts/validate-entry.sh"
    else
      VALIDATOR="$VE_HERE/validate-entry.sh"
    fi
  fi

  # ---- LOAD GUARD BEGIN -----------------------------------------------------
  # BEGIN/END delimit the guard as ONE replaceable unit so this suite's mandated mutation control can
  # replace it with `|| true` in a single edit and prove the UNEXAMINED assertions go RED. Structural,
  # not decorative — and the readability precheck below stays INSIDE the delimiters for exactly that
  # reason: it is part of the same guard, and moving it out would leave a mutant that still fails
  # closed by accident and therefore proves nothing.
  if [ ! -f "$VALIDATOR" ] || [ ! -r "$VALIDATOR" ]; then
    printf '%s: %s — UNEXAMINED: the shared validator is missing or unreadable at "%s", so NO rule in this store was examined. Reporting UNEXAMINED rather than reporting the store clean.\n' \
      "$PROG" "$REFUSE_VALIDATOR_UNAVAILABLE" "$VALIDATOR" >&2
    exit 2
  fi

  # Clause (i). errexit saved/restored rather than assumed. `|| true` here is FORBIDDEN.
  case "$-" in *e*) _ve_had_e=1 ;; *) _ve_had_e=0 ;; esac
  set +e
  # shellcheck source=/dev/null
  . "$VALIDATOR"
  _ve_src_rc=$?
  if [ "$_ve_had_e" -eq 1 ]; then set -e; fi
  if [ "$_ve_src_rc" -ne 0 ]; then
    printf '%s: %s — UNEXAMINED: sourcing the shared validator "%s" failed (status %s: unparseable or truncated), so NO rule in this store was examined. Reporting UNEXAMINED rather than reporting the store clean.\n' \
      "$PROG" "$REFUSE_VALIDATOR_UNAVAILABLE" "$VALIDATOR" "$_ve_src_rc" >&2
    exit 2
  fi

  # Clause (ii). All SIX required names, PLUS the aggregate — never one name as a proxy for the rest.
  for _vef in $VALIDATOR_REQUIRED_FUNCS validate_entry_all; do
    if ! command -v "$_vef" >/dev/null 2>&1; then
      printf '%s: %s — UNEXAMINED: the shared validator loaded but "%s" is not defined (a partially-loaded validator would report "examined and clean" over half a check), so NO rule in this store was examined.\n' \
        "$PROG" "$REFUSE_VALIDATOR_UNAVAILABLE" "$_vef" >&2
      exit 2
    fi
  done

  # Clause (iii). Compared against the HARDCODED literal — see the circularity note above.
  if [ "${VALIDATE_ENTRY_CONTRACT:-}" != "$VALIDATE_ENTRY_CONTRACT_REQUIRED" ]; then
    printf '%s: %s — UNEXAMINED: the shared validator contract sentinel is "%s", not the expected "%s" (the file is truncated, or its contract changed), so NO rule in this store was examined.\n' \
      "$PROG" "$REFUSE_VALIDATOR_UNAVAILABLE" "${VALIDATE_ENTRY_CONTRACT:-<unset>}" "$VALIDATE_ENTRY_CONTRACT_REQUIRED" >&2
    exit 2
  fi
  # ---- LOAD GUARD END -------------------------------------------------------
}

# ---------------------------------------------------------------------------
# Args. READ-ONLY BY CONSTRUCTION: every flag selects WHAT TO READ. An unknown flag is REFUSED rather
# than ignored, so a `--fix` typed by a hopeful caller fails loudly instead of being silently dropped
# into a run that looks like it did something.
# ---------------------------------------------------------------------------
ROOT_ARG=""
RULES_DIR_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root)        ROOT_ARG="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --root=*)      ROOT_ARG="${1#--root=}"; shift ;;
    --rules-dir)   RULES_DIR_ARG="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --rules-dir=*) RULES_DIR_ARG="${1#--rules-dir=}"; shift ;;
    -h|--help)
      awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
      exit 0 ;;
    *)
      printf '%s: unknown option "%s". This script is READ-ONLY and has no write flag; see --help.\n' \
        "$PROG" "$1" >&2
      exit 2 ;;
  esac
done

if [ -n "$ROOT_ARG" ]; then
  ROOT="$(cd "$ROOT_ARG" 2>/dev/null && pwd)"
  [ -n "$ROOT" ] || { printf '%s: UNEXAMINED: --root "%s" is not a usable directory.\n' "$PROG" "$ROOT_ARG" >&2; exit 2; }
else
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
cd "$ROOT" 2>/dev/null || { printf '%s: UNEXAMINED: cannot enter root "%s".\n' "$PROG" "$ROOT" >&2; exit 2; }

RULES_DIR="${RULES_DIR_ARG:-$ROOT/.agent/rules}"

if ! command -v jq >/dev/null 2>&1; then
  printf '%s: UNEXAMINED: jq is unavailable, so the rule store could not be parsed and NO rule was examined. Reporting UNEXAMINED rather than reporting the store clean.\n' "$PROG" >&2
  exit 2
fi

WORK="$(mktemp -d)" || { printf '%s: UNEXAMINED: could not create a work dir.\n' "$PROG" >&2; exit 2; }
trap 'rm -rf "$WORK" 2>/dev/null' EXIT

# US (0x1F) — the intra-cell delimiter for the ROUTE cell, exactly as read-rules.sh uses it. jq
# neutralizes tab/newline/US inside every pattern first, so the split is unambiguous by construction.
US=$'\037'

_ve_load_validator

# ---------------------------------------------------------------------------
# Store enumeration + a byte-identity fingerprint. The fingerprint is taken BEFORE any check runs and
# again AFTER the last one, and the two are compared in the report. This script has no write path at
# all, so the comparison is belt-and-braces — which is the point: the guarantee is ASSERTED FROM THE
# ENGINE'S OWN OUTPUT rather than inferred from the absence of a writer.
# ---------------------------------------------------------------------------
FILES_LIST="$WORK/files"
if [ -e "$RULES_DIR" ] && { [ ! -d "$RULES_DIR" ] || [ ! -r "$RULES_DIR" ] || [ ! -x "$RULES_DIR" ]; }; then
  printf '%s: UNEXAMINED: the rule store "%s" exists but could not be listed, so NO rule was examined.\n' "$PROG" "$RULES_DIR" >&2
  exit 2
fi
LC_ALL=C find "$RULES_DIR" -maxdepth 1 -type f -name '*.json' 2>/dev/null \
  | LC_ALL=C sort > "$FILES_LIST" 2>/dev/null || : > "$FILES_LIST"
[ -f "$FILES_LIST" ] || : > "$FILES_LIST"

# hash_one <file> — a content fingerprint, portable across macOS (shasum) and Linux CI (sha256sum),
# with a POSIX `cksum` last resort. Deliberately NOT `stat`: `stat -f %m` succeeds with GARBAGE on GNU
# coreutils, which would make the fingerprint machine-dependent — the exact class already shipped here.
hash_one() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" 2>/dev/null
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" 2>/dev/null
  else cksum "$1" 2>/dev/null
  fi
}
store_fingerprint() {
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    hash_one "$f"
  done < "$FILES_LIST"
}
FP_BEFORE="$(store_fingerprint)"

# ---------------------------------------------------------------------------
# Parse + validate + resolve supersession. The per-object validation, the LC_ALL=C path-sorted
# first-seen-id-wins dedup, the single-hop non-transitive supersession and the cycle handling are
# read-rules.sh's semantics, REUSED rather than reinterpreted — a second interpretation of "which
# rules are standing" would make this audit disagree with the reader every consumer actually uses.
# INJECTION SAFETY (read-rules.sh's rule, unchanged): untrusted rule text enters jq ONLY because jq
# reads the rule FILE as a positional path argument; the jq program text is fixed and the only
# flag-passed value is the trusted integer file index.
# ---------------------------------------------------------------------------
COMBINED="$WORK/combined"; : > "$COMBINED"
MALFORMED="$WORK/malformed"; : > "$MALFORMED"
n_files=0
unreadable=0
while IFS= read -r rf; do
  [ -n "$rf" ] || continue
  n_files=$((n_files + 1))
  if [ ! -r "$rf" ]; then
    printf '%s: UNEXAMINED: rule file "%s" exists but could not be read — a hole in the store makes a verdict of "clean" meaningless.\n' "$PROG" "$rf" >&2
    unreadable=1
    continue
  fi
  rows="$(jq -c --argjson fi "$n_files" '
    if type == "array" then to_entries | map({fi: $fi, ei: .key, obj: .value}) | .[] else empty end
  ' "$rf" 2>/dev/null)"
  if [ -n "$rows" ]; then
    printf '%s\n' "$rows" >> "$COMBINED"
  elif ! jq -e 'type == "array"' "$rf" >/dev/null 2>&1; then
    printf '%s\n' "$rf" >> "$MALFORMED"
  fi
done < "$FILES_LIST"
if [ "$unreadable" -eq 1 ]; then exit 2; fi

# RECORDS line kinds (tab-delimited; every free-text cell has tabs/newlines neutralized in jq):
#   SKIP\t<why>
#   DANGLE\t<id>\t<target>          supersedes names an id absent from the valid set
#   SELFREF\t<id>                   supersedes names its own id
#   DEAD\t<id>\t<hider>             hidden from the reader by a live rule's supersedes
#   CYCLE\t<id>                     a supersession cycle member; the reader drops its edge
#   RULE\t<id>\t<category>\t<enforcement>\t<check-kind>\t<check-text>\t<route>\t<prov-source>\t<prov-added>\t<file-index>\t<statement>
RECORDS="$WORK/records"; : > "$RECORDS"
if [ -s "$COMBINED" ]; then
  jq -rs '
    # route_spec — read-rules.sh s normalizer, same behaviour: "" for repo-wide AND for every
    # malformed shape (fail OPEN), else the US-joined glob list. jq NEVER matches; the case-glob
    # match lives in the shell below.
    def route_spec($at):
      ( if ($at | type) == "array"
          then ( $at | map( if type == "string" then gsub("[\t\n\u001f]"; "") else null end ) )
          else null
        end ) as $p0
      | ( if $p0 == null then null
          elif ($p0 | any(.[]; . == null)) then null
          else ($p0 | map(select(length > 0)))
          end ) as $p1
      | ( if ($p1 == null) or (($p1 | length) == 0) then "" else ($p1 | join("\u001f")) end );
    def cell: gsub("[\t\n]"; " ");

    sort_by([.fi, .ei])
    | reduce .[] as $row ( {seen: {}, out: []};
        ($row.obj) as $o
        | (
            if ($o | type) != "object" then {tag:"SKIP", why:"not-an-object"}
            elif ($o.id        | type) != "string" then {tag:"SKIP", why:"missing-or-nonstring-id"}
            elif ($o.category  | type) != "string" then {tag:"SKIP", why:("bad-category id=" + (($o.id // "?")|tostring))}
            elif ($o.statement | type) != "string" then {tag:"SKIP", why:("bad-statement id=" + (($o.id // "?")|tostring))}
            elif (($o.enforcement | type) != "string")
                 or (($o.enforcement == "advisory") or ($o.enforcement == "must") | not) then {tag:"SKIP", why:("bad-enforcement id=" + (($o.id // "?")|tostring))}
            elif ($o | has("check") | not) then {tag:"SKIP", why:("missing-check id=" + (($o.id // "?")|tostring))}
            elif (($o.check | type) != "string") and (($o.check) != null) then {tag:"SKIP", why:("bad-check id=" + (($o.id // "?")|tostring))}
            elif ($o.provenance | type) != "object" then {tag:"SKIP", why:("bad-provenance id=" + (($o.id // "?")|tostring))}
            elif (.seen[$o.id] // false) then {tag:"SKIP", why:("duplicate-id " + $o.id)}
            else {tag:"OK", obj:$o, fi:$row.fi}
            end
          ) as $res
        | if $res.tag == "OK" then
            { seen: (.seen + {($res.obj.id): true}),
              out:  (.out + [{kind:"OK", obj:$res.obj, fi:$res.fi}]) }
          else
            { seen: .seen, out: (.out + [{kind:"SKIP", why:$res.why}]) }
          end
      )
    | .out
    | ( [ .[] | select(.kind == "OK") ] ) as $ok_rows
    | ( $ok_rows | map(.obj) ) as $ok_objs
    | ( $ok_objs | map(.id) ) as $ok_ids
    # A hiding EDGE: a non-null STRING supersedes, not self-referential, resolving to another rule
    # that ALSO survived validation. Every other shape is a no-op for the reader — and is reported
    # separately below (DANGLE / SELFREF), which is what makes an inert curation edge VISIBLE.
    | (
        $ok_objs
        | map( . as $o | ($o.supersedes) as $tgt
               | select( ($tgt | type) == "string" )
               | select( $tgt != $o.id )
               | select( ($ok_ids | index($tgt)) != null )
               | {from: $o.id, to: $tgt} )
      ) as $edges
    | ( ( $edges | map({(.from): .to}) | add ) // {} ) as $edge_map
    | ( $edges | map(.from) ) as $edge_from_ids
    | ( $edge_from_ids | length ) as $edge_n
    # Cycle detection generalized to any length: out-degree is <= 1 per node, so a node is a cycle
    # member iff following its OWN edge chain returns to itself within edge_count steps. A single
    # bounded, non-recursive walk per node — it can never loop or hang on a malformed graph.
    | (
        $edge_from_ids
        | map( . as $start
               | ( reduce range(0; $edge_n) as $i ( {cur: $edge_map[$start], hit: false};
                     if .hit or (.cur == null) then .
                     elif .cur == $start then {cur: .cur, hit: true}
                     else {cur: ($edge_map[.cur] // null), hit: false}
                     end ) ) as $walk
               | select($walk.hit) | $start )
      ) as $cycle_members
    | ( $edges | map(select( (.from) as $ef | ($cycle_members | index($ef)) == null )) ) as $edges_live
    | ( $edges_live | map(.to) ) as $hidden_ids
    | (
        [ .[] | select(.kind == "SKIP") | "SKIP\t" + (.why | cell) ]
        + ( $ok_objs
            | map( . as $o | ($o.supersedes) as $tgt
                   | select( ($tgt | type) == "string" )
                   | select( ($tgt | length) > 0 )
                   | select( $tgt != $o.id )
                   | select( ($ok_ids | index($tgt)) == null )
                   | "DANGLE\t" + ($o.id | cell) + "\t" + ($tgt | cell) ) )
        + ( $ok_objs
            | map( . as $o | ($o.supersedes) as $tgt
                   | select( ($tgt | type) == "string" )
                   | select( $tgt == $o.id )
                   | "SELFREF\t" + ($o.id | cell) ) )
        + ( $edges_live | map( "DEAD\t" + (.to | cell) + "\t" + (.from | cell) ) )
        + ( $cycle_members | map( "CYCLE\t" + (. | cell) ) )
        + ( $ok_rows
            | map(select( (.obj.id) as $rid | ($hidden_ids | index($rid)) == null ))
            | sort_by([.obj.category, .obj.id])
            | map( .obj as $o
                   # EVERY cell is prefixed with ":" and NOTHING is emitted empty. Load-bearing, not
                   # decorative: TAB is an IFS *whitespace* character, so `IFS=$'\t' read` FOLDS a run
                   # of tabs into ONE delimiter. An empty `check` cell (the ordinary null-check rule)
                   # or an empty route cell (the ordinary repo-wide rule) would silently shift every
                   # later field left by one and hand `provenance.added` the file index. MEASURED on
                   # the live store before the prefix landed: every rule reported "applies_to glob
                   # matches nothing" quoting its own provenance.source as the glob. read-rules.sh
                   # solves the same hazard by STRIPPING its one optional cell; this line has four
                   # optional cells, so it pads instead. The shell strips one leading ":" per field.
                   | "RULE\t:" + ($o.id | cell)
                   + "\t:" + ($o.category | cell)
                   + "\t:" + ($o.enforcement | cell)
                   + "\t:" + (if ($o.check == null) then "null" else "string" end)
                   + "\t:" + (if ($o.check == null) then "" else ($o.check | cell) end)
                   + "\t:" + route_spec($o.applies_to)
                   + "\t:" + (($o.provenance.source // "") | tostring | cell)
                   + "\t:" + (($o.provenance.added  // "") | tostring | cell)
                   + "\t:" + (.fi | tostring)
                   + "\t:" + ($o.statement | cell) ) )
      )
    | .[]
  ' "$COMBINED" > "$RECORDS" 2>/dev/null
  jq_rc=$?
  if [ "$jq_rc" -ne 0 ]; then
    printf '%s: UNEXAMINED: the store could not be reduced to a rule set (jq status %s), so NO rule was examined.\n' "$PROG" "$jq_rc" >&2
    exit 2
  fi
fi

# ---------------------------------------------------------------------------
# THE COMPARE CORPUS — ONE LINE PER RULE STATEMENT. See "THE `--store` SHAPE TRAP" in the header:
# this shape is what makes `validate_duplicate` / `validate_contradiction` able to DECIDE at all.
# Return codes are the could-not-examine discipline, not a convenience:
#   0 usable (possibly empty: a store with no OTHER rules is a real, clean verdict)
#   2 the corpus could not be staged (never reported as clean — the caller turns it into UNKNOWN)
# <exclude-id> drops the rule being examined, so a rule is never compared against ITSELF (which would
# score 100% and refuse every rule in the store as a duplicate of itself).
# <after-iso>, when non-empty, keeps ONLY rules whose provenance.added is strictly LATER — that is
# the corpus for the "contradicted by a rule added AFTER it" store-wide check.
# ---------------------------------------------------------------------------
build_compare_corpus() {
  local out="$1" exclude="${2:-}" after="${3:-}"
  local kind rid c_cat c_enf c_ckk c_ckv c_route c_src c_added c_fi stmt
  : > "$out" || return 2
  while IFS=$'\t' read -r kind rid c_cat c_enf c_ckk c_ckv c_route c_src c_added c_fi stmt; do
    [ "$kind" = "RULE" ] || continue
    # Strip the ":" pad every RULE cell carries (see the emitter in the jq pass above).
    rid="${rid#:}"; c_added="${c_added#:}"; stmt="${stmt#:}"
    [ -n "$exclude" ] && [ "$rid" = "$exclude" ] && continue
    if [ -n "$after" ]; then
      # Lexicographic comparison is correct HERE AND ONLY HERE: both sides are validated by iso_ok as
      # zero-padded UTC ISO-8601 (`YYYY-MM-DDTHH:MM:SSZ`), a format whose string order IS its
      # chronological order. A row whose stamp did not validate never reaches this branch.
      iso_ok "$c_added" || continue
      [ "$c_added" \> "$after" ] || continue
    fi
    printf '%s\n' "$stmt" >> "$out" || return 2
  done < "$RECORDS"
  return 0
}

# iso_ok <stamp> — is this a UTC ISO-8601 second-resolution stamp we may order lexicographically?
# A `case` glob, deliberately not `date -d` / `date -j`: the GNU and BSD flavours disagree, and a
# date probe that succeeds with garbage on the other platform is how a machine-dependent verdict
# gets shipped (macOS-green != CI-green).
iso_ok() {
  case "${1:-}" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) return 0 ;;
  esac
  return 1
}

# ---------------------------------------------------------------------------
# THE REPO PATH LIST — what an `applies_to` glob is matched against for the "can never fire" check.
# TRACKED FILES ONLY (`git ls-files`): a rule store is COMMITTED, so the population a committed rule
# can meaningfully scope itself to is the committed tree. An on-disk `find` would make the verdict
# depend on which build artefacts and gitignored scratch files happen to be lying around — the
# measured defect that made validate-entry.sh's round-6 dead-reference fix machine-dependent (green
# on the author's working tree, red on every clean checkout). Unobtainable => UNKNOWN, never
# "matches nothing".
# ---------------------------------------------------------------------------
PATHS_FILE="$WORK/paths"
git -C "$ROOT" ls-files 2>/dev/null > "$PATHS_FILE" || : > "$PATHS_FILE"
[ -f "$PATHS_FILE" ] || : > "$PATHS_FILE"
PATHS_OK=1
[ -s "$PATHS_FILE" ] || PATHS_OK=0

# pattern_matches_any <glob> — the SAME native bash `case` glob read-rules.sh's `rule_applies` uses.
# `*` and `**` are equivalent and BOTH cross `/`; this is NOT .gitignore syntax. The pattern is
# expanded UNQUOTED into the case label — that is what makes it a glob rather than a literal.
pattern_matches_any() {
  local pat="$1" p
  [ -n "$pat" ] || return 1
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    # shellcheck disable=SC2254 — $pat is UNQUOTED on purpose: this IS the glob match.
    case "$p" in
      $pat) return 0 ;;
    esac
  done < "$PATHS_FILE"
  return 1
}

# ---------------------------------------------------------------------------
# Findings. Three classes, kept in three files so the report can never blur them:
#   BLOCKING — a definite finding from a fail-closed check. Counted; exit 1.
#   ADVISORY — dead-reference / cross-repo. Reported WITH evidence, NEVER counted, NEVER exit-bearing.
#   UNKNOWN  — could not decide (rc 2, an unobtainable input). Counted separately; exit 2.
# ---------------------------------------------------------------------------
F_BLOCK="$WORK/f.blocking"; : > "$F_BLOCK"; n_block=0
F_ADV="$WORK/f.advisory";   : > "$F_ADV";   n_adv=0
F_UNK="$WORK/f.unknown";    : > "$F_UNK";   n_unk=0

# add_finding <file> <check> <subject> <what> <evidence> [<recommendation>]
# Evidence is REQUIRED and printed verbatim: a finding without its evidence is a claim, and this
# audit re-runs two checks that already produced six rounds of false positives on prose.
add_finding() {
  {
    printf '  [%s] %s\n' "$2" "$3"
    printf '      what: %s\n' "$4"
    printf '      evidence: %s\n' "$5"
    if [ -n "${6:-}" ]; then printf '      recommend: %s\n' "$6"; fi
    printf '\n'
  } >> "$1"
  return 0
}
block() { add_finding "$F_BLOCK" "$@"; n_block=$((n_block + 1)); }
advise() { add_finding "$F_ADV" "$@"; n_adv=$((n_adv + 1)); }
unknown() { add_finding "$F_UNK" "$@"; n_unk=$((n_unk + 1)); }

# first_reason / all_reasons — the validator's OWN message is the evidence, because it is the thing
# carrying the matched text. `grep` is fed a FILE (never a pipe into an early-exit consumer: under
# `set -o pipefail` the producer takes SIGPIPE and the pipeline reports 141 EVEN ON A MATCH).
first_reason() {
  local line
  line="$(grep -m1 -E 'REFUSE_|ADVISORY:' "$1" 2>/dev/null)"
  [ -n "$line" ] || line="(the check reported no detail)"
  printf '%s' "$line"
}
all_reasons() {
  local out
  out="$(grep -E 'ADVISORY:' "$1" 2>/dev/null | sed -e 's/^/        | /')"
  [ -n "$out" ] || out="        | (the check reported no detail)"
  printf '\n%s' "$out"
}

REC_CURATE="replace it with a corrected rule via \`/rules add --supersedes <id> ...\`, or remove it via \`bash \${CLAUDE_PLUGIN_ROOT}/scripts/add-rule.sh --retract --target <id> --reason '<why>' --confirm\`. This audit PROPOSES; add-rule.sh is the sole writer."
REC_UNKNOWN="an UNCOMPARABLE_SHAPE reason means the comparison corpus was not one line per rule; any other reason names its own cause. Do NOT read this as a clean rule — re-run the audit once the named cause is fixed."

# ---------------------------------------------------------------------------
# Store-level defects that the READER SILENTLY SWALLOWS. read-rules.sh is a fail-safe reader: it
# skips a malformed object and exits 0, by design, because a read must never break its caller. That
# design decision means a broken rule is INVISIBLE at every consuming seam. Surfacing it is the whole
# reason an audit exists as a separate program.
# ---------------------------------------------------------------------------
while IFS= read -r mf; do
  [ -n "$mf" ] || continue
  block "store" "file: $mf" \
    "this rule file is malformed or is not a JSON array, so read-rules.sh skips the WHOLE file silently — every rule in it is invisible at every seam" \
    "$(jq -e 'type' "$mf" 2>&1 | head -1 | sed -e 's/^/parse: /')" \
    "fix the file by hand and re-run; the audit never writes."
done < "$MALFORMED"

# ---------------------------------------------------------------------------
# PASS 1 — RE-RUN THE FIVE SHARED CHECKS against every standing rule (AC1), plus the three
# store-wide checks that are per-rule properties (no-mechanism, dead scope, contradicted-by-a-later-rule).
#
# `</dev/null` on every validator call is NOT decoration: this loop's own stdin is the records file,
# and a check that read fd 0 would consume the rules it is being run over.
# ---------------------------------------------------------------------------
n_rules=0; n_must=0; n_dead=0; n_skipped=0
ERR="$WORK/err"
while IFS=$'\t' read -r kind rid r_cat r_enf r_ckk r_ckv r_route r_src r_added r_fi stmt; do
  [ "$kind" = "RULE" ] || continue
  # Strip the ":" pad every RULE cell carries (see the emitter in the jq pass above).
  rid="${rid#:}";   r_cat="${r_cat#:}";     r_enf="${r_enf#:}"; r_ckk="${r_ckk#:}"
  r_ckv="${r_ckv#:}"; r_route="${r_route#:}"; r_src="${r_src#:}"; r_added="${r_added#:}"
  r_fi="${r_fi#:}"; stmt="${stmt#:}"
  n_rules=$((n_rules + 1))
  [ "$r_enf" = "must" ] && n_must=$((n_must + 1))

  CORPUS="$WORK/corpus.$n_rules"
  build_compare_corpus "$CORPUS" "$rid" ""
  corpus_rc=$?
  if [ "$corpus_rc" -ne 0 ]; then
    unknown "corpus" "rule: $rid" \
      "the one-line-per-rule comparison corpus could not be staged (status $corpus_rc), so duplicate and contradiction COULD NOT BE EXAMINED for this rule" \
      "corpus target: $CORPUS" \
      "a hole in the corpus makes a 'clean' duplicate/contradiction verdict meaningless, so it is reported UNKNOWN rather than clean."
  else
    # -- shared check 1: duplicate (BLOCKING) --
    validate_duplicate --entry "$stmt" --store "$CORPUS" </dev/null 2>"$ERR"; rc=$?
    case "$rc" in
      0) : ;;
      1) block "duplicate" "rule: $rid" \
           "near-identical to another standing rule — two copies of one convention drift apart silently" \
           "$(first_reason "$ERR")" "$REC_CURATE" ;;
      *) unknown "duplicate" "rule: $rid" \
           "the duplicate check COULD NOT DECIDE (rc $rc) — UNKNOWN, NOT clean" \
           "$(first_reason "$ERR")" "$REC_UNKNOWN" ;;
    esac

    # -- shared check 2: contradiction, against the whole standing store (BLOCKING) --
    validate_contradiction --entry "$stmt" --store "$CORPUS" </dev/null 2>"$ERR"; rc=$?
    case "$rc" in
      0) : ;;
      1) block "contradiction" "rule: $rid" \
           "about the same subject as another standing rule, but of the opposite polarity" \
           "$(first_reason "$ERR")" "$REC_CURATE" ;;
      *) unknown "contradiction" "rule: $rid" \
           "the contradiction check COULD NOT DECIDE (rc $rc) — UNKNOWN, NOT clean" \
           "$(first_reason "$ERR")" "$REC_UNKNOWN" ;;
    esac
  fi

  # -- shared check 3: provenance (BLOCKING). The rule's own provenance.source is what add-rule.sh
  #    stamped at write time, so this re-asks the write-time question of the record as it stands.
  validate_provenance --entry "$stmt" --source "$r_src" </dev/null 2>"$ERR"; rc=$?
  case "$rc" in
    0) : ;;
    1) block "provenance" "rule: $rid" \
         "cites nothing that motivated it — neither provenance.source nor the statement text carries a real reference" \
         "provenance.source=\"$r_src\" | $(first_reason "$ERR")" "$REC_CURATE" ;;
    *) unknown "provenance" "rule: $rid" \
         "the provenance check COULD NOT DECIDE (rc $rc) — UNKNOWN, NOT clean" \
         "$(first_reason "$ERR")" "$REC_UNKNOWN" ;;
  esac

  # -- shared checks 4 + 5: dead-reference and cross-repo. ADVISORY BY CONSTRUCTION — they always
  #    return 0 and report on stderr. Six rounds of measured false refusals over free prose is why;
  #    see validate-entry.sh's header. Reported here WITH the matched text, never counted, never
  #    exit-bearing. A non-zero status from either is a DEFECT IN THE VALIDATOR, not a finding about
  #    the rule, and is labelled as such rather than converted into a verdict about the store.
  validate_dead_reference --entry "$stmt" --root "$ROOT" </dev/null 2>"$ERR"; rc=$?
  if [ "$rc" -ne 0 ]; then
    advise "dead_reference" "rule: $rid" \
      "the ADVISORY dead-reference check returned status $rc — that is a defect in validate-entry.sh, NOT a finding about this rule" \
      "$(first_reason "$ERR")" "report it against validate-entry.sh; nothing about this rule is implied."
  elif grep -q 'ADVISORY:' "$ERR" 2>/dev/null; then
    advise "dead_reference" "rule: $rid" \
      "ADVISORY ONLY — a path this rule's text cites did not resolve. This check REPORTS and never refuses; it produced false positives in six consecutive review rounds over prose, so read the matched text before acting" \
      "$(all_reasons "$ERR")" \
      "if the citation is genuinely stale, correct the rule via \`/rules add --supersedes <id>\`. If the matched token is prose rather than a path, no action — this is a known false-positive class."
  fi

  validate_cross_repo_reference --entry "$stmt" --root "$ROOT" </dev/null 2>"$ERR"; rc=$?
  if [ "$rc" -ne 0 ]; then
    advise "cross_repo" "rule: $rid" \
      "the ADVISORY cross-repo check returned status $rc — that is a defect in validate-entry.sh, NOT a finding about this rule" \
      "$(first_reason "$ERR")" "report it against validate-entry.sh; nothing about this rule is implied."
  elif grep -q 'ADVISORY:' "$ERR" 2>/dev/null; then
    advise "cross_repo" "rule: $rid" \
      "ADVISORY ONLY — a repo-shaped token in this rule's text is outside this repo's allowlist. Same false-positive history as dead-reference; read the matched text before acting" \
      "$(all_reasons "$ERR")" \
      "if the citation genuinely names another repository, correct the rule via \`/rules add --supersedes <id>\`. If the token is an in-repo path or prose, no action."
  fi

  # -- store-wide 1: an enforcement claim with NO MECHANISM (AC2). A STATIC LINT of the `check`
  #    STRING — the value is read as text and never run. `rules-check.sh` runs only `must` rules
  #    whose check is a NON-NULL STRING, so a `must` rule with a null (or whitespace-only) check is a
  #    rule that CLAIMS enforcement and can never be enforced by anything.
  if [ "$r_enf" = "must" ]; then
    ck_empty=0
    [ "$r_ckk" = "null" ] && ck_empty=1
    if [ "$r_ckk" = "string" ]; then
      case "$r_ckv" in *[![:space:]]*) : ;; *) ck_empty=2 ;; esac
    fi
    if [ "$ck_empty" -eq 1 ]; then
      block "no_mechanism" "rule: $rid" \
        "enforcement is \`must\` but \`check\` is null — rules-check.sh runs ONLY must-rules with a non-null check string, so this rule claims enforcement that nothing can ever apply" \
        "enforcement=must check=null (read as data; NOT executed by this audit)" \
        "$REC_CURATE Add a real \`--check\` to the replacement, or downgrade it to \`--enforcement advisory\`."
    elif [ "$ck_empty" -eq 2 ]; then
      block "no_mechanism" "rule: $rid" \
        "enforcement is \`must\` but \`check\` is a whitespace-only string — a mechanism in name only" \
        "enforcement=must check=\"$r_ckv\" (read as data; NOT executed by this audit)" \
        "$REC_CURATE Add a real \`--check\` to the replacement, or downgrade it to \`--enforcement advisory\`."
    fi
  fi

  # -- store-wide 2: an `applies_to` glob that matches ZERO repo paths (AC3). An empty route cell is
  #    repo-wide (or a fail-OPEN malformed shape) and has nothing to check — read-rules.sh already
  #    emits those everywhere.
  if [ -n "$r_route" ]; then
    if [ "$PATHS_OK" -ne 1 ]; then
      unknown "applies_to" "rule: $rid" \
        "the repo's tracked-path list could not be obtained, so whether this rule's globs match anything COULD NOT BE EXAMINED" \
        "root=$ROOT | \`git ls-files\` produced nothing" \
        "run the audit inside a git checkout with a populated index. Reported UNKNOWN rather than as a rule that matches nothing."
    else
      dead_globs=""; live_globs=0; total_globs=0
      rest="$r_route"
      while [ -n "$rest" ]; do
        case "$rest" in
          *"$US"*) pat="${rest%%"$US"*}"; rest="${rest#*"$US"}" ;;
          *)       pat="$rest";           rest="" ;;
        esac
        [ -n "$pat" ] || continue
        total_globs=$((total_globs + 1))
        if pattern_matches_any "$pat"; then
          live_globs=$((live_globs + 1))
        else
          dead_globs="${dead_globs}${dead_globs:+, }\"$pat\""
        fi
      done
      if [ "$total_globs" -gt 0 ] && [ "$live_globs" -eq 0 ]; then
        block "never_fires" "rule: $rid" \
          "every one of this rule's \`applies_to\` globs matches ZERO tracked repo paths — the rule is standing, valid, and can never be emitted for any file in this repo" \
          "globs matching nothing: $dead_globs (bash \`case\` globs against \`git ls-files\`; \`*\` and \`**\` both cross \`/\` — NOT .gitignore syntax)" \
          "$REC_CURATE Re-scope the replacement with \`--applies-to\`, or omit \`--applies-to\` entirely to make it repo-wide."
      elif [ -n "$dead_globs" ]; then
        block "dead_glob" "rule: $rid" \
          "the rule still fires, but $((total_globs - live_globs)) of its $total_globs \`applies_to\` globs match ZERO tracked repo paths — that part of its declared scope is inert" \
          "globs matching nothing: $dead_globs" \
          "$REC_CURATE Drop or correct the inert globs in the replacement."
      fi
    fi
  fi

  # -- store-wide 5: CONTRADICTED BY A RULE ADDED AFTER IT (the drift case). Direction matters: the
  #    per-rule contradiction check above compares against the WHOLE standing store, which answers
  #    "do two rules disagree". This one answers the over-time question the write-time gate structurally
  #    cannot ask — "did a LATER rule reverse this one without superseding it".
  if iso_ok "$r_added"; then
    LATER="$WORK/later.$n_rules"
    build_compare_corpus "$LATER" "$rid" "$r_added"
    corpus_rc=$?
    if [ "$corpus_rc" -ne 0 ]; then
      unknown "later_contradiction" "rule: $rid" \
        "the later-rules comparison corpus could not be staged (status $corpus_rc), so 'contradicted by a rule added after it' COULD NOT BE EXAMINED" \
        "corpus target: $LATER" "reported UNKNOWN rather than clean."
    elif [ -s "$LATER" ]; then
      validate_contradiction --entry "$stmt" --store "$LATER" </dev/null 2>"$ERR"; rc=$?
      case "$rc" in
        0) : ;;
        1) block "later_contradiction" "rule: $rid" \
             "a rule added AFTER this one says the opposite about the same subject, and did not supersede it — both are standing, and every consumer reads both" \
             "added=$r_added | $(first_reason "$ERR")" \
             "supersede the older rule from the newer one: \`/rules add --supersedes $rid ...\`, or retract one via \`add-rule.sh --retract --target $rid --reason '<why>' --confirm\`." ;;
        *) unknown "later_contradiction" "rule: $rid" \
             "the later-rule contradiction check COULD NOT DECIDE (rc $rc) — UNKNOWN, NOT clean" \
             "$(first_reason "$ERR")" "$REC_UNKNOWN" ;;
      esac
    fi
  else
    unknown "later_contradiction" "rule: $rid" \
      "provenance.added is absent or is not a UTC ISO-8601 second-resolution stamp, so this rule cannot be ORDERED against the others and 'contradicted by a rule added after it' COULD NOT BE EXAMINED" \
      "provenance.added=\"$r_added\" (expected YYYY-MM-DDTHH:MM:SSZ, the shape add-rule.sh stamps)" \
      "reported UNKNOWN rather than clean; an unorderable stamp hides the drift case entirely."
  fi
done < "$RECORDS"

# ---------------------------------------------------------------------------
# PASS 2 — the store-wide checks that are properties of the SUPERSESSION GRAPH plus the objects the
# reader silently drops. Read from the records file the jq pass already produced.
# ---------------------------------------------------------------------------
while IFS=$'\t' read -r kind a b _rest; do
  case "$kind" in
    SKIP)
      n_skipped=$((n_skipped + 1))
      block "skipped_object" "object: $a" \
        "read-rules.sh fail-safe-SKIPS this object and exits 0 by design, so it is invisible at every consuming seam — the store believes it holds a rule that nothing reads" \
        "reader diagnostic: $a" \
        "fix the object by hand and re-run; the audit never writes." ;;
    DANGLE)
      # -- store-wide 3: a dangling `supersedes` target (AC4).
      block "dangling_supersedes" "rule: $a" \
        "its \`supersedes\` names \"$b\", which is not a valid rule in this store — the reader ignores a dangling edge, so the curation the author wrote SILENTLY DID NOTHING" \
        "supersedes=\"$b\" (no valid rule carries that id; a target that exists only as a SKIPped object counts as absent, exactly as read-rules.sh treats it)" \
        "either the target was retracted (the edge is now noise and the rule should be re-authored without it) or the id is a typo. Re-author via \`/rules add --supersedes <correct-id>\` and retract this one via \`add-rule.sh --retract --target $a --reason '<why>' --confirm\`." ;;
    SELFREF)
      block "dangling_supersedes" "rule: $a" \
        "its \`supersedes\` names its OWN id — the reader ignores a self-referential edge, so the curation SILENTLY DID NOTHING" \
        "supersedes == id == \"$a\"" \
        "re-author with the correct target via \`/rules add --supersedes <older-id>\` and retract this one via \`add-rule.sh --retract --target $a --reason '<why>' --confirm\`." ;;
    DEAD)
      # -- store-wide 4: a rule superseded by a later rule (AC5).
      n_dead=$((n_dead + 1))
      block "dead_rule" "rule: $a" \
        "superseded by \"$b\" — it is HIDDEN from read-rules.sh's output, so it is a rule nobody reads that is still committed, still audited, and still looks live to anyone browsing the store" \
        "hidden by supersedes edge: $b -> $a (single-hop, non-transitive, as read-rules.sh resolves it)" \
        "remove the dead object outright: \`bash \${CLAUDE_PLUGIN_ROOT}/scripts/add-rule.sh --retract --target $a --reason 'superseded by $b' --confirm\`. Keeping it changes nothing that is read." ;;
    CYCLE)
      block "supersession_cycle" "rule: $a" \
        "this rule is a member of a \`supersedes\` CYCLE. read-rules.sh drops every edge originating from a cycle member (so nothing is silently hidden), which means this rule's curation edge SILENTLY DID NOTHING" \
        "cycle member id=\"$a\" (the reader's bounded chain walk returned to this id)" \
        "break the cycle: retract one member via \`add-rule.sh --retract --target $a --reason '<why>' --confirm\`, or re-author it without \`--supersedes\`." ;;
  esac
done < "$RECORDS"

FP_AFTER="$(store_fingerprint)"

# ---------------------------------------------------------------------------
# THE REPORT.
# ---------------------------------------------------------------------------
n_objects=0
[ -s "$COMBINED" ] && n_objects="$(wc -l < "$COMBINED" | tr -d '[:space:]')"
[ -n "$n_objects" ] || n_objects=0
n_valid=$((n_rules + n_dead))

printf '# /rules audit — correctness audit over the committed .agent/rules/ store\n\n'
printf 'READ-ONLY: this run wrote NOTHING. It has no write mode and no write flag. `add-rule.sh` is\n'
printf 'the sole writer and `rules-check.sh` the sole executor of a rule `check`; every recommendation\n'
printf 'below names an action a HUMAN runs afterwards, never something this run did.\n\n'

printf '## Store\n\n'
printf -- '- store dir: %s (%s file(s))\n' "$RULES_DIR" "$n_files"
printf -- '- rule objects parsed: %s\n' "$n_objects"
printf -- '- valid rules: %s   (objects skipped by per-object validation: %s)\n' "$n_valid" "$n_skipped"
printf -- '- superseded / hidden from the reader: %s\n' "$n_dead"
printf -- '- STANDING rules audited: %s   (of which `must`: %s)\n' "$n_rules" "$n_must"
printf -- '- rule `check` strings EXECUTED by this audit: 0 — every `check` was read as text and\n'
printf '  statically linted. `rules-check.sh` (human-invoked, confirm-gated) is the sole executor.\n\n'

printf '## Checks run\n\n'
printf -- '- SHARED (re-run from validate-entry.sh, contract `%s`, per standing rule):\n' "$VALIDATE_ENTRY_CONTRACT_REQUIRED"
printf '    duplicate, contradiction, provenance  — BLOCKING (0 pass / 1 finding / 2 could-not-decide)\n'
printf '    dead-reference, cross-repo            — ADVISORY (report only; never counted, never exit-bearing)\n'
printf -- '- STORE-WIDE (this file, over the merged store):\n'
printf '    no_mechanism        a `must` rule whose `check` is null or whitespace-only\n'
printf '    never_fires         an `applies_to` glob set that matches zero tracked repo paths\n'
printf '    dangling_supersedes a `supersedes` naming an id absent from the store (or its own id)\n'
printf '    dead_rule           a rule superseded by a later rule\n'
printf '    later_contradiction a rule contradicted by a rule added AFTER it\n'
printf '    (plus supersession_cycle and skipped_object — defects the fail-safe reader swallows)\n\n'

printf '## Findings — BLOCKING (%s)\n\n' "$n_block"
if [ "$n_block" -gt 0 ]; then cat "$F_BLOCK"; else printf '  none\n\n'; fi

printf '## Findings — ADVISORY (%s)\n\n' "$n_adv"
printf 'dead-reference and cross-repo REPORT, they never refuse, and they are NOT aggregated into the\n'
printf 'count above or into this run'"'"'s exit status. Both were demoted to advisory after SIX consecutive\n'
printf 'review rounds in which every false refusal came from these two checks scanning free prose. Read\n'
printf 'the matched text before acting on any of them.\n\n'
if [ "$n_adv" -gt 0 ]; then cat "$F_ADV"; else printf '  none\n\n'; fi

printf '## Findings — UNKNOWN / COULD NOT EXAMINE (%s)\n\n' "$n_unk"
printf 'An entry here is NOT a clean rule. It is a check that could not decide — an rc-2 verdict, an\n'
printf 'unobtainable input, an unorderable timestamp. Conflating "could not examine" with "examined and\n'
printf 'clean" is the fail-open class validate-entry.sh exists to close, so it is kept separate here and\n'
printf 'it makes this run exit 2.\n\n'
if [ "$n_unk" -gt 0 ]; then cat "$F_UNK"; else printf '  none\n\n'; fi

printf '## Small-N honesty\n\n'
printf 'This store holds %s standing rule(s), of which %s are `must`.\n' "$n_rules" "$n_must"
if [ "$n_block" -eq 0 ] && [ "$n_unk" -eq 0 ]; then
  printf 'ZERO BLOCKING FINDINGS OVER %s RULE(S) IS A SMALL-N RESULT, NOT EVIDENCE THE STORE IS SOUND.\n' "$n_rules"
  printf 'What this run actually established: the three blocking shared checks and the five store-wide\n'
  printf 'checks found nothing to report in THESE %s rules. It establishes nothing about rules that are\n' "$n_rules"
  printf 'not in the store, nothing about conditions none of these %s rules can exhibit, and nothing\n' "$n_rules"
  printf 'about the two ADVISORY checks, whose clean verdict is explicitly not proof of absence.\n'
else
  printf 'The findings above are drawn from a store of %s rule(s). At this size the ABSENCE of a finding\n' "$n_rules"
  printf 'in any category is a small-N result and is not evidence that category is clean.\n'
fi
printf '\n'

printf '## Store integrity\n\n'
if [ "$FP_BEFORE" = "$FP_AFTER" ]; then
  printf -- '- the store is BYTE-IDENTICAL to how this run found it (content fingerprint taken before the\n'
  printf '  first check and after the last one, and compared). This script has no write path; the\n'
  printf '  comparison is asserted from the run itself rather than inferred from that absence.\n'
else
  printf -- '- !! THE STORE CHANGED DURING THIS RUN. This script cannot write, so something else did —\n'
  printf '  a concurrent writer, or an edit landed mid-run. Every finding above describes a store that\n'
  printf '  no longer exists; re-run it.\n'
fi
printf '\n'

# ---------------------------------------------------------------------------
# Exit. UNKNOWN wins over a blocking finding: "could not examine" is the stronger statement, and
# collapsing it into "found something" would let a caller that only distinguishes 0 from non-zero
# treat an unexamined store as an examined one.
# ---------------------------------------------------------------------------
if [ "$FP_BEFORE" != "$FP_AFTER" ]; then exit 2; fi
if [ "$n_unk" -gt 0 ]; then exit 2; fi
if [ "$n_block" -gt 0 ]; then exit 1; fi
exit 0
