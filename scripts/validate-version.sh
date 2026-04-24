#!/bin/bash
set -euo pipefail

MARKETPLACE_JSON=".claude-plugin/marketplace.json"
MARKETPLACE_VERSION=$(jq -r '.plugins[0].version' "$MARKETPLACE_JSON")
MARKETPLACE_SOURCE=$(jq -r '.plugins[0].source' "$MARKETPLACE_JSON")

# 1. marketplace source path must resolve to an existing plugin directory.
# Catches typos in plugins[0].source that would break /plugin install even when versions line up.
if [ -z "$MARKETPLACE_SOURCE" ] || [ "$MARKETPLACE_SOURCE" = "null" ]; then
  echo "ERROR: marketplace.json plugins[0].source is missing"
  exit 1
fi

SOURCE_DIR="$MARKETPLACE_SOURCE"
if [ ! -d "$SOURCE_DIR" ]; then
  echo "ERROR: marketplace source directory does not exist: $SOURCE_DIR"
  exit 1
fi

PLUGIN_MANIFEST="${SOURCE_DIR%/}/.claude-plugin/plugin.json"
if [ ! -f "$PLUGIN_MANIFEST" ]; then
  echo "ERROR: marketplace source does not contain a plugin manifest: $PLUGIN_MANIFEST"
  exit 1
fi

# 2. version parity: marketplace.json ↔ plugin.json.
PLUGIN_VERSION=$(jq -r '.version' "$PLUGIN_MANIFEST")

if [ "$MARKETPLACE_VERSION" != "$PLUGIN_VERSION" ]; then
  echo "ERROR: Version mismatch detected!"
  echo "  marketplace.json: $MARKETPLACE_VERSION"
  echo "  plugin.json:      $PLUGIN_VERSION"
  exit 1
fi

echo "✓ Marketplace source resolves: $SOURCE_DIR → $PLUGIN_MANIFEST"
echo "✓ Versions match: $PLUGIN_VERSION"
