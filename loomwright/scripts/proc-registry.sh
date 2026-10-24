#!/usr/bin/env bash
# proc-registry.sh — the one registry of every detached process the plugin starts, so a stray or
# orphaned one can be listed and stopped safely. This header IS the contract (no other doc restates
# it); launchers code against it, never against the functions below.
#
# SUBCOMMANDS
#   register --pid <p> --kind <k> --purpose <text>
#            [--repo <root>] [--run-id <id>] [--runfile <path>] [--lane <dir>]
#            [--owner-pid <pid>] [--max-lifetime <s>] [--grace <s>] [--stop-hint <text>]
#            [--expect <substring>] [--session-id <id>]
#       Record one live process. Fail-SAFE: ALWAYS exits 0. A failure writes nothing and prints
#       exactly one `proc-registry: register failed — <reason>` line on stderr (bad or missing
#       argument, unknown kind, jq missing, registry dir unavailable or unwritable, dead pid). A
#       launcher calls it fully redirected and never lets it change the launch.
#       --expect: wait, bounded at about 2.5 s, until the command line BOTH contains <substring> AND
#       has exec'd past its launcher — its first word is not `nohup` or `env` (bare or a path such
#       as /usr/bin/env, the `#!/usr/bin/env bash` stage), and it is not the --owner-pid's own
#       command line (a forked child that has not exec'd yet still shows its parent's) — before
#       hashing. Those stages' lines already carry the final arguments, so the substring alone would
#       match (and hash) a line the process is about to replace; this exec wait lives HERE and nowhere
#       else — a launcher never hand-rolls its own. If the condition never holds the entry is still
#       written and one `proc-registry: register — command line never matched --expect` line is
#       printed on stderr.
#       Relative --repo / --runfile / --lane paths are made absolute against the caller's cwd.
#
# WRAPPER KINDS (lane, phase, drain): the launcher's pid is a wrapper, not the session it runs, so one
# launch writes TWO entries of the same kind (the same cap applies to both; `list` shows two rows, and
# each purpose says which is the wrapper and which the session):
#   the wrapper  registered by its launcher (no --owner-pid). It runs the session in the BACKGROUND,
#                traps TERM/INT/HUP to pass a TERM on to it, and waits while the session is alive
#                before its own teardown (so its EXIT cleanup never runs under a live session);
#   the session  registered by the wrapper right after the background launch — fail-safe, fully
#                redirected and itself in the background, so it never delays the wrapper's wait — with
#                --owner-pid = the wrapper and --expect, so the hash is the exec'd command line. It
#                reads finished once the session exits, and orphaned once the wrapper is gone.
#   reap never derives one pid from another (no ppid / child walk): a KILL, which a wrapper cannot pass
#   on, reaches the session only through the session's OWN entry. `reap --apply` processes entries
#   that carry an owner_pid after the rest, so a session whose wrapper the same pass stopped already
#   reads orphaned and takes the ordinary TERM / KILL path.
#   A wrapper's own teardown (the drain's salvage, worktree removal, lock release and death marker;
#   a lane / phase wrapper's death marker) runs only AFTER its session exits, so the wrapper entry
#   defaults to the longer WRAPPER grace (see GRACE): a KILL inside that teardown would leave no
#   death marker (and a drain's lock and worktree behind), so a dead session would read as completed.
#   Honest limits: a session that ignores TERM keeps its wrapper waiting, so the wrapper is KILLed
#   after grace_s and its teardown never runs; a teardown slower than the WRAPPER grace (the
#   drain's salvage has no time bound of its own) is KILLed the same way; a session whose own
#   registration failed is reachable only through its wrapper's TERM.
#   list
#       One row per entry (TSV after a `# id kind pid age class evidence` header): id, kind, pid,
#       age (the live process's elapsed time, `-` when it is gone), class, and the evidence for that
#       class. Read-only: creates nothing, changes nothing. ALWAYS exits 0; an empty, missing or
#       unavailable registry prints `(no entries)`.
#   summary [--scan]
#       Exactly ONE line on stdout. Read-only: never signals, creates nothing, changes nothing. Exits
#       0; any other argument is a usage error (exit 2). The line is
#         proc-registry: summary — <E> entries: <r> running, <o> overdue, <a> orphaned, <f> finished
#       E counts every entry file, and each is classified by the SAME code `list` uses (CLASSES), fed
#       from ONE process snapshot per call, however many entries exist:
#         env TZ=UTC0 LC_ALL=C ps -A -ww -o pid=,ppid=,lstart=,etime=,command=
#       (the lstart column under the same TZ/locale pin as pid_start; `-A` is the POSIX spelling both
#       BSD and procps accept, equal to BSD `-ax`). No snapshot is taken when there
#       is nothing to classify or scan. An empty or missing registry prints the line with every count
#       0. The line is instead
#         proc-registry: summary — unavailable
#       when the registry is unavailable (REGISTRY LOCATION), its path is unreadable or not a
#       directory, jq is missing, or the snapshot fails or comes back empty — never a guess.
#       --scan  also counts UNREGISTERED processes that look like the plugin's and appends
#               `; <u> unregistered` (u is 0 when the scan is skipped). A process in the same snapshot
#               counts when ALL of these hold:
#                 - its command line contains `/loomwright/scripts/` (a checkout) or
#                   `/loomwright/<one segment>/scripts/` (an installed, versioned plugin root), OR it
#                   is a `python*` command whose script path lies in a temp dir (/tmp, /var/tmp,
#                   /var/folders, their /private forms, or $TMPDIR) and no longer exists;
#                 - it is older than LOOMWRIGHT_PROC_UNREG_MIN_S seconds (a whole number, else the
#                   default 3600);
#                 - it is not the live process of an entry (an entry whose class is not finished: a
#                   recycled pid's new process IS unregistered);
#                 - it is not this call's own process, a direct child of it, or an ancestor ($PPID,
#                   then the snapshot's ppid chain).
#               HERMETIC SCAN SKIP: under HERMETIC_TEST_ENV=1 with LOOMWRIGHT_PROC_PS_SNAPSHOT unset
#               the scan is skipped, so no suite reads the live machine through it (the HERMETIC
#               REDIRECT's counterpart; classification of the hermetic registry still runs).
#               Honest limits: the python rule reads the first non-option argument as the script, so a
#               relative path or one containing a space is not checked; a process that rewrites its
#               argv is invisible to the scan.
#       Test seam: LOOMWRIGHT_PROC_PS_SNAPSHOT=<file> is read IN PLACE of running ps (same columns).
#   reap [--apply] [<id>...]
#       Without --apply (the DEFAULT): a dry run — prints the action it would take per entry, sends
#       no signal, writes nothing. With --apply, per entry (all entries, or only the named ids):
#         overdue / orphaned  re-read the live lstart + command-line hash IMMEDIATELY before the
#                             signal; TERM; wait up to the entry's grace_s while it still matches;
#                             re-check again and send KILL only if it STILL matches; remove the
#                             entry (kept only when the process survives a KILL, or a signal fails).
#         finished            pruned: the file is removed, no signal.
#         running             never touched.
#       Every processed (non-running) entry appends one line to <registry dir>/reap.log; each append
#       keeps that log to its last 1000 lines (nothing else rotates it). An id that is not in the
#       registry is reported and skipped. Entries with an owner_pid are processed last (WRAPPER
#       KINDS). Exits 0; a usage error (unknown option, malformed id)
#       exits 2.
#   A missing or unknown subcommand is a usage error: exit 2. `help` / `-h` / `--help` exit 0.
#
# NEVER SIGNAL BY PID ALONE. Every TERM and every KILL is preceded, in the same pass, by a check that
# the pid's live `lstart` AND the hash of its live command line still equal the entry's; reap takes
# ids, never pids, so a pid that is not in the registry is never touched. A recycled pid (alive, but
# a different start time or command line) is `finished`, and finished entries are only pruned.
# Honest limit: a tiny window remains between the last check and the kill(2) call itself.
#
# ENTRY: <registry dir>/<id>.json, built with `jq --arg` (never shell-templated). Keys:
#   pid             the registered process
#   pid_start       `env TZ=UTC0 LC_ALL=C ps -o lstart= -p <pid>`, whitespace-trimmed
#   cmd_hash        `<algo>:<hash>` of the full `ps -ww -o command=` line (shasum → sha1sum → cksum)
#   kind            phase | lane | drain | postmortem | merge-watch
#   purpose         free text
#   repo, run_id, runfile, lane, owner_pid, owner_start (owner's lstart, read at register time),
#   stop_hint, session_id (--session-id, else the harness session-id env var)
#                   null when absent
#   max_lifetime_s  the lifetime cap in seconds (see CAPS)
#   grace_s         seconds reap waits between TERM and KILL (--grace, else the GRACE table)
#   registered_at   UTC ISO-8601
#   The id is `<pid>-<hash of pid + pid_start>`: registering the same live process twice rewrites ONE
#   entry; a different process that later reuses the pid (a different start time) gets a NEW entry
#   and never overwrites the old one. No value may contain a newline.
#
# CLASSES (evaluated in this precedence; the row prints the first that holds):
#   finished  the pid is gone, OR its lstart differs, OR its live command-line hash differs. A
#             recycled pid is never trusted. (A hash made by a different algorithm differs too: it
#             reads finished and is never signalled.)
#   overdue   running and older than max_lifetime_s (age = the live process's `ps -o etime=`).
#   orphaned  running while its owner is gone: the repo dir is missing, OR the runfile's
#             `## Status:` is `done`, OR the lane dir is missing, OR owner_pid is dead or recycled
#             (its lstart differs from owner_start). A missing runfile alone is NOT an orphan.
#   running   otherwise.
#   An entry both overdue and orphaned prints `overdue` (its evidence names both).
#
# CAPS (max_lifetime_s by --kind; this table lives here and nowhere else — launchers pass --kind,
# never a number):
#   phase        21600   (6h)   override LOOMWRIGHT_PROC_MAX_S_PHASE
#   lane         86400   (24h)  override LOOMWRIGHT_PROC_MAX_S_LANE
#   drain        14400   (4h)   override LOOMWRIGHT_PROC_MAX_S_DRAIN
#   postmortem   3600    (1h)   override LOOMWRIGHT_PROC_MAX_S_POSTMORTEM
#   merge-watch  no default: --max-lifetime is REQUIRED (the watcher owns its cap and passes its own
#                resolved value); without it register takes the fail-safe path.
#   Precedence: --max-lifetime, then the env override (a positive integer; anything else is
#   ignored), then the table.
#
# GRACE (grace_s when --grace is not passed; like CAPS, this table lives here and nowhere else —
# launchers never pass --grace):
#   WRAPPER      120   a phase / lane / drain entry registered WITHOUT --owner-pid (the wrapper of a
#                      WRAPPER KIND): covers its session's TERM exit plus its own teardown (bounded
#                      parts: the webhook's 5 s curl cap, the desktop notifier's 3 s cap; the salvage
#                      and `git worktree remove` are not time-bounded — see WRAPPER KINDS' limits)
#   every other   10   sessions (--owner-pid set), postmortem, merge-watch (its EXIT trap only
#                      removes its marker)
#   reap waits only until the process stops matching, so the grace is a ceiling, not a delay: a
#   wrapper that tears down in 2 s costs reap 2 s. reap is sequential, so each wrapper whose session
#   ignores TERM (or whose teardown hangs) costs up to the WRAPPER grace before its KILL.
#
# REGISTRY LOCATION (resolved per call, in this order):
#   1. $LOOMWRIGHT_PROC_REGISTRY_DIR when non-empty (the test seam);
#   2. HERMETIC REDIRECT — when HERMETIC_TEST_ENV=1 (hermetic-test-env.sh): $HERMETIC_SHIM_DIR/procs.
#      If HERMETIC_SHIM_DIR is empty or not a directory the registry is UNAVAILABLE: register fails
#      safe (`register failed — hermetic registry dir unavailable`), list / reap see no entries,
#      summary prints `unavailable`. It
#      never falls back to $HOME and never to `/procs`;
#   3. ${HOME}/.claude/loomwright/procs (user scope, whatever the host mode). An empty HOME is
#      unavailable, the same way.
#   Known limit: a test that neither sources hermetic-test-env.sh nor sets the override, run
#   standalone, still registers into the real home registry.
#
# EXIT CODES: register 0 always; list 0 always; summary 0 (usage error 2); reap 0 (usage error 2);
# missing/unknown subcommand 2.
# bash 3.2 / BSD userland and Linux procps; needs jq and ps.

