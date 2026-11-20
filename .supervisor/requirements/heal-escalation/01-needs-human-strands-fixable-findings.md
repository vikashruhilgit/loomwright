# One NEEDS_HUMAN finding strands every fixable finding beside it

## Status: done
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/879 (merge 83a4549, v17.36.0)

> Owner decision 2026-11-10: design **A + B** (below). Found on PR vikashruhilgit/loomwright#876
> (`/automate` run `automate-2026-11-09-145614`, item `dismissed-followups/06c`).

## Depends on
none

## Touches
loomwright/agents/code-reviewer.md
loomwright/docs/result-schemas/code-review-result.md
loomwright/scripts/validate-code-review-result.py
loomwright/scripts/test-validate-code-review-result.sh
loomwright/skills/self-heal-advisory/SKILL.md
loomwright/agents/supervisor.md
loomwright/docs/result-schemas/supervisor-result.md
loomwright/scripts/validate-supervisor-result.py
loomwright/scripts/automate-dismissed.sh
loomwright/scripts/test-automate-dismissed.sh
loomwright/skills/automate-loop/per-item-loop.md
loomwright/docs/prompt-token-budgets.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
changelog.d/heal-escalation-01-needs-human-strands-fixable-findings.md

## Problem

On PR #876, Phase 4.5's code reviewer (round 1, `consistency_audit`) returned `NEEDS_HUMAN` with three findings:

1. **HIGH**: a real judgment call. The gate-configuration lens fires on any `scripts/guard-*.sh` hunk, and the brief required a comment-only edit to one.
2. **MEDIUM**: an ordinary defect. The `HOST_EFFECT` string in `build-capabilities.sh` dropped a clause.
3. **MEDIUM**: an ordinary defect. Stale "bucket each round" wording was left in `skills/pr-postmortem/SKILL.md`.

`.fix_floor` is `MEDIUM`, so findings 2 and 3 were at the floor and should have been fixed. None of the three was, and the owner was told the item was READY with "nothing to decide". Three gaps line up:

- **Gap 1 (Phase 4.5).** `skills/self-heal-advisory/SKILL.md`, the `if iter_decision == NEEDS_HUMAN:` branch of the heal loop, sets `ESCALATED`, posts the findings to the PR and `break`s before any fix round. One human-judgment finding cancels the fix round for every other at-floor finding in the same review. `CODE_REVIEW_RESULT` has no per-issue marker, so the loop *cannot* tell the human item from the fixable ones. (`SUPERVISOR_RESULT`: `heal_iterations: 0`, `heal_first_decision: NEEDS_HUMAN`, `heal_remaining_issues: 3`.)
- **Gap 2 (drain).** Phase 4.5's escalation comment is posted under the operator's `gh` login, so the `--until-mergeable` drain classifies it as human-authored: surfaced, never fixed, never a READY-blocker (`skills/review-heal/SKILL.md` "Human signals are surfaced but NEVER blocking"). The drain returned `READY` with `findings_validated: 0`. **This is correct drain behaviour and is NOT changed here** (see Non-goals).
- **Gap 3 (`/automate` park).** `scripts/automate-dismissed.sh` reads Phase 4.5's `heal_dismissed` (findings *below* the floor) and the drain's `dismissed`. At-floor findings left unfixed by an escalation are only a count (`heal_remaining_issues`), never itemised, so the park printed `parked; nothing to decide` with `pending_decisions: 0`.

## Goal

A single human-judgment finding no longer stops the fixable findings beside it from being fixed (A). Any at-floor finding Phase 4.5 still leaves unfixed, on *any* escalation exit, reaches the owner as an itemised decision at the `/automate` park, never as a bare count (B).

## Scope

### A. Fix the rest, escalate only the human item

1. **`CODE_REVIEW_RESULT` per-issue `needs_human`** (additive, optional, `schema_version` stays 3). It is a boolean on an issue: `true` means that issue is the judgment call the owner must make. Validation rules:
   - `decision: NEEDS_HUMAN` ⇒ at least one issue has `needs_human: true`.
   - `needs_human: true` on a non-`NEEDS_HUMAN` decision is rejected.
   - The environment-blocked path (`file: environment`) sets it on its BLOCKING issue.
   - **Legacy:** a `NEEDS_HUMAN` block with no `needs_human` on any issue stays valid and is read as "every issue needs a human", which is today's behaviour. The validator must not start rejecting old blocks.
