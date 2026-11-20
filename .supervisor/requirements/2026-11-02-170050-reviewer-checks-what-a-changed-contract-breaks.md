# Reviewer checks what a changed contract breaks outside the diff

## Status: pending

> From a 2026-11-02 question: does our code review check "what can this change break?" Mostly it doesn't. Every
> lens in `agents/code-reviewer.md` looks inward at the diff. The Adversarial-Input Lens covers "every code path the
> diff adds or changes". §5 runs "only the specific existing tests that cover the diff". The result-block section
> says "Scope is only the current task's code". LSP find-references / call-hierarchy is one optional "if available"
> bullet in Review Process step 1, and nothing requires reporting on it. `consistency_audit` does cross-file work,
> but only for Loomwright's own surfaces, never a user project. Launch Pad's `## Touched-file invariants` (Phase 3
> action 11, Plan Reviewer Criterion 18) names producer/consumer contracts at **plan** time. Nothing checks them
> at **review** time against the code that actually changed.

**As a** plugin owner whose PRs go through Phase 4.5 and `/review-pr`,
**I want** the code reviewer to list every contract the diff changes and check each unchanged consumer of it,
**so that** a change that breaks a caller outside the diff is caught in review, not by a CI bot, a later round or
production. Today only a pre-existing test that happens to exercise that caller catches it.

## Problem

A contract is anything another unit relies on: a function signature or return shape, a result-block field, a
script exit code or stdout format, a file/JSON/schema shape, a CLI flag, an env var, an emitted event or log line,
a hook payload. When a diff changes one, the reviewer reads the new side carefully and never opens the consumers.
An empty consumer check also looks exactly like "no impact", because no record says the reviewer looked.

## Scope

**Part A: the lens (`loomwright/agents/code-reviewer.md`).** Add a "Changed-contract consumers" lens next to the
Adversarial-Input Lens. It is part of the SAME review pass: no new agent, no new spawn, no new loop round. For each
contract the diff changes:
1. Find consumers with LSP references when available. Fall back to repo-wide `grep -rn` on the name/field/flag/
   env var. When the owned repo-map exists, use it to find them; it is never required (`skills/brain-context` ladder).
2. Read each consumer that is outside the diff and decide whether it still works with the new behaviour.
3. When the EXECUTION DIRECTIVE is present (Phase 4.5), also run the existing tests that cover those consumers, not
   only the diff's own tests. Without it the lens stays static, like the rest of §5's gate.
Upgrade the optional LSP bullet in Review Process step 1 into a pointer to this lens. Do not keep two copies.

**Part B: the record (schema + validator).** Add a `contract_impact` field to CODE_REVIEW_RESULT
(`docs/result-schemas/code-review-result.md`; the owner picks the exact name), one entry per changed contract:
`{contract, consumers_found: <n>, search: lsp|grep|repo_map, verdict: ok|broken|unverified, reason}`. A diff that
changes no contract records that explicitly (e.g. `contract_impact: none`). The field never stays silently absent.
`validate-code-review-result.py` checks the shape, following the `cannot_determine` / `house_rule_verdicts`
precedent.

**Part C: severity + decision.** A `broken` consumer is an ordinary `category: new` finding at HIGH or BLOCKING
under the existing severity-assignment rule (reference it, do not restate it). It enters the same FAIL/PASS decision
and fix floor. `unverified` is not a finding. It is the honest "could not check" state, and it counts toward the
same verdict binding as §5's `unverified`.

## Acceptance Criteria

**Happy path**
- [ ] Given a diff that renames a field in a script's JSON output, and an unchanged script elsewhere that reads that
      field, when the reviewer runs, then the result names the contract, finds that consumer, marks it `broken`, and
      raises a HIGH-or-above `new` finding that names the consumer file.
- [ ] Given a diff that changes a function's signature and updates every caller in the same diff, when the reviewer
      runs, then the contract entry lists the callers it found with verdict `ok` and raises no finding.
- [ ] Given Phase 4.5 with the EXECUTION DIRECTIVE, when a changed contract has consumers with existing tests, then
      the reviewer runs those tests and the entry's `reason` names the command it ran.
- [ ] Given a diff that changes no contract (e.g. a comment-only or internal-only change), when the reviewer runs,
      then the result records that explicitly, not an absent field.

**Edge cases**
- [ ] Given a contract whose consumers are found only by name (dynamic dispatch, a derived path, a string key built
      at runtime), when the search finds zero hits, then the entry is `unverified` with a reason, never `ok`. Zero
      hits are not evidence of zero consumers.
