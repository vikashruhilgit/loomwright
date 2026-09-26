# 05 — Rules reach the PLAN: Launch Pad routes applicable rules into the brief, Plan Reviewer gates on them

## Status: pending

> **Origin (2026-09-26).** Owner question after twin-loop/08 shipped (PR #267): *"why are these only for after
> implementation, why not at planning and at the time of working as well?"* 08 gave the substrate its trust key
> (`rules-check.sh --if-stamped`, content-keyed user-scope stamp) and one advisory consumer (Phase 4.5). Nothing
> upstream of the diff reads the store at all: `grep -c` for `read-rules|.agent/rules|house.rules|rules-check`
> over `agents/{launch-pad,plan-reviewer,orchestrator,product-owner}.md` returns **0 on all four**. A plan may
> therefore propose exactly what a `must` rule forbids, and the cost of discovering it is a whole worker run
> plus a review round — the most expensive point in the loop.

## Problem
The house-rules store is consumed only *downstream* of implementation. Two specific gaps:

1. **Launch Pad already computes the one input the reader needs and never uses it.** It builds a File Impact
   Map (action 3) and even passes those paths to the churn reader (`read-postmortem.sh`, args-bearing, at
   `agents/launch-pad.md` action 0b). `read-rules.sh` routes on `applies_to` given exactly such a path set, so
   the brief could name the conventions that apply to the files it is about to touch. It does not.
2. **Plan Reviewer gates brief save (`PASS`/`NEEDS_HUMAN`/`FAIL`) across 16 criteria and none of them is rule
   conformance.** It is the cheapest existing gate in the system and it cannot see the store.

## Goal
A brief carries the conventions that apply to its own File Impact Map, and the existing brief-save gate refuses
a plan that contradicts an applicable `must` rule or silently omits it from its own acceptance surface.

## Scope (recommendation, not pre-decided)

**(a) Launch Pad reads the store on the impact-map path set.** After the File Impact Map is settled, run
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-rules.sh" <impact-map paths…>` — paths as **command-line ARGUMENTS,
never stdin** (the no-hang shape the churn reader and the Phase 4.5 seam already use). Advisory, fail-safe: the
reader always exits 0 and self-gates on `.agent/rules/*.json`, so no detection wrapper is wanted. Empty output
⇒ omit the section entirely.

**(b) A new `rule: <rule-id>` bullet kind for `## Executable Acceptance`.** Today's kinds are
`{cmd, corpus-task, qa-executor}`; a machine-authored brief may emit **only** `corpus-task:` because
`cmd:`/bare-shell bullets are reserved for human authorship (Plan Reviewer Criterion 14). A `rule:` bullet
carries **no shell at all** — only an id — so it is machine-authorable by the same reasoning.
**Resolution must delegate, not re-implement:** `run-ground-truth.sh` must NOT read `.agent/rules/` or execute a
`check` itself. It resolves a `rule:` bullet by invoking `rules-check.sh --if-stamped` and reading its tally, so
`rules-check.sh` stays the **sole executor** of a rule's `check` (the §9 trust boundary) and the user-scope
stamp stays the only authorization.
> **Do not conflate the two stamps.** red-team-hardening/05's `sha256:` stamp lives *inside* an approved brief
> and gates `cmd:` bullets. A rule's check is NOT brief-embedded and a `.agent/rules/` object can land via an
> unreviewed PR, which is precisely why its authorization lives outside the repo. `skills/rules/SKILL.md` §8.1
> states this explicitly; a `rule:` bullet must never be routed through the brief stamp.

**(c) Applicable advisory rules go into the brief's constraints**, so the worker's existing DO-side paste
becomes brief-scoped rather than repo-wide.

**(d) Plan Reviewer Criterion 17 — Rule Conformance (conditional: skip silently when the reader is empty).**
Two checks:
- **17a** FAIL when the plan's stated approach contradicts an applicable `must` rule.
- **17b** FAIL when an applicable `must` rule with a non-null `check` is absent from the brief's
  `## Executable Acceptance` as a `rule:` bullet — a brief may not quietly drop its own acceptance.

## Acceptance criteria
- [ ] Launch Pad's brief, on a repo with a routed rule matching an impact-map path, names that rule; on a repo
      with an empty store the brief is **byte-identical** to today's (no empty heading, no placeholder).
- [ ] `run-ground-truth.sh` resolves `rule: <id>` by delegating to `rules-check.sh`; a grep proves it neither
      reads `.agent/rules/` nor runs a `check` itself.
- [ ] An unstamped machine run reports the `rule:` bullet as skipped/unapproved and **executes nothing** —
      asserted with a canary check that would create a file, proving the file never appears.
- [ ] A `rule:` bullet naming an id absent from the store fails per-check with a named reason (never silent-pass).
- [ ] Criterion 17a FAILs a brief that contradicts an applicable `must` rule; 17b FAILs a brief that omits one.
- [ ] Criterion 17 is skipped silently on an empty store — a fixture brief in a store-less repo returns the
      same verdict as before this item.
- [ ] Mutation control: reverting the Criterion-17 block makes the two FAIL cases pass.
- [ ] `check-command-sync.sh` / `check-doc-currency.sh` green (Criterion count 16 ⇒ 17 is a claimed number:
      grep the OLD value repo-wide, per CLAUDE.md).
- [ ] The full test loop is green — BOTH `loomwright/scripts/test-*.sh` AND root `scripts/test-*.sh` plus
      `scripts/check-vendor-coupling.sh`.

## Out of scope
- Any change to `read-rules.sh`'s routing semantics or to the rule schema (frozen at 7 members + optional
  `supersedes`).
- Making Launch Pad emit `cmd:` bullets — still forbidden for machine-authored briefs.

## Verified premises (read at `main @ 4f681d0`, 2026-09-26)
- `grep -c -iE 'read-rules|\.agent/rules|house.rules|rules-check'` over `agents/launch-pad.md`,
  `agents/plan-reviewer.md`, `agents/orchestrator.md`, `agents/product-owner.md`, `agents/worker.md` ⇒ **0** for
  every file.
- `agents/plan-reviewer.md`: `## 16 Review Criteria`; `grep -cE '^### [0-9]+\.'` ⇒ **16**. Criterion 14 is
  "Executable Acceptance Trust Surface".
- `agents/launch-pad.md` action 0b passes File-Impact-Map paths to the churn reader as arguments, not stdin;
  action 6 states `corpus-task:`-only for machine-authored briefs and "NEVER emit `cmd:` / bare-shell bullets".
- `scripts/run-ground-truth.sh` header: "kind in {cmd, corpus-task, qa-executor}"; a `--brief`-sourced `cmd:`
  bullet additionally requires the brief stamp or fails `cmd_unapproved`, never executed.
- `skills/rules/SKILL.md` §8.1: the rules stamp is "A DIFFERENT mechanism from `exec-acceptance-lib.sh`'s
  brief-embedded `sha256:` stamp … Do not conflate the two stamps or their storage locations."
- `scripts/read-rules.sh`: always exits 0, self-gates on `.agent/rules/*.json`, emits nothing on an empty store,
  and never executes a `check`.
