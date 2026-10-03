# Supervisor Job: Worker shared-context digest + explicit file lanes (D6)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — last content change 2026-07-31)
- **Git:** clean (0 files), branch: main @ 071bd9e
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/final-state/08-worker-context-digest-lanes.md
- **Base commit:** 071bd9e

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure plugin-surface work (markdown prompts + `scripts/*.py|sh` + the TypeScript `sdk-spike/`). All four languages already in-repo. |
| 2 | Dependency Availability | GO | No new deps. `sdk-spike/dist/` is built (`runner.js`, `schemas.js` present) and PR #111 (dependency materialization + real-brief parsing) is MERGED, so the SDK carrier is a real target, not a stub. |
| 3 | Architecture Fit | GO | Extends three existing contracts rather than inventing surfaces: the brief's `provides`/`requires` block (`supervisor-readiness` §"Provides / Requires Schema"), the pointer-not-payload transport rule (`docs/POINTER_AUDIT.md`), and the deterministic `outputs_verified` gate (`agents/worker.md` + `scripts/validate-worker-result.py`). |
| 4 | Scope vs Supervisor Capability | CAUTION | Exceeds the `context-bound` bound (>12 files AND >800 changed lines). Split into 4 sequential subtasks with a recorded `Split reason`. |
| 5 | Hard Blockers | CAUTION | **Acceptance criterion 3 of the source requirement ("Re-run measurement: worker re-read volume (or cost proxy) down vs the arm-2 baseline") is NOT satisfiable in this PR.** That measurement is a ~$60 multi-session operator-run eval on an external repo (`ntfs-tool`), the same class `00-overview.md` §"/automate handling" declares `/automate` cannot drive (items 05/06 were skipped at intake for exactly this reason). Owner decision at the Phase 2.5 gate: **build scope 1+2+3, defer the measurement**, leaving the criterion owed rather than silently dropped. |

**Overall Verdict:** CAUTION (proceeding — 2 CAUTION findings carried into Risk Assessment)

## Task
**Goal:** Hand Launch Pad's already-computed file-impact analysis to every spawned worker as a bounded per-job context digest, and give each subtask an explicit file lane the worker is told to stay inside and the deterministic gate mechanically checks.

**Problem Statement:**
Spawned workers need shared context and ownership boundaries because each one cold-starts with an empty context and re-reads the same files — that re-acquisition, not prompt overhead, is where the measured 6.4× goes.
Currently, Launch Pad computes a File Impact Map at Phase 3 (`agents/launch-pad.md` §"File Impact Map") and throws it away after assembling the brief, and no subtask declares which files it owns. This causes two distinct costs: every worker re-derives the same codebase understanding from scratch, and siblings can silently impact each other's work (the divergent-interface incident: ST-1/ST-2 shipped conflicting flag shapes for the same concept because neither could see the other's worktree).
Success looks like a bounded digest artifact produced once per job and pointer-handed to every worker on both spawn paths, plus per-subtask lane declarations whose violations are reported by the existing `outputs_verified` gate.

