# =============================================================================
echo "== F. finalize-empty / resume-glob --finalize (a closed-out run finalizes itself) =="
# SKILL §1.5 `finalize-empty` row, §3 "`done`", §4 step 1. closeout never writes
# `done`; a finished lane run stayed paused/awaiting_go and every RESUME listed it.
AUTD=".supervisor/automate"
fe_glob() { (cd "$P" && bash "${FE_H:-$SPYD/automate-helpers.sh}" resume-glob "$AUTD" --finalize 2>"$FX/fe.err"); }
fe_rf() { # <run_id> <status> <pause_reason> <REQ queue box> <current status>
  cat > "$P/$AUTD/$1.md" <<RF
# Automate Run: fixture $1
## Status: $2
## Queue
- [$4] $REQ
- [x] .supervisor/requirements/f/02-b.md  # skipped: owner said so
## Current
- item: $REQ | status: $5 | pr: $PRURL | branch: feature/x
- pause_reason: $3
## Progress
- t0 picked $REQ
RF
}

# (F0) invariant: a closeout that checks off the LAST Queue item leaves ## Status: paused.
fe_invariant() { # <fixture-n> <scripts-dir> → 0 when the run stayed paused/awaiting_go with remaining 0
  closeout_fixture "$1"
  (cd "$P" && bash "$2/automate-helpers.sh" closeout "$RF_REL" "$REQ" "$PRURL" >/dev/null)
  [ "$(bash "$H" remaining "$P/$RF_REL")" = 0 ] && grep -qxF -- "## Status: paused" "$P/$RF_REL" && grep -qxF -- "- pause_reason: awaiting_go" "$P/$RF_REL"
}
if fe_invariant 200 "$SPYD"; then ok "(F0) closeout checking off the last item leaves ## Status: paused / awaiting_go (remaining 0) — closeout never writes done"; else no "(F0) closeout state: $(grep -E '^## Status|^- pause_reason' "$P/$RF_REL" | tr '\n' '|')"; fi
MUTF="$TOP/mutd-done"; mkdir -p "$MUTF"; cp "$HERE"/*.sh "$HERE"/*.py "$MUTF/"; cp -R "$HERE/automate-helpers.d" "$MUTF/"; cp -R "$HERE/automate-trail.d" "$MUTF/"
awk '{ print } index($0, "    echo \"closeout: reconciled — ## Current $item status done, pause_reason $want\"")==1 { print "    { sed \"s/^## Status: paused/## Status: done/\" \"$rf\" > \"$rf.m\" && mv \"$rf.m\" \"$rf\"; }" }' "$TB" > "$MUTF/automate-trail.sh"
if cmp -s "$TB" "$MUTF/automate-trail.sh" || ! bash -n "$MUTF/automate-trail.sh"; then no "(F0) closeout-writes-done mutant not built"
elif fe_invariant 201 "$MUTF"; then no "(F0) mutation control REFUTED: a closeout that writes done still passed the invariant leg"
else ok "(F0) control: a closeout mutant that writes '## Status: done' turns the invariant leg red ($(grep '^## Status' "$P/$RF_REL"))"
fi

# (F1) branch mode OFF: closeout leaves the eligible state; resume-glob --finalize finalizes it.
closeout_fixture 202
run_closeout >/dev/null
[ -n "$(git -C "$P" diff --cached --name-only)" ] && ok "(F1) precondition: closeout's trail-pr left trail blobs staged in the primary index" || no "(F1) precondition: nothing staged after closeout"
plain_before="$(cd "$P" && bash "$H" resume-glob "$AUTD")"
[ "$plain_before" = "$AUTD/$RUN_ID.md" ] && ok "(F1) plain resume-glob lists the closed-out run (the incident)" || no "(F1) plain list: $plain_before"
spy_reset
lst="$(fe_glob)"; rc=$?
sed 's/^/    | /' "$FX/fe.err"
[ "$rc" -eq 0 ] && [ -z "$lst" ] && ok "(F1) resume-glob --finalize: exit 0 and the finalized run is NOT listed" || no "(F1) rc=$rc list='$lst'"
grep -qxF -- "## Status: done" "$P/$RF_REL" && grep -qxF -- "- pause_reason: null" "$P/$RF_REL" && ok "(F1) ## Status: done + pause_reason: null" || no "(F1) state: $(grep -E '^## Status|^- pause_reason' "$P/$RF_REL" | tr '\n' '|')"
grep -qxF -- "- item: $REQ | status: done | pr: $PRURL | branch: feature/x" "$P/$RF_REL" && ok "(F1) ## Current item line byte-unchanged" || no "(F1) item line changed"
grep -qE '^- [^ ]+ auto-finalized: queue empty after closeout$' "$P/$RF_REL" && ok "(F1) Progress: auto-finalized: queue empty after closeout" || no "(F1) no auto-finalized line"
grep -qE "^trail-pr $P/$RF_REL --reason done\$" "$SPYLOG" && ok "(F1) trail-pr <runfile> --reason done via the dispatcher (the Termination call)" || no "(F1) trail-pr call: $(tr '\n' '|' < "$SPYLOG" 2>/dev/null)"
grep -qE '^- [^ ]+ trail-pr: (opened|pushed|skipped)' "$P/$RF_REL" && ok "(F1) the trail line is appended to ## Progress" || no "(F1) trail line not appended"
grep -qxF "finalize-empty: finalized $AUTD/$RUN_ID.md" < <(head -n1 "$FX/fe.err") && grep -q '^trail-unstage: ' "$FX/fe.err" && ok "(F1) stderr: finalized line + trail-unstage line" || no "(F1) stderr: $(tr '\n' '|' < "$FX/fe.err")"
stg="$(git -C "$P" diff --cached --name-only)"
[ -z "$stg" ] && ok "(F1) mode off: the primary index carries NO staged path of the finalized run" || no "(F1) still staged: $(printf '%s' "$stg" | tr '\n' ' ')"
[ ! -d "$P/.supervisor/run.lock" ] && ok "(F1) run lock released" || no "(F1) run lock leaked"
c1="$(cksum < "$P/$RF_REL")"
o2="$(cd "$P" && bash "$H" finalize-empty "$RF_REL")"
[ "$o2" = "finalize-empty: skipped — not paused" ] && [ "$c1" = "$(cksum < "$P/$RF_REL")" ] && ok "(F1) a second finalize is a no-op ('$o2')" || no "(F1) second finalize: '$o2'"
# af/39a AC7: ONE dry-run sweep summary line per run end, AFTER the trail line (never inside the
# staged rewrite) — and the second (no-op) finalize above did not add another.
fe_sw="$(grep -nE '^- [^ ]+ sweep \(dry run\): sweep: summary — dry run: ' "$P/$RF_REL" | cut -d: -f1)"
fe_tr="$(grep -nE '^- [^ ]+ trail-pr: (opened|pushed|skipped)' "$P/$RF_REL" | tail -n1 | cut -d: -f1)"
[ "$(printf '%s\n' "$fe_sw" | grep -c .)" = 1 ] && [ -n "$fe_tr" ] && [ "$fe_sw" -gt "$fe_tr" ] \
  && ok "(F1) AC7 finalize-empty appends exactly ONE '<ts> sweep (dry run): sweep: summary — dry run: …' Progress line, after its trail line" \
  || no "(F1) sweep line(s) at '$(printf '%s' "$fe_sw" | tr '\n' ' ')' vs trail line $fe_tr"
grep -q '^sweep' "$FX/fe.err" && no "(F1) the sweep line leaked into finalize-empty's printed output" || ok "(F1) the sweep summary is appended to ## Progress only (finalize-empty's printed lines unchanged)"
# Control: without the mode-off trail-unstage the finalized run's trail blobs stay staged.
MUTU="$TOP/mutd-unstage"; mkdir -p "$MUTU"; cp "$HERE"/*.sh "$HERE"/*.py "$MUTU/"; cp -R "$HERE/automate-helpers.d" "$MUTU/"; cp -R "$HERE/automate-trail.d" "$MUTU/"
grep -v 'l="$(bash "$HLP" trail-unstage "$rf_abs"' "$TB" > "$MUTU/automate-trail.sh"
if cmp -s "$TB" "$MUTU/automate-trail.sh" || ! bash -n "$MUTU/automate-trail.sh"; then no "(F1) unstage mutant not built"
else
  closeout_fixture 203; run_closeout >/dev/null
  FE_H="$MUTU/automate-helpers.sh" fe_glob >/dev/null
  grep -qxF -- "## Status: done" "$P/$RF_REL" && [ -n "$(git -C "$P" diff --cached --name-only)" ] \
    && ok "(F1) control: without trail-unstage the finalized run leaves staged trail paths (the clean-index assertion is load-bearing)" || no "(F1) unstage control did not discriminate"
fi
# (F1b) the pause_reason line is authored by current-set (SKILL §3 "every write of …
# its `- pause_reason:` line is ONE current-set call"), run on the STAGED copy — the
# run file itself still changes in one runfile-write.
grep -qE "^current-set /[^ ]*/$AUTD/$RUN_ID\.md\.fe\.[A-Za-z0-9]+ --pause-reason null\$" "$SPYLOG" \
  && ok "(F1b) finalize-empty writes pause_reason via current-set --pause-reason null on the staged copy" \
  || no "(F1b) current-set call: $(grep '^current-set' "$SPYLOG" 2>/dev/null | tr '\n' '|')"
