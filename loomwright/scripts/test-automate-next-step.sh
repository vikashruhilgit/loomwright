#!/usr/bin/env bash
# test-automate-next-step.sh — self-test for automate-next-step.sh, the `/automate` loop's TAIL
# driver (automate-speed/06). UNCOUNTED by the doc-currency gate. One tally (`PASS: <n> FAIL: <m>`,
# exit 1 on any failure). Hermetic: every case runs in its own `mktemp -d` checkout (git init, HOME
# and the git identity sandboxed, a stub `gh` first on PATH — no network), the merge watcher, the
# notify and (in the golden legs) the run lock replaced by recorders through the driver's
# NEXT_STEP_WATCH_CMD / NEXT_STEP_NOTIFY_CMD / NEXT_STEP_LOCK_CMD.
#
# LEGS
#   G   GOLDEN PARITY (AC1). Every TAIL golden case under fixtures/automate-golden/ carries a
#       `next-step.results` file; the case's input.md + tree/ + gh.stub + setup are staged exactly
#       as test-automate-golden.sh stages them (the dot-<name> mapping, the stub table, the sourced
#       setup), the results file drives the driver, and the run file must equal the case's
#       expected.md byte for byte after the same normalisation (ISO ts → <TS>, scratch root →
#       <ROOT>, case dir → <CASE>, work dir → <TMP>). The required case list is asserted present.
#       next-step.results grammar (one directive per line, `#` / blank skipped; $RF $ROOT $AD
#       $RUN_ID expanded by eval):
#         env: <NAME>=<value> …    set (an empty value unsets) a driver env var for the calls below
#                                  (the driver's documented test seams: NEXT_STEP_FROM / _UNTIL /
#                                  _CLOSEOUT_OUT)
#         pre: <subcommand> <args> `bash automate-helpers.sh <subcommand> <args>` — a write the
#                                  segment's driver does not own (named, like a golden `loop:` line)
#         call: <args…>            `bash automate-next-step.sh "$RF" <args…>`
#         expect: <do>|none        the last call printed {"do":"<do>",…} (none = an UNTIL stop)
#   I   IDEMPOTENCY (AC2). After a case ends on an instruction, two calls with no --result print the
#       byte-identical instruction (the one the case's last call printed) and leave every file under
#       the scratch .supervisor/ (run file, sidecars, drafts) byte-unchanged. A replayed drain report
#       (the same report again after the terminal park) re-prints the park and writes nothing.
#   Q   QUESTION GATES (AC3). Under --non-interactive no call prints {"do":"ask"}: the AUT-WAIVE gate
#       parks escalated with escalation_cause validation_unrun, the park-first decisions record
#       pending_decisions: <n> instead of asking. Every ask any leg printed carries question,
#       header (a string, empty for human-only gates), options and cant_ask.
#   S   MERGE-SURFACE INVARIANT (AC4). The positive-grep file list (CLAUDE.md §Failure-Mode
#       Invariants) equals the base commit's list; the driver contributes no positive line and
#       calls `automate-helpers.sh gate-eval`.
#   C   CTX SHAPE (AC5). The ctx the driver wrote for gate-eval-merge carries exactly the six keys.
#   V   RUNNING SYSTEM (Validation 3). A scratch git repo (gh stubbed), the real run-lock.sh held as
#       PICK holds it, one item's tail from a post-drain run file (--result = a READY drain) to the
#       awaiting_merge park; the tail ## Progress lines are printed between `V3>` markers.
#   B   BRANCHES the golden segments do not reach: the whole --auto-merge MERGE chain in one run
#       (MERGE ⇒ drafts + pending record ⇒ SYNC ⇒ leftover kept ⇒ CHECK OFF ⇒ next PICK), AUT-WAIVE
#       answered Keep parked, an invalid answer / non-JSON --result (exit 2, nothing written), a refused
#       writer (surfaced, then retried by the next call) and the fix-now re-pass (spawn ⇒ re-drain ⇒
#       re-park with fix_now_reentered: true, fix-now never offered again). B5b/B6: a malformed drain
#       report (drain_result not READY|ESCALATED, a non-count or 20-digit items_processed / escalation_attempt, an unknown
#       escalation_cause, a non-hex sha, a multi-line progress_note — also as a spawn's answer) ⇒ exit 2, nothing printed,
#       .supervisor/ byte-unchanged. B7: a different drain report after a terminal park (## Current no
#       longer running) ⇒ exit 2, nothing written, the park re-prints. B8: the park-first READY park's
#       side-effect order on the driver itself — watcher armed < run lock released < park-ask-gate
#       (park-ask-gate recorded by a wrapper automate-helpers.sh beside a driver copy).
#       B9: item A's post-park ask pending, then the next PICK sets item B running (another PR) — A's
#       cant_ask / a no-result call ⇒ exit 2, nothing written; B's drain report starts B's own tail at
#       gate. B10: a 20-digit items_processed (a corrupt sidecar) at terminate ⇒ the limit_reached park.
#       B11: --non-interactive on the first call only — the flagless retry of a failed step still parks.
#       B12/B13: another item's draft with no Decision line (dismissed-pending prints `unknown`) at an
#       escalated park with a pending_decisions line / after a MERGE ⇒ `pending_decisions: unknown`, the
#       park (line, watcher, notify, lock release) / SYNC completes. B14a: the first drain report re-sent
#       after a fix-now spawn ⇒ the spawn re-prints, nothing written; a new re-drain report proceeds.
#       B14b: item A's drain report while item B runs, or a `pr` not ## Current's ⇒ exit 2, nothing written.
#       Q also enters the post-park decide step under --non-interactive: it parks, never asks.
#   D   DOC MIRROR: the schema doc's step list equals the driver's `case` arms, and its `do` table
#       equals the emitter's closed set.
#   M   MUTATION CONTROLS — each mutant gated non-empty + differs from the driver + `bash -n` (and
#       its anchor occurring exactly once); each must turn its leg red:
#         M2a gate-eval replaced by a direct awaiting_merge park   ⇒ G gate-eval-merge
#         M2b one unguarded merge-command line appended (built here at run time from pieces, so
#             this file never holds the positive literal on one line)  ⇒ S
#         MI  the no-result re-print replaced by a re-run of the last step  ⇒ I
#         MQ  the --non-interactive check dropped before an ask    ⇒ Q
#         MC  `"high_risk": false` added to the ctx                ⇒ C
#         MV* each drain-report guard dropped (drain_result, items_processed, escalation_cause, sha,
#             progress_note)                                       ⇒ B6
#         MQp both post-park --non-interactive guards of decide dropped (two edits) ⇒ Q (c)
#         MR  the running-status re-entry guard dropped            ⇒ B7
#         MO  ns_park arms the watcher only after the decide step (two edits; run file unchanged) ⇒ B8
#         MVbig the 1–9-digit count bound widened to any digits ⇒ B6 (the 20-digit report)
#         MB  the sidecar's item/PR binding dropped               ⇒ B9
#         MT  terminate's fail-CLOSED comparison reverted to a bare `-ge` ⇒ B10
#         MN  the persisted --non-interactive not read back       ⇒ B11
#         MPu ns_pending_write refuses `unknown` (iteration 2)    ⇒ B12 + B13
#         MRs the spawn branch's replay check dropped             ⇒ B14a
#         MRx the fresh-tail stale-report check dropped           ⇒ B14b
#
# ENV: NS_CASES="<a> <b>" runs only those golden cases (G only); NS_SKIP_MUTANTS=1 skips M.
# Bash 3.2 / BSD-userland safe; everything lives under one work dir removed in a trap.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
FIX="$HERE/fixtures/automate-golden"
DRIVER="$HERE/automate-next-step.sh"
H="$HERE/automate-helpers.sh"
TAB="$(printf '\t')"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass + 1)); }
no() { echo "FAIL: $1"; fail=$((fail + 1)); }

WORK="$(mktemp -d)" || { echo "FAIL: mktemp -d"; exit 1; }
WORK_P="$(cd "$WORK" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT
ASKS="$WORK/asks.log"; : > "$ASKS"

REQUIRED_CASES="escalated-park park-first-ready-park park-first-decisions-recorded
gate-validation-gate-unrun-escalated gate-validation-waive gate-eval-merge sync-closeout-no-trail
check-off-progress termination-limit-reached termination-queue-resolved
closeout-leftover-gate-non-interactive dismissed-findings-decision-step"

# --------------------------------------------------------------------------------------
# the scratch checkout — the shape of test-automate-golden.sh's run_case (stub gh, tree
# staging with the dot-<name> mapping, sourced setup, normalisation); kept in step with it
# --------------------------------------------------------------------------------------
GH_STUB_BODY='#!/usr/bin/env bash
all="$*"
if [ -n "${GOLDEN_GH_TABLE:-}" ] && [ -f "$GOLDEN_GH_TABLE" ]; then
  while IFS="	" read -r rc pat out || [ -n "$rc" ]; do
    case "$rc" in ""|"#"*) continue ;; esac
    # shellcheck disable=SC2254
    case "$all" in $pat) [ -n "$out" ] && printf "%s\n" "$out"; exit "$rc" ;; esac
  done < "$GOLDEN_GH_TABLE"
fi
echo "gh-stub: unmatched: $all" >&2
exit 1
'
REC_BODY='#!/usr/bin/env bash
printf "%s\n" "$*" >> "$NS_REC_LOG"
exit 0
'
stage_tree() { # <tree dir> <stage dir>
  local p b t
  cp -R "$1/." "$2/" || return 1
  find "$2" -depth -name 'dot-?*' > "$2.dots" || return 1
  while IFS= read -r p; do
    b="${p##*/}"; t="${p%/*}/.${b#dot-}"
    [ -e "$t" ] && return 1
    mv "$p" "$t" || return 1
  done < "$2.dots"
}
norm() { # <file>
  local c
  c="$(cat "$1"; printf x)"; c="${c%x}"
  c="${c//"$CASE_ROOT_P"/<ROOT>}"; c="${c//"$CASE_ROOT"/<ROOT>}"
  c="${c//"$CASE_DIR_P"/<CASE>}"; c="${c//"$CASE_DIR"/<CASE>}"
  c="${c//"$WORK_P"/<TMP>}"; c="${c//"$WORK"/<TMP>}"
  printf '%s' "$c" | sed -E 's/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z/<TS>/g'
}
GIT_ENV="GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=golden GIT_AUTHOR_EMAIL=golden@example.invalid GIT_COMMITTER_NAME=golden GIT_COMMITTER_EMAIL=golden@example.invalid GIT_AUTHOR_DATE=2026-10-13T12:00:00Z GIT_COMMITTER_DATE=2026-10-13T12:00:00Z"

