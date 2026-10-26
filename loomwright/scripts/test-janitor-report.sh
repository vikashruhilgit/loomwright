#!/usr/bin/env bash
# test-janitor-report.sh — self-tests for loomwright/scripts/janitor-report.sh (the /janitor report and act).
# Isolated: one mktemp -d holds every fixture (git repos, lane dirs, registry, CI-slot state); gh and lsof
# are PATH stubs; the process snapshot is the LOOMWRIGHT_PROC_PS_SNAPSHOT seam (live `ps -p` rows of this
# test's own fixture processes plus synthetic rows); every fixture process is a background child of this
# shell, tracked with its lstart and killed by its leg and by the EXIT trap.
#
#   leg_report_fixture  (brief AC4) the 2026-10-04 machine state — a leaked fixture server (an unregistered
#        look-alike), an old merge watcher (a registry entry past its max_lifetime_s), a dead run-lock holder
#        and a merged clean plugin-made worktree (gh stub: newest PR MERGED at the tip): each appears exactly
#        once with group, owner, age, state, evidence and a suggested action with its reason; exit 0; the
#        checksum of the registry dir, every .supervisor tree (run locks included), `git worktree list
#        --porcelain` and `git for-each-ref refs/heads` is unchanged.
#   leg_json_checks  (brief AC5, run inside leg_report_fixture) --json prints ONE object, schema_version 1, groups[], every row carrying id, group,
#        what, owner, age_s, state, evidence, action, reason — the same row ids, in the same order, as the
#        text table.
#   leg_report_only  (brief AC6) not-the-plugin's rows (a host background session, a python server) and
#        plugin-adjacent rows (a ci-slot holder, a keep-awake caffeinate) carry action none with a reason, and
#        `act --confirm <id>` refuses each with no signal (the live ci-slot holder stays alive).
#   leg_noninteractive  (brief AC7) `act` without --confirm, with --report, and with CI set acts on nothing:
#        `janitor: report only — <reason>`, exit 0, the look-alike alive, the same checksum.
#   leg_act_stop  (brief AC8) `act --confirm <the leaked server's id>` re-checks it through proc-registry
#        stop-unregistered and stops exactly that process (a second look-alike stays alive), prints what it
#        did and a fresh summary line, and the next report no longer lists it.
#   leg_act_recycled  (brief AC8) a look-alike that execs into ANOTHER look-alike command line after the
#        report is not signalled: refused by act's fresh re-read (its id changed), and — fed the stale
#        snapshot so the row still matches — refused by proc-registry's lstart/hash re-check.
#   leg_live_session  a look-alike whose snapshot ppid chain reaches a live host session (a fake desktop-app
#        `claude` row whose path has a space, through a shell) is action none ("its session is still alive"), its evidence naming its
#        command line, and `act --confirm` refuses it; a pid-1-reparented look-alike keeps stop-unregistered.
#   leg_host_session  a look-alike that IS a live host session (a lane's headless session whose --settings carry a plugin
#        scripts path) is none, "it is a live host session", and so is its look-alike child; a wrapper look-alike
#        with a live host session under it is none, "a live host session runs under it"; act refuses both.
#   leg_snapshot_fail  janitor's own snapshot cannot be taken (TMPDIR missing) while proc-registry takes its
#        own ps: every look-alike and the overdue entry are none, "the live-session check could not run".
#   leg_reap_host  an overdue entry whose pid is a live host session keeps reap, its reason warning that
#        reaping ends that session and its evidence naming the command line; a plain overdue entry has no warning
#        until a live host session runs under it, when its reason names that session.
#   leg_sweep_set  a would-remove set that grows after the report gives every sweep-apply row a new id, so
#        `act --confirm <the old id>` refuses it and removes nothing.
#   leg_lock_reclaim  (brief AC8b) a run lock whose recorded holder is dead and whose age is >= 1800s is
#        gone after `act --confirm <its id>` (`run-lock.sh status` prints UNLOCKED, janitor holds no lock);
#        a lock with a live holder and a dead-holder lock younger than 1800s are refused, unchanged;
#        --force-unlock is refused on the live one and breaks only the young dead one.
#   leg_act_reap  `act --confirm` on the ONE `fin` row of two finished entries prunes both entry files (its
#        multi-id data word-splits into `reap --apply`), and on the overdue watcher's row stops that process.
#   leg_act_sweep  two picked sweep-apply rows run the whole sweep ONCE (the second reads "already applied in
#        this call"), and both merged worktrees are gone.
#   leg_act_lane_remove  a lane whose run says done is a lane-remove row; `act --confirm` removes its clone
#        (salvage kept, the lane table says removed) and leaves the other lanes.
#   leg_act_config_restore  the stranded backup of a done run under a dead-holder lock is config-restore;
#        `act --confirm` puts config.json back byte-for-byte and removes the backup.
#   leg_nostatus  a dead-holder lock >= 1800s whose run file states no `## Status:`, and a config backup whose
#        run file states none, are none ("cannot be judged"), and act refuses both, unchanged.
#   leg_cfg_unjudged  a done run's config backup under a pid-less held primary lock is none ("run lock
#        cannot be judged (held with no recorded pid)"), and act refuses it.
#   leg_usage  bad arguments exit 2; an unknown row id is refused, exit 0.
#   MUTATION CONTROLS (gated per lesson fa32a308: non-empty, byte-differs, parses, a line-delete removes
#   exactly one line), each must turn its leg red: act's report-only guard line deleted (leg_noninteractive),
#   the not-the-plugin's `none` action flipped to stop-unregistered (leg_report_only), the report path
#   writing into the registry dir (leg_report_fixture), the live-session demotion dropped (leg_live_session),
#   the would-remove set dropped from the sweep row identity (leg_sweep_set), the host rule reading only the first word (leg_live_session),
#   the host-session-itself and host-session-below checks dropped (leg_host_session), each snapshot fail-closed
#   dropped (leg_snapshot_fail), the live-host-session and session-below reap warnings dropped (leg_reap_host),
#   act's once-per-call sweep guard dropped (leg_act_sweep), the fin row's ids quoted into one word
#   (leg_act_reap), the lock and config-backup no-status fail-closeds dropped (leg_nostatus), the
#   config-backup unjudgeable-lock fail-closed dropped (leg_cfg_unjudged).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT_REAL="$HERE/janitor-report.sh"
S="$SUT_REAL"
PRS="$HERE/proc-registry.sh"
RLS="$HERE/run-lock.sh"
. "$HERE/wait-lib.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass + 1)); }
no() { echo "  FAIL: $1"; fail=$((fail + 1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/test-janitor-report.XXXXXX")"
WORK="$(cd "$WORK" && pwd -P)"
export LOOMWRIGHT_PROC_REGISTRY_DIR="$WORK/default-registry"
export XDG_STATE_HOME="$WORK/state" LOOMWRIGHT_MACHINE_STATE_DIR="$WORK/machine"
export LOOMWRIGHT_PROC_UNREG_MIN_S=0
unset LOOMWRIGHT_PROC_PS_SNAPSHOT LOOMWRIGHT_RUN_LOCK_SESSION_ID LOOMWRIGHT_HOLDER_PID
# fixture git never prompts, never opens an editor, never signs
export GIT_TERMINAL_PROMPT=0 GIT_EDITOR=true GIT_CONFIG_NOSYSTEM=1
# ... and never depends on an ambient identity: a CI runner has no user.name / user.email and a hostname
# git cannot derive an address from, so `commit-tree` (which takes no -c identity) fails there
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# Fixture processes: tracked in $FIXDIR as <pid> -> its lstart at spawn; cleanup kills one only while that
# lstart still matches, so it never signals a pid the OS has since reused.
FIXDIR="$WORK/fixtures"; mkdir -p "$FIXDIR"
fix_kill() {
  local want cur
  want="$(cat "$FIXDIR/$1" 2>/dev/null)"; rm -f "$FIXDIR/$1"
  cur="$(env TZ=UTC0 LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null)"
  [ -n "$want" ] && [ "$cur" = "$want" ] && kill -9 "$1" 2>/dev/null
  return 0
}
cleanup() {
  local f
  for f in "$FIXDIR"/*; do [ -f "$f" ] && fix_kill "${f##*/}"; done
  rm -rf "$WORK"
}
trap cleanup EXIT

# PATH stubs: gh answers `pr list --head <B>` from $GHDIR/<B with / as _>.json ([] otherwise); lsof is
# the `lsof -a -d cwd -F pn` stand-in (pid 1 at /, so no fixture worktree reads live).
BIN="$WORK/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
[ "${1:-} ${2:-}" = "pr list" ] || { echo '[]'; exit 0; }
h=""; while [ $# -gt 0 ]; do [ "$1" = --head ] && h="${2:-}"; shift; done
f="${GHDIR:-/nonexistent}/$(printf '%s' "$h" | tr '/ ' '__').json"
if [ -f "$f" ]; then cat "$f"; else echo '[]'; fi
exit 0
STUB
cat > "$BIN/lsof" <<'STUB'
#!/usr/bin/env bash
printf 'p1\nfcwd\nn/\n'
exit 0
STUB
chmod +x "$BIN/gh" "$BIN/lsof"
export PATH="$BIN:$PATH"

# --- leg harness ----------------------------------------------------------------------------------------
QUIET=0; LEG_FAIL=0; LEG_PIDS=""
check() {   # check <label> <command…>
  local label="$1"; shift
  if "$@"; then [ "$QUIET" = 1 ] || ok "$label"
  else LEG_FAIL=1; [ "$QUIET" = 1 ] || no "$label"; fi
}
spawn() {
  "$@" </dev/null >/dev/null 2>&1 &
  SP=$!; disown "$SP" 2>/dev/null
  env TZ=UTC0 LC_ALL=C ps -o lstart= -p "$SP" > "$FIXDIR/$SP" 2>/dev/null
  LEG_PIDS="$LEG_PIDS $SP"
}
leg_end() { local p; for p in $LEG_PIDS; do fix_kill "$p"; done; LEG_PIDS=""; }
has() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }
eq() { [ "$1" = "$2" ]; }
lines() { awk 'END { print NR }' "$1"; }
alive() {
  local s
  s="$(ps -o stat= -p "$1" 2>/dev/null | tr -d '[:space:]')"
  [ -n "$s" ] || return 1
  case "$s" in Z*) return 1 ;; esac
  return 0
}
gone() { ! alive "$1"; }
no_lstart() { [ -z "$(ps -o lstart= -p "$1" 2>/dev/null)" ]; }
trimmed() { sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }
lstart_of() { env TZ=UTC0 LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | trimmed; }
cmd_is() { [ "$(ps -ww -o command= -p "$1" 2>/dev/null | trimmed)" = "$2" ]; }
etime_s() {
  ps -o etime= -p "$1" 2>/dev/null | tr -d ' ' | awk '{ d = 0; e = $0
    if (index(e, "-")) { split(e, a, "-"); d = a[1]; e = a[2] }
    n = split(e, p, ":"); s = 0; for (i = 1; i <= n; i++) s = s * 60 + p[i]; print d * 86400 + s }'
}
etime_ge() { local s; s="$(etime_s "$1")"; [ -n "$s" ] && [ "$s" -ge "$2" ]; }
dead_pid() { local p=99999; while kill -0 "$p" 2>/dev/null; do p=$((p - 1)); done; printf '%s' "$p"; }
FAKE_LSTART="Mon Jan  1 00:00:00 2001"
LW="$WORK/lw/loomwright/scripts"; mkdir -p "$LW"
# lookalike <name> <n> — `sleep <n>` whose argv[0] is a plugin script path, aged past 0 s (sets SP)
lookalike() {
  spawn bash -c 'exec -a "$0" sleep "$1"' "$LW/$1" "$2"
  WAIT_LIB_WHAT="pid $SP to exec its look-alike line" wait_for_cmd 5 cmd_is "$SP" "$LW/$1 $2"
  WAIT_LIB_WHAT="pid $SP to age past 0 s" wait_for_cmd 10 etime_ge "$SP" 1
}
# mk_lock <checkout> <pid> <age s> <owner> [pid_start]
mk_lock() {
  mkdir -p "$1/.supervisor/run.lock"
  { printf 'pid\t%s\n' "$2"; printf 'owner\t%s\n' "$4"; printf 'session_id\t\n'
    printf 'ts\t%s\n' "$(( $(date +%s) - $3 ))"; printf 'pid_source\tholder_env\n'
    [ -z "${5:-}" ] || printf 'pid_start\t%s\n' "$5"; } > "$1/.supervisor/run.lock/meta"
}

