# Evidence — Product Owner stories carry a gate-parseable Validation section (V4)

Real output from live headless `/product-owner` runs, captured 2026-11-02 on branch
`feature/requirement-to-plan-checks-2`. The Product Owner prompt, command and Story Template the runs
loaded are the ones committed in `8b47c3213d0d`. The runs read the uncommitted working tree, which
held exactly those files for runs 2 and 3. Run 1 was already running when one last edit landed, so it
may have loaded the earlier text. That edit swapped the order of two bullets in Responsibilities 3a
step 3 and changed no wording. The transcript does not echo the expanded command, so which order run 1
saw is not recorded. Nothing below is hand-written except the prose and the headings. The only edit to the
transcripts is path redaction: the branch checkout reads `<branch>`, the scratch project `<scratch>`
and its parent directory `<scratchpad>`.

## Which plugin copy ran

Every run's `init` event lists one `loomwright` plugin, loaded from the branch (`--plugin-dir`), which
replaces the installed copy of the same name for that session:

```text
run1: [{"name": "loomwright", "path": "<branch>/loomwright", "source": "loomwright@inline", "version": "17.26.0"}]
run2: [{"name": "loomwright", "path": "<branch>/loomwright", "source": "loomwright@inline", "version": "17.26.0"}]
run3: [{"name": "loomwright", "path": "<branch>/loomwright", "source": "loomwright@inline", "version": "17.26.0"}]
```

The command name the session lists is `loomwright:product-owner`, so the prompts call it by that name.

## Scratch project

A throwaway git repository (`git init`, one commit) holding a tiny Python CLI: `notes/format.py`
(`format_duration`), `notes/cli.py`, `tests/test_format.py`, and `githooks/commit-msg` (an accept-all
stub). No `.beads/`, no `.agent/`, so Product Owner runs in file-fallback mode with no house rules.
Its `CLAUDE.md`, verbatim:

```markdown
# CLAUDE.md — notes-cli

A small Python command-line tool for keeping team notes in a git repository.

## Commands
- Test command: `python3 -m unittest discover -s tests` (the project's only CI check)

## Structure
- `notes/cli.py` — the `notes` command (add, list)
- `notes/format.py` — pure formatting helpers (`format_duration(seconds)`)
- `githooks/` — the repo's git hooks, installed with `git config core.hooksPath githooks`; `githooks/commit-msg` exists and currently accepts every message
- `tests/` — unittest suites

## Domain Knowledge

### User Roles
| Role | Description | Primary Goals |
|------|-------------|---------------|
| Developer | Commits notes and code to the repo | Fast, traceable commits |
| Team lead | Reads notes and commit history | Every change traceable to a ticket |

### Business Rules
- Every commit message must reference a ticket id of the form `NOTE-<number>` (not enforced yet)
- Durations are shown to users as hours and minutes (`2h 5m`)

### Domain Terminology
| Term | Definition |
|------|------------|
| Ticket id | `NOTE-<number>`, e.g. `NOTE-42` |
```

## Exact commands

The runner (`<scratchpad>/run-po.sh`), verbatim. `$1` names the output files, `$2` is the prompt:

```bash
#!/usr/bin/env bash
# run-po.sh <out-prefix> <prompt> — one headless /product-owner run in the scratch project.
S="$(cd "$(dirname "$0")" && pwd)"
cd "$S/po-v4-project" || exit 9
claude -p "$2" \
  --plugin-dir <branch>/loomwright \
  --output-format stream-json --verbose \
  --permission-mode acceptEdits --permission-prompts none \
  --allowedTools "Bash(bash:*) Bash(mkdir:*) Bash(ls:*) Bash(date:*) Bash(test:*) Bash(git log:*) Bash(git status:*) Bash(cat:*) Bash(echo:*) Bash(head:*) Read Write Edit Glob Grep" \
  --no-session-persistence --max-budget-usd 6 < /dev/null > "$S/$1.jsonl" 2> "$S/$1.err"
echo "rc=$?" >> "$S/$1.done"
```

```bash
bash <scratchpad>/run-po.sh run1 '/loomwright:product-owner feature: "when a developer commits with a message that has no NOTE-<number> ticket id, the commit is rejected and the developer is told how to fix the message" --non-interactive'
bash <scratchpad>/run-po.sh run2 '/loomwright:product-owner feature: "durations of 24 hours or more are shown as days, hours and minutes, e.g. 90000 seconds as 1d 1h 0m" --non-interactive'
bash <scratchpad>/run-po.sh run3 '/loomwright:product-owner feature: "format_duration rejects a negative number of seconds with a ValueError that names the value, instead of returning a wrong string" --non-interactive'
```

