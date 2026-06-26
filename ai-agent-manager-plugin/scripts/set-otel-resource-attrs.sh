#!/usr/bin/env bash
# set-otel-resource-attrs.sh — SessionStart hook helper that auto-maintains a
# project's OpenTelemetry OTEL_RESOURCE_ATTRIBUTES so every span/metric/log this
# repo emits is labeled service.name=<repo-basename>, service.version=<plugin version>.
#
# CONTRACT: fail-safe + telemetry-gated. Mirrors session-resume.sh's shape —
# `set -u` (intentionally NO `set -e` / pipefail), jq-gated, and ALWAYS exits 0
# on EVERY path (a hook helper must never break session start). The ONLY thing it
# durably writes is <project>/.claude/settings.local.json (the per-project env
# overlay); it best-effort also appends to $CLAUDE_ENV_FILE for the live session.
# It is READ-ONLY toward ~/.claude/settings.json (the telemetry gate source) and
# never writes it.
#
# Gate: enabled IFF jq is present AND telemetry is on — either
#   ~/.claude/settings.json .env.CLAUDE_CODE_ENABLE_TELEMETRY == "1"
#   OR the live env CLAUDE_CODE_ENABLE_TELEMETRY == "1".
# Gated ONLY on that flag — NOT on OTEL_EXPORTER_OTLP_ENDPOINT — so console-mode /
# env-only telemetry still gets a labeled service.name. Not enabled / no jq ⇒
# silent exit 0 (touches no file).
#
# Value-level merge: any pre-existing service.name / service.version pairs in the
# current OTEL_RESOURCE_ATTRIBUTES are dropped and replaced; every OTHER attribute
# (e.g. deployment.environment=dev) is preserved.
#
# Injection-safety: APP / VER / ATTR cross into jq ONLY via --arg, never
# interpolated into a jq program string. APP/VER are sanitized to the OTel
# attribute grammar before composing.

set -u
# Intentionally NO `set -e` / pipefail — fail-safe hook helper.

# ---- 1. --help / -h (before the gate) --------------------------------------
case "${1:-}" in
  -h|--help)
    cat <<'EOF'
set-otel-resource-attrs.sh — fail-safe, telemetry-gated SessionStart helper that
writes service.name=<repo-basename> and service.version=<plugin version> into the
project's .claude/settings.local.json `.env.OTEL_RESOURCE_ATTRIBUTES` (value-level
merge — preserves other attributes), so this repo's OpenTelemetry signals are
per-project labeled. Gated on CLAUDE_CODE_ENABLE_TELEMETRY=="1" (settings.json or
env); silent no-op when telemetry is off or jq is missing. ALWAYS exits 0. Takes
no arguments (the hook passes none; /setup calls it bare); any arg other than
-h/--help is ignored.
EOF
    exit 0
    ;;
esac

# ---- 2. Telemetry gate ------------------------------------------------------
# jq is required (the write + gate read both use it). No jq ⇒ silent exit 0.
command -v jq >/dev/null 2>&1 || exit 0

telemetry_on=0
# settings.json source (read-only). Guard $HOME with ${HOME:-} so an unset HOME
# under `set -u` cannot abort the hook (fail-safe contract) — skip the file
# branch entirely when HOME is empty; the env-var branch below still applies.
# 2>/dev/null so a missing/unreadable file is silent. `jq -e` exit status
# carries the boolean.
if [ -n "${HOME:-}" ] && jq -e '.env.CLAUDE_CODE_ENABLE_TELEMETRY=="1"' "${HOME}/.claude/settings.json" >/dev/null 2>&1; then
  telemetry_on=1
fi
# Live-env source (OR branch). Console/env-only telemetry must still label.
if [ "${CLAUDE_CODE_ENABLE_TELEMETRY:-}" = "1" ]; then
  telemetry_on=1
fi
[ "$telemetry_on" = "1" ] || exit 0

# ---- 3. Resolve service.name ------------------------------------------------
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
APP="$(basename "$ROOT")"
[ -n "$APP" ] || exit 0

