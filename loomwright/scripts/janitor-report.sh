#!/usr/bin/env bash
# janitor-report.sh — ONE grouped, read-only report of everything the plugin left running or lying
# around, each row with a suggested action and its reason; and `act`, which runs ONLY the rows the
# owner picked, each through its existing guarded helper after a re-check. This header IS the
# contract; commands/janitor.md only renders the report and asks the owner.
#
# USAGE
#   janitor-report.sh [--json] [--root <checkout>]
#   janitor-report.sh act [--confirm] [--report] [--force-unlock] [--root <checkout>] <row id>...
#   janitor-report.sh -h | --help
#   <checkout> (default: the cwd) resolves to its PRIMARY checkout (the parent of `git rev-parse
#   --git-common-dir`, as `sweep` resolves it); every reader is pointed at that primary. Lane
#   checkouts are the directories `<primary>-lanes/<parent run>/L<n>`.
#
# REPORT (the default) — a fail-SAFE observer: ALWAYS exits 0 (a usage error exits 2). Rows come ONLY
#   from the existing readers below, each run once; nothing is re-derived and nothing is guessed. A
#   reader that is missing or fails yields ONE row in its group whose state is `unknown — <reader>
#   <why>` (action none) — never an empty, "clean" group.
#   Text: a `janitor: report — …` line, then per group a `## <title>` line and per row
#     - <id> | <what>
#         owner: <owner> · age: <age> · state: <state>
#         evidence: <evidence>
#         action: <action> — <reason>      (plus `alt: force-unlock …` on a lock row that offers it)
#   and the group's `note:` lines; last, ONE `janitor: summary — <R> row(s), <A> actionable …` line.
#   --json: ONE object {schema_version: 1, primary, generated_at, groups: [{group, title, rows: [{id,
#     group, what, owner, age_s, state, evidence, action, reason, alt_action}], notes: [..]}], summary:
#     {rows, actionable, by_action: {<action>: n}}} — the same rows as the text, in the same order.
#     age_s is an integer or null; alt_action is "force-unlock" or null.
#
# ROW IDS: `<kind>-<h8>`, h8 = the first 8 hex of the SHA-1 (shasum, else sha1sum; else cksum's CRC)
#   of the row's IDENTITY — what it is plus the state it was judged in, never its age. A row whose
#   identity changes (a pid recycled, a lock re-taken, a sweep verdict or would-remove set changed, a
#   look-alike's session ended) gets a NEW id, so
#   `act` with the old id refuses it. Kinds: reg fin unreg scan lock lane leaks wt br brkept cfgbak
#   mw mpf ret slot caf ext unk.
#
# GROUPS (this order; the closed list):
#   processes        `proc-registry.sh list --scan`: a running entry ⇒ none; overdue / orphaned ⇒
#                    reap, its evidence adding `; command: <its snapshot command line, cut at 200 chars>`;
#                    when that command line is a live host session (the host rule below) the reason says
#                    "<class>, but it is a live host session — reaping ends that session" (or, when a live
#                    host session's ppid chain passes through it, "<class>, but a live host session runs
#                    under it (pid <p>)") and the row's identity carries it (a row picked without the
#                    warning is refused once it applies);
#                    every finished entry together ⇒ ONE `fin` row ⇒ reap (prunes the files, no
#                    signal); each `unreg-<pid>` look-alike ⇒ stop-unregistered (lstart + cmd_hash from
#                    its evidence), EXCEPT, in this order, ⇒ none: the pid ITSELF is a live host session
#                    (the not-the-plugins host rule: an executable whose basename is `claude`, its path
#                    rebuilt across spaces, or `bg-pty-host` — a lane's headless session carries a plugin
#                    scripts path in its --settings) ⇒ "it is a live host session"; its snapshot ppid
#                    chain (at most 64 hops, stopping at pid 1) reaches a live host session ⇒ "its
#                    session is still alive — the session owns it" (a leak from an ENDED session was
#                    reparented and keeps stop-unregistered); a live host session's chain passes
#                    through it (an unregistered wrapper) ⇒ "a live host session runs under it". Its
#                    evidence adds `; command: <its command line, cut at 200 chars>` (and `; session:
#                    pid <p> <its command, cut at 200>`). FAIL-CLOSED: when janitor's own snapshot is
#                    unavailable (JR_SNAP_WHY) or the pid is not in it, every look-alike and every
#                    overdue / orphaned entry is none, "the live-session check could not run (<why>)"
#                    — never stop-unregistered or reap. A `# scan: skipped|unavailable — …` line ⇒
#                    ONE unknown row. The owner column of a registry row says only `plugin — <kind>
#                    entry`: `list` prints no repo / run.
#   locks            `run-lock.sh status --root <c>` and `liveness --root <c>` for the primary and each
#                    lane checkout: holder alive ⇒ none; holder `dead` while the run its owner label
#                    names (`<entry point>:<run_id>`) still says `## Status: running` ⇒ none (that run
#                    may go on in a fresh session; its `--resume` re-takes the lock); holder `dead` while
#                    that run's file exists but states no `## Status:` ⇒ none (cannot be judged); holder
#                    `dead` and age ≥ 1800 s ⇒ lock-reclaim; `dead` and younger ⇒ none, alt force-unlock;
#                    `unknown` (no recorded pid) ⇒ none. An UNLOCKED checkout makes no row (a note
#                    counts them).
#   lanes            per `<primary>/.supervisor/automate/<parent>.lanes`: `automate-helpers.sh
#                    lane-status <parent>.md --json` — one row per lane not `removed` / `abandoned` (or
#                    either with its dir still on disk — `lane-remove --abandon` leaves `abandoned`, not
#                    `removed`): `done` / `abandoned` ⇒ lane-remove; `gone` ⇒ none
#                    (`lane-remove --abandon` is a human's); any other state ⇒ none (its coordinator
#                    owns it). Then
#                    `lane-status <parent>.md --leaks` — the COMPARE mode only, NEVER `--snapshot`
#                    (that writes `<parent>.leaks-snapshot`) — its first line as ONE `leaks` row, shown
#                    as-is (`leaks: unknown — no snapshot …` included). A parent whose every lane is
#                    removed is skipped (a note counts them).
#   worktrees        `automate-helpers.sh sweep --root <primary>` (dry run; it already runs
#                    `worktree-salvage.sh --check-ignored` per worktree, so a worktree is removable only
#                    when sweep says `would-remove`): would-remove ⇒ sweep-apply, its identity carrying
#                    the count and hash of the sorted would-remove set (sweep-apply removes the whole
#                    set, so a set that changed after the report gives every such row a new id and
#                    act refuses the old one); kept worktree / app /
#                    lane / other ⇒ none; every kept branch together ⇒ ONE `brkept` row; age = the tip
#                    commit's age.
#   stale-state      `retention-sweep.sh --project-root <primary>` (report mode): one row per directory
#                    with candidates ⇒ none (`--delete` is irreversible and its own call); per
#                    `<primary>/.supervisor/automate/*.config-backup.json` ⇒ config-restore only when the
#                    primary's `run-lock.sh liveness` is `dead`, or `unknown` with `status` UNLOCKED, AND
#                    its run's file is gone or says `## Status: done`; otherwise none (a live tick, or that
#                    run's own RECONCILE on `--resume`, restores it; an unreadable liveness, a pid-less
#                    held lock or a run file with no `## Status:` cannot be judged);
#                    per `<run_id>.merge-watch` marker whose watcher is gone (no live merge-watch
#                    registry entry has its pid, and the snapshot shows no automate-merge-watch.sh at
#                    it) ⇒ none; per `*.meta-push-failed` marker (`automate-helpers.sh
#                    meta-push-failed <runfile>`) ⇒ none.
#   plugin-adjacent  `ci-slot.sh status --json` (run in the primary): one row per slot holder and
#                    waiter; per snapshot `caffeinate` process with `-w <pid>` (a keep-awake) ⇒ none.
#   not-the-plugins  per snapshot process that is (1) older than the scan threshold
#                    (LOOMWRIGHT_PROC_UNREG_MIN_S, else 3600), (2) not a registry row's live pid, not a
#                    listed look-alike, not a descendant of a live entry (snapshot ppid chain, at most 64
#                    hops) and not this call's own family, and (3) the host's own session (an executable
#                    whose basename is `claude` — an absolute path containing a space is rebuilt word by
#                    word —, or a command line containing `bg-pty-host`) or a `python*`
#                    process ⇒ none, naming the native way to close it. This rule is janitor's; it never
#                    widens what the plugin may stop.
#
# THE ONE SNAPSHOT: one `env TZ=UTC0 LC_ALL=C ps -A -ww -o pid=,ppid=,lstart=,etime=,command=` per call
#   (in a temp file, removed on exit), handed to `proc-registry.sh list --scan` as its
#   LOOMWRIGHT_PROC_PS_SNAPSHOT input, so the registry rows, the look-alikes, the keep-awakes and the
#   not-the-plugin's rows are one moment. A caller's LOOMWRIGHT_PROC_PS_SNAPSHOT is used instead
#   (read-only). HERMETIC SCAN SKIP: under HERMETIC_TEST_ENV=1 with that variable unset no snapshot is
#   taken (proc-registry's own skip then applies) and the snapshot rows read `unknown — skipped`.
#
# ACTIONS (the closed set; each has exactly ONE executor):
#   reap               proc-registry.sh reap --apply <entry id>...
#   stop-unregistered  proc-registry.sh stop-unregistered --pid <p> --start <lstart> --hash <hash> --apply
#                      with the row's recorded lstart + hash (proc-registry re-checks them before TERM and
#                      before KILL, and refuses a live entry or a pid the scan no longer counts); a
#                      look-alike under a live host session is a `none` row, so act refuses it
#   sweep-apply        automate-helpers.sh sweep --apply --root <primary>. Honest limit: sweep has no
#                      per-path filter, so picking ANY sweep row applies the WHOLE sweep (every
#                      would-remove row); it runs once per act call
#   lane-remove        automate-helpers.sh lane-remove <lane dir> (its own fail-CLOSED refusals apply)
#   lock-reclaim       run-lock.sh has no reclaim subcommand (reclaim happens inside acquire, only for a
#                      dead holder at age ≥ 1800 s): act re-reads `liveness --pid <recorded pid>` and
#                      `status`, then runs `acquire --owner human:janitor --root <c>` immediately followed
#                      by `release --owner human:janitor --root <c>` (LOOMWRIGHT_RUN_LOCK_SESSION_ID
#                      unset, so a cross-session re-entry cannot stand in for the reclaim), so janitor
#                      never keeps the lock; a refused acquire is reported and nothing else is tried
#   config-restore     automate-helpers.sh config-restore <primary>/.supervisor/config.json <backup>
#   none               report only; the reason names the native way to close it
#   force-unlock       NOT an action: a lock row's alt_action (dead holder, younger than 1800 s). Only
#                      `act --confirm --force-unlock <id>` runs it — `run-lock.sh release --force-unlock
#                      --owner human:janitor --root <c>` after the same re-check — and the command doc
#                      passes the flag only after a SECOND JAN-ACT confirmation.
#
# ACT — `act` acts ONLY when --confirm is passed, --report is not, and CI is unset or empty; otherwise
#   it prints ONE report-only line (`janitor: report` then ` only — <reason>; nothing acted on`) and
#   acts on nothing (`janitor-report.sh` without `act` prints the report). Then, for the picked ids: it re-runs the reader of every picked row's group
#   immediately before acting, and refuses (one `janitor: refused <id> — <why>` line, nothing done) an
#   id that is no longer in that fresh report (its state changed or it is gone), a `none` row, or an
#   unknown id. Each executed row prints `janitor: act <id> — <action>: <the helper's output>`; then
#   ONE fresh `janitor: summary — …` line. ALWAYS exits 0, a refusal too; a usage error (unknown
#   option, no row id) exits 2.
#
# WRITES: the report writes nothing in the checkout or the registry. Honest limits: `ci-slot.sh
#   status` creates its own (empty) per-repo state dir when it is missing, outside the checkout; the
#   snapshot temp file lives under $TMPDIR until exit; a row can change between the report and the
#   owner's pick, which is why act re-checks.
# bash 3.2 / BSD userland and Linux procps; needs jq (without it --json prints an error object and
#   the lane / ci-slot readers read unknown).

