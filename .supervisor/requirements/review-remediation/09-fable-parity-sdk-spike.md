# 09 — Fable-parity: Agent SDK spike (port Phase 3 loop) + multi-voter heal + baseline eval (P2, strategic)

## Goal
Close the generation gap between Loomwright's prompt-emulated orchestration and
current-harness deterministic orchestration, in the smallest falsifiable way: a bounded
Agent SDK spike that ports ONLY Execute Manager's Phase 3 poll loop to code, a
multi-voter upgrade to Phase 4.5 verification, per-stage model/effort routing, and an
eval that benchmarks Loomwright against bare Claude Code on the same tasks. The spike
answers "is a v16 SDK-based runner worth building?" with data, re-opening roadmap P2-11
(deferred "to v11+") deliberately.

## Evidence
- `loomwright/agents/execute-manager.md` (601 lines) is a markdown prompt emulating a
  deterministic poll loop with a 60-tool-call budget — control flow in prose is the
  largest remaining reliability gap (2026-07-05 review, finding 1; Fable-parity
  assessment 2026-07-05).
- Result blocks (WORKER_RESULT etc.) are free text validated post-hoc by 30s haiku
  prompt-hooks; schema-forced structured output at the tool-call layer makes malformed
  results impossible rather than detected. Only reachable via SDK.
- Phase 4.5 is a single reviewer + fix loop; current-generation quality pattern is N
  independent verifiers per finding (majority-refute kill, perspective-diverse lenses).
- No number exists for "Loomwright beats plain Claude Code on the same requirement."
- Roadmap P2-11 (Claude Agent SDK for Supervisor) was stamped DEFERRED by design in
  item 03 — this item is its deliberate re-opening, scoped to a spike, not a rewrite.

## Hard preconditions
- Item 05 (supervisor prompt refactor) MERGED first — port less prompt, not more.
- Items 01–04 merged (stable doc/test baseline to measure against).
- Verify current Agent SDK capabilities before design (docs/claude-code-guide, not
  memory): programmatic subagent spawn, structured-output schemas, session/transcript
  access, hook interop with a plugin-distributed runner. Anything unconfirmed is marked
  "needs verification" in the spike doc, never assumed.

## Part A — SDK spike: port the Phase 3 loop only (timebox: ~2 weeks of sessions)
1. New `loomwright/sdk-spike/` (TypeScript or Python — pick by SDK maturity at spike
   time; record the reason): a runner that, given a Supervisor-Ready Brief's subtask
   list, does what execute-manager.md does — spawn worker per subtask (worktree
   isolation), poll, spawn reviewer per completed worker, collect results — but in CODE:
   deterministic loop, no tool-call budget needed, worker/reviewer results returned as
   schema-validated structured output (reuse WORKER_RESULT / CODE_REVIEW_RESULT field
   shapes as JSON Schemas; schema_version fields preserved).
2. Integration seam: Supervisor Phase 3 gains an OPT-IN branch (`--sdk-runner`,
   default OFF) that shells out to the spike runner instead of Task-spawning
   execute-manager. Fail CLOSED if the runner binary/env is absent when the flag is
   passed; zero change to the default path.
3. Contract parity: the runner emits an EXECUTE_RESULT-equivalent block so Phase 4
   FINALIZE consumes it unchanged. SubagentStop hooks note: workers spawned by the SDK
   runner may not fire plugin hooks.json validators — document exactly what fires and
   what the runner validates itself (this is a spike finding, not a bug).
4. Spike record: `loomwright/docs/SPIKES/SDK_RUNNER_SPIKE.md` — what ported cleanly,
   what the SDK cannot do (hooks? memory? skills preload?), token/latency comparison on
   the same brief run both ways, and a GO/NO-GO recommendation for a v16 runner.

