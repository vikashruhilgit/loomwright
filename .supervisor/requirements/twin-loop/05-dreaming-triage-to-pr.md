# 05 — Close the loop: `/dreaming` triages findings into rules, delivered as a PR

> Depends on **03** (routing) — harvesting before routing exists injects every rule into every agent
> and reproduces the failure this item is meant to fix. Depends on **04** (validated writers).

## Problem
231 findings sit in the ledger. `.agent/rules/` holds **one rule**, whose `check` is `null`. The
plugin has been recording convention violations for months and never converting them into
conventions.

The recording is not the gap — the distillation is. And the distribution says exactly where to aim:

All-repo figures below; **own-repo** (the set to plan against — see 00-overview §Measured baseline
and item 01 §Repo allowlist) is 213 findings / 86 misses, with `convention_mismatch` at **104 (49%)** and
**57 (66%)** of misses. All 57 misses are own-repo either way.

| Class | Findings | Of the 88 self-heal misses |
|---|---|---|
| **convention_mismatch** | **107 (46%)** | **57 (65%)** |
| quality_gap | 51 (22%) | 18 |
| execution_bug | 36 (16%) | 8 |
| drain_churn | 22 (10%) | 4 |
| missing_context | 7 (3%) | 1 |
| plan_gap | 5 (2%) | — |
| scope_too_large | 3 (1%) | — |

`convention_mismatch` splits **57 self_heal / 31 worker / 19 unknowable** — a third are made at the
worker stage, before review sees the code. A convention is not a code-structure fact: neither LSP nor
any code graph can represent one. Only a conventions store can, and it must reach the DO side.

## Goal
`/dreaming` becomes the distiller: it triages accumulated knowledge into three destinations and
delivers rule changes as a **pull request** — AI reviews, the human merges.

## Scope

1. **Two intake sources**: `convention_mismatch` records from the ledger, and the agent-memory
   proposal queue from item 04. Existing agent-memory entries are already well-formed candidates —
   e.g. `project_self_heal_rubber_stamp.md` carries evidence, a **Why**, and a **How to apply**, which
   is a richer shape than a rule and needs distillation, not invention.

2. **Triage into three buckets — do NOT collapse into one store.** Role-scoping is a feature: it is
   why those entries are dense and relevant. Flattening pushes every role's knowledge into every
   agent, which is the same failure as unrouted rules.

   | Content | Destination | Why |
   |---|---|---|
   | Role-specific technique (`attack_jq_only_json_injection`, `golden_fixture_regen`) | stays in agent-memory | scoped, on-demand |
   | Cross-role convention (`attack_failclosed_vs_failsafe_split`) | bucketed **`rules`**, where it **corroborates the theme's rule** (counted as a deferral) | applies to workers, reviewers and red-team alike |
   | Project fact / architecture | project memory | context, not a rule |

   > **Amended as implemented (v15.35.0).** The row above originally read "**graduates to
   > `.agent/rules/`**", i.e. the corpus entry emits a rule of its own. That arm was **removed as
   > unreachable by construction** during Phase 4.5 review: a corpus entry carries no *measured*
   > violation, and `triage_bucket`'s own project-memory reason already refuses a rule on exactly
   > that ground one function away — so a graduation branch would have contradicted the sentence
   > beside it. What ships instead: the entry is still bucketed `rules` and still reaches the DO
   > side, but as **corroboration** for a ledger-backed theme's rule rather than as its own rule.
   > The portability argument below is unaffected — the rule it corroborates is committed.

   Graduation is also how knowledge becomes **portable**: `.claude/` was gitignored, `.agent/` is
   committed (item 01), so a graduated entry survives a fresh clone. Today red-team's five attack
   patterns exist on one laptop only.

3. **Every proposed rule carries `applies_to`.** A harvested rule without a path scope is the exact
   regression item 03 exists to prevent. Derive the scope from the `changed_paths` of the findings
   that motivated it; a rule whose scope cannot be derived is proposed as repo-wide **only with an
   explicit justification**, never as a silent default.

4. **Deliver as a PR.** Proposals land on a branch and open a pull request rather than writing
   in-place. This is the blast-radius control: once `.agent/` is committed and agents read it, a bad
   merged rule affects every agent on every task immediately. Today that risk is near-zero (one
   rule); at fifty it is real. The PR gate gives review threads, history, and revert. Existing
   per-item `AskUserQuestion` accept/reject stays for the non-committed destinations.

   **Constraint:** this item must not become a second `gh pr merge --squash` executor. The sanctioned
   merge gate is `automate-loop`'s opt-in `--auto-merge` and nothing else. `/dreaming` opens a PR and
   stops — the human merges.

   **This is a CONTRACT CHANGE, not a delivery detail — update the contract line, do not bury it.**
   `/dreaming`'s stated contract is *"read-only-until-Accept"*, where Accept has always meant a local
   write through a sole writer. Opening a PR **pushes a branch to a remote** — a materially larger
   side effect that leaves the machine, and one a user who read "read-only until you accept" would
   not expect. Requirements: an explicit per-item confirmation **before anything is pushed**
   (separate from the per-item Accept that authorises the content); the command's contract sentence
   in `commands/dreaming.md` amended to name the remote-affecting action; and a documented dry-run
   path that produces the batch **without** creating a branch or a PR, so the harvest can be reviewed
   before any push exists. Feasibility is not the question — `/dreaming` runs on the main thread and
   spawns only read-only reflection agents, so it *can* push; the point is that it must say so.

