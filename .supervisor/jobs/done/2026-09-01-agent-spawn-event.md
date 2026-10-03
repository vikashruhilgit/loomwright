# Supervisor Job: Spawn-side `agent_spawn` event (evidence-gated)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — 2026-09-01 17:58)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 2
- **Source requirement:** .supervisor/requirements/loom-floor-ui/01-agent-spawn-event.md

Warnings (non-blocking):
1. Four Claude Code session worktrees exist under `.claude/worktrees/` (`adoring-chatelet-ad5e83`, `busy-darwin-7b336a`, `gifted-cori-7925df`, `zen-ptolemy-90887b`). They are not Loomwright supervisor worktrees and do not block new ones, but `git worktree list` is not the single-entry clean state.
2. PR #168 (`claude/zen-ptolemy-90887b`) is open and unmerged. This work branches off `main` without it; no file overlap was found with this brief's lanes.

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure bash + `jq` emitter in the shape of `loomwright/scripts/emit-progress-event.sh`. No new runtime dependency. |
| 2 | Dependency Availability | GO | `jq`, `python3`, `claude` (2.1.237) all present. `claude --settings <file-or-json>` is a real flag (verified from `claude --help`), which is what makes an out-of-session hook probe possible. |
| 3 | Architecture Fit | GO | `PreToolUse` already exists in `loomwright/hooks/hooks.json` with one matcher entry (`AskUserQuestion`). Matchers are regex-alternation capable (`Notification` uses `a\|b\|c`), so a `Task` matcher is an additive sibling entry, not a new hook event. Verified: zero `"Task"` matchers across all 24 hook command entries. |
| 4 | Scope vs Supervisor Capability | GO | One coherent work group gated on one probe. **The GO branch does cross the `context-bound` FILE arm** (15 files > 12); it stays below the LINES arm (well under 800 — the doc half is one-number count bumps at 5 gate-matched occurrences across 4 files, plus 2 non-gate-matched rolling-current lines). Crossing a bound *permits* a split, it does not mandate one — and a split here would be actively harmful: the whole item is one probe gating one decision, so a second subtask is stranded with nothing to do on NO-GO. Single subtask, therefore no `Split reason:` (required only for >1 subtask). |
| 5 | Hard Blockers | **CAUTION** | The central claim — that `PreToolUse[Task]` fires per subagent spawn carrying an id joinable to `SubagentStop.agent_id` — is **unverified**. The overview states plainly it was drawn from the documented contract, not an observed payload. This is the requirement's own gate: it is settled empirically first, and a NO-GO with committed evidence is a successful outcome. A second, mechanical constraint compounds it: a `loomwright:worker` subagent **cannot spawn Task subagents** (spawn-depth), so the worker cannot trigger the hook from inside itself — see Risk Assessment R1 for the sanctioned mechanism. |

**Overall Verdict:** CAUTION

## Task
**Goal:** Settle empirically whether a `PreToolUse[Task]` payload carries a spawn-side agent id joinable to `SubagentStop.agent_id`, and — only if it does — add a fail-safe `agent_spawn` emitter plus additive honest naming on the stop side.

**Problem Statement:**
Anything that reports "who is working right now" needs a spawn-side event, because every progress event Loomwright writes comes from a `SubagentStop` hook. Currently the log records that an agent *finished* — never that one started, which agent it was, or what it was doing. Verified on this checkout 2026-09-01: `loomwright/hooks/hooks.json` has **zero** `"Task"` matchers across all 24 hook command entries, and the live log `.supervisor/logs/8d43da72-…jsonl` carries 3,641 `subtask_complete` events against 4 real subtasks in `state.md` — the event name asserts something ~900× stronger than what it observes. This causes every liveness question to be answered by guessing from a recent `token_ledger` line, which is the exact failure the one-writer invariant exists to prevent.
Success looks like: a committed, observed spawn payload and a recorded GO/NO-GO verdict — and, on GO, one `agent_spawn` line per spawn whose `agent_id` demonstrably joins to a real `SubagentStop` event from the same run.

## Acceptance Criteria

