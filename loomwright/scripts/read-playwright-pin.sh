#!/usr/bin/env bash
# read-playwright-pin.sh — the ONE reader of the `PW_TEST_VERSION=<x.y.z>` pin line in
# test-verify-walkthrough.sh. `.github/workflows/ci.yml` derives its actions/cache key for the
# @playwright/test + chromium cache from this script's stdout, so the pin line is the single
# source of truth for when that cache turns over, and this script is the single place the line
# is parsed (the workflow used to carry the same `sed` inline — a regex no committed test could
# reach; test-read-playwright-pin.sh now mutation-tests THIS file and asserts the workflow
# invokes it rather than a duplicate).
#
# Contract:
#   usage: read-playwright-pin.sh [<file>]      (default: test-verify-walkthrough.sh beside this file)
#   stdout: exactly the version (`x.y.z`, no quotes, no trailing comment) — and NOTHING on any
#           failure path, because an empty cache key would cache nothing, silently, which is the
#           same "gate that passes vacuously" the workflow forbids elsewhere.
#   exit 0  = one and only one matching line was found and printed
#   exit 1  = FAIL CLOSED: the file is missing/unreadable, no line matches, or more than one line
#             matches (an ambiguous pin) — reason on stderr
#
# The pattern is deliberately anchored on the WHOLE line (`^PW_TEST_VERSION=<digits.digits.digits>$`):
# a range (`=1`), a quoted value (`="1.63.0"`) and a trailing comment (`=1.63.0 # …`) all fail, on
# purpose — each would hand the cache a key that does not name an exact install.
set -euo pipefail

if [ "$#" -gt 1 ]; then
  echo "usage: read-playwright-pin.sh [<file>]" >&2
  exit 1
fi
file="${1:-$(dirname "${BASH_SOURCE[0]}")/test-verify-walkthrough.sh}"

if [ ! -f "$file" ] || [ ! -r "$file" ]; then
  echo "read-playwright-pin: cannot read $file — the Playwright cache key would be empty" >&2
  exit 1
fi

matches="$(sed -n 's/^PW_TEST_VERSION=\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)$/\1/p' "$file")"
# awk, not `grep -c`: grep -c exits 1 on zero matches, which under `set -e` would need a `|| true`
# — the exact masking construct this file must not carry. awk exits 0 and prints the count.
count="$(printf '%s\n' "$matches" | awk 'NF { n++ } END { print n + 0 }')"

case "$count" in
  1) printf '%s\n' "$matches"; exit 0 ;;
  0) echo "read-playwright-pin: no \`PW_TEST_VERSION=<x.y.z>\` line in $file — the Playwright cache key would be empty" >&2; exit 1 ;;
  *) echo "read-playwright-pin: $count \`PW_TEST_VERSION=<x.y.z>\` lines in $file — ambiguous pin, refusing to pick one" >&2; exit 1 ;;
esac