set -uo pipefail

PR_ME="proc-registry"
PR_T="$(printf '\t')"

pr_usage() {
  cat <<'USAGE'
usage: proc-registry.sh register --pid <p> --kind <phase|lane|drain|postmortem|merge-watch> --purpose <text> [options]
       proc-registry.sh list
       proc-registry.sh summary [--scan]
       proc-registry.sh reap [--apply] [<id>...]
See the header comment of proc-registry.sh for the full contract.
USAGE
}

# ---- primitives -------------------------------------------------------------------------------------

_pr_trim() { sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

_pr_is_uint() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac; return 0; }
_pr_is_pos_int() { _pr_is_uint "${1:-}" && [ "$1" -gt 0 ] 2>/dev/null; }

# summary's ONE process snapshot: PR_SNAP holds a TSV row per process (pid, ppid, lstart, etime,
# command); while PR_SNAP_ON=1 the three lookups below read it instead of running ps, so `summary`
# classifies with the very code `list` runs. Only cmd_summary sets it; register / reap never do.
PR_SNAP_ON=0
PR_SNAP=""

# _pr_snap_get <pid> <col> — one field of <pid>'s snapshot row (2 ppid, 3 lstart, 4 etime, 5 the
# command, everything after the fourth tab); empty when the pid is not in the snapshot. Never runs ps.
_pr_snap_get() {
  printf '%s\n' "$PR_SNAP" | awk -F'\t' -v p="$1" -v c="$2" '
    $1 == p {
      if (c < 5) { print $c } else { s = $0; for (k = 1; k < 5; k++) s = substr(s, index(s, "\t") + 1); print s }
      exit
    }'
}

