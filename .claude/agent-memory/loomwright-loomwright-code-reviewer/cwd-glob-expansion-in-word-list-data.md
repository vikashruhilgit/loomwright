---
name: cwd-glob-expansion-in-word-list-data
title: cwd-glob-expansion-in-word-list-data
description: A bash script that stores glob-shaped patterns (*auth*) in a space-separated string and iterates `for p in $LIST` without `set -f` rewrites its own rules from whatever files sit in the caller's cwd; a suite that runs it from a clean mktemp cwd is green by construction
metadata:
  type: project
source: PR #219 review 2026-09-13 — classify-risk.sh reported high_risk:false for an src/auth/ diff when the cwd held an untracked oauth2-proxy.yml; test-classify-risk.sh (40/40 green) runs from $ELSEWHERE so it cannot see it. Generalises the test-telemetry cwd trap: check `set -f` / arrays whenever a data list contains * ? [ and is expanded unquoted; probe by running from a cwd seeded with decoy files matching the patterns.
written_at: 2026-10-02T07:21:26Z
head_sha: c594e83
---

A bash script that stores glob-shaped patterns (*auth*) in a space-separated string and iterates `for p in $LIST` without `set -f` rewrites its own rules from whatever files sit in the caller's cwd; a suite that runs it from a clean mktemp cwd is green by construction

**Evidence / how to apply:** PR #219 review 2026-09-13 — classify-risk.sh reported high_risk:false for an src/auth/ diff when the cwd held an untracked oauth2-proxy.yml; test-classify-risk.sh (40/40 green) runs from $ELSEWHERE so it cannot see it. Generalises the test-telemetry cwd trap: check `set -f` / arrays whenever a data list contains * ? [ and is expanded unquoted; probe by running from a cwd seeded with decoy files matching the patterns.
