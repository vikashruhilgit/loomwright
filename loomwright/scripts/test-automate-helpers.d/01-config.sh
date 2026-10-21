# =============================================================================
echo "== A. config suppress / restore =="

# A1. normal restore: backup byte-for-byte, suppress sets auto_review=false, restore brings the ORIGINAL back.
WD="$(mktemp -d)"; CFG="$WD/config.json"; BAK="$WD/run.config-backup.json"
printf '{"auto_review": true, "notify": "x"}\n' > "$CFG"
ORIG_BYTES="$(cat "$CFG")"
bash "$H" config-suppress "$CFG" "$BAK"
if [ "$(jq -r '.auto_review' "$CFG")" = "false" ] && [ "$(jq -r '.notify' "$CFG")" = "x" ] && [ -f "$BAK" ]; then
  ok "suppress: auto_review->false, other keys preserved, backup written"
else
  no "suppress wrong (cfg='$(cat "$CFG")' bak-exists=$([ -f "$BAK" ] && echo y || echo n))"
fi
bash "$H" config-restore "$CFG" "$BAK"
if [ "$(cat "$CFG")" = "$ORIG_BYTES" ] && [ ! -f "$BAK" ]; then
  ok "restore: original config restored byte-for-byte, backup deleted"
else
  no "restore wrong (cfg='$(cat "$CFG")' bak-exists=$([ -f "$BAK" ] && echo y || echo n))"
fi
rm -rf "$WD"

# A2. absent-file restore DELETES config (never leaves a partial config.json).
WD="$(mktemp -d)"; CFG="$WD/config.json"; BAK="$WD/run.config-backup.json"
# no pre-existing config
bash "$H" config-suppress "$CFG" "$BAK"
if [ -f "$CFG" ] && [ "$(jq -r '.auto_review' "$CFG")" = "false" ]; then
  ok "absent: suppress writes a minimal auto_review:false config"
else
  no "absent-suppress wrong (cfg-exists=$([ -f "$CFG" ] && echo y || echo n))"
fi
bash "$H" config-restore "$CFG" "$BAK"
if [ ! -f "$CFG" ] && [ ! -f "$BAK" ]; then
  ok "absent: restore DELETES config (no partial config shadowing notify-config.json)"
else
  no "absent-restore should delete config (cfg-exists=$([ -f "$CFG" ] && echo y || echo n))"
fi
rm -rf "$WD"

# A3. malformed pre-existing config ABORTS (exit 2) — never clobber a hand-edited config.
WD="$(mktemp -d)"; CFG="$WD/config.json"; BAK="$WD/run.config-backup.json"
printf '{ this is not json \n' > "$CFG"
MAL_BYTES="$(cat "$CFG")"
run_h bash "$H" config-suppress "$CFG" "$BAK"
if [ "$RUN_RC" -eq 2 ] && [ "$(cat "$CFG")" = "$MAL_BYTES" ] && [ ! -f "$BAK" ]; then
  ok "malformed: suppress aborts (exit 2), config untouched, no backup written"
else
  no "malformed-abort wrong (rc=$RUN_RC cfg-unchanged=$([ "$(cat "$CFG")" = "$MAL_BYTES" ] && echo y || echo n))"
fi
rm -rf "$WD"

# A3b. valid JSON that is NOT an object is malformed too: abort before the backup, nothing left behind
#      (it used to pass the parse check, write the backup, then die in jq with exit 5 and a stray temp file).
WD="$(mktemp -d)"; CFG="$WD/config.json"; BAK="$WD/run.config-backup.json"
printf '[1,2]\n' > "$CFG"
run_h bash "$H" config-suppress "$CFG" "$BAK"
A3B_LEFT="$(cd "$WD" && ls | tr '\n' ' ')"
if [ "$RUN_RC" -eq 2 ] && [ "$(cat "$CFG")" = "[1,2]" ] && [ "$A3B_LEFT" = "config.json " ]; then
  ok "non-object config: suppress aborts (exit 2) before the backup, no stray file"
else
  no "non-object config wrong (rc=$RUN_RC files: $A3B_LEFT)"
fi
rm -rf "$WD"

# A4. crash-stranded backup restored at reconcile time (the backup persisted across a crash).
WD="$(mktemp -d)"; CFG="$WD/config.json"; BAK="$WD/run.config-backup.json"
printf '{"auto_review": true}\n' > "$CFG"
ORIG_BYTES="$(cat "$CFG")"
bash "$H" config-suppress "$CFG" "$BAK"     # simulate: tick set suppress, then "crashed" (no restore)
# config now shows auto_review:false, backup stranded on disk. RECONCILE restores it:
bash "$H" config-restore "$CFG" "$BAK"
if [ "$(cat "$CFG")" = "$ORIG_BYTES" ] && [ ! -f "$BAK" ]; then
  ok "crash-stranded backup restored on reconcile (original back, backup cleaned)"
else
  no "crash-restore wrong (cfg='$(cat "$CFG")')"
