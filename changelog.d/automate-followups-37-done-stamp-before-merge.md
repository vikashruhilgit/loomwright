<!-- bump: minor -->
A requirement's `## Status: done` is written only by the post-merge closeout (automate-followups/37)
Supervisor Phase 4.5's completion tail no longer stamps the originating requirement: step 2.5 of
`skills/self-heal-advisory/SKILL.md` ("Requirement close-out") now writes nothing to it, records the
heal verdict only on the brief's `## Outcome` block (and the run file), and defers the done stamp to
`automate-helpers.sh closeout`, which stamps only after its evidence gate reads the PR `MERGED`; the
closeout `printf` bytes are unchanged and are now the block's one byte-shape authority. Before this, the
tail stamped the requirement while the PR was still OPEN (pa/05 Validation 4, finding F7), and a
whole-lane `meta-sync.sh push` carried done claims for never-merged work. Honest limit: a plain
`/supervisor` / `/autonomous` run outside `/automate` gets no automatic done stamp (it reads
`brief-shipped`) until a human runs `reconcile-status --apply`, or `/automate --resume` / the merge
watcher closes it out. Caveat: `reconcile-status --apply` promotes only a `pending`/status-less
requirement; one `stamp-requirement-status.sh` (run on session start and when a Supervisor runner finishes) already marked
`brief-shipped` is listed as an `info` row and needs a hand-written `## Status: done` (or the
`closeout` above, whose sentinel-keyed guard appends regardless of that heading); promoting it in
`reconcile-status` is an open follow-up. `test-automate-trail.sh` gains leg DS (OPEN ⇒ requirement byte-identical,
MERGED ⇒ exactly one closeout-shaped block, plus a contract check on the skill), and
`test-reconcile-jobs.sh` leg 11 now extracts its done headings from the live writers' `printf` formats.
`ground-truth-json.md`, `PITFALLS.md`, `ARCHITECTURE_CONTRACTS.md` and the `automate-loop` skill
describe the pre-merge stamp as history.
