# Supervisor Job: The automate-helpers test parts refuse to run standalone, and their fixture `cd` groups stop when the `cd` fails

## Environment
- **Project:** ~/orca/workspaces/ai-agent-manager/dolphin
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: feature/automate-helpers-test-parts-refuse-standalone (at `origin/main`, 0 commits behind)
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (source requirement is gitignored, so its provenance is unverified)
- **Source requirement:** .supervisor/requirements/2026-11-28-092431-automate-helpers-test-parts-refuse-to-run-standalone.md
- **Base commit:** 1887fca47a52d35df2faeeebe15639544caae0cd

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash test scripts, the existing stack |
| 2 | Dependency Availability | GO | no new dependency; reuses the re-exec guard four parts already carry and Part A's (#1004, merged at base) scan program and `cd` override |
| 3 | Architecture Fit | GO | parts stay sourced by name by `test-automate-helpers.sh`; the guard is a no-op when sourced |
| 4 | Scope vs Supervisor Capability | GO | ~22 files, ~100 changed lines, mostly a one-line guard per part; one worker |
| 5 | Hard Blockers | GO | Part A (the dependency) is merged: `1887fca` is `origin/main` |

**Overall Verdict:** GO

## Task
**Goal:** Every tracked part under `loomwright/scripts/test-automate-helpers.d/` re-executes `test-automate-helpers.sh` for itself, before running any command, when it is run on its own with `bash <part>`; no fixture `cd` group in those parts can run on in the caller's directory after its `cd` fails; and a new suite part pins both, including a replay from a scratch checkout holding a sentinel run file.

**Problem Statement:**
The owner, whose `/automate` runs keep their only resume state in `.supervisor/automate/`, needs these parts to be harmless when run the wrong way, because a split test part run standalone has none of its runner's setup, and on 2026-11-28 one such part deleted every `.supervisor/automate/*.md` in the live checkout (GitHub issue #994; Part A fixed the trail and meta-sync parts in #1004).
Currently 16 of the 20 parts (`02-runfile` … `09-brief-repair`, `11-ceiling` … `17-right-size`) have no guard: run alone they find no `$H`, `ok` or `no`, run whatever fixture commands they can in the caller's directory, and exit 0. Four (`01-config`, `10-reconcile-status`, `18-backlog`, `19-followup`) already carry a re-exec guard. And macOS `/bin/bash` 3.2 treats `cd ""` as a successful no-op, so even a `( cd "$X" && rm … )` group runs in the caller's directory when `$X` is empty.
Success looks like: each part run standalone from a scratch checkout holding a sentinel `.supervisor/automate/sentinel-run.md` hands off to `test-automate-helpers.sh <its own name>` and the sentinel stays; `test-automate-helpers.sh` with no argument still runs every part with every existing leg unchanged.

**Guard form (decision; the requirement allows either form):** the re-exec form the four guarded parts already carry, for all 20 parts — `if [ "${BASH_SOURCE[0]}" = "$0" ]; then exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test-automate-helpers.sh" <part>; fi`. Part A's `exit 2` form is not used here, though the requirement's Assumptions expected it: `scripts/run-pin-mutations.sh` runs a pin's test file as `bash <file>`, and a `## Pin mutations` row that names a part (as `01-config.sh`'s header says) must then run that part's real legs. An `exit 2` guard would turn every such pin into an error, and removing the four existing re-exec guards would undo `6839cd3` ("run 10-reconcile-status / 18-backlog for real when executed directly"). The runner takes part names as positional arguments (`bash test-automate-helpers.sh [<part>...]`); it has no `--part` flag, so the requirement's "(`--part`)" means this positional form, and no runner argument is added.

