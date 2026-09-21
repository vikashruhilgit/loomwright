# North Star: what "better" means for this harness

The harness exists to turn a goal into **merged, correct software with as
little human attention as possible**. Every metric below is judged by how
well it approximates that. Vanity metrics (runs completed, PRs opened,
green advisory checks, rubric N/N) are explicitly not the goal.

## The metric that matters

**Unattended-quality rate:** of runs launched, the fraction whose PR a
human merged **without needing a substantive correction** (no
human-authored change request, no post-merge fix commit within the
follow-up window, no revert).

Decompose it as a funnel — each stage is measurable from data the harness
already emits or can emit:

| Stage | Metric | Source |
|---|---|---|
| 1. Landed | PR merged (not parked/abandoned) | `gh pr view state`, automate run files |
| 2. Clean | merged with 0 human change-requests | `reviewDecision`, review threads (pr-postmortem gather) |
| 3. Durable | no fix/revert touching the same files within 14 days | `git log --follow` on the PR's file set |
| 4. Cheap | tokens + human-interaction count per merged PR | session logs, `AskUserQuestion` events |

"Better" = stages 1–3 rise (or hold) while stage 4 falls. Any change that
improves an internal score (heal PASS rate, rubric score, reviewer
finding count) without moving this funnel is proxy drift, not progress.

## Known proxies and their failure modes

These are the internal signals the harness produces. They are useful for
diagnosis but must never be optimized directly:

- **`heal_decision: PASS`** — self-graded by the plugin's own reviewer.
  Optimizing it selects for changes the reviewer can't object to, not
  changes that work.
- **`rubric_score: N/M`** — in auto-authored-rubric mode the same run
  writes the rubric and grades its own diff against it; the grader is
  forbidden from checking behavior. N/N is nearly tautological.
- **Reviewer finding count → 0** — the drain loop can zero this out with
  cosmetic micro-commits (see `eval-corpus/review-churn-canary`).
- **QA gate pass count** — the QA Executor self-checks text-shaped gates
  on tests it wrote and edits until green.
- **Telemetry score** — a deterministic function of the graded agent's
  own self-reported result block.

## Regression checks (mechanized)

- `eval-corpus/parity-emit-block` — hook-required fields must be key
  lines inside the actual emit templates (closes the parity gate's
  documented prose-mention blind spot).
- `eval-corpus/review-churn-canary` — flags ≥3 consecutive ≤6-line
  review-drain commits (the churn signature).
- Existing CI hard gates (version/doc/parity/self-tests) protect the
  substrate; they say nothing about outcome quality — do not read a green
  CI as "the harness got better."

## What to build next (data before gates)

The funnel above needs accumulated run data; today `.supervisor/logs/`
and `postmortem/results.jsonl` are effectively empty and never read back.
Priority order:

1. Actually run `/pr-postmortem` on every merged PR (the dispatch hook
   exists) and keep the JSONL.
2. Add a weekly read-back: funnel stages 1–4 per plugin version, from
   postmortem + session logs (`/insights` is the natural home).
3. Only after ~30 merged-PR data points, consider flipping any advisory
   signal to gating (the deferred M3 milestone) — and only signals whose
   catch-rate the data supports.
