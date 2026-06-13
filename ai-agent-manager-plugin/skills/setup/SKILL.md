---
name: setup
description: Module protocol authority for the /setup umbrella command — the check/report/offer/apply/verify contract, the module registry, the jq deep-merge rules for ~/.claude/settings.json (backup-first, abort-on-parse-failure, idempotent), and the OTLP smoke-test recipe. Use when running /setup or modifying any setup module.
version: "1.0.0"
lastUpdated: "2026-06-13"
---

# Setup Skill

Protocol authority for `/setup` (see `${CLAUDE_PLUGIN_ROOT}/commands/setup.md` for the user-facing flows). The command owns orchestration and UX; this skill owns the contract and the canonical recipes. When the two disagree, this skill wins.

## When to Use

- Executing any `/setup` module flow (the command reads this skill at Step 0).
- Adding a new module to `/setup` — implement the contract below and add a registry row.
- Reviewing changes that touch user-scope `~/.claude/settings.json` — the merge rules here are the only sanctioned write path.

## When NOT to Use

- Telemetry consent — `/telemetry` owns `.supervisor/telemetry-consent.json`; `/setup telemetry` only delegates. See `telemetry/`.
- Per-run observability *analysis* — `/insights` reads logs; this skill only wires up emission backends.
- Anything that emits spans from the plugin itself. **The plugin emits NO spans** — Claude Code's native OTel telemetry is the only emitter; this skill configures destinations.

## Core Patterns

### Pattern 1 — The module contract

Every module implements five phases, in order, every invocation:

| Phase | Rule |
|---|---|
| **check** | Derive state from REAL commands (file tests, `jq -e`, `docker inspect`, `command -v`). Never assert state you didn't probe. |
| **report** | Print what check found. `status` subcommands stop here. |
| **offer** | `AskUserQuestion` with the applicable actions. Already-configured modules offer status/reconfigure/remove — never silently re-apply. **`AskUserQuestion` caps at 4 options** — the no-arg dashboard must NOT emit one option per module (6 modules > 4); it uses the fixed ≤4-option set in `commands/setup.md` (observability, telemetry, "Other integrations" folding the three guidance-only modules, "Nothing"). |
| **apply** | Make the change. Backup before any mutation of a pre-existing file. Stop at the first failed step — never continue past a failure to "finish" the flow. |
| **verify** | Re-run check (+ smoke test where defined) and show before/after. Success is claimed ONLY after verify passes. |

**Idempotency invariant:** running a module twice in a row must be safe — the second run reports "already configured" and changes nothing without an explicit user choice. Concretely: never regenerate an existing `.env` (it holds keys), never duplicate env-block keys (the merge is keyed), never `cp` over user-modified configs without saying so.

### Pattern 2 — Module registry

| Module | Depth (v1) | check probes | apply writes |
|---|---|---|---|
| `observability` | FULL init / status / remove | `~/.claude/settings.json` env block; `~/.claude/ai-agent-manager/observability/` copy; `docker inspect` health | asset copy + `.env` + `docker compose` + settings merge |
| `telemetry` | delegate | `.supervisor/telemetry-consent.json` | nothing — `/telemetry` owns it |
| `notifications` | status + guidance | none (always-on hooks) | nothing |
| `webhook` | status + guidance | `AI_AGENT_MANAGER_WEBHOOK_URL` set? | nothing (guidance only) |
| `beads` | status + guidance | `command -v bd`; `.beads/` dir | nothing (guidance only) |
| `mysql-mcp` | status + guidance | `DB_HOST`/`DB_USER`/`DB_PASS`/`DB_NAME` set? | nothing (guidance only) |

New modules append a row here AND a flow section in `commands/setup.md` in the same change.

### Pattern 3 — Settings merge (jq deep-merge into `~/.claude/settings.json`)

The ONLY sanctioned way to write user-scope settings. Rules: (a) timestamped backup BEFORE any write; (b) abort — never half-write — if the existing file fails to parse; (c) merge only under the `env` key, preserving every unrelated key at both levels; (d) atomic replace via tmp-file + `mv`.

