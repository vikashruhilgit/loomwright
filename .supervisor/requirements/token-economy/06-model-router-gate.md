# 06 — Model router gate: complexity-classified routing + gate-fail escalation + analyzer

> Added 2026-07-19. Today model selection is human-decided and static (`--cheap`
> all-or-nothing; sdk-spike ROLE_CONFIG per-role but global). Nothing DECIDES per
> subtask. This job adds a deterministic, auditable router: the Orchestrator classifies
> each subtask's complexity at PLAN time; a locked routing table maps complexity →
> model+effort at spawn; gate outcomes escalate retries one tier UP; a mandatory
> analyzer records (complexity, model, effort, tokens, verdict) tuples so a LATER,
> propose-only ratchet can earn demotions from evidence. Core asymmetry (locked):
> auto-ESCALATE is safe to mandate (can only cost money); auto-DEMOTE requires data +
> human approval (can cost correctness) and is explicitly out of scope here.

## Goal
Every Phase 3 subtask is routed by a declared table keyed on an Orchestrator-emitted
`complexity` field; a review-FAIL retry re-spawns one tier up (bounded by existing
heal/retry limits); every routed subtask leaves an analyzer tuple in the session JSONL;
a fail-safe valve escalates a chronically failing complexity class to `inherit`.
Unknown/missing complexity fails CLOSED to `inherit` — the router can never route
below today's behavior by accident.

## Evidence
- Orchestrator already decomposes into EPIC/TASK/SUBTASK and reasons about scope —
  emitting `complexity: trivial | standard | hard` per subtask is near-free (verify the
  actual task-tree output format from `agents/orchestrator.md` + RESULT_SCHEMAS before
  asserting field placement; additive field, no schema_version bump if the tree format
  allows — else document).
- Spawn contracts in `skills/async-orchestration/SKILL.md` Part 2 are the single choke
  point where model is set on Task spawn — the table parameterizes what `--cheap`
  currently overrides bluntly. The sdk-runner path already has ROLE_CONFIG (v15.11.0)
  — extend it to read per-subtask complexity, same table semantics.
- Token ledger (v15.9.0) + per-subtask `token_usage` (v15.11.0) provide the cost half
  of the analyzer tuple; verdicts come from the existing reviewer results.
- Precedent for propose-only learning: dreaming, /capability-check, rules suggest —
  no component silently rewrites its own decision policy; the router must not be the
  first.

## Scope
1. **Complexity field (PLAN)**: Orchestrator emits `complexity` per subtask with a
   one-line justification; closed enum; missing/invalid ⇒ treated as `hard`→`inherit`
   downstream (fail closed). Mirror the field in the brief/task-tree docs.
2. **Routing table (locked initial values — do not re-open):**
   - trivial → Sonnet / low
   - standard → Sonnet / medium
   - hard → inherit / high
   **No Haiku at launch** (untested classifier + 200K context window = hard-failure
   risk; Haiku entry is earned later via the propose-only demotion ratchet, out of
   scope here). Table lives in one authoritative config surface (follow the
   prompt-token-budgets.json pattern: machine-readable source + human mirror in
   ARCHITECTURE_CONTRACTS.md §"Model Routing", synced by an existing-or-new check).
   **Reviewer rule:** reviewer runs one tier above its worker with an absolute floor
   of Sonnet; the Phase 4.5 holistic reviewer stays at inherit — always.
