---
name: no_pipe_grep_q_in_tests
title: no_pipe_grep_q_in_tests
description: In new self-tests assert with grep -q < <(producer), never producer | grep -q (pipefail 141 on match; the test-no-pipefail-grep-q lint fails the PR)
metadata:
  type: feedback
source: dreaming:1378d676-ffcd-40f8-b6be-5e60d2dbd1ec
written_at: 2026-10-02T07:24:49Z
head_sha: c594e83
---

In new self-tests assert with `grep -q < <(producer)`, never `producer | grep -q`: under pipefail the pipe form returns 141 even on a match, and the `test-no-pipefail-grep-q` lint fails the PR.

**Why:** automate-followups-13 wrote 2 such asserts and parallel-automate-02 wrote 17; all had to be rewritten.

**How to apply:** in coverage review, treat a pipe-form assert as a latent failure.
