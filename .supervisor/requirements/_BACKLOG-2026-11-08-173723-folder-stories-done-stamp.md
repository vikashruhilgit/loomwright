# Folder stories done stamp alone — plan doc (index document, not an implementable item)

## Status: done (index document — nothing to implement)

## Why now
GitHub issue vikashruhilgit/loomwright#851: an `/automate --folder` story kept outside `.supervisor/requirements/`
never gets its `## Status: done` stamp after merge, so the next `--folder` run queues merged work again and close-out
raises an `AUT-LEFTOVER` that "Clean up now" cannot clear. Seen twice in the studio-sandbox p14 runs (stories 01 and 02).

## Owner decisions
none recorded

## Order
| Item | Delivers | Depends on | Can run in parallel with |
|---|---|---|---|
| folder-stories-get-their-done-stamp | driver hands the queued path to Launch Pad as the source requirement; close-out stamps the story | none | nothing — one-item doc |

## Run
/automate --backlog .supervisor/requirements/_BACKLOG-2026-11-08-173723-folder-stories-done-stamp.md
Sequential, safe mode, in a fresh session. Validation step 5 (a real `--folder` run in a sandbox repo) happens
outside this repo, after the PR's static checks pass.

## Considered and not queued
- Widening the guarded readers (`brief_requirement_path`, `stamp-requirement-status.sh`, `reconcile-jobs.sh`) to
  accept the run's `## Source` folder — dropped at the Product Owner gate (2026-11-08, "Refine requirements").

## Revisit when
`/automate` gains a single-file intake, or the Launch Pad source-requirement rule changes.

## Checklist
- [ ] .supervisor/requirements/2026-11-08-134816-folder-stories-get-their-done-stamp.md
