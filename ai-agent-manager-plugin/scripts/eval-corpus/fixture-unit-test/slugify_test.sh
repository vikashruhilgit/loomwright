#!/usr/bin/env bash
# slugify_test.sh — unit test for the bundled slugify() fixture function.
# Arrange-Act-Assert: source the function, call it, assert on the output.
# Exit 0 = all assertions pass; exit 1 = any assertion fails. Deterministic.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=slugify.sh
. "$HERE/slugify.sh"

fail=0
assert_eq() {  # assert_eq <description> <actual> <expected>
  local desc="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then
    echo "  ok: $desc"
  else
    echo "  FAIL: $desc — got '$actual', expected '$expected'"
    fail=1
  fi
}

# 1. basic lowercasing + space-to-dash
assert_eq "'Hello World' -> hello-world" "$(slugify 'Hello World')" "hello-world"

# 2. leading/trailing junk trimmed, internal punctuation collapsed to single dash
assert_eq "'  --Foo_Bar!!  ' -> foo-bar" "$(slugify '  --Foo_Bar!!  ')" "foo-bar"

# 3. empty input -> empty output
assert_eq "'' -> ''" "$(slugify '')" ""

# 4. all-punctuation input -> empty (no alphanumerics survive)
assert_eq "'***' -> ''" "$(slugify '***')" ""

# 5. mixed alphanumerics preserved, runs squeezed
assert_eq "'A  B   C' -> a-b-c" "$(slugify 'A  B   C')" "a-b-c"

if [ "$fail" -eq 0 ]; then
  echo "slugify_test: all assertions passed"
  exit 0
else
  echo "slugify_test: assertions FAILED"
  exit 1
fi