set -uo pipefail

JR_ME="janitor"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JR_PR="$HERE/proc-registry.sh"
JR_RL="$HERE/run-lock.sh"
JR_AH="$HERE/automate-helpers.sh"
JR_CS="$HERE/ci-slot.sh"
JR_RS="$HERE/retention-sweep.sh"
JQ="${LOOMWRIGHT_JQ_BIN:-jq}"
T="$(printf '\t')"
US="$(printf '\037')"
NL='
'
CR="$(printf '\r')"
JR_TTL=1800

jr_usage() {
  cat <<'USAGE'
usage: janitor-report.sh [--json] [--root <checkout>]
       janitor-report.sh act [--confirm] [--report] [--force-unlock] [--root <checkout>] <row id>...
See the header comment of janitor-report.sh for the full contract.
USAGE
}

# ---- primitives -------------------------------------------------------------------------------------

_jr_now() { date +%s 2>/dev/null || echo 0; }
_jr_iso() { date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null; }
_jr_is_uint() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac; return 0; }
_jr_has_jq() { command -v "$JQ" >/dev/null 2>&1; }
# _jr_clean <text> — one field: tabs, newlines and the unit separator become spaces
_jr_clean() { local v="${1//$T/ }"; v="${v//$NL/ }"; v="${v//$CR/ }"; printf '%s' "${v//$US/ }"; }
_jr_hash() {
  if command -v shasum >/dev/null 2>&1; then printf '%s' "$1" | shasum | cut -c1-8
  elif command -v sha1sum >/dev/null 2>&1; then printf '%s' "$1" | sha1sum | cut -c1-8
  else printf '%s' "$1" | cksum | cut -d' ' -f1; fi
}
# _jr_etime_s <[[dd-]hh:]mm:ss> — seconds; empty when malformed
_jr_etime_s() {
  awk -v e="$1" 'BEGIN { d = 0
    if (index(e, "-")) { split(e, a, "-"); d = a[1]; e = a[2] }
    if (e !~ /^[0-9]+(:[0-9]+)*$/ || d !~ /^[0-9]+$/) exit
    n = split(e, p, ":"); s = 0; for (i = 1; i <= n; i++) s = s * 60 + p[i]
    print d * 86400 + s }'
}
# _jr_mtime <file> — epoch mtime, GNU stat first, then BSD; validated numeric, empty otherwise
_jr_mtime() {
  local m
  m="$(stat -c %Y "$1" 2>/dev/null)"; _jr_is_uint "$m" && { printf '%s' "$m"; return 0; }
  m="$(stat -f %m "$1" 2>/dev/null)"; _jr_is_uint "$m" && { printf '%s' "$m"; return 0; }
  return 0
}
_jr_human() {
  local a="$1"
  _jr_is_uint "$a" || { printf -- '-'; return 0; }
  if [ "$a" -ge 86400 ]; then printf '%dd%02dh' $((a / 86400)) $((a % 86400 / 3600))
  elif [ "$a" -ge 3600 ]; then printf '%dh%02dm' $((a / 3600)) $((a % 3600 / 60))
  elif [ "$a" -ge 60 ]; then printf '%dm%02ds' $((a / 60)) $((a % 60))
  else printf '%ds' "$a"; fi
}

# ---- the row store ------------------------------------------------------------------------------------
# JR_ROWS: one TSV line per row — id group what owner age_s state evidence action reason alt data
# (data, never printed, is what the executor needs: \037-separated). JR_NOTES: `group<TAB>note` lines.
JR_ROWS=""
JR_NOTES=""

