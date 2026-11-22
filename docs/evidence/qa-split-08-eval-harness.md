# qa-split 08 — the eval harness and the Phase 3 gate, Validation step 2 (running system)

Recorded 2026-11-22 (report time 2026-11-22T02:26:54.754Z) on the owner's machine, branch
`feature/qa-split-08-eval-harness`, Node v24.11.1, with the real outside folder
`~/.claude/selvedge-eval/held-out/` (`SELVEDGE_EVAL_HELD_OUT` unset). This is one dated measurement,
not a live claim: the current report is the last held-out entry of `selvedge/eval/results.json`, and
the `selvedge/README.md` block generated from it.

Verdict: PASS for Validation 2

Validation 2 asks that the harness run once for real on the held-out set and that its report, gate
verdict and intervals be committed and shown in the README. They are. The **Phase 3 gate itself is
`not met`**, as the brief expected: the held-out known-FAIL denominator (21) is below the
floor of 60 that `FLOORS.held_out_fail` sets, because the planted-defect set does not exist yet. A
below-floor report does not count toward the two-revision rule.

## Result

| Rate | Numerator / denominator | Point estimate | 95% interval (Clopper-Pearson) |
|---|---|---|---|
| false-PASS (PASS on known-FAIL) | 0 / 21 | 0.0% | 0.0% – 16.1% |
| false-FAIL (FAIL on known-PASS) | 0 / 105 | 0.0% | 0.0% – 3.5% |
| abstention (BLOCKED + NOT_VERIFIABLE) | 74 / 126 | 58.7% | 49.6% – 67.4% |

- Engine: selvedge 0.9.0, planner `sonnet` (the default `claude -p` planner).
- 126 held-out cases on 42 sports-management commits (21 real-bug groups); no planted variant exists yet.
- `model-judged` criteria: 0 (the web runner reads `structured-read` only).
- Runner flips (3 runs of each plan 1): 1 of 126 cases. Planner flips (3 fresh plans): 37 of 126 cases.
- `budget_exceeded` BLOCKED: 0. Planner tokens over the run: 19182623; model-free run time: 827 s over 208 runs.

## Commands run

```
$ node selvedge/eval/harness.mjs run --set held-out --planner-repeats 3 --runner-repeats 3 \
    --work-dir "${TMPDIR}selvedge-eval-work/held-out-0.9.0-real" [--resume]
$ node selvedge/eval/harness.mjs readme
$ node selvedge/eval/harness.mjs check-readme
$ node selvedge/eval/eval-set.mjs check-leak
$ bash selvedge/tests/run.sh
```

The run's environment was a clean one (`env -i` with HOME, PATH, TMPDIR, USER, LANG), plus
`SELVEDGE_EVAL_SM_CHECKOUT` (the owner's sports-management checkout, read for
`supabase/config.toml` only), `SELVEDGE_PLAYWRIGHT_MODULE` and `PLAYWRIGHT_BROWSERS_PATH` (the
Playwright 1.65.1 the selvedge tests cache), so no Claude Code session variable reached the planner.

## The harness's printed report and gate line

