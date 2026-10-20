#!/usr/bin/env bash
# 02-ask-interactive-decide-then-park — stages the golden case `dismissed-findings-decision-step` into the eval sandbox (cwd) through the shared stager
exec bash "$(dirname "${BASH_SOURCE[0]}")/../lib/stage-golden.sh" dismissed-findings-decision-step
