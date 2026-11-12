# Design decisions — Launch Pad Phase 2.7 APPROACH protocol

Read on demand by Launch Pad Phase 2.7 only when a trigger fires: it records the chosen way, the ways it beat and the evidence, so "why not X?" is answered when the plan is made, not in review.

## Triggers (closed list)

Detect each from the named source only. No trigger ⇒ run `launch-pad-phase.sh 2.7 no trigger` (prints `## Phase 2.7: APPROACH — no trigger`) and emit no `## Design decisions` section.

| Trigger | Fires when | Detected from |
|---|---|---|
| `T1` | a new dependency is added | a Phase 2.5 check 1 or check 2 CAUTION row naming a dependency not yet in the manifest or lockfile |
| `T2` | a new script or module is created | a File Impact Map CREATE row that is a script or a module (not a test, fixture, doc or evidence file); re-checked after Phase 3 action 13, because the map does not exist at Phase 2.7 |
| `T3` | a new external integration | the goal or `## Task` names a service, API or SDK the project does not call yet |
| `T4` | a cross-cutting mechanism | the goal or `## Task` adds a mechanism many call sites share (retry, cache, auth, rate limiting, logging, queue, config layer) |
| `T5` | a hand-rolled platform feature | the goal or `## Task` builds something the manifest, the harness or a stackpack skill already provides |

Bug fixes, docs, prompt-only edits and small changes never trigger, even when they touch one of these areas.

## Candidates

List up to three candidates per trigger, in this order, and never skip the first:

1. **already in the repo** — an existing helper, module, script or a dependency already in the manifest or lockfile;
2. **provided by the platform** — the language runtime, the framework, the SDK, the harness or an installed stackpack skill;
3. **new** — a new dependency or new hand-written code.

## Axes

Rate every candidate on the five fixed axes, each `yes | partial | no`, with no weights:

- **fits the CLAUDE.md stack** — the language, framework and patterns CLAUDE.md names;
- **already in the lockfile or manifest** — nothing to add;
- **blast radius** — `yes` when the change stays inside the File Impact Map;
- **test cost** — `yes` when the existing test setup covers it with no new harness;
- **reversibility / lock-in** — `yes` when swapping it out later touches only its own call sites.

The candidate with the most `yes` is chosen; fewer `no` breaks a tie. Equal `yes` and `no` counts at the top are an **axes tie**.

## Evidence sources

Use only these three, cheapest first, and quote what each returned in `evidence:`:

1. **the repo** — Grep/Glob over the manifest, the lockfile, helpers, `scripts/` and an installed stackpack skills index;
2. **Context7** — library docs, within `skills/context7-lookup/SKILL.md`'s per-lookup token budget;
3. **`WebSearch`** — only under `--discovery`, and only where the tool is available (the `launch-pad-runner` agent disallows it, so it falls back to sources 1–2).

## Entry format

One entry per trigger, all six keys in this order:

```markdown
- decision: <what had to be chosen>
  chosen: <the way picked>
  rejected: <a way not picked> — <why, citing an axis>
  evidence: <the grep, doc or search result that decided it>
  revisit when: <the observable condition that would flip the choice>
  status: confirmed | unconfirmed
```

Repeat `rejected:` once per losing candidate; a T1 entry needs at least one. `status: confirmed` means the axes decided it with no tie, or the owner answered `Keep` or `Switch`; `status: unconfirmed` means `Decide later` or a run that could not ask.

## The `LP-APPROACH` ask

Asked only on an axes tie or a T1 dependency, once per such entry; every other entry is recorded with no question. Use the ask tool with `header: "LP-APPROACH"` and options `Keep <chosen>` · `Switch to <runner-up>` · `Decide later` (the runner-up is the candidate with the next most `yes`). `Switch to <runner-up>` swaps the two and records `status: confirmed`; `Decide later` keeps the default pick and records `status: unconfirmed`.

**Can't-ask branch** (Launch Pad Critical Rules' Can't-ask rule): record the default pick with `status: unconfirmed`. Never ask, and never abort the run for it; Plan Reviewer Criterion 23 turns a T1 `unconfirmed` entry into NEEDS_HUMAN.

## Assembly

Phase 2.7 prints `## Phase 2.7: APPROACH` with the entries it wrote; the T2 re-check after Phase 3 action 13 appends its entries. Phase 5 assembles every entry into ONE `## Design decisions` section between `## Task` and `## Acceptance Criteria`.

## After the brief

The entry binds the plan, not the worker's judgement: a worker's `plan:` deviation is the worker's channel for "I found a better way", read by the Phase 4.5 review lens. Nobody re-opens the entry mid-run.
