# Evidence: the drain honours a named required-checks set

Change: `.supervisor/config.json` `required_checks` and `--required-checks name:<a>[,<b>…]` for the
`/review-pr --until-mergeable` drain (GitHub issue #805). Recorded 2026-11-13 on macOS (Darwin 25.6.0) by the
Supervisor's docs worker (Subtask 3), on branch `feature/drain-named-required-checks-3-dep` over base `40b3f49`.

## Validation 2 — a live drain on a private GitHub-Free repo

**Not run.** No live drain was run from this branch, so there is no output to paste and no PASS to declare.

Why: Validation 2 runs `/review-pr <pr-url> --until-mergeable` twice on a real PR of one of the owner's private
GitHub-Free repos. That drain is not read-only. It posts PR comments (the dismissed-findings marker and, on the
typo run, the terminal `ESCALATED` comment), it may spawn a fix worker that pushes to the PR branch, and it needs
`required_checks` written into that repo's `.supervisor/config.json`. This worker runs under "production and shared
repos are read-only: no push, no PR", so it did not look for a candidate repo and did not run either drain.

Verdict: NOT RUN for Validation 2
Verdict: NOT-RUN for Validation 2

The first line is the literal the brief's AC 15 names. The second is the same verdict in the grammar the
`/automate` validation gate reads (`automate-lanes.d/evidence.sh`: `PASS|FAIL|NOT-RUN`, hyphenated); a line in
any other form declares nothing. Either way the gate reads Validation 2 as not run and keeps the item parked.

### What the owner runs to close it

1. Pick a private repo on GitHub Free with an open PR whose checks include one green check that should gate
   READY (below, `<named>`) and one red check no code fix can reach (a deployment integration, for example).
2. In that repo's checkout, set `.supervisor/config.json` to carry `"required_checks": ["<named>"]` (keep the
   file's other keys).
3. Run `/review-pr <pr-url> --until-mergeable`. Expected: `decision: READY`; the drain's sidecar
   (`.supervisor/review-heal/<pr_hash>.next-step.json`) shows `required_mode: named` and
   `required_names: ["<named>"]`; the red deployment check never blocks.
4. Rename the key's entry to a typo (`["<named>x"]`) and run the drain again. Expected: `decision: ESCALATED`,
   the `done` instruction's `message` is `required_check_absent`, and the terminal PR comment names `<named>x`.
   This run waits out `--check-wait-timeout` (default 1200 s); pass a smaller value to shorten it.
5. Paste both runs' output below in fenced blocks (owner and repo names redacted), delete the two `Verdict:`
   lines above, and add the column-0 line `Verdict: PASS for Validation 2` (or `FAIL`). The gate takes the worst
   declared verdict in a file, so a `NOT-RUN` line left in place keeps the item parked. Link this file from the
   PR body.

## What is covered without a live repo

The hermetic suites on this branch, which stub `gh` and never reach the network, cover every acceptance case
except the live one: `loomwright/scripts/test-review-heal-next-step.sh` (the named mode from the config and from
`name:`, flag over config, readable protection winning, `required_check_absent`, the malformed key, the `name:`
usage errors, the three byte-identical no-list pins, the driver reading `--root`'s config, and no
`--required-checks` in any drain invocation `automate-next-step.sh` builds), its golden case
`fixtures/review-heal-golden/named-required-ready` (READY with a red deployment status outside the set),
`loomwright/scripts/test-wait-for-checks.sh` (`--named-required`: the 200 read wins, the no-list arms take the
set, an absent named check stays pending, no flag means byte-unchanged output),
`loomwright/scripts/test-setup-base-branch.sh` (the advisory line) and
`loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh` (a lane clone keeps `required_checks`). These are
stubs: they show the drain does what the code says against the response bodies the tests assume. They do not show
that GitHub answers a real private Free repo with those bodies, which is what Validation 2 checks.