- [ ] Given a live Claude Code run with a `PreToolUse[Task]` capture hook registered, when at least one subagent is spawned, then the raw stdin JSON is captured to disk and committed under `loomwright/scripts/progress-event-fixtures/` — observed, never synthesized and never derived from documentation.
- [ ] Given the probe has run, when its result is recorded, then `loomwright/docs/SPIKES/AGENT_SPAWN_PAYLOAD_PROBE.md` exists carrying a `## Verdict` section stating **GO** or **NO-GO**, the exact command used, the raw payload (or the measured evidence that none fired), and the joinability measurement against a real `SubagentStop` `agent_id`.
- [ ] Given a NO-GO verdict, when the item closes, then the emitter, the hooks.json entry and the doc-surface count bumps are **NOT** made, the probe record states the measured reason, and the run reports NO-GO as a pass — the remaining criteria below are recorded as `not-applicable (NO-GO)` rather than failed.
- [ ] Given a GO verdict, when `emit-agent-spawn.sh` runs on the committed fixture, then exactly one JSONL line with `"event":"agent_spawn"` is appended carrying at minimum `agent_id`, `agent_type`, `branch`, `ts`, plus `subtask`/`description` when the payload offers them.
- [ ] Given a GO verdict, when the spawn↔stop join is demonstrated, then it is shown against **two real events** from a real run (one `agent_spawn`, one `SubagentStop`), not asserted in prose.
- [ ] Given a malformed payload, an empty payload, and a non-JSON payload, when each is fed to the emitter **as its own separate test case**, then nothing is written and the exit status is 0 in all three.
- [ ] Given invocation from inside a real detached linked worktree with no `.supervisor/` (created by an actual `git worktree add`, not a simulated cwd), when the emitter runs, then it resolves the main checkout or writes nothing — and never falls back to `$PWD`.
- [ ] Given a GO verdict, when `emit-progress-event.sh` runs, then `subagent_stop` is emitted **and** `subtask_complete` is still emitted, and `agent_type` is added additively on the stop side.
- [ ] Given the existing session-log corpus, when `build-state.sh` and `build-insights.sh` are run before and after the change, then their generated output files are **byte-identical** — proven by diffing the real generated files, not by reading the code.
- [ ] Given a GO verdict, when the hook is added, then the hook count moves 24 → 25 on **every surface that actually restates it**, in the same commit, and `bash scripts/check-doc-currency.sh` exits 0. **Derive that surface set mechanically — do not trust any hand-written list, including this one.** The gate matches exactly two patterns (`scripts/check-doc-currency.sh` §"Hook count") over its own `FILES` allowlist; run both, plus a repo-wide grep for the OLD value, and bump what they find:
      ```bash
      # NOTE: the gate pipes each file through `tr -d '*'` BEFORE matching (check-doc-currency.sh:96),
      # so a bolded variant like `**24** quality gate hooks` is caught by the gate but missed by a raw
      # grep. Normalize the same way or the two disagree.
      for f in <the FILES allowlist>; do tr -d '*' < "$f" | grep -nE '[0-9]+ quality gate hooks|[0-9]+ hooks centralized' | sed "s|^|$f:|"; done
      grep -rnE '\b24\b[^.]{0,40}hooks?|hooks?[^.]{0,40}\b24\b' README.md CLAUDE.md AGENT_GUIDELINES.md .claude-plugin/ loomwright/.claude-plugin/ loomwright/docs/
      ```
      As measured on this checkout 2026-09-01 the gate-matched set is five occurrences in four files (`README.md:63`, `.claude-plugin/README.md:441` and `:503`, `.claude-plugin/marketplace.json:10`, `loomwright/.claude-plugin/plugin.json:4`) — recorded as a starting point to re-derive, never as the list to copy.
- [ ] Given a GO verdict, when the doc surface is updated, then **two files that carry no hook total do not gain one**: `loomwright/docs/HOOKS.md` gains a new **row** in its Hook Table only — its line 10 states verbatim that it "deliberately does not restate the totals" (`AGENT_GUIDELINES.md` §"Claim Duplication Rule") — and `CLAUDE.md` gains only its normal latest-change banner, which per its own header rule is written **without** version numbers or counts. Genuinely frozen dated release banners are NOT retro-edited; the new count belongs in the new release's own banner and in `CHANGELOG.md`.
- [ ] Given a hit from AC #10's second grep that is **not** gate-matched, when deciding whether to bump it, then the decision is made by **whether the line's counts track the present release — never by whether its framing is dated**. A line introduced as "NEW in vX" but carrying today's numbers has been maintained forward and MUST bump; a line whose numbers still match the release it names is frozen and must not. These are the surfaces `check-doc-currency.sh` passes over while stale, and the repo already keeps a register of them: `.claude/agent-memory/loomwright-loomwright-code-reviewer/project_half_fixed_example_classes.md` §5 "Kept-current count surfaces NOT scanned by doc-currency CI" — read it, and add any newly-found instance to it. Two measured instances on this checkout 2026-09-01, both rolling-current and both invisible to the gate: `.claude-plugin/README.md:9` (framed "v14, stacked PRs" but reading `21 slash commands, 41 skills, 24 hooks` — today's values; the v14 era was 17 commands / 19 hooks) and `loomwright/docs/ARCHITECTURE_CONTRACTS.md:195` (`the default (21 of 24)`, which a new **command** hook takes to `22 of 25`). By contrast `README.md:9-21` are genuine frozen per-release banners — their counts step 24 → 22 → 21 → 19 and the v15.16.0 entry reads `24 hooks (22 → 24)` — and are correctly left alone.
- [ ] Given every new test case, when the mechanism it covers is reverted, then exactly that case fails and no other — each mutation control run and its result recorded.