[ -z "$(cd "$P/$AUTD" && ls -A | grep -F '.fe.')" ] && ok "(F1b) no staged .fe. copy left behind" || no "(F1b) leftover: $(ls -A "$P/$AUTD" | tr '\n' ' ')"
# A refusing current-set leaves the run file byte-unchanged and still eligible
# (still listed; a later --finalize retries) — never a half-finalized done+awaiting_go.
MUTC="$TOP/mutd-cs"; mkdir -p "$MUTC"; cp "$HERE"/*.sh "$HERE"/*.py "$MUTC/"; cp -R "$HERE/automate-helpers.d" "$MUTC/"; cp -R "$HERE/automate-trail.d" "$MUTC/"
mv "$MUTC/automate-helpers.sh" "$MUTC/automate-helpers.real.sh"
cat > "$MUTC/automate-helpers.sh" <<'SHIM'
#!/usr/bin/env bash
if [ "${1:-}" = current-set ]; then echo "current-set: refused — test" >&2; exit 1; fi
exec bash "$(dirname "$0")/automate-helpers.real.sh" "$@"
SHIM
closeout_fixture 206; run_closeout >/dev/null
c0="$(cksum < "$P/$RF_REL")"
lst="$(FE_H="$MUTC/automate-helpers.sh" fe_glob)"
[ "$lst" = "$AUTD/$RUN_ID.md" ] && [ "$c0" = "$(cksum < "$P/$RF_REL")" ] && grep -q 'not finalized — finalize-empty: skipped — runfile-write refused' "$FX/fe.err" \
  && [ -z "$(cd "$P/$AUTD" && ls -A | grep -F '.fe.')" ] && [ ! -d "$P/.supervisor/run.lock" ] \
  && ok "(F1b) current-set refusal ⇒ run file byte-unchanged, still listed, no staged copy, lock released" \
  || no "(F1b) refusal leg: list='$lst' stderr=$(tr '\n' '|' < "$FX/fe.err")"
lst="$(fe_glob)"
[ -z "$lst" ] && grep -qxF -- "## Status: done" "$P/$RF_REL" && grep -qxF -- "- pause_reason: null" "$P/$RF_REL" \
  && ok "(F1b) the next --finalize retries cleanly and finalizes" || no "(F1b) retry: list='$lst'"

# (F4) automate-followups/36 A4 — the order is kept on purpose: `## Status: done` is written BEFORE
# trail-pr, because the trail PR carries that stamp. So a FAILED trail-pr is not retried by a later
# --finalize (the run is no longer paused); its line sits in ## Progress and the recovery is a hand
# `trail-pr <runfile> --reason done`. A stub trail-pr records the run file's ## Status when called.
FTD="$TOP/fetrail"; mkdir -p "$FTD"; cp "$HERE"/*.sh "$HERE"/*.py "$FTD/"; cp -R "$HERE/automate-helpers.d" "$FTD/"; cp -R "$HERE/automate-trail.d" "$FTD/"
mv "$FTD/automate-helpers.sh" "$FTD/automate-helpers.real.sh"
cat > "$FTD/automate-helpers.sh" <<'SHIM'
#!/usr/bin/env bash
if [ "${1:-}" = trail-pr ]; then
  { printf 'trail-pr saw: '; grep -m1 '^## Status:' "$2"; } >> "$FE_TRAIL_LOG"
  if [ -n "${FE_TRAIL_FAIL:-}" ]; then echo "trail-pr: skipped — gh pr create failed (stub)"; exit 0; fi
fi
exec bash "$(dirname "$0")/automate-helpers.real.sh" "$@"
SHIM
export FE_TRAIL_LOG="$TOP/fe-trail.log"
fe_trail_leg() { # <helpers dir> — closeout, then --finalize through <dir>'s shim with a failing trail-pr
  closeout_fixture "$1"; run_closeout >/dev/null
  : > "$FE_TRAIL_LOG"
  FE_LST="$(FE_TRAIL_FAIL=1 FE_H="$2/automate-helpers.sh" fe_glob)"
}
fe_trail_leg 208 "$FTD"
[ -z "$FE_LST" ] && grep -qxF -- "## Status: done" "$P/$RF_REL" && [ "$(cat "$FE_TRAIL_LOG")" = "trail-pr saw: ## Status: done" ] \
  && ok "(F4) trail-pr runs AFTER the done write: the one trail call saw '## Status: done' (the trail carries the stamp)" \
  || no "(F4) list='$FE_LST' trail log: $(tr '\n' '|' < "$FE_TRAIL_LOG")"
grep -qE '^- [^ ]+ trail-pr: skipped — gh pr create failed \(stub\)$' "$P/$RF_REL" && grep -qxF 'trail-pr: skipped — gh pr create failed (stub)' "$FX/fe.err" \
  && ok "(F4) the failed trail is visible: its line is printed and appended to ## Progress" || no "(F4) failure line missing: $(tr '\n' '|' < "$FX/fe.err")"
c1="$(cksum < "$P/$RF_REL")"
lst="$(FE_H="$FTD/automate-helpers.sh" fe_glob)"
[ -z "$lst" ] && [ "$(wc -l < "$FE_TRAIL_LOG" | tr -d ' ')" = 1 ] && [ "$c1" = "$(cksum < "$P/$RF_REL")" ] \
  && ok "(F4) a later --finalize does NOT retry the failed trail (the run is done, not listed, byte-unchanged) — the documented limit" \
  || no "(F4) retry leg: list='$lst' trail calls=$(wc -l < "$FE_TRAIL_LOG")"
o="$(cd "$P" && bash "$H" trail-pr "$RF_REL" --reason done)"
case "$o" in "trail-pr: skipped"*|"") no "(F4) hand recovery 'trail-pr --reason done' shipped nothing: '$o'" ;;
  *) ok "(F4) the documented recovery — a hand 'trail-pr <runfile> --reason done' — ships the trail ('$o')" ;; esac
# Mutation control: a trail cut BEFORE the done write records 'paused' — the order leg turns red.
MUTFT="$TOP/mutd-fetrail"; mkdir -p "$MUTFT"; cp -R "$FTD"/* "$MUTFT/"
awk 'index($0, "  local tmp; tmp=\"$(mktemp \"${rf_abs}.fe.XXXXXX\")\"")==1 { print "  bash \"$HLP\" trail-pr \"$rf_abs\" --reason done >/dev/null 2>&1  # mutant A4" } { print }' "$TB" > "$MUTFT/automate-trail.sh"
if grep -q '# mutant A4' "$MUTFT/automate-trail.sh" && bash -n "$MUTFT/automate-trail.sh"; then
  fe_trail_leg 209 "$MUTFT"
  [ "$(head -n1 "$FE_TRAIL_LOG")" = "trail-pr saw: ## Status: paused" ] \
    && ok "(F4) control: a trail-pr cut before the done write sees 'paused' — the order leg is load-bearing" \
    || no "(F4) control did not discriminate: $(tr '\n' '|' < "$FE_TRAIL_LOG")"
else
  no "(F4) mutant A4 not built"
fi

# (F2) eligibility + lock: only paused/awaiting_go/remaining-0/Current-done runs finalize.
new_fixture 204
( cd "$P" && git checkout -q -- README; rm -f stray.txt; rm -f "$AUTD"/*.md )
fe_rf automate-a-eligible paused awaiting_go x done
fe_rf automate-b-unchecked paused awaiting_go ' ' done
fe_rf automate-c-otherreason paused awaiting_merge x done
fe_rf automate-d-curnotdone paused awaiting_go x awaiting_merge
fe_rf automate-e-eligible paused awaiting_go x done
want_all="$(printf '%s\n' "$AUTD/automate-a-eligible.md" "$AUTD/automate-b-unchecked.md" "$AUTD/automate-c-otherreason.md" "$AUTD/automate-d-curnotdone.md" "$AUTD/automate-e-eligible.md")"
[ "$(cd "$P" && bash "$H" resume-glob "$AUTD")" = "$want_all" ] && ok "(F2) plain resume-glob output unchanged (all five listed, sorted)" || no "(F2) plain list: $(cd "$P" && bash "$H" resume-glob "$AUTD" | tr '\n' ' ')"
sums() { (cd "$P/$AUTD" && cksum automate-*.md); }
s0="$(sums)"
bash "$HERE/run-lock.sh" acquire --owner fe-test-holder --root "$P" >/dev/null 2>&1
lst="$(fe_glob)"
[ "$lst" = "$want_all" ] && [ "$s0" = "$(sums)" ] && ok "(F2) run lock held ⇒ nothing finalized, every run listed, all byte-unchanged" || no "(F2) lock-held list: $(printf '%s' "$lst" | tr '\n' ' ')"
[ "$(grep -c 'not finalized — finalize-empty: skipped — run lock held by fe-test-holder' "$FX/fe.err")" = 2 ] && ok "(F2) stderr names the lock holder for both eligible runs" || no "(F2) stderr: $(tr '\n' '|' < "$FX/fe.err")"
bash "$HERE/run-lock.sh" release --owner fe-test-holder --root "$P" >/dev/null 2>&1
spy_reset
lst="$(fe_glob)"
sed 's/^/    | /' "$FX/fe.err"
want_rest="$(printf '%s\n' "$AUTD/automate-b-unchecked.md" "$AUTD/automate-c-otherreason.md" "$AUTD/automate-d-curnotdone.md")"
[ "$lst" = "$want_rest" ] && ok "(F2) lock released ⇒ the two eligible runs finalized; unchecked / other pause_reason / Current-not-done listed" || no "(F2) list: $(printf '%s' "$lst" | tr '\n' ' ')"
for r in automate-a-eligible automate-e-eligible; do grep -qxF -- "## Status: done" "$P/$AUTD/$r.md" || no "(F2) $r not done"; done
s1="$(sums | grep -v -e '-eligible\.md$')"; s0r="$(printf '%s\n' "$s0" | grep -v -e '-eligible\.md$')"
[ "$s1" = "$s0r" ] && ok "(F2) ineligible runs byte-untouched" || no "(F2) an ineligible run was modified"
[ "$(spy_count '^trail-pr .* --reason done$' "$SPYLOG")" = 2 ] && [ "$(count_creates)" = 2 ] && ok "(F2) mode off: one trail-pr --reason done (one trail PR) per finalized run" || no "(F2) trail calls: $(spy_count '^trail-pr' "$SPYLOG") creates: $(count_creates)"
[ "$(grep -c '^finalize-empty: finalized ' "$FX/fe.err")" = 2 ] && ! grep -q 'not finalized' "$FX/fe.err" && ok "(F2) stderr: two finalized lines, no ineligible noise" || no "(F2) stderr: $(tr '\n' '|' < "$FX/fe.err")"

# (F3) branch mode ON: finalized; trail-pr meta-pushes (no PR), no trail-unstage.
export LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="acme/widgets,vikashruhilgit/loomwright"
new_fixture 205; bm_switch
fe_rf "$RUN_ID" paused awaiting_go x done
: > "$GH_STUB_DIR/argv.log"
lst="$(fe_glob)"
sed 's/^/    | /' "$FX/fe.err"
[ -z "$lst" ] && grep -qxF -- "## Status: done" "$P/$RF_REL" && ok "(F3) branch mode: finalized and not listed" || no "(F3) list='$lst' status=$(grep '^## Status' "$P/$RF_REL")"
grep -q "^trail-pr: meta-pushed $BMB" "$FX/fe.err" && ! grep -q '^trail-unstage' "$FX/fe.err" && ok "(F3) trail meta-pushed; no trail-unstage in branch mode" || no "(F3) stderr: $(tr '\n' '|' < "$FX/fe.err")"
[ "$(count_creates)" = 0 ] && ok "(F3) no gh pr create in branch mode" || no "(F3) a PR was created"
grep -qxF -- "## Status: done" < <(bm_show "$RF_REL0") && ok "(F3) the metadata branch holds the finalized run file" || no "(F3) branch run file not done"
unset LOOMWRIGHT_MEMORY_REPO_ALLOWLIST

# =============================================================================
echo "== CL. closeout-classify: every closeout string is classified; kept/unknown/refusal ⇒ leftover (automate-followups/32 Part A) =="
# SKILL §1.5 `closeout-classify` row, §6 step 1 "Close-out leftover gate".
cls() { bash "$H" closeout-classify "$@"; }
# (CL1) table drift guard: every closeout string template automate-trail.sh can
# print (closeout, _co_current, _sync_primary's SYNC_SKIP) matches a CLOSEOUT_TABLE
# row — a new string must be classified on purpose, never fall through as unknown.
co_templates() { # <automate-trail.sh> → one sample line per closeout string template
  awk '/^_sync_primary\(\) \{/{on=1} /^# finalize-empty \(SKILL/{on=0} on && $0 !~ /^[[:space:]]*#/' "$1" \
    | grep -oE '((echo |=)"(\$S |closeout: )[^"]*"|SYNC_SKIP="[^"]*")' \
    | sed -E 's/^(echo |=)"//; s/^SYNC_SKIP="/closeout: skipped — /; s/"$//; s/^\$S /closeout: skipped — /' \
    | sed -E 's/\$\([^)]*\)/X/g; s/\$\{[^}]*\}/X/g; s/\$[A-Za-z_][A-Za-z0-9_]*/X/g' \
    | grep -vxE 'closeout: skipped —( X)? ?' | sed '/^$/d' | env LC_ALL=C sort -u   # "$S $SYNC_SKIP": the SYNC_SKIP templates carry it
}
cl_unknown() { # <automate-trail.sh> → the templates the classifier reads as unknown
  local t
  while IFS= read -r t; do
    grep -q "	unknown	" < <(printf '%s\n' "$t" | cls --run r --item i --pr p) && printf '%s\n' "$t"
  done <<CLT
$(co_templates "$1")
CLT
  return 0
}
ntpl="$(co_templates "$TB" | wc -l | tr -d ' ')"
unk="$(cl_unknown "$TB")"
[ "$ntpl" -ge 30 ] && [ -z "$unk" ] && ok "(CL1) all $ntpl closeout string templates in automate-trail.sh match a CLOSEOUT_TABLE row" || no "(CL1) templates=$ntpl unclassified: $(printf '%s' "$unk" | tr '\n' '|')"
MUTCL="$TOP/mutd-cl"; mkdir -p "$MUTCL"
awk '{ print } index($0, "  if [ \"$st\" != \"merged\" ]; then echo \"$S pr not merged")==1 { print "  echo \"$S a brand-new refusal nobody classified\"" }' "$TB" > "$MUTCL/automate-trail.sh"
if cmp -s "$TB" "$MUTCL/automate-trail.sh"; then no "(CL1) drift mutant not built"
else
  case "$(cl_unknown "$MUTCL/automate-trail.sh")" in *"a brand-new refusal nobody classified"*) ok "(CL1) control: a new unclassified closeout string is caught by the drift guard" ;; *) no "(CL1) control: drift guard missed a new string" ;; esac
