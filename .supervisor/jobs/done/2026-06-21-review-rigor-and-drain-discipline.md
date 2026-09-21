# Supervisor Job: First-Line Review Rigor (quality, not pass-the-PR) — drain cosmetic-defer deferred by evidence

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** working tree clean, currently on `feature/review-drain-worktree-isolation` (the **previous** v14.42 branch). **Before running Supervisor, cut a fresh branch off `main`** for this v14.43 work — e.g. `git checkout main && git pull && git checkout -b feature/review-rigor-and-severity`. Do NOT build this on top of the old worktree-isolation branch.
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Plugin version:** 14.42.0 (this change ships as **v14.43.0**)
- **Counts (verified):** 14 agents · 19 commands · 56 skills · 20 hook leaf entries — **UNCHANGED by this work** (no new agent/command/skill/hook; additive prompt/skill edits only)
- **Blockers:** 0 | **Warnings:** 2 (see Risk Assessment)

## Task

**Goal (this run):** Make the plugin's **first-line code review actually catch real defects** — better code, measured by real defects caught early / defects escaped to `main`, **NOT** reviewer agreement or gate-pass rate — **without** weakening the #64 lesson or homogenizing the two review lenses. Concretely: the adversarial-input + execution-grounded rigor lens (Subtask 1), the severity-assignment rule that makes the diff-review paths actually *fix* what the lens finds (Subtask 1c), and observable anticipatory fix-worker self-review (Subtask 2).

> **Scope note — the drain-churn half is deferred, not delivered here.** The original problem statement also aimed to "stop the `/review-pr --until-mergeable` drain from grinding on cosmetic noise" (Subtask 3, cosmetic-defer). The Pre-Implementation Evidence **evaluated that lever and deferred it**: the BetterBlocks #31/#32 postmortems show the churn was a *real self-heal miss*, not cosmetic noise — so the drain's cosmetic behavior is **unchanged this run** and Subtask 3 is parked for a follow-up brief. **This run strengthens review rigor; it does not change drain cosmetic-defer semantics.**

