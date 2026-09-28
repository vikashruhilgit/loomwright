#!/usr/bin/env bash
# run-ground-truth.sh — the System Twin GROUND-TRUTH execution runner (M2b slice 1a).
#
# This is the GROUND-TRUTH instrument: an ADVISORY runner that resolves a set of project-declared
# executable acceptance checks, runs each one (exit 0 = pass, non-0 = fail), and emits a single hard
# PASS/FAIL signal. Where the EVAL harness (run-eval.sh) scores plugin output quality over a fixed
# corpus, and the canary benchmark (run-benchmark.sh) validates hard-signal fixtures, THIS runner
# executes the actual acceptance checks a brief / project declares and reports whether they pass.
# "ground-truth" != "eval" != "benchmark" — kept distinct by name and intent.
#
# Output shape on stdout: a human/grep per-check block (one `  [PASS]/[FAIL]/[DEFERRED] <kind>:<target>`
# line per resolved check) + a `Checks passed: M/N` line, AND exactly ONE machine-readable line:
#   GROUND_TRUTH_JSON: {schema_version,ran,status,checks_total,checks_passed,pass_rate,per_check,commit,date}
# The JSON line is jq-built for injection safety (--arg/--argjson), with a printf fallback only on
# the no-jq path (mirrors run-benchmark.sh).
#
# Fail-safe: ALWAYS exits 0. A check's non-zero exit is a normal `fail` tally, NEVER a script crash.
#   - status "skipped"            — no check source resolved (no --check, no --brief Executable
#                                   Acceptance section, no --checks-file/stdin, no
#                                   .supervisor/twin/ground-truth.json). ran:false, 0/0, per_check [].
#   - status "unverified"         — fail-safe tooling path: jq unavailable (ran:false, 0/0, []), an
#                                   explicit `--project <dir>` that is not a directory (ran:false, 0/0,
#                                   []), OR the edge where checks resolved but NONE could actually be
#                                   verified (zero passes AND zero fails AND >=1 deferred — honest:
#                                   nothing was actually verified).
#   - status "advisory_failures"  — >=1 resolved check exited non-zero (a per_check fail present).
#   - status "pass"               — >=1 check executed and passed, and ZERO checks failed (deferred
#                                   qa-executor checks may coexist; they never block a pass).
#
# Check resolution (explicit sources are COMBINED; the JSON file is fallback-only):
#   1. Explicit (all three are appended together, in this order — NOT ranked against each other):
#      repeatable `--check '<line>'`; `--brief <path>` (extract the optional `## Executable
#      Acceptance` section — leading-`-` bullets between that heading and the next `## ` heading);
#      `--checks-file <path>` or stdin (one bullet per line).
#   2. Fallback (used ONLY when no explicit source resolved any check): `.supervisor/twin/
#      ground-truth.json` (gitignored) — a JSON array of check-line strings, or {checks:[...]};
#      jq-parsed, tolerant.
#   3. None -> status "skipped".
#
# A check line is a `- `-stripped bullet that is EITHER a raw shell command OR `<kind>: <target>`
# where kind in {cmd, corpus-task, qa-executor, rule}. Per-kind execution:
#   - cmd: <shell>   (or a bare line with no recognized kind:) -> run in the PROJECT ROOT (see
#                    "Project root" below) via `bash -c '<shell>' >/dev/null 2>&1`; exit 0 = pass.
#                    (Supervisor Phase 4.5 pins the repo-root CWD, so in that path the project root
#                    IS the repo root.) An empty command
#                    (bare `cmd:`) is a malformed bullet -> per_check fail, reason "empty_cmd_target"
#                    (never a false pass). NOTE: a bare bullet whose command itself starts with a dash
#                    (e.g. `- -flag ...`) must use the `cmd:` prefix (`cmd: -flag ...`) — at ingestion a
#                    leading bullet `- `/`-` is stripped, so a bare leading-dash command would be mangled.
#                    CONTENT-KEYED STAMP GATE (--brief-sourced lines ONLY — see "Content-keyed
#                    stamp gate" below): a --brief-sourced cmd:/bare bullet additionally requires a
#                    valid ## Configuration stamp to execute; absent/stale -> per_check unverified,
#                    reason "cmd_unapproved" (never executed). --check/--checks-file-sourced cmd:
#                    bullets are NEVER subject to this gate, regardless of --brief's stamp state.
#   - corpus-task: <task-id> -> resolve to $SCRIPT_DIR/eval-corpus/<task-id>/check.sh and run it via
#                    `( cd "<task-dir>" && bash check.sh >/dev/null 2>&1 )` with EVAL_PROJECT_ROOT
#                    already exported once, up front, for every check
#                    (like run-eval.sh, though without run-eval's present-but-non-executable-check.sh
#                    fail guard — here the check is always invoked through `bash` regardless of the
#                    executable bit); exit 0 = pass. Missing task dir / check.sh -> per_check fail,
#                    reason "corpus_task_not_found" (a missing dogfood target is a real failure, not a
#                    drop). The task dir is the CWD (task-local relative paths keep working); the
#                    project the check must VERIFY arrives in $EVAL_PROJECT_ROOT — a check.sh must never
#                    derive it from its own location (see "Project root" below).
#   - qa-executor: <target> -> RECOGNIZED but DEFERRED to slice 1b. Does NOT spawn anything; records
#                    per_check status "unverified", reason "qa_executor_dispatch_deferred_m2b_1b".
#                    Counts toward checks_total but neither checks_passed nor a fail.
#   - rule: <id>     -> a house rule, resolved by DELEGATION to rules-check.sh (plan-time-rule-routing).
#                    This runner NEVER reads the rules store and NEVER extracts or runs a rule's check
#                    itself — rules-check.sh stays the ONE script that parses and executes a check
#                    (skills/rules/SKILL.md §9). Resolution, all calls with cwd = PROJECT_ROOT and
#                    stdin </dev/null, each made at most ONCE per run however many rule: bullets exist:
#                    (a) `rules-check.sh --list-selected` names the must+checkable ids. An id NOT in that
#                        list -> per_check fail, reason "rule_not_found" (an absent id, an advisory
#                        rule, a null-check rule, an empty target — named, never a silent pass). A list
#                        call that itself exits non-zero -> every rule: bullet unverified,
#                        "rule_unresolved".
#                    (b) --no-cmd / GROUND_TRUTH_NO_CMD=1 -> rules-check.sh --if-stamped is NOT invoked
#                        and no PASS/FAIL is parsed; every listed id is unverified, reason
#                        "rule_cmd_disabled". (A check is arbitrary shell, so the unattended valve must
#                        reach it; and rules-check echoes raw check text on its SKIP/RUN lines, so a
#                        check carrying a newline + `  [PASS] <id>` could forge a pass if we parsed.)
#                    (c) otherwise `rules-check.sh --if-stamped` runs ONCE and its output is mapped
#                        FAIL-CLOSED, in this order:
#                          1. an exact `  [SKIP] all (unstamped)` line -> every listed id unverified,
#                             reason "rule_unapproved" (nothing executed);
#                          2. the run must END with an exact `Checks passed: N/M` line whose M equals
#                             the number of ids --list-selected printed, and exit 0 or 1 (1 is the
#                             EXPECTED rc when any check fails — a normal result, not a tooling
#                             error). Missing / malformed / mismatched trailer or any other rc -> every
#                             listed id unverified, reason "rule_unresolved". This closes the residual
#                             where a stamped check pre-prints a forged `[PASS] <id>` (via its own
#                             echoed check text) and then kills its parent before the real line;
#                          3. per id: exactly one whole-line `  [PASS] <id>` and no other result line
#                             for it -> pass; exactly one `  [FAIL] <id>` and no other -> fail, reason
#                             "rule_check_failed"; anything else (duplicates, a PASS+FAIL pair, a
#                             near-miss line containing `[PASS] <id>`/`[FAIL] <id>` that is not an
#                             exact result line, or no line at all) -> unverified, "rule_unresolved".
#                             A forged or ambiguous line can only DEGRADE a result, never promote it.
#                    NOT subject to the brief `sha256:` stamp gate and never hashed by
#                    exec-acceptance-lib.sh: a rule: bullet's authorization is the USER-SCOPE rules
#                    stamp only (skills/rules/SKILL.md §8.1 — two different stamps, never conflated).
#                    HONEST LIMITS: (i) --if-stamped replays the WHOLE stamped must-set, not just the
#                    named ids — the pre-existing rules-check contract, a set a human already
#                    confirmed; this runner REPORTS only the named ids. (ii) in execute mode
#                    rules-check echoes `  [RUN ] <id>: <check>` before each check, so a crafted check
#                    can still pre-print a forged `[PASS] <id>` for its OWN id; the duplicate/conflict
#                    rule turns that into rule_unresolved whenever the real result line also appears,
#                    and the trailer rule covers the case where it does not. A stamped set's check
#                    text was confirmed by a human (the stamp hashes `id\tcheck`), which bounds this to
#                    checks a human already approved.
#
# TRUST BOUNDARY (not a sandbox): the runner ITSELF performs no repo writes and makes no network
# calls — but it is NOT a security boundary. A `cmd:` (or bare) check runs an arbitrary
# `bash -c '<shell>'` with full, unrestricted shell privileges (it CAN write files / hit the
# network); that is the whole point — it executes the project's *declared* acceptance checks. The
# "no writes / no network" property is therefore a property of well-behaved, TRUSTED checks, not an
# enforced guarantee. Because Phase 4.5 runs this automatically and unattended (including under
# /autonomous, where the brief's `## Executable Acceptance` section is machine-authored by Launch
# Pad), `cmd:` bullets are a trust-sensitive surface — a --brief-sourced one now additionally
# requires the content-keyed stamp below to execute at all (enforced HERE, not merely reviewed at
# Plan Review); a --check/--checks-file-sourced one is a human typing the command directly into
# this invocation and is unaffected by the stamp gate.
# corpus-task ids are constrained to a single path segment (no `/`/`..`) so they cannot escape
# eval-corpus, but `cmd:` shell is intentionally unconstrained.
# eval-corpus is resolved relative to $SCRIPT_DIR so `corpus-task:` works regardless of CWD.
#
# Project root (the ONE directory every check kind is evaluated against):
#   PROJECT_ROOT = `--project <dir>` if given, else the git toplevel of the CALLER's CWD, else the
#   caller's CWD itself. `cmd:` checks run from it, the `.supervisor/twin/ground-truth.json` fallback
#   and the contextual `commit` field are read from it, and it is exported to every corpus-task
#   check.sh as EVAL_PROJECT_ROOT (the corpus contract — eval-corpus/README.md §"Project root").
#   WHY this is load-bearing: on a marketplace install $SCRIPT_DIR is
#   the plugin manager's install cache (<cache>/<marketplace>/loomwright/<version>/scripts) — NOT inside any git repo — so a
#   check.sh that resolved the repo from ITS OWN directory (`git rev-parse --show-toplevel` after the
#   runner's cd into the task dir) failed every maintainer-side dogfood task with "not inside a git
#   repo" (observed 2026-09-13: Phase 4.5 ground_truth reported advisory_failures 2/4 while the
#   checkout's copy of the same runner passed 4/4). The project being verified is the CALLER's, never
#   the runner's home; the runner is the only party that knows the caller's CWD, so it passes it down.
#
# Test-only env hook: GROUND_TRUTH_FORCE_NO_JQ=1 forces the no-jq fail-safe branch (so the self-test
# can deterministically exercise the "unverified" tooling path without a brittle PATH shim). It is a
# TEST-ONLY hook and has no effect on normal operation.
#
# Safety valve: --no-cmd (or GROUND_TRUTH_NO_CMD=1) skips cmd:/bare shell checks entirely (recorded
# per_check "unverified", reason "cmd_disabled" — never executed); corpus-task:/qa-executor: are
# unaffected. --no-cmd ALWAYS wins, regardless of source or stamp (see below) — it is checked first.
# It ALSO reaches rule: bullets (a rule check is arbitrary shell): listed ids become "unverified",
# reason "rule_cmd_disabled", and rules-check.sh --if-stamped is never invoked.
#
# Content-keyed stamp gate (red-team-hardening item 05, "cmd: valve by provenance" — supersedes the
# NON_INTERACTIVE-only mitigation this section used to describe): a `cmd:`/bare bullet sourced from
# `--brief`'s `## Executable Acceptance` section executes ONLY when the brief's `## Configuration`
# section carries a line `- **Executable Acceptance Approved:** sha256:<hash>` whose `<hash>` equals
# `scripts/exec-acceptance-hash.sh <brief>`'s CURRENT output (both this runner and that script share
# one classification/hash definition — `exec-acceptance-lib.sh` — so they cannot silently diverge).
# An absent OR stale (edited-since-stamped) stamp records the bullet as unverified, reason
# "cmd_unapproved" (a NEW reason, distinct from --no-cmd's "cmd_disabled"), and executes NOTHING.
# This gate applies ONLY to bullets sourced from --brief; an explicit --check/--checks-file bullet
# runs exactly as it always has, stamped or not — see the per-line source-provenance tracking below
# (CHECK_SOURCES). Machine-authored briefs (Launch Pad, /autonomous) never carry the stamp by
# construction, so their cmd:/bare bullets (an authoring-convention violation in the first place —
# see docs/RESULT_SCHEMAS.md §"`## Executable Acceptance`") are unapproved by default.
#
# Usage:  run-ground-truth.sh [--check '<line>']... [--brief <path>] [--checks-file <path>] [--no-cmd]
#                             [--project <dir>]
# Exit:   always 0.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORPUS="$SCRIPT_DIR/eval-corpus"