# _pr_lstart <pid> — the process start time, TZ- and locale-pinned; empty when the pid is gone.
_pr_lstart() {
  _pr_is_uint "${1:-}" || return 0
  [ "$PR_SNAP_ON" != 1 ] || { _pr_snap_get "$1" 3; return 0; }   # summary: the snapshot's lstart
  env TZ=UTC0 LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | _pr_trim
}

# _pr_cmdline <pid> — the full live command line; empty when the pid is gone.
_pr_cmdline() {
  _pr_is_uint "${1:-}" || return 0
  [ "$PR_SNAP_ON" != 1 ] || { _pr_snap_get "$1" 5; return 0; }   # summary: the snapshot's command line
  env LC_ALL=C ps -ww -o command= -p "$1" 2>/dev/null | _pr_trim
}

# _pr_hash <string> — `<algo>:<hash>` (shasum → sha1sum → cksum); empty when no tool works.
_pr_hash() {
  local h=""
  if command -v shasum >/dev/null 2>&1; then
    h="$(printf '%s' "$1" | shasum 2>/dev/null | cut -d' ' -f1)"
    [ -n "$h" ] && { printf 'sha1:%s' "$h"; return 0; }
  fi
  if command -v sha1sum >/dev/null 2>&1; then
    h="$(printf '%s' "$1" | sha1sum 2>/dev/null | cut -d' ' -f1)"
    [ -n "$h" ] && { printf 'sha1:%s' "$h"; return 0; }
  fi
  if command -v cksum >/dev/null 2>&1; then
    h="$(printf '%s' "$1" | cksum 2>/dev/null | cut -d' ' -f1)"
    [ -n "$h" ] && { printf 'cksum:%s' "$h"; return 0; }
  fi
  return 0
}

# _pr_etime_s <pid> — the live process's elapsed seconds (from `ps -o etime=`, [[dd-]hh:]mm:ss).
_pr_etime_s() {
  local e
  if [ "$PR_SNAP_ON" = 1 ]; then
    e="$(_pr_snap_get "$1" 4)"   # summary: the snapshot's etime
  else
    e="$(env LC_ALL=C ps -o etime= -p "$1" 2>/dev/null)"
  fi
  _pr_etime_to_s "$e"
}

# _pr_etime_to_s <etime> — seconds from an etime value ([[dd-]hh:]mm:ss); empty when malformed.
_pr_etime_to_s() {
  local e
  e="$(printf '%s' "${1:-}" | tr -d '[:space:]')"
  case "$e" in ''|*[!0-9:-]*) return 0 ;; esac
  awk -v e="$e" 'BEGIN {
    d = 0; i = index(e, "-")
    if (i) { d = substr(e, 1, i - 1) + 0; e = substr(e, i + 1) }
    n = split(e, a, ":"); s = 0
    for (k = 1; k <= n; k++) s = s * 60 + a[k]
    printf "%d", d * 86400 + s
  }'
}

