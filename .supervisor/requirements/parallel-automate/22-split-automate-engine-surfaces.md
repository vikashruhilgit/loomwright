# 22 — Split the `/automate` engine's shared surfaces, so engine items can run in parallel

## Status: pending

> **Origin (2026-10-07).** Owner decision relayed by S3 session 2216aefd: file #408's listed follow-up — split
> `automate-loop/SKILL.md` — kept out of `parallel-automate/11` on purpose because that file IS the engine, written as
> prose, so a split needs a step-by-step state-trace review. Owner then widened it in session f849e0cc after a
> measurement (below) showed the skill alone is not the only shared file: "split item covers all 4". Schedule early,
> right after `parallel-automate/05`.

## Problem
Every remaining engine item serializes one per wave because they all edit the same few files. Measured 2026-10-07 on
`main` `f4b0732` over the `## Touches` of the tail items (with `automate-loop/SKILL.md` already removed from the
comparison):

| Pair | Still shared without `SKILL.md` |
|---|---|
| af/34 ∩ pa/18 | `commands/agent-help.md`, `result-schemas/automate-run.md`, `scripts/automate-helpers.sh`, `fixtures/automate-helpers-help.golden`, `session-resume.sh` |
| af/34 ∩ S3 engine fixes (af/36) | the above + `commands/automate.md`, `automate-trail.sh` + test, `scripts/ci-local.sh` |
| pa/18 ∩ af/36 | the above + `meta-sync.sh` + test, `test-automate-helpers.sh`, `test-session-resume.sh` |
| Fleet operations (pa/21) ∩ pa/18 | `result-schemas/automate-run.md` only |

So splitting `SKILL.md` alone frees nothing. The hotspots are four surfaces:
1. `loomwright/skills/automate-loop/SKILL.md` (620 lines, §1–§13 + Anti-Patterns / Related / Quality Gates) — the
   engine protocol. 44 script references point at it (tests grep its text), so every parser must keep working.
2. `loomwright/commands/automate.md` (104 lines) — the command surface every engine item touches.
3. `loomwright/docs/result-schemas/automate-run.md` (108 lines) — §AUTOMATE_RUN: run-file layout, `## Status` enum,
   Queue convention, `## Current` fields, item lifecycle, crash-safety contract, JSONL breadcrumb.
4. The `automate-helpers.sh` usage header (39 `#   <subcommand>` lines) and its byte-for-byte `--help` golden
   (`fixtures/automate-helpers-help.golden`, checked by `test-automate-helpers-dispatch.sh` check 5) — any new
   subcommand or flag in ANY family file edits both, so pa/11's family split did not remove this overlap.

## Goal
After this item, two engine items that change different concerns (e.g. the sweep vs the backlog board vs the
fleet close) edit different files, so the wave planner can place them together. Behaviour is unchanged: this is a
move-only split plus generated indexes, like `parallel-automate/11`.

## Scope
1. **`automate-loop/SKILL.md` → a section split with an index.** Split by concern (recommended: resume §4–§5 /
   intake + per-item loop §2, §6–§8 / park, modes + merge gate §9–§10 / closeout + branch mode §11, §13 / run file
   §3 and invocation §12 may stay in the index), as `docs/result-schemas/` did for `RESULT_SCHEMAS.md`: the index
   keeps every `§N` anchor and heading people and scripts cite, pointing to the new file. Frontmatter and the skill's
   load behaviour (it is preloaded/cited by agents and commands) stay working — verify how the skill is loaded
   before choosing file names.
2. **`commands/automate.md`** → split the long "What This Does" / Parameters prose by the same concerns, or move the
   per-concern detail into the skill's split files and keep the command thin. Its frontmatter, `/automate` usage and
   the `/agent-help` mirror stay byte-compatible where tests pin them.
3. **`result-schemas/automate-run.md`** → split by section (run-file layout + Status enum + Queue / `## Current`
   fields / item lifecycle + crash safety / JSONL breadcrumb), index kept, every parser of the doc kept working
   (same rule pa/11 applied).
4. **The helpers usage header + golden** → per-family usage text: each `automate-helpers.d/<family>.sh` carries its
   own `#   <subcommand>` lines, the dispatcher's `--help` is assembled from them in the fixed family order, and the
   golden becomes one fixture per family (or a generated check), so adding a subcommand to one family edits only that
   family's files. `--help` output stays byte-identical to today's golden on this item's own branch.
5. **State-trace review (required — the engine is prose).** Before merge, trace the engine's paths through the split
   files: a fresh run (intake → PICK → per-item loop → park), RESUME (glob + reconcile, incl. a crashed run), the
   `--auto-merge` gate (all seven conditions), the dismissed-findings decision step, and closeout (watcher +
   `closeout-others` + finalize-empty). Each trace names the file and section it reads at every step; no step may
   point at a section that moved without its index entry. Paste the traces in the PR body.
