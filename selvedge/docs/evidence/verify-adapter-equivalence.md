# Evidence: `/selvedge:verify` gives the same `verdict.json` as the CLI run by hand

Recorded 2026-11-18 on the qa-split/06 branch (base commit `c0e7038` plus this change's adapter
files), Claude Code 2.1.325 on macOS. It proves the qa-split/06 criterion that a real
`/selvedge:verify` session produces the same per-criterion verdicts as the CLI run by hand on the
same frozen plan. CI cannot run a live Claude session, so this file is that proof;
`tests/test-adapter.sh` pins the deterministic parts (tools, command order, prohibitions) and reads
the subagent type below.

**Result: the same `plan_sha256` and the same per-criterion objects (step `duration_ms` excluded).
The `diff` printed nothing.**

- subagent_type the session used: `selvedge:verifier` (the stream-json `system/init` line listed
  `"agents": [… "selvedge:verifier" …]`, and the main thread's `Agent` call had
  `"subagent_type": "selvedge:verifier"`: one prefix, not doubled, because the agent's frontmatter
  `name` is the bare `verifier`)
- the plugin the session loaded: `{"name": "selvedge", "source": "selvedge@inline", "path": "<this
  checkout>/selvedge"}` (`--plugin-dir` loads only the checkout's copy)
- the adapter files the session ran (sha256 at the time of the session; unchanged when this file
  was written):
  - `agents/verifier.md` `9cdb60b38b23d2522d1be3d176f919c4593494cf9af0826c08bf62ada6edbfcb`
  - `commands/verify.md` `ce57f3738a9a7e1bfbc3b48e922463693188824cb4a502108e6a15f44c9f7733`
  - `skills/verify/SKILL.md` `c33aa330035894a0821dcb86a9a5991620b4df3e6afd288ee1b9978bdb2a0d7d`
  - `prompts/planner.md` `0d912611cd878f97921f7f4d4d6d534dbefc7e75f775687909369efe140b644d`

`$SCRATCH` below is a private temp folder; `$SELVEDGE` is this checkout's `selvedge/`; `$PWC` is the
Playwright cache `tests/lib/playwright-cache.sh` fills (`${TMPDIR}selvedge-test-pw`).

## Setup

The item 04 fixture app (`tests/fixtures/app-server.mjs`), started through its library entry
`startAppServer()` so it outlives the `serve` command's 15-minute watchdog, on
`http://localhost:55882`. A temp git repo `$SCRATCH/repo` holding:

`selvedge.json`

```json
{
  "schema_version": 1,
  "origins": ["http://localhost:55882"],
  "allow_remote": false,
  "allow_remote_mutation": false
}
```

`criteria.md`

```markdown
# Fixture shop

## Acceptance criteria

- On http://localhost:55882/cart, after clicking "Open cart", the cart's Total reads "6".
- On http://localhost:55882/cart, after opening the cart and setting Quantity to 3, the Total reads "18".
- On http://localhost:55882/echo, typing "Ada" into the User field makes the greeting read "Hello, Ada".
- The plain page looks good.
```

The last criterion is vague on purpose (`criteria check`: `vague c-c809a987088a ("looks good")`).

## 1. The live session

Headless, with a clean environment (`env -i` keeps only `HOME`, `USER`, `LOGNAME`, `LANG`,
`TMPDIR` and `PATH`, so no inherited `CLAUDE_CODE_ENTRYPOINT` or `CLAUDECODE` reaches it; user
settings are skipped so no other plugin loads):

```
cd $SCRATCH/repo
env -i HOME="$HOME" USER="$USER" LOGNAME="$USER" LANG=en_US.UTF-8 TMPDIR="$TMPDIR" \
  PATH="$SELVEDGE/bin:<node>:/opt/homebrew/bin:/usr/bin:/bin" \
  SELVEDGE_PLAYWRIGHT_MODULE="$PWC/node_modules/playwright/index.mjs" PLAYWRIGHT_BROWSERS_PATH="$PWC/browsers" \
  claude -p "/selvedge:verify criteria.md" --plugin-dir "$SELVEDGE" --setting-sources project,local \
    --allowedTools Bash Read Agent --output-format stream-json --verbose --max-budget-usd 6
```

Session `dba6b112-1843-43d4-be4b-ab798d76cc63`: `success`, 5 turns, 67 s, $0.43. What it did, read
from its stream-json transcript:

- main thread: `Bash` (`command -v selvedge; git rev-parse --show-toplevel; ls -la criteria.md`),
  `Agent` with `subagent_type: "selvedge:verifier"` and the prompt `Criteria command: selvedge
  criteria from-md criteria.md` / `Repo root: $SCRATCH/repo`, then `Read` of the run folder's
  `verdict.json` and `criteria.json`. No `selvedge comment` (a file source never posts).
- the verifier: 7 `Bash` and 2 `Read` calls, no other tool. Its `selvedge` commands, in order:
  `criteria from-md`, `criteria check`, `plan --init`, `snapshot` (twice, each with `--run-dir`),
  `plan --validate` (twice: the first named the `criteria_sha256`), `plan --freeze`, `run`,
  `verdict`. No command touched `~/.local/state/selvedge/`, and nothing wrote `plan.json` after
  the freeze.

The verifier's report:

```
SELVEDGE_VERIFY_RESULT
run_dir: $SCRATCH/repo/.selvedge/runs/20261118T021938Z-01fec2
plan_sha256: 49f5023db6df6b40fdcdac8ad6ff8dc020c88dcd2a20999e35e1d63178dde453
PASS c-2ad00cd24fbb
PASS c-dff43fdd189a
PASS c-e208613da025
NOT_VERIFIABLE criterion_not_testable c-c809a987088a
verdict NOT_VERIFIABLE $SCRATCH/repo/.selvedge/runs/20261118T021938Z-01fec2/verdict.json
```

## 2. The same frozen plan, by hand

The CLI's own re-run path (a copied folder would be refused `plan_modified`: replay the folder),
same environment variables, no model:

```
$ selvedge run --replay .selvedge/runs/20261118T021938Z-01fec2      # exit 3
PASS c-2ad00cd24fbb
PASS c-dff43fdd189a
PASS c-e208613da025
NOT_VERIFIABLE criterion_not_testable c-c809a987088a
verdict NOT_VERIFIABLE $SCRATCH/repo/.selvedge/runs/20261118T022051Z-07c622/verdict.json

$ selvedge verdict .selvedge/runs/20261118T022051Z-07c622           # exit 3
PASS c-2ad00cd24fbb
PASS c-dff43fdd189a
PASS c-e208613da025
NOT_VERIFIABLE criterion_not_testable c-c809a987088a
verdict NOT_VERIFIABLE .selvedge/runs/20261118T022051Z-07c622/verdict.json
```

## 3. The comparison

```
$ jq -r .plan_sha256 .selvedge/runs/20261118T021938Z-01fec2/verdict.json .selvedge/runs/20261118T022051Z-07c622/verdict.json
49f5023db6df6b40fdcdac8ad6ff8dc020c88dcd2a20999e35e1d63178dde453
49f5023db6df6b40fdcdac8ad6ff8dc020c88dcd2a20999e35e1d63178dde453

$ diff <(jq -S 'del(.criteria[].steps[].duration_ms) | .criteria' .selvedge/runs/20261118T021938Z-01fec2/verdict.json) \
       <(jq -S 'del(.criteria[].steps[].duration_ms) | .criteria' .selvedge/runs/20261118T022051Z-07c622/verdict.json)
$ echo $?
0
```

The diff output is empty. Over the whole file (step `duration_ms` still excluded) the only
difference is the run-level `replay_of`, `null` in the session's run and
`"20261118T021938Z-01fec2"` in the hand run, as it is by construction. Both runs: `plan_revision`
1, `prior_revisions` `[]`, `data_state` `unmanaged`.

Per criterion (both files):

| Criterion | Verdict | Reason | Read value | Expected |
|---|---|---|---|---|
| `c-2ad00cd24fbb` | PASS | — | `Total: 6` | `matches ^Total: 6$` |
| `c-dff43fdd189a` | PASS | — | `Total: 18` | `matches ^Total: 18$` |
| `c-e208613da025` | PASS | — | `Hello, Ada` | `equals Hello, Ada` |
| `c-c809a987088a` | NOT_VERIFIABLE | `criterion_not_testable` | — | — |

## An earlier session, for the record

A first session the same day, on the same adapter text except the verifier's `token_budget:` value
(frontmatter Claude Code does not read), wrote a plan that marked two assumptions `material: true`
("the Total updates on input without a further action", "the greeting updates on input"), so those
two criteria were NOT_VERIFIABLE `material_assumption` with matching reads. Its hand replay matched
it the same way (equal `plan_sha256` `c9518d9a70ba…`, empty diff). The verdict differs between the
two sessions because each wrote its own plan; for a given frozen plan the session and the CLI agree,
which is what this file claims. That folder was cleared before the session above, so the session's
plan is revision 1.

## Honest limits

- One session, one fixture app, one criteria file from a file source. The PR source (`from-pr`) and
  posting through `selvedge comment` after the question were not exercised live: a `claude -p`
  session cannot ask, and the command then posts nothing.
- The session ran with `--allowedTools Bash Read Agent` in a temp repo. The verifier's own tool list
  (Bash, Read) is the frontmatter's; its prohibitions are instructions, checked here only by reading
  the transcript.
