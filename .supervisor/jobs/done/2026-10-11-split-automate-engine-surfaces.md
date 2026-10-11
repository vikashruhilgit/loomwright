# Supervisor Job: Split the /automate engine's four shared surfaces (move-only, anchor index kept)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-11-082328/L1 (lane L1 clone of the loomwright marketplace repo)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (five tests outside the requirement's original Touches read the split surfaces verbatim — owner widened Touches to them, path re-point only; see C1)
- **Source requirement:** .supervisor/requirements/parallel-automate/22-split-automate-engine-surfaces.md
- **Base commit:** da2fac5d4f54bea55fc91700ebe5729755f587ef

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Markdown + bash 3.2 + awk; same toolset the pa/11 split (`test-result-schemas-split.sh`) used. |
| 2 | Dependency Availability | GO | No new dependency. |
| 3 | Architecture Fit | GO | Mirrors the shipped `docs/RESULT_SCHEMAS.md` → `docs/result-schemas/` index pattern and the `automate-helpers.d/` family-file loader. |
| 4 | Scope vs Supervisor Capability | CAUTION | ~35 files incl. moved text (>800 changed lines) — `context-bound`; two groups (docs split / helpers usage split) run in order because both must edit `vendor-coupling-manifest.json`. |
| 5 | Hard Blockers | CAUTION | Five tests OUTSIDE Touches grep literal text in `automate-loop/SKILL.md` / `commands/automate.md` / `result-schemas/automate-run.md`, and `test-result-schemas-split.sh` rejects any extra file directly in `docs/result-schemas/`. Owner decision 2026-10-11 (lane L1 question `pa22 scope`): widen Touches to those five tests, path re-point only (C1). `test-result-schemas-split.sh` is NOT edited (C3). New files under `loomwright/commands/` would be counted as new commands — forbidden (C4). |

**Overall Verdict:** CAUTION

## Task
**Goal:** Split `skills/automate-loop/SKILL.md`, `commands/automate.md`, `docs/result-schemas/automate-run.md` and the `automate-helpers.sh` usage header + `--help` golden by concern, move-only, keeping every pre-split anchor resolvable at its old path, so two engine items that change different concerns edit different files.

**Problem Statement:**
The `/automate` engine maintainers need engine items to run in parallel lanes because every remaining engine item edits the same four files.
Currently `plan-waves` serialises af/34, pa/18, af/36 and pa/21 one per wave on these four surfaces. This costs one wave per item.
Success looks like a split where each concern lives in its own file, every existing test passes with no assertion edited except path re-points inside Touches, `--help` is byte-identical to today's golden, and the concatenated split text reproduces the original byte-for-byte.

