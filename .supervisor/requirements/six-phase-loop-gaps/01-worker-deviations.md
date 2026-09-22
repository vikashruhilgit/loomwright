# 01 — Worker deviations record (`WORKER_RESULT.deviations` → `## Worker Results` → Phase 4.5 advisory)

## Status: pending

> **Cross-queue amendment (2026-09-22).** Sequenced by `.supervisor/requirements/_BACKLOG-hardening-sequence-2026-09-22.md`: this item lands BEFORE `six-phase-loop-gaps/02` and BEFORE `harness-port/01` (which adds `not_verified[]` to WORKER_RESULT, its own validator rule and its own worker budget raise). Therefore: (a) the validator rule number is **the next after the live last rule** in `scripts/validate-worker-result.py` at implementation time — "rule 10" below is the `05823bf` number, not authoritative, and `harness-port/01` will take the number after yours; (b) `worker 5876/5905, 29 headroom` is the `05823bf` measurement — re-run `bash scripts/check-token-budget.sh` and raise from the LIVE number (measured + ~10%), one raise-log row naming this item; item 02 and `harness-port/01` each re-measure and add their own row. Re-verify every premise against `main` before starting.

> **Rev 2 (2026-09-21, after red-team).** Changes from rev 1: (a) Phase 4.5 fixers are not workers — their
> `FIX_RESULT` never reaches `## Worker Results` — so the field is added to `FIX_RESULT` too and the advisory
> reads both, or item 02 §9's reviewer clause DoSes the heal loop; (b) the validator accepts any non-empty
> string — the kind prefix is a convention the prompt asks for, not a rejection rule, because rejecting an
> honest-but-unprefixed record while accepting silence is the wrong incentive; (c) worker token budget has
> 29 proxy tokens of headroom — the raise is in scope; (d) "validated when present" is a test-suite-visible
> guarantee — the runtime consequence of a validator `{"ok": false}` is a pre-existing plugin-wide question
> tracked in 00 §"Discovered during red-team", not this item's claim.

## Problem
A worker that departs from its subtask's plan, hits an edge case the brief never mentioned, or has to decide
something the brief left open records that fact nowhere durable. `grep -i deviat loomwright/agents/worker.md`
returns nothing; `WORKER_RESULT` (`docs/RESULT_SCHEMAS.md` §WORKER_RESULT, `schema_version: 2`) has
`summary` (≤200 tokens, "what was done") and `outputs_gap` ("what I did not deliver") but no "where I departed
from what was asked". The per-worker narrative, `.worker-summary.md`, is written in the worktree
(`agents/worker.md` §"Write summary file") and the worktree is removed at FINALIZE
(`skills/async-orchestration/SKILL.md` Part 2 worktree cleanup). Execute Manager reads it (~200 tokens) and
compresses it into `EXECUTE_RESULT` for the Supervisor — orchestrator-summary drift. Consequence: Phase 4.5's
code-reviewer must **infer** plan drift from the integrated diff alone; the `brief_conformance` advisory
(`skills/self-heal-advisory/SKILL.md` step 1f) asks "is each acceptance criterion addressed?" but cannot ask
"did the worker knowingly do something else, and why?". A worker-recorded deviation is written by the agent
that made it — the only party that knows.

## Goal
Every worker and every Phase 4.5 fixer can record, at near-zero cost, each deviation / edge case / open
decision / test diagnosis as one line; worker records survive worktree removal in `state.md`
`## Worker Results`; Phase 4.5 hands the union to the review lens as one advisory line, and a deviation that
contradicts an acceptance criterion surfaces as an ordinary finding through the existing gate. Nothing about
`heal_decision`, bounds, or never-merge changes.

