# 06 — Derived-artifact freshness: detect + nudge refresh of graph / bridge / agent-memory

## Problem
Item 02 handles curation of the human-curated stores (lessons, rules, memos). A second category — artifacts DERIVED from the repo — has no refresh path at all and silently drifts as the repo moves:
- `graphify-out/graph.json`: built once (manually, weeks/hundreds-of-commits ago); `brain-context` either silently falls back or serves the stale graph as advisory context with no age signal to the consumer.
- Findings→community bridge output: `read-bridge.sh` carries a staleness caveat but nothing ever prompts a `build-bridge.sh` rerun.
- Per-agent memory dirs (`.claude/agent-memory/*`): append-forever, no decay — same rot class item 02 fixes for the curated stores, but these six dirs are outside 02's scope.
Bet 3 made freshness a READ-side law (stale = hint, demote-never-drop). The refresh half — noticing drift and prompting a rebuild — is undesigned.

## Goal
Every derived artifact knows its own basis (as-of commit), every reader surfaces its age, and one advisory surface tells the human what's stale and how to refresh it. Advisory throughout — never auto-rebuild (graphify is expensive), never gate.

## Scope
1. **Basis stamping:** ensure each derived artifact records its as-of `HEAD` sha + timestamp at build time (graph.json metadata sidecar if the schema can't carry it; bridge output already close). Builders own the stamp.
2. **Staleness probe:** small fail-safe `check-derived-freshness.sh` (always exit 0): per artifact, commits-behind + age; thresholds documented, configurable, advisory.
3. **Surfacing at three existing seams (no new hooks):**
   - `/insights` (and/or `/handoff`) gains a `## Freshness` section listing each derived artifact, its basis, drift, and the one-line refresh command (`/graphify .`, `build-bridge.sh`, …).
   - `brain-context` reader prepends an age/basis line to any graph-derived context it injects (auditability — the human can SEE the basis, per the north star's trust-surface frontier).
   - The existing SessionStart nudge pattern (session-resume.sh, EMPTY-output-gated, hook-neutral) may add a one-line stale-twin hint mirroring the `/setup twin` nudge design. One line, debounced, never blocking.
4. **Agent-memory decay:** extend item 02's stale-knowledge flagging to the six agent memory dirs — `/dreaming` intake lists entries whose referenced files/paths no longer resolve as retire candidates (human-gated, mirrors 02's mechanism; coordinate to avoid duplicate implementations).
5. **Refresh ergonomics:** one documented command per artifact (existing commands — just enumerated in the Freshness section); `/setup twin` verify step reports drift too.

## Non-goals
No auto-rebuilds, no schedulers/cron, no new gating, no graph-schema migration, no new stores (freeze-compatible: this consumes existing signals and adds no advisory reader beyond age annotations on ones that already run).

## Acceptance criteria
- Each derived artifact carries a verifiable basis sha after a rebuild (falsify: hand-corrupt the stamp → probe reports `unknown-basis`, never crashes).
- `/insights` Freshness section renders on this repo showing the real (stale) graph age.
- brain-context injection demonstrably includes the age/basis line; missing artifact ⇒ unchanged silent fallback.
- All probes/readers always-exit-0 fail-safe; CI gates green.

## Outcomes Rubric
- Basis stamps on graph + bridge outputs
- Freshness section live with real drift numbers
- Age/basis line visible in injected brain context
- Agent-memory retire candidates surfaced via /dreaming, human-gated

## Status: pending — RE-SCOPED 2026-09-21 (two of three targets retired)
- **What changed since authoring (2026-07-20):** the graphify graph + bridge tier was RETIRED by twin-loop/06 (job `2026-08-17-retire-graphify-tier`, see `skills/brain-context/SKILL.md` §"Retirement note"). Scope items 1–3 and 5 as written target artifacts that no longer exist.
- **Surviving scope:** (a) basis-stamp + staleness line for the owned repo-map (`build-repo-map.sh` output) and orientation memos; (b) agent-memory decay across the three live `.claude/agent-memory/loomwright-loomwright-{code-reviewer,qa-executor,red-team-reviewer}/` dirs, coordinated with item 02's supersede/decay flags; (c) one `## Freshness` line in `/handoff`. Drop everything naming graph.json, bridge, `/graphify`, `build-bridge.sh`.
- Rewrite the Scope/AC sections to the surviving scope before dispatching; do not run as-is.
