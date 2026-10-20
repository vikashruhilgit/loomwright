echo "== LANE. parallel-automate/05 engine seams: resume-glob -L<n> skip, lane self-resume, ready_for_release, current-wave, lane dispatch arms =="
LN_T="$(mktemp -d)"; LN_A="$LN_T/p/.supervisor/automate"; mkdir -p "$LN_A"
printf '# Automate Run: par-1 — queue\n## Status: running\n' > "$LN_A/par-1.md"
printf '# Automate Run: par-1-L1 — .supervisor/requirements/q/a.md\n## Status: running\n' > "$LN_A/par-1-L1.md"
printf '# Automate Run: par-1-L2 — .supervisor/requirements/q/b.md\n## Status: done\n' > "$LN_A/par-1-L2.md"
printf '# Automate Run: par-1-Lx — not-a-lane-id\n## Status: running\n' > "$LN_A/par-1-Lx.md"
run_h bash "$H" resume-glob "$LN_A"
ln_exp="$(printf '%s\n' "$LN_A/par-1-Lx.md" "$LN_A/par-1.md" | env LC_ALL=C sort)"
if [ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "$ln_exp" ]; then ok "LANE resume-glob (primary): an unfinished AND a finished -L<n> lane run file are never listed; a non-digit -Lx id is"; else no "LANE resume-glob primary wrong (rc=$RUN_RC):\n$RUN_OUT"; fi
run_h bash "$H" resume-glob "$LN_A" --finalize
if [ "$RUN_OUT" = "$ln_exp" ]; then ok "LANE resume-glob --finalize (primary): lane run files are not candidates either"; else no "LANE resume-glob --finalize primary wrong:\n$RUN_OUT"; fi
# Mutation control (AC16, Scope 11): the same bundle without the -L<n> skip lists the lane files.
LN_MUT="$(dirname "$H")/lane-skip-mutant.sh"
sed '/^    _resume_lane_skip "\$f" "\$own" && continue$/d' "$H" > "$LN_MUT"
if ! cmp -s "$H" "$LN_MUT" && bash -n "$LN_MUT"; then
  ln_mo="$(bash "$LN_MUT" resume-glob "$LN_A" 2>/dev/null)"
  if [ "$ln_mo" != "$ln_exp" ] && grep -qxF "$LN_A/par-1-L1.md" <<<"$ln_mo"; then ok "LANE mutation control: dropping the -L<n> skip lists the lane run file — the primary assertion is load-bearing"; else no "LANE mutation control inconclusive: '$ln_mo'"; fi
else
  no "LANE mutation control: could not build the mutant (sed did not apply / bash -n failed)"