fi
# (CL2) literal lines.
cl_one() { printf '%s\n' "$1" | cls --run R1 --item q/01.md --pr "$PRURL"; }
for l in "closeout: synced — main at abc1234" "closeout: skipped — already synced (main at origin/main)" "closeout: skipped — ## Current is q/02.md (https://x/pull/9), not this item/PR" "closeout: skipped — ## Current already done" "closeout: removed — branch feature/x (tip == merged head abc)"; do
  [ "$(cl_one "$l")" = complete ] && ok "(CL2) complete: ${l#closeout: }" || no "(CL2) not complete: $l ⇒ $(cl_one "$l")"
done
want_row() { [ "$(cl_one "$1")" = "leftover	R1	q/01.md	$PRURL	$2	${1#closeout: }" ]; }
want_row "closeout: removed — worktree /w/a; kept /w/b still dirty after salvage" worktree && ok "(CL2) mixed 'removed — worktree A; kept B' ⇒ ONE worktree leftover row (kept wins over the verb)" || no "(CL2) mixed line: $(cl_one "closeout: removed — worktree /w/a; kept /w/b still dirty after salvage")"
# (CL2k) S3 wave-1 review: "kept" inside a NAME never flips a clean line — only the partial-removal form counts.
for l in "closeout: checked — - [x] reqs/kept-sessions.md" "closeout: skipped — already removed (no worktree on feat/kept-x)" \
         "closeout: removed — branch feat/kept-x (tip == merged head abc123def456)" "closeout: removed — worktree /w/kept-a"; do
  [ "$(cl_one "$l")" = complete ] && ok "(CL2k) a name containing 'kept' stays complete: ${l#closeout: }" || no "(CL2k) flipped to leftover: $l ⇒ $(cl_one "$l")"
done
want_row "closeout: skipped — pr not merged (awaiting_merge)" gate && ok "(CL2) 'skipped — pr not merged …' ⇒ leftover (gate)" || no "(CL2) pr not merged"
want_row "closeout: frobnicated — something new" unknown && ok "(CL2) an unknown closeout: line ⇒ leftover (unknown)" || no "(CL2) unknown line: $(cl_one 'closeout: frobnicated — something new')"
want_row "closeout: skipped — uncommitted changes outside the trail paths (README)" sync && ok "(CL2) sync skipped on a dirty primary ⇒ leftover (sync)" || no "(CL2) dirty sync"
want_row "closeout: skipped — no done brief" stamp && ok "(CL2) 'skipped — no done brief' ⇒ leftover (stamp)" || no "(CL2) no done brief"
# (CL2l) automate-followups/36 A1: a run lock held by a LIVE process is `run_lock_held` — neither
# complete nor a leftover; a dead or unreadable holder stays `leftover lock`.
o="$(cl_one "closeout: skipped — run lock held by automate:r-L1 (live pid 4242)")"
[ "$o" = "run_lock_held	R1	q/01.md	$PRURL	lock	skipped — run lock held by automate:r-L1 (live pid 4242)" ] \
  && ok "(CL2l) '… run lock held by <owner> (live pid <p>)' ⇒ ONE run_lock_held row (not complete, not leftover)" || no "(CL2l) live: $o"
want_row "closeout: skipped — run lock held by automate:r-L1 (holder pid 4242 not running)" lock && ok "(CL2l) a dead holder ⇒ leftover (lock)" || no "(CL2l) dead: $(cl_one "closeout: skipped — run lock held by automate:r-L1 (holder pid 4242 not running)")"
want_row "closeout: skipped — run lock held by unknown (holder pid unknown not running)" lock && ok "(CL2l) an unreadable holder ⇒ leftover (lock)" || no "(CL2l) unreadable holder"
CLR="$TOP/cl-held.md"; printf '# Automate Run: h\n## Status: running\n## Queue\n- [ ] q/01.md\n## Current\n- item: null | status: null | pr: null | branch: null\n- pause_reason: null\n## Progress\n- t0 run created\n' > "$CLR"
c0="$(cksum < "$CLR")"
printf 'brief-repair: skipped — nothing to repair\ncloseout: skipped — run lock held by automate:r-L1 (live pid 4242)\n' | cls --run R1 --item q/01.md --pr "$PRURL" --record "$CLR" >/dev/null
[ "$c0" = "$(cksum < "$CLR")" ] && ok "(CL2l) --record on a run_lock_held answer appends nothing (no false 'nothing to close out')" || no "(CL2l) --record appended: $(tail -n1 "$CLR")"
o="$(printf 'brief-repair: repaired x\ntrail-pr: skipped — gh failed\n' | cls --run R1)"
[ "$o" = "leftover	R1	-	-	none	no closeout: line in the input" ] && ok "(CL2) no closeout: line at all ⇒ one leftover row (nothing proves the close-out ran); brief-repair/trail-pr lines ignored" || no "(CL2) no closeout line: $o"
bash "$H" closeout-classify --bogus </dev/null >/dev/null 2>&1; [ $? -eq 1 ] && ok "(CL2) usage error exits 1" || no "(CL2) usage error rc"

