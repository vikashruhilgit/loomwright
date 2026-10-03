# Churn-ledger candidates dismissed durably

## Status: done

Owner triage, 2026-10-01. Each `evidence-set:` line below is matched by `propose-work.sh`'s `superseded_by()`
(a `## Status: done` requirement file under `.supervisor/requirements/`), so `/propose` stops re-emitting it.
Deleting the draft alone would not do that.

## drain_churn / self_heal (decided 2026-09-06)

evidence-set: drain_churn/self_heal@L44.0,L45.0,L46.0,L47.0,L48.0

All five cited `evidence` strings are the same template, `until-mergeable drain, decision=READY, fix_cycles=N`.
The candidate only says "drains take fix cycles", which is not a finding.

## The five pairs left undecided on 2026-09-06

evidence-set: execution_bug/self_heal@L7.1,L8.0,L9.0,L15.1,L16.0
evidence-set: execution_bug/worker@L5.4,L11.4,L14.3,L15.0,L15.3
evidence-set: quality_gap/self_heal@L7.3,L9.1,L9.4,L10.1,L15.5
evidence-set: quality_gap/worker@L2.0,L3.2,L3.5,L5.0,L5.2
evidence-set: convention_mismatch/worker@L2.1,L3.3,L6.1,L7.0,L14.1

Every cited entry sits on ledger lines 2–16, all from PRs merged months before this triage. The defects they name
were fixed in those PRs. The stage-level patterns are already the target of later work: the executing Phase 4.5
review (EXECUTION DIRECTIVE), `verify-provides.sh`, and the rules substrate and its gate. A real recurrence will
cite new ledger lines, produce a different `evidence-set:` token, and come back as a new candidate. This
dismissal does not suppress that.
