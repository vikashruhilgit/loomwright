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
node dist/runner.js --brief <path> [--dry-run] [--max-workers N] [--model M] [--effort E] [--branch B]
```

| Flag | Meaning |
|---|---|
| `--brief <path>` | Supervisor-Ready Brief to execute (required). The runner parses its `## Subtask Structure` table and `### Subtask contracts` YAML. |
| `--dry-run` | **No API calls, no worktrees, no git.** Workers/reviewers are replaced by an injected fake that returns canned schema-valid fixtures from `src/dry-run-fixtures/`. Fully offline and deterministic. |
| `--max-workers N` | Concurrent worker cap (default 2) — the in-code equivalent of the poll loop's `max_workers`. |
| `--model M` | Pass-through model for worker/reviewer `query()` calls (default: SDK default / inherit). |
| `--effort E` | Pass-through effort (`low..max`) — see NEEDS VERIFICATION note below. |
| `--branch B` | Feature branch to base worktrees on (default: the brief's `Suggested branch:`, else the current branch). |

Exit codes: `0` all subtasks completed+PASS · `1` one or more subtasks failed/blocked · `2` fatal (bad args, unreadable brief, SDK missing in live mode).

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
  source-level greps; no live worktree lifecycle runs.
- In degraded offline mode (no `node_modules`) the result is **"0 failures"
  with the compile and dry-run SKIPped — not 21 passes**; only a full install
  + build yields the 21/21 run.

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
- Exact TS SDK option spellings (`output_format` vs `outputFormat`, top-level
  `effort`, structured-payload field on the result message) — coded
  defensively with `// NEEDS VERIFICATION vs docs` markers in `src/runner.ts`.
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
