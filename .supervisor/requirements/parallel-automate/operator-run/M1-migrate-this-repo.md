# M1 — Migrate THIS repo's run history to `loomwright-meta` (OPERATOR-RUN — never an `/automate` item)

## Status: parked (operator-run: lives in `operator-run/` so folder intake never enqueues it; run by hand after 03 is merged AND the plugin is reinstalled)

**Usage check:** every command in an `operator-run/` runbook is checked against the shipped script's usage text (`<script> --help`) before the runbook is used — by hand, no checker script; a flag `--help` does not list (e.g. the dry-run flag M1 step 1 once named) is a runbook bug to fix first.

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
1. **Rehearse the push on a scratch clone (option A, owner 2026-10-05).** `meta-sync.sh` has no dry-run mode; this
   uses only `init` / `push` / `--root` from its `--help`. Run from the primary checkout; nothing reaches GitHub:
   ```bash
   PRIMARY="$(git rev-parse --show-toplevel)"; S="$(mktemp -d)"; BARE="$S/meta-remote.git"; CLONE="$S/clone"
   git init -q --bare "$BARE"
   git clone -q --branch main "$PRIMARY" "$CLONE"
   git -C "$CLONE" remote set-url origin "$BARE"
   git -C "$CLONE" remote get-url origin            # MUST print $BARE — stop here otherwise
   mkdir -p "$CLONE/.supervisor" && cp "$PRIMARY/.supervisor/config.json" "$CLONE/.supervisor/"  # scrub allowlist
   bash "$CLONE/loomwright/scripts/meta-sync.sh" init --root "$CLONE"
   bash "$CLONE/loomwright/scripts/meta-sync.sh" push --root "$CLONE"
   ```
   `push` exits 2 on a scrub hit and names each one as `meta_sync: scrub <path>: <rule>` (nothing pushed, branch
   and meta-base unchanged). Read every hit, fix or exclude it in the primary, apply the same fix in `$CLONE`, and
   re-run `push --root "$CLONE"` until it exits 0; then `rm -rf "$S"`. Fix before anything is published — the
   branch is on a PUBLIC repo and is never force-pushed, so a leak is permanent. While `main` still tracks the run
   history the clone carries the whole managed set; on an already-migrated `main` it carries none and `push` prints
   `meta_sync: no_changes` (exit 0) — copy the primary's managed files into `$CLONE` first to scrub them.
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
The corrected recipe from #361 (drill evidence 2026-10-03). The old order — revert the untrack PR, then
`meta-sync.sh pull`, then add the managed paths — **silently loses post-migration edits**: in branch mode the run
history is gitignored, so the revert overwrites the newer files with pre-migration bytes, and the pull then writes
nothing because it reads the stale bytes as a local edit. Never use that order.

**Preferred — the shipped subcommand** (`migrate-branch-mode.sh --help`): on the default branch, clean and equal to
`origin/<default>`:
```bash
bash <plugin>/scripts/migrate-branch-mode.sh rollback --commit <sha of the merged untrack commit>
```
It pushes local run-history edits to the branch first, reverts the untrack commit without committing, re-tracks the
CURRENT branch files, drops paths deleted on the branch since the migration, commits on a NEW branch, pushes it and
opens a PR — it never merges. The owner merges the PR, then `git checkout <default> && git pull`.
**Limit for THIS repo:** `rollback` reads the metadata branch from `.supervisor/migrate-branch-mode/state`, which only
`migrate-branch-mode.sh init` writes. M1 ran by hand, so this checkout has no recorded branch and `rollback` refuses
(`no metadata branch recorded`). Use the manual recipe below here; do not hand-write the state file.

**Manual recipe** (the #361 recipe, made BSD/GNU-portable — no `xargs -r`, no `/tmp` literals). Run on a NEW branch
off an up-to-date `main`, in the primary checkout:
```bash
BR_NAME=loomwright-meta; S="$(mktemp -d)"
bash <plugin>/scripts/meta-sync.sh push --branch "$BR_NAME"   # publish every post-migration local edit first
git fetch origin "$BR_NAME" && BR="$(git rev-parse "origin/$BR_NAME")"
git checkout -b chore/rollback-branch-mode
git revert --no-commit -m 1 <merge commit of the untrack PR>   # squash-merged: drop "-m 1"
git ls-tree -r --name-only "$BR" > "$S/onbranch"
[ -s "$S/onbranch" ] && tr '\n' '\0' < "$S/onbranch" | xargs -0 git checkout "$BR" --   # newest bytes for every branch path
git diff --cached --name-only --diff-filter=A HEAD -- .supervisor | grep -vxF -f "$S/onbranch" > "$S/gone"
while IFS= read -r p; do [ -n "$p" ] && git rm -q --cached -- "$p" && rm -f -- "$p"; done < "$S/gone"   # deleted on the branch since migration
git commit -m "Revert M1 untrack; re-track run history at $BR_NAME $BR"
```
Then push the branch, open a PR, and let the owner merge it. Check before the PR: every tracked file under the
managed patterns equals the branch tip (`git rev-parse HEAD:<p>` = `git rev-parse "$BR:<p>"`), `.gitignore` is back
to the pre-migration content, and `git status --porcelain` is empty. The metadata branch is left in place.

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
  - **Real `/automate` cycle — PASSED (2026-10-03):** `parallel-automate/04` ran under branch mode, producing exactly ONE
    PR (#365, merged 17:32Z). No `chore/…-trail-N` PR was opened (the newest is still trail-7, from before M1). The
    close-out meta-pushed `f74ecee` "trail (closeout)": the run file and both sidecars, 04's done stamp, the done
    brief, 1 ledger line and the dismissed summary. The final resume ended the run `## Status: done` and meta-pushed
    `62639a0` "trail (done)". No meta-push failure and no lock left behind.
- **M1 COMPLETE (2026-10-03).** Next per `00-overview.md` § Order (amended): S1 → `meta-sync-followups/01–05` → M2.
