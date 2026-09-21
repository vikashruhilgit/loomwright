# Supervisor Job: One writer for progress state, derived state.md (Fix 3 / D5)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — modified 2026-07-28)
- **Git:** clean (0 files), branch: main @ 7dcb671
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/final-state/02-fix3-one-writer-derived-state.md

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash + jq + python3 emitter appending JSONL, wired via `hooks.json` — the proven `emit-token-ledger.sh` shape (785 `token_ledger` lines in this repo's own logs). No new runtime. git 2.50.1 present. |
| 2 | Dependency Availability | GO | No new dependencies. Both declared `corpus-task:` ids exist with a `check.sh` (verified on disk). |
| 3 | Architecture Fit | CAUTION | The v15.4.0 move of the Supervisor phase bodies into `skills/` scattered the call sites across **9** files, not the requirement's 4. The delete-set is re-scoped accordingly, and a **sixth** mechanism (the terminal `- status:` flip) surfaced that the requirement does not name — see "Scope deviations". |
| 4 | Scope vs Supervisor Capability | CAUTION | 27 files across scripts / hooks / 9 prompt surfaces / contract docs / release surface. Exceeds the `context-bound` bound (> 12 files) → split justified, recorded as `Split reason: context-bound`. |
| 5 | Hard Blockers | CAUTION | The live post-change adherence re-measurement is **not producible inside this PR** — the installed plugin is a *copy*, not a symlink (Risk R3). AC-8 is scoped to what is provable in-PR, and the rubric is knowingly expected to score 3/4 (see "Expected rubric score"). |

**Overall Verdict:** CAUTION (proceed — every CAUTION is carried into an explicit acceptance criterion or Risk row)

### Scope deviations from the source requirement (deliberate, justified — do NOT "fix" back)

**(a) `record_decision` is RETAINED.** The requirement names `checkpoint`/`record_decision` as one mechanism to delete. `record_decision` appends to the `## Decisions Log`, a *different concern* from progress state: it is not part of the measured miss-rate evidence (785-vs-6 is about `phase_transition`), and it has **42 live call sites** — `skills/self-heal-advisory/SKILL.md` (22), `skills/state-management/SKILL.md` (8), `skills/preflight-sync/SKILL.md` (5), `agents/supervisor.md` (4), `skills/async-orchestration/SKILL.md` (1), `skills/supervisor-config/SKILL.md` (1), `agents/context-keeper.md` (1). Deleting it would leave the Phase 1.5 PRE-FLIGHT SYNC fail-closed gate and the whole Phase 4.5 completion tail calling a nonexistent operation, and would contradict AC-3 (which requires the projector preserve `## Decisions Log`) by removing its sole writer. `checkpoint` IS deleted — it copies `state.md`, exactly the mechanism being replaced.

**(b) A SIXTH mechanism exists and is in scope.** `skills/self-heal-advisory/SKILL.md:944–946` mandates the terminal `- status:` flip (`running` → `completed`/`completed_with_escalation`) on both the parallel path (via `update_phase`) and the inline path (via a direct best-effort write). The requirement names neither. It must go with the rest, and the terminal status becomes a projector derivation — see Risk R4 for the honest residual, which is **not** fully closable in this scope.

**(c) `record_batch` has TWO callers, not one.** `agents/execute-manager.md` *and* `skills/async-orchestration/SKILL.md:274`. It is retired with both.

### Expected rubric score: 3/4 (not a defect)

The `## Outcomes Rubric` below is copied **verbatim** from the source requirement and deliberately not reworded. Bullet 4 ("Adherence measurement re-run and recorded") is **knowingly unachievable in this PR** per Risk R3 — the installed plugin is a copy, so edited hooks do not fire until reinstall, and AC-8 explicitly forbids claiming a live count the run could not have produced. The Phase 4.5 Rubric Grader will therefore score **3/4**. That is the honest outcome, not a regression: the grader is advisory-only (it never changes `heal_decision` and never blocks the PR), and this run is single-iteration in `/automate` **safe mode**, so nothing gates on the score. Do not reword the rubric to manufacture a 4/4.

## Task
**Goal:** Replace the prompt-instructed progress-state bookkeeping mechanisms with a single hook-triggered event writer, and demote `.supervisor/state.md` to a view projected from an append-only event log.

**Problem Statement:**
The Supervisor stack needs progress state it can trust because `--continue` re-executes from it.
Currently, progress is recorded by prompt-instructed mechanisms the model must remember while doing the real work. This repo's own logs measure the miss rate: **785 hook-written `token_ledger` events vs 6 agent-written `phase_transition` events across 11+ sessions** — a single session should emit 5–6 `phase_transition` events on its own. On 2026-07-27 all 5 subtasks were merged while `state.md` read `phase: ACQUIRE` / all `PENDING`; `--continue` would have re-executed the whole job. The read-side guard shipped (`scripts/reconcile-resume-state.sh`, v15.15.0) — it **detects** the lie but does not stop it being written, and does not recover the ~200 lines of bookkeeping prose billed on every spawn.
Success looks like exactly one code path writing progress events, that path being hook-triggered, and `state.md` reproducible from the log alone.

**Why deleting (not deprecating) is the point:** a surviving instruction re-introduces the miss rate — the explicit anti-pattern from the resume-state incident. **Do not patch any gap found during implementation by adding another "write your state" instruction.** If a gap cannot be closed mechanically, record it as a residual and escalate; do not re-add prose.

### The delete-set

1. Context-Keeper `set_task`
2. Context-Keeper `set_subtasks`
3. Context-Keeper `update_phase` **and** `checkpoint` (one mechanism — `update_phase` transitions the phase *and* checkpoints)
4. Execute Manager `queue_ck_update` / `flush_ck_batch` — **and `record_batch`, retired with its two callers**
5. The Supervisor's inline best-effort `## Session` write (all **three** mirrored sides — see Subtask 2) + the progress-event half of the Session Logging catalog
6. The terminal `- status:` flip prose at `skills/self-heal-advisory/SKILL.md:944–946` (deviation (b))

### The retain-set (deleting any of these is a regression, not a cleanup)

| Retained | Why |
|---|---|
| `record_decision` | Decisions Log, not progress state; 42 call sites; AC-3 requires the section be preserved |
| `record_self_heal_resume` (`agents/context-keeper.md:50`) | Feeds the Phase 4.5 thrash check; the supervisor `SubagentStop` hook validates the `self_heal_resume_thrash` escalation that depends on it. Its unconditional reset at `self-heal-advisory/SKILL.md:942` stays. |
| `initialize`, `record_worker_result`, `record_review`, `record_error`, `query` | Not progress-state writers; unaffected |
| `## Phase Flag Operations` (`set_flag`/`get_flag`/`clear_flag`) | Consumed by `autonomous-loop` for stacked-branch handoff |
| `session_end` + its FLAT field spec (`skills/state-management/SKILL.md:381`, `:384`) | Hard contract with `build-insights.sh` (ST4); `/insights` breaks without it. Also the projector's only evidence for terminal status. |
| §"Resume Protocol" + §"Resume validation gate" | Read-side only; untouched |
| `scripts/reconcile-resume-state.sh` | Backstop for state written by older plugin versions, and the net under Risk R4's residual |

## Acceptance Criteria

- [ ] **AC-1 (one writer, and it is a hook).** Given a `loomwright:worker` subagent completes, when its `SubagentStop` hook fires, then exactly ONE `subtask_complete` JSONL event is appended to the session log, and the emitter exits 0 on **every** failure path (empty stdin, unresolvable session id, missing `python3`/`jq`, unwritable log dir, malformed payload, not-a-git-repo).
- [ ] **AC-2 (payload shape verified empirically, not assumed).** Given the real `SubagentStop` payload carries `last_assistant_message` + `agent_transcript_path` and **not** `result_block`, when the emitter parses stdin, then it reads only fields actually present — proven by a committed fixture, not by an invented `result_block` key.
- [ ] **AC-3 (state.md is derived and reproducible).** Given an event log, when `scripts/build-state.sh` runs, then it projects the canonical **lowercase** `## Session` block into `.supervisor/state.md`; and deleting `state.md` and re-projecting from the same log yields a byte-identical `## Session` block. The projector performs a **targeted in-place edit of `## Session` only**, preserving `## Decisions Log`, `## Phase Flags`, and `## Checkpoint`, via temp-file + rename.
- [ ] **AC-4 (resume gate still passes).** Given a projected `state.md`, when `/supervisor --continue` runs its Phase 0 resume validation gate, then `phase` and `status` are within their closed enums and any asserted `branch:` resolves — i.e. a projected file PASSES. `scripts/reconcile-resume-state.sh` is **unchanged** and still passes its full self-test suite.
- [ ] **AC-5 (hook-dispatch gate still authorizes — the second consumer).** Given a projected `state.md` during Phase 3 on **both** the Single-Agent Path and the Parallel Path, when `scripts/hook-dispatch-on-pr-create.sh` evaluates Source 1, then `- status:` is **present and non-terminal** and `- branch:` **equals the session feature branch** (not a subtask branch, not empty), so the until-mergeable drain still dispatches on a plain `/supervisor` run that has no autonomous `state.json` for Source 2.
- [ ] **AC-6 (session-id join key does not fragment — both emitters).** Given the ACQUIRE `state.md` write is gone, when the first `subtask_complete` event resolves a session id, then the projector **adopts that id** into the projected `- session_id:` line; and `emit-token-ledger.sh` uses the **same main-checkout anchoring**, so a `code-reviewer`/`qa-executor` completion whose cwd is inside a worktree still resolves the same log file. Verified by a harness assertion of **one log file per simulated session, including a worktree-cwd `token_ledger` emission**.
- [ ] **AC-7 (mechanisms deleted, not deprecated — grep must return ZERO).** Given the repo after the change, when
  `grep -rnE "queue_ck_update|flush_ck_batch|update_phase|set_subtasks|set_task|record_batch|operation: checkpoint" loomwright/agents/ loomwright/commands/ loomwright/skills/`
  runs, then it returns **zero** hits. Baseline measured 2026-07-28: **36 hits across exactly the 9 files enumerated in Subtask 2** — re-run this grep as an authoring gate before declaring the subtask done; do not reason from a file list. (`record_decision` is deliberately absent from this pattern — it is retained.)
- [ ] **AC-8 (measured, not asserted — scoped to what is provable in-PR).** Given Risk R3, when the PR is opened, then it records (i) per-agent **before/after proxy-token deltas** for `supervisor`, `execute-manager`, `context-keeper`, measured not estimated; (ii) a green run of `scripts/test-progress-state.sh`; and (iii) a written operator procedure for the live adherence re-measurement after reinstall. It does **not** claim a live post-change event count it could not have produced.
- [ ] **AC-9 (`session_end` and the ST4 contract survive).** Given the deletion sweep touches `skills/state-management/SKILL.md` §"Session Logging", then `session_end` and its FLAT `contract_*` / `benchmark_*` / `ground_truth_*` / `knowledge_sources_used` / `plugin_version` field spec are **retained verbatim**.
- [ ] **AC-10 (counts and version stay green).** Given the hook count moves 22 → 23 and the version 15.15.0 → 15.16.0, when `scripts/check-doc-currency.sh` and `scripts/validate-version.sh` run, then both pass — **and** the claim at `AGENT_GUIDELINES.md:610` ("22 hook entries") is updated even though no CI pattern matches that phrasing.

## Outcomes Rubric
- Hook writer shipped, fail-safe
- state.md derived, resume-compatible
- Five prompt mechanisms deleted, not deprecated
- Adherence measurement re-run and recorded

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Mechanism substrate: emitter + projector + self-test + hook wiring | AC-1, AC-2, AC-3, AC-5, AC-6 | 2 modify, 3 create | `skills/state-management/SKILL.md`, `skills/error-handling/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 2 | Delete the prompt-instructed mechanisms across all 9 files | AC-4, AC-7, AC-9 | 9 modify, 0 create | `skills/state-management/SKILL.md`, `skills/quality-checklist/SKILL.md` | BLOCKED (by #1) |
| 3 | Contract + budget surface: re-measure budgets, document the event | AC-8 (i), AC-8 (iii) | 5 modify, 0 create | `skills/monitoring-observability/SKILL.md` | BLOCKED (by #2) |
| 4 | Release surface: hook count 22→23, version 15.16.0 | AC-10 | 8 modify, 0 create | `skills/quality-checklist/SKILL.md` | BLOCKED (by #3) |

### Subtask 1 — Mechanism substrate (LAUNCHABLE)

**Step 0 — establish the hook's real cwd empirically before relying on it.** Do not assume. `emit-token-ledger.sh:80` uses `${PWD}/.supervisor/logs` and demonstrably works (785 events), which is strong evidence cwd is the main checkout — but prove it, and make the code correct **either way** (below). If evidence contradicts the design, record it and escalate rather than guessing.

Create `loomwright/scripts/emit-progress-event.sh`, modelled **line-for-line in discipline** on `loomwright/scripts/emit-token-ledger.sh` (read it first): `set -u` with **no** `set -e`, `trap 'exit 0' EXIT`, stdin read that no-ops on empty, and the same two-source session-id resolution (prefer `.supervisor/state.md`'s id when its `- status:` is `running`, else the Claude Code `session_id` UUID; always record the CC uuid as additive `cc_session_id`). It appends ONE JSONL line `{"ts":…,"event":"subtask_complete","type":"subtask_complete",…}` and then invokes the projector.

> `emit-token-ledger.sh:94` also accepts `checkpoint` in that status test. `checkpoint` is **not** in the closed status enum (`skills/state-management/SKILL.md:77`) and the projector can never emit it, so the new emitter accepts it **only** for backward compatibility with pre-change `state.md` files — note that in a comment; do not silently inherit it as if it were live.

**Worktree-safe anchoring (load-bearing — this is the R1 fix, empirically verified).** Never use bare `$PWD`, bare `git branch --show-current`, or `dirname` of the git common dir (the latter is wrong under `--separate-git-dir` and for submodules, and fails **silently** because the emitter is exit-0-by-contract). Resolve the **main worktree** by name:

```bash
# First porcelain entry is always the MAIN worktree — correct from inside any
# linked worktree, and unaffected by separate-git-dir / submodule layouts.
main_root="$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
[ -n "$main_root" ] && [ -d "$main_root" ] || exit 0        # fail SAFE, never guess
# Cross-check, abort (exit 0) on mismatch rather than writing to a garbage path:
top="$(git -C "$main_root" rev-parse --path-format=absolute --show-toplevel 2>/dev/null)"
[ "$top" = "$main_root" ] || exit 0
session_branch="$(git -C "$main_root" branch --show-current 2>/dev/null)"
log_dir="$main_root/.supervisor/logs"
```

**Verified 2026-07-28 on git 2.50.1** from inside a real linked worktree: `git worktree list --porcelain | sed -n '1s/^worktree //p'` returned the main checkout, while `git branch --show-current` in that worktree returned **empty** and the worktree had no `.supervisor/` — i.e. the hazard is real and this derivation fixes it. Commit that observation as a harness assertion (Step 0), not as prose.

**The branch must be the session feature branch** — `hook-dispatch-on-pr-create.sh:198` authorizes only when `- branch:` is present and *equals* the current branch, so a subtask branch or an empty value there silently kills the review drain (AC-5).

Modify `loomwright/scripts/emit-token-ledger.sh` — replace its `${PWD}`-anchored `LOG_DIR` (`:80`) and `STATE_MD` (`:87`) with the same anchoring, ideally via a small shared helper sourced by both emitters. **Behaviour must be byte-identical when cwd IS the main checkout**; the change only fixes the worktree case. This closes the other half of the AC-6 join — without it, a `code-reviewer` completing with worktree cwd falls back to the CC uuid and writes to a different log file than the projector adopted.

Create `loomwright/scripts/build-state.sh` — the projector. Reads the append-only log, derives the `## Session` block, writes it with temp-file + rename. **Derivation is evidence-only — a projector that guesses is the same lie in a new place:**

| Field | Derived from | Absent-evidence behavior |
|---|---|---|
| `session_id` | the id the FIRST event resolved (AC-6) | file not written |
| `branch` | `session_branch` above | field omitted |
| `status` | ≥1 event and no `session_end` ⇒ `running`; `session_end` present ⇒ its status mapped into `completed \| completed_with_escalation \| failed` | file not written |
| `phase` | `subtask_complete` present ⇒ `EXECUTE`; `session_end` present ⇒ `LOOP` | file not written |

**`status` is never omitted when the file exists** — an absent `- status:` trips the `[ -n "$s1_status" ]` presence guard at `hook-dispatch-on-pr-create.sh:198` and fails closed. Both `status` and `phase` MUST land inside the closed enums at `skills/state-management/SKILL.md:76–77` (verified: `EXECUTE`/`LOOP` and `running`/`completed`/`completed_with_escalation`/`failed` all qualify). An empty/absent log means **no `state.md` at all** — start-fresh, strictly better than today's lie.

Create `loomwright/scripts/test-progress-state.sh` — fixture-driven self-test covering: one-event-per-invocation; idempotency on repeated identical payloads; exit 0 on empty stdin / missing `jq` / missing `python3` / unwritable log dir / malformed JSON / not-a-git-repo / mismatched cross-check; **the main-checkout derivation asserted from inside a real `git worktree add`** (Step 0's observation); a Parallel-Path case (emitter invoked with cwd inside a worktree on a subtask branch ⇒ event lands in the main checkout's log carrying the *session* branch); a **worktree-cwd `token_ledger` emission** landing in the same log file (AC-6); projector round-trip byte-identity; projector preserves `## Decisions Log` / `## Phase Flags` / `## Checkpoint`; projected `state.md` satisfies `hook-dispatch-on-pr-create.sh` Source 1 (AC-5).

Modify `loomwright/hooks/hooks.json` — add exactly ONE `type: command` entry under the **existing** `loomwright:worker` `SubagentStop` matcher (which today has only a `prompt` entry), following the established `payload=$(cat); printf '%s' "$payload" | bash …` fan-out shape and carrying `|| true` per the v15.5.0 convention — legal **only** because the emitter is an always-exit-0 fail-safe emitter (CLAUDE.md §Failure-Mode Invariants). Hook entry count 22 → 23.

```yaml
provides:
  - {kind: "file", path: "loomwright/scripts/emit-progress-event.sh"}
  - {kind: "file", path: "loomwright/scripts/build-state.sh"}
  - {kind: "file", path: "loomwright/scripts/test-progress-state.sh"}
  - {kind: "symbol", path: "loomwright/hooks/hooks.json", name: "emit-progress-event.sh"}
  - {kind: "symbol", path: "loomwright/scripts/emit-token-ledger.sh", name: "main_root"}
requires: []
external_requires:
  - "jq"
  - "python3"
  - "git >= 2.31 (--path-format)"
```

### Subtask 2 — Delete the prompt-instructed mechanisms (BLOCKED by #1)

Delete, do not deprecate. Replacement text is a **one-line pointer to the hook mechanism** — never a replacement instruction. Line numbers are hints that drift; **anchor on the quoted name**. The 9 files below are the complete AC-7 hit set measured 2026-07-28 (36 hits); re-run the AC-7 grep as the exit gate.

| File | Hits | Sites (anchor on the name) |
|---|---|---|
| `loomwright/agents/execute-manager.md` | 10 | `queue_ck_update` / `flush_ck_batch` (:252–:319) and §"Batched Context-Keeper Updates" (:434–:452) |
| `loomwright/agents/context-keeper.md` | 7 | `set_task` (:44), `set_subtasks` (:45), `update_phase` (:51), `checkpoint` (:52), `record_batch` (:54) rows + their Operation Details bodies, and the `"Valid: initialize, set_task, ..."` error string (:200). **Retain** `initialize`, `record_worker_result`, `record_review`, `record_decision`, `record_error`, `record_self_heal_resume`, `query`, and all of `## Phase Flag Operations`. |
| `loomwright/agents/supervisor.md` | 6 | ACQUIRE `Context-Keeper(set_task / update_phase)` + its direct-write rationale (:166, :167, :169); PLAN `set_subtasks` / `update_phase` (:213, :214); **and `Context-Keeper(operation: checkpoint, ...)` in the Option-C adjudication bullet (:333)**. At :333 delete **only** the `checkpoint` call — the rest of option C (mark job `failed` with `reason: inter_subtask_gap`, move brief to `failed/`, exit cleanly) is unchanged, and needs no replacement because the projector regenerates `state.md` from the log. **Leave the `record_decision` sites at :191, :334, :396, :524 alone.** |
| `loomwright/skills/state-management/SKILL.md` | 5 | §"Writing State (Mutations)" operations table + §"Inline-path write responsibility" (:249–:286); Session Logging progress half — **`:371–:380` and `:386–:395` only**, explicitly excluding `:381` (the `session_end` example) and `:384` (the FLAT field spec), which AC-9 requires verbatim |
| `loomwright/skills/self-heal-advisory/SKILL.md` | 4 | `update_phase` at `:529` (`new_phase: SELF_HEAL`), `:564` (`new_phase: LOOP`), `:944` (`new_phase: LOOP`), **and `:945`**. At :944 remove **only** the `update_phase` clause — the `record_decision(...)` in the same line is retained. **`:945`–`:946` is deviation (b)'s sixth mechanism** — the "Canonical on-disk flip MUST happen" bullet mandating the terminal `- status:` flip via `update_phase` (parallel path) or a direct best-effort write (inline path). Delete both bullets; the terminal status becomes the projector's `session_end` derivation (Subtask 1's table). Keep the `record_self_heal_resume` reset at `:942`. |
| `loomwright/skills/workflow-management/SKILL.md` | 1 | §"Checkpoint Format (v4)" (:103–:109), whose body is `Context-Keeper(operation: checkpoint, ...)` at `:108`. This is the canonical documentation of the deleted mechanism, in a **Supervisor-preloaded** skill. |
| `loomwright/skills/context-summarization/SKILL.md` | 1 | `CK: update_phase — EXECUTE, progress 1/3` at `:164` (an illustrative compression example) |
| `loomwright/skills/async-orchestration/SKILL.md` | 1 | `→ Task(Context-Keeper, operation: record_batch, updates: [...])` at `:274` — `record_batch`'s **second** caller (deviation (c)) |
| `loomwright/commands/supervisor.md` | 1 | §"Inline-path canonical state writes" (:134–:150). **Mirrored pair** — that section's own preamble says to edit both sides in the same change. |

The last four rows are the v15.4.0 fallout: the Supervisor's phase bodies moved into skills, so the call sites are no longer where the requirement's file list expects them.

```yaml
provides:
  - {kind: "symbol", path: "loomwright/skills/state-management/SKILL.md", name: "Session Logging"}
  - {kind: "symbol", path: "loomwright/agents/context-keeper.md", name: "Phase Flag Operations"}
  - {kind: "symbol", path: "loomwright/agents/context-keeper.md", name: "record_self_heal_resume"}
requires:
  - {from: "1", kind: "file", path: "loomwright/scripts/emit-progress-event.sh"}
  - {from: "1", kind: "file", path: "loomwright/scripts/build-state.sh"}
external_requires: []
```

### Subtask 3 — Contract + budget surface (BLOCKED by #2)

Re-measure the three affected agents with the repo's own proxy-token method and lower their budgets in `loomwright/docs/prompt-token-budgets.json` (`supervisor`, `execute-manager`, `context-keeper`), with a `note` recording before → after and the reason. **Measure, do not estimate** — `scripts/check-token-budget.sh` fails CI closed on a drifted or ghost row and mechanically syncs the `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" mirror. Document the new `subtask_complete` event in `loomwright/docs/TELEMETRY.md` alongside `token_ledger`, including the AC-8 (iii) operator re-measurement procedure and Risk R4's residual. Stamp `## Status: done` on `.supervisor/requirements/one-writer-derived-state.md` with a pointer to this brief (its own "fold in, then retire" instruction).

```yaml
provides:
  - {kind: "symbol", path: "loomwright/docs/prompt-token-budgets.json", name: "execute-manager"}
  - {kind: "symbol", path: "loomwright/docs/TELEMETRY.md", name: "subtask_complete"}
requires:
  - {from: "2", kind: "symbol", path: "loomwright/skills/state-management/SKILL.md", name: "Session Logging"}
external_requires: []
```

### Subtask 4 — Release surface (BLOCKED by #3)

Version 15.15.0 → 15.16.0 and hook count 22 → 23 across every **current-claim** site. Verified sites: `loomwright/.claude-plugin/plugin.json:3,4`; `.claude-plugin/marketplace.json:10,11` (headline inside `description`); `.claude-plugin/README.md:9,430,503`; `README.md:9` and its `/ 22 hooks` current-claim lines; `CLAUDE.md:15,17,28,153`; `loomwright/commands/agent-help.md:1084`; **`AGENT_GUIDELINES.md:610`** ("As of v15.5.0 there are **22 hook entries**" plus its hook enumeration). Add the hook row to CLAUDE.md §"Plugin Hooks (Quality Gates)" and a CHANGELOG entry.

**`AGENT_GUIDELINES.md:610` is CI-invisible.** The file IS in `check-doc-currency.sh`'s allowlist (`:42`), but the hook patterns are only `[0-9]+ quality gate hooks` and `[0-9]+ hooks centralized` (`:116–:117`) — neither matches "hook entries". A green doc-currency run will NOT catch it. Per CLAUDE.md, grep the OLD value repo-wide before declaring done.

**Do NOT** update the historical `21 hooks` lines in `README.md` (dated release banners) or any `e.g. "X.Y.Z"` illustrative `plugin_version` placeholder — deliberately frozen and version-agnostic. Keep the `plugin.json` / `marketplace.json` `description` a **summary, not a changelog**: update the version string and counts in place; never append another version clause.

```yaml
provides:
  - {kind: "symbol", path: "loomwright/.claude-plugin/plugin.json", name: "version"}
  - {kind: "symbol", path: "CHANGELOG.md", name: "15.16.0"}
requires:
  - {from: "3", kind: "symbol", path: "loomwright/docs/prompt-token-budgets.json", name: "execute-manager"}
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2 ──→ Subtask 3 ──→ Subtask 4
```

The split is `context-bound` (27 files > 12), **not** parallelism: the four groups form a strict chain — deletions must reference the shipped mechanism; budgets can only be re-measured after the prose is deleted; counts can only be stamped once hook and budgets are final. No zero-overlap parallel pair exists, so `genuine-parallelism` explicitly does **not** apply and workers stay at 1.

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none (but #2 requires #1's contract) | YES (dependency) |
| Subtask 2 | Subtask 3 | none (but #3 measures #2's deletions) | YES (dependency) |
| Subtask 3 | Subtask 4 | none (but #4 stamps #3's final counts) | YES (dependency) |
| Subtask 1 | Subtask 4 | none | YES (transitive) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after 1)
- **Batch 3:** Subtask 3 (after 2)
- **Batch 4:** Subtask 4 (after 3)
- **Recommended workers:** 1
- **Estimated batches:** 4

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/state-management/SKILL.md`, `skills/error-handling/SKILL.md`, `skills/unit-testing/SKILL.md` |
| 2 | `skills/state-management/SKILL.md`, `skills/quality-checklist/SKILL.md` |
| 3 | `skills/monitoring-observability/SKILL.md` |
| 4 | `skills/quality-checklist/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| **R1** — Worktree cwd/branch hazard. A worker's worktree sits on a **subtask** branch (or detached) and has no `.supervisor/`. Bare `git branch --show-current` / `$PWD` would project a wrong-or-empty `- branch:`, which fails the equality guard at `hook-dispatch-on-pr-create.sh:198`; a plain `/supervisor` run has no autonomous `state.json` for Source 2, so the review drain silently never dispatches. | HIGH | Anchor to the **main worktree by name** via `git worktree list --porcelain` + a `--show-toplevel` cross-check that exits 0 on mismatch — **not** `dirname` of the git common dir, which is wrong under `--separate-git-dir`/submodules and fails silently. **Empirically verified 2026-07-28 (git 2.50.1) from inside a real linked worktree**: the derivation returned the main checkout while `git branch --show-current` there returned empty. Step 0 commits that as a harness assertion; AC-5 makes the gate a first-class criterion. Ordering is separately confirmed: Phase 3 EXECUTE precedes Phase 4 `gh pr create` on all paths (`skills/async-orchestration/SKILL.md:723,:725,:751`). |
| **R2** — Over-deletion: `session_end` sits inside the same §"Session Logging" catalog and carries the FLAT fields `build-insights.sh` (ST4) keys on. | HIGH | AC-9 + the retain-set table + a deletion range restated to *exclude* `:381` and `:384`. Source: `skills/state-management/SKILL.md:384`. |
| **R3** — The live post-change adherence re-measurement is **not producible in this PR.** Verified: `~/.claude/plugins/cache/atelier/loomwright/15.15.0` is a *copy*, not a symlink (distinct inodes for `hooks/hooks.json`), refreshed only at install. | MEDIUM | AC-8 is scoped to the three in-PR-provable things and forbids claiming a live count. Drives the deliberate 3/4 rubric outcome documented above. Stated limitation, not a silent gap. |
| **R4** — **Residual, NOT fully closed.** The terminal `- status:` flip (deviation (b)) becomes a projector derivation from `session_end` — but `session_end` is itself agent-written, so it inherits the miss rate this change exists to remove. If it is missed, `state.md` stays `running` after the run ends. | MEDIUM | **Accepted and documented, not papered over.** Degradation is graceful and is the *opposite* of the 2026-07-27 incident shape: a stale `running` over-reports activity rather than hiding merged work. Consequences are benign — `hook-dispatch-on-pr-create.sh` would authorize a redundant drain (idempotent per-PR marker), and `--continue` hits `reconcile-resume-state.sh`, which reports STALE with the true position. **Do NOT close this by re-adding a "flip the status" instruction** (R6). Making the terminal flip mechanical needs a completion-side hook that does not exist on the inline path — a separate design surface. Record it in `docs/TELEMETRY.md` (Subtask 3) as a known residual. |
| **R5** — Mirror drift: the `commands/supervisor.md` ↔ `agents/supervisor.md` ↔ `skills/self-heal-advisory/SKILL.md` trio all state the inline-path write; `check-command-sync.sh` gates only `commands/code-reviewer.md`, so divergence passes every CI gate and only a `consistency_audit` catches it. | MEDIUM | Subtask 2 names all three sides so they land in one commit. Phase 4.5's Code Reviewer auto-expands to `consistency_audit` because the diff touches `agents/`, `commands/`, and `skills/`. |
| **R6** — A worker "fixes" a gap by adding another "write your state" instruction — the explicit anti-pattern from the resume-state incident. | MEDIUM | Called out in the Problem Statement, in Subtask 2's opening line, and in R4. AC-7's grep makes a re-added mechanism name mechanically detectable. |
| **R7** — Deleting `record_decision` (as the source requirement literally says) would break the Phase 1.5 fail-closed gate and the Phase 4.5 completion tail across 42 call sites, and contradict AC-3. | MEDIUM | Scope deviation (a); retain-set table; AC-7's pattern deliberately omits it. |
| **R8** — `AGENT_GUIDELINES.md:610`'s "22 hook entries" is a current claim no `check-doc-currency.sh` pattern matches, so CI stays green while it goes stale. | MEDIUM | Named in Subtask 4's site list and in AC-10; grep the old value repo-wide before declaring done. |
| **R9** — Modifying the proven `emit-token-ledger.sh` (785 successful events) risks regressing a working emitter. | MEDIUM | The change is confined to two path-resolution lines (`:80`, `:87`) and MUST be byte-identical in behaviour when cwd is the main checkout; the shared helper is covered by Subtask 1's self-test, and the emitter's `trap 'exit 0' EXIT` contract is preserved. |
| **R10** — A `type: command` hook carrying `\|\| true` that is NOT always-exit-0 would be silently neutered; a future blocking gate must not carry it. | MEDIUM | The emitter is fail-SAFE by construction, which is what makes `\|\| true` legal (CLAUDE.md §Failure-Mode Invariants). Self-test asserts exit 0 on every failure mode. |
| **R11** — Absolute line numbers in Subtask 2 drift as edits land above them. | LOW | Every citation is paired with a searchable name, and AC-7's grep is the exit gate rather than the line list. |
| **R12** — Feasibility (Phase 2.5): the four command/agent mirrors are not CI-protected. | LOW | Carried from item 01's run; covered by R5. |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 4
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-07-28-one-writer-derived-state.md
```

---

## Outcome
- **Status:** completed
- **Branch:** feature/one-writer-derived-state
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/116
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0 (no BLOCKING/HIGH `new` issues on the integrated diff)
- **Heal remaining issues:** 0 (2 LOW dangling-SHA citations fixed anyway in 336bb90)
- **Rubric score:** 3/4 — item 4 ("Adherence measurement re-run and recorded") FAILs by design: no live post-change count is producible in-PR because the installed plugin is a copy, not a symlink, so edited hooks do not fire until reinstall. Recorded instead: per-agent token deltas, a 90-assertion fixture harness, and an operator re-measurement procedure. Rubric kept verbatim per user decision rather than reworded to manufacture 4/4.
- **Per-subtask reviews:** ST-1 PASS (1 heal iter) · ST-2 PASS (2 heal iters: 1 BLOCKING orphaned call sites, 2 HIGH overclaims) · ST-3 PASS (1 heal iter: 2 HIGH) · ST-4 PASS (2 MEDIUM fixed pre-commit)
- **Commits:** 36c39de, e644d9f, 28be6ca, ac289cf, 336bb90
- **Until-mergeable dispatched:** see reconciliation below (marker-based, not control-flow)
