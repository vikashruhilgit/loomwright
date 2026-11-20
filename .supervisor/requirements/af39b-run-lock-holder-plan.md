# Task Plan: af39b-run-lock-holder

Source brief: .supervisor/jobs/in-progress/2026-10-14-af39b-run-lock-holder.md (base adce64f)

## EPIC af39b-run-lock-holder — run lock records a live holder under any harness

- [ ] **af39b-1 (TASK, single worker, no worktree fan-out)** — run-lock holder resolution + pid_start fingerprint + degraded stderr line, the two close-out callers, caller prose, docs, changelog fragment, evidence
  - Acceptance: brief ACs 1-14 (all)
  - Lanes: brief `## Subtask Contracts` lanes list (18 paths)
  - Blocked by: nothing
  - Skills: skills/unit-testing/SKILL.md, skills/quality-checklist/SKILL.md
  - Gate: outputs_verified (verify-provides.sh) + targeted tests (test-run-lock.sh, test-automate-trail.sh, test-automate-lanes.sh) + check-doc-currency.sh + test-citation-drift.sh + check-token-budget.sh + check-vendor-coupling.sh (after git add) + check-version-bump.sh
  - No paired review subtask; Phase 4.5 integrated review after FINALIZE.
