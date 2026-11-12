<!-- Fixture brief, paired with the repo/ directory beside it. Pinned by scripts/test-design-decisions.sh. Not a real job. -->
# Supervisor Job: URL-safe note file names

## Environment
- **Project:** fixture-notes-api (bash scripts under `scripts/`; the `repo/` directory beside this brief)
- **Base commit:** 0000000000000000000000000000000000000000

## Task
**Goal:** `scripts/new-note.sh` names each note file after a URL-safe slug of its title, through a new `scripts/slugify.sh` helper.

**Problem Statement:**
A title with spaces or punctuation produces a file name that breaks links today. Success looks like `notes/<slug>.md` for every title.

## Design decisions
- decision: where the title-to-slug conversion lives
  chosen: a new `scripts/slugify.sh` defining `slugify()`, sourced by `scripts/new-note.sh`
  rejected: inline `tr` and `sed` in `scripts/new-note.sh` — reversibility: partial, a second caller would copy it
  evidence: `grep -n slug package.json` → no match, so the manifest declares no slug library
  revisit when: a second language needs the same slugs
  status: confirmed

## Acceptance Criteria
- [ ] **AC1:** `bash scripts/new-note.sh "Hello, World"` creates `notes/hello-world.md`.
- [ ] **AC2:** a title with only punctuation exits non-zero and creates nothing.
- [ ] **AC3:** `test/new-note.test.sh` covers AC1–AC2 and passes.

## Touched-file invariants

- **`scripts/new-note.sh`** — keep: `set -euo pipefail` and the final `echo "notes/$title.md"` output line (with `$title` replaced by the slug); pinned by: `test/new-note.test.sh`, which this change creates.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Slugged note file names | AC1–AC3 | 1 modify, 2 create | unit-testing | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "scripts/slugify.sh"}
  - {kind: "symbol", path: "scripts/slugify.sh", name: "slugify"}
requires: []
lanes:
  - "scripts/new-note.sh"
  - "scripts/slugify.sh"
  - "test/new-note.test.sh"
external_requires: []
```

### File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| notes | `scripts/new-note.sh` | `scripts/slugify.sh`, `test/new-note.test.sh` | HIGH |

## Parallelism Analysis
- **Batch 1:** Subtask 1
- **Recommended workers:** 1

## Skill References
- `skills/unit-testing/SKILL.md`

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Two titles map to one slug | LOW | AC2 rejects an empty slug; a collision overwrites, as today. |

## Configuration
- **Mode:** sequential
- **Recommended workers:** 1

## Handoff
/supervisor job: .supervisor/jobs/pending/fixture-note-slugs.md
