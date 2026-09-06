---
description: Turn the recorded churn ledger into candidate work items — a propose-only pass over floor.json that writes evidence-carrying requirement drafts to .supervisor/requirements/proposed/ for a human to promote or delete
---

> **Read-only on your work; writes only derived drafts.** `/propose` reads the projection the plugin already builds (`.supervisor/floor/floor.json`) and writes candidate requirement files to `.supervisor/requirements/proposed/` (gitignored). It touches no code, no agent, no state, no existing surface, and sends nothing anywhere. It **never queues, dispatches, ranks, scores, or merges** — `proposed/` is deliberately **not** an `/automate --folder` target.

# Command: /propose

## Purpose

The learning loop **records and never proposes.** Findings accumulate automatically — postmortem records, classified categories, per-entry flow stages — but nothing converts a trend into a piece of work. Every item this system has ever executed was typed by a human: `/automate`'s three intake sources (a prompt via `/product-owner`, `--folder`, `--backlog`) are all human-seeded.

Measured on this repo when the proposer was written: **109 `convention_mismatch` entries had produced 3 rules.** The recording was never the gap.

`/propose` is the invocation seam for that missing half. It is the *intake* side of a mill that invents its own work — and it stops at intake by design. **It proposes; the human decides at dequeue.**

## Usage

```bash
/propose                                    # read floor.json, write candidates to .supervisor/requirements/proposed/
```

The command shells out to the tested implementation:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/propose-work.sh"
```

## Parameters

`/propose` takes no flags. Its behaviour is tuned by environment variables read by `propose-work.sh`, all optional:

| Variable | Default | Description |
|----------|---------|-------------|
| `PROPOSE_FLOOR_JSON` | `.supervisor/floor/floor.json` | The basis to read. The **only** ledger surface consulted — it is not a second parser. |
| `PROPOSE_OUT_DIR` | `.supervisor/requirements/proposed` | Where candidates are written. The only place any file is written. |
| `PROPOSE_REQUIREMENTS_DIR` | `.supervisor/requirements` | Root scanned for `## Status: done` files that supersede a candidate. |
| `PROPOSE_THRESHOLD` | `10` | Entries a `(class, flow_stage)` pair needs before it is emitted. A non-numeric value is ignored with a named reason. |
| `PROPOSE_MAX_AGE_SECONDS` | `86400` (24h) | Staleness limit on the basis. Older ⇒ propose nothing, name the age, exit 0. |
| `PROPOSE_SOURCE_DATE_EPOCH` | *(now)* | Pin the staleness "now" for reproducible runs. |

## What This Does

1. **Refuses to propose from a stale or unreadable basis.** A missing `jq`, a missing / unparseable `floor.json`, an unreadable clock, or a basis older than the staleness threshold each **skip with a named reason and exit 0**. Skipping is the correct behaviour for an advisory reader; proposing from a stale basis is the exact failure this system keeps writing rules about.
2. **Threshold, never ranking.** A candidate is emitted when a `(class, flow_stage)` pair crosses the stated count. There is **no score, no rank, no priority, no top-N, no ordering field** — a view that ranks becomes a view that decides, and deciding is the human's half of this loop.
3. **Cites its evidence or stays silent.** Every candidate carries a mandatory `## Evidence` section naming each ledger entry it rests on (`class`, `flow_stage`, `round`, source `line`, `self_heal_miss`) plus the `generated_at_epoch` it read. **A candidate that cannot cite at least 3 distinct entries is not written.** Absent evidence is omitted, never defaulted — a fabricated count inside a proposal is precisely what this reduces.
4. **Suppresses what is already covered**, reporting each suppression with its basis so a silent suppression is never mistaken for "nothing to propose".
5. **Writes a directory contract.** `proposed/README.md` states that the directory is not an `/automate --folder` target and that promotion is a human moving a file out of it.

## Promoting or dismissing a candidate

- **Promote:** move the file out of `proposed/` into a real queue folder, then run it (`/automate --folder <dir>`, `/autonomous --requirement <path>`, or `/launch-pad`). Nothing is enqueued until you do.
- **Dismiss durably — deleting a file here is not a durable dismissal.** Deleting a proposal only silences it **until the next run**, which recomputes the same evidence set and writes the same file again — the cited coordinates are the earliest entries for the pair, so the `evidence-set:` token is stable as the ledger grows. To dismiss permanently, paste the candidate's `evidence-set:` line into a requirement file stamped `## Status: done` anywhere under `.supervisor/requirements/`. The next run finds that token and suppresses the candidate, naming the file it found it in.

## Notes

- **Determinism.** Two runs against an unchanged basis produce byte-identical proposal content — no run timestamps, no `$RANDOM`, no hash-order iteration.
- **Fail-safe.** `set -uo pipefail` with no `set -e`, a `jq` guard that skips rather than fails, and `exit 0` always. An advisory reader must never break its caller.
- **Refresh the basis first** if it has gone stale: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/build-floor.sh"`. `/propose` deliberately does **not** regenerate the projection itself.

## See Also

- `loomwright/scripts/propose-work.sh` — the implementation, guarded by `loomwright/scripts/test-propose-work.sh`.
- `/insights` — the run scoreboard over the same session logs.
- `/automate` — the engine that walks a *human-promoted* queue to reviewed PRs.
