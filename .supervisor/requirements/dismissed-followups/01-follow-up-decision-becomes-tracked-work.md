# A `follow-up` decision on a dismissed finding becomes tracked work, not a silent pile

## Status: pending

> Written 2026-10-27 by an owner-requested triage session. On that date `.supervisor/requirements/proposed/`
> held 177 `/automate` dismissed-finding drafts, all `- **Decision:** follow-up`, holding 369 findings, and
> none of them had been acted on. On 2026-10-01 the pile was 20 drafts. It was cleared by hand then (PR #343,
> which bundled 4 drafts into `automate-followups/21`) and has grown about 9x since. The one-off sweep of the
> 177 is this queue's items 02+. This item is the **prevention**. Its part D (the honest option note) shipped in the triage PR.

## Root cause (verified on `main` 84d9023)

The decision step offers **Follow-up (keep draft)** with the option note `0 min now (+ a future queue item)`.
Both copies are in `scripts/automate-next-step.sh`, in `ns_pending` and in the PICK-time `AUT-PENDING` batch.
Nothing creates that queue item. After the answer:

1. `dismissed-decide … follow-up` (`scripts/automate-dismissed.sh`) appends a ledger row and rewrites the
   draft's `- **Decision:**` line, and does nothing else.
2. `dismissed-pending` counts only drafts whose decision **starts with `undecided`**, so a follow-up draft
   leaves the one surface that ever asks about it.
3. `dismissed-drafts` emits `keep` for a follow-up name and never rewrites or recreates it, so the draft
   stays frozen in `proposed/` for good.
4. Intake skips it on purpose: `resolve-folder`/`is_not_ready` skip `## Status: proposed`, and
   `proposed/README.md` says `proposed/` is not an `/automate --folder` target.
5. `/backlog` (`automate-helpers.d/backlog.sh`, precedence step 1) reads every file under `proposed/` as
   `proposed`. It lumps a follow-up draft in with undecided drafts and hand-written proposals, and shows no age.

So **"follow-up" records a decision but creates no tracked work item**. The one promotion path is a human
moving a file out of `proposed/`, and nothing prompts that. The option note promises work that nothing makes:
a claim no check backs.

## Design (owner-chosen, human-gated, propose-only preserved)

**A. `/backlog` state `follow_up`, with age.** Add `follow_up` to `_BL_STATES`. It applies to a file under
`proposed/` matching `*--dismissed-*.md` whose first `- **Decision:**` value is `follow-up`. Evidence is
`follow-up <N>d — run <run_id>, PR <url>`. The age comes from the decision ledger's `ts` when the ledger is
readable, else the draft's mtime, labelled `(mtime)`. Undecided drafts and hand-written proposals stay
`proposed`. Totals still sum to the item count. `--state follow_up` filters as usual. This is read-only, like
the rest of the board.

**B. Promotion verb: `automate-helpers.sh followup-bundle <draft>... --into <queue-dir>/<NN-slug>.md [--confirm]`.**
- Without `--confirm` it prints the requirement file it would write and writes nothing.
- With `--confirm` it writes ONE requirement file, `## Status: pending`, with this layout. A provenance quote
  names each source draft, run, PR and `Key`/h8. Then a `## Findings` list in which each finding's text is
  quoted `> `-prefixed as untrusted data, never interpolated into a heading or command. Then
  `## Acceptance criteria` (re-verify each on `main`, then fix or record as not reproducible), `## Depends on`
  (`none`) and `## Touches` (the union of the drafts' `## Touches`, else `unknown`). After that it removes the
  source drafts. The ledger already holds their `follow-up` row, so `dismissed-drafts` never recreates them.
  It appends one `dismissed: bundled <draft> → <file>` `## Progress` line when the draft's run file still
  exists, and skips that silently when it does not.
- It refuses, and writes nothing, for: a draft that is not a regular `*--dismissed-*.md` file directly under
  `proposed/`, a draft whose decision is not `follow-up`, an `--into` path outside `.supervisor/requirements/`
  or inside `proposed/`, and an existing target file.
- It never enqueues, dispatches or runs anything. The owner runs the new file with `/automate --folder` as
  with any other queue item.

**C. Nudge (advisory, fail-SAFE, always exit 0).** At the interactive PICK, beside the pending-decisions ask,
and in `session-resume.sh` on `startup`, print one line when there is at least one follow-up draft and the
oldest is older than `LOOMWRIGHT_FOLLOWUP_NUDGE_DAYS` (default 14):
`automate: <n> follow-up drafts, oldest <d>d — /backlog --state follow_up, then followup-bundle`.
It never asks and never blocks.

**D. Make the option note true: shipped in the triage PR, not part of this item.** Both copies of the note now
say what happens: the draft is kept in `proposed/`, and nothing is enqueued. Once A and B land, extend the note to name
the `follow_up` board state and `followup-bundle`, and update `test-automate-dismissed.sh` C8 in the same change.

**Rejected:**
- (a) Have the `follow-up` decision itself append to a per-queue follow-up requirement. That auto-enqueues
  runnable work from one in-flow click, and 177 of 177 decisions show the click is used as "not now", so it
  would flood `/automate --folder` queues with LOW-severity work and break the propose-only contract.
- (b) Re-classify drafts older than N days against `main` automatically. That needs an LLM pass per tick, and
  the owner still has to decide on its verdict. Run it on demand as a sweep, as this queue's items 02+ do.

## Acceptance criteria
- [ ] `backlog`/`item-state` read a follow-up dismissed draft as `follow_up` with an age, and read undecided
      and hand-written `proposed/` files as `proposed`. The legs live in `test-automate-helpers.d/` and cover
      ledger ts, mtime fallback, an unreadable ledger (falls back to mtime and says so) and the totals sum.
- [ ] `followup-bundle` dry run writes nothing. `--confirm` writes exactly one file and removes exactly the
      named drafts. Each refusal case has a leg. A follow-up draft removed this way is not recreated by a
      re-run of `dismissed-drafts` for its run and item.
- [ ] Finding text containing a backtick, `$(…)`, a heading `#` line or a fake `## Status: done` stays quoted
      data in the bundle and does not change the file's status.
- [ ] The nudge line prints exactly once under its condition and never otherwise. Its exit code is always 0.
- [ ] The follow-up option note (made honest in the triage PR) names the `follow_up` state and `followup-bundle`.
- [ ] `proposed/README.md` (and its fixture `scripts/fixtures/proposed-readme/README.md`), `commands/propose.md`
      §Promote, `commands/backlog.md` and `skills/automate-loop/per-item-loop.md` §"Dismissed-findings decision
      step" name the `follow_up` state and `followup-bundle`.
- [ ] `bash scripts/check-version-bump.sh` passes (a `changelog.d/` fragment, no hand version edits).

## Depends on
none

## Touches
loomwright/scripts/automate-helpers.d/backlog.sh
loomwright/scripts/automate-dismissed.sh
loomwright/scripts/automate-helpers.sh
loomwright/scripts/automate-next-step.sh
loomwright/scripts/session-resume.sh
loomwright/scripts/test-automate-dismissed.sh
loomwright/scripts/test-automate-helpers.d/
loomwright/scripts/fixtures/proposed-readme/README.md
loomwright/commands/backlog.md
loomwright/commands/propose.md
loomwright/skills/automate-loop/per-item-loop.md
