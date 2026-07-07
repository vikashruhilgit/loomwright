# SDK Runner Spike — Fable-parity Phase 3 port (quarantined)

**Status:** spiked (v15.8.0) — **provisional GO/NO-GO** below; live token/latency comparison PENDING
**Date:** 2026-07-07
**Provenance:** Fable-parity job (review-remediation item 09; roadmap item 11 was `DEFERRED — no SDK rewrite`).
Artifact under test: the quarantined TypeScript runner at `loomwright/sdk-spike/` (uncounted — not an
agent, command, skill, or hook; referenced ONLY by the opt-in `--sdk-runner` seam below, default OFF
with `dist/` gitignored so nothing resolves until a one-time build — no default/always-on path
reaches it) plus the opt-in, fail-closed
`--sdk-runner` Supervisor seam (`commands/supervisor.md` Parameters table, `agents/supervisor.md`
Phase 3 §"`--sdk-runner` branch", `skills/supervisor-config/SKILL.md` step 2.8). Sibling records:
`FABLE_PARITY_EVAL.md` (the pre-registered decision rule that gates graduation),
`ADVISORY_LOOP_EVAL.md` (the pre-register-then-run precedent), `NORTH_STAR_DIRECTION.md`.

---

## Question

Can Execute Manager's Phase 3 poll loop — the plugin's most token-hungry prompt-driven control flow
(spawn workers into worktrees, poll `TaskOutput`, review each completion, unblock dependents, emit
`EXECUTE_RESULT`) — be ported to deterministic code via `@anthropic-ai/claude-agent-sdk` with
schema-forced worker/reviewer results, WITHOUT losing the contracts the prompt-based loop enforces
(WORKER_RESULT v2 outputs gate, CODE_REVIEW_RESULT v3 review gate, worktree isolation,
fail-closed error handling)? And is the result cheaper/faster enough to justify a v16 runner?

## Verified SDK capability matrix (doc-verified 2026-07-07 via claude-code-guide, NOT memory)

| # | Capability | Status | Mechanism |
|---|---|---|---|
| 1 | Programmatic subagent spawn, concurrent | SUPPORTED | `agents` dict of AgentDefinition in ClaudeAgentOptions; parent gets final message; https://code.claude.com/docs/en/agent-sdk/subagents.md |
| 2 | Schema-forced structured output | SUPPORTED | `output_format: {type:"json_schema", schema}` per `query()` (top-level result; per-worker schemas ⇒ run one query() per worker/reviewer); retries + `error_max_structured_output_retries`; https://code.claude.com/docs/en/agent-sdk/structured-outputs.md |
| 3 | Session streaming + resume | SUPPORTED | `resume: sessionId`; async-generator streaming; subagent transcripts persist |
| 4 | Hook interop | PARTIAL | SDK `hooks` option (callbacks, PreToolUse/SubagentStop/etc.); settings hooks fire iff `settingSources` includes `"project"`; **plugin hooks.json firing for SDK-spawned workers = NEEDS VERIFICATION — record as spike finding, not assumed** |
| 5 | TS vs Python maturity | NEEDS VERIFICATION | Docs treat both equally; TS bundles the CC binary → **pick TypeScript, reason recorded** |
| 6 | Per-agent model + effort | SUPPORTED | AgentDefinition `model` (incl. `inherit`) + `effort` (`low..max`) |
| 7 | Worktree/sandbox isolation | PARTIAL | No native sandbox; SDK runs in cwd — external `git worktree` per worker (matches our existing design); per-query `cwd` |

## Parity matrix

### What ported cleanly (dry-run-proven in `sdk-spike/`, self-test 21/21)

