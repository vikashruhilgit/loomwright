# Evidence — verified rule checks (`prove-rule-check.sh` + `add-rule.sh --proof`)

Real output from this repository, captured 2026-10-13 on branch `feature/verified-rule-checks-proof-gate`.
Nothing below is hand-written except the prose and the headings. The one edit to the transcripts is path
redaction: the repo root reads `<repo>` and the `mktemp -d` scratch directory reads `<E>`. The
counterexample patch and both proof files lived in `<E>`, outside the repo, and none of them is
committed.

## Why a candidate stands in for "an existing `must` rule"

The requirement's Validation step 3 asked to prove "one real existing `must` rule from `.agent/rules/`".
The store holds none: all three rules are `advisory` with `check: null`. So this run proves a realistic
**candidate** instead. It is CLAUDE.md's own invariant that `gh pr merge --squash` has exactly one
sanctioned executor, written as a ratchet over the positive-form grep CLAUDE.md documents (it resolves
to six paths today). The counterexample patch adds a second executor.

```text
HEAD=fd86d6fe3964ef3cca06dd3753182bc94788b892
```

## Counterexample patch (hand-written)

```diff
--- /dev/null
+++ b/loomwright/scripts/merge-now.sh
@@ -0,0 +1,2 @@
+#!/usr/bin/env bash
+gh pr merge --squash "$1"
```

## (a) The candidate check — `PROVEN`

Command (from the repo root): `bash loomwright/scripts/prove-rule-check.sh --check "$CHECK" --counterexample <E>/counterexample.patch --out <E>/proven.json --confirm < /dev/null`

```text
prove-rule-check.sh: candidate check (from argv — never read from .agent/rules/):
    test "$(grep -rn 'gh pr merge --squash' loomwright/ | grep -viE 'no |never |not ' | cut -d: -f1 | sort -u | wc -l)" -le 6
prove-rule-check.sh: counterexample patch (<E>/counterexample.patch):
    | --- /dev/null
    | +++ b/loomwright/scripts/merge-now.sh
    | @@ -0,0 +1,2 @@
    | +#!/usr/bin/env bash
    | +gh pr merge --squash "$1"
prove-rule-check.sh: repo root: <repo>   timeout per run: 60s
now leg (current tree, <repo>): exit 0
    stdout: (empty)
    stderr: (empty)
baseline (scratch copy of HEAD, before the patch): exit 0
counterexample leg (scratch copy of HEAD + patch): exit 1
    stdout: (empty)
    stderr: (empty)
verdict: PROVEN
rc=0
```

Both check outputs: on the current tree `test` exited 0; on HEAD + patch it exited 1. The check prints nothing, so both streams are empty. The six-path count was measured separately with the same pipeline on the current tree. The patch adds one more file that executes the command, which is why the count passes the bound of 6 (an inference: the prover does not print the count). The baseline run on the clean scratch copy of HEAD also exited 0, so the failure is credited to the patch and not to uncommitted state.

Proof file:

```json
{
  "schema": "rule-check-proof/1",
  "verdict": "PROVEN",
  "reason": null,
  "check_sha256": "83960b6dded42ef9b37202a18ca66e26e61ea923f1036842b8a8b16122b0cec2",
  "counterexample_sha256": "6c7baee6e6a193895105df92a60c42fcdf321cff35c406e47f01267f5bec43f7",
  "now_exit": 0,
  "baseline_exit": 0,
  "counterexample_exit": 1,
  "ts": "2026-10-13T16:17:56Z"
}
```

## (b) The same run with `check: true` — `VACUOUS`

```text
prove-rule-check.sh: candidate check (from argv — never read from .agent/rules/):
    true
prove-rule-check.sh: counterexample patch (<E>/counterexample.patch):
    | --- /dev/null
    | +++ b/loomwright/scripts/merge-now.sh
    | @@ -0,0 +1,2 @@
    | +#!/usr/bin/env bash
    | +gh pr merge --squash "$1"
prove-rule-check.sh: repo root: <repo>   timeout per run: 60s
now leg (current tree, <repo>): exit 0
    stdout: (empty)
    stderr: (empty)
baseline (scratch copy of HEAD, before the patch): exit 0
counterexample leg (scratch copy of HEAD + patch): exit 0
    stdout: (empty)
    stderr: (empty)
verdict: VACUOUS
rc=1
```

```json
{
  "schema": "rule-check-proof/1",
  "verdict": "VACUOUS",
  "reason": null,
  "check_sha256": "b5bea41b6c623f7c09f1bf24dcae58ebab3c0cdd90ad966bc43a45b44867e12b",
  "counterexample_sha256": "6c7baee6e6a193895105df92a60c42fcdf321cff35c406e47f01267f5bec43f7",
  "now_exit": 0,
  "baseline_exit": 0,
  "counterexample_exit": 0,
  "ts": "2026-10-13T16:17:57Z"
}
```

## The user's tree and worktree list are left as found

`git worktree list --porcelain` + `git status --porcelain`, captured before the two prove runs and again after them, compared with `cmp`:

```text
cmp: identical (30 lines)
```

## The writer gate on this repo (`add-rule.sh`, dry-run — nothing written)

Each run omits `--confirm`, so a passing gate only PLANS the write. `git status --porcelain` stayed at the one unrelated untracked file throughout.

`--enforcement must --check "$CHECK" --proof <E>/proven.json`:

```text
PLANNED WRITE (not written — pass --confirm to apply):
  target: <repo>/.agent/rules/process.json
  object: {
  "id": "process-only-automate-helpers-sh-gate-eval-executes-gh-pr-merge-squash-see-claude-md-failure-mode-invariants",
  "category": "process",
  "statement": "Only automate-helpers.sh gate-eval executes gh pr merge --squash; see CLAUDE.md Failure-Mode Invariants",
  "enforcement": "must",
  "check": "test \"$(grep -rn 'gh pr merge --squash' loomwright/ | grep -viE 'no |never |not ' | cut -d: -f1 | sort -u | wc -l)\" -le 6",
  "provenance": {
    "source": "/rules add",
    "added": "2026-10-13T16:18:54Z"
  },
  "applies_to": null
}
rc=0
```

`--enforcement must --check true --proof <E>/vacuous.json`:

```text
add-rule.sh: rejected: --proof verdict is 'VACUOUS', not PROVEN — this check has not been shown to fail on a violation. Add it as --enforcement advisory (check kept as data) instead. Nothing was written.
rc=1
```

`--enforcement must --check "$CHECK"` with no `--proof`:

```text
add-rule.sh: rejected: --enforcement must with --check requires --proof <file> written by prove-rule-check.sh (verdict PROVEN for this exact check). Prove it first, or add the rule as --enforcement advisory with the check kept as data. Nothing was written.
rc=1
```

## Validation 4 — an advisory `/rules add` is unchanged

The same dry-run through the base writer (`git show 4c1b594:loomwright/scripts/add-rule.sh`) and the new one, with the `provenance.added` timestamp normalized to `<ts>`:

```text
advisory + --check (no --proof): byte-identical to base
advisory, no --check:         byte-identical to base
```

```text
PLANNED WRITE (not written — pass --confirm to apply):
  target: <repo>/.agent/rules/process.json
  object: {
  "id": "process-prefer-the-narrow-probe-over-the-unrequested-sweep-see-claude-md-working-style",
  "category": "process",
  "statement": "Prefer the narrow probe over the unrequested sweep; see CLAUDE.md Working style",
  "enforcement": "advisory",
  "check": "bash scripts/ci-local.sh",
  "provenance": {
    "source": "/rules add",
    "added": "<ts>"
  },
  "applies_to": null
}
```
