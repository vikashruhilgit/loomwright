# Supervisor Job: Orca adapter — checkpoint/lifecycle mirror (fail-safe, probe-once)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main (v15.81.0)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (non-main worktrees from other concurrent plugin activity — acknowledged, non-blocking)
- **Source requirement:** .supervisor/requirements/orca-derived/06-orca-adapter.md

## Task
**Goal:** A new, fail-safe adapter script mirrors this plugin's own recorded lifecycle/checkpoint events into `orca` (a separate CLI tool) when it happens to be installed and configured — never as a dependency, never touching plugin core, and never breaking anything when `orca` is absent (which it is on this dev machine today).

**Problem Statement:**
The plugin runs unchanged inside Orca (verified from onorca.dev/docs: real `claude` PTY, `~/.claude` picked up, repo hooks run, slash commands listed, subagents shown as child rows). Orca has none of this plugin's differentiated "moat" (rules, rubric, churn, lessons, review lenses) and all of the undifferentiated shell (worktrees, agent state machine, CLI, orchestration inbox). Per this repo's own architecture rule (memory `portability-core-vs-adapter`: vendor-neutral CORE, harness-specific ADAPTERS — Loomwright should run under Cursor/Codex too, and native-tool integrations belong in an adapter, never core), this item is a NEW, isolated adapter — nothing it does may land in `agents/`, `skills/`, or `commands/`. `orca` is confirmed NOT installed on this dev machine (verified 2026-09-11 per the source requirement) — §A (this item) must be fully testable with a STUB `orca` on PATH, since no real instance exists to test against.

