# 06 — Token ceiling for `/automate` and `/autonomous` + single-run-per-repo lock

## Status: pending

## Problem
There is no spend ceiling anywhere in the plugin (0 hits for `max_cost|spend cap|cost ceiling|token ceiling`
across `loomwright/`). An `/automate` item is Launch Pad + Supervisor + N workers + reviewers + rubric + up to 5
drain rounds, each round pushing and re-triggering a CI review; the weekly subscription cap has already been
tripped by this pattern (2026-09-15, memory `claude-review-red-has-three-distinct-causes`). The only spend
signal is `emit-token-ledger.sh`'s `{"event":"token_ledger", input_tokens, output_tokens, cache_*}` lines in
the session JSONL — recorded, never read as a limit. Separately, `automate-loop/SKILL.md:357` states
"single-run-per-repo is an assumed constraint, not enforced"; two runs in one checkout race `git checkout`, the
`auto_review` toggle and `state.md` (memory `concurrent-heal-loop-sweeps-uncommitted-edits`); memory
`review-gate-brief-conformance-queue` names the `.lock` at PICK as the one unqueued follow-up.

## Goal
A run can be given a token budget it cannot exceed (fail-CLOSED PARK, never a silent continue), and two
plugin runs cannot share a checkout at the same time.

## Scope
1. **Ledger reader — `scripts/read-token-ledger.sh --session <id> | --run-id <automate run id>`** prints
   `INPUT=<n> OUTPUT=<n> CACHE_READ=<n> CACHE_CREATE=<n> TOTAL=<n> EVENTS=<n>` summed over the matching
   `token_ledger` events (session JSONL(s) under `.supervisor/logs/`; an automate run id maps to the sessions
   its `## Progress` lines name — read `automate-loop/SKILL.md` §3 for where session ids are recorded, add
   them if they are not). Fail-safe: unreadable ⇒ all zero + `LEDGER_UNREADABLE=1`.
2. **`--max-tokens <N>`** on `/automate` and `/autonomous` (commands + skills): parsed at INIT, carried in
   the run file `## Config` (automate) / `state.json` (autonomous). Checked at: automate PICK (before each
   item), autonomous EVALUATE (before each iteration), and Supervisor Phase 3 poll loop entry (via the
   forwarded flag `--max-tokens`, mirroring `--cheap` forwarding). Breach or `LEDGER_UNREADABLE=1` when a
   ceiling is set ⇒ `## Status: paused`, `pause_reason: token_ceiling` (automate) / `status: aborted,
   status_reason: token_ceiling_reached` (autonomous) + notify. No ceiling set ⇒ unchanged behaviour (opt-in).
   Document the honest limit: the ledger counts what the hooks saw (SubagentStop leaves), not CI-side reviews
   or the main thread's own tokens.
3. **Run lock — `scripts/run-lock.sh acquire|release|status --owner <label>`** on `.supervisor/run.lock`
   (a directory, `meta` file with `pid`, `session_id`, `owner`, `ts`; TTL reclaim only when the pid is dead
   AND age ≥ 1800 s — the `dispatch-pr-review.sh` `acquire_lock` shape, reused not re-implemented if it can
   be factored). Acquired at automate PICK (released at item completion/park), Supervisor INIT (released at
   the completion tail / Phase 4 abort), `/autonomous` INIT. A held lock ⇒ the entry point PARKS with
   `run_lock_held owner=<label> pid=<pid> age=<s>` and never proceeds; `--force-unlock` is a human-only flag
   that prints what it broke. `session-resume.sh` shows a stale lock under a heading; `close-stranded-run.sh`
   releases a lock whose `session_id` equals the ending session.
4. **Docs:** `commands/automate.md`, `commands/autonomous.md`, `commands/supervisor.md` Parameters tables;
   `automate-loop/SKILL.md` §11 (replace "assumed constraint" with the lock); `autonomous-loop/SKILL.md`
   INIT; `docs/ARCHITECTURE_CONTRACTS.md` §"Cost Profiles" sibling section "Token ceiling"; PITFALLS.md;
   CHANGELOG; bump.
5. **Tests:** `test-read-token-ledger.sh` (fixture JSONL with 3 events ⇒ sums; malformed line skipped;
   missing file ⇒ zeros + flag); `test-run-lock.sh` (acquire/second-acquire-refused/dead-pid-old-ts-reclaim/
   dead-pid-young-ts-refused/release); seam tests asserting the PICK / EVALUATE / INIT prose names the check.
   **Mutation control:** make the ledger reader always return 0 ⇒ the "breach parks" seam fixture must fail.

## Non-goals
No dollar conversion (the plugin has no price table and must not invent one). No per-agent budgets. No
change to `--cheap`. The lock does not protect against an IDE-hosted agent that never runs a plugin entry
point (state the limit).

## Acceptance criteria
- `read-token-ledger.sh` sums the fixture correctly and is fail-safe.
- `/automate --max-tokens 1000` against a run whose ledger already exceeds 1000 parks with
  `pause_reason: token_ceiling` before picking (seam test on the run-file writer helpers where possible).
- `run-lock.sh acquire` twice in one checkout ⇒ second prints `run_lock_held` and exits non-zero; reclaim
  rules as specified.
- `grep -n 'assumed constraint, not enforced' skills/automate-loop/SKILL.md` → 0.
- Full test loop + root checks green.

## Verified premises
- `emit-token-ledger.sh` event shape (lines ~198–201, 276); written under the MAIN checkout's
  `.supervisor/logs/` (line ~97 derives `main_root`).
- `dispatch-pr-review.sh` `acquire_lock` (mkdir lock dir, `meta` TSV, pid liveness, 1800 s TTL).
- `automate-loop/SKILL.md` §1.5 helper list, §4 RECONCILE, §11 concurrent-run constraint; `--cheap`
  forwarding precedent in `autonomous-loop/SKILL.md:121,289`.
