## MIGRATE_BRANCH_MODE_STATE

The on-disk resume state of `migrate-branch-mode.sh` (the engine behind `/setup memory migrate`):
`<root>/.supervisor/migrate-branch-mode/state`. The script's own header comment is the single source
of truth; this section restates it for readers and **must not coin keys the script does not write**.

> ⚠️ **This is a plain-text STATE-FILE contract, NOT a hook-validated emitted result block** — same
> precedent as `AUTOMATE_RUN` and `VERIFY_QUEUE`. No hook enumerates or validates it; the script writes
> and re-reads it on every step, and `migrate-branch-mode.sh state` prints it with the next step.

**Format.** Plain `key=value` lines, one key per line, values single-line. **Last write wins**: a key
may appear more than once and the reader takes the LAST occurrence. `preflight` refuses unless the
file's location is gitignored, so the state never becomes tracked.

### Keys

| Key | Value | Written by |
|---|---|---|
| `case` | `fresh` \| `history` | `preflight` |
| `default` | the repo's default branch | `preflight` |
| `repo` | `<owner/repo>` for `gh` (from `--repo`, else parsed from the origin URL); recorded once given | `preflight` |
| `branch` | the metadata branch (vetted with `setup-memory.sh valid-branch`); every later `meta-sync.sh` call passes it as `--branch` — never a fallback to `loomwright-meta` | `init` (`rehearse` before `init` uses `--branch` without recording it) |
| `pre_migration_sha` | `HEAD` at preflight | `preflight` |
| `preflight`, `scrub`, `rehearse`, `init`, `protect`, `mode_pr`, `seed`, `untrack_pr`, `verify_pr`, `after_merge`, `rollback` | step result: `PASS` \| `FAIL`; `protect` may also read `PRINTED` (ruleset printed, `protect --verify` not yet passed) | the step of the same name |
| `seed_a`, `seed_b` | counts: A = managed paths tracked on `origin/<default>` (`meta-sync.sh list-managed --tracked`), B = paths on the metadata branch | `seed` |
| `seed_sha` | the `origin/<default>` commit the seed check ran against | `seed` |
| `mode_pr_branch`, `untrack_branch`, `rollback_branch` | the NEW branch the step committed on | `mode-pr`, `untrack-pr`, `rollback` |
| `pr_mode`, `pr_untrack`, `pr_rollback` | the URL of the PR the step opened (never merged) | `mode-pr`, `untrack-pr`, `rollback` |
| `backup_mode_pr`, `backup_untrack_pr` | the path the `.gitignore.backup.<ts>` was moved to | `mode-pr`, `untrack-pr` |
| `verify_pr_sha` | `HEAD` (the fast-forwarded default) when `verify-pr` passed. Written by the code but NOT listed in the script's header — the header should gain it | `verify-pr` |

**Gate.** Every step after `preflight` refuses (exit 1, nothing changed) while the recorded `preflight`
result is not `PASS`; later steps also require the result of the step they follow.

**Side files** in the same folder (never tracked): `a.list` (the A set), `ab-names.diff`,
`ab-blobs.diff`, `extra.list`, `ruleset.json`, `*.body` (PR bodies), and backups.
