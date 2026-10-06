<!-- bump: minor -->
meta-sync — symlinked non-managed files sync, hardening branches pinned, default branch from the mode line
`meta-sync.sh` (meta-sync-followups/08). Part A: a symlink under `.supervisor/requirements/` that resolves to a
regular file at a non-managed path (e.g. `requirements/q/design.png`) no longer refuses the whole `pull`/`push`.
A directory, a dangling or a managed-`.md` symlink still fails closed with `meta_sync: symlink <path>`. Part B pins
four untested iteration-2 hardening branches with test legs, each proven by a sed mutant: the
`--no-write-fetch-head` fallback, the union's `changed during the sync` re-check, the nested stale-lock reclaim and
the `meta-base` directory guard. Two defects those legs exposed are fixed. `pull` now applies the ledger union
BEFORE any take-R write, so a `changed during the sync` refusal really changes nothing (it used to write earlier
take-R paths first). `pull`/`push` now refuse up front when `<gitdir>/meta-base` is not a regular file (a push
used to publish and only then fail to record it). Part C: with no `--branch`, the target is the branch named by the
checkout's mode line, read through `setup-memory.sh mode` (`off` keeps `loomwright-meta`). A `--branch` that
disagrees is refused `branch_mismatch`; an unknown mode, or a failed reader, is refused `mode_unknown`.
`--allow-branch-mismatch` forces an explicit `--branch`. `status` now prints `synced <sha> on <branch>`.
`meta-base` now records the branch it was taken from (a second line `branch <name>`), so a sync against any other branch — a mode-line switch, or a forced `--branch` — is refused `base_branch_mismatch` with nothing changed instead of deleting local run history (a legacy single-line base is adopted only when the target branch's own history holds every entry it records).
