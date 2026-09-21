# 05 — Pointers-not-payloads + shared stable prefix + async downpricing

> Added 2026-07-16: captures the remaining levers from the token-economy design
> discussion that jobs 01–04 don't cover: (a) pass file PATHS, not pasted content, in
> spawn prompts and inter-agent handoffs ("send pointers, not payloads"); (b) a shared
> byte-identical instruction prefix across all 14 agents — see the HONEST CACHE
> EXPECTATION below: this does NOT buy cross-agent cache hits; (c) route
> async analysis work (postmortems, insights corpus, dreaming, eval runs) toward
> cheaper meters where the plugin controls the invocation (model routing; Batch API
> noted as future work where an API-key path exists).

## Goal
Spawn prompts and inter-agent handoffs carry references + bounded summaries instead of
pasted bodies; all agent prompts open with one shared, byte-identical guidelines block
ordered before role-specific and volatile content; async analysis surfaces default to
the cheapest adequate model tier.

## Evidence
- **Honest cache expectation (do not overclaim in the PR):** prompt caching is a
  prefix match over the WHOLE rendered request, and `tools` render BEFORE the system
  prompt. Each agent type carries a different `tools:`/`disallowedTools:` frontmatter
  set, so two DIFFERENT agent types diverge at position 0 no matter how byte-identical
  their .md openings are — a shared leading block CANNOT produce cross-agent cache
  reads. Where the cache win is real: SAME-ROLE respawns — N workers in one Phase 3
  wave, repeated reviewer/fix-worker spawns in the heal loop — which already share
  identical agent files; there, job 01's within-contract ordering plus this job's
  volatile-last discipline is what pays. The cross-agent value of the shared block is
  consistency, dedup, and a smaller prompt inventory for job 02's ratchet — frame it
  as that, not as a cache saving.
- **Token-budget gate interplay (plan for it):** adding the shared block to all 14
  agent .md files INCREASES each agent's measured prompt-inventory weight, and
  `check-token-budget.sh` (v15.10.0, fail-CLOSED) will breach on agents with thin
  headroom (initial budgets were measured +~10%). Apply the gate's own raise rule:
  raise affected budgets in the SAME PR (in prompt-token-budgets.json + the mirror)
  with the one-line justification, net of whatever duplicated prose the shared block
  removes. A gate failure here is expected-by-design, not a surprise.
- Job 01 (PR #100, v15.9.0) already reordered spawn contracts stable-prefix-first
  WITHIN each contract; this job extends the idea ACROSS agents (shared leading block)
  and to the payloads themselves (paths not pastes).
- The worker → `.worker-summary.md` → Execute Manager pattern proves the pointer
  pattern works; audit remaining seams that still paste bodies (candidates to verify at
  execution, from the files not memory: brief body in worker spawn prompts, review
  findings handed to fix workers, Phase 4.5 enrichment blocks, handoff/insights inputs).
- Cost profiles already route via `--cheap` and the Haiku rubric-grader — precedent for
  per-role model routing of analysis surfaces.

## Scope
1. **Pointer audit + conversion**: enumerate every Task-spawn prompt and inter-agent
   handoff that pastes >~1k chars of file-backed content (grep the agent/skill .md
   sources — verify from the files, not memory). Convert each to: absolute path +
   ≤200-char summary + explicit "Read only the sections you need" instruction. Keep
   pastes ONLY where the consumer provably needs full content every time (document each
   exception inline).
2. **Shared stable prefix**: extract a common leading block (mission, safety, output
   contract essentials — content that is already duplicated across agent .md files)
   into ONE canonical source; each agent .md opens with it byte-identically (build-time
   include is NOT available for plugin agents — so enforce byte-identity with a CI
   check, e.g. extend check-command-sync.sh conventions or a new
   `check-shared-prefix.sh` + self-test, fail CLOSED). Order per agent: shared block →
   role block → preloaded skills → volatile content.
3. **Async model routing**: for plugin-invoked analysis roles where quality tolerance
   allows (pr-postmortem categorization, dreaming distillation, insights narrative if
   any model call exists — verify which of these actually spawn models today), default
   the spawn to the cheapest adequate tier (haiku/sonnet) via the Cost Profiles table in
   `ARCHITECTURE_CONTRACTS.md` §Cost Profiles (new rows, default documented, override
   flag preserved). Batch API routing is OUT of scope for implementation (plugin runs
   on the Claude Code subscription runtime, not raw API keys) — record it as a
   documented follow-up in the roadmap section of the PR instead of code.
4. **Measurement**: note in the PR how job-01's ledger attributes the change —
   measure the cache-read share delta on SAME-ROLE respawn sequences (Phase 3 waves,
   heal-loop reviewer spawns); do NOT claim cross-agent cache reuse without ledger
   evidence (expected ≈ zero per the honest cache expectation above). Additive
   `shared_prefix: true` marker on the JSONL line if cheap — same namespace discipline
   as job 04's `orientation_source`.

## Constraints / invariants
- Zero semantic change to any agent's behavior contract: pointer conversion and prefix
  extraction are transport/ordering changes; gates, schemas, and decisions unchanged.
- The shared-prefix CI check fails CLOSED (no `|| true`); emitters/markers fail SAFE.
- Byte-identity is the invariant, not similarity — a one-char drift silently kills the
  cache win, so the CI check is mandatory, not optional.
- Counts: a new CI script is uncounted; no new agents/commands/skills/hooks expected —
  if one becomes necessary, update all doc-currency surfaces in the same change.
- Cost-profile rows must not downgrade correctness-critical roles (code-reviewer,
  red-team) — analysis-only surfaces qualify; when in doubt, leave at inherit and note.
- Pointer conversions must respect worktree reality (memory: gitignored scratch absent
  in worktrees) — paths handed to worktree-resident workers must resolve there; pin
  main-checkout absolute paths where the artifact only exists in the main checkout.
- Minor version bump + CHANGELOG; description version string in place.

## Acceptance criteria
- [ ] Audit table in the PR: every >1k-char paste site found, converted or documented
      as a justified exception.
- [ ] All 14 agent .md files open with the byte-identical shared block; the CI check
      proves it and a self-test proves the check fails on a 1-char drift.
- [ ] check-token-budget.sh passes — any budget raises needed for the shared block
      land in the same PR per the gate's raise rule, with justifications.
- [ ] Spawn ordering (shared → role → skills → volatile) verified per agent in the PR.
- [ ] PR measures cache-read share via the ledger on same-role respawn sequences and
      states plainly that cross-agent reuse is structurally zero (no overclaim).
- [ ] Cost Profiles table gains the async-analysis rows with defaults + override; no
      correctness-critical role downgraded.
- [ ] Batch-API follow-up recorded as roadmap note, not code.
- [ ] check-doc-currency.sh, check-command-sync.sh, check-skills-index-sync.sh,
      validate-version.sh + the new prefix check pass.

## Test plan
CI validators + new prefix-check self-test (offline, bash-3.2/Linux-safe). Manual:
one real `/supervisor` run before/after if feasible, pasting the ledger's cache-read
share delta; else state live verification pending.

## Out of scope
Batch API implementation, prompt diets (job 02's ratchet governs growth), SDK-runner
internals (job 03), orientation memos (job 04), any gate/schema change.

## Status: done