# mk_fixture [--watcher] [--lanes] — a fresh machine state (sets P, WT, GHDIR, R, SNAP_EXTRA, LEAK, OTHER, HOLDER,
# WATCH): primary `proj` (main), a merged clean plugin-made worktree `proj-merged`, a dead-holder run lock
# (age 4000 s) on the primary, a lane L1 (with --lanes a lane-table row, no process: reads stalled) holding a YOUNG
# dead-holder lock and a lane L2 holding a LIVE-holder lock, a stale merge-watch marker, a stranded config
# backup of a done run, a ci-slot holder, the leaked fixture server and a second look-alike, the synthetic
# host session / python server / caffeinate rows; --watcher adds the overdue merge-watch registry entry and
# --lanes the lane table (lane-status is the slowest reader, so only the legs that read lanes pay for it).
# mk_merged_wt <name> <path> <pr number> — branch feat/<name> one commit past main, checked out at <path>,
# its newest PR (gh stub) MERGED at that tip: a worktree the sweep says would-remove. Fails loudly.
mk_merged_wt() {
  local c
  c="$(git -C "$P" -c commit.gpgsign=false commit-tree "$(git -C "$P" rev-parse 'main^{tree}')" -p main -m "$1")"
  [ -n "$c" ] || { echo "mk_merged_wt: commit-tree printed no commit" >&2; return 1; }
  git -C "$P" update-ref "refs/heads/feat/$1" "$c"
  git -C "$P" worktree add -q "$2" "feat/$1" >/dev/null 2>&1 || echo "mk_merged_wt: worktree add $2 failed" >&2
  printf '[{"number":%s,"state":"MERGED","headRefOid":"%s","mergedAt":"2026-10-01T00:00:00Z"}]\n' "$3" "$c" > "$GHDIR/feat_$1.json"
}
FXN=0
mk_fixture() {
  local d a watcher=0 lanes=0
  for a in "$@"; do case "$a" in --watcher) watcher=1 ;; --lanes) lanes=1 ;; esac; done
  FXN=$((FXN + 1))
  local fx="$WORK/fx$FXN"
  P="$fx/proj"; WT="$fx/proj-merged"; GHDIR="$fx/gh"; R="$fx/registry"
  export GHDIR LOOMWRIGHT_PROC_REGISTRY_DIR="$R"
  mkdir -p "$P" "$GHDIR" "$R"
  ( cd "$P" && git init -q && git symbolic-ref HEAD refs/heads/main && printf '.supervisor/\n' > .gitignore \
    && echo base > README && git add .gitignore README && git -c commit.gpgsign=false -c user.email=t@t -c user.name=t commit -qm init ) >/dev/null 2>&1
  mk_merged_wt merged "$WT" 11
  mkdir -p "$P/.supervisor/automate"
  mk_lock "$P" "$(dead_pid)" 4000 "automate:fx-crashed" "$FAKE_LSTART"
  # lanes: L1 (in the lane table, young dead lock), L2 (live-holder lock)
  for d in L1 L2; do mkdir -p "$P-lanes/fx-wave/$d/.supervisor/automate"; done
  if [ "$lanes" = 1 ]; then
    printf 'L1\t%s\t.supervisor/requirements/x.md\tfx-wave-L1\t\t\t\t\t\t\n' "$P-lanes/fx-wave/L1" > "$P/.supervisor/automate/fx-wave.lanes"
    printf '# Automate Run: fx-wave\n\n## Status: running\n' > "$P/.supervisor/automate/fx-wave.md"
  fi
  mk_lock "$P-lanes/fx-wave/L1" "$(dead_pid)" 100 "automate:fx-wave-L1" "$FAKE_LSTART"
  spawn sleep 3051; HOLDER=$SP   # fixed-sleep-ok: a background FIXTURE process (a live lock holder), not a wait
  mk_lock "$P-lanes/fx-wave/L2" "$HOLDER" 4000 "automate:fx-wave-L2" "$(lstart_of "$HOLDER")"
  # stale run state
  printf 'pid\t%s\npr_url\thttps://github.com/o/r/pull/1\nstarted\t2026-10-01T00:00:00Z\n' "$(dead_pid)" > "$P/.supervisor/automate/fx-old.merge-watch"
  printf '{"auto_review": true}\n' > "$P/.supervisor/automate/fx-old.config-backup.json"
  printf '# Automate Run: fx-old\n\n## Status: done\n' > "$P/.supervisor/automate/fx-old.md"
  # a ci-slot holder (a live process)
  spawn sleep 3052; SLOTP=$SP   # fixed-sleep-ok: a background FIXTURE process (a CI-slot holder), not a wait
  d="$(cd "$P" && bash "$HERE/ci-slot.sh" dir 2>/dev/null)"
  mkdir -p "$d/slots/0"; printf '%s\n%s\n%s\n%s\n' "$SLOTP" "$P" "ci-local" "$(( $(date +%s) - 60 ))" > "$d/slots/0/info"
  # processes
  lookalike fixture-server.sh 3053; LEAK=$SP
  lookalike fixture-other.sh 3054; OTHER=$SP
  WATCH=""
  if [ "$watcher" = 1 ]; then
    spawn sleep 3055; WATCH=$SP   # fixed-sleep-ok: a background FIXTURE process (the old watcher), not a wait
    bash "$PRS" register --pid "$WATCH" --kind merge-watch --purpose "old watcher" --max-lifetime 1 --repo "$P" 2>/dev/null
    WAIT_LIB_WHAT="watcher $WATCH to pass its 1 s cap" wait_for_cmd 10 etime_ge "$WATCH" 2
  fi
  SNAP_EXTRA="$(printf '900301 1 %s 10-00:00:00 /opt/host/bg-pty-host --session s1\n900302 1 %s 27-00:00:00 python3 /opt/srv/server.py --port 7811\n900303 1 %s 01:00:00 caffeinate -i -w 900399\n' "$FAKE_LSTART" "$FAKE_LSTART" "$FAKE_LSTART")"
  snap
}
# snap — a fresh snapshot file of this fixture's live processes plus the synthetic rows (sets SNAP)
SNAPN=0
snap() {
  local p list=""
  SNAPN=$((SNAPN + 1)); SNAP="$WORK/snap.$SNAPN"
  for p in $LEG_PIDS; do alive "$p" && list="${list:+$list,}$p"; done
  { [ -z "$list" ] || env TZ=UTC0 LC_ALL=C ps -ww -o pid=,ppid=,lstart=,etime=,command= -p "$list" 2>/dev/null
    printf '%s\n' "$SNAP_EXTRA"; } > "$SNAP"
}
jr() { env -u CI LOOMWRIGHT_PROC_PS_SNAPSHOT="$SNAP" bash "$S" "$@"; }
fxsum() {
  {
    (cd "$R" && find . -type f | env LC_ALL=C sort | while IFS= read -r f; do printf '%s ' "$f"; cksum < "$f"; done)
    find "$P/.supervisor" "$P-lanes" -type f 2>/dev/null | env LC_ALL=C sort | while IFS= read -r f; do printf '%s ' "$f"; cksum < "$f"; done
    git -C "$P" worktree list --porcelain
    git -C "$P" for-each-ref refs/heads
  } | cksum
}
# rows_where <json> <jq filter> — the matching rows, one compact JSON line each
rows_where() { printf '%s' "$1" | jq -c ".groups[].rows[] | select($2)" 2>/dev/null; }
nrows() { rows_where "$1" "$2" | awk 'NF { n++ } END { print n + 0 }'; }
row_id() { rows_where "$1" "$2" | head -1 | jq -r .id 2>/dev/null; }
full_row() {   # full_row <json row> — every field present, the descriptive ones non-empty, age numeric
  printf '%s' "$1" | jq -e '(.id | length > 0) and (.group | length > 0) and (.what | length > 0) and (.owner | length > 0)
    and (.age_s | type == "number") and (.state | length > 0) and (.evidence | length > 0) and (.action | length > 0)
    and (.reason | length > 0)' >/dev/null 2>&1
}
text_count() { grep -c -- "$2" <<<"$1" | tr -d ' '; }

