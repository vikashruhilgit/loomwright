# Evidence — lane-scope-regate Part A, Validation 2 (one LP-SCOPE question)

A live `/launch-pad` on a fixture item whose ACs need one file outside its `## Touches`, run headless with the
phase-session relay shape (a PreToolUse[AskUserQuestion] hook that records each ask; it answers `LP-SCOPE` with
the `Extend Touches` label and defers every other question, so the session stops at the save question with that
question recorded). Final run 2026-11-05, review-fix iteration 1, on this branch's checkout after the action 1a
wording fix below.

## Fixture

A scratch git repo under `$TMPDIR` (`lsr-a12/fx/`, never this repo): `src/greet.sh`, `src/lib.sh` (shared string
helpers), `tests/test-greet.sh`, a CLAUDE.md rule "every string helper lives in `src/lib.sh`",
`.supervisor/config.json` `{"base_branch": "main"}`, and `.supervisor/requirements/01-shout-flag.md`:

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
printf '%s\n' '{"type":"user","message":{"role":"user","content":"/loomwright:launch-pad goal: .supervisor/requirements/01-shout-flag.md --no-auto-gates"}}' \
| env CLAUDE_PLUGIN_ROOT=<checkout>/loomwright CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 \
  claude -p --input-format stream-json --output-format stream-json --verbose --permission-prompt-tool stdio \
  --permission-mode acceptEdits --allowedTools "Bash,Read,Edit,Write,Glob,Grep,Task,Agent,AskUserQuestion" \
  --plugin-dir <checkout>/loomwright \
  --append-system-prompt "Harness note: the loomwright plugin under test is loaded from --plugin-dir; its root is the CLAUDE_PLUGIN_ROOT environment variable (<checkout>/loomwright). Read every plugin file and run every plugin script from there; never from ~/.claude/plugins/cache." \
  --settings '{"hooks":{"PreToolUse":[{"matcher":"AskUserQuestion","hooks":[{"type":"command","command":"bash <scratch>/hook.sh"}]}]}}'
```

Claude Code 2.1.314. Session `ceaff768-…`, 16 turns, $1.55, ended `stop_reason: tool_deferred` at the save
question. The `--append-system-prompt` harness note is there because two earlier attempts found the plugin by
`ls -d ~/.claude/plugins/cache/*/loomwright/*` and read the INSTALLED copy's prompt, which has no LP-SCOPE step.
Those runs test nothing on this branch, and their output is not used below. With the note set, the session reads
and runs only the checkout. The only `plugins/cache` string in its stream is the `system/init` plugin list, for
another plugin.

## The helper's output (Bash call in the Launch Pad session, after Plan Review)

```
$ bash "$CLAUDE_PLUGIN_ROOT/scripts/automate-lanes.sh" scope-outside .supervisor/requirements/01-shout-flag.md <scratch brief>; echo rc=$?; ls .supervisor/lane.json
outside 1
src/lib.sh
rc=0
ls: .supervisor/lane.json: No such file or directory
```

Plan Review: `decision: PASS`, `requirement_fit: fulfils`, `issues: []` (attempt 1). Then the session asked
exactly two questions, in this order.

## The one LP-SCOPE question (recorded tool_input)

```
{
  "questions": [
    {
      "question": "Plan Review passed, but the plan edits 1 path outside the requirement's Touches (src/greet.sh, tests/test-greet.sh): src/lib.sh. The requirement's own 3rd acceptance criterion and the CLAUDE.md rule both put the new `upper` helper there. How should this be handled?",
      "header": "LP-SCOPE",
      "options": [
        {
          "label": "Extend Touches",
          "description": "Accept src/lib.sh; it is recorded in the brief's ## Scope widening section. The plan stays the same, so the PASS stands."
        },
        {
          "label": "Revise plan",
          "description": "Rework the plan to stay inside Touches and re-run Plan Review (uses an attempt). This would break AC3 and the CLAUDE.md rule."
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

Answered `Extend Touches`. The scratch brief then carried, right after `## Acceptance Criteria`:

```
## Scope widening
- src/lib.sh
- accepted: LP-SCOPE 2026-11-05
```

## The save question that followed (recorded tool_input)

```
{
  "questions": [
    {
      "question": "Plan Review PASSed (attempt 1/3, 0 issues, requirement fit: fulfils) for the --shout flag brief: 1 subtask, single agent, 3 small bash files modified, `upper` implemented with `tr` so it works on bash 3.2. What next?",
      "header": "LP-SAVE",
      "options": [
        {
          "label": "Save and exit",
          "description": "Write .supervisor/jobs/pending/2026-11-05-shout-flag.md and print the /supervisor command."
        },
        {
          "label": "Refine further",
          "description": "Answer clarifying questions and update sections. This voids the PASS and re-runs Plan Review (2 attempts left)."
        },
        {
          "label": "Edit sections",
          "description": "Name the changes to make in place. This voids the PASS and re-runs Plan Review."
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

- A1: one question under `header: "LP-SCOPE"`, asked BEFORE the save question. It lists the helper's complete
  list (`src/lib.sh`) and has exactly the labels `Extend Touches` · `Revise plan` · `Stop`.
- A2: `Extend Touches` wrote the `## Scope widening` record (`- src/lib.sh`, `- accepted: LP-SCOPE <date>`), and
  the plan and the PASS stood.
- A3: the save question does not mention `src/lib.sh` or the widening. Its header is `LP-SAVE`, which is correct
  here because Plan Review left no issue or note (`issues: []`), so nothing calls for `LP-SAVE-NOTE`.

History (for the record, not the verdict):
- The first live run (2026-11-04) asked the same LP-SCOPE question, but its save question named the accepted path
  and used `LP-SAVE` although a LOW note remained.
- A second run (iteration 1, before this file's final run) read the checkout through its plugin root. It used
  `LP-SAVE-NOTE` correctly for its LOW note, but still wrote "src/lib.sh is now recorded in Scope widening".
- So action 1a in `loomwright/agents/launch-pad.md` now has the model check the save question's text before
  asking, and delete any sentence that names a listed path or says `Scope widening`. The run above is the re-run
  after that fix.
- Honest limit: the final run's Plan Review left no note, so the "a remaining note still means `LP-SAVE-NOTE`"
  branch after an accepted widening was observed only in the second run, before the last wording change.

Verdict: PASS for Validation 2
