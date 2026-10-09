# Supervisor Job: pa/05 Validation 4/5 fixes B — lane park notification, real token counts, and the leaking lane-feed test

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (extra worktree `ai-agent-manager-pa05-engine` — detached at #426's old head `8226dfe`; not used by this job, do not touch it)
- **Source requirement:** .supervisor/requirements/parallel-automate/24-pa05-validation-fixes-b.md
- **Base commit:** 9a65ecb7c9b43bf55fee6314a7ed283731498992

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2-compatible shell + jq + python3, the stack `automate-lanes.sh` and `emit-token-ledger.sh` already use |
| 2 | Dependency Availability | GO | no new dependency; `notify-desktop.sh`, `send-webhook.sh`, `read-token-ledger.sh` already on `main` |
| 3 | Architecture Fit | GO | F6 stays inside the lane seam (pa/05 #426, pa/23 #434); F8 is a fix to the shared SubagentStop emitter; sequential path untouched |
| 4 | Scope vs Supervisor Capability | CAUTION | three independent defects; single-agent by the Decomposition Threshold (F6 and F8 both edit §14 of `SKILL.md` and `TELEMETRY.md`), but F8 changes a shared hook used by every run — see Risk Assessment |
| 5 | Hard Blockers | GO | none; the live `--parallel 2` re-validation needs the owner's typed command (operator step, not the worker's) |

**Overall Verdict:** CAUTION

## Task
**Goal:** Fix F6, F8 and F12 from pa/05's Validation 4/5 run so that every lane park reaches the owner the same documented way, per-lane and per-run token totals are real (so a `--max-tokens` share can park a lane), and a test-suite run leaves no live process behind.

**Problem Statement:**
The owner needs `/automate --parallel N` safe to release; the pa/05 release bump is held until this item merges.
Currently a lane's `ready_for_release` notification is not delivered (F6), every token ledger total reads 0 so `--max-tokens` can never trip (F8), and each suite run leaks a `tail -f | grep | jq` pipeline that hangs any `ci-local | tail` caller (F12).
Success looks like: each defect has a hermetic test that fails on `9a65ecb` and passes on the branch, and §14 + `TELEMETRY.md` describe exactly what the code does.

Read the source requirement's `## Problem` first. **Two of its root-cause statements are corrected below** — Launch Pad checked both in the running system on 2026-10-08 (session 33e9ed8c), and the evidence is quoted so the worker can re-run it:

- **F12 — the cause is the unescaped `+`, NOT the `/var` symlink.** `test-automate-lanes.sh` sets `T="$(cd "$(mktemp -d)" && pwd -P)"` near its top, so `$LR2` is already the resolved path. The T8 cleanup line (`sleep 1.5; pkill -f "tail -n +1 -f $LR2/L6.stream.log"`) never matches because `pkill -f` takes an extended regex and ` +1` means "one or more spaces, then 1" — it cannot match the literal `-n +1`. Probe (scratch file, macOS): `pgrep -f "tail -n +1 -f <file>"` → no match; `pgrep -f "tail -n \+1 -f <file>"` → matches the pid. Consequence: the leak is NOT macOS-only — procps `pkill` on Linux uses the same ERE semantics, so CI leaks it too (each CI job's runner tears the processes down, which is why it never hung there).
- **F8 — the cause is not lane-specific: no ledger line anywhere carries tokens.** `emit-token-ledger.sh` records real usage only when the SubagentStop payload carries usage fields, and its header says those fields are "EXPECTED ABSENT"; otherwise it writes a transcript-byte PROXY line (`"proxy":true`), which `read-token-ledger.sh` counts in EVENTS with 0 tokens. Evidence on the primary checkout: `read-token-ledger.sh --run-id automate-2026-10-08-071524` (pa/23's sequential run) → `TOTAL=0 EVENTS=7`; the 43 most recent `token_ledger` lines across `.supervisor/logs/*.jsonl` are all `proxy:true`, `usage:null`. So `ceiling-check` reads `OK total=0` on every run, sequential or lane. The real numbers exist: a subagent transcript (`agent_transcript_path`, `~/.claude/projects/<slug>/<session>/subagents/agent-<id>.jsonl`) carries `message.usage` (`input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`) on its `type: "assistant"` lines, **repeated once per streamed content block, and the repeats are NOT identical** (Plan Review attempt 1 finding, re-verified by Launch Pad): `input_tokens` and both cache fields repeat unchanged, but `output_tokens` on the early lines is a stream-start placeholder (typically 6–16) and only the FINAL line for that id — the one whose `message.stop_reason` is non-null — carries the real count (e.g. one id read 8, 8, 263). Older transcripts often lack that final line entirely (across 8 recent transcripts, most ids showed only placeholder values). So the per-id rule is: take the line with a non-null `stop_reason` when one exists, else the per-field MAX across that id's lines — never the first line; and output tokens can still be UNDER-counted when the final line is absent (an honest limit to document, never papered over). The parent's `LEDGER_UNREADABLE=1` in the run evidence is a separate fact: a `--parallel` coordinator runs no `/autonomous`, so its run file has no `session_id` lines.
- **F6** is as the requirement states: the step is prose; L1 called `send-webhook.sh` (stderr `repo_webhook_ignored slug=…`, no user-scope egress grant) and logged it as sent; L2 reported a desktop notification. The merge watcher already has the pattern to reuse: `automate-merge-watch.sh`'s `notify_as <gate_type> <msg>` builds a `{hook_event_name:"Notification",notification_type,message}` payload with `jq -cn --arg` and pipes it to `notify-desktop.sh` (a stdin-payload HOOK, not a CLI — never call it with args or `--help`; it blocks on stdin), then calls `send-webhook.sh --event-type gate --gate-type <gt> --context <msg>`. Both are fail-SAFE and print nothing useful to stdout, so "what was delivered" must be read from their observable outcomes (e.g. `send-webhook.sh`'s stderr / exit, `notify-desktop.sh`'s audit line in `.supervisor/logs/notifications.log`, the `LOOMWRIGHT_DESKTOP_NOTIFICATIONS=0` opt-out).

## Acceptance Criteria
- [ ] Given a lane at its `ready_for_release` park, when the lane runs the ONE new helper (an `automate-lanes.sh` subcommand dispatched through `automate-helpers.sh`, e.g. `lane-park-notify <runfile>`), then it sends the desktop notification AND the webhook with gate type `automate_ready_for_release` and the "do not merge yet — wave open" message, both fail-SAFE (always exit 0), and appends ONE `## Progress` line naming what was actually delivered per channel (e.g. `desktop: sent|disabled|failed`, `webhook: sent|ignored (<reason>)|failed`) — never "sent" for a channel that was not (F6)
- [ ] Given `send-webhook.sh` reports `repo_webhook_ignored`, when the helper runs, then the desktop notification is still attempted and the `## Progress` line says the webhook was ignored and names the delivered channel; a hermetic test proves both (stubbed `send-webhook.sh` / `notify-desktop.sh` through an env seam, no real notification, no network) (F6)
- [ ] Given §14 "Terminal park" of `loomwright/skills/automate-loop/SKILL.md` and the gate-type tables of `loomwright/docs/TELEMETRY.md`, when the change lands, then §14 names the helper (no prose-only notify step remains) and `automate_ready_for_release` is a documented `gate_type` row with its firing site, `--context` text and firing cadence (F6)
- [ ] Given a SubagentStop payload with no usage fields and a readable `agent_transcript_path` whose assistant lines carry `message.usage` (repeated per `message.id`, as real transcripts are), when `emit-token-ledger.sh` runs, then the ledger line records the real usage counted ONCE per distinct `message.id` (per id: the line with a non-null `message.stop_reason`, else the per-field max — never the first line), written as the four TOP-LEVEL integer fields `read-token-ledger.sh` already sums (`input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens` — the reader ignores a nested `.usage` object, and transcript usage carries non-numeric sub-objects) plus a marker a reader can tell it came from the transcript (`"usage_source":"transcript"`), and `read-token-ledger.sh` sums it into a non-zero `TOTAL`. The test fixture MUST repeat an id with a GROWING `output_tokens` (e.g. 8, 8, 263 with `stop_reason` only on the last) and assert 263 is counted exactly once, plus an id with no final line (asserting the max). An unreadable transcript still writes the existing proxy line, the emitter still always exits 0, and the existing proxy-path tests are untouched (F8)
- [ ] Given a fixture lane clone whose `.supervisor/logs/<sid>.jsonl` holds such a line and whose lane run file names that `session_id`, when `lane-status <parent_runfile> --tokens` runs, then the lane's `TOTAL` is non-zero; and when `ceiling-check <lane runfile> <share>` runs with a share below that total, then it prints `PARK: token_ceiling …` (F8)
- [ ] Given the finding, when the PR is opened, then its body states the F8 root cause (payload carries no usage; every line was a proxy, sequential runs included) with the evidence above, and §14 "Token split", `ARCHITECTURE_CONTRACTS.md` `## Token ceiling` and `TELEMETRY.md` §"Token ledger" state exactly which spend is still NOT counted (at least: the main thread's own tokens, CI-side `claude-review` spend, a `--parallel` coordinator's own run, and output tokens of a message whose final transcript line is absent) — and that `TOTAL` includes cache-read tokens (F8)
- [ ] Given `lanes_feed --follow` running, when its process receives TERM, INT or HUP, then it kills the `tail | grep | jq` pipeline it started before exiting, so killing the `lane-feed` process alone leaves nothing behind; T8's cleanup no longer relies on a `pkill -f` pattern (F12)
- [ ] Given `bash loomwright/scripts/test-automate-lanes.sh` finishes, when its EXIT trap (or a final leg) runs, then it asserts no process whose command line names the suite's `mktemp` dir `$T` is still running (`pgrep -f` on a literal-escaped `$T`) and fails the suite otherwise; this assertion fails on `9a65ecb` and passes on the branch (F12)
- [ ] Given every `loomwright/scripts/test-*.sh` and root `scripts/test-*.sh`, when swept for `pkill -f` / `pgrep -f` patterns, then no executed pattern UNDER-matches the process it targets because of an unescaped regex metacharacter (today only T8's `+` does — re-check, and note the result in the PR body). Over-matching is acceptable: the `.` in a private `mktemp` path (`tmp.XXXX`) inside the existing `_lane-run $T` / `$LR2` / `$L8` patterns is harmless and is left alone, and `test-verify-seam.sh`'s `pkill -f myapp` is a JSON fixture string, not executed (F12)
- [ ] Given each of F6, F8, F12, when its new test runs, then it fails against `9a65ecb` and passes on the branch (proof recorded in the PR body); for F12 also paste `pgrep -fl 'tail -n \+1 -f .*L6.stream.log'` after one suite run on `9a65ecb` (non-empty) and after one on the branch (empty), killing the pre-fix orphan afterwards
- [ ] Given no `--parallel` flag, when a sequential `/automate` runs, then nothing changes except that its ledger lines now carry real usage; the existing sequential tests are untouched
- [ ] Given the requirement's Validation 3 (a live `--parallel 2` run, shared with item 23's unrun Validation 3), when the PR is otherwise READY, then the PR body lists it under "Not verified" as an operator step and the worker never starts that run

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Fix F6/F8/F12 with tests and contract docs | all | 8-11 modify (3 conditional), 1 create | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "changelog.d/parallel-automate-24-pa05-validation-fixes-b.md"}
  - {kind: "symbol", path: "loomwright/docs/TELEMETRY.md", name: "automate_ready_for_release"}
  - {kind: "symbol", path: "loomwright/scripts/emit-token-ledger.sh", name: "usage_source"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-lanes.sh", name: "Validation 4/5 fixes B"}
requires: []
lanes:
  - "loomwright/scripts/automate-lanes.sh"
  - "loomwright/scripts/test-automate-lanes.sh"
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/emit-token-ledger.sh"
  - "loomwright/scripts/test-token-ledger.sh"
  - "loomwright/scripts/read-token-ledger.sh"
  - "loomwright/scripts/test-read-token-ledger.sh"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/docs/TELEMETRY.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/PITFALLS.md"
  - "changelog.d/parallel-automate-24-pa05-validation-fixes-b.md"
external_requires: []
```

The `Validation 4/5 fixes B` symbol is the new test-group header in `test-automate-lanes.sh`, following that file's `# ---- <Letter>: <title> ----` convention (e.g. `# ---- AA: Validation 4/5 fixes B (parallel-automate/24) ----`). `automate-helpers.sh` is in the lane only for the dispatch `case` line and header entry of the new F6 subcommand. `read-token-ledger.sh` / `test-read-token-ledger.sh` / `PITFALLS.md` are in the lane only if the F8 fix or its honest-limit text needs them; leave them untouched if unused.

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` |

## House Rules

> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| F8 changes a SHARED SubagentStop hook that fires for every subagent in every run, not just lanes (Feasibility (Phase 2.5), check 4) | HIGH | Keep the emitter's always-exit-0 trap and every existing no-op path; read the transcript with a bounded, streaming parse (it can be MBs); fall back to the existing proxy line on any read/parse failure; all existing `test-token-ledger.sh` legs must stay green unchanged |
| F8 makes `--max-tokens` live for the first time: ceilings that never tripped (TOTAL was always 0) will now park, and `TOTAL` is dominated by cache-read tokens | HIGH | Say so plainly in the changelog fragment and in `ARCHITECTURE_CONTRACTS.md` `## Token ceiling`; do NOT change `TOTAL`'s formula in this item (that is an owner decision — note it under "Not verified / follow-ups" in the PR body if the worker thinks a cache-excluded figure is needed) |
| F8 double-counting: transcripts repeat `message.usage` per streamed block, and a resumed subagent's transcript is re-read at each SubagentStop | MEDIUM | Dedupe by `message.id` within one emission (test with a fixture that repeats ids); state in the honest limits whether a resumed agent's earlier messages are counted again at its next stop, and test whichever behaviour is chosen |
| F12's documented diagnosis (path spelling) was wrong; a fix that only escapes the path would leave the leak | MEDIUM | The fix is the `lanes_feed --follow` signal trap plus the `$T` no-survivor assertion; the PR body records the `+` probe as the root cause and corrects the requirement's statement |
| F12 trap never fires: bash defers a trapped signal until the current FOREGROUND command returns, and `tail -f` never returns; a non-interactive bash also starts background children with SIGINT ignored | HIGH | Run the follow pipeline in the BACKGROUND and block on `wait` (a trapped signal interrupts `wait`); the trap kills the pipeline's pids (or its process group) explicitly, then exits; the `$T` no-survivor assertion proves it |
| F6 must report delivery truthfully, but both notifiers are fail-SAFE and silent on stdout | MEDIUM | Read observable outcomes only (webhook stderr/exit, the desktop audit line or opt-out); when an outcome cannot be read, say `unknown`, never `sent` |
| Contract restatement drift: §14, `ARCHITECTURE_CONTRACTS.md` and `TELEMETRY.md` restate each other (house rule above) | MEDIUM | Update all three in the same commit as the code; grep for `do not merge yet`, `automate_ready_for_release`, `proxy`, `Token split` before committing. The message `do not merge yet — wave open` is also restated in `docs/result-schemas/automate-run.md`, `commands/agent-help.md` and `commands/automate.md`: those are READ-ONLY for this item (outside its lanes) unless the message text changes — keep the text unchanged |
| F8 `usage_present()` branch copies a payload's nested `usage` object as-is, which the reader (top-level fields only) reads as 0 | MEDIUM | Whatever path records real usage writes the four top-level integer fields; if the worker touches the existing nested-copy branch, test it the same way |
| Release bump convention: the normal sequential PR runs `bump-version.sh` as its last commit | HIGH | **Do NOT run `scripts/bump-version.sh`.** Owner decision 2026-10-08: the pa/05 release is held until items 23 and 24 merge; this PR adds only its `changelog.d/` fragment (`<!-- bump: patch -->`, or `minor` if the worker judges live ceilings a behaviour change — say which and why) beside the pending `parallel-automate-05-lane-coordinator.md` and `parallel-automate-23-pa05-validation-fixes-a.md` |
| A pre-fix F12 proof run on `9a65ecb` leaks one more orphan pipeline | LOW | Kill it right after with `pkill -f 'tail -n \+1 -f .*L6.stream.log'` and confirm `pgrep` is empty |
| bash 3.2 / BSD traps on macOS (project memory `ead04b14`; repo lessons) | LOW | `"${arr[@]}"` guarded under `set -u`; no GNU-only flags; validate with `bash scripts/ci-local.sh` |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-08-pa24-lane-validation-fixes-b.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-10-08T14:14:12Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/435
- **Branch:** feature/pa24-lane-validation-fixes-b
- **Files changed:** 13
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** F6 lane-park-notify (truthful per-channel ## Progress line, automate_ready_for_release gate), F8 transcript-sourced token usage deduped per message.id with a locked position watermark, F12 lane-feed --follow signal trap + suite no-survivor assertion. Phase 4.5: iter 1 FAIL (2 HIGH emitter defects, fixed in 3a1cf14), iter 2 FAIL (deviation mislabel only, relabelled, no code change), iter 3 PASS. ground_truth 2/2. No version bump (release held).

## Not verified
- **Validation 3 — live /automate --parallel 2 run (shared with item 23)** — operator step; never started by the worker (subtask 1)
- **Real desktop banner and real webhook POST from lane-park-notify** — tests stub both notifiers through env seams (subtask 1)
- **emit-token-ledger.sh under a real SubagentStop firing** — synthetic transcripts only; installed 15.125.1 still runs the old emitter (subtask 1)
