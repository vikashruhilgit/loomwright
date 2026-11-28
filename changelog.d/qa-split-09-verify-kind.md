<!-- bump: minor -->
Ground truth checks a brief's `verify:` lines with Selvedge, and a mistyped check prefix is never run as shell
A brief's `## Executable Acceptance` line that starts with an unknown `<word>:` prefix (for example the typo
`verfy: the cart total updates`) used to be hashed into the stamp and, once stamped, run as a shell command. It is
now the kind `unknown_kind`: never hashed, never run, recorded `unverified` with reason `unknown_kind`, and Plan
Review Criterion 14 lists it as a line that will not run. A bare line with no such prefix is still a shell `cmd`,
and a brief with no `verify:` line hashes exactly as before, so existing stamps stay valid. The new `verify:`
kind (`qa-executor:` is kept as its alias) holds a criterion about what a user sees. `run-ground-truth.sh` sends
every `verify:` line of a run to ONE Selvedge run through the new driver `ground-truth-verify.sh` (`criteria
from-text`, then `plan --base <ref>`, then `run`), and maps each criterion's verdict from that run's
`verdict.json`: PASS is `pass`, FAIL is `fail`, BLOCKED or NOT_VERIFIABLE is `unverified` with Selvedge's reason.
No Selvedge CLI, a refusal or an unreadable `verdict.json` give `verify_plugin_absent`, `verify_refused` or
`verify_verdict_unreadable`, never a pass. `verify:` lines are hashed but need no stamp, and they still run under
`--no-cmd`. The runner prints a `Verify: verify 1 PASS · 1 NOT_VERIFIABLE` counts line and adds an additive
`verify_counts` key to `GROUND_TRUTH_JSON`; Phase 4.5's `ground_truth` decision line appends those counts, so a
`verify:` result never reads as a bare pass. Phase 4.5 hands Selvedge the run's base branch, so a PR's own
`selvedge.json` edit has no effect at plan time. Ground truth stays advisory: a `verify:` FAIL never starts a fix
iteration and never gates a merge. Open item: `selvedge run` takes no `--base` and reads `selvedge.json` from the
checkout, so the base-branch read holds at plan time only until a later Selvedge change
(`docs/evidence/qa-split-09-verify-kind.md` §"Open items").
