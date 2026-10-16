# ---- AF: fleet-closeout — the stepwise, idempotent wave close (A2) -----------------------------------
# Two lanes; the owner merges L1's PR, then L2's. Real helpers / closeout / finalize / run-lock; gh is a
# stub keyed per PR (AF_MERGED / AF_CLOSED / AF_NOHEAD) that also answers the `ci` check-runs read.
cat > "$T/af-gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >> "$T_AFGH"
case "$1" in
  auth) exit 0 ;;
  pr) if [ "$2" = list ]; then   # the dry sweep's read: `pr list --state all --head <B> --json …`
        if [ -n "${AF_SWEPT_OID:-}" ] && [ "$6" = feature/af-swept ]; then
          printf '[{"number":7,"state":"MERGED","headRefOid":"%s","mergedAt":"2026-10-10T00:00:00Z"}]\n' "$AF_SWEPT_OID"
        else echo '[]'; fi
        exit 0
      fi
      [ "$2" = view ] || exit 1
      st=OPEN; case " ${AF_MERGED:-} " in *" $3 "*) st=MERGED ;; esac; case " ${AF_CLOSED:-} " in *" $3 "*) st=CLOSED ;; esac
      ma=null; [ "$st" = MERGED ] && ma='"2026-10-10T00:00:00Z"'
      n="${3##*/}"; oid="$(printf '%040d' "$n")"; case " ${AF_NOHEAD:-} " in *" $3 "*) oid="" ;; esac
      printf '{"state":"%s","mergedAt":%s,"headRefName":"feature/af%s","headRefOid":"%s"}\n' "$st" "$ma" "$n" "$oid" ;;
  api) case "$2" in
         */check-runs*) printf '{"check_runs":[{"name":"ci","conclusion":"%s","started_at":"2026-10-10T00:00:00Z"}]}\n' "${AF_CI:-success}" ;;
         *) exit 1 ;;
       esac ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$T/af-gh"; export T_AFGH="$T/af-gh.calls"; mkdir -p "$T/remote-af"
af() { REMOTE11="$T/remote-af" LOOMWRIGHT_LANES_META_SYNC="$T/meta-f11.sh" LOOMWRIGHT_LANES_HELPERS="$SC/automate-helpers.sh" \
  LOOMWRIGHT_LANES_TRAIL="$T/ab-spy.sh" LOOMWRIGHT_GH_BIN="$T/af-gh" bash "$S" "$@" 2>&1; }
PARENT10=automate-2026-10-10-120000; RF10="$P/.supervisor/automate/$PARENT10.md"; LR10="$T/work/primary-lanes/$PARENT10"
printf '# Automate Run: %s\n\n## Status: running\n\n## Run Config\n- parallel: 2\n\n## Queue\n- [ ] reqs/a.md\n- [ ] reqs/b.md\n\n## Current\n- item: null | status: null\n- wave: 1 | items: reqs/a.md, reqs/b.md\n\n## Progress\n' "$PARENT10" > "$RF10"
af lane-status "$RF10" --leaks --snapshot >/dev/null
bash "$HERE/run-lock.sh" acquire --owner "automate-lanes:$PARENT10" --root "$P" >/dev/null 2>&1
PR101="https://github.com/o/r/pull/101"; PR102="https://github.com/o/r/pull/102"
ae_lane "$RF10" "$LR10" 1 ".supervisor/requirements/t/af1.md" "$PR101" awaiting_merge; L101="$ABL"; RF101="$ABRF"
ae_lane "$RF10" "$LR10" 2 ".supervisor/requirements/t/af2.md" "$PR102" awaiting_merge reqs/b.md; L102="$ABL"
# a new commit on origin/main, so the primary sync has something to pull
git clone -q "$ORIGIN" "$T/af-other" 2>/dev/null; echo c > "$T/af-other/c.txt"; git -C "$T/af-other" add c.txt
git -C "$T/af-other" commit -qm c; git -C "$T/af-other" push -q origin main 2>/dev/null
out="$(AF_MERGED="$PR101" af fleet-closeout "$RF10")"; rc=$?
printf '%s\n' "$out" | sed 's/^/       | /'
check "AF1 first call (L1 merged, L2 open): exit 0" "$rc" 0
check "AF1b … step 1 pulled the metadata branch first" "$(printf '%s\n' "$out" | head -1)" "fleet-closeout: pull — pulled test-meta"
has "AF1c … L1 backstop: lane-convert-ready closed it out and finalized it" "$out" "fleet-closeout: backstop — L1 lane-convert-ready (exit 0) — lane-convert-ready: finalize — finalize-empty: finalized"
has "AF1d … L2 waits for its merge" "$out" "fleet-closeout: waiting — L2 awaiting_merge"
has "AF1e … L1 checked off in the parent Queue" "$out" "fleet-closeout: check-off — L1 reqs/a.md"
check "AF1f parent Queue: reqs/a.md checked, reqs/b.md not" "$(grep -c '^- \[x\] reqs/a.md$' "$RF10" | tr -d ' '):$(grep -c '^- \[ \] reqs/b.md$' "$RF10" | tr -d ' ')" "1:1"
check "AF1g one parent Progress line for it, naming the PR" "$(grep -cxF -- "- fleet closeout: L1 reqs/a.md done (PR $PR101)" "$RF10" | tr -d ' ')" 1
has "AF1h step 4 pulled the primary onto origin/main" "$out" "fleet-closeout: sync — pulled main"
check "AF1i … the primary now has the new commit" "$(git -C "$P" rev-parse HEAD)" "$(git -C "$T/af-other" rev-parse HEAD)"
has "AF1j step 5 removed L1" "$out" "fleet-closeout: remove — L1 removed"
check "AF1k … L1 gone, L2 still there" "$([ -d "$L101" ] && echo kept || echo removed):$([ -d "$L102" ] && echo kept || echo removed)" "removed:kept"
check "AF1l step 6 waits on L2 (last line), lock still held" \
  "$(printf '%s\n' "$out" | tail -n1):$(bash "$HERE/run-lock.sh" status --root "$P" | cut -c1-6)" \
  "fleet-closeout: waiting — lane(s) not removed yet: L2 (re-run fleet-closeout on the next --resume):LOCKED"
hasnt "AF1m … no wave-end step ran" "$out" "lanes-dir"
SRF10="$(cksum < "$RF10")"
out="$(AF_MERGED="$PR101" af fleet-closeout "$RF10")"; rc=$?
check "AF2 a re-run with nothing new is idempotent (exit 0, parent run file byte-unchanged)" "$rc:$(cksum < "$RF10")" "0:$SRF10"
has "AF2b … it reads L1 removed" "$out" "fleet-closeout: lane — L1 removed"
has "AF2c … and the primary already synced" "$out" "fleet-closeout: sync — skipped — already synced (main at origin/main)"
# AF2d a closed-out lane whose removal is refused waits (never --stop, never an in-session wait)
echo junk > "$L102/junk.txt"
out="$(AF_MERGED="$PR101 $PR102" af fleet-closeout "$RF10")"; rc=$?
check "AF2d the owner merged L2 but its lane is dirty: closed out + checked off, removal waits (exit 0)" \
  "$rc:$(printf '%s\n' "$out" | grep -cxF 'fleet-closeout: waiting — L2 dirty working tree' | tr -d ' '):$([ -d "$L102" ] && echo kept)" "0:1:kept"
check "AF2e … and the wave end waits on it" "$(printf '%s\n' "$out" | tail -n1)" \
  "fleet-closeout: waiting — lane(s) not removed yet: L2 (re-run fleet-closeout on the next --resume)"
rm -f "$L102/junk.txt"
# a local branch in the primary whose newest PR merged at its tip — the dry sweep's would-remove candidate
git -C "$P" branch feature/af-swept 2>/dev/null; AFSW_OID="$(git -C "$P" rev-parse feature/af-swept)"
out="$(AF_SWEPT_OID="$AFSW_OID" AF_MERGED="$PR101 $PR102" AF_CI=failure af fleet-closeout "$RF10")"; rc=$?
printf '%s\n' "$out" | sed 's/^/       | /'
check "AF3 the next call removes it: exit 0" "$rc" 0
has "AF3b … L2 closed out, checked off and removed" "$out" "fleet-closeout: remove — L2 removed"
check "AF3c parent Queue fully checked off" "$(grep -c '^- \[ \] ' "$RF10" | tr -d ' ')" 0
has "AF3d the lanes dir is kept, naming its contents (salvage + logs kept by design)" "$out" "fleet-closeout: lanes-dir — kept $LR10 — contents: "
has "AF3e … salvage among them" "$(printf '%s\n' "$out" | grep 'lanes-dir — kept')" "salvage"
has "AF3f leaks vs the wave-start snapshot: none" "$out" "fleet-closeout: leaks — leaks: none (vs snapshot <primary>/.supervisor/automate/$PARENT10.leaks-snapshot)"
check "AF3g … its first line is in the parent Progress, with no absolute path" \
  "$(grep -c '^- fleet closeout leaks: leaks: none' "$RF10" | tr -d ' '):$(grep -c "$P" "$RF10" | tr -d ' ')" "1:0"
has "AF3h the wave end runs a DRY sweep of the primary: its summary line is printed" "$out" "fleet-closeout: sweep — sweep: summary — dry run: 1 would-remove, "
check "AF3h2 … appended once to the parent Progress, and the dry run removed nothing" \
  "$(grep -c '^- fleet closeout sweep (dry run): sweep: summary — dry run: 1 would-remove, ' "$RF10" | tr -d ' '):$(git -C "$P" rev-parse -q --verify refs/heads/feature/af-swept)" "1:$AFSW_OID"
