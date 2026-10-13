# changelog.d — pending changelog fragments

A feature PR does **not** edit `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` or
`CHANGELOG.md`. It adds one fragment here instead. Distinct fragment files never conflict, so two open PRs can no
longer collide on the version number or on the CHANGELOG's top line. `bash scripts/bump-version.sh` turns the
pending fragments into the bump.

## Fragment format

`changelog.d/<slug>.md` — any file here except this `README.md`:

```markdown
<!-- bump: minor -->
Headline of the change (no leading `#`, no trailing colon)
Body text. Every non-blank line after the headline is joined, with single spaces, into the
entry's one paragraph.
```

- **First line (optional):** `<!-- bump: patch|minor|major -->`. With no level argument the script uses the highest
  level any pending fragment requests; a fragment without the line requests `patch`. An explicit argument
  (`bash scripts/bump-version.sh minor`) always wins. An unknown level, or a bump directive anywhere but the first
  line, is refused.
- **Headline:** the first non-blank line after the directive.
- **Body:** everything after the headline. The CHANGELOG keeps one paragraph per entry, so line breaks and lists are
  flattened. Write the body as prose.

The fragments fold, in filename order, into ONE new top entry of `CHANGELOG.md`:
`**vX.Y.Z — <headline 1>; <headline 2>:** <body 1> <body 2>`. The script then deletes them. It also bumps
`plugin.json` and the loomwright entry of `marketplace.json`, regenerates `loomwright/capabilities.json` (its
`plugin_version` is a generated copy of the version, and nothing else in it may change), and runs
`scripts/validate-version.sh`, `scripts/check-doc-currency.sh` and `build-capabilities.sh --check`. Any failure
restores every file and exits 1. Preview with `--dry-run`.

## Who runs the bump, and the content rule (decision P7)

- **Sequential run / single PR** (the default): the PR's author, worker or human, writes a fragment, commits it,
  and runs `bash scripts/bump-version.sh`. Later commits may follow the bump. Phase 4.5 heal commits and
  `/review-pr` drain commits always do (#367, #512).
- **Parallel wave:** lanes write fragments only. The release lane runs the bump once for the whole wave.
- **An unfolded fragment merged without a bump is legal.** The next bump folds it.

**The rule is about content, not commit position.** At every commit, compared with `git merge-base HEAD origin/main`,
a branch is in one of two states:

- **Not bumped.** The versions in `plugin.json`, `marketplace.json` and `capabilities.json` and the whole of
  `CHANGELOG.md` equal the merge base's. Every fragment the merge base had is still present.
- **Bumped once.** The version is one patch, minor or major step above the merge base's in all three files.
  `CHANGELOG.md` is the merge base's plus exactly the one entry the script renders. That entry is the fold of
  fragments this branch carried, including every fragment the merge base had. No fragment is left pending.

`bash scripts/check-version-bump.sh` checks this. It is a thin wrapper over `bash scripts/bump-version.sh --check`,
and CI runs it on every PR with a deepened checkout. It reads the folded fragments back from the branch's history.
Exit 1 means the rule is broken. Exit 2 means it cannot check (no base ref, or a shallow clone), and CI treats that
as a failure.

**A fragment added after the bump** (for example, by a heal fix) is folded by **re-running**
`bash scripts/bump-version.sh`. On a branch that already carries a bump, the script **re-folds**:

1. It checks that the existing bump can be reproduced from the branch's fragments.
2. It restores the pre-bump state: the merge base's `CHANGELOG.md` and version lines, plus the fragments the bump
   folded. A pending fragment with the same name wins.
3. It bumps once over all of them, at the higher of the earlier bump's level and the fragments' request.

The script never double-bumps while it can resolve `origin/main`. Without it, the script prints a NOTE and bumps
from the working tree, as before. If the existing bump was hand-edited, it refuses and tells you to revert the bump
commit. On the plugin's sequential path, `scripts/release-refold.sh` runs `--refold` before every push: FINALIZE,
each Phase 4.5 heal push, and each `/review-pr` fix push. It commits the result, so no later commit can leave a
fragment unfolded. On a branch with no bump (a lane), `--refold` does nothing.

If `main` moves before the merge, bring it in (merge or rebase). If that brought in an unfolded fragment, re-run the
script to re-fold it. If `main` released in between, the bump is now more than one step from the new merge base and
the re-fold refuses, so revert the bump commit and re-run.

## The guard

`scripts/check-doc-currency.sh` fails when this branch changed the `plugin.json` version (compared with
`git merge-base HEAD origin/main`) while a fragment is still here. That combination is either a bump not made by the
script, or a scripted bump left stale after `main` moved (for example, a rebase onto a `main` that merged an unfolded
fragment). In both cases, re-run the script. It re-folds instead of double-bumping. A branch that is only behind
`main` stays green. On its own, this guard cannot catch a hand bump with no fragment; `--check` above can.
