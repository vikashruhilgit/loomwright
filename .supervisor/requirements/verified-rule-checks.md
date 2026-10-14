# A rule's `check` must prove it can fail before it becomes a `must` rule

## Status: pending

## Source
VERSE (arXiv 2610.02616). Notes in `AI-Radar-All.md`. It is a self-evolving optimizer
for agent harnesses. Its main finding: self-edits kept without execution verification made results WORSE; with a
replay-before-keep step they beat every baseline. We take the idea only, not the tool (no task corpus here, few
human-approved edits). Drafted 2026-10-13 against main 508aabc.

## Depends on
none

## Touches
loomwright/scripts/prove-rule-check.sh
loomwright/scripts/test-prove-rule-check.sh
loomwright/scripts/add-rule.sh
loomwright/scripts/test-add-rule.sh
loomwright/skills/rules/SKILL.md
loomwright/commands/rules.md
loomwright/commands/dreaming.md
changelog.d/verified-rule-checks.md

## Touches notes (moved out of the machine-read section 2026-10-13)
- `prove-rule-check.sh` and `test-prove-rule-check.sh` are new files.
- `add-rule.sh`: D2 — `--proof` required for a `must` rule with a `check`.
- `skills/rules/SKILL.md`: §7 add discipline, §9 trust boundary.
- `commands/dreaming.md`: the "Accept rule WITH check" path.

## Problem
Loomwright edits its own instructions in two places: `/rules add` and `/dreaming`'s harvested-rule Accept. Both
write a `must` rule with a `check` that has **never been run**. `add-rule.sh` validates the rule's shape and
wording (`validate-entry.sh`), never its behaviour, and `audit-rules.sh` deliberately never executes a check.
The first execution is a later `/rules check --confirm`, and that only proves the check PASSES today.

A check that passes today proves nothing on its own. `true`, a grep for a token that is always present, or a
path typo that matches nothing all pass forever. Once a human stamps such a rule and it is gate-countable
(`binds`), `rules-gate-verdict.sh` counts it as a passing must-check. That is a green signal at Phase 4.5, the
drain and `gate-eval` condition 7 backed by a check that cannot fail. This is VERSE's failure mode exactly: an
instruction kept because it looked right, not because it was shown to work.

## Goal
A `must` rule with a `check` enters the store only with proof that its check **can tell right from wrong**:
1. **Holds now.** The check passes on the current tree.
2. **Catches a violation.** The check fails on a tree that breaks the rule.

Both results are shown to the human who approves the rule.

