# Folder stories outside .supervisor/requirements/ get their done stamp

## Status: done
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/852

Source: GitHub issue vikashruhilgit/loomwright#851. Found in Loomwright Studio probe p14 (#829) on Loomwright 17.34.1 and 17.34.2, in `vikashruhilgit/studio-sandbox` runs whose stories live in `stories/`.

**As an** owner running `/automate --folder <dir>` on stories kept outside `.supervisor/requirements/`,
**I want** each merged story stamped `## Status: done` by the normal post-merge close-out,
**so that** the next `--folder` run doesn't queue merged work again, and I don't have to stamp stories by hand or answer an `AUT-LEFTOVER` question that "Clean up now" can't clear.

### Problem (verified against 17.34.2)

1. `agents/launch-pad.md` Phase 2 step 0 sets `source_requirement` only for a goal path under `.supervisor/requirements/`. Any other repo file "is treated as a literal goal string", so Phase 5 step 3a writes no `- **Source requirement:**` line and Phase 5.5 passes no `--- SOURCE REQUIREMENT ---` block to Plan Reviewer.
2. The `/automate` driver hands Launch Pad the queued item only as a goal. Fresh phases use `/loomwright:launch-pad goal: <item>` (`scripts/automate-next-step.sh`, the Launch Pad spawn). `--inline-phases` uses `/autonomous --single-iteration --requirement <item>`, which passes the path to Launch Pad as its input.
3. `scripts/automate-trail.d/closeout.sh` step 5 ("requirement stamp") keeps a done brief only when `brief_requirement_pointer` equals the item. With no pointer it reports `closeout: skipped — no done brief`, and the item becomes an `AUT-LEFTOVER`. A re-run hits the same skip.

Evidence: `.supervisor/jobs/done/2026-11-08-add-farewell.md` in the sandbox names `stories/02-add-farewell.md` only in its title and prose. `brief_requirement_pointer` on it returns rc=1. `stories/02-add-farewell.md` on the sandbox's `main` still reads `## Status: ready` after PR #9 merged. Story 01 had the same skip and was stamped by hand (`f98b37b`).

## Acceptance Criteria

**Happy path**
- [ ] Given an `/automate --folder <dir>` run (fresh phases, the default) whose queued item is a story file outside `.supervisor/requirements/`, when the driver spawns the Launch Pad phase, then it hands Launch Pad the queued item path explicitly as the source requirement (not only as a goal string), and the saved brief's `## Environment` carries `- **Source requirement:** <the item path, exactly as queued>`.
- [ ] Given the same run under `--inline-phases`, when `/autonomous --single-iteration --requirement <item>` runs Launch Pad, then the saved brief carries the same `Source requirement` line.
- [ ] Given Launch Pad received an explicit source requirement, when it reaches Phase 5.5, then Plan Reviewer receives that story verbatim in the `--- SOURCE REQUIREMENT ---` block, as it already does for `.supervisor/requirements/` files.
- [ ] Given that item's PR has merged, when `closeout` runs, then step 5 stamps the story `## Status: done` (the existing close-out block: Completed, Brief, PR), and no `AUT-LEFTOVER` is raised for the stamp.
- [ ] Given that story is now stamped done, when a later `/automate --folder <dir>` run resolves its Queue, then the story is skipped as already done.

**Edge cases**
- [ ] Given a hand-typed `/launch-pad goal: "<path to a repo file outside .supervisor/requirements/>"` (no explicit source requirement from the driver), when Launch Pad runs Phase 2 step 0, then the goal stays a literal goal string and the brief carries no `Source requirement` line. The current rule for typed goals is unchanged.
- [ ] Given a queued item under `.supervisor/requirements/` (prompt source, folder source or backlog source), when the item runs end to end, then the brief, Plan Reviewer input and close-out stamp are the same as today.
- [ ] Given an explicit source requirement path that fails `test -f`, when Launch Pad resolves it, then it does not invent a file. It falls back as the current rule does for a missing `.supervisor/requirements/` path, and notes the fallback.

**Security / guard (must not loosen)**
- [ ] Given a brief whose `Source requirement` pointer is outside `.supervisor/requirements/` (for example `stories/02-add-farewell.md`), when `stamp-requirement-status.sh` or `reconcile-jobs.sh` reads it through `brief_requirement_path`, then the pointer is still refused exactly as today (`BRIEF_REQUIREMENT_PREFIX` unchanged; absolute paths, `..` and symlinks still refused), and neither script writes to that file.
- [ ] Given the change, `brief_requirement_path` and its two callers have no behaviour change; only the unguarded `brief_requirement_pointer` consumers (closeout, trail-pr, reconcile-status, lane remove) see the new pointer, and each of them matches it against a run-file item rather than writing to an arbitrary path.