# shellcheck source=exec-acceptance-lib.sh
. "$SCRIPT_DIR/exec-acceptance-lib.sh"

# ---- argv parse -----------------------------------------------------------
EXPLICIT_CHECKS=()   # collected from --check / --brief / --checks-file (in resolution order)
BRIEF=""
CHECKS_FILE=""
PROJECT_ARG=""       # --project <dir>: explicit project root (else derived from the caller's CWD)
# --no-cmd (or GROUND_TRUTH_NO_CMD=1): safety valve for unattended use. When set, cmd:/bare shell
# checks are NOT executed (recorded per_check "unverified", reason "cmd_disabled"); corpus-task: and
# qa-executor: are unaffected. --no-cmd ALWAYS wins over the content-keyed stamp gate below — it is
# checked first in the execution loop, regardless of a bullet's source or stamp validity.
NO_CMD=0
[ "${GROUND_TRUTH_NO_CMD:-0}" = "1" ] && NO_CMD=1

while [ $# -gt 0 ]; do
  case "$1" in
    --check)        EXPLICIT_CHECKS+=("${2:-}"); shift; [ $# -gt 0 ] && shift ;;
    --check=*)      EXPLICIT_CHECKS+=("${1#--check=}"); shift ;;
    --brief)        BRIEF="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --brief=*)      BRIEF="${1#--brief=}"; shift ;;
    --checks-file)  CHECKS_FILE="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --checks-file=*) CHECKS_FILE="${1#--checks-file=}"; shift ;;
    --no-cmd)       NO_CMD=1; shift ;;
    --project)      PROJECT_ARG="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --project=*)    PROJECT_ARG="${1#--project=}"; shift ;;
    *) shift ;;
  esac
