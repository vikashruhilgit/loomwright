# tr09b — native overlap map and capability-scan cadence: evidence

Requirement: `.supervisor/requirements/twin-remediation/09b-overlap-map-and-scan-cadence.md`. Doc: `loomwright/docs/NATIVE_OVERLAP.md`. Reminder: `scripts/bump-version.sh` §"SCAN REMINDER" (header) and `scan_reminder()`.

All commands ran at the repo root of this branch (cut from `origin/main` at `29967f6`), with this branch's fragment and two fragments already on main and still unfolded (`changelog.d/lanes-test-parts-standalone-guard.md`, `changelog.d/salvage-drain-records.md`) pending.

## AC10 — the reminder in the running system

### `bash scripts/bump-version.sh --dry-run`

No reminder line: with no level argument the level comes from the fragments, and no pending fragment carries a `<!-- bump: X -->` directive, so the run is a patch (`17.14.1 -> 17.14.2`). The reminder prints only on minor or major.

```
bump-version: DRY RUN — nothing written
  version:   17.14.1 -> 17.14.2 (patch, from highest fragment request)
  fragments: changelog.d/lanes-test-parts-standalone-guard.md changelog.d/salvage-drain-records.md changelog.d/tr09b-overlap-map-and-scan-cadence.md
  also regenerates: loomwright/capabilities.json (plugin_version only)
  CHANGELOG entry:
**v17.14.2 — A test-automate-lanes part run on its own no longer SIGTERMs every live /automate lane; A drained worktree's salvage now keeps its drain records; The native overlap decisions are recorded, and a minor or major bump reminds you to re-scan the platform:** Each `loomwright/scripts/test-automate-lanes.d/` part is sourced by `test-automate-lanes.sh`, which sets the hermetic `$T`. Run standalone, `$T` was empty, so the AN-z cleanup in `06-phase-sessions.sh` turned `pgrep -f "_lane-run $T"` into `_lane-run ` and SIGTERMed every live lane wrapper on the machine (two lanes of a live wave on 2026-10-22). Every part now exits 2 on its first line unless the entry script sourced it, and every name-pattern process lookup in the suite goes through one helper, `tal_pgrep`, which refuses an empty or relative `$T` and any path outside it. `test-automate-lanes.sh` and `test-guard-lane-wait-armed.sh` also stop when `mktemp -d` fails instead of using the working directory as `$T`. The new `test-automate-lanes-standalone.sh` runs each part standalone beside a decoy `_lane-run` process and checks that the part exits 2, reaches no `pgrep` / `pkill`, and leaves the decoy alive. It also fails a part without the guard and any raw `pgrep -f` / `pkill -f` line, with mutation controls. `worktree-salvage.sh --ignored` copied only `.supervisor/logs/`, `.supervisor/postmortem/` and the host settings file. A drained PR worktree also holds `.supervisor/drain-rounds/` (the round ledger) and `.supervisor/review-heal/` (the REVIEW_HEAL_RESULT sidecars). Neither was on the salvage list, so neither was copied. Under closeout's `--allow-unsalvaged` the verdict read `ignored: ok 1` and the worktree was removed with them. Without that flag, the coverage check named only its FIRST unsalvaged entry. That was an empty `.supervisor/check-wait/`, so the real records stayed hidden behind a harmless-looking empty dir. Both drain dirs are now on the salvage list and are copied and verified. An empty directory (no file at any depth) never fails the verdict, and one `find` cannot read is still named, so the check stays fail-closed. The `failed` and `ignored-check: unsalvaged` lines now name every uncovered entry, joined by `, `. The README's list is read from `ign_salvage_list` instead of restating it. A new `loomwright/docs/NATIVE_OVERLAP.md` records the native-vs-ours verdicts, and every platform claim in it cites a `CAPABILITY_BASELINE.json` entry or is marked unverified. The Execute Manager poll loop vs native background completion notifications (2b) is KEEP OURS: the baseline records that capability only by name, and whether a notification reaches a subagent is unverified. Supervisor's worker worktrees vs native `isolation: worktree` (2d) is BLOCKED, because the native worktree branches from the default branch, not the parent session's HEAD; an owner-run re-probe in a reinstalled-plugin session is the trigger to revisit. The Workflow tool and nested spawning (2c) and Agent Teams (2e) are KEEP OURS. The agent-teams skill's dated graduation snapshot is replaced by the 2e verdict and a pointer. `bash scripts/bump-version.sh` now prints `bump-version: capability baseline last scanned at <X.Y.Z>; run /capability-check` on every minor or major bump and its `--dry-run`, reading `plugin_version_at_last_scan` live from the baseline. A patch bump, `--check`, a `--refold` no-op and a missing or invalid baseline print nothing, and the line never changes the exit status.
rc=0
```

