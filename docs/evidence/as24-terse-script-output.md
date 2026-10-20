# as24: plugin scripts print one line by default, with full output behind `--verbose`

Requirement: `.supervisor/requirements/automate-speed/24-terse-script-output.md`. Base commit: `ee3d7ea3bb069c50a07c3b37222c52c88202263b`. All results below come from the integrated branch (subtasks 1–3 merged) on 2026-10-20. Line numbers are this tree's, not the base's.

## 1. One real run of each script, default vs `--verbose`

Each script ran once from this tree. Its `--verbose` output was then compared byte for byte with the **base-commit** script (`git archive ee3d7ea loomwright/scripts`) run on the same input.

| Script | Default | `--verbose` | `--verbose` vs base default |
|---|---|---|---|
| `classify-bot-review.sh` | 1 line, 50 B | 1 line, 344 B (compact JSON array) | byte-identical |
| `automate-lanes.sh lane-status <runfile>` | 25 lines, 6,363 B | 153 lines, 28,169 B | identical except the live `machine: … load1=` sample (the two runs were seconds apart) |
| `automate-helpers.sh plan-waves` `--max 4` / `--lint` / `--touches` | 2 / 7 / 14 lines | same bytes as default | byte-identical in all three modes (default is byte-identical too) |
| `read-project-memory.sh` | 19 lines, **4,440 B** | 19 lines, 4,424 B | byte-identical |
| `verify-provides.sh <brief> 3 --root <tree>` | 1 line, 52 B | 1 line, 1,345 B (JSON object) | byte-identical |

**`classify-bot-review.sh`**, run on `loomwright/scripts/fixtures/terse-output/classify-bot-review/input.json`:

```
$ classify-bot-review.sh < input.json
classify-bot-review: kept 2 of 5 (skipped_self 1)
$ classify-bot-review.sh --verbose < input.json
[{"id":1,"user":{"login":"claude[bot]"},"html_url":"https://github.com/o/r/pull/1#issuecomment-1", … }]   (344 B, = verbose.golden)
$ printf 'not json' | classify-bot-review.sh            # fail-safe path, exit 0
classify-bot-review: kept 0 of 0 (reason invalid_json)
```

(Both runs also print the pre-existing stderr line `classify-bot-review: skip_marker_filtered 1`, which is not stdout.)

**`lane-status`**, run on the live parent run `automate-2026-10-15-163325` (24 lanes) from the primary checkout. This is read-only observation:

```
$ automate-lanes.sh lane-status <parent_runfile>
lane-status: automate-2026-10-15-163325 — 24 lane(s) — 2026-10-20T06:58:09Z — started 2026-10-15T11:03:25Z
L1  removed — done  item=.supervisor/requirements/automate-speed/25-automate-load-by-mode.md  pr=https://github.com/vikashruhilgit/loomwright/pull/562  ended=2026-10-16T01:40:38Z  path=…/L1
…
L23  running  item=.supervisor/requirements/automate-speed/24-terse-script-output.md  pr=-  path=…/L23
L24  running  item=.supervisor/requirements/automate-speed/26-diet-subagent-prompts.md  pr=-  path=…/L24
$ automate-lanes.sh lane-status <parent_runfile> --verbose
(the same header and lane lines, plus each lane's detail lines, e.g. for L23:)
    steps: Pick ✓ · Plan ✓ · Build ✓ · [Heal 59m active] · Drain · Decide · Merge  (started 2026-10-20T05:34:23Z)
    progress: … / actions: … / last: …
wave 1 PR: https://github.com/vikashruhilgit/loomwright/pull/567  branch=wave/automate-2026-10-15-163325-w1  built 2026-10-16T00:12:45Z  merged  lanes L1,L2,L3,L4
…
machine: state=ok load1=19.08 cpus=12 mem_pressure=ok
keep-awake: held (Claude app — only while a Code session works)
keep-awake suggestion (run it yourself, or lane-status --keep-awake): caffeinate -i -w <pid> — a closed lid still sleeps
```

The machine modes were checked against the base script too. `lane-status --json` is identical once `generated_at` and the live `machine` sample are removed. `verify-provides.sh --parse-only` and `--kind-table` are byte-identical. AC 4's other half (`test-lanes-addon.sh`) is in §3.

**`plan-waves`**, run on `.supervisor/requirements/automate-speed/` from the main checkout:

```
$ automate-helpers.sh plan-waves .supervisor/requirements/automate-speed --max 4      (= with --verbose = base)
wave 1: …/10-coordinator-model-ab.md …/16-diet-automate-loop.md …/24-terse-script-output.md …/26-diet-subagent-prompts.md
wave 2: …/18-lock-the-gains.md
$ automate-helpers.sh plan-waves .supervisor/requirements/automate-speed --lint        (= with --verbose = base)
.supervisor/requirements/automate-speed/10-coordinator-model-ab.md: Touches ok; Depends on ok
…   (7 lines)
$ automate-helpers.sh plan-waves …/24-terse-script-output.md --touches                 (= with --verbose = base)
known
changelog.d/as24-terse-script-output.md
…   (14 lines)
```

**`read-project-memory.sh`**, run on this tree's tracked `.supervisor/memory/` store (the 18 entry lines are left out here because they are identical in both runs):

```
$ read-project-memory.sh
## Advisory project memory — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins) — 18 verified
- [2d32221d] …   (18 entry lines)
$ read-project-memory.sh --verbose
## Advisory project memory — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- [2d32221d] …   (the same 18 entry lines)
$ read-project-memory.sh            # cwd with no store, exit 0  (--verbose prints 0 bytes here, as before)
## Advisory project memory — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins) — 0 verified (no_store)
```

**`verify-provides.sh`**, run against this job's brief and this tree:

```
$ verify-provides.sh <brief> 3 --root <tree>
verify-provides: subtask 3 verified — present 4/4
$ verify-provides.sh --verbose <brief> 3 --root <tree>
{"subtask_id":"3","outputs_verified":[ …4 records with check_run… ],"outputs_gap":"","source":"verify-provides.sh"}   (1,345 B)
$ verify-provides.sh <brief> 4 --root <tree>        # before this subtask wrote its two files
verify-provides: subtask 4 gap — present 0/2, gap docs/evidence/as24-terse-script-output.md, changelog.d/as24-terse-script-output.md
$ verify-provides.sh <brief> 99 --root <tree>       # unverifiable, exit 0
verify-provides: subtask 99 unverifiable — present 0/0, reason subtask_not_found
```

### Honest results

