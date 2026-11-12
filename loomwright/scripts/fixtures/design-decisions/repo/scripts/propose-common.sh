#!/usr/bin/env bash
# propose-common.sh — shared helpers for the fixture repo's note scripts. Sourced, never executed.
# Fixture for loomwright/scripts/test-design-decisions.sh (brief-c): this file already provides the
# slug helper that brief-c's new scripts/slugify.sh would hand-roll.

# pc_slugify <text> — lower-case, every run of non-alphanumerics becomes one '-', no leading or
# trailing '-'. Prints the slug.
pc_slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed -e 's/^-*//' -e 's/-*$//'
}