### `bash scripts/bump-version.sh minor --dry-run`

The last line is the reminder, with the live baseline's `plugin_version_at_last_scan` (`15.132.0`). Nothing was written (`git status` unchanged after both runs).

```
bump-version: DRY RUN — nothing written
  version:   17.14.1 -> 17.15.0 (minor, from argument)
  fragments: changelog.d/lanes-test-parts-standalone-guard.md changelog.d/salvage-drain-records.md changelog.d/tr09b-overlap-map-and-scan-cadence.md
  also regenerates: loomwright/capabilities.json (plugin_version only)
  CHANGELOG entry:
**v17.15.0 — A test-automate-lanes part run on its own no longer SIGTERMs every live /automate lane; A drained worktree's salvage now keeps its drain records; The native overlap decisions are recorded, and a minor or major bump reminds you to re-scan the platform:** Each `loomwright/scripts/test-automate-lanes.d/` part is sourced by `test-automate-lanes.sh`, which sets the hermetic `$T`. Run standalone, `$T` was empty, so the AN-z cleanup in `06-phase-sessions.sh` turned `pgrep -f "_lane-run $T"` into `_lane-run ` and SIGTERMed every live lane wrapper on the machine (two lanes of a live wave on 2026-10-22). Every part now exits 2 on its first line unless the entry script sourced it, and every name-pattern process lookup in the suite goes through one helper, `tal_pgrep`, which refuses an empty or relative `$T` and any path outside it. `test-automate-lanes.sh` and `test-guard-lane-wait-armed.sh` also stop when `mktemp -d` fails instead of using the working directory as `$T`. The new `test-automate-lanes-standalone.sh` runs each part standalone beside a decoy `_lane-run` process and checks that the part exits 2, reaches no `pgrep` / `pkill`, and leaves the decoy alive. It also fails a part without the guard and any raw `pgrep -f` / `pkill -f` line, with mutation controls. `worktree-salvage.sh --ignored` copied only `.supervisor/logs/`, `.supervisor/postmortem/` and the host settings file. A drained PR worktree also holds `.supervisor/drain-rounds/` (the round ledger) and `.supervisor/review-heal/` (the REVIEW_HEAL_RESULT sidecars). Neither was on the salvage list, so neither was copied. Under closeout's `--allow-unsalvaged` the verdict read `ignored: ok 1` and the worktree was removed with them. Without that flag, the coverage check named only its FIRST unsalvaged entry. That was an empty `.supervisor/check-wait/`, so the real records stayed hidden behind a harmless-looking empty dir. Both drain dirs are now on the salvage list and are copied and verified. An empty directory (no file at any depth) never fails the verdict, and one `find` cannot read is still named, so the check stays fail-closed. The `failed` and `ignored-check: unsalvaged` lines now name every uncovered entry, joined by `, `. The README's list is read from `ign_salvage_list` instead of restating it. A new `loomwright/docs/NATIVE_OVERLAP.md` records the native-vs-ours verdicts, and every platform claim in it cites a `CAPABILITY_BASELINE.json` entry or is marked unverified. The Execute Manager poll loop vs native background completion notifications (2b) is KEEP OURS: the baseline records that capability only by name, and whether a notification reaches a subagent is unverified. Supervisor's worker worktrees vs native `isolation: worktree` (2d) is BLOCKED, because the native worktree branches from the default branch, not the parent session's HEAD; an owner-run re-probe in a reinstalled-plugin session is the trigger to revisit. The Workflow tool and nested spawning (2c) and Agent Teams (2e) are KEEP OURS. The agent-teams skill's dated graduation snapshot is replaced by the 2e verdict and a pointer. `bash scripts/bump-version.sh` now prints `bump-version: capability baseline last scanned at <X.Y.Z>; run /capability-check` on every minor or major bump and its `--dry-run`, reading `plugin_version_at_last_scan` live from the baseline. A patch bump, `--check`, a `--refold` no-op and a missing or invalid baseline print nothing, and the line never changes the exit status.
bump-version: capability baseline last scanned at 15.132.0; run /capability-check
rc=0
```

