# 01 — Prevent findings at write time: worker self-review, touched-file invariants, worker budget, findings metric

## Status: parked — superseded by `.supervisor/requirements/implementation-quality/02-iq01-and-throughput-merged.md` (owner decision 2026-10-09: implementation-quality/01 + throughput/01–09 merged into ONE item / ONE PR; this file is kept as that file's Part source)

## Depends on
none

## Touches
loomwright/agents/worker.md
loomwright/agents/launch-pad.md
loomwright/commands/launch-pad.md
loomwright/agents/plan-reviewer.md
loomwright/skills/supervisor-readiness/SKILL.md
loomwright/skills/quality-checklist/SKILL.md
loomwright/skills/self-heal-advisory/SKILL.md
loomwright/scripts/validate-worker-result.py
loomwright/scripts/build-insights.sh
loomwright/docs/RESULT_SCHEMAS.md
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/docs/prompt-token-budgets.json
changelog.d/implementation-quality-01-prevent-findings-at-write-time.md

## Precondition (owner, 2026-10-09)
Start only after PR #438 (no self-matching waits — edits the same `worker.md` / fix-worker paragraphs and `prompt-token-budgets.json`) and PR #439 (token-ledger identity gate) are merged, so this branches from a `main` that carries both. Not duplicate work: #438 adds a wait rule; this item adds a self-review stage beside it.

