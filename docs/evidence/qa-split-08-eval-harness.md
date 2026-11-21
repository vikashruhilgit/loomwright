# qa-split 08 — the eval harness, Validation step 2 (running system): IN PROGRESS

Recorded 2026-11-22 on the owner's machine, branch `feature/qa-split-08-eval-harness`, Node v24.11.1,
selvedge 0.9.0, with the real outside folder `~/.claude/selvedge-eval/held-out/`. This file carries
**no PASS verdict line for Validation 2**: the real held-out run did not finish in the worker's session,
and a partial set is never scored as the gate.

## State

- `node selvedge/eval/harness.mjs run --set held-out --planner-repeats 3 --runner-repeats 3` ran in the
  work dir `${TMPDIR}selvedge-eval-work/held-out-0.9.0-real` (outside the repo). 31 of the 42 held-out
  targets (sports-management commits) finished there (each `targets/<n>-<hash>/result.json`) when the
  worker stopped; the rest were not run. No report was appended to `selvedge/eval/results.json`, so the
  README carries no results block (the AC6 real-tree arm checks exactly that).
- Every target tried so far revived. Nothing was scored part-way.

## To finish it

```
env -i HOME="$HOME" PATH="$PATH" TMPDIR="$TMPDIR" USER="$USER" LANG=en_US.UTF-8 \
  SELVEDGE_EVAL_SM_CHECKOUT=<the owner's sports-management checkout, read for supabase/config.toml only> \
  SELVEDGE_PLAYWRIGHT_MODULE="${TMPDIR}selvedge-test-pw/node_modules/playwright/index.mjs" \
  PLAYWRIGHT_BROWSERS_PATH="${TMPDIR}selvedge-test-pw/browsers" \
  node selvedge/eval/harness.mjs run --set held-out --planner-repeats 3 --runner-repeats 3 \
  --work-dir "${TMPDIR}selvedge-eval-work/held-out-0.9.0-real" --resume
node selvedge/eval/harness.mjs readme
node selvedge/eval/eval-set.mjs check-leak
bash selvedge/tests/run.sh
```

Docker must be running. `--resume` keeps the finished targets. Then commit `selvedge/eval/results.json`
and the README block, add the printed report and gate line here, and declare the Validation 2 verdict.
The gate is expected `not met`: the held-out known-FAIL denominator (21) is below `FLOORS.held_out_fail`.

## What the run found in the driver (each fixed at its cause, then resumed)

1. The dev server's background shell kept the driver's stdout open, so the harness waited on it after
   `up` had finished. The dev server now runs with its standard streams redirected.
2. `supabase db reset` applies the migrations and `seed.sql`, restarts the storage container, then seeds
   the storage buckets through the gateway, which still held the old container's address and answered
   502. Only for that failure the driver restarts the eval project's own gateway, waits for a real
   answer, and runs the CLI's own last step, `supabase seed buckets`.
3. For an older Chrome user agent Google served Archivo as `fonts.gstatic.com/l/font?kit=` files, which
   Turbopack refuses, so one commit answered 500 on every page. The driver now sends a current Chrome
   user agent and fails the fonts step by name if a stylesheet still points at `/l/` files.

Observed and not fixed: one `claude -p` planner call ran for over 30 minutes before it returned; neither
`selvedge plan` nor the harness puts a time limit on a planner, so one slow call holds the whole run.

## Side effects to know

The owner's sports-management checkout was only read (its `supabase/config.toml`); the eval used its own
Supabase project (`selvedge-eval-sm`, ports 553xx). Docker was not running at the start, and starting
Docker Desktop restarted the owner's own `sports-management` Supabase containers by their restart
policy. They were left as they were; nothing was run against them.
