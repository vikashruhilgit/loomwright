# loomwright sdk-spike (QUARANTINED)

A minimal TypeScript spike that ports **ONLY Execute Manager's Phase 3 poll loop**
(`loomwright/agents/execute-manager.md` §"Execution Protocol" Steps 1–5) to code
using `@anthropic-ai/claude-agent-sdk`, with schema-forced worker/reviewer results.

> **Quarantine statement:** this directory is **NOT part of the plugin manifest
> surface**; it is **uncounted** (not an agent, command, skill, or hook) and
> referenced ONLY by the **opt-in `--sdk-runner` Supervisor seam** (default
> OFF; `dist/` is gitignored, so nothing here resolves until a one-time
> `npm install && npm run build`). **No default or always-on path reaches it**,
> and no plugin manifest points here. It exists solely to answer the
> fable-parity spike question recorded in
> `loomwright/docs/SPIKES/SDK_RUNNER_SPIKE.md`.

## CLI contract

```
node dist/runner.js --brief <path> [--dry-run]
```

Full option set:

```
node dist/runner.js --brief <path> [--dry-run] [--dry-run-fixture-set default|fail|review-fail|throw-usage (test-internal)] [--max-workers N] [--model M] [--effort E] [--worker-effort E] [--reviewer-effort E] [--task-budget N] [--branch B]
```

| Flag | Meaning |
|---|---|
| `--brief <path>` | Supervisor-Ready Brief to execute (required). The runner parses its `## Subtask Structure` table and `### Subtask contracts` YAML. |
| `--dry-run` | **No API calls, no worktrees, no git.** Workers/reviewers are replaced by an injected fake that returns canned schema-valid fixtures from `src/dry-run-fixtures/`. Fully offline and deterministic. |
| `--dry-run-fixture-set` | Which fixture set the dry-run fake returns (default `default`). `fail` makes workers return `status: failed` (exercises the worker-failed gate + blocked-forever sweep offline); `review-fail` makes workers succeed and reviewers return `decision: FAIL` (exercises the review-FAIL branch + blocked sweep). Both failure sets exit 1 with the failures in `subtasks_failed`. `throw-usage` is test-internal: the reviewer query throws a `QueryFailedError` carrying synthetic `proxy: true` usage, exercising the fold-back that preserves a failing query's captured spend (exit 1). Note: this is the one deliberate exception to the "dry-run emits zeros" rule — the thrown usage is non-zero synthetic data, labeled `proxy: true`. |
| `--max-workers N` | Concurrent worker cap (default 2) — the in-code equivalent of the poll loop's `max_workers`. |
| `--model M` | Pass-through model for worker/reviewer `query()` calls (default: SDK default / inherit). |
| `--effort E` | Global effort override for **both** roles (`low\|medium\|high\|xhigh\|max`, the SDK `EffortLevel` set at `sdk.d.ts:522`; `Options.effort` typed at `:1620`). Per-role flags win over it. Invalid values **fail closed** (stderr error, exit 2, before any query). |
| `--worker-effort E` | Per-role effort override for worker queries (same value set / fail-closed validation). |
| `--reviewer-effort E` | Per-role effort override for reviewer queries (same value set / fail-closed validation). |
| `--task-budget N` | Opt-in per-**worker**-query token budget, passed as `taskBudget: { total: N }` (`sdk.d.ts:1647-1649`, **@alpha**, beta header `task-budgets-2026-03-13`). The runner enforces the documented **20,000-token minimum** (`N < 20000` fails closed, exit 2, before any query). When unset the field is **omitted entirely** from `Options` (never `null`/`0`). Reviewer queries never get a budget — their output is bounded by the CODE_REVIEW_RESULT schema, so a budget adds mid-review truncation risk without a cost upside. |
| `--branch B` | Feature branch to base worktrees on (default: the brief's `Suggested branch:`, else the current branch). |

Exit codes: `0` all subtasks completed+PASS · `1` one or more subtasks failed/blocked · `2` fatal (bad args — including invalid effort/budget values — unreadable brief, SDK missing in live mode).

### Per-role effort defaults (ROLE_CONFIG)

Effort is resolved via the runner's single `ROLE_CONFIG` table (`src/runner.ts`) —
never hard-coded at the call sites:

| Role | Default effort | Why |
|---|---|---|
| worker | `medium` | Mechanical, schema-bounded implementation subtasks. |
| reviewer | `high` | The higher named level from the same table: review is the spike's only quality gate (no fix-worker retry loop), so it gets deeper reasoning. |

Override precedence (all values fail-closed validated at parse time):
`--worker-effort` / `--reviewer-effort` > `--effort` (both roles) > `ROLE_CONFIG` default.

### Per-subtask token accounting

Each subtask entry in the EXECUTE_RESULT-equivalent block carries an **additive**
`token_usage` object aggregating its worker + reviewer queries, captured from
each query's terminal result message (`SDKResultSuccess` at `sdk.d.ts:4024` —
`usage` / `total_cost_usd` / `num_turns` at `:4037-4042`):

