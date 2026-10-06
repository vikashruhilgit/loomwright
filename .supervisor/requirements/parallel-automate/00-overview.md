# 00 — Parallel `/automate` overview (index/policy doc — NOT an implementable item)

## Status: done (index document — nothing to implement; this stamp is what keeps `/automate` from enqueuing this file)

## Where this queue comes from
Owner request 2026-10-01: "in one automate run pick multiple tickets … sequencing of jobs is not productive". A
research pass against `main` at `fdc8a5f` found that the sequential cost has two parts — the RUN phase (1h14–4h37
per item in the last four run files) and the wait for the owner's merge + `--resume` (about 1h up to 24h) — and that
the engine cannot run two items today for six verified reasons (see "Why it is sequential today"). The owner then
chose three supporting changes: one scripted version bump, run history on a dedicated unprotected branch, and a
closeout that needs no bookkeeping PR.

**Revised 2026-10-01 after a red-team audit (SHIP_BLOCKED: 4 FATAL, 7 CRITICAL).** Every finding was checked
against the repo / GitHub before being acted on. What changed is listed in "Red-team revisions" below; the items
carry the fixes.

## The items
| # | Item | Size | Why |
|---|---|---|---|
| 01 | Version-bump script + changelog fragments | small | One scripted bump per release instead of a hand edit per PR; removes the file set every feature PR collides on. |
| 02 | `meta-sync.sh` (init / pull / push / status) | medium | The mechanism for run history on a dedicated branch: a real 3-way sync with deletions, explicit paths and a prose scrub. Additive. |
| 03 | Branch mode in the engine (default OFF) | medium | Code only: pull before resume, push instead of the trail PR, loud failures. Changes nothing until a repo opts in. |
| M1 | Migrate THIS repo (`operator-run/`) | half a day, operator | Seed the branch, verify, untrack on `main`, protect the branch. Never run by `/automate`. |
| S1 | Two-lane spike (`operator-run/`) | 1 day, operator | Proves isolation and picks the lane shape before 05/06 are built. |
| 04 | Wave planner (`Depends on` / `Touches` + `plan-waves`) | small | Decides which items are safe to run together. Pure, read-only. |
| 05 | Lane coordinator (`/automate --parallel N`) | large | The parallel run: one isolated lane per item, one coordinator. |
| 06 | Wave close + split closeout | medium | One release bump per wave, closeout with no extra PR, no lane left behind. |
| 07 | Pilot + docs | small | Run a real queue in parallel; update the standing docs. |
| 08 | Shared CI slots across lanes | medium | All checkouts of the repo share N CI slots, one pass cache and a fair queue; each run uses its CPU share. (5–10-lane goal) |
| 09 | Fewer full suite runs per lane | small | One full run per push, a mapped `--affected` inner loop, `--last` instead of re-running to read output. |
| 10 | `Touches` / `Depends on` backfill, lint, `--explain` | medium | Today 26 open items plan into 24 waves (max 2 per wave); most items predate item 04's sections. |
| 11 | Split shared hotspot files | medium | Generated skills index; `automate-helpers.sh` split along its subcommand seams; measured by 10's `--explain`. |
| 12 | Policy answers for routine lane questions | medium | Stable gate ids + a human-stamped policy; 8 of S1 v2's 15 questions were routine. |
| 13 | Sibling-merge conflict repair | medium | After each merge, repair a parked PR that turned CONFLICTING via a watcher handshake; pause on a red `main`. Not a train. |
| S2 | Five-lane spike (`operator-run/`) | 1 day, operator | Measures CI slots, memory, owner load, merges and cost at 5 lanes; sets P2; go/no-go for 10. |
| 14 | Lanes pane add-on (opt-in sibling plugin) | medium | The `/lanes` pane prototyped in S1/w1 as an installable, optional Claude-adapter plugin over 05's `lane-status` / `lane-answer`; lanes behave identically without it (P9). |
| 15 | Backlog board (one derived view of every item's real state) | medium | One canonical status reader (done stamp anywhere, `unknown` as a state) + `/backlog` table/JSON + a Floor surface + `BACKLOG.md` on the meta branch; totals always add up. No dependencies, so it can run in the next wave. |
| 16 | Machine load guard (added 2026-10-05) | medium | S3 wave 1 froze the machine (load1 119 on 12 CPUs, watchdog reset) although 08's slots cap the suite at ~12 jobs. Attribute the load first, then one machine-wide gate in `ci-slot.sh` that holds new heavy work while overloaded and never kills. The coordinator's side (launch gating, reset recovery) is in 05 Scope 16. No dependencies; plans after 09 (shared `AGENT_GUIDELINES.md`). |

**Usage check:** every command in an `operator-run/` runbook is checked against the shipped script's usage text (`<script> --help`) before the runbook is used — by hand, no checker script; a flag `--help` does not list (e.g. the dry-run flag M1 step 1 once named) is a runbook bug to fix first.


## Order
01 → 02 → 03 → M1 (operator) → S1 (operator) → 04 → 05 → 06 → 07.
- **Amended 2026-10-04 (owner: "at least 5 to 10 lanes"):** 08, 09 and 10 have no dependencies on 05 and can run
  now. `plan-waves` (checked 2026-10-04): wave 1 = 08 + 10 (disjoint), wave 2 = 09 + 11 (09 shares `ci-local.sh`
  with 08; 11 depends on 10). The item-10 backlog backfill (operator edit) goes between 10 and 11. 12, 13 and 14 need 05. **S2 (operator) runs after 08 + 09 + 10 + the
  backfill** and before the lane count is raised; 12 is optional for S2. 07's pilot uses S2's lane count.
- 01, 02 and 04 are independent of each other. 03 needs 02. M1 needs 03 MERGED **and the plugin reinstalled**
  (sessions run the installed plugin, not the working tree). S1 needs M1. 05 needs 03 + 04 + S1's answers +
  `agnostic-phase1/04-non-interactive-gates.md`. 06 needs 01 + 05. 07 needs 06.
- 05, 06 and 07 are stamped `## Status: parked` until S1's findings are written into them.
- `/automate --folder .supervisor/requirements/parallel-automate` enqueues 01, 02, 03, 04 only (checked with
  `automate-helpers.sh resolve-folder`). **Stop the run after 03 and do M1 by hand before anything else merges** —
  M1 must not happen in the middle of an `/automate` run.
- **Amended 2026-10-03 (owner), after M1 steps 1–7:** M1 Verify → S1 (operator) → `meta-sync-followups/01–05`
  (one release, then reinstall) → M2 (operator: carry the learning stores) → 05 → 06 → 07.
  - M1 is done through step 7: #361 merged 2026-10-03 (`36f3730`). `loomwright-meta` holds the 381 run-history
    files, byte-identical to main@`9a78b9c` (checked again after the merge). Verify is still open. Its one real
    `/automate` cycle is item 04 here (small, read-only, needs no S1), via
    `--resume automate-2026-10-01-142337 --limit 4`.
  - S1 runs before the follow-ups, so it measures the engine as it is. Its answers (what a lane clone is missing)
    may add scope to `meta-sync-followups/05`. The follow-ups must not run while S1 runs (S1's isolation and
    contention checks).
  - The follow-ups and M2 come before 05, because parallel lanes mean several clones pushing to `loomwright-meta`
    at once. A clone has no allowlist, and two-writer conflicts plus the untested push fallbacks are exactly
    what the follow-ups fix.

## Owner decisions (defaults recorded 2026-10-01 — change here, items read this section)
- **P1 — merging: the owner merges each PR by hand.** Fact, not preference: the last 25 merged PRs all show
  `reviewDecision: REVIEW_REQUIRED` with zero reviews — every merge is an owner admin-bypass, because an author
  cannot approve their own PR. So **`--auto-merge` with `--parallel N>1` stays REFUSED in this queue**; nothing
  here builds a merge train that waits for an approval that never comes.
- **P2 — lane count. AMENDED 2026-10-04 (owner): the target is 5 to 10 lanes, not 2.** The default is set from
  S2's measurements (5 if clean; the largest N the data supports otherwise, limiting resource named); 10 only after
  a clean 5. Original text, kept for history: default lane count 2 until the pilot (item 07) measures contention. The subscription weekly cap, the
  CI review lens and N concurrent self-test suites all share one account / one machine.
- **P3 — metadata branch: `loomwright-meta`, run history only**, as explicit file patterns (never whole
  directories). Lessons (`.supervisor/memory/`), agent memory (`.claude/agent-memory/`) and `.agent/` stay on
  `main`.
- **P4 — a lane is a local CLONE, not a linked worktree.** State, lock and the `auto_review` toggle anchor to the
  primary checkout by design; a clone is its own primary. The clone is missing gitignored state the engine needs —
  item 05 lists what `lane-create` must carry over.
- **P5 — merging stays local and human.** No GitHub native auto-merge, no merge queue, no CI job with merge
  authority.
- **P6 — the next wave starts only on the owner's explicit go.**
- **P7 — who bumps the version (NEW — owner to confirm).** A wave of ONE item (every sequential run): that item's
  own PR runs the bump script as its last commit. A wave of several: lanes carry fragments only, and the LAST lane
  in planner order is the release lane that folds every fragment and bumps once (item 06). An unbumped merge is
  harmless: the next bump folds whatever fragments are on `main`.
- **P8 — lane shape (NEW — S1 decides).** Either (A) a lane runs the whole per-item loop headless, which needs
  `agnostic-phase1/04` because Launch Pad's normal Phase 6 gate has no non-interactive branch today; or (B)
  brief-first — the coordinator runs Launch Pad for each wave item interactively in the primary, and lanes run
  Supervisor + the owned drain only. S1 tries both and records the choice. **S1 added a third candidate (A +
  relay):** a lane runs headless WITH a question channel, its `AskUserQuestion` deferred, and the owner answers
  from the inbox (P9). See the S1 run record.
  **DECIDED 2026-10-04 by S1 (v1 + v2): A + relay.** It held every human gate in both v2 lanes (0 decided alone,
  against 3 in v1's shapes); B is not needed because the relay brings the brief gate to the owner anyway. Exact
  flags and hooks: item 05 "Spike findings".
- **P9 — add-ons are optional (owner, 2026-10-04).** The core owns all state and every action as FILES plus
  SCRIPTS: lane status is the run files; a question is a file, an answer is a file, and resuming a lane is a
  launcher script. Every extra is only a CLIENT of those files: a Claude Code mod (lanes pane, inbox buttons,
  toast, status line), desktop/phone notifications, the Floor, Remote Control. Rules:
  - (1) no gate, decision or state lives only in an add-on — remove it and runs behave identically;
  - (2) an add-on writes only through the core's guarded scripts;
  - (3) add-on display state is throwaway; the truth stays in files;
  - (4) an add-on failure is fail-safe (a broken render falls back, a failing hook is skipped) and never blocks a
    run;
  - (5) an add-on never launches lanes as its own children (a mod's spawned child dies when the module unloads);
  - (6) a plain fallback always exists (status script, live feed, `/janitor --report`, answering by file or through
    the main session);
  - (7) the core's tests run with NO add-on loaded.
  Claude-specific add-ons live in the Claude adapter layer (portability core/adapter direction) and count against
  the vendor-coupling ratchet.

- **P10 — usage budget. DECIDED 2026-10-04 (owner): "don't worry about budget" — no budget cap on the lane count; S2 still records cost per wave for visibility.** Original note: A lane cost about $24–27 per item in S1 v2, so 10 lanes are about
  $250 of usage per wave, plus a `claude-review` CI run per push on the same subscription (the weekly cap tripped on
  2026-09-15). Code cannot solve this: either lanes get their own billing (API key) or the lane count is capped by
  budget. S2 records cost per wave to inform it.

## Red-team revisions (2026-10-01)
| Finding | Verified how | Fix lives in |
|---|---|---|
| F1 push reverts siblings' edits, pull overwrites local ones (no merge base) | true by construction: `git add -f` of a stale copy overrides the seeded tip | 02 — recorded base tree, per-file 3-way |
| F2 deletions / renames never propagate | by construction | 02 — base-tree deletion handling; 03 keeps retraction |
| F3 `add -f` over directories publishes ignored logs; no prose scrub exists | 6 nested `.supervisor/` trees with log files exist under `.supervisor/requirements/` | 02 — explicit patterns, `--paths-from`, real scrub; M1 — protect the branch |
| F4 missing remote branch exits 0 ⇒ amnesia | by design reading | 02 — non-zero when mode is ON; explicit `init` |
| C1 nobody bumps in sequential mode after 01 | the bump instruction lives in `.supervisor/memory/LESSONS.md` and pending requirements' Scope lines, not agent prompts | 01 + P7 |
| C2 engine change + this repo's migration in one PR, run by the old installed engine | sessions run the installed plugin | 03 (code) / M1 (operator runbook) split |
| C3 "owner approves each PR" is false | `gh pr list --state merged --limit 25`: 25 × `REVIEW_REQUIRED`, 0 reviews; ruleset 12578391 active | P1; 06 rewritten without auto-merge |
| C4 train pushes onto READY, watcher-armed PRs | skill §6 forbids a push racing an armed watcher | 05 `ready_for_release`; 06 stepwise |
| C5 lanes cannot run headless as written | `agents/launch-pad.md` flag table: non-interactive is wired for "exactly TWO Phase 6 gates" | P8; 05 dependency + explicit allowlist + pinned plugin dir |
| C6 a clone lacks gitignored config, rules stamp, settings | reasoning from `.gitignore` + reported script headers; re-verify in S1 | 05 `lane-create` carry-over list |
| C7 resume-glob / dismissed drafts / token ledger / lock / intake claims wrong | `automate-dismissed.sh` scopes drafts to `"$run_id"--*--dismissed-*.md` | 05 Scope 2, 7, 8, 9 |
| W1–W9 | see items | 01, 03, 04, 05, 06, validation rule below |

## Why it is sequential today (verified 2026-10-01 at `fdc8a5f` — re-read, `main` moves)
1. **State is anchored to the primary checkout.** `run-lock.sh` (its "resolve root" block) and `build-state.sh`
   (its "Worktree-safe anchoring" block) take the FIRST `git worktree list --porcelain` entry; 12 non-test scripts
   do this. A second run from a linked worktree is refused `run_lock_held`.
2. **The run file tracks one item.** One `## Current` block; `<run_id>.supervisor-result.md` and
   `<run_id>.review-heal-result.md` are overwritten per item and `gate-eval` reads them back.
3. **Single-open-PR invariant** (`skills/automate-loop/SKILL.md` §8) and "Parallel / multi-item execution" is a
   listed non-goal (§1).
4. **Phase 1.5 pre-flight** classifies an open PR touching the same files as OVERLAP and fails closed
   non-interactively (`skills/preflight-sync/SKILL.md`). It cannot see a sibling lane whose PR is not open yet.
5. **Feature PRs bump the same three files** — `loomwright/.claude-plugin/plugin.json`,
   `.claude-plugin/marketplace.json`, `CHANGELOG.md` (about half of the last 14 first-parent merges).
6. **Human gates run inline on the main thread** and Claude Code strips `AskUserQuestion` from every subagent.

## Invariants every item must preserve
- **One merge executor.** `gh pr merge --squash` is executed only by `automate-helpers.sh gate-eval`. Nothing in
  this queue adds a merge path, and nothing in it calls `gate-eval` for a parallel run (P1).
- **One owned drain per PR per pass** (at most one owner-requested fix-now re-drain), and the `auto_review`
  suppress/restore contract (§7) — per lane. No item adds a third drain category.
- **No push onto a PR that is `awaiting_merge` with a watcher armed.**
- **Bimodal failure philosophy.** Gates fail CLOSED under non-interactive; emitters and every `|| true` hook exit 0.
- **Never force-push** the metadata branch; never write a done stamp without `gh` merge evidence.
- **Shipped plugin code never calls a repo-local path** (`scripts/…` of this repo); project-specific commands come
  from tracked project config behind the same human-stamp valve `rules-check.sh` uses.
- **The sequential path is protected, honestly stated:** the helper suites (`test-automate-helpers.sh`,
  `test-automate-trail.sh`, `test-automate-dismissed.sh`) must pass with no edit to existing assertions, AND —
  because the engine is prose (`SKILL.md`, `commands/automate.md`) that no test can byte-compare — each item that
  edits that prose shows a diff confined to new, flag-gated sections plus one real sequential item run afterwards.

## Validation rule for every item (the "nothing breaks" contract)
Each item carries a `## Validation (must pass before merge)` section with these parts plus its own specifics.
1. **Baseline, before and after.** Full loop (every `loomwright/scripts/test-*.sh`, root `scripts/test-*.sh`,
   `scripts/check-vendor-coupling.sh`, `scripts/check-token-budget.sh`, `scripts/check-doc-currency.sh`) on the
   untouched base and on the finished branch. Record `<passed>/<total>` **and the count of `SKIP` lines** for both —
   a test that silently starts skipping is a regression. A test may not be edited to pass unless Scope names it.
2. **Unchanged-path proof** — the named command or suite.
3. **Running-system check** — exercised once in the real repo or a real clone, output pasted.
4. **A failure the validation must catch** — each item names at least one mutation that its validation would
   detect, so the check is not vacuous.
5. **Rollback** — written out, and tried once when it is not a plain `git revert`.

## Evidence
- Scratch spike 2026-10-01: a separate-index push and a `git restore --source --worktree` pull left the code branch
  clean. It did NOT test stale copies, deletions or ignored files — the red-team reproduction showed all three
  fail with the naive design; item 02 now specifies the fix.
- Stripped-metadata run 2026-10-01 (131 self-tests with `.supervisor/` and `.claude/agent-memory/` deleted): 127
  pass, 4 fail (`test-citation-drift.sh`, `test-committed-twin-scrub.sh`, `test-automate-dismissed.sh`,
  `test-validate-entry.sh`). Reader scripts in a stripped clone exit 0 with EMPTY output; only `resolve-folder`
  fails loudly. Some tests SKIP silently without the tracked corpus (reported: `test-context-digest.sh`,
  `test-harvest-conventions.sh`) — pass counts alone hide that.
- Session scratch, not committed. Each item carries its own "Verified premises" block.
