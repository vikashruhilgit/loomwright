<!-- FIXTURE (CONFORMING — honors the must rule and carries its rule: bullet; expect NO rule_conformance issue) for Plan Reviewer Criterion 17 (Rule Conformance). Paired with
     rules/must.json; the APPLICABLE RULES block is `read-rules.sh --with-ids src/payments/refund.ts`
     run in a sandbox repo holding that store. Pinned by scripts/test-rule-conformance-seam.sh;
     driven live by the plan-time-rule-routing AC7 probe. Not a real job. -->
# Supervisor Job: Partial refunds (conforming)

## Environment
- **Project:** fixture-shop (TypeScript, Node 20)
- **Base commit:** 0000000000000000000000000000000000000000

## Task
**Goal:** Support partial refunds on a captured order in `src/payments/refund.ts`.

## Design decisions
1. `partialRefund(orderId, amountCents: number)` takes an integer number of cents; a non-integer input is rejected with `InvalidAmountError`.
2. The refundable remainder is computed as `capturedCents - refundedCents`, all integer arithmetic.

## Acceptance Criteria
- [ ] **AC1:** a partial refund of less than the captured amount succeeds and records the refunded amount.
- [ ] **AC2:** a refund larger than the remaining refundable amount is rejected with `RefundExceedsCaptureError`.
- [ ] **AC3:** `src/payments/refund.spec.ts` covers AC1–AC2 and passes.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Partial refunds | AC1–AC3 | 1 modify, 1 create | unit-testing | LAUNCHABLE |

## Subtask Contracts
# Subtask 1
provides:
  - {kind: "symbol", path: "src/payments/refund.ts", name: "partialRefund"}
requires: []
lanes:
  - "src/payments/refund.ts"
  - "src/payments/refund.spec.ts"
external_requires: []

## Parallelism Analysis
- **Batch 1:** Subtask 1
- **Recommended workers:** 1

## File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| payments | `src/payments/refund.ts` | `src/payments/refund.spec.ts` | HIGH |

## Skill References
- `skills/unit-testing/SKILL.md`

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- [MUST] Money amounts under src/payments/ are integer minor units (cents); never parse or store money as a floating-point number (no parseFloat, no toFixed).
  - id: payments-money-integer-minor-units
  - enforcement: must
  - category: payments
  - check (data only, NOT executed by this reader): grep -rnE -- 'parseFloat|toFixed' src/payments; test $? -eq 1

## Executable Acceptance
- rule: payments-money-integer-minor-units

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| A partial refund exceeds the captured amount | MEDIUM | AC2 rejects it before calling the gateway. |

## Configuration
- **Mode:** sequential
- **Recommended workers:** 1

## Handoff
/supervisor job: .supervisor/jobs/pending/fixture-partial-refunds.md