# new_scratch <case dir> — sets CASE_DIR CASE_ROOT CASE_ROOT_P CASE_DIR_P CASE_RF CASE_RUN CASE_BIN CASE_HOME
new_scratch() {
  local cd_="$1" cw
  CASE_RUN="$(sed -n 's/^run: *\([^ ]*\).*/\1/p' "$cd_/source" | head -n1)"
  [ -n "$CASE_RUN" ] || return 1
  cw="$(mktemp -d "$WORK/case.XXXXXX")" || return 1
  CASE_DIR="$cw"; CASE_ROOT="$cw/repo"; CASE_BIN="$cw/bin"; CASE_HOME="$cw/home"
  mkdir -p "$CASE_ROOT/.supervisor/automate" "$CASE_BIN" "$CASE_HOME"
  CASE_ROOT_P="$(cd "$CASE_ROOT" && pwd -P)"; CASE_DIR_P="$(cd "$cw" && pwd -P)"
  printf '%s' "$GH_STUB_BODY" > "$CASE_BIN/gh"; chmod +x "$CASE_BIN/gh"
  printf '%s' "$REC_BODY" > "$CASE_BIN/rec"; chmod +x "$CASE_BIN/rec"
  : > "$cw/rec.log"
  CASE_RF="$CASE_ROOT/.supervisor/automate/$CASE_RUN.md"
  ( cd "$CASE_ROOT" && export HOME="$CASE_HOME" && eval "export $GIT_ENV" && git init -q . && git symbolic-ref HEAD refs/heads/main ) \
    >/dev/null 2>&1 || return 1
  cp "$cd_/input.md" "$CASE_RF" || return 1
  if [ -d "$cd_/tree" ]; then
    mkdir "$cw/tree" && stage_tree "$cd_/tree" "$cw/tree" 2>/dev/null && cp -R "$cw/tree/." "$CASE_ROOT/" || return 1
  fi
  if [ -f "$cd_/setup" ]; then
    ( cd "$CASE_ROOT" && export HOME="$CASE_HOME" && eval "export $GIT_ENV" && ROOT="$CASE_ROOT" RF="$CASE_RF" \
        RUN_ID="$CASE_RUN" && . "$cd_/setup" ) >"$cw/setup.log" 2>&1 || return 1
  fi
  CASE_GH="$cd_/gh.stub"
  return 0
}

# in_case <driver> <seam env file> <command…> — run one command in the case's sandbox
in_case() {
  local drv="$1" seams="$2"; shift 2
  (
    cd "$CASE_ROOT" || exit 98
    unset LOOMWRIGHT_GH_BIN LOOMWRIGHT_HOLDER_PID NEXT_STEP_FROM NEXT_STEP_UNTIL NEXT_STEP_CLOSEOUT_OUT
    export HOME="$CASE_HOME" PATH="$CASE_BIN:$PATH" GOLDEN_GH_TABLE="$CASE_GH" NS_REC_LOG="$CASE_DIR/rec.log"
    eval "export $GIT_ENV"
    export NEXT_STEP_WATCH_CMD="$CASE_BIN/rec watch" NEXT_STEP_NOTIFY_CMD="$CASE_BIN/rec notify"
    [ -n "${NS_REAL_LOCK:-}" ] || export NEXT_STEP_LOCK_CMD="$CASE_BIN/rec lock"
    export NEXT_STEP_LOCK_RETRY_SECONDS=0
    export RF="$CASE_RF" ROOT="$CASE_ROOT" AD="$CASE_ROOT/.supervisor/automate" RUN_ID="$CASE_RUN" D="$drv" H="$H"
    local n v
    while IFS= read -r n; do
      [ -n "$n" ] || continue
      v="${n#*=}"; n="${n%%=*}"
      if [ -n "$v" ]; then export "$n=$v"; else unset "$n"; fi
    done < "$seams"
    "$@"
  ) < /dev/null
}

# drive <case dir> <driver> <results file> — runs the directives; sets LAST_OUT (last call's stdout)
# and DRIVE_ERR (non-empty on a broken expectation); every printed ask goes to $ASKS
drive() {
  local cd_="$1" drv="$2" rs="$3" line rest k=0 o e rc seams want got w nm
  local RF="$CASE_RF" ROOT="$CASE_ROOT" AD="$CASE_ROOT/.supervisor/automate" RUN_ID="$CASE_RUN"
  seams="$CASE_DIR/seams.env"; : > "$seams"; LAST_OUT=""; DRIVE_ERR=""
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ""|"#"*) continue ;; esac
    rest="${line#*:}"; rest="${rest# }"
    case "$line" in
      "env: "*)
        eval "set -- $rest"
        for w in "$@"; do
          nm="${w%%=*}"; awk -v n="$nm" -F= '$1 != n' "$seams" > "$seams.t"; mv "$seams.t" "$seams"; printf '%s\n' "$w" >> "$seams"
        done ;;
      "pre: "*)
        eval "set -- $rest"
        in_case "$drv" "$seams" bash "$H" "$@" >/dev/null 2>"$CASE_DIR/pre.err" || DRIVE_ERR="${DRIVE_ERR}pre failed: $rest; " ;;
      "call:"*)
        k=$((k + 1)); o="$CASE_DIR/call$k.out"; e="$CASE_DIR/call$k.err"
        eval "set -- $rest"
        in_case "$drv" "$seams" bash "$drv" "$CASE_RF" "$@" > "$o" 2> "$e"
        rc=$?
        LAST_OUT="$(cat "$o")"
        [ "$rc" -eq 0 ] || DRIVE_ERR="${DRIVE_ERR}call $k exit $rc ($(head -n 3 "$e" | tr '\n' ' ')); "
        grep '"do":"ask"' "$o" | sed "s|^|$(basename "$cd_")$TAB|" >> "$ASKS" ;;
      "expect: "*)
        want="$rest"
        if [ -z "$LAST_OUT" ]; then got=none; else got="$(printf '%s' "$LAST_OUT" | jq -r '.do // "?"' 2>/dev/null)"; fi
        [ "$got" = "$want" ] || DRIVE_ERR="${DRIVE_ERR}call $k printed do=$got, want $want; " ;;
      *) DRIVE_ERR="${DRIVE_ERR}bad directive: $line; " ;;
    esac
  done < "$rs"
}

# golden_case <case> <driver> — 0 when the run file matches expected.md (and every expectation held)
golden_case() {
  local c="$1" drv="$2" cd_="$FIX/$1"
  [ -f "$cd_/next-step.results" ] || { GC_MSG="no next-step.results"; return 1; }
  new_scratch "$cd_" || { GC_MSG="scratch checkout not built"; return 1; }
  drive "$cd_" "$drv" "$cd_/next-step.results"
  norm "$CASE_RF" > "$CASE_DIR/a.md"; norm "$cd_/expected.md" > "$CASE_DIR/x.md"
  if ! cmp -s "$CASE_DIR/a.md" "$CASE_DIR/x.md"; then
    GC_MSG="run file differs${DRIVE_ERR:+ [$DRIVE_ERR]}"; GC_DIFF="$(diff -u "$CASE_DIR/x.md" "$CASE_DIR/a.md")"; return 1
  fi
  [ -z "$DRIVE_ERR" ] || { GC_MSG="$DRIVE_ERR"; GC_DIFF=""; return 1; }
  return 0
}

snapshot() { ( cd "$CASE_ROOT/.supervisor" && find . -type f | env LC_ALL=C sort | while IFS= read -r f; do cksum "$f"; done ); }

# leg_idem <case> <driver> — 0 when two no-result calls re-print the case's last instruction and write nothing
leg_idem() {
  local c="$1" drv="$2" s0 s1 s2 o1 o2
  golden_case "$c" "$drv" || { LEG_MSG="case run: $GC_MSG"; return 1; }
  [ -n "$LAST_OUT" ] || { LEG_MSG="the case ends on no instruction"; return 1; }
  s0="$(snapshot)"
  : > "$CASE_DIR/seams.none"
  o1="$(in_case "$drv" "$CASE_DIR/seams.none" bash "$drv" "$CASE_RF" 2>/dev/null)"; s1="$(snapshot)"
  o2="$(in_case "$drv" "$CASE_DIR/seams.none" bash "$drv" "$CASE_RF" 2>/dev/null)"; s2="$(snapshot)"
  [ -n "$o1" ] && [ "$o1" = "$o2" ] || { LEG_MSG="the two no-result calls printed different instructions"; return 1; }
  [ "$o1" = "$LAST_OUT" ] || { LEG_MSG="the no-result call did not re-print the pending instruction"; return 1; }
  [ "$s0" = "$s1" ] && [ "$s1" = "$s2" ] || { LEG_MSG="run file unchanged on the second call: NO — .supervisor/ changed"; return 1; }
  return 0
}

# leg_cantask <driver> — 0 when every --non-interactive question gate takes its can't-ask outcome
leg_cantask() {
  local drv="$1" rs
  : > "$WORK/asks.q"
  # (a) AUT-WAIVE: the golden case runs --non-interactive
  ASKS_SAVE="$ASKS"; ASKS="$WORK/asks.q"
  golden_case gate-validation-gate-unrun-escalated "$drv" || { ASKS="$ASKS_SAVE"; LEG_MSG="AUT-WAIVE case: $GC_MSG"; return 1; }
  printf '%s' "$LAST_OUT" | jq -e '.do == "park" and .escalation_cause == "validation_unrun"' >/dev/null 2>&1 \
    || { ASKS="$ASKS_SAVE"; LEG_MSG="AUT-WAIVE: not the escalated validation_unrun park: $LAST_OUT"; return 1; }
  # (b) the decisions at a READY park, --non-interactive: recorded, never asked
  new_scratch "$FIX/park-first-ready-park" || { ASKS="$ASKS_SAVE"; LEG_MSG="scratch"; return 1; }
  rs="$CASE_DIR/nonint.results"
  printf '%s\n' "call: --non-interactive --result '{\"drain_result\":\"READY\",\"termination_reason\":\"converged\",\"ready_sha\":\"028cbed6b8e3588f93731d6b862f0bc334de1d96\"}'" "expect: park" > "$rs"
  drive "$FIX/park-first-ready-park" "$drv" "$rs"
  ASKS="$ASKS_SAVE"
  [ -z "$DRIVE_ERR" ] || { LEG_MSG="decisions: $DRIVE_ERR"; return 1; }
  grep -qxF -- '- pending_decisions: 2 | fix_now_reentered: false' "$CASE_RF" \
    || { LEG_MSG="decisions: pending_decisions: 2 not recorded"; return 1; }
  grep -q 'dismissed decisions asked after the park' "$CASE_RF" && { LEG_MSG="decisions: a post-park ask line was written"; return 1; }
  [ ! -s "$WORK/asks.q" ] || { LEG_MSG="an ask was printed under --non-interactive: $(head -n 1 "$WORK/asks.q")"; return 1; }
  # (c) the post-park decide step entered under --non-interactive (an item already parked awaiting_merge
  # with undecided drafts): it parks, never asks, leaves the run file byte-unchanged (its drafts stay
  # undecided — the park already recorded pending_decisions)
  ASKS="$WORK/asks.q"
  new_scratch "$FIX/park-first-decisions-recorded" || { ASKS="$ASKS_SAVE"; LEG_MSG="scratch (c)"; return 1; }
  printf '%s\n' "env: NEXT_STEP_FROM=decide" "call: --non-interactive" "expect: park" > "$CASE_DIR/nonint-post.results"
  drive "$FIX/park-first-decisions-recorded" "$drv" "$CASE_DIR/nonint-post.results"
  ASKS="$ASKS_SAVE"
  [ -z "$DRIVE_ERR" ] || { LEG_MSG="post-park decide: $DRIVE_ERR"; return 1; }
  [ ! -s "$WORK/asks.q" ] || { LEG_MSG="post-park decide asked under --non-interactive: $(head -n 1 "$WORK/asks.q")"; return 1; }
  cmp -s "$FIX/park-first-decisions-recorded/input.md" "$CASE_RF" || { LEG_MSG="post-park decide: the run file was written"; return 1; }
  return 0
}

