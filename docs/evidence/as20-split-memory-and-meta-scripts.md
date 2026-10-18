# Evidence: split setup-memory.sh and meta-sync.sh into sourced modules (automate-speed/20)

Base commit: `a8819a3`. Branch: `feature/as20-split-memory-and-meta-scripts` (subtask 1 `5f6ed39`, subtask 2 `ee7df3a`, merged as `2345a97` / `346efdd`, then the subtask 3 integration commit).
All runs: macOS, system bash 3.2.57, 2026-10-17/18, one session. "Base" is a clean `git worktree` detached at `a8819a3`. "Branch" is the integrated tree (subtasks 1 + 2 + the subtask 3 hunks below). No base number was carried over from another session.

## 1. Test and gate totals (AC5 to AC10)

`<passed>/<total>` as each test prints it. "absent" = the file is new on this branch.

| Test / gate | Base `a8819a3` | Branch | Note |
|---|---|---|---|
| `test-setup-memory.sh` (AC5) | 574/574 | 574/574 | integrated tree |
| `test-meta-sync.sh` (AC5) | 358/358 | 358/358 | integrated tree; its MUT_XVI leg seds `setup-memory.sh`, so only this run counts |
| `test-setup-memory-modules.sh` (AC6) | absent | 37/37 | 0 skipped |
| `test-meta-sync-modules.sh` (AC6) | absent | 52/52 | 0 skipped |
| `test-session-resume.sh` (AC7) | 338/338 | 338/338 | |
| `test-migrate-branch-mode.sh` (AC7, AC10) | 133/133 | 133/133 | 126/132 before its setup hunks (§4) |
| `test-meta-sync-rehearsal.sh` (AC7, AC10) | 42/42 | 42/42 | |
| `test-automate-helpers.sh` (AC7) | 740/740 | 740/740 | |
| `test-automate-lanes.sh` + parts (AC7) | 925/925 | 925/925 | |
| `test-automate-trail.sh` + parts (AC7) | 786/786 | 786/786 | 785/786 before the `$SPYD` hunks (§4) |
| `test-committed-twin-scrub.sh` (AC7) | 41/41 | 41/41 | |
| `test-guard-lane-wait-armed.sh` (AC7) | 45/45 | 45/45 | |
| `test-script-event-telemetry.sh` (AC7) | 30/30 | 30/30 | |
| `test-seed-rules.sh` (AC7) | 84/84 | 84/84 | |
| `test-validate-entry.sh` (AC7, AC15) | 301/301 | 301/301 | |
| `test-wave-build.sh` (AC7) | 85/85 | 85/85 | |
| `test-write-agent-memory.sh` (AC7) | 171/171 | 171/171 | |
| `scripts/test-check-locale-prefix.sh` (AC7) | 35/35 | 35/35 | leg 6 `ok: 6. reverting gitignore_gate's env prefix turns the gate red` on both |
| `test-citation-drift.sh` (AC7, AC15) | 26/26 | 26/26 | |
| `bash scripts/check-locale-prefix.sh` (AC7) | OK 376/376 | OK 400/400 | +24 = the new modules, test parts and `*-modules.sh` tests, all scanned |
| `test-no-fixed-sleep-race.sh` (AC9) | 27/27 | 27/27 | no per-file row names either script |
| `test-no-pipefail-grep-q.sh` (AC9) | 27/27 | 27/27 | no per-file row names either script |
| `bash scripts/check-test-hermetic.sh` (AC9) | OK 173/173 | OK 175/175 | +2 = the two `*-modules.sh` tests |
| `fixtures/self-test-weights.tsv` (AC9) | rows unchanged | rows unchanged | the runner basenames stay; the file is read only by `run-self-tests.sh` for shard weights (a test absent from it gets weight 20, never dropped), so the two new tests need no row |
| `bash scripts/check-vendor-coupling.sh` (AC8) | OK, TOTAL (flat) 2663 | OK, TOTAL (flat) 2663 | run after `git add`; allowances sum 2693 on both |
| `bash scripts/check-version-bump.sh` (AC14) | — | OK | "not bumped (version 17.7.0, the merge base's); 1 fragment(s) pending" |
| `bash scripts/ci-local.sh` (AC12) | see §7 | see §7 | |