```
"token_usage": {
  "worker":   { "input_tokens", "output_tokens", "cache_creation_input_tokens",
                "cache_read_input_tokens", "total_cost_usd", "num_turns" },
  "reviewer": { ...same shape, or null if that query never ran... },
  "total_tokens": <sum of all four token fields across both roles>,
  "total_cost_usd": <sum across both roles>,
  "proxy": false
}
```

- `total_tokens` is a **volume** figure (cache-read tokens counted 1:1), not a
  cost proxy — cost is `total_cost_usd`.
- `subtasks_completed[]` entries always carry it (both queries ran).
- `subtasks_failed[]` entries carry it **where available** (e.g. worker ran,
  review failed); `null` when no query ran (e.g. the blocked-forever sweep).
- In `--dry-run` the fixtures carry no real usage, so the runner emits **zeros
  with `proxy: true`** — it never invents token counts (mirrors the plugin's
  token-ledger convention of proxy-labeling synthetic numbers).

## What it does

1. **Parse** (Step 1): tolerant line/regex parser for the brief's Subtask Structure
   table + `### Subtask contracts` YAML (`provides`/`requires` with
   `{kind, path, name?, from?}` items).
2. **Schedule** (Steps 2+4): LAUNCHABLE = every `requires` producer already
   completed. Wave-based deterministic scheduling — a Promise pool runs up to
   `--max-workers` subtasks concurrently; when a wave finishes, newly unblocked
   subtasks launch (the "launch newly launchable" branch of the poll loop),
   replacing the prompt-driven `TaskOutput` polling with in-code `Promise.all`.
3. **Worktrees** (Step 2, live mode only): one `git worktree add -b
   sdk-spike/subtask-<n> ../<repo>-sdk-<n> <feature-branch>` per launchable
   subtask — always a deterministic per-subtask branch off the feature branch
   (git refuses to double-checkout the feature branch itself). If
   `sdk-spike/subtask-<n>` already exists from a previous run, the subtask
   **fails with a clear stale-branch error** (merge or `git branch -D` it) —
   no silent fallback.
4. **Workers** (Step 3): ONE `query()` per worker with structured output forced
   to a JSON Schema derived from **WORKER_RESULT schema_version 2**
   (`docs/RESULT_SCHEMAS.md`), `cwd` set to the subtask's worktree. Mirrors the
   real loop's v12 outputs gate: `status: partial` / non-empty `outputs_gap`
   never proceeds to review.
5. **Reviewers** (Step 4): on each worker completion, one reviewer `query()`
   forced to **CODE_REVIEW_RESULT schema_version 3**. Non-PASS = subtask failed
   (spike simplification: no fix-worker retry loop).