MSHA="$(git -C "$P" rev-parse origin/main)"
has "AF3i main health: a red ci check on origin/main HEAD pauses the wave (printed)" "$out" "fleet-closeout: wave_paused: main_red after $MSHA"
check "AF3j … and appended once to the parent Progress (no revert, no block)" "$(grep -cxF -- "- wave_paused: main_red after $MSHA" "$RF10" | tr -d ' ')" 1
check "AF3k the Queue is empty ⇒ the wave lock is released (last line)" \
  "$(printf '%s\n' "$out" | tail -n1):$(bash "$HERE/run-lock.sh" status --root "$P")" "fleet-closeout: wave closed — lock released:UNLOCKED"
check "AF3l the gh calls were reads only (pr view / the sweep's pr list / the check-runs api)" "$(grep -vE '^gh (pr view|pr list --state all --head [^ ]+ --json number,state,headRefOid,mergedAt$|api repos/\{owner\}/\{repo\}/commits/[0-9a-f]+/check-runs\?check_name=ci|auth status)' "$T_AFGH" | wc -l | tr -d ' ')" 0
# AF3m-r the Queue emptied ⇒ the PARENT is finalized as §6 "Termination" ends a sequential run (W3 left
# it `## Status: running` with its wave line, and the coordinator hand-wrote done + its trail)
check "AF3m the parent run file reads ## Status: done (no running left)" \
  "$(grep -c '^## Status: done$' "$RF10" | tr -d ' '):$(grep -c '^## Status: running' "$RF10" | tr -d ' ')" "1:0"
check "AF3n … ## Current carries pause_reason: null and no wave line" \
  "$(awk '/^## Current/ { c = 1; next } /^## / { c = 0 } c' "$RF10" | grep -cxF -- '- pause_reason: null' | tr -d ' '):$(grep -c '^- wave:' "$RF10" | tr -d ' ')" "1:0"
check "AF3o … ONE finalize Progress line" "$(grep -cE '^- [0-9TZ:-]+ wave closed — Queue empty, run finalized$' "$RF10" | tr -d ' ')" 1
check "AF3p … trail-pr --reason done ran ONCE on the parent (through the trail seam), its line printed and appended" \
  "$(grep -cxF -- "trail-pr $RF10 --reason done" "$T_ABSPY" | tr -d ' '):$(printf '%s\n' "$out" | grep -cxF 'fleet-closeout: finalize — trail-pr: meta-pushed test-meta' | tr -d ' '):$(grep -cE '^- [0-9TZ:-]+ trail-pr: meta-pushed test-meta$' "$RF10" | tr -d ' ')" "1:1:1"
check "AF3q … the finalize ran BEFORE the release (under the wave lock), and branch mode on ⇒ no trail-unstage" \
  "$(printf '%s\n' "$out" | tail -n3 | head -1):$(grep -c "^trail-unstage $RF10" "$T_ABSPY" | tr -d ' ')" \
  "fleet-closeout: finalize — finalized (## Status: done, pause_reason: null, wave line cleared):0"
check "AF3r … the pushed parent run file carries ## Status: done (the trail ran after the write)" \
  "$(grep -c '^## Status: done$' "$T/remote-af/.supervisor/automate/$PARENT10.md" 2>/dev/null | tr -d ' ')" 1
SRF10="$(cksum < "$RF10")"
out="$(AF_MERGED="$PR101 $PR102" AF_CI=failure af fleet-closeout "$RF10")"; rc=$?
check "AF4 a re-run after the close: exit 0, the parent run file byte-unchanged (no duplicate lines)" "$rc:$(cksum < "$RF10")" "0:$SRF10"
check "AF4b … still ends wave closed (release is idempotent)" "$(printf '%s\n' "$out" | tail -n1)" "fleet-closeout: wave closed — lock released"
check "AF4d … the finalize is skipped (already done) and no second trail-pr runs" \
  "$(printf '%s\n' "$out" | grep -cxF 'fleet-closeout: finalize — skipped (already done)' | tr -d ' '):$(grep -cxF -- "trail-pr $RF10 --reason done" "$T_ABSPY" | tr -d ' ')" "1:1"
SRF10="$(cksum < "$RF10")"
out="$(LOOMWRIGHT_LANES_SWEEP="$T/no-such-sweep.sh" AF_MERGED="$PR101 $PR102" af fleet-closeout "$RF10")"; rc=$?
check "AF4f a failed sweep is reported, never an exit change, and its line is not appended twice" \
  "$rc:$(printf '%s\n' "$out" | grep -cxF 'fleet-closeout: sweep — sweep: summary — skipped: no summary line (sweep failed or printed nothing)' | tr -d ' '):$(cksum < "$RF10")" "0:1:$SRF10"
# AF4c the next wave's item is still unchecked ⇒ the lock is kept (the next wave runs under it)
printf '%s\n' "- [ ] reqs/next.md" > "$T/af.q"; awk -v f="$T/af.q" '{ print } /^## Queue$/ { while ((getline l < f) > 0) print l }' "$RF10" > "$T/af.rf" && mv "$T/af.rf" "$RF10"
bash "$HERE/run-lock.sh" acquire --owner "automate-lanes:$PARENT10" --root "$P" >/dev/null 2>&1
out="$(AF_MERGED="$PR101 $PR102" af fleet-closeout "$RF10")"
check "AF4c a Queue item left for the next wave keeps the wave lock" \
  "$(printf '%s\n' "$out" | tail -n1):$(bash "$HERE/run-lock.sh" status --root "$P" | cut -c1-6)" \
  "fleet-closeout: lock kept — 1 Queue item(s) remain unchecked (the next wave runs under it):LOCKED"
hasnt "AF4e … and no finalize runs while a Queue item remains" "$out" "finalize"
bash "$HERE/run-lock.sh" release --owner "automate-lanes:$PARENT10" --root "$P" >/dev/null 2>&1
# human cases + the pull failure, on a fresh one-lane parent
PARENT11=automate-2026-10-10-130000; RF11="$P/.supervisor/automate/$PARENT11.md"; LR11="$T/work/primary-lanes/$PARENT11"
printf '# Automate Run: %s\n\n## Queue\n- [ ] reqs/a.md\n\n## Progress\n' "$PARENT11" > "$RF11"
PR111="https://github.com/o/r/pull/111"
ae_lane "$RF11" "$LR11" 1 ".supervisor/requirements/t/af11.md" "$PR111" awaiting_merge; L111="$ABL"
out="$(AF_CLOSED="$PR111" af fleet-closeout "$RF11")"; rc=$?
has "AF5 a gone lane (PR closed unmerged) is the human's: never auto-abandoned" "$out" "fleet-closeout: human — L1 gone (PR closed unmerged): lane-remove $L111 --abandon"
check "AF5b … the lane is kept and its run file untouched" "$rc:$([ -d "$L111" ] && echo kept):$(grep -c '^## Status: paused' "$L111/.supervisor/automate/$PARENT11-L1.md" | tr -d ' ')" "0:kept:1"
echo "push_failed — rejected 5 times" > "$L111/.supervisor/automate/$PARENT11-L1.meta-push-failed"
out="$(AF_MERGED="$PR111" af fleet-closeout "$RF11")"
has "AF6 a meta-push-failed marker is the human's (no backstop runs)" "$out" "fleet-closeout: human — L1 meta-push-failed: push_failed — rejected 5 times"
hasnt "AF6b … no backstop" "$out" "backstop"
rm -f "$L111/.supervisor/automate/$PARENT11-L1.meta-push-failed"
S11="$(cksum < "$RF11")"
out="$(STUB_META_FAIL=1 AF_MERGED="$PR111" REMOTE11="$T/remote-af" LOOMWRIGHT_LANES_META_SYNC="$T/meta-sync.sh" LOOMWRIGHT_LANES_HELPERS="$SC/automate-helpers.sh" \
  LOOMWRIGHT_LANES_TRAIL="$T/ab-spy.sh" LOOMWRIGHT_GH_BIN="$T/af-gh" bash "$S" fleet-closeout "$RF11" 2>&1)"; rc=$?
check "AF7 a failed metadata pull: exit 2, ONE line, nothing else runs" "$rc:$(printf '%s\n' "$out" | wc -l | tr -d ' '):$out" \
  "2:1:fleet-closeout: pull FAILED — (meta-sync exit 1)"
check "AF7b … the parent run file and the lane are untouched" "$(cksum < "$RF11"):$([ -d "$L111" ] && echo kept)" "$S11:kept"
out="$(af fleet-closeout "$T/nowhere/x.md")"; rc=$?
check "AF8 a bad parent run file is refused (exit 1)" "$rc:$(printf '%s' "$out" | grep -c '^fleet-closeout: refused — ' | tr -d ' ')" "1:1"
printf '# Automate Run: automate-2026-10-10-140000\n\n## Progress\n' > "$P/.supervisor/automate/automate-2026-10-10-140000.md"
check "AF9 no lane table ⇒ one skipped line, exit 0" "$(af fleet-closeout "$P/.supervisor/automate/automate-2026-10-10-140000.md"; echo "rc=$?")" \
  "fleet-closeout: skipped — no lane table (automate-2026-10-10-140000.lanes): no lane to close out
rc=0"

# AF10-AF13 the parent finalize's edges, on a parent whose only lane is already removed (the table row
# reads `removed`), so a call goes straight to the wave end. A helpers wrapper in front of the real copy
# can refuse runfile-write (FC_REFUSE); mode off runs through the no-op trail stub (records its calls).
cat > "$T/fc-helpers.sh" <<EOF
#!/usr/bin/env bash
if [ "\$1" = runfile-write ] && [ -n "\${FC_REFUSE:-}" ]; then echo "runfile-write: refused — forced by the test [runfile_write_refused]" >&2; exit 1; fi
exec bash "$SC/automate-helpers.sh" "\$@"
EOF
chmod +x "$T/fc-helpers.sh"
fc_parent() { # <parent_id> — a running parent with an empty Queue, a wave line and one removed lane
  FCRF="$P/.supervisor/automate/$1.md"
  printf '# Automate Run: %s\n\n## Status: running\n\n## Run Config\n- parallel: 2\n\n## Queue\n- [x] reqs/a.md\n\n## Current\n- item: null | status: null\n- wave: 1 | items: reqs/a.md\n\n## Progress\n' "$1" > "$FCRF"
  printf 'L1\t%s\treqs/a.md\t%s-L1\t-\t-\t-\tremoved\t-\t-\n' "$T/work/primary-lanes/$1/L1" "$1" > "$P/.supervisor/automate/$1.lanes"
  bash "$HERE/run-lock.sh" acquire --owner "automate-lanes:$1" --root "$P" >/dev/null 2>&1
}
fc() { REMOTE11="$T/remote-af" LOOMWRIGHT_LANES_META_SYNC="$T/meta-f11.sh" LOOMWRIGHT_LANES_HELPERS="$T/fc-helpers.sh" \
  LOOMWRIGHT_LANES_TRAIL="${FC_TRAIL:-$T/ab-spy.sh}" LOOMWRIGHT_GH_BIN="$T/af-gh" bash "${FC_S:-$S}" "$@" 2>&1; }