```
report: set held-out, selvedge 0.9.0, planner sonnet, 126 case(s)
false-PASS      0 / 21    0.0000   95% CI 0.0000 – 0.1611
false-FAIL      0 / 105   0.0000   95% CI 0.0000 – 0.0345
abstention     74 / 126   0.5873   95% CI 0.4962 – 0.6742
verdicts: PASS 49, FAIL 3, BLOCKED 6, NOT_VERIFIABLE 68
  abstained: BLOCKED plan_invalid × 3
  abstained: BLOCKED step_failed × 3
  abstained: NOT_VERIFIABLE exploration_budget × 4
  abstained: NOT_VERIFIABLE material_assumption × 14
  abstained: NOT_VERIFIABLE no_value_read × 1
  abstained: NOT_VERIFIABLE side_effect_not_observable × 49
budget_exceeded BLOCKED (counted in abstention, shown on its own): 0
model-judged (kept apart): 0 criterion(s)
runner flips: 1 of 126 case(s) over 3 run(s) of plan 1: sm-pr-422-nd-pricing-plans-parent BLOCKED/PASS/PASS
planner flips: 37 of 126 case(s) over 3 plan(s): sm-pr-226-nd-login-form-fix PASS/PASS/NOT_VERIFIABLE, sm-pr-226-nd-tournament-api-fix PASS/NOT_VERIFIABLE/NOT_VERIFIABLE, sm-pr-226-nd-tournament-api-parent NOT_VERIFIABLE/PASS/NOT_VERIFIABLE, sm-pr-333-nd-login-form-parent PASS/NOT_VERIFIABLE/PASS, sm-pr-357-nd-tournament-api-fix PASS/NOT_VERIFIABLE/PASS, sm-pr-357-nd-tournament-api-parent NOT_VERIFIABLE/PASS/PASS, sm-pr-362-bug-fix NOT_VERIFIABLE/NOT_VERIFIABLE/BLOCKED, sm-pr-362-nd-login-form-fix PASS/PASS/BLOCKED, sm-pr-362-nd-tournament-api-fix NOT_VERIFIABLE/NOT_VERIFIABLE/BLOCKED, sm-pr-365-nd-org-page-fix PASS/PASS/NOT_VERIFIABLE, sm-pr-365-nd-org-page-parent PASS/PASS/NOT_VERIFIABLE, sm-pr-365-nd-tournament-api-fix PASS/PASS/NOT_VERIFIABLE, sm-pr-365-nd-tournament-api-parent NOT_VERIFIABLE/PASS/PASS, sm-pr-368-bug-fix NOT_VERIFIABLE/PASS/NOT_VERIFIABLE, sm-pr-368-bug-parent NOT_VERIFIABLE/BLOCKED/BLOCKED, sm-pr-368-nd-tournament-api-fix PASS/PASS/NOT_VERIFIABLE, sm-pr-368-nd-tournament-api-parent NOT_VERIFIABLE/PASS/NOT_VERIFIABLE, sm-pr-378-nd-org-page-fix NOT_VERIFIABLE/PASS/NOT_VERIFIABLE, sm-pr-378-nd-org-page-parent NOT_VERIFIABLE/PASS/NOT_VERIFIABLE, sm-pr-387-nd-sports-list-fix NOT_VERIFIABLE/PASS/PASS, sm-pr-411-nd-login-form-fix PASS/NOT_VERIFIABLE/PASS, sm-pr-420-nd-sports-list-parent NOT_VERIFIABLE/PASS/NOT_VERIFIABLE, sm-pr-422-bug-parent FAIL/NOT_VERIFIABLE/NOT_VERIFIABLE, sm-pr-422-nd-pricing-plans-parent BLOCKED/PASS/PASS, sm-pr-426-bug-fix NOT_VERIFIABLE/NOT_VERIFIABLE/BLOCKED, sm-pr-426-nd-org-page-fix NOT_VERIFIABLE/NOT_VERIFIABLE/BLOCKED, sm-pr-426-nd-org-page-parent PASS/PASS/NOT_VERIFIABLE, sm-pr-426-nd-pricing-plans-fix PASS/PASS/BLOCKED, sm-pr-468-nd-org-page-fix NOT_VERIFIABLE/PASS/NOT_VERIFIABLE, sm-pr-468-nd-tournament-api-fix NOT_VERIFIABLE/PASS/PASS, sm-pr-468-nd-tournament-api-parent PASS/NOT_VERIFIABLE/PASS, sm-pr-469-bug-fix BLOCKED/NOT_VERIFIABLE/BLOCKED, sm-pr-469-bug-parent BLOCKED/NOT_VERIFIABLE/NOT_VERIFIABLE, sm-pr-469-nd-tournament-api-parent PASS/NOT_VERIFIABLE/NOT_VERIFIABLE, sm-pr-486-bug-parent BLOCKED/NOT_VERIFIABLE/FAIL, sm-pr-486-nd-admin-login-parent BLOCKED/NOT_VERIFIABLE/NOT_VERIFIABLE, sm-pr-486-nd-login-form-parent BLOCKED/PASS/PASS
planner tokens 19182623, run time 826520 ms over 208 run(s)
gate: not met — known-FAIL denominator 21 is below the floor 60 (FLOORS.held_out_fail); abstention 0.5873 > 0.2
harness: OK — report appended to /Users/vikashruhil/Documents/work/AI/ai-agent-manager/selvedge/eval/results.json; next: node selvedge/eval/harness.mjs readme
```