6. **Persist + output** (Step 5): after each worker completes (live mode), the
   runner **commits the worker's output inside its worktree** (`git -C <wt>
   add -A && git commit`, skipped when the worktree is clean) so the
   per-subtask branch actually carries the work — mirroring FINALIZE step 2 of
   `skills/async-orchestration/SKILL.md` (work persists on branches, merged
   later). Worktrees are then removed on exit; **branches are KEPT** and
   listed in `merge_order` / `branches` for the caller to merge and delete.
   Finally an **EXECUTE_RESULT-equivalent** JSON block is printed to stdout
   (`schema_version: 1` field shapes from `docs/RESULT_SCHEMAS.md`
   §EXECUTE_RESULT, plus a spike-local `mode` field).

**Fail-closed:** a live `query()` that ends with
`error_max_structured_output_retries` (SDK exhausted its schema retries), any
error subtype, a missing structured payload, or a payload failing local
re-validation throws — the subtask lands in `subtasks_failed`; nothing is
fabricated.

## Install / run

```bash
cd loomwright/sdk-spike
npm install --no-audit --no-fund   # installs @anthropic-ai/claude-agent-sdk + typescript
npm run build                      # tsc -> dist/
node dist/runner.js --brief test/fixtures/mini-brief.md --dry-run   # offline smoke
npm run self-test                  # bash test/self-test.sh
```

`@anthropic-ai/claude-agent-sdk` is pinned to **`^0.3.202`** (the version the
spike was built and dry-run-verified against); `package-lock.json` is committed
for reproducible installs.

The self-test is **offline-safe**: without `node_modules` it SKIPs the compile,
degrades the dry-run to fixture-vs-schema required-key checks (node, jq
fallback), and still asserts the fail-closed handling — it passes with zero
network. `node_modules/` and `dist/` are gitignored locally.

### What the self-test cannot prove

The suite is honest about its reach — the following are **grep/source-asserted
or dry-run-only**, never exercised against the live SDK:

- The live `makeLiveQuery` fail-closed branches (error subtype, missing
  structured payload, payload failing local re-validation) — asserted by
  grepping `src/runner.ts`, not by triggering them.
- The stale-branch abort and the `commitWorktree` clean-worktree warning —
  source-level greps; no live worktree lifecycle runs (these paths shell out
  to git and stay unexercised offline).
- The worker-failed gate, the review-FAIL branch, and the blocked-forever
  sweep ARE now exercised offline (via the `--dry-run-fixture-set fail` /
  `review-fail` failure dry-runs) — but only through the dry-run seam; their
  live-`query()` counterparts remain pending.
- In degraded offline mode (no `node_modules`) the result is **"0 failures"
  with the compile and dry-run SKIPped — not 36 passes**; only a full install
  + build yields the 40/40 run.

## What this proves / what it can't

**Proves (dry-run + doc-verified capability matrix in the brief):**
- The Phase 3 poll loop's control flow (parse → launchable computation →
  concurrent workers → per-completion review → wave unblock → EXECUTE_RESULT)
  ports to ~500 lines of deterministic TypeScript with no prompt-driven polling.
- WORKER_RESULT v2 / CODE_REVIEW_RESULT v3 field shapes express cleanly as
  non-recursive JSON Schemas suitable for the SDK's `json_schema` structured
  output (per-worker schemas ⇒ one `query()` per role instance).
- Worktree isolation composes with the SDK via per-query `cwd` (capability
  matrix row 7 — no native sandbox, external `git worktree`, same as the
  prompt-based design).

**Can't prove (yet) / NEEDS VERIFICATION:**
- **hooks.json firing for SDK-spawned workers = NEEDS VERIFICATION.** The SDK
  has its own `hooks` option (callbacks) and settings hooks fire iff
  `settingSources` includes `"project"` — whether the plugin's
  `hooks/hooks.json` SubagentStop validators fire for workers spawned via
  `query()` is unverified and recorded as a spike finding, not assumed.
- Exact TS SDK option spellings (`output_format` vs `outputFormat`,
  structured-payload field on the result message) — coded defensively with
  `// NEEDS VERIFICATION vs docs` markers in `src/runner.ts`. (Top-level
  `effort` is no longer on this list — it is doc-verified on `Options` at
  `sdk.d.ts:1620`, as is `taskBudget` at `:1647-1649` (@alpha).)
- **Context editing / history pruning: NOT exposed by the pinned SDK version —
  recorded as a gap.** `@anthropic-ai/claude-agent-sdk` 0.3.202 offers no
  per-query context-editing/prune option on `Options`; the closest surfaces are
  the PreCompact/PostCompact hooks, `getContextUsage()`, and settings-level
  autoCompact controls. Per the token-levers job's constraint, the runner does
  NOT hack around this and the SDK pin is unchanged; the lever is documented as
  a gap (no code).
- Live token/latency vs the prompt-based Execute Manager — requires the live
  arm of `loomwright/docs/SPIKES/FABLE_PARITY_EVAL.md`.
- Simplifications vs the real loop: no fix-worker retries, no Context-Keeper,
  no tool-call budget/EXECUTE_CHECKPOINT, and no Step 2a dependency
  materialization (producer branches are not merged into dependent worktrees).
  Concretely: `requires` only delays **spawn order**, not **visibility** — a
  dependent worktree branches from the feature branch and does NOT see producer
  commits, so a subtask with a real cross-subtask file dependency will not find
  the producer's files on disk in live mode.
- Branch lifecycle simplification: the runner commits each worker's output on
  its `sdk-spike/subtask-<n>` branch (so worktree removal never destroys work)
  but does **not** merge or delete branches — merging them in `merge_order`
  into the feature branch and deleting them afterwards is the caller's job
  (the spike stops where the real FINALIZE phase would take over).
