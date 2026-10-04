# Rules seam: four dismissed Phase 4.5 findings from PR #319 (item 13)

## Status: pending

> **Promoted from `proposed/` 2026-10-01** (owner triage session). Bundles the four `/automate` gate drafts
> `automate-2026-09-30-054439--13-dismissed-findings-triage-sweep-ce364e--dismissed-{1b4e0236,3d8b82d7,c37bc07f,summary}.md`,
> all recorded with owner decision **follow-up** in that run's `.dismissed-decisions` ledger. Source PR:
> https://github.com/vikashruhilgit/loomwright/pull/319 (round 1, origin `phase_4_5`, source `code_reviewer`).
> The finding text below is the reviewer's, quoted as data. Re-verify each one against `main` before changing anything.

## Findings

1. **MEDIUM, reproduced (`c37bc07f`, dismissed `pre_existing`).** `rules_check_line` tests `$NO_CMD_FLAG` before
   `unreadable`, so a `--no-cmd` run on an unparseable store escalates `rules_gate_unresolved` while posting
   `rules_check: cmd_disabled`. The posted line and the verdict disagree.
2. **MEDIUM, reproduced (`3d8b82d7`, dismissed `below_severity_floor`).** `SEAM_C_VAR_ASSIGN_RE` misses the repo's own
   `$(cd …)/read-rules.sh` reader idiom, spaced paths, `declare`/`local -r` and alias chains. Its "Limit" comment
   understates the gap.
3. **LOW (`0988b86c`, summary entry, dismissed `below_severity_floor`).** `SEAM_C_SINK_PIPE_RE` misses `| /bin/bash`,
   `| env bash`, `| ksh`; `SEAM_C_SINK_PROCSUB_RE` stops at a nested paren.
4. **LOW (`1b4e0236`, dismissed `pre_existing`).** `skills/automate-loop/SKILL.md` §10 condition 7 `cmd_disabled ⇒ PARK`
   bullet omits that an advisory-only store or an empty selection still reads `none` under `RULES_CHECK_NO_CMD=1`.

## Scope (recommendation)
- 1: reorder so `unreadable` wins over `cmd_disabled` (fail-CLOSED reading), with a fixture leg for `--no-cmd` +
  unparseable store.
- 2–3: widen the seam regexes or, if a regex cannot express the idiom, state the gap honestly in the Limit comment.
  Add one fixture per missed shape.
- 4: one-sentence doc fix in §10 condition 7.

## Acceptance criteria
- [ ] Each finding re-verified on `main`, then fixed or recorded as not reproducible.
- [ ] Fixture legs for 1–3; the full `test-*.sh` loop green.

## Depends on
none

## Touches
loomwright/skills/self-heal-advisory/SKILL.md
loomwright/scripts/test-rules-gate-seams.sh
loomwright/scripts/test-rules-seams.sh
loomwright/skills/automate-loop/SKILL.md
changelog.d/automate-followups-21-rules-seam-dismissed-followups.md
