A drained worktree's salvage now keeps its drain records
`worktree-salvage.sh --ignored` copied only `.supervisor/logs/`, `.supervisor/postmortem/` and the host
settings file. A drained PR worktree also holds `.supervisor/drain-rounds/` (the round ledger) and
`.supervisor/review-heal/` (the REVIEW_HEAL_RESULT sidecars). Neither was on the salvage list, so neither was
copied. Under closeout's `--allow-unsalvaged` the verdict read `ignored: ok 1` and the worktree was removed
with them. Without that flag, the coverage check named only its FIRST unsalvaged entry. That was an empty
`.supervisor/check-wait/`, so the real records stayed hidden behind a harmless-looking empty dir. Both drain
dirs are now on the salvage list and are copied and verified. An empty directory (no file at any depth) never
fails the verdict, and one `find` cannot read is still named, so the check stays fail-closed. The `failed`
and `ignored-check: unsalvaged` lines now name every uncovered entry, joined by `, `. The README's list is
read from `ign_salvage_list` instead of restating it.