Gate line: `gate: not met — known-FAIL denominator 21 is below the floor 60 (FLOORS.held_out_fail); abstention 0.5873 > 0.2`

## How the run went

The run needed seven passes over the same work dir (`--resume` keeps each finished target, and a
target in flight when a pass stops is run again from the start). Passes 1 to 3 stopped on a target
the driver could not bring up, with its reason, and nothing was scored part-way; each stop was a
driver defect, fixed at its cause before the next pass. Passes 4 to 6 were stopped from outside by
the worker session's 2-hour limit on a background command, not by the harness:

1. The dev server's background shell kept the driver's stdout open, so the harness waited on it
   after `up` had finished (the dev server now runs with its standard streams redirected).
2. `supabase db reset` applies the migrations and `seed.sql`, restarts the storage container, then
   seeds the storage buckets through the gateway, which still held the old container's address and
   answered 502. Only for that failure, the driver now restarts the eval project's own gateway,
   waits for it to answer, and runs the CLI's own last step, `supabase seed buckets`.
3. For the old Chrome user agent the driver first sent, Google served Archivo as
   `fonts.gstatic.com/l/font?kit=` files, which Turbopack refuses, so one commit answered 500 on
   every page. The driver now sends a current Chrome user agent and fails the fonts step by name if a
   stylesheet still points at `/l/` files.

Every one of the 42 held-out commits revived. The machine was heavily loaded for part of the run
(load average near 20, most of it the Docker VM): a target then took up to about 35 minutes, most of
it `supabase db reset` and the planner, and single `claude -p` planner calls ran for 30 to 45
minutes before they returned. Neither `selvedge plan` nor the harness puts a time limit on a
planner, so one slow call holds the whole run; that is an open item, not fixed here. The owner's own sports-management checkout was
only read (its `supabase/config.toml`), and the eval used its own Supabase project
(`selvedge-eval-sm`, ports 553xx). One side effect to know: Docker was not running at the start, and
starting Docker Desktop restarted the owner's own `sports-management` Supabase containers by their
restart policy. They were left as they were; nothing was run against them.

## check-readme, check-leak and the gate

```
$ node selvedge/eval/harness.mjs check-readme
harness: OK — the results block in /Users/vikashruhil/Documents/work/AI/ai-agent-manager/selvedge/README.md matches /Users/vikashruhil/Documents/work/AI/ai-agent-manager/selvedge/eval/results.json
$ node selvedge/eval/eval-set.mjs check-leak
eval-set: OK — no held-out answer or variant in the tracked files under selvedge/eval/
$ bash selvedge/tests/run.sh
rc=0
```

## Limits

- The held-out known-FAIL denominator is 21, so every interval above is wide; the gate stays
  `not met` until the planted-defect set brings it to the floor.
- Every held-out answer can still be worked out from committed data (`selvedge/eval/README.md`), so
  this report does not yet measure a hidden set.
- Selvedge's runner reads pages in a browser; criteria about a POST response or a status code are
  often not observable that way, which shows up as abstention, not as a wrong verdict.
