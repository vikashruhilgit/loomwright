#!/usr/bin/env bash
# propose-from-verify.sh - the VERIFY basis of `/propose`: turns the FAIL criteria of one Selvedge
# run folder's `verdict.json` into CANDIDATE requirement files under
# `.supervisor/requirements/proposed/`, each citing the criterion it rests on, for a human to
# promote or delete.
#
# WHY THIS EXISTS. A verification run that finds a failing acceptance criterion has no consumer
# unless something turns the FAIL into a piece of work. This is the third `/propose` basis
# (alongside the ledger basis `propose-work.sh` and the domain basis `propose-domain.sh`) and that
# consumer.
#
# THE CONTRACT (identical to the other bases):
#   `.supervisor/requirements/proposed/` is deliberately NOT an `/automate --folder` target;
#   promotion is a human moving a file out of it. IT PROPOSES; IT NEVER QUEUES. Nothing here
#   enqueues, dispatches, ranks, scores or merges.
#
# READS EXACTLY ONE SURFACE: `<run_dir>/verdict.json`, as DATA, with `jq` only. Not
# `criteria.json`, not `plan.json`, not `evidence.jsonl`. This script sources nothing and runs
# nothing from the verifier that wrote the file (no CLI call, no JavaScript runtime): the only
# coupling is the file's documented shape at `SUPPORTED_SCHEMA_VERSION` (below). Fields read:
#   top level   `schema_version` (must equal SUPPORTED_SCHEMA_VERSION), `plan_sha256` (64 hex),
#               `criteria` (object keyed `c-<12 hex>`)
#   per criterion `verdict` (PASS|FAIL|BLOCKED|NOT_VERIFIABLE), `expected` ({op,value} or null),
#               `failed_step` (non-negative int or null), `interpretation` (string or null),
#               `steps[]` ({step,type,...} - each entry carries its own `step` index)
#   The run id is the run folder's basename.
# WRITES ONLY under the output directory, through the shared `pc_guarded_write()` in
# `propose-common.sh` (sourced, never copied inline - every `/propose` basis sources the same file;
# see propose-common.sh's own header for how each caller's mutation control stays live).
#
# ONE DRAFT PER FAIL CRITERION. PASS, BLOCKED and NOT_VERIFIABLE never produce a draft: BLOCKED and
# NOT_VERIFIABLE are the run's problem, not the app's. The failed step is found by its own `step`
# index (`select(.step == $failed_step)`), never by array position - `steps[]` order is not a
# promise that position == index.
#
# IDEMPOTENT ON (run_id, criterion_id). The filename is DERIVED, never counted:
# `verify-<run_id>-<criterion_id>.md`. The body carries no timestamp and criteria are visited in
# sorted key order, so re-running against an unchanged run folder recomputes the identical file
# with identical content and `pc_guarded_write` overwrites it byte for byte - no duplicate.
#
# UNTRUSTED TEXT. `interpretation` and an `expected.value` string are run output, not instructions.
# Control characters are collapsed to one space and every such value is printed after a fixed
# prefix on one line, so no value can open a heading (e.g. a second `## Status:` line) in the
# draft. `interpretation` also feeds `## Touches` through `vt_touches` (stat-style tests only).
#
# EXIT CONTRACT. A human-invoked `/propose` basis (no hook and no script calls it). `set -uo
# pipefail`, no `set -e`. The WHOLE `verdict.json` is validated before the first write - including
# the output directory's `mkdir -p` - so an unusable input leaves nothing behind:
#   0  the file was usable: every FAIL criterion was drafted (zero FAIL criteria ⇒ zero drafts)
#   1  the file was usable but at least one draft was refused by `pc_guarded_write` (its reason is
#      on stderr); the other drafts were still written, each one whole (temp file + `mv -f`)
#   2  unusable input or environment, NOTHING written, one stderr line naming the case:
#      jq_missing | run_dir_missing | verdict_missing | verdict_malformed | unknown_schema_version
#      | propose_common_missing | out_dir_unwritable
#
# Usage:  propose-from-verify.sh <run_dir>
#   env PROPOSE_FROM_VERIFY_OUT_DIR=<path>   where candidates are written
#                                            (default .supervisor/requirements/proposed)
# Exit:   0 drafted; 1 a draft write was refused; 2 refused, nothing written.

