# Loop Evidence 2026-07 — first real read-back of the unattended-quality funnel

**Status:** recorded — dated snapshot of REAL accumulated data (not a pre-registration; not a live dashboard)
**Date:** 2026-07-21
**Provenance:** "Prove the Loop" job, subtask 4 (`st/loop-evidence-verdict`). Data produced by
`loomwright/scripts/build-loop-evidence.sh` (subtask 1 of the same job) run READ-ONLY against the
main checkout's gitignored `.supervisor/` state dir. The funnel definition below is adapted from a
draft north-star memo (`.supervisor/requirements/twin-remediation/salvage/NORTH_STAR.md`, gitignored)
— credited here as a useful draft, with one **correction**: that draft claimed `.supervisor/logs/`
and `postmortem/results.jsonl` were "effectively empty and never read back." That premise is
**false** — it was authored in a git worktree, where gitignored `.supervisor/` state simply does not
exist (a known worktree trap). The real state dir holds 41 session log files (27 deduplicated
`session_end` runs), 74 postmortem lines, and 4 heal-signal trend points. This document IS the first
read-back. Sibling records: `ADVISORY_LOOP_EVAL.md` / `FABLE_PARITY_EVAL.md` (the pre-registered
counterfactual protocols this snapshot does NOT replace), `NORTH_STAR_DIRECTION.md` (the
evidence-priced-surface-area discipline this snapshot serves).

> **This is a dated snapshot.** Every number below is as-of 2026-07-21. Nothing here is a claim
> about the current plugin version; era thresholds (rules seams ≥ 15.1.0, orientation memos
> ≥ 15.12.0) are historical ship facts, not current-version claims.

---

## 1. The funnel (definition)

The harness exists to turn a goal into **merged, correct software with as little human attention as
possible**. The metric that matters is the **unattended-quality rate**: of runs launched, the
fraction whose PR landed without needing a substantive human correction. Vanity metrics — runs
completed, PRs opened, green advisory checks, rubric N/N — are explicitly not the goal, and several
of them are shown below to be near-tautological in this corpus.

Decomposed as a funnel, each stage measurable from data the harness already emits (per run = one
`session_end` event in `.supervisor/logs/*.jsonl`, deduplicated by PR URL, latest wins):

| Stage | Meaning | Data source (as implemented in the builder) |
|---|---|---|
| 1. **landed** | the PR's landing commit is in git history | read-only `git log` — squash `"(#N)"` subject or `"Merge pull request #N"` merge commit |
| 2. **clean** | no substantive human correction | postmortem `review_rounds` **plus the false-zero drain rule (below)** |
| 3. **durable** | no revert / follow-up fix commit touching the same files within 14 days of landing | git history file-overlap; `pending(<14d)` until the window closes |
| 4. **cheap** | token spend per run | session token ledger — real usage preferred, labeled transcript-byte proxy fallback; never invented |

**The false-zero drain rule (mandatory):** a PR with 0 GitHub review rounds is still **NOT clean**
when drain-internal signals fire — `fix_cycles > 0` (review-heal events), `heal_iterations > 1`, or
≥ 3 consecutive ≤ 6-line "drain-cycle"-style commits on the PR branch. Rationale: the
`--until-mergeable` review drain resolves review findings *before* they ever reach GitHub, so a raw
`review_rounds: 0` can mean "clean" or "the drain silently churned" — the two must never be
conflated (this is the documented postmortem false-0 failure mode on inline-drain repos). The
drain-cycle *commit* signal is only detectable on true merge commits; squash merges collapse the
branch, in which case clean relies on the other two signals (noted under Data quality).

"Better" = stages 1–3 rise (or hold) while stage 4 falls. Any change that improves an internal
score (heal PASS rate, rubric score, reviewer finding count) without moving this funnel is proxy
drift, not progress.

---

## 2. Method + data quality

**Command (read-only, exit 0, both invocations):**

```
bash loomwright/scripts/build-loop-evidence.sh \
  --state-dir /Users/vikashruhil/Documents/work/AI/ai-agent-manager/.supervisor [--jsonl]
```

**n = 27 deduplicated runs** (from 41 log files), joined against 74 postmortem lines
(`postmortem/results.jsonl`, curation records excluded) and 4 heal-signal trend points
(`heal-signal/results.jsonl`), enriched with a read-only `git log` of the state dir's parent repo.
Corpus spans roughly 2026-04-26 → 2026-07-20.