## Acceptance Criteria
- [ ] AC1 — Given the split, when the skill index `loomwright/skills/automate-loop/SKILL.md` is read, then it keeps its YAML frontmatter (name `automate-loop`, version bumped as a minor), every pre-split `## §N` / `##` / `###` heading text appears in it (each either unchanged in place or as an index entry naming the split file that now holds the section), and the per-concern bodies live in new files under `loomwright/skills/automate-loop/` (recommended grouping: intake + per-item loop §2, §6–§8; resume §4–§5; modes + merge gate §9–§10; closeout/invariants + branch mode §11, §13; lanes §14 — §1, §1.5, §3, §12, Anti-Patterns, Related, Quality Gates may stay in the index).
- [ ] AC2 — Given the split skill files, when a new test `loomwright/scripts/test-automate-loop-split.sh` concatenates them in the documented order (index segments + split files), then the result equals the pre-split `SKILL.md` text byte-for-byte (the original is committed as a fixture or reconstructed from `git show da2fac5:…`; the test must not need git history if run in CI — commit a fixture), and the same byte-identity check holds for `result-schemas/automate-run.md` and for any text moved out of `commands/automate.md`.
- [ ] AC3 — Given every tracked file (CHANGELOG.md excluded), when the new test collects each citation of the four surfaces (`automate-loop/SKILL.md` + `§N` or a quoted heading anchor; `commands/automate.md` + anchor; `automate-run.md`/`§AUTOMATE_RUN` + anchor), then every cited anchor resolves — a heading at the cited path or an index entry there naming a split file that holds that heading; a dangling citation fails the test. **Mutation control:** removing one index entry that a citation uses makes the test fail (mutant gated on non-empty + differs + exactly one line fewer).
- [ ] AC4 — Given C1 (below), when the five widened-Touches readers — `test-automate-dismissed.sh`, `test-non-interactive-gates-seam.sh`, `test-run-lock.sh`, `test-classify-risk.sh`, `test-rules-gate-seams.sh` — run, then each passes with only path re-points (each reads the concatenation of the index + split files in documented order, the pa/11 `RS_ALL` idiom; no assertion text, regex or expected order edited), and `test-result-schemas-split.sh` passes with zero edits.
- [ ] AC5 — Given `commands/automate.md`, when it is thinned, then no new file is created under `loomwright/commands/` (C4), its frontmatter and `/automate` usage block are unchanged, every literal an existing test greps in it is still in it (C1), and its Step 0 lists every new skill split file to Read (so the inline engine still loads the whole protocol at run time).
- [ ] AC6 — Given `result-schemas/automate-run.md`, when it is split, then it stays the `## AUTOMATE_RUN` file `RESULT_SCHEMAS.md` points at, keeps an index entry for every pre-split `###` section, and its moved sections live under a NEW subdirectory `loomwright/docs/result-schemas/automate-run/` (never directly in `docs/result-schemas/` — C3).
- [ ] AC7 — Given the helper families, when `bash loomwright/scripts/automate-helpers.sh --help` (and `-h`, no-arg) runs, then stdout equals today's `loomwright/scripts/fixtures/automate-helpers-help.golden` byte-for-byte. Golden lines 1–53 are the usage list; lines 54–76 are incidental `#   ` comment lines from family bodies and the dispatcher's gate-eval comments (they stay where they are, untouched). Each usage line moves to the family file whose function implements it: config (lines 1–3), runfile (4–12, incl. `current-escalation`, implemented in runfile.sh), intake (13–14), resume (15–16), learning (18–19), escalation (20 `escalation-cause`), reconcile-status (21), meta (34–35), plan-waves (36–37). These stay in the dispatcher header: `gate-eval` (17, implemented in the dispatcher), the trail/dismissed segment 22–33 **including `closeout-classify` (25)** (kept beside the closeout lines it sits between), and the lanes segment 38–53. Assembly is an explicit ordered segment list in the dispatcher, never a glob: config, runfile, intake, resume, [hdr gate-eval], learning, escalation, reconcile-status, [hdr 22–33], meta, plan-waves, [hdr 38–53]; then the incidental lines exactly as the bundle grep emits them today. Usage-block lines carry a marker distinct from `#   ` (e.g. `#:  `) so the incidental grep never double-counts them.
- [ ] AC8 — Given the per-family usage, when the golden is checked, then the expected output is one fixture per segment under `loomwright/scripts/fixtures/automate-helpers-help/` (plus one for the incidental lines), so adding a subcommand to one family edits only that family's file and fixture. `test-automate-helpers-dispatch.sh` check 5 compares `--help` to the ordered concatenation of those fixtures (the single full golden `automate-helpers-help.golden` is retired — deleted — so no shared file is edited per subcommand; segment fixtures are named `<segment>.golden`, e.g. `config.golden`, `runfile.golden`, `hdr-trail.golden`, `hdr-lanes.golden`, `incidental.golden`). The vendor-coupling allowance for the relay-hook help line moves with it (C6). **Mutation controls:** a fixture set missing one help line fails, and a family with its usage block removed changes `--help` and fails.
- [ ] AC9 — Given the split, when `bash scripts/ci-local.sh` runs, then it passes with the same `<passed>/<total>` + SKIP counts as the base (baseline recorded on base `da2fac5` and on the branch), and no test assertion was edited except path re-points inside Touches (each listed in the PR body).
- [ ] AC10 — Given the PR, when it is opened, then its body carries the Scope 5 state traces — a fresh run (intake → PICK → per-item loop → park), RESUME (glob + reconcile, incl. a crashed run), the `--auto-merge` gate (all seven conditions), the dismissed-findings decision step, and closeout (watcher + `closeout-others` + `finalize-empty`) — each naming the file + section read at every step, and the re-run of the 2026-10-07 overlap table plus `plan-waves --max 5 --explain` on the remaining queue (or the shared file that still prevents co-placement); and a `changelog.d/parallel-automate-22-split-automate-engine-surfaces.md` fragment ships (no version bump). The PR body lists every created file, every path re-point (C1/C2), and the `## Touches` additions an operator must fold into the requirement (the five tests, `automate-helpers.d/escalation.sh`, the new files).
- [ ] AC11 — Given requirement Validation item 3 (one real `/automate` item on this branch's plugin through park), when the PR is opened, then its body carries the exact live-run command (`claude -p --plugin-dir <branch checkout>/loomwright "/loomwright:automate --folder <scratch dir> --non-interactive-fallback"`) and EITHER the run file's `## Current` + the lines showing the split files were read, OR an explicit `live run: NOT RUN in-lane — opens a real PR; owner validation before merge` line. Never a claimed run that did not happen.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- Wording that carries a contract — a heading a gate greps for, a sentence that states a guarantee — is treated as an interface: renaming it is a change to that interface and its consumers move with it.
  - id: documentation-wording-that-carries-a-contract-a-heading-a-gate-greps-for-a-sentence-that-states-a-guarantee-is-treated-as-an-interface-renaming-it-is-a-change-to-that-interface-and-its-consumers-move-with-it
  - enforcement: advisory
  - category: documentation
  - check (data only, NOT executed by this reader): (none)
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

## Design constraints (binding on both subtasks)
- **C1 — widened-Touches readers are re-pointed, never reworded.** Owner decision (2026-10-11): `test-automate-dismissed.sh` (its `SK=` reader, the `file|phrase` table under its single-drain leg, the `sub_body` extraction of `### Dismissed-findings decision step (before the park)`, the `p_rec < p_ask < p_run` order check, its `C8` grep of `commands/automate.md`, and its direct `$RSD/automate-run.md` greps for the `pending_decisions` template line and `owned drain started (fix-now re-drain) — `), `test-non-interactive-gates-seam.sh` (`AUTO_SKILL` / `AUTO_CMD`, checks (e)–(h)), `test-run-lock.sh` (`check_acquire_has_session_id "automate-loop SKILL PICK (reference shape)"`), `test-classify-risk.sh` (`LOOP=`), `test-rules-gate-seams.sh` (`AL=`) join Touches. Each reader of a moved section is re-pointed to a concatenation of the index + split files in the documented order (one shared helper or the `RS_ALL` idiom). An order check must still hold over that concatenation. No assertion text, regex or expected count changes. Every re-point is listed in the PR body.
- **C2 — re-point only inside (widened) Touches.** Inside-Touches tests that read a moved section (`test-automate-helpers.sh` `SKILL_FILE=` and its `automate-run.md` grep; `test-automate-trail.sh` `SKILL=`, including its absence scans over `result-schemas/*.md`) get the same re-point. Citations in files outside Touches (e.g. `session-resume.sh`, `build-handoff.sh`) are NOT edited; they keep resolving through the index (AC3).
- **C3 — `docs/result-schemas/` stays one file per top-level heading.** `test-result-schemas-split.sh` fails on any unreferenced file directly in `docs/result-schemas/`, and the RS_ALL / `SCHEMAS_ALL_DOC` concatenations glob `result-schemas/*.md` non-recursively — so automate-run sub-files go in `docs/result-schemas/automate-run/`, and any row an out-of-Touches test greps (e.g. the `suppressed_default_dispatch` `## Current` fields row) stays in `automate-run.md`.
- **C4 — no new file under `loomwright/commands/` or new directory under `loomwright/skills/`.** Either would change the command/skill count (`check-doc-currency.sh` counts `skills/` depth-1 dirs; companions treat any new `commands/*` as a new command).
- **C6 — `vendor-coupling-manifest.json` is edited by both subtasks, in order.** `scripts/check-vendor-coupling.sh` scans the whole tracked tree (`git ls-files`), so counts move with the moved text. Subtask 1 re-baselines the doc moves. Subtask 2 runs after it and re-baselines the help-fixture/family moves, e.g. the relay-hook help line's `ask_user` allowance ("golden copy of automate-helpers.sh --help"). The reason form is "moved by parallel-automate/22 split — no reference added".
- **C5 — move-only.** No engine behaviour, gate, schema field or step order changes; moved text is byte-identical (AC2); index entries are the only new prose besides the new test, per-family fixtures and the changelog fragment.

## Touched-file invariants

> Grounded at base `da2fac5d4f54bea55fc91700ebe5729755f587ef`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/automate-helpers.sh`** — keep: the family loader's fail-closed rule `die "missing family file: automate-helpers.d/$1.sh"` and "Listed by name, never globbed: a stray file in automate-helpers.d/ is never sourced."; keep the dispatcher's case arms byte-unchanged; reuse: `_ah_bundle` (self-contained — "the test harness evals this one function") for assembly rather than a second reader; mirror: the help pipeline `_ah_bundle | grep -E '^#   [a-z]' | sed 's/^#   /  /'` currently also emits 17 incidental `#   ` comment lines from `escalation.sh`, `learning.sh`, `meta.sh`, `reconcile-status.sh`, `resume.sh` — the golden contains them, so the new assembly must still emit them at the same positions (AC7 byte-identity); pinned by: `test-automate-helpers-dispatch.sh` (`GOLDEN="$HERE/fixtures/automate-helpers-help.golden"`), `test-automate-helpers.sh` (`grep -q "^  $s_ " <<<"$helpout_d"`), `test-automate-trail.sh`.
- **`loomwright/scripts/automate-helpers.d/*.sh` (config, escalation, intake, learning, meta, plan-waves, reconcile-status, resume, runfile)** — keep: each family file's existing code and comments byte-unchanged except the added usage block; keep the sourcing order (`# >>> automate-helpers.d/<name>.sh` markers) since `_ah_bundle` "reproduces that file's line order" and `test-automate-helpers.sh` runs the bundle as one file; pinned by: `test-automate-helpers-dispatch.sh` (checks 1–5), `test-automate-helpers.sh`.
- **`loomwright/scripts/test-automate-helpers-dispatch.sh`** — keep: check 5's byte-for-byte `help_matches` (files + `cmp`, exit 0, empty stderr) and its mutation control "golden mutant (one help line removed)"; keep the `# run-self-tests: early` marker behaviour (header: "a stale --help golden fails the run in seconds"); update the "ADDING A SUBCOMMAND? Regenerate the golden" instruction to the per-family form.
- **`loomwright/scripts/test-automate-helpers.sh` / `loomwright/scripts/test-automate-trail.sh`** — keep: every assertion string; only re-point `SKILL_FILE="$HERE/../skills/automate-loop/SKILL.md"` / `SKILL="$HERE/../skills/automate-loop/SKILL.md"` (and the `automate-run.md` grep `^- pause_reason: .*|live_lane|null`) to the index + split concatenation when the asserted text moved (C2); keep the `pass`/`fail` shadow-tally convention in test-automate-trail.sh ("A shadow tally the summary cross-checks").
- **`loomwright/scripts/test-automate-dismissed.sh`, `test-non-interactive-gates-seam.sh`, `test-run-lock.sh`, `test-classify-risk.sh`, `test-rules-gate-seams.sh` (widened Touches, C1)** — keep: every assertion string, regex, count and order check byte-unchanged, incl. test-automate-dismissed's `p_rec < p_ask < p_run` order check and its `$RSD/automate-run.md` greps; re-point only the reader variables `SK="$REPO/loomwright/skills/automate-loop/SKILL.md"`, `AUTO_SKILL="$PLUGIN_ROOT/skills/automate-loop/SKILL.md"` / `AUTO_CMD="$PLUGIN_ROOT/commands/automate.md"`, the `check_acquire_has_session_id "automate-loop SKILL PICK (reference shape)"` target, `LOOP="$HERE/../skills/automate-loop/SKILL.md"`, `AL="loomwright/skills/automate-loop/SKILL.md"` to the documented-order concatenation when their asserted text moved; keep each file's `hermetic-test-env.sh` sourcing and `ok`/`no` tally shape.
- **`loomwright/docs/vendor-coupling-manifest.json`** — keep: its per-file count map and reason map shape (`"loomwright/skills/automate-loop/SKILL.md": 18`, `"loomwright/docs/result-schemas/automate-run.md": "moved by parallel-automate/11 split — no reference added"`); mirror: counts move with the moved text to the new files (same "moved by … split — no reference added" reason form); re-baseline with the repo's own vendor-coupling checker, never hand-guessed.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Docs split: automate-loop SKILL.md + commands/automate.md + automate-run.md, anchor index, split/citation test, in-Touches re-points | AC1–AC6, AC9, AC10, AC11 | 15 modify, ~10 create | `skills/unit-testing/SKILL.md`, `skills/claude-md-validation/SKILL.md` | LAUNCHABLE |
| 2 | Helpers usage header per family + per-family golden + dispatch test | AC7, AC8, AC9 | 12 modify, ~13 create | `skills/unit-testing/SKILL.md` | BLOCKED (by #1) |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/test-automate-loop-split.sh"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/SKILL.md", name: "## §6 — The per-item loop"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/SKILL.md", name: "## §10 — Trusted auto-merge gate (7 conditions, fail CLOSED, SELF-RESOLVING)"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/automate-run.md", name: "## AUTOMATE_RUN"}
  - {kind: "file", path: "changelog.d/parallel-automate-22-split-automate-engine-surfaces.md"}
  - {kind: "file", path: "loomwright/docs/vendor-coupling-manifest.json"}
requires: []
lanes:
  - "loomwright/skills/automate-loop/**"
  - "loomwright/commands/automate.md"
  - "loomwright/commands/agent-help.md"
  - "loomwright/docs/result-schemas/automate-run.md"
  - "loomwright/docs/result-schemas/automate-run/**"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/skills/SKILLS_INDEX.md"
  - "CLAUDE.md"
  - "loomwright/scripts/test-automate-loop-split.sh"
  - "loomwright/scripts/fixtures/automate-loop-split/**"
  - "loomwright/scripts/test-automate-helpers.sh"
  - "loomwright/scripts/test-automate-trail.sh"
  - "loomwright/scripts/test-automate-dismissed.sh"
  - "loomwright/scripts/test-non-interactive-gates-seam.sh"
  - "loomwright/scripts/test-run-lock.sh"
  - "loomwright/scripts/test-classify-risk.sh"
  - "loomwright/scripts/test-rules-gate-seams.sh"
  - "changelog.d/parallel-automate-22-split-automate-engine-surfaces.md"
external_requires: []

# Subtask 2
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "_ah_bundle"}
  - {kind: "file", path: "loomwright/scripts/fixtures/automate-helpers-help/config.golden"}
  - {kind: "file", path: "loomwright/scripts/test-automate-helpers-dispatch.sh"}
requires:
  - {from: "1", kind: "file", path: "loomwright/docs/vendor-coupling-manifest.json"}
lanes:
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/automate-helpers.d/*.sh"
  - "loomwright/scripts/fixtures/automate-helpers-help.golden"
  - "loomwright/scripts/fixtures/automate-helpers-help/**"
  - "loomwright/scripts/test-automate-helpers-dispatch.sh"
  - "loomwright/docs/vendor-coupling-manifest.json"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2   (Subtask 2 requires Subtask 1's vendor-coupling-manifest.json re-baseline; legal sequential sharing — C6)
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | `loomwright/docs/vendor-coupling-manifest.json` (C6) | YES — Subtask 2 after Subtask 1. Subtask 2 never edits test-automate-helpers.sh / test-automate-trail.sh: `--help` stays byte-identical, so their help assertions need no change |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after Subtask 1)
- **Recommended workers:** 1
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/claude-md-validation/SKILL.md` |
| 2 | `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): five tests outside the original Touches read literal text (and one passage order) from the split surfaces | HIGH | Owner widened Touches (path re-point only, C1). Re-point to the documented-order concatenation. Run the tests before and after. AC4 forbids any assertion edit. |
| Negative (absence) scans silently lose coverage of moved text — e.g. test-automate-dismissed's unqualified drain-ownership loop over `$SK` + `RS_ALL` (`result-schemas/*.md`, non-recursive), and test-automate-trail's decision-9 grep over `result-schemas/*.md`. A fail-SAFE reader feeding a correctness check then reads "clean" | MEDIUM | Re-point those scans to include the split files (`skills/automate-loop/*.md`, `docs/result-schemas/automate-run/*.md`). test-automate-loop-split.sh asserts every absence-scan target set covers every split file (mutation: drop one split file from a scan ⇒ FAIL). |
| Feasibility (Phase 2.5): `test-result-schemas-split.sh` rejects unreferenced files directly in `docs/result-schemas/` | MEDIUM | C3: automate-run sub-files in `docs/result-schemas/automate-run/`. |
| Feasibility (Phase 2.5): new files, the five widened tests and `automate-helpers.d/escalation.sh` (it receives the `escalation-cause` usage line) are not in the requirement's `## Touches` | MEDIUM | New files cannot collide with another item; the sibling lane (host-contract/03) touches none of them. Name every created file and the escalation.sh edit in the PR body so the operator can re-point open items' Touches after merge (requirement Scope 6). |
| Feasibility (Phase 2.5): the inline engine reads the skill at run time — a section moved out of `SKILL.md` but not listed in `commands/automate.md` Step 0 is silently not loaded | HIGH | AC5: Step 0 lists every split file; the AC10 state traces name the file read at each step; the new test asserts every split file is named in Step 0. |
| Prior churn (postmortem ledger): `automate-loop/SKILL.md` (24), `automate-helpers.sh` (23), `commands/automate.md` (14), the help golden (6), `automate-run.md` (5) — recurring `drain_churn` + `self_heal_churn` | MEDIUM | Reviewers check byte-identity (AC2) and help identity (AC7) mechanically before prose; doc-currency green is necessary not sufficient (grep old anchors repo-wide). |
| `--help` assembly order — the golden interleaves the 59 header lines and 17 incidental family comment lines in bundle order | MEDIUM | Subtask 2 proves byte-identity with `cmp` before any other change; mutation control per AC8. |
| Vendor-coupling counts move with text | LOW | Re-baseline with the repo's checker; reason "moved by parallel-automate/22 split — no reference added". |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-11-split-automate-engine-surfaces.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-10-11T06:31:48Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/470
- **Branch:** feature/pa22-split-automate-engine-surfaces
- **Files changed:** 54
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Move-only split of the automate-loop skill, commands/automate.md and automate-run.md into anchor indexes + split files (byte-identical reassembly), per-family helper usage + per-segment --help fixtures (--help byte-identical); branch ci-local PASS 148/148; Phase 4.5 iter 1 FAIL (AC10 PR-body evidence) → PR body fixed → iter 2 PASS; ground truth 2/2; risk high_risk true (advisory).

## Not verified
- **live /automate item through park (AC11)** — NOT RUN in-lane — opens a real PR; owner validation before merge (subtask 1)
- **AC10 half 1 (four surfaces no longer shared after re-point)** — open items' Touches still pre-split; plan-waves places pa/18, af/36, af/39 in waves 1/2/3 (subtask 1 / fix-1)
