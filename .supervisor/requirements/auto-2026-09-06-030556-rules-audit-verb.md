# Requirement: `/rules audit` — a correctness audit over the standing `.agent/rules/` store

## Goal

Add a `/rules audit` verb: a READ-ONLY, PROPOSE-ONLY correctness audit that re-validates every
rule in the committed `.agent/rules/` store, reports inaccuracies with their evidence, and
recommends fixes expressed as existing actions.

## Why (the gap this closes)

`loomwright/scripts/validate-entry.sh` is the shared write-time validator every sole writer calls.
It already runs five correctness checks — `contradiction`, `duplicate`, `provenance` (BLOCKING) and
`dead_reference`, `cross_repo_reference` (ADVISORY, demoted after six review rounds of prose false
positives). `add-rule.sh` runs all five on every `/rules add`.

But it runs them **once, at write time, against the store as it stood that day.** Nothing
re-validates a rule as the repo drifts underneath it. A rule that validated clean in March can be
false in September because the code moved, CLAUDE.md changed, or a rule added later contradicted it.

`/rules check` is a DIFFERENT thing — it executes `must` rules' shell behind a confirm gate. The two
verbs must not be confused, and the docs must say so in a way a gate can assert.

## Acceptance Criteria

- [ ] Given the committed store, when `bash loomwright/scripts/audit-rules.sh` runs, then it re-runs
      `validate-entry.sh`'s five checks against every standing rule and prints per-rule findings.
- [ ] Given a store containing a `must` rule whose `check` is `null`, when the audit runs, then it
      reports that rule as an enforcement claim with no mechanism.
- [ ] Given a rule whose `applies_to` glob matches zero paths in the repo, when the audit runs, then
      it reports that rule as one that can never fire.
- [ ] Given a rule whose `supersedes` names an id absent from the store, when the audit runs, then it
      reports a dangling supersedes target.
- [ ] Given a rule that a later rule supersedes, when the audit runs, then it reports that rule as dead.
- [ ] Given any store, when the audit runs, then the store is byte-unchanged afterwards.
- [ ] Given any store, when the audit runs, then no rule's `check` string is ever executed.
- [ ] Given a store with zero findings, when the audit reports, then it states the store size and
      frames "0 issues" as a small-N result, never as evidence the store is sound.

## Scope (7 items — all required)

1. **New deterministic engine `loomwright/scripts/audit-rules.sh`** — READ-ONLY, with **no write mode
   at all** (not "dry-run by default" — dry-run ONLY, mirroring `harvest-conventions.sh`'s posture,
   whose header states the rationale: a read-only engine is strictly stronger than an opt-in write
   flag because there is no flag that could be passed by accident). It must **SOURCE
   `validate-entry.sh`** and re-run its five checks rather than reimplementing them. A second copy of
   the correctness logic is exactly the "a restated list drifts silently" defect this repo's own
   `process` rule names — reimplementing it would make the audit violate the store it audits.

2. **Store-wide checks** — the ones only answerable across the whole store, which a per-write
   validator structurally cannot ask:
   - a `must` rule with `check: null` (an enforcement claim with no mechanism)
   - an `applies_to` glob matching zero paths in the repo (a rule that can never fire)
   - a dangling `supersedes` target (names an id no rule carries)
   - a rule already superseded, and therefore dead
   - contradiction against a rule added AFTER it (write-time validation could not have seen it)

3. **Command + protocol surface** — `/rules audit` in `loomwright/commands/rules.md` and the protocol
   section in `loomwright/skills/rules/SKILL.md`. The command owns the JUDGMENT half: reading each
   statement against the repo and CLAUDE.md for inaccuracy, vagueness, and unfalsifiability. That
   half cannot be a script and must not pretend to be one.

4. **No new write path.** Every recommendation is expressed as an EXISTING action — `/rules add
   --supersedes <id>` or `add-rule.sh --retract --target <id> --reason <text>`. `add-rule.sh` stays
   the sole writer; the audit proposes and never writes.

5. **Never executes a `check`.** Static lint of the string only. `rules-check.sh` stays the ONLY
   execution path in the slice; that trust boundary is a standing invariant and this change must not
   widen it.

6. **Tests — `loomwright/scripts/test-audit-rules.sh`.** Mutation-control every store-wide assertion:
   delete the mechanism and prove the test fails. An assertion that still passes with its mechanism
   removed is vacuous, and this repo has shipped that defect before. Also assert the read-only
   posture directly — run against a live store and diff it byte-for-byte.

7. **Doc-currency.** Bump the command count wherever it is authoritative, declare a token budget if
   an agent prompt is touched, and extend `test-rules-docs.sh` to assert the audit-vs-check
   distinction is stated, so the naming confusion cannot silently drift back in.

## Honest limits — state these in the output, do not hide them

- The store currently holds **3 rules, all `advisory`, all `check: null`**. The deterministic tier
  will therefore find close to nothing today. Report "0 issues" as the small-N result it is, never as
  evidence the store is sound.
- Report findings **with their evidence**, never as a bare verdict. `dead_reference` and
  `cross_repo_reference` were demoted to advisory precisely because prose is ambiguous — six
  consecutive review rounds produced false refusals, and an audit inherits that same ambiguity.
- Findings are **ADVISORY throughout**. Nothing gates, nothing blocks a PR, and rules remain
  subordinate to CLAUDE.md.

## Constraints

- `add-rule.sh` remains the sole writer. No second writer, no new write path.
- `rules-check.sh` remains the sole executor of a rule's `check`.
- The rule schema is FROZEN at 7 always-present members plus optional `supersedes`. The audit adds
  no member and writes no sidecar.
- macOS bash 3.2 + BSD userland: no `timeout`; prefer `stat -c %Y` with a BSD `-f %m` fallback and
  validate numeric before arithmetic.

## Outcomes Rubric

- [ ] `audit-rules.sh` exists, sources `validate-entry.sh`, and re-runs all five shared checks — it does not reimplement any of them
- [ ] `audit-rules.sh` has no write mode and no write flag; a run leaves the store byte-identical
- [ ] All five store-wide checks are implemented and each one is proven by a mutation-controlled test
- [ ] No code path executes a rule's `check`; the static-lint-only posture is asserted by a test
- [ ] `/rules audit` is documented in both `commands/rules.md` and `skills/rules/SKILL.md`, and every recommendation it emits names an existing action (`/rules add --supersedes` or `add-rule.sh --retract`)
- [ ] `test-rules-docs.sh` asserts the audit-vs-check distinction is stated, so the naming confusion cannot drift back
- [ ] The small-N honest limit is stated in the audit's own output, not only in the docs
- [ ] Command count and any touched token budget are updated; `check-doc-currency.sh` passes

## Status: brief-shipped

Job `.supervisor/jobs/done/2026-09-06-rules-audit-verb.md` completed (reconciled from the job lifecycle, not self-reported).
Acceptance criteria are NOT machine-verified here — review them before promoting this to `## Status: done`.
