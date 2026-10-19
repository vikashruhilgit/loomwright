# =============================================================================
echo "== QG. automate-speed/01: queue-confirm (AUT-QUEUE, D1) + park-ask-gate (park first, then ask, D2/D3) =="
QG="$(mktemp -d)"; QG="$(cd "$QG" && pwd -P)"
QG_MUT="$(dirname "$H")/qg-mutant.sh"
# qg_mut <out> <anchor> <replacement|__DELETE__> — a COPY of the bundle with the FIRST line
# containing <anchor> replaced (or deleted). Values reach awk through the environment.
qg_mut() {
  QG_A="$2" QG_R="$3" awk 'BEGIN { a = ENVIRON["QG_A"]; r = ENVIRON["QG_R"] }
    !d && index($0, a) { d = 1; if (r == "__DELETE__") next; print r; next } { print }' "$H" > "$1"
}
# qg_mut_check <label> <anchor> <replacement|__DELETE__> <scenario_fn> <expected> — the
# mutant is trusted only when the anchor is unique in the bundle, the mutant is non-empty,
# differs from the original and passes `bash -n`; it must then make <scenario_fn> print
# something other than the <expected> the real helper prints (its leg turns red).
qg_mut_check() {
  local got
  qg_mut "$QG_MUT" "$2" "$3"
  if [ "$(grep -cF -- "$2" "$H")" = 1 ] && [ -s "$QG_MUT" ] && ! cmp -s "$H" "$QG_MUT" && bash -n "$QG_MUT" 2>/dev/null; then
    got="$("$4" "$QG_MUT")"
    if [ "$got" != "$5" ]; then ok "QG mutant ($1) turns its leg red: '$got'"; else no "QG mutant ($1) did NOT discriminate: '$got'"; fi
  else
    no "QG mutant ($1) not gated (anchor not unique, mutant empty, identical, or bash -n failed)"
  fi
  rm -f "$QG_MUT"
}
# qg_is <label> <got> <expected>
qg_is() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 — got '$2', want '$3'"; fi; }

