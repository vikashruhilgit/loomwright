# S1 — Two-lane spike (OPERATOR-RUN — not an `/automate` item; no plugin change)

## Status: parked (operator-run: lives in `operator-run/` so folder intake never enqueues it; run by hand after 03 merges)

## Depends on
03

## Purpose
Prove, in the running system, that two items can run at the same time in two isolated lanes using today's engine
unchanged — and collect the four answers items 05 and 06 are waiting on. Nothing here is committed to the plugin.

## Setup
1. Pick two requirements that touch disjoint files and have no dependency on each other.
2. `git clone --local <primary> <primary>-lanes/spike-a` and `…/spike-b`; point each clone's `origin` at GitHub.
3. In each clone: `meta-sync.sh pull`, then confirm `run-lock.sh status` prints `UNLOCKED` and that it resolves the
   CLONE as its root, not the primary.
4. In each clone, launch one single-item run headless, the way `dispatch-pr-review.sh` launches its drain (detached
   `claude -p`, namespaced slash command, pinned `--permission-mode` + `--allowedTools`):
   `/loomwright:automate --folder <dir holding only that item> --non-interactive-fallback`.

## Questions to answer (write the answers into 05 and 06, then un-park them)
1. **Isolation.** Do both lanes run to a PR with no `run_lock_held`, no cross-talk in `state.md`, and each lane's
   `auto_review` toggle restored in its own clone?
2. **Pre-flight.** When lane B reaches Supervisor Phase 1.5 with lane A's PR already open, does it classify CLEAR
   or OVERLAP? If OVERLAP, on which files (expect the version files unless item 01 has landed)?
3. **Human gates headless.** What does each lane do at Launch Pad feasibility / save, Plan Review FAIL, and the
   dismissed-findings ask under `--non-interactive-fallback`? Does `/autonomous` INIT's non-interactive detection
   abort (the known TTY false positive)?
4. **Merge.** After merging lane A's PR, what state is lane B's PR in (`main` is `strict: true`)? What does
   `gate-eval` say for lane B before and after updating its branch?

## Also record
- Wall-clock per lane versus the same items' sequential estimate.
- Token use per lane (`read-token-ledger.sh`), to size the default lane count (decision P2).
- Whether `.claude/agent-memory/` was visible to reviewers inside the clone.
- Anything that had to be done by hand.

## Safety checks (the spike must not disturb the primary checkout)
- Before starting, record from the primary: `git status --porcelain`, `git worktree list`,
  `run-lock.sh status`, and a checksum of `.supervisor/config.json` (or "absent").
- After the spike, record the same four and confirm they are identical.
- Never run either lane from inside the primary checkout, and never pass `--root` pointing at it.

## Done when
Both PRs are open (or a lane's park reason is recorded), the four answers are written into
`05-lane-coordinator.md` and `06-merge-train-and-closeout.md` under a "Spike findings" heading, and both clones are
removed. Close whichever spike PRs are not wanted; do not merge on the spike's behalf.
