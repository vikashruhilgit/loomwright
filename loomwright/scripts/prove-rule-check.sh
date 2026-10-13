#!/usr/bin/env bash
# prove-rule-check.sh — show that a CANDIDATE rule `check` can tell right from wrong before it may
# become a `must` rule (verified-rule-checks; owner decisions D1–D4).
#
# A check that passes today proves nothing on its own: `true`, a grep for a token that is always
# present, or a path typo that matches nothing all pass forever. This script runs the check twice:
#   leg 1  on the CURRENT working tree, from the repo root          → must exit 0
#   leg 2  on a throwaway scratch copy of HEAD with a COUNTEREXAMPLE patch applied → must exit non-zero
# and prints ONE verdict.
#
# VERDICTS — a closed set owned by THIS header; every other surface points here, never restates a
# different set. `add-rule.sh` accepts only PROVEN.
#   PROVEN      exit 0  leg 1 passed, the scratch baseline passed, leg 2 FAILED — the check catches
#                       the violation the patch introduces.
#   VACUOUS     exit 1  leg 1 passed AND leg 2 passed — the check cannot see the violation.
#   FAILS_NOW   exit 1  leg 1 failed — the check does not hold on the current tree. Leg 2 never runs.
#   UNPROVABLE  exit 2  could not examine: `UNPROVABLE (<reason>)`. Reasons: bad_args,
#                       counterexample_unreadable, counterexample_empty, not_a_git_repo,
#                       no_head_commit, out_inside_repo, out_dir_missing, out_not_a_file, jq_missing,
#                       sha256_unavailable, needs_confirmation, scratch_create_failed,
#                       worktree_add_failed, patch_does_not_apply, patch_no_effect,
#                       scratch_baseline_fails, timeout, interrupted, scratch_leak,
#                       proof_write_failed.
# Could-not-examine is NEVER proven: every error path is UNPROVABLE and non-zero. This is a
# correctness gate (CLAUDE.md bimodal-failure invariant) and fails CLOSED.
#
# Usage:
#   prove-rule-check.sh --check <str> --counterexample <patch-file> [--out <proof-file>]
#                       [--confirm] [--timeout <secs>]
#   --check           the candidate check string, run via `bash -c` exactly as rules-check.sh would
#                     run a stored one. It comes ONLY from argv: this script never reads .agent/rules/.
#   --counterexample  a unified-diff patch file (D1) introducing ONE violation of the rule. It is
#                     applied ONLY inside the scratch copy, never to the user's tree.
#   --out             write a proof file (D2) for every verdict — see "PROOF FILE" below. Must resolve
#                     OUTSIDE the repo working tree (refused otherwise: out_inside_repo). The
#                     containment check runs BEFORE any refusal that could write a proof, so an
#                     in-repo --out never receives one on ANY path: an earlier refusal (bad_args,
#                     counterexample_unreadable, …) still names its own reason, but writes nothing.
#   --confirm         run without a prompt. See "CONFIRMATION".
#   --timeout         per-leg timeout in seconds (positive integer; default 60). The environment
#                     variable PROVE_RULE_CHECK_TIMEOUT sets the default; argv wins. It is the ONLY
#                     environment variable this script reads as an input.
#
# CONFIRMATION (scope 2/3 — same trust boundary as `rules-check.sh --confirm`, skills/rules/SKILL.md
# §9). A check is arbitrary shell. The check string and the patch text are PRINTED first; the check
# runs only on an argv `--confirm` or an interactive `y` (stdin AND stdout both TTYs). No environment
# variable confirms. Otherwise nothing runs and the verdict is `UNPROVABLE (needs_confirmation)`.
# Proving writes NO stamp: the user-scope rules-check stamp is rules-check.sh's alone, and proving a
# candidate is not authorizing its replay — a human still runs `/rules check --confirm` for that.
#
# ORDER.
#   1. Leg 1: `bash -c "<check>" </dev/null` from the repo root (`git rev-parse --show-toplevel`).
#      Non-zero ⇒ FAILS_NOW; the scratch copy is never created.
#   2. Scratch: `mktemp -d` (physical path), `git worktree add --detach <scratch>/wt HEAD` with
#      hooks disabled for that one command.
#   3. Baseline: run the check in the scratch copy BEFORE the patch. Non-zero ⇒
#      `UNPROVABLE (scratch_baseline_fails)` — the scratch copy (HEAD) differs from the working tree
#      in something the check reads, so a later failure could not be credited to the patch.
#   4. `git apply` the patch in the scratch copy (fails ⇒ patch_does_not_apply; applies but changes
#      nothing ⇒ patch_no_effect).
#   5. Leg 2: run the check in the scratch copy. Exit 0 ⇒ VACUOUS, non-zero ⇒ PROVEN.
#   6. Cleanup (always, also on interrupt): `git worktree remove --force <scratch>/wt`, `rm -rf
#      <scratch>`, then VERIFY that `git worktree list --porcelain` has no entry for it and the
#      directory is gone. A failed verify overrides any verdict with `UNPROVABLE (scratch_leak)`.
#      `--force` is correct here: the scratch tree is this script's own; nothing of the user's lives
#      there. There is deliberately NO global `git worktree prune`: it would also prune the user's
#      OTHER stale worktree entries, changing a worktree list this script promises to leave as found.
#      A leaked entry is reported instead, with the remedy.
#
# TIMEOUT. No `timeout(1)` on stock macOS, so each run uses the background-process + watchdog idiom
# of run-self-tests.sh: the check runs in the background, polled against the limit; on expiry its
# process tree is TERMed, then KILLed. A timed-out run ⇒ `UNPROVABLE (timeout)`.
#
# OUTPUT. Each run's exit code and its (bounded) stdout/stderr, then ONE final line:
#   verdict: <VERDICT>[ (<reason>)]
#
# PROOF FILE (D2/D4). With --out, written atomically for EVERY verdict (an in-repo --out excepted:
# it never receives one — see --out), built only with `jq -n`:
#   {"schema":"rule-check-proof/1","verdict":…,"reason":…|null,"check_sha256":…|null,
#    "counterexample_sha256":…|null,"now_exit":…|null,"baseline_exit":…|null,
#    "counterexample_exit":…|null,"ts":…}
# `check_sha256` is the sha256 of the exact check bytes (`printf '%s'`, no trailing newline), the
# hash add-rule.sh recomputes. The proof is NOT a rule-schema member (D4): record the verdict and
# both outputs in the commit / PR body instead.
#
# HONEST LIMITS.
#   - Leg 1 runs the check in the USER'S working tree. The prover's own steps (scratch dir, worktree,
#     patch apply, proof file) never touch that tree, but the prover does not sandbox the check
#     itself: a check that writes files writes them there.
#   - Leg 2 runs on HEAD + patch: uncommitted edits are not carried into the scratch copy. A check
#     whose result depends on them reads `UNPROVABLE (scratch_baseline_fails)` rather than a PROVEN
#     the patch did not earn.
#   - A hand-forged proof file is not prevented. The gate makes the proof step a required, recorded
#     act, not a cryptographic one.
#   - A check that daemonizes a process outlives the watchdog's process-tree kill.