# _jr_row <kind> <group> <identity> <what> <owner> <age_s> <state> <evidence> <action> <reason> [alt] [data]
_jr_row() {
  local id
  id="$1-$(_jr_hash "$2|$3")"
  JR_ROWS="$JR_ROWS$id$T$2$T$(_jr_clean "$4")$T$(_jr_clean "$5")$T$6$T$(_jr_clean "$7")$T$(_jr_clean "$8")$T$9$T$(_jr_clean "${10}")$T${11:-}$T${12:-}
"
}
_jr_note() { JR_NOTES="$JR_NOTES$1$T$(_jr_clean "$2")
"; }
# _jr_unknown <group> <reader> <why> — the fail-SAFE row of a reader that is missing or failed
_jr_unknown() {
  _jr_row unk "$1" "unknown|$2|$3" "$2" "-" "" "unknown — $2 $3" "$2 could not be read" none \
    "report only — nothing in this group is judged until $2 answers"
}

# ---- context ------------------------------------------------------------------------------------------

JR_PRIMARY=""
# _jr_primary <root> — sets JR_PRIMARY (the primary checkout); 1 when it cannot be resolved
_jr_primary() {
  local root="$1" common
  common="$(git -C "$root" rev-parse --git-common-dir 2>/dev/null)" || return 1
  [ -n "$common" ] || return 1
  JR_PRIMARY="$(cd "$root" 2>/dev/null && cd "$common/.." 2>/dev/null && pwd -P)"
  [ -n "$JR_PRIMARY" ] && [ -d "$JR_PRIMARY" ]
}
# _jr_run_status <run file> — its first `## Status:` value (running, paused, done, …); empty when none
_jr_run_status() { awk '/^## Status:/ { sub(/^## Status:[ \t]*/, ""); sub(/[ \t].*$/, ""); print; exit }' "$1" 2>/dev/null; }
_jr_lane_dirs() {
  local d
  for d in "$JR_PRIMARY-lanes"/*/L*; do [ -d "$d" ] && printf '%s\n' "$d"; done
  return 0
}

# ---- the ONE snapshot ---------------------------------------------------------------------------------
JR_SNAP_FILE=""
JR_SNAP_OWN=0
JR_SNAP_WHY=""
JR_SNAP=""      # parsed: pid TAB ppid TAB lstart TAB etime TAB command
_jr_cleanup() { [ "$JR_SNAP_OWN" = 1 ] && [ -n "$JR_SNAP_FILE" ] && rm -f "$JR_SNAP_FILE"; return 0; }
trap _jr_cleanup EXIT

# _jr_snapshot — take (or adopt) the snapshot; JR_SNAP_WHY = `skipped — …` / `unavailable — …` otherwise
_jr_snapshot() {
  local raw
  JR_SNAP_WHY=""; JR_SNAP=""; JR_HOSTS=""; JR_HOSTS_DONE=0
  if [ -n "${LOOMWRIGHT_PROC_PS_SNAPSHOT:-}" ]; then
    JR_SNAP_FILE="$LOOMWRIGHT_PROC_PS_SNAPSHOT"; JR_SNAP_OWN=0
    [ -r "$JR_SNAP_FILE" ] || { JR_SNAP_WHY="unavailable — LOOMWRIGHT_PROC_PS_SNAPSHOT is unreadable"; return 1; }
  elif [ "${HERMETIC_TEST_ENV:-}" = 1 ]; then
    JR_SNAP_WHY="skipped — HERMETIC_TEST_ENV=1 without LOOMWRIGHT_PROC_PS_SNAPSHOT"; return 1
  else
    JR_SNAP_FILE="$(mktemp "${TMPDIR:-/tmp}/janitor-snap.XXXXXX" 2>/dev/null)" || { JR_SNAP_FILE=""; JR_SNAP_WHY="unavailable — no temp file"; return 1; }
    JR_SNAP_OWN=1
    env TZ=UTC0 LC_ALL=C ps -A -ww -o pid=,ppid=,lstart=,etime=,command= > "$JR_SNAP_FILE" 2>/dev/null \
      || { JR_SNAP_WHY="unavailable — ps failed"; return 1; }
  fi
  raw="$(cat "$JR_SNAP_FILE" 2>/dev/null)"
  JR_SNAP="$(printf '%s\n' "$raw" | awk '
    function tok() { if (!match(line, /^[^ \t]+/)) return ""; t = substr(line, 1, RLENGTH); line = substr(line, RLENGTH + 1); sub(/^[ \t]+/, "", line); return t }
    { line = $0; sub(/^[ \t]+/, "", line); pid = tok(); ppid = tok()
      if (pid !~ /^[0-9]+$/ || ppid !~ /^[0-9]+$/) next
      if (!match(line, /^[^ \t]+[ \t]+[^ \t]+[ \t]+[^ \t]+[ \t]+[^ \t]+[ \t]+[^ \t]+/)) next
      ls = substr(line, 1, RLENGTH); line = substr(line, RLENGTH + 1); sub(/^[ \t]+/, "", line)
      et = tok(); if (et == "") next
      sub(/[ \t]+$/, "", line); printf "%s\t%s\t%s\t%s\t%s\n", pid, ppid, ls, et, line }')"
  [ -n "$JR_SNAP" ] || { JR_SNAP_WHY="unavailable — the process snapshot is empty"; return 1; }
  return 0
}
_jr_snap_get() { printf '%s\n' "$JR_SNAP" | awk -F'\t' -v p="$1" -v c="$2" '$1 == p { print $c; exit }'; }
# _jr_is_host_cmd <command line> — 0 for the host's own session: an executable whose basename is `claude`,
# or a command line containing `bg-pty-host` (the one host rule; not-the-plugins and the session check
# share it). `ps` prints argv joined by spaces, so an absolute executable path that contains a space (the
# desktop app's `/Users/<n>/Library/Application Support/Claude/…/MacOS/claude`) is rebuilt word by word:
# a continuation word never starts with `/` or `-`, so `python3 /x/claude` is not a host.
_jr_is_host_cmd() {
  local rest="$1" exe w
  case "$1" in *bg-pty-host*) return 0 ;; esac
  exe="${rest%% *}"; rest="${rest#"$exe"}"
  while :; do
    [ "${exe##*/}" = claude ] && return 0
    case "$exe" in /*) ;; *) return 1 ;; esac
    rest="${rest# }"; w="${rest%% *}"
    case "$w" in ''|/*|-*) return 1 ;; esac
    exe="$exe $w"; rest="${rest#"$w"}"
  done
}
# _jr_live_session <pid> — prints the pid of the nearest live host session in <pid>'s snapshot ppid chain
# (at most 64 hops, stopping at pid 1); nothing when none. A process whose session ended was reparented
# (to pid 1, or a subreaper) and has none.
_jr_live_session() {
  local p k=0
  p="$(_jr_snap_get "$1" 2)"
  while _jr_is_uint "$p" && [ "$p" -gt 1 ] && [ "$k" -lt 64 ]; do
    if _jr_is_host_cmd "$(_jr_snap_get "$p" 5)"; then printf '%s' "$p"; return 0; fi
    p="$(_jr_snap_get "$p" 2)"; k=$((k + 1))
  done
  return 0
}
# _jr_host_below <pid> — prints the pid of a live host session whose snapshot ppid chain (at most 64 hops)
# passes through <pid> (a wrapper whose descendant is a session); nothing when none. One awk pass.
# The snapshot's host-session pids are listed once per snapshot (JR_HOSTS, reset by _jr_snapshot).
JR_HOSTS=""
JR_HOSTS_DONE=0
# (call _jr_hosts_init in the calling shell first: _jr_host_below runs inside $(...), so its own fill is lost)
_jr_hosts_init() {
  local p c
  [ "$JR_HOSTS_DONE" != 1 ] || return 0
  JR_HOSTS_DONE=1; JR_HOSTS=" "
  while IFS="$T" read -r p _ _ _ c; do
    [ -n "$p" ] && _jr_is_host_cmd "$c" && JR_HOSTS="$JR_HOSTS$p "
  done <<<"$JR_SNAP"
  return 0
}
_jr_host_below() {
  _jr_hosts_init
  [ "$JR_HOSTS" != " " ] || return 0
  printf '%s\n' "$JR_SNAP" | awk -F'\t' -v t="$1" -v hs="$JR_HOSTS" '
    { pp[$1] = $2 }
    END { n = split(hs, h, " ")
      for (i = 1; i <= n; i++) { if (h[i] == t) continue
        q = pp[h[i]]; for (k = 0; k < 64 && q != "" && q > 1; k++) {
        if (q == t) { print h[i]; exit }; q = pp[q] } } }'
}
# _jr_cut <text> — at most 200 chars, `...` marking a cut
_jr_cut() { if [ "${#1}" -le 200 ]; then printf '%s' "$1"; else printf '%s...' "${1:0:200}"; fi; }
# _jr_pr <args> — proc-registry.sh with the shared snapshot (when this call owns or adopted one)
_jr_pr() {
  if [ -z "$JR_SNAP_WHY" ] && [ -n "$JR_SNAP_FILE" ]; then
    LOOMWRIGHT_PROC_PS_SNAPSHOT="$JR_SNAP_FILE" bash "$JR_PR" "$@"
  else
    bash "$JR_PR" "$@"
  fi
}

# the registry listing, read ONCE per call (processes, merge-watch markers and not-the-plugin's share it)
JR_PRLIST=""
JR_PRLIST_DONE=0
_jr_prlist() {
  [ "$JR_PRLIST_DONE" = 1 ] && return 0
  JR_PRLIST_DONE=1
  [ -f "$JR_PR" ] || return 0
  JR_PRLIST="$(_jr_pr list --scan 2>/dev/null)"
  return 0
}

# ---- group: processes ---------------------------------------------------------------------------------
_jr_c_processes() {
  local g=processes id kind pid age class evid a fin="" nfin=0 rule lst hash seen=0 note cmd sess full why host hb
  [ -f "$JR_PR" ] || { _jr_unknown "$g" proc-registry.sh "missing ($JR_PR)"; return 0; }
  _jr_prlist
  [ -n "$JR_PRLIST" ] || { _jr_unknown "$g" "proc-registry.sh list --scan" "printed nothing"; return 0; }
  _jr_hosts_init
  while IFS="$T" read -r id kind pid age class evid; do
    case "$id" in
      '#'*|'(no entries)'|'') continue ;;
    esac
    seen=$((seen + 1))
    a="${age%s}"; _jr_is_uint "$a" || a=""
    if [ "$kind" = unregistered ]; then
      rule="${evid%%; lstart=*}"; lst="${evid#*; lstart=}"; lst="${lst%%; cmd_hash=*}"; hash="${evid##*; cmd_hash=}"
      full="$(_jr_snap_get "$pid" 5)"; cmd="$(_jr_cut "$full")"
      # fail CLOSED: without janitor's own snapshot (or with the pid missing from it) no session check ran
      if [ -n "$JR_SNAP_WHY" ] || [ -z "$full" ]; then
        why="${JR_SNAP_WHY:-pid $pid is not in the process snapshot}"
        _jr_row unreg "$g" "unreg|$pid|$lst|$hash|nocheck:$why" "unregistered process pid $pid" "unregistered (looks like the plugin's)" \
          "$a" "running, unregistered, not judged" "$evid; command: ${cmd:-unknown}" none \
          "the live-session check could not run ($why) — report only until the snapshot is readable"
        continue
      fi
      # the pid itself a host session (a lane's headless session whose --settings carry a plugin scripts path)
      if _jr_is_host_cmd "$full"; then
        _jr_row unreg "$g" "unreg|$pid|$lst|$hash|host:self" "unregistered process pid $pid" "unregistered — it is a live host session" \
          "$a" "running, unregistered, a live host session" "$evid; command: $cmd" none \
          "it is a live host session — it owns itself; end that session from the host"
        continue
      fi
      sess="$(_jr_live_session "$pid")"
      if [ -n "$sess" ]; then
        _jr_row unreg "$g" "unreg|$pid|$lst|$hash|session:$sess" "unregistered process pid $pid" "unregistered — a descendant of live host session pid $sess" \
          "$a" "running, unregistered, its session alive" "$evid; command: $cmd; session: pid $sess $(_jr_cut "$(_jr_snap_get "$sess" 5)")" none \
          "its session is still alive — the session owns it (pid $sess); it ends with that session, or stop it from there"
        continue
      fi
      sess="$(_jr_host_below "$pid")"
      if [ -n "$sess" ]; then
        _jr_row unreg "$g" "unreg|$pid|$lst|$hash|below:$sess" "unregistered process pid $pid" "unregistered — live host session pid $sess runs under it" \
          "$a" "running, unregistered, a live session below it" "$evid; command: $cmd; session: pid $sess $(_jr_cut "$(_jr_snap_get "$sess" 5)")" none \
          "a live host session runs under it (pid $sess) — stopping it would orphan that session; it ends when the session does"
        continue
      fi
      _jr_row unreg "$g" "unreg|$pid|$lst|$hash" "unregistered process pid $pid" "unregistered (looks like the plugin's)" \
        "$a" "running, unregistered" "$evid; command: $cmd" stop-unregistered \
        "it looks like the plugin's ($rule), no registry entry owns it, and it is not a live host session, none is its ancestor and none runs under it — stopped only on your pick, after proc-registry re-checks its lstart and command-line hash" \
        "" "$pid$US$lst$US$hash"
      continue
    fi
    case "$class" in
      finished) fin="$fin $id"; nfin=$((nfin + 1)) ;;
      overdue|orphaned)
        # its command line in the evidence; a live host session at its pid is named in the reason and folded
        # into the identity, so a row picked without that warning is refused once it applies
        if [ -n "$JR_SNAP_WHY" ]; then   # fail CLOSED: the live-host-session check cannot run
          _jr_row reg "$g" "reg|$id|$class|nocheck" "$kind process pid $pid (registry entry $id)" "plugin — $kind entry" "$a" "$class" \
            "$evid; command: unknown (process snapshot $JR_SNAP_WHY)" none \
            "$class, but the live-host-session check could not run ($JR_SNAP_WHY) — report only until the snapshot is readable" "" ""
          continue
        fi
        full="$(_jr_snap_get "$pid" 5)"
        hb="$(_jr_host_below "$pid")"
        if [ -n "$full" ] && _jr_is_host_cmd "$full"; then
          host="|host"; why="$class, but it is a live host session — reaping ends that session; "
        elif [ -n "$hb" ]; then
          host="|below:$hb"; why="$class, but a live host session runs under it (pid $hb) — reaping it can end or orphan that session; "
        else
          host=""; why="$class: "
        fi
        cmd="$(_jr_cut "$full")"
        _jr_row reg "$g" "reg|$id|$class$host" "$kind process pid $pid (registry entry $id)" "plugin — $kind entry" "$a" "$class" \
          "$evid; command: ${cmd:-unknown}" reap \
          "${why}reap re-checks its lstart and command-line hash, sends TERM, then KILL after its grace only if it still matches" "" "$id" ;;
      *)
        _jr_row reg "$g" "reg|$id|$class" "$kind process pid $pid (registry entry $id)" "plugin — $kind entry" "$a" "${class:-unknown}" "$evid" none \
          "running within its cap — the run that started it owns it" "" "" ;;
    esac
  done <<<"$JR_PRLIST"
  if [ "$nfin" -gt 0 ]; then
    _jr_row fin "$g" "fin|$(printf '%s\n' $fin | env LC_ALL=C sort | tr '\n' ' ')" "$nfin finished registry entr$( [ "$nfin" = 1 ] && echo y || echo ies)" \
      "plugin — registry" "" finished "pid gone or recycled: $(printf '%s\n' $fin | head -5 | tr '\n' ' ')$( [ "$nfin" -gt 5 ] && printf '+%s more' $((nfin - 5)))" reap \
      "their processes are gone; reap prunes the entry files and sends no signal" "" "${fin# }"
  fi
  note="$(printf '%s\n' "$JR_PRLIST" | grep '^# scan: ' | head -1)"
  case "$note" in
    "# scan: skipped"*|"# scan: unavailable"*)
      _jr_row scan "$g" "scan|${note#\# scan: }" "unregistered look-alike scan" "-" "" "unknown — proc-registry.sh list --scan ${note#\# scan: }" \
        "$note" none "report only — look-alikes are not judged while the scan does not run" ;;
    "") _jr_note "$g" "proc-registry.sh list --scan printed no scan line" ;;
    *) _jr_note "$g" "proc-registry.sh: $seen row(s); ${note#\# }" ;;
  esac
  return 0
}

# ---- group: locks -------------------------------------------------------------------------------------
_jr_lock_one() {   # _jr_lock_one <checkout> <label>
  local c="$1" st owner pid age lv
  st="$(bash "$JR_RL" status --root "$c" 2>/dev/null | head -1)"
  case "$st" in
    UNLOCKED) JR_UNLOCKED=$((JR_UNLOCKED + 1)); return 0 ;;
    "LOCKED owner="*" pid="*" age="*) ;;
    *) _jr_unknown locks "run-lock.sh status --root $c" "printed '${st:-nothing}'"; return 0 ;;
  esac
  owner="${st#LOCKED owner=}"; owner="${owner% pid=*}"
  pid="${st##* pid=}"; pid="${pid%% age=*}"
  age="${st##* age=}"; _jr_is_uint "$age" || age=""
  lv="$(bash "$JR_RL" liveness --root "$c" 2>/dev/null | head -1)"
  local what="run lock — $2 $c" ev="$st; liveness=$lv" run rst
  # the run the owner label names (`<entry point>:<run_id>`) — its run file's ## Status: line
  run="${owner#*:}"; rst=""
  [ "$run" != "$owner" ] && [ -f "$c/.supervisor/automate/$run.md" ] && rst="$(_jr_run_status "$c/.supervisor/automate/$run.md")"
  [ -z "$rst" ] || ev="$ev; run $run: $rst"
  case "$lv" in
    alive) _jr_row lock locks "lock|$c|$owner|$pid|alive" "$what" "$owner" "$age" "held, holder alive" "$ev" none \
             "its holder is alive — the run owns the lock (it releases it when it ends)" ;;
    dead)
      if [ "$run" != "$owner" ] && [ -f "$c/.supervisor/automate/$run.md" ] && [ -z "$rst" ]; then
        # fail CLOSED: the run file is there but states no ## Status (unreadable or malformed)
        _jr_row lock locks "lock|$c|$owner|$pid|dead|nostatus" "$what" "$owner" "$age" "held, holder dead, run $run states no status" "$ev" none \
          "its holder pid is dead but run $run's file states no \`## Status:\` — whether that run goes on cannot be judged; never reclaimed from here"
      elif [ "$rst" = running ]; then
        _jr_row lock locks "lock|$c|$owner|$pid|dead|running" "$what" "$owner" "$age" "held, holder dead, run still says running" "$ev" none \
          "its holder pid is dead but run $run still says running (it may continue in a fresh session) — \`/automate --resume $run\` re-takes it; never reclaimed from here"
      elif [ -n "$age" ] && [ "$age" -ge "$JR_TTL" ]; then
        _jr_row lock locks "lock|$c|$owner|$pid|dead|reclaim" "$what" "$owner" "$age" "held, holder dead, age >= ${JR_TTL}s" "$ev" lock-reclaim \
          "reclaimable: the holder is dead and the lock is at least ${JR_TTL}s old — run-lock acquire reclaims it and janitor releases it at once" "" "$c$US$pid"
      else
        _jr_row lock locks "lock|$c|$owner|$pid|dead|young" "$what" "$owner" "$age" "held, holder dead, younger than ${JR_TTL}s" "$ev" none \
          "not reclaimable until it is ${JR_TTL}s old (run-lock reclaims it then on the next acquire); force-unlock is offered only with a second JAN-ACT confirmation" \
          force-unlock "$c$US$pid"
      fi ;;
    *) _jr_row lock locks "lock|$c|$owner|$pid|${lv:-none}" "$what" "$owner" "$age" "held, holder ${lv:-unreadable}" "$ev" none \
         "the holder cannot be judged (no recorded pid, or liveness unreadable) — run-lock reclaims a pid-less lock at ${JR_TTL}s on the next acquire" ;;
  esac
  return 0
}
_jr_c_locks() {
  local d n=1
  [ -f "$JR_RL" ] || { _jr_unknown locks run-lock.sh "missing ($JR_RL)"; return 0; }
  JR_UNLOCKED=0
  _jr_lock_one "$JR_PRIMARY" primary
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    n=$((n + 1)); _jr_lock_one "$d" lane
  done <<<"$(_jr_lane_dirs)"
  _jr_note locks "$n checkout(s) checked (primary + lanes), $JR_UNLOCKED unlocked"
  return 0
}

# ---- group: lanes -------------------------------------------------------------------------------------
_jr_c_lanes() {
  local g=lanes t rf parent js rows n=0 skipped=0 lk lane state path item pr prs started why now age act reason
  local found=0
  now="$(_jr_now)"
  for t in "$JR_PRIMARY"/.supervisor/automate/*.lanes; do
    [ -f "$t" ] || continue
    found=1
    parent="$(basename "$t" .lanes)"; rf="${t%.lanes}.md"
    if ! _jr_has_jq; then _jr_unknown "$g" "lane-status $parent" "(jq not found)"; continue; fi
    js="$(bash "$JR_AH" lane-status "$rf" --json 2>/dev/null)"
    if [ -z "$js" ] || ! printf '%s' "$js" | "$JQ" -e '.lanes | type == "array"' >/dev/null 2>&1; then
      _jr_unknown "$g" "lane-status $parent --json" "printed no lane document"; continue
    fi
    # \037-joined, never TSV: IFS whitespace (a tab) would collapse an empty field and shift the rest
    rows="$(printf '%s' "$js" | "$JQ" -r '.lanes[] | [.lane, (.state // "unknown"), (.path // ""), (.item // ""), (.pr // ""), (.pr_state // ""), (.started_at // ""), (.reason // "")] | map(tostring | gsub("[\t\n\u001f]"; " ")) | join("\u001f")' 2>/dev/null)" \
      || { _jr_unknown "$g" "lane-status $parent --json" "unparseable"; continue; }
    n=0
    while IFS="$US" read -r lane state path item pr prs started why; do
      [ -n "$lane" ] || continue
      # lane-remove writes `removed`, or `abandoned` under --abandon, only after its rm -rf: both are gone
      case "$state" in removed|abandoned) [ -d "$path" ] || continue ;; esac
      n=$((n + 1))
      age=""
      [ -n "$started" ] && age="$("$JQ" -rn --arg s "$started" --argjson n "$now" '$n - ($s | fromdateiso8601)' 2>/dev/null)"
      _jr_is_uint "$age" || age=""
      case "$state" in
        done|abandoned) act=lane-remove; reason="$state, its clone still on disk — lane-remove salvages and removes it (it refuses unpushed, dirty or live lanes)" ;;
        gone) act=none; reason="its PR closed unmerged — only a human runs \`automate-helpers.sh lane-remove $path --abandon\`" ;;
        *) act=none; reason="$state — the wave's coordinator owns it (\`/automate --resume $parent\`; fleet-closeout removes it after merge)" ;;
      esac
      _jr_row lane "$g" "lane|$path|$state" "lane $lane of $parent" "run $parent" "$age" "$state${prs:+ (PR $prs)}" \
        "path $path; item ${item:--}; pr ${pr:--}${why:+; $why}" "$act" "$reason" "" "$path"
    done <<<"$rows"
    if [ "$n" -eq 0 ]; then skipped=$((skipped + 1)); continue; fi
    lk="$(bash "$JR_AH" lane-status "$rf" --leaks 2>/dev/null | head -1)"
    [ -n "$lk" ] || lk="leaks: unknown — lane-status --leaks printed nothing"
    _jr_row leaks "$g" "leaks|$parent|${lk%% (vs snapshot*}" "leak check of wave $parent" "run $parent" "" "$lk" \
      "lane-status $rf --leaks (compare mode)" none "report only — \`lane-status $rf --leaks\` prints each changed section"
  done
  [ "$found" = 1 ] || _jr_note "$g" "no lane table under $JR_PRIMARY/.supervisor/automate/"
  [ "$skipped" -eq 0 ] || _jr_note "$g" "$skipped wave(s) skipped: every lane removed"
  return 0
}

# ---- group: worktrees ---------------------------------------------------------------------------------
_jr_tip_age() {   # _jr_tip_age <git dir or worktree> <rev>
  local ct
  ct="$(git -C "$1" log -1 --format=%ct "$2" 2>/dev/null)"
  _jr_is_uint "$ct" && printf '%s' $(( $(_jr_now) - ct ))
  return 0
}
_jr_c_worktrees() {
  local g=worktrees out line head verb kind subj reason nact kept="" nkept=0 sum act owner age wset
  [ -f "$JR_AH" ] || { _jr_unknown "$g" automate-helpers.sh "missing ($JR_AH)"; return 0; }
  out="$(bash "$JR_AH" sweep --root "$JR_PRIMARY" 2>/dev/null)"
  sum="$(printf '%s\n' "$out" | grep '^sweep: summary — ' | tail -1)"
  [ -n "$sum" ] || { _jr_unknown "$g" "automate-helpers.sh sweep" "printed no summary line"; return 0; }
  case "$sum" in *"skipped:"*) _jr_unknown "$g" "automate-helpers.sh sweep" "${sum#sweep: summary — }"; return 0 ;; esac
  nact="$(printf '%s\n' "$out" | grep -c '^sweep: would-remove ')"
  # the would-remove SET (sorted `<kind> <subject>` heads): folded into every sweep-apply row's identity,
  # because sweep-apply removes the whole set — a set that changed after the report gives every row a new id
  wset="$(printf '%s\n' "$out" | awk '/^sweep: would-remove / { sub(/ — .*$/, ""); sub(/^sweep: would-remove /, ""); print }' | env LC_ALL=C sort)"
  wset="$nact:$(_jr_hash "$wset")"
  while IFS= read -r line; do
    case "$line" in "sweep: would-remove "*|"sweep: kept "*) ;; *) continue ;; esac
    head="${line%% — *}"; reason="${line#* — }"
    head="${head#sweep: }"; verb="${head%% *}"; head="${head#* }"; kind="${head%% *}"; subj="${head#* }"
    if [ "$verb" = kept ] && [ "$kind" = branch ]; then kept="$kept$subj$US"; nkept=$((nkept + 1)); continue; fi
    case "$kind" in
      worktree) owner="plugin-made worktree" ;; app) owner="the host app" ;; lane) owner="a lane" ;;
      branch) owner="local branch" ;; *) owner="unknown origin" ;;
    esac
    if [ "$kind" = branch ]; then age="$(_jr_tip_age "$JR_PRIMARY" "refs/heads/$subj")"; else age="$(_jr_tip_age "$subj" HEAD)"; fi
    if [ "$verb" = would-remove ]; then
      act=sweep-apply
      _jr_row "$( [ "$kind" = branch ] && echo br || echo wt)" "$g" "sweep|$verb|$kind|$subj|$reason|set:$wset" "$kind $subj" "$owner" "$age" "removable" "$reason" "$act" \
        "the sweep's squash-safe rule holds; sweep-apply runs the WHOLE sweep ($nact would-remove row(s)) — sweep has no per-path filter" "" "$JR_PRIMARY"
    else
      _jr_row wt "$g" "sweep|$verb|$kind|$subj|$reason" "$kind $subj" "$owner" "$age" "kept" "$reason" none \
        "report only — the sweep keeps it for the reason in its evidence; \`sweep --apply\` never removes it while that holds"
    fi
  done <<<"$out"
  if [ "$nkept" -gt 0 ]; then
    _jr_row brkept "$g" "brkept|$kept" "$nkept local branch(es) kept" "local branches" "" "kept" \
      "$(printf '%s' "$kept" | tr '\037' '\n' | head -5 | tr '\n' ' ')$( [ "$nkept" -gt 5 ] && printf '+%s more' $((nkept - 5)))" none \
      "report only — each fails the sweep's squash-safe rule (newest PR not merged at the tip, the current or base branch, or checked out); \`automate-helpers.sh sweep\` names each reason"
  fi
  _jr_note "$g" "$sum"
  return 0
}

# ---- group: stale-state -------------------------------------------------------------------------------
_jr_c_state() {
  local g=stale-state ad="$JR_PRIMARY/.supervisor/automate" out line dir sum cnt f lv run rst age m pid pr live cmd l mt now
  now="$(_jr_now)"
  # retention-sweep (report mode)
  if [ -f "$JR_RS" ]; then
    out="$(bash "$JR_RS" --project-root "$JR_PRIMARY" 2>/dev/null)"
    sum="$(printf '%s\n' "$out" | grep '^retention-sweep: summary — ' | tail -1)"
    if [ -z "$sum" ]; then
      _jr_unknown "$g" retention-sweep.sh "printed no summary line"
    else
      dir=""
      while IFS= read -r line; do
        case "$line" in
          "  candidates: "*)
            cnt="${line#  candidates: }"; cnt="${cnt%% *}"
            if _jr_is_uint "$cnt" && [ "$cnt" -gt 0 ]; then
              _jr_row ret "$g" "ret|$dir|$cnt" ".supervisor/$dir exhaust older than the threshold" "this checkout" "" "$cnt candidate file(s)" "${line#  }" none \
                "report only — \`retention-sweep.sh --project-root $JR_PRIMARY --delete\` removes them (irreversible)"
            fi ;;
          " "*|"") ;;
          *": "*) dir="${line%%: *}" ;;
        esac
      done <<<"$out"
      _jr_note "$g" "$sum"
    fi
  else
    _jr_unknown "$g" retention-sweep.sh "missing ($JR_RS)"
  fi
  [ -d "$ad" ] || { _jr_note "$g" "no $ad"; return 0; }
  # stranded config backups
  lv=""
  for f in "$ad"/*.config-backup.json; do
    [ -f "$f" ] || continue
    [ -n "$lv" ] || lv="$(bash "$JR_RL" liveness --root "$JR_PRIMARY" 2>/dev/null | head -1)"
    run="$(basename "$f" .config-backup.json)"; mt="$(_jr_mtime "$f")"; age=""; [ -n "$mt" ] && age=$((now - mt))
    rst=""; [ -f "$ad/$run.md" ] && rst="$(_jr_run_status "$ad/$run.md")"
    # `unknown` is UNLOCKED or a pid-less lock: only the former counts as no live run
    [ "$lv" != unknown ] || [ "$(bash "$JR_RL" status --root "$JR_PRIMARY" 2>/dev/null | head -1)" = UNLOCKED ] || lv="held with no recorded pid"
    if [ "$lv" = alive ]; then
      _jr_row cfgbak "$g" "cfgbak|$f|$(cksum < "$f" 2>/dev/null)|alive" "config backup of run $run" "run $run" "$age" "in use — a live run holds this checkout's lock" "$f" none \
        "a live run's tick owns it and restores it itself"
    elif [ "$lv" != dead ] && [ "$lv" != unknown ]; then   # fail CLOSED: the lock holder cannot be judged
      _jr_row cfgbak "$g" "cfgbak|$f|$(cksum < "$f" 2>/dev/null)|lock:${lv:-unreadable}" "config backup of run $run" "run $run" "$age" "run lock: ${lv:-unreadable}" "$f" none \
        "this checkout's run lock cannot be judged (${lv:-liveness unreadable}) — a live run may still own the backup; report only"
    elif [ -f "$ad/$run.md" ] && [ -z "$rst" ]; then   # fail CLOSED: its run file states no status
      _jr_row cfgbak "$g" "cfgbak|$f|$(cksum < "$f" 2>/dev/null)|nostatus" "config backup of run $run" "run $run" "$age" "run $run states no status" "$f" none \
        "run $run's file states no \`## Status:\` — whether that run goes on cannot be judged; report only"
    elif [ -n "$rst" ] && [ "$rst" != done ]; then
      _jr_row cfgbak "$g" "cfgbak|$f|$(cksum < "$f" 2>/dev/null)|$rst" "config backup of run $run" "run $run" "$age" "run $run says $rst" "$f" none \
        "its run is not done — that run's own RECONCILE restores a crash-stranded backup on \`/automate --resume $run\`"
    else
      _jr_row cfgbak "$g" "cfgbak|$f|$(cksum < "$f" 2>/dev/null)|${lv:-none}" "config backup of run $run" "run $run" "$age" "stranded (run lock: ${lv:-unknown})" "$f" config-restore \
        "no live run holds this checkout's lock — config-restore puts .supervisor/config.json back byte-for-byte and removes the backup" "" \
        "$JR_PRIMARY/.supervisor/config.json$US$f"
    fi
  done
  # merge-watch markers whose watcher is gone
  for m in "$ad"/*.merge-watch; do
    [ -f "$m" ] || continue
    pid="$(awk -F'\t' '$1 == "pid" { print $2; exit }' "$m" 2>/dev/null)"
    pr="$(awk -F'\t' '$1 == "pr_url" { print $2; exit }' "$m" 2>/dev/null)"
    _jr_prlist
    live="$(printf '%s\n' "$JR_PRLIST" | awk -F'\t' -v p="$pid" '$2 == "merge-watch" && $3 == p && $5 != "finished" { print "y"; exit }')"
    if [ -z "$live" ] && [ -z "$JR_SNAP_WHY" ] && [ -n "$JR_SNAP" ]; then
      cmd="$(_jr_snap_get "$pid" 5)"
      case "$cmd" in *automate-merge-watch.sh*) live=y ;; esac
    fi
    [ -z "$live" ] || continue
    run="$(basename "$m" .merge-watch)"; mt="$(_jr_mtime "$m")"; age=""; [ -n "$mt" ] && age=$((now - mt))
    _jr_row mw "$g" "mw|$m|$pid|$pr" "merge-watch marker of run $run" "run $run" "$age" "stale — watcher pid ${pid:--} is gone" \
      "$m; pid ${pid:--}; pr ${pr:--}" none \
      "report only — the next merge-watch launch for this run reclaims the marker; deleting it by hand is safe"
  done
  # meta-push failures
  for m in "$ad"/*.meta-push-failed; do
    [ -f "$m" ] || continue
    run="$(basename "$m" .meta-push-failed)"
    l="$(bash "$JR_AH" meta-push-failed "$ad/$run.md" 2>/dev/null | head -1)"
    mt="$(_jr_mtime "$m")"; age=""; [ -n "$mt" ] && age=$((now - mt))
    _jr_row mpf "$g" "mpf|$m|$l" "metadata push failure of run $run" "run $run" "$age" "push failed" "${l:-$m}" none \
      "report only — the run's next trail push retries it (\`/automate --resume $run\`), or publish by hand with meta-sync.sh push"
  done
  return 0
}

# ---- group: plugin-adjacent ---------------------------------------------------------------------------
_jr_c_adjacent() {
  local g=plugin-adjacent js rows k pid co name st now age w p cmd et ls
  now="$(_jr_now)"
  if [ ! -f "$JR_CS" ]; then _jr_unknown "$g" ci-slot.sh "missing ($JR_CS)"
  elif ! _jr_has_jq; then _jr_unknown "$g" "ci-slot.sh status --json" "(jq not found)"
  else
    js="$(cd "$JR_PRIMARY" 2>/dev/null && bash "$JR_CS" status --json 2>/dev/null)"
    rows="$(printf '%s' "$js" | "$JQ" -r '(.holders[]? | ["holder", .slot, .pid, .checkout, .name, .started]), (.waiters[]? | ["waiter", .ticket, .pid, .checkout, .name, .started]) | map(tostring | gsub("[\t\n\u001f]"; " ")) | join("\u001f")' 2>/dev/null)"
    if [ -z "$js" ] || ! printf '%s' "$js" | "$JQ" -e '.holders' >/dev/null 2>&1; then
      _jr_unknown "$g" "ci-slot.sh status --json" "printed no status document"
    else
      while IFS="$US" read -r w k pid co name st; do
        [ -n "$w" ] || continue
        age=""; _jr_is_uint "$st" && [ "$st" -gt 0 ] && age=$((now - st))
        _jr_row slot "$g" "slot|$w|$k|$pid|$st" "CI slot $w $k — $name" "$co" "$age" "$( [ "$w" = holder ] && echo "holding slot $k" || echo "queued (ticket $k)")" \
          "pid $pid; checkout $co" none "report only — it frees itself when the suite ends; \`ci-slot.sh release --pid $pid\` frees it by hand"
      done <<<"$rows"
      _jr_note "$g" "ci-slot.sh status: $(printf '%s' "$js" | "$JQ" -r '"\(.holders | length) holder(s), \(.waiters | length) waiter(s), \(.slots) slot(s)"' 2>/dev/null)"
    fi
  fi
  if [ -n "$JR_SNAP_WHY" ]; then
    _jr_row caf "$g" "caf|$JR_SNAP_WHY" "keep-awake scan" "-" "" "unknown — process snapshot $JR_SNAP_WHY" "$JR_SNAP_WHY" none \
      "report only — keep-awakes are not judged without the snapshot"
    return 0
  fi
  while IFS="$T" read -r pid p ls et cmd; do
    [ -n "$pid" ] || continue
    case "$cmd" in caffeinate*|*/caffeinate*) ;; *) continue ;; esac
    w="$(printf '%s\n' "$cmd" | awk '{ for (i = 1; i < NF; i++) if ($i == "-w") { print $(i + 1); exit } }')"
    _jr_is_uint "$w" || continue
    age="$(_jr_etime_s "$et")"
    _jr_row caf "$g" "caf|$pid|$ls" "keep-awake caffeinate pid $pid" "keep-awake for pid $w" "$age" \
      "keeping the machine awake while pid $w $( [ -n "$(_jr_snap_get "$w" 1)" ] && echo runs || echo "runs (pid $w is not in the snapshot)")" "$cmd" none \
      "report only — it exits by itself when pid $w exits; \`kill $pid\` ends it early"
  done <<<"$JR_SNAP"
  return 0
}

