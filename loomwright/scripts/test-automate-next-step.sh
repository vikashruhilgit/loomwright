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
#       header (its gate code, human-only gates included), options (the catalog labels) and cant_ask.
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
#       B15 (af/39g): the done exit's ONE `<ts> process registry: <summary>` line directly before its sweep
#       line; a silent `proc-registry.sh summary` (a stub beside a driver copy) ⇒ `… — skipped: no output`.
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
#       a call, the catalog labels, header "AUT-LEFTOVER"); cant_ask / --non-interactive ⇒ the closeout_leftover park, one
#       line per leftover, no trail-pr. P3 (AC4): one run, no --run, can't ask ⇒ the
#       resume_requires_flag_non_interactive stop with .supervisor/ byte-unchanged; AUT-RESUME asked and
#       re-printed; its cant_ask / Start new write nothing to the run; continue restores a stranded config
#       backup. P3 also pins the ask's auto_answer (D8): "Continue" for one run, null under `## Run Config`
#       `auto_gates: off`, two runs or a rebuilt ## Current, and a cant_ask on a "Continue" ask still stops. P4 (AC3): closeout-others at start — a `run_lock_held` row is a record, never a leftover; a
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
#       no run (run_not_incomplete) ⇒ exit 2, the exact stderr line, nothing printed, .supervisor/
#       byte-unchanged, no run-lock acquire. P11: a non-empty `meta-push-failed` answer ⇒ ONE `meta-push-failed:`
#       ## Progress line + the stderr report and the PICK proceeds (next: pending) — a report, never a block
#       (branch-mode.md); not repeated on a second pass; no marker ⇒ nothing written. P12 (af/39e): the DEFAULT
#       ns_watch launch (no NEXT_STEP_WATCH_CMD; gh stubbed OPEN via LOOMWRIGHT_GH_BIN) starts the real watcher,
#       which registers ONE merge-watch entry for its own (marker) pid with its cap, run file and stop hint
#       (proc-registry.sh, this suite's own LOOMWRIGHT_PROC_REGISTRY_DIR); an unwritable registry changes neither
#       the driver's exit/output nor the watcher log. Every watcher started is TERMed (marker removed). P13
#       (D8): the AUT-RESUME auto_answer's risk read over ## Current's PR (a real docs-only / agents/ diff in
#       the case repo, gh stubbed OPEN / unreadable / sha-less; no PR ⇒ no risk read).
#   V8  RUNNING SYSTEM (Validation 3 of automate-speed/08): a scratch repo (gh stubbed, the real run-lock.sh),
#       a run parked awaiting_merge whose PR the stub reads MERGED, driven through `--resume`: the closeout
#       lines through the next `picked` line are printed between `V3-08>` markers.
#   F   FRESH PHASE SESSIONS (automate-speed/09) — the driver's default; every other leg runs under
#       --inline-phases, which in_case adds to each driver call (AC2: the pre-09 expectations unchanged),
#       and a fresh leg sets NS_FRESH=1 with a `claude` stub on the case's PATH (phase-check reads its
#       --help). F1 (AC1): PICK (phase-check ok) → three `spawn`s with "session":"fresh" and phase
#       launch-pad, supervisor, drain in that order, each `launch` a runnable phase-launch line (BLOCKED,
#       exit 3, while no --owner-command is known), and ONE `session_id <sid> (<item>) phase=<phase>` line
#       per phase with three distinct ids. F2 (AC3): phase-check unavailable (or a session id phase-launch
#       cannot carry) ⇒ the phase_relay_unavailable park: no picked line, no spawn, the lock released. F3
#       (AC7): LAUNCH_PAD_RESULT discarded / blocked / aborted / *_non_interactive / malformed / rubric
#       dropped / a died phase ⇒ /autonomous PLAN step 4's status_reason on the no-PR line, no RUN; saved
#       (or ONE new brief behind a malformed block) ⇒ the Supervisor phase spawn. F4: an item whose last RUN
#       checkpointed (the no-PR `checkpoint` line) with its brief still in .supervisor/jobs/in-progress/ ⇒ the
#       re-pick / `--start run` spawns `/loomwright:supervisor --continue task: <id>`, never a fresh Launch Pad.
#       F4i: the same under --inline-phases — an inline spawn (the /autonomous forward set: --non-interactive,
#       --cheap, --max-tokens; --notify dropped), the task id written onto the `supervisor_checkpoint` line from
#       the reported SUPERVISOR_RESULT's task_id.
#   D   DOC MIRROR: the schema doc's step list equals the driver's `case` arms, its `do` table the
#       emitter's closed set, and its spawn row the emitters' `what` values; its coordinator_model closed
#       list equals the driver's NS_CM_VALUES and its Common fields name coordinator_model.
#   CM  COORDINATOR MODEL (automate-speed/10): every instruction the legs above printed carries a listed
#       coordinator_model; absent key ⇒ the shipped default (read from the driver's NS_CM_DEFAULT, so the
#       pin follows the A/B), a listed value ⇒ itself, an invalid one ⇒ session + ONE named stderr line
#       (never a refusal); the --resume start_new carries it from the automate dir's checkout. The valve: 2
#       FAILs in the last 20 ⇒ no escalation, 3 ⇒ ONE escalated record then session, an escalated record +
#       25 ok lines ⇒ still session, a malformed / capped ledger ⇒ session, the ledger deleted ⇒ the
#       configured value again; a refusal appends exactly ONE ok:false line and changes nothing else under
#       .supervisor/ (snapshot() excludes only that ledger), usage errors (a bad --root included) append
#       nothing, a dead-pid / aged ledger lock is broken (the 3rd FAIL still escalates) while a live holder's
#       is not, and a replayed report / a no-result re-print / a no-result --start pick append nothing.
#   E   EVAL SUITE (automate-speed/10): loomwright/evals/coordinator-model/lib/selftest.sh — a model-free
#       reference coordinator scores every A/B case PASS and the mutation control FAIL; the graders catch a
#       wrong question, a skipped instruction and a hand-edited run file.
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
#         M9e the re-pick ignoring the checkpoint / M9f the in-progress brief check dropped  ⇒ F4
#         M9g the inline resume re-running /autonomous / M9h the no-PR line's task_id hint dropped /
#             M9i the `supervisor_checkpoint` line ignored        ⇒ F4i
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
#         M8k automate-merge-watch.sh's registration call line deleted ⇒ P12
#         M9a the phase-check answer test flipped (unavailable proceeds) ⇒ F2
#         M9b --inline-phases parsed as off                             ⇒ R1
#         M9c the Supervisor phase spawn marked "session":"inline"      ⇒ F1
#         M9d a discarded LAUNCH_PAD_RESULT taken down the saved branch  ⇒ F3
#         M10a–q the coordinator_model pins (the brief's Pin mutations) ⇒ their CM leg: the invalid-value
#             fallback a pass-through / every configured value ⇒ session / the absent key ⇒ another listed
#             value (setting); the threshold 3 ⇒ 4 / 3 ⇒ 2 (threshold); a malformed ledger ⇒ the configured
#             model (badledger); the escalated record looked for only in the last-20 tail (persist); the
#             replay check dropped / the valve armed on every call (replay); coordinator_model dropped from
#             ns_base (every) / from the resume start_new (resume); a missing ledger ⇒ session (delete); the
#             ledger append dropped from ns_die2 / from a first arm's exit-2 refusal / the bad --root
#             refusal left armed (refusal); the stale-lock break dropped / a live holder read as stale (stalelock)
#
# LAYOUT: this file is the runner (header, shared setup, the leg functions); the sections themselves run
# from test-automate-next-step.d/<part>.sh in three pool groups (TNS_GROUPS below, part-groups-lib.sh):
# group 1 here, groups 2 and 3 from test-automate-next-step.2.sh / .3.sh, so the pool runs them at once.
# `bash test-automate-next-step.sh --all` runs every part in one process, in base order.
# ENV: NS_CASES="<a> <b>" runs only those golden cases (G only: group 1 or --all); NS_SKIP_MUTANTS=1 skips M.
# Bash 3.2 / BSD-userland safe; everything lives under one work dir removed in a trap.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
FIX="$HERE/fixtures/automate-golden"
DRIVER="$HERE/automate-next-step.sh"
H="$HERE/automate-helpers.sh"
TAB="$(printf '\t')"

# ---- pool groups (part-groups-lib.sh) ----------------------------------------------------------------
# One process ran every section in 700–755 s quiet, 78–84 % of run-self-tests.sh's 900 s per-test cap,
# and hit it under load (2026-11-02). The pool now runs the parts as groups, concurrently: group 1 from
# this file, group <g> from test-automate-next-step.<g>.sh (which only execs `--group <g>`). TNS_GROUPS is
# the ONE map; a part in no group, a missing / extra pool entry or an unknown argument fails here, before
# any setup. `bash test-automate-next-step.sh --all` still runs every part in one process.
# usage: test-automate-next-step.sh [--group <g> | --all | --part <part>]
# --part <part> runs ONE part after the shared setup — what a part file run directly does (it re-enters this
# runner for itself), so `bash test-automate-next-step.d/<part>.sh` (a pin-mutation run) is a real test run.
TNS_PARTS="01-golden-idem-gates 02-branches 03-run-drain 04-pick-resume 05-fresh-phases 06-running-system 07-doc-mirror 08-coordinator-model 09-mutants-tail 10-mutants-pick-fresh 11-mutants-cm 12-dismissed-batch 13-merge-parked"
TNS_GROUPS="1=01-golden-idem-gates,02-branches,03-run-drain,06-running-system,07-doc-mirror 2=04-pick-resume,05-fresh-phases,08-coordinator-model,11-mutants-cm,12-dismissed-batch 3=09-mutants-tail,10-mutants-pick-fresh,13-merge-parked"
. "$HERE/part-groups-lib.sh"
if [ "${1:-}" = --part ]; then
  case " $TNS_PARTS " in *" ${2:-} "*) ;; *) echo "  FAIL: --part names no part of TNS_PARTS: '${2:-}'"; exit 1 ;; esac
  [ "$#" = 2 ] || { echo "  FAIL: --part takes exactly one part name"; exit 1; }
  pg_select "$HERE/test-automate-next-step.sh" "$TNS_PARTS" "$TNS_GROUPS" --all || exit 1   # the map is still checked
  PG_SEL=" $2 "; PG_LABEL="part $2"
else
  pg_select "$HERE/test-automate-next-step.sh" "$TNS_PARTS" "$TNS_GROUPS" "$@" || exit 1
fi
set --

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass + 1)); }
no() { echo "FAIL: $1"; fail=$((fail + 1)); }

. "$HERE/wait-lib.sh"