- **`read-project-memory.sh` saves nothing. Its default is 16 bytes LONGER than before** (4,440 B vs 4,424 B). The design keeps one line per verified entry, because callers fold those facts in, and it adds `— <E> verified` to the banner. The gain is that an empty store now says so (`— 0 verified (no_store)`) where it used to print nothing. No byte saving is claimed.
- **`plan-waves` saves nothing, by decision.** `--verbose` is accepted and does nothing. The reasons: `--max`, `--lint` and `--touches` already print one line per wave, item or path. `--touches` must stay byte-identical because `lane-readiness` parses it (`automate-lanes.d/readiness.sh`, the `plan-waves "$d/$item" --touches` call). `--explain` is already the opt-in detail view. Four goldens captured from the pre-change script pin this: `loomwright/scripts/fixtures/terse-output/plan-waves/{max,lint,touches,explain}.golden`, checked by the `W-AS24` leg of `test-automate-helpers.d/13-plan-waves.sh`.
- The real savings: `lane-status` 28,169 → 6,363 B on a 24-lane run, `verify-provides.sh` 1,345 → 52 B per call, and `classify-bot-review.sh` 344 → 50 B on the fixture (more on a real PR's comment set). Every machine consumer passes `--verbose`, so it still pays the full size, as designed.

## 2. Consumer grep (AC 3)

The grep is `grep -rnF '<name>' --exclude=CHANGELOG.md .`, re-run on this integrated tree for each of the seven names. The hit counts are: `classify-bot-review.sh` 58, `read-project-memory.sh` 47, `verify-provides.sh` 134, `lane-status` 271, `plan-waves` 134, `automate-lanes.sh` 433, `automate-helpers.sh` 916. The worktree's `.supervisor/` holds no hits.

Kinds: script, prompt (agents/commands/skills), hook (the `/lanes` pane), test, fixture, prose (docs). Switch values: `--verbose`, `summary`, `no change: mode flag`, `no change: prose mention only`.

### 2.1 `classify-bot-review.sh` (58 hits, 24 files)

| Hit | Kind | Switch |
|---|---|---|
| `loomwright/scripts/review-heal-next-step.sh:460` (`bash "$HERE/classify-bot-review.sh" --verbose --trusted-actors …`) | script | `--verbose` |
| `loomwright/scripts/pr-postmortem-gather.sh:237` (`CLASSIFY_BIN=…`), run at `:239` (`bash "$CLASSIFY_BIN" --verbose`) | script | `--verbose` |
| `loomwright/scripts/test-classify-bot-review.sh:71` (`CLASSIFY=…`). It runs the script with `--verbose` at 22 call sites (cases 1–27 and their mutation controls). Its two call sites without the flag, `:525` and `:547`, test the default summary line and the fail-safe `(reason …)` lines | test | `--verbose` + summary |
| `loomwright/scripts/dispatch-pr-review.sh:303` (`DRAIN_SCRIPTS` file list. It copies or lists files and runs nothing) | script | no change: prose mention only |
| `loomwright/skills/review-heal/SKILL.md:251` (describes the driver's `classify` step as `scripts/classify-bot-review.sh --trusted-actors …`, without `--verbose`) | prompt | **no change: prose mention only**. It describes what `review-heal-next-step.sh classify` does and tells the model to run nothing. The driver, which is the real executor, passes `--verbose` at `:460`. This was subtask 1's open item. It was re-checked here and left unchanged |
| `loomwright/skills/review-heal/SKILL.md:271,355,480`; `loomwright/agents/review-pr.md:113`; `loomwright/skills/automate-loop/modes-and-merge-gate.md:64`; `loomwright/skills/self-heal-advisory/completion-tail.md:326` | prompt | no change: prose mention only |
| `loomwright/scripts/classify-bot-review.sh:2,120`; `wrap-external-text.sh:47,55,60,133`; `review-heal-next-step.sh:8,52`; `pr-postmortem-gather.sh:37,230,264,333,370` | script (comments) | no change: prose mention only |
| `loomwright/scripts/test-pr-postmortem-gather.sh:75,86,398,403,421,812`; `test-review-heal-next-step.sh:7`; `test-wrap-external-text.sh:5`; `test-no-fixed-sleep-race.sh:151` (a weights list); `fixtures/self-test-weights.tsv:36`; `fixtures/harvest-ledger/results.jsonl:18,24` | test / fixture | no change: prose mention only |
| `loomwright/docs/HOOKS.md:127`; `docs/loop-inventory/review-heal.md:94,95,96,143,288,330`; `docs/rationale/review-heal.md:175`; `docs/result-schemas/review-heal-next-step.md:66`; `docs/vendor-coupling-manifest.json:111,230,740`; `docs/evidence/as12-review-heal-drain-run.md:12,164,214`; `docs/evidence/as14-diet-review-heal.md:63,88,123,158,226`; `.github/workflows/claude-code-review.yml:282` (comment) | prose | no change: prose mention only |

### 2.2 `read-project-memory.sh` (47 hits, 26 files)

| Hit | Kind | Switch |
|---|---|---|
| `loomwright/scripts/build-handoff.sh:363` (`bash "$HELPERS_DIR/read-project-memory.sh" --verbose`, the handoff digest). `:362` is its existence guard | script | `--verbose` |
| `loomwright/agents/supervisor.md:102`, `loomwright/agents/launch-pad.md:224`, `loomwright/agents/code-reviewer.md:295`, `loomwright/docs/command-parts/dreaming/report.md:42` (`/dreaming` dedups against the verified facts) | prompt | summary. The default still prints one line per verified entry. `supervisor.md` now says `0 verified ⇒ proceed normally` |
| `loomwright/scripts/test-build-handoff.sh:317,319,324,330,331` (a mode-aware shim that proves the digest carries the `--verbose` output and not the terse header), `:396` (the pre-readers shim `exec … --verbose`) | test | `--verbose` |
| `loomwright/scripts/test-build-handoff.sh:17,260` (a source-reference check), `:392` (comment) | test | no change: prose mention only |
| `loomwright/scripts/test-project-memory.sh:31` (`READ=…`). It runs both modes and the new no-store / count cases | test | `--verbose` + summary |
| `loomwright/docs/loop-inventory/supervisor.md:66` (wording updated to `0 verified`), `loomwright/docs/loop-inventory/launch-pad-autonomous.md:69` | prose | no change: prose mention only |
| `loomwright/commands/handoff.md:5,40`; `loomwright/skills/rules/SKILL.md:26`; `loomwright/docs/command-parts/agent-help/knowledge.md:91` | prompt | no change: prose mention only. `/handoff` reaches the reader only through `build-handoff.sh` |
| `loomwright/scripts/build-handoff.sh:7,400`; `build-vault.sh:349`; `read-lessons.sh:3,9`; `write-project-memory.sh:52`; `retention-sweep.sh:123` (a row label string); `read-postmortem.sh:4`; `read-system-contract.sh:9`; `read-project-memory.sh:2,12,13` | script (comments/labels) | no change: prose mention only |
| `loomwright/docs/CORE_CONTRACT.md:60`; `loomwright/docs/ARCHITECTURE_CONTRACTS.md:246`; `loomwright/docs/SPIKES/P2b_MEMORY_DESIGN.md:39,101,106,147,180`; `loomwright/docs/SPIKES/LEARNING_LOOP_ROADMAP.md:66,127`; `loomwright/docs/rationale/launch-pad-autonomous.md:350`; `AGENT_GUIDELINES.md:165,171`; `loomwright/scripts/fixtures/corpus-briefs/done/2026-05-31-p4-consume-path.md:41` | prose | no change: prose mention only |

### 2.3 `verify-provides.sh` (134 hits, 53 files)

| Hit | Kind | Switch |
|---|---|---|
| `loomwright/agents/execute-manager.md:239` (`disk = Bash(… verify-provides.sh" --verbose {brief_path} {subtask_id} --root {worktree_path})`, which reads `disk.outputs_verified` / `disk.reason` / `disk.source`), plus its recorded `check_run` strings at `:254` and `:262` (`:262` elides the args with `…`) | prompt | `--verbose` |
| `loomwright/agents/supervisor.md:203` (Single-Agent gate), `:228` (Sequential gate) | prompt | `--verbose` |
| `loomwright/agents/worker.md:165` (Step 5.5 self-verification) | prompt | `--verbose` |
| `loomwright/docs/result-schemas/worker-result.md:54` | prose (the contract a worker follows) | `--verbose` |
| `loomwright/docs/CORE_CONTRACT.md:123` (the contract row now reads `[--verbose] <brief> <subtask-id> [--root <dir>]` and describes a one-summary-line default) | prose | updated with the change |
| `loomwright/agents/execute-manager.md:149`; `loomwright/skills/async-orchestration/SKILL.md:264` | prompt | no change: mode flag (`--kind-table`) |
| `loomwright/agents/launch-pad.md:522,610` | prompt | no change: mode flag (`--parse-only`) |
| `loomwright/scripts/test-verify-provides.sh:64` (`SCRIPT=…`). `run()` passes `--verbose` first (around `:104`), and the mutants and jq-less legs pass `--verbose`. The new `as24` section tests the default line (gap / verified / unverifiable) and `--verbose` in either position against the pre-change goldens in `fixtures/terse-output/verify-provides/`. `:464,512` test `--parse-only` and `:608` tests `--kind-table` (mode flags) | test | `--verbose` + summary |
| `loomwright/scripts/test-verify-provides.sh:244,569,572,576,629,641,644,659,661,668,682,683,689` (JSON-literal expectations and prompt-seam greps) | test | as the row above (they assert on `--verbose` output or grep prompt text) |
| `loomwright/scripts/supervisor-next-step.sh:121,639` and the `fixtures/supervisor-golden/**` copies of its gate text (`expected.out`, `expected/state.md`, `input/state.md`, `session-logs/*.json`) | script / fixture | no change: prose mention only. It names the script but runs nothing and passes no flags |
| `loomwright/scripts/check-children-settled.sh:8,14,20,26,62,107`; `validate-worker-result.py:117,118`; `verify-provides.sh`'s own 10 hits (its header and its `SELF=` name); `test-check-children-settled.sh:8`; `test-phase45-rounds-seam.sh:10`; `test-classify-risk.sh:6`; `test-no-pipefail-grep-q.sh:9` | script / test (comments) | no change: prose mention only |
| `loomwright/agents/execute-manager.md:255,303,309,337,504,606,792`; `loomwright/agents/supervisor.md:205,513`; `loomwright/agents/worker.md:123`; `loomwright/agents/launch-pad.md:400`; `loomwright/agents/orchestrator.md:48,304`; `loomwright/agents/plan-reviewer.md:224`; `loomwright/skills/async-orchestration/SKILL.md:173`; `loomwright/skills/supervisor-readiness/SKILL.md:338` | prompt | no change: prose mention only (`:309`'s `disk.source` check reads the `--verbose` object above) |
| `loomwright/docs/ARCHITECTURE_CONTRACTS.md:139,141,626,646,658`; `docs/FAILURE_ESCALATION.md:186,199,272`; `docs/loop-inventory/supervisor.md` (10 rows) and `launch-pad-autonomous.md:104,105,138`; `docs/result-schemas/agent-lifecycle-jsonl.md:167,255,259,268`; `docs/result-schemas/worker-result.md:51,52`; `fixtures/escalation-cause/s2c-files.json:1`; `fixtures/self-test-weights.tsv`; `fixtures/terse-output/verify-provides/*` (this change's goldens); `docs/evidence/as11-*`, `as13-*`, `as15-*` | prose / fixture | no change: prose mention only |

### 2.4 `lane-status` (271 hits, 46 files)

These are grouped by file. `summary` means the reader runs the default view and acts on the state on each lane line, which the terse view keeps. The default view now prints the header and each lane's first line, and `--watch` always passes `--verbose` (`automate-lanes.d/status.sh` `_lanes_watch`, `lanes_status "$1" --verbose` / `lanes_status --verbose`). Mode-flag rows use `--json`, `--inbox`, `--leaks`, `--resources`, `--tokens`, `--keep-awake`, `--refresh-readiness` or `--watch`. Their output is unchanged. `--keep-awake` still prints its start line first, which is the line the pane reads.

| File | Kind | Switch | Lines |
|---|---|---|---|
| `loomwright/docs/CORE_CONTRACT.md` | prose | no change: prose mention only | 110 |
| `loomwright/docs/loop-inventory/automate-loop.md` | prose | no change: prose mention only | 473,476,479,485,490,491,501,513,535,542,543,545 |
| `loomwright/docs/ARCHITECTURE_CONTRACTS.md` | prose | no change: prose mention only | 528,530 |
| `loomwright/docs/HOOKS.md` | prose | no change: prose mention only | 29,49 |
| `loomwright/docs/result-schemas/automate-run/parallel-lanes.md` | prose | no change: prose mention only | 12,29 |
| `loomwright/scripts/test-automate-lanes-modules.sh` | test | no change: prose mention only | 57 |
| `loomwright/scripts/test-automate-lanes.sh` | test | no change: prose mention only | 14,40,49 |
| `loomwright/scripts/guard-lane-wait-armed.sh` | script | no change: prose mention only | 37 |
| `loomwright/scripts/guard-lane-wait-armed.sh` | script | no change: mode flag | 148 |
| `loomwright/scripts/automate-lanes.sh` | script | no change: prose mention only | 66,70,72,73,135,207,208,210,216,245,249,250 |
| `loomwright/scripts/automate-lanes.sh` | script | no change: mode flag | 391 |
| `loomwright/scripts/automate-wave.sh` | script | no change: prose mention only | 35,174 |
| `loomwright/scripts/automate-helpers.sh` | script | no change: prose mention only | 42,96 |
| `loomwright/scripts/automate-helpers.sh` | script | no change: mode flag | 1114 |
| `loomwright/scripts/test-automate-lanes.d/03-fixes-to-finalize.sh` | test | no change: mode flag | 27,28,33,43,48,50,56,59,76,91,127,168,284,285,782,797,799,807 |
| `loomwright/scripts/test-automate-lanes.d/03-fixes-to-finalize.sh` | test | no change: prose mention only | 63,75,128,131,156,169 |
| `loomwright/scripts/test-automate-lanes.d/03-fixes-to-finalize.sh` | test | summary | 129,490,491 |
| `loomwright/scripts/test-automate-lanes.d/03-fixes-to-finalize.sh` | test | --verbose | 778,779,784 |
| `loomwright/scripts/test-automate-lanes.d/02-readiness-to-convert.sh` | test | no change: mode flag | 40,41,53,92,93,94,99,121,185,261,263,273,277,294 |
| `loomwright/scripts/test-automate-lanes.d/02-readiness-to-convert.sh` | test | --verbose | 52 |
| `loomwright/scripts/test-automate-lanes.d/02-readiness-to-convert.sh` | test | summary | 81 |
| `loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh` | test | no change: prose mention only | 317,381,398,519,528,601 |
| `loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh` | test | no change: mode flag | 347,355,395,444,454,457,474,475,482,491,493,498,500,501,520,586 |
| `loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh` | test | summary | 369,376,384,392,393 |
| `loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh` | test | --verbose | 374,437,441,442,472,479 |
| `loomwright/scripts/test-automate-lanes.d/05-timeline-and-gate.sh` | test | no change: mode flag | 191,578,581,590 |
| `loomwright/scripts/test-automate-lanes.d/05-timeline-and-gate.sh` | test | no change: prose mention only | 193,199,217,579 |
| `loomwright/scripts/test-automate-lanes.d/05-timeline-and-gate.sh` | test | --verbose | 205,214 |
| `loomwright/scripts/test-automate-lanes.d/04-fleet-closeout-to-optout.sh` | test | no change: mode flag | 32,655 |
| `loomwright/scripts/test-wave-build.sh` | test | no change: prose mention only | 223,412 |
| `loomwright/scripts/test-wave-build.sh` | test | no change: mode flag | 413 |
| `loomwright/scripts/test-guard-lane-wait-armed.sh` | test | no change: mode flag | 163,171 |
| `loomwright/scripts/fixtures/automate-helpers-help/hdr-lanes.golden` | fixture | no change: prose mention only | 12 |
| `loomwright/scripts/fixtures/terse-output/lane-status/verbose.golden` | fixture | no change: prose mention only | 1,22 |
| `loomwright/scripts/fixtures/terse-output/lane-status/default.golden` | fixture | no change: prose mention only | 1 |
| `loomwright/scripts/automate-lanes.d/relay.sh` | script | no change: prose mention only | 150,159 |
| `loomwright/scripts/automate-lanes.d/common.sh` | script | no change: prose mention only | 114,145 |
| `loomwright/scripts/automate-lanes.d/status-read.sh` | script | no change: prose mention only | 2,118,255,596,620,656,684 |
| `loomwright/scripts/automate-lanes.d/status-read.sh` | script | no change: mode flag (the --inbox lines this reader prints) | 138,143 |
| `loomwright/scripts/automate-lanes.d/status-read.sh` | script | summary (the terse header this reader prints) | 658 |
| `loomwright/scripts/automate-lanes.d/status-read.sh` | script | no change: mode flag | 682 |
| `loomwright/scripts/automate-lanes.d/readiness.sh` | script | no change: prose mention only | 13 |
| `loomwright/scripts/automate-lanes.d/status.sh` | script | no change: prose mention only | 2,16,90,110 |
| `loomwright/scripts/automate-lanes.d/status.sh` | script | summary (lines this reader prints itself) | 15,34,53 |
| `loomwright/scripts/automate-lanes.d/status.sh` | script | no change: mode flag | 66,217 |
| `loomwright/scripts/automate-lanes.d/park-leaks.sh` | script | no change: mode flag | 233 |
| `loomwright/scripts/automate-lanes.d/wave.sh` | script | no change: prose mention only | 113,129 |
| `loomwright/scripts/automate-lanes.d/wave.sh` | script | no change: mode flag | 249,250 |
| `loomwright/scripts/automate-lanes.d/remove.sh` | script | no change: prose mention only | 97,290 |
| `loomwright/scripts/test-token-ledger.sh` | test | no change: prose mention only | 1543 |
| `loomwright/scripts/automate-next-step.sh` | script | summary | 1102,1103,1211 |
| `loomwright/skills/automate-loop/command-lanes.md` | prompt | summary | 5 |
| `loomwright/skills/automate-loop/command-lanes.md` | prompt | no change: prose mention only | 9 |
| `loomwright/skills/automate-loop/per-item-loop.md` | prompt | no change: prose mention only | 13 |
| `loomwright/skills/automate-loop/lanes.md` | prompt | summary; --verbose for the detail lines | 17,22,24 |
| `loomwright/skills/automate-loop/lanes.md` | prompt | no change: mode flag | 19,55,56,78,97,103 |
| `loomwright/skills/automate-loop/lanes.md` | prompt | summary | 34,39,59,74,98,99 |
| `loomwright/skills/automate-loop/lanes.md` | prompt | no change: prose mention only | 36,48,67 |
| `loomwright/skills/automate-loop/lanes.md` | prompt | --verbose | 91 |
| `docs/evidence/tr08b-single-lane-sequential.md` | prose | no change: prose mention only | 21 |
| `docs/evidence/as19-split-lanes-and-trail-scripts.md` | prose | no change: prose mention only | 133,134,135,136,146,163 |
| `README.md` | prose | no change: prose mention only | 141 |
| `scripts/test-lanes-addon.sh` | test | no change: prose mention only | 8,12,13,55 |
| `scripts/test-lanes-addon.sh` | test | no change: mode flag | 45,50,54,56,57,81,87,89,90 |
| `.claude-plugin/marketplace.json` | prose | no change: prose mention only | 109 |
| `.github/workflows/ci.yml` | prose | no change: prose mention only | 112 |
| `loomwright-lanes/types/index.d.ts` | prose | no change: prose mention only | 1,3,153 |
| `loomwright-lanes/tests/pane.test.tsx` | test | no change: prose mention only | 4,263,397,568 |
| `loomwright-lanes/tests/pane.test.tsx` | test | no change: mode flag | 47,78,125,127,132,160,169,174,264,332,340,341,343,357,404,466,499 |
| `loomwright-lanes/README.md` | prose | no change: prose mention only | 5,18,20,23,26,33,36,43 |
| `loomwright-lanes/hooks/register.tsx` | hook | no change: prose mention only | 2,5,36,65,327,355,444,504,616 |
| `loomwright-lanes/hooks/register.tsx` | hook | no change: mode flag | 226,332,333,623 |
| `loomwright-lanes/.claude-plugin/plugin.json` | prose | no change: prose mention only | 4 |
| `CLAUDE.md` | prose | no change: prose mention only | 32 |

### 2.5 `plan-waves` (134 hits, 39 files)

Every `plan-waves` mode prints the same bytes as at the base commit, and `--verbose` is a no-op (§1, Honest results). So every executing hit is `no change: mode flag`, whatever mode it uses (`--max`, `--lint`, `--touches`, `--explain`).

| File | Kind | Switch | Lines |
|---|---|---|---|
| `loomwright/agents/product-owner.md` | prompt | no change: mode flag | 117,118 |
| `loomwright/docs/CORE_CONTRACT.md` | prose | no change: prose mention only | 77 |
| `loomwright/docs/loop-inventory/automate-loop.md` | prose | no change: prose mention only | 72,73,74,203,474,508,655 |
| `loomwright/docs/result-schemas/ground-truth-json.md` | prose | no change: prose mention only | 231 |
| `loomwright/scripts/propose-work.sh` | script | no change: prose mention only | 350 |
| `loomwright/scripts/propose-domain.sh` | script | no change: prose mention only | 896 |
| `loomwright/scripts/test-propose-from-verify.sh` | test | no change: prose mention only | 75 |
| `loomwright/scripts/test-propose-from-verify.sh` | test | no change: mode flag | 76,79,89 |
| `loomwright/scripts/test-automate-helpers.d/10-reconcile-status.sh` | test | no change: prose mention only | 558 |
| `loomwright/scripts/test-automate-helpers.d/13-plan-waves.sh` | test | no change: prose mention only | 2,335,345,431,713,714 |
| `loomwright/scripts/test-automate-helpers.d/13-plan-waves.sh` | test | no change: mode flag | 20,39,225,228,234,237,239,245,248,267,273,276,278,279,320,329,332,491,577,655,658,716,723,725 |
| `loomwright/scripts/test-propose-domain.sh` | test | no change: prose mention only | 318 |
| `loomwright/scripts/test-propose-domain.sh` | test | no change: mode flag | 319,322 |
| `loomwright/scripts/automate-wave.sh` | script | no change: prose mention only | 40 |
| `loomwright/scripts/test-propose-work.sh` | test | no change: prose mention only | 248 |
| `loomwright/scripts/test-propose-work.sh` | test | no change: mode flag | 249,252 |
| `loomwright/scripts/test-automate-dismissed.sh` | test | no change: mode flag | 964,970 |
| `loomwright/scripts/test-wave-scope.sh` | test | no change: prose mention only | 4,9,16,141 |
| `loomwright/scripts/test-wave-scope.sh` | test | no change: mode flag | 138,147,149,151,153,155,156,158,165,173,177 |
| `loomwright/scripts/automate-helpers.sh` | script | no change: prose mention only | 170,1064,1065,1066 |
| `loomwright/scripts/automate-helpers.sh` | script | no change: mode flag | 1096 |
| `loomwright/scripts/test-automate-helpers.sh` | test | no change: prose mention only | 167,179,320 |
| `loomwright/scripts/test-automate-helpers.sh` | test | no change: mode flag | 404 |
| `loomwright/scripts/test-automate-helpers-dispatch.sh` | test | no change: prose mention only | 44 |
| `loomwright/scripts/propose-from-verify.sh` | script | no change: prose mention only | 114 |
| `loomwright/scripts/fixtures/automate-helpers-help/plan-waves.golden` | fixture | no change: prose mention only | 1,2,3 |
| `loomwright/scripts/test-skills-index-companion.sh` | test | no change: prose mention only | 6,11,36,76,77 |
| `loomwright/scripts/test-skills-index-companion.sh` | test | no change: mode flag | 57,73 |
| `loomwright/scripts/automate-helpers.d/reconcile-status.sh` | script | no change: prose mention only | 32 |
| `loomwright/scripts/automate-helpers.d/plan-waves.sh` | script | no change: prose mention only | 2,3,4,5,8,16 |
| `loomwright/scripts/automate-helpers.d/plan-waves.sh` | script | no change: mode flag | 90,91,267 |
| `loomwright/scripts/test-rule-conformance-seam.sh` | test | no change: prose mention only | 37 |
| `loomwright/scripts/test-rule-conformance-seam.sh` | test | no change: mode flag | 383 |
| `loomwright/scripts/automate-lanes.d/readiness.sh` | script | no change: prose mention only | 7,194,205 |
| `loomwright/scripts/automate-lanes.d/readiness.sh` | script | no change: mode flag | 201 |
| `loomwright/scripts/automate-dismissed.sh` | script | no change: prose mention only | 395 |
| `loomwright/commands/product-owner.md` | prompt | no change: mode flag | 291,292 |
| `loomwright/commands/automate.md` | prompt | no change: mode flag | 56 |
| `loomwright/commands/propose.md` | prompt | no change: mode flag | 113 |
| `loomwright/skills/user-story-writing/SKILL.md` | prompt | no change: mode flag | 73,187,295,296 |
| `loomwright/skills/automate-loop/helpers.md` | prompt | no change: prose mention only | 30 |
| `loomwright/skills/automate-loop/helpers.md` | prompt | no change: mode flag | 52 |
| `loomwright/skills/automate-loop/resume.md` | prompt | no change: prose mention only | 11 |
| `loomwright/skills/automate-loop/intake.md` | prompt | no change: mode flag | 30 |
| `loomwright/skills/automate-loop/lanes.md` | prompt | no change: mode flag | 18 |
| `loomwright/skills/automate-loop/lanes.md` | prompt | no change: prose mention only | 54 |
| `docs/evidence/as21-split-automate-helpers-tests.md` | prose | no change: prose mention only | 25,128,158,224,324 |
| `docs/evidence/as05-golden-run-tests.md` | prose | no change: prose mention only | 377 |
| `docs/evidence/as06-next-step-driver-tail.md` | prose | no change: prose mention only | 112 |
| `docs/evidence/as07-next-step-drain-and-run.md` | prose | no change: prose mention only | 226 |
| `docs/evidence/automate-speed-baseline.md` | prose | no change: prose mention only | 828 |
| `scripts/check-doc-currency.sh` | script | no change: prose mention only | 62 |

### 2.6 `automate-lanes.sh` (433 hits) and `automate-helpers.sh` (916 hits)

Both are dispatchers. Only their `lane-status` and `plan-waves` subcommands changed, plus the `#:  lane-status` help line, which is pinned by `fixtures/automate-helpers-help/hdr-lanes.golden` and checked by `test-automate-helpers-dispatch.sh`. A hit that names `lane-status` or `plan-waves` is listed in §2.4 or §2.5 (the "covered" column). Every other executing hit runs a **different** subcommand, binds the script path, or builds a mutation copy. Those subcommands' output is unchanged, so each is `no change: mode flag`. The subcommands those hits run were extracted from the hit lines, and the extracted set contains neither `lane-status` nor `plan-waves`. Prose-only files (the rest: 522 + 261 comment/doc hits in 154 files) are not listed. The kind and line columns cover only executing hits.

`automate-helpers.sh`:

| File | Kind | Covered in §2.4/§2.5 | Other executing hits | Switch |
|---|---|---|---|---|
| `loomwright/agents/product-owner.md` | prompt | 1 | 0 | — |
| `loomwright/docs/CORE_CONTRACT.md` | prose | 2 | 0 | — |
| `loomwright/docs/loop-inventory/automate-loop.md` | prose | 5 | 0 | — |
| `loomwright/scripts/test-loop-inventory.sh` | test | 0 | 3 | no change: mode flag — lines 521,570,597 |
| `loomwright/scripts/test-propose-from-verify.sh` | test | 2 | 0 | — |
| `loomwright/scripts/test-automate-helpers.d/12-meta.sh` | test | 0 | 4 | no change: mode flag — lines 124,128,137,138 |
| `loomwright/scripts/test-automate-helpers.d/04-resume.sh` | test | 0 | 13 | no change: mode flag — lines 71,72,73,74,170,171,172,174,181,195,196,197,200 (subcommands: resume-glob) |
| `loomwright/scripts/test-automate-helpers.d/08-learning-emit.sh` | test | 0 | 3 | no change: mode flag — lines 485,599,657 |
| `loomwright/scripts/test-automate-helpers.d/10-reconcile-status.sh` | test | 0 | 18 | no change: mode flag — lines 81,82,210,211,212,214,223,304,392,393,396,462,490,526,599,620,670,688 (subcommands: rs of) |
| `loomwright/scripts/test-automate-helpers.d/15-lane-seams.sh` | test | 0 | 2 | no change: mode flag — lines 132,137 (subcommands: pick-guard) |
| `loomwright/scripts/test-automate-helpers.d/14-escalation.sh` | test | 0 | 20 | no change: mode flag — lines 124,125,126,127,172,173,174,175,200,201,202,203,215,216,217,218,219,282,283,294 |
| `loomwright/scripts/test-automate-helpers.d/02-runfile.sh` | test | 0 | 20 | no change: mode flag — lines 240,241,242,243,244,343,344,345,400,401,403,501,502,503,540,541,542,577,578,579 (subcommands: progress-append crd cr) |
| `loomwright/scripts/test-automate-helpers.d/13-plan-waves.sh` | test | 0 | 1 | no change: mode flag — lines 292 |
| `loomwright/scripts/test-automate-helpers.d/03-intake.sh` | test | 0 | 8 | no change: mode flag — lines 81,82,83,190,191,192,193,194 (subcommands: resolve-backlog resolve-folder) |
| `loomwright/scripts/test-automate-helpers.d/06-gate-eval-tail.sh` | test | 0 | 6 | no change: mode flag — lines 36,37,38,47,58,63 (subcommands: gate-eval) |
| `loomwright/scripts/test-automate-helpers.d/16-queue-gates.sh` | test | 0 | 2 | no change: mode flag — lines 232,235 (subcommands: queue-confirm resolve-backlog) |
| `loomwright/scripts/test-automate-helpers.d/05-gate-eval-harness.sh` | test | 0 | 2 | no change: mode flag — lines 43,118 (subcommands: gate-eval) |
| `loomwright/scripts/test-automate-helpers.d/09-brief-repair.sh` | test | 0 | 11 | no change: mode flag — lines 99,101,154,155,160,237,238,242,243,244,252 |
| `loomwright/scripts/test-automate-helpers.d/07-rules-gate.sh` | test | 0 | 11 | no change: mode flag — lines 198,202,203,204,229,255,277,608,667,712,734 (subcommands: gate-eval) |
| `loomwright/scripts/test-automate-helpers.d/11-ceiling.sh` | test | 0 | 2 | no change: mode flag — lines 102,118 (subcommands: ceiling-check) |
| `loomwright/scripts/test-automate-helpers.d/05-gate-eval.sh` | test | 0 | 1 | no change: mode flag — lines 170 (subcommands: gate-eval) |
| `loomwright/scripts/test-propose-domain.sh` | test | 1 | 0 | — |
| `loomwright/scripts/test-automate-trail.sh` | test | 0 | 1 | no change: mode flag — lines 173 |
| `loomwright/scripts/automate-lanes.sh` | script | 0 | 1 | no change: mode flag — lines 273 |
| `loomwright/scripts/dispatch-pr-review.sh` | script | 0 | 1 | no change: mode flag — lines 332 (subcommands: escalation-cause) |
| `loomwright/scripts/migrate-branch-mode.sh` | script | 0 | 1 | no change: mode flag — lines 131 |
| `loomwright/scripts/test-propose-work.sh` | test | 1 | 0 | — |
| `loomwright/scripts/test-automate-next-step.sh` | test | 0 | 11 | no change: mode flag — lines 209,1235,1236,1290,1291,1774,1775,1806,1809,1929,1930 (subcommands: gate-eval) |
| `loomwright/scripts/test-automate-dismissed.sh` | test | 0 | 1 | no change: mode flag — lines 76 |
| `loomwright/scripts/review-heal-next-step.sh` | script | 0 | 1 | no change: mode flag — lines 240 (subcommands: escalation-cause) |
| `loomwright/scripts/test-wave-scope.sh` | test | 2 | 1 | no change: mode flag — lines 24 |
| `loomwright/scripts/test-requirement-shape.sh` | test | 0 | 1 | no change: mode flag — lines 24 |
| `loomwright/scripts/automate-merge-watch.sh` | script | 0 | 2 | no change: mode flag — lines 129,336 (subcommands: progress-append closeout) |
| `loomwright/scripts/lane-policy.sh` | script | 0 | 1 | no change: mode flag — lines 86 |
| `loomwright/scripts/test-session-resume.sh` | test | 0 | 2 | no change: mode flag — lines 1643,1644 (subcommands: and) |
| `loomwright/scripts/test-automate-helpers.sh` | test | 0 | 5 | no change: mode flag — lines 221,223,225,226,228 (subcommands: bundle) |
| `loomwright/scripts/test-automate-lanes.d/03-fixes-to-finalize.sh` | test | 0 | 16 | no change: mode flag — lines 71,204,288,315,379,380,409,416,419,422,426,462,530,672,698,815 (subcommands: ceiling-check lane-park-notify sidecar-check) |
| `loomwright/scripts/test-automate-lanes.d/02-readiness-to-convert.sh` | test | 0 | 3 | no change: mode flag — lines 503,559,560 (subcommands: bash lane-convert-ready dispatches) |
| `loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh` | test | 0 | 4 | no change: mode flag — lines 406,547,548,645 (subcommands: current-set lane-wait) |
| `loomwright/scripts/test-automate-lanes.d/05-timeline-and-gate.sh` | test | 0 | 6 | no change: mode flag — lines 279,284,285,506,541,543 (subcommands: bash validation-gate current-escalation) |
| `loomwright/scripts/test-automate-lanes.d/04-fleet-closeout-to-optout.sh` | test | 0 | 14 | no change: mode flag — lines 28,138,156,243,318,338,346,350,409,412,414,417,562,583 (subcommands: bash progress-append current-set wave-plan) |
| `loomwright/scripts/test-automate-golden.sh` | test | 0 | 5 | no change: mode flag — lines 150,152,154,155,653 (subcommands: bundle) |
| `loomwright/scripts/test-automate-trail.d/06-sweep.sh` | test | 0 | 1 | no change: mode flag — lines 345 (subcommands: closeout) |
| `loomwright/scripts/test-automate-trail.d/04-watcher-branch-mode.sh` | test | 0 | 5 | no change: mode flag — lines 115,153,560,578,648 (subcommands: trail-pr) |
| `loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh` | test | 0 | 26 | no change: mode flag — lines 6,25,72,86,87,94,108,109,121,130,258,266,310,329,362,374,379,446,458,511,515,588,607,627,638,650 (subcommands: closeout fe co) |
| `loomwright/scripts/test-automate-trail.d/03-stamps-gate.sh` | test | 0 | 10 | no change: mode flag — lines 68,107,179,185,297,324,362,395,453,460 (subcommands: trail-pr closeout tg) |
| `loomwright/scripts/test-automate-trail.d/02-closeout.sh` | test | 0 | 12 | no change: mode flag — lines 14,15,45,105,106,125,132,171,191,219,329,344 (subcommands: closeout) |
| `loomwright/scripts/test-automate-trail.d/01-sidecar-trail-pr.sh` | test | 0 | 2 | no change: mode flag — lines 439,525 (subcommands: trail-pr) |
| `loomwright/scripts/test-automate-helpers-dispatch.sh` | test | 0 | 3 | no change: mode flag — lines 38,117,118 |
| `loomwright/scripts/test-wave-build.sh` | test | 0 | 3 | no change: mode flag — lines 209,210,352 (subcommands: wave-build) |
| `loomwright/scripts/test-automate-loop-split.sh` | test | 0 | 1 | no change: mode flag — lines 481 (subcommands: test-automate-trail) |
| `loomwright/scripts/test-dispatch-pr-review.sh` | test | 0 | 2 | no change: mode flag — lines 944,964 (subcommands: escalation-cause) |
| `loomwright/scripts/propose-from-verify.sh` | script | 1 | 0 | — |
| `loomwright/scripts/retention-sweep.sh` | script | 0 | 1 | no change: mode flag — lines 129 (subcommands: brief-repair) |
| `loomwright/scripts/test-script-event-telemetry.sh` | test | 0 | 2 | no change: mode flag — lines 274,308 (subcommands: sidecar-check) |
| `loomwright/scripts/test-skills-index-companion.sh` | test | 1 | 1 | no change: mode flag — lines 27 |
| `loomwright/scripts/test-reconcile-jobs.sh` | test | 0 | 1 | no change: mode flag — lines 32 |
| `loomwright/scripts/automate-helpers.d/plan-waves.sh` | script | 1 | 0 | — |
| `loomwright/scripts/test-verify-queue.sh` | test | 0 | 3 | no change: mode flag — lines 70,105,210 (subcommands: resolve-folder) |
| `loomwright/scripts/test-run-ground-truth.sh` | test | 0 | 2 | no change: mode flag — lines 789,810 (subcommands: sidecar-check) |
| `loomwright/scripts/test-rule-conformance-seam.sh` | test | 1 | 0 | — |
| `loomwright/scripts/automate-lanes.d/readiness.sh` | script | 1 | 0 | — |
| `loomwright/scripts/test-review-heal-next-step.sh` | test | 0 | 1 | no change: mode flag — lines 260 (subcommands: sidecar-check) |
| `loomwright/scripts/test-build-handoff.sh` | test | 0 | 3 | no change: mode flag — lines 607,611,613 (subcommands: and) |
| `loomwright/scripts/automate-trail.d/closeout.sh` | script | 0 | 2 | no change: mode flag — lines 95,147 (subcommands: current-set) |
| `loomwright/scripts/automate-trail.d/trail-pr.sh` | script | 0 | 2 | no change: mode flag — lines 232,354 (subcommands: reconcile-item progress-append) |
| `loomwright/scripts/automate-trail.d/finalize.sh` | script | 0 | 2 | no change: mode flag — lines 87,187 |
| `loomwright/scripts/automate-next-step.sh` | script | 0 | 16 | no change: mode flag — lines 249,260,328,441,454,477,998,1143,1331,1402,1677,1698,1747,2031,2326,2551 (subcommands: not resume-glob runfile-write current-rebuild closeout-classify config-suppress config-restore) |
| `loomwright/scripts/automate-dismissed.sh` | script | 1 | 1 | no change: mode flag — lines 805 (subcommands: progress-append) |
| `loomwright/commands/verify.md` | prompt | 0 | 1 | no change: mode flag — lines 154 |
| `loomwright/commands/product-owner.md` | prompt | 1 | 0 | — |
| `loomwright/commands/automate.md` | prompt | 1 | 9 | no change: mode flag — lines 60,67,74,92,98,99,103,105,112 (subcommands: sweep ceiling-check pick-guard lane-info meta-entry) |
| `loomwright/commands/pr-postmortem.md` | prompt | 0 | 1 | no change: mode flag — lines 50 (subcommands: learning-emit) |
| `loomwright/commands/propose.md` | prompt | 1 | 0 | — |
| `loomwright/skills/self-heal-advisory/completion-tail.md` | prompt | 0 | 2 | no change: mode flag — lines 300,303 (subcommands: closeout reconcile-status) |
| `loomwright/skills/verify-walkthrough/SKILL.md` | prompt | 0 | 1 | no change: mode flag — lines 311 (subcommands: resolve-folder) |
| `loomwright/skills/user-story-writing/SKILL.md` | prompt | 2 | 0 | — |
| `loomwright/skills/automate-loop/branch-mode.md` | prompt | 0 | 2 | no change: mode flag — lines 6,9 (subcommands: meta-entry meta-push-failed) |
| `loomwright/skills/automate-loop/helpers.md` | prompt | 1 | 6 | no change: mode flag — lines 6,9,51,53,55,57 (subcommands: closeout) |
| `loomwright/skills/automate-loop/invariants.md` | prompt | 0 | 3 | no change: mode flag — lines 3,8,9 (subcommands: gate-eval) |
| `loomwright/skills/automate-loop/resume.md` | prompt | 1 | 5 | no change: mode flag — lines 3,7,12,28,29 (subcommands: resume-glob meta-entry current-rebuild reconcile-status dismissed-pending) |
| `loomwright/skills/automate-loop/modes-and-merge-gate.md` | prompt | 0 | 4 | no change: mode flag — lines 22,41,43,76 (subcommands: gate-eval) |
| `loomwright/skills/automate-loop/intake.md` | prompt | 0 | 2 | no change: mode flag — lines 37,39 (subcommands: queue-confirm lane-info) |
| `loomwright/skills/automate-loop/SKILL.md` | prompt | 0 | 5 | no change: mode flag — lines 143,147,150,157,395 (subcommands: remaining runfile-write current-set gate-eval) |
| `loomwright/skills/automate-loop/per-item-loop.md` | prompt | 1 | 8 | no change: mode flag — lines 5,27,36,44,54,69,72,111 (subcommands: closeout trail-pr sweep brief-repair trail-gate) |
| `loomwright/skills/automate-loop/lanes.md` | prompt | 2 | 6 | no change: mode flag — lines 3,7,9,11,58,65 (subcommands: init-check lane-info pick-guard lane-drain-check) |
| `loomwright/skills/review-heal/SKILL.md` | prompt | 0 | 1 | no change: mode flag — lines 472 |
| `loomwright/skills/review-heal/escalation.md` | prompt | 0 | 1 | no change: mode flag — lines 15 (subcommands: escalation-cause) |
| `docs/evidence/automate-speed-baseline.md` | prose | 1 | 0 | — |

`automate-lanes.sh`:

| File | Kind | Covered in §2.4/§2.5 | Other executing hits | Switch |
|---|---|---|---|---|
| `loomwright/docs/loop-inventory/automate-loop.md` | prose | 12 | 0 | — |
| `loomwright/docs/HOOKS.md` | prose | 1 | 0 | — |
| `loomwright/scripts/test-automate-lanes-modules.sh` | test | 0 | 18 | no change: mode flag — lines 44,63,75,76,79,100,102,209,210,240,242,246,273,275,279,281,291,304 (subcommands: unreadable byte-for-byte) |
| `loomwright/scripts/test-automate-lanes.sh` | test | 0 | 2 | no change: mode flag — lines 97,124 (subcommands: bundle) |
| `loomwright/scripts/test-automate-helpers.d/15-lane-seams.sh` | test | 0 | 2 | no change: mode flag — lines 69,73 |
| `loomwright/scripts/guard-lane-wait-armed.sh` | script | 0 | 1 | no change: mode flag — lines 49 |
| `loomwright/scripts/automate-wave.sh` | script | 0 | 1 | no change: mode flag — lines 84 (subcommands: unreadable) |
| `loomwright/scripts/test-wave-scope.sh` | test | 0 | 1 | no change: mode flag — lines 23 |
| `loomwright/scripts/automate-helpers.sh` | script | 2 | 4 | no change: mode flag — lines 1111,1112,1113,1115 |
| `loomwright/scripts/test-automate-lanes.d/03-fixes-to-finalize.sh` | test | 0 | 23 | no change: mode flag — lines 564,565,567,568,570,608,609,611,612,613,618,619,620,647,648,651,652,653,703,704,706,707,708 (subcommands: ac) |
| `loomwright/scripts/test-automate-lanes.d/06-phase-sessions.sh` | test | 0 | 13 | no change: mode flag — lines 22,23,25,37,38,39,91,92,93,124,154,155,157 (subcommands: phase-check phase-launch relay-hook phase-answer lane-launch) |
| `loomwright/scripts/test-automate-lanes.d/02-readiness-to-convert.sh` | test | 0 | 15 | no change: mode flag — lines 177,179,211,304,305,306,347,348,349,421,422,423,471,472,473 (subcommands: lane-remove) |
| `loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh` | test | 0 | 12 | no change: mode flag — lines 17,44,45,160,161,240,241,248,249,271,272,273 (subcommands: relay-hook lane-launch lane-remove) |
| `loomwright/scripts/test-automate-lanes.d/05-timeline-and-gate.sh` | test | 0 | 9 | no change: mode flag — lines 435,436,439,515,516,519,585,586,589 (subcommands: vg) |
| `loomwright/scripts/test-automate-lanes.d/04-fleet-closeout-to-optout.sh` | test | 0 | 10 | no change: mode flag — lines 561,565,566,567,575,576,577,578,583,586 (subcommands: wave-plan has fleet-closeout) |
| `loomwright/scripts/test-automate-golden.sh` | test | 0 | 2 | no change: mode flag — lines 595,596 |
| `loomwright/scripts/test-wave-build.sh` | test | 0 | 4 | no change: mode flag — lines 21,322,323,330 (subcommands: bundle still) |
| `loomwright/scripts/test-guard-lane-wait-armed.sh` | test | 0 | 4 | no change: mode flag — lines 22,104,128,220 (subcommands: lane-wait not) |
| `loomwright/scripts/fixtures/automate-helpers-help/hdr-lanes.golden` | fixture | 1 | 0 | — |
| `loomwright/scripts/test-script-event-telemetry.sh` | test | 0 | 3 | no change: mode flag — lines 316,342,357 (subcommands: fleet-closeout) |
| `loomwright/scripts/automate-lanes.d/relay.sh` | script | 0 | 3 | no change: mode flag — lines 57,72,109 (subcommands: lane-answer relay-hook phase-answer) |
| `loomwright/scripts/automate-lanes.d/launch.sh` | script | 0 | 1 | no change: mode flag — lines 239 |
| `loomwright/scripts/automate-lanes.d/phase.sh` | script | 0 | 1 | no change: mode flag — lines 79 |
| `loomwright/scripts/automate-lanes.d/park-leaks.sh` | script | 0 | 2 | no change: mode flag — lines 174,180 |
| `loomwright/scripts/automate-lanes.d/create.sh` | script | 0 | 1 | no change: mode flag — lines 109 |
| `loomwright/skills/automate-loop/helpers.md` | prompt | 0 | 4 | no change: mode flag — lines 46,47,48,49 |
| `loomwright/skills/automate-loop/command-lanes.md` | prompt | 1 | 0 | — |
| `loomwright/skills/automate-loop/per-item-loop.md` | prompt | 0 | 1 | no change: mode flag — lines 77 |
| `loomwright/skills/automate-loop/lanes.md` | prompt | 1 | 4 | no change: mode flag — lines 3,58,61,65 |
| `docs/evidence/tr08b-single-lane-sequential.md` | prose | 1 | 0 | — |
| `docs/evidence/as19-split-lanes-and-trail-scripts.md` | prose | 4 | 0 | — |
| `loomwright-lanes/tests/pane.test.tsx` | test | 2 | 1 | no change: mode flag — lines 143 |
| `loomwright-lanes/README.md` | prose | 1 | 0 | — |
| `loomwright-lanes/hooks/register.tsx` | hook | 1 | 3 | no change: mode flag — lines 45,50,58 (subcommands: of) |

## 3. Validation set (AC 6)

Each test ran once from this tree on 2026-10-20. Nine of them ran concurrently, and `test-automate-lanes.sh` ran after them, alone. The machine was shared with the other lanes of the wave (load average 19–57 on 12 CPUs). The `<passed>/<total>` values are each suite's own `RESULT` / `passed:` line.

| Test | `<passed>/<total>` | Note |
|---|---|---|
| `loomwright/scripts/test-classify-bot-review.sh` | 31/31 | |
| `loomwright/scripts/test-automate-lanes.sh` | 1004/1005 | Run as `env -u LOOMWRIGHT_PHASE_DIR -u LOOMWRIGHT_RUN_LOCK_SESSION_ID bash …`, see (a). The one failure is `AH9 lane-wait writes nothing into any lane` (`expected [1] got [0]`), see (b) |
| `loomwright/scripts/test-automate-helpers.sh` | 753/753 | |
| `loomwright/scripts/test-project-memory.sh` | 167/167 | |
| `loomwright/scripts/test-verify-provides.sh` | 180/180 | |
| `scripts/test-lanes-addon.sh` | 12/12 | the pane's `--json` and `keep-awake:` reads (AC 4) |
| `loomwright/scripts/test-build-handoff.sh` | 94/94 | |
| `loomwright/scripts/test-review-heal-next-step.sh` | 160/160 | |
| `loomwright/scripts/test-pr-postmortem-gather.sh` | 27/27 | The concurrent run scored 26/27, see (c). Re-run alone it scored 27/27 |
| `loomwright/scripts/test-loop-inventory.sh` | 43/43 | |

(a) **Environment, not code.** When `test-automate-lanes.sh` inherits `LOOMWRIGHT_PHASE_DIR` and `LOOMWRIGHT_RUN_LOCK_SESSION_ID` from a `/automate` phase session, its relay legs (J/K/X/AD/AM, 42 checks) fail. They fail the same way at the base commit, so this is a pre-existing hermeticity gap in the suite. Run with both unset, as CI runs it, they pass. It is not fixed here because it is outside this change's lanes.

(b) **`AH9` is load-sensitive and not touched by this change.** The leg counts files under the fixture lane root that are newer than the `lane-wait` ledger, runs one `lane-wait` pass, and expects the same count. On this run the count was 1 before and 0 after: a lane file was already newer than the ledger, and the pass rewrote the ledger, which it is allowed to do. `git diff ee3d7ea` shows no change to the AH9 leg, to `lane-wait`, or to the `lane-status --json` read that `lane-wait` uses. The second sample, in the full `ci-local.sh` pool on `a6c163c` (§4), passed: `test-automate-lanes.sh` green in 476 s, AH9 included.

(c) **`3j` hit the classifier's stdin bound under load.** `3j` pipes a ~100 KB comments fixture through `classify-bot-review.sh`, whose stdin read is bounded (`read -t`, 10 s default). With nine suites running concurrently at load ~50, the read timed out, and the fail-safe returned `[]` for the bot comments. Run alone, all 27 checks pass. The bound and the fixture are both unchanged from the base commit.

## 4. Budgets and release

- `bash scripts/check-token-budget.sh` → `breaches: 0`. Every agent, skill dir and command doc is within its declared budget (`execute-manager` 31,410 / 42,568; `supervisor` 19,874 / 30,378; `worker` 9,130 / 9,949; `skills/automate-loop` 72,929 / 77,733 proxy tokens). `prompt-token-budgets.json` and `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" are not edited.
- `changelog.d/as24-terse-script-output.md` is a patch-level fragment (`<!-- bump: patch -->`). This is a lane of a parallel wave, so the release lane folds it, and `bump-version.sh` was not run here.
- `bash scripts/check-version-bump.sh` → `check OK — not bumped (… the merge base's); 1 fragment(s) pending — legal, the next bump folds them (base origin/main, merge base ee3d7ea3bb06)`, exit 0.
- Full `bash scripts/ci-local.sh` runs, both with `LOOMWRIGHT_PHASE_DIR` / `LOOMWRIGHT_RUN_LOCK_SESSION_ID` unset for reason (a) in §3. They verified the code tree before this paragraph was written; this paragraph is the only change after them.
  - On `33a750f`: 5 of 176 self-tests failed. `test-no-pipefail-grep-q.sh` found a real defect, a `printf | grep -q` in `test-project-memory.sh` added by this change. It was fixed in `2781343` and merged at `a6c163c`. The other four were AH9 (b) and three 900 s watchdog timeouts.
  - On `a6c163c`: 3 of 176 failed (wall 1938 s, load average ~25). All three were 900 s watchdog timeouts, with no failed assertion. `test-no-pipefail-grep-q.sh`, `test-project-memory.sh` and `test-automate-lanes.sh` passed. Each timed-out suite was then checked on its own on the same tree:

| Test | Result | Note |
|---|---|---|
| `loomwright/scripts/test-automate-next-step.sh` | `PASS: 153 FAIL: 0`, exit 0 | re-run alone, with the two variables unset. It reads `automate-helpers.sh` and `status-read.sh`, which this change edits |
| `loomwright/scripts/test-automate-trail.sh` | 786 passed, 0 failed, exit 0 | re-run alone, with the two variables unset. It reads `automate-helpers.sh` |
| `loomwright/scripts/test-meta-sync.sh` | 359 passed, 0 failed | printed inside the pool, with all assertions run, before the watchdog killed it in its final `rm -rf` cleanup. `meta-sync.sh` names `automate-helpers.sh` and `automate-lanes.sh` |

  CI runs the pool on its own runners; the PR's `ci` check is the release verdict.