done

# ---- project root (the one directory every check kind is evaluated against) --
# `--project <dir>` wins; else the git toplevel of the caller's CWD; else the caller's CWD itself.
# Resolved ONCE, before any check runs, and exported to corpus-task checks as EVAL_PROJECT_ROOT.
# An explicit --project that is not a directory is a caller configuration error: handled below (after
# the emit helpers exist) as the fail-safe "unverified" tooling path — never a false pass.
PROJECT_ROOT=""
PROJECT_ARG_INVALID=0
if [ -n "$PROJECT_ARG" ]; then
  if [ -d "$PROJECT_ARG" ]; then
    PROJECT_ROOT="$(cd "$PROJECT_ARG" && pwd -P)"
  else
    PROJECT_ARG_INVALID=1
  fi
else
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
fi
export EVAL_PROJECT_ROOT="$PROJECT_ROOT"

# ---- contextual fields (NOT part of the determinism invariant) ------------
# `commit` describes the PROJECT being verified (not the runner's own checkout — they differ on a
# marketplace install), so it is read from PROJECT_ROOT.
if [ -n "$PROJECT_ROOT" ]; then
  COMMIT="$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
else
  COMMIT="unknown"
fi
DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"

# ---- emit helpers ---------------------------------------------------------
# emit_no_jq_unverified: hand-built minimal JSON (only fixed/whitelisted values — injection-safe).
emit_no_jq_unverified() {
  echo "Checks passed: 0/0"
  printf 'GROUND_TRUTH_JSON: {"schema_version":1,"ran":false,"status":"unverified","checks_total":0,"checks_passed":0,"pass_rate":"0/0","per_check":[],"commit":"%s","date":"%s"}\n' \
    "$COMMIT" "$DATE"
}

