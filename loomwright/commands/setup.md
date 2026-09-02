---
description: Umbrella setup command — status dashboard plus guided configuration for every optional plugin capability — observability (local Langfuse + OTel collector), memory in version control, portable house-rule seeding, telemetry, notifications, webhook, Beads, MySQL MCP, opt-in status line
---

# Command: /setup

## Usage

```
/setup                      # Status dashboard (one row per module) + multi-select "what do you want to configure?"
/setup observability        # Observability module directly: init | status | remove
/setup memory               # Put the Twin memory stores under version control IN PLACE (gitignore negation + repo allowlist): status | apply | remove
/setup rules                # Seed .agent/rules/ with PORTABLE conventions on a cold-start repo (labelled seeded, not learned): status | (no-arg → seed)
/setup statusline           # Wire the one-line run report into the user-scope settings file: status | apply | remove
/setup telemetry            # DELEGATES to /telemetry (no consent logic duplicated here)
/setup notifications        # Status + guidance (notification hooks are always-on)
/setup webhook              # Status + guidance (LOOMWRIGHT_WEBHOOK_URL)
/setup beads                # Status + guidance (bd CLI + .beads/)
/setup mysql-mcp            # Status + guidance (DB_* env for the read-only MySQL MCP — separate mysql-mcp@atelier plugin)
```

## Parameters

- **module** (optional): one of `observability`, `telemetry`, `notifications`, `webhook`, `beads`, `mysql-mcp`, `memory`, `rules`, `statusline`.
  - If omitted: run the full status dashboard, then offer configuration via `AskUserQuestion` (multi-select).
  - If unrecognised: print this usage block and stop.
- **observability subcommand** (optional, second positional arg): `init` | `status` | `remove`. If omitted, the module's check step decides — unconfigured → offer `init`; configured → offer `status` / `remove` / reconfigure.
- **rules subcommand** (optional, second positional arg): `status` = read-only report of which portable seeds are present (no writes). If omitted, the module's check step decides — unseeded → offer to seed; already seeded → report and offer status only. **`remove` is N/A** — the store is committed and human-curated, so removing a rule is `/rules` territory (`add-rule.sh --retract`), never a module teardown; and re-seeding a still-seeded repo is a no-op by design rather than a reconfigure — including one whose seeds you have EDITED, since presence is keyed on the seeded stamp rather than the statement text. A seed you RETRACTED is the exception and is re-offered (see the module's honest limits — retract is not a permanent opt-out).
- **memory subcommand** (optional, second positional arg): `status` = read-only report (no writes) | `apply` | `remove`. If omitted, the module's check step decides — not configured → offer to apply (behind the consent gate); configured → offer `status` / `remove`. **`remove` is REQUIRED here** — un-committing is a real operation a user will want, most likely on realising something proprietary was published, so it is implemented rather than documented N/A.
- **statusline subcommand** (optional, second positional arg): `status` = read-only report (no writes) | `apply` | `remove`. If omitted, the module's check step decides — not configured → offer to apply; configured → offer `status` / `remove`. **`remove` is REQUIRED here** — the module changes a visible, always-on surface, so backing it out (and restoring whatever status line was there before) is a real user need, not a documented N/A. **A pre-existing status line this plugin did not write is never replaced without an explicit choice** — see the module's Offer step.
- Note: the twin module was retired with the graphify tier (graph + bridge cold-start bootstrap — a deliberate omission, not an oversight; see `CHANGELOG.md`).

## What This Does

`/setup` is the single entry point for checking and configuring the plugin's optional capabilities. Every module follows the same contract (authority: the `setup` skill, read at Step 0):

> **check → report → offer → apply → verify** — idempotent, and never blind-overwrite.

Settled design facts (do not re-litigate at runtime):

- **The plugin emits NO spans itself.** Claude Code's native OpenTelemetry telemetry (`CLAUDE_CODE_ENABLE_TELEMETRY=1`) is the only emitter. `/setup observability` configures *where those signals go*, nothing more.
- **Langfuse's OTLP endpoint (`/api/public/otel`) ingests TRACES ONLY.** Metrics and logs are not ingested by Langfuse. The bundled collector terminates metrics/logs in a debug exporter so senders never see export errors. This is documented behavior, not worked around.
- **Assets are COPIED at init time** from `${CLAUDE_PLUGIN_ROOT}/scripts/otel/` to `~/.claude/loomwright/observability/`; `docker compose` always runs against the copy (the plugin install dir stays pristine and survives plugin updates).
- **Env changes go in user-scope `~/.claude/settings.json`** under the `env` key via **jq deep-merge** — unrelated keys are never touched, a **timestamped backup is written first**, and the flow **aborts (never half-writes) if the existing file fails to parse**.
- `/telemetry` (GitHub-issues telemetry) is a separate, unchanged command; `/setup telemetry` delegates to it.

---

# Agent Prompt

You are handling the `/setup` slash command inline on the main thread. Parse the FIRST positional argument as the module and the SECOND as the subcommand — `observability` takes `init` | `status` | `remove`; `memory` takes `status` (read-only) | `apply` | `remove`; `rules` takes `status` (read-only). For `memory status` and `rules status`, run the Check + Report steps ONLY and STOP — they are read-only, so never fall through to that module's Offer/Apply flow.

## Step 0 — Load the protocol authority (every invocation)

1. Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md`. It is the authority for the module contract, the module registry, the settings-merge rules, and the smoke-test recipe. Execute its recipes verbatim where this prompt references them.
2. Resolve shared paths once via Bash:
   ```bash
   SETTINGS="$HOME/.claude/settings.json"
   OBS_DIR="$HOME/.claude/loomwright/observability"
   PLUGIN_VERSION=$(jq -r .version "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json")
   ```
3. NEVER hard-code plugin-repo-relative paths — `${CLAUDE_PLUGIN_ROOT}` is the only valid way to reference plugin assets at runtime.
4. End every invocation with a 1-line summary prefixed `Setup:`.

## No-arg flow — status dashboard

Run ONE real check per module (never guess; every cell of the dashboard is derived from a command you actually ran):

1. **observability** —
   - Env block: `[ -f "$SETTINGS" ] && jq -e '.env.CLAUDE_CODE_ENABLE_TELEMETRY == "1"' "$SETTINGS" >/dev/null 2>&1`
   - Mode: if env block present, read `.env.OTEL_TRACES_EXPORTER` (value `console` → console-debug mode) and `.env.OTEL_EXPORTER_OTLP_ENDPOINT`. Classify as **local stack** when the endpoint host is `localhost`/`127.0.0.1` (ANY port — do NOT key off the literal `:4318`; the port is parameterized as `$OTEL_COLLECTOR_PORT` and a customized value must still classify as local) AND the copied stack exists (`[ -f "$OBS_DIR/docker-compose.yml" ]`); otherwise **external endpoint**.
   - Local stack health (only when local): copied stack present (`[ -f "$OBS_DIR/docker-compose.yml" ] && [ -f "$OBS_DIR/.env" ]`) and per-container health via the wait-healthy probe from the skill (single pass, no loop):
     ```bash
     docker compose -p loomwright-observability -f "$OBS_DIR/docker-compose.yml" --env-file "$OBS_DIR/.env" ps -q \
       | xargs docker inspect -f '{{.Name}} {{.State.Health.Status}}' 2>/dev/null
     ```
     Bucket the reported states before choosing the cell: if any container reports `starting`, the stack is **booting** (first boot can take ~10 min — image pulls + ClickHouse migrations), NOT down — surface that distinctly so a just-launched `init` in another pane doesn't read as a failure. **Collector caveat (liveness-only):** `otel-collector`'s healthcheck is `--version` (the contrib image is distroless — no in-container HTTP probe), so a `healthy` collector cell proves the process is *up*, not that it bound `:4318` or is actually ingesting. True readiness is confirmed only by the `init` smoke test (Pattern 6); the dashboard MUST NOT upgrade "N/7 healthy" to "ingesting."
   - Status cell: `configured — local stack N/7 healthy (collector liveness-only)` | `configured — local stack booting (M/7 healthy, K starting)` | `configured — external endpoint` | `configured — console debug` | `partial — env block present, stack down/missing` | `not configured`.
2. **telemetry** — read `.supervisor/telemetry-consent.json` (user-project root). `always_allow` + repo → `enabled (target=<owner/repo>)`; `no` → `disabled`; absent/malformed → `unset`.
3. **notifications** — always-on via plugin hooks (desktop banners at human-decision gates); status cell is `active (built-in hooks)`. No check command needed — note that the webhook variant additionally requires the webhook module below.
4. **webhook** — `[ -n "${LOOMWRIGHT_WEBHOOK_URL:-}" ]`. Status: `set` / `not set`. NEVER print the URL value (it may embed a token) — print only `set (host: <hostname-only>)`.
5. **beads** — `command -v bd >/dev/null 2>&1` and `[ -d .beads ]`. Status: `ready` / `bd installed, repo not initialised` / `not installed`. Note: only Orchestrator/Product Owner use Beads — optional.
6. **mysql-mcp** — check `DB_HOST`, `DB_USER`, `DB_PASS`, `DB_NAME` env vars are non-empty (`DB_PORT` optional). Status: `configured` / `missing: <names of unset vars>`. NEVER print values — names only.
7. **memory** — run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-memory.sh" check` and read the `Memory readiness:` verdict plus the per-path `intended` / `unintended` ignore-status cells and the `allowlist:` line. The helper is fail-safe (always exits 0) and READ-ONLY on this path — it writes nothing. Derive a compact status cell: `configured` → `stores committable`; `gated (...)` → `memory stores committable, findings ledger WITHHELD` plus the offending slugs from the helper's own parenthetical (a **third** outcome — never collapse it into `configured` or `not configured`); `not configured` → `stores ignored (not in version control)`; `partial (...)` and `unknown (...)` → surface the helper's own parenthetical verbatim (`unknown` means the ignore status could not be probed at all — never restate it as a configured/partial claim); if the `.gitignore:` cell reads `absent` or `unparseable: …`, say so instead (e.g. `.gitignore unparseable — apply would abort`). Never guess — every cell comes from that one probe.