# leg_badreport <driver> — 0 when every malformed drain report exits 2, prints nothing and leaves every
# file under .supervisor/ byte-unchanged (a running item: the reports would otherwise start its tail)
BAD_REPORTS='{"drain_result":"BOGUS","termination_reason":"converged","ready_sha":"028cbed6b8e3588f93731d6b862f0bc334de1d96"}
{"drain_result":"ready","termination_reason":"converged","ready_sha":"028cbed6b8e3588f93731d6b862f0bc334de1d96"}
{"drain_result":"escalated","termination_reason":"bound_hit"}
{"drain_result":"died"}
{"drain_result":"superseded_by_merge","termination_reason":"converged"}
{"drain_result":"READY","termination_reason":"converged","ready_sha":"028cbed6b8e3588f93731d6b862f0bc334de1d96","items_processed":"two"}
{"drain_result":"READY","termination_reason":"converged","ready_sha":"028cbed6b8e3588f93731d6b862f0bc334de1d96","items_processed":"99999999999999999999"}
{"drain_result":"ESCALATED","termination_reason":"bound_hit","escalation_cause":"check_red","escalation_attempt":"99999999999999999999"}
{"drain_result":"ESCALATED","termination_reason":"bound_hit","escalation_cause":"bogus_cause"}
{"drain_result":"READY","termination_reason":"converged","ready_sha":"zz|028cbed"}
{"drain_result":"READY","termination_reason":"converged","ready_sha":"028cbed6b8e3588f93731d6b862f0bc334de1d96","progress_note":"one\n## Status: done"}'
leg_badreport() {
  local drv="$1" s0 r out rc
  new_scratch "$FIX/park-first-ready-park" || { LEG_MSG="scratch"; return 1; }
  : > "$CASE_DIR/seams.none"; s0="$(snapshot)"
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    out="$(in_case "$drv" "$CASE_DIR/seams.none" bash "$drv" "$CASE_RF" --result "$r" 2>/dev/null)"; rc=$?
    [ "$rc" = 2 ] && [ -z "$out" ] && [ "$s0" = "$(snapshot)" ] \
      || { LEG_MSG="$r ⇒ exit $rc, printed '${out:0:60}', .supervisor/ $([ "$s0" = "$(snapshot)" ] && echo unchanged || echo CHANGED)"; return 1; }
  done <<EOF
$BAD_REPORTS
EOF
  return 0
}

# leg_reentry <driver> — 0 when a DIFFERENT drain report after escalated-park's terminal park exits 2,
# writes nothing, and the no-result call still re-prints that park
leg_reentry() {
  local drv="$1" last s0 out rc again
  golden_case escalated-park "$drv" || { LEG_MSG="escalated-park did not run: $GC_MSG"; return 1; }
  last="$LAST_OUT"; s0="$(snapshot)"; : > "$CASE_DIR/seams.none"
  out="$(in_case "$drv" "$CASE_DIR/seams.none" bash "$drv" "$CASE_RF" \
    --result '{"drain_result":"ESCALATED","termination_reason":"bound_hit","escalation_cause":"check_red_unrelated","escalation_check":"ci","escalation_sha":"9999999"}' 2>/dev/null)"; rc=$?
  again="$(in_case "$drv" "$CASE_DIR/seams.none" bash "$drv" "$CASE_RF" 2>/dev/null)"
  [ "$rc" = 2 ] && [ -z "$out" ] && [ "$s0" = "$(snapshot)" ] && [ "$again" = "$last" ] \
    || { LEG_MSG="re-entry after the park ⇒ exit $rc, printed '${out:0:60}', .supervisor/ $([ "$s0" = "$(snapshot)" ] && echo unchanged || echo CHANGED)"; return 1; }
  return 0
}

# leg_binding <driver> — B9: item A's post-park AUT-DISMISS ask is pending when its PR merges and the next
# PICK sets item B running (PR 999). Nothing of A's pending state may reach B: the stale ask's can't-ask
# answer and a no-result call ⇒ exit 2, nothing written; B's own drain report starts B's tail at gate
# (its own validation-gate line — B's item file is absent here, so `unrun` — and its own escalated park)
B9_ITEM=.supervisor/requirements/parallel-automate/18-backlog-board-and-right-size.md
B9_PR=https://github.com/vikashruhilgit/loomwright/pull/999
leg_binding() {
  local drv="$1" s0 o rc o2 rc2 cut_
  new_scratch "$FIX/park-first-ready-park" || { LEG_MSG="scratch"; return 1; }
  printf '%s\n' "call: --result '{\"drain_result\":\"READY\",\"termination_reason\":\"converged\",\"ready_sha\":\"028cbed6b8e3588f93731d6b862f0bc334de1d96\"}'" "expect: ask" \
    "pre: current-set \"\$RF\" --item $B9_ITEM --status running --pr $B9_PR --branch feature/pa18 --pause-reason null" > "$CASE_DIR/b9.results"
  drive "$FIX/park-first-ready-park" "$drv" "$CASE_DIR/b9.results"
  [ -z "$DRIVE_ERR" ] || { LEG_MSG="setup: $DRIVE_ERR"; return 1; }
  s0="$(snapshot)"; : > "$CASE_DIR/seams.none"
  o="$(in_case "$drv" "$CASE_DIR/seams.none" bash "$drv" "$CASE_RF" --result '{"cant_ask":true}' 2>/dev/null)"; rc=$?
  o2="$(in_case "$drv" "$CASE_DIR/seams.none" bash "$drv" "$CASE_RF" 2>/dev/null)"; rc2=$?
  [ "$rc" = 2 ] && [ -z "$o" ] && [ "$rc2" = 2 ] && [ -z "$o2" ] && [ "$s0" = "$(snapshot)" ] \
    || { LEG_MSG="A's stale ask consumed on B: cant_ask ⇒ exit $rc '${o:0:70}'; no-result ⇒ exit $rc2 '${o2:0:50}'; .supervisor/ $([ "$s0" = "$(snapshot)" ] && echo unchanged || echo CHANGED)"; return 1; }
  cut_="$(wc -l < "$CASE_RF" | tr -d " ")"
  # B's own DRAIN bookkeeping (model-side, before the driver call) opens B's tail segment
  in_case "$drv" "$CASE_DIR/seams.none" bash "$H" progress-append "$CASE_RF" "2026-10-16T08:00:00Z owned drain started — /review-pr $B9_PR --until-mergeable --no-auto-postmortem @ 9999999" >/dev/null 2>&1 \
    && in_case "$drv" "$CASE_DIR/seams.none" bash "$H" progress-append "$CASE_RF" "2026-10-16T08:10:00Z drain READY (converged, 1 round)" >/dev/null 2>&1 \
    || { LEG_MSG="B's drain lines not appended"; return 1; }
  o="$(in_case "$drv" "$CASE_DIR/seams.none" bash "$drv" "$CASE_RF" --non-interactive \
    --result '{"drain_result":"READY","termination_reason":"converged","ready_sha":"9999999"}' 2>"$CASE_DIR/b9.err")"; rc=$?
  tail -n "+$((cut_ + 1))" "$CASE_RF" > "$CASE_DIR/b9.new"
  [ "$rc" = 0 ] && printf '%s' "$o" | jq -e --arg p "$B9_PR" '.do == "park" and .pr == $p and .pause_reason == "escalated"' >/dev/null 2>&1 \
    && grep -qF -- "- validation-gate: unrun — item file unreadable: $B9_ITEM" "$CASE_DIR/b9.new" \
    && grep -qF "parked escalated $B9_PR — validation_unrun" "$CASE_DIR/b9.new" \
    && grep -qF -- "- item: $B9_ITEM | status: escalated |" "$CASE_RF" \
    || { LEG_MSG="B's drain report ⇒ exit $rc '${o:0:120}' $(head -n 2 "$CASE_DIR/b9.err" | tr '\n' ' ') new lines: $(tr "\n" ";" < "$CASE_DIR/b9.new" | cut -c1-600)"; return 1; }
  return 0
}

# leg_bigcount <driver> — B10: termination-limit-reached from terminate with a 20-digit items_processed in the
# sidecar (out of a report's reach — ns_check_report refuses it there, B6 — so seeded as a corrupt sidecar)
leg_bigcount() {
  local drv="$1" o rc
  new_scratch "$FIX/termination-limit-reached" || { LEG_MSG="scratch"; return 1; }
  printf '{"items_processed":"99999999999999999999"}\n' > "$CASE_ROOT/.supervisor/automate/$CASE_RUN.next-step.json"
  printf 'NEXT_STEP_FROM=terminate\n' > "$CASE_DIR/seams.t"
  o="$(in_case "$drv" "$CASE_DIR/seams.t" bash "$drv" "$CASE_RF" 2>"$CASE_DIR/b10.err")"; rc=$?
  [ "$rc" = 0 ] && printf '%s' "$o" | jq -e '.do == "park" and .pause_reason == "limit_reached"' >/dev/null 2>&1 \
    && grep -qxF -- '- pause_reason: limit_reached' "$CASE_RF" \
    || { LEG_MSG="exit $rc, printed '${o:0:120}' $(head -n 2 "$CASE_DIR/b10.err" | tr '\n' ' ')"; return 1; }
  return 0
}
# leg_nonint_persist <driver> — B11: B4's refused writer, but the retry carries NO --non-interactive: the
# persisted flag keeps the AUT-WAIVE gate closed (escalated park, golden run file), never an ask
leg_nonint_persist() {
  local drv="$1" rc retry
  new_scratch "$FIX/gate-validation-gate-unrun-escalated" || { LEG_MSG="scratch"; return 1; }
  cp "$CASE_RF" "$CASE_DIR/rf.keep"; sed '1d' "$CASE_DIR/rf.keep" > "$CASE_RF"
  : > "$CASE_DIR/seams.none"
  in_case "$drv" "$CASE_DIR/seams.none" bash "$drv" "$CASE_RF" --non-interactive \
    --result '{"drain_result":"READY","termination_reason":"converged","ready_sha":"06ce6f59617b3b515a1950dbeb8b13630b54525c"}' >/dev/null 2>&1; rc=$?
  cp "$CASE_DIR/rf.keep" "$CASE_RF"
  retry="$(in_case "$drv" "$CASE_DIR/seams.none" bash "$drv" "$CASE_RF" 2>/dev/null)"
  norm "$CASE_RF" > "$CASE_DIR/a.md"; norm "$FIX/gate-validation-gate-unrun-escalated/expected.md" > "$CASE_DIR/x.md"
  [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ] && printf '%s' "$retry" | jq -e '.do == "park" and .escalation_cause == "validation_unrun"' >/dev/null 2>&1 \
    && cmp -s "$CASE_DIR/a.md" "$CASE_DIR/x.md" \
    || { LEG_MSG="first call exit $rc; flagless retry printed '${retry:0:120}'"; return 1; }
  return 0
}

