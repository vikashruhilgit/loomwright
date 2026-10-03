# Token Economy Plan — 2026-07-14 (Opus 4.7+ tokenizer inflation)

Master overview for the 5 work items in `.supervisor/requirements/token-economy/`.
(2026-07-16: 04 REWRITTEN — graph path dropped per prior negative finding; now
orientation memos + owned flat repo-map, graphify optional. 05 ADDED — pointers-not-
payloads, shared cross-agent stable prefix, async model routing. 01 executed as PR #100.)
Motivation: Opus 4.7-family tokenizers produce ~1×–1.35× the tokens of pre-4.7 models
for the same text; orchestration runs spawning 5–14 agents amplify that per spawn.

**This file is the overview only — do NOT feed it to /automate.** The per-item
requirement files live in the `token-economy/` subfolder, one item per file, each
self-contained (goal, evidence, scope, invariants, acceptance criteria, test plan).

## Execution order & batching

| # | File | Priority | Size | Depends on |
|---|------|----------|------|-----------|
| 01 | 01-token-ledger-and-cache-audit.md | P0 | M | — |
| 02 | 02-token-budget-ci-gate.md | P0 | M | — (can parallel 01) |
| 03 | 03-sdk-runner-token-levers.md | P1 | M | — (can parallel 01/02; quarantine-safe) |
| 04 | 04-orientation-memos-and-repo-map.md | P1 | L | **01 merged** (JSONL `orientation_source` rides the ledger) |
| 05 | 05-pointers-shared-prefix-batch-routing.md | P1 | M | **01 merged** (cache-read share delta measured via ledger) |
| 06 | 06-model-router-gate.md | P1 | L | **01 + 03 merged** (token_usage + ledger feed the analyzer); best after 04/05 |

**Sequencing rule:** 01 (PR #100) before 04 and 05 is hard — both attribute savings via
the ledger path 01 introduced. 02 and 03 are independent of each other and of 01.

Suggested batches:
- Batch A: merge PR #100 (job 01 — already executed).
- Batch B: `02` and/or `03` in any order (parallel OK).
- Batch C: `05` then `04` (05 is smaller and its shared-prefix CI check should exist
  before 04 edits agent prompt openings) — after 01 is on the base branch.

## What each job actually buys

| Job | Nature | Guaranteed win | Conditional / later win |
|-----|--------|----------------|-------------------------|
| 01 | Measure + spawn-contract reorder | Ledger + cache-prefix discipline; honest proxy if usage absent | Real $/token numbers only if SubagentStop (or transcript) carries usage |
| 02 | CI ratchet on prompt inventory | Stops future agent/skill prompt bloat | Does **not** measure tokenizer inflation (`bytes/4` ≠ Anthropic tokens) |
| 03 | SDK spike levers | Opt-in path gets effort / task_budget / context editing + metric | Zero effect on default path until eval GO + graduation |
| 04 | Orientation memos (learned map) + owned flat repo-map; graphify optional | Fail-safe-identical when nothing available; zero third-party deps; advances learning-loop Phase 5 | Compounding: cost per run decreases as memos accumulate |
| 05 | Pointers-not-payloads + shared byte-identical prefix + async model routing | Thinner transcripts; cache reads on SAME-ROLE respawns (tools render first — cross-agent reuse is structurally zero); inventory dedup for 02 | Batch-API downpricing (roadmap note only — needs API-key runtime) |

## Cross-cutting constraints (apply to every item)

- **Bimodal failure:** emitters fail SAFE / exit 0; CI gates fail CLOSED. Never invert.
- **Counts UNCHANGED** (14 agents / 21 commands / 41 skills / 22 hooks) unless an item
  explicitly documents a count change and updates all doc-currency surfaces.
- **Additive JSONL / schemas only** — no `schema_version` bump; old readers fail-safe-skip.
- **Description anti-rebloat:** plugin.json / marketplace.json description version
  string updated in place; never append.
- **Minor version bump** + CHANGELOG for each landed item (re-verify CURRENT version at
  execution time).
- **Proxy honesty:** any non-API token estimate must be labeled proxy everywhere surfaced.
- **Doc-currency:** `check-doc-currency.sh`, `check-skills-index-sync.sh`,
  `validate-version.sh` (and peers named in each item) pass before merge.

## Locked product calls (do not re-open mid-implementation)

1. **01 fallback policy** — If SubagentStop lacks usage fields: ship a clearly labeled
   proxy (e.g. transcript-size) + a documented gap note in insights and the PR. Do not
   block 01 on live Anthropic usage. Do not present proxy figures as exact tokens.
2. **02 measures inventory, not inflation** — The gate is a prompt-weight ratchet.
   Tokenizer family cost is environmental context for why the ratchet matters now.
3. **03 worker effort default** — `medium` for workers on mechanical subtasks; reviewers
   higher (table in runner config). Override path stays config-driven.
4. **04 injection bound** — Default ≤3k chars for the orientation block (memos or
   repo-map inject); raise only in the same PR with a one-line justification; keep
   advisory + fail-safe-skip. Graph/bridge tier is DROPPED (prior negative finding) —
   graphify is enrichment-if-present only, never a dependency.
5. **05 byte-identity + honest cache claim** — The shared cross-agent prefix is
   enforced byte-identical by a fail-CLOSED CI check. Its value is consistency +
   inventory dedup; the CACHE win belongs to same-role respawns only (tools render
   before system, so different agent types diverge at position 0 — never claim
   cross-agent cache reuse without ledger evidence). Batch API stays a roadmap note,
   not code, on the subscription runtime.
6. **04 staleness provenance** — Every memo header carries `written_at` + head-commit
   SHA; the reader annotates/demotes stale memos via a bounded git check (git error ⇒
   fresh-unknown, never block). A stale memo is never silently dropped.
7. **06 router asymmetry** — Auto-ESCALATE is mandated (fail-closed toward the
   stronger model; valve trigger ≥3 FAILs in last 20 per class, one-directional);
   auto-DEMOTE and Haiku routing are propose-only future work. Launch table: trivial
   Sonnet/low · standard Sonnet/medium · hard inherit/high; reviewer one tier above
   worker with a Sonnet floor; Phase 4.5 holistic reviewer stays inherit. `--cheap`
   untouched in 06, but precedence locked: explicit flag > router table > default
   (human opt-in may go below the router floor by design). Effort column applies to
   the sdk-runner arm only unless per-spawn effort is verified on the main path.
   Valve reads only a rolling, tail-bounded `routing-history.jsonl` — never the full
   logs dir.

## Out of scope for the whole package

Shrinking existing agent prompts (diet), graduating the SDK runner, running
FABLE_PARITY_EVAL, building/refreshing graphs, langfuse A/B, making the graph required,
live `count_tokens` in CI, changing heal/gate shapes or never-merge invariants.
