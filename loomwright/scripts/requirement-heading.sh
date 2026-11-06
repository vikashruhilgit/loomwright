#!/usr/bin/env bash
# requirement-heading.sh — the ONE writer of a done requirement's first `## Status:` line.
#
# SOURCED, NEVER EXECUTED. Callers: automate-trail.d/closeout.sh (step 5, in the same write as its
# appended block) and backfill-requirement-headings.sh (owner-run, for files stamped earlier). It
# defines functions; it runs nothing and writes nothing at source time.
#
# WHY. closeout appends its done block to the END of a requirement, so the file used to open with
# `## Status: pending` and end with `## Status: done`. Plugin readers handle that (is_done matches any
# line), but a person, an editor outline or `grep -m1 '^## Status'` reads `pending`.
#
# THE SHAPE, and why it is two lines:
#     ## Status: done
#     - **PR:** <url>
# trail-pr's evidence gate (_done_prs) treats EVERY done heading as a claim, reads the `- **PR:**` lines
# of that heading's own block (up to the next `## `), and fails closed on a block naming none. A bare
# `## Status: done` above `## Problem` would therefore stop the requirement riding the trail. Carrying
# the PR under the heading keeps the gate unchanged and still checking that PR.
#
# WHAT IS REWRITTEN: only an explicit `pending` / `ready` first heading, the same words
# _rs_first_status_open reads (`pending — note` counts and the note goes with it; `ready_for_release`
# and `pending-review` do not). Everything else stays: `proposed` / `parked` are owner decisions,
# `brief-shipped` keeps its "job landed, acceptance criteria not machine-verified" record, and any
# free-text heading is a person's statement. A `## Status:` line inside a fenced block is a quotation,
# never the heading.
#
# READERS (re-check on any change here). Each of these is decided by is_done before the first line is
# consulted, so a file this rewrites classifies as it did: is_not_ready's callers, backlog.sh's
# first-line rules (parked / proposed / brief_shipped / open) and _bl_is_conflict,
# _rs_first_status_open, and reconcile-status's status_hdr. backlog.sh's `abandoned` test and evidence
# read the LAST terminal line, which is still the appended block.

# req_open_heading_line <file> — the line number of the file's first unfenced `## Status:` line when it
# reads explicit pending/ready; prints nothing otherwise.
req_open_heading_line() {
  local n
  n="$(env LC_ALL=C awk '/^(```|~~~)/ { f = !f; next } !f && /^## Status:/ { print NR; exit }' "$1" 2>/dev/null)"
  [ -n "$n" ] || return 0
  sed -n "${n}p" "$1" 2>/dev/null \
    | env LC_ALL=C grep -qE '^## Status:[[:space:]]*(pending|ready)([^A-Za-z0-9_-]|$)' && printf '%s\n' "$n"
  return 0
}

# req_heading_write <file> <line|""> <value> <pr urls, one per line> <tail text|""> — ONE atomic write:
# line <line> becomes `## Status: <value>` plus one `- **PR:** <url>` line per url (a CRLF heading stays
# CRLF), and <tail text>, when given, is appended. An empty <line> only appends. Every other byte is
# unchanged. Temp file beside the target, then rename, so a reader or a crash never sees half of it.
# A symlink is never replaced by a rename, so it gets the append alone. Returns non-zero with the file
# unchanged when it cannot write.
req_heading_write() {
  local f="$1" n="$2" value="$3" prs="$4" tail_text="$5" tmp cr="" head_line url
  [ -w "$f" ] || return 1
  if [ -L "$f" ]; then
    [ -z "$tail_text" ] || printf '%s\n' "$tail_text" >> "$f" 2>/dev/null || return 1
    return 0
  fi
  tmp="$(mktemp "$f.XXXXXX" 2>/dev/null)" || return 1
  if [ -n "$n" ]; then
    head_line="$(sed -n "${n}p" "$f" 2>/dev/null)"
    case "$head_line" in *$'\r') cr=$'\r' ;; esac
  fi
  if cp -p "$f" "$tmp" 2>/dev/null && {
      if [ -z "$n" ]; then
        cat "$f"
      else
        { [ "$n" -le 1 ] || head -n "$((n - 1))" "$f"; } \
          && printf '## Status: %s%s\n' "$value" "$cr" \
          && while IFS= read -r url; do
               [ -z "$url" ] || printf -- '- **PR:** %s%s\n' "$url" "$cr"
             done <<<"$prs" \
          && tail -n "+$((n + 1))" "$f"
      fi && { [ -z "$tail_text" ] || printf '%s\n' "$tail_text"; }
    } > "$tmp" 2>/dev/null && mv -f "$tmp" "$f" 2>/dev/null; then
    return 0
  fi
  rm -f "$tmp"
  return 1
}
