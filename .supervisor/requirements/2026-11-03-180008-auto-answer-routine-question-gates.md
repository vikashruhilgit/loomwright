# Auto-answer routine question gates in every run, and show the owner what was auto-answered

## Status: pending

**Story: Auto-answer routine question gates in every run** (type: story)

**As a** plugin owner running `/automate`, `/launch-pad` and `/supervisor`,
**I want** gates whose recommended answer I accept essentially every time to apply that answer without asking me, with a list of what was auto-answered at the run's end,
**so that** each run stops spending a relay round trip and a turn on a question whose answer never changes, while the decisions I really make still reach me.

## Problem

The plugin asks through the host's ask tool at catalog gates (`loomwright/scripts/lane-policy.sh catalog`, mirrored in
`loomwright/docs/LANE_GATES.md`). A pre-answer mechanism exists, but it reaches very few of the questions:

- It works only inside `--parallel` lanes (the lane relay's `_lanes_policy_apply` in `scripts/automate-lanes.d/relay.sh`).
  Sequential runs and inline `/launch-pad` and `/supervisor` always ask.
- It answers only `allowed` codes, from a stamped project policy or an owner-set wave policy. Without one, it answers nothing.
- `LP-SAVE-NOTE`, the highest-volume Launch Pad gate, is `human-only`, so no policy may answer it.

One deterministic precedent already exists: `automate-helpers.sh queue-confirm` skips `AUT-QUEUE` for a backlog that is
not longer than `--limit` and records `skipped AUT-QUEUE: <reason>` in `## Progress`
(`skills/automate-loop/intake.md` §"`--limit N`"). This story generalises that one pattern into a catalog tier.

## Evidence (mined 2026-11-03 from every `~/.claude/projects` transcript: 2,825 ask calls, 4,201 questions)

- When an option was marked `(Recommended)`, the owner picked it 92.7% of the time (1,850 / 1,996).
  An unmarked first option was picked 86% of the time, and a free-text answer was given 6.4% of the time.
- Catalog-coded gates since 2026-10-10 (1,238 questions). These took the default every time:

  | Gate | Asks | Took the default |
  |---|---|---|
  | LP-SAVE-NOTE | 273 | 100% (Save 241, Refine 32) |
  | LP-SAVE | 45 | 100% |
  | AUT-QUEUE | 30 | 100% |
  | AUT-RESUME | 12 | 100% |
  | SUP-OVERLAP | 21 | 100% |

  Refine was picked 32 times on LP-SAVE-NOTE, each time when Refine was the recommended option.
- On these gates the owner overrides the recommendation often, so they are real decisions: SUP-CHILDREN 65% default
  (investigate 12 of 34), SUP-ADJ-GAP 65%, LP-NO-GO 67%, LP-RULE-OVR 57%.

**Honest limit.** A 93% acceptance rate does not prove the recommendations were correct. It may mean the questions were
rubber-stamped. The end-of-run auto-answer list (AC 4) is the oversight surface that replaces the per-question ask.

## Owner decision (recorded)

- 2026-11-03, /product-owner session (PO-ASSUME answered "Proceed anyway"): the owner chose to let a deterministic
  `auto` tier answer routine gates outside lanes. That includes `LP-SAVE-NOTE`, which `docs/LANE_GATES.md` currently
  defines as `human-only` ("no policy ever answers it"). This is a deliberate policy change, not drift. The docs must
  state the new tier and its triggers, never quietly reword the old one.

## Scope

- **A. An `auto` tier in the catalog.** A gate code's policy may be `auto`, alongside `allowed` and `human-only`.
  - An `auto` gate in an interactive run applies its recommended label without asking.
  - It records one `## Progress` line, in the same shape as the existing `skipped AUT-QUEUE: <reason>`, that names the
    code, the label applied and the reason.
  - It works in sequential runs, in inline `/launch-pad` and `/supervisor`, and in lanes.
  - The catalog stays the one authoritative table, and `docs/LANE_GATES.md` is regenerated from it in the same change.
- **B. Initial `auto` set (owner-chosen from the evidence):**
  - `LP-SAVE` on a Plan Review PASS with zero issues → `Save and exit`.
  - `LP-SAVE-NOTE` on a Plan Review PASS → `Save and exit`. The PASS's issues and notes are carried to the worker
    exactly as a human `Save and exit` carries them today.
  - `AUT-QUEUE` → `Process`.
  - `AUT-RESUME` → `Continue`, but only when exactly one incomplete run exists. Two or more always ask.
- **C. Deterministic escalation triggers.** An `auto` gate still asks the owner when ANY of these holds.
  - The question carries a finding or Plan Review issue of severity MEDIUM or higher.
  - The work is security-shaped: `scripts/classify-risk.sh` says the diff or brief is high-risk.
  - The answer would delete, discard, merge or push anything.
  - The recommended label is missing, ambiguous, or not one of the catalog labels.

  An escalated ask records why it was not auto-answered. No LLM judges these: every trigger is a deterministic read.
- **D. Off switch.** A run-level option (flag and/or `.supervisor/config.json` key) turns the `auto` tier off. Every gate
  then asks exactly as before. The option is recorded in `## Run Config`, so `--resume` keeps it.
- **E. End-of-run list.** At the run's end and at every park, one block lists every auto-answered gate of the run (code,
  label, reason, item), so the owner reviews the auto-answers in one place.

