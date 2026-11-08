<!-- bump: minor -->
/review-pr --cheap puts the review-heal loop's Task spawns on Sonnet
`/review-pr` takes `--cheap`. The reviewer, fix-worker and earned-fallback Task spawns of both loops then carry
`model: "sonnet"`. In the `--until-mergeable` drain, `scripts/review-heal-next-step.sh --start drain --cheap` keeps the
flag in its sidecar as `flag_cheap` and adds `model: "sonnet"` to its `fix worker` and `fallback review` spawn
instructions, so every later call of the run carries it. Without the flag no instruction carries a `model` key, and the
golden fixtures are byte-identical. A seat routed through `lens-run.sh` is a Bash shell-out, not a Task spawn, so it
ignores the key. An unknown cost flag such as `--cheaper` is refused with the existing `unknown option` error.
`docs/ARCHITECTURE_CONTRACTS.md` §"Cost Profiles" names `/review-pr --cheap` as a second entry point and adds rows
for the reviewer, the fix worker and the Earned Fallback Review. `skills/review-heal/SKILL.md`,
`skills/review-heal/fallback-review.md`, `commands/review-pr.md` and `docs/result-schemas/review-heal-next-step.md`
document the flag and the key, and `scripts/test-review-heal-next-step.sh` gains a C leg (and the MK1–MK3 mutation
controls) that pins them. The model alias is held in one variable in the driver and one in its test, and
`docs/vendor-coupling-manifest.json` raises each file's allowance by that one reference, with a reason.
