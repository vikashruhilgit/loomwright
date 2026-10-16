#!/usr/bin/env bash
# read-token-ledger.sh — fail-SAFE reader/summer for the `token_ledger` JSONL
# events emit-token-ledger.sh writes to `.supervisor/logs/<session_id>.jsonl`.
# NEVER blocks a caller and NEVER hard-errors: an unreadable/missing input
# always prints all-zero sums plus LEDGER_UNREADABLE=1 and exits 0.
#
# Usage:
#   read-token-ledger.sh --session <id>  [--root <checkout>]...
#   read-token-ledger.sh --run-id  <run_id | run-file path> [--root <checkout>]...
#   read-token-ledger.sh --per-item <run-file path | run_id> [--projects-dir <dir>] [--root <checkout>]...
#
# --session / --run-id print exactly ONE line to stdout (--per-item is a
# separate report, described at the end of this header):
#   INPUT=<n> OUTPUT=<n> CACHE_READ=<n> CACHE_CREATE=<n> TOTAL=<n> EVENTS=<n> [LEDGER_UNREADABLE=1]
# where TOTAL = INPUT + OUTPUT + CACHE_READ + CACHE_CREATE.
#
# --session <id>
#   Sums every `token_ledger` event in <root>/.supervisor/logs/<id>.jsonl.
#   A malformed (non-JSON) line is silently skipped, never a hard failure —
#   this reader never trusts the ledger file to be perfectly well-formed.
#
# --run-id <run_id>
#   An `/automate` run id (or a literal path to its run file). Resolves the
#   SET of session ids recorded in the run file's `## Progress` lines — see
#   `automate-loop/SKILL.md` §6 step 2, which appends a
#   `- <ts> session_id <id> (<item>)` line after each item's `/autonomous`
#   run — and sums across the UNION of those sessions' ledgers (i.e. this is
#   the `--session` sum, repeated per resolved id and added together).
#   `<run_id>` may be given bare (resolved to
#   `<root>/.supervisor/automate/<run_id>.md`) or as an existing path.
#
# --root <checkout>   (repeatable — parallel-automate/05, Scope 8)
#   Given more than once, every root is read and the sums are ADDED into the
#   same one line (a root named twice is read once). `--session` reads
#   `<root>/.supervisor/logs/<id>.jsonl` under each root; `--run-id` resolves
#   the run file under each root (a bare id: `<root>/.supervisor/automate/<id>.md`,
#   else — when that root is a lane clone whose `.supervisor/lane.json` names
#   `parent_run_id` = <id> — the lane's own `<lane run_id>.md`; a literal path
#   is one file whose sessions are read under every root) and sums that root's
#   sessions from that root's logs. So the parent total of a `--parallel` run is
#   `--run-id <parent> --root <primary> --root <lane1> …`. A root with nothing
#   readable contributes 0; LEDGER_UNREADABLE=1 only when NO root yielded a
#   readable ledger. With one (or no) --root the behavior is unchanged.
#   Overrides the checkout root `.supervisor/` is resolved under (mirrors
#   `automate-helpers.sh gate-eval`'s `--root`). Default: resolve the MAIN
#   worktree the same way `emit-token-ledger.sh` does (`git worktree list
#   --porcelain`'s first entry), falling back to `$PWD` when git resolution
#   is unavailable — so this reader and the emitter always agree on where
#   `.supervisor/logs/` lives.
#
# HONEST LIMITS (documented, not silently "fixed" by inventing a number):
#   - A `token_ledger` line written when neither the SubagentStop payload nor
#     the agent transcript yielded real usage is a PROXY line (`"proxy":true`, see
#     `emit-token-ledger.sh`'s `usage_present()`), carrying a
#     transcript-byte count instead of `input_tokens`/etc. This reader counts
#     a proxy line in EVENTS but its MISSING usage fields contribute exactly
#     0 to INPUT/OUTPUT/CACHE_READ/CACHE_CREATE/TOTAL — this is "no real
#     usage was ever recorded for that firing", NOT "0 tokens were spent".
#     There is no dollar or token estimate derived from transcript bytes
#     here — the plugin has no price table (see docs/PITFALLS.md).
#   - The ledger only knows what a SubagentStop hook actually saw. It does
#     NOT include the main thread's own tokens, any CI-side (GitHub Actions
#     `claude-review`) spend, or a `--parallel` coordinator's own run; output
#     tokens of a message whose final transcript line is absent are
#     under-counted (parallel-automate/24 F8, emit-token-ledger.sh header).
#     TOTAL includes cache-read tokens.
#   - `--run-id` sums only the sessions the run file NAMED. A session whose
#     `session_id <id>` line was written but whose log file is missing is
#     silently skipped (contributes 0, does not itself set
#     LEDGER_UNREADABLE) — this is a genuine under-count risk if that
#     session legitimately spent tokens; LEDGER_UNREADABLE=1 is reserved for
#     "nothing at all could be read" (missing run file, zero resolved
#     session ids, or every resolved session's log file unreadable).
#
# --per-item <run file>   (automate-speed/03 — a SEPARATE report; the proxy
#   ledger above is never read or mixed in)
#   Prints a markdown table to stdout: one row per item of the run (every
#   `## Queue` item, plus any picked item the Queue does not list), then one
#   `↳` row per phase under it. Every token figure is REAL USAGE read from the
#   Claude Code transcripts' per-message `message.usage`; no dollar figures.
#   * Item scope + wall time: `phase-timing.sh --run <rf> --item <item>
#     --logs-dir <root>/.supervisor/logs` (the sibling script) — its `.item.pick`,
#     `.item.park`, `.item.pick_to_park.seconds`, `.item.autonomous.end` (the
#     `ran /autonomous` line), `.item.owned_drains[]` and `.session_id` are read
#     as-is; the segment rule is NOT re-derived here.
#   * Session resolution (run file -> transcripts): the item's plugin session
#     ids are phase-timing's `.session_id` plus every `session_id <sid> (<item>)`
#     Progress line naming this item. Each <sid> contributes its
#     `<logs>/<sid>.owner` `cc_session_id=` value, every distinct
#     `"cc_session_id"` in `<logs>/<sid>.jsonl`, and <sid> itself (a lane run
#     records the Claude Code id directly); a `run created (session <uuid>)`
#     line adds <uuid>. Transcripts: `<projects>/*/<cc id>.jsonl` (main thread)
#     and `<projects>/*/<cc id>/subagents/agent-*.jsonl` (agent type from the
#     sibling `agent-*.meta.json` `agentType`, last `:` segment).
#     <projects> = --projects-dir, else $LOOMWRIGHT_CC_PROJECTS_DIR, else the
#     Claude Code projects directory under $HOME (PROJECTS_DEFAULT below).
#   * De-duplication: a transcript writes one message several times (and a
#     forked/resumed session copies earlier messages), so usage is counted ONCE
#     per `message.id` across every file read: the line with a non-null
#     `stop_reason` when present, else the per-field MAX — the same rule
#     emit-token-ledger.sh applies.
#   * Figures: context = input + cache_creation + cache_read; output =
#     output_tokens; both shown as total (main thread + subagents) with the
#     main-thread part in brackets; turns = distinct main-thread message ids;
#     peak context = the largest single main-thread message context; subagent
#     tokens are summed by agent type (context/output).
#   * Phases (by message timestamp, half-open windows): `picked` -> `launch-pad
#     saved` (Launch Pad) -> `FINALIZE:` (Build) -> `ran /autonomous`
#     (Phase 4.5, with one sub-row per `Phase 4.5 iter <n>` line, each the END
#     of iteration n) -> one Drain row per `.item.owned_drains[]` entry (a
#     fix-now re-drain is marked) -> `parked` (Decide, from the last drain's
#     end). The model-written lines are matched case-insensitively as a prefix.
#     A span with a missing boundary prints `not recorded`, never 0; no
#     `parked` line ⇒ the item's wall time and Decide print `not recorded` and
#     the item total runs to the last recorded boundary (named in the Window
#     cell). An item parked and then resumed in the same run (a work boundary —
#     launch-pad saved, FINALIZE, iter, `ran /autonomous`, drain end, or the LAST
#     item line of a work kind: a resume `picked`, `session_id`, `ran /autonomous`,
#     `owned drain started` (fix-now re-drains too) — later than
#     phase-timing's `.item.park`, which is the FIRST parked line) runs its token
#     window to the first `parked` line at or after that latest boundary (else to
#     the boundary), named in the Window cell; Wall stays phase-timing's
#     pick_to_park and stderr names `work_after_park`. So every phase window lies
#     inside the item window and no phase row exceeds the item row. A span whose
#     end precedes its start prints `not recorded`; a span holding no usage record
#     prints `no usage in window` in its token cells. Gaps between boundaries
#     belong to no phase, so phase rows need not add up to the item row.
#   * Lanes: with repeated --root, a root whose `.supervisor/lane.json` names
#     this run as `parent_run_id` contributes its lane run file's items (shown
#     as `[L<n>] <item>`), resolved against that lane's own logs. The given run
#     file is read against the first root that is not such a lane. Without the
#     lane root, a Queue item the run did not pick but a sibling lane run file
#     (`<run_id>-L<n>.md` next to the given one) has a `picked` line for prints
#     `picked in lane <run_id>-L<n>` (cost that lane file), never `not picked`.
#   * Fail SAFE: always exits 0. An item whose sessions resolve to no
#     transcript prints a named `no_transcripts` reason on stderr and ONE row
#     with `no transcripts` in every cell (no number, no phase rows) — never a
#     0 that reads as cheap. Likewise `no_usage_in_window`: transcripts were read
#     but none holds a usage record between pick and the item end — ONE row with
#     `no usage in window` in every cell. Other stderr reasons:
#     `run_file_unreadable`, `jq_unavailable`, `phase_timing_unavailable`,
#     `not_picked`, `picked_in_lane`, `tmpdir_unavailable`, `work_after_park`
#     (informational — the row still prints).
#   * Honest limits: the /automate engine's own main-thread tokens count only
#     when its Claude Code session id is resolvable through the chain above; a
#     Claude Code session that wrote into a plugin session log for unrelated
#     work is counted too (the log names it); CI-side spend is never seen.
#
# Authoritative spec: docs/PITFALLS.md "Token ceiling" entry,
# docs/ARCHITECTURE_CONTRACTS.md §"Token ceiling".