# _pr_abs <path> — absolute form (relative to the caller's cwd); empty stays empty.
_pr_abs() {
  case "${1:-}" in '') return 0 ;; /*) printf '%s' "$1" ;; *) printf '%s/%s' "$PWD" "$1" ;; esac
}

# _pr_resolve_dir — sets PR_DIR, or returns 1 with PR_DIR_WHY (the registry is unavailable).
_pr_resolve_dir() {
  PR_DIR=""; PR_DIR_WHY=""
  if [ -n "${LOOMWRIGHT_PROC_REGISTRY_DIR:-}" ]; then
    PR_DIR="$LOOMWRIGHT_PROC_REGISTRY_DIR"; return 0
  fi
  if [ "${HERMETIC_TEST_ENV:-}" = 1 ]; then   # >>> hermetic redirect
    { [ -n "${HERMETIC_SHIM_DIR:-}" ] && [ -d "${HERMETIC_SHIM_DIR:-}" ]; } || { PR_DIR_WHY="hermetic registry dir unavailable"; return 1; }
    PR_DIR="$HERMETIC_SHIM_DIR/procs"; return 0
  fi   # <<< hermetic redirect
  if [ -z "${HOME:-}" ]; then
    PR_DIR_WHY="HOME is empty"; return 1
  fi
  PR_DIR="$HOME/.claude/loomwright/procs"
  return 0
}

# _pr_default_cap <kind> — the CAPS table (the header mirrors it; test-proc-registry.sh pins both).
_pr_default_cap() {
  case "$1" in
    phase)      printf '21600' ;;
    lane)       printf '86400' ;;
    drain)      printf '14400' ;;
    postmortem) printf '3600' ;;
    *) return 1 ;;
  esac
}

# _pr_default_grace <kind> <owner_pid> — the GRACE table (the header mirrors it; test-proc-registry.sh
# pins both): a wrapper-kind entry without an owner is a wrapper, everything else the short default.
_pr_default_grace() {
  case "$1:${2:-}" in
    phase:|lane:|drain:) printf '120' ;;
    *) printf '10' ;;
  esac
}

# _pr_matches <pid> <pid_start> <cmd_hash> — 0 only when the live process is STILL the registered
# one; otherwise 1 with PR_WHY naming the first difference.
_pr_matches() {
  local cur
  PR_WHY=""
  cur="$(_pr_lstart "$1")"
  [ -n "$cur" ] || { PR_WHY="pid gone"; return 1; }
  [ "$cur" = "$2" ] || { PR_WHY="lstart differs (pid recycled)"; return 1; }
  [ "$(_pr_hash "$(_pr_cmdline "$1")")" = "$3" ] || { PR_WHY="command line differs (pid recycled)"; return 1; }
  return 0
}

_pr_now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# _pr_pre_exec <cmdline> — 0 while the line is still a launcher stage (`nohup …` / `env …`, bare or by
# path) that has not exec'd its target yet; the --expect wait below is the ONE place this is checked.
_pr_pre_exec() { case "${1%% *}" in nohup|*/nohup|env|*/env) return 0 ;; esac; return 1; }

# ---- register ---------------------------------------------------------------------------------------

_pr_reg_fail() { printf '%s: register failed — %s\n' "$PR_ME" "$1" >&2; }

cmd_register() {
  local pid="" kind="" purpose="" repo="" run_id="" runfile="" lane="" owner_pid="" max="" grace=""
  local hint="" expect="" sid="${CLAUDE_CODE_SESSION_ID:-}" opt val
  while [ "$#" -gt 0 ]; do
    opt="$1"
    case "$opt" in
      --pid|--kind|--purpose|--repo|--run-id|--runfile|--lane|--owner-pid|--max-lifetime|--grace|--stop-hint|--expect|--session-id)
        [ "$#" -ge 2 ] || { _pr_reg_fail "missing value for $opt"; return 0; }
        val="$2"; shift 2 ;;
      *) _pr_reg_fail "unknown option '$opt'"; return 0 ;;
    esac
    case "$opt" in
      --pid) pid="$val" ;;               --kind) kind="$val" ;;
      --purpose) purpose="$val" ;;       --repo) repo="$val" ;;
      --run-id) run_id="$val" ;;         --runfile) runfile="$val" ;;
      --lane) lane="$val" ;;             --owner-pid) owner_pid="$val" ;;
      --max-lifetime) max="$val" ;;      --grace) grace="$val" ;;
      --stop-hint) hint="$val" ;;        --expect) expect="$val" ;;
      --session-id) sid="$val" ;;
    esac
  done

  case "$pid" in
    '') _pr_reg_fail "missing --pid"; return 0 ;;
    *[!0-9]*|0*) _pr_reg_fail "--pid must be a positive integer without a leading zero"; return 0 ;;
    1) _pr_reg_fail "pid 1 is never registered"; return 0 ;;
  esac
  case "$kind" in
    phase|lane|drain|postmortem|merge-watch) : ;;
    '') _pr_reg_fail "missing --kind"; return 0 ;;
    *) _pr_reg_fail "unknown --kind '$kind'"; return 0 ;;
  esac
  [ -n "$purpose" ] || { _pr_reg_fail "missing --purpose"; return 0; }
  if [ -n "$owner_pid" ]; then
    case "$owner_pid" in *[!0-9]*|0*) _pr_reg_fail "--owner-pid must be a positive integer"; return 0 ;; esac
  fi
  if [ -n "$grace" ]; then
    _pr_is_uint "$grace" || { _pr_reg_fail "--grace must be a whole number of seconds"; return 0; }
  else
    grace="$(_pr_default_grace "$kind" "$owner_pid")"
  fi
  if [ -n "$max" ]; then
    _pr_is_pos_int "$max" || { _pr_reg_fail "--max-lifetime must be a positive whole number of seconds"; return 0; }
  elif max="$(_pr_default_cap "$kind")"; then
    # the per-kind env override (kind is one of the fixed table names here, so the eval is closed)
    local ov="" ov_name
    ov_name="LOOMWRIGHT_PROC_MAX_S_$(printf '%s' "$kind" | tr 'a-z' 'A-Z')"
    eval "ov=\"\${$ov_name:-}\""
    if _pr_is_pos_int "$ov"; then max="$ov"; fi
  else
    _pr_reg_fail "--kind $kind requires --max-lifetime"; return 0
  fi
  case "$purpose$repo$run_id$runfile$lane$hint$expect$sid" in
    *"
