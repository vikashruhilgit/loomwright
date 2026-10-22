# right-size / merge-items fixtures

Hermetic inputs for `test-automate-helpers.d/17-right-size.sh` (parallel-automate/18b). The test copies
them into a `mktemp -d` requirements tree under their original names; no test reads the live
`.supervisor/requirements/` (which is gitignored and lives on the metadata branch).

The real files were copied once, on 2026-10-22, from the primary checkout's gitignored requirements tree
(base 7b7cb08). Every edit made to a copy is listed below; nothing else was changed. Each copy was checked
for home paths (`/(Users|home)/<name>/`): none.

| File | Source | Edit |
|---|---|---|
| `af-17-pre.md` | `automate-followups/17-children-settled-non-plugin-spawns.md` | its `## Status: parked (merged 2026-10-05 …)` line removed: the file as it was before the merge |
| `af-25-pre.md` | `automate-followups/25-children-settled-before-publish.md` | the same |
| `af-33-merged.md` | `automate-followups/33-children-settled-gate.md` (the hand merge) | the sections added after the merge dropped: `## Touches re-pointed 2026-10-07 …`, `## Amended 2026-10-07 …`, and the close-out sentinel with its `## Status: done` block |
| `ms-09.md` | `meta-sync-followups/09-scrub-safe-schema-examples.md` | `## Status:` restamped `pending` (it is parked in the live tree) |
| `ms-10.md` | `meta-sync-followups/10-anchor-home-path-scrub.md` | the same |
| `iq-02-shaped.md` | none: synthesized | the shape of `implementation-quality/02` on 2026-10-09 (more than 30 Touches files, 10 `## Part` headings) with placeholder text |
| `merge-af33.expected.md` | `merge-items` output | the golden: `merge-items` on `af-17-pre.md` (Part A) and `af-25-pre.md` (Part B), title and goal from `af-33-merged.md`, `--date 2026-10-05` |

## What the legs read from them

- **ms/09 + ms/10.** Their companion-expanded Touches counts are 4 and 7: ms/10 names
  `loomwright/agents/launch-pad.md`, which the repo's `loomwright/agents/*.md` companion rule expands by two
  files. The test's tree carries only that rule (read from the repo's `.agent/companions.json` at test time)
  and sets `right_size_small` to 7, because the 2026-10-06 check that named this pair predates the 3-file
  default. So at 7 both read `small` and name each other as the top candidate (`same folder`), and at the
  default both read `ok`. The two items share no Touches path, so the candidate line says `0 shared files,
  same folder`: the source text's "3 shared files" example was illustrative, not a measurement.
- **af/17 + af/25 → af/33.** `merge-items` reproduces the hand merge with zero lost lines. The golden differs
  from the hand-merged `af-33-merged.md` in heading depth (Parts at H2, their sections at H3), blank lines,
  the generated header, and one real difference: Part A also carries af/17's 4-line blockquote
  (`> **Promoted from `proposed/` 2026-10-01** …` / `> **Origin (2026-10-01).** …`), which the hand merge
  dropped. That is the hand-merge line loss the post-check exists to catch.
- **iq-02-shaped.** Large on both causes: `large (33 files, 10 parts) — will not fit one PR: split by Part`.
