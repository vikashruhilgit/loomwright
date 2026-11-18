# Supervisor Job: A reviewed, committed QA-removal manifest with a checker and a rollback note (qa-split 11a)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** dirty (2 untracked dirs: `reports/`, `research_notes/` — unrelated), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 2 (unrelated untracked dirs; 6 linked worktrees present, none for this item)
- **Source requirement:** .supervisor/requirements/qa-split/11a-qa-removal-manifest-and-rollback-tag.md
- **Base commit:** a1b2ee589e752a2962e47335d29a5784d48f14de

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2-safe script + Markdown doc, the repo's standard `loomwright/scripts/check-*.sh` + `test-*.sh` shape |
| 2 | Dependency Availability | GO | no new dependency; `git ls-files`, `grep -F`, `awk` only |
| 3 | Architecture Fit | GO | a fail-closed checker with an offline self-test, same as `check-children-settled.sh` / `test-check-children-settled.sh` |
| 4 | Scope vs Supervisor Capability | CAUTION | the generated manifest is large (~144 tracked files outside `selvedge/` name a QA term at base, most with several named references) — together with the checker and its self-test it likely exceeds 800 changed lines, so the brief splits `context-bound` into 2 sequential subtasks |
| 5 | Hard Blockers | CAUTION | needs one file outside the requirement's Touches: the new doc names `.claude/agent-memory/…` paths and the `SubagentStop` matchers, which `scripts/check-vendor-coupling.sh` counts (class `coupled` for `loomwright/docs/*`, allowance 0 for a new path), so `loomwright/docs/vendor-coupling-manifest.json` must gain a measured allowance + reason — asked once at Phase 6 (`LP-SCOPE`) |

**Overall Verdict:** CAUTION

## Task
**Goal:** Commit `loomwright/docs/qa-removal-manifest.md` — one row per QA path or named QA reference outside `selvedge/`, each marked `delete` / `re-point` / `keep` with the item that acts on it (`11b1` / `11b2` / `12`), a row count and a rollback note — plus `loomwright/scripts/check-qa-removal-manifest.sh` (with its self-test) that checks the repo against it per row, so the removal PRs 11b1, 11b2 and 12 are checked against an approved list rather than a one-off grep.

**Problem Statement:**
The plugin's maintainer needs a reviewed, committed removal list and a checker for it because the old QA system (2 agents, 3 commands, 6 skills, the `/verify` scripts/tests, two SubagentStop matchers, schema docs, CI Playwright cache steps, a tracked agent-memory dir) is being removed (plan `qa-split/00-plan.md` D1, Q4) and ~144+ tracked files outside `selvedge/` still name it.
Currently, "grep returns nothing" is the only done-check, which is how a reference gets missed or the wrong file goes (plan red-team rows C7, W7). This causes unverifiable removal PRs.
Success looks like a committed manifest whose header carries the real row count, a checker that `--expect 11b1|11b2|12` turns into a per-row pass/fail gate, and a PR that deletes and re-points nothing.

## Design decisions
- decision: how to check the repo against the reviewed removal list (T2 — a new script is created)
  chosen: a new fail-closed `loomwright/scripts/check-qa-removal-manifest.sh` that parses the manifest's Markdown table with `awk` and checks each row with `[ -e ]` / `grep -F`, modelled on the sibling `check-children-settled.sh` and the table parsing `run-pin-mutations.sh` already does
  rejected: extend `loomwright/scripts/verify-provides.sh` (already in the repo) — blast radius: it is the `outputs_verified` gate and itself a `keep` row of this manifest; coupling a permanent gate to a transient removal list fails the reversibility axis
  rejected: a JSON manifest checked like `vendor-coupling-manifest.json` — the requirement fixes the deliverable as a reviewed Markdown doc (`loomwright/docs/qa-removal-manifest.md`), and a second JSON copy would be a restated list that drifts
  rejected: keep "grep returns nothing" as the done-check — the exact failure plan rows C7/W7 name
  evidence: `ls loomwright/scripts/check-*.sh` → `check-children-settled.sh`, `check-gate-headers.sh` (fail-closed checker + offline self-test idiom); `loomwright/scripts/verify-provides.sh` parses brief blocks only (`--parse-only`), no removal-list notion
  revisit when: the manifest needs machine consumers beyond this checker (then a JSON sidecar generated from the table)
  status: confirmed

