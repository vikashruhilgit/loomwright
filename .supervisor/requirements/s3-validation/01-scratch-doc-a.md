# 01 — S3 validation throwaway item A (pa/05 Validation 4)

## Status: done_with_escalation — ABANDONED (- [x] .supervisor/requirements/s3-validation/01-scratch-doc-a.md  # abandoned: throwaway pa/05 Validation 4/5 item; PR #429 closed unmerged by design)

## Depends on
none

## Touches
docs-scratch/s3-validation-a.md

## Problem
pa/05's Validation 4 needs a real `/automate --parallel 2` run on two small, disjoint, THROWAWAY items. This is one of them. Its PR is closed unmerged after the validation; nothing lands on main.

## Goal
Create one new file with one line, nothing else.

## Scope
1. Create `docs-scratch/s3-validation-a.md` containing exactly this single line:
   `S3 validation throwaway item A — created by an /automate --parallel 2 lane; this PR is closed unmerged.`
2. Change no other file. No tests, no docs, no changelog fragment, no version bump.

## Acceptance criteria
- `docs-scratch/s3-validation-a.md` exists and contains exactly the one line above.
- `git diff --name-only origin/main...HEAD` lists only `docs-scratch/s3-validation-a.md`.

## Validation (must pass before merge)
1. `cat docs-scratch/s3-validation-a.md` shows the one line. (This PR is never merged — it is closed after pa/05 Validation 4.)

## Non-goals
Everything else. Do not edit any existing file.

## Status: done_with_escalation — ABANDONED (- [x] .supervisor/requirements/s3-validation/01-scratch-doc-a.md  # abandoned: throwaway — PR closed unmerged after pa/05 Validation 4)
