# Evidence — lane-scope-regate Part B, Validation 2 (a held lane and one AUT-OVERLAP question)

**Status: RUN LIVE. No verdict declared.** A live `/automate --parallel 2` held both lanes before their Supervisor
phase and the coordinator asked `AUT-OVERLAP` naming the shared file. The run differs from the criterion's shape
in two places (see "Why no verdict"), and the owner should judge them. Run 2026-11-05, review-fix iteration 1, on
this branch's checkout.

## Fixture

A scratch repo under `$TMPDIR` (`lsr-b13/`, never this repo):
- `origin.git` is a local bare repo.
- `primary/` is a clone of it with `.supervisor/config.json` `{"base_branch": "main"}`. Branch mode is off, so
  there is no metadata branch.
- The files are `src/greet.sh`, `src/farewell.sh`, `src/lib.sh` (shared helpers), `tests/test-greet.sh` and
  `tests/test-farewell.sh`, plus a CLAUDE.md rule "every string helper lives in `src/lib.sh`".

There are two committed items:
- `reqs/01-shout-flag.md`: Touches `src/greet.sh`, `tests/test-greet.sh`. Its AC needs a new `upper` helper in
  `src/lib.sh`.
- `reqs/02-whisper-flag.md`: Touches `src/farewell.sh`, `tests/test-farewell.sh`. Its AC needs a new `lower` helper
  in `src/lib.sh`.

The declared Touches are disjoint, and both briefs plan `src/lib.sh`.

`PATH` starts with a scratch `gh` stub, because real `gh` refuses a non-GitHub remote. A first attempt parked both
lanes `trail_pr_open` on exactly that error. The stub only answers `pr list` with `[]` and fails every other call.
Its whole log for this run is 2 × `auth status` (failed) and the two lanes' trail-gate `pr list`. Nothing was
pushed, and no PR exists.

## Commands

```
cd lsr-b13/primary
printf '%s\n' '{"type":"user","message":{"role":"user","content":"/loomwright:automate --folder reqs --parallel 2"}}' \
| env PATH=<scratch>/bin:$PATH CLAUDE_PLUGIN_ROOT=<checkout>/loomwright CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 \
  claude -p --input-format stream-json --output-format stream-json --verbose --permission-prompt-tool stdio \
  --permission-mode acceptEdits --allowedTools "Bash,Read,Edit,Write,Glob,Grep,Task,Agent,AskUserQuestion" \
  --plugin-dir <checkout>/loomwright \
  --settings '{"hooks":{"PreToolUse":[{"matcher":"AskUserQuestion","hooks":[{"type":"command","command":"bash <scratch>/hook.sh"}]}]}}'
```

The hook records every coordinator ask. It defers `AUT-OVERLAP` / `LP-SCOPE`, and would answer a relayed
`LP-SAVE*` with its `Save…` label or a wave-policy question with its `No…` label; neither of those came up. The
lanes auto-answered their own `LP-SAVE-NOTE`.

The first coordinator session (`43882b45-…`, $1.43) deferred on the question shown below and ended. A second
session ran the same command with `/loomwright:automate --resume automate-2026-11-05-003210` ($0.63).

## lane-status, after both saves (lane process ended, no code written)

```
lane-status: automate-2026-11-05-003210 — 2 lane(s) — 2026-11-04T19:11:13Z — started 2026-11-04T19:02:10Z
policy: none answered
wave 1 (not built yet): lanes L1,L2
L1  scope_hold  item=reqs/01-shout-flag.md  pr=-  ended=2026-11-04T19:08:22Z  path=<scratch>/primary-lanes/automate-2026-11-05-003210/L1
    steps: Pick ✓ · Plan ✓ · [Build 2m waiting] · Heal · Drain · Decide · Merge  (started 2026-11-04T19:03:41Z)
    progress: 2026-11-04T19:08:22Z scope_hold — .supervisor/jobs/pending/2026-11-05-shout-flag-for-greet.md saved; held before the Supervisor phase for the coordinator's scope re-gate (lane-scope-check)
L2  scope_hold  item=reqs/02-whisper-flag.md  pr=-  ended=2026-11-04T19:09:03Z  path=<scratch>/primary-lanes/automate-2026-11-05-003210/L2
    steps: Pick ✓ · Plan ✓ · [Build 2m waiting] · Heal · Drain · Decide · Merge  (started 2026-11-04T19:04:04Z)
    progress: 2026-11-04T19:09:03Z scope_hold — .supervisor/jobs/pending/2026-11-05-whisper-flag.md saved; held before the Supervisor phase for the coordinator's scope re-gate (lane-scope-check)
```

