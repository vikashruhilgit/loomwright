#!/usr/bin/env bash
# automate-helpers.d/status-stamp.sh — the one reader of a requirement's `## Status:` stamps. Sourced, never run:
# deliberately not named test-*.sh. Self-test: loomwright/scripts/test-status-stamp.sh.
# It lives in this directory because every layout that carries automate-helpers.sh carries this directory too.
#
# Why: requirement files quote stamps as examples. A proposal about closeout showed the
# `## Status: done` block in a code fence, so a plain `grep '^## Status: done'` read that unstarted
# draft as finished: `/backlog` listed it done and `resolve-folder` never queued it. Separate grep
# copies also disagreed on what done means: two only accepted a bare `## Status: done`, so the
# `done (PR #N, merge <sha>)` stamp that `reconcile-status` writes did not count there.
#
# Any line outside a fence counts, not just the first: `closeout` appends its stamp below an older
# `## Status: pending`, so a stale first line is normal (the first-line rules that want the heading
# use their own readers).
#
# Fail direction: wrongly reading a finished item as not done re-runs merged work, so every doubt
# keeps the plain any-line answer. A fence that never closes is not treated as a fence (a stray
# ``` above an appended stamp must not hide it), and a failing filter keeps the grep's answer.
# Only a line starting with ``` or ~~~ opens or closes a fence, so a `> ` quote or an indented example is
# handled by the `^## Status:` anchor instead. Bash 3.2 / BSD safe; set -u safe.

STATUS_DONE_ERE='^## Status:[[:space:]]*done(_with_escalation)?\b'
STATUS_NOT_READY_ERE='^## Status:[[:space:]]*(proposed|parked)\b'

# status_unfenced <file> — the file without its closed code fences (``` or ~~~), in file order. A
# fence that never closes keeps its lines. For a reader that needs more than a heading, such as a
# closeout block and its PR line: feed it with a here-string, not a pipe, because an awk that exits
# early makes the producer return 141 under pipefail.
status_unfenced() {
  env LC_ALL=C awk '
    /^(```|~~~)/ { n = 0; inf = !inf; next }
    inf { buf[++n] = $0; next }
    { print }
    END { for (i = 1; i <= n; i++) if (inf) print buf[i] }' "$1" 2>/dev/null
}

# status_has <file> <ere> — true when a line status_unfenced keeps matches <ere>.
status_has() {
  local l
  grep -qE "$2" "$1" 2>/dev/null || return 1
  l="$(status_unfenced "$1")" || return 0
  grep -qE "$2" <<<"$l"
}

# status_is_done <file> — a terminal stamp: `done` or `done_with_escalation`, with or without a
# suffix. An escalated or abandoned item is terminal too, so nothing re-offers it.
status_is_done() { status_has "$1" "$STATUS_DONE_ERE"; }

# status_is_not_ready <file> — a `proposed` or `parked` stamp.
status_is_not_ready() { status_has "$1" "$STATUS_NOT_READY_ERE"; }
