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
