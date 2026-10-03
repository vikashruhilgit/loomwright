# Supervisor Job: Token ledger + cache-discipline audit of spawn contracts

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — patterns match loomwright/ layout at v15.8.0)
- **Git:** dirty (1 untracked `./--run-id` junk file — do not commit), branch: `main` @ `774a35e` (synced with origin/main)
- **GitHub CLI:** ✓ Authenticated (`vikashruhilgit`)
- **Blockers:** 0 | **Warnings:** 1 (untracked junk file; leave uncommitted)
- **Source requirement:** `.supervisor/requirements/token-economy/01-token-ledger-and-cache-audit.md`

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Bash emitters + insights jq patterns already exist; no new runtime deps |
| 2 | Dependency Availability | GO | jq already required by insights/telemetry; fixture self-tests offline |
| 3 | Architecture Fit | GO | Fail-SAFE SubagentStop command hooks + additive JSONL is the established pattern |
| 4 | Scope vs Supervisor Capability | GO | 4 subtasks, clear file partitions, doc-currency scripts exist |
| 5 | Hard Blockers | GO | None — SubagentStop usage fields absent per TELEMETRY.md (locked proxy path) |

**Overall Verdict:** GO

## Task
**Goal:** Ship a per-agent token (or honestly labeled proxy) ledger into session JSONL, surface it in `/insights` as `## Token economics`, and reorder Subagent Spawn Contracts so volatile content follows a stable cacheable prefix.

**Problem Statement:**
Opus 4.7-family tokenizers inflate prompt cost ~1×–1.35×; loomwright spawns 5–14 agents per run and today has no per-agent token trail in `.supervisor/logs/{session_id}.jsonl`. SubagentStop payloads carry `last_assistant_message` + `agent_transcript_path` but **no usage/token fields** (documented in `loomwright/docs/TELEMETRY.md`). Prompt-cache wins are also left on the table because Part 2 spawn contracts front-load volatile interpolations (task id, worktree, branch).

Success = additive fail-SAFE ledger (real usage when present, else labeled transcript-size proxy), insights section that degrades when absent, all 5 Part 2 contracts stable-prefix-first, AGENT_GUIDELINES rule, offline self-tests, minor bump to **15.9.0**.

## Acceptance Criteria
- [ ] Given a synthetic SubagentStop payload (fixture), when `emit-token-ledger.sh` (or chosen name) runs, then it exits 0 and appends one additive JSONL line under `.supervisor/logs/{session_id}.jsonl` with labeled proxy fields when usage is absent; when usage fields are present in a fixture they take precedence.
- [ ] Given SubagentStop hooks for agents that already run `send-telemetry.sh`, when those agents stop, then the ledger emitter is also invoked fail-SAFE (`|| true`) without changing hook counts unless a new matcher is explicitly justified and all doc-currency surfaces updated.
- [ ] Given a fixture session log with ledger lines, when `build-insights.sh` runs, then `## Token economics` renders with per-role/totals and explicit proxy-vs-real labeling; given a log without ledger lines, the section degrades silently (or with a short absent note) and never non-zero-exits.
- [ ] Given Part 2 spawn contracts in `skills/async-orchestration/SKILL.md`, when reviewed, then each of the 5 contracts places stable role/skill instructions before volatile task id / worktree / branch / brief body; PR review notes document each reorder; semantics unchanged.
- [ ] Given `AGENT_GUIDELINES.md`, when the PR lands, then a "stable-prefix-first" spawn-prompt rule with one-paragraph rationale is present.
- [ ] Given field names chosen for the ledger, when documented in PR / TELEMETRY or RESULT_SCHEMAS note, then they leave room for job 04’s additive `graph_context_used` (no conflicting key inventing).
- [ ] Given the landed PR, when `check-doc-currency.sh`, `check-skills-index-sync.sh`, `validate-version.sh`, and the new offline ledger self-test run, then all pass; plugin version is **15.9.0** with CHANGELOG + in-place description version string updates.

