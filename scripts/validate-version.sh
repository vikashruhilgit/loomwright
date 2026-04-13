#!/bin/bash
PLUGIN_VERSION=$(jq -r '.version' .claude-plugin/plugin.json)
echo "✓ Plugin version: $PLUGIN_VERSION"
