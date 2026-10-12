<!-- bump: minor -->
One requirement shape and one plan-doc template; Product Owner writes the plan doc for a story set
`skills/user-story-writing/SKILL.md` (1.3.0) gains §"Requirement Shape": a shape decision made before any file is
written (one item that fits one PR, one item with Parts, or a set of items plus a plan doc), item rules (every item
self-contained; repeated-run or timing criteria go under `## Measurements` against a frozen commit, never inside a
worker's turn budget; new findings join an existing theme's plan doc instead of a new `*-followups` folder), and a
`_BACKLOG.md` plan-doc template whose `## Status: done` stamp keeps `/automate --folder` from enqueuing it and whose
checklist `/automate --backlog` reads in order. INVEST "Small" now means "fits one PR", not "one finding". Product
Owner (agent and command mirror) applies the shape decision and, when it persists 2 or more stories, also writes
`.supervisor/requirements/_BACKLOG-{YYYY-MM-DD-HHMMSS}-{slug}.md` from the template. `skills/automate-loop/intake.md`
and `commands/automate.md` claimed PO already wrote an optional `_BACKLOG.md`, which it never did; both now describe
the plan doc PO writes and state that it is never a Queue item. New `test-requirement-shape.sh` extracts the template
from the skill and checks its sections, that `resolve-folder` skips it and `resolve-backlog` reads its checklist in
order, and that PO's prior-stories glob does not match the plan doc, with mutation controls for the status stamp and
the section list (parallel-automate/18 Part C, without C5).
