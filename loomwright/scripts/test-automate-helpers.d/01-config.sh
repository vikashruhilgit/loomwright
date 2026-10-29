# =============================================================================
# Run directly (`bash <this file>`, as run-pin-mutations.sh runs a pin), this fragment re-executes the
# suite for this one part, so its assertions run against the helpers beside it; sourced by the
# runner, BASH_SOURCE[0] is this file and $0 the runner, and the guard never fires. Without it a bare
# run finds no `ok`/`no`/`$H`, asserts nothing and exits 0 — so a neutralised guard in config.sh stayed green.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test-automate-helpers.sh" 01-config; fi
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


# =============================================================================
echo "== A8. config-suppress / config-restore refuse a target whose real location is outside the repo (path_outside_repo) =="
# The repo root is the parent of the config's directory (<root>/.supervisor/config.json). Refusal is an ABORT:
# exit 2 (automate-next-step.sh maps it to config_malformed before the /autonomous spawn), stderr names the reason,
# and nothing is read-modified, backed up, deleted or left as a temp file — the outside folder is byte-identical.
# cw_snap <dir> — listing + cksum of every file under <dir> (what "byte-identical, no backup, no temp" compares).
cw_snap() { { find "$1" -mindepth 1 | sort; find "$1" -type f -exec cksum {} + | sort; } 2>/dev/null; }
# cw_run <cmd…> — CW_RC / CW_ERR (stderr only; stdout dropped)
cw_run() { CW_ERR="$( "$@" 2>&1 >/dev/null )"; CW_RC=$?; }

# A8a. (a) symlinked parent: .supervisor -> <outside> (absolute). The backup path sits INSIDE the symlinked dir —
#      where automate-next-step.sh puts it — so a leak would show up outside.
CW="$(mktemp -d)"; CWR="$CW/repo"; CWO="$CW/outside"; mkdir -p "$CWR" "$CWO"; ln -s "$CWO" "$CWR/.supervisor"
printf '{"keep":1}\n' > "$CWO/config.json"
CWB="$CWR/.supervisor/run.config-backup.json"
CW_S0="$(cw_snap "$CWO")"
cw_run bash "$H" config-suppress "$CWR/.supervisor/config.json" "$CWB"
if [ "$CW_RC" -eq 2 ] && grep -q 'path_outside_repo' <<<"$CW_ERR" && [ "$CW_S0" = "$(cw_snap "$CWO")" ] && [ "$(cat "$CWO/config.json")" = '{"keep":1}' ] && [ ! -e "$CWB" ]; then
  ok "A8a suppress: .supervisor -> outside ⇒ exit 2 naming path_outside_repo; outside byte-identical, no backup, no temp, no toggle"
else
  no "A8a suppress not refused (rc=$CW_RC err='${CW_ERR:0:160}' outside: $([ "$CW_S0" = "$(cw_snap "$CWO")" ] && echo unchanged || echo CHANGED))"
fi
# restore: a backup that holds the original bytes, kept inside the repo; the outside config must stay and the backup must survive.
printf '{"restored":1}\n' > "$CWR/run.config-backup.json"
CW_S0="$(cw_snap "$CWO")"
cw_run bash "$H" config-restore "$CWR/.supervisor/config.json" "$CWR/run.config-backup.json"
if [ "$CW_RC" -eq 2 ] && grep -q 'path_outside_repo' <<<"$CW_ERR" && [ "$CW_S0" = "$(cw_snap "$CWO")" ] && [ "$(cat "$CWO/config.json")" = '{"keep":1}' ] && [ -f "$CWR/run.config-backup.json" ]; then
  ok "A8a restore: .supervisor -> outside ⇒ exit 2 naming path_outside_repo; outside config neither written nor replaced, backup kept"
else
  no "A8a restore not refused (rc=$CW_RC err='${CW_ERR:0:160}' outside: $([ "$CW_S0" = "$(cw_snap "$CWO")" ] && echo unchanged || echo CHANGED))"
