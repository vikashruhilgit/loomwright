---
name: supervisor-config
description: Protocol authority for Supervisor Phase 0 INIT configuration resolution — flag/defaults table, cost-profile resolution, base-branch handling, environment detection. Read on demand at phase entry, deliberately not preloaded.
version: "1.1.0"
lastUpdated: "2026-07-07"
---

# Supervisor Config Protocol (Supervisor Phase 0 INIT)

> **Read at phase entry (Phase 0) — deliberately NOT preloaded.**

This skill is the single source of truth for the Supervisor's **Phase 0 INIT** (interactive
configuration) protocol: environment auto-detection, resume-state loading behind the fail-closed
Resume validation gate, cost-profile resolution (`--cheap`), the base-branch + non-interactive
preamble (flag parsing/defaults + crash-recovery flag clearing), `.supervisor/` directory
bootstrap, Context-Keeper initialization, and job-brief loading. The Supervisor reads this file at
Phase 0 entry and executes the protocol below; `agents/supervisor.md` keeps only a short phase
stanza with the entry/exit conditions. The protocol prose below is moved verbatim from the
Supervisor prompt.

---

## Protocol

**Purpose:** Configure session preferences before any work begins.

**Actions:**
1. Auto-detect environment:
   - Check if `.supervisor/` exists (previous sessions)
   - Check git status (clean/dirty)
   - Check for existing worktrees (`git worktree list`)
2. Check for resume state:
   - If `--continue` flag: load state from scratchpad → `.supervisor/state.md` (priority order)
   - **Resume validation gate (fail-closed — runs BEFORE any loaded state is consumed):** when a state file WAS loaded (from either location), validate it against `skills/state-management/SKILL.md` §"Resume validation gate" (the authoritative contract) before reading any field out of it or acting on its content:
     a. The `## Session` block must exist.
     b. `phase` must be one of `INIT | ACQUIRE | PLAN | EXECUTE | FINALIZE | SELF_HEAL | LOOP` and `status` one of `running | paused | completed | completed_with_escalation | failed` — the closed sets from that skill's §"State File Schema". Note: `PRE_FLIGHT_SYNC` is a `record_decision`-only phase label (it appears in the Decisions Log), NOT a valid state-file `phase` — a state file asserting it fails this gate.
     c. If the `## Session` block asserts a `branch:` field, `git rev-parse --verify <branch>` must succeed (the branch must still exist locally). The value is untrusted: pass it as a single quoted argument and pre-check `git check-ref-format --branch <value>` first (per `skills/state-management/SKILL.md` §"Resume validation gate") — a value failing ref-format fails this check.
     On ANY violation: REFUSE the resume. Emit `SUPERVISOR_RESULT` with `status: failed` and `error: "resume_state_invalid"`, plus a clear user message: inspect or delete `.supervisor/state.md` (and the scratchpad copy, if that is what failed), or start fresh without `--continue`. NEVER silently fall back to a fresh start — that would mask corruption. There is NO escape-hatch flag for this gate (deleting the bad state file IS the escape hatch). A MISSING state file is NOT a violation — "no state found → start fresh" is unchanged; the gate only fires on a file that loaded but does not parse against the contract.
   - If resume state found:
     a. **Before jumping to the saved phase**, hydrate session config from the loaded state: read `config.cost_profile` (default `default` if absent — handles pre-cheap state files). This ensures `cost_profile` is in memory for every subsequent spawn, regardless of which phase is resumed.
     b. If `--cheap` was also passed on this invocation: override to `cost_profile = cheap`.
     c. Jump to the saved phase.
3. Ask user (via `AskUserQuestion`) if not resuming:
   - "Max parallel workers?" (default: 2; skip if `--sequential`)
   - "Specific task to work on?" (or user provides via `task:` parameter)
3a. Parse cost profile flag (fresh start only — the resume path is handled by the resume-state check above):
   - If `--cheap` was passed: set `cost_profile = cheap`.
   - Otherwise: `cost_profile = default`.
   - Record in session memory — used at every subagent spawn in the Supervisor's Phases 2, 3, and 4.5.
4. Create `.supervisor/` directory structure if not exists:
   ```bash
   mkdir -p .supervisor/history .supervisor/jobs/pending .supervisor/jobs/in-progress .supervisor/jobs/done .supervisor/jobs/failed .supervisor/logs
   grep -qxF '.supervisor/' .gitignore 2>/dev/null || echo '.supervisor/' >> .gitignore
   ```
5. Initialize scratchpad state file via Context-Keeper:
   ```
   Context-Keeper(operation: initialize, config: {max_workers, mode, cost_profile}, session: {...})
   ```

