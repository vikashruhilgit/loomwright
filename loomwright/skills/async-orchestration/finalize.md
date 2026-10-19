# Async Orchestration — Phase 4 FINALIZE protocol (Part 2)

Read by the Supervisor at Phase 4 FINALIZE entry only. A citation of `skills/async-orchestration/SKILL.md` "Part 2" steps or "Part 2 PR Body Template" means this file; `agents/supervisor.md` §"Phase 4: FINALIZE" keeps the mandatory gate list. Step numbering (1–7 incl. 5.5 and 6.5) is stable, so cross-file references such as "Phase 4 self-verify (step 6.5)" resolve here. Why: `docs/rationale/supervisor.md` §"Phase 4 FINALIZE — why the steps read as they do".

## Phase 4 FINALIZE procedure (steps 1–7)

**Actions:**

1. **Pre-merge safety gate** (ALL must pass before any merge) — **run by `scripts/supervisor-next-step.sh`**: `finalize` checks points 1–4 (WORKER_RESULTs `completed`; per-subtask gate decision `PASS`, vacuous on the inline paths; every `merge_order` worktree / branch present with changes, no orphans; the feature branch holds the base tip — a failure aborts the merge, job → `failed/`; a missing worktree / branch ⇒ checkpoint + resume command). `finalize-children` runs point 5, `check-children-settled.sh --all`, before any merge: `settled` / `no_identity_rows` pass; `unsettled` / `unverifiable` ⇒ the SUP-CHILDREN ask or, under the Can't-ask rule, `children_unsettled: {ids}` (fail CLOSED), with `ended_without_result_ids` / `rejected_stop_ids` beside the ids; `--skip-children-check` ⇒ `user_skipped_children_check`. After steps 2–5.5, `finalize-marker` calls `guard-finalize-publish.sh write-marker` and prints the publish instruction only once it exits 0. Steps 2–3 cover the branches in `merge_order` only; a read-only subtask (`WORKER_RESULT.no_changes: true`) is absent from it, but its worktree is still removed in step 4. Legacy-path text: `docs/supervisor-legacy-phases.md`.

2. **Commit worker changes in worktrees** (before merging):
   ```bash
   # For each completed subtask (in merge_order from EXECUTE_RESULT):
   git -C ../project-{subtask_a} add -A
   git -C ../project-{subtask_a} commit -m "subtask: {subtask_a} — {title}"
   ```

3. **Sequential merge** of each subtask branch into feature branch (in merge_order):
   ```bash
   git checkout feature/{task_id}-{desc}
   git merge feature/{subtask_a} --no-ff -m "merge: {subtask_a} {title}"
   git merge feature/{subtask_c} --no-ff -m "merge: {subtask_c} {title}"
   git merge feature/{subtask_b} --no-ff -m "merge: {subtask_b} {title}"
   ```
   If merge conflict: **STOP** — never force-resolve. Report conflicting files. Checkpoint with list of already-merged and not-yet-merged branches. Exit with resume command:
   ```markdown
   ## MERGE CONFLICT

   **Feature branch:** feature/BD-XX-desc
   **Merging:** feature/BD-XXb
   **Conflicting files:** [list]

   **Options:**
   1. Resolve manually, then: /supervisor --continue task: BD-XX
   2. Abort merge: git merge --abort
   ```

4. **Cleanup worktrees** (ONLY after successful merge):
   ```bash
   # Salvage uncommitted content, then remove the worktree, then the branch
   bash scripts/worktree-salvage.sh ../{project}-{subtask_id} --reason "FINALIZE step 4"   # protocol form (runtime form: agents/supervisor.md §Phase 4 gate 3)
   git worktree remove ../{project}-{subtask_id}
   git branch -d feature/{subtask_id}
   ```
   The salvage line runs as its own statement — never joined to the remove by `&&` — and always exits 0; it prints a `.supervisor/salvage/` path only when there was uncommitted content. The plain remove still refuses a dirty tree; if it refuses, report the refusal AND the salvage path the line above printed — do NOT reach for `--force` as a reflex, and never without the salvage line having run. `bash scripts/worktree-audit.sh report` (read-only) lists recorded siblings git still shows — it reports, never removes.

