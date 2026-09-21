# Supervisor Job: `/review-pr --until-mergeable` — all-review-channel drain, scoped wait-for-checks, validate-then-fix, auto-run by default

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** authored from branch `feature/launchpad-planreviewer-guardrails` (PR #64, v14.31.0, unmerged at authoring); Supervisor will branch off `main` at execution time
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (coordinate with PR #64 — see Risk R6; run this **after** #64 merges)

## Task
**Goal:** Make the `/review-pr --until-mergeable` merge-ready drain (shipped in v14.30.0 / PR #63) actually catch external bot review feedback by (1) reading **all** review channels — not just review objects + threads — (2) **waiting for CI/review workflows to complete** before evaluating readiness, (3) **validating each detected bot finding and fixing it if required** (regardless of the bot's stated severity), and (4) **auto-running the drain by default** from Supervisor after PR creation (opt-out `--no-until-mergeable` / `auto_until_mergeable: false`), while preserving the **never-merge** and **never-wait-on-humans** invariants.

**Problem Statement (root-caused against live evidence on PR #64, 2026-06-18):**

The `--until-mergeable` drain was designed to "drain machine-speed external review signals," but on PR #64 a real `claude[bot]` review finding (a MEDIUM count/restated-list drift, `issuecomment-4733632727`) was never caught. Three compounding root causes, all verified in-repo:

1. **RC1 — channel gap (the core defect).** The `claude-code-review.yml` workflow instructs the reviewer to *"Use `gh pr comment` … to leave your review as a comment"* (`.github/workflows/claude-code-review.yml:61`) — i.e. it posts a **PR issue comment** (`/issues/{n}/comments`), **not** a formal review object and **not** an inline review thread. But the drain's Step U1 (`skills/review-heal/SKILL.md:187`) reads **only** `gh pr view --json …,reviews,latestReviews,…` (review objects) **plus** GraphQL `reviewThreads` (inline threads). It **never reads PR issue comments**. On #64 the drain would see `reviews:[]`, `latestReviews:[]`, `reviewThreads:none` → nothing — while the real review sat in an issue comment. **The repo already knows CI review bots post issue comments:** `scripts/pr-postmortem-gather.sh:230` classifies exactly this (`bot_author_re`, reads `/issues/{n}/comments`) and its header notes *"workflows (e.g. claude-code-review.yml) post issue comments, NOT review objects."* That knowledge never reached the drain.

2. **RC2 — timing gap.** Readiness gates on **required** checks only (Step U2); branch protection makes only `ci` required, while the review-producing `claude-review` check is **not** required. On #64, `ci` completed green at `19:57:12Z` but the bot review comment landed at `20:02:26Z` — **5 minutes later**. The drain could declare `READY` the moment `ci` is green, *before the review even exists*, and never waits for the non-required review workflow to finish or re-scans afterward.

3. **RC3 — severity floor.** The drain auto-fixes only **BLOCKING/HIGH** items (`skills/review-heal/SKILL.md:264`); the #64 finding was **MEDIUM**, so even if seen it would not be acted on. Per the user decision, the fix replaces the blind severity floor with **validate-then-fix**: validate each finding (real / still-applicable / actionable) and fix if the validation confirms a required change, regardless of the bot's stated severity.

**Part A (orthogonal) — it never even ran on #64.** No automated path passes `--until-mergeable` (`grep -c` = 0 in `agents/supervisor.md` and `scripts/dispatch-pr-review.sh`). `/supervisor` created the PR and never invokes it; the Phase 4.5 auto-review dispatch is OFF by default and even when ON runs *plain* `/review-pr`. Per the user decision, Supervisor will now **auto-run `/review-pr --until-mergeable` by default** after PR creation (opt-out flag/config), detached and fire-and-forget, never merging, never waiting on humans.

**Current behavior to preserve (the "check what it's doing right now" delta):** today's drain = read `reviews`/`latestReviews`/`reviewThreads` + required-check discovery → auto-fix actionable BLOCKING/HIGH from required-check failures + bot-authored threads → `git push` (never `--force`) → re-poll until required-green AND no unresolved bot threads → `READY`; fail-CLOSED to `ESCALATED` on unknown thread/required-check state; bounded by `--max-rounds`; anti-churn fingerprint; churn-gated postmortem tail; **no `gh pr merge` ever**. All of that stays — this job is strictly additive to it.

## Feasibility (optional — Launch Pad v10.3+)
- **Tech Stack Compatibility:** GO — `gh` CLI + bash + agent-prompt/skill markdown; the exact surface the loop already uses.
- **Dependency Availability:** GO — `gh api repos/{o}/{r}/issues/{n}/comments`, `gh api .../check-runs/{id}/annotations`, `gh pr view --json statusCheckRollup` (with per-check `status`/`conclusion`) all verified available; the bot-comment classifier already exists in `pr-postmortem-gather.sh` to extract/share.
- **Architecture Fit:** GO — extends the canonical `review-heal` skill; auto-run dispatch mirrors the existing `dispatch-pr-review.sh` detached `claude -p` fail-safe pattern; preserves the "side-effect emitters fail SAFE / correctness gates fail CLOSED" invariants.
- **Scope vs Supervisor Capability:** GO — 6 subtasks, disjoint files, prompt/skill/script edits + one new helper script.
- **Hard Blockers:** none.

**Overall Verdict:** GO

## Acceptance Criteria

### Channel completeness
- [ ] **AC1** — Given a PR whose only review feedback is a **bot-authored issue comment** (the #64 shape: `reviews:[]`, `latestReviews:[]`, no review threads), when a `--until-mergeable` round runs, then Step U1 also reads PR issue comments (`gh api repos/{o}/{r}/issues/{n}/comments?per_page=100`) **and** check-run outputs/annotations, classifies bot-authored review findings, and surfaces them as drain signals (so the finding is no longer invisible).
- [ ] **AC2** — Given the set of review channels, when the drain enumerates feedback, then it covers **all** of: formal reviews (`reviews`/`latestReviews`), inline review threads (`reviewThreads`), **PR issue comments**, and **check-run conclusions + output/annotations**; the readiness decision is computed over the union. Any additional bot channel discovered is documented as covered or an explicit non-goal (e.g. commit comments).
- [ ] **AC2b** *(body extraction, not metadata)* — Given each covered channel, when the drain processes it, then it MUST extract the **body/content text** — formal review **body**, issue-comment **body**, inline-thread comment **body**, and check-run **output/annotation text** — and classify findings from that text. Reading channel **metadata alone** (e.g. `reviews[].state`, comment author, check `conclusion`) is insufficient: the actionable finding (like #64's MEDIUM) lives in the body, so a body-less read would re-miss it.

### Wait for CI / review workflows to complete
- [ ] **AC3** — Given a **required check OR a review-producing check** is still `QUEUED`/`IN_PROGRESS`, when the drain evaluates readiness, then it **does NOT declare READY**; it waits (bounded poll, `--check-wait-timeout`, respecting `--max-rounds`) for **only that scoped set** to complete, then **re-scans all review channels** so a late-posting review workflow's comment is seen. **It MUST NOT couple readiness to unrelated optional checks** (deploy/preview/security scanners that emit no review feedback): a perpetually-pending optional check must never, by itself, block READY or force escalation. **"Review-producing checks"** = the required checks (always) PLUS checks whose name/app matches a review-bot pattern — default e.g. `*review*` / `claude*`, overridable via `--review-check-pattern` and a `notify-config` include/exclude list. Document the include/exclude policy explicitly.
- [ ] **AC4** *(fail-safe on wait timeout — scoped)* — Given the bounded wait elapses with a **required or review-producing** check still in flight, when the drain exits, then it does **not** claim READY — it exits `ESCALATED` (fail-CLOSED), surfacing what was still pending. An **unrelated optional** check still pending at the bound does **not** force escalation (it is outside the wait set).

### Validate-then-fix (replaces the blind BLOCKING/HIGH floor)
- [ ] **AC5** — Given a detected bot finding (any stated severity), when the drain processes it, then it **validates** the finding (is it real, still applicable to the current branch state, and actionable?) before acting; a finding the validation confirms requires a change is **fixed regardless of the bot's stated severity** (so a real MEDIUM like #64 is fixed); a finding validated as not-auto-fixable (needs human judgment) **blocks READY and is surfaced/escalated**; a finding validated as stale/invalid/already-addressed is **recorded as dismissed (not fixed)** and does not block READY.
- [ ] **AC6** *(readiness redefinition)* — Given the new channels + validation, when a round completes, then `READY ⇔ required checks green AND review-producing checks settled (the scoped set — unrelated optional checks excluded) AND no unresolved validated bot findings remain across ALL channels`. Human approval, `reviewDecision: REVIEW_REQUIRED`, and human-authored findings/threads remain **surfaced but never blocking** (never-wait-on-humans preserved).

### Auto-run by default from Supervisor
- [ ] **AC7** — Given Supervisor completes a run that produced a PR, when the Phase 4.5 completion tail runs, then it dispatches the **until-mergeable drain by default** as a detached, fire-and-forget process **via the existing `review-pr-runner` agent form** — `dispatch-pr-review.sh:212` is `nohup claude -p --agent ai-agent-manager-plugin:review-pr-runner <pr-url>` (the **`--agent` runner form, deliberately NOT a `/review-pr` slash-command string** — the slash form would re-introduce the 11.1.1 spawn-depth auto-delegation trap). Because that invocation has no flag surface, the `--until-mergeable` signal is **threaded to the runner via the pinned dispatch-signal contract defined in Subtask 2** (an env var the runner reads, or a positional the runner parses — pinned in S2 so the dispatcher (S4, setter) and the runner (S3, reader) cannot diverge); the runner forwards it to its inline `/review-pr`. Always `exit 0`; never blocks/affects `SUPERVISOR_RESULT`. Opt-out via `--no-until-mergeable` **or** `auto_until_mergeable: false` in `.supervisor/notify-config.json`. Idempotent across `--continue` re-runs (per-PR marker).
- [ ] **AC8** *(invariants preserved)* — Given any path (manual or auto-run), when the drain terminates in any state (`READY`/`ESCALATED`), then **no `gh pr merge` is ever invoked**, the loop **never waits on human approval/threads**, pushes are **never `--force`**, the loop is bounded by `--max-rounds`, and the existing fail-CLOSED behavior (unknown thread-state / unreadable required-check metadata → `ESCALATED`) is unchanged.
- [ ] **AC8b** *(auto-run observability — fire-and-forget must still leave a trail)* — Given the auto-run dispatch never blocks/affects `SUPERVISOR_RESULT`, when Supervisor dispatches the drain, then it records a **visible trail** so a "complete" Supervisor run is not silently hiding an in-flight/escalated/pushing drain: an additive `until_mergeable_dispatched: true` marker + an `until_mergeable_log` path on the job `## Outcome` block and the session log (and, where the field is emitted, on `SUPERVISOR_RESULT` — additive/optional, no `schema_version` bump). The drain itself fires a best-effort notification on **BOTH** terminal states — `READY` **and** `ESCALATED` — not only on READY. **Downstream-ordering guidance:** because the detached drain may still be pushing fix commits to the PR branch after the Supervisor run is marked complete, **branch-dependent** downstream work (a stacked `/autonomous` iteration N+1, or a human merge) SHOULD wait until the drain reaches a terminal state (visible via this marker + the terminal notification) or a human intentionally proceeds (see Risk R9).
- [ ] **AC8c** *(headless-dispatch proof — the detached invocation must be tested against its REAL shape)* — Given the dispatcher now conveys until-mergeable by default, when the change lands, then a self-test (`scripts/test-dispatch-pr-review.sh`, mirroring the #63 precedent) asserts the **actual constructed command shape** the dispatcher emits — `nohup claude -p --agent ai-agent-manager-plugin:review-pr-runner <pr-url>` (the `--agent` runner form at `dispatch-pr-review.sh:212`, **not** a `/review-pr` slash-command string) — **AND** that the pinned until-mergeable dispatch signal is present in that invocation (the env var is exported, or the positional/arg the runner parses carries it), **AND** the fail-safe contract (no-op + `exit 0` when `claude`/`jq`/config absent; opt-out honored). Scope is the deterministic, CI-runnable **command-shape + signal-present + fail-safe** assertion (the existing `test-dispatch-*.sh` style), **NOT** a live end-to-end `claude` launch. Rationale pinned: lesson [[detached-claude-dispatch-needs-print-flag]] + the 11.1.1 `--agent`-not-slash trap — the detached form was a real bug fixed in #63; assert the dispatcher's ACTUAL line, never an assumed slash form.

### Reuse + schema + docs
- [ ] **AC9** *(single-source classifier)* — Given the bot-review-comment classification logic, when it is needed by both the drain and `pr-postmortem-gather.sh`, then it lives in **one** shared helper (`scripts/classify-bot-review.sh` + a `test-classify-bot-review.sh` self-test) and both consumers call it — the `bot_author_re` / review-marker logic is NOT duplicated (single source of truth; dogfoods Criterion 15).
- [ ] **AC10** *(additive schema + consumer docs)* — Given new drain outputs (channels scanned, validated/dismissed findings, checks-waited), when `REVIEW_HEAL_RESULT` is emitted, then any new fields are **additive and optional** (no `schema_version` bump beyond the existing v2 unless strictly required), documented in `docs/RESULT_SCHEMAS.md`, and the `/autonomous` consumer docs (`commands/autonomous.md`, `skills/autonomous-loop/SKILL.md`) still treat unrecognized/`READY` as terminal non-re-iterate.
- [ ] **AC11** *(doc-currency green, counts unchanged)* — Given the changes, when `scripts/check-doc-currency.sh`, `scripts/validate-version.sh`, and `scripts/check-command-sync.sh` run, then all pass; counts stay **14 agents / 18 commands / 55 skills / 19 hooks** (new helper scripts are uncounted). All cross-file restatements of the readiness semantics / flag surface are swept together (see Risk R5).

## Outcomes Rubric (optional — v12.2.0+)
- `skills/review-heal/SKILL.md` Step U1 reads PR issue comments (`/issues/{n}/comments`) and check-run outputs/annotations and classifies bot-authored review findings **from each channel's body text** (review body, comment body, thread body, check output — not just metadata), in addition to `reviews`/`latestReviews`/`reviewThreads`.
- `skills/review-heal/SKILL.md` adds a bounded wait scoped to **required + review-producing checks only** (never unrelated optional checks) that re-scans channels before evaluating READY, and exits `ESCALATED` if a required/review check is still pending at the bound.
- `skills/review-heal/SKILL.md` replaces the blind BLOCKING/HIGH auto-fix floor with a validate-then-fix step: each detected bot finding is validated, fixed if a required change is confirmed (any severity), surfaced/escalated if not auto-fixable, and dismissed if stale/invalid.
- `skills/review-heal/SKILL.md` redefines READY as: required checks green AND review-producing checks settled (the scoped set — unrelated optional checks excluded) AND no unresolved validated bot findings across all channels.
- `agents/supervisor.md` completion tail dispatches the until-mergeable drain by default after PR creation **via the `review-pr-runner` agent** (`claude -p --agent …:review-pr-runner <pr-url>` with the signal threaded per the S2 contract — not a `/review-pr` slash string), with `--no-until-mergeable` / `auto_until_mergeable: false` opt-out, never merging and never waiting on humans — and records an `until_mergeable_dispatched` marker + `until_mergeable_log` link (the drain notifies on both `READY` and `ESCALATED`).
- A single shared `scripts/classify-bot-review.sh` helper is used by both `skills/review-heal/SKILL.md`'s drain and `scripts/pr-postmortem-gather.sh` (the bot-author/review-marker logic is not duplicated).
- The diff adds no `gh pr merge` invocation anywhere (never-auto-merge invariant preserved).

## Executable Acceptance (optional — System Twin / M2b, v14.19.0+)
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Shared bot-review-comment classifier: extract `classify-bot-review.sh` (+ self-test) from `pr-postmortem-gather.sh`'s logic; rewire gather to use it | AC9 | 1 modify, 2 create | review-heal, pr-postmortem | LAUNCHABLE |
| 2 | `review-heal` drain core: all-channel read + **per-channel body extraction** (AC2b) + **scoped** wait (required + review-producing checks only) + validate-then-fix + READY redefinition + **pin the until-mergeable dispatch-signal contract** (the env-var/positional name S4 sets & S3 reads) | AC1–AC6 (incl. AC2b), AC7 (signal contract), AC8 | 1 modify, 0 create | review-heal, async-orchestration | BLOCKED (by #1) |
| 3 | Command + runner surface: `--no-until-mergeable`, `--check-wait-timeout`, `--review-check-pattern`, channel/wait/validate docs | AC7 (flag), AC8 | 2 modify, 0 create | review-heal | BLOCKED (by #2) |
| 4 | Supervisor auto-run-by-default + opt-out + **dispatch observability** + **dispatcher self-test** (`agents/supervisor.md`, `commands/supervisor.md`, `dispatch-pr-review.sh`, `test-dispatch-pr-review.sh`) | AC7, AC8, AC8b, AC8c | 4 modify, 0 create | workflow-management, async-orchestration | BLOCKED (by #2) |
| 5 | Schema + consumer docs: `REVIEW_HEAL_RESULT` additive fields, `/autonomous` consumer-doc consistency | AC10 | 3 modify, 0 create | — | BLOCKED (by #2) |
| 6 | Version bump + counts + CLAUDE.md banner + doc-currency green | AC11 | 5 modify, 0 create | commit | BLOCKED (by #1–#5) |

### Provides / Requires Schema (v12.0.0+)

```yaml
# Subtask 1 — shared bot-review classifier (LAUNCHABLE)
provides:
  - {kind: "file", path: "ai-agent-manager-plugin/scripts/classify-bot-review.sh"}
  - {kind: "file", path: "ai-agent-manager-plugin/scripts/test-classify-bot-review.sh"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/scripts/classify-bot-review.sh", name: "Bot-Review Classifier"}
requires: []
external_requires:
  - "gh CLI (gh api repos/{o}/{r}/issues/{n}/comments)"
  - "Existing scripts/pr-postmortem-gather.sh bot_author_re logic (extraction source — already present)"

# Subtask 2 — review-heal drain core (BLOCKED by #1)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/review-heal/SKILL.md", name: "Until-Mergeable Mode"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/review-heal/SKILL.md", name: "All-Channel Read"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/review-heal/SKILL.md", name: "Wait-For-Settled-Checks"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/review-heal/SKILL.md", name: "Validate-Then-Fix"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/review-heal/SKILL.md", name: "Until-Mergeable Dispatch Signal"}   # pinned env-var/positional contract the S4 dispatcher SETS and the S3 runner READS — single source of truth so they cannot diverge
requires:
  - {from: "1", kind: "file", path: "ai-agent-manager-plugin/scripts/classify-bot-review.sh"}
external_requires: []

# Subtask 3 — command + runner surface (BLOCKED by #2)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/commands/review-pr.md", name: "--no-until-mergeable"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/commands/review-pr.md", name: "--check-wait-timeout"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/review-pr.md", name: "All-Channel Drain"}
requires:
  - {from: "2", kind: "symbol", path: "ai-agent-manager-plugin/skills/review-heal/SKILL.md", name: "All-Channel Read"}
  - {from: "2", kind: "symbol", path: "ai-agent-manager-plugin/skills/review-heal/SKILL.md", name: "Until-Mergeable Dispatch Signal"}   # runner READS the pinned signal
external_requires: []

# Subtask 4 — Supervisor auto-run-by-default + opt-out (BLOCKED by #2)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/supervisor.md", name: "Auto-Until-Mergeable Dispatch"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/commands/supervisor.md", name: "--no-until-mergeable"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/scripts/dispatch-pr-review.sh", name: "until-mergeable-default"}
requires:
  - {from: "2", kind: "symbol", path: "ai-agent-manager-plugin/skills/review-heal/SKILL.md", name: "Until-Mergeable Mode"}
  - {from: "2", kind: "symbol", path: "ai-agent-manager-plugin/skills/review-heal/SKILL.md", name: "Until-Mergeable Dispatch Signal"}   # dispatcher SETS the pinned signal (same contract the S3 runner reads)
external_requires:
  - "scripts/notify-desktop.sh, scripts/send-webhook.sh (existing emitters); the EXISTING `dispatch-pr-review.sh:212` form `nohup claude -p --agent ai-agent-manager-plugin:review-pr-runner <pr-url>` (--agent runner form, NOT a slash string)"

# Subtask 5 — schema + consumer docs (BLOCKED by #2)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md", name: "REVIEW_HEAL_RESULT"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/commands/autonomous.md", name: "review_heal.decision"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/autonomous-loop/SKILL.md", name: "REVIEW_HEAL_RESULT"}
requires:
  - {from: "2", kind: "symbol", path: "ai-agent-manager-plugin/skills/review-heal/SKILL.md", name: "Validate-Then-Fix"}
external_requires: []

# Subtask 6 — version bump + counts + CLAUDE.md banner + doc-currency (BLOCKED by #1–#5)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/.claude-plugin/plugin.json", name: "version"}
  - {kind: "symbol", path: ".claude-plugin/marketplace.json", name: "version"}
  - {kind: "symbol", path: "CLAUDE.md", name: "Project Overview"}
requires:
  - {from: "2", kind: "symbol", path: "ai-agent-manager-plugin/skills/review-heal/SKILL.md", name: "Until-Mergeable Mode"}
  - {from: "3", kind: "symbol", path: "ai-agent-manager-plugin/commands/review-pr.md", name: "--no-until-mergeable"}
  - {from: "4", kind: "symbol", path: "ai-agent-manager-plugin/agents/supervisor.md", name: "Auto-Until-Mergeable Dispatch"}
  - {from: "5", kind: "symbol", path: "ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md", name: "REVIEW_HEAL_RESULT"}
external_requires:
  - "scripts/check-doc-currency.sh must pass (validator-owned surface — fold its scanned version/annotation surfaces into this subtask)"
```

**Authoring note (validator-owned surface — dogfoods the v14.31.0 guardrail):** Subtask 6's acceptance depends on `scripts/check-doc-currency.sh`. That validator scans agent/command/skill/hook counts, `plugin.json (vX.Y.Z)` annotations, and the `AI agents vX.Y.Z` headline. Counts are **unchanged** (new `classify-bot-review.sh` + test are *scripts*, uncounted; `/pr-postmortem` and `/review-pr` already exist) — bump only the version string + `description` `vX.Y.Z` token + the `(vX.Y.Z)` annotations the validator (and last PR) flagged: `CLAUDE.md` line ~28 + line ~152 region, `.claude-plugin/README.md`, `commands/agent-help.md`. Do **not** touch the four count claims.

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2 ──┬──→ Subtask 3 ──┐
                          ├──→ Subtask 4 ──┤
                          └──→ Subtask 5 ──┴──→ Subtask 6
```

### File Overlap Matrix
| | S1 | S2 | S3 | S4 | S5 | S6 |
|---|----|----|----|----|----|----|
| **S1** `classify-bot-review.sh`(+test), `pr-postmortem-gather.sh` | — | none | none | none | none | none |
| **S2** `review-heal/SKILL.md` | none | — | none | none | none | none |
| **S3** `commands/review-pr.md`, `agents/review-pr.md` | none | none | — | none | none | none |
| **S4** `agents/supervisor.md`, `commands/supervisor.md`, `scripts/dispatch-pr-review.sh` | none | none | none | — | none | none |
| **S5** `docs/RESULT_SCHEMAS.md`, `commands/autonomous.md`, `skills/autonomous-loop/SKILL.md` | none | none | none | none | — | none |
| **S6** `plugin.json`, `marketplace.json`, `CLAUDE.md`, `.claude-plugin/README.md`, `commands/agent-help.md` | none | none | none | none | none | — |

No file overlap. Dependencies are purely contract/ordering: S2 calls S1's classifier; S3/S4/S5 document/wire the S2 contract; S6 (version/docs) depends on all.

### Batches
- **Batch 1:** Subtask 1 (root — shared classifier + test)
- **Batch 2:** Subtask 2 (drain core)
- **Batch 3:** Subtask 3 ∥ Subtask 4 ∥ Subtask 5 (parallel — disjoint, all depend only on S2)
- **Batch 4:** Subtask 6 (version/docs/doc-currency)
- **Recommended workers:** 3

## Skill References
- `review-heal` — the canonical loop contract being extended (S1, S2, S3)
- `async-orchestration` — bounded poll / wait-for-checks / round-loop patterns (S2, S4)
- `pr-postmortem` — source of the bot-comment classifier being extracted/shared (S1)
- `workflow-management` — Supervisor completion-tail dispatch wiring (S4)
- `commit` — conventional commit + version bump (S6)

## Risk Assessment
| Risk | Severity | Mitigation |
|------|----------|------------|
| **R1** — Auto-running the drain by **default** silently pushes commits to every Supervisor PR and waits on CI. | HIGH | User-requested. Bounded by `--max-rounds`; detached + fire-and-forget (never blocks/affects `SUPERVISOR_RESULT`); opt-out `--no-until-mergeable` / `auto_until_mergeable: false`; **never merges, never waits on humans, never `--force`** (AC8). Document the new default loudly in CLAUDE.md + `commands/supervisor.md`. |
| **R2** — "Wait for CI to complete" could hang or wait on a perpetually-pending/optional check (a deploy-preview/security check that never settles would starve READY forever). | HIGH | **The wait set is scoped to required + review-producing checks ONLY (AC3), never the whole rollup** — an unrelated pending optional check never blocks READY or forces escalation. Bounded `--check-wait-timeout` + `--max-rounds` hard ceiling; on timeout with a **required/review** check still pending → `ESCALATED` (fail-CLOSED, AC4). Review-producing checks identified by configurable name/app pattern + include/exclude list, not a hard-coded workflow name. |
| **R3** — Bot-comment false positives (a non-review bot comment, e.g. a deploy-preview notice) trigger spurious fixes. | MEDIUM | Reuse `pr-postmortem-gather.sh`'s battle-tested classifier (the "Deploy Preview" negative control is already test-pinned); the **validate-then-fix** step (AC5) is a second gate — a finding must validate as real+applicable before any edit. |
| **R4** — Validate-then-fix is vague / the fix worker rubber-stamps its own validation. | MEDIUM | Specify validation as an explicit, evidence-citing check (finding maps to a concrete current-branch location AND is actionable); a finding that cannot be grounded is **dismissed** (recorded), not fixed; not-auto-fixable → `ESCALATED`. Keep the fix worker allowlist `Read/Write/Edit/Bash/Glob/Grep` (no Task). |
| **R5** — Readiness semantics + the new flag are restated across multiple files → mirror/count drift (the exact class PR #64 hit). | HIGH | S2 owns the authoritative semantics; S3/S4/S5 docs must **reference** it, not re-duplicate. Before S6, grep the readiness-semantics phrasing + `--until-mergeable`/`--no-until-mergeable` across `commands/review-pr.md`, `agents/review-pr.md`, `commands/supervisor.md`, `agents/supervisor.md`, `commands/autonomous.md`, `skills/autonomous-loop/SKILL.md`, CLAUDE.md and reconcile in one pass. (See lesson: agent↔command mirror-drift; spawn-prompt + command-doc restatements are outside `check-command-sync.sh`/`check-doc-currency.sh` coverage.) |
| **R6** — Coordination with PR #64 (v14.31.0): both touch `plugin.json`, `marketplace.json`, `CLAUDE.md`, `.claude-plugin/README.md`, `commands/agent-help.md`, `docs/RESULT_SCHEMAS.md`. | MEDIUM | Run this brief **only after PR #64 merges**; Supervisor branches off the merged `main` and bumps from the then-live `plugin.json` value. Do not run both at once. |
| **R7** — `REVIEW_HEAL_RESULT` schema change surprises `/autonomous` EVALUATE / Supervisor consumers. | LOW | New fields additive/optional; keep `schema_version` at 2 unless strictly required; AC10 updates the consumer docs; unrecognized/`READY` already treated as terminal non-re-iterate. |
| **R8** — Detached auto-run needs `claude -p` + the plugin available in the detached env (else silent no-op). | LOW | Mirror `dispatch-pr-review.sh` exactly (uses `claude -p`; always `exit 0`; logs one line and no-ops when `claude`/config absent). Lesson [[detached-claude-dispatch-needs-print-flag]] applies. |
| **R9** — The detached auto-run drain keeps **pushing fix commits to the PR's feature branch** after Supervisor has marked the job complete; branch-dependent downstream work can race a still-active drain. | LOW | A new Supervisor job that branches off `main` is independent (separate branch + worktree) — no direct conflict. The real hazard is **branch-dependent** downstream work: a stacked `/autonomous` iteration N+1 (branches off iter N's still-moving branch) or a human merge mid-push. Mitigation: do not start branch-dependent downstream work until the drain reaches a terminal state (`READY`/`ESCALATED`) — checkable via the AC8b `until_mergeable_dispatched` marker + `until_mergeable_log` and the terminal notification — or a human intentionally proceeds. Document this ordering guidance in `commands/supervisor.md` (S4) and the `/autonomous` stacked-iteration docs (S5). Never-`--force` + the per-PR dispatch marker bound the blast radius. |

## Configuration
- **Base Branch:** main
- **New runtime knobs:** `--no-until-mergeable` (Supervisor + /review-pr opt-out), `auto_until_mergeable` (config, default **true**) in `.supervisor/notify-config.json`, `--check-wait-timeout N` (bounded wait for the **scoped** check set), `--review-check-pattern <glob>` (+ a notify-config include/exclude list) to identify review-producing checks beyond the required set; existing `--max-rounds`, `--required-checks all-non-neutral`, `--no-auto-postmortem`, `--postmortem-churn-threshold` unchanged.
- **Auto-run observability:** Supervisor records `until_mergeable_dispatched: true` + `until_mergeable_log: <path>` (job `## Outcome` + session log; additive/optional on `SUPERVISOR_RESULT`); drain notifies on both `READY` and `ESCALATED`.
- **Auto-run default:** ON (Supervisor auto-dispatches `/review-pr --until-mergeable` after PR creation), detached/fire-and-forget; **never merges, never waits on humans**; opt-out via flag/config.
- **Readiness semantics:** READY ⇔ required checks green AND review-producing checks settled (the scoped set — unrelated optional checks excluded) AND no unresolved **validated** bot findings across all channels (reviews + threads + issue comments + check outputs). Human approval / `REVIEW_REQUIRED` / human findings never block.
- **New scripts (uncounted):** `scripts/classify-bot-review.sh` (+ `test-classify-bot-review.sh`).
- **Counts after this change:** 14 agents / 18 commands / 55 skills / 19 hooks (UNCHANGED).
- **Version:** bump from the **live** `plugin.json` value at execution time (a minor, additive feature). Likely `14.31.0 → 14.32.0` once PR #64 has merged; read the live value, do not assume a literal. `version-consistent` corpus-task validates against the live value.

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-06-18-until-mergeable-all-review-channels.md
```
> Run in a fresh Claude Code session, **only after PR #64 (v14.31.0) has merged** (Risk R6). Neither Supervisor nor the merge-ready loop auto-merges; "READY" is a notification, never a merge.

---

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/65 (#65, base `main`, OPEN — never auto-merged)
- **Branch:** feature/until-mergeable-all-review-channels
- **Commits:** 2 (41fd262 feature; d4010ce Phase 4.5 heal)
- **Version:** 14.31.0 → 14.32.0
- **Subtasks:** 6/6 complete (S1 classifier, S2 drain core, S3 surface, S4 auto-run+dispatcher, S5 schema/docs, S6 version)
- **heal_loop_ran:** true
- **heal_decision:** PASS
- **heal_iterations:** 1 (review: PASS-with-HIGH-drift → fix worker corrected CLAUDE.md banner/CHANGELOG/RESULT_SCHEMAS narrative → re-review clean)
- **heal_remaining_issues:** 0
- **Gates:** check-doc-currency ✓ · validate-version ✓ (14.32.0) · check-command-sync ✓
- **Self-tests:** classify 6/6 · gather 15/15 · dispatch 16/16
- **Invariants verified:** no `gh pr merge` invocation (only invariant-asserting prose); single-source classifier; fail-CLOSED gates / fail-SAFE emitters; never-wait-on-humans; never `--force`; env-var dispatch-signal contract consistent across setter/reader/skill.
- **until_mergeable_dispatched:** false (running Supervisor is v14.31.0 — the auto-run feature ships in this PR; no `--auto-review`/`--until-mergeable` flag passed)