lockst() { bash "$HERE/run-lock.sh" status --root "$P" | cut -c1-6; }
fc_parent automate-2026-10-11-100000; RF13="$FCRF"
out="$(FC_REFUSE=1 fc fleet-closeout "$RF13")"; rc=$?
check "AF10 a refused runfile-write ⇒ finalize FAILED naming why, exit unchanged (0)" \
  "$rc:$(printf '%s\n' "$out" | grep -c '^fleet-closeout: finalize FAILED — runfile-write: refused — forced by the test' | tr -d ' ')" "0:1"
check "AF10b … the finalize wrote nothing (still running, wave line kept, no finalize line; no stray staging file) and no trail-pr ran" \
  "$(grep -c '^## Status: running$' "$RF13" | tr -d ' '):$(grep -c '^- wave: 1' "$RF13" | tr -d ' '):$(grep -c 'run finalized' "$RF13" | tr -d ' '):$(ls "$P/.supervisor/automate/" | grep -c 'automate-2026-10-11-100000\.md\.' | tr -d ' '):$(grep -c "^trail-pr $RF13" "$T_ABSPY" | tr -d ' ')" "1:1:0:0:0"
check "AF10c … and the wave lock is STILL released (never stranded)" \
  "$(printf '%s\n' "$out" | tail -n1):$(lockst)" "fleet-closeout: wave closed — lock released:UNLOCK"
out="$(fc fleet-closeout "$RF13")"; rc=$?
check "AF10d the next call (lock already free: taken for the write) finalizes it: done, wave line gone, lock released" \
  "$rc:$(grep -c '^## Status: done$' "$RF13" | tr -d ' '):$(grep -c '^- wave:' "$RF13" | tr -d ' '):$(lockst)" "0:1:0:UNLOCK"
fc_parent automate-2026-10-11-110000; RF14="$FCRF"; : > "$T_TRAIL_LOG"
out="$(STUB_MODE_LINE=off FC_TRAIL="$T/trail-stub.sh" fc fleet-closeout "$RF14")"; rc=$?
check "AF11 branch mode OFF: finalized, trail-pr --reason done then trail-unstage, in that order" \
  "$rc:$(grep -c '^## Status: done$' "$RF14" | tr -d ' '):$(cat "$T_TRAIL_LOG" | tr '\n' '|')" \
  "0:1:trail trail-pr $RF14 --reason done|trail trail-unstage $RF14|"
has "AF11b … each printed as a finalize line" "$out" "fleet-closeout: finalize — trail-pr: skipped — meta no_changes"
# AF14 a TWO-wave run: each wave end prints its own dry sweep, but the parent Progress records the
# sweep ONLY at the parent finalize — so the one line at `## Status: done` is the FINAL wave's summary,
# never a frozen wave-1 snapshot (af/39a review). A stub sweep prints a per-call summary.
cat > "$T/sw-stub.sh" <<'EOF'
#!/usr/bin/env bash
echo "sweep: summary — dry run: ${SW_STUB_N:-0} would-remove, 0 kept (0 worktree(s), ${SW_STUB_N:-0} branch(es) examined)"
EOF
chmod +x "$T/sw-stub.sh"
fc_parent automate-2026-10-11-140000; RF17="$FCRF"
printf '%s\n' "- [ ] reqs/b.md" > "$T/af.q"; awk -v f="$T/af.q" '{ print } /^## Queue$/ { while ((getline l < f) > 0) print l }' "$RF17" > "$T/af.rf" && mv "$T/af.rf" "$RF17"
out="$(SW_STUB_N=1 LOOMWRIGHT_LANES_SWEEP="$T/sw-stub.sh" fc fleet-closeout "$RF17")"
check "AF14 wave 1 (a Queue item remains): its sweep is printed, NOT recorded, and the lock is kept" \
  "$(printf '%s\n' "$out" | grep -cxF 'fleet-closeout: sweep — sweep: summary — dry run: 1 would-remove, 0 kept (0 worktree(s), 1 branch(es) examined)' | tr -d ' '):$(grep -c '^- fleet closeout sweep (dry run): ' "$RF17" | tr -d ' '):$(lockst)" "1:0:LOCKED"
sed 's/^- \[ \] reqs\/b.md$/- [x] reqs\/b.md/' "$RF17" > "$T/af.rf" && mv "$T/af.rf" "$RF17"
out="$(SW_STUB_N=2 LOOMWRIGHT_LANES_SWEEP="$T/sw-stub.sh" fc fleet-closeout "$RF17")"
check "AF14b wave 2 finalizes: exactly ONE recorded sweep line, and it is the final wave's summary" \
  "$(grep -c '^## Status: done$' "$RF17" | tr -d ' '):$(grep -c '^- fleet closeout sweep (dry run): ' "$RF17" | tr -d ' '):$(grep -cxF -- '- fleet closeout sweep (dry run): sweep: summary — dry run: 2 would-remove, 0 kept (0 worktree(s), 2 branch(es) examined)' "$RF17" | tr -d ' ')" "1:1:1"
af14_fin="$(grep -n 'wave closed — Queue empty, run finalized$' "$RF17" | head -n1 | cut -d: -f1)"
af14_sw="$(grep -n '^- fleet closeout sweep (dry run): ' "$RF17" | head -n1 | cut -d: -f1)"
check "AF14c … recorded by the finalize, after its finalized line, as the run file's last line" \
  "$([ -n "$af14_fin" ] && [ -n "$af14_sw" ] && [ "$af14_sw" -gt "$af14_fin" ] && echo after):$(tail -n1 "$RF17" | cut -c1-34)" \
  "after:- fleet closeout sweep (dry run): "
out="$(SW_STUB_N=3 LOOMWRIGHT_LANES_SWEEP="$T/sw-stub.sh" fc fleet-closeout "$RF17")"
check "AF14d a re-run on the done parent records no second sweep line" "$(grep -c '^- fleet closeout sweep (dry run): ' "$RF17" | tr -d ' ')" "1"
# AF13 the run lock held by ANOTHER owner ⇒ nothing written under it, and it is never stolen
fc_parent automate-2026-10-11-130000; RF16="$FCRF"
bash "$HERE/run-lock.sh" release --owner "automate-lanes:automate-2026-10-11-130000" --root "$P" >/dev/null 2>&1
bash "$HERE/run-lock.sh" acquire --owner "automate-pick:someone-else" --root "$P" >/dev/null 2>&1
out="$(fc fleet-closeout "$RF16")"; rc=$?
check "AF13 a foreign run lock ⇒ finalize FAILED naming its holder, parent still running, the lock still theirs" \
  "$rc:$(printf '%s\n' "$out" | grep -cxF 'fleet-closeout: finalize FAILED — the run lock is held by automate-pick:someone-else, not automate-lanes:automate-2026-10-11-130000 (nothing written)' | tr -d ' '):$(grep -c '^## Status: running$' "$RF16" | tr -d ' '):$(bash "$HERE/run-lock.sh" status --root "$P" | cut -d' ' -f1-2)" \
  "0:1:1:LOCKED owner=automate-pick:someone-else"
bash "$HERE/run-lock.sh" release --owner "automate-pick:someone-else" --root "$P" >/dev/null 2>&1
# AF12 mutation control: with the finalize call deleted, the Queue-empty close leaves the parent running
mkdir -p "$MUT"; FCM="$SC/automate-lanes-nofinalize.sh"
awk '!/^  _lanes_fc_finalize "\$rf" "\$primary" "\$mb" "\$sw"$/' "$SB" > "$FCM"
fc_parent automate-2026-10-11-120000; RF15="$FCRF"
if ! cmp -s "$SB" "$FCM" && bash -n "$FCM"; then
  out="$(FC_S="$FCM" fc fleet-closeout "$RF15")"
  check "AF12 mutation (finalize call deleted) fails the done assertion — the parent stays running" \
    "$(grep -c '^## Status: done$' "$RF15" | tr -d ' '):$(grep -c '^## Status: running$' "$RF15" | tr -d ' '):$(printf '%s\n' "$out" | tail -n1)" \
    "0:1:fleet-closeout: wave closed — lock released"
else bad "AF12 mutation control not built"; fi
rm -f "$FCM"