## 2. Module map (AC4, AC13)

Every module ≤ 800 lines and passes `/bin/bash -n` (bash 3.2.57). Each entry's header carries the same map as a `# Modules (sourced in this order from <script>.d/):` block.

| File | Lines | Functions |
|---|---|---|
| `setup-memory.sh` (entry) | 457 | valid_branch_name reject_option_value usage _sm_source _sm_bundle apply_readiness_event |
| `setup-memory.d/probes.sh` | 220 | agent_memory_store_dir ignore_status tracked_count gitignore_gate managed_block_present strip_managed_block comment_bare_excludes (+ the INTENDED_PATHS / LEDGER_INTENDED_PATH / UNINTENDED_PATHS globals) |
| `setup-memory.d/detect.sh` | 255 | uncomment_bare_excludes managed_block managed_block_branch_mode read_mode normalize_mode resolve_effective_branch |
| `setup-memory.d/gitignore.sh` | 57 | proposed_applied_content proposed_removed_content unique_backup_path write_gitignore |
| `setup-memory.d/allowlist.sh` | 511 | parse_remote_url resolve_origin remote_slug allowlist_gh_limit allowlist_max_entries gh_id_bounded meta_allowlist_grants load_allowlist resolve_allowlist seed_allowlist filter_ledger_by_allowlist |
| `setup-memory.d/ledger-gate.sh` | 196 | _evaluate_ledger_gate ledger_gate_blocks_foreign_records ledger_gate_permits_negation ledger_gate_warrants_withdrawal negation_line_in_block existing_ledger_negation_present ledger_negation_in_block |
| `setup-memory.d/report.sh` | 358 | print_consent_disclosure print_consent_disclosure_branch_mode render_report print_path_rules |
| `setup-memory.d/commands.sh` | 393 | warn_if_not_configured do_check do_apply do_remove do_allowlist do_filter_ledger do_mode consent_key do_consent (+ the top-level resolve_effective_branch call and CONSENT_FILE_REL at their base positions) |
| `meta-sync.sh` (entry) | 660 | say warn die usage need_val read_branch_mode _ms_source _ms_bundle |
| `meta-sync.d/lock.sh` | 100 | g cleanup lock_holder_alive lock_is_stale reclaim_lock acquire_lock (+ the top-level `WORK=$(mktemp -d …)` and its EXIT / HUP / INT / TERM traps) |
| `meta-sync.d/managed.sh` | 228 | is_managed is_twin_path is_learning_path symlink_hazard path_has_no_symlink parent_inside remote_probe no_remote_branch_msg fetch_remote no_newline_in list_tree list_local list_history |
| `meta-sync.d/plan.sh` | 255 | load_base compute_plan classify_plan hold_rows count_outcome report_conflicts report_not_a_file union_into ordered_merge refuse_bad_base refuse_foreign_base write_base_file |
| `meta-sync.d/scrub.sh` | 151 | load_allowlist scrub_report email_matches first_match_line scan_file scrub_candidates (+ EMAIL_FORGE_EXEMPT) |
| `meta-sync.d/learning-twin.sh` | 158 | read_consent consent_skip tracked_learning_hold twin_sha twin_field twin_trusted twin_post_bytes twin_pair_check twin_gate |
| `meta-sync.d/commands.sh` | 318 | build_pull_base cmd_init fetch_or_exit cmd_pull build_agreed_base cmd_push status_paths split_learning_rows status_done learning_state cmd_status cmd_scrub cmd_list_managed |

`apply_readiness_event` stays in the `setup-memory.sh` entry, between the `report.sh` and `commands.sh` source lines, at its single-file position: it finds `emit-script-event.sh` through `${BASH_SOURCE[0]}`, so inside `setup-memory.d/` it would silently stop emitting (Phase 2 amendment). `test-script-event-telemetry.sh` (S6 asserts the event) is 30/30 on base and branch.