# ==== legs ===============================================================================================
leg_report_fixture() {
  local before out rc js r
  mk_fixture --watcher --lanes
  before="$(fxsum)"
  out="$(jr --root "$P" 2>/dev/null)"; rc=$?
  js="$(jr --root "$P" --json 2>/dev/null)"
  check "leg_report_fixture exit 0, one summary line, last" eval '[ "$rc" = 0 ] && [ "$(text_count "$out" "^janitor: summary — ")" = 1 ] && has "$(tail -n 1 <<<"$out")" "janitor: summary — "'
  # the leaked fixture server
  check "leg_report_fixture the leaked fixture server appears exactly once (text)" eq "$(text_count "$out" "^- .*| unregistered process pid $LEAK\$")" 1
  r="$(rows_where "$js" ".evidence | test(\"fixture-server.sh\")")"
  check "leg_report_fixture ... one processes row, unregistered, action stop-unregistered, every field filled" \
    eval '[ "$(printf "%s\n" "$r" | awk "NF" | wc -l | tr -d " ")" = 1 ] && full_row "$r" && [ "$(jq -r ".group + \"|\" + .action" <<<"$r")" = "processes|stop-unregistered" ]'
  # the old merge watcher
  check "leg_report_fixture the old merge watcher appears exactly once (text)" eq "$(text_count "$out" "^- .*| merge-watch process pid $WATCH ")" 1
  r="$(rows_where "$js" ".what | test(\"merge-watch process pid $WATCH \")")"
  check "leg_report_fixture ... overdue, action reap, every field filled" \
    eval 'full_row "$r" && [ "$(jq -r ".state + \"|\" + .action" <<<"$r")" = "overdue|reap" ]'
  # the dead lock holder on the primary
  check "leg_report_fixture the dead-holder run lock appears exactly once (text)" eq "$(text_count "$out" "^- lock-.*| run lock — primary $P\$")" 1
  r="$(rows_where "$js" ".group == \"locks\" and (.what | endswith(\"primary $P\"))")"
  check "leg_report_fixture ... action lock-reclaim, every field filled" eval 'full_row "$r" && [ "$(jq -r .action <<<"$r")" = lock-reclaim ]'
  # the merged clean worktree
  check "leg_report_fixture the merged clean worktree appears exactly once (text)" eq "$(text_count "$out" "^- wt-.*| worktree .*proj-merged\$")" 1
  r="$(rows_where "$js" ".group == \"worktrees\" and (.what | test(\"^worktree .*proj-merged$\"))")"
  check "leg_report_fixture ... removable, action sweep-apply naming the whole-sweep limit, every field filled" \
    eval 'full_row "$r" && [ "$(jq -r .action <<<"$r")" = sweep-apply ] && has "$(jq -r .reason <<<"$r")" "WHOLE sweep"'
  check "leg_report_fixture read-only: registry, .supervisor trees (locks), worktrees and branches unchanged" eq "$(fxsum)" "$before"
  check "leg_report_fixture ... and every fixture process still runs" eval 'alive "$LEAK" && alive "$OTHER" && alive "$WATCH" && alive "$HOLDER"'
  check "leg_report_fixture the lane-status leaks row is the compare mode, shown as-is (no snapshot written)" \
    eval '[ "$(nrows "$js" ".group == \"lanes\" and (.state | startswith(\"leaks: unknown — no snapshot\"))")" = 1 ] && [ ! -e "$P/.supervisor/automate/fx-wave.leaks-snapshot" ]'
  check "leg_report_fixture ... and the lane itself is one lanes row (stalled, its coordinator owns it)" \
    eval '[ "$(nrows "$js" ".group == \"lanes\" and .what == \"lane L1 of fx-wave\" and .action == \"none\" and .state == \"stalled\"")" = 1 ]'
  leg_json_checks "$js" "$out"
  leg_end
}

