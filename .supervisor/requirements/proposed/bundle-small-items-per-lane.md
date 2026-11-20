# Bundle small, related `/automate` items into one lane so they share the fixed per-item cost — DESIGN ONLY (do not implement from this file)

## Status: proposed
## Evidence-set: none — hand-authored design doc, NOT a `propose-work.sh` candidate. The `evidence-set:` dismissal contract in `proposed/README.md` does not apply; promote or delete this file by hand.
## Origin: token-consumption investigation, 2026-10-28 (one of four levers: fix_floor HIGH trial · this · `--cheap` reaching lanes · per-item cost report)

## Problem (measured, 2026-10-28)
43 `/automate` lanes across loomwright + loomwright-studio, each matched to its PR:

| Bucket | Median changed lines | Median files | Median tokens/item |
|---|---|---|---|
| Small | 278 | 8 | **35.0M** (min 17.7M) |
| Medium | 1,210 | — | 52.5M |
| Large | 3,188 | — | 57.5M |

- Linear fit: **tokens/item ≈ 44M fixed + 6.3M per 1k changed lines** (r = 0.34 — weak, so read the intercept as "most cost does not track the diff", not as a precise constant).
- 11× the lines costs only 1.6× the tokens. The cost is the pipeline, not the change.
- Each item runs ~20 sessions (Launch Pad, plan reviews, Supervisor, workers, Phase 4.5 reviews and fix agents, the owned drain). **~38% of lane tokens is those sessions' starting context re-sent every turn** — paid per session, so per item.

Consequence: two small items cost ~2 × 35M = ~70M; one item carrying both is expected near the medium bucket (~52M) — a ~25% saving per pair, more for three. That expectation is extrapolated from the fit, not observed; the measurement plan below is what would confirm it.

## What already exists (verified from the files, `main` @ the session's base)
Bundling is not new. The plugin already has the read side and the write side; what it lacks is a rule that fires on the items that actually pay the floor.

1. **`automate-helpers.sh right-size`** (`automate-helpers.d/right-size.sh`, parallel-automate/18b, PR #675). Advisory, never a gate. Verdict per item from the companion-expanded `## Touches` count: `small` ≤ `right_size_small` (**default 3 files**), `large` > `right_size_large_files` (30) or > `right_size_max_parts` (7) Parts, else `ok`. A `small` verdict names up to 3 merge candidates (shared Touches path, same `## Depends on` chain, or same folder; candidates that would create a dependency cycle are refused). Printed at folder/backlog intake beside the Queue (`skills/automate-loop/intake.md` §"Size line at intake"), at the Product Owner persist step, and after `/propose` writes a draft. Its header cites the same floor at the dollar level (S2, 2026-10-05: a small fix ~$17 and 4 owner questions vs. large ~$40).
2. **`automate-helpers.sh merge-items`** — owner-invoked only, "never called by the engine" (`skills/automate-loop/helpers.md` row `merge-items`). Copies each original verbatim as `## Part <X> — <title>`, folds Status / Depends on / Touches into the merged item, stamps each original `## Status: parked (merged <date> into <X> as Part <P> — …)`, re-points dependents, all-or-nothing after a lost-line check, refuses done / operator-run / already-merged originals and cycles.
3. **It has been used:** 23 originals under `.supervisor/requirements/` carry the `parked (merged …)` stamp, folded into 10 merged items between 2026-10-05 and 2026-10-10 (e.g. `automate-followups/32-run-file-lifecycle.md` A–C, `meta-sync-followups/08-meta-sync-hardening.md` A–C, `automate-followups/39-engine-hygiene.md` A–C).
4. **The large precedent — #440** (`implementation-quality/02-iq01-and-throughput-merged.md`): owner merged 10 items (iq/01 + throughput/01–09) into one requirement / one `/automate` item / one PR on 2026-10-09; merged the same day. It needed hand-written merged-item rules (one changelog fragment, budgets/skill versions/vendor manifest reconciled once and last, per-Part validation evidenced per Part in the PR body, an explicit internal ordering + shared-file table). Its originals use a hand-written `parked — superseded by …` stamp, not `merge-items`' form.
5. **Product Owner wave shaping — #586** (`po-wave-shaping-scope-fence`, 2026-10-17): PO runs `plan-waves --max <n> --explain` on the set it just wrote, reshapes needless serialisation, names hotspot files, picks N; `wave-plan`/`wave-build` gained a warn-only same-wave file-overlap check. This shapes sets for **parallelism**, not for cost — it does not merge stories.
6. **`skills/user-story-writing/SKILL.md` §"Requirement Shape"** already states the goal ("small enough to review in one PR, large enough to pay the run's fixed cost") and the ceiling: one item ≤ ~30 files, ≤ 7 subtasks, ≤ 2 Parts per subtask — "a 10-Part item failed Plan Review three times on the 7-subtask cap, then its 4-Part subtask kept hitting the worker's turn limit."

### The gap this draft is about
- **The `small` threshold does not reach the items that pay the floor.** The measured small bucket's median item touches **8 files**; `right_size_small` is 3. So the typical 35M item reads `ok` and gets no merge suggestion.
- **Nothing acts on the suggestion.** `right-size` prints; `merge-items` waits for the owner to run it by hand. No intake step, no PICK step, no PO step turns "these are candidates" into one Queue item.
- **The stamp form matters for status.** `item-state` follows `parked (merged … into X)` to X's state (verified: an original of a merged item reads X's state), but reads the #440 originals' hand-written `parked — superseded by …` as plain `parked` (verified: `throughput/03-check-wait-under-bash-cap` → `parked`, though its work merged in #440). Any bundling path must write the `merge-items` stamp.