echo "== CL. a real close-out that kept a worktree + a branch (tip != merged head); 'Clean up now' never forces =="
REALGIT="$(command -v git)"
GSHIM="$TOP/gshim"; mkdir -p "$GSHIM"
printf '#!/usr/bin/env bash\necho "git $*" >> "$GITLOG"\nexec "%s" "$@"\n' "$REALGIT" > "$GSHIM/git"; chmod +x "$GSHIM/git"
CUD="$TOP/cud"; mkdir -p "$CUD"; cp "$SPYD"/*.sh "$SPYD"/*.py "$CUD/"; cp -R "$SPYD/automate-helpers.d" "$CUD/"; cp -R "$SPYD/automate-trail.d" "$CUD/"
cat > "$CUD/automate-helpers.sh" <<'SHIM'
#!/usr/bin/env bash
if [ "${1:-}" = trail-pr ]; then echo "trail-pr: skipped — stubbed"; exit 0; fi
exec bash "$(dirname "$0")/automate-helpers.real.sh" "$@"
SHIM
mv "$CUD/worktree-salvage.sh" "$CUD/worktree-salvage.real.sh"
printf '#!/usr/bin/env bash\necho "SALVAGE $1" >> "$GITLOG"\nexec bash "$(dirname "$0")/worktree-salvage.real.sh" "$@"\n' > "$CUD/worktree-salvage.sh"
export GITLOG="$TOP/git.log"
cu_closeout() { (cd "$P" && PATH="$GSHIM:$PATH" bash "$CUD/automate-helpers.sh" closeout "$RF_REL" "$REQ" "$PRURL"); }
closeout_fixture 301
( cd "$FX/wt-pr" && echo more > more.txt && git add more.txt && git commit -qm "other work, same branch name" )
moved_tip="$(git -C "$P" rev-parse feature/x)"
: > "$GITLOG"
out="$(cu_closeout)"
rows="$(printf '%s\n' "$out" | cls --run "$RUN_ID" --item "$REQ" --pr "$PRURL")"
printf '%s\n' "$rows" | sed 's/^/    | /'
[ "$(printf '%s\n' "$rows" | cut -f5 | tr '\n' ' ')" = "worktree branch " ] && ok "(CL3) one leftover row per kept step: worktree + branch" || no "(CL3) rows: $(printf '%s' "$rows" | cut -f5 | tr '\n' ' ')"
[ "$(printf '%s\n' "$rows" | cut -f1-4 | env LC_ALL=C sort -u)" = "leftover	$RUN_ID	$REQ	$PRURL" ] && ok "(CL3) every row carries run_id / item / pr (a 'Clean up now' target)" || no "(CL3) row targets: $(printf '%s' "$rows" | cut -f1-4 | tr '\n' '|')"
# "Clean up now" = re-run closeout, re-classify ONCE.
out2="$(cu_closeout)"
rows2="$(printf '%s\n' "$out2" | cls --run "$RUN_ID" --item "$REQ" --pr "$PRURL")"
[ "$(printf '%s\n' "$rows2" | cut -f5 | tr '\n' ' ')" = "worktree branch " ] && ok "(CL4) 'Clean up now' re-run: both leftovers survive (reported, asked Keep/Stop only)" || no "(CL4) re-run rows: $rows2"
[ -d "$FX/wt-pr" ] && [ "$(git -C "$P" rev-parse feature/x)" = "$moved_tip" ] && ok "(CL4) the worktree and the branch at a foreign tip are still there" || no "(CL4) foreign-tip worktree/branch removed"
grep -F "worktree remove $FX/wt-pr" "$GITLOG" >/dev/null && no "(CL4) a foreign-tip worktree was removed" || ok "(CL4) never 'git worktree remove' on the foreign-tip worktree"
grep -E '^git (.* )?branch -D' "$GITLOG" >/dev/null && no "(CL4) git branch -D ran on a foreign tip" || ok "(CL4) never 'git branch -D' on a foreign tip"
grep -E '^git (.* )?(reset|stash)( |$)|--force|^git (.* )?push( .*)? (-f|\+)' "$GITLOG" >/dev/null && no "(CL4) a reset/stash/force: $(grep -E 'reset|stash|--force' "$GITLOG" | head -3 | tr '\n' '|')" || ok "(CL4) never a reset, a stash or a force (git argv log)"
# Matching tip: the worktree is removed, and only AFTER worktree-salvage.sh ran on it.
closeout_fixture 302
: > "$GITLOG"
cu_closeout >/dev/null
ls_="$(grep -nF "SALVAGE $FX/wt-pr" "$GITLOG" | head -n1 | cut -d: -f1)"
lr_="$(grep -nF "worktree remove $FX/wt-pr" "$GITLOG" | head -n1 | cut -d: -f1)"
[ -n "$ls_" ] && [ -n "$lr_" ] && [ "$ls_" -lt "$lr_" ] && [ ! -d "$FX/wt-pr" ] && ok "(CL4) a merged-head worktree is removed only after worktree-salvage.sh ran on it (log lines $ls_ < $lr_)" || no "(CL4) salvage/remove order: salvage=$ls_ remove=$lr_"

echo "== CL. an already closed-out item: complete, nothing asked, ≤1 'nothing to close out' line after two passes =="
closeout_fixture 303
o0="$(run_closeout)"
[ "$(printf '%s\n' "$o0" | cls --run "$RUN_ID" --item "$REQ" --pr "$PRURL" --record "$P/$RF_REL")" = complete ] && ok "(CL5) the first, real close-out classifies complete" || no "(CL5) first close-out: $(printf '%s\n' "$o0" | cls)"
grep -q 'nothing to close out' "$P/$RF_REL" && no "(CL5) a close-out that changed things recorded 'nothing to close out'" || ok "(CL5) a close-out that changed things records no 'nothing to close out' line"
for cl5_pass in 1 2; do
  o="$(run_closeout)"
  v="$(printf '%s\n' "$o" | cls --run "$RUN_ID" --item "$REQ" --pr "$PRURL" --record "$P/$RF_REL")"
  [ "$v" = complete ] || no "(CL5) pass $cl5_pass: $v"
  [ "$cl5_pass" = 1 ] && { cp "$P/$RF_REL" "$FX/rf.p1"; cp "$P/$REQ" "$FX/req.p1"; }
done
n_nt="$(grep -c "closeout: nothing to close out — $REQ\$" "$P/$RF_REL")"
[ "$n_nt" = 1 ] && ok "(CL5) two idempotent passes ⇒ complete both times, exactly ONE 'closeout: nothing to close out' line" || no "(CL5) nothing-to-close-out lines: $n_nt"
cmp -s "$FX/rf.p1" "$P/$RF_REL" && cmp -s "$FX/req.p1" "$P/$REQ" && ok "(CL5) the second pass mutates nothing (run file + requirement byte-identical)" || no "(CL5) second pass mutated files"

echo "== CO. closeout-others: another run's merged item is closed out before PICK (cross-run close-out) =="
RB="automate-2026-01-02-000000"; RBF=".supervisor/automate/$RB.md"
mk_rb() { printf '# Automate Run: current\n## Status: running\n## Queue\n- [ ] .supervisor/requirements/f/02-b.md\n## Current\n- item: null | status: null | pr: null | branch: null\n- pause_reason: null\n## Progress\n- t0 run created\n' > "$P/$RBF"; }
co_others() { (cd "$P" && bash "${CO_H:-$SPYD/automate-helpers.sh}" closeout-others .supervisor/automate "$@"); }
closeout_fixture 310; mk_rb; spy_reset
out="$(co_others --record "$RBF")"; rc=$?
printf '%s\n' "$out" | sed 's/^/    | /'
[ "$rc" -eq 0 ] && grep -qxF "closeout-others: $RUN_ID $REQ $PRURL" <<<"$out" && ok "(CO1) header names A's run, item and PR; exit 0" || no "(CO1) rc=$rc header missing"
grep -qxF -- "- [x] $REQ" "$P/$RF_REL" && grep -qF -- "- **PR:** $PRURL" "$P/$REQ" && [ ! -d "$FX/wt-pr" ] && ok "(CO1) A closed out: check-off, stamp, PR worktree removed" || no "(CO1) A not closed out"
grep -qE "^trail-pr $P/$RF_REL --reason closeout\$" "$SPYLOG" && ok "(CO1) A's trail via the dispatcher" || no "(CO1) no trail-pr call for A"
grep -qE "^closeout $P/$RF_REL $REQ $PRURL\$" "$SPYLOG" && ! grep -q -- '--session-id' "$SPYLOG" && ok "(CO1) closeout called without --session-id (its own lock)" || no "(CO1) closeout call: $(grep '^closeout' "$SPYLOG" | tr '\n' '|')"
grep -qE '^- .* closeout https://github.com/acme/widgets/pull/7: closeout: checked' "$P/$RF_REL" && ok "(CO1) A's Progress carries its closeout lines" || no "(CO1) A Progress missing closeout lines"
grep -qx complete <<<"$out" && grep -qxF "closeout-others: recorded — cross-run closeout $RUN_ID $REQ: complete" <<<"$out" && ok "(CO1) classify answer 'complete' + 'recorded — cross-run closeout …' line" || no "(CO1) verdict/record lines missing"
grep -qE "^- [^ ]+ cross-run closeout $RUN_ID $REQ: complete\$" "$P/$RBF" && ! grep -q 'https\?://' "$P/$RBF" && ok "(CO1) B's Progress records the cross-run close-out and carries NO PR URL" || no "(CO1) B record: $(grep cross-run "$P/$RBF")"
[ -z "$(git -C "$P" diff --cached --name-only)" ] && grep -q '^trail-unstage: unstaged' <<<"$out" && ok "(CO1) mode off: no A trail path left staged in the primary index" || no "(CO1) staged: $(git -C "$P" diff --cached --name-only | tr '\n' ' ')"
o2="$(co_others --record "$RBF")"
[ -z "$o2" ] && ok "(CO1) a second run is silent (A's item is now done)" || no "(CO1) second run: $o2"
MUTCO="$TOP/mutd-co"; mkdir -p "$MUTCO"; cp "$SPYD"/*.sh "$SPYD"/*.py "$MUTCO/"; cp -R "$SPYD/automate-helpers.d" "$MUTCO/"; cp -R "$SPYD/automate-trail.d" "$MUTCO/"
grep -vF 'l="$(bash "$HLP" trail-unstage "$f"' "$TB" > "$MUTCO/automate-trail.sh"
if cmp -s "$TB" "$MUTCO/automate-trail.sh" || ! bash -n "$MUTCO/automate-trail.sh"; then no "(CO1) unstage mutant not built"
else
  closeout_fixture 311; mk_rb
  CO_H="$MUTCO/automate-helpers.sh" co_others --record "$RBF" >/dev/null
  grep -qxF -- "- [x] $REQ" "$P/$RF_REL" && [ -n "$(git -C "$P" diff --cached --name-only)" ] && ok "(CO1) control: without trail-unstage A's trail paths stay staged (the clean-index assertion is load-bearing)" || no "(CO1) unstage control did not discriminate"
fi
for v in OPEN CLOSED unreadable done; do
  closeout_fixture "31$(case $v in OPEN) echo 2;; CLOSED) echo 3;; unreadable) echo 4;; done) echo 5;; esac)"; mk_rb
  case "$v" in
    OPEN|CLOSED) jq --arg s "$v" '.[0].state = $s' "$GH_STUB_DIR/prs.json" > "$GH_STUB_DIR/p.tmp" && mv "$GH_STUB_DIR/p.tmp" "$GH_STUB_DIR/prs.json" ;;
    unreadable) touch "$GH_STUB_DIR/pr-view-fail" ;;
    done) sed "s#^- item: $REQ | status: awaiting_merge#- item: $REQ | status: done#" "$P/$RF_REL" > "$P/rf.t" && mv "$P/rf.t" "$P/$RF_REL" ;;
  esac
  a0="$(cksum < "$P/$RF_REL")"; q0="$(cksum < "$P/$REQ")"; b0="$(cksum < "$P/$RBF")"
  o="$(co_others --record "$RBF")"
  [ -z "$o" ] && [ "$a0" = "$(cksum < "$P/$RF_REL")" ] && [ "$q0" = "$(cksum < "$P/$REQ")" ] && [ "$b0" = "$(cksum < "$P/$RBF")" ] && [ -d "$FX/wt-pr" ] \
    && ok "(CO2) A $v ⇒ A, its requirement and B byte-untouched, no line" || no "(CO2) $v: out='$o'"
done
# No --record file yet (a new run): the record line is printed for the engine to append once the run file exists.
closeout_fixture 316
o="$(co_others --record .supervisor/automate/not-created-yet.md)"
grep -qxF "closeout-others: record — cross-run closeout $RUN_ID $REQ: complete" <<<"$o" && ok "(CO3) no run file yet ⇒ 'record — …' printed, nothing appended" || no "(CO3) $o"

# (CO4)-(CO6) the LEFTOVER summary path (S3 wave-1 review: CO1-CO3 cover complete / untouched / no record file only).
# (CO4) real: a dirty primary makes A's close-out a sync leftover; B's Progress records it, no PR URL.
closeout_fixture 317; mk_rb
echo "local edit" >> "$P/README"
o="$(co_others --record "$RBF")"
git -C "$P" checkout -q -- README
grep -qE "^leftover	$RUN_ID	" <<<"$o" \
  && grep -qE "^closeout-others: recorded — cross-run closeout $RUN_ID $REQ: leftover sync — " <<<"$o" \
  && grep -qE "^- [^ ]+ cross-run closeout $RUN_ID $REQ: leftover sync — " "$P/$RBF" && ! grep -q 'https\?://' "$P/$RBF" \
  && ok "(CO4) a dirty primary ⇒ A's close-out is a sync leftover; B records 'leftover sync — …' with no PR URL" \
  || no "(CO4) out=$(printf '%s' "$o" | tr '\n' '|') B=$(grep 'cross-run' "$P/$RBF")"
# (CO5)/(CO6) a stubbed closeout-classify (everything else is the real helper).
CLD="$TOP/clstub"; mkdir -p "$CLD"; cp -R "$SPYD"/* "$CLD/"
cat > "$CLD/automate-helpers.sh" <<'SHIM'
#!/usr/bin/env bash
if [ "${1:-}" = closeout-classify ]; then
  cat >/dev/null
  case "${CL_STUB:-}" in
    empty) exit 0 ;;
    url) printf 'leftover\t-\t-\t-\tgate\tsee https://github.com/acme/widgets/pull/7 for details\n'; exit 0 ;;
  esac
fi
exec bash "$(dirname "$0")/automate-helpers.real.sh" "$@"
SHIM
closeout_fixture 318; mk_rb
o="$(CL_STUB=empty CO_H="$CLD/automate-helpers.sh" co_others --record "$RBF")"
grep -qxF "closeout-others: recorded — cross-run closeout $RUN_ID $REQ: leftover classify — closeout-classify printed nothing" <<<"$o" \
  && ok "(CO5) classify printed nothing ⇒ fallback 'leftover classify — closeout-classify printed nothing' recorded" \
  || no "(CO5) out=$(printf '%s' "$o" | tr '\n' '|')"
closeout_fixture 319; mk_rb
o="$(CL_STUB=url CO_H="$CLD/automate-helpers.sh" co_others --record "$RBF")"
grep -qxF "closeout-others: recorded — cross-run closeout $RUN_ID $REQ: leftover gate — see <url> for details" <<<"$o" \
  && ! grep -q 'https\?://' "$P/$RBF" \
  && ok "(CO6) a leftover detail carrying a PR URL reaches B's Progress as <url> — the record line never carries the URL" \
  || no "(CO6) out=$(printf '%s' "$o" | tr '\n' '|') B=$(grep 'cross-run' "$P/$RBF")"

# (CO7)-(CO9) automate-followups/36 A1: closeout-others meets the run lock held by ANOTHER process.
# co_plant_lock <pid> — a run lock owned by a sibling lane's run, recorded NOW (young: never TTL-reclaimable).
co_plant_lock() {
  mkdir -p "$P/.supervisor/run.lock"
  printf 'pid\t%s\nowner\tautomate:%s-L1\nsession_id\tother-session\nts\t%s\npid_source\tppid\n' "$1" "$RUN_ID" "$(date +%s)" > "$P/.supervisor/run.lock/meta"
}
co_live_leg() { # [<helpers>] — A's merged item meets a lock held by THIS live test shell; sets CO_O
  closeout_fixture 320; mk_rb
  co_plant_lock "$$"
  CO_O="$(CO_H="${1:-}" co_others --record "$RBF")"
}
co_live_leg
CO_HELD="closeout: skipped — run lock held by automate:$RUN_ID-L1 (live pid $$)"
grep -qxF -- "$CO_HELD" <<<"$CO_O" \
  && grep -qE "^run_lock_held	$RUN_ID	" <<<"$CO_O" && ! grep -qE '^leftover	' <<<"$CO_O" \
  && grep -qxF "closeout-others: recorded — cross-run closeout $RUN_ID $REQ: run_lock_held — skipped — run lock held by automate:$RUN_ID-L1 (live pid $$); retried at the next start" <<<"$CO_O" \
  && grep -qxF -- "- [ ] $REQ" "$P/$RF_REL" && grep -q "^owner	automate:$RUN_ID-L1\$" "$P/.supervisor/run.lock/meta" \
  && ok "(CO7) a LIVE holder ⇒ 'live pid' line, a run_lock_held row and NO leftover row (nothing for the gate to park), recorded as retried; A untouched, the lock not stolen" \
  || no "(CO7) out=$(printf '%s' "$CO_O" | tr '\n' '|')"
rm -rf "$P/.supervisor/run.lock"
o="$(co_others --record "$RBF")"
grep -qx complete <<<"$o" && grep -qxF -- "- [x] $REQ" "$P/$RF_REL" \
  && ok "(CO7) the next start (lock released) closes A out: complete, checked off — the retry the record line promised" || no "(CO7) retry: $(printf '%s' "$o" | tr '\n' '|')"
# (CO8) a DEAD holder whose lock is young (run-lock.sh will not reclaim it for 1800 s) stays a leftover.
sleep 0 & DEADPID=$!; wait "$DEADPID" 2>/dev/null
closeout_fixture 321; mk_rb
co_plant_lock "$DEADPID"
o="$(co_others --record "$RBF")"
rm -rf "$P/.supervisor/run.lock"
grep -qxF -- "closeout: skipped — run lock held by automate:$RUN_ID-L1 (holder pid $DEADPID not running)" <<<"$o" \
  && grep -qE "^leftover	$RUN_ID	$REQ	$PRURL	lock	" <<<"$o" && ! grep -q '^run_lock_held	' <<<"$o" \
  && grep -qxF "closeout-others: recorded — cross-run closeout $RUN_ID $REQ: leftover lock — skipped — run lock held by automate:$RUN_ID-L1 (holder pid $DEADPID not running)" <<<"$o" \
  && ok "(CO8) a DEAD (young, unreclaimable) holder ⇒ 'not running' line and a leftover lock row, as before" \
  || no "(CO8) out=$(printf '%s' "$o" | tr '\n' '|')"
# (CO8b) the liveness rule is run-lock.sh's, not a local `kill -0`: a LIVE pid whose recorded
# pid_start does not match (the OS reused it) is a dead holder — 'not running' and a leftover lock.
closeout_fixture 322; mk_rb
co_plant_lock "$$"; printf 'pid_start\tThu Jan  1 00:00:00 1970\n' >> "$P/.supervisor/run.lock/meta"
o="$(co_others --record "$RBF")"
rm -rf "$P/.supervisor/run.lock"
grep -qxF -- "closeout: skipped — run lock held by automate:$RUN_ID-L1 (holder pid $$ not running)" <<<"$o" \
  && grep -qE "^leftover	$RUN_ID	$REQ	$PRURL	lock	" <<<"$o" && ! grep -q '^run_lock_held	' <<<"$o" \
  && ok "(CO8b) a live pid with a mismatched pid_start (reused) ⇒ 'not running' + leftover lock (run-lock.sh's holder_alive, not kill -0)" \
  || no "(CO8b) out=$(printf '%s' "$o" | tr '\n' '|')"
# (CO8c) race: the refused holder (dead) releases and a LIVE newcomer takes the lock before the
# liveness read. The verdict is bound to the refused pid, so it fails toward the leftover — never
# the newcomer's 'alive'. A run-lock.sh wrapper swaps the meta right after a refused acquire.
RACELK="$TOP/race-lock"; mkdir -p "$RACELK"; cp "$SPYD"/*.sh "$SPYD"/*.py "$RACELK/"; cp -R "$SPYD/automate-helpers.d" "$RACELK/"; cp -R "$SPYD/automate-trail.d" "$RACELK/"
mv "$RACELK/run-lock.sh" "$RACELK/run-lock.real.sh"
cat > "$RACELK/run-lock.sh" <<'SHIM'
#!/usr/bin/env bash
out="$(bash "$(dirname "$0")/run-lock.real.sh" "$@")"; rc=$?
[ -z "$out" ] || printf '%s\n' "$out"
if [ "${1:-}" = acquire ] && [ "$rc" -ne 0 ] && [ -n "${RACE_META:-}" ]; then
  printf 'pid\t%s\nowner\tnewcomer\nsession_id\tnew\nts\t%s\npid_source\tppid\n' "$RACE_NEWPID" "$(date +%s)" > "$RACE_META"
fi
exit "$rc"
SHIM
sleep 0 & DEADPID=$!; wait "$DEADPID" 2>/dev/null
closeout_fixture 323; mk_rb
co_plant_lock "$DEADPID"
o="$(RACE_META="$P/.supervisor/run.lock/meta" RACE_NEWPID="$$" CO_H="$RACELK/automate-helpers.sh" co_others --record "$RBF")"
raced="$(grep -c '^owner	newcomer$' "$P/.supervisor/run.lock/meta" 2>/dev/null)"
rm -rf "$P/.supervisor/run.lock"
[ "$raced" = 1 ] \
  && grep -qxF -- "closeout: skipped — run lock held by automate:$RUN_ID-L1 (holder pid $DEADPID not running)" <<<"$o" \
  && grep -qE "^leftover	$RUN_ID	$REQ	$PRURL	lock	" <<<"$o" && ! grep -q '^run_lock_held	' <<<"$o" \
  && ok "(CO8c) refusal→liveness race (dead holder replaced by a live one) ⇒ still 'not running' + leftover lock" \
  || no "(CO8c) raced=$raced out=$(printf '%s' "$o" | tr '\n' '|')"
# (CO9) mutation control: drop the live-holder check ⇒ a live holder reads as a leftover again (CO7 red).
MUTLK="$TOP/mutd-lock"; mkdir -p "$MUTLK"; cp "$SPYD"/*.sh "$SPYD"/*.py "$MUTLK/"; cp -R "$SPYD/automate-helpers.d" "$MUTLK/"; cp -R "$SPYD/automate-trail.d" "$MUTLK/"
sed 's/^    if \[ "\$hlive" = alive \]; then$/    if false; then  # mutant A1/' "$TB" > "$MUTLK/automate-trail.sh"
if grep -q '# mutant A1' "$MUTLK/automate-trail.sh" && bash -n "$MUTLK/automate-trail.sh"; then
  co_live_leg "$MUTLK/automate-helpers.sh"
  rm -rf "$P/.supervisor/run.lock"
  grep -qE "^leftover	$RUN_ID	$REQ	$PRURL	lock	" <<<"$CO_O" && ! grep -q '^run_lock_held	' <<<"$CO_O" \
    && ok "(CO9) control: without the live-holder check a busy lane's lock is a leftover again — CO7 is load-bearing" \
    || no "(CO9) control did not discriminate: $(printf '%s' "$CO_O" | tr '\n' '|')"
else
  no "(CO9) mutant A1 not built"
fi

echo "== K. SKILL wiring (Part A, automate-followups/32) =="
s6="$(awk '/^## §6 /{s=1;next} s&&/^## /{exit} s' "$SKILL")"
gate="$(grep -m1 -F '**Close-out leftover gate' <<<"$s6")"
for t in 'closeout-classify --run <run_id> --item <item> --pr <pr_url> --record <runfile>`' '**Clean up now**' '**Keep and continue**' '**Stop**' 'ONE owner question batching ≤4 leftovers' 'never proceeds silently' '`current-set <runfile> --pause-reason closeout_leftover`' '`worktree-salvage.sh` runs before any `git worktree remove`' 're-classifies ONCE' 'closeout leftover kept: <run_id> <step> <detail>' '`run-lock.sh release`'; do
  grep -qF -- "$t" <<<"$gate" && ok "§6 step 1 leftover gate names $t" || no "§6 step 1 leftover gate missing $t"
done
s4="$(awk '/^## §4 /{s=1;next} s&&/^## /{exit} s' "$SKILL")"
grep -qF -- '`meta-entry` (branch mode) → **`closeout-others`** → `resume-glob --finalize` (step 1) → list / ask (step 4)' <<<"$s4" && ok "§4 start order: meta-entry → closeout-others → resume-glob --finalize → list/ask" || no "§4 start order missing"
grep -qF -- '`closeout_leftover`, `limit_reached` write the park state' "$SKILL" && ok "trail no-park list names closeout_leftover" || no "no-park list missing closeout_leftover"
grep -qF -- '**Other runs'"'"' merged items (`closeout-others`' "$SKILL" && ok "§8 names the cross-run close-out" || no "§8 cross-run bullet missing"
grep -qF 'nothing surfaces a live watcher at SessionStart' "$SKILL" && no "SKILL still says nothing surfaces a live watcher" || ok "SKILL's SessionStart honest limit updated"
for s in closeout-classify closeout-others; do
  grep -q "^| \`$s\` |" "$SKILL" && ok "§1.5 row: $s" || no "§1.5 row missing: $s"
  grep -q "^  $s " <<<"$(bash "$H" --help)" && ok "--help lists $s" || no "--help missing $s"
done
grep -qE '^    closeout-others\) exec bash "\$\(dirname "\$0"\)/automate-trail.sh" "\$cmd" "\$@" ;;' "$H" && ok "dispatcher row: closeout-others → automate-trail.sh" || no "closeout-others dispatcher row missing"
grep -qF 'closeout-classify' "$HERE/../commands/automate.md" && grep -qF 'closeout-others' "$HERE/../commands/automate.md" && ok "commands/automate.md overview names closeout-classify + closeout-others" || no "commands/automate.md surface missing"

echo "== LN. parallel-automate/05: a lane clone never closes out / finalizes another run (Scope 3 amendment, D2) =="
# Two-lane fleet against the same old unfinished run A (merged PR): each lane skips with ONE line and
# touches nothing; the coordinator (no lane.json — the primary) then closes A out exactly once.
closeout_fixture 340; mk_rb; spy_reset
a0="$(cksum < "$P/$RF_REL")"; q0="$(cksum < "$P/$REQ")"; ln_lane_out=""
for ln_l in L1 L2; do
  printf '{"schema_version":1,"lane":"%s","run_id":"par-9-%s","parent_run_id":"par-9"}\n' "$ln_l" "$ln_l" > "$P/.supervisor/lane.json"
  ln_o="$(co_others --record "$RBF")"; ln_lane_out="$ln_lane_out$ln_o"$'\n'
  [ "$ln_o" = "closeout-others: skipped — lane clone" ] && ok "(LN1) lane $ln_l: closeout-others prints ONE 'skipped — lane clone' line" || no "(LN1) lane $ln_l: '$ln_o'"
done
{ [ "$a0" = "$(cksum < "$P/$RF_REL")" ] && [ "$q0" = "$(cksum < "$P/$REQ")" ] && [ -d "$FX/wt-pr" ] && [ -z "$(grep -v '^closeout-others ' "$SPYLOG" 2>/dev/null)" ]; } \
  && ok "(LN1) neither lane touched A, its requirement or its PR worktree, and made no dispatcher call beyond closeout-others itself" || no "(LN1) a lane mutated A / called out: $(tr '\n' '|' < "$SPYLOG" 2>/dev/null)"
[ "$(grep -c '^closeout-others: '"$RUN_ID " <<<"$ln_lane_out")" = 0 ] && ok "(LN1) zero closeout lines in either lane" || no "(LN1) lane closeout lines: $ln_lane_out"
rm -f "$P/.supervisor/lane.json"
ln_o="$(co_others --record "$RBF")"
[ "$(grep -c "^closeout-others: $RUN_ID $REQ $PRURL\$" <<<"$ln_o")" = 1 ] && grep -qxF -- "- [x] $REQ" "$P/$RF_REL" \
  && ok "(LN1) the coordinator (primary, no lane.json) closes A out exactly once" || no "(LN1) coordinator closeout: $ln_o"
# Mutation control: TWO independent layers keep a lane out of the cross-run closeout — the
# `_in_lane_clone` guard in closeout_others and resume-glob's lane scoping (a lane clone lists only
# its own run). Dropping the guard alone leaves the lane silent (defense in depth, LN2a); dropping
# both lets the lane close A out, so the LN1 assertion is load-bearing (LN2b).
closeout_fixture 341; mk_rb; spy_reset
MUTLN="$TOP/mutln"; mkdir -p "$MUTLN"; cp -R "$SPYD"/* "$MUTLN/"
sed '/^  if _in_lane_clone "\$root"; then echo "\$S lane clone"; return 0; fi$/d' "$TB" > "$MUTLN/automate-trail.sh"
printf '{"schema_version":1,"lane":"L1","run_id":"par-9-L1","parent_run_id":"par-9"}\n' > "$P/.supervisor/lane.json"
if ! cmp -s "$TB" "$MUTLN/automate-trail.sh" && bash -n "$MUTLN/automate-trail.sh"; then
  ln_o="$(CO_H="$MUTLN/automate-helpers.sh" co_others --record "$RBF")"
  [ -z "$ln_o" ] && ok "(LN2a) guard dropped alone: resume-glob's lane scoping still keeps A out of the lane (empty output)" || no "(LN2a) guard-only mutant: '$ln_o'"
  sed '/^    if \[ -f "\$dir\/\.\.\/lane\.json" \]; then \[ -n "\$own" \]/d' "$SPYD/automate-helpers.d/resume.sh" > "$MUTLN/automate-helpers.d/resume.sh"
  if ! cmp -s "$SPYD/automate-helpers.d/resume.sh" "$MUTLN/automate-helpers.d/resume.sh" && bash -n "$MUTLN/automate-helpers.d/resume.sh"; then
    ln_o="$(CO_H="$MUTLN/automate-helpers.sh" co_others --record "$RBF")"
    grep -qxF "closeout-others: $RUN_ID $REQ $PRURL" <<<"$ln_o" && ok "(LN2b) mutation control: both layers dropped ⇒ the lane closes out A — the lane assertion is load-bearing" || no "(LN2b) mutation control inconclusive: '$ln_o'"
  else
    no "(LN2b) mutation control: could not build the resume.sh mutant"
  fi
else
  no "(LN2) mutation control: could not build the mutant"
fi
rm -f "$P/.supervisor/lane.json"
# finalize-empty in a lane clone: another run's eligible file is refused untouched; the lane's own run is not refused.
closeout_fixture 342
fe_rf other-run paused awaiting_go x done; fe_rf par-9-L1 paused awaiting_go x done
printf '{"schema_version":1,"lane":"L1","run_id":"par-9-L1","parent_run_id":"par-9"}\n' > "$P/.supervisor/lane.json"
ln_c="$(cksum < "$P/$AUTD/other-run.md")"
ln_o="$(cd "$P" && bash "$H" finalize-empty "$AUTD/other-run.md")"
[ "$ln_o" = "finalize-empty: skipped — lane clone (not this lane's run)" ] && [ "$ln_c" = "$(cksum < "$P/$AUTD/other-run.md")" ] \
  && ok "(LN3) finalize-empty in a lane: another run's eligible file ⇒ 'skipped — lane clone (not this lane's run)', byte-untouched" || no "(LN3) other run: '$ln_o'"
ln_o="$(cd "$P" && bash "$H" finalize-empty "$AUTD/par-9-L1.md" 2>/dev/null | head -n1)"
case "$ln_o" in *"lane clone"*) no "(LN3) the lane's own run was refused: '$ln_o'" ;; *) ok "(LN3) finalize-empty in a lane: its own run is not refused by the lane guard ('$ln_o')" ;; esac
rm -f "$P/.supervisor/lane.json" "$P/$AUTD/other-run.md" "$P/$AUTD/par-9-L1.md"

echo "== DS. automate-followups/37: a requirement's done stamp is written only by the post-merge closeout =="
# The fixture mirrors the end state of a sequential `/autonomous` + owned drain whose PR is still
# OPEN: the requirement at `## Status: pending`, its done brief in jobs/done/ pointing at it (with
# the `## Outcome` Phase 4.5 writes), the PR stubbed OPEN. Phase 4.5's completion tail is prose, so
# it is simulated by APPLYING whatever requirement stamp block the self-heal skill's step 2.5
# instructs (extracted, never hand-typed): on the base commit that block is a sentinel-led
# `## Status: done` and DS1 fails; since this item the step instructs none and the file is untouched.
DS_SKILL="$HERE/../skills/self-heal-advisory/SKILL.md"
# ds_tail_stamp <skill> — the first requirement stamp block the completion tail's step 2.5 tells the
# agent to write: the lines from an un-backticked sentinel line to the closing code fence, de-indented.
ds_tail_stamp() {
  awk '/^2\.5\. /{s=1} /^2\.6\. /{s=0} s' "$1" | awk '
    !d && /<!-- loomwright:requirement-closeout -->/ && !/`/ { b = 1 }
    b && /^[[:space:]]*```/ { b = 0; d = 1; next }
    b { sub(/^[[:space:]]+/, ""); print }'
}
# (control) the extractor is not vacuous: a step 2.5 shaped like the base commit's yields its block.
printf '%s\n' '2.5. **Requirement close-out:**' '      ```markdown' '      <!-- loomwright:requirement-closeout -->' \
  '      ## Status: done' '      - **PR:** {PR URL}' '      ```' '2.6. **Next**' > "$TOP/ds-base-shape.md"
[ "$(ds_tail_stamp "$TOP/ds-base-shape.md" | sed -n 2p)" = "## Status: done" ] \
  && ok "(DS0) control: the step-2.5 stamp extractor finds a base-shaped sentinel block" || no "(DS0) extractor is vacuous: $(ds_tail_stamp "$TOP/ds-base-shape.md" | tr '\n' '|')"
closeout_fixture 370
printf '# req a\n\n## Status: pending\n' > "$P/$REQ"
printf '\n## Outcome\n- **Status:** completed\n- **PR:** %s\n- **Heal decision:** PASS\n' "$PRURL" >> "$P/.supervisor/jobs/done/brief-a.md"
rm -f "$P/.supervisor/jobs/in-progress/brief-live.md"   # step 2 moved the run's brief; none is left in progress
ds_stamp="$(ds_tail_stamp "$DS_SKILL")"
[ -z "$ds_stamp" ] || printf '\n%s\n' "$ds_stamp" >> "$P/$REQ"   # the simulated completion tail
jq '.[0].state = "OPEN"' "$GH_STUB_DIR/prs.json" > "$GH_STUB_DIR/p.tmp" && mv "$GH_STUB_DIR/p.tmp" "$GH_STUB_DIR/prs.json"
printf '# req a\n\n## Status: pending\n' > "$TOP/ds-req-pending"
out="$(run_closeout)"
[ "$out" = "closeout: skipped — pr not merged (awaiting_merge)" ] && ok "(DS1) PR OPEN ⇒ closeout prints one 'pr not merged' line" || no "(DS1) OPEN closeout: $out"
cmp -s "$P/$REQ" "$TOP/ds-req-pending" && ! grep -qE '^## Status:[[:space:]]*done' "$P/$REQ" \
  && ok "(DS1) PR OPEN after Phase 4.5 + closeout ⇒ the requirement is byte-identical (## Status: pending) and carries no ## Status: done" \
  || no "(DS1) PR OPEN: requirement changed or claims done: $(tr '\n' '|' < "$P/$REQ")"
jq '.[0].state = "MERGED"' "$GH_STUB_DIR/prs.json" > "$GH_STUB_DIR/p.tmp" && mv "$GH_STUB_DIR/p.tmp" "$GH_STUB_DIR/prs.json"
out="$(run_closeout)"
case "$out" in *"closeout: stamped — $REQ (## Status: done, brief .supervisor/jobs/done/brief-a.md)"*) ok "(DS2) PR MERGED ⇒ closeout stamps the requirement" ;; *) no "(DS2) MERGED closeout: $(printf '%s' "$out" | tr '\n' '|')" ;; esac
[ "$(grep -cF '<!-- loomwright:requirement-closeout -->' "$P/$REQ")" = 1 ] && [ "$(grep -cE '^## Status:[[:space:]]*done' "$P/$REQ")" = 1 ] \
  && ok "(DS2) exactly one sentinel-led done block" || no "(DS2) sentinel/done count: $(tr '\n' '|' < "$P/$REQ")"
grep -qE '^- \*\*Completed:\*\* [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$P/$REQ" && ok "(DS2) Completed is a UTC ISO-8601 timestamp" || no "(DS2) Completed line malformed"
{ cat "$TOP/ds-req-pending"
  printf '\n<!-- loomwright:requirement-closeout -->\n## Status: done\n- **Completed:** <TS>\n- **Brief:** .supervisor/jobs/done/brief-a.md\n- **PR:** %s\n' "$PRURL"; } > "$TOP/ds-req-want"
sed -E 's/^(- \*\*Completed:\*\* ).*/\1<TS>/' "$P/$REQ" > "$TOP/ds-req-got"
cmp -s "$TOP/ds-req-got" "$TOP/ds-req-want" && ok "(DS2) the requirement is the pending bytes + the closeout printf block, byte for byte (Completed normalised)" \
  || no "(DS2) stamped bytes differ: $(diff "$TOP/ds-req-want" "$TOP/ds-req-got" | tr '\n' '|')"
