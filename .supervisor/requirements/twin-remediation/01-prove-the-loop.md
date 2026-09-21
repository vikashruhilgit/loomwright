# 01 — Prove the loop (Bet 5): first real before/after measurement

## Problem
The north star's success criterion is "does the loop demonstrably make work better." No measurement has ever run: Langfuse A/B deferred, eval harness deferred, FABLE_PARITY_EVAL never executed. Meanwhile the churn ledger (v14.36.0), postmortem JSONL (`.supervisor/postmortem/results.jsonl`), token ledger, and session logs have been silently accumulating exactly the data a first measurement needs. A learning loop that can't show it's learning is ceremony.

## Goal
Ship a **read-only measurement report + a repeatable `/insights` section** that answers, from data already on disk: *did review churn per PR go down after each advisory surface shipped?*

## Scope
1. New script `loomwright/scripts/build-loop-evidence.sh` (fail-safe, always exit 0, read-only): joins postmortem results.jsonl + churn ledger + token_ledger lines + PR merge dates, buckets PRs by which advisory surfaces existed at run time (rules seams v15.1.0, memos v15.12.0, bridge, etc.), and emits per-bucket: review rounds/PR, heal iterations, fix_cycles, root-cause class mix, advisory tokens spent.
2. Wire the output as a new `## Loop evidence` section in `/insights` (read-only dashboard, matches existing sections' conventions).
3. A one-page written verdict in `loomwright/docs/SPIKES/LOOP_EVIDENCE_2026-07.md`: per surface — SUPPORTED / NOT SUPPORTED / INSUFFICIENT DATA, with n. Honest nulls required: small n and confounds (model upgrades, task mix) must be stated, not smoothed over. If a surface shows no effect, say so — that feeds item 02's decay/cut path.

## Amendment (2026-07-21 — third-audit reconciliation)
1. **Outcome metric = the unattended-quality funnel** (landed → clean → durable → cheap; "durable" = no revert or follow-up fix touching the same files within ~14 days, from git history). Churn/heal/rubric numbers are reported AS proxies against this funnel, not as outcomes. Port and adapt the draft `NORTH_STAR.md` funnel definition from the uncommitted worktree `../loomwright-pr95-review/loomwright/docs/NORTH_STAR.md` (salvage before that worktree is cleaned; review, don't rubber-stamp — it was authored against a worktree missing gitignored state and contains at least one false premise about empty logs).
2. **Treat self-graded signals as untrusted:** rubric N/M where the rubric was auto-authored by the same run (Launch Pad → rubric-grader tautology) must be bucketed separately from human-approved rubrics in the analysis.
3. **Port the two working eval checks** from that worktree's `loomwright/scripts/eval-corpus/`: `parity-emit-block` (mutation-tested emit-template field check) and `review-churn-canary` (≥3 consecutive ≤6-line drain commits — already a true positive on real history). Re-verify both here (mutation test + true-positive replay) before wiring into `run-eval.sh`.

4. **Known data-quality trap (do not skip):** GitHub review-round counts are FALSE ZEROS for PRs whose review happened inside the `--until-mergeable` drain (rounds never reach GitHub — see the postmortem-false-zero lesson). The "clean" funnel stage must therefore combine GitHub rounds with drain-internal signals (`fix_cycles`, heal_iterations, drain-cycle commits per the churn canary) — a PR with 0 GitHub rounds and 5 drain cycles is NOT clean.

## Non-goals
No Langfuse, no new emitters, no new data collection, no gating. This is analysis of existing artifacts only.

## Acceptance criteria
- Script runs on this repo's real `.supervisor/` data and produces the bucketed table (verified in the PR description with actual output).
- Missing/partial data degrades to labeled `insufficient_data`, never invented numbers (the token-ledger "never invents tokens" rule applies).
- `/insights` renders the section; absent data ⇒ section says so and dashboard still builds.
- Doc-currency, skills-index, token-budget CI gates green.

## Outcomes Rubric
- Bucketed churn-per-PR table produced from real repo data
- Explicit SUPPORTED/NOT SUPPORTED/INSUFFICIENT verdict per advisory surface
- Zero new write-side surfaces introduced

## Status: done
- Completed 2026-07-21 via /supervisor job (PR #105, heal PASS, rubric 6/6 self_graded)
