<!-- bump: patch -->
Close the dismissed follow-up test-coverage gaps and test-harness defects (dismissed-followups 05)
The `/automate` drains had dismissed a set of test-side findings as follow-ups and never tracked them. Each one was
re-verified on the base commit, then fixed with a regression leg that goes red on the pre-fix code, corrected in a
header, or recorded as not reproducible or not worth fixing. Every disposition is a row in the `## Dispositions`
table of one of the five `docs/evidence/dismissed-05-*.md` files. Examples from the trail, meta-sync and lanes
suites: `test-automate-lanes.sh` now unsets an ambient `LOOMWRIGHT_PHASE_DIR` and `LOOMWRIGHT_RUN_LOCK_SESSION_ID` at
suite top (run from inside a live phase session, its relay legs wrote into that session's real phase inbox; leg AN0b
pins the line); meta-sync gains legs for a mode reader that exits 0 printing nothing and for a FIFO or dangling
symlink at `<gitdir>/meta-base`; closeout gains DS4 (a `## Status: brief-shipped` requirement keeps that heading
and gets the done block below it); and the trail suite's §SW pin-mutation list is regenerated from its
`sw_mutant` calls. Production scripts are unchanged.
