<!-- bump: minor -->
History references in runtime prompts may only go down, and every prompt-size ceiling sits at its live measure + ~10%
The automate-speed diet moved history out of the runtime prompts, and nothing stopped the next fix PR from writing it
back. New fail-CLOSED gate `scripts/check-prompt-history-refs.sh` counts history references in every `*.md` under
`loomwright/agents/`, `loomwright/commands/`, `loomwright/skills/` and `loomwright/docs/command-parts/` against a
committed baseline, `loomwright/docs/prompt-history-refs-baseline.json`, one entry per file. The command parts are
scanned on purpose: `check-token-budget.sh` already counts them as command weight, and leaving them out would let a
reference move from a command into its parts unseen. Nothing else under `loomwright/docs/` is scanned, nor
`CHANGELOG.md`. A file above its entry fails and the gate prints the references its base copy lacks. A file below its
entry passes and prints `lower the baseline`. The baseline itself may only go down: an entry above the same entry on
`main`, or a total above `main`'s, fails. An unresolvable base is skipped, and is an error under
`PROMPT_HISTORY_REFS_REQUIRE_BASE=1`, which CI sets. A base with no baseline file yet is the bootstrap skip and passes
even under require-base, so this PR's own CI can go green. A malformed baseline, a non-integer or missing entry, an
orphan entry or an empty scanned dir is an error. Frozen example records are not counted. CI runs the gate and its
self-test in a new step after the vendor-coupling step, with a dedicated base-ref fetch; `scripts/ci-local.sh` picks
both up from `ci.yml`. Every `.agents`, `.skills` and `.commands` row in `prompt-token-budgets.json` is re-baselined
to the live proxy with `budget` = ceil(measured × 1.10): loose rows drop (`execute-manager` 42568 to 21277,
`skills/automate-loop` 77733 to 48362, `commands/autonomous` 11846 to 4361) and near-breach rows get their margin
back. Every agent row, `rubric-grader` included, is now a live row in the `ARCHITECTURE_CONTRACTS.md` mirror, which
gains a re-measure log line and a `## Cost Profiles` pointer to the `coordinator_model` key. Evidence:
`docs/evidence/automate-speed-baseline.md` §"Item 18 — runtime read set after the diet".