set -uo pipefail

SELF="propose-from-verify"
SUPPORTED_SCHEMA_VERSION=1
say() { echo "$SELF: $1" >&2; }
# refuse <reason> <detail> - the one-line refusal; nothing has been written when it is called.
# The detail is flattened to one line (a run-dir path may carry a newline) with builtins only, so
# the jq_missing refusal holds even on a PATH with no external tools at all.
refuse() {
  local d="${2//$'\n'/ }"
  say "$1 - ${d//$'\r'/ }; nothing proposed"
  exit 2
}

command -v jq >/dev/null 2>&1 || refuse jq_missing "jq is required to read verdict.json"

RUN_DIR="${1:-}"
[ -n "$RUN_DIR" ] || refuse run_dir_missing "usage: propose-from-verify.sh <run_dir>"
[ -d "$RUN_DIR" ] || refuse run_dir_missing "no such run dir '$RUN_DIR'"
RUN_DIR_ABS="$(cd "$RUN_DIR" 2>/dev/null && pwd)"
[ -n "$RUN_DIR_ABS" ] || refuse run_dir_missing "cannot resolve '$RUN_DIR'"
RUN_ID="$(basename "$RUN_DIR_ABS")"

VERDICT="$RUN_DIR_ABS/verdict.json"
[ -f "$VERDICT" ] || refuse verdict_missing "no verdict.json under $RUN_DIR_ABS"