# bad_draft — another item's dismissed draft with no `- **Decision:**` line in the case checkout: dismissed-pending's
# documented `unknown` (run-wide, so ANY item's malformed draft yields it)
bad_draft() {
  mkdir -p "$CASE_ROOT/.supervisor/requirements/proposed" \
    && printf '# A malformed draft\n\n- **Item:** .supervisor/requirements/other/09-other.md\n' \
      > "$CASE_ROOT/.supervisor/requirements/proposed/$CASE_RUN--other-09--dismissed-abc12345.md"
}
# leg_unknown_park <driver> — B12: escalated park with a `pending_decisions:` line already in ## Current and
# another item's malformed draft ⇒ the park completes (exit 0, park printed, `pending_decisions: unknown`,
# the park Progress line, watcher + notify + run-lock release all recorded)
leg_unknown_park() {
  local drv="$1" o rc
  new_scratch "$FIX/escalated-park" || { LEG_MSG="scratch"; return 1; }
  awk '{ print } /^- pause_reason: null$/ { print "- pending_decisions: 0 | fix_now_reentered: false" }' "$CASE_RF" > "$CASE_RF.t" \
    && mv "$CASE_RF.t" "$CASE_RF" && bad_draft || { LEG_MSG="setup"; return 1; }
  : > "$CASE_DIR/seams.none"
  o="$(in_case "$drv" "$CASE_DIR/seams.none" bash "$drv" "$CASE_RF" \
    --result '{"drain_result":"ESCALATED","termination_reason":"bound_hit","escalation_cause":"check_red_unrelated","escalation_check":"ci","escalation_sha":"247e203"}' 2>"$CASE_DIR/b12.err")"; rc=$?
  [ "$rc" = 0 ] && printf '%s' "$o" | jq -e '.do == "park" and .pause_reason == "escalated" and .pending_decisions == "unknown"' >/dev/null 2>&1 \
    && grep -qxF -- '- pending_decisions: unknown | fix_now_reentered: false' "$CASE_RF" \
    && grep -qF 'parked escalated https://github.com/vikashruhilgit/loomwright/pull/126 — check_red_unrelated' "$CASE_RF" \
    && grep -q '^watch ' "$CASE_DIR/rec.log" && grep -q '^notify escalated ' "$CASE_DIR/rec.log" && grep -q '^lock release ' "$CASE_DIR/rec.log" \
    || { LEG_MSG="exit $rc '${o:0:120}' $(head -n 2 "$CASE_DIR/b12.err" | tr '\n' ' ') rec: $(tr '\n' ';' < "$CASE_DIR/rec.log" | cut -c1-200)"; return 1; }
  return 0
}
# leg_unknown_merge <driver> — B13: the --auto-merge MERGE path with another item's malformed draft ⇒
# `pending_decisions: unknown` recorded and the chain goes on to SYNC (the leftover ask), never a failure
leg_unknown_merge() {
  local drv="$1"
  new_scratch "$FIX/gate-eval-merge" && bad_draft || { LEG_MSG="scratch"; return 1; }
  printf '%s\n' "call: --result '{\"drain_result\":\"READY\",\"termination_reason\":\"converged\",\"ready_sha\":\"eb0e123e1584184cca438b53ed5145da79825acc\"}'" \
    "expect: ask" > "$CASE_DIR/b13.results"
  drive "$FIX/gate-eval-merge" "$drv" "$CASE_DIR/b13.results"
  [ -z "$DRIVE_ERR" ] && grep -qxF -- '- pending_decisions: unknown | fix_now_reentered: false' "$CASE_RF" \
    && printf '%s' "$LAST_OUT" | jq -e '.gate == "AUT-LEFTOVER"' >/dev/null 2>&1 \
    || { LEG_MSG="$DRIVE_ERR last '${LAST_OUT:0:100}' $(grep -F pending_decisions "$CASE_RF")"; return 1; }
  return 0
}
# leg_spawn_replay <driver> — B14a: after a fix-now spawn, the FIRST drain report re-sent (pre-fix ready_sha)
# re-prints the spawn and writes nothing; the genuine re-drain report (a new ready_sha) then proceeds
leg_spawn_replay() {
  local drv="$1" spawn s0 o rc o2
  new_scratch "$FIX/dismissed-findings-decision-step" || { LEG_MSG="scratch"; return 1; }
  printf '%s\n' "call: --result '{\"drain_result\":\"READY\",\"termination_reason\":\"converged\",\"ready_sha\":\"0000000\"}'" \
    "expect: ask" "call: --result '{\"answers\":[\"Fix now on this PR\"]}'" "expect: spawn" > "$CASE_DIR/b14.results"
  drive "$FIX/dismissed-findings-decision-step" "$drv" "$CASE_DIR/b14.results"
  [ -z "$DRIVE_ERR" ] || { LEG_MSG="setup: $DRIVE_ERR"; return 1; }
  spawn="$LAST_OUT"; s0="$(snapshot)"; : > "$CASE_DIR/seams.none"
  o="$(in_case "$drv" "$CASE_DIR/seams.none" bash "$drv" "$CASE_RF" \
    --result '{"drain_result":"READY","termination_reason":"converged","ready_sha":"0000000"}' 2>/dev/null)"; rc=$?
  [ "$rc" = 0 ] && [ "$o" = "$spawn" ] && [ "$s0" = "$(snapshot)" ] \
    || { LEG_MSG="replayed first report ⇒ exit $rc '${o:0:100}', .supervisor/ $([ "$s0" = "$(snapshot)" ] && echo unchanged || echo CHANGED)"; return 1; }
  o2="$(in_case "$drv" "$CASE_DIR/seams.none" bash "$drv" "$CASE_RF" \
    --result '{"drain_result":"READY","termination_reason":"converged","ready_sha":"1111111"}' 2>/dev/null)"; rc=$?
  [ "$rc" = 0 ] && printf '%s' "$o2" | jq -e '.do == "ask"' >/dev/null 2>&1 \
    || { LEG_MSG="the genuine re-drain report ⇒ exit $rc '${o2:0:100}'"; return 1; }
  return 0
}
# leg_cross_replay <driver> — B14b: item A's drain report re-sent while ## Current names item B (running) ⇒
# exit 2, nothing written; a report whose `pr` is not ## Current's ⇒ exit 2; B's own report then starts B's tail
leg_cross_replay() {
  local drv="$1" s0 o rc o2 rc2 o3 rc3
  new_scratch "$FIX/park-first-ready-park" || { LEG_MSG="scratch"; return 1; }
  printf '%s\n' "call: --result '{\"drain_result\":\"READY\",\"termination_reason\":\"converged\",\"ready_sha\":\"028cbed6b8e3588f93731d6b862f0bc334de1d96\"}'" "expect: ask" \
    "pre: current-set \"\$RF\" --item $B9_ITEM --status running --pr $B9_PR --branch feature/pa18 --pause-reason null" > "$CASE_DIR/b14b.results"
  drive "$FIX/park-first-ready-park" "$drv" "$CASE_DIR/b14b.results"
  [ -z "$DRIVE_ERR" ] || { LEG_MSG="setup: $DRIVE_ERR"; return 1; }
  s0="$(snapshot)"; : > "$CASE_DIR/seams.none"
  o="$(in_case "$drv" "$CASE_DIR/seams.none" bash "$drv" "$CASE_RF" --non-interactive \
    --result '{"drain_result":"READY","termination_reason":"converged","ready_sha":"028cbed6b8e3588f93731d6b862f0bc334de1d96"}' 2>/dev/null)"; rc=$?
  o2="$(in_case "$drv" "$CASE_DIR/seams.none" bash "$drv" "$CASE_RF" --non-interactive \
    --result '{"drain_result":"READY","termination_reason":"converged","ready_sha":"9999999","pr":"https://github.com/vikashruhilgit/loomwright/pull/1"}' 2>/dev/null)"; rc2=$?
  [ "$rc" = 2 ] && [ -z "$o" ] && [ "$rc2" = 2 ] && [ -z "$o2" ] && [ "$s0" = "$(snapshot)" ] \
    || { LEG_MSG="A's report on B ⇒ exit $rc '${o:0:80}'; foreign pr ⇒ exit $rc2 '${o2:0:60}'; .supervisor/ $([ "$s0" = "$(snapshot)" ] && echo unchanged || echo CHANGED)"; return 1; }
  o3="$(in_case "$drv" "$CASE_DIR/seams.none" bash "$drv" "$CASE_RF" --non-interactive \
    --result "{\"drain_result\":\"READY\",\"termination_reason\":\"converged\",\"ready_sha\":\"9999999\",\"pr\":\"$B9_PR\"}" 2>/dev/null)"; rc3=$?
  [ "$rc3" = 0 ] && printf '%s' "$o3" | jq -e --arg p "$B9_PR" '.do == "park" and .pr == $p' >/dev/null 2>&1 \
    || { LEG_MSG="B's own report ⇒ exit $rc3 '${o3:0:100}'"; return 1; }
  # A's report again, now during B's terminal park: still refused (B's tail kept the stale key)
  o="$(in_case "$drv" "$CASE_DIR/seams.none" bash "$drv" "$CASE_RF" \
    --result '{"drain_result":"READY","termination_reason":"converged","ready_sha":"028cbed6b8e3588f93731d6b862f0bc334de1d96"}' 2>/dev/null)"; rc=$?
  [ "$rc" = 2 ] && [ -z "$o" ] || { LEG_MSG="A's report after B's park ⇒ exit $rc '${o:0:80}'"; return 1; }
  return 0
}

