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
`plugin.json` and the loomwright entry of `marketplace.json`, nothing else, and runs `scripts/validate-version.sh` and
`scripts/check-doc-currency.sh`. Any failure restores every file and exits 1. Preview with `--dry-run`.

## Who runs the bump (decision P7)

- **Sequential run / single PR** (the default): the PR's author, worker or human, writes a fragment and runs
  `bash scripts/bump-version.sh` as the **LAST** commit of the PR. Nothing that touches the three version files or
  `changelog.d/` may follow that commit. If `main` moves before the merge, drop or revert the bump commit (which
  brings the fragment back), rebase, and re-run the script. A bare re-run after the fold has no fragment and is
  refused by design.
- **Parallel wave:** lanes write fragments only. The release lane runs the bump once for the whole wave.
- **An unfolded fragment merged without a bump is legal.** The next bump folds it.

## The guard

`scripts/check-doc-currency.sh` fails when this branch changed the `plugin.json` version (compared with
`git merge-base HEAD origin/main`) while a fragment is still here. That combination is either a bump not made by the
script, or a scripted bump left stale after `main` moved (for example, a rebase onto a `main` that merged an unfolded
fragment). If the branch already has a bump commit, drop or revert it first, then re-run the script; re-running on
top of it double-bumps. A branch that is only behind `main` stays green. A hand bump with no fragment cannot be detected, and the
script's header says so.