fi
rm -f "$LN_MUT"
# Lane-id shape (D2/D3: <parent_run_id>-L<n> of a real parent): an engine-minted parent id is a lane
# run even with no parent file beside it; a hand-made id merely ending -L<n> with no such parent stays listed.
LN_B="$LN_T/b/.supervisor/automate"; mkdir -p "$LN_B"
printf '# Automate Run: nightly-L3 — hand-made run\n## Status: running\n' > "$LN_B/nightly-L3.md"
printf '# Automate Run: automate-2026-10-07-170659-L1 — .supervisor/requirements/q/a.md\n## Status: running\n' > "$LN_B/automate-2026-10-07-170659-L1.md"
run_h bash "$H" resume-glob "$LN_B"
if [ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "$LN_B/nightly-L3.md" ]; then ok "LANE resume-glob: a hand-made nightly-L3 (no nightly run beside it) is listed; an automate-YYYY-MM-DD-HHMMSS-L1 lane run is skipped"; else no "LANE resume-glob lane-id shape wrong (rc=$RUN_RC):\n$RUN_OUT"; fi
printf '# Automate Run: nightly — the parent\n## Status: done\n' > "$LN_B/nightly.md"
run_h bash "$H" resume-glob "$LN_B"
if [ "$RUN_RC" -eq 0 ] && [ -z "$RUN_OUT" ]; then ok "LANE resume-glob: nightly-L3 IS skipped once a run titled nightly (its parent, even finished) sits beside it"; else no "LANE resume-glob parent-present shape wrong (rc=$RUN_RC):\n$RUN_OUT"; fi
# Inside a lane clone: its own run IS listed, nothing else (other lanes, the parent's run).
printf '{"schema_version":1,"lane":"L1","run_id":"par-1-L1","parent_run_id":"par-1"}\n' > "$LN_T/p/.supervisor/lane.json"
run_h bash "$H" resume-glob "$LN_A"
if [ "$RUN_OUT" = "$LN_A/par-1-L1.md" ]; then ok "LANE resume-glob (lane clone): exactly its own run is listed"; else no "LANE resume-glob lane wrong:\n$RUN_OUT"; fi
run_h bash "$H" resume-glob "$LN_A" --finalize
if [ "$RUN_OUT" = "$LN_A/par-1-L1.md" ]; then ok "LANE resume-glob --finalize (lane clone): only its own run is a candidate"; else no "LANE resume-glob --finalize lane wrong:\n$RUN_OUT"; fi
printf '{}\n' > "$LN_T/p/.supervisor/lane.json"
run_h bash "$H" resume-glob "$LN_A"
if [ "$RUN_RC" -eq 0 ] && [ -z "$RUN_OUT" ]; then ok "LANE resume-glob: a lane.json with no run_id lists nothing (fail closed — never another run)"; else no "LANE unreadable lane.json listed: $RUN_OUT"; fi
# ready_for_release + current-wave (Scope 2, Scope 5)
LN_RF="$LN_T/r.md"
printf '# Automate Run: par-1-L1 — a.md\n## Status: running\n## Queue\n- [ ] a.md\n## Current\n- item: a.md | status: running | pr: null | branch: null\n- pause_reason: null\n\n## Progress\n- t0 run created\n' > "$LN_RF"
run_h bash "$H" current-set "$LN_RF" --item a.md --status ready_for_release --pr https://github.com/acme/widgets/pull/9 --pause-reason ready_for_release
if [ "$RUN_RC" -eq 0 ] && grep -qxF -- "- item: a.md | status: ready_for_release | pr: https://github.com/acme/widgets/pull/9 | branch: null" "$LN_RF" && grep -qxF -- "- pause_reason: ready_for_release" "$LN_RF"; then ok "LANE current-set accepts ready_for_release as status AND pause_reason"; else no "LANE current-set ready_for_release refused (rc=$RUN_RC): $(tr '\n' '|' < "$LN_RF")"; fi
run_h bash "$H" current-wave "$LN_RF" --wave 1 --items "a.md,b.md"
if [ "$RUN_RC" -eq 0 ] && [ "$(grep -c '^- wave:' "$LN_RF")" = 1 ] && grep -qxF -- "- wave: 1 | items: a.md, b.md" "$LN_RF" \
   && [ "$(awk '/^## Current/{c=1;next} /^## /{c=0} c && NF' "$LN_RF" | tail -n1)" = "- wave: 1 | items: a.md, b.md" ]; then ok "LANE current-wave writes one '- wave:' line at the end of ## Current"; else no "LANE current-wave wrong (rc=$RUN_RC): $(tr '\n' '|' < "$LN_RF")"; fi
cp "$LN_RF" "$LN_T/ref"
run_h bash "$H" current-wave "$LN_RF" --wave 1 --items "a.md, b.md"
if [ "$RUN_OUT" = "current-wave: unchanged" ] && cmp -s "$LN_T/ref" "$LN_RF"; then ok "LANE current-wave: the same wave (either comma spelling) is unchanged, byte-identical"; else no "LANE current-wave not idempotent: $RUN_OUT"; fi
run_h bash "$H" current-wave "$LN_RF" --wave 2 --items c.md
if [ "$(grep -c '^- wave:' "$LN_RF")" = 1 ] && grep -qxF -- "- wave: 2 | items: c.md" "$LN_RF"; then ok "LANE current-wave replaces the line in place"; else no "LANE current-wave replace wrong: $(tr '\n' '|' < "$LN_RF")"; fi
cp "$LN_RF" "$LN_T/ref"; ln_bad=""
for ln_args in "--wave 0" "--wave x" "--wave 1 --items a|b" "--wave null --items a.md" "--items a.md" "--wave"; do
  # shellcheck disable=SC2086
  run_h bash "$H" current-wave "$LN_RF" $ln_args
  { [ "$RUN_RC" -eq 1 ] && cmp -s "$LN_T/ref" "$LN_RF"; } || ln_bad="$ln_bad [$ln_args rc=$RUN_RC]"
