# Supervisor Job: Apply the committable-Twin capability to this repo — scrub, re-index, negate, commit

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — 159 lines, v15.26.0 banner matches `plugin.json:3`)
- **Git:** clean (0 files), branch: main @ 1aef108
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (4 stale `.claude/worktrees/` checkouts present; they must REMAIN ignored — an assertion target, not a blocker)
- **Source requirement:** .supervisor/requirements/twin-loop/01b-apply-to-this-repo.md

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + git + jq, identical to the item-01 capability this consumes |
| 2 | Dependency Availability | GO | `loomwright/scripts/setup-memory.sh` merged (PR #126, `aee5734` on `origin/main`); `check` runs clean, reports `not configured` |
| 3 | Architecture Fit | GO | Pure data migration — consumes the shipped capability unchanged. No capability code touched, no version bump, counts unchanged |
| 4 | Scope vs Supervisor Capability | GO | 3 modify + 1 create + 1 delete → single subtask per the Decomposition Threshold default |
| 5 | Hard Blockers | GO | The ledger — the one part that required capability work — is descoped (see Scope Note) |

**Overall Verdict:** GO

### Scope Note — the ledger is deliberately OUT of scope (owner decision, 2026-08-07)

The source requirement's Scope §2 and its acceptance criteria call for the findings ledger (`.supervisor/postmortem/results.jsonl`) to be filtered and committed. **Two rounds of Plan Review proved that cannot be done as data work**, and the owner has split it into its own item (`01c-commit-the-ledger.md`). Recorded here so a later reader does not re-litigate it:

1. **The shipped managed block does not cover the ledger.** A hand-added negation placed after the block is relocated above `.supervisor/*` by the next `apply` (`setup-memory.sh:369-372` re-emits the block at EOF), silently re-excluding the parent directory. `render_report` probes only `INTENDED_PATHS` (`setup-memory.sh:145-148`), so the verdict would still read `configured` — latent, silent rot.
2. **The ledger is structurally CROSS-REPO by contract.** `skills/pr-postmortem/SKILL.md:21` — appends land in the *current working* `.supervisor/`, never the analyzed repo's. That is exactly how this repo accumulated its 7 `otherhub` records. Promoting the ledger to a **default** managed path would un-ignore an **unfiltered** cross-repo file in every repo a user runs `/setup memory apply` in (`apply` does not filter — `filter-ledger` only prints, `setup-memory.sh:52-53`), generalizing the very contamination this queue exists to remediate.
3. **It would silently break the consent contract.** `print_consent_disclosure()` (`setup-memory.sh:638-658`) enumerates exactly two stores and `:656-657` asserts everything else stays ignored; `commands/setup.md:319` requires that copy shown **verbatim**. A third managed store makes it materially false across five mirror sites.

Doing it correctly needs an opt-in flag or a fail-closed gate plus the full consent surface — capability work, tracked in `01c`. **This item consumes the capability exactly as shipped and leaves the ledger gitignored.** No publication risk follows: an ignored ledger is never committed, so its foreign records are never published.

## Task
**Goal:** Bring this repo's two Twin memory stores to a publishable state — redact the one foreign-repo citation, repair the `code-reviewer` index — then apply the item-01 negations and commit.

**Problem Statement:**
This repo needs its accumulated Twin memory under version control because it exists on one machine with no recovery path. Currently the stores cannot be committed safely: one memory entry cites a private work repo, and the largest memory index lists 1 of its 18 entries. `vikashruhilgit/loomwright` is PUBLIC, so committing before the scrub publishes work-repo engineering data irreversibly — and once pushed it cannot be unpublished. Success looks like every committed file containing only loomwright-related content, proven by a guard that the known contamination cannot return.

## Acceptance Criteria
- [ ] Given `setup-memory.sh apply` has run, when `git check-ignore --verbose` is run over every intended path, then `.claude/agent-memory/**` and `.supervisor/memory/**` — including the dot-prefixed sidecars `.provenance.jsonl` and `.lessons-provenance.jsonl` — are committable, each asserted individually.
- [ ] Given the same negations, when the unintended paths are checked, then `.claude/worktrees/`, `.claude/settings.local.json`, `.supervisor/logs/`, `.supervisor/jobs/`, `.supervisor/automate/`, `.supervisor/requirements/` and `.supervisor/postmortem/` all remain ignored — the ledger's continued ignored status is an explicit assertion, not an omission.
- [ ] Given the naive negation form (`.claude/` + `!.claude/agent-memory/`), when it is exercised in a fixture, then it is pinned as a proven-failing negative control alongside the working `/*` form.
- [ ] Given the redaction is applied, when `project_self_heal_rubber_stamp.md` is read, then it retains its finding, its `**Why:**` and `**How to apply:**` lines, keeps the `this repo #24/#26/#36/#41` half, and carries no foreign PR numbers.
- [ ] Given the index is merged from `MEMORY--premigration.md` (16 pointers) reconciled against the 18 entry files on disk, when `code-reviewer`'s `MEMORY.md` is compared to its directory, then every entry file has exactly one pointer line and no pointer references a missing file — the ≥2 never-indexed entries get hooks derived fresh from their `description:` frontmatter.
- [ ] Given the merge is complete, when the store is listed, then `MEMORY--premigration.md` is gone and the commit message records that it was **merged, not discarded**.
- [ ] Given the durable guard test, when it runs in the clean post-migration state, then a static whole-word case-insensitive deny-list (`otherhub`, `hub`) returns zero hits across an EXPLICIT file list covering both committed stores including the dot-prefixed sidecars — and the guard FAILS when a `otherhub #146`-shaped citation is re-added.
- [ ] Given the one-time migration audit, when the commit lands, then the terms derived from the ledger's `.repo` values and the exact derivation command are recorded as provenance in the test header, so the next sweep reproduces the method rather than a guessed string form.
- [ ] Given every new test, when it runs, then it makes ZERO writes under the real repo root — any `apply`/`remove` exercise runs against a `mktemp -d` + `git init` fixture via `setup-memory.sh --root` (`setup-memory.sh:70,131-136`) with `trap … EXIT` cleanup, per `test-no-junk-tracked-files.sh:62-71`.
- [ ] Given `apply` writes `.gitignore.backup.<ts>` at repo root and seeds `.supervisor/config.json` (creating `.supervisor/config.json.backup.<ts>`), when the change is staged, then a `.gitignore.backup.*` ignore line is added in the same commit and no backup artifact is staged.
- [ ] Given a `memory: project` agent is spawned after the change, when it reports from injected context only, then it still receives its store (probe re-run, not inferred).

## Outcomes Rubric
- `.gitignore` contains the `setup-memory.sh` managed block in its `/*` form, plus a `.gitignore.backup.*` ignore line, and no hand-added negation outside the block sentinels.
- The diff commits both memory stores including the two dot-prefixed sidecars, and commits nothing under `.supervisor/postmortem/`, `.supervisor/logs/`, `.supervisor/jobs/`, `.supervisor/automate/` or `.claude/worktrees/`.
- A new executable `loomwright/scripts/test-*.sh` exists whose deny-list sweep uses an explicit file list (not a bare recursive grep, which skips dotfiles) and carries a negative control that fails on a re-added `otherhub #146` citation.
- `project_self_heal_rubber_stamp.md`'s diff removes every foreign PR number while keeping the `**Why:**` and `**How to apply:**` lines.
- `code-reviewer/MEMORY.md` has 18 `- [` pointer lines and `MEMORY--premigration.md` is deleted in the same diff.
- No file outside `.gitignore`, the two memory stores, and `loomwright/scripts/` is modified — in particular `setup-memory.sh` itself is byte-unchanged.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Scrub, re-index, negate, commit | all | 3 modify, 1 create, 1 delete | `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md`, `skills/commit/SKILL.md` | LAUNCHABLE |

```yaml
# Subtask 1 — this repo's data migration (LAUNCHABLE)
provides:
  - {kind: "file", path: "loomwright/scripts/test-committed-twin-scrub.sh"}
  - {kind: "symbol", path: "loomwright/scripts/test-committed-twin-scrub.sh", name: "assert_no_foreign_terms"}
  - {kind: "file", path: ".gitignore"}
  - {kind: "file", path: ".claude/agent-memory/loomwright-loomwright-code-reviewer/MEMORY.md"}
  - {kind: "file", path: ".claude/agent-memory/loomwright-loomwright-code-reviewer/project_self_heal_rubber_stamp.md"}
requires: []
lanes:
  - "loomwright/scripts/test-committed-twin-scrub.sh"
  - ".gitignore"
  - ".claude/agent-memory/**"
  - ".supervisor/config.json"
external_requires:
  - "git >= 2.30 (check-ignore --verbose)"
  - "jq (allowlist seed path inside setup-memory.sh)"
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
| 1 | `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md`, `skills/commit/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Publishing to a PUBLIC repo is irreversible.** Anything the scrub misses is public on push and stays in history | HIGH | Pre-run sweep already executed (terms derived from the ledger's `.repo` values, whole-word, case-insensitive): `otherhub` 0, `othercorp` 0, `hub` 1 — the single known hit. Durable guard re-asserts it; staged diff reviewed file-by-file before commit |
| **The sweep returns a false clean.** Two prior audits missed `otherhub #146` by grepping `/hub`; a recursive grep also skips dotfiles by default, hiding the two `.provenance.jsonl` sidecars | HIGH | Whole-word case-insensitive matching over an EXPLICIT file list that names the dot-prefixed sidecars; negative control fails on a re-added citation. Derivation method recorded in the test header, not just its result |
| **Naive negation silently no-ops.** Git cannot re-include a file whose parent directory is excluded — the `/*` form is required | HIGH | Assert with `git check-ignore --verbose`; pin the naive form as a proven-failing negative control (item 01's precedent) |
| **The test rewrites the real `.gitignore`.** CI hard-globs `loomwright/scripts/test-*.sh` (`ci.yml:62-67`), so an unisolated `apply`/`remove` cycle mutates the repo and litters backups on every run | MEDIUM | All cycles run against `mktemp -d` + `git init` via `--root`, with `trap … EXIT`; the test asserts zero writes under the real repo root |
| **Predictable untracked artifacts get staged.** `apply` always writes `.gitignore.backup.<ts>` at repo root and `.supervisor/config.json.backup.<ts>`; no `.gitignore` pattern matches them and `test-no-junk-tracked-files.sh:45` only flags leading-`-` basenames | MEDIUM | Add a `.gitignore.backup.*` ignore line in the same commit and delete the artifacts before staging |
| **`git add -A` over a newly un-ignored tree sweeps in unintended files** | MEDIUM | Review the staged diff file-by-file; the rubric pins the allowed path set and names the directories that must contribute nothing |
| **Index merge loses curation.** `MEMORY--premigration.md` holds 16 already-curated hooks that cannot be regenerated (source sessions are gitignored and partly gone) | MEDIUM | Start FROM the premigration list, reconcile against disk, delete only after the merge is verified 18/18; commit message records the merge |
| **The durable guard is a regression net, not full coverage.** Its deny-list is static, so a NEW foreign org first appearing in a memory file is uncaught — a real class: `#129` is cited in the memory file but appears nowhere in the ledger, because memory is distilled from cross-repo sessions | LOW | State the limit explicitly; general detection is item 04's fifth check, which the source requirement already assigns there. Do not let a green guard be read as full coverage |
| **Tracking makes memory writes into working-tree changes** | LOW | Known and accepted by item 01 (documented `TRACKED-WRITE RISK`); out of scope |
| **A concurrent heal/automate loop sweeps uncommitted edits** into its own commit | LOW | This run owns the single-open-PR slot; verified 0 open PRs at plan time |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-08-07-twin-01b-apply-to-this-repo.md
```
