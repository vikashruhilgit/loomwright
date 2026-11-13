#!/usr/bin/env bash
# check-release.sh — the selvedge plugin's release-consistency check.
#
# Usage: bash selvedge/tests/check-release.sh [<plugin-dir>]
#   <plugin-dir> defaults to the plugin this script ships in (the dir above tests/). The tests
#   pass a fixture copy.
#
# Checks, failing on the FIRST violation with a named reason (a snake_case token) on stderr:
#   - .claude-plugin/plugin.json is a valid JSON object
#   - it has non-empty string name, version and description
#   - CHANGELOG.md has a release heading `## <X.Y.Z> — <YYYY-MM-DD>`
#   - the FIRST such heading's version equals plugin.json's version
# Each reason token sits on exactly one line (the check that emits it), so a test can pin it.
#
# selvedge releases on its own (its own version and changelog), so this is its release gate, run
# by selvedge/tests/run.sh. It reads nothing outside <plugin-dir>. jq is required (it is a CI
# dependency; the selvedge CLI itself never needs it). Exit: 0 consistent, 1 violated, 2 cannot
# check.
set -uo pipefail

fail() { printf 'check-release: FAIL %s\n' "$*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || { echo "check-release: CANNOT RUN — jq not found" >&2; exit 2; }

plugin_dir="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
[ -d "$plugin_dir" ] || { echo "check-release: CANNOT RUN — no such plugin dir: $plugin_dir" >&2; exit 2; }
pj="$plugin_dir/.claude-plugin/plugin.json"
cl="$plugin_dir/CHANGELOG.md"

[ -f "$pj" ] || fail "manifest_absent: $pj does not exist"
jq -e 'type == "object"' "$pj" >/dev/null 2>&1 || fail "manifest_invalid_json: $pj is not a valid JSON object"
for field in name version description; do
  [ -n "$(jq -r --arg f "$field" '.[$f] | strings' "$pj" 2>/dev/null)" ] || fail "manifest_missing_field: $pj has no non-empty string \"$field\""
done
pj_ver="$(jq -r '.version' "$pj")"

[ -f "$cl" ] || fail "changelog_absent: $cl does not exist"
cl_ver="$(awk '/^## [0-9]+\.[0-9]+\.[0-9]+ — [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ { print $2; exit }' "$cl")"
[ -n "$cl_ver" ] || fail "changelog_no_release: $cl has no '## <X.Y.Z> — <YYYY-MM-DD>' heading"
[ "$cl_ver" = "$pj_ver" ] || fail "changelog_version_mismatch: plugin.json version $pj_ver != first CHANGELOG.md release $cl_ver (bump both together)"

echo "check-release: OK — $(jq -r '.name' "$pj") $pj_ver (plugin.json == CHANGELOG.md top release)"
