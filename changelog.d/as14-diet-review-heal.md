<!-- bump: minor -->
review-heal prompts carry rules, not stories; the fallback, escalation and dispatch parts load only when used
The files a `/review-pr --until-mergeable` drain round reads (`skills/review-heal/SKILL.md` and `commands/review-pr.md`)
are cut to instructions and short rules: every story and history note moved to
`loomwright/docs/rationale/review-heal.md`, and every rule row of the `review-heal` loop inventory now has a non-prose
home (`global`, `step-scoped`, a script, or a rationale heading for a split row whose rule part has its own row).
Three path-only parts moved out of `SKILL.md`: the Earned Fallback Review to `skills/review-heal/fallback-review.md`
(read only when the driver prints a `spawn` with `what: "fallback review"`), §"Escalation cause" to
`skills/review-heal/escalation.md` (read only when the run ends `ESCALATED`), and §"Until-Mergeable Dispatch Signal"
with its sub-sections to `skills/review-heal/dispatch.md` (the dispatching side's, never read by a drain round).
Every moved heading keeps a one-line pointer in `SKILL.md`, so existing citations, including the `contract` strings
`scripts/review-heal-next-step.sh` prints, still resolve. `commands/review-pr.md` states this read rule.
`test-loop-inventory.sh` lists the new files as `review-heal` group sources, and `test-review-heal-next-step.sh`'s
prose-pin leg follows the moved text to its new file, as does `test-dispatch-pr-review.sh`'s script-name drift guard.
No rule's condition or action changed, and no non-test script was edited. Before/after sizes, history-reference counts, the by-home
table, the gate results and the open behaviour questions are in `docs/evidence/as14-diet-review-heal.md`.
