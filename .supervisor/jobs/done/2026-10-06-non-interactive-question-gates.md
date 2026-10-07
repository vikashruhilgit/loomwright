# Supervisor Job: Non-interactive question gates — Product Owner pre-persist gate + every gate reachable in a subagent/headless context

## Environment
- **Project:** ai-agent-manager-lanes-v2/s3-g (loomwright marketplace wrapper)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/agnostic-phase1/04-non-interactive-gates.md
- **Base commit:** a14db34935cf2abab56a17df5beff40baa4674f5

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Markdown prompt surfaces + one bash seam test; same stack as every prior gate change |
| 2 | Dependency Availability | GO | No new dependency; seam tests are grep-only bash (static, no gh/network) |
| 3 | Architecture Fit | GO | Extends the documented bimodal failure invariant (CLAUDE.md §"Failure-Mode Invariants") with the same named-status precedents |
| 4 | Scope vs Supervisor Capability | CAUTION | ~18 files across agents/commands/skills/docs — exceeds the context-bound threshold, split into 2 sequential subtasks |
| 5 | Hard Blockers | GO | Dependency `01-ratchet-hardening` is stamped done |

**Overall Verdict:** CAUTION

## Task
**Goal:** Give every `AskUserQuestion` gate in the plugin a defined, fail-CLOSED can't-ask behaviour (non-interactive run OR executing inside a subagent), add Product Owner's missing can't-ask branch (`po_gate: needs_owner`), wire `/automate` prompt intake to it, and record the full gate inventory in `docs/ARCHITECTURE_CONTRACTS.md`.

**Problem Statement:**
Unattended operators (CI, `/automate --non-interactive-fallback`, headless `claude -p` lanes) need every question gate to stop cleanly with a named status because a gate that cannot ask today either hangs or lets the model improvise.
Currently Product Owner's pre-persist soft gate (`agents/product-owner.md` §"Soft gate with user confirmation", mirrored in `commands/product-owner.md`) has no non-interactive branch, and `AskUserQuestion` is removed from every subagent's tool set by Claude Code (sub-agents doc, "tools removed from all subagents"), so any gate prose that runs inside a spawned agent has an unreachable interactive branch. This breaks the stated fail-CLOSED invariant.
Success looks like: an inventory table covering every `AskUserQuestion` site, no row whose can't-ask behaviour is "undefined", PO emitting `po_gate: needs_owner (<n> flags)` without persisting anything, and `/automate` prompt intake stopping (never wedging, never silently proceeding) on that result.

