# Gate verdict mode judges any PR head without merging

## Status: pending

Source: `loomwright-archive/requirements/gate/2026-10-30-063943-gate-verdict-mode-judges-any-pr-head-without-merging.md` (plan doc `_BACKLOG-2026-10-30-063943-gate-verdict-required-check.md`, item 2a). Refreshed against main `8ec200e` / v17.35.1.

**As the** owner (Vikash) choosing which PR to merge, including a winner VS Code's Judge picked among competing heads after `/verify` ran on it,
**I want** to ask the trusted-merge gate "would you merge this head, and if not, why?" on any PR, and get every condition's answer at once from the same code that merges, with no way for it to merge,
**so that** I can judge any PR head by the gate's own rules, and the answer is never a second, drifting copy of the gate.

### Problem (read on main `8ec200e`)

- `automate-helpers.sh` `gate_eval()` is the only executor of `gh pr merge --squash` (CLAUDE.md §"Failure-Mode Invariants"; `skills/automate-loop/invariants.md` §11). It prints one line and stops at the first failing condition, so no full per-condition answer exists.
- It needs a ctx.json from an owned drain, so a PR with no `/automate` behind it (a Judge winner) cannot be judged at all.
- No mode answers "would it merge?" without merging.

### Scope

- A new subcommand `merge-verdict <pr_url> [--ctx <ctx.json>] [--verify-run <dir>] [--root <checkout>]` in `automate-helpers.sh`, beside `gate-eval`, with its `#:` usage line in the `hdr-gate` help segment.
- **One implementation.** The conditions in `gate_eval()` are factored into per-condition functions that both modes call in the same order; `gate-eval` stops at the first park as today, `merge-verdict` runs them all. The `gh pr merge` call stays only in `gate-eval`'s all-pass branch. A copied or re-derived condition is a defect.
- **Output:** one JSON object, `TRUSTED_MERGE_VERDICT` `schema_version: 1`, built with `jq --arg/--argjson`, documented in a new `docs/result-schemas/trusted-merge-verdict.md` and indexed in `docs/RESULT_SCHEMAS.md`. Fields: `pr_url`, `head_sha` (live head judged, or null), `base`, `ts`, `would_merge` (boolean), `park_reason` (the exact text `gate-eval` would print after `PARK: ` for the same inputs, or null), `conditions` (one entry per condition in gate order: `id`, `status` = `pass` / `fail` / `unreadable` / `not_run` / `not_applicable`, `reason`), `flags` (item 04's bypass-actor flag names), `verify` (`status` = `current` / `stale` / `not_run`, `run_dir`, `counts_row`). Condition ids come from the gate code; the doc and suite read them from there, never a restated count.
- **Any PR head.** `--ctx` is optional. Without it, the drain-backed conditions (1, 1b, 1c, the drain cross-check, the rubric read) are `not_run` with a reason naming the missing owned drain, and every live-read condition (2–7) is still evaluated. With it, they are evaluated exactly as `gate-eval` does, and the gate-owned-key refusal applies unchanged.
- `would_merge` is true only when every condition is `pass` or `not_applicable`; any `fail`, `unreadable` or `not_run` ⇒ false.
- **`/verify` row, advisory:** the newest `.supervisor/verify/<run>/` under `--root` whose `run_start` line in `evidence.jsonl` has `head_sha` equal to the judged head (or `--verify-run <dir>`), showing the `PASS: …` counts row of its `summary.md` byte for byte, marked `current`; a run at another head is `stale`; none is `not_run`. It never changes `would_merge`, and `merge-verdict` never spawns `/verify`.
- **Read-only.** No `gh pr merge`, no non-GET `gh` call, no checkout, reset or write outside its own temp files. Condition 7's checkout pin applies as in `gate-eval`.
- **Docs:** a short "verdict mode" paragraph in `modes-and-merge-gate.md` §10 pointing at the schema doc, a `helpers.md` row, a loop-inventory row, `gate_eval()`'s header naming the shared condition functions, a `changelog.d/` fragment.

## Acceptance Criteria

All cases use the stubbed-`gh` gate harness of `scripts/test-automate-helpers.sh` in a new leg `test-automate-helpers.d/20-merge-verdict.sh`. No network.

**Happy path**
- [ ] On the harness fixture where `gate-eval` prints `MERGE`, `merge-verdict` (same PR, ctx, root) prints one object with `would_merge: true`, `park_reason: null`, every condition `pass` (or `not_applicable` for an absent rubric line), and the stub `gh` logs zero `pr merge` calls and zero non-GET calls. Test: `20-merge-verdict.sh`.
- [ ] For every single-condition PARK fixture in `05-gate-eval.sh` and `06-gate-eval-tail.sh` (item 04's included), `merge-verdict` gives `would_merge: false` and `park_reason` equal to `gate-eval`'s `PARK:` text for that fixture byte for byte. The leg loops over the fixtures, so the modes cannot drift. Test: `20-merge-verdict.sh`.
- [ ] A fixture failing two conditions (`unresolved_human_thread` and `high_risk_diff`) reports both as `fail`; `park_reason` is the earlier one in gate order. Test: `20-merge-verdict.sh`.
- [ ] No `--ctx` (a stub Judge winner): drain-backed conditions `not_run` with a reason naming the missing owned drain, live-read conditions still evaluated and reported, `would_merge: false`. Test: `20-merge-verdict.sh`.
- [ ] A verify run whose `run_start.head_sha` equals the live head and whose row is `PASS: 3 · FAIL: 0 · BLOCKED: 0 · NOT_VERIFIABLE: 1 · total: 4` ⇒ shown byte for byte, `current`; another head ⇒ `stale`; none ⇒ `not_run`; `would_merge` identical in all three. Test: `20-merge-verdict.sh`.
- [ ] Every key of the output object is one listed in `trusted-merge-verdict.md`; the leg reads the field list from the doc. Test: `20-merge-verdict.sh`.

**Edge cases**
- [ ] A ctx carrying a gate-owned key ⇒ `ctx_carries_gate_owned_key`, `would_merge: false`, the same refusal as `gate-eval`. Test: `20-merge-verdict.sh`.
- [ ] A PR whose base is not `main` ⇒ condition 2 `fail` with `base_not_main`, `would_merge: false`. Test: `20-merge-verdict.sh`.
- [ ] A `--root` not at the live head ⇒ condition 7 `fail` with `rules_gate_head_mismatch`, `rules-gate-verdict.sh` not called, `git status` and HEAD of the checkout identical before and after. Test: `20-merge-verdict.sh`.
- [ ] A classify-risk reason naming a file with `"`, a backtick, `-->` or a newline ⇒ still one valid JSON object carrying the text literally. Test: `20-merge-verdict.sh`.

**Error scenarios**
- [ ] Every `gh` read failing ⇒ each dependent condition `unreadable`, `would_merge: false`, exit 0. Test: `20-merge-verdict.sh`.
- [ ] `jq` missing ⇒ one stderr line naming it, empty stdout, non-zero exit (empty output is never a verdict); the schema doc says so. Test: `20-merge-verdict.sh`.
- [ ] Gated mutants: (a) `merge-verdict` reaching the merge call, (b) `not_run` or `unreadable` mapped to `would_merge: true`, (c) one mode's condition function differing from the other's — the suite fails on each. Test: `20-merge-verdict.sh`.
- [ ] Every pre-existing gate case (`05-gate-eval*`, `06-gate-eval-tail`, the `gate-eval-*` next-step goldens) passes unchanged after the factoring. Test: `test-automate-helpers.sh`, `test-automate-next-step.sh`.
- [ ] `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` prints only the §11-sanctioned surfaces (the new schema doc and help line add no positive hit). Test: `test-automate-next-step.sh` leg S.
- [ ] The real dispatcher's `--help` equals the per-segment goldens with the new `merge-verdict` line. Test: `test-automate-helpers-dispatch.sh`.

## Non-goals
- Posting the verdict anywhere: the check run through a GitHub App (2b) and its `/automate` wiring and drain exclusion (2c) are DEFERRED.
- A `neutral` conclusion or any check-run vocabulary: it existed only for GitHub's required-check semantics in 2b/2c.
- Any change to `gate-eval`'s decision, stdout line, order or park reasons.
- Auto-discovering drain results for an arbitrary PR (the drain writes no PR-keyed index).
- Making `/verify` decide `would_merge`.
- Wiring the verdict into the scorecard (`pr-scorecard.sh` has not landed on main).

## Owner decisions
- 2026-11-09 (Vikash, in chat): APPROVED from the archive review; refreshed against main 8ec200e / v17.35.1.
- 2026-11-09 (Vikash, in chat): runs after item 04; the same condition code as `gate-eval`, never a second implementation; no merge path; verdict JSON. Items 2b and 2c are DEFERRED, and anything here that only served them is removed.
- 2026-10-30 (Vikash, in the set request): any PR head, no live Judge or App needed; `/verify` on the winner is recorded as an input and testable with stubs; verdict-only, never merges, approves or pushes.
- PO default, pending owner review (naming): subcommand `merge-verdict`, schema `TRUSTED_MERGE_VERDICT` in `docs/result-schemas/trusted-merge-verdict.md`. `GATE_VERDICT` / `gate-verdict.md` already belong to the QA Strategist's gate audit, and `rules-gate-verdict.sh` is condition 7's helper, so the source's `gate-verdict` names would clash with both.
- PO default, pending owner review (replaces OQ-G2): output is `would_merge` plus `park_reason`, with no `success`/`failure`/`neutral` conclusion; a non-`main` base is a plain condition-2 `fail`, as in `gate-eval`.
- PO default, pending owner review (OQ-G1): drain inputs only through an explicit `--ctx` (the source's separate `--review-heal-result` / `--supervisor-result` flags are dropped: the ctx already carries both paths); absent ⇒ `not_run` ⇒ `would_merge: false`.
- PO default, pending owner review (OQ-G3): the `/verify` row is advisory, never changes `would_merge`, never spawned.

## Priority: MVP
**Rationale:** It answers "would the gate merge this head?" safely on any PR, from the gate's own code, and is the only safe base for 2b/2c if they are ever un-deferred.

## Assumptions
- `gate_eval()`'s conditions can be factored into functions without changing any `gate-eval` output; the existing gate suites and goldens staying green is the proof.
- The live reads (conditions 2–7) do not depend on ctx except condition 2's `ready_sha` cross-check; without ctx that check reports `not_run` while `base_not_main` is still judged.
- `verify-run.sh` keeps writing `run_start` as a line of `<run_dir>/evidence.jsonl` and the counts row as the first `^PASS: ` line of `summary.md` (read 2026-11-09).

## Dependencies
- Depends on: `04-gate-condition-4-reads-rulesets-and-flags-bypass-actors.md` (shares condition 4's new reads and flags; factoring first would refactor code item 04 then rewrites).
- Blocks: nothing queued (2b/2c deferred).

## Risks
- **Refactoring the sole merge executor's file.** The merge call stays in one branch of `gate-eval`; the stub fails the suite on any merge from the verdict path; `classify-risk.sh` marks the diff high-risk, so the owner merges it.
- **A verdict read as authority.** `would_merge: true` still needs an owned drain's ctx; a Judge winner without one is always false, by design.
- **Token budget.** `skills/automate-loop` has ~4,200 tokens of headroom, shared with item 04's doc growth; `check-token-budget.sh` fails closed, and the budget row then moves in the same change.

## Validation (must pass before merge)
1. **Static — gate suites:** `bash loomwright/scripts/test-automate-helpers.sh` (new leg `20-merge-verdict` plus the unchanged `05-gate-eval*`, `06-gate-eval-tail`), `bash loomwright/scripts/test-automate-next-step.sh` and `bash loomwright/scripts/test-automate-helpers-dispatch.sh` pass.
2. **Static — repo gates:** `bash scripts/ci-local.sh --affected` passes (incl. `test-result-schemas-split.sh`, `check-doc-currency.sh`, `test-loop-inventory.sh`, `check-prompt-history-refs.sh`, `check-token-budget.sh`, `check-test-hermetic.sh`); `bash scripts/check-version-bump.sh` passes with a `changelog.d/` fragment; no version file is hand-edited.
3. **Static — merge invariant:** `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` lists only §11-sanctioned surfaces.
4. **Running system — one real PR, read-only:** `automate-helpers.sh merge-verdict <an open PR url> --root <checkout at its head>` on one of the owner's repos prints one valid object with drain-backed conditions `not_run`, `would_merge: false`, and `gh` is called with GET reads only (run once under a `gh` wrapper that logs argv); the output is pasted in the PR description.

## Depends on
04-gate-condition-4-reads-rulesets-and-flags-bypass-actors.md

## Touches
loomwright/scripts/automate-helpers.sh
loomwright/scripts/test-automate-helpers.sh
loomwright/scripts/test-automate-helpers.d/20-merge-verdict.sh
loomwright/scripts/fixtures/automate-helpers-help/hdr-gate.golden
loomwright/docs/result-schemas/trusted-merge-verdict.md
loomwright/docs/RESULT_SCHEMAS.md
loomwright/skills/automate-loop/modes-and-merge-gate.md
loomwright/skills/automate-loop/helpers.md
loomwright/docs/loop-inventory/automate-loop.md
changelog.d/gate-merge-verdict-mode.md

## Changes since the source was written
- **Name clash resolved:** `docs/result-schemas/gate-verdict.md` (`GATE_VERDICT`) is the QA Strategist's gate audit, and `rules-gate-verdict.sh` is condition 7's helper. The subcommand is now `merge-verdict` and the schema `TRUSTED_MERGE_VERDICT`.
- **2b/2c deferred, their parts removed:** the `success`/`failure`/`neutral` conclusion and its "neutral satisfies a required check" assumption existed only for the check run; replaced by `would_merge` + `park_reason`.
- **Inputs simplified:** `--review-heal-result` / `--supervisor-result` dropped; `--ctx` carries both paths, as `gate-eval`'s does.
- **Gate changes since the source** (v17.33–v17.35): the paid-plan 403 and empty-required-list rollup read (`3a6cb32`) and the empty `reviewDecision` read as `none` (`742046c`) are inside the condition code this item shares, so the verdict inherits them with no extra work; `--merge-parked` (v17.33) still goes through `gate-eval` only.
- **Scorecard:** `pr-scorecard.sh` has not landed, so no `/verify` reader is shared yet; this item's reader is the one a later scorecard reuses.
- **Touches made concrete:** the new leg file and the `hdr-gate` help golden (`test-automate-helpers-dispatch.sh` compares `--help` byte for byte) replace the source's directory entry.
