# Evidence: split automate-lanes.sh and automate-trail.sh into sourced modules (automate-speed/19)

Base commit: `051553e` (the brief's `142540b` measurements were superseded by its Pre-flight decision; every "base" below is `051553e`).
Branch: `feature/as19-split-lanes-and-trail-scripts` (subtask 1 `9560281`, subtask 2 `0f19075`, the integration commit `5d3c348`, then the three consumer setup fixes `d588537`, §8).
All runs: macOS (bash 3.2 system shell), 2026-10-16. "Base" numbers come from a clean `git worktree` detached at `051553e`, run earlier in the same session by the previous integration attempt (logs kept in its scratchpad). "Branch" numbers come from the committed tree at `d588537` (integration plus the §8 fixes), re-run after the Phase 3 adjudication.

## 1. Test and gate totals (AC5 to AC10)

`<passed>/<total>` as each test prints it. Absent on base = the file is new on this branch.

| Test / gate | Base `051553e` | Branch | Note |
|---|---|---|---|
| `test-automate-lanes.sh` (AC5) | 864/864 | 866/866 | +2 = the AG7a/AG7b planted-violation legs (AC8). Without them the branch is 864/864, as subtask 1 measured |
| `test-automate-trail.sh` (AC5) | 782/782 | 782/782 | |
| `test-automate-lanes-modules.sh` (AC6) | absent | 56/56 | |
| `test-automate-trail-modules.sh` (AC6) | absent | 24/24 | 24/24 before and after setup fix 3, §8 |
| `test-no-pipefail-grep-q.sh` (AC7) | 26/26 | 27/27 | +1 = the planted test-part violation leg |
| `test-no-fixed-sleep-race.sh` (AC7) | 26/26 | 27/27 | +1 = the planted test-part sleep leg |
| `test-wave-build.sh` (AC8, AC10) | 65/65 | 67/67 | +2 = W6d2/W6d3 (planted push in a module) |
| `test-automate-loop-split.sh` (amendment iii) | 39/39 | 40/40 | +1 = M11 (raw read planted in a trail test part) |
| `test-guard-lane-wait-armed.sh` (AC10) | 45/45 | 45/45 | was 44/45 before setup fix 1, §8 |
| `test-reconcile-jobs.sh` (consumer re-scan) | 115/115 | 115/115 | was 114/115 before setup fix 2, §8 |
| `test-automate-helpers.sh` (AC10) | 737/737 | 737/737 | |
| `test-automate-helpers-dispatch.sh` (AC10) | 45/45 | 45/45 | |
| `test-automate-golden.sh` (AC10) | 64/64 | 64/64 | |
| `test-migrate-branch-mode.sh` (consumer re-scan) | 133/133 | 133/133 | |
| `test-verify-queue.sh` (consumer re-scan) | 44/44 | 44/44 | |
| `test-session-resume.sh` | 338/338 | 338/338 | |
| `scripts/test-lanes-addon.sh` (AC10) | 12/12 | 12/12 | |
| `scripts/check-test-hermetic.sh` (AC10) | OK, 169/169 | OK, 171/171 | +2 = the two new `*-modules.sh` tests; parts are not standalone tests |
| `scripts/check-vendor-coupling.sh` (AC9) | OK, 0 breaches, 2676 refs | OK, 0 breaches, 2677 refs | +1 = a NEW reference in `test-automate-lanes-modules.sh`, §5 |
| `scripts/check-locale-prefix.sh` | OK | OK, 373/373 files | was FAIL (2 sites in `test-automate-trail-modules.sh`) before setup fix 3, §8 |
| `scripts/check-version-bump.sh` (AC14) | OK, 2 fragments | OK, 3 fragments | +1 = this item's fragment |

AC10 byte-unchanged files: `git diff --stat 051553e -- loomwright/hooks/hooks.json loomwright/capabilities.json loomwright/.claude-plugin/plugin.json .claude-plugin/marketplace.json CHANGELOG.md` prints nothing.

### `bash scripts/ci-local.sh`

| Tree | Result |
|---|---|
| Base `051553e` | PASS after 871s: 23 ci.yml gates + 160 self-tests (16 early, 167 in the pool), 183 PASS, 0 FAIL |
| Branch `d588537` | PASS after 821s: 23 ci.yml gates + 162 self-tests (16 early, 169 in the pool), 185 PASS, 0 FAIL. The +2 entries over base are the two new `*-modules.sh` tests. No red leg |
| Branch `5d3c348` (before the §8 fixes, superseded) | FAIL after 34s in the early phase on `check-locale-prefix.sh`; with that fix alone in a scratch copy, FAIL after 1063s with 183 PASS, 2 FAIL of 185 (`test-guard-lane-wait-armed.sh`, `test-reconcile-jobs.sh`, both green on base) |

The AC10 consumer set on `d588537` (16 entries: the tests in the table above marked AC10, plus `test-automate-loop-split.sh`, `test-reconcile-jobs.sh`, both `*-modules.sh`, `test-automate-lanes.sh`, `test-automate-trail.sh`, and the vendor-coupling, hermetic, locale-prefix and version-bump gates): 16/16 exit 0. `loomwright/hooks/hooks.json` and `loomwright/capabilities.json`: `git diff --quiet origin/main` exits 0.

## 2. Module list per script (AC4, AC13)

Measured with `wc -l` and `sed -nE 's/^([A-Za-z_][A-Za-z0-9_]*)\(\) \{.*/\1/p'` on the branch. The largest module is 740 lines, under the 800 limit.

| Module | Lines | Functions |
|---|---|---|
| `automate-lanes.sh` (entry) | 371 | `die`, `_lanes_source`, `_lanes_bundle`, `_lanes_usage`, `lanes_main` (+ header, config block, direct-run guard) |
| `automate-lanes.d/common.sh` | 194 | now_utc _trim_ws _clean _lanes_need _lt_me _lt_holder _lt_holder_dead _lt_reclaim _lt_lock _lt_unlock _lt_set _lt_get _lane_ctx lanes_proc_alive _lanes_clip _lanes_pending_question _lanes_meta_branch _lanes_salvage _lanes_merge_hooks |
| `automate-lanes.d/create.sh` | 123 | lanes_create |
| `automate-lanes.d/launch.sh` | 237 | _lanes_regime_ok _lanes_admission _lanes_launch_lock _lanes_launch_unlock _lanes_optout_set _lanes_optout_file _lanes_optout_record _lanes_gate _lanes_spawn lanes_run_wrapper lanes_launch _lanes_launch_go _lanes_session_id _lanes_last_result |
| `automate-lanes.d/relay.sh` | 248 | _lanes_hook_root lanes_relay_hook _lanes_policy_apply _lanes_pending_file _lanes_validate_answers _lanes_answer_parked _lanes_answer_write_resume lanes_answer _lanes_deliver_pending |
| `automate-lanes.d/remove.sh` | 415 | _lanes_stop_pid _lanes_live_watchers _lanes_status_named _lanes_remove_refusals lanes_remove _lanes_meta_extras _lanes_noclaim_files _lanes_meta_trail _lanes_abandon_meta _lanes_current_item _lanes_no_host_identity lanes_convert_ready |
| `automate-lanes.d/notify-guards.sh` | 191 | _lanes_click_action _lanes_os_notifier lanes_park_notify lanes_info lanes_init_check lanes_pick_guard lanes_branch_check |
| `automate-lanes.d/status-read.sh` | 740 | _lanes_dash _lanes_epoch _lanes_boot_epoch _lanes_runfile_fields _lanes_runfile_branch _lanes_parked _lanes_last_message _lanes_last_actions _lanes_questions_json _lanes_policy_digest _lanes_inbox _lanes_keep_awake_holders _lanes_keep_awake_state _lanes_keep_awake_lasting _lanes_coordinator_pid _lanes_keep_awake_hint _lanes_keep_awake_start _lanes_machine_json _lanes_ci_json _lanes_table_for _lanes_state_of _lanes_parent_of _lanes_resolve _lanes_timeline _lanes_salvaged_sup _lanes_salvage_time _lanes_last_dated _lanes_lane_json _lanes_status_doc _lanes_render _lanes_resources _lanes_tokens _lanes_single_parent _lanes_lane_total _lanes_single_spent _lanes_tokens_line _lanes_tokens_record |
| `automate-lanes.d/park-leaks.sh` | 279 | lanes_park _lanes_pr_hash lanes_drain_check _lanes_leak_lanes_dir _lanes_leak_watchers _lanes_path_tied _lanes_leak_claude _lanes_leak_sections lanes_leaks |
| `automate-lanes.d/status.sh` | 291 | lanes_status _lanes_watch _lanes_wait_print _lanes_wait_unmark _lanes_quick_state lanes_wait lanes_feed |
| `automate-lanes.d/readiness.sh` | 468 | _lanes_rd_section _lanes_validation_rows lanes_readiness _lanes_vg_itemf _lanes_vg_after_pick _lanes_vg_last_pick _lanes_vg_has lanes_validation_gate |
| `automate-lanes.d/wave.sh` | 403 | _lanes_base_of _lanes_rf_done _lanes_sync_primary _lanes_append_once _lanes_fc_finalize lanes_fleet_closeout _lanes_wave_resolve lanes_wave_plan |
| `automate-trail.sh` (entry) | 253 | `_trail_source`, `_trail_bundle`, `main` (+ header with the Modules map, globals, `main "$@"; exit 0`) |
| `automate-trail.d/sidecar.sh` | 192 | sidecar_check |
| `automate-trail.d/trail-pr.sh` | 657 | trail_cleanup _in_list _trail_is_run_draft _trail_candidates _done_prs _outcome_prs _gate_keep _evidence_gate _trail_owned _stage_tip _branch_mode _trail_meta_fail _trail_meta_push trail_pr |
| `automate-trail.d/stage-sync.sh` | 228 | trail_unstage trail_gate _restage_landed _restore_prior _sync_primary |
| `automate-trail.d/closeout.sh` | 401 | _run_lock_in co_release _co_current _co_stamped closeout |
| `automate-trail.d/finalize.sh` | 247 | fe_release _fe_ineligible _in_lane_clone _lane_run_id finalize_empty closeout_others |
| `automate-trail.d/sweep.sh` | 332 | _sw_line _sw_rule _sw_live_read _sw_live _sw_plugin_made sweep_run |

Test parts (line counts): lanes runner 216; `test-automate-lanes.d/` 01-create-to-wait 620, 02-readiness-to-convert 560, 03-fixes-to-finalize 759, 04-fleet-closeout-to-optout 641, 05-timeline-and-gate 403. Trail runner 323; `test-automate-trail.d/` 01-sidecar-trail-pr 560, 02-closeout 362, 03-stamps-gate 484, 04-watcher-branch-mode 676, 05-finalize-closeout-others 706, 06-sweep 422.

## 3. Non-move hunks (AC3 and AC5)

As reported by subtask workers 1 and 2. AC3's byte-equality (the bundle, with loader and markers stripped, equals `git show 051553e:<path>`) is asserted by the AC3 legs of the two `*-modules.sh` tests (56/56 and 24/24 above).

**`automate-lanes.sh` (AC3)**
- The `# Modules (sourced in this order from automate-lanes.d/):` map, after base line 208 (AC13). It is stripped by AC3's comparison.
- The loader block (`_lanes_source`, `_lanes_bundle`) after `die()` (base line 240). It is entry-point only and belongs to no module.
- 11 marker triplets (`# >>> automate-lanes.d/<name>.sh`, `_lanes_source <name> || { return 1 2>/dev/null || exit 1; }`, `# <<< …`) replacing base lines 241 to 3829. Lanes `--help` reads only the header, which stays in the entry point, so the help arm needs no change.

**`automate-trail.sh` (AC3)**
- The `--help` arm now reads `_trail_bundle | grep -E '^#   [a-z]' | sed 's/^#   /  /'` instead of grepping `"$0"`. Base help matched body comment lines across the whole file, so it must read the bundle.
- A Modules map before `# Subcommands:`. Its lines start `# - `, so the help grep `^#   [a-z]` does not match them.
- The loader (`_trail_source`, `_trail_bundle`) plus 6 marker blocks.
- Placement: `_run_lock_in` sits in `closeout.sh` because it was under the closeout banner in base.

**`test-automate-lanes.sh` (AC5)**
- (a) An 8-line `SB` block (the `_lanes_bundle` output written once to a temp file). Every text read uses `"$SB"` instead of `"$S"`: mutant builders, their `cmp -s` gates, and static greps. Base lines re-pointed: 349, 429, 437, 460, 561, 769–771, 774 (twice), 943–944, 1010–1011, 1118–1119, 1161–1162, 1235–1236, 1285–1286, 1938, 1982, 1992, 2354, 2356, 2673–2674, 2683–2685, 2802–2803, 3075–3076, 3150, 3152, 3155–3156. Every RUN still goes through `S="$HERE/automate-lanes.sh"`.
- (b) None.
- (c) A `tal_part` guard plus 5 source-by-name lines.
- Subtask 3 (AC8): the AG7 check in `04-fleet-closeout-to-optout.sh` reads `automate-trail.d/*.sh` as well, through `ag7_callers`. The expected value `0:1` is unchanged. AG7a/AG7b plant a `fleet-closeout` call in a scratch copy of `automate-trail.d/sweep.sh` and expect AG7's input to count it (`1`).

**`test-automate-trail.sh` (AC5)**
- (a) A 9-line `TB` block after `trap cleanup_all EXIT`, used for text reads on 68 base lines: 416, 417, 437, 438, 707, 712, 713, 729, 767, 772, 780, 781, 809, 825, 950, 952, 953, 973, 974, 977, 1021, 1022, 1040, 1041, 1066, 1067, 1188, 1280, 1281, 1336, 1337, 1387, 1388, 1509, 1573, 1574, 1607, 1608, 1641, 1680, 1681, 1694, 1697, 2257, 2258, 2354, 2355, 2367, 2368, 2405, 2406, 2443, 2444, 2514, 2588, 2589, 2592, 2593, 2700, 2701, 2831, 2883, 2885, 2956, 3438, 3441, 3448, 3449.
- (b) `cp -R <src>/automate-trail.d` added on base line 762 (the SPY copy) and beside every `automate-helpers.d` copy, on base lines 866, 949, 972, 1020, 1039, 1065, 1181, 1187, 1279, 1335, 1386, 1508, 1572, 1606, 2256, 2343 (twice), 2404, 2442, 2460, 2482, 2632, 2699, 2807, 2830, 3447.
- (c) One guarded `.` line per part, replacing base lines 294 to 3503.
- Edge: the V leg's `$B32 -n $0` now parses only the runner. The parts are covered by `bash -n` in the modules test.

## 4. Gate edits by subtask 3 (AC7, AC8, amendments i to iii) and their pin mutations

| Gate | Edit (expected values unchanged) | Planted leg | Pin mutation (scratch copy) | Result |
|---|---|---|---|---|
| `test-no-pipefail-grep-q.sh` | rule-1 scan set gains `loomwright/scripts/test-*.d/*.sh` through `suite_files`. A part is scanned when it or its runner `test-<x>.sh` mentions `pipefail`, because a part runs under its runner's `set -o pipefail` and never sets it itself | a mirror runner with a part holding `printf … \| grep -q`: flagged | delete the `test-*.d/*.sh` member | 26/27, red: "a planted violation in a test part was NOT flagged" |
| `test-no-fixed-sleep-race.sh` | `files=(…)` gains `loomwright/scripts/test-*.d/*.sh`. Amendment (i): baseline row `3 test-automate-lanes.sh` re-pointed to `2 …/01-create-to-wait.sh` + `1 …/02-readiness-to-convert.sh` (total 3, unchanged) | a mirror part with `run_thing &` / `sleep 0.3`: counted | delete the `test-*.d/*.sh` member | 25/27, red: the planted leg and the ratchet (the two re-pointed rows go stale) |
| `test-wave-build.sh` W6d | reads `_lanes_bundle` output (one file, so the `^[0-9]+:` comment filter still matches). Exclusion filter and expected `""` unchanged | W6d2/W6d3: a push appended to a scratch `automate-lanes.d/wave.sh` is reported | append `  git push origin HEAD` to `automate-lanes.d/wave.sh` | red: `W6d … expected [] got [3916:  git push origin HEAD]` |
| `test-automate-lanes.d/04-…` AG7 | `ag7_callers` also reads `automate-trail.d/*.sh` | AG7a/AG7b | append a `fleet-closeout` call to `automate-trail.d/sweep.sh` | red: `AG7 … expected [0:1] got [1:1]` |
| `test-automate-loop-split.sh` §H (amendment ii) | `wiring` also runs its line checks over each reader's `test-<x>.d/*.sh` parts. The reader itself must still call `assemble.sh` (kept in the trail runner) | M11: a raw SKILL-index read planted in a scratch trail part is rejected | `wiring_reader` stops passing the parts | 39/40, red: "a raw SKILL-index read in a test part … was ACCEPTED (H)" |

Limit on the W6d and AG7 mutation runs: the brief's one-line mutations append at module top level. A sourced module therefore executes that line at load time, so those two scratch runs also show unrelated failures (wave-build 22/72, lanes 775/866). The pinned check itself goes red exactly as the Pin mutations table says.

## 5. Vendor-coupling manifest (AC9)

- Measured references move one for one. `automate-lanes.sh` 34 = entry 10 + common 1 + create 2 + launch 5 + notify-guards 2 + park-leaks 1 + relay 7 + remove 4 + status 2. `test-automate-lanes.sh` 44 measured = runner 5 + 01 23 + 02 3 + 03 5 + 04 8. `automate-trail.sh` 1 = `automate-trail.d/sweep.sh` 1. `test-automate-trail.sh` 6 = runner 1 + 04-watcher-branch-mode 4 + 06-sweep 1. Each new path has the reason `moved by automate-speed/19 split — no reference added`. `schema_version` and every key other than `allowances` / `allowance_reasons` are unchanged.
- Deviation from AC9's "(46)" (accepted owner decision, Phase 3 adjudication): base `test-automate-lanes.sh` was 2 below its allowance of 46 (measured 44, "debt paid down"). The allowances move at the measured 44, so the 2 units of headroom are dropped rather than carried into a part.
- Accepted owner decision (Phase 3 adjudication): the reference total goes from 2676 to 2677, and the allowance sum from 2699 to 2698. The +1 is not a moved reference: `test-automate-lanes-modules.sh` (new in subtask 1) feeds the Stop hook a payload with the continuation flag (`hook_protocol=1`). Its allowance carries its own "a NEW reference, not a moved one" reason. Net allowance change: −2 headroom + 1 new = −1.

## 6. Running-system check (AC11)

Input: the real parent run file `.supervisor/automate/automate-2026-10-14-041009.md` in the primary checkout (2 lanes, 1 merged wave). All runs use that checkout as cwd, back to back. Script: `ac11b.sh` in the session scratchpad.

```
cd <primary checkout>
bash <base-worktree>/loomwright/scripts/automate-lanes.sh lane-status .supervisor/automate/automate-2026-10-14-041009.md          # base1, base2
bash <base-worktree>/loomwright/scripts/automate-lanes.sh lane-status .supervisor/automate/automate-2026-10-14-041009.md --json   # base1, base2
bash <branch>/loomwright/scripts/automate-lanes.sh lane-status .supervisor/automate/automate-2026-10-14-041009.md                  # br
bash <branch>/loomwright/scripts/automate-lanes.sh lane-status .supervisor/automate/automate-2026-10-14-041009.md --json           # br
```

Every run exits 0. Results:
- **Text:** base1 vs base2 differ only on line 1's clock (`2026-10-16T05:53:29Z` vs `…:31Z`) and line 16's `load1=` (14.74 vs 14.60). base2 vs br differ only on line 1's clock. With `<now>` and `load1=<load>` substituted, base and branch are byte-identical (2816 bytes each).
- **JSON:** volatile fields are `generated_at` (clock), `machine.load1` (load average), and `machine.keep_awake_holders`. The last is a live read of the OS power assertions, and it changes between two consecutive BASE runs too: base1/base2 had 7 holders, base3/base4/base5 had 5, br had 6, br3/br4/br5 had 5, as other apps released their assertions. With those three fields removed, all 9 JSON outputs (5 base, 4 branch) are byte-identical. With only `generated_at` and `load1` removed, base4 = br4 and base5 = br5 byte for byte.

Branch text output (home directory shown as `~`):

```
lane-status: automate-2026-10-14-041009 — 2 lane(s) — 2026-10-16T05:53:33Z — started 2026-10-14T04:10:09Z
wave 1 PR: https://github.com/vikashruhilgit/loomwright/pull/541  branch=wave/automate-2026-10-14-041009-w1  built 2026-10-14T08:04:50Z  merged  lanes L1,L2
policy: none answered
L1  removed — done  item=.supervisor/requirements/automate-speed/01-question-gates-dont-stall.md  pr=https://github.com/vikashruhilgit/loomwright/pull/537  ended=2026-10-14T09:04:07Z  path=~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-14-041009/L1
    steps: Pick ✓ · Plan ✓ · Build ✓ · Heal ✓ · Drain ✓ · Decide ✓ · Merge ✓  (started 2026-10-14T04:13:17Z)
    progress: 2026-10-14T09:04:07Z trail-pr: meta-pushed loomwright-meta
    actions: Bash S=~/.claude/plugins/cache/atelier/loomwright/17.0.2/scripts; H=; Bash S=~/.claude/plugins/cache/atelier/loomwright/17.0.2/scripts; H=; Bash grep -n -A6 -i "scope-fence" .supervisor/automate/automate-2026-10-14-041009-L1.
    readiness: ready (1/5: validation NOT-RUN, scope-fence FAIL, gates NOT-RUN, headline-repro NOT-RUN)
    last: Lane L1 is parked at `ready_for_release` with PR #537 open (https://github.com/vikashruhilgit/loomwright/pull/537). Don't merge it on its own: the wave is still open, and the coordinator's `wave-build` merges it with the other lane into one wave PR for you to merge. **What the PR does (automate-spee
L2  removed — done  item=.supervisor/requirements/automate-speed/02-phase45-rounds-on-new-defects.md  pr=https://github.com/vikashruhilgit/loomwright/pull/538  ended=2026-10-14T09:04:33Z  path=~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-14-041009/L2
    steps: Pick ✓ · Plan ✓ · Build ✓ · Heal ✓ · Drain ✓ · Decide ✓ · Merge ✓  (started 2026-10-14T04:13:13Z)
    progress: 2026-10-14T09:04:33Z trail-pr: meta-pushed loomwright-meta
    actions: AskUserQuestion; Bash cd ~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-; Bash cd ~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-
    readiness: ready (1/5: validation FAIL, scope-fence FAIL, gates NOT-RUN, headline-repro NOT-RUN)
    last: Lane L2 is done and parked at `ready_for_release`. **PR #538** (automate-speed/02) is ready for review but **should not be merged yet**: the wave is still open, and the coordinator will put it on a wave PR together with L1. **What the PR changes** - **Pin mutations are checked by a script.** New `ru
machine: state=busy load1=14.60 cpus=12 mem_pressure=busy
keep-awake: held (Claude app — only while a Code session works)
keep-awake suggestion (run it yourself, or lane-status --keep-awake): caffeinate -i -w 15476 — a closed lid still sleeps
rc=0
```

## 7. Prose citations of moved code (AC12, AC13)

Command: `git grep -nE 'automate-(lanes|trail)\.sh' -- '*.md' ':!CHANGELOG.md' ':!docs/evidence/*'` (script: a line counts when it also names a function now defined in a `.d` module, or says header / comment block). citing-lines=332 with-moved-function=116 header-or-comment-cites=44.

Resolution rule: `named` = the function's name appears in the entry point's `# Modules` map; `range` = the map gives its module as a `first … last` range in base order (the function sits between them in that module). `[header]` = the line points at a header or comment block.

| Citation | Moved function → module (how the map resolves it) |
|---|---|
| `loomwright/docs/ARCHITECTURE_CONTRACTS.md:519` |  [header] |
| `loomwright/docs/ARCHITECTURE_CONTRACTS.md:955` | closeout → automate-trail.d/closeout.sh(named) [header] |
| `loomwright/docs/HOOKS.md:29` | lanes_proc_alive → automate-lanes.d/common.sh(named) _lanes_quick_state → automate-lanes.d/status.sh(named) |
| `loomwright/docs/TELEMETRY.md:2336` | lanes_park_notify → automate-lanes.d/notify-guards.sh(named) |
| `loomwright/docs/TELEMETRY.md:2346` | lanes_park_notify → automate-lanes.d/notify-guards.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:51` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:52` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:53` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:54` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:55` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:65` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:76` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:86` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:104` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:157` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:174` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:216` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:217` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:218` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:248` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:253` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:254` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:255` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:303` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:304` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:363` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:373` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:375` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:379` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:380` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:381` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:382` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:383` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:384` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:386` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:387` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:388` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:389` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:391` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:393` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:397` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:416` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:417` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:468` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:481` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:499` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:503` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:509` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:511` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:517` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:518` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:519` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:520` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:521` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:522` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:523` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:569` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/automate-loop.md:570` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/loop-inventory/supervisor.md:572` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/result-schemas/ground-truth-json.md:238` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/docs/result-schemas/session-end-jsonl.md:5` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/skills/automate-loop/SKILL.md:77` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/skills/automate-loop/SKILL.md:78` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/skills/automate-loop/SKILL.md:79` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/skills/automate-loop/SKILL.md:80` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/skills/automate-loop/SKILL.md:81` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/skills/automate-loop/SKILL.md:82` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/skills/automate-loop/SKILL.md:84` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/skills/automate-loop/SKILL.md:91` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/skills/automate-loop/SKILL.md:101` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/skills/automate-loop/lanes.md:3` | closeout → automate-trail.d/closeout.sh(named) [header] |
| `loomwright/skills/automate-loop/lanes.md:58` | lanes_drain_check → automate-lanes.d/park-leaks.sh(named) [header] |
| `loomwright/skills/automate-loop/lanes.md:61` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/skills/automate-loop/lanes.md:65` | closeout → automate-trail.d/closeout.sh(named) [header] |
| `loomwright/skills/automate-loop/lanes.md:78` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/skills/automate-loop/per-item-loop.md:25` |  [header] |
| `loomwright/skills/automate-loop/per-item-loop.md:107` | _run_lock_in → automate-trail.d/closeout.sh(named) closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/skills/automate-loop/per-item-loop.md:123` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/skills/automate-loop/per-item-loop.md:132` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/skills/automate-loop/per-item-loop.md:138` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/skills/automate-loop/per-item-loop.md:141` | closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/skills/automate-loop/per-item-loop.md:146` | _lanes_no_host_identity → automate-lanes.d/remove.sh(range) closeout → automate-trail.d/closeout.sh(named) |
| `loomwright/skills/self-heal-advisory/SKILL.md:1325` | closeout → automate-trail.d/closeout.sh(named) |

Golden fixture data (55 lines under `loomwright/scripts/fixtures/automate-golden/*/tree/`): frozen run-file and result-block text that the golden suite replays byte for byte. They quote what a past run wrote, they are not pointers a reader follows, and they must not change; not re-targeted.

## 8. Consumer breaks outside the original lanes: resolved (Phase 3 adjudication, option D)

The integration commit `5d3c348` broke three consumers that sat outside every lane of this item, so the worker stopped and reported them. The owner chose option D: widen subtask 3's lane to the three files and apply setup-only fixes. The fixes are commit `d588537`. No assertion, expected value or mutation pattern was edited.

1. **`loomwright/scripts/test-guard-lane-wait-armed.sh` leg E2.** Why it broke: the mutant dir copied only `automate-lanes.sh` (`cp "$S" "$MUT/"`). The mutant hook sources that copy, the copy cannot find `automate-lanes.d/`, the source returns 1 (AC1's sourced fallback), and the hook allows, so "session-id check removed ⇒ block" read `allow`. Hunk: that line gains `cp -R "$HERE/automate-lanes.d" "$MUT/"`, so the mutant entry has its modules beside it. Before 44/45, after 45/45 (base 45/45).
2. **`loomwright/scripts/test-reconcile-jobs.sh` leg 11a.** Why it broke: `TRAIL="$SCRIPT_DIR/automate-trail.sh"` pulled the closeout stamp `printf` format out of the entry point, and that text now lives in `automate-trail.d/closeout.sh`. Hunk: `TRAIL="$SCRIPT_DIR/automate-trail.d/closeout.sh"`, plus one comment line naming the module. Before 114/115, after 115/115 (base 115/115).
3. **`loomwright/scripts/test-automate-trail-modules.sh` (subtask 2's file) and the `check-locale-prefix.sh` early gate.** Why it broke: two `sort` sites (the `ONDISK` pipeline and the `$MODS` comparison) put `LC_ALL=C sort` at command position. The gate rejects that because Homebrew bash 5.3 segfaults restoring the locale in a forked subshell. Hunk: `env LC_ALL=C sort` at both sites. The test is 24/24 before and after; the gate goes from FAIL to OK (373/373 files).

Re-scan for other consumers: `git grep -nE 'automate-(lanes|trail)\.sh' -- 'loomwright/scripts/*.sh' 'scripts/*.sh' 'loomwright/scripts/adapters/*/*.sh'`. Every test file it names was run (§1). No break beyond the three above. The full branch `ci-local.sh` is green (§1).