done
if [ -z "$ln_bad" ]; then ok "LANE current-wave: every refusal exits 1 with the file byte-unchanged"; else no "LANE current-wave refusals wrong:$ln_bad"; fi
run_h bash "$H" current-wave "$LN_RF" --wave null
if [ "$RUN_RC" -eq 0 ] && ! grep -q '^- wave:' "$LN_RF"; then ok "LANE current-wave --wave null removes the line"; else no "LANE current-wave null did not remove"; fi
# Dispatch: every Subtask-1 lane subcommand reaches automate-lanes.sh (help lines present, never 'unknown subcommand').
ln_bad=""
for ln_s in lane-create lane-launch relay-hook lane-answer lane-remove lane-info lane-park lane-drain-check init-check pick-guard branch-check current-wave; do
  grep -q "^  $ln_s " <<<"$(bash "$H" --help)" || ln_bad="$ln_bad help:$ln_s"
done
for ln_s in lane-create lane-launch lane-answer lane-remove lane-info lane-park lane-drain-check init-check pick-guard branch-check; do
  awk -v w="$ln_s" 'index($0, "/automate-lanes.sh\" \"$cmd\" \"$@\" ;;") && /^    [a-z|-]+\) exec bash / { l=$1; sub(/\)$/, "", l); n=split(l, a, "|"); for (i=1;i<=n;i++) if (a[i]==w) f=1 } END { exit !f }' "$H" || ln_bad="$ln_bad arm:$ln_s"
done
(cd "$LN_T" && bash "$H" lane-info --root "$LN_T" </dev/null >/dev/null 2>"$LN_T/li.err"); ln_rc=$?
grep -q 'unknown subcommand' "$LN_T/li.err" && ln_bad="$ln_bad lane-info-unrouted"
if [ -z "$ln_bad" ] && [ "$ln_rc" -eq 1 ]; then ok "LANE dispatch: lane subcommands have help lines + exec arms to automate-lanes.sh; lane-info outside a lane exits 1"; else no "LANE dispatch wrong (lane-info rc=$ln_rc):$ln_bad"; fi
rm -rf "$LN_T"
echo "== SINGLELANE. twin-remediation/08b: current-set refuses the ready_for_release park in a single_lane checkout =="
SLH="$(mktemp -d)"; SLH="$(cd "$SLH" && pwd -P)"
sl_h_rf() { # <checkout> — a run file in <checkout>/.supervisor/automate/ with an item running
  mkdir -p "$1/.supervisor/automate"
  printf '# Automate Run: sl-1 — queue\n## Status: running\n## Queue\n- [ ] a.md\n## Current\n- item: a.md | status: running | pr: null | branch: null\n- pause_reason: null\n\n## Progress\n- t0 picked a.md\n' > "$1/.supervisor/automate/sl-1.md"
}
sl_h_rf "$SLH/single"; printf '{"schema_version": 1, "lane": "L1", "single_lane": true}\n' > "$SLH/single/.supervisor/lane.json"
sl_h_rf "$SLH/multi"; printf '{"schema_version": 1, "lane": "L1", "parallel": 2}\n' > "$SLH/multi/.supervisor/lane.json"
sl_h_rf "$SLH/false"; printf '{"schema_version": 1, "lane": "L1", "single_lane": false}\n' > "$SLH/false/.supervisor/lane.json"
sl_h_rf "$SLH/none"
SLRF="$SLH/single/.supervisor/automate/sl-1.md"; cp "$SLRF" "$SLH/ref"
sl_bad=""
for sl_args in "--item a.md --status ready_for_release --pr https://x/pull/1" "--item a.md --status ready_for_release --pause-reason ready_for_release" "--pause-reason ready_for_release" "--item a.md --status awaiting_merge --pause-reason ready_for_release"; do
  # shellcheck disable=SC2086
  sl_err="$(bash "$H" current-set "$SLRF" $sl_args 2>&1 >/dev/null)"; sl_rc=$?
  { [ "$sl_rc" -eq 1 ] && cmp -s "$SLH/ref" "$SLRF" && [ "$(printf '%s\n' "$sl_err" | grep -c .)" = 1 ] && case "$sl_err" in *single_lane*) true ;; *) false ;; esac; } || sl_bad="$sl_bad [$sl_args rc=$sl_rc err=$sl_err]"
