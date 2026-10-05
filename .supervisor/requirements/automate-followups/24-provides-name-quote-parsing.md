# 24 — A `provides` entry whose name contains a quote can be written and checked

## Status: pending

## Problem
In S1 v2 (2026-10-04) lane v2-b's worker finished item 18 with every test green, and the fail-closed output gate
still reported 1 of 6 promised outputs missing. The brief's contract named the symbol `PINS="1 2 … 10"` as
`name: "PINS=\"1 2 3 4 5 6 7 8 9 10\""`. `verify-provides.sh`'s `field()` takes a quoted value up to the FIRST
quote after the opening one and has no escape handling, so it searched for `PINS=\` and could never match, whatever
the file contained. The real line existed (checked with `grep -F`). Plan Review had flagged this exact entry as a
LOW note, but LOW notes reach the worker only as advisories, so nothing acted on it, and the owner had to answer an
output-gap question that only a brief edit could resolve.

## Goal
Either a quoted name with `\"` is read correctly, or such an entry is refused when the brief is reviewed, never
discovered as a false "missing" after the work is done.

## Scope
1. `verify-provides.sh` `field()`: inside a double-quoted value, `\"` is a literal quote and `\\` a literal
   backslash; inside a single-quoted value nothing is escaped (YAML-like). An unterminated quote stays "take the
   rest, trimmed" (today's behaviour).
2. The symbol check keeps using the unescaped name as a fixed string (`grep -F`), so regex metacharacters in a name
   (`=`, `"`, spaces) cannot mis-match.
3. Plan Review (`agents/plan-reviewer.md`) raises a provides name it cannot parse to a BLOCKING finding, not LOW,
   with the parser's reading shown ("this entry would be checked as `PINS=\`").
4. Tests (`test-verify-provides.sh`): `\"` inside a double-quoted name matches the real line; `\\` round-trips; a
   single-quoted name with a `"` inside matches; the v2-b entry verbatim now reports present; an unterminated quote
   behaves as before.

## Acceptance criteria
- Re-running `verify-provides.sh` on v2-b's original brief entry against #372's file reports 6 of 6.

## Validation (must pass before merge)
1. Baseline full loop, `<passed>/<total>` and `SKIP` counts, base and branch.
2. Unchanged path: every existing `test-verify-provides.sh` case passes unedited.
3. Running system: paste the v2-b entry checked against `main`'s `loomwright/scripts/test-rules-gate-seams.sh`.
4. A failure this must catch: drop the escape handling ⇒ the new `\"` test fails.
5. Rollback: `git revert`.

## Evidence
S1 run record, relay 4 (`.supervisor/requirements/parallel-automate/operator-run/S1-two-lane-spike.md`); archived lane
log `ai-agent-manager-lanes-v2/archive/v2-b/s1h-lane.log`.

## Depends on
none

## Touches
loomwright/scripts/verify-provides.sh
loomwright/scripts/test-verify-provides.sh
loomwright/agents/plan-reviewer.md
changelog.d/automate-followups-24-provides-name-quote-parsing.md

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-05T01:05:14Z
- **Brief:** .supervisor/jobs/done/2026-10-05-provides-name-quote-parsing.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/381