**Era bucketing** is keyed on per-run `plugin_version` where recorded, with a **ship-date fallback**
(labeled `date_fallback:` in the per-run table) where it is not — many older runs predate the
version stamp, so their era assignment is date-inferred and less precise. Four runs lack both a
parseable version and timestamp and are bucketed `unknown`.

**Every degradation the builder reported on this run (Data-quality section, plus the rubric-column label):**

1. One or more runs lack `plugin_version` — bucketed by ship-date fallback (labeled
   `date_fallback`), less precise than a version stamp.
2. **Squash-merge blindness:** squash-merged PRs collapse branch history — the drain-cycle commit
   signal is unavailable there; clean relies on `fix_cycles`/`heal_iterations` for those PRs.
3. **Hot-file durable sensitivity:** durable is a file-overlap heuristic and is SENSITIVE to hot
   shared files — one wide fix/revert commit touching e.g. CLAUDE.md can mark many PRs non-durable
   at once; clustered `durable=no` rows are a prompt to inspect, not a verdict. (This bit hard here:
   see §3.)
4. One or more runs lack BOTH `plugin_version` and a parseable `ts` — era bucket `unknown`.
5. **Proxy-only tokens:** all token spend in this corpus is a transcript-byte PROXY (labeled
   `proxy:`), not real ledger usage — the real-usage ledger path has no data in the window.
6. A session log file holds multiple `session_end` runs — its token sum is file-level, shared
   across those runs for display; era totals count each file's sum exactly once.
7. **Rubrics are `self_graded_unverified`:** auto-authored vs human-approved rubrics are NOT
   distinguishable in the recorded data (no `rubric_source` / `rubric_human_approved` fields
   anywhere in the corpus) — the whole rubric column carries that label.

**Confounds (stated plainly — none of these are controlled for):**

- **Model upgrades over the window.** The corpus spans ~3 months of model changes; any before/after
  era delta is confounded with the underlying model getting better or different. Era comparison here
  is observational, not causal.
- **Task-mix drift.** Early runs are feature-heavy twin/observability builds; recent runs are
  doc/plugin-metadata-heavy. Review-round counts are not comparable across task types.
- **Tiny post-surface n.** n=2 post-orientation-memos and n=4 post-rules-seams (of which only 2 and
  3 respectively have postmortem joins). No per-surface claim survives that.
- **Uneven postmortem coverage.** 9 of 17 pre-rules runs have no postmortem join at all
  (`insufficient_data(no_postmortem)`) — the pre-rules clean/round averages are computed on the
  8 runs that do.
- **Taxonomy timing.** The `drain_churn` root-cause class first appears in postmortems at PR #92
  (2026-07-06) and dominates everything after; earlier postmortems used
  execution_bug/quality_gap/convention_mismatch. Without re-classifying the older corpus we cannot
  distinguish "drain churn started dominating" from "the classifier started naming it."

---

## 3. Results

### Funnel by era (builder output, verbatim)

| era | runs | landed | clean | durable | avg heal iters | avg review rounds | fix_cycles | root-cause class mix | advisory tokens |
|---|---|---|---|---|---|---|---|---|---|
| post_orientation_memos | 2 | 1/2 | 0/2 | 0/2 | - | 4.0 | 0 | drain_churn(2) | proxy:4841441B |
| post_rules_seams | 4 | 3/4 | 0/4 | 0/4 | 0.3 | 3.7 | 0 | drain_churn(3) | insufficient_data |
| pre_rules | 17 | 14/17 | 1/17 | 5/17 | 0.5 | 3.0 | 4 | execution_bug(7) quality_gap(8) missing_context(2) convention_mismatch(7) | insufficient_data |
| unknown | 4 | 4/4 | 0/4 | 1/4 | 0.3 | 4.5 | 0 | drain_churn(2) | proxy:694536B |

(Era thresholds: rules seams ≥ 15.1.0 shipped ~2026-07-03; orientation memos ≥ 15.12.0 shipped
~2026-07-20. Exact machine-readable era rows are reproduced in Appendix B.)

### What the numbers say

