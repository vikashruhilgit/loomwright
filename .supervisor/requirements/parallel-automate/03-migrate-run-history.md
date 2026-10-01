# 03 — Migrate run history to the metadata branch and retire the trail PR

## Depends on
02

## Touches
`loomwright/scripts/setup-memory.sh`, `loomwright/scripts/test-setup-memory.sh`,
`loomwright/scripts/automate-trail.sh`, `loomwright/scripts/test-automate-trail.sh`,
`loomwright/scripts/automate-helpers.sh` (dispatch rows only), `loomwright/scripts/session-resume.sh`,
`loomwright/hooks/hooks.json`, `loomwright/skills/automate-loop/SKILL.md`, `loomwright/commands/setup.md`,
`loomwright/scripts/test-automate-dismissed.sh`, `loomwright/scripts/test-citation-drift.sh`, `.gitignore`,
the tracked files under `.supervisor/requirements|jobs|automate|postmortem` (untracked on `main`)

## Problem
With item 02's script in place, run history still lives on `main` and the engine still opens a trail PR after every
merge and at run end. The migration has one real danger, measured 2026-10-01: with the metadata absent, the plugin
does not crash — every reader exits 0 with EMPTY output, so a missed pull is indistinguishable from "no history".
`resume-glob` returning nothing means `/automate` would not see a paused run with an open PR and would start a new
one, bypassing the single-open-PR invariant.

## Goal
Run history lives on `loomwright-meta`. A run pulls it at start and refuses to start if it cannot; closeout and run
end push it. No metadata-only PR is ever opened again. Lessons, agent memory and `.agent/rules/` are untouched.

## Scope
1. **Branch mode in `/setup memory`** (opt-in, default unchanged for every other project using the plugin):
   `setup-memory.sh` gains a mode that writes the gitignore block WITHOUT the run-history re-includes
   (`!.supervisor/requirements/`, `!.supervisor/jobs/…`, `!.supervisor/automate/…`, `!.supervisor/postmortem/…`)
   and records the mode + branch name in a TRACKED place a fresh clone can read (inside the managed gitignore block
   as a comment line is acceptable; pick one and pin it in a test). `remove` reverts it.
2. **One-time migration for this repo** (a script or documented `setup-memory.sh` sub-step, idempotent):
   seed `loomwright-meta` from the current tracked run-history tree; then `git rm --cached` those paths on a PR
   branch with the new gitignore block. History stays in `main`'s log. Verify file-for-file that the branch holds
   everything that was untracked BEFORE the PR is opened.
3. **Pull at start, fail CLOSED.**
   - `/automate` PICK and `--resume`: `meta-sync.sh pull` is the first action when branch mode is on; a non-zero
     exit parks the run (new `pause_reason: meta_unreachable`) — it never proceeds on an empty folder.
   - `SessionStart` (`session-resume.sh`): call `pull`, fail SAFE (always exit 0), but on failure print one visible
     `metadata not synced` line instead of silence.
   - Branch mode OFF ⇒ none of this runs; behaviour byte-unchanged.
4. **Push replaces the trail PR.** `trail-pr`'s three triggers (inside `closeout` after merge evidence; a
   skipped/abandoned check-off; run end) call `meta-sync.sh push` when branch mode is on. Keep the evidence gate
   exactly as it is: a done stamp / done brief is pushed only for work `gh` reports MERGED. Delete what the PR
   mechanics needed only for tracked trails — `trail-unstage`, the `.trail-staged` record, the dropped-draft
   retraction — ONLY on the branch-mode path; the legacy path stays intact for projects not in branch mode.
5. **Closeout's "sync main" step** keeps working: with nothing tracked under the run-history paths, the pull can
   no longer be refused over trail files. Prove it with a test rather than assuming it.
6. **Fix what the stripped run broke.** Re-run the stripped-metadata check with ONLY the run-history paths removed
   (memory kept) and fix every failure. Expected from the 2026-10-01 run: `test-automate-dismissed.sh` (compares
   the committed `proposed/README.md`) and `test-citation-drift.sh` (one citation into a moved file).
   `test-committed-twin-scrub.sh` and `test-validate-entry.sh` failed on MEMORY files, which stay — confirm they
   pass, do not assume.
7. **Dead citations.** 63 shipped files cite specific `.supervisor/requirements/…` or `jobs/…` paths in comments.
   They stay as provenance, but state once (CLAUDE.md citation convention paragraph) that such paths resolve on the
   metadata branch. Do not mass-edit them.