# leg_json_checks <json> <text> — brief AC5 over leg_report_fixture's two runs of the same state
leg_json_checks() {
  local js="$1" out="$2" ids_t ids_j
  check "leg_json ONE JSON object, schema_version 1, groups[] in the closed order" \
    eval '[ "$(printf "%s" "$js" | jq -s "length" 2>/dev/null)" = 1 ] && [ "$(jq -r ".schema_version" <<<"$js")" = 1 ] && [ "$(jq -r "[.groups[].group] | join(\" \")" <<<"$js")" = "processes locks lanes worktrees stale-state plugin-adjacent not-the-plugins" ]'
  check "leg_json every row carries id, group, what, owner, age_s, state, evidence, action, reason" \
    eval '[ "$(jq "[.groups[].rows[] | select(has(\"id\") and has(\"group\") and has(\"what\") and has(\"owner\") and has(\"age_s\") and has(\"state\") and has(\"evidence\") and has(\"action\") and has(\"reason\") | not)] | length" <<<"$js")" = 0 ] && [ "$(jq "[.groups[].rows[]] | length" <<<"$js")" -gt 0 ]'
  ids_j="$(jq -r '.groups[].rows[].id' <<<"$js")"
  ids_t="$(sed -n 's/^- \([^ ]*\) | .*/\1/p' <<<"$out")"
  check "leg_json the same row ids, in the same order, as the text table" eval '[ -n "$ids_j" ] && [ "$ids_j" = "$ids_t" ]'
  check "leg_json the summary counts every row" eq "$(jq -r '.summary.rows' <<<"$js")" "$(printf '%s\n' "$ids_j" | awk 'NF { n++ } END { print n + 0 }')"
  check "leg_json every action is in the closed set" \
    eq "$(jq -r '[.groups[].rows[].action] | map(select(IN("reap","stop-unregistered","sweep-apply","lane-remove","lock-reclaim","config-restore","none") | not)) | length' <<<"$js")" 0
}

leg_report_only() {
  local js id out before
  mk_fixture
  js="$(jr --root "$P" --json 2>/dev/null)"
  check "leg_report_only the host background session is a not-the-plugin's row, action none, with a reason" \
    eval '[ "$(nrows "$js" ".group == \"not-the-plugins\" and (.evidence | test(\"bg-pty-host\")) and .action == \"none\" and (.reason | length > 0)")" = 1 ]'
  check "leg_report_only the python server is a not-the-plugin's row, action none" \
    eval '[ "$(nrows "$js" ".group == \"not-the-plugins\" and (.evidence | test(\"server.py\")) and .action == \"none\"")" = 1 ]'
  check "leg_report_only no not-the-plugin's row carries an action" eq "$(nrows "$js" '.group == "not-the-plugins" and .action != "none"')" 0
  check "leg_report_only the ci-slot holder and the keep-awake are plugin-adjacent, action none" \
    eval '[ "$(nrows "$js" ".group == \"plugin-adjacent\" and .action == \"none\" and ((.evidence | test(\"pid $SLOTP\")) or (.evidence | test(\"caffeinate\")))")" = 2 ]'
  check "leg_report_only no plugin-adjacent row carries an action" eq "$(nrows "$js" '.group == "plugin-adjacent" and .action != "none"')" 0
  before="$(fxsum)"
  local refused=1 ids
  ids="$(rows_where "$js" '.group == "not-the-plugins" or .group == "plugin-adjacent"' | jq -r .id)"
  # shellcheck disable=SC2086
  out="$(jr act --confirm --root "$P" $ids 2>/dev/null)"
  for id in $ids; do has "$out" "janitor: refused $id — a report-only row" || refused=0; done
  [ -n "$ids" ] || refused=0
  check "leg_report_only act --confirm refuses every report-only row" eq "$refused" 1
  check "leg_report_only ... with no signal (the live ci-slot holder runs) and no change" eval 'alive "$SLOTP" && [ "$(fxsum)" = "$before" ]'
  leg_end
}

leg_noninteractive() {
  local js id before out rc
  mk_fixture
  js="$(jr --root "$P" --json 2>/dev/null)"
  id="$(row_id "$js" ".evidence | test(\"fixture-server.sh\")")"
  before="$(fxsum)"
  out="$(jr act --root "$P" "$id" 2>/dev/null)"; rc=$?
  check "leg_noninteractive act without --confirm: 'janitor: report only — …', exit 0, nothing acted on" \
    eval '[ -n "$id" ] && [ "$rc" = 0 ] && has "$(head -n 1 <<<"$out")" "janitor: report only — " && alive "$LEAK" && [ "$(fxsum)" = "$before" ]'
  out="$(jr act --confirm --report --root "$P" "$id" 2>/dev/null)"; rc=$?
  check "leg_noninteractive act --confirm --report: report only, nothing acted on" \
    eval '[ "$rc" = 0 ] && has "$out" "janitor: report only — --report" && alive "$LEAK" && [ "$(fxsum)" = "$before" ]'
  out="$(CI=true LOOMWRIGHT_PROC_PS_SNAPSHOT="$SNAP" bash "$S" act --confirm --root "$P" "$id" 2>/dev/null)"; rc=$?
  check "leg_noninteractive act --confirm with CI set: report only, nothing acted on" \
    eval '[ "$rc" = 0 ] && has "$out" "janitor: report only — CI is set" && alive "$LEAK" && [ "$(fxsum)" = "$before" ]'
  leg_end
}

leg_act_stop() {
  local js id out next
  mk_fixture
  js="$(jr --root "$P" --json 2>/dev/null)"
  id="$(row_id "$js" ".evidence | test(\"fixture-server.sh\")")"
  out="$(jr act --confirm --root "$P" "$id" 2>/dev/null)"
  WAIT_LIB_WHAT="pid $LEAK to be reaped" wait_for_cmd 5 no_lstart "$LEAK"
  check "leg_act_stop act --confirm stops exactly the picked look-alike through proc-registry stop-unregistered" \
    eval '[ -n "$id" ] && has "$out" "janitor: act $id — stop-unregistered: unregistered unreg-$LEAK (pid $LEAK): stopped (TERM" && gone "$LEAK"'
  check "leg_act_stop ... the second look-alike stays alive" eval 'alive "$OTHER"'
  check "leg_act_stop ... then a fresh one-line summary, last" eval 'has "$(tail -n 1 <<<"$out")" "janitor: summary — "'
  snap
  next="$(jr --root "$P" --json 2>/dev/null)"
  check "leg_act_stop the next report no longer lists it (and still lists the other)" \
    eval '[ "$(nrows "$next" ".what == \"unregistered process pid $LEAK\"")" = 0 ] && [ "$(nrows "$next" ".what == \"unregistered process pid $OTHER\"")" = 1 ]'
  leg_end
}

leg_act_recycled() {
  local js id out p rf old
  mk_fixture
  printf '%s\n' 'trap '"'"'exec -a "$2" sleep 3056'"'"' USR1' ': > "$1"' 'while :; do sleep 0.1; done' > "$LW/first.sh"   # fixed-sleep-ok: the fixture script's own idle loop
  rf="$WORK/ready.$RANDOM"
  spawn bash "$LW/first.sh" "$rf" "$LW/second.sh"; p=$SP
  WAIT_LIB_WHAT="fixture $p to install its trap" wait_for_cmd 5 test -f "$rf"
  WAIT_LIB_WHAT="pid $p to age past 0 s" wait_for_cmd 10 etime_ge "$p" 1
  snap; old="$SNAP"
  js="$(jr --root "$P" --json 2>/dev/null)"
  id="$(row_id "$js" ".what == \"unregistered process pid $p\"")"
  kill -USR1 "$p"
  WAIT_LIB_WHAT="pid $p to exec its second look-alike line" wait_for_cmd 5 cmd_is "$p" "$LW/second.sh 3056"
  snap
  check "leg_act_recycled (control) before AND after the exec the pid is a listed look-alike" \
    eval '[ -n "$id" ] && [ "$(nrows "$(jr --root "$P" --json 2>/dev/null)" ".what == \"unregistered process pid $p\"")" = 1 ]'
  out="$(jr act --confirm --root "$P" "$id" 2>/dev/null)"
  check "leg_act_recycled act's fresh re-read refuses it (its id changed), not signalled" \
    eval 'has "$out" "janitor: refused $id — not in the fresh report" && alive "$p"'
  out="$(env -u CI LOOMWRIGHT_PROC_PS_SNAPSHOT="$old" bash "$S" act --confirm --root "$P" "$id" 2>/dev/null)"
  check "leg_act_recycled fed the stale snapshot, proc-registry's lstart/hash re-check refuses it, not signalled" \
    eval 'has "$out" "janitor: act $id — stop-unregistered: not signalled: no longer matches (command line differs (pid recycled))" && alive "$p"'
  leg_end
}

