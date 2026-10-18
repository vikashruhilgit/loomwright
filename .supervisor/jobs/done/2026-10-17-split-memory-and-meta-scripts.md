# Supervisor Job: Split setup-memory.sh and meta-sync.sh into sourced modules (move-only)

## Environment
- **Project:** ai-agent-manager-lanes/automate-2026-10-15-163325/L13 (lane checkout; repo `vikashruhilgit/loomwright`)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 2 (branch mode ON — `.supervisor/` run history lives on the metadata branch; this is lane L13 of a 4-lane wave, so sibling lanes may edit `loomwright/docs/vendor-coupling-manifest.json` or `loomwright/scripts/fixtures/self-test-weights.tsv` in the same wave)
- **Source requirement:** .supervisor/requirements/automate-speed/20-split-memory-and-meta-scripts.md
- **Base commit:** a8819a38100d77fbeddc2ff1a56963e91f172a5d

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2-safe shell only; no new language or dependency |
| 2 | Dependency Availability | GO | none needed |
| 3 | Architecture Fit | CAUTION | The repo already has the convention three times (`automate-helpers.sh` + `automate-helpers.d/`, PR #408; `automate-lanes.d/` and `automate-trail.d/`, automate-speed/19, PR #577, brief `.supervisor/jobs/done/2026-10-16-split-lanes-and-trail-scripts.md`). That precedent found a split breaks every consumer that copies ONE script file into a staging dir or `sed`s the monolith into a mutant copy. Here: `test-setup-memory.sh` builds three `sed` mutants of `"$MEM"` (`sed '/^\*\/\*\*\/\.supervisor\/$/d' "$MEM" > "$Tm/setup-memory.sh"`, the `BMR_MUT` and `CS_MUT` legs); `test-meta-sync.sh` builds mutants with `sed -e "$2" "$SUT" > "$1/meta-sync.sh"` and copies `cp "$HERE/setup-memory.sh" "$1/"` beside each, plus `cp "$SUT" "$NORD/meta-sync.sh"` and the `MUT_XVI` leg; OTHER tests copy a single script too (`test-session-resume.sh` `cp "$sd/setup-memory.sh" "$mutd/setup-memory.sh"`, `test-migrate-branch-mode.sh` `cp "$STUBPUSH/meta-sync.sh" "$MUT/meta-sync.sh"`, stub dirs, `test-automate-helpers.sh` `cp "$HERE"/*.sh "$HERE"/*.py "$RSM/"`). Resolved below by the precedent's bundle technique and a consumer re-scan |
| 4 | Scope vs Supervisor Capability | CAUTION | ~4,150 script lines + ~5,470 test lines move; two file-disjoint groups (setup-memory, meta-sync) ⇒ split `genuine-parallelism`, plus one integration subtask for the shared consumers |
| 5 | Hard Blockers | GO | none |

**Overall Verdict:** CAUTION

## Task
**Goal:** Turn `loomwright/scripts/setup-memory.sh` and `loomwright/scripts/meta-sync.sh` into thin entry points that source one module per concern from `loomwright/scripts/setup-memory.d/` and `loomwright/scripts/meta-sync.d/`, split their two test files the same way, and keep every subcommand, flag, output byte, exit code and test assertion identical (owner decision D6: move-only).

**Problem Statement:**
The owner (and every parallel lane) needs memory and metadata-branch changes to touch small files, because today every such change edits the same 2,357-line `setup-memory.sh` or 1,789-line `meta-sync.sh` and their 2,720 / 2,745-line tests.
Currently, two lanes of one wave collide on these files and reviewers read far more than the change.
Success looks like: no module over ~800 lines, the same test totals before and after, byte-identical usage/help and `meta-sync.sh status` output.

## Acceptance Criteria
- [ ] AC1 — Given the split, when `setup-memory.sh <subcommand> …` is invoked (directly or by any caller: `meta-sync.sh`, `automate-helpers.d/meta.sh`, `automate-trail.d/trail-pr.sh`, `session-resume.sh`, `migrate-branch-mode.sh`, `meta-sync-rehearsal.sh`), then stdout, stderr and exit code equal base for every arm of its `case "$SUBCMD" in` table (`consent`, `mode`, `check`, `apply`, `remove`, `allowlist`, `filter-ledger`), the top-level `valid-branch <name>` predicate handled before the dispatch (an accepted name, a refused name, a missing name — its exit code is its answer), `--help`/`-h`, no arguments and an unknown subcommand. The entry point keeps the whole header comment (`usage` prints it with `awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"`, so the header must stay the first comment block of the ENTRY file), `set -uo pipefail`, the argument parsing and the final `case "$SUBCMD" in … esac`. Each module is sourced by name (never a glob), resolved from `"$(dirname "${BASH_SOURCE[0]}")/setup-memory.d/"`, at the position its code held in the monolith (top-level statements between functions stay in base order). A missing/unreadable module ⇒ non-zero exit with the message `setup-memory: missing module file: setup-memory.d/<name>.sh` on stderr.
- [ ] AC2 — Given the split, when `meta-sync.sh <subcommand> …` is invoked (directly, by `automate-trail.d/trail-pr.sh` through `${LOOMWRIGHT_META_SYNC_BIN:-$HERE/meta-sync.sh}`, by `meta-sync-rehearsal.sh`, `migrate-branch-mode.sh`, `automate-lanes.d/*`), then stdout, stderr and exit code equal base for every arm of its final `case "$SUBCMD" in` table (`init`, `pull`, `push`, `status`, `scrub`, `list-managed`), `--help`/`-h`, no arguments, an unknown subcommand and every `usage:` refusal of the argument parser. The entry keeps the header (same `usage` awk over `"${BASH_SOURCE[0]}"`), `set -uo pipefail`, `HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` (so `"$HERE/setup-memory.sh"` still resolves beside the ENTRY), the argument parser and root/branch resolution that run before any lock/fetch, and the final dispatch. A missing/unreadable module ⇒ non-zero exit with `meta-sync: missing module file: meta-sync.d/<name>.sh` on stderr, before any lock, fetch, or write to the repo or the metadata branch (a temp dir created by a moved top-level `WORK=$(mktemp -d …)` and removed by its EXIT trap is allowed).
- [ ] AC3 — Given each entry point, when its bundle function runs (`_sm_bundle` / `_ms_bundle`, self-contained functions a test can `eval`, shaped like `automate-helpers.sh`'s `_ah_bundle` and `automate-trail.sh`'s `_trail_bundle`), then the bundle with the loader definitions and the source-marker lines removed equals `git show a8819a3:<path>` byte-for-byte (proof the code moved verbatim). The only other permitted hunks are loader/bundle additions; each is listed in the evidence file.
- [ ] AC4 — Given `wc -l` over every new module, then no module exceeds 800 lines, and every module passes `bash -n` and runs under bash 3.2 with `set -u` (code moved, not rewritten; no bash-4-only syntax added).
- [ ] AC5 — Given `test-setup-memory.sh` and `test-meta-sync.sh`, when each runs on the branch, then it reports the same totals as base (`RESULT: <p> passed, <f> failed` and `test-meta-sync: <p> passed, <f> failed`, base re-measured on a clean `a8819a3` worktree in the same session), and each test file is a thin runner that keeps its header comment, its hermetic first executable line (`check-test-hermetic.sh` passes), its shared setup, pass/fail helpers and final summary, and sources its parts BY NAME (never a glob) from `loomwright/scripts/test-setup-memory.d/` / `loomwright/scripts/test-meta-sync.d/` in base order. No assertion line, expected value or mutation pattern (`sed`/`awk` expression) is edited. Every RUN keeps running the REAL entry point (`MEM`, `SUT`/`SCRIPT` and `HERE` unchanged — `HERE` is never re-pointed). The only non-move edits allowed are (a) a separate bundle variable (e.g. `MEMB` / `SUTB`, the bundle written once to a temp file) used for every TEXT read — the `sed` mutant sources, their `cmp -s` gates and static greps over the script text (e.g. test-meta-sync's item 19 "forbidden-forms grep over meta-sync.sh") — a mutant written from the bundle is self-contained, so it runs without a `.d` dir; (b) a staging dir that must run a REAL copied entry gaining `cp -R "$HERE/<script>.d"` beside the copied entry; (c) the parts loader. Every such hunk is listed in the evidence file with its reason. If the bundle cannot reproduce the base totals, STOP and report — never edit an assertion or mutation line.
- [ ] AC6 — Given a new `loomwright/scripts/test-setup-memory-modules.sh` (subtask 1) and `loomwright/scripts/test-meta-sync-modules.sh` (subtask 2), each modelled on `test-automate-trail-modules.sh`, when they run, then they exercise the REAL entry point (not the bundle): every `case` arm reaches its function (never the usage/unknown branch); `--help` and the no-arg/unknown output equal base's (from the `a8819a3` blob via `git show`, a named SKIP in a shallow clone); a stray file in the `.d` dir is not sourced; a copy with one module removed exits non-zero with the exact loader message; AC3's verbatim-move equality holds; and each mutant is gated on non-empty + differs + `bash -n`.
- [ ] AC7 — Given every OTHER consumer that copies, stubs, sources or greps either script alone (base set from `git grep -nE '(setup-memory|meta-sync)\.sh' -- 'loomwright/scripts/*.sh' 'loomwright/scripts/test-*.d/*.sh' 'scripts/*.sh'`, tests among them: `test-session-resume.sh`, `test-migrate-branch-mode.sh`, `test-meta-sync-rehearsal.sh`, `test-automate-helpers.sh`, `test-automate-lanes.sh` + parts, `test-automate-trail.d/04-watcher-branch-mode.sh`, `test-committed-twin-scrub.sh`, `test-guard-lane-wait-armed.sh`, `test-script-event-telemetry.sh`, `test-seed-rules.sh`, `test-validate-entry.sh`, `test-wave-build.sh`, `test-write-agent-memory.sh`, `scripts/check-locale-prefix.sh`, `scripts/test-check-locale-prefix.sh`) plus the gates `loomwright/scripts/test-citation-drift.sh` and `bash scripts/check-locale-prefix.sh` (over the whole tree, the new `*-modules.sh` tests included), when each runs on the integrated branch, then it reports the same totals as base, and `test-meta-sync.sh` / `test-setup-memory.sh` are re-run there and report their AC5 base totals (the MUT_XVI leg of `test-meta-sync.sh` seds `setup-memory.sh`, so its total is only meaningful on the integrated tree); a consumer that copies one entry file into a dir and RUNS it gains the `.d` copy beside it (setup-only hunk, evidence-listed); a consumer that READS the script text is fed the bundle or the entry + modules so its check is not weakened; no expected value is edited. A consumer that still breaks and is outside this brief's lanes is STOP-and-report.
- [ ] AC8 — Given `loomwright/docs/vendor-coupling-manifest.json`, when `bash scripts/check-vendor-coupling.sh` runs on the integrated branch (after `git add`), then it passes with the flat total unchanged: each allowance for `loomwright/scripts/setup-memory.sh` (54), `loomwright/scripts/test-setup-memory.sh` (108) and any for `meta-sync.sh` / `test-meta-sync.sh` is moved to the paths that now carry those references, with one `allowance_reasons` entry per moved path reading `moved by automate-speed/20 split — no reference added`.
- [ ] AC9 — Given the per-file baselines that name the two test files (`loomwright/scripts/fixtures/self-test-weights.tsv` rows `121	loomwright/scripts/test-meta-sync.sh` and `26	loomwright/scripts/test-setup-memory.sh`; any per-file row in `test-no-fixed-sleep-race.sh` or `test-no-pipefail-grep-q.sh` naming these files or their moved writer sites), when the gates run, then they pass: the runner basenames stay (so weights rows need no change unless a gate demands one), a baseline row whose counted lines moved into a part is re-pointed with its count unchanged (never raised), and `bash scripts/check-test-hermetic.sh` passes unchanged.
- [ ] AC10 — Given the invariants of the requirement, when the branch runs, then `meta-sync.sh`'s scrub rules and managed set are byte-identical in behaviour (`meta-sync.sh list-managed --root <this checkout>` and `meta-sync.sh scrub` over the same input print the same as base) and `bash loomwright/scripts/test-meta-sync-rehearsal.sh` and `bash loomwright/scripts/test-migrate-branch-mode.sh` pass with base totals; `meta-sync-rehearsal.sh` and `migrate-branch-mode.sh` themselves are byte-unchanged; `loomwright/hooks/hooks.json` and `loomwright/capabilities.json` are byte-unchanged.
- [ ] AC11 — Given the running system, when `meta-sync.sh status --branch <a throwaway branch name not on origin>` (and `meta-sync.sh status` with the checkout's own mode branch, `loomwright-meta`) runs from a clean base worktree at `a8819a3` and then from the branch, back to back on the same checkout input, then the outputs and exit codes are byte-identical (a field that also differs between two consecutive base runs — a clock or age — is shown to do so and named); likewise `setup-memory.sh --root <checkout> mode` and `setup-memory.sh --root <checkout> check`.
- [ ] AC12 — Given the integrated branch, then a committed evidence file `docs/evidence/as20-split-memory-and-meta-scripts.md` contains: the before/after `<passed>/<total>` for every test and gate in AC5–AC10 (and `bash scripts/ci-local.sh` totals for base and branch, every red leg shown red on base too); the final module list per script (module → functions → line count); every non-move hunk of AC3, AC5 and AC7 with its reason; the AC11 commands and both outputs pasted; and every committed citation of a function or comment block that moved (from `git grep` over `*.md` AND every pinned `<script>.sh:<N> [pins: …]` citation in `loomwright/scripts/*.sh`, `loomwright/scripts/test-*.d/*.sh` and `scripts/*.sh`), each judged resolvable through the entry point's module map (AC13) — and the PR body links to it.
- [ ] AC13 — Given each entry point's header, then it carries one `# Modules (sourced in this order from <script>.d/):` block naming each module and the subcommands/functions it holds, so a reader told "see the header in `scripts/meta-sync.sh`" (e.g. the `meta-sync.sh header: CONSENT` citations in `setup-memory.sh` and `meta-sync-rehearsal.sh`) still finds that text in the ENTRY header (the header itself never moves); no prose file outside this item's lanes is edited (pointer re-targeting, if wanted, is a follow-up).
- [ ] AC15 — Given the two line-pinned citations into `setup-memory.sh` that `loomwright/scripts/test-citation-drift.sh` verifies — `loomwright/scripts/test-committed-twin-scrub.sh` (`setup-memory.sh:1616 [pins: `Removal does NOT unpublish`]`, text in `print_consent_disclosure`, which moves to a module) and `loomwright/scripts/test-validate-entry.sh` (`setup-memory.sh:224 [pins: `robust to header edits`]`, text in the entry header, which AC13's `# Modules` block shifts) — and any further pinned citation into either script found by AC12's scan, when `bash loomwright/scripts/test-citation-drift.sh` runs on the integrated branch, then it passes: each citation is re-pointed to the file and line that now hold its pin text (`setup-memory.d/<module>.sh:<N> [pins: …]` or the shifted entry line), pin text unchanged; each new line number is re-derived by grepping the pin text in the integrated tree (not computed from the header growth). In `test-committed-twin-scrub.sh` the citation is a comment; in `test-validate-entry.sh` it is the cited line inside the `--entry "see CLAUDE.md and loomwright/scripts/setup-memory.sh:224"` argument of a `dead-reference` leg (pin in its trailing comment) — that leg's assertion must still pass unchanged. These citation edits are the only edits to those two files.
- [ ] AC14 — Given `changelog.d/as20-split-memory-and-meta-scripts.md`, then it exists in the `changelog.d/README.md` format with `<!-- bump: patch -->` as its first line, and `plugin.json`, `marketplace.json` and `CHANGELOG.md` are not hand-edited (`bash scripts/check-version-bump.sh` passes).

## Touched-file invariants

> Grounded at base `a8819a3`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/setup-memory.sh`** — keep: `set -uo pipefail` (not `-e`); the top-level `valid-branch` handling before the dispatch; the header block read by `usage` via `awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"` (stays the entry's first comment block, so `--help` is byte-identical with no bundle); the final dispatch `case "$SUBCMD" in` with arms `consent)       do_consent ;;` … `filter-ledger) do_filter_ledger ;;`; the top-level `CONSENT_FILE_REL` declaration (between `do_mode` and `consent_key`; vendor-coupling counts it) moves byte-unchanged with its neighbours into the module holding `consent_key`, at its base position; the `set -m` process-group leader in `gh_id_bounded` moves with its function byte-unchanged; reuse: the `_trail_source`/`_trail_bundle` shape from `automate-trail.sh` (`# Modules (sourced in this order from automate-trail.d/):`) for the loader and bundle; fired by: `meta-sync.sh` (`bash "$HERE/setup-memory.sh" --root "$ROOT" mode`, `… allowlist`, `… consent status`), `automate-helpers.d/meta.sh` (`bash "$here/setup-memory.sh" --root "$root" mode`), `automate-trail.d/trail-pr.sh` (`bash "$HERE/setup-memory.sh" --root "$1" mode`), `session-resume.sh` (`bash "$here/setup-memory.sh" --root "$root" mode`), `/setup memory` (`commands/setup.md`); pinned by: `test-setup-memory.sh` (`MEM` mutants `sed '/^\*\/\*\*\/\.supervisor\/$/d' "$MEM"`), `test-meta-sync.sh` (`cp "$HERE/setup-memory.sh" "$1/"`, the `MUT_XVI` `granted="$(meta_allowlist_grants "$own")"` mutant), `test-session-resume.sh` (`cp "$sd/setup-memory.sh" "$mutd/setup-memory.sh"`), `scripts/test-check-locale-prefix.sh` leg 6 (`grep -qF '! env LC_ALL=C tr -d' "$MEM"` and a `sed` of the entry into `$tmp/r/setup-memory.sh` — `gitignore_gate`'s text), `test-committed-twin-scrub.sh` (`setup-memory.sh:1616 [pins: `Removal does NOT unpublish`]`), `test-validate-entry.sh` (`setup-memory.sh:224 [pins: `robust to header edits`]`) — both checked by `test-citation-drift.sh`, `test-meta-sync.sh` MUT_XVI (`sed -e 's/^    granted="\$(meta_allowlist_grants "\$own")"$/…/' "$HERE/setup-memory.sh"` — `load_allowlist`'s text).
- **`loomwright/scripts/meta-sync.sh`** — keep: `set -uo pipefail`; `HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`; `say()  { printf 'meta_sync: %s\n' "$*"; }` / `die()  { warn "$*"; exit 1; }` output prefixes; the header (`usage` uses the same awk over `"${BASH_SOURCE[0]}"`; its `CONSENT` section is cited as "meta-sync.sh header: CONSENT"); the top-level argument parser and the `case "$SUBCMD" in scrub|list-managed) NEEDS_BRANCH=0 ;; esac` / `--allow-branch-mismatch` refusals that run before any lock, fetch or write ("nothing was changed"); the root resolution `# ---- resolve root (mirrors run-lock.sh's "resolve root" block) ----`; the dispatch `pull)   acquire_lock; cmd_pull ;;` / `push)   acquire_lock; cmd_push ;;` (lock before pull/push); scrub rules (`scan_file`, `email_matches`, `first_match_line`, `scrub_candidates`) and the managed set (`is_managed`, `is_twin_path`, `is_learning_path`) move byte-unchanged (a scrub regression publishes home paths to a PUBLIC branch); fired by: `automate-trail.d/trail-pr.sh` (`${LOOMWRIGHT_META_SYNC_BIN:-$HERE/meta-sync.sh}` push), `automate-lanes.d/*` (lane pushes and `status --paths`), `automate-helpers.d/meta.sh` (`meta-entry` pull), `meta-sync-rehearsal.sh`, `migrate-branch-mode.sh`; pinned by: `test-meta-sync.sh` (`SUT="$HERE/meta-sync.sh"`, the mutation-control helper `sed -e "$2" "$SUT" > "$1/meta-sync.sh"`, `cp "$SUT" "$NORD/meta-sync.sh"` for the missing-reader leg whose expected text is `setup-memory.sh (the mode-line reader) is missing beside meta-sync.sh`), `test-migrate-branch-mode.sh` (`cp "$STUBPUSH/meta-sync.sh" "$MUT/meta-sync.sh"`).
- **`loomwright/scripts/test-setup-memory.sh`** — keep: its hermetic first executable line (`check-test-hermetic.sh`'s `prefix='. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/'`); `HERE="$(cd "$(dirname "$0")" && pwd)"`; the final lines `echo "RESULT: $pass passed, $fail failed"` and `[ "$fail" -eq 0 ] || exit 1`; mutant gates `if cmp -s "$MEM" "$Tm/setup-memory.sh"`.
- **`loomwright/scripts/test-meta-sync.sh`** — keep: the hermetic first executable line; `SUT="$HERE/meta-sync.sh"` / `SCRIPT="$SUT"` running the real entry; the final line `echo "test-meta-sync: $pass passed, $fail failed"` and `[ "$fail" -eq 0 ]`; the mutation-control helper's three gates (`sed … || return 1`, `cmp -s "$SUT" "$1/meta-sync.sh" && return 1`, `grep -qF "$3" "$1/meta-sync.sh" || return 1`) — only its `sed` INPUT moves to the bundle.
- **Both test files** — keep their basenames (named in `fixtures/self-test-weights.tsv` and globbed by `run-self-tests.sh`); parts must NOT match `loomwright/scripts/test-*.sh`, hence the `test-<x>.d/` dirs (already scanned by `test-no-pipefail-grep-q.sh` `"$1"/loomwright/scripts/test-*.d/*.sh` and `test-no-fixed-sleep-race.sh` `loomwright/scripts/test-*.d/*.sh`).
- **Subtask 3's consumer tests** (`test-session-resume.sh`, `test-migrate-branch-mode.sh`, `test-meta-sync-rehearsal.sh`, `test-automate-helpers.sh`, `test-automate-trail.d/**`, `test-automate-lanes.d/**`, `test-committed-twin-scrub.sh`, `test-validate-entry.sh`, `scripts/test-check-locale-prefix.sh`) — keep: every assertion, expected value, mutation expression and final total line byte-unchanged, and every run of a script under test against the real entry; the ONLY permitted hunks are (a) `cp -R "<dir>/<script>.d" "<dest>/"` beside an existing single-file copy that is then RUN — e.g. beside `cp "$sd/setup-memory.sh" "$mutd/setup-memory.sh"` (`test-session-resume.sh`), `cp "$STUBPUSH/meta-sync.sh" "$MUT/meta-sync.sh"` (`test-migrate-branch-mode.sh`), and the staging globs `cp "$HERE"/*.sh "$HERE"/*.py "$RSM/"` (`test-automate-helpers.sh`, add `cp -R "$HERE/setup-memory.d" "$HERE/meta-sync.d" "$RSM/"`) and `cp "$SCRIPT_DIR"/*.sh` (`test-session-resume.sh`); (b) a text read re-pointed to the bundle (`scripts/test-check-locale-prefix.sh` leg 6); (c) AC15's cited line numbers. `test-citation-drift.sh`, `test-no-fixed-sleep-race.sh` and `test-no-pipefail-grep-q.sh` — keep their scan sets and floors; only a per-file baseline row whose counted lines moved is re-pointed, count unchanged (AC9).
- **`loomwright/docs/vendor-coupling-manifest.json`** — keep: flat total unchanged; `allowance_reasons` per path; `schema_version` and every other key byte-unchanged.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-setup-memory-modules.sh` — every `case` arm reaches its function | delete `  mode)          do_mode ;;` in `loomwright/scripts/setup-memory.sh` |
| `loomwright/scripts/test-meta-sync-modules.sh` — every `case` arm reaches its function | delete `  status) cmd_status ;;` in `loomwright/scripts/meta-sync.sh` |
| both `*-modules.sh` — direct run with a missing module exits non-zero with the loader's exact message `missing module file: <script>.d/<name>.sh` | replace the loader's missing-file branch with `:` in a scratch copy |
| both `*-modules.sh` — stray `.d` file not sourced | replace one by-name source line with a loop over `<script>.d/*.sh` in a scratch copy |
| both `*-modules.sh` — AC3 verbatim move | edit one moved line (e.g. append a space) in one module of a scratch copy |
| `loomwright/scripts/test-setup-memory-modules.sh` — `--help` equals base | flip `/^#/{sub(/^# ?/,""); print; next}` → `/^#/{sub(/^# ?/,"");  next}` in `usage` of a scratch copy of `setup-memory.sh` |
| `loomwright/scripts/test-meta-sync-modules.sh` — `--help` equals base | flip `/^#/{sub(/^# ?/,""); print; next}` → `/^#/{sub(/^# ?/,"");  next}` in `usage` of a scratch copy of `meta-sync.sh` |
| `loomwright/scripts/test-meta-sync-modules.sh` — missing module exits before any lock/write | move the meta-sync loader lines after the `case "$SUBCMD" in` dispatch in a scratch copy (a `pull` then fails differently or writes a lock) |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Split `setup-memory.sh` + its test into `setup-memory.d/` / `test-setup-memory.d/` | AC1, AC3, AC4, AC5, AC6, AC13 (setup-memory halves) | 2 modify, ~8 create | `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 2 | Split `meta-sync.sh` + its test into `meta-sync.d/` / `test-meta-sync.d/` | AC2, AC3, AC4, AC5, AC6, AC13 (meta-sync halves) | 2 modify, ~8 create | `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 3 | Integration: other consumers, citation pins, baselines, vendor manifest, running-system check, evidence, changelog; AC5 re-run on the integrated tree | AC5 (integrated re-run), AC7, AC8, AC9, AC10, AC11, AC12, AC14, AC15 | ~9 modify, 2 create | `skills/ci-cd/SKILL.md`, `skills/unit-testing/SKILL.md` | BLOCKED (by #1, #2) |

### Subtask 1 — setup-memory split (detail)
- **Gates during subtasks 1–2:** until subtask 3 moves the vendor-coupling allowances and fixes the other consumers, `check-vendor-coupling.sh` and `ci-local.sh` are expected red on a subtask-1/2 branch — workers 1 and 2 run their own test file and its `*-modules.sh` test; they never edit the manifest or another script's tests. Subtask 1 must NOT touch `meta-sync.sh` or `test-meta-sync.sh` (even though `test-meta-sync.sh` copies `setup-memory.sh`; that consumer is subtask 2's own test and is fixed there — see subtask 2).
- **Modules (proposed; the worker confirms against the real call graph and records the final list in AC13's map and the evidence file; ≤ 800 lines each, cut at function boundaries in base order):** `probes.sh` (the code between the argument parsing and `uncomment_bare_excludes`: `agent_memory_store_dir`, the top-level `INTENDED_PATHS` / `LEDGER_INTENDED_PATH` / `UNINTENDED_PATHS` globals, `ignore_status`, `tracked_count`, `gitignore_gate`, `managed_block_present`, `strip_managed_block`, `comment_bare_excludes` — the worker may instead keep them in the entry at their base position if the entry stays ≤ 800 lines; record which), `detect.sh` (block/mode reading and branch resolution — `uncomment_bare_excludes` … `resolve_effective_branch`), `gitignore.sh` (`proposed_applied_content` … `write_gitignore`, remote parsing `parse_remote_url` … `remote_slug`), `allowlist.sh` (`allowlist_gh_limit` … `filter_ledger_by_allowlist`), `ledger-gate.sh` (`_evaluate_ledger_gate` … `ledger_negation_in_block`), `report.sh` (consent disclosures, `render_report`, `print_path_rules`, readiness — `print_consent_disclosure` … `warn_if_not_configured`), `commands.sh` (`do_check` … `do_consent`; split as `apply.sh` + `commands.sh` if > 800). STAYS in the entry point: the header, `set -uo pipefail`, globals and argument parsing that run at top level before the first function (unless they sit between functions — then they move with their neighbours at the same position), the loader and bundle, the final `case "$SUBCMD" in` dispatch.
- **Loader:** one source line per module between `# >>> setup-memory.d/<name>.sh` / `# <<< setup-memory.d/<name>.sh` markers, at the module's base position. Dir from the entry's `${BASH_SOURCE[0]}`. Missing/unreadable ⇒ the AC1 message and non-zero exit. Never a glob.
- **Bundle:** `_sm_bundle [<entry>]` prints the entry with each source line replaced by that module's text (self-contained so a test can `eval` it).
- **Test split:** `test-setup-memory.sh` keeps lines up to its shared setup (hermetic line, `HERE`, `MEM`, helpers, counters) and the final summary; the body moves verbatim, in order, into named parts under `loomwright/scripts/test-setup-memory.d/` (≤ ~800 lines each, cut between test legs, never inside one), sourced by name. Add `MEMB` = the bundle in a temp file and re-point EVERY text read of the script to it: every `sed`/`awk`/`grep`/`cmp` whose input is `"$MEM"` (find them with `grep -nE '(sed|awk|grep|cmp)[^|]*"\$MEM"'` over the test, excluding `bash "$MEM"` runs — about 20 sites at base, including the MA_SUT mutant helpers, the `do_consent` awk, the bm-f/bm-l legs, the fn, vb, am and cs mutants and their `cmp -s "$MEM" …` gates). Runs (`bash "$MEM" …`) keep the real entry.
- **New `test-setup-memory-modules.sh`:** AC6 against the REAL entry. Use `env LC_ALL=C <cmd>` (never `LC_ALL=C <cmd>` at command position) and run `bash scripts/check-locale-prefix.sh` before hand-back (as19's evidence §8 fix 3).

### Subtask 2 — meta-sync split (detail)
- **Modules (proposed; confirm and record):** `lock.sh` (`g` … `acquire_lock`), `managed.sh` (`is_managed` … `list_history`: managed set, symlink and containment checks, remote probe/fetch, listings), `plan.sh` (`load_base` … `write_base_file`: 3-way plan, classify, conflict reports, merges, base file), `scrub.sh` (`load_allowlist` … `scrub_candidates`), `learning-twin.sh` (`read_consent` … `twin_gate`), `commands.sh` (`build_pull_base` … `cmd_list_managed`; split as `pull-push.sh` + `status-scrub.sh` if > 800). STAYS in the entry point: the header, `set -uo pipefail`, `HERE`, `say`/`warn`/`die`/`usage`/`need_val`, the argument parser, root/branch resolution and `read_branch_mode` call sites that run at top level (if `read_branch_mode()` is defined between top-level statements, keep it in the entry at its base position), the loader, the bundle, the final dispatch. Top-level code that sits between function definitions keeps its base position (move-only); the loader runs before the first lock/fetch/write so a missing module refuses with nothing changed (AC2).
- **Loader/bundle:** same shape as subtask 1 (`_ms_source`, `_ms_bundle`), markers `# >>> meta-sync.d/<name>.sh`.
- **Test split:** as subtask 1 (`test-meta-sync.d/`). Keep `SUT="$HERE/meta-sync.sh"` for every RUN; add `SUTB` = the bundle and point the mutation-control helper's `sed -e "$2"` INPUT and its `cmp -s`/`grep -qF` gates and the static forbidden-forms grep (item 19 in the header) at it — find every text read with `grep -nE '(sed|awk|grep|cmp)[^|]*"\$(SUT|SCRIPT)"'`, excluding runs. The `MUT_XVI` leg is NOT subtask 2's: its `sed` input is `"$HERE/setup-memory.sh"` (the `load_allowlist` text subtask 1 moves), so subtask 3 fixes it on the integrated tree; worker 2 leaves that leg byte-unchanged. The mutation-control helper's `cp "$HERE/setup-memory.sh" "$1/"` copies the SIBLING entry that a bundle mutant calls through `"$HERE/setup-memory.sh"` — after subtask 1 that entry needs its `.d`: add `cp -R "$HERE/setup-memory.d" "$1/"` beside it. `cp "$SUT" "$NORD/meta-sync.sh"` (the missing-reader leg, expected `setup-memory.sh (the mode-line reader) is missing beside meta-sync.sh`): `read_branch_mode` dies before the first module would load if modules load at base positions, so test the plain copy first and add a hunk (copy the bundle or `meta-sync.d`) only if the leg's output actually changes; record the outcome, and record in the evidence file that top-level statements moved into a module (e.g. `WORK=$(mktemp -d …)` and the traps) run before later modules load. Every such hunk is setup-only and evidence-listed. If the bundle cannot reproduce the base total, STOP and report.
- **Ordering with subtask 1:** subtask 2's test copies `setup-memory.sh`; on a subtask-2-only branch (setup-memory not yet split) the `cp -R "$HERE/setup-memory.d"` line must not fail the leg — guard it (`[ -d "$HERE/setup-memory.d" ] && cp -R …`) or let subtask 3 add it. Worker 2 records which.
- **New `test-meta-sync-modules.sh`:** AC6 against the real entry. Same `env LC_ALL=C` rule and `check-locale-prefix.sh` run as subtask 1.

### Subtask 3 — Integration (detail)
- Runs on the merged result of 1 and 2.
- **Known breaks to fix (Plan Review attempt 1):** (i) `test-meta-sync.sh` MUT_XVI (now in a `test-meta-sync.d/` part): source its `setup-memory.sh` mutant from `_sm_bundle`'s output (sed expression unchanged), re-point its `cmp -s`/`grep -qF` gate to that source, and `cp -R "$HERE/meta-sync.d"` beside its copy of the real `meta-sync.sh`; then re-run both test files for AC5's totals. (ii) `scripts/test-check-locale-prefix.sh` leg 6: feed its `grep -qF` and `sed` the `_sm_bundle` output (or the module holding `gitignore_gate`); the expected `OFFENDER setup-memory.sh:` text unchanged — if the offender line now names the module path, STOP and report rather than editing an expected value. (iii) AC15's two citation re-points.
- AC7: re-run `git grep -nE '(setup-memory|meta-sync)\.sh' -- 'loomwright/scripts/*.sh' 'loomwright/scripts/test-*.d/*.sh' 'scripts/*.sh'` and run every listed consumer test on base (clean `a8819a3` worktree) and branch; fix setup-only staging (`cp -R "$HERE/<script>.d"` beside a copied runnable entry; stub dirs in `test-migrate-branch-mode.sh` / `test-session-resume.sh`) and text reads; expected values unchanged.
- AC8: `bash scripts/check-vendor-coupling.sh` on the integrated tree (after `git add`); move each allowance to the new paths it now lands on (modules AND test parts), flat total unchanged, reason text per AC8. Siblings in this wave may also edit this file — keep edits to the moved paths' own keys.
- AC9: run `test-no-fixed-sleep-race.sh`, `test-no-pipefail-grep-q.sh`, `check-test-hermetic.sh`, `scripts/check-locale-prefix.sh` and the self-test-weights check (whatever `run-self-tests.sh` / CI uses); re-point a per-file baseline row whose lines moved, count unchanged.
- AC10/AC11 running-system checks: `git worktree add` a clean base at `a8819a3` (scratch, removed after), run each command from base then branch against THIS checkout (`--root <this checkout>`), `diff` the outputs, repeat base twice to show any clock field.
- AC12 evidence file, AC14 changelog fragment, then `bash scripts/ci-local.sh` (wait with `bash scripts/ci-local.sh --wait`; exit 3 = still running) on base worktree and branch.

## Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/setup-memory.d/allowlist.sh"}
  - {kind: "symbol", path: "loomwright/scripts/setup-memory.d/allowlist.sh", name: "filter_ledger_by_allowlist"}
  - {kind: "symbol", path: "loomwright/scripts/setup-memory.sh", name: "_sm_bundle"}
  - {kind: "symbol", path: "loomwright/scripts/setup-memory.sh", name: "# Modules (sourced in this order from setup-memory.d/):"}
  - {kind: "file", path: "loomwright/scripts/test-setup-memory-modules.sh"}
requires: []
lanes:
  - "loomwright/scripts/setup-memory.sh"
  - "loomwright/scripts/setup-memory.d/**"
  - "loomwright/scripts/test-setup-memory.sh"
  - "loomwright/scripts/test-setup-memory.d/**"
  - "loomwright/scripts/test-setup-memory-modules.sh"
external_requires: []

# Subtask 2
provides:
  - {kind: "file", path: "loomwright/scripts/meta-sync.d/scrub.sh"}
  - {kind: "symbol", path: "loomwright/scripts/meta-sync.d/scrub.sh", name: "scan_file"}
  - {kind: "symbol", path: "loomwright/scripts/meta-sync.sh", name: "_ms_bundle"}
  - {kind: "symbol", path: "loomwright/scripts/meta-sync.sh", name: "# Modules (sourced in this order from meta-sync.d/):"}
  - {kind: "file", path: "loomwright/scripts/test-meta-sync-modules.sh"}
requires: []
lanes:
  - "loomwright/scripts/meta-sync.sh"
  - "loomwright/scripts/meta-sync.d/**"
  - "loomwright/scripts/test-meta-sync.sh"
  - "loomwright/scripts/test-meta-sync.d/**"
  - "loomwright/scripts/test-meta-sync-modules.sh"
external_requires: []

# Subtask 3
provides:
  - {kind: "file", path: "docs/evidence/as20-split-memory-and-meta-scripts.md"}
  - {kind: "file", path: "changelog.d/as20-split-memory-and-meta-scripts.md"}
  - {kind: "symbol", path: "changelog.d/as20-split-memory-and-meta-scripts.md", name: "<!-- bump: patch -->"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/setup-memory.sh", name: "_sm_bundle"}
  - {from: "2", kind: "symbol", path: "loomwright/scripts/meta-sync.sh", name: "_ms_bundle"}
lanes:
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "loomwright/scripts/test-session-resume.sh"
  - "loomwright/scripts/test-migrate-branch-mode.sh"
  - "loomwright/scripts/test-meta-sync-rehearsal.sh"
  - "loomwright/scripts/test-automate-helpers.sh"
  - "loomwright/scripts/test-automate-lanes.d/**"
  - "loomwright/scripts/test-automate-trail.d/**"
  - "loomwright/scripts/test-no-fixed-sleep-race.sh"
  - "loomwright/scripts/test-no-pipefail-grep-q.sh"
  - "loomwright/scripts/fixtures/self-test-weights.tsv"
  - "loomwright/scripts/test-committed-twin-scrub.sh"
  - "loomwright/scripts/test-validate-entry.sh"
  - "scripts/test-check-locale-prefix.sh"
  - "loomwright/scripts/test-meta-sync.d/**"
  - "loomwright/scripts/test-setup-memory.d/**"
  - "docs/evidence/as20-split-memory-and-meta-scripts.md"
  - "changelog.d/as20-split-memory-and-meta-scripts.md"
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
| Subtask 1 | Subtask 2 | none (`meta-sync.sh` CALLS `setup-memory.sh` through `$HERE`, and `test-meta-sync.sh` copies it; neither subtask edits the other's files) | NO |
| Subtask 1 | Subtask 3 | `loomwright/scripts/test-setup-memory.d/**` (only if a consumer fix lands there) | ordered by `requires` |
| Subtask 2 | Subtask 3 | `loomwright/scripts/test-meta-sync.d/**` (the MUT_XVI fix, and the guarded `setup-memory.d` copy if worker 2 left it to subtask 3) | ordered by `requires` |

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
| Feasibility (Phase 2.5): both test files and several OTHER tests copy a single script file or `sed` it into a mutant, so a split breaks them unless their TEXT reads use a single-file bundle and runnable copies carry the `.d` dir | HIGH | Runs keep the real entry (`MEM`/`SUT`, `HERE` unchanged); only text reads go through a bundle variable; staging dirs that run a copied entry get the `.d` dir; assertion/mutation lines unchanged; the `*-modules.sh` tests prove the real entry; subtask 3 re-scans and runs every consumer (AC7). Base totals not reproduced ⇒ STOP and report |
| A scrub-rule or managed-set regression in `meta-sync.sh` publishes home paths to the PUBLIC metadata branch | HIGH | AC3 proves the bundle equals the base blob byte-for-byte; AC10 diffs `list-managed` / `scrub` output and runs `test-meta-sync-rehearsal.sh` / `test-migrate-branch-mode.sh` |
| `meta-sync.sh` has top-level code (argument parser, root/branch resolution, `LOCK_WAIT` check) interleaved with function definitions; moving it out of order changes behaviour, and a loader placed after `acquire_lock` could leave a lock on a missing module | MEDIUM | Modules sourced at their base positions (AC3 equality proves order); AC2 + pin mutation require the missing-module refusal before any lock/fetch/write |
| `usage` prints the header from `"${BASH_SOURCE[0]}"` — a module that ends up first, or a header split, would change `--help` | MEDIUM | Header stays in the entry; AC6 diffs `--help` against the base blob |
| Prior churn (postmortem ledger): touched paths carry 19 prior churn rounds across 13 entries, recurring classes `drain_churn` and `self_heal_churn`, with a `self_heal_miss` | HIGH | Verbatim-move proof (AC3) and full before/after totals (AC5, AC7) make review mechanical; every non-move hunk evidence-listed |
| `vendor-coupling-manifest.json` / `self-test-weights.tsv` are also edited by sibling lanes of this wave | MEDIUM | Subtask 3 touches only the moved paths' own keys/rows; wave-branch integration resolves line conflicts |
| Line-pinned citations into `setup-memory.sh` (`test-committed-twin-scrub.sh`, `test-validate-entry.sh`) go red in `test-citation-drift.sh` once code moves or the header grows | MEDIUM | AC15 re-points them in subtask 3; AC12's scan covers pinned `.sh` citations |
| Prose citing "meta-sync.sh header: CONSENT" and function names in `setup-memory.sh` / `meta-sync.sh` | LOW | The header stays in the entry; AC13 module map; AC12 lists each citation |
| Requirement Touches omit the test-part dirs, the two `*-modules.sh` tests, the consumer tests and the manifest | LOW | Declared in this brief's lanes; setup-only edits; disclosed in the PR body |
| Base totals re-measured in a different session differ (timing-sensitive legs) | LOW | Workers re-measure base on a clean `a8819a3` worktree in the same session as the branch run |

## Executable Acceptance
- corpus-task: version-consistent

## Phase 2 amendment (Orchestrator, Supervisor decision: apply)
- **`apply_readiness_event` stays in the `setup-memory.sh` entry** at its base position (with its comment block), between two module source lines: it resolves `emit-script-event.sh` via `"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/emit-script-event.sh"`, so inside `setup-memory.d/` it would silently stop emitting (the call is `>/dev/null 2>&1 || true`). `report.sh` ends just before it; `warn_if_not_configured` starts the next module (or its own small one). Record it in the AC13 map and the evidence file. Worker 1 also runs `bash loomwright/scripts/test-script-event-telemetry.sh` (S6 asserts the event) before hand-back. No other function in either script uses `BASH_SOURCE`, `$0` or `FUNCNAME` (`meta-sync.sh` resolves via the entry's `HERE`).
- File estimates corrected: subtasks 1 and 2 create ~11–12 files each (modules + test parts + `*-modules.sh`); scope unchanged.

## Configuration
- **Workers:** 2
- **Mode:** parallel
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** genuine-parallelism

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-17-split-memory-and-meta-scripts.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-10-18T05:56:03Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/598
- **Branch:** feature/as20-split-memory-and-meta-scripts
- **Files changed:** 43
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** 3 subtasks (setup-memory split, meta-sync split, integration; subtask 3's first worker hit its turn limit before a rate-limit session end — its replacement committed 66eada1). Bundles == base a8819a3 byte-for-byte; test-setup-memory 574/574, test-meta-sync 358/358, every consumer = base. Phase 4.5: iteration 1 PASS+MEDIUM (stale header audit recipe) → fix 81eb45a (comment-only); iteration 2 PASS (pre_existing MEDIUM + LOWs dismissed). CI green, rules gate none, ground truth 1/1. children_check: skipped (owner). risk_classification high_risk=true (size/content heuristics; advisory).

## Not verified
- **full green bash scripts/ci-local.sh on the branch** — test-automate-trail.sh exceeds the 900s per-test watchdog under shared-machine load (base also red); passes 786/786 alone (subtask 3)
- **FINALIZE children-settled check** — skipped by owner decision; the first subtask-3 worker (ab9d99fa84cda0b3c) hit its turn limit with no terminal lifecycle row; its replacement committed the work (subtask 3)