## Acceptance Criteria
- [ ] **AC1 (standalone run re-execs the runner).** Given any tracked part `loomwright/scripts/test-automate-helpers.d/<p>.sh` (every `TAH_PARTS` entry, the new `20-standalone-guard` included), when it is run directly with `bash <part>`, then its first command, placed within the file's first 15 lines after any leading comment block, is exactly `if [ "${BASH_SOURCE[0]}" = "$0" ]; then exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test-automate-helpers.sh" <p>; fi`, with `<p>` the part's own file name without `.sh`. The 16 unguarded parts gain it (one short comment line above it is allowed); `01-config`, `10-reconcile-status`, `18-backlog` and `19-followup` already match it and keep it byte-for-byte.
- [ ] **AC2 (suite unchanged).** Given `test-automate-helpers.sh`, when it runs with no argument (as CI and `run-self-tests.sh` call it) and with one part name (as the guard calls it), then every selected part is still sourced (the `[ "$tah_done" = "$tah_list" ]` check stays green), every leg that passed at base still passes with the same `ok:` text, and the only new `ok:`/`FAIL:` lines are the AC3/AC4 legs below. The runner gains, before any part is sourced, Part A's empty-operand `cd` byte-for-byte as `test-automate-trail.sh` defines it: `cd() { if [ "$#" -ge 1 ] && [ -z "$1" ]; then echo "cd: empty directory operand (a fixture path is unset)" >&2; return 1; fi; builtin cd "$@"; }`. The new part `20-standalone-guard` joins `TAH_PARTS` (last) and the runner's source lines (`tah_run 20-standalone-guard && . "$TAH_D/20-standalone-guard.sh"`, after `19-followup`'s), so the runner's own source-line check still holds.
- [ ] **AC3 (every `cd` group stops on a failed `cd`).** Given a fixture step of the form `( cd "$X" && a; b; c )`, `$( cd "$X" && a; b )` or a multi-line `( cd "$X"` group in any part, when `$X` is empty or not a directory, then none of `a`, `b`, `c` runs. Proven by these legs of `20-standalone-guard.sh`:
  - **SG1 (static scan):** the SG1 awk program copied byte-for-byte from `test-automate-trail.sh` (`SG_SCAN=`), with the same planted control lines and expected `control:1 … control:14` hits, then run over every `$TAH_PARTS` entry by name (never a glob); it fails naming `file:line` for any hit. At base it reports seven lines, every one a `$(cd "$X" && find … -exec … \; …)` or `(cd "$1" && find … \; …)` whose escaped `\;` the scan reads as a separator: `10-reconcile-status.sh` (the `BEFORE=` and `AFTER=` lines), `17-right-size.sh` (the `RZ11_BEFORE=` and `RZ11_AFTER=` lines and `mi_snap()`), `18-backlog.sh` (`bl_sum()`) and `19-followup.sh` (`fu_sum()`). Each becomes `cd "$X" || exit 1;` in place of `cd "$X" &&`, the rest of the line byte-identical; the scan program itself is not changed.
  - **SG3 (runtime):** `( cd "$sg_x" || exit 1; : > <marker> )` with `sg_x` empty and with a missing directory each exit 1 and leave no marker, and `type -t cd` prints `function` (so a deleted override is caught on bash 5 too, which already refuses `cd ""`).
- [ ] **AC4 (the incident replayed, pinned).** Given a scratch checkout (`git init` under a `mktemp -d` root, never the real checkout) holding `.supervisor/automate/sentinel-run.md` and `.supervisor/automate/sentinel.next-step.json`, and a scratch layout `<s>/scripts/test-automate-helpers.d/` holding a copy of every part beside a stub `<s>/scripts/test-automate-helpers.sh` that writes its arguments to a log and exits 0, when each copied part is run with `bash <copy>` (cwd = the scratch checkout, stdin `</dev/null`), then — leg **SG2**, one `ok`/`no` per `$TAH_PARTS` entry — the part is first checked to have the exact AC1 guard as its first command within its first 15 lines (a part without it is reported red and never run, because running it is the incident itself), then it exits 0, the stub logged exactly `<p>`, and both sentinel files are still there with their content. These legs live in the new part `loomwright/scripts/test-automate-helpers.d/20-standalone-guard.sh`, which reads `$TAH_PARTS` and `$TAH_D` from the runner rather than a second part list.
- [ ] **AC5 (release fragment).** A `changelog.d/automate-helpers-parts-refuse-standalone.md` fragment (`<!-- bump: patch -->`) describes the change in prose; no version file is hand-edited, `bash scripts/check-version-bump.sh` passes, and the fragment cites no bare `file:line` (`test-citation-drift.sh`) and names no suite pass count.

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

(Applied here: the SG legs read the runner's own `TAH_PARTS` instead of keeping a second list; the fragment names no pass count. The SG1 program and the `cd` override are deliberate byte-for-byte copies of `test-automate-trail.sh`'s, so that Part B, the CI guard check and out of scope here, can compare them against one source.)

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| unguarded parts (gain the AC1 guard) | `loomwright/scripts/test-automate-helpers.d/02-runfile.sh` (661), `03-intake.sh` (217), `04-resume.sh` (237), `05-gate-eval-harness.sh` (177), `05-gate-eval.sh` (512), `06-gate-eval-tail.sh` (133), `07-rules-gate.sh` (888), `08-learning-emit.sh` (670), `09-brief-repair.sh` (264), `11-ceiling.sh` (132), `12-meta.sh` (340), `13-plan-waves.sh` (795), `14-escalation.sh` (416), `15-lane-seams.sh` (156), `16-queue-gates.sh` (245), `17-right-size.sh` (390; also its three AC3 `cd` lines) — all under `loomwright/scripts/test-automate-helpers.d/` | — | HIGH |
| guarded parts (AC3 `cd` lines only) | `loomwright/scripts/test-automate-helpers.d/10-reconcile-status.sh` (989), `loomwright/scripts/test-automate-helpers.d/18-backlog.sh` (544), `loomwright/scripts/test-automate-helpers.d/19-followup.sh` (355) | — | HIGH |
| runner | `loomwright/scripts/test-automate-helpers.sh` (451) | — | HIGH |
| new leg part | — | `loomwright/scripts/test-automate-helpers.d/20-standalone-guard.sh` | HIGH |
| release | — | `changelog.d/automate-helpers-parts-refuse-standalone.md` | HIGH |

`01-config.sh` (461) already carries the exact AC1 guard and has no AC3 hit: it is not modified.

**Module layout (one home per new responsibility):**
- The standalone guard → each part's own first command, edited in place in every part including those at or past 500 lines (`02`, `05-gate-eval`, `07`, `08`, `13`; `10` and `18` keep theirs). Reason: the guard has to run before anything the part sources or defines, so it cannot live in a shared helper the part would first have to find; it is one line, the form four parts already carry.
- The AC3 `cd` edits → in place, on the lines that already hold each group (an edit of an existing line, no new responsibility; `10-reconcile-status.sh` at 989 and `18-backlog.sh` at 544 change only those lines).
- The empty-operand `cd` → the runner (451), which sources every part, beside its part loader; one line.
- The SG1/SG2/SG3 legs → a CREATE part, `20-standalone-guard.sh`, not the runner: about 70 lines would take the runner (451) past the §"Module layout" threshold, and the legs read only `$TAH_PARTS`, `$TAH_D`, `ok` and `no`, all runner-set before any part is sourced.
- No helper that 2+ siblings copy is needed; no extract row. (The SG1 program is copied from `test-automate-trail.sh`, a third copy after `test-meta-sync.sh`'s; extracting it into a shared file is Part B's CI-guard work and a non-goal here.)

**Total estimated files:** 20 modify + 2 create

## Touched-file invariants

> Grounded at base `1887fca47a52d35df2faeeebe15639544caae0cd`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/test-automate-helpers.sh`** — keep: the hermetic first source `. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"` (`scripts/check-test-hermetic.sh` fails CI without it); the one part list `TAH_PARTS=` and prerequisite map `TAH_PREREQ=`; the self-text check `tah_have="$(grep -E '^tah_run |\. "\$TAH_D/' "${BASH_SOURCE[0]}")"`, which requires exactly one `tah_run <p> && . "$TAH_D/<p>.sh"` line per `TAH_PARTS` entry in order and no other line sourcing from `$TAH_D` (the `cd` line and any comment must not match that grep); the closing check `[ "$tah_done" = "$tah_list" ] ||`; the summary `echo "RESULT: $pass passed, $fail failed"`; positional part selection (`for tah_a in "$@"; do`) and `set --` before any part. reuse: `ok`/`no`. pinned by: `loomwright/scripts/test-automate-helpers-modules.sh` copies this runner and `test-automate-helpers.d/` into a scratch layout and asserts the loader's messages (`FAIL: missing test part:`, `FAIL: test part does not parse (bash -n):`) and the single-part banner `== test-automate-helpers: parts 11-ceiling (in this order, prerequisites included) ==` — none may change.
- **`loomwright/scripts/test-automate-helpers.d/*.sh`** — keep: each part stays sourced at top level with the runner's variables (no subshell wrapping of a part's body); the four existing guards byte-for-byte (`01-config.sh`'s `exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test-automate-helpers.sh" 01-config; fi`); every part must still pass `bash -n` under the runner's `$BASH` (`tah_part()`). reuse: the guard text above; the `cd "$X" || exit 1` idiom Part A used (`( cd "$P" || exit 1` in `test-automate-trail.d/04-watcher-branch-mode.sh`). mirror: `loomwright/docs/vendor-coupling-manifest.json` counts harness-specific tokens per file (`"loomwright/scripts/test-automate-helpers.d/05-gate-eval.sh": 2`) — the guard and the SG legs name no harness, vendor or host-settings path, so no count changes (`scripts/check-vendor-coupling.sh`).
- **`loomwright/scripts/test-automate-trail.sh`** (read, never modified) — mirror: `SG_SCAN='!cont && /^[ \t]*#/ { next }` through its closing `i = e } }'`, the control `printf` lines and the expected `control:1\ncontrol:2\ncontrol:3\ncontrol:4\ncontrol:8\ncontrol:12\ncontrol:14`, and `cd() { if [ "$#" -ge 1 ] && [ -z "$1" ]; then` — the copies in this change match these bytes.

## Closed enumerations touched

> Sibling grep at base `1887fca`: `git grep -nF '19-followup' -- . ':!CHANGELOG.md'` → 3 hits in 2 files.

- **`20-standalone-guard`** (sibling: `19-followup`) — must be named in:
  - `loomwright/scripts/test-automate-helpers.sh` — the part list `TAH_PARTS="01-config 02-runfile …"` — extend (append last).
  - `loomwright/scripts/test-automate-helpers.sh` — the source lines checked by `tah_have`, `tah_run 19-followup && . "$TAH_D/19-followup.sh"` — extend (one line after it).
  - `loomwright/scripts/test-automate-helpers.d/19-followup.sh` — its own guard's part argument — no change: each part names only itself; the new part names `20-standalone-guard` in its own guard.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-automate-helpers.d/20-standalone-guard.sh` — SG2 `02-runfile`: the guard is the first command | delete `test-automate-helpers.sh" 02-runfile; fi` in `loomwright/scripts/test-automate-helpers.d/02-runfile.sh` ⇒ the whole guard line is gone; SG2 reports `02-runfile` red without running it |
| `loomwright/scripts/test-automate-helpers.d/20-standalone-guard.sh` — SG2 `07-rules-gate`: the guard names its own part | flip `test-automate-helpers.sh" 07-rules-gate; fi` → `test-automate-helpers.sh" 06-gate-eval-tail; fi` in `loomwright/scripts/test-automate-helpers.d/07-rules-gate.sh` ⇒ the first command no longer equals the exact guard for `07-rules-gate` (and the stub would log the wrong name); SG2 red |
| `loomwright/scripts/test-automate-helpers.d/20-standalone-guard.sh` — SG1 cd-group scan | flip `bl_sum() { (cd "$1" \|\| exit 1;` → `bl_sum() { (cd "$1" &&` in `loomwright/scripts/test-automate-helpers.d/18-backlog.sh` ⇒ SG1 red naming that `18-backlog.sh` line |
| `loomwright/scripts/test-automate-helpers.d/20-standalone-guard.sh` — SG3 `type -t cd` is `function` | delete `cd() { if [ "$#" -ge 1 ] && [ -z "$1" ]; then` in `loomwright/scripts/test-automate-helpers.sh` ⇒ `cd` is the builtin again; SG3 red on every bash (and its empty-operand half also red on bash 3.2) |

(Each pin is run as `bash <pin file>`: the new part's own AC1 guard re-execs `test-automate-helpers.sh 20-standalone-guard`, so the pin runs its real legs.)

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Guard the 16 unguarded automate-helpers parts, fix the seven cd lines, add the runner's cd and the SG part, fragment | all | 20 modify, 2 create | `skills/unit-testing/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/test-automate-helpers.d/20-standalone-guard.sh"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-helpers.d/20-standalone-guard.sh", name: "sentinel-run.md"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-helpers.d/02-runfile.sh", name: "test-automate-helpers.sh\" 02-runfile; fi"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-helpers.d/17-right-size.sh", name: "test-automate-helpers.sh\" 17-right-size; fi"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-helpers.sh", name: "tah_run 20-standalone-guard"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-helpers.sh", name: "cd: empty directory operand"}
  - {kind: "file", path: "changelog.d/automate-helpers-parts-refuse-standalone.md"}
requires: []
lanes:
  - "loomwright/scripts/test-automate-helpers.d/*.sh"
  - "loomwright/scripts/test-automate-helpers.sh"
  - "changelog.d/automate-helpers-parts-refuse-standalone.md"
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
| Prior churn on `loomwright/scripts/test-automate-helpers.sh` (30 postmortem entries, 41 rounds; recurring `self_heal_churn`, `drain_churn`) — source: "Prior churn (postmortem ledger)" | MEDIUM | Keep the runner edit to the `cd` line plus the two closed-list entries; the legs live in the new part; run the full no-argument suite and the modules test before push |
| A guard that fires under the runner would re-exec mid-suite | HIGH | When sourced, `$0` is the runner and `BASH_SOURCE[0]` the part, so the guard never fires; AC2 runs the no-argument suite and a single-part run |
| SG2 runs a part standalone; an unguarded one is the incident itself | MEDIUM | SG2 checks the exact guard statically first and never runs a part without it; it runs only copies, beside a stub runner, with cwd a scratch checkout under a `mktemp -d` root. Never run a part standalone from the real checkout while developing |
| SG2's stub proves the target and the argument of the re-exec, not that the real runner then passes for that part | LOW | The real chain is what the four existing guards and `run-pin-mutations.sh` already use; the worker runs `bash loomwright/scripts/test-automate-helpers.d/11-ceiling.sh` once from a scratch clone and reports the `RESULT:` line in its hand-back |
| The empty-operand `cd` changes a leg that relied on `cd ""` succeeding | LOW | No part passes `cd` an empty literal at base; AC2's full run catches any other case |
| The SG1 copy drifts from `test-automate-trail.sh`'s | LOW | Copied byte-for-byte with the same control lines; cross-runner identity is Part B's CI check (non-goal here) |
| `test-automate-helpers-modules.sh` copies `test-automate-helpers.d/` and runs the runner with single parts | LOW | It runs named parts (`11-ceiling` etc.), so `20-standalone-guard` runs there only on a no-argument copy; re-run it via `ci-local.sh --affected` |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Validation (must pass before merge)
1. **Static — affected suites:** `bash scripts/ci-local.sh --affected` passes, including the new sentinel leg and `test-automate-helpers.sh` unchanged (run `bash loomwright/scripts/test-automate-helpers.sh` with no argument and `bash loomwright/scripts/test-automate-helpers-modules.sh` directly if `--affected` lists either as not covered).

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-28-automate-helpers-parts-refuse-standalone.md
```

## Plan Review: PASS (attempt 1/3)
- LOW (deferred, below fix floor MEDIUM) — requirement_fit: the brief uses the existing re-exec guard form, not Part A's exit-2 form. The requirement allows either; the reason is in `## Task`. Part B's CI guard check must accept both forms.
- LOW (deferred) — canonical_source: the reviewer could not run awk to confirm that SG1 reports exactly seven lines at base. Launch Pad ran Part A's SG_SCAN over every part at base `1887fca`, and it reported exactly those seven lines.

## Outcome
- **Status:** completed
- **Completed:** 2026-11-28T13:06:55Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/1007
- **Branch:** feature/automate-helpers-test-parts-refuse-standalone
- **Files changed:** 22
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** unknown (no_driver_handover)
- **Summary:** All 20 automate-helpers parts plus the new 20-standalone-guard carry the exact re-exec guard; the seven fixture cd groups use `cd "$X" || exit 1;`; the runner defines the trail runner's empty-operand cd; 20-standalone-guard adds SG1 (static cd-group scan, pinned line-by-line to test-automate-trail.sh), SG2 (scratch-checkout sentinel replay against a stub runner) and SG3 (runtime cd checks). Heal round 1 fixed a MEDIUM (control-block self-check weaker than its comment); round 2 PASS with one LOW dismissed (SG_SCAN reassignment after the pin). A MEDIUM module-shape note (SG_SCAN/cd copied in three files) was deferred to Part B per the brief. Driver acquire failed on the linked-worktree base checkout; Phases 1-4 ran on the --legacy prose.

## Not verified
- **run-self-tests.sh / GitHub CI no-argument invocation of test-automate-helpers.sh** — only the local runner was run directly; CI on the PR is the full gate (subtask 1)