set -u

JQ="${LOOMWRIGHT_JQ_BIN:-jq}"

die_usage() {
  echo "usage: read-token-ledger.sh --session <id> | --run-id <run_id> | --per-item <run file> [--projects-dir <dir>] [--root <checkout>]..." >&2
  exit 1
}

MODE=""
ID=""
NL='
'
ROOT=""
ROOTS=""
PROJECTS_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --session) MODE="session"; ID="${2:-}"; shift 2 ;;
    --run-id)  MODE="run-id"; ID="${2:-}"; shift 2 ;;
    --per-item) MODE="per-item"; ID="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --projects-dir) PROJECTS_DIR="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --root)    ROOT="${2:-}"
               case "$NL$ROOTS$NL" in *"$NL$ROOT$NL"*) ;; *) ROOTS="${ROOTS:+$ROOTS$NL}$ROOT" ;; esac
               shift 2 ;;
    -h|--help) die_usage ;;
    *) die_usage ;;
  esac
done

[ -n "$MODE" ] && [ -n "$ID" ] || die_usage

# ---- resolve root (mirrors emit-token-ledger.sh's worktree-safe anchoring) --
if [ -z "$ROOTS" ]; then
  main_root="$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
  if [ -n "$main_root" ] && [ -d "$main_root" ]; then
    top="$(git -C "$main_root" rev-parse --path-format=absolute --show-toplevel 2>/dev/null || true)"
    [ "$top" = "$main_root" ] || main_root=""
  fi
  [ -n "$main_root" ] || main_root="$PWD"
  ROOT="$main_root"
  ROOTS="$ROOT"
