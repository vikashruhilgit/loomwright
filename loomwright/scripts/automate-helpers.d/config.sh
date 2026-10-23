# --help usage (the `#:  ` lines): this family's segment of automate-helpers.sh --help, assembled
# by the dispatcher's _ah_usage in _AH_HELP_SEGMENTS order; fixture: fixtures/automate-helpers-help/config.golden.
#:  config-suppress  <config_path> <backup_path>      # §7 backup byte-for-byte, set auto_review=false; malformed ⇒ abort
#:  config-restore   <config_path> <backup_path>      # §7 overwrite-from-backup OR delete-if-absent; deletes backup
#:  config-orig      <config_path> [<backup_path>]     # §7 prints true|false|absent (the ORIGINAL auto_review); pass the backup once suppress has run

# --------------------------------------------------------------------------- #
# §7 — config suppress / restore (byte-for-byte; absent-delete; malformed-abort)
# --------------------------------------------------------------------------- #

# config-suppress <config_path> <backup_path>
# Backs up an existing config byte-for-byte to <backup_path>, then writes a config
# with .auto_review=false. If the config is ABSENT, no backup is made (absence is
# recorded by config-restore's marker semantics) and a minimal {"auto_review":false}
# is written. A MALFORMED pre-existing config ⇒ ABORT (exit 2) — never clobber a
# hand-edited config (SKILL §7 "malformed-abort"; Anti-Pattern). Valid JSON that is
# not an object (`[]`, a string, a number) is malformed too: the merge below cannot
# index it, and checking only parseability let it through to a jq exit 5 AFTER the
# backup was written, leaving the backup and a stray temp file behind.
config_suppress() {
  local cfg="$1" bak="$2"
  if [ -f "$cfg" ]; then
    # Validate before touching anything: valid JSON AND an object.
    if ! "$JQ" -e . "$cfg" >/dev/null 2>&1; then
      abort "pre-existing config is not valid JSON: $cfg"
    fi
    if ! "$JQ" -e 'type == "object"' "$cfg" >/dev/null 2>&1; then
      abort "pre-existing config is valid JSON but not an object: $cfg"
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

# --------------------------------------------------------------------------- #
# right-size thresholds (parallel-automate/18b) — reader functions only, no subcommand.
# THE one place the three defaults live (owner decision 2026-10-22; the evidence behind them is in
# automate-helpers.d/right-size.sh's header). Every other surface names the key and points here.
# - right_size_small        an item is `small` when its companion-expanded Touches count is <= this (3)
# - right_size_large_files  an item is `large` when that count is > this (30) ...
# - right_size_max_parts    ... or when it has more `## Part ` headings than this (7)
# Read from <root>/.supervisor/config.json. An absent file, a malformed one (not JSON, not an object,
# several documents), an absent or null key, a non-number, a non-integer, a negative value, or more
# than 9 digits all read the DEFAULT — never an abort (an advisory verdict must not stop a writer).
# jq missing reads the default too. The read uses the falsy-safe has()/null idiom of config_orig,
# never `.key // default`.
# --------------------------------------------------------------------------- #
# _cfg_nonneg_int <root> <key> <default> — prints the key's value as a plain non-negative integer.
_cfg_nonneg_int() {
  local cfg="$1/.supervisor/config.json" v=""
  if [ -f "$cfg" ] && command -v "$JQ" >/dev/null 2>&1; then
    v="$("$JQ" -r --arg k "$2" 'if type == "object" and has($k) and (.[$k] != null) then (.[$k] | if type == "number" then tostring else "not-a-number" end) else "" end' "$cfg" 2>/dev/null)" || v=""
  fi
  case "$v" in ""|*[!0-9]*) v="$3" ;; esac
  [ "${#v}" -le 9 ] || v="$3"
  printf '%s\n' "$((10#$v))"
}
right_size_small()       { _cfg_nonneg_int "${1:-.}" right_size_small 3; }
right_size_large_files() { _cfg_nonneg_int "${1:-.}" right_size_large_files 30; }
right_size_max_parts()   { _cfg_nonneg_int "${1:-.}" right_size_max_parts 7; }

