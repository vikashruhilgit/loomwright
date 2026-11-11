# Dismissed follow-ups bundle 04a + 04b — dispositions

Every finding was re-checked against the code it cites on base `83a4549`. Each `fixed` line names the leg
that goes red on the base code and green on the fix. Each such leg was proven by running its suite with the
base copy of the fixed script swapped in, then restored. A doc- or comment-only fix carries no leg.

## Part 04a dispositions

- F016 — fixed (test-review-heal-next-step.sh "B: rules gate unresolved after two remembered failures ⇒ remaining_issues counts the unresolved rule only")
- F020 — fixed (test-build-handoff.sh "(r) a '/' in RUN_TITLE_ERE still reads the title")
- F119 — fixed (test-automate-helpers-dispatch.sh "usage mutant (segment group repeated)" and "usage mutant (segment group named like a family")
- F131 — not worth fixing: the label is informational only (escalation_check, and the re-check re-runs validation-gate). An unambiguous split needs the producer's `V<n> <title>: <evidence>` line in automate-lanes.d/readiness.sh to change, and every validation-gate reader and the waiver-line matcher read that line.
- F155 — fixed (test-automate-helpers.sh 16-queue-gates "QG2l park-ask-gate --wait longer than 5 digits" and "QG2m park-ask-gate multi-document gh output")
- F159 — fixed (test-automate-helpers.sh 16-queue-gates "QG1d queue-confirm --lane-backlog … any positional beside it ⇒ usage error")
- F162 — fixed (test-run-pin-mutations.sh "(S) a `\|` in the Pin cell does not split the row there")
- F181 — fixed (test-automate-next-step.d/02-branches.sh "B2'': the superseded drain's close-out reads the closeout seam")
- F182 — not worth fixing: discovering readers needs a grammar for "a ^-anchored ## Progress reader" across the scripts tree. R12's extractor has a hand-written rule per reader, so the fix is a reader registry, which is its own item.
- F183 — fixed (test-only: test-automate-next-step.sh leg_run_idem / R7, "the RUN report re-sent at the rate-limit park" case)
- F261 — fixed (test-automate-next-step.d/08-coordinator-model.sh "CM message: coordinator_model_invalid lists NS_CM_VALUES")
- F302 — fixed (test-read-token-ledger.sh "a real 'run created (session <uuid>, plugin …)' line resolves the engine session")
- F303 — not worth fixing: performance only (output is correct). A cross-item transcript cache keyed by session id restructures per_item_report's extract-then-filter loop.
- F316 — not worth fixing: a test-marker variable can be inherited just like the seams it would guard, so it adds a second env var, not a boundary. Gating would also touch more than a hundred seam-setter lines across the harness, its legs, the goldens and test-read-token-ledger.sh.
- F317 — fixed (test-automate-next-step.d/02-branches.sh "B2': a refused waiver ⇒ escalated park validation_unrun … no write-only sidecar key"; the write-only key was dropped, and the refusal is already on stderr)
- F344 — fixed (test-automate-helpers.sh 18-backlog "BL15 a TERM while backlog-stamp holds the lock ⇒ the lock is removed"); the stale-age-break half is not worth fixing: a shared lock helper extract is its own item
- F345 — fixed (test-automate-helpers.sh 18-backlog "BL14 a merged-PR list as long as the read's --limit ⇒ github unverified")
- F346 — fixed (test-automate-helpers.sh 18-backlog "BL9 refused: a --date that is no calendar day" ×4, plus the BL16 leap-day positive control)
- F014 — fixed (doc/comment only)
- F055 — fixed (test-automate-helpers-dispatch.sh "empty <family>.sh ⇒ the dispatcher exits … naming it")
- F124 — fixed (doc/comment only)
- F195 — fixed (test-review-heal-next-step.sh "B: an off-list rules verdict at the confirming pass reads unreadable")
- F197 — fixed (test-review-heal-next-step.sh "B: a marker-less bot thread is never counted as an unresolved human thread")
- F198 — fixed (test-review-heal-next-step.sh "B: a /job/<digits> URL outside the Actions shape is not read as a check-run id")
- F199 — duplicate of F195
- F208 — not worth fixing: no golden or leg reaches RECONCILE's running-with-owned-drain stop. Writing `## Status: paused` there changes what the next --resume reads for that run and needs its own fixture, so the change was reverted and not shipped without a leg.
- F259 — fixed (doc/comment only)
- F260 — not worth fixing: the window is microseconds and the consequence is one duplicate escalated record (resolution stays session). An owner-token re-check narrows the window but does not close it; closing it needs an atomic rename-and-verify lock protocol, the same shared lock-helper extract as F344's stale break.
- F327 — not reproducible: the draft lives only on the loomwright-meta branch, outside this PR's reach; to fix there before that draft is promoted
- F019 — fixed (doc/comment only)
- F209 — fixed (doc/comment only)
- F306 — not worth fixing: a label and Decide-window nit in an advisory report. A correct fix needs a fix-now-aware window model (the re-drain's own Decide, ending at the re-park or close-out), not a local edit.

## Part 04b dispositions

- F065 — fixed (test-build-capabilities.sh "(P) a redirect written right after an fd duplication (2>&1>f) is a write of f (never [])" and "(P) a newline ends a redirect target (no next-line words glued onto the path)")
- F066 — fixed (doc/comment only)
- F084 — fixed (doc/comment only); the frontmatter note no longer claims to mirror hooks.json. agents/execute-manager.md carries the same claim and is outside this PR's lanes
- F089 — fixed (test-build-vault.sh "run note never projects the unwritten session_end duration_seconds slot")
- F263 — fixed (evals/coordinator-model/lib/selftest.sh "S3: a refused --result (exit N) does not answer the spawn ⇒ SKIPPED: 1"; test-automate-next-step.d/08-coordinator-model.sh "CM resume-elsewhere: a --resume dir outside .supervisor/automate takes the coordinator_model of the git checkout holding it")
- F293 — fixed (test-skills-index-companion.sh "a new item (03-cmd) reserves loomwright/docs/prompt-token-budgets.json" and "a new item (04-skill) …")
- F297 — fixed (test-check-token-budget.sh "case7u ALSO names the empty commands dir")
- F298 — fixed (test-check-token-budget.sh "case7s ERROR says symlink to a non-file, not dangling")
- F366 — fixed (test-module-shape-facts.sh "D6 an indented Python method def is not a definition (column-0 def only)")
- F369 — fixed (test-module-shape-facts.sh "F13 a head branch that moves mid-run ⇒ every fact describes the tree resolved at start")
- F057 — fixed (check-skills-index-sync.sh --self-test "bom-skill-still-checked" and "leading-blank-skill-still-checked")
- F069 — fixed (test-only: test-build-capabilities.sh "(F) the (S) agent predicate accepts a tools-less agent (tools: null is in the documented string[] | null type)")
- F121 — fixed (test-build-capabilities.sh "(HM) a StopFailure failures.log append to a non-literal path => writes [unknown] AND host_mode unknown")
- F248 — not worth fixing: four of the six Critical Rules items already have their own q: rows (LP-235 to LP-238); splitting out the other two needs new ids and a renumbered GAP list, which is more than a local edit
- F278 — fixed (test-check-prompt-history-refs.sh "P11 <queue>/<NN> trailing guard: a path segment followed by / counts 0" and "… a glob after the digits counts 0"; baseline lowered by 4). Queue-shaped examples such as qh/20-x stay counted: their shape is the same as a real reference
- F294 — fixed (test-check-token-budget.sh "case7v an empty-string .skills key exits 1" and "case7v ERROR names the newline-bearing key")
- F295 — fixed (test-check-token-budget.sh "case7t a .md under a commands subdirectory exits 1")
- F367 — fixed (test-module-shape-facts.sh "F12 a failed added-names diff ⇒ exit 0, line facts kept, stderr 'names_unavailable'")
