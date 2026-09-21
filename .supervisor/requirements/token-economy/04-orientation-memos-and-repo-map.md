# 04 — Orientation memos + owned flat repo-map (replaces "graph as token compressor")

> REWRITTEN 2026-07-16. The earlier draft depended on the maintainer's personal graphify
> skill (third-party from a plugin user's perspective) and on the knowledge-graph path,
> which prior findings judged weak (graphs go stale, are gitignored/absent in worktrees,
> and agents don't ask graph-shaped questions — agentic search won industry-wide for the
> same reason). Surviving insight from docs/SPIKES/CODE_GRAPH_OWNERSHIP.md: the measured
> 289×–1273× compression came from the FLAT repo-map tier (tree-sitter signatures +
> ranking), not the graph superstructure. New design: a LEARNED map (orientation memos
> that accumulate across runs) as primary, an owned flat repo-map script as cold-start
> secondary, graphify demoted to optional enrichment-if-present.

## Goal
Agents orient from ~1–2k tokens of accumulated knowledge instead of tens of thousands of
tokens of raw exploration: Launch Pad Phase 2 and Orchestrator read per-area orientation
memos first (written/updated by prior runs), fall back to a bundled flat repo-map on
cold-start repos, and only then do raw grep/read — scoped to the areas the task touches.
Token savings attributable via the job-01 ledger. Cost per run should DECREASE over the
life of a repo (memos appreciate; a graph depreciates).

## Evidence
- Agentic search (grep/glob) beat index/RAG approaches in Claude Code itself; the gap it
  leaves is "where to look" — which memos supply for ~1k tokens.
- The plugin already owns every substrate memos need: `.agent/rules/` committed store
  (v14.51.0), lessons/dreaming loop, per-agent `memory: project` dirs, and the
  advisory-only brain-context contract (`skills/brain-context/SKILL.md` — never gates,
  fail-safe-skip). This job consolidates the READ path — which is learning-loop Phase 5
  ("brain read-path consolidation", pending) — so one job advances two roadmap items.
- CODE_GRAPH_OWNERSHIP spike: repo-map tier measured across 4 repos / 4 languages —
  reuse its approach/prototype for the bundled script; do NOT port the graph/bridge tier.
- `graph_context_used`-style attribution rides job 01's ledger (PR #100) — reuse that
  JSONL namespace with an `orientation_source: memos|repo_map|graphify|none` field.

## Scope
1. **Memo substrate (primary)**: define a committed, human-reviewable location for
   per-area orientation memos (prefer extending `.agent/rules/` conventions or a sibling
   `.agent/orientation/` — decide at execution by reading the rules skill's schema; one
   file per area, one-line summary header, hard size cap per memo, e.g. ≤1k chars).
   Reader: a fail-safe `read-orientation.sh` (or extension of `read-rules.sh` if the
   schema fits) that emits a bounded (≤3k chars total) orientation block; EMPTY output
   when nothing exists.
   **Staleness provenance (required — memos go stale like graphs, and a stale memo is
   prose an agent will TRUST, not an index it ignores):** each memo header carries
   `written_at` + the head commit SHA at write time. The reader runs a cheap freshness
   check per memo (e.g. `git log --oneline <sha>.. -- <area paths> | head` — bounded,
   fail-safe: any git error ⇒ treat as fresh-unknown, never block) and ANNOTATES stale
   memos in the emitted block (e.g. `[stale — area changed since 2026-07-01, verify
   before trusting]`) or demotes them below fresh ones. Advisory only; a stale memo is
   never silently dropped (it may still be mostly right) and never blocks.
2. **Write-after-run seam (advisory)**: at Supervisor completion-tail (success only,
   fail-safe, additive), the run may propose memo updates for areas it touched.
   **Git-safety (locked):** the completion-tail runs AFTER FINALIZE creates the PR, so
   any direct write to the committed store would leave uncommitted edits in the main
   checkout — which a concurrent /review-pr or autonomous loop will `git add -A` into
   ITS commit (this exact incident is on record). Therefore the automatic path writes
   ONLY to a gitignored proposals location (`.supervisor/orientation-proposals/`);
   the committed store (`.agent/orientation/`) is updated exclusively through the
   per-item-approval flow (dreaming-style accept, which commits deliberately), with
   the same REJECT-hostile-content + path-containment discipline as add-rule.sh.
   Never blocks completion; failure to write is silent.
3. **Read-at-orientation seams**: Launch Pad Phase 2 and Orchestrator planning entry get
   an advisory "memos-first" step: read the orientation block; if EMPTY and the repo-map
   script is available, generate/read the flat map; scope subsequent raw exploration to
   task-relevant areas. Absent everything ⇒ byte-equivalent to today.
4. **Owned flat repo-map (secondary, cold-start)**: `scripts/build-repo-map.sh` —
   bundled, dependency-light. Tier A: tree-sitter-based signatures + ranking IF the
   toolchain is present (probe, never install); Tier B zero-dep fallback: directory
   skeleton + exported-symbol grep. Output capped (~2k tokens proxy), regenerated on
   demand, written under `.supervisor/` (not committed). Reuse the spike's prototype
   where licensing/shape allows; otherwise reimplement the Tier B fallback only and
   record Tier A as follow-up.
5. **brain-context SKILL.md**: rewrite the enrichment ladder as
   memos → repo-map → graphify-if-present → nothing; keep the never-gates contract
   authoritative; document the ≤3k-char injection bound (raise only with in-PR
   justification per the overview's locked call #4, which now applies to the memo block).
6. **Ledger attribution**: additive `orientation_source` field on job-01's session JSONL
   path (no second emitter; same namespace).
7. Command↔agent mirror sweep in the same commit (memory: agent-command mirror drift).

## Constraints / invariants
- Advisory only, all three tiers: missing/broken/oversized memos, map, or graph ⇒
  today's behavior. No new gates; no decision changes; no blocking reads.
- Memos are DATA, not instructions: the reader must treat memo content as context; the
  writer must enforce the same hostile-content REJECT categories as add-rule.sh; unsafe
  or over-cap memos are skipped per-object (nullable-required lesson: presence-check
  fields, test missing-key vs explicit-null).
- No network, no package installs in any script; probe-and-degrade only.
- Counts: `build-repo-map.sh` + reader are scripts (uncounted); if a new skill or
  command is added instead, update ALL doc-currency surfaces in the same change.
- Hard precondition: job 01 (PR #100) merged into the base branch — attribution rides
  its JSONL path. Do not invent a parallel ledger.
- Prompt-is-program discipline: dynamic trace required across states
  (memos present / stale memo / empty / hostile-content memo / map-present-no-memos /
  nothing / fresh-worktree).
- Minor version bump + CHANGELOG; description version string in place.

## Acceptance criteria
- [ ] Launch Pad + Orchestrator prompts contain the advisory memos-first step with an
      explicit fail-safe-skip branch (nothing available ⇒ today's behavior, verbatim).
- [ ] Reader emits a bounded block; over-cap and hostile-content memos are skipped
      per-object with a test proving it.
- [ ] Memo headers carry `written_at` + head-commit SHA; the reader annotates/demotes
      stale memos (area changed since the SHA) with a fixture test covering fresh,
      stale, and git-error (fresh-unknown) cases; staleness never blocks.
- [ ] Write-after-run seam is success-only, fail-safe, and never blocks the
      completion-tail (test or trace proving a write failure is silent).
- [ ] Automatic writes land ONLY in gitignored `.supervisor/orientation-proposals/`;
      the committed store changes only via the approval flow (trace proving no
      uncommitted working-tree edits to committed paths after a run).
- [ ] `build-repo-map.sh` Tier B works with zero deps on a bare macOS/Linux box; Tier A
      degrades to Tier B when tree-sitter tooling is absent (probe test).
- [ ] brain-context SKILL.md documents the memos → map → graphify → none ladder and
      remains the authority for the never-gates contract.
- [ ] `orientation_source` lands additively on the job-01 JSONL path.
- [ ] Dynamic trace table (seven states above) in the PR description.
- [ ] check-doc-currency.sh, check-command-sync.sh, check-skills-index-sync.sh,
      validate-version.sh pass; new self-tests pass offline (bash-3.2 + Linux-CI safe —
      no GNU-only stat/sed/date flags).

## Test plan
Fixture-driven self-tests for reader, writer REJECT path, and repo-map tiers (offline).
Dynamic trace table in the PR. If a live run on a memo-seeded repo is feasible, paste
the Launch Pad Context Read excerpt showing memos-first orientation; else state pending.

## Out of scope
Porting the graph/bridge tier, requiring graphify, langfuse A/B, learning-loop Phase 6
(brain write-back beyond the memo seam), committing repo-map output, prompt diets.

## Status: done
- completed: 2026-07-20
- pr: https://github.com/vikashruhilgit/loomwright/pull/103
