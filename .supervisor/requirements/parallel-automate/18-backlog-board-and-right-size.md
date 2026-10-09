# 18 — One backlog board with a right-size column, and one shape for writing requirements: every item's real state, its size verdict, merge candidates, and the plan doc a requirement set is written in

## Status: pending

## Merged from (2026-10-06, owner decision: both scan every requirement item and report on it — one run and one wave fewer)
- Part A: `15-backlog-board.md` — 15 — One backlog board: every requirement item's real state, derived, never hand-kept
- Part B: `17-right-size-check-and-merge-items.md` — 17 — Right-size check: flag items too small to pay a full run, name what to merge them into, and merge them mechanically
- Part C: added 2026-10-09 by owner decision, written in this file (no source file) — Requirement shape: decide the shape before writing, one plan-doc template for a requirement set, measurement steps kept out of workers

The originals are parked with a pointer here. Their text is kept below VERBATIM as parts (headings
demoted, their Status / Depends on / Touches folded into this file's own sections). Nothing was paraphrased.

## Depends on
04-wave-planner.md
10-touches-backfill-lint-and-explain.md

## Touches
loomwright/scripts/automate-helpers.sh
loomwright/scripts/fixtures/automate-helpers-help.golden
loomwright/scripts/automate-helpers.d/plan-waves.sh
loomwright/scripts/automate-helpers.d/intake.sh
loomwright/scripts/test-automate-helpers-dispatch.sh
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
loomwright/docs/result-schemas/automate-run.md
loomwright/scripts/automate-dismissed.sh
loomwright/scripts/propose-common.sh
loomwright/skills/user-story-writing/SKILL.md
loomwright/agents/product-owner.md
loomwright/commands/product-owner.md
loomwright/skills/SKILLS_INDEX.md
loomwright/docs/prompt-token-budgets.json
changelog.d/parallel-automate-18-backlog-board-and-right-size.md

## Goal
One derived board of every requirement item (A), where the right-size verdict and merge candidates are a column on that board, while the writing-time and intake-time size line and the `merge-items` helper stay as part B specifies (B), and every new requirement is written in one of three shapes chosen before writing, with one plan-doc template for a requirement set (C).

## How the parts join (owner decision 2026-10-06 — the only scope beyond the two parts)
- Part B's right-size verdict and its merge candidates are a **column on Part A's board** (table and JSON), read from
  the same canonical status reader pass, not a second scan of the requirements.
- Part B's writing-time and intake-time line (the size signal at product-owner writing and at `/automate` intake)
  stays as Part B specifies, and so does the `automate-helpers.sh merge-items` helper.
- **Part C (owner decision 2026-10-09)** uses Part B's verdict as its fit check, and its plan-doc section check is one
  more line of Part B's `right-size` output, not a new command. Its text lands in the same skill and Product Owner
  files Part B already edits.
- **Size budget:** with Part C this item is at the ~30-file limit Part C itself sets. Nothing else is added to it.

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
   **Amended 2026-10-09 — `large` means "will not fit one PR", not just "big":** `large` when the companion-expanded
   Touches count is over `right_size_large_files` (default 30: of 138 past agent PRs in the postmortem ledger, median 13 files, 90% at 29 or fewer) OR the item has
   more Parts than `right_size_max_parts` (default 7: Plan Review FAILs a brief with more than 7 subtasks, and one Part
   per subtask is the comfortable form). The line names the cause and the remedy, e.g. `implementation-quality/02:
   large (83 files, 10 parts) — will not fit one PR: split by Part`. Splitting stays a human or agent edit.
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
already in flight. No split helper (`large` names the remedy; the split is written by hand).

#### Acceptance criteria
- `right-size` over the S3 queue as it stood on 2026-10-06 flags `meta-sync-followups/09` and `/10` as small and names
  each other as the top candidate.
- `merge-items` reproduces `automate-followups/33-children-settled-gate.md` from its two originals with zero lost lines.
- `right-size` on `implementation-quality/02` as it stood on 2026-10-09 prints `large` with both causes (files and parts)
  and "split by Part".

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

### Part C — Requirement shape: decide the shape before writing, one plan-doc template, measurements kept out of workers

#### Problem
Nothing decides a requirement's shape when it is written, so items come out either too small to pay a full run or too
big to finish in one. Both happened to the same work on 2026-10-09:
- **Too small.** `implementation-quality/01` + `throughput/01`–`09` were written as ten items. The owner merged them by
  hand into one.
- **Too big.** The merged item, `implementation-quality/02` (83 declared files, about 95 by Launch Pad's count, 10 Parts),
  failed Plan Review three times: 14 subtasks against the cap of 7, then two execution schemes that broke the
  orchestrator's and the worker hook's rules. It passed on a later attempt with 7 subtasks of 1–4 Parts. Its Subtask 6
  (four Parts, T05–T08) then stopped and was resumed repeatedly, for two reasons:
  - the 40-turn worker limit;
  - T06's proof steps (each test 10× in a loaded pool, about 50 min per harness, plus an idle-machine timing) ran
    inside the subtask, so the worker stopped to wait for them. Edits made while a harness ran invalidated three runs
    (9/10 and 8/10 instead of 10/10), which had to be redone.

The writers do not help:
- **Product Owner** writes one story per user goal and no plan doc. `skills/automate-loop/SKILL.md` (§2 "Prompt
  source") says PO "already writes … an optional `_BACKLOG.md`"; neither `agents/product-owner.md` nor
  `commands/product-owner.md` mentions one.
- **Hand-written folders** are inconsistent. On 2026-10-09, 14 of 27 requirement folders had a plan doc (`00-overview.md`
  or `_BACKLOG.md`), each with different sections. The 13 without one include the folders where items pile up one
  finding at a time: `automate-followups` (36 items), `meta-sync-followups` (11), `review-remediation` (10),
  `token-economy` (7), `loom-floor-ui` (7), `reconciler-repair` (6).

The good pattern already exists, just not in one place: `throughput/00-overview.md` (binding owner decisions, measured
baseline, ordered queue table, "considered and not queued", revisit triggers), `host-contract/_BACKLOG.md` (why now,
run command, which items run in parallel, run rules, checklist), and `implementation-quality/02`'s header (owner run
rule, internal ordering, planning facts already verified).

#### Goal
Every requirement is written in one of three shapes, chosen before writing. A requirement set gets one plan doc with
fixed sections. Acceptance that needs repeated runs or timing is marked as a measurement, so it is never run inside a
worker's turn budget.

#### Scope
1. **Shape decision** — a new section in `skills/user-story-writing/SKILL.md`, applied before any file is written:
   - **One item:** fits one PR — about 30 files or fewer, at most 7 subtasks, at most 2 Parts per subtask.
   - **One item with Parts:** same theme and shared files, and still fits one PR.
   - **A set of items plus a plan doc:** anything bigger. Each item in the set fits one PR.

   Part B's `right-size` verdict is the check (`small` ⇒ merge, `large` ⇒ split). The existing INVEST guidance stays,
   reworded per Part B Scope 5 so "Small" means "fits one PR", not "one finding".
2. **Plan-doc template** (in the same skill section; a sibling reference file only if the skill's token budget
   requires it). File: `<folder>/_BACKLOG.md`, the name `/automate --backlog` already reads. Sections, in this order:
   1. `## Status: done (index document — nothing to implement)`, the stamp the existing overviews use, so
      `resolve-folder` never enqueues the plan doc itself;
   2. **Why now**, with the measured baseline when one exists;
   3. **Owner decisions**, binding on every item;
   4. **Order**: a table of item · delivers · depends on · can run in parallel with;
   5. **Run**: the command, the mode, and the run rules (for example "no new follow-up items");
   6. **Considered and not queued**, so nobody re-proposes them without new evidence;
   7. **Revisit when**;
   8. **Checklist**: the `- [ ]` lines, last.

   **Honest limit, stated in the template:** the engine reads only the checklist lines, and each item's run receives
   only `--requirement <item>`. So an owner decision that an item's run must obey is ALSO copied into that item under
   `## Owner decisions (from _BACKLOG.md)`. Passing the plan doc to runs is a separate, undecided engine change.
3. **Item rules** (same skill section):
   - every item is self-contained: Problem, Goal, Scope, Acceptance criteria, Validation, Non-goals, `## Depends on`,
     `## Touches`;
   - **measurements are not acceptance.** A criterion that needs repeated runs (N×), wall-clock timing, or an idle or
     loaded machine goes under `## Measurements`, not `## Acceptance criteria`. It names the frozen commit it runs
     against (`git worktree add <tmp> <sha>`), so edits never invalidate it, and runs after the code is complete, never
     inside a worker's turn budget. The worker's own acceptance for it is "the harness exists and passes once";
   - **new findings join an existing theme.** A new item, Part, or "not queued" row goes into an existing theme's plan
     doc. No new `*-followups` folder is started.
4. **Writers:**
   - **Product Owner's persist step** (agent + `commands/product-owner.md` mirror) applies the shape decision. When it
     persists 2 or more stories for one prompt it also writes the plan doc from the template, named
     `.supervisor/requirements/_BACKLOG-{YYYY-MM-DD-HHMMSS}-{slug}.md`. The leading `_` keeps it out of PO's own
     prior-stories glob `20[0-9][0-9]-*.md`. PO's prompt references the skill section by name and does not restate it,
     so its token budget barely moves (re-measure; raise its row in `prompt-token-budgets.json` only if needed).
   - `skills/automate-loop/SKILL.md` §2 is corrected to describe what PO actually writes.
5. **Plan-doc check** — one more line of Part B's `right-size` when its input is a plan doc:
   `plan doc: sections ok | missing: <names>`, plus the normal verdict for each checklist item. Advisory, never
   blocking.
6. **Tests:**
   - a fixture plan doc built from the template reads `sections ok`; deleting one section reports it;
   - `resolve-folder` skips the plan doc (its status stamp), and `resolve-backlog` still reads its checklist in order;
   - PO's prior-stories glob does not match `_BACKLOG-*.md`;
   - an item with `## Measurements` but no frozen commit named is flagged by `right-size` (advisory).
   - **Mutation controls:** dropping the plan doc's status stamp, and dropping one required section from the check's
     list, must each fail a test.

#### Non-goals
- Passing the plan doc to each item's run (engine change; separate decision).
- An agent writing the owner decisions: that section is the owner's, or written on the owner's request.
- A split helper.
- Rewriting existing folders' overviews; each is migrated by hand when its theme is next worked on.
- Supervisor running measurements itself; the writing rule comes first, the engine support only if the problem
  returns.

#### Acceptance criteria
- `skills/user-story-writing/SKILL.md` has the shape decision, the plan-doc template and the item rules. Product Owner's
  persist step (agent and command) references them, and `skills/automate-loop/SKILL.md` §2 matches what PO writes.
- `right-size` on a template-built plan doc prints `sections ok`; on one missing a section it names that section.
- A plan doc written from the template is never enqueued by `resolve-folder`, and `/automate --backlog` reads its
  checklist in order.

#### Validation (must pass before merge)
1. Baseline full loop, `<passed>/<total>` and `SKIP` counts, base and branch.
2. Unchanged path: `resolve-folder`, `resolve-backlog` and `plan-waves` outputs unchanged on existing fixtures.
3. Running system: write the plan doc for the backlog that remains on merge day from the template (the owner picks the
   items), run `right-size` on it, and paste the output.
4. A failure this must catch: the two mutation controls in Scope 6.
5. Rollback: `git revert`.

#### Evidence
- 2026-10-09 session: the ten-item → one-item merge; `implementation-quality/02`'s three Plan Review FAILs and its
  Subtask 6 stop / resume reports.
- Requirement-folder census: 14 of 27 folders with a plan doc.
- `skills/automate-loop/SKILL.md` §2's claim about PO vs PO's own files.
- `agents/plan-reviewer.md` ("> 7 subtasks still FAILs").
- `agents/worker.md` (`maxTurns: 40`).

## Touches re-pointed 2026-10-07 (S3 operator f849e0cc, after pa/11's split — #408, v15.124.0)
- `RESULT_SCHEMAS.md` → `result-schemas/automate-run.md` (item states read `## Current` / closeout stamps).
- `automate-helpers.sh` kept (new dispatcher arms `item-state`, `right-size`, `merge-items`) + `fixtures/automate-helpers-help.golden`
  and `test-automate-helpers-dispatch.sh` (new arms + regenerated golden) + `automate-helpers.d/plan-waves.sh`
  (Part B 3: `--explain`'s `small` note) + `automate-helpers.d/intake.sh` (Part B 3: intake prints right-size). Where
  the new functions live (an existing family file or a new one) is the brief's call; a new family file is added to
  the loader's list and to this section.

## Amended 2026-10-09 (owner decision)
- **Part A:** when sources disagree, the item's own stamp beats a run file's `## Current` (the run becomes `stale_run`),
  and a `pending` item an old run marked abandoned reads `conflict`. Found on the 2026-10-09 backlog count.
- **Part B:** `large` now means "will not fit one PR" (over ~30 files or more than 7 Parts) and names the remedy.
  Found when `implementation-quality/02` failed Plan Review.
- **Part C added:** the requirement shape standard (shape decision, plan-doc template, item rules incl. measurements,
  PO writes the plan doc). Owner: "it's related to how we create requirements".
- Touches + `loomwright/skills/SKILLS_INDEX.md` (skill version bump) and `loomwright/docs/prompt-token-budgets.json`
  (PO prompt re-measure). The item is now at its own ~30-file limit: nothing else is added.