leg_live_session() {
  local js id oid out r
  mk_fixture
  # the snapshot re-parents the leaked server under a shell of a live host session (900311 -bash, whose
  # parent 900312 is the desktop app's `…/Application Support/…/MacOS/claude`, a path with a space) and the second look-alike to pid 1 (its session ended)
  SNAP_EXTRA="$SNAP_EXTRA
900311 900312 $FAKE_LSTART 02:00:00 -bash
900312 1 $FAKE_LSTART 02:00:00 /Users/x/Library/Application Support/Claude/claude-code/9.9.9/claude.app/Contents/MacOS/claude --output-format stream-json"
  snap
  sed -E -e "s/^( *$LEAK +)[0-9]+ /\\1900311 /" -e "s/^( *$OTHER +)[0-9]+ /\\11 /" "$SNAP" > "$SNAP.r" && mv "$SNAP.r" "$SNAP"
  js="$(jr --root "$P" --json 2>/dev/null)"
  r="$(rows_where "$js" ".what == \"unregistered process pid $LEAK\"")"
  id="$(jq -r .id <<<"$r" 2>/dev/null)"
  check "leg_live_session a look-alike under a live host session: action none, 'its session is still alive', every field filled" \
    eval 'full_row "$r" && [ "$(jq -r .action <<<"$r")" = none ] && has "$(jq -r .reason <<<"$r")" "its session is still alive — the session owns it"'
  check "leg_live_session ... its evidence names its command line and the session" \
    eval 'has "$(jq -r .evidence <<<"$r")" "command: $LW/fixture-server.sh 3053" && has "$(jq -r .evidence <<<"$r")" "session: pid 900312 /Users/x/Library/Application Support/Claude/"'
  r="$(rows_where "$js" ".what == \"unregistered process pid $OTHER\"")"
  oid="$(jq -r .id <<<"$r" 2>/dev/null)"
  check "leg_live_session (control) a pid-1-reparented look-alike keeps stop-unregistered, its command in the evidence" \
    eval '[ -n "$oid" ] && [ "$(jq -r .action <<<"$r")" = stop-unregistered ] && has "$(jq -r .evidence <<<"$r")" "command: $LW/fixture-other.sh 3054"'
  out="$(jr act --confirm --root "$P" "$id" 2>/dev/null)"
  check "leg_live_session act --confirm refuses the live-session row, not signalled" \
    eval '[ -n "$id" ] && has "$out" "janitor: refused $id — a report-only row" && alive "$LEAK" && alive "$OTHER"'
  leg_end
}

leg_host_session() {
  local js r id oid out
  mk_fixture
  # synthetic rows: 900321 is a lane-like headless session whose --settings carry a plugin scripts path (a
  # look-alike that IS a host session, reparented to pid 1) with a look-alike child 900322; 900331 is an
  # unregistered wrapper look-alike with a live headless session (900332) running under it
  SNAP_EXTRA="$SNAP_EXTRA
900321 1 $FAKE_LSTART 03:00:00 /usr/local/bin/claude --print --settings $WORK/lw/loomwright/9.9.9/scripts/automate-lanes.sh
900322 900321 $FAKE_LSTART 03:00:00 $LW/fixture-child.sh 1
900331 1 $FAKE_LSTART 03:00:00 bash $LW/automate-lanes.sh _lane-run L1
900332 900331 $FAKE_LSTART 03:00:00 /usr/local/bin/claude --print hello"
  snap
  js="$(jr --root "$P" --json 2>/dev/null)"
  r="$(rows_where "$js" '.what == "unregistered process pid 900321"')"; id="$(jq -r .id <<<"$r" 2>/dev/null)"
  check "leg_host_session a look-alike that IS a live host session: action none, 'it is a live host session', its command cut in the evidence" \
    eval 'full_row "$r" && [ "$(jq -r .action <<<"$r")" = none ] && has "$(jq -r .reason <<<"$r")" "it is a live host session" && has "$(jq -r .evidence <<<"$r")" "command: /usr/local/bin/claude --print --settings"'
  check "leg_host_session ... its look-alike child is none too (its session is alive)" \
    eq "$(nrows "$js" '.what == "unregistered process pid 900322" and .action == "none" and (.reason | test("its session is still alive"))')" 1
  r="$(rows_where "$js" '.what == "unregistered process pid 900331"')"; oid="$(jq -r .id <<<"$r" 2>/dev/null)"
  check "leg_host_session a wrapper look-alike with a live host session under it: action none, 'runs under it', the session named" \
    eval 'full_row "$r" && [ "$(jq -r .action <<<"$r")" = none ] && has "$(jq -r .reason <<<"$r")" "a live host session runs under it (pid 900332)" && has "$(jq -r .evidence <<<"$r")" "session: pid 900332 /usr/local/bin/claude --print hello"'
  check "leg_host_session (control) the plain look-alike keeps stop-unregistered" \
    eq "$(nrows "$js" ".what == \"unregistered process pid $OTHER\" and .action == \"stop-unregistered\"")" 1
  out="$(jr act --confirm --root "$P" "$id" "$oid" 2>/dev/null)"
  check "leg_host_session act --confirm refuses both rows as report-only" \
    eval '[ -n "$id" ] && [ -n "$oid" ] && has "$out" "janitor: refused $id — a report-only row" && has "$out" "janitor: refused $oid — a report-only row"'
  leg_end
}

leg_snapshot_fail() {
  local js r
  mk_fixture --watcher
  # janitor's own snapshot cannot be taken (no temp dir); proc-registry still takes its own ps
  js="$(env -u CI -u HERMETIC_TEST_ENV -u LOOMWRIGHT_PROC_PS_SNAPSHOT TMPDIR="$WORK/no-such-tmp" bash "$S" --root "$P" --json 2>/dev/null)"
  r="$(rows_where "$js" ".what == \"unregistered process pid $LEAK\"")"
  check "leg_snapshot_fail a look-alike is none, 'the live-session check could not run' (never stop-unregistered)" \
    eval '[ -n "$r" ] && [ "$(jq -r .action <<<"$r")" = none ] && has "$(jq -r .reason <<<"$r")" "the live-session check could not run (unavailable — no temp file)"'
  r="$(rows_where "$js" ".what | test(\"merge-watch process pid $WATCH \")")"
  check "leg_snapshot_fail ... the overdue entry is none too (never reap without the host check)" \
    eval '[ -n "$r" ] && [ "$(jq -r ".state + \"|\" + .action" <<<"$r")" = "overdue|none" ] && has "$(jq -r .reason <<<"$r")" "check could not run"'
  check "leg_snapshot_fail ... no processes row is actionable except the finished-entry prune" \
    eq "$(nrows "$js" '.group == "processes" and .action != "none" and (.id | startswith("fin-") | not)')" 0
  leg_end
}

leg_reap_host() {
  local js r hp
  mk_fixture --watcher
  mkdir -p "$WORK/hostbin"
  spawn bash -c 'exec -a "$0" sleep "$1"' "$WORK/hostbin/claude" 3058; hp=$SP
  WAIT_LIB_WHAT="pid $hp to exec its host line" wait_for_cmd 5 cmd_is "$hp" "$WORK/hostbin/claude 3058"
  bash "$PRS" register --pid "$hp" --kind phase --purpose "a lane session" --max-lifetime 1 --repo "$P" 2>/dev/null
  WAIT_LIB_WHAT="pid $hp to pass its 1 s cap" wait_for_cmd 10 etime_ge "$hp" 2
  snap
  js="$(jr --root "$P" --json 2>/dev/null)"
  r="$(rows_where "$js" ".what | test(\"phase process pid $hp \")")"
  check "leg_reap_host an overdue entry that is a live host session keeps reap, its reason warning it ends that session" \
    eval 'full_row "$r" && [ "$(jq -r ".state + \"|\" + .action" <<<"$r")" = "overdue|reap" ] && has "$(jq -r .reason <<<"$r")" "overdue, but it is a live host session — reaping ends that session"'
  check "leg_reap_host ... its evidence names its command line" has "$(jq -r .evidence <<<"$r" 2>/dev/null)" "; command: $WORK/hostbin/claude 3058"
  r="$(rows_where "$js" ".what | test(\"merge-watch process pid $WATCH \")")"
  check "leg_reap_host (control) the plain overdue watcher: reap, no host warning, its command in the evidence" \
    eval '[ "$(jq -r .action <<<"$r")" = reap ] && ! has "$(jq -r .reason <<<"$r")" "live host session" && has "$(jq -r .evidence <<<"$r")" "; command: sleep 3055"'
  # a live host session under the overdue watcher (a lane wrapper's headless-session child)
  SNAP_EXTRA="$SNAP_EXTRA
900341 $WATCH $FAKE_LSTART 01:00:00 /usr/local/bin/claude --print x"
  snap
  r="$(rows_where "$(jr --root "$P" --json 2>/dev/null)" ".what | test(\"merge-watch process pid $WATCH \")")"
  check "leg_reap_host an overdue entry with a live host session under it keeps reap, its reason naming that session" \
    eval '[ "$(jq -r .action <<<"$r")" = reap ] && has "$(jq -r .reason <<<"$r")" "overdue, but a live host session runs under it (pid 900341)"'
  leg_end
}

