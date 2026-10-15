# automate-speed (items 03–24) — plan doc (index document, not an implementable item)

## Status: done (index document — nothing to implement)

## Why now
Measured 2026-10-15 from `~/.claude/projects` transcripts (last 7 days, this repo plus its worktrees and lanes):
- **Main-thread sessions hold 68% of all context tokens.** 110 sessions, ~104 turns each, ~380K context re-read per
  turn, peaks 750–858K; 1 compaction in 110 sessions. Subagents: general-purpose 15%, worker 9%, code-reviewer 3%,
  plan-reviewer 1%, context-keeper (Haiku) 0.1%.
- **One `/automate` item pulls ~1.04MB (proxy ~260K tokens) of prose inline:** automate-loop 316KB, self-heal-advisory
  176KB, review-heal 133KB, `agents/supervisor.md` 111KB, autonomous-loop 102KB, `agents/launch-pad.md` 94KB,
  `commands/supervisor.md` 58KB, async-orchestration 57KB, `commands/autonomous.md` 43KB.
- **What that prose is** (heuristic sentence classification): ~62% step-by-step bookkeeping and control flow, 19% rules
  and invariants, 11% history and stories, 8% "call script X". ~300 incident references (#NNN, queue/NN, dates) in the
  runtime prompts.
- **Lanes are not cheaper per item:** median lane item session 65M main-session tokens, 146 turns, 647K peak; inline
  `/automate` session 54M, 160 turns, 494K peak. Lanes buy wall-clock, not tokens.
- **PR #533 timeline:** Launch Pad 13m (Plan Review 3/3), build 40m, Phase 4.5 85m (ESCALATED 3/3), drain 2h11m for
  one round. GitHub CI ~7m, claude-review ~5.5m; local `ci-local` full 12–14m, `--affected` ~2.4m.
- **Bash output:** 300–500K chars per main session; plugin scripts are ~10% of it, the model's own exploration most.
- **Budget gate:** `check-token-budget.sh` covers only the 14 agents + preloaded skills; skills and commands have no
  ceiling. `prompt-token-budgets.json` is 37KB, mostly notes.
- **Models (Anthropic table, 2026-10-15):** Opus 5.5 $4/$20, Sonnet 5.5 $2/$10, Haiku 5.5 $0.10/$0.50 (≤100K prompt;
  $0.50/$2.50 above) per MTok; all 1M context.

Root cause: the loop is a program written in English, run inline in one context that never shrinks. The fix is to
move the deterministic part into scripts, run each phase in a fresh session, and keep only instructions and short
rules in the prompts.

## Owner decisions
Recorded 2026-10-15 (owner, Product Owner session):
- **D1** Moving prose never drops a rule. Every rule gets one of three homes — enforced by an existing script or hook,
  step-scoped (handed over only at its step), or global (kept, short) — recorded in the loop inventory (item 04)
  before its prose is deleted.
- **D2** Stories and history move to a rationale doc; a one-line "because" stays only where it stops a tempting wrong
  shortcut.
- **D3** The coordinator's model is chosen by measurement (item 10), not opinion. Implementing, reviewing and brief
  writing stay on the strong model.
- **D4** Owner item 15 (fix rounds on `ci-local --affected`) is dropped: shipped in #538.
- **D5** Phase 0 (items 03–05) lands before any Phase 1 prose is deleted; the legacy prose path stays selectable until
  golden parity (retired in item 08).
- **D6** Phase 3 splits are move-only: no behaviour, subcommand or output change.
- **D7** Product Owner does not push to `loomwright-meta`; the owner pushes before a `--parallel` run.
- **D8** (2026-10-15, owner: "items are fine, but finish in fewer waves") Keep the 22 items; cut waves by removing
  false conflicts. `## Touches` lists exact existing files, never a `skills/`/`commands/`/`agents/` directory (a
  directory entry fires the `.agent/companions.json` "new file" rules and serialises unrelated items). Item 05 runs
  beside 04 (item 06 links its cases into the inventory); items 11 and 12 start after 06, not 08; items 12 and 14 do
  not edit `agents/review-pr.md`; item 10 uses a config key, not an `/automate` flag. Item 21 is re-scoped to the test
  file because `automate-helpers.sh` is already split into `automate-helpers.d/`; new modules follow that `<script>.d/`
  convention.
- **D9** (2026-10-15, owner) Item 25 pulls the load-by-mode quick win out of item 16 into wave 1: Step 0 of
  `/automate` stops reading `lanes.md`, `command-lanes.md`, `resume.md` and `branch-mode.md` on runs that do not need
  them (~78K chars per item; seen on vendsy/hub PR #445 and loomwright PR #555). Item 06 now depends on 25.
- **D10** (2026-10-15, owner) Item 26 adds the subagent prompt diet (code-reviewer, execute-manager, plan-reviewer,
  worker): subagents were 36% of PR #555's item and every spawn re-pays its prompt. Kept at 7 waves: item 10 documents
  its config key in `docs/result-schemas/automate-run.md` instead of `ARCHITECTURE_CONTRACTS.md`, and item 18 adds
  the §"Cost Profiles" pointer; item 18 now also depends on 10 and 26.
- Flags acknowledged with "Proceed": a live `/automate` run on `feature/af39a-sweep` has uncommitted edits to
  `automate-helpers.sh` / `automate-lanes.sh` (items 19, 21, 24 wait for it); item 09 rewrites the documented
  inline-only rule in `docs/ARCHITECTURE_CONTRACTS.md`.

## Order
Owner's list → files: 1→04, 2→05, 3→03, 4→06/07/08, 5→09, 6→10, 7→11/12, 8+9+10→13/14/15/16 (by file group),
11→17, 12→18 (with the ceiling re-baseline), 13→19/20/21 (21 = the helpers' test file, D8), 14→22, 15→dropped (D4),
16+17→23, 18→24; quick win → 25 (D9); subagent prompt diet → 26 (D10).

| Item | Delivers | Depends on | Wave |
|---|---|---|---|
| 25 | /automate reads lanes, resume, branch-mode files only when the run needs them | none | 1 |
| 04 | Loop inventory + `test-loop-inventory.sh` | none | 1 |
| 05 | Golden run-file tests for every per-item-loop branch | none | 1 |
| 17 | Ceilings for skills and commands | none | 1 |
| 06 | next-step driver: tail (gate, park, closeout); links 05's cases into the inventory | 04, 05, 25 | 2 |
| 13 | Diet: Launch Pad + /autonomous | 04 | 2 |
| 03 | Per-item cost report + committed baseline | none | 2 |
| 19 | Split automate-lanes / automate-trail into `.d/` modules | none (after af39a merges) | 2 |
| 07 | next-step driver: DRAIN + RUN bookkeeping | 06 | 3 |
| 11 | next-step inside Supervisor | 06 | 3 |
| 12 | next-step inside review-heal | 06 | 3 |
| 20 | Split setup-memory / meta-sync into `.d/` modules | none | 3 |
| 08 | next-step driver: PICK, RECONCILE, resume; legacy retired | 07 | 4 |
| 14 | Diet: review-heal | 12 | 4 |
| 15 | Diet: Supervisor + self-heal-advisory | 11 | 4 |
| 21 | Split test-automate-helpers.sh to mirror automate-helpers.d/ | none (after af39a merges) | 4 |
| 09 | Fresh session per phase | 08 | 5 |
| 23 | Measure heal rounds + Plan Review attempts | 03 | 5 |
| 22 | Split dreaming / setup / agent-help commands | none | 5 |
| 10 | Coordinator model A/B | 09, 03 | 6 |
| 16 | Diet: automate-loop (load by phase) | 09, 25 | 6 |
| 24 | Terse script output | 19, 21 | 6 |
| 26 | Diet: code-reviewer, execute-manager, plan-reviewer, worker prompts + preloads | none | 6 |
| 18 | Lock the gains: history-ref lint + lowered ceilings + Cost Profiles pointer | 10, 13, 14, 15, 16, 17, 26 | 7 |

`plan-waves --max 4` (2026-10-15, after D8–D9, checklist order below) schedules **7 waves**; 3 lanes give 8, 2 give 11, sequential 22. The floor
is the driver chain 06 → 07 → 08 → 09 (same files, so never in one wave) plus 16 and 18 after it. The wave column is
the planner's greedy choice in checklist order — the order matters: items that edit an agent prompt (11, 13, 15, 26) or
the budget/contract docs (09, 17, 18) conflict pairwise through `.agent/companions.json`, so each needs its own wave; re-run `plan-waves <this folder> --max 4 --explain` after edits.

## Run
/automate --backlog .supervisor/requirements/automate-speed/_BACKLOG.md --parallel 4
- Before the run: `feature/af39a-sweep` merged; the owner pushes these item files to `loomwright-meta` with an exact
  `meta-sync.sh push --paths-from` list (lane-create aborts on items missing from the meta branch).
- Safe mode only (no `--auto-merge`; `init-check` refuses it with `--parallel`). One wave at a time; the owner merges
  each wave's PRs, then `/automate --resume <run_id>` starts the next wave.
- Re-run `plan-waves --lint` after any edit to an item's `## Touches` or `## Depends on`. Keep Touches as exact files
  under `skills/`, `commands/` and `agents/` (D8).
- No new follow-up items mid-run: findings outside an item's scope go to `.supervisor/requirements/proposed/`.

## Considered and not queued
- **Owner item 15, fix rounds on `ci-local --affected`:** shipped in #538 (automate-speed/02); GitHub CI runs the
  full suite.
- **Capping Plan Review attempts or heal rounds now:** both are quality gates; item 23 measures first.
- **Running the coordinator on Haiku before the driver exists:** the prose coordinator must follow ~1MB of
  interlocking rules; the model choice is only meaningful after items 06–09 (item 10).
- **Claiming cross-agent prompt-cache reuse:** tools render before system, so different agent types diverge at
  position 0 (token-economy plan, locked call 5).
- **Loosening `.agent/companions.json` to parallelise skill edits:** it is deliberate repo policy; changing it is its
  own decision with its own evidence.
- **Merging items 06–08 into one item to reach 5 waves:** owner kept the items (D8); revisit if a driver item fails
  Plan Review or its review diff turns out small.
- **Splitting `automate-helpers.sh` again:** already split into `automate-helpers.d/` (largest module 694 lines); only
  its test file needed it (item 21).
- **Splitting prompt files without load-by-mode:** parallel-automate/22 did a move-only split that saved nothing
  because the index still said "read every split in full".

## Revisit when
- Item 23 shows heal still 3/3 on most post-v17.2.0 items (its propose-only draft opens the follow-up).
- Item 10 finds no cheaper model with full parity.
- Item 03's report after item 09 shows the coordinator still above ~100K peak context per item.

## Checklist
- [ ] .supervisor/requirements/automate-speed/25-automate-load-by-mode.md
- [ ] .supervisor/requirements/automate-speed/04-loop-inventory.md
- [ ] .supervisor/requirements/automate-speed/05-golden-run-tests.md
- [ ] .supervisor/requirements/automate-speed/17-prompt-size-ratchet.md
- [ ] .supervisor/requirements/automate-speed/06-next-step-driver-tail.md
- [ ] .supervisor/requirements/automate-speed/13-diet-launch-pad-autonomous.md
- [ ] .supervisor/requirements/automate-speed/03-measure-run-cost.md
- [ ] .supervisor/requirements/automate-speed/19-split-lanes-and-trail-scripts.md
- [ ] .supervisor/requirements/automate-speed/07-next-step-drain-and-run.md
- [ ] .supervisor/requirements/automate-speed/11-next-step-supervisor.md
- [ ] .supervisor/requirements/automate-speed/12-next-step-review-heal.md
- [ ] .supervisor/requirements/automate-speed/20-split-memory-and-meta-scripts.md
- [ ] .supervisor/requirements/automate-speed/08-next-step-pick-and-resume.md
- [ ] .supervisor/requirements/automate-speed/14-diet-review-heal.md
- [ ] .supervisor/requirements/automate-speed/15-diet-supervisor.md
- [ ] .supervisor/requirements/automate-speed/21-split-automate-helpers.md
- [ ] .supervisor/requirements/automate-speed/09-fresh-session-per-phase.md
- [ ] .supervisor/requirements/automate-speed/23-measure-review-gates.md
- [ ] .supervisor/requirements/automate-speed/22-split-big-commands.md
- [ ] .supervisor/requirements/automate-speed/10-coordinator-model-ab.md
- [ ] .supervisor/requirements/automate-speed/16-diet-automate-loop.md
- [ ] .supervisor/requirements/automate-speed/24-terse-script-output.md
- [ ] .supervisor/requirements/automate-speed/26-diet-subagent-prompts.md
- [ ] .supervisor/requirements/automate-speed/18-lock-the-gains.md