- [ ] Given no LSP, when the lens runs, then it uses grep and records `search: grep`. It never skips the lens.
- [ ] Given a consumer that is a doc or prompt quoting the old shape, when found, then it is reported (a doc
      consumer is still a consumer). Severity follows the existing drift caps, not HIGH.
- [ ] Given a contract with too many consumers to read in budget (owner sets the cap), when the cap is hit, then
      the reviewer checks a stated sample, marks the rest `unverified` with the count, and never claims `ok` for
      what it did not read.
- [ ] Given a standalone `/review-pr` on a PR without the EXECUTION DIRECTIVE, when the lens runs, then it does
      only the static read and runs no consumer tests.

**Error scenarios**
- [ ] Given a CODE_REVIEW_RESULT with no contract-impact record at all, when the validator runs, then it blocks with
      the documented command-hook `{"decision": "block", …}` shape, not the `ok` shape.
- [ ] Given a malformed entry (missing `verdict`, unknown verdict value, empty `reason` on `unverified`), when the
      validator runs, then it blocks naming the entry index.
- [ ] Given a consumer test command that errors for environmental reasons, when the lens runs, then the entry is
      `unverified` (reason names the error). It never turns into `ok`.

## Constraints (CLAUDE.md invariants this must keep)
- Two review lenses, not four passes. This is a lens inside the existing reviewer pass. It adds no per-subtask LLM
  reviewer and no extra heal round.
- The CI `claude-review` lens stays static-only and is out of scope. Editing the review workflow file makes that run
  skip itself, so it cannot test its own change.
- `agents/code-reviewer.md` stays within its `prompt-token-budgets.json` row. Measure after the edit. If it must
  grow, re-baseline the row and the `ARCHITECTURE_CONTRACTS.md` mirror in the same change.
- RESULT_SCHEMAS is the single source for the new field. No other doc restates its key list (house rule
  `process-when-one-surface-restates-…`).
- No history in the runtime prompt. This file's story goes to `CHANGELOG.md` / `changelog.d/`, never into the agent
  text.
- The release goes through a `changelog.d/` fragment; `bash scripts/check-version-bump.sh` passes.

## Validation (must pass before merge)
1. `loomwright/scripts/test-validate-code-review-result.sh` covers: field absent → block; `none` → allow; each
   verdict value; malformed entry → block naming the index; empty `unverified` reason → block.
2. A fixture pair under `scripts/` reproduces the happy-path rename case. A scratch repo with a producer whose output
   field is renamed and an unchanged consumer reading the old name. Expected: one `broken` entry and a HIGH finding.
   This is the end-to-end proof that the lens catches what today's review does not.
3. `bash scripts/check-token-budget.sh` and `bash scripts/check-doc-currency.sh` pass.
4. `bash scripts/ci-local.sh --affected` passes.

## Priority: MVP
**Rationale:** this is the one class of regression neither review lens is told to look for, and the plan-time
consumer list (Touched-file invariants) has no review-time check behind it.

## Assumptions
- Requiring the record on every CODE_REVIEW_RESULT is allowed without a `schema_version` bump. The plugin's own
  reviewer is the only emitter. If not, bump to v4 and accept v3 for a window, following the existing v2→v3
  precedent. Owner decides.
- LSP references are available in some sessions and not others. The grep fallback is good enough to be the floor.

## Risks
- **Token / turn cost.** Consumer reads add work to every review. Subagents already hit the turn limit before
  emitting their result block, and this makes that more likely. Mitigation: the consumer cap and the
  `unverified`-with-count rule.
- **False `ok`.** A grep that finds nothing reads as safe. Mitigation: zero hits on a name-only search is
  `unverified`, never `ok`.
- **Interaction with the pending diff-scoped re-review item**
  (`2026-11-01-092114-phase-4-5-re-reviews-converge-on-what-the-last-fix-changed.md`). After round 1, the lens must
  still run on contracts the last fix changed, or diff scoping hides a consumer the fix broke.

## Considered and not queued
- Changing the CI `claude-review` prompt. Static-only, and the PR changing it cannot test itself. Revisit after this
  ships, as a separate PR that does not also touch other review surfaces.
- A separate "impact analysis" agent. Rejected: it would be a third LLM review lens.

## Rule conflicts (open decisions)
none

## Depends on
none

## Touches
loomwright/agents/code-reviewer.md
loomwright/docs/result-schemas/code-review-result.md
loomwright/scripts/validate-code-review-result.py
loomwright/scripts/test-validate-code-review-result.sh
loomwright/docs/prompt-token-budgets.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
changelog.d
