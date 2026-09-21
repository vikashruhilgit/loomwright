# 02 — The status line: the cheapest visual surface

## Problem

Loomwright has **zero** visual surface. Verified 2026-09-01: `0` `.html`, `.css`, `.tsx`,
`.jsx`, `.vue` or `.svelte` files exist anywhere in the repo. To know what a run is doing
you read `.supervisor/state.md` by hand, or you wait.

Meanwhile Claude Code offers a persistent one-line surface (`statusLine` in
`settings.json`) that the plugin does not use at all, and
`loomwright/docs/ARCHITECTURE_CONTRACTS.md` already carries a table literally titled
**"Color Legend (Status Line)"** — a surface designed for, and never built.

That table is also **stale**. Measured 2026-09-01: all **14** agents declare a `color:` in
their frontmatter, but the legend has **12** rows. Missing: `review-pr-runner` (`#00CED1`)
and `rubric-grader` (`#9ACD32`). The 12 rows present all match frontmatter, so this is an
omission rather than a contradiction — but the table is written as the surface a status
line would consume, and it is already two agents behind the source of truth.

## Goal

Ship a status line that reports the live run in one line, and make the colour legend
derived rather than hand-maintained so it cannot drift again.

~~This item is also the **cheapest possible proof that item 01's spawn↔stop pairing
works**.~~ **Void as of 2026-09-02** — 01 closed NO-GO and shipped no emitter, so there is
no pairing to prove and no spawn event to count. That role is gone; what remains is the
status line itself, which never depended on 01. See the Amendment under `## Depends on`.

## Scope

1. **`status-line.sh`** — reads `.supervisor/state.md` (phase, branch, subtask table) and
   the session log's tail, and prints one line: phase, branch, `N/M` subtasks, and the age
   of the last event. ~~count of agents currently spawned-but-not-stopped~~ **Void as of
   2026-09-02** — 01 closed NO-GO and shipped no emitter, so this field has no source. AC 1
   below forbids emitting it AND forbids inferring it from a proxy; this line previously
   contradicted that AC. Fail-safe:
   any missing/unreadable input degrades to a shorter line, never an error and never a
   stack trace in the user's status bar. Exits 0 unconditionally.
2. **Opt-in wiring, never automatic.** The plugin must **not** write the user's
   `~/.claude/settings.json` as a side effect of installation. Offer it through the
   existing `/setup` umbrella as a module, using the deep-merge + timestamped-backup +
   abort-on-unparseable semantics `/setup observability` already implements for the env
   block (see `loomwright/docs/OBSERVABILITY.md` §"settings.json merge semantics").
3. **Derive the colour legend.** A small generator reads `color:` from
   `loomwright/agents/*.md` frontmatter and emits the legend table; the committed table in
   `ARCHITECTURE_CONTRACTS.md` becomes generated output, and a check asserts it matches.
   Fold the check into `check-doc-currency.sh` rather than adding a new CI script if it
   fits there naturally.
4. **Fix the two missing rows** as the first output of that generator — not by hand.

## Non-goals

- No colour changes. The 14 assigned hex values are settled and documented; this item makes
  the legend *derived*, not *different*.
- No new agent, no new command. `/setup` gains a module; the command count does not change.
- No animation, no multi-line rendering, no TUI. One line.
- Does not depend on item 03 or 04 and must not wait for them.

## Depends on

**01 merged**, for the active-agent count only. If 01 returned NO-GO, ship this item
without that field rather than substituting an inferred one — a status line that guesses
liveness is worse than one that omits it.

### Amendment 2026-09-02 — item 01 outcome (measured, do not re-derive)

Item 01 ran and closed **NO-GO**, shipping evidence but **no emitter**. Consequences that
change how this item should be read:

1. **There is no `agent_spawn` event in any log today.** The fallback above therefore FIRES,
   and it is correct as written — omit the spawn-derived field rather than inferring one.
   This is not a degraded compromise; it is the accurate state of the data.
2. **The reason differs from what the fallback assumed.** `PreToolUse[Task]` *does* fire once
   per subagent spawn. What it lacks is an `agent_id`: it carries `tool_use_id` (`toolu_…`)
   while `SubagentStop` carries `agent_id` (`a…`). Measured, 2 spawns / 2 captures, fixtures
   committed at `loomwright/scripts/progress-event-fixtures/spawn-probe-2026-09-02/`.
3. **The path to enabling the field later is known and cheap.** The spawn payload carries
   `tool_input.subagent_type` and `tool_input.description`, so a liveness count keyed on
   `tool_use_id` needs no join at all. Correlating with the historical `agent_id` corpus is
   the part that needs a second hook (`PostToolUse[Task]`, whose `tool_response.agentId`
   bridges the two — verified 2/2) and resolves only when an agent *finishes*.
4. **Do not re-run the probe.** The verdict, the raw payloads and three falsified assumptions
   (the matcher is `Task` but the payload reports `tool_name: "Agent"`; `effort` is an object
   in one payload and a string in another; `agent_type` already ships on the stop side) are
   recorded in `loomwright/docs/SPIKES/AGENT_SPAWN_PAYLOAD_PROBE.md`.

## Acceptance criteria

- [ ] ~~Given a live run with 2 agents spawned and 1 stopped, the line reports **1** active~~
      — **NOT APPLICABLE (01 NO-GO).** No emitter shipped, so no `agent_spawn` event exists in
      any log and this criterion is unsatisfiable, not merely unmet. The status line MUST omit
      the active-agent field entirely rather than inferring one. Positive requirement in its
      place: **the rendered line contains no active-agent field, and no code path infers
      liveness from `token_ledger` recency or any other proxy** — grep-checkable, and the
      inference path is the specific failure this substitution exists to forbid.
- [ ] Given a missing `state.md`, an unparseable `state.md`, and an empty session log
      (three separate cases), the script prints a degraded line and exits 0 each time.
- [ ] Given a `~/.claude/settings.json` that fails to parse, the setup module **aborts**
      and writes nothing; a timestamped backup exists before any successful write; keys
      unrelated to `statusLine` are preserved byte-for-byte (diffed, not asserted).
- [ ] The generated legend contains **14** rows and byte-matches every agent's frontmatter
      `color:`; deleting a `color:` line or adding a 15th agent fails the check.
- [ ] The check is mutation-verified — reverting the generator's wiring fails the check, and
      the check is proven to have actually **executed** (not merely be reachable) on a
      fixture where the legend and frontmatter genuinely disagree.
- [ ] Uninstalling / disabling the module restores the prior `settings.json` state.

## Outcomes Rubric

- One honest line, live, opt-in, that degrades instead of breaking.
- The legend can no longer drift, and the drift found on 2026-09-01 is closed by the
  mechanism rather than by hand.
- ~~01's pairing is confirmed working on a real run before a week is spent on 03 and 04.~~
  **Void as of 2026-09-02** — 01 closed NO-GO and shipped no emitter, so there is no
  pairing to confirm; this bullet was unsatisfiable, not merely unmet. In its place:
  the absent active-agent field is *honestly* absent — omitted rather than guessed,
  and no code path infers liveness from a proxy.
- The user's `settings.json` is never touched without consent and never left corrupt.

## Status: done

Job `.supervisor/jobs/done/2026-09-02-status-line.md` completed (reconciled from the job lifecycle, not self-reported).
Promoted to `done` by the owner on 2026-09-02 after AC confirmation. Shipped as PR #172 (merged 12:08Z); PR #173 (merged 14:00Z) closed a gap found after that merge — a Subtasks row with no Status column printed a wrong number instead of omitting the field.