"*) _pr_reg_fail "a value contains a newline"; return 0 ;;
  esac
  command -v jq >/dev/null 2>&1 || { _pr_reg_fail "jq not found"; return 0; }
  _pr_resolve_dir || { _pr_reg_fail "$PR_DIR_WHY"; return 0; }

  local st st2 cmd="" matched=0 i=0 end ocmd=""
  st="$(_pr_lstart "$pid")"
  [ -n "$st" ] || { _pr_reg_fail "pid $pid is not running"; return 0; }
  if [ -n "$expect" ]; then
    # a forked child that has not exec'd yet still shows its parent's line (the owner's, for a session)
    [ -z "$owner_pid" ] || ocmd="$(_pr_cmdline "$owner_pid")"
    end=$(( $(date +%s) + 3 ))
    while :; do
      cmd="$(_pr_cmdline "$pid")"
      case "$cmd" in *"$expect"*) _pr_pre_exec "$cmd" || [ "$cmd" = "$ocmd" ] || { matched=1; break; } ;; esac
      [ -n "$(_pr_lstart "$pid")" ] || break
      i=$((i + 1))
      [ "$i" -lt 25 ] || break
      [ "$(date +%s)" -lt "$end" ] || break
      sleep 0.1
    done
  else
    cmd="$(_pr_cmdline "$pid")"
  fi
  st2="$(_pr_lstart "$pid")"
  [ -n "$st2" ] || { _pr_reg_fail "pid $pid exited during registration"; return 0; }
  [ "$st2" = "$st" ] || { _pr_reg_fail "pid $pid changed during registration"; return 0; }
  [ -n "$cmd" ] || { _pr_reg_fail "cannot read the command line of pid $pid"; return 0; }

  local chash idh id owner_start=""
  chash="$(_pr_hash "$cmd")"
  [ -n "$chash" ] || { _pr_reg_fail "no hash tool (shasum, sha1sum, cksum)"; return 0; }
  idh="$(_pr_hash "$pid $st" | sed 's/^[a-z0-9]*://' | tr -cd 'A-Za-z0-9' | cut -c1-16)"
  [ -n "$idh" ] || { _pr_reg_fail "cannot derive an entry id"; return 0; }
  id="$pid-$idh"
  [ -z "$owner_pid" ] || owner_start="$(_pr_lstart "$owner_pid")"

  local json
  json="$(jq -n \
    --arg pid "$pid" --arg pid_start "$st" --arg cmd_hash "$chash" --arg kind "$kind" \
    --arg purpose "$purpose" --arg repo "$(_pr_abs "$repo")" --arg run_id "$run_id" \
    --arg runfile "$(_pr_abs "$runfile")" --arg lane "$(_pr_abs "$lane")" \
    --arg owner_pid "$owner_pid" --arg owner_start "$owner_start" \
    --argjson max_lifetime_s "$max" --argjson grace_s "$grace" \
    --arg registered_at "$(_pr_now_iso)" --arg session_id "$sid" --arg stop_hint "$hint" \
    'def nn: if . == "" then null else . end;
     { pid: ($pid | tonumber), pid_start: $pid_start, cmd_hash: $cmd_hash, kind: $kind,
       purpose: $purpose, repo: ($repo | nn), run_id: ($run_id | nn), runfile: ($runfile | nn),
       lane: ($lane | nn), owner_pid: (if $owner_pid == "" then null else ($owner_pid | tonumber) end),
       owner_start: ($owner_start | nn), max_lifetime_s: $max_lifetime_s, grace_s: $grace_s,
       registered_at: $registered_at, session_id: ($session_id | nn), stop_hint: ($stop_hint | nn) }' \
    2>/dev/null)" || json=""
  [ -n "$json" ] || { _pr_reg_fail "jq could not build the entry"; return 0; }

  local tmp
  ( umask 077; mkdir -p "$PR_DIR" ) 2>/dev/null || { _pr_reg_fail "cannot create $PR_DIR"; return 0; }
  tmp="$(mktemp "$PR_DIR/.register.XXXXXX" 2>/dev/null)" || tmp=""
  [ -n "$tmp" ] || { _pr_reg_fail "cannot write in $PR_DIR"; return 0; }
  if ! printf '%s\n' "$json" > "$tmp" 2>/dev/null || ! mv -f "$tmp" "$PR_DIR/$id.json" 2>/dev/null; then
    rm -f "$tmp" 2>/dev/null
    _pr_reg_fail "cannot write $PR_DIR/$id.json"; return 0
  fi
  if [ -n "$expect" ] && [ "$matched" -ne 1 ]; then
    printf '%s: register — command line never matched --expect\n' "$PR_ME" >&2
  fi
  return 0
}

# ---- classification (list + summary + reap) ---------------------------------------------------------

