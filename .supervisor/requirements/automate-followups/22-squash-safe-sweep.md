# 22 — Squash-safe sweep: clean up worktrees and branches the plugin left behind, with closeout's own rule

## Status: pending

## Depends on
none

## Touches
loomwright/scripts/automate-helpers.sh
loomwright/scripts/automate-trail.sh
loomwright/scripts/test-automate-trail.sh
loomwright/skills/automate-loop/SKILL.md
loomwright/commands/automate.md
loomwright/docs/RESULT_SCHEMAS.md
changelog.d/automate-followups-22-squash-safe-sweep.md

## Problem
`closeout` (`automate-trail.sh`) cleans up exactly one PR, the one it was called for. It removes that PR-head
worktree only when it is clean after `worktree-salvage.sh`, and deletes the local head branch only when its tip
equals the PR's `headRefOid` (squash merges make ancestry useless, so `-d` and "0 commits outside main" are never
used). Nothing else in the plugin cleans up, so anything that never went through `closeout` stays forever:
- **PRs merged outside `/automate`** (`/supervisor`, `/review-pr` or a hand session). On 2026-10-03 the primary
  carried 5 worktrees whose PRs (#362, #363, #364, #368, and one detached checkout already on `main`) were merged
  and clean. The owner removed them by hand.
- **Old local branches.** 20 local branches (`feature/v12-S1…S5`, `pr-12`, `pr-24`, `release/v13.1.0`, `dev-temp`,
  …) are not ancestors of `origin/main`. Most are probably squash-merged, which no ancestry check can see, so
  each needs the `headRefOid` test to decide.
- **Supervisor's parallel-path worktrees** (`../<project>-<subtask>`, `async-orchestration` FINALIZE) left by a
  run that died before FINALIZE's own cleanup.

## Goal
One command reports, and on request removes, exactly the worktrees and local branches that are provably done:
the same proof `closeout` already trusts. Anything uncertain is reported and kept.

## Scope
1. **`automate-helpers.sh sweep [--apply] [--root <checkout>]`** (delegated to `automate-trail.sh`, beside
   `closeout`). Without `--apply`, a DRY RUN: it prints and changes nothing. One line per candidate:
   `sweep: would-remove|removed|kept <kind> <path-or-branch> — <reason>`, then one summary line. Always exit 0
   (fail-SAFE, like `closeout`).
2. **The rule is exactly closeout's**, with no new heuristic. For a local branch `B`:
   - find its PR (`gh pr list --state merged --head B`, the newest);
   - the candidate is removable ONLY when that PR is `MERGED` AND `B`'s tip equals the PR's `headRefOid`;
   - a branch with no PR, an open or closed-unmerged PR, a tip that moved after the merge, or a `gh` failure is
     `kept` with that reason (fail CLOSED toward keeping).
   - Never the current branch, the base branch, or a branch checked out in any worktree that is itself kept.
3. **Worktrees, by owner:**
   - **Plugin-made** (Supervisor's sibling `../<project>-<subtask>` worktrees, `trail-pr`'s temporary worktrees,
     `<primary>-lanes/**` lane clones): removable under rule 2 applied to the worktree's branch, only when clean
     after `worktree-salvage.sh`, and through `git worktree remove` (never `--force`, never `rm -rf`).
     **Lane clones are never swept here.** They belong to `lane-remove` (`parallel-automate/05`), which also
     checks live processes and pending questions. `sweep` reports them as `kept lane — use lane-remove`.
   - **App-made** (`.claude/worktrees/*`, created by the Claude desktop app for its sessions): **report only**,
     never removed, even with `--apply`. The app owns them and has its own cleanup (Settings › Storage). The
     report says which are clean and merged, so the owner can remove them there.
4. **Live processes:** a worktree whose path is the cwd of a live process (`lsof` where available) is `kept`
   with the pid named. No kill.
5. **Where it runs:**
   - on demand (`/automate --sweep`, a flag of the existing command; no new command, so the counts don't move);
   - in dry-run mode at the `## Status: done` run end, with one summary line appended to `## Progress`;
   - by item 06's fleet closeout, in dry-run mode.
   It never runs `--apply` unattended.
6. **Tests** (`test-automate-trail.sh`, new group, `gh` stubbed, real git repos in `mktemp -d`):
   - a merged PR whose tip equals `headRefOid` ⇒ `would-remove`, and `removed` with `--apply`;
   - tip moved after merge ⇒ `kept`;
   - an open PR, a closed-unmerged PR, no PR, a `gh` failure ⇒ `kept`, each with its reason;
   - a dirty worktree ⇒ `kept`;
   - an app-made `.claude/worktrees/x` that is clean and merged ⇒ reported, NOT removed with `--apply`;
   - a lane clone ⇒ `kept lane`;
   - the dry run changes nothing (a checksum of `git worktree list` + `git branch` before and after);
   - always exit 0.
   **Mutation controls:** dropping the `headRefOid` comparison must fail the moved-tip leg; dropping the
   app-made exclusion must fail its leg.

## Non-goals
Remote branches (GitHub's "delete branch on merge" owns those). Session transcripts (Claude Code's 30-day
`cleanupPeriodDays` owns those). Lane teardown (`parallel-automate/05` `lane-remove`). Any `--force`.

## Acceptance criteria
- Given this repo's 20 non-ancestor local branches, when `sweep` runs dry, then each is listed as `would-remove`
  or `kept` with a reason, and nothing changes (pasted output + the unchanged `git branch` checksum).
- Given `--apply`, then only `would-remove` items go, and a second dry run lists none of them.
- Given a clean, merged app-made worktree, then `--apply` reports it and leaves it in place.
- `bash scripts/ci-local.sh` green; ship a `changelog.d/` fragment (bump with `scripts/bump-version.sh` as the
  last commit, never by hand).

## Provenance
Owner, 2026-10-03, during S1 (session 0d556d54): "the cleanup should be handled by the plugin like we are doing
in closeout". The lane-specific half was amended into `parallel-automate/05` (`lane-remove` refusals) and `/06`
(fleet closeout teardown + leak summary) the same day. Evidence: 5 stale worktrees in the primary, removed by hand
with `git worktree remove` after checking each was clean and merged; 20 old local branches still open.