# emit_jq <ran-bool> <status> <total> <passed> <pass_rate> <per_check_json>
emit_jq() {
  local ran="$1" status="$2" total="$3" passed="$4" pr="$5" per_check="$6"
  echo "Checks passed: $pr"
  jq -cn \
    --argjson ran "$ran" \
    --arg status "$status" \
    --argjson total "$total" \
    --argjson passed "$passed" \
    --arg pr "$pr" \
    --argjson per_check "$per_check" \
    --arg commit "$COMMIT" \
    --arg date "$DATE" \
    '{schema_version:1,ran:$ran,status:$status,checks_total:$total,checks_passed:$passed,pass_rate:$pr,per_check:$per_check,commit:$commit,date:$date}' \
    | sed 's/^/GROUND_TRUTH_JSON: /'
}

# ---- fail-safe: no jq -----------------------------------------------------
# GROUND_TRUTH_FORCE_NO_JQ=1 forces this branch for deterministic self-testing.
if [ "${GROUND_TRUTH_FORCE_NO_JQ:-0}" = "1" ] || ! command -v jq >/dev/null 2>&1; then
  echo "run-ground-truth: no jq available — cannot build result, fail-safe no-op" >&2
  emit_no_jq_unverified
  exit 0
fi

# ---- fail-safe: --project names a non-directory ---------------------------
# A caller that names a project that does not exist has nothing verifiable; running the checks
# against some OTHER directory (the CWD, the runner's home) would report on the wrong project. Emit
# the same fail-safe "unverified" shape as the no-jq path (ran:false, 0/0, []) and exit 0.
if [ "$PROJECT_ARG_INVALID" -eq 1 ]; then
  echo "run-ground-truth: --project '$PROJECT_ARG' is not a directory — nothing verifiable (unverified)" >&2
  emit_jq false "unverified" 0 0 "0/0" "[]"
  exit 0
fi