```bash
SETTINGS="$HOME/.claude/settings.json"
# $ENV_JSON = a JSON object of the keys to merge, built with jq -n (never string-interpolated):
ENV_JSON=$(jq -n --arg endpoint "$ENDPOINT" --arg headers "$HEADERS" --arg ver "$PLUGIN_VERSION" '{
  CLAUDE_CODE_ENABLE_TELEMETRY: "1",
  OTEL_METRICS_EXPORTER: "otlp",
  OTEL_LOGS_EXPORTER: "otlp",
  OTEL_TRACES_EXPORTER: "otlp",
  OTEL_EXPORTER_OTLP_PROTOCOL: "http/protobuf",
  OTEL_EXPORTER_OTLP_ENDPOINT: $endpoint,
  OTEL_EXPORTER_OTLP_HEADERS: $headers,
  OTEL_RESOURCE_ATTRIBUTES: ("service.version=" + $ver)
}')

if [ -f "$SETTINGS" ]; then
  jq empty "$SETTINGS" 2>/dev/null \
    || { echo "ABORT: $SETTINGS exists but is not valid JSON — fix it by hand; nothing was written."; exit 1; }
  cp "$SETTINGS" "$SETTINGS.backup.$(date +%Y%m%d-%H%M%S)"
  jq --argjson new "$ENV_JSON" '.env = ((.env // {}) + $new)' "$SETTINGS" > "$SETTINGS.tmp" \
    && mv "$SETTINGS.tmp" "$SETTINGS"
else
  mkdir -p "$HOME/.claude"
  jq -n --argjson new "$ENV_JSON" '{env: $new}' > "$SETTINGS"
fi
```

Removal is the mirror image: same parse-check + backup, then `del(.env.KEY1, .env.KEY2, …)` of EXACTLY the keys this skill added — never `del(.env)` wholesale (the user may keep unrelated env there).

**Why these 8 keys:** this is the settled env-block contract — `CLAUDE_CODE_ENABLE_TELEMETRY=1`, the three `OTEL_*_EXPORTER=otlp` keys, `OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf`, endpoint, headers, and `OTEL_RESOURCE_ATTRIBUTES=service.version=<plugin version>`. Console mode is the one sanctioned variant (exporters=`console`, OTLP keys omitted/removed).

### Pattern 4 — `.env` generation (observability local backend)

Generated once into `~/.claude/ai-agent-manager/observability/.env`; NEVER regenerated if the file exists. Every variable below is consumed by the copied `docker-compose.yml` (`${CLAUDE_PLUGIN_ROOT}/scripts/otel/docker-compose.yml`) — except `COMPOSE_PROJECT_NAME`, which is consumed by the compose CLI itself (see the project-name convention below):

```bash
PK="pk-lf-$(openssl rand -hex 16)"
SK="sk-lf-$(openssl rand -hex 16)"
ADMIN_PW="$(openssl rand -hex 12)"
cat > "$OBS_DIR/.env" <<EOF
# Generated by /setup observability — local-only secrets, never commit.
# Project-name convention (belt-and-braces): every recipe/printed command
# carries -p ai-agent-manager-observability explicitly (correct on any
# compose version, from any cwd), AND this key makes a bare
# `docker compose -f <this dir>/docker-compose.yml ...` join the SAME
# project — compose v2 loads .env from the first -f file's directory, so
# without it the project name would derive from the dir basename
# ("observability") and create a second parallel stack with empty volumes.
COMPOSE_PROJECT_NAME=ai-agent-manager-observability
POSTGRES_USER=langfuse
POSTGRES_PASSWORD=$(openssl rand -hex 16)
POSTGRES_DB=langfuse
CLICKHOUSE_USER=clickhouse
CLICKHOUSE_PASSWORD=$(openssl rand -hex 16)
REDIS_AUTH=$(openssl rand -hex 16)
MINIO_ROOT_USER=minio
MINIO_ROOT_PASSWORD=$(openssl rand -hex 16)
LANGFUSE_S3_BUCKET=langfuse
LANGFUSE_SALT=$(openssl rand -hex 16)
LANGFUSE_ENCRYPTION_KEY=$(openssl rand -hex 32)
NEXTAUTH_SECRET=$(openssl rand -hex 32)
NEXTAUTH_URL=http://localhost:3000
LANGFUSE_PORT=3000
LANGFUSE_INIT_ORG_ID=ai-agent-manager
LANGFUSE_INIT_ORG_NAME=AI Agent Manager
LANGFUSE_INIT_PROJECT_ID=claude-code
LANGFUSE_INIT_PROJECT_NAME=Claude Code
LANGFUSE_INIT_PROJECT_PUBLIC_KEY=$PK
LANGFUSE_INIT_PROJECT_SECRET_KEY=$SK
LANGFUSE_INIT_USER_EMAIL=admin@local.test
LANGFUSE_INIT_USER_NAME=Admin
LANGFUSE_INIT_USER_PASSWORD=$ADMIN_PW
LANGFUSE_BASIC_AUTH=$(printf '%s:%s' "$PK" "$SK" | base64 | tr -d '\n')
OTEL_COLLECTOR_PORT=4318
EOF
chmod 600 "$OBS_DIR/.env"
```

