---
description: Umbrella setup command — status dashboard plus guided configuration for every optional plugin capability — observability (local Langfuse + OTel collector), Twin cold-start bootstrap, telemetry, notifications, webhook, Beads, MySQL MCP
---

# Command: /setup

## Usage

```
/setup                      # Status dashboard (one row per module) + multi-select "what do you want to configure?"
/setup observability        # Observability module directly: init | status | remove
/setup twin                 # Twin readiness status + guided cold-start bootstrap (graph + bridge + CLAUDE.md): status | (no-arg → bootstrap)
/setup telemetry            # DELEGATES to /telemetry (no consent logic duplicated here)
/setup notifications        # Status + guidance (notification hooks are always-on)
/setup webhook              # Status + guidance (AI_AGENT_MANAGER_WEBHOOK_URL)
/setup beads                # Status + guidance (bd CLI + .beads/)
/setup mysql-mcp            # Status + guidance (DB_* env for the bundled read-only MySQL MCP)
```

## Parameters

- **module** (optional): one of `observability`, `telemetry`, `notifications`, `webhook`, `beads`, `mysql-mcp`, `twin`.
  - If omitted: run the full status dashboard, then offer configuration via `AskUserQuestion` (multi-select).
  - If unrecognised: print this usage block and stop.
- **observability subcommand** (optional, second positional arg): `init` | `status` | `remove`. If omitted, the module's check step decides — unconfigured → offer `init`; configured → offer `status` / `remove` / reconfigure.
- **twin subcommand** (optional, second positional arg): `status` = read-only readiness report (no writes). If omitted, the module's check step decides — un-bootstrapped → offer to bootstrap; bootstrapped → offer `status` / re-bootstrap. **`remove` is explicitly N/A for v1** — Twin artifacts (graph / bridge / CLAUDE.md) are committed knowledge, not per-user config, so teardown is out of scope (a deliberate omission, not an oversight).

## What This Does

`/setup` is the single entry point for checking and configuring the plugin's optional capabilities. Every module follows the same contract (authority: the `setup` skill, read at Step 0):

> **check → report → offer → apply → verify** — idempotent, and never blind-overwrite.

Settled design facts (do not re-litigate at runtime):

- **The plugin emits NO spans itself.** Claude Code's native OpenTelemetry telemetry (`CLAUDE_CODE_ENABLE_TELEMETRY=1`) is the only emitter. `/setup observability` configures *where those signals go*, nothing more.
- **Langfuse's OTLP endpoint (`/api/public/otel`) ingests TRACES ONLY.** Metrics and logs are not ingested by Langfuse. The bundled collector terminates metrics/logs in a debug exporter so senders never see export errors. This is documented behavior, not worked around.
- **Assets are COPIED at init time** from `${CLAUDE_PLUGIN_ROOT}/scripts/otel/` to `~/.claude/ai-agent-manager/observability/`; `docker compose` always runs against the copy (the plugin install dir stays pristine and survives plugin updates).
- **Env changes go in user-scope `~/.claude/settings.json`** under the `env` key via **jq deep-merge** — unrelated keys are never touched, a **timestamped backup is written first**, and the flow **aborts (never half-writes) if the existing file fails to parse**.
- `/telemetry` (GitHub-issues telemetry) is a separate, unchanged command; `/setup telemetry` delegates to it.

---

# Agent Prompt

You are handling the `/setup` slash command inline on the main thread. Parse the FIRST positional argument as the module and the SECOND (observability only) as the subcommand.

## Step 0 — Load the protocol authority (every invocation)

1. Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md`. It is the authority for the module contract, the module registry, the settings-merge rules, and the smoke-test recipe. Execute its recipes verbatim where this prompt references them.
2. Resolve shared paths once via Bash:
   ```bash
   SETTINGS="$HOME/.claude/settings.json"
   OBS_DIR="$HOME/.claude/ai-agent-manager/observability"
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
     docker compose -p ai-agent-manager-observability -f "$OBS_DIR/docker-compose.yml" --env-file "$OBS_DIR/.env" ps -q \
       | xargs docker inspect -f '{{.Name}} {{.State.Health.Status}}' 2>/dev/null
     ```
     Bucket the reported states before choosing the cell: if any container reports `starting`, the stack is **booting** (first boot can take ~10 min — image pulls + ClickHouse migrations), NOT down — surface that distinctly so a just-launched `init` in another pane doesn't read as a failure. **Collector caveat (liveness-only):** `otel-collector`'s healthcheck is `--version` (the contrib image is distroless — no in-container HTTP probe), so a `healthy` collector cell proves the process is *up*, not that it bound `:4318` or is actually ingesting. True readiness is confirmed only by the `init` smoke test (Pattern 6); the dashboard MUST NOT upgrade "N/7 healthy" to "ingesting."
   - Status cell: `configured — local stack N/7 healthy (collector liveness-only)` | `configured — local stack booting (M/7 healthy, K starting)` | `configured — external endpoint` | `configured — console debug` | `partial — env block present, stack down/missing` | `not configured`.
2. **telemetry** — read `.supervisor/telemetry-consent.json` (user-project root). `always_allow` + repo → `enabled (target=<owner/repo>)`; `no` → `disabled`; absent/malformed → `unset`.
3. **notifications** — always-on via plugin hooks (desktop banners at human-decision gates); status cell is `active (built-in hooks)`. No check command needed — note that the webhook variant additionally requires the webhook module below.
4. **webhook** — `[ -n "${AI_AGENT_MANAGER_WEBHOOK_URL:-}" ]`. Status: `set` / `not set`. NEVER print the URL value (it may embed a token) — print only `set (host: <hostname-only>)`.
5. **beads** — `command -v bd >/dev/null 2>&1` and `[ -d .beads ]`. Status: `ready` / `bd installed, repo not initialised` / `not installed`. Note: only Orchestrator/Product Owner use Beads — optional.
6. **mysql-mcp** — check `DB_HOST`, `DB_USER`, `DB_PASS`, `DB_NAME` env vars are non-empty (`DB_PORT` optional). Status: `configured` / `missing: <names of unset vars>`. NEVER print values — names only.
7. **twin** — run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-twin.sh" check` and read its output (the `Twin readiness:` verdict plus the per-cell `graph:` / `bridge:` / `CLAUDE.md:` lines). Never guess — every cell is derived from this real probe (the helper is fail-safe and always exits 0). Derive a compact status cell: verdict `bootstrapped` → `bootstrapped`; verdict `needs bootstrap` → name the gap from the cells, e.g. `needs bootstrap (graph absent)` when `graph: absent`, `needs bootstrap (stale graph)` when `graph: present (stale …)`, or `needs bootstrap (CLAUDE.md absent)` / `needs bootstrap (bridge absent)` as applicable.

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
| twin          | <derived>                               | /setup twin           |
```

Then use `AskUserQuestion`. **`AskUserQuestion` accepts at most 4 options**, so do NOT emit one option per unconfigured module (a fresh machine has many unconfigured modules → an invalid call). Use this fixed ≤4-option set — the two modules with real apply flows (observability + twin) individually, the four status/guidance-or-delegation-only modules (telemetry · webhook · Beads · MySQL MCP) folded into one, plus an opt-out:
- `question`: "Which would you like to configure now?"
- `header`: "Configure"
- `multiSelect`: true
- `options` (exactly these, in order; append each module's current status to its description):
  1. **observability** — full local-Langfuse / existing-endpoint / console init flow.
  2. **twin** — Twin cold-start bootstrap: detect/refresh the code graph (guide if `graphify` absent), rebuild the bridge, validate/scaffold CLAUDE.md.
  3. **Other integrations (telemetry · webhook · Beads · MySQL MCP)** — print status + setup guidance / delegation for these (telemetry delegates to `/telemetry`; webhook · Beads · MySQL MCP are guidance-only; `notifications` is always-on and needs no action).
  4. **Nothing — just checking** — stop with the summary line.

Run the corresponding module flow (below) for each selection, in the order listed. For option 3, run the `telemetry` delegation block plus the `webhook`, `beads`, and `mysql-mcp` status/guidance blocks in turn. If "Nothing", stop with the summary line.

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
   - Project identity: `COMPOSE_PROJECT_NAME` (= `ai-agent-manager-observability` — belt-and-braces with the explicit `-p` flag below: compose v2 loads `.env` from the `-f` file's directory, so even a bare `docker compose -f "$OBS_DIR/docker-compose.yml" …` joins the same project instead of deriving a second `observability` project from the dir basename)
   - Infrastructure: `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `CLICKHOUSE_USER`, `CLICKHOUSE_PASSWORD`, `REDIS_AUTH`, `MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD`, `LANGFUSE_S3_BUCKET`
   - Langfuse core: `LANGFUSE_SALT`, `LANGFUSE_ENCRYPTION_KEY` (64 hex chars — `openssl rand -hex 32`), `NEXTAUTH_SECRET`, `NEXTAUTH_URL`, `LANGFUSE_PORT`
   - Headless provisioning: `LANGFUSE_INIT_ORG_ID`, `LANGFUSE_INIT_ORG_NAME`, `LANGFUSE_INIT_PROJECT_ID`, `LANGFUSE_INIT_PROJECT_NAME`, `LANGFUSE_INIT_PROJECT_PUBLIC_KEY` (`pk-lf-…`), `LANGFUSE_INIT_PROJECT_SECRET_KEY` (`sk-lf-…`), `LANGFUSE_INIT_USER_EMAIL`, `LANGFUSE_INIT_USER_NAME`, `LANGFUSE_INIT_USER_PASSWORD`
   - Collector: `LANGFUSE_BASIC_AUTH` (= `base64("<public_key>:<secret_key>")`, derived from the two generated `LANGFUSE_INIT_PROJECT_*_KEY` values), `OTEL_COLLECTOR_PORT`
