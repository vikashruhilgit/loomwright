# 04 — The Floor: a local, animated view of the run

## Problem

Items 01–03 make the truth available; nothing renders it. The specific gap this closes is
not "there is no dashboard" — `/insights`, `/handoff` and `/obsidian` already report
*history* well. It is that there is no way to see **what is happening now**: which agents
are alive, on which worktree, how far into their turn budget, and — most usefully —
which one has **stopped moving**.

A stall is currently invisible. It is discovered by a human noticing that nothing has
happened for a while.

## Goal

A local, read-only web view of `floor.json` in which motion carries information: an agent's
position is its progress against its declared `maxTurns`, and an agent that stops emitting
events visibly stops and desaturates.

Design reference: the published research artefact "The Loom Floor" (2026-09-01), which
carries a working animated mock of the intended layout — five pipeline stages
(Queue · Plan · Execute · Review · Shipped) above a set of parallel lanes, one per active
worktree. The mock is a **design proposal driven by a timer**, not a screenshot; treat its
layout as the specification and its data as placeholder.

## Scope

1. **A static bundle** — hand-authored HTML/CSS/JS, no framework, no bundler, no build
   step, polling `floor.json` on an interval. Self-contained.
2. **A `/setup ui` module** following the observability module's pattern exactly: the module
   copies the bundle to `~/.claude/loomwright/ui/` and operates on that **copy**, never on
   the plugin install directory (see `loomwright/docs/OBSERVABILITY.md`, which states this
   rule for `~/.claude/loomwright/observability/`).
3. **Served by `python3 -m http.server`.** Python 3 is already a hard dependency —
   **eight** hook entries in `hooks.json` invoke it directly (verified 2026-09-01). Bind to loopback only.
4. **Identity from frontmatter, not from prose.** Colour, `model:` tier and `maxTurns` come
   from `loomwright/agents/*.md` via `floor.json`. Read-only agents (those whose
   `disallowedTools` covers Write/Edit) are drawn distinctly — that distinction is
   load-bearing in this system and worth making visible.
   *(Amended 2026-09-03: identity reaches a lane only through a recorded `agent_type`, which
   is present on a minority of events — see the Amendment under `## Depends on`; the roster
   itself is always complete because it is read from frontmatter, not from the log.)*
5. **Honest empty and stale states.** No run in flight ⇒ the view says so. `floor.json`
   older than its freshness threshold ⇒ the view says so, prominently. A stalled agent stops
   moving; the **absence** of motion is the signal, which is why the animation must be
   event-driven and never a decorative loop that runs regardless.
6. **Accessibility and theme.** Honour `prefers-reduced-motion` (freeze motion, keep state
   legible), work in light and dark, and keep every state readable without colour alone —
   14 saturated agent hues cannot carry meaning by themselves.

## Non-goals

- **No control plane.** The view is strictly read-only: no buttons that start, stop, merge,
  approve or retry anything. It renders; it does not act.
- **No writes to `.supervisor/`** beyond what 03 already produces.
- **No network egress, no telemetry, no analytics.** Local only — the same posture
  `/insights` and `/obsidian` state.
- **No Node, no npm, no CDN.** Any of those would add a dependency the plugin does not have.
- No authentication layer, because there is nothing to authenticate against on loopback —
  but also therefore **no binding to `0.0.0.0`**.

## Depends on

**03 merged** (hard — this renders `floor.json` and nothing else). Benefits from 01 but
must degrade honestly without it: if spawn data is absent, the lanes show last-known state
with an explicit "liveness unavailable" note rather than animating on inferred activity.

### Amendment 2026-09-03 — item 01 outcome and what the logs actually carry (measured, do not re-derive)

