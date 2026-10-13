# Criterion 20 fixtures: expected findings

This file is the answer key for the three `brief-*.md` fixtures in this directory. It is **never shown to a
reviewer**: a live Plan Reviewer probe passes brief content only, so no brief carries a verdict, a label, a
criterion number or a header comment. `scripts/test-pr-body-evidence-seam.sh` fails if a hint leaks into a brief
and pins the rows below.

The three briefs share one title, one task and AC1/AC3; only AC2 differs. AC2 is the #511 shape: a criterion that
asks for the exact command behind every number (as on PR #459) or for rejected alternatives. AC3 mentions a PR
without asking for anything in its body, so it is never a finding.

Only the Criterion 20 column is the answer key; other criteria may add their own notes on a fixture.

| Fixture | Expected Criterion 20 result |
|---|---|
| `brief-pr-body.md` | 20a HIGH `pr_body_evidence` on AC2 (its only evidence is the PR body), so the decision is FAIL |
| `brief-pr-description.md` | 20a HIGH `pr_body_evidence` on AC2 (its only evidence is the PR description), so the decision is FAIL |
| `brief-evidence-file.md` | none: AC2's evidence is the committed `docs/evidence/qa-prompt-sizes.md` (a File Impact Map create and a `lanes:` entry); the PR body only links to it |
