# Supervisor Job: Agent lifecycle ledger — waiting/heartbeat/failed + result-presence + doc-derived stalled/ended_without_result

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (4 non-main `git worktree` entries observed — `pr227-fix` plus 3 detached-HEAD review-drain worktrees from other concurrent plugin activity in this repo; none collide with this brief's own worktree naming, acknowledged and not a blocker)
- **Source requirement:** .supervisor/requirements/orca-derived/01-agent-lifecycle-ledger.md

## Task
**Goal:** Give every spawned agent a lifecycle row (`waiting` / heartbeat `working` / `failed`) in the session JSONL, derive `stalled`/`ended_without_result` at read time, and record whether a stop event actually carried a result block — so the log alone can answer "is this agent waiting on a human, has it gone quiet, or did it end without a result."

**Problem Statement:**
The plugin's hooks record what an agent PRODUCED (a `WORKER_RESULT`/`token_ledger` line on SubagentStop) but never what state it is IN. Three real incidents share this root cause: (a) a worker that dies before emitting `WORKER_RESULT` leaves the deterministic gate with no input and nothing flags it; (b) an until-mergeable drain marker `true` means dispatched, not completed; (c) most spawned agents hit the turn limit before their result block and nobody notices until the Supervisor times out. Currently the plugin records `spawned` (`agent_identity`, `PostToolUse[Task]`) and an END event on `SubagentStop` (`subtask_complete` for workers, `token_ledger` for every other role), but silently DISCARDS the `waiting` state (`Notification`/`PreToolUse[AskUserQuestion]` only toast) and has no `working` heartbeat or derived `stalled` state. Success looks like: a reader (`build-floor.sh`, `build-state.sh`) can answer all three questions from the JSONL log alone, without polling any process table.

## Acceptance Criteria
- [ ] Given an `AskUserQuestion` call inside a spawned worker, when the hook fires, then exactly one `agent_lifecycle:waiting` line is appended to the SAME session JSONL as that worker's `agent_identity` line, carrying that worker's `agent_id` (present per the documented PreToolUse subagent-field rule — see `## Risk Assessment`).
- [ ] Given a fixture worker `SubagentStop` payload whose `last_assistant_message` has no `WORKER_RESULT` fence, when `emit-progress-event.sh` runs, then it emits `subtask_complete` with `result_block_present: false`, and a reader can derive `ended_without_result` from the log alone; given a payload with no `last_assistant_message` key at all, then the `result_block_present` key is OMITTED entirely and the reader derives `unknown` (never either terminal state). Mutation control: delete the derivation logic and the fixture must read as clean (the paired test must then fail).
- [ ] Given a real or fixture `StopFailure` payload, when the hook fires, then `agent_lifecycle:failed` is appended with `reason` equal to the payload's top-level `error` string verbatim (e.g. `server_error`, `rate_limit`, `authentication_failed`, `model_not_found`); given a payload with no `error` key, then `reason: unknown` (the payload's own vocabulary, never a parsed/derived message). The raw `.supervisor/logs/failures.log` append (`STOP_FAILURE $(cat)`) stays byte-identical — this is an ADDITIONAL emitter on the same hook, not a replacement.
- [ ] Given a 200-tool-call fixture run for one `agent_id`, when the heartbeat emitter runs on every `PostToolUse` firing, then the resulting heartbeat line count is bounded to at most `duration / debounce_seconds` — never one line per tool call — using a debounce key derived per-`agent_id` (not per-matcher-block), so an untyped payload hitting more than one registered `PostToolUse` matcher in the same tool call still yields one line, not N.
- [ ] Given the existing `Notification` hook and `notify-desktop.sh`, when the new `waiting` emitter is added alongside it, then `notify-desktop.sh` still receives byte-identical stdin (it reads STDIN directly) and still fires the OS toast — the new emitter must `tee`/re-read, never consume the payload before `notify-desktop.sh` does.
- [ ] Given the new emitters on every documented failure path (empty stdin, malformed JSON, missing `jq`/`python3`, unresolvable session id, not-a-git-repo, unwritable log dir), when any of those conditions hold, then every new emitter exits 0 and writes nothing — same fail-safe contract as `emit-progress-event.sh`/`emit-agent-identity.sh`.
- [ ] Given a new `agent_lifecycle` JSONL record (states `waiting`/`working`/`failed`), when `RESULT_SCHEMAS.md` is checked by `check-doc-currency.sh`, then the new schema section exists with frozen example values (per that script's documented convention) and the doc-currency gate stays green.
- [ ] Given `stalled` and `ended_without_result`, when any reader derives them, then BOTH are computed at READ time by `build-floor.sh`/`build-state.sh` and NEVER written to the log directly — no new writer emits either state name.

## Outcomes Rubric
- Payload shapes probed and recorded before any emitter was written (`## §0 Probe Results` section appended to the source requirement file, dated 2026-09-17, before this brief's implementation)
- `waiting` is recorded from every seam the probe confirmed fires (`PreToolUse[AskUserQuestion]` — documented `agent_id` presence for subagents; `Notification` — implemented the same way but flagged unverified per the probe note), carrying the derived `agent_id` when present
- `result_block_present` is recorded on `subtask_complete`; its absence (no `last_assistant_message` key) stays `unknown`, never a guessed boolean
- The heartbeat emitter is bounded and debounced per derived `agent_id`, never per matcher block
- `stalled` and `ended_without_result` are reader-derived only — no new writer path for either name
- `RESULT_SCHEMAS.md` gets the new `agent_lifecycle` schema section and `check-doc-currency.sh` stays green; no existing gate, `heal_decision`, or `state.md` writer is touched

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Agent lifecycle ledger (waiting/heartbeat/failed + result-presence flag + schema doc) | all | 3 modify, 2 create | `skills/state-management/SKILL.md`, `skills/quality-checklist/SKILL.md` | LAUNCHABLE |

**Split reason:** none — single subtask (Decomposition Threshold default). The five scope items (§0 probe already resolved by Launch Pad, §1 waiting, §2 heartbeat, §3 failed, §3b result_block_present, §4 derivation, §5 schema) are one cohesive, inherently-sequential change to the plugin's hook-emitter layer, sharing one new helper script and one hooks.json edit set — no genuine parallelism (file-conflict: all touch `hooks.json`; below the context-bound and genuine-parallelism thresholds).

### Provides / Requires Schema

```yaml
# Subtask 1 — Agent lifecycle ledger (LAUNCHABLE)
provides:
  - {kind: "file", path: "loomwright/scripts/emit-lifecycle.sh"}
  - {kind: "symbol", path: "loomwright/scripts/emit-lifecycle.sh", name: "waiting"}
  - {kind: "symbol", path: "loomwright/scripts/emit-lifecycle.sh", name: "heartbeat"}
  - {kind: "symbol", path: "loomwright/scripts/emit-lifecycle.sh", name: "failed"}
  - {kind: "file", path: "loomwright/scripts/test-emit-lifecycle.sh"}
  - {kind: "symbol", path: "loomwright/scripts/emit-progress-event.sh", name: "result_block_present"}
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "agent_lifecycle"}
requires: []
lanes:
  - "loomwright/hooks/hooks.json"
  - "loomwright/scripts/emit-lifecycle.sh"
  - "loomwright/scripts/test-emit-lifecycle.sh"
  - "loomwright/scripts/emit-progress-event.sh"
  - "loomwright/scripts/test-progress-state.sh"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/docs/HOOKS.md"
  - ".claude-plugin/README.md"
external_requires: []
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/state-management/SKILL.md` (`.supervisor/` log conventions, atomic/append-only writes), `skills/quality-checklist/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| `Notification` payload's exact field name for the permission/idle subtype (and whether `agent_id` is present on it for a subagent) is UNDOCUMENTED and was not empirically confirmed in this session (see the source requirement's `## §0 Probe Results`) | MEDIUM | Read the reason defensively from whichever candidate field is actually present (never invent); omit `agent_scope` when `agent_id` is absent — same never-guess discipline `emit-progress-event.sh` already uses. Acceptance criteria explicitly tolerate "keeps only the `PreToolUse` seam" as a valid outcome. |
| Adding a second `command` entry to the `Notification` hook block risks accidentally starving `notify-desktop.sh`'s stdin (it reads STDIN directly per its own header comment and memory `runfile-write-accepts-empty-stdin`) | HIGH if regressed | New emitter must `tee` the payload to both the OS-toast script and the log, or read via a `payload=$(cat)` capture-and-refan pattern identical to the existing `SubagentStop` telemetry fan-out blocks in `hooks.json` (see the `code-reviewer` matcher's `payload=$(cat); printf '%s' "$payload" \| ...` pattern) — never a bare second `cat`-consuming command. |
| Heartbeat emitter fires on 3+ existing `PostToolUse` matchers (Bash / Write\|Edit / Task) for a single tool call whose payload is untyped, risking duplicate lines per call | MEDIUM | Debounce key must be the DERIVED `agent_id` (or main-thread marker), written to one shared per-id debounce file (`.notify-debounce`-style), never a per-matcher-block key — acceptance criteria's 200-tool-call fixture is the mechanized guard. |
| `check-doc-currency.sh` treats illustrative example values in the new `agent_lifecycle` schema section as live claims unless frozen per its documented convention | LOW | Follow the exact frozen-example convention already used for `session_end`/`POSTMORTEM_RESULT` blocks in `RESULT_SCHEMAS.md` (see that file's own header note) — do not invent a new convention. |
| New `hooks.json` command entries change the mechanical hook count `check-doc-currency.sh` computes via `[.hooks[][].hooks[]] | length`, cross-checked against `.claude-plugin/README.md`'s `"N quality gate hooks"` comment (currently 36) — that file was absent from this brief's file scope | MEDIUM (Plan Review finding) | After finalizing the `hooks.json` diff, run `scripts/check-doc-currency.sh` locally and bump `.claude-plugin/README.md`'s hook-count comment to match before opening the PR. Added to `lanes:` below for visibility (doc-only bump, no `provides` entry needed). |
| Feasibility (Phase 2.5) — Scope vs Supervisor Capability | LOW | Single-subtask, one new script + edits to 2 existing scripts + 1 hooks.json + 1 doc file; well within Single-Agent Path capacity (~5 files). |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-17-agent-lifecycle-ledger.md
```

## Outcome
- **Heal loop ran:** true
- **Heal iterations:** 3 internal review rounds (all FAIL->fix->re-review) + 2 external claude-review-bot-driven fix rounds (a full-test-loop-only hook-count regression, then a real `.supervisor/` auto-creation footprint bug found by the GitHub bot across rounds 1-4 and fixed in round 5)
- **Heal decision:** PASS (final internal review + final external claude-review: no findings)
- **Rubric score:** 4/6 as machine-graded (2 false negatives — grader's isolated worktree lacked the gitignored probe-results file and did not itself run check-doc-currency.sh; both independently verified true by 3 separate code-reviewer passes and the plan-reviewer)
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/231
- **Merge commit:** fc884278293173e8979ce2dbaa36b6a2e9da0cfb (merge commit, --admin — required 1 approving review, no human reviewer available; standing order)
- **Version:** 15.78.0 -> 15.79.0
