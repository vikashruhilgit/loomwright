# Supervisor Job: One projector, one contract — `build-floor.sh` → `floor.json`

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main @ 23e4b10 (== origin/main, includes PR #172 + #173)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1
- **Source requirement:** .supervisor/requirements/loom-floor-ui/03-floor-projector.md

Warning: the requirement's nine-surface table is a **snapshot measured 2026-09-01** and several
values have already moved. Re-measured 2026-09-02 (below). Treat that table as *shape*, never as
contract values — the hermetic-fixture AC recomputes against known counts instead.
**These counts are a moving target even within one session:** the largest log measured 11,600 →
11,627 → 11,657 lines over ~40 minutes as this very run appended to it. That is the argument for
the counting-basis AC in miniature — a bare number with no stated basis and no timestamp is already wrong.

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash + jq, matching `build-insights.sh` / `build-handoff.sh`, the two sibling projectors this mirrors. |
| 2 | Dependency Availability | GO | `jq` 1.7.1 present; the jq-absent AC requires a `command -v jq` skip-with-exit-0 anyway. |
| 3 | Architecture Fit | GO | `build-insights.sh` is a direct structural precedent (read-only, deterministic, `set -uo pipefail` without `set -e`, exit 0 always, writes one gitignored derived artefact). |
| 4 | Scope vs Supervisor Capability | GO | One script + one self-test + a schema block. Smaller than item 02. |
| 5 | Hard Blockers | CAUTION | No blocker, but the requirement asks for **per-input mtimes**, which walks straight into the `stat` flavour trap this repo has already been burned by. See Risk 1. |

**Overall Verdict:** GO

## Task
**Goal:** Ship `build-floor.sh`, a deterministic read-only projector that reads the nine scattered `.supervisor/` surfaces and emits one versioned, schema-documented `floor.json` that every later view consumes instead of re-parsing raw state.

**Problem Statement:**
Any future view of Loomwright's run state needs data that is real and already on disk, but scattered across nine surfaces in four formats (markdown tables, folder membership, JSONL, JSON). Currently each consumer would parse them itself, so every view re-implements the same nine parsers and drifts independently. Exactly one thing should read them.

Success looks like: one file that is the contract, carrying its own `schema_version`, its own freshness, and — critically — omitting what it cannot prove rather than defaulting it.

**Measured on-disk truth, 2026-09-02 (recompute; do not hard-code these):**

| Surface | Value now | Requirement said (2026-09-01) |
|---|---|---|
| `jobs/{pending,in-progress,done,failed}/` | 0 / 0 / 90 / 2 | 0 / 0 / 88 / 2 |
| `logs/*.jsonl` | **65** | "98 files" — see the counting-basis note |
| `drain-rounds/*.json` | 495 | 487 |
| `worker-summaries/*.md` | 114 | 112 |
| `postmortem/results.jsonl` | 87 lines | 85 |
| `automate/*.md` | 8 run files | "1 run file" |
| `.agent/rules/*.json` | 2 | 2 |
| largest log | **11,657** lines at 15:0x (100% carry `cc_session_id`), **124** distinct via `jq … | sort -u | wc -l` | 10,271 lines / 116 sessions |

**The counting-basis divergence is the single most important finding here, and it is this item's whole thesis in miniature.** `.supervisor/logs/` holds **99 directory entries**: 65 `.jsonl` session logs plus **34 plain `.log` files** — modally `review-pr-dispatch-*.log` (24 of 34), then `pr-postmortem-dispatch-*.log` (4), plus `failures.log`, `notifications.log`, `worktrees.log`, `twin.log`. The requirement's "98 files" counted directory entries; a `*.jsonl` glob counts 65. Both readings are defensible and they differ by 34. The sibling `build-insights.sh` settles it by globbing `*.jsonl` explicitly. `floor.json` MUST declare its counting basis per surface rather than emitting a bare number a consumer has to guess at.

## Acceptance Criteria
- [ ] Given a **hermetic fixture tree built by the test** (`mktemp -d` + `git init`, mirroring `test-build-handoff.sh` / `test-insights.sh` / `test-reconcile-resume-state.sh`, which all do this) populated with a **known** number of job, log, drain-round, worker-summary and ledger entries, when `build-floor.sh` runs against it, then every count in `floor.json` equals the fixture's known value — recomputed independently — **and the test FAILS if any counted section is absent or zero**, so an empty tree can never satisfy it. A negative-control fixture with a deliberately wrong count must turn the assertion red.
- [ ] Given the real `.supervisor/` is present (local dev only), when the same recomputation runs against it, then it agrees; when it is absent the test prints an explicit **`SKIPPED — <reason>`** line and that skip is **reported, never silently counted as a pass**. This split is mandatory, not stylistic: `.gitignore:78` is `.supervisor/*`, so eight of the nine input surfaces are absent from every fresh clone and worktree, while `ci.yml` runs every `loomwright/scripts/test-*.sh` as a hard gate — a real-tree assertion would compare 0 to 0 and go silently green there.
- [ ] Given each counted surface, when `floor.json` is read, then every count is accompanied by an explicit **counting basis** (the glob or predicate that produced it), so `logs: 65` can never be confused with `logs: 99`.
- [ ] Given a **committed synthetic JSONL fixture** with a known distinct `cc_session_id` count (e.g. 3 ids across 7 lines, plus one line missing the field entirely), when sessions are segmented, then they are grouped by `cc_session_id` (never by filename) and the count equals that known value exactly, with the field-less line accounted for explicitly. The 11,657-line live log is a **local-only corroboration**, never the CI subject.
- [ ] Given a missing input directory, an empty log, and a malformed JSON input (three separate cases), then the affected section is omitted, the reason is named in the output, and the script exits 0. An unreadable input reports **`unverified`**, never `clean`.
- [ ] Given `jq` absent, then the script skips with a named reason and exits 0.
- [ ] Given `floor.json`, when validated, then the test **parses the required-key set out of the `## FLOOR_PROJECTION` block in `loomwright/docs/RESULT_SCHEMAS.md`** and validates against that parsed set — following the existing precedent in `loomwright/scripts/eval-corpus/emit-block-parses/check.sh`, which parses `check-contract-parity.sh`'s MANIFEST out of the source rather than restating it — so a doc/validator divergence FAILS. A payload with any one required key removed is rejected **with a diagnostic naming that key**, and a control proves the same validator PASSES the unmodified payload, so the rejection is discriminating rather than blanket. A hand-copied key list inside the test does not satisfy this. **The block MUST use the annotated-YAML convention** already used by `MISSING_FUNCTIONALITY_REPORT` in the same file (one key per line with a trailing `# <type>, required` / `# <type>, optional` marker) — a bare fenced JSON example in the `GROUND_TRUTH_JSON` style carries no required/optional marking, leaving nothing to parse and silently implying every field is mandatory, which contradicts the omit-absent-evidence rule.
- [ ] Given no state change, when the script is run twice with **two different injected generation timestamps** (a `SOURCE_DATE_EPOCH`-style env seam), then the unified diff of the two **raw, unfiltered** outputs has exactly one changed line pair and that line is the generation-timestamp field; run twice with the **same** injected timestamp, the outputs are byte-identical with zero diff lines. A source-level assertion pins exactly one clock read in the script, and a negative-control variant embedding a second clock read must fail it. (Filtering the timestamp line before diffing would pass vacuously — two runs share the same wall-clock second, so the filter would never be exercised.)
- [ ] Given a hermetic fixture tree, when it is hashed before and after a run — the hash set being every regular file under the fixture root via `find . -type f -not -path "./.git/*" -not -path "./.supervisor/floor/*"`, `LC_ALL=C` sorted and content-hashed, with **ignored files IN SCOPE and git never consulted** — then the two hashes are identical and `floor.json` is the only path that appeared. **Git must not be used for this check:** `.gitignore:78` ignores the entire `.supervisor/` tree, and a probe file written into `.supervisor/logs/` is reported by neither `git status --porcelain` nor `--ignored` (measured), so a git-based tree hash sees neither an illegal write nor the legitimate output and the assertion could never fail. A mutation control — a variant that writes one byte to `.supervisor/state.md`, gated on the mutant still being executable — must turn this assertion RED.
- [ ] Given a freshness field, when it is computed, then it is derived via the repo's existing helper shape at `build-handoff.sh` (GNU `stat -c %Y` **first**, BSD `stat -f %m` second, empty on failure, numeric-validated before any arithmetic). Falsified with a **`stat` STUB placed first on `PATH`** that exits 0 printing a non-numeric string (`/`, mimicking GNU `stat -f %m` returning a mount point): the field must be **OMITTED** from `floor.json` — not empty, not `0`, not the raw string — and no arithmetic attempted on it; a control run without the stub asserts the same field is present and numeric. **Copy the helper, not its call sites:** `build-handoff.sh`'s callers do `e="${e:-0}"`, the plausible-default this item forbids.
- [ ] Given the schema is added, when `loomwright/docs/RESULT_SCHEMAS.md` is read, then its intro `Current versions:` paragraph names `FLOOR_PROJECTION` with its `schema_version` and no-hook-validator status, and `### Version History` gains a dated entry — matching the `EVAL_RESULT` / `GROUND_TRUTH_JSON` precedent. Neither is machine-enforced (`check-doc-currency.sh` does not scan this file; the contract-parity MANIFEST is fixed and hook-scoped), so both are asserted here or not at all.

## Outcomes Rubric
- One reader, one schema, one file; no downstream view parses a raw surface.
- Session boundaries are correct today, with no emitter change, using a field already present.
- Absent evidence is visibly absent rather than silently defaulted.
- Byte-identical on re-run; provably writes nothing else.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | `build-floor.sh` projector + documented schema + self-test | AC 1-11 (all) | 6 modify, 3 create | `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` | LAUNCHABLE |

```yaml
# Subtask 1 — the whole item (LAUNCHABLE)
provides:
  - {kind: "file", path: "loomwright/scripts/build-floor.sh"}
  - {kind: "file", path: "loomwright/scripts/test-build-floor.sh"}
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "## FLOOR_PROJECTION"}
  - {kind: "file", path: "loomwright/scripts/fixtures/floor-sessions.jsonl"}
requires: []
lanes:
  - "loomwright/scripts/build-floor.sh"
  - "loomwright/scripts/test-build-floor.sh"
  - "loomwright/scripts/fixtures/floor-sessions.jsonl"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - "CHANGELOG.md"
  - "CLAUDE.md"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 (single, independent)
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | — | n/a (single subtask) | n/a |

### Batch Plan
- **Batch 1:** Subtask 1
- **Recommended workers:** 1
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| **The `stat` flavour trap — the stat-portability AC exists because of a real CI failure here.** The requirement asks `floor.json` to record each input's mtime. `stat -f %m` is BSD and **succeeds with garbage on Linux**, and a non-numeric value in `$(( ))` under `set -u` silently empties the field. This repo shipped exactly that bug once (macOS 29/29 green, Linux CI red). | HIGH | Reuse the **existing** `mtime_epoch()` shape from `loomwright/scripts/build-handoff.sh` verbatim: GNU `stat -c %Y` first, BSD `stat -f %m` second, empty on failure — the order is load-bearing. Validate numeric before arithmetic; omit the field on failure. Do not invent a new helper; `build-loop-evidence.sh` documents avoiding `stat` altogether for this reason and is the fallback design if mtimes prove unreliable. |
| **A bare count is the bug this item exists to kill.** `logs` is 65 or 99 depending on basis — a 34-file difference between two defensible readings, and the requirement itself picked the other one. | HIGH | The counting-basis AC: every count carries its basis in the artefact. Mirror `build-insights.sh`'s explicit `*.jsonl` glob. The test recomputes independently rather than asserting the script's own number back at itself. |
| **The requirement's numbers are already stale** (7 of 8 surfaces moved in one day; one appears to have shrunk only because of the basis ambiguity). A brief or test that hard-codes them will be wrong by merge time. | MEDIUM | No AC asserts a literal count. The hermetic-fixture AC recomputes. The measured table above is dated and labelled as shape-not-contract. |
| **Byte-identical re-run vs embedded clocks.** The byte-identical AC forbids any clock read other than the single generation timestamp. A stray `date` in a per-surface field, or unsorted jq object keys / unsorted glob order, silently breaks determinism. | MEDIUM | Sort every enumeration (`LC_ALL=C`), use `jq -S` or an explicit key order, and diff two runs **raw and unfiltered** under two *different* injected timestamps. **Never filter before diffing** — two consecutive runs share the same wall-clock second, so a filtered diff exercises nothing and passes with the defect present. |
| **Vendor-coupling ratchet.** A new file under `loomwright/scripts/*` is CORE with allowance 0. This script should need no vendor token (it reads `.supervisor/` and `.agent/`), but a test fixture naming `.claude/` would breach. | MEDIUM | `git add` first, then `bash scripts/check-vendor-coupling.sh --print-allowances`; declare measured numbers only if a breach is real. Prefer renaming a fixture path over raising an allowance — item 02's heal did exactly that. |
| **"Writes nothing else" is easy to claim and easy to violate** via a temp file, a lock, or a jq `>` redirect landing outside the output dir. | MEDIUM | The tree-hash AC hashes via `find` with **ignored files in scope and git never consulted** — `.supervisor/` is *ignored*, not untracked, and a probe written there is reported by neither `git status --porcelain` nor `--ignored` (measured), so any git-based check is unfalsifiable. Keep temp files inside `.supervisor/floor/` or `mktemp -d`. |
| **A schema that rejects nothing.** The schema-parse AC's second half is the real test; a "schema" that is prose or an always-true jq filter passes trivially. | MEDIUM | The test must feed a payload with a required key removed and assert the validator FAILS with its specific diagnostic — plus a control proving it PASSES on the valid payload, so the failure is discriminating. |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Design decisions (for Plan Review to challenge)

1. **Schema block name `## FLOOR_PROJECTION` in `RESULT_SCHEMAS.md`.** That file's existing blocks are emitted *result* contracts (`LAUNCH_PAD_RESULT`, `REVIEW_HEAL_RESULT`); `floor.json` is a derived artefact, closer to the `AUTOMATE_RUN` state-file contract already documented there. The requirement says to put it there "rather than in a new file", so it goes there — named as a projection, not a RESULT, to avoid implying a hook-validated emitted block.
2. **Counting basis is emitted per surface, not documented once.** A consumer reading `floor.json` alone must be able to tell what a number counted. This is a small size cost for the property the whole item is about.
3. **The session fixture goes in the existing `loomwright/scripts/fixtures/`**, not a new `floor-fixtures/` directory — two fixture directories already exist (`fixtures/`, `progress-event-fixtures/`) and a third for a single file is drift.
4. **`.supervisor/floor/` is gitignored** by the existing `.supervisor/*` rule, matching `.supervisor/insights/`. The artefact is derived and regenerable; nothing commits it.

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-02-floor-projector.md
```