4. **Start the stack:**
   ```bash
   docker compose -p ai-agent-manager-observability -f "$OBS_DIR/docker-compose.yml" --env-file "$OBS_DIR/.env" up -d
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

7. **Smoke test BEFORE reporting success** — execute the skill's smoke-test recipe: emit a test span via `curl` to `http://localhost:<OTEL_COLLECTOR_PORT>/v1/traces`, then poll the Langfuse API (`/api/public/traces`, Basic auth `pk:sk` from `.env`) until the span lands (up to ~3 minutes — ingestion is async through the worker + ClickHouse). If it never lands: report FAILURE with the collector logs (`docker compose -p ai-agent-manager-observability logs otel-collector --tail 50`) — the env merge stays in place (it is correct), but success is NOT claimed.
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
   - `docker compose -p ai-agent-manager-observability -f "$OBS_DIR/docker-compose.yml" --env-file "$OBS_DIR/.env" down` (containers only — data volumes survive).
   - Separately ask before `down -v` (DESTRUCTIVE: deletes all collected traces) and before deleting `$OBS_DIR` (contains `.env` with the keys).
2. Remove the env block from `$SETTINGS` — same backup-first + abort-on-parse rules, then `jq 'del(.env.CLAUDE_CODE_ENABLE_TELEMETRY, .env.OTEL_METRICS_EXPORTER, .env.OTEL_LOGS_EXPORTER, .env.OTEL_TRACES_EXPORTER, .env.OTEL_EXPORTER_OTLP_PROTOCOL, .env.OTEL_EXPORTER_OTLP_ENDPOINT, .env.OTEL_EXPORTER_OTLP_HEADERS, .env.OTEL_RESOURCE_ATTRIBUTES)'`. Only these 8 keys — everything else in `env` is untouched.
3. **Strip the CURRENT repo's project-level label (best-effort).** With telemetry off, also remove the auto-written per-project label from `<project>/.claude/settings.local.json` — same backup-first / parse-gate / atomic-write discipline as the user-scope merge: if `$PWD/.claude/settings.local.json` is absent or fails `jq empty`, skip (fail-safe no-op); otherwise back it up, then `jq 'del(.env.OTEL_RESOURCE_ATTRIBUTES)'` and write atomically (temp file + `mv`). Note: `remove` only knows the CURRENT repo. OTHER repos whose labels were auto-written by the SessionStart hook are left in place — they are INERT while telemetry is off (nothing is exported, so the label has no effect) and can be cleaned manually per-repo (`jq 'del(.env.OTEL_RESOURCE_ATTRIBUTES)' .claude/settings.local.json`).
4. Report what was removed (including whether the current-repo label was stripped) and what was kept, + restart note.

