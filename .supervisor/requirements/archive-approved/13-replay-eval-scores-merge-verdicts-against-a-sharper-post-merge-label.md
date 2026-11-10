# Replay eval scores merge verdicts against a sharper post-merge label

## Status: pending

Source: `loomwright-archive/requirements/batchA/2026-10-30-070224-replay-eval-scores-gate-verdicts-against-what-happened-after-merge.md` (plan doc `_BACKLOG-2026-10-30-070224-batch-a-replay-evals-and-narrow-worker-tokens.md`, item R2). Refreshed against main `8ec200e` / v17.35.1.

**As the** owner (Vikash), deciding how far to trust the trusted-merge gate,
**I want** a post-merge outcome label that only marks a PR bad when a later commit undoes or fixes that PR's own work, and one local command that replays past merged PRs through the gate's replay mode (story 12), labels each with that label, and scores the verdicts,
**so that** the gate's accuracy is measured against outcomes that really say something about each PR, on this machine only, and tracked over time.

### Problem (read on main `8ec200e`)

- **The only post-merge label cannot score anything.** `build-loop-evidence.sh` `durable_check()` marks a run "not durable" when any commit inside 14 days whose subject matches `^([Rr]evert|fix|Fix|hotfix)` touches any FILE the landing touched. Measured on this checkout on 2026-11-09: 49 of 57 runs with a verdict are "no", 8 "yes". The owner's earlier count was 48 of 56; the window has moved since. One commit (`4f855bb`, a v14.39.0 release that touched `CHANGELOG.md`, `CLAUDE.md`, `plugin.json`, `marketplace.json`) marks 7 runs "no", and a 25-file mechanical fix from 2026-11-09 (`660fddd`) marks 6 more. The script's own Data-quality note says the label is sensitive to hot shared files.
- **Reverts of merged PRs are close to zero.** Every revert-subject commit checked on main undoes an in-branch version bump (`7c69413`, `e6ea462`, `ac5dc0c`, `b44b245`, …), not a merged PR. So a revert-only label would be nearly all "stayed".
- **The old matcher is frozen on purpose.** Its header says the matching is "deliberately FROZEN (the published SPIKE verdicts rest on it)", and `/insights` "Loop evidence" renders from it.
- **No instrument scores the gate.** `run-eval.sh` scores fixture tasks, `measure-heal-signal.py` scores `heal_decision` against review churn before merge, and the phase45-reviewer suite (v17.25.0) replays the reviewer, not the gate.

### Scope

**Part 1: the sharp outcome label (built first, usable alone).**
- New `loomwright/scripts/outcome-label.sh`, a sourceable library plus CLI: `outcome-label.sh [--root <repo>] [--base <branch>] [--window-days D] [--now <epoch>] [--merge-sha <sha>] <pr-number>...`. It prints one JSON line per PR: `pr`, `landing_sha`, `merged_at`, `window_end`, `label`, `by`, `evidence_sha`, `reason`. It reads local git only, with no `gh` and no network.
- **Labels**, in this precedence order (window `D` days after landing, default 14):
  - `reverted`: a commit in the window that reverts the PR's own landing commit, meaning a body `This reverts commit <landing sha>` (7+ hex) or a revert-style subject naming `(#N)`. This is the strongest label. A revert of any other commit (for example an in-branch version bump) is not.
  - `follow_up_fix`: a commit in the window, outside the PR's own landing and branch, whose subject matches the fix-style pattern AND either (a) names the PR as `#N` (a whole number, so `#12` never matches `#123`), or (b) modifies or deletes at least one line that the PR introduced, in a file not on the ignore list. "The PR introduced" means `git blame` at the follow-up's parent attributes the line to the squash landing, or to a commit of a true merge's branch. `by` records `names_pr` or `line_overlap`.
  - `stayed`: none of the above, and the window has closed.
  - `pending`: none of the above, and the window is still open. A `reverted` or `follow_up_fix` found inside the window is final at once.
  - `unknown`: the history is ambiguous or unreadable. `reason` is one of `landing_not_found`, `ambiguous_landing` (more than one first-parent commit claims `#N` and no `--merge-sha` was given), `landing_not_on_base`, `shallow_history`, `blame_failed`, `ignore_list_unreadable`, `git_unavailable`. It is never guessed into another label.
