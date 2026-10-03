# 03 — Branch mode in the engine (code only, default OFF)

## Depends on
02

## Touches
loomwright/scripts/setup-memory.sh
loomwright/scripts/test-setup-memory.sh
loomwright/scripts/automate-trail.sh
loomwright/scripts/test-automate-trail.sh
loomwright/scripts/automate-helpers.sh
loomwright/scripts/session-resume.sh
loomwright/scripts/test-automate-dismissed.sh
loomwright/scripts/test-context-digest.sh
loomwright/scripts/test-harvest-conventions.sh
loomwright/scripts/fixtures/
loomwright/skills/automate-loop/SKILL.md
loomwright/skills/SKILLS_INDEX.md
loomwright/commands/setup.md
loomwright/commands/automate.md
loomwright/docs/RESULT_SCHEMAS.md
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/docs/PITFALLS.md

## Problem
With item 02's script in place the engine still commits run history to `main` through a trail PR. The switch has
two dangers, both measured:
- **Silent amnesia.** With the metadata absent every reader exits 0 with EMPTY output. `resume-glob` returning
  nothing means `/automate` would not see a paused run with an open PR and would start a new one.
- **The migration cannot ride this PR.** Sessions run the INSTALLED plugin, not the working tree. If this PR also
  untracked the files, the old engine's `trail-pr` (which drops any candidate `git check-ignore` reports ignored)
  would close out this very item by committing nothing anywhere.

## Goal
The engine supports a branch mode that a repo opts into. With the mode OFF — the default, and this repo's state
until operator item M1 — behaviour is unchanged. This PR changes NO tracked run-history file and NO gitignore line
of this repo.

## Scope
1. **Mode switch in `/setup memory`.** `setup-memory.sh` gains a branch mode: the gitignore block is written
   WITHOUT the run-history re-includes, and the mode + branch name are recorded as a comment line INSIDE the
   managed block (tracked, so a fresh clone can read it). A plain `apply` must PRESERVE the recorded mode (today's
   `apply` rewrites the block — without this it would silently re-include run history). `remove` reverts it.
   `setup-memory.sh` keeps its header invariant: it never runs `git add` / `git rm` / `git commit` — the migration
   is NOT a sub-step of it (M1).
2. **One reader for the mode:** `meta-sync.sh mode` (or a sourced helper) prints `off` / `on <branch>` from the
   tracked block. Every caller below uses it; nothing else parses the block.