8. **rules** — run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/seed-rules.sh" check` and read its per-seed `seed: ABSENT` / `seed: ALREADY SEEDED` lines plus the `seeds: N total · N already seeded · N absent` summary. `check` is READ-ONLY — it invokes no writer and creates nothing (not even the store directory). Derive a compact status cell from that summary alone: `0 absent` → `seeded (N/N portable rules)`; `N absent` with some present → `partially seeded (N of M)`; all absent → `not seeded (M portable rules available)`. If the helper exits non-zero it could not run (missing `jq` — exit 2); report `unknown (seed-rules.sh could not run)` and never a seeded/not-seeded claim. Never guess — every cell comes from that one probe.

9. **statusline** — run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-statusline.sh" check` and read its `statusLine:` cell plus the `Statusline readiness:` verdict. `check` is READ-ONLY — it writes nothing. Derive a compact status cell from that verdict alone: `configured` → `active (one-line run report)`; `not configured` → `not wired`; `foreign (...)` → `another status line is configured — preserved` (a **third** outcome: it is neither configured nor unconfigured, and must never be collapsed into either, because collapsing it to `not configured` is what would invite a silent overwrite); `unknown (...)` → surface the helper's own parenthetical verbatim (missing `jq`, or a settings document that does not parse — report UNVERIFIED, never a configured/not-configured claim). Never guess — every cell comes from that one probe.

Print the dashboard:

```
## /setup — module status

| Module        | Status                                  | Configure with        |
|---------------|-----------------------------------------|-----------------------|
| observability | <derived>                               | /setup observability  |
| telemetry     | <derived>                               | /setup telemetry      |
| notifications | active (built-in hooks)                 | /setup notifications  |
| webhook       | <derived>                               | /setup webhook        |
| beads         | <derived>                               | /setup beads          |
| mysql-mcp     | <derived>                               | /setup mysql-mcp      |
| memory        | <derived>                               | /setup memory         |
| rules         | <derived>                               | /setup rules          |
| statusline    | <derived>                               | /setup statusline     |
```