In `meta-sync.sh`, top-level statements that sat between functions moved with their neighbours: `WORK=$(mktemp -d …)` and its traps are now in `lock.sh`, so they run when `lock.sh` is sourced (after the parser, root/branch resolution and `read_branch_mode`, before `managed.sh` and later modules load). This is their base order. A missing module refuses before any lock, fetch or write (`test-meta-sync-modules.sh` leg 4).

Test parts: `test-setup-memory.d/` 01-gitignore-paths (310), 02-meta-allowlist (531), 03-apply-safety-ledger-gate (621), 04-verdicts-trail (399), 05-branch-mode-consent (549), runner 336 lines. `test-meta-sync.d/` 01-sync-core (615), 02-guards-mode-base (654), 03-mutants-scrub-allowlist (666), 04-learning-stores (503), runner 332 lines.

## 3. Verbatim move (AC3) and the non-move hunks in the two entries

`test-setup-memory-modules.sh` leg 5: `ok: bundle minus the Modules map, loader block and markers == a8819a38100d77fbeddc2ff1a56963e91f172a5d:loomwright/scripts/setup-memory.sh byte-for-byte`, and its mutant (one moved line changed in `commands.sh`) makes the comparison fail. `test-meta-sync-modules.sh` leg 5 does the same for `meta-sync.sh`.

The only entry hunks that are not moves (`diff <(git show a8819a3:…) <entry>`):

| Entry | Hunk | Reason |
|---|---|---|
| `setup-memory.sh` | the `# Modules (sourced in this order from setup-memory.d/):` comment block after the header | AC13 module map. It is its own comment block, so `usage` (first comment block only) and `--help` are unchanged |
| `setup-memory.sh` | the `# >>> module loader` block: `_sm_source`, `_sm_bundle` | loader + bundle (AC1, AC3), shaped like `automate-trail.sh`'s `_trail_source` / `_trail_bundle` |
| `setup-memory.sh` | seven `# >>> setup-memory.d/<name>.sh` / `_sm_source <name>` / `# <<< …` triples, each at its module's base position | by-name sourcing, never a glob |
| `meta-sync.sh` | the `# Modules (sourced in this order from meta-sync.d/):` block below the header's first blank line | AC13 module map |
| `meta-sync.sh` | the `# >>> module loader` block: `_ms_source`, `_ms_bundle` | loader + bundle (AC2, AC3) |
| `meta-sync.sh` | six `# >>> meta-sync.d/<name>.sh` / `_ms_source <name>` / `# <<< …` triples | by-name sourcing |

## 4. Non-move hunks in tests (AC5, AC7)

### 4.1 The two split test files (AC5, subtasks 1 and 2)

Measured by inlining each runner's parts (`tsm_part` / `tms_part` lines replaced by the part text) and diffing against the base blob.