## Acceptance Criteria
- [ ] AC1 — Given `grep -rn AskUserQuestion loomwright/agents loomwright/commands loomwright/skills`, when the inventory table in `loomwright/docs/ARCHITECTURE_CONTRACTS.md` — a NEW `## Question-gate inventory` section placed immediately before `## Failure Escalation Summary`, with ONE pointer line added to the repo-root `CLAUDE.md` §"Failure-Mode Invariants" (that section lives in CLAUDE.md, not in ARCHITECTURE_CONTRACTS.md) — is compared against it, then every grep hit is accounted for either as its own inventory row or grouped under the gate it describes (a pure description/cross-reference hit, e.g. `commands/agent-help.md`, is listed under the gate it names, never silently dropped), and every gate row has with columns: gate · file/section · contexts it can run in (main thread interactive / main thread `--non-interactive` / subagent / headless `claude -p`) · current can't-ask behaviour · new can't-ask behaviour. The table states NO literal total count (house rule: count claims live in one authoritative place). The PR body carries the full inventory table AND the grep's total hit count (requirement scope 1: "in the PR body AND … `ARCHITECTURE_CONTRACTS.md`").
- [ ] AC2 — Given the inventory, when any row's "new can't-ask behaviour" cell is read, then none says "undefined"; each is a named fail-closed status, "main-thread-only by construction" (one line stating why), or "writes nothing without an Accept" (allowed for `/dreaming`, `/setup`, `/telemetry` only, per requirement scope 4).
- [ ] AC3 — Given Product Owner's Assumption Check raises ≥1 prerequisite flag or architecture conflict, when PO runs with `--non-interactive` OR is executing as a subagent (the ask tool is not in its tool set), then it creates no Beads tasks, persists no requirements file, and emits the flags + draft stories in its output with the machine-readable line `po_gate: needs_owner (<n> flags)`; when no flags exist behaviour is unchanged (proceed silently). `grep -n 'po_gate: needs_owner' loomwright/agents/product-owner.md loomwright/commands/product-owner.md` ≥ 1 each, and the two files carry the SAME branch text (agent↔command mirror, same commit).
- [ ] AC4 — Given `/product-owner`'s parameter table, when read, then it documents `--non-interactive` (no human to ask; flags ⇒ `po_gate: needs_owner`, nothing persisted).
- [ ] AC5 — Given `/automate "<prompt>" --non-interactive-fallback`, when the prompt-source intake runs `/product-owner`, then it passes `--non-interactive`, and a `po_gate: needs_owner` result is handled like "0 generated files ⇒ report + stop" with the `## Progress` note naming the gate and listing the flags — never a wedge, never a silent proceed. `grep -n 'needs_owner' loomwright/skills/automate-loop/SKILL.md` ≥ 1 inside §2 "Prompt source"; `commands/automate.md`'s prompt-source / `--non-interactive-fallback` rows reference it.
- [ ] AC6 — Given every other gate the inventory marks reachable in a subagent or headless context (Launch Pad, Supervisor, autonomous-loop, qa-executor and any other surface the inventory finds), when the run cannot ask, then the gate prose carries an explicit can't-ask branch failing closed with a NAMED status string following the existing precedents (`preflight_overlap_detected`, `non_interactive_without_fallback`, `rubric_gate_closed_non_interactive`, `resume_ambiguous_non_interactive`, `needs_human_non_interactive`); gates main-thread-only by construction get one line saying so. No gate's interactive options change.
- [ ] AC7 — Given the detection signal, when a changed gate decides it cannot ask, then it uses explicit flags (`--non-interactive`/`--non-interactive-fallback`) and spawn-contract knowledge ("I am a subagent" / the ask tool is absent from my tool set) — NOT only a stdin-TTY probe (the TTY probe false-positives inside the Claude Code Bash tool); any existing TTY probe stays as an additional signal.
- [ ] AC8 — Given `loomwright/scripts/test-non-interactive-gates-seam.sh`, when run, then it greps each changed gate for its can't-ask status string and passes; a mutation control (delete the PO can't-ask branch from a temp copy of `agents/product-owner.md`, gated on non-empty + differs-from-original) makes the PO seam assertion fail. The PR states whether a PO fixture-level test exists (else seam-only).
- [ ] AC9 — Given the full gate set, when `bash scripts/ci-local.sh` runs, then it is green — including `check-token-budget.sh` (every AGENT whose live spawn-time weight grows — its own `agents/<stem>.md` OR any `SKILL.md` it preloads via frontmatter `skills:` — gets its `.agents[<stem>]` entry in `prompt-token-budgets.json` and its `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" mirror row raised with a reason; commands and on-demand skills have NO budget entries and none may be added — the gate fails CLOSED on an orphaned key), `check-vendor-coupling.sh` (any raised `AskUserQuestion` allowance carries a new `allowance_reasons` entry), `check-doc-currency.sh`, and `test-citation-drift.sh`.
- [ ] AC10 — Given the release convention for a parallel-wave lane (`changelog.d/README.md` §"Who runs the bump", P7 parallel wave), when the PR is opened, then it carries `changelog.d/agnostic-phase1-04-non-interactive-gates.md` (`<!-- bump: minor -->`) and does NOT hand-edit `plugin.json`, `marketplace.json` or `CHANGELOG.md`.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Product Owner can't-ask branch + `/automate` prompt-intake wiring + seam test | AC3, AC4, AC5, AC7 (PO), AC8, AC9 (partial) | 7 modify, 1 create | `skills/quality-checklist/SKILL.md` | LAUNCHABLE |
| 2 | Gate inventory + can't-ask branches for every other subagent/headless-reachable gate | AC1, AC2, AC6, AC7, AC8 (extend), AC9, AC10 | ~13 modify, 1 create | `skills/quality-checklist/SKILL.md` | BLOCKED (by #1) |

## Subtask Contracts

```yaml
# Subtask 1 — PO can't-ask branch + /automate intake wiring + seam test (LAUNCHABLE)
provides:
  - {kind: "symbol", path: "loomwright/agents/product-owner.md", name: "po_gate: needs_owner"}
  - {kind: "symbol", path: "loomwright/commands/product-owner.md", name: "po_gate: needs_owner"}
  - {kind: "symbol", path: "loomwright/commands/product-owner.md", name: "--non-interactive"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/SKILL.md", name: "needs_owner"}
  - {kind: "symbol", path: "loomwright/commands/automate.md", name: "needs_owner"}
  - {kind: "file", path: "loomwright/scripts/test-non-interactive-gates-seam.sh"}
requires: []
lanes:
  - "loomwright/agents/product-owner.md"
  - "loomwright/commands/product-owner.md"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/commands/automate.md"
  - "loomwright/scripts/test-non-interactive-gates-seam.sh"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
external_requires:
  - "Claude Code sub-agents doc: AskUserQuestion is removed from every subagent's tool set even when listed in tools"

# Subtask 2 — Inventory table + remaining gates (BLOCKED by #1)
provides:
  - {kind: "symbol", path: "loomwright/docs/ARCHITECTURE_CONTRACTS.md", name: "Question-gate inventory"}
  - {kind: "file", path: "changelog.d/agnostic-phase1-04-non-interactive-gates.md"}
requires:
  - {from: "1", kind: "file", path: "loomwright/scripts/test-non-interactive-gates-seam.sh"}
  - {from: "1", kind: "symbol", path: "loomwright/agents/product-owner.md", name: "po_gate: needs_owner"}
lanes:
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "CLAUDE.md"
  - "loomwright/agents/launch-pad.md"
  - "loomwright/commands/launch-pad.md"
  - "loomwright/agents/supervisor.md"
  - "loomwright/commands/supervisor.md"
  - "loomwright/agents/qa-executor.md"
  - "loomwright/skills/autonomous-loop/SKILL.md"
  - "loomwright/commands/autonomous.md"
  - "loomwright/skills/**/SKILL.md"
  - "loomwright/commands/*.md"
  - "loomwright/scripts/test-non-interactive-gates-seam.sh"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "changelog.d/agnostic-phase1-04-non-interactive-gates.md"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | `test-non-interactive-gates-seam.sh`, `prompt-token-budgets.json`, `vendor-coupling-manifest.json`, `ARCHITECTURE_CONTRACTS.md`, and via Subtask 2's glob lanes `skills/automate-loop/SKILL.md`, `commands/automate.md`, `commands/product-owner.md` | YES |

> Sequential sharing grants visibility, not preservation: after its own edits Subtask 2 MUST re-check that Subtask 1's `po_gate: needs_owner` (both PO files) and `needs_owner` (automate-loop §2, `commands/automate.md`) strings still resolve — the seam test does this mechanically.

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after Subtask 1 — extends its seam test, inventories the PO row it created)
- **Recommended workers:** 1
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/quality-checklist/SKILL.md`, `skills/automate-loop/SKILL.md` (§2 prompt source — the file being edited) |
| 2 | `skills/quality-checklist/SKILL.md`, `skills/autonomous-loop/SKILL.md` (INIT step 0 non-interactive detection — the precedent) |

### Cited-line premise check

| ref | resolves | premise | deciding line | as of |
|-----|----------|---------|----------------|-------|
| `agents/product-owner.md:168-184` | yes | HOLDS | `**Soft gate with user confirmation (before \`bd create\`):**` | tip 3 hours ago, fetched <1h |
| `skills/automate-loop/SKILL.md:87` | yes | HOLDS (moved to 95) | `### Prompt source — \`/automate "X"\`` (and the "0 generated files ⇒ report + stop" bullet at 101) | tip 3 hours ago, fetched <1h |
| `commands/automate.md:49` | yes | HOLDS | `` \| `"<prompt>"` \| … **Prompt source.** Runs `/product-owner` `` | tip 3 hours ago, fetched <1h |
| `commands/automate.md:58` | yes | HOLDS | `` \| `--non-interactive-fallback` \| … governs the engine's own gates `` | tip 3 hours ago, fetched <1h |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Scope spans ~18 files (Feasibility (Phase 2.5) check 4) | MEDIUM | Split into 2 sequential subtasks (context-bound); subtask 2 starts from the seam test and PO row subtask 1 produced |
| `check-vendor-coupling.sh` counts literal `AskUserQuestion` occurrences per file against a ratcheted allowance — new prose naming the tool breaches it | HIGH | Prefer wording that does not add the literal token ("the ask tool", "cannot ask"); where a literal is genuinely needed, raise that path's allowance in `vendor-coupling-manifest.json` with a NEW `allowance_reasons` entry in the same commit (raise_check refuses an inherited reason) |
| Grown agent prompts breach `check-token-budget.sh` (fails CLOSED) | HIGH | Raise the affected `.agents[<stem>]` entries in `prompt-token-budgets.json` (an agent's own .md or a frontmatter-preloaded SKILL.md grew) to measured weight + ~10% headroom — never a command or on-demand-skill key — with the mirror row in `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets"; keep added prose terse |
| Agent↔command mirror drift (PO branch fixed in the agent but not the command, or Launch Pad agent vs command) | HIGH | Edit `agents/product-owner.md` and `commands/product-owner.md` (and `agents/launch-pad.md` / `commands/launch-pad.md`) in the SAME commit with identical branch text; seam test asserts the string in BOTH files |
| TTY probe false-positives inside the Claude Code Bash tool (stdin is not a TTY there) | MEDIUM | Detection uses explicit flags + "I am a subagent / the ask tool is absent"; any existing TTY probe is kept only as an additional signal, never newly introduced as the sole signal |
| Inventory misclassifies a gate's reachable contexts by agent NAME instead of actual spawn site | MEDIUM | Derive "can run in a subagent" from the real spawn sites (`grep -rn "subagent_type" loomwright/`, runner `claude --agent`/`claude -p` dispatch scripts) — e.g. `/qa-executor` Task-spawns `qa-executor`; runners are never Task-spawned (AC9 of review-pr) but run headless via `claude -p --agent` |
| Doc-currency / citation-drift: new `file:N` citations in committed prose | MEDIUM | Use descriptive anchors (CLAUDE.md citation convention); `test-citation-drift.sh` fails any new bare unpinned citation |
| Requirement text says "run `scripts/bump-version.sh`", but this lane is part of a parallel wave (backlog "S1 v2 lane s3-g"; main's recent `chore(release): … fold #398, #399, #400 fragments`) | LOW | Fragment only (`changelog.d/README.md` P7 parallel wave: lanes write fragments, the release lane bumps); state this in the PR body |
| House rule: a count claim lives in one authoritative place | LOW | The inventory's total site count goes in the PR body only, never as a literal in `ARCHITECTURE_CONTRACTS.md` |

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-06-non-interactive-question-gates.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-10-06T18:32:39Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/403
- **Branch:** feature/agnostic-phase1-04-non-interactive-gates
- **Files changed:** 19
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** PO can't-ask branch (po_gate: needs_owner) + /automate NI intake stop; named fail-closed can't-ask statuses for every subagent/headless-reachable gate; Question-gate inventory in ARCHITECTURE_CONTRACTS.md + CLAUDE.md pointer; seam test (57 checks, PO mutation control); fragment-only changelog. Heal: 3 iterations each fixing one HIGH (resume auto-continue → resume_requires_flag_non_interactive; missing /autonomous→Launch Pad --non-interactive forward; unapproved auto-authored rubric under the forward) — final fix 10b82be unreviewed; 15 lower-severity findings dismissed. Ground truth 2/2.

## Not verified
- **Product Owner can't-ask branch at runtime (--non-interactive or subagent)** — prompt behaviour; no PO fixture harness, seam-only (subtask 1)
- **/automate "<prompt>" --non-interactive-fallback end-to-end stop on po_gate: needs_owner** — needs a live /automate run (subtask 1)
- **Agent prompt behaviour in a real non-interactive or subagent run (LP, Supervisor, autonomous, automate, qa-executor branches)** — seam test pins wiring only (subtask 2)