# ---- QG1. queue-confirm (AC1) — one scenario fn per leg, run on the real helper and its mutant
qc() { local h="$1"; shift; RUN_OUT="$(bash "$h" queue-confirm "$@" 2>&1)"; RUN_RC=$?; printf 'rc=%s %s' "$RUN_RC" "$RUN_OUT"; }
QC_LANE="skip — lane backlog written by lane-create from the owner's --parallel command"
qc_le()    { qc "$1" backlog 5 5; }            # n == limit still skips (D1: "≤")
qc_lt()    { qc "$1" backlog 3 5; }
qc_gt()    { qc "$1" backlog 6 5; }            # n > limit asks
qc_src()   { printf '%s|%s|%s' "$(qc "$1" folder 1 5)" "$(qc "$1" prompt 0 5)" "$(qc "$1" nonsense 1 5)"; }
qc_lane()  { printf '%s|%s' "$(qc "$1" --lane-backlog)" "$(qc "$1" backlog 9 1 --lane-backlog)"; }
qc_bad()   { printf '%s|%s|%s|%s|%s' "$(qc "$1" backlog -1 5)" "$(qc "$1" backlog abc 5)" "$(qc "$1" backlog 3 x)" "$(qc "$1" backlog 08 9)" "$(qc "$1" backlog 1234567890 5)"; }
qc_max()   { printf '%s|%s' "$(qc "$1" backlog 123456789 999999999)" "$(qc "$1" backlog 999999999 5)"; }  # 9 digits is the largest accepted count
qc_usage() { printf '%s|%s|%s' "$(qc "$1" backlog 3 2>/dev/null | cut -c1-4)" "$(qc "$1" 2>/dev/null | cut -c1-4)" "$(qc "$1" backlog 1 2 3 | cut -c1-4)"; }
E_LE="rc=0 skip — backlog queue 5 ≤ limit 5"
E_GT="rc=0 ask"
E_SRC="rc=0 ask|rc=0 ask|rc=0 ask"
E_LANE="rc=0 $QC_LANE|rc=0 $QC_LANE"
E_BAD="rc=0 ask|rc=0 ask|rc=0 ask|rc=0 ask|rc=0 ask"
E_USAGE="rc=1|rc=1|rc=1"
E_MAX="rc=0 skip — backlog queue 123456789 ≤ limit 999999999|rc=0 ask"
qg_is "QG1a queue-confirm backlog n == limit ⇒ exactly 'skip — backlog queue 5 ≤ limit 5', exit 0" "$(qc_le "$H")" "$E_LE"
qg_is "QG1a' queue-confirm backlog 3 ≤ 5 ⇒ skip line names both numbers" "$(qc_lt "$H")" "rc=0 skip — backlog queue 3 ≤ limit 5"
qg_is "QG1b queue-confirm backlog n > limit ⇒ ask" "$(qc_gt "$H")" "$E_GT"
qg_is "QG1c queue-confirm folder / prompt / unknown source ⇒ ask at any count" "$(qc_src "$H")" "$E_SRC"
qg_is "QG1d queue-confirm --lane-backlog ⇒ the lane skip text exactly (positional args ignored)" "$(qc_lane "$H")" "$E_LANE"
qg_is "QG1e queue-confirm non-integer / signed / leading-zero / >9-digit count ⇒ ask, nothing on stderr" "$(qc_bad "$H")" "$E_BAD"
qg_is "QG1e' queue-confirm 9-digit counts are accepted (the length-cap boundary): 123456789 ≤ 999999999 skips, 999999999 > 5 asks" "$(qc_max "$H")" "$E_MAX"
qg_is "QG1f queue-confirm missing or extra argument ⇒ usage error exit 1" "$(qc_usage "$H")" "$E_USAGE"
# the lane text is the lane's existing Progress reason, byte for byte (intake.md's lane bullet)
QG_INTAKE="$HERE/../skills/automate-loop/intake.md"
qg_lane_prose() { if grep -qF -- "skipped AUT-QUEUE: ${QC_LANE#skip — }" "$1"; then printf match; else printf differ; fi; }
qg_is "QG1d' the --lane-backlog reason is intake.md's lane Progress line byte for byte" "$(qg_lane_prose "$QG_INTAKE")" match
# qg_prose_check <label> <src> <mutant> <scenario_fn> <expected> — a prose mutant is trusted only
# when it is non-empty, differs from <src> and lost no line; it must then turn <scenario_fn> red.
qg_prose_check() {
  if [ -s "$3" ] && ! cmp -s "$2" "$3" && [ "$(wc -l < "$3")" -ge "$(wc -l < "$2")" ]; then
    if [ "$("$4" "$3")" != "$5" ]; then ok "QG prose mutant ($1) turns its leg red"; else no "QG prose mutant ($1) did NOT discriminate"; fi
  else
    no "QG prose mutant ($1) not gated (empty, identical, or a line was lost)"
  fi
  rm -f "$3"
}
QG_LANE_TXT="${QC_LANE#skip — }"
QG_LT="$QG_LANE_TXT" awk 'BEGIN { t = ENVIRON["QG_LT"] } !d && (i = index($0, t)) { d = 1; $0 = substr($0, 1, i - 1) "lane backlog made by" substr($0, i + length("lane backlog written by")) } { print }' "$QG_INTAKE" > "$QG/intake-lane-mutant.md"
qg_prose_check "QG1d': intake.md's lane line reworded (written by → made by)" "$QG_INTAKE" "$QG/intake-lane-mutant.md" qg_lane_prose match
qg_mut_check "QG1a: -le flipped to -lt" '  if [ "$n" -le "$limit" ]; then' '  if [ "$n" -lt "$limit" ]; then' qc_le "$E_LE"
qg_mut_check "QG1b: comparison always true" '  if [ "$n" -le "$limit" ]; then' '  if true; then' qc_gt "$E_GT"
qg_mut_check "QG1c: source check deleted" '  [ "$src" = backlog ] || { echo "ask"; return 0; }' __DELETE__ qc_src "$E_SRC"
qg_mut_check "QG1d: one word of the lane text changed" "    echo \"$QC_LANE\"; return 0" "    echo \"skip — lane backlog made by lane-create from the owner's --parallel command\"; return 0" qc_lane "$E_LANE"
qg_mut_check "QG1e: integer check dropped" '  { _qc_count "$n" && _qc_count "$limit"; } || { echo "ask"; return 0; }' __DELETE__ qc_bad "$E_BAD"
qg_mut_check "QG1e': length cap lowered to 8 digits" '  [ "${#1}" -le 9 ]' '  [ "${#1}" -le 8 ]' qc_max "$E_MAX"
qg_mut_check "QG1f: argument-count die deleted" '  [ "$k" -eq 3 ] || die "queue-confirm: usage:' __DELETE__ qc_usage "$E_USAGE"