# ---- resolve check lines (priority order) ---------------------------------
# CHECK_LINES is the ordered list of resolved bullet strings (already `- `-stripped, trimmed).
# CHECK_SOURCES is a PARALLEL array (same index) recording where each line came from —
# "check" (1a --check) | "brief" (1b --brief) | "checks_file" (1c --checks-file/stdin) |
# "fallback" (2, .supervisor/twin/ground-truth.json). This is the per-line source-provenance
# tracking the content-keyed stamp gate needs: the gate below applies ONLY to kind=="cmd" lines
# whose source is exactly "brief" — an explicit --check/--checks-file cmd: bullet is NEVER gated,
# even in a mixed invocation that also passes an unstamped --brief. `trim`/`strip_bullet` are
# defined in the sourced exec-acceptance-lib.sh (shared with exec-acceptance-hash.sh).
CHECK_LINES=()
CHECK_SOURCES=()

add_line() {  # add_line <raw-line> <source-tag> — add a raw bullet line if non-empty after stripping
  local s; s="$(strip_bullet "$1")"
  if [ -n "$s" ]; then
    CHECK_LINES+=("$s")
    CHECK_SOURCES+=("${2:-unknown}")
  fi
}

# 1a. Explicit --check args (highest priority, in order).
if [ "${#EXPLICIT_CHECKS[@]}" -gt 0 ]; then
  for c in "${EXPLICIT_CHECKS[@]}"; do
    add_line "$c" "check"
  done
fi

# 1b. --brief: extract the `## Executable Acceptance` section's leading-`-` bullets (shared
# extraction logic — exec-acceptance-lib.sh's extract_brief_section_bullets — identical heading
# match and bullet collection rule exec-acceptance-hash.sh uses to compute the stamp).
if [ -n "$BRIEF" ] && [ -f "$BRIEF" ]; then
  while IFS= read -r s; do
    [ -n "$s" ] && { CHECK_LINES+=("$s"); CHECK_SOURCES+=("brief"); }
  done < <(extract_brief_section_bullets "$BRIEF")
fi

# 1c. --checks-file (or stdin via "-"): one bullet per line.
if [ -n "$CHECKS_FILE" ]; then
  if [ "$CHECKS_FILE" = "-" ]; then
    while IFS= read -r raw || [ -n "$raw" ]; do add_line "$raw" "checks_file"; done
  elif [ -f "$CHECKS_FILE" ]; then
    while IFS= read -r raw || [ -n "$raw" ]; do add_line "$raw" "checks_file"; done < "$CHECKS_FILE"
  fi
fi

# 2. Fallback: .supervisor/twin/ground-truth.json (only if nothing explicit resolved).
if [ "${#CHECK_LINES[@]}" -eq 0 ]; then
  GT_FILE="$PROJECT_ROOT/.supervisor/twin/ground-truth.json"
  if [ -f "$GT_FILE" ]; then
    # Tolerant: accept a top-level array of strings OR {checks:[...]}; sort for stable order.
    gt_lines="$(jq -r '
        (if type=="array" then . elif (type=="object" and (.checks|type=="array")) then .checks else [] end)
        | map(select(type=="string")) | .[]
      ' "$GT_FILE" 2>/dev/null | LC_ALL=C sort)"
    if [ -n "$gt_lines" ]; then
      while IFS= read -r raw; do add_line "$raw" "fallback"; done <<EOF
$gt_lines
EOF
    fi
  fi
fi

# 3. None resolved -> skipped.
if [ "${#CHECK_LINES[@]}" -eq 0 ]; then
  echo "run-ground-truth: no check source resolved — nothing to verify (skipped)" >&2
  emit_jq false "skipped" 0 0 "0/0" "[]"
  exit 0
fi

# ---- content-keyed stamp gate (--brief-sourced cmd:/bare bullets only) ----------------------
# BRIEF_HASH_VALID=1 iff: a --brief was given, its Executable Acceptance section has >=1 cmd:/bare
# bullet (exec_acceptance_hash != "none"), AND the brief's ## Configuration section carries a
# stamp line whose hash matches that CURRENT hash exactly. A missing OR stale (post-stamp edit)
# stamp leaves this 0 — the gate below then records every brief-sourced cmd:/bare bullet
# "unverified"/"cmd_unapproved" and executes none of them. Computed ONCE, before the loop, from
# the SAME shared exec_acceptance_hash() exec-acceptance-hash.sh uses — see exec-acceptance-lib.sh.
# This is the LOAD-BEARING hash-comparison — the BLOCKING mutation control in
# test-run-ground-truth.sh splices this exact block out and replaces it with an unconditional
# BRIEF_HASH_VALID=1 to prove the stale-stamp test case genuinely depends on this comparison
# (see red-team-hardening item 05 AC7).
# MUTATION_CONTROL_BEGIN: exec-acceptance-stamp-gate
BRIEF_HASH_VALID=0
if [ -n "$BRIEF" ] && [ -f "$BRIEF" ]; then
  BRIEF_CURRENT_HASH="$(exec_acceptance_hash "$BRIEF" 2>/dev/null || printf 'none\n')"
  if [ "$BRIEF_CURRENT_HASH" != "none" ]; then
    BRIEF_STAMP="$(extract_configuration_stamp "$BRIEF")"
    if [ -n "$BRIEF_STAMP" ] && [ "$BRIEF_STAMP" = "$BRIEF_CURRENT_HASH" ]; then
      BRIEF_HASH_VALID=1
    fi
  fi