## Outcomes Rubric

- The spawn payload is known from evidence on disk, not from reasoning.
- Spawn↔stop pairing is demonstrated on real events from a real run.
- The emitter is indistinguishable in discipline from `emit-progress-event.sh`.
- Existing consumers are provably unaffected.
- A NO-GO, if it happens, is reported as clearly as a GO.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Probe the `PreToolUse[Task]` payload, then GO/NO-GO on the `agent_spawn` emitter | all | **NO-GO branch:** 1 modify, 3 create · **GO branch:** 10 modify, 5 create | `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` | LAUNCHABLE |

```yaml
# Subtask 1 — evidence-gated spawn event (LAUNCHABLE)
provides:
  - {kind: "file", path: "loomwright/docs/SPIKES/AGENT_SPAWN_PAYLOAD_PROBE.md"}
  - {kind: "symbol", path: "loomwright/docs/SPIKES/AGENT_SPAWN_PAYLOAD_PROBE.md", name: "## Verdict"}
  - {kind: "file", path: "loomwright/scripts/capture-task-spawn-payload.sh"}
requires: []
lanes:
  - "loomwright/docs/SPIKES/AGENT_SPAWN_PAYLOAD_PROBE.md"
  - "loomwright/scripts/capture-task-spawn-payload.sh"
  - "loomwright/scripts/progress-event-fixtures/*"
  - "loomwright/scripts/emit-agent-spawn.sh"
  - "loomwright/scripts/test-agent-spawn-event.sh"
  - "loomwright/scripts/emit-progress-event.sh"
  - "loomwright/scripts/test-progress-state.sh"
  - "loomwright/hooks/hooks.json"
  - "loomwright/docs/HOOKS.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - "README.md"
  - ".claude-plugin/README.md"
  - "CLAUDE.md"
  - "CHANGELOG.md"
external_requires:
  - "Claude Code >= 2.1.237 PreToolUse hook dispatch for the Task tool (the very thing under test — an absent or id-less payload is the NO-GO branch, not a failure)"
```

**Why `provides` names only three artifacts — and the TWO gaps that creates.** The deterministic
`outputs_verified` gate is satisfiable on **both** branches of this item, by construction.
`emit-agent-spawn.sh`, the `hooks.json` entry and the doc count bumps exist **only** on GO, so
listing them in `provides` would fail the gate on a legitimate NO-GO — the outcome the
requirement calls a pass. Two things therefore go unchecked by the deterministic gate, and both
are named here rather than left implicit:

1. **It cannot prove the GO-branch emitter exists.** A GO verdict with no emitter in the diff
   passes `outputs_verified`.
2. **It cannot distinguish a REAL probe run from an UNRUN one.** All three `provides` entries
   live in files this subtask itself creates, so a stub capture script plus a probe doc whose
   `## Verdict` heading carries an unevidenced NO-GO satisfies every entry without a live
   session ever running. The `## Verdict` symbol token forces the section to exist; it
   constrains no content.

