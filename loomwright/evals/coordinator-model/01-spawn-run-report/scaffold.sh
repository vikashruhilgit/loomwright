#!/usr/bin/env bash
# 01-spawn-run-report — stages the golden case `run-config-suppress-restore` into the eval sandbox (cwd) through the shared stager
exec bash "$(dirname "${BASH_SOURCE[0]}")/../lib/stage-golden.sh" run-config-suppress-restore
