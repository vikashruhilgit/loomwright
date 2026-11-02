#!/usr/bin/env bash
# 01-control-pr651 — stages PR #651's pre-drain diff into the eval sandbox (cwd) through the shared stager
exec bash "$(dirname "${BASH_SOURCE[0]}")/../lib/stage-case.sh" "$(dirname "${BASH_SOURCE[0]}")"