3. **Spawn integration**: the spawn contracts (and sdk-runner ROLE_CONFIG) read the
   table + subtask complexity at spawn. Any resolution failure (table unreadable,
   malformed, unknown key) ⇒ `inherit` (today's behavior), never a cheaper model.
   **Effort-column applicability (verify, don't assume):** plugin-agent `effort` is
   set in agent frontmatter — fixed per agent file, NOT per spawn. Confirm from the
   actual Task-spawn surface whether per-spawn effort is honored on the main path; if
   it is not (the expected outcome), the effort column applies to the sdk-runner arm
   ONLY and the main path routes MODEL only — record this split explicitly in
   §Model Routing. Do not fake per-spawn effort on the main path.
   **Routing scope (locked):** the router covers Phase 3 worker/reviewer spawns on
   BOTH paths, including the fast-path single-subtask worker (routed like any
   subtask). Phase 4.5 fix workers, heal-loop spawns, red-team, rubric-grader, and
   every other unclassified spawn stay at their current model (`inherit` /
   existing --cheap semantics) — no complexity label ⇒ fail-closed ⇒ untouched.
4. **Gate-fail escalation (retry routing)**: when a subtask's review verdict is FAIL
   and a retry occurs, the retry spawns one tier up on the MODEL-TIER ladder
   (Sonnet → inherit; already-inherit stays inherit) — NOT the complexity-class
   ladder: a trivial-classified FAIL retries at inherit-model, its complexity label
   unchanged, and effort unchanged except on the sdk-runner arm where ROLE_CONFIG may
   raise it. Bounded by the existing retry/heal-iteration limits — no new loop.
   Record `escalated: true` + prior verdict in the analyzer tuple so postmortems can
   distinguish "cheap model failed" from "brief was bad" (keeps the future demotion
   ratchet's data clean).
5. **Analyzer (mandatory, write-only, fail-SAFE)**: every routed subtask appends
   `(complexity, model_tier, effort, token_usage-or-proxy, review_verdict,
   heal_iterations, escalated)` to the session JSONL — additive fields on the existing
   token-ledger namespace, always exit 0. `/insights` gains a small `## Routing`
   subsection (advisory; degrades silently).
6. **Auto-escalate valve (safety, not learning — locked trigger):** at spawn time,
   read the analyzer history; if a complexity class shows ≥3 review-FAILs within the
   last 20 routed subtasks of that class, route that class to `inherit` for this run
   and flag it in the run summary. **Bounded read (locked — prevents a spawn-time
   wedge):** the valve does NOT scan `.supervisor/logs/*.jsonl` (unbounded, grows
   forever; the bash-3.2 wedge lesson was triggered by exactly this shape). The
   analyzer ALSO appends each tuple to a single rolling `routing-history.jsonl`
   (analyzer-trimmed to the last ~200 lines on write, fail-safe); the valve reads
   ONLY that file, tail-bounded (e.g. `tail -c` hard byte cap + last-N-lines), and
   goes inactive past any cap or on any read anomaly. Failure mode is explicitly
   one-directional: unreadable/absent/malformed/oversized history ⇒ valve inactive ⇒
   static table applies. The valve may only move routing UP; there is no demote path
   in this job.
7. Self-tests (offline, fixture-driven): table resolution incl. fail-closed cases,
   escalation step, valve trigger/inactive/one-directionality, analyzer emission.
8. Docs: ARCHITECTURE_CONTRACTS §Model Routing, command/agent mirror sweep, CHANGELOG.

## Constraints / invariants
- Fail-closed direction is ALWAYS toward the stronger model (`inherit`); no code path
  may resolve to a cheaper tier on error. State this as an invariant in the docs.
- `--cheap` is UNTOUCHED in this job — but its PRECEDENCE is locked now (ambiguous
  interactions always cost a review round): **explicit human flag > router table >
  default.** With `--cheap` set, its existing override applies after routing exactly
  as today — including routing a `hard → inherit` subtask down to Sonnet. That is
  permitted BY DESIGN: the fail-closed-toward-stronger invariant governs the router's
  own error paths, not an explicit human opt-in, which is allowed to go below the
  router's floor. Document this in the one-paragraph interaction note; no code
  integration, aliasing, or deprecation here.
- Analyzer is write-only fail-SAFE (exit 0); the valve's ledger READ is fail-safe to
  "valve inactive". Bimodal philosophy holds: no emitter gates, no gate silently opens.
- Auto-DEMOTE, Haiku routing, and any learned/automatic table mutation are OUT of
  scope — future propose-only `/insights`-fed brief, human-applied.
- No change to gate shapes, heal decisions, never-merge invariants, or retry bounds.
- Additive JSONL/schema fields only; counts unchanged unless documented with all
  doc-currency surfaces in the same change; minor version bump + CHANGELOG;
  description version string in place.
- Prompt-is-program: dynamic trace required (complexity present/missing/invalid ×
  table ok/unreadable × valve active/inactive × escalation on retry).
- **Cache-pool note (considered interaction, not a change):** prompt caches are
  per-model, so mixed routing splits worker spawns across cache pools, mildly
  counteracting jobs 01/05's same-role cache wins. The analyzer tuples + token ledger
  already capture what's needed to observe the net effect — state this in §Model
  Routing so review doesn't flag it as unconsidered.

## Acceptance criteria
- [ ] Orchestrator output carries `complexity` per subtask; missing/invalid provably
      routes to inherit (test or trace).
- [ ] Routing table exists in one authoritative source + human mirror, with the locked
      launch values and the reviewer one-tier-above + Sonnet-floor + Phase-4.5-inherit
      rules stated.
- [ ] Spawn contracts and sdk-runner ROLE_CONFIG both resolve from the table; every
      failure path resolves to inherit (fixture tests).
- [ ] Per-spawn effort applicability on the main path is VERIFIED and recorded in
      §Model Routing (expected: effort column = sdk-runner arm only; main path routes
      model only) — no faked capability.
- [ ] Valve reads only the rolling `routing-history.jsonl`, tail-bounded with a hard
      byte cap; fixture test proves inactive on oversized/absent/malformed history.
- [ ] §Model Routing documents the locked precedence (flag > table > default, with
      the human-opt-in-may-go-below-floor note) and the per-model cache-pool
      interaction.
- [ ] Review-FAIL retry spawns one tier up, bounded by existing limits; `escalated` +
      prior verdict recorded.
- [ ] Analyzer tuples appear on the session JSONL for every routed subtask; `/insights`
      `## Routing` renders on fixtures and degrades silently.
- [ ] Valve: fixture tests for trigger (≥3 FAIL in last 20 per class), inactive on
      unreadable ledger, and one-directionality (no demote path exists).
- [ ] Dynamic trace table in the PR; CI validators pass; self-tests pass offline
      (bash-3.2 + Linux-CI safe where shell is involved).

## Test plan
Offline fixture self-tests for table/escalation/valve/analyzer; dynamic trace in PR.
If a live routed run is feasible, paste its analyzer JSONL lines; else state live
verification pending.

## Out of scope
`--cheap` changes of any kind, Haiku in the routing table, auto-demotion or any
automatic table mutation, learned routing proposals (future `/insights`-fed brief),
gate-shape changes, sdk-runner graduation.