## Outcomes Rubric
- `loomwright/scripts/` contains a new fail-SAFE token-ledger emitter script (stdin SubagentStop JSON → append to session JSONL; always exit 0).
- An offline fixture self-test for that emitter exists under `loomwright/scripts/test-*.sh` and asserts exit 0 + JSONL shape.
- `loomwright/scripts/build-insights.sh` emits a `## Token economics` heading and labels proxy vs real figures in its advisory blurb or body.
- `loomwright/skills/async-orchestration/SKILL.md` Part 2 Subagent Spawn Contracts reorder volatile interpolations after a stable instruction/skill prefix for all five contracts (Context-Keeper, Orchestrator, Execute Manager, Worker, Code Reviewer).
- `AGENT_GUIDELINES.md` contains a stable-prefix-first spawn-prompt rule.
- `loomwright/.claude-plugin/plugin.json` version is `15.9.0` and CHANGELOG.md has a corresponding entry.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

### ST1 — Probe note + fail-SAFE ledger emitter + fixture self-test
- **Files:** `loomwright/scripts/emit-token-ledger.sh` (new), `loomwright/scripts/test-token-ledger.sh` (new), `loomwright/scripts/token-ledger-fixtures/` (new fixtures), `loomwright/hooks/hooks.json` (extend existing `send-telemetry.sh` SubagentStop command chains only — prefer chaining `emit-token-ledger.sh || true` beside existing telemetry to keep hook count at 22), `loomwright/docs/TELEMETRY.md` (probe result + field namespace)
- **Criteria:** Emitter always exits 0; writes additive event (suggested `type`/`event`: `token_ledger`) with real usage keys when present else labeled proxy (`token_proxy_*` or explicit `proxy: true`); never invents usage; self-test covers happy/proxy/empty/missing-session_id; hooks wire without count bump if possible
- **Skills:** error-handling, unit-testing (bash fixture conventions)
- **Depends on:** none
- **requires:** []
- **Provides:**
  - kind: file, path: loomwright/scripts/emit-token-ledger.sh
  - kind: file, path: loomwright/scripts/test-token-ledger.sh
  - kind: file, path: loomwright/docs/TELEMETRY.md

### ST2 — `/insights` `## Token economics` section + tests + docs
- **Files:** `loomwright/scripts/build-insights.sh`, `loomwright/scripts/test-insights.sh`, `loomwright/commands/insights.md`
- **Criteria:** Section mirrors Corpus-health advisory posture; reconciles wording with existing `## Cost` "not captured" blurb (ledger is advisory proxy/usage when present — Cost remains ccusage for $); fixture cases for present / absent / malformed; soft-deps on ST1 field names
- **Skills:** monitoring-observability
- **Depends on:** ST1 (field names)
- **requires:**
  - kind: file, path: loomwright/docs/TELEMETRY.md, from: ST1
  - kind: file, path: loomwright/scripts/emit-token-ledger.sh, from: ST1
- **Provides:**
  - kind: file, path: loomwright/scripts/build-insights.sh
  - kind: symbol, path: loomwright/scripts/build-insights.sh, name: "## Token economics"
  - kind: file, path: loomwright/scripts/test-insights.sh

### ST3 — Cache-discipline reorder of Part 2 spawn contracts + AGENT_GUIDELINES
- **Files:** `loomwright/skills/async-orchestration/SKILL.md`, `loomwright/skills/SKILLS_INDEX.md`, `AGENT_GUIDELINES.md`
- **Criteria:** All 5 contracts stable-prefix-first; skill version/lastUpdated bumped; SKILLS_INDEX Version cell synced; guidelines one-paragraph rule; PR notes list each reorder; **no semantic change** to Task shapes beyond prompt field order
- **Skills:** pattern-detector
- **Depends on:** none (parallel-safe with ST1; merge before ST4)
- **requires:** []
- **Provides:**
  - kind: file, path: loomwright/skills/async-orchestration/SKILL.md
  - kind: file, path: AGENT_GUIDELINES.md
  - kind: file, path: loomwright/skills/SKILLS_INDEX.md

