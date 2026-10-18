#!/usr/bin/env bash
# test-automate-next-step.sh — self-test for automate-next-step.sh, the `/automate` loop's driver
# (automate-speed/06 the tail, automate-speed/07 RUN and DRAIN, automate-speed/08 PICK / RECONCILE / resume). UNCOUNTED by the doc-currency
# gate. One tally (`PASS: <n> FAIL: <m>`,
# exit 1 on any failure). Hermetic: every case runs in its own `mktemp -d` checkout (git init, HOME
# and the git identity sandboxed, a stub `gh` first on PATH — no network), the merge watcher, the
# notify and (in the golden legs) the run lock replaced by recorders through the driver's
# NEXT_STEP_WATCH_CMD / NEXT_STEP_NOTIFY_CMD / NEXT_STEP_LOCK_CMD.
#
# LEGS
#   G   GOLDEN PARITY (AC1). Every TAIL golden case and every RUN/DRAIN one (automate-speed/07)
#       under fixtures/automate-golden/ carries a `next-step.results` file; the case's input.md + tree/
#       (where present) + gh.stub (where present) + setup (where present) are staged exactly as
#       test-automate-golden.sh stages them (the dot-<name> mapping, the stub table — a scratch copy, so
#       `gh:` rows add to it —, the sourced setup), the results file drives the driver, and the run
#       file must equal the case's expected.md byte for byte after the same normalisation (ISO ts →
#       <TS>, scratch root → <ROOT>, case dir → <CASE>, work dir → <TMP>). The required case list is
#       asserted present. The case's own files are read-only: anything a RUN/DRAIN case needs that the
#       loop's model would hand over (a SUPERVISOR_RESULT, a REVIEW_HEAL_RESULT, a free-text line) is
#       fixed input in the results file.
#       next-step.results grammar (one directive per line, `#` / blank skipped; $RF $ROOT $AD
#       $RUN_ID expanded by eval):
#         env: <NAME>=<value> …    set (an empty value unsets) a driver env var for the calls below
#                                  (the driver's documented test seams: NEXT_STEP_FROM / _UNTIL /
#                                  _CLOSEOUT_OUT)
#         pre: <subcommand> <args> `bash automate-helpers.sh <subcommand> <args>` — a write the
#                                  segment's driver does not own (named, like a golden `loop:` line)
#         call: <args…>            `bash automate-next-step.sh "$RF" <args…>`
#         call-bare: <args…>       `bash automate-next-step.sh <args…>` — no run file: the resume entry
#                                  (`--resume "$AD" [--run <id>|latest]`, automate-speed/08) picks it
#         expect: <do>|none        the last call printed {"do":"<do>",…} (none = an UNTIL stop or
#                                  a failed call)
#         expect-exit: <n>         the last call exited <n> (directly after its call:; without it a
#                                  non-zero exit is a broken expectation) — the current_not_set 3
#         gh: <rc>\t<pattern>\t<out>  one stub-table row (gh.stub's tab-separated form), appended
#                                  to the case's scratch table — fixed `gh` input
#         file: <path> <content>   write <content> (one shell word, `$'…'` allowed) to <path> under
#                                  the scratch root — fixed input a case has no tree/ file for
#         sidecar: <json>          merge <json> into the driver's sidecar before the next call — the
#                                  state an earlier, unrecorded driver call left (a FROM case)
#         out: <command>           run <command> in the case's sandbox; its normalised stdout must
#                                  equal the output block under `$ loop: <command>` in expected.out
#                                  (the learning-emit case's ledger projection)
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
#   R   RUN / DRAIN (automate-speed/07). R1 (AC5): `.auto_review` suppressed before the /autonomous
#       spawn prints, restored byte-for-byte (backup deleted, the original read backup-first into ## Run
#       Config) when the RUN report arrives and before the owned-drain spawn prints. R2 (AC2): another
#       owned-drain spawn for the same pass ⇒ exit 2 `drain_already_owned`, nothing printed, .supervisor/
#       byte-unchanged — while the spawn is pending, after its report, and with only the run file's
#       record left. R3 (AC3): a malformed config.json ⇒ exit 2 `config_malformed` before the spawn,
#       config.json byte-unchanged, no backup. R4 (AC4): drain-superseded-by-merge through the driver ⇒
#       byte-identical, no review-heal sidecar, no ledger line, the awaiting_go park; the same no-block
#       report while the PR reads OPEN ⇒ nothing written, done/stopped. R5/R6: malformed RUN / DRAIN
#       reports ⇒ exit 2, nothing written; a no-PR RUN report ⇒ the pinned no-PR line. R7: the new spawns
#       re-print (idempotent); the RUN report re-sent byte-identical at the owned-drain spawn / the no-PR
#       done re-prints it, nothing written; a different RUN report there, the RUN report after the DRAIN
#       report, or --start run is refused. R8: the 429-hint rate-limit
#       park (reason_hint) and a stale failed row (no park). R9: the first DRAIN report re-sent at its
#       tail's ask ⇒ the ask re-prints; re-sent at the fix-now re-drain spawn ⇒ the spawn re-prints,
#       nothing written (B14a's rule, DRAIN reports).
#       R10: a progress_notes entry / progress_note starting with a reserved prefix (a line the driver or
#       a helper keys on — `picked `, `parked `, `owned drain started`, `validation waived:`, …, case
#       folded) ⇒ exit 2
#       reserved_prefix, nothing written, at the gate entry and the owned-drain spawn; mid-line it is a
#       note, and the pass still owns ONE drain. R11: --start run without / with a malformed
#       --session-id ⇒ exit 2 session_id_missing / session_id_malformed, nothing written; the loop's own
#       log parks rate_limit; no session id / no log at the check ⇒ ONE pinned skipped line. R12: every
#       ^-anchored ## Progress prefix extracted from the reader sites (phase-timing, read-token-ledger,
#       the /lanes `cls`, runfile / readiness / park-leaks) is in NS_RESERVED_PREFIXES or a named
#       exception, and the schema doc names every reserved prefix.
#   V7  RUNNING SYSTEM (Validation 3 of automate-speed/07): a scratch git repo (gh stubbed), the real
#       run-lock.sh held as PICK holds it, one item from PICK through --start run → the RUN report →
#       the DRAIN report → the awaiting_merge park; the Progress lines are printed between `V3-07>`
#       markers.
#   P   PICK / RECONCILE / resume (automate-speed/08). P1 (AC2): an OPEN in-flight PR (awaiting_merge,
#       escalated) or this run's open trail PR ⇒ `--start pick` parks, releases the lock it took, writes no
#       `picked` line and no new ## Current item. P2 (AC3): RECONCILE's closeout leftovers ⇒ AUT-LEFTOVER (≤ 4
#       a call, the catalog labels, header ""); cant_ask / --non-interactive ⇒ the closeout_leftover park, one
#       line per leftover, no trail-pr. P3 (AC4): one run, no --run, can't ask ⇒ the
#       resume_requires_flag_non_interactive stop with .supervisor/ byte-unchanged; AUT-RESUME asked and
#       re-printed; its cant_ask / Start new write nothing to the run; continue restores a stranded config
#       backup. P4 (AC3): closeout-others at start — a `run_lock_held` row is a record, never a leftover; a
#       `leftover` row parks closeout_leftover before the PICK lock (a wrapper automate-helpers.sh beside a
#       driver copy prints the fixed closeout-others answer). P5: current-set BEFORE the `picked` line. P6:
#       brief-repair-merged through RECONCILE's closeout (the case itself is a pure helper call). P7: a crashed /
#       silent closeout-classify on the AUT-LEFTOVER Clean up now retry (a wrapper automate-helpers.sh beside a
#       driver copy) stays a leftover — re-ask, then the closeout_leftover park — never trail gate / PICK; silent at
#       RECONCILE ⇒ one leftover. P8: a --parallel coordinator run (`- parallel: 2` / `1`) ⇒ --resume --run, the
#       AUT-RESUME Continue and --start pick print done/stopped coordinator_run, .supervisor/ byte-unchanged, no
#       lock; a bare start still asks AUT-RESUME / stops resume_requires_flag_non_interactive (AC4). P9: a live merge watcher
#       (a real process carrying automate-merge-watch.sh + the PR) ⇒ ONE `merge-watch noted:` line at the
#       open-PR park, not repeated by a second --start pick; a dead one ⇒ none. P8 also seeds the marker
#       whitespace variants `- parallel:2`, `- parallel: 2  # wave` and `-  parallel: 2`. P10: the named
#       refusals — `--start pick` on a `## Status: done` run (run_done), `--start pick` while this pass's
#       /autonomous spawn is pending (pick_already_started; the spawn still re-prints), `--resume --run` naming
#       no incomplete run (run_not_incomplete) ⇒ exit 2, the exact stderr line, nothing printed, .supervisor/
#       byte-unchanged, no run-lock acquire. P11: a non-empty `meta-push-failed` answer ⇒ ONE `meta-push-failed:`
#       ## Progress line + the stderr report and the PICK proceeds (next: pending) — a report, never a block
#       (branch-mode.md); not repeated on a second pass; no marker ⇒ nothing written.
#   V8  RUNNING SYSTEM (Validation 3 of automate-speed/08): a scratch repo (gh stubbed, the real run-lock.sh),
#       a run parked awaiting_merge whose PR the stub reads MERGED, driven through `--resume`: the closeout
#       lines through the next `picked` line are printed between `V3-08>` markers.
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
#         M7a the config restore moved from run-result to drain-result (two edits; Validation 2a)
#                                                                  ⇒ R1 (+ run-config-suppress-restore)
#         M7b the second-drain refusal removed (Validation 2b)     ⇒ R2
#         M7c config-suppress's non-zero exit ignored              ⇒ R3
#         M7d the review-heal sidecar written on the superseded path ⇒ R4
#         M7e progress-append's exit swallowed on the drain start line ⇒ G drain-pinned-start-line-current-not-set
#         M7f the reserved-prefix check of the free-text notes removed ⇒ R10
#         M7g both --start run session-id refusals removed (two edits) ⇒ R11
#         M7h the rate-limit check's pinned skipped line removed ⇒ R11
#         M7i `parked` dropped from NS_RESERVED_PREFIXES               ⇒ R12 and R10
#         M7j the reserved-prefix case fold dropped                   ⇒ R10
#         M7k the RUN report replay dropped                           ⇒ R7
#         M7l the DRAIN report replay at an open ask dropped          ⇒ R9
#         M8a the open-PR park skipped (Validation 2 of automate-speed/08) ⇒ P1
#         M8b the trail-gate park skipped                             ⇒ P1
#         M8c any closeout-classify answer read as complete           ⇒ P2
#         M8d Continue auto-picked when the resume cannot ask         ⇒ P3
#         M8e the picked line written before current-set               ⇒ P5
#         M8f the Clean up now retry's classify guard dropped          ⇒ P7
#         M8g the coordinator-run (`- parallel:`) detection dropped     ⇒ P8
#         M8h the live merge-watcher note dropped                       ⇒ P9
#         M8i the run_done refusal dropped                              ⇒ P10
#         M8j the meta-push-failed ## Progress report line dropped      ⇒ P11
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
closeout-leftover-gate-non-interactive dismissed-findings-decision-step
run-config-suppress-restore run-record-pr drain-owned-drain-started drain-pinned-start-line-current-not-set
drain-superseded-by-merge learning-emit-end-of-drain rate-limit-park dismissed-fix-now-re-drain
pick-current-set-then-picked pick-pending-decisions-ask pick-time-lane-guard-park pick-time-token-ceiling-park
pick-time-trail-gate-park reconcile-closeout-merged gate-validation-recheck-at-reconcile resume-ambiguous-park
resume-config-crash-restore resume-current-rebuild resume-glob-finalize resume-rate-limit-park
resume-reconcile-status skipped-item-check-off"

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
  # the stub table is a scratch copy of gh.stub (where present), so a case's `gh:` rows add fixed input
  # without touching the read-only fixture
  CASE_GH="$cw/gh.table"
  if [ -f "$cd_/gh.stub" ]; then cp "$cd_/gh.stub" "$CASE_GH" || return 1; else : > "$CASE_GH"; fi
  if [ -s "$CASE_GH" ] && [ -n "$(tail -c 1 "$CASE_GH")" ]; then echo >> "$CASE_GH"; fi
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
  local cd_="$1" drv="$2" rs="$3" line rest k=0 o e rc seams want got w nm pend="" sc n=0
  local RF="$CASE_RF" ROOT="$CASE_ROOT" AD="$CASE_ROOT/.supervisor/automate" RUN_ID="$CASE_RUN"
  seams="$CASE_DIR/seams.env"; : > "$seams"; LAST_OUT=""; DRIVE_ERR=""; LAST_RC=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ""|"#"*) continue ;; esac
    rest="${line#*:}"; rest="${rest# }"
    # a call's non-zero exit is a broken expectation unless the very next directive expects it
    case "$line" in "expect-exit: "*) ;; *) DRIVE_ERR="$DRIVE_ERR$pend"; pend="" ;; esac
    case "$line" in
      "expect-exit: "*)
        [ "$LAST_RC" = "$rest" ] || DRIVE_ERR="${DRIVE_ERR}call $k exit $LAST_RC, want $rest; "
        pend="" ;;
      "gh: "*) printf '%s\n' "$rest" >> "$CASE_GH" ;;
      "file: "*)
        eval "set -- $rest"
        if [ "$#" = 2 ] && case "$1" in "$CASE_ROOT"/*) true ;; *) false ;; esac; then
          mkdir -p "$(dirname "$1")" && printf '%s' "$2" > "$1" || DRIVE_ERR="${DRIVE_ERR}file not written: $1; "
        else DRIVE_ERR="${DRIVE_ERR}file: wants <path under the scratch root> <content>: $rest; "; fi ;;
      "sidecar: "*)
        eval "set -- $rest"; sc="$AD/$RUN_ID.next-step.json"
        [ -f "$sc" ] || printf '{}\n' > "$sc"
        jq -S --argjson x "$1" '. + $x' "$sc" > "$sc.t" 2>/dev/null && mv "$sc.t" "$sc" || DRIVE_ERR="${DRIVE_ERR}sidecar seed refused: $rest; " ;;
      "out: "*)
        n=$((n + 1))
        in_case "$drv" "$seams" bash -c "$rest" > "$CASE_DIR/out$n.txt" 2>/dev/null
        LINE_="\$ loop: $rest" awk 'BEGIN { w = ENVIRON["LINE_"] } f && /^= [0-9]+$/ { exit } f { print } $0 == w { f = 1 }' \
          "$cd_/expected.out" > "$CASE_DIR/want$n.txt"
        norm "$CASE_DIR/out$n.txt" > "$CASE_DIR/got$n.txt"
        if [ ! -s "$CASE_DIR/want$n.txt" ]; then DRIVE_ERR="${DRIVE_ERR}out: no '\$ loop: $rest' block in expected.out; "
        elif ! cmp -s "$CASE_DIR/want$n.txt" "$CASE_DIR/got$n.txt"; then
          DRIVE_ERR="${DRIVE_ERR}out: '$rest' printed $(head -c 300 "$CASE_DIR/got$n.txt" | tr '\n' ' '), want $(head -c 300 "$CASE_DIR/want$n.txt" | tr '\n' ' '); "
        fi ;;
      "env: "*)
        eval "set -- $rest"
        for w in "$@"; do
          nm="${w%%=*}"; awk -v n="$nm" -F= '$1 != n' "$seams" > "$seams.t"; mv "$seams.t" "$seams"; printf '%s\n' "$w" >> "$seams"
        done ;;
      "pre: "*)
        eval "set -- $rest"
        in_case "$drv" "$seams" bash "$H" "$@" >/dev/null 2>"$CASE_DIR/pre.err" || DRIVE_ERR="${DRIVE_ERR}pre failed: $rest; " ;;
      "call:"*|"call-bare:"*)
        k=$((k + 1)); o="$CASE_DIR/call$k.out"; e="$CASE_DIR/call$k.err"
        eval "set -- $rest"
        case "$line" in "call:"*) set -- "$CASE_RF" "$@" ;; esac
        in_case "$drv" "$seams" bash "$drv" "$@" > "$o" 2> "$e"
        rc=$?; LAST_RC=$rc
        LAST_OUT="$(cat "$o")"
        [ "$rc" -eq 0 ] || pend="call $k exit $rc ($(head -n 3 "$e" | tr '\n' ' ')); "
        grep '"do":"ask"' "$o" | sed "s|^|$(basename "$cd_")$TAB|" >> "$ASKS" ;;
      "expect: "*)
        want="$rest"
        if [ -z "$LAST_OUT" ]; then got=none; else got="$(printf '%s' "$LAST_OUT" | jq -r '.do // "?"' 2>/dev/null)"; fi
        [ "$got" = "$want" ] || DRIVE_ERR="${DRIVE_ERR}call $k printed do=$got, want $want; " ;;
      *) DRIVE_ERR="${DRIVE_ERR}bad directive: $line; " ;;
    esac
  done < "$rs"
  DRIVE_ERR="$DRIVE_ERR$pend"
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

# --------------------------------------------------------------------------------------
# RUN / DRAIN legs (automate-speed/07)
# --------------------------------------------------------------------------------------
# the 39b RUN report (PR #542) and a READY DRAIN report, as the fixtures carry them
R_RUN="$(sed -n "s/^call: --result '\(.*\)'$/\1/p" "$FIX/run-record-pr/next-step.results")"
R_DRAIN="$(sed -n "s/^call: --result '\(.*\)'$/\1/p" "$FIX/drain-pinned-start-line-current-not-set/next-step.results")"
R_NOPR='{"status_reason":"plan_review_failed","no_pr_why":"Plan Review FAIL x3 on the brief","session_id":"auto-2026-10-14-091531"}'
R_SEAMS="$WORK/seams.none"; : > "$R_SEAMS"
ns_call() { # <driver> <args…> — one driver call in the current case; sets NC_OUT NC_RC NC_ERR
  local drv="$1"; shift
  NC_OUT="$(in_case "$drv" "$R_SEAMS" bash "$drv" "$CASE_RF" "$@" 2>"$CASE_DIR/nc.err")"; NC_RC=$?
  NC_ERR="$(cat "$CASE_DIR/nc.err")"
}
# leg_run_order <driver> — AC5: suppress BEFORE the /autonomous spawn is printed, restore (byte-for-byte,
# backup deleted, auto_review_original read backup-first) when the RUN report arrives and BEFORE the
# owned-drain spawn is printed
leg_run_order() {
  local drv="$1" cfg bak
  new_scratch "$FIX/run-config-suppress-restore" || { LEG_MSG="scratch"; return 1; }
  cfg="$CASE_ROOT/.supervisor/config.json"; bak="$CASE_ROOT/.supervisor/automate/$CASE_RUN.config-backup.json"
  printf '{"auto_review": true, "keep": [1, 2]}\n' > "$cfg"; cp "$cfg" "$CASE_DIR/cfg.orig"
  ns_call "$drv" --start run --session-id s-run
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "spawn" and .what == "/autonomous run" and (.invocation | startswith("/autonomous --single-iteration --requirement "))' >/dev/null 2>&1 \
    || { LEG_MSG="--start run ⇒ exit $NC_RC '${NC_OUT:0:120}' ${NC_ERR:0:160}"; return 1; }
  jq -e '.auto_review == false and .keep == [1, 2]' "$cfg" >/dev/null 2>&1 && cmp -s "$bak" "$CASE_DIR/cfg.orig" \
    || { LEG_MSG="at the /autonomous spawn: config.json not suppressed or the backup is not byte-for-byte"; return 1; }
  grep -qxF -- '- auto_review_original: true | config_backup: automate-2026-10-13-181331.config-backup.json' "$CASE_RF" \
    || { LEG_MSG="auto_review_original not recorded as true (read backup-first): $(grep -F auto_review_original "$CASE_RF")"; return 1; }
  ns_call "$drv" --result "$R_RUN"
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "spawn" and .what == "owned drain"' >/dev/null 2>&1 \
    || { LEG_MSG="RUN report ⇒ exit $NC_RC '${NC_OUT:0:120}' ${NC_ERR:0:160}"; return 1; }
  cmp -s "$cfg" "$CASE_DIR/cfg.orig" && [ ! -e "$bak" ] \
    || { LEG_MSG="at the owned-drain spawn: config.json not restored byte-for-byte (or the backup left): $(jq -c . "$cfg" 2>/dev/null)"; return 1; }
  in_order "$CASE_RF" "auto_review suppressed (backup $CASE_RUN.config-backup.json)" "auto_review restored (config-restore: original true)" \
    "session_id auto-2026-10-14-091531" "ran /autonomous → PR https://github.com/vikashruhilgit/loomwright/pull/542 (" \
    || { LEG_MSG="RUN lines out of order: $(grep -nE 'auto_review|session_id|ran /autonomous' "$CASE_RF" | tr '\n' ';')"; return 1; }
  ! grep -q 'owned drain started' "$CASE_RF" || { LEG_MSG="a drain start line was written before the drain ran"; return 1; }
  return 0
}
# leg_drain_once <driver> — AC2: another owned-drain spawn for the same pass ⇒ exit 2 drain_already_owned,
# nothing printed, .supervisor/ byte-unchanged — while the spawn is pending, after its report, and with
# only the run file's record left (the sidecar gone)
leg_drain_once() {
  local drv="$1" s0
  new_scratch "$FIX/drain-owned-drain-started" || { LEG_MSG="scratch"; return 1; }
  ns_call "$drv" --start drain
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.what == "owned drain"' >/dev/null 2>&1 || { LEG_MSG="first --start drain ⇒ exit $NC_RC '${NC_OUT:0:100}' ${NC_ERR:0:120}"; return 1; }
  s0="$(snapshot)"; ns_call "$drv" --start drain
  [ "$NC_RC" = 2 ] && [ -z "$NC_OUT" ] && grep -q 'next-step: drain_already_owned — ' <<<"$NC_ERR" && [ "$s0" = "$(snapshot)" ] \
    || { LEG_MSG="second spawn before the report ⇒ exit $NC_RC '${NC_OUT:0:100}' ${NC_ERR:0:120} .supervisor/ $([ "$s0" = "$(snapshot)" ] && echo unchanged || echo CHANGED)"; return 1; }
  ns_call "$drv" --non-interactive --result "$R_DRAIN"
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "park"' >/dev/null 2>&1 || { LEG_MSG="the DRAIN report ⇒ exit $NC_RC '${NC_OUT:0:100}' ${NC_ERR:0:160}"; return 1; }
  s0="$(snapshot)"; ns_call "$drv" --start drain
  [ "$NC_RC" = 2 ] && [ -z "$NC_OUT" ] && grep -q 'drain_already_owned' <<<"$NC_ERR" && [ "$s0" = "$(snapshot)" ] \
    || { LEG_MSG="a spawn after the report ⇒ exit $NC_RC '${NC_OUT:0:100}' ${NC_ERR:0:120}"; return 1; }
  # the run file is the durable record: the sidecar gone, the item running again, still refused
  rm -f "$CASE_ROOT/.supervisor/automate/$CASE_RUN.next-step.json"
  in_case "$drv" "$R_SEAMS" bash "$H" current-set "$CASE_RF" --item .supervisor/requirements/automate-followups/39b-run-lock-and-guard-arm.md --status running --pause-reason null >/dev/null 2>&1
  s0="$(snapshot)"; ns_call "$drv" --start drain
  [ "$NC_RC" = 2 ] && [ -z "$NC_OUT" ] && grep -q 'drain_already_owned' <<<"$NC_ERR" && [ "$s0" = "$(snapshot)" ] \
    || { LEG_MSG="sidecar gone ⇒ exit $NC_RC '${NC_OUT:0:100}' ${NC_ERR:0:120}"; return 1; }
  return 0
}
# leg_config_malformed <driver> — AC3: a malformed config.json ⇒ exit 2 config_malformed before the spawn: no
# line, config.json byte-unchanged, no backup (and nothing else under .supervisor/ written)
leg_config_malformed() {
  local drv="$1" s0 cfg
  new_scratch "$FIX/run-config-suppress-restore" || { LEG_MSG="scratch"; return 1; }
  cfg="$CASE_ROOT/.supervisor/config.json"; printf '{"auto_review": true,\n' > "$cfg"; cp "$cfg" "$CASE_DIR/cfg.bad"
  s0="$(snapshot)"; ns_call "$drv" --start run --session-id s-run
  [ "$NC_RC" = 2 ] && [ -z "$NC_OUT" ] && grep -q 'next-step: config_malformed — ' <<<"$NC_ERR" && [ "$s0" = "$(snapshot)" ] \
    && cmp -s "$cfg" "$CASE_DIR/cfg.bad" && [ ! -e "$CASE_ROOT/.supervisor/automate/$CASE_RUN.config-backup.json" ] \
    && ! grep -q 'auto_review suppressed' "$CASE_RF" \
    || { LEG_MSG="malformed config ⇒ exit $NC_RC '${NC_OUT:0:100}' ${NC_ERR:0:160} .supervisor/ $([ "$s0" = "$(snapshot)" ] && echo unchanged || echo CHANGED)"; return 1; }
  return 0
}
# leg_superseded <driver> — AC4: the superseded case through the driver is byte-identical, writes no review-heal
# sidecar and no ledger line, parks awaiting_go; a no-block drain whose PR reads OPEN writes nothing
leg_superseded() {
  local drv="$1"
  golden_case drain-superseded-by-merge "$drv" || { LEG_MSG="parity: $GC_MSG"; return 1; }
  [ ! -e "$CASE_ROOT/.supervisor/automate/$CASE_RUN.review-heal-result.md" ] || { LEG_MSG="a review-heal sidecar was written on the superseded path"; return 1; }
  [ ! -s "$CASE_ROOT/.supervisor/postmortem/results.jsonl" ] || { LEG_MSG="a learning line was written on the superseded path"; return 1; }
  printf '%s' "$LAST_OUT" | jq -e '.do == "park" and .pause_reason == "awaiting_go"' >/dev/null 2>&1 || { LEG_MSG="not the awaiting_go park: $LAST_OUT"; return 1; }
  new_scratch "$FIX/drain-superseded-by-merge" || { LEG_MSG="scratch (open)"; return 1; }
  printf '0\tpr view https://github.com/vikashruhilgit/loomwright/pull/305 --json state,mergedAt\t{"state":"OPEN","mergedAt":null}\n' > "$CASE_GH"
  printf 'NEXT_STEP_FROM=drain-result\n' > "$CASE_DIR/seams.from"
  NC_OUT="$(in_case "$drv" "$CASE_DIR/seams.from" bash "$drv" "$CASE_RF" --result '{"no_terminal_block":true}' 2>"$CASE_DIR/nc.err")"; NC_RC=$?
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "done" and .status == "stopped"' >/dev/null 2>&1 \
    && cmp -s "$FIX/drain-superseded-by-merge/input.md" "$CASE_RF" && [ ! -e "$CASE_ROOT/.supervisor/automate/$CASE_RUN.review-heal-result.md" ] \
    || { LEG_MSG="no block + OPEN ⇒ exit $NC_RC '${NC_OUT:0:120}' $(head -c 160 "$CASE_DIR/nc.err"); run file $(cmp -s "$FIX/drain-superseded-by-merge/input.md" "$CASE_RF" && echo unchanged || echo CHANGED)"; return 1; }
  return 0
}
# leg_bad_run_reports <driver> — a malformed RUN report at the /autonomous spawn ⇒ exit 2, nothing printed,
# .supervisor/ byte-unchanged; then a no-PR report writes the pinned no-PR line and stops
BAD_RUN='{"supervisor_result":"SUPERVISOR_RESULT:\n  pr_url: https://github.com/o/r/pull/1\n  branch: b","run_note":"two\nlines"}
{"supervisor_result":"SUPERVISOR_RESULT:\n  pr_url: https://github.com/o/r/pull/1\n  branch: b","pr_url":"https://github.com/o/r/pull/2"}
{"supervisor_result":"SUPERVISOR_RESULT:\n  pr_url: not-a-pr-url\n  branch: b"}
{"supervisor_result":"SUPERVISOR_RESULT:\n  pr_url: https://github.com/o/r/pull/1"}
{"pr_url":"https://github.com/o/r/pull/1","branch":"b"}
{"status_reason":"plan_review_failed"}
{"supervisor_result":"x","supervisor_result_file":"/etc/hosts","no_pr_why":"y"}
{"supervisor_result_file":"/nonexistent/sup.md","no_pr_why":"y"}
{"no_pr_why":"y","session_id":"../../etc"}
{"no_pr_why":"y","status_reason":"has space"}
{"review_heal_result":"REVIEW_HEAL_RESULT:\n  decision: READY"}'
leg_bad_run_reports() {
  local drv="$1" s0 r
  new_scratch "$FIX/run-config-suppress-restore" || { LEG_MSG="scratch"; return 1; }
  ns_call "$drv" --start run --session-id s-run; [ "$NC_RC" = 0 ] || { LEG_MSG="--start run ⇒ exit $NC_RC"; return 1; }
  s0="$(snapshot)"
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    ns_call "$drv" --result "$r"
    [ "$NC_RC" = 2 ] && [ -z "$NC_OUT" ] && [ "$s0" = "$(snapshot)" ] \
      || { LEG_MSG="$r ⇒ exit $NC_RC '${NC_OUT:0:60}' .supervisor/ $([ "$s0" = "$(snapshot)" ] && echo unchanged || echo CHANGED)"; return 1; }
  done <<EOF
$BAD_RUN
EOF
  ns_call "$drv" --result '{"status_reason":"plan_review_failed","no_pr_why":"Plan Review FAIL x3 on the brief","session_id":"auto-2026-10-14-091531"}'
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "done" and .status == "stopped" and .step == "rate-limit"' >/dev/null 2>&1 \
    && grep -qE -- '^- [0-9TZ:-]+ ran /autonomous — no PR: plan_review_failed \(Plan Review FAIL x3 on the brief\)$' "$CASE_RF" \
    && [ ! -e "$CASE_ROOT/.supervisor/automate/$CASE_RUN.supervisor-result.md" ] && [ ! -e "$CASE_ROOT/.supervisor/config.json" ] \
    && grep -q '^lock release ' "$CASE_DIR/rec.log" \
    || { LEG_MSG="no-PR report ⇒ exit $NC_RC '${NC_OUT:0:120}' ${NC_ERR:0:120} $(grep -F 'ran /autonomous' "$CASE_RF")"; return 1; }
  return 0
}
# leg_bad_drain_reports <driver> — a malformed DRAIN report at the owned-drain spawn ⇒ exit 2, nothing printed,
# .supervisor/ byte-unchanged (a bare drain report there is refused too: the driver owns DRAIN's lines)
BAD_DRAIN='{"ready_sha":"35b8303"}
{"review_heal_result":"REVIEW_HEAL_RESULT:\n  decision: READY","no_terminal_block":true}
{"no_terminal_block":false}
{"review_heal_result":"REVIEW_HEAL_RESULT:\n  decision: ready"}
{"review_heal_result":"no block here, decision: READY"}
{"review_heal_result":"REVIEW_HEAL_RESULT:\n  decision: READY\n  fix_cycles: many"}
{"review_heal_result":"REVIEW_HEAL_RESULT:\n  decision: READY","head_sha":"zz|35b8303"}
{"review_heal_result":"REVIEW_HEAL_RESULT:\n  decision: READY","started_at":"yesterday"}
{"review_heal_result":"REVIEW_HEAL_RESULT:\n  decision: READY","progress_notes":["one\n## Status: done"]}
{"review_heal_result":"REVIEW_HEAL_RESULT:\n  decision: READY","progress_notes":"not an array"}
{"review_heal_result":"REVIEW_HEAL_RESULT:\n  decision: READY","drain_note":"two\nlines"}
{"review_heal_result":"REVIEW_HEAL_RESULT:\n  decision: READY","pr":"https://github.com/vikashruhilgit/loomwright/pull/1"}
{"drain_result":"READY","termination_reason":"converged","ready_sha":"35b8303"}'
leg_bad_drain_reports() {
  local drv="$1" s0 r
  new_scratch "$FIX/drain-owned-drain-started" || { LEG_MSG="scratch"; return 1; }
  ns_call "$drv" --start drain; [ "$NC_RC" = 0 ] || { LEG_MSG="--start drain ⇒ exit $NC_RC"; return 1; }
  s0="$(snapshot)"
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    ns_call "$drv" --result "$r"
    [ "$NC_RC" = 2 ] && [ -z "$NC_OUT" ] && [ "$s0" = "$(snapshot)" ] \
      || { LEG_MSG="$r ⇒ exit $NC_RC '${NC_OUT:0:60}' .supervisor/ $([ "$s0" = "$(snapshot)" ] && echo unchanged || echo CHANGED)"; return 1; }
  done <<EOF
$BAD_DRAIN
EOF
  return 0
}
# leg_run_idem <driver> — the /autonomous and owned-drain spawns re-print on a no-result call (and on a re-sent
# --start run) and write nothing; the RUN report re-sent byte-identical at the owned-drain spawn (or at the
# no-PR `done`) is a replay — the pending instruction re-prints, nothing written — while a different RUN
# report there ⇒ exit 2; --start run while the drain spawn is pending ⇒ run_already_started
leg_run_idem() {
  local drv="$1" s0 sp
  new_scratch "$FIX/run-config-suppress-restore" || { LEG_MSG="scratch"; return 1; }
  ns_call "$drv" --start run --session-id s-run; sp="$NC_OUT"; s0="$(snapshot)"
  ns_call "$drv"; [ "$NC_OUT" = "$sp" ] || { LEG_MSG="no-result call did not re-print the /autonomous spawn"; return 1; }
  ns_call "$drv" --start run --session-id s-run; [ "$NC_RC" = 0 ] && [ "$NC_OUT" = "$sp" ] && [ "$s0" = "$(snapshot)" ] || { LEG_MSG="a re-sent --start run did not re-print / wrote"; return 1; }
  ns_call "$drv" --result "$R_RUN"; sp="$NC_OUT"; s0="$(snapshot)"
  ns_call "$drv"; [ "$NC_OUT" = "$sp" ] && [ "$s0" = "$(snapshot)" ] || { LEG_MSG="no-result call did not re-print the owned-drain spawn"; return 1; }
  ns_call "$drv" --result "$R_RUN"; [ "$NC_RC" = 0 ] && [ "$NC_OUT" = "$sp" ] && [ "$s0" = "$(snapshot)" ] || { LEG_MSG="the RUN report re-sent at the drain spawn ⇒ exit $NC_RC '${NC_OUT:0:80}' .supervisor/ $([ "$s0" = "$(snapshot)" ] && echo unchanged || echo CHANGED)"; return 1; }
  ns_call "$drv" --result "$(printf '%s' "$R_RUN" | jq -c '.run_note = "a different note"')"
  [ "$NC_RC" = 2 ] && [ -z "$NC_OUT" ] && [ "$s0" = "$(snapshot)" ] || { LEG_MSG="a different RUN report at the drain spawn ⇒ exit $NC_RC '${NC_OUT:0:80}'"; return 1; }
  ns_call "$drv" --start run --session-id s-run
  [ "$NC_RC" = 2 ] && [ -z "$NC_OUT" ] && grep -q 'run_already_started' <<<"$NC_ERR" && [ "$s0" = "$(snapshot)" ] || { LEG_MSG="--start run at the drain spawn ⇒ exit $NC_RC ${NC_ERR:0:100}"; return 1; }
  # the DRAIN report moves the pass on: the RUN report re-sent after it answers nothing (exit 2)
  ns_call "$drv" --non-interactive --result "$R_DRAIN"; s0="$(snapshot)"
  [ "$NC_RC" = 0 ] || { LEG_MSG="the DRAIN report ⇒ exit $NC_RC ${NC_ERR:0:100}"; return 1; }
  ns_call "$drv" --result "$R_RUN"
  [ "$NC_RC" = 2 ] && [ -z "$NC_OUT" ] && [ "$s0" = "$(snapshot)" ] || { LEG_MSG="the RUN report re-sent after the DRAIN report ⇒ exit $NC_RC '${NC_OUT:0:80}'"; return 1; }
  # a no-PR RUN: its byte-identical re-send re-prints the `done` `stopped`, a different one ⇒ exit 2
  new_scratch "$FIX/run-config-suppress-restore" || { LEG_MSG="scratch (no PR)"; return 1; }
  ns_call "$drv" --start run --session-id s-run
  ns_call "$drv" --result "$R_NOPR"; sp="$NC_OUT"; s0="$(snapshot)"
  printf '%s' "$sp" | jq -e '.do == "done" and .status == "stopped"' >/dev/null 2>&1 || { LEG_MSG="no-PR RUN report ⇒ '${sp:0:80}'"; return 1; }
  ns_call "$drv" --result "$R_NOPR"; [ "$NC_RC" = 0 ] && [ "$NC_OUT" = "$sp" ] && [ "$s0" = "$(snapshot)" ] || { LEG_MSG="the no-PR RUN report re-sent ⇒ exit $NC_RC '${NC_OUT:0:80}'"; return 1; }
  ns_call "$drv" --result "$(printf '%s' "$R_NOPR" | jq -c '.no_pr_why = "another why"')"
  [ "$NC_RC" = 2 ] && [ -z "$NC_OUT" ] && [ "$s0" = "$(snapshot)" ] || { LEG_MSG="a different no-PR RUN report ⇒ exit $NC_RC '${NC_OUT:0:80}'"; return 1; }
  return 0
}
# leg_rate_hint <driver> — an `unknown` failed row with a 429 in its session's closest-preceding STOP_FAILURE line
# parks rate_limit with a separate reason_hint line; a failed row older than the picked line is never a hit
leg_rate_hint() {
  local drv="$1" lg
  new_scratch "$FIX/rate-limit-park" || { LEG_MSG="scratch"; return 1; }
  lg="$CASE_ROOT/.supervisor/logs"; mkdir -p "$lg"
  printf '%s\n' '{"event":"agent_lifecycle","state":"failed","session_id":"s-hint","cc_session_id":"cc-hint","agent_scope":"main","reason":"unknown","ts":"2026-10-12T15:21:00Z"}' > "$lg/s-hint.jsonl"
  local lam=last_assistant_message   # the one stop-failure payload field the 429 hint reads (vendor-coupling manifest)
  printf '%s\n' "[2026-10-12T15:00:00Z] STOP_FAILURE {\"session_id\":\"cc-hint\",\"$lam\":\"ok\"}" \
    "[2026-10-12T15:20:59Z] STOP_FAILURE {\"session_id\":\"cc-hint\",\"$lam\":\"API Error: 429 Too Many Requests\"}" \
    "[2026-10-12T15:20:59Z] STOP_FAILURE {\"session_id\":\"other\",\"$lam\":\"fine\"}" > "$lg/failures.log"
  printf 'NEXT_STEP_FROM=rate-limit\n' > "$CASE_DIR/seams.from"
  NC_OUT="$(in_case "$drv" "$CASE_DIR/seams.from" bash "$drv" "$CASE_RF" --session-id s-hint 2>/dev/null)"; NC_RC=$?
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "park" and .pause_reason == "rate_limit"' >/dev/null 2>&1 \
    && in_order "$CASE_RF" "- pause_reason: rate_limit" "- reason_hint: rate_limit" "## Progress" \
    && grep -qF -- '| status: rate_limit |' "$CASE_RF" \
    || { LEG_MSG="429 hint ⇒ exit $NC_RC '${NC_OUT:0:100}' $(sed -n '/^## Current/,/^## Progress/p' "$CASE_RF" | tr '\n' ';')"; return 1; }
  new_scratch "$FIX/rate-limit-park" || { LEG_MSG="scratch (stale)"; return 1; }
  mkdir -p "$CASE_ROOT/.supervisor/logs"; printf 'NEXT_STEP_FROM=rate-limit\n' > "$CASE_DIR/seams.from"
  printf '%s\n' '{"event":"agent_lifecycle","state":"failed","session_id":"s-old","agent_scope":"main","reason":"rate_limit","ts":"2026-10-12T12:00:00Z"}' > "$CASE_ROOT/.supervisor/logs/s-old.jsonl"
  NC_OUT="$(in_case "$drv" "$CASE_DIR/seams.from" bash "$drv" "$CASE_RF" --session-id s-old 2>/dev/null)"; NC_RC=$?
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "done" and .status == "stopped"' >/dev/null 2>&1 \
    && cmp -s "$FIX/rate-limit-park/input.md" "$CASE_RF" \
    || { LEG_MSG="a row before the picked line ⇒ exit $NC_RC '${NC_OUT:0:100}'"; return 1; }
  return 0
}

# leg_drain_replay <driver> — the first drain's DRAIN report re-sent at the fix-now re-drain spawn ⇒ the spawn
# re-prints, nothing written; the re-drain's own DRAIN report then proceeds (the B14a rule for DRAIN reports)
leg_drain_replay() {
  local drv="$1" a b spawn s0 sc
  new_scratch "$FIX/dismissed-findings-decision-step" || { LEG_MSG="scratch"; return 1; }
  # the first drain's report names the case's own review-heal sidecar (its dismissed list makes the drafts);
  # the re-drain's carries the same block inline, at a new head
  sc="$CASE_ROOT/.supervisor/automate/$CASE_RUN.review-heal-result.md"
  a="$(jq -cn --arg f "$sc" '{review_heal_result_file: $f, ready_sha: "0000000"}')"
  b="$(jq -cn --rawfile t "$sc" '{review_heal_result: $t, ready_sha: "1111111"}')"
  printf 'NEXT_STEP_FROM=drain-result\n' > "$CASE_DIR/seams.from"
  NC_OUT="$(in_case "$drv" "$CASE_DIR/seams.from" bash "$drv" "$CASE_RF" --result "$a" 2>"$CASE_DIR/nc.err")"; NC_RC=$?
  printf '%s' "$NC_OUT" | jq -e '.do == "ask"' >/dev/null 2>&1 || { LEG_MSG="first DRAIN report ⇒ exit $NC_RC '${NC_OUT:0:100}' $(head -c 160 "$CASE_DIR/nc.err")"; return 1; }
  spawn="$NC_OUT"; s0="$(snapshot)"; ns_call "$drv" --result "$a"
  [ "$NC_RC" = 0 ] && [ "$NC_OUT" = "$spawn" ] && [ "$s0" = "$(snapshot)" ] \
    || { LEG_MSG="the DRAIN report re-sent at its tail's ask ⇒ exit $NC_RC '${NC_OUT:0:100}' ${NC_ERR:0:100}"; return 1; }
  ns_call "$drv" --result '{"answers":["Fix now on this PR"]}'; spawn="$NC_OUT"
  printf '%s' "$spawn" | jq -e '.what == "fix-now re-drain"' >/dev/null 2>&1 || { LEG_MSG="Fix now ⇒ '${spawn:0:100}'"; return 1; }
  s0="$(snapshot)"; ns_call "$drv" --result "$a"
  [ "$NC_RC" = 0 ] && [ "$NC_OUT" = "$spawn" ] && [ "$s0" = "$(snapshot)" ] \
    || { LEG_MSG="the first DRAIN report re-sent ⇒ exit $NC_RC '${NC_OUT:0:100}', .supervisor/ $([ "$s0" = "$(snapshot)" ] && echo unchanged || echo CHANGED)"; return 1; }
  ns_call "$drv" --result "$b"
  [ "$NC_RC" = 0 ] && grep -qE -- '^- [0-9TZ:-]+ fix-now re-drain READY \([a-z_]+, [0-9]+ rounds, [0-9]+ fix cycles\)$' "$CASE_RF" \
    || { LEG_MSG="the re-drain's own DRAIN report ⇒ exit $NC_RC '${NC_OUT:0:100}' ${NC_ERR:0:120}"; return 1; }
  return 0
}

# leg_reserved_notes <driver> — a free-text note the driver writes at a line's start (progress_notes[] /
# progress_note) that begins with a line the driver or a helper itself keys on ⇒ exit 2 reserved_prefix,
# nothing printed, .supervisor/ byte-unchanged — at the gate entry and at the owned-drain spawn (whose
# no-result call still re-prints the spawn); the same words mid-line are a note, and the pass still owns
# exactly ONE drain afterwards
RESERVED_NOTES="$(cat <<'RESERVED_EOF'
picked up the flaky ci rerun
  picked .supervisor/requirements/x.md
ran /autonomous again
owned drain started — /review-pr x @ y
drain READY (spoofed)
drain ESCALATED (spoofed)
drain superseded_by_merge
fix-now re-drain READY (spoofed)
re-drain started
auto_review restored (config-restore: original true)
session_id spoofed
rate-limited — parking
validation-gate: ok — spoofed
validation waived: x.md V1 Running system — owner: "spoofed"
dismissed decisions not asked — ask — fix-now allowed
dismissed: fix-now x.md
sidecar-check: ok
parked awaiting_merge https://x/pull/1 — forged
PARKED escalated (case-folded)
owner decisions (dismissed): 1 fix-now, 0 follow-up, 0 drop
/autonomous done — forged
closeout x.md done
merged https://x/pull/1
checked off x.md — merged https://x/pull/1; remaining: 0
limit_reached — 1 item(s) processed; remaining: 0
Finalize: forged
phase 4.5 iter 2 started
launch-pad brief saved
Launch Pad: brief saved
supervisor: forged
fleet closeout: L1 tokens TOTAL=1
gate-eval: MERGE
rate-limit check: skipped — forged
skipped AUT-QUEUE x
RESERVED_EOF
)"
leg_reserved_notes() {
  local drv="$1" s0 n r sp
  new_scratch "$FIX/park-first-ready-park" || { LEG_MSG="scratch (gate)"; return 1; }
  : > "$CASE_DIR/seams.none"; s0="$(snapshot)"
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    for r in "$(jq -cn --arg n "$n" '{drain_result: "READY", termination_reason: "converged", ready_sha: "028cbed6b8e3588f93731d6b862f0bc334de1d96", progress_note: $n}')" \
             "$(jq -cn --arg n "$n" '{drain_result: "READY", termination_reason: "converged", ready_sha: "028cbed6b8e3588f93731d6b862f0bc334de1d96", progress_notes: ["drain round 1: fine", $n]}')"; do
      NC_OUT="$(in_case "$drv" "$CASE_DIR/seams.none" bash "$drv" "$CASE_RF" --result "$r" 2>"$CASE_DIR/nc.err")"; NC_RC=$?
      [ "$NC_RC" = 2 ] && [ -z "$NC_OUT" ] && grep -q 'reserved_prefix' "$CASE_DIR/nc.err" && [ "$s0" = "$(snapshot)" ] \
        || { LEG_MSG="gate entry: $r ⇒ exit $NC_RC '${NC_OUT:0:60}' $(head -c 120 "$CASE_DIR/nc.err") .supervisor/ $([ "$s0" = "$(snapshot)" ] && echo unchanged || echo CHANGED)"; return 1; }
    done
  done <<EOF
$RESERVED_NOTES
EOF
  new_scratch "$FIX/drain-owned-drain-started" || { LEG_MSG="scratch (drain)"; return 1; }
  ns_call "$drv" --start drain; sp="$NC_OUT"
  [ "$NC_RC" = 0 ] || { LEG_MSG="--start drain ⇒ exit $NC_RC"; return 1; }
  s0="$(snapshot)"
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    for r in "$(printf '%s' "$R_DRAIN" | jq -c --arg n "$n" '.progress_notes = [$n]')" "$(printf '%s' "$R_DRAIN" | jq -c --arg n "$n" '.progress_note = $n')"; do
      ns_call "$drv" --non-interactive --result "$r"
      [ "$NC_RC" = 2 ] && [ -z "$NC_OUT" ] && grep -q 'reserved_prefix' <<<"$NC_ERR" && [ "$s0" = "$(snapshot)" ] \
        || { LEG_MSG="owned-drain spawn: '$n' ⇒ exit $NC_RC '${NC_OUT:0:60}' ${NC_ERR:0:120} .supervisor/ $([ "$s0" = "$(snapshot)" ] && echo unchanged || echo CHANGED)"; return 1; }
    done
  done <<EOF
$RESERVED_NOTES
EOF
  ns_call "$drv"; [ "$NC_OUT" = "$sp" ] && [ "$s0" = "$(snapshot)" ] || { LEG_MSG="no-result call after the refusals did not re-print the spawn / wrote"; return 1; }
  ns_call "$drv" --non-interactive --result "$(printf '%s' "$R_DRAIN" | jq -c '.progress_notes = ["drain round 1: picked up the flaky ci rerun"]')"
  [ "$NC_RC" = 0 ] && grep -qE -- '^- [0-9TZ:-]+ drain round 1: picked up the flaky ci rerun$' "$CASE_RF" \
    || { LEG_MSG="a mid-line 'picked' note ⇒ exit $NC_RC ${NC_ERR:0:120}"; return 1; }
  ns_call "$drv" --start drain
  [ "$NC_RC" = 2 ] && [ -z "$NC_OUT" ] && grep -q 'drain_already_owned' <<<"$NC_ERR" || { LEG_MSG="a second owned drain after the noted pass ⇒ exit $NC_RC '${NC_OUT:0:80}'"; return 1; }
  return 0
}

# leg_reader_prefixes <driver> — every ^-anchored ## Progress prefix a reader keys on (the regex literals at
# the reader sites: phase-timing.sh's item spans, read-token-ledger.sh's phase windows, the /lanes step
# classifier `cls`, the `^([^ ]+ )?<prefix>` awk matches of runfile.sh / readiness.sh / park-leaks.sh) is
# covered by the driver's NS_RESERVED_PREFIXES (a reserved prefix starts it, case folded) unless it is a
# named exception below; the extraction is sanity-anchored (a broken extractor fails, never passes empty)
# and each reserved prefix is named in the schema doc. A new reader prefix cannot drift past the list.
READER_PREFIX_EXCEPTIONS='drain |the drain-round notes (`drain round N: …`) are this prefix by design
launch|read-token-ledger.sh `launch[- ]?pad`: covered by its spellings launch-pad / launch pad / launchpad'
rp_literal() { # <regex> — the literal prefix(es) a ^-anchored regex starts with, one per line (a leading
  # group's alternatives each); `\x` is a literal x; stops at the first metachar (a char a ? / * makes optional dropped)
  RP_RE="$1" awk 'function lit(r,    o, i, c, n) {
      o = ""
      for (i = 1; i <= length(r); i++) {
        c = substr(r, i, 1)
        if (c == "\\") { while (substr(r, i + 1, 1) == "\\") i++; i++; c = substr(r, i, 1) }
        else if (index("[(.+*?$|{)^", c)) break
        n = substr(r, i + 1, 1)
        if (n == "?" || n == "*") break
        o = o c
      }
      return o }
    BEGIN { r = ENVIRON["RP_RE"]; sub(/^\^/, "", r); sub(/^- /, "", r); sub(/^\(\[\^ \]\+ \)\?/, "", r)
      if (substr(r, 1, 1) == "(") {
        d = 0; g = ""
        for (i = 2; i <= length(r); i++) { c = substr(r, i, 1); if (c == "(") d++; if (c == ")") { if (!d) break; d-- } g = g c }
        n = split(g, alt, "|"); for (j = 1; j <= n; j++) print lit(alt[j])
      } else print lit(r) }'
}
rp_extract() { # the reader regexes (one per line) → their literal prefixes, lower-cased, de-duplicated
  {
    # jq: a ^-anchored test(), or the ^-anchored alternatives of an unanchored one (`a|^drain |b`)
    { grep -oE 'test\("[^"]*"' "$HERE/read-token-ledger.sh"
      awk '/def cls:/,/else \[\] end;/' "$HERE/automate-lanes.d/status-read.sh" | grep -oE 'test\("[^"]*"'
    } | sed 's/^test("//; s/"$//' | while IFS= read -r re; do
      case "$re" in "^"*) printf '%s\n' "$re" ;; *) printf '%s\n' "$re" | tr '|' '\n' | grep '^\^' ;; esac
    done
    grep -oE 'p_first\(r"[^"]*"|re\.match\(r"[^"]*", t2?\)|t2?\.startswith\("[^"]*"\)' "$HERE/phase-timing.sh" \
      | sed -E 's/^p_first\(r"//; s/^re\.match\(r"/^/; s/", t2?\)$//; s/^t2?\.startswith\("/^/; s/"\)$//; s/"$//'
    # an awk /regex/ ends at its unescaped `/`, a quoted 'regex' at its quote; comment lines are prose, not readers
    for f in automate-helpers.d/runfile.sh automate-lanes.d/readiness.sh automate-lanes.d/park-leaks.sh; do
      grep -vE '^[[:space:]]*#' "$HERE/$f" | grep -oE '/\^(- )?\(\[\^ \]\+ \)\?(\\/|[^/])*/' | sed 's|^/||; s|/$||'
      grep -vE '^[[:space:]]*#' "$HERE/$f" | grep -oE "'\^(- )?\(\[\^ \]\+ \)\?[^']*'" | sed "s/^'//; s/'\$//"
    done
  } | while IFS= read -r re; do [ -n "$re" ] && rp_literal "$re"; done | tr '[:upper:]' '[:lower:]' | grep -v '^$' | env LC_ALL=C sort -u
}
leg_reader_prefixes() {
  local drv="$1" lits list miss="" l p ok_ e
  list="$(sed -n "/^NS_RESERVED_PREFIXES='/,/'\$/p" "$drv" | sed "s/^NS_RESERVED_PREFIXES='//; s/'\$//" | tr '[:upper:]' '[:lower:]')"
  [ "$(grep -c . <<<"$list")" -ge 20 ] || { LEG_MSG="NS_RESERVED_PREFIXES not read from the driver ($(grep -c . <<<"$list") entries)"; return 1; }
  lits="$(rp_extract)"
  for e in 'parked' 'finalize:' 'phase 4.5 iter ' 'owner decisions' '/autonomous done' 'picked ' 'ran /autonomous' 'skipped aut-queue' 'launch' 'drain '; do
    grep -qxF -- "$e" <<<"$lits" || { LEG_MSG="extractor sanity: '$e' not extracted from the readers (got: $(tr '\n' ',' <<<"$lits"))"; return 1; }
  done
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    ok_=0
    while IFS= read -r p; do [ -n "$p" ] || continue; case "$l" in "$p"*) ok_=1; break ;; esac; done <<<"$list"
    if [ "$ok_" = 0 ]; then
      e="$(grep -F -- "$l|" <<<"$READER_PREFIX_EXCEPTIONS" | head -n 1)"
      [ "${e%%|*}" = "$l" ] || miss="$miss '$l'"
    fi
  done <<<"$lits"
  [ -z "$miss" ] || { LEG_MSG="reader prefixes not in NS_RESERVED_PREFIXES:$miss"; return 1; }
  for p in launch-pad 'launch pad' launchpad; do grep -qxF -- "$p" <<<"$list" || { LEG_MSG="the 'launch' exception needs '$p' reserved"; return 1; }; done
  # the schema doc names each reserved prefix (its progress_note bullet)
  l="$(grep -F -- '- **`progress_note`**:' "$HERE/../docs/result-schemas/automate-run.md" | tr '[:upper:]' '[:lower:]')"
  while IFS= read -r p; do [ -n "$p" ] || continue; case "$l" in *"\`$p\`"*) ;; *) miss="$miss '$p'" ;; esac; done <<<"$list"
  [ -z "$miss" ] || { LEG_MSG="reserved prefixes the schema doc's progress_note bullet does not name:$miss"; return 1; }
  RP_N="$(grep -c . <<<"$lits")"
  return 0
}