fi
# restore of an originally-ABSENT config would DELETE the outside file: it must be refused the same way.
printf '__ABSENT__\n' > "$CWR/run.config-backup.json"
cw_run bash "$H" config-restore "$CWR/.supervisor/config.json" "$CWR/run.config-backup.json"
if [ "$CW_RC" -eq 2 ] && grep -q 'path_outside_repo' <<<"$CW_ERR" && [ "$(cat "$CWO/config.json")" = '{"keep":1}' ] && [ -f "$CWR/run.config-backup.json" ]; then
  ok "A8a restore (__ABSENT__ marker): refused, the outside config is not deleted"
else
  no "A8a restore-absent not refused (rc=$CW_RC err='${CW_ERR:0:160}' outside-config-exists=$([ -f "$CWO/config.json" ] && echo y || echo n))"
fi
# a symlinked parent that DANGLES (target missing) is refused too — it must not fall through to "the repo exists, so inside".
CWD="$CW/dangle"; mkdir -p "$CWD"; ln -s "$CW/no-such-dir" "$CWD/.supervisor"
cw_run bash "$H" config-suppress "$CWD/.supervisor/config.json" "$CWD/run.config-backup.json"
if [ "$CW_RC" -eq 2 ] && grep -q 'path_outside_repo' <<<"$CW_ERR" && [ ! -e "$CW/no-such-dir" ] && [ ! -e "$CWD/run.config-backup.json" ]; then
  ok "A8a suppress: dangling symlinked parent ⇒ exit 2 naming path_outside_repo, nothing created"
else
  no "A8a dangling parent not refused (rc=$CW_RC err='${CW_ERR:0:160}' created=$([ -e "$CW/no-such-dir" ] && echo y || echo n))"
fi

# A8a-mut. MUTATION CONTROL (gated): with the suppress / restore containment call neutralised the same fixture is written
#          through the link — so A8a is not vacuous. The mutant sits beside $H so the library and siblings resolve.
CW_MUT="$(dirname "$H")/cw-mutant.sh"
for CW_W in suppress restore; do
  sed "s/cpl_check_write config-$CW_W /true config-$CW_W /" "$H" > "$CW_MUT"
  if [ "$(grep -cF "cpl_check_write config-$CW_W " "$H")" = 1 ] && [ -s "$CW_MUT" ] && ! cmp -s "$H" "$CW_MUT" && bash -n "$CW_MUT" 2>/dev/null; then
    CWM="$(mktemp -d)"; mkdir -p "$CWM/repo" "$CWM/outside"; ln -s "$CWM/outside" "$CWM/repo/.supervisor"
    printf '{"keep":1}\n' > "$CWM/outside/config.json"; printf '{"restored":1}\n' > "$CWM/repo/run.config-backup.json"
    CW_M0="$(cw_snap "$CWM/outside")"
    if [ "$CW_W" = suppress ]; then cw_run bash "$CW_MUT" config-suppress "$CWM/repo/.supervisor/config.json" "$CWM/repo/run.config-backup.json"
    else cw_run bash "$CW_MUT" config-restore "$CWM/repo/.supervisor/config.json" "$CWM/repo/run.config-backup.json"; fi
    if [ "$CW_RC" -eq 0 ] && [ "$CW_M0" != "$(cw_snap "$CWM/outside")" ]; then ok "A8a-mut: config-$CW_W containment neutralised ⇒ the outside folder IS modified (A8a goes red)"
    else no "A8a-mut: config-$CW_W mutant did not discriminate (rc=$CW_RC)"; fi
    rm -rf "$CWM"
  else no "A8a-mut: config-$CW_W mutant not gated (anchor not unique, empty, identical, or bash -n failed)"; fi
done
rm -f "$CW_MUT"; rm -rf "$CW"

