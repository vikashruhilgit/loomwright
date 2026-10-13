# reconcile-status stamps a requirement done from a PR that shipped only part of it

## Status: proposed

> Propose-only, filed 2026-10-13 from the af/36 remainder pass. Not enqueued; a human promotes it by moving it out of
> `proposed/`. Reproduced on main 508aabc.

## Problem
`automate-helpers.sh reconcile-status <root> --apply` stamps a requirement `done` when a MERGED PR's body cites the
file on an implements-shaped line (`_rs_implements_cites` in `automate-helpers.d/reconcile-status.sh`). The match
only asks that the line OPENS with an implements verb and names the path in its first clause. It never asks
whether the PR implements the WHOLE requirement, so a partial-delivery line counts as completion:

- **Reproduction:** PR #489's body opens `Implements item 1 of .supervisor/requirements/twin-remediation/09-native-flow-adoption.md
  (refresh the stale capability baseline)`. The dry run planned, and `--apply` wrote,
  `## Status: done (PR #489, merge 726831b)`. Yet the requirement's own Re-scope note reads "Remaining: items 2–5 (refine
  first) … Requirement stays open." Pushed, the stamp would have dropped four queued items from every later intake
  (`is_done` matches the appended heading anywhere in the file).
- **Second defect, same run:** `_rs_strip_trailing_status` removes only a BARE `## Status: pending` line. tr/09's
  line was annotated (`## Status: pending (verified still open 2026-10-05: …)`), so it survived, and the stamped
  file carried both `pending` (line 3) and `done` (appended). The status a reader sees depends on which line it reads.

The stamp was caught by reading the file and reverted by hand. tr/09 is now `parked`.

## Scope
1. Treat a partial-delivery citation as no evidence: an implements line whose first clause scopes the citation to
   part of the requirement (`item N of`, `items N–M of`, `part of`, `step N of`, `phase N of`, and similar) gets no
   body-citation credit. Missing a stamp is the recoverable direction, as the script's own header already argues.
2. Optionally, refuse to stamp a file whose body states it stays open (`Requirement stays open`, `Remaining:`).
   Emit an `info` row naming the conflict instead.
3. Make the stale-line strip match an annotated `## Status: pending (…)` as well as the bare form, so a stamped
   file never carries two contradictory status headings.

## Acceptance
- A fixture PR body `Implements item 1 of <req>` against a merged PR yields NO `plan` row for `<req>`.
  `Implements <req>` still yields one. Each leg goes red when its guard is removed (mutation control).
- A fixture requirement with an annotated `## Status: pending (…)` line, once stamped, carries exactly one
  `## Status:` heading.
- Existing `test-automate-helpers.sh` reconcile-status legs unchanged and green.
