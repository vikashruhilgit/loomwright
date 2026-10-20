#!/usr/bin/env bash
# 03-non-interactive-escalated-park — stages the golden case `gate-validation-gate-unrun-escalated` into the eval sandbox (cwd) through the shared stager
exec bash "$(dirname "${BASH_SOURCE[0]}")/../lib/stage-golden.sh" gate-validation-gate-unrun-escalated
