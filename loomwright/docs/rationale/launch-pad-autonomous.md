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

`DEPENDED_ON_BY` (derived dependents) was the enrichment over an earlier depends-on-only read; together with incident history it turns the twin read into a full blast-radius graph. `twin-graph.sh` dedupes and sorts ids and is fail-safe (no store or no sha tool gives empty groups). `read-system-contract.sh` emits only chain-valid contracts and always exits 0. The no-contract, no-edge case is the common one and is always the case on a first run — incident history can only exist inside a verified contract, so "no contract" already covers "no incidents" — which is why the fallback omits the subsection instead of rendering an empty one. Script paths use `${CLAUDE_PLUGIN_ROOT}`, the runtime plugin-root variable, never a `loomwright/...` repo path.

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