## Scope
1. **Schema — `docs/RESULT_SCHEMAS.md` §WORKER_RESULT:** add `deviations: string[]` — optional, additive,
   does NOT bump `schema_version` (stays 2), **validated when present** (the `out_of_lane` precedent, with its
   reason restated next to the field: an unvalidated field lets malformed data through while
   `check-contract-parity.sh` stays green). Each entry is a non-empty string; **by convention** it starts with
   `plan:` (did something other than the subtask said, and what), `edge:` (an edge case the brief did not
   name and how it was handled), `open:` (a decision the brief left open and which way it went), or `test:`
   (a failing test's diagnosis — `test: <name> — <code wrong | assertion wrong | env>: <why>`; item 02 §8
   makes recording one the rule before fixing). An entry without a prefix is read as `other:` by consumers;
   it is never rejected. Absent by default; `[]` when explicitly nothing to report. REPORT-ONLY: never
   influences `status`, `outputs_gap`, or any validation rule — add an invariant note mirroring
   `out_of_lane`'s. **Bound:** ≤ 12 entries, each ≤ 200 characters — the field rides in a ~200-token summary
   read (Execute Manager) and a capped advisory (§6); longer stories belong in `.worker-summary.md` prose.
   **`docs/RESULT_SCHEMAS.md` §FIX_RESULT:** the SAME optional field with the SAME shape and bound —
   Phase 4.5 fix tasks legitimately edit assertions (reviewer-found wrong assertion, the "fix the CLASS"
   sweep) and must be able to carry their own `test:` diagnosis, or item 02 §9 flags every fixer assertion
   edit every round until `max_iterations_reached`.
2. **Validator — `scripts/validate-worker-result.py` rule 10:** absence accepted at any `schema_version`;
   when present must be an array of ≤ 12 non-empty strings, each ≤ 200 chars. Reject `null`, non-array,
   empty-string entries, over-count, over-length. Rule text transcribed into the docstring's rule list exactly
   as rules 1–9 are. (If `FIX_RESULT` has a validator, mirror the rule; read `hooks.json` first — as of
   2026-09-21 no `FIX_RESULT` validator hook exists, so document the field as prompt-contract only.)
3. **Parity pin — `scripts/check-contract-parity.sh`** WORKER_RESULT MANIFEST row: append `deviations`;
   `loomwright/scripts/test-check-contract-parity.sh` must still pass.
