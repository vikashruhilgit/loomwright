# 00 — Provider routing + configurable base branch (index — NOT an implementable item)

## Status: done (index document — nothing to implement; this stamp keeps `/automate --folder` from enqueuing it)

**Origin:** 2026-10-27, `/product-owner` session. Three owner asks, every premise read from `origin/main @ bd4be26`
(v17.18.2) the same day by two read-only inventories, then spot-checked by hand:

- **A — the base branch must be configurable** (`main`, `development`, anything). Today it is resolved in four
  unrelated ways and two of them disagree on any repo whose default branch is not `main`.
- **B — `/setup --help`.** Partly exists by accident (see 01 Part 7).
- **C — choose which AI CLI runs which pipeline step**, default all Claude, headless, configured through `/setup`.

**Re-read each item's "Verified premises" block before dispatch — `main` moves.**

## Why now

A is a live bug: any repo that integrates on a branch other than `main` gets item PRs against `main` while `/automate`
lanes, waves and trail PRs use origin/HEAD. C cannot be designed honestly until a real machine says which CLIs work
headless (D2′), so the probe is the first C step; B is a small usability gap in the `/setup` files 01 already edits.

## Checklist

- [ ] 01-base-branch-configurable.md (wave 1)
- [ ] 02-providers-probe.md (wave 1)
- [ ] 03-routing-config-readonly-seats.md (wave 2 — proposed, promote after 02's report)
- [ ] 04-routing-write-seats.md (wave 3 — proposed, promote after 03 ships)

## Owner decisions

- 2026-10-27: three waves. Script and prompt base-branch work merged into one item (01); the `/setup providers` screen
  moved from the probe into the routing item (03) so the probe touches no `/setup` file and runs beside 01.

## Order — three waves

| Wave | # | Item | Ready? | Why this position |
|---|---|---|---|---|
| 1 | 01 | Configurable base branch: resolver, every script and prompt consumer, `/setup base-branch`, `/setup --help` | ready | Live bug on non-`main` repos; independent of C |
| 1 | 02 | Provider probe script (check + report only) + Grok/Copilot table entries | ready | D2′: the second-harness probe comes first; shares no file with 01 |
| 2 | 03 | `/setup providers` + routing config + user-scoped egress grant + read-only seats | **proposed** | Premises come from 02's report; edits the `/setup` files 01 also edits |
| 3 | 04 | Write seats (worker, heal fix, drain fix) | **proposed** | Builds on 03's config and consent code |

Run wave 1: `/automate --folder .supervisor/requirements/provider-routing --parallel 2` — enqueues 01 and 02 only; 03/04
carry `## Status: proposed` (`is_not_ready`). Between waves: read 02's report, answer 03's open questions, rewrite 03's
premises, stamp it `pending`, run it; then the same for 04.

## Standing decisions (do not re-litigate)

- **D2′** (`loomwright/docs/SPIKES/FINAL_STATE_GOAL.md`): a runner that drives headless CLIs through a provider table is
  built only after a real second-harness probe, Grok Build first. 02 IS that probe.
- **The conductor stays Claude**: main session, supervisor-runner, execute-manager, context-keeper, the
  `/autonomous`/`/automate` loops, the detached drain runner process, and the `TaskCompleted` prompt hook are not
  routable seats.
- **Egress consent is user-scoped** (`~/.claude/loomwright/egress.json`, keyed by repo): a repo file may request a
  provider, never grant one — same rule as telemetry (red-team-hardening item 02).
- QA/verify (browser-driving) is not an item; 02's report carries one "browser-capable?" column. It becomes an item
  only if a provider answers yes.

## Considered and not queued

- One item per seat (six-item draft): split one mechanism into many designs — merged into 03 (read-only) and 04 (write).
- `/setup --help` as its own item: too small to pay a run's fixed cost; folded into 01 (same files).
- Base branch as two items (scripts, then prompts): forced a third wave-1/2 split; merged into 01.
- `--help` for every command: no command has it today; out of scope unless 02's mechanism turns out reusable for free.

## Revisit when

- 02's report lands → promote 03 (and re-verify its premises), then 04.
- A provider in 02 reports browser-capable → write a QA/verify routing item.