## Part B — Multi-voter Phase 4.5 verification (independent of Part A; prompt-only)
1. **Opt-in experiment flag, NOT default-ON (rebaselined 2026-07-06):** gate the whole
   mechanism behind `--multi-voter-heal` (or `.supervisor/config.json`
   `.multi_voter_heal`), default OFF — it changes Phase 4.5 cost (~2× review spawns) and
   user expectations around the currently opt-in red-team lens, so it graduates to
   default only if Part D's eval shows it earns its cost. When ON: spawn code-reviewer +
   red-team-reviewer (existing agents) as INDEPENDENT parallel reviewers on the
   integrated diff; a BLOCKING/HIGH finding triggers a fix only if it survives a
   second-opinion check (the other lens is asked to refute it; refuted findings are
   logged, not fixed). Flag semantics must not collide with the standalone
   `--red-team/--no-red-team` advisory lens — document the interaction in one place.
2. Advisory discipline unchanged: heal_decision semantics, bounds (--heal-iterations),
   and never-merge stay identical; this changes WHICH findings get fixed, not the gate
   shape. Red-team participation here is default-ON for the verification vote but its
   own standalone --red-team lens semantics are untouched.
3. Record per-run: findings_raised / findings_refuted / findings_fixed in the
   SUPERVISOR_RESULT summary (additive, no schema bump).

## Part C — Per-stage model/effort routing (small)
- Add a recommended-model/effort note per agent frontmatter comment + route Phase 4.5
  verification spawns at the strongest available tier while keeping `model: inherit`
  the default everywhere (Fable-class models are only available when the session runs
  on them — inherit is correct; do NOT hardcode model IDs).
- Extend the `--cheap` profile table in ARCHITECTURE_CONTRACTS.md with the new
  verification-stage row.

## Part D — Baseline eval (extends item 08's harness; run after A+B land)
Pre-registered before running: pick 5 requirements; run each 3 ways on the same model —
(1) bare Claude Code (no plugin, plain prompt + subagents), (2) Loomwright default,
(3) Loomwright + --sdk-runner + multi-voter. Metrics: review rounds to READY,
heal_iterations, post-merge defect findings from an independent /code-reviewer pass,
wall tokens. Record in `docs/SPIKES/FABLE_PARITY_EVAL.md` with an explicit decision
rule stated up front: SDK runner graduates to v16 only if (3) beats (2) on defects or
rounds without >1.5× token cost; Loomwright itself must beat (1) or the losing layers
get cut (north-star "prove the loop works — or cut it").

## Constraints / invariants
- Default behavior byte-identical with the flag off; all existing tests + validators
  green throughout.
- Single-merge-executor, bimodal-failure, sole-writer invariants untouched.
- Spike code is quarantined in sdk-spike/ (not shipped in the plugin manifest surface;
  no count changes) until a GO decision produces a real v16 plan.
- Every SDK capability claim in the spike doc cites the docs version checked.
- Scratch branches only for eval runs; no PRs to main from eval traffic.

## Acceptance criteria
- [ ] SDK_RUNNER_SPIKE.md exists with parity matrix (what works / what doesn't / needs
      verification), measured token+latency comparison, and GO/NO-GO.
- [ ] `--sdk-runner` opt-in branch exists, fail-closed when runner absent, default path
      diff-clean.
- [ ] Multi-voter Phase 4.5 live with refute-logging; ≥1 real run showing a refuted
      finding NOT fixed (or an explicit note that none occurred).
- [ ] FABLE_PARITY_EVAL.md with pre-registered decision rule, 5×3 run table, and a
      graduate/cut verdict per layer.
- [ ] Roadmap P2-11 verdict updated from DEFERRED to the spike's outcome.

## Out of scope
Full v16 SDK rewrite (that is the OUTPUT decision, not this item), porting Supervisor
phases other than 3, forcing non-inherit models, changing result schema versions,
agent-teams integration.

## Status: done
- completed: 2026-07-07 | PR: https://github.com/vikashruhilgit/loomwright/pull/99 | via: /automate run automate-2026-07-06-100629
