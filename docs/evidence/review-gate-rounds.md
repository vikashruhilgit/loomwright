# as23 — Did v17.2.0 end the 3/3 Phase 4.5 heal rounds, and what do Plan Review attempts cost: evidence

Requirement: `.supervisor/requirements/automate-speed/23-measure-review-gates.md`. Base commit: `3a03dfa66d7de22ff93b0327affa60aa752948d2`. Measured 2026-10-18 by the lane worker, macOS, from the repo root. Every table and count below is the verbatim output of the commands in [`## Commands`](#commands); the two live reads (`gh`, Claude Code transcripts) are kept apart under [Recorded live reads](#recorded-live-reads-not-re-run). Nothing here touched a production service; the only network reads are read-only `gh` calls against `vikashruhilgit/loomwright`.

**Frozen cutoff:** ledger rows with `ts <= 2026-10-18T09:35:11Z` (the newest row at the base commit) plus the frozen PR lists `MERGED_POST` and `NOT_MERGED` (from the one-off merged-state read). A row written to the ledger later does not change any printed table.

**Local data only:** the commands read `.supervisor/postmortem/results.jsonl`, `.supervisor/automate/*.md` (run files and their `<run_id>.supervisor-result.md` sidecars) and `.supervisor/jobs/done/*.md`. `.supervisor/` is gitignored; these paths are carried on the `loomwright-meta` branch (`meta-sync.sh`'s managed set), so the commands re-run only on a checkout that pulled that branch (`/automate`'s `meta-entry` does).

## Result

- **Post-v17.2.0 items: 16** (AC4: at least 3 exist, so the "fewer than 3" branch does not apply).
- **Before/after at 3/3 Phase 4.5 rounds:**
  - `post-v17.2.0: 5 of 16 items at 3/3 (31.2%)`
  - `pre-v17.2.0: 15 of 58 items at 3/3 (25.9%)` (54 earlier items have no recorded rounds and are left out of the denominator)
  - `pre-v17.2.0, plugin >= 16.0.0` (PRs #499–#538, ledger rows 2026-10-12 to 2026-10-14): `7 of 7 items at 3/3 (100.0%)`
- **AC5 draft condition did not fire:** 5 of 16 is less than half, so no propose-only draft was written to `.supervisor/requirements/proposed/`.
- **Plan Review:** of the 13 post-v17.2.0 items whose attempts are recorded, 10 used 3 of 3 attempts and 3 used 2 of 3. All 6 recorded pre-v17.2.0 items on plugin >= 16.0.0 used 3 of 3.

### What the numbers support, and what they do not

1. **The 3/3 streak ended.** Every recorded item on plugin 16.0.0 to 17.0.2 hit 3/3 (7 of 7). On 17.2.0 and later, 5 of 16 did. The distribution of rounds 0/1/2/3 is 1/3/7/5.
2. **Most items still use three reviewer passes.** `self_heal_rounds` counts fix rounds (`SUPERVISOR_RESULT.heal_iterations`), not reviews. An item that ends `PASS` after 2 fix rounds ran a third review (the run files say `heal PASS after 3 reviews / 2 fix rounds` for #542, #558 and #594). All 7 post-v17.2.0 items at 2 rounds ended `PASS`, so 12 of 16 still ran three reviews. Only the 5 at 3/3 ended with an unreviewed final fix (`ESCALATED (max_iterations_reached)`).
3. **Compared with the long-run baseline, the share at 3/3 is similar but the typical item takes more rounds.** Across all 58 recorded pre-v17.2.0 items, 25.9% hit 3/3, close to the post group's 31.2%. But 22 of those 58 (37.9%) took 2 or more rounds, against 12 of 16 (75%) after v17.2.0.
4. **These numbers do not show that v17.2.0 caused the change.** The groups hold different items. The post group is mostly `automate-speed` refactors run as parallel lanes, and releases 17.3.0 to 17.6.1 (carrying some of these same items) landed during the window. There is no controlled re-run of the same item. n = 16 is small.
5. **Phase 4.5 duration cannot be compared.** It is recorded for only 4 of the 16 post-v17.2.0 items (32m, 1h 14m, 1h 7m, 2h 27m). It is recorded for 19 earlier items, but only 3 of them are in the plugin >= 16.0.0 slice (#501 4h 0m, #533 1h 25m, #538 51m). The other 16 ran on plugin 15.x and took 4m to 53m. Lane run files from `automate-2026-10-15-163325` mostly write no FINALIZE or PR-opened line, and the transcript report reads `not recorded` for the same items (see live reads).
6. **Launch Pad duration is not the cost of Plan Review alone.** The `picked` to brief-saved span also holds the time spent waiting on the owner. #548 (8h 34m, 3/3) records three owner decisions and five post-PASS fixes before its save. #562 (4h 34m, 3/3) records only that the owner chose "Save and exit", so the run file cannot split its span into review time and wait time. The plan-reviewer subagent's own token usage, read from transcripts for 8 lane items, is in the live-read section: 2.0M to 4.3M context tokens per item.

## How each column is derived

| Column | Source | Rule |
|---|---|---|
| Which rows count | ledger | `source == "automate_drain"` with a `pr_url`, `ts <= CUT`. One row per `pr_url`: the latest `ts`, then the later line. `manual_postmortem` rows, rows with no `source` and rows with no `pr_url` are excluded and listed below. |
| Group (post / pre) | ledger `plugin_version` | `post` when `plugin_version` >= 17.2.0, compared as numbers split on `.` (jq array compare, so 17.10.0 sorts after 17.2.0). `plugin_version` is the installed plugin when the drain ran. For the earliest post rows (run `automate-2026-10-13-181331`), the run file records "verified on installed v17.2.0" at 2026-10-14T09:23:03Z, before #542's Phase 4.5. A row with a non-numeric `plugin_version` (`unknown`) is excluded and listed. |
| Merged | recorded live read | The post group is filtered on the frozen list `MERGED_POST`. Every PR in both groups was MERGED except #429 (CLOSED), which is in `NOT_MERGED` and excluded. |
| Phase 4.5 rounds | ledger `self_heal_rounds`, else sidecar `heal_iterations` | The sidecar is used only when its `pr_url` is this item's PR. Ledger rows before 2026-09-27 carry no `self_heal_rounds`, and a run's sidecar holds only that run's last item, so 54 earlier items read `not recorded`. A sidecar value is marked `(sidecar)`. "3/3" means `self_heal_rounds == 3`, the default `--heal-iterations` cap. No row in either group records more than 3. |
| Phase 4.5 duration | run file | From the item's PR-opened line to its end-of-RUN line. The end of RUN is the first `/autonomous done` or `ran supervisor` line, else the first `ran /autonomous` line. The PR-opened line is the first line before it that starts `FINALIZE:`, or that names this PR (`pull/N` or `PR #N`) and says `FINALIZE` or `PR opened` (e.g. `PR opened …/pull/538 (FINALIZE; …)`, `supervisor FINALIZE: … PR …/pull/402`). When a run writes a `/autonomous done` line, its earlier `ran /autonomous → PR …` line is the PR-opened line (#382, #408, #464, #470). `read-token-ledger.sh --per-item` reads only the `FINALIZE:` shape for its Phase 4.5 row; where that shape exists both give the same window, including the 85m the requirement quotes for #533. |
| Termination | sidecar, else run file | `heal_decision` from the PR's sidecar, else `heal PASS`, `heal ESCALATED` or `heal FAIL` from the end-of-RUN line. The reason in brackets is the first `max_iterations_reached` or `needs_human` found in the sidecar `error`, the end-of-RUN line or the sidecar `summary`. Sidecars carry no `escalation_reason` key. |
| Plan Review attempts | run file, else brief | The largest `Plan Review … N/M` between the item's `picked` line and its brief-saved line. Else the first `attempt N/M` in the `## Plan Review` section of the brief named by the run file's close-out `stamped — <item> (… brief <path>)` line, marked `(brief)`. N is read as attempts used, as the requirement reads "Plan Review PASS 3/3" on #533. |
| Launch Pad duration | run file | From the item's `picked` line to its first brief-saved line: one that says `brief saved`, `launch-pad saved`, `Launch Pad saved` or `LAUNCH_PAD_RESULT saved` (any case). A negated line (`no brief saved`, `never saved`, `not saved`) is not one; #294 and #450 each carry one before the item ran. |

The item segment of a run file starts at its first `picked <item>` line and ends at the next `picked` line for a different item. A `picked` line is `- ` (or `- - `), at most two words before `picked` (a timestamp in any format, or none), then `picked` in any case and a `.md` name, bare or as `item N (<name>)`. The name matches the item when it equals the item path with a leading `./` or `.supervisor/requirements/` removed, or, when it has no `/`, the item's file name. Only `YYYY-MM-DDTHH:MM:SSZ` timestamps are used, after the `- ` or `- - ` prefix. Older run files with other formats read `not recorded (run file: …)`.

## Post-v17.2.0 items

<!-- post -->
| PR | Item | Plugin | Phase 4.5 rounds | Phase 4.5 duration | Termination | Plan Review attempts | Launch Pad duration |
|---|---|---|---|---|---|---|---|
| #542 | automate-followups/39b-run-lock-and-guard-arm.md | 17.2.0 | 2 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | 3/3 | 26m |
| #548 | twin-remediation/08b-single-lane-sequential.md | 17.2.0 | 2 | 32m | PASS | 3/3 | 8h 34m |
| #555 | automate-followups/39a-sweep-and-janitor.md | 17.2.0 | 3 | 2h 27m | ESCALATED (max_iterations_reached) | 2/3 | 1h 26m |
| #559 | automate-speed/04-loop-inventory.md | 17.3.0 | 2 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | 3/3 | 16m |
| #558 | automate-speed/05-golden-run-tests.md | 17.3.0 | 2 | 1h 14m | PASS | 2/3 | 12m |
| #562 | automate-speed/25-automate-load-by-mode.md | 17.3.0 | 2 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | 3/3 | 4h 34m |
| #565 | automate-speed/17-prompt-size-ratchet.md | 17.3.0 | 1 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | 3/3 (brief) | not recorded (run file: no brief-saved line) |
| #570 | automate-speed/03-measure-run-cost.md | 17.3.0 | 3 | 1h 7m | ESCALATED (max_iterations_reached) | 3/3 | 12m |
| #573 | automate-speed/13-diet-launch-pad-autonomous.md | 17.3.0 | 2 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | 3/3 | 20m |
| #577 | automate-speed/19-split-lanes-and-trail-scripts.md | 17.3.0 | 1 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | 3/3 | 50m |
| #575 | automate-speed/06-next-step-driver-tail.md | 17.3.0 | 3 | not recorded (run file: no FINALIZE or PR-opened line) | ESCALATED (max_iterations_reached) | 3/3 | 30m |
| #594 | automate-speed/07-next-step-drain-and-run.md | 17.5.0 | 2 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #598 | automate-speed/20-split-memory-and-meta-scripts.md | 17.6.1 | 1 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #601 | automate-speed/11-next-step-supervisor.md | 17.6.1 | 0 | not recorded (run file: no FINALIZE or PR-opened line) | ESCALATED (needs_human) | 3/3 | 16m |
| #600 | automate-speed/12-next-step-review-heal.md | 17.6.1 | 3 | not recorded (run file: no FINALIZE or PR-opened line) | ESCALATED (max_iterations_reached) | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #599 | automate-speed/08-next-step-pick-and-resume.md | 17.6.1 | 3 | not recorded (run file: no FINALIZE or PR-opened line) | ESCALATED (max_iterations_reached) | 2/3 (brief) | not recorded (run file: no brief-saved line) |
<!-- /post -->

## Pre-v17.2.0 items

112 items. Rounds are recorded for 58 of them.

<details>
<summary>Full table (<code>table pre</code>)</summary>

<!-- pre -->
| PR | Item | Plugin | Phase 4.5 rounds | Phase 4.5 duration | Termination | Plan Review attempts | Launch Pad duration |
|---|---|---|---|---|---|---|---|
| #91 | review-remediation/01-command-clarity.md | 15.2.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no FINALIZE or PR-opened line) | PASS | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #92 | review-remediation/02-telemetry-core-tests.md | 15.2.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no picked line) | not recorded (sidecar: none for this PR; run file: no heal decision) | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no picked line) |
| #93 | review-remediation/03-doc-hygiene-index-roadmap.md | 15.2.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no picked line) | not recorded (sidecar: none for this PR; run file: no heal decision) | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no picked line) |
| #94 | review-remediation/04-state-resume-validation.md | 15.2.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no picked line) | not recorded (sidecar: none for this PR; run file: no heal decision) | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no picked line) |
| #95 | review-remediation/05-supervisor-prompt-refactor.md | 15.4.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no picked line) | not recorded (sidecar: none for this PR; run file: no heal decision) | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no picked line) |
| #96 | review-remediation/06-script-test-gaps-and-roadmap-remainders.md | 15.5.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no picked line) | not recorded (sidecar: none for this PR; run file: no heal decision) | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no picked line) |
| #97 | review-remediation/07-tech-stack-skills-spinoff.md | 15.6.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no picked line) | not recorded (sidecar: none for this PR; run file: no heal decision) | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no picked line) |
| #98 | review-remediation/08-curation-half-and-counterfactual-eval.md | 15.7.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no FINALIZE or PR-opened line) | PASS | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #99 | review-remediation/09-fable-parity-sdk-spike.md | 15.6.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no picked line) | not recorded (sidecar: none for this PR; run file: no heal decision) | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no picked line) |
| #100 | token-economy/01-token-ledger-and-cache-audit.md | 15.9.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no FINALIZE or PR-opened line) | PASS | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #101 | token-economy/02-token-budget-ci-gate.md | 15.10.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no FINALIZE or PR-opened line) | not recorded (sidecar: none for this PR; run file: no heal decision) | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #102 | token-economy/03-sdk-runner-token-levers.md | 15.9.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no FINALIZE or PR-opened line) | PASS | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #103 | token-economy/04-orientation-memos-and-repo-map.md | 15.12.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no picked line) | not recorded (sidecar: none for this PR; run file: no heal decision) | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no picked line) |
| #104 | token-economy/05-pointers-shared-prefix-batch-routing.md | 15.13.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no FINALIZE or PR-opened line) | PASS | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #106 | twin-remediation/02-curation-anti-rot.md | 15.14.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no picked line) | not recorded (sidecar: none for this PR; run file: no heal decision) | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no picked line) |
| #115 | final-state/01-fix1-single-agent-default.md | 15.15.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no picked line) | not recorded (sidecar: none for this PR; run file: no heal decision) | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no picked line) |
| #116 | final-state/02-fix3-one-writer-derived-state.md | 15.16.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no picked line) | not recorded (sidecar: none for this PR; run file: no heal decision) | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no picked line) |
| #119 | final-state/04-fix7-two-review-lenses.md | 15.18.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no picked line) | not recorded (sidecar: none for this PR; run file: no heal decision) | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no picked line) |
| #120 | final-state/07-route-freshness-tools.md | 15.18.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no picked line) | not recorded (sidecar: none for this PR; run file: no heal decision) | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no picked line) |
| #121 | final-state/08-worker-context-digest-lanes.md | 15.20.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no picked line) | not recorded (sidecar: none for this PR; run file: no heal decision) | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no picked line) |
| #122 | final-state/09-claude-md-diet-dreaming.md | 15.21.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no picked line) | not recorded (sidecar: none for this PR; run file: no heal decision) | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no picked line) |
| #123 | final-state/13-drain-bounding-earned-checks.md | 15.22.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no end-of-RUN line) | not recorded (sidecar: none for this PR; run file: no heal decision) | 3/3 | not recorded (run file: no brief-saved line) |
| #124 | final-state/11-subtask-id-determinism.md | 15.23.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no end-of-RUN line) | not recorded (sidecar: none for this PR; run file: no heal decision) | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #125 | final-state/12-4c-unified-tools-lists.md | 15.23.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no end-of-RUN line) | not recorded (sidecar: none for this PR; run file: no heal decision) | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #126 | twin-loop/01-commit-the-distilled-twin.md | 15.25.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no FINALIZE or PR-opened line) | PASS | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #134 | twin-loop/02-curation-cadence.md | 15.29.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no end-of-RUN line) | not recorded (sidecar: none for this PR; run file: no heal decision) | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: timestamp not ISO-8601 UTC) |
| #138 | twin-loop/03-applies-to-routing.md | 15.29.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no end-of-RUN line) | not recorded (sidecar: none for this PR; run file: no heal decision) | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #160 | 2026-08-22-092036-vendor-coupling-ratchet.md | 15.38.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no end-of-RUN line) | not recorded (sidecar: none for this PR; run file: no heal decision) | not recorded (run file, brief: no Plan Review N/M) | 52m |
| #170 | loom-floor-ui/01-agent-spawn-event.md | 15.41.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no end-of-RUN line) | not recorded (sidecar: none for this PR; run file: no heal decision) | 3/3 | not recorded (run file: no brief-saved line) |
| #172 | loom-floor-ui/02-status-line.md | 15.41.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no end-of-RUN line) | not recorded (sidecar: none for this PR; run file: no heal decision) | 3/3 | 1h 4m |
| #174 | loom-floor-ui/03-floor-projector.md | 15.41.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no picked line) | not recorded (sidecar: none for this PR; run file: no heal decision) | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no picked line) |
| #176 | loom-floor-ui/04-the-floor-ui.md | 15.41.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no end-of-RUN line) | not recorded (sidecar: none for this PR; run file: no heal decision) | 3/3 | not recorded (run file: no brief-saved line) |
| #177 | loom-floor-ui/05-archive-views.md | 15.41.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no end-of-RUN line) | not recorded (sidecar: none for this PR; run file: no heal decision) | 3/3 | not recorded (run file: no brief-saved line) |
| #181 | loom-floor-ui/06-ui-command-and-projects.md | 15.41.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no end-of-RUN line) | not recorded (sidecar: none for this PR; run file: no heal decision) | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #182 | loom-floor-ui/07-ui-guarded-writes.md | 15.47.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no end-of-RUN line) | not recorded (sidecar: none for this PR; run file: no heal decision) | 3/3 | not recorded (run file: no brief-saved line) |
| #204 | invention/02a-product-context-store.md | 15.56.1 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no FINALIZE or PR-opened line) | not recorded (sidecar: none for this PR; run file: no heal decision) | 3/3 | 28m |
| #208 | reconciler-repair/01-brief-pointer-extraction.md | 15.63.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no FINALIZE or PR-opened line) | not recorded (sidecar: none for this PR; run file: no heal decision) | 3/3 | 25m |
| #209 | reconciler-repair/02-reconcile-on-fresh-session.md | 15.61.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no end-of-RUN line) | not recorded (sidecar: none for this PR; run file: no heal decision) | 1/3 | 7m |
| #210 | reconciler-repair/03-merge-evidenced-repair.md | 15.65.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no end-of-RUN line) | not recorded (sidecar: none for this PR; run file: no heal decision) | 1/3 | 40m |
| #211 | reconciler-repair/04-worktree-audit-log-is-blind.md | 15.65.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no end-of-RUN line) | not recorded (sidecar: none for this PR; run file: no heal decision) | 3/3 | 1h 17m |
| #212 | reconciler-repair/05-salvage-before-removal.md | 15.66.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no end-of-RUN line) | not recorded (sidecar: none for this PR; run file: no heal decision) | 1/3 | 26m |
| #213 | reconciler-repair/06-retention-without-amnesia.md | 15.66.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no end-of-RUN line) | not recorded (sidecar: none for this PR; run file: no heal decision) | 3/3 | not recorded (run file: no brief-saved line) |
| #215 | review-gate-brief-conformance/01-brief-conformance-in-phase45-review.md | 15.68.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no FINALIZE or PR-opened line) | PASS | 2/3 | 10m |
| #217 | review-gate-brief-conformance/02-manager-reverifies-provides.md | 15.68.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no FINALIZE or PR-opened line) | PASS | 2/3 | 43m |
| #219 | review-gate-brief-conformance/03-high-risk-park-in-trusted-merge-gate.md | 15.68.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no FINALIZE or PR-opened line) | PASS | not recorded (run file, brief: no Plan Review N/M) | 16m |
| #220 | verify-walkthrough/01-verify-env-contract.md | 15.72.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no FINALIZE or PR-opened line) | PASS | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #222 | verify-walkthrough/02-verify-evidence-store.md | 15.72.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no FINALIZE or PR-opened line) | PASS | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #223 | verify-walkthrough/03-verify-command-and-mode.md | 15.74.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | 12m | PASS | not recorded (run file, brief: no Plan Review N/M) | 24m |
| #226 | verify-walkthrough/04-verify-auth-pause.md | 15.77.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no end-of-RUN line) | not recorded (sidecar: none for this PR; run file: no heal decision) | not recorded (run file, brief: no Plan Review N/M) | 20m |
| #264 | harness-port/05-dismissed-findings.md | 15.98.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no end-of-RUN line) | not recorded (sidecar: none for this PR; run file: no heal decision) | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: timestamp not ISO-8601 UTC) |
| #265 | harness-port/06-shared-local-services.md | 15.99.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no end-of-RUN line) | not recorded (sidecar: none for this PR; run file: no heal decision) | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: timestamp not ISO-8601 UTC) |
| #266 | harness-port/07-ci-trust-probe.md | 15.100.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no end-of-RUN line) | not recorded (sidecar: none for this PR; run file: no heal decision) | 1/3 | not recorded (run file: timestamp not ISO-8601 UTC) |
| #267 | twin-loop/08-executable-rule-candidates.md | 15.98.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | not recorded (run file: no end-of-RUN line) | not recorded (sidecar: none for this PR; run file: no heal decision) | 1/3 | not recorded (run file: timestamp not ISO-8601 UTC) |
| #269 | token-economy/07-verify-spec-replay.md | 15.98.0 | 1 (sidecar) | not recorded (run file: no end-of-RUN line) | PASS | 1/3 | 44m |
| #272 | automate-followups/01-learning-emit-counts-self-heal-rounds.md | 15.98.0 | not recorded (ledger: no self_heal_rounds; sidecar: none for this PR) | 11m | PASS | 2/3 | 27m |
| #281 | automate-followups/02-ci-review-bot-cannot-execute.md | 15.106.2 | 1 | 8m | PASS | 3/3 | 3h 52m |
| #288 | automate-followups/03-resume-glob-lists-sidecar-artifacts.md | 15.108.1 | 0 | 4m | PASS | 2/3 | 1h 9m |
| #290 | automate-followups/04-hermetic-test-notifier-egress.md | 15.108.1 | 0 | 28m | PASS | 1/3 | 1h 15m |
| #292 | automate-followups/05-plan-time-rule-routing.md | 15.108.4 | 0 | 53m | PASS | 1/3 | 2h 41m |
| #294 | automate-followups/06-worker-rule-self-check.md | 15.108.4 | 1 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | 3/3 | not recorded (run file: no brief-saved line) |
| #296 | automate-followups/07-rule-enforcement-at-review-and-merge.md | 15.108.4 | 1 | 49m | PASS | 1/3 | 25m |
| #299 | automate-followups/09-audit-rules-at-phase45-and-gate-trigger-nudge.md | 15.112.0 | 1 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | 1/3 | 5h 48m |
| #301 | automate-followups/10-rules-reach-standalone-review.md | 15.113.0 | 2 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | 1/3 | 28m |
| #314 | automate-followups/12-dismissed-findings-become-tracked-decisions.md | 15.114.2 | 2 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | 2/3 | 32m |
| #319 | automate-followups/13-dismissed-findings-triage-sweep.md | 15.115.0 | 1 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | 1/3 | 25m |
| #327 | parallel-automate/01-version-bump-script.md | 15.115.0 | 0 | not recorded (run file: no FINALIZE or PR-opened line) | not recorded (sidecar: none for this PR; run file: no heal decision) | 1/3 | 23m |
| #334 | parallel-automate/02-meta-sync-script.md | 15.115.0 | 3 | not recorded (run file: no FINALIZE or PR-opened line) | not recorded (sidecar: none for this PR; run file: no heal decision) | 1/3 | 5h 49m |
| #347 | parallel-automate/03-branch-mode-engine.md | 15.117.2 | 3 | not recorded (run file: no FINALIZE or PR-opened line) | not recorded (sidecar: none for this PR; run file: no heal decision) | 1/3 | 41m |
| #365 | parallel-automate/04-wave-planner.md | 15.119.2 | 2 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | 2/3 | not recorded (run file: no brief-saved line) |
| #374 | automate-followups/19-is-run-file-tolerant-title.md | 15.119.2 | 0 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | 1/3 | 7m |
| #372 | automate-followups/18-fail-to-unstamped-escalates.md | 15.119.2 | 1 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | 1/3 | 7m |
| #375 | parallel-automate/08-shared-ci-slots.md | 15.119.2 | 1 | 38m | PASS | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #377 | parallel-automate/10-touches-backfill-lint-and-explain.md | 15.119.2 | 1 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #379 | automate-followups/30-lens-run-test-concurrency-safe.md | 15.119.2 | 1 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #381 | automate-followups/24-provides-name-quote-parsing.md | 15.119.2 | 0 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #382 | meta-sync-followups/01-untested-push-and-base-fallbacks.md | 15.119.2 | 0 | 13m | PASS | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #386 | automate-followups/26-notification-group-per-lane-and-no-refire.md | 15.119.2 | 0 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #385 | agnostic-phase1/01-ratchet-hardening.md | 15.119.2 | 1 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | 2/3 | not recorded (run file: no brief-saved line) |
| #384 | automate-followups/16-gate-eval-cond7-pin-head.md | 15.119.2 | 2 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #391 | meta-sync-followups/04-scrub-safe-briefs-and-push-rehearsal.md | 15.122.0 | 0 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #394 | meta-sync-followups/08-meta-sync-hardening.md | 15.122.0 | 0 | 8m | PASS | 2/3 | not recorded (run file: timestamp not ISO-8601 UTC) |
| #392 | parallel-automate/09-ci-local-fewer-full-runs.md | 15.122.0 | 1 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #395 | automate-followups/32-run-file-lifecycle.md | 15.122.0 | 1 | 44m | PASS | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #402 | parallel-automate/16-machine-load-guard.md | 15.123.1 | 1 | 22m | PASS | 3/3 | 11m |
| #403 | agnostic-phase1/04-non-interactive-gates.md | 15.123.1 | 3 | not recorded (run file: no FINALIZE or PR-opened line) | ESCALATED (max_iterations_reached) | 1/3 | 8m |
| #408 | parallel-automate/11-split-shared-hotspot-files.md | 15.123.1 | 1 | 21m | PASS | 1/3 | 35m |
| #410 | automate-followups/33-children-settled-gate.md | 15.124.0 | 1 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #412 | host-contract/01-published-capability-contract.md | 15.124.0 | 2 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #417 | meta-sync-followups/07-onboard-any-repo-to-branch-mode.md | 15.124.0 | 3 | not recorded (run file: no FINALIZE or PR-opened line) | ESCALATED (max_iterations_reached) | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #415 | automate-followups/31-transient-escalation-recheck.md | 15.124.0 | 3 | not recorded (run file: no FINALIZE or PR-opened line) | ESCALATED (max_iterations_reached) | 1/3 | 41m |
| #426 | parallel-automate/05-lane-coordinator.md | 15.125.1 | 1 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #434 | parallel-automate/23-pa05-validation-fixes-a.md | 15.125.1 | 1 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #435 | parallel-automate/24-pa05-validation-fixes-b.md | 15.125.1 | 2 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #440 | implementation-quality/02-iq01-and-throughput-merged.md | 15.125.1 | 3 | not recorded (run file: no FINALIZE or PR-opened line) | ESCALATED (max_iterations_reached) | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #445 | agnostic-phase1/02-completion-evidence-integrity.md | 15.126.0 | 0 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #446 | automate-followups/37-done-stamp-before-merge.md | 15.126.0 | 3 | not recorded (run file: no FINALIZE or PR-opened line) | ESCALATED (max_iterations_reached) | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #450 | host-contract/02-host-mode-no-repo-writes.md | 15.126.0 | 3 | not recorded (run file: no FINALIZE or PR-opened line) | ESCALATED (max_iterations_reached) | 3/3 | 8h 51m |
| #455 | automate-followups/38-closeout-for-lane-and-auto-merge.md | 15.126.0 | 0 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | not recorded (run file, brief: no Plan Review N/M) | 10m |
| #460 | churn-ledger/01-restated-lists-diverge-from-authority.md | 15.127.1 | 0 | 6m | PASS | not recorded (run file, brief: no Plan Review N/M) | 11m |
| #459 | twin-loop/07-rules-baseline-remeasurement.md | 15.127.1 | 2 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #464 | parallel-automate/21-fleet-operations.md | 15.127.1 | 0 | 11m | PASS | 3/3 | 21m |
| #468 | host-contract/03-declare-host-mode-in-contract.md | 15.128.1 | 0 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #470 | parallel-automate/22-split-automate-engine-surfaces.md | 15.128.1 | 1 | 21m | PASS | 3/3 | 54m |
| #477 | churn-ledger/02-classifier-unknowable-attribution.md | 15.130.0 | 1 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | 2/3 | 14m |
| #479 | twin-remediation/10-harness-portability.md | 15.130.0 | 0 | not recorded (run file: no FINALIZE or PR-opened line) | PASS | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #499 | af36-remainder/04-dreaming-memory-pr.md | 16.0.0 | 3 | not recorded (run file: no FINALIZE or PR-opened line) | ESCALATED | 3/3 | 32m |
| #501 | af36-remainder/02-meta-allowlist-grant.md | 16.0.0 | 3 | 4h 0m | ESCALATED | 3/3 | 33m |
| #502 | af36-remainder/01-validation-unrun-gate.md | 16.0.0 | 3 | not recorded (run file: no FINALIZE or PR-opened line) | ESCALATED (max_iterations_reached) | 3/3 | 33m |
| #528 | af36-remainder/03-meta-sync-learning-stores.md | 16.3.0 | 3 | not recorded (run file: no FINALIZE or PR-opened line) | ESCALATED (max_iterations_reached) | not recorded (run file, brief: no Plan Review N/M) | not recorded (run file: no brief-saved line) |
| #533 | verified-rule-checks.md | 17.0.0 | 3 | 1h 25m | ESCALATED (max_iterations_reached) | 3/3 | 13m |
| #538 | automate-speed/02-phase45-rounds-on-new-defects.md | 17.0.2 | 3 | 51m | ESCALATED (max_iterations_reached) | 3/3 | 27m |
| #537 | automate-speed/01-question-gates-dont-stall.md | 17.0.2 | 3 | not recorded (run file: no FINALIZE or PR-opened line) | ESCALATED (max_iterations_reached) | 3/3 | 14m |
<!-- /pre -->

</details>

## Before/after comparison

<!-- share -->
```
post: 5 of 16 items at 3/3 (31.2%); rounds 0/1/2/3 = 1/3/7/5; 0 item(s) with rounds not recorded left out
post: Plan Review attempts 1/3, 2/3, 3/3 = 0, 3, 10; other caps 0; not recorded 3
pre: 15 of 58 items at 3/3 (25.9%); rounds 0/1/2/3 = 16/20/7/15; 54 item(s) with rounds not recorded left out
pre: Plan Review attempts 1/3, 2/3, 3/3 = 20, 9, 22; other caps 0; not recorded 61
pre (plugin >= 16.0.0): 7 of 7 items at 3/3 (100.0%); rounds 0/1/2/3 = 0/0/0/7; 0 item(s) with rounds not recorded left out
pre (plugin >= 16.0.0): Plan Review attempts 1/3, 2/3, 3/3 = 0, 0, 6; other caps 0; not recorded 1
```
<!-- /share -->

`share pre 16` is a slice of the pre group: plugin 16.0.0 to 17.0.2, the window in which the requirement observed "every `/automate` item since 2026-10-12" at 3/3.

## Excluded ledger rows

Each ledger row up to the cutoff that is not counted, with its reason (190 rows = 62 excluded + 128 counted; `#429` is counted by `items` but dropped by `table` as not merged):

<!-- excluded -->
```
line 1	#47 (no pr_url)	source=absent
line 2	#48 (no pr_url)	source=absent
line 3	#43 (no pr_url)	source=absent
line 4	#47 (no pr_url)	source=absent
line 5	#60 (no pr_url)	source=absent
line 6	#61 (no pr_url)	source=absent
line 7	#62 (no pr_url)	source=absent
line 8	#67 (no pr_url)	source=absent
line 9	#67 (no pr_url)	source=absent
line 10	#68 (no pr_url)	source=absent
line 11	#69 (no pr_url)	source=absent
line 12	#70	source=absent
line 13	#37	source=absent
line 14	#45	source=absent
line 15	#54	source=absent
line 16	#55	source=absent
line 17	#59	source=absent
line 18	#63	source=absent
line 19	#64	source=absent
line 20	#65	source=absent
line 21	#66	source=absent
line 22	#71	source=absent
line 23	#46	source=absent
line 24	#53	source=absent
line 25	#51	source=absent
line 26	#52	source=absent
line 27	#56	source=absent
line 28	#57	source=absent
line 29	#58	source=absent
line 30	#72	source=absent
line 31	#73	source=absent
line 32	#74	source=absent
line 33	#75	source=absent
line 34	#76	source=absent
line 35	#77	source=absent
line 36	#78	source=absent
line 37	#79	source=absent
line 38	#80	source=absent
line 39	#81	source=absent
line 40	#82	source=absent
line 41	#83	source=absent
line 42	#84	source=absent
line 54	#101	source=manual_postmortem
line 55	#100	source=manual_postmortem
line 56	#99	source=manual_postmortem
line 57	#98	source=manual_postmortem
line 58	#97	source=manual_postmortem
line 59	#96	source=manual_postmortem
line 60	#95	source=manual_postmortem
line 61	#94	source=manual_postmortem
line 62	#93	source=manual_postmortem
line 63	#92	source=manual_postmortem
line 65	#102	source=absent
line 78	#126	duplicate of line 79 (same pr_url; the latest ts, then the later line, is kept)
line 80	#129	source=absent
line 81	#130	source=absent
line 84	#141	source=absent
line 93	#194	source=absent
line 149	#429	PR not merged (recorded live read: CLOSED)
line 150	#428	plugin_version=unknown (no version to compare)
line 166	#472	source=absent
line 174	#536	source=absent
```
<!-- /excluded -->

## Commands

Paste block 1 into bash or zsh at the repo root; it defines the frozen inputs and four functions. Bash 3.2 and zsh print byte-identical output. Needs `jq` (1.6+) and BSD or GNU `sed`/`awk`. There is no new script file; the requirement says "no new tool".

```bash
# 0. Frozen inputs.
CUT=2026-10-18T09:35:11Z
L=.supervisor/postmortem/results.jsonl
A=.supervisor/automate
MERGED_POST='542 548 555 558 559 562 565 570 573 575 577 594 598 599 600 601'
NOT_MERGED='429'

# 1. Ledger rows that are NOT counted, with the reason.
excluded() {
  jq -rs --arg cut "$CUT" --arg post "$MERGED_POST" --arg nm "$NOT_MERGED" '
    [to_entries[] | .value + {line: (.key + 1)} | select(.ts <= $cut)] as $rows
    | ($rows | map(select(.source == "automate_drain" and .pr_url != null))
             | group_by(.pr_url) | map(max_by([.ts, .line]) | {key: .pr_url, value: .line}) | from_entries) as $kept
    | $rows[]
    | (if .source != "automate_drain" then "source=\(.source // "absent")"
       elif .pr_url == null then "no pr_url"
       elif $kept[.pr_url] != .line then "duplicate of line \($kept[.pr_url]) (same pr_url; the latest ts, then the later line, is kept)"
       elif ((.plugin_version // "") | test("^[0-9]+[.][0-9]+[.][0-9]+$") | not) then "plugin_version=\(.plugin_version // "absent") (no version to compare)"
       elif ((.pr_url | split("/") | last) | IN($nm | split(" ")[])) then "PR not merged (recorded live read: CLOSED)"
       elif (.plugin_version | split(".") | map(tonumber)) >= [17, 2, 0]
            and ((.pr_url | split("/") | last) | IN($post | split(" ")[]) | not) then "post-v17.2.0 PR not in the frozen merged list"
       else empty end) as $why
    | "line \(.line)\t\(if .pr_url then "#" + (.pr_url | split("/") | last) else "#\(.number) (no pr_url)" end)\t\($why)"' "$L"
}

# 2. Counted items, one per pr_url: group, PR URL, run_id, item, plugin_version, ledger rounds.
items() {
  jq -rs --arg cut "$CUT" '
    [to_entries[] | .value + {line: (.key + 1)}
     | select(.ts <= $cut and .source == "automate_drain" and .pr_url != null)]
    | group_by(.pr_url) | map(max_by([.ts, .line]))
    | map(select((.plugin_version // "") | test("^[0-9]+[.][0-9]+[.][0-9]+$")))
    | sort_by(.ts)[]
    | (.automate_key | split("\u001f")) as $k
    | [ (if (.plugin_version | split(".") | map(tonumber)) >= [17, 2, 0] then "post" else "pre" end),
        .pr_url, $k[0], $k[1], .plugin_version,
        (if has("self_heal_rounds") then (.self_heal_rounds | tostring) else "-" end) ] | @tsv' "$L"
}

# 3. One table row per item of group $1 (post | pre).
scv() { sed -nE "s/^ *(- )?$2: *\"?([^\"]*)\"? *\$/\2/p" "$1" 2>/dev/null | head -n 1; }
table() {
  printf '| PR | Item | Plugin | Phase 4.5 rounds | Phase 4.5 duration | Termination | Plan Review attempts | Launch Pad duration |\n'
  printf '|---|---|---|---|---|---|---|---|\n'
  items | awk -F '\t' -v g="$1" '$1 == g' | while IFS="$(printf '\t')" read -r grp url run item ver rl; do
    case " $NOT_MERGED " in *" ${url##*/} "*) continue ;; esac
    case " $MERGED_POST " in *" ${url##*/} "*) ;; *) [ "$grp" = post ] && continue ;; esac
    rf="$A/$run.md"; sc="$A/$run.supervisor-result.md"
    hd= hi= he= hs=
    if [ "$(scv "$sc" pr_url)" = "$url" ]; then
      hd=$(scv "$sc" heal_decision); hi=$(scv "$sc" heal_iterations); he=$(scv "$sc" error); hs=$(scv "$sc" summary)
    fi
    bf=$(grep -F "stamped — $item (" "$rf" 2>/dev/null | sed -nE 's/.*, brief ([^ )]+)\).*/\1/p' | head -n 1)
    bpr=$( [ -n "$bf" ] && sed -n '/^## Plan Review/,/^## [^P]/p' "$bf" 2>/dev/null | grep -oE 'attempt [0-9]+/[0-9]+' | head -n 1 | cut -d' ' -f2)
    { [ -f "$rf" ] && cat "$rf" || printf ''; } | jq -Rrs --arg item "$item" --arg url "$url" --arg ver "$ver" --arg rl "$rl" \
      --arg hd "$hd" --arg hi "$hi" --arg he "$he" --arg hs "$hs" --arg bpr "$bpr" '
      def t: (capture("^(- )+(?<t>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z) ") | .t) // null;
      def span($a; $b): if $a == null or $b == null then null
        else ((($b | fromdateiso8601) - ($a | fromdateiso8601)) / 60 | round) as $m
        | if $m < 0 then null elif $m >= 60 then "\($m / 60 | floor)h \($m % 60)m" else "\($m)m" end end;
      def nr($why): "not recorded (\($why))";
      def norm: sub("^[.]/"; "") | sub("^[.]supervisor/requirements/"; "");
      def picked: (capture("^(- )+([^ ]+ ){0,2}picked (item [0-9]+ [(](?<q>[^)]+[.]md)[)]|(?<p>[^ ;]+[.]md))"; "i")
        | (.q // .p) | norm) // null;
      def same: . != null and (. == ($item | norm) or ((contains("/") | not) and . == ($item | split("/") | last)));
      def saved: test("brief saved|launch[- ]pad saved|launch_pad_result saved"; "i")
        and (test("(no|not|never) (brief )?saved"; "i") | not);
      ($url | split("/") | last) as $n
      | split("\n") as $ls
      | [range(0; $ls | length) | select($ls[.] | picked != null)] as $p
      | ([$p[] | select($ls[.] | picked | same)] | first) as $s
      | (if $s == null then [] else
           $ls[$s:([$p[] | select(. > $s and ($ls[.] | picked | same | not))] | first // ($ls | length))] end) as $seg
      | ([range(0; $seg | length) | select($seg[.] | saved)] | first) as $si
      | ([range(0; $seg | length) | select($seg[.] | test("ran /autonomous"))] | first) as $ri
      | ([range(0; $seg | length) | select($seg[.] | test("^(- )+[^ ]+ (/autonomous done|ran supervisor)[ :]"))] | first) as $di
      | ($di // $ri) as $ei
      | (if $ei == null then null else $seg[$ei] end) as $ran
      | ([range(0; $ei // ($seg | length)) | select(($seg[.] | test("^(- )+[^ ]+ FINALIZE: "))
          or (($seg[.] | test("(pull/|PR #)\($n)([^0-9]|$)")) and (($seg[.] | test("FINALIZE|PR opened")) or . == $ri)))]
          | first) as $fi
      | ([$seg[0:(if $si == null then ($seg | length) else $si + 1 end)][]
          | capture("plan review[^0-9;]*(?<n>[0-9]+)/(?<c>[0-9]+)"; "i")] | max_by(.n | tonumber)) as $pr
      | (if $hd != "" then $hd else ([($ran // "") | capture("heal (?<d>PASS|ESCALATED|FAIL)") | .d] | first) end) as $dec
      | ([[$he, ($ran // ""), $hs][] | capture("(?<r>max_iterations_reached|needs_human)"; "i") | .r | ascii_downcase] | first) as $why
      | [ "#\($n)", ($item | sub("^[.]supervisor/requirements/"; "")), $ver,
          (if $rl != "-" then $rl elif $hi != "" then "\($hi) (sidecar)" else nr("ledger: no self_heal_rounds; sidecar: none for this PR") end),
          (if $s == null then nr("run file: no picked line")
           elif $ei == null then nr("run file: no end-of-RUN line")
           elif $fi == null then nr("run file: no FINALIZE or PR-opened line")
           else (span($seg[$fi] | t; $ran | t) // nr("run file: timestamp not ISO-8601 UTC")) end),
          (if $dec == null then nr("sidecar: none for this PR; run file: no heal decision")
           else $dec + (if $why then " (\($why))" else "" end) end),
          (if $pr != null then "\($pr.n)/\($pr.c)" elif $bpr != "" then "\($bpr) (brief)"
           else nr("run file, brief: no Plan Review N/M") end),
          (if $s == null then nr("run file: no picked line")
           elif $si == null then nr("run file: no brief-saved line")
           else (span($seg[0] | t; $seg[$si] | t) // nr("run file: timestamp not ISO-8601 UTC")) end)
        ] | "| " + join(" | ") + " |"'
  done
}

# 4. The 3/3 share of group $1, counting only items whose rounds are recorded; $2 = lowest plugin major (optional).
share() {
  table "$1" | awk -F ' [|] ' -v g="$1" -v min="${2:-0}" 'NR > 2 {
      split($3, v, "."); if (v[1] + 0 < min + 0) next
      r = $4; sub(/ .*/, "", r)
      if (r ~ /^[0-9]+$/) { n++; c[r]++; if (r == 3) k++ } else x++
      p = $7; sub(/ .*/, "", p); if (p ~ /^[0-9]+\/[0-9]+$/) pc[p]++; else px++ }
    END { w = g (min > 0 ? " (plugin >= " min ".0.0)" : "")
          printf "%s: %d of %d items at 3/3 (%.1f%%); rounds 0/1/2/3 = %d/%d/%d/%d; %d item(s) with rounds not recorded left out\n",
                 w, k, n, (n ? 100 * k / n : 0), c[0], c[1], c[2], c[3], x
          printf "%s: Plan Review attempts 1/3, 2/3, 3/3 = %d, %d, %d; other caps %d; not recorded %d\n",
                 w, pc["1/3"], pc["2/3"], pc["3/3"], length(pc) - (("1/3" in pc) + ("2/3" in pc) + ("3/3" in pc)), px }'
}
```

Block 2 prints the four outputs above:

```bash
excluded                              # → Excluded ledger rows
table post                            # → Post-v17.2.0 items
table pre                             # → Pre-v17.2.0 items
share post; share pre; share pre 16   # → Before/after comparison
```

Block 3 checks that a re-run prints what this file holds. Each block above sits between `<!-- name -->` markers.

```bash
blk() { sed -n "/^<!-- $1 -->\$/,/^<!-- \/$1 -->\$/p" docs/evidence/review-gate-rounds.md | sed '1d;$d' | grep -v '^```'; }
diff <(excluded) <(blk excluded) && diff <(table post) <(blk post) && diff <(table pre) <(blk pre) \
  && diff <(share post; share pre; share pre 16) <(blk share) && echo "all four blocks match"
```

To measure again later (the requirement's "re-run after Phase 1 lands"), raise `CUT`, add the newly merged PRs to `MERGED_POST` after a fresh merged-state read, and keep this file's numbers as the earlier measurement.

**Drift the cutoff cannot stop.** Run `automate-2026-10-13-181331` is still paused with one queue item left (`parallel-automate/18`). If it resumes, its single sidecar is overwritten with the next item's PR, and #555's sidecar match is lost. #555's row would not change: its rounds come from the ledger, and its `ran /autonomous` line gives the same `ESCALATED (max_iterations_reached)`. Every other run that holds a post-v17.2.0 item is a finished single-item lane run.

**Frozen-cutoff control** (scratch copy of the ledger under the session scratchpad, not the checkout). A copy of the last row was appended with `ts` 2026-10-19T00:00:00Z, PR 9999 and `self_heal_rounds: 3`. `table post` then printed the same bytes as on the real ledger. With `CUT` raised to 2026-10-19T00:00:00Z and 9999 added to `MERGED_POST`, `share post` read `6 of 17 items at 3/3 (35.3%)`.

## Recorded live reads (not re-run)

These reads are not in `## Commands`. They need network access or this machine's Claude Code transcripts, which are not on `loomwright-meta` and are pruned by retention.

### Merged state (`gh`, run 2026-10-18T18:15:43Z)

`for n in 542 548 555 558 559 562 565 570 573 575 577 594 598 599 600 601; do gh pr view "$n" --repo vikashruhilgit/loomwright --json state,mergedAt -q '[.state, .mergedAt] | @tsv'; done`

```
542	MERGED	2026-10-14T15:50:55Z
548	MERGED	2026-10-15T02:38:16Z
555	MERGED	2026-10-15T10:49:38Z
558	MERGED	2026-10-16T01:38:51Z
559	MERGED	2026-10-16T01:38:51Z
562	MERGED	2026-10-16T01:38:50Z
565	MERGED	2026-10-16T01:38:51Z
570	MERGED	2026-10-16T11:27:09Z
573	MERGED	2026-10-16T11:27:09Z
575	MERGED	2026-10-16T11:27:08Z
577	MERGED	2026-10-16T11:27:08Z
594	MERGED	2026-10-17T13:50:28Z
598	MERGED	2026-10-18T10:55:46Z
599	MERGED	2026-10-18T10:55:45Z
600	MERGED	2026-10-18T10:55:46Z
601	MERGED	2026-10-18T10:55:45Z
```

All 16 have base `main` (`--json baseRefName`). These 16 numbers are `MERGED_POST`.

For the pre group, `gh pr list --repo vikashruhilgit/loomwright --state merged --limit 1000 --json number -q '.[].number'` returned 476 merged PRs. Of the 113 pre-v17.2.0 PRs from `items`, only #429 was missing. `gh pr view 429 … --json state,mergedAt` gave `CLOSED` with no `mergedAt` (an `s3-validation` scratch item), so `NOT_MERGED='429'`.

### Per-item transcript report (`read-token-ledger.sh --per-item`, run 2026-10-18)

`bash loomwright/scripts/read-token-ledger.sh --per-item .supervisor/automate/<run_id>.md`, once for each run that holds a post-v17.2.0 item. It reads Claude Code transcripts under `~/.claude/projects/`. Token figures are real usage (context = input + cache creation + cache read); wall time is from run-file boundaries.

| PR | Run | Launch Pad wall | Plan-reviewer tokens (context / output) | Launch Pad context, all agents | Phase 4.5 wall |
|---|---|---|---|---|---|
| #562 | `…-L1` | 4h 34m 0s | 3104033 / 32703 | 16201386 | not recorded |
| #559 | `…-L2` | 15m 42s | 2163199 / 32931 | 14207178 | not recorded |
| #558 | `…-L3` | 12m 1s | 1962394 / 26707 | 9363780 | 1h 14m 25s |
| #573 | `…-L6` | 19m 37s | 4264212 / 52620 | 17668144 | not recorded |
| #570 | `…-L7` | 12m 20s | 2696717 / 29487 | 19352400 | 1h 7m 5s |
| #577 | `…-L8` | 49m 47s | 2943170 / 42060 | 23227035 | not recorded |
| #575 | `…-L9` | 29m 46s | 3954414 / 49226 | 17191826 | not recorded |
| #601 | `…-L11` | 15m 58s | 2481566 / 30963 | 16605967 | not recorded |
| #565, #594, #598, #599, #600 | `…-L4`, `-L10`, `-L13`, `-L14`, `-L12` | not recorded | not recorded | not recorded | not recorded |
| #542, #548, #555 | `automate-2026-10-13-181331` | no transcripts | no transcripts | no transcripts | no transcripts |

(`…` = `automate-2026-10-15-163325`.) Where both sources have a value, the transcript report agrees with the run-file columns after rounding to minutes. For the last two rows it prints `not recorded` (no brief-saved or `FINALIZE:` line) and `no_transcripts` (session ids `auto-2026-10-1x-…` have no transcript on this machine). The Phase 4.5 code-reviewer usage it prints for #558 (9966418 / 83096) and #570 (10535049 / 90697) is the only Phase 4.5 token data available.

## Draft condition (AC5)

`post-v17.2.0: 5 of 16 items at 3/3 (31.2%)`. That is less than half, so the classification of each new HIGH as (a) present before round 1 and missed, (b) introduced by a fix, or (c) found by a check earlier rounds did not run was not done. No draft was written under `.supervisor/requirements/proposed/`.

## Validation

Run 2026-10-18 on the branch's worktree, from the repo root. Re-run 2026-10-19 after the run-file line selectors were widened (PR-opened, end-of-RUN, `picked` and brief-saved shapes); the results below are from the re-run.

| Check | Result |
|---|---|
| `bash scripts/check-doc-currency.sh` | exit 0. Last line: `✓ doc-currency: all checked version/count claims match the authoritative source.` |
| `bash scripts/check-version-bump.sh` | exit 0: `bump-version: check OK — not bumped (version 17.8.0, the merge base's); 1 fragment(s) pending — legal, the next bump folds them (base origin/main, merge base 3a03dfa66d7d)` |
| `bash scripts/ci-local.sh --affected` | 16/16 passed: `ci-local --affected: PASS after 19s — 16 of the full run's 191 entries` |
| `## Commands` block 3 (re-run check) | `all four blocks match` in bash 3.2 and zsh. Mutation control: on a scratch copy of this file with #542's rounds changed from 2 to 3, block 3 prints that one-line diff and exits 1. |
| Frozen-cutoff control | see `## Commands`: an appended later row leaves `table post` byte-identical |

This change adds two files and edits nothing else. It does not touch `CHANGELOG.md`, `loomwright/.claude-plugin/plugin.json` or `.claude-plugin/marketplace.json`, and `bump-version.sh` was not run: this is a `--parallel` lane, so the wave branch carries the bump.
