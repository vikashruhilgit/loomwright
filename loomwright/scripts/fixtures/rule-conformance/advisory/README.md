# Criterion 17c fixtures: expected verdicts

This file is the answer key for the advisory-rule fixtures in this directory (issue #432, plan half). Like the
parent directory's README, it is **never shown to a reviewer**: a live Plan Reviewer probe passes brief content
only, so the two briefs share one title (`# Supervisor Job: Delivery address city field`) and carry no verdict.
`scripts/test-rule-conformance-seam.sh` PART 5 pins the rows below and fails if a hint leaks into a brief.

Every fixture pairs with `rules/advisory.json` (one `advisory` rule, `check: null`, routed to `src/ui/*`). The
APPLICABLE RULES block a probe pastes is the output of `read-rules.sh --with-ids src/ui/address-form.tsx` run in
a sandbox repo that holds that store.

| Fixture | Expected verdict |
|---|---|
| `brief-no-override.md` | NEEDS_HUMAN: 17c MEDIUM `rule_conformance` (AC1 and Design decision 1 put 20 options in a Select; the `## Out of scope` line is not an override) |
| `brief-override.md` | PASS: no 17c issue (same brief plus the owner-acknowledged `Rule override:` line, carried verbatim from the story) |
| `story-conflict.md` | Product Owner output shape: a `## Rule conflicts (open decisions)` section naming the conflicting AC and the rule id, before `## Depends on` |

`brief-override.md`'s `## Rule conflicts (open decisions)` section is byte-identical to `story-conflict.md`'s:
that is Launch Pad Phase 5 action 6a (iii) carrying the section through unchanged.
