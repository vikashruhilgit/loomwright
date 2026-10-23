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
#       as /usr/bin/env, the `#!/usr/bin/env bash` stage) — before hashing. Those launchers' lines
#       already carry the final arguments, so the substring alone would match (and hash) a line the
#       process is about to replace; this exec wait lives HERE and nowhere else — a launcher never
#       hand-rolls its own. If the condition never holds the entry is still written and one
#       `proc-registry: register — command line never matched --expect` line is printed on stderr.
#       Relative --repo / --runfile / --lane paths are made absolute against the caller's cwd.
#
# WRAPPER KINDS (lane, phase, drain): the registered pid is a wrapper, not the session it runs. The
# contract has two halves, and a reap never orphans the child only when both hold:
#   the wrapper  runs its child in the BACKGROUND, traps TERM/INT/HUP to pass a TERM on to it, and
#                waits while the child is alive before its own teardown (so its EXIT cleanup never
#                runs under a live child);
#   reap         for these kinds only, the KILL leg (the wrapper still matches after grace_s) KILLs
#                the wrapper's live direct children first — read from one `ps` pass made right after
#                the wrapper's own identity re-check, so a child pid is never taken from the entry —
#                then waits up to another grace_s for the wrapper to finish its teardown by itself,
#                and KILLs the wrapper only if it STILL matches after that. A wrapper cannot pass a
#                KILL on, which is why reap delivers that one itself.
#   Honest limit: only DIRECT children; a grandchild the session itself started is the session's.
#   list
#       One row per entry (TSV after a `# id kind pid age class evidence` header): id, kind, pid,
#       age (the live process's elapsed time, `-` when it is gone), class, and the evidence for that
#       class. Read-only: creates nothing, changes nothing. ALWAYS exits 0; an empty, missing or
#       unavailable registry prints `(no entries)`.
#   reap [--apply] [<id>...]
#       Without --apply (the DEFAULT): a dry run — prints the action it would take per entry, sends
#       no signal, writes nothing. With --apply, per entry (all entries, or only the named ids):
#         overdue / orphaned  re-read the live lstart + command-line hash IMMEDIATELY before the
#                             signal; TERM; wait up to the entry's grace_s while it still matches;
#                             re-check again and send KILL only if it STILL matches (a wrapper
#                             kind's children first — see WRAPPER KINDS); remove the entry (kept
#                             only when the process survives a KILL, or a signal fails).
#         finished            pruned: the file is removed, no signal.
#         running             never touched.
#       Every processed (non-running) entry appends one line to <registry dir>/reap.log; each append
#       keeps that log to its last 1000 lines (nothing else rotates it). An id that is not in the
#       registry is reported and skipped. Exits 0; a usage error (unknown option, malformed id)
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
#   grace_s         seconds reap waits between TERM and KILL (default 10)
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
# REGISTRY LOCATION (resolved per call, in this order):
#   1. $LOOMWRIGHT_PROC_REGISTRY_DIR when non-empty (the test seam);
#   2. HERMETIC REDIRECT — when HERMETIC_TEST_ENV=1 (hermetic-test-env.sh): $HERMETIC_SHIM_DIR/procs.
#      If HERMETIC_SHIM_DIR is empty or not a directory the registry is UNAVAILABLE: register fails
#      safe (`register failed — hermetic registry dir unavailable`), list / reap see no entries. It
#      never falls back to $HOME and never to `/procs`;
#   3. ${HOME}/.claude/loomwright/procs (user scope, whatever the host mode). An empty HOME is
#      unavailable, the same way.
#   Known limit: a test that neither sources hermetic-test-env.sh nor sets the override, run
#   standalone, still registers into the real home registry.
#
# EXIT CODES: register 0 always; list 0 always; reap 0 (usage error 2); missing/unknown subcommand 2.
# bash 3.2 / BSD userland and Linux procps; needs jq and ps.

set -uo pipefail

PR_ME="proc-registry"
PR_T="$(printf '\t')"

pr_usage() {
  cat <<'USAGE'
usage: proc-registry.sh register --pid <p> --kind <phase|lane|drain|postmortem|merge-watch> --purpose <text> [options]
       proc-registry.sh list
       proc-registry.sh reap [--apply] [<id>...]
See the header comment of proc-registry.sh for the full contract.
USAGE
}

# ---- primitives -------------------------------------------------------------------------------------

_pr_trim() { sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

_pr_is_uint() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac; return 0; }
_pr_is_pos_int() { _pr_is_uint "${1:-}" && [ "$1" -gt 0 ] 2>/dev/null; }

# _pr_lstart <pid> — the process start time, TZ- and locale-pinned; empty when the pid is gone.
_pr_lstart() {
  _pr_is_uint "${1:-}" || return 0
  env TZ=UTC0 LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | _pr_trim
}

