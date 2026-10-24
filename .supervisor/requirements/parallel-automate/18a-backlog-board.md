# 18a — One backlog board: every requirement item's real state, derived, never hand-kept (`/backlog`)

## Status: pending

## Split from
`parallel-automate/18-backlog-board-and-right-size.md` Part A, split 2026-10-22 by the owner (/product-owner
session, re-verified read-only against main 7b7cb08 / v17.14.1). The board's feeds (Floor surface, `BACKLOG.md` at
meta push, the SessionStart nudge) moved to `25-backlog-board-feeds.md` to keep this item inside one PR. Part A's
text is carried VERBATIM under `## Source text`; where it and this header differ, this header wins.

## Problem
Requirement files' `## Status:` lines and `_BACKLOG.md` checkboxes are not updated on merge. Measured 2026-10-22:
of 271 requirement items, 224 had shipped, yet most still read `## Status: pending` (all 24 automate-speed items
merged; their `_BACKLOG.md` showed 0/24 checked). Answering "what is pending" took a hand cross-check of run files,
`git log` and merged PRs.

## Goal
One read-only `/backlog` command that prints every requirement item's real state from evidence, never from a
hand-kept label, with a right-size column.

## Scope
Source text Part A items A1, A2, A4, A5 and A6, with these 2026-10-22 corrections. A3 (feeds) is item 25.
1. **A1 one reader** `automate-helpers.sh item-state <item>` covering every state (`done`, `in_flight`, `pr_open`,
   `merged_unstamped`, `parked`, `unknown`, `conflict`, `stale_run`); the item's own stamp beats a run file's
   `## Current` (the run reads `stale_run`). Evidence order, reused from the 2026-10-22 sweep: a run file's
   `- [x] <path>` or `fleet closeout: … <path> done`, then a merged PR whose branch or title names the item, then
   the item's own stamp. `is_done()` already matches an appended stamp — reuse it. `parked (merged … into X)` and
   `parked (split … into X)` read X's state.
2. **A1 conflict guard:** `_rs_process_abandoned` in `automate-helpers.d/reconcile-status.sh` must not stamp
   ABANDONED over an item whose state is `conflict`; tested on a fixture.
3. **A2 the board:** `commands/backlog.md` → table + `--json` + `--state <s>` + totals that add up; the right-size
   column calls 18b's `right-size` (same pass, no second scan).
4. **A4** `--unknown` hygiene list. **A5** `--verify`: since #517, `reconcile-status` already promotes a
   `brief-shipped` item that has merged-PR evidence, so `--verify` covers only items with no evidence, lists them
   for the owner, and stamps only what the owner approves.
5. Stale premise in the Source text: lanes are read through `lane-status --json`
   (`automate-lanes.d/status-read.sh`), not lane clones.
6. A new command: register it in `agent-help`, give it a `prompt-token-budgets.json` entry plus its mirror row, and
   let `check-doc-currency.sh` drive the count surfaces. Prefer removing a restated count over editing it (house
   rule: a count lives in one authoritative place).

## Non-goals
Floor surface, `BACKLOG.md`, SessionStart nudge (item 25). Writing any status stamp without the owner's per-item
approval. Reading GitHub for anything but merged-PR evidence.

## Owner decisions (from _BACKLOG.md)
- 2026-10-22: the board is a new `/backlog` command, not an `/automate --board` flag.
- Open, for Launch Pad to ask: when an item is `conflict` (which dates win between an `# abandoned:` row and a later
  stamp), and how the owner settles one.

## Acceptance criteria
- Every Part A acceptance criterion in the Source text holds, with the 2026-10-09-snapshot checks rewritten as
  hermetic fixtures (a test never reads the live backlog).
- Given a fixture tree with an item stamped `pending` whose path is checked `- [x]` in a run file, then
  `/backlog` reads it `merged_unstamped`, never `pending`.
- Given an item `parked (merged … into X)` with X done, then it reads `done` and names X.
- Given `--json`, then totals per state sum to the item count.
- `reconcile-status --apply` leaves a `conflict` item unstamped (fixture).
- `bash scripts/check-version-bump.sh` passes with the `changelog.d/pa18a-backlog-board.md` fragment.

## Validation (must pass before merge)
1. Targeted tests: `test-automate-helpers.d/18-backlog.sh`, `10-reconcile-status.sh`, the help-golden check,
   `check-doc-currency.sh`, `test-citation-drift.sh`, `check-token-budget.sh`. Full `ci-local` on GitHub CI.
2. Running system: `/backlog --json` on this repo's live requirements, read-only; paste the state totals and five
   sample rows into the PR body, with the PR or run-file line behind each `done`.
3. Rollback: `git revert`.

## Depends on
18b-right-size-check.md

