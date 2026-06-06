#!/usr/bin/env bash
# twin-graph.sh — blast-radius graph helper for the System Twin contract store (v14.15.0).
#
# Computes, for a given subsystem, the FULL blast-radius graph from the contract store:
#   - DEPENDS_ON      = that subsystem's own `dependencies` (forward, directional edges)
#   - DEPENDED_ON_BY  = every OTHER verified contract whose `dependencies` list contains <id>
#                       (the REVERSE direction, DERIVED here by scanning all contracts — it is NOT
#                        stored in any contract per the SYSTEM_CONTRACT schema).
#
# .supervisor/twin/ is an ADVISORY artifact store — subordinate to the human-authored CLAUDE.md and
# NEVER an enforcement boundary. This helper is read-only, propose-only, and gates nothing.
#
# PROVENANCE-SAFE READ: this script NEVER `cat`s contract files directly. It shells out to the
# read-side provenance gate `read-system-contract.sh` (same dir) and parses ONLY the verified
# contracts it emits — so an out-of-band poisoned contract file is never counted in the graph.
#
# OUTPUT CONTRACT (STABLE — downstream consumers, e.g. Launch Pad / ST3, parse this verbatim):
#   --subsystem "<id>" mode emits EXACTLY two labeled lines, in this order, ALWAYS both present:
#       DEPENDS_ON: <id> <id> ...
#       DEPENDED_ON_BY: <id> <id> ...
#     Each label is at column 0, followed by ": ", then space-separated subsystem ids (the logical
#     `subsystem:` values, verbatim, NOT sanitized filenames). An EMPTY group is emitted as the bare
#     label with nothing after the colon (e.g. "DEPENDS_ON:") so a consumer can distinguish "no edges"
#     from "error/absent". ids within a group are de-duplicated and sorted for stable output.
#   no-arg mode (nice-to-have) lists every edge, one per line, as:
#       EDGE: <from> -> <to>      (meaning: <from> depends on <to>)
#     followed by a trailing "DONE" line so a consumer can confirm a complete (non-truncated) listing.
#
# FAIL-SAFE: exit 0 ALWAYS for reads (a read must never break its caller). No contract store, no sha
# tool, no read-system-contract.sh output → empty groups (labels still printed), exit 0. jq is NOT
# required for the common YAML case (pure grep/sed/awk parsing).
#
# SCOPE — JSON-bodied contracts are NOT parsed by this no-jq path. write-system-contract.sh stores
# the body verbatim and a body may be JSON; this helper only understands the two YAML `dependencies`
# shapes below. A JSON-bodied contract yields a no-edge contract (it contributes nothing to the
# graph) — so the "BOTH supported YAML shapes" claim is YAML-only and excludes JSON by design.
#
# Usage:  twin-graph.sh --subsystem "<id>"   (blast-radius for one subsystem)
#         twin-graph.sh                       (list all depends-on edges)
# Exit:   always 0.

set -uo pipefail   # `set -e` intentionally omitted — a read must NEVER fail its caller.

HERE="$(cd "$(dirname "$0")" && pwd)"
READ="$HERE/read-system-contract.sh"

SUBSYSTEM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --subsystem)   SUBSYSTEM="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --subsystem=*) SUBSYSTEM="${1#--subsystem=}"; shift ;;
    *) shift ;;
  esac
done

# ---- Acquire ONLY verified contracts via the read-side provenance gate -------
RAW=""
if [ -x "$READ" ] || [ -f "$READ" ]; then
  RAW="$(bash "$READ" 2>/dev/null || true)"
fi

