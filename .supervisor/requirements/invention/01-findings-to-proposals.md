# 01 — The loop proposes: findings become candidate work items

## Problem

The learning loop records and never proposes. Findings accumulate automatically; nothing
converts a trend into a piece of work. Every item this system has ever executed was typed
by a human: `/automate`'s intake is a prompt (via `/product-owner`), `--folder`, or
`--backlog`, and all three are human-seeded.

Measured on this checkout, 2026-09-06:

| Fact | Value | Source |
|---|---|---|
| Postmortem records | **92** | `.supervisor/floor/floor.json` → `surfaces.postmortem.count` |
| Classified category entries | **233** | same → `detail.categories_total` |
| `convention_mismatch` | **107** | same → `detail.class_distribution` |
| …of which self-heal **misses** | **60** | `detail.entries[]` grouped by `class` + `self_heal_miss` |
| …originating at the **worker** stage | **29** | same, filtered `flow_stage == "worker"` |
| Next-largest classes | quality_gap 46 (17 misses) · execution_bug 36 (11) · drain_churn 34 (6) | same |
| Rules actually distilled from all of it | **3**, across 2 files | `.agent/rules/documentation.json` (1), `process.json` (2) |
| Drain-round files / worker summaries | **591** / **120** | `surfaces.drain_rounds`, `surfaces.worker_summaries` |

107 recorded convention mismatches have produced 3 rules. The recording is not the gap.

**What changed since this was last considered, and why it makes the item small:** item 03 of
the floor-UI queue shipped `build-floor.sh`, and item 05 added the rules and churn detail
surfaces. `floor.json` now carries the postmortem ledger **pre-aggregated** — class
distribution, per-entry `flow_stage`, `round`, `self_heal_miss`, and a free-text `evidence`
string — plus a `rules` surface whose `correlations` already ship with the disclaimer that a
path overlap is an observation and not proof of violation. A proposer therefore parses
**one file**, not the nine raw surfaces. This item would have been a projector plus a
proposer; the projector already exists.

## Goal

A proposer that reads `floor.json` and writes candidate requirement files into
`.supervisor/requirements/proposed/`, each carrying the ledger evidence it was derived from,
for a human to promote or delete. It proposes; it never queues.

## Scope

1. **`propose-work.sh`** — jq-based, deterministic, reading **only**
   `.supervisor/floor/floor.json` and writing **only** under
   `.supervisor/requirements/proposed/`. Mirror `build-floor.sh`'s discipline exactly:
   `set -uo pipefail` with no `set -e`, a `command -v jq` guard that skips rather than
   fails, and **exit 0 always**. It is an advisory reader; it must never break its caller.

2. **One proposal = one `.md` in the shape `/automate --folder` already consumes** —
   Problem / Goal / Scope / Acceptance criteria — **plus a mandatory `## Evidence`
   section** naming every ledger entry it rests on (`class`, `flow_stage`, `round`, source
   `line`, and the `evidence` string) and the `floor.json` `generated_at_epoch` it read.
   **A candidate that cannot cite at least three distinct ledger entries is not written.**
   The proposal states the pattern it observed and what it would change; it does not state
   a fix it has not verified.

3. **Threshold, never ranking.** A candidate is emitted when a `(class, flow_stage)` pair
   crosses a stated, configurable count. There is no score, no rank, no "top N", no
   priority field. This inherits item 05's non-goal verbatim and for the same reason: a
   view that ranks becomes a view that decides, and deciding is the human's half of this
   loop.

4. **Dedup and supersession.** A candidate whose evidence set is already covered by a file
   in `proposed/`, or by any requirement file under `.supervisor/requirements/` carrying
   `## Status: done`, is suppressed. Each run reports what it suppressed and on what basis,
   so a silent suppression can never be mistaken for "nothing to propose".

