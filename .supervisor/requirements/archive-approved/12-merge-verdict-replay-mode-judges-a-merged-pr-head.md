# Merge-verdict replay mode judges a merged PR head

## Status: pending

Source: `loomwright-archive/requirements/batchA/2026-10-30-070224-gate-verdict-replay-mode-judges-a-merged-pr-head.md` (plan doc `_BACKLOG-2026-10-30-070224-batch-a-replay-evals-and-narrow-worker-tokens.md`, item R1). Rebased onto story 05 (`merge-verdict`, `TRUSTED_MERGE_VERDICT`). Refreshed against main `8ec200e` / v17.35.1.

**As the** owner (Vikash), who wants to know how often the trusted-merge gate is right,
**I want** to ask `merge-verdict` "what would you say about this already-merged PR's final head?", answered by the same condition code that merges, with every condition that cannot be judged after the fact marked as such and kept out of the answer,
**so that** merged PRs can be replayed and later scored (item R2, the PR scorecard of story 10) without a second, drifting copy of the gate and without counting a condition read from today's state as a historical pass.

### Problem (read on main `8ec200e`)

- `automate-helpers.sh` `gate_eval()` is the only gate code and the only `gh pr merge --squash` executor. Story 05 (not built) factors its conditions into functions shared with a read-only `merge-verdict`. Neither mode separates inputs fixed by a PR's final head from inputs that are only true now.
- On a merged PR most conditions read **today's** state, not the state at merge: `reviewDecision` and the review threads (condition 3; on Loomwright's own repo `main` requires one human approval, so a merged PR reads the post-merge `APPROVED`), branch protection and, after story 04, rulesets and bypass actors (condition 4), the required-check list taken from that protection payload (condition 5), and the machine-local human stamp `rules-gate-verdict.sh` replays (condition 7, `--gate-state` / `--if-stamped`). The drain-backed conditions (1, 1b, 1c, the drain cross-check, the rubric read, condition 2's `ready_sha` match) need an owned drain's ctx that a past PR usually no longer has.
- Condition 6 runs `classify-risk.sh origin/<base> <head> --root <root>`, and `classify-risk.sh` diffs three-dot (`git diff <base>...<head>`). After a **merge-commit** merge the head is an ancestor of `origin/main`, so the three-dot diff is empty and the risk reads low: replaying condition 6 against `origin/<base>` would pass a high-risk PR. The base the PR merged into is the merge commit's first parent (true for squash, merge-commit and rebase merges: in each its history holds the base tip at merge time). `classify-risk.sh` also reads `.agent/risk.json` at `<base_ref>`, so with that base the project risk rules are the ones in force at merge.
- A separate replay script re-judging these inputs would be a second gate implementation; story 05 and the scorecard's OQ-1 both reject that.

### Scope

- An additive flag on story 05's subcommand: `merge-verdict <merged_pr_url> --replay [--root <checkout>]`. Its `#:` usage line in the `hdr-gate` help segment names the flag.
- **One implementation.** The replay calls the same per-condition functions as `gate-eval` and `merge-verdict`, in gate order. The only replay-specific inputs are (a) the PR's merge facts from one extra GET read (`gh pr view <url> --json state,mergedAt,mergeCommit,headRefOid,baseRefName`) and (b) condition 6's base argument, which is `<mergeCommit.oid>^1` instead of `origin/<base>`. Condition functions take the base as an argument; none is copied or re-derived.
- **Class tags in the gate code, one place.** One table in `automate-helpers.sh` gives every condition id `merge-verdict` emits exactly one class: `sha_fixed` (every input is fixed by the PR's final head and the merge commit's first parent) or `live_state` (any input is only knowable now or at the time). A condition with any live input is `live_state`. The schema doc and the suite read the table; no other surface restates it or its count. PO default classes, pinned by the suite: condition 2's base-is-`main` check and condition 6 (base resolution plus risk class) are `sha_fixed`; every other condition, including the drain-backed ones, is `live_state`. If story 05's ids do not separate condition 2's base check from its `ready_sha` match, this item splits that id without changing any `gate-eval` output.
- **`live_state` is reported, not scored.** In a replay every `live_state` condition gets `status: not_replayable` and a `reason` naming why (for example `post_merge_review_state`, `protection_read_today`, `machine_local_rules_stamp`, `owned_drain_state`). Where the function can still run read-only (conditions 3, 4, 5, 7), its result today is shown as `observed_now` (`status` and `reason`, as the function returned them), labelled as today's read. Drain-backed conditions do not run (`observed_now: null`). No `observed_now` value ever enters `replay_conclusion`, `would_merge` or `park_reason`.
- **Output:** story 05's `TRUSTED_MERGE_VERDICT` object, with additive fields documented in `trusted-merge-verdict.md`: `mode` (`"replay"`; the doc says it is absent or `"live"` otherwise, matching whatever story 05 lands), `merged_at`, `merge_commit_sha`, `replay_base` (the commit used as condition 6's base), `replay_conclusion`, and per condition `replay_class` and `observed_now`. In a replay `would_merge` is always `false` and `park_reason` is the exact `PARK:` text of the first `sha_fixed` condition that is `fail`, else `null`.
- **`replay_conclusion`:** `would_block` if any `sha_fixed` condition is `fail`; else `unscorable` if any `sha_fixed` condition is `unreadable` or `not_run`, or none ran; else `would_pass` (every `sha_fixed` condition `pass` or `not_applicable`). A PR that is not merged (open, or closed without merging) or whose merge facts cannot be read gives one object with `replay_conclusion: "unscorable"` and a top-level `replay_reason` (`pr_not_merged` / `pr_state_unreadable`), and no condition is evaluated.
- **Read-only and local.** No `gh pr merge`, no non-GET `gh` call, no `git fetch`, checkout, reset or write in `--root` or the caller's checkout, nothing written outside its own temp files, nothing posted. The merge commit must already be in `--root`'s object store; otherwise condition 6 is `unreadable` (`replay_base_unavailable`). Producing a scratch clone at the head is R2's job, by throwaway clone, never `git worktree add`.
- **Never in CI.** `--replay` with `CI` or `GITHUB_ACTIONS` set non-empty refuses: one stderr line, empty stdout, non-zero exit, no `gh` call. No workflow under `.github/workflows/` invokes it.
- `--replay` with `--ctx` or `--verify-run` is a usage error (one stderr line, empty stdout, non-zero): a past ctx is not replayed in v1.
- **Docs:** one sentence on the flag in `modes-and-merge-gate.md` §10's verdict-mode paragraph pointing at the schema doc, story 05's `helpers.md` row and loop-inventory row name the flag, a `changelog.d/` fragment.