## Acceptance Criteria
- [ ] Given a Launch Pad run that produces a brief, when Phase 5 PACKAGE completes, then a bounded per-job context digest artifact exists at the documented path containing the File Impact Map, interfaces touched, conventions, the sibling-subtask summary, and the cross-lane producer/consumer contracts.
- [ ] Given the digest exceeds its documented hard bound, when it is written, then it is truncated to the bound with an explicit truncation marker (the digest is never unbounded).
- [ ] Given a worker is spawned on the **Task-spawn path**, when its prompt is composed, then it receives the digest as a **pointer** (path + ≤200-char summary + "Read only the sections you need") and never as a pasted body.
- [ ] Given a worker is spawned into a **linked git worktree**, when the digest pointer is composed, then the pointer is the **main-checkout absolute path** and the prompt says so — because gitignored `.supervisor/` artifacts do not exist inside worktrees.
- [ ] Given a worker is spawned on the **SDK-runner path**, when the runner composes that spawn's prompt, then it carries the same digest pointer and lane text as the Task-spawn path.
- [ ] Given a brief with more than one subtask, when it is assembled, then each subtask declares a `lanes:` list of owned path globs alongside its existing `provides`/`requires` contract.
- [ ] Given a worker modifies a file matching no glob in its own declared lane, when it emits `WORKER_RESULT`, then that path appears in a new `out_of_lane` field.
- [ ] Given an out-of-lane path falls inside the declared lane of a subtask **not reachable from this one in either direction in the `requires` DAG** (transitive closure — equivalently, the scheduler would place them in the same wave), when the result is consumed, then it is surfaced as a lane collision through the **existing** escalation surface (this is the divergent-interface failure mode). Given either subtask **is** reachable from the other, then they are sequentially ordered, a shared file is legal, and it is **not** flagged.
- [ ] Given a subtask edits a file that carries an **upstream** subtask's `provides` symbol, when it completes, then that symbol still resolves — sequential lane sharing grants visibility, not preservation, and no existing gate checks it.
- [ ] Given a `WORKER_RESULT` carrying `out_of_lane`, when the SubagentStop validator runs, then the field is validated as an **optional additive field at `schema_version: 2`** — **no schema-version bump** (following the `memory_candidates` precedent at `loomwright/docs/RESULT_SCHEMAS.md:29`: "an optional, backwards-compatible field needs no bump") — and blocks omitting it are still accepted.
- [ ] Given `out_of_lane` is validated-but-**OPTIONAL**, when `scripts/check-contract-parity.sh` runs, then its WORKER_RESULT MANIFEST row (`scripts/check-contract-parity.sh:340`) includes `out_of_lane`, satisfied by the field name appearing in **executable (non-comment, non-string) position** in `loomwright/scripts/validate-worker-result.py` plus the agent prompt. **This deliberately diverges from the unpinned `memory_candidates` precedent**, and the reason must be stated in the brief and the code: `memory_candidates` is never validated, whereas `out_of_lane` *is* — so leaving it unpinned would let the validator drop it while the parity gate stayed green, which is the silent-under-enforcement failure that gate exists to prevent. Pinning an optional-but-validated field is correct; making it *required* would violate the preceding criterion.
- [ ] Given a brief is parsed by the SDK runner, when its contract block heading is either `### Subtask contracts` or `### Provides / Requires Contracts`, then the dependency graph is parsed from it; and given a brief has a Subtask Structure table but zero parsed contracts, then the runner **fails closed with an explicit error** rather than silently emitting an all-LAUNCHABLE wave.
- [ ] Given the brief declares `lanes:`, when Plan Reviewer runs, then a new **Criterion 16** validates the lane declarations (every subtask with a contract block declares `lanes:`; every lane path resolves or has an existing parent; any same-wave lane overlap is reported).
- [ ] Given the digest and lane seams ship, when `loomwright/scripts/test-context-digest.sh` runs, then it asserts the digest bound + truncation marker, the worktree-absolute pointer form, and that a same-wave lane overlap is flagged while a sequentially-ordered shared file is not.
- [ ] Given the change touches the plugin doc surface, when CI runs, then **every gate in `.github/workflows/ci.yml` passes** (currently seven: `validate-version.sh`, `check-command-sync.sh`, `check-doc-currency.sh`, `check-skills-index-sync.sh`, `check-contract-parity.sh`, `check-token-budget.sh`, `check-shared-prefix.sh` — assert against the workflow file, not against this enumeration, which will drift).
- [ ] **DEFERRED BY OWNER DECISION — not satisfied by this PR:** Given the digest ships, when a re-run measurement is taken, then worker re-read volume (or cost proxy) is down vs the arm-2 baseline. This is a ~$60 operator-run eval on an external repo; it remains owed against the source requirement.

## Outcomes Rubric
- Digest shipped on both spawn paths
- Lanes declared + mechanically checked
- Cross-lane contracts stated in digest
- Before/after cost or re-read measurement recorded

