# Supervisor Job: Inventory every branch and rule in the loop prose, with a test that keeps it honest

## Environment
- **Project:** ai-agent-manager-lanes/automate-2026-10-15-163325/L2 (lane clone of the loomwright marketplace repo)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/automate-speed/04-loop-inventory.md
- **Base commit:** f5c2d0e23fb717d385047340d7ddb5862153b6e0

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Markdown docs + one bash test; the repo's own idiom (bash 3.2-safe `test-*.sh`, awk/grep). |
| 2 | Dependency Availability | GO | Only bash, awk, grep, mktemp — all used by sibling tests. |
| 3 | Architecture Fit | GO | New `loomwright/docs/loop-inventory/` subdirectory; CI auto-discovers `loomwright/scripts/test-*.sh`. |
| 4 | Scope vs Supervisor Capability | CAUTION | ~1.1 MB of source prose (≈230 `###`/`####` headings, ≈1,700 list items) across four groups — far beyond one worker's context, so the brief splits `context-bound` per group. |
| 5 | Hard Blockers | GO | None. |

**Overall Verdict:** CAUTION

## Task
**Goal:** Commit four loop-inventory tables (one per prose file group) listing every branch and rule in the `/automate` → `/autonomous` → Launch Pad / Supervisor → `/review-pr` loop prose, plus `loomwright/scripts/test-loop-inventory.sh`, which fails whenever the prose and the inventory disagree.

**Problem Statement:**
The maintainers of the loop protocol need a mechanical list of every branch and rule that exists in prose because later automate-speed items will move control flow into scripts and move stories out.
Currently nothing lists those branches, so a paragraph can be deleted and the only copy of an edge case silently goes with it. This makes every prose move unsafe to review.
Success looks like: four committed inventory files whose rows are checked by CI against the prose (heading coverage, live anchors, real script subcommands, unique ids, counts and gap lists computed, never hand-maintained).

