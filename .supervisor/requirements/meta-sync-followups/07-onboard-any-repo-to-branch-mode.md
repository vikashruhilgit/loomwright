# 07 — Onboard any repo to branch mode: a guided, human-gated migration instead of a this-repo runbook

## Status: pending

## Problem
Branch mode (run history on a metadata branch, not on `main`) is what lets parallel lanes write records without
extra PRs. The plugin ships the parts but not the move:
- `/setup memory` with branch mode writes the `.gitignore` mode block and nothing else. `setup-memory.sh` keeps its
  header invariant and never runs `git add` / `git rm` / `git commit`.
- `meta-sync.sh init | push | pull | status` work on any repo.
- The migration itself (scrub, create the branch, protect it, seed it, check that `main` and the branch hold
  identical files, untrack on a PR, re-check at merge, pull in every checkout) exists only as
  `parallel-automate/operator-run/M1-migrate-this-repo.md`, an operator runbook written for THIS repo. It ran on
  2026-10-02 → 03 and took about half a day.

M1's run record lists what a second repo would hit again: `push --dry-run` did not exist, so a hand-made
scratch-clone rehearsal stood in for it. The runbook's own Rollback recipe loses post-migration edits (the
corrected recipe is in #361's PR body). The untrack PR merged before step 6's re-check ran. Seven scrub hits on
tracked files had to be cleared by a separate PR (#359) first. Nothing in the plugin does these steps for another
repo, so today every new repo would repeat M1 by hand.

## Goal
On any repo, `/setup memory` can take the owner from "default mode" to "branch mode, history on the branch,
untracked on `main`" through one guided flow. It runs as a dry run first, stops at every step only the owner can
take, and refuses to continue past a failed check.

## Scope
1. **Two cases, detected, never assumed.**
   - **Fresh:** no managed path is tracked on `main` (`git ls-files` over the managed set from `meta-sync.sh` is
     empty). Steps: mode block → `init` → protect → done. Nothing to untrack.
   - **History:** managed paths are tracked. The full sequence in Scope 2.
2. **The guided sequence** (one deterministic script, `migrate-branch-mode.sh`, with `plan` (read-only) and per-step
   subcommands; the command owns only the asking):
   a. **Preconditions**, each printed with its result: on the default branch, clean, equal to `origin`; no
      `/automate` run in flight (`resume-glob`, `run-lock.sh status`); no open trail PR; other worktrees clean.
   b. **Scrub dry run** over every file that would be pushed (`meta-sync-followups/04`'s scrub: its
      `push --dry-run` if 04 ships option B, otherwise the scrub alone over the candidate list). Any hit stops the
      flow with the file, line and rule. Nothing is published with a hit.
   c. **Rehearsal** in a scratch clone with a local bare remote (`meta-sync-followups/05` Scope D's harness): init,
      push, check, second-checkout pull, and the corrected rollback drill. Any FAIL stops the flow.
   d. **Create the branch** (`meta-sync.sh init --branch <name>`) only after the owner confirms the branch name.
   e. **Protect it (owner step).** Print the exact ruleset to add (target the branch; block deletion and
      non-fast-forward; no bypass) and the `gh api` command that would create it. Wait for the owner to say it is
      done, then verify it with `gh api …/rulesets` before seeding. Never create or change a ruleset itself.
   f. **Seed** with `meta-sync.sh push`, then the M1 step-4 check against the CURRENT `origin/<default>`: list A
      (tracked managed paths) equals list B (branch tree); every blob matches; no non-`.md`/`results.jsonl` entry
      on the branch. Tracked `.supervisor/` files outside the managed set are listed for an owner decision, never
      dropped silently.
   g. **Untrack on a PR (owner merges).** Write the branch-mode `.gitignore` block, `git rm -r --cached` the
      managed paths on a new branch, open the PR with the A/B counts, the empty diffs and the pre-migration SHA in
      its body. Never merge.
   h. **Merge-time re-check is a precondition, not advice** (M1's lesson): `migrate-branch-mode.sh verify-pr <n>`
      repeats step f against the then-current default branch and pushes anything new first. The PR body tells the
      owner to run it immediately before merging.
   i. **After merge:** in the primary `git pull` then `meta-sync.sh pull`, then confirm the files are back and
      `git status --porcelain` is empty. Print the two commands every other checkout must run.
3. **Rollback** is a subcommand that implements the corrected recipe (re-track the CURRENT files, nothing written
   since the migration is lost), and it is drilled in step c before anything real happens.
4. **Resumable.** Each step records its result in a small state file under `.supervisor/` (gitignored), so a
   flow stopped at the owner steps (e, g) continues from there.
5. **Branch name.** Default `loomwright-meta`, any valid name accepted, and the mode line written by step g is what
   `meta-sync.sh` reads afterwards (`meta-sync-followups/06`).
6. **Tests:** fixtures for both cases on a local bare remote; each precondition failing stops the flow; a planted
   scrub hit stops it before `init`; A ≠ B stops it before the untrack PR; the rollback subcommand keeps a
   post-migration edit. **Mutation controls:** skipping the step-h re-check, and the old M1 rollback order, each
   must fail a test.

## Non-goals
Creating or editing GitHub rulesets or branch protection (printed for the owner, verified after). Merging the
untrack PR. Migrating the learning stores (`meta-sync-followups/05` A–C). Moving a repo back out of branch mode
beyond the rollback in Scope 3.

## Acceptance criteria
- On a scratch repo with tracked history, the flow reaches a ready-to-merge untrack PR with A = B and no blob
  mismatch, and stops at steps e and g for the owner.
- On a fresh repo, the flow ends with the branch created, protected (verified), and the mode line written, with no
  untrack PR.
- `plan` on this repo (already migrated) reports `already in branch mode on loomwright-meta` and changes nothing.

## Validation (must pass before merge)
1. Baseline full loop, `<passed>/<total>` and `SKIP` counts, base and branch.
2. Unchanged path: `/setup memory` without branch mode, and `/setup memory` on this already-migrated repo, write
   nothing new.
3. Running system: the full flow on a second real repo the owner picks (or a throwaway GitHub repo), owner doing
   steps e and g. Paste the A/B counts, the ruleset check, the PR link and the post-merge `git status`.
4. A failure this must catch: the two mutation controls in Scope 6.
5. Rollback: `git revert`.

## Evidence
`parallel-automate/operator-run/M1-migrate-this-repo.md` (steps, Verify, Rollback, run record 2026-10-02 → 03); PRs
#359 (scrub hits cleared first) and #361 (untrack PR, corrected rollback in its body); owner question 2026-10-05:
"did all these also handle setting up the initial shift from main to meta branch on other repos?" Answer: no.

## Depends on
04-scrub-safe-briefs-and-push-rehearsal.md
08-meta-sync-hardening.md

## Touches
loomwright/scripts/migrate-branch-mode.sh
loomwright/scripts/test-migrate-branch-mode.sh
loomwright/scripts/meta-sync-rehearsal.sh
loomwright/scripts/test-meta-sync-rehearsal.sh
.github/workflows/ci.yml
loomwright/docs/vendor-coupling-manifest.json
loomwright/commands/setup.md
loomwright/skills/setup/SKILL.md
loomwright/docs/RESULT_SCHEMAS.md
changelog.d/meta-sync-followups-07-onboard-any-repo-to-branch-mode.md

## Part D — moved 2026-10-06 from `05-carry-the-learning-stores.md` (verbatim; owner decision: fewer, larger items — a run costs ~$17–20 plus 4+ owner questions even for a tiny change)
Scope 2c above names "`meta-sync-followups/05` Scope D's harness": that harness is now this part, so this
item no longer depends on 05. The M2 runbook (D.4) still describes carrying 05's part-B stores; it can be
written here, and M2 itself runs after 05 merges.

#### D. Committed rehearsal harness + M2 runbook (the testing method, made repeatable)
1. A rehearsal script under `loomwright/scripts/` that, given a checkout, builds a scratch clone and a local bare remote and runs the full migration and drill against them. Nothing reaches the real remote. It copies `config.json` (the allowlist) by default and can run without it (`--no-config`). It runs:
   - `init` → `push` → verify: every managed path present, blob-identical, nothing extra, file types as declared;
   - a second checkout: `git pull` removes the copies, `meta-sync pull` restores them byte-identical;
   - the corrected rollback (#361's PR body) after a post-migration edit, add and delete: all kept, `.gitignore` back to the pre-migration content;
   - the twin reader verifying the same contract count after a round trip.

   It prints one PASS/FAIL line per check, exits non-zero on any FAIL, and cleans up after itself.
2. Its self-test proves each check can go red (mutants: a dropped file, a changed blob, the runbook's old rollback order, a contract without provenance).
3. **CI sees run history again (M1 Verify follow-up, owner 2026-10-03).** Since M1, CI's checkout has no
   `.supervisor/jobs/done/`, so `loomwright/sdk-spike/test/digest-lanes.test.sh`'s optional corpus sweep prints
   `SKIP` (before M1 it swept 132 real briefs). Add a CI step that runs `meta-sync.sh pull` before the suite.
   Read-only: CI never pushes, and a failed pull is reported and leaves the suite as today. The PR edits a workflow
   file, so `claude-review` skips itself on it; the owner reviews that PR by hand.
4. Fix M1's Rollback section to the corrected recipe (the runbook's own recipe silently loses post-migration edits — drill evidence 2026-10-03). Write `operator-run/M2-carry-learning-stores.md`, with the same shape as M1: backup → rehearsal (this script) → real push → verify → consent recorded. Pause for the owner at each step.

#### Notes on the touched files (moved with Part D)
- Part D: a new rehearsal script + self-test (proposed names `meta-sync-rehearsal.sh` / `test-meta-sync-rehearsal.sh`); D.3 CI pull step in `.github/workflows/ci.yml`; `vendor-coupling-manifest.json` because the setup-memory scripts carry ratcheted allowances.

#### Acceptance criteria (moved with Part D)
- **D1** The rehearsal script passes on this repo with config and with `--no-config` + the request file. Its self-test shows each check going red under its mutant, including the old rollback order losing a post-migration edit.
- **D3** On `main`'s CI after this lands, the corpus sweep reports `parseBrief threw on …/N` (or its NOTE) instead of `SKIP`, and the self-test count of real skips is back to the pre-M1 one (the Linux-host Darwin cases only).
- **D2** M1's Rollback section is the corrected recipe. M2's runbook names only commands and flags that exist in the shipped scripts' `--help`.