# ---- QG2. park-ask-gate (AC3/AC4) against a stubbed gh (pr view → ghstub/pr-view.json, or exit 1)
make_stub_bin "$QG/bin"; mkdir -p "$QG/ghstub" "$QG/auto"
QG_RF="$QG/auto/automate-qg-1.md"; QG_MK="$QG/auto/automate-qg-1.merge-watch"
QG_PR="https://github.com/acme/widgets/pull/77"; QG_PR2="https://github.com/acme/widgets/pull/78"
qg_rf() {  # <item> <status> <pr>
  printf '# Automate Run: automate-qg-1 — q\n## Status: paused\n## Queue\n- [ ] .supervisor/requirements/x/01-a.md\n## Current\n- item: %s | status: %s | pr: %s | branch: feat/a\n- pause_reason: awaiting_merge\n- pending_decisions: 2 | fix_now_reentered: false\n\n## Progress\n- t0 run created\n' "$1" "$2" "$3" > "$QG_RF"
}
qg_marker() { printf 'pid\t4242\npr_url\t%s\nstarted\t2026-10-14T00:00:00Z\n' "$1" > "$QG_MK"; }
qg_state() { rm -f "$QG/ghstub/pr-view-fail"; if [ "$1" = fail ]; then touch "$QG/ghstub/pr-view-fail"; else printf '{"state":"%s"}\n' "$1" > "$QG/ghstub/pr-view.json"; fi; }
pag() { local h="$1"; shift; RUN_OUT="$(env PATH="$QG/bin:$PATH" GH_STUB_DIR="$QG/ghstub" bash "$h" park-ask-gate "$@" 2>/dev/null)"; RUN_RC=$?; printf 'rc=%s %s' "$RUN_RC" "$RUN_OUT"; }
QG_ITEM=".supervisor/requirements/x/01-a.md"
qg_parked() { qg_rf "./$QG_ITEM" awaiting_merge "$QG_PR"; qg_marker "$QG_PR"; }
p_open()    { qg_parked; qg_state OPEN; pag "$1" "$QG_RF" "$QG_ITEM" "$QG_PR"; }
p_states()  { qg_parked; local s o=""; for s in MERGED CLOSED DRAFT; do qg_state "$s"; o="$o|$(pag "$1" "$QG_RF" "$QG_ITEM" "$QG_PR")"; done; printf '%s' "$o"; }
p_ghfail()  { qg_parked; qg_state fail; local a; a="$(pag "$1" "$QG_RF" "$QG_ITEM" "$QG_PR")"; rm -f "$QG/ghstub/pr-view-fail"; printf '{}\n' > "$QG/ghstub/pr-view.json"; printf '%s|%s' "$a" "$(pag "$1" "$QG_RF" "$QG_ITEM" "$QG_PR")"; }
p_done()    { qg_parked; qg_rf "$QG_ITEM" done "$QG_PR"; qg_state OPEN; pag "$1" "$QG_RF" "$QG_ITEM" "$QG_PR"; }
p_running() { qg_parked; qg_rf "$QG_ITEM" running "$QG_PR"; qg_state OPEN; pag "$1" "$QG_RF" "$QG_ITEM" "$QG_PR"; }
p_marker()  { qg_parked; qg_state OPEN; rm -f "$QG_MK"; local a; a="$(pag "$1" "$QG_RF" "$QG_ITEM" "$QG_PR")"; qg_marker "$QG_PR2"; printf '%s|%s' "$a" "$(pag "$1" "$QG_RF" "$QG_ITEM" "$QG_PR")"; }
p_foreign() { qg_state OPEN; qg_marker "$QG_PR"; qg_rf ".supervisor/requirements/x/02-b.md" awaiting_merge "$QG_PR"; local a; a="$(pag "$1" "$QG_RF" "$QG_ITEM" "$QG_PR")"; qg_rf "$QG_ITEM" awaiting_merge "$QG_PR2"; printf '%s|%s' "$a" "$(pag "$1" "$QG_RF" "$QG_ITEM" "$QG_PR")"; }
p_missing() { qg_state OPEN; local a; a="$(pag "$1" "$QG/auto/absent.md" "$QG_ITEM" "$QG_PR")"; printf '# Automate Run: x\n## Status: paused\n## Queue\n## Current\n- pause_reason: null\n' > "$QG/auto/noitem.md"; printf '%s|%s' "$a" "$(pag "$1" "$QG/auto/noitem.md" "$QG_ITEM" "$QG_PR")"; }
p_usage()   { printf '%s|%s|%s|%s|%s' "$(pag "$1" "$QG_RF" "$QG_ITEM")" "$(pag "$1" "$QG_RF" "$QG_ITEM" "$QG_PR" --wait x)" "$(pag "$1" "$QG_RF" "$QG_ITEM" "$QG_PR" --nope)" "$(pag "$1" "$QG_RF" "$QG_ITEM" "$QG_PR" --wait)" "$(pag "$1" "$QG_RF" "$QG_ITEM" "$QG_PR" extra)"; }
# delayed marker: the watcher writes it ~2s after the call; --wait 5 must see it and answer ask
p_delayed() {
  qg_parked; qg_state OPEN; rm -f "$QG_MK"
  ( sleep 2; qg_marker "$QG_PR" ) & local bg=$! out   # fixed-sleep-ok: the delayed writer IS the fixture (the watcher writes its marker late)
  out="$(pag "$1" "$QG_RF" "$QG_ITEM" "$QG_PR" --wait 5)"
  wait "$bg" 2>/dev/null; printf '%s' "$out"
}
p_never()   { qg_parked; qg_state OPEN; rm -f "$QG_MK"; pag "$1" "$QG_RF" "$QG_ITEM" "$QG_PR" --wait 1; }
P_OPEN="rc=0 ask — fix-now allowed: PR OPEN, parked awaiting_merge, merge watcher armed"
P_STATES="|rc=0 ask — fix-now unavailable: PR MERGED|rc=0 ask — fix-now unavailable: PR CLOSED|rc=0 ask — fix-now unavailable: PR state DRAFT"
P_GHFAIL="rc=0 ask — fix-now unavailable: PR state unreadable|rc=0 ask — fix-now unavailable: PR state unreadable"
P_DONE="rc=0 ask — fix-now unavailable: closed out"
P_RUNNING="rc=0 refuse — park not written: ## Current status running, not awaiting_merge"
P_MARKER="rc=0 refuse — no merge-watch marker for this PR within 0s|rc=0 refuse — no merge-watch marker for this PR within 0s"
P_FOREIGN="rc=0 refuse — ## Current is .supervisor/requirements/x/02-b.md ($QG_PR), not this item/PR|rc=0 refuse — ## Current is $QG_ITEM ($QG_PR2), not this item/PR"
P_MISSING="rc=0 refuse — run file not found or unreadable: $QG/auto/absent.md|rc=0 refuse — no ## Current item line"
P_USAGE="rc=1 |rc=1 |rc=1 |rc=1 |rc=1 "
P_NEVER="rc=0 refuse — no merge-watch marker for this PR within 1s"
qg_is "QG2a park-ask-gate parked awaiting_merge + marker for this PR + gh OPEN ⇒ fix-now allowed (a ./ item spelling matches)" "$(p_open "$H")" "$P_OPEN"
p_ro() {  # <helper> — `unchanged` when one park-ask-gate call left the run file and marker byte-identical
  local a b; qg_parked; qg_state OPEN; a="$(cksum < "$QG_RF")"; b="$(cksum < "$QG_MK")"
  pag "$1" "$QG_RF" "$QG_ITEM" "$QG_PR" --wait 1 >/dev/null
  if [ "$(cksum < "$QG_RF")" = "$a" ] && [ "$(cksum < "$QG_MK")" = "$b" ]; then printf unchanged; else printf changed; fi
}
qg_is "QG2a' park-ask-gate is READ-ONLY: run file and marker byte-unchanged" "$(p_ro "$H")" unchanged
qg_is "QG2b park-ask-gate MERGED / CLOSED / any other state ⇒ fix-now unavailable (exact OPEN only)" "$(p_states "$H")" "$P_STATES"
qg_is "QG2c park-ask-gate gh pr view failing, or a body with no state ⇒ fix-now unavailable: state unreadable (fail closed, unlike reconcile-item)" "$(p_ghfail "$H")" "$P_GHFAIL"
qg_is "QG2d park-ask-gate item closed out (status done) ⇒ ask — fix-now unavailable: closed out" "$(p_done "$H")" "$P_DONE"
qg_is "QG2e park-ask-gate park not written (status running) ⇒ refuse (park before ask)" "$(p_running "$H")" "$P_RUNNING"
qg_is "QG2f park-ask-gate no marker / a marker for another PR ⇒ refuse" "$(p_marker "$H")" "$P_MARKER"
qg_is "QG2g park-ask-gate ## Current naming another item / another PR ⇒ refuse" "$(p_foreign "$H")" "$P_FOREIGN"
qg_is "QG2h park-ask-gate missing run file ⇒ refuse naming it; no ## Current item line ⇒ refuse" "$(p_missing "$H")" "$P_MISSING"
qg_parked; chmod 000 "$QG_RF"
if [ -r "$QG_RF" ]; then ok "QG2h' unreadable-run-file leg not applicable (running as a user that reads mode-000 files)"
else qg_is "QG2h' park-ask-gate unreadable run file ⇒ refuse" "$(pag "$H" "$QG_RF" "$QG_ITEM" "$QG_PR")" "rc=0 refuse — run file not found or unreadable: $QG_RF"; fi
chmod 644 "$QG_RF"
qg_is "QG2i park-ask-gate usage errors (missing pr, non-integer --wait, unknown option, --wait without a value, a 4th positional) ⇒ exit 1, nothing on stdout" "$(p_usage "$H")" "$P_USAGE"
QG_T0="$(date +%s)"; QG_GOT="$(p_delayed "$H")"; QG_DT=$(( $(date +%s) - QG_T0 ))
qg_is "QG2j park-ask-gate --wait 5 with the marker written ~2s later ⇒ ask (the watcher's async marker race)" "$QG_GOT" "$P_OPEN"
if [ "$QG_DT" -lt 5 ]; then ok "QG2j' it answered when the marker appeared (${QG_DT}s), not at the deadline"; else no "QG2j' it waited the full deadline (${QG_DT}s)"; fi
QG_T0="$(date +%s)"; QG_GOT="$(p_never "$H")"; QG_DT=$(( $(date +%s) - QG_T0 ))
qg_is "QG2k park-ask-gate --wait 1 and the marker never appears ⇒ refuse" "$QG_GOT" "$P_NEVER"
if [ "$QG_DT" -ge 1 ]; then ok "QG2k' it polled for the --wait window (${QG_DT}s)"; else no "QG2k' it did not wait (${QG_DT}s)"; fi
qg_mut_check "QG2a: gh never read (always fail closed)" '  if ! view="$("$GH" pr view "$pr" --json state 2>/dev/null)"; then' '  if true; then' p_open "$P_OPEN"
qg_mut_check "QG2b: exact-OPEN dropped (any readable state allows fix-now)" '    OPEN) echo "ask — fix-now allowed' '    ?*) echo "ask — fix-now allowed: PR OPEN, parked awaiting_merge, merge watcher armed" ;;' p_states "$P_STATES"
qg_mut_check "QG2c: a failed gh pr view treated as OPEN" '    echo "ask — fix-now unavailable: PR state unreadable"; return 0' "    view='{\"state\":\"OPEN\"}'" p_ghfail "$P_GHFAIL"
qg_mut_check "QG2d: done arm deleted" '    done) echo "ask — fix-now unavailable: closed out"; return 0 ;;' __DELETE__ p_done "$P_DONE"
qg_mut_check "QG2e: item-status check deleted" '    *) echo "refuse — park not written:' '    *) ;;' p_running "$P_RUNNING"
qg_mut_check "QG2f: merge-watch marker check deleted" '  if [ -n "$mp" ] && [ "$mp" = "$pr" ]; then echo "judged"; else echo "need_marker"; fi' '  echo "judged"' p_marker "$P_MARKER"
qg_mut_check "QG2g: item/PR match deleted" '  if [ "${ci#./}" != "${item#./}" ] || [ "$cp" != "$pr" ]; then' '  if false; then' p_foreign "$P_FOREIGN"
qg_mut_check "QG2h: run-file readability check deleted" '  if [ ! -f "$rf" ] || [ ! -r "$rf" ]; then echo "refuse — run file not found' __DELETE__ p_missing "$P_MISSING"
qg_mut_check "QG2i: usage die neutered" '    || die "park-ask-gate: usage:' '    || true' p_usage "$P_USAGE"
qg_mut_check "QG2j: --wait ignored (judge once)" '        wait="$2"; shift 2 ;;' '        shift 2 ;;' p_delayed "$P_OPEN"
qg_mut_check "QG2a': the judge appends to the run file" '  [ -n "$line" ] || { echo "refuse — no ## Current item line"; return 0; }' '  printf x >> "$rf"; [ -n "$line" ] || { echo "refuse — no ## Current item line"; return 0; }' p_ro unchanged
qg_mut_check "QG2a': the judge appends to the merge-watch marker" '  mp="$(awk -F' "  printf x >> \"\$marker\"; mp=\"\$(awk -F'\\t' '\$1 == \"pr_url\" { print \$2; exit }' \"\$marker\" 2>/dev/null || true)\"" p_ro unchanged
qg_mut_check "QG2k: no-marker refusal turned into a pass" '    need_marker) echo "refuse — no merge-watch marker' '    need_marker) ;;' p_never "$P_NEVER"

