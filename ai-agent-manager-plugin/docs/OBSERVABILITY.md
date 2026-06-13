# Observability (Local Langfuse + OTel Collector)

How the plugin's optional observability module works: where the signals come from, where they go, what is pinned, and how to troubleshoot it. Configured via `/setup observability` (authority: the `setup` skill — `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md`); this document is the reference companion.

> **Repo vs. runtime paths:** repo-relative paths like `ai-agent-manager-plugin/scripts/otel/...` below describe this repo's layout only. Anything executed at runtime resolves through `${CLAUDE_PLUGIN_ROOT}/...` (e.g. `${CLAUDE_PLUGIN_ROOT}/scripts/otel/docker-compose.yml`), and the running stack always operates on the **copy** at `~/.claude/ai-agent-manager/observability/` — never on the plugin install dir.

---

## Architecture

**The plugin emits NO spans itself.** The only telemetry emitter is **Claude Code's native OpenTelemetry support**, switched on by `CLAUDE_CODE_ENABLE_TELEMETRY=1` in the user-scope settings env block. The plugin's observability module configures *where those native signals go* — nothing more.

```
Claude Code CLI (native OTel, CLAUDE_CODE_ENABLE_TELEMETRY=1)
        │  OTLP http/protobuf → localhost:4318
        ▼
otel-collector (contrib, bundled)
        │  attributes/genai_token_rename processor:
        │    input_tokens            → gen_ai.usage.input_tokens
        │    output_tokens           → gen_ai.usage.output_tokens
        │    cache_read_tokens       → gen_ai.usage.cache_read.input_tokens
        │    cache_creation_tokens   → gen_ai.usage.cache_creation.input_tokens
        │  TRACES forwarded; metrics/logs terminated in a debug exporter
        ▼
Langfuse v3 (self-hosted) — /api/public/otel (Basic auth)
        └─ stores traces (web + worker + postgres + clickhouse + redis + minio)
```

- The collector receives OTLP over HTTP on `0.0.0.0:4318` and renames Claude-Code-style flat token-count span attributes to OTel GenAI semantic-convention names (the `attributes/genai_token_rename` processor in `scripts/otel/otel-collector-config.yaml`), so Langfuse's GenAI views can read usage off the spans.
- A persistent sending queue (`file_storage` extension, directory `/var/lib/otelcol/file_storage`) buffers spans across Langfuse downtime and collector restarts.

## Env-block reference (the 8 keys)

`/setup observability init` deep-merges exactly these keys into the `env` object of `~/.claude/settings.json`:

| Key | Value |
|---|---|
| `CLAUDE_CODE_ENABLE_TELEMETRY` | `1` |
| `OTEL_METRICS_EXPORTER` | `otlp` |
| `OTEL_LOGS_EXPORTER` | `otlp` |
| `OTEL_TRACES_EXPORTER` | `otlp` |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `http/protobuf` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | the collector endpoint (default `http://localhost:4318`) |
| `OTEL_EXPORTER_OTLP_HEADERS` | auth headers for the OTLP hop, e.g. `Authorization=Basic <base64(pk:sk)>` |
| `OTEL_RESOURCE_ATTRIBUTES` | `service.version=<plugin version>` (read from `plugin.json` at init — this is what powers per-plugin-version slicing) |

Console mode is the one sanctioned variant: exporters set to `console`, OTLP keys omitted/removed (useful for verification — see below).

> **External-endpoint header note:** `OTEL_EXPORTER_OTLP_HEADERS` is a comma-separated `key=value` list; a base64 Basic-auth value ends in `=` padding (e.g. `Authorization=Basic dXNlcjpwYXNz==`). The **local** backend is unaffected — the bundled collector accepts unauthenticated OTLP and ignores this header. For the **existing-endpoint** backend the header string is taken verbatim from what you supply, so paste exactly the `Authorization=Basic …` value your provider gives you; if a remote endpoint rejects it, confirm the exporter split the value on the *first* `=` (the OTel default) rather than choking on the trailing pad.

### settings.json merge semantics

The init flow **never blind-overwrites** `~/.claude/settings.json`:

1. A **timestamped backup** of the existing file is written first.
2. The env block is applied via **jq deep-merge** — only the 8 keys above are touched; unrelated keys (and unrelated top-level sections) are preserved byte-for-byte.
3. If the existing file **fails to parse as JSON, the flow aborts** — it never half-writes a corrupted settings file.

## Documented limitation: Langfuse ingests TRACES ONLY

Langfuse's OTLP endpoint (`/api/public/otel`) **accepts traces only** — metrics and logs are not ingested. Consequence: **Claude Code's native cost/token METRICS do not land in Langfuse.** Token usage is still visible per-trace via the renamed `gen_ai.usage.*` span attributes, but the metrics stream itself terminates in the collector's debug exporter (deliberately, so the CLI never sees export errors). This is documented Langfuse behavior, not something the bundled stack works around.

## Session-start health probe

`${CLAUDE_PLUGIN_ROOT}/scripts/session-resume.sh` (the existing `SessionStart` hook — hook count unchanged at 19) also runs `observability_probe`:

- **Inherits the host hook's outer gates:** `session-resume.sh` only runs on `SessionStart` sources `resume`/`clear`/`compact` (a fresh `startup` is silent) AND early-exits when the working directory has no `.supervisor/` dir. The probe is called after those gates, so — by design — the down-stack warning fires only when you resume/clear/compact **inside a Supervisor-managed repo**. Observability config is global (`~/.claude/settings.json`), so a session in a non-`.supervisor/` repo with a down stack gets no warning; this is intentional (the hook's primary job is Supervisor recovery context, and `/setup observability status` reports stack health on demand anywhere).
- **Gated on the env block:** runs only when `~/.claude/settings.json` has `env.CLAUDE_CODE_ENABLE_TELEMETRY` truthy (explicit `0`/`false` is treated as unconfigured) AND a non-empty `env.OTEL_EXPORTER_OTLP_ENDPOINT`. Missing `jq`/`curl`/settings → strict no-op, byte-identical to pre-probe hook output.
- **Probe:** `curl --max-time 1` against the base of the configured OTLP endpoint (any `/v1/traces|metrics|logs` suffix stripped). Any HTTP response counts as up.
- **Debounce:** on failure it appends a bounded warning and writes a 24h marker file (`~/.claude/ai-agent-manager/observability/.last-warned`); a fresh (<24h) marker suppresses the entire warning.
- **It NEVER starts Docker.** It only prints the exact restart command:

  ```bash
  docker compose -p ai-agent-manager-observability -f ~/.claude/ai-agent-manager/observability/docker-compose.yml up -d
  ```

### Compose project-name convention

The stack's compose project is always **`ai-agent-manager-observability`** (named volumes: `ai-agent-manager-observability_*`), pinned two ways: every documented command carries `-p ai-agent-manager-observability` explicitly, and the generated `.env` contains `COMPOSE_PROJECT_NAME=ai-agent-manager-observability` (compose v2 loads `.env` from the `-f` file's directory, so even a bare `docker compose -f … up -d` joins the same project). A command with neither would derive project `observability` from the directory basename and silently create a second parallel stack on fresh empty volumes — orphaning the existing traces and fighting over ports.

## Pinned versions

Every image in `scripts/otel/docker-compose.yml` is pinned (no `:latest`, no floating major tags). The two load-bearing pins:

| Component | Image | Pin |
|---|---|---|
| Langfuse v3 (web + worker) | `langfuse/langfuse`, `langfuse/langfuse-worker` | **3.82.0** |
| OTel Collector | `otel/opentelemetry-collector-contrib` | **0.116.1** |

Supporting services (also pinned there): `postgres:16.6-alpine`, `clickhouse/clickhouse-server:24.8.6.70-alpine`, `redis:7.4.1-alpine`, `minio/minio:RELEASE.2024-11-07T00-52-20Z` (Langfuse v3 hard-requires S3-compatible blob storage; MinIO provides it locally).

## Per-role attribution (`agent.name`) — verification required

Whether Claude Code's native spans carry a usable `agent.name` attribute for subagents spawned from a **third-party-marketplace plugin** (i.e. whether per-agent-role attribution like `supervisor-runner` vs `worker` survives, or is redacted/generic) has **NOT yet been verified empirically** on this plugin. Do not assume per-role dashboards will work until you have checked.

**How to verify on your first real session:** temporarily set `OTEL_TRACES_EXPORTER=console` (console mode; OTLP keys removed) in the settings env block, run a session that spawns at least one subagent, and inspect the console-printed spans for `agent.name` (or equivalent) values. If the attribute is present and role-specific, per-role attribution will work in Langfuse; if it is absent or redacted, treat traces as session-scoped only. Restore the `otlp` exporters afterwards.

## Troubleshooting

### (a) Collector exits / restarts on first boot — file_storage permission failure

The `otel-collector-contrib` image is **distroless and runs as non-root UID 10001** by default. A freshly created named volume mounted at the `file_storage` path (`/var/lib/otelcol/file_storage`) is root-owned, so a non-root collector's `create_directory`/write would **permission-fail on the very first boot** and stall `wait-healthy`. **The bundled compose handles this by setting `user: "0:0"` on the `otel-collector` service** — it runs as root and creates the directory cleanly, so the default first boot needs no manual step. This is an accepted trade for a local-only collector.

If you prefer to keep the collector non-root (remove the `user: "0:0"` override), pre-seed the volume ownership before first boot instead (the `-p` flag is load-bearing here — it makes the pre-seed act on the real stack's `ai-agent-manager-observability_otel_collector_queue` volume, not a freshly created `observability_*` one):

  ```bash
  docker compose -p ai-agent-manager-observability -f ~/.claude/ai-agent-manager/observability/docker-compose.yml run --rm --user 0:0 --entrypoint sh otel-collector -c 'chown -R 10001:10001 /var/lib/otelcol/file_storage'
  ```

### (b) Stack is down — session-start warning

If the stack is stopped, the session-start probe prints a bounded warning (debounced to once per 24h) with the restart command. Run it, or use `/setup observability` to repair the stack:

```bash
docker compose -p ai-agent-manager-observability -f ~/.claude/ai-agent-manager/observability/docker-compose.yml up -d
```

### (c) Traces not appearing in Langfuse

The collector forwards to Langfuse's `/api/public/otel` with **Basic auth built from the Langfuse project keypair**. If traces never appear:

1. Check the collector logs for `401`/`403` from `langfuse-web` — that means the Basic auth credentials don't match the project keys.
2. Verify the headless-provisioning init keys (`LANGFUSE_INIT_PROJECT_PUBLIC_KEY` / `LANGFUSE_INIT_PROJECT_SECRET_KEY` in the stack's `.env`) match what the collector config sends — these are created on first boot by Langfuse's `LANGFUSE_INIT_*` provisioning, so a regenerated `.env` after first boot will NOT change the keys already stored in postgres.
3. Confirm the CLI is actually exporting: env block present in `~/.claude/settings.json` and the session restarted after the merge (env changes only apply to new sessions).
4. Remember the traces-only limitation above — missing *metrics* in Langfuse is expected behavior, not a failure.
