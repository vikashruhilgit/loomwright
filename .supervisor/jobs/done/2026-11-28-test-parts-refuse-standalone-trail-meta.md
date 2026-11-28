# Supervisor Job: Trail and meta-sync test parts refuse to run standalone, and their fixture `cd` groups stop when the `cd` fails

## Environment
- **Project:** ~/orca/workspaces/ai-agent-manager/dolphin
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: vikashruhilgit/split-test-part-files
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 2 (source requirement is gitignored, so its provenance is unverified; this checkout is 2 commits behind `origin/main`, neither touching the File Impact Map — `git diff --stat 9a6a850 origin/main -- <the map's paths>` is empty)
- **Source requirement:** .supervisor/requirements/2026-11-28-092429-test-parts-refuse-to-run-standalone-and-never-touch-the-real-checkout.md
- **Base commit:** 9a6a850ee5d07ebde56fedfada437ae86b4d509d

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash test scripts, the existing stack |
| 2 | Dependency Availability | GO | no new dependency; reuses the lanes-part guard idiom and the `( cd "$P" \|\| exit 1` idiom already in `test-automate-trail.d/04-watcher-branch-mode.sh` |
| 3 | Architecture Fit | GO | parts stay sourced by name by their runner; the guard is a no-op under the runner |
| 4 | Scope vs Supervisor Capability | GO | 15 files but ~60 changed lines, all mechanical; one worker |
| 5 | Hard Blockers | CAUTION | needs one file outside the requirement's Touches: `docs/evidence/test-parts-standalone-guard.md` (Validation 2's committed evidence) — asked once at Phase 6 (`LP-SCOPE`) |

**Overall Verdict:** CAUTION

## Task
**Goal:** Every tracked part under `loomwright/scripts/test-automate-trail.d/` and `loomwright/scripts/test-meta-sync.d/` exits non-zero, naming its parent runner, before running any command when it is run on its own; and every fixture `cd` group in those parts stops when its `cd` fails.

