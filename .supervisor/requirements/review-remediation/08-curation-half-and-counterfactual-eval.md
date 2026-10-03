# 08 — Knowledge curation (supersession/decay) + counterfactual eval of the advisory loop (P2, strategic)

## Goal
Ship the missing write/curation half of the Twin (north-star Bet 4) and produce the first
evidence that the advisory loop pays for itself (Bet 5). Two deliverables, sequenced:
curation first (it cleans the corpus the eval will measure), then a small A/B eval.

## Evidence
- North-star doc (docs/SPIKES/NORTH_STAR_DIRECTION.md, Bet 4): anti-rot (dedup,
  supersession, decay), unlearning, net-positive token budget, counterfactual eval — all
  listed as "the missing piece". 2026-07-05 review confirmed: memory/lessons/churn/rules
  corpora are append-only; nothing supersedes, decays, or deletes. Advisory signals will
  eventually be poisoned by stale entries.
- Bet 5 status: System Twin foundation shipped; loop-value proof not attempted.

## Part A — Curation (run through /product-owner → /launch-pad first; design decisions ahead)
Target corpora (each has a sole-writer script today — curation must go through the same
writers or a new sibling curator script, never direct edits):
- `.supervisor/postmortem/results.jsonl` (churn ledger), lessons store (write-lessons.sh),
  project memory (write-project-memory.sh), `.agent/rules/*.json` (add-rule.sh),
  System Twin contracts (write-system-contract.sh).

Mechanisms to design (per-corpus, pick minimal viable subset in the brief):
1. **Supersession**: a new entry can name the entry it replaces; readers (read-postmortem.sh,
   read-lessons.sh, read-rules.sh, read-project-memory.sh) serve only the head of a
   supersession chain. Additive field, old readers unaffected (fail-safe-skip unknown fields).
2. **Decay/staleness**: entries carry as-of provenance (many already do); readers annotate
   or drop entries older than a per-corpus TTL (churn: N months / M releases; lessons:
   existing 90-day cache is precedent — align, don't duplicate).
3. **Unlearning**: a `/rules` -style human-gated `retract` verb (extend the relevant
   command: `/dreaming` already has per-item approval UX — reuse that pattern) that writes
   a tombstone via the sole writer. Never silent deletion; tombstones are auditable.
4. **Net-token budget**: each reader already bounds output; add a per-corpus size warning
   in /insights (advisory line: "corpus X: N entries, Y superseded, Z stale").

Invariants: all advisory seams stay never-gating; readers stay fail-safe (malformed
curation metadata ⇒ treat entry as live, never crash); sole-writer + atomic-write +
parse-gate discipline identical to add-rule.sh; nullable-required fields get presence
checks (memory: PR #84 lesson); every new writer path gets a test-*.sh.

## Part B — Counterfactual eval (after Part A merges)
Smallest honest experiment:
1. Pick 6–10 completed historical requirements (from `.supervisor/jobs/done/` + merged PRs)
   whose runs used advisory seams.
2. Define the metric before running: review rounds to READY (from /pr-postmortem +
   fix_cycles), Phase 4.5 heal_iterations, rubric score where present.
3. Re-run a sample (3–5) via /autonomous in a scratch branch with advisory seams disabled
   (needs a temporary `--no-advisory` master switch, or per-seam env gates — design at plan
   time; the switch itself must be default-ON-advisory, opt-out only, and removed or kept
   per result) vs enabled, same requirement text.
4. Record results in `docs/SPIKES/ADVISORY_LOOP_EVAL.md`: per-run table + verdict.
   Decision rule stated up front: if seams show no measurable benefit, cut the losing
   seams (per north-star "prove the loop works — or cut it"); if they do, the number goes
   in the marketplace description at the next release.

Constraint: eval is read-mostly + scratch-branch only; no PRs to main from eval runs;
token cost is bounded (cap at 5 re-runs); note the OAuth-token constraint from the
deferred eval-harness memory if any API-based harness is considered — prefer in-session
/autonomous runs instead.

## Acceptance criteria
- [ ] Part A brief produced via /product-owner + /launch-pad with Outcomes Rubric;
      per-corpus mechanism choices explicit; Plan Review PASS before execution.
- [ ] Supersession + staleness live in ≥2 corpora (churn ledger + lessons recommended
      first) with reader tests proving: superseded hidden, stale annotated, malformed
      metadata fail-safe.
- [ ] `retract` verb human-gated, tombstoned, tested.
- [ ] ADVISORY_LOOP_EVAL.md exists with pre-registered metric, ≥3 paired runs, and an
      explicit keep/cut verdict per seam.

## Out of scope
Phase 5/6 brain read-path consolidation & write-back (separate roadmap track),
applies_to path-scoped rules, any gating behavior for advisory signals.

## Status: done
- Completed 2026-07-07 via /automate item 08 → PR #98 (v15.7.0). Part A shipped; Part B paired runs pre-registered (docs/SPIKES/ADVISORY_LOOP_EVAL.md), pending post-merge.
