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
| `preflight`, `scrub`, `rehearse`, `init`, `protect`, `mode_pr`, `seed`, `untrack_pr`, `verify_pr`, `after_merge`, `rollback` | step result: `PASS` \| `FAIL`; `protect` may also read `PRINTED` (ruleset printed, `protect --verify` not yet passed); `seed`, `untrack_pr`, `verify_pr` may also read `STALE` (a later step invalidated them: a re-run `seed` stales `untrack_pr` + `verify_pr`, a re-cut `untrack-pr` stales `verify_pr`, an `after-merge` tracked-path FAIL stales all three) — `STALE` never satisfies a gate | the step of the same name (`STALE`: `seed`, `untrack-pr`, `after-merge`) |
| `seed_a`, `seed_b` | counts: A = managed paths tracked on `origin/<default>` (`meta-sync.sh list-managed --tracked`), B = paths on the metadata branch | `seed` |
| `seed_sha` | the `origin/<default>` commit the seed check ran against | `seed` |
| `seed_check` | `equal` (A = B) \| `subset` (A ⊆ B, follow-up round only) — the relation the seed check proved; the untrack PR body states it | `seed` |
| `followup` | `1` once `after-merge` found managed paths still tracked after a merged untrack PR — merge proven, not inferred from the mode line: no path of this round's A set (`a.list`) is still tracked, or the PR's head commit is in `HEAD`; otherwise `after-merge` refuses ("untrack PR not merged yet") and records nothing. The A/B check accepts A ⊆ B only when this is recorded AND the mode line reads `on <b>` (never on the mode line alone). Deleted by `rollback`, and by `preflight` unless `after_merge` is still `FAIL` (the fresh-case recovery re-runs `preflight` mid-round) | `after-merge` (deleted: `rollback`, `preflight`) |
| `mode_pr_branch`, `untrack_branch`, `rollback_branch` | the NEW branch the step committed on | `mode-pr`, `untrack-pr`, `rollback` |
| `pr_mode`, `pr_untrack`, `pr_rollback` | the URL of the PR the step opened (never merged) | `mode-pr`, `untrack-pr`, `rollback` |
| `backup_mode_pr`, `backup_untrack_pr` | the path the `.gitignore.backup.<ts>` was moved to | `mode-pr`, `untrack-pr` |
| `verify_pr_sha` | `HEAD` (the fast-forwarded default) when `verify-pr` passed | `verify-pr` |

**Gate.** Every step except `plan`, `state` and `rollback` refuses (exit 1, nothing changed) while the
recorded `preflight` result is not `PASS`; later steps also require the result of the step they follow.
The script header's `preflight` entry is the one authoritative statement of these exemptions and why.

**Side files** in the same folder (never tracked): `a.list` (the A set), `ab-names.diff`,
`ab-blobs.diff`, `extra.list`, `ruleset.json`, `*.body` (PR bodies), and backups.
