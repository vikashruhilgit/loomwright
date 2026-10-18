# The exact content apply WOULD write (deterministic → byte-comparable for idempotency).
proposed_applied_content() {
  strip_managed_block < "$GI" | comment_bare_excludes
  managed_block
}

# The exact content remove WOULD write.
proposed_removed_content() {
  strip_managed_block < "$GI" | uncomment_bare_excludes
}

# unique_backup_path <file> → a `<file>.backup.<ts>` sibling that does NOT already exist, or
# NOTHING (empty stdout, status 1) when every candidate name is taken.
#
# The timestamp is second-granular, so two writes inside the SAME second resolve to the same name
# and the second `cp` would OVERWRITE the first backup — destroying the user's PRISTINE original,
# which is the single file the whole backup-first contract exists to protect (the later backup
# only holds this tool's own output). The plain `<file>.backup.<ts>` form is kept for the common
# case because it is the documented name; a collision falls back to a pid-qualified name, then to
# a counter bounded at $BACKUP_MAX_TRIES.
#
# EXHAUSTION FAILS CLOSED. The bounded counter cannot promise "a free name always exists", so when
# it runs out this returns EMPTY rather than a path it never verified — an earlier version fell out
# of the loop at the bound and returned `$base.$$.<bound>` WITH that file still present, which the
# caller's `cp` would then have overwritten. Callers MUST treat empty as "no backup is possible"
# and abort without writing (write_gitignore / seed_allowlist both do). Asserted in
# test-setup-memory.sh group (e), which seeds every candidate name and asserts the write is refused
# and the pre-existing backup is left byte-identical.
BACKUP_MAX_TRIES=1000
unique_backup_path() {
  local f="$1" ts base n
  ts="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo unknown)"
  base="$f.backup.$ts"
  if [ ! -e "$base" ]; then printf '%s' "$base"; return 0; fi
  if [ ! -e "$base.$$" ]; then printf '%s' "$base.$$"; return 0; fi
  n=1
  while [ "$n" -le "$BACKUP_MAX_TRIES" ]; do
    if [ ! -e "$base.$$.$n" ]; then printf '%s' "$base.$$.$n"; return 0; fi
    n=$((n + 1))
  done
  return 1
}

# Backup-first + atomic replace. Echoes the backup path on success.
write_gitignore() {
  local content="$1" backup tmp
  backup="$(unique_backup_path "$GI")"
  if [ -z "$backup" ]; then
    echo "setup-memory: every backup name for $GI is already taken (${BACKUP_MAX_TRIES}+ collisions); refusing to overwrite an existing backup — nothing changed." >&2
    return 1
  fi
  cp "$GI" "$backup" 2>/dev/null || { echo "setup-memory: could not write backup $backup — nothing changed." >&2; return 1; }
  tmp="$GI.tmp.$$"
  printf '%s\n' "$content" > "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; echo "setup-memory: could not stage the rewrite — nothing changed." >&2; return 1; }
  mv "$tmp" "$GI" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; echo "setup-memory: could not replace .gitignore — nothing changed." >&2; return 1; }
  printf '%s' "$backup"
}
