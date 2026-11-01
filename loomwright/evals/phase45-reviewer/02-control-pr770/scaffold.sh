#!/usr/bin/env bash
# 02-control-pr770 — stages PR #770's pre-drain diff into the eval sandbox (cwd) through the shared stager
exec bash "$(dirname "${BASH_SOURCE[0]}")/../lib/stage-case.sh" "$(dirname "${BASH_SOURCE[0]}")"