## Scope
1. **New `prove-rule-check.sh`.** Inputs: the check string, plus a **counterexample**: a patch file (D1) that
   introduces one violation of the rule. It:
   - runs the check from the repo root on the current tree → must exit 0;
   - applies the counterexample in a throwaway scratch copy (`git worktree add --detach` under the scratch dir,
     never the user's working tree), runs the check there → must exit non-zero;
   - removes the scratch copy, and verifies it is gone (the worktree-removal lesson: verify, then remove);
   - prints one verdict: `PROVEN`, `VACUOUS` (passes on both), `FAILS_NOW` (fails on the current tree), or
     `UNPROVABLE` (could not run: bad patch, worktree failed, timeout). Exit 0 only for `PROVEN`.
   Could-not-examine is never proven: every error path is `UNPROVABLE`, non-zero.
2. **Trust boundary unchanged.** This executes a `check`, which is arbitrary shell (`skills/rules/SKILL.md` §9),
   so it runs ONLY on the same human-confirmed path as `rules-check.sh --confirm`: it displays the check and the
   patch, and runs only after explicit confirmation. It writes NO stamp. Proving is not authorizing replay; the
   human still runs `/rules check --confirm` to stamp.
3. **Can't-ask branch.** Non-interactive or no confirmation ⇒ nothing runs, verdict `UNPROVABLE`
   (`needs_confirmation`). The rule is then not added as `must`; it may be added as `advisory` (D3).
4. **Wire the two callers.** `/rules add --enforcement must --check …` and `/dreaming`'s "Accept rule WITH check"
   run the proof before calling `add-rule.sh`. Only `PROVEN` proceeds to a `must` write. The verdict and both
   check outputs go in front of the human, and into the `/dreaming` rules PR body.
5. **Unchanged.** Advisory rules and `check: null` rules need no proof. Lessons (`LESSONS.md`) are prose and
   cannot be executed; out of scope (see Non-goals).

## Owner decisions (2026-10-13)
- **D1. Counterexample = a unified-diff patch file** the author supplies. It is applied only in the scratch copy.
- **D2. Enforced in `add-rule.sh`.** A `must` + `check` add requires `--proof <file>` written by
  `prove-rule-check.sh`. The writer re-hashes the check string and refuses a missing proof, a non-`PROVEN` proof,
  or a proof for a different check. The callers (`/rules add`, `/dreaming`) produce the proof first.
- **D3. A rule that fails proof is offered as `advisory`**, with the check kept as data. It never counts at a gate.
- **D4. Proof is recorded in the commit / PR body.** The rule schema stays frozen; no `proof` member.

## Acceptance criteria
- `check: true` + any counterexample ⇒ `VACUOUS`, no `must` rule written.
- A check that greps for a token, with a patch deleting that token ⇒ `PROVEN`, rule written.
- A check that fails on the current tree ⇒ `FAILS_NOW`, nothing written.
- A patch that does not apply, or a missing `git worktree` ⇒ `UNPROVABLE`, non-zero, nothing written.
- Non-interactive / no confirmation ⇒ the check never runs (a canary-file check proves it), verdict `UNPROVABLE`.
- After any verdict, `git worktree list` and `git status --porcelain` match their state before the run (no
  leaked scratch copy, user's tree untouched).
- No stamp file is written or changed by a proof run.
- `add-rule.sh --enforcement must --check X` with no `--proof`, or a proof for a different check
  string, is refused; advisory and `check: null` adds are unchanged.
- `CLAUDE.md` bimodal-failure invariant holds: this is a correctness gate and fails CLOSED.

## Validation (must pass before merge)
1. `test-prove-rule-check.sh` covering every acceptance case above + `test-add-rule.sh`,
   `scripts/check-doc-currency.sh`, `loomwright/scripts/test-citation-drift.sh` (+ token-budget and vendor
   ratchet after `git add`). Report `<passed>/<total>` per suite.
2. **Mutation control:** replace the counterexample leg with a no-op; the `VACUOUS` case must then fail its test.
3. Running system: in this repo, prove one real existing `must` rule from `.agent/rules/` with a hand-written
   counterexample; paste the verdict and both outputs. Then run the same with `check: true`; paste `VACUOUS`.
4. Unchanged path: `/rules add` of an advisory rule behaves exactly as before.
5. Rollback: `git revert`.

## How we know it helps (after release)
Dogfood in this repo first. Each `/dreaming` rules PR body carries the verdict counts (proven / vacuous / fails-now
/ unprovable). If vacuous or fails-now proposals show up, the gate is catching real wrong rules. If nearly every
`check_candidate` comes out `UNPROVABLE` for lack of a counterexample, the cost is too high and D1 (patch file) needs revisiting.

## Non-goals
- Lessons (`LESSONS.md`) and agent memory: prose, nothing to execute. Their existing `confidence` trailer and
  read-side staleness lint stay as they are.
- Re-proving standing rules over time. `audit-rules.sh` stays read-only and never executes; a periodic re-proof is
  a follow-up if this one earns its keep.
- Auto-generating counterexamples. The author (human or `/dreaming` proposal) supplies one.
- Any change to `rules-check.sh`, the stamp, or `rules-gate-verdict.sh`.
- Adopting the VERSE code or a benchmark harness.

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-14T01:02:33Z
- **Brief:** .supervisor/jobs/done/2026-10-13-verified-rule-checks.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/533
