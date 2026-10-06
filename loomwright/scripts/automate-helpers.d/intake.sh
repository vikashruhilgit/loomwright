# resolve-folder <dir> — every *.md NOT marked "## Status: done" and not
# "## Status: proposed|parked" (sorted).
resolve_folder() {
  local dir="$1" f
  [ -d "$dir" ] || die "folder not found: $dir"
  for f in "$dir"/*.md; do
    [ -e "$f" ] || continue
    is_done "$f" && continue
    is_not_ready "$f" && continue
    echo "$f"
  done | env LC_ALL=C sort
}

# resolve-backlog <backlog.md> — emit items in DOCUMENTED build order, honoring
# done/✅ markers (SKILL §2 "Backlog-doc source"). We parse "- [ ] <path>" /
# "- [x] <path>" checklist lines (the documented order = file order) and emit
# only the not-done ones. Done is read from TWO places, either one excludes:
#   (1) the line — a checked "[x]" box, a "✅", or an inline "# Status: done";
#   (2) the file the line names — its own `## Status: done|done_with_escalation`
#       heading (`is_done`, the predicate resolve-folder and the dir fallback
#       use). This is the evidence-gated truth: `closeout` writes that stamp
#       after reading the PR MERGED, and the engine never ticks the backlog doc
#       (human-owned), so without (2) every merged item is re-queued by the next
#       `--backlog` run. Resolved by `_backlog_item_file`: an unresolvable path is
#       NOT read and the line stays listed (fail toward listing).
# _BACKLOG.md-absent ⇒ fall back to dir scan.
# SCOPE BOUNDARY (deliberate, not an oversight): a checklist line here names a
# path directly, which is a human's explicit inclusion decision for that line.
# So the NOT-READY stamp (`## Status: proposed|parked`, `is_not_ready`) is
# honoured ONLY on the dir-fallback path below (`resolve_backlog_dir`), never
# when a checklist line directly names an existing file. The DONE stamp is
# different — nobody includes merged work on purpose — so (2) applies here.
# _backlog_item_file <payload> <backlog.md> — the file a checklist payload names,
# for the read-only `is_done` check above, or nothing. Tried as written (relative
# to the cwd — the repo root the loop runs from — or absolute), then relative to
# the backlog doc's directory. Same safety rules as the dir fallback, which only
# ever reads `*.md` entries: the candidate must end in `.md` and be a regular
# file (`-f` follows a symlink to a regular file, exactly as the dir fallback's
# glob does). A leading `-` is defused with `./` so `grep` never takes it as an
# option. Anything else — empty, missing, a directory, a non-`*.md` — prints
# nothing, and the caller keeps the line listed.
_backlog_item_file() {
  local p="$1" doc="$2" c
  case "$p" in *.md) ;; *) return 0 ;; esac
  for c in "$p" "$(dirname "$doc")/$p"; do
    case "$c" in /*) ;; *) c="./$c" ;; esac
    if [ -f "$c" ]; then printf '%s\n' "$c"; return 0; fi
    case "$p" in /*) return 0 ;; esac   # absolute: no doc-relative retry
  done
  return 0
}

resolve_backlog() {
  local doc="$1"
  if [ ! -f "$doc" ]; then
    # Fallback: scan the directory the path points into by ## Status: stamp.
    local d; d="$(dirname "$doc")"
    [ -d "$d" ] && resolve_backlog_dir "$d"
    return 0
  fi
  # Preserve documented order; emit not-done checklist items.
  while IFS= read -r line; do
    case "$line" in
      "- [x] "*|"- [X] "*) continue ;;          # checked ⇒ done
      "- [ ] "*)
        # NOTE: '[' and ']' are glob metachars in parameter-expansion patterns,
        # so strip the fixed 6-char "- [ ] " prefix by offset, not by '#- [ ] '.
        local payload="${line:6}"
        case "$payload" in
          *"✅"*) continue ;;                    # explicit done marker
          *"# Status: done"*|*"## Status: done"*) continue ;;
        esac
        # strip any trailing inline comment / marker, keep the item token
        payload="${payload%%  #*}"
        local item_file
        item_file="$(_backlog_item_file "$payload" "$doc")"
        if [ -n "$item_file" ] && is_done "$item_file"; then continue; fi   # (2) file stamp
        echo "$payload"
        ;;
    esac
  done < "$doc"
}

# resolve_backlog_dir <dir> — fallback ordering by directory order over *.md,
# excluding ## Status: done files and ## Status: proposed|parked files.
resolve_backlog_dir() {
  local dir="$1" f
  for f in "$dir"/*.md; do
    [ -e "$f" ] || continue
    is_done "$f" && continue
    is_not_ready "$f" && continue
    echo "$f"
  done | env LC_ALL=C sort
}