## Gate summaries

```
$ bash scripts/test-bump-version.sh
RESULT: 139 passed, 0 failed, 0 skipped
$ bash scripts/check-doc-currency.sh
✓ doc-currency: all checked version/count claims match the authoritative source.
$ bash loomwright/scripts/test-citation-drift.sh
citation-drift: 26 passed, 0 failed
$ bash scripts/check-token-budget.sh
agent-teams                2974     3231  OK      257 headroom (1 .md files)
check-token-budget: OK — every agent, skill dir and command doc within its declared prompt-inventory budget.
$ bash scripts/check-vendor-coupling.sh
loomwright/docs/CAPABILITY_BASELINE.json                       coupled                  10      10  OK      at allowance [install_root=2 orchestration=3 ask_user=2 hook_protocol=1 model_names=2]
loomwright/skills/agent-teams/SKILL.md                         coupled                   4       4  OK      at allowance [install_root=3 orchestration=1]
check-vendor-coupling: OK — no path exceeds its declared vendor-coupling allowance, and every raise or exemption carries a reason.
$ bash scripts/check-prompt-history-refs.sh
check-prompt-history-refs: scanned files: 125 | references: 421 | violations: 0 | errors: 0
check-prompt-history-refs: OK — no runtime prompt above its baseline, and the baseline did not rise.
$ bash scripts/check-version-bump.sh
bump-version: check OK — not bumped (version 17.14.1, the merge base's); 3 fragment(s) pending — legal, the next bump folds them (base origin/main, merge base 29967f686890)
```

`loomwright/docs/NATIVE_OVERLAP.md` is not in the vendor-coupling table: it carries 0 references (a `coupled` path with no allowance may carry 0). Before the skill edit, `check-prompt-history-refs.sh` printed `lower the baseline: loomwright/skills/agent-teams/SKILL.md 3 -> 2`, and the baseline entry was lowered to 2.

## The new suite cases (`scripts/test-bump-version.sh` §9f)