# ---- SL: single-lane mode `--parallel 1` (twin-remediation/08b) ---------------------------------------
# lane.json marker (FIRST leg: the requirement's mutation control) · lane-park seam · fresh lane numbers
# (1..99, never reused) · whole-run token ceiling · lane-remove / fleet-closeout tokens line · drain guard
# (lane-drain-check) · current-set's single_lane refusal · the merge watcher outlives its launcher (AC 8).
cat > "$T/sl-ledger.sh" <<'EOF'
#!/usr/bin/env bash
root=""; prev=""; for a in "$@"; do [ "$prev" = --root ] && root="$a"; prev="$a"; done
f="$root/.supervisor/sl-tokens"
if [ -f "$f" ]; then echo "INPUT=0 OUTPUT=0 CACHE_READ=0 CACHE_CREATE=0 TOTAL=$(cat "$f") EVENTS=1"
else echo "INPUT=0 OUTPUT=0 CACHE_READ=0 CACHE_CREATE=0 TOTAL=0 EVENTS=0 LEDGER_UNREADABLE=1"; fi
EOF
chmod +x "$T/sl-ledger.sh"
sl() { LOOMWRIGHT_LANES_TOKEN_LEDGER="$T/sl-ledger.sh" LOOMWRIGHT_LANES_HELPERS="$SC/automate-helpers.sh" bash "$S" "$@" 2>&1; }
sl_parent() { # <parent_id> <N> — a running parent run file with `- parallel: <N>` and the two items queued
  printf '# Automate Run: %s\n\n## Status: running\n\n## Run Config\n- parallel: %s\n\n## Queue\n- [ ] reqs/a.md\n- [ ] reqs/b.md\n\n## Current\n- item: null | status: null\n- pause_reason: null\n\n## Progress\n- 2026-10-14T00:00:00Z run created\n' "$1" "$2" > "$P/.supervisor/automate/$1.md"
}
PARS=automate-2026-10-14-120000; RFS="$P/.supervisor/automate/$PARS.md"; LRS="$T/work/primary-lanes/$PARS"; TBS="$P/.supervisor/automate/$PARS.lanes"
PARN=automate-2026-10-14-130000; RFN="$P/.supervisor/automate/$PARN.md"; LRN="$T/work/primary-lanes/$PARN"
sl_parent "$PARS" 1; sl_parent "$PARN" 2
SL_KEYS='["schema_version","lane","run_id","parent_run_id","primary","parallel","max_tokens","created","policy"]'
# SL1 (FIRST LEG — the requirement's mutation control): an explicit --parallel 1 writes single_lane: true
out="$(sl lane-create "$RFS" reqs/a.md 1 --parallel 1)"; rc=$?
check "SL1 lane-create --parallel 1 ⇒ exit 0 and lane.json carries single_lane: true" "$rc:$(jq -c '.single_lane' "$LRS/L1/.supervisor/lane.json")" "0:true"
check "SL1b … appended LAST — every other key in today's order" "$(jq -c 'keys_unsorted' "$LRS/L1/.supervisor/lane.json")" \
  "${SL_KEYS%]},\"single_lane\"]"
check "SL1c lane-park --root <single lane> ⇒ awaiting_merge (exit 0)" "$(sl lane-park --root "$LRS/L1"; echo "rc=$?")" "awaiting_merge
rc=0"
# SL2 no --parallel (par defaults to n, here 1) and --parallel 2 ⇒ NO key; lane-park ⇒ ready_for_release
sl lane-create "$RFN" reqs/a.md 1 >/dev/null; sl lane-create "$RFN" reqs/b.md 2 --parallel 2 >/dev/null
check "SL2 lane-create without --parallel (n = 1 ⇒ parallel 1) ⇒ no single_lane key, today's keys and order" \
  "$(jq -c 'keys_unsorted' "$LRN/L1/.supervisor/lane.json"):$(jq -c '.parallel' "$LRN/L1/.supervisor/lane.json")" "$SL_KEYS:1"
check "SL2b lane-create --parallel 2 ⇒ no single_lane key" "$(jq -c 'has("single_lane")' "$LRN/L2/.supervisor/lane.json")" false
check "SL2c lane-park on both ⇒ ready_for_release" "$(sl lane-park --root "$LRN/L1"):$(sl lane-park --root "$LRN/L2")" "ready_for_release:ready_for_release"
# SL3 lane-park edge cases: no lane.json (not a lane) ⇒ the sequential park; unreadable / not an object /
# single_lane false ⇒ ready_for_release (the park that arms no watcher)
mkdir -p "$T/park/none" "$T/park/bad/.supervisor" "$T/park/arr/.supervisor" "$T/park/false/.supervisor" "$T/park/empty/.supervisor"
printf '{"lane": "L1", ' > "$T/park/bad/.supervisor/lane.json"; printf '[{"single_lane": true}]\n' > "$T/park/arr/.supervisor/lane.json"
printf '{"schema_version": 1, "single_lane": false}\n' > "$T/park/false/.supervisor/lane.json"; : > "$T/park/empty/.supervisor/lane.json"
check "SL3 lane-park with NO lane.json (not a lane) ⇒ awaiting_merge" "$(sl lane-park --root "$T/park/none")" awaiting_merge
check "SL3b lane-park on a malformed lane.json ⇒ ready_for_release" "$(sl lane-park --root "$T/park/bad")" ready_for_release
check "SL3c … a JSON array, single_lane false, an empty file ⇒ ready_for_release" \
  "$(sl lane-park --root "$T/park/arr"):$(sl lane-park --root "$T/park/false"):$(sl lane-park --root "$T/park/empty")" "ready_for_release:ready_for_release:ready_for_release"
check "SL3d lane-park defaults to the current checkout's top level" "$(cd "$LRS/L1" && bash "$S" lane-park)" awaiting_merge
# SL4 fresh lane numbers: a number already in the table is refused, nothing created
SL_TB0="$(cksum < "$TBS")"
out="$(bash "$S" lane-create "$RFS" reqs/b.md 1 --parallel 1 2>&1 >/dev/null)"; rc=$?
check "SL4 L1 reused under --parallel 1 ⇒ refused on stderr, exit 1" "$rc:$out" \
  "1:lane-create: refused — lane L1 already used in this run (single-lane takes a fresh number)"
check "SL4b … nothing created (table byte-unchanged, no salvage, L1 untouched)" \
  "$(cksum < "$TBS"):$([ -e "$LRS/salvage" ] && echo salvage || echo none):$(cat "$LRS/L1/.supervisor/lane-backlog.md")" "$SL_TB0:none:- [ ] reqs/a.md"
# SL5 lane numbers 1..99 under --parallel 1 only
out="$(sl lane-create "$RFS" reqs/b.md 11 --parallel 1)"; rc=$?
check "SL5 lane number 11 accepted under --parallel 1" "$rc:$([ -d "$LRS/L11" ] && echo created):$(jq -r .run_id "$LRS/L11/.supervisor/lane.json")" "0:created:$PARS-L11"
out="$(sl lane-create "$RFN" reqs/b.md 11)"; rc=$?
check "SL5b … still refused without it (1..10)" "$rc:$([ -e "$LRN/L11" ] && echo created || echo none)" "1:none"
has "SL5c … naming the bound" "$out" "lane number must be 1..10 (got '11')"
out="$(sl lane-create "$RFS" reqs/b.md 100 --parallel 1)"; check "SL5d 100 refused even under --parallel 1" "$?" 1
# SL6 whole-run token ceiling: SPENT = live lanes' ledger TOTAL + removed lanes' parent tokens lines
echo 300 > "$LRS/L1/.supervisor/sl-tokens"; echo 200 > "$LRS/L11/.supervisor/sl-tokens"
printf 'L5\t%s\treqs/z.md\t%s-L5\t-\t-\t-\tremoved\t-\t-\n' "$LRS/L5" "$PARS" >> "$TBS"   # a removed lane, directory gone
out="$(sl lane-create "$RFS" reqs/b.md 12 --parallel 1 --max-tokens 1000)"; rc=$?
check "SL6 a gone lane with no tokens line ⇒ refused token_ceiling ledger_unreadable, nothing created" \
  "$rc:$(printf '%s\n' "$out" | tail -n1):$([ -e "$LRS/L12" ] && echo created || echo none)" "1:lane-create: refused — token_ceiling ledger_unreadable:none"
bash "$SC/automate-helpers.sh" progress-append "$RFS" "fleet closeout: L5 tokens TOTAL=100" >/dev/null 2>&1
out="$(sl lane-create "$RFS" reqs/b.md 12 --parallel 1 --max-tokens 600)"; rc=$?
check "SL6b SPENT (300 + 200 + gone 100) ≥ T ⇒ refused token_ceiling total=600 max=600, nothing created" \
  "$rc:$(printf '%s\n' "$out" | tail -n1):$([ -e "$LRS/L12" ] && echo created || echo none)" "1:lane-create: refused — token_ceiling total=600 max=600:none"
out="$(sl lane-create "$RFS" reqs/b.md 12 --parallel 1 --max-tokens 1000)"; rc=$?
check "SL6c SPENT < T ⇒ lane.json max_tokens = T − SPENT (1000 − 600), not T / parallel" "$rc:$(jq -c .max_tokens "$LRS/L12/.supervisor/lane.json")" "0:400"
echo 50 > "$LRS/L12/.supervisor/sl-tokens"; rm -f "$LRS/L11/.supervisor/sl-tokens"
out="$(sl lane-create "$RFS" reqs/b.md 13 --parallel 1 --max-tokens 5000)"; rc=$?
check "SL6d a live lane whose reader says LEDGER_UNREADABLE ⇒ refused token_ceiling ledger_unreadable" \
  "$rc:$(printf '%s\n' "$out" | tail -n1)" "1:lane-create: refused — token_ceiling ledger_unreadable"
echo 200 > "$LRS/L11/.supervisor/sl-tokens"
# SL7 lane-remove (plain AND --abandon) on a single-lane parent writes the tokens line before deleting
out="$(sl lane-remove "$LRS/L12")"; rc=$?
check "SL7 plain lane-remove on a single-lane parent: removed, ONE tokens line with the lane's TOTAL" \
  "$rc:$([ -d "$LRS/L12" ] && echo kept || echo removed):$(grep -cxF -- '- fleet closeout: L12 tokens TOTAL=50' "$RFS" | tr -d ' ')" "0:removed:1"
out="$(sl lane-remove "$LRS/L11" --abandon)"; rc=$?
check "SL7b lane-remove --abandon: removed, tokens line written before the abandon line" \
  "$rc:$([ -d "$LRS/L11" ] && echo kept || echo removed):$(awk '/^- fleet closeout: L11 tokens TOTAL=200$/ { t = NR } /^- lane abandoned: L11 / { a = NR } END { print (t && a && t < a) }' "$RFS")" "0:removed:1"
