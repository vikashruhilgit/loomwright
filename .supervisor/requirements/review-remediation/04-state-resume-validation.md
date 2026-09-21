# 04 — Fail-closed validation of .supervisor/state.md on resume (P0, small)

## Goal
Supervisor's resume path (`/supervisor --continue`) refuses to act on a state file whose
`phase`/`status` (and minimally-required fields) don't parse against the known schema,
instead of steering the run from unvalidated local state. Same fail-closed philosophy as
Phase 1.5 preflight and the rubric gate.

## Evidence
- `loomwright/agents/supervisor.md` Phase 1 ACQUIRE reads `.supervisor/state.md` on resume
  and acts on its phase/status with no schema rejection — in contrast to every result block,
  which is hook-validated.
- Prior incident class: the v14.34.0 PostToolUse-hook fix specifically had to stop a "stale
  terminal state.md" from short-circuiting dispatch — same trust-unvalidated-state root cause.
- Threat is low (gitignored, local) but a corrupted/stale/hand-edited file could send the
  agent toward FINALIZE-like behavior, skipping phases.

## Scope
1. **`loomwright/agents/supervisor.md`** — in Phase 1 ACQUIRE resume branch, add a strict
   parse gate BEFORE any state is consumed:
   - `## Session` block must exist; `phase` must be in the closed set actually used by the
     state-management skill (enumerate from `loomwright/skills/state-management/SKILL.md` —
     read the file for the authoritative set, do not invent one); `status` must be in its
     closed set; branch field, if asserted, must match an existing local branch
     (`git rev-parse --verify`).
   - On ANY violation: refuse resume, `status: failed`, new closed error value
     `error: "resume_state_invalid"`, and instruct the user to inspect/delete state.md or
     start fresh. NEVER silently fall back to fresh-start (that would mask corruption).
2. **`loomwright/skills/state-management/SKILL.md`** — document the closed enums as the
   authoritative validation contract (one new subsection, "Resume validation gate"), and
   bump skill version.
3. **`loomwright/docs/RESULT_SCHEMAS.md`** — add `resume_state_invalid` to the
   SUPERVISOR_RESULT error values if errors are enumerated there (verify first); this is
   additive, NO schema_version bump.
4. **`loomwright/commands/supervisor.md`** — one row in the (new, from item 01) flag table
   note or Troubleshooting: what `resume_state_invalid` means and how to recover. Mirror
   agent↔command prose in the same commit.
5. **CLAUDE.md** — one line under Common Pitfalls "Supervisor workflow interrupted?"
   mentioning the gate.

## Constraints / invariants
- Fail CLOSED, no `--skip-*` escape hatch for this gate in v1 (deleting the bad state file
  IS the escape hatch); if review argues for one, `--force-resume` may be added but must be
  logged in the session JSONL.
- Context-Keeper sole-writer contract untouched — this is a READ-side gate only.
- No new hooks, counts unchanged. Minor version bump + CHANGELOG.
- Prompt-is-program discipline (memory): dynamically trace the resume path for idempotency —
  a valid resume must behave exactly as before; run the trace for: valid file, missing file
  (fresh start, unchanged), unknown phase, unknown status, valid-but-branch-gone.

## Acceptance criteria
- [ ] supervisor.md Phase 1 contains the gate with the closed enums sourced from
      state-management SKILL.md (cite section).
- [ ] `resume_state_invalid` documented in RESULT_SCHEMAS.md (if error enum exists there),
      commands/supervisor.md, and CLAUDE.md pitfall line — all in one commit.
- [ ] Valid-resume behavior byte-identical in prose (no semantic drift to the happy path).
- [ ] check-command-sync.sh + doc-currency green.

## Out of scope
Automated state repair, structured state recovery from job dirs (existing manual procedure
stands), validating `## Phase Flags` contents beyond parseability.

## Status: done
- Completed 2026-07-06 via /automate → PR #94 (v15.3.0), Phase 4.5 PASS, heal_iterations 1.