3. **Pull BEFORE the first read of run history.** When mode is on, `meta-sync.sh pull` runs at `/automate` entry —
   before `resume-glob`, before any run file is created, before the run-lock acquire at PICK (bare `/automate`,
   `--resume`, and new runs all call `resume-glob` first). Outcomes:
   - non-zero with NO run file yet ⇒ **abort** with the message, create nothing (parking would create a run file
     that makes the next resume ambiguous);
   - non-zero on a resume of an existing run ⇒ park, new `pause_reason: meta_unreachable` (add it to
     `RESULT_SCHEMAS.md` §AUTOMATE_RUN and the skill's `pause_reason` lists);
   - `conflict` ⇒ same handling, naming the path.
4. **SessionStart: no network.** `session-resume.sh` does NOT pull (a fetch on every start/compact, no `timeout`
   on macOS, writing into a live checkout). It runs `meta-sync.sh status` only when mode is on and, on
   `never_synced`, appends one line to its existing output: "run history is on branch `<name>` and has not been
   pulled — run `meta-sync.sh pull`". Always exit 0.
5. **Push replaces the trail PR — keeping its filters.** With mode on, `trail-pr`'s three triggers (inside
   `closeout` after merge evidence; a skipped/abandoned check-off; run end) call
   `meta-sync.sh push --paths-from <list>` where `<list>` is exactly what `_trail_candidates` + the evidence gate
   produce today (explicit paths, done claims only for MERGED work, only this run's ledger lines). The
   dropped-draft retraction becomes a real deletion (item 02 propagates it) — keep the behaviour, drop only the PR
   mechanics (`trail-unstage`, the `.trail-staged` record, the trail worktree) on the mode-on path. Mode off ⇒ the
   legacy path, byte-unchanged.
6. **Push failures are loud.** `trail-pr` stays advisory (always exit 0), but a failed or scrub-refused push
   appends a `## Progress` line `meta-push FAILED: <reason>`, fires the notify, and sets a marker that (a) the next
   PICK reports before picking and (b) item 05's `lane-remove` refuses on. A stamp that exists only locally makes
   other checkouts re-queue merged work — silence is not acceptable here.
7. **CI coverage must not evaporate when the corpus leaves `main`.** Tests that read the tracked corpus and skip
   silently without it (reported: `test-context-digest.sh`, `test-harvest-conventions.sh`) get a frozen fixture
   corpus under `loomwright/scripts/fixtures/`; `test-automate-dismissed.sh` compares `proposed/README.md` against
   a fixture, not the live file. Record the `SKIP` count before and after.
8. **Docs:** `automate-loop/SKILL.md` gets a NEW flag-gated §"Branch mode" plus one-line pointers from §4 and §6;
   existing sections are otherwise untouched. `commands/setup.md`, `commands/automate.md`,
   `ARCHITECTURE_CONTRACTS.md`, `PITFALLS.md`. A SKILL.md edit forces `SKILLS_INDEX.md` — same commit.
9. **Tests:** mode on + unreachable remote + no run file ⇒ abort, nothing created; mode on + paused run on the
   branch ⇒ `resume-glob` lists it after the pull; closeout with mode on opens NO PR, pushes only evidence-gated
   paths, and a dropped draft is gone from the branch; push failure ⇒ `## Progress` line + marker; plain `apply`
   preserves the mode; mode off ⇒ existing trail tests pass unchanged. **Mutation controls:** making `pull` exit 0
   on fetch failure must fail the abort test; removing the evidence gate from the push list must fail a test that
   asserts an unmerged item's stamp is NOT on the branch.

## Non-goals
Migrating this repo (M1). Moving lessons, agent memory or `.agent/`. Changing default behaviour for any project
that has not opted in. Parallel lanes.

## Acceptance criteria
- `git diff --stat origin/main` for this PR shows no change to `.gitignore` and no change under `.supervisor/`
  except this requirement's own stamp.
- With mode off, `test-automate-trail.sh`, `test-automate-helpers.sh` and `test-setup-memory.sh` pass with no edit
  to their legacy-path assertions.
- With mode on in a scratch clone, one closeout pushes to the branch and `gh pr list` (stubbed) shows no trail PR.
- `SKIP` count after ≤ `SKIP` count before.
- Full test loop + root checks green.

## Validation (must pass before merge)
1. **Baseline:** full loop on base and branch; `<passed>/<total>` and `SKIP` counts for both.
2. **Unchanged path (mode OFF):** the three suites above with zero edits to legacy assertions;
   `setup-memory.sh` writes a gitignore block byte-identical to today's; one real single-item `/automate` on this
   repo AFTER merge + reinstall still opens its trail PR exactly as before (this repo is still mode-off until M1).
3. **Running system (mode ON, scratch clone + local bare remote):** paste the abort on an unreachable remote
   (`ls .supervisor/automate` unchanged), `resume-glob` listing a paused run after the pull, and the branch
   contents after a closeout.
4. **A failure this must catch:** the two mutation controls in Scope 9, shown failing.
5. **Rollback:** `git revert`. No repo is in branch mode yet, so nothing is stranded.

## Verified premises (re-check before starting)
- Reader behaviour on absent metadata and the 4 failing stripped tests (00-overview §Evidence).
- `automate-loop/SKILL.md` §6 "Trail PR after merge and at run end": exactly three triggers; trail failures are
  advisory and the loop ignores the exit status; an undecided draft can ride a trail commit, hence the retraction.
- `automate-trail.sh` `_trail_candidates` drops gitignored candidates ("Drop gitignored candidates" comment) and
  has the evidence gate for done stamps.
- `setup-memory.sh` header invariants ("never runs `git add`…", exit 0 in normal paths) — red-team report; read
  the header before editing.
- Sessions run the installed plugin version, not the working tree (project memory: desktop vs CLI install
  location; installed version lagged the repo on 2026-10-01).

## Status: pending

<!-- loomwright:requirement-closeout -->
## Status: done_with_escalation
- **Completed:** 2026-10-02T11:25:44Z
- **Brief:** .supervisor/jobs/done/2026-10-02-parallel-automate-03-branch-mode-engine.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/347
- **Heal:** max_iterations_reached — 2 remaining
