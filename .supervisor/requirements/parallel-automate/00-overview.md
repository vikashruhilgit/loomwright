# 00 — Parallel `/automate` overview (index/policy doc — NOT an implementable item)

## Status: done (index document — nothing to implement; this stamp is what keeps `/automate` from enqueuing this file)

## Where this queue comes from
Owner request 2026-10-01: "in one automate run pick multiple tickets … sequencing of jobs is not productive". A
research pass against `main` at `fdc8a5f` found that the sequential cost has two parts — the RUN phase (1h14–4h37
per item in the last four run files) and the wait for the owner's merge + `--resume` (about 1h up to 24h) — and that
the engine cannot run two items today for six verified reasons (see "Why it is sequential today"). The owner then
chose three supporting changes that make parallelism simple instead of bolted on: bump the version at merge time,
move run history to a dedicated unprotected branch, and split closeout so no bookkeeping PR is needed.

## The items
| # | Item | Size | Why |
|---|---|---|---|
| 01 | Version-bump script + changelog fragments | small | Two open PRs can never claim the same version; removes the one file set every feature PR collides on. |
| 02 | `meta-sync.sh` (pull / push / status) | medium | The mechanism for run history on a dedicated branch. Additive — changes no behaviour on its own. |
| 03 | Migrate run history to the metadata branch + retire the trail PR | medium | Removes metadata-only PRs (20 of the last 60 merges on `main`). Makes lane closeout a push, not a PR. |
| S1 | Two-lane spike (`operator-run/`) | 1 day, no plugin change | Proves isolation and answers four open questions before 05/06 are built. Operator-run, never enqueued. |
| 04 | Wave planner (`Depends on` / `Touches` + `plan-waves`) | small | Decides which items are safe to run together. Pure, read-only, testable. |
| 05 | Lane coordinator (`/automate --parallel N`) | large | The parallel run itself: one isolated lane per item, each running today's per-item loop unchanged. |
| 06 | Merge train + split closeout | medium | Serial, gate-preserving merge of a wave; closeout with no extra PR. |
| 07 | Pilot + docs | small | Run a real queue in parallel; update the skill, command docs and CLAUDE.md invariants. |

## Order
01 → 02 → 03 → S1 (operator) → 04 → 05 → 06 → 07.
- 01, 02 and 04 are independent of each other. 03 needs 02. S1 needs 03. 05 needs 03 + 04 + S1's answers.
  06 needs 01 + 05. 07 needs 06.
- 05, 06 and 07 are stamped `## Status: parked` until S1's findings are written into them; un-park by
  replacing the stamp with `## Status: pending`.
- `/automate --folder .supervisor/requirements/parallel-automate` therefore enqueues 01, 02, 03, 04 only.

## Owner decisions (defaults recorded 2026-10-01 — change here, items read this section)
- **P1 — required review on `main`: KEEP.** The owner approves each PR; the merge train does everything else and
  waits for the approval. Hands-off merging would need the protection rule relaxed — out of scope.
- **P2 — default lane count: 3.** The Claude subscription weekly cap is shared across lanes.
- **P3 — metadata branch: `loomwright-meta`, run history only.** Lessons (`.supervisor/memory/`), agent memory
  (`.claude/agent-memory/`) and `.agent/rules/` stay on `main`.
- **P4 — a lane is a local CLONE, not a linked worktree.** State, lock and the `auto_review` toggle anchor to the
  primary checkout by design; a clone is its own primary, a worktree is not.
- **P5 — merging stays local.** No GitHub native auto-merge, no merge queue, no CI job with merge authority.
- **P6 — the next wave starts only on the owner's explicit go**, as the next item does today.

## Why it is sequential today (verified 2026-10-01 at `fdc8a5f` — re-read, `main` moves)
1. **State is anchored to the primary checkout.** `run-lock.sh` (its "resolve root" block) and `build-state.sh`
   (its "Worktree-safe anchoring" block) take the FIRST `git worktree list --porcelain` entry; 12 non-test scripts
   do this. A second run from a linked worktree is refused `run_lock_held`.
2. **The run file tracks one item.** One `## Current` block; `<run_id>.supervisor-result.md` and
   `<run_id>.review-heal-result.md` are overwritten per item and `gate-eval` reads them back.
