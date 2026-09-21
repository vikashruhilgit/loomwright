# 07 — Multi-ticket queue with its own run file, resume by reconcile

## Problem
The owner wants `/verify` to "work on multiple tickets from requirement files, same as automate, but maintain
its state differently than automate/executor". `automate-loop` §3–4 already has the right discipline
(single run file, `## Progress` append-only, atomic writes, resume = glob + reconcile belief vs truth) but its
truth source is wrong for verification — `gh pr view` says nothing about whether the app still starts, the
session is still valid, or the branch under test moved. And `/verify`'s state must never share a file with
`/automate`: a verify pause (`needs_auth`) is not an automate pause (`awaiting_merge`).

## Goal
`/verify --folder <dir>` walks every not-done ticket in order, one run dir per ticket, under one queue file
in `.supervisor/verify/`; a crash or a `needs_auth` pause resumes exactly where evidence says it stopped.

## Scope
1. **Intake.** `--folder <dir>` reuses `automate-helpers.sh resolve-folder` verbatim (non-recursive `*.md`,
   skips `## Status: done`) — the subfolder skip convention applies unchanged. `--backlog` is Phase 2.
   Each ticket keeps its own `<run_id>/` (02); the queue is
   `.supervisor/verify/queue-<UTC ts>-<slug>.md`, written ONLY via `verify-helpers.sh queue-write`
   (atomic temp+rename; **line-count guard before every rewrite** — memory `runfile-write-accepts-empty-stdin`)
   and `queue-progress-append`. Template: `## Status: running|paused|done`, `## Source`, `## Run Config`
   (`limit`, `impact_limit`; `--notify`/`--cheap` passthrough NOT persisted, re-pass on resume),
   `## Queue` (`- [ ] <ticket> → <run_id>` / `- [x] … verdict: ...` / `- [x] … # skipped: <reason>`),
   `## Current` (`item`, `run_id`, `status`, `pause_reason: needs_auth|env_failed|limit_reached|null`),
   `## Progress` (append-only).
2. **Per-item loop.** pick next `- [ ]` → 03 single-ticket run (+04 auth, +05 sink, +06 impact) → on
   `run_end` check off with the derived verdict counts (from `summary-build`, never tallied here) → next.
   `--limit N` caps processed items, not queue size (automate §2 semantics). `needs_auth` ⇒ queue
   `paused` with that reason; the remaining items are untouched.
3. **Reconcile on every start** (bare `/verify --folder`, `--resume`): glob `queue-*.md` not `done`; for the
   `## Current` item compare belief vs truth — (a) the run dir's `evidence.jsonl` last line (`run_end` ⇒ item
   is done even if unchecked; `pause` ⇒ still paused; anything else ⇒ crashed mid-AC, resume at first
   unverdicted AC), (b) `git rev-parse <branch>` vs the `run_start` head sha — moved ⇒ the item's verdicts are
   STALE: mark `- [x] … # stale: head moved <old>→<new>` and re-queue a fresh item for it (never re-use the
   run dir), (c) `verify-env.sh auth-probe` before resuming an authenticated item. Two incomplete queues and
   no explicit `--resume <id>` ⇒ `AskUserQuestion`; under `--non-interactive-fallback` fail closed with
   `pause_reason: resume_ambiguous` (automate's exact convention).
4. **Never shares state with `/automate`.** `.supervisor/verify/` only; no read or write of
   `.supervisor/automate/`, `config.json`, `state.md`. A verify run inside an `/automate` tick (if ever
   wired) is a Phase 2 question — this item forbids it by omission and says so in the skill.
5. **Tests.** `scripts/test-verify-queue.sh`: 3-ticket folder with one `Status: done` ⇒ 2 items; `--limit 1`
   processes one and pauses `limit_reached`; kill after the first AC of item 2 (fixture flag) ⇒ resume picks
   item 2 at AC 2, item 1 stays checked; move the branch head between runs ⇒ item marked stale + re-queued,
   old run dir untouched; the empty-stdin guard: pipe an empty rewrite and the queue file must be
   byte-unchanged with a non-zero exit. Mutation control: remove the head-sha comparison and the stale case
   must fail.

## Non-goals
No auto-merge, no PR interaction, no `/automate` integration, no `--backlog`, no parallel items (D3 — one app
instance, one browser, sequential). No cross-project queues.

## Acceptance criteria
- `/verify --folder <dir>` with 3 tickets (1 done) creates one queue file with 2 `- [ ]` items and processes
  them in `LC_ALL=C` sort order.
- A `needs_auth` pause leaves the queue `paused` with that reason and the later items untouched; `--resume`
  after sign-in finishes both without re-running any AC that already has a verdict.
- A crash mid-item resumes at the first AC without a verdict; the finished item is not re-run.
- A moved branch head marks the item stale and re-queues it; verdict counts from the stale run never appear
  in the new item's summary.
- `find .supervisor/automate .supervisor/state.md -newer <marker>` after a full verify queue run is empty.

## Outcomes Rubric
- Intake reuses `resolve-folder`; nothing re-implemented
- Queue file atomic, append-only progress, line-count-guarded
- Resume position derived from evidence, staleness from head sha
- Separate store; automate/state untouched, proven by mtime
- Sequential, bounded, passthrough flags re-passed


## Status: done (PR #230, merge e39fc9f)
- **Completed:** 2026-09-16T06:49:43Z
- **Brief:** .supervisor/jobs/done/2026-09-16-verify-queue-and-resume.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/230
- **Reconciled:** 2026-09-21 by hand from the merged PR — the PR was merged outside the /automate loop, so nothing wrote this stamp at merge time.