# Whole-file validation, BEFORE any write. Prints `ok` or `<reason>\t<detail>`. `-s` slurps, so a
# file holding two JSON values (or none) is refused as malformed rather than half-read. Every field
# this script reads is required to be PRESENT with the right type - a missing nullable key is not
# silently read as null.
VCHECK="$(jq -rs --argjson sv "$SUPPORTED_SCHEMA_VERSION" '
  def nat: type == "number" and . == floor and . >= 0;
  def oneof(a): . as $v | any(a[]; . == $v);
  def bad(m): "verdict_malformed\t" + m;
  def crit_err:
    .key as $k | .value as $c
    | if ($k | test("^c-[0-9a-f]{12}$")) | not then bad("criterion key \($k | tojson) is not c-<12 hex>")
      elif ($c | type) != "object" then bad("criterion \($k) is not an object")
      elif ($c | has("verdict")) | not then bad("criterion \($k) has no verdict")
      elif ($c.verdict | oneof(["PASS", "FAIL", "BLOCKED", "NOT_VERIFIABLE"])) | not then bad("criterion \($k) verdict \($c.verdict | tojson) is not PASS|FAIL|BLOCKED|NOT_VERIFIABLE")
      elif ($c | has("expected") and has("failed_step") and has("interpretation") and has("steps")) | not then bad("criterion \($k) lacks expected / failed_step / interpretation / steps")
      elif ($c.expected != null) and (($c.expected | type) != "object"
             or ($c.expected.op | oneof(["equals", "contains", "matches", "gt", "lt", "changed_from"])) | not
             or ($c.expected.value | type | oneof(["string", "number", "boolean"])) | not)
        then bad("criterion \($k) expected is neither null nor {op,value}")
      elif ($c.failed_step != null) and (($c.failed_step | nat) | not) then bad("criterion \($k) failed_step is neither null nor a non-negative integer")
      elif ($c.interpretation != null) and (($c.interpretation | type) != "string") then bad("criterion \($k) interpretation is neither null nor a string")
      elif ($c.steps | type) != "array" then bad("criterion \($k) steps is not an array")
      elif any($c.steps[]; (type != "object") or ((.step | nat) | not) or ((.type | type) != "string")) then bad("criterion \($k) has a step without an integer step and a string type")
      else empty end;
  if length != 1 or (.[0] | type) != "object" then bad("not exactly one JSON object")
  else .[0]
    | if has("schema_version") | not then bad("no schema_version")
      elif .schema_version != $sv then "unknown_schema_version\tschema_version \(.schema_version | tojson), this reader supports \($sv)"
      elif (.plan_sha256 | type) != "string" or ((.plan_sha256 | test("^[0-9a-f]{64}$")) | not) then bad("plan_sha256 missing or not 64 lowercase hex")
      elif (.criteria | type) != "object" then bad("criteria missing or not an object")
      else (first(.criteria | to_entries[] | crit_err) // "ok")
      end
  end
' "$VERDICT" 2>/dev/null)" || VCHECK=""
TAB="$(printf '\t')"
[ -n "$VCHECK" ] || VCHECK="verdict_malformed${TAB}not valid JSON"
if [ "$VCHECK" != "ok" ]; then
  refuse "${VCHECK%%"$TAB"*}" "${VCHECK#*"$TAB"} in $VERDICT"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
# PROPOSE_COMMON_SH overrides the sibling path - a test-only knob (see propose-common.sh's own
# header) that lets a mutation control point this script's sourcing at a mutated COPY of
# propose-common.sh without touching this script's own text. Unset in every real run.
COMMON="${PROPOSE_COMMON_SH:-$SCRIPT_DIR/propose-common.sh}"
[ -f "$COMMON" ] || refuse propose_common_missing "sibling propose-common.sh not found at $COMMON"
# shellcheck disable=SC1090
. "$COMMON"

# The planner's machine-read sections (parallel-automate/10): every draft carries `## Depends on`
# (`none`) and `## Touches` — the repo-relative FILE paths its interpretation text names, else
# `unknown`; lint-clean under `automate-helpers.sh plan-waves --lint`. The text is untrusted
# evidence: it is only split on characters outside the Touches grammar and each token is passed to
# stat-style tests under the checkout root (`cd -P` / `[ -L ]` / `[ -f ]`) — never opened, executed
# or interpolated. A token must contain `/` or `.`, and carry no leading `/`, trailing `/`, `//`, or
# `.`/`..` segment. It must then pass the CONTAINMENT rule: its first segment is not `.git` (any
# case); its parent directory, physically resolved (`cd -P … && pwd -P`, bash 3.2 / BSD safe — no
# realpath / readlink -f), is the resolved root or strictly under it and not in its `.git` dir; and
# its final component is a regular file that is NOT itself a symlink. So a committed symlink can
# never turn the existence test into a probe of a path outside the checkout (an in-repo symlinked
# DIRECTORY resolving inside the root is accepted as written; a symlinked FILE is always rejected).
# Grammar copy 3 of 3, sharing no code: the authority is the PW_TOUCHES_GRAMMAR line in
# automate-helpers.d/plan-waves.sh (_pw_touches); copy 2 is PATH_TOK / BAD_SEG beside touches_of in
# automate-dismissed.sh. Change all three together — test-automate-helpers.sh §X7 fails on drift.
# Containment is an EXTRACTOR-only rule shared with touches_of (the planner's --lint judges grammar,
# never the filesystem), so X7 does not cover it; test-propose-from-verify.sh and
# test-automate-dismissed.sh each pin it with the same symlink / `.git` fixtures.
VT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
vt_touches() {
  local vt_rp
  vt_rp="$(cd -P -- "$VT_ROOT" 2>/dev/null && pwd -P)" || return 0
  [ -n "$vt_rp" ] || return 0
  printf '%s\n' "$1" | env LC_ALL=C tr -c 'A-Za-z0-9._/@+-' '\n' | sed 's/\.*$//' | env LC_ALL=C sort -u \
    | while IFS= read -r t; do
        case "$t" in ""|/*|*/|*//*) continue ;; esac
        case "$t" in */*|*.*) ;; *) continue ;; esac
        case "/$t/" in */./*|*/../*) continue ;; esac
        case "$t" in [.][Gg][Ii][Tt]|[.][Gg][Ii][Tt]/*) continue ;; esac
        case "$t" in */*) d="$VT_ROOT/${t%/*}" ;; *) d="$VT_ROOT" ;; esac
        dp="$(cd -P -- "$d" 2>/dev/null && pwd -P)" || continue
        case "$dp/" in "$vt_rp"/*) ;; *) continue ;; esac
        case "${dp#"$vt_rp"}/" in /[.][Gg][Ii][Tt]/*) continue ;; esac
        f="$dp/${t##*/}"
        [ -L "$f" ] && continue
        if [ -f "$f" ]; then printf '%s\n' "$t"; fi
      done
}