grep -qF "printf '\n<!-- loomwright:requirement-closeout -->\n## Status: done\n- **Completed:** %s\n- **Brief:** %s\n- **PR:** %s\n'" "$TB" \
  && ok "(DS2) closeout's step-5 printf is unchanged in automate-trail.sh" || no "(DS2) closeout printf changed"
# Contract: the completion tail instructs no requirement `## Status:` stamp (fails on the base commit).
[ -z "$(grep -A1 -F '<!-- loomwright:requirement-closeout -->' "$DS_SKILL" | grep '## Status')" ] \
  && ok "(DS3) contract: self-heal-advisory carries no sentinel-led requirement ## Status block" || no "(DS3) self-heal-advisory still carries a requirement stamp block"
ds25="$(awk '/^2\.5\. /{s=1} /^2\.6\. /{s=0} s' "$DS_SKILL")"
if grep -q '^2\.5\. \*\*Requirement close-out' <<<"$ds25" && ! grep -qE '^[[:space:]]*## Status:' <<<"$ds25" \
   && grep -qF 'writes NOTHING to the requirement' <<<"$ds25" && grep -qF '`automate-helpers.sh closeout`' <<<"$ds25"; then
  ok "(DS3) contract: step 2.5 (Requirement close-out) defers to closeout and stamps no ## Status: line"