## Design options (for the owner — none chosen)

### A. Product Owner bundles at write time (shape, before files exist)
PO's shape decision already chooses one item / item-with-Parts / set. Add a cost rule: stories in one PO pass that share files or a dependency chain and are each under a size line are written as **one item with Parts** from the start (no originals, so no stamps to repair).
- + Cheapest: no new engine path; reuses the Parts form the planner, Plan Review and the 7-Part cap already understand.
- − Only covers prompt-sourced work. Folder/backlog queues written earlier (and `/propose` / dismissed-findings drafts) are untouched.

### B. Intake offers a bundle, owner confirms (folder/backlog/prompt intake, before `AUT-QUEUE`)
At intake, after the size line, group `small`-or-below items by `right-size`'s candidate rule and ask once per proposed bundle (new gate, e.g. `AUT-BUNDLE`: `Bundle` · `Keep separate`). On `Bundle`, intake runs `merge-items` and the Queue lists the merged item instead of its originals.
- + Covers every source; the owner sees each bundle; reuses `merge-items`' lossless write and stamp.
- − New question gate ⇒ needs a named can't-ask branch (CLAUDE.md §"Every question gate has a named can't-ask branch"): under `--non-interactive-fallback` either never bundle (safe default) or bundle per a config key. Changes `merge-items` from "never called by the engine" to engine-called — an invariant change, not a tweak.

### C. `/automate` bundles at PICK (runtime grouping, no file merge)
When the loop or `wave-plan` picks the next item, it also picks up to k compatible queued items and hands Launch Pad a synthetic multi-item brief; originals stay as they are and each is stamped done individually at closeout.
- + No requirement files are rewritten.
- − Largest change: Launch Pad, Supervisor, closeout, `item-state`, `measure.py` and the run file's one-row-per-item `## Queue` all assume one item = one file = one PR. Partial outcomes (Part A merged, Part B dropped) have no representation today. Highest risk of the three.

### D. Owner-marked bundle (manual, documented)
Keep the engine unchanged; lower `right_size_small` (or add a separate `bundle_below` key) so `right-size` flags the 8-file items, and document "run `merge-items` on the flagged pairs before `/automate`" in the intake text and `/backlog`.
- + Zero new behaviour; can be trialled this week with a config change and a hand merge.
- − Relies on the owner doing it every time — which is today's state, and today it mostly isn't done for ~8-file items.

A natural staging is **D now (trial), then A and/or B** if the trial shows the saving; C only if A/B leave a measured gap.

