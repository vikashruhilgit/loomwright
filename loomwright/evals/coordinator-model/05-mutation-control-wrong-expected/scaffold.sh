#!/usr/bin/env bash
# 05-mutation-control-wrong-expected — stages the golden case `escalated-park` into the eval sandbox (cwd) through the shared stager
exec bash "$(dirname "${BASH_SOURCE[0]}")/../lib/stage-golden.sh" escalated-park --mutate-expected
