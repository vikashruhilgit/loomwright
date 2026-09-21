# 04 — `not_verified` transport end-to-end (worker → state → PR body + done brief → `/verify` impact rows)

## Status: pending
## Depends on: 01 (the worker emits the field; the schema + validator exist)

## Problem
After item 01 the worker names what it could not verify, but the list dies in the worker's transcript.
`EXECUTE_RESULT` carries no per-worker optional fields (its `out_of_lane` note in `docs/RESULT_SCHEMAS.md` explains
that per-worker reports travel via Context-Keeper `record_worker_result` into `state.md ## Worker Results`); the
Phase 4 FINALIZE PR-body template (`skills/async-orchestration/SKILL.md` Part 2) has no such section; and `/verify`
resolves tickets by PATH under `.supervisor/` — it never reads a PR body. The human still has no greppable list of
unchecked surfaces, and the one tool built to walk surfaces never sees them (decision H4).

## Goal
`not_verified` items reach three surfaces — `state.md`, the PR body, and the completed brief — and `/verify` walks
them as `scope: impact` rows (decision H7). Zero items ⇒ all three surfaces byte-identical to today.

## Scope
1. **`loomwright/agents/context-keeper.md`** `record_worker_result` parameter contract: add `not_verified` to the
   `result {…}` field list and to the `## Worker Results` line it writes (one `not_verified: <n>` count on the row
   plus the items as an indented sub-list ONLY when n>0). Headroom 319 — raise per `raise_rule` if needed (JSON +
   ARCHITECTURE_CONTRACTS row, same PR).
2. **`loomwright/agents/execute-manager.md`** poll loop: pass the worker's `not_verified` through to
   `record_worker_result` unchanged (parallel path). **`skills/async-orchestration/SKILL.md`** Sequential and
   Single-Agent paths: the Supervisor records it the same way (mirror the `out_of_lane` "records the report only"
   sentence). `EXECUTE_RESULT` stays `schema_version: 1`, unchanged (add one note beside the `out_of_lane` note).
3. **`skills/async-orchestration/SKILL.md` Part 2 — FINALIZE PR Body Template:** new optional section
   `## Not verified` — one bullet per item `- **<surface>** — <reason> (subtask <id>)`, aggregated from
   `state.md ## Worker Results`; OMITTED entirely when every worker's list is absent/empty (no "none" line).
   Placed after `## Test Plan`.
4. **Done brief:** the completion tail that stamps `## Status: done` on the brief (`skills/self-heal-advisory/SKILL.md`
   step 2.5 — read it; do not restate it) also appends the same `## Not verified` section to the brief when non-empty.
   The brief is what `/verify` can find; the PR body is for the human.
5. **`loomwright/scripts/verify-run.sh`:** `acs <ticket>` gains, for `ticket_kind: brief`, an additional output key
   `not_verified: [{id: "NV1", text: "<surface> — <reason>", source: "not_verified", surfaces: []}]` read from the
   brief's `## Not verified` bullets (absent section ⇒ `[]`). The `acs[]` array is UNCHANGED. The qa-executor
   `--verify` step feeds those objects into the EXISTING impact manifest (`walk --scope impact --manifest`, shape
   `{id, text, source, surfaces}`) — so they land in the impact table, never the ticket score.
6. **`loomwright/skills/verify-walkthrough/SKILL.md`** §impact scope: add `not_verified` as a fourth best-effort
   source (after diff / brief-surfaces / prior-acs), with the same "NEVER inflates or deflates the ticket score"
   sentence and `source: "not_verified"` provenance.
7. **`loomwright/docs/RESULT_SCHEMAS.md`:** §WORKER_RESULT already has the field (item 01); add the transport note to
   §EXECUTE_RESULT and §CONTEXT_KEEPER_STATE (`## Worker Results` row shape); §VERIFY_* if a manifest/evidence
   shape gains the `not_verified` source value (read the enums first — memory `sweep-grep-gate-variants`).
8. **Docs:** POINTER_AUDIT unaffected (no new paste). CHANGELOG paragraph; version bump.

## Non-goals
No change to `outputs_verified` / `outputs_gap` / adjudication. No PR-body reader in `/verify`. No new `ac_id`
family; `AC<n>` ordinals and `summary-build`'s `scope: "ticket"` filter are untouched. No gating: a non-empty
`## Not verified` never blocks FINALIZE, Phase 4.5, READY, or `/automate` gate-eval.

## Acceptance criteria
- Fixture `state.md` with two workers, one carrying one `not_verified` item ⇒ the FINALIZE PR body contains exactly
  one `## Not verified` bullet; with none ⇒ the PR body has no such heading (diff against `origin/main`'s template
  output).
- The done brief for that run carries the same section; `bash loomwright/scripts/verify-run.sh acs <that brief>`
  returns `acs` unchanged and `not_verified` with one `NV1` object whose `source` is `not_verified`.
- `verify-run.sh summary-build` on a run whose evidence contains an `NV1` impact row reports the ticket score
  WITHOUT it (assert the ticket counts line equals the ticket-only fixture).
- `record_worker_result` fixture: a worker result with `not_verified` writes the count + sub-list; one without
  writes a row byte-identical to today's.
- `check-token-budget.sh` green (context-keeper raise if needed, with mirror row).
- Full test loop + root checks green.

## Verified premises (re-check before starting)
- `agents/context-keeper.md` operations table row `record_worker_result` (params list includes `out_of_lane`).
- RESULT_SCHEMAS §EXECUTE_RESULT blockquote "`out_of_lane` is NOT an EXECUTE_RESULT field".
- `async-orchestration/SKILL.md` Part 2 "PR Body Template" (Summary / Changes / Test Plan / Task).
- `verify-run.sh` header: `acs`, `walk --scope impact --manifest` (`{id, text, source, surfaces}`),
  `impact record-surfaces`; `verify-walkthrough/SKILL.md` §"Three sources feed the surface classification".
- `self-heal-advisory/SKILL.md` step 2.5 stamps `## Status: done` on the brief heading (per `is_done`'s comment).
