#!/bin/bash
set -euo pipefail

MARKETPLACE_JSON=".claude-plugin/marketplace.json"

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