# ---- group: not-the-plugins ---------------------------------------------------------------------------
_jr_c_external() {
  local g=not-the-plugins min ex="" live=" " p k pid pp ls et cmd b age anc why
  if [ -n "$JR_SNAP_WHY" ]; then
    _jr_row ext "$g" "ext|$JR_SNAP_WHY" "process scan" "-" "" "unknown — process snapshot $JR_SNAP_WHY" "$JR_SNAP_WHY" none \
      "report only — nothing is listed here without the snapshot"
    return 0
  fi
  min="${LOOMWRIGHT_PROC_UNREG_MIN_S:-}"; _jr_is_uint "$min" || min=3600
  _jr_prlist
  # pids the plugin owns: every registry row's live pid and every listed look-alike
  ex=" $(printf '%s\n' "$JR_PRLIST" | awk -F'\t' '!/^#/ && $3 ~ /^[0-9]+$/ && $5 != "finished" { printf "%s ", $3 }')"
  live=" $(printf '%s\n' "$JR_PRLIST" | awk -F'\t' '!/^#/ && $3 ~ /^[0-9]+$/ && $5 != "finished" && $2 != "unregistered" { printf "%s ", $3 }')"
  # this call's own family: itself and its ancestors
  ex="$ex$$ "; p="${PPID:-}"; k=0
  while _jr_is_uint "$p" && [ "$p" -gt 1 ] && [ "$k" -lt 64 ]; do ex="$ex$p "; p="$(_jr_snap_get "$p" 2)"; k=$((k + 1)); done
  while IFS="$T" read -r pid pp ls et cmd; do
    [ -n "$pid" ] || continue
    case "$ex" in *" $pid "*) continue ;; esac
    [ "$pp" = "$$" ] && continue
    b="${cmd%% *}"; b="${b##*/}"
    why=""
    ! _jr_is_host_cmd "$cmd" || why=host
    [ -n "$why" ] || case "$b" in [Pp]ython*) why=python ;; esac
    [ -n "$why" ] || continue
    age="$(_jr_etime_s "$et")"; _jr_is_uint "$age" || continue
    [ "$age" -gt "$min" ] || continue
    # a descendant of a live entry is the plugin's
    anc="$pp"; k=0
    while _jr_is_uint "$anc" && [ "$anc" -gt 1 ] && [ "$k" -lt 64 ]; do
      case "$live" in *" $anc "*) anc=LIVE; break ;; esac
      anc="$(_jr_snap_get "$anc" 2)"; k=$((k + 1))
    done
    [ "$anc" = LIVE ] && continue
    if [ "$why" = host ]; then
      _jr_row ext "$g" "ext|$pid|$ls" "host session pid $pid" "not the plugin's — the host's own session" "$age" "running" "$cmd" none \
        "report only — the plugin did not start it; close it from the host (end that session, or quit the app)"
    else
      _jr_row ext "$g" "ext|$pid|$ls" "python process pid $pid" "not the plugin's" "$age" "running" "$cmd" none \
        "report only — the plugin did not start it; stop it from the session or tool that started it (check its command line before any \`kill $pid\`)"
    fi
  done <<<"$JR_SNAP"
  return 0
}