# ---- QG3. park-first order (AC5, AC9): the sequential interactive READY park writes the park, arms
# the watcher and releases the run lock BEFORE park-ask-gate --wait 75, and park-ask-gate runs before
# the ask. automate-speed/08 retired the --legacy prose that held this order as a numbered list; the
# order now lives in scripts/automate-next-step.sh — its `park` step (park write, watcher, release,
# then the park-first hand-off to `decide`) and the post-park entry of its `decide` step (the gate
# read, then the ask). QG_LOOP is that driver; qg_list prints the two bodies in execution order and
# every mutant below is a driver copy (non-empty, differs, no line lost, `bash -n`).
QG_LEAD='  # first entry: the post-park gate read (park-first), then the queue'
QG_LOOP="$HERE/automate-next-step.sh"
qg_list() {
  awk '/^ns_park\(\) \{/ { f = 1 } f { print } f && /^}/ { exit }' "$1"
  QG_H="$QG_LEAD" awk 'BEGIN { h = ENVIRON["QG_H"] } $0 == h { f = 1 } f { print } f && /^}/ { exit }' "$1"
}
qg_idx() { local n; n="$(grep -n${3:-} -m1 -F -- "$2" "$1" 2>/dev/null)"; n="${n%%:*}"; echo "${n:-0}"; }
qg_order() {  # <driver> — prints the verdict line the leg compares
  local L p w r d g a
  L="$QG/list.md"; qg_list "$1" > "$L"
  p="$(qg_idx "$L" '--status "$kind" --pr "$PR"')"; w="$(qg_idx "$L" 'ns_watch; ns_notify awaiting_merge')"
  r="$(qg_idx "$L" '  ns_release' x)"; d="$(qg_idx "$L" 'then NEXT=decide; return 0; fi')"
  g="$(qg_idx "$L" "park-ask-gate")"; a="$(qg_idx "$L" "ns_decide_next_batch && return 0")"
  if [ "$p" -gt 0 ] && [ "$w" -gt 0 ] && [ "$r" -gt 0 ] && [ "$d" -gt 0 ] && [ "$g" -gt 0 ] && [ "$a" -gt 0 ] \
     && [ "$p" -lt "$d" ] && [ "$w" -lt "$d" ] && [ "$r" -lt "$d" ] && [ "$d" -lt "$g" ] && [ "$g" -lt "$a" ] \
     && grep -qF -- "--wait 75" < <(grep -F -m1 -- "park-ask-gate" "$L"); then
    echo "park-first"
  else
    echo "bad order: park=$p watcher=$w release=$r handoff=$d gate=$g ask=$a"
  fi
}
qg_is "QG3a automate-next-step.sh park-first order: park write, watcher, lock release precede the decide hand-off, then park-ask-gate --wait 75, then the ask" "$(qg_order "$QG_LOOP")" "park-first"
QG_CITED='# step: park — the park writes, then watcher / notify / run-lock release'
qg_lead() { if [ "$(grep -cxF -- "$QG_LEAD" "$1")" = 1 ] && grep -qxF -- "$QG_CITED" "$1"; then printf ok; else printf bad; fi; }
qg_is "QG3a' the post-park lead line is unique and the park step's banner is byte-unchanged" "$(qg_lead "$QG_LOOP")" ok
qg_drv_check() {  # <label> <mutant> <scenario_fn> <expected> — qg_prose_check + `bash -n` (a driver copy)
  if bash -n "$2" 2>/dev/null; then qg_prose_check "$1" "$QG_LOOP" "$2" "$3" "$4"; else no "QG driver mutant ($1) not gated (bash -n failed)"; rm -f "$2"; fi
}
QG_H="$QG_LEAD" awk 'BEGIN { h = ENVIRON["QG_H"] } { print } !d && $0 == h { d = 1; print }' "$QG_LOOP" > "$QG/lead-dup.sh"
qg_drv_check "QG3a': the lead line duplicated" "$QG/lead-dup.sh" qg_lead ok
QG_H="$QG_CITED" awk 'BEGIN { h = ENVIRON["QG_H"] } $0 == h { $0 = "# step: park — the park writes, then notify / run-lock release" } { print }' "$QG_LOOP" > "$QG/heading-mut.sh"
qg_drv_check "QG3a': the park step's banner altered" "$QG/heading-mut.sh" qg_lead ok
# qg_move <out> <target line> — a driver copy with the park-ask-gate --wait 75 line moved to just
# before line <target> (or after it, when <target> is negative: -N) — the Pin-mutations row.
qg_move() {
  local gl; gl="$(qg_idx "$QG_LOOP" 'park-ask-gate "$RF" "$ITEM" "$PR" --wait 75')"
  QG_G="$gl" QG_T="$2" awk 'BEGIN { g = ENVIRON["QG_G"] + 0; t = ENVIRON["QG_T"] + 0 }
    FNR == NR { if (FNR == g) held = $0; next }
    FNR == g { next }
    t > 0 && FNR == t { print held }
    { print }
    t < 0 && FNR == -t { print held }' "$QG_LOOP" "$QG_LOOP" > "$1"
}
qg_prose_mut() {  # <label> <target line> — the order leg must turn red on the moved copy
  local m="$QG/loop-mutant.sh"
  qg_move "$m" "$2"
  if [ "$2" != 0 ] && [ "$2" != -0 ] && [ -s "$m" ] && ! cmp -s "$QG_LOOP" "$m" && [ "$(wc -l < "$m")" = "$(wc -l < "$QG_LOOP")" ] && bash -n "$m" 2>/dev/null; then
    if [ "$(qg_order "$m")" != "park-first" ]; then ok "QG3 driver mutant ($1) turns the order leg red: $(qg_order "$m")"; else no "QG3 driver mutant ($1) did NOT discriminate"; fi
  else
    no "QG3 driver mutant ($1) not gated (empty, identical, a line was lost, or bash -n failed)"
  fi
  rm -f "$m"
}
QG_PK="$(qg_idx "$QG_LOOP" 'ns_park() {')"; QG_DL="$(qg_idx "$QG_LOOP" "$QG_LEAD" x)"
qg_after() { local n; n="$(awk -v s="$2" -v t="$3" 'NR > s && index($0, t) { print NR; exit }' "$1")"; echo "${n:-0}"; }
qg_t() {  # <after line> <anchor> <offset> — the target line, or 0 when the anchor is missing
  local n; n="$(qg_after "$QG_LOOP" "$1" "$2")"; if [ "$1" -gt 0 ] && [ "$n" -gt 0 ]; then echo $((n + $3)); else echo 0; fi
}
qg_prose_mut "park-ask-gate moved before the park write" "$(qg_t "$QG_PK" '--status "$kind" --pr "$PR"' 0)"
qg_prose_mut "park-ask-gate moved before the watcher arm" "$(qg_t "$QG_PK" 'ns_progress "$line" || return 1' 1)"
qg_prose_mut "park-ask-gate moved before the lock release" "$(qg_t "$QG_PK" 'then NEXT=decide; return 0; fi' -1)"
qg_prose_mut "park-ask-gate moved after the ask" "-$(qg_t "$QG_DL" 'ns_decide_next_batch && return 0' 0)"

