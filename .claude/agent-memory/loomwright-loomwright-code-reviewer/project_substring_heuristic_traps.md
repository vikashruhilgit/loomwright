---
name: substring-heuristic-traps
description: Verified false-positive classes for review-churn text heuristics (pr-postmortem gather and similar) — "review" matches "preview", unanchored "round N" matches "background 4"
metadata:
  type: project
---

When reviewing churn/review-detection heuristics (pr-postmortem gather, telemetry scoring), test these verified substring traps with jq before approving:

- `test("review";"i")` matches **"preview"** — deploy-preview bots (vercel[bot], netlify[bot]) get counted as review rounds. Require a heading-anchored marker (markdown heading containing "review") instead.
- Unanchored `round[- ]?[0-9]+` matches **"background 4"**, **"playground 2"**, **"workaround 3"**.
- `reconcil` / `\bfindings?\b` / `\bnits?\b` match ordinary feature commits ("reconcile inventory", "audit findings export").

**Why:** PR #49 (iteration 1 of the review_rounds undercount fix) reintroduced exactly the broadened regex that the accepted design (merged as 65a30ba, v14.23.1) had explicitly evaluated and rejected as false-positive-prone; the accepted design instead uses timestamp-anchored bot-comment rounds (commit lands after comment).
**How to apply:** Any diff touching `pr-postmortem-gather.sh` heuristic regexes — verify each new alternation empirically with `jq -n '... | test(...)'` against benign strings, and check the broadening wasn't already rejected in the script header / CLAUDE.md release note.
