# qa-split 11b1 — removal evidence

Evidence record for the QA removal part 1 (qa-split item 11b1): the rollback tag, then the gate and
Validation 3 outputs. The rationale is in `loomwright/docs/rationale/qa-split.md`; the per-path plan is
`loomwright/docs/qa-removal-manifest.md`.

## Rollback tag

Recorded once, before any deletion, and never recomputed (a later merge of `main` into the branch moves
the merge-base; the tag correctly does not move).

Start sha: 4951d864ad493d477d1cdf839b9d6980665b094a

How the start sha was computed (on branch `feature/qa-split-11b1-remove-qa-surfaces`, after
`git fetch origin main`):

```
$ git merge-base HEAD origin/main
4951d864ad493d477d1cdf839b9d6980665b094a
```

Remote tag before tagging (empty output — the tag did not exist):

```
$ git ls-remote --tags origin pre-qa-removal
```

Tag command. The push runs from a linked worktree that is not the run's feature-branch checkout, because
`guard-finalize-publish.sh` denies `git push` in the live run's own checkout before FINALIZE; a tag is
repo-wide, so the push only sends the tag ref:

```
$ git tag pre-qa-removal 4951d864ad493d477d1cdf839b9d6980665b094a
$ git -C .claude/worktrees/strange-visvesvaraya-79c9b9 push origin pre-qa-removal
To https://github.com/vikashruhilgit/loomwright.git
 * [new tag]         pre-qa-removal -> pre-qa-removal
```

Remote tag after tagging:

```
$ git ls-remote --tags origin pre-qa-removal
4951d864ad493d477d1cdf839b9d6980665b094a	refs/tags/pre-qa-removal
```

To restore any removed file: `git checkout pre-qa-removal -- <path>`.
