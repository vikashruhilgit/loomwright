# Supervisor Job: Split the shared hotspot files — generated skills index, automate-helpers.sh family files, RESULT_SCHEMAS.md per-schema files

## Environment
- **Project:** ai-agent-manager-lanes-v2/s3-f (lane checkout; repo `vikashruhilgit/loomwright`)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 2 (branch mode ON — `.supervisor/` run history lives on the metadata branch; this item's sibling lanes pa/16 and agnostic/04 run in the same wave)
- **Source requirement:** .supervisor/requirements/parallel-automate/11-split-shared-hotspot-files.md
- **Base commit:** a14db34935cf2abab56a17df5beff40baa4674f5

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2-safe shell + markdown; no new language or dependency |
| 2 | Dependency Availability | GO | `plan-waves --explain` (item 10) is on `main` (`automate-helpers.sh` header + implementation); jq/awk/git already hard CI deps |
| 3 | Architecture Fit | CAUTION | The requirement says `test-automate-helpers.sh` passes "unchanged"; 17 of its mutation controls `sed` the monolith's text into a mutant copy (`"$H" > "$MUT/automate-helpers.sh"`), so a split cannot leave that file byte-identical. Resolved below by a single-line `$H` re-resolution to a test-time bundle (no assertion, no mutation line edited) — see Risk Assessment |
| 4 | Scope vs Supervisor Capability | CAUTION | ~3,300 + ~3,500 lines move; three file-disjoint groups → split `genuine-parallelism`, plus one dependency-ordered integration subtask |
| 5 | Hard Blockers | GO | none; Validation 2 (a real sequential `/automate` run after the split) can only run after release + reinstall — recorded as a post-merge check, not a PR gate |

**Overall Verdict:** CAUTION

## Task
**Goal:** Stop shared registries and monoliths from forcing separate waves: generate the skills index from SKILL.md frontmatter (and drop its companion rule), split `loomwright/scripts/automate-helpers.sh` into per-family files under `loomwright/scripts/automate-helpers.d/` behind a byte-identical CLI, and split `loomwright/docs/RESULT_SCHEMAS.md` into per-schema files under `loomwright/docs/result-schemas/` with `RESULT_SCHEMAS.md` kept as the heading-preserving index — measured before and after with `plan-waves --explain`.

**Problem Statement:**
The S3 wave operator needs items that edit different helpers, schemas or skills to share a wave, because the planner compares paths, not hunks.
Currently, `SKILLS_INDEX.md` is companion-added to every `skills/*/SKILL.md` edit, `automate-helpers.sh` holds every helper in one 3,349-line file, and `RESULT_SCHEMAS.md` holds every schema in one 3,506-line file. This makes the open backlog plan to 12 waves at `--max 5`.
Success looks like fewer `conflicts with` lines naming these three paths in a before/after `plan-waves --explain`, with every existing test, CLI and anchor unchanged.

### Scope 1 — measured BEFORE (recorded here; Scope 1 of the requirement)
`plan-waves <14 open S3 items> --max 5 --explain` at `a14db34` (items: agnostic/04, af/31, af/33, af/34, ms/05, ms/07, pa/05, pa/06, pa/07, pa/11, pa/12, pa/14, pa/16, pa/18; real `.agent/companions.json`): **12 waves, 140 `conflicts with` lines**. Ranked by path:
`SKILLS_INDEX.md` 38 · `RESULT_SCHEMAS.md` 22 · `automate-loop/SKILL.md` 16 · `ARCHITECTURE_CONTRACTS.md` 12 · `automate-helpers.sh` 8 · `commands/automate.md` 5 · `commands/agent-help.md` 5 · `test-automate-helpers.sh` 3 · others ≤ 3.
Without pa/11 itself in the set: 11 waves, 115 lines (`SKILLS_INDEX.md` 27 · `automate-loop/SKILL.md` 16 · `RESULT_SCHEMAS.md` 14 · `ARCHITECTURE_CONTRACTS.md` 12).
`automate-loop/SKILL.md` ranks 3rd, not top ⇒ per the requirement's Scope 4 it stays OUT of this item (recorded as a follow-up).

## Acceptance Criteria
- [ ] AC1 — Given every `{plugin}/skills/*/SKILL.md` frontmatter, when `bash scripts/check-skills-index-sync.sh --write` runs, then each plugin's `SKILLS_INDEX.md` Version and Last Updated cells (and the row set) are regenerated from frontmatter `version`/`lastUpdated`, curated cells (Skill Name, Agent Consumers, Token Est.) are preserved, and a second `--write` is a byte-for-byte no-op.
- [ ] AC2 — Given the committed index, when `bash scripts/check-skills-index-sync.sh` (gate mode) runs, then it regenerates into a temp file and diffs: clean ⇒ exit 0; a hand-edited Version or Last Updated cell, a missing row, or a ghost row ⇒ exit 1 naming the row; its `--self-test` proves both directions.
- [ ] AC3 — Given `.agent/companions.json`, when it is read, then the `{"when": "loomwright/skills/*/SKILL.md", "add": ["loomwright/skills/SKILLS_INDEX.md"]}` rule is gone (all `new: true` rules unchanged), and a plan-waves fixture proves two items editing two different skills' bodies share one wave.
- [ ] AC4 — Given the split, when any `automate-helpers.sh <subcommand>` is invoked with the same arguments as on base, then stdout, stderr and exit code are identical — including `--help` and no-arg output, which today greps `^#   [a-z]` over the WHOLE file (non-header matches exist inside the reconcile-item, gate-eval, brief-repair, reconcile-status and meta-entry sections), so the help arm greps the in-memory bundle expansion (dispatcher with each family file expanded at its source point), whose line order equals base. The dispatcher keeps the header, the shared predicates, `gate_eval` and `main`, and sources each family file from `"$(dirname "$0")/automate-helpers.d/"` at the position its code held in the monolith; a missing or unreadable family file fails CLOSED (non-zero exit, named file), never a silent no-op. A test diffs base `--help` (from `git show <base>:loomwright/scripts/automate-helpers.sh`) against the branch's real dispatcher `--help`.
- [ ] AC5 — Given `loomwright/scripts/test-automate-helpers.sh`, when it runs against the split, then it passes with the same pass/skip totals as on base, and `git diff` of that file shows only the `$H` resolution hunk (no `ok`/`no` line, expected value or mutation `sed` line edited).
- [ ] AC6 — Given a new `loomwright/scripts/test-automate-helpers-dispatch.sh`, when it runs, then every subcommand in the dispatcher's `case` table reaches its function (never `unknown subcommand`), and a mutant that removes one family file or breaks one family's function name makes the test fail.
- [ ] AC7 — Given `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "`, when it runs after the split, then it resolves to exactly the same five surfaces CLAUDE.md lists today (`gate_eval` stays in `automate-helpers.sh`, so no invariant doc changes).
- [ ] AC8 — Given the split schema doc, when any reader looks for a schema, then `loomwright/docs/result-schemas/` holds one file per top-level schema section (fence-aware), `RESULT_SCHEMAS.md` keeps its path, its preamble, and every top-level `## ` heading in the original order each followed by a pointer to its split file, and the concatenated split bodies equal the original section bodies byte-for-byte.
- [ ] AC9 — Given every reader that PARSES `RESULT_SCHEMAS.md` (listed in the PR body, each by file and the check it runs), when the full loop runs on the split, then each still passes, reading the split file it needs; and `test-citation-drift.sh` is green with every pin's quoted text unchanged — only the cited path/line of the THREE pins that cite `RESULT_SCHEMAS.md:<N>` re-derived to the split file now holding the text: `loomwright/scripts/format-twin-delta.sh` (currently `:841` → re-derive to `result-schemas/session-end-jsonl.md:<N>`), `loomwright/skills/self-heal-advisory/SKILL.md` (currently `:614` → `result-schemas/code-review-result.md:<N>`) and the in-file pin in the SUPERVISOR_RESULT section (currently `docs/RESULT_SCHEMAS.md:614`, the `category: enum […]` line → `docs/result-schemas/code-review-result.md:<N>`). `CHANGELOG.md`'s frozen mention and the fixture brief under `loomwright/scripts/fixtures/corpus-briefs/` are outside the scan and listed in the PR body as checked and left alone.
- [ ] AC10 — Given `loomwright/docs/vendor-coupling-manifest.json`, when `check-vendor-coupling.sh` runs on the integrated branch, then it passes with the flat total unchanged (allowances moved from the monoliths to the new paths with a `moved by parallel-automate/11 split — no reference added` reason).
- [ ] AC11 — Given the integrated branch, when `plan-waves --explain` re-runs on the same 14 items, then the PR body records before/after counts for `SKILLS_INDEX.md`, `automate-helpers.sh` and `RESULT_SCHEMAS.md` — measured as-is AND with each open item's Touches re-pointed (in a scratch copy) to the family/split files its own scope names — and both counts for `SKILLS_INDEX.md` are lower than before.
- [ ] AC12 — Given `bash scripts/ci-local.sh` on the integrated branch, then it is green (or every red leg is shown red on a clean base worktree too), with `<passed>/<total>` and SKIP counts reported for base and branch.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Generated skills index + drop the SKILL.md ⇒ index companion | AC1, AC2, AC3 | 4 modify, 1 create | `skills/unit-testing/SKILL.md`, `skills/ci-cd/SKILL.md` | LAUNCHABLE |
| 2 | Split `automate-helpers.sh` into `automate-helpers.d/` family files | AC4, AC5, AC6, AC7 | 2 modify, ~9 create | `skills/unit-testing/SKILL.md`, `skills/automate-loop/SKILL.md` (reference) | LAUNCHABLE |
| 3 | Split `RESULT_SCHEMAS.md` into `result-schemas/` + keep every parser working | AC8, AC9 | ~15 modify, ~30 create | `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 4 | Integration: vendor-coupling re-baseline, after-measurement, changelog fragment | AC10, AC11, AC12 | 1 modify, 1 create | `skills/ci-cd/SKILL.md` | BLOCKED (by #1, #2, #3, #5) |
| 5 | Remediation (adjudication B, owner 2026-10-06): keep the 3 out-of-lane tests green on the split + write the Scope-4 state-trace table | AC12 (part), AC9 (state-trace) | 3 modify, 1 create | `skills/unit-testing/SKILL.md` | BLOCKED (by #2, #3) |

### Subtask 1 — Generated skills index (detail)
- **Regeneration path (decision):** per-PR. A PR that changes a skill's frontmatter `version`/`lastUpdated` runs `--write` and commits the index; the gate fails CI otherwise. Consequence (disclosed in Risk Assessment): with the companion rule gone, such an item must declare `loomwright/skills/SKILLS_INDEX.md` in its own Touches; two that do not can share a wave and meet a git conflict on the index, resolved mechanically by re-running `--write` (generated content). Release-time regeneration in `bump-version.sh` was rejected: between bumps the gate would have to tolerate a stale Version cell, which weakens it.
- **Cells generated (deviation from the requirement's "name, version, description"):** the index has no description column and its Skill Name is a curated display name (`Supervisor Readiness`, not the slug), so the generator owns the row set, Version, Last Updated and the `**Total: N skills**` line (derived from the row count, per the advisory count-claim house rule); Skill Name, Agent Consumers and Token Est. stay curated.
- Extend `scripts/check-skills-index-sync.sh` (keep its multi-plugin loop, bash-3.2 safety and the `CHECK_SKILLS_DIR`/`CHECK_SKILLS_INDEX` env overrides) with a renderer `render_index` that rewrites ONLY the generator-owned cells — the Directory cell's row set, Version (frontmatter `version`) and Last Updated (frontmatter `lastUpdated`) — and preserves every curated cell, section, footnote and prose line. `--write` installs the rendered index (temp + rename); the default gate mode renders to a temp file and `diff`s (the diff is the failure message). A new skill dir with no row: the renderer appends a row under the LAST table of the index with Skill Name = frontmatter `name`, Agent Consumers `—`, Token Est. `—`, so the gate fails until it is generated, never silently.
- First `--write` on base content: if any Last Updated cell differs from frontmatter (e.g. `2026-03` vs `2026-03-xx`), commit that normalisation as its own commit and list the changed rows in the PR body — that is the "round-trips the current index" evidence (after normalisation a re-run is a no-op).
- Both plugins with a skills dir: `loomwright/skills/SKILLS_INDEX.md` and `stackpack/skills/SKILLS_INDEX.md`.
- `--self-test`: extend the existing synthetic proof with: hand-edited Version ⇒ fail; hand-edited Last Updated ⇒ fail; missing row ⇒ fail; `--write` idempotent; curated cell preserved.
- `.agent/companions.json`: delete exactly the one `skills/*/SKILL.md ⇒ SKILLS_INDEX.md` rule; keep the file's strict shape (`schema_version: 1`).
- New `loomwright/scripts/test-skills-index-companion.sh` (under `loomwright/scripts/` so CI's self-test glob runs it; a root `scripts/test-*.sh` would need a `ci.yml` edit, which makes the PR un-reviewable by claude-review): builds a temp repo whose `.agent/companions.json` is a copy of the REAL file, two items whose Touches name two different `loomwright/skills/<x>/SKILL.md`, runs `automate-helpers.sh plan-waves … --max 5 --root <tmp>` and asserts both land in `wave 1`; a control with the old rule re-added asserts they split.

### Subtask 2 — automate-helpers.sh split (detail)
- Families follow the dispatcher's own `case` table. Proposed grouping (the worker confirms against the real call graph and records the final list in the PR body): `config.sh` (config-suppress/-restore/-orig), `runfile.sh` (runfile-write, progress-append, queue-checkoff, current-set, current-rebuild, remaining + their `_progress_*`/`_current_*`/`_runfile_*` privates), `intake.sh` (resolve-folder, resolve-backlog + `_backlog_*`), `resume.sh` (resume-glob, reconcile-item, closeout-classify), `learning.sh` (learning-emit, brief-repair, ceiling-check), `reconcile-status.sh` (reconcile-status + `_rs_*`), `meta.sh` (meta-entry, meta-push-failed, `_meta_root`), `plan-waves.sh` (plan-waves + `_pw_*`).
- STAYS in `automate-helpers.sh`: the header comment block (the `--help` source), `die`/`abort`, the shared predicates (`is_done`, `is_not_ready`, `RUN_TITLE_ERE`, `is_run_file`) and any other function called from more than one family, `gate_eval` with its `_ge_*` privates (the ONLY `gh pr merge --squash` executor keeps its documented file, so CLAUDE.md, `automate-loop/SKILL.md` §11 and `commands/agent-help.md` need no edit), and `main`. The sibling `exec bash automate-trail.sh …` / `automate-dismissed.sh …` arms are unchanged.
- Sourcing: each family file is sourced at the exact point its code occupied in the monolith (so config/runfile before the shared predicates, intake/resume before `gate_eval`, learning/reconcile-status/meta/plan-waves after it), each through one line `_ah_source <name>` between begin/end marker comments, which does `[ -r ] || die "missing family file: <name>"` then `.`. No glob — a stray file is never sourced. Every `$(dirname "$0")` sibling lookup keeps working because `$0` is still the dispatcher. Code moves VERBATIM (cut/paste, no reformatting).
- ONE expansion function `_ah_bundle` (in the dispatcher) prints the dispatcher text with each `_ah_source` block replaced by that family file's text. The help arm becomes `_ah_bundle | grep -E '^#   [a-z]' | sed 's/^#   /  /'` (same filter as base), and the test bundler (below) calls the same function. Proof of a verbatim move: `_ah_bundle` output with the marker blocks, `_ah_source`/`_ah_bundle` definitions removed, and the help-arm line removed on BOTH sides (base's `grep -E '^#   [a-z]' "$0"` line and the branch's `_ah_bundle | grep …` line), equals `git show a14db34:loomwright/scripts/automate-helpers.sh` byte-for-byte; the `_ah_source`/`_ah_bundle` definitions must carry no `^#   [a-z]` comment line (the base-vs-branch `--help` diff enforces it) — assert it in the dispatch test against the base blob when available (skip with a named reason in a shallow clone).
- Test harness, minimal and assertion-free: in `test-automate-helpers.sh`, change ONLY how `$H` is resolved — write `_ah_bundle`'s output (a single-file script) into a temp dir in which every other `loomwright/scripts/*` entry is symlinked, and set `H` to it. Every existing mutation `sed … "$H" > …` then still finds its target text, every sibling lookup resolves, and no `ok`/`no`/mutation line changes. The bundle builder is a small function above `H=`; the sourcing block carries begin/end marker comments so the builder is exact. If the bundle cannot reproduce base totals, STOP and report (do not edit assertions or mutation lines).
- New `loomwright/scripts/test-automate-helpers-dispatch.sh` exercises the REAL dispatcher (not the bundle): for every subcommand in the `case` table, invoke it with arguments that reach its usage/argument check and assert the output never contains `unknown subcommand`, and that the named function is defined after sourcing; mutants: (a) a copy of the scripts dir with one family file removed ⇒ the dispatcher exits non-zero naming it; (b) a family whose function is renamed ⇒ the test fails. Gate each mutant on non-empty + differs + `bash -n` (lesson fa32a308). Also asserts the real dispatcher's `--help` and no-arg output equal base's (from the base blob) byte-for-byte.
- Callers unchanged: `automate-trail.sh`, `automate-dismissed.sh`, `test-automate-trail.sh`, `test-automate-dismissed.sh`, every SKILL/command prose `automate-helpers.sh <subcommand>` — byte-identical CLI.

### Subtask 3 — RESULT_SCHEMAS.md split (detail)
- One file per TOP-LEVEL schema section, detected fence-aware (the `## Status`/`## Queue`/… lines inside the AUTOMATE_RUN / VERIFY_QUEUE example fences and any heading inside a fenced block are NOT sections). File names: lowercase kebab of the heading's leading token, e.g. `supervisor-result.md`, `automate-run.md`, `session-end-jsonl.md`, `agent-lifecycle-jsonl.md`, `schema-versioning.md`, `validation-location.md`.
- `RESULT_SCHEMAS.md` keeps: its path, its preamble (everything before the first `## `), and for every section its exact original `## ` heading line, in the original order, followed by one line `See [result-schemas/<file>](result-schemas/<file>).` — so `§"X"` prose citations, `grep '^## VERIFY_RESULT$'` checks and heading-order checks keep resolving. Each split file starts with the same `## ` heading and holds the section body verbatim.
- Parsers: FIRST list every reader that parses the doc's CONTENT (not a comment mention) — the starting set from `git grep` at base is `test-automate-dismissed.sh`, `test-automate-trail.sh`, `test-build-floor.sh`, `test-check-children-settled.sh`, `test-check-contract-parity.sh`, `test-classify-risk.sh`, `test-context-digest.sh`, `test-not-verified-transport-seam.sh`, `test-verify-evidence.sh`, `test-verify-provides.sh`, `test-verify-walkthrough.sh`, `test-setup-ui.sh` (its FLOOR_PROJECTION key-set awk reads the yaml fence under `## FLOOR_PROJECTION`) (all under `loomwright/scripts/`) — then re-check with a wider grep (multi-line constructions, `../docs/` relative paths, `sdk-spike/`, `scripts/check-*.sh`, `scripts/eval-corpus/`) and include any found. Re-point each to the split file(s) it needs; never weaken a check (same strings, same counts, same order assertions). The PR body lists each parser and the check it runs.
- Parser search was widened at brief time (root `scripts/*.sh`, `eval-corpus/`, `sdk-spike/src/`, `*.py`, `adapters/`, `docs/*` globs): an exhaustive scan (every `*.sh`/`*.py`/`*.ts`/`*.js` that assigns or quotes a `RESULT_SCHEMAS.md` path AND runs a reader) yields exactly the 12 parsers listed above; the other hits (`test-lens-run.sh`, `propose-product.sh`, `propose-verify.sh`, `validate-code-review-result.py`, `validate-qa-result.py`) are echo/die/docstring text. `test-citation-drift.sh` scans `loomwright/docs/*.md`, which crosses `/` and so already covers `result-schemas/*.md`. A parser the worker still finds outside the declared lanes is STOP-and-report, never an edit.
- **State-trace review (requirement Scope 4):** list every agent/skill/command that tells a runtime model to READ the doc (not merely cite a `§"X"`), and for each record whether the index's heading + pointer is enough or the reference must name the split file. Found at brief time: `agents/launch-pad.md` Phase 3 (`docs/RESULT_SCHEMAS.md` → `## SYSTEM_CONTRACT` convention — the heading stays in the index with a pointer, judged enough). Any reader judged NOT enough is recorded in the PR body as a follow-up — no agent/skill prose is edited in this item (agnostic/04 edits those files this wave).
- New `loomwright/scripts/test-result-schemas-split.sh`: every index heading has exactly one pointer to an existing split file whose first `## ` heading equals it; no split file is unreferenced; the index's heading sequence equals the split files' heading sequence; a mutant index with one pointer removed ⇒ fail.
- Pins: re-derive all THREE pins that cite `RESULT_SCHEMAS.md:<N>` — `loomwright/scripts/format-twin-delta.sh` (currently `:841` → `result-schemas/session-end-jsonl.md:<N>`), `loomwright/skills/self-heal-advisory/SKILL.md` (currently `:614` → `result-schemas/code-review-result.md:<N>`), and the in-file pin in the SUPERVISOR_RESULT section (it cites `docs/RESULT_SCHEMAS.md:614`, which would resolve to the index → `docs/result-schemas/code-review-result.md:<N>`) — each to the split file and line now holding the pinned text, the `[pins: …]` text byte-unchanged. `test-citation-drift.sh` green.
- Do NOT edit `loomwright/docs/vendor-coupling-manifest.json` (subtask 4 owns it); `check-vendor-coupling.sh` is EXPECTED to fail in this subtask's own run on the new paths — report it, do not fix it.

### Subtask 5 — Remediation (detail; inserted at Phase 3 adjudication, option B, owner decision 2026-10-06)
- Runs on the MERGED result of subtasks 2 and 3 (it edits `test-automate-trail.sh`, a subtask-3 lane file, so it must start after 3).
- `loomwright/scripts/test-automate-trail.sh`: its scratch staging copies the scripts dir without `automate-helpers.d/` (128 FAIL on the split). Make the staging also copy `automate-helpers.d/` (or the same set the dispatcher sources). Setup-only change — no `ok`/`no` check, expected value or mutation line edited.
- `loomwright/scripts/test-verify-queue.sh`: same cause in its `stage()` (4 FAIL) — same setup-only fix.
- `loomwright/scripts/test-no-pipefail-grep-q.sh`: its writer baseline names `automate-helpers.sh` for a line that moved to `automate-helpers.d/reconcile-status.sh` (2 FAIL) — re-point that baseline entry to the new path; the line itself and the rule are unchanged.
- Re-scan for any OTHER test that stages or copies `automate-helpers.sh` alone (`git grep -n 'automate-helpers.sh' -- 'loomwright/scripts/test-*.sh' 'loomwright/scripts/adapters/*/test-*.sh'` plus `cp`/`ln` of the scripts dir) and run each; any further breakage found outside these lanes is STOP-and-report.
- Write the Scope-4 state-trace table subtask 3 did not produce — not as a committed doc, but to `.supervisor/jobs/context-digests/pa11-state-trace.md` (gitignored, main checkout) for the PR body: every agent/skill/command that tells a runtime model to READ `RESULT_SCHEMAS.md`, and whether the index heading + pointer is enough. No prose edits.
- Then run all three tests plus `test-automate-helpers.sh`, `test-automate-helpers-dispatch.sh`, `test-result-schemas-split.sh` on the merged tree.

### Subtask 4 — Integration (detail)
- **Cited sub-heading anchors (added after subtask 5's state-trace, 2026-10-06):** prose cites `RESULT_SCHEMAS.md §"…"` for sub-headings the index no longer carries — at least §"`## Executable Acceptance`" (now in `result-schemas/ground-truth-json.md`; cited from launch-pad.md, plan-reviewer.md, self-heal-advisory, rules, supervisor-readiness ×2) and §"Completion authority join" (now in `result-schemas/agent-lifecycle-jsonl.md`; cited from execute-manager.md ×2, supervisor.md, async-orchestration). The requirement says every heading a prose citation names must still resolve in the index. Add to `RESULT_SCHEMAS.md`, after the per-schema pointers, ONE `## Cited sub-section anchors` block listing every sub-heading that any committed prose cites as `RESULT_SCHEMAS.md §"X"` (derive the list mechanically with a grep over the repo; table: anchor text → split file). Extend `test-result-schemas-split.sh` with a check that every `RESULT_SCHEMAS.md §"X"` citation in the tracked tree whose X is not a top-level index heading appears in that block and names a split file containing X (plus a mutant with one row removed ⇒ fail). No prose file outside these lanes is edited. Full table: `~/Documents/work/AI/ai-agent-manager-lanes-v2/s3-f/.supervisor/jobs/context-digests/pa11-state-trace.md`.
- `check-vendor-coupling.sh` on the integrated tree (after `git add`): move each allowance from `automate-helpers.sh` / `RESULT_SCHEMAS.md` to the new paths that now carry those references, flat total unchanged, one `allowance_reasons` entry per moved path: `moved by parallel-automate/11 split — no reference added`.
- After-measurement (AC11): re-run the Scope 1 command on the integrated tree; then, in a scratch copy of the 14 items, re-point each item's `RESULT_SCHEMAS.md` / `automate-helpers.sh` Touches line to the split/family files its own Scope text names (list the mapping), and re-run. Record both tables in the PR body. Do not edit the real requirement files' Touches (that is the post-merge re-point, S3 gap 7).
- `changelog.d/parallel-automate-11-split-shared-hotspot-files.md` fragment (format: `changelog.d/README.md`); no hand version bump.
- Full loop: `bash scripts/ci-local.sh` on base worktree and branch; report `<passed>/<total>` + SKIP for both.

## Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "scripts/check-skills-index-sync.sh", name: "render_index"}
  - {kind: "symbol", path: "scripts/check-skills-index-sync.sh", name: "--write"}
  - {kind: "file", path: "loomwright/scripts/test-skills-index-companion.sh"}
requires: []
lanes:
  - "scripts/check-skills-index-sync.sh"
  - "loomwright/skills/SKILLS_INDEX.md"
  - "stackpack/skills/SKILLS_INDEX.md"
  - ".agent/companions.json"
  - "loomwright/scripts/test-skills-index-companion.sh"
external_requires: []

# Subtask 2
provides:
  - {kind: "file", path: "loomwright/scripts/automate-helpers.d/plan-waves.sh"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.d/plan-waves.sh", name: "plan_waves"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "gate_eval"}
  - {kind: "file", path: "loomwright/scripts/test-automate-helpers-dispatch.sh"}
requires: []
lanes:
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/automate-helpers.d/**"
  - "loomwright/scripts/test-automate-helpers.sh"
  - "loomwright/scripts/test-automate-helpers-dispatch.sh"
external_requires: []

# Subtask 3
provides:
  - {kind: "file", path: "loomwright/docs/result-schemas/supervisor-result.md"}
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "## SUPERVISOR_RESULT"}
  - {kind: "file", path: "loomwright/scripts/test-result-schemas-split.sh"}
requires: []
lanes:
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/docs/result-schemas/**"
  - "loomwright/scripts/test-result-schemas-split.sh"
  - "loomwright/scripts/test-automate-dismissed.sh"
  - "loomwright/scripts/test-automate-trail.sh"
  - "loomwright/scripts/test-build-floor.sh"
  - "loomwright/scripts/test-check-children-settled.sh"
  - "loomwright/scripts/test-check-contract-parity.sh"
  - "loomwright/scripts/test-classify-risk.sh"
  - "loomwright/scripts/test-context-digest.sh"
  - "loomwright/scripts/test-not-verified-transport-seam.sh"
  - "loomwright/scripts/test-verify-evidence.sh"
  - "loomwright/scripts/test-verify-provides.sh"
  - "loomwright/scripts/test-verify-walkthrough.sh"
  - "loomwright/scripts/test-setup-ui.sh"
  - "loomwright/scripts/format-twin-delta.sh"
  - "loomwright/skills/self-heal-advisory/SKILL.md"
external_requires: []

# Subtask 5
provides:
  - {kind: "file", path: "loomwright/scripts/test-automate-trail.sh"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-trail.sh", name: "automate-helpers.d"}
  - {kind: "symbol", path: "loomwright/scripts/test-verify-queue.sh", name: "automate-helpers.d"}
  - {kind: "symbol", path: "loomwright/scripts/test-no-pipefail-grep-q.sh", name: "automate-helpers.d/reconcile-status.sh"}
requires:
  - {from: "2", kind: "file", path: "loomwright/scripts/automate-helpers.d/plan-waves.sh"}
  - {from: "3", kind: "file", path: "loomwright/scripts/test-result-schemas-split.sh"}
lanes:
  - "loomwright/scripts/test-automate-trail.sh"
  - "loomwright/scripts/test-verify-queue.sh"
  - "loomwright/scripts/test-no-pipefail-grep-q.sh"
external_requires: []

# Subtask 4
provides:
  - {kind: "file", path: "changelog.d/parallel-automate-11-split-shared-hotspot-files.md"}
  - {kind: "symbol", path: "loomwright/docs/vendor-coupling-manifest.json", name: "loomwright/docs/result-schemas/supervisor-result.md"}
requires:
  - {from: "1", kind: "file", path: "loomwright/scripts/test-skills-index-companion.sh"}
  - {from: "2", kind: "file", path: "loomwright/scripts/automate-helpers.d/plan-waves.sh"}
  - {from: "3", kind: "file", path: "loomwright/docs/result-schemas/supervisor-result.md"}
  - {from: "5", kind: "symbol", path: "loomwright/scripts/test-verify-queue.sh", name: "automate-helpers.d"}
lanes:
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/scripts/test-result-schemas-split.sh"
  - "changelog.d/parallel-automate-11-split-shared-hotspot-files.md"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──┐
Subtask 2 ──┼──→ Subtask 4
Subtask 3 ──┘
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none (subtask 1's fixture CALLS `automate-helpers.sh plan-waves`; it does not edit it) | NO |
| Subtask 1 | Subtask 3 | none | NO |
| Subtask 2 | Subtask 3 | none (`test-automate-helpers.sh` names `docs/RESULT_SCHEMAS.md` only as fixture Touches strings — no read; stays subtask 2's) | NO |
| Subtasks 1–3 | Subtask 4 | `vendor-coupling-manifest.json` is subtask 4's only; 4 runs after all three | ordered by `requires` |

### Batch Plan
- **Batch 1:** Subtask 1, Subtask 2, Subtask 3 (parallel — empty `requires`, zero file overlap)
- **Batch 2:** Subtask 4 (after 1, 2, 3)
- **Recommended workers:** 3
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/ci-cd/SKILL.md` |
| 2 | `skills/unit-testing/SKILL.md`, `skills/automate-loop/SKILL.md` (§1.5 subcommand table — reference only, not edited) |
| 3 | `skills/unit-testing/SKILL.md` |
| 4 | `skills/ci-cd/SKILL.md` |

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): the requirement says `test-automate-helpers.sh` "passes unchanged"; 17 mutation controls `sed` the monolith text, so the file cannot stay byte-identical | HIGH | Only the `$H` resolution changes (bundle of dispatcher + family files, verbatim code); zero `ok`/`no`/mutation lines edited; PR body shows the one-hunk diff. The bundle tests the moved code, not the sourcing — the new dispatch test exercises the real dispatcher. If the bundle cannot reproduce base totals, the worker stops and reports instead of editing assertions |
| Feasibility (Phase 2.5): ~6,800 moved lines in one PR | MEDIUM | Code and schema text move verbatim (cut/paste); each subtask's PR-body section states "move-only" and lists any non-move hunk; the drain's large-PR review path (pa/19) applies |
| `gate_eval` stays in `automate-helpers.sh` (deviation from the requirement's example family list) | MEDIUM | Deliberate: keeps the single merge executor in the file CLAUDE.md, `automate-loop/SKILL.md` §11 and `agent-help.md` name, so AC7's grep is unchanged and this item does not edit the hottest skill (16 conflict lines, sibling agnostic/04 edits it this wave) |
| Three pins and 12 parser tests must be re-pointed; the requirement says "no pin edited to make it pass" | MEDIUM | Pins keep their `[pins: …]` text byte-identical; only path/line re-derived to where the text now lives. Parser checks keep the same strings/counts/order |
| Index regeneration is per-PR: with the companion rule gone, an item that changes a skill's frontmatter version must declare `SKILLS_INDEX.md` itself, or two such items can share a wave and meet a (mechanically resolvable) git conflict on the index | MEDIUM | Disclosed trade-off of requirement Scope 2; resolution is `check-skills-index-sync.sh --write` (generated content, never a hand merge); release-time regeneration rejected because it needs a gate tolerant of stale cells |
| Generator owns row set / Version / Last Updated / Total only — not the requirement's "name, version, description" | LOW | The index has no description column and a curated display name; generating them would rewrite curated content. Disclosed deviation |
| Requirement Validation 2 ("a real sequential `/automate` run after the split", listed must-pass-before-merge) moves to post-merge | MEDIUM | Needs explicit owner sign-off at save; recorded in the PR body |
| `check-vendor-coupling.sh` fails in subtasks 2 and 3 until subtask 4 | MEDIUM | Expected and owned by subtask 4; workers 2/3 report it, never edit the manifest |
| Sibling agnostic/04 (same wave) also edits `vendor-coupling-manifest.json` | MEDIUM | Different keys; wave-branch integration resolves any line conflict; subtask 4 keeps its edits to the moved paths' own keys and reasons |
| Index generator normalises existing Last Updated cells on its first run | LOW | Normalisation in its own commit, changed rows listed in the PR body |
| After-merge Touches drift: open items still name `RESULT_SCHEMAS.md` / `automate-helpers.sh` | LOW | Out of PR scope (S3 gap 7); AC11 measures the re-pointed case in a scratch copy and lists the mapping for the operator |
| `automate-loop/SKILL.md` remains a hotspot (ranked 3rd) | LOW | Out of scope per requirement Scope 4; becomes a follow-up item |

## Configuration
- **Workers:** 3
- **Mode:** parallel
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** genuine-parallelism

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-06-split-shared-hotspot-files.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-10-07T00:47:52Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/408
- **Branch:** feature/parallel-automate-11-split-shared-hotspot-files
- **Files changed:** 67
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** 5 subtasks (incl. remediation subtask 5 from adjudication B); skills index generated + companion dropped; automate-helpers.sh split into 8 family files behind identical stdout/exit CLI; RESULT_SCHEMAS.md split into 33 files with heading-preserving index + cited sub-section anchors; ci-local 146/146; explain conflicts 140 -> 91 (84 re-pointed). Review PASS with 6 MEDIUM/LOW dismissed findings.

## Not verified
- **Live sequential /automate run through the split dispatcher** — no local runtime; owner-approved post-merge check (subtask 2)
- **CI self-test glob picking up loomwright/scripts/test-skills-index-companion.sh** — ran locally only (subtask 1)
