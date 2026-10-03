# M1 — Migrate THIS repo's run history to `loomwright-meta` (OPERATOR-RUN — never an `/automate` item)

## Status: parked (operator-run: lives in `operator-run/` so folder intake never enqueues it; run by hand after 03 is merged AND the plugin is reinstalled)

## Depends on
03

## Why this is a human runbook
Sessions run the installed plugin, not the working tree. If an `/automate` run performed this migration, the engine
closing out the item would be the one from before the migration, and its trail step would commit nothing anywhere.
The migration also changes GitHub settings and untracks ~370 files — both need the owner.

## Preconditions (check each, write the result down)
1. Item 03 is merged, the plugin is reinstalled, and the running session reports the new version.
2. No `/automate` run is in flight: `automate-helpers.sh resume-glob .supervisor/automate` lists nothing running,
   `run-lock.sh status` prints `UNLOCKED`, `gh pr list --state open` shows no trail PR.
3. The primary checkout is on `main`, clean, and equal to `origin/main`.
4. No other checkout or worktree of this repo has uncommitted run-history edits (`git worktree list`; check each).

## Steps
1. **Dry-run the scrub.** `meta-sync.sh push --dry-run` (or the scrub alone) over the managed set. Read every hit.
   Fix or exclude before anything is published — the branch is on a PUBLIC repo and is never force-pushed, so a
   leak is permanent.
2. **Create the branch.** `meta-sync.sh init --branch loomwright-meta`.
3. **Protect it before the first real push.** Add a repository ruleset targeting `loomwright-meta` that blocks
   deletion and non-fast-forward updates (neither blocks normal pushes). Without it any write token can delete the
   branch.
4. **Seed.** `meta-sync.sh push`. Then verify, against the CURRENT `origin/main` (not an earlier SHA):
   - list A = `git ls-files .supervisor` on `origin/main`, minus `.supervisor/memory/`, restricted to the managed
     patterns; list B = `git ls-tree -r --name-only origin/loomwright-meta`;
   - `comm -23 A B` is empty; for every path `git rev-parse origin/main:<p>` equals
     `git rev-parse origin/loomwright-meta:<p>`;
   - `git ls-tree -r --name-only origin/loomwright-meta | grep -vE '\.md$|results\.jsonl$'` is empty.
   - Tracked files under `.supervisor/` that are NOT in the managed patterns: list them and decide each (keep on
     `main`, or extend the patterns in a follow-up) — do not silently drop them.
5. **Untrack on a PR branch.** Enable branch mode via `/setup memory` (writes the new gitignore block), then
   `git rm -r --cached` the managed paths. PR body carries the A/B counts, the empty diffs and `main`'s
   pre-migration SHA.
6. **Re-verify at merge time.** Immediately before merging, repeat step 4's comparison against the then-current
   `origin/main`; if anything new landed under the managed paths, `meta-sync.sh push` it first.
7. **Merge, then in the primary:** `git pull` (the working-tree copies of the untracked files are deleted by this
   pull in every checkout except the one that ran `git rm --cached`), then `meta-sync.sh pull`. Confirm the files
   are back and `git status --porcelain` is empty.
8. **Every other checkout / machine:** `git pull`, then `meta-sync.sh pull`.

## Verify (paste each into the migration PR or a follow-up note)
- `git ls-files .supervisor` on `main` lists only `.supervisor/memory/` (plus anything deliberately kept in step 4).
- A new session shows the "not pulled" line in a fresh clone, and no line in the primary.
- `/handoff` and `/insights` produce non-empty output in the primary.
- CI on `main` is green, and the self-test `SKIP` count is not higher than before the migration.
- ONE real single-item `/automate` cycle: exactly one PR (the feature PR); the stamp, done brief, run file and
  ledger line are on `loomwright-meta`.

## Rollback (try once in a scratch clone BEFORE step 5)
`git revert` the untrack PR (restores the old gitignore block) → `meta-sync.sh pull` → `git add` the managed paths
→ commit. This re-tracks the CURRENT files, so nothing written since the migration is lost. The metadata branch is
left in place.

## Stop conditions
Any scrub hit you cannot explain; any path in A missing from B; a non-empty non-`.md` listing on the branch; CI
red on the untrack PR; the real `/automate` cycle opening a second PR. Stop, roll back, and write up what happened.

## Run record (2026-10-02 → 2026-10-03)
- **Before step 1:** #359 cleared 7 scrub hits on tracked files (5 home paths, 2 `acme/widgets` placeholders). Step 1's
  `push --dry-run` does not exist. A scratch-clone rehearsal (local bare remote, `config.json` copied for the
  allowlist) stood in for it; the fix is `meta-sync-followups/04` + `/05` part D. Backup:
  `~/supervisor-backup-2026-10-03.tgz` (2,357 files, verified identical).
- **Steps 2–4:** branch `fc318fe` → `9ce8123`. Ruleset 24406129 (deletion + non-fast-forward, no bypass).
  A = B = 381, with 0 blob mismatches against main@`9a78b9c`. Kept on `main`: `.supervisor/memory/` and the two
  `twin-remediation/salvage/*/check.sh` scripts (owner decision).
- **Rollback drill:** steps 5–7 work. **This runbook's Rollback recipe loses post-migration edits.** In branch mode
  the files are gitignored, `git revert` overwrites them, and `meta-sync pull` then writes 0. Use the corrected
  recipe in #361's PR body; `meta-sync-followups/05` part D fixes the section above.
- **Step 5:** #361, with CI fixed by `f428263` (`test-committed-twin-scrub.sh` reads the mode). It merged
  2026-10-03 (`36f3730`) **before** step 6 ran. Checked afterwards: no managed path was added or changed on `main`
  after `9a78b9c`, and all 381 deleted paths are on the branch with identical bytes, so nothing was lost.
  Lesson: an early merge skips step 6, so M2 must make the re-check a precondition for merging.
- **Step 7:** the primary keeps all 381 files byte-identical, clean status, mode `on loomwright-meta`, readiness
  `configured`.
- **Verify:** a fresh GitHub clone shows the "not pulled" line, and `meta-sync pull` writes 382 files and clears
  it; the primary shows none. `/handoff` (8 items) and `/insights` (89 run notes) are non-empty. CI green (122/122)
  at `9a78b9c`, `36f3730` and `1f32d16`.
  - **Skip count +1 — accepted (owner, option 1):** the `sdk-spike` `digest-lanes.test.sh` optional corpus sweep
    no longer sees `.supervisor/jobs/done/` in CI and prints `SKIP: local corpus sweep … not present`. Before M1,
    CI swept 132 real briefs (2 known throws, a note, never a gate). The sweep still runs locally with the
    identical 2/132 result, and the committed fixture briefs remain the CI guard. Restoring it in CI is scoped
    in `meta-sync-followups/05` part D.
  - **Open:** the one real single-item `/automate` cycle (`parallel-automate/04`, run
    `automate-2026-10-01-142337 --limit 4`).
