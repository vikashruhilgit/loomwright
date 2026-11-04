# Evidence — lane-scope-regate Part A, Validation 2 (one LP-SCOPE question)

A live `/launch-pad` on a fixture item whose ACs need one file outside its `## Touches`, run headless with the
phase-session relay shape (a PreToolUse[AskUserQuestion] hook that records each ask and defers; the answer is
supplied on `--resume`, exactly as `automate-lanes.sh phase-answer` does). Run 2026-11-04, worker of subtask 1.

## Fixture

A scratch git repo (`fx/`): `src/greet.sh`, `src/lib.sh` (shared string helpers), `tests/test-greet.sh`, a
CLAUDE.md rule "every string helper lives in `src/lib.sh`", `.supervisor/config.json` `{"base_branch": "main"}`,
and `.supervisor/requirements/01-shout-flag.md`:

```
## Acceptance Criteria
- [ ] Given `bash src/greet.sh --shout ada`, then it prints `HELLO, ADA!`.
- [ ] Given no `--shout`, then the output is unchanged (`bash src/greet.sh ada` prints `Hello, ada!`).
- [ ] The upper-casing is a new `upper` helper in `src/lib.sh` (the project rule: every string helper lives in `src/lib.sh`), and `tests/test-greet.sh` covers both cases.

## Touches
src/greet.sh
tests/test-greet.sh
```

## Command

```
claude -p --input-format stream-json --output-format stream-json --verbose --permission-prompt-tool stdio \
  --permission-mode acceptEdits --allowedTools "Bash,Read,Edit,Write,Glob,Grep,Task,Agent,AskUserQuestion" \
  --plugin-dir <checkout>/loomwright --settings '{"hooks":{"PreToolUse":[{"matcher":"AskUserQuestion","hooks":[{"type":"command","command":"bash <scratch>/hook.sh"}]}]}}'
stdin: {"type":"user","message":{"role":"user","content":"/loomwright:launch-pad goal: .supervisor/requirements/01-shout-flag.md --no-auto-gates"}}
```

A first attempt stopped at Phase 1 (`LP-CLARIFY`: the fixture had no origin remote, so `resolve-base-branch.sh`
printed `base_branch_unresolved`, the correct fail-closed branch); the fixture then got its `base_branch` config
and the run below started fresh.

## The helper's output (Bash call in the Launch Pad session, before the Plan Reviewer spawn)

```
$ bash $P/scripts/automate-lanes.sh scope-outside .supervisor/requirements/01-shout-flag.md <scratch brief>
outside 1
src/lib.sh
scope rc=0
```

Plan Review: `decision: PASS` (attempt 1, one LOW note). Then the session's next and only question:

## The one LP-SCOPE question (recorded tool_input)

```
{
  "questions": [
    {
      "question": "LP-SCOPE: The brief edits a path outside requirement 01-shout-flag's Touches (src/greet.sh, tests/test-greet.sh). Outside path: src/lib.sh. AC 3 and the CLAUDE.md rule require the new `upper` helper to live there. How should Launch Pad proceed?",
      "header": "LP-SCOPE",
      "options": [
        {
          "label": "Extend Touches",
          "description": "Record src/lib.sh in the brief's `## Scope widening` section. The plan is unchanged and the PASS stands."
        },
        {
          "label": "Revise plan",
          "description": "Re-plan to stay inside Touches and re-run Plan Review. This uses one attempt, and no compliant plan exists: putting the helper in greet.sh breaks AC 3 and CLAUDE.md."
        },
        {
          "label": "Stop",
          "description": "Save nothing (status: discarded)."
        }
      ],
      "multiSelect": false
    }
  ]
}
```

Answered `Extend Touches` (resume of the same session). The brief then carried, right after `## Acceptance Criteria`:

```
## Scope widening
- src/lib.sh
- accepted: LP-SCOPE 2026-11-04
```

## The save question that followed (recorded tool_input)

```
{
  "questions": [
    {
      "question": "LP-SAVE-NOTE: The shout-flag brief passed Plan Review on attempt 1 with one LOW note: no test covers `bash src/greet.sh --shout` with no name (it would print HELLO, WORLD!). The requirement doesn't ask for it. src/lib.sh is now recorded under Scope widening. Separate warning: the repo has no git remote, so Supervisor can't push or open a PR. What next?",
      "header": "LP-SAVE",
      "options": [
        {
          "label": "Save and exit",
          "description": "Write the brief to .supervisor/jobs/pending/2026-11-04-shout-flag.md and print the /supervisor command."
        },
        {
          "label": "Refine further",
          "description": "Change the brief, e.g. add the no-name AC, then re-run Plan Review (uses 1 of the 2 remaining attempts)."
        },
        {
          "label": "Edit sections",
          "description": "Name the sections to change. Plan Review re-runs afterward (uses 1 attempt)."
        },
        {
          "label": "Discard",
          "description": "Cancel without saving."
        }
      ],
      "multiSelect": false
    }
  ]
}
```

## Result

- Observed as specified: one question under `header: "LP-SCOPE"`, BEFORE the save question, listing the
  helper's complete list (`src/lib.sh`), with exactly `Extend Touches` · `Revise plan` · `Stop`; `Extend Touches`
  wrote the `## Scope widening` record; the save question followed.
- Observed deviations (both model behaviour at the save question, not the helper):
  1. The save question still names the accepted path ("src/lib.sh is now recorded under Scope widening"), where
     A3 says it no longer mentions it.
  2. It carried `header: "LP-SAVE"` although a LOW Plan Review note remained, where Phase 6 action 3 requires
     `LP-SAVE-NOTE` (its own question text even says "LP-SAVE-NOTE").
  Fix applied after this run: action 1a's wording now says the save question names none of the paths "not even as
  recorded", and that a remaining issue or note still means `LP-SAVE-NOTE`. That fix was NOT re-run live.
- Harness note: the session's Bash environment inherited the parent session's `CLAUDE_PLUGIN_ROOT` (the installed
  17.31.0 cache, which has no `scope-outside`); the model found and used the `--plugin-dir` checkout instead. A
  re-run should `env -u CLAUDE_PLUGIN_ROOT`.

No `Verdict` line is declared: the run shows the LP-SCOPE question as specified, but the save question that
followed it deviated, and the corrected wording has not been observed live. A re-run of this fixture after the
fix decides the verdict.
