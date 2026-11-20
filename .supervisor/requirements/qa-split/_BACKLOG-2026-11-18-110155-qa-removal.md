# Remove QA from Loomwright (qa-split Phase 4) — plan doc (index document, not an implementable item)

## Status: done (index document — nothing to implement)

## Why now
Phase 1 of `qa-split/00-plan.md` finished 2026-11-18, and the owner decided (Q4, 2026-11-12) that QA is
removed from Loomwright after Phase 1. The old QA has had zero `/verify` runs and two manual QA runs, yet
about 171 files outside `selvedge/` still name it and every count, budget and doc gate carries it.

## Owner decisions
none recorded

## Order
| Item | Delivers | Depends on | Can run in parallel with |
|---|---|---|---|
| 11a | Reviewed removal manifest + checker script + rollback note | none | none |
| 11b1 | QA agents, commands, skills, hooks and memory removed; `pre-qa-removal` tag; migration note (was item 13) | 11a | none |
| 11b2 | QA scripts, schema docs, blueprint and CI Playwright steps removed | 11b1 | none |
| 12 | Coupled surfaces re-pointed to Selvedge (`/propose --from-verify` reads `verdict.json`, `classify-risk` guards `selvedge.json`), each pinned by a test | 11b2 | none |

## Run
/automate --backlog .supervisor/requirements/qa-split/_BACKLOG-2026-11-18-110155-qa-removal.md
Sequential, safe mode (no `--auto-merge`): every item edits shared doc and count surfaces, so no two can
run at once. Review 11a's manifest by hand before 11b1 starts: it is the done-check for everything after.

## Considered and not queued
- Item 13 as its own PR: folded into 11b1, because the release that removes `/qa-executor` is the one
  whose changelog must say what replaced it.
- Splitting 11b1 / 11b2 further: `right-size` calls both large (33 and 61 files), but nearly all of it is
  whole-file deletion checked mechanically by the manifest checker. Split per surface only if review shows
  otherwise (the plan allows it).
- Removing `classify_kind`'s `qa-executor` arm: waits for Phase 3's item 09 (or D18).

## Revisit when
Item 11a's manifest is reviewed: if its real row count or a surface changes the split, reshape 11b1/11b2/12.

## Checklist
- [ ] .supervisor/requirements/qa-split/11a-qa-removal-manifest-and-rollback-tag.md
- [ ] .supervisor/requirements/qa-split/11b1-remove-qa-agents-commands-skills.md
- [ ] .supervisor/requirements/qa-split/11b2-remove-qa-scripts-schemas-ci.md
- [ ] .supervisor/requirements/qa-split/12-re-point-qa-couplings-to-selvedge.md
