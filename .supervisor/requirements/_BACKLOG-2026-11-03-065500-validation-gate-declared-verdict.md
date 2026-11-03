# Validation gate reads committed evidence — plan doc (index document, not an implementable item)

## Status: done (index document — nothing to implement)

## Why now
In run automate-2026-11-02-173506 (PR #802), V3 and V4 had committed, passing evidence, but the gate made the owner waive them. The gate reads only the PR body, while the evidence rule (#511) puts evidence in committed files the body only links. Every future Running system step will park the same way until this is fixed.

## Owner decisions
- 2026-11-03 (owner, at PO-ASSUME): the gate reads an evidence file only through a verdict line the file declares (step + result), and never infers either from headings or words inside the output.
- 2026-11-03 (owner, at PO-SCOPE): new files only; PR #802's two evidence files are not edited.

## Order
| Item | Delivers | Depends on | Can run in parallel with |
|---|---|---|---|
| 2026-11-03-064334 | validation-gate and lane-readiness accept a committed docs/evidence file that declares a passing verdict for the step; the authoring surfaces teach the line | none | none (single item) |

## Run
/automate --backlog .supervisor/requirements/_BACKLOG-2026-11-03-065500-validation-gate-declared-verdict.md --parallel 1
Safe mode (no --auto-merge). N = 1 is single-lane mode: the item runs in its own clone, and the owner merges its PR.
Serialisations: outside this set, the item shares loomwright/scripts/automate-lanes.d/readiness.sh with dismissed-followups/03-lanes-and-meta-sync-defects.md and automate-loop docs with dismissed-followups/12-bundle-04ab-drivers-and-gate-tooling.md; do not run it in the same wave as either.
Hotspots: none inside the set. Its own changelog.d fragment.
Companions rule: none proposed.

## Considered and not queued
- Reusing the PR-body passage reader on evidence files: measured on PR #802's files on 2026-11-03, and it fails in three ways (title-heading anchor, `(V4)` naming, expected FAIL output).
- Pasting evidence into the PR body at FINALIZE: this would reverse #511, and nothing can edit the body after a heal.
- Back-filling a verdict line into PR #802's evidence files: owner chose new files only.

## Revisit when
- Authors often forget the declared line and steps keep parking (the authoring surfaces then need a check, not just prose).
- An evidence file needs to prove more than one step and the line's syntax gets in the way.

## Checklist
- [ ] .supervisor/requirements/2026-11-03-064334-validation-gate-accepts-committed-evidence-with-a-declared-verdict.md
