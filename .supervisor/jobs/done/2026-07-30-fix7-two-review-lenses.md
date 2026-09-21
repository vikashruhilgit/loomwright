# Supervisor Job: Two review lenses, not four passes — make the drain heal-only (deterministically, with an earned fallback) and drop the per-subtask LLM reviewer

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — committed 2026-07-30)
- **Git:** clean (0 files), branch: main @ 23a2b04
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (a stranded `in-progress/` brief from the crashed item-03 tick — see Risk Assessment; `.supervisor/jobs/` is Supervisor-owned and was deliberately not touched by the planner)
- **Source requirement:** .supervisor/requirements/final-state/04-fix7-two-review-lenses.md

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Markdown agent/skill/command prompts + shell scripts + JSON manifests — exactly this repo's substrate. No new language or runtime. |
| 2 | Dependency Availability | GO | `gh` authenticated, `jq`, `git`, `python3` present. The one new runtime read (has-a-review-lens-posted detection) reuses the drain's EXISTING §U1 all-channel read — no new dependency, no new fetch. |
| 3 | Architecture Fit | GO | Implements decision **D4** in `docs/SPIKES/FINAL_STATE_GOAL.md:35` and **Fix 7** in `docs/SPIKES/EVAL_FINDINGS_AND_FIXES.md`. Execution-order item 4 of the fixed plan; its stated prerequisite (item 01 single-agent default, v15.15.0) is MERGED. |
| 4 | Scope vs Supervisor Capability | CAUTION | ~21 file touches across ~21 distinct files exceeds the `context-bound` bound (> 12 files) in `skills/supervisor-readiness/SKILL.md` §"Decomposition Threshold" ⇒ split, `Split reason: context-bound`. Matches the precedent set by items 01 and 03 (both context-bound, serialized chains). |
| 5 | Hard Blockers | CAUTION | No hard blocker, but the requirement's **premise is only partly true as written** and one of its instructions would open a review hole if followed literally. Both are resolved in the Task/AC below and carried as HIGH risks. |

**Overall Verdict:** CAUTION — proceed; the two CAUTION findings are carried into Risk Assessment and have become acceptance criteria (AC-1, AC-3) rather than being planned around.

## Task

**Goal:** Collapse the default PR flow to **two LLM review lenses with different information** — Phase 4.5 (working tree + brief + rubric) and CI review (independent context, PR-only) — by making the until-mergeable drain **deterministically heal-only with an evidence-gated fallback**, dropping the per-subtask LLM reviewer above threshold in favour of the existing deterministic gate, and writing the counter-pressure rule that says when a pass is *owed*.

**Problem Statement:**

Maintainers of this plugin need every review pass on a PR to be *earned* because four passes were added independently, each defaulting ON, with no rule anywhere that a later pass skips what an earlier one covered. Currently the default flow runs: (1) a per-subtask `code-reviewer` per subtask, (2) the Phase 4.5 integrated review, (3) the detached `/review-pr --until-mergeable` drain, (4) CI `claude-review`. This causes duplicated LLM review of the same diff before a human ever sees it — review *count* substituted for review *quality*, since passes sharing a lens over the same diff find the same things repeatedly. Success looks like exactly two LLM lenses plus deterministic gates by default, each surviving pass carrying a written statement of the information it has that the prior pass lacked, and a before/after defect-rate measurement answerable from data already being collected.

**Two planner findings that change the shape of the work — do not plan around them, they are AC-1 and AC-3:**

**Finding A — pass 3's review half is NOT deterministically present; the spec contradicts itself.** The requirement says to "skip its own redundant diff review", which presumes that review reliably happens. Verified against the current source, it does not:

| Surface | What it says | Implication |
|---|---|---|
| `skills/review-heal/SKILL.md:223` | `--until-mergeable` is "layered *on top of* the default diff-only loop above" | Step 2's `Task(code-reviewer)` **does** run |
| `commands/review-pr.md:30` | "Layers the external-signal drain loop on top of the default diff-only loop" | Step 2 **does** run |
| `agents/review-pr.md:111` | "When `--until-mergeable` is **absent**, this runner runs the default diff-only loop… When present, run the drain loop per the skill" | Step 2 **does not** run |
| `skills/review-heal/SKILL.md` §U4 — "The bounded drain loop", the pseudocode fence (`:360-452`) | The drain-loop pseudocode contains **no `Task(loomwright:code-reviewer)` call at all** — its only spawn is the `general-purpose` fix worker. (Whole-file check: `code-reviewer` appears in that skill only at `:73`, `:78`, and Step 2's spawn at `:123`.) | Step 2 **does not** run |

So whether a second LLM diff review happens today depends on which sentence the executing model follows. **The deliverable is therefore "make it deterministic in the heal-only direction", not "remove a measured pass"** — and every one of those four surfaces must end up saying the same thing. (This is the "prompt is program — state-trace it" discipline: the contradiction is invisible to a static consistency audit because each surface is individually coherent.)

**Finding B — a blanket heal-only cut opens a review hole exactly on workflow-touching PRs.** The requirement's own scope item 4 says to verify the CI-healing role live before cutting. Doing so (asserting on posted comments/reviews, never on run conclusion) produced the evidence below, and it falsifies "just drop pass 3's review half":

| PR | Files | `claude-review` check | Posted comments | Posted reviews |
|---|---|---|---|---|
| #118 | 37 | **pass, 3m53s** | **1** (author `claude`) | 0 |
| #117 | 2, **both `.github/workflows/*`** | **pass, 14s** | **0** | 0 |
| #116 | — | pass | **5** | 0 |
| #115 | — | pass | **12** | 0 |

Two facts follow, both load-bearing:

1. **`claude-code-action` self-skips on any workflow-touching PR and still exits 0.** #117 is the proof: green in **14 seconds** with **zero** posted comments, versus #118's 3m53s with a real review. A green check is **not** evidence a review happened — so pass 4 is *not reliably present*, and on a PR that modifies CI it can never be present. If pass 3 becomes unconditionally heal-only, such a PR is left with **exactly ONE** LLM lens (Phase 4.5), not two — the opposite of D4's intent.
2. **Every real finding arrived as a PR *issue comment*; `reviews` was empty (0) on all four PRs.** So the drain's channel-draining half is genuinely load-bearing (it is the only thing that heals those findings), confirming it must **not** be touched — and any new detection logic must read the issue-comment channel, never `--json reviews`.

**Consequently the design is heal-only *by default* with an evidence-gated fallback**, which is a stricter reading of counter-pressure rather than an exception to it: a pass is owed when it has information the prior pass lacked, **or when the pass that was supposed to supply that information verifiably did not run.**

## Acceptance Criteria

> **Line-number convention governing every AC and subtask in this brief.** All `file:line` citations were verified against `main @ 23a2b04`, and each cited file is owned by **exactly one** subtask (see the File Overlap Matrix), so no pointer crosses a worker boundary. But a worker's own edits invalidate its remaining pointers mid-subtask, and "absolute line-ref drift in prose edits" is a recorded recurring failure mode in this repo. **Treat every line number as a first-look locator only, and re-find by the descriptive anchor given alongside it** — never trust a bare line number after your first edit to a file.

- [ ] **AC-1 (Finding A — determinism).** Given `--until-mergeable`, when the drain runs, then it performs **no diff review of its own** by default, and all four surfaces above (`skills/review-heal/SKILL.md`, `agents/review-pr.md`, `commands/review-pr.md`, and §U4's pseudocode) state that **identically** — the "layered on top of the default diff-only loop" composition phrasing is replaced everywhere by heal-only phrasing, leaving no surface from which a reader could conclude Step 2 still runs under the flag.
- [ ] **AC-2 (invariants intact).** Given the heal-only drain, when it terminates, then `READY` / `ESCALATED` semantics, the never-merges invariant, the fail-CLOSED-on-unknown-channel rule, the `--max-rounds` bound, and the anti-churn guardrail are **byte-for-byte unchanged**, and `--until-mergeable`-absent behaviour remains the byte-for-byte diff-only loop (AC7 of the original contract).
- [ ] **AC-3 (Finding B — earned fallback).** Given a PR where the drain's existing §U1 all-channel read finds **no review-producing lens actually posted** (no bot-authored review finding in any channel AND the review-producing check is green-with-empty-output, absent, or skipped), when the drain would otherwise declare READY, then it **runs exactly ONE diff review of its own first** (bounded, reusing Step 2's machinery, never more than once per drain run) so the PR always receives two lenses. The trigger is computed from data §U1 already fetches — **no new API call** — and it reads the **issue-comment** channel, never `--json reviews`. A read failure of that signal fails **CLOSED to running the review** (a review we did not need costs tokens; a review we needed and skipped costs a defect).
- [ ] **AC-4 (per-subtask LLM reviewer).** Given a run **above** the Decomposition Threshold (or on the Sequential Path), when a subtask's worker completes, then **no per-subtask `code-reviewer` is spawned**; the deterministic `outputs_verified` gate (`agents/execute-manager.md`, the `# --- v12 outputs_verified gate (BEFORE spawning reviewer) ---` block, `:220-228`) plus tests/lint is the per-subtask gate, and the integrated Phase 4.5 review is the LLM gate. Below threshold this is already the behaviour (v15.15.0, item 01) and must not regress. All four restating surfaces are synced in the same PR: `agents/execute-manager.md` (the `subagent_type: "loomwright:code-reviewer"` line inside the `# Spawn reviewer in background` block, `:272`), `agents/orchestrator.md` §"Review Gate Policy", `skills/async-orchestration/SKILL.md` (its per-subtask reviewer spawn contract, `:781`), `skills/workflow-management/SKILL.md` (the `--sequential` path line promising "per-subtask reviewer runs", `:62`).
- [ ] **AC-5 (counter-pressure rule).** Given the plugin's standards doc, when a reader asks "is this pass owed?", then a single authoritative rule answers it — written once in `AGENT_GUIDELINES.md` as a sibling of §"Read-Before-Write Verification Gate" — stating (a) a pass is owed only if it has information the prior pass lacked, (b) it is also owed when the pass expected to supply that information verifiably did not run, and (c) review count is not review quality. Each **surviving** pass cites it by path, and no surviving pass restates it.
- [ ] **AC-6 (measurement).** Given the postmortem corpus, when this change lands, then the **pre-change baseline is recorded in-repo** with its capture date and per-source means, together with the exact re-measurement command, so "did dropping a pass raise the defect rate?" is answerable later from data already collected rather than argued.
- [ ] **AC-7 (release surface).** Given the doc-currency and version gates, when CI runs, then all 7 repo gates pass: counts (14 agents / 21 commands / 41 skills / 24 hooks — **all unchanged by this work**), the version bump is applied in-place across every surface, `check-token-budget.sh` is green (raise with a mirror + raise-log entry if a touched agent breaches, per the v15.16.0/v15.17.0 precedent), and the `gh pr merge --squash` single-executor invariant grep still resolves to exactly its four sanctioned surfaces.

## Outcomes Rubric
- Drain reduced to heal-only with invariants intact
- Per-subtask LLM review removed above/below threshold per item-01 design
- Counter-pressure rule written and cited by the passes that survive
- Before/after measurement plan recorded with baseline

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Counter-pressure rule — the authority | AC-5 | 1 modify, 0 create | `skills/quality-checklist/SKILL.md` | LAUNCHABLE |
| 2 | Drain heal-only + earned fallback (4 surfaces) | AC-1, AC-2, AC-3 | 3 modify, 0 create | `skills/review-heal/SKILL.md`, `skills/quality-checklist/SKILL.md` | BLOCKED (by #1) |
| 3 | Per-subtask LLM reviewer removal above threshold | AC-4 | 5 modify, 0 create | `skills/async-orchestration/SKILL.md`, `skills/quality-checklist/SKILL.md` | BLOCKED (by #1) |
| 4 | Supervisor-side mirrors + schema + checklist citations | AC-2, AC-4, AC-5 | 4 modify, 0 create | `skills/quality-checklist/SKILL.md` | BLOCKED (by #2, #3) |
| 5 | Measurement record + release surface + all 7 gates | AC-6, AC-7 | 8 modify, 0 create | `skills/commit/SKILL.md` | BLOCKED (by #4) |

**Totals:** 0 created + 21 modified = **21 file touches** across **21 distinct files** (no file appears in two subtasks — see the File Overlap Matrix).

### Subtask 1 — Counter-pressure rule, the authority (LAUNCHABLE)

Scope: `AGENT_GUIDELINES.md` ONLY.

Add a top-level `## Review Counter-Pressure Rule` section (sibling of the existing `## Read-Before-Write Verification Gate` at `:29`) stating the rule in three parts:

1. **A pass is owed only if it has information the prior pass lacked.** Same lens over the same diff finds the same things — review count is not review quality.
2. **A pass is ALSO owed when the pass expected to supply that information verifiably did not run.** Verifiably means asserted on posted output (comments/reviews), never on a run conclusion — cite the #117 evidence (workflow-touching PR, `claude-review` green in 14s, zero posted comments) as the concrete case.
3. **Deterministic gates are not passes** and are never traded against this rule — they cost no tokens and carry no lens.

Also record the default flow's two sanctioned lenses and each one's information advantage, so a future addition has to argue against a written baseline:

| Lens | Information it has that the other lacks |
|---|---|
| Phase 4.5 integrated review | The working tree, the brief, and the Outcomes Rubric — it can check intent-vs-implementation, not just the diff |
| CI review (`claude-review`) | Fully independent context, PR-only — no memory of the authoring session, so it cannot inherit the implementer's blind spots |

```yaml
provides:
  - {kind: "file", path: "AGENT_GUIDELINES.md"}
  - {kind: "symbol", path: "AGENT_GUIDELINES.md", name: "## Review Counter-Pressure Rule"}
requires: []
external_requires: []
```

### Subtask 2 — Drain heal-only + earned fallback (BLOCKED by #1)

Scope: `loomwright/skills/review-heal/SKILL.md` (authority), `loomwright/agents/review-pr.md`, `loomwright/commands/review-pr.md`.

1. **Kill the contradiction (AC-1).** In `skills/review-heal/SKILL.md` §"Until-Mergeable Mode" (`:219-225`), replace "an **opt-in, strictly additive** drain loop layered *on top of* the default diff-only loop above" with heal-only phrasing: under `--until-mergeable` the drain **replaces** the diff-only loop's review half and runs no `code-reviewer` of its own by default. Mirror the identical statement in `commands/review-pr.md:30` and `agents/review-pr.md:97` + `:111`. Keep the AC7 sentence ("absent ⇒ byte-for-byte the diff-only loop") intact and unchanged — it is about the flag being absent and stays true.
2. **State it in §U4's pseudocode** so the executable-shaped surface agrees with the prose: an explicit comment that the drain loop deliberately contains no `code-reviewer` call, with the fallback below as the ONE exception.
3. **Add the earned fallback (AC-3)** as a new subsection of §"Until-Mergeable Mode", named and defined ONCE here (the other two surfaces reference it, never restate it). Contract:
   - **Trigger, computed from §U1's existing read — no new fetch:** `no_review_lens_posted` is true when the union of bot-authored review findings across ALL channels is **empty** AND every review-producing check is green-with-empty-output, absent, or skipped. The issue-comment channel is authoritative for "posted" (`reviews` was empty on all four measured PRs); never gate on `--json reviews`.
   - **Effect:** before declaring `READY`, run **exactly one** `Task(loomwright:code-reviewer)` diff review (Step 2's machinery, `review_mode: diff_review`), at most **once per drain run** — enforce with a run-scoped `fallback_review_ran` flag so the outer `while rounds < max_rounds` loop can never re-trigger it. Findings feed the existing validate-then-fix path; the run remains bounded by `--max-rounds`.
   - **Fail-CLOSED direction is TO running the review:** if the signal cannot be computed (any channel unknown), run the fallback review. Note explicitly that this is the opposite direction from the channel-unknown ⇒ `ESCALATED` rule and say why — an unnecessary review wastes tokens, a skipped necessary review ships a defect. Do **not** let this weaken §U1's existing unknown-channel `ESCALATED` behaviour: both apply, and `ESCALATED` still wins for readiness.
   - **Cite** `AGENT_GUIDELINES.md` §"Review Counter-Pressure Rule" as the reason this fallback exists (AC-5's citation duty).
   - **Record WHY the fallback's `Task(loomwright:code-reviewer)` spawn is legal here** (load-bearing — this repo's most expensive runtime trap). §U4's loop today spawns only `general-purpose`; adding a `code-reviewer` spawn makes the drain loop spawn-dependent for the first time. It is safe **only because every caller that can reach `--until-mergeable` runs as the main agent of its own process** — the detached `-runner` launched by `dispatch-pr-review.sh`, or an inline `/review-pr` on the main thread — both spawn-capable. Note explicitly that the `/autonomous` EVALUATE Task step is **not** such a caller, and that **routing the drain through a Task step in future would turn this fallback into a hard failure** — "subagents cannot spawn subagents" (`agents/review-pr.md:73-78`, the 11.1.1 `-runner` trap). Write this next to the fallback so a future caller-side change cannot break it silently.
     **Cite the two halves of the EVALUATE argument separately — they live in different subsections of `docs/RESULT_SCHEMAS.md` §"REVIEW_HEAL_RESULT" and conflating them produces an unsupported sentence:**
     - *"the EVALUATE step is a non-`--until-mergeable` caller and emits v1"* → the **§"Schema versions (v1 still accepted)"** `schema_version: 2` bullet (`:1974`), which is where the non-caller set is actually enumerated ("every non-`--until-mergeable` caller — the default `/review-pr` loop, the plain-`/supervisor` completion-tail auto-dispatch, and the `/autonomous` EVALUATE step — continues to emit `schema_version: 1`").
     - *"the EVALUATE step runs as a Task-spawned step"* → **§"Emission contexts"** (`:1978`). This is the half that makes the spawn hazard concrete, so keep it.
     (§"Emission contexts" is a **bold paragraph, not a `###` heading** — grep the text, not a heading. Do not cite it for the non-caller fact: `:1978` says only that the step is Task-spawned and parses the block; it never mentions `--until-mergeable` or `schema_version`.)
4. **Invariants (AC-2):** do not touch `READY`/`ESCALATED` definitions, never-merge, the fail-CLOSED channel rules, `--max-rounds`, the anti-churn guardrail, fork-aware push, or the postmortem tail. If `REVIEW_HEAL_RESULT` gains a field for the fallback, it must be **additive and optional** — Subtask 4 owns the schema doc.

```yaml
provides:
  - {kind: "symbol", path: "loomwright/skills/review-heal/SKILL.md", name: "no_review_lens_posted"}
  - {kind: "symbol", path: "loomwright/agents/review-pr.md", name: "no_review_lens_posted"}
  - {kind: "file", path: "loomwright/commands/review-pr.md"}
requires:
  - {from: "1", kind: "symbol", path: "AGENT_GUIDELINES.md", name: "## Review Counter-Pressure Rule"}
external_requires: []
```

### Subtask 3 — Per-subtask LLM reviewer removal above threshold (BLOCKED by #1)

Scope: `loomwright/agents/execute-manager.md`, `loomwright/agents/orchestrator.md`, `loomwright/skills/async-orchestration/SKILL.md`, `loomwright/skills/workflow-management/SKILL.md`, `loomwright/skills/self-heal-advisory/SKILL.md`.

1. **`agents/execute-manager.md`:** delete the per-subtask reviewer spawn at `:272` (`Task(subagent_type: "loomwright:code-reviewer", run_in_background: true, …)`) and the reviewer-polling arm that consumes its `CODE_REVIEW_RESULT`. **Keep** the deterministic `outputs_verified` gate at `:220-228` and its adjudication path — that gate, plus tests/lint, becomes the per-subtask gate. Removing the reviewer must not orphan the poll loop's bookkeeping (`results_found` / `idle_streak` / `poll_interval`) or the `record_review` calls the v15.16.0 fix added on the FAIL==3 / NEEDS_HUMAN terminal branches; re-point or remove them coherently and state which.
2. **`agents/orchestrator.md`** §"Review Gate Policy" (`:47`, marked *authoritative — cited elsewhere, not restated*): rewrite so **both** sides of the threshold use the deterministic gate + integrated Phase 4.5 review, and no paired LLM review subtask is generated at any threshold. Keep the Beads/file-fallback persistence-mode branch working.
3. **`skills/async-orchestration/SKILL.md:781`:** remove the per-subtask reviewer spawn contract; keep the worker spawn contract and worktree lifecycle untouched.
4. **`skills/workflow-management/SKILL.md:62`:** fix the Sequential-Path line that still promises "per-subtask reviewer runs".
5. **`skills/self-heal-advisory/SKILL.md`:** update `:630` ("Previous per-subtask reviews all passed — look for issues only visible in the integrated view"), which is now false. Adjust the `:617` ANTI-OVERLAP rule so it no longer names a per-subtask review as a prior gate that could have found something, while keeping deterministic gates and earlier heal iterations in its scope.
6. **Record the side benefit** where the change is made: dropping the per-subtask LLM reviewer also eliminates the worktree-isolation cross-file false-positive class (a per-subtask reviewer cannot see sibling worktrees, so it produced false `NEEDS_HUMAN` on producer/consumer contracts).
7. **Cite the counter-pressure rule at the two removal sites (this is what consumes Subtask 1's contract).** A future reader standing at a removal site will ask "why is there no per-subtask lens here?", and the answer must be one path reference away rather than re-argued. Cite `AGENT_GUIDELINES.md` §"Review Counter-Pressure Rule" **by path, with no restatement** at exactly the two places that question arises: (a) `agents/orchestrator.md` §"Review Gate Policy", where the gate is decided; and (b) the `skills/self-heal-advisory/SKILL.md` ANTI-OVERLAP rule (`:617`), where the list of prior gates is being changed. AC-5's citation duty formally binds *surviving* passes — this step extends the same discipline to the *removal* sites, and is the step that makes Subtask 3's `requires` edge on Subtask 1 real rather than merely ordering.

```yaml
provides:
  - {kind: "symbol", path: "loomwright/agents/orchestrator.md", name: "Review Gate Policy"}
  - {kind: "symbol", path: "loomwright/agents/execute-manager.md", name: "outputs_verified"}
  - {kind: "file", path: "loomwright/skills/async-orchestration/SKILL.md"}
  - {kind: "file", path: "loomwright/skills/workflow-management/SKILL.md"}
  - {kind: "file", path: "loomwright/skills/self-heal-advisory/SKILL.md"}
requires:
  - {from: "1", kind: "symbol", path: "AGENT_GUIDELINES.md", name: "## Review Counter-Pressure Rule"}
external_requires: []
```

### Subtask 4 — Supervisor-side mirrors, schema, checklist citations (BLOCKED by #2, #3)

Scope: `loomwright/agents/supervisor.md`, `loomwright/commands/supervisor.md`, `loomwright/docs/RESULT_SCHEMAS.md`, `loomwright/skills/quality-checklist/SKILL.md`.

1. **`agents/supervisor.md` + `commands/supervisor.md`:** sync every restatement of the drain's role (Phase 4.5 step 5.5 dispatch prose, the `auto_until_mergeable` default-ON description at `commands/supervisor.md:60`, and any Phase-3 text implying a per-subtask reviewer) to heal-only + the earned fallback. **Do not** change the dispatch paths themselves (step 5.5 and the `PostToolUse[Bash]` hook) — the requirement's non-goals forbid it. Preserve the Phase 4.5 completion-tail guard and the `phase45_review_invoked` invariant exactly.
2. **`docs/RESULT_SCHEMAS.md`:** if Subtask 2 added a `REVIEW_HEAL_RESULT` field for the fallback, document it as **optional/additive** at the existing `schema_version: 2` (no bump); if it added none, state explicitly that no schema change was needed. Also confirm `CODE_REVIEW_RESULT` is unaffected.
3. **`skills/quality-checklist/SKILL.md`:** add the gate question ("is this pass owed? cite `AGENT_GUIDELINES.md` §Review Counter-Pressure Rule") — a **citation by path only**, no restatement of the rule.
4. **Anti-drift sweep for this subtask:** grep the OLD phrasings repo-wide before finishing — `grep -rn "on top of the default diff-only\|layered on top\|per-subtask review\|paired review" loomwright/ *.md` — and confirm every remaining hit is either intentionally historical (a dated CHANGELOG / release-banner entry, which is exempt) or fixed. A green doc-currency run is necessary but not sufficient here; Supervisor phase enumerations and command Parameters-table prose are documented as unscanned by that gate.

```yaml
provides:
  # NOTE: `auto_until_mergeable` already exists on main (commands/supervisor.md:60), so a bare
  # presence check is VACUOUS — it passes whether or not you rewrote the row. Post-edit predicate
  # for your own outputs_verified entry: that row must state the drain's heal-only role AND the
  # earned fallback. Verify by CONTENT, not existence.
  - {kind: "symbol", path: "loomwright/commands/supervisor.md", name: "auto_until_mergeable"}
  - {kind: "file", path: "loomwright/agents/supervisor.md"}
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "REVIEW_HEAL_RESULT"}
  - {kind: "symbol", path: "loomwright/skills/quality-checklist/SKILL.md", name: "Review Counter-Pressure Rule"}
requires:
  - {from: "2", kind: "symbol", path: "loomwright/skills/review-heal/SKILL.md", name: "no_review_lens_posted"}
  - {from: "3", kind: "symbol", path: "loomwright/agents/orchestrator.md", name: "Review Gate Policy"}
external_requires: []
```

### Subtask 5 — Measurement record + release surface + all 7 gates (BLOCKED by #4)

Scope: `loomwright/docs/SPIKES/EVAL_FINDINGS_AND_FIXES.md`, `loomwright/docs/SPIKES/FINAL_STATE_GOAL.md`, `CLAUDE.md`, `CHANGELOG.md`, `README.md`, `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `loomwright/commands/agent-help.md`.

1. **Measurement record (AC-6)** — append to `docs/SPIKES/EVAL_FINDINGS_AND_FIXES.md` under Fix 7 a **Baseline (pre-change)** block recording, verbatim and with its capture date:
   - Corpus: `.supervisor/postmortem/results.jsonl`, **n=77 at 2026-07-29**.
   - Per-source `review_rounds` means: **legacy (`source: null`) n=50 mean 3.42** (5 zero-round); **`automate_drain` n=17 mean 2.82** (2 zero-round); **`manual_postmortem` n=10 mean 3.80** (0 zero-round); **overall mean 3.34**.
   - The re-measure command, so the after-figure is produced the same way:
     ```
     jq -rs 'group_by(.source)[]|{src:(.[0].source//"legacy"),n:length,mean:((([.[].review_rounds]|add)/length)*100|round/100)}' .supervisor/postmortem/results.jsonl
     ```
   - **Honesty note (required):** these means mix requirement difficulty and plugin version across months and are **not** a controlled before/after. They are a *trend* baseline; a rise after this change is a prompt to investigate, not proof of causation. Say so — do not present it as a measured result.
   - Also record the **live CI-healing verification** (the #118/#117/#116/#115 table from the Task section) as the evidence that pass 4 posts real findings via issue comments and self-skips on workflow PRs — and record it **reproducibly**, with the capture date (**2026-07-30**) and the exact commands used, the same discipline AC-6 applies to the jq re-measure. Anyone re-checking it should run, per PR:
     ```
     gh pr view <n> --json comments,reviews \
       -q '"comments: \(.comments|length) | reviews: \(.reviews|length)", (.comments[]|"  C \(.author.login)")'
     gh pr checks <n>          # for the check name + duration (14s self-skip vs 3m53s real review)
     gh pr view <n> --json files -q '[.files[].path]|map(select(test("\\.github/workflows")))'
     ```
     State plainly that these are **four observations on one repo**, not a controlled sample — the self-skip *mechanism* is documented upstream behaviour and #117 is one confirming instance, not a measured rate.
2. **`docs/SPIKES/FINAL_STATE_GOAL.md`:** mark execution-order item 4 (D4) as shipped, and record that D4's "drain becomes heal-only" was implemented as heal-only **plus an evidence-gated fallback**, with the #117 finding as the reason — so the decision record carries the amendment rather than a later reader concluding the plan was not followed.
3. **Release surface (AC-7):** version bump applied in-place everywhere (`plugin.json`, `marketplace.json`, the `Loomwright vX.Y.Z` headline, `CLAUDE.md` banner — keeping only the two most recent release notes per its own rule, `CHANGELOG.md` entry, `README.md`); counts stay **14 / 21 / 41 / 24** (this change adds no agent, command, skill, or hook); `commands/agent-help.md` synced if it describes the drain's review half.
   - Do **not** append another version clause to the plugin `description` — update the version string and counts in place (anti-rebloat rule).
   - Do **not** "fix" frozen illustrative example versions in `RESULT_SCHEMAS.md`-style sample blocks — they are deliberately version-agnostic.
4. **Run all 7 gates** (`scripts/validate-version.sh`, `check-doc-currency.sh`, `check-skills-index-sync.sh`, `check-command-sync.sh`, `check-contract-parity.sh`, `check-token-budget.sh`, `check-shared-prefix.sh`). `check-token-budget.sh` is the one at real risk: `supervisor` has only **741** proxy tokens of headroom and `orchestrator` **788**. Net deletion should help, but if a budget breaches, **raise it with the mirror row in `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" and a raise-log note in the same commit** (the v15.16.0 / v15.17.0 precedent) — never silently trim prose to fit.
5. **Invariant re-check:** `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` must still resolve to exactly its four sanctioned surfaces.

```yaml
provides:
  - {kind: "symbol", path: "loomwright/docs/SPIKES/EVAL_FINDINGS_AND_FIXES.md", name: "Baseline (pre-change)"}
  - {kind: "symbol", path: "loomwright/docs/SPIKES/FINAL_STATE_GOAL.md", name: "D4"}
  - {kind: "file", path: "CHANGELOG.md"}
  - {kind: "file", path: "CLAUDE.md"}
  - {kind: "file", path: "README.md"}
  - {kind: "file", path: "loomwright/.claude-plugin/plugin.json"}
  - {kind: "file", path: ".claude-plugin/marketplace.json"}
  - {kind: "file", path: "loomwright/commands/agent-help.md"}
requires:
  - {from: "4", kind: "symbol", path: "loomwright/commands/supervisor.md", name: "auto_until_mergeable"}
  - {from: "4", kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "REVIEW_HEAL_RESULT"}
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──┬──→ Subtask 2 ──┬──→ Subtask 4 ──→ Subtask 5
            └──→ Subtask 3 ──┘
```

Subtask 1 writes the rule that Subtasks 2 and 3 must cite by path, so it goes first. Subtasks 2 and 3 are genuinely independent (disjoint file sets, no shared symbol). Subtask 4 mirrors both into the Supervisor surfaces and the schema, so it needs both. Subtask 5 is the release surface and must be last so the version bump and gates see the final tree.

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none (contract dep only) | YES (contract) |
| Subtask 1 | Subtask 3 | none (contract dep only) | YES (contract) |
| Subtask 2 | Subtask 3 | **none** | NO |
| Subtask 2 | Subtask 4 | none | YES (contract) |
| Subtask 3 | Subtask 4 | none | YES (contract) |
| Subtask 4 | Subtask 5 | none | YES (contract) |

No file appears in two subtasks, so every serialization above is a *contract* dependency, not a write conflict.

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2, Subtask 3 (parallel — disjoint files)
- **Batch 3:** Subtask 4
- **Batch 4:** Subtask 5
- **Recommended workers:** 2
- **Estimated batches:** 4

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/quality-checklist/SKILL.md` |
| 2 | `skills/review-heal/SKILL.md`, `skills/quality-checklist/SKILL.md` |
| 3 | `skills/async-orchestration/SKILL.md`, `skills/workflow-management/SKILL.md`, `skills/self-heal-advisory/SKILL.md`, `skills/quality-checklist/SKILL.md` |
| 4 | `skills/self-heal-advisory/SKILL.md`, `skills/workflow-management/SKILL.md`, `skills/quality-checklist/SKILL.md` |
| 5 | `skills/commit/SKILL.md`, `skills/quality-checklist/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Review hole on workflow-touching PRs.** A blanket heal-only cut leaves one LLM lens where `claude-code-action` self-skipped. Verified live: #117 (2 workflow files) → `claude-review` green in **14s**, **0** posted comments, vs #118 green in 3m53s with a real review. | **HIGH** | AC-3's earned fallback — the drain runs exactly one diff review when §U1's existing read shows no review lens posted. Fails CLOSED *to running* the review. Source: Feasibility (Phase 2.5) check 5. |
| **The premise "the drain runs a redundant diff review" is only conditionally true** — four surfaces disagree (Finding A table). A worker told to "remove" it may find nothing to remove and either no-op or delete the wrong thing. | **HIGH** | AC-1 reframes the deliverable as *make it deterministic*, and names all four surfaces explicitly, including §U4's pseudocode. Precedent: item 03's 4d was correctly dropped on a falsified premise — here the premise is repaired, not dropped. Source: Feasibility (Phase 2.5) check 5. |
| **Detection built on `--json reviews` would see nothing.** All four measured PRs had `reviews: 0`; every real finding was a PR **issue comment** (the #64 channel gap). | **HIGH** | AC-3 pins the issue-comment channel as authoritative and forbids gating on `reviews`. Reuses §U1's existing all-channel read — no new fetch, no invented `--json reviewThreads` flag. |
| **AC-3 makes the drain loop spawn-dependent for the first time.** §U4 today spawns only `general-purpose`; the fallback adds a `Task(loomwright:code-reviewer)`. Safe as scoped — every `--until-mergeable` caller is the main agent of its own process (detached `-runner`, or inline `/review-pr`), and the `/autonomous` EVALUATE Task step never passes the flag — but this repo's most expensive trap is "subagents cannot spawn subagents". | MEDIUM | Subtask 2 step 3 must record the reachability argument **next to the fallback**, naming the legal callers, the EVALUATE step as a non-caller, and the consequence of ever Task-nesting a drain caller. **Cite the two halves separately** — `docs/RESULT_SCHEMAS.md` §"Schema versions (v1 still accepted)" `schema_version: 2` bullet (`:1974`) for the non-caller enumeration, and §"Emission contexts" (`:1978`) for the Task-spawned fact; `:1978` alone does not support the non-caller claim. Latent doc gap, not a live failure. |
| **Removing the per-subtask reviewer could orphan Execute Manager's poll-loop bookkeeping** (`results_found`, `idle_streak`, `poll_interval`) or the `record_review` calls the v15.16.0 fix added on the FAIL==3 / NEEDS_HUMAN branches. | MEDIUM | Subtask 3 step 1 requires re-pointing or removing them coherently and stating which — a state-trace of the loop, not a line delete. |
| **`supervisor` token budget has only 741 proxy tokens of headroom** (`orchestrator` 788) and Subtask 4 edits `agents/supervisor.md`. | MEDIUM | Net deletion should help; if a budget breaches, raise it with the mirror row + raise-log in the same commit (v15.16.0/v15.17.0 precedent). Never trim prose to fit a budget. |
| **Self-referential execution.** Running this brief above threshold uses the Sequential/parallel path, so the very per-subtask reviewers it deletes will review it. | LOW | Expected and harmless — the change is not in force until merged. Same shape as item 01's brief, which recorded the threshold rule it was introducing as not-yet-in-force. |
| **Mirror drift across ~6 restating surfaces** — this is the repo's most-recurring failure mode, and the doc-currency gate does **not** scan Supervisor phase enumerations or command Parameters-table prose. | MEDIUM | Subtask 4 step 4 mandates an explicit OLD-phrasing grep sweep; AC-1 requires all four drain surfaces to state the rule identically. |
| **Stranded `in-progress/` brief.** `.supervisor/jobs/in-progress/2026-07-29-fix4-cheap-batch.md` remains from the crashed item-03 tick even though PR #118 merged (the Phase 4.5 completion tail never ran). | LOW | Deliberately untouched — `.supervisor/jobs/` is Supervisor-owned and the planner must not write it. Supervisor's Phase 0/1 should reconcile or ignore it; if it interferes, resolve by hand rather than from a worker. |
| **Overall verdict was CAUTION**, so its findings are HIGH risks by construction. | — | Both CAUTION findings became AC-1 and AC-3 rather than being planned around. Source: Feasibility (Phase 2.5). |

## Configuration
- **Workers:** 2
- **Mode:** parallel
- **Estimated batches:** 4
- **Base Branch:** main
- **Split reason:** context-bound

> **Split reason justification (`context-bound`, per `skills/supervisor-readiness/SKILL.md` §"Decomposition Threshold"):** 21 file touches across 21 distinct files exceeds the `> 12 files changed` bound. Checked against the other two legal reasons and neither fires: `file-conflict` does not (the File Overlap Matrix shows **zero** shared files — every serialization is a contract dependency), and `genuine-parallelism` is not the *trigger* (it happens to hold for Subtasks 2 and 3 at 3 and 5 files, which is why they share Batch 2, but the reason forcing the split is context, not fan-out). Same trigger and same serialized-chain shape as items 01 and 03.

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-07-30-fix7-two-review-lenses.md
```

---

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/119
- **Branch:** feature/fix7-two-review-lenses (base: main)
- **Commits:** 8290db4 (implementation) · 314f1cb (heal 1) · 304871e (heal 2) · f4953f6 (follow-ups)
- **Diff:** 32 files, +485/−468
- **Version:** 15.17.0 → 15.18.0 · counts UNCHANGED 14 agents / 21 commands / 41 skills / 24 hooks
- **heal_loop_ran:** true · **heal_iterations:** 2 · **heal_decision:** PASS
- **rubric_score:** 4/4
- **red_team_advisory:** disabled (--red-team not passed)
- **All 7 CI gates:** green
- **Until-mergeable dispatched:** false (SUPPRESSED — `/automate` owns exactly one inline drain per §7)

### Review rounds (each found what the prior missed — all in mirror surfaces, none in logic)
1. **FAIL** — `docs/FAILURE_ESCALATION.md` documented the deleted Phase-3 reviewer escalation flow as live; `agents/supervisor.md` self-contradicted this same diff at 4 sites.
2. **FAIL** — the sweep was still incomplete: heal 1 used a case-SENSITIVE literal grep, so `Worker/reviewer` and `workers and reviewers` survived two lines below an already-fixed line.
3. **PASS** — reviewer closed its own two coverage gaps and found `record_review` documented as live with zero callers.

### Per-subtask review outcomes
ST-1 PASS (1 nit) · ST-2 FAIL→PASS · ST-3 PASS (4 findings fixed) · ST-4 / ST-5 gated deterministically + covered by Phase 4.5.

**ST-2's FAIL is the substantive one:** the earned-fallback feature was a NO-OP as written — it ran the review then discarded the findings, because `auto_fixable`/`needs_human` were bound before the fallback executed, so the READY gate read stale values. Every sentence was individually coherent; doc-currency and a static consistency audit both passed it. Only state-tracing the pseudocode caught it.

### Two planner findings that reshaped the requirement
- The drain's "redundant diff review" was **not deterministically running** — four surfaces contradicted each other, one contradicting itself. Deliverable became *make it deterministic*, not *remove a measured pass*.
- A blanket heal-only cut would have opened a **review hole**: PR #117 (2 workflow files) saw `claude-review` pass green in 14s with zero posted comments — the documented self-skip — vs #118's 3m53s with a real review. Hence heal-only **plus** an evidence-gated fallback failing CLOSED toward running.

### Scope additions beyond the brief's 21-file enumeration (all mirror surfaces)
`commands/orchestrator.md` · `.claude-plugin/README.md` · `docs/FAILURE_ESCALATION.md` · 7 further `worker/reviewer` sites · `prompt-token-budgets.json` + `ARCHITECTURE_CONTRACTS.md` (4 budget raises).
**Root cause:** the plan was thorough on *logic* surfaces and under-counted *restatement* surfaces — which is exactly what the `prior_churn` advisory predicted for these paths (`convention_mismatch` dominant, 61 prior rounds, `self_heal_miss` recorded).

### Verified non-fixes (checked, not assumed)
- `--cheap` lists naming `code-reviewer` are TRUE — the profile still overrides the Phase 4.5 reviewer and fix tasks.
- The Subtasks `Review` column is harmless — `reconcile-resume-state.sh` reads only ID (col 1) and Status (col 3).
- "Sequential keeps its reviewer" survives only in the dated v15.15.0 CHANGELOG entry; the live surface already says otherwise.
- `sdk-spike/` + `docs/SPIKES/*` excluded by this PR's non-goals; `IMPROVEMENTS_ROADMAP.md:62` is a true hook-coverage claim.
