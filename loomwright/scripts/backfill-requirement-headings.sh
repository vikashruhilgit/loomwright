#!/usr/bin/env bash
# backfill-requirement-headings.sh <requirements_root> [--apply]
#
# OWNER-RUN, ONE-TIME. closeout now rewrites a requirement's first `## Status:` line when it stamps
# (requirement-heading.sh). Files stamped before that, and files stamped by `reconcile-status --apply`
# or `backlog-stamp`, which still only append, keep opening with `## Status: pending`. This rewrites
# those headings. No hook, skill or agent calls it.
#
# DRY RUN BY DEFAULT: without --apply nothing is opened for writing.
#
# IT PROMOTES NOTHING. A file is a candidate only when it already carries a real close-out block (the
# sentinel line, unfenced, immediately above a done / done_with_escalation heading), so is_done already
# reads it as done. The heading takes the last such block's value and every PR that block names. HONEST
# LIMIT: it does not re-read whether those PRs merged; it copies a claim the file already makes, and
# trail-pr's evidence gate checks the PRs when the file is pushed.
#
# OUTPUT (tab-separated; <file> is relative to <requirements_root>):
#   plan\t<file>\t<first status line>\t<heading it would get>
#   rewrote\t<file>\t<first status line>\t<heading it got>
#   skip\t<file>\t<reason>      an explicit pending/ready heading that is left alone: the block is
#                               ABANDONED (an owner decision, no shipped-work claim), or names no PR
#                               (the rewritten heading would fail trail-pr's evidence gate)
#   fail\t<file>\tnot writable
# then one `summary` row. A file whose first status line is anything else is not listed. Re-running
# after --apply finds nothing, so it is idempotent. Exit 0, also when a row reads `fail`; exit 2 on usage.
#
# BRANCH MODE. The requirements folder lives on the metadata branch, so push the rewritten files
# afterwards by exact list (`meta-sync.sh push --paths-from <list>`), never a whole-tree push.

set -u
HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo .)"
# shellcheck source=/dev/null
. "$HERE/requirement-heading.sh"

ROOT=""; APPLY=0
for a in "$@"; do
  case "$a" in
    --apply) APPLY=1 ;;
    -*) echo "backfill-requirement-headings: unknown flag: $a" >&2; exit 2 ;;
    *) if [ -z "$ROOT" ]; then ROOT="$a"; else echo "backfill-requirement-headings: extra argument: $a" >&2; exit 2; fi ;;
  esac
done
if [ -z "$ROOT" ] || [ ! -d "$ROOT" ]; then
  echo "usage: backfill-requirement-headings.sh <requirements_root> [--apply]" >&2; exit 2
fi

# _bf_block <file> — the LAST real close-out block: line 1 is its value (done | done_with_escalation),
# or `abandoned` when its heading is an ABANDONED stamp; the rest, one first `…/pull/<n>` token per
# `- **PR:**` line of the block. Prints nothing when the file has no real block. Same fence rule and
# same PR token as requirement-heading.sh and trail-pr's _done_prs.
_bf_block() {
  env LC_ALL=C awk '
    BEGIN { s = "<!-- loomwright:requirement-closeout -->" }
    { sub(/\r$/, "") }
    /^(```|~~~)/ { f = !f; prev = 0; inb = 0; next }
    f { next }
    prev && /^## Status:[[:space:]]*done(_with_escalation)?([^A-Za-z0-9_]|$)/ {
      v = ($0 ~ /^## Status:[[:space:]]*done_with_escalation/) ? "done_with_escalation" : "done"
      if ($0 ~ /ABANDONED/) v = "abandoned"
      n = 0; inb = 1; prev = 0; next
    }
    inb && /^## / { inb = 0 }
    inb && /^- \*\*PR:\*\*/ && match($0, /https?:\/\/[^][:space:]()<>]+\/pull\/[0-9]+/) { P[++n] = substr($0, RSTART, RLENGTH) }
    { prev = ($0 == s) }
    END { if (v != "") { print v; for (i = 1; i <= n; i++) print P[i] } }' "$1" 2>/dev/null
}

planned=0; rewrote=0; skipped=0; failed=0
while IFS= read -r -d '' f; do
  n="$(req_open_heading_line "$f")"
  [ -n "$n" ] || continue
  block="$(_bf_block "$f")"
  [ -n "$block" ] || continue
  rel="${f#"$ROOT"/}"
  value="${block%%$'\n'*}"
  prs=""; case "$block" in *$'\n'*) prs="${block#*$'\n'}" ;; esac
  if [ "$value" = abandoned ]; then
    printf 'skip\t%s\tblock is ABANDONED\n' "$rel"; skipped=$((skipped + 1)); continue
  fi
  if [ -z "$prs" ]; then
    printf 'skip\t%s\tblock names no PR\n' "$rel"; skipped=$((skipped + 1)); continue
  fi
  old="$(sed -n "${n}p" "$f" | tr -d '\r')"
  if [ "$APPLY" -eq 0 ]; then
    printf 'plan\t%s\t%s\t## Status: %s\n' "$rel" "$old" "$value"; planned=$((planned + 1))
  elif req_heading_write "$f" "$n" "$value" "$prs" ""; then
    printf 'rewrote\t%s\t%s\t## Status: %s\n' "$rel" "$old" "$value"; rewrote=$((rewrote + 1))
  else
    printf 'fail\t%s\tnot writable\n' "$rel"; failed=$((failed + 1))
  fi
done < <(find "$ROOT" -type f -name '*.md' -print0 | env LC_ALL=C sort -z)

if [ "$APPLY" -eq 0 ]; then
  printf 'summary\tdry run: %s would be rewritten, %s skipped; nothing written (pass --apply)\n' "$planned" "$skipped"
else
  printf 'summary\t%s rewritten, %s skipped, %s failed\n' "$rewrote" "$skipped" "$failed"
fi
exit 0