else
  no "(DS3) step 2.5 still stamps, or no longer names the deferral to closeout"
fi

echo "== NT. automate-followups/38: closeout --no-trail, the --auto-merge SYNC close-out, the strict sentinel guard =="
# nt_norm <file> <fx dir> — a run file / requirement with the per-fixture bytes normalised: the fixture
# dir, UTC timestamps and git object ids (each fixture's squash merge is a different commit).
nt_norm() { sed -E "s#$2#<FX>#g; s/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z/<TS>/g; s/[0-9a-f]{7,40}/<OID>/g" "$1"; }
nt_seed() { # a session id + pick/park so closeout's silent item_timing step has a record to write
  printf -- '- 2026-10-01T10:00:00Z picked %s\n- 2026-10-01T10:30:00Z session_id sess-nt (%s)\n- 2026-10-01T11:00:00Z parked awaiting_merge\n' "$REQ" "$REQ" >> "$P/$RF_REL"
  mkdir -p "$P/.supervisor/logs"
}
# (NT1) the plain closeout reference run, then the same fixture shape under --no-trail (flag FIRST).
closeout_fixture 500; nt_seed; spy_reset
nt_plain="$(run_closeout)"; NT_FXP="$FX"; cp "$P/$RF_REL" "$TOP/nt-rf-plain"; cp "$P/$REQ" "$TOP/nt-req-plain"
closeout_fixture 501; nt_seed; spy_reset
nt_c0="$(count_creates)"
nt_out="$(cd "$P" && bash "$SPYD/automate-helpers.sh" closeout --no-trail "$RF_REL" "$REQ" "$PRURL")"; rc=$?
printf '%s\n' "$nt_out" | sed 's/^/    | /'
[ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$nt_out" | tail -n1)" = "trail-pr: skipped — --no-trail" ] \
  && ok "(NT1) --no-trail: exit 0, last line 'trail-pr: skipped — --no-trail'" || no "(NT1) rc=$rc last=$(printf '%s\n' "$nt_out" | tail -n1)"
