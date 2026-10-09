# 02 — Merged item: implementation-quality/01 + throughput/01–09 in ONE PR (prevent findings at write time, and make each review cycle cheaper)

## Status: pending

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
loomwright/scripts/drain-subfloor-decision.sh
loomwright/scripts/test-drain-subfloor-decision.sh
loomwright/skills/review-heal/SKILL.md
loomwright/agents/review-pr.md
loomwright/commands/review-pr.md
loomwright/docs/result-schemas/review-heal-result.md
loomwright/scripts/automate-dismissed.sh
loomwright/scripts/automate-helpers.sh
loomwright/scripts/fixtures/automate-helpers-help.golden
loomwright/scripts/test-automate-dismissed.sh
loomwright/skills/automate-loop/SKILL.md
loomwright/commands/automate.md
loomwright/docs/result-schemas/automate-run.md
loomwright/scripts/wait-for-checks.sh
loomwright/scripts/test-wait-for-checks.sh
loomwright/docs/PITFALLS.md
loomwright/scripts/retention-sweep.sh
loomwright/scripts/test-retention-sweep.sh
loomwright/scripts/phase-timing.sh
loomwright/scripts/test-phase-timing.sh
loomwright/scripts/fixtures/phase-timing/
loomwright/scripts/emit-lifecycle.sh
loomwright/scripts/test-emit-lifecycle.sh
loomwright/scripts/hook-dispatch-on-pr-create.sh
loomwright/scripts/test-hook-dispatch-on-pr-create.sh
loomwright/scripts/automate-trail.sh
loomwright/scripts/test-automate-trail.sh
loomwright/scripts/test-insights.sh
loomwright/commands/insights.md
loomwright/hooks/hooks.json
loomwright/docs/HOOKS.md
loomwright/docs/result-schemas/session-end-jsonl.md
loomwright/docs/result-schemas/agent-lifecycle-jsonl.md
loomwright/docs/vendor-coupling-manifest.json
scripts/ci-local.sh
scripts/test-ci-local.sh
loomwright/scripts/run-self-tests.sh
loomwright/scripts/test-run-self-tests.sh
loomwright/scripts/test-automate-helpers-dispatch.sh
loomwright/scripts/test-citation-drift.sh
AGENT_GUIDELINES.md
loomwright/scripts/test-ci-slot.sh
loomwright/scripts/test-build-floor.sh
loomwright/scripts/test-harvest-conventions.sh
loomwright/scripts/test-automate-trail-closeout.sh
loomwright/scripts/test-automate-trail-merge-watch.sh
.github/workflows/ci.yml
loomwright/scripts/test-automate-lanes.sh
loomwright/scripts/test-setup-ui.sh
loomwright/scripts/wait-lib.sh
loomwright/scripts/test-wait-lib.sh
loomwright/scripts/test-no-fixed-sleep-race.sh
loomwright/scripts/fixtures/self-test-weights.tsv
scripts/check-vendor-coupling.sh
scripts/test-check-vendor-coupling.sh
loomwright/agents/execute-manager.md
loomwright/agents/code-reviewer.md
loomwright/agents/supervisor.md
loomwright/docs/POINTER_AUDIT.md
loomwright/docs/result-schemas/worker-result.md
loomwright/docs/result-schemas/supervisor-result.md
loomwright/docs/result-schemas/plan-review-result.md
loomwright/scripts/test-result-validators.sh
loomwright/scripts/result-validator-fixtures/
loomwright/scripts/validate-supervisor-result.py
loomwright/scripts/test-rule-conformance-seam.sh
loomwright/skills/async-orchestration/SKILL.md
loomwright/skills/SKILLS_INDEX.md
loomwright/skills/state-management/SKILL.md
scripts/check-contract-parity.sh
changelog.d/iq01-throughput-merged.md

## Why this file exists (owner decision, 2026-10-09)
The owner merged ten queued items into **one requirement, one `/automate` item, one PR**:
`implementation-quality/01-prevent-findings-at-write-time.md` and `throughput/01`–`09`. Each source file is now stamped
`## Status: parked — superseded by` this file, and `.supervisor/iq01-backlog.md` lists only this file. The
evidence, owner decisions D1/D2 and the "Considered and NOT queued" list in `throughput/00-overview.md` still bind.

Each source is reproduced below as its own labelled **Part** (`IQ01`, `T01` … `T09`), with its Problem, Goal, Scope,
Acceptance criteria, Validation and Non-goals kept verbatim (headings demoted two levels). Inside a part, "item NN",
"this item" and "Depends on NN" mean **Part T-NN** / this part; "PR body" means the ONE merged PR's body (one
labelled section per part); a part's own `changelog.d/<slug>.md` and its own `plan-waves … --lint` validation line are
replaced by the merged-item rules below.