Each lane's `## Progress` ends with `launch-pad saved <brief>` and then the `scope_hold —` line, with no
Supervisor session. Both clones are still on `main` at the seed commit with a clean tree. Each lane brief carries
the lane branch's record (`## Scope widening` / `- src/lib.sh` / `- decision: pending-coordinator`). Neither lane's
Launch Pad asked `LP-SCOPE`.

## The coordinator's questions

The first session handled L1's hold at 19:08, before L2 had saved. `lane-scope-check` then read `clear` plus
`widening — src/lib.sh`. Per step 8a, that combination gets an LP-SCOPE question, and the coordinator asked one.
It was recorded and deferred, so it was never answered:

```
header: LP-SCOPE
question: Lane L1 (reqs/01-shout-flag.md, the --shout flag) saved a plan that widens its scope beyond its declared Touches to: src/lib.sh (needed: the AC puts the new `upper` helper there). The scope check against lane L2 reads clear only because L2 has not saved its plan yet; L2's item also needs a `lower` helper in src/lib.sh, so L2 will most likely be flagged as overlapping L1 when it saves, and you'd get an AUT-OVERLAP question then. How should L1 proceed?
labels: Extend Touches · Revise plan · Stop
```

The resumed session re-ran `lane-scope-check` for both held lanes:

```
== L1
overlap — src/lib.sh shared with L2 (saved brief)
widening — src/lib.sh
== L2
overlap — src/lib.sh shared with L1 (saved brief)
widening — src/lib.sh
```

Then it made ONE `AskUserQuestion` call. The call carries one `AUT-OVERLAP` question per held lane, and each names
the shared file:

```
header: AUT-OVERLAP
question: AUT-OVERLAP — lane L1 (reqs/01-shout-flag.md) shares src/lib.sh with lane L2 (reqs/02-whisper-flag.md, saved brief). L1's brief also lists src/lib.sh as a pending scope widening. How should L1 proceed?
labels: Serialize · Continue in parallel · Defer to next wave · Revise

header: AUT-OVERLAP
question: AUT-OVERLAP — lane L2 (reqs/02-whisper-flag.md) shares src/lib.sh with lane L1 (reqs/01-shout-flag.md, saved brief). L2's brief also lists src/lib.sh as a pending scope widening. How should L2 proceed?
labels: Serialize · Continue in parallel · Defer to next wave · Revise
```

Nothing was answered, so no `lane-scope-decide` ran. Both lanes remain held.

## Why no verdict

- The criterion expects the second lane held and ONE `AUT-OVERLAP` question. Because both fixture briefs widen
  into the same file, the run asked about the first lane too.
  - L1 got an `LP-SCOPE` question while L2 was unsaved.
  - After L2 saved, the one `AUT-OVERLAP` call carried two questions, one per held lane.
  - That matches step 8a (one question per held lane), but not the criterion's literal "ONE question".
- L1's widening of `src/lib.sh` appeared in two questions: the unanswered `LP-SCOPE`, then again inside its
  `AUT-OVERLAP`. Step 8a says "the owner is never asked twice about one widening".
  - The first ask was never answered and its session ended; a re-check after the sibling saves is by design.
  - Whether this counts as asking twice is for the owner to decide, not this file.
- A fixture where only the second lane's brief reaches into the first lane's Touches would match the criterion's
  shape. It races too: the first lane's save reads `clear` with no widening, so the coordinator would release it
  into a Supervisor phase, which pushes. That was not run, under the "never push" constraint.
