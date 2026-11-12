# Criterion 23 fixtures: briefs, answer key and fixture repo

Four fixture briefs for Plan Reviewer Criterion 23 (approach justification). The answer key is the
`expected-<letter>.json` file beside each brief (`fixture`, `trigger`, `sub_check`, `severity`, `category`,
`decision`). Read the expected shapes there; this file does not restate them.

The answer key is **never shown to a reviewer**: a live Plan Reviewer probe passes brief content only. That is
why the briefs carry a neutral header comment and no verdict, category or sub-check label anywhere.
`scripts/test-design-decisions.sh` fails when such a hint leaks into a brief.

`repo/` is the project every brief plans against (a Node.js 20 + Express 4 API with bash note scripts):

- `repo/package.json` is the manifest a T1 entry's `chosen:` is searched in. It does not declare
  `express-rate-limit`, so that library is a new dependency.
- `repo/scripts/propose-common.sh` already defines `pc_slugify`, the helper brief-c's new `scripts/slugify.sh`
  would hand-roll.
- `repo/scripts/new-note.sh` and `repo/src/routes/upload.js` are the files the briefs modify, so a probe's
  file-path checks find them.

Each brief also carries a one-entry `## Touched-file invariants` section and complete contract blocks, so the
other criteria have no HIGH finding to add and the expected `decision` stays Criterion 23's. The test pins the
text that produces these shapes, never a model's verdict. The running-system runs are
`docs/evidence/design-decisions.md` (Validations V4–V6).
