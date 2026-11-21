#!/usr/bin/env bash
# stub-driver.sh — a SELVEDGE_EVAL_TARGET_DRIVER for test-eval-harness.sh (not named test-*, so
# run.sh never runs it). Brings nothing up: `up` prints origin=http://localhost:9 and root=<workdir>,
# or, with STUB_DRIVER_FAIL set, fails the way target-driver.sh does (exit 1, the step named).
# Every call appends "<command> <args>" to $STUB_LOG/driver.log.
set -uo pipefail
log="${STUB_LOG:?STUB_LOG must be set}"
mkdir -p "$log"
echo "$*" >>"$log/driver.log"
case "${1:-}" in
  up)
    if [ -n "${STUB_DRIVER_FAIL:-}" ]; then echo "target-driver: FAIL step 'npm ci': stub failure" >&2; exit 1; fi
    mkdir -p "$3"
    echo "origin=http://localhost:9"
    echo "root=$3"
    ;;
  down|stop) ;;
  *) exit 2 ;;
esac
