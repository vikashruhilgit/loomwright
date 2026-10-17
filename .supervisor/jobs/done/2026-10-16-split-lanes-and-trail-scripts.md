# Supervisor Job: Split automate-lanes.sh and automate-trail.sh into sourced modules (move-only)

## Environment
- **Project:** ai-agent-manager-lanes/automate-2026-10-15-163325/L8 (lane checkout; repo `vikashruhilgit/loomwright`)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 2 (branch mode ON — `.supervisor/` run history lives on the metadata branch; this is lane L8 of a 4-lane wave, so siblings may edit `loomwright/docs/vendor-coupling-manifest.json` in the same wave)
- **Source requirement:** .supervisor/requirements/automate-speed/19-split-lanes-and-trail-scripts.md
- **Base commit:** 142540b8210a4b206e87e2b4349999c9978f8e29

## Pre-flight decision (Supervisor Phase 1.5, owner: proceed-anyway)
- `origin/main` moved after planning: PR #569 (31c74be, f9ba064) changed `loomwright/scripts/automate-lanes.sh` and `loomwright/scripts/test-automate-lanes.sh`. The feature branch is cut from **`051553e`**, which includes it.
- **Every reference to base `142540b` in this brief now means `051553e`:** AC3's verbatim-move equality is `git show 051553e:<path>`, AC5's base totals and AC11's base worktree are re-measured at `051553e` (the 861/782 figures above were taken at `142540b` and are superseded).
- Open PR #570 (sibling lane) also edits `loomwright/docs/vendor-coupling-manifest.json`; resolved at wave build.

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2-safe shell only; no new language or dependency |
| 2 | Dependency Availability | GO | The requirement's precondition holds: `feature/af39a-sweep` merged as PR #555 (2026-10-15T10:49:38Z) and is on `origin/main` at the base commit |
| 3 | Architecture Fit | CAUTION | The repo already has the convention (`automate-helpers.sh` + `automate-helpers.d/`, parallel-automate/11, PR #408). That precedent found that a split breaks every test that `sed`s/`awk`s the monolith into a mutant copy or stages a scripts dir with `cp "$HERE"/*.sh`; here both test files do both (lanes: 11+ mutant builders writing `$MUT/automate-lanes.sh`; trail: ~20 `cp "$HERE"/*.sh … ; cp -R "$HERE/automate-helpers.d"` staging dirs and `sed … "$HERE/automate-trail.sh"` mutants). Resolved below by the precedent's bundle technique |
| 4 | Scope vs Supervisor Capability | CAUTION | ~6,100 script lines + ~6,700 test lines move; two file-disjoint groups (lanes, trail) ⇒ split `genuine-parallelism`, plus one integration subtask for the shared gates |
| 5 | Hard Blockers | GO | none |

**Overall Verdict:** CAUTION

## Task
**Goal:** Turn `loomwright/scripts/automate-lanes.sh` and `loomwright/scripts/automate-trail.sh` into thin entry points that source one module per concern from `loomwright/scripts/automate-lanes.d/` and `loomwright/scripts/automate-trail.d/`, split their two test files the same way, and keep every subcommand, flag, output byte, exit code and test assertion identical (owner decision D6: move-only).

**Problem Statement:**
The owner (and every parallel lane) needs lane, wave and trail changes to touch small files, because today every such change edits the same 3,852-line `automate-lanes.sh` (or the 2,241-line `automate-trail.sh`) and their 3,149 / 3,511-line tests.
Currently, two lanes of one wave collide on these files and reviewers read far more than the change.
Success looks like: no module over ~800 lines, the same test totals before and after, byte-identical help/usage and `lane-status` output.

**Base measurements (taken at `142540b` by Launch Pad, to be re-measured by the workers):** `bash loomwright/scripts/test-automate-lanes.sh` ⇒ `passed: 861  failed: 0`; `bash loomwright/scripts/test-automate-trail.sh` ⇒ `test-automate-trail: 782 passed, 0 failed`.

## Acceptance Criteria
- [ ] AC1 — Given the split, when `automate-lanes.sh <subcommand> …` is invoked (directly, through `automate-helpers.sh`, or after being SOURCED by `automate-wave.sh` / `guard-lane-wait-armed.sh`), then stdout, stderr and exit code equal base for every subcommand in `lanes_main`'s `case` table, including `--help`/`-h`/`help` and an unknown subcommand (usage on stderr, exit 2). The entry point keeps the whole header comment (the `# Usage (standalone` block `_lanes_usage` reads from `"$SELF"`, and the `# Files` block the skill calls the contract), the config/variable block (`SELF`, `HERE`, `PLUGIN_ROOT`, `META_SYNC` … `LT_HEADER`, `LANE_DISALLOWED_FIXED`), `lanes_main` and the `if [ "${BASH_SOURCE[0]}" = "$0" ]` guard. Each module is sourced by name (never a glob), resolved from `"$(dirname "${BASH_SOURCE[0]}")/automate-lanes.d/"` of the entry point, at the position its code held in the monolith. A missing/unreadable module: run directly ⇒ non-zero exit naming the file; SOURCED ⇒ `return 1` naming the file on stderr (never `exit`), so a sourcing caller's own fallback runs (`guard-lane-wait-armed.sh`'s `. "$LANES_SH" >/dev/null 2>&1 || allow` must still print `{}`; `automate-wave.sh`'s `|| { echo "wave-build: refused — automate-lanes.sh unreadable"; exit 1; }` must still fire).
- [ ] AC2 — Given the split, when `automate-trail.sh <subcommand> …` is invoked (directly or via `automate-helpers.sh`), then stdout, stderr and exit code equal base for every subcommand in `main`'s `case` table, including `""`/`-h`/`--help` and an unknown subcommand. Base `--help` is `grep -E '^#   [a-z]' "$0"` over the WHOLE file and matches body comment lines (e.g. the `trail-gate: PARK —` lines inside `trail_gate`'s comment and the sweep classification lines), so the help arm greps the in-memory bundle (entry with each module expanded at its source point), exactly as `automate-helpers.sh`'s `_ah_bundle`/`_ah_usage` do. A missing/unreadable module ⇒ non-zero exit naming the file (trail is never sourced by another script — verify with `git grep`).
- [ ] AC3 — Given each entry point, when its bundle function runs (`<script> ` exposes it the way `_ah_bundle` is exposed — a self-contained function the tests can `eval`), then the bundle with the loader definitions and the source-marker lines removed equals `git show 142540b:<path>` byte-for-byte (proof the code moved verbatim). The only other permitted hunk is the help/usage arm switching its input from the whole file to the bundle; it is listed in the evidence file.
- [ ] AC4 — Given `wc -l` over every new module, then no module exceeds 800 lines, and every module passes `bash -n` and runs under bash 3.2 with `set -u` (no bash-4-only syntax added; the code is moved, not rewritten).
- [ ] AC5 — Given `test-automate-lanes.sh` and `test-automate-trail.sh`, when each runs on the branch, then it reports the same totals as base (lanes `passed: 861  failed: 0`, trail `782 passed, 0 failed`, re-measured on a clean base worktree in the same session), and each test file is a thin runner that keeps its header comment, its hermetic first executable line (`check-test-hermetic.sh` passes), its shared setup and pass/fail helpers, and sources its parts BY NAME (never a glob) from `loomwright/scripts/test-automate-lanes.d/` / `loomwright/scripts/test-automate-trail.d/` in base order. No assertion line (lanes: `ok`/`bad`/`check`/`has`/`hasnt`; trail: `ok`/`no` and its helpers), no expected value and no mutation pattern (`sed`/`awk`/`grep -v` expression) is edited. Every RUN of the script under test keeps running the REAL entry point (`S="$HERE/automate-lanes.sh"`, `T="$HERE/automate-trail.sh"` unchanged; `HERE` is never re-pointed — both tests also read `$HERE/../skills/…` and the lanes test asserts the real plugin root via H1's `--plugin-dir`). The only non-move edits allowed are (a) a separate bundle variable (e.g. `SB` / `TB`, the `_lanes_bundle` / `_trail_bundle` output written once to a temp file) used for every TEXT read — mutant builders (`awk/sed/grep -v … "$SB" > "$MUT/automate-lanes.sh"`), their `cmp -s` gates and static greps over the script text (e.g. lanes' AG6 guard) — a mutant written from the bundle is a single self-contained file, so it runs without a `.d` dir; (b) a staging copy that must run the REAL entry adding `cp -R "$HERE/automate-trail.d"` / `automate-lanes.d` beside its existing `automate-helpers.d` copy (the precedent's setup-only fix); (c) the test parts loader — every such hunk is listed in the evidence file with its reason.
- [ ] AC6 — Given a new `loomwright/scripts/test-automate-lanes-modules.sh` (subtask 1) and `loomwright/scripts/test-automate-trail-modules.sh` (subtask 2), each modelled on `test-automate-helpers-dispatch.sh`, when they run, then they exercise the REAL entry point (not the bundle): every `case` arm reaches its function (never the usage/unknown branch); `--help` and the no-arg/unknown output equal base's (from the `142540b` blob via `git show`, a named SKIP in a shallow clone); a stray file in the `.d` dir is not sourced; a copy with one module removed exits non-zero naming it (and, for lanes, returns non-zero without exiting when sourced); AC3's verbatim-move equality holds; and each mutant is gated on non-empty + differs + `bash -n`.
- [ ] AC7 — Given the gates whose scan sets glob `loomwright/scripts/test-*.sh` for test CONTENT — `test-no-pipefail-grep-q.sh` (its rule-1 `files=(…)` array) and `test-no-fixed-sleep-race.sh` (its `files=(…)` array) — when they run after the split, then they also scan `loomwright/scripts/test-*.d/*.sh` (so moved test code is not exempted), and a planted violation in a test part is caught (one mutant leg each). `check-test-hermetic.sh` needs no change: parts are not standalone tests; the runner still carries the hermetic line.
- [ ] AC8 — Given `test-wave-build.sh`'s W6d check (`automate-lanes.sh still has no executable git merge / push`, which greps `$L`), when it runs after the split, then it greps the lanes entry point AND every `automate-lanes.d/*.sh` module (or the bundle), so the check is not weakened to the thin entry point; its expected value (`""`) is unchanged. Same for `test-automate-lanes.sh`'s check that greps `"$HERE/automate-trail.sh"` for `fleet-closeout|wave-plan` (it must also read `automate-trail.d/*.sh`), expected `0:1` unchanged.
- [ ] AC9 — Given `loomwright/docs/vendor-coupling-manifest.json`, when `bash scripts/check-vendor-coupling.sh` runs on the integrated branch, then it passes with the flat total unchanged: each allowance for `automate-lanes.sh` (34), `test-automate-lanes.sh` (46), `automate-trail.sh` (1) and `test-automate-trail.sh` (6) is moved to the paths that now carry those references, with one `allowance_reasons` entry per moved path reading `moved by automate-speed/19 split — no reference added`.
- [ ] AC10 — Given the external consumers, when they run on the branch, then they pass unchanged: `bash scripts/test-lanes-addon.sh` (the `loomwright-lanes` add-on calls `scripts/automate-lanes.sh lane-status|lane-feed|lane-answer`), `test-wave-build.sh`, `test-guard-lane-wait-armed.sh`, `test-automate-helpers.sh`, `test-automate-helpers-dispatch.sh`, `test-automate-golden.sh`, `bash scripts/check-vendor-coupling.sh`, `bash scripts/check-test-hermetic.sh`; `loomwright/hooks/hooks.json` and `loomwright/capabilities.json` are byte-unchanged.
- [ ] AC11 — Given the running system, when `automate-lanes.sh lane-status <a real parent run file>` and `lane-status <same> --json` run from a clean base worktree at `142540b` and then from the branch, back to back on the same input, then the outputs are byte-identical (a field that also differs between two consecutive base runs — a clock or age — is shown to do so and named).
- [ ] AC12 — Given the integrated branch, then a committed evidence file `docs/evidence/as19-split-lanes-and-trail-scripts.md` contains: the before/after `<passed>/<total>` for every test and gate in AC5–AC10 (and `bash scripts/ci-local.sh` totals for base and branch, every red leg shown red on base too); the final module list per script (module → functions → line count); every non-move hunk of AC3 and AC5 with its reason; the AC11 commands and outputs; and every committed prose citation of a function or comment block that moved (from `git grep` over `*.md`, e.g. `skills/automate-loop/lanes.md`'s "the `lanes_drain_check` header in `scripts/automate-lanes.sh`" and `per-item-loop.md`'s "the subcommand's header in `scripts/automate-lanes.sh` is the contract"), each judged resolvable through the entry point's module map (AC13) — and the PR body links to it.
- [ ] AC13 — Given each entry point's header, then it carries one `# Modules (sourced in this order from <script>.d/):` block naming each module and the subcommands/functions it holds, so a reader told "see the header in `scripts/automate-lanes.sh`" finds the module; no prose file outside this item's lanes is edited (pointer re-targeting, if wanted, is a follow-up).
- [ ] AC14 — Given `changelog.d/as19-split-lanes-and-trail-scripts.md`, then it exists in the `changelog.d/README.md` format with `<!-- bump: patch -->` as its first line, and `plugin.json`, `marketplace.json` and `CHANGELOG.md` are not hand-edited (`bash scripts/check-version-bump.sh` passes).

## Touched-file invariants

> Grounded at base `142540b`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/automate-lanes.sh`** — keep: the direct-run guard `if [ "${BASH_SOURCE[0]}" = "$0" ]; then lanes_main "$@"; exit $?; fi` (sourced callers get functions only); `SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"` — `SELF` must still name the ENTRY point, because `bash "$SELF" _lane-run`, `bash "$SELF" lane-convert-ready`, `bash "$SELF" lane-remove` and `bash "$SELF" lane-status` re-invoke it and `_lanes_usage` reads the header with `awk '/^# Usage \(standalone/ …' "$SELF"`; the two tokens only `LANE_DISALLOWED_FIXED=` may name (its comment: `These two are the only`) stay in the entry point; `set -uo pipefail` (not `-e`); reuse: the `_ah_source`/`_ah_bundle` shape from `automate-helpers.sh` for the loader and bundle; fired by: `automate-helpers.sh`'s `exec bash "$(dirname "$0")/automate-lanes.sh"` arms (pinned by `test-automate-helpers.sh`'s `/automate-lanes.sh\" \"$cmd\" \"$@\" ;;` awk), `automate-wave.sh`'s `. "$(dirname "$WAVE_SELF")/automate-lanes.sh"`, `guard-lane-wait-armed.sh`'s `. "$LANES_SH" >/dev/null 2>&1 || allow`, each lane's relay hook command `automate-lanes.sh" relay-hook` (pinned by `test-automate-lanes.sh`'s `test("automate-lanes.sh\" relay-hook$")`), and the add-on's `scripts/automate-lanes.sh` path (`loomwright-lanes/hooks/register.tsx`); pinned by: `test-wave-build.sh` W6d `automate-lanes.sh still has no executable git merge / push`; the in-file marker comments mutants anchor on (`# >>> spawn`, `# >>> awaiting-input check`, `# >>> live-process check`, `# TOTAL-CALL`, `# UNPUSHED-UNREADABLE`, `# REFUSE-BEFORE-STOP`, `# HOOK-ROOT`, `# LAUNCHLOCK`) move with their code, byte-unchanged.
- **`loomwright/scripts/automate-trail.sh`** — keep: `HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"` (sibling lookups resolve beside the entry point); `main "$@"` then `exit 0` (always exit 0 — fail-SAFE emitter, CLAUDE.md "Bimodal failure philosophy"); `*) echo "automate-trail: unknown subcommand: $cmd" >&2 ;;`; the help line `grep -E '^#   [a-z]' "$0" | sed 's/^#   /  /'` becomes a grep over the bundle with the same filter; mirror: `automate-helpers.sh`'s header `#:@ hdr-trail` usage lines and `fixtures/automate-helpers-help/hdr-trail.golden` stay byte-unchanged (they describe the CLI, which does not change); fired by: `automate-helpers.sh`'s `exec bash … automate-trail.sh` arms, `automate-lanes.sh`'s `sweep_sh="${LOOMWRIGHT_LANES_SWEEP:-$HERE/automate-trail.sh}"`, `automate-merge-watch.sh` via the helpers; pinned by: `test-automate-trail.sh` (`helper header names the automate-trail.sh carve-out`, the SN mutants `sed … "$HERE/automate-trail.sh"`), `test-automate-helpers.sh`.
- **`loomwright/scripts/test-automate-lanes.sh`** — keep: first executable line sourcing `hermetic-test-env.sh` (`check-test-hermetic.sh`'s `prefix='. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/'`); the final total line `echo "passed: $PASS  failed: $FAIL"` and exit code; `trap cleanup EXIT` and its `ere` pkill safety net; helpers `ok`/`bad`/`check`/`has`/`hasnt`; `run() { bash "$S" "$@" 2>&1; }` running the real entry; mutant gating `! cmp -s … && bash -n …`.
- **`loomwright/scripts/test-automate-trail.sh`** — keep: the hermetic first executable line; `trap cleanup_all EXIT`; the `_tally_ok`/`_tally_no` shadow counters its summary cross-checks; the final line `echo "test-automate-trail: $pass passed, $fail failed"` and exit code; `T="$HERE/automate-trail.sh"` running the real entry.
- **Both test files** — keep their basenames (named in `fixtures/self-test-weights.tsv` and globbed by `run-self-tests.sh` `tests=(loomwright/scripts/test-*.sh …)` — parts must NOT match that glob, hence the `test-<x>.d/` dirs).
- **`loomwright/scripts/test-no-pipefail-grep-q.sh` / `loomwright/scripts/test-no-fixed-sleep-race.sh`** — keep: their existing `files=(…loomwright/scripts/test-*.sh loomwright/scripts/adapters/*/test-*.sh …scripts/test-*.sh)` members and the `scanned ${#files[@]} test files` floor; extend only; `WRITER_BASELINE` (rule 2, all tracked `*.sh`) needs no edit unless a moved writer site's PATH changes — then re-point that one baseline row (count unchanged), as PR #408 did for `automate-helpers.d/reconcile-status.sh`.
- **`loomwright/scripts/test-wave-build.sh`** — keep: W6d's expected value `""` and its exclusion filter `grep -vE 'LANE_DISALLOWED_FIXED=|disallow="|echo "git |printf .git merge'`; only its input set widens (AC8).
- **`loomwright/docs/vendor-coupling-manifest.json`** — keep: flat total unchanged; `allowance_reasons` per path; `schema_version` and every other key byte-unchanged.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-automate-lanes-modules.sh` — every `case` arm reaches its function | delete `    lane-feed) lanes_feed "$@" ;;` in `loomwright/scripts/automate-lanes.sh` |
| `loomwright/scripts/test-automate-lanes-modules.sh` — sourced + missing module returns, not exits | flip `return 1` → `exit 1` in the lanes entry point's loader (scratch copy) |
| `loomwright/scripts/test-automate-trail-modules.sh` — `--help` equals base | revert the help arm's input from `_trail_bundle \| grep -E '^#   [a-z]'` to `grep -E '^#   [a-z]' "$0"` in `loomwright/scripts/automate-trail.sh` (drops the body lines the base help prints) |
| `loomwright/scripts/test-automate-lanes-modules.sh` / `test-automate-trail-modules.sh` — stray `.d` file not sourced | replace one by-name source line with a loop over `<script>.d/*.sh` in a scratch copy |
| both `*-modules.sh` — direct run with a missing module exits non-zero with the loader's own message `missing module file: automate-<x>.d/<name>.sh` (the test asserts that exact message, not just the file name) | replace the loader's missing-file branch with `:` in a scratch copy |
| both `*-modules.sh` — AC3 verbatim move | edit one moved line (e.g. append a space) in one module of a scratch copy |
| `loomwright/scripts/test-automate-lanes-modules.sh` — lanes `--help`/unknown equals base | flip `/^# Usage \(standalone/` → `/^# Usage \(standalonX/` in `_lanes_usage` of a scratch copy |
| `loomwright/scripts/test-automate-trail-modules.sh` — trail no-arg/unknown equals base | flip `unknown subcommand:` → `unknown command:` in `loomwright/scripts/automate-trail.sh` |
| `test-automate-lanes.d/` part holding the widened `fleet-closeout\|wave-plan` check (AC8) | add a `fleet-closeout` line to one `automate-trail.d/` module of a scratch copy (the check then reports `1:1`, not `0:1`) |
| `loomwright/scripts/test-automate-trail-modules.sh` — every `case` arm reaches its function | delete `    sweep)         sweep_run "$@" ;;` in `loomwright/scripts/automate-trail.sh` |
| `loomwright/scripts/test-no-pipefail-grep-q.sh` — test parts are scanned | delete the `loomwright/scripts/test-*.d/*.sh` member from its rule-1 `files=(…)` (planted part violation then passes) |
| `loomwright/scripts/test-no-fixed-sleep-race.sh` — test parts are scanned | delete the `loomwright/scripts/test-*.d/*.sh` member from its `files=(…)` |
| `loomwright/scripts/test-wave-build.sh` W6d — modules are read | add an executable `  git push origin HEAD` line to one `automate-lanes.d/` module of a scratch copy (W6d then reports that line instead of `""`) |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Split `automate-lanes.sh` + its test into `automate-lanes.d/` / `test-automate-lanes.d/` | AC1, AC3, AC4, AC5, AC6, AC13 (lanes halves) | 2 modify, ~14 create | `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 2 | Split `automate-trail.sh` + its test into `automate-trail.d/` / `test-automate-trail.d/` | AC2, AC3, AC4, AC5, AC6, AC13 (trail halves) | 2 modify, ~10 create | `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 3 | Integration: shared gates, cross-script checks, vendor manifest, running-system check, evidence, changelog | AC7, AC8, AC9, AC10, AC11, AC12, AC14 | ~5 modify, 2 create | `skills/ci-cd/SKILL.md`, `skills/unit-testing/SKILL.md` | BLOCKED (by #1, #2) |

### Subtask 1 — lanes split (detail)
- **Gates during subtasks 1–2:** until subtask 3 moves the vendor-coupling allowances and widens the shared gates, `check-vendor-coupling.sh` and `ci-local.sh` are expected red on a subtask-1/2 branch — workers 1 and 2 run their own test file, its `*-modules.sh` test and the consumers in AC10 that do not depend on the manifest; they never edit the manifest.
- **Modules (proposed; the worker confirms against the real call graph and records the final list in AC13's map and the evidence file; ≤ 800 lines each, cut at function boundaries in base order):** `common.sh` (`now_utc` … `_lanes_merge_hooks`: helpers, the `_lt_*` lane-table lock, `_lane_ctx`, `lanes_proc_alive`, salvage, hook merge), `create.sh` (`lanes_create`), `launch.sh` (`_lanes_regime_ok` … `_lanes_last_result`: admission, gate, spawn, run wrapper, launch), `relay.sh` (`_lanes_hook_root` … `_lanes_deliver_pending`: relay hook, policy apply, answer, pending delivery), `remove.sh` (`_lanes_stop_pid` … `lanes_convert_ready`: removal, metadata pushes, abandon, convert-ready), `notify-guards.sh` (`_lanes_click_action` … `lanes_branch_check`: park-notify, info, init-check, pick-guard, branch-check), `status-read.sh` (`_lanes_dash` … `_lanes_tokens_record`; split in two if > 800), `park-leaks.sh` (`lanes_park` … `lanes_leaks`), `status.sh` (`lanes_status` … `lanes_feed`: status, watch, wait, feed), `readiness.sh` (`_lanes_rd_section` … `lanes_validation_gate`), `wave.sh` (`_lanes_base_of` … `lanes_wave_plan`: fleet-closeout, wave resolve/plan). STAYS in the entry point: the header, the config/variable block, `die` if more than one module calls it, `_lanes_usage`, `lanes_main`, the direct-run guard, the loader and bundle functions.
- **Loader:** one source line per module between `# >>> automate-lanes.d/<name>.sh` / `# <<< automate-lanes.d/<name>.sh` markers, at the module's base position. Resolve the dir from the entry point's `${BASH_SOURCE[0]}` (sourced by `automate-wave.sh` / `guard-lane-wait-armed.sh`, `$0` is the CALLER). On a missing/unreadable module: when sourced, print `automate-lanes: missing module file: automate-lanes.d/<name>.sh` to stderr and make the SOURCE itself fail — a `return 1` inside a helper function only returns from the function and the file's last command (the false direct-run guard) would leave status 0, so each top-level loader line must propagate it (e.g. `_lanes_source x || { return 1 2>/dev/null || exit 1; }`); when run directly, `die`. The AC6 sourced-mode leg also runs `guard-lane-wait-armed.sh` against a copy missing one module and asserts it prints `{}`. Prove both in the modules test. Never a glob.
- **Bundle:** `_lanes_bundle [<entry>]` prints the entry with each `_lanes_source` line replaced by that module's text (self-contained so a test can `eval` it). `_lanes_usage` already reads only the header (which stays), so lanes' help needs no bundle — confirm by AC1.
- **Test split:** `test-automate-lanes.sh` keeps lines up to its shared setup (hermetic line, `HERE`, `T`, `cleanup`/`trap`, `ok`/`no`/`check`/`has` helpers, `PASS`/`FAIL`) and the final summary; the body moves verbatim, in order, into named parts under `loomwright/scripts/test-automate-lanes.d/` (≤ ~800 lines each, cut between test legs, never inside one), sourced by name. The lanes test helpers are `ok`/`bad`/`check`/`has`/`hasnt`. Keep `S="$HERE/automate-lanes.sh"` for every RUN (H1 asserts `--plugin-dir` is the real `loomwright/` dir, which a symlinked bundle dir would break via `resolve-loomwright-root.sh`, and lane-create writes `bash "<scripts>/automate-lanes.sh" relay-hook` from it). Add `SB` = `_lanes_bundle`'s output in a temp file and re-point only TEXT reads to it — every mutant builder (`awk … "$SB" > "$MUT/automate-lanes.sh"`, `sed … "$SB"`, `grep -v … "$SB"`), its `cmp -s` gate, and static greps over the script (the AG6 guard near the `fleet-closeout|wave-plan` check) — so each still finds its text. If the bundle cannot reproduce 861/861, STOP and report — never edit an assertion or mutation line.
- **New `test-automate-lanes-modules.sh`:** AC6 against the REAL entry point. Arguments that reach each subcommand's own usage/argument check (e.g. `lane-info --root /nonexistent`, `lane-park --root <tmp>`), asserting the output never comes from `_lanes_usage`'s unknown branch; sourced-mode proof: `( . <copy-without-a-module> ; echo rc=$? )` prints a non-zero rc and the shell survives.

### Subtask 2 — trail split (detail)
- **Modules (proposed; confirm and record):** `sidecar.sh` (`sidecar_check`), `trail-pr.sh` (`trail_cleanup` … `trail_pr`; split at `_trail_meta_push` if > 800), `stage-sync.sh` (`trail_unstage`, `trail_gate`, `_restage_landed`, `_restore_prior`, `_sync_primary`, `_run_lock_in`), `closeout.sh` (`co_release` … `closeout`), `finalize.sh` (`fe_release` … `closeout_others`), `sweep.sh` (`_sw_line` … `sweep_run`). STAYS: the header (with AC13's map), shared globals, `main` and `main "$@"; exit 0`, the loader and bundle.
- **Module map format:** trail's `--help` greps the bundle for `^#   [a-z]`, so AC13's map lines must not match it (write them `# - sweep.sh: …`, never `#   sweep.sh …`); AC2's diff proves it.
- **Loader/bundle:** same shape as subtask 1 (`_trail_source`, `_trail_bundle`), dir from `${BASH_SOURCE[0]}`; trail is only ever run, so a missing module `exit`s non-zero naming it — but note this is the ONE place the entry point may exit non-zero, and only on a broken install (a fail-SAFE emitter must not silently no-op on missing code; precedent `_ah_source`'s `die "missing family file: …"`). The `--help` arm becomes `_trail_bundle | grep -E '^#   [a-z]' | sed 's/^#   /  /'` (AC2).
- **Test split:** as subtask 1 (`test-automate-trail.d/`). This test reads `"$HERE/automate-trail.sh"` directly in its `sed` mutants and stages scripts dirs with `cp "$HERE"/*.sh "$HERE"/*.py "$X/"; cp -R "$HERE/automate-helpers.d" "$X/"` in ~20 places: keep `HERE` and `T="$HERE/automate-trail.sh"` unchanged (the test also reads `$HERE/../skills/…`); add `TB` = `_trail_bundle`'s output in a temp file and point every `sed`/`awk` mutant source and `cmp -s` gate at it (a mutant written from the bundle is self-contained); every `cp "$HERE"/*.sh … ; cp -R "$HERE/automate-helpers.d" …` staging dir that runs the copied entry gets `cp -R "$HERE/automate-trail.d"` beside it. Every such hunk is a setup-only change listed in the evidence file. Also check the `H="$HERE/automate-helpers.sh"` uses: the helpers dispatcher `exec`s `$(dirname "$0")/automate-trail.sh`, so any staging dir holding the helpers must also hold a working `automate-trail.sh` (bundle or entry+`.d`). If the bundle cannot reproduce 782/782, STOP and report.
- **Keep in the trail runner (orchestrator amendment):** `test-automate-loop-split.sh` §H requires `test-automate-trail.sh` itself to contain `fixtures/automate-loop-split/assemble.sh` — keep `ASM="$HERE/fixtures/automate-loop-split/assemble.sh"` and its assemble calls in the runner's shared setup, not in a part.
- **New `test-automate-trail-modules.sh`:** AC6 against the real entry point.

### Subtask 3 — Integration (detail)
- Runs on the merged result of 1 and 2.
- AC7: extend the two scan arrays with `loomwright/scripts/test-*.d/*.sh` (under `shopt -s nullglob` where the file already uses it), plus one planted-violation leg each.
- AC8: widen W6d's input in `test-wave-build.sh` to the lanes entry + `automate-lanes.d/*.sh` — feed it the bundle (`_lanes_bundle | grep -nE …`) or add `-h`, because multi-file `grep -n` prefixes `file:N:` and the `^[0-9]+:[[:space:]]*#` comment filter would stop matching; widen the lanes-test check that greps `"$HERE/automate-trail.sh"` for `fleet-closeout|wave-plan` (now in a `test-automate-lanes.d/` part) to also read `automate-trail.d/*.sh`. Expected values unchanged.
- AC9: `bash scripts/check-vendor-coupling.sh` on the integrated tree (after `git add`); move each allowance to the new paths it now lands on (module files AND test parts), flat total unchanged; reason text per moved path as in AC9. Siblings in this wave may also edit this file — keep edits to the moved paths' own keys.
- Re-scan for any OTHER consumer that stages, copies, sources or greps either script alone: `git grep -nE 'automate-(lanes|trail)\.sh' -- 'loomwright/scripts/*.sh' 'scripts/*.sh' 'loomwright/scripts/adapters/*/*.sh'` (base set: `automate-wave.sh`, `guard-lane-wait-armed.sh`, `test-guard-lane-wait-armed.sh`, `test-wave-build.sh`, `test-automate-helpers.sh`, `test-automate-golden.sh`, `test-migrate-branch-mode.sh`, `test-verify-queue.sh`, `test-reconcile-jobs.sh`, `scripts/test-lanes-addon.sh`) and run each; a consumer that still breaks and is not in a lane here is STOP-and-report.
- AC11 running-system check: `git worktree add` a clean base at `142540b` (scratch, removed after), pick a real parent run file present in this checkout's `.supervisor/automate/` (e.g. `automate-2026-10-14-041009.md`), run `lane-status <rf>` and `lane-status <rf> --json` from base then branch, `diff` the outputs; repeat base twice to show any clock field.
- **Orchestrator amendments (Phase 2, Supervisor decision: apply AC7's rule):** (i) `test-no-fixed-sleep-race.sh` carries a per-file baseline row `3 loomwright/scripts/test-automate-lanes.sh` — after widening its scan, re-point that row to the file(s) now holding those sleeps (total unchanged, never raised); (ii) `test-automate-loop-split.sh` §H reads only the trail runner — widen its reads to also cover `loomwright/scripts/test-automate-trail.d/*.sh`, with one planted-violation leg, expected values unchanged; (iii) run `test-automate-loop-split.sh` in the AC10 consumer set.
- AC12 evidence file, AC14 changelog fragment, then `bash scripts/ci-local.sh` (wait with `bash scripts/ci-local.sh --wait`; exit 3 = still running) on base worktree and branch.

## Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/automate-lanes.d/create.sh"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.d/create.sh", name: "lanes_create"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "_lanes_bundle"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "lanes_main"}
  - {kind: "file", path: "loomwright/scripts/test-automate-lanes-modules.sh"}
requires: []
lanes:
  - "loomwright/scripts/automate-lanes.sh"
  - "loomwright/scripts/automate-lanes.d/**"
  - "loomwright/scripts/test-automate-lanes.sh"
  - "loomwright/scripts/test-automate-lanes.d/**"
  - "loomwright/scripts/test-automate-lanes-modules.sh"
external_requires: []

# Subtask 2
provides:
  - {kind: "file", path: "loomwright/scripts/automate-trail.d/sweep.sh"}
  - {kind: "symbol", path: "loomwright/scripts/automate-trail.d/sweep.sh", name: "sweep_run"}
  - {kind: "symbol", path: "loomwright/scripts/automate-trail.sh", name: "_trail_bundle"}
  - {kind: "file", path: "loomwright/scripts/test-automate-trail-modules.sh"}
requires: []
lanes:
  - "loomwright/scripts/automate-trail.sh"
  - "loomwright/scripts/automate-trail.d/**"
  - "loomwright/scripts/test-automate-trail.sh"
  - "loomwright/scripts/test-automate-trail.d/**"
  - "loomwright/scripts/test-automate-trail-modules.sh"
external_requires: []

# Subtask 3
provides:
  - {kind: "file", path: "docs/evidence/as19-split-lanes-and-trail-scripts.md"}
  - {kind: "file", path: "changelog.d/as19-split-lanes-and-trail-scripts.md"}
  - {kind: "symbol", path: "loomwright/scripts/test-no-pipefail-grep-q.sh", name: "loomwright/scripts/test-*.d/*.sh"}
  - {kind: "symbol", path: "loomwright/scripts/test-no-fixed-sleep-race.sh", name: "loomwright/scripts/test-*.d/*.sh"}
  - {kind: "symbol", path: "loomwright/scripts/test-wave-build.sh", name: "automate-lanes.d/*.sh"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "_lanes_bundle"}
  - {from: "2", kind: "symbol", path: "loomwright/scripts/automate-trail.sh", name: "_trail_bundle"}
lanes:
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "loomwright/scripts/test-no-pipefail-grep-q.sh"
  - "loomwright/scripts/test-no-fixed-sleep-race.sh"
  - "loomwright/scripts/test-wave-build.sh"
  - "loomwright/scripts/test-automate-loop-split.sh"
  - "loomwright/scripts/test-guard-lane-wait-armed.sh"
  - "loomwright/scripts/test-reconcile-jobs.sh"
  - "loomwright/scripts/test-automate-trail-modules.sh"
  - "loomwright/scripts/test-automate-lanes.d/**"
  - "docs/evidence/as19-split-lanes-and-trail-scripts.md"
  - "changelog.d/as19-split-lanes-and-trail-scripts.md"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──┐
            ├──→ Subtask 3
Subtask 2 ──┘
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none (lanes CALLS `automate-trail.sh sweep` through `$HERE`; it does not edit it) | NO |
| Subtask 1 | Subtask 3 | `loomwright/scripts/test-automate-lanes.d/**` (one check widened in AC8) | ordered by `requires` |
| Subtask 2 | Subtask 3 | none | ordered by `requires` |

### Batch Plan
- **Batch 1:** Subtask 1, Subtask 2 (parallel — empty `requires`, zero file overlap)
- **Batch 2:** Subtask 3 (after 1 and 2)
- **Recommended workers:** 2
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md` |
| 2 | `skills/unit-testing/SKILL.md` |
| 3 | `skills/ci-cd/SKILL.md`, `skills/unit-testing/SKILL.md` |

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

(Applied: AC13's module map is the one authority for "which module holds what"; it states no module or line count — counts live only in the evidence file as measurements.)

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): both test files mutate/stage the monolith text (`$MUT/automate-lanes.sh` mutants; `cp "$HERE"/*.sh` staging and `sed … "$HERE/automate-trail.sh"` mutants), so a split breaks them unless their TEXT reads use a single-file bundle | HIGH | Runs keep the real entry point (`S`/`T`, `HERE` unchanged — a symlinked bundle dir would move PLUGIN_ROOT and turn H1 red); only text reads go through a bundle variable (`SB`/`TB`); staging dirs that run the copied entry get the `.d` dir copied; assertion/mutation lines unchanged; the `*-modules.sh` tests prove the real entry. Base totals not reproduced ⇒ STOP and report |
| Moving test content into `test-*.d/` exempts it from gates that glob only `loomwright/scripts/test-*.sh` | HIGH | AC7 extends the two content scanners with a planted-violation leg each; `check-test-hermetic.sh` stays valid because the runner keeps the hermetic line |
| `automate-lanes.sh` is SOURCED by `automate-wave.sh` and the fail-SAFE `guard-lane-wait-armed.sh` Stop hook; a loader that `exit`s on a missing module would kill the guard with no `{}` | HIGH | AC1: sourced ⇒ `return 1`; the modules test proves the guard's `|| allow` and wave-build's refusal still fire; dir resolved from `${BASH_SOURCE[0]}`, never `$0` |
| `automate-trail.sh --help` greps the whole file and matches body comment lines; a thin entry point would drop them | MEDIUM | AC2: help greps the bundle; AC6 diffs it against the base blob |
| W6d-style "no executable git merge/push in automate-lanes.sh" checks silently weaken when the code moves to modules | MEDIUM | AC8 widens their input set; pin mutation row plants a push in a module |
| ~12,800 moved lines in one PR | MEDIUM | AC3 proves verbatim movement mechanically (bundle == base blob); every non-move hunk listed in the evidence file |
| `vendor-coupling-manifest.json` is also edited by sibling lanes of this wave | MEDIUM | Subtask 3 touches only the moved paths' own keys and reasons; wave-branch integration resolves line conflicts |
| Prose citing "the `<fn>` header in `scripts/automate-lanes.sh`" (`skills/automate-loop/lanes.md`, `per-item-loop.md`) no longer finds the text in that file | LOW | AC13 module map in the entry header; AC12 lists each citation; re-targeting the prose is a follow-up (those skill files are outside this item's lanes) |
| Requirement Touches omit the test-part dirs, the two `*-modules.sh` tests, the gate files and the manifest | LOW | Declared in this brief's lanes; all are new files or single-purpose gate edits; disclosed in the PR body |
| Base totals re-measured on a different machine/session differ (timing-sensitive legs) | LOW | Workers re-measure base on a clean `142540b` worktree in the same session as the branch run |

## Executable Acceptance
- corpus-task: version-consistent

## Phase 3 adjudication (owner: D — widen the writer's declared lane)
- Subtask 3's lane gains `test-guard-lane-wait-armed.sh` (E2 mutant dir also copies `automate-lanes.d`), `test-reconcile-jobs.sh` (11a reads the closeout text from `automate-trail.d/closeout.sh`) and `test-automate-trail-modules.sh` (`env LC_ALL=C sort` at its two `sort` sites, check-locale-prefix). Setup-only fixes; no assertion or expected value edited.
- AC9 deviation accepted: vendor-coupling flat total 2676 → 2677 (one new reference in `test-automate-lanes-modules.sh`, with its own reason); recorded in the evidence file.

## Configuration
- **Workers:** 2
- **Mode:** parallel
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** genuine-parallelism

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-16-split-lanes-and-trail-scripts.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-10-16T08:27:26Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/577
- **Branch:** feature/as19-split-lanes-and-trail-scripts
- **Files changed:** 43
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** 3 subtasks (lanes split, trail split, integration; subtask 3 re-queued once after owner adjudication D). Branch merged origin/main e232771 (PRs #572/#574 ported into modules; bundle == e232771 byte-for-byte). Phase 4.5: iteration 1 PASS+MEDIUM (stale evidence §2/§7) → fix 5d78274; iteration 2 PASS (LOW only). Lanes 889/889 (base 887 + 2 planted legs), trail 782/782, modules tests 56/56 + 24/24, required CI green, rules gate none, ground truth 1/1. children_check: skipped (owner). risk_classification high_risk=true (size/content heuristics; advisory).

## Not verified
- **Full ci-local on the merged tree** — last full run 184/185 on ef57b60 (W19 fails on a gitignored local file, reproduced identically on origin/main); 185/185 on pre-merge d588537 (subtask 3 / merge fix)
- **FINALIZE children-settled check** — skipped by owner decision; subtask 3's first worker (a4bed9348f481c61b) hit its turn limit without a result, its retry produced the committed work (subtask 3)
- **Prose pointers into moved functions** — skills/automate-loop lanes.md / per-item-loop.md and guard-lane-wait-armed.sh comments name automate-lanes.sh; resolve via the entry's module map; re-targeting is a follow-up (subtask 1)