set -uo pipefail

PROG="prove-rule-check.sh"
PROOF_SCHEMA="rule-check-proof/1"
OUTPUT_BOUND=2000          # bytes of each stream shown per run
PATCH_SHOW_LINES=400       # patch lines shown before confirmation

check_set=0; CHECK=""
PATCH=""; PATCH_ABS=""
OUT=""; OUT_ABS=""
CONFIRM=0
TIMEOUT="${PROVE_RULE_CHECK_TIMEOUT:-60}"
TOP=""
SCRATCH=""; WT=""; WT_ATTEMPTED=0
NOW_EXIT="null"; BASE_EXIT="null"; CE_EXIT="null"
CHECK_SHA="null"; PATCH_SHA="null"
FINISHED=0
CUR_PID=""                 # the check currently running in the background, if any

say() { printf '%s\n' "$*"; }

# _sha256_stdin — the fallback chain rules-check.sh's _rc_sha256_file uses (shasum -a 256 →
# sha256sum → openssl dgst -sha256), reading stdin. Prints nothing when no tool works.
_sha256_stdin() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum 2>/dev/null | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 2>/dev/null | awk '{print $NF}'
  fi
}
_is_sha() { case "$1" in *[!0-9a-f]*|"") return 1 ;; esac; [ "${#1}" -eq 64 ]; }

