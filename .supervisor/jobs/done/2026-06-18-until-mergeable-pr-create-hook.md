# Supervisor Job: Hook-backstop the until-mergeable review drain (PostToolUse on PR creation)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: feature/phase2b-knowledge-sources-insights (brief planned against `main`)
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (sequencing vs open PR #66 — see Risk Assessment)

## Feasibility (Launch Pad Phase 2.5)

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Bash + jq hook wrapper + hooks.json registration — the exact stack of the existing `dispatch-*` scripts |
| 2 | Dependency Availability | GO | `dispatch-pr-review.sh` already exists and is self-contained: reads `--pr-url`, reads opt-out config, per-PR idempotency marker, always `exit 0`. The wrapper just feeds it a URL |
| 3 | Architecture Fit | GO | Additive `PostToolUse` hook + fail-safe wrapper; mirrors the existing fail-safe dispatcher pattern; preserves "side-effect emitters fail SAFE / exit 0" invariant |
| 4 | Scope vs Supervisor Capability | GO | 3 small subtasks (script+test / registration / docs), sequential chain, 30–45 min each |
| 5 | Hard Blockers | GO | None |

**Overall Verdict:** GO

## Task
**Goal:** Add a `PostToolUse[Bash]` hook that fires the until-mergeable review drain on PR creation, so it runs reliably regardless of whether the orchestrating agent executes Supervisor's Phase 4.5 prompt **step 5.5** — closing the inline-execution gap where `/autonomous`/`/supervisor` run inline on the main thread and can silently skip that prose step.

**Problem Statement:**
The plugin maintainer needs the until-mergeable drain (the v14.32.0 / PR #65 feature) to fire dependably, because today it is triggered ONLY by Supervisor Phase 4.5 prompt step 5.5 (`agents/supervisor.md:1011`) — *agent-prompt logic, not a hook*. On the inline `/autonomous`/`/supervisor` path the Supervisor IS the main thread (not a subagent), so the existing `SubagentStop(supervisor-runner)` hooks never fire either, and if the agent doesn't execute step 5.5 the drain silently never dispatches (observed: a real `/autonomous` run created a PR and the drain never ran). Success looks like: the drain dispatches when a plugin-orchestrated PR is created, even if step 5.5 is skipped, with no double-dispatch and no behavior change to unrelated PRs.

**Design decisions baked into this brief (Plan Review + Phase 6 should confirm):**
1. **`PostToolUse[Bash]` is the correct hook, NOT `SubagentStop`.** SubagentStop(supervisor-runner) does not fire on the inline path (the Supervisor is the main thread there), so it cannot close this gap. `PostToolUse[Bash]` fires on the actual `gh pr create` tool call — the agent cannot "forget" it.
2. **Defense-in-depth, not a replacement.** Keep Supervisor step 5.5 unchanged. The hook is an additive backstop. The dispatcher's existing **per-PR idempotency marker** guarantees exactly ONE dispatch even if BOTH the hook and step 5.5 fire for the same PR.
3. **Session-scope gate (the key safety decision) — branch-match against EXISTING durable state, NOT a new prompt-written marker.** A naive `PostToolUse[Bash]` hook would fire on *any* `gh pr create` in *any* repo — hijacking unrelated manual PRs. A non-empty `.supervisor/jobs/in-progress/` **alone is too broad**. The wrapper gates on a signal it can trust: **(a)** an in-progress job exists, AND **(b)** the PR's head branch (the branch `gh pr create` runs from = current git branch) matches the **active Supervisor session's feature branch**, resolved from `.supervisor/state.md` (Supervisor records the branch in Phase 1 ACQUIRE — *core* workflow), with the current git branch as the practical fallback. **Why NOT a new producer marker (addresses the review's High-1):** a marker written by a Supervisor/autonomous *prompt step* would reintroduce the exact prompt-skip fragility this hook exists to fix (the agent could skip the marker-write just as it skipped step 5.5). So the gate deliberately consumes state the core lifecycle ALREADY writes durably — branch creation + `state.md` + the `in-progress/` job move, none skippable without aborting the run. **The producer is the existing Supervisor lifecycle; the consumer is the wrapper — both are now specified and wired (no new producer code).** An explicit short-TTL marker is OPTIONAL future hardening, never the sole signal. Bare "in-progress non-empty" is explicitly NOT sufficient. This is the headline review point.
4. **Reuse `dispatch-pr-review.sh` as-is — relying on its current default-ON semantics.** It already does opt-out resolution, the per-PR marker, and fail-safe `exit 0`. The wrapper does NOT re-implement any of that — it extracts the PR URL and calls the dispatcher. **Dependency note:** this brief depends on the dispatcher being **default-ON** (the #65 / v14.32.0 behavior — `ENABLED=1`, suppressed only by an explicit `auto_review:false`). Against a pre-#65 (opt-in) dispatcher the hook would call it and it would silently no-op until `auto_review:true`; Subtask 2 MUST verify the installed `dispatch-pr-review.sh` is the default-ON version.

**Out of scope (documented follow-ups):** the optional completion-tail GUARD (refuse a "success" SUPERVISOR_RESULT unless `until_mergeable_dispatched` is set/suppressed — the 11.1.2 anti-skip-guard pattern). The hook alone closes the "agent missed the prompt" gap; the loud-failure guard is a separate, additive hardening slice.

## On/Off controls (unchanged — documented for completeness)
The hook reuses the existing switches; it adds NO new default-on side effect beyond what step 5.5 already does:
- **OFF entirely:** `.supervisor/notify-config.json` `{"auto_review": false}` (or `--no-auto-review` on a faithful `/supervisor`).
- **Drain off, plain review on:** `{"auto_until_mergeable": false}` (or `--no-until-mergeable`).
- **ON (default):** no action.

## Acceptance Criteria

> ACs are numbered so the Subtask Structure can reference them precisely (e.g. "AC 1–8").

1. **AC1** — Given the main thread runs `gh pr create` via the Bash tool **during an active plugin run**, when the `PostToolUse[Bash]` hook fires, then the wrapper extracts the `https://github.com/.../pull/<n>` URL from the tool response and invokes `dispatch-pr-review.sh --pr-url <url>` (which itself applies opt-out + per-PR idempotency + fail-safe).
2. **AC2** — Given a Bash call that is NOT a PR creation (no `/pull/<n>` URL in the response), when the hook fires, then the wrapper no-ops and exits 0.
3. **AC3** *(branch-match session gate)* — Dispatch happens ONLY when ALL hold: **(i)** `.supervisor/jobs/in-progress/` is non-empty (the primary gate — it IS cleared on completion); **(ii)** `.supervisor/state.md` Status is NOT `completed`/`failed` (state.md **retains the last session's `- branch:` after completion**, so the branch term is not self-clearing — this guards the stale-branch case); AND **(iii)** the PR's head branch == the active session's feature branch (from `.supervisor/state.md`, current-git-branch fallback). Given a `gh pr create` that fails ANY of (i)–(iii) — head branch mismatch, OR `jobs/in-progress/` empty, OR state.md Status `completed` — when the hook fires, then it no-ops and exits 0. A non-empty `.supervisor/jobs/in-progress/` **alone MUST NOT** trigger dispatch.
4. **AC4** — Given the drain is opted out (`.auto_review:false` or `.auto_until_mergeable:false`), when the hook dispatches, then `dispatch-pr-review.sh` honors the opt-out (no change to existing opt-out semantics).
5. **AC5** — Given both the hook AND Supervisor step 5.5 fire for the same PR, when each calls the dispatcher, then the per-PR marker yields exactly ONE detached drain (no double-dispatch).
6. **AC6** — Given `claude`/`jq` missing or a malformed PostToolUse payload, when the hook fires, then it logs one stderr line and exits 0 (never breaks the originating Bash tool call).
7. **AC7** *(one-time fixture capture — manual/dev-time, NOT a CI test step)* — A fixture (e.g. `scripts/fixtures/posttooluse-gh-pr-create.json`) is **captured from a REAL `PostToolUse[Bash]` payload** (top-level `hook_event_name`, `tool_name`, `tool_input` with the Bash `command`, and `tool_response` with the `gh pr create` stdout / PR URL) and **checked in**. It MUST be derived from / verified against an actual emitted payload — never hand-invented (the documented hook-payload-shape footgun: assumed shapes have diverged from real ones). Capturing it is a **documented one-time developer step**; the resulting fixture file is committed.
8. **AC8** *(deterministic test — no live `gh`/`claude`)* — `scripts/test-hook-dispatch-on-pr-create.sh` (mirroring `test-dispatch-pr-review.sh` style) runs **deterministically against the checked-in AC7 fixture** — no live `gh pr create`, no `claude` launch — and asserts: URL extraction from the real-shaped fixture, no-op on non-PR Bash (AC2), the branch-match session gate (AC3) **including the stale-state cases — `jobs/in-progress/` empty with branch matching → no-op, AND state.md Status `completed` with branch matching → no-op** — opt-out honored (AC4), and fail-safe exit 0 (AC6). The suite passes in CI.
9. **AC9** — `hooks/hooks.json` gains exactly ONE well-formed `PostToolUse[Bash]` entry pointing at the wrapper; existing hook entries are unchanged.
10. **AC10** — Authoritative hook count goes `19 → 20` (`jq '[.hooks[][].hooks[]] | length'`); the CLAUDE.md hook table gains the new PostToolUse row; every `19`-hook current-claim is updated (plugin.json, marketplace.json, agent-help.md, README.md, .claude-plugin/README.md, AGENT_GUIDELINES.md, CLAUDE.md); version bumped; `check-doc-currency.sh` + `validate-version.sh` green.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Fail-safe hook wrapper (branch-match gate) + self-test + checked-in real-payload fixture | AC 1–8 | 0 modify, 3 create | error-handling | LAUNCHABLE |
| 2 | Register PostToolUse hook + verify default-ON dispatcher + Supervisor backstop note | AC 1, 5, 9 | 2 modify, 0 create | monitoring-observability | BLOCKED (by #1) |
| 3 | Hook-count + version bump + doc-currency | AC 10 | 7 modify, 0 create | quality-checklist | BLOCKED (by #2) |

### Provides / Requires Contracts

```yaml
# Subtask 1 — Fail-safe hook wrapper (branch-match gate) + self-test + fixture (LAUNCHABLE)
provides:
  - {kind: "file", path: "ai-agent-manager-plugin/scripts/hook-dispatch-on-pr-create.sh"}
  - {kind: "file", path: "ai-agent-manager-plugin/scripts/test-hook-dispatch-on-pr-create.sh"}
  - {kind: "file", path: "ai-agent-manager-plugin/scripts/fixtures/posttooluse-gh-pr-create.json"}
requires: []
external_requires:
  - "dispatch-pr-review.sh (existing, unchanged — reused for opt-out + idempotency + dispatch)"
  - ".supervisor/state.md (existing — read-only, for the active session's branch in the AC3 gate)"

# Subtask 2 — Register PostToolUse hook + Supervisor backstop note (BLOCKED by #1)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/hooks/hooks.json", name: "PostToolUse"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/supervisor.md", name: "hook backstop"}
requires:
  - {from: "1", kind: "file", path: "ai-agent-manager-plugin/scripts/hook-dispatch-on-pr-create.sh"}
external_requires: []

# Subtask 3 — Hook-count + version bump + doc-currency (BLOCKED by #2)
provides:
  - {kind: "symbol", path: "CLAUDE.md", name: "PostToolUse"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/.claude-plugin/plugin.json", name: "version"}
  - {kind: "symbol", path: ".claude-plugin/marketplace.json", name: "description"}
  - {kind: "symbol", path: "CHANGELOG.md", name: "14.34.0"}
requires:
  - {from: "2", kind: "symbol", path: "ai-agent-manager-plugin/hooks/hooks.json", name: "PostToolUse"}
external_requires: []
```

**Contract note:** this is a **dependency chain (1 → 2 → 3)**, not a parallel fan-out. Subtask 2's hook entry references subtask 1's script; subtask 3's authoritative hook count (`20`) requires subtask 2's hooks.json change to be present. Doc-currency must run on the integrated tree (the worktree-isolation gotcha) — so sequential execution by a single worker is correct and intended here.

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2 ──→ Subtask 3
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none (but #2 requires #1's script) | YES (dependency) |
| Subtask 2 | Subtask 3 | none (but #3 requires #2's count) | YES (dependency) |
| Subtask 1 | Subtask 3 | none | YES (transitive) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after #1)
- **Batch 3:** Subtask 3 (after #2)
- **Recommended workers:** 1 (sequential chain — tightly coupled; doc-currency needs integrated tree)
- **Estimated batches:** 3

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/error-handling/SKILL.md` |
| 2 | `skills/monitoring-observability/SKILL.md` |
| 3 | `skills/quality-checklist/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Hook hijacks unrelated manual PRs** (fires on any `gh pr create` in any repo) | HIGH | Session-scope gate (AC3): dispatch ONLY when an in-progress job exists AND the PR's head branch matches the active session's branch (from `.supervisor/state.md`, current-git-branch fallback). **Bare `.supervisor/jobs/in-progress/` non-empty is explicitly insufficient.** No-op + exit 0 otherwise; covered by AC3 + a test case |
| **Gate signal is itself prompt-skippable** (a new producer marker would reintroduce the step-5.5 fragility) | MEDIUM | The gate consumes EXISTING durable lifecycle state (branch + `state.md` + the `in-progress/` job move — core Phase 1 writes that cannot be skipped without aborting the run), NOT a new prompt-written marker. Producer = existing Supervisor lifecycle; consumer = the wrapper. An explicit marker stays optional future hardening, never the sole signal |
| **Test passes against an invented payload, fails against the real hook** | MEDIUM | AC7: the test fixture MUST match the real `PostToolUse[Bash]` payload shape (`hook_event_name`/`tool_name`/`tool_input`/`tool_response`), captured empirically from one real `gh pr create` under the hook — never a hand-invented sample. This is the documented hook-payload-shape footgun (assumed shapes have diverged from real ones) |
| **Hook calls the dispatcher but it no-ops** (dispatcher not default-ON) | LOW | This brief relies on the #65 / v14.32.0 **default-ON** `dispatch-pr-review.sh` (`ENABLED=1`; suppressed only by explicit `auto_review:false`). Subtask 2 verifies the installed dispatcher is the default-ON version; against a pre-#65 opt-in dispatcher the hook would correctly call it yet no-op until `auto_review:true` |
| **Double-dispatch** (hook + step 5.5 both fire) | MEDIUM | Reuse `dispatch-pr-review.sh`'s existing per-PR idempotency marker — exactly one drain per PR; AC5 + test assert it |
| **Hook breaks the originating Bash call** (non-zero exit) | HIGH | Wrapper is fail-safe: any failure (missing claude/jq, malformed payload, parse miss) logs one line and `exit 0`. PostToolUse must never block the tool. Mirrors `send-telemetry.sh`/`send-webhook.sh` |
| **Version/sequencing collision with open PR #66 (v14.33.0)** | MEDIUM | This brief targets **v14.34.0** and assumes #66 lands first. Execute AFTER #66 merges (then Base Branch `main`, bump 14.33.0→14.34.0). If executing before #66 merges, stack this on `feature/phase2b-knowledge-sources-insights` (set Base Branch accordingly) to avoid a 14.33.0 collision |
| **PR-URL extraction misses non-`gh pr create` PR creation** (MCP/other tool) | LOW | Documented limitation: the hook covers `gh pr create` via the Bash tool (the plugin's only PR-creation path). Step 5.5 remains as the in-context path for anything else |
| **Hook-count doc drift (19→20 across 7 surfaces)** | MEDIUM | Run `check-doc-currency.sh` after edits; it enumerates the count-claim surfaces. Update the CLAUDE.md hook table row + every `19`-hook claim in plugin.json/marketplace.json/agent-help/README/.claude-plugin-README/AGENT_GUIDELINES |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 3
- **Base Branch:** main
- **Target version:** 14.34.0 (assumes PR #66 / v14.33.0 lands first — see Risk Assessment for the stack-vs-wait sequencing)

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-06-18-until-mergeable-pr-create-hook.md
```

---

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/67 (base: main)
- **Version:** 14.33.0 → 14.34.0
- **Hook count:** 19 → 20
- **heal_loop_ran:** true
- **heal_decision:** PASS
- **heal_iterations:** 1
- **heal_fixable_issues_fixed:** 1 (LOW defense-in-depth: added `gh pr create` command guard to tighten the session gate's false-positive surface)
- **heal_remaining_issues:** 0
- **Tests:** test-hook-dispatch-on-pr-create.sh 9/9; test-dispatch-pr-review.sh 16/16 (no regression)
- **Gates:** check-doc-currency.sh ✓; validate-version.sh ✓ (14.34.0); hook leaf-count = 20
- **Until-mergeable dispatched:** true
