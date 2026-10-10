<!-- bump: minor -->
A requirement's `## Status: done` is written only by the post-merge closeout (automate-followups/37)
Supervisor Phase 4.5's completion tail no longer stamps the originating requirement: step 2.5 of
`skills/self-heal-advisory/SKILL.md` ("Requirement close-out") now writes nothing to it, records the heal
verdict only on the brief's `## Outcome` block (and the run file), and defers the done stamp to
`automate-helpers.sh closeout`, which stamps only after its evidence gate reads the PR `MERGED`; the
closeout `printf` bytes are unchanged and are now the block's one byte-shape authority. Before this, the
tail stamped the requirement while the PR was still OPEN (pa/05 Validation 4, finding F7), and a
whole-lane `meta-sync.sh push` carried done claims for never-merged work. Honest limit: two paths get no
automatic done stamp, a plain `/supervisor` / `/autonomous` run outside `/automate` and an `/automate
--auto-merge` item that `gate-eval` merged. `closeout`'s callers are `/automate --resume`'s RECONCILE
(this run's `## Current` item), the merge watcher (armed only at an `/automate` park) and
`closeout-others` (another run's `## Current` item), so it reaches a requirement only when that is the `##
Current` item of an `/automate` run whose PR merged after a park (for other requirements `/automate
--resume` runs `reconcile-status` as a dry run only). A gate-merged item never parks: the `automate-loop`
§6 step 5 SYNC runs `brief-repair` and the pull, not `closeout`, because `closeout`'s trail PR would make
the next PICK's `trail-gate` park `trail_pr_open` after every merge; before this change Phase 4.5's
pre-merge stamp covered that item, and a trail-less close-out at SYNC is an open follow-up. For both
paths, recovery after the merge is a human step: `reconcile-status --apply`, which promotes any not-done
requirement on merged-PR evidence EXCEPT one `stamp-requirement-status.sh` (run on session start and when
a Supervisor runner finishes) already marked `brief-shipped` — that one is listed as an `info` row and
needs a hand-written `## Status: done`. Until then `resolve-folder` keeps listing the merged item.
Promoting a merged `brief-shipped` requirement in `reconcile-status` is an open follow-up.
`test-automate-trail.sh` gains leg DS (OPEN ⇒ requirement byte-identical, MERGED ⇒ exactly one
closeout-shaped block, plus a contract check on the skill), and `test-reconcile-jobs.sh` leg 11 now
extracts its done headings from the live writers' `printf` formats. `ground-truth-json.md`, `PITFALLS.md`,
`ARCHITECTURE_CONTRACTS.md` and the `automate-loop` skill describe the pre-merge stamp as history.
