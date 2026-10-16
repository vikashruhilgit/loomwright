# Rationale — Launch Pad and /autonomous

Stories, history, examples and explanations moved out of the runtime prompts of the `launch-pad-autonomous` loop group (`agents/launch-pad.md`, `commands/launch-pad.md`, `skills/autonomous-loop/SKILL.md`, `commands/autonomous.md`). Nothing here is read at runtime and nothing here is a rule: every rule stayed in a runtime prompt or moved to the script that enforces it (`docs/loop-inventory/launch-pad-autonomous.md` records each row's home). A `story` row's home is `rationale:docs/rationale/launch-pad-autonomous.md#<slug>`, where `<slug>` is one of the headings below (lowercase, spaces to `-`, other characters dropped).

## Launch Pad — inputs, outputs and why

### Launch Pad inputs

- **Goal:** Raw user objective (`goal:`, `feature:`, or `problem:`) — OR a path to a requirement file (next bullet)
- **Requirement file (optional):** When the `goal:`/`feature:`/`problem:` value is the path to an existing `.md` file **under `.supervisor/requirements/`** (the Beads-absent Product Owner handoff target), Launch Pad reads that file and treats its contents as the requirement source instead of the literal string. Paths outside that directory (e.g. `README.md`) stay literal goals. Resolves the PO→Launch Pad handoff in Beads-optional mode.
- **CLAUDE.md:** Project context and patterns
- **Git state:** Current branch, working tree status
- **Flags:** `--discovery`, `--skip-validation`, `--project`

The requirement-file rule itself (scoped to `.supervisor/requirements/`, `test -f`, literal-goal fallback) lives in Phase 2 step 0 of both Launch Pad prompts.

### Launch Pad outputs

- **Supervisor-Ready Brief:** Structured markdown file saved to `.supervisor/jobs/pending/{date}-{slug}.md`
- **Supervisor command:** Exact `/supervisor job: {path}` command for a fresh-context session
- **Environment report:** Blockers and warnings from validation

### Why use Launch Pad

The Supervisor's context budget gets consumed by Phases 0-2 (planning) before any code execution begins. Launch Pad:

1. **Frees planning context** for Supervisor's execution phases (Phases 0-2 are pre-answered by the brief)
2. **Enables plan review** before workers start (no wasted effort)
3. **Prevents environment failures** mid-run (pre-flight validation)
4. **Improves parallelism** with file impact analysis (accurate overlap detection)
5. **Provides clean handoff** via `.supervisor/jobs/pending/` (fresh session, full context)
6. **Catches infeasible goals early** via Phase 2.5 (before wasting tokens on analysis and execution)

## Launch Pad — how to use

### Step 1: Run Launch Pad

```bash
/launch-pad goal: "add user authentication with JWT"
```

### Step 2: Review the Brief

- Check acceptance criteria are complete
- Verify file impact map matches your expectations
- Confirm subtask boundaries make sense
- Review parallelism analysis (is it conservative enough?)

### Step 3: Refine or Save

- Choose "Save and exit" if the brief looks good
- Choose "Refine further" to ask more questions
- Choose "Edit sections" to change specific parts

### Step 4: Start Fresh Session

```bash
# In a NEW Claude Code session (clean context):
/supervisor job: .supervisor/jobs/pending/2026-02-08-jwt-auth.md
```

### When to use Launch Pad vs direct Supervisor

| Scenario | Use |
|----------|-----|
| Complex task (>3 subtasks expected) | `/launch-pad` then `/supervisor job:` |
| Want to review plan before execution | `/launch-pad` then `/supervisor job:` |
| Simple task (1-2 subtasks) | `/supervisor` directly |
| Resuming interrupted work | `/supervisor --continue` |
| Quick fix or bug | `/supervisor task: "fix the bug"` |

### Workflow positioning

```
/launch-pad goal: "..."
    ↓
Validates environment, checks feasibility, analyzes codebase, decomposes subtasks
    ↓
Plan Reviewer validates brief (mandatory gate, max 3 spawns per session)
    ↓
.supervisor/jobs/pending/{date}-{slug}.md  (Supervisor-Ready Brief)
    ↓
/supervisor job: .supervisor/jobs/pending/{file}.md  (clean context execution)
    ↓
EXECUTE → FINALIZE → PR
```

### Further tips

- **Review file impact map carefully:** This is where Launch Pad adds the most value — catch wrong assumptions early
- **Trust the parallelism analysis:** If Launch Pad says BLOCKED, there's likely a reason (file overlap or dependency)

### Related commands

| Command | Purpose |
|---------|---------|
| `/supervisor` | Execute the workflow (consumes the brief) |
| `/supervisor job: {path}` | Execute from a Launch Pad brief |
| `/orchestrator` | Plan tasks without execution (no brief, no file analysis) |
| `/product-owner` | Define requirements only (no codebase analysis) |
| `/agent-help` | List all commands |

### See also

- `agents/launch-pad.md` — Full agent prompt (7-phase readiness model incl. non-interactive Phase 7 `LAUNCH_PAD_RESULT` emission)
- `agents/plan-reviewer.md` — Plan Reviewer agent (validates briefs in Phase 5.5)
- `skills/supervisor-readiness/SKILL.md` — Pre-flight checklist, brief template, jobs convention
- `skills/product-discovery/SKILL.md` — Discovery framework
- `skills/claude-md-validation/SKILL.md` — CLAUDE.md freshness validation
- `commands/supervisor.md` — Supervisor command (consumes briefs)

## Launch Pad — diagrams and examples

### Launch Pad architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                    LAUNCH PAD (Readiness Agent)                    │
│  Goal → Discovery → Feasibility → Analysis → Decomposition →     │
│  Brief → Plan Review (mandatory gate) → Save                      │
└──────────┬──────────────────────────────────────────┬────────────┘
           │                          │               │
    ┌──────▼──────┐           ┌───────▼────────┐ ┌────▼──────────────────────┐
    │  CLAUDE.md  │           │ Plan Reviewer  │ │  .supervisor/             │
    │  + Codebase │           │ (Phase 5.5)    │ │  jobs/pending/{brief}.md  │
    │  (reads)    │           │ (subagent)     │ │  (PASS or user-overridden │
    └─────────────┘           └────────────────┘ │   NEEDS_HUMAN to save)    │
                                                 └───────────────────────────┘
```

### Seven-phase overview

```
┌─────────────────────────────────────────────────────────────────┐
│              LAUNCH PAD — SUPERVISOR READINESS                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Phase 1: VALIDATE (Environment Readiness)                      │
│     └─> Git, CLAUDE.md, worktrees, gh                           │
│                                                                 │
│  Phase 2: DISCOVER (Requirement Refinement)                     │
│     └─> Product discovery, acceptance criteria, MVP scoping     │
│                                                                 │
│  Phase 2.5: FEASIBILITY (Soft Gate)                             │
│     └─> Tech stack, deps, architecture, scope, blockers         │
│         → GO / CAUTION (risks) / NO-GO (stop + override option) │
│                                                                 │
│  Phase 3: ANALYZE (Codebase Impact Estimation)                  │
│     └─> Grep/glob codebase, file grouping, overlap detection    │
│                                                                 │
│  Phase 4: DECOMPOSE (Subtask Structure)                         │
│     └─> Decomposition Threshold (default 1; split for a reason) │
│                                                                 │
│  Phase 5: PACKAGE (Assemble Brief)                              │
│     └─> Supervisor-Ready Brief with all sections                │
│                                                                 │
│  Phase 5.5: PLAN REVIEW (Mandatory Gate)                        │
│     └─> Plan Reviewer validates brief (max 3 spawns/session)    │
│                                                                 │
│  Phase 6: REFINE & SAVE (Interactive)                           │
│     └─> Save (on PASS or user override) / Refine / Discard      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

Phase 7 (non-interactive) emits the `LAUNCH_PAD_RESULT` block after Phase 6; it has no interactive step, so it is not drawn in the box.

### Single-subtask example brief

```markdown
# Supervisor Job: Add JWT Authentication

## Environment
- **Project:** ~/my-project
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0

## Task
**Goal:** Add JWT-based authentication with refresh tokens to the NestJS API

## Acceptance Criteria
- [ ] Given valid credentials, when POST /auth/login, then return JWT + refresh token
- [ ] Given valid JWT, when accessing protected endpoint, then allow access
- [ ] Given expired JWT, when accessing protected endpoint, then return 401

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | JWT authentication (guard, strategy, refresh, controller) | 6 modify, 5 create | LAUNCHABLE |

## Parallelism Analysis
single-agent (no fan-out)

- Recommended workers: 1

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-02-08-jwt-auth.md
```

> This example shows the below-threshold default (one subtask). See `skills/supervisor-readiness/SKILL.md` §"Decomposition Threshold" for when a split is justified, and the complete worked example below for a `Split reason: genuine-parallelism` case.

### Complete worked example brief

A `Split reason: genuine-parallelism` brief (moved from `agents/launch-pad.md` §"Output Format"; the authoritative template is `skills/supervisor-readiness/SKILL.md` §"Supervisor-Ready Brief Template").

````markdown
# Supervisor Job: Add JWT Authentication

## Environment
- **Project:** ~/my-project
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main
- **GitHub CLI:** ✓ Authenticated
- **Base commit:** a3f9c21e7d4b8f0912e6c5d4a7b8091234f5e6d7
- **Blockers:** 0 | **Warnings:** 0

## Task
**Goal:** Add JWT-based authentication with refresh tokens to the NestJS API

**Problem Statement:**
The API currently has no authentication. All endpoints are publicly accessible.
Users need secure access with token rotation.

## Acceptance Criteria
- [ ] Given valid credentials, when POST /auth/login, then return JWT + refresh token
- [ ] Given valid JWT, when accessing protected endpoint, then allow access
- [ ] Given expired JWT, when accessing protected endpoint, then return 401
- [ ] Given valid refresh token, when POST /auth/refresh, then return new JWT
- [ ] Given invalid refresh token, when POST /auth/refresh, then return 403

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | JWT guard + strategy | 3 modify, 2 create | LAUNCHABLE |
| 2 | Refresh token service | 1 modify, 2 create | LAUNCHABLE |
| 3 | Auth controller + routes | 2 modify, 1 create | BLOCKED (by #1) |
| 4 | E2E tests | 0 modify, 2 create | BLOCKED (by #3) |

## Parallelism Analysis
- **Batch 1:** Subtask 1, Subtask 2 (parallel — no file overlap)
- **Batch 2:** Subtask 3 (depends on Subtask 1)
- **Batch 3:** Subtask 4 (depends on Subtask 3)
- **Recommended workers:** 2
- **Estimated batches:** 3

## Subtask Contracts

```yaml
subtask_1:
  provides:
    - {kind: file, path: src/auth/jwt.guard.ts}
    - {kind: symbol, path: src/auth/jwt.strategy.ts, name: JwtStrategy}
  requires: []
  lanes:
    - "src/auth/jwt.guard.ts"
    - "src/auth/jwt.strategy.ts"
  external_requires: []
subtask_2:
  provides:
    - {kind: file, path: src/auth/refresh.service.ts}
  requires: []
  lanes:
    - "src/auth/refresh.service.ts"
  external_requires: []
subtask_3:
  provides:
    - {kind: file, path: src/auth/auth.controller.ts}
  requires:
    - {from: "1", kind: symbol, path: src/auth/jwt.strategy.ts, name: JwtStrategy}
  lanes:
    - "src/auth/auth.controller.ts"
  external_requires: []
subtask_4:
  provides:
    - {kind: file, path: e2e/auth.spec.ts}
  requires:
    - {from: "3", kind: file, path: src/auth/auth.controller.ts}
  lanes:
    - "e2e/auth.spec.ts"
  external_requires: []
```

## Skill References
- `skills/error-handling/SKILL.md` (Subtask 1)
- `skills/unit-testing/SKILL.md` (Subtask 2)
- `skills/{domain}/SKILL.md` (Subtask 3)
- `skills/playwright-e2e/SKILL.md` (Subtask 4)

## Risk Assessment
| Risk | Impact | Mitigation |
|------|--------|------------|
| Token storage strategy unclear | HIGH | Clarify DB vs Redis in Subtask 2 |
| Refresh token rotation complexity | MEDIUM | Use established pattern from the relevant guard skill (stackpack@atelier plugin) |

## Configuration
- **Workers:** 2
- **Mode:** parallel
- **Estimated batches:** 3
- **Split reason:** genuine-parallelism (Subtask 1 and Subtask 2 have zero file overlap and each touches ≥3 files — see `skills/supervisor-readiness/SKILL.md` §"Decomposition Threshold"; a smaller goal would stay single-subtask)

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-02-08-jwt-auth-split.md
````

### Invocation examples

```
/launch-pad goal: "add user authentication with JWT"
/launch-pad feature: "customers need order history"
/launch-pad problem: "login is broken on mobile"
/launch-pad goal: "..." --discovery
/launch-pad goal: "..." --skip-validation
/launch-pad goal: "..." --project /path/to/project
```

### Agent responsibilities and integration

Launch Pad validates environment readiness (git, CLAUDE.md, worktrees, gh); refines requirements with the product-discovery and MVP-scoping skills; analyzes the codebase for file impact (grep/glob/read); decomposes per `skills/supervisor-readiness/SKILL.md` §"Decomposition Threshold" (default ONE subtask; split only for a named reason) with dependency analysis; computes parallelism (LAUNCHABLE vs BLOCKED from file overlap); assembles and saves the Supervisor-Ready Brief; and offers interactive refinement (save/refine/edit/discard).

It is used by the `/launch-pad` command, writes the brief to `.supervisor/jobs/pending/`, is consumed by Supervisor via `job:`, spawns one subagent (Plan Reviewer) for the Phase 5.5 gate, uses `.supervisor/` for state, and learns which files goals in a project commonly touch. The runner agent's skills are pre-loaded through its frontmatter (no file-read latency).

## Launch Pad — why the rules read as they do

Explanations removed from the runtime prompt. Each paragraph names the step it explains; the step's rule text is unchanged in `agents/launch-pad.md`.

### Inline execution banner

The `/launch-pad` banner's subagent-nesting limit comes from the Claude Code sub-agents documentation (https://code.claude.com/docs/en/sub-agents). A delegated runner both loses the ask tool and spends a nesting layer; `docs/ARCHITECTURE_CONTRACTS.md` §"Subagent nesting" holds the contract.

### Phase 1 source-doc provenance warning

The warning exists because a brief planned from an uncommitted source document may be built on a draft that is not yet the source of truth. It is scoped to the one source file on purpose: a generally-dirty tree already has its own WARNING, and this one is about the source doc's provenance, not the tree's cleanliness. With no specific source doc the run is unchanged. The prompt points at Phase 2 step 0 for the resolution criteria instead of restating them.

### Phase 1 shared local services bounding

The `unset, never empty` rule is gated on the outcome of bounding (zero non-empty lines to join), not on an enumeration of input shapes, so no future body shape can slip through as an empty string.

### Phase 2 requirement-file scoping

Auto-resolution is scoped to `.supervisor/requirements/` so a goal that merely names a repo file ("improve `README.md`") is never reinterpreted as a spec to plan from. It resolves the Product Owner to Launch Pad handoff when Beads is absent.

### Phase 3 advisory readers

Every Phase 3 reader used to restate the same caveat: advisory, subordinate to `CLAUDE.md`, fail-safe, never blocking. The caveat now sits once at the top of Phase 3. Details that were restated per reader:

- `read-project-memory.sh` emits only provenance-verified entries (unverified or poisoned lines are dropped), so its output is trustworthy advisory context.
- `read-lessons.sh` always exits 0 and emits only provenance-verified, non-stale entries; stale or unrelated categories are skipped.
- `read-postmortem.sh` reads the local `.supervisor/postmortem/results.jsonl` ledger and is quiet when the corpus is absent or empty or `jq` is missing. Matching is by exact path, so predicting `src/auth/guard.ts` when history recorded `src/auth/jwt.guard.ts` gives no hit — acceptable for an advisory signal.
- The memos-first orientation step is byte-equivalent to the old behaviour when neither orientation script exists.

### Phase 3 blast-radius prediction

`DEPENDED_ON_BY` (derived dependents) was the enrichment over an earlier depends-on-only read; together with incident history it turns the twin read into a full blast-radius graph. `twin-graph.sh` dedupes and sorts ids and is fail-safe (no store or no sha tool gives empty groups). `read-system-contract.sh` emits only chain-valid contracts and always exits 0. The no-contract, no-edge case is the common one and is always the case on a first run — incident history can only exist inside a verified contract, so "no contract" already covers "no incidents" — which is why the fallback omits the subsection instead of rendering an empty one. Script paths use the runtime plugin-root variable, never a `loomwright/...` repo path.

### Phase 3 validator-owned surfaces

The check is keyed on the generic trigger (acceptance satisfied by a scripted checker) rather than a filename, so any concrete script name in the prompt is illustrative only, and an ordinary goal sees no false positive.

### Phase 5 base-commit stamp

The stamp feeds Supervisor's Phase 1.5 brief-staleness churn signal (`skills/preflight-sync/SKILL.md`, signal (c)). A brief without it degrades that signal silently and fail-safe, so the stamp is not a blocking requirement on Launch Pad's output.

### Phase 5 Executable Acceptance

Supervisor also skips `cmd:` bullets on the unattended path, so a machine-authored one never runs unattended either way. The plugin doc surface is the doc-currency surface of `scripts/check-doc-currency.sh`, distinct from `agents/code-reviewer.md`'s review-trigger taxonomy.

### Phase 5 Outcomes Rubric producer seam

Step 7 is a deliberate, documented deviation from Launch Pad's usual "inline instruction, no source change" convention: it is the rubric producer seam for multi-iteration `/autonomous`, and it stays guarded so default behaviour is untouched.

### Phase 5 MATERIALIZE

Both artifacts (scratch brief and context digest) are derived from the brief text, so a revision that does not re-run MATERIALIZE leaves them describing a version that no longer exists: the reviewer re-reviews the pre-revision text, silently degrading the mandatory three-attempt gate to one effective review, and workers are pointer-handed the lanes of a plan Plan Review had just rejected. Re-running is cheap and safe; skipping it is neither.

The serialization is stated as happening in Phase 5 first because Phase 5 completes before Phase 5.5 begins — Phase 5 cannot reuse anything Phase 5.5 produces. The digest (File Impact Map, interfaces touched, conventions, sibling-subtask summary, cross-lane producer/consumer contracts; bounded, with an explicit truncation marker) reaches workers as a path + ≤200-char summary + "Read only the sections you need" on both the Task-spawn carrier (`skills/async-orchestration/SKILL.md` §"Context digest pointer") and the SDK-runner carrier.

### Phase 5.5 scratch-file reuse

Re-assembling the brief in Phase 5.5 would risk reviewing text that differs from what MATERIALIZE wrote and what Phase 6 saves. Reusing the scratch file, which the FAIL branch re-materializes, is what makes a retry a genuine second review rather than a re-read of the rejected text.

### Phase 6 notes

- Action 2a: after a non-interactive auto-strip the run can never be NEEDS_HUMAN for `executable_acceptance` again, since the flagged bullets no longer exist. Every post-PASS or post-NEEDS_HUMAN mutation consumes an attempt from the same shared cap.
- Action 2b: a story written through an answered Product Owner gate carries no `pending` line, so the 17c gate mostly fires for requirements that never went through that gate.
- Action 3 (non-interactive PASS): the explicit flag is `/autonomous`' documented CI contract for an unattended save, and the save is safe because the mandatory Plan Review — this phase's correctness gate — passed (same precedent as `no_rubric_in_non_interactive`).
- Action 7: `.supervisor/memory/` is a committed store, which is why its sole writer is confirm-gated. The earlier wording scoped the human gate to the first version of project memory; the rule itself (never auto-write) is unchanged.

### Phase 7 result block

Before `LAUNCH_PAD_RESULT`, `/autonomous` PLAN detected the saved brief with a fragile `ls`-diff of `.supervisor/jobs/pending/`. The block's core schema stays a tight four fields (see the CODE_REVIEW_RESULT v3 cautionary tale in `docs/RESULT_SCHEMAS.md`); `cmd_bullets_stripped_non_interactive` is the one additive exception, and it is omitted rather than emitted `false` so the common case's YAML is unchanged.

### Launch Pad token budget

Launch Pad is lightweight by design: no state file management, and a clean exit after save.

## /autonomous — why the rules read as they do

Explanations and history removed from `skills/autonomous-loop/SKILL.md`, `skills/autonomous-loop/multi-iteration.md` and `commands/autonomous.md`. Each paragraph names the step it explains; the step's rule text stays in the runtime file.

### Why multi-iteration is the default

The default flipped from single to multi-iteration in v14.0.0. The earlier "default single, opt-in multi" assumed multi-iteration was advanced behavior; in practice the rubric and Option-C signals are the common shape of real autonomous work, and stacked branches removed the merge-and-wait friction that made multi-iteration feel heavy. Callers scripting around the one-PR contract pass `--single-iteration` explicitly — which is what `/automate` does for every item. The INIT migration hint exists so existing scripts notice the default change. Before INIT-time detection, a gate that fired in an unattended terminal could only be escaped by killing the session (which corrupts state); a gate timeout was deferred as its own design surface.

### Step 0 re-reads and load by mode

Step 0 re-reads Launch Pad, Supervisor and this protocol on every run, so a change to any of them between releases reaches `/autonomous` automatically; the command body's "references, not duplicates" promise depends on it — otherwise the main thread would execute remembered shapes. The multi-iteration protocol (EVALUATE, stacked branches, the rubric gates, rubric auto-authoring and freeze) moved to its own file (automate-speed/13) because a `--single-iteration` run — every `/automate` item — never executes any of it, and reading it cost context on every item turn. Each moved section kept its heading in `SKILL.md` with a pointer, so existing `§"…"` citations still resolve.

### Brief-save detection

`LAUNCH_PAD_RESULT.saved_brief_path` became the primary brief-save signal in v14.2.0; before that the loop relied only on an `ls`-diff of `.supervisor/jobs/pending/`, which cannot tell two concurrent sessions apart. The diff is kept as a fallback for a run where the block is absent or malformed, with its single-session-only constraint and the `concurrent_session_detected` abort; for those runs the safe rule is still one autonomous / launch-pad invocation at a time per repo. The inline-path validator call exists because the result-block validator hook only fires when Launch Pad runs as its own agent session, never on the inline slash-command path `/autonomous` uses. A malformed block falls through to the fallback rather than aborting because the fallback is functionally equivalent for the common single-session case.

### Session id collisions

Two sessions started in the same second would produce identical `session_id`s. That is moot under the single-session assumption; a later hardening can append a short random suffix (`auto-{YYYY-MM-DD}-{HHMMSS}-{4hex}`) once concurrent sessions are supported. For the same reason the stale-session-id pre-snapshot check fires in practice only on the `rubric_dropped_from_brief` retry footgun and similar leftover-brief cases. The `session_id` already carries the date, so requirement paths sort without a redundant date prefix.

### state.json advisory note

`state.json` was introduced as advisory-only in v13.0.0 to seed future resume tooling (the "Doc 4" state.json sidecar plan). The `_v1_note` field is removable once a later plan defines a stable resume contract; its presence is what makes accidental dependence on advisory state impossible to do silently.

### ACQUIRE signals residual window

There is no positive terminal flip of `current_status` in `state.json`, so liveness rests on external cleanup: if an autonomous run dies without moving its brief out of `jobs/in-progress/` and without stamping `ended_at`, its `state.json` stays "active", and a later unrelated PR whose head branch exactly equals that crashed feature branch could be dispatched against through Source 2. This is accepted residual risk, not a blocker: the window needs an exact branch-name collision AND the stale brief still in `in-progress/` (which the plugin already treats as an active run), it is Source-2-only (a non-terminal `state.md` is the preferred Source 1), and the drain is fail-safe (it never merges and never force-pushes). The ACQUIRE write exists because the branch otherwise reaches `iterations[-1].branch` only at EVALUATE — post-PR, too late for the hook.

### Rubric preservation and auto-authoring

`has_rubric` replaced a substring `grep -qF` because the substring match fires on commented headers, inline mentions and empty placeholder headers, which would silently suppress auto-authoring on the common inline-string path — the same reason INIT writes a non-header placeholder. The freeze step writes an authored rubric back into the requirement body because every refined-requirement template copies the requirement body, not the brief; without it iteration 2+ would score against an absent rubric. A `rubric_dropped_from_brief` abort chooses to stop because a precondition for multi-iteration was violated, not because the system failed — it pairs with `status: aborted` in the `AUTONOMOUS_RUN` status↔reason table.

### Why the base branch is passed both ways

The stacked `--base-branch` CLI flag was added because a spike found EXECUTE step 1 did not actually pass it (`docs/SPIKES/W-NEW-3-stacked-branches-e2e.md`). If Launch Pad ignores the inline directive and saves a brief without `Base Branch:`, the CLI flag still wins; if the flag were ever stripped (a later refactor re-parsing argv), the brief field is the fallback. Plan Reviewer Criterion 13 checks the two agree.

### Forward-set history

The forward set grew one flag at a time: `--base-branch` and `--non-interactive` (v14), `--cheap` (v15.2.0), `--max-tokens` (red-team-hardening/06), and the separate Launch Pad `--non-interactive` forward. An earlier phrasing said the loop forwards "ONLY `--non-interactive`"; the loop always also forwarded `--base-branch` conditionally. `/supervisor` standalone still accepts `--non-interactive` explicitly — a separate invocation path. The `--cheap` profile suits multi-iteration runs because each iteration is a full Launch Pad plus a full Supervisor run.

### The detached drain and the chained review-heal

Supervisor's Phase 4.5 step 5.5 drain is part of the inline Supervisor workflow, so stopping the Supervisor enumeration at Rubric Grader would have hidden it. A `PostToolUse[Bash]` hook backstop also dispatches the same drain when the PR is created on the inline path; the dispatcher's per-PR idempotency marker guarantees exactly one dispatch. The loop's own EVALUATE review-heal exists to inform the stacking decision (does iteration N+1 stack on a PR the reviewer flagged?), which is why it runs only in multi-iteration mode and only diff-only. AC9 (the review-pr runner is never Task-spawned) is retained pending owner review now that nesting is allowed; the Task step's own code-reviewer and fix-worker spawns are already one nesting layer down. Review-heal never merges, so it cannot create a new PR that would retrigger the loop.

### Merge verification reads in-memory state

The merge-verification and PR-base pseudocode uses `jq` on `state.json` only because it is the most concise way to write the example. Real implementations keep `current_brief_path` and the `iterations[].branch` values in memory: reading `state.json` back mid-run is wasteful and adds a JSON-parser dependency, and the `state.json` writes are for persistence, not intra-session lookups. The local ref is preferred over `origin/<branch>` because the user pushed from it and a stale remote ref could hide the real tip.

### PR-base verification is the second line

Supervisor's own Phase 4 self-verify is the first line of defense for the PR base. EVALUATE's check covers the case where that self-verify was silenced (environment error, `gh` outage) but Phase 4.5 still completed and emitted a result; using the identical retry policy on both sites avoids divergence.

### Why Signal 2 anchors on the filename

`.supervisor/state.md` is per-Supervisor-session and Context-Keeper rewrites it atomically (`agents/context-keeper.md`, its atomic read-validate-mutate-write rule), so pre-rewrite stale content from a prior session could survive briefly and produce a false positive; a global grep might be naturally scoped, but the filename anchor is robust against state.md not yet being updated or concurrent inconsistency. Of the three iteration-scoped sources, `SUPERVISOR_RESULT.error` and `.summary` are where the gap reason is reliably present on Option C; the failed brief is a Launch Pad product that Supervisor moves to `failed/` without necessarily appending the reason, so its check is kept only in case a later Supervisor annotates the brief.

### Gate fail-closed choices

Under `--non-interactive-fallback` the rubric gate fails closed (`rubric_gate_closed_non_interactive`): silently picking `continue` would be unsafe in CI, and silently picking `stop` would silently degrade multi-iteration to single-iteration. The no-rubric gate instead exits `done` (`no_rubric_in_non_interactive`): without a rubric there is no quality signal to gate on, so continuing in CI would be busywork, while the rubric gate has a signal that is unsafe to drop. Before v14.0.0 a multi-iteration run with no rubric silently terminated as `done`; the gate made the decision explicit because refactor and cleanup goals often have no rubric yet still want more iterations.

### Pre-flight gate and stacked runs

The Phase 1.5 pre-flight gate (added to Supervisor in v14.8.0) checks *work overlap* before decomposition: whether the requested work intersects recent commits or open PRs on `$BASE_BRANCH` (same-file overlap, or an already-merged equivalent), between Supervisor Phase 1 and Phase 2. EVALUATE's PR-base check runs after FINALIZE and confirms iteration N+1's stacked PR was opened against `iterations[N].branch`. Because the pre-flight gate scopes its overlap scan to `$BASE_BRANCH`, it does not flag the stacked parent iteration's own commits or PR, so a stacked run does not trip the gate on its own chain. The loop terminates rather than re-iterating on `preflight_overlap_detected` because the overlap is a precondition the user resolves, not a quality signal the next iteration could improve on.

### Max-iterations cap

The hard cap of 10 exists because stacked-PR review burden becomes unmanageable beyond about ten PRs in a stack; review velocity, not loop logic, is the rate-limiting step.

## /autonomous failure modes without a recovery path

### Session terminated mid-loop

Process killed, terminal closed, machine restart: unsupported. The user cleans up `.supervisor/jobs/in-progress/`, closes abandoned PRs, and restarts with `/autonomous`. A resume contract is its own plan (it depends on the state.json sidecar work).

### inter_subtask_gap string drift

If `FAILURE_ESCALATION.md` changes the grep-stable `inter_subtask_gap` string, Signal 2 detection silently fails and the loop falls through to default termination with `status_reason=supervisor_failed_other`; the user inspects the failed brief and re-runs. Promotion to a typed enum is future work.

## /autonomous — usage notes

User-facing notes moved out of `commands/autonomous.md`.

### Iteration vs item

An **iteration** (`/autonomous`) is one `/launch-pad` → `/supervisor` pass on the SAME goal; `/automate`'s **item** is one independent goal from a queue. `/autonomous` deepens one goal across iterations; `/automate` walks many goals one item at a time.

### Not shipped

- **`--gate-timeout-minutes`** — deferred. CI hangs are prevented only by the INIT-time non-interactive detection; once a gate fires in an unattended terminal, the only escape is killing the session externally (which corrupts state). A wrapper-process timeout is the right shape and its own design surface. Unattended runs must pass `--non-interactive-fallback`.
- **`--status` / `--continue` / `--abort` / `--background` / `--auto-merge`** — deferred. The resume contract depends on the state.json sidecar work; auto-merge needs trusted-PR enforcement that is its own design surface.

### Example: single-iteration smoke test

```bash
$ /autonomous "add a /version command that prints plugin version" --single-iteration
```

The loop writes `.supervisor/requirements/auto-2026-05-11-143022-add-a-version-command.md`, runs Launch Pad inline (you confirm save at Phase 6), runs Supervisor inline (it produces PR #42), and emits:

```
# Autonomous Run Summary
- session_id: auto-2026-05-11-143022
- mode: single
- status: done
- total_iterations: 1
- iterations:
  - { n: 1, supervisor_status: completed, pr_url: "https://github.com/.../pull/42", rubric_score: null }
```

### Example: multi-iteration with rubric-driven re-planning

```bash
$ /autonomous --requirement .supervisor/requirements/jwt-auth-with-rubric.md --no-stacked-branches
```

The requirement file already contains an `## Outcomes Rubric` with 5 items. Iteration 1 runs Launch Pad → Supervisor → PR #42 with `rubric_score: "3/5"`. The rubric gate fires (`--no-stacked-branches`, so a merge comes first): merge-and-continue / stop-here / force-continue-anyway. You merge PR #42, then pick `merge-and-continue`; the loop verifies the merge with `gh pr view --json state` → `MERGED`, writes `...-iter2.md` referencing the rubric and the merged PR, and loops back to PLAN. Iteration 2 re-discovers (now seeing PR #42's merged code), scopes the brief around the remaining 2 rubric items, and Supervisor produces PR #43 with `rubric_score: "5/5"`. The loop terminates:

```
- mode: multi
- status: done
- total_iterations: 2
- iterations:
  - { n: 1, pr_url: ".../pull/42", rubric_score: "3/5" }
  - { n: 2, pr_url: ".../pull/43", rubric_score: "5/5" }
- policy_decisions: [user_picked_save, user_picked_merge_and_continue, user_picked_save]
```

In the default stacked mode the same run needs no merge: the gate offers continue-to-next-iteration and iteration 2 branches from iteration 1's branch.

### Example: multi-iteration with Option-C re-planning

```bash
$ /autonomous --requirement .supervisor/requirements/refactor-with-hidden-deps.md
```

Iteration 1: Launch Pad saves a brief; a Worker emits `outputs_gap`; Execute Manager raises adjudication; you pick **Option C "Exit to Launch Pad"**. Supervisor marks the job failed with `inter_subtask_gap`. EVALUATE detects it through the anchor-by-filename check (`.supervisor/jobs/failed/{basename(brief)}` exists + `inter_subtask_gap` in the failed brief, `SUPERVISOR_RESULT.error` or `SUPERVISOR_RESULT.summary`), writes `...-iter2.md` with the gap context and loops back to PLAN with no merge prompt (no PR was created). Iteration 2 completes cleanly.

### Risks and limitations

- **Multi-iteration merge cadence.** In `--no-stacked-branches` mode the rubric gate asks for a merge between iterations and verifies it via `gh pr view` or a local ancestry check; `force-continue-anyway` skips it, but iteration N+1's branch then lacks iteration N's changes and the PRs likely conflict. (Stacked mode, the default, needs no merge between iterations.)
- **Rubric per-item PASS/FAIL is not available** — only the score `"N/M"` is in `SUPERVISOR_RESULT`. The refined requirement passes the full rubric back to Launch Pad and relies on its re-discovery to identify gaps.
- **Crash recovery is unsupported.** Re-running after a crash may duplicate work (a similar brief, a similar PR, likely merge conflicts). Clean up `.supervisor/jobs/in-progress/`, close abandoned PRs, then restart; `/autonomous --continue` is deferred.
- **No QA integration in the loop.** The loop trusts Supervisor's Phase 4.5 self-heal and Rubric Grader for in-PR quality; auto-spawning QA after each PR is its own design surface.
- **Cost.** Each iteration runs a full Launch Pad and a full Supervisor (including Phase 4.5 and the Rubric Grader). `--max-iterations N` (default 3) and `--max-tokens N` are the caps.

### Troubleshooting: rubric_dropped_from_brief

Launch Pad did not honor the inline instruction to preserve the `## Outcomes Rubric`. The abort happens after Phase 6's save, so the saved brief is still in `.supervisor/jobs/pending/` (its filename starts with this run's `session_id`). Move it to `.supervisor/jobs/failed/` or delete it before re-running — otherwise the next run's `ls`-diff counts it as new and either picks it up or trips `concurrent_session_detected`: `mv .supervisor/jobs/pending/<this-session-id>-*.md .supervisor/jobs/failed/`. Fallback: convert the rubric to inline acceptance criteria and re-run single-iteration, or file a follow-up for a Launch Pad source change.

### Troubleshooting: concurrent_session_detected

The brief-save `ls`-diff found more than one new file in `pending/` after Phase 6 — likely another `/launch-pad` or `/autonomous` session on the same repo. Stop the other session, clean stray pending briefs, restart.

### Troubleshooting: iteration N+1 lacks PR N's changes

You picked `force-continue-anyway` on a `--no-stacked-branches` rubric gate without merging PR N, so iteration N+1 branched from `main` without PR N's code. Merge PR N now and pick `merge-and-continue` at the next rubric gate.

### Troubleshooting: Option-C re-plan did not fire

Either `.supervisor/jobs/failed/{basename(current_brief_path)}` does not exist (Supervisor did not move the brief, e.g. the run aborted before adjudication resolved — check `git status` and `ls .supervisor/jobs/in-progress/`), or the grep-stable `inter_subtask_gap` string changed in `FAILURE_ESCALATION.md` and the plugin is out of date. Inspect `.supervisor/state.md`, the failed brief and `SUPERVISOR_RESULT`, then re-run on a refined requirement.

### Troubleshooting: Supervisor returned checkpoint

The loop does not auto-resume from `checkpoint` (the state may be indeterminate). Run `/supervisor --continue task: <task_id>` to finish the in-flight task, then start a new `/autonomous` for the next requirement.

### /autonomous related commands

- `/launch-pad` — the inner workflow PLAN invokes; run it standalone for a Supervisor-ready brief without Supervisor.
- `/supervisor` — the inner workflow EXECUTE invokes; run it standalone to execute a brief without the outer loop.
- `/dreaming` — read-only reflection over completed sessions, including `.supervisor/autonomous/{session_id}/summary.md` history.
- `/agent-help` — every plugin command.
- `loomwright/docs/FAILURE_ESCALATION.md` (adjudication options; Option C is the failed-iteration trigger) and `loomwright/docs/RESULT_SCHEMAS.md` (`SUPERVISOR_RESULT`, `AUTONOMOUS_RUN`).
