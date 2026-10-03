# 01 — Token ledger + cache-discipline audit of spawn contracts

> Motivation (2026-07-14): the Opus 4.7-family tokenizer produces ~1×–1.35× the tokens of
> pre-4.7 models for the same text (Sonnet 5 vs 4.6 is the ~30% case; Fable 5 shares the
> Opus 4.8 tokenizer). For an orchestration plugin spawning 5–14 agents per run, the
> inflation compounds per spawn. This job is the MEASURE half: a per-run token ledger,
> plus the cheapest structural win (prompt-cache prefix discipline in the spawn contracts).

## Goal
Every qualifying run leaves a per-agent token trail (input / output / cache-read /
cache-write) in the session JSONL, `/insights` surfaces a `## Token economics` section,
and the verbatim Subagent Spawn Contracts order all volatile content AFTER the stable
instruction/skill prefix so prompt caching actually hits.

## Evidence
- SubagentStop `type: command` telemetry hooks (code-reviewer / qa-executor /
  supervisor-runner) already receive hook payloads — verify empirically what usage fields
  the payload carries (memory: "SubagentStop payload shape" — real payload has
  `last_assistant_message` + `agent_transcript_path`, NOT `result_block`; do NOT assume
  token usage is present — probe first, and if usage is not available in the payload,
  derive what is derivable (e.g. transcript-size proxy) and document the gap honestly).
- `/insights` (`build-insights.sh`) already aggregates session JSONL — additive section
  pattern exists (v15.7.0 added `## Corpus health`).
- Spawn contracts live in `skills/async-orchestration/SKILL.md` Part 2 (moved from
  agents/supervisor.md in v15.4.0). Prompt caching is a prefix match: any volatile value
  (task id, brief path, timestamp, worktree path) interpolated EARLY invalidates the
  cached prefix for every subsequent spawn.

## Scope
1. **Ledger emitter**: extend the existing telemetry/logging path (fail-SAFE, always
   exit 0, additive JSONL fields only — no schema_version bump) to append per-agent token
   fields (or the best honestly-labeled proxy available from the payload) to
   `.supervisor/logs/{session_id}.jsonl`.
2. **`/insights` `## Token economics` section** in `build-insights.sh`: per-role and
   per-run totals, cache-hit ratio when available; degrades gracefully on runs without
   ledger data (advisory, never gates).
3. **Cache-discipline audit** of the Subagent Spawn Contracts in
   `skills/async-orchestration/SKILL.md` Part 2: reorder each contract so stable content
   (role instructions, skill references) precedes volatile content (task id, brief body,
   branch/worktree names). Semantics unchanged — ordering only.
4. **`AGENT_GUIDELINES.md`**: add a "stable-prefix-first" spawn-prompt rule (volatile
   content last) with one-paragraph rationale.
5. Self-test for the ledger emitter (offline, fixture-driven, matching
   `test-insights.sh` conventions).

## Constraints / invariants
- Emitters fail SAFE and always exit 0 (bimodal failure philosophy — do not invert).
- Additive only: no schema_version bumps; old readers must fail-safe-skip new fields.
- Counts likely UNCHANGED (14 agents / 21 commands / 41 skills / 22 hooks) — if a new
  hook entry is genuinely required, update all doc-currency surfaces in the same change.
- Minor version bump from the CURRENT version at execution time + CHANGELOG entry;
  update plugin.json/marketplace.json description version string in place only.
- Never claim the payload carries token usage without verifying empirically (memory:
  verify payload shapes; verify invocation shapes from the file).
- **Locked fallback (do not re-open):** if SubagentStop lacks usage fields, ship a
  clearly labeled proxy (e.g. transcript-size) plus an honest gap note in `/insights`
  and the PR. Do not block this job on live Anthropic usage. Do not present proxy
  figures as exact tokens. Real usage fields, when present, take precedence.

## Acceptance criteria
- [ ] Probe SubagentStop (or the active telemetry path) and RECORD in the PR which
      usage fields exist; ship real fields when present, else the locked proxy path.
- [ ] A qualifying run appends per-agent token (or documented-proxy) fields to the
      session JSONL; a run with the emitter unavailable is unaffected.
- [ ] `/insights` renders `## Token economics` on a fixture log, labels proxy vs real
      counts, degrades silently when data is absent, and states the gap when only
      proxy is available.
- [ ] Every spawn contract in async-orchestration Part 2 places volatile values after
      the stable prefix; a diff-level review note documents each reorder.
- [ ] AGENT_GUIDELINES.md carries the stable-prefix rule.
- [ ] Ledger field names leave room for job 04’s additive `graph_context_used`
      marker (do not invent a conflicting schema; document the intended key namespace
      in the PR if the marker lands in 04’s follow-up).
- [ ] check-doc-currency.sh, check-skills-index-sync.sh, validate-version.sh pass;
      new self-test passes offline.

## Test plan
Fixture-driven self-tests (bash, offline). Manually run one real `/supervisor` smoke run
if feasible and paste the resulting JSONL lines into the PR description; otherwise state
plainly that live verification is pending (no fabricated status).

## Out of scope
CI token-budget gate (job 02), SDK-runner levers (job 03), graph compression (job 04),
any change to gate shapes or heal decisions.

## Status: brief-shipped

Job `.supervisor/jobs/done/2026-07-14-token-ledger-cache-audit.md` completed (reconciled from the job lifecycle, not self-reported).
Acceptance criteria are NOT machine-verified here — review them before promoting this to `## Status: done`.
