# Evidence — Product Owner publishes the story it writes to the metadata branch (Validation 3)

Real output from one live headless `/loomwright:product-owner` run, captured 2026-11-28 on branch
`feature/2026-11-28-po-orchestrator-publish-to-meta-branch`. The run started after commit `c1f32c9`
(the commit that adds the Persistence Mode Publish step), with a clean working tree for every file the
run loads. Nothing below is hand-written except the prose and the headings. The only edit to the
output is path redaction: the branch checkout reads `<branch>`, the scratch directory `<scratch>`, and
home directories `/Users/<name>/`.

## Which plugin copy ran

The run's `init` event lists the `loomwright` plugin loaded from the branch (`--plugin-dir`), which
replaces the installed copy of the same name for that session:

```text
{"name": "loomwright", "path": "<branch>/loomwright", "source": "loomwright@inline", "version": "18.1.2"}
```

## Scratch project (branch mode on, LOCAL bare origin)

A throwaway git repository holding a tiny Python CLI (`notes/format.py` with `format_duration`,
`notes/cli.py`, `tests/test_format.py`, `githooks/commit-msg`) and a `CLAUDE.md` with one business rule
(durations are shown as hours and minutes). No `.beads/` and no `.agent/`, so Product Owner runs in
file-fallback mode with no house rules. Branch mode was switched on with the branch's own scripts, and
`origin` is a bare repository on the same disk — nothing left the machine:

```bash
bash <branch>/loomwright/scripts/setup-memory.sh --root "$PWD" apply --branch-mode loomwright-meta
git add -A && git commit -qm init
git clone -q --bare <scratch>/project <scratch>/origin.git
git remote add origin <scratch>/origin.git && git fetch -q origin && git branch -q -u origin/main
bash <branch>/loomwright/scripts/meta-sync.sh init --root "$PWD"
```

```text
meta_sync: initialised loomwright-meta at 4a3628513519d0e0773cff04122e6519c29b741a
mode: on loomwright-meta
```

## Exact command

```bash
cd <scratch>/project
claude -p '/loomwright:product-owner feature: "format_duration rejects a negative number of seconds with a ValueError that names the value, instead of returning a wrong string" --non-interactive' \
  --plugin-dir <branch>/loomwright \
  --output-format stream-json --verbose \
  --permission-mode acceptEdits \
  --allowedTools "Bash Read Write Edit Glob Grep" \
  --no-session-persistence --max-budget-usd 6 < /dev/null > run1.jsonl
```

Result event: `is_error=false num_turns=6 total_cost_usd=0.61 duration_ms=43442`, no permission denials.
Product Owner raised no flag (the defect was reproduced, nothing conflicted with `CLAUDE.md`), so it
persisted one story: `.supervisor/requirements/2026-11-28-115428-format-duration-rejects-negative-seconds.md`.

## The helper call and its line