# A8b. (b) .supervisor -> ./real-supervisor INSIDE the repo: no false refusal, absolute and relative paths.
CW="$(mktemp -d)"; CWR="$CW/repo"; mkdir -p "$CWR/real-supervisor"; ln -s ./real-supervisor "$CWR/.supervisor"
printf '{"auto_review": true, "notify": "x"}\n' > "$CWR/real-supervisor/config.json"; CW_ORIG="$(cat "$CWR/real-supervisor/config.json")"
cw_run bash "$H" config-suppress "$CWR/.supervisor/config.json" "$CWR/.supervisor/run.config-backup.json"
CW_ABS_RC="$CW_RC"
cw_run bash "$H" config-restore "$CWR/.supervisor/config.json" "$CWR/.supervisor/run.config-backup.json"
if [ "$CW_ABS_RC" -eq 0 ] && [ "$CW_RC" -eq 0 ] && [ "$(cat "$CWR/real-supervisor/config.json")" = "$CW_ORIG" ] && [ ! -e "$CWR/real-supervisor/run.config-backup.json" ]; then
  ok "A8b inside-pointing symlinked parent (absolute paths): suppress + restore succeed, original restored"
else
  no "A8b inside symlink falsely refused (suppress rc=$CW_ABS_RC restore rc=$CW_RC err='${CW_ERR:0:120}')"
fi
( cd "$CWR" && bash "$H" config-suppress .supervisor/config.json .supervisor/run.config-backup.json ) >/dev/null 2>&1; CW_RC=$?
CW_SUP="$(jq -r '.auto_review' "$CWR/real-supervisor/config.json" 2>/dev/null)"
( cd "$CWR" && bash "$H" config-restore .supervisor/config.json .supervisor/run.config-backup.json ) >/dev/null 2>&1; CW_RC2=$?
if [ "$CW_RC" -eq 0 ] && [ "$CW_SUP" = false ] && [ "$CW_RC2" -eq 0 ] && [ "$(cat "$CWR/real-supervisor/config.json")" = "$CW_ORIG" ]; then
  ok "A8b relative config + backup paths naming a location inside the repo: suppress + restore succeed"
else
  no "A8b relative paths falsely refused (suppress rc=$CW_RC auto_review=$CW_SUP restore rc=$CW_RC2)"
fi
rm -rf "$CW"

# A8c. (c) a repo reached THROUGH a symlink above its root (the macOS /tmp -> /private/tmp shape): no false refusal.
CW="$(mktemp -d)"; mkdir -p "$CW/real-parent/repo/.supervisor"; ln -s "$CW/real-parent" "$CW/link"
printf '{"auto_review": true, "notify": "x"}\n' > "$CW/real-parent/repo/.supervisor/config.json"; CW_ORIG="$(cat "$CW/real-parent/repo/.supervisor/config.json")"
cw_run bash "$H" config-suppress "$CW/link/repo/.supervisor/config.json" "$CW/link/repo/.supervisor/run.config-backup.json"
CW_ABS_RC="$CW_RC"
CW_SUP="$(jq -r '.auto_review' "$CW/real-parent/repo/.supervisor/config.json" 2>/dev/null)"
cw_run bash "$H" config-restore "$CW/link/repo/.supervisor/config.json" "$CW/link/repo/.supervisor/run.config-backup.json"
if [ "$CW_ABS_RC" -eq 0 ] && [ "$CW_SUP" = false ] && [ "$CW_RC" -eq 0 ] && [ "$(cat "$CW/real-parent/repo/.supervisor/config.json")" = "$CW_ORIG" ]; then
  ok "A8c repo under a symlinked ancestor: suppress + restore succeed (no false refusal)"
else
  no "A8c symlinked-ancestor repo falsely refused (suppress rc=$CW_ABS_RC auto_review=$CW_SUP restore rc=$CW_RC err='${CW_ERR:0:120}')"