fi
# MUTATION_CONTROL_END: exec-acceptance-stamp-gate

# ---- rule: pre-resolution (DELEGATION to rules-check.sh — see the header's `rule:` entry) --------
# Everything a rule: bullet needs is gathered HERE, ONCE, before the per-check loop: the selected-id
# list and (unless --no-cmd) one --if-stamped replay. This block never reads the rules store and never
# sees a check string — rules-check.sh is the only party that does.
RULE_LISTED=""        # newline-joined ids printed by `rules-check.sh --list-selected`
RULE_LIST_OK=1        # 0 => the list call exited non-zero => every rule: bullet rule_unresolved
RULE_LISTED_N=0       # number of listed ids (the M the --if-stamped trailer must agree with)
RULE_RUN_MODE=""      # disabled | unapproved | unresolved | mapped | "" (nothing listed to run)
RULE_RUN_OUT=""       # captured stdout of the ONE --if-stamped call (mapped mode only)

# _rule_is_listed <id> — exit 0 iff <id> is exactly one of the listed ids (whole-line, literal).
_rule_is_listed() {
  [ -n "$1" ] && [ -n "$RULE_LISTED" ] || return 1
  grep -Fxq -- "$1" <<<"$RULE_LISTED"
}

# _rule_map_id <id> — prints pass | fail | unresolved from RULE_RUN_OUT (decision (c) step 3).
_rule_map_id() {
  local id="$1" l rest np=0 nf=0 nm=0
  while IFS= read -r l; do
    if [ "$l" = "  [PASS] $id" ]; then
      np=$((np+1))
    elif [ "$l" = "  [FAIL] $id" ]; then
      nf=$((nf+1))
    else
      case "$l" in
        *"[PASS] $id"*|*"[FAIL] $id"*)
          # An exact result line of ANOTHER listed id (e.g. `ab` when this id is `a`) is not about
          # this id; anything else mentioning `[PASS] <id>`/`[FAIL] <id>` is a near-miss => degrade.
          rest=""
          case "$l" in
            "  [PASS] "*) rest="${l#"  [PASS] "}" ;;
            "  [FAIL] "*) rest="${l#"  [FAIL] "}" ;;
          esac
          if [ -n "$rest" ] && [ "$rest" != "$id" ] && _rule_is_listed "$rest"; then
            :
          else
            nm=$((nm+1))
          fi
          ;;
      esac
    fi
  done <<EOF
$RULE_RUN_OUT
EOF
  if [ "$np" -eq 1 ] && [ "$nf" -eq 0 ] && [ "$nm" -eq 0 ]; then
    printf 'pass\n'
  elif [ "$nf" -eq 1 ] && [ "$np" -eq 0 ] && [ "$nm" -eq 0 ]; then
    printf 'fail\n'
  else
    printf 'unresolved\n'
  fi
}

_rule_any=0
_rule_any_listed=0
for idx in "${!CHECK_LINES[@]}"; do
  [ "$(classify_kind "${CHECK_LINES[$idx]}")" = "rule" ] && { _rule_any=1; break; }
done
if [ "$_rule_any" -eq 1 ]; then
  RULE_LISTED="$( cd "$PROJECT_ROOT" && bash "$SCRIPT_DIR/rules-check.sh" --list-selected </dev/null 2>/dev/null )"
  _rule_rc=$?
  if [ "$_rule_rc" -ne 0 ]; then
    RULE_LIST_OK=0
    RULE_LISTED=""
  fi
  if [ -n "$RULE_LISTED" ]; then
    while IFS= read -r _rule_l; do
      [ -n "$_rule_l" ] && RULE_LISTED_N=$((RULE_LISTED_N+1))
    done <<EOF
$RULE_LISTED
EOF
  fi
  for idx in "${!CHECK_LINES[@]}"; do
    [ "$(classify_kind "${CHECK_LINES[$idx]}")" = "rule" ] || continue
    if _rule_is_listed "$(trim "${CHECK_LINES[$idx]#rule:}")"; then _rule_any_listed=1; break; fi
  done
fi
if [ "$_rule_any_listed" -eq 1 ]; then
  if [ "$NO_CMD" -eq 1 ]; then
    RULE_RUN_MODE="disabled"            # (b): never invoke --if-stamped, never parse PASS/FAIL
  else
    RULE_RUN_OUT="$( cd "$PROJECT_ROOT" && bash "$SCRIPT_DIR/rules-check.sh" --if-stamped </dev/null 2>/dev/null )"
    _rule_rc=$?
    if grep -Fxq -- "  [SKIP] all (unstamped)" <<<"$RULE_RUN_OUT"; then
      RULE_RUN_MODE="unapproved"        # (c)1: checked FIRST — nothing executed
    else
      RULE_RUN_MODE="unresolved"        # (c)2: default until the trailer + rc validate
      _rule_last="${RULE_RUN_OUT##*$'\n'}"
      case "$_rule_rc" in
        0|1)
          case "$_rule_last" in
            "Checks passed: "*/*)
              _rule_nm="${_rule_last#Checks passed: }"
              _rule_n="${_rule_nm%%/*}"
              _rule_m="${_rule_nm#*/}"
              case "$_rule_n$_rule_m" in
                *[!0-9]*) : ;;
                *)
                  if [ -n "$_rule_n" ] && [ -n "$_rule_m" ] && [ "$_rule_m" -eq "$RULE_LISTED_N" ]; then
                    RULE_RUN_MODE="mapped"
                  fi
                  ;;
              esac
              ;;
          esac
          ;;
      esac
    fi
  fi
