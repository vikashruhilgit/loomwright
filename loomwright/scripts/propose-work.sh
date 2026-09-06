#!/usr/bin/env bash
# propose-work.sh - deterministic, ADVISORY reader that turns the already-aggregated
# .supervisor/floor/floor.json ledger into CANDIDATE requirement files under
# .supervisor/requirements/proposed/, each citing the ledger evidence it rests on, for a
# human to promote or delete.
#
# THE CONTRACT (repeated verbatim in the generated proposed/README.md):
#   `.supervisor/requirements/proposed/` is deliberately NOT an `/automate --folder` target;
#   promotion is a human moving a file out of it.
# It is restated HERE, in committed source, on purpose: that README is written at runtime
# into a gitignored directory (`.gitignore` ignores `.supervisor/*`), so a fresh clone would
# otherwise carry no record of the contract at all.
#
# IT PROPOSES; IT NEVER QUEUES. Nothing here enqueues, dispatches, ranks, scores, or merges.
# The human gate sits at dequeue, not at write.
#
# DISCIPLINE (mirrors build-floor.sh, the projector that produces this script's only input):
#   * set -uo pipefail with NO set -e.
#   * a `command -v jq` guard that SKIPS rather than fails.
#   * exit 0 ALWAYS - an advisory reader must never break its caller.
#   * READS EXACTLY ONE LEDGER SURFACE: .supervisor/floor/floor.json. It is not a second
#     parser. If a needed field is missing from floor.json the fix is a change to
#     build-floor.sh in a separate PR - never a raw-surface read here. (superseded_by()
#     additionally reads requirement .md files for dedup only - to compare an evidence-set
#     token against text already written, never as a data surface.)
#   * WRITES ONLY FILES under .supervisor/requirements/proposed/, through guarded_write().
#     mkdir -p additionally creates that directory's missing PARENTS, outside the guard.
#
# EVIDENCE-ONLY: absent evidence is OMITTED, never defaulted (build-floor.sh's rule). A
# ledger entry that carries no `evidence` string is NOT citable, and a candidate that cannot
# cite MIN_CITATIONS distinct entries is NOT WRITTEN. A fabricated count inside a proposal is
# the exact failure this reader exists to reduce, so no number is ever invented to fill a gap.
#
# THRESHOLD, NEVER RANKING. A (class, flow_stage) PAIR is emitted when it crosses
# PAIR_THRESHOLD entries. There is no score, no rank, no priority, no top-N and no ordering
# field anywhere in the output: a view that ranks becomes a view that decides, and deciding
# is the human's half of this loop.
#
# DETERMINISM. No run timestamp reaches any emitted byte. The wall clock is read exactly once
# and only to compute the staleness of the basis. Every collection is sorted before emission
# (see the single marked sorting site in cited_entries()), so output is a function of floor.json's
# CONTENT and not of its serialisation order.
#
# Usage:  propose-work.sh
#   env PROPOSE_FLOOR_JSON=<path>          basis to read (default .supervisor/floor/floor.json)
#       PROPOSE_OUT_DIR=<path>             where proposals are written
#       PROPOSE_REQUIREMENTS_DIR=<path>    root scanned for `## Status: done` supersession
#       PROPOSE_THRESHOLD=<n>              pair emission threshold
#       PROPOSE_MAX_AGE_SECONDS=<n>        staleness threshold
#       PROPOSE_SOURCE_DATE_EPOCH=<n>      pin the staleness "now" (reproducible runs)
# Exit:   0 always.

set -uo pipefail

# ---------------------------------------------------------------------------
# The two stated thresholds, each ONE named variable, both overridable.
# ---------------------------------------------------------------------------
PAIR_THRESHOLD="${PROPOSE_THRESHOLD:-10}"        # entries in a (class, flow_stage) pair
STALE_AFTER_SECONDS="${PROPOSE_MAX_AGE_SECONDS:-86400}"   # 24h
MIN_CITATIONS=3          # a candidate citing fewer distinct entries is not written
MAX_CITATIONS=5          # citation cap; the proposal states the cap and the pair total

case "$PAIR_THRESHOLD" in ''|*[!0-9]*)
  echo "propose-work: PROPOSE_THRESHOLD='$PAIR_THRESHOLD' is not a number - ignoring it, using 10" >&2
  PAIR_THRESHOLD=10 ;;
