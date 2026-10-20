# automate-speed/24 — Plugin scripts print one line by default; detail behind --verbose

## Status: pending

## Problem
Main sessions take in 300–500K chars of Bash output each (plan doc §Why now). Measured over 7 days, the model's own
exploration (`cd`/`sed`/`cat`/`grep`/`git`) is most of it; the plugin's own scripts are ~10%: `classify-bot-review.sh`
2.1%, `automate-lanes.sh` 1.8% (+1.0% `lane-status`), `automate-helpers.sh` 1.5% (+0.8% `plan-waves`),
`read-project-memory.sh` 1.1%, `verify-provides.sh` 0.7%. Honest limit: the expected saving is small; items 06–09
remove most of the model's exploration of the loop by removing the need for it.

## Goal
<!-- bump: patch -->
The five top-output plugin scripts print a one-line summary by default (status + the fields the caller acts on) and
keep today's full output behind `--verbose`.

## Scope
- `classify-bot-review.sh`, `automate-lanes.sh lane-status`, `automate-helpers.sh plan-waves`,
  `read-project-memory.sh`, `verify-provides.sh` (after items 19 and 21 the code may live in their `<script>.d/` modules).
- Every caller that parses today's output (scripts, prompts, hooks, `loomwright-lanes`) is switched to `--verbose` or to
  the new summary in the same change. Find them with a repo-wide grep; a machine consumer is never broken.

## Invariants
- No machine consumer's parse breaks (`lane-status --json` is unchanged; the pane reads it).
- Fail-SAFE readers keep exiting 0 with a named reason.

## Non-goals
- Changing what the scripts compute.

## Owner decisions (from _BACKLOG.md)
- none recorded beyond the plan doc's.

## Acceptance criteria
- Given each script's default invocation, then stdout is one line (or one line per item for list commands).
- Given `--verbose`, then output is byte-identical to today's.
- Every consumer found by the grep is listed in the PR body with how it was switched.

## Validation (must pass before merge)
1. The five scripts' test suites, `scripts/test-lanes-addon.sh`, `test-build-handoff.sh`, `test-project-memory.sh`;
   report `<passed>/<total>`.
2. Running system: run each script once with and without `--verbose`; paste the default lines.

## Depends on
19
21

## Touches
loomwright/scripts/classify-bot-review.sh
loomwright/scripts/test-classify-bot-review.sh
loomwright/scripts/automate-lanes.sh
loomwright/scripts/automate-lanes.d/
loomwright/scripts/test-automate-lanes.sh
loomwright/scripts/automate-helpers.sh
loomwright/scripts/automate-helpers.d/
loomwright/scripts/test-automate-helpers.sh
loomwright/scripts/read-project-memory.sh
loomwright/scripts/test-project-memory.sh
loomwright/scripts/verify-provides.sh
loomwright/scripts/test-verify-provides.sh
changelog.d/as24-terse-script-output.md

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-20T14:28:53Z
- **Brief:** .supervisor/jobs/done/2026-10-20-as24-terse-script-output.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/635
