# 03 — Worker checkpoints (Orca: `orca worktree set --comment` at named moments)

## Problem
`/handoff` ("decision · why · tried/rejected") and `/dreaming` mine end-of-run artefacts: worker
summaries, session_end, postmortem. A hypothesis a worker confirmed or refuted MID-run, a blocker it hit
and worked around, an investigate→fix transition — none of it is recorded, so "tried/rejected" is
reconstructed from the final diff or lost. Orca's checkpoint pattern names exactly those moments and makes
the agent write one line each ("reproduced auth failure; testing credential-chain fix"). This is the raw
material the Twin thesis (accumulated judgment, Bet 2) is missing, and it is one event type.

## Goal
A worker leaves a short, structured trail of *what it concluded and why* at the moments that matter,
readable by the Floor lane, `/handoff`, and `/dreaming` — without forcing chat.

## Scope
1. **`worker_checkpoint` event** (renamed 2026-09-12 — `checkpoint` is the name of a Context-Keeper mechanism
   D5 deleted, listed in `EVAL_FINDINGS_AND_FIXES.md`; a reader or grep would conflate them) —
   `{"event":"worker_checkpoint","kind":"hypothesis_confirmed|hypothesis_refuted|blocker|
   transition|slice_done","text":"<≤200 chars, first line = the action>","paths":[…]}` appended by a tiny
   fail-safe helper (`checkpoint.sh`, exit 0 always, ledger path POSITIONAL and validated — memory
   `learning-emit-ledger-path-positional`, this bit us twice).
2. **Worker contract:** the worker prompt (`agents/worker.md`, 0 checkpoint mentions today) names the five
   moments and the helper — advisory wording ("emit a checkpoint when…"), never a gate; a worker that emits
   none is not penalized.
   **Pre-registered expectation (D11):** this is a prompt-instructed emitter — the class D5 measured at 6 agent
   events vs 560 hook events. Expect a LOW emission rate. Record, in this file, the rate over the first five
   real runs (checkpoints per worker, workers with zero); if it is <1 per worker the item's value is not
   proven and the SDK runner (D1/D6, which composes each spawn's prompt) is the carrier to move it to —
   not more prompt wording.
3. **Consumers:** `read-…`/`build-handoff.sh` renders checkpoints under "tried/rejected" with provenance;
   `build-floor.sh` carries the last checkpoint text per lane (item 05 renders it); `/dreaming` treats
   `hypothesis_refuted` lines as LESSON candidates (human-gated, as today).
4. **Adapter mirror (optional, item 06):** when `orca` is on PATH, mirror to `orca worktree set --comment`.

## Non-goals
Not a progress bar; not a substitute for `WORKER_RESULT`; never consumed by any gate. No `state.md` write.

## Acceptance criteria
- `checkpoint.sh` with a missing/invalid ledger path writes NOTHING and exits 0 (test both) — never a junk file.
- A fixture run with three checkpoints shows them in `/handoff` output under tried/rejected with the
  session id as provenance; `read-postmortem.sh`-style consumers that key on other fields are unaffected
  (verify their match filters — memory `verify-consumer-contract-before-for-free`).
- Worker prompt token budget stays within `prompt-token-budgets.json` (or the budget is bumped in the same PR).

## Outcomes Rubric
- One event type (`worker_checkpoint`), one fail-safe helper, positional ledger path validated
- Emission rate pre-registered and measured, not assumed
- Worker prompt names the moments advisorily
- `/handoff` and Floor consume it; `/dreaming` proposes from `hypothesis_refuted`
- No gate reads it

## Status: done (PR #233, merge 7732d89 + PR #234 merge 840cfc8, v15.81.0)