- **01 closed NO-GO and shipped no emitter** (PR #170/#171). There is no `agent_spawn`
  event in any log, so spawn data is absent on every run and the "liveness unavailable"
  note above is the permanent default, not an edge case.
- **Per-lane identity is PARTIAL, not absent.** The `SubagentStop` emitters
  (`emit-progress-event.sh`, `emit-token-ledger.sh`) already record `agent_type` when the
  host passes it. Measured across `.supervisor/logs/*.jsonl` on 2026-09-03: 194 events carry
  `agent_type` (128 `token_ledger`, 66 `subtask_complete`; only `code-reviewer` and `worker`
  ever appear); since 2026-09-01 it is 8 typed events against 2,823 untyped. In the newest
  session, 4 of 20 `agent_id`s can be typed. So a lane's colour/name comes from the roster
  when ANY event for that `agent_id` carried a type, and is drawn as identity-unknown
  otherwise — never inferred from ordering, recency or count.
- **"Turn counts" are not derivable.** `token_ledger` fires at `SubagentStop` (a stop, not
  a tool call) and carries only a transcript-bytes proxy; nothing records tool calls or
  turns per agent. The lane therefore shows the agent's **event count** and **last-event
  age** (both facts from the record's own `ts`), and its position is that count relative to
  the busiest lane in the same session. `maxTurns` from frontmatter is shown on the roster
  as the declared budget, never as a denominator for a progress bar.
- **Nothing here changes 03's contract.** The projector gains ADDITIVE optional keys
  (an `agents` roster surface from `agents/*.md` frontmatter, per-agent rows for the newest
  `cc_session_id` under `sessions.detail`, and the subtask rows under `state.detail`);
  `schema_version` stays 1 and every existing key is unchanged.

## Release-surface obligations

- `/setup` gains a module: update the `setup` skill, `commands/setup.md`, and the status
  dashboard. Command count is unchanged (21).
- No new agent (so no token-budget entry) and no new hook (so 24 is unchanged) — **if either
  turns out to be needed, bump every doc surface in the same commit**;
  `check-doc-currency.sh` fails CI otherwise.
- `check-vendor-coupling.sh` — a vanilla bundle plus `jq`/`python3` names none of the four
  vendor tokens, so the ratchet should not move. **Measure it rather than assuming**, and if
  it does move, classify the new files explicitly (CORE-ratcheted or ADAPTER-exempt) with the
  measured allowance regenerated via `--print-allowances`, never hand-typed.

## Acceptance criteria

- [ ] ~~Given a `floor.json` from a real run with 3 active agents, the view renders 3 lanes
      with the correct agent names, colours and turn counts — checked against the source
      file, not eyeballed.~~ **Void as of 2026-09-03** — "active" and "turn counts" have no
      source (see the Amendment under `## Depends on`). Replaced by: Given a `floor.json`
      whose newest session carries 3 agent rows — two with an `agent_type`, one without —
      the view renders 3 lanes; the two typed lanes carry the roster's name and colour for
      that type, the untyped lane is drawn neutral and labelled as identity unknown, and
      every lane's event count and last-event age match the file — checked against the
      source file, not eyeballed.
- [ ] Given an agent whose last event is older than the stall threshold, its lane stops
      moving and is visibly marked stalled; a control agent still emitting continues to move.
- [ ] Given no `floor.json`, an empty one, and one older than the freshness threshold (three
      separate cases), the view renders a clear state for each and never a blank page,
      spinner-forever, or console error.
- [ ] The page issues **zero** requests to any origin other than its own — asserted from the
      network log of a real page load, not from reading the source.
- [ ] The server binds loopback only — asserted by attempting a connection from a
      non-loopback address and having it refused.
- [ ] `prefers-reduced-motion: reduce` freezes motion while every state remains
      distinguishable; both themes render legibly.
- [ ] The vendor-coupling ratchet is measured before and after and the delta is reported,
      whatever it is.
- [ ] Removing the module leaves no residue in `~/.claude/` and no modified plugin file.

## Outcomes Rubric

- A run's live state is visible at a glance, and a stall is visible **without** being
  looked for.
- Motion encodes progress; nothing animates that is not backed by an event.
- Absent, stale and empty are all rendered honestly and distinctly.
- Zero new runtime dependencies; loopback only; nothing leaves the machine.
- The plugin's release surfaces and the coupling ratchet are left consistent and measured.

## Status: brief-shipped

Job `.supervisor/jobs/done/2026-09-03-the-floor-ui.md` completed (reconciled from the job lifecycle, not self-reported).
Acceptance criteria are NOT machine-verified here — review them before promoting this to `## Status: done`.
