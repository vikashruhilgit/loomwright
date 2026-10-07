# M2 — Carry the learning stores on `loomwright-meta` (OPERATOR-RUN — never an `/automate` item)

## Status: parked (operator-run: lives in `operator-run/` so folder intake never enqueues it; run by hand after `meta-sync-followups/05` is merged AND the plugin is reinstalled)

**Usage check:** every command in an `operator-run/` runbook is checked against the shipped script's usage text (`<script> --help`) before the runbook is used — by hand, no checker script. This runbook was written against the `--help` of `meta-sync.sh`, `meta-sync-rehearsal.sh`, `setup-memory.sh` and `run-lock.sh` as of `meta-sync-followups/07`. Item 05 changes `meta-sync.sh` (new managed paths, a consent step); re-read its `--help` after 05 merges and fix this runbook FIRST if any command or flag below is missing or has changed.

## Depends on
`meta-sync-followups/05` (part B: the managed set gains the learning stores, plus consent before their first publish) and `meta-sync-followups/07` (the rehearsal harness). M1 is complete.

## Why this is a human runbook
Same reasons as M1: sessions run the installed plugin, not the working tree, and the first push of the learning stores PUBLISHES internal agent reasoning to a branch on a PUBLIC repo that is never force-pushed. The scrub only pattern-checks that text, so a person reads what is about to go out and records the consent.

## Preconditions (check each, write the result down)
1. Item 05 is merged, the plugin is reinstalled, and the running session reports the new version.
2. No `/automate` run is in flight: `run-lock.sh status` prints `UNLOCKED`, and `gh pr list --state open` shows no trail PR.
3. The primary checkout is on `main`, clean, and equal to `origin/main`. `setup-memory.sh mode` prints `on loomwright-meta`.
4. No other checkout or worktree of this repo has unpushed run-history edits (`git worktree list`; run `meta-sync.sh status --branch loomwright-meta --root <that checkout>` in each).

## Steps — PAUSE for the owner after every step; do not start the next one without an explicit go-ahead
1. **Backup.** From the primary checkout root, outside the repo (`<backup-dir>` is any folder that is not inside a checkout):
   ```bash
   tar -czf <backup-dir>/supervisor-backup-<date>.tgz .supervisor .claude/agent-memory
   tar -tzf <backup-dir>/supervisor-backup-<date>.tgz | grep -vc '/$'     # file count in the archive
   find .supervisor .claude/agent-memory -type f | wc -l                  # must equal the line above
   ```
   Record the path and both counts in the run record. **PAUSE — owner confirms the backup.**
2. **Rehearse on a scratch clone** (nothing reaches GitHub; the checkout is only read):
   ```bash
   bash <plugin>/scripts/meta-sync-rehearsal.sh --root <repo> --branch loomwright-meta
   bash <plugin>/scripts/meta-sync-rehearsal.sh --root <repo> --branch loomwright-meta --no-config
   ```
   Every check must print `PASS` and the last line must read `meta-sync-rehearsal: <n> passed, 0 failed`. `--no-config` rehearses without `.supervisor/config.json` (the repo allowlist) and `.agent/meta-sync-deny.txt` (the scrub deny patterns).
   **Known blocker, check first:** as shipped by 07 the harness refuses a checkout that is ALREADY in branch mode (check `scratch-mode-off`: "already migrated or unreadable; nothing to rehearse"), and this repo is. Unless 05 (or a follow-up) has taught it to rehearse an already-migrated checkout — its `--help` would say so — STOP here and file that follow-up. Do not hand-roll a scratch rehearsal in its place.
   Then dry-run the scrub over exactly what the real push would add:
   ```bash
   bash <plugin>/scripts/meta-sync.sh list-managed --root <repo> > <scratch>/managed.list
   bash <plugin>/scripts/meta-sync.sh scrub --paths-from <scratch>/managed.list --root <repo>
   ```
   Exit 0 = clean; exit 2 = hits, one `scrub-hit` line each on stderr. Fix every hit in the primary and re-run until clean. **PAUSE — owner reviews the rehearsal output and the scrub result.**
3. **Consent recorded.** Show the owner the list of learning-store paths the push would add for the first time (`list-managed` minus `git ls-tree -r --name-only origin/loomwright-meta`) and say plainly: these files hold internal agent reasoning, the branch is public and never force-pushed, and the scrub only pattern-checks them. Record the answer, the date and the path count in the run record. If 05 shipped its own consent prompt for the first publish, answer it with the same decision; take its exact form from `meta-sync.sh --help` at run time — this runbook names no consent flag because none exists as of 07. **No recorded "yes" ⇒ stop.** **PAUSE.**
4. **Real push.**
   ```bash
   bash <plugin>/scripts/meta-sync.sh push --branch loomwright-meta --message "M2: carry the learning stores"
   ```
   A scrub hit exits 2 and pushes nothing — go back to step 2. **PAUSE — owner confirms the push output.**
5. **Verify** against the CURRENT `origin/loomwright-meta`:
   ```bash
   git fetch origin loomwright-meta
   bash <plugin>/scripts/meta-sync.sh list-managed --root <repo> > <scratch>/A
   git ls-tree -r --name-only origin/loomwright-meta > <scratch>/B
   comm -23 <scratch>/A <scratch>/B     # must be empty: nothing managed is missing from the branch
   comm -13 <scratch>/A <scratch>/B     # must be empty: nothing extra on the branch
   bash <plugin>/scripts/meta-sync.sh status --branch loomwright-meta
   ```
   For every path in A, `git hash-object <p>` equals `git rev-parse origin/loomwright-meta:<p>`. **PAUSE — owner signs off.**

## Verify (paste each into the run record)
- The A/B lists match, every blob is equal, and nothing outside the managed set is on the branch.
- A fresh clone, after `meta-sync.sh pull --branch loomwright-meta`, has the same managed list with byte-identical files.
- `/handoff` and `/insights` produce non-empty output in the primary.
- ONE real single-item `/automate` cycle: exactly one PR, and its trail (including any learning-store writes) lands on `loomwright-meta`.

## Rollback
The learning stores were never tracked on `main`, so nothing on `main` changes. Restore local files from the step-1 backup if they were damaged. A file published to the branch stays in its history (the branch is never force-pushed): if something sensitive went out, treat it as published, rotate any secret, and decide with the owner whether a history rewrite of the metadata branch is warranted.

## Stop conditions
A rehearsal `FAIL`; the known `scratch-mode-off` blocker in step 2; any scrub hit you cannot explain; no recorded consent; any path in A missing from B, or anything extra on the branch; a blob mismatch. Stop, restore from the backup if needed, and write up what happened.

## Run record
(empty — fill in while running: backup path and counts, rehearsal summary lines, scrub result, consent answer and date, push output, A/B counts)
