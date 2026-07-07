#!/bin/bash
set -euo pipefail

# Env override (used by --self-test to point the gate at a fixture tree's manifest).
MARKETPLACE_JSON="${CHECK_MARKETPLACE_JSON:-.claude-plugin/marketplace.json}"

# --self-test: negative-path proof for the per-plugin loop (mirrors check-skills-index-sync.sh).
# Builds throwaway fixtures and asserts: aligned passes; bad .source, missing manifest,
# version mismatch, and empty plugins[] each exit 1.
if [ "${1:-}" = "--self-test" ]; then
  SCRIPT="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  TMP=$(mktemp -d)
  trap "rm -rf '$TMP'" EXIT
  pass=0; fail=0
  check() { # name expected_rc marketplace_path
    local rc=0
    ( cd "$TMP" && CHECK_MARKETPLACE_JSON="$3" bash "$SCRIPT" >/dev/null 2>&1 ) || rc=$?
    if [ "$rc" -eq "$2" ]; then pass=$((pass+1)); echo "  ✓ self-test: $1"
    else fail=$((fail+1)); echo "  ✗ self-test: $1 (expected rc=$2, got rc=$rc)"; fi
  }
  mkdir -p "$TMP/good/.claude-plugin"
  echo '{"name":"good","version":"1.2.3"}' > "$TMP/good/.claude-plugin/plugin.json"
  echo '{"plugins":[{"name":"good","source":"./good","version":"1.2.3"}]}' > "$TMP/aligned.json"
  check "aligned marketplace passes" 0 aligned.json
  echo '{"plugins":[{"name":"bad","source":"./nope","version":"1.2.3"}]}' > "$TMP/badsource.json"
  check "unresolvable .source fails" 1 badsource.json
  mkdir -p "$TMP/hollow"
  echo '{"plugins":[{"name":"hollow","source":"./hollow","version":"1.2.3"}]}' > "$TMP/nomanifest.json"
  check "missing plugin manifest fails" 1 nomanifest.json
  echo '{"plugins":[{"name":"good","source":"./good","version":"9.9.9"}]}' > "$TMP/mismatch.json"
  check "version mismatch fails" 1 mismatch.json
  echo '{"plugins":[]}' > "$TMP/empty.json"
  check "empty plugins[] fails" 1 empty.json
  echo "self-test: $pass passed, $fail failed"
  [ "$fail" -eq 0 ]
  exit $?
fi

PLUGIN_COUNT=$(jq '.plugins | length' "$MARKETPLACE_JSON")
if [ "$PLUGIN_COUNT" -eq 0 ]; then
  echo "ERROR: marketplace.json lists no plugins"
  exit 1
fi

# Validate EVERY marketplace plugin entry (loomwright, stackpack, mysql-mcp, ...):
# source dir resolves, plugin manifest exists, marketplace version == plugin.json version.
while IFS= read -r ENTRY; do
  PLUGIN_NAME=$(jq -r '.name // "<unnamed>"' <<<"$ENTRY")
  MARKETPLACE_VERSION=$(jq -r '.version' <<<"$ENTRY")
  MARKETPLACE_SOURCE=$(jq -r '.source' <<<"$ENTRY")

  # 1. marketplace source path must resolve to an existing plugin directory.
  # Catches typos in a plugin's .source that would break /plugin install even when versions line up.
  if [ -z "$MARKETPLACE_SOURCE" ] || [ "$MARKETPLACE_SOURCE" = "null" ]; then
    echo "ERROR: marketplace.json plugin '$PLUGIN_NAME' .source is missing"
    exit 1
  fi

  SOURCE_DIR="$MARKETPLACE_SOURCE"
  if [ ! -d "$SOURCE_DIR" ]; then
    echo "ERROR: marketplace source directory does not exist: $SOURCE_DIR (plugin: $PLUGIN_NAME)"
    exit 1
  fi

  PLUGIN_MANIFEST="${SOURCE_DIR%/}/.claude-plugin/plugin.json"
  if [ ! -f "$PLUGIN_MANIFEST" ]; then
    echo "ERROR: marketplace source does not contain a plugin manifest: $PLUGIN_MANIFEST (plugin: $PLUGIN_NAME)"
    exit 1
  fi

  # 2. version parity: marketplace.json ↔ plugin.json.
  PLUGIN_VERSION=$(jq -r '.version' "$PLUGIN_MANIFEST")

  if [ "$MARKETPLACE_VERSION" != "$PLUGIN_VERSION" ]; then
    echo "ERROR: Version mismatch detected! (plugin: $PLUGIN_NAME)"
    echo "  marketplace.json: $MARKETPLACE_VERSION"
    echo "  plugin.json:      $PLUGIN_VERSION"
    exit 1
  fi

  echo "✓ [$PLUGIN_NAME] Marketplace source resolves: $SOURCE_DIR → $PLUGIN_MANIFEST"
  echo "✓ [$PLUGIN_NAME] Versions match: $PLUGIN_VERSION"
done < <(jq -c '.plugins[]' "$MARKETPLACE_JSON")
