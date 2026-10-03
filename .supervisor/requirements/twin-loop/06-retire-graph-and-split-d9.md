# 06 — Retire the graphify tier and split D9 by regenerability

## Problem — the tier is dead, and its maintenance model is why

Measured 2026-08-06:
- `graphify-out/graph.json` is **absent**. Built once on 2026-06-22 at `f5e10d6`, gitignored, never
  rebuilt in this checkout.
- `.supervisor/bridge/bridge.json` (138 KB) **survives as an orphan** — `built_at_commit: f5e10d6`,
  `graph_fresh_vs_head: false`, **255 commits** behind `HEAD`.
- `read-bridge.sh` emits **nothing**: line 124 is `[ -s "$GRAPH" ] || exit 0` — "a bridge without a
  graph is meaningless". Confirmed by running it against a real path.
- brain-context Signal 1 (`test -e graphify-out/graph.json`) does not fire.
- `brain_context` appears **0 times** across all `.supervisor/logs/*.jsonl`. Not one run has recorded
  consuming this tier.

The value was never the problem — the Step-4 gate scored 71% strict specific-area, above its ≥50%
bar. The **maintenance model** is: the graph is the only store in the system requiring an expensive
deliberate rebuild to stay true, it is gitignored so it does not survive a clone, and it degrades
silently. NORTH_STAR named this exact hazard ("vendors sell the all-in-one graph; it's the staleness
trap") and the tier then fell into it.

Two further facts settle it rather than merely arguing it:
1. **The 71% has no control arm.** The gate compared graph-linked context against *no context*, never
   against a plain **file-path join**. Every strict hit the doc verifies is anchored by a shared file
   (`skills/review-heal/SKILL.md` for seven PRs, `skills/autonomous-loop/SKILL.md` for two, and so
   on) — matches a `changed_paths` grep would also have found. No file-disjoint community hit is
   demonstrated anywhere in the record.
2. **It targets the wrong class.** `convention_mismatch` is 65% of all-repo self-heal misses and
   **66% own-repo**; `missing_context` — the tier's actual target — is **1.9% own-repo, one single
   miss** (see 00-overview §Measured baseline). A semantic code
   graph cannot represent a convention. The rules substrate (items 03–05) can, is always fresh,
   committed, and portable — it is a *better* implementation of the same job.

## Goal
Remove the graphify/bridge tier cleanly, and replace the blanket no-auto-delete rule with one split
on whether an artifact is actually regenerable.

## Scope

1. **Delete the orphaned artifacts** — `.supervisor/bridge/{bridge.json,bridge.md}`. Safe under the
   new D9 (below): they are derived, and their source is already gone.
2. **Unwire the three seams** — this is a real removal, not an `rm`. Verify each against the file:
   - `skills/brain-context/SKILL.md` — Signal 1 and the "Bridge read" section
   - `skills/self-heal-advisory/SKILL.md` — Phase 4.5 step 1d
   - `agents/launch-pad.md` — Phase 3 consult and the Phase 5 risk row
   Grep repo-wide for `read-bridge`, `build-bridge`, `graphify-out`, `bridge.json`, `GRAPH_PRESENT`
   before claiming the sweep is complete. Preserve the enrichment ladder's silent-fallback behaviour:
   removing a rung must not change any caller's success path.
3. **Decide the scripts explicitly** — `build-bridge.{sh,py}`, `read-bridge.sh`, `test-build-bridge.sh`,
   `twin-graph.sh`, `test-twin-graph.sh`. Delete or retain-as-dormant, stated with a reason, not left
   ambiguous. If deleted, the `ci.yml` `test-*.sh` glob and any budget/count mirrors update in the
   same change.
4. **Split D9.** `FINAL_STATE_GOAL.md:40` currently reads *"Nothing auto-deletes; flag-only remains
   the rule."* Too broad. Replace with a rule keyed on regenerability:

   | Kind | Auto-delete? | Why |
   |---|---|---|
   | **Derived** — bridge, graph, insights dashboard, `state.md` | **Yes, freely** | genuinely rebuilt on demand |
   | **Distilled** — lessons, rules, agent-memory, project memory | **No** | not recoverable (see item 01): the stores *and* their source logs were gitignored, and only ~3 months of logs survive an 84-PR history |

   Record it as an amendment with its reasoning — do not silently rewrite the decision.
5. **Preserve the evidence.** `CODE_GRAPH_OWNERSHIP.md` and `LOCAL_TWIN_PATH.md` are **not** deleted.
   They deliberately keep retracted claims with ⚠️ corrections — that record is why an unfair
   "graphify 0/10" test could be identified as unfair. Add a status banner marking the tier retired,
   with the reason and the missing-control-arm finding, and keep the evidence intact.
6. **State the honest reversal condition.** If concept-retrieval is wanted later, the requirement is a
   **cheap incremental refresh**, not a manual rebuild — and it must pass the validation harness the
   code-graph spike deliberately kept for exactly this.

   **The harness is currently unciteable, and that must be fixed here or the condition is void.**
   `validate.py` and `validate_gen.py` live in `.supervisor/scratch/code-graph-spike/` — inside the
   **gitignored** `.supervisor/`. So the reversal condition, as first written, depends on files that
   do not survive a `git clone`, on a machine where the graph itself already vanished by exactly
   that mechanism. Resolve it explicitly, one of:
   - **commit the harness** (e.g. under `loomwright/scripts/` or a committed spike directory) as
     part of this item, so a future revival can actually be held to it; or
   - **restate the condition** in terms that do not cite gitignored files — i.e. name the property
     the revival must demonstrate (ranking validated against an independent ground truth), not the
     script that measured it.

   Committing the harness is preferred: the entire argument for retiring this tier is that
   ungoverned, unreachable artifacts rot silently, and leaving the reversal gate in the same
   condition would repeat the error inside the item that names it.

## Non-goals
No rebuild of the graph. No replacement retrieval system. No deletion of spike docs or of any
distilled store. No change to LSP wiring.

## Acceptance criteria
- Orphaned bridge artifacts deleted; no path in the repo still reads them.
- All three seams unwired; repo-wide grep for the five terms returns only historical/spike-doc
  mentions, each intentional.
- Every caller of the enrichment ladder behaves identically before and after — traced, not assumed.
- Script disposition decided and justified; CI globs, budgets, and counts consistent; all gates green.
- D9 amended with the regenerability split and its reasoning; every surface restating the old
  blanket form is swept (grep the phrase and its variants, not just the exact sentence).
- Spike docs retained with status banners; the no-control-arm finding recorded.

## Outcomes Rubric
- Tier removed at every seam, ladder fallback behaviour unchanged
- Script disposition explicit, CI consistent
- D9 split recorded with reasoning, old form swept including variants
- Evidence docs preserved and banner-marked, not deleted
- Reversal condition stated (incremental refresh + harness), not left implicit, and the harness it
  cites is reachable from a fresh clone — or the condition is restated without citing gitignored files

## Status: brief-shipped

Job `.supervisor/jobs/done/2026-08-17-retire-graphify-tier.md` completed (reconciled from the job lifecycle, not self-reported).
Acceptance criteria are NOT machine-verified here — review them before promoting this to `## Status: done`.