6. **Every reference re-pointed** *(superseded 2026-10-07 by the anchor-index amendment below — re-point only references inside this item's own `## Touches`)*: the 44 script references, agent/command/skill cross-links, CLAUDE.md /
   ARCHITECTURE_CONTRACTS mentions, the `vendor-coupling-manifest.json` entries, and `check-doc-currency.sh` /
   `test-citation-drift.sh` pins. Then re-point every open item's `## Touches` (the post-pa/11 step, done by the
   operator after merge, as on 2026-10-07).
7. **Tests:** a byte-identity check that the concatenated split files reproduce the original text (move-only); every
   existing test passes with no assertion edited except path re-points; `--help` equals today's golden. **Mutation
   control:** dropping one index entry fails a test; removing one family's usage block changes `--help` and fails.

## Non-goals
Changing any engine behaviour, any gate, or any schema field. Splitting other files. Re-ordering engine steps.

## Acceptance criteria
- Re-running the 2026-10-07 overlap table over the open items' re-pointed `## Touches` shows af/34, pa/18 and the S3
  engine fixes no longer sharing the four surfaces above (they may still share genuinely common files — report them).
- `plan-waves --max 5 --explain` on the remaining queue places at least two of af/34, pa/18, af/36, pa/21 in one wave,
  or the PR states which shared file still prevents it.
- One real sequential `/automate` item runs end to end on the installed release that contains this split (the engine
  reads the split files at run time).

## Validation (must pass before merge)
1. Baseline full loop, `<passed>/<total>` and `SKIP` counts, base and branch.
2. Unchanged path: the move-only byte-identity check; `--help` byte-identical; no test assertion edited except
   path re-points (list them).
3. Running system: one real `/automate` item on this branch's plugin (`--plugin-dir`) through park; paste the run
   file's `## Current` and the lines showing the split files were read.
4. A failure this must catch: the two mutation controls in Scope 7.
5. Rollback: `git revert` (move-only).

## Amended 2026-10-07 — keep an ANCHOR INDEX; re-point only inside this item's Touches (owner choice (a), relayed by S3 session 2216aefd)
- **Why:** Scope 6 said "the 44 script references … re-pointed", but those scripts are not in this item's `## Touches`.
  One of them, `loomwright/scripts/session-resume.sh` (edited by `host-contract/02`), cites
  `skills/automate-loop/SKILL.md §6 "Post-merge close-out"` and `§"Branch mode"` in comments (verified 2026-10-07 on
  `main` `f4b0732`). Editing them would be undeclared Touches drift — the class agnostic/04 hit in S3 wave 2.
- **Change:** every split surface keeps an **anchor-preserving index** at its current path, the way
  `parallel-automate/11` kept `RESULT_SCHEMAS.md`: each pre-split `§N` / heading anchor stays resolvable at the old
  path (an index entry pointing to the new file, or the anchor left unchanged). This item re-points ONLY references
  inside its own `## Touches`; every other citation keeps resolving through the index. Re-pointing outside citations
  is follow-up work for each file's owner (pa/11's precedent). It does not edit the citing scripts and docs.
- **Acceptance (added):** after the split, every pre-split citation of the four surfaces (SKILL.md, commands/automate.md,
  result-schemas/automate-run.md, the helpers usage header) still resolves — an index entry or an unchanged anchor —
  checked by a test that collects the citations repo-wide and fails on a dangling one. **Mutation control:** removing
  one index entry that a citation uses makes that test fail.

## Evidence
Overlap table above (S3 operator session f849e0cc, 2026-10-07, from the `## Touches` of af/34, pa/18,
automate-followups/36 and parallel-automate/21 on `main` `f4b0732`). `parallel-automate/11` (#408) for the split
method and its follow-up note naming this file. `test-automate-helpers-dispatch.sh` header for the golden.

## Depends on
05-lane-coordinator.md

## Touches
loomwright/skills/automate-loop/SKILL.md
loomwright/commands/automate.md
loomwright/commands/agent-help.md
loomwright/docs/result-schemas/automate-run.md
loomwright/docs/RESULT_SCHEMAS.md
loomwright/scripts/automate-helpers.sh
loomwright/scripts/automate-helpers.d/config.sh
loomwright/scripts/automate-helpers.d/intake.sh
loomwright/scripts/automate-helpers.d/learning.sh
loomwright/scripts/automate-helpers.d/meta.sh
loomwright/scripts/automate-helpers.d/plan-waves.sh
loomwright/scripts/automate-helpers.d/reconcile-status.sh
loomwright/scripts/automate-helpers.d/resume.sh
loomwright/scripts/automate-helpers.d/runfile.sh
loomwright/scripts/fixtures/automate-helpers-help.golden
loomwright/scripts/test-automate-helpers-dispatch.sh
loomwright/scripts/test-automate-helpers.sh
loomwright/scripts/test-automate-trail.sh
loomwright/docs/vendor-coupling-manifest.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/skills/SKILLS_INDEX.md
CLAUDE.md
changelog.d/parallel-automate-22-split-automate-engine-surfaces.md
