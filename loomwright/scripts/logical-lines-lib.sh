#!/usr/bin/env bash
# logical-lines-lib.sh — the shared line reader for the self-tests that lint shell source by regex
# (test-no-pipefail-grep-q.sh, test-base-branch-single-resolver.sh). Sourced, never run: like
# wait-lib.sh it is deliberately not named test-*.sh, so the run-self-tests.sh glob never runs it.
#
#   logical_lines <file>   prints `startline:text` per LOGICAL line: backslash-continued lines are
#                          joined (so a pattern split across a continuation is still one line),
#                          whole-line comments are dropped and a trailing ` # comment` is stripped
#                          (so prose that NAMES a form is never red). Always returns 0.
#
# Honest limit: it is a line reader, not a shell parser — a `#` inside a quoted string followed by a
# space is treated as a comment start, and heredoc bodies are read as code.
# Bash 3.2 / BSD awk safe.

logical_lines() {
  awk '{ if (buf == "") start = NR
         if ($0 ~ /\\$/) { buf = buf substr($0, 1, length($0) - 1) " "; next }
         print start ":" buf $0; buf = "" }
       END { if (buf != "") print start ":" buf }' "$1" \
    | grep -vE '^[0-9]+:[[:space:]]*#' | sed -E 's/[[:space:]]#[[:space:]].*$//'
  return 0
}