## Problem
One `/automate` item (parallel-automate/24, run `automate-2026-10-08-121222`, PR #435) took 5 h 13 m for ~700 changed lines. The PR was READY at 2 h 05 m; the rest went to review-found fixes, each costing a ~45-minute cycle (fix → 11-min `ci-local` → push → 12-min GitHub CI → re-review). The reviews found **14 findings**; **11 of the 14 are classes the Code Reviewer already checks and the Worker is never asked to**:

- `agents/worker.md`'s whole self-check is one line, "Self-review: check for obvious issues". It never mentions the Self-Heal Miss-Class Checklist (`skills/quality-checklist/SKILL.md`, 0 mentions in the worker) and never runs adversarial repros. `agents/code-reviewer.md` has both: the checklist, and §5's scratch-dir adversarial repro of every load-bearing claim (enabled by the Phase 4.5 EXECUTION DIRECTIVE).
- So bugs are DISCOVERED at review (~45 min each) instead of PREVENTED at write time (minutes). Plan + Plan Review + drain do not change what the worker checks.

**The 14 findings (the evidence and the test set):**

| # | Finding (PR #435) | Found by | Class | Preventable by |
|---|---|---|---|---|
| 1 | watermark read outside the per-log lock → concurrent firings double-count (HIGH) | Phase 4.5 iter 1 | adversarial input: concurrent | worker self-review (checklist + repro) |
| 2 | trailing id-less transcript line drops the watermark → resume re-counts (HIGH) | Phase 4.5 iter 1 + claude-review | adversarial input: edge/empty | worker self-review |
| 3 | `agent_id` absent → watermark disabled → repeat stops re-sum | Phase 4.5 iter 3 | adversarial input: missing field | worker self-review |
| 4 | foreign `agent_transcript_path` summed → tokens booked to the wrong agent | claude-review @783b00b | adversarial input: invalid | worker self-review + touched-file invariants (the file already had the identity check) |
| 5 | `desktop: sent` inferred from an audit line written on every host | Phase 4.5 iter 1 | mirror a producer's rules exactly | touched-file invariants (notify-desktop.sh dispatch conditions) |
| 6 | Darwin `CLICK_ACTION` condition not mirrored (introduced by the fix for #5) | claude-review @842cbe7 | mirror a producer's rules exactly | same |
| 7 | `commands/insights.md` still called the proxy "the expected path" | Phase 4.5 iter 1 | restated-claim drift | worker sweep: grep old wording repo-wide |
| 8 | `read-token-ledger.sh` pointer named a place that no longer states the limit | Phase 4.5 iter 1 | cross-reference precision | worker sweep |
| 9 | TELEMETRY.md "sum once whatever their ts" overclaim | Phase 4.5 iter 2 | claim no check backs | worker sweep |
| 10 | atexit comment overclaims on signal death | Phase 4.5 iter 2 | claim no check backs | worker sweep |
| 11 | lock timeout / stale-break branches untested | Phase 4.5 iter 2 | branch coverage | worker self-review (checklist) |
| 12 | full-log scan per stop; the file already had an O(1)-tail convention | claude-review @77fc06b | ignored the file's own convention | touched-file invariants |
| 13 | `loomwright:worker` SubagentStop matcher never ran the ledger | Phase 4.5 iter 1 (pre-existing) | plan gap | touched-file invariants ("which callers / matchers fire this?") |
| 14 | `case24e` deviation labelled `code wrong` instead of `assertion wrong` | Phase 4.5 iter 2 | process | worker self-review (`test:` deviation rule) |

Also measured: the worker hit its `maxTurns: 40` limit and had to be resumed, so a self-review stage needs turn budget.

## Goal
A non-trivial item reaches Phase 4.5 PASS on its **first** review iteration, and the CI `claude-review` reports "no new findings", because the worker already applied the reviewer's lens to its own diff and the brief told it the invariants it must keep. Findings-per-item is measured so the effect is visible.

## Scope (one item, one PR — owner decision 2026-10-09: "do 1 to 4 in one go")
1. **Worker pre-hand-back self-review (`agents/worker.md`).** Before emitting `WORKER_RESULT`, the worker MUST: (a) apply the Self-Heal Miss-Class Checklist (`skills/quality-checklist/SKILL.md` — reference it, do not restate it) to its own diff; (b) run a scratch-dir adversarial repro of each load-bearing claim it introduced, following the SAME procedure as `agents/code-reviewer.md` §5 (reference, do not copy — one procedure, two callers; the worker may write inside the checkout, the repro still runs in a `mktemp -d` dir with `HOME` relocated); (c) for every claim, count, or behaviour it changed, grep the repo for the OLD wording and update or point every restated copy; (d) re-read each `## Touched-file invariants` entry of the brief (item 2) and confirm it holds. It records the result in a new `WORKER_RESULT` field (e.g. `self_review: [{class|claim, result: held|fixed|n/a, evidence}]`), and a worker result without it is incomplete — enforced by `validate-worker-result.py` the same way an absent required field is today (check `docs/HOOKS.md` §"Command-validator decision shape" for the documented block shape). Add a "reuse the file's own conventions and guards" class to the checklist (finding 12's class), so both lenses check it.
2. **Touched-file invariants in the brief (Launch Pad + plan).** Launch Pad Phase 3 adds a `## Touched-file invariants` section: for each file the change MODIFIES, the existing guards/conventions/fail-safe rules in it that the change must keep or reuse (e.g. "emit-token-ledger.sh: always exit 0; agent_scope identity check; O(1) tail reads"), and every producer/consumer contract the change must mirror exactly (e.g. "lane-park-notify desktop status must match notify-desktop.sh's dispatch conditions"), and for any hook/emitter change, which matchers/callers fire it. Template in `skills/supervisor-readiness/SKILL.md`; Plan Reviewer gains a conditional criterion that the section exists and its entries are grounded (file:anchor) when the brief modifies existing scripts. Keep `commands/launch-pad.md`'s mirrored text in sync (agent↔command mirror).
3. **Worker turn budget.** Raise the worker's `maxTurns` (measure: what the pa/24 worker needed) so the self-review stage is not the first thing dropped at the limit, and declare the larger prompt in `docs/prompt-token-budgets.json` + the `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" mirror (check-token-budget fails CI closed otherwise).
4. **Findings-per-item metric.** Record, per Supervisor run, the first Phase 4.5 iteration's decision and the total `new` findings across iterations (additive fields on `SUPERVISOR_RESULT` and the flat `session_end` line, `schema_version` unchanged), and surface "first-pass PASS rate" and "findings per item" in `/insights` (`build-insights.sh`), next to the existing `heal_iterations` aggregate.

## Acceptance criteria
- `agents/worker.md` requires the four-part self-review before `WORKER_RESULT`, referencing (not restating) the checklist and code-reviewer §5; `WORKER_RESULT` carries the new field; `validate-worker-result.py` blocks a result without it (documented decision shape), with a test that fails before the change.
- The checklist gains the "reuse the file's own conventions and guards" class.
- A brief for a change that modifies existing scripts carries `## Touched-file invariants` with grounded entries; Plan Reviewer flags its absence; the template and the Launch Pad agent/command mirror agree.
- Worker `maxTurns` is raised with a measured justification; token budgets declared and `check-token-budget.sh` green.
- `SUPERVISOR_RESULT` / `session_end` carry the first-iteration decision and findings count; `/insights` shows first-pass PASS rate and findings per item; a fixture test covers both.
- **Replay check (the headline):** re-run the self-review procedure (as a worker would) against the pre-review commit of PR #435 (`87f2205`) in a scratch clone and record, per finding in the table above, whether the new stage catches it. Target: ≥ 9 of the 11 worker-preventable findings (rows 1–12 except 13's plan part) caught before review. Paste the per-row result in the PR body; honest misses are listed, not hidden.
- `bash scripts/ci-local.sh` green; the sequential and parallel `/automate` paths otherwise unchanged.

## Validation (must pass before merge)
1. `bash scripts/ci-local.sh` green.
2. New tests fail on the base commit and pass on the branch (validator field, insights fields, plan-reviewer criterion where testable).
3. The replay check above, pasted in the PR body.
4. The next real `/automate` item after merge: record its first Phase 4.5 verdict and findings count (operator follow-up; the success signal, not a merge gate).

## Non-goals
- Changing the drain's validate-then-fix rule or adding a post-READY "drop LOW nits" stop rule — a separate owner decision.
- `ci-local` fail-fast / `--affected` inner loop / scripting the per-item loop (the throughput findings) — separate items; this one reduces how many cycles happen, not what a cycle costs.