## Acceptance Criteria

All cases live in a new leg `scripts/test-automate-helpers.d/21-merge-verdict-replay.sh`, registered in `test-automate-helpers.sh`, using the stubbed-`gh` gate harness (`05-gate-eval-harness.sh`): its `gh` stub learns the `state,mergedAt,mergeCommit,...` view, and every merged-PR fixture is built inside the harness's temp dir with real commits in `E_ROOT` (a squash fixture and a merge-commit fixture). No network. Every case except the CI-refusal one runs under `env -u CI -u GITHUB_ACTIONS`, so the leg passes on GitHub Actions.

**Happy path**
- [ ] Squash-merged fixture, low-risk diff, `--root` at the head: `merge-verdict <url> --replay --root <E_ROOT>` prints one object with `mode: "replay"`, the fixture's `merged_at` and `merge_commit_sha`, `replay_base` = the merge commit's first parent, `replay_conclusion: "would_pass"`, every `sha_fixed` condition `pass`, every `live_state` condition `not_replayable` with a non-empty `reason`, `would_merge: false`, `park_reason: null`; the stub logs zero `pr merge` calls and zero non-GET calls. Test: `21-merge-verdict-replay.sh`.
- [ ] Same fixture with a high-risk diff (a `.claude/` path): condition 6 `fail`, `park_reason` equals byte for byte the `PARK:` text `gate-eval` prints for that head and base, `replay_conclusion: "would_block"`. Test: `21-merge-verdict-replay.sh`.
- [ ] Merge-commit fixture with a high-risk diff, where the leg first asserts `git diff --name-only origin/main...<head>` is empty: the replay still reads condition 6 `fail` and `would_block`, because it judged against the merge commit's first parent. Test: `21-merge-verdict-replay.sh`.
- [ ] Live state reported, not scored: on the would-pass fixture, the leg varies each live read in turn (today's `reviewDecision` `APPROVED` vs `CHANGES_REQUESTED`, an unresolved human thread, protection 404, a red required check, a failing rules verdict); each shows in that condition's `observed_now`, and `replay_conclusion`, `would_merge` and `park_reason` are identical across every variant. Test: `21-merge-verdict-replay.sh`.
- [ ] Tags in one place: the leg reads the condition ids from `merge-verdict`'s own output and the classes from the gate code's table; every id has exactly one class from {`sha_fixed`, `live_state`}, and the condition-2 base check and condition 6 are `sha_fixed`. `trusted-merge-verdict.md` points at the table and lists no class per id. Test: `21-merge-verdict-replay.sh`.
- [ ] Every key of a replay object, top level and per condition, is listed in `trusted-merge-verdict.md` (story 05's field-list read, extended to the replay fields). Test: `21-merge-verdict-replay.sh`.

**Edge cases**
- [ ] An open PR, and a PR closed without merging: one object, `replay_conclusion: "unscorable"`, `replay_reason: "pr_not_merged"`, no condition evaluated, exit 0. Test: `21-merge-verdict-replay.sh`.
- [ ] A merge commit absent from `--root`'s object store: condition 6 `unreadable` with `replay_base_unavailable`, `replay_conclusion: "unscorable"`, and `--root`'s refs, object count, HEAD and `git status --porcelain` are identical before and after (no fetch). Test: `21-merge-verdict-replay.sh`.
- [ ] Caller's checkout untouched: across every case, the HEAD, refs and `git status --porcelain` of the directory the leg runs from and of `--root` are identical before and after. Test: `21-merge-verdict-replay.sh`.
- [ ] `--replay --ctx <file>` and `--replay --verify-run <dir>`: one stderr line, empty stdout, non-zero exit, no `gh` call. Test: `21-merge-verdict-replay.sh`.
- [ ] Same code, same answer: for the squash fixture's head, a non-replay `merge-verdict` on an open-PR variant whose `origin/main` is the merge commit's first parent gives condition 6 the same `status` and `reason` as the replay. Test: `21-merge-verdict-replay.sh`.

**Error scenarios**
- [ ] Every `gh` read failing: one object, `replay_conclusion: "unscorable"`, `replay_reason: "pr_state_unreadable"`, exit 0. Test: `21-merge-verdict-replay.sh`.
- [ ] `CI=true`, and separately `GITHUB_ACTIONS=true`: refused with one stderr line, empty stdout, non-zero exit, zero `gh` calls. No file under `.github/workflows/` contains `merge-verdict`. Test: `21-merge-verdict-replay.sh`.
- [ ] Gated mutants, each failing the leg: (a) a `live_state` condition's status counted in `replay_conclusion`; (b) condition 6 handed `origin/<base>` in a replay; (c) a condition id missing from the class table; (d) the replay path reaching the merge call; (e) `unreadable` on a `sha_fixed` condition mapped to `would_pass`. Test: `21-merge-verdict-replay.sh`.
- [ ] Every pre-existing gate case passes unchanged: `05-gate-eval*`, `06-gate-eval-tail`, story 05's `20-merge-verdict`, and the `gate-eval-*` next-step goldens. Test: `test-automate-helpers.sh`, `test-automate-next-step.sh`.
- [ ] `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` prints only the surfaces `skills/automate-loop/invariants.md` §11 sanctions. Test: `test-automate-next-step.sh` leg S.
- [ ] The real dispatcher's `--help` equals the per-segment goldens with the `--replay` flag in the `merge-verdict` line. Test: `test-automate-helpers-dispatch.sh`.

## Non-goals
- Selecting PRs, scoring replays, keeping history or producing the scratch clone (item R2).
- Showing the verdict or a score anywhere: the PR scorecard (story 10) carries it later; the score in a check run's output (R3) stays deferred, and no GitHub App or check run is used (gate 2b/2c).
- Reconstructing historical live state (review threads, protection or rulesets at merge time, the stamp then); it stays `not_replayable`.
- Replaying a past drain's ctx.
- Any change to `gate-eval`'s or non-replay `merge-verdict`'s decision, stdout, condition order or park reasons.
- Running the gate code of the plugin version that judged the PR at the time; a replay applies today's condition code.

## Owner decisions
- 2026-11-09 (Vikash, in chat): R1 un-deferred and decoupled from gate 2b/2c; refreshed against main 8ec200e / v17.35.1.
- 2026-11-09 (Vikash, in chat): the same condition code on a merged PR's final head, never a second implementation of any condition; classes `sha_fixed` vs `live_state` tagged in the gate's own code; results `would_block` / `would_pass` / `unscorable` with which conditions could not be replayed and why; no merge path, the §11 grep stays satisfied; offline-friendly where possible, nothing leaves the machine, never runs in CI; the verdict reaches the PR through the scorecard (story 10) later; R3 stays deferred.
- PO default, pending owner review (naming): a `--replay` flag on story 05's `merge-verdict`, fields added to `TRUSTED_MERGE_VERDICT` `schema_version: 1` (additive, present only in replay output), replacing the source's `gate-verdict` names.
- PO default, pending owner review (live state): `live_state` conditions are reported as `observed_now`, labelled as today's read, and never scored.
- PO default, pending owner review (classes): only condition 2's base check and condition 6 are `sha_fixed`. Condition 5 is `live_state` because its required list comes from today's protection and rulesets, and a check run can be re-run after merge. Condition 7 is `live_state` because the human stamp is machine-local. Alternative: score condition 5 from the rollup GitHub recorded on the head.
- PO default, pending owner review (base): condition 6's replay base is the merge commit's first parent; a missing merge commit is `unreadable`, never fetched.
- PO default, pending owner review (CI): a `CI` / `GITHUB_ACTIONS` refusal plus no workflow reference. This is a tripwire against accidental use, not a security control.
- PO default, pending owner review (conclusion order): a `sha_fixed` `fail` gives `would_block` even when another `sha_fixed` condition is `unreadable`.

## Priority: MVP
**Rationale:** R2 and the scorecard cannot score a replay that is not the gate's own judgement. The other options are a second gate copy, which is rejected, or scoring today's reads as historical, which is wrong.

## Assumptions
- `gh pr view --json state,mergedAt,mergeCommit,headRefOid,baseRefName` keeps returning the final head and the merge commit for a merged PR (the implementer records one capture from a real merged PR, with the read date).
- Story 05's factoring lets condition 6 take its base as an argument without changing any `gate-eval` output; the unchanged gate suites are the proof.
- Merging a PR does not change `classify-risk.sh`'s inputs beyond the diff range: its project rules come from `.agent/risk.json` at the base ref and its trusted-root list is a constant in the script.

## Dependencies
- Depends on: `05-gate-verdict-mode-judges-any-pr-head-without-merging.md` (`merge-verdict`, the shared condition functions, `trusted-merge-verdict.md`); transitively `04-gate-condition-4-reads-rulesets-and-flags-bypass-actors.md`.
- Blocks: item R2 (replay scoring) and the scorecard's replay row (story 10).

## Risks
- **Touches the sole merge executor's file.** The flag lives on the non-merging subcommand only; mutant (d) and the §11 grep guard it; `classify-risk.sh` marks the diff high-risk, so the owner merges it.
- **Thin replayable set.** With the default classes a replay scores the base and the risk class only, so `would_pass` means "today's sha-fixed conditions pass", not "the gate would have merged". R2 reports coverage beside every score.
- **Today's code on old heads.** A risk rule added after a PR merged judges that PR; R2 records the plugin version with each replay.
- **Token budget.** `skills/automate-loop` headroom is shared with stories 04 and 05. If `check-token-budget.sh` fails, the budget row moves in the same change, and `loomwright/docs/prompt-token-budgets.json` plus its `ARCHITECTURE_CONTRACTS.md` row join this story's Touches.

## Validation (must pass before merge)
1. **Static — gate suites:** `bash loomwright/scripts/test-automate-helpers.sh` (new leg `21-merge-verdict-replay` plus the unchanged `05-gate-eval*`, `06-gate-eval-tail`, `20-merge-verdict`), `bash loomwright/scripts/test-automate-next-step.sh` and `bash loomwright/scripts/test-automate-helpers-dispatch.sh` pass.
2. **Static — repo gates:** `bash scripts/ci-local.sh --affected` passes (incl. `test-result-schemas-split.sh`, `check-doc-currency.sh`, `test-loop-inventory.sh`, `check-prompt-history-refs.sh`, `check-token-budget.sh`, `check-test-hermetic.sh`); `bash scripts/check-version-bump.sh` passes with a `changelog.d/` fragment; no version file is hand-edited.
3. **Static — merge invariant:** `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` lists only §11-sanctioned surfaces.
4. **Running system — one real merged PR, read-only:** `automate-helpers.sh merge-verdict <a merged loomwright PR url> --replay --root <throwaway clone at its head>`, run locally with `CI` unset and once under a `gh` wrapper that logs argv, prints one valid object with `mode: "replay"`, condition 3's `observed_now` showing the post-merge approval and `not_replayable` status, and a `replay_conclusion`; the wrapper log shows GET reads only and the clone's `git status` and refs are unchanged. The output is pasted in the PR description.

## Depends on
05-gate-verdict-mode-judges-any-pr-head-without-merging.md

## Touches
loomwright/scripts/automate-helpers.sh
loomwright/scripts/test-automate-helpers.sh
loomwright/scripts/test-automate-helpers.d/05-gate-eval-harness.sh
loomwright/scripts/test-automate-helpers.d/21-merge-verdict-replay.sh
loomwright/scripts/fixtures/automate-helpers-help/hdr-gate.golden
loomwright/docs/result-schemas/trusted-merge-verdict.md
loomwright/skills/automate-loop/modes-and-merge-gate.md
loomwright/skills/automate-loop/helpers.md
loomwright/docs/loop-inventory/automate-loop.md
changelog.d/merge-verdict-replay-mode.md

## Changes since the source was written
- **Rebased onto story 05:** `gate-verdict` → `merge-verdict --replay`; the source's own `conclusion` / check-run framing is gone (05 has `would_merge` + `park_reason`, no `neutral`); the schema is `TRUSTED_MERGE_VERDICT` in `trusted-merge-verdict.md`, settling the source's OQ-E1 name clash.
- **Decoupled from 2b/2c (owner, 2026-11-09):** no App or check run; the verdict reaches the PR through story 10 later; R3 stays out.
- **New premise found:** `classify-risk.sh` diffs three-dot, so replaying condition 6 against `origin/<base>` reads a merge-commit-merged PR as an empty, low-risk diff. The replay base is now the merge commit's first parent, with a fixture that proves it.
- **Live state is reported, not scored:** the source left live-state conditions unevaluated; this item shows today's read as `observed_now` (for example Loomwright's post-merge human approval) and keeps it out of the conclusion.
- **Classes named by default:** the source deliberately listed no classes; this item proposes them (conditions 5 and 7 are `live_state`, reasons above), pinned by the suite and open to owner review.
- **Gate changes since the source** (v17.33–v17.35): the paid-plan 403 classifier, the empty-required-list rollup read and the empty `reviewDecision` read as `none` all sit inside `live_state` conditions here, so they show in `observed_now` and change no replay score. Story 04's ruleset and bypass reads are also `live_state`.
- **Added:** the CI refusal, the `--ctx` / `--verify-run` usage error, the not-merged and no-fetch cases, and concrete Touches (the leg file, the harness, the help golden) in place of the source's directory entries. `RESULT_SCHEMAS.md` is no longer touched: story 05 adds the index row.