# One compact JSON record per FAIL criterion, in sorted criterion-id order. Every untrusted string
# is flattened to one line here (control characters -> one space); `expected.value` is rendered
# with `tojson`, so a string value stays quoted and unambiguous.
RECORDS="$(jq -c '
  def flat: gsub("[[:cntrl:]]+"; " ");
  .plan_sha256 as $plan
  | .criteria | to_entries | sort_by(.key)[]
  | select(.value.verdict == "FAIL")
  | .value.failed_step as $failed_step
  | {id: .key, plan: $plan,
     interp: (if .value.interpretation == null then "" else (.value.interpretation | flat) end),
     expected: (if .value.expected == null then "none"
                else "\(.value.expected.op) \(.value.expected.value | tojson | flat)" end),
     fstep: (if $failed_step == null then "none"
             else ([.value.steps[] | select(.step == $failed_step)] | first) as $s
               | if $s == null then "\($failed_step) (type: not in steps[])"
                 else "\($failed_step) (type: \($s.type | flat))" end
             end)}
' "$VERDICT" 2>/dev/null)" || refuse verdict_malformed "could not extract the FAIL criteria from $VERDICT"

if [ -z "$RECORDS" ]; then
  say "no FAIL criterion in $VERDICT - nothing to propose (PASS / BLOCKED / NOT_VERIFIABLE are never drafted)"
  exit 0
fi

OUT_DIR="${PROPOSE_FROM_VERIFY_OUT_DIR:-.supervisor/requirements/proposed}"
mkdir -p "$OUT_DIR" 2>/dev/null || refuse out_dir_unwritable "cannot create $OUT_DIR"
OUT_DIR_ABS="$(cd "$OUT_DIR" 2>/dev/null && pwd)"
[ -n "$OUT_DIR_ABS" ] || refuse out_dir_unwritable "cannot resolve $OUT_DIR"

emitted=0
refused=0
while IFS= read -r rec; do
  [ -n "$rec" ] || continue
  cid="$(printf '%s' "$rec" | jq -r '.id')"
  plan="$(printf '%s' "$rec" | jq -r '.plan')"
  interp="$(printf '%s' "$rec" | jq -r '.interp')"
  expected="$(printf '%s' "$rec" | jq -r '.expected')"
  fstep="$(printf '%s' "$rec" | jq -r '.fstep')"
  touches="$(vt_touches "$interp")"
  fname="verify-${RUN_ID}-${cid}.md"
  if {
      printf '# Proposed: verify FAIL %s (%s)\n\n' "$cid" "$RUN_ID"
      printf 'evidence-set: %s/%s@plan:%s\n\n' "$RUN_ID" "$cid" "$plan"
      printf '## Depends on\n\nnone\n\n## Touches\n\n%s\n\n' "${touches:-unknown}"
      printf '## Problem\n\n'
      printf 'Criterion %s failed: %s\n\n' "$cid" "${interp:-none}"
      printf 'Observed verdict: FAIL\n'
      printf '\n## Evidence\n\n'
      printf -- '- source: verdict.json of run %s\n' "$RUN_ID"
      printf -- '- criterion: %s\n' "$cid"
      printf -- '- interpretation: %s\n' "${interp:-none}"
      printf -- '- expected: %s\n' "$expected"
      printf -- '- failed step: %s\n' "$fstep"
      printf -- '- run: %s\n' "$RUN_ID"
      printf -- '- plan_sha256: %s\n' "$plan"
      printf '\n## Suggested acceptance\n\n'
      printf -- '- [ ] Criterion %s passes on a fresh run of the same plan: %s\n' "$cid" "${interp:-none}"
      printf '\n## Status: proposed\n'
    } | pc_guarded_write "$OUT_DIR_ABS" "$SELF" "$fname"; then
    emitted=$((emitted + 1)); say "proposed $cid -> $OUT_DIR/$fname"
  else
    refused=$((refused + 1))
  fi
done <<EOF
$RECORDS
EOF

say "$emitted candidate(s) written to $OUT_DIR - nothing was queued, and nothing will be until a human moves a file out of it"
[ "$refused" -eq 0 ] || { say "$refused candidate(s) refused by the write guard (reasons above)"; exit 1; }
exit 0