5a. **Base-branch + non-interactive preamble (v14.0.0):**

   This preamble runs on **every** Phase 0 entry — both fresh start and `--continue` resume. The two `clear_flag` calls implement the **read-on-start, clear-on-start invariant** (see `skills/state-management/SKILL.md` §"Phase Flags") for crash-recovery flags: any pre-existing flag left over from a crashed prior session is cleared before this session can act on it.

   1. Parse `--base-branch <name>` from argv. Default to `main` if absent. Record as `BASE_BRANCH` in session memory (used by the Supervisor's Phase 4 FINALIZE PR creation, Phase 4 self-verify, and Phase 4.5 spawn prompts).
   2. Parse `--non-interactive` from argv. Default to `false` if absent. Record as `NON_INTERACTIVE` in session memory.
   2.5. Parse `--skip-preflight-sync` from argv. Default to `false` if absent. Record as `SKIP_PREFLIGHT_SYNC` in session memory (consumed by the Supervisor's Phase 1.5 PRE-FLIGHT SYNC — the skip check in `skills/preflight-sync/SKILL.md` short-circuits the gate as a deliberate choice).
   2.6. Parse `--no-auto-review` and `--auto-review` from argv. Default: **neither** (record `AUTO_REVIEW_FLAG = none`). If `--no-auto-review` is present record `AUTO_REVIEW_FLAG = suppress`; else if `--auto-review` is present record `AUTO_REVIEW_FLAG = force`. (`--no-auto-review` wins if both appear.) Consumed by the Supervisor's Phase 4.5 completion-tail review-drain dispatch step. **As of the until-mergeable default (AC7), the post-`/supervisor` review drain dispatches BY DEFAULT** on a PASS/normal completion that produced a PR — `AUTO_REVIEW_FLAG == suppress` (or `.supervisor/config.json` `.auto_review == false`; legacy `.supervisor/notify-config.json` is still read as a fallback, the new path wins when both exist) is now the OPT-OUT; `--auto-review` / `.auto_review == true` are the legacy explicit-enable signals, now redundant with the default but still honored. This only controls the post-`/supervisor` standalone review-and-heal dispatch — it never affects the in-Supervisor Phase 4.5 review-and-fix loop.
   2.6a. Parse the **until-mergeable** flags (consumed by the same Phase 4.5 dispatch step): `--no-until-mergeable` (record `UNTIL_MERGEABLE_FLAG = suppress`; else `none`) opts the dispatched drain out of `--until-mergeable` (the runner then runs the plain diff-only `/review-pr`); when `none`, `.supervisor/config.json` `.auto_until_mergeable` decides (**DEFAULT true** — the drain runs until-mergeable). Also capture the optional tuning values `--check-wait-timeout N` (record `CHECK_WAIT_TIMEOUT`) and `--review-check-pattern <glob>` (record `REVIEW_CHECK_PATTERN`); both are forwarded to the dispatcher ONLY when set and thread to the runner via the S2-pinned env-var signal contract (`skills/review-heal/SKILL.md` §"Until-Mergeable Dispatch Signal").
   2.7. Parse `--no-red-team` and `--red-team` from argv (mirrors the auto-review flag-pair precedent above). Default: **neither** (record `RED_TEAM_FLAG = none`). If `--no-red-team` is present record `RED_TEAM_FLAG = suppress`; else if `--red-team` is present record `RED_TEAM_FLAG = enable`. (`--no-red-team` wins if both appear.) When `RED_TEAM_FLAG == none`, `.supervisor/config.json` `.red_team_high_risk` (boolean; default false/absent) decides. Resolve and record `RED_TEAM_ENABLED = true` iff (`RED_TEAM_FLAG == enable`) OR (`RED_TEAM_FLAG == none` AND config `.red_team_high_risk == true`); otherwise `RED_TEAM_ENABLED = false`. Consumed by the Supervisor's Phase 4.5 **Advisory red-team lens** step — an OPT-IN, DEFAULT-OFF, FAIL-SAFE, strictly NON-GATING advisory pass for high-risk integrated diffs. It NEVER changes `heal_decision`, never drives the fix task, never gates, and never blocks the PR/run.
   2.8. Parse `--sdk-runner` from argv (**EXPERIMENTAL — opt-in, default OFF**). Default: `false` if absent. Record as `SDK_RUNNER` in session memory at Phase 0 INIT like the other flags. Consumed by the Supervisor's Phase 3 EXECUTE `--sdk-runner` branch: when `true`, Phase 3 shells out to the quarantined spike runner (`node "${CLAUDE_PLUGIN_ROOT}/sdk-spike/dist/runner.js" --brief <brief path> --branch <feature branch>` — cwd stays the user project; CLI contract: `sdk-spike/README.md`) instead of Task-spawning `execute-manager` (or the inline fast-path worker/reviewer loop). **Fail CLOSED at Phase 3:** if `node` is unavailable or `"${CLAUDE_PLUGIN_ROOT}/sdk-spike/dist/runner.js"` is absent when the flag is passed, the run aborts with `error: "sdk_runner_unavailable"` — never a silent fallback to the default path (`dist/` is gitignored and marketplace installs ship source only — build once with `npm install && npm run build` inside `${CLAUDE_PLUGIN_ROOT}/sdk-spike`). Zero change to the default path when the flag is absent.
   2.9. Parse `--multi-voter-heal` and `--no-multi-voter-heal` from argv (mirrors the red-team flag-pair precedent in 2.7). Default: **neither** (record `MULTI_VOTER_FLAG = none`). If `--no-multi-voter-heal` is present record `MULTI_VOTER_FLAG = suppress`; else if `--multi-voter-heal` is present record `MULTI_VOTER_FLAG = enable`. (`--no-multi-voter-heal` wins if both appear.) When `MULTI_VOTER_FLAG == none`, `.supervisor/config.json` `.multi_voter_heal` (boolean; default false/absent) decides. Resolve and record `MULTI_VOTER_HEAL = true` iff (`MULTI_VOTER_FLAG == enable`) OR (`MULTI_VOTER_FLAG == none` AND config `.multi_voter_heal == true`); otherwise `MULTI_VOTER_HEAL = false`. Consumed by the Supervisor's Phase 4.5 review-and-fix loop's **Multi-voter verification** step (`skills/self-heal-advisory/SKILL.md` Part 2 §"Multi-voter verification") — an OPT-IN, DEFAULT-OFF second independent reviewer (a `red-team-reviewer` verification vote alongside the gating `code-reviewer`) plus a second-opinion refute check that decides WHICH BLOCKING/HIGH `new` findings get fixed. It NEVER changes heal_decision semantics, `--heal-iterations` bounds, never-merge, or the completion tail. Distinct from and independent of the standalone `--red-team` advisory lens (step 2.7) — the flags do not alias each other; the interaction authority is that skill section.
   3. **W-NEW-14 mitigation — clear any stale `base_mismatch_detected` flag from a crashed prior session before this session can act on it:**
      ```
      Context-Keeper(operation: clear_flag, key: "base_mismatch_detected")
      ```
   4. **W-NEW-15 mitigation — autonomous-loop's session-scoped `non_interactive` flag is consumed read-once at every Phase 0; standalone `/supervisor` must treat the terminal as interactive:**
      ```
      Context-Keeper(operation: clear_flag, key: "non_interactive")
      ```
   5. **If `NON_INTERACTIVE == true`, re-arm the flag for this session** (so the Supervisor's Phase 4 FINALIZE / Phase 4.5 can re-read it after a context-summarization round-trip — W-NEW-10 LLM-recall residual mitigation):
      ```
      Context-Keeper(operation: set_flag, key: "non_interactive",
                     value: {set_at: "<ISO 8601>", source: "supervisor_flag"})
      ```
      When `NON_INTERACTIVE == false` the flag stays cleared.
   6. **Echo the resolved values prominently** (placed AFTER environment detection, BEFORE the Status output, so later phases can re-derive these values via LLM recall even if scratchpad state is summarized away):
      ```markdown
      ### Session Configuration (echoed for cross-phase recall)
      - **BASE_BRANCH:** {BASE_BRANCH value or "main"}
      - **NON_INTERACTIVE:** {true or false}
      - **RED_TEAM_ENABLED:** {true or false}
      ```

   > **Other INIT-parsed flags:** the loop-shaping flags `--skip-self-heal` and `--heal-iterations N` (default 3) are also parsed here at INIT and recorded in session memory — they are consumed by the Supervisor's Phase 4.5 SELF_HEAL (the `skip_self_heal_requested` invariant is "set once from INIT-parsed flags, never mutated").

6. Check for job file:
   - If `job:` parameter provided: read brief from path
   - If no `job:` but `.supervisor/jobs/pending/` has files < 24h old: ask user if they want to use one
   - If job file loaded:
     - Move brief from `pending/` → `in-progress/` (if brief is in `pending/`; skip move if path doesn't match `pending/` for backward compatibility with old flat `jobs/` layout)
     - Skip environment validation (already done by Launch Pad)
     - Pre-populate: task details, acceptance criteria, subtask hints, parallelism analysis, skill references
     - Jump to the Supervisor's Phase 1 with enriched context — planning phases are pre-answered by the brief, freeing budget for Phase 3 execution

**Output:**
```markdown
## SUPERVISOR v4: Starting Parallel Workflow

## ENVIRONMENT
- **Path:** {project_path}
- **CLAUDE.md:** ✓ Found | ✗ Missing
- **Git:** clean | dirty ({N} files)
- **Branch:** {current_branch}
- **Worktrees:** {count} existing
- **Config:** workers={N}, mode={parallel|sequential}
```

**Supervisor context after INIT:** ~200 tokens (config only)