Runs 1 and 2 used the runner without `Bash(echo:*) Bash(head:*)` in `--allowedTools`; those two
entries were added before run 3, after run 2's compound `…; echo exit=$?` calls were denied.

| Run | Prompt kind | Result |
|---|---|---|
| run1 | outcome shown only in a running system (a git hook firing) | is_error=False num_turns=16 total_cost_usd=0.67 duration_ms=85383; persisted `2026-11-02-184329-reject-commits-without-a-ticket-id.md` |
| run2 | static proof only (a pure helper) | is_error=False num_turns=10 total_cost_usd=0.50 duration_ms=47931; **persisted nothing** (see below) |
| run3 | static proof only (a pure helper), replacing run2 | is_error=False num_turns=13 total_cost_usd=0.56 duration_ms=57700; persisted `2026-11-02-190000-format-duration-rejects-negative-seconds.md` |

**Run 2 persisted nothing, correctly.** The prompt contradicted the scratch `CLAUDE.md` business rule
"Durations are shown to users as hours and minutes", so Product Owner raised an architecture conflict
and, unable to ask (`--non-interactive`), took its can't-ask branch. Its lines, verbatim:

```text
- [!] **Architecture conflicts (1):** the request contradicts the CLAUDE.md business rule *"Durations are shown to users as hours and minutes (`2h 5m`)"*. Building it changes a documented domain rule, not just code. CLAUDE.md is the authority, so whoever owns that rule (the Team lead role) has to approve the amendment. I won't settle that for them.
po_gate: needs_owner (1 flags)
```

That was the scratch project's fault, not the feature's, so run 3 used a static-only prompt that
conflicts with nothing.

**Honest limits of the runs.**
- The headless permission set has no approver, so some of Product Owner's own Bash calls were denied
  (2 in run1, 3 in run2, 3 in run3, counted from each run's stream-json transcript, which is not
  committed). In run3 that included its `read-rules.sh` / `read-product.sh` calls, so it checked
  for `.agent/` with Glob instead, and it ran no in-session `plan-waves --lint`. The lint below was run
  separately on both persisted files.
- Run3's filename timestamp `190000` was not taken from `date` (run3 made no `date` call); the file's
  write time is 2026-11-02 18:46:47 local (IST). The filename still has the `YYYY-MM-DD-HHMMSS-` shape the
  prior-stories glob reads.
- The running-system entry of story 1 was not exercised. This evidence shows that the story
  carries the entry and that the validation gate reads it. It does not show that the hook works:
  nothing was built.

## Story 1 — running-system outcome (run1), verbatim

`<scratch>/.supervisor/requirements/2026-11-02-184329-reject-commits-without-a-ticket-id.md`:

```markdown
# Reject commits without a ticket id (type: story)

**As a** Developer committing to the notes repo,
**I want** a commit whose message has no `NOTE-<number>` ticket id to be rejected with a message telling me how to fix it,
**so that** every change is traceable to a ticket (the Team lead's goal) and I learn the format at the moment I get it wrong, not in review.

Business rule (CLAUDE.md, currently "not enforced yet"): every commit message must reference a ticket id of the form `NOTE-<number>`, e.g. `NOTE-42`.

## Acceptance Criteria

**Happy path**
- [ ] Given the repo's hooks are installed (`git config core.hooksPath githooks`), when a developer commits with a message containing a ticket id (e.g. `NOTE-42: add list command`), then the commit is created.
- [ ] Given hooks are installed, when the ticket id appears anywhere in the message — subject or body (e.g. subject `add list command`, body `Refs NOTE-7`) — then the commit is created.

**Rejection and guidance**
- [ ] Given hooks are installed, when a developer commits with a message that contains no ticket id (e.g. `fix typo`), then the commit is NOT created and the hook exits non-zero.
- [ ] Given a rejected commit, then the output (on stderr) states that a ticket id is required, shows the required form `NOTE-<number>`, gives a concrete corrected example (e.g. `NOTE-42: fix typo`), and tells the developer to re-run `git commit` with a corrected message (nothing was committed, so there is nothing to amend).

**Edge cases**
- [ ] Given a message with `NOTE-` but no digits (e.g. `NOTE-: fix`, `NOTE-abc`), then the commit is rejected with the same guidance.
- [ ] Given a lowercase id (e.g. `note-42`), then the commit is rejected with the same guidance (the domain form is uppercase `NOTE`; see Assumptions).
- [ ] Given an id embedded in a longer word (e.g. `XNOTE-42`), then the commit is rejected.
- [ ] Given a message whose only `NOTE-<number>` is on a `#` comment line that git strips from the final message, then the commit is rejected.
- [ ] Given an empty message, then git's own empty-message abort behaviour is unchanged (no traceback or confusing double error from the hook).

