# 40 — Lane defects seen in wave W2: deferred-question exits close the run, `-dep` summary miss, readiness truncation, null session ids

## Status: pending

## Source
Observed while running wave W2 (coordinator run `automate-2026-10-10-194230`, wave PR #465 → v15.128.0, 2026-10-10).
Owner asked for these to be filed as one follow-up after the wave closed, not fixed inside pa/21. Every defect below was
read in the code or the lane's salvaged logs (`<primary>-lanes/automate-2026-10-10-194230/salvage/L1-removed-*/supervisor/logs/`); none is inferred.

## Depends on
none

## Touches
loomwright/scripts/close-stranded-run.sh
loomwright/scripts/test-close-stranded-run.sh
loomwright/scripts/result_block_parser.py
loomwright/scripts/test-result-validators.sh
loomwright/scripts/automate-lanes.sh
loomwright/scripts/test-automate-lanes.sh
loomwright/scripts/automate-trail.sh
loomwright/scripts/test-automate-trail.sh
changelog.d/w2-lane-defects.md
loomwright/scripts/test-build-floor.sh
loomwright/docs/HOOKS.md

## Goal
A lane that exits to defer a question and is resumed keeps writing to its own run log, a dependency worker's summary is
found on the first try, a lane's metadata push is never blocked by text the engine itself truncated, and the local CI
suite stays green on a checkout whose logs carry `item_timing` events.

## Defects

### D1 — a lane's deferred-question exit is treated as a stranded session (MEDIUM, root cause of the forced `--skip-children-check`)
- **Mechanism.** A headless lane defers `AskUserQuestion` by exiting (`stop_reason: tool_deferred`). That exit fires the
  `SessionEnd` hook `close-stranded-run.sh`, which writes `session_end status: failed, reason:
  session_ended_without_completion` into the run log and leaves `state.md` off `running`. `lane-answer` then resumes the
  SAME session, but `emit-lifecycle.sh`'s plugin-session join adopts the run id only while `state.md` reads
  `running|checkpoint`, so every later lifecycle row goes to `<cc_session_id>.jsonl` instead of the run log `state.md` names.
- **Evidence (L1, pa/21).** The run log `auto-2026-10-10-194843.jsonl` holds 5 lines, ending
  `14:38:30Z agent_lifecycle waiting (ask_user)` + `session_end failed session_ended_without_completion`. The session log
  `c3bdba95-….jsonl` holds 149 `agent_lifecycle` rows from 14:14 to 16:57. FINALIZE point 5 read the run log, found
  child `a7a5ec2ce29921fe4` without a terminal row, and the owner had to answer `--skip-children-check`.
- **Size: medium.** The fix is a decision in `close-stranded-run.sh` (recognise a deferred exit, e.g. a pending lane inbox
  question / `tool_deferred`, and do not close the run) or a re-open on resume. Either needs a test for: deferred exit
  ⇒ run stays `running`; a genuine stranding ⇒ still closed (the July fan-in this hook exists for must not return).
- Applies to every lane question, so every multi-question lane hits it.

### D2 — `-dep` dependency worktrees miss the worker-summary lookup (LOW)
- `result_block_parser.py` `worker_summary_file_evidence` tier 3 globs `../*{task_id}/.worker-summary.md`. A dependent
  subtask runs in `../<repo>-<sub>-dep` (`agents/execute-manager.md`, `skills/async-orchestration/SKILL.md`), which the
  glob cannot match. L1's two dependent workers each had one rejected stop before tier 5 accepted a retry.
- **Size: small.** Also match `../*{task_id}-dep/`; one fixture per form.

### D3 — `lane-readiness` truncates a Progress line mid-URL, which then blocks the lane's metadata push (MEDIUM)
- `automate-lanes.sh` `lanes_readiness` builds the children-settled line with `cut -c1-160`. On L2 it cut
  `…/vikashruhilgit/loomwright/pull/460` to `…/vikashruhilgit/loomwrig`; meta-sync's `forge_slug` scrub (correctly, fail
  closed) refuses the non-allowlisted slug, so `lane-convert-ready` exits 2 and `lane-remove` refuses the lane.
- `lane-status --refresh-readiness` cannot repair it: it rewrites only lanes reading `ready_for_release|awaiting_merge`,
  and after the post-merge re-run the lane reads `done`/`awaiting_go`.
- W2 cleared it with an owner-approved one-line hand repair of the advisory file (recorded in the coordinator run file).
- **Size: small.** Truncate at a word/URL boundary (or not at all) and add an ellipsis marker the scrub ignores; test a
  line whose cut point falls inside a forge URL. Decide whether `--refresh-readiness` should cover `done` lanes.

### D4 — `item_timing` writes `"cc_session_id": null`, and `test-build-floor.sh`'s recount counts it (LOW, local-only CI red)
- The `item_timing` event `closeout` appends (the `phase-timing.sh --run` record) carries `"cc_session_id": null`. `build-floor.sh`
  counts only non-empty string ids; `test-build-floor.sh`'s "independent recount" uses `select(has("cc_session_id"))`
  and counts the `null`, so on any checkout whose gitignored logs hold such a line the suite fails
  (`real sessions == 425, independent recount says 426` on this machine, 2026-10-10). GitHub CI has no logs and stays green.
- **Size: small.** Omit the key when there is no id where `closeout` (`automate-trail.sh`) appends the line to the
  session log — `phase-timing.sh`'s own stdout record keeps `null` for a missing value by its contract — AND make the
  recount use the builder's predicate (non-empty string) so the test checks the contract rather than its own looser reading.

### D5 — duplicated "done" regex in `automate-lanes.sh` (nit, from the #465 review)
- `lanes_convert_ready` inlines `^## Status:[[:space:]]*done([^A-Za-z0-9_]|$)`, byte-identical to `_lanes_rf_done()`.
  Call the helper.

## Acceptance criteria
1. A lane that defers a question and is resumed writes its later lifecycle rows to the run log `state.md` names, and
   FINALIZE point 5 reads every child settled without `--skip-children-check` (D1). A session that genuinely ends
   unfinished is still closed `failed`.
2. A `-dep` worker's summary is accepted on its first stop (D2).
3. No readiness line can end inside a URL; a lane whose Progress carries a long PR line pushes its metadata cleanly (D3).
4. `test-build-floor.sh` passes on a logs dir containing an `item_timing` line without a session id, and new
   `item_timing` lines carry no `null` `cc_session_id` (D4).
5. `lanes_convert_ready` uses `_lanes_rf_done` (D5).

## Validation (must pass before merge)
- `bash scripts/ci-local.sh` green, on this machine (whose logs reproduce D4).
- D1 reproduced first as a failing test (deferred exit ⇒ run closed), then green.
- Running system: one `--parallel 2` wave with at least one lane question reaches FINALIZE without the children-check skip.
  If that cannot run before merge, list it under "Not verified" with the reason.

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-11T02:15:40Z
- **Brief:** none — implemented directly at the owner's request (no /automate run)
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/466
- **Released:** v15.128.1 (https://github.com/vikashruhilgit/loomwright/pull/467)
