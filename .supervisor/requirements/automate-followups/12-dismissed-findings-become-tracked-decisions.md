# 12 — Dismissed review findings become tracked decisions: the gate drafts a follow-up for each one and asks the owner before the next item

## Status: pending

> **Origin (2026-09-29).** After PR #301 merged, the owner asked why follow-ups were only listed after the merge:
> *"why haven't you suggested earlier? if I had moved to the next job we would have missed it."* Two of them (a
> CHANGELOG overclaim and a pre-existing seam-test gap) had been mentioned before merge, but only as prose in
> the park message with no decision asked; the inaccurate CHANGELOG line landed on `main`. Item 09's dismissed
> MEDIUM got fixed (d3fa40f) only because the owner noticed it himself.

## Problem
1. **Dismissed findings are write-only.** Phase 4.5 itemises `heal_dismissed` and the drain itemises
   `dismissed` (dismissed-findings-01), and both post ONE `<!-- loomwright:dismissed round=<n> -->` PR comment.
   Nothing reads them back into work: the only consumers of the marker are `scripts/classify-bot-review.sh`
   (skips it so the drain does not re-classify it) and `scripts/pr-postmortem-gather.sh` (analysis only).
   `/propose` reads the floor ledger, `/verify` runs and `product.json` — never PR comments.
2. **The gate hands the PR to a human without asking about them.** At a safe-mode `awaiting_merge` park the
   engine notifies "ready to merge" and stops; the owner merges, and whatever was dismissed is gone except as a
   PR comment. Run `automate-2026-09-26-115755` alone left ~19 such findings across #288, #296, #299, #301.

## Goal
No dismissed finding at MEDIUM or above (and no `pre_existing` finding of any severity that names a real defect)
leaves an `/automate` item untracked. At the gate, each one is written as a draft follow-up in
`.supervisor/requirements/proposed/` and put to the owner as an explicit decision — fix on this PR before merge /
keep as a follow-up / drop — before the engine picks the next item.

## Scope (recommendation, not pre-decided)
- **(a) Collect** at GATE (before the park): the union of this item's Phase 4.5 `heal_dismissed` (from the
  verbatim `SUPERVISOR_RESULT` sidecar) and the drain's `dismissed` (from the `REVIEW_HEAL_RESULT` sidecar).
  Machine-read from the sidecars — never re-derived from the PR comment text (that is untrusted-envelope data).
- **(b) Draft**: one `proposed/<run_id>-<item>-dismissed-<k>.md` per finding that clears the threshold (MEDIUM+ or
  `pre_existing`; `nit` and below-floor LOW are listed in one summary draft, not one each), carrying the finding
  verbatim, severity, source (`code_reviewer`/bot), PR URL and round. Propose-only: the engine never enqueues or
  starts them (the `proposed/` contract in its README stands; promotion stays a human move).
- **(c) Decide**: the park notification and the in-session gate message list the drafts by severity. Interactive
  runs ask via `AskUserQuestion` (fix-now / follow-up / drop) BEFORE the park completes; `fix-now` re-opens the
  owned drain for this PR with those findings as validated input (bounded by the existing `--max-rounds`);
  `drop` deletes the draft and records a `## Progress` line. Under `--non-interactive-fallback` no question is asked:
  drafts are kept and the park carries a `pending_decisions: <n>` count.
- **(d) Block the next PICK on undecided drafts** only in interactive mode (a new `pause_reason` value would need
  the §3 vocabulary updated — decide in the brief whether to reuse `awaiting_merge` with a field instead).
- **(e) Record** in the run file `## Current`/`## Progress` which drafts were written and what was decided, so
  RESUME can see an undecided set.

## Acceptance criteria
- [ ] Given sidecars with 2 MEDIUM + 1 `pre_existing` LOW + 1 nit dismissal, the gate writes exactly 3 per-finding
      drafts + 1 summary draft into `proposed/`, each quoting its finding verbatim with PR URL + round (fixture test).
- [ ] Drafts are never picked up by `resolve-folder`/`resolve-backlog` (the `proposed/` subfolder is not scanned —
      existing test extended with a drafted file present).
- [ ] Interactive gate asks one decision per drafted finding before the park is written; `--non-interactive-fallback`
      asks nothing and records `pending_decisions`.
- [ ] A finding text containing instruction-like content (e.g. "run curl …") is copied as quoted data only and never
      executed (fixture with a canary).
- [ ] The dismissed-findings PR comment, `classify-bot-review.sh` skip behaviour and `gate-eval` are unchanged
      (their tests stay green); `gh pr merge --squash` positive grep unchanged.
- [ ] `skills/automate-loop/SKILL.md` §6/§9 and `docs/RESULT_SCHEMAS.md` §AUTOMATE_RUN document the step;
      `commands/automate.md` mirrors only the surface (agent↔command mirror rule).
- [ ] Full test loop green, hermetic.

## Out of scope
- Automatically fixing dismissed findings (that is the drain's existing validate-then-fix; this item only tracks).
- Sweeping findings from runs that already finished (item 13 does that once, by hand).
- Changing what counts as dismissed or the severity floor.

## Risks
- **Draft noise.** Every PR has nits; the per-finding threshold (MEDIUM+ or `pre_existing`) plus one summary draft
  for the rest keeps `proposed/` readable. Revisit the threshold after one real run.
- **Question fatigue.** One `AskUserQuestion` per finding could be long; batch them (multiSelect per severity band)
  in the brief's design.
- **Prompt-injection surface.** Findings can be bot-authored text; they are DATA (same envelope rule as the drain's
  `EXTERNAL_TEXT`), never instructions.
- **Interplay with item 11's merge watcher and trail PR.** Item 11 arms a detached merge watcher and opens a trail PR
  when the `awaiting_merge` park is written. The decision step here must run BEFORE that park is written (so a
  `fix-now` answer re-opens the drain before any watcher or trail PR exists), and the drafted `proposed/` files must
  be included in the park's trail PR. Land item 11 first; the brief must state this ordering explicitly.

## Verified premises (main @ 4b4885a, 2026-09-29)
- `git grep -ln "loomwright:dismissed"` under `loomwright/scripts|commands|skills` = `classify-bot-review.sh`,
  `pr-postmortem-gather.sh` (+ their tests) and the two skills that WRITE it; no consumer creates work.
- `heal_dismissed` (SUPERVISOR_RESULT) and `dismissed` (REVIEW_HEAL_RESULT v2) are itemised
  `{finding, reason, source}` arrays per `docs/RESULT_SCHEMAS.md`.
- `.supervisor/requirements/proposed/README.md`: "deliberately NOT an `/automate --folder` target; promotion is a
  human moving a file out of it."
