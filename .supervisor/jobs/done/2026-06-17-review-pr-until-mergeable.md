# Supervisor Job: `/review-pr --until-mergeable` external-review-aware heal loop + churn-gated auto-postmortem

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh; CLAUDE.md banner still reads v14.28.0 but `plugin.json` is already v14.29.0 — see Risk R7)
- **Git:** dirty (1 file: `ai-agent-manager-plugin/docs/SPIKES/LEARNING_LOOP_ROADMAP.md`), branch: main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 2 (working tree dirty; on `main` — Supervisor will branch a feature ref before any edit)

## Task
**Goal:** Extend `/review-pr` + the `review-heal` skill with an opt-in `--until-mergeable` mode that drains *machine-speed* external PR signals (**required** CI check-runs + automated/**bot** reviews + unresolved **bot-authored** review threads), auto-fixes the BLOCKING/HIGH ones, pushes, and loops until **required checks are green AND no unresolved bot-authored review threads remain** — then stops with `decision: READY` and fires a "ready to merge" notification (**never merges**). **The loop never waits on human approval or human-authored review threads** — those are surfaced, not gated. Bounded by `--max-rounds`, with an anti-churn guardrail that escalates to a deep "fix-the-class" self-review on oscillation. **Additionally**, on loop exit, conditionally fire the existing read-only `/pr-postmortem <pr-url>` — but **only when churn is meaningful** (trigger-gated), via a fail-safe dispatcher that can NEVER alter the loop result.

**Problem Statement:**
Today the entire review-and-heal machinery (Supervisor Phase 4.5, standalone `/review-pr` + `review-heal`, `/autonomous` EVALUATE) is a **closed internal loop**: it runs *our own* `code-reviewer` against the integrated diff, fixes new BLOCKING/HIGH issues, posts findings, and exits. It **never consults external GitHub review state** (`reviewDecision`, `gh pr view --json reviews`, `statusCheckRollup`, review threads), **never waits** for CI/bot reviewers, and **never re-acts** on what the PR's reviewers/bots flag. So real reviewer/CI feedback that lands after Supervisor's self-heal is unaddressed until a human re-engages. This feature closes that gap for the machine-speed signals (required CI + bots), bounded and churn-guarded, never auto-merging, **and explicitly without waiting on humans**. Separately, when a PR took meaningful churn to get there, we want a **learning signal** captured automatically — but cheaply and only when it's worth it, never for clean PRs, and never in a way that can affect whether the PR is declared ready.

## Feasibility (optional — Launch Pad v10.3+)
- **Tech Stack Compatibility:** GO — `gh` CLI + bash; same surface the loop already uses.
- **Dependency Availability:** GO — `gh pr view --json reviews,latestReviews,statusCheckRollup,reviewDecision,mergeable,mergeStateStatus` verified available. **Two derived signals need more than `gh pr view --json`:** (a) unresolved review threads + their author type need `gh api graphql` (`reviewThreads { isResolved, comments(first:1){ nodes{ author{ login __typename } } } }`) — NOT exposed by `--json` (Risk R1); (b) **which checks are required** needs branch-protection metadata (`gh api repos/{owner}/{repo}/branches/{base}/protection/required_status_checks` or GraphQL `baseRef.branchProtectionRule.requiredStatusCheckContexts`), with `mergeStateStatus`/`mergeable` as corroborating signals (Risk R2). Auto-postmortem reuses the EXISTING `/pr-postmortem` + `pr-postmortem` skill + `pr-postmortem-gather.sh` (verified) and mirrors the EXISTING `dispatch-pr-review.sh` fail-safe pattern.
- **Architecture Fit:** GO — extends the canonical `review-heal` skill; mirrors Phase 4.5 semantics; the postmortem dispatcher follows the "side-effect emitters fail SAFE, always exit 0" invariant; required-check discovery follows the "correctness gates fail CLOSED" invariant.
- **Scope vs Supervisor Capability:** GO — 4 subtasks.
- **Hard Blockers:** none.

**Overall Verdict:** GO

## Acceptance Criteria

### Merge-ready loop — readiness semantics
- [ ] **AC1** — Given a PR URL and `--until-mergeable`, when a round runs, then it reads external state via `gh pr view <url> --json statusCheckRollup,reviews,latestReviews,reviewDecision,mergeable,mergeStateStatus` PLUS `gh api graphql` for review threads (with each thread's `isResolved` and the author `login`/`__typename` of its first comment) PLUS branch-protection required-check discovery (AC14).
- [ ] **AC2** — Given a **required** failing check-run or an unresolved **bot-authored** review thread, when a round runs, then a `Task(general-purpose)` fix worker (allowlist Read/Write/Edit/Bash/Glob/Grep, **no Task**) addresses the actionable BLOCKING/HIGH items, followed by a regular `git push` (**never `--force`**), then the loop re-polls.
- [ ] **AC3** — Given **all required checks are green** AND **no unresolved bot-authored review threads remain**, when a round completes, then the loop exits with `decision: READY` and fires the desktop + webhook "ready to merge" notification best-effort. **Human approval state, `reviewDecision: REVIEW_REQUIRED`, and human-authored unresolved threads are explicitly NOT readiness blockers** — the loop never waits on a human.
- [ ] **AC14** *(required-check discovery — fail CLOSED)* — Given the loop must decide "checks green", when it evaluates check state, then it discovers the **required** check contexts from branch-protection metadata and gates READY on those only (optional/non-required failing checks do NOT block READY). **If required-check metadata is unavailable** (insufficient permissions, no branch protection, API error), then the loop MUST NOT claim READY — it exits `ESCALATED` (fail closed), UNLESS an explicit config/flag (`--required-checks all-non-neutral`) opts into treating every non-`NEUTRAL`/`SKIPPED` check as blocking.
- [ ] **AC15** *(bot-vs-human thread classification)* — Given an unresolved review thread, when classifying it, then it counts as a READY-blocker ONLY if its first comment's author is a bot (`author.__typename == "Bot"` or login matching `*[bot]`). Human-authored (or unknown-author) unresolved threads are surfaced/notified but NEVER block READY.

### Merge-ready loop — bounds & invariants
- [ ] **AC4** — Given `--max-rounds N` (default 5), when N rounds elapse without reaching the exit condition, then the loop exits with `decision: ESCALATED`, posts remaining findings via `gh pr comment`, and notifies — never unbounded.
- [ ] **AC5** — Given the same issue class recurs across rounds (anti-churn fingerprint match) OR a churn-round threshold is hit, when the guardrail trips, then the loop runs one deep "fix-the-class" self-review pass before continuing; if oscillation persists at `--max-rounds`, it exits `ESCALATED`.
- [ ] **AC6** — Given any terminal state (`READY`, `PASS`, or `ESCALATED`), when the loop exits, then **no `gh pr merge` is ever invoked** — the PR is left open for a human (no-auto-merge invariant preserved).
- [ ] **AC7** — Given `/review-pr` is run **without** `--until-mergeable`, when it runs, then behavior is byte-for-byte the existing diff-only review→fix→re-review loop (the new mode is strictly additive and opt-in).
- [ ] **AC8** — Given the new `decision: READY` value and added result fields, when the loop emits `REVIEW_HEAL_RESULT`, then it is at `schema_version: 2` (v1 still accepted) and `docs/RESULT_SCHEMAS.md` documents the new fields + the GraphQL review-thread / required-check details.
- [ ] **AC16** *(consumer doc consistency)* — Given `REVIEW_HEAL_RESULT` v2 adds `READY`, when the schema changes, then docs that enumerate `review_heal.decision` (`commands/autonomous.md`, `skills/autonomous-loop/SKILL.md`) are updated to list `READY` as an additive value, noting that `/autonomous` EVALUATE never emits `READY` (it does not pass `--until-mergeable`) and its parser treats an unrecognized/`READY` decision as a terminal, non-re-iterate state (degrades safely).

### Churn-gated auto-postmortem
- [ ] **AC9** *(no-op on clean PRs)* — Given a `--until-mergeable` run whose `fix_cycles ≤ postmortem_churn_threshold` (default 2) AND `decision != ESCALATED` AND no required CI check failed again after a fix AND no bot feedback remained unresolved after a fix, when the loop exits, then **no postmortem is dispatched**.
- [ ] **AC10** *(fires on meaningful churn)* — Given **any** of: `fix_cycles > postmortem_churn_threshold` | `decision == ESCALATED` (escalated/timed-out) | the same required CI/check failure repeats after a fix | bot/automated feedback remains unresolved after ≥1 attempted fix — when the loop exits, then `dispatch-pr-postmortem.sh` fires `/pr-postmortem <pr-url>` best-effort (fire-and-forget).
- [ ] **AC11** *(configurable threshold)* — Given `postmortem_churn_threshold` in `.supervisor/notify-config.json` (read via jq) or `--postmortem-churn-threshold N`, when evaluating the fix-cycle trigger, then postmortem runs only when `fix_cycles > threshold`; default **2**.
- [ ] **AC12** *(read-only + fail-safe — the hard guarantee)* — Given the postmortem dispatcher, `/pr-postmortem`, or its gather/write step errors, when the loop completes, then `REVIEW_HEAL_RESULT.decision` is **unchanged**, the dispatcher exits **0**, and the merge-ready result is identical to a run where postmortem succeeded. The decision is computed and emitted **before** dispatch. Postmortem only **appends** to `.supervisor/postmortem/results.jsonl` — it mutates no repo file.
- [ ] **AC13** *(opt-out)* — Given `--no-auto-postmortem` (or `auto_postmortem: false` in `.supervisor/notify-config.json`), when the loop exits, then no postmortem is dispatched regardless of churn.

## Outcomes Rubric (optional — v12.2.0+)
- `skills/review-heal/SKILL.md` documents the `--until-mergeable` drain: required-CI-check discovery (only required checks gate READY, fail-closed when metadata is unavailable), bot-authored unresolved-thread detection via `gh api graphql`, with human approval explicitly not awaited.
- `docs/RESULT_SCHEMAS.md` lists `READY` as a `REVIEW_HEAL_RESULT.decision` enum value and the schema is at `schema_version: 2`.
- `commands/review-pr.md` documents `--until-mergeable`, `--max-rounds`, `--no-auto-postmortem`, and `--postmortem-churn-threshold` in its parameter table.
- `skills/review-heal/SKILL.md` documents an anti-churn guardrail that escalates to a deep self-review when an issue class recurs across rounds.
- `scripts/dispatch-pr-postmortem.sh` exists, is churn-gated on `postmortem_churn_threshold` (default 2), fires `/pr-postmortem` best-effort, and exits 0 on every failure path.
- `skills/review-heal/SKILL.md` states the postmortem dispatch runs only after the loop decision is computed and can never change `REVIEW_HEAL_RESULT.decision`.
- The diff adds no `gh pr merge` invocation anywhere (never-auto-merge invariant preserved).

## Executable Acceptance (optional — System Twin / M2b, v14.19.0+)
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | `review-heal` loop: `--until-mergeable` drain (required-check discovery + bot-thread classification) + anti-churn + `--max-rounds` + postmortem-dispatch tail + `dispatch-pr-postmortem.sh` | AC1–AC7, AC14, AC15, AC9–AC13 | 1 modify, 2 create | review-heal, async-orchestration, pr-postmortem | LAUNCHABLE |
| 2 | `REVIEW_HEAL_RESULT` schema v1→v2 (`READY` + fields + GraphQL/required-check note) **+ `/autonomous` consumer-doc consistency** | AC8, AC16, AC12 | 3 modify, 0 create | — | BLOCKED (by #1) |
| 3 | Command + runner-agent surface: `--until-mergeable` / `--max-rounds` / `--no-auto-postmortem` / `--postmortem-churn-threshold` / `--required-checks` + READY notification | AC3, AC4, AC7, AC11, AC13, AC14 | 2 modify, 0 create | review-heal | BLOCKED (by #1) |
| 4 | Version bump + counts + CLAUDE.md banner + doc-currency green | AC8 | 4 modify, 0 create | commit | BLOCKED (by #1, #2, #3) |

### Provides / Requires Schema (v12.0.0+)

```yaml
# Subtask 1 — review-heal loop + external drain + anti-churn + postmortem dispatcher (LAUNCHABLE)
provides:
  - {kind: "file", path: "ai-agent-manager-plugin/skills/review-heal/SKILL.md"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/review-heal/SKILL.md", name: "Until-Mergeable Mode"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/review-heal/SKILL.md", name: "Anti-Churn Guardrail"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/review-heal/SKILL.md", name: "Postmortem Dispatch Tail"}
  - {kind: "file", path: "ai-agent-manager-plugin/scripts/dispatch-pr-postmortem.sh"}
  - {kind: "file", path: "ai-agent-manager-plugin/scripts/test-dispatch-pr-postmortem.sh"}
requires: []
external_requires:
  - "gh CLI (gh pr view --json statusCheckRollup,reviews,mergeStateStatus; gh api graphql reviewThreads; gh api branch protection required_status_checks)"
  - "Existing /pr-postmortem command + pr-postmortem-gather.sh (dispatch target — already present)"

# Subtask 2 — REVIEW_HEAL_RESULT schema v1→v2 + autonomous consumer-doc consistency (BLOCKED by #1)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md", name: "REVIEW_HEAL_RESULT"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/commands/autonomous.md", name: "review_heal.decision"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/autonomous-loop/SKILL.md", name: "REVIEW_HEAL_RESULT"}
requires:
  - {from: "1", kind: "symbol", path: "ai-agent-manager-plugin/skills/review-heal/SKILL.md", name: "Until-Mergeable Mode"}
  - {from: "1", kind: "symbol", path: "ai-agent-manager-plugin/skills/review-heal/SKILL.md", name: "Postmortem Dispatch Tail"}
external_requires: []

# Subtask 3 — command + runner-agent surface + flags + READY notification (BLOCKED by #1)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/commands/review-pr.md", name: "--until-mergeable"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/commands/review-pr.md", name: "--no-auto-postmortem"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/commands/review-pr.md", name: "--required-checks"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/review-pr.md", name: "Until-Mergeable Mode"}
requires:
  - {from: "1", kind: "symbol", path: "ai-agent-manager-plugin/skills/review-heal/SKILL.md", name: "Until-Mergeable Mode"}
  - {from: "1", kind: "file", path: "ai-agent-manager-plugin/scripts/dispatch-pr-postmortem.sh"}
external_requires:
  - "scripts/notify-desktop.sh, scripts/send-webhook.sh (existing notification emitters)"

# Subtask 4 — version bump + counts + CLAUDE.md banner + doc-currency (BLOCKED by #1,#2,#3)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/.claude-plugin/plugin.json", name: "version"}
  - {kind: "symbol", path: ".claude-plugin/marketplace.json", name: "version"}
  - {kind: "symbol", path: "CLAUDE.md", name: "Project Overview"}
requires:
  - {from: "1", kind: "symbol", path: "ai-agent-manager-plugin/skills/review-heal/SKILL.md", name: "Until-Mergeable Mode"}
  - {from: "2", kind: "symbol", path: "ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md", name: "REVIEW_HEAL_RESULT"}
  - {from: "3", kind: "symbol", path: "ai-agent-manager-plugin/commands/review-pr.md", name: "--until-mergeable"}
external_requires:
  - "scripts/check-doc-currency.sh must pass (validator-owned surface)"
```

**Authoring note (validator-owned surface):** Subtask 4's acceptance depends on `scripts/check-doc-currency.sh` passing. That validator mechanically scans the plugin doc surface (agent/command/**skill**/hook counts, `plugin.json (vX.Y.Z)` annotations, the `AI agents vX.Y.Z` headline). This feature adds **no** new agent/command/skill/hook — the new `dispatch-pr-postmortem.sh` is a *script* (uncounted), `/pr-postmortem` already exists, and Subtask 2 *edits* (does not add) `commands/autonomous.md` + `skills/autonomous-loop/SKILL.md` — so counts stay **14 / 18 / 55 / 19**. Subtask 4 bumps only the version string + `description` `vX.Y.Z` token (in place) and adds a CLAUDE.md banner; do **not** touch the four count claims.

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2 ──┐
          └─→ Subtask 3 ──┴──→ Subtask 4