## Acceptance Criteria
- [ ] AC1 — Given the four file groups, when the inventory is written, then four files exist under `loomwright/docs/loop-inventory/`: `automate-loop.md` (every `loomwright/skills/automate-loop/*.md` + `loomwright/commands/automate.md`), `supervisor.md` (`loomwright/agents/supervisor.md`, `loomwright/commands/supervisor.md`, `loomwright/skills/self-heal-advisory/SKILL.md`, `loomwright/skills/async-orchestration/SKILL.md`), `review-heal.md` (`loomwright/skills/review-heal/SKILL.md`, `loomwright/commands/review-pr.md`, `loomwright/agents/review-pr.md`) and `launch-pad-autonomous.md` (`loomwright/agents/launch-pad.md`, `loomwright/commands/launch-pad.md`, `loomwright/skills/autonomous-loop/SKILL.md`, `loomwright/commands/autonomous.md`), each in the exact format of `## Inventory format (shared contract)` below.
- [ ] AC2 — Given any listed source file, when `test-loop-inventory.sh` runs, then every `###`/`####` heading line of that file outside fenced code blocks and outside `<!-- split:begin … -->`/`<!-- split:end … -->` index blocks is the `h:` anchor of at least one row whose `file` cell names that file; a missing heading fails the test naming the file and the heading.
- [ ] AC3 — Given every numbered or bulleted list item in a listed file that states a condition→action branch or a rule, then it maps to its own row (anchored by a `q:` quote of its text, or by its heading when the item is the heading's only content); a list item that is pure enumeration (a file list, a flag list, an illustrative example) is covered by its section's heading row. (Reviewer's check — the test checks headings only.)
- [ ] AC4 — Given a row whose anchor no longer exists in its file while its `home` is `prose`, when `test-loop-inventory.sh` runs, then it exits non-zero and prints a line naming the row id (`FAIL <id>: anchor not found in <file>`); a row whose home is not `prose` is not anchor-checked.
- [ ] AC5 — Given a row whose `home` or `implemented by` cell reads `script:automate-helpers.sh gate-eval`, then the test passes; given the same row renamed to a subcommand the script has no case arm for, then it fails naming the row id.
- [ ] AC6 — Given two rows sharing one id (within one file or across the four files), then the test fails naming the duplicated id.
- [ ] AC7 — Given each group file, then it ends with `## Gap list (ordered by risk)` (every `GAP` row's id exactly once, highest risk first, one-line reason each) followed by `## Counts` (rows, one line per kind, GAP); the test fails when the gap list's id set differs from the table's `GAP` rows or when any count line differs from the count the test computes, and prints one informational `GAP <group>: <n>` line per group (never a failure on its own). All six `## Counts` lines (`rows`, the four kinds, `GAP`) are required — a missing line fails like a wrong one.
- [ ] AC7b — Given a row whose `test` cell is not `GAP`, then it must name a `test-*.sh` file that exists under `loomwright/scripts/` or `scripts/`; otherwise the test fails naming the row id.
- [ ] AC8 — Given the mutation controls, when `test-loop-inventory.sh` runs, then its own fixture legs prove AC2 and AC4–AC7 red on scratch copies (a new `###` heading added to a scratch copy of `per-item-loop.md` with no row — AC2; an anchored heading deleted from a scratch copy of `per-item-loop.md` — AC4; a renamed subcommand — AC5; a duplicated id — AC6; a wrong count value, a missing `## Counts` line, and a gap-list line deleted — AC7; a `test` cell naming a nonexistent file — AC7b), prove the exemptions green (a heading inside a fenced block or a split-index block needs no row; a row whose home is not `prose` is not anchor-checked) and green on the unmutated tree, with every mutant checked non-empty and different from its original before it is trusted.
- [ ] AC9 — Given the validation run, then a committed evidence file `docs/evidence/as04-loop-inventory.md` contains the `<passed>/<total>` results of `bash loomwright/scripts/test-loop-inventory.sh`, `bash loomwright/scripts/test-citation-drift.sh`, `bash scripts/check-doc-currency.sh`, `bash scripts/check-vendor-coupling.sh` and `bash scripts/test-check-vendor-coupling.sh`, the mutation-control transcript (the heading deleted from a scratch copy of `per-item-loop.md` and the red line naming its row), and the per-group counts (rows, per kind, GAP), and the PR body links to it.
- [ ] AC10 — Given the release rule, then the change carries `changelog.d/as04-loop-inventory.md` with `<!-- bump: minor -->` and makes no edit to `plugin.json`, `marketplace.json` or `CHANGELOG.md` (lane PRs carry fragments only; the wave bumps).
- [ ] AC11 — Given the non-goals, then no prose file, script or behaviour changes outside the six created files, the evidence file, and `loomwright/docs/vendor-coupling-manifest.json`.
- [ ] AC12 — Given the vendor-coupling ratchet (`scripts/check-vendor-coupling.sh`: `loomwright/docs/*` is a counted class and a path with no allowance has allowance 0), when the four inventory files quote prose that carries counted tokens, then `loomwright/docs/vendor-coupling-manifest.json` gains one measured `allowances` entry (`--print-allowances`) and one `allowance_reasons` line per inventory file that needs one (reason: the inventory quotes headings and branch text of its source prose verbatim; measured), `test-loop-inventory.sh` itself names no counted token literally (its fixtures included — build any needed token from parts or avoid it), and `bash scripts/check-vendor-coupling.sh` exits 0.

## Inventory format (shared contract)

Every group file uses exactly this shape (all four workers and the test author share it; the test parses it):

```markdown
# Loop inventory — <group name>

<one paragraph: what this file is, that test-loop-inventory.sh keeps it in sync, never hand-maintained counts>

## Sources
- `<path relative to loomwright/>`   (one bullet per source file of the group)

## Inventory

| id | file | anchor | condition | action | kind | home | implemented by | test |
|----|------|--------|-----------|--------|------|------|----------------|------|
| AL-001 | skills/automate-loop/per-item-loop.md | h: ### Rate-limit park (end of RUN, before DRAIN) | … | … | deterministic | prose | script:automate-helpers.sh current-set | test-automate-helpers.sh |

## Gap list (ordered by risk)
1. AL-0NN — <one-line reason it is risky>

## Counts
- rows: <n>
- deterministic: <n>
- judgment: <n>
- rule: <n>
- story: <n>
- GAP: <n>
```

Cell rules:
- **id** — `AL-NNN` (automate-loop), `SV-NNN` (supervisor), `RH-NNN` (review-heal), `LP-NNN` (launch-pad-autonomous); three or more digits, sequential from 001, never reused. Unique across all four files.
- **file** — path relative to `loomwright/` (e.g. `agents/supervisor.md`), one of the file's `## Sources`.
- **anchor** — `h: <the heading line exactly as in the file, leading #s included>` or `q: <a literal substring of one line of the file, ≥ 12 characters>`. Never a line number (`test-citation-drift.sh` polices `file:N` text in `loomwright/docs/`). A literal `|` inside any cell is written `\|`; the test unescapes `\|` before matching.
- **kind** — one of `deterministic` · `judgment` · `rule` · `story`.
- **home** — `prose` for every row today (this item moves nothing); the other legal forms, for later items: `script:<file> <subcommand>`, `hook:<leaf>`, `step-scoped`, `global`, `rationale:<doc>#<anchor>`.
- **implemented by** — `script:<file> <subcommand>` (a script under `loomwright/scripts/` and one of its `case` arm labels), `script:<file>` (a whole standalone script), or `-`.
- **test** — a `test-*.sh` file name that exists under `loomwright/scripts/` or `scripts/`, or `GAP`.

## Touched-file invariants

> Grounded at base `f5c2d0e23fb717d385047340d7ddb5862153b6e0`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/docs/vendor-coupling-manifest.json`** — keep: only ADD keys inside `"allowances": {` and `"allowance_reasons": {` (one measured integer and one non-empty one-line reason per new path); leave `token_classes`, `classes`, `scan_roots`, `unclassified_default`, `policy_reasons` and every existing entry byte-unchanged; the file stays valid JSON (`jq . <file>` exits 0). reuse: the gate's own measurement — `bash scripts/check-vendor-coupling.sh --print-allowances` — never a hand count; place new entries beside the existing `"loomwright/docs/HOOKS.md"` entries. mirror: the gate in `scripts/check-vendor-coupling.sh` reads this file (`MANIFEST="${VENDOR_COUPLING_MANIFEST:-$repo_root/loomwright/docs/vendor-coupling-manifest.json}"`) and its raise rule (`TO RAISE AN ALLOWANCE: raise it in loomwright/docs/vendor-coupling-manifest.json`) requires an added/changed `allowance_reasons` entry per raised path. fired by: `.github/workflows/ci.yml` and `scripts/ci-local.sh` (`bash scripts/check-vendor-coupling.sh`). pinned by: `scripts/test-check-vendor-coupling.sh` (`REAL_MANIFEST="$repo_root/loomwright/docs/vendor-coupling-manifest.json"` — its token-class and class-glob checks), which must stay green.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | automate-loop group inventory | AC1, AC3, AC7 (file shape), AC11 | 0 modify, 1 create | — | LAUNCHABLE |
| 2 | supervisor group inventory | AC1, AC3, AC7 (file shape), AC11 | 0 modify, 1 create | — | LAUNCHABLE |
| 3 | review-heal group inventory | AC1, AC3, AC7 (file shape), AC11 | 0 modify, 1 create | — | LAUNCHABLE |
| 4 | launch-pad-autonomous group inventory | AC1, AC3, AC7 (file shape), AC11 | 0 modify, 1 create | — | LAUNCHABLE |
| 5 | test-loop-inventory.sh + evidence + changelog fragment + vendor-coupling allowances | AC2, AC4, AC5, AC6, AC7, AC7b, AC8, AC9, AC10, AC11, AC12 | 1 modify, 3 create | `skills/unit-testing/SKILL.md` | BLOCKED (by #1, #2, #3, #4) |

**Size estimate (for the split predicate):** ≈230 `###`/`####` headings (one row each) plus the branch- or rule-bearing share of ≈1,700 list items. Estimated rows: automate-loop ≈ 350, supervisor ≈ 400, review-heal ≈ 200, launch-pad-autonomous ≈ 300 — ≈ 1,250 table lines in total, each group file alone ≈ 200–400 lines. Plus the test (≈ 300 lines). That is well over the 800-changed-line `context-bound` bound, and no single worker can also hold the ≈ 1.1 MB of source it must read.

Per-subtask notes:
- **Subtasks 1–4:** read every source file of the group in full, top to bottom, and write one row per `###`/`####` heading (outside fences and split-index blocks) and one row per list item that states a branch or rule. Fill `implemented by` / `test` only after confirming the script arm (`grep -nE` for the arm label in the script's `case`) or the test file exists; otherwise `-` / `GAP`. Every `q:` anchor is copied, never paraphrased, and checked with `grep -F` against the file before hand-back. End with the gap list and counts (counted from the table). Change no source file.
- **Subtask 5:** `test-loop-inventory.sh` in the style of its siblings (`#!/usr/bin/env bash`, `set -u`, a header comment naming what is and is not checked, bash 3.2 + BSD userland, no network, no `gh`); a checker function over a plugin root (default: the repo's `loomwright/`, `--root <dir>` for a scratch copy), then fixture legs on `mktemp -d` copies for AC8. Subcommand rule: a `script:<file> <sub>` cell passes iff `<file>` exists under `loomwright/scripts/` and has a line matching a shell `case` arm whose `|`-separated labels include `<sub>` followed by `)`. Run it plus `test-citation-drift.sh` and `check-doc-currency.sh`; then (once the four files are `git add`ed) `bash scripts/check-vendor-coupling.sh --print-allowances`, add the measured `allowances` + `allowance_reasons` entries for each inventory file that needs one (and for the manifest itself only if its note quotes a token), re-run `check-vendor-coupling.sh` to exit 0; write the evidence file, add the fragment.

## Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/docs/loop-inventory/automate-loop.md"}
  - {kind: "symbol", path: "loomwright/docs/loop-inventory/automate-loop.md", name: "## Gap list (ordered by risk)"}
  - {kind: "symbol", path: "loomwright/docs/loop-inventory/automate-loop.md", name: "## Counts"}
requires: []
lanes:
  - "loomwright/docs/loop-inventory/automate-loop.md"
external_requires: []

# Subtask 2
provides:
  - {kind: "file", path: "loomwright/docs/loop-inventory/supervisor.md"}
  - {kind: "symbol", path: "loomwright/docs/loop-inventory/supervisor.md", name: "## Gap list (ordered by risk)"}
  - {kind: "symbol", path: "loomwright/docs/loop-inventory/supervisor.md", name: "## Counts"}
requires: []
lanes:
  - "loomwright/docs/loop-inventory/supervisor.md"
external_requires: []

# Subtask 3
provides:
  - {kind: "file", path: "loomwright/docs/loop-inventory/review-heal.md"}
  - {kind: "symbol", path: "loomwright/docs/loop-inventory/review-heal.md", name: "## Gap list (ordered by risk)"}
  - {kind: "symbol", path: "loomwright/docs/loop-inventory/review-heal.md", name: "## Counts"}
requires: []
lanes:
  - "loomwright/docs/loop-inventory/review-heal.md"
external_requires: []

# Subtask 4
provides:
  - {kind: "file", path: "loomwright/docs/loop-inventory/launch-pad-autonomous.md"}
  - {kind: "symbol", path: "loomwright/docs/loop-inventory/launch-pad-autonomous.md", name: "## Gap list (ordered by risk)"}
  - {kind: "symbol", path: "loomwright/docs/loop-inventory/launch-pad-autonomous.md", name: "## Counts"}
requires: []
lanes:
  - "loomwright/docs/loop-inventory/launch-pad-autonomous.md"
external_requires: []

# Subtask 5
provides:
  - {kind: "file", path: "loomwright/scripts/test-loop-inventory.sh"}
  - {kind: "file", path: "docs/evidence/as04-loop-inventory.md"}
  - {kind: "file", path: "changelog.d/as04-loop-inventory.md"}
  - {kind: "file", path: "loomwright/docs/vendor-coupling-manifest.json"}
requires:
  - {from: "1", kind: "file", path: "loomwright/docs/loop-inventory/automate-loop.md"}
  - {from: "2", kind: "file", path: "loomwright/docs/loop-inventory/supervisor.md"}
  - {from: "3", kind: "file", path: "loomwright/docs/loop-inventory/review-heal.md"}
  - {from: "4", kind: "file", path: "loomwright/docs/loop-inventory/launch-pad-autonomous.md"}
lanes:
  - "loomwright/scripts/test-loop-inventory.sh"
  - "docs/evidence/as04-loop-inventory.md"
  - "changelog.d/as04-loop-inventory.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
external_requires: []
```

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-loop-inventory.sh` — heading coverage (AC2) | delete `AL-001` in `loomwright/docs/loop-inventory/automate-loop.md` (its first occurrence is the table row; AL-001 must be an `h:` heading row) |
| `loomwright/scripts/test-loop-inventory.sh` — live anchor (AC4) | delete `### Rate-limit park (end of RUN, before DRAIN)` in `loomwright/skills/automate-loop/per-item-loop.md` |
| `loomwright/scripts/test-loop-inventory.sh` — script subcommand exists | flip `    gate-eval)       gate_eval "$@" ;;` → `    gate-evalx)       gate_eval "$@" ;;` in `loomwright/scripts/automate-helpers.sh` |
| `loomwright/scripts/test-loop-inventory.sh` — duplicate id | flip `AL-002` → `AL-001` in `loomwright/docs/loop-inventory/automate-loop.md` |
| `loomwright/scripts/test-loop-inventory.sh` — computed counts, missing line (AC7) | delete `- GAP:` in `loomwright/docs/loop-inventory/review-heal.md` |
| `loomwright/scripts/test-loop-inventory.sh` — gap-list drift (AC7) | delete `1. RH-` in `loomwright/docs/loop-inventory/review-heal.md` (if that group has no GAP row, apply it to the first group file whose gap list is non-empty, with that group's prefix) |
| `loomwright/scripts/test-loop-inventory.sh` — wrong count value (AC7) | flip `- rows: ` → `- rows: 9` in `loomwright/docs/loop-inventory/supervisor.md` (prefixes a digit, so the count differs) |
| `loomwright/scripts/test-loop-inventory.sh` — test cell names a real file (AC7b) | flip `test-automate-helpers.sh` → `test-does-not-exist.sh` in `loomwright/docs/loop-inventory/automate-loop.md` |

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──┐
Subtask 2 ──┤
Subtask 3 ──┼──→ Subtask 5
Subtask 4 ──┘
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1–4 (pairwise) | each other | none | NO |
| Subtask 1–4 | Subtask 5 | none (5 reads their outputs) | YES (requires) |

### Batch Plan
- **Batch 1:** Subtasks 1, 2, 3, 4 (parallel — each one group, one file)
- **Batch 2:** Subtask 5 (after 1–4)
- **Recommended workers:** 4
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1–4 | — (read-only prose analysis; follow `## Inventory format (shared contract)`) |
| 5 | `skills/unit-testing/SKILL.md` (fixture legs, negative controls) |

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

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

Conformance note: the inventory restates the prose's branch list on purpose (owner decision D1); per the second rule it is kept in sync by `test-loop-inventory.sh` (the sanctioned last-resort sync gate the first rule allows), and the `## Counts` block is a second static copy only because the requirement asks for it — the test recomputes and enforces it, so it can never drift silently.

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Scope: ≈1.1 MB of prose is beyond one worker's context (Feasibility (Phase 2.5)) | HIGH | `context-bound` split, one worker per group; each worker reads its group file-by-file and writes rows as it goes. |
| Four parallel workers drift on format | MEDIUM | One shared format contract in this brief; Subtask 5's test parses it and fails on any malformed row, so drift is caught before PR. |
| `q:` anchors paraphrased instead of copied → false red, or anchored on text that also appears elsewhere | MEDIUM | Workers `grep -F` every anchor against its file before hand-back; anchors ≥ 12 characters. |
| Headings inside fenced templates (`agents/launch-pad.md` output examples) or split-index entries (`skills/automate-loop/SKILL.md`, `commands/automate.md`) miscounted as live headings | MEDIUM | Coverage skips fenced blocks and `<!-- split:begin/end -->` blocks; a split-index entry's content is covered in its split file. |
| A `file:N` style string in an inventory cell trips `test-citation-drift.sh` | MEDIUM | Anchors are headings or quotes only; the test author runs `test-citation-drift.sh` and records it in the evidence file. |
| Invalid mutants silently pass the AC8 legs (lesson fa32a308) | MEDIUM | Every mutant is checked non-empty and differs from its original before the leg is trusted. |
| Vendor-coupling ratchet (`scripts/check-vendor-coupling.sh`, run by CI and `ci-local.sh`) fails on new docs files quoting counted tokens | HIGH | AC12: measured allowances + reasons added in Subtask 5 after the files exist; the test script avoids every counted token; result recorded in the evidence file. |
| Bullet coverage (AC3) is judgment, not mechanically checked | LOW | Stated honestly; Phase 4.5 reviewer spot-checks a sample of list items per group against the table. |

## Configuration
- **Workers:** 4
- **Mode:** parallel
- **Estimated batches:** 2
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-15-as04-loop-inventory.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-10-15T13:38:19Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/559
- **Branch:** feature/as04-loop-inventory
- **Files changed:** 9
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Four loop-inventory tables (2182 rows) + test-loop-inventory.sh (39/39) + vendor-coupling allowances + evidence + fragment. Phase 4.5: iter 1 PASS with MEDIUM fence-evasion + red CI (closed-enum seam grep) → fixed b431319; iter 2 PASS with 2 MEDIUM (stale evidence count, undisclosed AC11 seam edit) → fixed cce550e; iter 3 clean PASS. Ground truth 2/2. AC11 scope exception (test-closed-enum-pins-seam.sh --exclude-dir=loop-inventory) disclosed for owner acceptance.

## Not verified
- **test-loop-inventory.sh under Linux awk (gawk/mawk)** — only BSD awk run locally; CI is first Linux run (subtask 5)