- **landed is the healthy stage:** 22/27 overall (the 5 misses are 4 runs with no PR URL recorded
  and 1 recent PR not yet in history). The harness reliably produces merged PRs.
- **clean is the collapsed stage:** among the **15 runs with review-round data, exactly 1 was
  clean** (~7%). Average review rounds do **not** improve across eras — 3.0 (pre-rules, n=8) →
  3.7 (post-rules, n=3) → 4.0 (post-memos, n=2). Given the confounds and tiny post-era n this is
  not evidence the surfaces made things *worse*, but it is certainly **not evidence they helped**.
- **drain_churn dominates the recent root-cause mix** — 7 of the 7 classified July-era runs
  (post-rules 3, post-memos 2, unknown 2) carry `drain_churn` as the dominant class, versus a
  pre-rules mix of quality_gap(8)/execution_bug(7)/convention_mismatch(7). Subject to the
  taxonomy-timing confound above, the loop's own review drain is now the *named* primary source of
  churn — the unflattering reading is that the machinery built to absorb review churn is what the
  postmortems now classify runs by.
- **durable=no comes in clusters, exactly as the hot-file warning predicts:** four wide fix commits
  account for all 15 non-durable verdicts — `4f855bb` (#72) alone marks 7 runs non-durable,
  `de24cc3` (a #103 drain-round commit) marks 5, plus `9c360bd` (#70) and `c636629` (#53). All four
  are themselves drain/review-fix commits touching hot shared files (CLAUDE.md-adjacent surfaces).
  So the durable stage is currently measuring "the repo has hot files that drain commits keep
  touching," not per-PR regression rates — inspect, don't conclude.
- **Rubric scores corroborate the draft's tautology warning:** 12 runs recorded a rubric score;
  **all 12 are perfect N/N** (7/7, 6/6, 8/8, 10/10, …), and all are `self_graded_unverified`. A
  signal that is 100% perfect across three months discriminates nothing.
- **Heal-signal trend (4 points, 2026-06-19 → 2026-06-23):** n=8 → n=20, coverage 24% → 54%,
  **recall 0% → 0%**, fp 0%. On the 20-PR confusion matrix, Phase 4.5 self-heal caught **none** of
  the issues that later external review found (and raised no false alarms — it is quiet, not noisy).
  That is the documented self-heal blind spot, now with a number attached.
- **cheap is unmeasurable as "cheap":** only 3 runs have any token figure at all, all
  transcript-byte proxies (post-memos era total `proxy:4841441B` ≈ 4.8 MB of transcript across 2
  runs). No real-usage ledger data exists in the window, so no cost trend can be stated.

Full per-run funnel table: Appendix A.

---

## 4. Per-surface verdicts

Verdict vocabulary: **SUPPORTED** / **NOT SUPPORTED** / **INSUFFICIENT DATA** — on the funnel
metrics only; "feels helpful" does not count.

| Advisory surface | Verdict | n | Reasoning |
|---|---|---|---|
| **Rules seams** (≥ 15.1.0) | **INSUFFICIENT DATA** | n=4 runs (3 with postmortem joins) | 4 observational runs cannot support any claim. What data exists shows no improvement (avg rounds 3.7 vs 3.0 pre-rules; 0/4 clean), but the era comparison is confounded by model, task mix, and taxonomy timing — do not read a negative verdict either. |
| **Orientation memos** (≥ 15.12.0) | **INSUFFICIENT DATA** | n=2 runs (both date-fallback-bucketed; 1 not yet landed; durable pending <14d) | Shipped ~1 day before this snapshot. Two runs — one of them the job that shipped the feature — is not a sample. No verdict is honest at n=2. |
| **Bridge (findings→community area knowledge)** | **INSUFFICIENT DATA** | n=0 attributable | No per-run field records whether bridge context was consulted, so runs cannot even be bucketed into bridge/no-bridge arms. Zero instrumentation ⇒ zero evidence either way. (The `orientation_source` ledger field shipped in 15.12.0 is reserved plumbing for exactly this attribution — no producer yet at snapshot time.) |
| **Self-heal loop (Phase 4.5) as a defect catcher** | **NOT SUPPORTED** (as currently measured) | n=20 (heal-signal confusion matrix) + 15 funnel runs with review data | The data does speak here, and it is unflattering: recall 0% across all 4 trend points (coverage grew 24%→54%, so this is not just a coverage artifact); 1/15 measured runs clean despite heal PASS being routine; 12/12 recorded rubrics perfect N/N; drain_churn the dominant named root cause in every post-July classified run. As a *defect catcher* the loop's green signals do not predict clean PRs. Narrow scope note: this verdict is about the loop's measured catch-rate, not about whether removing it would make outcomes worse — that counterfactual needs the ablation eval. |

Honesty note: with n=2 and n=4, INSUFFICIENT DATA **is** the correct verdict for the two newer
surfaces — manufacturing a direction from those cells would be exactly the proxy-drift failure mode
this document exists to prevent.

---

## 5. What would change these verdicts

1. **The pending 07 parity-ablation eval** (`ADVISORY_LOOP_EVAL.md` + `FABLE_PARITY_EVAL.md`,
   twin-remediation item 07): paired same-requirement, same-base-commit runs with seams
   disabled/enabled, and the 3-arm parity protocol. That design removes the model-upgrade and
   task-mix confounds that make every era comparison above observational — it is the only path to a
   SUPPORTED/NOT SUPPORTED verdict on rules seams and orientation memos, and it directly tests the
   self-heal counterfactual this snapshot cannot.
2. **n ≈ 30 merged-PR data points per era** (the draft memo's own threshold, which this snapshot
   endorses): post-surface buckets need ~15× more runs before observational funnel deltas mean
   anything.
3. **Version stamps on every `session_end`** — kill the `date_fallback` and `unknown` buckets.
4. **PR URL on every run** — 4 runs were unlandable-by-construction (no `pr_url` recorded).
5. **Real token-ledger usage** instead of transcript-byte proxies — until then the *cheap* stage
   has no data, only labeled proxies.
6. **`rubric_source` / `rubric_human_approved` recorded at run time** — until then every rubric
   column is `self_graded_unverified` and the 12/12-perfect pattern is uninterpretable beyond
   "tautology warning corroborated."
7. **Per-run advisory-surface attribution** — populate the `orientation_source` ledger field (and
   an equivalent for bridge/rules consultation) so runs can be bucketed by *what context they
   actually consumed*, not by plugin-version era.
8. **Postmortem back-classification** of the pre-#92 corpus with the current taxonomy (or a
   recorded taxonomy-version field going forward) — resolves the drain_churn timing confound.

---

## Appendix A — full per-run funnel (builder output, verbatim)

| run | version | landed | clean | durable | cheap |
|---|---|---|---|---|---|
| v14-20260516-221852 | date_fallback:2026-05-16 | yes | insufficient_data(no_postmortem) | yes | insufficient_data |
| 2026-06-04-system-twin-foundation.jsonl | date_fallback:2026-06-04 | yes | insufficient_data(no_postmortem) | no (follow-up fix c636629 touched same files <14d) | insufficient_data |
| obsidian-vault | date_fallback:2026-06-04 | yes | insufficient_data(no_postmortem) | no (follow-up fix 9c360bd touched same files <14d) | insufficient_data |
| twin-inline-delta | date_fallback:2026-06-05 | yes | insufficient_data(no_postmortem) | no (follow-up fix 9c360bd touched same files <14d) | insufficient_data |
| insights-twin-scoreboard | date_fallback:2026-06-07 | yes | insufficient_data(no_postmortem) | no (follow-up fix 4f855bb touched same files <14d) | insufficient_data |
| m2b-part2-ci-fitness | unknown | yes | insufficient_data(no_postmortem) | no (follow-up fix 4f855bb touched same files <14d) | insufficient_data |
| pr-postmortem-analyzer | date_fallback:2026-06-09 | yes | no (review_rounds=4) | no (follow-up fix 4f855bb touched same files <14d) | insufficient_data |
| setup-observability | 14.24.0 | yes | no (review_rounds=7) | no (follow-up fix 4f855bb touched same files <14d) | insufficient_data |
| learning-loop-phase1-2 | 14.28.0 | yes | no (review_rounds=2) | no (follow-up fix 4f855bb touched same files <14d) | insufficient_data |
| auto-2026-06-18-135602 | 14.33.0 | yes | yes | no (follow-up fix 4f855bb touched same files <14d) | insufficient_data |
| phase4-churn-ledger | 14.36.0 | yes | no (review_rounds=5 fix_cycles=4) | no (follow-up fix 4f855bb touched same files <14d) | insufficient_data |
| 20260426-004614-supervisor.jsonl | date_fallback:2026-04-26 | yes | insufficient_data(no_postmortem) | yes | insufficient_data |
| review-rigor-and-severity | 14.43.0 | yes | no (review_rounds=1) | yes | insufficient_data |
| automate-learning-e6763b7 | 14.44.0 | yes | no (review_rounds=2) | yes | insufficient_data |
| supervisor-handoff-digest.jsonl | 14.49.0 | yes | no (review_rounds=3) | yes | insufficient_data |
| auto-2026-07-18-143648 | unknown | yes | no (review_rounds=4) | no (follow-up fix de24cc3 touched same files <14d) | proxy:694536B |
| auto-2026-07-20-140859 | date_fallback:2026-07-20 | yes | no (review_rounds=3) | pending(<14d) | proxy:2810387B |
| auto-2026-07-20-205727 | date_fallback:2026-07-20 | no(not_in_history) | no (review_rounds=5) | - | proxy:2031054B |
| cheap-passthrough-autonomous-automate | unknown | yes | insufficient_data(no_postmortem) | yes | insufficient_data |
| auto-2026-07-06-204810 | 15.4.0 | yes | no (review_rounds=5) | no (follow-up fix de24cc3 touched same files <14d) | insufficient_data |
| script-test-gaps | 15.5.0 | yes | no (review_rounds=2) | no (follow-up fix de24cc3 touched same files <14d) | insufficient_data |
| auto-2026-07-07-162407 | unknown | yes | no (review_rounds=5) | no (follow-up fix de24cc3 touched same files <14d) | insufficient_data |
| 2026-07-07-fable-parity-sdk-spike | 15.8.0 | yes | no (review_rounds=4) | no (follow-up fix de24cc3 touched same files <14d) | insufficient_data |
| auto-2026-07-07-094534.jsonl | date_fallback:2026-07-07 | insufficient_data(no_pr_url) | insufficient_data(no_postmortem) | - | insufficient_data |
| eval-harness | date_fallback:2026-06-06 | insufficient_data(no_pr_url) | insufficient_data(no_postmortem) | - | insufficient_data |
| polish-gate-and-delta | date_fallback:2026-06-06 | insufficient_data(no_pr_url) | insufficient_data(no_postmortem) | - | insufficient_data |
| supervisor-c52ff8b.jsonl | 14.24.0 | insufficient_data(no_pr_url) | insufficient_data(no_postmortem) | - | insufficient_data |

## Appendix B — machine-exact era + meta records (`--jsonl` output, verbatim)

```jsonl
{"type":"era_bucket","era":"post_orientation_memos","runs":"2","landed":"1","clean":"0","durable":"0","avg_heal_iterations":"-","avg_review_rounds":"4.0","fix_cycles":"0","class_mix":"drain_churn(2)","advisory_tokens":"proxy:4841441B"}
{"type":"era_bucket","era":"post_rules_seams","runs":"4","landed":"3","clean":"0","durable":"0","avg_heal_iterations":"0.3","avg_review_rounds":"3.7","fix_cycles":"0","class_mix":"drain_churn(3)","advisory_tokens":"insufficient_data"}
{"type":"era_bucket","era":"pre_rules","runs":"17","landed":"14","clean":"1","durable":"5","avg_heal_iterations":"0.5","avg_review_rounds":"3.0","fix_cycles":"4","class_mix":"execution_bug(7) quality_gap(8) missing_context(2) convention_mismatch(7)","advisory_tokens":"insufficient_data"}
{"type":"era_bucket","era":"unknown","runs":"4","landed":"4","clean":"0","durable":"1","avg_heal_iterations":"0.3","avg_review_rounds":"4.5","fix_cycles":"0","class_mix":"drain_churn(2)","advisory_tokens":"proxy:694536B"}
{"type":"meta","heal_signal_trend":"4 points; first 2026-06-19T16:12:19Z (n=8, recall=0%, coverage=24%) -> last 2026-06-23T05:32:13Z (n=20, recall=0%, fp=0%, coverage=54%)","rubric_column":"self_graded_unverified"}
```