**Problem Statement:**
The owner, whose `/automate` runs keep their only resume state in `.supervisor/automate/`, needs these test parts to be harmless when run the wrong way, because on 2026-11-28 a worker ran `bash loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh` from the live checkout (GitHub issue #994).
Currently, a part run alone has an empty `$P`; `( cd "$P" && git checkout -q -- README; rm -f stray.txt; rm -f "$AUTD"/*.md )` runs its `rm` in the caller's directory because `;` does not stop after a failed `cd`. That deleted the live run file and 449 run-history files.
Success looks like: the same command, run from a scratch checkout holding a sentinel `.supervisor/automate/sentinel-run.md`, exits non-zero naming `test-automate-trail.sh` and leaves the sentinel in place; a suite leg pins it; both suites still run every part and every existing leg still passes.

**Guard form (decision, owner allowed either):** the lanes-part form, for both runners — `declare -F <runner function> >/dev/null && [ -n "${<runner dir>:-}" ] && [ -d "$<runner dir>" ] || { echo "…: run via <runner>, never standalone …" >&2; exit 2; }`. The `--part` re-exec form is not used: neither `test-automate-trail.sh` nor `test-meta-sync.sh` accepts `--part` (trail's arguments are parsed by `part-groups-lib.sh`'s `pg_select`, which takes only `--group <g>` / `--all`), so adding it would change `part-groups-lib.sh`, outside this item's Touches and a non-goal ("how `scripts/ci-local.sh` picks suites" stays as is).

## Acceptance Criteria
- [ ] **AC1 (standalone refusal).** Given any tracked part under `loomwright/scripts/test-automate-trail.d/` (`00-shared.sh` and `01`–`06`) or `loomwright/scripts/test-meta-sync.d/` (`01`–`04`), when it is run directly with `bash <part>` from a checkout, then it exits non-zero (exit 2) with one stderr line `<part file name>: run via test-automate-trail.sh, never standalone (its fixtures need the suite's $TOP)` (trail) or `<part file name>: run via test-meta-sync.sh, never standalone (its fixtures need the suite's $TROOT)` (meta-sync), before it runs any command. The guard is the part's first command, placed within the file's first 15 lines (after its leading comment block), exactly:
  - trail parts: `declare -F tat_part >/dev/null && [ -n "${TOP:-}" ] && [ -d "$TOP" ] || { echo "${BASH_SOURCE[0]##*/}: run via test-automate-trail.sh, never standalone (its fixtures need the suite's \$TOP)" >&2; exit 2; }`
  - meta-sync parts: `declare -F tms_part >/dev/null && [ -n "${TROOT:-}" ] && [ -d "$TROOT" ] || { echo "${BASH_SOURCE[0]##*/}: run via test-meta-sync.sh, never standalone (its fixtures need the suite's \$TROOT)" >&2; exit 2; }`
- [ ] **AC2 (suites unchanged).** Given `test-automate-trail.sh` (every pool group: no argument, `--group 2`, `--group 3`, and `--all`) and `test-meta-sync.sh`, when they run their parts as today, then every part is still sourced (trail's `[ "$TAT_DONE" = "$PG_SEL" ]` check stays green), every leg that passed at base still passes with the same `ok:` text, and the only new `ok:`/`FAIL:` lines are the AC3/AC4 legs below.
- [ ] **AC3 (every `cd` group guarded).** Given a fixture step of the form `( cd "$X" && a; b; c )`, `$( cd "$X" && a; b )`, or a multi-line `( cd "$X"` ⏎ `a` ⏎ `b )` in any part of those two runners, when `$X` is empty or not a directory, then none of `a`, `b`, `c` runs: each such group's first command becomes `cd "$X" || exit 1` (the idiom `( cd "$P" || exit 1` already in `04-watcher-branch-mode.sh`), the rest of the group byte-identical. The base inventory (all must be converted; a fully `&&`-chained group with no `;` and no line break after the `cd`, e.g. `(cd "$P" && bash "$H" trail-pr …)`, is already safe and stays):
  - `test-automate-trail.d/00-shared.sh` — the three multi-line `( cd "$P"` groups in `new_fixture()`, `closeout_fixture()` and `bm_switch()`
  - `test-automate-trail.d/01-sidecar-trail-pr.sh` — `case "$(cd "$P" && bash "$H" trail-unstage "$RF_REL0" >/dev/null; git -C "$P" diff --cached --name-only)" in`
  - `test-automate-trail.d/02-closeout.sh` — the two multi-line `( cd "$P"` groups that rewrite `## Current` with `awk -v L="$LATER"`, the group `( cd "$P" && git pull -q --ff-only origin main 2>/dev/null; mkdir -p stories`, and the multi-line `( cd "$P"` group that writes `stories/04-z.md`
  - `test-automate-trail.d/05-finalize-closeout-others.sh` — `( cd "$P" && git checkout -q -- README; rm -f stray.txt; rm -f "$AUTD"/*.md )`
  - `test-meta-sync.d/02-guards-mode-base.sh` — `(cd "$W/B" && find .supervisor -type f` and `(cd "$W/$1" && bash "$HERE/setup-memory.sh" --root "$W/$1" apply --branch-mode "$2" >/dev/null 2>&1; rm -f .gitignore.backup.*)`
  - `test-meta-sync.d/03-mutants-scrub-allowlist.sh` — `(cd "$W/M" && bash "$HERE/setup-memory.sh" --root "$W/M" apply --branch-mode team-meta >/dev/null 2>&1; rm -f .gitignore.backup.*)`

  Each runner gains one static leg that scans its own parts (trail: `00-shared` plus every `$TAT_PARTS` entry; meta-sync: its four `tms_part` names — by name, never a glob) and fails, naming `file:line`, on any line where a `(`/`$(` subshell opens with `cd "…"` that is followed either by end of line or by `&&` with a `;` before the group's closing `)` on that line.
- [ ] **AC4 (the incident replayed, pinned).** Given a scratch checkout (a `git init` dir under the suite's own temp root, never the real checkout) holding `.supervisor/automate/sentinel-run.md` and `.supervisor/automate/sentinel.next-step.json`, when each of the runner's parts is run from it with `bash <part>` (cwd = the scratch checkout, `env -u TOP -u P -u FX` for trail, `env -u TROOT -u W` for meta-sync, stdin `</dev/null`), then each exits non-zero, its stderr carries the AC1 line naming its runner, and both sentinel files are still there. In `test-automate-trail.sh` these legs run in group 1 and `--all` only (gated `pg_want 01-sidecar-trail-pr`), so the pool runs them once and a plain `bash test-automate-trail.sh` runs them; `05-finalize-closeout-others.sh` is among them. `test-meta-sync.sh` runs the same legs for its four parts.
- [ ] **AC5 (Validation 2 evidence).** Given a scratch clone of the branch (`git clone` into `mktemp -d`, never the real checkout's `.supervisor/`) holding a sentinel `.supervisor/automate/sentinel-run.md`, when `bash loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh` is run from it, then a committed evidence file `docs/evidence/test-parts-standalone-guard.md` contains the exact commands, the exit code, the stderr line naming `test-automate-trail.sh` and an `ls .supervisor/automate/` showing the sentinel still present, plus the declared line `Verdict: PASS for Validation 2` at column 0 outside any fence; and the PR body links to it.
- [ ] **AC6 (release fragment).** A `changelog.d/test-parts-refuse-standalone.md` fragment (`<!-- bump: patch -->`) describes the change in prose; no version file is hand-edited, and `bash scripts/check-version-bump.sh` passes. The fragment cites no bare `file:line` (`test-citation-drift.sh`).

## Scope widening
- docs/evidence/test-parts-standalone-guard.md
- accepted: LP-SCOPE 2026-11-28

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

(Applied here: the AC3/AC4 legs read each runner's own part list — `$TAT_PARTS`, the `tms_part` names — rather than restating a second copy; the changelog fragment and evidence file name no suite pass count.)

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| trail parts | `loomwright/scripts/test-automate-trail.d/00-shared.sh` (159), `loomwright/scripts/test-automate-trail.d/01-sidecar-trail-pr.sh` (529), `loomwright/scripts/test-automate-trail.d/02-closeout.sh` (479), `loomwright/scripts/test-automate-trail.d/03-stamps-gate.sh` (475), `loomwright/scripts/test-automate-trail.d/04-watcher-branch-mode.sh` (885), `loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh` (946), `loomwright/scripts/test-automate-trail.d/06-sweep.sh` (477) | — | HIGH |
| meta-sync parts | `loomwright/scripts/test-meta-sync.d/01-sync-core.sh` (699), `loomwright/scripts/test-meta-sync.d/02-guards-mode-base.sh` (706), `loomwright/scripts/test-meta-sync.d/03-mutants-scrub-allowlist.sh` (775), `loomwright/scripts/test-meta-sync.d/04-learning-stores.sh` (538) | — | HIGH |
| runners | `loomwright/scripts/test-automate-trail.sh` (369), `loomwright/scripts/test-meta-sync.sh` (355) | — | HIGH |
| release + evidence | — | `changelog.d/test-parts-refuse-standalone.md`, `docs/evidence/test-parts-standalone-guard.md` | HIGH |

**Module layout (one home per new responsibility):**
- The standalone guard → each part's own first command, appended in place in every part including those at or past 500 lines (`01`, `04`, `05`, `01-sync-core`, `02-guards`, `03-mutants`, `04-learning`) — reason: the guard must run before anything the part sources or defines, so it cannot live in a shared helper the part would first have to locate and source; it is one line, the form the lanes parts already carry inline.
- The cd-group fixes → in place, the line that already holds each group (an edit of an existing line, no new responsibility).
- The AC3 static scan and AC4 standalone/sentinel legs → each runner (`test-automate-trail.sh` 369, `test-meta-sync.sh` 355, both under 500), next to the `tat_part`/`tms_part` source lines whose part lists they read.
- No helper is copied by 2+ siblings that this change needs; no extract row.

**Total estimated files:** 13 modify + 2 create

## Touched-file invariants

> Grounded at base `9a6a850ee5d07ebde56fedfada437ae86b4d509d`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/test-automate-trail.sh`** — keep: the part loader and its closed check, `tat_part() {` and `[ "$TAT_DONE" = "$PG_SEL" ] || no`; the hermetic first source, `. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"` (`scripts/check-test-hermetic.sh` fails CI without it); the temp root, `TOP="$(cd "$TOP" && pwd -P)"`, and its `trap cleanup_all EXIT` — the scratch checkout for AC4 lives under `$TOP`; the group map `TAT_GROUPS=` and `pg_select "$HERE/test-automate-trail.sh"` unchanged (no new part, no new argument). reuse: `ok`/`no` for the new legs; `pg_want 01-sidecar-trail-pr` to run them in group 1 / `--all` only. pinned by: `loomwright/scripts/test-automate-loop-split.sh` copies this runner and its parts (`cp -R "$HERE/test-automate-trail.d" "$M11/"`) and reads them statically; the guard line must not contain a raw SKILL-index read.
- **`loomwright/scripts/test-meta-sync.sh`** — keep: `tms_part() {`, the temp root `TROOT="$(mktemp -d)"` and its EXIT trap, the summary `echo "test-meta-sync: $pass passed, $fail failed"`; reuse: `check $?` / `ok` / `no`.
- **`loomwright/scripts/test-automate-trail.d/*.sh`** — keep: each part stays sourced at top level with the runner's variables (no subshell wrapping of a part's body); `00-shared.sh`'s contract `Definitions only: no leg, no ok/no call.` (the guard is neither); `02-closeout.sh`'s non-fatal pull, `git pull -q --ff-only origin main 2>/dev/null; mkdir -p stories` (only the `cd` before it changes). reuse: the idiom `( cd "$P" || exit 1` from `04-watcher-branch-mode.sh`; the guard shape from `test-automate-lanes.d/03-fixes-to-finalize.sh`, `run via test-automate-lanes.sh, never standalone`. mirror: `loomwright/docs/vendor-coupling-manifest.json` counts harness-specific tokens per file (`"loomwright/scripts/test-automate-trail.d/04-watcher-branch-mode.sh": 4`) — the guard text names no harness, vendor or host-settings path, so no count changes (`scripts/check-vendor-coupling.sh`).
- **`loomwright/scripts/test-meta-sync.d/*.sh`** — keep: top-level sourcing; `03-mutants-scrub-allowlist.sh`'s `build_mutant()` gates (`bash -n "$1/meta-sync.sh" || return 1`) untouched; the `setup-memory.sh … apply … >/dev/null 2>&1; rm -f .gitignore.backup.*` steps keep their non-fatal `;` after the new `cd … || exit 1`.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-automate-trail.sh` — AC4 leg: `05-finalize-closeout-others.sh` run standalone keeps the sentinel and names the runner | delete `declare -F tat_part >/dev/null` in `loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh` ⇒ removes the whole one-line guard (test, message and `exit 2` together); the part runs, its `rm` empties the scratch `.supervisor/automate/`, leg red |
| `loomwright/scripts/test-automate-trail.sh` — AC1/AC4 leg for `00-shared.sh` | delete `declare -F tat_part >/dev/null` in `loomwright/scripts/test-automate-trail.d/00-shared.sh` ⇒ the whole guard line is gone; the definitions-only file exits 0 with no runner line, leg red |
| `loomwright/scripts/test-meta-sync.sh` — AC4 leg for `02-guards-mode-base.sh` | delete `declare -F tms_part >/dev/null` in `loomwright/scripts/test-meta-sync.d/02-guards-mode-base.sh` ⇒ the whole guard line is gone; no runner line on stderr, leg red |
| `loomwright/scripts/test-automate-trail.sh` — AC3 static cd-group leg | flip `( cd "$P" \|\| exit 1; git checkout -q -- README` → `( cd "$P" && git checkout -q -- README` in `loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh` ⇒ leg red naming that line |
| `loomwright/scripts/test-meta-sync.sh` — AC3 static cd-group leg | flip `(cd "$W/M" \|\| exit 1; bash "$HERE/setup-memory.sh"` → `(cd "$W/M" && bash "$HERE/setup-memory.sh"` in `loomwright/scripts/test-meta-sync.d/03-mutants-scrub-allowlist.sh` ⇒ leg red naming that line |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Guard trail + meta-sync parts, fix cd groups, add pinned legs, evidence + fragment | all | 13 modify, 2 create | `skills/unit-testing/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh", name: "run via test-automate-trail.sh, never standalone"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-trail.d/00-shared.sh", name: "run via test-automate-trail.sh, never standalone"}
  - {kind: "symbol", path: "loomwright/scripts/test-meta-sync.d/02-guards-mode-base.sh", name: "run via test-meta-sync.sh, never standalone"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-trail.sh", name: "sentinel-run.md"}
  - {kind: "symbol", path: "loomwright/scripts/test-meta-sync.sh", name: "sentinel-run.md"}
  - {kind: "file", path: "docs/evidence/test-parts-standalone-guard.md"}
  - {kind: "symbol", path: "docs/evidence/test-parts-standalone-guard.md", name: "Verdict: PASS for Validation 2"}
  - {kind: "file", path: "changelog.d/test-parts-refuse-standalone.md"}
requires: []
lanes:
  - "loomwright/scripts/test-automate-trail.d/*.sh"
  - "loomwright/scripts/test-meta-sync.d/*.sh"
  - "loomwright/scripts/test-automate-trail.sh"
  - "loomwright/scripts/test-meta-sync.sh"
  - "changelog.d/test-parts-refuse-standalone.md"
  - "docs/evidence/test-parts-standalone-guard.md"
external_requires: []
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md` (mutation-control discipline: every mutant valid before trusting it) |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Needs a file outside the requirement's Touches (`docs/evidence/test-parts-standalone-guard.md`) — source: "Feasibility (Phase 2.5)" | MEDIUM | Asked once at Launch Pad Phase 6 (`LP-SCOPE`); the evidence-file form is the house rule for a Running-system Validation step |
| A guard that fires under the runner aborts the whole suite (`exit 2` in a sourced part) | HIGH | The guard tests only what the runner already sets before sourcing (`tat_part`/`TOP`, `tms_part`/`TROOT`); AC2 runs every trail group plus `--all` and the meta-sync suite before push |
| Pin mutations run an UNGUARDED part standalone (the incident itself) | MEDIUM | `run-pin-mutations.sh` runs pins in a scratch working-tree copy with HOME relocated; the AC4 leg's own cwd is a scratch checkout under the suite's temp root; empty-variable absolute paths resolve under `/`, which is not writable. Never run a part standalone from the real checkout while developing — use the scratch clone of AC5 |
| The AC3 static scanner misses a shape (nested `$( )` inside a group) or over-flags a safe `&&`-only group | MEDIUM | The base inventory in AC3 is the expected set; the scanner must flag every listed group at base (check once against `git show 9a6a850:<part>` copies) and none of the fully `&&`-chained groups |
| A sibling test copies these files and runs them (`test-automate-loop-split.sh` M11) | LOW | M11 is static (`wiring_reader`); re-run it via `ci-local.sh --affected` |
| 15 files touched trips the `context-bound` file count, yet stays one subtask | LOW | ~60 changed lines, each a one-line guard or a `&&`→`\|\| exit 1;` edit; splitting by runner would leave both halves under 3 meaningful files of work and serialize on the fragment |
| Old losses are not undone (a whole-set `meta-sync.sh push` from a damaged checkout would publish deletions) | LOW | Out of scope (requirement non-goal); this item only prevents new losses |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Validation (must pass before merge)
1. **Static — affected suites:** `bash scripts/ci-local.sh --affected` passes, including the new sentinel legs and the two runners' suites (trail: every group); run any suite it lists as not covered directly.
2. **Running system — the incident replayed:** in a scratch clone holding a sentinel `.supervisor/automate/sentinel-run.md`, `bash loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh` exits non-zero naming `test-automate-trail.sh`, and the sentinel is still there; the command and output are committed in `docs/evidence/test-parts-standalone-guard.md` with `Verdict: PASS for Validation 2` (AC5), linked from the PR body.

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-28-test-parts-refuse-standalone-trail-meta.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-11-28T11:40:00Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/1004
- **Branch:** feature/test-parts-refuse-standalone-trail-meta
- **Files changed:** 15
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** unknown (no_driver_handover)
- **Summary:** Every trail (00-06) and meta-sync (01-04) test part now exits 2 naming its runner before running anything when run standalone; the 12 inventoried fixture cd groups open with `cd "$X" || exit 1`, and each runner defines a cd that refuses an empty operand (bash 3.2). New legs: SG1 static cd-group scan with control, SG2 exact-guard check + sentinel replay, SG3 empty/missing-dir cd, SG4 cross-runner identity pin. Evidence docs/evidence/test-parts-standalone-guard.md (Verdict: PASS for Validation 2). Phase 4.5: 2 review rounds, 1 fix round, final PASS; CI green on 2faa312. Driver parked at finalize-marker (linked-worktree state.md trap); marker written and PR opened by hand per the --continue prose.

## Not verified
- **test-automate-trail.sh --all after 193df1f** — ran on ccdb120 (931 ok plus the 2 pre-existing G1/G2 FAILs that also fail at base 6febfe0); after later commits only groups 1-3 and meta-sync re-ran, all green (subtask 1)
- **PR body link to docs/evidence/test-parts-standalone-guard.md (AC5)** — not verified by the worker; the Supervisor's PR body links it (subtask 1)