## Out of scope (stated so it is not re-litigated)

- **`SUP-OVERLAP` stays human.** It went 21 of 21 `proceed-anyway`, but it is the stale-branch incident guard (Phase 1.5,
  CLAUDE.md §"Claimed work is already merged"). A later item may make it `auto` only when the overlapping PR merged before
  the brief was planned. That is not this item.
- **Never `auto`.** These gates are never auto-answered: Plan Review FAIL or NEEDS_HUMAN (`LP-FAIL`, `LP-NEEDHUMAN`),
  `LP-NO-GO`, `LP-RULE-OVR`, `PO-ASSUME`, `PO-RULE-MUST`, `SUP-CHILDREN`, `SUP-ADJ-GAP`, `SUP-ADJ-LANE`, `AUT-WAIVE`,
  `AUT-LEFTOVER`, every `AN-*` gate, every `BL-*` gate, `JAN-ACT`, and any gate that merges a PR. The `--auto-merge`
  executor's single-executor invariant is unchanged.
- **Dismissed-finding gates** (`AUT-DISMISS`, `AUT-PENDING`, `AUT-SUMMARY`) are handled by
  `2026-11-03-180009-stop-asking-per-dismissed-finding.md` and `2026-11-03-102217-stop-asking-about-summary-dismissed-finding-drafts.md`.
- **No LLM judge.** A judge for the free-text `LP-CLARIFY` (88 asks, 98% took the recommended option) is not part of this item.
- **No override ledger.** The trigger "the owner has overridden this gate before" was considered and dropped: no durable
  per-gate override record exists today, and building one is its own item.

## Acceptance criteria

**Happy path**
- [ ] Given an interactive sequential `/automate` run and a Plan Review PASS with notes, when Launch Pad reaches Phase 6,
      then no question is asked. The brief is saved with the notes carried, and `## Progress` gains one line naming
      `LP-SAVE-NOTE`, `Save and exit` and the reason.
- [ ] Given a folder or prompt source, when the Queue is resolved, then `AUT-QUEUE` is auto-answered `Process`. The
      existing `queue-confirm` skip lines are unchanged for the cases they already cover.
- [ ] Given exactly one incomplete run, when `/automate` starts, then `AUT-RESUME` is auto-answered `Continue`.
      Given two or more incomplete runs, then it asks as before.