# ---- Parse the gate output into a flat edge table ----------------------------
# The gate emits, per verified contract:
#     ### contract: <sanitized-filename-id>
#     <verbatim body...>   (contains the logical `subsystem:` and `dependencies:` lines)
# We key off the LOGICAL `subsystem:` field from the body (NOT the sanitized header), and extract
# `dependencies` in BOTH supported YAML shapes:
#     inline:     dependencies: [a, b, c]
#     block-list: dependencies:
#                   - a
#                   - b
#
# EDGES is a newline-separated "from<TAB>to" table (from depends on to).
EDGES="$(printf '%s\n' "$RAW" | awk '
  function trim(s){ gsub(/^[ \t]+|[ \t]+$/,"",s); return s }
  function flush_inline(line,   arr,n,i,v) {
    # line is the bracketed content already stripped of "dependencies:" and surrounding [].
    n = split(line, arr, ",")
    for (i=1;i<=n;i++){ v=trim(arr[i]); gsub(/^["'\'']|["'\'']$/,"",v); if(v!="") print cur "\t" v }
  }
  BEGIN{ cur=""; inblock=0 }
  {
    raw=$0
    # detect a new contract boundary: reset any block-list state.
    # Reset BOTH inblock AND cur: a new contract must not inherit the previous contract subsystem
    # id. Without resetting cur, a contract whose dependencies precede its subsystem line, or that
    # omits subsystem entirely, would leak its edges onto the PREVIOUS contract id -- a fabricated
    # false edge. With cur empty a subsystem-less contract contributes ZERO edges, since every
    # print path is guarded by cur!="" already.
    if (raw ~ /^### contract:/){ inblock=0; cur=""; next }

    # logical subsystem line: "subsystem: <id>" (allow leading spaces). Strip inline comments.
    if (raw ~ /^[ \t]*subsystem[ \t]*:/){
      val=raw; sub(/^[ \t]*subsystem[ \t]*:[ \t]*/,"",val); sub(/[ \t]*#.*$/,"",val)
      gsub(/^["'\'']|["'\'']$/,"",val); val=trim(val)
      cur=val; inblock=0; next
    }

    # dependencies line.
    if (raw ~ /^[ \t]*dependencies[ \t]*:/){
      rest=raw; sub(/^[ \t]*dependencies[ \t]*:[ \t]*/,"",rest); sub(/[ \t]*#.*$/,"",rest); rest=trim(rest)
      if (rest ~ /^\[/){
        # inline form: dependencies: [a, b, c]  (possibly empty [])
        gsub(/^\[|\][ \t]*$/,"",rest)
        if (cur!="" && trim(rest)!="") flush_inline(rest)
        inblock=0
      } else if (rest=="") {
        # block-list form begins on following "  - x" lines
        inblock=1
      } else {
        # tolerate a bare single scalar: dependencies: foo
        if (cur!=""){ v=rest; gsub(/^["'\'']|["'\'']$/,"",v); if(trim(v)!="") print cur "\t" trim(v) }
        inblock=0
      }
      next
    }

    # inside a block-list, consume "  - item" lines until a non-list line.
    if (inblock==1){
      if (raw ~ /^[ \t]*-[ \t]*/){
        v=raw; sub(/^[ \t]*-[ \t]*/,"",v); sub(/[ \t]*#.*$/,"",v)
        gsub(/^["'\'']|["'\'']$/,"",v); v=trim(v)
        if (cur!="" && v!="") print cur "\t" v
        next
      } else {
        inblock=0   # block-list ended
      }
    }
  }
')"

# ---- helper: unique + sorted space-joined group from stdin (one id per line) --
join_group() {
  # reads ids on stdin, prints them space-separated, deduped, sorted; empty stdin -> empty string.
  sort -u | grep -v '^[[:space:]]*$' | tr '\n' ' ' | sed -E 's/[[:space:]]+$//'
}

if [ -n "$SUBSYSTEM" ]; then
  depends_on="$(printf '%s\n' "$EDGES" | awk -F'\t' -v s="$SUBSYSTEM" 'NF==2 && $1==s {print $2}' | join_group)"
  depended_on_by="$(printf '%s\n' "$EDGES" | awk -F'\t' -v s="$SUBSYSTEM" 'NF==2 && $2==s {print $1}' | join_group)"
  printf 'DEPENDS_ON: %s\n' "$depends_on" | sed -E 's/ $//'
  printf 'DEPENDED_ON_BY: %s\n' "$depended_on_by" | sed -E 's/ $//'
  exit 0
fi

# no-arg mode: list every edge.
printf '%s\n' "$EDGES" | awk -F'\t' 'NF==2 {print "EDGE: " $1 " -> " $2}' | sort -u
printf 'DONE\n'
exit 0