out="$(sl lane-create "$RFS" reqs/b.md 13 --parallel 1 --max-tokens 1000)"; rc=$?
check "SL7c … so the next lane-create still reads SPENT (300 + 100 + 50 + 200 = 650 ⇒ max_tokens 350)" "$rc:$(jq -c .max_tokens "$LRS/L13/.supervisor/lane.json" 2>/dev/null)" "0:350"
bash "$SC/automate-helpers.sh" progress-append "$RFS" "fleet closeout: L13 tokens TOTAL=7" >/dev/null 2>&1
out="$(sl lane-remove "$LRS/L13")"
check "SL7d a lane that already has its tokens line gets no second one" "$(grep -c '^- fleet closeout: L13 tokens TOTAL=' "$RFS" | tr -d ' ')" 1
out="$(sl lane-remove "$LRN/L2")"; rc=$?
check "SL7e lane-remove on an N>1 parent's lane writes NO tokens line" "$rc:$(grep -c 'tokens TOTAL=' "$RFN" | tr -d ' ')" "0:0"
# SL7f/g the tokens line is read after one OPTIONAL timestamp token (the run file's own convention), by
# both readers: the whole-run SPENT sum and lane-remove's "already has its line" skip
printf 'L7\t%s\treqs/y.md\t%s-L7\t-\t-\t-\tremoved\t-\t-\n' "$LRS/L7" "$PARS" >> "$TBS"   # a gone lane, timestamped line
bash "$SC/automate-helpers.sh" progress-append "$RFS" "t9 fleet closeout: L7 tokens TOTAL=1000" >/dev/null 2>&1
out="$(sl lane-create "$RFS" reqs/b.md 14 --parallel 1 --max-tokens 2000)"; rc=$?
check "SL7f a timestamped tokens line counts toward SPENT (300+100+50+200+7+1000 = 1657 ⇒ max_tokens 343)" \
  "$rc:$(jq -c .max_tokens "$LRS/L14/.supervisor/lane.json" 2>/dev/null)" "0:343"
bash "$SC/automate-helpers.sh" progress-append "$RFS" "t9 fleet closeout: L14 tokens TOTAL=3" >/dev/null 2>&1
out="$(sl lane-remove "$LRS/L14")"; rc=$?
check "SL7g a lane whose tokens line is timestamped gets no second one" "$rc:$(grep -c 'fleet closeout: L14 tokens TOTAL=' "$RFS" | tr -d ' ')" "0:1"
# SL8 lane-drain-check: markers, not prose — dispatch marker / owned-drain count after the LAST picked / config backup
SLD="$LRS/L1"; SLDR="$SLD/.supervisor/automate/$PARS-L1.md"; SLPR="https://github.com/o/r/pull/881"
sl_drf() { # <progress lines…> — the lane run file at its park with these ## Progress lines
  { printf '# Automate Run: %s-L1 — reqs/a.md\n\n## Status: paused\n\n## Queue\n- [ ] reqs/a.md\n\n## Current\n- item: reqs/a.md | status: awaiting_merge | pr: %s | branch: feature/sl\n- pause_reason: awaiting_merge\n\n## Progress\n' "$PARS" "$SLPR"
    for l in "$@"; do printf -- '- %s\n' "$l"; done; } > "$SLDR"
}
sl_drf "t0 picked reqs/z.md" "t1 owned drain started — /review-pr x --until-mergeable @ aaa" "t2 picked reqs/a.md" "t3 owned drain started — /review-pr y --until-mergeable @ bbb" "t4 drain READY"
check "SL8 one owned drain after the LAST picked (an earlier item's drain before it) ⇒ ok" "$(sl lane-drain-check "$SLD")" \
  "drain-guard: ok — 1 owned drain(s), no dispatch marker, no config backup"
sl_drf "t2 picked reqs/a.md" "t3 owned drain started — a @ b" "t4 owned drain started — a @ c"
check "SL8b two plain owned drains after the last picked ⇒ violation" "$(sl lane-drain-check "$SLD")" \
  "drain-guard: violation — 2 owned drain(s) after the last picked line (exactly 1 expected)"
sl_drf "t2 picked reqs/a.md" "t3 owned drain started — a @ b" "t4 owned drain started (fix-now re-drain) — a @ c"
check "SL8c one plain + one fix-now re-drain ⇒ ok (the forms are counted apart)" "$(sl lane-drain-check "$SLD")" \
  "drain-guard: ok — 2 owned drain(s), no dispatch marker, no config backup"
sl_drf "t2 picked reqs/a.md" "t3 owned drain started — a @ b" "t4 owned drain started (fix-now re-drain) — a @ c" "t5 owned drain started (fix-now re-drain) — a @ d"
has "SL8d two fix-now re-drains ⇒ violation" "$(sl lane-drain-check "$SLD")" "drain-guard: violation — 2 fix-now re-drains after the last picked line (at most 1)"
sl_drf "t2 picked reqs/a.md" "t4 drain READY"
has "SL8e no owned drain after the last picked ⇒ violation" "$(sl lane-drain-check "$SLD")" "drain-guard: violation — 0 owned drain(s) after the last picked line"
# SL8k-n the drain-start line is matched after one OPTIONAL timestamp token, colon form tolerated
sl_drf "t2 picked reqs/a.md" "t3 owned drain started: /review-pr x --until-mergeable @ b"
check "SL8k a colon-form drain start (legacy run files) ⇒ ok, 1 drain" "$(sl lane-drain-check "$SLD")" \
  "drain-guard: ok — 1 owned drain(s), no dispatch marker, no config backup"
sl_drf "picked reqs/a.md" "owned drain started — a @ b" "drain READY"
check "SL8l an untimestamped drain start is counted ⇒ ok, 1 drain" "$(sl lane-drain-check "$SLD")" \
  "drain-guard: ok — 1 owned drain(s), no dispatch marker, no config backup"
sl_drf "t2 picked reqs/a.md" "owned drain started — a @ b" "t4 owned drain started — a @ c"
check "SL8m one untimestamped + one timestamped plain drain ⇒ violation, 2 drains" "$(sl lane-drain-check "$SLD")" \
  "drain-guard: violation — 2 owned drain(s) after the last picked line (exactly 1 expected)"
sl_drf "t2 picked reqs/a.md" "t3 owned drain started: a @ b" "owned drain started (fix-now re-drain) — a @ c" "t5 owned drain started (fix-now re-drain) — a @ d"
check "SL8n fix-now re-drains still counted apart, timestamp optional (1 plain ok, 2 fix-now ⇒ violation)" "$(sl lane-drain-check "$SLD")" \
  "drain-guard: violation — 2 fix-now re-drains after the last picked line (at most 1)"
sl_drf "t2 picked reqs/a.md" "t3 owned drain started — a @ b"
# the marker is named by the DISPATCHER's own PR_HASH block (dispatch-pr-review.sh), run on the lane's PR URL
SL_HASHBLK="$(awk '/^PR_HASH=""$/ { on = 1 } on && /^MARKER=/ { exit } on' "$HERE/dispatch-pr-review.sh")"
SL_HASH="$(PR_URL="$SLPR" bash -c "$SL_HASHBLK"'
printf "%s" "$PR_HASH"')"
mkdir -p "$SLD/.supervisor/review-dispatch"; : > "$SLD/.supervisor/review-dispatch/$SL_HASH"
check "SL8f the dispatcher's marker for the lane PR (hash from dispatch-pr-review.sh's own block) ⇒ violation" \
  "$([ -n "$SL_HASHBLK" ] && echo blk):$(sl lane-drain-check "$SLD")" \
  "blk:drain-guard: violation — review-dispatch marker for $SLPR (a detached default drain was dispatched)"
rm -f "$SLD/.supervisor/review-dispatch/$SL_HASH"; : > "$SLD/.supervisor/review-dispatch/0123456789abcdef0123456789abcdef01234567"
: > "$SLD/.supervisor/automate/$PARS-L1.config-backup.json"
check "SL8g a config backup ⇒ violation (another PR's dispatch file is not this lane's marker)" "$(sl lane-drain-check "$SLD")" \
  "drain-guard: violation — config backup $PARS-L1.config-backup.json present (auto_review never restored)"
rm -f "$SLD/.supervisor/automate/$PARS-L1.config-backup.json"; rm -rf "$SLD/.supervisor/review-dispatch"
rm -f "$SLDR"
out="$(sl lane-drain-check "$SLD")"; rc=$?
check "SL8h an unreadable (absent) lane run file ⇒ unknown, exit 0 (fail SAFE, never ok)" "$rc:$out" "0:drain-guard: unknown — lane run file unreadable ($PARS-L1.md)"
check "SL8i not a lane ⇒ unknown" "$(sl lane-drain-check "$T/park/none")" "drain-guard: unknown — not a lane: $T/park/none"
sl_drf "t3 owned drain started — a @ b"
has "SL8j no picked line ⇒ unknown" "$(sl lane-drain-check "$SLD")" "drain-guard: unknown — no picked line"
rm -f "$SLDR"
# SL9 current-set refuses the ready_for_release park in a single_lane checkout (file byte-unchanged)
sl_crf() { printf '# Automate Run: %s\n\n## Status: running\n\n## Queue\n- [ ] reqs/a.md\n\n## Current\n- item: reqs/a.md | status: running | pr: null | branch: null\n- pause_reason: null\n\n## Progress\n- t0 picked reqs/a.md\n' "$2" > "$1"; }
SLC="$SLD/.supervisor/automate/$PARS-L1.md"; sl_crf "$SLC" "$PARS-L1"; SLC0="$(cksum < "$SLC")"
out="$(bash "$SC/automate-helpers.sh" current-set "$SLC" --item reqs/a.md --status ready_for_release --pr "$SLPR" 2>&1 >/dev/null)"; rc=$?
check "SL9 current-set --status ready_for_release in a single_lane lane ⇒ exit 1, file byte-unchanged, ONE stderr line naming single_lane" \
  "$rc:$(cksum < "$SLC"):$(printf '%s\n' "$out" | grep -c . | tr -d ' '):$(printf '%s' "$out" | grep -c 'single_lane' | tr -d ' ')" "1:$SLC0:1:1"