## Non-goals
- Widening the guarded readers (`brief_requirement_path`, `stamp-requirement-status.sh`, `reconcile-jobs.sh`) to accept the run's `## Source` folder or any other root. Dropped at the Product Owner gate (see Owner decisions).
- Changing Launch Pad Phase 2 step 0's auto-resolution rule for hand-typed goals.
- Stamping stories with `## Status: brief-shipped` outside `.supervisor/requirements/`.
- Lane close-out losing stamps (`dismissed-followups/03`), a different path.
- Back-stamping stories from earlier runs (for example the sandbox's `stories/02-add-farewell.md`).

## Owner decisions
- 2026-11-08 (this session, before /product-owner): the driver passes the queued item path to Launch Pad explicitly as the source requirement, so a hand-typed goal that only names a repo file stays a literal goal string.
- 2026-11-08 (PO-ASSUME gate, "Refine requirements"): design point 2, letting the guarded readers accept the run's `## Source` folder, is dropped. Reason: those readers run offline on every SessionStart and SubagentStop with no run in hand, so they would have to trust run-file `## Source` lines, which in branch mode come from the meta branch. They are also not needed for the fix: the `done` stamp is written by closeout, which matches the brief against the trusted run-file item, and stamp-requirement-status already skips stories that carry a `## Status:` heading. The guarded readers stay unchanged and keep refusing an outside pointer, pinned by a test.

## Priority: MVP
**Rationale:** Every `--folder` run on stories outside `.supervisor/requirements/` silently loses its done stamp and re-queues merged work, and the `AUT-LEFTOVER` it raises can't be cleared by its own "Clean up now" option.

## Assumptions
- How the explicit source requirement reaches Launch Pad (a new Launch Pad flag, or a field in the driver's phase prompt) is a planning choice. Whatever form is chosen is documented in `commands/launch-pad.md`'s parameter table, and a hand-typed goal never sets it.
- The inline path's `/autonomous --requirement <item>` should count as an explicit source requirement. If it is cheaper to have `/autonomous` forward the explicit form, that is acceptable as long as the AC above holds.
- `closeout.sh` needs no change: its pointer match already handles a `stories/` path once the brief carries it (a leading `./` is stripped).

## Dependencies
- Depends on: none.
- Blocks: none.

## Risks
- **Mirror drift:** the Launch Pad rule is restated in `commands/launch-pad.md`, `skills/supervisor-readiness/SKILL.md` (the `Source requirement` field note) and `skills/autonomous-loop/SKILL.md` (PLAN step 1). All of them must change in the same PR (house rule: a restating copy is updated in the same change as its authority).
- **Prompt growth:** the Launch Pad agent and command docs have declared token budgets (`docs/prompt-token-budgets.json`, mirrored in `docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets"); `check-token-budget.sh` fails CI when one is exceeded.
- **History in prompts:** `check-prompt-history-refs.sh` fails a prompt that gains a history reference; the incident story goes in the changelog fragment, not the prompt.
- **Guard regression:** a planner may be tempted to widen `BRIEF_REQUIREMENT_PREFIX`. The guard AC and its test exist to catch that.

## Validation (must pass before merge)
1. **Static — close-out stamp for a folder story:** a test (in `scripts/test-automate-trail.d/` or `scripts/test-automate-next-step.d/`) builds a run whose `## Source` is a folder outside `.supervisor/requirements/`, a done brief carrying `- **Source requirement:** stories/<x>.md`, and a merged-PR fixture. It asserts `closeout` prints `closeout: stamped — stories/<x>.md`, the story reads `## Status: done`, and no `no done brief` leftover is recorded.
2. **Static — driver hands over the path:** a `scripts/test-automate-next-step.d/` case asserts the Launch Pad spawn instruction for a `stories/<x>.md` item carries the explicit source-requirement form, and a hand-typed-goal fixture does not.
3. **Static — guard unchanged:** `scripts/test-brief-pointer.sh` (plus `test-stamp-requirement-status.sh` / `test-reconcile-jobs.sh` where they cover it) asserts `brief_requirement_path` still refuses `stories/<x>.md`, an absolute path, a `..` path and a symlinked path.
4. **Static — repo gates:** `bash scripts/ci-local.sh --affected` passes, including `check-token-budget.sh`, `check-doc-currency.sh`, `check-prompt-history-refs.sh` and `test-citation-drift.sh`; `bash scripts/check-version-bump.sh` passes with a `changelog.d/` fragment.
5. **Running system — a real folder run stamps the story:** an `/automate --folder stories` run in a sandbox repo (like `vikashruhilgit/studio-sandbox`) on one story outside `.supervisor/requirements/`, merged through `--merge-parked` or by hand, ends with the story stamped `## Status: done` on `main` and no `AUT-LEFTOVER`. A saved brief shows the `Source requirement` line.

## Depends on
none

## Touches
loomwright/agents/launch-pad.md
loomwright/commands/launch-pad.md
loomwright/skills/supervisor-readiness/SKILL.md
loomwright/skills/autonomous-loop/SKILL.md
loomwright/scripts/automate-next-step.sh
loomwright/scripts/test-automate-next-step.d
loomwright/scripts/test-automate-trail.d
loomwright/scripts/test-brief-pointer.sh
loomwright/docs/prompt-token-budgets.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
changelog.d

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-11-09T02:24:58Z
- **Brief:** .supervisor/jobs/done/2026-11-08-folder-stories-get-their-done-stamp.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/852