leg_sweep_set() {
  local js id out js2
  mk_fixture
  js="$(jr --root "$P" --json 2>/dev/null)"
  id="$(row_id "$js" ".group == \"worktrees\" and .action == \"sweep-apply\"")"
  # after the report, a second merged worktree joins the would-remove set
  mk_merged_wt merged2 "$P-merged2" 12
  js2="$(jr --root "$P" --json 2>/dev/null)"
  check "leg_sweep_set (control) the grown set gives every sweep-apply row a new id" \
    eval '[ -n "$id" ] && [ "$(nrows "$js2" ".action == \"sweep-apply\" and (.what | startswith(\"worktree \"))")" = 2 ] && [ "$(nrows "$js2" ".id == \"$id\"")" = 0 ]'
  out="$(jr act --confirm --root "$P" "$id" 2>/dev/null)"
  check "leg_sweep_set act with the old sweep id refuses it (not in the fresh report); neither worktree removed" \
    eval 'has "$out" "janitor: refused $id — not in the fresh report" && [ -d "$WT" ] && [ -d "$P-merged2" ]'
  leg_end
}

leg_lock_reclaim() {
  local js id young live out l1 l2 m1 m2
  mk_fixture
  l1="$P-lanes/fx-wave/L1"; l2="$P-lanes/fx-wave/L2"
  js="$(jr --root "$P" --json 2>/dev/null)"
  id="$(row_id "$js" ".group == \"locks\" and (.what | endswith(\"primary $P\"))")"
  young="$(row_id "$js" ".group == \"locks\" and (.what | endswith(\"$l1\"))")"
  live="$(row_id "$js" ".group == \"locks\" and (.what | endswith(\"$l2\"))")"
  check "leg_lock_reclaim (control) the three locks: reclaim / none + alt force-unlock / none" \
    eval '[ "$(rows_where "$js" ".id == \"$id\"" | jq -r .action)|$(rows_where "$js" ".id == \"$young\"" | jq -r ".action + \"+\" + (.alt_action // \"-\")")|$(rows_where "$js" ".id == \"$live\"" | jq -r ".action + \"+\" + (.alt_action // \"-\")")" = "lock-reclaim|none+force-unlock|none+-" ]'
  m1="$(cksum < "$l1/.supervisor/run.lock/meta")"; m2="$(cksum < "$l2/.supervisor/run.lock/meta")"
  out="$(jr act --confirm --root "$P" "$id" "$young" "$live" 2>/dev/null)"
  check "leg_lock_reclaim the dead-holder >= 1800s lock is reclaimed and released: UNLOCKED, janitor holds no lock" \
    eval 'has "$out" "janitor: act $id — lock-reclaim: reclaimed and released" && [ "$(bash "$RLS" status --root "$P")" = UNLOCKED ] && [ ! -e "$P/.supervisor/run.lock" ]'
  check "leg_lock_reclaim the young dead-holder lock and the live-holder lock are refused, unchanged" \
    eval 'has "$out" "janitor: refused $young — a report-only row" && has "$out" "janitor: refused $live — a report-only row" && [ "$(cksum < "$l1/.supervisor/run.lock/meta")" = "$m1" ] && [ "$(cksum < "$l2/.supervisor/run.lock/meta")" = "$m2" ] && alive "$HOLDER"'
  out="$(jr act --confirm --force-unlock --root "$P" "$live" 2>/dev/null)"
  check "leg_lock_reclaim --force-unlock is refused on the live-holder lock" \
    eval 'has "$out" "janitor: refused $live — --force-unlock applies only" && [ "$(cksum < "$l2/.supervisor/run.lock/meta")" = "$m2" ]'
  out="$(jr act --confirm --force-unlock --root "$P" "$young" 2>/dev/null)"
  check "leg_lock_reclaim --force-unlock breaks only the young dead-holder lock" \
    eval 'has "$out" "janitor: act $young — force-unlock: force-unlock: broke" && [ "$(bash "$RLS" status --root "$l1")" = UNLOCKED ] && [ -f "$l2/.supervisor/run.lock/meta" ]'
  leg_end
}

leg_act_reap() {
  local js fid wid out f1 f2 e1 e2
  mk_fixture --watcher
  # two finished entries (registered processes that have since exited): ONE `fin` row carrying both ids
  spawn sleep 3061; f1=$SP; spawn sleep 3062; f2=$SP   # fixed-sleep-ok: background FIXTURE processes, not waits
  bash "$PRS" register --pid "$f1" --kind phase --purpose "a finished phase" --repo "$P" 2>/dev/null
  bash "$PRS" register --pid "$f2" --kind phase --purpose "another finished phase" --repo "$P" 2>/dev/null
  # register prints nothing; an entry's id is its file name, `<pid>-<hash>.json`
  e1="$(cd "$R" && ls "$f1"-*.json 2>/dev/null | head -1)"; e1="${e1%.json}"
  e2="$(cd "$R" && ls "$f2"-*.json 2>/dev/null | head -1)"; e2="${e2%.json}"
  fix_kill "$f1"; fix_kill "$f2"
  WAIT_LIB_WHAT="pids $f1 $f2 to exit" wait_for_cmd 5 eval 'gone "$f1" && gone "$f2"'
  snap
  js="$(jr --root "$P" --json 2>/dev/null)"
  fid="$(row_id "$js" '.group == "processes" and .action == "reap" and (.id | startswith("fin-"))')"
  wid="$(row_id "$js" ".what | test(\"merge-watch process pid $WATCH \")")"
  check "leg_act_reap (control) the two finished entries are ONE fin row (reap), the old watcher an overdue reap row" \
    eval '[ -n "$e1" ] && [ -n "$e2" ] && [ -f "$R/$e1.json" ] && [ -f "$R/$e2.json" ] && [ -n "$fid" ] && [ -n "$wid" ] && [ "$(rows_where "$js" ".id == \"$fid\"" | jq -r .what)" = "2 finished registry entries" ]'
  out="$(jr act --confirm --root "$P" "$fid" "$wid" 2>/dev/null)"
  check "leg_act_reap act --confirm on the fin row prunes BOTH entry files (its multi-id data word-splits into reap --apply)" \
    eval 'has "$out" "janitor: act $fid — reap: " && has "$out" "finished $e1 " && has "$out" "finished $e2 " && [ ! -e "$R/$e1.json" ] && [ ! -e "$R/$e2.json" ]'
  WAIT_LIB_WHAT="watcher $WATCH to be reaped" wait_for_cmd 10 no_lstart "$WATCH"
  check "leg_act_reap act --confirm on the overdue row stops the old watcher through proc-registry reap" \
    eval 'has "$out" "janitor: act $wid — reap: " && gone "$WATCH" && alive "$LEAK" && alive "$HOLDER"'
  leg_end
}

