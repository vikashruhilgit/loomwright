# Supervisor Job: Golden run-file tests pin today's `/automate` per-item-loop behaviour (automate-speed/05)

## Environment
- **Project:** lane clone `L3` of `ai-agent-manager` (`<primary>-lanes/automate-2026-10-15-163325/L3`)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main (lane clone; origin = vikashruhilgit/loomwright)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1
- **Source requirement:** .supervisor/requirements/automate-speed/05-golden-run-tests.md
- **Base commit:** f5c2d0e23fb717d385047340d7ddb5862153b6e0

> **Warning (1):** this checkout is lane `L3` of the `--parallel 4` wave `automate-2026-10-15-163325`. Sibling lanes run at the same time in their own clones: item 25 (edits `loomwright/commands/automate.md`, `loomwright/skills/automate-loop/SKILL.md`), item 04 (creates `loomwright/docs/loop-inventory/*`, `loomwright/scripts/test-loop-inventory.sh`) and item 17 (token-budget gate files, `CLAUDE.md`, `ARCHITECTURE_CONTRACTS.md`). None intersect this item's Touches. Stay inside `## Touches`: this item creates files only and edits NO existing file. The PR carries a `changelog.d/` fragment and NO version bump (lane PRs never bump; `bash scripts/check-version-bump.sh` passes). Do NOT write to the loop inventory (item 04 owns it; item 06 links the cases).

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2-safe test script + markdown/TSV fixtures; same shape as the other `loomwright/scripts/test-*.sh` suites. |
| 2 | Dependency Availability | GO | Drives existing `automate-helpers.sh` subcommands (bundled via the dispatcher's `_ah_bundle`, the way `test-automate-helpers.sh` builds `$H`); `jq`, `awk`, `git` present; `gh` is STUBBED on `PATH` for any `gh`-reading subcommand — no network. |
| 3 | Architecture Fit | GO | Tests the helper subcommands the prose (`skills/automate-loop/per-item-loop.md`, `modes-and-merge-gate.md`, `resume.md`) tells the engine to call, in that prose's order; adds no behaviour. |
| 4 | Scope vs Supervisor Capability | CAUTION | One subtask, but ~50 prose units (headings + numbered branches) to map. Bounded by allowing a `judgment — covered at the step boundary` case and by one case covering several units where the prose is one helper sequence. |
| 5 | Hard Blockers | GO | `## Depends on: none`. |

**Overall Verdict:** CAUTION (scope size — see Risk Assessment)

## Task
**Goal:** Add a golden run-file test suite, `loomwright/scripts/test-automate-golden.sh`, plus fixtures under `loomwright/scripts/fixtures/automate-golden/`. Each case starts from a run file built from a real past run in `.supervisor/automate/` (scrubbed). It runs the `automate-helpers.sh` subcommands the prose calls for that step, in the prose's order, and diffs the resulting run file against an expected run file byte-for-byte, with timestamps normalised. Every `##`/`###`/`####` heading and every column-0 numbered branch in `per-item-loop.md`, `modes-and-merge-gate.md` and `resume.md` must map to a case (or to a `judgment — covered at the step boundary` case); the test prints the map and fails on an unmapped unit.

**Problem Statement:** Items 06–09 will move the loop's control flow from prose into a `next-step` script. Other scripts parse the run file's pinned `## Progress` / `## Current` line formats (for example, `lane-drain-check` counts `owned drain started` lines). Today, no test pins the run file a branch produces, so a migration that changes a line format or skips a branch would pass every suite.

**Out of scope:** Supervisor / review-heal / Launch Pad inner gaps (items 11–13); writing to `loomwright/docs/loop-inventory/` (item 04 owns it, item 06 links the cases); ANY behaviour change. A case that would need a behaviour change to pass is a finding: record it under `## Findings (behaviour not changed)` in the committed evidence file `docs/evidence/as05-golden-run-tests.md`. Do not fix it here, and do not write a case that pins the wrong behaviour as correct without naming it there.

## Acceptance Criteria
- [ ] **AC1 (unit extraction + map, fail on unmapped).** Given the repo prose files `loomwright/skills/automate-loop/per-item-loop.md`, `modes-and-merge-gate.md` and `resume.md`, when `bash loomwright/scripts/test-automate-golden.sh` runs, then it extracts every unit LIVE from those files, skipping fenced code blocks. Units are (a) every line matching `^#{2,4} ` (id `<file>|<heading text>`) and (b) every column-0 numbered list item `^[0-9]+\. ` (id `<file>|<nearest preceding heading text>|L<k>.<n>`, where `k` is the 1-based ordinal of that numbered list under that heading — a list restarts at `1.` — and `n` is the item number). It reads the committed map `loomwright/scripts/fixtures/automate-golden/MAP.tsv` (data rows `<unit id>\t<case name>` or `<unit id>\tjudgment — covered at the step boundary: <case name>`; lines starting with `#` and blank lines are comments the parser ignores) and prints one `map: <unit id> → <case>` line per unit. It FAILS (non-zero exit, `FAIL: unmapped unit <id>`) on any unit with no map row, FAILS (`FAIL: stale map row <id>`) on any map row whose unit no longer exists, and FAILS (`FAIL: map names missing case <case>`) on any map row naming a case directory that does not exist.
- [ ] **AC2 (golden cases drive the helpers in prose order).** Given a case directory `loomwright/scripts/fixtures/automate-golden/<case>/` holding `input.md` (the run file before), `steps` (one helper invocation per line, in the prose's order, with `$RF` for the case's scratch copy of the run file and other documented placeholders) and `expected.md` (the run file after), plus a MANDATORY `expected.out` (each step's stdout, stderr and exit code — e.g. the drain-start guard case pins exit 3 and its `current_not_set:` stderr line, which the run file alone cannot show because the guard appends before it exits), a MANDATORY `source` file (the real run id the input came from) and an optional `gh.stub` (a scripted `gh` answer table for subcommands that read `gh`), when the test runs the case, then it copies `input.md` into a fresh `mktemp -d` scratch dir (outside the repo), runs each step through the bundled helper with no network, normalises timestamps (`[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z` → `<TS>`) in BOTH actual and expected, and compares byte-for-byte. A mismatch FAILS naming the case (`FAIL: <case>: run file differs` plus a unified diff, and the same for `expected.out`). Case names are the kebab-case slug of the prose step heading or bold step label they cover (e.g. `drain-superseded-by-merge`, `rate-limit-park`, `termination-limit-reached`), so item 06 can map them to inventory rows mechanically.
- [ ] **AC3 (fixtures from real runs, scrubbed).** Given the fixtures, then every `input.md` is derived from a real run file in `.supervisor/automate/` (at minimum `automate-2026-10-13-181331`: its drain-READY park, dismissed-findings decisions, post-merge closeout lines and resume/re-pick sequence; plus whichever other real runs supply an `escalated` park, a `rate_limit`/`drain_died`/`trail_pr_open` park, a lane run file, and a superseded-by-merge drain), trimmed to the lines the case needs. Each case's `source` file is the ONE provenance record: it names the real run id the input came from. When no real run carries the branch (e.g. `automate-2026-10-13-181331` has no escalated or superseded-by-merge lines, and no run may hold the pinned `drain superseded_by_merge — …` line), build the input from the nearest real run, and name the gap in that `source` file and in the evidence file's Findings section. Never use this wave's in-flight run files (`automate-2026-10-15-163325*`) as a source. When `bash loomwright/scripts/test-automate-golden.sh` runs, then it asserts no file under `fixtures/automate-golden/` contains `/Users/` or `/home/` (`FAIL: home path in <file>`). Fixtures carry only this plugin's own run content (requirement paths, PR URLs of `vikashruhilgit/loomwright`), never another project's.
- [ ] **AC4 (a pinned prefix change turns the suite red, naming the case — built-in mutation legs).** Given the test's own mutation legs, each run against a mutated COPY of the code under test (never the working tree): (M1) a bundle copy where the anchor `owned drain started)'` (the closing alternative of `_progress_current_guard`'s `re_g=` regex in `automate-helpers.d/runfile.sh` — unique in the bundle, unlike the bare phrase, which also sits in the `#:` usage line) has one character changed ⇒ the golden case that appends an `owned drain started — …` line over an unset `## Current` FAILS by name; (M2) a bundle copy where the anchor `local msg="current_rebuilt:` (unique; the bare `current_rebuilt:` also appears in a usage line and a comment) has one character changed ⇒ the resume `## Current`-repair case FAILS by name; (M3) a copy of `automate-dismissed.sh` (beside the bundle, so the bundle's `$SCRIPT_DIR` sibling lookup resolves it) where the `dismissed: $decision` progress prefix has one character changed ⇒ the dismissed-findings decision case FAILS by name; (M4) a scratch copy of `per-item-loop.md` with one extra `### ` heading ⇒ `unmapped unit`; (M5) a scratch prose copy with one mapped heading removed ⇒ `stale map row`; (M6) a scratch fixture copy containing `/Users/<x>/` ⇒ `home path`. The test supports this through env overrides it documents in its header (`GOLDEN_HELPERS=<bundle path>`, `GOLDEN_PROSE_DIR=<dir>`, `GOLDEN_FIXTURES=<dir>`), and each leg is gated: the mutant is non-empty, differs from the original, its anchor text occurs exactly once, and a mutated script passes `bash -n`. A leg whose mutant cannot be built FAILS (never a silent skip). Each leg asserts that the inner run exits non-zero AND that its output names the expected case or unit.
- [ ] **AC5 (judgment boundaries).** Given a unit the helpers alone cannot drive (it needs a model or owner judgment — e.g. the `AUT-WAIVE` ask, the Interactive dismissed-findings ask, RUN's `/autonomous` call itself, §10 cond 3's trusted-actor read), then its map row reads `judgment — covered at the step boundary: <case>`. That case's fixture pins what the step RECEIVES (input run file + any sidecar) and what it MUST WRITE (expected run file after the step's helper calls, with the judgment's answer supplied as a fixed input, e.g. the `dismissed-decide … follow-up` call an owner's "Follow-up" produces).
- [ ] **AC6 (no behaviour change, no edits to existing files).** Given the PR diff, then it creates only `loomwright/scripts/test-automate-golden.sh`, files under `loomwright/scripts/fixtures/automate-golden/`, `docs/evidence/as05-golden-run-tests.md` and `changelog.d/as05-golden-run-tests.md` (the evidence file goes beyond the requirement's Touches; it is a new unique path that collides with no sibling lane); `git diff --name-only origin/main...HEAD` lists no other path. The evidence file `docs/evidence/as05-golden-run-tests.md` (committed Markdown) has a `## Findings (behaviour not changed)` section listing every case where today's output differs from what the prose says (or states "none found").
- [ ] **AC7 (repo test gates).** Given the new test, then its first executable line is the self-resolving `. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"` (`scripts/check-test-hermetic.sh`); it uses no temporary locale assignment (`env LC_ALL=C sort`, never `LC_ALL=C sort` — `scripts/check-locale-prefix.sh`); no fixed `sleep` (`test-no-fixed-sleep-race.sh`); every assertion helper it calls is defined (`test-suite-helpers-defined.sh`); bash 3.2-safe (no `mapfile`, no `sed -i`, no GNU-only flags); it ends with a `PASS: <n> FAIL: <m>` style tally and exits non-zero on any failure; it cleans every `mktemp -d` dir in a trap. No bare unpinned `file.ext:<N>` citation in committed prose/comments (`test-citation-drift.sh`).
- [ ] **AC8 (fragment, no bump).** Given the PR diff, then `changelog.d/as05-golden-run-tests.md` exists (`<!-- bump: patch -->`, format per `changelog.d/README.md`); no version file (`loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CHANGELOG.md`) is touched; `bash scripts/check-version-bump.sh` passes.
- [ ] **AC9 (validation evidence in a committed evidence file).** Given the requirement's `## Validation`, then the committed `docs/evidence/as05-golden-run-tests.md` holds: V1 `bash loomwright/scripts/test-automate-golden.sh` and `bash loomwright/scripts/test-automate-helpers.sh` each with `<passed>/<total>` and 0 failures (for test-automate-helpers the ratio is derived from its `RESULT: N passed, M failed` line); V2 (mutation control, by hand, outside the built-in legs) — change the `owned drain started` alternative in a SCRATCH bundle copy of `automate-helpers.sh` and run `GOLDEN_HELPERS=<that copy> bash loomwright/scripts/test-automate-golden.sh` ⇒ non-zero exit naming the case; the by-hand red/green record of every Pin mutations row; and the `bash scripts/ci-local.sh` result line. Each output sits in a fenced block. The PR body links to that file, and it may also repeat the outputs under `validation 1` / `validation 2` lines for `validation-gate`.

## House Rules

> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift. (Here: the unit list is extracted LIVE from the prose, never hand-copied; `MAP.tsv` holds only id → case.)
- A count or version claim lives in exactly ONE authoritative machine-readable place. (Here: the PR body and fragment state no unit/case count as a standing claim; counts appear only as test output evidence.)

## Configuration
- **Mode:** single-agent
- **Base Branch:** main
- **Workers:** 1

## Pin mutations

> Grounded at base `f5c2d0e23fb717d385047340d7ddb5862153b6e0`. Rows M1–M6 are ALSO built-in legs of the test (AC4). Rows H1+ are by-hand only. The worker runs every row once, by hand, and records red/green in `docs/evidence/as05-golden-run-tests.md`. In the M1 row, the `\|` characters are Markdown table escapes; the source has a plain `|`.

| Pin (case / leg) | Code mutation that must turn it red |
|---|---|
| M1 — drain-start guard case (fails via `expected.out`: exit 3 + `current_not_set:` stderr) | `loomwright/scripts/automate-helpers.d/runfile.sh` `_progress_current_guard`: anchor `owned drain started)'` in `re_g='^([^ ]+ )?(picked \|ran /autonomous\|owned drain started)'` → `owned drain startex)'` (in a bundle copy) |
| M2 — resume `## Current` repair case | `runfile.sh` `current-rebuild`: anchor `local msg="current_rebuilt:` → `local msg="current_rebuilx:` |
| M3 — dismissed-findings decision case | `loomwright/scripts/automate-dismissed.sh` `dismissed-decide`: `"…dismissed: $decision $name — $snippet"` → `dismissex:` |
| M4 — unit map completeness | add `### Scratch heading` to a prose copy of `per-item-loop.md` |
| M5 — stale map row | delete one mapped `### ` heading line from a prose copy |
| M6 — home-path scrub | add a `/Users/<x>/` line to a fixture copy |
| H1… — one row per helper subcommand family the cases drive (`current-set`, `queue-checkoff`, `closeout`, `trail-gate`, `dismissed-drafts`, `validation-gate`, `gate-eval`, `lane-park`, `finalize-empty`, …) | the worker adds one row per family BEFORE writing that family's cases. Each row names a one-character change to an output literal that family prints or writes (anchor quoted, unique in its file) and the case that must go red. The row is run by hand on a scratch copy, and the result is recorded in the evidence file. |

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | Golden suite: harness + map + mutation legs + real-run fixtures + fragment | 0 modify, 3+ create (test script, fixtures dir, fragment) | LAUNCHABLE |

### Subtask 1 — Golden run-file suite (LAUNCHABLE)
- **Criteria:** AC1–AC9
- **Files (create):** `loomwright/scripts/test-automate-golden.sh` (HIGH), `loomwright/scripts/fixtures/automate-golden/MAP.tsv` (HIGH), `loomwright/scripts/fixtures/automate-golden/<case>/{input.md,steps,expected.md,expected.out,source[,gh.stub]}` (HIGH — one dir per case), `docs/evidence/as05-golden-run-tests.md` (HIGH), `changelog.d/as05-golden-run-tests.md` (HIGH)
- **Files (modify):** none
- **Read-only inputs:** the three prose files above; `loomwright/scripts/automate-helpers.sh` (its `_ah_bundle` function and `#:` usage lines) and `loomwright/scripts/automate-helpers.d/*.sh`; `loomwright/scripts/automate-trail.sh`, `automate-dismissed.sh`, `automate-lanes.sh` (subcommands they implement); `loomwright/scripts/test-automate-helpers.sh` (`ah_build_bundle`, its `gh` stub patterns, its mutation-leg gating convention — copy the shape, do not import or edit it); `loomwright/scripts/hermetic-test-env.sh`; real run files `.supervisor/automate/automate-2026-10-13-181331.md` and the others named in AC3 (lane runs `*-L<n>.md`, escalated/superseded runs found by `grep -l 'pause_reason: escalated\|superseded_by_merge\|rate_limit\|drain_died' .supervisor/automate/*.md`, EXCLUDING this wave's own `automate-2026-10-15-163325*` files).
- **Design notes (from Phase 3 analysis):**
  - Build the helper under test exactly like `test-automate-helpers.sh` does (`_ah_bundle` expansion into a `mktemp -d` dir beside symlinks to every other `scripts/` entry), unless `GOLDEN_HELPERS` is set. Run each step as `bash "$H" <subcommand> …`.
  - Steps that need `git` (closeout's sync, `trail-gate`, `trail-pr`) run inside a throwaway `git init` repo in the scratch dir with a bare `origin`, or are covered as a judgment/boundary case with their printed lines supplied as fixed input — pick per case and say which in the map comment. Never touch this checkout's git state or the network.
  - `gh` reads (`reconcile-item`, `closeout`'s evidence gate, `park-ask-gate`, `gate-eval`) go through a `PATH`-prepended stub driven by the case's `gh.stub`.
  - Timestamps the loop itself writes in a step line are fixed in `steps`; timestamps a helper generates are normalised (AC2).
  - Bold-labelled bullet branches (`- **Drain superseded by a merge…**`, the Rate-limit park and Termination bullets) are not map units (AC1 follows the requirement's "numbered branch"), but each still gets a named case.
  - Numbered sub-steps of the two "Order —" lists in "Dismissed-findings decision step (before the park)" are separate units (`L1.*`, `L2.*`); one case may cover a whole list when the list is one helper sequence. Map each unit explicitly anyway.
  - §10 conditions 1–7 each get a `gate-eval` case with a stubbed `gh`/protection/GraphQL answer and the loop's resulting `awaiting_merge` park write, or a boundary case where the condition's input cannot be stubbed hermetically (state why in the map comment).

```yaml
# Subtask 1 — Golden run-file suite (LAUNCHABLE)
provides:
  - {kind: "file", path: "loomwright/scripts/test-automate-golden.sh"}
  - {kind: "file", path: "loomwright/scripts/fixtures/automate-golden/MAP.tsv"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-golden.sh", name: "GOLDEN_HELPERS"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-golden.sh", name: "GOLDEN_PROSE_DIR"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-golden.sh", name: "unmapped unit"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-golden.sh", name: "stale map row"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-golden.sh", name: "hermetic-test-env.sh"}
  - {kind: "symbol", path: "loomwright/scripts/fixtures/automate-golden/MAP.tsv", name: "judgment — covered at the step boundary"}
  - {kind: "file", path: "changelog.d/as05-golden-run-tests.md"}
  - {kind: "file", path: "docs/evidence/as05-golden-run-tests.md"}
requires: []
lanes:
  - "loomwright/scripts/test-automate-golden.sh"
  - "loomwright/scripts/fixtures/automate-golden/"
  - "changelog.d/as05-golden-run-tests.md"
  - "docs/evidence/as05-golden-run-tests.md"
```

## Parallelism Analysis
single-agent (no fan-out)

- Recommended workers: 1

## Skill References
- `loomwright/skills/quality-checklist/SKILL.md`
- `loomwright/skills/automate-loop/SKILL.md` (§1.5 subcommand table — the authority for each subcommand's output shape)

## Risk Assessment

| Risk | Level | Source | Mitigation |
|------|-------|--------|------------|
| Evidence recorded only in the PR body is invisible to brief conformance (Plan Review attempt 1) | HIGH | Plan Review | All validation output, the Findings list and the pin red/green record live in `docs/evidence/as05-golden-run-tests.md`. |
| Scope: ~50 prose units, many needing `gh`/`git` stubs; one worker runs out of context | MEDIUM | Feasibility (Phase 2.5) | One case may cover several units of one helper sequence; boundary cases allowed per AC5; build the harness + map + mutation legs FIRST, then add cases file by file, committing per prose file. |
| A case pins today's WRONG behaviour silently | HIGH | Requirement non-goal | AC6's `## Findings (behaviour not changed)` section; when output disagrees with the prose, write the case to today's output AND name the disagreement there. |
| Golden diffs flake on helper-generated timestamps, temp paths or `mktemp` names | MEDIUM | Analysis | Normalise ISO timestamps; run every case in its own scratch dir; put no absolute scratch path into an expected file (normalise the scratch root to `<TMP>` if a helper prints it). |
| Fixtures leak a home path or a non-plugin project's content | MEDIUM | Requirement scope | AC3 built-in scrub assertion + M6 leg; fixtures derive only from this repo's own runs. |
| Mutation legs that silently do not mutate (anchor drifted) read as green | HIGH | `test-automate-helpers.sh` convention | AC4 gating: anchor occurs exactly once, mutant differs, `bash -n`, else the leg FAILS. |
| Repo-wide test ratchets reject the new suite (hermetic first line, locale prefix, fixed sleep, undefined helper) | MEDIUM | `check-test-hermetic.sh`, `check-locale-prefix.sh`, `test-no-fixed-sleep-race.sh`, `test-suite-helpers-defined.sh` | AC7; run `bash scripts/ci-local.sh` before push. |
| Item 25 (parallel lane) edits `SKILL.md`; items 06+ later edit the three prose files | LOW | Wave plan | The unit list is extracted live, and `stale map row` / `unmapped unit` tell the later item exactly which row to update. This item reads, and never edits, the prose. |

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-10-15-as05-golden-run-tests.md

## Plan Review
- **Result:** PASS (attempt 2/3; attempt 1 FAIL — 2 HIGH pr_body_evidence + 5 MEDIUM, all fixed)
- **Deferred (LOW, below fix floor):** (1) M3 leg must `rm -f` the bundle-dir symlink `automate-dismissed.sh` before writing its mutant and assert the real file unchanged (a write through the symlink would edit the working tree); (2) the evidence file's pin table should name every subcommand family that appears in any case's `steps`.

## Outcome
- **Status:** completed
- **Completed:** 2026-10-15T13:43:38Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/558
- **Branch:** feature/as05-golden-run-tests
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Golden run-file suite (test-automate-golden.sh, 43 cases, 50 prose units mapped live, legs M1–M10). Phase 4.5: iter 1 PASS + 2 MEDIUM at floor (mixed-fence tracking, duplicate unit ids) and CI red (75 fixture files under tree/.supervisor/ gitignored by */**/.supervisor/ — never committed) → fix 1db705e (dot-supervisor/ storage + check_ignored guard); iter 2 PASS but CI red (intermittent SIGPIPE 'Broken pipe' stderr from automate-lanes.sh _lanes_validation_rows under ignored SIGPIPE) → fix 86a4967 (narrow stderr filter + leg M10, helper race recorded F9); iter 3 PASS, CI all green on 86a4967. 8 LOW/nit findings dismissed below the MEDIUM floor.