5. **Create commits** (inline, following `skills/commit/SKILL.md`):
   - Stage all changes
   - Write conventional commit message with task linking
   - Format: `feat|fix|refactor({scope}): {message}\n\nCloses {task_id}`
   - **NEVER code-fence the message.** The first line passed to `git commit` MUST be the conventional-commit subject (e.g. `feat({scope}): {message}`) — never a ```` ``` ```` / ```` ```bash ```` fence. Pass multi-line messages as separate `-m` flags or via `git commit -F -` / a heredoc (see `skills/commit/SKILL.md` → "Passing the Message to git").

5.5. **Release re-fold (#512) — after step 5's commits, BEFORE `write-marker` and step 6's push:**
   ```bash
   bash scripts/release-refold.sh   # protocol form — the runtime-resolvable form is agents/supervisor.md §Phase 4 FINALIZE gate 5
   ```
   A no-op (exit 0) unless the project has a fold-capable `scripts/bump-version.sh` and this branch already carries a bump with a `changelog.d/` fragment still pending; then it re-folds every fragment into that ONE bump and commits it (HEAD moves, so it runs before `write-marker`). It then runs `bump-version.sh --check`, so a hand-edited version file or CHANGELOG.md also exits non-zero. Non-zero ⇒ abort FINALIZE before the push, like a failed pre-merge gate: no push, no PR, log its printed reason, `SUPERVISOR_RESULT.status: failed` with `error: "release_refold_refused"`, run lock released on this abort exit.

6. **Push and create PR (against `BASE_BRANCH` — defaults to `main`):**
   ```bash
   git push -u origin feature/{task_id}-{desc}
   gh pr create --base "$BASE_BRANCH" --title "{task_id}: {title}" --body "{PR body}"
   ```
   `BASE_BRANCH` is the value resolved at Phase 0 (`skills/supervisor-config/SKILL.md`) from the `--base-branch` flag, defaulting to `main`.

6.5. **Phase 4 FINALIZE self-verify — PR base branch** — run by the driver's `pr-verify` / `pr-verify-answer` steps from the PR URL you report: `baseRefName` == `BASE_BRANCH` ⇒ hand-over; different ⇒ the `base_mismatch_detected` flag (`reason: phase4_self_verify`); a `gh` failure ⇒ ONE retry after 5 s, then the SUP-GH-RETRY ask (retry / skip-verify-once ⇒ `user_skipped_base_verify` / abort ⇒ the flag, `reason: user_aborted_gh_retry`), or under `--non-interactive` the flag with `reason: gh_unavailable_non_interactive`. Phase 4 sets the flag at most once and never emits `SUPERVISOR_RESULT` here — Phase 4.5's base-mismatch cleanup (`skills/self-heal-advisory/escalation.md` §"Phase 4.5 base-mismatch cleanup (step 5)") is the single emission point.

7. **Exit FINALIZE** — the driver's `handover` step (`done`, `next: "phase-4.5"`). The task is NOT yet marked completed and the job file is NOT yet moved — Phase 4.5 SELF_HEAL's completion tail does both.

**Safety guarantees:**
- Worker code lives in git branches until explicitly merged — can always recover
- If EXECUTE_CHECKPOINT (partial): only merge subtasks whose `outputs_verified` gate passed (no per-subtask reviewer decision to gate on), leave in-progress worktrees intact

**PR Body Template:**
```markdown
## Summary
{One paragraph describing the changes}

## Changes
- {Bullet list of key changes}

## Test Plan
- {How to verify the changes}

## Evidence
- `docs/evidence/{slug}.md`

## Not verified
- **{surface}** — {reason} (subtask {id})

## Task
Closes {task_id}

---
Generated by Supervisor Agent v4
```

**`## Evidence` section (optional, #511):** one bullet per file the branch adds or modifies under `docs/evidence/` — `git diff --name-only --diff-filter=AM "origin/$BASE_BRANCH...HEAD" -- docs/evidence/`. **OMITTED ENTIRELY** (no heading, no "none" line) when that prints nothing. It only points at the files — evidence lives in the committed file, never in this body (Plan Reviewer Criterion 20); a file a later Phase 4.5 fix adds is not listed.

**`## Not verified` section (optional, harness-port/04):** aggregated by reading `state.md`'s `## Worker Results` section and collecting every worker's `not_verified` sub-list — one bullet per item, across ALL workers, `- **<surface>** — <reason> (subtask <id>)`. **OMITTED ENTIRELY** (no heading, no "none" line) when every worker's `not_verified` list is absent/empty (the `## Evidence` block follows its own rule). REPORT-ONLY: this section never gates FINALIZE, Phase 4.5, or a merge decision.