# show_stream <label> <file> — bounded, indented.
show_stream() {
  local label="$1" f="$2" n
  [ -f "$f" ] || return 0
  n="$(wc -c < "$f" | tr -d '[:space:]')"
  if [ "${n:-0}" -eq 0 ]; then say "    $label: (empty)"; return 0; fi
  say "    $label:"
  head -c "$OUTPUT_BOUND" "$f" | sed 's/^/      /'
  printf '\n'
  [ "$n" -gt "$OUTPUT_BOUND" ] && say "      … ($((n - OUTPUT_BOUND)) more bytes not shown)"
  return 0
}

# descendants <pid> — every descendant pid, one per line (ps flags identical on BSD and procps).
descendants() {
  local c
  for c in $(ps -A -o pid= -o ppid= 2>/dev/null | awk -v p="$1" '$2 == p { print $1 }'); do
    echo "$c"; descendants "$c"
  done
}

# run_check <dir> <label> — runs the check in <dir> under the watchdog. Sets RUN_RC and RUN_TIMED_OUT;
# stdout/stderr land in $SCRATCH_LOGS/<label>.{out,err}.
run_check() {
  local dir="$1" label="$2" pid start
  RUN_RC=0; RUN_TIMED_OUT=0
  ( cd "$dir" && exec bash -c "$CHECK" ) </dev/null >"$SCRATCH_LOGS/$label.out" 2>"$SCRATCH_LOGS/$label.err" &
  pid=$!; CUR_PID="$pid"
  start="$(date +%s)"
  while kill -0 "$pid" 2>/dev/null; do
    if [ $(( $(date +%s) - start )) -ge "$TIMEOUT" ]; then RUN_TIMED_OUT=1; break; fi
    sleep 0.2
  done
  if [ "$RUN_TIMED_OUT" -eq 1 ]; then
    kill_tree "$pid"   # the watchdog kill
    wait "$pid" 2>/dev/null
    RUN_RC=124
  else
    wait "$pid"; RUN_RC=$?
  fi
  CUR_PID=""
  return 0
}

# kill_tree <pid> — TERM then KILL a check's whole process tree.
kill_tree() {
  local tree k
  tree="$( { echo "$1"; descendants "$1"; } | grep -E '^[0-9]+$')"
  for k in $tree; do kill -TERM "$k" 2>/dev/null; done
  sleep 1
  for k in $tree; do kill -KILL "$k" 2>/dev/null; done
  return 0
}

# cleanup_scratch — idempotent. Removes the scratch worktree and dir; never prunes globally.
cleanup_scratch() {
  [ -n "$SCRATCH" ] || return 0
  if [ "$WT_ATTEMPTED" -eq 1 ] && [ -n "$TOP" ]; then
    git -C "$TOP" worktree remove --force "$WT" >/dev/null 2>&1
  fi
  rm -rf "$SCRATCH" 2>/dev/null
  return 0
}

# scratch_gone — 0 only when the dir is gone AND no worktree entry names it. A worktree list that
# cannot be read is NOT evidence of absence (fail closed).
scratch_gone() {
  local listing
  [ -n "$SCRATCH" ] || return 0
  [ ! -e "$SCRATCH" ] || return 1
  if [ "$WT_ATTEMPTED" -eq 1 ]; then
    listing="$(git -C "$TOP" worktree list --porcelain 2>/dev/null)" || return 1
    printf '%s\n' "$listing" | grep -qxF "worktree $WT" && return 1
  fi
  return 0
}

write_proof() {
  local verdict="$1" reason="$2" dir tmp reason_json
  [ -n "$OUT_ABS" ] || return 0
  command -v jq >/dev/null 2>&1 || return 1
  if [ -n "$reason" ]; then reason_json="$(jq -n --arg r "$reason" '$r')" || return 1; else reason_json="null"; fi
  if [ -e "$OUT_ABS" ] && [ ! -f "$OUT_ABS" ]; then return 1; fi
  dir="$(dirname "$OUT_ABS")"
  tmp="$(mktemp "$dir/.prove-rule-check.XXXXXX" 2>/dev/null)" || return 1
  if ! jq -n \
      --arg schema "$PROOF_SCHEMA" \
      --arg verdict "$verdict" \
      --argjson reason "$reason_json" \
      --argjson check_sha256 "$CHECK_SHA" \
      --argjson counterexample_sha256 "$PATCH_SHA" \
      --argjson now_exit "$NOW_EXIT" \
      --argjson baseline_exit "$BASE_EXIT" \
      --argjson counterexample_exit "$CE_EXIT" \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{schema: $schema, verdict: $verdict, reason: $reason, check_sha256: $check_sha256,
        counterexample_sha256: $counterexample_sha256, now_exit: $now_exit,
        baseline_exit: $baseline_exit, counterexample_exit: $counterexample_exit, ts: $ts}' \
      > "$tmp" 2>/dev/null; then
    rm -f "$tmp"; return 1
  fi
  mv -f "$tmp" "$OUT_ABS" 2>/dev/null || { rm -f "$tmp"; return 1; }
  jq -e --arg v "$verdict" '.verdict == $v' "$OUT_ABS" >/dev/null 2>&1 || return 1
  return 0
}

