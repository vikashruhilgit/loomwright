# S1 — Two-lane spike (OPERATOR-RUN — not an `/automate` item; no plugin change)

## Status: parked (operator-run: lives in `operator-run/` so folder intake never enqueues it; run by hand after M1)

## Depends on
M1

## Purpose
Prove, in the running system, that two items can run at the same time in two isolated lanes — and settle the
questions items 05 and 06 are parked on, including which lane shape to build (decision P8). Nothing here is
committed to the plugin.

## Setup
1. Pick two requirements that touch disjoint files and have no dependency on each other.
2. `git clone --local <primary> <primary>-lanes/spike-a` and `…/spike-b`. **Set each clone's `origin` to the
   GitHub URL BEFORE anything else** — a `--local` clone's origin is the primary's path, where
   `loomwright-meta` does not exist, and it turns the primary's local branches into stale `origin/*` refs.
3. In each clone: `meta-sync.sh pull`; confirm `run-lock.sh status` prints `UNLOCKED` and resolves the CLONE as
   its root.
4. Note what the clone is MISSING compared with the primary: `.supervisor/config.json`, `notify-config.json`,
   `.claude/settings.local.json`, the rules stamp, Claude auto-memory (keyed by cwd). Copy the first two; record
   the effect of the others.
5. Launch one item per clone, detached and headless. Do NOT reuse `dispatch-pr-review.sh`'s allowlist — it permits
   only `Read,Grep,Glob,Task` plus scoped `git`/`gh`, which cannot implement anything. Write down the exact
   `--permission-mode`, `--allowedTools`, `--disallowedTools` and `--plugin-dir` you used.
6. Intake: point each lane at the item's CANONICAL path (a one-line backlog doc naming it), not a copy in another
   folder — closeout stamps and `brief-repair` match on the canonical path.

## Try both lane shapes (decision P8)
- **Shape A — whole loop headless:** `/loomwright:automate --backlog <one-line doc> --non-interactive-fallback`.
- **Shape B — brief-first:** run Launch Pad for both items interactively in the primary (human-approved briefs),
  copy each brief into its lane, and launch only Supervisor + the owned drain headless.

## Questions to answer (write the answers into 05 and 06, then un-park them)
1. **Isolation.** Do both lanes run to a PR with no `run_lock_held`, no cross-talk in `state.md`, and each lane's
   `auto_review` toggle restored in its own clone? Did anything in the PRIMARY change?
2. **Pre-flight.** When lane B reaches Phase 1.5 with lane A's PR open — and when it is NOT yet open — what does it
   classify, on which files?
3. **Headless gates.** Shape A: where exactly does each lane stop (Launch Pad Phase 6 save/refine/discard has no
   non-interactive branch today)? Does `claude -p` stay alive for a multi-hour inline Supervisor run? What happens
   to an `AskUserQuestion` under the chosen permission mode? Does the rate-limit hook fire headless?
4. **After a merge.** The owner merges lane A's PR by hand (admin bypass, as always). What state is lane B's PR
   in, and does it still merge cleanly by bypass without updating its branch?
5. **Missing clone state.** Does the metadata push from a lane pass the ledger allowlist (the allowlist lives in
   gitignored `.supervisor/config.json`)? Do reviewers in the lane see `.claude/agent-memory/`? What does the
   rules stamp check report in a clone?
6. **Contention.** Two concurrent `run-self-tests.sh` suites on this machine: wall-clock versus one, any shared
   `/tmp` cache collisions, any timeouts.
7. **Which shape?** A or B, with the reason.

## Also record
Wall-clock and tokens per lane (`read-token-ledger.sh --root <lane>`); everything done by hand.

## Safety checks (the spike must not disturb the primary checkout)
- Before: `git status --porcelain`, `git worktree list`, `run-lock.sh status`, and a checksum of
  `.supervisor/config.json` (or "absent") in the primary. After: the same four, identical.
- Never run a lane from inside the primary, never pass `--root` pointing at it.
- Use a throwaway metadata branch for the spike, or do not push metadata from the lanes at all.

