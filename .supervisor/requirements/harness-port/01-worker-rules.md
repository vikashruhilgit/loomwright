# 01 — Worker rules: honest limits, no self-promotion, shared services read-only (ONE edit, ONE budget raise)

## Status: pending

> **Cross-queue amendment (2026-09-22).** This item is sequenced by `.supervisor/requirements/_BACKLOG-hardening-sequence-2026-09-22.md` AFTER `six-phase-loop-gaps/01` and `/02`, which ALSO add `agents/worker.md` prose, an optional WORKER_RESULT list (`deviations`), a `validate-worker-result.py` rule and a worker budget raise. Therefore: (a) the validator rule number is **the next after the live last rule** in `scripts/validate-worker-result.py` at implementation time — "rule (10)" below is the number as of `05823bf`, not authoritative; (b) `worker 5876/5905, 29 headroom` is the `05823bf` measurement — re-run `bash scripts/check-token-budget.sh` and raise from the LIVE number (measured + ~10%), one raise-log row naming this item; (c) H1 "one worker.md PR, one budget raise" holds WITHIN this folder only — the two sibling-queue raises are legitimate and precede this one. Re-verify every "Verified premises" row against `main` before starting.

## Problem
`loomwright/agents/worker.md` has no instruction to (a) name what it could not verify, (b) refrain from stamping
its own follow-up work as ready for a queue, or (c) treat shared local services as read-only when running in
parallel. Each is a small rule, but the worker prompt has **29 proxy tokens (~116 bytes) of headroom**
(`bash scripts/check-token-budget.sh` → `worker 5876/5905`), so three separate PRs each breach `check-token-budget`
and CI fails CLOSED. `raise_rule` in `loomwright/docs/prompt-token-budgets.json` says a raise edits the JSON and the
`ARCHITECTURE_CONTRACTS.md` mirror row in the same PR — so the three rules land together with one raise (decision H1).

## Goal
One `agents/worker.md` edit adds the three rules; `WORKER_RESULT` gains the optional `not_verified[]` field (schema +
validated shape, so it is not invisible to the gate); the spawn contract passes `subtask_ordinal`; the budget is
raised once. Absent inputs ⇒ byte-identical worker behaviour and result blocks.