Key facts: `LANGFUSE_ENCRYPTION_KEY` must be 64 hex chars (`-hex 32`); `LANGFUSE_BASIC_AUTH` is `base64("<public_key>:<secret_key>")` consumed by the collector's `Authorization: Basic` header toward Langfuse; the `LANGFUSE_INIT_*` block headlessly provisions org/project/user/keypair on first boot so init never clicks through the UI.

**Project-name convention (settled — do not vary):** the compose project is ALWAYS `ai-agent-manager-observability`, pinned two ways: (a) every compose command in the recipes AND every user-facing printed command (restart hints, the chown pre-seed, teardown) carries `-p ai-agent-manager-observability` explicitly; (b) `COMPOSE_PROJECT_NAME=ai-agent-manager-observability` is written into the generated `.env` so a hand-typed bare `docker compose -f "$OBS_DIR/docker-compose.yml" …` still resolves to the same project (compose v2 loads `.env` from the first `-f` file's directory; verified empirically). Named volumes are therefore always `ai-agent-manager-observability_*`. A command that omits BOTH would derive project `observability` from the directory basename and spin up a second parallel stack on fresh empty volumes — never print such a command.

### Pattern 5 — Wait-healthy loop

```bash
P="ai-agent-manager-observability"
for i in $(seq 1 60); do  # 60 × 10s = 10 min ceiling (first boot pulls images + runs ClickHouse migrations)
  total=$(docker compose -p "$P" -f "$OBS_DIR/docker-compose.yml" --env-file "$OBS_DIR/.env" ps -q | wc -l | tr -d ' ')
  healthy=$(docker compose -p "$P" -f "$OBS_DIR/docker-compose.yml" --env-file "$OBS_DIR/.env" ps -q \
            | xargs docker inspect -f '{{.State.Health.Status}}' 2>/dev/null | grep -c '^healthy$')
  [ "$total" -gt 0 ] && [ "$healthy" -eq "$total" ] && break
  sleep 10
done
# Final assertion requires a NON-ZERO total: zero containers (stack never
# started / wrong project name) must abort, never false-pass as 0 == 0.
[ "${total:-0}" -gt 0 ] && [ "$healthy" -eq "$total" ] || { echo "TIMEOUT: ${healthy:-0}/${total:-0} healthy"; exit 1; }
```

`docker inspect` is used (not `compose ps` text parsing) because output is stable across compose versions, and the collector's health port (13133) is intentionally not published to the host.

### Pattern 6 — Smoke-test recipe (emit span → poll Langfuse)

Success is claimed ONLY after a real span round-trips. Emit via OTLP/HTTP JSON to the collector, then poll the Langfuse public API with the generated keypair:

```bash
# Source the keypair + ports from the stack's generated .env FIRST — on the
# reuse/reconfigure path the keys were generated in a prior session, so
# in-memory $PK/$SK from the generation recipe may be absent/stale (a 401
# on the poll otherwise).
PK=$(sed -n 's/^LANGFUSE_INIT_PROJECT_PUBLIC_KEY=//p' "$OBS_DIR/.env")
SK=$(sed -n 's/^LANGFUSE_INIT_PROJECT_SECRET_KEY=//p' "$OBS_DIR/.env")
LANGFUSE_PORT=$(sed -n 's/^LANGFUSE_PORT=//p' "$OBS_DIR/.env")
OTEL_COLLECTOR_PORT=$(sed -n 's/^OTEL_COLLECTOR_PORT=//p' "$OBS_DIR/.env")

TRACE_ID=$(openssl rand -hex 16); SPAN_ID=$(openssl rand -hex 8)
NOW_NS=$(($(date +%s) * 1000000000))
curl -sf -X POST "http://localhost:${OTEL_COLLECTOR_PORT:-4318}/v1/traces" \
  -H 'Content-Type: application/json' -d '{
  "resourceSpans": [{
    "resource": {"attributes": [{"key": "service.name", "value": {"stringValue": "ai-agent-manager-smoke-test"}}]},
    "scopeSpans": [{
      "scope": {"name": "setup-smoke-test"},
      "spans": [{"traceId": "'"$TRACE_ID"'", "spanId": "'"$SPAN_ID"'", "name": "setup-smoke-test",
                 "kind": 1, "startTimeUnixNano": "'"$NOW_NS"'", "endTimeUnixNano": "'"$((NOW_NS + 1000000))"'"}]
    }]
  }]
}'
# Poll: ingestion is async (collector batch 5s → Langfuse worker → ClickHouse). Up to ~3 min.
for i in $(seq 1 36); do
  curl -sf -u "$PK:$SK" "http://localhost:${LANGFUSE_PORT:-3000}/api/public/traces?name=setup-smoke-test&limit=1" \
    | jq -e '.data | length > 0' >/dev/null && { echo "SMOKE OK ($TRACE_ID)"; break; }
  sleep 5
done
```

For an external/existing endpoint, only the emit half runs (verify 2xx) — arbitrary backends can't be polled. **Traces only:** Langfuse's `/api/public/otel` ingests traces, not metrics/logs; the local collector terminates those in a debug exporter by design. Document this, never work around it.

## Anti-Patterns

- **String-interpolating user input into the settings JSON.** Always build `$ENV_JSON` with `jq -n --arg` — injection-safe by construction.
- **Overwriting `~/.claude/settings.json` wholesale** (or writing it with a non-jq tool). Unrelated keys (model, hooks, permissions) must survive every merge.
- **Proceeding after a parse failure** ("I'll just recreate the file"). The file may hold config you can't reconstruct — abort with the path and let the human fix it.
- **Regenerating `.env` on re-init.** The keypair in it authenticates the collector to Langfuse and the smoke-test poll; regenerating orphans the provisioned project.
- **Claiming success without the smoke test.** "Containers are up" is not "traces land".
- **Repo-relative plugin paths at runtime.** Only `${CLAUDE_PLUGIN_ROOT}/scripts/otel/...` resolves for installed users.
- **Running compose against the plugin install dir.** Always copy to `~/.claude/ai-agent-manager/observability/` first — the install dir is replaced on plugin update and must never accumulate state (`.env`, volumes).

## Example Implementation

`/setup observability` on a clean machine: check finds no env block and no copy → report "not configured" → offer backends → user picks local → Docker check (warn about start-at-login) → copy assets → generate `.env` (Pattern 4) → `compose up -d` → wait-healthy (Pattern 5) → settings merge (Pattern 3) → smoke test (Pattern 6) → report dashboard URL + login + "restart Claude Code sessions" + optional per-repo `service.name` snippet. A second `/setup observability` run finds everything healthy and offers status/reconfigure/remove instead of re-applying.

## Testing Approach

- Merge recipe: run against a fixture settings.json with unrelated keys (`model`, `hooks`) + a pre-existing `env` → assert all preserved, 8 keys added, backup file exists; run against malformed JSON → assert abort + no write + no backup-restore needed.
- Idempotency: run apply twice → assert second run is a no-op offer, `.env` mtime unchanged.
- Smoke test: assert failure path stops the flow (kill `langfuse-worker`, expect poll timeout → no success claim).
- Removal: assert exactly the 8 keys are deleted and everything else survives.

## Related Skills

- `telemetry/` — the OTHER telemetry (GitHub-issues run summaries); `/setup telemetry` delegates there. Disjoint write paths: this skill never touches `.supervisor/telemetry-consent.json`.
- `docker/` — container patterns behind the compose stack (healthchecks, pinned images).
- `error-handling/` — the fail-closed abort pattern used by the merge recipe.
- `quality-checklist/` — gates for reviewing changes to this skill or the command.

## Quality Gates

- [ ] Every settings.json write path: backup-first, `jq empty` parse gate, tmp+`mv` atomic replace.
- [ ] Env block is exactly the 8 settled keys (or the documented console variant) — no extras, no renames.
- [ ] `.env` variable names match what `${CLAUDE_PLUGIN_ROOT}/scripts/otel/docker-compose.yml` consumes (sole exception: `COMPOSE_PROJECT_NAME`, consumed by the compose CLI) — verify against the compose file on any change to either.
- [ ] Every compose command (recipe or printed) carries `-p ai-agent-manager-observability` — the project-name convention in Pattern 4.
- [ ] No repo-relative plugin path (the dev-checkout-only form) in any runtime instruction — `${CLAUDE_PLUGIN_ROOT}/...` only.
- [ ] Smoke test gates the success claim (local backend) — never report success on `compose up` alone.
- [ ] Idempotency invariant holds for every module (re-run = report + offer, not re-apply).
- [ ] No secret values printed except the local-only Langfuse dashboard login.

## Token Cost

- Invocation: ~1,200 tokens (skill body)
- Storage: inline (markdown only)
- Context7: not required