| File | Hunk | Reason |
|---|---|---|
| `test-setup-memory.sh` | `MEMB` block: the `_sm_bundle` output written once to `$FIXTURE_ROOT/bundle/setup-memory.sh`, fail-closed if it cannot be built | AC5 (a): the single-file text that every text read uses |
| `test-setup-memory.sh` | `TSM_D`, `tsm_part` and five `tsm_part N; . "$TSM_D/N.sh"` lines | AC5 (c): parts loader, by name |
| `test-setup-memory.sh` | header comment: the mkdir / `ln -s` / `chmod 000` audit recipe greps `"$0"` AND `test-setup-memory.d/*.sh`; the "allowlist config read/write" and "EVERY LEDGER ASSERTION" notes name the parts instead of "below" / "this file" | Phase 4.5 iteration 1 review finding: header audit recipe re-pointed to the test parts; comment-only |
| `test-setup-memory.d/*` | 34 lines whose only change is `"$MEM"` → `"$MEMB"` (sed/awk/grep sources and their `cmp -s` gates, incl. the MA_SUT helpers, the `do_consent` awk, bm-f/bm-l, the fn/vb/am/cs mutants) | AC5 (a). Checked mechanically: with `"$MEMB"` mapped back to `"$MEM"` the 34 changed lines equal the base lines exactly |
| `test-meta-sync.sh` | `SUTB` block (`_ms_bundle` output written once, fail-closed), `TMS_D`, `tms_part` + four part lines | AC5 (a), (c) |
| `test-meta-sync.d/01-sync-core.sh` | leg 19's forbidden-forms grep reads `"$SUTB"` | AC5 (a) |
| `test-meta-sync.d/02-guards-mode-base.sh` | `PX_N` (`MAX_ATTEMPTS` grep) reads `"$SUTB"` | AC5 (a) |
| `test-meta-sync.d/03-mutants-scrub-allowlist.sh` | `build_mutant`: `sed -e "$2" "$SUTB"`, `cmp -s "$SUTB" …`, plus a guarded `[ -d "$HERE/setup-memory.d" ] && cp -R "$HERE/setup-memory.d" "$1/"` | AC5 (a), (b): the bundle mutant calls the copied `setup-memory.sh` entry, which needs its `.d` |
| `test-meta-sync.d/03-mutants-scrub-allowlist.sh` | `HP_RE` (`home_path` rule sed) reads `"$SUTB"` | AC5 (a) |
| `test-meta-sync.d/03-mutants-scrub-allowlist.sh` | MUT_XVI (subtask 3): the `setup-memory.sh` mutant is now written from `_sm_bundle` output (`SMB_XVI`), its `cmp -s` gate reads `SMB_XVI`, and `cp -R "$HERE/meta-sync.d" "$MUT_XVI/"` beside the copied real `meta-sync.sh` | the mutant's `sed` target (`granted="$(meta_allowlist_grants "$own")"`, in `load_allowlist`) moved to `setup-memory.d/allowlist.sh`; sed expression unchanged |

No assertion line, expected value or `sed`/`awk` mutation expression changed. Every run still uses `MEM` / `SUT` / `SCRIPT`; `HERE` is not re-pointed.

### 4.2 Other consumers (AC7, subtask 3)