# ---- 4. Resolve service.version --------------------------------------------
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  manifest="${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json"
else
  manifest="$(dirname "${BASH_SOURCE[0]}")/../.claude-plugin/plugin.json"
fi
VER="$(jq -r '.version' "$manifest" 2>/dev/null)"
# Unresolvable / empty / literal "null" ⇒ "unknown" (still label service.name).
case "$VER" in
  ""|null) VER="unknown" ;;
esac

# ---- 5. Sanitize for the OTel attribute grammar (BEFORE composing) ----------
# Neutralize commas / '=' / spaces / newlines that would corrupt the comma-and-
# '='-delimited OTEL_RESOURCE_ATTRIBUTES list. printf '%s' adds NO trailing
# newline, so `tr -c` cannot append a spurious trailing '_'.
APP="$(printf '%s' "$APP" | tr -c 'A-Za-z0-9._-' '_')"
VER="$(printf '%s' "$VER" | tr -c 'A-Za-z0-9._-' '_')"

# ---- 6. Value-level merge — compose ATTR ------------------------------------
SL="$ROOT/.claude/settings.local.json"
NEW_NAME="service.name=${APP}"
NEW_VER="service.version=${VER}"

# Read the CURRENT value (if the file exists + parses) and preserve all non-
# service.name/service.version attributes. The merge is done in bash/awk —
# NOT inside the write jq program — so APP/VER/ATTR only reach jq via --arg.
preserved=""
if [ -f "$SL" ]; then
  cur="$(jq -r '.env.OTEL_RESOURCE_ATTRIBUTES // empty' "$SL" 2>/dev/null)"
  if [ -n "$cur" ]; then
    # Split on ',', drop service.name=* / service.version=*, keep the rest.
    preserved="$(printf '%s' "$cur" | awk -v RS=',' '
      { gsub(/^[ \t]+|[ \t]+$/, "") }
      $0 == "" { next }
      $0 ~ /^service\.name=/ { next }
      $0 ~ /^service\.version=/ { next }
      { if (out != "") out = out ","; out = out $0 }
      END { printf "%s", out }
    ')"
  fi
fi

if [ -n "$preserved" ]; then
  ATTR="${NEW_NAME},${NEW_VER},${preserved}"
else
  ATTR="${NEW_NAME},${NEW_VER}"
fi

# ---- 7. Current-session best-effort (UNVERIFIED bonus) ----------------------
# If Claude Code exposed a session env file, export the attrs for the live
# session too. Correctness must NOT depend on this — skip silently on any issue.
if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -w "${CLAUDE_ENV_FILE}" ]; then
  printf 'export OTEL_RESOURCE_ATTRIBUTES=%q\n' "$ATTR" >> "${CLAUDE_ENV_FILE}" 2>/dev/null || true
fi

# ---- 8. Durable write -------------------------------------------------------
mkdir -p "$ROOT/.claude" 2>/dev/null || exit 0

if [ -f "$SL" ]; then
  # Parse-gate: an unparseable settings.local.json must NEVER be clobbered.
  jq empty "$SL" 2>/dev/null || exit 0
  # Idempotent: if the current value already equals the freshly-computed ATTR,
  # do not rewrite (preserves mtime).
  existing="$(jq -r '.env.OTEL_RESOURCE_ATTRIBUTES // empty' "$SL" 2>/dev/null)"
  [ "$existing" = "$ATTR" ] && exit 0
  tmp="$(mktemp "${SL}.XXXXXX" 2>/dev/null)" || exit 0
  if jq --arg a "$ATTR" '.env = ((.env // {}) + {OTEL_RESOURCE_ATTRIBUTES:$a})' "$SL" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$SL" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null
  fi
else
  if jq -n --arg a "$ATTR" '{env:{OTEL_RESOURCE_ATTRIBUTES:$a}}' > "$SL" 2>/dev/null; then
    chmod 600 "$SL" 2>/dev/null || true
  fi
fi

exit 0