- **The ignore list and fix pattern are data**, kept in `loomwright/docs/outcome-label-ignore.json` (`basenames`, `path_prefixes`, `fix_subject_ere`) and read at runtime from the plugin root. Initial content: basenames `CHANGELOG.md`, `CLAUDE.md`, `plugin.json`, `marketplace.json`, `capabilities.json`, `prompt-token-budgets.json`, `prompt-history-refs-baseline.json` (by basename, so they also match the pre-rename `ai-agent-manager-plugin/` paths and the sibling plugins). Path prefixes: `changelog.d/`, `.claude-plugin/README.md`. `fix_subject_ere`: the old matcher's `^([Rr]evert|fix|Fix|hotfix)`, unchanged, so the comparison isolates the line and `#N` rules.
- **Alongside, not shared.** `build-loop-evidence.sh` is not changed at all. Its label, its `/insights` numbers and its frozen SPIKE basis stay as they are. The two labels are named differently (`durable` vs `label`) so they are never confused.
- **Discrimination evidence.** `outcome-label.sh --summary` prints a total per label and a count of PRs per `evidence_sha`, so a commit that clusters is visible. The new label is run once on this repo over the same PRs as the old count, and both rates are recorded in `docs/evidence/outcome-label-sharpening.md`. That doc carries label rates only, never a gate score.

**Part 2: the replay eval (needs story 12).**
- New `loomwright/scripts/replay-eval.sh [--since <date>] [--limit N] [--window-days D] [--no-record] [--project <dir>]`.
- **Select:** merged PRs of the current repo, newest first, read with GET-only `gh` calls (`number`, `mergeCommit`, `mergedAt`, `baseRefName`, `headRefOid`). The base comes from `resolve-base-branch.sh`. Defaults are `--limit 50`, plus `--since`. A PR merged into another base is skipped and counted as `other_base`.
- **Replay:** for each PR, make a throwaway independent clone under `mktemp -d` (the `lens-run.sh` pattern, never `git worktree add`). It holds the merge commit and the PR's final head. If the head cannot be obtained, the PR is `unscorable` with reason `head_unavailable`. The clone is removed on every exit path. Then call `automate-helpers.sh merge-verdict <url> --replay --root <clone>` (story 12) and keep its `replay_conclusion`, `replay_reason` and each condition's `replay_class` / `status`. `replay-eval.sh` never evaluates a gate condition itself.
- **Label:** `outcome-label.sh` with `--merge-sha` from the PR's `mergeCommit`. There is exactly one labeler, and `replay-eval.sh` sources it.
- **Score:** `would_block` predicts bad, `would_pass` predicts good. Bad means `reverted` / `follow_up_fix`; good means `stayed`. The output has a confusion matrix (`tp` blocked & bad, `fp` blocked & stayed, `fn` passed & bad, `tn` passed & stayed), plus `precision` and `recall` as `"x/y"` fractions with counts. A denominator of 0 gives `"n/a"`. **Coverage** is printed beside every score: `scored`, `unscorable` (with a count per reason), `pending`, `unknown` (with a count per reason), `other_base`, and the total of `sha_fixed` vs `not_replayable` conditions. A PR that is `unscorable`, `pending` or `unknown` never lands in a matrix cell.
- **History, local only:**
  - The per-PR verdict cache `.supervisor/eval/replay-prs.jsonl` is keyed by `(repo, pr, head sha, plugin version, content hash of the plugin's automate-helpers.sh)`. A cache hit skips the clone and the `merge-verdict` call.
  - Labels are recomputed on every run (git only, cheap), so `pending` resolves by itself.
  - One summary line per run is appended to `.supervisor/eval/replay-results.jsonl`: `recorded_at`, plugin version, window, the ignore-list hash, the matrix, precision/recall and coverage.
  - Both files are built with `jq`. Recording is best-effort and fail-safe (the `run-eval.sh` convention), and `--no-record` turns it off. Neither file is in meta-sync's managed set, so neither ever reaches the meta branch.
- **Output:** a short human report, then exactly one line `REPLAY_EVAL_RESULT: {…}`, documented in the new `docs/result-schemas/replay-eval-result.md` (with the per-PR record and label vocabulary) and indexed in `docs/RESULT_SCHEMAS.md`.
- **Advisory, local, never in CI.** It always exits 0. With `CI` or `GITHUB_ACTIONS` non-empty it refuses (`status: "refused_ci"`) and makes no `gh` call and no clone. It never gates, posts, comments, sends telemetry or writes outside `.supervisor/eval/` and its own temp dirs.

