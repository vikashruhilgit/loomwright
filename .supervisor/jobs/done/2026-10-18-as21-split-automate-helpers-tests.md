# Supervisor Job: Split test-automate-helpers.sh into a thin runner + sourced parts under test-automate-helpers.d/ (move-only)

## Environment
- **Project:** automate-2026-10-15-163325/L17 (lane clone of loomwright)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (disk 92% used, 35 GiB free — adequate)
- **Source requirement:** .supervisor/requirements/automate-speed/21-split-automate-helpers.md
- **Base commit:** 3a03dfa66d7de22ff93b0327affa60aa752948d2

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure bash test file; the same runner + `test-<x>.d/` part pattern already ships for `test-automate-trail.sh` and `test-automate-lanes.sh` (automate-speed/19). |
| 2 | Dependency Availability | GO | No new dependency. The requirement's precondition `feature/af39a-sweep` is merged (`514781c Merge pull request #555`, folded in v17.3.0). |
| 3 | Architecture Fit | GO | Mirrors the `tat_part` loader in `test-automate-trail.sh` (by-name source, missing part ⇒ exit 1). CI globs `loomwright/scripts/test-*.sh` only, so `.d/` parts are never separate suites. |
| 4 | Scope vs Supervisor Capability | CAUTION | ~6,200 moved lines over ~18 files, but the move is mechanical (contiguous line ranges cut with a script, byte-verified), so one worker holds it. Splitting across workers would make every subtask edit the runner (file-conflict). |
| 5 | Hard Blockers | GO | None. The base already has 1 failing leg (W19, environment-dependent; see Risk Assessment) — the AC is identical before/after, not all-green. |

**Overall Verdict:** CAUTION

## Task
**Goal:** Turn `loomwright/scripts/test-automate-helpers.sh` into a thin runner that sources its legs, moved verbatim and in base order, from parts under `loomwright/scripts/test-automate-helpers.d/`, with every assertion and the `<passed>/<total>` result unchanged.

**Problem Statement:**
Maintainers and parallel lanes need the automate-helpers test to be small per concern because every helper change edits it. Currently it is one 6,216-line file (the largest test in the repo) while `automate-helpers.sh` is already split into a dispatcher + nine `automate-helpers.d/` modules. This causes lane collisions on one file and reviews that read far more than the change. Success looks like a runner under ~350 lines plus parts each ≤ ~800 lines, with the same `RESULT: <passed> passed, <failed> failed` line before and after.

