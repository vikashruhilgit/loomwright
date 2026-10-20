#!/usr/bin/env bash
# 04-done-check-off — stages the golden case `check-off-progress` into the eval sandbox (cwd) through the shared stager
exec bash "$(dirname "${BASH_SOURCE[0]}")/../lib/stage-golden.sh" check-off-progress
