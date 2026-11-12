# Evidence: Launch Pad phase lines, before and after `launch-pad-phase.sh`

Captured 2026-11-12 on macOS (Darwin 25.6.0) with Claude Code 2.1.319 and `claude-opus-5-5`. Base `main` is
`98abee7`. "After" is branch `fix/launch-pad-phase-lines`.

**In one line:** on `main`, three headless runs printed **0** phase lines. On this branch, three runs printed
**9 of 9** (phases 1, 2, 2.5, 3, 4, 5, 5.5, 6, 7), in order.

## The gap

`agents/launch-pad.md` gives each phase an `**Output:**` block that starts with a header such as
`## Phase 2.5: FEASIBILITY`. No headless run on record printed one. `docs/evidence/design-decisions.md`
§"Validation 4" and §"Validation 5" on `feature/approach-02-design-decisions` record three such runs: V4, V5,
and a V5 rerun against a prompt edited to say "print it verbatim". The three `main` runs below reproduce the gap
on `main` itself.

## How the runs were made

Scratch project: a fresh git repo with one commit on `main` and a gitignored `.supervisor/config.json`
`{"base_branch":"main"}`. It holds a Node/Express 4 + multer API (`src/server.js` mounts one router,
`src/routes/upload.js`), a `README.md` whose `## Install` section has the typo `npm instal`, and a three-line
`CLAUDE.md` naming the stack. Each run used a fresh copy of the project:

```bash
env -u CLAUDECODE -u CLAUDE_PID claude -p --output-format stream-json --verbose \
  --permission-mode acceptEdits --allowedTools "Read,Write,Edit,Glob,Grep,Bash,Task,Agent,LSP" \
  --plugin-dir <checkout>/loomwright "/loomwright:launch-pad <goal> --non-interactive"
```

The "before" checkout is a clean `git worktree` of `origin/main` at `98abee7`. The "after" checkout is this
branch. Two counts come from each `stream.jsonl`:

```bash
# phase headers the model wrote itself (assistant text messages)
jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' stream.jsonl \
  | grep -E '^#+ Phase [0-9.]+' | sort | uniq -c
# phase lines in tool results (the script's stdout)
jq -r 'select(.type=="user") | .message.content[]? | select(.type=="tool_result")
       | (.content | if type=="array" then map(.text? // "") | join("\n") else . end)' stream.jsonl \
  | grep -E '^## Phase [0-9.]+: [A-Z]' | sort | uniq -c
```

## Results

| Run | Checkout | Goal | Session | Header text lines written by the model | Phase lines from the script | Turns, seconds |
|-----|----------|------|---------|-----------------------------|----------------------------|----------------|
| before-typo | this worktree, before any edit | typo | `7b150e99-…` | 0 | 0 | 14, 106 |
| before-main-typo | `main` `98abee7` | typo | `da532c6b-…` | 0 | 0 | 15, 104 |
| before-main-rate | `main` `98abee7` | rate limit | `e4985270-…` | 0 | 0 | 17, 370 |
| after-typo | branch, first wiring | typo | `0fb02b9f-…` | 0 | **9/9** | 14, 126 |
| after-rate | branch, first wiring | rate limit | `6b407b73-…` | 0 | **9/9** | 17, 207 |
| after-final-rate | branch HEAD (committed) | rate limit | `2f6ab723-…` | 0 | **9/9** (phase 1 twice) | 14, 166 |

Goals: typo = `goal: "fix the typo in README.md §Install"`. Rate limit = `goal: "add rate limiting to the
/api/upload route with a library"`. Every run ended `success`, and each saved its brief through the
`saved_on_pass_non_interactive` branch.

The phase lines from after-rate, as they appear in its tool results:

```text
## Phase 1: VALIDATE — 0 blockers, 1 warnings
## Phase 2: DISCOVER — 4 criteria
## Phase 2.5: FEASIBILITY — CAUTION
## Phase 3: ANALYZE — 2 modify, 1 create
## Phase 4: DECOMPOSE — 1 subtasks
## Phase 5: PACKAGE — 1 subtasks, 3 files
## Phase 5.5: PLAN REVIEW — PASS (attempt 1/3)
## Phase 6: SAVE — saved .supervisor/jobs/pending/2026-11-12-add-rate-limiting-api-upload-route.md
## Phase 7: RESULT — saved
```

## What else the runs showed

- **No "before" run used the checkout's prompt.** All three read the installed plugin
  (`~/.claude/plugins/cache/atelier/loomwright/17.36.2/agents/launch-pad.md` and its skills). On `main`,
  `commands/launch-pad.md` names `agents/launch-pad.md` relative to a plugin root it never states, so the model
  went looking and found the cache. This matches the unpinned attempts in `design-decisions.md`. The 17.36.2
  agent has the same `**Output:**` blocks, so the 0 count still measures the gap. The after runs ran
  `<checkout>/loomwright/scripts/launch-pad-phase.sh`, and after-rate and after-final-rate also read `<checkout>/loomwright/agents/launch-pad.md`.
  The new "Phase lines" rule in the command body carries `${CLAUDE_PLUGIN_ROOT}`. Both after runs used the
  checkout's absolute path from their second tool call on, which no before run did. That points to the
  variable being substituted in the command body. It is an inference from the transcripts, because the stream
  does not echo the command body.
- **Lines can arrive batched.** In after-typo the model ran phase 1 alone, then phases 2, 2.5, 3 and 4 in one
  Bash call after its analysis, then phase 5 when the brief was drafted. So each line appears once and in
  order, but it is not always printed at its own phase's boundary. The verdicts were its own (`GO`, `CAUTION`,
  `PASS (attempt 1/3)`, the saved path), and they match the briefs it saved.
- **A corrected verdict prints the line twice.** In after-final-rate the model ran phase 1 with `0 blockers, 0 warnings`, noticed the scratch repo has no git remote, and ran it again with `0 blockers, 1 warning`. Both lines are in the stream, and the second one is right.
- **The model still printed no header in its own text.** The header-text count is 0 in all six runs. The lines
  are in the transcript only because a Bash call put them there.

## Limits

- This is three runs per side, all `--non-interactive` and all reaching `saved`. The interactive path
  (questions relayed and resumed) and the abort branches (`blocked`, `aborted`) were not run. The phase-7 line
  is written to run on every path, but no run here took one of those branches.
- A tool call is still a step the model can skip. It is more dependable than prose because it is one concrete
  command per phase, and `test-launch-pad-phase.sh` fails if a phase's call is dropped from either prompt file.
  But no hook enforces it at run time, and the counts above are what supports "dependable".
- Phase 2.7 (APPROACH) is not on `main` yet. It arrives with vikashruhilgit/loomwright#895, and whichever PR
  merges second adds the row `2.7|APPROACH` to the script's table, a call in both prompt files, and a pin. The
  test's wiring check turns red if either prompt calls `launch-pad-phase.sh 2.7` before the table has that row.
