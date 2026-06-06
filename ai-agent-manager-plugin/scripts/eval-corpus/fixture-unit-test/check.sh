#!/usr/bin/env bash
# check.sh — fixture-unit-test eval task.
# Fully self-contained "a function plus its passing unit test" eval shape: no repo
# dependency. The task dir ships slugify.sh (the function under test) and
# slugify_test.sh (its unit test). Pass iff the bundled unit test passes.
# Deterministic and self-contained. The runner cd's into this dir first, so the
# test is reachable by relative path.
set -uo pipefail

bash slugify_test.sh
exit $?