if grep -q '^trail-pr ' "$SPYLOG" 2>/dev/null; then no "(NT1) trail-pr was called: $(grep '^trail-pr ' "$SPYLOG")"; else ok "(NT1) --no-trail: no trail-pr call (spy)"; fi
[ "$(count_creates)" = "$nt_c0" ] && ok "(NT1) --no-trail: no trail PR created" || no "(NT1) a trail PR was opened"
for t in "brief-repair: " "closeout: removed — worktree " "closeout: synced — main at " "closeout: removed — branch feature/x" "closeout: stamped — $REQ" "closeout: checked — - [x] $REQ" "closeout: reconciled — ## Current $REQ status done, pause_reason awaiting_go"; do
  grep -qF -- "$t" <<<"$nt_out" && ok "(NT1) --no-trail still runs: $t" || no "(NT1) --no-trail missing step line: $t"
done
nt_norm "$TOP/nt-req-plain" "$NT_FXP" > "$TOP/nt-req-a"; nt_norm "$P/$REQ" "$FX" > "$TOP/nt-req-b"
cmp -s "$TOP/nt-req-a" "$TOP/nt-req-b" && grep -qxF '<!-- loomwright:requirement-closeout -->' "$P/$REQ" \
  && ok "(NT1) the requirement block is byte-identical to plain closeout's (Completed normalised)" || no "(NT1) requirement differs: $(diff "$TOP/nt-req-a" "$TOP/nt-req-b" | tr '\n' '|')"
nt_norm "$TOP/nt-rf-plain" "$NT_FXP" > "$TOP/nt-rf-a"; nt_norm "$P/$RF_REL" "$FX" > "$TOP/nt-rf-b"
cmp -s "$TOP/nt-rf-a" "$TOP/nt-rf-b" && grep -qE '^- .* closeout https://github.com/acme/widgets/pull/7: closeout: checked' "$P/$RF_REL" \
  && ok "(NT1) the run file (check-off, ## Current reconcile, ## Progress lines) equals plain closeout's, normalised" || no "(NT1) run file differs: $(diff "$TOP/nt-rf-a" "$TOP/nt-rf-b" | tr '\n' '|')"
[ "$(it_count "$P/.supervisor/logs/sess-nt.jsonl")" = 1 ] && ok "(NT1) --no-trail still appends ONE item_timing event" || no "(NT1) item_timing rows: $(it_count "$P/.supervisor/logs/sess-nt.jsonl")"
[ ! -d "$P/.supervisor/run.lock" ] && ok "(NT1) --no-trail releases the closeout run lock" || no "(NT1) run lock leaked under --no-trail"
case "$nt_plain" in *"closeout: stamped — "*) ok "(NT1) control: the plain reference run stamped too" ;; *) no "(NT1) plain reference run did not stamp: $nt_plain" ;; esac
# (NT1b) the flag between the positionals and next to --session-id parses the same (never swallowed as pr_url).
closeout_fixture 502; spy_reset
nt_out2="$(cd "$P" && bash "$SPYD/automate-helpers.sh" closeout "$RF_REL" --no-trail "$REQ" --session-id nt-sid "$PRURL")"
if [ "$(printf '%s\n' "$nt_out2" | tail -n1)" = "trail-pr: skipped — --no-trail" ] && grep -qF "closeout: stamped — $REQ" <<<"$nt_out2" && ! grep -q '^trail-pr ' "$SPYLOG" 2>/dev/null; then
  ok "(NT1b) --no-trail between the positionals (with --session-id) ⇒ the same close-out, no trail"
else no "(NT1b) $(printf '%s' "$nt_out2" | tr '\n' '|')"; fi
# (NT3) closeout-classify reads the whole --no-trail output as complete.
nt_cv="$(printf '%s\n' "$nt_out" | cls --run "$RUN_ID" --item "$REQ" --pr "$PRURL")"
[ "$nt_cv" = complete ] && ok "(NT3) closeout-classify on a MERGED --no-trail run prints exactly 'complete'" || no "(NT3) classify: $(printf '%s' "$nt_cv" | tr '\n' '|')"
# (NT2) PR OPEN + --no-trail ⇒ one evidence-gate line, nothing written, no spy call.
closeout_fixture 503; spy_reset
jq '.[0].state = "OPEN"' "$GH_STUB_DIR/prs.json" > "$GH_STUB_DIR/p.tmp" && mv "$GH_STUB_DIR/p.tmp" "$GH_STUB_DIR/prs.json"
a0="$(cksum < "$P/$RF_REL")"; q0="$(cksum < "$P/$REQ")"
nt_out="$(cd "$P" && bash "$SPYD/automate-helpers.sh" closeout "$RF_REL" "$REQ" "$PRURL" --no-trail)"
if [ "$nt_out" = "closeout: skipped — pr not merged (awaiting_merge)" ] && [ "$a0" = "$(cksum < "$P/$RF_REL")" ] && [ "$q0" = "$(cksum < "$P/$REQ")" ] && ! grep -q '^trail-pr ' "$SPYLOG" 2>/dev/null; then
  ok "(NT2) --no-trail on an OPEN PR prints only 'pr not merged', run file + requirement byte-unchanged, no trail-pr"
else no "(NT2) $nt_out"; fi

# (NT4) the --auto-merge SYNC close-out (SKILL §6 step 5): branch mode OFF, requirement pending, its
# done brief in jobs/done/, the PR MERGED by the gate; the PICK lock is held and re-entered.
closeout_fixture 504; spy_reset
printf '# req a\n\n## Status: pending\n' > "$P/$REQ"
sed "s#^- item: $REQ | status: awaiting_merge#- item: $REQ | status: running#; s#^- pause_reason: awaiting_merge#- pause_reason: null#; s#^\#\# Status: paused#\#\# Status: running#" "$P/$RF_REL" > "$P/rf.t" && mv "$P/rf.t" "$P/$RF_REL"
bash "$HERE/run-lock.sh" acquire --owner "automate:$RUN_ID" --session-id NT-SID --root "$P" >/dev/null
nt_c0="$(count_creates)"
nt_out="$(cd "$P" && bash "$SPYD/automate-helpers.sh" closeout "$RF_REL" "$REQ" "$PRURL" --no-trail --session-id NT-SID)"
printf '%s\n' "$nt_out" | sed 's/^/    | /'
[ "$(grep -A1 -xF '<!-- loomwright:requirement-closeout -->' "$P/$REQ" | tr '\n' '|')" = "<!-- loomwright:requirement-closeout -->|## Status: done|" ] && [ "$(grep -cE '^## Status:[[:space:]]*done' "$P/$REQ")" = 1 ] \
  && ok "(NT4) auto-merge SYNC: the requirement carries ONE sentinel-led ## Status: done block" || no "(NT4) requirement: $(tr '\n' '|' < "$P/$REQ")"
[ "$(grep -cxF -- "- [x] $REQ" "$P/$RF_REL")" = 1 ] && ok "(NT4) exactly one - [x] row for the item" || no "(NT4) check-off rows: $(grep -cF "$REQ" "$P/$RF_REL")"
grep -qF -- "- item: $REQ | status: done" "$P/$RF_REL" && grep -qxF -- '- pause_reason: null' "$P/$RF_REL" \
  && ok "(NT4) ## Current reconciled to done / null (the run is running)" || no "(NT4) ## Current: $(grep -A2 '^## Current' "$P/$RF_REL" | tr '\n' '|')"
