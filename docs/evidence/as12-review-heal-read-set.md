# Evidence — automate-speed/12: the review-heal read set before and after the next-step driver

Source requirement: `.supervisor/requirements/automate-speed/12-next-step-review-heal.md`. Driver:
`loomwright/scripts/review-heal-next-step.sh`. Base commit `a8819a3` (`a8819a38100d77fbeddc2ff1a56963e91f172a5d`).
macOS, BSD `wc`.

The read set is the three files the `/review-pr --until-mergeable` drain reads as prose: the skill, the command and the
runner agent (the review-heal group of `loomwright/scripts/test-loop-inventory.sh`).

## Commands

Run from the repository root.

```
# before (base)
git show a8819a3:loomwright/skills/review-heal/SKILL.md | wc -c
git show a8819a3:loomwright/commands/review-pr.md | wc -c
git show a8819a3:loomwright/agents/review-pr.md | wc -c

# after (this branch)
wc -c < loomwright/skills/review-heal/SKILL.md
wc -c < loomwright/commands/review-pr.md
wc -c < loomwright/agents/review-pr.md
```

## Measurements

| File | Before (`a8819a3`) | After | Change |
|---|---|---|---|
| `loomwright/skills/review-heal/SKILL.md` | 133454 | 110754 | −22700 (−17.0%) |
| `loomwright/commands/review-pr.md` | 21014 | 18297 | −2717 (−12.9%) |
| `loomwright/agents/review-pr.md` | 21195 | 21195 | 0 (not edited, by the brief's non-goal) |
| **Read set** | **175663** | **150246** | **−25417 (−14.5%)** |

`check-token-budget.sh` after the change (proxy tokens = bytes / 4): `review-heal` 27688 / 36700, `review-pr` (command)
4574 / 5779. Both budgets may only shrink and neither was raised.

## What was removed and what stayed

Removed, each replaced by a pointer to the driver step that now executes it:

- §U1's `gh pr view` / `drain-gh-read.sh` code block and the `bot_findings = …` pseudocode (driver steps `read`,
  `classify`).
- §U2's `required-checks` code block (`required`) and §U2.5's wait loop pseudocode (`wait`).
- §U4's whole pseudocode block: the state variables, the ledger calls, the probe loop with its run-id derivation, the
  Validate-Then-Fix bookkeeping, the earned-fallback branch, the marker post, the READY / `ci_untrusted` / `findings`
  branches, the sub-floor bookkeeping, the anti-churn bookkeeping and the emit block (steps `start` to `finish`).
- The termination-only severity floor's confirming-pass code block and its result mapping (`confirm`).
- `commands/review-pr.md`'s `--until-mergeable` items 1–8 are now nine short pointer items, the first of which says how
  to run the driver.

Kept in prose, because it is the contract the driver's instructions cite or a judgment the model still makes: the rule
sections of §U1–§U3.5 (channel set, envelope, fail-closed rules, thread classification, the Validate-Then-Fix cases),
§"Dismissed-findings marker comment" (its format is the one `pr-postmortem-gather.sh` parses), §"Earned Fallback
Review", §"READY redefinition", §"Terminal states", §"Escalation cause", the Anti-Churn Guardrail, and the parts of §U4
other tests pin: the defaults, the rules-gate mapping (`test-rules-gate-seams.sh` pins 2/7/10), the fix-worker prompt
(`test-phase45-rounds-seam.sh`, `test-no-self-matching-wait.sh`) and the `push_fix_to_pr()` call site
(`test-release-refold.sh`).

## Honest limits

- This measures bytes of prose, not what a session actually reads. A drain now also reads the driver's JSON
  instructions (one per call) and may open `loomwright/docs/result-schemas/review-heal-next-step.md` (17003 bytes),
  which did not exist at base. The saving is in what the model re-derives from prose each round, not a guaranteed
  per-session token cut.
- `agents/review-pr.md` still restates parts of the drain (its rows are pinned, not migrated), so the runner agent's own
  read is unchanged.