esac
case "$STALE_AFTER_SECONDS" in ''|*[!0-9]*)
  echo "propose-work: PROPOSE_MAX_AGE_SECONDS='$STALE_AFTER_SECONDS' is not a number - ignoring it, using 86400" >&2
  STALE_AFTER_SECONDS=86400 ;;
esac

GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$GITROOT" 2>/dev/null || true

command -v jq >/dev/null 2>&1 || {
  echo "propose-work: jq required - skipping, nothing proposed" >&2
  exit 0
}

FLOOR="${PROPOSE_FLOOR_JSON:-.supervisor/floor/floor.json}"
OUT_DIR="${PROPOSE_OUT_DIR:-.supervisor/requirements/proposed}"
REQ_DIR="${PROPOSE_REQUIREMENTS_DIR:-.supervisor/requirements}"

[ -f "$FLOOR" ] || {
  echo "propose-work: $FLOOR not found - skipping, nothing proposed" >&2
  exit 0
}

jq -e . "$FLOOR" >/dev/null 2>&1 || {
  echo "propose-work: $FLOOR is not parseable JSON - skipping, nothing proposed" >&2
  exit 0
}

# ---------------------------------------------------------------------------
# Staleness. The basis is the artefact's OWN generated_at_epoch. Per-input mtimes live at
# surfaces.<name>.mtime_epoch - there is NO top-level `inputs` key in floor.json, and an
# implementation that looks for one finds nothing and silently treats every basis as fresh.
# ---------------------------------------------------------------------------
gen_epoch="$(jq -r '.generated_at_epoch // empty' "$FLOOR" 2>/dev/null)"
case "$gen_epoch" in
  ''|*[!0-9]*)
    echo "propose-work: $FLOOR carries no readable generated_at_epoch - skipping, nothing proposed" >&2
    exit 0 ;;
esac

now_epoch="${PROPOSE_SOURCE_DATE_EPOCH:-}"
case "$now_epoch" in ''|*[!0-9]*) now_epoch="$(date -u +%s 2>/dev/null)" ;; esac
case "$now_epoch" in
  ''|*[!0-9]*)
    echo "propose-work: could not read the clock - skipping, nothing proposed" >&2
    exit 0 ;;
esac

age=$(( now_epoch - gen_epoch ))
[ "$age" -lt 0 ] && age=0
if [ "$age" -ge "$STALE_AFTER_SECONDS" ]; then
  echo "propose-work: basis $FLOOR is ${age}s old ($(( age / 3600 ))h) at generated_at_epoch $gen_epoch, over the ${STALE_AFTER_SECONDS}s staleness threshold - proposing nothing" >&2
  exit 0
fi

ENTRIES_PATH='.surfaces.postmortem.detail.entries'
have_entries="$(jq -r "if ($ENTRIES_PATH | type) == \"array\" then \"yes\" else \"no\" end" "$FLOOR" 2>/dev/null)"
if [ "$have_entries" != "yes" ]; then
  echo "propose-work: $FLOOR carries no $ENTRIES_PATH array - skipping, nothing proposed" >&2
  exit 0
fi

total_entries="$(jq -r "$ENTRIES_PATH | length" "$FLOOR" 2>/dev/null)"
case "$total_entries" in ''|*[!0-9]*) total_entries="" ;; esac

# The postmortem surface mtime is REPORTED (it is the age of the underlying ledger) but is
# not the staleness basis. Absent => the line is omitted from the proposal, never defaulted.
pm_mtime="$(jq -r '.surfaces.postmortem.mtime_epoch // empty' "$FLOOR" 2>/dev/null)"
case "$pm_mtime" in *[!0-9]*) pm_mtime="" ;; esac
pm_source="$(jq -r '.surfaces.postmortem.source // empty' "$FLOOR" 2>/dev/null)"

mkdir -p "$OUT_DIR" 2>/dev/null || {
  echo "propose-work: cannot create $OUT_DIR - skipping, nothing proposed" >&2
  exit 0
}
OUT_DIR_ABS="$(cd "$OUT_DIR" 2>/dev/null && pwd)"
[ -n "$OUT_DIR_ABS" ] || {
  echo "propose-work: cannot resolve $OUT_DIR - skipping, nothing proposed" >&2
  exit 0
}

