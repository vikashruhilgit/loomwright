# 06 — Orca adapter: checkpoint mirror (code item; the §B shell evaluation is 06b)

## Context
The plugin runs inside Orca unchanged (verified from onorca.dev/docs: real `claude` PTY, `~/.claude` picked
up, repo hooks run, slash commands listed, subagents shown as child rows). Orca has NONE of the moat (rules,
rubric, churn, lessons, review lenses) and ALL of the undifferentiated shell (worktrees, agent state machine,
CLI, orchestration inbox). Architecture rule (memory `portability-core-vs-adapter`): vendor-neutral CORE,
harness-specific ADAPTERS — this is a NEW adapter, nothing lands in core. `orca` is NOT installed on the
dev machine as of 2026-09-11; §A must be testable with a stub on PATH.

## §A — mirror (normal code item)
1. `scripts/adapters/orca/orca-mirror.sh <event-json>`: fail-SAFE, exit 0 always; no-op unless
   `command -v orca` AND `orca status --json` succeeds (cache the probe per session — one `orca status`
   per run, not per event). Maps `phase_transition` → `--workspace-status in-progress|in-review`,
   `pr_created` → `in-review` + comment with the URL, `worker_checkpoint` (item 03) → `--comment "<text>"`,
   `session_end` → `completed|todo` by status. Reads the existing comment first (`orca worktree current
   --json`) and preserves user-written lines — Orca's own "reading before writing" rule.
2. Call sites: the same emitter helpers items 01/03 add (one `|| true` line each) — no prompt-layer edits.
3. Test: stub `orca` on PATH recording argv; assert mapping + preservation; assert NO call when the probe
   fails; assert `CLAUDE_PLUGIN_ROOT`-free core (the mirror is the only file that names `orca`).

## §B — moved
The D2 shell evaluation lives in `operator-run/06b-orca-shell-evaluation.md` (split 2026-09-12 — operator-run, not an
`/automate` item). This file is the mirror script only.

## Non-goals
No Orca-specific behavior in agents/, skills/, commands/. No use of `orca orchestration` (experimental; our
Supervisor is that layer). No `orca artifacts share` (data leaves the machine; user's explicit action only).

## Acceptance criteria (§A)
- Stub-backed test proves mapping, comment preservation, and the no-Orca no-op; `grep -rl orca loomwright/
  --exclude-dir=adapters` returns only docs.
- Adapter dir documented in a NEW `ARCHITECTURE_CONTRACTS.md` §"Portability" (no such section exists today —
  2026-09-12; the item creates it, citing memory `portability-core-vs-adapter`'s core/adapter rule) with the
  probe-once rule. `loomwright/scripts/adapters/` does not exist today either; this item creates it and 07 reuses it.

## Outcomes Rubric
- Mirror is fail-safe, probe-once, preserves human text
- Core stays Orca-free (grep-verified)
- §B lives in 06b; this file has no operator-only step

## Status: done (PR #237 merge f12999a + PR #238 merge b2b502d)