# rec_helpers <driver path> — replace the automate-helpers.sh beside <driver> (a symlink in a built dir)
# with a wrapper that records each park-ask-gate call into the case's rec.log, then runs the real one
rec_helpers() {
  local d; d="$(dirname "$1")"
  rm -f "$d/automate-helpers.sh"
  printf '#!/usr/bin/env bash\nif [ "${1:-}" = park-ask-gate ]; then printf "%%s\\n" "$*" >> "$NS_REC_LOG"; fi\nexec bash "%s" "$@"\n' "$H" > "$d/automate-helpers.sh"
}
# leg_order <driver> — park-first READY park: the watcher is armed, then the run lock released, and only
# then park-ask-gate runs (the park is complete before the ask is gated)
leg_order() {
  local drv="$1" w r g
  golden_case park-first-ready-park "$drv" || { LEG_MSG="park-first-ready-park: $GC_MSG"; return 1; }
  w="$(grep -n -m1 '^watch ' "$CASE_DIR/rec.log" | cut -d: -f1)"
  r="$(grep -n -m1 '^lock release ' "$CASE_DIR/rec.log" | cut -d: -f1)"
  g="$(grep -n -m1 '^park-ask-gate ' "$CASE_DIR/rec.log" | cut -d: -f1)"
  [ -n "$w" ] && [ -n "$r" ] && [ -n "$g" ] && [ "$w" -lt "$r" ] && [ "$r" -lt "$g" ] \
    || { LEG_MSG="order watch=${w:-none} release=${r:-none} park-ask-gate=${g:-none}: $(tr '\n' ';' < "$CASE_DIR/rec.log" | cut -c1-200)"; return 1; }
  return 0
}

# leg_ctx <driver> — 0 when gate-eval-merge's ctx carries exactly the six keys
SIX="drain_result,ready_sha,review_heal_result_path,supervisor_result_path,termination_reason,trust_unprotected"
leg_ctx() {
  local drv="$1" keys
  golden_case gate-eval-merge "$drv" >/dev/null 2>&1
  [ -f "$CASE_ROOT/.supervisor/automate/$CASE_RUN.gate-ctx.json" ] || { LEG_MSG="no ctx file written"; return 1; }
  keys="$(jq -r 'keys | join(",")' "$CASE_ROOT/.supervisor/automate/$CASE_RUN.gate-ctx.json" 2>/dev/null)"
  [ "$keys" = "$SIX" ] || { LEG_MSG="ctx keys: $keys"; return 1; }
  jq -e '.drain_result == "READY" and .trust_unprotected == false and (.ready_sha | test("^eb0e123"))' \
    "$CASE_ROOT/.supervisor/automate/$CASE_RUN.gate-ctx.json" >/dev/null || { LEG_MSG="ctx values wrong"; return 1; }
  return 0
}

# surface_list <driver file> — the AC4 grep's file list, the driver file standing in for the real one
SURFACE_BASE="loomwright/commands/agent-help.md
loomwright/docs/loop-inventory/automate-loop.md
loomwright/scripts/automate-helpers.sh
loomwright/scripts/fixtures/automate-golden/drain-superseded-by-merge/tree/dot-supervisor/requirements/automate-followups/11-post-park-lifecycle.md
loomwright/scripts/result_block_parser.py
loomwright/scripts/test-automate-helpers.sh
loomwright/skills/automate-loop/modes-and-merge-gate.md
loomwright/skills/automate-loop/per-item-loop.md"
MC_PIECE_A="gh pr merge"; MC_PIECE_B="--squash"
surface_list() {
  local drv="$1" pat="$MC_PIECE_A $MC_PIECE_B"
  {
    ( cd "$REPO" && grep -rn -- "$pat" loomwright/ | grep -viE "no |never |not " | cut -d: -f1 ) \
      | grep -vxF loomwright/scripts/automate-next-step.sh
    if grep -q . < <(grep -n -- "$pat" "$drv" | grep -viE "no |never |not "); then echo loomwright/scripts/automate-next-step.sh; fi
  } | env LC_ALL=C sort -u
}
leg_surface() {
  local drv="$1" got
  got="$(surface_list "$drv")"
  [ "$got" = "$SURFACE_BASE" ] || { LEG_MSG="surface list differs from base: $(printf '%s\n' "$got" | tr '\n' ' ')"; return 1; }
  return 0
}

# build_mutant <name> <anchor> <replacement|-append:<line>> — a driver copy beside symlinks to every other
# scripts/ entry; prints its path; gated: anchor once, non-empty, differs, bash -n
build_mutant() {
  local name="$1" anchor="$2" repl="$3" d c
  d="$WORK/mut-$name"; mkdir -p "$d"
  for e in "$HERE"/*; do [ "$e" = "$DRIVER" ] || ln -s "$e" "$d/$(basename "$e")"; done
  case "$repl" in
    -append:*) cp "$DRIVER" "$d/automate-next-step.sh"; printf '%s\n' "${repl#-append:}" >> "$d/automate-next-step.sh" ;;
    *)
      c="$(grep -cF -- "$anchor" "$DRIVER")"
      [ "$c" = 1 ] || { echo "anchor occurs $c time(s)" >&2; return 1; }
      AN="$anchor" RE="$repl" awk 'BEGIN { a = ENVIRON["AN"]; r = ENVIRON["RE"] }
        { i = index($0, a); if (i > 0 && !d) { $0 = substr($0, 1, i - 1) r substr($0, i + length(a)); d = 1 } print }' \
        "$DRIVER" > "$d/automate-next-step.sh" ;;
  esac
  [ -s "$d/automate-next-step.sh" ] || { echo "mutant empty" >&2; return 1; }
  ! cmp -s "$DRIVER" "$d/automate-next-step.sh" || { echo "mutant does not differ" >&2; return 1; }
  bash -n "$d/automate-next-step.sh" 2>/dev/null || { echo "mutant fails bash -n" >&2; return 1; }
  echo "$d/automate-next-step.sh"
}
# build_mutant2 <name> <anchor1> <repl1> <anchor2> <repl2> — two edits (the second applied to the first's
# output, same gates: its anchor once in that copy, the result non-empty, differing, bash -n)
build_mutant2() {
  local m c
  m="$(build_mutant "$1" "$2" "$3")" || return 1
  c="$(grep -cF -- "$4" "$m")"
  [ "$c" = 1 ] || { echo "second anchor occurs $c time(s)" >&2; return 1; }
  AN="$4" RE="$5" awk 'BEGIN { a = ENVIRON["AN"]; r = ENVIRON["RE"] }
    { i = index($0, a); if (i > 0 && !d) { $0 = substr($0, 1, i - 1) r substr($0, i + length(a)); d = 1 } print }' \
    "$m" > "$m.t" || return 1
  ! cmp -s "$m" "$m.t" || { echo "second edit does not differ" >&2; return 1; }
  mv "$m.t" "$m"
  [ -s "$m" ] && ! cmp -s "$DRIVER" "$m" && bash -n "$m" 2>/dev/null || { echo "second edit failed its gates" >&2; return 1; }
  echo "$m"
}

# ======================================================================================
echo "== test-automate-next-step.sh — driver: $DRIVER"
bash -n "$DRIVER" && ok "driver passes bash -n" || no "driver fails bash -n"

echo "-- G. golden parity (AC1)"
missing=""
for c in $REQUIRED_CASES; do [ -f "$FIX/$c/next-step.results" ] || missing="$missing $c"; done
for d in "$FIX"/gate-eval-*-park; do [ -f "$d/next-step.results" ] || missing="$missing $(basename "$d")"; done
[ -z "$missing" ] && ok "every required TAIL case carries next-step.results" || no "next-step.results missing:$missing"
sel="${NS_CASES:-}"
if [ -z "$sel" ]; then
  for d in "$FIX"/*/next-step.results; do sel="$sel $(basename "$(dirname "$d")")"; done
fi
for c in $sel; do
  GC_MSG=""; GC_DIFF=""
  if golden_case "$c" "$DRIVER"; then ok "$c: run file matches expected.md"
  else no "$c: $GC_MSG"; [ -n "$GC_DIFF" ] && printf '%s\n' "$GC_DIFF" | sed 's/^/    /'; fi
done
[ -n "${NS_CASES:-}" ] && { echo "PASS: $pass FAIL: $fail"; [ "$fail" -eq 0 ]; exit $?; }

echo "-- I. idempotency (AC2)"
for c in escalated-park park-first-ready-park gate-validation-gate-unrun-escalated; do
  LEG_MSG=""
  if leg_idem "$c" "$DRIVER"; then ok "I $c: two no-result calls re-print the instruction, nothing written"
  else no "I $c: $LEG_MSG"; fi
done

# replay: the case's own first drain report sent again after its terminal park re-prints it, writes nothing
if golden_case escalated-park "$DRIVER"; then
  last="$LAST_OUT"; s0="$(snapshot)"
  grep -m1 '^call: ' "$FIX/escalated-park/next-step.results" > "$CASE_DIR/replay.results"
  drive "$FIX/escalated-park" "$DRIVER" "$CASE_DIR/replay.results"
  if [ -z "$DRIVE_ERR" ] && [ "$LAST_OUT" = "$last" ] && [ "$s0" = "$(snapshot)" ]; then
    ok "I replay: the same drain report after the terminal park re-prints it, nothing written"
  else no "I replay: a replayed drain report re-ran the tail ($DRIVE_ERR)"; fi
else no "I replay: escalated-park did not run: $GC_MSG"; fi

echo "-- Q. question gates (AC3)"
LEG_MSG=""
if leg_cantask "$DRIVER"; then ok "Q: --non-interactive never asks (validation_unrun park; pending_decisions: 2 recorded)"
else no "Q: $LEG_MSG"; fi
# one interactive leftover ask, so AUT-LEFTOVER's shape is checked too
new_scratch "$FIX/closeout-leftover-gate-non-interactive" \
  && printf '%s\n' 'env: NEXT_STEP_FROM=sync NEXT_STEP_CLOSEOUT_OUT=$ROOT/closeout.out' "call:" "expect: ask" > "$CASE_DIR/lo.results" \
  && drive "$FIX/closeout-leftover-gate-non-interactive" "$DRIVER" "$CASE_DIR/lo.results"
[ -z "$DRIVE_ERR" ] && ok "Q: an interactive close-out leftover asks (AUT-LEFTOVER)" || no "Q: leftover ask: $DRIVE_ERR"
n_ask="$(grep -c . "$ASKS" || true)"
bad="$(cut -f2- "$ASKS" | jq -c 'select((.question | type) != "string" or (.question | length) == 0
    or (.header | type) != "string" or (.options | type) != "array" or (.options | length) == 0
    or (.cant_ask | type) != "string" or (.cant_ask | length) == 0)' 2>&1)"