# ---------------------------------------------------------------------------
# guarded_write <plain-file-name> - the SINGLE enforcement point for the blast radius.
#
# Deliberately the ONLY sanitisation in this script. A second, redundant check elsewhere
# (slugging the class name on the way in, say) would make this guard's mutation control
# vacuous - the self-test could delete the guard and nothing would escape, so the test would
# stay green with the mechanism removed. That is this repo's single most-recorded defect
# class, so the defence is concentrated here where deleting it is observable.
#
# Content arrives on stdin.
# ---------------------------------------------------------------------------
guarded_write() {
  name="$1"
  # >>> WRITE-PATH GUARD (the self-test's AC8 mutation control deletes this marked block)
  case "$name" in
    ''|.|..|.*|*/*|*'\'*)
      echo "propose-work: refusing to write '$name' - not a plain file name under $OUT_DIR" >&2
      cat >/dev/null; return 1 ;;
  esac
  # Unreachable defence-in-depth: the case above already rejects any name containing "/",
  # so dirname is always $OUT_DIR_ABS and this cannot fire. Kept deliberately so the guard
  # still holds if that case is ever narrowed. Not load-bearing - do not cite it as the
  # traversal defence; the case above is the defence.
  guard_parent="$(cd "$(dirname "$OUT_DIR_ABS/$name")" 2>/dev/null && pwd)"
  if [ "$guard_parent" != "$OUT_DIR_ABS" ]; then
    echo "propose-work: refusing to write '$name' - resolves outside $OUT_DIR_ABS" >&2
    cat >/dev/null; return 1
  fi
  # <<< END WRITE-PATH GUARD
  { cat > "$OUT_DIR_ABS/$name"; } 2>/dev/null || {
    echo "propose-work: cannot write $OUT_DIR_ABS/$name - skipping this candidate" >&2
    return 1
  }
  return 0
}

# ---------------------------------------------------------------------------
# cited_entries <class> <flow_stage> - the citable entries for a pair, capped, as TSV
# (line, index, round, self_heal_miss, evidence).
#
# "Citable" means the entry actually carries every field a citation quotes. An entry with no
# `evidence` string is dropped rather than cited with a blank - absent evidence is omitted,
# never defaulted.
# ---------------------------------------------------------------------------
cited_entries() {
  jq -r --arg cls "$1" --arg fs "$2" --argjson cap "$MAX_CITATIONS" '
    .surfaces.postmortem.detail.entries
    | map(select((.class? // "") == $cls and (.flow_stage? // "") == $fs))
    | map(select((.evidence? | type) == "string" and (.evidence | length) > 0))
    | map(select((.line? | type) == "number" and (.round? | type) == "number"))
    | sort_by([.line, (.index? // 0)])                      # SORT-BEFORE-EMISSION
    | .[0:$cap]
    | .[]
    | [ (.line|tostring),
        ((.index? // 0)|tostring),
        (.round|tostring),
        (if (.self_heal_miss? // false) then "miss" else "hit" end),
        (.evidence | gsub("[[:cntrl:]]"; " "))
      ] | @tsv
  ' "$FLOOR" 2>/dev/null
}

# ---------------------------------------------------------------------------
# superseded_by <evidence-set-token> - path of the first file whose text already covers this
# evidence set, or empty. Two arms: an existing file in proposed/ (dedup), and any
# requirement file under REQ_DIR carrying `## Status: done` (supersession).
#
# grep is run directly against FILES, never as the right-hand side of a pipe: under
# `pipefail` a `producer | grep -q` returns 141 on a match, which silently inverts the
# result of exactly this kind of check.
# ---------------------------------------------------------------------------
superseded_by() {
  sb_tok="$1"
  for sb_f in "$OUT_DIR_ABS"/*.md; do
    [ -f "$sb_f" ] || continue
    if grep -Fq -- "$sb_tok" "$sb_f" 2>/dev/null; then printf '%s' "$sb_f"; return 0; fi
  done
  # >>> DONE-SUPERSESSION CHECK (the self-test's AC4b mutation control deletes this block)
  if [ -d "$REQ_DIR" ]; then
    sb_list="$(find "$REQ_DIR" -type f -name '*.md' 2>/dev/null | LC_ALL=C sort)"
    while IFS= read -r sb_f; do
      [ -n "$sb_f" ] && [ -f "$sb_f" ] || continue
      grep -Eq '^##[[:space:]]+Status:[[:space:]]*done[[:space:]]*$' "$sb_f" 2>/dev/null || continue
      if grep -Fq -- "$sb_tok" "$sb_f" 2>/dev/null; then printf '%s' "$sb_f"; return 0; fi
    done <<EOF
$sb_list
EOF
  fi
  # <<< END DONE-SUPERSESSION CHECK
  return 1
}

# ---------------------------------------------------------------------------
# The directory contract. Static content, so re-runs stay byte-identical.
# ---------------------------------------------------------------------------
printf '%s\n' \
'# proposed/ - candidate work items, not a queue' \
'' \
'These files are written by `loomwright/scripts/propose-work.sh` from' \
'`.supervisor/floor/floor.json`. Each one states a pattern the ledger already records and' \
'cites the entries it rests on. None of them has been decided on.' \
'' \
'`.supervisor/requirements/proposed/` is deliberately NOT an `/automate --folder` target;' \
'promotion is a human moving a file out of it.' \
'' \
'Nothing in this directory is enqueued, dispatched, or started by anything.' \
'' \
'## Deleting a file here is not a durable dismissal' \
'' \
'Deleting a proposal silences it only until the next run, which recomputes the same' \
'evidence set and writes the same file again. The cited coordinates are the earliest' \
'entries for that pair, so the `evidence-set:` token is stable as the ledger grows.' \
'' \
'To dismiss a candidate permanently, paste its `evidence-set:` line into a requirement' \
'file stamped `## Status: done` anywhere under `.supervisor/requirements/`. The next run' \
'finds that token and suppresses the candidate, naming the file it found it in.' \
| guarded_write "README.md" \
  || echo "propose-work: could not write the directory contract README - continuing" >&2

# ---------------------------------------------------------------------------
# Pairs, threshold-selected. group_by yields a sorted, deterministic enumeration.
# ---------------------------------------------------------------------------
pairs="$(jq -r '
  .surfaces.postmortem.detail.entries
  | map(select((.class? | type) == "string" and (.flow_stage? | type) == "string"))
  | group_by([.class, .flow_stage])
  | map({cls: .[0].class, fs: .[0].flow_stage, n: length})
  | sort_by([.cls, .fs])
  | .[] | [.cls, .fs, (.n|tostring)] | @tsv
' "$FLOOR" 2>/dev/null)"

if [ -z "$pairs" ]; then
  echo "propose-work: no (class, flow_stage) pairs in $FLOOR - nothing proposed" >&2
  exit 0
fi

emitted=0
while IFS="$(printf '\t')" read -r cls fs n; do
  [ -n "${cls:-}" ] && [ -n "${fs:-}" ] || continue
  case "${n:-}" in ''|*[!0-9]*) continue ;; esac

  if [ "$n" -lt "$PAIR_THRESHOLD" ]; then
    echo "propose-work: below threshold ($n < $PAIR_THRESHOLD): $cls/$fs - not proposed" >&2
    continue
  fi

  cites="$(cited_entries "$cls" "$fs")"
  ncites=0
  [ -n "$cites" ] && ncites="$(printf '%s\n' "$cites" | awk 'NF{c++} END{print c+0}')"
  if [ "$ncites" -lt "$MIN_CITATIONS" ]; then
    echo "propose-work: $cls/$fs clears the threshold ($n) but only $ncites of its entries carry citable evidence (minimum $MIN_CITATIONS) - not proposed" >&2
    continue
  fi

  # The evidence-set token: the pair plus the exact ledger coordinates cited, sorted. It is
  # what dedup and supersession match on, and it is human-readable on purpose so a person
  # can hand-write it into a `## Status: done` requirement file to retire a candidate.
  coords="$(printf '%s\n' "$cites" | awk -F'\t' 'NF{printf "%sL%s.%s", (c++?",":""), $1, $2}')"
  token="evidence-set: $cls/$fs@$coords"

  covered_by="$(superseded_by "$token")"
  if [ -n "$covered_by" ]; then
    echo "propose-work: suppressed $cls/$fs - its evidence set is already covered by $covered_by" >&2
    continue
  fi

  class_total="$(jq -r --arg cls "$cls" '
    .surfaces.postmortem.detail.entries
    | map(select((.class? // "") == $cls)) | length' "$FLOOR" 2>/dev/null)"
  case "$class_total" in ''|*[!0-9]*) class_total="" ;; esac

  unknowable_note=""
  if [ "$fs" = "unknowable" ]; then
    unknowable_note='**Read this first: `flow_stage: unknowable` means the flow stage could not be attributed** - the ledger record carried no stage, so these entries name a pattern without naming where in the pipeline it arose. This candidate is therefore not directly actionable as written. Closing the attribution gap is the first thing to decide about it.'
  fi

  {
    printf '# Proposed: %s findings at the %s stage\n\n' "$cls" "$fs"
    printf '%s\n\n' "$token"
    printf -- '- basis: `%s` at `generated_at_epoch: %s`\n' "$FLOOR" "$gen_epoch"
    [ -n "$pm_source" ] && printf -- '- ledger: `%s`\n' "$pm_source"
    [ -n "$pm_mtime" ] && printf -- '- ledger mtime_epoch: %s\n' "$pm_mtime"
    printf -- '- pair entries: %s (emission threshold %s)\n' "$n" "$PAIR_THRESHOLD"
    [ -n "$class_total" ] && printf -- '- entries in class `%s`: %s\n' "$cls" "$class_total"
    [ -n "$total_entries" ] && printf -- '- classified entries in the ledger: %s\n' "$total_entries"
    printf '\n## Problem\n\n'
    [ -n "$unknowable_note" ] && printf '%s\n\n' "$unknowable_note"
    printf 'The ledger holds %s entries classified `%s` attributed to the `%s` flow stage,\n' "$n" "$cls" "$fs"
    printf 'at or over the emission threshold of %s. That is a repeating pattern, not an incident.\n' "$PAIR_THRESHOLD"
    printf 'This file states the pattern; it does not state a fix that has not been verified.\n'
    printf '\n## Goal\n\n'
    printf 'Decide what, if anything, changes so that `%s` findings stop recurring at the\n' "$cls"
    printf '`%s` stage - or record why the pattern is acceptable and delete this file.\n' "$fs"
    printf '\n## Scope\n\n'
    printf -- '- Re-read the cited entries below at their source lines in the ledger.\n'
    printf -- '- Establish whether they share one cause or several.\n'
    printf -- '- Write the change, or the reason not to, somewhere a future session will read it.\n'
    printf '\n## Acceptance criteria\n\n'
    printf -- '- [ ] Each cited entry has been read at its source line.\n'
    printf -- '- [ ] The pattern is named as one cause, several, or a mis-classification.\n'
    printf -- '- [ ] Either a change lands, or this candidate is dismissed durably.\n'
    printf -- '      Deleting this file only silences it until the next run recomputes the same\n'
    printf -- '      evidence set. To dismiss it permanently, paste the `%s`\n' "$token"
    printf -- '      line above into a requirement file stamped `## Status: done`.\n'
    printf '\n## Evidence\n\n'
    printf 'Every line below is a ledger entry read from `%s`\n' "$FLOOR"
    printf '(`generated_at_epoch: %s`). Nothing here is inferred.\n\n' "$gen_epoch"
    printf '%s\n' "$cites" | awk -F'\t' -v cls="$cls" -v fs="$fs" 'NF {
      printf "- class `%s` - flow_stage `%s` - round %s - line %s - index %s - self_heal_miss `%s`\n", cls, fs, $3, $1, $2, $4
      printf "  - evidence: %s\n", $5
    }'
    printf '\nCited %s of the %s entries in this pair (citation cap %s).\n' "$ncites" "$n" "$MAX_CITATIONS"
  } | guarded_write "${cls}--${fs}.md" || continue

  emitted=$(( emitted + 1 ))
  echo "propose-work: proposed $cls/$fs ($n entries, $ncites cited) -> $OUT_DIR/${cls}--${fs}.md" >&2
done <<EOF
$pairs
EOF

echo "propose-work: $emitted candidate(s) written to $OUT_DIR - nothing was queued, and nothing will be until a human moves a file out of it" >&2
exit 0
