# --------------------------------------------------------------------------- #
# §7 — config suppress / restore (byte-for-byte; absent-delete; malformed-abort)
# --------------------------------------------------------------------------- #

# config-suppress <config_path> <backup_path>
# Backs up an existing config byte-for-byte to <backup_path>, then writes a config
# with .auto_review=false. If the config is ABSENT, no backup is made (absence is
# recorded by config-restore's marker semantics) and a minimal {"auto_review":false}
# is written. A MALFORMED pre-existing config ⇒ ABORT (exit 2) — never clobber a
# hand-edited config (SKILL §7 "malformed-abort"; Anti-Pattern).
config_suppress() {
  local cfg="$1" bak="$2"
  if [ -f "$cfg" ]; then
    # Validate JSON before touching anything.
    if ! "$JQ" -e . "$cfg" >/dev/null 2>&1; then
      abort "pre-existing config is not valid JSON: $cfg"
    fi
    # Byte-for-byte backup (cp preserves exact bytes).
    cp "$cfg" "$bak"
    # Merge auto_review=false into the existing object (atomic temp+rename).
    local tmp; tmp="$(mktemp "${cfg}.XXXXXX")"
    "$JQ" '.auto_review = false' "$cfg" > "$tmp"
    mv -f "$tmp" "$cfg"
  else
    # Originally absent: write a marker backup so restore knows to DELETE on restore.
    printf '__ABSENT__\n' > "$bak"
    printf '{"auto_review":false}\n' > "$cfg"
  fi
}

# config-restore <config_path> <backup_path>
# Restores config from the backup, OR DELETES config if it was originally absent
# (backup holds the __ABSENT__ marker). Deletes the transient backup on success.
# Never leaves a partial config.json (SKILL §7 "absent-delete").
config_restore() {
  local cfg="$1" bak="$2"
  [ -f "$bak" ] || die "no backup to restore: $bak"
  if [ "$(head -n1 "$bak")" = "__ABSENT__" ]; then
    rm -f "$cfg"
  else
    # Atomic restore (temp+rename) so a crash mid-restore can't half-write.
    local tmp; tmp="$(mktemp "${cfg}.XXXXXX")"
    cp "$bak" "$tmp"
    mv -f "$tmp" "$cfg"
  fi
  rm -f "$bak"
}

# config-orig <config_path> [<backup_path>]
# Prints the auto_review_original value to record in ## Run Config: true|false|absent.
#
# CALL-ORDER (§7): the contract sequence is backup -> suppress -> record, so this is
# normally called AFTER config_suppress has rewritten the live config to
# auto_review:false — at which point the LIVE file reports "false" for every original
# and only the byte-for-byte backup still holds the truth. So when <backup_path>
# exists we read THE BACKUP; otherwise we fall back to the live config (the
# pre-suppress call order, where the live config IS the original). The answer is
# therefore the same in either call order. Losing the true/false/absent distinction
# by reading the wrong FILE would defeat the same care the value-extraction below
# takes to avoid losing it by using the wrong OPERATOR.
#
# A backup path that is GIVEN but MISSING falls back to the live config; it does NOT
# abort the way a MALFORMED backup does (they are different kinds of event: malformed
# can never be legitimate, missing is the normal state of a correct PRE-suppress 2-arg
# call, and aborting on it would re-introduce call-order dependence in the other
# direction). The residual: if the backup is lost AFTER suppress (stale/reused run_id,
# partial cleanup, a race with a concurrent restore) the fallback reports the SUPPRESSED
# value as the original. The helper cannot distinguish that from the pre-suppress call —
# both are "2 args, no backup on disk" — so only the CALLER can prevent it, by recording
# the original before deleting the backup. Both arms pinned in test §A7f; SKILL.md §7.
config_orig() {
  local cfg="$1" bak="${2:-}" src
  if [ -n "$bak" ] && [ -f "$bak" ]; then
    # The __ABSENT__ marker means there was no pre-existing config at suppress time.
    if [ "$(head -n1 "$bak")" = "__ABSENT__" ]; then echo "absent"; return 0; fi
    src="$bak"
  else
    src="$cfg"
  fi
  if [ ! -f "$src" ]; then echo "absent"; return 0; fi
  if ! "$JQ" -e . "$src" >/dev/null 2>&1; then abort "config to read the original from is not valid JSON: $src"; fi
  # NB: use an explicit null/has() check, NOT `.auto_review // "absent"` — the `//`
  # operator is FALSY-triggered, so a genuine `false` would collapse to "absent",
  # making a recorded false original indistinguishable from no config (the same
  # falsy-coercion hazard documented in gate_eval §10). Emit true|false|absent
  # faithfully so ## Run Config records the real original.
  local v; v="$("$JQ" -r 'if has("auto_review") and (.auto_review != null) then .auto_review else "absent" end' "$src")"
  echo "$v"
}