8. **Docs:** `automate-loop/SKILL.md` §3/§4/§6 ("Trail PR after merge and at run end", RESUME), `commands/setup.md`,
   `docs/ARCHITECTURE_CONTRACTS.md`, `docs/PITFALLS.md` (retire the pitfalls that only exist for tracked trails).
9. **Tests:** branch mode on ⇒ PICK with an unreachable remote parks `meta_unreachable` and writes nothing else;
   `resume-glob` after a pull lists the paused run; closeout with branch mode on opens NO PR and the stamp is on
   the branch; branch mode off ⇒ existing trail tests pass unchanged. **Mutation control:** making `pull` exit 0
   on fetch failure must fail the PICK test.

## Non-goals
Moving lessons, agent memory or `.agent/`. Changing default behaviour for projects that have not opted into branch
mode. Parallel lanes (item 05). Rewriting `main`'s history to drop the old files.

## Acceptance criteria
- A full single-item `/automate` cycle on this repo completes with exactly ONE PR (the feature PR) and the
  requirement stamp, done brief, run file and ledger line are on `loomwright-meta`.
- `git ls-files .supervisor` on `main` lists only `.supervisor/memory/`.
- A fresh clone + session start has the run history in place, or shows a visible `metadata not synced` line.
- CI green on `main` after the untrack PR; full test loop + root checks green.

## Validation (must pass before merge)
This is the one item that can lose data or make a session silently forget history. Its validation is stricter.
1. **Baseline:** full loop on the base and on the branch; both `<passed>/<total>` lines in the PR body.
2. **Unchanged path (branch mode OFF):** in a scratch clone with branch mode not enabled,
   `test-automate-trail.sh`, `test-automate-helpers.sh` and `test-setup-memory.sh` pass with NO edits to their
   legacy-path assertions, and `setup-memory.sh` writes a gitignore block byte-identical to today's.
3. **No file lost (before the untrack PR is opened):** save `git ls-files .supervisor` minus `.supervisor/memory/`
   from `main` as list A; `git ls-tree -r --name-only origin/loomwright-meta` as list B; `comm -23 A B` must be
   empty, and for every path `git rev-parse main:<p>` equals `git rev-parse origin/loomwright-meta:<p>`. Paste the
   counts and the empty diff in the PR body.
4. **Stripped re-run:** repeat the 2026-10-01 check on the branch — a scratch worktree with ONLY the run-history
   paths removed (memory kept), all self-tests — and paste the result. Target: 0 failures.
5. **Silent-amnesia check (the real danger):** in a scratch clone with branch mode on and the remote made
   unreachable, `/automate` PICK must park `meta_unreachable` and write nothing else; with the remote reachable and
   a paused run on the branch, `automate-helpers.sh resume-glob .supervisor/automate` must list that run after the
   pull. Paste both outputs.
6. **Running system:** after merge, in the primary checkout — a new session shows the run history present
   (`ls .supervisor/requirements | wc -l` matches list A's folder count), `/handoff` and `/insights` produce
   non-empty output, and `git status --porcelain` is empty.
7. **One real item end to end** before this item is checked off: run a single small `/automate` item on this repo
   and confirm exactly ONE PR was opened and the stamp / done brief / run file are on `loomwright-meta`.
8. **Rollback (write it and try it once in a scratch clone):** `git revert` the untrack PR restores the old
   gitignore block; then `meta-sync.sh pull` + `git add` of the run-history paths re-tracks the CURRENT files, so
   nothing written since the migration is lost. The metadata branch is left in place. Keep `main`'s pre-migration
   SHA in the PR body as the known-good point.

## Verified premises (re-check before starting)
- `git ls-files .supervisor | cut -d/ -f2 | sort | uniq -c` at `fdc8a5f`: automate 23, jobs 149, memory 4,
  postmortem 1, requirements 191.
- `.gitignore` block: `.supervisor/*` then re-includes for `memory/`, `requirements/`, `jobs/done|failed/`,
  `automate/*.md`, `postmortem/results.jsonl`, between `/setup memory` sentinels.
- `automate-loop/SKILL.md` §6 "Trail PR after merge and at run end" lists exactly three triggers and states trail
  failures are advisory / fail-SAFE; v15.114.2's CHANGELOG entry explains why the trail runs only after merge.
- Stripped-clone reader behaviour (00-overview §Evidence).
- `.claude/agent-memory` resolution inside a clone or worktree was NOT verified — irrelevant here because agent
  memory stays tracked, but do not extend this item to move it.

## Status: pending
