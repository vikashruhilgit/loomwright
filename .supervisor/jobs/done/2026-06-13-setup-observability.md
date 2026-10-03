# Supervisor Job: /setup umbrella command + observability module (v14.24.0)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — v14.23.2, matches plugin.json; doc-currency green at brief time)
- **Git:** clean (1 untracked: `.claude/` — benign), branch: main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (untracked `.claude/` dir; no impact)

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Work is markdown commands/skills + bash scripts + YAML configs — exactly this repo's stack |
| 2 | Dependency Availability | CAUTION | Docker images (Langfuse v3 stack, otel-collector-contrib) are external; Langfuse v3 self-host requires Postgres + ClickHouse + Redis + S3/MinIO — compose MUST follow the official Langfuse compose, pinned tags. CI has no running containers: all new self-tests must be static-validation only |
| 3 | Architecture Fit | GO | Follows established conventions: opt-in config (telemetry precedent), `${CLAUDE_PLUGIN_ROOT}` runtime paths, `test-*.sh` CI gate, additive schema fields, hook-count freeze |
| 4 | Scope vs Supervisor Capability | GO | 5 subtasks, each 30–60 min, clean file boundaries, 3 parallelizable |
| 5 | Hard Blockers | GO | No migrations, no credentials needed at build time (Langfuse keys generated at user-init runtime, not in repo) |

**Overall Verdict:** GO (CAUTION findings carried into Risk Assessment)

