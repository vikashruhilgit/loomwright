Close the automate-speed run's still-live dismissed findings
The wave planner now ends a `## Touches` or `## Depends on` section at the close-out sentinel, so a done item whose
last section is one of those no longer reads as unknown and runs alone. `check-token-budget.sh` fails closed on an
unreadable file instead of measuring it as 0. `config-suppress` aborts before the backup on a config that is valid
JSON but not an object, instead of dying in jq with a backup and a stray temp file left behind. `closeout-others`
names an invalid lane marker instead of reporting a lane clone that `lane-info` rejects. The validate-entry and
verify-seam source scans now include `<script>.d/` modules. The setup-memory suite runs its own setup-guard audit
as the (sg) leg, and three unguarded setup calls gain their guard. Prose that had drifted from the code is corrected:
the earned-fallback condition reads a review check's output whatever its conclusion, the postmortem tail is cited at
§"Churn gate", classify-bot-review is cited with `--verbose`, the dispatch env table counts three optional vars, a
bare next-step re-print persists a new session id, execute-manager still preloads context-summarization, and
CLAUDE.md points at the merge-executor surface list in automate-loop §11 instead of restating a stale count.