# leg_session_id <driver> — RUN never starts without this loop's session id (exit 2 session_id_missing /
# session_id_malformed, nothing written); a rate_limit row in that session's log parks at the end of RUN;
# a rate-limit check that could not read its log (no session id at the step, no log) writes ONE pinned
# skipped line instead of reading "clean"
leg_session_id() {
  local drv="$1" s0
  new_scratch "$FIX/run-config-suppress-restore" || { LEG_MSG="scratch"; return 1; }
  s0="$(snapshot)"
  ns_call "$drv" --start run
  [ "$NC_RC" = 2 ] && [ -z "$NC_OUT" ] && grep -q 'next-step: session_id_missing — ' <<<"$NC_ERR" && [ "$s0" = "$(snapshot)" ] && cmp -s "$FIX/run-config-suppress-restore/input.md" "$CASE_RF" \
    || { LEG_MSG="--start run without --session-id ⇒ exit $NC_RC '${NC_OUT:0:80}' ${NC_ERR:0:120}"; return 1; }
  ns_call "$drv" --start run --session-id '../../etc'
  [ "$NC_RC" = 2 ] && [ -z "$NC_OUT" ] && grep -q 'next-step: session_id_malformed — ' <<<"$NC_ERR" && [ "$s0" = "$(snapshot)" ] \
    || { LEG_MSG="--start run with a malformed --session-id ⇒ exit $NC_RC '${NC_OUT:0:80}' ${NC_ERR:0:120}"; return 1; }
  mkdir -p "$CASE_ROOT/.supervisor/logs"
  printf '%s\n' '{"event":"agent_lifecycle","state":"failed","session_id":"loop-1","agent_scope":"main","reason":"rate_limit","ts":"2026-10-14T10:00:00Z"}' > "$CASE_ROOT/.supervisor/logs/loop-1.jsonl"
  ns_call "$drv" --start run --session-id loop-1
  [ "$NC_RC" = 0 ] || { LEG_MSG="--start run --session-id loop-1 ⇒ exit $NC_RC ${NC_ERR:0:120}"; return 1; }
  ns_call "$drv" --result "$R_RUN"
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "park" and .pause_reason == "rate_limit"' >/dev/null 2>&1 && grep -q ' rate-limited — parking' "$CASE_RF" \
    || { LEG_MSG="a rate_limit row in the loop's own log (session id persisted from --start run) ⇒ exit $NC_RC '${NC_OUT:0:100}'"; return 1; }
  # the check reached without a session id (the step seam) / with no log for it ⇒ the pinned skipped line
  new_scratch "$FIX/rate-limit-park" || { LEG_MSG="scratch (rate-limit)"; return 1; }
  printf 'NEXT_STEP_FROM=rate-limit\n' > "$CASE_DIR/seams.from"
  NC_OUT="$(in_case "$drv" "$CASE_DIR/seams.from" bash "$drv" "$CASE_RF" 2>/dev/null)"; NC_RC=$?
  [ "$NC_RC" = 0 ] && grep -qE -- '^- [0-9TZ:-]+ rate-limit check: skipped — no session id$' "$CASE_RF" \
    || { LEG_MSG="rate-limit with no session id ⇒ exit $NC_RC, no pinned skipped line"; return 1; }
  new_scratch "$FIX/rate-limit-park" || { LEG_MSG="scratch (rate-limit, no log)"; return 1; }
  printf 'NEXT_STEP_FROM=rate-limit\n' > "$CASE_DIR/seams.from"
  NC_OUT="$(in_case "$drv" "$CASE_DIR/seams.from" bash "$drv" "$CASE_RF" --session-id s-nolog 2>/dev/null)"; NC_RC=$?
  [ "$NC_RC" = 0 ] && grep -qE -- '^- [0-9TZ:-]+ rate-limit check: skipped — no session log \.supervisor/logs/s-nolog\.jsonl$' "$CASE_RF" \
    && [ "$(grep -c 'rate-limit check: skipped' "$CASE_RF")" = 1 ] \
    || { LEG_MSG="rate-limit with no log ⇒ exit $NC_RC, pinned skipped line $(grep -c 'rate-limit check: skipped' "$CASE_RF")×"; return 1; }
  return 0
}

