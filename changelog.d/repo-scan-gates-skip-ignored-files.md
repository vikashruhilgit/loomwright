<!-- bump: patch -->
Repo-scanning gates enumerate what CI sees, not the disk
`scripts/check-locale-prefix.sh` and leg L of `test-orca-mirror.sh` enumerated the working tree with `find` / `grep -r`, so
`bash scripts/ci-local.sh` failed locally on .gitignore'd files a CI checkout never has: 11 OFFENDERs in stale salvage
copies under `.supervisor/salvage/`, and orca hits under `loomwright/sdk-spike/node_modules/`. In the main checkout the walk
also scanned every nested `.claude/worktrees/` tree (544 files scanned against the 270 CI sees). Both now enumerate
`git ls-files --cached --others --exclude-standard` (tracked plus untracked-but-not-ignored, so a new file is still caught
before it is staged) when the root is a work-tree top level, and fall back to the old walk otherwise. New legs (gate test
10a-e, orca L2a-c) drop an offender into a .gitignore'd path and assert it is not reported, with controls that the same
line in a tracked and in an untracked-unignored file is; each goes red when the enumeration reverts to the walk or narrows
to tracked-only.
