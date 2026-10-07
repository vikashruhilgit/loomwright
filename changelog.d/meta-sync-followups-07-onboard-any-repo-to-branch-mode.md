<!-- bump: minor -->
Onboard any repo to branch mode — guided, owner-gated migration (`migrate-branch-mode.sh` + `meta-sync-rehearsal.sh`)
New `migrate-branch-mode.sh` takes a repo from the default `/setup memory` mode to branch mode one resumable step at a time
(plan, preflight, scrub, rehearse, init, protect, mode-pr or seed / untrack-pr / verify-pr, after-merge, rollback, state),
with its state in `.supervisor/migrate-branch-mode/state` (documented as MIGRATE_BRANCH_MODE_STATE). It never merges a PR
and never writes a ruleset; its only commits are on NEW branches (mode-pr, untrack-pr, rollback), each opening a PR for
the owner. `rollback` ships the corrected recipe that keeps edits made after the migration. New `meta-sync-rehearsal.sh`
drills the whole life cycle on a scratch clone and a local bare remote with named PASS/FAIL checks (`--no-config` drops
`.supervisor/config.json` and `.agent/meta-sync-deny.txt`). `meta-sync.sh` gains `scrub --paths-from` (dry run) and
`list-managed [--tracked]`; `setup-memory.sh` gains `valid-branch`, and its branch-mode disclosure and `Next:` hint now
name `migrate-branch-mode.sh plan`. `/setup memory migrate` documents the flow: the command only asks, the script runs
every step. CI pulls run history from the metadata branch after the self-test suite, read-only and never failing the
job. Limits: `gh` and ruleset behaviour is tested only against stubs, and a checkout that synced against the metadata
branch before the untrack merge must put back the files `git pull` deletes before running `meta-sync.sh pull`.