fi
rm -rf "$WD"

# A5. config-orig reports the recorded original .auto_review across present-true,
#     present-false, and absent-config (the value stamped into ## Run Config).
WD="$(mktemp -d)"; CFG="$WD/config.json"
printf '{"auto_review": true, "notify": "x"}\n' > "$CFG"
run_h bash "$H" config-orig "$CFG"
if [ "$RUN_OUT" = "true" ] && [ "$RUN_RC" -eq 0 ]; then
  ok "config-orig: present auto_review:true ⇒ 'true'"
else
  no "config-orig present-true wrong (out='$RUN_OUT' rc=$RUN_RC)"
fi
printf '{"auto_review": false, "notify": "x"}\n' > "$CFG"
run_h bash "$H" config-orig "$CFG"
if [ "$RUN_OUT" = "false" ] && [ "$RUN_RC" -eq 0 ]; then
  ok "config-orig: present auto_review:false ⇒ 'false'"
else
  no "config-orig present-false wrong (out='$RUN_OUT' rc=$RUN_RC)"
fi
rm -f "$CFG"   # absent config
run_h bash "$H" config-orig "$CFG"
if [ "$RUN_OUT" = "absent" ] && [ "$RUN_RC" -eq 0 ]; then
  ok "config-orig: absent config ⇒ 'absent'"
else
  no "config-orig absent wrong (out='$RUN_OUT' rc=$RUN_RC)"
fi
# A6. config-orig on a MALFORMED config ABORTS (exit 2) — never silently report a value.
printf '{ not json \n' > "$CFG"
run_h bash "$H" config-orig "$CFG"
if [ "$RUN_RC" -eq 2 ]; then
  ok "config-orig: malformed config ⇒ abort (exit 2)"
else
  no "config-orig malformed should abort (rc=$RUN_RC out='$RUN_OUT')"
fi
rm -rf "$WD"

# A7. CALL-ORDER HAZARD (§7) — the defect this assertion exists to catch.
#     §7's sequence is backup -> suppress -> record `auto_review_original`, so a
#     caller following the prose queries AFTER config-suppress has run, and by then
#     the LIVE config says auto_review:false for EVERY original. Only the byte-for-byte
#     backup still holds the truth. Observed 2026-09-04 on a real /automate run: a
#     config with NO auto_review key was recorded as `false` when the true original
#     was `absent`. Contract: `config-orig <cfg> [<bak>]` reports the TRUE original
#     regardless of call order, and keeps true/false/absent DISTINGUISHABLE (the same
#     distinction config_orig's own body is careful to preserve against jq's `//`).
echo "== A7. config-orig is call-order-independent (post-suppress, via the backup) =="

# A7a. THE OBSERVED DEFECT: no `auto_review` key at all -> must stay 'absent' after suppress.
WD="$(mktemp -d)"; CFG="$WD/config.json"; BAK="$WD/run.config-backup.json"
printf '{"notify": "x"}\n' > "$CFG"
run_h bash "$H" config-orig "$CFG"          # pre-suppress, 1-arg form: already correct
PRE_OUT="$RUN_OUT"
bash "$H" config-suppress "$CFG" "$BAK"
run_h bash "$H" config-orig "$CFG" "$BAK"   # post-suppress, contract form
if [ "$PRE_OUT" = "absent" ] && [ "$RUN_OUT" = "absent" ] && [ "$RUN_RC" -eq 0 ]; then
  ok "config-orig: no auto_review key ⇒ 'absent' BOTH before and after suppress"
else
  no "config-orig call-order: no-key original should be 'absent' (pre='$PRE_OUT' post='$RUN_OUT' rc=$RUN_RC)"
fi
# Live config really is suppressed — proves the assertion above is not vacuous.
if [ "$(jq -r '.auto_review' "$CFG")" = "false" ]; then
  ok "config-orig: (control) live config IS auto_review:false at query time"
else
  no "control failed: live config not suppressed (cfg='$(cat "$CFG")')"
fi
rm -rf "$WD"

# A7b. a GENUINE `false` original must NOT collapse to 'absent' via the backup path
#      either (the falsy-coercion hazard config_orig guards against on the live path).
WD="$(mktemp -d)"; CFG="$WD/config.json"; BAK="$WD/run.config-backup.json"
printf '{"auto_review": false, "notify": "x"}\n' > "$CFG"
bash "$H" config-suppress "$CFG" "$BAK"
run_h bash "$H" config-orig "$CFG" "$BAK"
if [ "$RUN_OUT" = "false" ] && [ "$RUN_RC" -eq 0 ]; then
  ok "config-orig: genuine false original ⇒ 'false' after suppress (not 'absent')"
else
  no "config-orig call-order: false original wrong (out='$RUN_OUT' rc=$RUN_RC)"
fi
rm -rf "$WD"