gates="$(cut -f2- "$ASKS" | jq -r '.gate' 2>/dev/null | env LC_ALL=C sort -u | tr '\n' ' ')"
if [ "$n_ask" -gt 0 ] && [ -z "$bad" ]; then ok "Q: all $n_ask ask(s) carry question, header, options, cant_ask (gates: $gates)"
else no "Q: $n_ask ask(s); malformed: ${bad:-none}"; fi
if cut -f2- "$ASKS" | jq -e 'select(.gate == "AUT-WAIVE" or .gate == "AUT-DISMISS" or .gate == "AUT-LEFTOVER") | select(.header != "")' >/dev/null 2>&1; then
  no "Q: a human-only gate carries a catalog code in its header"
else ok "Q: human-only gates (AUT-WAIVE / AUT-DISMISS / AUT-LEFTOVER) carry an empty header"; fi
if cut -f2- "$ASKS" | jq -e 'select(.gate == "AUT-SUMMARY") | select(.header != "AUT-SUMMARY" or .options != ["Keep summary","Drop summary"])' >/dev/null 2>&1; then
  no "Q: an AUT-SUMMARY ask lacks its code or labels"
else ok "Q: AUT-SUMMARY asks carry header AUT-SUMMARY and exactly its two labels"; fi

echo "-- S. merge-surface invariant (AC4)"
LEG_MSG=""
if leg_surface "$DRIVER"; then ok "S: the positive-grep file list equals the base commit's (driver absent from it)"; else no "S: $LEG_MSG"; fi
grep -qF 'bash "$H" gate-eval "$PR" "$CTXF" --root "$ROOT"' "$DRIVER" && ok "S: the driver calls automate-helpers.sh gate-eval" \
  || no "S: the driver does not call automate-helpers.sh gate-eval"

echo "-- C. ctx shape (AC5)"
LEG_MSG=""
if leg_ctx "$DRIVER"; then ok "C: gate-eval-merge ctx carries exactly the six keys"; else no "C: $LEG_MSG"; fi

echo "-- V. running system (Validation 3)"
V3="$WORK/v3"; mkdir -p "$V3/fx"
cat > "$V3/fx/input.md" <<'EOF'
# Automate Run: v3 scratch backlog
## Status: running
## Source
- backlog .supervisor/requirements/v3/_BACKLOG.md
## Run Config
- mode: safe | limit: 5 | trust_unprotected: false
- auto_review_original: absent | config_backup: automate-2026-10-16-000000.config-backup.json
## Queue
- [ ] .supervisor/requirements/v3/01-scratch-item.md
- [ ] .supervisor/requirements/v3/02-next-item.md
## Current
- item: .supervisor/requirements/v3/01-scratch-item.md | status: running | pr: https://github.com/example/scratch/pull/7 | branch: feature/v3-scratch
- pause_reason: null
- owned_drain_started: 2026-10-16T10:00:00Z | owned_drain_result: READY | suppressed_default_dispatch: true
## Progress
- 2026-10-16T09:00:00Z picked .supervisor/requirements/v3/01-scratch-item.md
- 2026-10-16T09:40:00Z ran /autonomous → PR https://github.com/example/scratch/pull/7
- 2026-10-16T10:00:00Z owned drain started — /review-pr https://github.com/example/scratch/pull/7 --until-mergeable --no-auto-postmortem @ 1111111111111111111111111111111111111111
- 2026-10-16T10:20:00Z drain READY (converged, 1 round, 0 fix cycles)
EOF
printf 'run: automate-2026-10-16-000000\nscratch: Validation 3 of automate-speed/06\n' > "$V3/fx/source"
mkdir -p "$V3/fx/tree/dot-supervisor/requirements/v3"
printf '# Scratch item\n\n## Status: pending\n\n## Task\nA one-line doc change.\n' > "$V3/fx/tree/dot-supervisor/requirements/v3/01-scratch-item.md"
printf '0\tpr view https://github.com/example/scratch/pull/7 --json state\t{"state":"OPEN"}\n' > "$V3/fx/gh.stub"
if new_scratch "$V3/fx"; then
  hold="$(NS_REAL_LOCK=1 LOOMWRIGHT_HOLDER_PID=$$ in_case "$DRIVER" /dev/null bash -c 'LOOMWRIGHT_HOLDER_PID='"$$"' bash "'"$HERE"'/run-lock.sh" acquire --owner "automate:'"$CASE_RUN"'" 2>&1')"; hrc=$?
  out="$(NS_REAL_LOCK=1 in_case "$DRIVER" /dev/null bash "$DRIVER" "$CASE_RF" \
    --result '{"drain_result":"READY","termination_reason":"converged","ready_sha":"1111111111111111111111111111111111111111"}' 2>"$V3/err")"; vrc=$?
  st_after="$(NS_REAL_LOCK=1 in_case "$DRIVER" /dev/null bash "$HERE/run-lock.sh" status 2>&1)"
  echo "V3> acquire (PICK's lock, real run-lock.sh): exit $hrc"
  echo "V3> driver exit $vrc, instruction: $out"
  echo "V3> run-lock.sh status after: $st_after"
  echo "V3> ## Status / ## Current:"; grep -E '^## Status: |^- item: |^- pause_reason: |^- pending_decisions: ' "$CASE_RF" | sed 's/^/V3>   /'
  echo "V3> tail ## Progress:"; tail -n 5 "$CASE_RF" | sed 's/^/V3>   /'
  echo "V3> recorded side effects:"; sed 's/^/V3>   /' "$CASE_DIR/rec.log"
  if [ "$hrc" -eq 0 ] && [ "$vrc" -eq 0 ] && printf '%s' "$out" | jq -e '.do == "park" and .pause_reason == "awaiting_merge"' >/dev/null 2>&1 \
     && grep -qxF '## Status: paused' "$CASE_RF" \
     && grep -qF -- '- item: .supervisor/requirements/v3/01-scratch-item.md | status: awaiting_merge |' "$CASE_RF" \
     && grep -qE -- '^- [0-9TZ:-]+ parked awaiting_merge https://github.com/example/scratch/pull/7 — 0 dismissed decision\(s\) pending$' "$CASE_RF" \
     && grep -qxF "watch $CASE_RF .supervisor/requirements/v3/01-scratch-item.md https://github.com/example/scratch/pull/7" "$CASE_DIR/rec.log" \
     && ! grep -q "automate:$CASE_RUN" <<<"$st_after"; then
    ok "V: one item's tail from a READY drain report to the awaiting_merge park (watcher armed, the real run lock released)"
  else
    no "V: tail run wrong (acquire $hrc, driver $vrc: $(head -n 3 "$V3/err" | tr '\n' ' '))"
  fi
else
  no "V: scratch repo not built"
fi

echo "-- B. branches the golden segments do not reach"
# inline_run <case> <results text> — a fresh scratch of <case>, driven by the given directives
inline_run() { new_scratch "$FIX/$1" || { DRIVE_ERR="scratch not built"; return 1; }; printf '%s\n' "$2" > "$CASE_DIR/inline.results"; drive "$FIX/$1" "$DRIVER" "$CASE_DIR/inline.results"; }
in_order() { # <file> <fixed string>… — each string on a later line than the previous one
  local f="$1" last=0 n s; shift
  for s in "$@"; do n="$(grep -nF -- "$s" "$f" | head -n 1 | cut -d: -f1)"; [ -n "$n" ] && [ "$n" -gt "$last" ] || return 1; last="$n"; done
}
# B1 — the --auto-merge MERGE chain in one run: gate-eval → drafts + pending record → SYNC → leftover ask → CHECK OFF → next PICK
inline_run gate-eval-merge "$(printf '%s\n' "call: --result '{\"drain_result\":\"READY\",\"termination_reason\":\"converged\",\"ready_sha\":\"eb0e123e1584184cca438b53ed5145da79825acc\"}'" \
  "expect: ask" "call: --result '{\"answers\":[\"Keep and continue\"]}'" "expect: done")"
if [ -z "$DRIVE_ERR" ] && in_order "$CASE_RF" "gate-eval: MERGE" "- dismissed-drafts: 1 per-finding + 1 summary" \
     "closeout leftover kept: $CASE_RUN guard skipped — gh unavailable" "checked off .supervisor/requirements/automate-followups/39a-sweep-and-janitor.md — merged" \
   && grep -qxF -- '- pending_decisions: 2 | fix_now_reentered: false' "$CASE_RF" \
   && grep -qxF -- '- [x] .supervisor/requirements/automate-followups/39a-sweep-and-janitor.md' "$CASE_RF" \
   && printf '%s' "$LAST_OUT" | jq -e '.status == "running" and .remaining == 1' >/dev/null; then
  ok "B1: MERGE ⇒ drafts + pending_decisions recorded ⇒ SYNC leftover kept ⇒ checked off ⇒ {do: done, status: running}"
else no "B1: MERGE chain wrong: $DRIVE_ERR"; tail -n 8 "$CASE_RF" | sed 's/^/    /'; fi
# B2 — AUT-WAIVE answered Keep parked ⇒ the escalated park (validation_unrun, the step as --check)
inline_run gate-validation-waive "$(printf '%s\n' "call: --result '{\"drain_result\":\"READY\",\"termination_reason\":\"converged\",\"ready_sha\":\"8f8a52d\"}'" \
  "expect: ask" "call: --result '{\"answers\":[\"Keep parked\"]}'" "expect: park")"
if [ -z "$DRIVE_ERR" ] && printf '%s' "$LAST_OUT" | jq -e '.escalation_cause == "validation_unrun"' >/dev/null \
   && grep -qF -- '- escalation_cause: validation_unrun | check: V3 Running system | run_id: null | attempt: null | sha: 8f8a52d' "$CASE_RF" \
   && grep -qF -- 'validation-gate: unrun — V3 Running system' "$CASE_RF" && ! grep -q 'validation waived' "$CASE_RF"; then
  ok "B2: AUT-WAIVE Keep parked ⇒ escalated park, escalation_cause validation_unrun, no waiver written"