```
ok   - scan reminder: a minor bump exits 0, bumps, and prints exactly one 'capability baseline last scanned at 1.0.0; run /capability-check' line
ok   - scan reminder: the line carries the bump-version: prefix, and the wave release step's version parse still reads 1.3.0
ok   - scan reminder: a major bump exits 0, bumps, and prints exactly one reminder line
ok   - scan reminder: a patch bump (no level, no directive) prints no reminder
ok   - scan reminder: 'minor --dry-run' exits 0, writes nothing, and prints the reminder
ok   - scan reminder fail-SAFE: (i) no baseline file — minor bump exits 0 and bumps, no reminder, no jq: error text
ok   - scan reminder fail-SAFE (i) precondition: the fixture has no baseline
ok   - scan reminder fail-SAFE: (ii) invalid JSON — minor bump exits 0 and bumps, no reminder, no jq: error text
ok   - scan reminder fail-SAFE: (iii) valid JSON, plugin_version_at_last_scan absent — minor bump exits 0 and bumps, no reminder, no jq: error text
ok   - scan reminder fail-SAFE: (iii) valid JSON, plugin_version_at_last_scan not X.Y.Z — minor bump exits 0 and bumps, no reminder, no jq: error text
ok   - scan reminder: --check (not bumped) prints none
ok   - scan reminder: the --refold no-op on a fragments-only branch prints none
ok   - scan reminder: --check (bumped) prints none
ok   - scan reminder: the --refold no-op on a current bump prints none
ok   - scan reminder: a minor re-fold prints it once (the child bump) and refold-touched: stays the last line
ok   - mutation control: with the level guard at -ge 4, a minor bump prints no reminder (the minor case would be red)
ok   - mutation control: with the level guard at -ge 1, a patch bump prints the reminder (the patch case would be red)
ok   - mutation control: without the X.Y.Z guard, a baseline lacking the key prints a reminder (case iii would be red)
ok   - mutation control: without the stderr guard, the missing-baseline shape leaks jq: error text (case i / ii would be red)
ok   - mutation control: without the stderr guard, the invalid-baseline shape leaks jq: error text (case i / ii would be red)
ok   - mutation control: with the jq-line guard exiting 1, a missing baseline fails the bump (case i would be red)
ok   - mutation control: without the dry-run call, 'minor --dry-run' prints no reminder (the dry-run case would be red)
```

## Pin mutations, each applied once by hand

Each row of the brief's Pin mutations table was re-applied on this branch to a copy of `scripts/bump-version.sh` (the literals are the brief's, unchanged), and the suite was run against the copy through its `BUMP_VERSION_UNDER_TEST` seam. The working tree's script was never edited, so nothing needed restoring. Every row turns its target case red. The §9f in-suite mutation controls also go red under every row, because their own mutation no longer applies to an already-mutated copy.

| Row | Mutation | Target case red | Suite result |
|-----|----------|-----------------|--------------|
| r1 | `-ge 2 ] \|\| return 0` → `-ge 4 ] \|\| return 0` | yes — `FAIL - scan reminder: a minor bump exits 0…` | `RESULT: 128 passed, 11 failed, 0 skipped` |
| r2 | `-ge 2 ] \|\| return 0` → `-ge 1 ] \|\| return 0` | yes — `FAIL - scan reminder: a patch bump…` | `RESULT: 136 passed, 3 failed, 0 skipped` |
| r3 | `semver_ok "$v" \|\| return 0` → `: \|\| return 0` | yes — `FAIL - scan reminder fail-SAFE: (iii) valid JSON, plugin_version_at_last_scan absent…` | `RESULT: 136 passed, 3 failed, 0 skipped` |
| r4 | `"$CAP_BASELINE" 2>/dev/null)` → `"$CAP_BASELINE")` | yes — `FAIL - scan reminder fail-SAFE: (i) no baseline file…` | `RESULT: 134 passed, 5 failed, 0 skipped` |
| r5 | `2>/dev/null)" \|\| return 0` → `2>/dev/null)" \|\| exit 1` | yes — `FAIL - scan reminder fail-SAFE: (i) no baseline file…` | `RESULT: 131 passed, 8 failed, 0 skipped` |
| r6 | delete the `scan_reminder` call after `printf '%s\n' "$entry"` | yes — `FAIL - scan reminder: 'minor --dry-run'…` | `RESULT: 137 passed, 2 failed, 0 skipped` |

Row r4 also turns case (ii) (invalid JSON) red, and r5 also reddens three pre-existing minor/major cases with no baseline (`fold: three fragments bump`, `--dry-run: exit 0 …`, `re-fold: a later minor fragment …`), as expected: every fixture without a baseline is the missing-file shape.
