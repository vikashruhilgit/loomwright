#!/usr/bin/env bash
# read-product.sh — fail-safe ADVISORY reader for the committed `.agent/product.json` product-context
# store (what this project IS, who it SERVES, who it COMPETES with).
# Parity with the existing read-*.sh advisory-reader family; the `command -v jq` skip-not-fail guard
# follows read-rules.sh / read-postmortem.sh, the two readers that carry it. Pure-READ, NO side
# effects, NO network, NEVER writes the store.
#
# The store's SCHEMA AUTHORITY is `docs/RESULT_SCHEMAS.md` §"PRODUCT_CONTEXT"; this reader conforms to
# it, never the reverse. The store itself is created per-project by the bootstrap (`propose-product.sh`),
# never by this reader.
#
# STORED FIELDS (all top-level keys of a single JSON OBJECT):
#   domain        (string)   what this project is, in the terms its own market uses.
#   stance        (string)   EXACTLY "product" or "tool" — load-bearing, see STANCE below.
#   audience      (string)   who it serves, and whether that is evidence-backed or assumed.
#   competitors   (array)    each {name, url, last_fetched}. See LAST_FETCHED below.
#   written_at    (string)   ISO-8601 UTC — provenance.
#   head_sha      (string)   the commit the store was written against — provenance.
#                            (`written_at` + `head_sha` mirror the `.agent/orientation/` memo header
#                            provenance pair, so staleness is measurable against churn rather than
#                            guessed from elapsed time.)
#
# EMITTED-BUT-NOT-STORED: `stance_default_action` (see STANCE). It is a reader OUTPUT only — it is
# NEVER a key in the JSON, and the bootstrap must never write it.
#
# STANCE — the derived `stance_default_action`, and why it is a lookup rather than a constant:
#   `stance` decides what the DEFAULT ACTION on a discovered gap should be, and hard-coding either
#   default would make a downstream lane carry ONE fixed policy regardless of the project (telling a
#   payments app to skip its missing fraud checks because parity is a NO for a tool). So the output is
#   a FUNCTION OF PROJECT DATA: a TWO-ENTRY LOOKUP keyed on the stored `stance` —
#       product => build-highest-priority
#       tool    => do-not-build-by-default
#   That mapping lives in EXACTLY ONE named place in this script: the jq `def STANCE_ACTIONS` below.
#   A consumer reads `stance_default_action` from this reader (or the mapping from RESULT_SCHEMAS.md);
#   it must NOT re-derive it. When `stance` is ABSENT (or not a string, or not one of the two enum
#   values) the reader emits `stance_default_action: unset` and substitutes NEITHER value — it never
#   guesses. This reader only REPORTS the default; nothing here acts on it.
#
# LAST_FETCHED IS NULLABLE-REQUIRED — the distinction this reader exists to preserve:
#   Each competitor's `last_fetched` key is REQUIRED and its value MAY be `null`, meaning NEVER
#   FETCHED. Those are two different facts and are rendered differently:
#       key present, value null      -> "never fetched"      (a legitimate, complete record)
#       key ABSENT                   -> "unset (key missing)" (an INCOMPLETE record + a stderr warning)
#   Presence is therefore asserted with jq `has("last_fetched")`, NEVER with `.last_fetched // empty`
#   or any other `//` default — a `//` default silently collapses a legitimate `null` into the
#   missing-key case and the two become indistinguishable. (This exact defect shipped once before in
#   read-rules.sh's `check` field and was missed by both a review and a full-marks rubric.) A null
#   `last_fetched` is NEVER rendered as a date and NEVER as "stale" — unknown is not old.
#
# FAIL-SAFE (hard requirement): ALWAYS exit 0 — a read must never break its caller. In each of the
# three degraded cases the reader emits NOTHING ON STDOUT, names the reason ON STDERR, and exits 0:
#   - store absent            -> stderr diagnostic, no stdout, exit 0
#   - store malformed         -> stderr diagnostic, no stdout, exit 0   (unparseable JSON, or a root
#                                that is not a JSON object)
#   - jq unavailable          -> stderr diagnostic, no stdout, exit 0
# Note the family precedent is SPLIT on this (read-postmortem.sh writes to stderr at its jq guard but
# is silent on an absent corpus); this reader deliberately names the reason in ALL THREE cases.
# "Emits nothing" here always means ON STDOUT — never "no stderr". A partial/odd store (an unknown
# stance, a non-array `competitors`, a missing scalar) is demote-never-crash: the unusable part
# degrades to `unset` with a stderr warning and everything else is still emitted.
#
# ABSENCE IS NOT THIS READER'S TO ANNOUNCE. The reader is advisory and must not break or spam its
# caller, so an absent store produces no user-facing output here. It is the CONSUMER SEAM (the agent
# prose that asks for product context) that must say, loudly, that the store is missing and name the
# bootstrap. Do not "helpfully" move that message into this reader.
#
# INJECTION SAFETY (jq-only): untrusted store text (domain/audience/competitor names and urls) enters
# jq ONLY because jq reads the store as a POSITIONAL FILE-PATH argument. It is NEVER string-
# interpolated into a shell command or into a jq program, the jq program text is fixed, and no value
# read from the store is ever executed, eval'd, sourced or bash -c'd. Tabs/newlines/CRs inside any
# value are neutralized so a value can never break the reader's own line framing.
#
# INPUT CONTRACT (no-hang): this reader NEVER reads its own stdin. The only inputs are the optional
# flags below, so a caller whose stdin is an open-but-idle pipe (a hook or an agent in a non-TTY
# context) can never hang it.
#
# Usage:  read-product.sh [--store <file>] [--repo <dir>]
#         defaults: repo = cwd git root (fallback: pwd); store = <repo>/.agent/product.json
#         env overrides (for tests): PRODUCT_STORE / PRODUCT_REPO_DIR
#         precedence: flags > env > defaults. Unknown args are ignored (fail-safe).
#         The explicit store override exists so tests can point the reader at a FIXTURE without ever
#         touching the real repo's .agent/.
# Exit:   always 0; diagnostics go to stderr (and, best-effort, .supervisor/logs/memory.log).