| File | Hunk | Reason |
|---|---|---|
| `test-session-resume.sh` | `cp -R "$SCRIPT_DIR/setup-memory.d" "$mutd/"` beside `cp "$SCRIPT_DIR"/*.sh …` in `test_branch_mode_hint`'s mutant dir, and beside the `ZHM` copy | the copied `session-resume.sh` runs the copied `setup-memory.sh … mode`. The stub-dir copies (`sd`, the `cp "$sd/setup-memory.sh"` line) are counting stubs and need nothing |
| `test-migrate-branch-mode.sh` | `cp -R "$HERE/setup-memory.d" "$HERE/meta-sync.d" …` beside each scripts-dir copy that is then RUN (`build_mutant`, `reh-none`, `reh-log`, `mut-ms-tracked`, `stub-apply-refuses`, `stub-push-noop`) | without them the copied entries cannot load their modules: 126/132 with six failures (e.g. `mutation control (meta-sync tracked-learning hold) did not build`, `the pre-fix relation failed for another reason (preflight=FAIL …)`) |
| `test-migrate-branch-mode.sh` | `mut-ms-tracked`: the `meta-sync.sh` mutant is written from `_ms_bundle` output (`MSB`), its `cmp -s` gate reads `MSB` | `tracked_learning_hold` moved to `meta-sync.d/learning-twin.sh`; sed expression unchanged |
| `test-meta-sync-rehearsal.sh` | `build_mutant`: when `<file>` is `meta-sync.sh` the sed source and `cmp -s` gate read `MSB` (`_ms_bundle` output); `cp -R "$HERE/setup-memory.d" "$HERE/meta-sync.d" "$1/"` beside the scripts-dir copy | same reason; sed scripts and `grep -qF` gates unchanged |
| `test-automate-helpers.sh` | `cp -R "$HERE/setup-memory.d" "$HERE/meta-sync.d" "$RSM/"` beside both `cp "$HERE"/*.sh "$HERE"/*.py "$RSM/"` staging copies | brief-directed staging parity. The `reconcile-status` mutants it runs do not reach `setup-memory.sh` today: 740/740 was also measured without this hunk |
| `test-automate-trail.d/02-closeout.sh`, `03-stamps-gate.sh`, `04-watcher-branch-mode.sh` (`bm-mut`), `05-finalize-closeout-others.sh`, `06-sweep.sh` | `cp -R "$HERE/setup-memory.d" "$HERE/meta-sync.d" "<dir>/"` beside every `cp "$HERE"/*.sh … ; cp -R "$HERE/automate-trail.d" "<dir>/"` staging copy (18 lines) | the copied `automate-trail.sh` calls `_branch_mode`, which runs the copied `setup-memory.sh … mode` from closeout, finalize, stage-sync and trail-pr. Without the `.d` the mode is read as `unknown`, so a mutant could go red for the wrong reason. Not added to `bm-i`'s `stub` / `strip` dirs (there `setup-memory.sh` is a stub or deleted, and `meta-sync` is a spy) |
| `test-automate-trail.d/02-closeout.sh` (`L6D`), `05-finalize-closeout-others.sh` (`CUD`, `MUTCO`, `RACELK`, `MUTLK`) | `cp -R "$SPYD/setup-memory.d" "$SPYD/meta-sync.d" "<dir>/"` beside each `cp -R "$SPYD/automate-trail.d"` copy (5 lines) | the same, for copies taken from the spy dir. Measured: without them `(CO1) unstage control did not discriminate` failed (785/786) because `MUTCO`'s copied `setup-memory.sh` could not load its modules. The `cp -R "$SPYD"/* …` copies already carry the `.d` dirs |
| `scripts/test-check-locale-prefix.sh` | leg 6: `MEMB` = `_sm_bundle` output; its `grep -qF '! env LC_ALL=C tr -d'` and the `sed` that writes `$tmp/r/setup-memory.sh` read `MEMB` | `gitignore_gate` moved to `setup-memory.d/probes.sh`. The fixture is still named `setup-memory.sh`, so the expected `OFFENDER setup-memory.sh:` text is unchanged and the leg passes |
| `test-committed-twin-scrub.sh` | the citation comment only (AC15, §6) | |
| `test-validate-entry.sh` | the cited line number only (AC15, §6) | |

Consumers with no hunk: `test-automate-lanes.sh` and parts (stubs written into `$T`, or `cp -R "$HERE"` which carries the `.d` dirs), `test-automate-trail.d/01-sidecar-trail-pr.sh` (copies named files only, never `setup-memory.sh`), `test-guard-lane-wait-armed.sh`, `test-script-event-telemetry.sh` (runs the real entry in place), `test-seed-rules.sh`, `test-wave-build.sh` (stubs), `test-write-agent-memory.sh`, `scripts/check-locale-prefix.sh`.

## 5. Vendor coupling (AC8)

| Path | Base | Branch |
|---|---|---|
| `loomwright/scripts/setup-memory.sh` | 54 | 8 |
| `loomwright/scripts/setup-memory.d/probes.sh` | — | 18 |
| `loomwright/scripts/setup-memory.d/detect.sh` | — | 8 |
| `loomwright/scripts/setup-memory.d/report.sh` | — | 12 |
| `loomwright/scripts/setup-memory.d/commands.sh` | — | 8 |
| `loomwright/scripts/test-setup-memory.sh` | 108 | 17 |
| `loomwright/scripts/test-setup-memory.d/01-gitignore-paths.sh` | — | 57 |
| `loomwright/scripts/test-setup-memory.d/03-apply-safety-ledger-gate.sh` | — | 27 |
| `loomwright/scripts/test-setup-memory.d/04-verdicts-trail.sh` | — | 2 |
| `loomwright/scripts/test-setup-memory.d/05-branch-mode-consent.sh` | — | 5 |