## Failure modes and how each option meets them
1. **One failing Part blocks the bundle.** A bundle is one PR: an ESCALATED Phase 4.5, a Plan Review FAIL×3, a rubric-gate park or a NO-GO parks every Part together (`per-item-loop.md` §"Termination" — every park stops the item). Mitigations to decide: bundle only items of the same risk class (`classify-risk.sh`); cap bundle size; a defined "split back out" path (re-stamp originals `pending`, delete or park the merged item) for a bundle that parks.
2. **Bigger diffs may draw more review rounds.** Since 2026-10-11, 3+ Phase 4.5 reviews rose to 61% of items (`.supervisor/cost-trials/fix-floor-high.md`); a larger diff gives each round more surface. If a bundle of two adds one review round, part of the saving is spent. This is exactly what the measurement must show (reviews/item, CI-bot comments/PR), not assume.
3. **The ceiling still binds.** ≤ 7 subtasks, ≤ 2 Parts per subtask, worker turn limit; `right_size_max_parts` = 7. #440's 10-Part shape needed bespoke merged-item rules and a first Launch Pad pass that only passed Plan Review on attempt 3/3. Bundles should stay well under the ceiling (2–4 Parts).
4. **Lane overlap / wave shape.** `plan-waves` serialises items whose Touches intersect; a bundle's Touches is the union of its Parts, so it conflicts with more of the wave and can lengthen the critical path. Rule of thumb to decide: bundle items that **share** files (they would serialise anyway — bundling removes a wave slot rather than adding a conflict); avoid bundling unrelated small items purely for cost, which widens the union for nothing. `wave-build`'s same-wave overlap check is warn-only and unaffected.
5. **Status stamps.** Today `closeout` stamps the requirement file it ran. With `merge-items`' form, originals resolve through `item-state` to the merged item's state, so the board stays right. With any other form (C's synthetic grouping, or a hand-written "superseded by") originals read `parked` forever. A bundle that merges with one Part dropped late has no stamp representation in any option today.
6. **Per-Part evidence and release surfaces.** One changelog fragment per bundle, token budgets / skill versions reconciled once (as #440 rule 1, 3–5) — or per-Part fragments folded by `bump-version.sh`. Either way the PR body needs per-Part acceptance evidence so a reviewer can tell which Part a finding belongs to.
7. **Dependencies.** `merge-items` refuses cycles; an item that depends on a Part of a bundle is re-pointed to the bundle and now waits for every Part.

## Owner decisions (open — not decided here)
- **Q1 Where does bundling happen?** A (PO write time) · B (intake offer) · C (PICK) · D (owner-marked, config + hand merge) · a staged combination.
- **Q2 What counts as bundle-eligible?** Keep `right_size_small` = 3 and add a separate key (e.g. `bundle_below_files`, ~10 to cover the measured 8-file median), or raise `right_size_small` itself? Size by files, by changed lines (only known after the fact), or by scope items/criteria?
- **Q3 Which relatedness is required?** Shared Touches only · same `## Depends on` chain · same folder · any (as `right-size` ranks today). Allow unrelated small items to be bundled for cost alone?
- **Q4 Maximum bundle size?** Parts per bundle (2? 3? 4?) and total files, given the 7-subtask / 2-Parts-per-subtask ceiling.
- **Q5 Risk mixing:** may a `high_risk` item ride in a bundle with low-risk ones (it would pull the whole bundle under the high-risk paths)?
- **Q6 Engine-called `merge-items`?** B and C make the engine write requirement files or synthesise briefs. Accept changing "owner-invoked only — never called by the engine", or keep every merge a human act?
- **Q7 Can't-ask branch** (B only): under `--non-interactive-fallback`, never bundle, or bundle per config?
- **Q8 A bundle that parks:** split back into originals automatically, on owner request, or never?
- **Q9 Release shape:** one fragment per bundle (#440 rule) or one per Part?
- **Q10 Stamp repair for #440:** re-stamp the 10 hand-written `parked — superseded by` originals into the `parked (merged … into X)` form so `/backlog` follows them? (Out of this draft's scope; listed because the gap was found here.)

## How to measure it
Tool: `python3 -I .supervisor/cost-trials/measure.py --since <run id> [--until <run id>]` — prints per lane: tokens, Phase 4.5 reviews, plan reviews, `claude` CI-bot comments, PR; and the summary line `tokens/item median/mean`, `Phase 4.5 reviews/item`, `plan reviews/item`, `CI bot comments/PR`.

Procedure:
1. **Baseline (unbundled):** the lanes since 2026-10-20 already in `fix-floor-high.md` (MEDIUM) — but see confounder 1; the comparable baseline is the first fix_floor HIGH waves.
2. **Bundled wave:** run one wave in which 2–3-Part bundles (built with `merge-items`, i.e. option D) sit beside unbundled items of similar size, same repo, same `fix_floor`, same model/`--cheap` setting. Record the run id.
3. **Compare per original item, not per lane.** `measure.py` assumes one lane = one item = one PR, so a bundle reads as one item. Divide each bundled lane's tokens by its Part count (read from the merged item's `## Part` headings) before comparing medians; report both the per-lane and per-original numbers.
4. **Success:** tokens per original item clearly below the unbundled median for comparable size; Phase 4.5 reviews per lane up by less than the saving; CI-bot comments/PR not clearly up; no bundle parked because of a single Part. Aim for ≥ 10 bundled originals before judging (the fix_floor trial uses ~10 items vs. baseline n = 13).
5. **Record** results next to the fix_floor trial in `.supervisor/cost-trials/` (a `bundle-trial.md`), not in this file.

Confounders to control:
1. **The fix_floor HIGH trial is live** (`.supervisor/config.json`, started 2026-10-28). Bundled and unbundled lanes must run under the same `fix_floor`, or the review-round effect of HIGH will be read as a bundling effect. Do not change that config for this trial.
2. **`--cheap` in lanes** and **the per-item report fix** are being changed in parallel sessions; note which were live for each compared wave.
3. **`measure.py` only sees lane runs** (project dirs matching `-lanes-automate-<run>-L…`) and cannot see the CI bot's tokens (not in local transcripts) — CI-bot comments/PR is the proxy.
4. The 2026-10-28 fit is weak (r = 0.34) and pooled two repos; compare within one repo.

## Non-goals
No change to the trusted-merge gate, Phase 4.5's review contract, the single-drain invariant, or `fix_floor`. No auto-merge of bundles. No implementation from this file.

## What "done" would look like (for the human who promotes this)
An implementable requirement in a real queue folder that answers Q1–Q9, names the chosen surface's files in `## Touches`, keeps `merge-items`' lossless stamp form for every bundle, gives any new gate its can't-ask branch, and carries the bundle-trial numbers that justified it.
