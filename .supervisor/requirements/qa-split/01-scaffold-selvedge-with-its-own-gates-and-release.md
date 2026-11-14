# selvedge exists as its own plugin, with its own gates and its own release

## Status: done
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/912

> Phase 1, item 01 of the approved plan `qa-split/00-plan.md` (rev 2, owner-approved 2026-11-12).
> Decisions: D4 (no dependency on Loomwright; CLI discovery), D19 (selvedge releases on its own).
> Read the plan's §4 rows for D4 and D19 before starting; they carry the reasons and the rejected alternatives.

## Why

selvedge is a sibling plugin in the atelier marketplace repo, like `loomwright-lanes`. It must not join
Loomwright's count, budget, doc-currency or citation gates: that shared-gate coupling made the August
extraction an atomic 45-file change. It must also not move Loomwright's version. Today
`bump-version.sh` versions only the loomwright plugin, and a lanes-only PR's `changelog.d/` fragment still
folds into Loomwright's release (`git show --stat b685d9f`). That is the thing to fix at the root, not copy.

## Scope

1. `selvedge/` with `.claude-plugin/plugin.json` (`name: selvedge`, own `version` starting `0.1.0`), a
   short description that says what it does ("evidenced PASS/FAIL per acceptance criterion"), `README.md`,
   `CHANGELOG.md`, `bin/selvedge` (a stub that prints its version and the subcommand list), `tests/`.
2. A marketplace entry in `.claude-plugin/marketplace.json`.
3. **Release scoping (D19):** `scripts/check-version-bump.sh` / the fragment fold only consider changes to
   the loomwright plugin. A PR that touches only `selvedge/` needs no `changelog.d/` fragment and leaves
   loomwright's three version files alone. selvedge's own version is bumped by hand in its `plugin.json`
   with a `selvedge/CHANGELOG.md` entry, and a selvedge gate checks the two agree.
4. **selvedge's own gates**, run by CI as a separate job (or a `selvedge/tests/run.sh` invoked from
   `ci.yml`): manifest is valid JSON with the required fields, version and changelog agree, tests pass.
   None of Loomwright's count/budget gates scan `selvedge/`; check each one's scan scope and say in the PR
   which ones needed an exclusion (none should need to *include* it).
5. **CLI discovery spike (D4):** find out, on the running Claude Code, whether a plugin's `bin/` directory
   is put on `PATH` for Bash calls (desktop app and CLI install both). Record the answer, with the evidence,
   in `selvedge/docs/cli-discovery.md`. Ship `selvedge install-cli`, which symlinks `bin/selvedge` into
   `~/.local/bin` (refuses to overwrite a non-symlink, prints what it did). If the spike shows `bin/` is on
   `PATH`, document `install-cli` as optional.

## Acceptance criteria

- `/plugin install selvedge@atelier` installs it; `selvedge --version` prints the manifest version.
- A test PR touching only `selvedge/` passes `check-version-bump.sh` with no fragment and no loomwright bump;
  a test covers this (and the existing loomwright cases still pass).
- A selvedge version/changelog mismatch fails selvedge's gate (tested).
- `selvedge/docs/cli-discovery.md` states yes/no for desktop and CLI installs, with the command output it
  was based on.
- No file under `loomwright/` changes.

## Depends on

none

## Touches

- `selvedge/**` (new)
- `.claude-plugin/marketplace.json`
- `scripts/check-version-bump.sh`, `scripts/bump-version.sh` (fragment scoping only) and their tests
- `.github/workflows/ci.yml` (selvedge gate job)

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-11-14T02:38:33Z
- **Brief:** .supervisor/jobs/done/2026-11-13-qa-split-01-scaffold-selvedge.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/912
