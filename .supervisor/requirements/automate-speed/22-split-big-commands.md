# automate-speed/22 — Split the three biggest command docs by sub-command, loaded on demand

## Status: pending

## Problem
`loomwright/commands/dreaming.md` is 138KB, `commands/setup.md` 94KB and `commands/agent-help.md` 84KB (plan doc
§Why now). Each is read whole whenever the command runs, although one invocation uses one sub-command or one section
(for example `/setup memory` reads all of `/setup`). They are not on the per-item `/automate` path, so this saves tokens
only when those commands run; the larger benefit is maintenance (owner, 2026-10-15).

## Goal
<!-- bump: minor -->
Each of the three command docs becomes a short router: shared rules plus "for sub-command X, read <part>". The
sub-command bodies live in part files read only when that sub-command runs.

## Scope
- Part files live under `loomwright/docs/command-parts/<command>/`, NOT under `commands/` (a subdirectory there would
  register as namespaced commands and change the command count) and not as new skills (would change the skill count).
- Runtime reads use `${CLAUDE_PLUGIN_ROOT}/docs/command-parts/...`.
- `commands/agent-help.md` keeps its description of the sanctioned `--auto-merge` gate in the router file itself, so
  the CLAUDE.md `gh pr merge --squash` surface enumeration stays true without edits.
- Each part file gets an `.commands` ceiling entry only if item 17 has landed (it then covers the router; parts are
  counted under the command's entry).

## Invariants
- `scripts/check-command-sync.sh`, `check-doc-currency.sh` (command and skill counts unchanged) and
  `check-skills-index-sync.sh` pass.
- Headings that a gate or another doc cites are interfaces (house rule, advisory): moved headings keep their text, and
  every citation is updated in the same change.

## Non-goals
- Changing what any sub-command does.

## Owner decisions (from _BACKLOG.md)
- D6: move-only.

## Acceptance criteria
- Given `/setup memory`, then only the router and the memory part are read (asserted from a transcript in the
  running-system step).
- Each router file is under 20KB; the sum of router + parts is no larger than the original file.
- The CLAUDE.md invariant grep output is identical before and after.

## Validation (must pass before merge)
1. `scripts/check-command-sync.sh`, `check-doc-currency.sh`, `check-skills-index-sync.sh`, `test-citation-drift.sh`;
   report `<passed>/<total>`.
2. Running system: run `/loomwright:setup` (status) and `/loomwright:agent-help`; paste the first lines of each.

## Depends on
none

## Touches
loomwright/commands/dreaming.md
loomwright/commands/setup.md
loomwright/commands/agent-help.md
loomwright/docs/command-parts/
changelog.d/as22-split-big-commands.md
