---
description: Check finished work against its acceptance criteria with selvedge - a separate Bash+Read verifier plans, freezes and runs, and selvedge derives each verdict from evidence alone
argument-hint: "[PR number | criteria file | pasted criteria]"
---

# /selvedge:verify

Checks finished work against its acceptance criteria. You (the main thread) resolve where the
criteria come from, hand the work to the `verifier` subagent (tools: Bash and Read only), show
the verdict table selvedge wrote, and, for a PR, post it only if the user says so. You never
write a plan or a verdict yourself.

Criteria source: `$ARGUMENTS`

## 1. Resolve the criteria command

| `$ARGUMENTS` is | Criteria command for the verifier |
|---|---|
| a PR number (`123` or `#123`) | `selvedge criteria from-pr <n>` |
| the path of an existing file | `selvedge criteria from-md <file>` |
| anything else: pasted text | `selvedge criteria from-text`, the text on stdin |

Empty `$ARGUMENTS`: print `usage: /selvedge:verify <PR number | criteria file | pasted criteria>`
and stop. Check `command -v selvedge` first; when it finds nothing, tell the user to run
`<plugin dir>/bin/selvedge install-cli` and stop.

## 2. Spawn the verifier

Use the Agent tool with `subagent_type: "selvedge:verifier"`. Its prompt gives the criteria
command from step 1 (with the pasted text verbatim, for `from-text`) and the repo root
(`git rev-parse --show-toplevel`). Nothing else: it works from the CLI, not from your reading of
the code. Never do its work in the main thread if the spawn fails: report the error and stop.

## 3. Report the verdict table

Take `run_dir:` from the verifier's `SELVEDGE_VERIFY_RESULT` block, then Read
`<run_dir>/verdict.json` and `<run_dir>/criteria.json` yourself: the table comes from those files,
never from the verifier's prose. One row per criterion: verdict, reason (BLOCKED /
NOT_VERIFIABLE), the criterion text. Then the overall verdict, `plan_sha256` and the run folder.
If the block says `stopped:`, report that reason and stop.

## 4. Post to the PR (PR source only)

Only when step 1 resolved a PR number, and never by default:

- Ask before posting: ask the user once, "Post this verdict to PR #<n> as one selvedge comment (updated in place on later runs)? (y/N)".
- On an explicit yes, run `selvedge comment <run_dir> --pr <n> --yes` and print the comment URL it
  prints. Any other answer, or no way to ask (a non-interactive session), posts nothing.

A file or pasted-text source never posts.
