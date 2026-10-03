# 01 — Version-bump script + changelog fragments

## Depends on
none

## Touches
scripts/bump-version.sh
scripts/test-bump-version.sh
changelog.d/
.github/workflows/ci.yml
.supervisor/memory/LESSONS.md
.supervisor/memory/PROJECT_MEMORY.md
AGENT_GUIDELINES.md
CLAUDE.md

## Problem
The version bump has been done by hand hundreds of times. The version lives in exactly three files —
`loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` and `CHANGELOG.md` — and there is no bump
script; `scripts/validate-version.sh` only checks that they agree. Because feature PRs edit those three files, two
open PRs conflict and can claim the same number (2026-09-27: "#284 took v15.107.0 → this PR renumbered to
v15.108.0, CHANGELOG conflict resolved" in run file `automate-2026-09-26-115755`).

The instruction to bump does NOT live in agent prompts. It lives in `.supervisor/memory/LESSONS.md` (the "version
bump touches ~8 doc surfaces" and "run version-bumping briefs strictly sequentially" lessons), project memory, and
the Scope lines of pending requirements ("CHANGELOG entry, version bump"). Any fix that only edits agent prompts
changes nothing.

## Goal
One deterministic script performs the bump. Every PR carries its changelog text as a fragment. The rule for WHO
runs the script is explicit (decision P7) so the version never silently stops moving.

## Scope
1. **`scripts/bump-version.sh [patch|minor|major] [--dry-run]`** (root `scripts/`, maintainer tooling — not shipped
   in the plugin):
   - reads the current version from `plugin.json` (authoritative);
   - updates `plugin.json` and the **loomwright entry only** of `marketplace.json` (it lists three plugins; the
     stackpack and mysql-mcp versions and descriptions must be byte-unchanged). Edit by targeted in-place
     replacement of the one version value — NOT a `jq .` round-trip, which re-encodes unrelated lines of that file;
   - folds every `changelog.d/*.md` fragment (except `README.md`) into ONE new top entry in `CHANGELOG.md` in the
     existing `**vX.Y.Z — <headline>:** <body>` shape, then deletes the folded fragments;
   - refuses (exit 1, nothing written) when there is no fragment, or when the three files disagree before the bump;
   - is atomic across the three files: write all to temp files first, rename last; on any failure restore;
   - finishes by running `scripts/validate-version.sh` and `scripts/check-doc-currency.sh`; a failure restores the
     three files and exits 1;
   - bash 3.2 + BSD userland safe (macOS) AND GNU safe (CI).
2. **Changelog fragments.** `changelog.d/<slug>.md` — first line the headline, the rest the body; optional first
   line `<!-- bump: minor -->`. With no positional argument the script takes the highest level any fragment asks
   for, default `patch`. Multiple fragments fold into one entry in filename order.
3. **Who runs it (decision P7 — the answer to "nobody bumps").**
   - **Sequential run / single PR (today's default, and every item of this queue until 06):** the PR's author
     (worker or human) writes a fragment and runs `bash scripts/bump-version.sh` as the LAST commit of the PR.
     Same outcome as today, by script instead of by hand.
   - **Parallel wave:** lanes write fragments only; the release lane bumps (item 06).
   - A merge with an unfolded fragment and no bump is legal; the next bump folds it.
4. **Sweep the real instruction sites.** Supersede the two LESSONS entries through `write-lessons.sh` (never a hand
   edit — the store is provenance-gated), update `PROJECT_MEMORY.md`, `AGENT_GUIDELINES.md` and the CLAUDE.md
   "~8 doc surfaces" pointers, and append a one-line amendment to every PENDING requirement whose Scope says
   "version bump" (`grep -rln 'version bump' .supervisor/requirements --include='*.md'`, skip `## Status: done`
   files): "bump = write a `changelog.d/` fragment and run `scripts/bump-version.sh`".
5. **Guard.** `check-doc-currency.sh` fails when `plugin.json`'s version differs from `origin/main`'s AND any
   `changelog.d/*.md` fragment (other than `README.md`) is still present — a bump that did not go through the
   script. State the honest limit in the script header: a hand bump with no fragment is not detectable.
6. **Tests** (`scripts/test-bump-version.sh`, hermetic temp repo): patch/minor/major arithmetic; three files agree
   afterwards; the other two marketplace entries byte-unchanged; fragments folded and removed; no-fragment refusal
   leaves all three files byte-unchanged; pre-existing disagreement refused; `--dry-run` writes nothing.
   **Mutation control:** make the `.claude-plugin/` DIRECTORY read-only (a read-only file does not block a rename)
   and assert `plugin.json` and `CHANGELOG.md` are unchanged — no half bump.
7. **CI wiring.** `run-self-tests.sh` globs `loomwright/scripts/` only, so a root test needs an explicit `ci.yml`
   step like the other root tests. A PR that edits a workflow file makes `claude-code-action` skip itself (green
   check, zero comments). Therefore: land the `ci.yml` step as its OWN one-line PR after this one, and verify the
   review lens posted on the next non-workflow PR (`gh pr view <n> --json comments,reviews`).

## Non-goals
The release-lane bump (item 06). A slash command — `.claude/commands/` is gitignored in this repo
(`.gitignore`: `.claude/*`), so a project command file would never reach the PR; the script is the interface.
Versioning `stackpack` / `mysql-mcp`. Changing the CHANGELOG entry style.

## Acceptance criteria
- `bash scripts/bump-version.sh` on a tree with one fragment produces a diff touching exactly the two manifests,
  `CHANGELOG.md` and the removed fragment; `git diff` of `marketplace.json` is ONE changed line.
- Two branches cut from the same `main`, each with its own fragment and no version-file edit, merge into each
  other with no conflict.
- `grep -rn 'version bump' .supervisor/requirements --include='*.md'` over pending files shows the amendment line
  on each; the two LESSONS entries are superseded with provenance.
- This PR itself is bumped by running the new script (its own fragment folded).
- Full test loop + root checks green on macOS and in CI.

## Validation (must pass before merge)
1. **Baseline:** full loop on the base and on the branch; `<passed>/<total>` and `SKIP` counts for both in the PR
   body (00-overview §"Validation rule").
2. **Unchanged path:** `bash scripts/validate-version.sh --self-test && bash scripts/validate-version.sh` and
   `bash scripts/check-doc-currency.sh` pass on the branch before any bump is run.
3. **Running system:** in a scratch clone of THIS repo (never the primary), add one fragment, run the script, and
   paste `git diff --stat`, the one-line `marketplace.json` diff, and both validators' output. Then the refusal
   case (no fragment): paste `git status --porcelain` showing nothing changed.
4. **A failure this must catch:** replace the targeted edit with a `jq .` round-trip — the "ONE changed line"
   criterion and the "other entries byte-unchanged" test must both fail.
5. **Rollback:** `git revert`. Nothing is lost; a fragment written after the revert is folded into `CHANGELOG.md`
   by hand.

## Verified premises (re-check before starting)
- `git grep -l -F "$(jq -r .version loomwright/.claude-plugin/plugin.json)" -- . ':!.supervisor'` returns exactly
  the three files (2026-10-01, v15.115.3).
- `ls loomwright/scripts scripts | grep -iE 'bump|version|release'` returns only `validate-version.sh`.
- `.github/workflows/ci.yml` runs `validate-version.sh --self-test` then `validate-version.sh`; no per-PR bump
  requirement; root tests are listed as explicit steps.
- `grep -n -i bump .supervisor/memory/LESSONS.md` shows the two lessons named above.
- `git check-ignore -v .claude/commands/bump.md` → `.gitignore` `.claude/*`.
- Red-team report (not re-run by the author): a `jq .` round-trip of `marketplace.json` changes two unrelated
  lines — confirm before relying on it either way.

## Status: pending

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-01T15:47:54Z
- **Brief:** .supervisor/jobs/done/2026-10-01-parallel-automate-01-version-bump-script.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/327