Both are carried by the Acceptance Criteria, the Outcomes Rubric and the Phase 4.5 holistic
review instead — see Risk Assessment R4 for what the reviewer must check.

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| **R1 — the worker cannot trigger the hook from inside itself.** A `loomwright:worker` subagent cannot spawn Task subagents (spawn-depth), so it can never produce a `PreToolUse[Task]` event in its own session. | HIGH | Capture out-of-session: write the capture hook into a settings JSON and run a **separate** headless session that spawns a subagent — `claude -p --settings <capture-settings.json> "<prompt that spawns one subagent>"`. `--settings <file-or-json>` is a verified real flag on 2.1.237, and this repo already ships detached `claude -p` dispatchers (`loomwright/scripts/dispatch-pr-review.sh`), so the pattern is proven here. Use `-p`; add no permission-bypass flags. |
| **R2 — the payload may not fire, or may carry no joinable id.** Sourced from the documented contract, not an observation (the overview says so explicitly). | HIGH | This is the item's gate, not a defect. Run the probe FIRST, before a line of emitter is written. On no-fire or no-joinable-id, stop and close NO-GO with the evidence and the measured reason committed. Do **not** substitute a plausible-looking payload shape — this repo's `SubagentStop` history (`last_assistant_message` + `agent_transcript_path`, no `result_block`) is the precedent for why. |
| **R3 — a mid-session hook registration may not take effect.** Hooks are read at session start; editing `.claude/settings.local.json` inside a live session is not a reliable way to arm a capture hook. | MEDIUM | The R1 mechanism sidesteps this entirely — the capture session is fresh, so its settings are read at its own start. Never conclude "the hook does not fire" from a mid-session registration that silently never armed; that is a false NO-GO. The probe record must state which mechanism produced the result. |
| **R4 — the deterministic gate covers neither the GO branch nor the probe's reality.** `provides` is intentionally branch-agnostic (see the two numbered gaps in the note above), so `outputs_verified` passing means neither that the emitter was written nor that the probe was ever run. | MEDIUM | The Outcomes Rubric and the Phase 4.5 holistic review are the only checks here. The reviewer MUST: (a) read `## Verdict` first and judge the diff against the branch it declares — a GO verdict with no emitter in the diff is a FAIL, and a NO-GO verdict with an emitter in the diff is also a FAIL; (b) confirm the committed fixture under `loomwright/scripts/progress-event-fixtures/` is a REAL captured payload — non-empty, and structurally distinct from the existing `subagentstop-full.json`; (c) confirm `## Verdict` carries the exact command used and the raw payload (or the raw evidence that none fired). An unevidenced verdict is a FAIL on either branch. |
| **R5 — doc-surface lockstep.** A new hook takes the hook count 24 → 25 on every surface that restates it, in the same commit — that set is **DERIVED per AC #10 and #11, never enumerated here**; `check-doc-currency.sh` counts `[.hooks[][].hooks[]] \| length` and fails CI on the gate-matched ones, while the non-gate-matched ones go stale with CI green. | MEDIUM | Only on GO. Run `bash scripts/check-doc-currency.sh` before finishing and grep the OLD value repo-wide — a green run is necessary, not sufficient. On NO-GO no count changes and no bump is made. |
| **R6 — renaming the stop event could break live consumers.** `subtask_complete` is read by `build-state.sh` (the `## Session` projector), `curation-status.sh` and `test-curation-status.sh`. | MEDIUM | Additive only — emit `subagent_stop` **alongside** `subtask_complete`, never instead of it. Prove it by diffing real generated `state.md` / insights output before and after on the existing corpus; a code reading is not the evidence the criterion asks for. |
| **R7 — macOS-green is not CI-green.** Any new `stat`/`date`/`sed -i` use in the emitter or its test passes locally and fails on Linux CI (`stat -f %m` succeeds with garbage under GNU). | LOW | Mirror `emit-progress-event.sh` exactly; try `stat -c %Y` first and validate numeric before arithmetic. |
| **R8 — a concurrent writer on this checkout.** Four session worktrees exist and PR #168 is open; a concurrent agent can sweep uncommitted edits or advance `main` mid-run. | LOW | Commit early on the feature branch; before FINALIZE re-check `gh pr list` and `git log origin/main`. Never assert merge state from memory. |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-01-agent-spawn-event.md
```

---

## Outcome

- **Heal loop ran:** true
- **Heal decision:** PASS (round 1 FAIL → fixed → round 2 FAIL → fixed as follow-up PR #171)
- **Heal iterations:** 2
- **Heal remaining issues:** 0 (all round-2 findings shipped in PR #171)
- **Rubric score:** 5/5
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/170 (MERGED 2026-09-02T05:59:57Z, merge commit 462b27f)
- **Follow-up PR:** https://github.com/vikashruhilgit/loomwright/pull/171 (round-2 heal findings; branched off merged main, never pushed to the merged branch)
- **Until-mergeable dispatched:** false — resolved from the on-disk marker, not from control flow: no `.supervisor/review-dispatch/` marker contains this PR URL and no `review-pr-runner` process exists for it. The owned inline drain never ran because the PR was merged by the owner during Phase 4.5, leaving nothing open to drain. `auto_review` suppression held throughout and was restored byte-for-byte (key absent, matching its original state).
- **Verdict:** NO-GO on the requirement's central claim — `PreToolUse[Task]` fires per spawn but carries no `agent_id`. Per the source requirement, a NO-GO with committed evidence is a **successful** outcome, so this item is DONE.
- **Carried forward for items 02–05:** live liveness is reachable today keyed on `tool_use_id` (`subagent_type` + `description` are on the spawn payload); correlating with the historical `agent_id` corpus needs a second hook (`PostToolUse[Task]`) and resolves only at agent completion — a re-plan, not a continuation. Requirement scope item 3 (`agent_type` on the stop side) was already implemented before this item began and should be struck.
