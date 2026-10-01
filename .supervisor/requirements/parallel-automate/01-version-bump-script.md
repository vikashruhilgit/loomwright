# 01 — Version-bump script + changelog fragments (bump once, at merge time)

## Depends on
none

## Touches
`scripts/bump-version.sh` (new), `scripts/test-bump-version.sh` (new), `changelog.d/` (new),
`.claude/commands/bump.md` (new, project-level), `loomwright/agents/worker.md`, `AGENT_GUIDELINES.md`,
`CLAUDE.md`, `.github/workflows/ci.yml` (only if the fragment check needs a step)

## Problem
The version bump has been done by hand hundreds of times and is written by whichever agent finishes an item. The
version lives in exactly three files — `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
and `CHANGELOG.md` — and there is no bump script; `scripts/validate-version.sh` only checks that they agree. Because
every feature PR edits those three files, any two open PRs conflict and can claim the same number (2026-09-27:
"#284 took v15.107.0 → this PR renumbered to v15.108.0, CHANGELOG conflict resolved" in run file
`automate-2026-09-26-115755`). That one collision is what makes otherwise file-disjoint items un-parallelisable.

## Goal
One deterministic command bumps the version. Feature PRs stop touching the three version files during the work;
each carries its changelog text as a fragment, and the bump folds the fragments in as the LAST step before merge.

## Scope
1. **`scripts/bump-version.sh <patch|minor|major> [--dry-run]`** (root `scripts/`, maintainer tooling — NOT shipped
   in the plugin, so the CI-checked plugin command count does not move):
   - reads the current version from `plugin.json` (the authoritative source);
   - writes the new version to `plugin.json` and `marketplace.json` (in place, `jq` + temp + rename);
   - folds every `changelog.d/*.md` fragment into ONE new top entry in `CHANGELOG.md` in the existing
     `**vX.Y.Z — <headline>:** <body>` shape, then deletes the folded fragments;
   - refuses (exit 1, nothing written) when there is no fragment, when the working tree has unrelated staged
     changes to the three files, or when the three files disagree before the bump;
   - finishes by running `scripts/validate-version.sh` and `scripts/check-doc-currency.sh`; a failure restores the
     three files and exits 1.
   - bash 3.2 + BSD userland safe (macOS) AND GNU safe (CI).
2. **Changelog fragments.** `changelog.d/<slug>.md` — first line is the headline, the rest is the body. One
   fragment per PR. `changelog.d/README.md` states the format. Multiple fragments fold into one entry, headlines
   joined, in filename order.
3. **Level selection.** The fragment may carry an optional first-line marker `<!-- bump: minor -->`; with no
   positional argument the script takes the highest level any fragment asks for, defaulting to `patch`.
4. **Rule change for agents.** Worker / Supervisor / fix-worker prose: write a fragment, do NOT edit the three
   version files. Update the instruction where it lives today (find every place that tells an agent to bump — grep
   `CHANGELOG` and `version bump` across `loomwright/agents`, `loomwright/skills`, `AGENT_GUIDELINES.md`,
   `CLAUDE.md`; fix agent and command mirrors in the same commit).
5. **Project-level command** `.claude/commands/bump.md` — a thin wrapper that runs the script and prints the diff.
6. **Tests** (`scripts/test-bump-version.sh`, hermetic temp repo): patch/minor/major arithmetic; three files agree
   afterwards; fragments folded and removed; no-fragment refusal leaves all three files byte-unchanged; pre-existing
   disagreement refused; `--dry-run` writes nothing. **Mutation control:** a fixture where `marketplace.json` is
   read-only must leave `plugin.json` unchanged (no half bump).
7. **Guard against the old habit.** `check-doc-currency.sh` (or a small new check) fails a PR that changes
   `plugin.json`'s version AND still has an unfolded `changelog.d/*.md` fragment, i.e. a hand bump.

## Non-goals
Wiring the bump into the merge train (item 06). Changing the CHANGELOG entry style. Moving the script into the
plugin. Versioning `stackpack` / `mysql-mcp`.

## Acceptance criteria
- `bash scripts/bump-version.sh patch` on a tree with one fragment produces a commit-ready diff touching exactly the
  three version files plus the removed fragment; `validate-version.sh` and `check-doc-currency.sh` pass.
- Two branches cut from the same `main`, each with its own fragment and NO version-file edits, merge into each other
  with no conflict.
- No agent prompt or skill still instructs a hand edit of the three version files.
- Full test loop + root checks green on macOS and in CI.

## Validation (must pass before merge)
1. **Baseline:** full loop on the base and on the branch; both `<passed>/<total>` lines in the PR body
   (00-overview §"Validation rule").
2. **Unchanged path:** `bash scripts/validate-version.sh --self-test && bash scripts/validate-version.sh` and
   `bash scripts/check-doc-currency.sh` pass on the branch BEFORE any bump is run — i.e. adding the script and the
   fragment directory alone changes nothing CI checks.
3. **Running system:** in a scratch clone of THIS repo (never the primary), add one fragment, run
   `bash scripts/bump-version.sh patch`, and paste: the `git diff --stat` (exactly the three version files + the
   removed fragment), and the output of `validate-version.sh` + `check-doc-currency.sh`. Then run the refusal case
   (no fragment) and paste `git status --porcelain` showing nothing changed.
4. **Rollback:** `git revert` of the PR. Nothing is lost; any fragment written after the revert must be folded into
   `CHANGELOG.md` by hand.

## Verified premises (re-check before starting)
- `git grep -l -F "$(jq -r .version loomwright/.claude-plugin/plugin.json)" -- . ':!.supervisor'` returns exactly
  the three files (2026-10-01, v15.115.3).
- `ls loomwright/scripts scripts | grep -iE 'bump|version|release'` returns only `validate-version.sh`.
- `.github/workflows/ci.yml` runs `bash scripts/validate-version.sh --self-test` then `bash
  scripts/validate-version.sh`; a grep of `ci.yml` for `bump|changelog` finds no per-PR bump requirement.
- CLAUDE.md §"Adding or Modifying Agents": the plugin `description` carries no version string — the script must not
  add one.

## Status: pending