# ---- report rendering ---------------------------------------------------------------------------------
JR_GROUPS="processes locks lanes worktrees stale-state plugin-adjacent not-the-plugins"
_jr_title() {
  case "$1" in
    processes) echo "Processes" ;; locks) echo "Run locks" ;; lanes) echo "Lanes" ;;
    worktrees) echo "Worktrees and branches" ;; stale-state) echo "Stale run state" ;;
    plugin-adjacent) echo "Plugin-adjacent (report only)" ;; not-the-plugins) echo "Not the plugin's (report only)" ;;
  esac
}
_jr_collect() {   # _jr_collect <group>...
  local gr
  for gr in "$@"; do
    case "$gr" in
      processes) _jr_c_processes ;; locks) _jr_c_locks ;; lanes) _jr_c_lanes ;; worktrees) _jr_c_worktrees ;;
      stale-state) _jr_c_state ;; plugin-adjacent) _jr_c_adjacent ;; not-the-plugins) _jr_c_external ;;
    esac
  done
}
_jr_summary() {
  printf '%s' "$JR_ROWS" | awk -F'\t' '
    NF { r++; if ($8 != "none") { a++; c[$8]++ } }
    END { s = ""; for (k in c) s = s (s == "" ? "" : ", ") k "=" c[k]
          printf "janitor: summary — %d row(s), %d actionable%s\n", r, a, (s == "" ? "" : " (" s ")") }'
}
_jr_text() {
  local gr
  printf 'janitor: report — primary %s — %s — read-only, nothing changed\n' "$JR_PRIMARY" "$(_jr_iso)"
  for gr in $JR_GROUPS; do
    printf '## %s\n' "$(_jr_title "$gr")"
    printf '%s' "$JR_ROWS" | awk -F'\t' -v g="$gr" '
      function hum(a) { if (a == "" || a == "-") return "-"
        if (a >= 86400) return sprintf("%dd%02dh", a / 86400, (a % 86400) / 3600)
        if (a >= 3600) return sprintf("%dh%02dm", a / 3600, (a % 3600) / 60)
        if (a >= 60) return sprintf("%dm%02ds", a / 60, a % 60)
        return a "s" }
      $2 == g { n++
        printf "- %s | %s\n    owner: %s · age: %s · state: %s\n    evidence: %s\n    action: %s — %s\n", $1, $3, $4, hum($5), $6, $7, $8, $9
        if ($10 != "") printf "    alt: %s — only after a second JAN-ACT confirmation (act --confirm --force-unlock %s)\n", $10, $1 }
      END { if (!n) print "  (no rows)" }'
    printf '%s' "$JR_NOTES" | awk -F'\t' -v g="$gr" '$1 == g { printf "  note: %s\n", $2 }'
  done
  _jr_summary
}
_jr_json() {
  local rows notes
  if ! _jr_has_jq; then
    printf '{"schema_version":1,"error":"jq not found — janitor-report.sh --json needs jq"}\n'; return 0
  fi
  rows="$(printf '%s' "$JR_ROWS" | "$JQ" -Rn '[inputs | select(length > 0) | split("\t")
    | {id: .[0], group: .[1], what: .[2], owner: .[3], age_s: (if (.[4] // "") == "" then null else (.[4] | tonumber) end),
       state: .[5], evidence: .[6], action: .[7], reason: .[8], alt_action: (if (.[9] // "") == "" then null else .[9] end)}]')"
  notes="$(printf '%s' "$JR_NOTES" | "$JQ" -Rn '[inputs | select(length > 0) | split("\t") | {group: .[0], note: .[1]}]')"
  "$JQ" -n --argjson rows "$rows" --argjson notes "$notes" --arg primary "$JR_PRIMARY" --arg at "$(_jr_iso)" --arg order "$JR_GROUPS" '
    def title: {"processes": "Processes", "locks": "Run locks", "lanes": "Lanes", "worktrees": "Worktrees and branches",
                "stale-state": "Stale run state", "plugin-adjacent": "Plugin-adjacent (report only)",
                "not-the-plugins": "Not the plugin'"'"'s (report only)"}[.];
    {schema_version: 1, primary: $primary, generated_at: $at,
     groups: [($order | split(" "))[] as $g | {group: $g, title: ($g | title),
               rows: [$rows[] | select(.group == $g)], notes: [$notes[] | select(.group == $g) | .note]}],
     summary: {rows: ($rows | length), actionable: ([$rows[] | select(.action != "none")] | length),
               by_action: ([$rows[] | select(.action != "none") | .action] | group_by(.) | map({(.[0]): length}) | add // {})}}'
}

# ---- act ----------------------------------------------------------------------------------------------
_jr_group_of_id() {
  case "$1" in
    reg-*|fin-*|unreg-*|scan-*) echo processes ;; lock-*) echo locks ;; lane-*|leaks-*) echo lanes ;;
    wt-*|br-*|brkept-*) echo worktrees ;; cfgbak-*|mw-*|mpf-*|ret-*) echo stale-state ;;
    slot-*|caf-*) echo plugin-adjacent ;; ext-*) echo not-the-plugins ;; unk-*) echo unknown ;; *) echo "" ;;
  esac
}
_jr_find() { printf '%s' "$JR_ROWS" | awk -F'\t' -v i="$1" '$1 == i { print; exit }'; }