## Acceptance Criteria

Every case builds a fixture git repo in the test's temp dir (squash and true-merge landings, revert and fix commits, controlled `GIT_COMMITTER_DATE`, a fixed `--now`). Part 2 adds a stub `gh` that serves fixture PR JSON and logs argv, and a stub `merge-verdict` reached through the script's documented helper-path override. No network (`check-test-hermetic.sh`).

**Part 1: label (Test: `loomwright/scripts/test-outcome-label.sh`)**
- [ ] **Hot commit no longer clusters:** seven fixture PRs each add lines to their own file plus a `CHANGELOG.md` and a `plugin.json` line. One later `fix(…)` commit inside the window edits all seven files (on lines none of them introduced) plus `CHANGELOG.md` and `plugin.json`. All seven are `stayed`, and `--summary` shows no `evidence_sha` cluster. Test: `test-outcome-label.sh`.
- [ ] **Own line fixed:** a `fix:` commit inside the window that modifies one line a PR introduced gives `follow_up_fix`, `by: line_overlap`, with `evidence_sha` naming the commit. This holds for a squash landing and for a true-merge landing whose line came from a branch commit. Test: `test-outcome-label.sh`.
- [ ] **Hot file ignored:** a `fix:` commit that only rewrites the PR's own `CHANGELOG.md` / `changelog.d/<x>.md` / `plugin.json` lines gives `stayed`. Test: `test-outcome-label.sh`.
- [ ] **Names the PR:** a `fix:` commit naming `#7` that touches unrelated files gives `follow_up_fix`, `by: names_pr` for PR 7. The same subject naming `#70` does not label PR 7, and a non-fix subject naming `#7` does not label it. Test: `test-outcome-label.sh`.
- [ ] **Revert is strongest:** a `This reverts commit <landing sha>` commit 3 days after landing gives `reverted` even when a qualifying fix also exists. A revert of an in-branch version-bump commit (not the landing) gives no `reverted`. Test: `test-outcome-label.sh`.
- [ ] **Window:** with no bad commit and `--now` inside the window, the label is `pending`. After the window it is `stayed`. A qualifying fix inside a still-open window gives `follow_up_fix`. Test: `test-outcome-label.sh`.
- [ ] **Rename survives:** the PR's file is renamed after landing, then a `fix:` edits a line the PR wrote, giving `follow_up_fix`. Test: `test-outcome-label.sh`.
- [ ] **Unknown, never guessed:** two first-parent commits claiming `#9` (no `--merge-sha`) give `unknown/ambiguous_landing`. No claim gives `landing_not_found`. A shallow clone gives `shallow_history`. A `--merge-sha` that is not on the base's first-parent history gives `landing_not_on_base`. Test: `test-outcome-label.sh`.
- [ ] **The list is data, and a bad list fails toward unknown:** adding a path to a copy of the ignore file (through the documented override) stops that path's overlap from counting. A missing, empty-object or malformed ignore file makes every PR `unknown/ignore_list_unreadable`, never an empty list read as "nothing hot". Test: `test-outcome-label.sh`.
- [ ] **Output safety:** a subject or path holding a backtick, `"`, `-->` or a newline still yields one valid JSON line per PR. Test: `test-outcome-label.sh`.
- [ ] **Mutants each fail a case:** (a) file-level overlap in place of line overlap, (b) the ignore list skipped, (c) precedence with `follow_up_fix` before `reverted`, (d) `#N` matched as a prefix. Test: `test-outcome-label.sh`.
- [ ] **Old label untouched:** `loomwright/scripts/build-loop-evidence.sh` is byte-identical to main, and `test-build-loop-evidence.sh` passes unchanged. Test: `test-outcome-label.sh` (a `git diff --exit-code` guard) and `test-build-loop-evidence.sh`.

