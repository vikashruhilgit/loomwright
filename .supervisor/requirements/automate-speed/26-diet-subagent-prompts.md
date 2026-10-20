# automate-speed/26 — Prompt diet for the four most-spawned subagents: code-reviewer, execute-manager, plan-reviewer, worker

## Status: pending

## Problem
Items 13–16 shrink what the MAIN thread reads; nothing shrinks what each SUBAGENT reads at spawn. Subagents were 36%
of PR #555's item (63M of 172M context tokens: general-purpose 30.9M, worker 17.8M, code-reviewer 11.1M across 3
spawns, plan-reviewer 2.0M) and 14% of vendsy/hub PR #445's (13M: code-reviewer 6.5M, worker 2.8M, plan-reviewer 2.4M
across 3 spawns). Every spawn pays its prompt again (measured 2026-10-15, bytes/4 proxy):
- `agents/code-reviewer.md` 66KB + 5 preloaded skills (quality-checklist, context7-lookup, unit-testing,
  error-handling, monitoring-observability) ≈ 25K proxy tokens; spawned 3× per item (Phase 4.5 rounds).
- `agents/execute-manager.md` 61KB + 3 preloaded skills including `async-orchestration` (57KB) ≈ 39K proxy tokens.
- `agents/plan-reviewer.md` 49KB ≈ 12K proxy tokens (8 history references); spawned up to 3× per item.
- `agents/worker.md` 36KB ≈ 9K proxy tokens; also the template the general-purpose fix workers load.
Each spawn also starts at ~55K of host context (system prompt, tools) before its own prompt (plan doc §Why now).
`prompt-token-budgets.json` records stale `measured` values for two of them (plan-reviewer 6,392 and worker 4,158 vs
~12.4K and ~9.1K today).

## Goal
<!-- bump: minor -->
Each of the four agent prompts carries instructions and short rules only, preloads only the skills it uses on
every spawn, and loads the rest on demand — so every spawn of every item pays less.

## Scope
- **Part A — rule homes and stories out** (same method as items 13–16, applied per agent file): rules enforced by a
  SubagentStop validator, a hook, `verify-provides.sh` or another existing script lose their prose (keep one line
  only if the agent would otherwise attempt the blocked action); history and incident narrative moves to
  `loomwright/docs/rationale/subagents.md`, keeping a one-line "because" only where it blocks a tempting wrong
  shortcut. Result-block shapes the validators parse are interfaces and stay byte-identical.
- **Part B — preloads.** For each frontmatter `skills:` entry, keep it only if the agent uses it on every spawn; move
  the rest to an on-demand Read at the step that needs it (e.g. execute-manager reads the FINALIZE part of
  `async-orchestration` only at FINALIZE; code-reviewer reads `monitoring-observability` only when the diff touches
  observability code). Record each decision and its trigger in the rationale doc.
- Re-measure the four agents and set their `measured` values in `prompt-token-budgets.json` to today's figures (the
  ceiling-lowering itself is item 18).

## Invariants
- Every SubagentStop/Stop validator still parses each agent's result block (CODE_REVIEW_RESULT, PLAN_REVIEW_RESULT,
  WORKER_RESULT, execute-manager summary): the result-validator suites pass unchanged.
- Claude Code ignores `hooks` in plugin agent frontmatter; the frontmatter hook copies stay for `~/.claude/agents/`
  compatibility (CLAUDE.md "Hook gotcha") — do not delete them as "dead".
- The shared agent prefix stays byte-identical (`scripts/check-shared-prefix.sh`).
- No per-subtask LLM reviewer is introduced; Phase 4.5 stays the sole LLM gate. The code reviewer's EXECUTION
  DIRECTIVE and pin-mutation rules keep their meaning.
- Skill CONTENT is not edited here (async-orchestration belongs to items 11/15; review-heal to 12/14); only which
  skills an agent preloads changes.

## Non-goals
- Changing what any agent decides, reviews or returns. Model or effort changes (item 10 covers the coordinator only).

## Owner decisions (from _BACKLOG.md)
- D1: no rule is dropped — every removed rule names its enforcing script/hook or its new on-demand location in the
  rationale doc.
- D2: stories move to the rationale doc; one-line "because" only where it blocks a wrong shortcut.

## Acceptance criteria
- Given each of the four agents, then its spawn weight (`check-token-budget.sh` proxy, agent file + preloaded skills)
  is at least 30% lower; before/after per agent is in the PR body.
- Given `loomwright/scripts/test-result-validators.sh` (and the four agents' validator suites), then they pass unchanged.
- Given `loomwright/docs/rationale/subagents.md`, then every removed rule line maps to its enforcing script/hook or to
  the step that now reads it on demand.
- `prompt-token-budgets.json` `measured` values for the four agents equal the new measure.

## Validation (must pass before merge)
1. `check-token-budget.sh`, `scripts/check-shared-prefix.sh`, `test-result-validators.sh`, `check-doc-currency.sh`,
   `test-citation-drift.sh`; report `<passed>/<total>`.
2. Mutation control: delete a result-block field line from a scratch copy of `agents/code-reviewer.md`'s template ⇒
   the result-validator suite goes red.
3. Running system: one real Phase 4.5 round and one Plan Review on the slimmed prompts; paste each spawn's peak
   context from item 03's report.

## Depends on
none

## Touches
loomwright/agents/code-reviewer.md
loomwright/agents/execute-manager.md
loomwright/agents/plan-reviewer.md
loomwright/agents/worker.md
loomwright/docs/rationale/subagents.md
loomwright/docs/prompt-token-budgets.json
changelog.d/as26-diet-subagent-prompts.md

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-20T14:29:24Z
- **Brief:** .supervisor/jobs/done/2026-10-20-as26-diet-subagent-prompts.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/634