# A7c. a `true` original must survive suppress (the case the live path silently loses).
WD="$(mktemp -d)"; CFG="$WD/config.json"; BAK="$WD/run.config-backup.json"
printf '{"auto_review": true, "notify": "x"}\n' > "$CFG"
bash "$H" config-suppress "$CFG" "$BAK"
run_h bash "$H" config-orig "$CFG" "$BAK"
if [ "$RUN_OUT" = "true" ] && [ "$RUN_RC" -eq 0 ]; then
  ok "config-orig: true original ⇒ 'true' after suppress"
else
  no "config-orig call-order: true original wrong (out='$RUN_OUT' rc=$RUN_RC)"
fi
rm -rf "$WD"

# A7d. originally-ABSENT config: suppress writes the __ABSENT__ marker backup; the
#      recorded original must be 'absent', not the 'false' the synthesized config shows.
WD="$(mktemp -d)"; CFG="$WD/config.json"; BAK="$WD/run.config-backup.json"
bash "$H" config-suppress "$CFG" "$BAK"     # no pre-existing config
run_h bash "$H" config-orig "$CFG" "$BAK"
if [ "$RUN_OUT" = "absent" ] && [ "$RUN_RC" -eq 0 ]; then
  ok "config-orig: __ABSENT__ marker backup ⇒ 'absent' after suppress"
else
  no "config-orig call-order: absent-original wrong (out='$RUN_OUT' rc=$RUN_RC)"
fi
rm -rf "$WD"

# A7e. a MALFORMED backup ABORTS (exit 2) — same never-silently-report-a-value rule
#      as A6, so a corrupted sidecar can't fabricate an auto_review_original.
WD="$(mktemp -d)"; CFG="$WD/config.json"; BAK="$WD/run.config-backup.json"
printf '{"auto_review": true}\n' > "$CFG"
bash "$H" config-suppress "$CFG" "$BAK"
printf '{ not json \n' > "$BAK"
run_h bash "$H" config-orig "$CFG" "$BAK"
if [ "$RUN_RC" -eq 2 ]; then
  ok "config-orig: malformed backup ⇒ abort (exit 2)"
else
  no "config-orig malformed backup should abort (rc=$RUN_RC out='$RUN_OUT')"
fi
rm -rf "$WD"

# A7f. BRANCH COVERAGE for "backup path GIVEN but NOT FOUND" — the fallback branch.
#      Missing is NOT treated like malformed (which aborts, A7e) because the two are
#      not the same kind of event: a malformed backup can never be legitimate, whereas
#      a MISSING one is the normal state of a correct PRE-suppress 2-arg call. Aborting
#      on missing would re-introduce call-order dependence in the opposite direction —
#      exactly what this fix exists to remove. So the fallback is INTENTIONAL, and both
#      of its arms are pinned here so that changing it is a visible test change.

# A7f-i. LOAD-BEARING arm: 2-arg call BEFORE suppress (backup not created yet) must
#        fall back to the live config, which at that moment IS the original.
WD="$(mktemp -d)"; CFG="$WD/config.json"; BAK="$WD/run.config-backup.json"
printf '{"auto_review": true, "notify": "x"}\n' > "$CFG"
run_h bash "$H" config-orig "$CFG" "$BAK"   # $BAK deliberately does not exist yet
if [ "$RUN_OUT" = "true" ] && [ "$RUN_RC" -eq 0 ] && [ ! -f "$BAK" ]; then
  ok "config-orig: 2-arg call pre-suppress (no backup yet) falls back to live ⇒ 'true'"
else
  no "config-orig pre-suppress 2-arg fallback wrong (out='$RUN_OUT' rc=$RUN_RC)"
fi
rm -rf "$WD"

# A7f-ii. CHARACTERIZATION arm (pins a KNOWN LIMIT, not a desired outcome): if the
#         backup goes missing AFTER suppress — stale/reused run_id, partial cleanup, a
#         race with a concurrent restore — the fallback reads the SUPPRESSED live config
#         and reports 'false' for an original that was 'absent'. The helper cannot tell
#         this apart from A7f-i: both are "2 args, no backup on disk", and only the
#         CALLER knows whether suppress has run. Documented in SKILL.md §7 and in the
#         function's own comment. If this is ever changed to abort, THIS assertion is
#         the one that must be edited — deliberately and visibly.
WD="$(mktemp -d)"; CFG="$WD/config.json"; BAK="$WD/run.config-backup.json"
printf '{"notify": "x"}\n' > "$CFG"        # no auto_review key ⇒ true original is 'absent'
bash "$H" config-suppress "$CFG" "$BAK"
rm -f "$BAK"                                # backup lost after suppress
run_h bash "$H" config-orig "$CFG" "$BAK"
if [ "$RUN_OUT" = "false" ] && [ "$RUN_RC" -eq 0 ]; then
  ok "config-orig: (known limit, pinned) backup lost post-suppress ⇒ falls back to live 'false'"
else
  no "config-orig lost-backup fallback changed behavior (out='$RUN_OUT' rc=$RUN_RC) — intentional? update SKILL.md §7 + this arm"
fi
rm -rf "$WD"