## Acceptance Criteria
- [ ] AC1 — Given the merged manifest, when `bash loomwright/scripts/check-qa-removal-manifest.sh` runs with no `--expect` on `main`, then it exits 0 and every `delete` and `re-point` row reports `pending` (pinned by a self-test fixture that mirrors the base state, and by a real-repo leg asserting exit 0 with no refusal).
- [ ] AC2 — Given a fixture repo where one `delete` path marked `11b1` still exists, when the checker runs `--expect 11b1`, then it exits non-zero (1) and its output names that path.
- [ ] AC3 — Given a fixture repo where a `keep` path (e.g. `loomwright/scripts/verify-provides.sh`) is missing, when the checker runs `--expect 11b1`, then it exits non-zero (1) and names that path.
- [ ] AC4 — Given a fixture where a `re-point` file still names `qa-executor`, when the checker runs `--expect 12`, then it exits non-zero (1) and names the file and the reference.
- [ ] AC5 — Given a manifest row whose action is not `delete` / `re-point` / `keep`, then the checker refuses the manifest (exit 2, naming the row), never skips the row. The same refusal (exit 2) covers an item not in `11b1` / `11b2` / `12`, a header row count that differs from the parsed row count, a duplicate (path, reference) row, a `keep` row and a `re-point` row naming the same (path, reference), and an unknown `--expect` value.
- [ ] AC6 — Given the committed manifest, then every path named in the requirement's Scope has a row — `loomwright/capabilities.json`, `.claude-plugin/marketplace.json` (counts and keywords), `loomwright/.claude-plugin/plugin.json` (description counts), `.github/workflows/ci.yml` (the Playwright pin and cache steps), `loomwright/hooks/hooks.json` (the two matchers), each of the 9 tracked files under `.claude/agent-memory/loomwright-loomwright-qa-executor/`, `loomwright/docs/prompt-token-budgets.json` and its mirror table in `loomwright/docs/ARCHITECTURE_CONTRACTS.md`, and the `CLAUDE.md` agent-roles table — asserted by a self-test leg over the real manifest; and the manifest header carries the row count on a column-0 line `Row count: <N>` that the checker verifies against its parsed rows (exit 2 on mismatch), so the real number red team C7 asked for is committed in the diff (FINALIZE's PR body links the manifest).
- [ ] AC7 — Given the manifest, then it carries `keep` rows (item `11b1`, so every `--expect` level checks them) for `loomwright/scripts/verify-provides.sh`, `loomwright/scripts/test-verify-provides.sh`, the `outputs_verified` gate's home, the `unit-testing` and `quality-checklist` skills, `classify_kind`'s `qa-executor` arm in `loomwright/scripts/exec-acceptance-lib.sh` and `run-ground-truth.sh`'s deferred `qa-executor` branch (each with a reason naming Phase 3 item 09 / D18), plus `keep` rows for the manifest, the checker, its self-test, `CHANGELOG.md` and `docs/evidence/` history files that name QA terms.
- [ ] AC8 — Given the manifest, then it has a `## Rollback` section naming the tag `pre-qa-removal` (created on `origin/main` as 11b1's first step, not here) and listing what to re-add by hand (agents, commands, skills, hooks.json matchers, token-budget entries, CI Playwright steps, agent-memory dir, counts in the manifests).
- [ ] AC9 — Given the generation search, then it ran over `git ls-files` minus `selvedge/` (never `find`, which sees gitignored dirs) for every QA name the requirement lists, and every script that builds an agent or skill name from a table (the notify / webhook / telemetry / routing / token-ledger name maps) has a `re-point` row (the derived-name risk); the manifest's `## How this list was generated` section records the exact search command(s) and the date.
- [ ] AC10 — Given the PR diff, when `git diff --name-status <base>...HEAD` is listed, then it shows only `A` for the three new files and the `changelog.d/` fragment and `M` for `loomwright/docs/vendor-coupling-manifest.json` — no QA file is deleted or edited, and no tag is created.
- [ ] AC11 — Given the branch, when `bash loomwright/scripts/test-check-qa-removal-manifest.sh` runs, then it passes all legs; `bash scripts/check-vendor-coupling.sh` is green with the new doc's measured allowance; `bash scripts/ci-local.sh --affected` passes; `bash scripts/check-version-bump.sh` passes.

## Scope widening
- loomwright/docs/vendor-coupling-manifest.json
- accepted: LP-SCOPE 2026-11-18

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| checker | — | `loomwright/scripts/check-qa-removal-manifest.sh` (new responsibility: parse + check the manifest — its own module), `loomwright/scripts/test-check-qa-removal-manifest.sh` (its offline self-test, auto-run by CI's `loomwright/scripts/test-*.sh` glob — no `ci.yml` / `ci-local.sh` edit needed) | HIGH |
| manifest | `loomwright/docs/vendor-coupling-manifest.json` (817 — append one `allowances` + one `allowance_reasons` entry: the single authority for per-path allowances, no new responsibility) | `loomwright/docs/qa-removal-manifest.md`, `changelog.d/qa-removal-manifest.md` | HIGH (paths) / MEDIUM (row count) |

> Not modified, though the requirement's Touches lists them: `scripts/ci-local.sh` and `.github/workflows/ci.yml` — the new self-test is picked up by the existing `loomwright/scripts/test-*.sh` glob in both (`suite=(loomwright/scripts/test-*.sh …)` in `scripts/ci-local.sh`).

## Touched-file invariants

> Grounded at base `a1b2ee589e752a2962e47335d29a5784d48f14de`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/docs/vendor-coupling-manifest.json`** — keep: valid JSON and the measured-allowance rule, quoting `A value is the count the gate itself measured on the commit that introduced or last raised it` (so the new value is what `bash scripts/check-vendor-coupling.sh` reports for the new doc, never hand-typed) and `A path absent from this map has an allowance of 0`; keep: the reason rule, quoting `REQUIRED for every allowance that is new or higher than the base manifest's` — add exactly one `allowances` entry and one matching one-line `allowance_reasons` entry for `loomwright/docs/qa-removal-manifest.md` (the reason names `qa-split/11a` and that the doc lists harness paths to delete); add NO entry for the checker or its self-test — they must stay at 0 by not naming any vendor token (fixture paths avoid the harness config dir). mirror: the consumer is `scripts/check-vendor-coupling.sh` (`BASE_REF="${VENDOR_COUPLING_BASE:-origin/main}"` drives the raise_check). pinned by: `scripts/test-check-vendor-coupling.sh` (runs the gate, including a control on the real tree).

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-check-qa-removal-manifest.sh` — delete row present at `--expect 11b1` ⇒ exit 1 naming the path | delete the line in `loomwright/scripts/check-qa-removal-manifest.sh` that marks a selected `delete` row `MISMATCH` when its path exists |
| `loomwright/scripts/test-check-qa-removal-manifest.sh` — keep path missing at `--expect 11b1` ⇒ exit 1 naming the path | delete the line in `loomwright/scripts/check-qa-removal-manifest.sh` that marks a selected `keep` row `MISMATCH` when its path is absent |
| `loomwright/scripts/test-check-qa-removal-manifest.sh` — re-point file still names `qa-executor` at `--expect 12` ⇒ exit 1 naming file + reference | delete the `grep -F` reference check for `re-point` rows in `loomwright/scripts/check-qa-removal-manifest.sh` |
| `loomwright/scripts/test-check-qa-removal-manifest.sh` — unknown action ⇒ exit 2 | delete the catch-all action arm that refuses the manifest in `loomwright/scripts/check-qa-removal-manifest.sh` (the row would then be skipped) |
| `loomwright/scripts/test-check-qa-removal-manifest.sh` — header `Row count:` ≠ parsed rows ⇒ exit 2 | delete the row-count comparison in `loomwright/scripts/check-qa-removal-manifest.sh` |
| `loomwright/scripts/test-check-qa-removal-manifest.sh` — no `--expect` on a base-state fixture ⇒ exit 0, every delete/re-point row `pending` | flip the no-`--expect` exit status from `0` to `1` in `loomwright/scripts/check-qa-removal-manifest.sh` |
| `loomwright/scripts/test-check-qa-removal-manifest.sh` — unknown item (not `11b1`/`11b2`/`12`) ⇒ exit 2 | delete the catch-all item arm that refuses the manifest in `loomwright/scripts/check-qa-removal-manifest.sh` |
| `loomwright/scripts/test-check-qa-removal-manifest.sh` — duplicate (path, reference) row ⇒ exit 2 | delete the duplicate-key check in `loomwright/scripts/check-qa-removal-manifest.sh` |
| `loomwright/scripts/test-check-qa-removal-manifest.sh` — a `keep` and a `re-point` row on the same (path, reference) ⇒ exit 2 | delete the keep/re-point conflict check in `loomwright/scripts/check-qa-removal-manifest.sh` |
| `loomwright/scripts/test-check-qa-removal-manifest.sh` — unknown `--expect` value ⇒ exit 2 | delete the `--expect` value check in `loomwright/scripts/check-qa-removal-manifest.sh` (an unknown value would then select nothing and exit 0) |
| `loomwright/scripts/test-check-qa-removal-manifest.sh` — `--expect 11b2` still checks an `11b1` delete row and does not check a `12` row | flip the "at or before" item comparison to an exact-match comparison in `loomwright/scripts/check-qa-removal-manifest.sh` |
| `loomwright/scripts/test-check-qa-removal-manifest.sh` — real-repo leg (no `--expect`, exit 0, no refusal) | flip the default manifest path in `loomwright/scripts/check-qa-removal-manifest.sh` to a non-existent file name (the missing-manifest refusal, exit 2, turns the leg red) |
| `loomwright/scripts/test-check-qa-removal-manifest.sh` — `AC6 scope rows`: the real manifest has a row for each Scope-named path | delete the `loomwright/hooks/hooks.json` row from `loomwright/docs/qa-removal-manifest.md` (and lower `Row count:` by one) |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Checker + offline self-test (defines the manifest row format) | AC1 (fixture half), AC2, AC3, AC4, AC5, AC11 (self-test) | 0 modify, 2 create | `loomwright/skills/unit-testing/SKILL.md`, `loomwright/skills/quality-checklist/SKILL.md` | LAUNCHABLE |
| 2 | Generate the manifest, real-repo self-test legs, vendor-coupling allowance, changelog fragment | AC1 (real-repo half), AC6, AC7, AC8, AC9, AC10, AC11 | 2 modify, 2 create | `loomwright/skills/quality-checklist/SKILL.md` | BLOCKED (by #1) |

**Manifest format (the contract between subtasks 1 and 2 — subtask 1 documents it in the checker's header comment; subtask 2 writes to it):**
- A column-0 line `Row count: <N>` before the table; `<N>` is the number of data rows.
- One table under the heading `## Rows`, header exactly `| path | reference | action | item | reason |`, then a `|---|…` separator, then one data row per entry. `path` is repo-relative (a file or a directory, no leading `./`), in backticks; `reference` is the named old string in backticks (a whole-path row writes `—`); `action` ∈ `delete` | `re-point` | `keep`; `item` ∈ `11b1` | `11b2` | `12`; `reason` is one line.
- Order of items: `11b1` < `11b2` < `12`. `--expect <item>` selects every row whose item is at or before `<item>`.
- Per selected row: `delete` ⇒ `MISMATCH` if the path exists; `keep` ⇒ `MISMATCH` if the path is missing, or, when a reference is given, the file no longer contains it (`grep -F`); `re-point` ⇒ only at `--expect 12`: `MISMATCH` if the file still contains the reference, or the file is missing. Non-selected rows and the no-`--expect` mode report `pending` / `done` / `ok` and never fail.
- Output: one line per row, `<status> <action> <item> <path>` plus ` :: <reference>` when there is one, then a summary line; exit 0 (clean or report-only), 1 (≥1 `MISMATCH`), 2 (refused manifest or bad usage — named on stderr).
- Flags: `--expect <11b1|11b2|12>`, `--manifest <file>` (default `loomwright/docs/qa-removal-manifest.md` under the root), `--root <dir>` (default: the repo root resolved from the script's own location) — the self-test runs every fixture in a `mktemp -d` root.

## Parallelism Analysis

### Dependency Graph
```
Subtask 2 ──→ Subtask 1
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | `loomwright/scripts/test-check-qa-removal-manifest.sh` (subtask 2 appends the real-repo legs) | YES (sequential — 2 requires 1, legal sharing) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after Subtask 1)
- **Recommended workers:** 1
- **Estimated batches:** 2

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/check-qa-removal-manifest.sh"}
  - {kind: "symbol", path: "loomwright/scripts/check-qa-removal-manifest.sh", name: "--expect"}
  - {kind: "symbol", path: "loomwright/scripts/check-qa-removal-manifest.sh", name: "Row count:"}
  - {kind: "file", path: "loomwright/scripts/test-check-qa-removal-manifest.sh"}
  - {kind: "symbol", path: "loomwright/scripts/test-check-qa-removal-manifest.sh", name: "hermetic-test-env.sh"}
requires: []
lanes:
  - "loomwright/scripts/check-qa-removal-manifest.sh"
  - "loomwright/scripts/test-check-qa-removal-manifest.sh"
external_requires: []

# Subtask 2
provides:
  - {kind: "file", path: "loomwright/docs/qa-removal-manifest.md"}
  - {kind: "symbol", path: "loomwright/docs/qa-removal-manifest.md", name: "## Rows"}
  - {kind: "symbol", path: "loomwright/docs/qa-removal-manifest.md", name: "## Rollback"}
  - {kind: "symbol", path: "loomwright/docs/qa-removal-manifest.md", name: "pre-qa-removal"}
  - {kind: "symbol", path: "loomwright/docs/vendor-coupling-manifest.json", name: "loomwright/docs/qa-removal-manifest.md"}
  - {kind: "symbol", path: "loomwright/scripts/test-check-qa-removal-manifest.sh", name: "AC6 scope rows"}
  - {kind: "file", path: "changelog.d/qa-removal-manifest.md"}
requires:
  - {from: "1", kind: "file", path: "loomwright/scripts/check-qa-removal-manifest.sh"}
  - {from: "1", kind: "file", path: "loomwright/scripts/test-check-qa-removal-manifest.sh"}
lanes:
  - "loomwright/docs/qa-removal-manifest.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "loomwright/scripts/test-check-qa-removal-manifest.sh"
  - "changelog.d/qa-removal-manifest.md"
external_requires: []
```

**Subtask 1 notes:** bash 3.2 / BSD-safe; the test's first executable line is `. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"` (`scripts/check-test-hermetic.sh`); no temporary locale prefix (`env LC_ALL=C sort`, never `LC_ALL=C sort` — `scripts/check-locale-prefix.sh`); no bare `mkdir` lock (`scripts/check-mkdir-lock.sh`); guard empty-array expansions under `set -u`; no vendor tokens in either file (fixture paths use plain dirs like `agents/x.md`, not the harness config dir) so their vendor-coupling allowance stays 0. Fixture legs: AC1 base-state (all delete/re-point `pending`, exit 0), AC2, AC3, AC4, AC5 (each refusal case its own leg, exit 2, row named), plus a `--expect 11b2` leg proving an `11b1` delete row is still checked and a `12` row is not.

**Subtask 2 notes:** generate rows from `git ls-files | grep -v '^selvedge/'` (never `find`) searched for every QA name: `qa-executor`, `qa-strategist`, `playwright-e2e`, `qa-gates`, `qa-orchestration`, `qa-strategy`, `qa-test-patterns`, `verify-walkthrough`, the `verify` command, `QA_SYSTEM_BLUEPRINT`, the `/verify` scripts (`verify-run.sh`, `verify-env.sh`, `verify-helpers.sh`, `read-verify.sh`, `verify-fixture-app.py`, `propose-verify.sh`, `propose-from-verify.sh`), `.agent/verify.json`, `VERIFY_EVIDENCE` / `VERIFY_ENV` / `VERIFY_RESULT` / `VERIFY_QUEUE` / `QA_RESULT` / `QA_SESSION`, `validate-qa-result.py`, `validate-verify-evidence.py`, `read-playwright-pin.sh` and the ci.yml Playwright steps — then read the name-map scripts for derived names. Item assignment follows the sibling requirements' scopes (`11b1-remove-qa-agents-commands-skills.md`, `11b2-remove-qa-scripts-schemas-ci.md`, `12-re-point-qa-couplings-to-selvedge.md`). Do NOT restate plugin counts as literals in the doc (e.g. never write "14 agent roles" — reference the description field instead), so 11b1's count edits never make this doc stale. Measure the doc's vendor-coupling count with `bash scripts/check-vendor-coupling.sh` and record exactly that number. Append to the self-test: a real-repo leg labelled `real-repo` (no `--expect`, exit 0, no refusal) and a leg labelled `AC6 scope rows` asserting each AC6 path has a row. That leg must not name a vendor token (the test's vendor-coupling allowance stays 0): it checks the 9 agent-memory rows by the suffix `agent-memory/loomwright-loomwright-qa-executor/` and a count of exactly 9 data rows under it, never by writing the harness config dir prefix. Row references and reasons name things by text (a function, a matcher, a step name), never by a bare `file:N` line number — `loomwright/scripts/test-citation-drift.sh` scans `loomwright/docs/*.md` and fails an unpinned one. Fragment: `changelog.d/qa-removal-manifest.md`, `<!-- bump: patch -->` or `minor` per `changelog.d/README.md`, prose body naming the row count.

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `loomwright/skills/unit-testing/SKILL.md`, `loomwright/skills/quality-checklist/SKILL.md` |
| 2 | `loomwright/skills/quality-checklist/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): the manifest + checker + test likely exceed 800 changed lines | MEDIUM | `context-bound` split into 2 sequential subtasks; the row format is fixed in this brief so subtask 2 cannot drift from the parser |
| Feasibility (Phase 2.5): the new doc names `.claude/agent-memory/…` and `SubagentStop`, which the vendor-coupling ratchet counts | MEDIUM | one measured allowance + reason in `loomwright/docs/vendor-coupling-manifest.json` (outside Touches — `LP-SCOPE`); checker and test carry no vendor token |
| A reference by a derived (runtime-computed) name is invisible to a literal grep | HIGH | AC9: every name-map script gets a `re-point` row; the worker reads each map, not only grep hits |
| A file has both a kept reference (the deferred `qa-executor` arm in `exec-acceptance-lib.sh` / `run-ground-truth.sh`) and other QA references | MEDIUM | `keep` rows carry the specific reference; the checker refuses a `keep` and `re-point` row on the same (path, reference); 12 re-points other references only |
| The doc restates a count that 11b1 then changes (house rule: one authoritative place per count) | MEDIUM | the doc never writes plugin count literals; its own `Row count:` is verified by the checker against its rows, so it cannot drift silently |
| A real-repo self-test leg that asserts "every row pending" would break as soon as 11b1 deletes paths | LOW | the real-repo leg asserts exit 0 and no refusal only; `pending` wording is pinned on a base-state fixture |
| Concurrent agents in this checkout may revert uncommitted edits (project memory) | LOW | workers run in worktrees; commit early |

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-18-qa-removal-manifest-and-checker.md
```


## Outcome
- **Status:** completed
- **Completed:** 2026-11-18T12:51:55Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/944
- **Branch:** feature/qa-removal-manifest-and-checker
- **Files changed:** 5
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** armed
- **Summary:** Committed the 434-row QA-removal manifest (loomwright/docs/qa-removal-manifest.md, Row count verified by the checker), the fail-closed check-qa-removal-manifest.sh (report-only with no --expect; per-row gate at --expect 11b1|11b2|12; exit 2 on a malformed manifest) and its 197-check hermetic self-test, a measured vendor-coupling allowance (16) and a patch changelog fragment. Phase 4.5: round 1 PASS with 2 MEDIUM manifest-precision findings fixed in 673bf3b (narrowed the schema-versioning.md qa-executor re-point + keep row on the kept kind; Rollback CI clause corrected); round 2 PASS with 3 LOW left as dismissed follow-ups. Ground truth 2/2 pass. No QA file deleted or edited, no tag created.

## Not verified
- **check-qa-removal-manifest.sh against the real committed manifest (AC1 real-repo half, AC6)** — loomwright/docs/qa-removal-manifest.md is created by subtask 2, which appends those legs (subtask 1)
- **the --expect 11b1/11b2 gates on the real removal PRs** — item assignment of re-point rows comes from reading tests and gates, not from deleting files; a missed gate shows up in that PR, which then edits the row (subtask 2)