done
if [ -z "$sl_bad" ]; then ok "SINGLELANE current-set: ready_for_release (status or pause_reason) in a single_lane checkout ⇒ exit 1, file byte-unchanged, one stderr line naming single_lane"; else no "SINGLELANE refusal wrong:$sl_bad"; fi
run_h bash "$H" current-set "$SLRF" --item a.md --status awaiting_merge --pr https://x/pull/1 --pause-reason awaiting_merge
if [ "$RUN_RC" -eq 0 ] && grep -qxF -- '- item: a.md | status: awaiting_merge | pr: https://x/pull/1 | branch: null' "$SLRF"; then ok "SINGLELANE current-set: the single lane's awaiting_merge park is written"; else no "SINGLELANE awaiting_merge park refused (rc=$RUN_RC)"; fi
sl_bad=""
for sl_d in multi false none; do
  sl_rf="$SLH/$sl_d/.supervisor/automate/sl-1.md"
  run_h bash "$H" current-set "$sl_rf" --item a.md --status ready_for_release --pause-reason ready_for_release
  { [ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "current-set: written" ] && grep -qxF -- '- pause_reason: ready_for_release' "$sl_rf"; } || sl_bad="$sl_bad ready:$sl_d"
  run_h bash "$H" current-set "$sl_rf" --item a.md --status awaiting_merge --pause-reason awaiting_merge
  { [ "$RUN_RC" -eq 0 ] && grep -qxF -- '- pause_reason: awaiting_merge' "$sl_rf"; } || sl_bad="$sl_bad merge:$sl_d"