## Scope
1. **`loomwright/agents/worker.md` — three rules, terse, generic** (placeholders only; no product/tool/port names):
   - **(a) Honest limits.** For every surface the diff affects that you did not observe running — a rendered
     `<route>`/view, a CLI path, a consumer of a contract you changed — emit one `not_verified` item
     `{surface: <string>, reason: <string>}`. A reason is a reason, not an exemption: "needs a write to a shared
     `<service>`", "needs a multi-step flow", "no local runtime" are all valid items, never a reason to omit the
     surface. Zero items ⇒ omit the field entirely (do NOT emit `not_verified: []` or a placeholder).
   - **(b) No self-promotion.** Any follow-up item you create (a requirement/story file, a task in the tracker in
     use) carries `## Status: proposed` (or that tracker's "not ready" marker) and is written to a location the
     intake does not read as ready (e.g. a `proposed/` subfolder when the source is a requirements folder). You
     never write the marker or location a queue reads as ready; only a human promotes. (Mechanism: item 02.)
   - **(c) Shared local services.** When your spawn prompt carries a `Shared local services:` line (item 06),
     every `<service>` it lists is read-only for you — no reset, seed, migrate, truncate or write. A verification
     that would need such a write is skipped and reported via (a). If the line names a `<PORT_ENV>`, set it to
     `<base> + subtask_ordinal` for any server you start; if it names none, start nothing that binds a port the
     line lists. The line is the project's declaration — the plugin cannot make a host app honour `<PORT_ENV>`;
     say so in the rule.
2. **`loomwright/docs/RESULT_SCHEMAS.md` §WORKER_RESULT:** add `not_verified: object[]` — optional, additive,
   `schema_version` stays 2 (same precedent as `out_of_lane`); item shape `{surface: string, reason: string}`,
   both non-empty; "absent by default; an empty list MUST be serialised as absent". One happy-path example line.
3. **`loomwright/scripts/validate-worker-result.py`:** new rule (10) mirroring rule (9) `out_of_lane`: WHEN
   PRESENT, `not_verified` must be a list of dicts each with non-empty string `surface` and `reason`; `null`, a
   non-list, or a malformed item ⇒ block with a named reason; absence ⇒ accepted at any schema_version. The
   block is emitted in the documented SubagentStop command-hook shape (top-level `{"decision":"block","reason":…}`
   — see 00 §Cross-cutting facts; `{"ok": false}` blocks nothing). Test in the existing test file for this
   validator: present-valid, present-malformed (blocks), present-null (blocks), absent (accepted) — plus a
   **mutation control**: delete rule (10) → the malformed case must FAIL the test.
4. **`loomwright/skills/async-orchestration/SKILL.md` Part 2 — worker spawn contract:** add `subtask_ordinal:
   <1-based position in the brief's subtask list>` to the fields passed to every worker (parallel, sequential and
   Single-Agent paths). Name is `subtask_ordinal`, NOT `subtask_index` — the skill already uses "Subtask index"
   for the ids/titles/deps list (decision H8). Re-measure `execute-manager` (3216 headroom; no raise expected).
5. **Budget raise:** `loomwright/docs/prompt-token-budgets.json` `.agents.worker.budget` = live measured + ~10%
   with a one-line `note` justification naming this item; mirror row in `loomwright/docs/ARCHITECTURE_CONTRACTS.md`
   §"Prompt Token Budgets" (the gate asserts the two are equal; drift fails CI closed).
6. **Docs:** CHANGELOG paragraph; version bump (`plugin.json` + `marketplace.json` + CHANGELOG only — memory
   `release-surfaces-readme-claude-md-no-longer-bump`).

## Non-goals
No transport of `not_verified` beyond the worker's own result block (item 04). No intake change (item 02). No brief
or spawn-prompt line for shared services (item 06) — rule (c) is inert until 06 lands, by design. No change to
`outputs_verified` / `outputs_gap` / `status` semantics; `not_verified` never influences `status`.

## Acceptance criteria
- `bash scripts/check-token-budget.sh` green after exactly ONE `worker` raise; JSON budget == ARCHITECTURE_CONTRACTS
  cell (the gate's own assertion).
- `grep -c 'not_verified' loomwright/agents/worker.md` ≥ 2 (rule (a) and rule (c)'s cross-reference);
  `grep -c 'Status: proposed' loomwright/agents/worker.md` = 1; `grep -c 'subtask_ordinal' loomwright/agents/worker.md loomwright/skills/async-orchestration/SKILL.md` ≥ 2.
- `grep -rn 'subtask_index' loomwright/` → 0 (the wrong name is not introduced).
- Validator: the four shape cases pass; the mutation control fails when rule (10) is removed; the block output is
  the `decision: block` shape (test asserts on `decision`, not on `ok`).
- RESULT_SCHEMAS §WORKER_RESULT documents the field with the "empty ⇒ absent" rule and `schema_version` stays 2.
- Portability: `grep -nE 'localhost|127\.0\.0\.1|:[0-9]{4}\b|postgres|mysql|redis|docker' loomwright/agents/worker.md` → 0
  new hits (compare against `git show origin/main:loomwright/agents/worker.md`).
- Prompt-level (not machine-checkable — record as such): a worker asked to change a template it never renders emits
  ≥1 `not_verified` item in a live spawn; a worker with nothing unverified emits no field.
- Full test loop + root checks green (00 §Cross-cutting facts).

## Verified premises (re-check before starting)
- `check-token-budget.sh` live table at `05823bf`: worker 5876/5905 (29), execute-manager 35430/38646 (3216).
- `validate-worker-result.py` rules (6)(7)(9) and REQUIRED_FIELDS at the top of the file; `out_of_lane` rule (9)
  comment contrasts it with unvalidated `memory_candidates`.
- `async-orchestration/SKILL.md` §"Pointers, not payloads" and the worker spawn block listing "Subtask index
  (compact — ids/titles/deps only …)".
- RESULT_SCHEMAS §WORKER_RESULT `out_of_lane` / `memory_candidates` additive-field wording.