# --------------------------------------------------------------------------------------
# PICK / RECONCILE / resume legs (automate-speed/08)
# --------------------------------------------------------------------------------------
P_SID=auto-2026-10-15-040641
P_RUN=automate-2026-10-13-181331
p_call() { # <driver> <args…> — a call WITHOUT the run file (the resume entry); sets NC_OUT NC_RC NC_ERR
  local drv="$1"; shift
  NC_OUT="$(in_case "$drv" "$R_SEAMS" bash "$drv" "$@" 2>"$CASE_DIR/nc.err")"; NC_RC=$?
  NC_ERR="$(cat "$CASE_DIR/nc.err")"
}
p_seamed() { # <seams file> <driver> <args…> — one driver call (run file first) under <seams>
  local sf="$1" drv="$2"; shift 2
  NC_OUT="$(in_case "$drv" "$sf" bash "$drv" "$CASE_RF" "$@" 2>"$CASE_DIR/nc.err")"; NC_RC=$?
  NC_ERR="$(cat "$CASE_DIR/nc.err")"
}
p_no_new_pick() { # <copy of the run file before> — no new `picked` line, ## Current's item line unchanged
  [ "$(grep -c ' picked ' "$CASE_RF")" = "$(grep -c ' picked ' "$1")" ] \
    && [ "$(grep -m1 '^- item: ' "$CASE_RF")" = "$(grep -m1 '^- item: ' "$1")" ]
}
# leg_open_pr_park <driver> — AC2: the in-flight item's PR is OPEN (awaiting_merge, escalated) ⇒ `--start pick`
# parks (## Status: paused, pause_reason unchanged), the run lock it took is released, and NO picked line /
# no current-set for a new item; this run's own trail PR open ⇒ the trail_pr_open park, the same guarantees.
# The gh rows make every later PICK step clear, so a PICK that skipped the park would reach current-set + picked
leg_open_pr_park() {
  local drv="$1" st
  for st in awaiting_merge escalated; do
    new_scratch "$FIX/resume-glob-finalize" || { LEG_MSG="scratch"; return 1; }
    printf '0\tpr view https://github.com/vikashruhilgit/loomwright/pull/555 --json state,mergedAt\t{"state":"OPEN","mergedAt":null}\n0\tpr list --state open *\t[]\n0\tpr list *\t[]\n0\tauth status*\t\n' >> "$CASE_GH"
    if [ "$st" = escalated ]; then
      in_case "$drv" "$R_SEAMS" bash "$H" current-set "$CASE_RF" --item .supervisor/requirements/automate-followups/39a-sweep-and-janitor.md \
        --status escalated --pr https://github.com/vikashruhilgit/loomwright/pull/555 --branch feature/af39a-sweep --pause-reason escalated >/dev/null 2>&1 \
        || { LEG_MSG="escalated: seed refused"; return 1; }
    fi
    cp "$CASE_RF" "$CASE_DIR/before.md"
    ns_call "$drv" --start pick --session-id "$P_SID"
    [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e --arg s "$st" '.do == "park" and .step == "reconcile" and .pause_reason == $s' >/dev/null 2>&1 \
      || { LEG_MSG="$st: --start pick ⇒ exit $NC_RC '${NC_OUT:0:160}' ${NC_ERR:0:160}"; return 1; }
    p_no_new_pick "$CASE_DIR/before.md" || { LEG_MSG="$st: a picked line or a new ## Current item was written"; return 1; }
    grep -qx '## Status: paused' "$CASE_RF" || { LEG_MSG="$st: ## Status is not paused"; return 1; }
    grep -q "^lock acquire --owner automate:$P_RUN" "$CASE_DIR/rec.log" && grep -q "^lock release --owner automate:$P_RUN" "$CASE_DIR/rec.log" \
      || { LEG_MSG="$st: the run lock was not acquired then released: $(tr '\n' ';' < "$CASE_DIR/rec.log" | cut -c1-200)"; return 1; }
  done
  golden_case pick-time-trail-gate-park "$drv" || { LEG_MSG="trail PR open: $GC_MSG"; return 1; }
  printf '%s' "$LAST_OUT" | jq -e '.do == "park" and .pause_reason == "trail_pr_open"' >/dev/null 2>&1 \
    && ! grep -q ' picked .supervisor/requirements/parallel-automate/18' "$CASE_RF" && grep -q '^lock release ' "$CASE_DIR/rec.log" \
    || { LEG_MSG="trail PR open: not the trail_pr_open park, a picked line, or the lock kept"; return 1; }
  return 0
}
# leg_reconcile_leftover <driver> — AC3: RECONCILE's closeout leaves 5 leftovers ⇒ interactive: AUT-LEFTOVER
# (header "", the catalog labels, 4 questions in the first call), no PICK; cant_ask ⇒ the closeout_leftover park
# (one `closeout leftover:` line per leftover, no trail-pr, no picked); --non-interactive ⇒ that park directly
P_LEFT='closeout: bogus — a
closeout: bogus — b
closeout: bogus — c
closeout: bogus — d
closeout: bogus — e'
leg_reconcile_leftover() {
  local drv="$1" mode n
  for mode in ask nonint; do
    new_scratch "$FIX/reconcile-closeout-merged" || { LEG_MSG="scratch"; return 1; }
    printf '%s\n' "$P_LEFT" > "$CASE_DIR/co.out"
    printf 'NEXT_STEP_FROM=reconcile\nNEXT_STEP_CLOSEOUT_OUT=%s\n' "$CASE_DIR/co.out" > "$CASE_DIR/seams.lo"
    cp "$CASE_RF" "$CASE_DIR/before.md"
    if [ "$mode" = ask ]; then
      p_seamed "$CASE_DIR/seams.lo" "$drv" --session-id "$P_SID"
      [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "ask" and .gate == "AUT-LEFTOVER" and .header == "" and (.questions | length) == 4
          and .options == ["Clean up now","Keep and continue","Stop"] and .cant_ask == "closeout_leftover park"' >/dev/null 2>&1 \
        || { LEG_MSG="interactive: not the AUT-LEFTOVER ask: exit $NC_RC '${NC_OUT:0:200}' ${NC_ERR:0:160}"; return 1; }
      p_no_new_pick "$CASE_DIR/before.md" && ! grep -q 'trail-gate' <(diff "$CASE_DIR/before.md" "$CASE_RF") \
        || { LEG_MSG="interactive: the PICK went on past the leftover"; return 1; }
      ns_call "$drv" --result '{"cant_ask":true}'
    else
      p_seamed "$CASE_DIR/seams.lo" "$drv" --session-id "$P_SID" --non-interactive
    fi
    [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "park" and .pause_reason == "closeout_leftover"' >/dev/null 2>&1 \
      || { LEG_MSG="$mode: not the closeout_leftover park: exit $NC_RC '${NC_OUT:0:200}' ${NC_ERR:0:160}"; return 1; }
    n="$(grep -cE "^- [0-9TZ:-]+ closeout leftover: $P_RUN unknown bogus — [a-e]\$" "$CASE_RF")"
    [ "$n" = 5 ] && grep -qx '## Status: paused' "$CASE_RF" && p_no_new_pick "$CASE_DIR/before.md" \
      && ! grep -q 'trail-pr' < <(diff "$CASE_DIR/before.md" "$CASE_RF") \
      || { LEG_MSG="$mode: $n leftover line(s) (want 5), or a picked / trail-pr line, or not paused"; return 1; }
  done
  return 0
}
# leg_resume_entry <driver> — AC4: one incomplete run, no --run, can't ask ⇒ the
# `automate: resume_requires_flag_non_interactive <run_id>` stop, NOTHING written (.supervisor/ byte-unchanged);
# interactive ⇒ AUT-RESUME (header + the catalog labels), re-printed by a second call; its cant_ask ⇒ the same
# stop, Start new ⇒ `done` choice start_new — the run file unchanged throughout; continue on a crash-stranded
# config backup ⇒ config.json restored byte-for-byte, the backup deleted, no line
leg_resume_entry() {
  local drv="$1" s0 ask1 ad
  new_scratch "$FIX/resume-glob-finalize" || { LEG_MSG="scratch"; return 1; }
  ad="$CASE_ROOT/.supervisor/automate"; s0="$(snapshot)"
  p_call "$drv" --resume "$ad" --non-interactive --session-id "$P_SID"
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e --arg r "$P_RUN" '.do == "done" and .step == "resume" and .stop == "resume_requires_flag_non_interactive"
      and (.message | startswith("automate: resume_requires_flag_non_interactive " + $r))' >/dev/null 2>&1 && [ "$s0" = "$(snapshot)" ] \
    || { LEG_MSG="can't ask: exit $NC_RC '${NC_OUT:0:200}' ${NC_ERR:0:120}, .supervisor/ $([ "$s0" = "$(snapshot)" ] && echo unchanged || echo CHANGED)"; return 1; }
  p_call "$drv" --resume "$ad" --session-id "$P_SID"; ask1="$NC_OUT"
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e --arg r "$P_RUN" '.do == "ask" and .gate == "AUT-RESUME" and .header == "AUT-RESUME"
      and .options == ["Continue","Start new","Archive"] and (.run_file | endswith("/" + $r + ".md"))' >/dev/null 2>&1 \
    || { LEG_MSG="interactive: not the AUT-RESUME ask: exit $NC_RC '${NC_OUT:0:200}' ${NC_ERR:0:120}"; return 1; }
  p_call "$drv" --resume "$ad" --session-id "$P_SID"
  [ "$NC_OUT" = "$ask1" ] || { LEG_MSG="a second --resume did not re-print the pending AUT-RESUME ask"; return 1; }
  ns_call "$drv" --result '{"cant_ask":true}'
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.stop == "resume_requires_flag_non_interactive"' >/dev/null 2>&1 \
    || { LEG_MSG="cant_ask: exit $NC_RC '${NC_OUT:0:160}'"; return 1; }
  p_call "$drv" --resume "$ad" --session-id "$P_SID"; ns_call "$drv" --result '{"answers":["Start new"]}'
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "done" and .choice == "start_new"' >/dev/null 2>&1 \
    || { LEG_MSG="Start new: exit $NC_RC '${NC_OUT:0:160}' ${NC_ERR:0:120}"; return 1; }
  cmp -s "$FIX/resume-glob-finalize/input.md" "$CASE_RF" || { LEG_MSG="the run file was written by an ask / a stop / a choice"; return 1; }
  # continue (--run): RECONCILE restores the crash-stranded backup (resume-config-crash-restore)
  new_scratch "$FIX/resume-config-crash-restore" || { LEG_MSG="scratch (restore)"; return 1; }
  printf 'NEXT_STEP_UNTIL=reconcile\n' > "$CASE_DIR/seams.u"
  NC_OUT="$(in_case "$drv" "$CASE_DIR/seams.u" bash "$drv" --resume "$CASE_ROOT/.supervisor/automate" --run "$P_RUN" --non-interactive --session-id "$P_SID" 2>"$CASE_DIR/nc.err")"; NC_RC=$?
  [ "$NC_RC" = 0 ] && [ -z "$NC_OUT" ] && [ "$(cat "$CASE_ROOT/.supervisor/config.json")" = '{"repo_allowlist":["vikashruhilgit/loomwright"]}' ] \
    && [ ! -e "$CASE_ROOT/.supervisor/automate/$P_RUN.config-backup.json" ] && cmp -s "$FIX/resume-config-crash-restore/input.md" "$CASE_RF" \
    || { LEG_MSG="continue: config not restored / backup left / run file written: exit $NC_RC $(head -c 160 "$CASE_DIR/nc.err")"; return 1; }
  return 0
}
# leg_start_closeout_others <driver> — AC3 at START: closeout-others' `run_lock_held` row (a live holder) is not a
# leftover — its record line is appended, no gate, no park; a `leftover` row goes through the leftover gate
# before the first PICK (--non-interactive ⇒ the closeout_leftover park). A wrapper automate-helpers.sh beside a
# driver copy prints the fixed closeout-others answer (a live lock holder cannot be staged hermetically)
co_helpers() { # <driver path> <closeout-others output file>
  local d; d="$(dirname "$1")"
  rm -f "$d/automate-helpers.sh"
  printf '#!/usr/bin/env bash\nif [ "${1:-}" = closeout-others ]; then cat "%s"; exit 0; fi\nexec bash "%s" "$@"\n' "$2" "$H" > "$d/automate-helpers.sh"
}
leg_start_closeout_others() {
  local drv="$1" co="$WORK/co-others.out"
  co_helpers "$drv" "$co"
  printf 'closeout-others: automate-2026-09-30-054439 .supervisor/requirements/x.md https://github.com/o/r/pull/1\nrun_lock_held\tautomate-2026-09-30-054439\t.supervisor/requirements/x.md\thttps://github.com/o/r/pull/1\tlock\trun lock held by automate:z (live pid 4242)\ncloseout-others: record — cross-run closeout automate-2026-09-30-054439 .supervisor/requirements/x.md: run_lock_held — run lock held by automate:z (live pid 4242); retried at the next start\n' > "$co"
  new_scratch "$FIX/resume-glob-finalize" || { LEG_MSG="scratch"; return 1; }
  printf 'NEXT_STEP_UNTIL=resume-continue\n' > "$CASE_DIR/seams.u"
  NC_OUT="$(in_case "$drv" "$CASE_DIR/seams.u" bash "$drv" --resume "$CASE_ROOT/.supervisor/automate" --run "$P_RUN" --non-interactive --session-id "$P_SID" 2>"$CASE_DIR/nc.err")"; NC_RC=$?
  grep -qE '^- [0-9TZ:-]+ cross-run closeout automate-2026-09-30-054439 \.supervisor/requirements/x\.md: run_lock_held — ' "$CASE_RF" \
    && ! grep -q 'closeout leftover' "$CASE_RF" && ! grep -q 'pause_reason: closeout_leftover' "$CASE_RF" && [ "$NC_RC" = 0 ] \
    || { LEG_MSG="run_lock_held row: exit $NC_RC '${NC_OUT:0:120}' $(head -c 160 "$CASE_DIR/nc.err") — record line / no leftover gate"; return 1; }
  printf 'leftover\tautomate-2026-09-30-054439\t.supervisor/requirements/x.md\thttps://github.com/o/r/pull/1\tworktree\tkept /tmp/wt (dirty)\ncloseout-others: record — cross-run closeout automate-2026-09-30-054439 .supervisor/requirements/x.md: leftover worktree — kept /tmp/wt (dirty)\n' > "$co"
  new_scratch "$FIX/resume-glob-finalize" || { LEG_MSG="scratch"; return 1; }
  p_call "$drv" --resume "$CASE_ROOT/.supervisor/automate" --run "$P_RUN" --non-interactive --session-id "$P_SID"
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "park" and .pause_reason == "closeout_leftover"' >/dev/null 2>&1 \
    && grep -qE '^- [0-9TZ:-]+ closeout leftover: automate-2026-09-30-054439 worktree kept /tmp/wt \(dirty\)$' "$CASE_RF" \
    && ! grep -q "^lock acquire " "$CASE_DIR/rec.log" \
    || { LEG_MSG="leftover row: exit $NC_RC '${NC_OUT:0:160}' ${NC_ERR:0:120} (want the closeout_leftover park before the PICK lock)"; return 1; }
  return 0
}
# leg_pick_order <driver> — current-set BEFORE the `picked` line: on a never-set ## Current the PICK pair writes
# both (exit 0); the reverse order trips progress-append's exit 3 current_not_set, which must surface
leg_pick_order() {
  local drv="$1"
  new_scratch "$FIX/resume-current-rebuild" || { LEG_MSG="scratch"; return 1; }
  printf 'NEXT_STEP_FROM=picked\nNEXT_STEP_UNTIL=picked\n' > "$CASE_DIR/seams.p"
  p_seamed "$CASE_DIR/seams.p" "$drv" --session-id "$P_SID"
  [ "$NC_RC" = 0 ] && grep -qxF -- '- item: .supervisor/requirements/automate-followups/14-closeout-fail-safe.md | status: running | pr: null | branch: null' "$CASE_RF" \
    && grep -qE '^- [0-9TZ:-]+ picked \.supervisor/requirements/automate-followups/14-closeout-fail-safe\.md$' "$CASE_RF" \
    || { LEG_MSG="exit $NC_RC ${NC_ERR:0:200}"; return 1; }
  return 0
}
# leg_brief_repair <driver> — brief-repair-merged through the driver: RECONCILE's closeout (gh authenticated)
# passes the repairing brief-repair line through and moves the brief (the case's own steps are a pure helper
# call, not a driver step — evidence file, AC1 exceptions)
leg_brief_repair() {
  local drv="$1"
  new_scratch "$FIX/brief-repair-merged" || { LEG_MSG="scratch"; return 1; }
  printf '0\tauth status*\t\n' >> "$CASE_GH"
  printf 'NEXT_STEP_FROM=reconcile\nNEXT_STEP_UNTIL=reconcile\n' > "$CASE_DIR/seams.b"
  p_seamed "$CASE_DIR/seams.b" "$drv" --session-id "$P_SID"
  [ "$NC_RC" = 0 ] && grep -qE '^- [0-9TZ:-]+ closeout https://github\.com/vikashruhilgit/loomwright/pull/542: brief-repair: repaired \.supervisor/jobs/in-progress/2026-10-14-af39b-run-lock-holder\.md → \.supervisor/jobs/done/2026-10-14-af39b-run-lock-holder\.md' "$CASE_RF" \
    && [ -f "$CASE_ROOT/.supervisor/jobs/done/2026-10-14-af39b-run-lock-holder.md" ] && [ ! -e "$CASE_ROOT/.supervisor/jobs/in-progress/2026-10-14-af39b-run-lock-holder.md" ] \
    || { LEG_MSG="exit $NC_RC ${NC_ERR:0:160}; brief-repair line / brief move missing"; return 1; }
  return 0
}
# leg_leftover_retry <driver> — a crashed (exit 1) or silent (exit 0, no answer) closeout-classify is never a
# resolved close-out: on the AUT-LEFTOVER "Clean up now" retry the row stays a leftover (the re-ask without
# Clean up now, then cant_ask ⇒ the closeout_leftover park naming closeout-classify) — no trail gate, no PICK;
# a silent classify at RECONCILE itself is one leftover too. A wrapper automate-helpers.sh beside a driver
# copy makes closeout print nothing and closeout-classify fail once <driver dir>/cls.mode is written
cls_helpers() { # <driver path>
  local d; d="$(dirname "$1")"
  rm -f "$d/automate-helpers.sh"
  printf '#!/usr/bin/env bash\nm="$(cat "%s/cls.mode" 2>/dev/null)"\nif [ -n "$m" ]; then\n  case "${1:-}" in\n    closeout) exit 0 ;;\n    closeout-classify) cat >/dev/null; [ "$m" = fail ] && exit 1; exit 0 ;;\n  esac\nfi\nexec bash "%s" "$@"\n' "$d" "$H" > "$d/automate-helpers.sh"
}
leg_leftover_retry() {
  local drv="$1" mode want d; d="$(dirname "$drv")"
  for mode in fail empty; do
    new_scratch "$FIX/reconcile-closeout-merged" || { LEG_MSG="scratch"; return 1; }
    rm -f "$d/cls.mode"
    printf 'closeout: bogus — a\n' > "$CASE_DIR/co.out"
    printf 'NEXT_STEP_FROM=reconcile\nNEXT_STEP_CLOSEOUT_OUT=%s\n' "$CASE_DIR/co.out" > "$CASE_DIR/seams.lo"
    cp "$CASE_RF" "$CASE_DIR/before.md"
    p_seamed "$CASE_DIR/seams.lo" "$drv" --session-id "$P_SID"
    [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "ask" and .gate == "AUT-LEFTOVER" and (.questions | length) == 1' >/dev/null 2>&1 \
      || { LEG_MSG="$mode: not the first AUT-LEFTOVER ask: exit $NC_RC '${NC_OUT:0:160}'"; return 1; }
    printf '%s\n' "$mode" > "$d/cls.mode"
    ns_call "$drv" --result '{"answers":["Clean up now"]}'
    [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "ask" and .gate == "AUT-LEFTOVER" and .options == ["Keep and continue","Stop"]
        and (.question | contains("closeout-classify"))' >/dev/null 2>&1 \
      || { LEG_MSG="$mode: Clean up now with a $mode classify was not re-asked as a leftover: exit $NC_RC '${NC_OUT:0:200}' ${NC_ERR:0:120}"; return 1; }
    p_no_new_pick "$CASE_DIR/before.md" && ! grep -q 'trail-gate' < <(diff "$CASE_DIR/before.md" "$CASE_RF") \
      || { LEG_MSG="$mode: the PICK went on past a $mode classify"; return 1; }
    ns_call "$drv" --result '{"cant_ask":true}'
    want=1; [ "$mode" = empty ] && want=0
    [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "park" and .pause_reason == "closeout_leftover"' >/dev/null 2>&1 \
      && grep -qE "^- [0-9TZ:-]+ closeout leftover: $P_RUN closeout-classify exited $want with no verdict — kept as a leftover\$" "$CASE_RF" \
      || { LEG_MSG="$mode: not the closeout_leftover park naming closeout-classify: exit $NC_RC '${NC_OUT:0:160}'"; return 1; }
  done
  # a silent classify at RECONCILE itself: one leftover row, never an empty gate
  new_scratch "$FIX/reconcile-closeout-merged" || { LEG_MSG="scratch (reconcile)"; return 1; }
  printf 'closeout: bogus — a\n' > "$CASE_DIR/co.out"; printf 'empty\n' > "$d/cls.mode"
  printf 'NEXT_STEP_FROM=reconcile\nNEXT_STEP_CLOSEOUT_OUT=%s\n' "$CASE_DIR/co.out" > "$CASE_DIR/seams.lo"
  p_seamed "$CASE_DIR/seams.lo" "$drv" --session-id "$P_SID"; rm -f "$d/cls.mode"
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "ask" and .gate == "AUT-LEFTOVER" and (.questions | length) == 1
      and (.question | contains("closeout-classify — exited 0 with no verdict"))' >/dev/null 2>&1 \
    || { LEG_MSG="reconcile: a silent classify is not one leftover: exit $NC_RC '${NC_OUT:0:200}'"; return 1; }
  return 0
}
# leg_coordinator <driver> — a `--parallel` coordinator run (`- parallel: N` in ## Run Config, N = 2 and the
# single-lane N = 1) is never picked in the primary: a continue (--run <id> non-interactive, the AUT-RESUME
# Continue) and --start pick print done / stopped `coordinator_run` naming lanes.md's loop, with .supervisor/
# byte-unchanged on the fresh calls (the run file throughout) and no run-lock acquire; a BARE start is not a
# continue (AC4): --non-interactive ⇒ the resume_requires_flag_non_interactive stop, interactive ⇒ AUT-RESUME
leg_coordinator() {
  local drv="$1" n s0 ad w
  for n in 2 1; do
    new_scratch "$FIX/resume-glob-finalize" || { LEG_MSG="scratch"; return 1; }
    awk -v n="$n" '{ print } /^## Run Config$/ { print "- parallel: " n }' "$CASE_RF" > "$CASE_RF.t" && mv "$CASE_RF.t" "$CASE_RF"
    grep -qx -- "- parallel: $n" "$CASE_RF" || { LEG_MSG="parallel: $n not seeded"; return 1; }
    w="per-wave loop"; [ "$n" = 1 ] && w="Single-lane mode"
    ad="$CASE_ROOT/.supervisor/automate"; s0="$(snapshot)"
    p_call "$drv" --resume "$ad" --run "$P_RUN" --non-interactive --session-id "$P_SID"
    [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e --arg w "$w" --argjson n "$n" '.do == "done" and .status == "stopped" and .stop == "coordinator_run"
        and .step == "rebuild" and .parallel == $n and (.message | contains($w))' >/dev/null 2>&1 \
      || { LEG_MSG="parallel $n, --resume --run: exit $NC_RC '${NC_OUT:0:200}' ${NC_ERR:0:120}"; return 1; }
    p_call "$drv" --resume "$ad" --non-interactive --session-id "$P_SID"
    [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e --arg r "$P_RUN" '.step == "resume" and .stop == "resume_requires_flag_non_interactive"
        and (.message | startswith("automate: resume_requires_flag_non_interactive " + $r))' >/dev/null 2>&1 \
      || { LEG_MSG="parallel $n, bare --non-interactive --resume: not the resume_requires_flag stop: exit $NC_RC '${NC_OUT:0:200}'"; return 1; }
    ns_call "$drv" --start pick --session-id "$P_SID"
    [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.step == "pick" and .stop == "coordinator_run"' >/dev/null 2>&1 \
      || { LEG_MSG="parallel $n, --start pick: exit $NC_RC '${NC_OUT:0:200}'"; return 1; }
    [ "$s0" = "$(snapshot)" ] && ! grep -q '^lock acquire ' "$CASE_DIR/rec.log" \
      || { LEG_MSG="parallel $n: .supervisor/ written or the run lock acquired"; return 1; }
    p_call "$drv" --resume "$ad" --session-id "$P_SID"
    [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "ask" and .gate == "AUT-RESUME"' >/dev/null 2>&1 \
      || { LEG_MSG="parallel $n, bare interactive --resume: not the AUT-RESUME ask: exit $NC_RC '${NC_OUT:0:200}'"; return 1; }
    ns_call "$drv" --result '{"answers":["Continue"]}'
    [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.step == "rebuild" and .stop == "coordinator_run"' >/dev/null 2>&1 \
      || { LEG_MSG="parallel $n, Continue: not coordinator_run: exit $NC_RC '${NC_OUT:0:200}' ${NC_ERR:0:120}"; return 1; }
    grep -qx -- "- parallel: $n" "$CASE_RF" && sed '/^- parallel: /d' "$CASE_RF" | cmp -s - "$FIX/resume-glob-finalize/input.md" \
      && ! grep -q '^lock acquire ' "$CASE_DIR/rec.log" \
      || { LEG_MSG="parallel $n: the run file written or the run lock acquired at the ask / Continue"; return 1; }
  done
  # whitespace-tolerant marker (the `_lanes_single_parent` convention): `- parallel:2`, a trailing comment,
  # an extra space before `parallel:`
  local v
  for v in '- parallel:2' '- parallel: 2  # wave' '-  parallel: 2'; do
    new_scratch "$FIX/resume-glob-finalize" || { LEG_MSG="scratch"; return 1; }
    V="$v" awk '{ print } /^## Run Config$/ { print ENVIRON["V"] }' "$CASE_RF" > "$CASE_RF.t" && mv "$CASE_RF.t" "$CASE_RF"
    grep -qxF -- "$v" "$CASE_RF" || { LEG_MSG="'$v' not seeded"; return 1; }
    s0="$(snapshot)"
    ns_call "$drv" --start pick --non-interactive --session-id "$P_SID"
    [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.step == "pick" and .stop == "coordinator_run" and .parallel == 2' >/dev/null 2>&1 \
      || { LEG_MSG="'$v', --start pick --non-interactive: exit $NC_RC '${NC_OUT:0:200}'"; return 1; }
    [ "$s0" = "$(snapshot)" ] && ! grep -q '^lock acquire ' "$CASE_DIR/rec.log" \
      || { LEG_MSG="'$v': .supervisor/ written or the run lock acquired"; return 1; }
  done
  return 0
}
# leg_watch_note <driver> — per-item-loop.md §6 step 1: a LIVE `<run_id>.merge-watch` watcher of the in-flight
# OPEN PR is noted with ONE `merge-watch noted:` line at the open-PR park (a second --start pick adds none);
# once the watcher is dead nothing is noted. The fake watcher is a real process whose argv carries
# automate-merge-watch.sh and the PR url (the watcher's own `ps -ww` liveness test)
leg_watch_note() {
  local drv="$1" pr=https://github.com/vikashruhilgit/loomwright/pull/555 wp i c rc=0
  new_scratch "$FIX/resume-glob-finalize" || { LEG_MSG="scratch"; return 1; }
  printf '0\tpr view %s --json state,mergedAt\t{"state":"OPEN","mergedAt":null}\n0\tpr list --state open *\t[]\n0\tpr list *\t[]\n0\tauth status*\t\n' "$pr" >> "$CASE_GH"
  mkdir -p "$CASE_DIR/w"; printf 'while :; do sleep 1; done\n' > "$CASE_DIR/w/automate-merge-watch.sh"
  bash "$CASE_DIR/w/automate-merge-watch.sh" "$CASE_RF" item "$pr" </dev/null >/dev/null 2>&1 &
  wp=$!
  i=0; while [ "$i" -lt 50 ]; do case "$(ps -ww -p "$wp" -o command= 2>/dev/null)" in *automate-merge-watch.sh*) break ;; esac; sleep 0.1; i=$((i + 1)); done
  printf 'pid\t%s\npr_url\t%s\nstarted\t2026-10-17T09:00:00Z\n' "$wp" "$pr" > "$CASE_ROOT/.supervisor/automate/$P_RUN.merge-watch"
  ns_call "$drv" --start pick --session-id "$P_SID"
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "park" and .step == "reconcile"' >/dev/null 2>&1 || rc=1
  ns_call "$drv" --start pick --session-id "$P_SID"
  c="$(grep -cE "^- [0-9TZ:-]+ merge-watch noted: live pid=$wp watching $pr — no second watcher armed\$" "$CASE_RF")"
  kill "$wp" 2>/dev/null; wait "$wp" 2>/dev/null
  [ "$rc" = 0 ] && [ "$c" = 1 ] || { LEG_MSG="live watcher: park $([ "$rc" = 0 ] && echo ok || echo missing), $c note line(s) after two --start pick (want 1): '${NC_OUT:0:120}' ${NC_ERR:0:120}"; return 1; }
  ns_call "$drv" --start pick --session-id "$P_SID"
  c="$(grep -c ' merge-watch noted: ' "$CASE_RF")"
  [ "$NC_RC" = 0 ] && [ "$c" = 1 ] || { LEG_MSG="dead watcher: exit $NC_RC, $c note line(s) (want still 1)"; return 1; }
  return 0
}
# leg_stops <driver> — the three named refusals of the PICK / resume entry, each exit 2 with its exact
# stderr line, nothing on stdout, .supervisor/ byte-unchanged and no run-lock acquire:
#   run_done             `--start pick` on a `## Status: done` run
#   pick_already_started `--start pick` while this pass's /autonomous spawn is pending (a no-result call then
#                        still re-prints that spawn byte-identically)
#   run_not_incomplete   `--resume <dir> --run <id>` naming no incomplete run
leg_stops() {
  local drv="$1" s0 sp want
  # run_done
  new_scratch "$FIX/resume-glob-finalize" || { LEG_MSG="scratch (run_done)"; return 1; }
  sed 's/^## Status: paused$/## Status: done/' "$CASE_RF" > "$CASE_RF.t" && mv "$CASE_RF.t" "$CASE_RF"
  grep -qx '## Status: done' "$CASE_RF" || { LEG_MSG="run_done: ## Status: done not seeded"; return 1; }
  s0="$(snapshot)"
  ns_call "$drv" --start pick --session-id "$P_SID"
  want='next-step: run_done — ## Status: done; nothing to pick — nothing written'
  [ "$NC_RC" = 2 ] && [ -z "$NC_OUT" ] && grep -qxF -- "$want" <<<"$NC_ERR" && [ "$s0" = "$(snapshot)" ] \
    && ! grep -q '^lock acquire ' "$CASE_DIR/rec.log" \
    || { LEG_MSG="run_done: exit $NC_RC '${NC_OUT:0:120}' ${NC_ERR:0:200}, .supervisor/ $([ "$s0" = "$(snapshot)" ] && echo unchanged || echo CHANGED)"; return 1; }
  # pick_already_started
  new_scratch "$FIX/run-config-suppress-restore" || { LEG_MSG="scratch (pick_already_started)"; return 1; }
  ns_call "$drv" --start run --session-id s-run
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "spawn" and .what == "/autonomous run"' >/dev/null 2>&1 \
    || { LEG_MSG="pick_already_started: --start run ⇒ exit $NC_RC '${NC_OUT:0:120}' ${NC_ERR:0:160}"; return 1; }
  sp="$NC_OUT"; s0="$(snapshot)"; : > "$CASE_DIR/rec.log"
  ns_call "$drv" --start pick --session-id "$P_SID"
  want="next-step: pick_already_started — a pending /autonomous run instruction belongs to $(sed -n 's/^- item: \([^ ]*\) .*/\1/p' "$CASE_RF" | head -n 1)'s pass (a no-result call re-prints it) — nothing written"
  [ "$NC_RC" = 2 ] && [ -z "$NC_OUT" ] && grep -qxF -- "$want" <<<"$NC_ERR" && [ "$s0" = "$(snapshot)" ] \
    && ! grep -q '^lock acquire ' "$CASE_DIR/rec.log" \
    || { LEG_MSG="pick_already_started: exit $NC_RC '${NC_OUT:0:120}' ${NC_ERR:0:240}, .supervisor/ $([ "$s0" = "$(snapshot)" ] && echo unchanged || echo CHANGED)"; return 1; }
  ns_call "$drv"
  [ "$NC_RC" = 0 ] && [ "$NC_OUT" = "$sp" ] && [ "$s0" = "$(snapshot)" ] \
    || { LEG_MSG="pick_already_started: the pending spawn was not re-printed byte-identically after the refusal: exit $NC_RC"; return 1; }
  # run_not_incomplete
  new_scratch "$FIX/resume-glob-finalize" || { LEG_MSG="scratch (run_not_incomplete)"; return 1; }
  s0="$(snapshot)"
  p_call "$drv" --resume "$CASE_ROOT/.supervisor/automate" --run automate-1999-01-01-000000 --session-id "$P_SID"
  want="next-step: run_not_incomplete — --run automate-1999-01-01-000000 names no incomplete run in $CASE_ROOT/.supervisor/automate — nothing written"
  [ "$NC_RC" = 2 ] && [ -z "$NC_OUT" ] && { grep -qxF -- "$want" <<<"$NC_ERR" || grep -qxF -- "${want//"$CASE_ROOT"/$CASE_ROOT_P}" <<<"$NC_ERR"; } \
    && [ "$s0" = "$(snapshot)" ] && ! grep -q '^lock acquire ' "$CASE_DIR/rec.log" \
    || { LEG_MSG="run_not_incomplete: exit $NC_RC '${NC_OUT:0:120}' ${NC_ERR:0:240}, .supervisor/ $([ "$s0" = "$(snapshot)" ] && echo unchanged || echo CHANGED)"; return 1; }
  return 0
}
# leg_meta_push <driver> — branch-mode.md "PICK report": a non-empty `meta-push-failed` answer (the
# `<run_id>.meta-push-failed` marker's first line) is ONE `meta-push-failed: <answer>` ## Progress line plus the
# stderr report, and the PICK proceeds (exit 0, next step `pending`) — a report, never a block; a second pass
# of the step adds no second line; no marker ⇒ no line, still proceeds
leg_meta_push() {
  local drv="$1" mk ans c
  ans='2026-10-17T08:00:00Z conflict — meta-sync push rejected (no_remote_branch)'
  new_scratch "$FIX/pick-current-set-then-picked" || { LEG_MSG="scratch"; return 1; }
  mk="$CASE_ROOT/.supervisor/automate/$CASE_RUN.meta-push-failed"
  printf '%s\nmeta_sync: scrub x: rule a\n' "$ans" > "$mk"
  printf 'NEXT_STEP_FROM=meta-push\nNEXT_STEP_UNTIL=meta-push\n' > "$CASE_DIR/seams.mp"
  cp "$CASE_RF" "$CASE_DIR/before.md"
  p_seamed "$CASE_DIR/seams.mp" "$drv" --session-id "$P_SID"
  c="$(grep -cxE -- "- [0-9TZ:-]+ meta-push-failed: $(printf '%s' "$ans" | sed 's/[][\.*^$()+?{}|]/\\&/g')" "$CASE_RF")"
  [ "$NC_RC" = 0 ] && [ "$c" = 1 ] && grep -qxF -- "next-step: meta-push-failed: $ans (reported — not a block)" <<<"$NC_ERR" \
    && grep -qF -- 'next: pending' <<<"$NC_ERR" && [ "$(jq -r '.next // empty' "$CASE_ROOT/.supervisor/automate/$CASE_RUN.next-step.json" 2>/dev/null)" = pending ] \
    && [ "$(diff "$CASE_DIR/before.md" "$CASE_RF" | grep -c '^>')" = 1 ] \
    || { LEG_MSG="marker: exit $NC_RC, $c report line(s) (want 1), stderr '${NC_ERR:0:240}', next=$(jq -r '.next // empty' "$CASE_ROOT/.supervisor/automate/$CASE_RUN.next-step.json" 2>/dev/null)"; return 1; }
  p_seamed "$CASE_DIR/seams.mp" "$drv" --session-id "$P_SID"
  c="$(grep -c ' meta-push-failed: ' "$CASE_RF")"
  [ "$NC_RC" = 0 ] && [ "$c" = 1 ] || { LEG_MSG="a second meta-push pass: exit $NC_RC, $c report line(s) (want still 1)"; return 1; }
  new_scratch "$FIX/pick-current-set-then-picked" || { LEG_MSG="scratch (no marker)"; return 1; }
  printf 'NEXT_STEP_FROM=meta-push\nNEXT_STEP_UNTIL=meta-push\n' > "$CASE_DIR/seams.mp"
  p_seamed "$CASE_DIR/seams.mp" "$drv" --session-id "$P_SID"
  [ "$NC_RC" = 0 ] && cmp -s "$FIX/pick-current-set-then-picked/input.md" "$CASE_RF" && ! grep -q 'meta-push-failed' <<<"$NC_ERR" \
    && [ "$(jq -r '.next // empty' "$CASE_ROOT/.supervisor/automate/$CASE_RUN.next-step.json" 2>/dev/null)" = pending ] \
    || { LEG_MSG="no marker: exit $NC_RC, run file $(cmp -s "$FIX/pick-current-set-then-picked/input.md" "$CASE_RF" && echo unchanged || echo WRITTEN), stderr '${NC_ERR:0:160}'"; return 1; }
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

echo "-- R. RUN and DRAIN (automate-speed/07)"
LEG_MSG=""
if leg_run_order "$DRIVER"; then ok "R1 (AC5): suppressed before the /autonomous spawn; restored byte-for-byte (backup deleted, original read backup-first) before the owned-drain spawn"
else no "R1 (AC5): $LEG_MSG"; fi
LEG_MSG=""
if leg_drain_once "$DRIVER"; then ok "R2 (AC2): another owned-drain spawn for the pass ⇒ exit 2 drain_already_owned, nothing written (pending, after the report, sidecar gone)"
else no "R2 (AC2): $LEG_MSG"; fi
LEG_MSG=""
if leg_config_malformed "$DRIVER"; then ok "R3 (AC3): malformed config.json ⇒ exit 2 config_malformed before the spawn; config.json byte-unchanged, no backup, no line"
else no "R3 (AC3): $LEG_MSG"; fi
LEG_MSG=""
if leg_superseded "$DRIVER"; then ok "R4 (AC4): superseded_by_merge ⇒ byte-identical, no review-heal sidecar, no ledger line, awaiting_go park; an OPEN PR ⇒ nothing written"
else no "R4 (AC4): $LEG_MSG"; fi
LEG_MSG=""
if leg_bad_run_reports "$DRIVER"; then ok "R5: $(grep -c . <<<"$BAD_RUN") malformed RUN reports ⇒ exit 2, nothing written; a no-PR report ⇒ the pinned no-PR line, done/stopped, lock released"
else no "R5: $LEG_MSG"; fi
LEG_MSG=""
if leg_bad_drain_reports "$DRIVER"; then ok "R6: $(grep -c . <<<"$BAD_DRAIN") malformed DRAIN reports (and a bare drain report) at the owned-drain spawn ⇒ exit 2, nothing written"
else no "R6: $LEG_MSG"; fi
LEG_MSG=""
if leg_run_idem "$DRIVER"; then ok "R7: the /autonomous and owned-drain spawns re-print, write nothing; the RUN report re-sent at the drain spawn / the no-PR done ⇒ re-print; a different one, or after the DRAIN report ⇒ exit 2; --start run at the drain spawn ⇒ exit 2"
else no "R7: $LEG_MSG"; fi
LEG_MSG=""
if leg_rate_hint "$DRIVER"; then ok "R8: unknown + a 429 STOP_FAILURE hint ⇒ rate_limit park with a separate reason_hint line; a row older than picked ⇒ no park"
else no "R8: $LEG_MSG"; fi
LEG_MSG=""
if leg_drain_replay "$DRIVER"; then ok "R9: the first DRAIN report re-sent at its tail's ask ⇒ the ask re-prints; re-sent at the fix-now spawn ⇒ the spawn re-prints, nothing written; the re-drain's own report proceeds"
else no "R9: $LEG_MSG"; fi
LEG_MSG=""
if leg_reserved_notes "$DRIVER"; then ok "R10: $(grep -c . <<<"$RESERVED_NOTES") reserved-prefix notes (progress_notes[] / progress_note) at the gate entry and the owned-drain spawn ⇒ exit 2 reserved_prefix, nothing written; mid-line ⇒ a note; still ONE owned drain"
else no "R10: $LEG_MSG"; fi
LEG_MSG=""
LEG_MSG=""
if leg_reader_prefixes "$DRIVER"; then ok "R12: all $RP_N ^-anchored ## Progress prefixes of the readers (phase-timing / read-token-ledger / /lanes cls / runfile / readiness / park-leaks) are reserved or a named exception; the doc names every reserved prefix"
else no "R12: $LEG_MSG"; fi
LEG_MSG=""
if leg_session_id "$DRIVER"; then ok "R11: --start run without / with a malformed --session-id ⇒ exit 2, nothing written; the loop's log parks rate_limit; no session id / no log at the check ⇒ ONE pinned skipped line"
else no "R11: $LEG_MSG"; fi

echo "-- P. PICK / RECONCILE / resume (automate-speed/08)"
LEG_MSG=""
if leg_open_pr_park "$DRIVER"; then ok "P1 (AC2): an OPEN in-flight PR (awaiting_merge, escalated) / this run's open trail PR ⇒ --start pick parks, releases its lock, no picked line, no new ## Current item"
else no "P1: $LEG_MSG"; fi
LEG_MSG=""
if leg_reconcile_leftover "$DRIVER"; then ok "P2 (AC3): RECONCILE's closeout leftovers ⇒ AUT-LEFTOVER (4 a call, catalog labels, header \"\"); cant_ask / --non-interactive ⇒ closeout_leftover park, one line per leftover, no trail-pr, no PICK"
else no "P2: $LEG_MSG"; fi
LEG_MSG=""
if leg_resume_entry "$DRIVER"; then ok "P3 (AC4): one run, no --run, can't ask ⇒ resume_requires_flag_non_interactive stop, nothing written; AUT-RESUME asked + re-printed; cant_ask / Start new write nothing; continue restores a stranded config backup"
else no "P3: $LEG_MSG"; fi
LEG_MSG=""
if m="$(build_mutant co - '-append:# co-helpers')" && leg_start_closeout_others "$m"; then ok "P4 (AC3): closeout-others at start — a run_lock_held row is recorded, never a leftover; a leftover row ⇒ the closeout_leftover park before the PICK lock"
else no "P4: ${LEG_MSG:-driver copy not built}"; fi
LEG_MSG=""
if leg_pick_order "$DRIVER"; then ok "P5: PICK's pair — current-set BEFORE the picked line (a never-set ## Current: both written, exit 0)"
else no "P5: $LEG_MSG"; fi
LEG_MSG=""
if leg_brief_repair "$DRIVER"; then ok "P6: brief-repair-merged through RECONCILE's closeout — the repairing brief-repair line passed through, the brief moved"
else no "P6: $LEG_MSG"; fi
LEG_MSG=""
if m="$(build_mutant cls - '-append:# cls-helpers')" && cls_helpers "$m" && leg_leftover_retry "$m"; then ok "P7: a crashed / silent closeout-classify on the Clean up now retry stays a leftover (re-ask, then the closeout_leftover park naming it); a silent one at RECONCILE is one leftover — never a PICK"
else no "P7: ${LEG_MSG:-driver copy not built}"; fi
LEG_MSG=""
if leg_coordinator "$DRIVER"; then ok "P8: a --parallel coordinator run (parallel: 2 / single-lane 1; also parallel:2 / a trailing comment / an extra space before parallel:) ⇒ --resume --run, Continue and --start pick print done/stopped coordinator_run, a bare start asks AUT-RESUME / stops resume_requires_flag_non_interactive, nothing written, no run lock"
else no "P8: $LEG_MSG"; fi
LEG_MSG=""
if leg_watch_note "$DRIVER"; then ok "P9: a live merge watcher of the in-flight open PR ⇒ ONE merge-watch noted line at the open-PR park (not repeated); a dead one ⇒ none"
else no "P9: $LEG_MSG"; fi
LEG_MSG=""
if leg_stops "$DRIVER"; then ok "P10: run_done (--start pick on a done run) / pick_already_started (a pending /autonomous spawn) / run_not_incomplete (--resume --run naming no incomplete run) ⇒ exit 2, the exact refusal line, nothing printed, .supervisor/ byte-unchanged, no run lock"
else no "P10: $LEG_MSG"; fi
LEG_MSG=""
if leg_meta_push "$DRIVER"; then ok "P11: a non-empty meta-push-failed answer ⇒ ONE meta-push-failed: ## Progress line + the stderr report, the PICK proceeds (next: pending); no marker ⇒ nothing written"
else no "P11: $LEG_MSG"; fi

echo "-- V7. running system (Validation 3 of automate-speed/07): PICK → RUN → DRAIN → the tail, one item"
V7="$WORK/v7"; mkdir -p "$V7/fx"
V7_PR=https://github.com/example/scratch/pull/9
cat > "$V7/fx/input.md" <<'EOF'
# Automate Run: v7 scratch backlog
## Status: running
## Source
- backlog .supervisor/requirements/v7/_BACKLOG.md
## Run Config
- mode: safe | limit: 5 | trust_unprotected: false
- auto_review_original: absent | config_backup: automate-2026-10-17-000000.config-backup.json
## Queue
- [ ] .supervisor/requirements/v7/01-scratch-item.md
- [ ] .supervisor/requirements/v7/02-next-item.md
## Current
- item: .supervisor/requirements/v7/01-scratch-item.md | status: running | pr: null | branch: null
- pause_reason: null
## Progress
- 2026-10-17T09:00:00Z picked .supervisor/requirements/v7/01-scratch-item.md
EOF
printf 'run: automate-2026-10-17-000000\nscratch: Validation 3 of automate-speed/07\n' > "$V7/fx/source"
mkdir -p "$V7/fx/tree/dot-supervisor/requirements/v7"
printf '# Scratch item\n\n## Status: pending\n\n## Task\nA one-line doc change.\n' > "$V7/fx/tree/dot-supervisor/requirements/v7/01-scratch-item.md"
printf '0\tpr view %s --json headRefOid\t{"headRefOid":"2222222222222222222222222222222222222222"}\n0\tpr view %s --json files,additions,deletions,changedFiles\t{"files":[{"path":"README.md"}],"additions":1,"deletions":0,"changedFiles":1}\n0\tpr view %s --json state\t{"state":"OPEN"}\n' "$V7_PR" "$V7_PR" "$V7_PR" > "$V7/fx/gh.stub"
V7_SUP="$(printf 'SUPERVISOR_RESULT:\n  schema_version: 1\n  task_id: v7\n  status: completed\n  pr_url: %s\n  branch: feature/v7-scratch\n  subtasks_completed: 1\n  subtasks_failed: 0\n  heal_loop_ran: true\n  heal_iterations: 1\n  heal_decision: PASS\n  heal_fixable_issues_fixed: 0\n  heal_remaining_issues: 0\n  summary: "one-line doc change"\n' "$V7_PR")"
V7_RH="$(printf 'REVIEW_HEAL_RESULT:\n  schema_version: 2\n  decision: READY\n  iterations: 1\n  issues_fixed: 0\n  remaining_issues: 0\n  pr_url: "%s"\n  notified: true\n  rounds: 1\n  fix_cycles: 0\n  repeat_check_failure: false\n  unresolved_bot_feedback: false\n  termination_reason: converged\n' "$V7_PR")"
if new_scratch "$V7/fx"; then
  hold="$(NS_REAL_LOCK=1 in_case "$DRIVER" /dev/null bash -c 'LOOMWRIGHT_HOLDER_PID='"$$"' bash "'"$HERE"'/run-lock.sh" acquire --owner "automate:'"$CASE_RUN"'" 2>&1')"; hrc=$?
  o1="$(NS_REAL_LOCK=1 in_case "$DRIVER" /dev/null bash "$DRIVER" "$CASE_RF" --start run --non-interactive --session-id v7-loop 2>"$V7/e1")"; r1=$?
  c1="$([ -f "$CASE_ROOT/.supervisor/config.json" ] && jq -c . "$CASE_ROOT/.supervisor/config.json")"
  o2="$(NS_REAL_LOCK=1 in_case "$DRIVER" /dev/null bash "$DRIVER" "$CASE_RF" \
    --result "$(jq -cn --arg t "$V7_SUP" '{supervisor_result: $t, session_id: "auto-2026-10-17-090001", run_note: "SUPERVISOR_RESULT completed: heal PASS, 1 review"}')" 2>"$V7/e2")"; r2=$?
  c2="$([ -f "$CASE_ROOT/.supervisor/config.json" ] && echo present || echo absent)"
  o3="$(NS_REAL_LOCK=1 in_case "$DRIVER" /dev/null bash "$DRIVER" "$CASE_RF" \
    --result "$(jq -cn --arg t "$V7_RH" '{review_heal_result: $t, ready_sha: "2222222222222222222222222222222222222222", progress_notes: ["drain round 1: 0 validated findings; ci green on 2222222"], drain_note: "converged, 1 round, 0 fix cycles; ci green on 2222222"}')" 2>"$V7/e3")"; r3=$?
  st_after="$(NS_REAL_LOCK=1 in_case "$DRIVER" /dev/null bash "$HERE/run-lock.sh" status 2>&1)"
  echo "V3-07> acquire (PICK's lock, real run-lock.sh): exit $hrc"
  echo "V3-07> call 1 --start run: exit $r1, $(printf '%s' "$o1" | jq -c '{do, step, what, invocation}' 2>/dev/null); config.json at the spawn: $c1"
  echo "V3-07> call 2 RUN report: exit $r2, $(printf '%s' "$o2" | jq -c '{do, step, what, invocation, head_sha}' 2>/dev/null); config.json at the drain spawn: $c2"
  echo "V3-07> call 3 DRAIN report: exit $r3, $(printf '%s' "$o3" | jq -c '{do, step, pause_reason, message}' 2>/dev/null)"
  echo "V3-07> ## Progress, auto_review suppressed .. drain READY:"
  sed -n '/auto_review suppressed/,/ drain READY /p' "$CASE_RF" | sed 's/^/V3-07>   /'
  echo "V3-07> ## Progress after it:"; sed -n '/ drain READY /,$p' "$CASE_RF" | sed '1d; s/^/V3-07>   /'
  echo "V3-07> run-lock.sh status after: $st_after"
  if [ "$hrc$r1$r2$r3" = 0000 ] && [ "$c1" = '{"auto_review":false}' ] && [ "$c2" = absent ] \
     && printf '%s' "$o1" | jq -e '.what == "/autonomous run" and .invocation == "/autonomous --single-iteration --requirement .supervisor/requirements/v7/01-scratch-item.md --non-interactive-fallback"' >/dev/null 2>&1 \
     && printf '%s' "$o2" | jq -e --arg p "$V7_PR" '.what == "owned drain" and .invocation == ("/review-pr " + $p + " --until-mergeable --no-auto-postmortem") and .head_sha == "2222222222222222222222222222222222222222"' >/dev/null 2>&1 \
     && printf '%s' "$o3" | jq -e '.do == "park" and .pause_reason == "awaiting_merge"' >/dev/null 2>&1 \
     && in_order "$CASE_RF" "auto_review suppressed (backup automate-2026-10-17-000000.config-backup.json)" "auto_review restored (config-restore: original absent)" \
          "session_id auto-2026-10-17-090001" "ran /autonomous → PR $V7_PR (SUPERVISOR_RESULT completed" \
          "owned drain started — /review-pr $V7_PR --until-mergeable --no-auto-postmortem @ 2222222222222222222222222222222222222222" \
          "drain round 1: 0 validated findings" "drain READY (converged, 1 round, 0 fix cycles" "validation-gate: none" "parked awaiting_merge $V7_PR" \
     && grep -qE -- '^- owned_drain_started: [0-9]{4}-[0-9TZ:-]+ \| owned_drain_result: READY \| suppressed_default_dispatch: true$' "$CASE_RF" \
     && grep -qF -- "- item: .supervisor/requirements/v7/01-scratch-item.md | status: awaiting_merge | pr: $V7_PR | branch: feature/v7-scratch" "$CASE_RF" \
     && [ -s "$CASE_ROOT/.supervisor/automate/$CASE_RUN.review-heal-result.md" ] && [ -s "$CASE_ROOT/.supervisor/automate/$CASE_RUN.supervisor-result.md" ] \
     && grep -q '"source":"automate_drain"' "$CASE_ROOT/.supervisor/postmortem/results.jsonl" \
     && ! grep -q "automate:$CASE_RUN" <<<"$st_after"; then
    ok "V7: PICK → RUN (suppress, /autonomous spawn, restore) → DRAIN (owned-drain spawn, pinned lines, sidecars, learning line) → awaiting_merge park; the real run lock released"
  else
    no "V7: drive wrong (acquire $hrc, calls $r1/$r2/$r3: $(cat "$V7/e1" "$V7/e2" "$V7/e3" | head -n 4 | tr '\n' ' '))"
  fi
else
  no "V7: scratch repo not built"
fi

echo "-- V8. running system (Validation 3 of automate-speed/08): a run parked awaiting_merge whose PR merged, through the resume entry"
if new_scratch "$FIX/reconcile-closeout-merged"; then
  o8="$(NS_REAL_LOCK=1 in_case "$DRIVER" /dev/null bash "$DRIVER" --resume "$CASE_ROOT/.supervisor/automate" --run "$CASE_RUN" \
    --non-interactive --session-id auto-2026-10-17-080000 2>"$WORK/v8.err")"; r8=$?
  st8="$(NS_REAL_LOCK=1 in_case "$DRIVER" /dev/null bash "$HERE/run-lock.sh" status 2>&1)"
  echo "V3-08> --resume <automate_dir> --run $CASE_RUN --non-interactive (gh stub: PR #555 MERGED): exit $r8, $(printf '%s' "$o8" | jq -c '{do, step, what, invocation}' 2>/dev/null)"
  echo "V3-08> ## Progress, the closeout lines through the next picked line:"
  sed -n '/ closeout https:\/\/github.com\/vikashruhilgit\/loomwright\/pull\/555: /,/ picked /p' "$CASE_RF" | sed 's/^/V3-08>   /'
  echo "V3-08> ## Status / ## Current after it:"; grep -E '^## Status: |^- item: |^- pause_reason: ' "$CASE_RF" | sed 's/^/V3-08>   /'
  echo "V3-08> run-lock.sh status (PICK holds it through RUN): $(printf '%s' "$st8" | head -n 1)"
  if [ "$r8" = 0 ] && printf '%s' "$o8" | jq -e '.do == "spawn" and .what == "/autonomous run" and .invocation == "/autonomous --single-iteration --requirement .supervisor/requirements/parallel-automate/18-backlog-board-and-right-size.md --non-interactive-fallback"' >/dev/null 2>&1 \
     && in_order "$CASE_RF" "closeout https://github.com/vikashruhilgit/loomwright/pull/555: closeout: reconciled" "trail-unstage: unstaged" \
          "picked .supervisor/requirements/parallel-automate/18-backlog-board-and-right-size.md" \
     && [ "$(grep -c '^- trail-gate: clear' "$CASE_RF")" = 2 ] && grep -q ' auto_review suppressed (backup ' < <(tail -n 1 "$CASE_RF") \
     && grep -qx '## Status: running' "$CASE_RF" \
     && grep -qxF -- '- [x] .supervisor/requirements/automate-followups/39a-sweep-and-janitor.md' "$CASE_RF" \
     && grep -qF -- '- item: .supervisor/requirements/parallel-automate/18-backlog-board-and-right-size.md | status: running | pr: null | branch: null' "$CASE_RF" \
     && grep -q "automate:$CASE_RUN" <<<"$st8"; then
    ok "V8: resume → PICK (real run lock) → RECONCILE closeout of the merged PR → trail gate / un-stage → current-set + picked → the /autonomous spawn"
  else
    no "V8: drive wrong (exit $r8: $(head -n 3 "$WORK/v8.err" | tr '\n' ' '))"
  fi
else
  no "V8: scratch repo not built"
fi

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
  # M7a (Validation 2a) — the config restore moved from the RUN-result step to the drain-result step ⇒ R1 red
  # (config.json still suppressed when the owned-drain spawn prints) and run-config-suppress-restore red
  if m="$(build_mutant2 7a 'ns_once once_rr_restore ns_config_restore || return 1   # the RUN-result restore: before the drain spawn' \
       ':   # restore moved to DRAIN' \
       '  ns_once once_dr_start ns_drain_start_line "$kind" "$pr" || return 1' \
       '  ns_once once_rr_restore ns_config_restore || return 1; ns_once once_dr_start ns_drain_start_line "$kind" "$pr" || return 1')"; then
    LEG_MSG=""; if golden_case run-config-suppress-restore "$m"; then m7a_gold=green; else m7a_gold=red; fi
    if leg_run_order "$m"; then no "M7a: the restore-order leg stayed green with the restore at DRAIN (parity $m7a_gold)"
    else ok "M7a: restore moved to drain-result ⇒ R1 red ($LEG_MSG); run-config-suppress-restore parity $m7a_gold"; fi
  else no "M7a: mutant not built"; fi
  # M7b (Validation 2b) — the second-drain refusal removed ⇒ R2 red
  if m="$(build_mutant 7b 'if ns_drain_owned; then' 'if false; then')"; then
    LEG_MSG=""
    if leg_drain_once "$m"; then no "M7b: the second-drain leg stayed green with the refusal removed"
    else ok "M7b: second-drain refusal removed ⇒ R2 red ($LEG_MSG)"; fi
  else no "M7b: mutant not built"; fi
  # M7c — config-suppress's non-zero exit ignored (the /autonomous spawn printed anyway) ⇒ R3 red
  if m="$(build_mutant 7c 'e="$(bash "$H" config-suppress "$CFG_PATH" "$BAK_PATH" 2>&1 >/dev/null)"; rc=$?' 'e="$(bash "$H" config-suppress "$CFG_PATH" "$BAK_PATH" 2>&1 >/dev/null)"; rc=0')"; then
    LEG_MSG=""
    if leg_config_malformed "$m"; then no "M7c: the malformed-config leg stayed green with the abort ignored"
    else ok "M7c: config-suppress exit ignored ⇒ R3 red ($LEG_MSG)"; fi
  else no "M7c: mutant not built"; fi
  # M7d — the review-heal sidecar written on the superseded path ⇒ R4 red
  if m="$(build_mutant 7d '  # NO review-heal sidecar, NO learning-emit, NO GATE / decision step: close the item out as RECONCILE does' \
       '  ns_write_text drain_text "$AD/$RUN_ID.review-heal-result.md"')"; then
    LEG_MSG=""
    if leg_superseded "$m"; then no "M7d: the superseded leg stayed green with a review-heal sidecar written"
    else ok "M7d: sidecar written on the superseded path ⇒ R4 red ($LEG_MSG)"; fi
  else no "M7d: mutant not built"; fi
  # M7e — progress-append's exit swallowed on the drain start line ⇒ drain-pinned-start-line-current-not-set red
  if m="$(build_mutant 7e 'ns_progress "$ts owned drain started$tag — /review-pr $2 --until-mergeable --no-auto-postmortem @ $h"' \
       'ns_progress "$ts owned drain started$tag — /review-pr $2 --until-mergeable --no-auto-postmortem @ $h" || true')"; then
    if golden_case drain-pinned-start-line-current-not-set "$m"; then no "M7e: the current_not_set case stayed green with the exit swallowed"
    else ok "M7e: start-line exit swallowed ⇒ drain-pinned-start-line-current-not-set red (${GC_MSG:0:160})"; fi
  else no "M7e: mutant not built"; fi
  # M7f — the reserved-prefix check of the free-text notes removed ⇒ R10 red
  if m="$(build_mutant 7f 'case "$t" in "$p"*) printf '"'"'%s'"'"' "$p"; return 0 ;; esac' ':')"; then
    LEG_MSG=""
    if leg_reserved_notes "$m"; then no "M7f: the reserved-prefix leg stayed green with the check removed"
    else ok "M7f: reserved-prefix check removed ⇒ R10 red ($LEG_MSG)"; fi
  else no "M7f: mutant not built"; fi
  # M7i — a reader prefix dropped from NS_RESERVED_PREFIXES (`parked`) ⇒ R12 red and R10 red (the forged park note)
  if m="$(build_mutant 7i - '-append:# M7i')" && awk '$0 != "parked"' "$m" > "$m.t" && mv "$m.t" "$m" \
     && [ -s "$m" ] && ! grep -qx parked "$m" && bash -n "$m"; then
    LEG_MSG=""; if leg_reserved_notes "$m"; then m7i_r10=green; else m7i_r10=red; fi
    LEG_MSG=""
    if leg_reader_prefixes "$m"; then no "M7i: the reader-prefix leg stayed green with 'parked' unreserved (R10 $m7i_r10)"
    elif [ "$m7i_r10" = red ]; then ok "M7i: 'parked' unreserved ⇒ R12 red ($LEG_MSG) and R10 red"
    else no "M7i: 'parked' unreserved ⇒ R12 red but R10 stayed green"; fi
  else no "M7i: mutant not built"; fi
  # M7j — the case fold dropped (a reader lower-cases before it matches: `Finalize:` / `PARKED`) ⇒ R10 red
  if m="$(build_mutant 7j 'ns_lc() { printf '"'"'%s'"'"' "$1" | tr '"'"'[:upper:]'"'"' '"'"'[:lower:]'"'"'; }' 'ns_lc() { printf '"'"'%s'"'"' "$1"; }')"; then
    LEG_MSG=""
    if leg_reserved_notes "$m"; then no "M7j: the reserved-prefix leg stayed green with the case fold dropped"
    else ok "M7j: case fold dropped ⇒ R10 red ($LEG_MSG)"; fi
  else no "M7j: mutant not built"; fi
  # M7k — the RUN report replay dropped (a byte-identical re-send is refused again) ⇒ R7 red
  if m="$(build_mutant 7k 'elif ns_run_replay "$RESULT"; then' 'elif false; then')"; then
    LEG_MSG=""
    if leg_run_idem "$m"; then no "M7k: the RUN-idempotency leg stayed green with the RUN replay dropped"
    else ok "M7k: RUN replay dropped ⇒ R7 red ($LEG_MSG)"; fi
  else no "M7k: mutant not built"; fi
  # M7l — the DRAIN replay at an open ask dropped (the report read as the ask's answer) ⇒ R9 red
  if m="$(build_mutant 7l 'elif [ "$pending_do" = ask ] && ns_is_drain_report "$RESULT" && [ "$(ns_report_hash "$RESULT")" = "$(st drain_report_hash)" ]; then' 'elif false; then')"; then
    LEG_MSG=""
    if leg_drain_replay "$m"; then no "M7l: the drain-replay leg stayed green with the ask replay dropped"
    else ok "M7l: DRAIN replay at the ask dropped ⇒ R9 red ($LEG_MSG)"; fi
  else no "M7l: mutant not built"; fi
  # M7g — both --start run session-id refusals removed (RUN starts with no id) ⇒ R11 red
  if m="$(build_mutant2 7g '[ -n "$SID" ] || { ns_err "session_id_missing' 'true || { ns_err "session_id_missing' \
       'ns_sid_ok "$SID" || { ns_err "session_id_malformed' 'true || { ns_err "session_id_malformed')"; then
    LEG_MSG=""
    if leg_session_id "$m"; then no "M7g: the session-id leg stayed green with the refusal removed"
    else ok "M7g: session-id refusal removed ⇒ R11 red ($LEG_MSG)"; fi
  else no "M7g: mutant not built"; fi
  # M7h — the rate-limit check's pinned skipped line removed (a skipped check reads clean again) ⇒ R11 red
  if m="$(build_mutant 7h 'if [ -n "$skip" ]; then ns_once once_rl_skip' 'if false; then ns_once once_rl_skip')"; then
    LEG_MSG=""
    if leg_session_id "$m"; then no "M7h: the session-id leg stayed green with the skipped line removed"
    else ok "M7h: pinned skipped line removed ⇒ R11 red ($LEG_MSG)"; fi
  else no "M7h: mutant not built"; fi
  # MO — ns_park reordered: the merge watcher armed only AFTER the post-park decide step (the run file is
  # byte-identical, so only the order leg can see it) ⇒ B8 red
  if m="$(build_mutant2 O '*) ns_watch; ns_notify awaiting_merge' '*) ns_notify awaiting_merge' \
       'if [ "$(st order)" = park-first ]; then NEXT=decide; return 0; fi' 'if [ "$(st order)" = park-first ]; then ns_decide; ns_watch; return 0; fi')"; then
    rec_helpers "$m"; LEG_MSG=""
    if golden_case park-first-ready-park "$m"; then mo_gold=green; else mo_gold=red; fi
    if leg_order "$m"; then no "MO: the order leg stayed green with the watcher armed after park-ask-gate"
    else ok "MO: watcher armed after the decide step ⇒ order leg red (golden run file $mo_gold: $LEG_MSG)"; fi
  else no "MO: mutant not built"; fi
  # M8a (Validation 2 of automate-speed/08) — the open-PR park skipped: PICK falls through to current-set + picked ⇒ P1 red
  if m="$(build_mutant 8a '  ns_open_pr_park   # §8: an open PR blocks PICK' '  ns_after_reconcile; return 0   # M8a')"; then
    LEG_MSG=""
    if leg_open_pr_park "$m"; then no "M8a: the open-PR leg stayed green with the open-PR park skipped"
    else ok "M8a: open-PR park skipped (current-set + picked reached) ⇒ P1 red ($LEG_MSG)"; fi
  else no "M8a: mutant not built"; fi
  # M8b — the trail-gate park skipped (an open trail PR no longer parks) ⇒ P1 red
  if m="$(build_mutant 8b 'ns_run_park trail-gate trail_pr_open "" 1' 'NEXT=trail-unstage; return 0; ns_run_park trail-gate trail_pr_open "" 1')"; then
    LEG_MSG=""
    if leg_open_pr_park "$m"; then no "M8b: the open-PR leg stayed green with the trail-gate park skipped"
    else ok "M8b: trail-gate park skipped ⇒ P1 red ($LEG_MSG)"; fi
  else no "M8b: mutant not built"; fi
  # M8c — any closeout-classify answer read as complete ⇒ P2 red
  if m="$(build_mutant 8c 'ns_classify_complete() { [ "$1" = complete ]; }' 'ns_classify_complete() { return 0; }')"; then
    LEG_MSG=""
    if leg_reconcile_leftover "$m"; then no "M8c: the leftover leg stayed green with every answer read as complete"
    else ok "M8c: every closeout-classify answer read as complete ⇒ P2 red ($LEG_MSG)"; fi
  else no "M8c: mutant not built"; fi
  # M8d — the can't-ask resume auto-picks Continue ⇒ P3 red
  if m="$(build_mutant 8d '  ns_resume_stop   # one run, no --run, can not ask: fail closed, never auto-continued' '  NEXT=rebuild; return 0   # M8d')"; then
    LEG_MSG=""
    if leg_resume_entry "$m"; then no "M8d: the resume leg stayed green with Continue auto-picked"
    else ok "M8d: Continue auto-picked when the run cannot ask ⇒ P3 red ($LEG_MSG)"; fi
  else no "M8d: mutant not built"; fi
  # M8e — the picked line written BEFORE current-set (exit 3 current_not_set must surface) ⇒ P5 red
  if m="$(build_mutant 8e 'ns_once once_pk_current ns_call_writer current-set' 'ns_once once_pk_line ns_progress "$(ns_ts) picked $it" || return 1; ns_once once_pk_current ns_call_writer current-set')"; then
    LEG_MSG=""
    if leg_pick_order "$m"; then no "M8e: the PICK-order leg stayed green with the writes swapped"
    else ok "M8e: picked before current-set ⇒ P5 red ($LEG_MSG)"; fi
  else no "M8e: mutant not built"; fi
  # M8f — the Clean up now retry's classify guard dropped (a crashed classify reads as cleaned) ⇒ P7 red
  if m="$(build_mutant 8f 'cls="$(ns_classify_or_leftover "$crc" "$cls" "$r" "$it" "$p")"' ':')"; then
    cls_helpers "$m"; LEG_MSG=""
    if leg_leftover_retry "$m"; then no "M8f: the leftover-retry leg stayed green with the classify guard dropped"
    else ok "M8f: retry classify guard dropped ⇒ P7 red ($LEG_MSG)"; fi
  else no "M8f: mutant not built"; fi
  # M8g — the coordinator-run detection dropped (a --parallel run is picked in the primary) ⇒ P8 red
  if m="$(build_mutant 8g 'ns_parallel() { ns_section' 'ns_parallel() { return 0; ns_section')"; then
    LEG_MSG=""
    if leg_coordinator "$m"; then no "M8g: the coordinator leg stayed green with the parallel line ignored"
    else ok "M8g: coordinator detection dropped ⇒ P8 red ($LEG_MSG)"; fi
  else no "M8g: mutant not built"; fi
  # M8h — the live merge-watcher note dropped at the open-PR park ⇒ P9 red
  if m="$(build_mutant 8h '  ns_watch_note || return 1' '  :')"; then
    LEG_MSG=""
    if leg_watch_note "$m"; then no "M8h: the watch-note leg stayed green with the note dropped"
    else ok "M8h: merge-watch note dropped ⇒ P9 red ($LEG_MSG)"; fi
  else no "M8h: mutant not built"; fi
  # M8i — the run_done refusal dropped (a done run is picked: the PICK lock is acquired) ⇒ P10 red
  if m="$(build_mutant 8i '[ "$(ns_run_status)" != done ] || { ns_err "run_done' 'true || { ns_err "run_done')"; then
    LEG_MSG=""
    if leg_stops "$m"; then no "M8i: the stop leg stayed green with the run_done refusal dropped"
    else ok "M8i: run_done refusal dropped ⇒ P10 red ($LEG_MSG)"; fi
  else no "M8i: mutant not built"; fi
  # M8j — the meta-push-failed report's ## Progress line dropped (only the stderr report left) ⇒ P11 red
  if m="$(build_mutant 8j 'ns_once once_pk_meta ns_progress "$(ns_ts) meta-push-failed: $l" || return 1' ':')"; then
    LEG_MSG=""
    if leg_meta_push "$m"; then no "M8j: the meta-push leg stayed green with the report line dropped"
    else ok "M8j: meta-push-failed report line dropped ⇒ P11 red ($LEG_MSG)"; fi
  else no "M8j: mutant not built"; fi
fi

echo "PASS: $pass FAIL: $fail"
[ "$fail" -eq 0 ]