fi
# the same through an ORIGINALLY-ABSENT config (suppress writes a fresh file, restore deletes it)
rm -f "$CW/real-parent/repo/.supervisor/config.json"
cw_run bash "$H" config-suppress "$CW/link/repo/.supervisor/config.json" "$CW/link/repo/.supervisor/run.config-backup.json"
CW_ABS_RC="$CW_RC"; CW_HAD=n; [ -f "$CW/real-parent/repo/.supervisor/config.json" ] && CW_HAD=y
cw_run bash "$H" config-restore "$CW/link/repo/.supervisor/config.json" "$CW/link/repo/.supervisor/run.config-backup.json"
if [ "$CW_ABS_RC" -eq 0 ] && [ "$CW_HAD" = y ] && [ "$CW_RC" -eq 0 ] && [ ! -e "$CW/real-parent/repo/.supervisor/config.json" ]; then
  ok "A8c absent config under a symlinked ancestor: suppress writes it, restore deletes it"
else
  no "A8c absent config under a symlinked ancestor wrong (suppress rc=$CW_ABS_RC wrote=$CW_HAD restore rc=$CW_RC)"
fi
rm -rf "$CW"

# A8d. (d) leaf symlink — even to an INSIDE target — is refused with reason `symlink` (a deliberate tightening: both
#      writers used to `mv` over the link, replacing it). The link and its target stay exactly as they were.
CW="$(mktemp -d)"; CWR="$CW/repo"; mkdir -p "$CWR/.supervisor"
printf '{"auto_review": true}\n' > "$CWR/.supervisor/real.json"; ln -s real.json "$CWR/.supervisor/config.json"
printf '{"restored":1}\n' > "$CWR/run.config-backup.json"
CW_S0="$(cw_snap "$CWR/.supervisor")"
cw_run bash "$H" config-suppress "$CWR/.supervisor/config.json" "$CWR/.supervisor/run.config-backup.json"
if [ "$CW_RC" -eq 2 ] && grep -q 'symlink' <<<"$CW_ERR" && ! grep -q 'path_outside_repo' <<<"$CW_ERR" && [ -L "$CWR/.supervisor/config.json" ] && [ "$CW_S0" = "$(cw_snap "$CWR/.supervisor")" ]; then
  ok "A8d suppress: symlinked config.json (inside target) ⇒ exit 2 naming symlink; link and target unchanged, no backup"
else
  no "A8d suppress leaf symlink wrong (rc=$CW_RC err='${CW_ERR:0:160}' dir: $([ "$CW_S0" = "$(cw_snap "$CWR/.supervisor")" ] && echo unchanged || echo CHANGED))"
fi
cw_run bash "$H" config-restore "$CWR/.supervisor/config.json" "$CWR/run.config-backup.json"
if [ "$CW_RC" -eq 2 ] && grep -q 'symlink' <<<"$CW_ERR" && [ -L "$CWR/.supervisor/config.json" ] && [ "$CW_S0" = "$(cw_snap "$CWR/.supervisor")" ] && [ -f "$CWR/run.config-backup.json" ]; then
  ok "A8d restore: symlinked config.json (inside target) ⇒ exit 2 naming symlink; link and target unchanged, backup kept"
else
  no "A8d restore leaf symlink wrong (rc=$CW_RC err='${CW_ERR:0:160}')"
fi
rm -rf "$CW"