# finish <VERDICT> [<reason>] — the ONE exit path: cleanup, verify-gone, proof, verdict line.
finish() {
  local verdict="$1" reason="${2:-}" rc
  FINISHED=1
  trap - INT TERM HUP
  cleanup_scratch
  if ! scratch_gone; then
    say "$PROG: the scratch copy could not be removed and verified gone: $SCRATCH"
    say "$PROG: remove the directory and run \`git worktree prune\` in $TOP (it also prunes any other stale entries)."
    verdict="UNPROVABLE"; reason="scratch_leak"
  fi
  if ! write_proof "$verdict" "$reason"; then
    say "$PROG: could not write the proof file: $OUT_ABS"
    verdict="UNPROVABLE"; reason="proof_write_failed"
    rm -f "$OUT_ABS" 2>/dev/null
  fi
  case "$verdict" in
    PROVEN) rc=0 ;;
    VACUOUS|FAILS_NOW) rc=1 ;;
    *) verdict="UNPROVABLE"; rc=2 ;;
  esac
  if [ -n "$reason" ]; then say "verdict: $verdict ($reason)"; else say "verdict: $verdict"; fi
  exit "$rc"
}

unprovable() { [ -n "${2:-}" ] && say "$PROG: $2"; finish UNPROVABLE "$1"; }

on_signal() {
  [ "$FINISHED" -eq 1 ] && exit 2
  [ -n "$CUR_PID" ] && kill_tree "$CUR_PID"
  unprovable interrupted "interrupted"
}
trap on_signal INT TERM HUP
trap 'if [ "$FINISHED" -eq 0 ]; then cleanup_scratch; fi' EXIT

# ---------------------------------------------------------------------------
# Arguments.
# ---------------------------------------------------------------------------
bad_args=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check)          if [ "$#" -ge 2 ]; then check_set=1; CHECK="$2"; shift 2; else bad_args="--check requires a value"; break; fi ;;
    --counterexample) if [ "$#" -ge 2 ]; then PATCH="$2"; shift 2; else bad_args="--counterexample requires a value"; break; fi ;;
    --out)            if [ "$#" -ge 2 ]; then OUT="$2"; shift 2; else bad_args="--out requires a value"; break; fi ;;
    --timeout)        if [ "$#" -ge 2 ]; then TIMEOUT="$2"; shift 2; else bad_args="--timeout requires a value"; break; fi ;;
    --confirm)        CONFIRM=1; shift ;;
    -h|--help)        grep -E '^# ' "$0" | sed -E 's/^# ?//'; exit 0 ;;
    *)                bad_args="unknown argument: $1"; break ;;
  esac
done

# The repo root is RESOLVED here, before anything can exit, because the --out containment check
# below needs it. Its verdicts (not_a_git_repo, no_head_commit) are still issued further down, after
# the argument checks, so the reason a run reports is unchanged.
TOP_ERR=""
TOP="$(git rev-parse --show-toplevel 2>/dev/null)" || TOP=""
if [ -n "$TOP" ]; then
  TOP="$(cd "$TOP" 2>/dev/null && pwd -P)" || { TOP=""; TOP_ERR="cannot resolve the repo root"; }
fi