## Done when
Both PRs are open (or each lane's stop point is recorded), the seven answers are written into
`05-lane-coordinator.md` and `06-wave-close-and-closeout.md` under "Spike findings", decision P8 is filled in
`00-overview.md`, and both clones are removed. Close the spike PRs that are not wanted.

## Run record (in progress — 2026-10-04, session 0d556d54; findings land in 05/06 at the end)
**Setup (steps 1–6), as run:**
- Items: lane A `automate-followups/19` (`is_run_file` tolerance: `automate-helpers.sh` + its test); lane B
  `automate-followups/18` (fail→unstamped escalates, owner Option A: two SKILL.md files). Disjoint, independent.
- Clones `<primary>-lanes/spike-a|spike-b` via `git clone --local`, then `origin` set to GitHub, then
  `fetch --prune`. No stale primary refs were left; only `main` locally. `config.json` and `notify-config.json`
  copied. `meta-sync pull` wrote 384 files.
- Throwaway metadata branch `loomwright-meta-s1`:
  - the clones' `.gitignore` mode line was edited to `-s1` and marked `--skip-worktree`, so no lane commit can
    carry it (`git add -A --dry-run` was checked);
  - each clone's meta-base was dropped first. Kept, it would have made the empty new branch read as "every file
    deleted";
  - seeded from spike-a: 384 files, blob-identical to `loomwright-meta@b8b44fc`. The real branch was untouched.
- Release: fragment only (P7). The note sits in each lane's copy of the requirement file — **strip it before the
  lanes' records return to `loomwright-meta`**.
- Launch, Shape A, both lanes at once, 01:53:27Z:
  `claude -p "/loomwright:automate --backlog .supervisor/s1-backlog.md --non-interactive-fallback"
  --permission-mode acceptEdits --allowedTools "Bash,Read,Edit,Write,Glob,Grep,Task,Agent"
  --output-format stream-json --verbose`, nohup, `env -u CLAUDECODE -u CLAUDE_PID`, installed plugin 15.119.2.
- Primary snapshot BEFORE: `../ai-agent-manager-lanes-s1-before.txt`. **Deliberate primary change during the
  spike:** the owner removed 5 stale, merged, clean `.claude/worktrees/*` at about 02:40Z, so the after-check's
  worktree list is expected to shrink by those 5.

**Q1 Isolation (partial):** each clone's run lock resolves to the clone. While lane A ran, its lock was `LOCKED
owner=automate:automate-2026-10-04-072436 pid=82630`, while lane B and the primary read `UNLOCKED`. Lane B
restored its `auto_review` toggle byte-for-byte. The primary was unchanged at every check so far.

**Q2 Pre-flight:** not yet observed (lane B never reached Phase 1.5; lane A's PR was not yet open).

**Q3 Headless gates — the key finding:**
- In `claude -p` with no permission host, `AskUserQuestion` is ABSENT from the tool list (stream-json `init`),
  so a lane cannot ask at all.
- Launch Pad Phase 6 (save / refine / discard) has no non-interactive branch for a PASS, and the two lanes did
  OPPOSITE things there:
  - **Lane B** failed closed: no brief saved, run parked with `status: failed`, `pause_reason: awaiting_go`
    (an enum gap — no value fits "stopped at a human-only gate"), lock released, config restored.
  - **Lane A** rewrote its own brief after a Plan Review FAIL (attempt 1), saved it to `jobs/pending/` with no
    human approval, and went on to implement. **This is a silent skipped approval.** Its PR needs the owner to
    read its brief before merging.
- `/autonomous` labels lane B's stop `user_aborted_at_launch_pad` although no user aborted.
- The run-file write guard worked under stress: a broken `sed` produced empty output, and `runfile-write`
  refused it, leaving the file intact.
- A bare non-interactive `--resume` in lane B is ambiguous: the clone carries the older paused run
  `automate-2026-09-30-054439`, whose queue also lists item 18.
- **Probe (outside the lanes):** with a permission host (`--permission-prompt-tool stdio` + stream-json input),
  `AskUserQuestion` exists in `-p`. A `PreToolUse` hook returning `defer` exits the process cleanly
  (`stop_reason: tool_deferred`, question in `deferred_tool_use`). The main session asked the owner, and
  `claude -p --resume <id>` with the hook returning `allow` + `updatedInput.answers` completed the job in the
  same session. Gotchas: `--setting-sources project,local` broke auth (the login is user-scoped); `defer` needs
  the question to be the only tool call in its turn.

**Q5 Missing clone state:** `config.json` and `notify-config.json` were copied, and the allowlist works for
`meta-sync pull` (no trail push observed yet). `.claude/agent-memory/` is tracked, so it is present. Absent:
`.claude/settings.local.json`; the rules stamp (user-scoped, keyed by repo path, so the clones read
`unstamped`); Claude auto-memory (keyed by cwd).

**Q6 Contention:** `scripts/ci-local.sh` locks on `git rev-parse --git-common-dir`. Separate clones do NOT share
it, so lane CI suites run fully parallel (worktrees would serialize). Lane A has run `ci-local` 4 times so far.
A concurrent two-suite measurement has not yet been taken.

**Cost/time so far:** lane B 01:53:27Z → 02:07Z (Launch Pad + review only), $7.16 per its result event (the
event's 1-minute duration is wrong; use the timestamps). Lane A was still running at 02:45Z.