> **Rubric note (carried into Phase 4.5 grading):** bullet 4 is an **expected FAIL by owner decision** — the measurement is the deferred operator-run eval named in Feasibility check 5 and the last acceptance criterion. Expected score is therefore **3/4**, and that FAIL is a recorded decision, not a defect. The rubric is copied **verbatim** from the source requirement per the preserve-rubric contract; it was deliberately NOT reworded to make it self-satisfying — laundering an owed obligation into a satisfied one is exactly what that contract exists to prevent.
>
> **The expected 3/4 MUST NOT be treated as a re-iteration trigger.** `rubric_score N<M` is a documented `/autonomous` Signal-1 re-iteration condition. This brief is executed under **`/autonomous --single-iteration`**, which short-circuits EVALUATE before the rubric gate can fire (`skills/autonomous-loop/SKILL.md` §"AC-2 single-iteration short-circuit"), so the signal is unreachable on this path. If this brief is ever re-run in multi-iteration mode, the operator must decline the re-iteration prompt — another iteration cannot satisfy bullet 4, because the blocker is an external operator-run eval, not missing implementation.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Digest artifact contract + Launch Pad producer + brief-template lanes | AC1, AC2, AC6 | 4 modify, 1 create | `supervisor-readiness`, `state-management` | LAUNCHABLE |
| 2 | Task-spawn carrier + worker consumption + lane gate | AC3, AC4, AC7, AC8, AC9, AC10, AC11 | 7 modify | `async-orchestration`, `quality-checklist` | BLOCKED (by #1) |
| 3 | SDK-runner parity + brief-parser hardening | AC5, AC12 | 2 modify, 1 create | `async-orchestration` | BLOCKED (by #1) |
| 4 | Plan Reviewer criterion + seam tests + doc/version lockstep | AC13, AC14, AC15 | 14 modify, 1 create | `quality-checklist`, `claude-md-validation` | BLOCKED (by #2, #3) |

> **AC coverage:** AC1–AC15 are each owned by exactly one subtask — no orphan, no double-ownership. **AC16 is the deliberate deferral** (the operator-run measurement) and is owned by no subtask by design.

### Subtask contracts

> **Heading is load-bearing — do not rename.** The SDK runner enters its contract parser ONLY on `/^###\s+Subtask contracts\b/` (`loomwright/sdk-spike/src/runner.ts:359`). Under the alternative in-repo spelling `### Provides / Requires Contracts` (used by 6 of 13 archived briefs, so the trap is live) the entire YAML block below is skipped, every subtask parses with empty `provides`/`requires`, and the wave scheduler at `runner.ts:1004` marks **all four subtasks LAUNCHABLE in wave 1** — inverting this brief's sequential plan and running subtasks 1 and 2 concurrently on the shared `RESULT_SCHEMAS.md`. That silent-empty-graph failure already happened once (documented at `runner.ts:374-377`). Subtask 3 fixes the root cause (accept both headings + fail closed on a zero-contract parse); this heading is the belt-and-braces half.

> **Lane collision semantics (the rule subtask 1 must write into the schema).** A `lanes:` entry declares the paths a subtask owns. A write outside a subtask's own lane is recorded in `out_of_lane` and is **report-only**.
>
> **The concurrency test — ONE authoritative definition, stated as reachability, not as edges.** Two subtasks A and B may collide **iff neither is reachable from the other in the `requires` DAG (transitive closure)** — equivalently, iff the wave scheduler would assign them the same wave. **Do NOT phrase this as "no `requires` edge"**: that reads as *direct* edge and would falsely flag every transitively-ordered pair. This brief is its own counterexample — subtask 1 and subtask 4 share no direct edge yet are two waves apart via 1→2→4, and subtask 1 can touch `loomwright/skills/SKILLS_INDEX.md`, which subtask 4 owns. Under the reachability test that pair is correctly NOT a collision.
>
> **Sequentially-ordered subtasks legitimately share files** and must NOT be flagged (subtask 1 creates the `CONTEXT_DIGEST` section in `RESULT_SCHEMAS.md`; subtask 2 then adds `out_of_lane` to `WORKER_RESULT` in the same file, ordered by a `requires` edge).
>
> **The edge set is an assertion, not trusted input.** A spurious `requires` edge silences the check for that pair, so the rule is defeatable by construction. Plan Reviewer validates the declared dependency edges (Criterion 5) — the lane check consumes that validated graph and must never be treated as a guarantee independent of it.
>
> **Sequential sharing guarantees visibility, NOT preservation** — see the dedicated Risk Assessment row. A downstream subtask editing a file that carries an upstream subtask's `provides` symbol must re-verify that symbol still resolves after its own edit; nothing in the existing gate does this for it.

```yaml
# Subtask 1 — digest contract + producer + brief-template lanes (LAUNCHABLE)
provides:
  - {kind: "file", path: "loomwright/scripts/build-context-digest.sh"}
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "CONTEXT_DIGEST"}
  - {kind: "symbol", path: "loomwright/skills/supervisor-readiness/SKILL.md", name: "Lane Declaration Schema"}
  - {kind: "symbol", path: "loomwright/agents/launch-pad.md", name: "Context digest emission"}
  - {kind: "symbol", path: "loomwright/docs/POINTER_AUDIT.md", name: "### Context digest"}
requires: []
lanes:
  - "loomwright/scripts/build-context-digest.sh"
  - "loomwright/skills/supervisor-readiness/SKILL.md"
  - "loomwright/agents/launch-pad.md"
  - "loomwright/docs/POINTER_AUDIT.md"
  - "loomwright/docs/RESULT_SCHEMAS.md"
external_requires: []

# Subtask 2 — Task-spawn carrier + worker consumption + lane gate (BLOCKED by #1)
provides:
  - {kind: "symbol", path: "loomwright/skills/async-orchestration/SKILL.md", name: "Context digest pointer"}
  - {kind: "symbol", path: "loomwright/agents/worker.md", name: "out_of_lane"}
  - {kind: "symbol", path: "loomwright/scripts/validate-worker-result.py", name: "out_of_lane"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "CONTEXT_DIGEST"}
  - {from: "1", kind: "symbol", path: "loomwright/skills/supervisor-readiness/SKILL.md", name: "Lane Declaration Schema"}
lanes:
  - "loomwright/skills/async-orchestration/SKILL.md"
  - "loomwright/agents/worker.md"
  - "loomwright/agents/supervisor.md"
  - "loomwright/agents/execute-manager.md"
  - "loomwright/scripts/validate-worker-result.py"
  - "loomwright/docs/RESULT_SCHEMAS.md"      # sequentially shared with #1 (ordered by the requires edge below) — legal per the lane-collision rule above
  - "scripts/check-contract-parity.sh"       # WRAPPER-ROOT script; co-owner of the out_of_lane MANIFEST pin
external_requires: []

# Subtask 3 — SDK-runner parity + brief-parser hardening (BLOCKED by #1)
provides:
  - {kind: "symbol", path: "loomwright/sdk-spike/src/runner.ts", name: "contextDigestPointer"}
  - {kind: "symbol", path: "loomwright/sdk-spike/src/runner.ts", name: "laneGlobs"}
  - {kind: "file", path: "loomwright/sdk-spike/test/digest-lanes.test.sh"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "CONTEXT_DIGEST"}
lanes:
  - "loomwright/sdk-spike/src/runner.ts"
  - "loomwright/sdk-spike/src/schemas.ts"
  - "loomwright/sdk-spike/test/digest-lanes.test.sh"
external_requires: []

# Subtask 4 — Plan Reviewer criterion + seam tests + doc/version lockstep (BLOCKED by #2, #3)
provides:
  - {kind: "symbol", path: "loomwright/agents/plan-reviewer.md", name: "Criterion 16"}
  - {kind: "file", path: "loomwright/scripts/test-context-digest.sh"}
  - {kind: "symbol", path: "CHANGELOG.md", name: "15.20.0"}
requires:
  - {from: "2", kind: "symbol", path: "loomwright/agents/worker.md", name: "out_of_lane"}
  - {from: "3", kind: "symbol", path: "loomwright/sdk-spike/src/runner.ts", name: "contextDigestPointer"}
lanes:
  # Doc-currency surfaces: DERIVE this set from scripts/check-doc-currency.sh's FILES list
  # (currently :39-54) + its count sources — do NOT hand-maintain a parallel copy.
  # skills/supervisor-readiness/SKILL.md:210 states that rule explicitly.
  - "loomwright/agents/plan-reviewer.md"
  - "loomwright/scripts/test-context-digest.sh"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - ".claude-plugin/README.md"                 # carries "Plugin manifest (v15.19.0)" at :430 — scanned, WILL drift on the bump
  - "loomwright/commands/agent-help.md"        # carries "Plugin metadata (v15.19.0)" at :1082 — scanned, WILL drift on the bump
  - "CHANGELOG.md"
  - "CLAUDE.md"
  - "README.md"                                # wrapper root; loomwright/README.md DOES NOT EXIST
  - "AGENT_GUIDELINES.md"                      # in FILES (:42); no 15.19.0 claim today, listed so the lane matches the derived set
  - "loomwright/docs/ARCHITECTURE.md"          # in FILES (:47); same rationale
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/skills/SKILLS_INDEX.md"        # sequentially shared with #1/#2 if either bumps a SKILL.md version: frontmatter — check-skills-index-sync.sh enforces index<->frontmatter parity, so the bump and the index row must land together
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
1 ──┬──> 2 ──┐
    └──> 3 ──┴──> 4
```

### File Overlap Matrix

| | 1 | 2 | 3 | 4 |
|---|---|---|---|---|
| **1** | — | `loomwright/docs/RESULT_SCHEMAS.md` | none | `loomwright/skills/SKILLS_INDEX.md` (conditional) |
| **2** | `loomwright/docs/RESULT_SCHEMAS.md` | — | none | `loomwright/skills/SKILLS_INDEX.md` (conditional) |
| **3** | none | none | — | none |
| **4** | `loomwright/skills/SKILLS_INDEX.md` (conditional) | `loomwright/skills/SKILLS_INDEX.md` (conditional) | none | — |

Every overlap in this matrix is between subtasks that are **ordered in the `requires` DAG — one is reachable from the other** (in exactly one direction; *mutual* reachability is impossible in a DAG, it would be a cycle) — i.e. sequentially ordered, never same-wave — so none is a flaggable collision under the rule above. Note 1↔4 is a **transitive** ordering (1→2→4, no direct edge), which is exactly the pair the "no `requires` edge" phrasing would have mis-flagged and the reachability test handles correctly.

Specifically: #1 creates the `CONTEXT_DIGEST` section in `RESULT_SCHEMAS.md`, then #2 adds `out_of_lane` to `WORKER_RESULT` in the same file; and if **#1 or #2** bumps a `SKILL.md` `version:` frontmatter (#1 owns `supervisor-readiness`, #2 owns `async-orchestration`), the matching `SKILLS_INDEX.md` row — owned by #4 — must move in lockstep or `check-skills-index-sync.sh` fails closed.

Subtasks 2 and 3 have zero overlap with each other and both depend only on #1, so they satisfy the letter of `genuine-parallelism` — but the whole job is one `context-bound` chain, and splitting it across workers would re-pay the cold start this very PR exists to eliminate. **Run sequentially, one worker.**

### Batch Plan
Single sequential batch: 1 → 2 → 3 → 4. Estimated batches: 4.

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/supervisor-readiness/SKILL.md`, `skills/state-management/SKILL.md` |
| 2 | `skills/async-orchestration/SKILL.md`, `skills/quality-checklist/SKILL.md` |
| 3 | `skills/async-orchestration/SKILL.md` |
| 4 | `skills/quality-checklist/SKILL.md`, `skills/claude-md-validation/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Overloading `outputs_gap` with lane violations would break a hard invariant.** `loomwright/agents/worker.md:211-212` pins `status: completed` ⇔ `outputs_gap == ""` and `partial` ⇔ `outputs_gap != ""`. Reusing that field for out-of-lane writes would flip legitimate completions to `partial`. | HIGH | Add a **separate** `out_of_lane` field. Never write lane data into `outputs_gap`. Subtask 2 must preserve the invariant block byte-for-byte — **including the carve-out at `worker.md:214`** (a worker that could not read its pinned brief returns `partial` with `outputs_gap: ""`, and "Consumers must not infer `outputs_gap != \"\"` from `partial` alone"). The biconditional is not unqualified; the carve-out is part of what must survive. |
| **`check-contract-parity.sh` pins worker.md's allowed `status:` literals** to `[completed,failed,partial,present,missing,pending,enum]` (`scripts/check-contract-parity.sh:391`). Any new lane-related `status: <token>` example added to `worker.md` will **hard-fail** that gate. | MEDIUM | Do not introduce a new `status:` literal for lanes. `out_of_lane` is a path list, not a status. Subtask 2 owns this script and must run the gate locally. |
| **Sequential lane sharing guarantees visibility, NOT preservation.** The concurrent-only collision rule correctly stops flagging sequentially-ordered shared files — but that removes the only automated signal for a *different* failure: a downstream subtask silently clobbering an upstream one's edits. Nothing existing covers it — `loomwright/scripts/validate-worker-result.py` checks a producer's own `provides` at producer time (`:99`, `:146`), never that a later consumer preserved them. This brief is itself exposed: #2 edits `RESULT_SCHEMAS.md` after #1 creates the `CONTEXT_DIGEST` section there. | MEDIUM | Dedicated acceptance criterion: a subtask editing a file carrying an upstream subtask's `provides` symbol must re-verify that symbol still resolves after its own edit. Subtask 2's instructions for `RESULT_SCHEMAS.md` must say so explicitly. Subtask 1 records the visibility-vs-preservation distinction in the Lane Declaration Schema so the gap is documented, not implied. |
| **SDK brief parser is fragile by construction beyond the heading.** `lanes:` is silently ignored today only because lane entries are quoted strings and the item regex (`runner.ts:402`) requires brace form; `lanes:` never resets `listKey` (`runner.ts:393-398`), so brace-form lane items authored after a non-empty `requires:` would be appended straight into `requires`. | MEDIUM | Subtask 3 adds `lanes` to the recognized list-header set so it resets `listKey` explicitly, rather than relying on the accident that lane entries do not match the item regex. |
| **Making out-of-lane a hard failure would break legitimate cross-cutting edits.** The source requirement says violations are *"flagged"*, not *"failed"*. | HIGH | Report-only by default. The only condition that escalates is an out-of-lane path landing inside a **sibling's** declared lane — the actual divergent-interface hazard — and it escalates through the **existing** adjudication surface, inventing no new gate. |
| **Digest pointer handed to a worktree-resident worker resolves to nothing.** Gitignored `.supervisor/` artifacts do not exist inside linked worktrees (`docs/POINTER_AUDIT.md` §"Worktree reality"). | HIGH | Pin the main-checkout **absolute** path for parallel-path workers and say so in the prompt text, exactly as the existing brief pointer does. Add a test asserting the worktree form. |
| **Unbounded digest re-imports the payload cost the pointer rule exists to avoid.** A digest that grows with the repo would silently reintroduce paste-sized prompts. | MEDIUM | Documented hard bound + explicit truncation marker (AC2), and the digest travels as a pointer, never inline. Record the exception reasoning in `docs/POINTER_AUDIT.md`. |
| **Doc-currency / version lockstep is CI-enforced and easy to half-do.** The 15.19.0 → 15.20.0 bump drifts version claims in surfaces that are easy to miss — two were missed in this brief's own first draft (`.claude-plugin/README.md:430`, `loomwright/commands/agent-help.md:1082`). `check-token-budget.sh` fails CLOSED on an agent with no declared budget. | HIGH | Subtask 4 owns the whole lockstep as one unit and runs **every** gate in `.github/workflows/ci.yml` locally. Derive the surface set from `scripts/check-doc-currency.sh`'s FILES list + count sources — never from a hand-maintained copy (`skills/supervisor-readiness/SKILL.md:210`). Then grep the OLD value (`15.19.0`) repo-wide: a green doc-currency run is necessary but **not** sufficient, because the gate deliberately scans only high-confidence current-claim phrasings. **Do NOT "fix" illustrative/frozen example versions** in `RESULT_SCHEMAS.md` / `agents/supervisor.md` sample blocks — those are deliberately version-agnostic (CLAUDE.md codified this in v14.25.1 after a review round chased them). |
| **Stale premise in the requirement + FINAL_STATE_GOAL D6.** Both call the SDK runner *"the natural carrier"*, written before the arm-3 CUT row; decision **D1** then superseded the CUT ("chosen substrate, not an experiment; both blockers already fixed (PR #111, merged)"). A reader hitting the CUT row first could wrongly conclude this work is blocked. | MEDIUM | Owner decision at the Phase 2.5 gate: **Task-spawn is the primary, always-on carrier; the SDK runner gets parity.** Subtask 4 adds a one-line pointer from the CUT row to D1 so the superseding decision is discoverable from the row that looks like a blocker. Do NOT rewrite the eval row itself — eval honesty (D11) forbids editing a recorded run. |
| **Deferred measurement (Feasibility 5).** Rubric bullet 4 and the last acceptance criterion cannot be satisfied here. | MEDIUM (accepted) | Recorded as an expected FAIL-by-decision in the rubric note and left owed on the source requirement. Do **not** reword the rubric to make it pass, and do **not** stamp the source requirement `## Status: done` — it retains an owed criterion. |
| **Feature inert on the default path if built SDK-first.** `--sdk-runner` is opt-in / default-OFF. | LOW | Owner decision: Task-spawn path is primary and always-on; SDK parity follows it. |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 4
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-07-31-worker-context-digest-lanes.md
```