_jr_act_lock() {   # _jr_act_lock <id> <checkout> <recorded pid> <mode reclaim|force>
  local c="$2" pid="$3" lv st age out rc after
  lv="$(bash "$JR_RL" liveness --pid "$pid" --root "$c" 2>/dev/null | head -1)"
  st="$(bash "$JR_RL" status --root "$c" 2>/dev/null | head -1)"
  age="${st##* age=}"
  case "$st" in "LOCKED owner="*" pid=$pid age="*) ;; *) echo "janitor: refused $1 — the lock changed since the report ($st)"; return 0 ;; esac
  [ "$lv" = dead ] || { echo "janitor: refused $1 — its holder is no longer dead (liveness: ${lv:-unreadable})"; return 0; }
  if [ "$4" = reclaim ]; then
    _jr_is_uint "$age" && [ "$age" -ge "$JR_TTL" ] || { echo "janitor: refused $1 — the lock is younger than ${JR_TTL}s (age $age)"; return 0; }
    out="$(env -u LOOMWRIGHT_RUN_LOCK_SESSION_ID bash "$JR_RL" acquire --owner human:janitor --root "$c" 2>&1)"; rc=$?
    if [ "$rc" -ne 0 ]; then echo "janitor: act $1 — lock-reclaim: acquire refused ($(_jr_clean "$out")); nothing else tried"; return 0; fi
    bash "$JR_RL" release --owner human:janitor --root "$c" >/dev/null 2>&1
    after="$(bash "$JR_RL" status --root "$c" 2>/dev/null | head -1)"
    echo "janitor: act $1 — lock-reclaim: reclaimed and released the lock of $c (was: $st); status now: $after"
  else
    out="$(bash "$JR_RL" release --force-unlock --owner human:janitor --root "$c" 2>&1)"
    after="$(bash "$JR_RL" status --root "$c" 2>/dev/null | head -1)"
    echo "janitor: act $1 — force-unlock: $(_jr_clean "$out"); status now: $after"
  fi
  return 0
}

