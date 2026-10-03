# 07 — Rules that GATE: promote a failing stamped must-check from a report line to a blocker (owner decision)

## Status: pending

> **Promoted from `proposed/` to the queue (owner decision, 2026-09-28).** The owner overrode the original
> revisit trigger (≥1 `enforcement: must` rule with a non-null `check` in `.agent/rules/`) and answered
> **D1–D4** — see §"Owner decisions (2026-09-28)" at the end. Build the gate now so it is ready when the first
> checkable `must` rule lands. **Consequence, stated honestly:** on 2026-09-28 the store still holds 3 rules,
> 0 `must`, 0 with a check, so on this repo the gate ships DORMANT — every acceptance criterion below must be
> proven against fixture stores, never against the live one. Accepting D1 supersedes
> `twin-remediation/03-mechanize-rules-tier1.md`'s "No new gating paths" non-goal (already recorded in the
> 2026-09-26 owner direction). Items 05, 06 and 10 are additive and do NOT depend on this one;
> `proposed/automate-followups-08-setup-rules-ci-offer.md` (still parked) does.

## Depends on
`twin-loop/08` (**done**, PR #267) and `red-team-hardening/03` (gate-eval self-resolving, **done**, PR #250).
Both on `main`.

> **Origin (2026-09-26).** Same owner question as items 05–06, taken to its end: after 08, a `must` rule whose
> check a human confirmed on this machine is **executed** at Phase 4.5 and its failure is **printed**. Nothing
> more. `self-heal-advisory/SKILL.md` states the choice plainly: the replay "is SURFACED, not a new review pass:
> it never enters the review-and-fix loop and it NEVER changes `heal_decision`", and the tally line tolerates
> `n < m` — "a failing stamped check still replays and still never gates". Meanwhile `/automate`'s trusted
> auto-merge gate has six conditions and none of them asks about rules.

## Problem
A rule can be mechanized, human-confirmed, executed, observed to fail — and the PR still reaches `READY`, and
(with `--auto-merge`) still merges. "The rule was followed" and "the rule failed and we printed it" remain
indistinguishable in every terminal state.

## THE DECISION THIS ITEM EXISTS TO PUT TO THE OWNER
This is **not** a bug in 08. 08 deliberately chose advisory-only and said so, citing CLAUDE.md's Failure-Mode
Invariants. Promoting a failure to a blocker **changes a documented invariant** and must be an explicit owner
decision recorded in CLAUDE.md — not a quiet edit inside a worker's diff.

- **D1 — Phase 4.5.** Does a **failing stamped** `must` check become a BLOCKING finding that enters the
  review-and-fix loop and holds `READY`?
  *Recommendation: yes, and ONLY for a stamped failure.* A stamped failure is the one signal in the whole
  advisory tier that is deterministic, human-authorized, and reproducible — it is categorically unlike a rubric
  score or a reviewer opinion. `unstamped` must stay advisory: a signal you were not allowed to run cannot gate.
- **D2 — `/automate` gate-eval.** Add condition 7?
  *Recommendation: yes, self-resolved.* **It cannot be passed in `ctx.json`** — red/03 made the gate
  self-resolving and it refuses a ctx carrying a gate-owned key outright (`PARK: ctx_carries_gate_owned_key`)
  before evaluating anything. Cond 7 must run `rules-check.sh --if-stamped` itself, exactly as cond 6 re-runs
  `classify-risk.sh`.
- **D3 — what `unstamped` means at the merge gate.** Two defensible readings:
  - **(i) `none`-like, not a blocker** — precedent: cond 5's `rubric_satisfied: true|"na"|false`, where `na`
    (no rubric) is explicitly not a blocker.
  - **(ii) PARK** — strict fail-closed, matching the gate's house convention.
  *Recommendation: a middle form — PARK only when the store contains ≥1 `must` rule with a non-null `check`
  (there IS something to verify and this machine never confirmed it); otherwise pass as `none`.* Reading (ii)
  alone would brick auto-merge on every fresh machine and every clone; reading (i) alone lets an operator dodge
  every rule by never stamping.
- **D4 — CLAUDE.md.** On accepting D1, the Failure-Mode Invariants paragraph must be amended in the SAME change:
  a stamped rule check is a correctness gate, not an advisory emitter. Leaving the old wording standing would be
  exactly the "a claim no check backs" defect the store's own rules describe.

## Goal
A failing human-confirmed `must` check blocks the drain and parks the merge gate, with `unstamped` and
`cmd_disabled` still non-gating. (Re-validating the rules store itself every run was this item's scope (c); it
moved to item 09.)

## Scope
**(a) Phase 4.5** — per D1, a stamped failure becomes a BLOCKING finding entering the existing review-and-fix
loop; `--until-mergeable` cannot reach `READY` while one fails. `unstamped`/`cmd_disabled` keep today's line
verbatim. `--no-cmd` still wins over everything, including a valid stamp.

**(b) gate-eval condition 7** — per D2/D3, self-resolved, written in the existing affirmative
`!= "true"` ⇒ PARK form. **Never** a `= "false"` test. No override flag (cond-6 posture): `--trust-unprotected`
is cond 4 only.

**(c) MOVED to item 09** (`automate-followups/09-audit-rules-at-phase45-and-gate-trigger-nudge.md`, owner
direction 2026-09-26). Do not re-implement `audit-rules.sh` at Phase 4.5 here; if 09 has not merged when this
item is picked, build on whatever 09 left and do not duplicate it.

**(d) Close the D1 caveat (required, not optional).** A stamp binds a check's TEXT, never the files that check
runs, so a PR could edit `scripts/lint.sh` and make its own gate pass. The gate may only count a check that
either (i) executes no repo-tracked file (e.g. a grep-only check), or (ii) is bound to the content of every
repo file it invokes. Pick one in the plan and state why; Plan Review decides. A check outside the chosen set
must stay advisory, reported as such, never silently counted as a pass.

## Acceptance criteria
- [ ] Stamped + failing ⇒ drain does not reach `READY`; the finding names the rule id and its failing check.
- [ ] Stamped + all passing ⇒ terminal state and report line byte-identical to pre-item.
- [ ] `unstamped` ⇒ byte-identical to pre-item (still the advisory line, still non-gating); nothing executes
      (canary-file assertion).
- [ ] `--no-cmd` with a valid stamp ⇒ `cmd_disabled`, nothing executes, nothing gates.
- [ ] gate-eval: a `ctx.json` carrying the cond-7 key is REFUSED with `ctx_carries_gate_owned_key` (proves the
      condition is gate-owned and self-resolved, not caller-supplied).
- [ ] gate-eval cond 7 per D3: failing ⇒ PARK with a named reason; unstamped-with-must-checks ⇒ PARK;
      unstamped-with-none ⇒ not a blocker.
- [ ] (d): a fixture PR that edits the file a counted check invokes cannot turn that check from failing to
      passing without the gate noticing; a check outside the chosen set is reported advisory, never counted.
- [ ] Mutation controls: reverting (a) makes AC1 reach `READY`; reverting (b) makes the failing-check gate MERGE.
- [ ] CLAUDE.md's Failure-Mode Invariants amended in the same change (D4); grep the OLD wording repo-wide.
- [ ] `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` still resolves to exactly the
      five sanctioned surfaces — no second executor introduced.
- [ ] The full test loop is green — BOTH `loomwright/scripts/test-*.sh` AND root `scripts/test-*.sh` plus
      `scripts/check-vendor-coupling.sh`.

## Out of scope
- Gating on **advisory** rules, on `unstamped`, or on `audit-rules.sh` findings — all stay non-gating.
- Any new executor of a rule's `check`: `rules-check.sh` remains the sole one.
- Sharing or committing the stamp to make CI gate — that is item 08's problem and has a different answer.

## Verified premises (read at `main @ 4f681d0`, 2026-09-26)
- `skills/self-heal-advisory/SKILL.md`: the replay "is SURFACED, not a new review pass … it never enters the
  review-and-fix loop and it NEVER changes `heal_decision`"; `rules_check: passed {n}/{m}` where "n MAY be < m —
  a failing stamped check still replays and still never gates"; the script's non-zero exit "is read as 'some
  replayed check failed', folded into the `n/m` figure, and nothing else. No fix iteration is ever triggered."
- `scripts/automate-helpers.sh`: `gate-eval … 6-condition fail-closed gate (cond 6 = classify-risk.sh high_risk,
  NO override)`; refuses a ctx carrying a gate-owned key with `ctx_carries_gate_owned_key` "BEFORE evaluating
  anything else"; cond 5 carries `rubric_satisfied: true|"na"|false` with `na` = not a blocker; the fail-closed
  convention is the affirmative `!= "true"` ⇒ PARK form and "NEVER add a condition written as `= "false"`".
- CLAUDE.md §Failure-Mode Invariants: correctness gates fail CLOSED, runtime emitters fail SAFE, and inverting
  either "is a security regression, not a bug fix"; `--auto-merge` is opt-in, default-OFF, six conditions.
- `commands/rules.md` §`audit`: read-only, propose-only, has NO write mode and NO write flag, refuses unknown
  flags, asserts a byte-identical store via a path-list + per-file-hash fingerprint, re-runs `validate-entry.sh`'s
  shared checks, exit `0` clean / `1` findings / `2` could not examine, and "NEVER EXECUTES a `check`".

## Owner direction (2026-09-26)
- **Yes in principle to D1–D4, deferred** until the revisit trigger fires. Scope (c) (`audit-rules.sh` at
  Phase 4.5) was split out and ships now as `automate-followups/09`; it is no longer part of this item.
- **D1 caveat found by PR #267 review:** the stamp binds a check's TEXT, never files it invokes. A PR can
  edit the script a stamped check runs (e.g. `bash scripts/lint.sh`) and make its own gate pass. When built,
  gate only on checks that do not execute repo files (e.g. harvested grep-only candidates), or bind those files.
- Accepting D1 supersedes `twin-remediation/03-mechanize-rules-tier1.md`'s "No new gating paths" non-goal.

## Owner decisions (2026-09-28)
- **D1 — yes, stamped failures only.** A failing stamped `must` check is a BLOCKING Phase 4.5 finding.
  `unstamped` and `cmd_disabled` stay advisory.
- **D2 — yes.** gate-eval condition 7, self-resolved (the gate runs `rules-check.sh --if-stamped` itself),
  refused if a caller passes it in `ctx.json`.
- **D3 — the middle form.** At the merge gate, `unstamped` PARKS only when the store holds ≥1 `must` rule with a
  non-null `check`; otherwise it passes as `none`.
- **D4 — yes.** Amend CLAUDE.md §"Failure-Mode Invariants" in the same change: a stamped rule check is a
  correctness gate, not an advisory emitter. Grep the old wording repo-wide.
- **Revisit trigger overridden.** Build now; the gate is dormant on this repo until a checkable `must` rule exists.

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-09-28T23:24:23Z
- **Brief:** .supervisor/jobs/done/2026-09-28-rule-enforcement-at-review-and-merge.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/296
