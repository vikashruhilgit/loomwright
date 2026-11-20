# Closeout's done stamp also updates the requirement's heading `## Status:` line

## Status: proposed

> Propose-only. Raised 2026-11-02 when the owner read the four requirements closed out by runs
> `automate-2026-11-01-195532` and `automate-2026-11-02-071559` as still pending. Not enqueued.

## Problem (read 2026-11-02 against `main` at `38eb8e4`)
`closeout` (`loomwright/scripts/automate-trail.d/closeout.sh`, the step that `printf`s the
`<!-- loomwright:requirement-closeout -->` block) appends its stamp to the END of the requirement file:

```
<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** <ts>
```

It never touches the heading line, so the file opens with `## Status: pending` and ends with `## Status: done`.
`loomwright/scripts/test-automate-trail.sh`'s DS2 leg pins that shape ("the pending bytes + the closeout printf
block, byte for byte").

The plugin's readers handle it. `is_done` (`loomwright/scripts/automate-helpers.sh`) matches any `## Status: done`
line, and `/backlog`'s `item-state` reads the closeout block. But a person opening the file, a plain
`grep -m1 '^## Status'`, an editor outline, or any reader outside the plugin sees `pending`. All four items above
were done (merged PRs #781, #783, #785, #788; stamps dated `2026-11-02T08:52:30Z`) yet read pending to the owner.
This is the same symptom recorded earlier, when many shipped items read `pending`.

## Invariants to keep
- The closeout block stays: the sentinel is what `closeout`'s "already stamped" check and `/backlog` read, and it
  carries Completed / Brief / PR as evidence.
- Only `closeout`, behind its merge-evidence gate, writes the done stamp; nothing else promotes a requirement.
- `is_not_ready` (heading `proposed|parked`) and `/backlog`'s first-status-line rules (the `brief_shipped` / explicit
  `pending|ready` conflict detection in `automate-helpers.d/backlog.sh`) must keep their meaning. Check every
  first-line reader before changing what the first line says.
- Idempotent: a second closeout changes nothing.

## Suggested direction
1. In the same write as the appended block, rewrite the FIRST `## Status:` line to
   `## Status: done (closeout <ts>, PR <url>)`, or to plain `## Status: done` if the shorter form keeps readers'
   regexes simpler. Same atomic temp-and-rename discipline as the run-file writers.
2. Update DS2 to pin the new shape. Add legs proving: an already-stamped file is untouched, a `proposed`/`parked`
   heading is never rewritten (closeout should not reach those, but assert it), and the backlog conflict detector
   still behaves.
3. Optional, owner-run only: a one-time `reconcile-status`-style pass that rewrites the heading of items already
   carrying a closeout block. It reports first and applies only with an explicit `--apply`, never unattended.

## Tests
- DS2 rewritten for the new shape.
- First-line readers (`is_not_ready`, the backlog conflict rule) re-run against a stamped fixture.
- Mutation control: skip the heading rewrite ⇒ the heading leg turns red.

## Likely touches
`loomwright/scripts/automate-trail.d/closeout.sh`, `loomwright/scripts/test-automate-trail.sh` (and its
`test-automate-trail.d/` parts), `loomwright/scripts/automate-helpers.d/backlog.sh` (only if a first-line rule needs
it), `loomwright/skills/automate-loop/per-item-loop.md` (the closeout description)