Then use `AskUserQuestion`. **`AskUserQuestion` accepts at most 4 options**, so do NOT emit one option per unconfigured module (9 modules > 4 → an invalid call). The set below is FIXED at four and must NOT be grown when a module is added — a tenth module folds into an existing bucket or gets its own nested question, exactly as `memory`, `rules` and `statusline` do here:
- `question`: "Which would you like to configure now?"
- `header`: "Configure"
- `multiSelect`: true
- `options` (exactly these, in order; append each module's current status to its description):
  1. **Claude Code surfaces (observability · status line)** — the two modules that write the user-scope settings file; selecting it asks ONE nested question (below) to pick which.
  2. **Repo knowledge stores (memory in version control · portable rule seeds)** — the two per-repo apply flows; selecting it asks ONE nested question (below) to pick which.
  3. **Other integrations (telemetry · webhook · Beads · MySQL MCP)** — print status + setup guidance / delegation for these (telemetry delegates to `/telemetry`; webhook · Beads · MySQL MCP are guidance-only; `notifications` is always-on and needs no action).
  4. **Nothing — just checking** — stop with the summary line.

**How to render the status on a BUNDLED option** (options 1, 2 and 3 each fold several modules behind one label, so "the module's status" is ambiguous): append the per-module statuses joined by ` · `, each prefixed with its module name — `observability: <status> · statusline: <status>` for option 1, `memory: <status> · rules: <status>` for option 2, and `telemetry: <status> · webhook: <status> · beads: <status> · mysql-mcp: <status>` for option 3. Never collapse them into one aggregate word, and never pick one module's status to stand for the bundle. Option 4 is no-module and takes none. Truncate from the right if the description exceeds the option-description limit — drop whole `name: status` pairs, never a status string mid-word.

**Nested question — only when option 1 was selected** (also ≤4 options; never inline these into the set above):
- `question`: "Which Claude Code surface?"
- `header`: "Surfaces"
- `multiSelect`: true
- `options` (exactly these, in order; append each module's current status to its description):
  1. **observability** — full local-Langfuse / existing-endpoint / console init flow.
  2. **statusline** — wire the one-line run report (phase · branch · N/M subtasks · age of the last event) into the user-scope settings file. Backup-first and parse-gated. **If a status line you did not install is already configured it is PRESERVED and merely reported** — replacing it is a separate, explicit choice, and the previous value is recorded so `remove` restores it.
  3. **None — go back** — skip both and continue with the remaining selections.

**Nested question — only when option 2 was selected** (also ≤4 options; never inline these into the set above):
- `question`: "Which repo knowledge store?"
- `header`: "Stores"
- `multiSelect`: true
- `options` (exactly these, in order; append each module's current status to its description):
  1. **memory** — put `.claude/agent-memory/` + `.supervisor/memory/` + the findings ledger `.supervisor/postmortem/results.jsonl` under version control IN PLACE (gitignore negation + repo allowlist). The ledger is GATED: it is un-ignored only while every record's `.repo` is inside the repo allowlist. Consent-bearing — the memory module's own Offer step states what becomes version-controlled before anything is written.
  2. **rules** — seed `.agent/rules/` with a small set of PORTABLE conventions (true of any repo) so a cold-start repo is not empty. They are labelled SEEDED, not learned: every one carries `provenance.source=setup:rules-seed`. Advisory only, no gate.
  3. **None — go back** — skip both and continue with the remaining selections.

Run the corresponding module flow (below) for each selection, in the order listed. For option 3, run the `telemetry` delegation block plus the `webhook`, `beads`, and `mysql-mcp` status/guidance blocks in turn. If "Nothing", stop with the summary line.

**Every module stays reachable as a direct jump regardless of this set** — `/setup memory` and `/setup rules` (and every other module name) go straight to that module's flow without touching the dashboard question. The ≤4-option set is a convenience for the no-arg dashboard, never the only route to a module.

## `/setup <module>` — jump straight to that module's flow.

---

## Module: observability

Pipes Claude Code's native OTel telemetry into a backend. Three backends; v1 implements the **local Langfuse stack** fully.

### Check

Run the same checks as the dashboard row (env block, mode, copied stack, container health). Also detect leftovers: `$OBS_DIR` exists but env block absent (or vice versa) → report as `partial` with which half is missing.

### Report

Print what was found (mode, endpoint, stack health, settings backup count). For `status` subcommand, stop here plus:
- Source the stack `.env` FIRST so a customized `LANGFUSE_PORT` is honored (the smoke-test recipe already does this; the health probe must too — otherwise a changed port is probed against the default `3000`): `set -a; . "$OBS_DIR/.env" 2>/dev/null; set +a`, then `curl -sf "http://localhost:${LANGFUSE_PORT:-3000}/api/public/health"` → Langfuse reachable?
- Container table from the `docker compose ... ps` probe above.

### Offer

If `init` was requested or the module is unconfigured, use `AskUserQuestion`:
- `question`: "Where should Claude Code's OTel telemetry go?"
- `header`: "Backend"
- `multiSelect`: false
- `options`:
  1. `Local Langfuse stack (recommended)` — "Self-hosted Langfuse v3 + OTel collector via Docker; traces land in a local dashboard"
  2. `Existing OTLP endpoint` — "You already run a collector or use Langfuse Cloud; env-merge only, no Docker"
  3. `Console (debug only)` — "Print telemetry to console; no Docker, no endpoint"

If already configured, offer instead: `Status` / `Reconfigure (re-run init)` / `Remove` / `Cancel`.

### Apply — backend 1: local Langfuse stack (FULL init flow)

1. **Docker check.** `command -v docker` and `docker info >/dev/null 2>&1`. If the CLI is missing → stop with install guidance (Docker Desktop on macOS/Windows, docker-ce on Linux). If the daemon is down → ask the user to start it and re-run. **Warn explicitly:** enable *"Start Docker Desktop when you sign in"* (or the OS equivalent) — the stack uses `restart: unless-stopped`, which only auto-restarts while the daemon itself is running; without start-at-login your traces silently go nowhere after a reboot (the collector's persistent queue is in a container volume, not on the host).
2. **Copy assets** (idempotent; never clobber secrets):
   ```bash
   mkdir -p "$OBS_DIR"
   cp "${CLAUDE_PLUGIN_ROOT}/scripts/otel/docker-compose.yml" "$OBS_DIR/"
   cp "${CLAUDE_PLUGIN_ROOT}/scripts/otel/otel-collector-config.yaml" "$OBS_DIR/"
   ```
   Re-copying compose/config on re-init is fine (it picks up plugin updates). **NEVER overwrite an existing `$OBS_DIR/.env`** — it holds the generated keys; if present, reuse it and skip step 3.
3. **Generate `$OBS_DIR/.env`** with openssl-generated secrets — execute the ".env generation" recipe in the setup skill verbatim. The variable set matches exactly what the copied `docker-compose.yml` consumes, plus one compose-CLI key:
   - Project identity: `COMPOSE_PROJECT_NAME` (= `loomwright-observability` — belt-and-braces with the explicit `-p` flag below: compose v2 loads `.env` from the `-f` file's directory, so even a bare `docker compose -f "$OBS_DIR/docker-compose.yml" …` joins the same project instead of deriving a second `observability` project from the dir basename)
   - Infrastructure: `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `CLICKHOUSE_USER`, `CLICKHOUSE_PASSWORD`, `REDIS_AUTH`, `MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD`, `LANGFUSE_S3_BUCKET`
   - Langfuse core: `LANGFUSE_SALT`, `LANGFUSE_ENCRYPTION_KEY` (64 hex chars — `openssl rand -hex 32`), `NEXTAUTH_SECRET`, `NEXTAUTH_URL`, `LANGFUSE_PORT`
   - Headless provisioning: `LANGFUSE_INIT_ORG_ID`, `LANGFUSE_INIT_ORG_NAME`, `LANGFUSE_INIT_PROJECT_ID`, `LANGFUSE_INIT_PROJECT_NAME`, `LANGFUSE_INIT_PROJECT_PUBLIC_KEY` (`pk-lf-…`), `LANGFUSE_INIT_PROJECT_SECRET_KEY` (`sk-lf-…`), `LANGFUSE_INIT_USER_EMAIL`, `LANGFUSE_INIT_USER_NAME`, `LANGFUSE_INIT_USER_PASSWORD`
   - Collector: `LANGFUSE_BASIC_AUTH` (= `base64("<public_key>:<secret_key>")`, derived from the two generated `LANGFUSE_INIT_PROJECT_*_KEY` values), `OTEL_COLLECTOR_PORT`
4. **Start the stack:**
   ```bash
   docker compose -p loomwright-observability -f "$OBS_DIR/docker-compose.yml" --env-file "$OBS_DIR/.env" up -d
   ```
5. **Wait-healthy loop** — execute the skill's wait-healthy recipe (all containers report `healthy` via `docker inspect`; allow up to ~10 minutes on first boot — image pulls + ClickHouse migrations). On timeout: print `docker compose … ps` + the last 20 log lines of any unhealthy service, and STOP (do not merge env, do not report success).
6. **jq deep-merge the env block into `$SETTINGS`** — execute the skill's "Settings merge" recipe verbatim (timestamped backup first; abort if the existing file fails `jq empty`). The block (exactly these 8 keys — the settled contract):

   | Key | Value (local backend) |
   |---|---|
   | `CLAUDE_CODE_ENABLE_TELEMETRY` | `1` |
   | `OTEL_METRICS_EXPORTER` | `otlp` |
   | `OTEL_LOGS_EXPORTER` | `otlp` |
   | `OTEL_TRACES_EXPORTER` | `otlp` |
   | `OTEL_EXPORTER_OTLP_PROTOCOL` | `http/protobuf` |
   | `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://localhost:<OTEL_COLLECTOR_PORT>` (default `http://localhost:4318`) |
   | `OTEL_EXPORTER_OTLP_HEADERS` | `Authorization=Basic <LANGFUSE_BASIC_AUTH>` (the local collector accepts unauthenticated OTLP and ignores it; written anyway so the block shape is identical across backends — note this persists the local Langfuse keypair, base64 `pk:sk`, in plaintext in `settings.json`; acceptable because the keys are local-only, but be aware it lives there) |
   | `OTEL_RESOURCE_ATTRIBUTES` | `service.version=<plugin version from Step 0>` |

7. **Smoke test BEFORE reporting success** — execute the skill's smoke-test recipe: emit a test span via `curl` to `http://localhost:<OTEL_COLLECTOR_PORT>/v1/traces`, then poll the Langfuse API (`/api/public/traces`, Basic auth `pk:sk` from `.env`) until the span lands (up to ~3 minutes — ingestion is async through the worker + ClickHouse). If it never lands: report FAILURE with the collector logs (`docker compose -p loomwright-observability logs otel-collector --tail 50`) — the env merge stays in place (it is correct), but success is NOT claimed.
8. **Label THIS repo immediately (init-tail).** Now that telemetry is enabled, run the per-project labeler once so the current repo is labeled this session instead of waiting for the next session's SessionStart hook:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/set-otel-resource-attrs.sh"
   ```
   Then read back and report the resulting label in the success summary: `jq -r '.env.OTEL_RESOURCE_ATTRIBUTES // "not set"' "$PWD/.claude/settings.local.json" 2>/dev/null` (expect `service.name=<repo>,service.version=<plugin version>`). The script is fail-safe and always exits 0.
9. **Report success:**
   - Dashboard: `http://localhost:<LANGFUSE_PORT>` — login with `LANGFUSE_INIT_USER_EMAIL` / `LANGFUSE_INIT_USER_PASSWORD` from `$OBS_DIR/.env` (print both; this is a local-only credential).
   - Per-project label: report the `service.name`/`service.version` written by the init-tail step above.
   - **"Restart your Claude Code sessions to pick up the env"** — settings.json `env` is read at session start; running sessions keep emitting nothing until restarted.
   - **Per-project labeling is now auto-maintained** by the `set-otel-resource-attrs.sh` SessionStart hook whenever telemetry is enabled: it writes `service.name=<repo-basename>,service.version=<plugin version>` into each repo's `<project>/.claude/settings.local.json` `.env.OTEL_RESOURCE_ATTRIBUTES` (value-level merge — preserves any other attrs you set). You no longer need to hand-author the snippet. *Manual fallback (if you want to set it yourself for a repo):*
     ```json
     { "env": { "OTEL_RESOURCE_ATTRIBUTES": "service.name=<repo-name>,service.version=<plugin version>" } }
     ```
     Note: the project-level `OTEL_RESOURCE_ATTRIBUTES` overrides the user-level value, so both the script's value-level merge and any manual snippet restate `service.name`/`service.version` (other attrs are preserved by the script's merge).

### Apply — backend 2: existing OTLP endpoint (env-merge only, no Docker)

1. Collect from the user (AskUserQuestion + free-text follow-ups): the OTLP endpoint URL and the headers string (e.g. Langfuse Cloud: endpoint `https://cloud.langfuse.com/api/public/otel`, headers `Authorization=Basic <base64(pk:sk)>`).
2. Run the same settings-merge recipe with the same 8 keys; `OTEL_EXPORTER_OTLP_ENDPOINT` / `OTEL_EXPORTER_OTLP_HEADERS` from the user's answers.
3. Smoke test: `curl` a test span to `<endpoint>/v1/traces` with the user's headers and verify a 2xx response (arbitrary backends can't be polled). **Document, don't work around:** if the endpoint is a bare Langfuse `/api/public/otel`, metrics and logs exporters will get rejected — Langfuse ingests traces only; that's expected. Point the endpoint at a collector if the rejection noise matters.
4. **Label THIS repo immediately (init-tail).** Telemetry is now enabled, so run the per-project labeler once: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/set-otel-resource-attrs.sh"` (fail-safe, always exits 0), then read back `jq -r '.env.OTEL_RESOURCE_ATTRIBUTES // "not set"' "$PWD/.claude/settings.local.json" 2>/dev/null`.
5. Report: restart note (as above) + the per-project `service.name`/`service.version` label written by step 4 (auto-maintained going forward by the SessionStart hook; manual fallback snippet still available).

### Apply — backend 3: console (debug only)

1. Merge (same recipe, same backup/abort rules) a reduced block: `CLAUDE_CODE_ENABLE_TELEMETRY=1`, `OTEL_METRICS_EXPORTER=console`, `OTEL_LOGS_EXPORTER=console`, `OTEL_TRACES_EXPORTER=console`, `OTEL_RESOURCE_ATTRIBUTES=service.version=<plugin version>`. The OTLP-specific keys (protocol/endpoint/headers) are omitted — nothing is exported over OTLP in this mode; if they linger from a previous OTLP config, remove them in the same merge (`del`).
2. **Label THIS repo immediately (init-tail).** Telemetry is enabled in console mode too, so run the per-project labeler once: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/set-otel-resource-attrs.sh"` (fail-safe, always exits 0), then read back `jq -r '.env.OTEL_RESOURCE_ATTRIBUTES // "not set"' "$PWD/.claude/settings.local.json" 2>/dev/null`.
3. No Docker, no smoke test. Report: restart note + the per-project `service.name`/`service.version` label written by step 2 + "console output is for debugging only".

### Verify (all backends)

Re-run the Check step and show the before/after status row. Local backend additionally confirms the smoke-test trace ID it found in Langfuse.

### Subflow: `/setup observability status`

The Check + Report steps only (read-only). Include: mode, env-block keys present (names only — never print header values beyond the endpoint), container health table (with the `booting`/collector-liveness-only buckets from the dashboard check), Langfuse `/api/public/health` probe (source `$OBS_DIR/.env` first so a customized `LANGFUSE_PORT` is honored), last settings backup filename.

Also report the CURRENT repo's per-project label (read-only): `jq -r '.env.OTEL_RESOURCE_ATTRIBUTES // empty' "$PWD/.claude/settings.local.json" 2>/dev/null` — print `per-project label: service.name=<repo>,service.version=<X>` when set, or `per-project label: not set` when absent/unreadable.

### Subflow: `/setup observability remove`

1. Confirm via AskUserQuestion. Two-step teardown:
   - `docker compose -p loomwright-observability -f "$OBS_DIR/docker-compose.yml" --env-file "$OBS_DIR/.env" down` (containers only — data volumes survive).
   - Separately ask before `down -v` (DESTRUCTIVE: deletes all collected traces) and before deleting `$OBS_DIR` (contains `.env` with the keys).
2. Remove the env block from `$SETTINGS` — same backup-first + abort-on-parse rules, then `jq 'del(.env.CLAUDE_CODE_ENABLE_TELEMETRY, .env.OTEL_METRICS_EXPORTER, .env.OTEL_LOGS_EXPORTER, .env.OTEL_TRACES_EXPORTER, .env.OTEL_EXPORTER_OTLP_PROTOCOL, .env.OTEL_EXPORTER_OTLP_ENDPOINT, .env.OTEL_EXPORTER_OTLP_HEADERS, .env.OTEL_RESOURCE_ATTRIBUTES)'`. Only these 8 keys — everything else in `env` is untouched.
3. **Strip the CURRENT repo's project-level label (best-effort).** With telemetry off, also remove the auto-written per-project label from `<project>/.claude/settings.local.json` — same backup-first / parse-gate / atomic-write discipline as the user-scope merge: if `$PWD/.claude/settings.local.json` is absent or fails `jq empty`, skip (fail-safe no-op); otherwise back it up, then `jq 'del(.env.OTEL_RESOURCE_ATTRIBUTES)'` and write atomically (temp file + `mv`). Note: `remove` only knows the CURRENT repo. OTHER repos whose labels were auto-written by the SessionStart hook are left in place — they are INERT while telemetry is off (nothing is exported, so the label has no effect) and can be cleaned manually per-repo (`jq 'del(.env.OTEL_RESOURCE_ATTRIBUTES)' .claude/settings.local.json`).
4. Report what was removed (including whether the current-repo label was stripped) and what was kept, + restart note.

---

## Module: memory

Puts this repo's Twin memory stores — `.claude/agent-memory/`, `.supervisor/memory/`, and (behind a fail-closed gate) the findings ledger `.supervisor/postmortem/results.jsonl` — under version control **IN PLACE**, by un-ignoring them where they already sit. **No move, no symlink, no generated copy, no bridge of any kind.** Nothing moves, so the harness keeps injecting agent memory from its own fixed path and every `memory: project` agent still receives its store from the unchanged path.

> **The findings ledger is the THIRD store, and it is GATED.** It is structurally CROSS-REPO: a `/pr-postmortem` append lands in the CURRENT working `.supervisor/`, never in the analysed repo's, so a ledger accumulates records belonging to OTHER repos. `apply` therefore **fails closed** on it — the negation is emitted only while every record's `.repo` sits inside the resolved allowlist. Otherwise the negation is WITHHELD, the offending slugs are NAMED, readiness reports the third verdict `gated`, and **the exit code is still 0** (fail-closed in the WRITE dimension, never in the exit status). Only `results.jsonl` is re-included — every other file under `.supervisor/postmortem/` stays ignored.
>
> **Honest limits — relay these, do not soften them.** (a) The gate is evaluated **at apply time only**: a ledger that gains a foreign record after a clean apply stays un-ignored until the next apply, and a routine `git add -A` can commit it in between — tell the user to run `filter-ledger` before committing. (b) Withdrawal does **NOT** un-track an already-committed ledger; `.gitignore` only governs UNTRACKED files, so an already-published ledger needs `git rm -r --cached` plus a re-commit. (c) The gate keys on each record's `.repo` field ONLY — it does not read finding TEXT.

The deterministic engine is `${CLAUDE_PLUGIN_ROOT}/scripts/setup-memory.sh` (subcommands `check` / `apply` / `remove`, plus `allowlist` and `filter-ledger` for the repo allowlist). It is fail-safe (always exits 0), write-contained to `<project>/.gitignore` (+ one timestamped backup) and `<project>/.supervisor/config.json`, and it NEVER runs `git add` / `git rm` / `git commit`. This command owns the INTERACTIVE half — the consent-bearing offer.

**Why this exists:** those stores are gitignored in every repo, so a fresh clone, a second machine, CI and every `git worktree` checkout start COLD, and a bad curation pass is irreversible (there is no `git checkout` to undo it). Committing them also closes a real gap — committed files exist inside `git worktree` checkouts; gitignored ones do not, so workers in worktrees currently cannot see lessons or agent memory.

**The naive negation silently fails.** `.claude/` + `!.claude/agent-memory/` looks correct and does nothing: git cannot re-include a file whose parent DIRECTORY is excluded. The working form excludes the directory's CONTENTS (`.claude/*` + `!.claude/agent-memory/`), which leaves the directory traversable. Both forms are asserted in `test-setup-memory.sh` — the failure is proven by test, not by comment. Any pre-existing bare `.claude/` / `.supervisor/` line is therefore COMMENTED OUT by apply (neutralised, not merely out-ordered) and restored verbatim by `remove`.

> **Tracked-write risk — stated here, mitigated elsewhere (deliberate).** Once `.claude/agent-memory/` is tracked, every memory write becomes a working-tree modification: it shows in `git status`, can be swept into an unrelated commit by a `git add -A` (the exact failure already recorded in project memory about concurrent heal loops), and `MEMORY.md` becomes a merge-conflict surface under parallel workers. Today that is near-theoretical (hand-written, rare). The mitigation belongs to the **memory-writer item (item 04)** — agent writes land in a gitignored proposal queue and only `/dreaming`-promoted entries touch the tracked store. **Building a proposal queue is OUT OF SCOPE for this module by design; do not add one here.**

### Check

Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-memory.sh" check` and report its cells: the `.gitignore:` gate (`ok` / `absent` / `unparseable: <reason>`), whether the managed block is present, the per-path ignore status for the intended stores and the must-stay-ignored set, how many files are tracked under each store today, the resolved `allowlist:` and its source, and the `Memory readiness:` verdict (`configured` / `gated (…)` / `not configured` / `partial (…)` / `unknown (…)` — `gated` means the two memory stores are fine and the findings ledger is deliberately WITHHELD because it holds records outside the allowlist, and the last means nothing could be probed, e.g. off a git repo). Read-only — `check` writes nothing. When `jq` is unavailable **or non-functional** the ledger row reads `not probed (jq unavailable — gate not evaluated)`: report that as UNVERIFIED, never as clean. On a repo where the negation was ALREADY applied the row instead reads the real ignore status followed by `^ PRESERVED, not re-verified` plus the reason — also UNVERIFIED, but nothing was withdrawn and no contamination is claimed (emitting a NEW negation needs an examined `pass`; WITHDRAWING an existing one needs an examined `refuse` naming real slugs).

### Report

Print what check found. For the `status` subcommand, STOP after the report — read-only, no writes, no offer.

### Offer — CONSENT-BEARING (never a silent default)

`check`'s output ends with the disclosure block the user must see BEFORE anything is written. **Show it verbatim** — do not paraphrase, summarise or shorten it — then ask. It names, in plain language: exactly which paths become version-controlled; that committing PUBLISHES (agent memory can hold proprietary architecture, internal service names or client detail, and it travels wherever the repo travels — a public repo publishes it to everyone, as does any fork or clone); that removal does NOT unpublish; and that writes become working-tree changes.

**If not configured** — use `AskUserQuestion` (cap 4 options):
- `question`: "Commit this repo's Twin memory stores to version control?"
- `header`: "Memory"
- `multiSelect`: false
- `options`:
  1. `Apply — commit the memory stores` — "Un-ignore .claude/agent-memory/, .supervisor/memory/ and — only if it holds no records from other repos — .supervisor/postmortem/results.jsonl, in place, and seed the repo allowlist. Nothing is moved, and nothing is committed by this step."
  2. `Status only` — "Re-print the report and stop (no writes)."
  3. `Cancel` — "Do nothing."

Default to NOT applying. If the user's answer is ambiguous, treat it as Cancel.

**If already configured** — do NOT re-apply silently. Offer `Status` / `Remove (stop future tracking)` / `Cancel`.

**If `gated`** — the two memory stores ARE applied and only the ledger is withheld, so this is neither "not configured" nor a failure. Relay the helper's `apply: WITHHELD` block verbatim (offending slugs + the `filter-ledger` / extend-the-allowlist remedy + the does-NOT-un-track note) and offer `Filter the ledger and re-apply` / `Leave it withheld` / `Status only`. **Never** tell the user to comment out an exclude on this path — the only surviving exclude is this module's own `.supervisor/*` line, and removing it publishes the contaminated ledger.

### Apply

1. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-memory.sh" apply` ONLY after an explicit confirm.
2. Read its **headline status line** and report it verbatim. Exactly ONE of these is printed:
   - `apply: applied` — the managed block was written; a timestamped `.gitignore.backup.<ts>` sits beside it (pid-suffixed, then counter-suffixed, if that name was already taken, so a backup never overwrites another — and if every candidate name is taken the apply ABORTS rather than clobber an existing backup), and the allowlist was seeded into `.supervisor/config.json` as a JSON ARRAY **unless an `allowlist: SKIPPED` line says otherwise** (see step 3).
   - `apply: applied (ledger negation WITHDRAWN)` — the block was written AND the findings-ledger negation was removed because foreign records appeared since the last apply. A dedicated `apply: ledger negation WITHDRAWN — <slugs>` block follows it. Relay both; never present this as a plain `applied`.
   - `apply: no-op — already configured` — nothing was written (idempotent second run).
   - `apply: no-op — the two memory stores are already configured, but the findings ledger is GATED …` — the gated form of the no-op. It is a DISTINCT headline: do not report it as `already configured`.
   - `apply: ABORTED — <reason>` — nothing was written, no partial write, no backup. Surface the reason (absent `.gitignore`, unresolved conflict markers, unbalanced managed-block sentinels, NUL bytes, non-regular file, no free backup name) and STOP. Never "repair" the file to get past an abort.
3. **Then check for the ADDITIONAL lines — they are extra output, not one of the three headlines above.** Two can appear, each CO-OCCURRING with the `applied` or `no-op` headline rather than replacing it. **Report the headline AND every additional line** — reporting only the headline would silently drop them and present a half-done apply as a success.
   - `apply: WITHHELD — …` is printed AFTER the headline when readiness is `gated`. It does NOT mean the apply failed: the two memory stores ARE applied and the findings ledger is deliberately withheld. It names the offending repo slugs, the `filter-ledger` / extend-the-allowlist remedy, and the fact that withholding does not un-track an already-committed ledger. Relay it verbatim, present the memory half as a success and the ledger half as withheld, and do NOT hand the user any "comment out the surviving exclude" advice — that advice belongs to the under-inclusion case below and would publish the contaminated ledger here.
   - `apply: WARNING — readiness is '<verdict>', not 'configured'` is printed AFTER the headline (both paths run the same post-write verify). It means the block WAS written but the negation did not take effect; the helper names each intended path still ignored and the rule that wins for it (from `git check-ignore -v`). Relay that verbatim too and do NOT present the apply as a success; the usual cause is a deeper or parent-`.gitignore` exclude the rewriter does not neutralise.
   - `allowlist: SKIPPED — <reason>` means the `.gitignore` half succeeded but `.supervisor/config.json` was left UNCHANGED, so the allowlist was NOT seeded (the helper still exits 0 — the skip is fail-safe, never fatal). Seeding runs on both the applied and the no-op path, so this line can accompany either headline. Surface the reason and tell the user the allowlist still needs seeding by hand. Reasons: `jq` not available; the config exists but is not valid JSON; no git remote to default from and nothing configured; the merge/create could not be written; and — the backup-first contract holding here exactly as it does for `.gitignore` — `could not write a backup of <cfg>; refusing to rewrite it unbacked-up (unchanged)`.
4. **The stores are only UN-IGNORED — nothing is committed.** Tell the user to review `git status --short .claude/agent-memory .supervisor/memory .supervisor/postmortem/results.jsonl` and commit deliberately (the ledger is the third store and is NOT under either memory directory, so a two-path `git status` would let it be committed unreviewed). This command never stages or commits on their behalf.

**The repo allowlist** (`.setup_memory.repo_allowlist` in `<project>/.supervisor/config.json`) is a **JSON ARRAY, never a string**, and is never derived from the live remote at read time. A repo RENAME is the documented reason: records written before a rename carry the old slug, so a live-remote-keyed filter would silently drop the older half of a ledger. It defaults to the CURRENT remote's `owner/repo` on a fresh install (never a hardcoded owner — the plugin ships to other users) and is extended by hand afterwards:
```bash
jq '.setup_memory.repo_allowlist += ["owner/old-name"]' .supervisor/config.json
```
`setup-memory.sh filter-ledger --ledger <path>` applies it to a JSONL ledger and is the reusable predicate for any later item that decides which records belong to this repo. An EMPTY allowlist retains NOTHING (fail-closed), and a record with no `repo` field is excluded as unattributable.

### Verify

Re-run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-memory.sh" check` and show the before/after: each intended path flipped to `committable`, each unintended path (`.claude/worktrees/`, `.claude/settings.local.json`, `.supervisor/logs/`, and every file under `.supervisor/postmortem/` other than `results.jsonl`) still `ignored`, and the verdict now `configured` **or** `gated`. **`gated` is a SUCCESS outcome, not a failure** — the two memory stores are committable and the ledger is correctly withheld; say exactly that rather than claiming the apply did not work. Success is claimed ONLY after that re-check.

### Subflow: `/setup memory remove`

1. Confirm via `AskUserQuestion` first.
2. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-memory.sh" remove` — it deletes the managed block, restores the original bare excludes verbatim, and re-reports readiness.
3. **Relay the helper's history warning verbatim — do not soften it.** Removal stops FUTURE tracking; it does NOT unpublish. Git history retains everything already committed, on this clone and on every remote, fork and clone that has it; if it was pushed, it is published. Purging genuinely published content requires a history rewrite (e.g. `git filter-repo`) plus a force-push of every affected ref, and anything secret that was exposed must be assumed compromised and rotated.
4. Already-TRACKED files stay tracked — `.gitignore` only affects untracked files. The helper prints the current tracked counts for **all three** stores and the exact `git rm -r --cached .claude/agent-memory .supervisor/memory .supervisor/postmortem/results.jsonl` the user can run themselves. **Never run it for them.**

### Idempotency note

A second `/setup memory` on an already-applied repo reports "already configured" and writes nothing — apply compares the file it WOULD write against the file on disk byte-for-byte before touching anything, and an existing non-empty allowlist is never overwritten (a hand-added pre-rename slug must survive re-apply).

**Restated precisely, now that the ledger gate exists:** the managed block is a pure function of (the pre-existing `.gitignore` contents, **the ledger gate outcome**). For a FIXED gate outcome it is byte-stable across runs, which is what idempotency requires — but the gate outcome is an INPUT. A repo that applied cleanly and LATER gains a foreign-slug record WILL legitimately rewrite `.gitignore` on the next apply to withdraw the ledger negation. That is correct fail-closed behaviour, it is ANNOUNCED (never a bare `apply: applied`), and it does not un-track an already-committed ledger.

---

## Module: rules

Gives a **cold-start** repo a non-empty `.agent/rules/` house-rules store by seeding a small set of **portable** conventions — ones true of any repository, in any language, with any layout. `/dreaming` is the other half of this substrate and the opposite direction: it DISTILS rules from what a repo has actually accumulated (ledger findings, the agent-memory corpus). A fresh repo has accumulated nothing, so that path yields an empty batch and the store stays cold forever; this module closes that gap without pretending anything was measured.

The deterministic engine is `${CLAUDE_PLUGIN_ROOT}/scripts/seed-rules.sh` (subcommands `check` / `seed`, plus `--confirm` to apply and `--root <dir>` to point at another repo). It authors every rule through the sole writer `add-rule.sh`, never by hand. This command owns the INTERACTIVE half — the offer and the one confirm.

> **SEEDED IS NOT LEARNED, and the distinction is DATA.** Every seeded rule is stamped `provenance.source=setup:rules-seed`. That value IS the mechanism: a reader separates a shipped default from a rule `/dreaming` earned off this repo's own findings (which carries `dreaming:<session_id>`) by reading `provenance.source` and nothing else. **No new member is added to the rule object and no sidecar file is written** — the schema is frozen at 7 always-present members (`id`, `category`, `statement`, `enforcement`, `check`, `provenance`, `applies_to`) plus the optional `supersedes`, and `add-rule.sh` rejects any unknown argument outright. When you report the result, say plainly that these rules are **seeded defaults, not something the tool learned here** — the helper's own output says so on every path; relay it, do not paraphrase it into "rules configured for your repo".
>
> **Honest limits — relay these, do not soften them.** (a) Every seed is **repo-wide** (`applies_to: null`) and that is a stated justification, not a silent default: a path glob is a claim about a directory layout, and no layout is universal, so scoping a portable rule to a path would contradict the portability that qualifies it. A rule that genuinely needs a path scope is evidence-derived — that is `/dreaming`'s job, not this module's. (b) `check` is `null` on every seed and the helper never passes `--check`: **rules are DATA, never executed**, the `rules-check.sh --no-cmd` trust boundary is unchanged, and **this module adds NO gate** — seeds are advisory and subordinate to the project's own `CLAUDE.md`. (c) The store is committed and human-curated, so a seed you disagree with is meant to be edited or retracted (`/rules`), not tolerated. (d) **Those two curation actions are NOT equally durable, and the user must be told which is which.** An EDIT is durable: presence is keyed on the seeded stamp for the seed's category, not on the statement text, so a rewritten seed is reported `ALREADY SEEDED (curated)` and a later run never touches it. A RETRACT is **not** a permanent opt-out: it deletes the object, so nothing is left carrying the stamp and a later `/setup rules` re-offers and rewrites that seed at exit 0 with no record of the refusal. Recording a refusal would need a store the frozen schema has no room for (a sidecar would be the same freeze violation one layer out), so the honest advice is: to keep a seed out, edit it down to what you do want, or do not re-run the module.

### Check

Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/seed-rules.sh" check` and report its cells: the per-seed `seed: ABSENT` / `seed: ALREADY SEEDED` lines (each with its category and statement) and the `seeds: N total · N already seeded · N absent` summary. **Read-only — `check` invokes no writer and creates nothing, not even the store directory.** It exits 0; a non-zero exit means it could not run (exit 2 = missing `jq`, or a usage error), and that is `unknown`, never a not-seeded claim.

### Report

Print what check found, including the helper's seeded-not-learned disclosure block. For the `status` subcommand, STOP after the report — read-only, no writes, no offer.

### Offer

Branch on what Check found (never re-seed silently):

**If any seed is ABSENT** — use `AskUserQuestion` (cap 4 options):
- `question`: "Seed this repo's rules store with portable conventions?"
- `header`: "Rules"
- `multiSelect`: false
- `options`:
  1. `Seed them` — "Write the absent portable rules to .agent/rules/ via add-rule.sh, each stamped provenance.source=setup:rules-seed so they read as SEEDED, not learned from this repo. Advisory only — nothing is gated, nothing is executed, nothing is committed."
  2. `Plan only (show me what would be written)` — "Print the exact rule object for each absent seed and write nothing."
  3. `Cancel` — "Do nothing."

Default to NOT seeding. If the answer is ambiguous, treat it as Cancel.

**If 0 are absent** — do NOT re-run apply. Report "already seeded" and offer `Status` / `Cancel` only. There is no reconfigure (a second seed on a still-seeded repo is a no-op by design, edits included) and no `remove` (retracting a rule is `/rules` territory — `add-rule.sh --retract`, which is a per-rule human decision, not a module teardown).

(A bare `/setup rules` with NO subcommand lands here and branches exactly as above. A `status` subcommand never reaches this phase — Report already stopped it.)

### Apply

1. On `Plan only`, run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/seed-rules.sh" seed` — it prints the full rule object each absent seed WOULD produce and writes nothing. Then return to the Offer.
2. On `Seed them`, and ONLY after that explicit confirm, run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/seed-rules.sh" seed --confirm`.
3. **Which invocation writes, stated so nothing is assumed.** `add-rule.sh` writes on `--confirm`, and otherwise **prompts `Confirm write? [y/N]` and writes on `y` whenever stdin and stdout are both a TTY** — which is exactly how `/setup` runs. A missing `--confirm` is therefore not by itself a dry run. The helper closes that by redirecting **every** writer invocation's stdin from `/dev/null` on **both** paths, which makes the prompting branch unreachable: so `seed-rules.sh` itself NEVER prompts, N seeds can never fire N prompts at the user's terminal, and the consent lives here, once, in the Offer above. Do not add a second prompt, and do not pass `--confirm` on the plan path.
4. Read the helper's summary line and report it verbatim — `written: N · failed: M` (apply) or `planned: N · failed: M · NOTHING WAS WRITTEN` (plan). Its exit contract: **0** = every seed handled (reported / planned / written / already present); **1** = at least one seed the writer REFUSED (the per-seed `seed: FAILED` line names it) — surface those and do NOT report success; **2** = usage error or missing dependency (`jq`, or the writer itself) — nothing was attempted.
5. **Seeding is not committing.** The store is a committed, version-controlled surface, but this command never stages anything. Tell the user to review `git status --short .agent/rules` and commit deliberately.

### Verify

Re-run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/seed-rules.sh" check` and show the before/after: each previously-absent seed now `ALREADY SEEDED`, and `0 absent` in the summary. Success is claimed ONLY after that re-check — and it is claimed as *"N portable rules seeded"*, never as *"N rules learned from your repo"*.

### Idempotency note

A second `/setup rules` on a **seeded and unretracted** repo reports "already seeded" and writes nothing: the helper skips a seed that is already PRESENT in a well-formed `.agent/rules/*.json` array, checked BEFORE the writer is invoked, so no duplicate is created and the run still exits 0. That skip is deliberate rather than left to the writer's own duplicate check — that check REFUSES with a non-zero status, which would turn a correct, already-configured second run into a reported failure.

**PRESENT is keyed on the seeded stamp, not on the statement text**, and the difference is what makes editing safe. A rule counts as present when its statement matches the seed EXACTLY (any provenance) **or** when it carries `provenance.source=setup:rules-seed` for that seed's category — matched on `.category` or on the frozen `<category>-` id prefix. So **an edited seed is recognised as curated, not missing**: `check` reports it `ALREADY SEEDED` and marks the match `curated`, a re-run writes nothing, and your wording survives byte-for-byte. (Keying on the exact statement instead made the skip strictly narrower than the near-identical refusal it exists to avoid: one edited word made the seed look absent, the writer then refused it as a near-duplicate, and the module reported a hard failure on every subsequent run of a correctly-configured repo.)

**RETRACT IS NOT A PERMANENT OPT-OUT — say so rather than implying idempotence covers it.** `add-rule.sh --retract` removes the rule object outright, so nothing is left carrying the stamp: a later `/setup rules` re-offers that seed and writes it back at exit 0, with no record that you rejected it. That asymmetry is real and worth stating to the user plainly — **editing a seed is durable curation; retracting one is not.** It is a known limit rather than an oversight: recording a refusal needs somewhere to store it, and the rule schema is frozen at 7 members while a sidecar would be the same freeze violation one layer out. To keep a seed out today, **edit it down to what you do want** (durable), or simply do not re-run the module.

---

## Module: statusline

Wires Loomwright's one-line run report into the host's status-line surface, so a long run stops being opaque without the user opening `.supervisor/state.md` by hand. **Opt-in, and it is the only module that writes the USER-SCOPE settings document.**

The line is assembled from facts that already exist and nothing else:

```
Loomwright · EXECUTE · feature/status-line · 3/4 · 2m ago
```

phase · branch · COMPLETED-over-total subtasks · how long ago the newest session-log record was written. **Every field is omitted rather than guessed** when its source is absent, and with no state file at all the line reads `Loomwright · no run state`.

> **There is deliberately NO "currently running agent" field, and that absence is the honest answer rather than a gap.** Inferring it would mean reading the recency of some other record and calling that liveness — a log line proves something was written, never that anything is running now. The emitter that would have made such a field truthful was investigated and closed NO-GO, so no spawn event exists in any log to read. `test-status-line.sh` asserts the absence mechanically, in the rendered output AND as a source grep, so this paragraph cannot rot into a claim the code does not back.

> **Time is read from the record, never from the filesystem.** The age comes from the log line's own `ts` field, parsed try-BSD-then-GNU and validated numeric before any arithmetic; the field is omitted when neither flavour parses it. `stat` is never invoked — `stat -f %m` is BSD and *succeeds with garbage* on GNU/Linux, which would put a plausible wrong number on screen rather than failing visibly.

The deterministic engine is `${CLAUDE_PLUGIN_ROOT}/scripts/setup-statusline.sh` (subcommands `check` / `apply` / `remove`). It is fail-safe (always exits 0 — "fails closed" here means refuse-to-write plus a named-reason status line, never a non-zero exit), write-contained to the user-scope settings document (+ one timestamped backup), and it never touches a project file. The renderer itself is `${CLAUDE_PLUGIN_ROOT}/scripts/status-line.sh` — read-only, dependency-free, and it always exits 0. This command owns the INTERACTIVE half.

### Check

Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-statusline.sh" check` and report its cells: the settings path, whether the renderer exists, the `settings parse:` gate (`ok` / `absent` / `UNPARSEABLE`), the `statusLine:` cell (absent / installed by this plugin / **NOT installed by this plugin**, with the existing value shown), the `restore record:`, and the `Statusline readiness:` verdict (`configured` / `not configured` / `foreign (…)` / `unknown (…)`). Read-only — `check` writes nothing. `unknown` means nothing could be probed (missing `jq`, or a settings document that does not parse): report it as UNVERIFIED, never as clean.

### Report

Print what check found. For the `status` subcommand, STOP after the report — read-only, no writes, no offer.

### Offer — CONSENT-BEARING when something already exists

**If `not configured`** — use `AskUserQuestion` (cap 4 options):
- `question`: "Wire Loomwright's status line into your settings?"
- `header`: "Statusline"
- `multiSelect`: false
- `options`:
  1. `Apply` — "Set statusLine to Loomwright's one-line run report. Your settings file is backed up first, and every unrelated key is preserved."
  2. `Status only` — "Re-print the report and stop (no writes)."
  3. `Cancel` — "Do nothing."

**If `foreign`** — this is the case that matters, and it is neither configured nor unconfigured. **Do NOT offer a plain "Apply".** Report the existing value verbatim, state plainly that applying would REPLACE the user's own status line, and offer:
  1. `Replace it` — "Install Loomwright's status line. Your current one is recorded under `.loomwrightStatusLinePrior` and `/setup statusline remove` restores it verbatim." Runs the engine **with `--replace`**.
  2. `Leave mine alone` — "Change nothing." (the default; treat any ambiguous answer as this)
  3. `Status only` — "Re-print the report and stop."

Default to NOT applying in both cases. **Never pass `--replace` on the strength of a generic "yes"** — it is earned only by the user choosing `Replace it` against a report that named their existing value.

### Apply

1. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-statusline.sh" apply` (adding `--replace` ONLY per the offer above) after an explicit confirm.
2. Read its **headline status line** and report it verbatim. Exactly ONE of these is printed:
   - `apply: applied` — the status line was installed; a timestamped backup path is printed on the following line.
   - `apply: applied (REPLACED a pre-existing statusLine …)` — followed by the `replaced:` value. Relay BOTH; never present this as a plain `applied`, and tell the user how to get their line back.
   - `apply: applied (created …)` — there was no settings document; one was created holding just the status line.
   - `apply: no-op — already configured` — nothing was written (idempotent second run), and no second backup was made.
   - `apply: WITHHELD — a statusLine this plugin did not write is already configured` — followed by the existing value. **Nothing was written and no backup was made.** This is the fail-closed path, not a failure: relay it and go back to the Offer step. Never re-run with `--replace` to "get past" it.
   - `apply: ABORTED — <reason>` — nothing was written, no partial write, no backup. Reasons: the settings document exists but is not valid JSON; `jq` unavailable or non-functional; the renderer script is missing; no free backup name. Surface the reason and STOP. **Never "repair" the settings document to get past an abort** — a hand-edited file is the user's.
3. Tell the user the status line appears on the next session (the host reads `statusLine` at startup).

### Verify

Re-run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-statusline.sh" check` and show the before/after: the verdict now `configured`, the command pointing at `status-line.sh`, and the backup path. Success is claimed ONLY after that re-check. As a live smoke test, run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/status-line.sh"` in the project and show the actual line — it exits 0 even with no run in flight.

### Subflow: `/setup statusline remove`

1. Confirm via `AskUserQuestion` first.
2. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-statusline.sh" remove`. It restores the status line that was there BEFORE this module applied (recorded at apply time under `.loomwrightStatusLinePrior`), or deletes ours outright when there was none, then drops the record. Backup-first, like apply.
3. **`remove` REFUSES a status line this plugin did not write** — it prints `remove: REFUSED` and changes nothing. That is correct: a foreign status line is not this module's to remove, and the user should edit it themselves.

### Idempotency note

A second `/setup statusline` on an already-configured setup reports `no-op — already configured`, writes nothing and makes no second backup — apply computes the document it would write and byte-compares it against the one on disk before touching anything. **The restore record survives re-application unchanged:** a second apply must never recapture the current (ours) value as "the prior one", or `remove` would hand the user back a copy of the very thing it was undoing instead of their own status line.

---

## Module: telemetry

DELEGATES — print `Telemetry is managed by /telemetry (consent logic lives there and is not duplicated).`, show the consent state from the dashboard check, and tell the user to run `/telemetry enable | disable | status | test`.

**When to auto-run the enable flow (and when NOT to):** only when telemetry was the EXPLICIT target — i.e. invoked directly as `/setup telemetry`. On that explicit path you may execute the `/telemetry enable` flow by following `${CLAUDE_PLUGIN_ROOT}/commands/telemetry.md` directly (the consent-file write is performed by telemetry.md's own enable recipe, permitted under telemetry.md's authority). When telemetry is reached via the no-arg dashboard's bundled **Other integrations (telemetry · webhook · Beads · MySQL MCP)** option, print the delegation message + consent state ONLY and point the user to `/telemetry enable` — do NOT auto-launch the interactive enable / repo-selection flow from the bundle (a user who picked the bundle for webhook/Beads/MySQL must not get a surprise telemetry consent prompt).

What is forbidden on every path is `/setup`'s OWN logic touching `.supervisor/telemetry-consent.json` — never read-modify-write it, duplicate the consent prompt, or write it outside of executing telemetry.md's recipe verbatim.

## Module: notifications

Status + guidance only. Report: desktop notifications fire via always-on plugin hooks (`PreToolUse[AskUserQuestion]` + `Notification` → `notify-desktop.sh`) — nothing to configure. The webhook-POST variant of gate notifications additionally needs `LOOMWRIGHT_WEBHOOK_URL` → point to the webhook module.

## Module: webhook

Status + guidance only. Report whether `LOOMWRIGHT_WEBHOOK_URL` is set (never print the full URL). Guidance: export it in the shell profile (user choice of Slack/Discord/custom receiver); consumed by `send-webhook.sh` on supervisor completion and decision gates, and by `/autonomous --notify`. This command does NOT edit shell profiles.

## Module: beads

Status + guidance only. Report `bd` availability and `.beads/` presence. Guidance: Beads is optional and used only by Orchestrator / Product Owner; install per the Beads project docs, then `bd init` in the repo. This command does NOT install software.

## Module: mysql-mcp

Status + guidance only. Report which of `DB_HOST`, `DB_USER`, `DB_PASS`, `DB_NAME` (+ optional `DB_PORT`) are unset — names only, never values. Guidance: the read-only MySQL MCP server is provided by the separate `mysql-mcp@atelier` plugin (`/plugin install mysql-mcp@atelier`) and resolves these from the environment; set them in the shell profile or project `.mcp.json` env. This command does NOT write credentials anywhere and does NOT install the plugin.

---

## Constraints (every module)

- The ONLY files this command's OWN logic may write:
  - `$OBS_DIR/*` (the copied stack + generated `.env`),
  - `$HOME/.claude/settings.json` — user-scope env, via the merge recipe, backup-first,
  - `<project>/.claude/settings.local.json` — project-scope, gitignored-by-convention; sanctioned for the `remove` subflow's `jq 'del(.env.OTEL_RESOURCE_ATTRIBUTES)'` (backup-first, like the user-scope merge) and — via the invoked `set-otel-resource-attrs.sh` script — the init-tail per-project label. The script write uses parse-gate (`jq empty`, no clobber on unparseable) + atomic tmp-file-`mv` + idempotent skip-if-unchanged; it does NOT back up (the merge is single-key and idempotent, so there is nothing destructive to roll back), and
  - **memory** (`/setup memory`) — **a `.gitignore` write class no other module has, so it gets its own line:** (a) `<project>/.gitignore`, rewritten ONLY via `setup-memory.sh apply` / `remove`, and ONLY after an explicit consent-bearing confirm. The write is backup-first (a timestamped `<project>/.gitignore.backup.<ts>` sibling, pid-suffixed on a same-second collision so one backup can never overwrite another), atomic (tmp-file + `mv`), confined to a sentinel-delimited managed block plus the commenting-out of pre-existing directory-shaped `.claude/` / `.supervisor/` excludes — including the recursive `**` family (`.claude/**`, `**/.claude/`, `**/.claude/**`), but never the `X/*` working form — and **idempotent by byte-comparison** — apply computes the file it would write and does nothing when it already matches. It **ABORTS without any write and without a backup** on an absent, non-regular, symlinked, NUL-containing, conflict-marked, or sentinel-unbalanced `.gitignore` — never a partial write, never a blind repair; and (b) `<project>/.supervisor/config.json` key `.setup_memory.repo_allowlist` — a jq merge that is parse-gated (`jq empty`), backup-first, atomic, preserves every unrelated key, stores a JSON **array**, and never overwrites an existing non-empty one. The memory module touches NO `~/.claude/settings.json` and nothing under `~/.claude/`, and it **NEVER runs `git add`, `git rm`, `git commit` or any other history-touching git command** — un-ignoring is not committing, and un-committing is the user's own `git rm --cached`.

  - **statusline** (`/setup statusline`) — **the only module whose write domain is the USER-SCOPE settings document, so it gets its own line:** the user-scope settings JSON ONLY (the same path Pattern 3 governs), written ONLY via `setup-statusline.sh apply` / `remove`, and ONLY after an explicit confirm. The write is backup-first (a timestamped `.backup.<ts>` sibling, pid- then counter-suffixed on a same-second collision so one backup can never overwrite another, and an apply that cannot obtain a free backup name ABORTS rather than write unbacked-up), parse-gated (`jq empty` — an unparseable document ABORTS with **no write and no backup**), atomic (tmp-file + `mv`), and **idempotent by byte-comparison** — apply computes the document it would write and does nothing when it already matches. It touches exactly TWO keys, `statusLine` and the namespaced restore record `loomwrightStatusLinePrior`; every other key at every level is preserved, which `test-setup-statusline.sh` asserts by DIFFING the two documents with those two keys removed rather than by spot-checking. **NOTHING ELSE under the user's `~/.claude/` directory** — no sidecar state file, no project write, no `.gitignore` write, and no history-touching git command. A pre-existing `statusLine` this plugin did not write is PRESERVED and reported; replacing it requires the explicit `--replace` flag, and the replaced value is recorded so `remove` restores it verbatim.

  - **rules** (`/setup rules`): `<project>/.agent/rules/<category>.json` ONLY, written ONLY via `seed-rules.sh seed --confirm` (which authors every rule through the sole writer `add-rule.sh`), and ONLY after an explicit confirm. `check` and a bare `seed` write NOTHING — every writer invocation is stdin-detached, so this module NEVER prompts and an unconfirmed run cannot write. No `~/.claude/` write of any kind, no `.gitignore` write, no `git add`/`rm`/`commit`, and no rule object built by hand.

  Everything else is read-only or delegated. One delegation carve-out: when the telemetry module executes telemetry.md's enable recipe (see "Module: telemetry"), that recipe writes `.supervisor/telemetry-consent.json` under telemetry.md's authority — setup.md's own logic still never touches that file.
- Idempotent: re-running any flow against an already-configured module reports "already configured" and offers status/reconfigure/remove — it never blind-overwrites, and never regenerates an existing `.env`.
- Abort (never half-write) if `~/.claude/settings.json` exists but fails to parse — tell the user the path and the backup convention, and stop.
- Never print secret VALUES (webhook URL, DB_PASS, header values, generated keys) except the local-only Langfuse dashboard login at the end of a successful local init.
- All plugin asset references via `${CLAUDE_PLUGIN_ROOT}` — no repo-relative paths.
- Always end with the 1-line `Setup:` summary.

## Examples

```
$ /setup
## /setup — module status
| Module        | Status                          | Configure with       |
| observability | not configured                  | /setup observability |
| telemetry     | enabled (target=acme/agents)    | /setup telemetry     |
...
[AskUserQuestion multi-select] → observability
[... full local init flow runs, smoke test passes ...]
Setup: observability configured (local Langfuse, 7/7 healthy, smoke trace landed). Restart Claude Code sessions to start emitting.
```

```
$ /setup observability status
[mode: local stack · env block: 8/8 keys · containers: 7/7 healthy · Langfuse health: OK]
Setup: observability healthy (local stack); dashboard at http://localhost:3000.
```