# _pr_entry_files — every entry file, sorted (none when the registry is missing or unavailable).
_pr_entry_files() {
  [ -d "$PR_DIR" ] || return 0
  local f
  for f in "$PR_DIR"/*.json; do
    [ -f "$f" ] && printf '%s\n' "$f"
  done | env LC_ALL=C sort
}

# _pr_classify <file> — sets E_ID E_KIND E_PID E_START E_HASH E_GRACE E_AGE E_CLASS E_EVID.
_pr_classify() {
  local f="$1" rec="" max="" repo="" runfile="" lane="" opid="" ostart="" cur="" st="" orphan="" why=""
  E_ID="$(basename "$f" .json)"; E_KIND="?"; E_PID="?"; E_START=""; E_HASH=""; E_GRACE=10; E_AGE="-"
  rec="$(jq -r '
      [.pid, .pid_start, .cmd_hash, .kind, .max_lifetime_s, .grace_s, .repo, .runfile, .lane,
       .owner_pid, .owner_start]
      | map(if . == null then "" else tostring end)
      | if any(.[]; test("[\n\r\u001f]")) then error("bad value") else join("\u001f") end' \
      "$f" 2>/dev/null)" || rec=""
  if [ -z "$rec" ]; then
    E_CLASS=finished; E_EVID="unreadable entry"; return 0
  fi
  IFS=$'\037' read -r E_PID E_START E_HASH E_KIND max E_GRACE repo runfile lane opid ostart <<<"$rec"
  _pr_is_uint "$E_GRACE" || E_GRACE=10
  if ! _pr_is_uint "$E_PID" || [ -z "$E_START" ] || [ -z "$E_HASH" ]; then
    E_CLASS=finished; E_EVID="entry lacks pid / pid_start / cmd_hash"; return 0
  fi
  if ! _pr_matches "$E_PID" "$E_START" "$E_HASH"; then
    E_CLASS=finished; E_EVID="$PR_WHY"; return 0
  fi
  E_AGE="$(_pr_etime_s "$E_PID")"
  [ -n "$E_AGE" ] || E_AGE="-"

  if [ -n "$repo" ] && [ ! -d "$repo" ]; then orphan="${orphan:+$orphan; }repo dir missing: $repo"; fi
  if [ -n "$runfile" ] && [ -f "$runfile" ]; then
    st="$(awk '/^## Status:/ { sub(/^## Status:[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); print; exit }' "$runfile" 2>/dev/null)"
    if [ "$st" = done ]; then orphan="${orphan:+$orphan; }run file ## Status: done: $runfile"; fi
  fi
  if [ -n "$lane" ] && [ ! -d "$lane" ]; then orphan="${orphan:+$orphan; }lane dir missing: $lane"; fi
  if [ -n "$opid" ]; then
    cur="$(_pr_lstart "$opid")"
    if [ -z "$cur" ]; then
      orphan="${orphan:+$orphan; }owner pid $opid dead"
    elif [ -n "$ostart" ] && [ "$cur" != "$ostart" ]; then
      orphan="${orphan:+$orphan; }owner pid $opid recycled (lstart differs)"
    fi
  fi

  if _pr_is_uint "$max" && _pr_is_uint "$E_AGE" && [ "$E_AGE" -gt "$max" ]; then
    E_CLASS=overdue; E_EVID="age ${E_AGE}s > cap ${max}s${orphan:+; also orphaned: $orphan}"
  elif [ -n "$orphan" ]; then
    E_CLASS=orphaned; E_EVID="$orphan"
  else
    why="identity matches"
    _pr_is_uint "$max" && why="$why; age ${E_AGE}s <= cap ${max}s"
    E_CLASS=running; E_EVID="$why"
  fi
  return 0
}

_pr_age_col() { case "$1" in -|'') printf '%s' "-" ;; *) printf '%ss' "$1" ;; esac; }

cmd_list() {
  [ "$#" -eq 0 ] || printf '%s: list takes no arguments (ignored: %s)\n' "$PR_ME" "$*" >&2
  local files f n=0
  printf '# id\tkind\tpid\tage\tclass\tevidence\n'
  if _pr_resolve_dir && command -v jq >/dev/null 2>&1; then
    files="$(_pr_entry_files)"
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      _pr_classify "$f"
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$E_ID" "$E_KIND" "$E_PID" "$(_pr_age_col "$E_AGE")" "$E_CLASS" "$E_EVID"
      n=$((n + 1))
    done <<<"$files"
  fi
  [ "$n" -gt 0 ] || printf '(no entries)\n'
  return 0
}

# ---- summary ----------------------------------------------------------------------------------------

_pr_sum_unavail() { printf 'proc-registry: summary — unavailable\n'; }

# _pr_snapshot — take the ONE snapshot (or read LOOMWRIGHT_PROC_PS_SNAPSHOT in its place) into PR_SNAP
# and turn the lookups over to it; 1 when it fails or holds no row. The lstart field keeps its exact
# text (the day of month is space-padded), so it compares byte-for-byte with a stored pid_start.
_pr_snapshot() {
  local raw=""
  if [ -n "${LOOMWRIGHT_PROC_PS_SNAPSHOT:-}" ]; then
    { [ -f "$LOOMWRIGHT_PROC_PS_SNAPSHOT" ] && [ -r "$LOOMWRIGHT_PROC_PS_SNAPSHOT" ]; } || return 1
    raw="$(cat "$LOOMWRIGHT_PROC_PS_SNAPSHOT" 2>/dev/null)" || return 1
  else
    raw="$(env TZ=UTC0 LC_ALL=C ps -A -ww -o pid=,ppid=,lstart=,etime=,command= 2>/dev/null)" || return 1
  fi
  PR_SNAP="$(printf '%s\n' "$raw" | awk '
    function tok() { if (!match(line, /^[^ \t]+/)) return ""; t = substr(line, 1, RLENGTH); line = substr(line, RLENGTH + 1); sub(/^[ \t]+/, "", line); return t }
    {
      line = $0; sub(/^[ \t]+/, "", line)
      pid = tok(); ppid = tok()
      if (pid !~ /^[0-9]+$/ || ppid !~ /^[0-9]+$/) next
      if (!match(line, /^[^ \t]+[ \t]+[^ \t]+[ \t]+[^ \t]+[ \t]+[^ \t]+[ \t]+[^ \t]+/)) next
      ls = substr(line, 1, RLENGTH); line = substr(line, RLENGTH + 1); sub(/^[ \t]+/, "", line)
      et = tok()
      if (et == "") next
      sub(/[ \t]+$/, "", line)
      printf "%s\t%s\t%s\t%s\t%s\n", pid, ppid, ls, et, line
    }')"
  [ -n "$PR_SNAP" ] || return 1
  PR_SNAP_ON=1
  return 0
}

# _pr_in_tmp <path> — 0 when <path> lies in a temp dir.
_pr_in_tmp() {
  local t="${TMPDIR:-}"
  case "$1" in /tmp/*|/var/tmp/*|/var/folders/*|/private/tmp/*|/private/var/tmp/*|/private/var/folders/*) return 0 ;; esac
  t="${t%/}"
  [ -n "$t" ] || return 1
  case "$1" in "$t"/*) return 0 ;; esac
  return 1
}

# _pr_unreg_count <" live entry pids "> — the --scan count over PR_SNAP (header: summary --scan).
_pr_unreg_count() {
  local ex="$1" min p k=0 cands pid et path age u=0
  min="${LOOMWRIGHT_PROC_UNREG_MIN_S:-}"
  _pr_is_uint "$min" || min=3600
  ex="$ex$$ "
  p="${PPID:-}"
  while _pr_is_uint "$p" && [ "$p" -gt 1 ] && [ "$k" -lt 64 ]; do   # the caller's ancestors
    ex="$ex$p "
    p="$(_pr_snap_get "$p" 2)"; k=$((k + 1))
  done
  # one row per look-alike that is not excluded: pid, etime, and the python script path (`-` otherwise)
  cands="$(printf '%s\n' "$PR_SNAP" | awk -F'\t' -v ex="$ex" -v self="$$" '
    index(ex, " " $1 " ") || $2 == self { next }
    { cmd = $0; for (k = 1; k < 5; k++) cmd = substr(cmd, index(cmd, "\t") + 1) }
    cmd ~ /\/loomwright\/([^\/ \t]+\/)?scripts\// { print $1 "\t" $4 "\t-"; next }
    {
      n = split(cmd, w, /[ \t]+/); b = w[1]; sub(/.*\//, "", b)
      if (b !~ /^[Pp]ython/) next
      for (k = 2; k <= n; k++) {
        if (w[k] == "-m" || w[k] == "-c") next
        if (w[k] ~ /^-/) continue
        print $1 "\t" $4 "\t" w[k]
        next
      }
    }')"
  while IFS="$PR_T" read -r pid et path; do
    [ -n "$pid" ] || continue
    age="$(_pr_etime_to_s "$et")"
    _pr_is_uint "$age" || continue
    [ "$age" -gt "$min" ] || continue
    if [ "$path" != "-" ]; then
      { _pr_in_tmp "$path" && [ ! -e "$path" ]; } || continue
    fi
    u=$((u + 1))
  done <<<"$cands"
  printf '%s' "$u"
}

cmd_summary() {
  local scan=0 arg
  while [ "$#" -gt 0 ]; do
    arg="$1"; shift
    case "$arg" in
      --scan) scan=1 ;;
      -h|--help) pr_usage; return 0 ;;
      *) printf '%s: summary — unknown argument %s\n' "$PR_ME" "$arg" >&2; pr_usage >&2; return 2 ;;
    esac
  done
  if ! _pr_resolve_dir || ! command -v jq >/dev/null 2>&1; then _pr_sum_unavail; return 0; fi
  if [ -e "$PR_DIR" ] && { [ ! -d "$PR_DIR" ] || [ ! -r "$PR_DIR" ] || [ ! -x "$PR_DIR" ]; }; then
    _pr_sum_unavail; return 0
  fi
  local files f n=0 nr=0 no=0 na=0 nf=0 live=" " do_scan="$scan" u=0 line
  files="$(_pr_entry_files)"
  if [ "$scan" = 1 ] && [ "${HERMETIC_TEST_ENV:-}" = 1 ] && [ -z "${LOOMWRIGHT_PROC_PS_SNAPSHOT:-}" ]; then   # >>> hermetic scan skip
    do_scan=0
  fi   # <<< hermetic scan skip
  if [ -n "$files" ] || [ "$do_scan" = 1 ]; then
    _pr_snapshot || { _pr_sum_unavail; return 0; }
  fi
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    _pr_classify "$f"
    n=$((n + 1))
    case "$E_CLASS" in
      running) nr=$((nr + 1)) ;;
      overdue) no=$((no + 1)) ;;
      orphaned) na=$((na + 1)) ;;
      *) nf=$((nf + 1)) ;;
    esac
    [ "$E_CLASS" = finished ] || live="$live$E_PID "   # a registered pid is never counted unregistered
  done <<<"$files"
  line="proc-registry: summary — $n entries: $nr running, $no overdue, $na orphaned, $nf finished"
  if [ "$scan" = 1 ]; then
    [ "$do_scan" != 1 ] || u="$(_pr_unreg_count "$live")"
    line="$line; $u unregistered"
  fi
  printf '%s\n' "$line"
  return 0
}

# ---- reap -------------------------------------------------------------------------------------------

# _pr_log <line> — append to reap.log, then keep only its last 1000 lines.
_pr_log() {
  local log="$PR_DIR/reap.log" tmp
  printf '%s\t%s\n' "$(_pr_now_iso)" "$1" >> "$log" 2>/dev/null || return 0
  tmp="$(mktemp "$PR_DIR/.reap-log.XXXXXX" 2>/dev/null)" || return 0
  if tail -n 1000 "$log" > "$tmp" 2>/dev/null; then mv -f "$tmp" "$log" 2>/dev/null || rm -f "$tmp"; else rm -f "$tmp"; fi
  return 0
}

# _pr_wait_unmatched <seconds> — poll (0.1 s) while the entry's process still matches, up to <seconds>.
_pr_wait_unmatched() {
  local end=$(( $(date +%s) + $1 ))
  while _pr_matches "$E_PID" "$E_START" "$E_HASH"; do
    [ "$(date +%s)" -lt "$end" ] || return 0
    sleep 0.1
  done
  return 0
}

# _pr_stop <file> — the overdue/orphaned path of `reap --apply`. Prints the outcome; logs one line.
_pr_stop() {
  local f="$1" what="$E_ID${PR_T}$E_KIND${PR_T}pid=$E_PID${PR_T}class=$E_CLASS" outcome="" keep=0 nokill=""
  if ! _pr_matches "$E_PID" "$E_START" "$E_HASH"; then
    outcome="not signalled: no longer matches ($PR_WHY); pruned"
  elif ! kill -TERM "$E_PID" 2>/dev/null; then
    outcome="TERM failed; entry kept"; keep=1
  else
    _pr_wait_unmatched "$E_GRACE"
    if [ -n "$(_pr_lstart "$E_PID")" ]; then
      _pr_matches "$E_PID" "$E_START" "$E_HASH" || nokill="$PR_WHY"
      if [ -n "$nokill" ]; then
        outcome="stopped (TERM); no KILL: no longer matches ($nokill)"
      elif ! kill -KILL "$E_PID" 2>/dev/null; then
        outcome="TERM ignored; KILL failed; entry kept"; keep=1
      else
        _pr_wait_unmatched 2
        if _pr_matches "$E_PID" "$E_START" "$E_HASH"; then
          outcome="survived KILL; entry kept"; keep=1
        else
          outcome="stopped (TERM+KILL)"
        fi
      fi
    else
      outcome="stopped (TERM)"
    fi
  fi
  [ "$keep" -eq 1 ] || rm -f "$f" 2>/dev/null
  _pr_log "$what${PR_T}$outcome${PR_T}$E_EVID"
  printf '%s %s (%s, pid %s): %s\n' "$E_CLASS" "$E_ID" "$E_KIND" "$E_PID" "$outcome"
  return 0
}

# _pr_owned_last — the entry files on stdin, those without an owner_pid first (order otherwise kept), so
# a session whose wrapper this pass stops is classified after that stop (header: WRAPPER KINDS).
_pr_owned_last() {
  local f owned=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ "$(jq -r '.owner_pid // empty' "$f" 2>/dev/null)" = "" ]; then printf '%s\n' "$f"; else owned="$owned$f
"; fi
  done
  printf '%s' "$owned"
}

# _pr_dry_row — what `reap` WOULD do with the classified entry (E_*); prints only.
_pr_dry_row() {
  case "$E_CLASS" in
    overdue|orphaned) printf 'would stop %s (%s, pid %s, %s): TERM, KILL after %ss if it still matches — %s\n' "$E_ID" "$E_KIND" "$E_PID" "$E_CLASS" "$E_GRACE" "$E_EVID" ;;
    finished) printf 'would prune %s (%s, pid %s, finished): no signal — %s\n' "$E_ID" "$E_KIND" "$E_PID" "$E_EVID" ;;
    *) printf 'keep %s (%s, pid %s, running)\n' "$E_ID" "$E_KIND" "$E_PID" ;;
  esac
}

cmd_reap() {
  local apply=0 ids="" a f files="" id
  while [ "$#" -gt 0 ]; do
    a="$1"; shift
    case "$a" in
      --apply) apply=1 ;;
      -h|--help) pr_usage; return 0 ;;
      -*) printf '%s: reap — unknown option %s\n' "$PR_ME" "$a" >&2; pr_usage >&2; return 2 ;;
      *)
        case "$a" in
          *[!A-Za-z0-9-]*|-*|'') printf '%s: reap — malformed id %s\n' "$PR_ME" "$a" >&2; return 2 ;;
        esac
        ids="$ids $a" ;;
    esac
  done
  if ! _pr_resolve_dir || ! command -v jq >/dev/null 2>&1; then
    printf '(no entries)\n'; return 0
  fi
  if [ -n "$ids" ]; then
    files=""
    for id in $ids; do
      if [ -f "$PR_DIR/$id.json" ]; then files="$files$PR_DIR/$id.json
"
      else printf '%s: reap — no entry %s (skipped)\n' "$PR_ME" "$id" >&2; fi
    done
  else
    files="$(_pr_entry_files)"
  fi
  files="$(printf '%s\n' "$files" | _pr_owned_last)"
  local n=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    n=$((n + 1))
    _pr_classify "$f"
    [ "$apply" -eq 1 ] || { _pr_dry_row; continue; }   # the dry-run gate: nothing below runs without --apply
    case "$E_CLASS" in
      overdue|orphaned) _pr_stop "$f" ;;
      finished)
        rm -f "$f" 2>/dev/null
        _pr_log "$E_ID${PR_T}$E_KIND${PR_T}pid=$E_PID${PR_T}class=finished${PR_T}pruned (no signal)${PR_T}$E_EVID"
        printf 'finished %s (%s, pid %s): pruned (no signal) — %s\n' "$E_ID" "$E_KIND" "$E_PID" "$E_EVID" ;;
      *) printf 'keep %s (%s, pid %s, running)\n' "$E_ID" "$E_KIND" "$E_PID" ;;
    esac
  done <<<"$files"
  [ "$n" -gt 0 ] || printf '(no entries)\n'
  [ "$apply" -eq 1 ] || printf '(dry run — nothing signalled or changed; re-run with --apply)\n'
  return 0
}

# ---- dispatch ---------------------------------------------------------------------------------------

sub="${1:-}"
[ "$#" -gt 0 ] && shift
case "$sub" in
  register) cmd_register "$@"; exit 0 ;;
  list) cmd_list "$@"; exit 0 ;;
  summary) cmd_summary "$@"; exit $? ;;
  reap) cmd_reap "$@"; exit $? ;;
  help|-h|--help) pr_usage; exit 0 ;;
  '') printf '%s: missing subcommand\n' "$PR_ME" >&2; pr_usage >&2; exit 2 ;;
  *) printf '%s: unknown subcommand %s\n' "$PR_ME" "$sub" >&2; pr_usage >&2; exit 2 ;;
esac
