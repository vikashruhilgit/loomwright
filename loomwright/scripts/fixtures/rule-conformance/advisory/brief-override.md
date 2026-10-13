<!-- Plan Reviewer Criterion 17 fixture, paired with rules/advisory.json. Pinned by
     scripts/test-rule-conformance-seam.sh. Not a real job. -->
# Supervisor Job: Delivery address city field

## Environment
- **Project:** fixture-shop (TypeScript, React 18)
- **Base commit:** 0000000000000000000000000000000000000000

## Task
**Goal:** Add a City field to the delivery address form in `src/ui/address-form.tsx`.

## Design decisions
1. The City field is a `Select` listing all 20 supported delivery cities, sorted alphabetically.

## Out of scope
- The Select-versus-AutoComplete question for City is already decided; do not revisit it.

## Acceptance Criteria
- [ ] **AC1:** the delivery address form shows a City `Select` over the 20 supported delivery cities.
- [ ] **AC2:** submitting the form without a City shows the inline error `City is required`.
- [ ] **AC3:** `src/ui/address-form.spec.tsx` covers AC1–AC2 and passes.

## Touched-file invariants

- **`src/ui/address-form.tsx`** — keep: the exported `AddressForm(` component's props; pinned by: `src/ui/address-form.spec.tsx`, which this change creates.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | City field | AC1–AC3 | 1 modify, 1 create | unit-testing | LAUNCHABLE |

## Subtask Contracts
# Subtask 1
provides:
  - {kind: "symbol", path: "src/ui/address-form.tsx", name: "CityField"}
requires: []
lanes:
  - "src/ui/address-form.tsx"
  - "src/ui/address-form.spec.tsx"
external_requires: []

## Parallelism Analysis
- **Batch 1:** Subtask 1
- **Recommended workers:** 1

## File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| ui | `src/ui/address-form.tsx` | `src/ui/address-form.spec.tsx` | HIGH |

## Skill References
- `skills/unit-testing/SKILL.md`

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A Select under src/ui/ offers at most about 10 options; a longer list uses AutoComplete instead.
  - id: ui-select-max-ten-options
  - enforcement: advisory
  - category: ui
  - check (data only, NOT executed by this reader): (none)

## Rule conflicts (open decisions)
- Conflicts with house rule ui-select-max-ten-options (advisory): AC "it is a Select over the 20 supported delivery cities" vs rule "A Select under src/ui/ offers at most about 10 options; a longer list uses AutoComplete instead.". Owner's choice: override
- Rule override: ui-select-max-ten-options — the depot team wants every city visible at once for this release; AutoComplete is planned for the next one (acknowledged by the owner: /product-owner session, 2026-10-13)

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| A city outside the supported list is submitted | LOW | The field only offers the supported cities. |

## Configuration
- **Mode:** sequential
- **Recommended workers:** 1

## Handoff
/supervisor job: .supervisor/jobs/pending/fixture-city-field.md