---

## Module: twin

Gives a fresh repo its Twin readiness picture and a guided cold-start bootstrap (code graph + findings→community bridge + CLAUDE.md). The deterministic, mechanizable engine is `${CLAUDE_PLUGIN_ROOT}/scripts/setup-twin.sh` (subcommands `check` / `bootstrap [--run-graphify]`); this command owns the INTERACTIVE half — the `AskUserQuestion` offers, running the external `graphify .`, and the confirmed CLAUDE.md write. The helper is fail-safe (always exits 0), write-contained to `.supervisor/bridge/`, and NEVER writes CLAUDE.md or `~/.claude/` — those decisions live here.

> **`remove` is N/A for v1** — Twin artifacts (graph / bridge / CLAUDE.md) are committed knowledge, not per-user config; teardown is deliberately out of scope. There is no `/setup twin remove`.

### Check

Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-twin.sh" check` and report its readiness cells (graph present / stale / absent, bridge present, CLAUDE.md present, brain-wiki) plus the `Twin readiness:` verdict. Read-only — the `check` subcommand writes nothing.

### Report

Print what check found (the four cells + verdict). For the `status` subcommand, STOP after the report — it is read-only, no writes, no offer.

### Offer

If the module is un-bootstrapped (`Twin readiness: needs bootstrap`) OR no subcommand was given, use `AskUserQuestion` (cap 4 options):
- `question`: "Bootstrap the Twin for this repo now?"
- `header`: "Twin"
- `multiSelect`: false
- `options`:
  1. `Bootstrap now` — "Detect/refresh the code graph (guide if graphify absent), rebuild the bridge, and validate/scaffold CLAUDE.md."
  2. `Status only` — "Re-print the readiness report and stop (no writes)."
  3. `Cancel` — "Do nothing."

If the graph is absent, the `Bootstrap now` apply step owns the graphify offer (below). If the module is already bootstrapped and a non-`status` invocation reaches here, offer `Status` / `Re-bootstrap (rebuild bridge / re-validate)` / `Cancel` instead — never silently re-apply.

### Apply (bootstrap)

1. **Graph step.** Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-twin.sh" check` to see whether the graph is absent. If absent, use `AskUserQuestion` to offer running `graphify .` (note: `graphify` is the EXTERNAL user-global `/graphify` CLI/skill at `~/.claude/skills/graphify` — the command layer, NOT the helper, owns this offer):
   - On confirm AND `command -v graphify >/dev/null 2>&1` succeeds → either run `( cd "$PWD" && graphify . )` directly OR invoke `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-twin.sh" bootstrap --run-graphify` (which runs `graphify .` then ALWAYS rebuilds the bridge in the same invocation).
   - If `graphify` is NOT on PATH → print the install/run guidance (run `/graphify .` in this repo to build the code graph, then re-run `/setup twin`) and CONTINUE — NEVER hard-fail on the missing external CLI.
2. **Bridge rebuild.** Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-twin.sh" bootstrap` (WITHOUT `--run-graphify` if graphify was declined/unavailable or already run in step 1) — bootstrap ALWAYS rebuilds the bridge (`build-bridge.sh --out .supervisor/bridge`, write-contained via the explicit `--out`) in the same invocation.
3. **CLAUDE.md.**
   - If `setup-twin.sh check` reports CLAUDE.md **present**: run the `claude-md-validation` skill (advisory, non-blocking — read `${CLAUDE_PLUGIN_ROOT}/skills/claude-md-validation/SKILL.md` and apply it). Never block on its findings.
   - If CLAUDE.md is **absent**: the helper's bootstrap prints a starter skeleton to stdout. The COMMAND LAYER then OFFERS (`AskUserQuestion`) to write it, and writes `CLAUDE.md` ONLY on explicit confirm AND ONLY if the file is still absent (`[ ! -f CLAUDE.md ]`) — NEVER overwrite an existing CLAUDE.md. The helper never writes it; this command does the confirmed write.

