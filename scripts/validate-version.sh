#!/bin/bash
MARKETPLACE_VERSION=$(jq -r '.plugins[0].version' .claude-plugin/marketplace.json)
PLUGIN_VERSION=$(jq -r '.version' ai-agent-manager-plugin/.claude-plugin/plugin.json)

if [ "$MARKETPLACE_VERSION" != "$PLUGIN_VERSION" ]; then
  echo "ERROR: Version mismatch detected!"
  echo "  marketplace.json: $MARKETPLACE_VERSION"
  echo "  plugin.json: $PLUGIN_VERSION"
  exit 1
fi

echo "✓ Versions match: $PLUGIN_VERSION"