else no "B2: Keep parked wrong: $DRIVE_ERR"; grep -E 'escalation_cause|validation' "$CASE_RF" | sed 's/^/    /'; fi
# B3 — a --result that answers nothing valid exits 2 and writes nothing; the ask stays pending
inline_run park-first-ready-park "$(printf '%s\n' "call: --result '{\"drain_result\":\"READY\",\"termination_reason\":\"converged\",\"ready_sha\":\"028cbed6b8e3588f93731d6b862f0bc334de1d96\"}'" "expect: ask")"
ask1="$LAST_OUT"; s0="$(snapshot)"; : > "$CASE_DIR/seams.none"
in_case "$DRIVER" "$CASE_DIR/seams.none" bash "$DRIVER" "$CASE_RF" --result '{"answers":["Merge it now"]}' > "$CASE_DIR/b3.out" 2> "$CASE_DIR/b3.err"; b3rc=$?
in_case "$DRIVER" "$CASE_DIR/seams.none" bash "$DRIVER" "$CASE_RF" --result 'not json' > /dev/null 2>&1; b3rc2=$?
s1="$(snapshot)"; again="$(in_case "$DRIVER" "$CASE_DIR/seams.none" bash "$DRIVER" "$CASE_RF" 2>/dev/null)"
if [ -z "$DRIVE_ERR" ] && [ "$b3rc" = 2 ] && [ "$b3rc2" = 2 ] && [ ! -s "$CASE_DIR/b3.out" ] && [ "$s0" = "$s1" ] && [ "$again" = "$ask1" ]; then
  ok "B3: a label that is not an option / a non-JSON --result ⇒ exit 2, nothing written, the ask re-prints"
else no "B3: invalid answer: rc $b3rc/$b3rc2, unchanged=$([ "$s0" = "$s1" ] && echo yes || echo no), $DRIVE_ERR $(head -n 2 "$CASE_DIR/b3.err" | tr '\n' ' ')"; fi
# B4 — a refused writer is surfaced (no instruction, non-zero exit), and the next call retries the step
new_scratch "$FIX/gate-validation-gate-unrun-escalated"
cp "$CASE_RF" "$CASE_DIR/rf.keep"; sed '1d' "$CASE_DIR/rf.keep" > "$CASE_RF"   # no `# Automate Run:` title ⇒ progress-append refuses
: > "$CASE_DIR/seams.none"
in_case "$DRIVER" "$CASE_DIR/seams.none" bash "$DRIVER" "$CASE_RF" --non-interactive \
  --result '{"drain_result":"READY","termination_reason":"converged","ready_sha":"06ce6f59617b3b515a1950dbeb8b13630b54525c"}' > "$CASE_DIR/b4.out" 2> "$CASE_DIR/b4.err"; b4rc=$?
cp "$CASE_DIR/rf.keep" "$CASE_RF"
retry="$(in_case "$DRIVER" "$CASE_DIR/seams.none" bash "$DRIVER" "$CASE_RF" --non-interactive 2>/dev/null)"
norm "$CASE_RF" > "$CASE_DIR/a.md"; norm "$FIX/gate-validation-gate-unrun-escalated/expected.md" > "$CASE_DIR/x.md"
if [ "$b4rc" -ne 0 ] && [ "$b4rc" -ne 2 ] && [ ! -s "$CASE_DIR/b4.out" ] && grep -q 'progress-append exited' "$CASE_DIR/b4.err" \
   && printf '%s' "$retry" | jq -e '.do == "park"' >/dev/null 2>&1 && cmp -s "$CASE_DIR/a.md" "$CASE_DIR/x.md"; then
  ok "B4: a refused progress-append ⇒ exit $b4rc, no instruction, stderr names it; the retry finishes the case byte-identically"
else no "B4: writer failure: rc $b4rc, out '$(cat "$CASE_DIR/b4.out")', retry '$retry'"; diff "$CASE_DIR/x.md" "$CASE_DIR/a.md" | sed 's/^/    /' | head -n 12; fi
# B5 — fix-now before the park (a lane: decide-then-park) ⇒ spawn ⇒ the re-drain report ⇒ re-park, fix-now never offered again
inline_run dismissed-findings-decision-step "$(printf '%s\n' "call: --result '{\"drain_result\":\"READY\",\"termination_reason\":\"converged\",\"ready_sha\":\"0000000\"}'" \
  "expect: ask" "call: --result '{\"answers\":[\"Fix now on this PR\"]}'" "expect: spawn")"
spawn="$LAST_OUT"; b5err1="$DRIVE_ERR"
printf '%s\n' "call: --result '{\"drain_result\":\"READY\",\"termination_reason\":\"converged\",\"ready_sha\":\"1111111\"}'" "expect: ask" \
  "call: --result '{\"answers\":[\"Follow-up (keep draft)\"]}'" "expect: park" > "$CASE_DIR/b5b.results"
: > "$WORK/asks.b5"; ASKS_SAVE="$ASKS"; ASKS="$WORK/asks.b5"
drive "$FIX/dismissed-findings-decision-step" "$DRIVER" "$CASE_DIR/b5b.results"; ASKS="$ASKS_SAVE"
if [ -z "$b5err1$DRIVE_ERR" ] && printf '%s' "$spawn" | jq -e '.what == "fix-now re-drain" and (.findings | length) == 1' >/dev/null \
   && grep -qF -- 'owner decisions (dismissed): 1 fix-now, 0 follow-up, 0 drop' "$CASE_RF" \
   && grep -qxF -- '- pending_decisions: 0 | fix_now_reentered: true' "$CASE_RF" \
   && grep -q . "$WORK/asks.b5" && ! grep -qF 'Fix now on this PR' < <(cut -f2- "$WORK/asks.b5"); then
  ok "B5: fix-now ⇒ {do: spawn} ⇒ re-drain report ⇒ re-asked Follow-up/Drop only ⇒ re-park with fix_now_reentered: true"
else no "B5: fix-now re-pass wrong: $b5err1 $DRIVE_ERR"; tail -n 6 "$CASE_RF" | sed 's/^/    /'; fi
# B5b — a malformed re-drain report answering the spawn ⇒ exit 2, nothing written, the spawn re-prints
inline_run dismissed-findings-decision-step "$(printf '%s\n' "call: --result '{\"drain_result\":\"READY\",\"termination_reason\":\"converged\",\"ready_sha\":\"0000000\"}'" \
  "expect: ask" "call: --result '{\"answers\":[\"Fix now on this PR\"]}'" "expect: spawn")"
spawn="$LAST_OUT"; s0="$(snapshot)"; : > "$CASE_DIR/seams.none"
b5o="$(in_case "$DRIVER" "$CASE_DIR/seams.none" bash "$DRIVER" "$CASE_RF" --result '{"drain_result":"died"}' 2>/dev/null)"; b5rc=$?
again="$(in_case "$DRIVER" "$CASE_DIR/seams.none" bash "$DRIVER" "$CASE_RF" 2>/dev/null)"
if [ -z "$DRIVE_ERR" ] && [ "$b5rc" = 2 ] && [ -z "$b5o" ] && [ "$s0" = "$(snapshot)" ] && [ -n "$spawn" ] && [ "$again" = "$spawn" ]; then
  ok "B5b: a re-drain report with drain_result 'died' ⇒ exit 2, nothing written, the spawn re-prints"
else no "B5b: malformed re-drain report: rc $b5rc, out '$b5o', $DRIVE_ERR"; fi
# B6 — a malformed drain report (drain_result not READY|ESCALATED, a non-count items_processed, an unknown
# escalation_cause, a non-hex sha, a multi-line progress_note) ⇒ exit 2, nothing printed, nothing written
LEG_MSG=""
if leg_badreport "$DRIVER"; then ok "B6: $(grep -c . <<<"$BAD_REPORTS") malformed drain reports ⇒ exit 2, nothing printed, .supervisor/ byte-unchanged"
else no "B6: $LEG_MSG"; fi
# B7 — a different drain report after the terminal park (status no longer running) ⇒ exit 2, nothing written
LEG_MSG=""
if leg_reentry "$DRIVER"; then ok "B7: a different drain report after the escalated park ⇒ exit 2, nothing written, the park re-prints"
else no "B7: $LEG_MSG"; fi
# B8 — park-first order on the driver itself: watcher armed < run lock released < park-ask-gate
LEG_MSG=""
RECD="$WORK/rec-real"; mkdir -p "$RECD"
for e in "$HERE"/*; do [ "$e" = "$DRIVER" ] || ln -s "$e" "$RECD/$(basename "$e")"; done
cp "$DRIVER" "$RECD/automate-next-step.sh"; rec_helpers "$RECD/automate-next-step.sh"
if leg_order "$RECD/automate-next-step.sh"; then ok "B8: park-first READY park — watcher armed, then lock released, then park-ask-gate"
else no "B8: $LEG_MSG"; fi
# B9 — the sidecar's pending state is bound to ## Current's item + PR
LEG_MSG=""
if leg_binding "$DRIVER"; then ok "B9: A's pending ask never answers for B (exit 2, nothing written); B's report starts B's own tail at gate"
else no "B9: $LEG_MSG"; fi
# B10 — a count `[` cannot compare (20 digits, held in the sidecar) at terminate ⇒ the limit_reached park, never running
LEG_MSG=""
if leg_bigcount "$DRIVER"; then ok "B10: a 20-digit items_processed at terminate ⇒ limit_reached park (fail CLOSED)"
else no "B10: $LEG_MSG"; fi
# B11 — --non-interactive given on the first call only: the no-result retry of the failed step stays non-interactive
LEG_MSG=""
if leg_nonint_persist "$DRIVER"; then ok "B11: --non-interactive persists for the tail — the flagless retry parks (validation_unrun), never asks"
else no "B11: $LEG_MSG"; fi
# B12/B13 — dismissed-pending's documented `unknown` (another item's draft with no Decision line) is recorded,
# never a refusal: the escalated park completes, and the MERGE path goes on to SYNC
LEG_MSG=""
if leg_unknown_park "$DRIVER"; then ok "B12: a malformed draft (unknown) at an escalated park ⇒ pending_decisions: unknown, park line, watcher, notify, lock released"
else no "B12: $LEG_MSG"; fi
LEG_MSG=""
if leg_unknown_merge "$DRIVER"; then ok "B13: a malformed draft (unknown) after a MERGE ⇒ pending_decisions: unknown, SYNC reached"
else no "B13: $LEG_MSG"; fi
# B14 — a replayed drain report never stands in for a new one: the first report after a spawn re-prints the
# spawn (a new re-drain report proceeds); item A's report while B runs, or a foreign `pr`, ⇒ exit 2
LEG_MSG=""
if leg_spawn_replay "$DRIVER"; then ok "B14a: the first drain report re-sent after a spawn ⇒ the spawn re-prints, nothing written; a new re-drain report proceeds"
else no "B14a: $LEG_MSG"; fi
LEG_MSG=""
if leg_cross_replay "$DRIVER"; then ok "B14b: A's drain report while B runs / a foreign pr ⇒ exit 2, nothing written; B's own report (pr bound) starts B's tail"
else no "B14b: $LEG_MSG"; fi

echo "-- D. the schema doc mirrors the driver (closed lists)"
DOC="$HERE/../docs/result-schemas/automate-run.md"
arms="$(awk '/^ns_dispatch\(\) \{/,/^}/' "$DRIVER" | sed -n 's/^    \([a-z][a-z-]*\)) .*/\1/p' | env LC_ALL=C sort | tr '\n' ' ')"
docarms="$(grep -F "one of the driver's \`case\` arms:" "$DOC" | sed 's/.*arms: //; s/).*//' | grep -oE '`[a-z-]+`' | tr -d '`' | env LC_ALL=C sort | tr '\n' ' ')"
[ -n "$arms" ] && [ "$arms" = "$docarms" ] && ok "D: the doc's step list equals the driver's case arms ($arms)" || no "D: steps: driver '$arms' vs doc '$docarms'"
dos="$(grep -oE 'ns_emit (spawn|ask|park|done|[a-z]+) ' "$DRIVER" | awk '{print $2}' | env LC_ALL=C sort -u | tr '\n' ' ')"
docdos="$(grep -E '^\| `[a-z]+` \| ' "$DOC" | sed -n 's/^| `\([a-z]*\)` | .*/\1/p' | env LC_ALL=C sort -u | tr '\n' ' ')"
[ "$dos" = "ask done park spawn " ] && [ "$docdos" = "$dos" ] && ok "D: the closed do enum (spawn | ask | park | done) — emitter and doc agree" \
  || no "D: do enum: driver '$dos' vs doc '$docdos'"

