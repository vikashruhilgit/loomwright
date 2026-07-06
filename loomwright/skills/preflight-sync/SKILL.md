---
name: preflight-sync
description: Protocol authority for Supervisor Phase 1.5 PRE-FLIGHT SYNC — CLEAR/OVERLAP/SUPERSEDED remote-state reconciliation of the requested work against recent origin/$BASE_BRANCH commits and open PRs, before Phase 2 PLAN spawns anything. Read on demand at phase entry, deliberately not preloaded.
version: "1.0.0"
lastUpdated: "2026-07-06"
---

# Pre-Flight Sync Protocol (Supervisor Phase 1.5)

> **Read at phase entry (Phase 1.5) — deliberately NOT preloaded into any agent frontmatter.**

This skill is the single source of truth for the Supervisor's **Phase 1.5 PRE-FLIGHT SYNC**
(remote-state reconciliation) gate. The Supervisor reads this file at Phase 1.5 entry and
executes the protocol below; `agents/supervisor.md` keeps only a short phase stanza with the
entry/exit conditions. The protocol prose below is moved verbatim from the Supervisor prompt.

---

## Protocol

**Purpose:** Before any tokens are spent on decomposition or execution, reconcile the *requested work* against remote state — recent `origin/$BASE_BRANCH` commits and open PRs — to catch (a) in-flight or recently-landed work that touches the **same files** this task will touch, and (b) an **already-merged equivalent** of the requested work. Derive the canonical version and base-branch tip SHA. Classify the task as **CLEAR | OVERLAP | SUPERSEDED** and surface overlaps to the human (or fail closed in CI) *before* Phase 2 PLAN spawns the Orchestrator or any worker.

**Entry:** Runs AFTER Phase 1 ACQUIRE has produced a task and a fresh feature branch, BEFORE Phase 2 PLAN. Skipped entirely when `--skip-preflight-sync` was passed (see AC5 below).

**What this is NOT (scope guard):** Phase 1 ACQUIRE already does `git fetch origin "$BASE_BRANCH"` + `git pull` so the feature branch starts fresh (the ACQUIRE branch-creation step), and the existing `base_branch_mismatch` path (Phase 4 self-verify → Phase 4.5 cleanup) only checks the *PR's `baseRefName`* against `$BASE_BRANCH`. **Neither detects that the requested *work* overlaps with or is superseded by recent commits / open PRs.** This gate adds that *semantic work-overlap reconciliation* and MUST NOT duplicate or weaken either the existing fetch/pull or the post-hoc base-mismatch path. Reuse Phase 1's `git fetch` result where it is fresh — do not redundantly re-fetch if ACQUIRE just fetched `$BASE_BRANCH`.

**Bounded budget (AC7):** the entire phase is capped at **≤ 6 tool calls and a short timeout** (treat ~20s per `gh`/`git` invocation as a SOFT guideline — there is no native per-call shell timeout, so this is an advisory budget the agent self-enforces by passing an explicit Bash `timeout`, not a hard bound). On any tooling unavailability or error (`gh` not installed/authenticated, `git fetch` failure, timeout), record "pre-flight unverified", emit ONE warning, set `preflight_sync = unverified`, and **continue to Phase 2** — NEVER hard-block on a tooling failure.

**Actions:**