# _pr_cmdline <pid> — the full live command line; empty when the pid is gone.
_pr_cmdline() {
  _pr_is_uint "${1:-}" || return 0
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
  e="$(env LC_ALL=C ps -o etime= -p "$1" 2>/dev/null | tr -d '[:space:]')"
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
    grace=10
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

  local st st2 cmd="" matched=0 i=0 end
  st="$(_pr_lstart "$pid")"
  [ -n "$st" ] || { _pr_reg_fail "pid $pid is not running"; return 0; }
  if [ -n "$expect" ]; then
    end=$(( $(date +%s) + 3 ))
    while :; do
      cmd="$(_pr_cmdline "$pid")"
      case "$cmd" in *"$expect"*) _pr_pre_exec "$cmd" || { matched=1; break; } ;; esac
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

# ---- classification (list + reap) -------------------------------------------------------------------

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

# _pr_is_wrapper_kind <kind> — the kinds whose registered pid is a wrapper (header: WRAPPER KINDS).
_pr_is_wrapper_kind() { case "$1" in lane|phase|drain) return 0 ;; esac; return 1; }

# _pr_children <pid> — the live direct children of <pid>, one per line, from ONE `ps` pass (same flags on
# BSD and procps); a zombie child is skipped.
_pr_children() {
  _pr_is_uint "${1:-}" || return 0
  env LC_ALL=C ps -A -o pid= -o ppid= -o stat= 2>/dev/null | awk -v p="$1" '$2 == p && $3 !~ /^Z/ { print $1 }'
}

# _pr_stop <file> — the overdue/orphaned path of `reap --apply`. Prints the outcome; logs one line.
_pr_stop() {
  local f="$1" what="$E_ID${PR_T}$E_KIND${PR_T}pid=$E_PID${PR_T}class=$E_CLASS" outcome="" keep=0 nokill=""
  local kids k nkids=0 kidnote=""
  if ! _pr_matches "$E_PID" "$E_START" "$E_HASH"; then
    outcome="not signalled: no longer matches ($PR_WHY); pruned"
  elif ! kill -TERM "$E_PID" 2>/dev/null; then
    outcome="TERM failed; entry kept"; keep=1
  else
    _pr_wait_unmatched "$E_GRACE"
    if [ -n "$(_pr_lstart "$E_PID")" ]; then
      _pr_matches "$E_PID" "$E_START" "$E_HASH" || nokill="$PR_WHY"
      if [ -z "$nokill" ] && _pr_is_wrapper_kind "$E_KIND"; then
        # WRAPPER KINDS (header): the wrapper still matches (re-checked just above), so its live
        # direct children are its session — KILL them, then give the wrapper its own teardown time
        kids="$(_pr_children "$E_PID")"
        for k in $kids; do kill -KILL "$k" 2>/dev/null && nkids=$((nkids + 1)); done
        if [ "$nkids" -gt 0 ]; then
          kidnote=" (KILLed $nkids child process(es) of the wrapper)"
          _pr_wait_unmatched "$E_GRACE"
        fi
      fi
      if [ -n "$nokill" ]; then
        outcome="stopped (TERM); no KILL: no longer matches ($nokill)"
      elif [ "$nkids" -gt 0 ] && ! _pr_matches "$E_PID" "$E_START" "$E_HASH"; then
        outcome="stopped (TERM+KILL)$kidnote; the wrapper then exited by itself"
      elif ! kill -KILL "$E_PID" 2>/dev/null; then
        outcome="TERM ignored; KILL failed$kidnote; entry kept"; keep=1
      else
        _pr_wait_unmatched 2
        if _pr_matches "$E_PID" "$E_START" "$E_HASH"; then
          outcome="survived KILL$kidnote; entry kept"; keep=1
        else
          outcome="stopped (TERM+KILL)$kidnote"
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

# _pr_dry_row — what `reap` WOULD do with the classified entry (E_*); prints only.
_pr_dry_row() {
  case "$E_CLASS" in
    overdue|orphaned)
      if _pr_is_wrapper_kind "$E_KIND"; then
        printf 'would stop %s (%s, pid %s, %s): TERM, KILL after %ss if it still matches (its children first) — %s\n' "$E_ID" "$E_KIND" "$E_PID" "$E_CLASS" "$E_GRACE" "$E_EVID"
      else
        printf 'would stop %s (%s, pid %s, %s): TERM, KILL after %ss if it still matches — %s\n' "$E_ID" "$E_KIND" "$E_PID" "$E_CLASS" "$E_GRACE" "$E_EVID"
      fi ;;
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
  reap) cmd_reap "$@"; exit $? ;;
  help|-h|--help) pr_usage; exit 0 ;;
  '') printf '%s: missing subcommand\n' "$PR_ME" >&2; pr_usage >&2; exit 2 ;;
  *) printf '%s: unknown subcommand %s\n' "$PR_ME" "$sub" >&2; pr_usage >&2; exit 2 ;;
esac