done
if [ -z "$sl_bad" ]; then ok "SINGLELANE current-set unchanged without the key: no lane.json, a lane.json without single_lane, single_lane false — ready_for_release and awaiting_merge both written"; else no "SINGLELANE current-set changed off the single lane:$sl_bad"; fi
rm -rf "$SLH"
echo "== LANEGUARD. parallel-automate/05 AC12: the lane guard is wired into the DEFAULT path (sequential PICK + new-run start), not only §14 =="
LG_T="$(mktemp -d)"; mkdir -p "$LG_T/auto"
run_h bash "$H" pick-guard "$LG_T/auto"
if [ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "ok" ]; then ok "LANEGUARD pick-guard on a dir with no *.lanes table prints exactly 'ok', exit 0 (the no-flag path's output is unchanged)"; else no "LANEGUARD pick-guard no-table wrong (rc=$RUN_RC): '$RUN_OUT'"; fi
# live_lane is a RUN-level pause_reason current-set accepts (run-level form: item line byte-unchanged).
LG_RF="$LG_T/r.md"
printf '# Automate Run: seq-1 — queue\n## Status: paused\n## Queue\n- [ ] a.md\n## Current\n- item: a.md | status: running | pr: null | branch: null\n- pause_reason: null\n\n## Progress\n- t0 run created\n' > "$LG_RF"
lg_item0="$(grep '^- item: ' "$LG_RF")"
run_h bash "$H" current-set "$LG_RF" --pause-reason live_lane
if [ "$RUN_RC" -eq 0 ] && grep -qxF -- '- pause_reason: live_lane' "$LG_RF" && [ "$(grep '^- item: ' "$LG_RF")" = "$lg_item0" ]; then ok "LANEGUARD current-set accepts --pause-reason live_lane (run-level form, item line unchanged)"; else no "LANEGUARD current-set live_lane refused (rc=$RUN_RC): $(tr '\n' '|' < "$LG_RF")"; fi
# phase_relay_unavailable (automate-speed/09) is the PICK-time phase-guard's RUN-level park: the same run-level form
run_h bash "$H" current-set "$LG_RF" --pause-reason phase_relay_unavailable
if [ "$RUN_RC" -eq 0 ] && grep -qxF -- '- pause_reason: phase_relay_unavailable' "$LG_RF" && [ "$(grep '^- item: ' "$LG_RF")" = "$lg_item0" ]; then ok "PHASEGUARD current-set accepts --pause-reason phase_relay_unavailable (run-level form, item line unchanged)"; else no "PHASEGUARD current-set phase_relay_unavailable refused (rc=$RUN_RC): $(tr '\n' '|' < "$LG_RF")"; fi
# Every enum copy carries live_lane (runfile.sh validator, SKILL §3 template, automate-run.md template); the
# two templates pin the tail exactly — live_lane, then phase_relay_unavailable (automate-speed/09), then null.
lg_bad=""
grep -q '^CURRENT_PAUSE_ENUM=.* live_lane ' "$HERE/automate-helpers.d/runfile.sh" || lg_bad="$lg_bad runfile.sh"
grep -q '^- pause_reason: .*|live_lane|phase_relay_unavailable|null$' "$SKILL_FILE" || lg_bad="$lg_bad SKILL§3"
grep -q '^- pause_reason: .*|live_lane|phase_relay_unavailable|null$' "$RUN_DOC" || lg_bad="$lg_bad automate-run.md"
grep -qF -- '`meta_unreachable`, `closeout_leftover`, `live_lane` | `current-set <rf> --pause-reason <reason>`' "$SKILL_FILE" || lg_bad="$lg_bad SKILL-transition-table"
if [ -z "$lg_bad" ]; then ok "LANEGUARD live_lane is in every pause_reason enum copy"; else no "LANEGUARD live_lane missing from:$lg_bad"; fi
# Prose seams (same helper on the real SKILL and on a mutant, like G7): §6 step 1's PICK-time run-lock
# paragraph runs pick-guard AFTER the acquire and parks live_lane with the lock released; §4's start
# order runs init-check before meta-entry and pick-guard for a new run.
lg_pick_seam() {  # <skill_path> — 0 when the PICK-time run-lock paragraph wires the lane guard after the acquire
  local line; line="$(grep -F -- '**PICK-time run-lock acquire' "$1" | head -1)"
  [ -n "$line" ] || return 1
  case "$line" in *'run-lock.sh acquire'*'automate-helpers.sh pick-guard .supervisor/automate'*'--pause-reason live_lane'*'run-lock.sh release'*'no `trail-pr`'*) return 0 ;; *) return 1 ;; esac
}
lg_start_seam() {  # <skill_path> — 0 when §4's start order runs init-check first and pick-guard for a new run
  local line; line="$(grep -F -- '**Start order (automate-followups/32):**' "$1" | head -1)"
  [ -n "$line" ] || return 1
  case "$line" in *'`init-check` (only when `--parallel` was passed) → `meta-entry`'*'`pick-guard` (a NEW run only, before §2'"'"'s intake)'*'automate-helpers.sh pick-guard .supervisor/automate'*) return 0 ;; *) return 1 ;; esac
}
lg_pick_seam "$SKILL_FILE" && ok "LANEGUARD prose seam: SKILL §6 step 1 PICK runs pick-guard after the run-lock acquire, parks live_lane, releases the lock, no trail-pr" || no "LANEGUARD §6 step 1 PICK does not wire pick-guard"
lg_start_seam "$SKILL_FILE" && ok "LANEGUARD prose seam: SKILL §4 start order runs init-check first (with --parallel) and pick-guard before a new run's intake" || no "LANEGUARD §4 start order does not wire init-check/pick-guard"
awk 'index($0,"**PICK-time run-lock acquire") {gsub(/pick-guard/,"guard_removed")} {print}' "$SKILL_FILE" > "$LG_T/no-pick.md"
awk 'index($0,"**Start order (automate-followups/32):**") {gsub(/pick-guard/,"guard_removed")} {print}' "$SKILL_FILE" > "$LG_T/no-start.md"
if ! cmp -s "$SKILL_FILE" "$LG_T/no-pick.md" && ! lg_pick_seam "$LG_T/no-pick.md" && lg_start_seam "$LG_T/no-pick.md"; then ok "LANEGUARD (mutant) pick-guard gone from §6 PICK only ⇒ PICK pin red, start pin green"; else no "LANEGUARD PICK mutant not discriminated"; fi
if ! cmp -s "$SKILL_FILE" "$LG_T/no-start.md" && ! lg_start_seam "$LG_T/no-start.md" && lg_pick_seam "$LG_T/no-start.md"; then ok "LANEGUARD (mutant) pick-guard gone from §4 start only ⇒ start pin red, PICK pin green"; else no "LANEGUARD start mutant not discriminated"; fi
# §14's intro no longer claims "no automate-lanes.sh call" without naming the pick-guard exception.
# twin-remediation/08b: the sentence no longer folds N = 1 into "no lane code path" — `--parallel 1` is single-lane mode.
lg_intro="$(grep -F -- '**Without the flag, no lane code path is entered**' "$SKILL_FILE" | head -1)"
case "$lg_intro" in *'except the read-only `pick-guard`'*'**`--parallel 1` is single-lane mode**'*) ok "LANEGUARD §14 intro names the pick-guard exception and states single-lane mode for N = 1" ;; *) no "LANEGUARD §14 intro contradicts the default-path pick-guard or omits single-lane mode: $lg_intro" ;; esac
rm -rf "$LG_T" "$SPLIT_D"

