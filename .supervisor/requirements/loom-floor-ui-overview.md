# The Loom Floor — a UI for Loomwright · overview (2026-09-01)

Master overview for the 5 work items in `.supervisor/requirements/loom-floor-ui/`.

**This file is the overview only — do NOT feed it to `/automate`.** It lives as a sibling
of the folder, not inside it, precisely so `--folder` never enqueues it (the folder source
enqueues *every* `.md` in the directory). The per-item requirement files are each
self-contained.

Research record: the published artefact **"The Loom Floor"** (2026-09-01) — carries the
measurements below plus a working animated mock of the item-04 layout. The mock is driven
by a timer; it is a design proposal, not a screenshot.

## The finding that shapes the whole plan

**Rendering was never the blocker. The event schema is.**

Everything needed for *what shipped* and *what's queued* is already on disk and readable
with no plugin change at all. What is missing is the ability to say **who is working right
now** — and it is missing for one specific reason: every progress event in Loomwright comes
from a `SubagentStop` hook, and there is no spawn-side hook. Verified 2026-09-01:
`hooks.json` has no `"Task"` matcher across any of its 24 entries.

The log records deaths, not lives.

Measured on the live log `.supervisor/logs/8d43da72-…jsonl` the same day:

| Measurement | Value | Meaning |
|---|---|---|
| `subtask_complete` events | 3,641 | Against **4** real subtasks in `state.md` — it is "a subagent stopped", not "a subtask completed" |
| Distinct `agent_id` | 559 | Agents *are* individually addressable |
| Fields per event | 7 | No `agent_type`, no title, no status — nothing can name or colour the agent |
| Agents with a `color:` | 14 of 14 | The visual identity already exists in frontmatter |
| Rows in the "Color Legend (Status Line)" table | 12 | Two agents stale — `review-pr-runner`, `rubric-grader` |
| HTML/CSS/JS files in the repo | 0 | No visual surface of any kind today |

## One research claim was wrong — recorded so it is not re-derived

Initial research concluded that a session log accumulates unboundedly (35 days, 6+ branches
in one file) because its join key is `state.md`'s `status:`, stuck at `running` since
2026-07-29 — and that a rotating key was therefore needed.

**That conclusion was wrong.** Re-measured on the same file: `cc_session_id` is present on
**100%** of its 10,271 lines and segments cleanly into **116** sessions with coherent time
spans. The file *name* is stale; the *data* is already segmented. A reader groups by that
field and needs no emitter change.

Consequence: item 01 shrank to the genuine gap (the spawn event), and item 03 does the
grouping. Both files carry this correction so the wrong version is not rediscovered.

## Execution order & batching

| # | File | Priority | Size | Depends on |
|---|------|----------|------|-----------|
| 01 | `01-agent-spawn-event.md` | P0 | M | — |
| 02 | `02-status-line.md` | P1 | S | **01 merged** (active-agent count only; ships without that field on a 01 NO-GO) |
| 03 | `03-floor-projector.md` | P1 | M | — (soft on 01: omits spawn fields if absent) |
| 04 | `04-the-floor-ui.md` | P1 | L | **03 merged** (hard) |
| 05 | `05-archive-views.md` | P2 | M | **03 merged** (hard); independent of 01/02/04 |

**Sequencing rule:** 01 before 02 is the only hard model-facing ordering, and it exists for
a reason worth stating — 02 is the cheapest possible proof that 01's spawn↔stop pairing
actually works. If the active-agent count is wrong there, it is wrong in 04 too, and 02
costs hours to find that out where 04 costs a week.

Suggested batches:
- **Batch A:** `01` alone. Run it, read the outcome, decide. Do not queue past it blind.
- **Batch B:** `02` and `03` (independent of each other, both cheap).
- **Batch C:** `04`, then `05` — or `05` first if a browsable archive is worth more to you
  than a live view.

## 01 can legitimately return NO-GO — that is a pass, not a failure

Item 01's first task is to **capture a real `PreToolUse[Task]` payload from a live run** and
commit it as a fixture, before any emitter is written. This is not ceremony. This repo's own
history records that the real `SubagentStop` payload carries `last_assistant_message` +
`agent_transcript_path` and **no** `result_block`, contrary to what was assumed at design
time — see the header of `loomwright/scripts/emit-progress-event.sh`.

I did **not** run the plugin to observe a live spawn payload. The claim that
`PreToolUse[Task]` fires per subagent spawn with a joinable id is drawn from the hook's
documented contract, not from an observed payload. If it does not hold, 01 closes as NO-GO
with the captured evidence and 02–05 are re-scoped against what the payload actually offers
(worst case: `WorktreeCreate`, already logged to `.supervisor/logs/worktrees.log`, gives
worker-lifecycle liveness only).

**Run batch A before committing to batches B and C.**

## What each item actually buys

| Item | Nature | Guaranteed win | Conditional / later win |
|---|---|---|---|
| 01 | New fail-safe emitter | A known, evidence-backed spawn payload — even a NO-GO is a real answer | Spawn↔stop pairing, and everything live downstream, only if the payload holds |
| 02 | One-line surface + derived legend | The legend can no longer drift; the 2026-09-01 drift is closed mechanically | Live agent count, only if 01 went GO |
| 03 | Projector | One reader, one schema; nine surfaces stop being parsed nine ways | Every view after it becomes cheap |
| 04 | Static local view | Live run state visible; a stall visible without being looked for | — |
| 05 | Archive views | 85 ledger lines and 487 drain rounds become answerable questions | — |

## Standing constraints (every item)

- **Read-only on state.** `build-state.sh` is the sole writer of `state.md`'s `## Session`
  block. New scripts write only their own files, in their own directories.
- **Fail safe, always exit 0.** These are runtime side-effect emitters and reporters under
  the bimodal invariant, never gates. An unreadable input reports **unverified** — never
  "clean".
- **Worktree-safe anchoring.** Never `$PWD`, never `git branch --show-current` — the latter
  returns empty inside the detached drain worktrees this repo actually creates.
- **Local only.** No network egress. Loopback binding only for anything served.
- **No new runtime dependency.** `jq` and `python3` are already hard dependencies; nothing
  else may be added — no Node, no bundler, no CDN.
- **Release-surface lockstep.** A new hook takes 24 → 25 and a new command 21 → 22 across
  `plugin.json`, `marketplace.json`, README and CLAUDE.md, in the **same** commit;
  `check-doc-currency.sh` fails CI otherwise. A new agent additionally needs a token-budget
  entry. Measure `check-vendor-coupling.sh` before and after and report the delta whatever
  it is.
- **Every new mechanism is mutation-verified** — reverting it must fail exactly its own
  cases, and a check must be proven to have *executed*, not merely be reachable.

## Adjacent work — deliberately not done here

`.supervisor/requirements/twin-remediation/08-session-segmentation.md` covers fresh-context-
per-unit-of-work. It is about **token cost**; these items are about **event shape and
visibility**. They touch the same log and must not absorb each other's scope. 08 is
unstamped and unscheduled; nothing here depends on it.

The advisory-surface freeze declared in `twin-remediation/00-overview.md` is **lifted** —
items 01 and 02 there are both stamped `## Status: done`. These items would have been exempt
regardless, being consumers of existing signals.

## How to run this

```
/automate --folder .supervisor/requirements/loom-floor-ui --limit 1
```

`--limit 1` for batch A deliberately: read 01's outcome before queueing anything behind it.
Directory order is processing order, so the numeric prefixes give the intended sequence.