5. **Refuses to propose from stale evidence.** `floor.json` records its own
   `generated_at_epoch` and per-input mtimes. If it is older than a stated threshold, the
   script names the age and **skips** — it does not regenerate the projection itself, and it
   does not propose anyway. Skipping and exiting 0 is the correct behaviour for an advisory
   reader; proposing from a stale basis is the exact failure this system keeps writing
   rules about.

6. **The human gate sits at dequeue, not at write.** `proposed/` is deliberately **not** an
   `/automate --folder` target. Promotion is a human moving a file out of `proposed/` into
   a real queue folder. Nothing in this item may enqueue, dispatch, or start anything, and
   the directory's own `README.md` states that contract so a future session cannot mistake
   `proposed/` for a backlog.

7. **Absent evidence is absent.** Adopt `build-floor.sh`'s rule verbatim: a field with no
   basis is omitted, never defaulted. A proposal must never contain a fabricated count.

## Non-goals

- **No new agent** (so no `prompt-token-budgets.json` entry) and **no new hook** (so the
  hook count is unchanged). If either turns out to be genuinely needed, every doc surface
  bumps in the same commit or `check-doc-currency.sh` fails CI.
- **No new store, ledger, or emitter.** Every input already exists.
- **No writes to any existing surface** — not `.agent/`, not `.supervisor/postmortem/`,
  not `state.md`, not the floor. One new directory, nothing else.
- **No auto-queue, no auto-dispatch, no auto-merge.** Not now, not behind a flag.
- **No ranking, scoring, or prioritisation of proposals.**
- **No network.** Nothing leaves the machine.
- **Not a second parser.** If a needed field is missing from `floor.json`, the fix is to add
  it to the projector in a separate change — never to read a raw surface here.

## Depends on

Nothing hard. `build-floor.sh` and the postmortem/rules detail surfaces are shipped and
present in this checkout (`schema_version: 1`).

## Release-surface obligations

- A script-only change leaves agent/command/skill/hook counts unchanged. **Measure the
  vendor-coupling ratchet before and after and report the delta whatever it is**; if it
  moves, classify the new file explicitly with allowances regenerated via
  `--print-allowances`, never hand-typed.
- `.supervisor/` is gitignored (`.gitignore:78` [pins: `.supervisor/*`]), so proposals are
  machine-local by construction — the same posture as every other requirement file here.
  Do not add a negation to commit them.

## Acceptance criteria

- [ ] Given this repo's real `floor.json`, the script produces at least one proposal for
      the `convention_mismatch` class, and every count quoted inside that proposal is
      independently recomputed from `floor.json` and matches.
- [ ] Every emitted proposal carries a `## Evidence` section citing ≥3 distinct ledger
      entries plus the `generated_at_epoch` it read — asserted by parsing the emitted file,
      not by reading the script.
- [ ] Given a synthetic `floor.json` where a class has fewer entries than the threshold, no
      proposal is emitted for it and the run says so by name.
- [ ] Given a `proposed/` already containing a file covering the same evidence set, the
      second run emits nothing new and reports the suppression with its basis.
- [ ] Given a `floor.json` older than the staleness threshold, the script proposes nothing,
      names the age, and exits 0.
- [ ] Given `jq` absent, a missing `floor.json`, and a malformed `floor.json` (three
      separate cases), the script skips with a named reason and exits 0 in each.
- [ ] Running twice against an unchanged `floor.json` produces byte-identical output.
- [ ] No file outside `.supervisor/requirements/proposed/` is created or modified —
      asserted by hashing the tree before and after, not by reading the code.
- [ ] No emitted proposal contains a score, rank, priority, or ordering field — asserted by
      grepping the emitted files.

## Outcomes Rubric

- The loop proposes its own work for the first time, and every proposal shows its evidence.
- Nothing is ranked, scored, or queued; the human decides at dequeue.
- A stale or unreadable basis yields silence with a named reason, never a plausible-looking
  proposal.
- One reader, one input file; no raw surface is parsed a second time.
- Byte-identical on re-run; provably writes nothing else.

## Status: done
