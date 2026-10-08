# 23 — pa/05 Validation 4/5 fixes A: the lane-coordinator bugs that block the release

## Status: pending

## Depends on
05-lane-coordinator.md

## Touches
loomwright/scripts/automate-lanes.sh
loomwright/scripts/test-automate-lanes.sh
loomwright/scripts/run-lock.sh
loomwright/scripts/test-run-lock.sh
loomwright/skills/automate-loop/SKILL.md
changelog.d/parallel-automate-23-pa05-validation-fixes-a.md

## Problem
pa/05 (PR #426, head `8226dfe`) passed its Validation 4/5 on 2026-10-08: a real `/automate --parallel 2` on two
throwaway items (run `automate-2026-10-08-033739`, PRs #428/#429 closed unmerged). The run found seven defects in the
new lane code, listed below. The owner decided to merge #426 as validated and to hold its release bump until this item
and item 24 merge. No real `--parallel` run happens before then. Full evidence is in #426's description, under
"Known issues found by Validation 4/5".

- **F1 — the wave-start snapshot cannot be taken in the documented order.** §14 "The per-wave loop" step 5 runs
  `lane-status <parent_runfile> --leaks --snapshot` before step 6's `lane-create`. `lanes_status` resolves the
  table with `_lanes_table_for` first. With no `<run_id>.lanes` yet, it prints `lane-status: no lane table (…) — no
  lanes` and returns 0 before reaching `lanes_leaks`, so no snapshot is written and nothing reports the miss.
  The run worked around it by sourcing the script and calling `lanes_leaks <primary> <run_id> 1`.
- **F2 — a held answer is lost.** `lane-answer` runs authority and admission before it records the answer (by
  design: "a HELD resume leaves nothing half-written"). When admission says `load busy` (macOS memory pressure at
  level 2, plus another launch less than `LOOMWRIGHT_LANE_RECHECK_S` = 60 s earlier), it prints `lane-launch: HELD —
  <lane> — load busy` (exit 4) and stores nothing. The owner's answer is gone. Nothing retries it, and the next poll
  shows the same question again. Seen once: L2's "Save and exit", which was re-sent by hand 55 s later.
- **F4 — a died lane cannot resume for up to 30 minutes.** `lane-launch --resume-run <lane run_id>` starts a NEW
  `claude -p` session (L2: `89fd9878` died, `0d177970` resumed). The lane's `.supervisor/run.lock` still records the
  dead session: pid dead, age under `LOCK_TTL_SECONDS` = 1800. `run-lock.sh acquire` is re-entrant only for the
  same `--session-id`, and reclaims only when the pid is dead AND the age is ≥ 1800 s. So the resumed lane waits.
  L2 waited about 20 minutes, then took the lock over normally. §14 names `--resume-run` as the recovery for `died`.
  In practice, any lane that dies within 30 minutes of its PICK stalls. (A resume after an ANSWER keeps the session
  id through `--resume <sid>` and is re-entrant, so it does not stall.)
- **F5 — the merge-readiness report is never written for items with no named repro.** At the end of
  `lanes_readiness`, the report group's last line is `echo "- $eline"; [ -n "$erows" ] && printf '%s' "$erows"`.
  With `erows` empty (the Validation names no headline repro), that `&&` list exits 1, so the whole `{ … } >
  "$out.tmp.$$"` group exits 1. Then `&& mv` is skipped, the `||` branch prints `report not written (unwritable)`,
  and the temp file is removed. This is deterministic, and both lanes hit it. Both lanes reproduced it in a scratch
  directory.
- **F9 — the leak check can never read `none` after a removal.** `lane-remove` salvages into
  `<primary>-lanes/<run_id>/salvage/`, and the lane stream logs (`L<n>.stream.log`, `L<n>.stdin.json`) also live in
  `<primary>-lanes/<run_id>/`. `_lanes_leak_sections` lists `ls -1 <primary>-lanes`, so the run's own directory always
  reads as `lanes-dir: changed + <run_id>`. Validation 5 cannot pass by its own measure, and item 21's planned
  "remove the then-empty run directory" would be refused, because the directory is never empty.
- **F10 — `lane-remove --abandon` breaks the coordinator's own trail push.** It appends `lane abandoned: L<n> (…) —
  state ${state:-unknown}; salvaged to <absolute path>` to the PARENT run file. `trail-pr <parent> --reason done`
  (branch mode) then fails the scrub: `trail-pr: meta-push FAILED — scrub .supervisor/automate/<run_id>.md:
  home_path`, and the run file stays local. That line's `state` also prints the table's `launched` instead of the
  lane's real state (`gone`).
- **F11 — after the wave-end conversion, `lane-remove` still refuses, and the obvious fix pushes false claims.**
  `lane-convert-ready` pushes only the lane run file. `lane-remove` then refuses with `metadata not pushed (local_ahead
  5)` / `(… 7)`, because the lane also holds its briefs, result sidecars, the `results.jsonl` line, dismissed drafts
  and the requirement file. §14's wave end names no step that pushes them. The run used a whole-lane `meta-sync.sh
  push --root <lane>`. **That bypasses `trail-pr`'s evidence gate** (§13 honest limit 1). It pushed Phase 4.5's
  `## Status: done` closeout block for both UNMERGED items, and their briefs under `jobs/done/`, to
  `loomwright-meta`. This had to be corrected by hand (meta `b8697aa`: ABANDONED stamps, briefs moved to
  `jobs/failed/`).

## Goal
A `--parallel` wave runs §14 exactly as written, from snapshot to removal, with no hand steps. A died lane resumes
at once. A held answer is never lost. The leak check reads `none` after a clean wave. Nothing the lanes or the
coordinator push makes a done claim for unmerged work.

## Scope
1. **F1:** make the step-5 snapshot work before any lane exists. Either `lane-status <rf> --leaks --snapshot`
   derives the parent run id and primary from `<rf>` when no table exists (preferred, since the step order is right),
   or the snapshot moves into the first `lane-create`. Never a silent `no lanes`: a snapshot request that writes
   nothing exits non-zero with the reason.
2. **F2:** a HELD `lane-answer` keeps the owner's answer. One possible design: record it in a coordinator-side pending
   file in the primary's `.supervisor/automate/`. The next poll, or `lane-status`, then delivers it through the same
   `lane-answer` path once admission allows. Answer validation (labels only) happens before the hold, so a held answer
   is already a valid one. `lane-status` shows the lane as `answer_pending` (or similar) instead of re-showing the
   question. The no-write-into-the-lane rule is unchanged.
3. **F4:** a `--resume-run` after `died` / `stalled` / `lost_to_reset` does not wait on its own dead session's lock.
   Preferred: resume the lane's LAST session id (the table already holds it), so the lock's re-entrant path applies,
   falling back to a fresh session only when that session cannot be resumed. If the fallback needs the lock released,
   the lane's own engine does it on entry when the recorded session is this lane's previous session and its pid is
   dead. The coordinator never writes the lane's lock. `--force-unlock` stays human-only. Record which path was taken
   in the lane's `## Progress`.
4. **F5:** fix the report group so an empty `erows` (and empty `vrows` / `crows` / `frows`) cannot fail it. For
   example, end it with `[ -z "$erows" ] || printf …` or `if …; fi`. Distinguish a real write failure from a non-zero
   status inside the body.
5. **F9:** after a clean wave, `lane-status --leaks` reads `none`, and salvage and the stream logs are still kept and
   findable. Either keep them outside `<primary>-lanes/` (for example under the primary's
   `.supervisor/automate/<run_id>.salvage/`), or have the leak check exclude this run's own salvage and log files by
   exact name, never by a broad glob. Item 21's "remove the then-empty run directory" must work with what you choose;
   note the choice in this item's PR.
6. **F10:** no lane subcommand writes an absolute path into any run file. Paths in run files are repo-relative or
   use the `<primary>-lanes/…` form. The `lane abandoned` line reports the lane's real state, from the same reader
   `lane-status` uses.
7. **F11:** the wave end leaves every lane removable without hand steps, and pushes only evidence-gated paths. Extend
   `lane-convert-ready`, or add a named wave-end step in §14, so the lane's remaining metadata goes through
   `trail-pr`'s evidence-gated candidate list (or the same gate). A done stamp or a `jobs/done/` brief rides only
   when its PR reads `MERGED`. A lane whose PR closed unmerged gets the `done_with_escalation — ABANDONED (<row>)`
   stamp, the shape `reconcile-status` writes. §14 says which step does it, and §13's honest limit 1 names this path.

## Acceptance criteria
- Each of F1, F2, F4, F5, F9, F10, F11 has a hermetic test in `test-automate-lanes.sh` (or `test-run-lock.sh` for a
  lock change) that fails on `8226dfe` and passes on the branch.
- The F11 test asserts that a lane whose item carries an unmerged done stamp pushes NO done claim.
- The F10 test asserts that no line containing `$HOME` is written into the parent run file by any lane subcommand.
- `lane-status --leaks` after the hermetic full-wave fixture reads `leaks: none`.
- §14 wording matches the code for steps 5 and 6 and the wave end. No other SKILL section changes.
- The sequential path is unchanged: `pick-guard` prints `ok` with no `*.lanes`, and the no-flag tests are untouched.

## Validation (must pass before merge)
1. `bash scripts/ci-local.sh` is green.
2. Each new test, shown failing against `8226dfe` and passing on the branch (paste both).
3. **Running system:** a `--parallel 2` run on two NEW throwaway items, on the owner's typed command. Kill one lane
   once and resume it. The resume must not wait on the lock. Close both PRs unmerged, then run the §14 wave end with
   no hand steps. Paste `lane-status --leaks` reading `none`, the trail push succeeding, and `git show
   origin/loomwright-meta:<item>` showing the ABANDONED stamp and no done claim. Both throwaway PRs are closed
   unmerged.
4. Rollback: `git revert`.

## Non-goals
F3, F6, F8 (item 24) and F7 (`automate-followups/37`). Item 21's fleet closeout and policy answers. Any change to
the sequential loop.

## Verified premises (re-check before starting)
- Every quoted line above was read in `loomwright/scripts/automate-lanes.sh` / `run-lock.sh` at `8226dfe` on
  2026-10-08. Re-read them at the merged head before changing anything.
- Evidence: the coordinator transcript of session 33778c29 and the run file
  `.supervisor/automate/automate-2026-10-08-033739.md`.

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-08T08:54:18Z
- **Brief:** .supervisor/jobs/done/2026-10-08-pa23-lane-validation-fixes.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/434