1. **Skip check (AC5):** If `--skip-preflight-sync` was passed (parsed in Phase 0's base-branch / non-interactive preamble — the step 5a block), record the skip as a deliberate choice and short-circuit straight to Phase 2:
   ```
   Context-Keeper(operation: record_decision, phase: PRE_FLIGHT_SYNC,
                  decision: "preflight_skipped", rationale: "--skip-preflight-sync flag")
   ```
   Set `preflight_sync = skipped` and proceed to Phase 2. Do NOT run any of the steps below.

2. **Gather remote state (bounded):**
   ```bash
   # Reuse Phase 1's fetch if it just ran against $BASE_BRANCH; otherwise:
   git fetch origin "$BASE_BRANCH"
   BASE_TIP=$(git rev-parse --short "origin/$BASE_BRANCH")
   git log --oneline "origin/$BASE_BRANCH" -20        # recent history (N≈20)
   gh pr list --state open --json number,title,headRefName   # list open PRs (portable across gh versions)
   # then, for the bounded set of candidate PRs, fetch changed files per-PR:
   gh pr view <n> --json files                               # per-PR file listing for the same-file overlap check
   # (gh >= 2.x also supports `gh pr list --json ...,files` as a single-call optimization)
   ```
   Derive the **canonical version** (from `plugin.json` / manifest on `origin/$BASE_BRANCH`, or the task's stated target) and the **base-branch tip SHA** (`BASE_TIP`). If `gh` or `git fetch` errors → graceful degradation (set `preflight_sync = unverified`, one warning, continue — see Bounded budget above).

   **Per-PR scan bound:** inspect at most N≈3 candidate open PRs (one `gh pr view <n> --json files` call per candidate), prioritised by title / `headRefName` overlap with the task; skip the rest within the ≤6-call budget. Record how many of the open PRs were file-inspected for the Output block disclosure.

3. **Determine the task's anticipated file set:** use the job brief's **File Impact Map** when present (the `job:` brief lists per-subtask MODIFY/CREATE paths); otherwise derive from the task title + criteria.

4. **Classify CLEAR | OVERLAP | SUPERSEDED** using these required signals:
   - **(a) same-file overlap → OVERLAP:** a recent `origin/$BASE_BRANCH` commit (from `git log`) OR an open PR whose changed files intersect the task's anticipated file set. Record the intersecting paths and the commit SHAs / PR numbers.
   - **(b) already-merged equivalent → SUPERSEDED:** recent `origin/$BASE_BRANCH` history already implements the requested work. This is the motivating case behind the **v13.1.0→v14.0.0 stale-branch incident** (work was branched from a stale base and re-implemented something already merged) — cite the specific landing commit(s). SUPERSEDED requires BOTH a topic match (the commit message or PR title names the same feature / versioned component as the task) AND a file overlap (changed files intersect the anticipated file set) — either signal alone is insufficient (prevents a topic-only false SUPERSEDED).
   - Otherwise → **CLEAR.**

5. **Stacked-iteration scoping (AC6):** when `$BASE_BRANCH ≠ main` (the `/autonomous` loop stacks iteration N+1 on iteration N's branch), scope the overlap comparison to `$BASE_BRANCH` only and do NOT flag the **parent iteration's own commits or PR** as overlap — those are the legitimate base this iteration builds on, not a competing change. No false positive against the stacked-PR chain.

6. **Act on the classification:**

   - **CLEAR (AC2 — silent):** proceed to Phase 2 with no extra prompt. Record a one-line pre-flight summary and set `preflight_sync = clear`:
     ```
     Context-Keeper(operation: record_decision, phase: PRE_FLIGHT_SYNC,
                    decision: "preflight_clear",
                    rationale: "version={canonical_version}, base_tip={BASE_TIP}, no overlap")
     ```

   - **OVERLAP / SUPERSEDED in an interactive session (AC3):** present an `AskUserQuestion` (mirroring **Launch Pad's** Phase 2.5 feasibility soft-gate) BEFORE spawning any worker. The question MUST cite the **specific overlapping commit SHAs / PR numbers AND the intersecting file paths**. Three options:
     - **proceed-anyway** → set `preflight_sync = overlap_proceed` (OVERLAP) or `superseded_proceed` (SUPERSEDED); record the decision (`record_decision(phase: PRE_FLIGHT_SYNC, decision: "preflight_overlap_proceed" | "preflight_superseded_proceed", rationale: "{cited commits/PRs + paths}")`); continue to Phase 2.
     - **revise-scope** → pause and checkpoint; do NOT spawn any worker. Keep the existing feature branch, `record_decision(phase: PRE_FLIGHT_SYNC, decision: "preflight_revise_scope", rationale: "{cited overlap}")`, and emit a single `SUPERVISOR_RESULT` with `status: checkpoint` and `preflight_sync: null` (the classification lives in the Decisions Log entry above, not the field — and a well-formed result block keeps the SubagentStop validator happy), then exit with a resume command. The user re-invokes `/supervisor` with the narrowed/redirected task (reusing the branch, or `git checkout $BASE_BRANCH && git branch -D feature/{old}` first if the new scope warrants a different branch name); Phase 1.5 then re-evaluates the revised scope against remote state on the next run. Do NOT silently fall through to Phase 2.
     - **abort** → fail the run cleanly (no worker spawned): record `record_decision(phase: PRE_FLIGHT_SYNC, decision: "preflight_abort", rationale: "{classification} — {cited commits/PRs + paths}")`, mark the task `failed`, move the job brief to `failed/` if a `job:` was used, and emit a single `SUPERVISOR_RESULT` with `status: failed`, `error: "preflight_overlap_detected: {classification} — {cited commits/PRs + paths}"`. Do NOT proceed to Phase 2.

   - **OVERLAP / SUPERSEDED under CI / non-interactive (AC4 — fail closed):** re-read the non-interactive state LIVE (do NOT trust in-context state alone — W-NEW-10):
     ```
     ni = Context-Keeper(operation: get_flag, key: "non_interactive")
     ```
     If `ni` is set (or `--non-interactive` was passed) OR **stdin is not a TTY**, an OVERLAP/SUPERSEDED classification **FAILS CLOSED** — UNLESS `--skip-preflight-sync` was passed (which would already have short-circuited in step 1). Abort with a diagnostic: mark the task `failed`, move the job brief to `failed/` if a `job:` was used, and emit a single `SUPERVISOR_RESULT` with:
     - `status: failed`
     - `SUPERVISOR_RESULT.error = "preflight_overlap_detected"` (the dedicated reason — surfaced by the `/autonomous` loop as `AUTONOMOUS_RUN.status_reason: "preflight_overlap_detected"`)
     Do NOT spawn any worker, do NOT proceed to Phase 2.

**`preflight_sync` field (SUPERVISOR_RESULT, see the Supervisor's "Result Block"):** records this phase's outcome — `clear` (CLEAR, silent), `overlap_proceed` (OVERLAP, user proceeded), `superseded_proceed` (SUPERSEDED, user proceeded), `skipped` (`--skip-preflight-sync`), or `unverified` (graceful degradation). Optional/additive — `schema_version` stays 1.

**Output:**
```markdown
### Phase 1.5: PRE-FLIGHT SYNC
- Canonical version: {version} | Base tip: {BASE_TIP}
- Open PRs scanned: {count} | Recent commits scanned: {N}
- PRs file-inspected: {n} of {open_count}
- Classification: CLEAR | OVERLAP | SUPERSEDED | UNVERIFIED (tooling degraded) | SKIPPED (--skip-preflight-sync)
- Overlap: none | {cited commit SHAs / PR #s + intersecting paths}
- Decision: proceed (silent) | proceed-anyway | revise-scope | aborted (fail-closed) | skipped
- preflight_sync: clear | overlap_proceed | superseded_proceed | skipped | unverified
```