**Part 2: eval (Test: `loomwright/scripts/test-replay-eval.sh`)**
- [ ] **Matrix:** take four PRs past the window, labelled `reverted`, `follow_up_fix`, `stayed`, `stayed`, with stub conclusions `would_block`, `would_pass`, `would_block`, `would_pass`. The result is `tp 1, fn 1, fp 1, tn 1`, precision `"1/2"`, recall `"1/2"`, and `REPLAY_EVAL_RESULT` parses with `jq`, with every key listed in `replay-eval-result.md` (the test reads the field list from the doc). Test: `test-replay-eval.sh`.
- [ ] **Coverage, never cells:** a stub `unscorable` (reason `pr_state_unreadable`), a `pending` PR, an `unknown` PR and an `other_base` PR each appear only in coverage, with their reason counts. The `sha_fixed` / `not_replayable` totals equal the stub output's counts. Test: `test-replay-eval.sh`.
- [ ] **`n/a`:** with no `would_block`, precision is `"n/a"`, never `0` or `1`. Test: `test-replay-eval.sh`.
- [ ] **History:** a run appends exactly one trend line and one cache record per replayed PR. A second run with no new PRs makes zero stub `merge-verdict` calls and appends one more trend line with the same matrix. Moving `--now` past a `pending` PR's window re-labels and scores it without re-replaying. `--no-record` writes nothing. Test: `test-replay-eval.sh`.
- [ ] **Scratch clone:** each replay's `--root` is a separate directory outside the caller's checkout, not listed by `git worktree list`. After the run, the caller's HEAD, refs, `git status --porcelain` and `git worktree list` are identical, and no scratch dir is left under the temp root (also after a stub that exits non-zero). Test: `test-replay-eval.sh`.
- [ ] **Stub verdict missing, non-zero or not one JSON object:** that PR is `unscorable` with reason `verdict_unreadable`, never scored. Test: `test-replay-eval.sh`.
- [ ] **Fail-safe:** `gh` failing, or `jq` / `git` missing, gives one stderr line naming it, `status: "unverified"` with zero counts, nothing appended, and exit 0. Test: `test-replay-eval.sh`.
- [ ] **Never in CI:** with `GITHUB_ACTIONS=true` (and separately `CI=1`), the result is `status: "refused_ci"`, zero `gh` calls, no clone, exit 0. Test: `test-replay-eval.sh`.
- [ ] **Nothing leaves the machine:** the stub `gh` log holds only GET reads (no `pr comment`, `pr review`, `pr merge`, `api -X POST|PATCH|PUT|DELETE`). No file outside `.supervisor/eval/` and temp dirs changes. Sourcing `meta-sync.d/managed.sh`, `is_managed` returns non-zero for both new `.supervisor/eval/` paths. `README.md`, `.claude-plugin/marketplace.json` and `loomwright/.claude-plugin/plugin.json` contain no `replay-eval` / `REPLAY_EVAL` string. Test: `test-replay-eval.sh`.
- [ ] **One gate, one labeler (grep checks plus mutants):** `replay-eval.sh` never calls `classify-risk.sh` or `rules-gate-verdict.sh`, sources `outcome-label.sh`, and holds no `git blame` / revert-matching code of its own. A mutant that scores `pending` / `unknown` / `unscorable` into a cell fails a case, and so does a mutant that prints `0` for `n/a`. Test: `test-replay-eval.sh`.

## Non-goals
- Showing a score on a PR, a check run or a GitHub App (gate 2b/2c and R3 stay deferred).
- Any public or published score: no README, marketplace, plugin description, badge, PR body or telemetry carries a replay score or precision/recall. The evidence doc carries label rates only.
- Changing `build-loop-evidence.sh`, its `durable` label or the `/insights` "Loop evidence" numbers. Part 1 does not switch it to the new labeler.
- A `/insights` "Gate replay score" section (PO default below).
- A `ci_failed_after_merge` label from check runs on the merge commit (PO default below).
- Scoring Phase 4.5 / drain verdicts (`heal_decision`, `READY`) against the new label. A later item can reuse `outcome-label.sh`.
- Replaying other repos, lane clones, or running on a schedule or in CI.