fi

# ---- execute each resolved check ------------------------------------------
total=0
passed=0
failures=0
deferred=0
per_check_json="[]"

# append_check <kind> <target> <status> [reason]
append_check() {
  local kind="$1" target="$2" status="$3" reason="${4:-}"
  if [ -n "$reason" ]; then
    per_check_json="$(printf '%s' "$per_check_json" \
      | jq -c --arg k "$kind" --arg t "$target" --arg s "$status" --arg r "$reason" \
        '. + [{kind:$k,target:$t,status:$s,reason:$r}]')"
  else
    per_check_json="$(printf '%s' "$per_check_json" \
      | jq -c --arg k "$kind" --arg t "$target" --arg s "$status" \
        '. + [{kind:$k,target:$t,status:$s}]')"
  fi
}

for idx in "${!CHECK_LINES[@]}"; do
  line="${CHECK_LINES[$idx]}"
  line_source="${CHECK_SOURCES[$idx]}"
  total=$((total+1))

  # Classify via the shared classify_kind() (exec-acceptance-lib.sh) — IDENTICAL rule
  # exec-acceptance-hash.sh uses, by construction (one sourced definition, not two copies).
  kind="$(classify_kind "$line")"
  target=""
  # Use trim (whitespace only) — NOT strip_bullet — so a target with a leading dash (e.g.
  # `cmd: -x foo`) keeps its dash. The line was already bullet-stripped at ingestion (add_line).
  case "$kind" in
    cmd)          target="$(trim "${line#cmd:}")" ;;
    corpus-task)  target="$(trim "${line#corpus-task:}")" ;;
    qa-executor)  target="$(trim "${line#qa-executor:}")" ;;
    rule)         target="$(trim "${line#rule:}")" ;;
  esac

  case "$kind" in
    cmd)
      if [ "$NO_CMD" -eq 1 ]; then
        # Safety valve (--no-cmd / GROUND_TRUTH_NO_CMD=1): do NOT execute arbitrary shell. Record
        # as unverified (like a deferral) — counts toward checks_total, never a pass or a fail.
        # This ALWAYS wins, regardless of source or stamp validity — checked first.
        deferred=$((deferred+1))
        echo "  [SKIP] cmd:$target (cmd execution disabled via --no-cmd)"
        append_check "cmd" "$target" "unverified" "cmd_disabled"
      elif [ "$line_source" = "brief" ] && [ "$BRIEF_HASH_VALID" -ne 1 ]; then
        # Content-keyed stamp gate: this bullet came from --brief's Executable Acceptance section
        # and the brief carries no valid (matching, non-stale) stamp — do NOT execute. Applies
        # ONLY to line_source=="brief" lines; a --check/--checks-file cmd: bullet is NEVER gated
        # here, even in a mixed invocation alongside an unstamped --brief.
        deferred=$((deferred+1))
        echo "  [SKIP] cmd:$target (unapproved — brief Executable Acceptance stamp missing or stale)"
        append_check "cmd" "$target" "unverified" "cmd_unapproved"
      elif [ -z "$target" ]; then
        # An empty command (a bare `cmd:` or `cmd:` + whitespace bullet) is a malformed declaration,
        # NOT a check. `bash -c ""` exits 0, so without this guard it would be a false PASS that
        # silently inflates the green signal. Surface it as a fail so the bad bullet is visible.
        failures=$((failures+1))
        echo "  [FAIL] cmd: (empty command)"
        append_check "cmd" "$target" "fail" "empty_cmd_target"
      elif ( cd "$PROJECT_ROOT" && bash -c "$target" >/dev/null 2>&1 ); then
        # Run from PROJECT_ROOT (see header §"Project root") so a repo-root-relative command in a brief
        # means the same thing whichever copy of this runner executes it.
        passed=$((passed+1))
        echo "  [PASS] cmd:$target"
        append_check "cmd" "$target" "pass"
      else
        failures=$((failures+1))
        echo "  [FAIL] cmd:$target"
        append_check "cmd" "$target" "fail"
      fi
      ;;
    corpus-task)
      # A corpus task-id is a single path segment under eval-corpus/. Reject empty ids and any
      # '/' or '..' so a target can never escape $CORPUS (resolve eval-corpus relative to SCRIPT_DIR).
      # NOTE: `*..*` is intentionally over-broad — it also rejects a legit id that merely *contains*
      # ".." (e.g. `foo..bar`). That's a deliberate fail-closed choice; corpus ids are simple slugs
      # today, so no real id is lost, and it keeps the traversal guard dead simple.
      case "$target" in
        ""|*/*|*..*)
          failures=$((failures+1))
          echo "  [FAIL] corpus-task:$target (invalid task id)"
          append_check "corpus-task" "$target" "fail" "corpus_task_invalid_id"
          continue
          ;;
      esac
      task_dir="$CORPUS/$target"
      check="$task_dir/check.sh"
      if [ ! -f "$check" ]; then
        failures=$((failures+1))
        echo "  [FAIL] corpus-task:$target (check.sh not found)"
        append_check "corpus-task" "$target" "fail" "corpus_task_not_found"
      elif ( cd "$task_dir" && bash "$check" >/dev/null 2>&1 ); then
        # CWD = task dir (task-local relative paths keep working); the project to VERIFY reaches the
        # check via the exported EVAL_PROJECT_ROOT (set once above), never via the check's location.
        passed=$((passed+1))
        echo "  [PASS] corpus-task:$target"
        append_check "corpus-task" "$target" "pass"
      else
        failures=$((failures+1))
        echo "  [FAIL] corpus-task:$target"
        append_check "corpus-task" "$target" "fail"
      fi
      ;;
    rule)
      # Resolved by DELEGATION (see the pre-resolution block + header). Never hashed, never subject
      # to the brief stamp gate, never executed here.
      if [ "$RULE_LIST_OK" -ne 1 ]; then
        deferred=$((deferred+1))
        echo "  [SKIP] rule:$target (unresolved — rules-check.sh --list-selected failed)"
        append_check "rule" "$target" "unverified" "rule_unresolved"
      elif ! _rule_is_listed "$target"; then
        failures=$((failures+1))
        echo "  [FAIL] rule:$target (not a must rule with a check)"
        append_check "rule" "$target" "fail" "rule_not_found"
      else
        case "$RULE_RUN_MODE" in
          disabled)
            deferred=$((deferred+1))
            echo "  [SKIP] rule:$target (cmd execution disabled via --no-cmd)"
            append_check "rule" "$target" "unverified" "rule_cmd_disabled"
            ;;
          unapproved)
            deferred=$((deferred+1))
            echo "  [SKIP] rule:$target (unapproved — no matching rules-check stamp)"
            append_check "rule" "$target" "unverified" "rule_unapproved"
            ;;
          mapped)
            case "$(_rule_map_id "$target")" in
              pass)
                passed=$((passed+1))
                echo "  [PASS] rule:$target"
                append_check "rule" "$target" "pass"
                ;;
              fail)
                failures=$((failures+1))
                echo "  [FAIL] rule:$target"
                append_check "rule" "$target" "fail" "rule_check_failed"
                ;;
              *)
                deferred=$((deferred+1))
                echo "  [SKIP] rule:$target (unresolved rules-check output)"
                append_check "rule" "$target" "unverified" "rule_unresolved"
                ;;
            esac
            ;;
          *)
            deferred=$((deferred+1))
            echo "  [SKIP] rule:$target (unresolved rules-check output)"
            append_check "rule" "$target" "unverified" "rule_unresolved"
            ;;
        esac
      fi
      ;;
    qa-executor)
      # DEFERRED to slice 1b — recognized, recorded, never spawned. Neither pass nor fail.
      deferred=$((deferred+1))
      echo "  [DEFERRED] qa-executor:$target (dispatch deferred to M2b slice 1b)"
      append_check "qa-executor" "$target" "unverified" "qa_executor_dispatch_deferred_m2b_1b"
      ;;
  esac
done

pass_rate="$passed/$total"

# ---- derive status --------------------------------------------------------
# advisory_failures: any check failed.
# pass:              >=1 real pass AND zero failures.
# unverified:        zero passes AND zero failures (only deferred checks resolved) — nothing verified.
if [ "$failures" -gt 0 ]; then
  status="advisory_failures"
elif [ "$passed" -gt 0 ]; then
  status="pass"
else
  # passed==0 && failures==0 => only deferred checks (deferred >= 1 by construction here).
  status="unverified"
fi

# `ran` means ">=1 check actually executed a verifiable pass/fail". A deferred qa-executor check
# executes nothing, so the all-deferred path reports ran:false (status:unverified) — matching the
# header / RESULT_SCHEMAS contract and the supervisor.md `ground_truth.checked = gt.ran` mapping.
if [ $((passed + failures)) -gt 0 ]; then ran=true; else ran=false; fi

emit_jq "$ran" "$status" "$total" "$passed" "$pass_rate" "$per_check_json"
exit 0