jr_act() {
  local confirm=0 report=0 force=0 root="" ids="" a why="" groups="" gr id row action alt data swept=0
  while [ "$#" -gt 0 ]; do
    a="$1"; shift
    case "$a" in
      --confirm) confirm=1 ;; --report) report=1 ;; --force-unlock) force=1 ;;
      --root) [ "$#" -ge 1 ] && [ -n "$1" ] || { echo "$JR_ME: act — --root needs a value" >&2; return 2; }; root="$1"; shift ;;
      -h|--help) jr_usage; return 0 ;;
      -*) echo "$JR_ME: act — unknown option $a" >&2; jr_usage >&2; return 2 ;;
      *) case "$a" in *[!A-Za-z0-9-]*) echo "$JR_ME: act — malformed row id $a" >&2; return 2 ;; esac
         ids="$ids $a" ;;
    esac
  done
  [ -n "$ids" ] || { echo "$JR_ME: act — no row id given" >&2; jr_usage >&2; return 2; }
  _jr_primary "${root:-$PWD}" || { echo "janitor: refused — not a git checkout (${root:-$PWD}); nothing acted on"; return 0; }
  # THE NON-INTERACTIVE GUARD: nothing below runs without --confirm, under --report, or with CI set
  if [ "$report" = 1 ]; then why="--report"; elif [ -n "${CI:-}" ]; then why="CI is set"; elif [ "$confirm" != 1 ]; then why="no --confirm (only the owner's JAN-ACT answer confirms)"; fi
  [ -z "$why" ] || { printf 'janitor: report only — %s; nothing acted on\n' "$why"; return 0; }
  for id in $ids; do
    gr="$(_jr_group_of_id "$id")"
    case "$gr" in ''|unknown) continue ;; esac
    case " $groups " in *" $gr "*) ;; *) groups="$groups $gr" ;; esac
  done
  _jr_snapshot
  # re-run each picked row's reader immediately before acting
  _jr_collect $groups
  for id in $ids; do
    gr="$(_jr_group_of_id "$id")"
    [ -n "$gr" ] && [ "$gr" != unknown ] || { echo "janitor: refused $id — unknown row id"; continue; }
    row="$(_jr_find "$id")"
    [ -n "$row" ] || { echo "janitor: refused $id — not in the fresh report (its state changed or it is gone; re-run /janitor)"; continue; }
    action="$(printf '%s' "$row" | cut -f8)"; alt="$(printf '%s' "$row" | cut -f10)"; data="$(printf '%s' "$row" | cut -f11)"
    if [ "$force" = 1 ]; then
      [ "$alt" = force-unlock ] || { echo "janitor: refused $id — --force-unlock applies only to a dead-holder lock younger than ${JR_TTL}s"; continue; }
      _jr_act_lock "$id" "${data%%"$US"*}" "${data#*"$US"}" force; continue
    fi
    case "$action" in
      reap) echo "janitor: act $id — reap: $(_jr_clean "$(_jr_pr reap --apply $data 2>&1)")" ;;
      stop-unregistered)
        local p s h
        p="${data%%"$US"*}"; s="${data#*"$US"}"; s="${s%%"$US"*}"; h="${data##*"$US"}"
        if [ "$JR_SNAP_OWN" = 1 ]; then
          echo "janitor: act $id — stop-unregistered: $(_jr_clean "$(bash "$JR_PR" stop-unregistered --pid "$p" --start "$s" --hash "$h" --apply 2>&1)")"
        else
          echo "janitor: act $id — stop-unregistered: $(_jr_clean "$(_jr_pr stop-unregistered --pid "$p" --start "$s" --hash "$h" --apply 2>&1)")"
        fi ;;
      sweep-apply)
        if [ "$swept" = 1 ]; then echo "janitor: act $id — sweep-apply: already applied in this call"; continue; fi
        swept=1
        echo "janitor: act $id — sweep-apply (the whole sweep): $(_jr_clean "$(bash "$JR_AH" sweep --apply --root "$data" 2>&1)")" ;;
      lane-remove) echo "janitor: act $id — lane-remove: $(_jr_clean "$(bash "$JR_AH" lane-remove "$data" 2>&1)")" ;;
      lock-reclaim) _jr_act_lock "$id" "${data%%"$US"*}" "${data#*"$US"}" reclaim ;;
      config-restore)
        if bash "$JR_AH" config-restore "${data%%"$US"*}" "${data#*"$US"}" >/dev/null 2>&1; then
          echo "janitor: act $id — config-restore: restored ${data%%"$US"*} from ${data#*"$US"} (backup removed)"
        else echo "janitor: act $id — config-restore: failed (nothing else tried)"; fi ;;
      *) echo "janitor: refused $id — a report-only row (action none): $(printf '%s' "$row" | cut -f9)" ;;
    esac
  done
  # a fresh one-line summary
  JR_ROWS=""; JR_NOTES=""; JR_PRLIST=""; JR_PRLIST_DONE=0
  _jr_cleanup; JR_SNAP_FILE=""; JR_SNAP_OWN=0
  _jr_snapshot
  _jr_collect $JR_GROUPS
  _jr_summary
  return 0
}

jr_report() {
  local json=0 root="" a
  while [ "$#" -gt 0 ]; do
    a="$1"; shift
    case "$a" in
      --json) json=1 ;;
      --root) [ "$#" -ge 1 ] && [ -n "$1" ] || { echo "$JR_ME: --root needs a value" >&2; return 2; }; root="$1"; shift ;;
      -h|--help) jr_usage; return 0 ;;
      *) echo "$JR_ME: unknown argument $a" >&2; jr_usage >&2; return 2 ;;
    esac
  done
  if ! _jr_primary "${root:-$PWD}"; then
    JR_PRIMARY="${root:-$PWD}"
    _jr_unknown processes git "rev-parse: not a git checkout (${root:-$PWD})"
  else
    _jr_snapshot
    _jr_collect $JR_GROUPS
  fi
  if [ "$json" = 1 ]; then _jr_json; else _jr_text; fi
  return 0
}

case "${1:-}" in
  act) shift; jr_act "$@"; exit $? ;;
  *) jr_report "$@"; exit $? ;;
esac
