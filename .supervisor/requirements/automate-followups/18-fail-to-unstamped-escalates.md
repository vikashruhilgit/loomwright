# A countable rules `fail` that turns `unstamped` mid-loop is silently cleared at Phase 4.5 / the drain

## Status: pending

> **Promoted from `proposed/` 2026-10-01** (owner triage session). **Owner decision 2026-10-01: Option A** — remember a countable `fail` seen earlier in the same loop; a later `unstamped` on that rule escalates instead of passing. Option B (document only) is rejected. This narrows D3 for the fail→unstamped transition only; a rule that was never seen failing stays advisory when `unstamped`.
> **Origin.** Dismissed finding 6 from PR #296 (item 07, rules that gate), recovered by the item-13 triage sweep
> (run automate-2026-09-30-054439, classified 2026-10-01 against main@0dc0a5b, owner-approved as *draft*).

## Finding (verbatim summary)
> A `fail` that turns `unstamped` mid-loop (fixer edits a bound file) is silently cleared at Phase 4.5 / drain, while
> the merge gate still parks `rules_unstamped`.

## Evidence on main
- `loomwright/skills/self-heal-advisory/SKILL.md` Part 2: `RULES_PASSABLE = ("ok", "none", "unstamped", "cmd_disabled")`
  and "ok / none / unstamped / cmd_disabled ⇒ rule_findings == [] and everything below is BYTE-IDENTICAL."
- `loomwright/skills/review-heal/SKILL.md`: "unstamped/cmd_disabled are advisory at the drain".
- So a stamped countable `fail` that a fix turns into `unstamped` reaches PASS / READY with only a
  `rules_check: unstamped` line; nothing records that an earlier round FAILED. Under `/automate` the merge gate still
  parks `rules_unstamped`; a human merging after `/supervisor` or `/review-pr` gets no warning.
- Arguably by design under owner decision D3 (unstamped stays advisory) — needs an owner call before any change.

## Scope (recommendation, owner decision first)
- Option A: remember a countable fail seen earlier in the same loop; a later `unstamped` on that rule escalates
  (or emits a hard-signal line) instead of passing silently.
- Option B: keep behaviour, document the gap as an honest limit in both skills.
- Files: `loomwright/skills/self-heal-advisory/SKILL.md` (Part 2 loop), `loomwright/skills/review-heal/SKILL.md`
  (drain), plus their tests if A.

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-04T08:15:03Z
- **Brief:** .supervisor/jobs/done/2026-10-04-fail-to-unstamped-escalates.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/372