2. **Reviewer prompt** (`agents/code-reviewer.md`, decision matrix + output section): when it returns `NEEDS_HUMAN`, mark exactly the issue(s) that need a human. Every other issue keeps its ordinary severity/category and is unmarked.
3. **Phase 4.5 loop** (`skills/self-heal-advisory/SKILL.md`). On `iter_decision == NEEDS_HUMAN`, split `review.issues`:
   - `human_issues`: the issues with `needs_human: true`, or *all* issues when none is marked (legacy reading).
   - `fixable_issues`: the at-floor issues not in `human_issues`, plus `rule_findings` and `ci_findings`.
   - If `fixable_issues` is empty, behave exactly as today (escalate, post, break).
   - Otherwise run **one** fix round for `fixable_issues` through the same fix Task and push path as a FAIL round, counted against `max_heal_iterations`, then re-review. Never fix a `human_issues` item.
   - On the re-review: if `NEEDS_HUMAN` again, escalate with whatever is still at floor, with no second "fix the rest" round in the same run. If `PASS`/`FAIL`, continue the ordinary loop. A human item that disappears on re-review is not proof it was resolved: escalate anyway, because the owner never ruled on it.
   - The escalation comment lists the `human_issues` first under "Needs a human decision", then any still-unfixed at-floor items.
   - `heal_first_decision` and `heal_new_findings` keep their current meaning.
4. **Mirror** in `agents/supervisor.md` (the "Pause on NEEDS_HUMAN" quality-gate line and the `ESCALATED` description).

### B. Itemise what escalation leaves unfixed

5. **`heal_dismissed` gains reason `escalated_unfixed`** (closed-enum extension, additive, `SUPERVISOR_RESULT` `schema_version` stays 1). On every Phase 4.5 exit that leaves at-floor issues unfixed, itemise each one with its `severity`, `source: code_reviewer`, and `reason: escalated_unfixed`, including the `human_issues`. The exits are: `NEEDS_HUMAN`, max iterations, `rules_gate_unresolved`, `rules_fail_then_unstamped`, `WRITE_SEAT_TAMPERED`, and the resume-thrash exit. `heal_remaining_issues` stays a count and must equal the number of `escalated_unfixed` items from `code_reviewer`, plus rule/CI findings as today. Update `validate-supervisor-result.py` to accept the new enum value. *Implementer's choice, to settle in the brief:* a separate `heal_unfixed` list instead of a new reason. Pick whichever keeps `pr-postmortem-gather.sh`'s marker-comment parsing and the `/automate` decision step unchanged in shape.
6. **`/automate` park** (`scripts/automate-dismissed.sh` + `skills/automate-loop/per-item-loop.md` "Dismissed-findings decision step"):
   - `escalated_unfixed` items become drafts like any dismissed finding, so `pending_decisions` counts them and the park asks fix-now / follow-up / drop.
   - An item that was a `human_issues` entry is labelled as the judgment call (e.g. a "needs your ruling" prefix) so the owner does not read it as an ordinary defect.
   - The park message never says `nothing to decide` while any `escalated_unfixed` item is undecided.

## Non-goals

- **Changing the drain's trust model.** The drain keeps fixing bot-authored findings only. It must not ingest Phase 4.5's PR comment, nor any `<!-- loomwright:` marker body, as findings. `classify-bot-review.sh`'s self-skip and the actor allowlist (red-team-hardening item 01, decision R2) are untouched. Phase 4.5's leftovers travel through the local `SUPERVISOR_RESULT` sidecar instead (B).
- **The gate-configuration lens itself.** It fires on comment-only `scripts/guard-*.sh` hunks; whether a comment-only hunk should be exempt is a separate question. File it as a follow-up if wanted.
- **Auto-resolving the human item.** No path may fix, waive or drop a `needs_human` issue without the owner.
- Any change to merge behaviour. `review-heal` and Phase 4.5 still never merge.