3. **Single-open-PR invariant** (`skills/automate-loop/SKILL.md` §8) and "Parallel / multi-item execution" is a
   listed non-goal (§1).
4. **Phase 1.5 pre-flight** classifies an open PR touching the same files as OVERLAP and fails closed
   non-interactively (`skills/preflight-sync/SKILL.md`).
5. **Every feature PR bumps the same three files** — `loomwright/.claude-plugin/plugin.json`,
   `.claude-plugin/marketplace.json`, `CHANGELOG.md` (6 of the last 14 first-parent merges).
6. **Human gates run inline on the main thread** (Launch Pad feasibility / save, Plan Review FAIL×3, Supervisor
   adjudication, the dismissed-findings ask) and Claude Code strips `AskUserQuestion` from every subagent.

## Invariants every item must preserve
- **One merge executor.** `gh pr merge --squash` is executed only by `automate-helpers.sh gate-eval`, all seven
  conditions, fail CLOSED. The positive-form grep in CLAUDE.md §"Failure-Mode Invariants" must still resolve to the
  same five surfaces.
- **One owned drain per PR per pass**, and the `auto_review` suppress/restore contract (§7) — per lane.
- **Bimodal failure philosophy.** Gates fail CLOSED under non-interactive; emitters and every `|| true` hook exit 0.
- **`--parallel 1` (the default) is byte-for-byte today's behaviour.** This is the no-breakage guarantee; the
  existing `test-automate-helpers.sh` / `test-automate-trail.sh` suites must pass unchanged for that path.
- **Never force-push** the metadata branch; never write a done stamp without `gh` merge evidence.
- Run the FULL test loop before pushing: every `loomwright/scripts/test-*.sh` AND root `scripts/test-*.sh` +
  `scripts/check-vendor-coupling.sh` + `scripts/check-token-budget.sh` + `scripts/check-doc-currency.sh`.

## Validation rule for every item (the "nothing breaks" contract)
Each item carries a `## Validation (must pass before merge)` section. All of them share these four parts; the item
adds its own specifics. A PR that cannot show all four is not ready, whatever its tests say.
1. **Baseline, before and after.** Before the first edit, run the full loop (every `loomwright/scripts/test-*.sh`,
   root `scripts/test-*.sh`, `scripts/check-vendor-coupling.sh`, `scripts/check-token-budget.sh`,
   `scripts/check-doc-currency.sh`) on the untouched base and record `<passed>/<total>` plus the names of any test
   already failing. Run it again on the finished branch. The PR body carries both lines. A test that passed before
   and fails after blocks the PR; a test may not be edited to pass unless the item's Scope names it.
2. **Unchanged-path proof.** Show that the behaviour the item does NOT intend to change is unchanged — the item
   names the exact command or suite.
3. **Running-system check.** Exercise the change once in the real repo (or a real clone of it), not only in a temp
   fixture, and paste the observed output. Hermetic tests assert the shape the code chose; this checks the shape
   the system actually has.
4. **Rollback.** State how to undo the item after merge and what is lost. If rollback is not a plain `git revert`,
   the steps are written out and were tried once.

## Evidence
- Scratch spike 2026-10-01: pushing gitignored files to a side branch via a separate index
  (`GIT_INDEX_FILE` + `git add -f` + `write-tree` + `commit-tree` + `update-ref`) left the code branch and its index
  clean; `git restore --source=origin/<branch> --worktree -- .supervisor` in a second clone landed the files as
  ignored with a clean `git status`.
- Stripped-metadata run 2026-10-01 (all 131 self-tests in a worktree with `.supervisor/` and
  `.claude/agent-memory/` deleted): 127 pass, 4 fail — `test-citation-drift.sh`, `test-committed-twin-scrub.sh`,
  `test-automate-dismissed.sh`, `test-validate-entry.sh`. Reader scripts in a stripped clone all exit 0 with EMPTY
  output (`resume-glob`, `read-postmortem.sh`, `session-resume.sh`, `reconcile-jobs.sh`,
  `stamp-requirement-status.sh`); only `resolve-folder` fails loudly.
- These were session scratch (not committed). Each item carries its own "Verified premises" block.
