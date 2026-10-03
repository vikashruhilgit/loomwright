# 12 — Unified `tools:` superset across the 14 agents (4c; D8)

**Provenance.** This is item 07's scope item 3, split out and enqueued on its own because the source
requirement itself mandates it: *"4c gets its own PR (plugin-wide frontmatter change)"*
(`07-route-freshness-tools.md:3`, `:42`). Item 07's PR delivers 4f + 4g only. This file exists so
the deferral is a **recorded** hand-off rather than a silent drop — the failure mode the engine's
own PLAN directive warned about twice.

## Problem

13 distinct `tools:` lists across 14 agents. Render order is tools→system→messages, so agents
diverge at byte 0 and share no cache prefix — which is why the v15.13.0 shared-prefix block cannot
buy cross-agent sharing.

> **Premise correction (recorded at execution, 2026-08-05 — do not re-derive the optimistic
> reading below).** This section originally claimed *"the unified tools block + shared prefix
> stacked is what clears the [512-token] floor"*. That premise is **FALSE** and was falsified
> before the executing brief was written: unifying `tools:` alone does not clear the floor, because
> `disallowedTools:` renders in the same pre-system-prompt frontmatter block and is deliberately
> **not** unified (per-agent read-only enforcement forbids it — see the executing brief's RULE B).
> Cross-agent prompt-cache reuse remains structurally **zero** after this change. See
> `loomwright/docs/shared-agent-prefix.md` §"HONEST CACHE EXPECTATION" and
> `loomwright/docs/POINTER_AUDIT.md` §"HONEST CACHE EXPECTATION" for the corrected, evidenced
> framing. This item shipped as a **consistency-only** change with honest cache-floor reporting, not
> a cache win.

Verified on disk (2026-07-30) — the 14 current lists, `orchestrator` and `qa-strategist` being the
only byte-identical pair, which is what makes it 13 distinct rather than 14:

| Agent | `tools:` |
|---|---|
| code-reviewer | Read, Glob, Grep, Bash, LSP |
| context-keeper | Read, Write, Edit |
| execute-manager | Task, TaskOutput, Read, Bash, Glob, Grep |
| launch-pad | Read, Write, Glob, Grep, Bash, Task, LSP |
| orchestrator | Read, Glob, Grep, Bash |
| plan-reviewer | Read, Glob, Grep |
| product-owner | Read, Glob, Grep, Bash, WebSearch, WebFetch |
| qa-executor | Read, Write, Edit, Glob, Grep, Bash, Task, LSP |
| qa-strategist | Read, Glob, Grep, Bash |
| red-team-reviewer | Read, Glob, Grep, Bash, WebFetch, WebSearch |
| review-pr | Task, Read, Glob, Grep, Bash |
| rubric-grader | Read, Bash, Glob, Grep |
| supervisor | Task, TaskOutput, Read, Glob, Grep, Bash, Write, Edit |
| worker | Read, Write, Edit, Bash, Glob, Grep, LSP |

Note `rubric-grader` is the same SET as `orchestrator`/`qa-strategist` but a different ORDER — order
matters for a shared cache prefix, so the superset must be emitted in one canonical order.

## Scope

Unify `tools:` to a superset across the 14 agents; verify no agent gains a tool its contract
forbids. Read-only roles keep enforcement via `disallowedTools` — the mechanism that survives plugin
distribution (`permissionMode` is silently ignored for plugin agents, per CLAUDE.md).

## Non-goals

No change to any agent's actual capabilities or contract. No new gates. This is a cache-prefix and
consistency change, not a permissions change.

## Acceptance criteria

- Tools superset landed across all 14 agents, emitted in ONE canonical order.
- Read-only enforcement verified **per-agent**: every role that previously lacked a mutating tool
  and gains it in the superset must carry the corresponding `disallowedTools` entry. Name the
  per-agent verification, do not assert it in aggregate.
- Cache-prefix claim **re-measured**, with honest framing: this is a consistency win *unless* the
  512-token floor is actually cleared — say which it turned out to be, with the measurement.
- `scripts/check-shared-prefix.sh` still passes (it enforces byte-identical shared prefix, exactly
  once per agent, and fails closed).
- Token budgets re-declared for any agent whose measured weight moves, with the margin stated.
- Full gate set enumerated from disk (`ls scripts/check-*.sh scripts/validate-*.sh`) and green.

## Outcomes Rubric

- Tools superset landed across all 14 agents in one canonical order
- Per-agent `disallowedTools` verification recorded, not asserted in aggregate
- Cache-prefix claim re-measured with honest framing (floor cleared or not)
- Token budgets re-declared where measured moved, margin stated

## Status: done

Job `.supervisor/jobs/done/2026-08-05-4c-unified-tools-superset.md` completed. Shipped in PR #125 (v15.24.0), MERGED 2026-08-06T05:15:02Z at merge commit `261ff1b`, verified contained in `origin/main`.

Promoted from `brief-shipped` on 2026-08-06 only after checking the ACs against merged `main` (the precondition this section previously stated), not on the merge alone:
- **AC1 (unified `tools:`)** — 14 agent files, `sort -u` over their `tools:` lines yields exactly **1** distinct line. 13 distinct lists → 1.
- **AC2 (no capability change, measured against the EFFECTIVE set)** — all 14 agents carry a `disallowedTools:` row; the four `memory: project` agents that effectively hold `Write`/`Edit` today (`launch-pad`, `product-owner`, `qa-strategist`, `red-team-reviewer`) deliberately do **not** block them.
- **AC3 (honest cache framing)** — satisfied through its own "say which it turned out to be" branch: `docs/shared-agent-prefix.md` states the 512-token cross-agent floor is **NOT** cleared, and records the one **unverified dependency** in that claim (whether `disallowedTools` reaches the rendered request prefix) rather than dropping it, erring toward the conservative reading. `docs/ARCHITECTURE_CONTRACTS.md` carries the matching **PROVISIONAL** hedge.

**Recorded honestly — one question shipped OPEN.** The owned drain terminated `ESCALATED` on a deliberately unresolved finding: whether to keep `Write`/`Edit` blocked for `product-owner` / `qa-strategist` / `red-team-reviewer`. Merging the PR resolved the park, **not the question** — it now lives on `main` as a PROVISIONAL claim. See `CHANGELOG.md` v15.24.0 and the `code-reviewer` open question left unresolved by design.
