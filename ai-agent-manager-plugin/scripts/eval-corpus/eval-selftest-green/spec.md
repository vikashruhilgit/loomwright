# Task: eval-selftest-green

## What this task asks

The eval harness's own self-test must pass — a deliberately-broken eval
runner would be caught here.

`test-run-eval.sh` exercises `run-eval.sh` against isolated
**temp-fixture corpora** (built with `mktemp -d` and pointed at via the
`EVAL_CORPUS_DIR` override), covering pass/fail tallying, the
determinism invariant, and the missing-corpus fail-safe. If a change
broke the runner's scoring, determinism, or fail-safe behavior, this
self-test would go red.

## How it's checked

`check.sh` resolves the repo root (via `git rev-parse --show-toplevel`)
and runs the harness's own self-test:

```
bash ai-agent-manager-plugin/scripts/test-run-eval.sh
```

It exits with that self-test's status — exit 0 (all self-tests pass) =
pass, non-zero = fail.

## Recursion-safety note

`test-run-eval.sh` uses temp-fixture corpora via the `EVAL_CORPUS_DIR`
override; it does **not** run the real corpus. So when `run-eval.sh` runs
this task's `check.sh` over the real corpus, there is no infinite
recursion — this check intentionally invokes the self-test, never
`run-eval.sh` against the real corpus.
