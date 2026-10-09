# 02 — Show the cost of fix-now at the dismissed-findings decision: a derived wall-clock estimate in every fix-now prompt

## Status: parked — superseded by `.supervisor/requirements/implementation-quality/02-iq01-and-throughput-merged.md` (owner decision 2026-10-09: implementation-quality/01 + throughput/01–09 merged into ONE item / ONE PR; this file is kept as that file's Part source)

## Depends on
none

## Touches
loomwright/scripts/automate-dismissed.sh
loomwright/scripts/automate-helpers.sh
loomwright/scripts/fixtures/automate-helpers-help.golden
loomwright/scripts/test-automate-dismissed.sh
loomwright/skills/automate-loop/SKILL.md
loomwright/commands/automate.md
loomwright/docs/result-schemas/automate-run.md
changelog.d/throughput-02-fix-now-cost-at-decision.md

## Problem
The owner decides fix-now / follow-up / drop for each dismissed finding **without being shown what fix-now costs**. On the last real item, that choice took most of the item's wall-clock.

**Measured (run `.supervisor/automate/automate-2026-10-08-121222.md`, PR #435, `## Progress`):**
- 12:12:22Z run created → 14:17:25Z "drain READY (converged, 1 round, 0 fix cycles…)".
- 14:20:07Z: the owner chose **fix-now on 4 drafts**. The four `fix-now 2026-10-08T14:20:07Z` rows are in `.supervisor/automate/automate-2026-10-08-121222.dismissed-decisions`.
- 15:08:30Z: "owned drain started (fix-now re-drain, owner decision) … @ 842cbe7". This was 48 min of fix-now pass before the re-drain.
- 16:41:29Z: "fix-now re-drain READY (sub_floor_converged, 2 rounds…)".
- 17:24:50Z: "parked awaiting_merge". The decision step ran again for the re-drain's 2 new dismissals; their ledger rows are `follow-up 2026-10-08T17:24:50Z`.
- **Drain READY → park = 3 h 07 m (14:17:25 → 17:24:50), 60% of the 5 h 12 m item (12:12:22 → 17:24:50).** Decision → re-drain READY alone = **2 h 21 m** (14:20:07 → 16:41:29).

**Prior fix-now re-drains (decision → re-drain terminal line, this repo's run files):**

| Run | Decision → re-drain terminal | Span |
|---|---|---|
| 09-30-054439 | 15:21:55 → 15:47:43 (progress lines) | 26 m |
| 10-01-142337 (item 01) | ledger 18:30:30 → 18:44:18 | 14 m |
| 10-01-142337 (item 03) | ledger 10-02 12:12:15 → 13:11:15 | 59 m |
| 10-07-170659 | ledger 00:38:39 → 01:51:59 | 1 h 13 m |
| 10-08-071524 | ledger 09:02:57 → 11:55:42 | 2 h 53 m |
| 10-08-121222 | ledger 14:20:07 → 16:41:29 | 2 h 21 m |

The spread is wide, and the two most recent are the longest (GitHub `ci` now runs 11.5–14.9 min per push on PR #435). A fixed number would mislead. The estimate must be derived.

**Where the question lives (no cost shown):** `loomwright/skills/automate-loop/SKILL.md` §6 "Dismissed-findings decision step (before the park)", step 2. It defines "ONE question per per-finding draft, options **Follow-up (keep draft)** (recommended, first) · **Fix now on this PR** · **Drop**". Step 3 defines what fix-now triggers: "ONE full re-pass of DRAIN → GATE". The mechanics are in `loomwright/scripts/automate-dismissed.sh`, dispatched from `automate-helpers.sh` (`dismissed-drafts` / `dismissed-decide` / `dismissed-pending`). None of them computes or prints a cost.

**What the data allows, and its traps:**
1. **Start time.** The fix-now decision time is script-written and reliable from 10-01 on: the `dismissed-decide` ledger row `draft<TAB>fix-now<TAB>ts`.
   - Trap: the 09-30-054439 ledger's fix-now row reads `2026-10-01T03:15:17Z`, 11 h *after* that item's re-drain READY (09-30 15:47:43Z). A derivation must drop a span whose end precedes its start.
2. **End time.** The re-drain's start and terminal `## Progress` lines are model-written prose with **no pinned format**. `automate-helpers.d/runfile.sh` guards only the `owned drain started` prefix (`re_g='^([^ ]+ )?(picked |ran /autonomous|owned drain started)'`). Real wording varies across runs:
   - starts: "owned drain started (fix-now re-drain, owner decision)", "owned drain started — fix-now re-drain", "owned re-drain started (fix-now re-pass…)";
   - terminals: "fix-now re-drain READY (…)", "re-drain READY (…)", "re-drain (918470a): SETTLED required=green …".

## Goal
Every fix-now option the owner sees states what fix-now will cost, and the estimate is derived from this repo's recorded fix-now re-drains when they exist. The owner still decides per finding. The decision enum, its recording, and the non-interactive can't-ask branch are unchanged.

## Scope
**Owner decision (binding, 2026-10-09):** show the cost. The owner still decides per finding (fix-now / follow-up / drop). The non-interactive can't-ask branch stays.

1. **Estimator: a new `dismissed-cost <runfile>` subcommand in `automate-dismissed.sh`.** It sits with its siblings (same protocol authority, same ledger), is dispatched from `automate-helpers.sh` like `dismissed-drafts`, and is listed in the header usage block.
   - **Output:** one line, `fix_now_cost: <estimate> (<basis>)`.
   - **With samples:** basis = `median of <n> recorded fix-now re-drains in this repo, range <min>–<max>`.
   - **Without samples:** basis = the stated default.
   - **Samples.** Read every `.supervisor/automate/*.dismissed-decisions` sibling of the run file's directory. For each run with a `fix-now` row:
     - start = that run's earliest fix-now ts per decision batch;
     - end = the first later `## Progress` line in the matching run file that is a fix-now re-drain terminal (READY or ESCALATED).
   - **Matching the end line:** the new pinned form (item 3), plus a tolerant match for the legacy wordings quoted in Problem.
   - **Dropped samples:** end ≤ start, or a span > 12 h (owner think-time or an overnight stall).
   - **Fail-SAFE (advisory emitter):** this output never feeds a gate.
     - An unreadable ledger or run file ⇒ that sample is skipped.
     - Nothing readable ⇒ the default line.
     - Always `exit 0`.
   - Its own fixtures must cover:
     - the 09-30 out-of-order ledger (dropped);
     - legacy and pinned wordings;
     - zero samples (default);
     - median and range on the six spans in the Problem table (expected median ≈ 66 min, range 14 m–2 h 53 m).
2. **Default when no sample exists: the measured baseline, not a guess.** Use `≈ 1h06m median, range 14m–2h53m (6 fix-now re-drains in this repo, 2026-09-30 → 10-08)`, the six spans in the Problem table. (Correction, 2026-10-09: an earlier "~1.5–2.5 h" figure came from the two most recent spans only, and the 2 h 53 m one falls outside it. The owner's D2 asks to *show the cost*, not for a particular number, so the measured median and range are used.) The default applies only to a repo with no recorded fix-now re-drain, such as a fresh install. It must say it is another repo's baseline: `(default: loomwright's own 2026-10 baseline; no fix-now re-drain recorded here yet)`.
3. **Pin the re-drain progress lines** going forward, so item 1's derivation does not depend on prose. In `automate-loop/SKILL.md` §6 step 3, specify the exact start and terminal line text, for example:
   - `<ts> owned drain started (fix-now re-drain) — …`
   - `<ts> fix-now re-drain <READY|ESCALATED> (…)`

   Document both in `docs/result-schemas/automate-run.md` beside the `owned_drain_started` row. The `current_not_set` guard regex is unchanged; the start line still begins `owned drain started`.
4. **Prompt text (`automate-loop/SKILL.md` §6 step 2).**
   - Before asking, run `automate-helpers.sh dismissed-cost <runfile>` once per decision batch.
   - In every per-finding question's **Fix now on this PR** option description, state: "≈ <estimate> wall-clock: ONE owner-requested fix pass + full re-drain + re-park (<basis>)".
   - Show **Follow-up** as "0 min now (+ a future queue item)", and **Drop** as "0 min".
   - The recommended-first order (Follow-up) stays.
   - With `fix_now_reentered: true` the options are already Follow-up / Drop only, so no cost line is needed.
   - The §6 step 1 PICK-time pending-decisions ask (Follow-up / Drop only) is unchanged.
5. **Recording.** Append `fix_now_cost` to the decision's `## Progress` line as data, e.g. `… (est. fix_now_cost ≈ 1h06m, n=6)`, so a later item can measure estimate against actual. Change nothing else: `dismissed-decide`'s ledger row shape (`draft<TAB>decision<TAB>ts`), the decision enum `fix-now|follow-up|drop`, and the `--non-interactive-fallback` branch ("step 2 asks nothing and step 3 never runs") all stay as they are.
6. **Mirrors:**
   - `commands/automate.md`'s "Dismissed findings" bullet gains "(each fix-now option shows its derived wall-clock cost)";
   - the `automate-loop/SKILL.md` §1.5 helper table gains a `dismissed-cost` row;
   - regenerate `fixtures/automate-helpers-help.golden` (instruction in `test-automate-helpers-dispatch.sh`: "ADDING A SUBCOMMAND? Regenerate the golden in the same change").
7. **Token budget:** no budget change expected. `automate-loop/SKILL.md` is in no agent's `skills:` frontmatter, and `check-token-budget.sh` measures only agent `.md` files plus preloaded skills. Confirm with `bash scripts/check-token-budget.sh`.
8. **Item 04 (phase timing, future) will improve the estimate.** This item works standalone from the ledger plus `## Progress` derivation above. When item 04 lands, its per-phase timestamps may replace the progress-line matching, with the same output line.

## Acceptance criteria
- `automate-helpers.sh dismissed-cost <runfile>` prints exactly one `fix_now_cost:` line and exits 0 on all inputs, including a missing directory, an unreadable ledger, or zero samples.
- Fixture tests in `test-automate-dismissed.sh`:
  - the six spans in the Problem table give median ≈ 66 min, range 14 m–2 h 53 m;
  - the 09-30 out-of-order ledger row is dropped;
  - a > 12 h span is dropped;
  - pinned and legacy terminal wordings both match;
  - zero samples ⇒ the default line.
- §6 step 2 requires the cost in every fix-now option and shows follow-up as 0 min now. §6 step 3 pins the re-drain start and terminal line formats, mirrored in `docs/result-schemas/automate-run.md`.
- No change to the decision enum, to the ledger row shape, to `dismissed-pending`, or to the non-interactive branch: the existing `test-automate-dismissed.sh` cases pass unmodified.
- The help golden is regenerated, and `test-automate-helpers-dispatch.sh` is green.
- The zero-sample default line names its basis (another repo's baseline), never a bare number.

## Validation (must pass before merge)
1. `bash scripts/ci-local.sh` green.
2. The new `dismissed-cost` tests fail on the base commit (unknown subcommand) and pass on the branch. Mutation control: removing the end-before-start drop makes the 09-30 fixture fail.
3. `bash loomwright/scripts/automate-helpers.sh plan-waves .supervisor/requirements/throughput/02-fix-now-cost-at-decision.md --lint` prints `Touches ok; Depends on ok`.
4. Operator follow-up, not a merge gate: at the next interactive park with drafts, the question shows the derived cost, and the decision's `## Progress` line carries the estimate.

## Non-goals
- Changing the recommended option, the options themselves, or making fix-now unavailable.
- Making the decision for the owner or auto-picking by cost, interactive or not.
- Changing the non-interactive can't-ask branch or the PICK-time ask.
- Per-phase timing instrumentation (item 04).
- Reducing what a fix-now re-drain costs (items 01/03, implementation-quality/01).