## Owner decisions
- 2026-11-09 (Vikash, in chat): R2 un-deferred and decoupled from gate 2b/2c; first part sharpens the durable label; refreshed against main 8ec200e / v17.35.1.
- 2026-11-09 (Vikash, in chat): a follow-up counts only when it touches the merged PR's own changed lines or names the PR (`#N`); hot/generated files are ignored through a data list; a revert of the PR's own landing is the strongest label; `pending` inside the window, `unknown` when history is ambiguous; an AC re-runs the new label on this repo and records its rate next to the old one. The eval selects merged PRs, replays each through story 12 in a scratch clone, and outputs a confusion matrix, coverage, a per-PR cache and a trend file. Nothing leaves the machine, it never runs in CI, and there are no public scorecard claims.
- PO default, pending owner review (shared vs alongside): the new labeler sits alongside. `build-loop-evidence.sh` is untouched, because its header freezes the matcher for the SPIKE verdicts and `/insights` reads it. Switching it later is a separate item that would change `/insights` numbers.
- PO default, pending owner review (hot list): basenames `CHANGELOG.md`, `CLAUDE.md`, `plugin.json`, `marketplace.json`, `capabilities.json`, `prompt-token-budgets.json`, `prompt-history-refs-baseline.json`; prefixes `changelog.d/`, `.claude-plugin/README.md`. `README.md`, `AGENT_GUIDELINES.md` and `ARCHITECTURE_CONTRACTS.md` stay countable because they carry real content, and line overlap already limits their noise.
- PO default, pending owner review (fix pattern): a follow-up needs the old fix-style subject (`^([Rr]evert|fix|Fix|hotfix)`, unchanged) in both the `#N` rule and the line rule, so the comparison isolates the line and `#N` change. A non-fix commit that names `#N` (a trail stamp, a doc link) never counts.
- PO default, pending owner review (lines): only modified or deleted PR lines count. A pure insertion next to the PR's hunk does not.
- PO default, pending owner review (CI label, replaces OQ-E4): no `ci_failed_after_merge` in v1. Labels stay git-only and reproducible offline, and post-merge check runs on this repo are sparse and flaky-prone.
- PO default, pending owner review (bounds, OQ-E5): `--limit 50`, window 14 days, and the window also bounds reverts.
- PO default, pending owner review (OQ-E6, OQ-E7): only replays are scored, not recorded `gate-eval` lines. PRs merged into another base are skipped and counted.
- PO default, pending owner review (`/insights`): no `/insights` section in v1. The trend file is the record, and a section can follow once the coverage is known to be readable.
- PO default, pending owner review (evidence location): the label comparison goes in the committed `docs/evidence/outcome-label-sharpening.md`, following the `docs/evidence/` precedent. It holds label rates and the PR list used, never a gate score.

## Priority: MVP
**Rationale:** The gate can't be scored until a label separates PRs. Part 1 is useful on its own as a sharper outcome signal, and Part 2 is the measurement R2 exists for.

## Assumptions
- `git blame` at the follow-up's parent attributes lines to the landing (squash) or the branch commits (true merge) on this repo's history, renames included. Fixture cases cover both landings and a rename.
- The PR list for the comparison comes from the `pr_url` values in the session_end lines behind `build-loop-evidence.sh`'s runs. The evidence doc records that list, so the comparison can be reproduced without changing the old script.
- The scratch clone can hold the merge commit and the PR head (story 12 requires the merge commit in `--root`'s object store, and fetching the head ref is R2's job). A PR whose head ref is gone is `unscorable/head_unavailable`, counted in coverage.
- `.supervisor/eval/` is already "never deleted" in `retention-sweep.sh`'s policy table. The new files fall under it with no table edit.
- New `loomwright/scripts/test-*.sh` files are picked up by the CI and `ci-local.sh` globs with no registration.
- No test or cache writer needs a lock. If one is added, it uses an O_EXCL create (`check-mkdir-lock.sh`).