- [ ] Given a finished or parked run with at least one auto-answer, when the run ends or parks, then one block lists
      every auto-answer of the run.

**Escalation and edge cases**
- [ ] Given a Plan Review PASS that carries a MEDIUM-or-higher issue, when Phase 6 runs, then `LP-SAVE-NOTE` is asked,
      and the record names the trigger.
- [ ] Given `classify-risk.sh` reports high-risk for the item, when any `auto` gate fires, then it asks.
- [ ] Given the off switch is set, when any gate fires, then it asks exactly as before this item, and `--resume` keeps the setting.
- [ ] Given a question whose labels, with `(Recommended)` stripped, are not exactly the catalog row's labels, or one
      with no recommended label, then it asks. The tier fails toward asking, never toward an answer.
- [ ] Given a `human-only` code, then nothing in this item answers it, in a lane or out of one.

**Can't-ask and lanes**
- [ ] Every gate's can't-ask branch is unchanged. An `auto` answer applies only where the run could have asked.
      Non-interactive and subagent runs keep their named fail-closed statuses
      (`docs/ARCHITECTURE_CONTRACTS.md` §"Question-gate inventory").
- [ ] Inside a lane, an `auto` gate is answered the same way, and the existing `allowed` policy path
      (`lane-policy.sh resolve` / `decide`) behaves byte-identically for `allowed` codes.

**Checks**
- [ ] `lane-policy.sh catalog` carries the new tier. `docs/LANE_GATES.md` is regenerated from it in the same change, and
      `scripts/check-gate-headers.sh` passes. No other surface restates the `auto` set as a list; each points to the catalog.
- [ ] `scripts/test-lane-policy.sh` has legs for: the `auto` tier, each escalation trigger, the off switch, a label
      mismatch, and a `human-only` code that stays human.
- [ ] `docs/ARCHITECTURE_CONTRACTS.md` §"Question-gate inventory" and `docs/LANE_GATES.md` describe the three tiers.
- [ ] `bash scripts/check-token-budget.sh` passes for every edited agent, command and skill.
- [ ] `bash scripts/check-version-bump.sh` passes (a `changelog.d/` fragment, no hand version edits).

## Priority: MVP

**Rationale:** LP-SAVE-NOTE alone is 22% of all catalog-coded questions, and every one of them was answered with the
default. This is the single largest attention cost the evidence shows, with no decision in it.

## Assumptions

- The ask sites are prose in agent, command and skill files. The answer seat can be a deterministic helper the prose
  calls before asking (the `queue-confirm` pattern), a `PreToolUse[AskUserQuestion]` hook, or both. The choice is the
  implementer's, provided every AC holds.
- Plan Review issue severity is machine-readable at Phase 6. If it is not, the MEDIUM+ trigger asks (fail toward asking).

## Risks

- **Rubber-stamp risk moves, it does not vanish.** If the end-of-run list goes unread, a bad recommendation passes
  silently. Mitigation: the list sits in the park block, the one place the owner always reads.
- **A recommended label written by the same model it gates.** Mitigation: the escalation triggers are deterministic and
  never read the model's own confidence.

## Rule conflicts (open decisions)

none

## Depends on
none

## Touches
loomwright/scripts/lane-policy.sh
loomwright/scripts/test-lane-policy.sh
loomwright/scripts/check-gate-headers.sh
loomwright/scripts/automate-lanes.d/relay.sh
loomwright/scripts/automate-helpers.sh
loomwright/hooks/hooks.json
loomwright/docs/LANE_GATES.md
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/agents/launch-pad.md
loomwright/commands/launch-pad.md
loomwright/skills/automate-loop/intake.md
loomwright/skills/automate-loop/resume.md
loomwright/skills/automate-loop/per-item-loop.md
changelog.d/

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-11-04T02:23:48Z
- **Brief:** .supervisor/jobs/done/2026-11-03-auto-answer-routine-question-gates.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/813
