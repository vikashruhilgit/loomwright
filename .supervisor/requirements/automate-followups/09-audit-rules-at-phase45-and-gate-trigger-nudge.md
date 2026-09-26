# 09 — Re-validate the rules store every Phase 4.5 run (advisory), and nudge when the parked rule-gate becomes relevant

## Status: pending

> **Origin (2026-09-26).** Split out of item 07 (`proposed/automate-followups-07-rule-enforcement-at-review-and-merge.md`,
> scope (c)) on owner direction. 07's GATING half is parked until the store actually holds gateable rules. This
> half executes nothing and gates nothing, so it ships now. The owner also asked: when 07 is parked, what tells
> us it has become relevant? `/propose` never re-reads hand-authored docs in `proposed/` and never reads the rules
> store, so today the answer is "nothing". Part (b) below is that watcher.

## Depends on
None. `audit-rules.sh` already exists on `main`. The Phase 4.5 rules-check replay step it sits beside
(`skills/self-heal-advisory/SKILL.md` §"Rules-check replay", twin-loop/08, PR #267) is merged.

## Problem
- **Rules rot silently.** `validate-entry.sh`'s correctness checks run ONCE, at `/rules add` time.
  `audit-rules.sh` re-runs them plus store-wide checks (`no_mechanism`, `dangling_supersedes`, `never_fires`,
  `later_contradiction`, `supersession_cycle`, `skipped_object`), but only when a human types `/rules audit`. No
  runtime seam calls it; `self-heal-advisory/SKILL.md` has 0 references to it.
- **A parked design has no trigger watcher.** Item 07 is correctly deferred because, on 2026-09-26, the store had
  3 rules, 0 `must`, and 0 with a `check`, so a gate would gate on nothing. Nothing will notice the day that
  changes. A parked item whose revisit condition nobody watches is a claim nothing backs.

## Scope (recommendation, not pre-decided)
**(a) `audit-rules.sh` at Phase 4.5 — advisory, never gating.**
- Add one step beside the existing "Rules-check replay" in `self-heal-advisory/SKILL.md` Part 1. It emits ONE
  advisory line, e.g. `rules_audit: clean | findings <n> (<kinds>) | unexamined`.
- **Exit `2` (could not examine) must surface as `unexamined`, never as `clean`.**
- It executes nothing (it lints `check` as data), so it needs no stamp and no `--no-cmd` interplay. It must still
  leave the store byte-identical (the script's own fingerprint assertion).
- It never changes `heal_decision` and never enters the review-and-fix loop, matching the existing replay step's
  wording.

**(b) The revisit nudge for the parked gate (item 07).**
- When the store contains ≥1 `enforcement: must` rule with a non-null `check`, AND
  `.supervisor/requirements/proposed/automate-followups-07-rule-enforcement-at-review-and-merge.md` still exists,
  print ONE extra advisory line naming that file, e.g. `rules_gate_trigger: <n> must rule(s) now carry a check —
  proposed/automate-followups-07-… is now actionable`.
- Emit it from the same Phase 4.5 step, and also from `/rules audit` (`commands/rules.md` §`audit`), so it
  reaches a human with or without Supervisor.
- Read-only. It never moves, stamps or edits the proposed file; promotion stays a human act
  (`proposed/README.md`).

## Non-goals
- Any gating on audit findings or on the trigger (that is item 07, parked).
- Any write mode in `audit-rules.sh`, which stays dry-run ONLY by design.
- Generalising (b) into a watcher for every hand-authored doc in `proposed/`. That is a possible follow-up
  once this one instance proves useful. Record the idea; don't build it here.

## Acceptance criteria
- [ ] Phase 4.5 prose (`self-heal-advisory/SKILL.md` Part 1) runs `audit-rules.sh` and emits exactly one
  `rules_audit:` line, state-traced for all three states (`clean`, `findings`, `unexamined`). It explicitly says
  `heal_decision` is unchanged in every state.
- [ ] Fixture: a store with a `must` rule whose `check` is null ⇒ `findings` naming `no_mechanism`; store
  byte-identical before and after.
- [ ] Fixture: an unreadable store (audit exit 2) ⇒ `unexamined`, never `clean`. Mutation control: mapping exit 2
  to `clean` makes this fixture fail.
- [ ] Fixture: a store with ≥1 `must` rule with a `check` AND the proposed 07 file present ⇒ the
  `rules_gate_trigger:` line appears. With 0 such rules, or with the proposed file absent, it does not appear.
- [ ] `/rules audit` (`commands/rules.md`) prints the same trigger line under the same conditions.
- [ ] The seam guard stays green: `test-rules-seams.sh` must still pass. If it asserts on which rules scripts an
  unattended seam may reference, extend its allowlist deliberately and state why (`audit-rules.sh` executes
  nothing, which is unlike `rules-check.sh`).
- [ ] Token budget: re-measure any agent prompt touched; `check-token-budget.sh` green. Full test loop green.

## Verified premises (read at `main @ 41bd0f2`, 2026-09-26)
- `loomwright/scripts/audit-rules.sh` header: "READ-ONLY, PROPOSE-ONLY… THIS SCRIPT HAS NO WRITE MODE AT ALL";
  `check` is read as data, never executed.
- `skills/self-heal-advisory/SKILL.md` §"Rules-check replay (executable-rule-candidates/01 — advisory-only, NEVER
  gates)" exists; `grep -c audit-rules` on that file = 0.
- `.agent/rules/`: 3 rule objects, 0 `enforcement: must`, 0 with a string `check` (jq over `.agent/rules/*.json`,
  2026-09-26).
- `proposed/README.md`: "promotion is a human moving a file out of it"; `/propose` reads `floor.json`, a
  `/verify` run, or `product.json`, never the rules store and never hand-authored proposed docs.