4. **Worker prompt — `agents/worker.md`:** (a) add `- deviations: ["plan: …", "edge: …", …]   # OPTIONAL`
   to the WORKER_RESULT output block directly after `memory_candidates`; (b) a short §"deviations" beside
   §"memory_candidates": the four kinds with one example each, the bound, the transient-vs-durable split
   (deviations are THIS run's story; `memory_candidates` are durable codebase facts — never cross-post), and
   "never secrets/PII"; (c) echo every entry verbatim under a `## deviations` heading in `.worker-summary.md`,
   one `- ` bullet per entry, heading omitted when empty — byte-for-byte the `memory_candidates` echo rule.
   **Token budget:** `bash scripts/check-token-budget.sh` → `worker 5876/5905, 29 headroom`; this prose does
   not fit. Raise `.agents.worker` in `docs/prompt-token-budgets.json` (measured + ~10%) and add the raise-log
   row in `docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" in the same PR (item 02 adds worker prose
   too — whichever lands second re-measures). Never trim unrelated `worker.md` prose to make room.
   **Fixer prompt:** the Phase 4.5 fix-task spawn prompt (`skills/self-heal-advisory/SKILL.md` review-and-fix
   loop, a `general-purpose` agent with no validator) gains the `deviations` line in its `FIX_RESULT` output
   shape with **conditional-mandatory** wording: *"a FIX_RESULT whose diff edits a test assertion and carries
   no `test:` entry is incomplete — add it before emitting"*. Optional elsewhere; one forgetful fixer must not
   cost a heal iteration.
5. **Carriage.** (a) `agents/context-keeper.md` `record_worker_result` result object gains `deviations`
   (as `out_of_lane` was added); `skills/state-management/SKILL.md` §"Worker Results" template gains the
   field's rendering (it is a fixed template — Context-Keeper needs the shape there, not only in its
   parameter table). **Both Supervisor record sites** — Single-Agent step "Record result via Context-Keeper —
   including the worker's `out_of_lane` field" and the `--sequential` path's equivalent — and Execute
   Manager's poll-loop record call name `deviations` in the same sentence as `out_of_lane`. `EXECUTE_RESULT`
   stays at `schema_version: 1` — add the same "NOT an `EXECUTE_RESULT` field" blockquote `out_of_lane` has.
   (b) **Fixer deviations:** `FIX_RESULT` is returned in-context to the Supervisor, not through Context-Keeper.
   The review-and-fix loop keeps a per-run `fixer_deviations` list (appended from each iteration's
   `FIX_RESULT.deviations`, prefixed `fix-<iteration>`) and step 1g reads it alongside `## Worker Results`.
   Record it in `state.md` `## Decisions Log` via `record_decision` on each append so it survives compaction.
   **Phase 4.5 only** — the standalone `/review-pr` drain (`review-heal` skill) has no Context-Keeper and no
   advisory carriage; giving it one is a follow-up item (00 §"Follow-ups"), and item 02 §9's reviewer clause
   is presence-scoped so the drain is unaffected until then.
6. **Consumer — `skills/self-heal-advisory/SKILL.md`** new step **1g "Deviations advisory (worker- and
   fixer-recorded plan drift — pre-review enrichment, ADVISORY ONLY, fail-safe)"**, sibling to 1c/1e/1f:
   collect every `deviations` entry from `state.md` `## Worker Results` (prefixed by `subtask_id`) plus
   `fixer_deviations` (§5b), bound to the SAME cap Part 1 uses for `brief_conformance` (omitted-count marker
   on truncation — **and the marker must be visible to the reviewer**, because item 02 §9 exempts truncated
   advisories), and thread it into the code-reviewer Task prompt as a **DEVIATIONS ADVISORY** line placed
   directly after BRIEF-CONFORMANCE ADVISORY, included only when non-empty. **Runs on every iteration**, not
   only the first (fixer entries arrive per iteration). Skip silently (empty) when: no `state.md`, no
   `## Worker Results`, zero entries. `record_decision(phase: SELF_HEAL, decision: "deviations_advisory:
   {non-empty | empty}", …)` on every path. Contract, stated verbatim in the step: fed to the REVIEW lens
   only, never to workers/fixers as an instruction; NEVER changes `heal_decision`, adds NO gate and NO schema
   field; **like 1f and unlike 1c/1e, the reviewer's response IS ordinary findings** — one `category: new`
   finding per deviation that contradicts an acceptance criterion or an `## Outcomes Rubric` bullet (quoting
   both), through the existing `CODE_REVIEW_RESULT` gate and fix selection. A deviation that is merely
   *unexpected* is not a finding — the question is "does this break a stated criterion?", not "would I have
   done it differently?".
7. **Reviewer prompt mirror — `agents/code-reviewer.md`** Self-heal lens paragraph: add `deviations` to the
   advisory inputs with the one-line question above and the `other:` reading for unprefixed entries.
   `scripts/check-command-sync.sh` does not cover this prose (memory `agent-command-mirror-drift-on-fixes`) —
   a consistency read is the gate.
8. **Docs:** `docs/ARCHITECTURE_CONTRACTS.md` Worker row mentions the field; `docs/POINTER_AUDIT.md` gains no
   row (bounded summary derived from state.md, same transport class as `brief_conformance`); `CHANGELOG.md`
   one paragraph; version bump per `release-surfaces-readme-claude-md-no-longer-bump`.
9. **Tests:** the validator's test file (read the tree — `test-validate-worker-result.sh` or wherever rules
   1–9 are exercised): absent → accepted; `[]` → accepted; four prefixed entries → accepted; an unprefixed
   entry → accepted; `null`, non-array, `[""]`, 13 entries, a 201-char entry → rejected with the rule-10
   message. **Mutation control:** delete the length check → the 201-char case must fail. Seam test asserting
   `self-heal-advisory/SKILL.md` contains step 1g, the `DEVIATIONS ADVISORY` token inside the code-reviewer
   Task prompt block, the per-iteration wording, and `fixer_deviations` — mirror
   `loomwright/scripts/test-brief-conformance-seam.sh`'s shape.

