# `gate-eval` condition 7 judges whatever is checked out at `--root`, not the PR head it is about to merge

## Status: pending

> **Promoted from `proposed/` 2026-10-01** (owner triage session). Run first: the only open finding where the sole `gh pr merge --squash` executor can merge when it should park.
> **Origin.** Dismissed finding 3 from PR #296 (item 07, rules that gate), recovered by the item-13 triage sweep
> (run automate-2026-09-30-054439, classified 2026-10-01 against main@0dc0a5b, owner-approved as *draft*).
> **Priority:** the only still-open finding of the sweep where the trusted auto-merge gate (the plugin's sole
> `gh pr merge --squash` executor) can MERGE when it should park.

## Finding (verbatim summary)
> `gate-eval` condition 7 judges the working tree at `--root` without pinning `HEAD == live_head` or a clean tree.

## Evidence on main
- `loomwright/scripts/automate-helpers.sh` `gate_eval`, condition 7:
  `rules_json="$(bash "$rules_bin" --root "$root" </dev/null 2>/dev/null)"` — nothing compares `$root`'s HEAD to
  `live_head` or checks porcelain; the only `root` lines are `local root="."` and the `--root)` arg parse.
- `loomwright/scripts/rules-gate-verdict.sh` has no HEAD / porcelain check either.
- Condition 6 DOES pin the head (`classify-risk.sh main "$live_head" --root "$root"`); condition 7 does not, so a
  stale or dirty checkout can answer `ok` for a head whose bound files would fail.
- Not reproduced in scratch (classification from reading the code path).

## Scope (recommendation)
- In `gate_eval` condition 7: PARK (new reason, e.g. `rules_gate_head_mismatch`) unless
  `git -C "$root" rev-parse HEAD == live_head` AND the tree is clean — fail CLOSED, no override (matches cond 6/7 policy).
- `loomwright/scripts/test-automate-helpers.sh`: a stale-HEAD leg and a dirty-tree leg that must PARK, with a control.
- `loomwright/skills/automate-loop/SKILL.md` §10 condition 7 + the PARK-reason list.
- Behavioural, security-relevant (merge gate). High-risk per `classify-risk.sh`.
