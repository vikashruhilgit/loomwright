Dismissed follow-ups 04a+04b: driver and gate tooling fixes
This release closes out 50 review findings that were dismissed as follow-ups. Each one is fixed with a regression leg that fails on the old code, or recorded with a reason in docs/evidence/dismissed-followups-12-bundle-04ab.md.
In the review-heal driver, one allow-list now checks the rules verdict and an off-list verdict reads unreadable. remaining_issues is counted per branch. Only a human-authored thread counts as a human thread, and a check-run id is read only from an Actions job URL.
In the next-step driver, the superseded close-out reads the closeout seam. The invalid coordinator_model message is built from NS_CM_VALUES, and the write-only waive_refusal key is gone.
automate-helpers refuses a repeated usage group and an empty family file. park-ask-gate, queue-confirm and backlog-stamp are tighter: a lock trap, a truncated merged-PR list reads unverified, and --date must be a real calendar day.
The token ledger reads the real run-created line. Handoff strips a title that contains a slash, and the pin runner accepts an escaped pipe in a Pin cell.
build-capabilities.sh reads a redirect written right after an fd duplication and ends a target at a newline. A non-literal failures.log append makes host_mode unknown, and check (S) accepts an agent with no tools key.
check-token-budget.sh reports every empty dir before it exits. It names a command-doc symlink to a directory as such, and fails closed on a .md in a commands subdirectory and on an empty or newline-bearing budget key.
check-skills-index-sync.sh still checks a SKILL.md that starts with a BOM or blank lines. The history-refs <queue>/<NN> pattern no longer counts a path segment or a glob, and its baseline is lowered.
module-shape-facts.sh resolves head once for every git read. It reports a failed added-names diff as names_unavailable and reads a Python def only at column 0.
The coordinator-model eval counts an ask or spawn as answered only when the driver accepted the later --result. build-vault.sh no longer reads the duration_seconds slot that nothing writes. New commands and skills reserve prompt-token-budgets.json in the companion table.