## Acceptance criteria

1. **Failing test first (#876 shape).** A fixture `CODE_REVIEW_RESULT` with `decision: NEEDS_HUMAN` and issues `[HIGH needs_human:true, MEDIUM new, MEDIUM new]` at `fix_floor: MEDIUM`, driven through the Phase 4.5 loop's decision logic, must show:
   - on the base: zero fix rounds, both MEDIUMs unfixed, no `escalated_unfixed` items;
   - on the fix: one fix round whose `fixable_issues` holds exactly the two MEDIUMs, with the HIGH absent from it;
   - after the re-review returns `NEEDS_HUMAN` with only the HIGH: `heal_decision: ESCALATED`, `heal_remaining_issues: 1`, and `heal_dismissed` containing the HIGH with `reason: escalated_unfixed`.
   Where the loop is prose, pin the split rule with a test of whatever script or validator now carries it. If no script carries it, the brief must say how the behaviour is verified (a real Phase 4.5 run on a scratch PR counts).
2. **Legacy NEEDS_HUMAN unchanged.** The same fixture with no `needs_human` on any issue gives today's result: no fix round, escalate. All three issues are itemised `escalated_unfixed`.
3. **Validator.** `validate-code-review-result.py` accepts a `NEEDS_HUMAN` block with ≥1 marked issue and a legacy block with none. It rejects `needs_human: true` under `PASS`/`FAIL`, and rejects a non-boolean value. Each case has a test in `test-validate-code-review-result.sh`.
4. **Every escalation exit itemises.** For each exit listed in Scope 5, a fixture or test shows each unfixed at-floor issue in `heal_dismissed` with `reason: escalated_unfixed` and the right `severity`.
5. **Park asks.** `test-automate-dismissed.sh` gains a case built from #876's `SUPERVISOR_RESULT` shape: 3 `escalated_unfixed` items yield 3 drafts and `pending_decisions: 3`, and the HIGH is labelled as the judgment call. A sidecar with no `escalated_unfixed` gives byte-identical output to today.
6. **Drain untouched.** `git diff` shows no change to `classify-bot-review.sh`, `review-heal-next-step.sh` or `skills/review-heal/`.
7. Doc-currency, token-budget, citation-drift and prompt-history gates pass. `bash scripts/check-version-bump.sh` passes. One `changelog.d/` fragment.

## Verified premises (re-check before starting; each read on 2026-11-10 at `bbb71cc`)

- `skills/self-heal-advisory/SKILL.md`: the `if iter_decision == NEEDS_HUMAN:` branch sets `ESCALATED`, posts a PR comment and `break`s; the fix Task is only reached on `FAIL`.
- `docs/result-schemas/code-review-result.md`: the issue object has `severity`/`category`/`drift_kind`/`file`/`line`/`description`/`suggestion` and no per-issue human marker. The only rule for `NEEDS_HUMAN` is "`issues` must be non-empty".
- `agents/code-reviewer.md`: `NEEDS_HUMAN` is reserved for "genuine design ambiguity … NOT for ordinary MEDIUM/LOW findings". The gate-configuration lens raises HIGH "unconditionally" on any `scripts/guard-*.sh` hunk.
- `scripts/automate-dismissed.sh`: its source table reads only `SUPERVISOR_RESULT.heal_dismissed` and `REVIEW_HEAL_RESULT.dismissed`; `heal_remaining_issues` is never read.
- `docs/result-schemas/supervisor-result.md`: `heal_dismissed.reason` is the closed enum `pre_existing | nit | drift | below_severity_floor`; `heal_remaining_issues` is a required integer.
- PR #876 evidence: the Phase 4.5 comment "Supervisor Phase 4.5 — escalated (NEEDS_HUMAN)" was posted by `vikashruhilgit`; the drain's `<!-- loomwright:clean round=1 -->` comment counted only `claude[bot]`; `REVIEW_HEAL_RESULT` reported `findings_validated: 0`, `decision: READY`.
