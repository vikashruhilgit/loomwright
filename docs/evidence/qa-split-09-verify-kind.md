# Evidence — `verify:` lines checked by one real Selvedge run

Requirement: `.supervisor/requirements/qa-split/09-loomwright-verify-kind-and-unknown-prefix-root-fix.md`
(Validation 3). Captured 2026-11-28 on macOS (Darwin 25.6.0), branch
`feature/qa09-verify-kind-unknown-prefix`, base `9a6a850`. The run used the real Selvedge CLI from this
checkout (not the stale copy on this machine's `PATH`), its real default planner (`claude -p`), real
Playwright 1.65.1 with its Chromium, and Selvedge's bundled sample app. Nothing was stubbed.

**Status in one line:** two `verify:` lines went into ONE Selvedge run folder, each came back with its own
result read from that folder's `verdict.json`, and the runner printed the counts line.

## Setup

A scratch git repo (outside this checkout, shown as `<scratch>/v3-demo`) with its own Playwright and a
committed `selvedge.json`, so `plan --base main` reads the allowlist from a commit:

```bash
mkdir <scratch>/v3-demo && cd <scratch>/v3-demo && git init -q && npm init -y && npm i -D playwright
<checkout>/selvedge/bin/selvedge env init --port 4291          # origin http://localhost:4291
git add -A && git commit -qm "demo: selvedge.json"                # HEAD 07c70df on main
<checkout>/selvedge/bin/selvedge sample-app --port 4291 &         # serving on http://localhost:4291
<checkout>/selvedge/bin/selvedge doctor                           # six ok lines (no hooks, planner claude)
```

The brief (`<scratch>/v3-brief.md`) carries exactly two lines in its `## Executable Acceptance` section and
no stamp:

```markdown
## Executable Acceptance
- verify: On http://localhost:4291/cart, after clicking "Open cart", the Total reads 6
- verify: On http://localhost:4291/echo, after typing Ada in the User field, the page shows "Hello, Ada"
```

## Command

```bash
SELVEDGE_BIN=<checkout>/selvedge/bin/selvedge "$SELVEDGE_BIN" --version
SELVEDGE_BIN=<checkout>/selvedge/bin/selvedge GROUND_TRUTH_VERIFY_BASE=main \
  bash loomwright/scripts/run-ground-truth.sh --brief <scratch>/v3-brief.md --project <scratch>/v3-demo
```

`GROUND_TRUTH_VERIFY_BASE=main` names the base ref the driver passes to `plan --base`; the scratch repo has
no `origin`, so the default (`origin/HEAD`, else `origin/main`) would not resolve there.

## Full output

stdout and stderr together, with only the scratch path shortened to `<scratch>`:

```text
selvedge 0.12.1
  verify: one Selvedge run, folder <scratch>/v3-demo/.selvedge/runs/20261128T030132Z-422942
  [PASS] verify:On http://localhost:4291/cart, after clicking "Open cart", the Total reads 6
  [PASS] verify:On http://localhost:4291/echo, after typing Ada in the User field, the page shows "Hello, Ada"
Checks passed: 2/2
Verify: verify 2 PASS
GROUND_TRUTH_JSON: {"schema_version":1,"ran":true,"status":"pass","checks_total":2,"checks_passed":2,"pass_rate":"2/2","per_check":[{"kind":"verify","target":"On http://localhost:4291/cart, after clicking \"Open cart\", the Total reads 6","status":"pass"},{"kind":"verify","target":"On http://localhost:4291/echo, after typing Ada in the User field, the page shows \"Hello, Ada\"","status":"pass"}],"commit":"07c70df","date":"2026-11-28T03:01:32Z","verify_counts":{"total":2,"pass":2,"fail":0,"blocked":0,"not_verifiable":0,"unverified":0}}
GROUND_TRUTH_NESTED: {"checked":true,"status":"pass","checks_total":2,"checks_passed":2}
runner rc=0
```

No stderr line was printed: every Selvedge call exited 0, so the driver had nothing to report.

## What the run folder shows

`ls <scratch>/v3-demo/.selvedge/runs/` lists exactly one folder, `20261128T030132Z-422942`. It holds
`criteria.json`, `planner-input.json`, `plan.json`, `plan.sha256`, `freeze.json`, `snapshots.jsonl`,
`evidence.jsonl`, `screenshots/` and `verdict.json`. The `verdict.json` (verdict fields only):

```json
{"schema_version":1,"plan_sha256":"c1754411d9f6dcf503c922fb939321a1cb32425cddf0fb32b5b0cec89fb5ab53","plan_revision":1,"data_state":"unmanaged","criteria":{"c-79c264272869":{"verdict":"PASS","reason":null,"read_value":"Total: 6"},"c-8a89397c28b4":{"verdict":"PASS","reason":null,"read_value":"Hello, Ada"}}}
```

The two ids are the two lines, in order (`criteria.json`: `c-79c264272869` = the cart line,
`c-8a89397c28b4` = the echo line). `.selvedge/runs.jsonl` holds one `freeze` line and one `run` line for
that run id; the run line reads `"entry":"loomwright"`, `"verdict":"PASS"`,
`"counts":{"PASS":2,"FAIL":0,"BLOCKED":0,"NOT_VERIFIABLE":0}` and `"planner_tokens":263196` (the cost of
one plan; the run itself calls no model).

## What this run does not show

- Only PASS came back. FAIL, BLOCKED and NOT_VERIFIABLE mapping, the `verify 1 PASS · 1 NOT_VERIFIABLE`
  counts form, plugin-absent, refusals and an unreadable `verdict.json` are pinned with a stub
  `SELVEDGE_BIN` in `loomwright/scripts/test-run-ground-truth.sh` section (v), not by this real run.
- The run was started by hand, not from Supervisor Phase 4.5. Phase 4.5 does not set
  `GROUND_TRUTH_VERIFY_BASE` yet, so there the base ref is derived (`origin/HEAD`, else `origin/main`).

## Open items

- **`selvedge run` reads `selvedge.json` from the working tree, not the base.** In Selvedge 0.12.1,
  `selvedge/lib/runner/run.mjs` loads its config with `loadConfig({ cwd: runDir })` and `run` takes no
  `--base`. The driver passes `--base <ref>` to `plan` (its one-go form runs init, the planner, validate
  and freeze, all against the base `selvedge.json`), so a PR's edit to `selvedge.json` has no effect at plan
  time. At run time, `run` re-reads the checkout's `selvedge.json`, so the base-branch rule holds at plan
  time only. Per the 2026-11-28 owner decision this PR does not wait for that fix and Loomwright does not
  work around it (it never passes `run` a flag `run` does not list). The fix is a separate Selvedge change:
  `.supervisor/requirements/2026-11-28-081548-selvedge-run-reads-selvedge-json-from-the-base-the-plan-was-frozen-against.md`.
- **A stale `selvedge` on `PATH`.** On this machine `command -v selvedge` finds a 0.7.1 copy in the plugin
  cache. With no `SELVEDGE_BIN`, the driver uses whatever `PATH` finds first, so set `SELVEDGE_BIN`, or
  re-run `selvedge install-cli` from the current install, until the copy on `PATH` is current.

Verdict: PASS for Validation 3