set -uo pipefail   # `set -e` intentionally omitted — a read must NEVER fail its caller.

# ---------------------------------------------------------------------------
# 1. Resolve repo + store (flags > env > defaults). Arg parsing is fail-safe: a flag missing its
#    value, or an unknown arg, is ignored — never an error. (Mirrors read-orientation.sh.)
# ---------------------------------------------------------------------------
store_arg=""
repo_arg=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --store) if [ "$#" -ge 2 ]; then store_arg="$2"; shift 2; else shift; fi ;;
    --repo)  if [ "$#" -ge 2 ]; then repo_arg="$2";  shift 2; else shift; fi ;;
    *)       shift ;;
  esac
done

REPO_DIR="${repo_arg:-${PRODUCT_REPO_DIR:-}}"
if [ -z "$REPO_DIR" ]; then
  REPO_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
STORE="${store_arg:-${PRODUCT_STORE:-}}"
[ -n "$STORE" ] || STORE="$REPO_DIR/.agent/product.json"

LOG="$REPO_DIR/.supervisor/logs/memory.log"

# diag() — the ONE diagnostic channel: stderr (contractual, per AC2) plus a best-effort append to
# memory.log (never stdout). The log write is entirely optional; it can never fail the reader, and the
# log directory is only created when there is actually something to say.
diag() {
  echo "$1" >&2
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" "$1" >> "$LOG" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# 2. Tooling presence (fail-safe). jq is REQUIRED (parsing + the injection-safe boundary); when it is
#    absent the reader says so on stderr and emits nothing. Mirrors read-rules.sh / read-postmortem.sh.
# ---------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  diag "read-product: jq unavailable — product context unreadable, emitting nothing (fail-safe)"
  exit 0
fi

# ---------------------------------------------------------------------------
# 3. Store presence (fail-safe). Absent store => named on stderr, nothing on stdout, exit 0.
# ---------------------------------------------------------------------------
if [ ! -f "$STORE" ]; then
  diag "read-product: no product context store at $STORE — emitting nothing (fail-safe)"
  exit 0
fi

# ---------------------------------------------------------------------------
# 4. Render in ONE jq pass. jq emits prefixed lines the shell partitions:
#      OUT\t...        -> stdout (the advisory block)
#      WARN\t...       -> stderr + log (a degraded field; the rest is still emitted)
#      MALFORMED\t...  -> stderr + log, and NOTHING reaches stdout (the whole store is unusable)
#    Nothing is written to stdout until the whole render has been produced and checked for
#    MALFORMED, so a store that turns out to be unusable can never emit a partial block.
# ---------------------------------------------------------------------------
render="$(mktemp 2>/dev/null)" || {
  diag "read-product: could not allocate a temp file — emitting nothing (fail-safe)"
  exit 0
}
trap 'rm -f "$render" 2>/dev/null' EXIT

JQ_PROG='
  # Neutralize tab/newline/CR inside any rendered value so a value can never break line framing.
  def clean: tostring | gsub("[\t\n\r]"; " ");

  # ==========================================================================================
  # THE STANCE MAPPING — the SINGLE named place (see "STANCE" in this script s header docstring).
  # A consumer reads `stance_default_action` from this reader s output, or reads this mapping from
  # docs/RESULT_SCHEMAS.md §PRODUCT_CONTEXT. It must NOT re-derive the mapping, and this reader must
  # never hard-code either action outside this two-entry object.
  # ==========================================================================================
  def STANCE_ACTIONS: {"product": "build-highest-priority", "tool": "do-not-build-by-default"};

  def BANNER: "## Product context — advisory, subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)";

  # field($o; $k) — render one required STRING scalar. Presence is asserted with has(), so an absent
  # key and an explicit null are distinguished and BOTH are warned about (they degrade to the same
  # `unset` render, but for different, separately-named reasons).
  def field($o; $k):
    if ($o | has($k) | not) then
      [ "WARN\tread-product: required key `" + $k + "` is absent — emitting `" + $k + ": unset`",
        "OUT\t- " + $k + ": unset" ]
    elif ($o[$k] == null) then
      [ "WARN\tread-product: `" + $k + "` is null — emitting `" + $k + ": unset`",
        "OUT\t- " + $k + ": unset" ]
    elif (($o[$k] | type) != "string") then
      [ "WARN\tread-product: `" + $k + "` is a " + ($o[$k] | type) + ", expected a string — emitting `" + $k + ": unset`",
        "OUT\t- " + $k + ": unset" ]
    elif (($o[$k] | length) == 0) then
      [ "WARN\tread-product: `" + $k + "` is empty — emitting `" + $k + ": unset`",
        "OUT\t- " + $k + ": unset" ]
    else
      [ "OUT\t- " + $k + ": " + ($o[$k] | clean) ]
    end;

  # competitor_string($c; $k) — a competitor s `name` / `url`: degrade to "unset", never guess.
  def competitor_string($c; $k):
    if ($c | has($k)) and (($c[$k] | type) == "string") and (($c[$k] | length) > 0)
      then ($c[$k] | clean)
      else "unset"
    end;

  . as $o
  | if ($o | type) != "object" then
      [ "MALFORMED\tread-product: store root is a " + ($o | type) + ", not a JSON object — emitting nothing (fail-safe)" ]
    else
      # ---- stance + the DERIVED stance_default_action -------------------------------------------
      ( if ($o | has("stance") | not) then
          { v: "unset", a: "unset",
            w: "read-product: `stance` is absent — emitting `stance: unset` and `stance_default_action: unset` (no default substituted)" }
        elif (($o.stance | type) != "string") then
          { v: "unset", a: "unset",
            w: ("read-product: `stance` is a " + ($o.stance | type) + ", expected the string \"product\" or \"tool\" — emitting `unset` for both (no default substituted)") }
        elif (STANCE_ACTIONS | has($o.stance)) then
          { v: ($o.stance | clean), a: (STANCE_ACTIONS[$o.stance]) }
        else
          { v: ($o.stance | clean), a: "unset",
            w: ("read-product: unrecognized stance `" + ($o.stance | clean) + "` — not one of \"product\" / \"tool\"; emitting `stance_default_action: unset` (no default substituted)") }
        end
      ) as $st

      # ---- competitors[] ------------------------------------------------------------------------
      | ( if ($o | has("competitors") | not) then
            { rows: [], w: [ "read-product: `competitors` is absent — emitting `competitors: none recorded`" ] }
          elif (($o.competitors | type) != "array") then
            { rows: [], w: [ ("read-product: `competitors` is a " + ($o.competitors | type) + ", expected an array — emitting `competitors: none recorded`") ] }
          else
            ( $o.competitors
              | to_entries
              | map(
                  .key as $i
                  | .value as $c
                  | if ($c | type) != "object" then
                      { row: null,
                        w: ("read-product: competitors[" + ($i | tostring) + "] is a " + ($c | type) + ", expected an object — entry skipped") }
                    else
                      # `last_fetched` is NULLABLE-REQUIRED. has() distinguishes an explicit null
                      # (a complete record meaning NEVER FETCHED) from an absent key (an INCOMPLETE
                      # record). A `//` default here would silently collapse the two — do not add one.
                      ( if ($c | has("last_fetched") | not) then
                          { v: "unset (key missing)",
                            w: ("read-product: competitors[" + ($i | tostring) + "] is missing the required `last_fetched` key — emitting `unset (key missing)`, which is NOT the same as never fetched") }
                        elif ($c.last_fetched == null) then
                          { v: "never fetched" }
                        elif (($c.last_fetched | type) == "string") and (($c.last_fetched | length) > 0) then
                          { v: ($c.last_fetched | clean) }
                        else
                          { v: "unset (malformed)",
                            w: ("read-product: competitors[" + ($i | tostring) + "] has a malformed `last_fetched` (a " + ($c.last_fetched | type) + ") — emitting `unset (malformed)`") }
                        end
                      ) as $lf
                      | { row: ( "  - name: " + competitor_string($c; "name")
                                 + " | url: " + competitor_string($c; "url")
                                 + " | last_fetched: " + $lf.v ),
                          w: ( if ($lf | has("w")) then $lf.w else null end ) }
                    end
                )
            ) as $ents
            | { rows: [ $ents[] | select(.row != null) | .row ],
                w:    [ $ents[] | .w | select(. != null) ] }
          end
        ) as $comp

      # ---- assemble -----------------------------------------------------------------------------
      | [ "OUT\t" + BANNER ]
        + field($o; "domain")
        + ( if ($st | has("w")) then [ "WARN\t" + $st.w ] else [] end )
        + [ "OUT\t- stance: " + $st.v,
            "OUT\t- stance_default_action: " + $st.a ]
        + field($o; "audience")
        + ( $comp.w | map("WARN\t" + .) )
        + ( if (($comp.rows | length) == 0)
              then [ "OUT\t- competitors: none recorded" ]
              else [ "OUT\t- competitors:" ] + ($comp.rows | map("OUT\t" + .))
            end )
        + field($o; "written_at")
        + field($o; "head_sha")
    end
  | .[]
'

if ! jq -r "$JQ_PROG" "$STORE" > "$render" 2>/dev/null; then
  diag "read-product: $STORE is not parseable JSON — emitting nothing (fail-safe)"
  exit 0
fi

if [ ! -s "$render" ]; then
  diag "read-product: $STORE produced no readable product context — emitting nothing (fail-safe)"
  exit 0
fi

# 4a. First pass — MALFORMED short-circuit. A store whose ROOT is not a JSON object is unusable as a
#     whole: report every MALFORMED line on stderr and emit NOTHING on stdout.
malformed=0
while IFS= read -r line; do
  case "$line" in
    MALFORMED$'\t'*) malformed=1 ;;
  esac
done < "$render"
if [ "$malformed" -eq 1 ]; then
  while IFS= read -r line; do
    case "$line" in
      MALFORMED$'\t'*) diag "${line#MALFORMED$'\t'}" ;;
    esac
  done < "$render"
  exit 0
fi

# 4b. Second pass — emit. OUT lines go to stdout (the advisory block, in jq's emission order); WARN
#     lines name a degraded field on stderr. Machine consumers can gate on NON-EMPTY stdout.
while IFS= read -r line; do
  case "$line" in
    OUT$'\t'*)  printf '%s\n' "${line#OUT$'\t'}" ;;
    WARN$'\t'*) diag "${line#WARN$'\t'}" ;;
  esac
done < "$render"

exit 0
