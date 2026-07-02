#!/usr/bin/env bash
# test-setup-observability.sh — static self-tests for the bundled OTel/Langfuse
# observability assets (scripts/otel/). STATIC ONLY: requires no Docker daemon
# and no network, so it runs on the plugin's Ubuntu CI like every other
# test-*.sh. Exit 0 = all pass, 1 = any failure.
#
# Covers: YAML parseability (python3+pyyaml, skip-with-pass when unavailable),
# restart/healthcheck policy on every compose service, the 7-service roster,
# the four GenAI token-attribute rename rules, persistent sending_queue +
# file_storage, the Langfuse OTLP exporter target, and a no-committed-secrets
# scan (${...} placeholders only).

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
COMPOSE="$HERE/otel/docker-compose.yml"
CONFIG="$HERE/otel/otel-collector-config.yaml"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

echo "== 0. assets exist =="
[ -f "$COMPOSE" ] && ok "docker-compose.yml present" || no "docker-compose.yml missing"
[ -f "$CONFIG" ] && ok "otel-collector-config.yaml present" || no "otel-collector-config.yaml missing"
if [ ! -f "$COMPOSE" ] || [ ! -f "$CONFIG" ]; then
  echo; echo "RESULT: $pass passed, $fail failed"; exit 1
fi

echo "== 1. YAML parses (python3 + pyyaml; optional dep — skip-with-pass) =="
if command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" >/dev/null 2>&1; then
  if python3 - "$COMPOSE" "$CONFIG" <<'PY' >/dev/null 2>&1
import sys, yaml
for p in sys.argv[1:]:
    with open(p) as f:
        yaml.safe_load(f)
PY
  then ok "both YAML files parse with yaml.safe_load"
  else no "YAML parse error (run: python3 -c \"import yaml,sys; yaml.safe_load(open(sys.argv[1]))\" <file>)"
  fi
else
  ok "python3/pyyaml not available — parse check skipped (pass)"
fi

echo "== 2. compose: service roster (7 expected) =="
# Service names = 2-space-indented keys inside the top-level services: block.
services="$(awk '
  /^services:[[:space:]]*$/ { insvc=1; next }
  insvc && /^[^ ]/ { insvc=0 }
  insvc && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { s=$0; gsub(/^[ ]+|:[[:space:]]*$/, "", s); print s }
' "$COMPOSE")"
n_services="$(printf '%s\n' "$services" | grep -c . || true)"
[ "$n_services" -eq 7 ] && ok "exactly 7 services declared" || no "expected 7 services, found $n_services ($services)"
for svc in langfuse-web langfuse-worker postgres clickhouse redis minio otel-collector; do
  printf '%s\n' "$services" | grep -qx "$svc" && ok "service present: $svc" || no "service missing: $svc"
done

echo "== 3. compose: restart + healthcheck on every service =="
n_restart="$(grep -c '^    restart: unless-stopped[[:space:]]*$' "$COMPOSE" || true)"
[ "$n_restart" -eq "$n_services" ] && ok "restart: unless-stopped on all $n_services services" || no "restart: unless-stopped count $n_restart != service count $n_services"
n_health="$(grep -c '^    healthcheck:[[:space:]]*$' "$COMPOSE" || true)"
[ "$n_health" -eq "$n_services" ] && ok "healthcheck on all $n_services services" || no "healthcheck count $n_health != service count $n_services"

echo "== 4. compose: pinned images (no :latest, no unpinned image) =="
if grep -E '^    image:.*:latest[[:space:]]*$|^    image:[^:]+[[:space:]]*$' "$COMPOSE" >/dev/null 2>&1; then
  no "found :latest or tag-less image reference"
else
  ok "every image carries an explicit pinned tag"
fi
grep -q 'otel/opentelemetry-collector-contrib:0\.' "$COMPOSE" && ok "otel-collector image is the pinned contrib build" || no "otel-collector contrib image pin missing"

echo "== 5. collector config: four GenAI token rename rules =="
check_rename() { # $1 = source attr, $2 = target attr
  if grep -q "key: $2" "$CONFIG" && grep -q "from_attribute: $1" "$CONFIG"; then
    ok "rename rule: $1 -> $2"
  else
    no "rename rule missing: $1 -> $2"
  fi
}
check_rename input_tokens gen_ai.usage.input_tokens
check_rename output_tokens gen_ai.usage.output_tokens
check_rename cache_read_tokens gen_ai.usage.cache_read.input_tokens
check_rename cache_creation_tokens gen_ai.usage.cache_creation.input_tokens

echo "== 6. collector config: persistent queue + Langfuse exporter =="
grep -qE '^  file_storage:' "$CONFIG" && ok "file_storage extension declared" || no "file_storage extension missing"
grep -q 'sending_queue:' "$CONFIG" && ok "sending_queue configured on exporter" || no "sending_queue missing"
grep -q 'storage: file_storage' "$CONFIG" && ok "sending_queue backed by file_storage" || no "sending_queue not backed by file_storage"
grep -q '/api/public/otel' "$CONFIG" && ok "exporter targets Langfuse /api/public/otel" || no "exporter does not target /api/public/otel"
grep -qE 'exporters: \[otlphttp/langfuse\]' "$CONFIG" && ok "traces pipeline exports to Langfuse" || no "traces pipeline does not export to Langfuse"

echo "== 7. no committed secrets (placeholders only) =="
# Real-looking credential literals must never be committed; ${VAR} placeholders ok.
if grep -nE 'sk-lf-[0-9a-fA-F]|pk-lf-[0-9a-fA-F]|AKIA[0-9A-Z]{16}|-----BEGIN .*PRIVATE KEY' "$COMPOSE" "$CONFIG" >/dev/null 2>&1; then
  no "suspicious credential-like literal committed"
else
  ok "no credential-like literals found"
fi
# Every secret-bearing key must resolve from the environment (${...} present
# on the line). $${VAR} (compose runtime-escape) contains ${VAR} and passes.
secretish="$(grep -nE '(PASSWORD|SECRET|SALT|ENCRYPTION_KEY|REDIS_AUTH|BASIC_AUTH)' "$COMPOSE" "$CONFIG" | grep -vE '\$\{' | grep -vE '^\s*[^:]*:?\s*#|#.*' || true)"
if [ -n "$secretish" ]; then
  no "secret-bearing line without \${...} placeholder: $secretish"
else
  ok "all secret-bearing keys use \${...} placeholders"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