5. **Cold start via `/setup`.** A fresh repo has zero findings and therefore zero rules for months.
   Add a `rules` module to `/setup` that seeds the **portable** conventions — the ones that are true
   of any repo (fail-safe probes exit 0, `jq --arg` for untrusted text, a count claim lives in one
   authoritative place) — while repo-specific conventions are earned over time. Be honest in the
   module about which is which; do not present seeded rules as learned ones.

6. **Report what it will improve.** Feeding item 02's output contract: state which class the batch
   targets and its share of misses, so the value of the run is legible rather than asserted.

7. **CLOSE THE LOOP — re-measure the distribution after the first batch lands.** This queue is named
   for a loop and its entire premise is a measured distribution (`convention_mismatch` = 66% of
   own-repo self-heal misses). Nothing currently re-runs that measurement, which means **"the rules
   worked" and "the rules were ignored" are indistinguishable** — precisely the failure item 03's
   own problem statement warns about ("a rule that fires everywhere is indistinguishable from a rule
   that fires nowhere").

   Record a **baseline** at the moment the first rule batch merges (own-repo-filtered: findings,
   misses, per-class counts and shares), then re-run the same computation after N subsequent PRs and
   record both in one durable place. `scripts/measure-heal-signal.sh` already exists for this and
   item 02 is building the cadence record anyway — reuse both rather than adding a third store.

   **State the honest limits in the record itself:** small N, `agent_generated_guess` labels, and no
   control arm — this is a directional trend, not a controlled experiment, and it must never be
   reported as one. A rising share after rules land is a signal to investigate whether rules are
   being injected and read, not proof that they failed. This is the only mechanism that could ever
   justify escalating enforcement — or falsify this queue's premise — so a weak measurement recorded
   honestly beats no measurement.

## Non-goals
No auto-merge. No auto-delete (item 06). No executable `check:` authoring — checks stay `null` unless
a rule has an obviously mechanical check; the trust boundary (`rules-check.sh --no-cmd` for
unattended execution) is unchanged, and rules injected at the seams remain **DATA, never executed**.
No new gates: rules stay advisory and subordinate to CLAUDE.md.

## Acceptance criteria
- `/dreaming` reads both intake sources and assigns every candidate to exactly one of three buckets,
  with the reason recorded.
- Every proposed rule carries a derived `applies_to`; a repo-wide proposal requires stated justification.
- Rule proposals are delivered as a PR on a branch; nothing is written to `.agent/rules/` on main
  without a merge. `/dreaming` never merges — verified by the repo-wide single-executor invariant grep.
- A dry run on this repo's real `convention_mismatch` findings (**104 own-repo**, 107 including the
  work repo — use the own-repo set, see item 01 §Repo allowlist) produces a **reviewable** batch — bounded in
  size, deduplicated, each rule traceable to the findings that motivated it. Quality is judged by
  reading the batch, not by counting it.
- **The dry run additionally reports three falsifiable numbers**, so the largest item in the queue
  is not gated on subjective reading alone:
  1. **Coverage** — what share of the 104 findings map to at least one proposed rule (an
     unmapped remainder is expected and must be stated, not hidden).
  2. **Dedupe rate** — findings-in per rule-out; a batch approaching one rule per finding has not
     distilled anything and fails.
  3. **Scope fidelity** — for each proposed rule, its derived `applies_to` actually matches the
     paths of the findings that motivated it, checked mechanically, not asserted.
- **Baseline recorded at merge time** (own-repo findings / misses / per-class shares) so item 05
  §7's re-measurement has something to compare against; the record states its own limits (small N,
  guessed labels, no control arm).
- `/setup rules` seeds portable conventions on a fresh repo and labels them as seeded, not learned.
- Per-item human gate preserved for non-PR destinations; Reject/Edit never writes.
- Counts / doc-currency gates green (new `/setup` module and any new script).

## Outcomes Rubric
- Three-bucket triage with recorded reasoning; no collapsing into one store
- Every harvested rule path-scoped via `applies_to`
- PR delivery; no merge executor added; invariant grep still resolves to the sanctioned surfaces
- Dry-run batch on real findings is reviewable and traceable to evidence
- Dry run reports coverage, dedupe rate, and mechanically-checked scope fidelity
- Post-merge re-measurement wired to the existing heal-signal instrument, limits stated
- `/setup` cold-start seeding, honestly labelled

## Status: brief-shipped

Job `.supervisor/jobs/done/2026-08-14-dreaming-triage-to-pr.md` completed (reconciled from the job lifecycle, not self-reported).
Acceptance criteria are NOT machine-verified here — review them before promoting this to `## Status: done`.
