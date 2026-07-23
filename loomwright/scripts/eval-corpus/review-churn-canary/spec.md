# Task: review-churn-canary

## What this task asks

The review→fix→re-review drain must not degenerate into cosmetic churn:
long runs of tiny commits produced solely to zero out the reviewer's own
finding count (the Goodhart failure mode where "reviewer finds nothing
new" is optimized instead of "the change is correct").

The canary's signature: **3 or more consecutive** commits (within a
15-commit window on HEAD) that both

1. have a subject matching the drain vocabulary (`drain round`,
   `drain cycle`, `address review`, `review follow-up`, `bot-review`,
   `heal iter`, `heal residual` — case-insensitive), and
2. change **≤ 6 total lines** (insertions + deletions via
   `git show --numstat`, binary files counted as 1).

Three consecutive micro-fix rounds means the loop spent three model
round-trips on nits — either the reviewer's finding bar is too low, or
the fix worker is manufacturing diffs to satisfy it.

## Eval mode is fixture-based (deliberate design choice)

This repo's real history contains a **known historical true positive**
(the PR #103 drain: `c816684` → `498d1e5`, five consecutive
drain/heal-subject commits of 18/3/31/11/6 lines). Scoring live history
in the eval would turn that historical event into a **permanently red
eval task** — a dead signal nobody can fix without rewriting history.

So the eval task asserts the canary **mechanism** instead: `check.sh`
(no args, as run by `run-eval.sh` after `cd <task-dir>`) builds two
hermetic throwaway git repos in a temp dir (pinned git config; no
dependence on the enclosing repo or the user's `~/.gitconfig`):

- **churn fixture** — seed + exactly 3 consecutive micro drain commits
  (2, 3, and boundary 6 lines): scanner must report max streak
  **exactly 3** (canary fires);
- **boundary/clean fixture** — a >6-line drain-subject commit, a tiny
  non-drain commit, then only a 2-streak of micro drain commits:
  scanner must report max streak **exactly 2** (canary stays silent).

Exit 0 iff both assertions hold. Deterministic (fixture content and the
pass/fail decision are fully pinned; commit timestamps vary but are
never read) and side-effect-free outside the temp dir.

## `--live` mode (advisory diagnostic, not scored by the eval)

`bash check.sh --live [--window N] [--max-lines N] [--streak N]` scans
the enclosing repo's real history and exits 1 when a qualifying streak
is found. Defaults: window 15, max-lines 6, streak 3. Non-numeric knob
values fail closed (exit 2).

True-positive replay against this repo (as of `eedd3ac`): with the
strict default `--max-lines 6` the five drain commits are recognized by
subject but only `498d1e5` (6 lines) passes the micro filter — max
streak 1, no fire ("small-fix churn", not "pure-nit churn"). With
`--live --max-lines 35` the canary fires with a **streak of 5** on
exactly those commits. The knob exists so operators can tune the
micro-commit definition without editing the check.