# --out is resolved FIRST, so even a bad-args run leaves a proof file saying so — but OUT_ABS (the
# ONLY thing write_proof reads) is set only after the containment check has passed. Every exit
# before that point, including an interrupt, therefore writes no proof. An in-repo --out is HELD
# BACK (OUT_INSIDE=1) rather than refused here, so an earlier refusal still names its own reason;
# the out_inside_repo verdict itself is issued at its usual place below.
OUT_INSIDE=0
if [ -n "$OUT" ]; then
  out_dir="$(cd "$(dirname "$OUT")" 2>/dev/null && pwd -P)" || out_dir=""
  [ -n "$out_dir" ] || unprovable out_dir_missing "the --out directory does not exist: $(dirname "$OUT")"
  out_cand="$out_dir/$(basename "$OUT")"
  # An existing non-regular --out (a directory, a fifo) would swallow the atomic `mv` of the proof.
  if [ -e "$out_cand" ] && [ ! -f "$out_cand" ]; then
    unprovable out_not_a_file "--out exists and is not a regular file: $OUT"
  fi
  # Proof writing needs jq, and the proof's hashes need a sha256 tool — both checked before anything runs.
  command -v jq >/dev/null 2>&1 || unprovable jq_missing "jq is required to write a proof file"
  # Containment. Fail CLOSED: inside a repo whose root cannot be resolved, containment cannot be
  # shown, so the proof is held back as if it were inside.
  if [ -n "$TOP_ERR" ]; then
    OUT_INSIDE=1
  elif [ -n "$TOP" ]; then
    case "$out_cand/" in "$TOP/"*) OUT_INSIDE=1 ;; esac
  fi
  [ "$OUT_INSIDE" -eq 1 ] || OUT_ABS="$out_cand"
fi

[ -z "$bad_args" ] || unprovable bad_args "$bad_args"
[ "$check_set" -eq 1 ] && [ -n "$CHECK" ] || unprovable bad_args "--check <str> is required and must be non-empty"
[ -n "$PATCH" ] || unprovable bad_args "--counterexample <patch-file> is required"
case "$TIMEOUT" in ""|*[!0-9]*|0) unprovable bad_args "--timeout must be a positive integer (got: $TIMEOUT)" ;; esac

if [ ! -f "$PATCH" ] || [ ! -r "$PATCH" ]; then
  unprovable counterexample_unreadable "the counterexample patch is missing or unreadable: $PATCH"
fi
[ -s "$PATCH" ] || unprovable counterexample_empty "the counterexample patch is empty: $PATCH"
PATCH_ABS="$(cd "$(dirname "$PATCH")" && pwd -P)/$(basename "$PATCH")"

if [ -n "$OUT_ABS" ]; then
  h="$(printf '%s' "$CHECK" | _sha256_stdin)"
  _is_sha "$h" || unprovable sha256_unavailable "no working sha256 tool (shasum / sha256sum / openssl)"
  CHECK_SHA="\"$h\""
  h="$(_sha256_stdin < "$PATCH_ABS")"
  _is_sha "$h" || unprovable sha256_unavailable "no working sha256 tool (shasum / sha256sum / openssl)"
  PATCH_SHA="\"$h\""
fi

# TOP was resolved before the --out block; only its verdicts are issued here.
[ -z "$TOP_ERR" ] || unprovable not_a_git_repo "$TOP_ERR"
[ -n "$TOP" ] || unprovable not_a_git_repo "not inside a git working tree — no scratch worktree is possible"
git -C "$TOP" rev-parse --verify -q 'HEAD^{commit}' >/dev/null 2>&1 \
  || unprovable no_head_commit "the repo has no HEAD commit to copy into a scratch worktree"

[ "$OUT_INSIDE" -eq 0 ] \
  || unprovable out_inside_repo "--out must resolve OUTSIDE the repo working tree ($TOP) — the prover never writes into it"

# ---------------------------------------------------------------------------
# Display, then confirm. Nothing below this block runs without confirmation.
# ---------------------------------------------------------------------------
say "$PROG: candidate check (from argv — never read from .agent/rules/):"
say "    $CHECK"
say "$PROG: counterexample patch ($PATCH_ABS):"
plines="$(wc -l < "$PATCH_ABS" | tr -d '[:space:]')"
head -n "$PATCH_SHOW_LINES" "$PATCH_ABS" | sed 's/^/    | /'
[ "${plines:-0}" -gt "$PATCH_SHOW_LINES" ] && say "    | … ($((plines - PATCH_SHOW_LINES)) more lines not shown)"
say "$PROG: repo root: $TOP   timeout per run: ${TIMEOUT}s"

proceed=0
if [ "$CONFIRM" -eq 1 ]; then
  proceed=1