## Touches
loomwright/scripts/automate-helpers.d/backlog.sh
loomwright/scripts/automate-helpers.sh
loomwright/scripts/fixtures/automate-helpers-help/backlog.golden
loomwright/scripts/fixtures/backlog-state/
loomwright/scripts/test-automate-helpers.d/18-backlog.sh
loomwright/scripts/automate-helpers.d/reconcile-status.sh
loomwright/scripts/test-automate-helpers.d/10-reconcile-status.sh
loomwright/skills/automate-loop/helpers.md
loomwright/commands/backlog.md
loomwright/commands/agent-help.md
loomwright/docs/command-parts/agent-help/ops.md
loomwright/docs/prompt-token-budgets.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/.claude-plugin/plugin.json
.claude-plugin/marketplace.json
README.md
CLAUDE.md
changelog.d/pa18a-backlog-board.md

## Source text (verbatim from 18 Part A — superseded where the header above differs)

### Part A — 15 — One backlog board: every requirement item's real state, derived, never hand-kept

#### Problem
Owner (2026-10-05): "this lane stuff picking stuff randomly — how can we keep track of all the tasks which are done,
pending and all, we need a good way to keep track of all those". (Lanes do not pick at random: the operator picks a wave
from `plan-waves`, and each lane gets exactly one item through its backlog file. But nothing shows that, or the rest.)

Today the state of the backlog is spread across five places, and no reader combines them:
- **Item files** under `.supervisor/requirements/<folder>/NN-*.md`: the first `## Status:` line, plus a done stamp that
  closeout APPENDS at the end (`<!-- loomwright:requirement-closeout -->` / `## Status: done`). So the first line can say
  `pending` while the item is done; on 2026-10-04 the operator counted 39 "pending" items by first line, when 26 were
  really open.
- **Run files** (`.supervisor/automate/*.md`): which item is in flight, parked or awaiting merge; one per run, and lanes
  add one per lane.
- **Lane clones** (outside the repo): which item each live lane is working on.
- **GitHub:** open PR, checks, merged commit.
- **Prose records** (S1/S2 run records, overviews): decisions, waves, why something was skipped.

A one-off board built from the files on 2026-10-05 read **97 done · 59 open · 5 in a lane · 5 parked · 1 proposed**. The
37 open items counted by explicit `pending|ready|parked` lines the day before differ from those 59 by ~22 items with **no
`## Status:` line or a non-standard one** (mostly `final-state/`, `twin-loop/`, `twin-remediation/`). Some may be done,
superseded or abandoned with no stamp. There is no single honest answer to "what is left?"

The Floor (`build-floor.sh` → `floor.json`) already projects 14 `.supervisor/` surfaces, but not requirement items.

#### Goal
One command and one view answer, for every requirement item: is it done, in flight (where: lane / run / PR), parked,
blocked, open-and-ready (in which wave), or unknown (and why). All of it derived from the existing sources on every run,
never a hand-maintained list, and the counts always add up.

