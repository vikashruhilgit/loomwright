<!-- bump: minor -->
Product Owner and Orchestrator publish the requirement files they write to the metadata branch
In branch mode, `/product-owner` and `/orchestrator` now push every requirement file they write to the metadata
branch right after writing it, so a teammate can read it with `git show origin/<branch>:<path>` without waiting for
an `/automate` trail push. Both call the new `automate-helpers.sh meta-publish --paths-from <file> --root <checkout>`,
which reads `setup-memory.sh mode` itself, skips in an `/automate` lane (a lane publishes at wave end), refuses a
path outside `meta-sync.sh list-managed` by name, runs the scrub dry run, then pushes exactly the listed paths with
`meta-sync.sh push --paths-from`. It always exits 0 and prints one named verdict line (skipped, refused, blocked,
pushed, no_changes or FAILED with the retry command), so a failed publish never undoes the write. The four
Collaboration notes no longer call these files local-only: with branch mode off they stay in the checkout, with it
on they are published to the metadata branch, which is public when the repo is. New hermetic legs in the `12-meta`
test part cover each verdict, a linked worktree, and unlisted local-ahead or locally deleted files being left alone.