WORK="$(mktemp -d)" || { echo "FAIL: mktemp -d"; exit 1; }
WORK_P="$(cd "$WORK" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT
# af/39e: this suite's own process registry — a standalone run never registers into the real home
export LOOMWRIGHT_PROC_REGISTRY_DIR="$WORK/procs"
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
  # AC2 of automate-speed/09: every pre-09 leg and golden case runs the driver under --inline-phases (the
  # inline-parity form — its expectations unchanged); the fresh-phase legs set NS_FRESH=1 to run the default
  if [ "${NS_FRESH:-}" != 1 ] && [ "$#" -ge 2 ] && [ "$1" = bash ] && [ "$2" = "$drv" ]; then
    set -- bash "$drv" --inline-phases "${@:3}"
  fi
  (
    cd "$CASE_ROOT" || exit 98
    # LOOMWRIGHT_PHASE_DIR: a run started inside a live phase session inherits it, and gate-auto.sh resolves
    # a run file from it when given none — a case never reaches that session's real run file
    unset LOOMWRIGHT_GH_BIN LOOMWRIGHT_HOLDER_PID NEXT_STEP_FROM NEXT_STEP_UNTIL NEXT_STEP_CLOSEOUT_OUT LOOMWRIGHT_PHASE_DIR
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

# every file under .supervisor/ but the coordinator-model ledger — the ONE file an exit-2 refusal may append to
# (automate-speed/10 AC4); leg CM asserts what that ledger gains on each path
snapshot() { ( cd "$CASE_ROOT/.supervisor" && find . -type f ! -path ./automate/coordinator-model.jsonl | env LC_ALL=C sort | while IFS= read -r f; do cksum "$f"; done ); }

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
  # one pending: dismissed-drafts kept the summary draft automatically, only the per-finding draft waits
  grep -qxF -- '- pending_decisions: 1 | fix_now_reentered: false' "$CASE_RF" \
    || { LEG_MSG="decisions: pending_decisions: 1 not recorded"; return 1; }
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
# leg_registry_line <driver> — B15 (af/39g AC4): the done exit's ONE `<ts> process registry: <summary>` line sits
# directly before its `sweep (dry run)` line; with a `proc-registry.sh summary` that prints nothing (a silent
# stub beside a driver copy) it reads the pinned `proc-registry: summary — skipped: no output` form
leg_registry_line() {
  local drv="$1" d="$WORK/reg-silent" e r s
  golden_case termination-queue-resolved "$drv" || { LEG_MSG="termination-queue-resolved: $GC_MSG"; return 1; }
  r="$(grep -nE '^- [0-9TZ:-]+ process registry: proc-registry: summary — 0 entries: ' "$CASE_RF" | cut -d: -f1)"
  s="$(grep -nE '^- [0-9TZ:-]+ sweep \(dry run\): ' "$CASE_RF" | cut -d: -f1)"
  [ "$(grep -c . <<<"$r")" = 1 ] && [ -n "$s" ] && [ "$r" = "$((s - 1))" ] \
    || { LEG_MSG="registry line(s) at '$(tr '\n' ' ' <<<"$r")', sweep line at '$s' (want ONE, directly before)"; return 1; }
  rm -rf "$d"; mkdir -p "$d"
  for e in "$HERE"/*; do
    case "${e##*/}" in automate-next-step.sh|proc-registry.sh) ;; *) ln -s "$e" "$d/${e##*/}" ;; esac
  done
  cp "$drv" "$d/automate-next-step.sh"; printf '#!/usr/bin/env bash\nexit 0\n' > "$d/proc-registry.sh"
  golden_case termination-queue-resolved "$d/automate-next-step.sh"   # differs from expected.md by design
  [ -z "$DRIVE_ERR" ] || { LEG_MSG="silent summary: $DRIVE_ERR"; return 1; }
  r="$(grep -nE '^- [0-9TZ:-]+ process registry: ' "$CASE_RF" | cut -d: -f1)"
  s="$(grep -nE '^- [0-9TZ:-]+ sweep \(dry run\): ' "$CASE_RF" | cut -d: -f1)"
  [ "$(grep -c . <<<"$r")" = 1 ] && [ -n "$s" ] && [ "$r" = "$((s - 1))" ] \
    && grep -qE -- '^- [0-9TZ:-]+ process registry: proc-registry: summary — skipped: no output$' "$CASE_RF" \
    || { LEG_MSG="silent summary: $(grep -E 'process registry' "$CASE_RF" | tr '\n' ' ') (want ONE pinned skipped line directly before the sweep line)"; return 1; }
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
# re-prints the spawn and writes nothing; the genuine re-drain report (a new ready_sha) then proceeds to the
# re-park (no fix-now is left, so nothing is asked)
leg_spawn_replay() {
  local drv="$1" spawn s0 o rc o2
  new_scratch "$FIX/dismissed-findings-decision-step" || { LEG_MSG="scratch"; return 1; }
  printf '%s\n' "call: --result '{\"drain_result\":\"READY\",\"termination_reason\":\"converged\",\"ready_sha\":\"0000000\"}'" \
    "expect: ask" "call: --result '{\"answers\":[\"Fix all listed on this PR\"]}'" "expect: spawn" > "$CASE_DIR/b14.results"
  drive "$FIX/dismissed-findings-decision-step" "$drv" "$CASE_DIR/b14.results"
  [ -z "$DRIVE_ERR" ] || { LEG_MSG="setup: $DRIVE_ERR"; return 1; }
  spawn="$LAST_OUT"; s0="$(snapshot)"; : > "$CASE_DIR/seams.none"
  o="$(in_case "$drv" "$CASE_DIR/seams.none" bash "$drv" "$CASE_RF" \
    --result '{"drain_result":"READY","termination_reason":"converged","ready_sha":"0000000"}' 2>/dev/null)"; rc=$?
  [ "$rc" = 0 ] && [ "$o" = "$spawn" ] && [ "$s0" = "$(snapshot)" ] \
    || { LEG_MSG="replayed first report ⇒ exit $rc '${o:0:100}', .supervisor/ $([ "$s0" = "$(snapshot)" ] && echo unchanged || echo CHANGED)"; return 1; }
  o2="$(in_case "$drv" "$CASE_DIR/seams.none" bash "$drv" "$CASE_RF" \
    --result '{"drain_result":"READY","termination_reason":"converged","ready_sha":"1111111"}' 2>/dev/null)"; rc=$?
  [ "$rc" = 0 ] && printf '%s' "$o2" | jq -e '.do == "park"' >/dev/null 2>&1 \
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
# leg_nested_run_reports <driver> — issue #616: a RUN report whose SUPERVISOR_RESULT carries a nested
# object off its schema shape ⇒ exit 2 naming the key, nothing written — the two real #616 shapes
# (ground_truth without checked; ground_truth with pass_rate and no counts), a bad heal_dismissed item,
# a contract_conformance missing its counts, and a top-level partial that also carries a nested error;
# then the runner's GROUND_TRUTH_NESTED line copied verbatim ⇒ accepted (the pinned no-PR line).
NESTED_RUN='ground_truth|{"supervisor_result":"SUPERVISOR_RESULT:\n  status: failed\n  ground_truth: {status: skipped}","no_pr_why":"y"}
ground_truth|{"supervisor_result":"SUPERVISOR_RESULT:\n  status: failed\n  ground_truth: {checked: true, status: pass, pass_rate: \"2/2\"}","no_pr_why":"y"}
heal_dismissed|{"supervisor_result":"SUPERVISOR_RESULT:\n  status: failed\n  heal_dismissed: [{finding: x}]","no_pr_why":"y"}
contract_conformance|{"supervisor_result":"SUPERVISOR_RESULT:\n  status: failed\n  contract_conformance: {checked: true, status: pass}","no_pr_why":"y"}
ground_truth|{"supervisor_result":"SUPERVISOR_RESULT:\n  pr_url: https://github.com/o/r/pull/1\n  branch: b\n  ground_truth: {checked: true, status: pass, pass_rate: \"2/2\"}"}'
leg_nested_run_reports() {
  local drv="$1" s0 line key r
  new_scratch "$FIX/run-config-suppress-restore" || { LEG_MSG="scratch"; return 1; }
  ns_call "$drv" --start run --session-id s-run; [ "$NC_RC" = 0 ] || { LEG_MSG="--start run ⇒ exit $NC_RC"; return 1; }
  s0="$(snapshot)"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    key="${line%%|*}"; r="${line#*|}"
    ns_call "$drv" --result "$r"
    [ "$NC_RC" = 2 ] && [ -z "$NC_OUT" ] && [ "$s0" = "$(snapshot)" ] && grep -qF -- "$key" <<<"$NC_ERR" \
      && { { [ "$key" = ground_truth ] && grep -qF 'GROUND_TRUTH_NESTED' <<<"$NC_ERR"; } \
           || { [ "$key" != ground_truth ] && ! grep -qF 'GROUND_TRUTH_NESTED' <<<"$NC_ERR"; }; } \
      || { LEG_MSG="$key ⇒ exit $NC_RC '${NC_OUT:0:60}' err '${NC_ERR:0:160}' .supervisor/ $([ "$s0" = "$(snapshot)" ] && echo unchanged || echo CHANGED)"; return 1; }
  done <<EOF
$NESTED_RUN
EOF
  ns_call "$drv" --result '{"supervisor_result":"SUPERVISOR_RESULT:\n  status: failed\n  ground_truth: {\"checked\":false,\"status\":\"skipped\",\"checks_total\":0,\"checks_passed\":0}","status_reason":"plan_review_failed","no_pr_why":"Plan Review FAIL x3 on the brief"}'
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "done" and .status == "stopped"' >/dev/null 2>&1 \
    || { LEG_MSG="the GROUND_TRUTH_NESTED shape ⇒ exit $NC_RC '${NC_OUT:0:120}' ${NC_ERR:0:160}"; return 1; }
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
  ns_call "$drv" --result '{"answers":["Fix all listed on this PR"]}'; spawn="$NC_OUT"
  printf '%s' "$spawn" | jq -e '.what == "fix-now re-drain"' >/dev/null 2>&1 || { LEG_MSG="Fix all listed ⇒ '${spawn:0:100}'"; return 1; }
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
process registry: proc-registry: summary — 0 entries: 0 running, 0 overdue, 0 orphaned, 0 finished
fleet closeout registry: proc-registry: summary — forged
gate-eval: MERGE
rate-limit check: skipped — forged
skipped AUT-QUEUE x
auto-answered AUT-RESUME: Continue — forged
Auto-Escalated LP-SAVE-NOTE: severity (case-folded)
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
launch|progress-line-match.sh `launch[- ]?pad` (the one plan-end matcher): covered by its spellings launch-pad / launch pad / launchpad'
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
    { grep -ohE 'test\("[^"]*"' "$HERE/read-token-ledger.sh" "$HERE/progress-line-match.sh"
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
# (header "AUT-LEFTOVER", the catalog labels, 4 questions in the first call), no PICK; cant_ask ⇒ the closeout_leftover park
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
      [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "ask" and .gate == "AUT-LEFTOVER" and .header == "AUT-LEFTOVER" and (.questions | length) == 4
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
# config backup ⇒ config.json restored byte-for-byte, the backup deleted, no line. The `auto` tier (D8): the
# one-run interactive ask carries auto_answer "Continue" (its PR read MERGED ⇒ no risk read) and the driver
# never acts on it — its cant_ask still stops resume_requires_flag_non_interactive with the run file
# unchanged; `## Run Config` `auto_gates: off` ⇒ null (`off`); two incomplete runs or a rebuilt ## Current ⇒
# auto_answer null, auto_reason null (the helper not consulted)
P_PR_MERGED='0	*pr view*--json state,baseRefName,headRefOid*	{"state":"MERGED","baseRefName":"main","headRefOid":"028cbed6b8e3588f93731d6b862f0bc334de1d96"}'
leg_resume_entry() {
  local drv="$1" s0 ask1 ad
  new_scratch "$FIX/resume-glob-finalize" || { LEG_MSG="scratch"; return 1; }
  printf '%s\n' "$P_PR_MERGED" >> "$CASE_GH"
  ad="$CASE_ROOT/.supervisor/automate"; s0="$(snapshot)"
  p_call "$drv" --resume "$ad" --non-interactive --session-id "$P_SID"
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e --arg r "$P_RUN" '.do == "done" and .step == "resume" and .stop == "resume_requires_flag_non_interactive"
      and (.message | startswith("automate: resume_requires_flag_non_interactive " + $r))' >/dev/null 2>&1 && [ "$s0" = "$(snapshot)" ] \
    || { LEG_MSG="can't ask: exit $NC_RC '${NC_OUT:0:200}' ${NC_ERR:0:120}, .supervisor/ $([ "$s0" = "$(snapshot)" ] && echo unchanged || echo CHANGED)"; return 1; }
  p_call "$drv" --resume "$ad" --session-id "$P_SID"; ask1="$NC_OUT"
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e --arg r "$P_RUN" '.do == "ask" and .gate == "AUT-RESUME" and .header == "AUT-RESUME"
      and .options == ["Continue","Start new","Archive"] and (.run_file | endswith("/" + $r + ".md"))' >/dev/null 2>&1 \
    || { LEG_MSG="interactive: not the AUT-RESUME ask: exit $NC_RC '${NC_OUT:0:200}' ${NC_ERR:0:120}"; return 1; }
  printf '%s' "$NC_OUT" | jq -e '.auto_answer == "Continue"
      and .auto_reason == "one incomplete run, ## Current not rebuilt, PR https://github.com/vikashruhilgit/loomwright/pull/555 MERGED (no risk read)"' >/dev/null 2>&1 \
    || { LEG_MSG="one run, interactive: auto_answer not \"Continue\" with its reason: '${NC_OUT:0:400}'"; return 1; }
  p_call "$drv" --resume "$ad" --session-id "$P_SID"
  [ "$NC_OUT" = "$ask1" ] || { LEG_MSG="a second --resume did not re-print the pending AUT-RESUME ask"; return 1; }
  ns_call "$drv" --result '{"cant_ask":true}'
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.stop == "resume_requires_flag_non_interactive"' >/dev/null 2>&1 \
    || { LEG_MSG="cant_ask: exit $NC_RC '${NC_OUT:0:160}'"; return 1; }
  cmp -s "$FIX/resume-glob-finalize/input.md" "$CASE_RF" \
    || { LEG_MSG="cant_ask on an auto_answer \"Continue\" ask wrote the run file (the driver must never act on auto_answer)"; return 1; }
  p_call "$drv" --resume "$ad" --session-id "$P_SID"; ns_call "$drv" --result '{"answers":["Start new"]}'
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "done" and .choice == "start_new"' >/dev/null 2>&1 \
    || { LEG_MSG="Start new: exit $NC_RC '${NC_OUT:0:160}' ${NC_ERR:0:120}"; return 1; }
  cmp -s "$FIX/resume-glob-finalize/input.md" "$CASE_RF" || { LEG_MSG="the run file was written by an ask / a stop / a choice"; return 1; }
  # the off switch in ## Run Config ⇒ asked exactly as before (auto_answer null, the trigger named)
  new_scratch "$FIX/resume-glob-finalize" || { LEG_MSG="scratch (off)"; return 1; }
  printf '%s\n' "$P_PR_MERGED" >> "$CASE_GH"
  awk '{ print } /^- auto_review_original: / { print "- auto_gates: off" }' "$CASE_RF" > "$CASE_RF.t" && mv "$CASE_RF.t" "$CASE_RF"
  p_call "$drv" --resume "$CASE_ROOT/.supervisor/automate" --session-id "$P_SID"
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "ask" and .gate == "AUT-RESUME" and .auto_answer == null and .auto_reason == "off"' >/dev/null 2>&1 \
    || { LEG_MSG="## Run Config auto_gates: off: not an ask with auto_answer null / auto_reason off: exit $NC_RC '${NC_OUT:0:300}'"; return 1; }
  # two incomplete runs (resume-ambiguous-park), and a rebuilt ## Current (resume-current-rebuild) ⇒ not consulted
  new_scratch "$FIX/resume-ambiguous-park" || { LEG_MSG="scratch (two runs)"; return 1; }
  printf '%s\n' "$P_PR_MERGED" >> "$CASE_GH"
  p_call "$drv" --resume "$CASE_ROOT/.supervisor/automate" --session-id "$P_SID"
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "ask" and .gate == "AUT-RESUME" and .auto_answer == null and .auto_reason == null' >/dev/null 2>&1 \
    || { LEG_MSG="two incomplete runs: not an ask with auto_answer / auto_reason null: exit $NC_RC '${NC_OUT:0:300}'"; return 1; }
  new_scratch "$FIX/resume-current-rebuild" || { LEG_MSG="scratch (rebuilt)"; return 1; }
  p_call "$drv" --resume "$CASE_ROOT/.supervisor/automate" --run automate-2026-09-30-054439 --session-id "$P_SID"
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "ask" and .gate == "AUT-RESUME" and .auto_answer == null and .auto_reason == null' >/dev/null 2>&1 \
    || { LEG_MSG="a rebuilt ## Current: not an ask with auto_answer / auto_reason null: exit $NC_RC '${NC_OUT:0:300}'"; return 1; }
  # continue (--run): RECONCILE restores the crash-stranded backup (resume-config-crash-restore)
  new_scratch "$FIX/resume-config-crash-restore" || { LEG_MSG="scratch (restore)"; return 1; }
  printf 'NEXT_STEP_UNTIL=reconcile\n' > "$CASE_DIR/seams.u"
  NC_OUT="$(in_case "$drv" "$CASE_DIR/seams.u" bash "$drv" --resume "$CASE_ROOT/.supervisor/automate" --run "$P_RUN" --non-interactive --session-id "$P_SID" 2>"$CASE_DIR/nc.err")"; NC_RC=$?
  [ "$NC_RC" = 0 ] && [ -z "$NC_OUT" ] && [ "$(cat "$CASE_ROOT/.supervisor/config.json")" = '{"repo_allowlist":["vikashruhilgit/loomwright"]}' ] \
    && [ ! -e "$CASE_ROOT/.supervisor/automate/$P_RUN.config-backup.json" ] && cmp -s "$FIX/resume-config-crash-restore/input.md" "$CASE_RF" \
    || { LEG_MSG="continue: config not restored / backup left / run file written: exit $NC_RC $(head -c 160 "$CASE_DIR/nc.err")"; return 1; }
  return 0
}
# leg_resume_auto_risk <driver> — the AUT-RESUME auto tier's risk read (D8): ## Current's PR OPEN ⇒ classify-risk.sh
# over origin/<base>...<head> (a docs-only diff ⇒ "Continue" naming the open PR; a diff that adds agents/ ⇒ null,
# high_risk); a PR gh cannot read, or an OPEN one without a head sha ⇒ null, high_risk (fail toward asking); no PR
# ⇒ "Continue" with no risk read. Each sub-case drops the pending ask first (a re-print is never re-decided).
leg_resume_auto_risk() {
  local drv="$1" ad shas low high u="https://github.com/vikashruhilgit/loomwright/pull/555" w
  new_scratch "$FIX/resume-glob-finalize" || { LEG_MSG="scratch"; return 1; }
  ad="$CASE_ROOT/.supervisor/automate"; cp "$CASE_GH" "$CASE_DIR/gh.base"
  shas="$(in_case "$drv" "$R_SEAMS" bash -c 'git commit --allow-empty -qm base && git update-ref refs/remotes/origin/main HEAD \
    && mkdir -p docs agents && printf "x\n" > docs/note.txt && git add docs/note.txt && git commit -qm low && git rev-parse HEAD \
    && printf "y\n" > agents/x.md && git add agents/x.md && git commit -qm high && git rev-parse HEAD' 2>/dev/null)"
  low="$(sed -n 1p <<<"$shas")"; high="$(sed -n 2p <<<"$shas")"
  [[ "$low" =~ ^[0-9a-f]{40}$ ]] && [[ "$high" =~ ^[0-9a-f]{40}$ ]] || { LEG_MSG="case repo commits not made: '$shas'"; return 1; }
  ra_case() { # <gh row or ""> <jq expectation> <label>
    cp "$CASE_DIR/gh.base" "$CASE_GH"; [ -z "$1" ] || printf '%s\n' "$1" >> "$CASE_GH"
    rm -f "$ad/$P_RUN.next-step.json"
    p_call "$drv" --resume "$ad" --session-id "$P_SID"
    [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "ask" and .gate == "AUT-RESUME"' >/dev/null 2>&1 \
      && printf '%s' "$NC_OUT" | jq -e "$2" >/dev/null 2>&1 \
      || { LEG_MSG="$3: exit $NC_RC '${NC_OUT:0:400}' ${NC_ERR:0:120}"; return 1; }
  }
  w="0	*pr view*--json state,baseRefName,headRefOid*"
  ra_case "$w	{\"state\":\"OPEN\",\"baseRefName\":\"main\",\"headRefOid\":\"$low\"}" \
    ".auto_answer == \"Continue\" and .auto_reason == \"one incomplete run, ## Current not rebuilt, open PR $u not high-risk\"" "open PR, docs-only diff" || return 1
  ra_case "$w	{\"state\":\"OPEN\",\"baseRefName\":\"main\",\"headRefOid\":\"$high\"}" '.auto_answer == null and .auto_reason == "high_risk"' "open PR, agents/ diff" || return 1
  ra_case "" '.auto_answer == null and .auto_reason == "high_risk"' "gh cannot read the PR" || return 1
  ra_case "$w	{\"state\":\"OPEN\",\"baseRefName\":\"main\",\"headRefOid\":\"\"}" '.auto_answer == null and .auto_reason == "high_risk"' "open PR without a head sha" || return 1
  sed 's#^\(- item: .*\) | pr: [^|]* | #\1 | pr: null | #' "$CASE_RF" > "$CASE_RF.t" && mv "$CASE_RF.t" "$CASE_RF"
  grep -q '| pr: null |' "$CASE_RF" || { LEG_MSG="could not unset ## Current's pr"; return 1; }
  ra_case "" '.auto_answer == "Continue" and .auto_reason == "one incomplete run, ## Current not rebuilt, no PR (no risk read)"' "no PR" || return 1
  grep -q 'auto-answered\|auto-escalated' "$CASE_RF" && { LEG_MSG="the driver wrote an auto-* record itself"; return 1; }
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
# af/39e AC10/AC11/AC16 — the DEFAULT ns_watch launch (no NEXT_STEP_WATCH_CMD) at the escalated park starts the
# real automate-merge-watch.sh beside <driver>, with gh stubbed (LOOMWRIGHT_GH_BIN) to read the PR OPEN. The
# watcher registers itself: ONE merge-watch entry whose pid is the marker's pid, with this run's resolved cap,
# the run file and a stop hint. Its `started` log line is printed only after that (synchronous) registration
# call, so the registry is read once that line is there — the mutant side costs no timeout. Every watcher this
# leg starts is TERMed before it asserts (its EXIT trap removes the marker).
MW_GH_BODY='#!/usr/bin/env bash
case "$*" in
  "pr view "*" --json state,headRefOid,statusCheckRollup") printf "%s\n" "{\"state\":\"OPEN\",\"headRefOid\":\"247e203aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"statusCheckRollup\":[]}"; exit 0 ;;
esac
exec gh "$@"
'
# mw_launch <driver> <registry dir> — one escalated park through <driver> with the default watcher launch; sets
# MW_PID (the marker pid, '' when no watcher started), MW_LOG (the watcher log), MW_OUT (the driver's normalised
# instruction) and MW_RC; leaves the watcher RUNNING (the caller stops it with mw_stop)
mw_launch() {
  local drv="$1" reg="$2" rs w
  MW_PID=""; MW_OUT=""; MW_RC=""
  new_scratch "$FIX/escalated-park" || { LEG_MSG="scratch"; return 1; }
  printf '%s' "$MW_GH_BODY" > "$CASE_BIN/gh-open"; chmod +x "$CASE_BIN/gh-open"
  rs="$CASE_DIR/mw.results"
  { printf 'env: NEXT_STEP_WATCH_CMD= LOOMWRIGHT_GH_BIN=%s LOOMWRIGHT_PROC_REGISTRY_DIR=%s LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=7777\n' "$CASE_BIN/gh-open" "$reg"
    grep -v '^#' "$FIX/escalated-park/next-step.results"; } > "$rs"
  drive "$FIX/escalated-park" "$drv" "$rs"
  MW_RC="$LAST_RC"; printf '%s' "$LAST_OUT" > "$CASE_DIR/mw.out"; MW_OUT="$(norm "$CASE_DIR/mw.out")"
  MW_LOG="$CASE_ROOT/.supervisor/automate/$CASE_RUN.merge-watch.log"; MW_MARKER="$CASE_ROOT/.supervisor/automate/$CASE_RUN.merge-watch"
  wait_for_file_content "$MW_LOG" "merge-watch: started pid=" 20; w=$?
  # the marker pid is read whatever happened, so the caller's mw_stop never leaks a started watcher
  MW_PID="$(awk -F'\t' '$1 == "pid" { print $2; exit }' "$MW_MARKER" 2>/dev/null)"
  case "$MW_PID" in ''|*[!0-9]*) MW_PID="" ;; esac
  [ -z "$DRIVE_ERR" ] || { LEG_MSG="drive: $DRIVE_ERR"; return 1; }
  [ "$w" = 0 ] || { LEG_MSG="the default launch started no watcher: $(head -c 300 "$MW_LOG" 2>/dev/null)"; return 1; }
  [ -n "$MW_PID" ] || { LEG_MSG="no marker pid"; return 1; }
  return 0
}
mw_stop() { # TERM the leg's watcher; 0 once it is gone and its trap removed the marker
  [ -n "${MW_PID:-}" ] || return 0
  kill -TERM "$MW_PID" 2>/dev/null
  wait_for_pid_gone "$MW_PID" 10 && WAIT_LIB_WHAT="the marker removed by the watcher's trap" wait_for_cmd 5 test ! -e "$MW_MARKER"
}
leg_watch_registry() {
  local drv="$1" reg lrc n="" e="" base_out rf_abs bad
  reg="$WORK/mw-procs.$$.$RANDOM"
  mw_launch "$drv" "$reg"; lrc=$?
  if [ "$lrc" -eq 0 ]; then
    n="$(cat "$reg"/*.json 2>/dev/null | jq -s '[.[] | select(.kind == "merge-watch")] | length' 2>/dev/null)"
    e="$(cat "$reg"/*.json 2>/dev/null | jq -c -s '[.[] | select(.kind == "merge-watch")][0] // {}' 2>/dev/null)"
  fi
  mw_stop || { LEG_MSG="${LEG_MSG:+$LEG_MSG; }the watcher pid=$MW_PID did not stop on TERM / left its marker"; return 1; }
  [ "$lrc" -eq 0 ] || return 1
  rf_abs="$(cd "$(dirname "$CASE_RF")" && pwd -P)/$(basename "$CASE_RF")"
  [ "$n" = 1 ] || { LEG_MSG="$n merge-watch entr(ies) in the registry (want 1) after the watcher started: $(ls "$reg" 2>/dev/null | tr '\n' ' ')"; return 1; }
  bad="$(jq -r --argjson p "$MW_PID" --arg rf "$rf_abs" '[
      (if .pid != $p then "pid \(.pid) is not the marker pid \($p)" else empty end),
      (if .max_lifetime_s != 7777 then "max_lifetime_s \(.max_lifetime_s) is not the watcher cap 7777" else empty end),
      (if .runfile != $rf then "runfile \(.runfile)" else empty end),
      (if ((.stop_hint // "") | contains("kill -TERM \($p)")) | not then "stop_hint \(.stop_hint)" else empty end)
    ] | join("; ")' <<<"$e" 2>/dev/null)" || bad="unreadable entry: $e"
  [ -z "$bad" ] || { LEG_MSG="entry: $bad"; return 1; }
  base_out="$MW_OUT"
  # AC16: a registry that cannot be written (the dir is a regular file) changes neither the launch nor its output
  : > "$WORK/mw-procs-file.$$"
  mw_launch "$drv" "$WORK/mw-procs-file.$$"; lrc=$?
  mw_stop || { LEG_MSG="unwritable registry: the watcher pid=$MW_PID did not stop on TERM"; return 1; }
  [ "$lrc" -eq 0 ] || { LEG_MSG="unwritable registry: $LEG_MSG"; return 1; }
  [ "$MW_RC" = 0 ] && [ "$MW_OUT" = "$base_out" ] \
    || { LEG_MSG="unwritable registry changed the driver call: exit $MW_RC, '${MW_OUT:0:160}' vs '${base_out:0:160}'"; return 1; }
  ! grep -q 'proc-registry' "$MW_LOG" \
    || { LEG_MSG="unwritable registry: a registry line reached the watcher log: $(grep 'proc-registry' "$MW_LOG" | head -1)"; return 1; }
  return 0
}
# mw_mutant <name> — a scripts/ dir whose automate-merge-watch.sh lacks its ONE registration call line (gated:
# the line occurs once, the copy non-empty, differing, bash -n); prints the dir's driver path
mw_mutant() {
  local d="$WORK/mut-mw-$1" e c
  rm -rf "$d"; mkdir -p "$d"
  for e in "$HERE"/*; do [ "$(basename "$e")" = automate-merge-watch.sh ] || ln -s "$e" "$d/$(basename "$e")"; done
  c="$(grep -c 'proc-registry.sh" register --pid' "$HERE/automate-merge-watch.sh")"
  [ "$c" = 1 ] || { echo "registration line occurs $c time(s)" >&2; return 1; }
  grep -v 'proc-registry.sh" register --pid' "$HERE/automate-merge-watch.sh" > "$d/automate-merge-watch.sh"
  [ -s "$d/automate-merge-watch.sh" ] && ! cmp -s "$HERE/automate-merge-watch.sh" "$d/automate-merge-watch.sh" \
    && bash -n "$d/automate-merge-watch.sh" 2>/dev/null || { echo "mutant gates failed" >&2; return 1; }
  echo "$d/automate-next-step.sh"
}
# leg_stops <driver> — the three named refusals of the PICK / resume entry, each exit 2 with its exact
# stderr line, nothing on stdout, .supervisor/ byte-unchanged and no run-lock acquire:
#   run_done             `--start pick` on a `## Status: done` run
#   pick_already_started `--start pick` while this pass's /autonomous spawn is pending (a no-result call then
#                        still re-prints that spawn byte-identically)
#   run_not_incomplete   `--resume <dir> --run <id>` naming no run
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
  want="next-step: run_not_incomplete — --run automate-1999-01-01-000000 names no run in $CASE_ROOT/.supervisor/automate — nothing written past the start steps"
  [ "$NC_RC" = 2 ] && [ -z "$NC_OUT" ] && { grep -qxF -- "$want" <<<"$NC_ERR" || grep -qxF -- "${want//"$CASE_ROOT"/$CASE_ROOT_P}" <<<"$NC_ERR"; } \
    && [ "$s0" = "$(snapshot)" ] && ! grep -q '^lock acquire ' "$CASE_DIR/rec.log" \
    || { LEG_MSG="run_not_incomplete: exit $NC_RC '${NC_OUT:0:120}' ${NC_ERR:0:240}, .supervisor/ $([ "$s0" = "$(snapshot)" ] && echo unchanged || echo CHANGED)"; return 1; }
  return 0
}
# leg_resume_done <driver> — `--resume --run <id>` on a run that reads done is the `done` answer, never the
# run_not_incomplete refusal: (a) a run --finalize stamps done in this very call (the refusal used to say
# "nothing written" right after that write) ⇒ exit 0, stderr silent, no PICK, no lock, no sidecar; (b) a run
# already done ⇒ the same answer, .supervisor/ byte-unchanged; (c) a result sidecar named as the id is not a run,
# even with a done status line ⇒ the refusal.
leg_resume_done() {
  local drv="$1" s0 id sc ad
  new_scratch "$FIX/resume-glob-finalize" || { LEG_MSG="scratch (a)"; return 1; }
  id="$CASE_RUN"; ad="$CASE_ROOT/.supervisor/automate"
  sed -e 's/^- \[ \] /- [x] /' -e 's/^\(- item: .*\) status: [a-z_]* |/\1 status: done |/' \
      -e 's/^- pause_reason: .*/- pause_reason: awaiting_go/' "$CASE_RF" > "$CASE_RF.t" && mv "$CASE_RF.t" "$CASE_RF"
  p_call "$drv" --resume "$ad" --run "$id" --session-id "$P_SID"
  [ "$NC_RC" = 0 ] && ! grep -q 'run_not_incomplete' <<<"$NC_ERR" \
    && printf '%s' "$NC_OUT" | jq -e --arg id "$id" '.do == "done" and .step == "resume" and .status == "done" and .remaining == 0
         and .run_id == $id and (.run_file | endswith("/" + $id + ".md")) and (.closeout_others | type == "array") and (has("choice") | not)' >/dev/null 2>&1 \
    || { LEG_MSG="(a) finalized here: exit $NC_RC '${NC_OUT:0:200}' ${NC_ERR:0:240}"; return 1; }
  grep -qx '## Status: done' "$CASE_RF" && grep -q ' auto-finalized: ' "$CASE_RF" && ! grep -q '^lock acquire ' "$CASE_DIR/rec.log" \
    && [ "$(grep -c ' picked ' "$CASE_RF")" = "$(grep -c ' picked ' "$FIX/resume-glob-finalize/input.md")" ] && [ ! -e "$ad/$id.next-step.json" ] \
    || { LEG_MSG="(a) finalized here: run file or lock state wrong: $(sed -n 2p "$CASE_RF")"; return 1; }
  # (b) the second call finds it already done: same answer, no write
  s0="$(snapshot)"
  p_call "$drv" --resume "$ad" --run "$id" --session-id "$P_SID"
  [ "$NC_RC" = 0 ] && [ "$s0" = "$(snapshot)" ] && printf '%s' "$NC_OUT" | jq -e '.do == "done" and .status == "done"' >/dev/null 2>&1 \
    || { LEG_MSG="(b) already done: exit $NC_RC '${NC_OUT:0:160}' .supervisor/ $([ "$s0" = "$(snapshot)" ] && echo unchanged || echo CHANGED)"; return 1; }
  # (c) a sidecar carrying a done status line is not a run
  sc="$id.supervisor-result"
  printf '## Status: done\n' >> "$ad/$sc.md"
  p_call "$drv" --resume "$ad" --run "$sc" --session-id "$P_SID"
  [ "$NC_RC" = 2 ] && [ -z "$NC_OUT" ] && grep -q "^next-step: run_not_incomplete — --run $sc names no run " <<<"$NC_ERR" \
    || { LEG_MSG="(c) sidecar id: exit $NC_RC '${NC_OUT:0:160}' ${NC_ERR:0:200}"; return 1; }
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
# leg_pick_summary_autokeep <driver> — the summary auto-keep's resume half (AC6) and its fallback (AC8a). A run
# started before dismissed-drafts kept summaries itself (pick-pending-decisions-ask: an undecided summary + an
# undecided per-finding draft on disk): the PICK `pending` step records the summary follow-up with NO question —
# its ledger row and ONE `kept automatically` Progress line — interactive (the per-finding draft is followed up
# automatically too, so nothing is asked) and under --non-interactive (no ask at all); a replayed step writes no
# second line. With the ledger read-only the auto-keep is refused: the summary stays undecided and the AUT-SUMMARY
# ask (Keep summary / Drop summary) is the fallback, at PICK and at the decision step.
leg_pick_summary_autokeep() {
  local drv="$1" sp led g
  ak_case() { # <case> — a fresh scratch; sp = its summary draft, led = its ledger
    new_scratch "$FIX/$1" || return 1
    sp="$CASE_ROOT/.supervisor/requirements/proposed/$CASE_RUN--39a-sweep-and-janitor-1c7166--dismissed-summary.md"
    led="$CASE_ROOT/.supervisor/automate/$CASE_RUN.dismissed-decisions"
    printf 'NEXT_STEP_FROM=pending\nNEXT_STEP_UNTIL=pending\n' > "$CASE_DIR/seams.ak"
    printf 'NEXT_STEP_UNTIL=pending\n' > "$CASE_DIR/seams.ak2"
  }
  ak_kept() { grep -cE "^- [0-9TZ:-]+ dismissed: follow-up ${sp##*/} — kept automatically \(summary below the tracking threshold, no question\)\$" "$CASE_RF"; }
  ak_gate() { printf '%s' "$NC_OUT" | jq -r 'select(.do == "ask") | .gate' 2>/dev/null; }
  ak_led() { awk -F'\t' -v n="${sp##*/}" '$1 == n { d = $2 } END { print d }' "$led" 2>/dev/null; }
  # (a) interactive resume
  ak_case pick-pending-decisions-ask || { LEG_MSG="scratch (a)"; return 1; }
  p_seamed "$CASE_DIR/seams.ak" "$drv" --session-id "$P_SID"
  [ "$NC_RC" = 0 ] && [ -z "$(ak_gate)" ] && grep -qxF -- '- **Decision:** follow-up' "$sp" && [ "$(ak_kept)" = 1 ] && [ "$(ak_led)" = follow-up ] \
    && [ "$(grep -c ' dismissed: follow-up ' "$CASE_RF")" = 2 ] \
    || { LEG_MSG="interactive: exit $NC_RC, gate '$(ak_gate)', $(ak_kept) kept line(s), ledger '$(ak_led)', $(grep '^- \*\*Decision' "$sp")"; return 1; }
  p_seamed "$CASE_DIR/seams.ak" "$drv" --session-id "$P_SID"
  [ "$NC_RC" = 0 ] && [ -z "$(ak_gate)" ] && [ "$(ak_kept)" = 1 ] && [ "$(grep -c ' dismissed: follow-up ' "$CASE_RF")" = 2 ] \
    || { LEG_MSG="replay: exit $NC_RC, gate '$(ak_gate)', $(ak_kept) kept line(s) (want still 1)"; return 1; }
  # (b) --non-interactive: recorded too, nothing asked
  ak_case pick-pending-decisions-ask || { LEG_MSG="scratch (b)"; return 1; }
  p_seamed "$CASE_DIR/seams.ak" "$drv" --session-id "$P_SID" --non-interactive
  [ "$NC_RC" = 0 ] && [ -z "$(ak_gate)" ] && grep -qxF -- '- **Decision:** follow-up' "$sp" && [ "$(ak_kept)" = 1 ] && [ "$(ak_led)" = follow-up ] \
    && [ "$(jq -r '.next // empty' "$CASE_ROOT/.supervisor/automate/$CASE_RUN.next-step.json" 2>/dev/null)" = reconcile ] \
    || { LEG_MSG="--non-interactive: exit $NC_RC, gate '$(ak_gate)', $(ak_kept) kept line(s), ledger '$(ak_led)'"; return 1; }
  # (c) AC8a at PICK: a read-only ledger ⇒ refused, undecided, AUT-SUMMARY asked after the per-finding ask
  ak_case pick-pending-decisions-ask || { LEG_MSG="scratch (c)"; return 1; }
  : > "$led"; chmod 444 "$led"
  p_seamed "$CASE_DIR/seams.ak" "$drv" --session-id "$P_SID"
  g="$(ak_gate)"
  p_seamed "$CASE_DIR/seams.ak2" "$drv" --result '{"answers":["Follow-up (keep draft)"]}'
  chmod 644 "$led"
  [ "$g" = AUT-PENDING ] && [ "$(ak_gate)" = AUT-SUMMARY ] && grep -qxF -- '- **Decision:** undecided' "$sp" && [ "$(ak_kept)" = 0 ] \
    && [ "$(printf '%s' "$NC_OUT" | jq -c '[.header, .options]')" = '["AUT-SUMMARY",["Keep summary","Drop summary"]]' ] \
    || { LEG_MSG="read-only ledger at PICK: asks '$g' then '$(ak_gate)' (want AUT-PENDING then AUT-SUMMARY), $(ak_kept) kept line(s), $(grep '^- \*\*Decision' "$sp")"; return 1; }
  # (d) AC8a at the decision step: a summary the auto-keep could not record is asked under AUT-SUMMARY
  ak_case park-first-decisions-recorded || { LEG_MSG="scratch (d)"; return 1; }
  awk 'd == 0 && /^- \*\*Decision:\*\* / { print "- **Decision:** undecided"; d = 1; next } { print }' "$sp" > "$sp.t" && mv "$sp.t" "$sp"
  : > "$led"; chmod 444 "$led"
  printf 'NEXT_STEP_FROM=decide\n' > "$CASE_DIR/seams.akd"; : > "$CASE_DIR/seams.akd2"
  p_seamed "$CASE_DIR/seams.akd" "$drv"
  g="$(ak_gate)"
  p_seamed "$CASE_DIR/seams.akd2" "$drv" --result '{"answers":["Fix none (follow-up all)"]}'
  chmod 644 "$led"
  [ "$g" = AUT-DISMISS ] && [ "$(ak_gate)" = AUT-SUMMARY ] && [ "$(printf '%s' "$NC_OUT" | jq -c '.options')" = '["Keep summary","Drop summary"]' ] \
    || { LEG_MSG="decision step fallback: asks '$g' then '$(ak_gate)' (want AUT-DISMISS then AUT-SUMMARY)"; return 1; }
  # (e) the ledger already records the owner's drop of the summary, but the file is still on disk (the rm
  # failed): the PICK auto-keep writes no row and no Progress line, and the draft is still asked (AUT-SUMMARY —
  # the per-finding draft was followed up automatically, so it is the first ask)
  ak_case pick-pending-decisions-ask || { LEG_MSG="scratch (e)"; return 1; }
  printf '%s\tdrop\t2026-01-01T00:00:00Z\n' "${sp##*/}" >> "$led"
  p_seamed "$CASE_DIR/seams.ak" "$drv" --session-id "$P_SID"
  g="$(ak_gate)"
  [ "$g" = AUT-SUMMARY ] && [ "$(ak_kept)" = 0 ] && [ "$(ak_led)" = drop ] \
    && ! grep -qF "summary-member" "$led" && grep -qxF -- '- **Decision:** undecided' "$sp" \
    || { LEG_MSG="ledger drop + file on disk: asks '$g' then '$(ak_gate)', $(ak_kept) kept line(s), ledger '$(ak_led)'"; return 1; }
  # (f) the ledger is appendable but the Decision rewrite fails (proposed/ read-only): repeated PICKs append
  # exactly ONE follow-up row and ONE kept-automatically line
  ak_case pick-pending-decisions-ask || { LEG_MSG="scratch (f)"; return 1; }
  chmod 555 "${sp%/*}"
  p_seamed "$CASE_DIR/seams.ak" "$drv" --session-id "$P_SID" --non-interactive
  p_seamed "$CASE_DIR/seams.ak" "$drv" --session-id "$P_SID" --non-interactive
  p_seamed "$CASE_DIR/seams.ak" "$drv" --session-id "$P_SID" --non-interactive
  chmod 755 "${sp%/*}"
  [ "$NC_RC" = 0 ] && [ "$(awk -F'\t' -v n="${sp##*/}" '$1 == n && $2 == "follow-up"' "$led" | wc -l | tr -d ' ')" = 1 ] && [ "$(ak_kept)" = 1 ] \
    || { LEG_MSG="rewrite failure: exit $NC_RC, $(awk -F'\t' -v n="${sp##*/}" '$1 == n && $2 == "follow-up"' "$led" | wc -l | tr -d ' ') follow-up row(s), $(ak_kept) kept line(s) (want 1 and 1)"; return 1; }
  return 0
}

# --------------------------------------------------------------------------------------
# F. fresh phase sessions (automate-speed/09) — the driver's default: no --inline-phases (NS_FRESH=1)
# --------------------------------------------------------------------------------------
F_ITEM=.supervisor/requirements/parallel-automate/18-backlog-board-and-right-size.md
F_PR=https://github.com/vikashruhilgit/loomwright/pull/601
F_SHA=3333333333333333333333333333333333333333
F_OWNER='/automate --resume automate-2026-10-13-181331'
f_claude() { # <1|0> — a `claude` stub first on the case's PATH: phase-check reads its --help (1 = the
  # pinnable regime advertised, 0 = no --permission-prompt-tool)
  local h='--permission-prompt-tool <tool> --allowedTools <tools> --disallowedTools <tools>'
  [ "$1" = 1 ] || h='--allowedTools <tools> --disallowedTools <tools>'
  printf '#!/usr/bin/env bash\ncase "$*" in *--help*) echo "Usage: claude [options] %s" ;; esac\nexit 0\n' "$h" > "$CASE_BIN/claude"
  chmod +x "$CASE_BIN/claude"
}
f_call() { # <driver> <args…> — one fresh-phase driver call (the real run-lock.sh); sets NC_OUT NC_RC NC_ERR
  local drv="$1"; shift
  NC_OUT="$(NS_FRESH=1 NS_REAL_LOCK=1 in_case "$drv" "$R_SEAMS" bash "$drv" "$CASE_RF" "$@" 2>"$CASE_DIR/nc.err")"; NC_RC=$?
  NC_ERR="$(cat "$CASE_DIR/nc.err")"
}
f_spawn_ok() { # <instruction> <step> <phase> — a fresh-phase spawn
  printf '%s' "$1" | jq -e --arg s "$2" --arg p "$3" '.do == "spawn" and .step == $s and .session == "fresh" and .phase == $p
      and (.launch | type) == "string" and (.prompt | type) == "string" and (.sidecar | endswith("-result.md"))
      and (.then | contains("phase-wait") and contains("phase-answer") and contains("ONE structured ask-user question") and contains("exit 5") and contains("exit 6"))' >/dev/null 2>&1
}
# f_argv_ok <instruction> <phase> <owner command or ""> [<coordinator session, default coord-1>] — `launch` parses
# (as the shell runs it) into exactly bash <automate-helpers.sh> phase-launch <runfile> <phase> [--owner-command
# <cmd>] --coordinator-session <coordinator session> -- <the instruction's prompt>
f_argv_ok() {
  local l p got want
  l="$(printf '%s' "$1" | jq -r .launch)"; p="$(printf '%s' "$1" | jq -r .prompt)"
  got="$(bash -c 'eval "set -- $1"; printf "%s\n" "$@"' _ "$l" | sed '2s|.*/automate-helpers\.sh$|<H>|')"
  want="$(printf '%s\n' bash '<H>' phase-launch "$CASE_RF" "$2"; [ -n "$3" ] && printf '%s\n' --owner-command "$3"; printf '%s\n' --coordinator-session "${4:-coord-1}" -- "$p")"
  [ "$got" = "$want" ]
}
# leg_fresh_walk <driver> — AC1: one Queue item without --inline-phases: PICK (phase-check ok) → the Launch Pad
# phase spawn → its report → the Supervisor phase spawn → the RUN report → the drain phase spawn → the DRAIN
# report; three `spawn`s with "session":"fresh" and phase launch-pad, supervisor, drain in that order, and ONE
# `session_id <sid> (<item>) phase=<phase>` line per phase (three distinct ids: the Launch Pad and drain ones as
# reported, the Supervisor one from .supervisor/state.md). A launch line printed before any --owner-command is
# runnable and refused BLOCKED (exit 3, no process)
leg_fresh_walk() {
  local drv="$1" sp ad b la rc
  new_scratch "$FIX/reconcile-closeout-merged" || { LEG_MSG="scratch"; return 1; }
  f_claude 1
  printf '0\tpr view %s*\t{"headRefOid":"%s","state":"OPEN","files":[{"path":"README.md"}],"additions":1,"deletions":0,"changedFiles":1}\n' "$F_PR" "$F_SHA" >> "$CASE_GH"
  ad="$CASE_ROOT/.supervisor/automate"; b=.supervisor/jobs/pending/2026-10-19-fresh.md
  f_call "$drv" --start pick --non-interactive --session-id coord-1; sp="$NC_OUT"
  [ "$NC_RC" = 0 ] && f_spawn_ok "$sp" plan launch-pad \
    && printf '%s' "$sp" | jq -e --arg i "$F_ITEM" --arg s "$CASE_RUN.launch-pad-result.md" '.what == "launch pad phase" and .sidecar == $s
         and .invocation == ("/loomwright:launch-pad goal: " + $i + " --non-interactive")
         and (.prompt | contains("has an ## Outcomes Rubric section, copy it verbatim into the saved brief") and contains($s))' >/dev/null 2>&1 \
    && f_argv_ok "$sp" launch-pad "" && grep -qE "^- [0-9TZ:-]+ picked $F_ITEM\$" "$CASE_RF" \
    || { LEG_MSG="--start pick ⇒ exit $NC_RC '${sp:0:200}' ${NC_ERR:0:200}"; return 1; }
  la="$(NS_FRESH=1 in_case "$drv" "$R_SEAMS" bash -c "$(printf '%s' "$sp" | jq -r .launch)" 2>&1)"; rc=$?
  [ "$rc" = 3 ] && [ "$la" = "phase-launch: BLOCKED — launch-pad — no owner command — need the owner" ] && [ ! -e "$ad/$CASE_RUN.phase/launch-pad/pid" ] \
    || { LEG_MSG="the launch line without an owner command ⇒ exit $rc '$la'"; return 1; }
  mkdir -p "$CASE_ROOT/.supervisor/jobs/pending" && printf '# Brief\n\n## Task\nfresh\n' > "$CASE_ROOT/$b"
  printf 'LAUNCH_PAD_RESULT:\n  schema_version: 1\n  status: saved\n  saved_brief_path: %s\n  summary: Plan Review PASS 1/3\n' "$b" > "$ad/$CASE_RUN.launch-pad-result.md"
  f_call "$drv" --owner-command "$F_OWNER" --result "$(jq -cn --arg f "$ad/$CASE_RUN.launch-pad-result.md" '{launch_pad_result_file: $f, session_id: "lp-sess-1"}')"; sp="$NC_OUT"
  [ "$NC_RC" = 0 ] && f_spawn_ok "$sp" run supervisor && f_argv_ok "$sp" supervisor "$F_OWNER" \
    && printf '%s' "$sp" | jq -e --arg b "$b" --arg s "$CASE_RUN.supervisor-result.md" '.what == "/autonomous run" and .sidecar == $s
         and .invocation == ("/loomwright:supervisor job: " + $b + " --non-interactive") and .config_backup != null' >/dev/null 2>&1 \
    && [ "$(jq -c . "$CASE_ROOT/.supervisor/config.json" 2>/dev/null)" = '{"auto_review":false}' ] \
    || { LEG_MSG="Launch Pad report ⇒ exit $NC_RC '${sp:0:200}' ${NC_ERR:0:200}"; return 1; }
  printf -- '- session_id: sup-sess-2\n' > "$CASE_ROOT/.supervisor/state.md"
  printf 'SUPERVISOR_RESULT:\n  schema_version: 1\n  task_id: f\n  status: completed\n  pr_url: %s\n  branch: feature/f-fresh\n  subtasks_completed: 1\n  subtasks_failed: 0\n  heal_loop_ran: true\n  heal_iterations: 1\n  heal_decision: PASS\n  heal_fixable_issues_fixed: 0\n  heal_remaining_issues: 0\n  summary: "fresh"\n' "$F_PR" > "$ad/$CASE_RUN.supervisor-result.md"
  f_call "$drv" --result "$(jq -cn --arg f "$ad/$CASE_RUN.supervisor-result.md" '{supervisor_result_file: $f, session_id: "cc-sup-9", run_note: "fresh supervisor phase"}')"; sp="$NC_OUT"
  [ "$NC_RC" = 0 ] && f_spawn_ok "$sp" drain drain && f_argv_ok "$sp" drain "$F_OWNER" \
    && printf '%s' "$sp" | jq -e --arg p "$F_PR" --arg h "$F_SHA" '.what == "owned drain" and .head_sha == $h
         and .invocation == ("/review-pr " + $p + " --until-mergeable --no-auto-postmortem")' >/dev/null 2>&1 \
    && [ ! -e "$CASE_ROOT/.supervisor/config.json" ] \
    || { LEG_MSG="RUN report ⇒ exit $NC_RC '${sp:0:200}' ${NC_ERR:0:200}"; return 1; }
  printf 'REVIEW_HEAL_RESULT:\n  schema_version: 2\n  decision: READY\n  iterations: 1\n  issues_fixed: 0\n  remaining_issues: 0\n  pr_url: "%s"\n  notified: true\n  rounds: 1\n  fix_cycles: 0\n  repeat_check_failure: false\n  unresolved_bot_feedback: false\n  termination_reason: converged\n' "$F_PR" > "$ad/$CASE_RUN.review-heal-result.md"
  f_call "$drv" --result "$(jq -cn --arg f "$ad/$CASE_RUN.review-heal-result.md" --arg h "$F_SHA" '{review_heal_result_file: $f, session_id: "dr-sess-3", ready_sha: $h, drain_note: "converged, 1 round"}')"
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "park" or .do == "ask" or .do == "done"' >/dev/null 2>&1 \
    || { LEG_MSG="DRAIN report ⇒ exit $NC_RC '${NC_OUT:0:200}' ${NC_ERR:0:200}"; return 1; }
  in_order "$CASE_RF" "picked $F_ITEM" "session_id coord-1 ($F_ITEM) phase=driver" "session_id lp-sess-1 ($F_ITEM) phase=launch-pad" "launch-pad saved $b" \
      "auto_review suppressed (backup $CASE_RUN.config-backup.json) — running the supervisor phase (fresh session)" \
      "session_id sup-sess-2 ($F_ITEM) phase=supervisor" "ran /autonomous → PR $F_PR (fresh supervisor phase)" \
      "owned drain started — /review-pr $F_PR --until-mergeable --no-auto-postmortem @ $F_SHA" \
      "session_id dr-sess-3 ($F_ITEM) phase=drain" "drain READY (converged, 1 round)" \
    && [ "$(grep -cE "^- [0-9TZ:-]+ session_id [A-Za-z0-9_-]+ \\($F_ITEM\\) phase=(launch-pad|supervisor|drain)\$" "$CASE_RF")" = 3 ] \
    && ! grep -q 'session_id cc-sup-9' "$CASE_RF" \
    && [ "$(grep -cE "^- [0-9TZ:-]+ session_id [A-Za-z0-9_-]+ \\($F_ITEM\\) phase=driver\$" "$CASE_RF")" = 1 ] \
    || { LEG_MSG="## Progress: $(sed -n '/ picked .*18-backlog/,$p' "$CASE_RF" | tr '\n' '|' | head -c 900)"; return 1; }
  FRESH_RF="$CASE_RF"
  return 0
}
# leg_fresh_unavailable <driver> — AC3: no relay (the `claude` stub advertises no --permission-prompt-tool, so
# phase-check prints `unavailable — …`) and no --inline-phases ⇒ PICK parks phase_relay_unavailable: no picked
# line, no current-set, no spawn, RECONCILE never reached, the run lock released; a session id phase-launch
# cannot carry parks the same way
leg_fresh_unavailable() {
  local drv="$1" sid want
  for sid in coord-1 auto.2026-10-19; do
    new_scratch "$FIX/reconcile-closeout-merged" || { LEG_MSG="scratch"; return 1; }
    if [ "$sid" = coord-1 ]; then f_claude 0; want='phase-check: unavailable — CLI advertises no pinnable permission regime'
    else f_claude 1; want="phase-check: unavailable — the session id $sid is not one phase-launch accepts"; fi
    cp "$CASE_RF" "$CASE_DIR/before.md"
    f_call "$drv" --start pick --non-interactive --session-id "$sid"
    [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "park" and .step == "phase-guard" and .pause_reason == "phase_relay_unavailable" and (.message | contains("--inline-phases"))' >/dev/null 2>&1 \
      && p_no_new_pick "$CASE_DIR/before.md" && grep -qx '## Status: paused' "$CASE_RF" && grep -qxF -- '- pause_reason: phase_relay_unavailable' "$CASE_RF" \
      && grep -qE -- "^- [0-9TZ:-]+ $want" "$CASE_RF" && ! grep -q ' closeout https' < <(diff "$CASE_DIR/before.md" "$CASE_RF") \
      && ! grep -q "automate:$CASE_RUN" <<<"$(NS_REAL_LOCK=1 in_case "$drv" "$R_SEAMS" bash "$HERE/run-lock.sh" status 2>&1)" \
      || { LEG_MSG="$sid: exit $NC_RC '${NC_OUT:0:200}' ${NC_ERR:0:200}; $(diff "$CASE_DIR/before.md" "$CASE_RF" | tr '\n' '|' | head -c 400)"; return 1; }
  done
  return 0
}
# f_plan_case <driver> <LAUNCH_PAD_RESULT text> [<requirement text> [<brief path> <brief text>]] — a fresh
# `--start run` (the pass has no saved brief ⇒ the Launch Pad phase spawn first), then — the brief the phase
# "saved" written after the spawn — the Launch Pad report; NC_* hold the report's answer
f_plan_case() {
  local drv="$1" t="$2" ad item
  new_scratch "$FIX/run-config-suppress-restore" || { NC_RC=98; return 1; }
  f_claude 1; ad="$CASE_ROOT/.supervisor/automate"
  item="$(sed -n 's/^- item: \([^ ]*\) .*/\1/p' "$CASE_RF" | head -n 1)"
  if [ -n "${3:-}" ]; then mkdir -p "$CASE_ROOT/$(dirname "$item")" && printf '%s' "$3" > "$CASE_ROOT/$item"; fi
  f_call "$drv" --start run --session-id coord-1
  [ "$NC_RC" = 0 ] && f_spawn_ok "$NC_OUT" plan launch-pad || { NC_RC=99; return 1; }
  mkdir -p "$CASE_ROOT/.supervisor/jobs/pending"
  if [ -n "${4:-}" ]; then printf '%s' "$5" > "$CASE_ROOT/$4"; fi
  printf '%s' "$t" > "$ad/$CASE_RUN.launch-pad-result.md"
  f_call "$drv" --result "$(jq -cn --arg f "$ad/$CASE_RUN.launch-pad-result.md" '{launch_pad_result_file: $f, session_id: "lp-sess-1"}')"
}
f_nopr_ok() { # <want line after the timestamp> [park] — the plan's no-PR outcome: done/stopped (a failure) or the
  # no_pr_stop park (`park`, a deliberate stop), the pinned line, no RUN
  local row inst='.do == "done" and .status == "stopped"'
  [ "${2:-}" = park ] && inst='.do == "park" and .status == "paused" and .pause_reason == "no_pr_stop"'
  row="$(grep -E -- '^- [0-9TZ:-]+ ran /autonomous — no PR: ' "$CASE_RF" | tail -n 1 | sed -E 's/^- [0-9TZ:-]+ //')"
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e "$inst" >/dev/null 2>&1 \
    && [ "$row" = "$1" ] && ! grep -q 'auto_review suppressed' "$CASE_RF" && [ ! -e "$CASE_ROOT/.supervisor/config.json" ] \
    && grep -q 'session_id lp-sess-1 (.*) phase=launch-pad$' "$CASE_RF" && ! grep -q 'launch-pad saved' "$CASE_RF" \
    || { LEG_MSG="exit $NC_RC '${NC_OUT:0:160}' line '$row' (want '$1') ${NC_ERR:0:160}"; return 1; }
}
# leg_fresh_plan_mapping <driver> — AC7: a Launch Pad report whose LAUNCH_PAD_RESULT is discarded / blocked /
# aborted (a named *_non_interactive summary included) / malformed with no new brief / a saved brief that dropped
# the requirement's rubric, or a phase that died ⇒ the no-PR line with /autonomous PLAN step 4's (step 6's)
# status_reason and the block's own summary, NO Supervisor spawn, no .auto_review suppress, `done` `stopped`. A
# saved brief (and a malformed block with exactly ONE new brief — the ls-diff fallback) ⇒ the Supervisor phase
# spawn on it
leg_fresh_plan_mapping() {
  local drv="$1" st sum want lp='LAUNCH_PAD_RESULT:\n  schema_version: 1\n  status: %s\n  saved_brief_path: %s\n  summary: %s\n'
  local rq=$'# Item\n\n## Outcomes Rubric\n- the thing works\n\n## Task\nx\n'
  while IFS='|' read -r st sum want; do
    [ -n "$st" ] || continue
    # shellcheck disable=SC2059
    f_plan_case "$drv" "$(printf "$lp" "$st" null "$sum")"
    f_nopr_ok "$want" park || { LEG_MSG="$st: $LEG_MSG"; return 1; }
  done <<EOF
discarded|User chose Discard at Phase 6|ran /autonomous — no PR: user_discarded_at_phase_6 (LAUNCH_PAD_RESULT discarded: User chose Discard at Phase 6)
blocked|Plan Review FAIL x3|ran /autonomous — no PR: launch_pad_blocked (LAUNCH_PAD_RESULT blocked: Plan Review FAIL x3)
aborted|owner aborted at NO-GO|ran /autonomous — no PR: user_aborted_at_launch_pad (LAUNCH_PAD_RESULT aborted: owner aborted at NO-GO)
blocked|plan_review_fail_non_interactive — FAIL x3, nobody to ask|ran /autonomous — no PR: launch_pad_cant_ask_non_interactive (LAUNCH_PAD_RESULT blocked: plan_review_fail_non_interactive — FAIL x3, nobody to ask)
EOF
  f_plan_case "$drv" "$(printf 'LAUNCH_PAD_RESULT:\n  status: saved\n')"
  f_nopr_ok "ran /autonomous — no PR: user_discarded_at_phase_6 (malformed LAUNCH_PAD_RESULT (schema_version must be the integer 1; got None); no new brief in .supervisor/jobs/pending/)" \
    || { LEG_MSG="malformed: $LEG_MSG"; return 1; }
  # shellcheck disable=SC2059
  f_plan_case "$drv" "$(printf "$lp" saved .supervisor/jobs/pending/r.md PASS)" "$rq" .supervisor/jobs/pending/r.md $'# Brief\n\n## Task\nx\n'
  f_nopr_ok "ran /autonomous — no PR: rubric_dropped_from_brief (the requirement's ## Outcomes Rubric is missing from the saved brief .supervisor/jobs/pending/r.md)" park \
    || { LEG_MSG="rubric dropped: $LEG_MSG"; return 1; }
  # shellcheck disable=SC2059
  f_plan_case "$drv" "$(printf "$lp" saved .supervisor/jobs/pending/r.md PASS)" "$rq" .supervisor/jobs/pending/r.md "$rq"
  [ "$NC_RC" = 0 ] && f_spawn_ok "$NC_OUT" run supervisor && printf '%s' "$NC_OUT" | jq -e '.invocation == "/loomwright:supervisor job: .supervisor/jobs/pending/r.md"' >/dev/null 2>&1 \
    && grep -qE -- '^- [0-9TZ:-]+ launch-pad saved \.supervisor/jobs/pending/r\.md$' "$CASE_RF" && ! grep -q 'ran /autonomous — no PR' "$CASE_RF" \
    || { LEG_MSG="saved (rubric kept) ⇒ exit $NC_RC '${NC_OUT:0:160}' ${NC_ERR:0:160}"; return 1; }
  f_plan_case "$drv" 'no block at all' "" .supervisor/jobs/pending/new.md $'# Brief\n'
  [ "$NC_RC" = 0 ] && f_spawn_ok "$NC_OUT" run supervisor && printf '%s' "$NC_OUT" | jq -e '.invocation == "/loomwright:supervisor job: .supervisor/jobs/pending/new.md"' >/dev/null 2>&1 \
    || { LEG_MSG="malformed + one new brief (ls-diff fallback) ⇒ exit $NC_RC '${NC_OUT:0:160}' ${NC_ERR:0:160}"; return 1; }
  # a phase that died (no result) reports no_pr_why ⇒ the no-PR line, no RUN
  new_scratch "$FIX/run-config-suppress-restore" || { LEG_MSG="scratch"; return 1; }
  f_claude 1; f_call "$drv" --start run --session-id coord-1
  f_call "$drv" --result '{"status_reason":"phase_died","no_pr_why":"phase-wait: died — no result line since the last launch","session_id":"lp-sess-1"}'
  f_nopr_ok "ran /autonomous — no PR: phase_died (phase-wait: died — no result line since the last launch)" || { LEG_MSG="died: $LEG_MSG"; return 1; }
  # review fix (iteration 2): a phase that died AFTER saving its brief (e.g. it wrote no result sidecar) still gets
  # the ls-diff fallback — one new brief ⇒ the Supervisor phase spawn on it (never stranded in pending/); two ⇒
  # concurrent_session_detected
  local died='{"status_reason":"phase_died","no_pr_why":"phase-wait: died — the session ended without writing its result sidecar","session_id":"lp-sess-1"}'
  new_scratch "$FIX/run-config-suppress-restore" || { LEG_MSG="scratch"; return 1; }
  f_claude 1; f_call "$drv" --start run --session-id coord-1
  mkdir -p "$CASE_ROOT/.supervisor/jobs/pending" && printf '# Brief\n' > "$CASE_ROOT/.supervisor/jobs/pending/died.md"
  f_call "$drv" --result "$died"
  [ "$NC_RC" = 0 ] && f_spawn_ok "$NC_OUT" run supervisor && printf '%s' "$NC_OUT" | jq -e '.invocation == "/loomwright:supervisor job: .supervisor/jobs/pending/died.md"' >/dev/null 2>&1 \
    && grep -qE -- '^- [0-9TZ:-]+ launch-pad saved \.supervisor/jobs/pending/died\.md$' "$CASE_RF" && ! grep -q 'ran /autonomous — no PR' "$CASE_RF" \
    || { LEG_MSG="died after saving its brief ⇒ exit $NC_RC '${NC_OUT:0:160}' ${NC_ERR:0:160}"; return 1; }
  new_scratch "$FIX/run-config-suppress-restore" || { LEG_MSG="scratch"; return 1; }
  f_claude 1; f_call "$drv" --start run --session-id coord-1
  mkdir -p "$CASE_ROOT/.supervisor/jobs/pending" && printf '# Brief\n' > "$CASE_ROOT/.supervisor/jobs/pending/d1.md" && printf '# Brief\n' > "$CASE_ROOT/.supervisor/jobs/pending/d2.md"
  f_call "$drv" --result "$died"
  f_nopr_ok "ran /autonomous — no PR: concurrent_session_detected (phase-wait: died — the session ended without writing its result sidecar; 2 new briefs in .supervisor/jobs/pending/)" \
    || { LEG_MSG="died + two new briefs: $LEG_MSG"; return 1; }
  # iteration 3: PLAN step 6's rubric check also covers the died phase's ls-diff brief — a requirement with a real
  # rubric + ONE new brief that dropped it ⇒ rubric_dropped_from_brief, no Supervisor spawn
  local ri
  new_scratch "$FIX/run-config-suppress-restore" || { LEG_MSG="scratch"; return 1; }
  f_claude 1; ri="$(sed -n 's/^- item: \([^ ]*\) .*/\1/p' "$CASE_RF" | head -n 1)"
  mkdir -p "$CASE_ROOT/$(dirname "$ri")" && printf '%s' "$rq" > "$CASE_ROOT/$ri"
  f_call "$drv" --start run --session-id coord-1
  mkdir -p "$CASE_ROOT/.supervisor/jobs/pending" && printf '# Brief\n\n## Task\nx\n' > "$CASE_ROOT/.supervisor/jobs/pending/died.md"
  f_call "$drv" --result "$died"
  f_nopr_ok "ran /autonomous — no PR: rubric_dropped_from_brief (the requirement's ## Outcomes Rubric is missing from the saved brief .supervisor/jobs/pending/died.md)" park \
    || { LEG_MSG="died + one new brief without the rubric: $LEG_MSG"; return 1; }
  return 0
}
# leg_fresh_state_stale <driver> — review fix: .supervisor/state.md persists between runs (rewritten only at the next
# Supervisor INIT), so the fresh RUN record trusts its session_id only when this pass's phase rewrote it: a STALE
# state.md (mtime before the Supervisor phase spawn) + a phase_died report records the REPORTED id, never the stale
# one; with no reported id no phase=supervisor line at all; a fresh state.md naming the coordinator's own session
# is not the phase's either
leg_fresh_state_stale() {
  local drv="$1" item rep want lp='LAUNCH_PAD_RESULT:\n  schema_version: 1\n  status: saved\n  saved_brief_path: %s\n  summary: PASS\n'
  local rq=$'# Item\n\n## Outcomes Rubric\n- the thing works\n\n## Task\nx\n' c state stamp opr=https://github.com/vikashruhilgit/loomwright/pull/777 left
  local ghrc recorded stub own
  for c in stale-reported stale-none fresh-coord fresh-recorded fresh-prefix fresh-ghfail stat-gnu stat-bsd stat-garbage; do
    # shellcheck disable=SC2059
    f_plan_case "$drv" "$(printf "$lp" .supervisor/jobs/pending/r.md)" "$rq" .supervisor/jobs/pending/r.md "$rq"
    [ "$NC_RC" = 0 ] && f_spawn_ok "$NC_OUT" run supervisor || { LEG_MSG="$c: no Supervisor phase spawn (exit $NC_RC) ${NC_ERR:0:160}"; return 1; }
    item="$(sed -n 's/^- item: \([^ ]*\) .*/\1/p' "$CASE_RF" | head -n 1)"
    ghrc=0; recorded=''; stub=''; own=0
    case "$c" in
      stale-reported) state=old-sup-1; stamp=old; rep='"session_id":"sup-died-2",'; want="session_id sup-died-2 ($item) phase=supervisor" ;;
      stale-none) state=old-sup-1; stamp=old; rep=''; want='' ;;
      fresh-coord) state=coord-1; stamp=now; rep='"session_id":"sup-r-3",'; want="session_id sup-r-3 ($item) phase=supervisor" ;;
      # iteration 3: the run file already records this PR (another item's) ⇒ not this phase's, no annotation
      fresh-recorded) state=coord-1; stamp=now; rep='"session_id":"sup-r-3",'; want="session_id sup-r-3 ($item) phase=supervisor"; recorded="$opr" ;;
      # …but a recorded PR whose URL merely STARTS with this one (…/pull/7777 vs …/pull/777) is a different PR
      fresh-prefix) state=coord-1; stamp=now; rep='"session_id":"sup-r-3",'; want="session_id sup-r-3 ($item) phase=supervisor"; recorded="${opr}7" ;;
      # gh failing (no PR list) ⇒ no annotation, the no-PR line as reported
      fresh-ghfail) state=coord-1; stamp=now; rep='"session_id":"sup-r-3",'; want="session_id sup-r-3 ($item) phase=supervisor"; ghrc=1 ;;
      # the portable mtime read: a GNU coreutils stat (-c works; -f is file-SYSTEM status — exits 0 with
      # non-numeric text) and a BSD stat (-c is an illegal option) both read the fresh mtime ⇒ state.md's id
      # wins; a stat answering garbage to both forms fails CLOSED (stale) ⇒ the reported id, no annotation
      stat-gnu) state=sup-st-5; stamp=now; rep='"session_id":"sup-rep-6",'; want="session_id sup-st-5 ($item) phase=supervisor"; stub=gnu; own=1 ;;
      stat-bsd) state=sup-st-5; stamp=now; rep='"session_id":"sup-rep-6",'; want="session_id sup-st-5 ($item) phase=supervisor"; stub=bsd; own=1 ;;
      stat-garbage) state=sup-st-5; stamp=now; rep='"session_id":"sup-rep-6",'; want="session_id sup-rep-6 ($item) phase=supervisor"; stub=garbage ;;
    esac
    # review fix (iteration 2): the died phase left an OPEN PR on the feature branch state.md records — named on the
    # no-PR line only when state.md is THIS phase's (fresh); a stale state.md's branch is a previous run's
    printf -- '- session_id: %s\n- branch: feature/died-x\n' "$state" > "$CASE_ROOT/.supervisor/state.md"
    if [ "$ghrc" = 0 ]; then printf '0\tpr list --head feature/died-x *\t[{"url":"%s"}]\n' "$opr" >> "$CASE_GH"
    else printf '1\tpr list --head feature/died-x *\t\n' >> "$CASE_GH"; fi
    if [ -n "$recorded" ]; then
      awk -v l="- 2026-10-01T00:00:00Z ran /autonomous → PR $recorded (another item)" '{ print } $0 == "## Progress" { print l }' "$CASE_RF" > "$CASE_RF.t" && mv "$CASE_RF.t" "$CASE_RF"
    fi
    case "$stub" in
      gnu) printf '%s\n' '#!/usr/bin/env bash' \
             'case "$1" in -c) [ "$2" = %Y ] && exec python3 -I -c "import os,sys; print(int(os.stat(sys.argv[1]).st_mtime))" "$3" ;;' \
             '  -f) printf "  File: \"%s\"\n    ID: 0 Namelen: 255 Type: ext2/ext3\n" "$3"; exit 0 ;; esac; exit 1' > "$CASE_BIN/stat" ;;
      bsd) printf '%s\n' '#!/usr/bin/env bash' \
             'case "$1" in -c) echo "stat: illegal option -- c" >&2; exit 1 ;;' \
             '  -f) [ "$2" = %m ] && exec python3 -I -c "import os,sys; print(int(os.stat(sys.argv[1]).st_mtime))" "$3" ;; esac; exit 1' > "$CASE_BIN/stat" ;;
      garbage) printf '%s\n' '#!/usr/bin/env bash' 'echo "1700000000 garbage"; exit 0' > "$CASE_BIN/stat" ;;
    esac
    [ -n "$stub" ] && chmod +x "$CASE_BIN/stat"
    [ "$stamp" = old ] && touch -t 202001010000 "$CASE_ROOT/.supervisor/state.md"
    if [ "$stamp" = old ] || [ "$ghrc" != 0 ] || [ "$recorded" = "$opr" ] || [ "$stub" = garbage ]; then left=0; else left=1; fi
    f_call "$drv" --result "{${rep}\"status_reason\":\"phase_died\",\"no_pr_why\":\"phase-wait: died — no result line since the last launch\"}"
    rm -f "$CASE_BIN/stat"
    [ "$NC_RC" = 0 ] && grep -q 'ran /autonomous — no PR: phase_died' "$CASE_RF" && { [ "$own" = 1 ] || ! grep -qv ' phase=driver$' < <(grep "session_id $state " "$CASE_RF"); } \
      && if [ "$left" = 1 ]; then grep -qF -- "no PR: phase_died (phase-wait: died — no result line since the last launch; the phase left PR $opr open on feature/died-x — not drained" "$CASE_RF"; else ! grep -q 'the phase left PR' "$CASE_RF"; fi \
      && if [ -n "$want" ]; then grep -qE -- "^- [0-9TZ:-]+ $(printf '%s' "$want" | sed 's/[().]/\\&/g')\$" "$CASE_RF"; else ! grep -q 'phase=supervisor' "$CASE_RF"; fi \
      || { LEG_MSG="$c: exit $NC_RC ${NC_ERR:0:160}; ## Progress: $(grep 'session_id\|no PR' "$CASE_RF" | tr '\n' '|' | head -c 400)"; return 1; }
  done
  return 0
}
# leg_fresh_checkpoint <driver> — wave 7 (lane L23): an item whose last RUN checkpointed (the no-PR `checkpoint` line)
# with its task's brief still in .supervisor/jobs/in-progress/ resumes as the Supervisor phase spawn
# `/loomwright:supervisor --continue task: <id>` — no Launch Pad spawn — on the `--start pick` re-pick (the L23 path)
# and on a `--start run` re-entry; with no `--continue task:` on the line the brief saved before it names the task.
# The in-progress brief gone, or a newer `launch-pad saved` after the checkpoint line ⇒ the pre-fix routing (the Launch
# Pad spawn / that newer brief)
leg_fresh_checkpoint() {
  local drv="$1" c tid=2026-10-14-af39b hint want sp
  for c in pick run-brief-name no-inprogress superseded; do
    new_scratch "$FIX/run-config-suppress-restore" || { LEG_MSG="scratch"; return 1; }
    f_claude 1
    hint="; resume with /supervisor --continue task: $tid"; [ "$c" = run-brief-name ] && hint=""
    { printf -- '- 2026-10-14T09:20:00Z launch-pad saved .supervisor/jobs/pending/%s.md\n' "$tid"
      printf -- '- 2026-10-14T09:20:00Z auto_review suppressed (backup %s.config-backup.json) — running the supervisor phase (fresh session)\n' "$CASE_RUN"
      printf -- '- 2026-10-14T11:00:00Z auto_review restored (config-restore: original absent)\n'
      printf -- '- 2026-10-14T11:00:01Z ran /autonomous — no PR: checkpoint (Supervisor checkpointed at Phase 3 EXECUTE (subtask 4 hit its turn limit)%s)\n' "$hint"
      if [ "$c" = superseded ]; then
        printf -- '- 2026-10-14T12:00:00Z picked %s\n' "$(sed -n 's/^- item: \([^ ]*\) .*/\1/p' "$CASE_RF" | head -n 1)"
        printf -- '- 2026-10-14T12:10:00Z launch-pad saved .supervisor/jobs/pending/newer.md\n'
      fi; } >> "$CASE_RF"
    [ "$c" = no-inprogress ] || { mkdir -p "$CASE_ROOT/.supervisor/jobs/in-progress" && printf '# Brief\n' > "$CASE_ROOT/.supervisor/jobs/in-progress/$tid.md"; }
    case "$c" in
      pick|no-inprogress) # PICK's trail-gate reads this run's open trail PR: none
        printf '0\tpr list --state open *\t[]\n0\tpr list *\t[]\n' >> "$CASE_GH"
        f_call "$drv" --start pick --non-interactive --session-id coord-1 ;;
      *) f_call "$drv" --start run --session-id coord-1 ;;
    esac
    sp="$NC_OUT"
    case "$c" in
      pick) want="/loomwright:supervisor --continue task: $tid --non-interactive" ;;
      run-brief-name) want="/loomwright:supervisor --continue task: $tid" ;;
      superseded) want="/loomwright:supervisor job: .supervisor/jobs/pending/newer.md" ;;
      no-inprogress) want="" ;;
    esac
    if [ -n "$want" ]; then
      [ "$NC_RC" = 0 ] && f_spawn_ok "$sp" run supervisor && printf '%s' "$sp" | jq -e --arg i "$want" '.invocation == $i and (.prompt | startswith($i + " — "))' >/dev/null 2>&1 \
        && [ "$(jq -c . "$CASE_ROOT/.supervisor/config.json" 2>/dev/null)" = '{"auto_review":false}' ] \
        || { LEG_MSG="$c ⇒ exit $NC_RC '${sp:0:240}' ${NC_ERR:0:200}"; return 1; }
    else
      [ "$NC_RC" = 0 ] && f_spawn_ok "$sp" plan launch-pad || { LEG_MSG="$c (no in-progress brief) ⇒ not the Launch Pad spawn: exit $NC_RC '${sp:0:240}' ${NC_ERR:0:200}"; return 1; }
    fi
    case "$c" in
      # the re-pick's own `picked` line (the LAST one) follows the checkpoint line, and the --continue suppress line follows it
      pick) local nck npk nct
            nck="$(grep -nF -- "ran /autonomous — no PR: checkpoint (" "$CASE_RF" | tail -n 1 | cut -d: -f1)"
            npk="$(grep -nE -- '^- [0-9TZ:-]+ picked ' "$CASE_RF" | tail -n 1 | cut -d: -f1)"
            nct="$(grep -nxF -- "- $(grep -oE '^- [0-9TZ:-]+ auto_review suppressed .*--continue task: .*' "$CASE_RF" | tail -n 1 | sed 's/^- //')" "$CASE_RF" | cut -d: -f1)"
            [ -n "$nck" ] && [ -n "$npk" ] && [ "$npk" -gt "$nck" ] && [ -n "$nct" ] && [ "$nct" -gt "$npk" ] \
              && grep -qE -- "^- [0-9TZ:-]+ auto_review suppressed \(backup $CASE_RUN\.config-backup\.json\) — running the supervisor phase \(fresh session, --continue task: $tid — the checkpointed run, no fresh Launch Pad\)\$" "$CASE_RF" \
            || { LEG_MSG="pick: ## Progress $(sed -n '/## Progress/,$p' "$CASE_RF" | tr '\n' '|' | head -c 900)"; return 1; } ;;
    esac
  done
  return 0
}
# np_lp <driver> <status> <summary> — a Launch Pad phase on an item whose requirement exists ends with that block
np_lp() {
  # shellcheck disable=SC2059
  f_plan_case "$1" "$(printf 'LAUNCH_PAD_RESULT:\n  schema_version: 1\n  status: %s\n  saved_brief_path: null\n  summary: %s\n' "$2" "$3")" $'# Item\n\n## Task\nx\n'
  printf '0\tpr list --state open *\t[]\n0\tpr list *\t[]\n' >> "$CASE_GH"
}
np_item() { sed -n 's/^- item: \([^ ]*\) .*/\1/p' "$CASE_RF" | head -n 1; }
np_parked() { # the run file reads parked no_pr_stop, the item still running, the run lock released
  grep -qx '## Status: paused' "$CASE_RF" && grep -qx -- '- pause_reason: no_pr_stop' "$CASE_RF" && grep -q '^- item: .* | status: running | pr: null' "$CASE_RF" \
    && [ ! -d "$CASE_ROOT/.supervisor/run.lock" ]
}
# leg_no_pr_stop <driver> — an owner's no-PR stop (Refine offline ⇒ launch_pad_blocked) is a park, and an owner's
# --resume on the unchanged requirement parks again instead of re-running Launch Pad on it: the edit, or a # skipped:
# check-off, is what moves it on. A PICK-time park overwriting pause_reason does not lift that. A gate's stop re-picks;
# a real failure (phase_died) keeps its done/stopped instruction and its run file, so a lane there still reads stalled
leg_no_pr_stop() {
  local drv="$1" before it
  np_lp "$drv" blocked 'Plan Review FAIL x3; owner chose Refine offline'
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "park" and .step == "rate-limit" and .pause_reason == "no_pr_stop" and (.message | contains("launch_pad_blocked"))' >/dev/null 2>&1 \
    && np_parked && grep -qE -- '^- [0-9TZ:-]+ parked no_pr_stop — launch_pad_blocked; requirement cksum [0-9]+-[0-9]+$' "$CASE_RF" \
    || { LEG_MSG="the stop ⇒ exit $NC_RC '${NC_OUT:0:240}' ${NC_ERR:0:200}"; return 1; }
  # what a --continue'd session gets: the same park, nothing written
  cp "$CASE_RF" "$CASE_DIR/before.md"
  f_call "$drv" --session-id coord-1
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "park" and .pause_reason == "no_pr_stop"' >/dev/null 2>&1 && cmp -s "$CASE_DIR/before.md" "$CASE_RF" \
    || { LEG_MSG="bare call ⇒ exit $NC_RC '${NC_OUT:0:200}'"; return 1; }
  f_call "$drv" --start run --session-id coord-1
  [ "$NC_RC" = 2 ] && case "$NC_ERR" in *no_pr_stop*) true ;; *) false ;; esac && cmp -s "$CASE_DIR/before.md" "$CASE_RF" \
    || { LEG_MSG="--start run ⇒ exit $NC_RC ${NC_ERR:0:200}"; return 1; }
  # --resume, requirement unchanged: parked again, no picked line, no Launch Pad spawn
  p_call_fresh "$drv" --resume "$CASE_ROOT/.supervisor/automate" --run "$CASE_RUN" --session-id coord-2
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "park" and .step == "reconcile" and .pause_reason == "no_pr_stop" and (.message | contains("unchanged"))' >/dev/null 2>&1 \
    && np_parked && p_no_new_pick "$CASE_DIR/before.md" \
    || { LEG_MSG="--resume unchanged ⇒ exit $NC_RC '${NC_OUT:0:240}' ${NC_ERR:0:200}"; return 1; }
  # a PICK-time park overwrites pause_reason before RECONCILE: the guard reads ## Progress, so it still holds
  ( cd "$CASE_ROOT" && bash "$H" current-set "$CASE_RF" --pause-reason token_ceiling ) >/dev/null 2>&1
  f_call "$drv" --start pick --session-id coord-3
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "park" and .pause_reason == "no_pr_stop"' >/dev/null 2>&1 && p_no_new_pick "$CASE_DIR/before.md" \
    || { LEG_MSG="after an overwriting park ⇒ exit $NC_RC '${NC_OUT:0:240}' ${NC_ERR:0:200}"; return 1; }
  # the owner refines the requirement: --resume re-picks it and re-plans
  it="$(np_item)"; printf '\nOwner note: narrowed after Plan Review.\n' >> "$CASE_ROOT/$it"
  p_call_fresh "$drv" --resume "$CASE_ROOT/.supervisor/automate" --run "$CASE_RUN" --session-id coord-4
  [ "$NC_RC" = 0 ] && f_spawn_ok "$NC_OUT" plan launch-pad && grep -qx '## Status: running' "$CASE_RF" && grep -qx -- '- pause_reason: null' "$CASE_RF" \
    && [ "$(grep -c " picked $it\$" "$CASE_RF")" = 2 ] \
    || { LEG_MSG="--resume refined ⇒ exit $NC_RC '${NC_OUT:0:240}' ${NC_ERR:0:200}"; return 1; }
  # the owner gives up on it: the check-off moves the run to the next row
  np_lp "$drv" aborted 'owner aborted at NO-GO'; it="$(np_item)"; np_parked || { LEG_MSG="aborted ⇒ not parked"; return 1; }
  ( cd "$CASE_ROOT" && bash "$H" queue-checkoff "$CASE_RF" "$it" "owner gave up" skipped ) >/dev/null 2>&1
  p_call_fresh "$drv" --resume "$CASE_ROOT/.supervisor/automate" --run "$CASE_RUN" --session-id coord-5
  [ "$NC_RC" = 0 ] && f_spawn_ok "$NC_OUT" plan launch-pad && [ "$(np_item)" != "$it" ] \
    || { LEG_MSG="skipped check-off ⇒ exit $NC_RC '${NC_OUT:0:240}' ${NC_ERR:0:200}"; return 1; }
  # a gate's stop: parked too, but nobody chose it, so the owner's --resume is the remedy
  np_lp "$drv" blocked 'plan_review_fail_non_interactive — FAIL x3, nobody to ask'; it="$(np_item)"
  np_parked && grep -qE -- '^- [0-9TZ:-]+ parked no_pr_stop — launch_pad_cant_ask_non_interactive$' "$CASE_RF" || { LEG_MSG="cant_ask ⇒ $(tail -n 2 "$CASE_RF" | tr '\n' '|')"; return 1; }
  p_call_fresh "$drv" --resume "$CASE_ROOT/.supervisor/automate" --run "$CASE_RUN" --session-id coord-6
  [ "$NC_RC" = 0 ] && f_spawn_ok "$NC_OUT" plan launch-pad || { LEG_MSG="cant_ask --resume ⇒ exit $NC_RC '${NC_OUT:0:240}' ${NC_ERR:0:200}"; return 1; }
  # a failure is not a decision: no park, the run file stays as a lane reads `stalled`
  new_scratch "$FIX/run-config-suppress-restore" || { LEG_MSG="scratch"; return 1; }; f_claude 1
  f_call "$drv" --start run --session-id coord-1
  f_call "$drv" --result '{"status_reason":"phase_died","no_pr_why":"phase-wait: died — no result line since the last launch","session_id":"lp-sess-1"}'
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "done" and .status == "stopped"' >/dev/null 2>&1 \
    && grep -qx '## Status: running' "$CASE_RF" && grep -qx -- '- pause_reason: null' "$CASE_RF" && ! grep -q 'parked no_pr_stop' "$CASE_RF" \
    || { LEG_MSG="phase_died ⇒ exit $NC_RC '${NC_OUT:0:200}'"; return 1; }
  # a block the validator rejected, no brief: the fallback's user_discarded_at_phase_6 names nobody's decision
  f_plan_case "$drv" "$(printf 'LAUNCH_PAD_RESULT:\n  status: saved\n')"
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "done" and .status == "stopped"' >/dev/null 2>&1 && ! grep -q 'parked no_pr_stop' "$CASE_RF" \
    || { LEG_MSG="malformed ⇒ exit $NC_RC '${NC_OUT:0:200}'"; return 1; }
}
p_call_fresh() { # <driver> <args…> — a fresh-phase call WITHOUT the run file (the resume entry)
  local drv="$1"; shift
  NC_OUT="$(NS_FRESH=1 NS_REAL_LOCK=1 in_case "$drv" "$R_SEAMS" bash "$drv" "$@" 2>"$CASE_DIR/nc.err")"; NC_RC=$?
  NC_ERR="$(cat "$CASE_DIR/nc.err")"
}
# leg_inline_checkpoint <driver> — F4's --inline-phases twin. `record`: an inline RUN whose SUPERVISOR_RESULT is a
# checkpoint, reported with /autonomous's `supervisor_checkpoint` token and a why that names no task, writes the
# no-PR line with `resume with /supervisor --continue task: <task_id>` (the block's task_id; inline has no
# `launch-pad saved` line to fall back on); with the brief in .supervisor/jobs/in-progress/, the re-pick then
# prints the inline `/loomwright:supervisor --continue task: <id>` spawn (no `session`, no Launch Pad) whose `then`
# asks for the SUPERVISOR_RESULT RUN report, and its suppress line names the resumed task. `flags`: a `--start run`
# with --notify --cheap --max-tokens forwards --cheap and --max-tokens, never --notify or --non-interactive-fallback.
# `no-inprogress`: the brief gone ⇒ the pre-fix `/autonomous --single-iteration` spawn
leg_inline_checkpoint() {
  local drv="$1" c tid=2026-10-14-af39b it sp want sr
  for c in record flags no-inprogress; do
    new_scratch "$FIX/run-config-suppress-restore" || { LEG_MSG="scratch"; return 1; }
    it="$(sed -n 's/^- item: \([^ ]*\) .*/\1/p' "$CASE_RF" | head -n 1)"
    if [ "$c" = record ]; then
      f_call "$drv" --inline-phases --start run --non-interactive --session-id coord-1; sp="$NC_OUT"
      [ "$NC_RC" = 0 ] && printf '%s' "$sp" | jq -e --arg i "/autonomous --single-iteration --requirement $it --non-interactive-fallback" '.do == "spawn" and .step == "run" and .invocation == $i' >/dev/null 2>&1 \
        || { LEG_MSG="record: --start run ⇒ exit $NC_RC '${sp:0:240}' ${NC_ERR:0:200}"; return 1; }
      sr="$(printf 'SUPERVISOR_RESULT:\n  schema_version: 1\n  task_id: %s\n  status: checkpoint\n  pr_url: null\n  branch: feature/%s\n  subtasks_completed: 3\n  subtasks_failed: 0\n  heal_loop_ran: false\n  heal_iterations: null\n  heal_decision: null\n  heal_fixable_issues_fixed: 0\n  heal_remaining_issues: 0\n  summary: "checkpointed at Phase 3 EXECUTE"\n' "$tid" "$tid")"
      f_call "$drv" --result "$(jq -cn --arg s "$sr" '{supervisor_result: $s, status_reason: "supervisor_checkpoint", no_pr_why: "Supervisor checkpointed at Phase 3 EXECUTE (subtask 4 hit its turn limit)", session_id: "inl-sess-1"}')"
      [ "$NC_RC" = 0 ] && grep -qxE -- "- [0-9TZ:-]+ ran /autonomous — no PR: supervisor_checkpoint \(Supervisor checkpointed at Phase 3 EXECUTE \(subtask 4 hit its turn limit\); resume with /supervisor --continue task: $tid\)" "$CASE_RF" \
        || { LEG_MSG="record: the checkpoint RUN report ⇒ exit $NC_RC ${NC_ERR:0:200} ## Progress $(sed -n '/## Progress/,$p' "$CASE_RF" | tr '\n' '|' | tail -c 600)"; return 1; }
    fi
    [ "$c" = no-inprogress ] && printf -- '- 2026-10-14T11:00:01Z ran /autonomous — no PR: supervisor_checkpoint (Supervisor checkpointed; resume with /supervisor --continue task: %s)\n' "$tid" >> "$CASE_RF"
    [ "$c" = flags ] && printf -- '- 2026-10-14T11:00:01Z ran /autonomous — no PR: supervisor_checkpoint (Supervisor checkpointed; resume with /supervisor --continue task: %s)\n' "$tid" >> "$CASE_RF"
    [ "$c" = no-inprogress ] || { mkdir -p "$CASE_ROOT/.supervisor/jobs/in-progress" && printf '# Brief\n' > "$CASE_ROOT/.supervisor/jobs/in-progress/$tid.md"; }
    case "$c" in
      record) # the re-pick: PICK's trail-gate reads this run's open trail PR: none
        printf '0\tpr list --state open *\t[]\n0\tpr list *\t[]\n' >> "$CASE_GH"
        f_call "$drv" --inline-phases --start pick --non-interactive --session-id coord-1
        want="/loomwright:supervisor --continue task: $tid --non-interactive" ;;
      flags) f_call "$drv" --inline-phases --start run --notify --cheap --max-tokens 900000 --session-id coord-1
        want="/loomwright:supervisor --continue task: $tid --cheap --max-tokens 900000" ;;
      no-inprogress) f_call "$drv" --inline-phases --start run --session-id coord-1
        want="/autonomous --single-iteration --requirement $it" ;;
    esac
    sp="$NC_OUT"
    [ "$NC_RC" = 0 ] && printf '%s' "$sp" | jq -e --arg i "$want" '.do == "spawn" and .step == "run" and .what == "/autonomous run"
          and (has("session") | not) and (has("launch") | not) and .invocation == $i and (.then | contains("SUPERVISOR_RESULT"))' >/dev/null 2>&1 \
      && [ "$(jq -c . "$CASE_ROOT/.supervisor/config.json" 2>/dev/null)" = '{"auto_review":false}' ] \
      || { LEG_MSG="$c ⇒ exit $NC_RC '${sp:0:300}' ${NC_ERR:0:200}"; return 1; }
    if [ "$c" != no-inprogress ]; then
      printf '%s' "$sp" | jq -e '.then | contains("inline") and contains("no Launch Pad")' >/dev/null 2>&1 \
        && grep -qE -- "^- [0-9TZ:-]+ auto_review suppressed \(backup $CASE_RUN\.config-backup\.json\) — running /loomwright:supervisor --continue task: $tid \(inline — the checkpointed run, no fresh Launch Pad\)\$" "$CASE_RF" \
        || { LEG_MSG="$c: then '$(printf '%s' "$sp" | jq -r .then | head -c 200)' ## Progress $(sed -n '/## Progress/,$p' "$CASE_RF" | tr '\n' '|' | tail -c 600)"; return 1; }
    fi
  done
  return 0
}
# leg_lane_cheap <driver> — inside a lane, `.supervisor/lane.json` `"cheap": true` (lane-create --cheap) sets --cheap
# though the call names none: the RUN spawn carries it. A lane.json without the key, and a checkout with no
# lane.json at all (the sequential run), get none — there --cheap stays passthrough-only
leg_lane_cheap() {
  local drv="$1" c it want
  for c in cheap nokey nolane; do
    new_scratch "$FIX/run-config-suppress-restore" || { LEG_MSG="scratch"; return 1; }
    it="$(sed -n 's/^- item: \([^ ]*\) .*/\1/p' "$CASE_RF" | head -n 1)"
    case "$c" in
      cheap) printf '{"schema_version":1,"lane":"L1","cheap":true}\n' > "$CASE_ROOT/.supervisor/lane.json"
        want="/autonomous --single-iteration --requirement $it --cheap" ;;
      nokey) printf '{"schema_version":1,"lane":"L1"}\n' > "$CASE_ROOT/.supervisor/lane.json"
        want="/autonomous --single-iteration --requirement $it" ;;
      nolane) want="/autonomous --single-iteration --requirement $it" ;;
    esac
    f_call "$drv" --inline-phases --start run --session-id coord-1
    [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e --arg i "$want" '.do == "spawn" and .step == "run" and .invocation == $i' >/dev/null 2>&1 \
      || { LEG_MSG="$c ⇒ exit $NC_RC '${NC_OUT:0:300}' ${NC_ERR:0:200}"; return 1; }
  done
  return 0
}
# leg_lane_scope_hold <driver> — lane-scope-regate Part B (B1, B3, B5 Revise, B7): inside a lane whose lane.json
# reads `parallel: 2`, a saved Launch Pad report writes the pinned `launch-pad saved <brief>` line FIRST, then parks
# `scope_hold` (## Status: paused, current-set's run-level form — the item stays `status: running`, one `scope_hold —`
# line), and spawns no Supervisor phase; while held `--start run` is refused (exit 2) and a bare call re-prints the
# park; once released (what lane-scope-decide writes: ## Status: running, pause_reason null, the release line) a bare
# call resumes at RUN — the Supervisor phase on that brief, no second Launch Pad spawn. A `revise` release resumes at
# a new Launch Pad phase whose prompt names the files to keep off. `parallel: 1` and no lane.json go straight to the
# Supervisor phase (no hold). A plan-review deferral (issue 1): the leg lives beside the runner's other legs.
lsh_release() { # <revise files|""> — the release lane-scope-decide writes, applied to the case's run file
  local l="scope re-gate released (continue)"
  [ -z "$1" ] || l="scope re-gate released (revise) — keep off: $1"
  awk '!d && /^## Status: / { print "## Status: running"; d = 1; next } { print }' "$CASE_RF" > "$CASE_RF.t" \
    && sed 's/^- pause_reason: scope_hold$/- pause_reason: null/' "$CASE_RF.t" > "$CASE_RF" && rm -f "$CASE_RF.t" \
    && printf -- '- 2026-11-04T10:00:00Z %s\n' "$l" >> "$CASE_RF"
}
lsh_saved() { # <driver> <lane.json text|""> — a fresh --start run, then a saved Launch Pad report naming .supervisor/jobs/pending/h.md
  local ad lp
  new_scratch "$FIX/run-config-suppress-restore" || { NC_RC=98; return 1; }
  f_claude 1; ad="$CASE_ROOT/.supervisor/automate"
  [ -z "$2" ] || printf '%s\n' "$2" > "$CASE_ROOT/.supervisor/lane.json"
  f_call "$1" --start run --session-id coord-1
  [ "$NC_RC" = 0 ] && f_spawn_ok "$NC_OUT" plan launch-pad || { NC_RC=99; return 1; }
  mkdir -p "$CASE_ROOT/.supervisor/jobs/pending" && printf '# Brief\n' > "$CASE_ROOT/.supervisor/jobs/pending/h.md"
  lp="$(printf 'LAUNCH_PAD_RESULT:\n  schema_version: 1\n  status: saved\n  saved_brief_path: .supervisor/jobs/pending/h.md\n  summary: PASS\n')"
  printf '%s' "$lp" > "$ad/$CASE_RUN.launch-pad-result.md"
  f_call "$1" --result "$(jq -cn --arg f "$ad/$CASE_RUN.launch-pad-result.md" '{launch_pad_result_file: $f, session_id: "lp-sess-1"}')"
}
lsh_sup_ok() { # the Supervisor phase spawn on h.md
  [ "$NC_RC" = 0 ] && f_spawn_ok "$NC_OUT" run supervisor \
    && printf '%s' "$NC_OUT" | jq -e '.invocation == "/loomwright:supervisor job: .supervisor/jobs/pending/h.md"' >/dev/null 2>&1
}
leg_lane_scope_hold() {
  local drv="$1" c
  lsh_saved "$drv" '{"schema_version":1,"lane":"L2","parallel":2}'
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "park" and .pause_reason == "scope_hold"' >/dev/null 2>&1 \
    && grep -qx '## Status: paused' "$CASE_RF" && grep -qx -- '- pause_reason: scope_hold' "$CASE_RF" \
    && grep -q '^- item: .* | status: running' "$CASE_RF" \
    && in_order "$CASE_RF" 'launch-pad saved .supervisor/jobs/pending/h.md' 'scope_hold — .supervisor/jobs/pending/h.md saved; held before the Supervisor phase' \
    && ! grep -q 'auto_review suppressed' "$CASE_RF" && [ ! -e "$CASE_ROOT/.supervisor/config.json" ] \
    || { LEG_MSG="parallel 2 ⇒ exit $NC_RC '${NC_OUT:0:200}' ${NC_ERR:0:200} $(tr '\n' '|' < "$CASE_RF" | tail -c 400)"; return 1; }
  f_call "$drv" --start run --session-id coord-1
  [ "$NC_RC" = 2 ] && case "$NC_ERR" in *scope_hold*) true ;; *) false ;; esac \
    || { LEG_MSG="held --start run ⇒ exit $NC_RC ${NC_ERR:0:200}"; return 1; }
  f_call "$drv" --session-id coord-1
  [ "$NC_RC" = 0 ] && printf '%s' "$NC_OUT" | jq -e '.do == "park" and .pause_reason == "scope_hold"' >/dev/null 2>&1 \
    || { LEG_MSG="held bare call ⇒ exit $NC_RC '${NC_OUT:0:200}'"; return 1; }
  lsh_release "" && f_call "$drv" --session-id coord-1
  lsh_sup_ok && [ "$(grep -c 'launch-pad saved' "$CASE_RF")" = 1 ] \
    || { LEG_MSG="released bare call ⇒ exit $NC_RC '${NC_OUT:0:240}' ${NC_ERR:0:200}"; return 1; }
  # Revise: the bare call after a revise release is a NEW Launch Pad phase whose prompt names the files to keep off
  lsh_saved "$drv" '{"schema_version":1,"lane":"L2","parallel":2}'
  lsh_release "src/k.ts, src/p.ts" && f_call "$drv" --session-id coord-1
  [ "$NC_RC" = 0 ] && f_spawn_ok "$NC_OUT" plan launch-pad \
    && printf '%s' "$NC_OUT" | jq -e '.prompt | contains("Revise at the coordinator'"'"'s scope re-gate") and contains("src/k.ts, src/p.ts")' >/dev/null 2>&1 \
    || { LEG_MSG="revise release ⇒ exit $NC_RC '${NC_OUT:0:240}' ${NC_ERR:0:200}"; return 1; }
  # --inline-phases has no launch-pad saved line, so an N > 1 lane could never hold: refused, not silently unguarded,
  # and the refused flag does not persist. A single lane may run it (not refused here)
  new_scratch "$FIX/run-config-suppress-restore" || { LEG_MSG="no scratch"; return 1; }
  f_claude 1; printf '%s\n' '{"schema_version":1,"lane":"L2","parallel":2}' > "$CASE_ROOT/.supervisor/lane.json"
  f_call "$drv" --start run --session-id coord-1 --inline-phases
  [ "$NC_RC" = 2 ] && case "$NC_ERR" in *inline_phases_in_parallel_lane*) true ;; *) false ;; esac \
    || { LEG_MSG="--inline-phases in an N > 1 lane ⇒ exit $NC_RC ${NC_ERR:0:200}"; return 1; }
  f_call "$drv" --start run --session-id coord-1
  [ "$NC_RC" = 0 ] && f_spawn_ok "$NC_OUT" plan launch-pad \
    || { LEG_MSG="the refused flag persisted ⇒ exit $NC_RC '${NC_OUT:0:200}' ${NC_ERR:0:200}"; return 1; }
  new_scratch "$FIX/run-config-suppress-restore" || { LEG_MSG="no scratch"; return 1; }
  f_claude 1; printf '%s\n' '{"schema_version":1,"lane":"L1","parallel":1,"single_lane":true}' > "$CASE_ROOT/.supervisor/lane.json"
  f_call "$drv" --start run --session-id coord-1 --inline-phases
  [ "$NC_RC" != 2 ] || ! case "$NC_ERR" in *inline_phases_in_parallel_lane*) true ;; *) false ;; esac \
    || { LEG_MSG="--inline-phases in a single lane refused ⇒ ${NC_ERR:0:200}"; return 1; }
  # B7: a single lane and a sequential run never hold
  for c in '{"schema_version":1,"lane":"L1","parallel":1,"single_lane":true}' ''; do
    lsh_saved "$drv" "$c"
    lsh_sup_ok && ! grep -q 'scope_hold' "$CASE_RF" \
      || { LEG_MSG="no hold (${c:-no lane.json}) ⇒ exit $NC_RC '${NC_OUT:0:200}' ${NC_ERR:0:200}"; return 1; }
  done
  return 0
}
# leg_fresh_owner_session <driver> — review fixes (iterations 1 + 2): --owner-command is the launch authority of the
# session that typed it, and a pending fresh spawn's `launch` line is REBUILT from the re-printing call's identity.
# coord-1's own re-print stays byte for byte (its owner command, --coordinator-session coord-1). Re-printed with
# --session-id coord-2 it carries no owner command and --coordinator-session coord-2; that identity PERSISTS, so a
# later bare re-print and a bare --result (the Supervisor spawn) carry coord-2 and no owner command (X1, X3). A
# second case: coord-2's OWN --owner-command given on a re-print is used, and inherited by the bare calls (X2)
leg_fresh_owner_session() {
  local drv="$1" b=.supervisor/jobs/pending/o.md ad first own c rep
  for c in none own; do
    new_scratch "$FIX/run-config-suppress-restore" || { LEG_MSG="scratch"; return 1; }
    f_claude 1; ad="$CASE_ROOT/.supervisor/automate"
    f_call "$drv" --start run --session-id coord-1 --owner-command "$F_OWNER"; first="$NC_OUT"
    [ "$NC_RC" = 0 ] && f_spawn_ok "$NC_OUT" plan launch-pad && f_argv_ok "$NC_OUT" launch-pad "$F_OWNER" \
      || { LEG_MSG="$c: coord-1 --start run ⇒ exit $NC_RC '${NC_OUT:0:160}' ${NC_ERR:0:160}"; return 1; }
    f_call "$drv"
    [ "$NC_RC" = 0 ] && [ "$NC_OUT" = "$first" ] || { LEG_MSG="$c: coord-1's bare re-print is not byte for byte its spawn: '${NC_OUT:0:200}'"; return 1; }
    f_call "$drv" --session-id coord-1
    [ "$NC_RC" = 0 ] && [ "$NC_OUT" = "$first" ] || { LEG_MSG="$c: coord-1's re-print (--session-id coord-1) is not byte for byte its spawn"; return 1; }
    if [ "$c" = own ]; then own='/automate --resume coord-2-typed'; rep=(--session-id coord-2 --owner-command "$own"); else own=""; rep=(--session-id coord-2); fi
    f_call "$drv" "${rep[@]}"
    [ "$NC_RC" = 0 ] && f_spawn_ok "$NC_OUT" plan launch-pad && f_argv_ok "$NC_OUT" launch-pad "$own" coord-2 \
      || { LEG_MSG="$c: coord-2 re-print ⇒ exit $NC_RC '${NC_OUT:0:240}' (want owner '${own}', coord-2)"; return 1; }
    f_call "$drv"
    [ "$NC_RC" = 0 ] && f_argv_ok "$NC_OUT" launch-pad "$own" coord-2 \
      || { LEG_MSG="$c: the bare re-print after coord-2's did not inherit coord-2's identity: '${NC_OUT:0:240}'"; return 1; }
    mkdir -p "$CASE_ROOT/.supervisor/jobs/pending" && printf '# Brief\n\n## Task\no\n' > "$CASE_ROOT/$b"
    printf 'LAUNCH_PAD_RESULT:\n  schema_version: 1\n  status: saved\n  saved_brief_path: %s\n  summary: PASS\n' "$b" > "$ad/$CASE_RUN.launch-pad-result.md"
    f_call "$drv" --result "$(jq -cn --arg f "$ad/$CASE_RUN.launch-pad-result.md" '{launch_pad_result_file: $f, session_id: "lp-sess-1"}')"
    [ "$NC_RC" = 0 ] && f_spawn_ok "$NC_OUT" run supervisor && f_argv_ok "$NC_OUT" supervisor "$own" coord-2 \
      || { LEG_MSG="$c: the bare --result's Supervisor spawn ⇒ exit $NC_RC '${NC_OUT:0:240}' (want owner '${own}', coord-2) ${NC_ERR:0:160}"; return 1; }
    # each coordinator that printed a phase spawn names itself once (phase=driver); a re-print writes nothing
    [ "$(grep -cE ' session_id coord-1 \(.*\) phase=driver$' "$CASE_RF")" = 1 ] && [ "$(grep -cE ' session_id coord-2 \(.*\) phase=driver$' "$CASE_RF")" = 1 ] \
      || { LEG_MSG="$c: driver lines: $(grep 'phase=driver' "$CASE_RF" | tr '\n' '|' | head -c 300)"; return 1; }
  done
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

# --------------------------------------------------------------------------------------
# CM — the coordinator_model setting and its escalate-on-failure valve (automate-speed/10)
# --------------------------------------------------------------------------------------
CM_LEDGER_REL=".supervisor/automate/coordinator-model.jsonl"
CM_VALUES="session claude-haiku-5-5 claude-sonnet-5-5"
# the shipped default: the pin follows whatever the A/B set (docs/evidence/coordinator-model-ab.md)
CM_DEFAULT="$(sed -n 's/^NS_CM_DEFAULT=//p' "$DRIVER" | head -n 1)"
ESC_CALL="$(grep -m1 '^call: ' "$FIX/escalated-park/next-step.results")"
DFD_CALL1="$(grep '^call: ' "$FIX/dismissed-findings-decision-step/next-step.results" | sed -n 1p)"
DFD_CALL2="$(grep '^call: ' "$FIX/dismissed-findings-decision-step/next-step.results" | sed -n 2p)"
cm_lines() { # <true|false> <n> — n report lines
  local i=0
  while [ "$i" -lt "$2" ]; do printf '{"ts":"2026-10-20T00:00:00Z","run_id":"r","item":null,"step":"gate","ok":%s}\n' "$1"; i=$((i + 1)); done
}
CM_ESC_REC='{"ts":"2026-10-20T00:00:00Z","escalated":true,"fails":3,"window":20,"from":"claude-haiku-5-5"}'
# cm_run <driver> <case> <config json|-> <ledger text|-> <directives> — a fresh scratch, config / ledger seeded
cm_run() {
  new_scratch "$FIX/$2" || { DRIVE_ERR="scratch not built"; return 1; }
  [ "$3" = - ] || printf '%s\n' "$3" > "$CASE_ROOT/.supervisor/config.json"
  [ "$4" = - ] || printf '%s' "$4" > "$CASE_ROOT/$CM_LEDGER_REL"
  printf '%s\n' "$5" > "$CASE_DIR/cm.results"
  drive "$FIX/$2" "$1" "$CASE_DIR/cm.results"
}
cm_model() { printf '%s' "$LAST_OUT" | jq -r 'if has("coordinator_model") then .coordinator_model else "ABSENT" end' 2>/dev/null; }
cm_last_err() { local n; n="$(grep -c '^call' "$CASE_DIR/cm.results")"; cat "$CASE_DIR/call$n.err" 2>/dev/null; }
cm_ledger() { cat "$CASE_ROOT/$CM_LEDGER_REL" 2>/dev/null; }
cm_n() { cm_ledger | grep -c . | tr -d ' '; }

# leg_cm_setting <driver> — absent ⇒ the shipped default; each listed value ⇒ itself; an invalid value (an
# unknown id, a non-string, a config that is not an object) ⇒ session, ONE named stderr line, never a refusal
leg_cm_setting() {
  local drv="$1" v m e
  cm_run "$drv" escalated-park - - "$ESC_CALL"$'\nexpect: park'
  [ -z "$DRIVE_ERR" ] && [ "$(cm_model)" = "$CM_DEFAULT" ] || { LEG_MSG="absent key: '$(cm_model)', want the default '$CM_DEFAULT' ($DRIVE_ERR)"; return 1; }
  for v in $CM_VALUES; do
    cm_run "$drv" escalated-park "{\"coordinator_model\":\"$v\"}" - "$ESC_CALL"$'\nexpect: park'
    [ -z "$DRIVE_ERR" ] && [ "$(cm_model)" = "$v" ] || { LEG_MSG="configured $v: '$(cm_model)' ($DRIVE_ERR)"; return 1; }
  done
  for v in '{"coordinator_model":"gpt-9"}' '{"coordinator_model":5}' '{"coordinator_model":"claude-haiku-5-5 session"}' '[1]'; do
    cm_run "$drv" escalated-park "$v" - "$ESC_CALL"$'\nexpect: park'
    m="$(cm_model)"; e="$(cm_last_err | grep -c '^next-step: coordinator_model_invalid' | tr -d ' ')"
    [ -z "$DRIVE_ERR" ] && [ "$m" = session ] && [ "$e" = 1 ] || { LEG_MSG="invalid $v: model '$m', $e invalid line(s) ($DRIVE_ERR)"; return 1; }
  done
  return 0
}
# leg_cm_every <driver> — every instruction a spawn / ask / park / done case prints carries a listed coordinator_model
leg_cm_every() {
  local drv="$1" c n=0 bad="" f l
  for c in run-config-suppress-restore dismissed-findings-decision-step resume-glob-finalize check-off-progress; do
    golden_case "$c" "$drv" || { LEG_MSG="$c: $GC_MSG"; return 1; }
    for f in "$CASE_DIR"/call*.out; do
      [ -s "$f" ] || continue
      l="$(head -n 1 "$f")"; n=$((n + 1))
      case " $CM_VALUES " in *" $(printf '%s' "$l" | jq -r '.coordinator_model // "ABSENT"' 2>/dev/null) "*) ;; *) bad="$bad $c:$(basename "$f")" ;; esac
    done
  done
  [ "$n" -ge 6 ] && [ -z "$bad" ] || { LEG_MSG="$n instruction(s); without a listed coordinator_model:${bad:- none}"; return 1; }
  CM_EVERY_N="$n"; return 0
}
# leg_cm_resume <driver> — the inline --resume no-incomplete-run start_new carries the field, resolved from
# the checkout that holds the automate dir (a --root elsewhere does not change it)
leg_cm_resume() {
  local drv="$1"
  new_scratch "$FIX/escalated-park" || { LEG_MSG="scratch not built"; return 1; }
  rm -f "$CASE_RF"; printf '{"coordinator_model":"claude-haiku-5-5"}\n' > "$CASE_ROOT/.supervisor/config.json"
  mkdir -p "$CASE_DIR/elsewhere/.supervisor"; printf '{"coordinator_model":"claude-sonnet-5-5"}\n' > "$CASE_DIR/elsewhere/.supervisor/config.json"
  # AD / RUN_ID unset in the driver's environment (in_case exports them): the resume entry must not lean on them
  printf '%s\n' 'env: AD= RUN_ID=' 'call-bare: --resume "$AD" --session-id cm-resume' 'expect: done' > "$CASE_DIR/cm.results"
  drive "$FIX/escalated-park" "$drv" "$CASE_DIR/cm.results"
  [ -z "$DRIVE_ERR" ] && [ "$(printf '%s' "$LAST_OUT" | jq -r .choice)" = start_new ] && [ "$(cm_model)" = claude-haiku-5-5 ] \
    || { LEG_MSG="start_new: '$LAST_OUT' ($DRIVE_ERR)"; return 1; }
  printf '%s\n' 'env: AD= RUN_ID=' 'call-bare: --resume "$AD" --root "$CASE_DIR/elsewhere" --session-id cm-resume' 'expect: done' > "$CASE_DIR/cm.results"
  drive "$FIX/escalated-park" "$drv" "$CASE_DIR/cm.results"
  [ -z "$DRIVE_ERR" ] && [ "$(cm_model)" = claude-haiku-5-5 ] || { LEG_MSG="start_new with --root elsewhere: '$(cm_model)' ($DRIVE_ERR)"; return 1; }
  return 0
}
# leg_cm_threshold <driver> — 2 FAILs in the last 20 ⇒ no escalation; FAILs older than the window do not
# count; the 3rd FAIL (a refused report) ⇒ ONE escalated record, then session
leg_cm_threshold() {
  local drv="$1" hk='{"coordinator_model":"claude-haiku-5-5"}' l3 l4
  cm_run "$drv" escalated-park "$hk" "$(cm_lines false 2; cm_lines true 5)"$'\n' "$ESC_CALL"$'\nexpect: park'
  [ -z "$DRIVE_ERR" ] && [ "$(cm_model)" = claude-haiku-5-5 ] && ! grep -q '"escalated"' < <(cm_ledger) \
    || { LEG_MSG="2 FAILs/20: '$(cm_model)' ($DRIVE_ERR)"; return 1; }
  cm_run "$drv" escalated-park "$hk" "$(cm_lines false 3; cm_lines true 20)"$'\n' "$ESC_CALL"$'\nexpect: park'
  [ -z "$DRIVE_ERR" ] && [ "$(cm_model)" = claude-haiku-5-5 ] || { LEG_MSG="3 FAILs outside the window: '$(cm_model)' ($DRIVE_ERR)"; return 1; }
  cm_run "$drv" escalated-park "$hk" "$(cm_lines false 2)"$'\n' "call: --result 'not json'"$'\nexpect-exit: 2\n'"$ESC_CALL"$'\nexpect: park'
  l3="$(cm_ledger | sed -n 3p)"; l4="$(cm_ledger | sed -n 4p)"
  printf '%s' "$l3" | jq -e '.ok == false and (.reason | test("not a JSON object"))' >/dev/null 2>&1 \
    && printf '%s' "$l4" | jq -e '.escalated == true and .fails == 3 and .window == 20 and .from == "claude-haiku-5-5"' >/dev/null 2>&1 \
    && [ "$(cm_ledger | grep -c '"escalated"' | tr -d ' ')" = 1 ] && [ -z "$DRIVE_ERR" ] && [ "$(cm_model)" = session ] \
    || { LEG_MSG="3 FAILs/20: model '$(cm_model)', ledger: $(cm_ledger | tr '\n' ' ') ($DRIVE_ERR)"; return 1; }
  return 0
}
# leg_cm_persist <driver> — an escalated record followed by 25 ok lines still resolves session
leg_cm_persist() {
  local drv="$1"
  cm_run "$drv" escalated-park '{"coordinator_model":"claude-haiku-5-5"}' "$CM_ESC_REC"$'\n'"$(cm_lines true 25)"$'\n' "$ESC_CALL"$'\nexpect: park'
  [ -z "$DRIVE_ERR" ] && [ "$(cm_model)" = session ] || { LEG_MSG="escalated + 25 ok: '$(cm_model)' ($DRIVE_ERR)"; return 1; }
  return 0
}
# leg_cm_badledger <driver> — a malformed ledger, and one at its byte cap, resolve session with a named
# stderr line; nothing is appended to the capped one
leg_cm_badledger() {
  local drv="$1" e s0
  cm_run "$drv" escalated-park '{"coordinator_model":"claude-haiku-5-5"}' $'not json\n' "$ESC_CALL"$'\nexpect: park'
  e="$(cm_last_err | grep -c '^next-step: coordinator_model_ledger_malformed' | tr -d ' ')"
  [ -z "$DRIVE_ERR" ] && [ "$(cm_model)" = session ] && [ "$e" = 1 ] || { LEG_MSG="malformed ledger: '$(cm_model)', $e line(s) ($DRIVE_ERR)"; return 1; }
  cm_run "$drv" escalated-park '{"coordinator_model":"claude-haiku-5-5"}' "$(cm_lines true 3500)"$'\n' "$ESC_CALL"$'\nexpect: park'
  e="$(cm_last_err | grep -c '^next-step: coordinator_model_ledger_over_cap' | tr -d ' ')"
  [ -z "$DRIVE_ERR" ] && [ "$(cm_model)" = session ] && [ "$e" = 1 ] && [ "$(cm_n)" = 3500 ] \
    || { LEG_MSG="capped ledger: '$(cm_model)', $e line(s), $(cm_n) ledger lines ($DRIVE_ERR)"; return 1; }
  return 0
}
# leg_cm_delete <driver> — the owner deletes the ledger: the configured value resolves again. Read through the
# no-result resume start_new (it appends nothing, so each call resolves the ledger exactly as it lies on disk;
# an accepted --result report appends its ok line BEFORE the instruction resolves, re-creating the file)
leg_cm_delete() {
  local drv="$1"
  new_scratch "$FIX/escalated-park" || { LEG_MSG="scratch not built"; return 1; }
  rm -f "$CASE_RF"; printf '{"coordinator_model":"claude-haiku-5-5"}\n' > "$CASE_ROOT/.supervisor/config.json"
  printf '%s\n' "$CM_ESC_REC" "$(cm_lines true 2)" > "$CASE_ROOT/$CM_LEDGER_REL"
  printf '%s\n' 'env: AD= RUN_ID=' 'call-bare: --resume "$AD" --session-id cm-delete' 'expect: done' > "$CASE_DIR/cm.results"
  drive "$FIX/escalated-park" "$drv" "$CASE_DIR/cm.results"
  [ -z "$DRIVE_ERR" ] && [ "$(cm_model)" = session ] || { LEG_MSG="escalated ledger: '$(cm_model)' ($DRIVE_ERR)"; return 1; }
  rm -f "$CASE_ROOT/$CM_LEDGER_REL"
  drive "$FIX/escalated-park" "$drv" "$CASE_DIR/cm.results"
  [ -z "$DRIVE_ERR" ] && [ "$(cm_model)" = claude-haiku-5-5 ] && [ ! -e "$CASE_ROOT/$CM_LEDGER_REL" ] \
    || { LEG_MSG="ledger deleted: '$(cm_model)' ($DRIVE_ERR)"; return 1; }
  return 0
}
# leg_cm_refusal <driver> — a refused report (not a JSON object; an ask answered with a label it does not
# offer) appends exactly ONE ok:false line and changes nothing else under .supervisor/; usage errors append nothing
leg_cm_refusal() {
  local drv="$1" s0 n0 l
  cm_run "$drv" escalated-park - - "call: --result 'not json'"$'\nexpect-exit: 2'
  l="$(cm_ledger)"
  [ -z "$DRIVE_ERR" ] && [ "$(cm_n)" = 1 ] \
    && printf '%s' "$l" | jq -e --arg r "$CASE_RUN" '.ok == false and .run_id == $r and (.reason | test("not a JSON object"))
         and .item == ".supervisor/requirements/twin-loop/01-commit-the-distilled-twin.md" and (.ts | test("^[0-9]{4}-"))' >/dev/null 2>&1 \
    || { LEG_MSG="not-JSON refusal: ledger '$l' ($DRIVE_ERR)"; return 1; }
  s0="$(snapshot)"; n0="$(cm_n)"
  # a well-formed report sent with a --root that is not a directory is a usage error too (it appends nothing)
  printf '%s\n' 'call: --bogus-flag' 'expect-exit: 2' 'call: --start pick --result "{}"' 'expect-exit: 2' \
    "$ESC_CALL --root /nonexistent/cm-bad-root" 'expect-exit: 2' > "$CASE_DIR/cm.results"
  drive "$FIX/escalated-park" "$drv" "$CASE_DIR/cm.results"
  [ -z "$DRIVE_ERR" ] && [ "$(cm_n)" = "$n0" ] && [ "$s0" = "$(snapshot)" ] || { LEG_MSG="usage errors wrote: ledger $(cm_n) line(s) ($DRIVE_ERR)"; return 1; }
  cm_run "$drv" dismissed-findings-decision-step - - "$DFD_CALL1"$'\nexpect: ask'
  [ -z "$DRIVE_ERR" ] && [ "$(cm_n)" = 1 ] && cm_ledger | jq -e '.ok == true and .step == "gate"' >/dev/null 2>&1 \
    || { LEG_MSG="accepted drain report: ledger '$(cm_ledger)' ($DRIVE_ERR)"; return 1; }
  s0="$(snapshot)"
  printf '%s\n' "call: --result '{\"answers\":[\"Not an option\"]}'" 'expect-exit: 2' > "$CASE_DIR/cm.results"
  drive "$FIX/dismissed-findings-decision-step" "$drv" "$CASE_DIR/cm.results"
  l="$(cm_ledger | sed -n 2p)"
  [ -z "$DRIVE_ERR" ] && [ "$(cm_n)" = 2 ] && [ "$s0" = "$(snapshot)" ] && printf '%s' "$l" | jq -e '.ok == false and .step == "decide" and (.reason | length) > 0' >/dev/null 2>&1 \
    || { LEG_MSG="refused answer: ledger line '$l', $(cm_n) line(s) ($DRIVE_ERR)"; return 1; }
  return 0
}
# leg_cm_stalelock <driver> — the ledger lock cannot outlive its holder: a pre-created lock whose stamped pid is
# not running, and an unstamped one over a minute old, are broken, so the 3rd FAIL still writes ONE escalated
# record (then session) and no lock is left; a LIVE holder's fresh lock is never broken (the escalation waits,
# the report line is still appended, the holder's lock survives)
leg_cm_stalelock() {
  local drv="$1" hk='{"coordinator_model":"claude-haiku-5-5"}' lk dead kind
  bash -c 'exit 0' & dead=$!; wait "$dead" 2>/dev/null
  for kind in deadpid aged live; do
    new_scratch "$FIX/escalated-park" || { LEG_MSG="$kind: scratch not built"; return 1; }
    printf '%s\n' "$hk" > "$CASE_ROOT/.supervisor/config.json"
    cm_lines false 2 > "$CASE_ROOT/$CM_LEDGER_REL"
    lk="$CASE_ROOT/$CM_LEDGER_REL.lock"; mkdir "$lk" || { LEG_MSG="$kind: lock not pre-created"; return 1; }
    case "$kind" in
      deadpid) printf '%s\n' "$dead-1" > "$lk/owner" ;;
      aged) touch -t 202001010000 "$lk" ;;
      live) printf '%s\n' "$$-1" > "$lk/owner" ;;
    esac
    printf '%s\n' "call: --result 'not json'" 'expect-exit: 2' "$ESC_CALL" 'expect: park' > "$CASE_DIR/cm.results"
    drive "$FIX/escalated-park" "$drv" "$CASE_DIR/cm.results"
    if [ "$kind" = live ]; then
      [ -z "$DRIVE_ERR" ] && ! grep -q '"escalated"' < <(cm_ledger) && [ "$(cm_n)" = 4 ] && [ "$(cat "$lk/owner" 2>/dev/null)" = "$$-1" ] \
        || { LEG_MSG="live holder: ledger $(cm_ledger | tr '\n' ' '), lock owner '$(cat "$lk/owner" 2>/dev/null)' ($DRIVE_ERR)"; return 1; }
      rm -rf "$lk"
    else
      [ -z "$DRIVE_ERR" ] && [ "$(cm_ledger | grep -c '"escalated"' | tr -d ' ')" = 1 ] && [ "$(cm_model)" = session ] && [ ! -e "$lk" ] \
        || { LEG_MSG="$kind stale lock: model '$(cm_model)', lock $( [ -e "$lk" ] && echo left || echo gone ), ledger $(cm_ledger | tr '\n' ' ') ($DRIVE_ERR)"; return 1; }
    fi
  done
  return 0
}
# leg_cm_replay <driver> — a byte-identical replayed report, a no-result re-print and a no-result --start pick
# append nothing
leg_cm_replay() {
  local drv="$1" l1
  cm_run "$drv" escalated-park - - "$ESC_CALL"$'\nexpect: park'
  [ -z "$DRIVE_ERR" ] && [ "$(cm_n)" = 1 ] || { LEG_MSG="first report: $(cm_n) ledger line(s) ($DRIVE_ERR)"; return 1; }
  l1="$(cm_ledger)"
  printf '%s\n' "$ESC_CALL" 'expect: park' 'call:' 'expect: park' > "$CASE_DIR/cm.results"
  drive "$FIX/escalated-park" "$drv" "$CASE_DIR/cm.results"
  [ -z "$DRIVE_ERR" ] && [ "$(cm_ledger)" = "$l1" ] || { LEG_MSG="replay / re-print appended: $(cm_ledger | tr '\n' ' ') ($DRIVE_ERR)"; return 1; }
  : > "$CASE_DIR/seams.none"
  in_case "$drv" "$CASE_DIR/seams.none" bash "$drv" "$CASE_RF" --start pick --session-id cm-replay >/dev/null 2>&1
  [ "$(cm_ledger)" = "$l1" ] || { LEG_MSG="a no-result --start pick appended: $(cm_ledger | tr '\n' ' ')"; return 1; }
  return 0
}