leg_act_sweep() {
  local js id1 id2 out
  mk_fixture
  mk_merged_wt merged2 "$P-merged2" 12
  js="$(jr --root "$P" --json 2>/dev/null)"
  id1="$(row_id "$js" ".group == \"worktrees\" and .action == \"sweep-apply\" and (.what | test(\"proj-merged$\"))")"
  id2="$(row_id "$js" ".group == \"worktrees\" and .action == \"sweep-apply\" and (.what | test(\"proj-merged2$\"))")"
  check "leg_act_sweep (control) two sweep-apply rows, both worktrees present" \
    eval '[ -n "$id1" ] && [ -n "$id2" ] && [ "$id1" != "$id2" ] && [ -d "$WT" ] && [ -d "$P-merged2" ]'
  out="$(jr act --confirm --root "$P" "$id1" "$id2" 2>/dev/null)"
  check "leg_act_sweep the first picked row runs the whole sweep once; the second is 'already applied in this call'" \
    eval '[ "$(text_count "$out" "sweep-apply (the whole sweep): ")" = 1 ] && has "$out" "janitor: act $id1 — sweep-apply (the whole sweep): " && has "$out" "janitor: act $id2 — sweep-apply: already applied in this call"'
  check "leg_act_sweep ... both merged worktrees are removed (gone from disk and from git worktree list)" \
    eval '[ ! -d "$WT" ] && [ ! -d "$P-merged2" ] && ! grep -q "proj-merged" < <(git -C "$P" worktree list --porcelain)'
  leg_end
}

leg_act_lane_remove() {
  local js id out l3
  mk_fixture --lanes
  # lane L3: a clean clone (its own git dir, .supervisor/ excluded, no branches to push) whose run says done
  l3="$P-lanes/fx-wave/L3"; mkdir -p "$l3/.supervisor/automate"
  git init -q "$l3" && printf '.supervisor/\n' >> "$l3/.git/info/exclude"
  printf '{"lane":"L3","run_id":"fx-wave-L3","parent_run_id":"fx-wave","primary":"%s"}\n' "$P" > "$l3/.supervisor/lane.json"
  printf '# Automate Run: fx-wave-L3\n\n## Current\n- item: .supervisor/requirements/y.md | status: done\n' > "$l3/.supervisor/automate/fx-wave-L3.md"
  printf 'L3\t%s\t.supervisor/requirements/y.md\tfx-wave-L3\t\t\t\t\t\t\n' "$l3" >> "$P/.supervisor/automate/fx-wave.lanes"
  js="$(jr --root "$P" --json 2>/dev/null)"
  id="$(row_id "$js" '.group == "lanes" and .what == "lane L3 of fx-wave" and .action == "lane-remove"')"
  check "leg_act_lane_remove (control) the done lane is one lanes row, action lane-remove" eval '[ -n "$id" ] && [ "$(rows_where "$js" ".id == \"$id\"" | jq -r .state)" = done ]'
  out="$(jr act --confirm --root "$P" "$id" 2>/dev/null)"
  check "leg_act_lane_remove act --confirm runs lane-remove: the lane dir is gone, the table says removed, a salvage is kept" \
    eval 'has "$out" "janitor: act $id — lane-remove: lane-remove: removed L3 ($l3)" && [ ! -d "$l3" ] && [ "$(awk -F"\t" "\$1 == \"L3\" { print \$8 }" "$P/.supervisor/automate/fx-wave.lanes")" = removed ] && [ -n "$(ls -d "$P-lanes/fx-wave/salvage/L3-removed-"* 2>/dev/null)" ]'
  check "leg_act_lane_remove ... the other lanes stay on disk" eval '[ -d "$P-lanes/fx-wave/L1" ] && [ -d "$P-lanes/fx-wave/L2" ]'
  leg_end
}

leg_act_config_restore() {
  local js id out cfg bak
  mk_fixture
  cfg="$P/.supervisor/config.json"; bak="$P/.supervisor/automate/fx-old.config-backup.json"
  printf '{"auto_review": false}\n' > "$cfg"   # the suppressed config a crashed run left behind
  js="$(jr --root "$P" --json 2>/dev/null)"
  id="$(row_id "$js" '.group == "stale-state" and .what == "config backup of run fx-old"')"
  check "leg_act_config_restore (control) the stranded backup of a done run under a dead lock: action config-restore, every field filled" \
    eval '[ -n "$id" ] && full_row "$(rows_where "$js" ".id == \"$id\"")" && [ "$(rows_where "$js" ".id == \"$id\"" | jq -r .action)" = config-restore ]'
  out="$(jr act --confirm --root "$P" "$id" 2>/dev/null)"
  check "leg_act_config_restore act --confirm restores config.json byte-for-byte from the backup and removes the backup" \
    eval 'has "$out" "janitor: act $id — config-restore: restored $cfg from $bak (backup removed)" && [ "$(cat "$cfg")" = "{\"auto_review\": true}" ] && [ ! -e "$bak" ]'
  leg_end
}

leg_nostatus() {
  local js r id cid out l4 m4
  mk_fixture
  # lane L4: a dead-holder lock old enough to reclaim, but the run its owner names states no ## Status:
  l4="$P-lanes/fx-wave/L4"; mkdir -p "$l4/.supervisor/automate"
  mk_lock "$l4" "$(dead_pid)" 4000 "automate:fx-wave-L4" "$FAKE_LSTART"
  printf '# Automate Run: fx-wave-L4\n\n## Current\n- item: x\n' > "$l4/.supervisor/automate/fx-wave-L4.md"
  # a config backup whose run file states no ## Status: (the primary's lock holder is dead)
  printf '{"auto_review": true}\n' > "$P/.supervisor/automate/fx-nost.config-backup.json"
  printf '# Automate Run: fx-nost\n\n## Progress\n' > "$P/.supervisor/automate/fx-nost.md"
  js="$(jr --root "$P" --json 2>/dev/null)"
  r="$(rows_where "$js" ".group == \"locks\" and (.what | endswith(\"$l4\"))")"; id="$(jq -r .id <<<"$r" 2>/dev/null)"
  check "leg_nostatus a dead-holder >= 1800s lock whose run states no status: action none, never reclaimed, no alt" \
    eval 'full_row "$r" && [ "$(jq -r ".action + \"|\" + (.alt_action // \"-\")" <<<"$r")" = "none|-" ] && has "$(jq -r .reason <<<"$r")" "run fx-wave-L4'"'"'s file states no \`## Status:\` — whether that run goes on cannot be judged; never reclaimed from here"'
  r="$(rows_where "$js" '.group == "stale-state" and .what == "config backup of run fx-nost"')"; cid="$(jq -r .id <<<"$r" 2>/dev/null)"
  check "leg_nostatus a config backup whose run file states no status: action none, 'cannot be judged'" \
    eval 'full_row "$r" && [ "$(jq -r .action <<<"$r")" = none ] && has "$(jq -r .reason <<<"$r")" "run fx-nost'"'"'s file states no \`## Status:\` — whether that run goes on cannot be judged; report only"'
  check "leg_nostatus (control) the done run's backup under the same dead lock is still config-restore" \
    eq "$(nrows "$js" '.what == "config backup of run fx-old" and .action == "config-restore"')" 1
  m4="$(cksum < "$l4/.supervisor/run.lock/meta")"
  out="$(jr act --confirm --root "$P" "$id" "$cid" 2>/dev/null)"
  check "leg_nostatus act --confirm refuses both, lock and backup unchanged" \
    eval '[ -n "$id" ] && [ -n "$cid" ] && has "$out" "janitor: refused $id — a report-only row" && has "$out" "janitor: refused $cid — a report-only row" && [ "$(cksum < "$l4/.supervisor/run.lock/meta")" = "$m4" ] && [ -f "$P/.supervisor/automate/fx-nost.config-backup.json" ]'
  leg_end
}

leg_cfg_unjudged() {
  local js r id out
  mk_fixture
  # the primary's lock now records no holder pid: liveness reads `unknown` while status is LOCKED
  mk_lock "$P" "" 4000 "automate:fx-crashed"
  js="$(jr --root "$P" --json 2>/dev/null)"
  r="$(rows_where "$js" '.group == "stale-state" and .what == "config backup of run fx-old"')"; id="$(jq -r .id <<<"$r" 2>/dev/null)"
  check "leg_cfg_unjudged a done run's backup under a pid-less held lock: action none, 'run lock cannot be judged'" \
    eval 'full_row "$r" && [ "$(jq -r ".state + \"|\" + .action" <<<"$r")" = "run lock: held with no recorded pid|none" ] && has "$(jq -r .reason <<<"$r")" "this checkout'"'"'s run lock cannot be judged (held with no recorded pid)"'
  out="$(jr act --confirm --root "$P" "$id" 2>/dev/null)"
  check "leg_cfg_unjudged act --confirm refuses it, the backup kept" \
    eval '[ -n "$id" ] && has "$out" "janitor: refused $id — a report-only row" && [ -f "$P/.supervisor/automate/fx-old.config-backup.json" ]'
  leg_end
}