**Regression**
- [ ] The existing test suite still passes and nothing outside commit-message validation changes behaviour.
- [ ] CLAUDE.md no longer says the ticket-id rule is "not enforced yet" or that `githooks/commit-msg` "accepts every message".

## Non-goals
- Enforcing that developers install the hooks (`core.hooksPath` remains a per-clone setup step).
- Preventing bypass via `git commit --no-verify`, or any server-side / CI enforcement of the rule.
- Validating that the ticket number actually exists in a tracker.
- Rewriting or auto-fixing the developer's message.
- Exemptions for merge, revert, or fixup/squash commits (deferred; see Risks).

## Owner decisions
none recorded

## Priority: MVP
**Rationale:** It is the only story for this request and turns an already-written business rule into enforcement; the hook mechanism already exists, so value-to-effort is high.

## Assumptions
- The id may appear anywhere in the message (CLAUDE.md says "reference", not "start with") — validate with the Team lead.
- Matching is case-sensitive uppercase `NOTE-` followed by one or more digits, as a standalone token — validate with the Team lead.
- "Every commit" includes merge commits made locally (git runs the `commit-msg` hook for merges that create a commit), so a default `Merge branch 'x'` message would be rejected — validate with the Team lead.
- Developers have run `git config core.hooksPath githooks`; without it the hook never fires.

## Dependencies
- Depends on: none (`githooks/commit-msg` already exists as an accept-all stub).
- Blocks: none.

## Risks
- Default merge/revert messages will be rejected, adding friction to `git merge` / `git revert`; developers will need `-m`/`--edit` with a ticket id.
- Client-side only: `--no-verify` or an uninstalled hook bypasses it, so the Team lead's traceability goal is not guaranteed by this story alone.
- The hook is `#!/bin/sh`; it must behave the same under macOS (BSD userland) and Linux shells.

## Validation (must pass before merge)
1. **Static — `python3 -m unittest discover -s tests`:** passes, including new tests that run `githooks/commit-msg` against message files for each acceptance criterion above (accepted ids, missing id, `NOTE-` without digits, lowercase, embedded word, id only in a comment line) and assert exit status and the guidance text.
2. **Running system — a real rejected commit:** in a scratch clone with `git config core.hooksPath githooks`, `git commit --allow-empty -m "fix typo"` fails, prints the guidance (required form + corrected example), and `git log` shows no new commit; `git commit --allow-empty -m "NOTE-42: fix typo"` then succeeds.

## Depends on
none

## Touches
githooks/commit-msg
tests/test_commit_msg.py
CLAUDE.md
```

## Story 2 — static proof only (run3), verbatim

`<scratch>/.supervisor/requirements/2026-11-02-190000-format-duration-rejects-negative-seconds.md`:

```markdown
# format_duration rejects negative seconds (type: story)

**As a** Developer using `format_duration` to show durations to users,
**I want** a negative number of seconds to raise a `ValueError` that names the value I passed,
**so that** a bad duration fails loudly at its source instead of reaching users as a plausible-looking but wrong string (today `format_duration(-60)` returns `"-1h 59m"`).

Business rule (CLAUDE.md): durations are shown to users as hours and minutes (`2h 5m`). A negative duration has no valid rendering in that form.

## Acceptance Criteria

**Happy path (unchanged behaviour)**
- [ ] Given `7500` seconds, when `format_duration` is called, then it returns `"2h 5m"` (existing test still passes).
- [ ] Given `0` seconds, when `format_duration` is called, then it returns `"0h 0m"` (zero is valid, not rejected).

