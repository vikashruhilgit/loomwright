<!-- Product Owner rule-conflict fixture, paired with rules/advisory.json. Pinned by
     scripts/test-rule-conformance-seam.sh. Not a real story. -->
### Delivery address city field (type: story)

**As a** shopper,
**I want** to pick my city when I enter a delivery address,
**so that** my order is routed to the right depot.

#### Acceptance Criteria

**Happy Path:**
- [ ] Given the delivery address form, when I open the City field, then it is a Select over the 20 supported delivery cities.

**Error Scenarios:**
- [ ] Given no City is chosen, when I submit the form, then I see the inline error "City is required".

#### Priority: MVP
**Rationale:** orders cannot be routed without a city.

#### Assumptions
- The supported city list stays at 20 entries for this release.

#### Dependencies
- Depends on: none
- Blocks: none

#### Risks
- A longer city list makes a Select slow to scan.

## Rule conflicts (open decisions)
- Conflicts with house rule ui-select-max-ten-options (advisory): AC "it is a Select over the 20 supported delivery cities" vs rule "A Select under src/ui/ offers at most about 10 options; a longer list uses AutoComplete instead.". Owner's choice: override
- Rule override: ui-select-max-ten-options — the depot team wants every city visible at once for this release; AutoComplete is planned for the next one (acknowledged by the owner: /product-owner session, 2026-10-13)

## Depends on
none

## Touches
src/ui/address-form.tsx
src/ui/address-form.spec.tsx