## Acceptance Criteria
- [ ] AC1 — Given base `3a03dfa` and the branch, when `bash loomwright/scripts/test-automate-helpers.sh` runs on each in the same checkout environment, then the final `RESULT: <passed> passed, <failed> failed` line is identical (base measured in this lane: `RESULT: 765 passed, 1 failed`, the one failure being the environment-dependent W19 leg), and the set of `ok:`/`FAIL:` lines is identical as a sorted multiset (`grep -E '^  (ok|FAIL): '` output, `LC_ALL=C sort`, `diff` empty).
- [ ] AC2 — Given the branch, every line the runner adds beyond base text sits either inside a `# >>> runner-only` … `# <<< runner-only` block or is a part-source line; when the runner is expanded by deleting those blocks and replacing each part-source line with that part's contents, and the ONE allowed hoist (base lines 3513–3517: the two-line split-index comment, `SPLIT_D="$(mktemp -d)"; SKILL_FILE=…; RUN_DOC=…` and the two `fixtures/automate-loop-split/assemble.sh` calls) is put back at its base position, then the result equals `git show 3a03dfa:loomwright/scripts/test-automate-helpers.sh` byte-for-byte (move-only proof, D6); the hoist itself is checked as "base lines 3513–3517 appear verbatim exactly once in the runner setup, outside any runner-only block". The exact expansion command and its empty `diff` output are recorded in the evidence file.
- [ ] AC3 — Given the parts, when `wc -l loomwright/scripts/test-automate-helpers.d/*.sh` runs, then no part exceeds 800 lines, and each part is a contiguous base line range named for the helper module (or dispatcher subcommand) its legs exercise — `config`, `runfile`, `intake`, `resume`, `gate-eval-harness` + `gate-eval` + `gate-eval-tail` (dispatcher), `rules-gate` (dispatcher cond 7), `learning` (two parts: learning-emit, brief-repair), `reconcile-status`, `ceiling` (runfile.sh `ceiling-check`), `meta`, `plan-waves`, `escalation`, `lane-seams` (dispatcher), `queue-gates` — numbered in base order (`NN-<name>.sh`).
- [ ] AC4 — Given the runner, when a part file is missing or unreadable, then the run aborts with exit 1 and one `FAIL: missing test part: test-automate-helpers.d/<name>.sh` line (the `tat_part` shape in `test-automate-trail.sh`); parts are sourced BY NAME, never by glob.
- [ ] AC5 — Given the runner, when invoked as `bash test-automate-helpers.sh <part-name>...` (part names without `.sh`), then it runs the shared setup and the named parts plus their prerequisites from ONE fixed map in a runner-only block, always in base order and each sourced at most once: `05-gate-eval`, `06-gate-eval-tail` and `07-rules-gate` require `05-gate-eval-harness` (the section E harness, base lines ~1571–1692 — its own contiguous part, since R at base line ~2089 says it "Reuses Section E's harness"); the inline MERGE leg (base 1999–2011) runs iff `05-gate-eval` runs (guarded in a runner-only block). It prints the same `RESULT:` line format and exits 0 iff no leg failed; with no arguments it runs every part exactly as base (the CI / `run-self-tests.sh` invocation is unchanged). An unknown part name exits 1 naming it. Every part, run alone this way, exits 0 except `13-plan-waves` (carries the pre-existing W19 failure); the per-part totals are recorded in the evidence file. No count-sum rule applies (prerequisite legs are counted in each dependent run). No leg is edited, duplicated or reordered.
- [ ] AC6 — Given the CLAUDE.md positive-form invariant grep `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not " | cut -d: -f1 | LC_ALL=C sort -u`, when run on base and branch, then the file list is identical (the three hits in this test — the header comment and the gate all-pass MERGE leg — stay in the runner file: the MERGE leg's lines are kept inline in the runner between the two gate-eval parts so legs still run in base order). `bash loomwright/scripts/test-automate-next-step.sh` (its `SURFACE_BASE` list) stays green, and neither `CLAUDE.md` nor `skills/automate-loop/invariants.md` changes.
- [ ] AC7 — Given the consumer gates, when each runs on the branch, then each passes with the same result as base (or the base result plus the new files counted, explained in the evidence file): `test-automate-helpers-dispatch.sh`, `test-automate-golden.sh`, `test-automate-loop-split.sh` (section H wiring reads the runner and its `test-automate-helpers.d/*.sh` parts), `test-automate-next-step.sh`, `test-no-pipefail-grep-q.sh`, `test-no-fixed-sleep-race.sh`, `test-loop-inventory.sh`, `test-citation-drift.sh`, `scripts/check-test-hermetic.sh`, `scripts/check-vendor-coupling.sh` (the manifest's `test-automate-helpers.sh` reference count is redistributed move-only to the files the references now live in; total unchanged), `scripts/check-locale-prefix.sh`, and `bash scripts/check-version-bump.sh`.
- [ ] AC8 — Given a mutation control, when one `ok "…"` assertion line is deleted from one part in a scratch copy of the scripts dir, then the scratch runner's `passed` total drops by exactly one; the command and both totals are recorded in the evidence file.
- [ ] AC9 — Given the branch, when `git diff --stat 3a03dfa` runs, then `loomwright/scripts/automate-helpers.sh` and every `loomwright/scripts/automate-helpers.d/*.sh` are unchanged (non-goal: no helper change), and the only changed paths are the runner, the new parts, the vendor-coupling manifest (only if AC7 needs it), the changelog fragment and the evidence file.
- [ ] AC10 — Given the change, then a committed evidence file `docs/evidence/as21-split-automate-helpers-tests.md` contains the AC1 before/after `RESULT:` lines and multiset diff, the AC2 byte-equality command and output, the AC3 part table (name, base line range, line count), the AC5 per-part alone totals (with prerequisites), the AC6 grep output on base and branch, the AC7 gate results table and the AC8 mutation totals, and the PR body links to it.
- [ ] AC11 — Given the change, then `changelog.d/as21-split-automate-helpers-tests.md` exists with first line `<!-- bump: patch -->` and a one-line headline, and no version file is hand-edited (lane: fragment only, no bump).

## File Impact Map

| Path | Action | Confidence |
|---|---|---|
| `loomwright/scripts/test-automate-helpers.sh` | modify (becomes runner) | HIGH |
| `loomwright/scripts/test-automate-helpers.d/*.sh` (17 parts, AC3/AC5 names) | create | HIGH |
| `loomwright/docs/vendor-coupling-manifest.json` | modify only if `check-vendor-coupling.sh` breaches | MEDIUM |
| `docs/evidence/as21-split-automate-helpers-tests.md` | create | HIGH |
| `changelog.d/as21-split-automate-helpers-tests.md` | create | HIGH |

## Touched-file invariants

> Grounded at base `3a03dfa`. The worker re-checks each entry before hand-back.

- **`loomwright/scripts/test-automate-helpers.sh`** — keep: the setup preamble verbatim — the hermetic source line `. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"`, `set -uo pipefail`, `HERE="$(cd "$(dirname "$0")" && pwd)"` (parts are sourced, so `$0` still names the runner and every `$HERE` / `$(dirname "$0")` lookup is unchanged), the bundle build `H="$(ah_build_bundle)" || { echo "FAIL: could not build the automate-helpers.sh bundle"; exit 1; }`, the counters `ok() { echo "  ok: $1"; pass=$((pass+1)); }`, and the summary `echo "RESULT: $pass passed, $fail failed"` + `[ "$fail" -eq 0 ] || exit 1`; reuse: the loader shape of `test-automate-trail.sh` — `tat_part() { [ -f "$TAT_D/$1.sh" ] && [ -r "$TAT_D/$1.sh" ] || { echo "  FAIL: missing test part: test-automate-trail.d/$1.sh"; exit 1; }; }` — sourced by name at top level so parts share the runner's functions, stubs and counters; mirror: the CLAUDE.md invariant grep surface (header comment line containing `gh pr merge --squash --match-head-commit <checked head>` and the leg `ok "gate all-pass: MERGE fires 'gh pr merge --squash --match-head-commit <checked head> <url>' exactly once"` stay in this file) and `test-automate-next-step.sh`'s `SURFACE_BASE` list naming `loomwright/scripts/test-automate-helpers.sh`; pinned by: `test-automate-loop-split.sh` section H (`READERS="test-automate-dismissed.sh test-automate-helpers.sh …"` — `wiring()` runs `grep -qF 'fixtures/automate-loop-split/assemble.sh'` on the RUNNER file only, so base lines 3513–3517 are hoisted verbatim into the runner setup (the one allowed hoist, AC2); this also defines `$SKILL_FILE` / `$RUN_DOC` / `$SPLIT_D` for `15-lane-seams` run alone under `set -u`; `wiring_reader` also scans `test-automate-helpers.d/*.sh` for raw index reads), `fixtures/self-test-weights.tsv` (`86	loomwright/scripts/test-automate-helpers.sh` — scheduler weight, keep the path), `test-loop-inventory.sh` (`script:test-automate-helpers.sh` cells need only the file to exist).
- **`loomwright/docs/vendor-coupling-manifest.json`** (only if `check-vendor-coupling.sh` breaches) — keep: the per-file count shape `"loomwright/scripts/test-automate-helpers.sh": 3,`; mirror: the precedent entries `"loomwright/scripts/test-automate-trail.d/04-watcher-branch-mode.sh": 4,` — a moved reference is re-recorded against the part that now holds it, the total unchanged.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Move-only split of test-automate-helpers.sh into runner + parts | all | 1–2 modify, 19 create | `skills/unit-testing/SKILL.md`, `skills/commit/SKILL.md` | LAUNCHABLE |

```yaml
# Subtask 1 — runner + test-automate-helpers.d/ parts (LAUNCHABLE)
provides:
  - {kind: "file", path: "loomwright/scripts/test-automate-helpers.sh"}
  - {kind: "file", path: "loomwright/scripts/test-automate-helpers.d/01-config.sh"}
  - {kind: "file", path: "loomwright/scripts/test-automate-helpers.d/02-runfile.sh"}
  - {kind: "file", path: "loomwright/scripts/test-automate-helpers.d/03-intake.sh"}
  - {kind: "file", path: "loomwright/scripts/test-automate-helpers.d/04-resume.sh"}
  - {kind: "file", path: "loomwright/scripts/test-automate-helpers.d/05-gate-eval-harness.sh"}
  - {kind: "file", path: "loomwright/scripts/test-automate-helpers.d/05-gate-eval.sh"}
  - {kind: "file", path: "loomwright/scripts/test-automate-helpers.d/06-gate-eval-tail.sh"}
  - {kind: "file", path: "loomwright/scripts/test-automate-helpers.d/07-rules-gate.sh"}
  - {kind: "file", path: "loomwright/scripts/test-automate-helpers.d/08-learning-emit.sh"}
  - {kind: "file", path: "loomwright/scripts/test-automate-helpers.d/09-brief-repair.sh"}
  - {kind: "file", path: "loomwright/scripts/test-automate-helpers.d/10-reconcile-status.sh"}
  - {kind: "file", path: "loomwright/scripts/test-automate-helpers.d/11-ceiling.sh"}
  - {kind: "file", path: "loomwright/scripts/test-automate-helpers.d/12-meta.sh"}
  - {kind: "file", path: "loomwright/scripts/test-automate-helpers.d/13-plan-waves.sh"}
  - {kind: "file", path: "loomwright/scripts/test-automate-helpers.d/14-escalation.sh"}
  - {kind: "file", path: "loomwright/scripts/test-automate-helpers.d/15-lane-seams.sh"}
  - {kind: "file", path: "loomwright/scripts/test-automate-helpers.d/16-queue-gates.sh"}
  - {kind: "file", path: "docs/evidence/as21-split-automate-helpers-tests.md"}
  - {kind: "file", path: "changelog.d/as21-split-automate-helpers-tests.md"}
requires: []
lanes:
  - "loomwright/scripts/test-automate-helpers.sh"
  - "loomwright/scripts/test-automate-helpers.d/*"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "docs/evidence/as21-split-automate-helpers-tests.md"
  - "changelog.d/as21-split-automate-helpers-tests.md"
external_requires: []
```

## Part Boundaries (guidance for Subtask 1)

**Suggested part boundaries** (section headers at base `3a03dfa`; the worker verifies exact cut lines so each part starts at its section's `# ====` rule and the inline MERGE leg keeps its preceding comment):

| Part | Base sections | Approx. base lines |
|---|---|---|
| 01-config | A, A7 | 300–519 |
| 02-runfile | B, B9, B10 | 520–1116 |
| 03-intake | C | 1117–1333 |
| 04-resume | D | 1334–1570 |
| *(runner setup, hoisted)* | G's split-index lines (SPLIT_D / SKILL_FILE / RUN_DOC + 2 assemble.sh calls) | 3513–3517 |
| 05-gate-eval-harness | E header + harness (WD/BIN/GH_STUB_DIR, `reset_live`, `pass_ctx`, `gate`, `merges`, the counted E-harness leg) | 1571–~1692 |
| 05-gate-eval | E conditions up to the all-pass MERGE leg | ~1693–1998 |
| *(runner, inline)* | E: "All-pass MERGE fires `gh pr merge --squash` EXACTLY once" leg | 1999–2011 |
| 06-gate-eval-tail | E: TOCTOU, merge-fails, cond-6 mutation control | 2012–2085 |
| 07-rules-gate | R | 2086–2839 |
| 08-learning-emit | F | 2840–3509 |
| 09-brief-repair | G (minus the hoisted 3513–3517) | 3510–3778 |
| 10-reconcile-status | H | 3779–4478 |
| 11-ceiling | I1–I7 | 4479–4610 |
| 12-meta | branch mode: meta-entry / meta-push-failed | 4611–4761 |
| 13-plan-waves | W, X | 4762–5428 |
| 14-escalation | ESC | 5429–5826 |
| 15-lane-seams | LANE, SINGLELANE, LANEGUARD | 5827–5972 |
| 16-queue-gates | QG1–QG4 | 5973–end of legs |

The header comment block (lines 1–202) stays in the runner unchanged; append one short paragraph naming the parts directory and the `[<part>...]` argument.

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/commit/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Base already fails one leg: W19 (`real 22-split-automate-engine-surfaces.md ## Touches parses`) reads the gitignored queue under `.supervisor/requirements/` and fails in this lane clone (`no …/.agent/companions.json`) | MEDIUM | AC1 compares base vs branch in the SAME checkout; do not "fix" W19 (move-only, D6). Record it in the evidence file as pre-existing. |
| A leg depends on state an earlier part set, so running a part alone (AC5) fails | MEDIUM | Known cases handled by design: E harness → its own prerequisite part; G's split-index lines → the one hoist. Any further dependency the worker finds is added to the AC5 prerequisite map (never a new hoist, never a leg edit) and listed in the evidence file. |
| A text-reading test pins content now living in a part (e.g. section-H wiring, sleep/pipefail scanners, vendor-coupling counts) | MEDIUM | AC7 runs every consumer named in `grep -rlF test-automate-helpers` over `loomwright/scripts/` and the root gates; fix only manifests/allowlists that count per file, move-only. |
| Feasibility (Phase 2.5) — scope: ~6,200 moved lines | LOW | Cut with a script by line range (`sed -n 'a,bp'`), then prove AC2 byte-equality instead of hand-moving. |
| Invariant-grep surface drift if the MERGE leg moved into a part | HIGH | AC6: keep those lines inline in the runner; `test-automate-next-step.sh` guards it. |
| Full test run is ~3 min and the whole `ci-local.sh` ~15 min | LOW | Run the targeted consumers first; `bash scripts/ci-local.sh` once before push (`--wait` to poll). |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-18-as21-split-automate-helpers-tests.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-10-18T20:43:06Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/609
- **Branch:** feature/as21-split-automate-helpers-tests
- **Files changed:** 21
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Move-only split of test-automate-helpers.sh into a runner + 17 parts under test-automate-helpers.d/ (RESULT 765/1 identical to base; W19 pre-existing). Phase 4.5: iter1 3 MEDIUM (part-list agreement, PATH bash -n, no committed loader test) → 737ebb5; iter2 1 MEDIUM (source-line path unchecked) → bd39cc8; iter3 PASS (1 LOW nit dismissed). Loader test deferred: brief AC9/AC1 forbid a new file — follow-up test-automate-helpers-modules.sh. Driver restarted once after sn_brief_subtasks misread a guidance table under ## Subtask Structure.

## Not verified
- **bash scripts/ci-local.sh on base 3a03dfa** — not run (~20 min pool); inferred from base test-automate-helpers.sh exiting 1 with W19 in this checkout (subtask 1)
- **GitHub CI run of the branch (W19 expected to skip without the gitignored queue)** — worker did not push; skip behaviour taken from the test header, not observed on a runner (subtask 1)