#### Scope
1. **One canonical status reader** (`automate-helpers.sh item-state <item>` or a small `backlog-state.sh`), used by every
   consumer instead of ad-hoc greps: `done` (done or done_with_escalation stamp anywhere), `abandoned`, `parked`,
   `proposed`, `in_flight` (named by a non-done run file's `## Current`, or by a live lane's backlog), `pr_open` (a run or
   lane names a PR that `gh` reports open, with its checks), `merged_unstamped` (PR merged but no done stamp: needs
   closeout), `open` (explicit `pending`/`ready`), and **`unknown`** (no status line or a value outside the enum, reported
   with the offending line). Never guess: `unknown` is a first-class state that the board shows, not folds into `open`.
   **Amended 2026-10-09 — when sources disagree:**
   - **The item's own stamp beats a run file's `## Current`.** An item stamped `done`, `parked` or `abandoned` never
     reads `in_flight` because an unfinished run still names it. That run is listed instead under **Runs needing
     attention** as `stale_run`, with the reason (its `## Current` item is done / parked / abandoned, or the run file
     is self-inconsistent, e.g. `## Status: paused` with `pause_reason: null`). Suggest-only: the board names the fix
     (`resume-glob --finalize`, `closeout`, or automate-followups/34's janitor) and edits nothing.
   - **An item that an old run marked `# abandoned:` / `# skipped:` but whose own file still says `pending` / `ready`
     reads `conflict`**, a first-class state like `unknown`, shown with both sources and their dates. Never picked
     silently, and `reconcile-status --apply` must not stamp `ABANDONED` over a `conflict` item without the owner.
2. **`/backlog` (or `/automate --board`)**: a table grouped by folder: item, state, wave (from `plan-waves`), lane/run, PR
   and checks, merged commit, last change. `--json` for other views. `--state open|unknown|in_flight|…` filters. Totals that
   add up to the number of item files, with each state counted once.
3. **Feeds the existing views, not a new UI:** a `backlog` surface in `floor.json` (the Floor shows it), a `BACKLOG.md`
   regenerated on the metadata branch at each `meta-sync push` (readable on GitHub), and `lane-status` (item 05) pointing
   at it. The pane add-on (item 14) can render it.
4. **Hygiene, owner-gated:** `--unknown` lists every item with no or a bad status line, with a suggested fix
   (stamp done with the PR that shipped it, mark abandoned, or add `## Status: pending`). It suggests only; the owner
   applies, or `reconcile-status --apply` does where it has PR evidence.
5. **Root fix for `brief-shipped` (owner 2026-10-05: "verify-and-stamp flow"; keeps queue-hygiene/01's "never
   auto-promote" — a landed brief proves the work ran, not that its acceptance criteria were met, and the 2026-10-05
   validation found 2 of 21 `brief-shipped` items only partial):**
   - **Nudge:** at SessionStart (`session-resume.sh`, fail-safe, one line, at most once a day) when any `brief-shipped` item
     has a merged PR: "N shipped items await verification — `/backlog --verify`".
   - **`/backlog --verify [item…]`:** for each `brief-shipped` (or named) item, read-only: read its acceptance criteria,
     check each against `main` (named files / functions / flags / docs exist and behave as stated), find its merged PR(s),
     and propose `done` / `done_with_escalation` (with what is owed) / still `pending` (partial, what is missing) /
     `ABANDONED` (superseded, by what) — with evidence per item. **Stamps only what the owner approves**, in the engine's
     shapes (`<!-- loomwright:requirement-closeout -->` + `## Status: …` + `- **Completed:**` + one `- **PR:**` line per PR;
     ABANDONED as `## Status: done_with_escalation — ABANDONED (reason)`), then pushes via meta-sync with `--branch`.
     This mechanizes exactly the 2026-10-05 manual pass (4 read-only research agents + owner approval).
6. **Tests:** the reader on fixtures for every state (including first-line `pending` plus an appended done stamp ⇒ `done`;
   a missing status ⇒ `unknown`; a lane backlog naming the item ⇒ `in_flight`); totals add up; `--json` round-trips;
   `gh` unavailable ⇒ PR fields `unverified`, never silently `open`; a parked item named by an unfinished run's
   `## Current` ⇒ `parked`, and that run listed as `stale_run`; a `pending` item with an older run's `# abandoned:` row
   ⇒ `conflict`.

#### Non-goals
- No new state store and no manual board: every value is recomputed from the sources.
- No automatic status edits outside `reconcile-status`'s existing evidence rule.

#### Acceptance criteria
- On the real backlog, `/backlog` totals equal the number of item files, and every item counted as `open` has an explicit
  `pending`/`ready` line; the ~22 status-less items appear as `unknown` with the reason.
- During a lane wave, each lane's item shows `in_flight` with its lane name, and after merge plus closeout `done` with the PR.
- On the backlog as it stood on 2026-10-09: `implementation-quality/01` shows `parked` (not `in_flight`), run
  `automate-2026-10-09-053232` is listed as `stale_run`, and `review-remediation/10`, `token-economy/06`,
  `twin-remediation/03` and `twin-remediation/06` show `conflict`.

#### Validation (must pass before merge)
1. Baseline full loop, `<passed>/<total>` and `SKIP` counts, base and branch.
2. Unchanged path: `reconcile-status`, `resolve-folder` and `plan-waves` outputs unchanged on existing fixtures.
3. Running system: paste `/backlog` totals and the `unknown` list over this repo's real backlog.
4. A failure this must catch: read only the first `## Status:` line ⇒ the appended-done-stamp fixture fails.
5. Rollback: `git revert`.

#### Root cause found 2026-10-05 (why 21 items sat at `brief-shipped`)
`loomwright/scripts/stamp-requirement-status.sh` (runs at every SessionStart) stamps `## Status: brief-shipped` when a
brief lands in `.supervisor/jobs/done/`: by design it records only what it can prove (the work ran), never `done`. **Nothing
ever upgrades `brief-shipped` to `done`**, so every requirement that went through it stayed "open" to every reader. A
read-only validation of the 32 status-less / `brief-shipped` items on 2026-10-05 found 19 done, 2 done-with-escalation, 5
abandoned/superseded, 1 parked and only 5 still open (+1 partial); the owner approved the stamps. Scope addition:
`brief-shipped` is a first-class board state ("shipped, not verified"), and `/backlog --unknown` lists every
`brief-shipped` item with its merged PR, so the owner can verify-and-stamp in one pass instead of it rotting silently.

#### Evidence
The 2026-10-05 one-off board (this session); the 39-vs-26 miscount (S1/S2 records, `parallel-automate/10` Verified premises).


<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-24T20:58:27Z
- **Brief:** .supervisor/jobs/done/2026-10-24-pa18a-backlog-board.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/690