## Non-goals
No change to `EXECUTE_RESULT`, `CODE_REVIEW_RESULT`, `heal_decision`, `--heal-iterations`, or the completion
tail. Not fed to the rubric-grader. Not a gate: a worker that records zero deviations is not penalised and one
that records twelve is not blocked. No `/dreaming` consumer in this item (the `## deviations` heading makes one
possible; a `test:` entry recurring across runs is the obvious future LESSON candidate — note as deferred in
the changelog paragraph, do not build). No attempt to prove sequence (diagnosis-before-fix) — see 02 §8.

## Acceptance criteria
- `validate-worker-result.py` accepts a v2 block with no `deviations`, with `deviations: []`, with
  `["plan: skipped migration down-direction — brief did not ask; flagged open", "test: audit-log format —
  assertion wrong: asserted the pre-change format", "skipped the migration"]`; rejects `null`, `"plan: x"`,
  `[""]`, 13 entries, and a 201-char entry, each with a message naming rule 10 — as exercised by the test
  suite (runtime consequence of a rejection = the existing SubagentStop validator hook's behaviour, unchanged
  by this item).
- `docs/RESULT_SCHEMAS.md` §FIX_RESULT lists `deviations` with the same shape/bound; the Phase 4.5 fix-task
  spawn prompt's output shape includes it.
- `scripts/check-contract-parity.sh` passes with `deviations` in the WORKER_RESULT row and FAILS if the row is
  reverted while `RESULT_SCHEMAS.md` still lists the field (one-off negation check).
- `agents/context-keeper.md` `record_worker_result` lists `deviations`; `skills/state-management/SKILL.md`
  `## Worker Results` template renders it; both Supervisor record sites and Execute Manager's name it.
- `skills/self-heal-advisory/SKILL.md` step 1g exists, runs per iteration, reads `fixer_deviations`, places
  `DEVIATIONS ADVISORY` directly after `BRIEF-CONFORMANCE ADVISORY`, surfaces the truncation marker, and states
  all three contract clauses.
- `agents/worker.md` output block carries the field; §"deviations" names the four kinds, the bound, and the
  `.worker-summary.md` echo rule with omit-when-empty.
- `scripts/check-token-budget.sh` passes with the worker raise recorded in `prompt-token-budgets.json` and the
  ARCHITECTURE_CONTRACTS raise-log row.
- `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` still resolves to exactly the
  five surfaces CLAUDE.md enumerates.
- Full `loomwright/scripts/test-*.sh` loop + root `scripts/check-*.sh` green locally before push.

## Verified premises (re-check before starting; each was read on 2026-09-21)
- `docs/RESULT_SCHEMAS.md` §WORKER_RESULT `out_of_lane` field comment + validation paragraph — the template;
  §FIX_RESULT exists (two YAML shapes) and has no `deviations`.
- `scripts/validate-worker-result.py` docstring rule (9) — numbering ends at 9.
- `scripts/check-contract-parity.sh` `worker|worker.md|WORKER_RESULT|schema_version,…,out_of_lane`.
- `agents/context-keeper.md` `record_worker_result` row lists `out_of_lane` in its result object;
  `skills/state-management/SKILL.md` §"Worker Results" is a fixed template.
- `agents/supervisor.md` — two record sites ("Record result via Context-Keeper — including the worker's
  `out_of_lane`": Single-Agent step and the `--sequential` path).
- `skills/self-heal-advisory/SKILL.md` steps 1c/1e/1f; the code-reviewer Task spawn; zero occurrences of
  `record_worker_result` (fixers bypass Context-Keeper).
- `agents/worker.md` `memory_candidates` → `.worker-summary.md` echo rule; output-block line.
- `bash scripts/check-token-budget.sh` → `worker 5876 5905 OK 29 headroom`.
- `scripts/result_block_parser.py` `emit()` — `{"ok": false, "reason"}` on stdout, exit ALWAYS 0, hook wired
  with `|| true`: the validator's decision is stdout-only.