leg_usage() {
  local rc out
  mk_fixture
  jr --bogus >/dev/null 2>&1; rc=$?
  check "leg_usage an unknown report argument exits 2" eq "$rc" 2
  jr act --confirm --root "$P" >/dev/null 2>&1; rc=$?
  check "leg_usage act with no row id exits 2" eq "$rc" 2
  jr act --confirm --bogus x-1 >/dev/null 2>&1; rc=$?
  check "leg_usage act with an unknown option exits 2" eq "$rc" 2
  out="$(jr act --confirm --root "$P" nosuch-12345678 2>/dev/null)"; rc=$?
  check "leg_usage an unknown row id is refused, exit 0" eval '[ "$rc" = 0 ] && has "$out" "janitor: refused nosuch-12345678 — unknown row id"'
  out="$(jr --root "$WORK/not-a-checkout" 2>/dev/null)"; rc=$?
  check "leg_usage a non-checkout root: exit 0, one unknown row (never a clean report)" eval '[ "$rc" = 0 ] && has "$out" "state: unknown — git "'
  leg_end
}

# ==== run the legs against the real script ===============================================================
echo "== janitor-report.sh =="
for leg in leg_report_fixture leg_report_only leg_noninteractive leg_act_stop leg_act_recycled leg_live_session leg_host_session leg_snapshot_fail leg_reap_host leg_sweep_set leg_lock_reclaim leg_act_reap leg_act_sweep leg_act_lane_remove leg_act_config_restore leg_nostatus leg_cfg_unjudged leg_usage; do
  LEG_FAIL=0; S="$SUT_REAL"; t0="$(date +%s)"; "$leg"; echo "  ($leg: $(( $(date +%s) - t0 ))s)"
done

# ==== mutation controls ==================================================================================
echo "== mutation controls =="
MUT=""
mk_mutant() {   # mk_mutant <name> del <fixed string> | sub <fixed a> <fixed b>
  local name="$1" mode="$2"
  MUT="$WORK/mutant-$name.sh"
  case "$mode" in
    del) awk -v m="$3" 'index($0, m) == 0' "$SUT_REAL" > "$MUT" ;;
    sub) awk -v a="$3" -v b="$4" '{ i = index($0, a); if (i) $0 = substr($0, 1, i - 1) b substr($0, i + length(a)); print }' "$SUT_REAL" > "$MUT" ;;
  esac
  MUT_MODE="$mode"
}
gate_mutant() {   # gate_mutant <label> — the lesson-fa32a308 gate
  local g=0
  [ -s "$MUT" ] || { no "$1 mutant is EMPTY"; g=1; }
  cmp -s "$MUT" "$SUT_REAL" && { no "$1 mutant is byte-identical — the mutation no-opped"; g=1; }
  bash -n "$MUT" 2>/dev/null || { no "$1 mutant does not parse"; g=1; }
  if [ "$MUT_MODE" = del ] && [ "$(( $(lines "$SUT_REAL") - $(lines "$MUT") ))" != 1 ]; then
    no "$1 mutant removed $(( $(lines "$SUT_REAL") - $(lines "$MUT") )) lines, not exactly one"; g=1
  fi
  return "$g"
}
# The mutant runs from $MDIR — a real dir of symlinks to every scripts/ entry — so its readers resolve
# beside it and nothing is written into the repo.
MDIR="$WORK/mscripts"; mkdir -p "$MDIR"
for f in "$HERE"/*; do ln -s "$f" "$MDIR/${f##*/}"; done
run_mutant() {   # run_mutant <label> <leg>
  local m="$MDIR/janitor-report.sh"
  gate_mutant "$1" || return 0
  rm -f "$m"; cp "$MUT" "$m"
  QUIET=1; LEG_FAIL=0; S="$m"
  "$2"
  QUIET=0; S="$SUT_REAL"
  if [ "$LEG_FAIL" = 1 ]; then ok "$1: the mutant turns $2 red"; else no "$1: the mutant PASSES $2 — the pin is not load-bearing"; fi
}

mk_mutant guard del "printf 'janitor: report only — %s"
run_mutant "brief AC7 act's report-only guard line deleted (act would act without --confirm)" leg_noninteractive
mk_mutant extnone sub '"running" "$cmd" none' '"running" "$cmd" stop-unregistered'
run_mutant "brief AC6 the not-the-plugin's none action flipped to stop-unregistered" leg_report_only
mk_mutant regwrite sub 'local json=0 root="" a' ': > "$LOOMWRIGHT_PROC_REGISTRY_DIR/.touched"; local json=0 root="" a'
run_mutant "brief AC4 the report path writes into the registry dir (checksum)" leg_report_fixture
mk_mutant nosession sub 'sess="$(_jr_live_session "$pid")"' 'sess=""'
run_mutant "the live-session demotion dropped (a live session's look-alike offered for stopping)" leg_live_session
mk_mutant firstword sub 'exe="$exe $w"; rest="${rest#"$w"}"' 'return 1'
run_mutant "the host rule reads only the first word (a desktop-app session path with a space is missed)" leg_live_session
mk_mutant hostself sub 'if _jr_is_host_cmd "$full"; then' 'if false; then'
run_mutant "the look-alike-is-itself-a-host-session check dropped (a live lane session offered for stopping)" leg_host_session
mk_mutant hostbelow sub 'sess="$(_jr_host_below "$pid")"' 'sess=""'
run_mutant "the live-session-below check dropped (a wrapper of a live session offered for stopping)" leg_host_session
mk_mutant snapopen sub 'if [ -n "$JR_SNAP_WHY" ] || [ -z "$full" ]; then' 'if false; then'
run_mutant "the look-alike fail-closed on a missing snapshot dropped (stop-unregistered offered unchecked)" leg_snapshot_fail
mk_mutant regsnapopen sub 'if [ -n "$JR_SNAP_WHY" ]; then   # fail CLOSED: the live-host' 'if false; then   # fail CLOSED: the live-host'
run_mutant "the overdue-entry fail-closed on a missing snapshot dropped (reap offered unchecked)" leg_snapshot_fail
mk_mutant reapwarn sub 'host="|host"; why="$class, but it is a live host session — reaping ends that session; "' 'host=""; why="$class: "'
run_mutant "the live-host-session warning on an overdue entry dropped" leg_reap_host
mk_mutant reapbelow sub 'hb="$(_jr_host_below "$pid")"' 'hb=""'
run_mutant "the live-session-below warning on an overdue entry dropped" leg_reap_host
mk_mutant noset sub '|$reason|set:$wset"' '|$reason"'
run_mutant "the would-remove set dropped from the sweep row identity (act sweeps rows never shown)" leg_sweep_set
mk_mutant sweeponce del 'if [ "$swept" = 1 ]; then echo'
run_mutant "act's once-per-call sweep-apply guard dropped (a second picked sweep row re-runs the whole sweep)" leg_act_sweep
mk_mutant reapquoted sub '_jr_pr reap --apply $data' '_jr_pr reap --apply "$data"'
run_mutant "the fin row's ids passed to reap as ONE word (a multi-entry fin row prunes nothing)" leg_act_reap
mk_mutant locknostatus sub 'if [ "$run" != "$owner" ] && [ -f "$c/.supervisor/automate/$run.md" ] && [ -z "$rst" ]; then' 'if false; then'
run_mutant "the dead-holder lock fail-closed on a run file with no status dropped (lock-reclaim offered)" leg_nostatus
mk_mutant cfgnostatus sub 'elif [ -f "$ad/$run.md" ] && [ -z "$rst" ]; then' 'elif false; then'
run_mutant "the config-backup fail-closed on a run file with no status dropped (config-restore offered)" leg_nostatus
mk_mutant cfgunjudged sub 'elif [ "$lv" != dead ] && [ "$lv" != unknown ]; then' 'elif false; then'
run_mutant "the config-backup fail-closed on an unjudgeable run lock dropped (config-restore offered)" leg_cfg_unjudged

echo
echo "test-janitor-report.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