```

### File Overlap Matrix
| | S1 | S2 | S3 | S4 |
|---|----|----|----|----|
| **S1** `review-heal/SKILL.md`, `dispatch-pr-postmortem.sh`, `test-dispatch-pr-postmortem.sh` | — | none | none | none |
| **S2** `RESULT_SCHEMAS.md`, `commands/autonomous.md`, `skills/autonomous-loop/SKILL.md` | none | — | none | none |
| **S3** `commands/review-pr.md`, `agents/review-pr.md` | none | none | — | none |
| **S4** `plugin.json`, `marketplace.json`, `CLAUDE.md`, `SKILLS_INDEX.md` | none | none | none | — |

No file overlap between subtasks. S2 now also edits the two `/autonomous` consumer docs (disjoint from S1/S3/S4). Dependencies are purely contract/ordering.

### Batches
- **Batch 1:** Subtask 1 (root — loop contract + dispatcher script + named surfaces)
- **Batch 2:** Subtask 2 ∥ Subtask 3 (parallel — disjoint files, both depend only on S1)
- **Batch 3:** Subtask 4 (version/docs/doc-currency)
- **Recommended workers:** 2

## Skill References
- `review-heal` — the canonical loop contract being extended
- `async-orchestration` — bounded poll / round loop patterns (Subtask 1)
- `pr-postmortem` — read-only churn-analyzer conditionally dispatched (Subtask 1)
- `commit` — conventional commit + version bump (Subtask 4)

## Risk Assessment
| Risk | Severity | Mitigation |
|------|----------|------------|
| **R1** — Unresolved review threads + author type are NOT available via `gh pr view --json` (verified). | HIGH | Subtask 1 MUST use `gh api graphql` `reviewThreads { isResolved, comments(first:1){ nodes{ author{ login __typename } } } }`. Pinned so Supervisor does not invent a `--json reviewThreads` flag. Fail-safe: GraphQL error → thread-state "unknown → do not claim READY" → `ESCALATED`. |
| **R2** — `statusCheckRollup` alone does NOT distinguish **required** vs optional checks; naive handling either blocks forever on optional CI or claims READY too early. | HIGH | **AC14:** discover required checks via branch-protection metadata (`gh api repos/{o}/{r}/branches/{base}/protection/required_status_checks` or GraphQL `requiredStatusCheckContexts`); gate READY on required checks only. **Fail CLOSED** when metadata is unavailable (→ `ESCALATED`), unless `--required-checks all-non-neutral` is explicitly set. `mergeStateStatus`/`mergeable` corroborate but are not the sole basis (`mergeStateStatus` conflates "required check failing" with "approval missing", which we deliberately ignore). |
| **R3** — Anti-churn guardrail could loop forever or fire too eagerly. | MEDIUM | Fingerprint by `{file, issue_category, rule}`; trip only on a *repeat* fingerprint after a fix OR `churn_rounds ≥ 2`; deep self-review runs **once per trip**; `--max-rounds` is the hard ceiling. |
| **R4** — Breaking the never-auto-merge invariant. | HIGH | AC6 + Outcomes Rubric bullet assert no `gh pr merge` is added. `READY` is terminal-stop-and-notify, merge-identical to `PASS`/`ESCALATED`. |
| **R5** — `/autonomous` EVALUATE & Supervisor Phase 4.5 consume `REVIEW_HEAL_RESULT`; a new `decision: READY` could surprise them. | MEDIUM | Keep `READY` opt-in (only under `--until-mergeable`). **AC16** updates the `/autonomous` consumer docs to list `READY` and treat unrecognized/`READY` as terminal non-re-iterate. Default `/review-pr` + all auto-chained callers still emit only `PASS`/`ESCALATED`; v1 consumers degrade safely. |
| **R6** — Coordination with companion brief `2026-06-17-launchpad-planreviewer-guardrails.md` (both bump `plugin.json` + edit `CLAUDE.md`). | MEDIUM | Run sequentially; second branches from the first's merged result (or re-bumps the version). Never run both Supervisors at once. |
| **R7** — Brief authored against v14.28.0 snapshot; repo advanced to v14.29.0 mid-planning (commits `7868123`, `3c38767`). | LOW | Subtask 4 bumps above the **live** `plugin.json` value (14.29.0 → 14.30.0). `version-consistent` corpus-task reads the live value. |
| **R8** — Auto-postmortem fires on clean/low-churn PRs (noise). | MEDIUM | Strict churn gate: ALL of the AC10 OR-triggers false → skip; default threshold 2; on-by-default-but-churn-gated within `--until-mergeable` only; opt-out via `--no-auto-postmortem` / `auto_postmortem: false`. AC9 asserts the clean-PR no-op. |
| **R9** — Postmortem dispatch failure changes the merge-ready result (the cardinal sin). | HIGH | AC12: decision finalized **before** dispatch; dispatcher mirrors `dispatch-pr-review.sh` (fire-and-forget, `exit 0` every path); postmortem append-only to `.supervisor/postmortem/results.jsonl`. `postmortem_dispatched` is informational, never a gate input. |
| **R10** — Subagent-cannot-spawn-subagent when dispatching `/pr-postmortem` from inside a Task-spawned loop body. | MEDIUM | Mirror `dispatch-pr-review.sh`: launch `/pr-postmortem` as a **fresh detached `claude` process** (or no-op when `claude`/config absent), NOT a nested Task spawn. Document the exact launch form in Subtask 1. |
| **R11** — Bot-vs-human thread classification false-negatives could let the loop claim READY while a human asked for changes. | LOW | Acceptable by design (AC15): READY never auto-merges — it only notifies; the human is still the merge gate. Classify by GraphQL `author.__typename == "Bot"` / login `*[bot]`; unknown-author threads are surfaced in the notification so a human sees them before merging. |

## Configuration
- **Base Branch:** main
- **Heal iterations (Supervisor self-heal):** default (3)
- **New runtime knobs:** `--until-mergeable` (opt-in), `--max-rounds N` (default 5), `--required-checks all-non-neutral` (opt-in fallback when branch-protection metadata is unreadable; default = fail closed), `--no-auto-postmortem` (opt-out), `--postmortem-churn-threshold N` (default 2) — all on `/review-pr`; config equivalents `auto_postmortem` / `postmortem_churn_threshold` in `.supervisor/notify-config.json` (read via jq)
- **Readiness semantics:** READY ⇔ required checks green AND no unresolved bot-authored threads. Human approval / `REVIEW_REQUIRED` / human threads are NEVER awaited.
- **Auto-postmortem default:** ON within `--until-mergeable` but **churn-gated** (no-op on clean PRs); read-only; never affects the loop result
- **New script (uncounted):** `scripts/dispatch-pr-postmortem.sh` (+ `test-dispatch-pr-postmortem.sh`) — no new command (reuses `/pr-postmortem`)
- **Counts after this change:** 14 agents / 18 commands / 55 skills / 19 hooks (UNCHANGED)
- **Version:** bump from the live `plugin.json` value (currently **14.29.0** → **14.30.0**; minor — additive). Do not assume 14.28.0.

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-06-17-review-pr-until-mergeable.md
```
> Run in a fresh Claude Code session for clean context. Sequence with the companion guardrails brief — start it **only after a human has merged this PR** (neither Supervisor nor the merge-ready loop auto-merges; "ready" is a notification, not a merge). See Risk R6.

## Outcome
- **Status:** completed
- **Completed:** 2026-06-17T13:23:58Z
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/63
- **Branch:** feature/review-pr-until-mergeable
- **Files changed:** 14
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0
- **Red team advisory:** disabled
- **Rubric score:** 7/7
- **Summary:** v14.30.0 — opt-in --until-mergeable external-review-aware heal loop (required-check fail-closed discovery, bot-thread classification via gh api graphql, never-merge / never-wait-on-humans) + churn-gated fail-safe auto-postmortem dispatcher. 4 subtasks, all per-subtask + holistic consistency_audit reviews PASS, zero drift. Doc-currency + version-consistent gates green.