if [ "${NS_SKIP_MUTANTS:-}" != 1 ]; then
  echo "-- M. mutation controls"
  # M2a — gate-eval replaced by a direct awaiting_merge park
  if m="$(build_mutant 2a 'gl="$(bash "$H" gate-eval "$PR" "$CTXF" --root "$ROOT" 2>"$errf")"; rc=$?' 'gl="PARK: skipped"; rc=0')"; then
    if golden_case gate-eval-merge "$m"; then no "M2a: gate-eval-merge stayed green with gate-eval skipped"
    else ok "M2a: gate-eval skipped (direct park) ⇒ gate-eval-merge red ($GC_MSG)"; fi
  else no "M2a: mutant not built"; fi
  # M2b — an unguarded merge-command line appended (the literal assembled from pieces here)
  if m="$(build_mutant 2b - "-append:$(printf '%s %s "$PR"' "$MC_PIECE_A" "$MC_PIECE_B")")"; then
    if leg_surface "$m"; then no "M2b: the surface leg stayed green with an unguarded merge line"
    else ok "M2b: an unguarded merge-command line ⇒ surface leg red"; fi
  else no "M2b: mutant not built"; fi
  # MI — the no-result path re-runs the last step instead of re-printing
  if m="$(build_mutant I "then printf '%s\n' \"\$pending\"; exit 0; fi" 'then NS_STATE="$(printf '"'"'%s'"'"' "$NS_STATE" | "$JQ" -c '"'"'.failed = .last_arm'"'"')"; fi')"; then
    if leg_idem escalated-park "$m"; then no "MI: idempotency stayed green with the re-print replaced"
    else ok "MI: re-run instead of re-print ⇒ idempotency red ($LEG_MSG)"; fi
  else no "MI: mutant not built"; fi
  # MQ — the --non-interactive check dropped before an ask
  if m="$(build_mutant Q 'ns_interactive() { [ "$NONINT" != 1 ]; }' 'ns_interactive() { return 0; }')"; then
    if leg_cantask "$m"; then no "MQ: can't-ask stayed green with the --non-interactive check dropped"
    else ok "MQ: --non-interactive check dropped ⇒ can't-ask red ($LEG_MSG)"; fi
  else no "MQ: mutant not built"; fi
  # MC — a gate-owned key added to the ctx
  if m="$(build_mutant C 'supervisor_result_path: $sp}' 'supervisor_result_path: $sp, high_risk: false}')"; then
    if leg_ctx "$m"; then no "MC: ctx leg stayed green with high_risk in the ctx"
    else ok "MC: \"high_risk\": false in the ctx ⇒ ctx leg red ($LEG_MSG)"; fi
  else no "MC: mutant not built"; fi
  # MV* — each drain-report guard dropped ⇒ the malformed-report leg (B6) red
  mv_leg() { # <name> <anchor> <replacement>
    local m
    if m="$(build_mutant "$1" "$2" "$3")"; then
      LEG_MSG=""
      if leg_badreport "$m"; then no "M$1: the malformed-report leg stayed green with the guard dropped"
      else ok "M$1: guard dropped ⇒ malformed-report leg red ($LEG_MSG)"; fi
    else no "M$1: mutant not built"; fi
  }
  mv_leg Vdr 'ns_field_ok drain_result "$dr" ||' 'true ||'
  mv_leg Vip 'escalation_attempt|items_processed) ns_count_ok "$2" ;;' 'escalation_attempt|items_processed) true ;;'
  mv_leg Vbig 'ns_count_ok() { [[ "$1" =~ ^[0-9]{1,9}$ ]]; }' 'ns_count_ok() { [[ "$1" =~ ^[0-9]+$ ]]; }'
  mv_leg Vec 'check_pending|check_red_unrelated|check_red|findings|validation_unrun|other) return 0 ;; *) return 1 ;; esac ;;' '*) return 0 ;; esac ;;'
  mv_leg Vsha 'ready_sha|escalation_sha) [[' 'ready_sha|escalation_sha) true || [['
  mv_leg Vnote 'progress_note) case "$2" in' 'progress_note) case "x" in'
  # MQp — both post-park --non-interactive guards of the decide step dropped (the first-entry park and
  # the batch emitter; either alone keeps the ask away) ⇒ Q (c) red
  if m="$(build_mutant2 Qp 'if ! ns_interactive; then ns_emit_park decide' 'if false; then ns_emit_park decide' \
       'ns_interactive || return 1   # --non-interactive' 'true || return 1   # --non-interactive')"; then
    LEG_MSG=""
    if leg_cantask "$m"; then no "MQp: can't-ask stayed green with the post-park guards dropped"
    else ok "MQp: post-park --non-interactive guards dropped ⇒ can't-ask red ($LEG_MSG)"; fi
  else no "MQp: mutant not built"; fi
  # MR — the running-status re-entry guard dropped ⇒ B7 red
  if m="$(build_mutant R '[ "$STATUS" = running ] ||' 'true ||')"; then
    LEG_MSG=""
    if leg_reentry "$m"; then no "MR: the re-entry leg stayed green with the running-status guard dropped"
    else ok "MR: running-status guard dropped ⇒ re-entry leg red ($LEG_MSG)"; fi
  else no "MR: mutant not built"; fi
  # MB — the item/PR binding of the sidecar dropped ⇒ B9 red
  if m="$(build_mutant B 'if [ -z "${NEXT_STEP_FROM:-}" ] && ! ns_bound; then' 'if false; then')"; then
    LEG_MSG=""
    if leg_binding "$m"; then no "MB: the binding leg stayed green with the item/PR binding dropped"
    else ok "MB: item/PR binding dropped ⇒ binding leg red ($LEG_MSG)"; fi
  else no "MB: mutant not built"; fi
  # MT — terminate's fail-CLOSED comparison reverted to a bare -ge (an erroring test reads as under) ⇒ B10 red
  if m="$(build_mutant T 'if ! ns_count_ok "$p" || ! [ "$p" -lt "$lim" ] 2>/dev/null; then' 'if [ "$p" -ge "$lim" ] 2>/dev/null; then')"; then
    LEG_MSG=""
    if leg_bigcount "$m"; then no "MT: the big-count leg stayed green with the bare -ge"
    else ok "MT: bare -ge at terminate ⇒ big-count leg red ($LEG_MSG)"; fi
  else no "MT: mutant not built"; fi
  # MN — the persisted --non-interactive no longer read back ⇒ B11 red
  if m="$(build_mutant N 'elif [ "$(st flag_non_interactive)" = true ]; then NONINT=1; fi' 'fi')"; then
    LEG_MSG=""
    if leg_nonint_persist "$m"; then no "MN: the persistence leg stayed green with the flag not read back"
    else ok "MN: persisted --non-interactive not read back ⇒ persistence leg red ($LEG_MSG)"; fi
  else no "MN: mutant not built"; fi
  # MPu — ns_pending_write refuses dismissed-pending's documented `unknown` again ⇒ B12 and B13 red
  if m="$(build_mutant Pu 'ns_count_ok "$1" || [ "$1" = unknown ] ||' 'ns_count_ok "$1" ||')"; then
    LEG_MSG=""; r12=green; r13=green
    leg_unknown_park "$m" || r12=red
    leg_unknown_merge "$m" || r13=red
    if [ "$r12" = red ] && [ "$r13" = red ]; then ok "MPu: unknown refused ⇒ B12 and B13 red"
    else no "MPu: unknown refused ⇒ B12 $r12, B13 $r13"; fi
  else no "MPu: mutant not built"; fi
  # MRs — the spawn branch's replay check dropped ⇒ B14a red
  if m="$(build_mutant Rs 'if ns_same_report "$RESULT" "$(st report_key)"; then' 'if false; then')"; then
    LEG_MSG=""
    if leg_spawn_replay "$m"; then no "MRs: the spawn-replay leg stayed green with the replay check dropped"
    else ok "MRs: spawn replay check dropped ⇒ B14a red ($LEG_MSG)"; fi
  else no "MRs: mutant not built"; fi
  # MRx — the fresh-tail stale-report check dropped ⇒ B14b red
  if m="$(build_mutant Rx '  ns_stale_report "$RESULT" && ns_die2 "--result is the drain report of a tail already left behind (another item / PR; ' '  false && ns_die2 "--result is the drain report of a tail already left behind (another item / PR; ')"; then
    LEG_MSG=""
    if leg_cross_replay "$m"; then no "MRx: the cross-item replay leg stayed green with the stale check dropped"
    else ok "MRx: stale-report check dropped ⇒ B14b red ($LEG_MSG)"; fi
  else no "MRx: mutant not built"; fi
  # MO — ns_park reordered: the merge watcher armed only AFTER the post-park decide step (the run file is
  # byte-identical, so only the order leg can see it) ⇒ B8 red
  if m="$(build_mutant2 O '*) ns_watch; ns_notify awaiting_merge' '*) ns_notify awaiting_merge' \
       'if [ "$(st order)" = park-first ]; then NEXT=decide; return 0; fi' 'if [ "$(st order)" = park-first ]; then ns_decide; ns_watch; return 0; fi')"; then
    rec_helpers "$m"; LEG_MSG=""
    if golden_case park-first-ready-park "$m"; then mo_gold=green; else mo_gold=red; fi
    if leg_order "$m"; then no "MO: the order leg stayed green with the watcher armed after park-ask-gate"
    else ok "MO: watcher armed after the decide step ⇒ order leg red (golden run file $mo_gold: $LEG_MSG)"; fi
  else no "MO: mutant not built"; fi
fi

echo "PASS: $pass FAIL: $fail"
[ "$fail" -eq 0 ]