## Owner run rule (binding for this item)
**No new follow-up items.** Every finding — Plan Review, Phase 4.5 (`new`, `nit`, `pre_existing`, `drift`), the
`claude-review` lens, the owned drain — is fixed in THIS PR, unless fixing it would divert the work too much. The
exception is the owner's call, never the agent's: a finding the agent believes is too large to fix here is put to the
owner with its estimated cost (Part T02's cost line) and the reason, and is drafted only if the owner says so. Default
answer at the dismissed-findings decision step: **Fix now on this PR**. This does not change the decision enum, the
ledger, or the non-interactive can't-ask branch.

## Merged-item rules (override the parts where they conflict)
1. **One changelog fragment:** `changelog.d/iq01-throughput-merged.md`, `<!-- bump: minor -->`, one paragraph per part.
   The ten per-part fragment names in the parts are NOT created.
2. **No version bump.** Do NOT run `scripts/bump-version.sh` — the release is held by the owner (pending fragments from
   parallel-automate/05, 23, 24, #438, #439). Add only the fragment.
3. **Token budgets are reconciled ONCE, last.** Parts IQ01, T01, T03 each say "re-run `check-token-budget.sh`, raise on
   a breach". Do that once after every prompt edit has landed: raise only breached budgets per
   `docs/prompt-token-budgets.json` `raise_rule`, with the `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" mirror
   row and ONE raise-log paragraph naming this item (written even when nothing breached).
4. **Skill version bumps + `SKILLS_INDEX.md` are reconciled ONCE, last.** Bump `version:`/`lastUpdated:` only on skills
   this PR changed, then `bash scripts/check-skills-index-sync.sh --write` (the index is generated; never hand-edit or
   hand-merge it). No earlier subtask touches skill frontmatter or the index.
5. **Vendor-coupling manifest edits are reconciled ONCE**, after Part T09's detail block exists (T03 and T04 may need
   allowances; T09 may move test paths if the owner picks option B/C). Prefer removing a new token over a raise.
6. **Validation per part stays per part.** Each part's Acceptance criteria and Validation list must be met and evidenced
   in the PR body under that part's heading. The merged item's own validation:
   `bash loomwright/scripts/automate-helpers.sh plan-waves .supervisor/requirements/implementation-quality/02-iq01-and-throughput-merged.md --lint` prints `Touches ok; Depends on ok`, and
   `bash scripts/ci-local.sh` is green before every push.
7. **One owner decision is still open inside a part:** Part T09 Scope 2 (vendor-coupling option A/B/C, default A). Ask it
   at Launch Pad (or record "A" if not asked), never pick B/C silently.

## Internal ordering (for Launch Pad's subtask split)
Hard ordering stated by the owner:
- **Part T04 after the Part IQ01 subtasks** (both edit `build-insights.sh`, `test-insights.sh`, `commands/insights.md`,
  `session-end-jsonl.md`, `automate-trail.sh`, `test-automate-trail.sh`; T04 builds on IQ01's metric fields).
- **Part T08 after Part T06** (sharding is pointless while a serial tail sits in a shard).
- **Part T09 after Part T05** (T09's detail block is what T05's early phase prints).

File overlaps that also force serialization (from each part's `Touches` plus the IQ01 planning facts below) — parts
that share a file must not run in the same parallel wave:

| Parts | Shared files |
|---|---|
| IQ01 · T01 | `loomwright/docs/ARCHITECTURE_CONTRACTS.md`, `loomwright/docs/prompt-token-budgets.json` |
| IQ01 · T03 | `loomwright/docs/ARCHITECTURE_CONTRACTS.md`, `loomwright/docs/prompt-token-budgets.json` |
| IQ01 · T04 | `loomwright/scripts/automate-trail.sh`, `loomwright/scripts/build-insights.sh`, `loomwright/scripts/test-automate-trail.sh`, `loomwright/scripts/test-insights.sh` |
| IQ01 · T06 | `loomwright/scripts/test-automate-trail.sh` |
| IQ01 · T07 | `loomwright/scripts/test-automate-trail.sh` |
| IQ01 · T09 | `loomwright/docs/ARCHITECTURE_CONTRACTS.md` |
| T01 · T03 | `loomwright/agents/review-pr.md`, `loomwright/commands/review-pr.md`, `loomwright/docs/ARCHITECTURE_CONTRACTS.md`, `loomwright/docs/prompt-token-budgets.json`, `loomwright/skills/review-heal/SKILL.md` |
| T01 · T09 | `loomwright/docs/ARCHITECTURE_CONTRACTS.md` |
| T02 · T04 | `loomwright/docs/result-schemas/automate-run.md`, `loomwright/scripts/automate-dismissed.sh`, `loomwright/scripts/test-automate-dismissed.sh`, `loomwright/skills/automate-loop/SKILL.md` |
| T03 · T09 | `loomwright/docs/ARCHITECTURE_CONTRACTS.md` |
| T04 · T05 | `scripts/ci-local.sh`, `scripts/test-ci-local.sh` |
| T04 · T06 | `loomwright/scripts/test-automate-trail.sh` |
| T04 · T07 | `loomwright/scripts/test-automate-trail.sh` |
| T04 · T08 | `scripts/test-ci-local.sh` |
| T04 · T09 | `loomwright/docs/vendor-coupling-manifest.json` |
| T05 · T06 | `loomwright/scripts/run-self-tests.sh`, `loomwright/scripts/test-run-self-tests.sh` |
| T05 · T08 | `loomwright/scripts/run-self-tests.sh`, `loomwright/scripts/test-run-self-tests.sh`, `scripts/test-ci-local.sh` |
| T05 · T09 | `AGENT_GUIDELINES.md` |
| T06 · T07 | `loomwright/scripts/test-automate-trail.sh` |
| T06 · T08 | `.github/workflows/ci.yml`, `loomwright/scripts/run-self-tests.sh`, `loomwright/scripts/test-run-self-tests.sh` |

Parts with NO overlap with any other (except the end-of-run reconciliation files in rules 3–5): T02 overlaps only T04;
T07 overlaps only via `test-automate-trail.sh`. A sensible split (Launch Pad decides; this is a suggestion, not a
contract): {IQ01 worker/validator/checklist} ∥ {IQ01 touched-file invariants} ∥ {T01 → T03 review-heal drain} ∥
{T05 → T06 → T08, with T07 after T06} ∥ {T02}, then {IQ01 metrics → T04}, then {T09}, then the rules 3–5
reconciliation subtask (budgets, skill versions + index, vendor manifest, changelog).

## Planning facts already verified (Launch Pad pass on `45f6d7b`, 2026-10-09 — re-verify, `main` moves)
These came out of the first iq/01 Launch Pad run (Plan Review PASS on attempt 3/3, never saved because the session
exited). They are scope the IQ01 part's own `Touches` missed:
- **Worker turns measured:** the pa/24 worker (session `33e9ed8c`, `subagents/agent-ae93b523f0ce82630.jsonl`) made 79
  distinct assistant messages / 82 tool calls against `maxTurns: 40`, and was resumed. Other copies of the worker's 40:
  `ARCHITECTURE_CONTRACTS.md` §"Agent Timeout Rules" (update); `loomwright/sdk-spike/src/runner.ts`,
  `docs/SPIKES/EVAL_FINDINGS_AND_FIXES.md`, `docs/FLOOR_UI_VERIFICATION.md` AC12 Roster line (historical — leave, name in
  the PR body).
- **`self_review` WORKER_RESULT field:** require it for `status: completed|partial` (not `failed`, not
  `no_changes: true`); the block reason must state the exact shape (a block costs a runtime continuation, cap 8).
  `scripts/check-contract-parity.sh`'s WORKER_RESULT MANIFEST row must list it as an item in the existing 4th column —
  never a 5th column (out-of-tree consumer `loomwright/scripts/eval-corpus/parity-emit-block/check.sh`). Schema doc is
  `docs/result-schemas/worker-result.md` (RESULT_SCHEMAS.md is an index). The fix-worker `self_review:` clause
  (`FIX_RESULT.summary`, `clean | fixed-in-pass — …`) is an existing, distinct convention — say so, rename neither.
- **worker.md pin:** `test-no-self-matching-wait.sh` requires the "Waiting on a long run:" sub-bullet within 3 lines of
  the "pre-push command" line in `### Step 5: Verify` — insert the self-review after item 4, never between them.
- **Self-review step (d) must be reachable on every path:** the parallel worker prompt is
  `agents/execute-manager.md` Step 3 ("Read only your subtask's section"), plus the Single-Agent / Sequential `Brief:`
  lines in `skills/async-orchestration/SKILL.md` §"Subagent Spawn Contracts". The EM's own brief-read line and its copy
  in `agents/supervisor.md` §"Parallel Path" do not change.
- **Plan Reviewer criteria count** is restated 7× and pinned by exact strings in `test-rule-conformance-seam.sh`:
  plan-reviewer.md (heading `## 17 Review Criteria`, "All 17 review criteria must be checked", Decision Matrix
  "(17 total, …)", "All 17 criteria checked"), launch-pad.md "Check all 17 review criteria.", commands/launch-pad.md
  "checks all 17 criteria", `docs/POINTER_AUDIT.md` row 7. New category `touched_file_invariants` goes in
  `docs/result-schemas/plan-review-result.md`'s list. The Can't-ask rule bullet must stay byte-identical in agent and
  command (`test-non-interactive-gates-seam.sh`); `test-rule-conformance-seam.sh` extracts launch-pad action 0c
  (`^0c\. ` → `^1\. Parse CLAUDE\.md`) and 6a (`^6a\. \*\*House Rules` → `^7\. `); `test-verify-provides.sh` pins
  Phase 5.5 `1b` and the example line `# Subtask 2 — JWT guard (BLOCKED by #1)`.
- **New SUPERVISOR_RESULT fields** (`heal_first_decision`, `heal_new_findings` — names are a suggestion) must be added to
  `automate-trail.sh`'s SUPERVISOR_RESULT optional-key set, or `sidecar-check` fails every engine trail sidecar; and to
  `check-contract-parity.sh`'s SUPERVISOR_RESULT row once `validate-supervisor-result.py` validates them when present.
  `heal_decision`'s closed enum is not extended. The Phase 4.5 loop (`self-heal-advisory/SKILL.md` Part 2) keeps
  `iter_decision` local today — the accumulation is new.
- **`session_end` spec gap:** `docs/result-schemas/session-end-jsonl.md` lists neither `heal_iterations` nor
  `heal_decision`, yet `build-insights.sh` reads `heal_iterations`. Document the existing heal fields with the new ones.
  `build-insights.sh` must keep a `0` (use `has()`, never `// empty`); `commands/insights.md` restates the dashboard
  Summary contents.
- **Sibling, not in scope:** `automate-followups/27` (pending) proposes `## Closed enumerations touched` /
  `## Pin mutations` brief sections; shape `## Touched-file invariants` so they can sit beside it. Part T04 Scope 4
  already references AF/27 and AF/20.
- **Replay range for IQ01's headline check:** PR #435's `baseRefOid` is `9a65ecb7c9b43bf55fee6314a7ed283731498992`;
  `git diff 9a65ecb… 87f2205` = 13 files, +523/−36. Both commits are ancestors of `main`.

---

## Part IQ01 — 01 — Prevent findings at write time: worker self-review, touched-file invariants, worker budget, findings metric

*Source: `.supervisor/requirements/implementation-quality/01-prevent-findings-at-write-time.md` (now superseded). Part touches:* `loomwright/agents/worker.md`, `loomwright/agents/launch-pad.md`, `loomwright/commands/launch-pad.md`, `loomwright/agents/plan-reviewer.md`, `loomwright/skills/supervisor-readiness/SKILL.md`, `loomwright/skills/quality-checklist/SKILL.md`, `loomwright/skills/self-heal-advisory/SKILL.md`, `loomwright/scripts/validate-worker-result.py`, `loomwright/scripts/build-insights.sh`, `loomwright/docs/RESULT_SCHEMAS.md`, `loomwright/docs/ARCHITECTURE_CONTRACTS.md`, `loomwright/docs/prompt-token-budgets.json`

#### Precondition (owner, 2026-10-09)
Start only after PR #438 (no self-matching waits — edits the same `worker.md` / fix-worker paragraphs and `prompt-token-budgets.json`) and PR #439 (token-ledger identity gate) are merged, so this branches from a `main` that carries both. Not duplicate work: #438 adds a wait rule; this item adds a self-review stage beside it.

#### Problem
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

#### Goal
A non-trivial item reaches Phase 4.5 PASS on its **first** review iteration, and the CI `claude-review` reports "no new findings", because the worker already applied the reviewer's lens to its own diff and the brief told it the invariants it must keep. Findings-per-item is measured so the effect is visible.

#### Scope (one item, one PR — owner decision 2026-10-09: "do 1 to 4 in one go")
1. **Worker pre-hand-back self-review (`agents/worker.md`).** Before emitting `WORKER_RESULT`, the worker MUST: (a) apply the Self-Heal Miss-Class Checklist (`skills/quality-checklist/SKILL.md` — reference it, do not restate it) to its own diff; (b) run a scratch-dir adversarial repro of each load-bearing claim it introduced, following the SAME procedure as `agents/code-reviewer.md` §5 (reference, do not copy — one procedure, two callers; the worker may write inside the checkout, the repro still runs in a `mktemp -d` dir with `HOME` relocated); (c) for every claim, count, or behaviour it changed, grep the repo for the OLD wording and update or point every restated copy; (d) re-read each `## Touched-file invariants` entry of the brief (item 2) and confirm it holds. It records the result in a new `WORKER_RESULT` field (e.g. `self_review: [{class|claim, result: held|fixed|n/a, evidence}]`), and a worker result without it is incomplete — enforced by `validate-worker-result.py` the same way an absent required field is today (check `docs/HOOKS.md` §"Command-validator decision shape" for the documented block shape). Add a "reuse the file's own conventions and guards" class to the checklist (finding 12's class), so both lenses check it.
2. **Touched-file invariants in the brief (Launch Pad + plan).** Launch Pad Phase 3 adds a `## Touched-file invariants` section: for each file the change MODIFIES, the existing guards/conventions/fail-safe rules in it that the change must keep or reuse (e.g. "emit-token-ledger.sh: always exit 0; agent_scope identity check; O(1) tail reads"), and every producer/consumer contract the change must mirror exactly (e.g. "lane-park-notify desktop status must match notify-desktop.sh's dispatch conditions"), and for any hook/emitter change, which matchers/callers fire it. Template in `skills/supervisor-readiness/SKILL.md`; Plan Reviewer gains a conditional criterion that the section exists and its entries are grounded (file:anchor) when the brief modifies existing scripts. Keep `commands/launch-pad.md`'s mirrored text in sync (agent↔command mirror).
3. **Worker turn budget.** Raise the worker's `maxTurns` (measure: what the pa/24 worker needed) so the self-review stage is not the first thing dropped at the limit, and declare the larger prompt in `docs/prompt-token-budgets.json` + the `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" mirror (check-token-budget fails CI closed otherwise).
4. **Findings-per-item metric.** Record, per Supervisor run, the first Phase 4.5 iteration's decision and the total `new` findings across iterations (additive fields on `SUPERVISOR_RESULT` and the flat `session_end` line, `schema_version` unchanged), and surface "first-pass PASS rate" and "findings per item" in `/insights` (`build-insights.sh`), next to the existing `heal_iterations` aggregate.

#### Acceptance criteria
- `agents/worker.md` requires the four-part self-review before `WORKER_RESULT`, referencing (not restating) the checklist and code-reviewer §5; `WORKER_RESULT` carries the new field; `validate-worker-result.py` blocks a result without it (documented decision shape), with a test that fails before the change.
- The checklist gains the "reuse the file's own conventions and guards" class.
- A brief for a change that modifies existing scripts carries `## Touched-file invariants` with grounded entries; Plan Reviewer flags its absence; the template and the Launch Pad agent/command mirror agree.
- Worker `maxTurns` is raised with a measured justification; token budgets declared and `check-token-budget.sh` green.
- `SUPERVISOR_RESULT` / `session_end` carry the first-iteration decision and findings count; `/insights` shows first-pass PASS rate and findings per item; a fixture test covers both.
- **Replay check (the headline):** re-run the self-review procedure (as a worker would) against the pre-review commit of PR #435 (`87f2205`) in a scratch clone and record, per finding in the table above, whether the new stage catches it. Target: ≥ 9 of the 11 worker-preventable findings (rows 1–12 except 13's plan part) caught before review. Paste the per-row result in the PR body; honest misses are listed, not hidden.
- `bash scripts/ci-local.sh` green; the sequential and parallel `/automate` paths otherwise unchanged.

#### Validation (must pass before merge)
1. `bash scripts/ci-local.sh` green.
2. New tests fail on the base commit and pass on the branch (validator field, insights fields, plan-reviewer criterion where testable).
3. The replay check above, pasted in the PR body.
4. The next real `/automate` item after merge: record its first Phase 4.5 verdict and findings count (operator follow-up; the success signal, not a merge gate).

#### Non-goals
- Changing the drain's validate-then-fix rule or adding a post-READY "drop LOW nits" stop rule — a separate owner decision.
- `ci-local` fail-fast / `--affected` inner loop / scripting the per-item loop (the throughput findings) — separate items; this one reduces how many cycles happen, not what a cycle costs.

---

## Part T01 — 01 — Script the sub-floor stop decision: a deterministic `continue | READY sub_floor_converged | ESCALATED` helper the drain calls instead of evaluating pseudocode

*Source: `.supervisor/requirements/throughput/01-sub-floor-stop-decision-scripted.md` (now superseded). Part touches:* `loomwright/scripts/drain-subfloor-decision.sh`, `loomwright/scripts/test-drain-subfloor-decision.sh`, `loomwright/skills/review-heal/SKILL.md`, `loomwright/agents/review-pr.md`, `loomwright/commands/review-pr.md`, `loomwright/docs/result-schemas/review-heal-result.md`, `loomwright/docs/prompt-token-budgets.json`, `loomwright/docs/ARCHITECTURE_CONTRACTS.md`

#### Problem
The drain's sub-floor termination rule exists **only as prose and pseudocode the model evaluates**, and on the last real run the model got it wrong. That cost a full extra round of about 33 minutes, and it also mis-recorded the result.

**Where the rule lives (all prose):** `loomwright/skills/review-heal/SKILL.md`:
- §"Step U4 — The bounded drain loop", in the pseudocode block just after `pushed_sha = capture_head_sha()`. This is the `sub_floor_eligible = (required_failing == []) and (needs_human == []) and (auto_fixable != []) and all(severity_rank(f) < severity_rank(severity_floor) for f in auto_fixable)` test. It is followed by the `confirming_required_check_pass(pushed_sha, required)` call, the `rules_after = rules_gate_read(<checkout>)` re-read, and the three-way branch: READY `sub_floor_converged`, a fall-through to the next round, or ESCALATED on RED/UNREADABLE.
- §"Termination-only severity floor (`sub_floor_converged`)", including its blockquote "PINNED SEMANTICS — reading B (fix-then-stop) only; reading A (find-then-defer) is FORBIDDEN".
- §Anti-Patterns, entry "\"Find-then-defer\" (reading A) for `sub_floor_converged`".

**No script makes this decision.** The scripts each do one smaller job:
- `loomwright/scripts/drain-rounds.sh` only counts rounds (`init`/`bump`/`check`/`read`, per its header).
- `loomwright/scripts/wait-for-checks.sh` only reports settlement. Its header says: "it never decides drain readiness itself".
- `loomwright/scripts/automate-helpers.sh` `gate-eval` only *reads* the outcome afterwards (the "Condition 1b — a `sub_floor_converged` READY is NOT auto-merge-eligible" block).

**Measured misapplication.** The evidence is run `.supervisor/automate/automate-2026-10-08-121222.md`, PR vikashruhilgit/loomwright#435, the owner-requested fix-now re-drain.
- `## Progress`: "15:08:30Z owned drain started (fix-now re-drain …) @ 842cbe7" → "16:41:29Z fix-now re-drain READY (sub_floor_converged, 2 rounds, 2 fix cycles 77fc06b/783b00b, confirming pass green on 783b00b)".
- **Round 1 (scan on 842cbe7) met every eligibility condition:**
  - required `ci` on 842cbe7 was SUCCESS at 15:20:18Z (`gh api …/commits/842cbe7…/check-runs`);
  - `remaining_issues: 0` and `rules_gate: none`;
  - the round's only validated finding was LOW: the Darwin `CLICK_ACTION` mirror in `lane-park-notify`, listed with `severity: LOW` in the sidecar's `sub_floor_fixed`;
  - it was fixed in 77fc06b.
- **The confirming required-check pass on 77fc06b would have returned GREEN.** `ci` on 77fc06b completed SUCCESS at **16:08:41Z**. By the pseudocode, the drain ends READY/`sub_floor_converged` there.
- **Instead, a second round ran.** It re-scanned and fixed one more LOW: `last_counted_mark()` scanning the whole log, fixed in 783b00b. READY came at 16:41:29Z, **32 m 48 s later than the rule allows.**
- Honest note: that second round found a real LOW. The skill accepts that trade-off in so many words, in §"Termination-only severity floor", paragraph "The residual (R2 — the honest cost)". That paragraph says it "accepts that a finding round N+1's re-scan would have *discovered* … is never found". So the extra round broke the contract. It was not a quality win the contract failed to allow.

**Bookkeeping drift in the same run.** `.supervisor/automate/automate-2026-10-08-121222.review-heal-result.md` has `sub_floor_fixed:` listing **both** rounds' findings: the Darwin `CLICK_ACTION` fix (round 1) and the `last_counted_mark()` fix (round 2). The schema says otherwise. `loomwright/docs/result-schemas/review-heal-result.md` (the file `docs/RESULT_SCHEMAS.md` §REVIEW_HEAL_RESULT points to), in its field table's `sub_floor_fixed` row, says the field holds only the findings "fixed … in the final, un-re-scanned round". The pseudocode agrees: `sub_floor_fixed += auto_fixable` sits only inside the terminal READY branch. A model building the block by hand drifted from both.

**Root cause.** A multi-clause, fail-closed decision is left to the model to evaluate across a long loop, under time pressure. Nothing mechanical checks it. The repo already mechanized the neighbouring decisions for this exact reason:
- the round ceiling, in `drain-rounds.sh` ("an executable ledger, not a prose-tracked variable", §U4's "Mechanized bound" note);
- the wait, in `wait-for-checks.sh` (red-team-hardening item 04).

The stop decision is the remaining unmechanized piece.

#### Goal
On the round's real inputs, the drain's sub-floor stop decision is printed by a deterministic, tested script, and the model only acts on its one output line. `sub_floor_fixed` comes from that script's output, so it can hold only the final round's findings. The decision **semantics are unchanged**.

#### Scope
**Owner decision (binding, 2026-10-09).** Reading B stays: every validated finding at every severity is still **fixed** in its round (§U3.5 Validate-Then-Fix, unchanged). Batching sub-floor findings into follow-ups is **dropped**, because that is the forbidden reading A. This item changes *who evaluates* the existing rule (script, not prose), not the rule itself.

1. **New script `loomwright/scripts/drain-subfloor-decision.sh` (NEW), plus `loomwright/scripts/test-drain-subfloor-decision.sh` (NEW).** It is a separate script, not a `drain-rounds.sh` subcommand. `drain-rounds.sh` is a per-PR, stateful, deliberately jq-free ledger. Its header's `read_field` is "dependency-free (no jq requirement)", and its four subcommands only store and compare an integer. This decision is a stateless pure function over structured findings, and needs `jq` the way `wait-for-checks.sh` does. If, after reading both, the implementer finds the subcommand route cleaner, record why in the PR body.

   The script has two calls, matching the two points where the pseudocode decides:
   - **`eligible`.** Input: the round's classified `required_failing`, `needs_human`, `auto_fixable` (each item carrying its `severity`), and `severity_floor`. Output: `confirm` (run the confirming pass) or `continue` (normal next-round bookkeeping). It implements the `sub_floor_eligible` expression exactly, with `severity_rank` as defined under the U4 pseudocode (`BLOCKING > HIGH > MEDIUM > LOW`, "below" = strictly lower).
   - **`decide`.** Input: the same round inputs, plus the confirming pass's one `wait-for-checks.sh … --required-only` output line, the `rules_after` verdict, `rules_failed_seen`, and `checks_ever_fixed`. Output: exactly one of:
     - `READY sub_floor_converged`, plus the `sub_floor_fixed` JSON, which is **this round's `auto_fixable` only**;
     - `continue`, for GREEN with the rules clause not holding (the pseudocode's `elif outcome.result == "GREEN": pass` fall-through);
     - `ESCALATED`, plus `repeat_check_failure=<bool>` per AC13 (RED whose failing names intersect `checks_ever_fixed`).

     It mirrors the pseudocode's AFFIRMATIVE READY test: `GREEN and not (unstamped and rules_failed_seen) and verdict in RULES_PASSABLE`.
2. **Fail CLOSED, never READY on unknown input:**
   - **`eligible`:** missing, unreadable or malformed input, a finding with absent or unrecognized severity, or an unknown floor ⇒ `continue`. This is the conservative path: a full next-round re-scan, which can never yield a false READY.
   - **`decide`:** a missing or unparseable wait line, `required=unknown` (per §U2's fail-CLOSED rule, quoted in the confirming-pass block: "anything other than exactly 'green' is RED"), an `ELAPSED` line, or a sha mismatch ⇒ `ESCALATED`. This matches the skill's existing rule: "never `READY` on a red or unknown SHA".
   - **Exit codes:** state them in the header, like `drain-rounds.sh`'s `check`. No path prints READY on an exit other than the documented success.
3. **`review-heal/SKILL.md` calls the script.**
   - In §U4, replace the model-evaluated `sub_floor_eligible = …` expression and the three-way branch with the two script calls and a one-line "act on the printed line" contract. Keep the AC12 earned-fallback proof comment (it argues about the inputs, not the evaluator) and the `drain-rounds.sh bump` placement.
   - §"Termination-only severity floor" keeps the PINNED SEMANTICS block and the R2 residual verbatim, and names the script as the mechanization (pattern: "MECHANIZED via `scripts/wait-for-checks.sh`").
   - The §Anti-Patterns reading-A entry stays.
   - Add one Anti-Pattern: "deciding sub-floor termination in prose instead of from `drain-subfloor-decision.sh`'s line".
4. **`sub_floor_fixed` bookkeeping fix.** The emit step takes `sub_floor_fixed` from `decide`'s READY output, never from a hand-accumulated list. Add one clarifying sentence to the `sub_floor_fixed` row of `docs/result-schemas/review-heal-result.md`: final round only; earlier rounds' fixes are counted in `issues_fixed`/`fix_cycles`, not listed here. `schema_version` stays 2. The field stays additive/optional.
5. **Mirrors.** `agents/review-pr.md`'s "Termination-only severity floor" bullet and `commands/review-pr.md` §5 "READY terminal state" each gain a pointer to the script (authority stays the skill, "not restated here"). Check the agent↔command mirror in the same commit.
6. **Token budget.** `review-heal/SKILL.md` is preloaded by `agents/review-pr.md` (`skills: [review-heal, quality-checklist]`). Today's gate reads `review-pr 39304 / 43235 OK 3931 headroom`. Re-run `bash scripts/check-token-budget.sh` after the edit:
   - a net shrink or growth within headroom ⇒ no raise;
   - a breach ⇒ a measured raise in `docs/prompt-token-budgets.json` per its `raise_rule`, **plus** the `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" `review-pr` row in the same edit (the gate fails closed on a drifted mirror).
7. **Unchanged, explicitly:**
   - `automate-helpers.sh gate-eval` condition 1b: `sub_floor_converged` stays never auto-merge-eligible. Do not touch it.
   - `wait-for-checks.sh`'s output contract.
   - `drain-rounds.sh`.
   - The default `--severity-floor HIGH`.

#### Acceptance criteria
- `drain-subfloor-decision.sh eligible|decide` exists, with its decision table in its header. The §U4 pseudocode no longer contains a model-evaluated `sub_floor_eligible` expression or READY/ESCALATED branch; it calls the script and acts on its single line.
- **Replay of the 2026-10-08 round 1 (fixture):**
  - `required_failing=[]`, `needs_human=[]`, `auto_fixable=[{Darwin CLICK_ACTION, LOW}]`, floor `HIGH` ⇒ `eligible` prints `confirm`;
  - with `SETTLED sha=77fc06b… required=green review_producing=settled` and rules `none` ⇒ `decide` prints `READY sub_floor_converged` with `sub_floor_fixed` holding exactly that one finding.
- Table-driven tests cover every row:
  - a HIGH or MEDIUM-at-floor finding ⇒ `continue`;
  - `required_failing != []` or `needs_human != []` ⇒ `continue`;
  - `auto_fixable == []` ⇒ `continue`;
  - `required=red` ⇒ ESCALATED, plus `repeat_check_failure=true` iff the failing name is in `checks_ever_fixed`;
  - `required=unknown`, `ELAPSED`, sha mismatch, empty or garbage line ⇒ ESCALATED;
  - GREEN + rules `fail`/`unresolved`/`unreadable`, or `unstamped` with `rules_failed_seen` ⇒ `continue`;
  - garbage or missing `eligible` input or unknown severity ⇒ `continue`.
- **Mutation control:** two mutants are run against COPIES of the script, never the file on disk (the `test-add-orientation.sh` "MUTATION CONTROLS" pattern). Each must turn at least one case red:
  - `<` → `<=` in the severity comparison;
  - dropping the `required=green` requirement.
- The emitted `REVIEW_HEAL_RESULT.sub_floor_fixed` on a two-round drain lists only the final round's findings (fixture). The schema row states it.
- `gate-eval` cond 1b is byte-unchanged (`git diff` shows no hunk in that block). `bash scripts/check-token-budget.sh` is OK. Mirrors agree.

#### Validation (must pass before merge)
1. `bash scripts/ci-local.sh` green (the new `test-*.sh` is picked up by the suite glob).
2. The new tests fail on the base commit: the script is absent and the replay fixture has no decider. The two mutation controls fail as designed.
3. (merged item: see Merged-item rule 6 for the plan-waves lint).
4. Operator follow-up, not a merge gate: on the next real drain that ends `sub_floor_converged`, the `## Progress` READY line's round count equals the first eligible round with a GREEN confirming pass.

#### Non-goals
- Changing reading B, the default severity floor, or Validate-Then-Fix. Every validated finding is still fixed.
- Deferring or batching sub-floor findings into follow-up drafts. This is reading A, explicitly dropped by the owner.
- Making `sub_floor_converged` auto-merge-eligible, or any change to `gate-eval`.
- Mechanizing the rest of §U4 (channel scan, validation, fix dispatch). Only the stop decision is in scope.
- Shortening CI or the per-round wait. That belongs to items 02/03 and others.

---

## Part T02 — 02 — Show the cost of fix-now at the dismissed-findings decision: a derived wall-clock estimate in every fix-now prompt

*Source: `.supervisor/requirements/throughput/02-fix-now-cost-at-decision.md` (now superseded). Part touches:* `loomwright/scripts/automate-dismissed.sh`, `loomwright/scripts/automate-helpers.sh`, `loomwright/scripts/fixtures/automate-helpers-help.golden`, `loomwright/scripts/test-automate-dismissed.sh`, `loomwright/skills/automate-loop/SKILL.md`, `loomwright/commands/automate.md`, `loomwright/docs/result-schemas/automate-run.md`

#### Problem
The owner decides fix-now / follow-up / drop for each dismissed finding **without being shown what fix-now costs**. On the last real item, that choice took most of the item's wall-clock.

**Measured (run `.supervisor/automate/automate-2026-10-08-121222.md`, PR #435, `## Progress`):**
- 12:12:22Z run created → 14:17:25Z "drain READY (converged, 1 round, 0 fix cycles…)".
- 14:20:07Z: the owner chose **fix-now on 4 drafts**. The four `fix-now 2026-10-08T14:20:07Z` rows are in `.supervisor/automate/automate-2026-10-08-121222.dismissed-decisions`.
- 15:08:30Z: "owned drain started (fix-now re-drain, owner decision) … @ 842cbe7". This was 48 min of fix-now pass before the re-drain.
- 16:41:29Z: "fix-now re-drain READY (sub_floor_converged, 2 rounds…)".
- 17:24:50Z: "parked awaiting_merge". The decision step ran again for the re-drain's 2 new dismissals; their ledger rows are `follow-up 2026-10-08T17:24:50Z`.
- **Drain READY → park = 3 h 07 m (14:17:25 → 17:24:50), 60% of the 5 h 12 m item (12:12:22 → 17:24:50).** Decision → re-drain READY alone = **2 h 21 m** (14:20:07 → 16:41:29).

**Prior fix-now re-drains (decision → re-drain terminal line, this repo's run files):**

| Run | Decision → re-drain terminal | Span |
|---|---|---|
| 09-30-054439 | 15:21:55 → 15:47:43 (progress lines) | 26 m |
| 10-01-142337 (item 01) | ledger 18:30:30 → 18:44:18 | 14 m |
| 10-01-142337 (item 03) | ledger 10-02 12:12:15 → 13:11:15 | 59 m |
| 10-07-170659 | ledger 00:38:39 → 01:51:59 | 1 h 13 m |
| 10-08-071524 | ledger 09:02:57 → 11:55:42 | 2 h 53 m |
| 10-08-121222 | ledger 14:20:07 → 16:41:29 | 2 h 21 m |

The spread is wide, and the two most recent are the longest (GitHub `ci` now runs 11.5–14.9 min per push on PR #435). A fixed number would mislead. The estimate must be derived.

**Where the question lives (no cost shown):** `loomwright/skills/automate-loop/SKILL.md` §6 "Dismissed-findings decision step (before the park)", step 2. It defines "ONE question per per-finding draft, options **Follow-up (keep draft)** (recommended, first) · **Fix now on this PR** · **Drop**". Step 3 defines what fix-now triggers: "ONE full re-pass of DRAIN → GATE". The mechanics are in `loomwright/scripts/automate-dismissed.sh`, dispatched from `automate-helpers.sh` (`dismissed-drafts` / `dismissed-decide` / `dismissed-pending`). None of them computes or prints a cost.

**What the data allows, and its traps:**
1. **Start time.** The fix-now decision time is script-written and reliable from 10-01 on: the `dismissed-decide` ledger row `draft<TAB>fix-now<TAB>ts`.
   - Trap: the 09-30-054439 ledger's fix-now row reads `2026-10-01T03:15:17Z`, 11 h *after* that item's re-drain READY (09-30 15:47:43Z). A derivation must drop a span whose end precedes its start.
2. **End time.** The re-drain's start and terminal `## Progress` lines are model-written prose with **no pinned format**. `automate-helpers.d/runfile.sh` guards only the `owned drain started` prefix (`re_g='^([^ ]+ )?(picked |ran /autonomous|owned drain started)'`). Real wording varies across runs:
   - starts: "owned drain started (fix-now re-drain, owner decision)", "owned drain started — fix-now re-drain", "owned re-drain started (fix-now re-pass…)";
   - terminals: "fix-now re-drain READY (…)", "re-drain READY (…)", "re-drain (918470a): SETTLED required=green …".

#### Goal
Every fix-now option the owner sees states what fix-now will cost, and the estimate is derived from this repo's recorded fix-now re-drains when they exist. The owner still decides per finding. The decision enum, its recording, and the non-interactive can't-ask branch are unchanged.

#### Scope
**Owner decision (binding, 2026-10-09):** show the cost. The owner still decides per finding (fix-now / follow-up / drop). The non-interactive can't-ask branch stays.

1. **Estimator: a new `dismissed-cost <runfile>` subcommand in `automate-dismissed.sh`.** It sits with its siblings (same protocol authority, same ledger), is dispatched from `automate-helpers.sh` like `dismissed-drafts`, and is listed in the header usage block.
   - **Output:** one line, `fix_now_cost: <estimate> (<basis>)`.
   - **With samples:** basis = `median of <n> recorded fix-now re-drains in this repo, range <min>–<max>`.
   - **Without samples:** basis = the stated default.
   - **Samples.** Read every `.supervisor/automate/*.dismissed-decisions` sibling of the run file's directory. For each run with a `fix-now` row:
     - start = that run's earliest fix-now ts per decision batch;
     - end = the first later `## Progress` line in the matching run file that is a fix-now re-drain terminal (READY or ESCALATED).
   - **Matching the end line:** the new pinned form (item 3), plus a tolerant match for the legacy wordings quoted in Problem.
   - **Dropped samples:** end ≤ start, or a span > 12 h (owner think-time or an overnight stall).
   - **Fail-SAFE (advisory emitter):** this output never feeds a gate.
     - An unreadable ledger or run file ⇒ that sample is skipped.
     - Nothing readable ⇒ the default line.
     - Always `exit 0`.
   - Its own fixtures must cover:
     - the 09-30 out-of-order ledger (dropped);
     - legacy and pinned wordings;
     - zero samples (default);
     - median and range on the six spans in the Problem table (expected median ≈ 66 min, range 14 m–2 h 53 m).
2. **Default when no sample exists: the measured baseline, not a guess.** Use `≈ 1h06m median, range 14m–2h53m (6 fix-now re-drains in this repo, 2026-09-30 → 10-08)`, the six spans in the Problem table. (Correction, 2026-10-09: an earlier "~1.5–2.5 h" figure came from the two most recent spans only, and the 2 h 53 m one falls outside it. The owner's D2 asks to *show the cost*, not for a particular number, so the measured median and range are used.) The default applies only to a repo with no recorded fix-now re-drain, such as a fresh install. It must say it is another repo's baseline: `(default: loomwright's own 2026-10 baseline; no fix-now re-drain recorded here yet)`.
3. **Pin the re-drain progress lines** going forward, so item 1's derivation does not depend on prose. In `automate-loop/SKILL.md` §6 step 3, specify the exact start and terminal line text, for example:
   - `<ts> owned drain started (fix-now re-drain) — …`
   - `<ts> fix-now re-drain <READY|ESCALATED> (…)`

   Document both in `docs/result-schemas/automate-run.md` beside the `owned_drain_started` row. The `current_not_set` guard regex is unchanged; the start line still begins `owned drain started`.
4. **Prompt text (`automate-loop/SKILL.md` §6 step 2).**
   - Before asking, run `automate-helpers.sh dismissed-cost <runfile>` once per decision batch.
   - In every per-finding question's **Fix now on this PR** option description, state: "≈ <estimate> wall-clock: ONE owner-requested fix pass + full re-drain + re-park (<basis>)".
   - Show **Follow-up** as "0 min now (+ a future queue item)", and **Drop** as "0 min".
   - The recommended-first order (Follow-up) stays.
   - With `fix_now_reentered: true` the options are already Follow-up / Drop only, so no cost line is needed.
   - The §6 step 1 PICK-time pending-decisions ask (Follow-up / Drop only) is unchanged.
5. **Recording.** Append `fix_now_cost` to the decision's `## Progress` line as data, e.g. `… (est. fix_now_cost ≈ 1h06m, n=6)`, so a later item can measure estimate against actual. Change nothing else: `dismissed-decide`'s ledger row shape (`draft<TAB>decision<TAB>ts`), the decision enum `fix-now|follow-up|drop`, and the `--non-interactive-fallback` branch ("step 2 asks nothing and step 3 never runs") all stay as they are.
6. **Mirrors:**
   - `commands/automate.md`'s "Dismissed findings" bullet gains "(each fix-now option shows its derived wall-clock cost)";
   - the `automate-loop/SKILL.md` §1.5 helper table gains a `dismissed-cost` row;
   - regenerate `fixtures/automate-helpers-help.golden` (instruction in `test-automate-helpers-dispatch.sh`: "ADDING A SUBCOMMAND? Regenerate the golden in the same change").
7. **Token budget:** no budget change expected. `automate-loop/SKILL.md` is in no agent's `skills:` frontmatter, and `check-token-budget.sh` measures only agent `.md` files plus preloaded skills. Confirm with `bash scripts/check-token-budget.sh`.
8. **Item 04 (phase timing, future) will improve the estimate.** This item works standalone from the ledger plus `## Progress` derivation above. When item 04 lands, its per-phase timestamps may replace the progress-line matching, with the same output line.

#### Acceptance criteria
- `automate-helpers.sh dismissed-cost <runfile>` prints exactly one `fix_now_cost:` line and exits 0 on all inputs, including a missing directory, an unreadable ledger, or zero samples.
- Fixture tests in `test-automate-dismissed.sh`:
  - the six spans in the Problem table give median ≈ 66 min, range 14 m–2 h 53 m;
  - the 09-30 out-of-order ledger row is dropped;
  - a > 12 h span is dropped;
  - pinned and legacy terminal wordings both match;
  - zero samples ⇒ the default line.
- §6 step 2 requires the cost in every fix-now option and shows follow-up as 0 min now. §6 step 3 pins the re-drain start and terminal line formats, mirrored in `docs/result-schemas/automate-run.md`.
- No change to the decision enum, to the ledger row shape, to `dismissed-pending`, or to the non-interactive branch: the existing `test-automate-dismissed.sh` cases pass unmodified.
- The help golden is regenerated, and `test-automate-helpers-dispatch.sh` is green.
- The zero-sample default line names its basis (another repo's baseline), never a bare number.

#### Validation (must pass before merge)
1. `bash scripts/ci-local.sh` green.
2. The new `dismissed-cost` tests fail on the base commit (unknown subcommand) and pass on the branch. Mutation control: removing the end-before-start drop makes the 09-30 fixture fail.
3. (merged item: see Merged-item rule 6 for the plan-waves lint).
4. Operator follow-up, not a merge gate: at the next interactive park with drafts, the question shows the derived cost, and the decision's `## Progress` line carries the estimate.

#### Non-goals
- Changing the recommended option, the options themselves, or making fix-now unavailable.
- Making the decision for the owner or auto-picking by cost, interactive or not.
- Changing the non-interactive can't-ask branch or the PICK-time ask.
- Per-phase timing instrumentation (item 04).
- Reducing what a fix-now re-drain costs (items 01/03, implementation-quality/01).

---

## Part T03 — 03 — Keep the scoped check-wait under the 600 s foreground cap: a resumable `wait-for-checks.sh` with a persisted total deadline

*Source: `.supervisor/requirements/throughput/03-check-wait-under-bash-cap.md` (now superseded). Part touches:* `loomwright/scripts/wait-for-checks.sh`, `loomwright/scripts/test-wait-for-checks.sh`, `loomwright/skills/review-heal/SKILL.md`, `loomwright/agents/review-pr.md`, `loomwright/commands/review-pr.md`, `loomwright/docs/PITFALLS.md`, `loomwright/scripts/retention-sweep.sh`, `loomwright/scripts/test-retention-sweep.sh`, `loomwright/docs/prompt-token-budgets.json`, `loomwright/docs/ARCHITECTURE_CONTRACTS.md`

#### Problem
The drain's check-wait contract asks for a single foreground call that may run up to 1200 s. The host's Bash tool caps a foreground command at 600 s. Real CI already outlasts 600 s.

- **The contract** is in `loomwright/skills/review-heal/SKILL.md` §"Step U2.5", under "Bounded wait — MECHANIZED via `scripts/wait-for-checks.sh`": "a single **foreground, blocking** script call". The quote block below it reads: "Never run this wait in the background and never end the turn while waiting — under `claude -p` ending the turn ends the process and the drain dies with no result." The same sentence guards the confirming pass in §"Termination-only severity floor". The bound is "**Default sizing — 1200 s, measured, not guessed**". It is mirrored in:
  - the skill's flag table (`--check-wait-timeout N` … "default 1200");
  - `loomwright/commands/review-pr.md`'s flag table ("1200 (20 min)");
  - `loomwright/agents/review-pr.md` ("a single foreground, blocking call").
- **The cap.** The Bash tool's documented foreground limit is a 600000 ms maximum `timeout`. This repo already designed around it once, in `scripts/ci-local.sh`'s header for `--wait` (PR #438, commit 0cdf464): "default 540: under the 600 s a single agent tool call may block". The same header records what happens to a call that runs longer: "a full run takes ~10 min, so an agent's foreground call is moved to the background". Under `claude -p`, a backgrounded wait followed by a turn-end is exactly the death this script was written to prevent (`wait-for-checks.sh` header, "WHY THIS EXISTS").
- **Measured CI per push on PR #435.** Required `ci` check-run `started_at` → `completed_at`, from `gh api repos/vikashruhilgit/loomwright/commits/<sha>/check-runs`:

  | Commit | ci duration |
  |---|---|
  | 87f2205 | 11 m 31 s |
  | 3a1cf14 | 14 m 51 s |
  | 842cbe7 | 11 m 48 s |
  | 77fc06b | 13 m 32 s |
  | 783b00b | 11 m 57 s |

  Every one exceeds 600 s, so a single foreground call cannot cover even one push.
- **The workaround is manual.** The 2026-10-08 operator split each wait by hand. `.supervisor/handover-2026-10-09-to-9768c6f2.md` records it: "`wait-for-checks.sh`: two ≤580 s foreground calls on the same SHA (Bash 600 s cap)". Nothing in the skill tells a detached `review-pr-runner` (or the next operator) to do this. It has not yet killed a drain, but with CI at 11–15 min it will.
- **Root cause.** The script's only clock is in-process. The `wait-for-checks.sh` header says the bound is "tracked via the bash builtin `$SECONDS` (reset to 0 at script start)". So the total bound cannot be split across calls: a second call restarts the full budget, and a 1200 s call outlives the host cap.

#### Goal
No single foreground `wait-for-checks.sh` call exceeds the host cap. The **total** bound per (PR, SHA, scope) is still honoured across calls (1200 s default, or the re-measured value). The fail-closed outcomes are unchanged: a total-budget timeout is the existing `ELAPSED` outcome, so the decision is still ESCALATED.

#### Scope
1. **A resumable mode in `wait-for-checks.sh`.**
   - A per-call ceiling, e.g. `--call-max <s>`, capped at 570 s. Reuse PR #438's precedent: `ci-local.sh --wait`'s default of 540 s, a "STILL-RUNNING — call again" result, and exit 3 there.
   - The script then loops inside one call until the scoped set settles, the per-call ceiling is reached, or the total deadline passes.
   - **New outcome on the per-call ceiling, with budget left:** one final line such as `CONTINUE sha=<sha> remaining=<s> pending=<…>`. It keeps the one-line, always-exit-0 contract; the header states the new line kind beside `SETTLED`/`ELAPSED`.
   - **Without the new flag, the output is byte-unchanged** for every existing caller. That includes `automate-helpers.d/escalation.sh`'s snapshot call `--bound 0 --names`, the default line, and `--names` lines.
2. **Persisted total deadline, keyed on the same SHA.**
   - The first call for a (PR, `--sha`, scope = `--required-only` vs review-pattern) key writes an absolute deadline: epoch seconds, `date +%s`, BSD/GNU-portable. It is written to gitignored scratch, e.g. `.supervisor/check-wait/<key-hash>.json`. Reuse `drain-rounds.sh`'s `pr_hash` derivation (shasum → sha1sum → cksum fallback).
   - Continuation calls read that deadline and never reset it.
   - A **different SHA is a different key**: a new push starts a fresh 1200 s, matching the skill's "The bound starts the moment a fix is pushed".
   - **Fail-CLOSED on continuation.** If the state is unreadable or garbage on a call that claims to continue (e.g. an explicit `--continue` with no or garbage state), the call ⇒ `ELAPSED … pending=unreadable_deadline`. It never grants a fresh full budget, which would make the wait unbounded.
   - Missing state on a first call is normal: create it.
   - Register the new scratch directory in `retention-sweep.sh`'s `policy_rows` as an `exhaust` row, like `drain-rounds`, with a fixture in `test-retention-sweep.sh`.
3. **Skill loop (`review-heal/SKILL.md`).**
   - At **both** call sites (§U2.5 scoped wait and the confirming pass), the call becomes a foreground loop: call with `--bound <check_wait_timeout> --call-max 540`; on `CONTINUE`, call again immediately on the **same** `--sha`, as a new foreground tool call; stop on `SETTLED` or `ELAPSED`. Each call's tool `timeout` must be set ≥ call-max + one poll interval and < 600000 ms.
   - The "Never run this wait in the background…" sentence stays, and gains "…and a `CONTINUE` line is not a result: call again, never end the turn on it".
   - Add the Anti-Pattern: "a single wait call sized past the host's foreground cap".
   - The 1200 s sizing note keeps its measured justification. Update it to the PR #435 numbers above, since 3a1cf14's 891 s is near the note's own "if `ci` grows past ~900 s, raise the bound" threshold. Raise the bound only if the owner agrees; this item does not change the default by itself. **Owner decision (2026-10-09, Launch Pad): keep 1200 s** — refresh the sizing note only.
4. **Mirrors.**
   - `agents/review-pr.md`'s scoped-check-wait bullet: "a single foreground, blocking call" becomes "foreground, blocking calls, each under the host cap, looped on `CONTINUE`".
   - `commands/review-pr.md`'s `--check-wait-timeout` row: "total across calls".
   - `docs/PITFALLS.md`'s "A review-drain marker means 'dispatched'…" entry, whose "Fixed two ways" paragraph says "a single foreground, **blocking** script call": one clause.
5. **Unchanged:**
   - `required=unknown` ⇒ escalate;
   - SHA binding and the materialization guard;
   - AC3 (optional checks never block);
   - AC4 (elapsed ⇒ ESCALATED);
   - always exit 0;
   - the `GH`/`JQ` test stub seam.
6. **Token budget + vendor ratchet.** `review-heal/SKILL.md` is preloaded by `agents/review-pr.md`. The gate today reads `review-pr 39304 / 43235 OK 3931 headroom`. Re-measure with `bash scripts/check-token-budget.sh`; on a breach, raise per `prompt-token-budgets.json`'s `raise_rule` and update the `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" `review-pr` row in the same edit. `wait-for-checks.sh` has a vendor-coupling allowance of 2 in `docs/vendor-coupling-manifest.json`. Write new comments vendor-neutral, so they do not add `claude` tokens. If that proves impossible, the manifest joins this item's Touches and its own measured-raise procedure applies.

#### Acceptance criteria
- `wait-for-checks.sh --bound 1200 --call-max 540` against a stub whose required check stays IN_PROGRESS gives:
  - call 1 prints `CONTINUE … remaining≈660` within 540 s + one interval;
  - call 2 (same SHA) prints `ELAPSED …` within the remaining budget, not after another 1200 s.

  Tests use small numbers, e.g. `--bound 4 --call-max 2 --interval 1`, so the suite stays fast.
- A continuation whose required check settles green prints `SETTLED … required=green`. A new SHA starts a fresh deadline. Unreadable state on continuation ⇒ `ELAPSED … pending=unreadable_deadline`, never a fresh budget.
- Without `--call-max` (or the chosen flag), every existing `test-wait-for-checks.sh` case passes unmodified: the output is byte-identical, `escalation.sh`'s `--bound 0 --names` included.
- Mutation control: a copy of the script that resets the deadline on every call (re-writes state unconditionally) fails the "call 2 elapses within the remaining budget" case.
- Both skill call sites loop on `CONTINUE` with per-call `--call-max ≤ 570`. No prose anywhere still requires one call to cover the full bound (`grep -rn "single foreground" loomwright/` shows only updated wording). The agent, command and PITFALLS mirrors agree.
- `retention-sweep.sh` lists the new scratch dir, and its test covers it. `check-token-budget.sh` is OK. `check-vendor-coupling.sh` is OK.

#### Validation (must pass before merge)
1. `bash scripts/ci-local.sh` green.
2. The new continuation tests fail on the base commit (no `CONTINUE` line, `$SECONDS`-only bound) and pass on the branch. The mutation control fails as designed.
3. (merged item: see Merged-item rule 6 for the plan-waves lint).
4. Operator follow-up, not a merge gate: on the next real drain, the transcript shows ≥2 foreground `wait-for-checks.sh` calls on one SHA with no tool call above 600 s, and a `SETTLED` reached across them.

#### Non-goals
- Changing the 1200 s default or the 15 s poll interval (a separate measured decision, see Scope 3).
- Backgrounding the wait, or any notification/callback-based wait. Foreground remains the contract.
- Speeding up GitHub CI or `ci-local`.
- Changing `drain-rounds.sh`, the confirming pass's GREEN/RED/UNREADABLE mapping, or any READY/ESCALATED decision logic (item 01 owns the sub-floor decision).

---

## Part T04 — 04 — Phase timing: per-phase wall-clock and machine-vs-owner time, derived from the log

*Source: `.supervisor/requirements/throughput/04-phase-timing.md` (now superseded). Part touches:* `loomwright/scripts/phase-timing.sh`, `loomwright/scripts/test-phase-timing.sh`, `loomwright/scripts/fixtures/phase-timing/`, `loomwright/scripts/emit-lifecycle.sh`, `loomwright/scripts/test-emit-lifecycle.sh`, `loomwright/scripts/hook-dispatch-on-pr-create.sh`, `loomwright/scripts/test-hook-dispatch-on-pr-create.sh`, `loomwright/scripts/automate-dismissed.sh`, `loomwright/scripts/test-automate-dismissed.sh`, `loomwright/scripts/automate-trail.sh`, `loomwright/scripts/test-automate-trail.sh`, `loomwright/scripts/build-insights.sh`, `loomwright/scripts/test-insights.sh`, `loomwright/commands/insights.md`, `loomwright/hooks/hooks.json`, `loomwright/docs/HOOKS.md`, `loomwright/docs/result-schemas/session-end-jsonl.md`, `loomwright/docs/result-schemas/agent-lifecycle-jsonl.md`, `loomwright/docs/result-schemas/automate-run.md`, `loomwright/skills/automate-loop/SKILL.md`, `loomwright/docs/vendor-coupling-manifest.json`, `scripts/ci-local.sh`, `scripts/test-ci-local.sh`

#### Problem
Nobody can say where an `/automate` item's time went without hand work. Finding out where PR #435's 5 h 12 m went (run `.supervisor/automate/automate-2026-10-08-121222.md`, session log `.supervisor/logs/auto-2026-10-08-123152.jsonl`) meant hand-joining subagent transcripts, ci-slot run logs and `gh run list`. Nothing can answer the red-team's first question, which is how much of an item is machine time and how much is waiting on the owner.

What the log has today (verified 2026-10-09):

- **The session log** (95 lines) has `agent_lifecycle` ×84, `token_ledger` ×6, `subtask_complete` ×3, and one each of `autonomous_start` and `session_end`. It has **no `phase_transition` event**. Across all of `.supervisor/logs/*.jsonl`, `phase_transition` appears in only 4 logs, and the last is from 2026-06-13. That is by design. `loomwright/scripts/emit-progress-event.sh`'s header ("WHY THIS EXISTS") measured 785 hook-written `token_ledger` events against 6 agent-written `phase_transition` events. `skills/state-management/SKILL.md` §"Session Logging" retired prompt-written progress events for that reason. **This item must not bring back a prompt-written phase event.**
- **`session_end` has no duration field.** None of the 116 `session_end` records in the corpus carries `duration_seconds`, but `build-insights.sh` (its §1 `jq` record collector) reads `.duration_seconds // null` and renders it when present. It is a reader slot nothing writes. `session_end` is appended by the Supervisor model at the Phase 4.5 completion tail (`skills/self-heal-advisory/SKILL.md` §"Hard-signal dual emission"; there is no helper script). A duration added there would be a model-computed number with the same miss rate as `phase_transition`.
- **Part of the session is in the wrong file.** Events before `autonomous_start` go to the Claude Code UUID log `.supervisor/logs/33e9ed8c-64ae-4ee8-8563-8468e749516f.jsonl` (138 lines), not to the `auto-…` log, because the plugin session id does not exist yet. That includes Launch Pad's plan-reviewer spans (12:12:59Z–12:21:02Z) and the owner question at 12:21:08Z. The run file's `run created (session <uuid>)` line and the `auto-2026-10-08-123152.owner` sidecar (`cc_session_id=`) are the join keys. No reader uses them.
- **The `## Progress` lines are timestamped at the automate boundaries**: `picked` 12:12:45Z, `ran /autonomous → PR` 14:15:29Z, `owned drain started` 14:15:58Z, `drain READY` 14:17:25Z, `owned drain started (fix-now re-drain…)` 15:08:30Z, `fix-now re-drain READY` 16:41:29Z, `parked awaiting_merge` 17:24:50Z. The exceptions are the `dismissed: <decision> …` lines. `automate-dismissed.sh` (the `progress-append … "dismissed: $decision $name — $snippet"` call) writes them **without a timestamp**, so the moment the owner answered is not recorded.
- **When the owner was asked is recorded; when the owner answered is not.** `PreToolUse[AskUserQuestion]` and `Notification[permission_prompt]` write `agent_lifecycle` `state: waiting` rows (orca-derived/01, done, PR #231). Nothing fires on the answer: `hooks.json` has no `PostToolUse[AskUserQuestion]` leaf. The only proxy is the next debounced `working` heartbeat (`LOOMWRIGHT_LIFECYCLE_HEARTBEAT_DEBOUNCE`, default 60 s, `emit-lifecycle.sh` header), which is an upper bound, not a fact.
- **PR creation time is not in the log.** The PR was created at 13:22:00Z (`gh pr view 435 --json createdAt`), so FINALIZE ran *before* Phase 4.5 (first reviewer at 13:23:02Z). A reader cannot place that boundary from local data. The `gh pr create` `PostToolUse[Bash]` hook (`hook-dispatch-on-pr-create.sh`) already fires on it but logs no event.
- **`/insights` computes no wall-clock.** `commands/insights.md`, `build-insights.sh` and `build-loop-evidence.sh` aggregate counts and decisions only.
- **ci-local runs cannot be attributed by time window.** Run logs in `~/.local/state/loomwright/ci-slots/<repo-key>/runs/` are named `<tree>-<origin/main>-<OS>-<ts>-<pid>.log` (`ci-local.sh` `content_key()` / `open_log()`). They are shared by every session and checkout, and only the newest 20 are kept. In #435's window (base `9a65ecb`) there are 10 full runs. Seven match a #435 commit tree. **One (`5bdf5a4…`, 14:26Z) is PR #438's commit `0cdf464`'s tree.** Two (`3e7bc89…` 14:29Z, `96b9fcf…` 15:31Z, both FAIL) match no commit tree, because they ran on uncommitted working trees. The log header names only the key, with no HEAD and no branch, so tree matching alone cannot attribute those two.

What the existing rows already reconstruct (the replay this item must automate; derived by hand on 2026-10-09):

| Span | Wall | Machine / owner | Source |
|---|---|---|---|
| pick → `autonomous_start` | 19 m 07 s | ≈ 8 m Launch Pad + plan review (12:12:59–12:21:02) · ≈ 10 m owner (asked 12:21:08, next `working` 12:31:13) | run file + **UUID log** |
| worker | 12:33:25 → 13:20:37 | machine (one validator-rejected stop at 13:19:44) | `agent_lifecycle` / `subtask_complete` |
| PR created | 13:22:00 | — | `gh` only (not in the log) |
| Phase 4.5 reviewer iterations | 13:23:02–13:31:07 · 14:01:15–14:07:54 · 14:10:09–14:13:23 | machine | `agent_lifecycle` rows, code-reviewer `agent_id`s |
| pick → drain READY | **2 h 04 m 40 s** | — | run file |
| post-READY (READY → park) | **3 h 07 m 25 s** | ≈ 2 m owner (asks 14:18:33 / 14:19:23 → 14:20:46) · fix-now fix pass 14:21:49–15:07:53 (machine) · **re-drain 15:08:30 → 16:41:29 (1 h 32 m 59 s)** · ≈ 43 m owner (asked 16:41:41, next `working` 17:24:51) | run file + lifecycle rows |
| park → merge | 6 h 38 m | owner (outside the 5 h 12 m) | `gh` `mergedAt` 00:02:40Z |

So about 55 m of the 5 h 12 m pick→park was owner wait. That figure is only estimable today, and only from heartbeat upper bounds. The 51 m between READY and the re-drain start, which looks like owner time in the run file, was almost all machine time (the fix-now fix pass). The evidence brief (`00-overview.md`) says the third Phase 4.5 iteration took "~11 m". The lifecycle rows show 14:07:54 → 14:13:23 (≈ 5.5 m, including its 32 s fix pass). That discrepancy is the kind this item removes.

#### Goal
For any Supervisor run and any `/automate` item, a script answers from local logs alone: how long each phase took, and how much of the item was machine time versus waiting on the owner. `/insights` shows it. A timestamp that was never recorded reads as `null` (unknown), never as 0, and nothing in the pipeline is a model-computed duration.

#### Scope
1. **One derivation, one reader script: `loomwright/scripts/phase-timing.sh` (NEW).** Read-only and fail-SAFE (exit 0; unreadable input ⇒ `null` fields plus one stderr note). Input is a run file (`--run <runfile>`) or a session id (`--session <id>`). Output is one JSON record per item or session. Build on orca-derived/01's lifecycle ledger; do not add a parallel clock or any new heartbeat.
   - **Join:** the plugin session log plus the Claude Code UUID log, keyed by `cc_session_id` (rows), the run file's `run created (session <uuid>)` and `session_id <id>` lines, and the `<session>.owner` sidecar.
   - **Supervisor spans:** plan (first plan-reviewer `working` → last plan-reviewer `ended`, when present), execute (first worker `working` → last non-rejected worker `subtask_complete`), finalize (→ `pr_created`, item 3c), Phase 4.5 per iteration (one span per code-reviewer `agent_id`, from its first `working` to its `ended`, plus the fix pass between iterations), and completion (→ `session_end.ts`).
   - **Ordering:** phases are ordered by their timestamps, never assumed. #435 ran FINALIZE before Phase 4.5.
   - **Automate per-item spans** come from the `## Progress` timestamps: pick→`autonomous_start`, `/autonomous`, each owned drain (start → READY/ESCALATED), each fix-now pass, and READY→park.
   - **Missing endpoints:** a span with a missing endpoint is `null`. A run that reports an `owned_drain_result` value outside today's enum (see Scope 4) closes the drain span at that line's ts, or leaves it `null`. It is never guessed.
2. **Owner-wait intervals.** `asked` is the `waiting` row's ts (`reason: ask_user`; `permission_prompt` counts only when no `ask_user` row is within the debounce window, so one question is not counted twice). `answered` is the new row in 3a. Each interval carries `exact: true` when `answered` came from 3a. On logs written before this item, `answered` falls back to the next main-scope `working` row with `exact: false` (an upper bound). Owner time is the sum of intervals; machine time is wall time minus owner time. Each is `null` when its inputs are missing, never 0.
3. **The minimum new emission points.** These are hook-written or script-written, fail-SAFE (exit 0, `|| true` per `CLAUDE.md` §"Plugin Hooks"), and never invent a value.
   - **3a.** Add a `PostToolUse[AskUserQuestion]` leaf → `emit-lifecycle.sh answered`. It writes `agent_lifecycle` `state: working`, `reason: answered`, and the payload's tool-use id, so it pairs with the `PreToolUse` `waiting` row. It bypasses the heartbeat debounce. **Probe first:** record one real `PostToolUse[AskUserQuestion]` payload (key set, whether a tool-use id is present in both Pre and Post) in this file before writing the emitter, using the recipe in `~/.claude/CLAUDE.md` (a temporary hook in `.claude/settings.local.json`). If no shared id exists, pair by order and say so.
   - **3b.** `automate-dismissed.sh` writes its `dismissed:` Progress line with the same leading `<ts>` every other Progress line carries. That ts is the moment the decision was recorded.
   - **3c.** `hook-dispatch-on-pr-create.sh` appends one `pr_created` event (`ts`, PR URL) to the session log it already resolves. It records the PR only and never changes the dispatch gate.
   - **3d.** `scripts/ci-local.sh` writes `HEAD` sha and branch as one additive header line in each run log. This lets a run on an uncommitted tree be attributed by HEAD, not by time.
4. **Schemas, additive only (`schema_version` unchanged).** Follow the rule in `docs/result-schemas/schema-versioning.md` (rule 3) and the additive-field precedent in `session-end-jsonl.md` (`reason`, `plugin_version`, `knowledge_sources_used`).
   - **Persisted record.** The automate per-item summary is persisted as ONE script-written `item_timing` JSONL event that `automate-trail.sh closeout` appends by calling `phase-timing.sh --run` (fail-SAFE). Document it in `session-end-jsonl.md` as a "related additive session-log event", the way `token_ledger` is noted there.
   - **`session_end` gets no model-written duration.** `build-insights.sh` attaches the derived spans to its in-memory `session_end` record and stops reading the dead `duration_seconds` slot, or feeds that slot from the derivation. Say which.
   - **Closed enums.** `agent_lifecycle`'s `reason: answered` on a `working` row is additive (`working` carries no reason vocabulary today). `state` is NOT extended. This item adds **no** `pause_reason` or `owned_drain_result` value. If implementation finds it needs one, the brief carries a `## Closed enumerations touched` section (per `automate-followups/27`), and the value lands together with `automate-followups/20`.
   - **Relation to `automate-followups/20`.** AF/20 proposes `owned_drain_result: superseded_by_merge`. Its second proposal, `awaiting_go`, is already in the `pause_reason` enum (`automate-run.md`, written only by `closeout`, since commit `4bf97cc`). The timing reader must close a drain span on `superseded_by_merge` if AF/20 lands first.
   - **Relation to `automate-followups/27`.** AF/27 is the brief rule that makes "which closed lists does this new value belong to" a required section. This item follows that rule. Both AF items are pending, with no hard dependency. AF/20 also edits `automate-trail.sh` / `automate-run.md`, so run them sequentially, never in one wave (the shared Touches already prevent co-scheduling).
5. **`/insights` (`build-insights.sh`, `commands/insights.md`)** gets a `## Wall-clock (phases · machine vs owner)` section:
   - per-phase medians and the latest run's spans;
   - for each automate item, pick→park, owner time, machine time, and the share of owner time that is `exact`;
   - a `null` span renders as "not recorded", never 0.
6. **ci-local time line per item.** `phase-timing.sh --run` lists the item's ci-local runs, each with start, wall seconds and verdict.
   - **Attribution** is by tree key only: the log's `<tree>` matches a commit tree on the item's branch (`git log --format=%T <base>..<head>`), or 3d's HEAD is on that branch. It is **never by time window**, because a PR #438 run sat inside PR #435's window.
   - **Unattributable runs** are counted as `unattributed`, not dropped and not guessed.
   - **Pruned logs:** only 20 logs are kept, so `closeout`'s `item_timing` captures the list at merge time. Runs pruned before that make the list `null` (incomplete), not empty.
7. **Not folded in:** `proposed/insights-stranded-closeouts-counted-as-failed.md`. It is the same surface (`build-insights.sh`'s `session_end` collector) but a different defect, status classification. It stays a separate proposal. This item must not make it worse: the derivation gives a `close-stranded-run.sh` synthetic `session_end` (`reason: session_ended_without_completion`) `null` spans, never a session duration ending at the close-out.

#### Acceptance criteria
- **Replay (headline).** `phase-timing.sh --run .supervisor/automate/automate-2026-10-08-121222.md`, over `auto-2026-10-08-123152.jsonl` and the UUID log `33e9ed8c-….jsonl`, reproduces each of these within one minute:
  - pick → drain READY: 2 h 04 m 40 s
  - post-READY (READY → park): 3 h 07 m 25 s
  - fix-now re-drain: 15:08:30 → 16:41:29
  - pick → `autonomous_start`: 19 m 07 s, split into plan review ≈ 8 m and owner ≈ 10 m (`exact: false`)
  - the three Phase 4.5 reviewer spans in the table above
  - the two post-READY owner waits (≈ 2 m, ≈ 43 m, `exact: false`)

  Paste the record in the PR body. Copy these logs, trimmed to the rows the derivation reads, into `loomwright/scripts/fixtures/phase-timing/` (NEW directory; the source logs are gitignored on disk), so the replay is a committed test in `test-phase-timing.sh` (NEW). The fixtures sit under the `core`-classed `loomwright/scripts/*` glob, so run the vendor-coupling gate on them too.
- **Owner-wait fixture.** With a `waiting` row plus a 3a `answered` row, owner time is exact and `exact: true`. With no `answered` row, it falls back with `exact: false`. With no `waiting` row, owner time is `0` only when the log provably spans the item and contains no ask; otherwise it is `null`.
- **Mutation controls.** Each must turn a test red:
  - delete the `cc_session_id` join (the 19-minute split must go red);
  - make a missing endpoint yield 0 instead of `null`;
  - attribute ci-local runs by time window (the `5bdf5a4…` #438 run must not appear in #435's list).
- **Emitter tests.** 3a, 3b, 3c and 3d each have a test, and each emitter exits 0 on an empty or malformed payload. 3b's ts line passes `test-automate-dismissed.sh` with its count assertions updated, not removed. The `hooks.json` leaf for 3a carries `|| true`, and the `docs/HOOKS.md` hook table gains its row.
- **Vendor-coupling ratchet.** `emit-lifecycle.sh` / `hook-dispatch-on-pr-create.sh` are `core`. Remove any new hook-protocol token before raising an allowance. A raise carries an added `allowance_reasons` entry (`scripts/check-vendor-coupling.sh` header, "TO RAISE AN ALLOWANCE").
- **`/insights`.** A fixture corpus shows the wall-clock section, and `null` spans render as "not recorded".
- **No model-computed number.** `grep` the diff: no agent or skill prose instructs a model to compute or write a duration.

#### Validation (must pass before merge)
1. `bash scripts/ci-local.sh` green (the full run).
2. New tests fail on the base commit and pass on the branch: `test-phase-timing.sh`, the 3a–3d emitter legs, and the insights leg.
3. The replay record above, pasted in the PR body, with each known span's delta (must be ≤ 60 s).
4. **Running system** (operator follow-up after merge, not a merge gate): the next real `/automate` item's `item_timing` line, showing `exact: true` owner intervals.

#### Non-goals
- **Reintroducing `phase_transition`** or any prompt-written progress event. The derivation reads hook- and script-written rows only (see Problem).
- **Changing gates, `heal_decision`, the drain, or the dismissed-findings decision itself.** This item measures and decides nothing.
- **The stranded-close-out bucketing** (`proposed/insights-stranded-closeouts-counted-as-failed.md`). Not folded in; see Scope 7.
- **GitHub CI wall-clock per push** (`gh run list` timings). This is local-log-only, consistent with `/insights`' "no data leaves your machine". A later item may add it.
- **The output-token source.** This is separate, and not about timing. Session 33e9ed8c's 15 subagent transcripts hold 398 assistant message ids. **356 of them (89%) carry only the stream-start placeholder `output_tokens`, with no final `stop_reason` line.** So the F8 limit in `loomwright/docs/TELEMETRY.md` §"Transcript usage" ("output tokens of a message whose final line is absent … are UNDER-counted", described there as "common in older transcripts") is the **common** case in current transcripts, not an edge case. This needs its own follow-up on where output tokens come from. Pointer only; not scoped here.

---

## Part T05 — 05 — ci-local early gates: a full run fails in seconds when a cheap gate is red, not after the whole pool

*Source: `.supervisor/requirements/throughput/05-ci-local-early-gates.md` (now superseded). Part touches:* `scripts/ci-local.sh`, `scripts/test-ci-local.sh`, `loomwright/scripts/run-self-tests.sh`, `loomwright/scripts/test-run-self-tests.sh`, `loomwright/scripts/test-automate-helpers-dispatch.sh`, `loomwright/scripts/test-citation-drift.sh`, `AGENT_GUIDELINES.md`

#### Problem
**Owner decision D1 (2026-10-09, binding — `00-overview.md` §"Owner decisions"):** the pre-push rule stays. One FULL `bash scripts/ci-local.sh` before every push, drain pushes included, with no "GitHub CI is the full run" exemption. So the only way to make a red push-gate cheaper is to make the full run **fail early**, never to skip it.

Today a full run puts every gate into one pool and reports only at the end:

- `scripts/ci-local.sh` (the `--- plan:` block and the `--- run ---` block) turns every ci.yml gate into a wrapper and appends every root and loomwright self-test, then makes ONE `bash "$runner" "${plan[@]}"` call. The 20 ci.yml gates and the 135 self-tests share a single pool (`ci-local: 20 ci.yml gates + 135 self-tests, one pool` in every PR #435 log).
- `loomwright/scripts/run-self-tests.sh` prints failures only after the whole pool has finished. Its header says so: "a red test does not hide the ones after it: every test runs, then each failure's full log is printed at the end". The verdict-collection loop prints `FAIL` banners only after both `schedule` calls return. The one thing it streams as it happens is a TIMEOUT (the watchdog's `.hang` report).

**Measured (ci-slot run logs `~/.local/state/loomwright/ci-slots/dd8a9612cd818d9a/runs/`, 2026-10-08, attributed by tree key):** PR #435's item made 9 full runs, 639–836 s each (6114 s ≈ 102 min in total). 4 failed. 3 of those 4 were caught only by static gates or by fast, deterministic self-tests, yet each took the full wall time to say so:

| Run (tree key, start) | Wall | What failed | Cheapest thing that catches it |
|---|---|---|---|
| `b8f9698…` 12:54Z | 646 s | `check-vendor-coupling.sh` + `test-check-vendor-coupling.sh` (case15 "live repo passes its own ratchet") + `test-automate-helpers-dispatch.sh` (`--help`/`-h`/no-arg output differs from `automate-helpers-help.golden`) + `test-citation-drift.sh` ("2 pinned citation(s) have DRIFTED") | `check-vendor-coupling.sh` (7 s) + dispatch test (11–12 s) + citation-drift (6 s) |
| `3e7bc89…` 14:29Z | 836 s | vendor-coupling pair + gate `19-build-capabilities.sh` (`build-capabilities.sh --check`, stale `capabilities.json`) + `test-build-capabilities.sh` | `check-vendor-coupling.sh` + `build-capabilities.sh --check` (1–2 s) |
| `e615441…` 14:45Z | 658 s | `test-automate-lanes.sh` S6 (`--keep-awake`; the same tree passed on the immediate rerun at 14:56Z) | not catchable early: a race, item 07 |
| `96b9fcf…` 15:31Z | 639 s | vendor-coupling pair | `check-vendor-coupling.sh` (7 s) |

Per-entry times are from the passing logs of the same item (`1095661…`, `2503f9…`, `d0dd0c…`, `e615441…-1139`). They were measured inside the 6-way pool, so they are upper bounds. The pure static gates (every ci.yml gate that is not a `scripts/test-*.sh` — 13 of the 20) total ≈16–17 s of test time. All 20 gate wrappers, self-tests included, total ≈126 s (`test-ci-local.sh` 45 s, `test-check-vendor-coupling.sh` 31–32 s and `test-check-doc-currency.sh` 26–28 s are the heavy ones). The whole pool totals ≈2808 test-seconds at 6 jobs: ≈470 s ideal against ≈650 s wall.

`--affected` has the matching gap. Its cheap-gate filter (the `case "$s" in scripts/check-*.sh|scripts/validate-version.sh)` arm in the `--- --affected:` block) matches only those two name shapes, so it never schedules `loomwright/scripts/build-capabilities.sh --check`. That is the gate that went red in run `3e7bc89…`. A dismissed Phase 4.5 follow-up already records this: `.supervisor/requirements/proposed/automate-2026-10-07-055816--01-published-capability-contract-fbc9f7--dismissed-summary.md` Entry 1, key `ae6f354e` (PR #412, LOW, "ci-local.sh --affected skips the capabilities --check gate on agent/command/skill/hooks.json edits"). **This item folds it in and closes it.**

CI parity is not at risk. GitHub CI already fails early in effect: ci.yml runs each static gate as its own step before the "Run full deterministic self-test suite" step, and a failing step stops the job. On run 37809076650 (`783b00b`) the static gate steps were done 31 s after checkout. Only the local mirror flattens everything into one end-of-run report.

#### Goal
A full `ci-local` run whose tree breaks a cheap gate or an `early`-marked self-test exits 1 within ≈1–2 minutes (slot acquire + early phase), not after ~650–840 s. A green tree still runs every gate and every test exactly once and stamps as today. Expected saving on PR #435: the 3 catchable red runs (646 + 836 + 639 s ≈ 35 min) become ~1–2 min each.

#### Scope
1. **Early set, derived, never hand-listed (`scripts/ci-local.sh`).** The early set is:
   - (a) every ci.yml gate the existing `gates=()` derivation finds whose script basename is not `test-*.sh`. That is every `scripts/check-*.sh` / `scripts/validate-version.sh` line with its argument (`--self-test` forms included) **and** every `loomwright/scripts/<x>.sh --check` line (today `build-capabilities.sh --check`). A new gate of either shape joins the early phase automatically.
   - (b) every planned self-test (root or loomwright) that carries the exact line `# run-self-tests: early`.

   The rule is structural (by gate shape and marker), not a list of file names.
2. **One marker parser (`loomwright/scripts/run-self-tests.sh`).** Add the `# run-self-tests: early` marker next to `serial`, with the same `grep -qx` exact-line rule, documented in the header's `marker:` paragraph. Do not re-implement the grep in ci-local. Expose it from the runner instead (e.g. `run-self-tests.sh --select-marked early <tests…>` prints the marked subset in input order), so the two markers keep one parser. In the runner's own default run (what CI's suite step calls), an `early` marker changes nothing: the test stays in the concurrent batch. A test carrying both `early` and `serial` is a usage error (exit 1, named), because the two phases conflict.
3. **Mark the measured-fast candidates, after measuring each alone.** Run each with `time bash <test>` on an idle machine, record the number in the PR body, and mark only those that are deterministic and ≲15 s alone:
   - `loomwright/scripts/test-automate-helpers-dispatch.sh` (help golden; 11–12 s in the pool)
   - `loomwright/scripts/test-citation-drift.sh` (6 s in the pool)

   `scripts/test-check-vendor-coupling.sh` is a ci.yml gate already. It is a `test-*.sh` wrapper, so it is not in (a). At 31–32 s it is not "fast", and its case15 failure was always accompanied by `check-vendor-coupling.sh` (7 s) failing on the same live tree in all three vendor-coupling runs above. So `check-vendor-coupling.sh` in (a) already catches that class. Do not move it early unless the measurement contradicts this, and say so either way.
4. **Early phase in a full run.** After the slot acquire and the post-slot cache re-check, and before the pool:
   - Run the early set through the same runner (`bash "$runner" <early…>`), so the watchdog, the hermetic layer and the fail-closed rules are identical. The nested call folds into ci-local's slot (ci-slot.sh NESTED, as today).
   - **Early red:** print every early failure, not just the first. The runner already runs all of its arguments and prints each failing log; run `b8f9698…` had three distinct early-catchable failures. Then `rm -f "$stamp"` as the pool-failure path does, set a verdict that starts with `ci-local: FAIL` (e.g. `ci-local: FAIL after <n>s — early gates failed; pool skipped (nothing cached)`) so `--last` and `--wait` parse it unchanged, write no PASS stamp, and exit 1 without starting the pool.
   - **Early green:** run the pool with the remaining entries only. Every full-plan entry runs exactly once across the two phases.
   - The tree-moved check and the stamp at the end are unchanged.
5. **Stream FAIL lines as they happen (`run-self-tests.sh`).** When a test finishes non-zero, print one line at once, e.g. `run-self-tests: FAIL (exit <rc>, <secs>s): <test>`, in addition to (not instead of) the full banner and log at the end. Mirror how the TIMEOUT path already reports from the worker. This applies to the pool and the early phase alike, so a reader of a running log, or of `--wait` output, sees a red test within seconds. The end-of-run report and its order (passes, slowest tests, failures last, the `N of M self-tests FAILED` summary) are unchanged.
6. **`--affected` uses the same early set.** Replace the `scripts/check-*.sh|scripts/validate-version.sh` filter with the early-set predicate from step 1. `build-capabilities.sh --check` and the `early`-marked tests then always run under `--affected`, which closes `ae6f354e`. Rename the "cheap gates" wording in its messages and counts to the early-set term. Keep the `refusing to report green on an empty plan` refusal, and keep the "never reads, writes or removes a pass stamp" rule.
7. **`--list` shows the phases.** A full `--list` marks which planned entries are early (e.g. an `early:` prefix, or a separate block). `--affected --list` shows the same early set. Keep the "no temp wrapper paths" rule of arm (LS).
8. **Docs in the same change.** Update the ci-local header (`SAME GATES AS CI`, `--affected`, a new early-phase paragraph), the run-self-tests header (`marker:`), and `AGENT_GUIDELINES.md` §"Pre-push: one command" (the `--affected` bullet's "cheap `check-*`/`validate-version` gates" wording).
9. **Sequencing with pending work (not a dependency).** `automate-followups/34` Part B and `automate-followups/36` Part C also edit `scripts/ci-local.sh` (and 36 edits `scripts/test-ci-local.sh` and `AGENT_GUIDELINES.md`). Run them sequentially with this item, never in one parallel wave. The shared `## Touches` lines already keep the wave planner from co-scheduling them. PR #438's `--wait` is merged. Build on it: the early-red verdict must be what `--wait` returns.

#### Acceptance criteria
- A full run on a tree with a red early gate exits 1 with a `ci-local: FAIL …` verdict as the log's last content line. It names every red early entry (fixture: two early gates both red ⇒ both printed), starts no pool entry (a pool sentinel test did not run), leaves no PASS stamp (an existing stamp for the key is removed), and `--last` reports `FAIL <log>`.
- A green tree runs every full-plan entry exactly once across the two phases (fixture: each entry appends to a ledger; no duplicates, none missing) and stamps as today. Arms (P), (C), (U), (F), (O), (M), (X), (Q), (QC), (LG), (LA1–3), (UV) and (PR) still pass.
- The early set is derived. A fixture ci.yml with a new `scripts/check-new.sh` line and a `loomwright/scripts/gen.sh --check` line puts both in the early phase with no edit to ci-local. A `scripts/test-*.sh` gate stays in the pool. A fixture test carrying `# run-self-tests: early` runs early; the same test with the marker removed runs in the pool (mutation control).
- A copy of ci-local that skips the early-red exit is caught by the early-red arm (mutation control).
- `run-self-tests.sh` streams a `FAIL` line for a red test before the end-of-run report (fixture: a fast red test plus a slow green test; the FAIL line precedes the slow test's PASS line in the output). The end report is unchanged. `test-run-self-tests.sh` arms (F), (C) and (S) still pass. A test marked both `early` and `serial` exits 1, named.
- `--affected` runs `build-capabilities.sh --check`-shaped gates and `early`-marked tests: an (AF1)-style fixture with a `--check` gate shows it ran. (AF5) "empty changed set ⇒ early set only" holds, and the empty-plan refusal still fires when the early set and the mapped set are both empty.
- On the real repo, `ci-local --list` shows the early set: the 13 non-`test-*` ci.yml gates today plus the marked tests (the exact count goes in the PR body as evidence, never restated in docs).
- The real-repo early phase is measured: wall time of a forced early-red run (e.g. a deliberately stale `capabilities.json` in a scratch worktree) from `ci-local` start to verdict, recorded in the PR body. Target ≤ 120 s including slot acquire on an idle machine.

#### Validation (must pass before merge)
1. `bash scripts/ci-local.sh` green (the full run, early phase included), with its log path in the PR body.
2. New `test-ci-local.sh` / `test-run-self-tests.sh` arms fail on the base commit and pass on the branch.
3. The forced early-red measurement above, plus one green full run's wall time before vs after on the same machine. Expected roughly unchanged: the early set is a few seconds and leaves the pool.
4. Operator follow-up after merge (the file is gitignored, so it is not in the worktree): remove Entry 1 (key `ae6f354e`) from `.supervisor/requirements/proposed/automate-2026-10-07-055816--01-published-capability-contract-fbc9f7--dismissed-summary.md`, citing this item's PR.

#### Non-goals
- Skipping or caching any part of the full run beyond today's whole-tree PASS stamp (D1). The early phase reorders the run. It never shortens a green one.
- Changing CI's suite step behaviour. ci.yml's own steps already stop at the first failure. The `early` marker is inert in a default `run-self-tests.sh` run.
- Stopping at the first early failure. Every early entry runs, so one fix round sees all of them.
- Making `test-check-vendor-coupling.sh`, `test-check-doc-currency.sh` or `test-ci-local.sh` early. They are 26–45 s, and their live-repo arms duplicate gates already in (a).
- Fixing the S6 race (item 07) or the serial tail (item 06).

---

## Part T06 — 06 — Remove the serial tail: make the three `serial` tests pool-safe, so a full run fits under 540 s

*Source: `.supervisor/requirements/throughput/06-remove-serial-tail.md` (now superseded). Part touches:* `loomwright/scripts/test-ci-slot.sh`, `loomwright/scripts/test-build-floor.sh`, `loomwright/scripts/test-harvest-conventions.sh`, `loomwright/scripts/run-self-tests.sh`, `loomwright/scripts/test-run-self-tests.sh`, `loomwright/scripts/test-automate-trail.sh`, `loomwright/scripts/test-automate-trail-closeout.sh`, `loomwright/scripts/test-automate-trail-merge-watch.sh`, `.github/workflows/ci.yml`

#### Problem
`loomwright/scripts/run-self-tests.sh` runs every test that carries the exact line `# run-self-tests: serial` ALONE, one at a time, after the concurrent batch. Its header `marker:` paragraph and the block above `par_idx=(); ser_idx=()` describe this: "for tests that measure wall-clock time and need an idle machine". The same script is the GitHub CI suite step, so the tail is paid locally and on every push.

**Measured (ci-slot run logs, 2026-10-08; every PR #435 log reads `152 concurrently (6 at a time), then 3 serially`):** three tests are marked, and their serial run adds a fixed tail to every full run:

| Test | Time (4 passing logs) | Reason the file gives for `serial` |
|---|---|---|
| `test-ci-slot.sh` | 111–113 s | **none.** The marker sits alone below the arms list, with no explanation. It has been there since the file was created (commit f0b6f01, 2026-10-04). |
| `test-build-floor.sh` | 38–39 s | Line-3 note: "case (x) is a calibrated wall-clock runtime ratio; under a loaded concurrent run it measured 183-222 units against its 180 bound" |
| `test-harvest-conventions.sh` | 27–29 s | Line-3 note: "(M1) feeds 'y' to a PTY after a fixed `sleep 1`; under load the writer has not reached its prompt yet and the control reads as vacuous" |

That is ≈181 s of serial tail per full run. The concurrent batch is ≈470 s of ideal work (≈2808 test-seconds / 6 jobs) against ≈650 s wall. The full run therefore does not fit the 600 s an agent's Bash call may block (`AGENT_GUIDELINES.md` §"Pre-push: one command": "A full run takes about 10 minutes, longer than one agent tool call may block (600 s)"). That is why PR #438 had to add `ci-local.sh --wait`.

The single-test floor is `test-automate-trail.sh` at 386–398 s, the slowest test in every log. It is 2473 lines with 38 `echo "== X. … =="` sections: sidecar-check, dispatcher, trail-pr, closeout ×10, evidence-gated stamps, retract, dismissed drafts, `== W. merge watcher ==` and `== WE. escalated park … ==` (AC13 / M2 / E7 / repark, about 450 lines), branch mode, finalize, closeout-classify, closeout-others and lane-clone. Even with no serial tail, the pool cannot finish sooner than its longest test.

What the brief got partly wrong, and the reshaped goal: **test-ci-slot.sh does not read the real machine.** Its setup block sandboxes `XDG_STATE_HOME`, `LOOMWRIGHT_MACHINE_STATE_DIR` and `LOOMWRIGHT_MACHINE_LOAD_CMD` (a fixture `load.sh`), and `LOOMWRIGHT_CI_CPUS` is set per arm. So "it measures admission under real load" is not why it is serial. The likely reason is wall-clock margins: elapsed-time bounds (`t0=$(date +%s)` … `el` checks such as `[ "$el" -gt 3 ]`), `--wait 1` timeouts, `sleep 1.2` "at least one more progress period", and the G10/G13 5 s reader wait against a 6 s `slow` fixture reader (a 1 s margin). This is a hypothesis. This item measures it rather than assumes it.

`run-self-tests.sh` already records the preferred repair. Its comment cites `test-write-agent-memory.sh` (j5/X): "marked too and STILL flaked under outside load, then was made deterministic (barriers instead of sleeps) and unmarked — prefer that repair whenever the ordering can be pinned".

#### Goal
No test needs the serial tail, or the tail that is left is ≤ 30 s with a written, measured reason per remaining marker. A full `bash scripts/ci-local.sh` on this machine finishes in ≤ 540 s wall, which fits one foreground agent Bash call (600 s) with margin. GitHub CI's suite step loses the same tail.

#### Scope
1. **Measure first, per test.**
   - Run each marked test 10× inside a loaded concurrent pool: with the marker removed, alongside the heaviest tests (e.g. `run-self-tests.sh` over the test plus `test-automate-trail.sh`, `test-meta-sync.sh`, `test-setup-ui.sh` at 6 jobs).
   - Record which arms fail and by how much.
   - For `test-ci-slot.sh`, find out which arms actually need an idle machine. The file states no reason, so this measurement is the evidence.
2. **Repair, preferring determinism over isolation:**
   - **`test-ci-slot.sh`:** replace elapsed-wall-clock assertions with event-driven ones where the property is ordering, not duration. Examples: wait on `status --json` reaching a state, or on a file appearing, with a bounded deadline, instead of asserting `el -le N`. Where a duration IS the property (a bounded `--wait N`, the G13 "bounded by the clock" arm), widen the margin so it is relative to the fixture's own timing (e.g. the fixture reader sleeps a multiple of the bound), never an absolute number tuned to an idle laptop. Keep every MUTATION CONTROL red against its mutant.
   - **`test-build-floor.sh` (x):** the ratio is calibrated in the same run, but the unit (one `jq` scan) and the projector are measured at different moments, so load that varies between them moves the ratio. Candidate repairs, chosen by measurement:
     - measure child **CPU** time (user+sys via `getrusage(RUSAGE_CHILDREN)` in the existing python3 measurement) instead of wall time;
     - interleave several unit/projector samples and take the minimum of each.

     Keep the bound's property: the consolidated readers must sit well below and the pre-consolidation code well above. Re-run the historical arm (`PERF_PRE_SHA`) where git history allows and record both ranges. The file's comment block rejects counting `jq` invocations (37 vs 35): do not reintroduce it.
   - **`test-harvest-conventions.sh` (M1):** replace the fixed `sleep 1` before feeding `y` with a wait for the prompt. Poll the PTY transcript for the prompt text with a bounded deadline, then feed. A deadline miss is a FAIL naming the missing prompt, never a vacuous pass. (M1a)'s "CONFIRMED the hazard is real" control must still go red on its mutant.
3. **Unmark only what is proven safe.** Remove `# run-self-tests: serial` from each repaired test, then run it 10× in the loaded pool with zero failures. Any test that still genuinely needs an idle machine keeps the marker. Its marker line then gets a one-line reason (as build-floor and harvest-conventions have today) and the measured failure rate under load. If two or more stay marked and they do not interfere with each other, they may run as a small concurrent batch instead of one at a time. Measure that too, and change the `schedule 1` call in the runner only if it helps.
4. **Split `test-automate-trail.sh` only if the sections are independent and it pays.**
   - Check what the sections share: the `stub gh` block, `$P`/`$TOP` fixtures, spy logs, and state set by earlier sections.
   - If clusters can be separated, split along the natural seams into independent files, each sourcing `hermetic-test-env.sh` first (`scripts/check-test-hermetic.sh`). Proposed seams: closeout (the `== C. … ==` / `== CL. … ==` / `== CO. … ==` sections) and the merge-watch block (`== W. ==` + `== WE. ==`: AC13 single-instance, M2 replace, (E7) AC9 double-arm, repark). The rest stays.
   - The two new file names in Touches, `loomwright/scripts/test-automate-trail-closeout.sh` and `loomwright/scripts/test-automate-trail-merge-watch.sh`, are **NEW** (neither exists today) and are proposals. If the measurement picks other seams, update `## Touches` before starting. If the split does not lower the pool's critical path by ≥ 60 s, do not split, and record the measurement in the PR body.
   - Shared setup moves into a sourced helper only if it already exists as a function. Do not invent a framework.
5. **Docs in the same change.**
   - `run-self-tests.sh`'s header `marker:` paragraph and the comment above `par_idx`: state which tests (if any) remain serial and why. The "Observed flaking … test-build-floor.sh (x), test-harvest-conventions.sh (M1a)" sentence must stay true.
   - `.github/workflows/ci.yml`'s `timeout-minutes` comment ("one hang in the concurrent batch, one in the serial phase after it", "A green run takes ~8 min"): update it to the measured reality.
   - `test-run-self-tests.sh` arm (S) keeps testing the marker mechanism, which stays even if no committed test uses it.
6. **Sequencing.** `automate-followups/34`, `automate-followups/36` and item 07 all touch `loomwright/scripts/test-automate-trail.sh`. The shared Touches line keeps them in different waves. If 07 lands first, the split carries its fixes. Item 08 depends on this item.

#### Acceptance criteria
- Each remaining `# run-self-tests: serial` marker carries a written reason and a measured failure rate under the loaded pool. Each removed marker has 10/10 green runs in a loaded pool recorded in the PR body.
- Serial tail (the sum of the serial phase) ≤ 30 s, read from the `slowest tests` timings of a real full run.
- A full `bash scripts/ci-local.sh --force` on this machine finishes in ≤ 540 s wall. Measure before and after on the same machine with the same `SELF_TEST_JOBS` and an otherwise idle slot pool, and put both log paths in the PR body.
- Every mutation control in the touched tests still goes red on its mutant (the G13 iteration-bounded mutant, build-floor's historical arm where reachable, (M1a)).
- If `test-automate-trail.sh` is split: the union of the new files' assertions equals the original. The PR body carries the `passed:` counts before and after, and `test-suite-helpers-defined.sh` stays green. The new longest test is recorded.
- The `run-self-tests.sh` header claim about the serial marker matches what the code and the marked files now do.

#### Validation (must pass before merge)
1. `bash scripts/ci-local.sh` green; the before/after wall times and log paths in the PR body.
2. The 10× loaded-pool runs per unmarked test (command and result counts in the PR body).
3. GitHub CI on the PR: the suite step's wall time against the 10m12s baseline (run 37809076650, `783b00b`), with the `running … then N serially` line quoted.

#### Non-goals
- Raising `SELF_TEST_JOBS` or the slot count. Two concurrent full runs took ~830 s against ~650 s solo (`00-overview.md` §"Considered and NOT queued").
- Sharding CI (item 08) or adding an early phase (item 05).
- Removing the `serial` marker mechanism itself: `test-run-self-tests.sh` (S) covers it, and a future wall-clock test may need it.
- Speeding up a test by deleting assertions. A split moves assertions. It never drops them.

---

## Part T07 — 07 — Fixed-sleep test races: wait on the condition, not the clock (S6 and its class), plus a guard

*Source: `.supervisor/requirements/throughput/07-fixed-sleep-test-races.md` (now superseded). Part touches:* `loomwright/scripts/test-automate-lanes.sh`, `loomwright/scripts/test-automate-trail.sh`, `loomwright/scripts/test-setup-ui.sh`, `loomwright/scripts/wait-lib.sh`, `loomwright/scripts/test-wait-lib.sh`, `loomwright/scripts/test-no-fixed-sleep-race.sh`

#### Problem
**S6 is a confirmed flake that was never filed.** In `loomwright/scripts/test-automate-lanes.sh`, the `# ---- S: keep-awake` block runs `out="$(run lane-status "$RF2" --keep-awake)"; sleep 0.3` and then asserts `has "S6 --keep-awake starts it, tied to the coordinator" "$(cat "$CAFF_LOG")" "caffeinate -i -w 4242"`. The caffeinate stub (`$T/caff-stub`, which appends `caffeinate $*` to `$CAFF_LOG`) is started in the background by `lane-status --keep-awake` (`automate-lanes.sh`, `LOOMWRIGHT_LANES_CAFFEINATE`). The 0.3 s sleep races that background write. The ci-slot run logs (`~/.local/state/loomwright/ci-slots/dd8a9612cd818d9a/runs/`) show `FAIL - S6 --keep-awake starts it, tied to the coordinator`, with S6b ("and says so") green, in two runs:
- `5656bf…-20261008T093018Z` (09:30Z, a 4190 s run under heavy load);
- `e615441…-20261008T144512Z` (14:45Z, 658 s). The same tree passed on the immediate rerun at 14:56Z (`e615441…-145627Z`).

That cost PR #435's item one full 658 s run (`00-overview.md`: "1× S6 `sleep 0.3` race").

**The class.** `grep -nE "sleep 0\.[0-9]" loomwright/scripts/test-*.sh scripts/test-*.sh` matches **95** lines today, across 19 files. Classified by reading each site:

- **(a) inside a bounded poll loop — fine (80 lines).** For example `wait_gone`, the `i=0; while … && [ "$i" -lt N ]; do sleep 0.1; …` waits, `nwait`/`xwait` in test-ci-slot, `s_wait_gone`/`n_wait_up` in test-setup-ui, and the meta-sync rendezvous loops.
- **(b) fixed sleep, then an assertion on async state — a race. Fix all in this item (5 lines):**

  | File | Case | Site |
  |---|---|---|
  | `test-automate-lanes.sh` | **S6** `--keep-awake starts it, tied to the coordinator` | `lane-status … --keep-awake; sleep 0.3`, then reads `$CAFF_LOG` (failed twice, above) |
  | `test-automate-lanes.sh` | **N8** `live merge watcher refused` | backgrounds the merge-watch stub, `sleep 0.3`, then `lane-remove`, whose `_lanes_live_watchers` matches the pid's `ps` command line (`*automate-merge-watch*<pr_url>*`). Under load the child may not have exec'd yet. |
  | `test-automate-trail.sh` | `== W. merge watcher ==`, **"dead-pid marker is reclaimed"** | `( sleep 0 & echo $! > "$TOP/deadpid" ); sleep 0.2` assumes that pid is already dead before the reclaim launch |
  | `test-automate-trail.sh` | **(E7) AC9 (1)–(3)** in `dbl_arm` | after the first status line appears in the second launch's log, `sleep 0.3`, then asserts that log's WHOLE content equals one line and the first watcher is alive. This is a fixed quiet period. Wait for the second launcher to exit instead (it exits after `already running`). |
  | `test-setup-ui.sh` | the reap helper behind **(p6)** ("a TERM-ignoring process is gone") | after `kill_if_fixture … KILL`, `sleep 0.25`, then the survivors are read into `REAP_LEFT`, which (p6) asserts empty. A KILLed, reparented process can still be listed until it is reaped. |

- **(c) settle-before-action or quiet-period negatives — keep, but annotate why (4 lines).** None of these assert on async output directly. They are either vacuity risks (too short ⇒ the test exercises a different path and still passes) or absence checks a condition-wait cannot express:
  - `test-automate-lanes.sh` `aa_feed` (AA-F12a–c): `sleep 0.3; kill -"$sig"`;
  - `test-automate-trail.sh` M2: `sleep 0.5   # A is now inside its 30s interval nap`;
  - `test-ci-slot.sh` (X) `mixed_ok`: `sleep 0.6`, then "N=1 waiter took a slot";
  - `test-ci-slot.sh` interrupt arm: `sleep 0.3   # past the claim attempt, into the poll wait`.
- **(d) not a wait (6 lines):**
  - `test-ci-slot.sh`: two comments, the `slowsleep` stub's content, and the G13 `sed` mutant pattern;
  - `test-token-ledger.sh`: a `sleep 0.3` injected into a mutant to widen a race on purpose;
  - `test-setup-memory.sh`: a `sleep 0.05` capability probe.

**The brief's regex misses whole-second sleeps.** A second heuristic, `sleep [1-9]…` excluding `sleep N &` holder processes, matches ~66 more lines. Most of them are legitimate:
- mtime or timestamp separation: `test-set-otel-resource-attrs.sh`, `test-token-ledger.sh`, `test-verify-queue.sh`, `test-worktree-audit.sh`;
- stub bodies;
- `test-agent-identity.sh`'s "The `sleep 1` is the assertion" case.

At least one more belongs to this item's class: `test-automate-lanes.sh` **AA-F12e** ("the unescaped pattern T8 used never matched a live tail") runs `sleep 1; pgrep -f "<unescaped>" && echo matched || echo unmatched` and expects `unmatched`. On a slow start the tail is not up yet, so `unmatched` passes for the wrong reason. It should first wait until the ESCAPED pattern sees the tail, as `aa_feed` does, then probe the unescaped one. `test-harvest-conventions.sh` (M1)'s `sleep 1` PTY feed is item 06's.

**Is there a shared helper to put a wait function in? Not really.** The only file every test sources is `loomwright/scripts/hermetic-test-env.sh` (all 143 covered test files today; it must be the first executable line, `scripts/check-test-hermetic.sh`). Its header scopes it to egress: (a) scrub egress env vars, (b) desktop-notification opt-out, (c) the notifier/curl/wget recording stubs, (d) `HERMETIC_TEST_ENV=1`, (e) never touch HOME. A wait helper there would mix an unrelated concern into a fail-closed egress layer, which `run-self-tests.sh` also sources for every worker. No other sourced test library exists, and each test defines its own poll loop today.

#### Goal
No test asserts on async output after a fixed sleep. Every such wait is a bounded poll on the condition the assertion reads, and a deadline miss fails with the condition named. A new fixed-sleep-then-assert cannot land unnoticed.

#### Scope
1. **Shared helper (NEW `loomwright/scripts/wait-lib.sh`).** A sourced library. It is deliberately NOT named `test-*.sh`: the `run-self-tests.sh` glob would run it as a test, and `check-test-hermetic.sh` covers only `test-*.sh`. It holds a few bounded waits, bash 3.2 safe, with no GNU-only flags:
   - `wait_for_file_content <file> <fixed-string> <timeout_s>`
   - `wait_for_pid_gone <pid> <timeout_s>`
   - `wait_for_cmd <timeout_s> <cmd…>` (true when the command succeeds)

   Each polls at 0.1 s, bounds by the CLOCK rather than an iteration count (the G13 lesson in `test-ci-slot.sh`: a slow `sleep` stretched a count-bounded wait to ~15 s), returns 0 or 1, and never exits the caller. Its own self-test is NEW `loomwright/scripts/test-wait-lib.sh`, with the hermetic source line first. It covers: a condition that becomes true after 0.5 s, a timeout, a slow `sleep` on PATH (the clock bound holds), and a mutation control (a count-bounded copy fails under the slow sleep).
2. **Fix every (b) site in the table, plus AA-F12e,** using the helper or an equivalent local bounded poll:
   - **S6:** `wait_for_file_content "$CAFF_LOG" "caffeinate -i -w 4242" 5`, then assert.
   - **N8:** wait until `ps -o command= -p "$WPID"` shows the watcher, then run `lane-remove`.
   - **Dead-pid reclaim:** `wait_for_pid_gone` on the recorded pid before writing the marker.
   - **(E7) `dbl_arm`:** capture the second launcher's pid and wait for it to exit before reading its log.
   - **(p6) reap helper:** poll for the survivors to clear with a bound before setting `REAP_LEFT`.

   Each fix keeps its assertion's meaning, and each must FAIL when the condition never becomes true. Show this with a stub that never writes, plus a mutation control per fixed case.
3. **Annotate the (c) lines.** Give each a short trailing comment saying why it is a settle or quiet period, and the vacuity risk if it is too short. Change one to a condition wait only where that is clearly possible: `aa_feed` already waits for the tail to be seen, so its `sleep 0.3` may not be needed at all. Measure before removing it.
4. **Guard (NEW `loomwright/scripts/test-no-fixed-sleep-race.sh`).** A lint-as-self-test, modeled on `loomwright/scripts/test-no-pipefail-grep-q.sh`: a per-file count RATCHET (its `WRITER_BASELINE` pattern) over `loomwright/scripts/test-*.sh`, `loomwright/scripts/adapters/*/test-*.sh` and `scripts/test-*.sh`. It is auto-included by the suite glob, so CI runs it with no ci.yml edit.
   - **What it counts:** a `sleep <literal>` statement that is not on a loop line (`while`/`until`/`for` … `do`, or inside a `do … done` body) and not on a comment line. Heredoc bodies are skipped, reusing the heredoc-awareness approach of `test-suite-helpers-defined.sh`.
   - **The ratchet:** any increase, or any file not in the baseline, is red. A count that falls without the baseline being lowered is also red, so the baseline only shrinks.
   - **Escape hatch:** a trailing `# fixed-sleep-ok: <reason>` on the same line exempts that site. This is how the (c) and (d) sites and the legitimate whole-second ones stay green with a written reason.
   - **Controls:** the guard ships with controls proving it can fire, e.g. a fixture with a new `sleep 0.3` + `has …` pair ⇒ red, and the same pair inside a bounded `while` ⇒ green.
5. **Sequencing.**
   - `automate-followups/34` touches `test-automate-trail.sh` and `test-setup-ui.sh`.
   - `automate-followups/36` touches `test-automate-trail.sh`.
   - Item 06 may split `test-automate-trail.sh`.

   The shared Touches lines keep these items out of one wave. Whichever lands second rebases onto the other's version of the file.

#### Acceptance criteria
- S6 passes 50/50 under a loaded pool, e.g. `run-self-tests.sh` over `test-automate-lanes.sh` ×1 plus the heaviest tests at 6 jobs, repeated. On the base commit it fails at least once in the same harness with the stub delayed: a `caffeinate` stub that sleeps 0.5 s before writing reproduces the race deterministically, so the PR shows red on base and green on branch.
- Every (b) site in the table and AA-F12e is rewritten. For each one, a delayed-stub (or never-writing-stub) variant shows: the new wait succeeds when the condition arrives late (but within the bound), and fails, naming the condition, when it never arrives.
- `wait-lib.sh` exists with `test-wait-lib.sh` green, including the slow-`sleep` mutation control.
- `test-no-fixed-sleep-race.sh` is green on the branch. It is red on a fixture adding one new fixed-sleep-then-assert, green on the same sleep inside a bounded loop, and green on a `# fixed-sleep-ok:` annotated line. Its baseline lists every file and count it accepts, and the PR body explains each non-zero count, or each count is covered by annotations.
- The (c) lines carry their reason comments, and no (b)-class site remains un-annotated, as the guard proves.

#### Validation (must pass before merge)
1. `bash scripts/ci-local.sh` green.
2. The S6 delayed-stub repro: red on the base commit, green on the branch (commands and output in the PR body).
3. The loaded-pool 50× run for `test-automate-lanes.sh` (count of passes in the PR body).

#### Non-goals
- Rewriting (a) poll loops onto the new helper. They are correct, and churn there is risk without benefit.
- Making the quiet-period negatives (c) event-driven. "Nothing happened for T seconds" has no event to wait on. They get a reason comment and stay under the guard's annotation.
- Whole-second sleeps that separate timestamps or mtimes (e.g. `test-set-otel-resource-attrs.sh`, `test-token-ledger.sh`). They are not waits on async output, and the guard exempts them by annotation.
- `test-harvest-conventions.sh` (M1)'s PTY feed and the serial markers (item 06).
- A guard with no false positives. The ratchet-plus-annotation shape accepts that a line-based heuristic cannot fully parse bash. It only has to stop the count from growing silently.

---

## Part T08 — 08 — Shard GitHub CI's self-test suite across a job matrix, keeping the required `ci` check fail-closed

*Source: `.supervisor/requirements/throughput/08-ci-suite-shard.md` (now superseded). Part touches:* `.github/workflows/ci.yml`, `loomwright/scripts/run-self-tests.sh`, `loomwright/scripts/test-run-self-tests.sh`, `scripts/test-ci-local.sh`, `loomwright/scripts/fixtures/self-test-weights.tsv`

#### Problem
`.github/workflows/ci.yml` has one job, `ci`. Inside it, the "Run full deterministic self-test suite (hard gate)" step calls `bash loomwright/scripts/run-self-tests.sh`, and that step dominates every push.

**Measured on PR #435's five pushes (`gh run list --workflow ci.yml`, check-runs per commit):**
- The `ci` run took 11.6–15 min per push:
  - `87f2205` 11m37s
  - `3a1cf14` 14m56s
  - `842cbe7` 11m51s
  - `77fc06b` 13m36s
  - `783b00b` 12m00s
- `claude-review` finished first on all five, so `ci` is the critical path of every push.
- On run 37809076650 (`783b00b`), step timestamps show:
  - the static gate steps (version … capability contract) done 31 s after checkout (16:28:42Z → 16:29:13Z);
  - `test-ci-local.sh` 40 s;
  - the suite step alone **10m12s** (16:29:57Z → 16:40:09Z);
  - sdk-spike 8 s.
- That suite step logged `running 134 self-tests: 131 concurrently (4 at a time), then 3 serially` and `all 134 self-tests passed (wall 612s, 4-way)`. Its per-test PASS times sum to 1846 test-seconds. That is ≈462 s of ideal 4-way work plus a 145 s serial tail: `test-ci-slot.sh` 103 s, `test-harvest-conventions.sh` 24 s, `test-build-floor.sh` 18 s. Item 06 removes that tail.
- The CI floor is the longest single test: `test-automate-trail.sh` 235 s on the runner. Next come `test-verify-walkthrough.sh` 149 s, `test-setup-ui.sh` 134 s and `test-meta-sync.sh` 121 s.

So one 4-vCPU runner is CPU-bound on ≈1846 test-seconds. Sharding the suite over N runners divides the batch part by N, down to the longest-test floor. It cannot help while a serial tail stays inside a shard, which is why this item depends on 06.

**Constraints that are easy to break:**
- **The required check.** `gh api repos/vikashruhilgit/loomwright/branches/main/protection` (read 2026-10-09) shows `required_status_checks.contexts: ["ci"]`, `checks: [{context: "ci", app_id: null}]`, `strict: true`, plus 1 required approving review.
  - Matrix jobs report as `<job> (<k>)`, so the `ci` context must still be produced by exactly one job.
  - **A job skipped because a `needs:` dependency failed reports `skipped`, and GitHub treats a skipped required check as passing.** An aggregating `ci` job with a plain `needs:` would therefore turn a red shard into a mergeable PR. It must run with `if: always()` and fail unless every needed job's `result` is `success`.
- **ci-local derives its gates from ci.yml text.** The `gates=()` block in `scripts/ci-local.sh` greps the whole file for `bash (scripts/<x>.sh( --self-test)?|loomwright/scripts/<x>.sh --check)`. Any NEW `bash scripts/<x>.sh` line, such as an aggregator script, would silently become a ci-local gate. The shard invocation (`bash loomwright/scripts/run-self-tests.sh --shard …`) does not match the pattern, which is correct.
- **Other tests read ci.yml text.**
  - `scripts/test-ci-local.sh` (W) needs `bash scripts/test-ci-local.sh` and `bash loomwright/scripts/build-capabilities.sh --check` present.
  - `loomwright/scripts/test-run-self-tests.sh` (W) needs `bash loomwright/scripts/run-self-tests.sh` and a job-level `^    timeout-minutes: [0-9]+` line.
  - `scripts/test-check-vendor-coupling.sh` case14a–f pins the vendor step's `git fetch --no-tags --depth=1 origin +refs/heads/main:refs/vendor-coupling/base`, `VENDOR_COUPLING_BASE: refs/vendor-coupling/base`, `VENDOR_COUPLING_REQUIRE_BASE: "1"`, and no `|| true`.
- **Step ordering that encodes behaviour.** The "Pull run history from the metadata branch" step sits AFTER the suite on purpose: "two of its tests change behaviour when real run history is present". In separate jobs every shard has its own fresh checkout, so the pull can no longer leak into the suite. It must still come after any test step in the job it lives in. The Playwright cache (`LOOMWRIGHT_VERIFY_TEST_CACHE`, key from `read-playwright-pin.sh`) must be restored in whichever shard runs `test-verify-walkthrough.sh`.
- **The claude-review self-skip is not triggered.** Editing `ci.yml` does not trigger claude-code-action's self-skip. Only a PR that edits the review workflow file itself is skipped (verified 2026-10-07: loomwright #412 edited only `ci.yml` and was reviewed every round). So this PR's review is real.

#### Goal
The `ci` required check finishes in roughly (longest single test + per-job setup) rather than ≈10 min of suite. It stays fail-closed: every test reports, a missing or failed shard fails `ci`, and branch protection keeps reading the same `ci` context. Target: the `ci` check ≤ 6 min wall on a typical push (from 11.6–15 min). The exact target comes from 06's new longest-test floor.

#### Scope
1. **Deterministic shard selection (`loomwright/scripts/run-self-tests.sh`).**
   - **`--shard K/N`** (1 ≤ K ≤ N): selects a stable subset of the canonical no-argument suite (the same two globs). Malformed `K/N` or `K>N` exits 1, named. Combining `--shard` with explicit test arguments is a usage error.
   - **`--list`:** prints the selected tests, one per line, and runs nothing. The aggregator uses it.
   - **The split:** pick one by measurement and record why in the PR body.
     - (a) name-hash or round-robin over the sorted list. No data file; balance is uneven.
     - (b) a greedy longest-first split by committed per-test weights, NEW `loomwright/scripts/fixtures/self-test-weights.tsv`, measured from a CI run's PASS times. Every test absent from the file gets a default weight, so a new test is never dropped.

     If (a) is chosen, drop the weights file from Touches before starting.
   - **Invariant, tested:** for every N, the union over K of the `--shard K/N --list` outputs equals the full list, with no duplicates.
   - Serial-marked tests (if 06 leaves any) keep their after-the-batch rule inside the shard that owns them.
   - Admission, watchdog, the hermetic layer and the fail-closed exit rules are unchanged per shard.
2. **Workflow shape (`.github/workflows/ci.yml`).**
   - **A `static` job:** checkout, every existing static gate step verbatim, `test-ci-local.sh`, then the read-only meta-sync pull, sdk-spike, fitness report and eval upload. It keeps the vendor step's env and fetch exactly, so case14 still matches.
   - **A `suite` job:** a `strategy.matrix.shard` over 1..N (choose N by measurement; start at 3–4) with `fail-fast: false`, so every shard reports even when one is red. Each shard restores the Playwright cache, runs `bash loomwright/scripts/run-self-tests.sh --shard ${{ matrix.shard }}/N`, and writes and uploads a per-shard result manifest (each test it ran plus its rc).
   - **A job named exactly `ci`:** `needs: [static, suite]`, `if: always()`. It fails unless `needs.static.result == 'success'` and `needs.suite.result == 'success'`. It downloads every shard manifest and fails closed when a manifest is missing, a test is missing or duplicated against `run-self-tests.sh --list` (the full no-shard list), or any rc is non-zero. Write it as an inline `run:` block. Do NOT add a `bash scripts/<x>.sh` line: ci-local would derive it as a gate.
   - Every job carries a job-level `timeout-minutes` (the `test-run-self-tests.sh` (W) regex). Recompute the 45-minute rationale in the comment per job.
   - No other job may be named `ci`.
3. **Keep every ci.yml-reading test green.** Extend `scripts/test-ci-local.sh` with a fixture ci.yml in the new multi-job shape. ci-local derives exactly the same gate list from it as from the single-job shape, a matrix shard line is never derived as a gate, and a fixture adding an aggregator `bash scripts/agg.sh` line shows the hazard: it IS derived, which is why the real file must not have one. Extend `test-run-self-tests.sh` with `--shard`/`--list` arms: the union invariant, malformed input, args-plus-shard refused, and a test absent from the weights file still scheduled (if (b)).
4. **Docs in the same change:** the ci.yml comments (suite step, `timeout-minutes`, the ci-local mirror note), and the `run-self-tests.sh` header usage.

#### Acceptance criteria
- Branch protection is untouched. On the PR, the `ci` check exists, and it is the job that aggregates. A deliberately red shard on a throwaway commit makes `ci` **fail** (not skip), and `gh pr view --json mergeStateStatus` is not CLEAN. Revert the commit before merge and record the run URL in the PR body.
- A deliberately dropped shard manifest (or a test removed from every shard by a mutated split) makes `ci` fail and names the missing test.
- `bash scripts/ci-local.sh --list` prints the same `gate:` lines before and after the ci.yml change (diff in the PR body).
- `test-ci-local.sh`, `test-run-self-tests.sh` and `test-check-vendor-coupling.sh` are green, and the new arms fail on the base commit.
- **Measured on a real PR:** `ci` check wall time (check-run `started_at` → `completed_at`) for 3 pushes after the change, against the five PR #435 baselines above (11.6–15 min), plus each shard's wall and its longest test. Total runner minutes per push are recorded too. Public repo: no billing block is expected, but the cost is visible.

#### Validation (must pass before merge)
1. `bash scripts/ci-local.sh` green.
2. The red-shard and dropped-manifest probes above, with their run URLs.
3. The before/after `ci` wall times from real PR runs.
4. `gh api repos/vikashruhilgit/loomwright/branches/main/protection` re-read after merge: still `contexts: ["ci"]`, and the next PR's `ci` check comes from the aggregator job.

#### Non-goals
- Changing branch protection, its required contexts, or the review requirement. This is a user-only action, and nothing here needs it.
- Sharding ci-local. Locally the pool is already one machine; items 05 and 06 cover local wall time.
- Editing `.github/workflows/claude-code-review.yml`. That would self-skip the reviewer on this PR.
- Caching test results across pushes, or skipping unaffected tests in CI. Every push still runs every test (owner decision D1's spirit: shrink the run's wall time, never its coverage).
- `concurrency:` cancellation of superseded runs. It is a separate decision with its own trade-off (a cancelled run reports `cancelled`, which a required check treats as not passing).

---

## Part T09 — 09 — Vendor-coupling ratchet, shifted left: a breach says exactly what was added and how to fix it

*Source: `.supervisor/requirements/throughput/09-vendor-coupling-shift-left.md` (now superseded). Part touches:* `scripts/check-vendor-coupling.sh`, `scripts/test-check-vendor-coupling.sh`, `loomwright/docs/vendor-coupling-manifest.json`, `loomwright/docs/ARCHITECTURE_CONTRACTS.md`, `AGENT_GUIDELINES.md`

#### Owner / red-team constraint (binding)
The ratchet must never auto-raise, never exempt silently, and never loosen fail-closed. `scripts/check-vendor-coupling.sh` is a **deliberate**, fail-CLOSED portability gate. Its header says counts "may FALL or stay FLAT, but … may not RISE without a reviewed, REASONED edit to the manifest", and it has "no third state and no `|| true`". It came from `.supervisor/requirements/2026-08-22-092036-vendor-coupling-ratchet.md` (status done) and the owner's core-vs-adapter direction (`loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Core/adapter architecture rule"). This item changes **when** a breach is seen and **how clearly** it says what to do. It does not change **what** counts as a breach.

#### Problem
The gate is right, but its failure is found late and is hard to act on.

1. **It is a genuine catch.** On PR #435 the ratchet caught real new coupling. The first red run (`b8f9698…`, 12:54Z) printed BREACH rows for five paths:
   - `emit-token-ledger.sh` +3 (`core`, `hook_protocol`)
   - `test-token-ledger.sh` +3
   - `test-automate-lanes.sh` +1
   - `TELEMETRY.md` +2
   - `ARCHITECTURE_CONTRACTS.md` +1

   The fix commit `87f2205` removed the emitter's references instead of raising them ("New prose names no host hook token; the emitter reuses its existing `_apath`"). It raised only two test allowances by one each, with reasons. So the gate is worth keeping exactly as strict as it is.
2. **It is found late.** It failed 3 of the 9 full `ci-local` runs attributed to PR #435 by tree key: `b8f9698…` 12:54Z, `3e7bc89…` 14:29Z and `96b9fcf…` 15:31Z, in `~/.local/state/loomwright/ci-slots/dd8a9612cd818d9a/runs/`. Each time the verdict came at the end of a 646 s, 836 s and 639 s run (10.7–13.9 min). The live gate itself takes about 8 s (`PASS 8s … 12-check-vendor-coupling.sh` in run `e615441…`). Its self-test fails alongside it every time (`FAIL - case15 live repo passes its own ratchet` in `scripts/test-check-vendor-coupling.sh`), so one cause shows up as two red entries. Item 05 moves the 8 s gate into an early phase, which fixes the timing.
3. **The remediation is unclear.** The BREACH row (the `printf "$ROWFMT" … "BREACH  +$((n - allow)) over the declared allowance — remove the reference, or raise the allowance …"` site) prints only the count, the overage and the per-class totals. It does not say **which lines** added the references, gives no ready-to-paste manifest edit, and does not say how to route the reference through an adapter. The author has to diff by hand to find the new tokens.
4. **Much of the friction is test files.** `loomwright/scripts/*` is classed `core` (manifest `classes.core.globs`), and that glob includes hermetic `test-*.sh` files, which legitimately spell hook-protocol tokens to build payloads. Re-measured 2026-10-09 (this corrects the evidence brief's wording, see below):
   - **Allowance lines added.** Across the manifest's history (`git log -p`) there are 384 added path-allowance lines, and 76 of them are `test-*.sh` paths. This counts the initial seeding commit `7fa14d8`. Without it, the numbers are 316 and 60. These are *added* lines (new or changed values), not all raises.
   - **Current allowances.** 50 of the 262 allowance entries are `loomwright/scripts/test-*.sh`. Those hold 666 of the 1330 allowance units in `core` paths, about **50%**, and 666 of 2581 overall.
   - **Manifest edit rate.** Since the manifest was created (2026-08-30, `7fa14d8`), 38 of 587 non-merge commits touching `loomwright/scripts/` or `scripts/` also edited the manifest (**6.5%**). Counting merge commits, the figure is 59 of 646 (9.1%).
5. **The manifest is a merge-conflict hotspot.** PRs #410, #412 and #417 all edited `loomwright/docs/vendor-coupling-manifest.json` (verified via `gh pr view --json files`). Every unnecessary per-path raise adds to that.
6. **A dismissed follow-up is still open.** `.supervisor/requirements/proposed/automate-2026-10-05-002720--01-ratchet-hardening-5ac6cf--dismissed-summary.md` (PR #385, decision follow-up) holds three LOW items, re-checked on `main` 2026-10-09. All three still apply:
   - Entry 1, key `6751fe48`: the summary line still reads `of which frontmatter-exempt: N`, although those files' bodies are counted (the `files scanned:` echo).
   - Entry 2, key `7a5865e3`: the seven token-class names are restated in the script header ("named classes — install root, subagent orchestration, …") and in `ARCHITECTURE_CONTRACTS.md` §"Core/adapter architecture rule", besides the manifest's `token_classes`.
   - Entry 3, key `93982b64`: the raise_check BREACH row prints the raw JSON literal (`$bv -> $cur`, e.g. `2 -> 3.0`), and the jq predicate accepts `-0`, which the shell check then rejects.

#### Goal
When the ratchet trips, the author learns in seconds (via item 05) exactly which added lines tripped it and the two legitimate ways out:
- route the reference through an existing adapter or indirection, or
- raise the allowance with a reason the author must write.

The gate stays exactly as strict as today. A pasted suggestion with an unfilled reason is still a BREACH.

#### Scope (shift-left only)
1. **Per-breach detail, printed by the gate (`scripts/check-vendor-coupling.sh`).** For every BREACH path, print a block under its row:
   - **Added lines.** List the lines that carry tokens and were added versus the base: `git diff <base> -- <path>` `+` lines, counted with the **same** awk leftmost-longest counter, never a second matcher. Give each line's number, its token(s) and class(es). When the base does not resolve, list the path's token-bearing lines, capped and labelled `base unavailable — showing all, not only added`.
   - **Ways out, in this order.** (a) Reword prose so it names the concept, not the token (docs). (b) Reuse the file's existing reference; PR #435's emitter reused its existing `_apath`. (c) Move the harness-specific code into an `adapter`-classed file; list the manifest's `classes.adapter.globs` as data, never hard-coded. (d) Raise the allowance. The block must **never** suggest assembling a token at runtime (concatenation or indirection to dodge the literal count). That is the gate's documented blind spot (header: "It therefore CANNOT see a reference ASSEMBLED AT RUNTIME"), and recommending it would loosen the gate in practice.
   - **Ready-to-paste raise row.** Print both manifest entries, `"<path>": <actual>,` for `allowances` and `"<path>": "<placeholder>"` for `allowance_reasons`. The placeholder is a fixed sentinel string. **raise_check treats a reason equal to, or containing, the sentinel as missing (BREACH)**, so pasting without writing the reason still fails closed. Integer formatting follows Entry 3 (below).
2. **Owner decision option, NOT decided here: a separate test-fixture path group.** Present it in the PR body for the owner, and implement it only if the owner picks it. Option A is the default.
   - **A (status quo):** `test-*.sh` stays `core`. Pro: one ratchet, nothing new to reason about. Con: about half of the `core` allowance units are tests, test-only raises churn the hotspot manifest, and the `core` number overstates runtime coupling.
   - **B:** a new class, e.g. `test_fixture`, for `loomwright/scripts/test-*.sh`, `scripts/test-*.sh` and `loomwright/scripts/fixtures/*`. It keeps per-path allowances and keeps reasons on raises, so it is still fail-closed. Moving the paths is a `policy_reasons` `exempt:`-namespaced change, reviewed once. Pro: `core` then measures what a non-Claude harness would run. Con: a new class in the gate's fixed four-class precedence, and a runtime helper named `test-*.sh` would be misclassed. Mitigation: the gate ERRORs if a `test_fixture` path is referenced from `loomwright/hooks/hooks.json` or sourced by a non-test script.
   - **C:** B with one class-level budget instead of per-path allowances. This removes most test raises from the hotspot, at the cost of per-path visibility. A raise still needs a reason.

   Whichever is chosen: no class may be uncounted (that would be `adapter`), and a moved path keeps being counted.

   **Owner decision (2026-10-09, asked at Launch Pad, run `automate-2026-10-09-072725`): A (status quo).** The manifest's class layout is untouched by this part; Scope 1/3/4/5 proceed.
3. **Visible early.** Two parts:
   - **Mechanical: the early phase (Depends on 05).** `check-vendor-coupling.sh` is a `scripts/check-*.sh` ci.yml gate. Item 05 makes it run in the early phase of every full `ci-local` run, and it already runs under `--affected` (the cheap-gate filter). This item's job is that the early-phase output carries the Scope-1 block in full.
   - **Advisory: one line in `AGENT_GUIDELINES.md` §"Pre-push: one command".** After adding any install-root, hook-protocol or ask-user token (see the manifest's `token_classes`, not a restated list), run `bash scripts/check-vendor-coupling.sh` (about 8 s) before the full run.

   **`loomwright/agents/worker.md` is deliberately not touched.** `implementation-quality/01` is editing it. More importantly, the worker prompt ships to every user project, and this gate is a Loomwright-repo-only root `scripts/` gate, so naming it there would be wrong for every other project. This also removes the need to depend on iq/01.
4. **case15 reads as the same cause.** When `test-check-vendor-coupling.sh` case15 ("live repo passes its own ratchet") fails, its FAIL line says it is the live gate's verdict, and it points at, or reprints, the live BREACH rows. One cause then reads as one cause. Its assertion is unchanged: it still fails whenever the live repo breaches.
5. **Fold in the three dismissed LOW items (the `proposed/…ratchet-hardening…dismissed-summary.md` file, Problem 6).**
   - Entry 1: relabel the `frontmatter-exempt` count in the summary line so it does not read as uncounted, for example `frontmatter-bounded (header exempt, body counted)`.
   - Entry 2: the script header and `ARCHITECTURE_CONTRACTS.md` point at `token_classes` instead of naming the seven classes. The #385 changelog fragment was already folded into `CHANGELOG.md` and is history, so leave it.
   - Entry 3: the raise row prints integers. The jq predicate rejects `-0` in the same place the shell check does, so the two layers agree.

#### Acceptance criteria
- **The detail block.** A fixture that adds two hook-protocol tokens to a `core` script prints a BREACH block. The block lists exactly those two added lines (line numbers, tokens, class) and not the file's pre-existing references. It lists the adapter globs read from the fixture manifest, and the ready-to-paste raise row with the sentinel reason. The exit code is 1, as today.
- **The sentinel still fails.** Pasting the suggested row unchanged and re-running gives exit 1, with a raise_check BREACH naming the unfilled reason. Replacing the sentinel with a real reason gives exit 0. Mutation control: drop the sentinel check and the "pasted unchanged" leg must fail.
- **No suggestion of runtime assembly.** The test greps the block for the advice it must never give, and the block also states that rule positively.
- **No base.** With no base (the `skipped (no base)` path), the block says `base unavailable` and lists the token-bearing lines. The exit code is unchanged.
- **case15.** On a breaching live-repo fixture, case15 still FAILs, and its line names the live gate's verdict as the cause.
- **Entries 1–3.** Each has a leg: the summary label, no restated class list in either surface (grep), integer raise-row output, and `-0` rejected consistently.
- **Strictness unchanged.** The whole existing `test-check-vendor-coupling.sh` passes unchanged except the asserted new output. No existing BREACH/ERROR case flips to exit 0.
- **If the owner picks B or C,** the moved paths are still counted (the per-class report shows the new class), and the move is certified by `policy_reasons` entries. Otherwise the manifest is untouched by this item.

#### Validation (must pass before merge)
1. `bash scripts/ci-local.sh` green (the full run).
2. New `test-check-vendor-coupling.sh` legs fail on the base commit and pass on the branch.
3. **Running system.** Replay PR #435's first red tree: check out `fe64cff` (tree `b8f9698…`) in a scratch worktree, run the gate against base `9a65ecb`, and paste the five BREACH blocks in the PR body. The `emit-token-ledger.sh` block must list the 3 added `hook_protocol` lines that `87f2205` later removed.
4. The owner's A/B/C answer is recorded in the PR body, and in this file's Scope 2 once decided.

#### Non-goals
- Any loosening: no auto-raise, no silent exemption, no `|| true`, no warning-only mode, no skip on a missing base where CI sets `VENDOR_COUPLING_REQUIRE_BASE=1`.
- Moving the gate earlier in `ci-local`. That is item 05; this item only makes the early output actionable.
- Seeing runtime-assembled references (the gate's stated literal-match limit). Out of scope, and never to be "solved" by advising authors to use it.
- Editing `loomwright/agents/worker.md` (see Scope 3).
- Resolving manifest merge conflicts mechanically (#410/#412/#417). Option B or C would reduce how often they happen. Neither removes them.

<!-- loomwright:requirement-closeout -->
## Status: done_with_escalation
- **Completed:** 2026-10-09T14:11:40Z
- **Brief:** .supervisor/jobs/done/2026-10-09-iq01-throughput-merged.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/440
- **Heal:** max_iterations_reached — 1 remaining
