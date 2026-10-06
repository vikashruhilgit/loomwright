# 18 — One backlog board with a right-size column: every item's real state, its size verdict and merge candidates

## Status: pending

## Merged from (2026-10-06, owner decision: both scan every requirement item and report on it — one run and one wave fewer)
- Part A: `15-backlog-board.md` — 15 — One backlog board: every requirement item's real state, derived, never hand-kept
- Part B: `17-right-size-check-and-merge-items.md` — 17 — Right-size check: flag items too small to pay a full run, name what to merge them into, and merge them mechanically

The originals are parked with a pointer here. Their text is kept below VERBATIM as parts (headings
demoted, their Status / Depends on / Touches folded into this file's own sections). Nothing was paraphrased.

## Depends on
04-wave-planner.md
10-touches-backfill-lint-and-explain.md

## Touches
loomwright/scripts/automate-helpers.sh
loomwright/scripts/test-automate-helpers.sh
loomwright/scripts/build-floor.sh
loomwright/scripts/session-resume.sh
loomwright/scripts/test-session-resume.sh
loomwright/scripts/test-build-floor.sh
loomwright/scripts/meta-sync.sh
loomwright/scripts/test-meta-sync.sh
loomwright/commands/backlog.md
loomwright/commands/agent-help.md
loomwright/skills/automate-loop/SKILL.md
loomwright/docs/RESULT_SCHEMAS.md
loomwright/scripts/automate-dismissed.sh
loomwright/scripts/propose-common.sh
loomwright/skills/user-story-writing/SKILL.md
loomwright/agents/product-owner.md
loomwright/commands/product-owner.md
changelog.d/parallel-automate-18-backlog-board-and-right-size.md

## Goal
One derived board of every requirement item (A), where the right-size verdict and merge candidates are a column on that board, while the writing-time and intake-time size line and the `merge-items` helper stay as part B specifies (B).

## How the parts join (owner decision 2026-10-06 — the only scope beyond the two parts)
- Part B's right-size verdict and its merge candidates are a **column on Part A's board** (table and JSON), read from
  the same canonical status reader pass, not a second scan of the requirements.
- Part B's writing-time and intake-time line (the size signal at product-owner writing and at `/automate` intake)
  stays as Part B specifies, and so does the `automate-helpers.sh merge-items` helper.

## Acceptance criteria
- Every part's own acceptance criteria hold, on one branch and one PR.

## Validation (must pass before merge)
1. Baseline full loop once for the merged branch, `<passed>/<total>` and `SKIP` counts, base and branch.
2. Every part's own Validation steps, labelled by part in the PR body. A part with no Validation section is
   checked by running its acceptance criteria, and the PR body says so.
3. Any "Running system" step a part names is run, or listed under "Not verified" with the reason.
4. Rollback: `git revert`.

## Parts

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
   `gh` unavailable ⇒ PR fields `unverified`, never silently `open`.

#### Non-goals
- No new state store and no manual board: every value is recomputed from the sources.
- No automatic status edits outside `reconcile-status`'s existing evidence rule.

#### Acceptance criteria
- On the real backlog, `/backlog` totals equal the number of item files, and every item counted as `open` has an explicit
  `pending`/`ready` line; the ~22 status-less items appear as `unknown` with the reason.
- During a lane wave, each lane's item shows `in_flight` with its lane name, and after merge plus closeout `done` with the PR.

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

### Part B — 17 — Right-size check: flag items too small to pay a full run, name what to merge them into, and merge them mechanically

#### Problem
Every requirement item that `/automate` runs pays a fixed cost whatever its size: Launch Pad, Plan Review, Supervisor,
Phase 4.5 review, the owned drain, CI and `claude-review` on every push, and the owner's gate questions. S2's five lanes
(2026-10-05, lane logs archived under `~/Documents/work/AI/ai-agent-manager-lanes-v2/archive/s2-*`; the logged
`total_cost_usd` is cumulative per session, so each session's final value is counted once):

| Lane | Item size | ~Cost | Owner questions |
|---|---|---|---|
| s2-c | small fix (`automate-followups/24`) | ~$17 | 4 |
| s2-e | tests only (`meta-sync-followups/01`) | ~$19 | 5 |
| s2-d | medium (`automate-followups/26`) | ~$26 | 6 |
| s2-b | medium (`automate-followups/16`) | ~$36 | 6 |
| s2-a | large (`agnostic-phase1/01`) | ~$40 | 8 |

Plus roughly 2–4 h wall-clock and ~25 min per `claude-review` round each. The floor (~$17–20 and four or more owner
questions) is paid even by a one-file change.

Nothing in the plugin looks at this when an item is written or enqueued:
- `plan-waves --lint` checks only that `## Touches` / `## Depends on` are present and parseable.
- Launch Pad Phase 2.5 FEASIBILITY asks whether the goal is achievable, not whether it is worth a run.
- Plan Review judges the brief's quality; the Decomposition Threshold splits one brief into subtasks and never batches
  across requirements.
- `skills/user-story-writing/SKILL.md` pushes the other way: INVEST "Small" and "Multiple features … Split into
  separate stories", so the writers produce exactly the many small items that each pay the floor.

On 2026-10-05/06 the operator merged items by hand three times (`automate-followups/32` = 14 + 28 + 29, `/33` = 17 + 25,
`meta-sync-followups/08` = 02 + 03 + 06) and the owner chose four more (ms/09 + ms/10, pa/13 into pa/06, af/22 + af/23,
ms/05 Part D into ms/07). Each hand merge needed the same steps: copy the originals verbatim as parts, park them with a
pointer, re-point every dependent, check that no original line was lost.

#### Goal
When an item is written or enqueued, the plugin says whether it is small relative to the run's fixed cost and which
pending items it could merge into. A helper performs a merge the owner chooses, mechanically and losslessly. Advisory
only: nothing is blocked, nothing is merged without the owner's choice.

#### Scope
1. **Size signal.** `automate-helpers.sh right-size <item|dir|item-list> [--root <checkout>] [--json]` reports per item:
   Touches count (after companion expansion, the planner's own reading), Scope bullet count, acceptance-criteria count,
   and a verdict `small | ok | large`. Thresholds are configurable defaults (`.supervisor/config.json` keys, documented),
   seeded from S2 and re-tuned from S3's lane costs; the defaults and their evidence are stated in the skill.
2. **Merge candidates.** For a `small` item, list pending items it could fold into, ranked by: shared Touches (declared
   or companion), being in the same `## Depends on` chain, and same requirement folder. Never propose a candidate whose
   merge would create a dependency cycle or pull a parked / operator-run / done item. Output names the shared files.
   Example: `meta-sync-followups/09: small (4 files, 2 scope items) — merge candidates: meta-sync-followups/10 (3 shared
   files, same folder)`.
3. **Where it runs (advisory, never blocking):**
   - the requirement writers — Product Owner's persist step (agent + `commands/product-owner.md` mirror), the `/propose`
     writers (`propose-*.sh`), the dismissed-finding drafts (`automate-dismissed.sh`) — print the line for the item they
     just wrote;
   - folder / backlog intake prints it beside `plan-waves --lint` before the Queue is confirmed;
   - `plan-waves --explain` adds a `small` note to a placed item.
4. **`automate-helpers.sh merge-items <out.md> --title <t> --goal <text> <Part:item>...`** — the hand procedure made
   mechanical: originals copied VERBATIM as parts (headings demoted; their Status / Depends on / Touches folded into the
   merged item's own sections; Touches unioned, changelog fragment renamed), originals' `## Status` set to `parked
   (merged <date> into <out> as Part <X> — do not run this file)`, every dependent's `## Depends on` re-pointed, and a
   post-check that every non-heading line of every original appears in the output (exit 1 and nothing written
   otherwise). Refuses a done, operator-run or already-merged original, and a merge that would create a cycle.
5. **Skill wording.** `user-story-writing`: "small enough to review in one PR, large enough to pay the run's fixed cost;
   when two stories touch the same files, prefer one story with parts." Same note in Product Owner's persist step.
6. **Tests:** fixtures for each verdict; a small item with a sibling sharing files gets that sibling first; no cycle or
   parked candidate is ever proposed; `merge-items` round trip on the three real 2026-10-05 merges (output equals the
   committed merged files modulo the generated header); the lost-line post-check fails when a line is removed.
   **Mutation controls:** dropping companion expansion from the size count, and dropping the post-check, must each fail
   a test.

#### Non-goals
Merging anything automatically, blocking intake or a writer, changing the planner's wave placement, or re-sizing items
already in flight.

#### Acceptance criteria
- `right-size` over the S3 queue as it stood on 2026-10-06 flags `meta-sync-followups/09` and `/10` as small and names
  each other as the top candidate.
- `merge-items` reproduces `automate-followups/33-children-settled-gate.md` from its two originals with zero lost lines.

#### Validation (must pass before merge)
1. Baseline full loop, `<passed>/<total>` and `SKIP` counts, base and branch.
2. Unchanged path: `plan-waves` output for an existing queue is byte-identical apart from the added `small` notes;
   writers still write the same item.
3. Running system: run `right-size` over the real pending queues and paste the report; perform one real merge the owner
   chooses with `merge-items` and paste the post-check.
4. A failure this must catch: the two mutation controls in Scope 6.
5. Rollback: `git revert`.

#### Evidence
S2 lane logs (costs above); S3 record `operator-run/S3-stabilization-wave-spike.md`; the three hand merges of
2026-10-05; owner request 2026-10-06: "I don't want to run automate for small requirements — not worth it … do we have
any check while writing a requirement whether it's good to run the full process?" Answer: no.
