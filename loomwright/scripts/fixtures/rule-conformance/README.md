# Criterion 17 fixtures: expected verdicts

This file is the answer key for the three `brief-*.md` fixtures in this directory. It is **never shown to a
reviewer**: a live Plan Reviewer probe passes brief content only. That is why the briefs carry a neutral
header and one shared title (`# Supervisor Job: Partial refunds`), with no verdict or label anywhere in the
brief text. `scripts/test-rule-conformance-seam.sh` fails if a hint leaks back into a brief and pins the
rows below.

Every brief pairs with `rules/must.json` (one checkable `must` rule routed to `src/payments/refund.ts`).
The APPLICABLE RULES block a probe pastes is the output of `read-rules.sh --with-ids src/payments/refund.ts`
run in a sandbox repo that holds that store.

| Fixture | Expected Plan Reviewer verdict |
|---|---|
| `brief-conforming.md` | PASS: no `rule_conformance` issue (honors the rule and carries its `rule:` bullet) |
| `brief-contradicting.md` | FAIL: 17a HIGH `rule_conformance` (Design decisions use parseFloat/toFixed against the rule) |
| `brief-omitting.md` | FAIL: 17b HIGH `rule_conformance` (honors the rule but omits its `rule:` bullet) |
