---
name: bash32-heredoc-in-cmdsubst-apostrophe
title: bash32-heredoc-in-cmdsubst-apostrophe
description: An apostrophe inside a quoted heredoc (<<'PY') nested in $(...) makes macOS /bin/bash 3.2 fail to PARSE the whole script; suites stay green because PATH `bash` is Homebrew 5.x
metadata:
  type: project
source: PR #305 iteration-2 review (2026-09-30) — loomwright/scripts/automate-trail.sh:106 "drain-rounds.sh's" broke /bin/bash -n at every commit of the file; test-automate-trail.sh passed 142/142 because inner `bash` resolved to /opt/homebrew/bin/bash.
written_at: 2026-10-02T07:21:38Z
head_sha: c594e83
---

When a diff adds a script with `x="$(cmd <<'EOF' ... EOF\n)"`, run `/bin/bash -n <file>` explicitly (not `bash -n`) and grep the heredoc body for unbalanced ' or `. A test invoking `bash script.sh` under `/bin/bash test.sh` still runs the child under PATH bash.