| Prompt-loop element | Port | Evidence |
|---|---|---|
| Supervisor-Ready Brief parsing (`## Subtask Structure` table + `### Subtask contracts` YAML `provides`/`requires`) | Tolerant line/regex parser in `src/runner.ts` — deterministic, no LLM parse step | `test/self-test.sh` cases against `test/fixtures/mini-brief.md` |
| Poll loop → `requires`-driven wave scheduling | LAUNCHABLE = all `requires` producers completed; a Promise pool runs up to `--max-workers` concurrent lanes and launches newly unblocked subtasks per wave — the prompt-driven `TaskOutput` polling is replaced by in-code `Promise.all` (capability row 1, https://code.claude.com/docs/en/agent-sdk/subagents.md, verified 2026-07-07) | `sdk-spike/README.md` §"What it does" step 2 |
| Per-worker / per-reviewer `query()` with schema-forced results | One `query()` per role instance, `output_format: json_schema` derived from **WORKER_RESULT schema_version 2** and **CODE_REVIEW_RESULT schema_version 3** field shapes (`docs/RESULT_SCHEMAS.md`); schema_version preserved; the v12 outputs gate is mirrored (`status: partial` / non-empty `outputs_gap` never proceeds to review) (capability row 2, https://code.claude.com/docs/en/agent-sdk/structured-outputs.md, verified 2026-07-07) | `src/schemas.ts` + fixtures in `src/dry-run-fixtures/` |
| Worktree lifecycle with commit-before-remove | One `git worktree add -b sdk-spike/subtask-<n>` per launchable subtask; per-query `cwd` points the worker at its worktree (capability row 7, verified 2026-07-07); on completion the runner commits inside the worktree BEFORE removal (FINALIZE-step-2 mirror of `skills/async-orchestration/SKILL.md` Part 2), so branches carry the work; stale `sdk-spike/subtask-<n>` branches fail closed | `sdk-spike/README.md` §"What it does" steps 3 + 6 |
| Fail-closed structured-output handling | `error_max_structured_output_retries`, any error subtype, a missing structured payload, or a payload failing local re-validation ⇒ the subtask lands in `subtasks_failed`; nothing is fabricated | `sdk-spike/README.md` §"Fail-closed"; self-test asserts the degraded paths |
| EXECUTE_RESULT-equivalent output | JSON block with `schema_version: 1` field shapes from `docs/RESULT_SCHEMAS.md` §EXECUTE_RESULT (+ a spike-local `mode` field), consumed by the `--sdk-runner` seam exactly as if it came from Execute Manager | dry-run output; `commands/supervisor.md` `--sdk-runner` row |

### What the SDK cannot do, or does differently

| Gap | Detail |
|---|---|
| Plugin `hooks.json` firing for SDK-spawned workers — **NEEDS VERIFICATION** | The SDK has its own `hooks` option (code callbacks) and settings hooks fire iff `settingSources` includes `"project"` (capability row 4, https://code.claude.com/docs/en/agent-sdk/subagents.md, verified 2026-07-07); whether the plugin's SubagentStop validators fire for `query()`-spawned workers is unverified. **Mitigation shipped:** the runner self-validates every worker/reviewer payload against the local schema regardless — the hook layer is redundant on this path, not load-bearing. Recorded as a spike finding, not assumed either way. |
| Skills preload & agent memory for SDK-defined agents — **NEEDS VERIFICATION** | The plugin's `skills:` frontmatter preload and `memory: project` persistence are Claude Code plugin-agent features; nothing in the SDK docs verified 2026-07-07 (subagents.md / structured-outputs.md) states that AgentDefinition-declared agents receive either. The spike's workers run without preloaded skills or persistent memory; a v16 runner would need to inline skill content into prompts (workaround exists) and re-verify memory. Marked needs-verification, not confirmed-absent. |
| No native sandbox | SDK runs in `cwd` (capability row 7, verified 2026-07-07). Isolation comes from external `git worktree` per worker + per-query `cwd` — the same design the prompt loop already uses, so this is parity-by-construction, not a regression. |
| Structured output is per-`query()` top-level | The `output_format` schema applies to the query's single top-level result (capability row 2, https://code.claude.com/docs/en/agent-sdk/structured-outputs.md, verified 2026-07-07), so per-worker schemas force **one `query()` per worker/reviewer** — no multiplexing several schema-forced roles inside one session. Cost implication measured by the live comparison below. |
| Exact TS option spellings | `output_format` vs `outputFormat`, top-level `effort`, the structured-payload field on the result message — coded defensively with `// NEEDS VERIFICATION vs docs` markers in `src/runner.ts` (capability row 5). |
| json_schema strictness semantics — **NEEDS VERIFICATION** | Does the SDK require all-properties-required under `additionalProperties: false` (as OpenAI strict mode canonically does)? `src/schemas.ts` now adopts the strict-mode-safe posture (every declared property required, previously-optional ones nullable), which is valid under either semantics — but the SDK's actual enforcement is unverified; a rejecting backend would have exhausted structured-output retries on every live `query()` while the offline suite stayed green. |
| Spike simplifications (not SDK limits) | No fix-worker retry loop after a non-PASS review, no Context-Keeper, no tool-call budget / EXECUTE_CHECKPOINT, no Step 2a dependency materialization (producer branches are not merged into dependent worktrees), no branch merge/delete (FINALIZE's job, per the seam's documented delta). |

### Residual known divergences from the real protocol (review findings, subtask-1 review)

1. **Clean-worktree false-success WARNS, not FAILS:** a worker that reports `status: completed` but
   leaves its worktree clean (nothing to commit) gets a warning while the subtask still counts as
   completed — the prompt loop's reviewer would see an empty diff and fail it. **Backstop:** the
   `--sdk-runner` seam's FINALIZE delta (`commands/supervisor.md` `--sdk-runner` row, step (a))
   verifies each `merge_order` branch is AHEAD of the feature branch before merging, so an empty
   branch cannot silently merge — the divergence is bounded to a late (FINALIZE-time) rather than
   early (review-time) failure.
2. **Failed-before-commit worktrees are removed:** a subtask that fails before its commit point has
   its worktree removed on exit, discarding partial work the real protocol would leave on disk for
   inspection/retry. Acceptable for a spike (failed subtasks are re-run from scratch); a v16 runner
   should keep failed worktrees or commit-then-tag them.
3. **Dependents cannot SEE producer output (spawn-order only, not visibility):** the `requires`
   scheduler delays a dependent until its producers complete, but the dependent's worktree still
   branches from the **feature branch** — producer commits live on `sdk-spike/subtask-<n>` branches
   that are never merged in (no Step 2a dependency materialization). A subtask with a REAL
   cross-subtask file dependency will not find the producer's files on disk in live mode. The
   eval protocol (`FABLE_PARITY_EVAL.md`) is required to include at least one such requirement so
   this gap surfaces in the measured comparison rather than staying theoretical.

**Live-path coverage honesty:** the live git lifecycle — the stale-branch abort, the
`commitWorktree` clean-worktree skip/warn, the `removeWorktree` error path, and the
blocked-forever sweep — is **source-verified only** (self-test greps `src/runner.ts`; no executing
test drives these branches against a real repo or the live SDK). The eval must NOT treat these
paths as behaviorally proven; arm-3 runs are their first live exercise.

## TypeScript choice (capability row 5)

TypeScript, because `@anthropic-ai/claude-agent-sdk` **bundles the Claude Code binary** — one
`npm install` yields a runnable agent runtime with no separate CC install/version-skew problem,
which the Python SDK does not provide (docs treat the SDKs as feature-equivalent otherwise;
NEEDS VERIFICATION marker retained on maturity parity, verified 2026-07-07). The SDK is pinned to
**`^0.3.202`** — the version the spike was built and dry-run-verified against — with
`package-lock.json` committed for reproducible installs (`sdk-spike/README.md` §"Install / run").

## Token/latency comparison

**Dry-run (measured 2026-07-07, this machine, node v22.14.0):** `node dist/runner.js --brief
test/fixtures/mini-brief.md --dry-run` completes the full 2-subtask control flow (parse → schedule →
2 workers → 2 reviews → EXECUTE_RESULT) in **~0.03s wall, 0 tokens, 0 API calls**. This measures
only the orchestration shell — it proves the control flow costs nothing when moved to code, but
says nothing about end-to-end run cost, which is dominated by the worker/reviewer LLM calls both
designs share.

**LIVE comparison — PENDING** (deferred per the brief's MVP scoping note, risk R1; same
pre-register-then-run pattern as `ADVISORY_LOOP_EVAL.md`). Exact instructions:

1. Build: `cd loomwright/sdk-spike && npm install --no-audit --no-fund && npm run build`.
2. Pick ONE small real brief (2–3 subtasks) from `.supervisor/jobs/done/` (or author a scratch one).
3. Arm A (prompt loop): run `/supervisor job: <brief>` on a scratch branch; record from the session
   JSONL + `SUPERVISOR_RESULT`: wall-clock Phase 3 duration, total tokens (session `usage`), and
   the Execute Manager's tool-call count.
4. Arm B (SDK runner): same brief, same base commit, scratch branch; run `/supervisor --sdk-runner
   job: <brief>`; record wall-clock Phase 3 duration and tokens (SDK result messages carry `usage`).
5. Record both rows in `FABLE_PARITY_EVAL.md`'s results table (its arm-2 vs arm-3 comparison
   subsumes this measurement); scratch branches only, NO PRs to main.

## Provisional GO/NO-GO

**Provisional GO — conditional on `FABLE_PARITY_EVAL.md` arm 3 winning under its pre-registered
decision rule; otherwise CUT.**

Honest reading of the parity matrix:

- **Capability parity is real.** Every load-bearing contract of the Phase 3 loop — brief parsing,
  dependency-driven scheduling, schema-forced WORKER_RESULT v2 / CODE_REVIEW_RESULT v3 (versions
  preserved), worktree isolation with commit-before-remove, fail-closed error handling,
  EXECUTE_RESULT shape — ported to ~500 lines of deterministic TypeScript, dry-run-proven offline
  (self-test 21/21). Nothing in the port required weakening a contract.
- **The gaps are known and bounded, not disqualifying:** two NEEDS-VERIFICATION items (hooks.json
  firing — mitigated by runner self-validation; skills preload/agent memory — workaroundable by
  prompt inlining) and two residual divergences (§above), one of which FINALIZE already backstops.
- **But capability parity is not the bar — measured benefit is.** The north-star discipline is
  "prove the loop works — or cut it" (`NORTH_STAR_DIRECTION.md`: earn every bit of surface area
  with evidence). The runner's claimed win (deterministic control flow, fewer orchestration tokens)
  is exactly what the dry-run cannot prove end-to-end, because real-run cost is dominated by the
  worker/reviewer calls both designs share, and the one-query-per-role constraint may claw back
  some of the orchestration saving.

**Therefore:** the SDK runner graduates to a v16 runner ONLY if `FABLE_PARITY_EVAL.md` arm 3
(Loomwright + `--sdk-runner` + `--multi-voter-heal`) beats arm 2 (Loomwright default) on
post-merge defects or review rounds without >1.5× token cost, per that file's pre-committed
decision rule. If it does not, the spike is cut: `sdk-spike/` is deleted and the `--sdk-runner`
seam removed — quarantine makes the cut a two-path revert. No third outcome.