bash "$SC/automate-helpers.sh" current-set "$SLC" --pause-reason ready_for_release >/dev/null 2>&1; rc=$?
check "SL9b … --pause-reason ready_for_release (run-level form) refused too" "$rc:$(cksum < "$SLC")" "1:$SLC0"
out="$(bash "$SC/automate-helpers.sh" current-set "$SLC" --item reqs/a.md --status awaiting_merge --pr "$SLPR" --pause-reason awaiting_merge 2>&1)"; rc=$?
check "SL9c … the awaiting_merge park is written" "$rc:$out:$(grep -c "^- item: reqs/a.md | status: awaiting_merge | pr: $SLPR" "$SLC" | tr -d ' ')" "0:current-set: written:1"
SLN="$LRN/L1/.supervisor/automate/$PARN-L1.md"; sl_crf "$SLN" "$PARN-L1"
out="$(bash "$SC/automate-helpers.sh" current-set "$SLN" --item reqs/a.md --status ready_for_release --pause-reason ready_for_release 2>&1)"; rc=$?
check "SL9d an N>1 lane (no single_lane key) still writes ready_for_release" "$rc:$out" "0:current-set: written"
rm -f "$SLC" "$SLN"
# SL10 fleet-closeout on a `- parallel: 1` parent writes `fleet closeout: <lane> tokens TOTAL=<n>` BEFORE lane-remove
PARF=automate-2026-10-14-140000; RFF="$P/.supervisor/automate/$PARF.md"; LRF="$T/work/primary-lanes/$PARF"; sl_parent "$PARF" 1
PRF1="https://github.com/o/r/pull/141"
sl_lane() { # <parent_rf> <lanes_root> <n> <req> <pr> <status> — ae_lane, created as a SINGLE lane
  local id="$(basename "$1" .md)-L$3"
  run lane-create "$1" reqs/a.md "$3" --parallel 1 >/dev/null; ABL="$2/L$3"; ABRF="$ABL/.supervisor/automate/$id.md"
  LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$ABL" --owner-command '/automate --parallel 1' >/dev/null; wait_gone "$ABL"
  mkdir -p "$ABL/$(dirname "$4")" "$ABL/.supervisor/jobs/done"
  printf '# req\n\n## Status: pending\n' > "$ABL/$4"
  printf '# brief\n- **Source requirement:** %s\n\n## Outcome\n- **PR:** %s\n' "$4" "$5" > "$ABL/.supervisor/jobs/done/2026-10-14-$id.md"
  printf '# Automate Run: %s\n\n## Status: paused\n\n## Source\n- backlog: lane\n\n## Run Config\n- limit: 1\n\n## Queue\n- [ ] %s\n\n## Current\n- item: %s | status: %s | pr: %s | branch: feature/sl\n- pause_reason: %s\n\n## Progress\n- 2026-10-14T00:00:00Z drain READY\n' \
    "$id" "$4" "$4" "$6" "$5" "$6" > "$ABRF"
}
sl_lane "$RFF" "$LRF" 1 ".supervisor/requirements/t/sl1.md" "$PRF1" awaiting_merge; LF1="$ABL"
echo 4242 > "$LF1/.supervisor/sl-tokens"
out="$(AF_MERGED="$PRF1" LOOMWRIGHT_LANES_TOKEN_LEDGER="$T/sl-ledger.sh" af fleet-closeout "$RFF")"; rc=$?
printf '%s\n' "$out" | sed 's/^/       | /'
check "SL10 single-lane parent: the merged lane is closed out, checked off and removed (exit 0)" \
  "$rc:$([ -d "$LF1" ] && echo kept || echo removed):$(grep -c '^- \[x\] reqs/a.md$' "$RFF" | tr -d ' ')" "0:removed:1"
check "SL10b … the tokens line printed BEFORE the lane-remove line" \
  "$(printf '%s\n' "$out" | awk '$0 == "fleet-closeout: tokens — L1 TOTAL=4242" { t = NR } $0 ~ /^fleet-closeout: remove — L1 removed/ { r = NR } END { print (t && r && t < r) }')" 1
check "SL10c … and ONE parent ## Progress line carrying the lane's real TOTAL (read while its directory existed)" \
  "$(grep -cxF -- '- fleet closeout: L1 tokens TOTAL=4242' "$RFF" | tr -d ' ')" 1
check "SL10d … the next item stays queued under the kept lock" "$(printf '%s\n' "$out" | tail -n1)" \
  "fleet-closeout: lock kept — 1 Queue item(s) remain unchecked (the next wave runs under it)"
check "SL10e fleet-closeout on the N>1 parent (AF above) wrote NO tokens line" "$(grep -c 'tokens TOTAL=' "$RF10" | tr -d ' ')" 0
# SL11 the merge watcher outlives the process that launched it (AC 8, owner decision 2). The launch line
# is READ from automate-merge-watch.sh's header (its documented source), never typed here; the leg runs it
# from a short-lived `bash -c` parent against a stub gh that reports OPEN, waits for that parent to exit,
# then delivers the hang-up a host's exit sends, and asserts the marker pid is alive and is the watcher.
cat > "$T/ws-gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in "pr view") [ -z "${WS_GH_LOG:-}" ] || echo poll >> "$WS_GH_LOG"
  echo '{"state":"OPEN","headRefOid":"abc","statusCheckRollup":[]}' ;; *) exit 1 ;; esac
EOF
chmod +x "$T/ws-gh"
ws_calls() { # <gh call log> — how many `gh pr view` polls the watcher has made (0 before the first)
  if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi
}
_ws_settled() { # <pid> <gh call log> <n> — the watcher is gone, or it has made <n> polls
  ! kill -0 "$1" 2>/dev/null || [ "$(ws_calls "$2")" -ge "$3" ]
}
ws_line() { # <merge-watch file> — the documented launch line (header + its continuation), placeholders kept
  awk 'index($0, "#   env -u CLAUDE_PID -u CLAUDECODE ") == 1 && / automate-merge-watch\.sh \\$/ {
         l = $0; sub(/^#   /, "", l); sub(/ \\$/, "", l); getline n; sub(/^#[ ]+/, "", n); print l " " n; exit }' "$1"
}
ws_sub() { # <text> <from> <to> — literal replace-all (values via ENVIRON, never awk -v)
  WS_T="$1" WS_F="$2" WS_R="$3" awk 'BEGIN { t = ENVIRON["WS_T"]; f = ENVIRON["WS_F"]; r = ENVIRON["WS_R"]; o = ""
    while ((i = index(t, f)) > 0) { o = o substr(t, 1, i - 1) r; t = substr(t, i + length(f)) } print o t }'
}
ws_leg() { # <merge-watch file the line is read from> <tag> — prints `alive` | `dead` | `parent-blocked` | `no-line` | `no-marker` | `unsettled`
  local src="$1" tag="$2" d rf cmd p i wp gl c0
  cmd="$(ws_line "$src")"; [ -n "$cmd" ] || { echo no-line; return 0; }
  d="$T/ws-$tag"; mkdir -p "$d/.supervisor/automate"; rf="$d/.supervisor/automate/ws-$tag.md"
  printf '# Automate Run: ws-%s\n\n## Current\n- item: reqs/a.md | status: awaiting_merge | pr: %s\n\n## Progress\n' "$tag" "$SLPR" > "$rf"
  cmd="$(ws_sub "$cmd" '"<runfile dir>/<run_id>.merge-watch.log"' "'$d/.supervisor/automate/ws-$tag.merge-watch.log'")"
  cmd="$(ws_sub "$cmd" '<runfile> <item> <pr_url>' "'$rf' reqs/a.md '$SLPR'")"
  cmd="$(ws_sub "$cmd" ' automate-merge-watch.sh ' " '$HERE/automate-merge-watch.sh' ")"
  gl="$d/gh-calls"
  LOOMWRIGHT_GH_BIN="$T/ws-gh" WS_GH_LOG="$gl" LOOMWRIGHT_MERGE_WATCH_INTERVAL=1 bash -c "$cmd" </dev/null >/dev/null 2>&1 & p=$!
  i=0; while kill -0 "$p" 2>/dev/null && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  if kill -0 "$p" 2>/dev/null; then pkill -TERM -P "$p" 2>/dev/null; kill -TERM "$p" 2>/dev/null; wait "$p" 2>/dev/null; echo parent-blocked; return 0; fi
  wait "$p" 2>/dev/null
  i=0; while [ ! -s "$d/.supervisor/automate/ws-$tag.merge-watch" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  wp="$(awk -F'\t' '$1 == "pid" { print $2 }' "$d/.supervisor/automate/ws-$tag.merge-watch" 2>/dev/null)"
  [ -n "$wp" ] || { echo no-marker; return 0; }
  kill -HUP "$wp" 2>/dev/null   # the hang-up a host's exit delivers to what it started
  # Wait on a CONDITION, never a fixed time: the watcher dies (the hang-up took) or makes two more polls
  # counted AFTER the kill — a command boundary and a full interruptible nap lie between them, where its
  # `trap 'exit 0' HUP` would already have run — so `alive` below cannot pass before the signal acted.
  # A deadline miss with the watcher alive but not polling is `unsettled`, red for both SL11b and SL11c.
  c0="$(ws_calls "$gl")"
  if ! wait_for_cmd 20 _ws_settled "$wp" "$gl" "$((c0 + 2))" 2>/dev/null; then
    echo unsettled
  elif kill -0 "$wp" 2>/dev/null && case "$(ps -ww -p "$wp" -o command= 2>/dev/null)" in *automate-merge-watch.sh*" $SLPR"*) true ;; *) false ;; esac; then
    echo alive
  else echo dead; fi
  kill -TERM "$wp" 2>/dev/null   # stop it (its trap removes the marker) — nothing may leak into the piped suite
  i=0; while kill -0 "$wp" 2>/dev/null && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  kill -KILL "$wp" 2>/dev/null; return 0
}
check "SL11 the documented launch line is found in the automate-merge-watch.sh header" \
  "$(ws_line "$HERE/automate-merge-watch.sh" | grep -c '^env -u CLAUDE_PID -u CLAUDECODE nohup bash automate-merge-watch.sh <runfile> <item> <pr_url> </dev/null >"<runfile dir>/<run_id>.merge-watch.log" 2>&1 &$' | tr -d ' ')" 1
