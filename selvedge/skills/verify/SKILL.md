---
name: verify
description: Check finished work against its acceptance criteria with the selvedge CLI - criteria, a frozen plan, a model-free run, a verdict per criterion derived from evidence alone. The same workflow /selvedge:verify runs, for any agent host. Use when asked to verify a PR, a brief or pasted criteria against a running app.
version: "1.0.0"
lastUpdated: "2026-11-18"
---

# Selvedge verify

Checks finished work against its acceptance criteria and reports an evidenced PASS / FAIL /
BLOCKED / NOT_VERIFIABLE per criterion. It is the workflow of the Claude Code command
`/selvedge:verify` and its `verifier` subagent (`selvedge/agents/verifier.md`), written for any
agent host that can run shell commands and read files.

**Who runs it.** Run it in an agent that did not write the code: the implementing agent checks its
own mental model. If your host can start a separate agent, start one with only a shell and a file
reader and give it this workflow; if it cannot, run it yourself and say so in the report.

**What it needs.** The `selvedge` CLI on `PATH` (`selvedge install-cli`), Node.js >= 18,
Playwright (see the README's "How Playwright is found"), a committed `selvedge.json` listing the
app's origin, and the app running. `gh` for a PR source.

## Criteria source

| The source is | Criteria command |
|---|---|
| a PR number | `selvedge criteria from-pr <n>` |
| a markdown file | `selvedge criteria from-md <file>` |
| pasted text | `selvedge criteria from-text`, the text on stdin |

## The plan rules

The rules a plan must follow are selvedge's planner prompt, `prompts/planner.md` in the plugin
(its "Steps" and "The rules the lint enforces" sections). Read it before writing a plan; this
skill does not restate it. `selvedge plan --validate` lists every rule a plan breaks.

## Workflow

Run these in this order, at the repo root. Copy each path a command prints; do not rely on shell
state between calls.

1. `selvedge criteria <from-pr|from-md|from-text> …` — write the criteria to a temp file, then
   `selvedge criteria check <that file>`. Every criterion it calls vague is not planned: list it
   under `not_planned` with `"reason": "criterion_not_testable"` and the rewrite it printed.
2. `selvedge plan --init <the criteria file>` — creates the run folder and prints `<run-dir>`.
3. `selvedge snapshot <url> --run-dir <run-dir>` (with `--steps /dev/stdin` for a page state
   that needs clicks first) — see each page a criterion needs before naming its controls; every
   call counts against the folder's budget.
4. `selvedge plan --validate <run-dir>/plan.json` — after writing the plan there. For
   `criteria_sha256`, the lint's `criteria_sha_mismatch` line names criteria.json's hash. Rewrite and
   validate until it prints no problem.
5. `selvedge plan --freeze <run-dir>` — lints and hashes the plan; it is fixed from here.
6. `selvedge run <run-dir>` — executes the frozen plan in the guarded browser with no model. Exit
   1, 2 or 3 is a FAIL, BLOCKED or NOT_VERIFIABLE outcome, not an error to retry.
7. `selvedge verdict <run-dir>` — re-derives `verdict.json` and prints one line per criterion.

Report the table from `<run-dir>/verdict.json` (per criterion: verdict, reason, the criterion text
from `<run-dir>/criteria.json`), the overall verdict, `plan_sha256` and the run folder.

## Never

- Never edit `plan.json` or `plan.sha256` after `selvedge plan --freeze`: a new plan is a new `selvedge plan --init` folder.
- Never read anything under `~/.local/state/selvedge/` (the stored sign-in session) or print an environment variable's value.
- Never write a verdict yourself; never put a secret in a plan (use `{{NAME}}`).
- Never look at the app outside `selvedge snapshot`, and never run `selvedge env approve`, `selvedge env hook` or `selvedge auth setup` for the user.

## Posting to the PR

Only when the source was a PR number, and only after asking the user once and getting a yes:
`selvedge comment <run-dir> --pr <n> --yes`. It posts one text-only comment and updates it in
place on later runs. A host that cannot ask the user never posts.