fi

LOG_DIR="${ROOT}/.supervisor/logs"

emit_zero() {
  # --per-item has no one-line sum: its fail-SAFE form is a named stderr reason.
  if [ "$MODE" = "per-item" ]; then
    echo "read-token-ledger: per-item: jq_unavailable — no report" >&2
    exit 0
  fi
  echo "INPUT=0 OUTPUT=0 CACHE_READ=0 CACHE_CREATE=0 TOTAL=0 EVENTS=0 LEDGER_UNREADABLE=1"
  exit 0
}

# jq must be present AND functional (a jq on PATH that cannot execute would
# otherwise fall through to a hard failure — probe functionally, not with
# `command -v` alone, same discipline as emit-token-ledger.sh's log-owner probe).
command -v "$JQ" >/dev/null 2>&1 || emit_zero
printf '{}' | "$JQ" -e . >/dev/null 2>&1 || emit_zero

TOTAL_INPUT=0
TOTAL_OUTPUT=0
TOTAL_CACHE_READ=0
TOTAL_CACHE_CREATE=0
TOTAL_EVENTS=0
ANY_READABLE=0

# sum_session_file <path> — on success, adds that file's sums into the
# TOTAL_* accumulators and sets ANY_READABLE=1; returns 1 (no accumulation)
# when the file is missing/unreadable or jq fails to produce a line.
sum_session_file() {
  local f="$1" line
  [ -f "$f" ] && [ -r "$f" ] || return 1
  line="$("$JQ" -R -r -s '
    def numf(x): if (x|type)=="number" then x else 0 end;
    (split("\n")
      | map(select(length>0))
      | map(try fromjson catch empty)
      | map(select(type=="object" and .event=="token_ledger"))
    ) as $ev
    | [ ($ev | map(numf(.input_tokens)) | add // 0),
        ($ev | map(numf(.output_tokens)) | add // 0),
        ($ev | map(numf(.cache_read_input_tokens)) | add // 0),
        ($ev | map(numf(.cache_creation_input_tokens)) | add // 0),
        ($ev | length)
      ]
    | @tsv
  ' "$f" 2>/dev/null)"
  [ -n "$line" ] || return 1
  local i o cr cc ev
  IFS=$'\t' read -r i o cr cc ev <<< "$line"
  case "$i$o$cr$cc$ev" in
    *[!0-9]*) return 1 ;;   # any non-numeric field ⇒ treat the file as unreadable, never miscount
  esac
  TOTAL_INPUT=$((TOTAL_INPUT + i))
  TOTAL_OUTPUT=$((TOTAL_OUTPUT + o))
  TOTAL_CACHE_READ=$((TOTAL_CACHE_READ + cr))
  TOTAL_CACHE_CREATE=$((TOTAL_CACHE_CREATE + cc))
  TOTAL_EVENTS=$((TOTAL_EVENTS + ev))
  ANY_READABLE=1
  return 0
}

print_result() {
  local total=$((TOTAL_INPUT + TOTAL_OUTPUT + TOTAL_CACHE_READ + TOTAL_CACHE_CREATE))
  echo "INPUT=$TOTAL_INPUT OUTPUT=$TOTAL_OUTPUT CACHE_READ=$TOTAL_CACHE_READ CACHE_CREATE=$TOTAL_CACHE_CREATE TOTAL=$total EVENTS=$TOTAL_EVENTS"
}

# lane_run_file <root> <id> — parallel-automate/05: when <root> is a lane clone
# whose lane.json names parent_run_id = <id>, print the lane's own run file path.
lane_run_file() {
  local lj="$1/.supervisor/lane.json" par rid
  [ -f "$lj" ] || return 0
  par="$("$JQ" -r '.parent_run_id // empty | strings' "$lj" 2>/dev/null)"
  rid="$("$JQ" -r '.run_id // empty | strings' "$lj" 2>/dev/null)"
  [ -n "$par" ] && [ "$par" = "$2" ] && [ -n "$rid" ] || return 0
  case "$rid" in */*|.*) return 0 ;; esac
  printf '%s\n' "$1/.supervisor/automate/$rid.md"
}

# ---- --per-item (automate-speed/03) — header "--per-item" block is the spec --
PROJECTS_DEFAULT="$HOME/.claude/projects"

pi_note() { echo "read-token-ledger: per-item: $*" >&2; }

# pi_items <run file> — every Queue item, then any picked item the Queue lacks
# (first-appearance order, a leading ./ dropped).
pi_items() {
  {
    awk '/^## Queue/{q=1;next} /^## /{q=0} q && /^- \[.\] /{sub(/^- \[.\] /,""); print $1}' "$1" 2>/dev/null
    grep -oE '^- [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z picked [^ ]+' "$1" 2>/dev/null | awk '{print $4}'
  } | sed 's#^\./##' | awk 'NF && !seen[$0]++'
}

# pi_lane_of <run file> <item> — the lane run id (<run_id>-L<n>, lowest n first)
# whose run file, next to <run file>, has a `picked <item>` Progress line.
pi_lane_of() {
  local dir rid f b
  dir="$(dirname "$1")"; rid="$(basename "$1" .md)"
  for f in "$dir/$rid"-L*.md; do
    b="$(basename "$f" .md)"
    case "${b#"$rid"-L}" in ''|*[!0-9]*) continue ;; esac
    [ -f "$f" ] && [ -r "$f" ] || continue
    if pi_items_picked "$f" | grep -qxF "$2"; then printf '%s\t%s\n' "${b#"$rid"-L}" "$b"; fi
  done | sort -n | head -1 | cut -f2
}

pi_items_picked() {
  grep -oE '^- [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z picked [^ ]+' "$1" 2>/dev/null | awk '{print $4}' | sed 's#^\./##'
}

# pi_cc_ids <logs dir> <run file> <item> <phase-timing json> — the Claude Code
# session ids the item's plugin sessions resolve to (one per line, sanitized).
pi_cc_ids() {
  local logs="$1" rf="$2" item="$3" ptj="$4" sid sids
  sids="$(
    printf '%s' "$ptj" | "$JQ" -r '.session_id // empty | strings' 2>/dev/null
    # every `session_id <sid> (<item>)` line naming THIS item (a resumed item can have several)
    awk -v it="$item" '{
      i = index($0, "session_id "); if (!i) next
      rest = substr($0, i + 11); n = index(rest, " ("); if (!n) next
      tail = substr(rest, n + 2); sub(/^\.\//, "", tail)
      if (substr(tail, 1, length(it) + 1) == it ")") print substr(rest, 1, n - 1)
    }' "$rf" 2>/dev/null
  )"
  {
    printf '%s' "$ptj" | "$JQ" -r '.cc_session_id // empty | strings' 2>/dev/null
    grep -oE 'run created \(session [A-Za-z0-9_-]+\)' "$rf" 2>/dev/null | sed 's/^run created (session //; s/)$//'
    while IFS= read -r sid; do
      [ -n "$sid" ] || continue
      printf '%s\n' "$sid"
      [ -f "$logs/$sid.owner" ] && sed -n 's/^cc_session_id=//p' "$logs/$sid.owner" 2>/dev/null
      [ -f "$logs/$sid.jsonl" ] && "$JQ" -R -r 'fromjson? | objects | .cc_session_id // empty | strings' "$logs/$sid.jsonl" 2>/dev/null
    done <<< "$sids"
  } | tr -cd 'A-Za-z0-9_\n-' | awk 'NF && !seen[$0]++'
}

# pi_extract <projects dir> <cc ids> <out file> — append one compact usage record
# per transcript line carrying message.usage; prints the transcript-file count.
pi_extract() {
  local projects="$1" ccids="$2" out="$3" cc f at kind n=0
  local had_nullglob=0
  shopt -q nullglob && had_nullglob=1
  shopt -s nullglob
  while IFS= read -r cc; do
    [ -n "$cc" ] || continue
    for f in "$projects"/*/"$cc".jsonl "$projects"/*/"$cc"/subagents/agent-*.jsonl; do
      [ -f "$f" ] && [ -r "$f" ] || continue
      n=$((n + 1))
      case "$f" in
        */subagents/agent-*.jsonl)
          at="$("$JQ" -r '.agentType // empty | strings | split(":") | last' "${f%.jsonl}.meta.json" 2>/dev/null)"
          [ -n "$at" ] || at="(unknown)"
          kind="sub" ;;
        *) at=""; kind="main" ;;
      esac
      "$JQ" -R -c --arg kind "$kind" --arg at "$at" '
        def n(x): if (x|type) == "number" then x else 0 end;
        fromjson? | objects | select(.type == "assistant") | .message as $m
        | select(($m|type) == "object" and ($m.id|type) == "string" and ($m.usage|type) == "object")
        | {id: $m.id, ts: ((.timestamp // "") | tostring | sub("\\.[0-9]+Z$"; "Z")), kind: $kind, at: $at,
           final: ($m.stop_reason != null),
           in: n($m.usage.input_tokens), cc: n($m.usage.cache_creation_input_tokens),
           cr: n($m.usage.cache_read_input_tokens), out: n($m.usage.output_tokens)}
      ' "$f" >> "$out" 2>/dev/null || true
    done
  done <<< "$ccids"
  [ "$had_nullglob" -eq 1 ] || shopt -u nullglob
  printf '%s' "$n"
}

# The per-item renderer. ONE jq program: de-dup by message.id, build the item and
# phase windows from the phase-timing record + Progress lines, sum each window.
PI_JQ='
def ep: if . == null then null else (try (sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) catch null) end;
def secs(a; b): if a == null or b == null then null
  else (a|ep) as $x | (b|ep) as $y | if $x == null or $y == null or $y < $x then null else $y - $x end end;
def fmt(s): if s == null then "not recorded"
  else (s|floor) as $s
  | if $s >= 3600 then "\($s / 3600 | floor)h \(($s % 3600) / 60 | floor)m \($s % 60)s"
    else "\($s / 60 | floor)m \($s % 60)s" end end;
def win(s; e): if s == null or e == null then "not recorded"
  else "\(s[5:10]) \(s[11:19]) → \(if e[0:10] == s[0:10] then e[11:19] else "\(e[5:10]) \(e[11:19])" end)" end;
def ctxof: .in + .cc + .cr;
# (a forked session copies subagent transcripts without their meta.json, so the
# agent type is taken from any copy that has one)
def dedup_by_msg_id: group_by(.id) | map((map(select(.final)) | last) as $f | (map(.ts | select(. != "")) | min) as $t | ((map(.at | select(. != "(unknown)")) | first) // .[0].at) as $a | if $f != null then $f + {ts: $t, at: $a} else .[0] + {ts: $t, at: $a, in: (map(.in) | max), cc: (map(.cc) | max), cr: (map(.cr) | max), out: (map(.out) | max)} end);
($recs | dedup_by_msg_id | map(select((.ts | type) == "string" and .ts != ""))) as $M
| def stats($s; $e):
    [$M[] | select(.ts >= $s and .ts < $e)] as $w
    | ($w | map(select(.kind == "main"))) as $m
    | {n: ($w | length), ctx: ($w | map(ctxof) | add // 0), out: ($w | map(.out) | add // 0),
       mctx: ($m | map(ctxof) | add // 0), mout: ($m | map(.out) | add // 0),
       turns: ($m | map(.id) | unique | length),
       peak: ($m | map(ctxof) | max),
       subs: ($w | map(select(.kind != "main")) | group_by(.at)
              | map({at: .[0].at, ctx: (map(ctxof) | add), out: (map(.out) | add)}) | sort_by(-.ctx, .at))};
  # a window with a missing or inverted boundary is "not recorded"; one that holds no
  # usage record prints "no usage in window" (never a 0 that reads as a cheap phase)
  def row($label; $s; $e; $wall; $wincell):
    if $s == null or $e == null or $e < $s then
      "| \($label) | not recorded | not recorded | not recorded | not recorded | not recorded | not recorded | not recorded |"
    else stats($s; $e) as $x
      | if $x.n == 0 then
          "| \($label) | \($wincell) | \(fmt($wall)) | no usage in window | no usage in window | no usage in window | — | — |"
        else "| \($label) | \($wincell) | \(fmt($wall)) | \($x.ctx) (main \($x.mctx)) | \($x.out) (main \($x.mout)) | \($x.turns) | \($x.peak // "—") | \(if ($x.subs | length) == 0 then "—" else ($x.subs | map("\(.at) \(.ctx)/\(.out)") | join("; ")) end) |"
        end
    end;
  ($pt.item // {}) as $I
  | $I.pick as $pick | $I.park as $park | $I.autonomous.end as $ra
  | ($prog | map(select(.ts >= $pick))) as $after
  | ([$after[] | select(.text | test("^picked ")) | select((.text | capture("^picked (?<p>\\S+)").p | sub("^\\./"; "")) != $item)] | first | .ts // "9999") as $bound
  | ($after | map(select(.ts < $bound))) as $seg
  | ([$seg[] | select(.text | ascii_downcase | test("^launch[- ]?pad:?( brief)? saved"))] | first | .ts) as $lp
  | ([$seg[] | select(.text | ascii_downcase | test("^finalize:")) | select(.ts >= ($lp // $pick)) | select($ra == null or .ts <= $ra)] | first | .ts) as $fin
  | [$seg[] | select(.text | ascii_downcase | test("^phase 4\\.5 iter [0-9]+")) | select(.ts >= ($fin // $pick)) | select($ra == null or .ts <= $ra)
     | {ts, n: (.text | ascii_downcase | capture("^phase 4\\.5 iter (?<n>[0-9]+)").n)}] as $iters
  | ($I.owned_drains // []) as $drains
  | (if ($drains | length) > 0 then ($drains | last | .end) else null end) as $decide_s
  # the latest work boundary the item recorded (every phase row ends at or before it).
  # $lp/$fin/$iters/$ra are each the FIRST such line, so the LAST item line of every
  # work kind in the segment is a boundary too — a resume re-pick, its session_id
  # line, a second `ran /autonomous`, a drain or fix-now re-drain start (with or
  # without a recorded end): any of them after the first park means the item worked
  # past it, and none may leave that usage outside the item window silently
  | ([[$lp, "launch-pad saved"], [$fin, "FINALIZE"], ($iters | last | if . == null then [null, ""] else [.ts, "Phase 4.5 iter \(.n)"] end), [$ra, "ran /autonomous"], ($drains | map([.end, "drain \(.result // "end")"]) | .[]),
      ([$seg[] | select(.ts > $pick) | (.text | ascii_downcase) as $t
        | (if ($t | test("^picked ")) then "resume pick"
           elif ($t | test("^session_id ")) then "session_id line"
           elif ($t | test("^ran /autonomous")) then "ran /autonomous"
           elif ($t | test("^owned drain started")) then "drain start"
           elif ($t | test("^launch[- ]?pad:?( brief)? saved")) then "launch-pad saved"
           elif ($t | test("^finalize:")) then "FINALIZE"
           elif ($t | test("^phase 4\\.5 iter [0-9]+")) then "Phase 4.5 iter"
           else null end) as $k
        | select($k != null) | [.ts, $k]] | last // [null, ""])]
     | map(select(.[0] != null)) | sort_by(.[0]) | last) as $l
  # phase-timing.sh `.item.park` is the FIRST parked line; an item parked and then
  # resumed in the same run did work after it, so its token window runs past that park
  # to the first parked line at or after the latest work boundary (else to that boundary)
  | ($park != null and $l != null and $l[0] > $park) as $resumed
  | (if $resumed then ([$seg[] | select(.text | ascii_downcase | test("^parked( |$)")) | select(.ts >= $l[0])] | first | .ts) else $park end) as $park_eff
  | (if $park == null then
       (if $l == null then {e: null, note: ""} else {e: $l[0], note: " (no parked line — to \($l[1]))"} end)
     elif $resumed then
       (if $park_eff != null then {e: $park_eff, note: " (resumed after park — to the later parked line; wall is pick → first park)"}
        else {e: $l[0], note: " (resumed after park — to \($l[1]); wall is pick → first park)"} end)
     else {e: $park, note: ""} end) as $iend
  # transcripts were read but none holds a usage record inside the item window: ONE
  # sentinel line (the caller prints the named reason and a no-number row)
  | if $pick != null and $iend.e != null and $iend.e >= $pick and stats($pick; $iend.e).n == 0 then
      "NO_USAGE_IN_WINDOW\t\($pick)\t\($iend.e)"
    else
    # (the caller turns this sentinel into the named work_after_park stderr reason)
    (if $resumed then "WORK_AFTER_PARK\t\($park)\t\($iend.e)" else empty end),
    row("**\($label)**"; $pick; $iend.e; $I.pick_to_park.seconds; (win($pick; $iend.e) + $iend.note)),
    row("↳ Launch Pad"; $pick; $lp; secs($pick; $lp); win($pick; $lp)),
    row("↳ Build"; $lp; $fin; secs($lp; $fin); win($lp; $fin)),
    row("↳ Phase 4.5"; $fin; $ra; secs($fin; $ra); win($fin; $ra)),
    (range(0; $iters | length) as $k
      | (if $k == 0 then $fin else $iters[$k - 1].ts end) as $s
      | row("↳ ↳ iter \($iters[$k].n)"; $s; $iters[$k].ts; secs($s; $iters[$k].ts); win($s; $iters[$k].ts))),
    (if ($iters | length) > 0 and $ra != null and ($ra > ($iters | last | .ts)) then
       ($iters | last | .ts) as $s
       | row("↳ ↳ after iter \($iters | last | .n) (no iter line)"; $s; $ra; secs($s; $ra); win($s; $ra))
     else empty end),
    (range(0; $drains | length) as $k | $drains[$k] as $d
      | row("↳ Drain \($k + 1)\(if $d.fix_now then " (fix-now re-drain)" else "" end)\(if $d.result then " — \($d.result)" else "" end)"; $d.start; $d.end; $d.seconds; win($d.start; $d.end))),
    row("↳ Decide"; $decide_s; $park_eff; secs($decide_s; $park_eff); win($decide_s; $park_eff))
    end
'

per_item_report() {
  local rf="$ID" run_id pt projects tmp pairs="" first_plain="" r lrf lane lane_items="" line
  pt="$(dirname "$0")/phase-timing.sh"
  projects="${PROJECTS_DIR:-${LOOMWRIGHT_CC_PROJECTS_DIR:-$PROJECTS_DEFAULT}}"
  if [ ! -f "$rf" ]; then
    r="$(printf '%s\n' "$ROOTS" | head -1)"
    [ -f "$r/.supervisor/automate/$ID.md" ] && rf="$r/.supervisor/automate/$ID.md"
  fi
  if [ ! -f "$rf" ] || [ ! -r "$rf" ]; then
    pi_note "run_file_unreadable — $ID"
    return 0
  fi
  run_id="$(basename "$rf" .md)"
  tmp="$(mktemp -d 2>/dev/null)" || { pi_note "tmpdir_unavailable — no report"; return 0; }

  # (root, run file, lane label) pairs: the given run file against the first
  # root that is not a lane of this run; each lane root's own lane run file.
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    lrf="$(lane_run_file "$r" "$run_id")"
    if [ -n "$lrf" ]; then
      [ -f "$lrf" ] || continue
      lane="$("$JQ" -r '.lane // empty | strings' "$r/.supervisor/lane.json" 2>/dev/null)"
      pairs="${pairs}${r}	${lrf}	${lane:-lane}${NL}"
      lane_items="${lane_items}$(pi_items "$lrf")${NL}"
    elif [ -z "$first_plain" ]; then
      first_plain="$r"
    fi
  done <<< "$ROOTS"
  [ -n "$first_plain" ] || first_plain="$(printf '%s\n' "$ROOTS" | head -1)"
  pairs="${first_plain}	${rf}	${NL}${pairs}"

  echo "**Run \`$run_id\`** — per-item cost. Every token figure is **real usage** (\`message.usage\` from Claude Code transcripts, each message counted once by \`message.id\`); context = input + cache_creation + cache_read; no dollar figures; the proxy ledger is not mixed in."
  echo
  echo "| Item / phase | Window (UTC) | Wall | Context tokens (real usage) | Output tokens (real usage) | Turns (main) | Peak context (real usage, main) | Subagent tokens by type (real usage, context/output) |"
  echo "|---|---|---|---|---|---|---|---|"
  local sess_notes="" root prf label item ptj ccids nfiles prog recs disp rendered nu_s nu_e inlane
  while IFS='	' read -r root prf lane; do
    [ -n "$root" ] && [ -n "$prf" ] || continue
    prog="$tmp/prog.json"
    "$JQ" -R -c 'capture("^- (?<ts>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z) (?<text>.*)$")?' "$prf" 2>/dev/null > "$prog" || : > "$prog"
    while IFS= read -r item; do
      [ -n "$item" ] || continue
      if [ -n "$lane" ]; then disp="[$lane] $item"; else disp="$item"; fi
      ptj=""
      [ -f "$pt" ] && ptj="$(bash "$pt" --run "$prf" --item "$item" --logs-dir "$root/.supervisor/logs" 2>/dev/null)"
      if ! printf '%s' "$ptj" | "$JQ" -e '.kind == "item"' >/dev/null 2>&1; then
        pi_note "phase_timing_unavailable — $disp"
        echo "| **$disp** | not recorded | not recorded | not recorded | not recorded | not recorded | not recorded | not recorded |"
        continue
      fi
      if [ "$(printf '%s' "$ptj" | "$JQ" -r '.item.pick // empty')" = "" ]; then
        # an unpicked Queue item the lanes picked is reported under its lane row only
        if [ -z "$lane" ] && grep -qxF "$item" <<<"$lane_items"; then continue; fi
        # a parallel wave's parent: the item was picked by a lane whose run file sits
        # next to this one as <run_id>-L<n>.md (costed there, never "not picked" here)
        inlane=""
        [ -z "$lane" ] && inlane="$(pi_lane_of "$prf" "$item")"
        if [ -n "$inlane" ]; then
          pi_note "picked_in_lane — $disp ($inlane)"
          echo "| **$disp** | picked in lane $inlane | not recorded | see lane run $inlane | see lane run $inlane | see lane run $inlane | see lane run $inlane | see lane run $inlane |"
          continue
        fi
        pi_note "not_picked — $disp"
        echo "| **$disp** | not picked | not recorded | not picked | not picked | not picked | not picked | not picked |"
        continue
      fi
      ccids="$(pi_cc_ids "$root/.supervisor/logs" "$prf" "$item" "$ptj")"
      recs="$tmp/recs.jsonl"; : > "$recs"
      nfiles="$(pi_extract "$projects" "$ccids" "$recs")"
      if [ "${nfiles:-0}" -eq 0 ]; then
        # no transcript at all: a named reason and a row with NO number (a 0
        # would read as a cheap item, a wall time as a costed one)
        if [ -n "$ccids" ]; then
          pi_note "no_transcripts — $disp (session ids tried: $(printf '%s' "$ccids" | tr '\n' ' ' | sed 's/ $//'); none has a transcript under $projects)"
        else
          pi_note "no_transcripts — $disp (no session id recorded for the item: no session_id line, owner file or run-created session)"
        fi
        echo "| **$disp** | no transcripts | no transcripts | no transcripts | no transcripts | no transcripts | no transcripts | no transcripts |"
      else
        rendered="$("$JQ" -r -n --argjson pt "$ptj" --slurpfile prog "$prog" --slurpfile recs "$recs" \
          --arg item "$item" --arg label "$disp" "$PI_JQ" 2>/dev/null)" \
          || rendered="| **$disp** | not recorded | not recorded | not recorded | not recorded | not recorded | not recorded | not recorded |"
        case "$rendered" in
          NO_USAGE_IN_WINDOW*)
            # transcripts exist but hold no usage record inside pick -> end: the same
            # no-number treatment as no_transcripts (a 0 would read as a cheap item)
            IFS='	' read -r _ nu_s nu_e <<< "$rendered"
            pi_note "no_usage_in_window — $disp (${nfiles} transcript file(s) read; no assistant message.usage between $nu_s and $nu_e)"
            echo "| **$disp** | no usage in window | no usage in window | no usage in window | no usage in window | no usage in window | no usage in window | no usage in window |" ;;
          WORK_AFTER_PARK*)
            IFS='	' read -r _ nu_s nu_e <<< "${rendered%%"$NL"*}"
            pi_note "work_after_park — $disp (worked after its first parked line $nu_s; token window runs to $nu_e)"
            printf '%s\n' "${rendered#*"$NL"}" ;;
          *) [ -z "$rendered" ] || printf '%s\n' "$rendered" ;;
        esac
      fi
      sess_notes="${sess_notes}- \`$disp\`: session ids tried $(printf '%s' "$ccids" | awk 'NF{printf "%s%s", (n++ ? ", " : ""), $0}') — ${nfiles:-0} transcript file(s)${NL}"
    done < <(pi_items "$prf")
  done <<< "$pairs"
  if [ -n "$sess_notes" ]; then
    echo
    printf '%s' "$sess_notes"
  fi
  rm -rf "$tmp" 2>/dev/null
  return 0
}

if [ "$MODE" = "per-item" ]; then
  per_item_report
  exit 0
fi

while IFS= read -r ROOT; do
  [ -n "$ROOT" ] || continue
  LOG_DIR="${ROOT}/.supervisor/logs"
  case "$MODE" in
    session)
      sum_session_file "${LOG_DIR}/${ID}.jsonl" || true
      ;;
    run-id)
      RUNFILE=""
      if [ -f "$ID" ]; then
        RUNFILE="$ID"
      elif [ -f "${ROOT}/.supervisor/automate/${ID}.md" ]; then
        RUNFILE="${ROOT}/.supervisor/automate/${ID}.md"
      else
        RUNFILE="$(lane_run_file "$ROOT" "$ID")"
        [ -f "$RUNFILE" ] || RUNFILE=""
      fi
      [ -n "$RUNFILE" ] && [ -r "$RUNFILE" ] || continue
      SESSIONS="$(grep -oE 'session_id [A-Za-z0-9_-]+' "$RUNFILE" 2>/dev/null | awk '{print $2}' | env LC_ALL=C sort -u || true)"
      [ -n "$SESSIONS" ] || continue
      while IFS= read -r sid; do
        [ -n "$sid" ] || continue
        sum_session_file "${LOG_DIR}/${sid}.jsonl" || true
      done <<< "$SESSIONS"
      ;;
  esac
done <<< "$ROOTS"

if [ "$ANY_READABLE" -eq 1 ]; then
  print_result
else
  emit_zero
fi

exit 0