## Dependencies
- Depends on: `12-merge-verdict-replay-mode-judges-a-merged-pr-head.md` (Part 2's `merge-verdict --replay`; it in turn depends on story 05). Part 1 does not depend on it and can be built and merged first if the story is split at Launch Pad.
- Blocks: R3 (deferred).

## Risks
- **A thin replay.** With story 12's default classes, only condition 2's base check and condition 6 are `sha_fixed`, so `would_pass` means "today's sha-fixed conditions pass". Mitigation: coverage and the `sha_fixed` / `not_replayable` totals are printed beside every score, and the report says the score is advisory.
- **The new label may under-count.** It misses non-fix subjects and pure insertions, so it can read "stayed" for a real follow-up. Mitigation: `by`, `evidence_sha` and `--summary` make every bad label inspectable, and the evidence doc shows both rates and the clusters.
- **Small samples read as precise.** Mitigation: fractions with counts, `n/a`, coverage on every line.
- **Blame cost on large windows.** Mitigation: blame runs only on fix-style commits in the window that touch a PR file, and `--limit` plus the verdict cache bound the work.

## Validation (must pass before merge)
1. **Static — label suite:** `bash loomwright/scripts/test-outcome-label.sh` passes, including its mutants and the `build-loop-evidence.sh` byte-identity guard. `bash loomwright/scripts/test-build-loop-evidence.sh` passes unchanged.
2. **Static — eval suite:** `bash loomwright/scripts/test-replay-eval.sh` passes, including the CI refusal, the GET-only `gh` log, the meta-sync managed-set check and the mutants.
3. **Static — repo gates:** `bash scripts/ci-local.sh --affected` passes (incl. `check-test-hermetic.sh`, `check-mkdir-lock.sh`, `test-result-schemas-split.sh`, `check-doc-currency.sh`). `bash scripts/check-version-bump.sh` passes with a `changelog.d/` fragment. No version file is hand-edited.
4. **Running system — label discriminates on this repo:** on one HEAD and date, run `build-loop-evidence.sh --jsonl` and `outcome-label.sh --summary` over the same runs' PRs. `docs/evidence/outcome-label-sharpening.md` records the old not-durable rate (48/56 at the owner's count, re-read at that HEAD), the new bad rate, the per-commit clusters under both (whether `4f855bb` and `660fddd` still cluster), the PR list and the HEAD sha.
5. **Running system — one local eval, read-only:** with `CI` unset, `replay-eval.sh --limit 5` on this repo prints a report and one `REPLAY_EVAL_RESULT` with coverage. A `gh` wrapper that logs argv shows GET reads only. The caller's checkout and `git worktree list` are unchanged, and the two `.supervisor/eval/replay-*.jsonl` files exist. The numbers stay local and are not pasted into the PR body.

## Depends on
12-merge-verdict-replay-mode-judges-a-merged-pr-head.md

## Touches
loomwright/scripts/outcome-label.sh
loomwright/scripts/test-outcome-label.sh
loomwright/docs/outcome-label-ignore.json
loomwright/scripts/replay-eval.sh
loomwright/scripts/test-replay-eval.sh
loomwright/docs/result-schemas/replay-eval-result.md
loomwright/docs/RESULT_SCHEMAS.md
docs/evidence/outcome-label-sharpening.md
changelog.d/replay-eval-sharp-outcome-label.md

## Changes since the source was written
- **Label rebuilt, not extracted.** The source extracted `build-loop-evidence.sh`'s revert/fix heuristic into a shared library and kept it as `follow_up_fix (heuristic)`. That label marks 49 of 57 runs bad on this checkout and clusters on single release commits, so it is replaced, for this eval only, by a line-level / `#N` label with a data ignore list. The old script stays byte-identical (its matcher is frozen for the SPIKE verdicts).
- **Premise corrected:** the old label is not "any commit touching the same files". It requires a revert/fix-style subject (`^([Rr]evert|fix|Fix|hotfix)`) and checks at most 50 candidates. File-level overlap is still the cause of the clustering.
- **Interface follows stories 05 and 12:** `gate-verdict … --replay` became `automate-helpers.sh merge-verdict <url> --replay --root <clone>`, reading `replay_conclusion`, `replay_reason`, `replay_class` and `not_replayable` from `TRUSTED_MERGE_VERDICT`. Story 12 leaves producing the scratch clone to this item and refuses in CI itself; this item refuses earlier, before any `gh` call.
- **Dropped:** the `ci_failed_after_merge` label and the `/insights` section (PO defaults above). The source's touch of `build-loop-evidence.sh` is gone.
- **Added:** `pending` resolving across runs without a re-replay, `unknown` reasons, the CI refusal, the GET-only and meta-sync checks (meta-sync syncs `.supervisor/eval/results.jsonl` and `brain-baseline.jsonl` by exact path, so the new files must stay outside that list), and the no-public-claims check.
- **Shipped since 10-30 (reused as patterns, not touched):** v17.25.0's `build-feature-scorecard.sh` (registry as data, `unknown` never 0) and the `phase45-reviewer` replay suite (replays the reviewer, not the gate). `resolve-base-branch.sh` is used for the base. The `mkdir`-lock gate (v17.32.0) applies to any lock this item adds.
- **Touches made concrete:** no fixture directory (fixtures are built in the tests' temp dirs). `test-insights.sh` / `build-insights.sh` are gone with the `/insights` section. `ARCHITECTURE_CONTRACTS.md`, `prompt-token-budgets.json` and `retention-sweep.sh` are not edited (no prompt file changes, and the eval retention row already covers the new files).