**Error scenarios**
- [ ] Given `-60` seconds, when `format_duration` is called, then it raises `ValueError` and returns no string.
- [ ] Given a rejected value, then the `ValueError` message contains the value exactly as passed (e.g. `-60`) and says that seconds must not be negative.
- [ ] Given `-1` second, then it raises `ValueError` naming `-1`.

**Edge cases**
- [ ] Given a negative fraction such as `-0.5` (which today truncates to `0` and returns `"0h 0m"`), then it raises `ValueError` naming `-0.5` — the check applies to the value passed, before any truncation (see Assumptions).
- [ ] Given a large negative value (e.g. `-86400`), then it raises `ValueError` naming that value.

**Regression**
- [ ] `python3 -m unittest discover -s tests` passes, and the output for every non-negative input is unchanged.

## Non-goals
- Rejecting non-numeric input (`None`, strings) — behaviour for those stays as it is today.
- Rendering negative durations in any form (e.g. `-1h 1m`).
- Changing the output format, rounding, or adding days/seconds to the output.
- Changing `notes/cli.py` (it does not call `format_duration` today).

## Owner decisions
none recorded

## Priority: MVP
**Rationale:** The only story for this request. It is a small correctness fix to a pure helper, with a known wrong output today, and no callers that depend on the wrong output.

## Assumptions
- "Negative" means `seconds < 0` on the value as passed, so `-0.5` is rejected even though it truncates to `0`. Validate with the Team lead if sub-second negatives should instead be treated as zero.
- Exact message wording is not specified; only that it names the value and states the non-negative requirement.
- No caller relies on the current `-1h 59m` output (verified: the only references to `format_duration` are `notes/format.py` and `tests/test_format.py`).

## Dependencies
- Depends on: none.
- Blocks: none.

## Risks
- A future caller that passes a computed difference (end − start) where clocks skew could now get an exception instead of a wrong string. That's the intended behaviour, but such callers would need to handle it.

## Validation (must pass before merge)
1. **Static — `python3 -m unittest discover -s tests`:** passes, including new tests in `tests/test_format.py` asserting `ValueError` with the value in the message for `-60`, `-1`, `-0.5`, and `-86400`, plus `format_duration(0) == "0h 0m"` and the existing `7500 → "2h 5m"` case.

## Depends on
none

## Touches
notes/format.py
tests/test_format.py
```

## Lint and validation gate on both stories

Run from `<scratch>` with `H=<branch>/loomwright/scripts/automate-helpers.sh`. The `validation-gate`
calls pass no PR (`""`), so a running-system step reads `unrun` (nothing pasted yet), and a story with
no running-system step reads `none` without looking for one.

```text
$ bash "$H" plan-waves .supervisor/requirements/2026-11-02-184329-reject-commits-without-a-ticket-id.md --lint
.supervisor/requirements/2026-11-02-184329-reject-commits-without-a-ticket-id.md: Touches ok; Depends on ok
0 of 1 items will run alone: none
0 of 1 items depend on every earlier item: none
exit=0
$ bash "$H" plan-waves .supervisor/requirements/2026-11-02-190000-format-duration-rejects-negative-seconds.md --lint
.supervisor/requirements/2026-11-02-190000-format-duration-rejects-negative-seconds.md: Touches ok; Depends on ok
0 of 1 items will run alone: none
0 of 1 items depend on every earlier item: none
exit=0
$ bash "$H" validation-gate .supervisor/automate/none.md .supervisor/requirements/2026-11-02-184329-reject-commits-without-a-ticket-id.md ""
validation-gate: unrun — V2 Running system — a real rejected commit: PR body unreadable: no PR recorded
exit=0
$ bash "$H" validation-gate .supervisor/automate/none.md .supervisor/requirements/2026-11-02-190000-format-duration-rejects-negative-seconds.md ""
validation-gate: none — no running-system step in .supervisor/requirements/2026-11-02-190000-format-duration-rejects-negative-seconds.md
exit=0
```

## Verdict

```text
V4 story 1 (running system): plan-waves --lint ok; ## Validation (must pass before merge) at H2; Running system entry present (validation-gate: unrun — V2 Running system …)
V4 story 2 (static only):    plan-waves --lint ok; ## Validation (must pass before merge) at H2; no Running system entry (validation-gate: none)
Both stories: Non-goals listed; Owner decisions reads "none recorded" (no owner decision was possible under --non-interactive)
```