### Verify

Re-run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-twin.sh" check` and show the before/after readiness verdict (and which cells flipped present).

### Idempotency note

A second `/setup twin` on an already-bootstrapped repo reports "already bootstrapped" and changes nothing without an explicit choice (`Re-bootstrap` rebuilds the bridge / re-validates CLAUDE.md; it never regenerates the graph or overwrites CLAUDE.md).

---

## Module: telemetry

DELEGATES — print `Telemetry is managed by /telemetry (consent logic lives there and is not duplicated).`, show the consent state from the dashboard check, and tell the user to run `/telemetry enable | disable | status | test`. If the user selected telemetry from the no-arg multi-select, execute the `/telemetry enable` flow by following `${CLAUDE_PLUGIN_ROOT}/commands/telemetry.md` directly — on that delegated path the consent-file write is performed by telemetry.md's own enable recipe and is permitted (it happens under telemetry.md's authority). What is forbidden is `/setup`'s OWN logic touching `.supervisor/telemetry-consent.json` — never read-modify-write it, duplicate the consent prompt, or write it outside of executing telemetry.md's recipe verbatim.

## Module: notifications

Status + guidance only. Report: desktop notifications fire via always-on plugin hooks (`PreToolUse[AskUserQuestion]` + `Notification` → `notify-desktop.sh`) — nothing to configure. The webhook-POST variant of gate notifications additionally needs `AI_AGENT_MANAGER_WEBHOOK_URL` → point to the webhook module.

## Module: webhook

Status + guidance only. Report whether `AI_AGENT_MANAGER_WEBHOOK_URL` is set (never print the full URL). Guidance: export it in the shell profile (user choice of Slack/Discord/custom receiver); consumed by `send-webhook.sh` on supervisor completion and decision gates, and by `/autonomous --notify`. This command does NOT edit shell profiles.

## Module: beads

Status + guidance only. Report `bd` availability and `.beads/` presence. Guidance: Beads is optional and used only by Orchestrator / Product Owner; install per the Beads project docs, then `bd init` in the repo. This command does NOT install software.

## Module: mysql-mcp

Status + guidance only. Report which of `DB_HOST`, `DB_USER`, `DB_PASS`, `DB_NAME` (+ optional `DB_PORT`) are unset — names only, never values. Guidance: the bundled MySQL MCP server is read-only and resolves these from the environment; set them in the shell profile or project `.mcp.json` env. This command does NOT write credentials anywhere.

---

## Constraints (every module)

- The ONLY files this command's OWN logic may write:
  - `$OBS_DIR/*` (the copied stack + generated `.env`),
  - `$HOME/.claude/settings.json` — user-scope env, via the merge recipe, backup-first,
  - `<project>/.claude/settings.local.json` — project-scope, gitignored-by-convention; sanctioned for the `remove` subflow's `jq 'del(.env.OTEL_RESOURCE_ATTRIBUTES)'` (backup-first, like the user-scope merge) and — via the invoked `set-otel-resource-attrs.sh` script — the init-tail per-project label. The script write uses parse-gate (`jq empty`, no clobber on unparseable) + atomic tmp-file-`mv` + idempotent skip-if-unchanged; it does NOT back up (the merge is single-key and idempotent, so there is nothing destructive to roll back), and
  - **twin** (`/setup twin`): (a) `<project>/.supervisor/bridge/` — written ONLY via `setup-twin.sh`'s `build-bridge.sh --out "$repo/.supervisor/bridge"` call (the explicit `--out` means a repo-local `.supervisor/config.json .build_bridge.out` can NOT redirect it); and (b) the command-layer **confirmed** `<project>/CLAUDE.md` create-when-absent — written ONLY on explicit user confirm AND only while the file is still absent (NEVER overwrite an existing CLAUDE.md). The twin module touches NO `~/.claude/settings.json` and nothing under `~/.claude/` — Twin artifacts are per-repo committed knowledge, not per-user config.

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