if [ "$(count_creates)" = "$nt_c0" ] && ! grep -q '^trail-pr ' "$SPYLOG" 2>/dev/null; then ok "(NT4) no trail PR opened (gh stub create count + trail-pr spy: zero calls)"; else no "(NT4) a trail PR was opened"; fi
grep -q "^owner	automate:$RUN_ID\$" "$P/.supervisor/run.lock/meta" 2>/dev/null && ok "(NT4) the PICK lock survives the re-entered closeout" || no "(NT4) PICK lock lost"
tg="$(cd "$P" && bash "$H" trail-gate "$RF_REL")"
case "$tg" in "trail-gate: clear — "*) ok "(NT4) the next PICK's trail-gate reads clear ($tg)" ;; *) no "(NT4) trail-gate: $tg" ;; esac
bash "$HERE/run-lock.sh" release --owner "automate:$RUN_ID" --root "$P" >/dev/null

# (NT5) the strict sentinel guard: a quoted sentinel is not a stamp; a real stamp block is.
nt_q='quotes `<!-- loomwright:requirement-closeout -->` inline in its prose'
for v in inline ownline real dwe; do
  case "$v" in inline) closeout_fixture 510 ;; ownline) closeout_fixture 511 ;; real) closeout_fixture 512 ;; dwe) closeout_fixture 513 ;; esac
  case "$v" in
    inline)  printf '# req a\n\n## Status: pending\n\n## Problem\nThe guard %s.\n' "$nt_q" > "$P/$REQ" ;;
    ownline) printf '# req a\n\n## Status: pending\n\n## Problem\n<!-- loomwright:requirement-closeout -->\nis the sentinel, quoted on its own line.\n' > "$P/$REQ" ;;
    real)    printf '# req a\n\n<!-- loomwright:requirement-closeout -->\n## Status: done\n- **PR:** %s\n' "$PRURL" > "$P/$REQ" ;;
    dwe)     printf '# req a\n\n<!-- loomwright:requirement-closeout -->\n## Status: done_with_escalation — heal reason x\n- **PR:** %s\n' "$PRURL" > "$P/$REQ" ;;
  esac
  q0="$(cksum < "$P/$REQ")"
  nt_out="$(run_closeout)"
  case "$v" in
    inline|ownline)
      grep -qF "closeout: stamped — $REQ" <<<"$nt_out" && [ "$(grep -cE '^## Status:[[:space:]]*done' "$P/$REQ")" = 1 ] \
        && ok "(NT5) a sentinel quoted $v in prose ⇒ closeout stamps" || no "(NT5) $v: $(grep -F 'closeout: s' <<<"$nt_out" | tr '\n' '|')"
      nt_out="$(run_closeout)"
      grep -qxF "closeout: skipped — already stamped" <<<"$nt_out" && [ "$(grep -cE '^## Status:[[:space:]]*done' "$P/$REQ")" = 1 ] \
        && ok "(NT5) $v: the re-run reads its own block as stamped (idempotent, one block)" || no "(NT5) $v re-run: $(tr '\n' '|' <<<"$nt_out")" ;;
    *)
      grep -qxF "closeout: skipped — already stamped" <<<"$nt_out" && [ "$q0" = "$(cksum < "$P/$REQ")" ] \
        && ok "(NT5) a real stamp block ($v) ⇒ skipped — already stamped, requirement unchanged" || no "(NT5) $v: $(tr '\n' '|' <<<"$nt_out")" ;;
  esac
done

# (NT6) SKILL / command / --help wiring (Scope 2 + 3 text).
# §6 steps 5–6 (SYNC, CHECK OFF) are run by scripts/automate-next-step.sh's `sync` / `leftover` /
# `checkoff` case arms: automate-speed/08 retired the --legacy prose (legacy-tail.md) the step-5/6 legs
# used to read, so they read the driver — the function each arm calls (never a first-match read of the
# assembled skill, whose per-item-loop.md stub lines only point at the driver).
nt_drv="$HERE/automate-next-step.sh"
nt_fn() { awk -v f="$2" '$0 ~ "^" f "\\(\\) \\{" { s = 1 } s { print } s && /^\}/ { exit }' "$1"; }
nt_st5="$(nt_fn "$nt_drv" ns_sync)"
nt_t1='closeout "$RF" "$ITEM" "$PR" --no-trail ${SID:+--session-id "$SID"}'
for t in "$nt_t1" 'closeout-classify --run "$RUN_ID" --item "$ITEM" --pr "$PR" --record "$RF"' 'st_set leftovers "$cls"; NEXT=leftover'; do
  grep -qF -- "$t" <<<"$nt_st5" && ok "(NT6) driver ns_sync (step 5 SYNC) names $t" || no "(NT6) driver ns_sync (step 5 SYNC) missing $t"
done
# BOTH branch modes: SYNC's --no-trail is unconditional (no branch-mode read in the sync step), and
# closeout's step 2 IS brief-repair (SYNC runs no brief-repair of its own)
grep -qE 'meta|branch' <<<"$nt_st5" && no "(NT6) driver ns_sync reads the branch mode (--no-trail must hold in BOTH branch modes)" || ok "(NT6) driver ns_sync passes --no-trail in BOTH branch modes (no branch-mode read)"
grep -qF 'brief-repair' <<<"$nt_st5" && no "(NT6) driver ns_sync runs its own brief-repair (closeout's step 2 IS brief-repair)" || ok "(NT6) driver ns_sync leaves brief-repair to closeout's step 2"
grep -qF -- 'current-set "$RF" --pause-reason closeout_leftover' <<<"$(nt_fn "$nt_drv" ns_leftover_park)" && ok "(NT6) driver leftover park writes pause_reason closeout_leftover" || no "(NT6) driver leftover park lacks closeout_leftover"
grep -qE 'git (checkout|pull)' <<<"$nt_st5" && no "(NT6) SYNC still runs its own git checkout main && git pull" || ok "(NT6) SYNC no longer runs its own git checkout main && git pull"
nt_ck_ok() {  # <driver> — ok iff checkoff calls queue-checkoff only for a still-unchecked row and writes ONE line
  local b; b="$(nt_fn "$1" ns_checkoff)"
  if grep -qE '^[[:space:]]+checkoff\) ns_checkoff ;;' "$1" && grep -qF -- 'grep -qxF -- "- [ ] $ITEM"; then' <<<"$b" \
     && [ "$(grep -c 'queue-checkoff' <<<"$b")" = 1 ] && [ "$(grep -cF 'checked off $ITEM' <<<"$b")" = 1 ]; then printf ok; else printf bad; fi
}
[ "$(nt_ck_ok "$nt_drv")" = ok ] && ok "(NT6) driver checkoff (step 6): an auto-merged item is already - [x], not checked off twice" || no "(NT6) step 6 double check-off not addressed"
# Mutation control (repointed from the --legacy prose mutant): a driver copy whose checkoff checks the
# item off a second time (an unguarded queue-checkoff after the guarded one) turns the step-6 leg red
# (gated: non-empty, differs, bash -n).
nt_mut="$TOP/nt6-legacy-mutant.sh"
awk '/^ns_checkoff\(\) \{/ { s = 1 } { print } s && /^  fi$/ { print "  ns_call_writer queue-checkoff \"$RF\" \"$ITEM\" || return 1"; s = 0 }' "$nt_drv" > "$nt_mut"
if [ -s "$nt_mut" ] && ! cmp -s "$nt_drv" "$nt_mut" && bash -n "$nt_mut" 2>/dev/null; then
  [ "$(nt_ck_ok "$nt_mut")" = bad ] && ok "(NT6) mutant driver (checkoff checks the item off a second time) turns the step-6 leg red" || no "(NT6) mutant driver (double check-off) still passes the step-6 leg"
else
  no "(NT6) step-6 mutant could not be built (empty, identical or bash -n failed)"
fi
# The --no-trail rule's own driver leg (the sync arm), with its mutant below.
nt_sync_ok() {  # <driver> — ok iff the sync arm exists and its function runs closeout --no-trail + closeout-classify
  local b; b="$(nt_fn "$1" ns_sync)"
  if grep -qE '^[[:space:]]+sync\) ns_sync ;;' "$1" && grep -qF 'closeout "$RF" "$ITEM" "$PR" --no-trail' <<<"$b" \
     && grep -qF 'closeout-classify --run "$RUN_ID" --item "$ITEM" --pr "$PR" --record "$RF"' <<<"$b"; then printf ok; else printf bad; fi
}
[ "$(nt_sync_ok "$nt_drv")" = ok ] && ok "(NT6) driver sync arm runs closeout --no-trail, classified by closeout-classify" || no "(NT6) driver sync arm lacks closeout --no-trail / closeout-classify"
nt_ck="$(nt_fn "$nt_drv" ns_checkoff)"
if grep -qE '^[[:space:]]+checkoff\) ns_checkoff ;;' "$nt_drv" && grep -qF -- 'grep -qxF -- "- [ ] $ITEM"' <<<"$nt_ck" && grep -qF 'queue-checkoff' <<<"$nt_ck"; then
  ok "(NT6) driver checkoff arm calls queue-checkoff only for a still-unchecked row (no double check-off)"
else
  no "(NT6) driver checkoff arm does not guard queue-checkoff on an unchecked row"
fi
nt_dmut="$TOP/nt6-driver-mutant.sh"
awk '/^ns_sync\(\) \{/ { s = 1 } s && /closeout "\$RF" "\$ITEM" "\$PR" --no-trail/ { sub(/ --no-trail/, "") } s && /^\}/ { s = 0 } 1' "$nt_drv" > "$nt_dmut"
if [ -s "$nt_dmut" ] && ! cmp -s "$nt_drv" "$nt_dmut" && bash -n "$nt_dmut" 2>/dev/null; then
  [ "$(nt_sync_ok "$nt_dmut")" = bad ] && ok "(NT6) mutant driver (sync without --no-trail) turns the sync-arm leg red" || no "(NT6) mutant driver (sync without --no-trail) still passes"
else
  no "(NT6) driver mutant could not be built (empty, identical or bash -n failed)"
fi
for old in 'a trail-less close-out at SYNC is an open follow-up' 'no requirement done stamp' 'the stamp now rides'; do
  grep -qF -- "$old" "$SKILL" && no "(NT6) stale SKILL sentence: $old" || ok "(NT6) SKILL no longer says: $old"
done
grep -q '^| `closeout` |.*<pr_url> \[--session-id <sid>\] \[--no-trail\]`' "$SKILL" && ok "(NT6) §1.5 closeout row documents --no-trail" || no "(NT6) §1.5 closeout row lacks --no-trail"
grep -qF 'it runs no `current-set` but `closeout <the lane'"'"'s run file> <item> <its ## Current pr> --no-trail` inside the lane' "$SKILL" \
  && ok "(NT6) §14 Terminal park names closeout --no-trail as the lane's stamp writer" || no "(NT6) §14 Terminal park sentence"
nt_help="$(bash "$H" --help)"
grep -q '^  closeout .*\[--no-trail\]' <<<"$nt_help" && ok "(NT6) --help closeout row documents --no-trail" || no "(NT6) --help closeout row"
grep -q '^  lane-convert-ready .*closeout --no-trail' <<<"$nt_help" && ok "(NT6) --help lane-convert-ready row names closeout --no-trail" || no "(NT6) --help lane-convert-ready row"
grep -qF 'closeout --no-trail' "$HERE/../commands/automate.md" && ok "(NT6) commands/automate.md SYNC points at closeout --no-trail" || no "(NT6) command SYNC pointer"