**North star / explicit non-goals:**
- ❌ Do **NOT** make the plugin's `code-reviewer` mirror or converge with a target repo's CI review rubric (`.github/review-rubric.md`) to make "self-heal PASS predict CI-clean." That is teaching-to-the-test and destroys the defense-in-depth value of two **independent** lenses (Phase 4.5 self-heal vs the repo's CI bot stay deliberately different).
- ❌ Do **NOT** reinstate a BLOCKING/HIGH **severity floor** in the drain. §U3.5 Validate-Then-Fix deliberately removed it after the **#64** incident (a real **MEDIUM** SQL-injection finding was dropped by the old floor). "Reinstating a BLOCKING/HIGH severity floor" is a pinned **Anti-Pattern** (`skills/review-heal/SKILL.md:574`). Lever 2 below is **category-based (cosmetic vs correctness)**, not severity-based.

**Root cause (verified in code):** Phase 4.5 self-heal ([`agents/supervisor.md:706-722`](ai-agent-manager-plugin/agents/supervisor.md)) and the `/review-pr` drain ([`skills/review-heal/SKILL.md:122-127`](ai-agent-manager-plugin/skills/review-heal/SKILL.md)) both spawn the **same** `ai-agent-manager-plugin:code-reviewer` agent. The first-line review *reads a checklist* rather than *interrogating inputs / executing behavior*, so the CI bot later catches real correctness/security bugs (negative-amount exploit, idempotency holes, run-once violations) it missed — caught late, in the drain, over ~5 rounds. Because the reviewer is a **shared brain**, the rigor fix belongs in **one place** and all three callers (Phase 4.5, the drain, standalone `/code-reviewer`) inherit it.

## Pre-Implementation Evidence (ALREADY GATHERED — outcome: DEFER Subtask 3)

The #31/#32 postmortems were run against the **target repo (BetterBlocks)**, and their `POSTMORTEM_RESULT` lines live in **that** repo's ledger — `~/Documents/work/personal/BetterBlocks/.supervisor/postmortem/results.jsonl` — NOT this plugin repo's `.supervisor/postmortem/results.jsonl` (the plugin ledger holds only this repo's own PRs and never had #31/#32; that's expected, not a gap).

**Verified readings (from the BetterBlocks ledger, repo `vikashruhilgit/BetterBlocks`):**

| PR | `review_rounds` | `self_heal_misses` | categories | Verdict |
|---|---|---|---|---|
| **#31** | 1 | **1** | `round 1: quality_gap, self_heal_miss=true, flow=self_heal` (the `TrySpend(0)` validation-parity / revive double-grant / coin-source class) | **real self-heal miss — NOT cosmetic** |
| **#32** | 0 | 0 | — (clean, no churn) | not cosmetic-dominant (no churn) |

**Gate outcome (by Subtask 3's own crisp rule — "proceed only if BOTH PRs cosmetic-dominant"):** **SKIP / DEFER Subtask 3.** #31 fails on `self_heal_misses == 1` (a real bug self-heal missed); #32 fails on `review_rounds == 0` (no churn at all). Neither shows the approve-with-followup nit churn that would justify the cosmetic-defer lever.

**What the evidence affirmatively says: Subtask 1 is the right lever.** #31's miss is a `quality_gap` caught at the **`self_heal` flow stage** — a `TrySpend(0)` validation-parity bug self-heal should have caught. That is *exactly* the class Subtask 1 targets (adversarial zero/negative-input lens + the validation-parity item in the Self-Heal Miss-Class Checklist). The data confirms the churn was a **rigor gap, not cosmetic noise** → ship Subtasks **1 + 2 + 4**, defer Subtask **3**.

## Acceptance Criteria

- [ ] **Given** a changed code path in any review (Phase 4.5, drain, or standalone), **when** `code-reviewer` reviews it, **then** it applies an explicit **adversarial-input lens** (negative / zero / overflow / replay-idempotency / concurrent) and an **execution-grounded** step, not just a static read.
- [ ] **Given** the adversarial/execution lens confirms a **correctness / security / behavior regression introduced by the diff**, **when** the reviewer assigns severity, **then** it labels it **HIGH or BLOCKING** (so the diff-review fix floor `new+BLOCKING/HIGH` actually fixes it in Phase 4.5 / default `/review-pr`) — MEDIUM/LOW reserved for maintainability/polish/non-blocking risk; the `drift` severity caps are unchanged. *(P1 — the rigor lens is inert in the diff-review paths without this.)*
- [ ] **Given** behavior cannot be verified without mutating the tree, writing artifacts (snapshots/coverage/caches/temp DB/generated files), or needs unavailable infra, **when** the reviewer reports, **then** it marks the behavior **`unverified`** (never a silent pass) and runs **no** update/fix/format/snapshot-update/migration/seed command — **and if that behavior is load-bearing** (central to the diff's correctness/security claim) and static review can't establish safety, it returns **`NEEDS_HUMAN` / a blocking issue, not `PASS`** (non-load-bearing unverified is reported but doesn't block). *(P2 + P2.1.)*
- [ ] **Given** the shared `code-reviewer` agent is changed once, **when** Phase 4.5 self-heal and the `/review-pr` drain run, **then** both inherit the new rigor with **no per-caller duplication** of the adversarial/execution logic, and none of the three call-site prompts narrows the review below the new baseline.
- [ ] **Given** a fix worker (Phase 4.5 or drain) finishes a fix, **when** it pushes, **then** it has first **self-reviewed its own diff for downstream regressions** (persistence / state / lifecycle) — the class behind the combo-split→double-`Save` and earn-counter→dedup-collision — **and emitted an observable `self_review:` note** naming the risk classes checked (persistence/state/lifecycle/idempotency/concurrency) in `FIX_RESULT` / its output; a push with no note is treated as incomplete. *(P5 — not just a prompt sentence.)*
- [ ] **Given** the change touches `agents/`, `commands/`, `skills/`, `docs/`, and plugin metadata, **when** review runs, **then** doc-currency holds (counts stay 14/19/56/20; version bumped to 14.43.0 across `plugin.json` + `marketplace.json` + CLAUDE.md current-version lines; `scripts/check-doc-currency.sh` green) and `skills/review-heal/SKILL.md` single-source-of-truth references stay in sync (no mirror drift in `commands/review-pr.md`, the runner agent, `docs/RESULT_SCHEMAS.md`, autonomous EVALUATE).
- [ ] **Given** all invariants, **when** the work lands, **then**: `/review-pr` & Phase 4.5 **never merge**; the only `gh pr merge --squash` executor stays the `automate-loop` gate; runtime emitters fail-SAFE (exit 0), correctness gates fail-CLOSED; the two review lenses remain independent (no rubric-mirroring).

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | Rigor in the shared reviewer brain (adversarial-input + execution-grounded) | 2 modify | LAUNCHABLE |
| 2 | Anticipatory fix-worker self-review (both loops) | 2 modify | LAUNCHABLE |
| ~~3~~ | ~~Drain cosmetic-defer disposition~~ | — | **DEFERRED by evidence** (BetterBlocks #31 `self_heal_misses=1`, #32 no churn → not cosmetic-dominant). Spec retained below for a follow-up brief; NOT executed this run. |
| 4 | Cross-surface sync, version bump, doc-currency, CHANGELOG | ~5 modify | BLOCKED (by #1, #2) |

**Active scope this run: Subtasks 1 → 2 → 4.** Subtask 3 is deferred per the Pre-Implementation Evidence outcome above.

### Subtask 1 — Rigor in the shared reviewer brain (lever 1)
- **Scope:** Add to the `code-reviewer` **Review Process**:
  - **(a) Adversarial-input lens** — for every changed code path, reason about negative/zero/overflow/empty, replay/idempotency, and concurrent execution.
  - **(b) Execution-grounded verification WITH mutation guardrails** — run targeted, *non-mutating* checks when discoverable (type-check; the specific tests covering the diff). **NEVER** run update/fix/format, snapshot-update (`-u`/`--update`), coverage-writing, migration, or seed commands. If verification would mutate the tree, write artifacts (snapshots / coverage / caches / temp DB state / generated files), or needs unavailable infra → report the behavior as **`unverified`** in the result summary — **never as passing**. ("Skipped/unverified ⇒ UNVERIFIED, not clean" — the plugin's standing invariant; a static read is the floor, executed-and-verified is the goal, and the gap between them must be *stated*.)
    - **Decision consequence — bind `unverified` to the verdict (P2.1):** if the unverified behavior is **load-bearing** (central to the diff's correctness/security claim) AND static review cannot establish safety, the reviewer returns **`NEEDS_HUMAN`** — or a blocking `new` HIGH issue when the gap is simply "no test exists" that the fix worker can close — **never `PASS`**. A **non-load-bearing** unverified behavior (tangential, not central to the change's correctness) is reported as `unverified` but does **not** block PASS. This mirrors the existing decision-matrix row "environment prevents a normal review → NEEDS_HUMAN" (`agents/code-reviewer.md:418`) and honors fail-CLOSED-on-correctness; `NEEDS_HUMAN` → `ESCALATED` leaves the PR open for a human, exactly as intended.
  - **(c) Severity-assignment rule (closes the MEDIUM-slips-through gap — P1).** Any **confirmed correctness / security / behavior regression introduced by the diff** — exactly what the adversarial lens hunts — MUST be labeled **HIGH or BLOCKING**, never MEDIUM/LOW. MEDIUM/LOW are reserved for maintainability, polish, or non-blocking risk. **Why this is load-bearing:** the diff-review paths only fix `new + BLOCKING/HIGH` (`agents/supervisor.md:740`, `skills/review-heal/SKILL.md:144`) and `code-reviewer` PASSes when only MEDIUM/LOW remain (`agents/code-reviewer.md:415`) — so a real correctness bug *mislabeled* MEDIUM is found but never fixed in Phase 4.5 / default `/review-pr`. Without this rule the rigor lens improves *thinking* but still lets MEDIUM-labeled real bugs slide. This rule does **NOT** touch the `drift` severity caps (`count`/`version_secondary` ≤ MEDIUM, `hooks_parity`/`wording` ≤ LOW stay as-is) — it governs only `category: new` code-behavior findings.

  Place (a)+(b) as numbered Review-Process steps and (c) in the agent's **severity definitions** (`agents/code-reviewer.md:355-379`). Mirror (a) and (c) into the **Self-Heal Miss-Class Checklist** (`skills/quality-checklist/SKILL.md:145-160`, the preloaded repo-agnostic surface Phase 4.5 already invokes at `agents/supervisor.md:712`).
- **Files:** `ai-agent-manager-plugin/agents/code-reviewer.md` (Review Process §303-406 + severity definitions §355-379), `ai-agent-manager-plugin/skills/quality-checklist/SKILL.md` (Self-Heal Miss-Class Checklist §).
- **provides:**
  - `{kind: file, path: ai-agent-manager-plugin/agents/code-reviewer.md, name: "Review Process — adversarial-input lens + execution-grounded(guardrailed) step; severity-assignment rule (correctness/security/behavior regression ⇒ HIGH/BLOCKING)"}`
  - `{kind: file, path: ai-agent-manager-plugin/skills/quality-checklist/SKILL.md, name: "Self-Heal Miss-Class Checklist — adversarial-input class + correctness-severity rule"}`
- **requires:** none.
- **Skills:** `quality-checklist`, `pattern-detector`. **Confidence:** HIGH.
- **Invariant:** read-only contract preserved (no Write/Edit; Bash stays non-mutating — and now explicitly forbids mutating test/format/migration commands; unverifiable ⇒ `unverified`, never silent-pass). The severity rule (c) refines severity **assignment** for `new` correctness findings; it does **not** alter the `drift` severity **caps** or the PASS-on-MEDIUM/LOW decision matrix for genuine maintainability/polish.

### Subtask 2 — Anticipatory fix-worker self-review (lever 3)
- **Scope:** Add to **both** fix-worker prompts a pre-push self-review step: "before committing/pushing, re-read your own diff and check it introduces no downstream regression in persistence/state/lifecycle (e.g. duplicated writes, changed ordering, cross-session collisions); if it does, fix it in this same pass." This is **distinct** from the existing "fix-the-class sweep" (which sweeps *sibling* instances) and the Anti-Churn Guardrail (which trips on oscillation across rounds).
- **Make it observable, not skippable (P5).** The self-review MUST produce a visible artifact, not just be a prompt sentence: the **Phase 4.5** fix worker emits a one-line `self_review:` note inside `FIX_RESULT.summary` (or an additive optional `FIX_RESULT.self_review` field) **naming the risk classes it checked** — persistence / state / lifecycle / idempotency / concurrency — and the result (clean, or fixed-in-pass); the **drain** `general-purpose` worker prints the same `self_review:` line in its output. A fix that pushes with **no** self-review note is treated as incomplete by the loop (re-prompt or surface), so the step can't silently degrade to a no-op.
- **Files:** `ai-agent-manager-plugin/agents/supervisor.md` (Phase 4.5 fix-worker prompt, ~lines 742-764), `ai-agent-manager-plugin/skills/review-heal/SKILL.md` (default-loop fix prompt ~lines 146-153 **and** drain fix prompt ~lines 395-403).
- **provides:**
  - `{kind: file, path: ai-agent-manager-plugin/agents/supervisor.md, name: "Phase 4.5 fix-worker prompt — pre-push self-regression review step"}`
  - `{kind: file, path: ai-agent-manager-plugin/skills/review-heal/SKILL.md, name: "default-loop + drain fix-worker prompts — pre-push self-regression review step"}`
- **requires:** none. **Confidence:** HIGH.
- **Note:** edits `review-heal/SKILL.md` (the fix-worker prompts). With Subtask 3 deferred there is no same-file concurrency hazard this run; Subtask 2 is the only active editor of that file.

### Subtask 3 — Drain cosmetic-defer disposition (lever 2 — #64-SAFE, HIGHEST RISK) — ⛔ DEFERRED BY EVIDENCE (do NOT execute this run)
> **Status: DEFERRED.** The Pre-Implementation Evidence (BetterBlocks ledger) already evaluated the gate → **SKIP**: #31 `self_heal_misses=1` (real miss), #32 no churn. The full spec below is **retained for a follow-up brief** to be planned only if later evidence shows cosmetic/nit-dominated drain churn. Supervisor does **not** run this subtask in this job.
>
> **Deferred acceptance criterion (belongs to the follow-up brief, NOT a gate for this run):** Given a drain round confirms a finding that is purely cosmetic/style (not correctness/security/behavior), when the loop dispositions it, then it is deferred to a tracked follow-up and excluded from READY-blockers, while every confirmed correctness/security/behavior finding is still fixed in-loop at ANY stated severity (the #64 MEDIUM is still fixed); cosmetic classifier conservative/fail-toward-fix.
- **Scope:** In `review-heal/SKILL.md` §U3.5 **Validate-Then-Fix**, add a FIFTH disposition for a confirmed finding that is **purely cosmetic/style** (NOT correctness/security/behavior): **defer to a tracked follow-up** (added to a deferred-nits PR comment and/or a chip) and **exclude from READY-blockers** — while keeping case-2 (confirmed correctness/security/behavior → FIX regardless of stated severity) **exactly as-is** so the #64 MEDIUM is still fixed. Add an Anti-Pattern note clarifying this is **category-based, NOT a severity floor** (so it does not contradict line 574).
- **Redefine ALL affected result semantics, not just add a field (P4).** Deferral creates a new "validated-but-neither-fixed-nor-blocking" state, so every dependent definition must be made precise in the same edit, or the contract goes muddy:
  - **`READY` redefinition** (§"READY redefinition", line 436): "no unresolved validated **correctness/security/behavior** findings; **cosmetic findings are fixed OR deferred-and-tracked**" (deferred cosmetics, like dismissed findings, do NOT block READY — but unlike dismissed, they ARE recorded).
  - **`findings_deferred`** (new, additive/optional, `REVIEW_HEAL_RESULT` v2, **no schema_version bump beyond 2**): count of confirmed-cosmetic findings deferred-and-tracked.
  - **`findings_validated`**: clarify it counts confirmed findings = fixed (case-2) + human-judgment-blocking (case-3) + **deferred-cosmetic (new case)** — deferral is a kind of "validated", not "dismissed".
  - **`findings_dismissed`**: clarify it remains **stale/invalid/already-addressed ONLY** — a deferred cosmetic is valid and is NOT dismissed.
  - **`remaining_issues`**: clarify deferred cosmetics are **excluded** (they don't block); only case-3 (confirmed, not-auto-fixable, human-judgment) count.
  - Update the §U3.5 prose, the READY definition, the "Terminal states" list, and the Quality-Gates bullet so all four fields read consistently with the new disposition.
- **Cosmetic classifier MUST be conservative (fail-toward-fix):** anything not confidently cosmetic is treated as correctness and fixed in-loop. Reuse `CODE_REVIEW_RESULT` `category: nit` where available; for bot findings, a lightweight heuristic that defaults to "fix" on ambiguity.
- **Files:** `ai-agent-manager-plugin/skills/review-heal/SKILL.md` (§U3.5 + READY redefinition + Anti-Patterns), `ai-agent-manager-plugin/commands/review-pr.md` (surface sync — referenced, not re-coined), `ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md` (`REVIEW_HEAL_RESULT` v2 additive `findings_deferred`; **no schema_version bump beyond 2**).
- **Evidence gate (HISTORICAL TEMPLATE — already evaluated for #31/#32 → SKIP; update the ledger path/PR set before reusing for a future follow-up).** *For the #31/#32 decision this was run against the **BetterBlocks** ledger `~/Documents/work/personal/BetterBlocks/.supervisor/postmortem/results.jsonl` (see Pre-Implementation Evidence) — NOT the plugin-local `.supervisor/postmortem/results.jsonl` shown in the generic template below.* The generic, reusable form: Supervisor evaluates the relevant postmortem evidence against the **real corpus schema** (verified keys: `repo`, `number`, `review_rounds`, `self_heal_misses` (int per PR), `categories[].self_heal_miss` (bool per round) — NOT `pr`/`pr_url`/`pr_number`). Run (against the **target app's** ledger, not necessarily the plugin's):
  ```
  jq -c 'select((.number==<PR_A> or .number==<PR_B>) and (.repo|test("<TARGET_REPO>")))' <TARGET_REPO_LEDGER>/.supervisor/postmortem/results.jsonl
  ```
  where `<TARGET_REPO>` / `<TARGET_REPO_LEDGER>` identify the app whose drain churn is in question (a bare `grep -E '"number":(N|M)'` is acceptable ONLY if no same-numbered PR from another repo shares that ledger — repo-qualify to avoid collision).
- **Crisp threshold (P3 — verified fields: `review_rounds` (int), `self_heal_misses` (int), `categories[].{class, self_heal_miss}`).** For EACH matched #31/#32 line, compute **"cosmetic-dominant"** ⇔ **`self_heal_misses == 0`** (no real bug self-heal should have caught) **AND** `review_rounds >= 3` (there actually was churn to address) **AND** a **majority of `categories[]` have `self_heal_miss == false`** and are nit/convention-style classes (e.g. `convention_mismatch`) rather than `quality_gap`/correctness classes carrying `self_heal_miss == true`. **Proceed with Subtask 3 ONLY if BOTH matched PRs are cosmetic-dominant.** **Otherwise SKIP** — i.e. no matched line (absent ⇒ defer until evidence exists), OR any matched PR has `self_heal_misses >= 1`, OR its categories are correctness-dominated. On SKIP: `record_decision(phase: PLAN, decision: "subtask3_deferred", rationale: "<no evidence | self_heal_misses>=1 | correctness-dominant>")` and note in `SUPERVISOR_RESULT.summary` that the cosmetic-defer lever is deferred to a follow-up brief. **Default posture is SKIP** — a `self_heal_misses >= 1` reading means the drain rounds were *real missed bugs* (→ Subtask 1 is the fix, not cosmetic-defer), so fail-toward-defer keeps the risky lever out unless the evidence affirmatively shows nit churn. *(For #31/#32 this already evaluated to SKIP — see Pre-Implementation Evidence.)*
- **provides:**
  - `{kind: file, path: ai-agent-manager-plugin/skills/review-heal/SKILL.md, name: "§U3.5 cosmetic-defer disposition + READY-redefinition update + Anti-Pattern clarification (category-based, NOT a severity floor)"}`
  - `{kind: file, path: ai-agent-manager-plugin/commands/review-pr.md, name: "surface sync for cosmetic-defer (referenced, not re-coined)"}`
  - `{kind: symbol, path: ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md, name: "REVIEW_HEAL_RESULT.findings_deferred — additive optional field, no schema_version bump beyond 2"}`
- **requires:**
  - `{kind: file, path: ai-agent-manager-plugin/skills/review-heal/SKILL.md, name: "fix-worker prompt edits (shared-file ordering)", from: subtask-2}`
- **Confidence:** MEDIUM (evidence-gated — see the Evidence gate above + Pre-Implementation Evidence).
- **Invariant guard:** preserve `--until-mergeable` absent ⇒ default loop byte-for-byte (AC7); never merge; fail-CLOSED on unknown channels; deferral **tracks, never drops**; correctness fixed at ANY severity (no severity floor reinstated — `skills/review-heal/SKILL.md:574`).

### Subtask 4 — Cross-surface sync, version bump, doc-currency
- **Scope:** Bump version 14.42.0 → **14.43.0** (`plugin.json`, `marketplace.json`, CLAUDE.md current-version lines + a single banner; descriptions updated **in place**, no appended version clause). Bump `review-heal/SKILL.md` `version:` 1.3.0 → 1.4.0. Reconcile any behavior wording in `commands/agent-help.md` / `CLAUDE.md` Common-Pitfalls if a described behavior changed. Add a `CHANGELOG.md` entry. Run `scripts/check-doc-currency.sh` + `scripts/validate-version.sh` green. **Counts stay 14/19/56/20.**
- **Files:** `plugin.json`, `.claude-plugin/marketplace.json`, `CLAUDE.md`, `CHANGELOG.md`, `commands/agent-help.md` (if needed), `skills/review-heal/SKILL.md` (frontmatter only).
- **provides:**
  - `{kind: file, path: ai-agent-manager-plugin/.claude-plugin/plugin.json, name: "version 14.43.0 + description updated in place"}`
  - `{kind: file, path: .claude-plugin/marketplace.json, name: "version 14.43.0 + description updated in place"}`
  - `{kind: file, path: CHANGELOG.md, name: "v14.43.0 entry"}`
- **requires:**
  - `{kind: file, path: ai-agent-manager-plugin/agents/code-reviewer.md, name: "rigor lens", from: subtask-1}`
  - `{kind: file, path: ai-agent-manager-plugin/agents/supervisor.md, name: "anticipatory-fix", from: subtask-2}`
  - *(Subtask 3 dependency dropped — Subtask 3 is DEFERRED by evidence, so there is no cosmetic-defer surface to sync this run.)*
- **Confidence:** HIGH.

## Parallelism Analysis
- **Recommended workers: 1 (fully serial).** Every subtask edits a high-drift prompt / single-source-of-truth surface (the `code-reviewer` agent, the `review-heal` SSoT skill, Phase 4.5). The parallelism payoff is marginal and the prose-as-program / mirror-drift risk is real (see Risk Assessment + the `prompt-is-program` lesson) — serial is the disciplined choice for a change to the plugin's own review machinery.
- **Serial order (this run): Subtask 1 → Subtask 2 → Subtask 4.** Subtask 3 is **DEFERRED by evidence** and not executed.
- **Note:** Subtask 2 edits `review-heal/SKILL.md` (the fix-worker prompts). With Subtask 3 deferred there is no longer a same-file concurrency hazard — but serial execution is still the recommendation for the prose-as-program / mirror-drift reasons above.

## Outcomes Rubric
- The shared `code-reviewer` agent gained an explicit adversarial-input lens AND an execution-grounded step; neither Phase 4.5 nor the drain duplicates that logic.
- A confirmed correctness/security/behavior regression introduced by the diff is labeled HIGH/BLOCKING (not MEDIUM/LOW), so the diff-review fix floor actually fixes it; `drift` caps unchanged.
- Execution-grounded review runs no mutating command and reports `unverified` (not pass) when behavior can't be verified; **load-bearing** unverified correctness/security ⇒ `NEEDS_HUMAN`/blocking, not `PASS` (non-load-bearing ⇒ reported, non-blocking).
- Every fix worker (Phase 4.5 + drain) self-reviews its own diff for downstream regressions before push AND emits an observable `self_review:` note naming the risk classes checked.
- Subtask 3 (drain cosmetic-defer) is explicitly **deferred by evidence** — **no drain defer-semantics change ships in this run** (READY / remaining_issues / findings_validated / findings_dismissed are left untouched; no `findings_deferred` field added). Carried to a follow-up brief; NOT graded against this run's diff.
- No rubric-mirroring was introduced; the two review lenses remain independent.
- Invariants intact: `/review-pr` & Phase 4.5 never merge; sole `gh pr merge --squash` executor unchanged; emitters exit 0 / gates fail closed.
- Counts unchanged (14/19/56/20); version 14.43.0 consistent across authoritative surfaces; doc-currency + version-validate gates green; no `review-heal` single-source-of-truth mirror drift.

## Risk Assessment

| Risk | Severity | Source | Mitigation |
|---|---|---|---|
| Lever 2 re-drops a #64-style correctness MEDIUM if the cosmetic classifier mis-labels it | HIGH | Feasibility (Phase 2.5) | **MOOT this run — Subtask 3 DEFERRED by evidence.** (When revived as a follow-up: category-based not severity; conservative/fail-toward-fix; correctness fixed at any severity; tracks-never-drops.) |
| `review-heal/SKILL.md` SSoT referenced by `review-pr.md`, runner agent, `RESULT_SCHEMAS.md`, autonomous EVALUATE → mirror drift | MEDIUM | Feasibility (Phase 2.5) | Reduced now that Subtask 3 is deferred (Subtask 2 still edits the fix-worker prompt there); consistency_audit auto-triggers; reference-don't-restate discipline |
| Lever 2 may add risk without payoff if drain churn was real bugs, not cosmetics | — (resolved) | Evidence | **Confirmed real bugs, not cosmetics** (#31 `self_heal_misses=1`) → Subtask 3 deferred; the evidence instead validates Subtask 1 as the lever |
| Rigor lens finds a real bug but mislabels it MEDIUM → diff-review paths never fix it (the inert-lens gap) | HIGH | Review feedback (P1) | Subtask 1(c) severity rule: correctness/security/behavior regression ⇒ HIGH/BLOCKING; rubric + Phase 4.5 verify |
| "Execution-grounded" review runs a mutating command (snapshots/coverage/migrations) or fakes a pass | MEDIUM | Review feedback (P2) | Subtask 1(b) guardrails: non-mutating only; no update/fix/format/snapshot/migration; unverifiable ⇒ `unverified`, never silent-pass |
| Prose-as-program edits introduce undefined-flag / idempotency drift | MEDIUM | Lessons (`prompt-is-program`) | State-trace each edited loop; Plan Review dynamic trace |

## Configuration
- `--heal-iterations` default 3 (unchanged) · drain `--max-rounds` default 5 (unchanged)
- No new flags or schema changes in this run's active scope (Subtasks 1, 2, 4). (The additive optional `findings_deferred` field belongs to the **deferred** Subtask 3 and arrives only with its follow-up brief.)
- Suggested: `/supervisor --red-team` optional (high-risk review machinery change).

## Handoff
```
# Evidence already gathered (BetterBlocks ledger) → Subtask 3 DEFERRED.
# Active scope: Subtasks 1, 2, 4. In a fresh session:
/supervisor job: .supervisor/jobs/pending/2026-06-21-review-rigor-and-drain-discipline.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-06-22T00:21:00Z
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/76
- **Branch:** feature/review-rigor-and-severity
- **Files changed:** 11
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0
- **Heal remaining issues:** 0
- **Rubric score:** 8/8
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** true
- **Until-mergeable log:** .supervisor/logs/review-pr-dispatch-20260621T185031Z-3fc4d9e92172b6e7bdf9e8330e0a4cb9daf8d3cd.log
- **Subtask 3:** deferred by evidence (BetterBlocks #31 self_heal_misses=1; #32 no churn) — no drain cosmetic-defer semantics shipped
- **Summary:** Shipped v14.43.0 first-line review rigor — adversarial-input + execution-grounded lens + correctness⇒HIGH/BLOCKING severity rule in the shared code-reviewer (mirrored into the Self-Heal Miss-Class Checklist), and an observable anticipatory self_review gate on all 3 fix-worker prompts. Counts unchanged 14/19/56/20; doc-currency + validate-version green. Subtasks 1,2,4 done; Subtask 3 deferred.