elif [ -t 0 ] && [ -t 1 ]; then
  printf 'Run this check on the current tree, then on a scratch copy with the patch applied? [y/N] '
  read -r reply || reply=""
  case "$reply" in y|Y|yes|YES) proceed=1 ;; *) proceed=0 ;; esac
fi
[ "$proceed" -eq 1 ] || unprovable needs_confirmation "not confirmed — nothing was run (pass --confirm, or answer y at a terminal)"

# ---------------------------------------------------------------------------
# Scratch dir (logs + the scratch worktree), physical path so it matches git's own record.
# ---------------------------------------------------------------------------
# An explicit template: a bare `mktemp -d` on macOS ignores $TMPDIR, so the scratch location would not
# be the caller's to choose (or to observe).
s_raw="$(mktemp -d "${TMPDIR:-/tmp}/prove-rule-check.XXXXXX" 2>/dev/null)" || s_raw=""
[ -n "$s_raw" ] || unprovable scratch_create_failed "mktemp -d failed"
SCRATCH="$(cd "$s_raw" && pwd -P)" || { SCRATCH="$s_raw"; unprovable scratch_create_failed "cannot resolve the scratch dir"; }
SCRATCH_LOGS="$SCRATCH/logs"
WT="$SCRATCH/wt"
mkdir -p "$SCRATCH_LOGS" || unprovable scratch_create_failed "cannot create $SCRATCH_LOGS"

# ---- Leg 1: the current tree ----------------------------------------------
run_check "$TOP" now
[ "$RUN_TIMED_OUT" -eq 1 ] && { say "now leg (current tree): timed out after ${TIMEOUT}s"; unprovable timeout; }
NOW_EXIT="$RUN_RC"
say "now leg (current tree, $TOP): exit $NOW_EXIT"
show_stream stdout "$SCRATCH_LOGS/now.out"
show_stream stderr "$SCRATCH_LOGS/now.err"
if [ "$NOW_EXIT" -ne 0 ]; then
  say "counterexample leg: not run (the check already fails on the current tree)"
  finish FAILS_NOW
fi

# ---- Leg 2: HEAD + counterexample in a scratch worktree -------------------
WT_ATTEMPTED=1
if ! git -C "$TOP" -c core.hooksPath=/dev/null worktree add --detach "$WT" HEAD >"$SCRATCH_LOGS/wt-add.log" 2>&1; then
  sed 's/^/    /' "$SCRATCH_LOGS/wt-add.log"
  unprovable worktree_add_failed "git worktree add failed"
fi

run_check "$WT" baseline
[ "$RUN_TIMED_OUT" -eq 1 ] && { say "baseline (scratch copy, before the patch): timed out after ${TIMEOUT}s"; unprovable timeout; }
BASE_EXIT="$RUN_RC"
say "baseline (scratch copy of HEAD, before the patch): exit $BASE_EXIT"
if [ "$BASE_EXIT" -ne 0 ]; then
  show_stream stdout "$SCRATCH_LOGS/baseline.out"
  show_stream stderr "$SCRATCH_LOGS/baseline.err"
  unprovable scratch_baseline_fails "the check fails on a clean copy of HEAD although it passes on the working tree — it depends on uncommitted state, so a failure after the patch could not be credited to the patch"
fi

if ! git -C "$WT" apply "$PATCH_ABS" >"$SCRATCH_LOGS/apply.log" 2>&1; then
  sed 's/^/    /' "$SCRATCH_LOGS/apply.log"
  unprovable patch_does_not_apply "the counterexample patch does not apply to HEAD"
fi
# `--ignored` too: a counterexample may legitimately edit a gitignored file the check reads.
if [ -z "$(git -C "$WT" status --porcelain --untracked-files=all --ignored 2>/dev/null)" ]; then
  unprovable patch_no_effect "the counterexample patch applied but changed nothing"
fi

run_check "$WT" counterexample
[ "$RUN_TIMED_OUT" -eq 1 ] && { say "counterexample leg: timed out after ${TIMEOUT}s"; unprovable timeout; }
CE_EXIT="$RUN_RC"
say "counterexample leg (scratch copy of HEAD + patch): exit $CE_EXIT"
show_stream stdout "$SCRATCH_LOGS/counterexample.out"
show_stream stderr "$SCRATCH_LOGS/counterexample.err"

if [ "$CE_EXIT" -eq 0 ]; then
  finish VACUOUS
fi
finish PROVEN