check "SL11b a watcher launched with that line outlives its parent and the hang-up (marker pid alive, ps shows the watcher + pr_url)" \
  "$(ws_leg "$HERE/automate-merge-watch.sh" real)" alive
# mutation control: the same leg on a header whose launch line lost `nohup` must report the watcher dead
sed 's/^#   env -u CLAUDE_PID -u CLAUDECODE nohup bash automate-merge-watch.sh \\$/#   env -u CLAUDE_PID -u CLAUDECODE bash automate-merge-watch.sh \\/' "$HERE/automate-merge-watch.sh" > "$T/ws-nonohup.sh"
if cmp -s "$HERE/automate-merge-watch.sh" "$T/ws-nonohup.sh"; then bad "SL11c mutant (nohup removed) not built"
else check "SL11c mutation control: the line without nohup ⇒ the watcher dies with the hang-up (SL11b would be red)" "$(ws_leg "$T/ws-nonohup.sh" nonohup)" dead; fi

# ---- AG: wave-plan is READ-ONLY (A4) + the no-new-merge-path guards (A3) + mutation control ----------
PARENT12=automate-2026-10-10-150000; RF12P="$P/.supervisor/automate/$PARENT12.md"; LR12="$T/work/primary-lanes/$PARENT12"
printf '# Automate Run: %s\n\n## Queue\n- [ ] reqs/a.md\n- [ ] reqs/b.md\n\n## Current\n- item: null | status: null\n- wave: 2 | items: reqs/b.md, reqs/a.md\n\n## Progress\n' "$PARENT12" > "$RF12P"
PR121="https://github.com/o/r/pull/121"; PR122="https://github.com/o/r/pull/122"
ae_lane "$RF12P" "$LR12" 1 ".supervisor/requirements/t/ag1.md" "$PR121" ready_for_release; L121="$ABL"
run lane-create "$RF12P" reqs/b.md 2 >/dev/null; L122="$LR12/L2"
printf '# Automate Run: %s-L2\n\n## Status: paused\n\n## Queue\n- [ ] reqs/b.md\n\n## Current\n- item: reqs/b.md | status: ready_for_release | pr: %s | branch: feature/b\n- pause_reason: ready_for_release\n\n## Progress\n' \
  "$PARENT12" "$PR122" > "$L122/.supervisor/automate/$PARENT12-L2.md"
ag_state() { # every ref + the working tree (status + content checksums) of the primary and both lanes
  local d; for d in "$P" "$L121" "$L122"; do git -C "$d" for-each-ref; git -C "$d" status --porcelain --untracked-files=all; lane_sum "$d"; done 2>&1 | cksum
}
: > "$T_AFGH"; AG0="$(ag_state)"
out="$(AF_NOHEAD="$PR121" af wave-plan "$RF12P")"; rc=$?
SHA122="$(printf '%040d' 122)"
check "AG1 wave-plan prints the operator's commands in planner order (exit 0)" "$rc
$out" "0
# wave-plan: $PARENT12 wave 2 (from ## Current) — READ-ONLY: nothing below was run; the operator runs it
git fetch origin
git checkout -b wave/$PARENT12-w2 origin/main
git merge --no-ff $SHA122 -m \"Merge lane L2 (reqs/b.md) PR #122\"
# L1: head unreadable — resolve before integrating
bash scripts/ci-local.sh
# run this project's release step
git push -u origin wave/$PARENT12-w2
gh pr create --base main --head wave/$PARENT12-w2
# Conflict rules (Part S):
#   - a marker-only conflict is resolved in the merge commit itself
#   - anything larger stops the integration: hand it to the owner
#   - never rewrite or push a lane branch
#   - a lane broken on the wave branch is fixed on its own PR, and its new head is re-merged"
check "AG2 GUARD: every ref and the working tree of the primary and the lanes are byte-identical after it" "$(ag_state)" "$AG0"
check "AG2b … and its only gh calls were pr view reads" "$(grep -vc '^gh pr view ' "$T_AFGH" | tr -d ' ')" 0
mkdir -p "$P/scripts"; printf '#!/usr/bin/env bash\n' > "$P/scripts/bump-version.sh"
out="$(af wave-plan "$RF12P" --wave-branch release/w2)"
has "AG3 a repo with scripts/bump-version.sh gets it as the release step" "$out" "
bash scripts/bump-version.sh
"
has "AG3b --wave-branch names the branch" "$out" "git checkout -b release/w2 origin/main"
has "AG3c … both lanes merged by their exact head sha" "$out" "git merge --no-ff $(printf '%040d' 121) -m \"Merge lane L1 (reqs/a.md) PR #121\""
rm -rf "$P/scripts"
out="$(af wave-plan "$RF11")"
check "AG3d no ## Current wave line ⇒ the lane table order, wave 1" "$(printf '%s\n' "$out" | sed -n '1p;3,4p')" \
  "# wave-plan: $PARENT11 wave 1 (no ## Current wave items — lane table order) — READ-ONLY: nothing below was run; the operator runs it
git checkout -b wave/$PARENT11-w1 origin/main
git merge --no-ff $(printf '%040d' 111) -m \"Merge lane L1 (reqs/a.md) PR #111\""
sed 's/^- wave: 2 | items: reqs\/b.md, reqs\/a.md$/- wave: 3 | items: reqs\/zzz.md/' "$RF12P" > "$T/ag.rf"; cp "$RF12P" "$T/ag.rf.keep"; mv "$T/ag.rf" "$RF12P"
check "AG3e a wave item with no lane is named and skipped" "$(af wave-plan "$RF12P" | sed -n 4p)" "# reqs/zzz.md: no lane in $PARENT12.lanes — skipped"
mv "$T/ag.rf.keep" "$RF12P"
out="$(af wave-plan "$RF12P" --wave-branch 'bad..name')"; rc=$?
check "AG4 an invalid wave branch name is refused (exit 1)" "$rc:$(printf '%s' "$out" | grep -c "^wave-plan: refused — 'bad..name' is not a valid branch name" | tr -d ' ')" "1:1"
check "AG4b helpers dispatches wave-plan and fleet-closeout to automate-lanes.sh" \
  "$(bash "$HERE/automate-helpers.sh" wave-plan 2>&1 | grep -c '^wave-plan: refused — ' | tr -d ' '):$(bash "$HERE/automate-helpers.sh" fleet-closeout 2>&1 | grep -cxF 'automate-lanes: usage: fleet-closeout <parent_runfile>' | tr -d ' ')" \
  "1:1"
# AG5 mutation control: a wave-plan that writes ONE ref (the wave branch) must fail the AG2 guard.
sed 's|^  echo "git checkout -b \$wb origin/\$base"$|&; git -C "$primary" branch "$wb" "refs/remotes/origin/$base" >/dev/null 2>\&1|' "$SB" > "$MUT/automate-lanes.sh"
if [ -s "$MUT/automate-lanes.sh" ] && ! cmp -s "$SB" "$MUT/automate-lanes.sh" && bash -n "$MUT/automate-lanes.sh"; then ok "AG5a mutant valid (non-empty, differs, bash -n)"; else bad "AG5a mutant invalid"; fi
AF_NOHEAD="$PR121" REMOTE11="$T/remote-af" LOOMWRIGHT_GH_BIN="$T/af-gh" bash "$MUT/automate-lanes.sh" wave-plan "$RF12P" >/dev/null 2>&1
if [ "$(ag_state)" != "$AG0" ]; then ok "AG5b mutation (wave-plan writes a ref) fails the read-only guard"; else bad "AG5b mutation control did not trip"; fi
git -C "$P" branch -D "wave/$PARENT12-w2" >/dev/null 2>&1
check "AG5c … the mutant's ref removed again" "$(ag_state)" "$AG0"
# AG6 A3/A4 static guards: no executable merge / push / gate-eval in automate-lanes.sh — the only hits
# are comments, the deny-list lines that NAME the tokens, and wave-plan's printed strings.
ag_exec_hits() { grep -nE 'gh pr merge|gate-eval|git( -C [^ ]+)? (merge|push)( |$)' "$1" \
  | grep -vE '^[0-9]+:[[:space:]]*#' | grep -vE 'LANE_DISALLOWED_FIXED=|disallow="|echo "git |printf .git merge'; }
check "AG6 automate-lanes.sh has no executable gh pr merge / gate-eval / git merge / git push" "$(ag_exec_hits "$SB")" ""
awk '{ print } /^lanes_wave_plan\(\) \{$/ { print "  git -C \"$LP_PRIMARY\" push origin HEAD >/dev/null 2>&1" }' "$SB" > "$MUT/automate-lanes.sh"
if [ -s "$MUT/automate-lanes.sh" ] && ! cmp -s "$SB" "$MUT/automate-lanes.sh" && bash -n "$MUT/automate-lanes.sh"; then ok "AG6a mutant valid (non-empty, differs, bash -n)"; else bad "AG6a mutant invalid"; fi
check "AG6b mutation (an executable git push) is caught by the static guard" "$(ag_exec_hits "$MUT/automate-lanes.sh" | wc -l | tr -d ' ')" 1
check "AG7 A5: no sequential-loop script calls fleet-closeout or wave-plan (only the helpers dispatch arm)" \
  "$(grep -lE 'fleet-closeout|wave-plan' "$HERE"/automate-helpers.d/*.sh "$HERE/automate-trail.sh" "$HERE/automate-dismissed.sh" 2>/dev/null | wc -l | tr -d ' '):$(grep -cE '^ +fleet-closeout\|wave-plan\) exec bash "\$\(dirname "\$0"\)/automate-lanes.sh"' "$HERE/automate-helpers.sh" | tr -d ' ')" "0:1"