### ST4 — Version bump 15.9.0 + CHANGELOG + doc-currency surfaces
- **Files:** `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CHANGELOG.md`, `CLAUDE.md`, `README.md`, `loomwright/commands/agent-help.md`, optionally `.claude-plugin/README.md`, `loomwright/docs/RESULT_SCHEMAS.md` (additive JSONL namespace note if not already in TELEMETRY)
- **Criteria:** version 15.9.0 everywhere required; description version strings updated in place only; `validate-version.sh` + `check-doc-currency.sh` + `check-skills-index-sync.sh` pass; counts UNCHANGED unless ST1 forced a hook-count bump (prefer not)
- **Skills:** quality-checklist
- **Depends on:** ST1, ST2, ST3
- **requires:**
  - kind: file, path: loomwright/scripts/emit-token-ledger.sh, from: ST1
  - kind: file, path: loomwright/scripts/build-insights.sh, from: ST2
  - kind: file, path: loomwright/skills/async-orchestration/SKILL.md, from: ST3
  - kind: file, path: AGENT_GUIDELINES.md, from: ST3
- **Provides:**
  - kind: file, path: loomwright/.claude-plugin/plugin.json
  - kind: file, path: CHANGELOG.md

## Parallelism Analysis
- **LAUNCHABLE together:** ST1 + ST3 (zero file overlap)
- **BLOCKED:** ST2 waits on ST1 field-name freeze; ST4 waits on ST1+ST2+ST3
- **Recommended wave:** Wave A: ST1 ‖ ST3 → Wave B: ST2 → Wave C: ST4

## File Impact Map (confidence)

| Path | Confidence | Notes |
|------|------------|-------|
| loomwright/scripts/emit-token-ledger.sh | HIGH | new |
| loomwright/scripts/test-token-ledger.sh | HIGH | new |
| loomwright/scripts/token-ledger-fixtures/* | HIGH | new |
| loomwright/hooks/hooks.json | HIGH | chain emit beside send-telemetry |
| loomwright/docs/TELEMETRY.md | HIGH | probe + schema note |
| loomwright/scripts/build-insights.sh | HIGH | new section near Cost/Corpus health |
| loomwright/scripts/test-insights.sh | HIGH | additive cases |
| loomwright/commands/insights.md | MEDIUM | docs |
| loomwright/skills/async-orchestration/SKILL.md | HIGH | Part 2 reorder |
| loomwright/skills/SKILLS_INDEX.md | HIGH | version sync |
| AGENT_GUIDELINES.md | HIGH | new rule |
| version/doc surfaces | HIGH | 15.9.0 |

## Skill References
- `skills/error-handling/SKILL.md` — fail-SAFE emitters
- `skills/state-management/SKILL.md` — session JSONL catalog (add event if needed)
- `skills/async-orchestration/SKILL.md` — spawn contracts (mutate Part 2 only)
- `skills/monitoring-observability/SKILL.md` — insights advisory posture
- `skills/quality-checklist/SKILL.md` — doc-currency gates

## Risk Assessment
| Risk | Mitigation |
|------|------------|
| No usage fields on SubagentStop | Locked fallback: labeled transcript-size proxy; PR records probe |
| Coverage only on 3 hook matchers (not worker/EM) | Document coverage gap honestly; prefer no hook-count bump this PR |
| `## Cost` says tokens not captured | Reword Cost to clarify $ via ccusage; Token economics is separate advisory ledger |
| Semantic drift in spawn-contract reorder | Order-only change; code-reviewer consistency check; review notes per contract |
| ST2/ST1 field rename thrash | Freeze event + key names in ST1 TELEMETRY note before ST2 |
| Job 04 `graph_context_used` collision | Reserve namespace; document keys for 04 |

## Configuration
- **feature_branch:** `feature/token-ledger-cache-audit`
- **base:** `main`
- **max_workers:** 2
- **cost_profile:** default
- **Do not commit:** `./--run-id`, `.supervisor/`

## Locked product calls (do not re-open)
1. If SubagentStop lacks usage → labeled proxy + gap note; do not block on live Anthropic usage.
2. Never present proxy figures as exact tokens.
3. Real usage fields, when present, take precedence over proxy.

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-07-14-token-ledger-cache-audit.md
```

## LAUNCH_PAD_META
- source_requirement: .supervisor/requirements/token-economy/01-token-ledger-and-cache-audit.md
- automate_run: .supervisor/automate/automate-2026-07-14-151145.md
- plugin_version_at_plan: 15.8.0 → target 15.9.0