# build_mutant <name> <anchor> <replacement|-append:<line>> — a driver copy beside symlinks to every other
# scripts/ entry; prints its path; gated: anchor once, non-empty, differs, bash -n
build_mutant() {
  local name="$1" anchor="$2" repl="$3" d c
  # a fresh dir every time: re-linking into a reused one makes `ln -s` follow the old directory
  # symlinks and write self-links into the real scripts/ tree (two mutants sharing a name did)
  d="$WORK/mut-$name"; rm -rf "$d"; mkdir -p "$d"
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
echo "== test-automate-next-step.sh — driver: $DRIVER — $PG_LABEL"
bash -n "$DRIVER" && ok "driver passes bash -n" || no "driver fails bash -n"

# ---- B helpers, hoisted from the B section (02-branches) because 06-running-system calls in_order too ----
# inline_run <case> <results text> — a fresh scratch of <case>, driven by the given directives
inline_run() { new_scratch "$FIX/$1" || { DRIVE_ERR="scratch not built"; return 1; }; printf '%s\n' "$2" > "$CASE_DIR/inline.results"; drive "$FIX/$1" "$DRIVER" "$CASE_DIR/inline.results"; }
in_order() { # <file> <fixed string>… — each string on a later line than the previous one
  local f="$1" last=0 n s; shift
  for s in "$@"; do n="$(grep -nF -- "$s" "$f" | head -n 1 | cut -d: -f1)"; [ -n "$n" ] && [ "$n" -gt "$last" ] || return 1; last="$n"; done
}
# ns_cm_all_check — every instruction the legs above printed (spawn / ask / park / done) carries a listed
# coordinator_model. Moved verbatim from the CM section: the loader runs it once per group, after the
# group's parts 01–07 and before any 08+ part, which is exactly where it ran in the one-process suite.
ns_cm_all_check() {
# every instruction leg G printed (spawn / ask / park / done, 41 cases) carries a listed coordinator_model
cm_all="$(cat "$WORK"/case.*/call*.out 2>/dev/null | grep '^{' || true)"
cm_all_n="$(printf '%s\n' "$cm_all" | grep -c '^{' | tr -d ' ')"
cm_all_bad="$(printf '%s\n' "$cm_all" | grep '^{' | jq -r '.coordinator_model // "ABSENT"' 2>/dev/null | grep -vxE 'session|claude-haiku-5-5|claude-sonnet-5-5' | head -n 3 | tr '\n' ' ')"
[ "$cm_all_n" -gt 0 ] && [ -z "$cm_all_bad" ] && ok "CM: all $cm_all_n instruction(s) the legs above printed carry a listed coordinator_model" \
  || no "CM: instructions without a listed coordinator_model: ${cm_all_bad:-none of $cm_all_n}"
}

# ---- legs: test-automate-next-step.d/<part>.sh ----------------------------------------------------
# The sections moved verbatim, in base order, into test-automate-next-step.d/; each selected part is
# sourced BY NAME (never a glob) at top level, so it shares this file's setup, helpers and counters, and a
# missing or unreadable part aborts the suite (exit 1, the part named). NS_CASES applies to 01 (leg G).
TNS_D="$HERE/test-automate-next-step.d"
TNS_DONE=" "; TNS_CM_CHECKED=0; TNS_BEFORE_CM=0
tns_part() {
  [ -f "$TNS_D/$1.sh" ] && [ -r "$TNS_D/$1.sh" ] || { echo "FAIL: missing test part: test-automate-next-step.d/$1.sh"; exit 1; }
  TNS_DONE="$TNS_DONE$1 "
  case "$1" in
    0[1-7]-*) TNS_BEFORE_CM=1 ;;
    *) if [ "$TNS_BEFORE_CM" = 1 ] && [ "$TNS_CM_CHECKED" = 0 ]; then TNS_CM_CHECKED=1; ns_cm_all_check; fi ;;
  esac
}
pg_want 01-golden-idem-gates  && tns_part 01-golden-idem-gates  && . "$TNS_D/01-golden-idem-gates.sh"
pg_want 02-branches           && tns_part 02-branches           && . "$TNS_D/02-branches.sh"
pg_want 03-run-drain          && tns_part 03-run-drain          && . "$TNS_D/03-run-drain.sh"
pg_want 04-pick-resume        && tns_part 04-pick-resume        && . "$TNS_D/04-pick-resume.sh"
pg_want 05-fresh-phases       && tns_part 05-fresh-phases       && . "$TNS_D/05-fresh-phases.sh"
pg_want 06-running-system     && tns_part 06-running-system     && . "$TNS_D/06-running-system.sh"
pg_want 07-doc-mirror         && tns_part 07-doc-mirror         && . "$TNS_D/07-doc-mirror.sh"
pg_want 08-coordinator-model  && tns_part 08-coordinator-model  && . "$TNS_D/08-coordinator-model.sh"
pg_want 09-mutants-tail       && tns_part 09-mutants-tail       && . "$TNS_D/09-mutants-tail.sh"
pg_want 10-mutants-pick-fresh && tns_part 10-mutants-pick-fresh && . "$TNS_D/10-mutants-pick-fresh.sh"
pg_want 11-mutants-cm         && tns_part 11-mutants-cm         && . "$TNS_D/11-mutants-cm.sh"
pg_want 12-dismissed-batch    && tns_part 12-dismissed-batch    && . "$TNS_D/12-dismissed-batch.sh"
pg_want 13-merge-parked       && tns_part 13-merge-parked       && . "$TNS_D/13-merge-parked.sh"
if [ "$TNS_BEFORE_CM" = 1 ] && [ "$TNS_CM_CHECKED" = 0 ]; then TNS_CM_CHECKED=1; ns_cm_all_check; fi
[ "$TNS_DONE" = "$PG_SEL" ] || no "parts sourced ($TNS_DONE) differ from the parts selected ($PG_SEL): a TNS_PARTS entry has no source line"
echo "PASS: $pass FAIL: $fail ($PG_LABEL)"
[ "$fail" -eq 0 ]