The Bash call Product Owner made for the Publish step (it ran the lint, the size check and the publish
in one call; `$H` is the branch's `automate-helpers.sh`, path redacted), verbatim from the transcript:

```bash
H=<branch>/loomwright/scripts/automate-helpers.sh; F=.supervisor/requirements/2026-11-28-115428-format-duration-rejects-negative-seconds.md; bash $H plan-waves $F --lint; echo "lint rc=$?"; bash $H right-size $F; echo "rs rc=$?"; lf="$(mktemp)"; printf '%s\n' $F > "$lf"; bash $H meta-publish --paths-from "$lf" --root "$(git rev-parse --show-toplevel)"
```

The helper's line, from that call's output and quoted again in Product Owner's final report:

```text
meta-publish: pushed loomwright-meta f9d1775fe0946b6ceb07459f9cd5df6a86aa292b (1 path(s))
```

## The branch right after the run

Run in `<scratch>/project` after the run ended (nothing else wrote to the scratch repository or its origin in between):

```text
$ git fetch -q origin; git log --oneline origin/loomwright-meta
f9d1775 chore(supervisor): publish planning file(s) on write
4a36285 meta-sync: initialise loomwright-meta
$ git ls-tree -r --name-only origin/loomwright-meta
.supervisor/requirements/2026-11-28-115428-format-duration-rejects-negative-seconds.md
$ git show origin/loomwright-meta:.supervisor/requirements/2026-11-28-115428-format-duration-rejects-negative-seconds.md > ../shown.md; cmp ../shown.md .supervisor/requirements/2026-11-28-115428-format-duration-rejects-negative-seconds.md && echo IDENTICAL
IDENTICAL
```

The pushed commit is the sha the helper printed, the branch holds exactly the one path Product Owner
wrote, and the branch copy is byte-identical to the local file.

`git show origin/loomwright-meta:.supervisor/requirements/2026-11-28-115428-format-duration-rejects-negative-seconds.md`, verbatim:

```markdown
# format_duration rejects negative seconds (type: story)

**As a** developer calling `notes.format.format_duration`,
**I want** a negative number of seconds to raise a `ValueError` that names the value it was given,
**so that** a bad input fails loudly at its source instead of being shown to users as a wrong duration such as `-1h 59m`.

## Acceptance Criteria

**Happy path (unchanged behaviour):**
- [ ] Given `7500` seconds, when `format_duration` is called, then it returns `"2h 5m"` (existing test keeps passing).
- [ ] Given `0` seconds, when `format_duration` is called, then it returns `"0h 0m"` (zero is valid, not negative).

**Error scenarios:**
- [ ] Given `-1` seconds, when `format_duration` is called, then it raises `ValueError` and returns no string.
- [ ] Given `-3600` seconds, when `format_duration` is called, then it raises `ValueError` whose message contains `-3600`.
- [ ] Given a negative non-integer such as `-0.5`, when `format_duration` is called, then it raises `ValueError` whose message contains `-0.5` (today it silently returns `"0h 0m"` because the value is truncated first; the check applies to the value as passed, before any truncation).

**Contract change:**
- [ ] The accepted input form of `format_duration` narrows from "any number" to "any number `>= 0`"; the refusal form is `ValueError` with the offending value in its message. This is pinned by a unit test in `tests/test_format.py`.

## Non-goals
- Validating non-numeric input (strings, `None`) — out of scope; behaviour unchanged.
- Changing the output format for valid input (`Nh Mm`, per CLAUDE.md business rule).
- Adding a CLI-level error message — `notes/cli.py` does not call `format_duration` today.

## Owner decisions
none recorded

## Priority: MVP
**Rationale:** The function's only job is to show a correct duration; a negative input today produces a plausible-looking but wrong string, which is worse than an error.

## Assumptions
- Defect evidence: reproduced — traced values on today's code: `format_duration(-1)` → `'-1h 59m'`, `format_duration(-61)` → `'-1h 58m'`, `format_duration(-3600)` → `'-1h 0m'` (floor division on negatives).
- "Negative" means any value `< 0`, including fractional values such as `-0.5`; `0` stays valid.
- "Names the value" means the value's text appears in the exception message; exact wording is left to the implementer.
- No caller in the repo depends on negative input (grep: `notes/cli.py` has no `format_duration` call), so the contract narrowing breaks nothing in-repo.

## Dependencies
- Depends on: none
- Blocks: none

## Risks
- An external caller relying on the old negative output would now get an exception — accepted, since that output was wrong.

## Validation (must pass before merge)
1. **Static — unit tests:** `python3 -m unittest discover -s tests` (the project's only CI check) passes, including new tests for `-1`, `-3600`, `-0.5` (raise `ValueError`, message contains the value) and `0` (returns `"0h 0m"`); the negative-input tests fail on today's code.

## Depends on
none

## Touches
notes/format.py
tests/test_format.py
```

## Honest limits

- One run, one story. A two-story run with a `_BACKLOG-*` plan doc (three paths) was not run headless;
  the three-path push, the exact-list rule (an unlisted local-ahead file and an unlisted locally
  deleted file are left alone) and every non-push verdict are pinned by the hermetic legs BP1 to BP11
  in `loomwright/scripts/test-automate-helpers.d/12-meta.sh`, not by this run.
- No `/orchestrator` run was made; its Publish step is the same helper call with one path.
- The run used `--allowedTools "Bash …"` (any Bash command) so the compound Publish call was not
  denied; an interactive session asks for that call as it asks for any Bash command.

Verdict: PASS for Validation 3
