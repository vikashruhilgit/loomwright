#!/usr/bin/env bash
# run.sh — the selvedge plugin's own gate. CI's `static` job runs `bash selvedge/tests/run.sh`.
#
# 1. check-release.sh on the real plugin (manifest valid, version == CHANGELOG.md top release).
# 2. Every selvedge/tests/test-*.sh, each in its own bash; any failure fails the gate. Zero tests
#    found is a failure too (fail CLOSED: a glob that silently matches nothing is not a pass).
#
# selvedge imports nothing from Loomwright: nothing here sources, execs or reads a path under
# loomwright/, and each test sets up its own temp HOME. Works from any cwd. Exit 0 pass, 1 fail.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$TESTS_DIR/.." && pwd)"

failed=0
echo "== selvedge gate: release consistency"
bash "$TESTS_DIR/check-release.sh" "$PLUGIN_DIR" || failed=1

ran=0
for t in "$TESTS_DIR"/test-*.sh; do
  [ -f "$t" ] || continue
  ran=$((ran + 1))
  echo "== selvedge gate: $(basename "$t")"
  bash "$t" || { echo "selvedge gate: FAIL $(basename "$t")" >&2; failed=1; }
done
[ "$ran" -gt 0 ] || { echo "selvedge gate: FAIL no tests/test-*.sh found under $TESTS_DIR" >&2; failed=1; }

if [ "$failed" -eq 0 ]; then
  echo "selvedge gate: PASS (release check + $ran test file(s))"
else
  echo "selvedge gate: FAIL" >&2
fi
exit "$failed"