54 = 8 + 18 + 8 + 12 + 8 and 108 = 17 + 57 + 27 + 2 + 5. The base manifest has no allowance for `meta-sync.sh` or `test-meta-sync.sh`, and the gate reports no breach for their modules or parts. Each new path has the reason `moved by automate-speed/20 split — no reference added`. The gate's TOTAL (flat) is 2663 on base and branch.

## 6. Citations (AC12, AC15)

Pinned line citations into either script (`git grep -nE '(setup-memory|meta-sync)(\.d/[a-z-]+)?\.sh:[0-9]+'` over `loomwright/scripts/*.sh`, `loomwright/scripts/test-*.d/*.sh`, `scripts/*.sh`, `*.md`):

| Citation | Base | Branch | Pin text found at (grep on the integrated tree) |
|---|---|---|---|
| `test-committed-twin-scrub.sh:8` | `setup-memory.sh:1616 [pins: \`Removal does NOT unpublish\`]` | `setup-memory.d/report.sh:44 [pins: …]` | `setup-memory.d/report.sh:44` (`print_consent_disclosure`; the second hit, :107, is the branch-mode disclosure) |
| `test-validate-entry.sh:712` | `--entry "… setup-memory.sh:224"` `# [pins: \`robust to header edits\`]` | `setup-memory.sh:255` | `setup-memory.sh:255` (the entry's `usage` comment; the `# Modules` block shifted it) |
| `CHANGELOG.md:529` | release history | unchanged | historical text, not a live citation; `test-citation-drift.sh` passes |

Pin texts unchanged; `test-citation-drift.sh` 26/26.

Prose citations of a moved function or of an entry header (`git grep -nE '(setup-memory|meta-sync)\.sh' -- '*.md'`, 72 lines, filtered to the lines that name a moved function or a script header). Each one is resolvable through the entry's `# Modules` map or because the header did not move:

| Citation | Names | Resolvable through |
|---|---|---|
| `loomwright/commands/setup.md:268` | `setup-memory.sh`'s header (`--help`) | header stays in the entry |
| `loomwright/commands/setup.md:270` | `setup-memory.sh`'s header invariant | header stays in the entry |
| `loomwright/docs/ARCHITECTURE_CONTRACTS.md:324` | `setup-memory.sh`'s header, CONSENT; `remote_slug` | header line 71 (`CONSENT IS LOAD-BEARING`); map: `remote_slug` → `allowlist.sh` |
| `loomwright/docs/ARCHITECTURE_CONTRACTS.md:328` | "the script header holds the bound" (`meta-sync.sh`) | header stays in the entry |
| `loomwright/docs/ARCHITECTURE_CONTRACTS.md:330` | `is_managed`, `scan_file` | map: `managed.sh`, `scrub.sh` |
| `loomwright/docs/ARCHITECTURE_CONTRACTS.md:345` | `test-meta-sync.sh` header's `# Covers` list | runner header line 7, unmoved |
| `loomwright/docs/CORE_CONTRACT.md:45` | `is_managed` | map: `managed.sh` |
| `loomwright/docs/CORE_CONTRACT.md:60` | `setup-memory.sh` header | header stays in the entry |
| `loomwright/docs/CORE_CONTRACT.md:64` | `is_managed` | map: `managed.sh` |
| `loomwright/skills/setup/SKILL.md:277` | the header's WRITE-CONTAINMENT INVARIANT | header line 87, unmoved |

The "meta-sync.sh header: CONSENT" citations in `setup-memory.sh` and `meta-sync-rehearsal.sh` still resolve: `meta-sync.sh`'s header keeps its CONSENT section. No prose file outside this item's lanes was edited (AC13).

## 7. Running system (AC10, AC11)

Commands run from the primary checkout as `--root`, first with `<base>/loomwright/scripts`, then with the branch's, then base again, then branch again, back to back (`ac11.sh <scripts-dir> <out>`):

```
meta-sync.sh status --branch as20-throwaway-not-on-origin --root <checkout>
meta-sync.sh status --branch as20-throwaway-not-on-origin --allow-branch-mismatch --root <checkout>
meta-sync.sh status --root <checkout>                       # the mode branch, loomwright-meta
meta-sync.sh status --paths --learning --root <checkout>
setup-memory.sh --root <checkout> mode
setup-memory.sh --root <checkout> check
meta-sync.sh list-managed --root <checkout>
meta-sync.sh list-managed --tracked --root <checkout>
meta-sync.sh scrub --paths-from <list-managed output> --root <checkout>
meta-sync.sh scrub --paths-from paths.txt --root <scrub-hit fixture>   # email, home_path, forge_slug planted
```

Result: base run 1, base run 2, branch run 1 and branch run 2 are byte-identical (985 lines each, sha256 `954edc151c49…`; the list-managed set, 874 paths, sha256 `2084b4977552…` on both). The two base runs do not differ, so no clock or age field appears in these outputs. The same four-way identity held in an earlier run in the same session.

Output (identical on base and branch; checkout path shown as `<checkout>`; the 79-line `check` report and the 874-path `list-managed` list are shown by count and hash above):

```
### meta-sync status --branch as20-throwaway-not-on-origin
meta_sync: branch_mismatch — --branch 'as20-throwaway-not-on-origin' but this checkout's mode line names 'loomwright-meta'; nothing was changed. Drop --branch to target 'loomwright-meta', or add --allow-branch-mismatch to force 'as20-throwaway-not-on-origin'.
rc=1
### meta-sync status --branch as20-throwaway-not-on-origin --allow-branch-mismatch
no_remote_branch
rc=0
### meta-sync status (mode branch)
local_ahead 1
rc=0
### meta-sync status --paths --learning (mode branch)
local_ahead 1
  .supervisor/automate/automate-2026-10-15-163325-L13.md
learning: synced; consent none
rc=0
### setup-memory mode
on loomwright-meta
rc=0
### setup-memory check
Memory store report for: <checkout>
  .gitignore:        ok
  managed block:     present
  branch mode:       on loomwright-meta (run history is synced to that branch and stays ignored here)
  … (79 lines)
rc=0
### meta-sync list-managed
… (874 paths)
rc=0
### meta-sync list-managed --tracked
rc=0
### meta-sync scrub over the list-managed set
meta_sync: clean (874 file(s) scanned)
rc=0
### meta-sync scrub over the hit fixture
meta_sync: scrub-hit .supervisor/automate/hit.md:2: email
meta_sync: scrub-hit .supervisor/automate/hit.md:1: home_path
meta_sync: scrub-hit .supervisor/automate/hit.md:-: forge_slug
meta_sync: aborted — scrub hit(s) above in 1 of 2 file(s); nothing was changed (clean or exclude the named paths before a push)
rc=2
```

`meta-sync-rehearsal.sh`, `migrate-branch-mode.sh`, `loomwright/hooks/hooks.json` and `loomwright/capabilities.json` are byte-unchanged (`git diff --quiet a8819a3 -- <path>`).

## 8. `bash scripts/ci-local.sh` (AC12)

Run on the base worktree, then on the branch tree (before this section was filled in), one after the other, on a shared machine (load average 25 to 36 during the runs):

| Tree | Early phase | Pool | Verdict | Red legs |
|---|---|---|---|---|
| base `a8819a3` | 16/16 | 169/171 | FAIL after 1533s | `test-automate-trail.sh` and `test-migrate-branch-mode.sh`: both `TIMEOUT after 900s` (exit 124, the per-test watchdog) |
| branch | 16/16 | 172/173 | FAIL after 1599s | `test-automate-trail.sh`: `TIMEOUT after 900s` (exit 124) |

The branch's only red leg is red on base too, and for the same reason: the 900s watchdog under load, not an assertion. Run alone, both suites pass on both trees: `test-automate-trail.sh` 786/786 (base 683s; branch measured alone after the `$SPYD` hunks) and `test-migrate-branch-mode.sh` 133/133 (base 521s; branch 580s), §1. The pool has 2 more entries on the branch: the two `*-modules.sh` tests. `sdk-spike` (npm build + node suites) is not run locally on either tree; CI runs it.