## Task
**Goal:** Add a `/setup` umbrella configuration command with a full observability module (local cost/trace tracking via Claude Code's native OTel → bundled Langfuse stack) plus version-stamped quality metrics, shipped as plugin v14.24.0.

**Problem Statement:**
Plugin users (maintainer and third-party installers) need one-command setup for per-run cost, token, and cache-behavior tracking because agent-run economics are currently invisible — no cost-per-run, no cache-efficiency evidence, no cross-version performance comparison. Currently, configuration knowledge is scattered (`/telemetry`, webhook env, Beads, MySQL MCP) and quality metrics (heal_iterations, rubric_score, review_rounds) carry no plugin version, so "is v14.25 better than v14.24" is unanswerable. Success looks like: `/setup observability` yields a healthy local Langfuse receiving version-tagged traces from every repo, a session-start warning when the backend is down, and `/insights` showing a per-version quality table.

**Settled design constraints (NOT open questions):**
- The plugin emits NO spans itself — Claude Code's native OTel telemetry is the only emitter. No transcript parsing.
- Env block goes in user-scope `~/.claude/settings.json` `env` key via jq deep-merge (never overwrite), with a timestamped backup written first.
- Env block contents: `CLAUDE_CODE_ENABLE_TELEMETRY=1`, `OTEL_METRICS_EXPORTER=otlp`, `OTEL_LOGS_EXPORTER=otlp`, `OTEL_TRACES_EXPORTER=otlp`, `OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf`, `OTEL_EXPORTER_OTLP_ENDPOINT=<collector>`, `OTEL_EXPORTER_OTLP_HEADERS=<Basic auth>`, `OTEL_RESOURCE_ATTRIBUTES=service.version=<plugin version>`.
- Langfuse OTLP endpoint (`/api/public/otel`) ingests TRACES ONLY, HTTP only — collector forwards traces; this limitation is documented, not worked around.
- Hook count MUST stay 19: down-detection extends `scripts/session-resume.sh`, no new `hooks.json` entry. The hook informs only — NEVER starts/restarts Docker.
- All runtime references use `${CLAUDE_PLUGIN_ROOT}/...` paths; repo-relative `ai-agent-manager-plugin/...` paths appear only in dev docs.
- Version-stamp fields are ADDITIVE OPTIONAL — no `schema_version` bumps anywhere. The `session_end` flat field names are a hard contract with build-insights.sh (ST4): never rename existing fields, only add `plugin_version`.
- `/telemetry` command is UNCHANGED; `/setup telemetry` delegates to it.
- Out of scope: plugin-side span emission, mid-session watchdog, container auto-heal, `/insights` cost integration beyond the per-version quality table, fixed-task eval harness.

## Acceptance Criteria
- [ ] AC1: Given the plugin installed, when the user runs `/setup` with no args, then a status dashboard covering observability / telemetry / notifications / webhook / Beads / MySQL MCP is printed (each row derived from a real check: env var, consent file, container state, `bd` presence) and a multi-select offers which to configure.
- [ ] AC2: Given Docker running, when the user completes `/setup observability` choosing "local Langfuse", then assets are copied to `~/.claude/ai-agent-manager/observability/`, `docker compose up -d` reaches healthy, Langfuse is headlessly provisioned via `LANGFUSE_INIT_*` with generated keys, the env block is deep-merged into `~/.claude/settings.json` (existing keys preserved, backup written), and a smoke-test span lands in Langfuse before success is reported.
- [ ] AC3: Given a corporate OTLP endpoint, when the user chooses "existing endpoint", then only the env-merge step runs (no Docker), with endpoint/headers collected from the user.
- [ ] AC4: Given observability configured and the collector endpoint unreachable, when a Claude Code session starts, then `session-resume.sh` injects a context warning containing the exact `docker compose ... up -d` restart command and a `/setup observability` pointer, fires `notify-desktop.sh`, suppresses repeat warnings for 24h via a marker file, and exits 0.
- [ ] AC5: Given observability NOT configured, when `session-resume.sh` runs, then no probe executes and existing behavior is byte-for-byte unaffected.
- [ ] AC6: Given a Supervisor run completes, when the `session_end` JSONL event is written, then it carries `plugin_version` (read from plugin.json); the same additive field appears in the POSTMORTEM_RESULT trend line (`.supervisor/postmortem/results.jsonl` jq template in `skills/pr-postmortem/SKILL.md`) and the telemetry payload (`send-telemetry-core.sh`).
- [ ] AC7: Given session logs spanning ≥2 plugin versions, when `build-insights.sh` runs, then the dashboard includes a per-version table (run count, heal-PASS rate, avg heal_iterations, avg rubric_score) with version-less runs grouped as "unknown".
- [ ] AC8: Given a machine without a Docker daemon (CI), when `test-setup-observability.sh` and `test-session-probe.sh` run, then they pass using static validation only (YAML parses, rename rules present, merge idempotency, probe state machine).
- [ ] AC9: Given the finished change, when `scripts/check-doc-currency.sh` and `scripts/validate-version.sh` run, then all count claims (14 agents / 18 commands / 54 skills / 19 hooks) and v14.24.0 version claims pass.

## Outcomes Rubric
- `ai-agent-manager-plugin/commands/setup.md` exists and every runtime asset reference in it uses `${CLAUDE_PLUGIN_ROOT}/scripts/otel/...` (no `ai-agent-manager-plugin/...` runtime paths).
- `ai-agent-manager-plugin/skills/setup/SKILL.md` exists with version frontmatter and `skills/SKILLS_INDEX.md` contains a `setup` row.
- `ai-agent-manager-plugin/scripts/otel/otel-collector-config.yaml` contains rename rules for all four token attributes (`input_tokens`, `output_tokens`, `cache_read_tokens`, `cache_creation_tokens`) to `gen_ai.usage.*` names and a `file_storage`-backed sending queue.
- Every service in `ai-agent-manager-plugin/scripts/otel/docker-compose.yml` declares `restart: unless-stopped` and a `healthcheck`.
- `ai-agent-manager-plugin/scripts/session-resume.sh` contains a probe gated on observability env presence, a 24h marker suppression, and no `docker start`/`docker compose up` invocation.
- `ai-agent-manager-plugin/scripts/build-insights.sh` emits a per-version section grouped by `plugin_version` with an "unknown" fallback group.
- `ai-agent-manager-plugin/.claude-plugin/plugin.json` version is `14.24.0` and `hooks/hooks.json` defines exactly the same 19 hook entries as before (no additions/removals).

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | OTel bundled assets + static self-test | AC8 (partial) | 0 modify, 3 create | docker, monitoring-observability | LAUNCHABLE |
| 2 | `/setup` command + setup skill + index | AC1, AC2, AC3 | 1 modify, 2 create | quality-checklist, agent-output, telemetry | BLOCKED (by #1) |
| 3 | Session-start health probe | AC4, AC5, AC8 (partial) | 1 modify, 1 create | error-handling | LAUNCHABLE |
| 4 | Version stamping + per-version insights | AC6, AC7 | 7 modify, 0 create | telemetry, quality-checklist | LAUNCHABLE |
| 5 | Docs + hygiene sweep (v14.24.0) | AC9 | 6 modify, 1 create | commit, quality-checklist, claude-md-validation | BLOCKED (by #1–#4) |

### Subtask 1 — OTel bundled assets + static self-test (LAUNCHABLE)

Create the bundled observability assets and their Docker-independent self-test.

- `ai-agent-manager-plugin/scripts/otel/docker-compose.yml` — Langfuse v3 self-host stack following the **official Langfuse docker-compose** (langfuse-web, langfuse-worker, postgres, clickhouse, redis, **minio** — v3 requires S3-compatible storage) plus an `otel-collector` (image `otel/opentelemetry-collector-contrib`, pinned tag). Every service: `restart: unless-stopped` + `healthcheck`. Langfuse headless provisioning via `LANGFUSE_INIT_ORG_*` / `LANGFUSE_INIT_PROJECT_*` (incl. `_PUBLIC_KEY`/`_SECRET_KEY`) and `LANGFUSE_INIT_USER_*` env vars, parameterized through an `.env` file the init flow generates (placeholders in the committed compose; NO real secrets committed).
- `ai-agent-manager-plugin/scripts/otel/otel-collector-config.yaml` — OTLP receiver (http/protobuf, 4318); `transform`/`attributes` processor renaming span attributes `input_tokens`→`gen_ai.usage.input_tokens`, `output_tokens`→`gen_ai.usage.output_tokens`, `cache_read_tokens`→`gen_ai.usage.cache_read.input_tokens`, `cache_creation_tokens`→`gen_ai.usage.cache_creation.input_tokens`; `otlphttp` exporter → `http://langfuse-web:3000/api/public/otel` with Basic auth header from env; `file_storage` extension + persistent `sending_queue`. Traces pipeline only (Langfuse ingests traces only); metrics/logs pipelines may terminate in a `debug`/`nop` exporter with a comment explaining why.
- `ai-agent-manager-plugin/scripts/test-setup-observability.sh` — static-only self-test (MUST pass without a Docker daemon, per CI hard gate that runs every `test-*.sh`): compose YAML parses (python3 yaml), every service has `restart: unless-stopped` + healthcheck, all four rename rules present, sending-queue + file_storage present, no real secrets in committed files, exporter targets `/api/public/otel`.

```yaml
provides:
  - {kind: "file", path: "ai-agent-manager-plugin/scripts/otel/docker-compose.yml"}
  - {kind: "file", path: "ai-agent-manager-plugin/scripts/otel/otel-collector-config.yaml"}
  - {kind: "file", path: "ai-agent-manager-plugin/scripts/test-setup-observability.sh"}
requires: []
external_requires:
  - "Docker images at user runtime only (langfuse v3, otel/opentelemetry-collector-contrib, postgres, clickhouse, redis, minio) — never pulled in CI"
  - "Langfuse v3 headless-init env var contract (LANGFUSE_INIT_*)"
```

### Subtask 2 — `/setup` command + setup skill + index (BLOCKED by #1)

- Create `ai-agent-manager-plugin/commands/setup.md` — inline main-thread workflow (same execution model as `/telemetry`, `/insights`). No-arg: status dashboard (observability: env block present? containers healthy via `docker compose ps`? — telemetry: `.supervisor/telemetry-consent.json` — notifications: hooks present (always-on note) — webhook: `AI_AGENT_MANAGER_WEBHOOK_URL` — Beads: `bd` on PATH + `.beads/` — MySQL MCP: `DB_*` env), then `AskUserQuestion` multi-select. `/setup <module>` jumps directly. Module contract: check → report → offer → apply → verify; idempotent; never blind-overwrite. v1 depth: observability FULL (init flow per settled constraints: Docker check incl. start-at-login warning → backend choice local-Langfuse / existing-endpoint / console → copy assets from `${CLAUDE_PLUGIN_ROOT}/scripts/otel/` to `~/.claude/ai-agent-manager/observability/` → generate `.env` with keys → `docker compose up -d` + wait-healthy → jq deep-merge env block into `~/.claude/settings.json` with timestamped backup → smoke test: emit span, poll Langfuse API → print dashboard URL + restart note + optional per-repo `service.name` snippet; plus `status` and `remove` subflows); telemetry DELEGATES to `/telemetry` (no consent duplication); others status + guidance only.
- Create `ai-agent-manager-plugin/skills/setup/SKILL.md` — module protocol (check/report/offer/apply/verify contract, module registry, settings-merge rules, smoke-test recipe) with version frontmatter, per `skills/SKILL_TEMPLATE.md`.
- Modify `ai-agent-manager-plugin/skills/SKILLS_INDEX.md` — add `setup` row.

```yaml
provides:
  - {kind: "file", path: "ai-agent-manager-plugin/commands/setup.md"}
  - {kind: "file", path: "ai-agent-manager-plugin/skills/setup/SKILL.md"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/SKILLS_INDEX.md", name: "setup"}
requires:
  - {from: "1", kind: "file", path: "ai-agent-manager-plugin/scripts/otel/docker-compose.yml"}
  - {from: "1", kind: "file", path: "ai-agent-manager-plugin/scripts/otel/otel-collector-config.yaml"}
external_requires:
  - "jq (already a plugin runtime dependency)"
```

### Subtask 3 — Session-start health probe (LAUNCHABLE)

- Modify `ai-agent-manager-plugin/scripts/session-resume.sh` (153 lines today): add an `observability_probe` function called from the existing flow. Gate: env block present in `~/.claude/settings.json` (jq read of `env.CLAUDE_CODE_ENABLE_TELEMETRY` + `env.OTEL_EXPORTER_OTLP_ENDPOINT`) — absent ⇒ return immediately (AC5, zero added output). Probe: `curl --max-time 1` against the configured endpoint's health path. Down ⇒ append a bounded warning block to the hook's context output (restart command + `/setup observability` pointer) + fire `notify-desktop.sh`; write marker `~/.claude/ai-agent-manager/observability/.last-warned`; suppress if marker < 24h old. ALWAYS `exit 0`; NEVER invoke docker. Preserve the script's existing silent-on-startup vs resume/clear/compact source handling and its ≤10k context bound.
- Create `ai-agent-manager-plugin/scripts/test-session-probe.sh` — static tests of the probe's 4 states (unconfigured no-op / healthy silent / down warns / marker-suppressed), using a temp HOME fixture and a stubbed curl; no Docker, no network.

```yaml
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/scripts/session-resume.sh", name: "observability_probe"}
  - {kind: "file", path: "ai-agent-manager-plugin/scripts/test-session-probe.sh"}
requires: []
external_requires: []
```

### Subtask 4 — Version stamping + per-version insights (LAUNCHABLE)

Additive `plugin_version` (read from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` at runtime) in three emitters + one aggregator. NO schema_version bumps; NEVER rename existing `session_end` flat fields (hard ST4 contract).

- Modify `ai-agent-manager-plugin/agents/supervisor.md` — instruct the `session_end` JSONL emission (Phase 4.5 completion tail) to include `plugin_version`; update the inline example line (~L1324) and the hard-signal fields paragraph (additive note).
- Modify `ai-agent-manager-plugin/skills/pr-postmortem/SKILL.md` — add `plugin_version` to the jq trend-append template (~L120–133) and the trend-line schema table (§"POSTMORTEM_RESULT trend-line schema", additive optional row; `schema_version` stays 1).
- Modify `ai-agent-manager-plugin/scripts/send-telemetry-core.sh` — include `plugin_version` in the structured payload/redacted JSON.
- Modify `ai-agent-manager-plugin/scripts/build-insights.sh` — new per-version table: group `session_end` events by `plugin_version // "unknown"`; columns: runs, heal-PASS rate, avg heal_iterations, avg rubric_score.
- Modify `ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md` — document the additive field on the `session_end` hard-signal section and the POSTMORTEM trend schema.
- Modify `ai-agent-manager-plugin/scripts/test-insights.sh` + `ai-agent-manager-plugin/scripts/test-telemetry.sh` — fixture coverage: version present, absent ("unknown" grouping), mixed.

```yaml
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/supervisor.md", name: "plugin_version"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/pr-postmortem/SKILL.md", name: "plugin_version"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/scripts/send-telemetry-core.sh", name: "plugin_version"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/scripts/build-insights.sh", name: "plugin_version"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md", name: "plugin_version"}
requires: []
external_requires: []
```

### Subtask 5 — Docs + hygiene sweep, v14.24.0 (BLOCKED by #1–#4)

- Create `ai-agent-manager-plugin/docs/OBSERVABILITY.md` — architecture (CLI emits → collector renames → Langfuse stores), env reference, Langfuse traces-only limitation, settings-merge/backup behavior, probe behavior, `agent.name` redaction caveat for third-party-marketplace plugins (**verify empirically during this subtask** with a console-exporter run; document the observed behavior honestly), troubleshooting.
- Modify `ai-agent-manager-plugin/.claude-plugin/plugin.json` — version `14.24.0`; description counts updated IN PLACE (18 slash commands, 54 skills; no appended version clause — anti-rebloat rule).
- Modify `.claude-plugin/marketplace.json` — same in-place count/version updates.
- Modify `README.md` — quick-start line ("run `/setup` to configure optional integrations") + command table row.
- Modify `CLAUDE.md` — v14.24.0 release banner (keep two most recent: drop v14.23.1's banner per convention), command/skill counts, prior release notes → CHANGELOG.md, note the SessionStart hook's probe extension in the hook table row (count stays 19).
- Modify `ai-agent-manager-plugin/commands/agent-help.md` — add `/setup`.
- Modify `CHANGELOG.md` — v14.24.0 entry (and relocated v14.23.1 note).
- Verify locally before completion: `bash scripts/check-doc-currency.sh`, `bash scripts/validate-version.sh`, `bash scripts/check-command-sync.sh`, `bash scripts/check-contract-parity.sh`, and the full `test-*.sh` suite.

```yaml
provides:
  - {kind: "file", path: "ai-agent-manager-plugin/docs/OBSERVABILITY.md"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/.claude-plugin/plugin.json", name: "version"}
  - {kind: "symbol", path: "README.md", name: "/setup"}
  - {kind: "symbol", path: "CLAUDE.md", name: "v14.24.0"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/commands/agent-help.md", name: "/setup"}
requires:
  - {from: "1", kind: "file", path: "ai-agent-manager-plugin/scripts/otel/docker-compose.yml"}
  - {from: "2", kind: "file", path: "ai-agent-manager-plugin/commands/setup.md"}
  - {from: "2", kind: "file", path: "ai-agent-manager-plugin/skills/setup/SKILL.md"}
  - {from: "3", kind: "file", path: "ai-agent-manager-plugin/scripts/test-session-probe.sh"}
  - {from: "4", kind: "symbol", path: "ai-agent-manager-plugin/scripts/build-insights.sh", name: "plugin_version"}
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2 ──→ Subtask 5
Subtask 3 ─────────────────→ Subtask 5
Subtask 4 ─────────────────→ Subtask 5
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 3 | none | NO |
| Subtask 1 | Subtask 4 | none | NO |
| Subtask 3 | Subtask 4 | none | NO |
| Subtask 2 | Subtask 1/3/4 | none (dep is contract-level, not file-level) | via requires |
| Subtask 5 | all | none (S5 touches only docs/manifests untouched by #1–#4) | via requires |

### Batch Plan
- **Batch 1:** Subtask 1, Subtask 3, Subtask 4 (parallel)
- **Batch 2:** Subtask 2 (after #1)
- **Batch 3:** Subtask 5 (after all)
- **Recommended workers:** 3
- **Estimated batches:** 3

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/docker/SKILL.md`, `skills/monitoring-observability/SKILL.md` |
| 2 | `skills/quality-checklist/SKILL.md`, `skills/agent-output/SKILL.md`, `skills/telemetry/SKILL.md` (delegation boundary) |
| 3 | `skills/error-handling/SKILL.md` |
| 4 | `skills/telemetry/SKILL.md`, `skills/quality-checklist/SKILL.md` |
| 5 | `skills/commit/SKILL.md`, `skills/quality-checklist/SKILL.md`, `skills/claude-md-validation/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| CI hard-gate runs every `test-*.sh` on Ubuntu without containers — a Docker-dependent test breaks the whole suite (source: Feasibility 2.5) | HIGH | Both new tests are static-only (YAML parse, grep assertions, temp-HOME fixtures, stubbed curl); explicitly asserted in AC8 |
| `~/.claude/settings.json` is the user's global config — a bad merge corrupts every project | HIGH | jq deep-merge only, timestamped backup before any write, idempotency covered in self-test; `/setup` aborts (never half-writes) if the file fails to parse |
| Langfuse v3 compose shape (needs MinIO/S3 + ClickHouse) drifts from what's bundled; headless `LANGFUSE_INIT_*` contract is version-sensitive (source: Feasibility 2.5) | MEDIUM | Follow official Langfuse compose, pin image tags, record the pinned Langfuse version in OBSERVABILITY.md; smoke test catches a non-functional stack at init time, not silently later |
| `session_end` flat fields are a hard contract with build-insights.sh (ST4) | MEDIUM | `plugin_version` is additive only; no renames; test-insights.sh fixtures cover absent-field ("unknown") path |
| `agents/supervisor.md` is ~1,460 lines — surgical edits risk collateral wording drift | MEDIUM | Subtask 4 limits edits to the session_end emission instruction + example + hard-signal paragraph; code-reviewer consistency audit auto-expands on `agents/` changes |
| `agent.name` may be redacted to "custom"/"third-party" for this non-official-marketplace plugin, blunting per-role attribution | MEDIUM | Empirical console-exporter check in Subtask 5; document observed behavior; per-role attribution claims in docs phrased per the verified result |
| Langfuse OTLP ingests traces only — users may expect the USD cost *metric* in Langfuse | LOW | Documented explicitly in OBSERVABILITY.md; collector config carries an explanatory comment |
| Marker/asset dir `~/.claude/ai-agent-manager/observability/` collides with a future plugin feature | LOW | Namespaced path agreed in design; documented in skill |

## Configuration
- **Workers:** 3
- **Mode:** parallel
- **Estimated batches:** 3
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-06-13-setup-observability.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-06-12T22:47:25Z
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/54
- **Branch:** feature/setup-observability
- **Files changed:** 29
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Rubric score:** 7/7
- **Summary:** /setup umbrella command + observability module shipped as v14.24.0. 5 subtasks (3 parallel + 2 sequential), all per-subtask reviews PASS. Phase 4.5 integration review found 1 HIGH cross-file defect (compose project-name mismatch), fixed class-wide in 1 iteration; re-review PASS. Rubric 7/7; benchmark pass; ground-truth 2/2; contract conformance pass (3 contracts, 0 violations).