# =============================================================================
echo "== K. right-size threshold readers (parallel-automate/18b: config.sh right_size_small / right_size_large_files / right_size_max_parts) =="
# k_read <helper> <reader> <root> — the reader's output, called in a shell that sourced the bundle (no
# positional args, so the bundle's own main only prints --help, which is discarded).
k_read() { K_R="$2" K_ROOT="$3" bash -c '. "$0" >/dev/null 2>&1; "$K_R" "$K_ROOT"' "$1" 2>/dev/null; }
k_all() { printf '%s %s %s' "$(k_read "$1" right_size_small "$2")" "$(k_read "$1" right_size_large_files "$2")" "$(k_read "$1" right_size_max_parts "$2")"; }
KD="$(mktemp -d)"; mkdir -p "$KD/.supervisor"
# K1 absent file ⇒ the three defaults
if [ "$(k_all "$H" "$KD")" = "3 30 7" ]; then ok "K1 no config.json ⇒ defaults 3 / 30 / 7"; else no "K1 defaults wrong: '$(k_all "$H" "$KD")'"; fi
# K2 valid values are read; 0 is a valid non-negative integer
printf '{"right_size_small": 5, "right_size_large_files": 40, "right_size_max_parts": 0}\n' > "$KD/.supervisor/config.json"
if [ "$(k_all "$H" "$KD")" = "5 40 0" ]; then ok "K2 valid keys read (5 / 40 / 0)"; else no "K2 valid keys wrong: '$(k_all "$H" "$KD")'"; fi
# K3 malformed file / non-object / absent key / null ⇒ defaults, exit 0
K3_BAD=""
for v in '{ not json' '[5]' '"5"' '{"other": 1}' '{"right_size_small": null, "right_size_large_files": null, "right_size_max_parts": null}'; do
  printf '%s\n' "$v" > "$KD/.supervisor/config.json"
  [ "$(k_all "$H" "$KD")" = "3 30 7" ] || K3_BAD="$K3_BAD [$v]"
done
if [ -z "$K3_BAD" ]; then ok "K3 malformed / non-object / absent key / null ⇒ defaults, never an abort"; else no "K3 not defaulted:$K3_BAD"; fi
# K4 non-integer, negative, string, boolean, oversized ⇒ that key's default
K4_BAD=""
for v in '4.5' '-1' '"5"' 'true' '1e30' '12345678901'; do
  printf '{"right_size_small": %s, "right_size_large_files": %s, "right_size_max_parts": %s}\n' "$v" "$v" "$v" > "$KD/.supervisor/config.json"
  [ "$(k_all "$H" "$KD")" = "3 30 7" ] || K4_BAD="$K4_BAD [$v ⇒ $(k_all "$H" "$KD")]"
done
if [ -z "$K4_BAD" ]; then ok "K4 non-integer / negative / string / boolean / oversized values ⇒ the default"; else no "K4 not defaulted:$K4_BAD"; fi
# K5 a falsy-but-valid 0 is not collapsed to the default (the has()/null idiom, never `// default`)
printf '{"right_size_small": 0}\n' > "$KD/.supervisor/config.json"
if [ "$(k_read "$H" right_size_small "$KD")" = 0 ]; then ok "K5 right_size_small 0 reads 0 (falsy value kept)"; else no "K5 0 collapsed: '$(k_read "$H" right_size_small "$KD")'"; fi
# K6 mutation control: the right_size_small reader flipped to always return its default ⇒ K2 turns red
K_MUT="$(dirname "$H")/k-mutant.sh"
awk '!d && index($0, "right_size_small()       { _cfg_nonneg_int") { d = 1; print "right_size_small()       { echo 3; }"; next } { print }' "$H" > "$K_MUT"
printf '{"right_size_small": 5}\n' > "$KD/.supervisor/config.json"
if [ "$(grep -cF 'right_size_small()       { _cfg_nonneg_int' "$H")" = 1 ] && [ -s "$K_MUT" ] && ! cmp -s "$H" "$K_MUT" && bash -n "$K_MUT" 2>/dev/null; then
  if [ "$(k_read "$K_MUT" right_size_small "$KD")" != 5 ] && [ "$(k_read "$H" right_size_small "$KD")" = 5 ]; then ok "K6 mutant (reader always returns the default) turns K2's read red"
  else no "K6 mutant did not discriminate"; fi
else no "K6 mutant not gated (anchor not unique, empty, identical, or bash -n failed)"; fi
rm -f "$K_MUT"; rm -rf "$KD"