## Acceptance Criteria
- [ ] Given `orca` is NOT on PATH (today's actual state on this machine), when `scripts/adapters/orca/orca-mirror.sh <event-json>` is invoked with any event, then it exits 0 and does NOTHING — no `orca` subprocess is even attempted (the `command -v orca` check short-circuits before any probe).
- [ ] Given `orca` IS on PATH but `orca status --json` fails/errors (simulating a real-but-unconfigured/broken Orca install), when the mirror runs, then it exits 0 and does NOTHING — the probe result gates every subsequent call, and the probe is CACHED per session/run (one `orca status` call per run, not one per event — verify with a stub that counts its own invocations).
- [ ] Given `orca` IS on PATH and the probe succeeds, when the mirror receives a `phase_transition` event, then it invokes `orca --workspace-status in-progress` or `orca --workspace-status in-review` (mapping the specific transition correctly — read the source requirement for the exact in-progress/in-review split, and if the plugin's own recorded phase-transition semantics don't map cleanly onto Orca's two-state model, make the most defensible choice and document the mapping decision, don't guess silently).
- [ ] Given the same setup, when the mirror receives a `pr_created` event (carrying a PR URL), then it invokes the Orca workspace-status call for `in-review` AND posts a comment containing the URL — using Orca's actual comment-adding invocation shape (read `orca --help`/`orca worktree current --help` if the CLI is available to inspect on this machine, or derive the shape defensibly from the source requirement's own citations; a stub test proves the exact argv the mirror produces).
- [ ] Given the same setup, when the mirror receives a `worker_checkpoint` event (item 03, merged v15.81.0 — read `loomwright/scripts/checkpoint.sh` and its JSONL shape), then it invokes `orca worktree set --comment "<text>"` with the checkpoint's own text (bounded/escaped safely — never raw shell-interpolated).
- [ ] Given the same setup, when the mirror receives a `session_end` event, then it invokes the Orca workspace-status call for `completed` or `todo`, mapped from the session's own recorded status field (read `close-stranded-run.sh`'s `session_end` shape — `status: failed` etc. — as the grounding for what status values actually appear).
- [ ] Given the mirror is about to post an Orca comment, when it runs, then it FIRST reads the existing comment via `orca worktree current --json` and PRESERVES any user-written lines already there — never overwrites/clobbers human-authored text (Orca's own "reading before writing" rule, per the source requirement). A stub-backed test proves preservation: seed a stub comment, run the mirror, assert the seeded text survives alongside the new content.
- [ ] Given a stub `orca` on PATH recording its own argv to a file, when the FULL test suite runs, then it asserts: (a) the correct Orca CLI invocation shape for each of the four event types above, (b) comment preservation, (c) NO call at all when the probe fails, (d) `grep -rl orca loomwright/ --exclude-dir=adapters` returns ONLY documentation files (agents/skills/commands stay Orca-free — this is the core/adapter boundary this item must not violate).
- [ ] Given `loomwright/docs/ARCHITECTURE_CONTRACTS.md` has NO `## Portability` section today (confirmed absent), when this PR lands, then it creates one, citing memory `portability-core-vs-adapter`'s core/adapter architecture rule, documenting the `loomwright/scripts/adapters/` directory's existence and purpose, and stating the probe-once rule explicitly.

## Outcomes Rubric
- Mirror is fail-safe (always exit 0) and probe-once (one `orca status` call per run, cached, never per-event)
- No-op (not an error) when `orca` is absent OR present-but-unconfigured — both are silent, harmless no-ops
- Every mapped event (`phase_transition`, `pr_created`, `worker_checkpoint`, `session_end`) produces the argv a stub-backed test can assert on precisely
- User-written Orca comment text survives a mirror write (read-before-write proven by test, not just claimed)
- Core stays Orca-free: `grep -rl orca loomwright/ --exclude-dir=adapters` returns docs only
- New `## Portability` section exists in `ARCHITECTURE_CONTRACTS.md`, citing the core/adapter memory rule and the probe-once contract

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Orca adapter mirror (new script, stub-backed tests, Portability doc section) | all | 1 modify, 2 create | none preloaded | LAUNCHABLE |

**Split reason:** none — single subtask. One new, self-contained adapter script plus its test and one doc section; below the file-conflict, context-bound, and genuine-parallelism thresholds.

### Provides / Requires Schema

```yaml
# Subtask 1 — Orca adapter mirror (LAUNCHABLE)
provides:
  - {kind: "file", path: "loomwright/scripts/adapters/orca/orca-mirror.sh"}
  - {kind: "file", path: "loomwright/scripts/adapters/orca/test-orca-mirror.sh"}
  - {kind: "symbol", path: "loomwright/docs/ARCHITECTURE_CONTRACTS.md", name: "Portability"}
requires: []
lanes:
  - "loomwright/scripts/adapters/orca/orca-mirror.sh"
  - "loomwright/scripts/adapters/orca/test-orca-mirror.sh"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
external_requires:
  - "orca CLI (optional, runtime-detected — not a build/test dependency; all tests use a stub)"
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | (none preloaded — this is a new, isolated adapter script with no dependency on existing plugin skills) |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| The exact CALL SITES that should invoke `orca-mirror.sh` are under-specified by the source requirement — it names `phase_transition`/`pr_created`/`session_end` as event types to MAP, but says the wiring reuses "the same emitter helpers items 01/03 add," which are DIFFERENT event types (`agent_lifecycle`, `worker_checkpoint`). This is a genuine open question, not a settled fact | HIGH — could misdirect implementation effort | The worker should investigate where `phase_transition`/`pr_created`/`session_end` are ACTUALLY emitted today (agent-written via Context-Keeper prompts, or `close-stranded-run.sh` for session_end, or the PR-create hook for pr_created — read `loomwright/scripts/close-stranded-run.sh` and `loomwright/scripts/hook-dispatch-on-pr-create.sh` first) and choose defensible wiring, documenting the decision explicitly rather than guessing silently. **This subtask's PRIMARY deliverable is the mirror script + its stub-backed unit tests (each event type mapped correctly in isolation) — wiring it into live hook call sites is secondary and may reasonably be deferred to a documented follow-up if the call-site question proves genuinely ambiguous after investigation.** |
| `orca` is not installed on this machine — no live integration test is possible, only stub-backed unit tests | MEDIUM (inherent to the item, not a defect) | Source requirement explicitly designs for this; stub-based testing is the sanctioned approach, not a shortcut |
| A CLI-invocation adapter script is a plausible injection-risk surface if event JSON fields (e.g. checkpoint text, PR URL) are shell-interpolated unsafely | HIGH if mishandled | Use `jq`/array-based argv construction throughout, never string-interpolate untrusted event fields into a shell command |
| Feasibility (Phase 2.5) — Scope vs Supervisor Capability | LOW | Single-subtask, 1 new script + 1 new test + 1 doc section; well within Single-Agent Path capacity |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-17-orca-adapter.md
```

## Outcome
- **Heal loop ran:** true
- **Heal iterations:** 3 fix cycles (round 1: internal review PASS zero findings; round 2: external claude-review found a real phase_transition field-name bug + test-infra glob gap, fixed; round 3: external claude-review found a second, analogous pr_created field-name bug, fixed via follow-up PR #238 after #237 was independently merged by the repo owner)
- **Heal decision:** PASS (external claude-review clean on final commit)
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/237 (mirror + fixes) + https://github.com/vikashruhilgit/loomwright/pull/238 (follow-up field-name fix)
- **Merge commits:** f12999a (PR #237), b2b502d (PR #238) — both merge commits, --admin — required 1 approving review, no human reviewer available; standing order. #237 and #238 were both merged directly by the repo owner (vikashruhilgit) faster than this run reached them.
- **Version:** no plugin version bump (new isolated adapter, no core-plugin behavior change requiring one)