# ---- QG4. intake prose (AC2): §2 "--limit N" calls queue-confirm, asks AUT-QUEUE only on `ask`,
# and appends ONE `skipped AUT-QUEUE: <reason>` line on a skip.
qg_intake() {  # <md> — 0 when the --limit N section wires queue-confirm as AC2 says
  grep -qF -- 'skipped AUT-QUEUE: backlog queue <n> ≤ limit <N>' < <(awk '/^### `--limit N`/ { f = 1 } f' "$1" \
    | grep -F -- 'automate-helpers.sh queue-confirm <source> <n> <limit>' | grep -F -- '`ask` ⇒ ask `AUT-QUEUE`' | grep -F -- 'skipped AUT-QUEUE: <reason>')
}
qg_intake "$QG_INTAKE" && ok "QG4 intake.md --limit N: queue-confirm decides, AUT-QUEUE only on ask, one skipped AUT-QUEUE line on skip" || no "QG4 intake.md --limit N does not wire queue-confirm"
awk '{ gsub(/automate-helpers\.sh queue-confirm/, "automate-helpers.sh resolve-backlog") } { print }' "$QG_INTAKE" > "$QG/intake-mutant.md"
if [ -s "$QG/intake-mutant.md" ] && ! cmp -s "$QG_INTAKE" "$QG/intake-mutant.md"; then
  qg_intake "$QG/intake-mutant.md" && no "QG4 prose mutant (queue-confirm call removed) did NOT discriminate" || ok "QG4 prose mutant (queue-confirm call removed) turns the intake leg red"
else
  no "QG4 prose mutant not gated (empty or identical)"
fi
rm -rf "$QG"