# ---- AI: gate opt-out carry (lane-guardrails part 3) ---------------------------------------------------
# A lane launched WITH the test-integrity guard's opt-out inherits it; a resume run from an environment
# that lacks it would silently have the guard block the lane. The FACT is recorded coordinator-side at
# first launch; every resume path refuses (exit 3, no spawn, nothing in the lane) until the owner re-runs
# with it set or passes --without-gate-optout. The opt-out is never ADDED to a resume's environment.
PARENT6=automate-2026-10-11-100000; RF6="$P/.supervisor/automate/$PARENT6.md"; LR6="$T/work/primary-lanes/$PARENT6"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENT6" > "$RF6"
for n in 1 2 3; do run lane-create "$RF6" reqs/a.md "$n" --parallel 3 >/dev/null; done
L61="$LR6/L1"; L62="$LR6/L2"; L63="$LR6/L3"; TABLE6="$P/.supervisor/automate/$PARENT6.lanes"
OF61="$P/.supervisor/automate/$PARENT6.L1.gate-optout"; OF63="$P/.supervisor/automate/$PARENT6.L3.gate-optout"
OPT_ON="LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS=1"
lenv() { grep '^ENV' "$STUB_LOG" | tail -1 | sed 's/.* OPTOUT=//'; }
LJ61="$(cat "$L61/.supervisor/lane.json")"
n6="$(claude_calls)"
out="$(env "$OPT_ON" LOOMWRIGHT_LANE_RECHECK_S=0 bash "$S" lane-launch "$L61" --owner-command "$OWN" 2>&1)"; rc=$?
wait_gone "$L61"
check "AI1 first launch with the opt-out set launches (and the lane inherits it)" "$rc:$(( $(claude_calls) - n6 )):$(lenv)" "0:1:1"
check "AI1b the FACT is recorded coordinator-side (no value)" "$(cut -f1 "$OF61" 2>/dev/null):$(grep -c 'LOOMWRIGHT\|=1' "$OF61" 2>/dev/null | tr -d ' ')" "gate_optout_at_launch:0"
check "AI1c … never in the lane: lane.json byte-identical, no opt-out file under the lane" \
  "$([ "$(cat "$L61/.supervisor/lane.json")" = "$LJ61" ] && echo same):$(find "$L61" -name '*optout*' | wc -l | tr -d ' ')" "same:0"
mkdir -p "$L61/.supervisor/automate"; printf '# Automate Run: %s-L1 — reqs/a.md\n' "$PARENT6" > "$L61/.supervisor/automate/$PARENT6-L1.md"
ai_blocked="lane-launch: BLOCKED — L1 — launched with the test-integrity guard's opt-out; this resume's environment lacks it — re-run the same command with it set, or add --without-gate-optout to resume without it — need the owner"
n6="$(claude_calls)"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L61" --owner-command "/automate --resume $PARENT6" --continue)"; rc=$?
check "AI2 --continue without the opt-out ⇒ BLOCKED exit 3, the exact line, no spawn" "$rc:$(printf '%s\n' "$out" | head -1):$(( $(claude_calls) - n6 ))" "3:$ai_blocked:0"
check "AI2b … the table reads blocked_launch with the reason; the fact is kept" \
  "$(awk -F'\t' '$1 == "L1" { print $8 "|" $10 }' "$TABLE6"):$([ -e "$OF61" ] && echo kept)" \
  "blocked_launch|launched with the test-integrity guard's opt-out; this resume's environment lacks it:kept"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L61" --owner-command "/automate --resume $PARENT6" --resume-run "$PARENT6-L1")"; rc=$?
check "AI3 --resume-run without the opt-out ⇒ BLOCKED exit 3, no spawn" "$rc:$(( $(claude_calls) - n6 ))" "3:0"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS=true run lane-launch "$L61" --owner-command "/automate --resume $PARENT6" --continue)"; rc=$?
check "AI3b a value other than 1 is the guard's 'unset' too ⇒ BLOCKED" "$rc:$(( $(claude_calls) - n6 ))" "3:0"
out="$(env "$OPT_ON" LOOMWRIGHT_LANE_RECHECK_S=0 bash "$S" lane-launch "$L61" --owner-command "/automate --resume $PARENT6" --continue 2>&1)"; rc=$?
wait_gone "$L61"
check "AI4 the same resume WITH the opt-out set ⇒ resumes, the lane runs with it (inherited)" "$rc:$(( $(claude_calls) - n6 )):$(lenv)" "0:1:1"
check "AI4b … and the fact stays recorded" "$([ -e "$OF61" ] && echo kept || echo gone)" kept
n6="$(claude_calls)"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L61" --owner-command "/automate --resume $PARENT6" --continue --without-gate-optout)"; rc=$?
wait_gone "$L61"
check "AI5 --without-gate-optout resumes without it (never added)" "$rc:$(( $(claude_calls) - n6 )):$(lenv)" "0:1:unset"
check "AI5b … and clears the recorded fact" "$([ -e "$OF61" ] && echo kept || echo gone)" gone
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L61" --owner-command "/automate --resume $PARENT6" --continue)"; rc=$?
wait_gone "$L61"
check "AI6 fact cleared ⇒ a resume without the opt-out is unchanged (launches)" "$rc:$(( $(claude_calls) - n6 ))" "0:2"
# AI7 --without-gate-optout given while the environment HAS it: dropped from the spawn, nothing recorded.
n6="$(claude_calls)"
out="$(env "$OPT_ON" LOOMWRIGHT_LANE_RECHECK_S=0 bash "$S" lane-launch "$L62" --owner-command "$OWN" --without-gate-optout 2>&1)"; rc=$?
wait_gone "$L62"
check "AI7 a first launch with --without-gate-optout drops it from the lane's env and records nothing" \
  "$rc:$(lenv):$([ -e "$P/.supervisor/automate/$PARENT6.L2.gate-optout" ] && echo recorded || echo none)" "0:unset:none"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L62" --owner-command "/automate --resume $PARENT6" --continue)"; rc=$?
wait_gone "$L62"
check "AI7b recorded = unset ⇒ resumes exactly as before" "$rc" 0
# AI8 lane-answer: the refusal keeps the owner's validated answer pending (never lost), like HELD.
out="$(env "$OPT_ON" LOOMWRIGHT_LANE_RECHECK_S=0 bash "$S" lane-launch "$L63" --owner-command "$OWN" 2>&1)"; wait_gone "$L63"
zq "$L63" toolu_ai1 sess-ai1
PF63="$P/.supervisor/automate/$PARENT6.L3.answer-pending.json"; AF63="$L63/.supervisor/inbox/answers/toolu_ai1.json"
n6="$(claude_calls)"
out="$(printf '%s' '{"answers":{"0":"Red","1":"A,B"},"note":"keep it small"}' | LOOMWRIGHT_LANE_RECHECK_S=0 bash "$S" lane-answer "$L63" toolu_ai1 --owner-command "$OWN" --via test 2>&1)"; rc=$?
check "AI8 lane-answer without the opt-out ⇒ BLOCKED exit 3, no spawn, nothing written into the lane" \
  "$rc:$(printf '%s\n' "$out" | head -1):$(( $(claude_calls) - n6 )):$([ -e "$AF63" ] && echo written || echo none)" \
  "3:${ai_blocked/— L1 —/— L3 —}:0:none"
check "AI8b … the validated answer is KEPT pending (answers, note, via)" \
  "$(jq -c '[.tool_use_id, .answers["0"], .answers["1"], .note, .via]' "$PF63" 2>/dev/null)" '["toolu_ai1","Red","A,B","keep it small","test"]'
has "AI8c … and the line says how to deliver it" "$out" "deliver it with the opt-out set, or with --without-gate-optout"
check "AI8d lane-status shows the lane as answer_pending" "$(bash "$S" lane-status "$RF6" --json 2>/dev/null | jq -r '.lanes[] | select(.lane == "L3") | .state')" answer_pending
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-answer "$L63" --deliver-pending --owner-command "/automate --resume $PARENT6")"; rc=$?
check "AI9 --deliver-pending without the opt-out ⇒ BLOCKED, the answer still pending, nothing in the lane" \
  "$rc:$([ -s "$PF63" ] && echo kept || echo gone):$([ -e "$AF63" ] && echo written || echo none):$(( $(claude_calls) - n6 ))" "3:kept:none:0"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-answer "$L63" --deliver-pending --owner-command "/automate --resume $PARENT6" --without-gate-optout)"; rc=$?
wait_gone "$L63"
check "AI9b --deliver-pending --without-gate-optout delivers: answer file written, pending gone, fact cleared, env unset" \
  "$rc:$(jq -c '[.answers["Which color?"], .note]' "$AF63" 2>/dev/null):$([ -e "$PF63" ] && echo kept || echo gone):$([ -e "$OF63" ] && echo kept || echo gone):$(lenv)" \
  '0:["Red","keep it small"]:gone:gone:unset'
check "AI9c … one spawn, resuming the deferred session" "$(( $(claude_calls) - n6 )):$(grep '^ARGS' "$STUB_LOG" | tail -1 | grep -c '\[--resume\] \[sess-ai1\]' | tr -d ' ')" "1:1"
check "AI10 the opt-out's name never reaches a lane file (lane.json, inbox, settings)" \
  "$(grep -rl 'ALLOW_GATE_CONFIG_EDITS\|gate-optout\|gate_optout' "$L61/.supervisor" "$L63/.supervisor" "$L61/.claude" 2>/dev/null | wc -l | tr -d ' ')" 0

