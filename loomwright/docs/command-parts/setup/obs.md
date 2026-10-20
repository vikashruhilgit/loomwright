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

