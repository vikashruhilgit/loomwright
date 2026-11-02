#!/usr/bin/env bash
# test-automate-trail.3.sh — the pool entry for group 3 of test-automate-trail.sh (part-groups-lib.sh): the pool
# runs each test-*.sh as one job, so a group of that suite's parts runs concurrently with the others.
# The group's parts are named in that file's group map; this file only runs them.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
exec "${BASH:-bash}" "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test-automate-trail.sh" --group 3
