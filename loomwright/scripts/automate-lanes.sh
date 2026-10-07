#!/usr/bin/env bash
# automate-lanes.sh — lane lifecycle for `/automate --parallel N` (parallel-automate/05).
#
# A LANE is a local clone of the primary checkout at `<primary>-lanes/<parent_run_id>/L<n>/` that runs
# the ordinary per-item `/automate` loop for ONE item, headless (`claude -p`), with a question channel
# (lane shape A + relay). One coordinator in the primary creates, launches and removes lanes through
# this script. Without `--parallel`, or with N = 1, nothing here is ever called.
#
# Usage (standalone: `bash automate-lanes.sh <subcmd> ...`):
#   lane-create <parent_runfile> <item> <n> [--parallel N] [--max-tokens T]
#        clone + origin-before-fetch + meta pull + carried configs + lane.json + one-line backlog + relay hooks
#   lane-launch <lane_dir> --owner-command '<cmd the owner typed>' [--resume-run <run_id> | --continue]
#        detached headless launch (or resume by run id / fixed decision-free continue message)
#   lane-launch <lane_dir> --host-denied '<reason>'      record a host-refused spawn as blocked_launch
#   relay-hook                                           PreToolUse / PermissionRequest hook (stdin: hook JSON)
#   lane-answer <lane_dir> <tool_use_id> --owner-command '<cmd>' [--via <client>]
#        stdin: {"answers":{"0":"<label>"},"note":"<optional free text>"}; validates, records, resumes
#   lane-remove <lane_dir> [--stop] [--abandon]          guarded removal (salvages first)
#   lane-info [--root <dir>]                             print .supervisor/lane.json (exit 1 when absent)
#   init-check --parallel N [--auto-merge]               INIT refusals: `ok` | `refuse: <reason>` (exit 1)
#   pick-guard <automate_dir>                            PICK guard: `ok` | `refuse: live_lane <run_id> <lane>`
#   branch-check <lane_dir> <branch>                     remote branch-name check: prints the name to use
#   lane-status [<parent_runfile>] [--json] [--watch] [--refresh-readiness] [--keep-awake]
#        one line per lane: state, item, PR, progress, last 3 actions, question, CI slot, readiness
#   lane-status [<parent_runfile>] --leaks [--snapshot]  Validation 5 leak check vs the wave-start snapshot
#   lane-status [<parent_runfile>] --resources | --tokens  latest fleet.log line + peak | per-lane + parent tokens
#   lane-feed <lane_dir|L<n>> [--follow]                 readable narration of the lane's stream log
#   lane-readiness <lane_dir|L<n>>                       write <run_id>.merge-readiness.md (advisory, never merges)
#
# Files (all paths derived; nothing hard-coded):
#   <lane>/.supervisor/lane.json        D2 marker — the ONE marker lane-create writes (plus the copied
#                                       configs, the intake `lane-backlog.md`, and the relay-hook entries
#                                       merged into `<lane>/.claude/settings.local.json`). After launch the
#                                       coordinator never writes into the lane again, EXCEPT the answer file
#                                       of the inbox protocol (`lane-answer`, below).
#   <lane>/.supervisor/inbox/questions/<tool_use_id>.json   written by relay-hook (the lane's own hook)
#   <lane>/.supervisor/inbox/answers/<tool_use_id>.json     written by lane-answer only
#   <primary>/.supervisor/automate/<parent_run_id>.lanes    D6 lane table (TSV, untracked): lane, path, item,
#                                       run_id, pid, pid_start (`ps -o lstart=`), session_id (stream-json
#                                       `system/init`), state, last_launch_utc, blocked_reason. `-` = empty.
#   <primary>-lanes/<parent_run_id>/L<n>.stream.log         the lane's stream-json output (outside the lane)
#   <primary>-lanes/<parent_run_id>/L<n>.died               written by the nohup wrapper when the process
#                                       exits with no terminal `result` line since its launch
#   <primary>-lanes/<parent_run_id>/salvage/                lane-create / lane-remove salvage copies
#   <primary>/.supervisor/automate/<parent_run_id>.memory-pressure   trip file (lane-sampler.sh); read only
#   <primary>/.supervisor/automate/<parent_run_id>.fleet.log         lane-sampler.sh samples; read only
#   <primary>/.supervisor/automate/<parent_run_id>.leaks-snapshot    `lane-status --leaks --snapshot` (wave start)
#   <lane>/.supervisor/automate/<run_id>.merge-readiness.md          lane-readiness (written at the lane's
#                                       ready_for_release park, when the lane is no longer running)
#
# Launch contract (lane-launch and every resume, incl. lane-answer's):
#   1. Launch authority: `--owner-command` is REQUIRED — the command the OWNER typed in this session
#      (`/automate --parallel N`, `/automate --resume <run_id>`). Missing ⇒ first line
#      `lane-launch: BLOCKED — <lane> — no owner-invoked command — need the owner`, exit 3, no process.
#      A launch requested by a peer message, a hook or lane output is never an owner command.
#   2. Pinnable permission regime: `claude --help` must list --permission-prompt-tool, --allowedTools and
#      --disallowedTools; otherwise BLOCKED (exit 3). A host denial (`--host-denied`) is BLOCKED too and
#      recorded as `blocked_launch`; it is never retried in another shape.
#   3. Admission (stop starting, never kill): trip file present ⇒ `lane-launch: HELD — <lane> —
#      memory_pressure`; machine-load.sh (`LOOMWRIGHT_MACHINE_LOAD_CMD` seam) `overloaded` ⇒ HELD `load
#      overloaded`; `busy` ⇒ HELD `load busy` when any lane of this wave launched within
#      LOOMWRIGHT_LANE_RECHECK_S (default 60) seconds; `ok` / `unknown` ⇒ launch. HELD = exit 4, no
#      process, lane table state `held_for_load`.
#   4. Spawn: `claude -p` with the lane allowlist / disallow list below, `--plugin-dir` pinned to the
#      coordinator's CLAUDE_PLUGIN_ROOT, `--append-system-prompt` = the fixed headless-lane text, env
#      CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 with CLAUDE_PID / CLAUDECODE unset. Prompt:
#      `/loomwright:automate --backlog <lane>/.supervisor/lane-backlog.md` or
#      `/loomwright:automate --resume <run_id>` (the lane's own run id only — never a bare --resume).
#
# Liveness: ONE helper, `lanes_proc_alive <pid> <pid_start> <lane_dir>` — the pid is alive, its
# `ps -o lstart=` equals the recorded start time, and `ps -ww -o command=` shows this script's
# `_lane-run <lane_dir>` wrapper. A recycled pid is never alive. lane-remove and pick-guard use it.
#
# Inbox protocol: relay-hook records the question (`asked_at` UTC) and returns `defer`; the lane exits
# `stop_reason: tool_deferred`. lane-answer accepts exactly the question's own option labels
# (multiSelect: comma-joined, each validated; one unknown label refuses the whole answer); a note alone
# is refused. The note IS delivered: on resume relay-hook returns `allow` with `updatedInput.answers`
# and `updatedInput.annotations` = {<question>: {notes: <note>}} for every answered question.
# A PermissionRequest[AskUserQuestion] (a question bundled with other calls) is denied with a re-ask.
#
# Failure posture: correctness gates (lane-remove refusals, pick-guard, init-check, launch authority,
# origin-before-fetch, remote branch-name hit) fail CLOSED; relay-hook outside a lane emits `{}`.
# Every meta-sync call passes `--branch` explicitly (the mode line's branch).
#
# Observation (lane-status, lane-feed, lane-readiness) fails SAFE: an absent or unreadable source reads
# `unknown` and the command exits 0. lane-status state, first match wins: removed/abandoned,
# blocked_launch, held_for_load, created, missing, running (lanes_proc_alive), awaiting_input, the run
# file's park (merged / gone after reconcile-item), lost_to_reset (boot later than the last launch),
# died (.died marker), stalled (process gone, not parked, no question). Keep-awake is SUGGESTED on macOS
# (`caffeinate -i -w <coordinator pid>`); only `lane-status --keep-awake` starts it.
#
# Test seams: LOOMWRIGHT_LANES_META_SYNC (meta-sync.sh path), LOOMWRIGHT_LANES_SETUP_MEMORY
# (setup-memory.sh path), LOOMWRIGHT_LANES_HELPERS (automate-helpers.sh path),
# LOOMWRIGHT_LANES_INIT_WAIT_S (default 15: wait for the session id), LOOMWRIGHT_LANES_STOP_GRACE_S
# (default 60: TERM→KILL grace for --stop), LOOMWRIGHT_MACHINE_LOAD_CMD, LOOMWRIGHT_LANE_RECHECK_S,
# LOOMWRIGHT_GH_BIN, LOOMWRIGHT_LANES_CI_SLOT, LOOMWRIGHT_LANES_PGREP, LOOMWRIGHT_LANES_CAFFEINATE,
# LOOMWRIGHT_LANES_UNAME, LOOMWRIGHT_LANES_COORDINATOR_PID, LOOMWRIGHT_LANES_BOOT_EPOCH,
# LOOMWRIGHT_LANES_TOKEN_LEDGER, LOOMWRIGHT_LANES_WATCH_ITERATIONS, LOOMWRIGHT_LANES_WATCH_INTERVAL_S.
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
HERE="$(dirname "$SELF")"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$HERE/.." && pwd)}"
META_SYNC="${LOOMWRIGHT_LANES_META_SYNC:-$HERE/meta-sync.sh}"
SETUP_MEMORY="${LOOMWRIGHT_LANES_SETUP_MEMORY:-$HERE/setup-memory.sh}"
HELPERS="${LOOMWRIGHT_LANES_HELPERS:-$HERE/automate-helpers.sh}"

# The lane allowlist (the minimum S1 found sufficient) and the DISALLOW list. These two are the only
# lines in this file that may name the merge / admin tokens (Validation 3 greps for them).
LANE_ALLOWED_TOOLS="Bash,Read,Edit,Write,Glob,Grep,Task,Agent,AskUserQuestion"
LANE_DISALLOWED_FIXED="Bash(gh pr merge:*),Bash(gh pr merge *),Bash(*--admin*),Bash(git push --force:*),Bash(git push -f:*),Bash(git push --force-with-lease:*),Bash(git push *--force*)"
LANE_SYS="You are running as a HEADLESS lane (claude -p). Ending your turn ENDS this process and stops any background task. Never end your turn to wait for background work (CI, checks, subagents, long commands): wait in the FOREGROUND with a blocking Bash call or a Monitor you wait on. End your turn only when the item is parked, or when you must ask the owner via AskUserQuestion."
LANE_CONTINUE_MSG="continue where you left off; wait in the foreground"
LT_HEADER="$(printf '#lane\tpath\titem\trun_id\tpid\tpid_start\tsession_id\tstate\tlast_launch_utc\tblocked_reason')"

die() { echo "automate-lanes: $*" >&2; exit 1; }
now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }
_trim_ws() { tr -s ' ' | sed 's/^ //; s/ $//'; }
_clean() { local v="${1:-}"; [ -n "$v" ] || v="-"; printf '%s' "$v" | tr '\t\n' '  '; }

# ---- lane table (D6) ----------------------------------------------------------------------------
_lt_lock() {
  local i=0
  while ! mkdir "$1.lock" 2>/dev/null; do
    i=$((i + 1)); if [ "$i" -gt 100 ]; then rmdir "$1.lock" 2>/dev/null; i=0; fi; sleep 0.1
  done
}
_lt_unlock() { rmdir "$1.lock" 2>/dev/null || true; }

# _lt_set <table> <lane> <col> <val> [<col> <val> ...] — rewrite one row's columns (1-based).
_lt_set() {
  local f="$1" lane="$2" spec="" rc; shift 2
  [ -f "$f" ] || return 1
  _lt_lock "$f"
  (
    while [ "$#" -ge 2 ]; do export "LT_C$1=$(_clean "$2")"; spec="$spec $1"; shift 2; done
    LT_SPEC="$spec" LT_LANE="$lane" awk -F'\t' -v OFS='\t' '
      BEGIN { n = split(ENVIRON["LT_SPEC"], s, " ") }
      $1 == ENVIRON["LT_LANE"] { for (i = 1; i <= n; i++) $(s[i]) = ENVIRON["LT_C" s[i]] }
      { print }' "$f" > "$f.tmp.$$" && mv "$f.tmp.$$" "$f"
  )
  rc=$?; _lt_unlock "$f"; return "$rc"
}

# _lt_get <table> <lane> <col> — one column ('' for `-` or no row).
_lt_get() {
  [ -f "$1" ] || return 0
  awk -F'\t' -v l="$2" -v c="$3" '$1 == l { v = $c } END { if (v != "-") printf "%s", v }' "$1"
}

# ---- lane context -------------------------------------------------------------------------------
# _lane_ctx <lane_dir> — sets LN_* from <lane_dir>/.supervisor/lane.json; returns 1 when not a lane.
_lane_ctx() {
  local d="${1:-}" j
  [ -n "$d" ] && [ -d "$d" ] || return 1
  LN_DIR="$(cd "$d" && pwd -P)"; j="$LN_DIR/.supervisor/lane.json"
  [ -s "$j" ] || return 1
  LN_LANE="$(jq -r '.lane // empty' "$j" 2>/dev/null)"
  LN_RUN="$(jq -r '.run_id // empty' "$j" 2>/dev/null)"
  LN_PARENT="$(jq -r '.parent_run_id // empty' "$j" 2>/dev/null)"
  LN_PRIMARY="$(jq -r '.primary // empty' "$j" 2>/dev/null)"
  case "$LN_LANE" in L[0-9]|L[0-9][0-9]) ;; *) return 1 ;; esac
  case "$LN_PARENT" in ''|*/*|.*) return 1 ;; esac
  [ "$LN_RUN" = "$LN_PARENT-$LN_LANE" ] || return 1
  [ -n "$LN_PRIMARY" ] || return 1
  LN_TABLE="$LN_PRIMARY/.supervisor/automate/$LN_PARENT.lanes"
  LN_ROOT="$(dirname "$LN_DIR")"
  LN_LOG="$LN_ROOT/$LN_LANE.stream.log"
  LN_DIED="$LN_ROOT/$LN_LANE.died"
  LN_INBOX="$LN_DIR/.supervisor/inbox"
  return 0
}

# ---- shared liveness helper (lane-remove, pick-guard; Subtask 2's lane-status reuses it) ------------
# lanes_proc_alive <pid> <pid_start> <lane_dir> — 0 only for a VERIFIED live lane process.
lanes_proc_alive() {
  local pid="${1:-}" st="${2:-}" dir="${3:-}" cur cmd
  case "$pid" in ''|-|*[!0-9]*) return 1 ;; esac
  command -v ps >/dev/null 2>&1 || return 0   # cannot verify ⇒ treat as alive (callers are gates)
  cur="$(ps -o lstart= -p "$pid" 2>/dev/null | _trim_ws)"
  [ -n "$cur" ] || return 1
  [ "$cur" = "$(printf '%s' "$st" | _trim_ws)" ] || return 1
  cmd="$(ps -ww -o command= -p "$pid" 2>/dev/null)"
  case "$cmd" in
    *"automate-lanes.sh _lane-run $dir "*|*"automate-lanes.sh _lane-run $dir") return 0 ;;
  esac
  return 1
}

# _lanes_pending_question <inbox> — prints the first recorded question id with no answer file.
_lanes_pending_question() {
  local q id
  for q in "$1"/questions/*.json; do
    [ -f "$q" ] || continue
    id="$(basename "$q" .json)"
    [ -e "$1/answers/$id.json" ] || { printf '%s' "$id"; return 0; }
  done
  return 1
}

# ---- meta-sync (always with --branch) -----------------------------------------------------------
# _lanes_meta_branch <root> — prints the branch for `on <Y>`, prints nothing for `off`, returns 1 otherwise.
_lanes_meta_branch() {
  local m; m="$(bash "$SETUP_MEMORY" --root "$1" mode 2>/dev/null | head -1)"
  case "$m" in
    "on "?*) printf '%s' "${m#on }" ;;
    off) ;;
    *) return 1 ;;
  esac
}

# ---- salvage (copy, never move) -----------------------------------------------------------------
_lanes_salvage() { # <dir> <dest_parent> <label> — prints the destination
  local dir="$1" dest="$2/$3-$(date -u +%Y%m%dT%H%M%SZ)-$$" f
  mkdir -p "$dest" || return 1
  if [ -d "$dir/.git" ]; then
    git -C "$dir" rev-parse HEAD > "$dest/BASE_SHA" 2>/dev/null
    git -C "$dir" status --porcelain > "$dest/status.txt" 2>/dev/null
    git -C "$dir" diff HEAD > "$dest/tracked.patch" 2>/dev/null
    git -C "$dir" ls-files --others --exclude-standard 2>/dev/null | while IFS= read -r f; do
      [ -n "$f" ] || continue; mkdir -p "$dest/untracked/$(dirname "$f")"; cp -p "$dir/$f" "$dest/untracked/$f" 2>/dev/null
    done
  fi
  [ -d "$dir/.supervisor" ] && cp -R "$dir/.supervisor" "$dest/supervisor" 2>/dev/null
  printf '%s' "$dest"
}

# ---- relay hook settings merge (never replaces an existing `hooks` key) -------------------------
_lanes_merge_hooks() { # <settings_file> <hook_command>
  local f="$1" cmd="$2" base="{}" out
  mkdir -p "$(dirname "$f")" || return 1
  if [ -s "$f" ]; then base="$(cat "$f")"; jq -e 'type == "object"' >/dev/null 2>&1 <<<"$base" || return 1; fi
  out="$(jq --arg h "$cmd" '
    def add($ev): .hooks[$ev] = (((.hooks[$ev]) // [])
      | if any(.[]?; (.hooks // []) | any(.[]?; .command == $h)) then .
        else . + [{matcher: "AskUserQuestion", hooks: [{type: "command", command: $h}]}] end);
    .hooks = (.hooks // {}) | add("PreToolUse") | add("PermissionRequest")' <<<"$base")" || return 1
  printf '%s\n' "$out" > "$f.tmp.$$" && mv "$f.tmp.$$" "$f"
}

# ==================================================================================================
# lane-create <parent_runfile> <item> <n> [--parallel N] [--max-tokens T]
lanes_create() {
  local runfile="" item="" n="" par="" maxt="" a
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --parallel) par="${2:-}"; shift 2 ;;
      --max-tokens) maxt="${2:-}"; shift 2 ;;
      *) if [ -z "$runfile" ]; then runfile="$1"; elif [ -z "$item" ]; then item="$1"; elif [ -z "$n" ]; then n="$1"
         else die "lane-create: unexpected argument '$1'"; fi; shift ;;
    esac
  done
  [ -n "$runfile" ] && [ -n "$item" ] && [ -n "$n" ] || die "usage: lane-create <parent_runfile> <item> <n> [--parallel N] [--max-tokens T]"
  case "$n" in [1-9]|10) ;; *) die "lane-create: lane number must be 1..10 (got '$n')" ;; esac
  [ -n "$par" ] || par="$n"
  case "$par" in [1-9]|10) ;; *) die "lane-create: --parallel must be 1..10 (got '$par')" ;; esac
  case "$maxt" in ''|*[!0-9]*) [ -z "$maxt" ] || die "lane-create: --max-tokens must be a whole number" ;; esac
  case "$item" in /*|*..*) die "lane-create: item must be the canonical repo-relative path (got '$item')" ;; esac
  [ -f "$runfile" ] || die "lane-create: run file not found: $runfile"
  local rdir parent primary
  rdir="$(cd "$(dirname "$runfile")" && pwd -P)"; parent="$(basename "$runfile" .md)"
  case "$parent" in ''|*/*|.*|*-L[0-9]|*-L[0-9][0-9]) die "lane-create: bad parent run file name '$parent'" ;; esac
  [ "$(basename "$rdir")" = automate ] && [ "$(basename "$(dirname "$rdir")")" = .supervisor ] \
    || die "lane-create: run file must live in <primary>/.supervisor/automate/"
  primary="$(cd "$rdir/../.." && pwd -P)"
  [ "$(git -C "$primary" rev-parse --show-toplevel 2>/dev/null)" = "$primary" ] || die "lane-create: $primary is not a git checkout root"
  [ -f "$primary/$item" ] || die "lane-create: item not found in the primary: $item"
  local url; url="$(git -C "$primary" remote get-url origin 2>/dev/null)"
  [ -n "$url" ] || die "lane-create: refused — the primary has no origin remote"
  local lane="L$n" lroot="$primary-lanes/$parent" C run_id="$parent-L$n" table="$rdir/$parent.lanes"
  C="$lroot/$lane"
  if [ -e "$C" ]; then
    local sv; sv="$(_lanes_salvage "$C" "$lroot/salvage" "$lane-leftover")"
    echo "lane-create: refused — leftover lane directory $C (salvaged to ${sv:-<salvage failed>}); never reused" >&2
    return 1
  fi
  mkdir -p "$lroot" || die "lane-create: cannot create $lroot"
  _abort() { rm -rf "$C"; echo "lane-create: aborted $lane — $1 (clone removed)" >&2; return 1; }
  git clone -q --local "$primary" "$C" 2>/dev/null || { _abort "clone failed"; return 1; }
  # origin = the primary's remote URL BEFORE any fetch; prune the refs the --local clone inherited.
  git -C "$C" remote set-url origin "$url" || { _abort "could not set origin"; return 1; }
  git -C "$C" fetch -q --prune origin 2>/dev/null || { _abort "fetch from origin failed"; return 1; }
  git -C "$C" for-each-ref --format='%(refname)' refs/remotes/origin | while IFS= read -r a; do
    git -C "$C" rev-parse -q --verify "$a" >/dev/null 2>&1 || git -C "$C" update-ref -d "$a" 2>/dev/null
  done
  git -C "$C" remote set-head origin -a >/dev/null 2>&1
  local base; base="$(git -C "$C" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"; base="${base#origin/}"
  [ -n "$base" ] || base=main
  git -C "$C" checkout -q -B "$base" "origin/$base" 2>/dev/null || { _abort "base branch origin/$base not found"; return 1; }
  # metadata pull (always --branch); non-zero ⇒ abort the lane.
  local mb
  if ! mb="$(_lanes_meta_branch "$C")"; then _abort "metadata mode unknown"; return 1; fi
  if [ -n "$mb" ]; then
    bash "$META_SYNC" pull --branch "$mb" --root "$C" >/dev/null 2>&1 || { _abort "meta-sync pull --branch $mb failed"; return 1; }
  fi
  [ -f "$C/$item" ] || { _abort "item $item absent in the lane after the metadata pull"; return 1; }
  mkdir -p "$C/.supervisor/automate" "$C/.supervisor/inbox/questions" "$C/.supervisor/inbox/answers" || { _abort "cannot create .supervisor"; return 1; }
  local cf
  for cf in config.json notify-config.json; do
    if [ -f "$primary/.supervisor/$cf" ]; then cp -p "$primary/.supervisor/$cf" "$C/.supervisor/$cf" || { _abort "cannot copy $cf"; return 1; }; fi
  done
  local mt=null; [ -n "$maxt" ] && mt=$((10#$maxt / par))
  jq -n --arg lane "$lane" --arg run "$run_id" --arg parent "$parent" --arg primary "$primary" \
    --argjson parallel "$par" --argjson mt "$mt" --arg created "$(now_utc)" \
    '{schema_version: 1, lane: $lane, run_id: $run, parent_run_id: $parent, primary: $primary,
      parallel: $parallel, max_tokens: $mt, created: $created}' > "$C/.supervisor/lane.json" \
    || { _abort "cannot write lane.json"; return 1; }
  printf -- '- [ ] %s\n' "$item" > "$C/.supervisor/lane-backlog.md" || { _abort "cannot write the backlog"; return 1; }
  _lanes_merge_hooks "$C/.claude/settings.local.json" "bash \"$PLUGIN_ROOT/scripts/automate-lanes.sh\" relay-hook" \
    || { _abort "cannot merge the relay hooks"; return 1; }
  local porc; porc="$(git -C "$C" status --porcelain 2>/dev/null)"
  [ -z "$porc" ] || { _abort "lane is not clean after setup: $(printf '%s' "$porc" | head -3 | tr '\n' ' ')"; return 1; }
  _lt_lock "$table"
  if [ ! -s "$table" ]; then
    { printf '%s\n' "$LT_HEADER"
      printf '# not carried into lanes: .claude/settings.local.json (relay hooks only), the rules stamp, Claude auto-memory\n'; } > "$table"
  fi
  awk -F'\t' -v l="$lane" '$1 != l' "$table" > "$table.tmp.$$" && mv "$table.tmp.$$" "$table"
  printf '%s\t%s\t%s\t%s\t-\t-\t-\tcreated\t-\t-\n' "$lane" "$C" "$(_clean "$item")" "$run_id" >> "$table"
  _lt_unlock "$table"
  echo "lane-create: $lane $C run_id=$run_id item=$item meta=${mb:-off}"
}

# ==================================================================================================
# _lanes_regime_ok — the CLI advertises a pinnable permission regime.
_lanes_regime_ok() {
  local h; h="$(claude --help 2>&1)" || true
  case "$h" in *--permission-prompt-tool*) ;; *) return 1 ;; esac
  case "$h" in *--allowedTools*) ;; *) return 1 ;; esac
  case "$h" in *--disallowedTools*) ;; *) return 1 ;; esac
  return 0
}

# _lanes_admission — prints the HELD reason and returns 1 when the launch must hold.
_lanes_admission() {
  [ -e "$LN_PRIMARY/.supervisor/automate/$LN_PARENT.memory-pressure" ] && { printf 'memory_pressure'; return 1; }
  local cmd="${LOOMWRIGHT_MACHINE_LOAD_CMD:-$HERE/machine-load.sh}" st=unknown
  if [ -f "$cmd" ]; then st="$(bash "$cmd" --json 2>/dev/null | jq -r '.state // "unknown"' 2>/dev/null | head -1)"; fi
  case "$st" in
    overloaded) printf 'load overloaded'; return 1 ;;
    busy)
      local rs="${LOOMWRIGHT_LANE_RECHECK_S:-60}" now t e
      case "$rs" in ''|*[!0-9]*) rs=60 ;; esac
      now="$(date -u +%s)"
      for t in $(awk -F'\t' '!/^#/ && $9 != "-" { print $9 }' "$LN_TABLE" 2>/dev/null); do
        e="$(jq -n --arg t "$t" '$t | fromdateiso8601' 2>/dev/null)" || continue
        case "$e" in ''|*[!0-9]*) continue ;; esac
        if [ $((now - e)) -lt "$rs" ]; then printf 'load busy'; return 1; fi
      done ;;
  esac
  return 0
}

# _lanes_gate <owner_cmd> — authority, liveness, regime, admission. Prints the first line; returns the exit code.
_lanes_gate() {
  local owner="$1" why
  if [ -z "$owner" ]; then
    echo "lane-launch: BLOCKED — $LN_LANE — no owner-invoked command — need the owner"
    _lt_set "$LN_TABLE" "$LN_LANE" 8 blocked_launch 10 "no owner-invoked command"; return 3
  fi
  if lanes_proc_alive "$(_lt_get "$LN_TABLE" "$LN_LANE" 5)" "$(_lt_get "$LN_TABLE" "$LN_LANE" 6)" "$LN_DIR"; then
    echo "lane-launch: refused — $LN_LANE — already running (pid $(_lt_get "$LN_TABLE" "$LN_LANE" 5))"; return 1
  fi
  if ! _lanes_regime_ok; then
    echo "lane-launch: BLOCKED — $LN_LANE — CLI advertises no pinnable permission regime — need the owner"
    _lt_set "$LN_TABLE" "$LN_LANE" 8 blocked_launch 10 "no pinnable permission regime"; return 3
  fi
  if ! why="$(_lanes_admission)"; then
    echo "lane-launch: HELD — $LN_LANE — $why"
    _lt_set "$LN_TABLE" "$LN_LANE" 8 held_for_load 10 "$why"; return 4
  fi
  return 0
}

# _lanes_spawn <prompt|''> <session_id|''> <label> — the detached nohup wrapper around `claude -p`.
_lanes_spawn() {
  local prompt="$1" sid="$2" label="$3" base disallow in pid st off i s=""
  base="$(git -C "$LN_DIR" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"; base="${base#origin/}"; [ -n "$base" ] || base=main
  disallow="$LANE_DISALLOWED_FIXED,Bash(git push origin $base:*),Bash(git push origin HEAD:$base:*),Bash(git push origin HEAD:refs/heads/$base:*),Bash(git push -u origin $base:*)"
  local -a flags=(-p --input-format stream-json --output-format stream-json --verbose
    --permission-prompt-tool stdio --permission-mode acceptEdits
    --allowedTools "$LANE_ALLOWED_TOOLS" --disallowedTools "$disallow"
    --plugin-dir "$PLUGIN_ROOT" --append-system-prompt "$LANE_SYS")
  [ -n "$sid" ] && flags+=(--resume "$sid")
  in=/dev/null
  if [ -n "$prompt" ]; then
    in="$LN_ROOT/$LN_LANE.stdin.json"
    jq -n -c --arg c "$prompt" '{type: "user", message: {role: "user", content: $c}}' > "$in" || return 1
  fi
  touch "$LN_LOG"; rm -f "$LN_DIED"
  off="$(wc -c < "$LN_LOG" | tr -d ' ')"
  # >>> spawn (the only process start; it writes nothing into the lane directory)
  nohup bash "$SELF" _lane-run "$LN_DIR" "$LN_LOG" "$LN_DIED" "$in" -- \
    env -u CLAUDECODE -u CLAUDE_PID CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 claude "${flags[@]}" >> "$LN_LOG" 2>&1 &
  pid=$!
  # <<< spawn
  st="$(ps -o lstart= -p "$pid" 2>/dev/null | _trim_ws)"
  _lt_set "$LN_TABLE" "$LN_LANE" 5 "$pid" 6 "$st" 8 launched 9 "$(now_utc)" 10 -
  local w="${LOOMWRIGHT_LANES_INIT_WAIT_S:-15}"; case "$w" in ''|*[!0-9]*) w=15 ;; esac
  i=0
  while [ "$i" -lt $((w * 5)) ]; do
    s="$(tail -c +"$((off + 1))" "$LN_LOG" 2>/dev/null | grep '^{' | jq -r -R 'fromjson? | select(.type == "system" and .subtype == "init") | .session_id // empty' 2>/dev/null | head -1)"
    [ -n "$s" ] && break
    kill -0 "$pid" 2>/dev/null || { sleep 0.2; s="$(tail -c +"$((off + 1))" "$LN_LOG" 2>/dev/null | grep '^{' | jq -r -R 'fromjson? | select(.type == "system" and .subtype == "init") | .session_id // empty' 2>/dev/null | head -1)"; break; }
    sleep 0.2; i=$((i + 1))
  done
  [ -n "$s" ] && _lt_set "$LN_TABLE" "$LN_LANE" 7 "$s"
  echo "lane-launch: launched $LN_LANE (pid $pid, session ${s:-unknown}) $label"
}

# _lane-run <lane_dir> <log> <died> <stdin> -- <cmd...> — the nohup wrapper (its argv carries the lane dir).
lanes_run_wrapper() {
  local dir="$1" log="$2" died="$3" in="$4" off cp rc=0; shift 4; [ "${1:-}" = "--" ] && shift
  off="$(wc -c < "$log" 2>/dev/null | tr -d ' ')"; off="${off:-0}"
  cd "$dir" || exit 1
  "$@" < "$in" &
  cp=$!
  trap 'kill -TERM "$cp" 2>/dev/null' TERM INT HUP
  wait "$cp"; rc=$?
  while kill -0 "$cp" 2>/dev/null; do wait "$cp"; rc=$?; done
  if ! tail -c +"$((off + 1))" "$log" 2>/dev/null | grep -q '"type": *"result"'; then
    printf 'died_at\t%s\nexit\t%s\n' "$(now_utc)" "$rc" > "$died"
  fi
  exit "$rc"
}

# ==================================================================================================
# lane-launch <lane_dir> --owner-command '<cmd>' [--resume-run <run_id> | --continue] | --host-denied '<reason>'
lanes_launch() {
  local dir="" owner="" resume_run="" cont=0 denied="" denied_set=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --owner-command) owner="${2:-}"; shift 2 ;;
      --resume-run) resume_run="${2:-}"; [ -n "$resume_run" ] || die "lane-launch: --resume-run needs a run id"; shift 2 ;;
      --continue) cont=1; shift ;;
      --host-denied) denied="${2:-host denied the spawn}"; denied_set=1; shift 2 ;;
      *) [ -z "$dir" ] || die "lane-launch: unexpected argument '$1'"; dir="$1"; shift ;;
    esac
  done
  _lane_ctx "$dir" || die "lane-launch: not a lane (no valid .supervisor/lane.json): ${dir:-<none>}"
  if [ "$denied_set" = 1 ]; then
    echo "lane-launch: BLOCKED — $LN_LANE — $denied — need the owner"
    _lt_set "$LN_TABLE" "$LN_LANE" 8 blocked_launch 10 "$denied"; return 3
  fi
  local rc; _lanes_gate "$owner"; rc=$?; [ "$rc" = 0 ] || return "$rc"
  if [ -n "$resume_run" ]; then
    [ "$resume_run" = "$LN_RUN" ] || { echo "lane-launch: refused — $LN_LANE resumes only its own run ($LN_RUN), not '$resume_run'"; return 1; }
    [ -f "$LN_DIR/.supervisor/automate/$LN_RUN.md" ] || { echo "lane-launch: refused — no run file $LN_RUN.md in $LN_LANE"; return 1; }
    _lanes_spawn "/loomwright:automate --resume $LN_RUN" "" "(resume $LN_RUN)"
  elif [ "$cont" = 1 ]; then
    local sid; sid="$(_lanes_session_id)"
    [ -n "$sid" ] || { echo "lane-launch: refused — $LN_LANE has no recorded session to continue"; return 1; }
    _lanes_spawn "$LANE_CONTINUE_MSG" "$sid" "(continue)"
  else
    [ -s "$LN_DIR/.supervisor/lane-backlog.md" ] || { echo "lane-launch: refused — $LN_LANE has no backlog (setup incomplete)"; return 1; }
    jq -e '[.hooks.PreToolUse[]?.hooks[]?.command] | any(test("automate-lanes.sh\" relay-hook"))' \
      "$LN_DIR/.claude/settings.local.json" >/dev/null 2>&1 \
      || { echo "lane-launch: refused — $LN_LANE has no relay hook (a lane never runs without its question channel)"; return 1; }
    _lanes_spawn "/loomwright:automate --backlog $LN_DIR/.supervisor/lane-backlog.md" "" "(launch)"
  fi
}

# _lanes_session_id — the lane table's session id, else the newest `system/init` in the stream log.
_lanes_session_id() {
  local s; s="$(_lt_get "$LN_TABLE" "$LN_LANE" 7)"
  [ -n "$s" ] || s="$(grep '^{' "$LN_LOG" 2>/dev/null | jq -r -R 'fromjson? | select(.type == "system" and .subtype == "init") | .session_id // empty' 2>/dev/null | tail -1)"
  printf '%s' "$s"
}

_lanes_last_result() { grep '^{' "$1" 2>/dev/null | jq -c -R 'fromjson? | select(.type == "result")' 2>/dev/null | tail -1; }

# ==================================================================================================
# relay-hook — PreToolUse[AskUserQuestion]: answer recorded ⇒ allow + updatedInput, else record + defer.
#              PermissionRequest[AskUserQuestion] (bundled call, defer ignored) ⇒ deny with a re-ask.
lanes_relay_hook() {
  local in ev cwd root id q a
  in="$(cat)"
  ev="$(jq -r '.hook_event_name // empty' <<<"$in" 2>/dev/null)"
  if [ "$ev" = "PermissionRequest" ]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"AskUserQuestion must be the ONLY tool call in its turn (the answer is relayed to the owner). Call AskUserQuestion again, alone, in a turn of its own."}}}'
    return 0
  fi
  [ "$ev" = "PreToolUse" ] || { echo '{}'; return 0; }
  cwd="$(jq -r '.cwd // empty' <<<"$in" 2>/dev/null)"; [ -n "$cwd" ] || cwd="${CLAUDE_PROJECT_DIR:-$PWD}"
  root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"; [ -n "$root" ] || root="$cwd"
  [ -s "$root/.supervisor/lane.json" ] || { echo '{}'; return 0; }
  id="$(jq -r '.tool_use_id // empty' <<<"$in" 2>/dev/null)"
  case "$id" in ''|*[!A-Za-z0-9_-]*) echo '{}'; return 0 ;; esac
  q="$root/.supervisor/inbox/questions/$id.json"; a="$root/.supervisor/inbox/answers/$id.json"
  mkdir -p "$(dirname "$q")" "$(dirname "$a")" 2>/dev/null
  if [ -s "$a" ]; then
    jq -c --slurpfile ans "$a" '
      ($ans[0].answers) as $A | ($ans[0].note) as $N
      | {hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow",
          permissionDecisionReason: "answered by the owner via automate-lanes.sh lane-answer",
          updatedInput: ({questions: .tool_input.questions, answers: $A}
            + (if ($N // "") == "" then {} else {annotations: ($A | with_entries(.value = {notes: $N}))} end))}}' <<<"$in"
  else
    jq -c --arg at "$(now_utc)" '{id: .tool_use_id, asked_at: $at, questions: .tool_input.questions}' <<<"$in" > "$q.tmp.$$" \
      && mv "$q.tmp.$$" "$q"
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"defer"}}'
  fi
}

# ==================================================================================================
# lane-answer <lane_dir> <tool_use_id> --owner-command '<cmd>' [--via <client>]  (stdin: answers JSON)
lanes_answer() {
  local dir="" id="" owner="" via=cli
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --owner-command) owner="${2:-}"; shift 2 ;;
      --via) via="${2:-cli}"; shift 2 ;;
      *) if [ -z "$dir" ]; then dir="$1"; elif [ -z "$id" ]; then id="$1"; else die "lane-answer: unexpected argument '$1'"; fi; shift ;;
    esac
  done
  _lane_ctx "$dir" || die "lane-answer: not a lane: ${dir:-<none>}"
  case "$id" in ''|*[!A-Za-z0-9_-]*) die "lane-answer: bad tool_use_id '$id'" ;; esac
  local qf="$LN_INBOX/questions/$id.json" af="$LN_INBOX/answers/$id.json" last in out rc
  [ -s "$qf" ] || die "lane-answer: refused — no recorded question $id"
  [ -e "$af" ] && die "lane-answer: refused — $id already answered"
  last="$(_lanes_last_result "$LN_LOG")"
  [ "$(jq -r '.stop_reason // empty' <<<"$last" 2>/dev/null)" = "tool_deferred" ] || die "lane-answer: refused — $LN_LANE did not park on a question"
  [ "$(jq -r '.deferred_tool_use.id // empty' <<<"$last" 2>/dev/null)" = "$id" ] || die "lane-answer: refused — $LN_LANE is parked on another question"
  in="$(cat)"
  jq -e 'type == "object"' >/dev/null 2>&1 <<<"$in" || die "lane-answer: refused — answers are not a JSON object"
  out="$(jq -c --argjson in "$in" '.questions as $qs | ($qs | length) as $n
    | if ($in.answers | type) != "object" then error("an answer is one of the question'"'"'s own option labels per question (a note alone is never the decision)") else . end
    | if ([$in.answers | keys[]] | map(tonumber? // -1) | sort) != [range(0; $n)] then error("need exactly one answer for each of the \($n) question(s)") else . end
    | reduce range(0; $n) as $i ({}; ($in.answers[($i | tostring)]) as $a
        | [$qs[$i].options[].label] as $labels
        | (if ($a | type) != "string" then [] elif $qs[$i].multiSelect == true then ($a | split(",") | map(sub("^ +"; "") | sub(" +$"; ""))) else [$a] end) as $parts
        | if ($parts | length) == 0 or any($parts[]; . as $p | ($labels | index($p)) == null)
          then error("question \($i + 1): \"\($a)\" is not one of its options\(if $qs[$i].multiSelect == true then " (multiSelect: comma-joined labels)" else "" end)")
          else . end
        | . + {($qs[$i].question): ($parts | join(","))})' "$qf" 2>&1)" \
    || die "lane-answer: refused — $(sed -E 's/^jq: error \(at [^)]*\): //' <<<"$out")"
  # authority + admission BEFORE the answer is recorded, so a HELD resume leaves nothing half-written
  _lanes_gate "$owner"; rc=$?; [ "$rc" = 0 ] || return "$rc"
  local note; note="$(jq -r '.note // ""' <<<"$in")"
  jq -n --argjson a "$out" --arg note "$note" --arg via "$via" --arg at "$(now_utc)" \
    '{answers: $a, note: (if $note == "" then null else $note end), source: "human", via: $via, at: $at}' > "$af.tmp.$$" \
    && mv "$af.tmp.$$" "$af" || die "lane-answer: cannot write the answer file"
  local sid; sid="$(jq -r '.session_id // empty' <<<"$last")"; [ -n "$sid" ] || sid="$(_lanes_session_id)"
  [ -n "$sid" ] || die "lane-answer: refused — no session id to resume"
  [ -n "$note" ] && echo "lane-answer: note recorded and delivered to the lane as an annotation (never the decision)"
  _lanes_spawn "" "$sid" "(resume after answer $id via $via)"
}

# ==================================================================================================
# lane-remove <lane_dir> [--stop] [--abandon]
_lanes_stop_pid() { # <pid> <label> — TERM, then KILL after the grace period
  local p="$1" g="${LOOMWRIGHT_LANES_STOP_GRACE_S:-60}" i=0
  case "$g" in ''|*[!0-9]*) g=60 ;; esac
  kill -TERM "$p" 2>/dev/null
  while kill -0 "$p" 2>/dev/null && [ "$i" -lt $((g * 5)) ]; do sleep 0.2; i=$((i + 1)); done
  kill -0 "$p" 2>/dev/null && kill -KILL "$p" 2>/dev/null
  echo "lane-remove: stopped $2 (pid $p)"
}

lanes_remove() {
  local dir="" stop=0 abandon=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --stop) stop=1; shift ;;
      --abandon) abandon=1; shift ;;
      *) [ -z "$dir" ] || die "lane-remove: unexpected argument '$1'"; dir="$1"; shift ;;
    esac
  done
  _lane_ctx "$dir" || die "lane-remove: not a lane: ${dir:-<none>}"
  local L="$LN_LANE" pid st m mp mu q state rf b u mb ms
  _refuse() { echo "lane-remove: refused — $L — $1"; return 1; }
  # >>> live-process check
  pid="$(_lt_get "$LN_TABLE" "$L" 5)"; st="$(_lt_get "$LN_TABLE" "$L" 6)"
  if lanes_proc_alive "$pid" "$st" "$LN_DIR"; then
    if [ "$stop" = 1 ]; then _lanes_stop_pid "$pid" "claude -p"; else _refuse "live claude -p process (pid $pid); use --stop"; return 1; fi
  fi
  # <<< live-process check
  for m in "$LN_DIR"/.supervisor/automate/*.merge-watch; do
    [ -f "$m" ] || continue
    mp="$(awk -F'\t' '$1 == "pid" { print $2 }' "$m")"; mu="$(awk -F'\t' '$1 == "pr_url" { print $2 }' "$m")"
    case "$mp" in ''|*[!0-9]*) continue ;; esac
    case "$(ps -ww -o command= -p "$mp" 2>/dev/null)" in
      *automate-merge-watch*"$mu"*)
        if [ "$stop" = 1 ]; then _lanes_stop_pid "$mp" "merge watcher"; else _refuse "live merge watcher (pid $mp, $mu); use --stop"; return 1; fi ;;
    esac
  done
  # >>> awaiting-input check
  rf="$LN_DIR/.supervisor/automate/$LN_RUN.md"
  if q="$(_lanes_pending_question "$LN_INBOX")"; then _refuse "awaiting_input — unanswered question $q"; return 1; fi
  if [ -f "$rf" ] && grep -q 'pause_reason: *awaiting_input' "$rf"; then _refuse "awaiting_input — run file is parked on a question"; return 1; fi
  if [ "$(jq -r '.stop_reason // empty' <<<"$(_lanes_last_result "$LN_LOG")" 2>/dev/null)" = "tool_deferred" ]; then
    q="$(jq -r '.deferred_tool_use.id // empty' <<<"$(_lanes_last_result "$LN_LOG")")"
    [ -e "$LN_INBOX/answers/$q.json" ] || { _refuse "awaiting_input — deferred tool call $q"; return 1; }
  fi
  # <<< awaiting-input check
  state="$(_lt_get "$LN_TABLE" "$L" 8)"
  if [ "$abandon" = 0 ]; then
    if [ "$state" = gone ] || { [ -f "$rf" ] && grep -qE '(status|pause_reason): *gone' "$rf"; }; then
      _refuse "gone (PR closed unmerged) — a human runs lane-remove --abandon"; return 1
    fi
  fi
  [ -z "$(git -C "$LN_DIR" status --porcelain 2>/dev/null)" ] || { _refuse "dirty working tree"; return 1; }
  [ -e "$LN_DIR/.supervisor/automate/$LN_RUN.meta-push-failed" ] && { _refuse "meta-push failure marker is set"; return 1; }
  if ! mb="$(_lanes_meta_branch "$LN_DIR")"; then _refuse "metadata mode unknown (cannot prove the metadata was pushed)"; return 1; fi
  if [ -n "$mb" ]; then
    ms="$(bash "$META_SYNC" status --branch "$mb" --root "$LN_DIR" 2>/dev/null)" || { _refuse "metadata status unreadable"; return 1; }
    case "$ms" in local_ahead*|conflict*|*local_ahead*|*conflict*) _refuse "metadata not pushed ($ms)"; return 1 ;; esac
  fi
  for b in $(git -C "$LN_DIR" for-each-ref --format='%(refname:short)' refs/heads); do
    u="$(git -C "$LN_DIR" rev-list --count "$b" --not --remotes=origin 2>/dev/null)"
    [ "${u:-0}" -gt 0 ] && { _refuse "branch $b has $u commit(s) not on origin"; return 1; }
  done
  local sv; sv="$(_lanes_salvage "$LN_DIR" "$LN_ROOT/salvage" "$L-removed")" || { _refuse "salvage failed"; return 1; }
  rm -rf "$LN_DIR" || { echo "lane-remove: could not remove $LN_DIR" >&2; return 1; }
  _lt_set "$LN_TABLE" "$L" 8 "$([ "$abandon" = 1 ] && echo abandoned || echo removed)"
  if [ "$abandon" = 1 ]; then
    bash "$HELPERS" progress-append "$LN_PRIMARY/.supervisor/automate/$LN_PARENT.md" \
      "lane abandoned: $L ($LN_RUN) — state ${state:-unknown}; salvaged to $sv" >/dev/null 2>&1 || true
  fi
  echo "lane-remove: removed $L ($LN_DIR); salvage $sv"
}

# ==================================================================================================
# lane-info [--root <dir>]
lanes_info() {
  local root=""
  [ "${1:-}" = "--root" ] && { root="${2:-}"; [ -n "$root" ] || die "lane-info: --root needs a directory"; }
  [ -n "$root" ] || root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  local j="$root/.supervisor/lane.json"
  if [ -s "$j" ] && jq -e '.schema_version == 1 and (.run_id | type == "string")' "$j" >/dev/null 2>&1; then cat "$j"; return 0; fi
  echo "lane-info: not a lane (no valid .supervisor/lane.json under $root)" >&2
  return 1
}

# init-check --parallel N [--auto-merge]
lanes_init_check() {
  local n="" am=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --parallel) n="${2:-}"; shift 2 ;;
      --auto-merge) am=1; shift ;;
      *) echo "refuse: unknown_argument $1"; return 1 ;;
    esac
  done
  case "$n" in ''|*[!0-9]*) echo "refuse: parallel_out_of_range"; return 1 ;; esac
  n=$((10#$n))
  if [ "$n" -lt 1 ] || [ "$n" -gt 10 ]; then echo "refuse: parallel_out_of_range"; return 1; fi
  if [ "$n" -gt 1 ] && [ "$am" = 1 ]; then echo "refuse: auto_merge_with_parallel"; return 1; fi
  echo ok
}

# pick-guard <automate_dir> — a lane is live when its process is (lanes_proc_alive) or it holds an
# unanswered question (a deferred session is a lane mid-flight). The run lock alone is reclaimable.
lanes_pick_guard() {
  local d="${1:-}" t lane path run pid st
  [ -n "$d" ] && [ -d "$d" ] || { echo "refuse: automate_dir_missing ${d:-<none>}"; return 1; }
  for t in "$d"/*.lanes; do
    [ -f "$t" ] || continue
    while IFS="$(printf '\t')" read -r lane path _ run pid st _; do
      case "$lane" in L[0-9]*) ;; *) continue ;; esac
      if lanes_proc_alive "$pid" "$st" "$path" || { [ -d "$path/.supervisor/inbox" ] && _lanes_pending_question "$path/.supervisor/inbox" >/dev/null; }; then
        echo "refuse: live_lane $run $lane"; return 1
      fi
    done < "$t"
  done
  echo ok
}

# branch-check <lane_dir> <branch> — prints the branch name to use; a remote hit ⇒ `<branch>-L<n>`;
# both taken ⇒ `refuse: remote_branch_exists <branch>` (exit 1). Never a force push.
lanes_branch_check() {
  local dir="${1:-}" b="${2:-}" hit
  _lane_ctx "$dir" || die "branch-check: not a lane: ${dir:-<none>}"
  [ -n "$b" ] || die "branch-check: usage: branch-check <lane_dir> <branch>"
  hit="$(git -C "$LN_DIR" ls-remote --heads origin "$b" 2>/dev/null)" || { echo "refuse: remote_unreachable $b"; return 1; }
  [ -z "$hit" ] && { echo "$b"; return 0; }
  hit="$(git -C "$LN_DIR" ls-remote --heads origin "$b-$LN_LANE" 2>/dev/null)" || { echo "refuse: remote_unreachable $b"; return 1; }
  [ -z "$hit" ] && { echo "$b-$LN_LANE"; return 0; }
  echo "refuse: remote_branch_exists $b"; return 1
}

# ==================================================================================================
# OBSERVATION — lane-status, lane-feed, lane-readiness, lane-status --leaks. Every reader fails SAFE:
# an absent or unreadable source prints `unknown` and the command exits 0. Nothing here starts, stops
# or kills a lane; the only process it may start is the opt-in `--keep-awake` holder.
LANES_GH="${LOOMWRIGHT_GH_BIN:-gh}"

_lanes_dash() { case "${1:-}" in -|null) ;; *) printf '%s' "${1:-}" ;; esac; }

_lanes_epoch() { # <UTC ISO 8601> — epoch seconds; returns 1 when unparseable
  local e; e="$(jq -n --arg t "${1:-}" '$t | fromdateiso8601' 2>/dev/null)"
  case "$e" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$e"
}

_lanes_boot_epoch() { # machine boot time (epoch); returns 1 when unknown
  local b="${LOOMWRIGHT_LANES_BOOT_EPOCH:-}"
  if [ -z "$b" ]; then
    case "$(uname -s 2>/dev/null)" in
      Darwin) b="$(sysctl -n kern.boottime 2>/dev/null | sed -n 's/^{ *sec = \([0-9][0-9]*\).*/\1/p' | head -1)" ;;
      *) b="$(awk '$1 == "btime" { print $2 }' /proc/stat 2>/dev/null | head -1)" ;;
    esac
  fi
  case "$b" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$b"
}

# _lanes_runfile_fields <runfile> — status<TAB>pause_reason<TAB>pr<TAB>last_progress<TAB>pending_decisions
# (`-` for each value that is absent; the whole line is `-`s when the run file is absent).
_lanes_runfile_fields() {
  [ -f "${1:-}" ] || { printf -- '-\t-\t-\t-\t-'; return 0; }
  awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function d(s) { return (s == "" ? "-" : s) }
    /^## / { sec = $0; next }
    sec == "## Current" && /^- item:/ {
      n = split($0, a, / \| /)
      for (i = 1; i <= n; i++) { kv = a[i]; sub(/^- /, "", kv); k = kv; sub(/:.*/, "", k); v = kv; sub(/^[^:]*: */, "", v)
        if (k == "status") st = trim(v); else if (k == "pr") pr = trim(v) } }
    sec == "## Current" && /^- pause_reason:/ { v = $0; sub(/^- pause_reason: */, "", v); sub(/ \|.*/, "", v); pa = trim(v) }
    sec == "## Current" && /pending_decisions:/ { v = $0; sub(/.*pending_decisions: */, "", v); sub(/[ |].*/, "", v); pd = v }
    sec == "## Progress" && /^- / { lp = substr($0, 3); gsub(/\t/, " ", lp) }
    END { printf "%s\t%s\t%s\t%s\t%s", d(st), d(pa), d(pr), d(lp), d(pd) }' "$1" 2>/dev/null | tr -d '\r'
}

# _lanes_parked <status> <pause_reason> — prints the park reason; returns 1 when the run is not parked.
_lanes_parked() {
  case "${2:-}" in -|null|'') ;; *) printf '%s' "$2"; return 0 ;; esac
  case "${1:-}" in awaiting_merge|ready_for_release|escalated|failed|rate_limit|drain_died|done|gone) printf '%s' "$1"; return 0 ;; esac
  return 1
}

# _lanes_last_message <stream_log> — the most recent assistant TEXT (never a tool-use line), ≤300 chars.
_lanes_last_message() {
  grep '^{' "$1" 2>/dev/null | jq -r -R 'fromjson? | select(.type == "assistant")
    | [.message.content[]? | select(.type == "text") | .text] | join(" ")
    | gsub("[\\r\\n\\t]+"; " ") | gsub("^ +| +$"; "") | select(length > 0) | .[0:300]' 2>/dev/null | tail -1
}

# _lanes_last_actions <stream_log> — the last 3 tool calls, one per line.
_lanes_last_actions() {
  grep '^{' "$1" 2>/dev/null | jq -r -R 'fromjson? | select(.type == "assistant") | .message.content[]?
    | select(.type == "tool_use")
    | (.name + " " + ((.input.command // .input.description // .input.file_path // .input.pattern // "") | tostring
        | gsub("[\\r\\n\\t]+"; " ") | .[0:80])) | gsub(" +$"; "")' 2>/dev/null | tail -3
}

# _lanes_questions_json <inbox> <now_epoch> — JSON array of unanswered questions (asked_at, waiting_s).
_lanes_questions_json() {
  local q id at e w out="[]" nx
  for q in "$1"/questions/*.json; do
    [ -f "$q" ] || continue
    id="$(basename "$q" .json)"
    [ -e "$1/answers/$id.json" ] && continue
    at="$(jq -r '.asked_at // empty' "$q" 2>/dev/null)"
    w=null; if e="$(_lanes_epoch "$at")"; then w=$(( $2 - e )); fi
    nx="$(jq -c --slurpfile Q "$q" --arg id "$id" --arg at "$at" --argjson w "$w" \
      '. + [{id: $id, asked_at: (if $at == "" then null else $at end), waiting_s: $w,
             question: (($Q[0].questions // [])[0].question // null)}]' <<<"$out" 2>/dev/null)" \
      || nx="$(jq -c --arg id "$id" '. + [{id: $id, asked_at: null, waiting_s: null, question: null}]' <<<"$out")"
    out="$nx"
  done
  printf '%s' "$out"
}

_lanes_keep_awake_state() {
  if "${LOOMWRIGHT_LANES_PGREP:-pgrep}" -x caffeinate >/dev/null 2>&1; then printf 'held'; else printf 'not held'; fi
}

# _lanes_coordinator_pid — LOOMWRIGHT_LANES_COORDINATOR_PID, else the nearest `claude` ancestor, else $PPID.
_lanes_coordinator_pid() {
  local p="${LOOMWRIGHT_LANES_COORDINATOR_PID:-}" i=0 c
  case "$p" in ''|*[!0-9]*) ;; *) printf '%s' "$p"; return 0 ;; esac
  p="$PPID"
  while [ "$i" -lt 12 ]; do
    case "$p" in ''|*[!0-9]*|0|1) break ;; esac
    c="$(ps -o comm= -p "$p" 2>/dev/null)"
    case "${c##*/}" in claude) printf '%s' "$p"; return 0 ;; esac
    p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"; i=$((i + 1))
  done
  printf '%s' "$PPID"
}

# _lanes_keep_awake_hint — the macOS suggestion (the owner runs it); nothing on other OSes.
_lanes_keep_awake_hint() {
  case "${LOOMWRIGHT_LANES_UNAME:-$(uname -s 2>/dev/null)}" in
    Darwin) printf 'caffeinate -i -w %s' "$(_lanes_coordinator_pid)" ;;
  esac
}

# _lanes_keep_awake_start — `--keep-awake` opt-in ONLY: starts the holder tied to the coordinator pid.
_lanes_keep_awake_start() {
  local cf="${LOOMWRIGHT_LANES_CAFFEINATE:-caffeinate}" cp hp
  case "${LOOMWRIGHT_LANES_UNAME:-$(uname -s 2>/dev/null)}" in
    Darwin) ;;
    *) echo "keep-awake: not started — no keep-awake holder known on this OS"; return 0 ;;
  esac
  [ "$(_lanes_keep_awake_state)" = held ] && { echo "keep-awake: already held"; return 0; }
  cp="$(_lanes_coordinator_pid)"
  nohup "$cf" -i -w "$cp" >/dev/null 2>&1 &
  hp=$!
  echo "keep-awake: started (opt-in --keep-awake) — $cf -i -w $cp (pid $hp); it ends with the coordinator"
}

# _lanes_machine_json — {state, load1, cpus, mem_pressure, keep_awake}; `unknown` when the reader is
# absent or unreadable (never an error).
_lanes_machine_json() {
  local cmd="${LOOMWRIGHT_MACHINE_LOAD_CMD:-$HERE/machine-load.sh}" j="" ka
  ka="$(_lanes_keep_awake_state)"
  [ -f "$cmd" ] && j="$(bash "$cmd" --json 2>/dev/null | jq -c 'select(type == "object")' 2>/dev/null | head -1)"
  [ -n "$j" ] || j='{}'
  jq -c --arg ka "$ka" '{state: ((.state // "unknown") | tostring), load1: (.load1 // "unknown"),
    cpus: (.cpus // "unknown"), mem_pressure: (.mem_pressure // "unknown"), keep_awake: $ka}' <<<"$j" 2>/dev/null \
    || printf '{"state":"unknown","load1":"unknown","cpus":"unknown","mem_pressure":"unknown","keep_awake":"%s"}' "$ka"
}

_lanes_ci_json() { # `ci-slot.sh status --json`, or nothing
  local c="${LOOMWRIGHT_LANES_CI_SLOT:-$HERE/ci-slot.sh}"
  [ -f "$c" ] || return 0
  bash "$c" status --json 2>/dev/null | jq -c 'select(type == "object")' 2>/dev/null | head -1
}

# _lanes_table_for [<parent_runfile>|<table>] — the D6 lane table; returns 1 when none.
_lanes_table_for() {
  local rf="${1:-}" top t
  if [ -n "$rf" ]; then
    case "$rf" in *.lanes) t="$rf" ;; *) t="${rf%.md}.lanes" ;; esac
    [ -f "$t" ] && { printf '%s' "$t"; return 0; }
    return 1
  fi
  top="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  t="$(ls -t "$top"/.supervisor/automate/*.lanes 2>/dev/null | head -1)"
  [ -n "$t" ] && [ -f "$t" ] && { printf '%s' "$t"; return 0; }
  return 1
}

# _lanes_resolve <lane_dir|L<n>> — a lane directory (L<n> through the newest lane table).
_lanes_resolve() {
  case "${1:-}" in
    L[0-9]|L[0-9][0-9])
      local t; t="$(_lanes_table_for "")" || return 1
      awk -F'\t' -v l="$1" '$1 == l { p = $2 } END { if (p != "") print p }' "$t" ;;
    *) printf '%s' "${1:-}" ;;
  esac
}

# _lanes_lane_json <10 lane-table columns> <now_epoch> <ci_json> — one lane's status object.
# Classification order (first match wins): removed/abandoned · blocked_launch · held_for_load · created
# · missing · running (lanes_proc_alive) · awaiting_input · parked (merged / gone after reconcile) ·
# lost_to_reset (boot later than the last launch) · died (.died marker) · stalled.
_lanes_lane_json() {
  local lane="$1" path="$2" item="$3" run="$4" pid="$5" st="$6" sid="$7" ts="$8" llu="$9" why="${10}" now="${11}" ci="${12}"
  local root log died rf status pause pr lp pd state reason="" held="" qs nq pk prs="" le be rdf rds="" rdsum="" lm la cij
  root="$(dirname "$path")"; log="$root/$lane.stream.log"; died="$root/$lane.died"
  rf="$path/.supervisor/automate/$run.md"
  IFS="$(printf '\t')" read -r status pause pr lp pd <<<"$(_lanes_runfile_fields "$rf")"
  qs="$(_lanes_questions_json "$path/.supervisor/inbox" "$now")"; nq="$(jq 'length' <<<"$qs" 2>/dev/null)"; nq="${nq:-0}"
  cij='{"state":"unknown","position":null,"held":null}'
  if [ -n "$ci" ]; then
    cij="$(jq -c --arg d "$path" 'def m: ((.checkout // "") as $c | ($c == $d or ($c | startswith($d + "/"))));
      if ((.holders // []) | any(m)) then {state: "holding", position: null, held: null}
      else ([(.waiters // []) | to_entries[] | select(.value | m)] | first) as $w
        | if $w == null then {state: "none", position: null, held: null}
          else {state: "waiting", position: ($w.key + 1), held: $w.value.held} end end' <<<"$ci" 2>/dev/null)" \
      || cij='{"state":"unknown","position":null,"held":null}'
  fi
  case "$ts" in
    removed|abandoned) state="$ts" ;;
    blocked_launch) state=blocked_launch; reason="$(_lanes_dash "$why")" ;;
    held_for_load) state=held_for_load; reason="held for load: $(_lanes_dash "$why")"; held="$(_lanes_dash "$why")" ;;
    created) state=created; reason="not launched" ;;
    *)
      if [ ! -d "$path" ]; then state=missing; reason="lane directory vanished"
      elif lanes_proc_alive "$pid" "$st" "$path"; then
        state=running
        held="$(jq -r '.held // empty' <<<"$cij" 2>/dev/null)"
        if [ "$(jq -r .state <<<"$cij")" = waiting ]; then reason="waiting for a CI slot — position $(jq -r .position <<<"$cij")"; fi
        [ -n "$held" ] && reason="${reason:+$reason; }held for load: $held"
      elif [ "$nq" -gt 0 ]; then state=awaiting_input; reason="question $(jq -r '.[0].id' <<<"$qs")"
      elif pk="$(_lanes_parked "$status" "$pause")"; then
        state="$pk"
        if [ -n "$(_lanes_dash "$pr")" ]; then
          case "$pk" in
            awaiting_merge|ready_for_release)
              prs="$(bash "$HELPERS" reconcile-item "$pr" "$pk" 2>/dev/null | head -1)"
              case "$prs" in merged) state=merged ;; gone) state=gone; reason="PR closed unmerged" ;; awaiting_merge) ;; *) prs="" ;; esac ;;
          esac
        fi
      elif be="$(_lanes_boot_epoch)" && le="$(_lanes_epoch "$(_lanes_dash "$llu")")" && [ "$be" -gt "$le" ]; then
        state=lost_to_reset; reason="machine booted after the last launch ($llu); resume with lane-launch --resume-run $run"
      elif [ -e "$died" ]; then
        state=died; reason="process exited with no terminal result ($(awk -F'\t' '$1 == "died_at" { print $2 }' "$died" 2>/dev/null))"
      else
        state=stalled; reason="process gone, run file not parked, no pending question — resume once with lane-launch --continue"
      fi ;;
  esac
  rdf="$path/.supervisor/automate/$run.merge-readiness.md"
  if [ -f "$rdf" ]; then
    rds="$(sed -n 's/^- score: \([0-9]*\/[0-9]*\).*/\1/p' "$rdf" | head -1)"
    rdsum="$(sed -n 's/^- score: .* | summary: //p' "$rdf" | head -1)"
  fi
  lm="$(_lanes_last_message "$log")"; la="$(_lanes_last_actions "$log")"
  jq -n -c --arg lane "$lane" --arg path "$path" --arg item "$(_lanes_dash "$item")" --arg run "$run" \
    --arg state "$state" --arg reason "$reason" --arg pid "$(_lanes_dash "$pid")" --arg sid "$(_lanes_dash "$sid")" \
    --arg llu "$(_lanes_dash "$llu")" --arg status "$(_lanes_dash "$status")" --arg pause "$(_lanes_dash "$pause")" \
    --arg pr "$(_lanes_dash "$pr")" --arg prs "$prs" --arg lp "$(_lanes_dash "$lp")" --arg lm "$lm" --arg la "$la" \
    --argjson qs "$qs" --argjson ci "$cij" --arg held "$held" --arg rdf "$rdf" --arg rds "$rds" --arg rdsum "$rdsum" \
    'def n: if . == "" then null else . end;
     {lane: $lane, path: $path, item: $item, run_id: $run, state: $state, reason: $reason, pid: ($pid | n),
      session_id: ($sid | n), last_launch_utc: ($llu | n), run_status: ($status | n), pause_reason: ($pause | n),
      pr: ($pr | n), pr_state: ($prs | n), last_progress: $lp, last_actions: ($la | split("\n") | map(select(. != ""))),
      last_message: $lm, questions: $qs, ci_slot: $ci, held_for_load: ($held | n),
      readiness: (if $rds == "" then null else {score: $rds, summary: $rdsum, file: $rdf} end)}'
}

# _lanes_status_doc <table> <parent> <primary> — the full lane-status JSON document.
_lanes_status_doc() {
  local table="$1" parent="$2" primary="$3" now ci m hint lanes="" row tab
  tab="$(printf '\t')"; now="$(date -u +%s)"; ci="$(_lanes_ci_json)"; m="$(_lanes_machine_json)"; hint="$(_lanes_keep_awake_hint)"
  local lane path item run pid st sid ts llu why
  while IFS="$tab" read -r lane path item run pid st sid ts llu why; do
    case "$lane" in L[0-9]|L[0-9][0-9]) ;; *) continue ;; esac
    row="$(_lanes_lane_json "$lane" "$path" "$item" "$run" "$pid" "$st" "$sid" "$ts" "$llu" "${why:--}" "$now" "$ci")" || continue
    lanes="$lanes$row
"
  done < "$table"
  printf '%s' "$lanes" | jq -s -c --arg parent "$parent" --arg primary "$primary" --arg at "$(now_utc)" --argjson m "$m" \
    --arg hint "$hint" --arg mp "$([ -e "$primary/.supervisor/automate/$parent.memory-pressure" ] && echo true || echo false)" \
    '{schema_version: 1, parent_run_id: $parent, primary: $primary, generated_at: $at, machine: $m,
      memory_pressure: ($mp == "true"), keep_awake_suggestion: (if $hint == "" then null else $hint end), lanes: .}'
}

_lanes_render() { # <status JSON> — the plain view
  jq -r '"lane-status: \(.parent_run_id) — \(.lanes | length) lane(s) — \(.generated_at)",
    (.lanes[] | "\(.lane)  \(.state)\(if .reason != "" then " (" + .reason + ")" else "" end)  item=\(.item)  pr=\(.pr // "-")  path=\(.path)",
      (if .last_progress != "" then "    progress: \(.last_progress)" else empty end),
      (if (.last_actions | length) > 0 then "    actions: \(.last_actions | join("; "))" else empty end),
      (.questions[] | "    question: \(.id) asked_at=\(.asked_at // "unknown") waiting_s=\(.waiting_s // "unknown") — \(.question // "")"),
      (if .ci_slot.state == "waiting" then "    ci-slot: waiting — position \(.ci_slot.position)"
       elif .ci_slot.state == "holding" then "    ci-slot: holding a slot" else empty end),
      (if .held_for_load != null then "    held for load: \(.held_for_load)" else empty end),
      (if .readiness != null then "    readiness: \(.readiness.summary)" else empty end),
      (if .last_message != "" then "    last: \(.last_message)" else empty end)),
    "machine: state=\(.machine.state) load1=\(.machine.load1) cpus=\(.machine.cpus) mem_pressure=\(.machine.mem_pressure)\(if .memory_pressure then " — memory_pressure: new launches held" else "" end)",
    "keep-awake: \(.machine.keep_awake)",
    (if .keep_awake_suggestion != null and .machine.keep_awake != "held"
     then "keep-awake suggestion (run it yourself): \(.keep_awake_suggestion) — a closed lid still sleeps" else empty end)' <<<"$1"
}

# _lanes_resources <primary> <parent> — the latest fleet.log line per lane plus the wave's peak.
_lanes_resources() {
  local f="$1/.supervisor/automate/$2.fleet.log" last
  [ -s "$f" ] || { echo "resources: unknown — no fleet.log ($f)"; return 0; }
  last="$(tail -1 "$f")"
  printf '%s\n' "$last" | awk '{
      printf "resources: latest %s\n", $1; m = ""
      for (i = 2; i <= NF; i++) { k = $i; sub(/=.*/, "", k)
        if (k ~ /(^|[_.])L[0-9]+([_.]|$)/) { match(k, /L[0-9]+/); l = substr(k, RSTART, RLENGTH)
          if (!(l in seen)) { seen[l] = 1; order[++n] = l }; lines[l] = lines[l] " " $i }
        else m = m " " $i }
      printf "machine:%s\n", (m == "" ? " unknown" : m)
      for (j = 1; j <= n; j++) printf "%s:%s\n", order[j], lines[order[j]] }'
  awk '{ for (i = 2; i <= NF; i++) { k = $i; v = $i; sub(/=.*/, "", k); sub(/^[^=]*=/, "", v)
          if (v ~ /^[0-9]+(\.[0-9]+)?/ && (!(k in pk) || v + 0 > pk[k] + 0)) { if (!(k in pk)) ord[++n] = k; pk[k] = v } } }
       END { printf "peak:"; for (j = 1; j <= n; j++) printf " %s=%s", ord[j], pk[ord[j]]; print "" }' "$f"
}

# _lanes_tokens <table> <primary> <parent> — per-lane and parent token totals (read-token-ledger.sh).
_lanes_tokens() {
  local rtl="${LOOMWRIGHT_LANES_TOKEN_LEDGER:-$HERE/read-token-ledger.sh}" tab lane path run out all="" po
  [ -f "$rtl" ] || { echo "tokens: unknown — read-token-ledger.sh absent"; return 0; }
  tab="$(printf '\t')"
  while IFS="$tab" read -r lane path _ run _; do
    case "$lane" in L[0-9]|L[0-9][0-9]) ;; *) continue ;; esac
    if [ -d "$path" ]; then out="$(bash "$rtl" --run-id "$run" --root "$path" 2>/dev/null | head -1)"; else out=""; fi
    echo "$lane ${out:-unknown}"
    [ -n "$out" ] && all="$all$out
"
  done < "$1"
  po="$(bash "$rtl" --run-id "$3" --root "$2" 2>/dev/null | head -1)"
  echo "parent ${po:-unknown}"
  printf '%s%s\n' "$all" "$po" | awk '{ for (i = 1; i <= NF; i++) { k = $i; v = $i; sub(/=.*/, "", k); sub(/^[^=]*=/, "", v)
      if (k == "LEDGER_UNREADABLE") u = 1; else if (v ~ /^[0-9]+$/) { if (!(k in s)) o[++n] = k; s[k] += v } } }
    END { printf "total (parent + lanes):"; for (j = 1; j <= n; j++) printf " %s=%s", o[j], s[o[j]]; if (u) printf " LEDGER_UNREADABLE=1"; print "" }'
}

# ---- leak check (Validation 5) ----------------------------------------------------------------------
_lanes_leak_sections() { # <primary>
  local p="$1" pg="${LOOMWRIGHT_LANES_PGREP:-pgrep}"
  echo "## worktrees"; git -C "$p" worktree list --porcelain 2>/dev/null | awk '/^worktree /'
  echo "## lanes-dir"; ls -1 "$p-lanes" 2>/dev/null
  echo "## claude-p"; "$pg" -lf 'claude -p' 2>/dev/null
  echo "## merge-watch"; "$pg" -lf automate-merge-watch 2>/dev/null
  echo "## config-checksum"
  if [ -f "$p/.supervisor/config.json" ]; then cksum < "$p/.supervisor/config.json" | awk '{ print $1, $2 }'; else echo absent; fi
  echo "## git-status"; git -C "$p" status --porcelain 2>/dev/null | awk '!/\.leaks-snapshot$/'
  return 0
}

# lanes_leaks <primary> <parent> [snapshot 0|1] — `--snapshot` records the wave-start state; otherwise
# compares now against it. First line: `leaks: none` | `leaks: found — <sections>` | `leaks: unknown — …`.
lanes_leaks() {
  local p="$1" parent="$2" snap="${3:-0}" sf tmp sec found="" body="" d
  sf="$p/.supervisor/automate/$parent.leaks-snapshot"
  if [ "$snap" = 1 ]; then
    if { echo "# leaks snapshot $(now_utc)"; _lanes_leak_sections "$p"; } > "$sf.tmp.$$" 2>/dev/null && mv "$sf.tmp.$$" "$sf"; then
      echo "leaks: snapshot written — $sf"
    else rm -f "$sf.tmp.$$"; echo "leaks: snapshot not written (unwritable) — $sf"; fi
    return 0
  fi
  if [ ! -f "$sf" ]; then
    echo "leaks: unknown — no snapshot (take one at wave start: lane-status --leaks --snapshot)"
    _lanes_leak_sections "$p" | sed 's/^/  /'; return 0
  fi
  tmp="$(mktemp -d 2>/dev/null)" || { echo "leaks: unknown — no temp dir"; return 0; }
  _lanes_leak_sections "$p" > "$tmp/now"
  for sec in worktrees lanes-dir claude-p merge-watch config-checksum git-status; do
    awk -v s="## $sec" '/^## / { on = ($0 == s); next } on' "$sf" | env LC_ALL=C sort > "$tmp/a"
    awk -v s="## $sec" '/^## / { on = ($0 == s); next } on' "$tmp/now" | env LC_ALL=C sort > "$tmp/b"
    if cmp -s "$tmp/a" "$tmp/b"; then body="$body- $sec: same
"
    else
      found="$found${found:+, }$sec"
      d="$(env LC_ALL=C comm -13 "$tmp/a" "$tmp/b" | sed 's/^/  + /'; env LC_ALL=C comm -23 "$tmp/a" "$tmp/b" | sed 's/^/  - /')"
      body="$body- $sec: changed
$d
"
    fi
  done
  rm -rf "$tmp"
  if [ -z "$found" ]; then echo "leaks: none (vs snapshot $sf)"; else echo "leaks: found — $found"; fi
  printf '%s' "$body"
  return 0
}

# ==================================================================================================
# lane-status [<parent_runfile>] [--json] [--watch] [--leaks [--snapshot]] [--resources] [--tokens]
#             [--refresh-readiness] [--keep-awake]
lanes_status() {
  local rf="" json=0 watch=0 leaks=0 snap=0 res=0 tok=0 ka=0 refresh=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --json) json=1 ;; --watch) watch=1 ;; --leaks) leaks=1 ;; --snapshot) leaks=1; snap=1 ;;
      --resources) res=1 ;; --tokens) tok=1 ;; --keep-awake) ka=1 ;; --refresh-readiness) refresh=1 ;;
      -*) echo "lane-status: unknown flag '$1'" >&2; return 2 ;;
      *) [ -z "$rf" ] || { echo "lane-status: unexpected argument '$1'" >&2; return 2; }; rf="$1" ;;
    esac
    shift
  done
  if [ "$watch" = 1 ]; then _lanes_watch "$rf"; return 0; fi
  local table parent primary doc tab lane path ts
  if ! table="$(_lanes_table_for "$rf")"; then
    if [ "$json" = 1 ]; then
      jq -n -c --argjson m "$(_lanes_machine_json)" '{schema_version: 1, parent_run_id: null, machine: $m, lanes: []}'
    else echo "lane-status: no lane table (${rf:-none found}) — no lanes"; fi
    return 0
  fi
  parent="$(basename "$table" .lanes)"; primary="$(cd "$(dirname "$table")/../.." && pwd -P)"
  [ "$leaks" = 1 ] && { lanes_leaks "$primary" "$parent" "$snap"; return 0; }
  [ "$res" = 1 ] && { _lanes_resources "$primary" "$parent"; return 0; }
  [ "$tok" = 1 ] && { _lanes_tokens "$table" "$primary" "$parent"; return 0; }
  [ "$ka" = 1 ] && _lanes_keep_awake_start
  if [ "$refresh" = 1 ]; then
    tab="$(printf '\t')"
    while IFS="$tab" read -r lane path _; do
      case "$lane" in L[0-9]|L[0-9][0-9]) ;; *) continue ;; esac
      [ -d "$path" ] && _lane_ctx "$path" || continue
      ts="$(_lanes_runfile_fields "$path/.supervisor/automate/$LN_RUN.md" | cut -f1-2)"
      case "$ts" in *ready_for_release*|*awaiting_merge*) lanes_readiness "$path" >/dev/null ;; esac
    done < "$table"
  fi
  doc="$(_lanes_status_doc "$table" "$parent" "$primary")"
  if [ -z "$doc" ]; then echo "lane-status: unknown — status unreadable"; return 0; fi
  if [ "$json" = 1 ]; then printf '%s\n' "$doc"; else _lanes_render "$doc"; fi
  return 0
}

# _lanes_watch [<parent_runfile>] — the plain view every LOOMWRIGHT_LANES_WATCH_INTERVAL_S (default 15)
# seconds; LOOMWRIGHT_LANES_WATCH_ITERATIONS (default 0 = until interrupted) is the test seam.
_lanes_watch() {
  local n="${LOOMWRIGHT_LANES_WATCH_ITERATIONS:-0}" iv="${LOOMWRIGHT_LANES_WATCH_INTERVAL_S:-15}" i=0
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  case "$iv" in ''|*[!0-9]*) iv=15 ;; esac
  while :; do
    [ -t 1 ] && printf '\033[H\033[2J'
    echo "lane-status --watch — $(now_utc) — every ${iv}s (interrupt to stop)"
    if [ -n "${1:-}" ]; then lanes_status "$1"; else lanes_status; fi
    i=$((i + 1)); [ "$n" -gt 0 ] && [ "$i" -ge "$n" ] && return 0
    sleep "$iv"
  done
}

# ==================================================================================================
# lane-feed <lane_dir|L<n>> [--follow] — a readable narration of the lane's stream log.
_LANES_FEED_JQ='fromjson? |
  if .type == "system" and .subtype == "init" then "[init] session \(.session_id // "?")"
  elif .type == "assistant" then (.message.content[]? |
    if .type == "text" then ((.text // "") | gsub("[\\r\\n\\t]+"; " ") | gsub("^ +| +$"; "")) as $t
      | select($t != "") | "[say] \($t[0:200])"
    elif .type == "tool_use" then
      if (.name == "Task" or .name == "Agent") then "[spawn] \(.input.subagent_type // "agent"): \((.input.description // "") | tostring | .[0:120])"
      elif .name == "AskUserQuestion" then "[ask] \(((.input.questions // [])[0].question // "") | tostring | .[0:160])"
      elif .name == "Bash" and ((.input.command // "") | test("current-set")) and ((.input.command // "") | test("ready_for_release|awaiting_merge|escalated"))
        then "[park] \((.input.command // "") | gsub("[\\r\\n\\t]+"; " ") | .[0:160])"
      else "[tool] \(.name) \((.input.command // .input.description // .input.file_path // .input.pattern // "") | tostring | gsub("[\\r\\n\\t]+"; " ") | .[0:120])" end
    else empty end)
  elif .type == "result" then
    if .stop_reason == "tool_deferred" then "[park] deferred \(.deferred_tool_use.id // "?") — awaiting input"
    else "[end] \(.subtype // "?") stop_reason=\(.stop_reason // "?")" end
  else empty end'

lanes_feed() {
  local target="" follow=0 dir
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --follow) follow=1 ;;
      *) [ -z "$target" ] || die "lane-feed: unexpected argument '$1'"; target="$1" ;;
    esac
    shift
  done
  dir="$(_lanes_resolve "$target")"
  _lane_ctx "$dir" || die "lane-feed: not a lane: ${target:-<none>}"
  if [ ! -f "$LN_LOG" ] && [ "$follow" = 0 ]; then echo "lane-feed: $LN_LANE — no stream log yet ($LN_LOG)"; return 0; fi
  echo "lane-feed: $LN_LANE ($LN_RUN) — $LN_LOG"
  if [ "$follow" = 1 ]; then
    touch "$LN_LOG" 2>/dev/null
    tail -n +1 -f "$LN_LOG" | grep --line-buffered '^{' | jq --unbuffered -r -R "$_LANES_FEED_JQ" 2>/dev/null
    return 0
  fi
  grep '^{' "$LN_LOG" 2>/dev/null | jq -r -R "$_LANES_FEED_JQ" 2>/dev/null
  [ -f "$LN_DIED" ] && echo "[died] $(awk -F'\t' '$1 == "died_at" { print $2 }' "$LN_DIED" 2>/dev/null) — no terminal result"
  return 0
}

# ==================================================================================================
# lane-readiness <lane_dir|L<n>> — writes <lane>/.supervisor/automate/<run_id>.merge-readiness.md
# (advisory, never a merge executor). Five checks, each PASS / FAIL / NOT-RUN with its evidence:
#   validation     each `## Validation` entry of the item: PASS only with pasted output (a fenced block)
#                  in the PR body's matching section; mentioned without output, or absent ⇒ NOT-RUN
#   carried-notes  the brief's carried MEDIUM/LOW Plan Review notes, accounted for in the PR body
#   scope-fence    `gh pr diff --name-only` ⊆ the item's `## Touches` / the brief's lanes + changelog.d/
#   gates          required checks on the current head, dismissed-finding decisions, children-settled
#   headline-repro the Validation entry naming a mutation / repro (PASS n/a when none is named)
# Called by the lane at its ready_for_release park; re-written on demand (`lane-status --refresh-readiness`).
_lanes_rd_section() { # <n> <title> <body_file> — the PR body's lines for Validation entry n
  awk -v n="$1" -v t="$2" '
    BEGIN { t = tolower(t) }
    { l = tolower($0) }
    on && (l ~ /^#/ || (l ~ /validation[ #]*[0-9]/ && l !~ ("validation[ #]*" n "([^0-9]|$)"))) { on = 0 }
    !on && (l ~ ("validation[ #]*" n "([^0-9]|$)") || (t != "" && index(l, t) > 0)) { on = 1 }
    on { print }' "$3"
}

lanes_readiness() {
  local target="${1:-}" dir
  dir="$(_lanes_resolve "$target")"
  _lane_ctx "$dir" || die "lane-readiness: not a lane: ${target:-<none>}"
  local rf="$LN_DIR/.supervisor/automate/$LN_RUN.md" out="$LN_DIR/.supervisor/automate/$LN_RUN.merge-readiness.md"
  local status pause pr lp pd item itemf tmp view="" head=unknown gh_ok=0 brief=""
  IFS="$(printf '\t')" read -r status pause pr lp pd <<<"$(_lanes_runfile_fields "$rf")"
  pr="$(_lanes_dash "$pr")"; pd="$(_lanes_dash "$pd")"
  item="$(sed -n 's/^- \[.\] //p' "$LN_DIR/.supervisor/lane-backlog.md" 2>/dev/null | head -1)"
  itemf="$LN_DIR/$item"
  tmp="$(mktemp -d 2>/dev/null)" || die "lane-readiness: no temp dir"
  : > "$tmp/body"; : > "$tmp/files"
  if [ -n "$pr" ] && view="$("$LANES_GH" pr view "$pr" --json body,headRefOid 2>/dev/null)" && jq -e 'type == "object"' >/dev/null 2>&1 <<<"$view"; then
    gh_ok=1; jq -r '.body // ""' <<<"$view" > "$tmp/body"; head="$(jq -r '.headRefOid // "unknown"' <<<"$view")"
  fi
  # ---- a + e: Validation entries
  local vrows="" erows="" n title sec st ev rs=0 vworst=PASS eworst=PASS vlabel="" isrepro
  awk '/^## /{ on = ($0 ~ /^## Validation/); next } on && /^[0-9]+\. / {
         n = $0; sub(/\..*/, "", n); t = $0
         if (match(t, /\*\*[^*]+\*\*/)) t = substr(t, RSTART + 2, RLENGTH - 4); else { sub(/^[0-9]+\. */, "", t); t = substr(t, 1, 60) }
         sub(/:$/, "", t); full = $0; gsub(/\t/, " ", full); print n "\t" t "\t" full }' "$itemf" 2>/dev/null > "$tmp/val"
  while IFS="$(printf '\t')" read -r n title full; do
    [ -n "$n" ] || continue
    isrepro=0; case "$(printf '%s %s' "$title" "$full" | tr '[:upper:]' '[:lower:]')" in *mutation*|*"must catch"*|*repro*|*"must fail"*) isrepro=1 ;; esac
    if [ "$gh_ok" = 0 ]; then st=NOT-RUN; ev="PR body unreadable${pr:+ ($pr)}${pr:-: no PR recorded}"
    else
      sec="$(_lanes_rd_section "$n" "$title" "$tmp/body")"
      if [ -z "$sec" ]; then st=NOT-RUN; ev="no evidence in the PR body"
      elif ! printf '%s\n' "$sec" | grep -q '```'; then st=NOT-RUN; ev="mentioned in the PR body without pasted output"
      elif [ "$isrepro" = 0 ] && printf '%s\n' "$sec" | grep -qw 'FAIL'; then st=FAIL; ev="pasted output shows FAIL"
      else st=PASS; ev="pasted output in the PR body"; fi
    fi
    if [ "$isrepro" = 1 ]; then
      erows="$erows  - V$n $title: $st — $ev
"
      case "$st" in FAIL) eworst=FAIL ;; NOT-RUN) [ "$eworst" = FAIL ] || eworst=NOT-RUN ;; esac
    else
      vrows="$vrows  - V$n $title: $st — $ev
"
      case "$st" in
        FAIL) vworst=FAIL ;;
        NOT-RUN) [ "$vworst" = FAIL ] || vworst=NOT-RUN ;;
      esac
      if [ "$st" != PASS ]; then
        case "$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]')" in
          *"running system"*) case "$vlabel" in ''|running-system) vlabel=running-system ;; *) vlabel=validation ;; esac ;;
          *) vlabel=validation ;;
        esac
      fi
    fi
  done < "$tmp/val"
  local vline eline
  if [ ! -s "$tmp/val" ]; then vworst=NOT-RUN; vlabel=validation; vline="validation: NOT-RUN — no ## Validation section in $item"
  else vline="validation: $vworst — $(printf '%s' "$vrows" | grep -c ' PASS ' | tr -d ' ') of $(printf '%s' "$vrows" | grep -c '^  - ' | tr -d ' ') entr(ies) evidenced"; fi
  if [ -z "$erows" ]; then eworst=PASS; eline="headline-repro: PASS — n/a (the Validation names no repro)"
  else eline="headline-repro: $eworst — the Validation's named repro"; fi
  # ---- b: carried Plan Review notes
  local cline crows="" nc
  local bl; bl="$(grep -l -F "$item" "$LN_DIR"/.supervisor/jobs/*/*.md 2>/dev/null)"
  [ -n "$item" ] && [ -n "$bl" ] && brief="$(printf '%s\n' "$bl" | while IFS= read -r f; do ls -t "$f"; done 2>/dev/null | head -1)"
  local cworst
  if [ -z "$item" ] || [ -z "$brief" ]; then cworst=NOT-RUN; cline="carried-notes: NOT-RUN — no brief naming $item found in the lane"
  else
    grep -iE 'carried' "$brief" | grep -E 'MEDIUM|LOW' | sed 's/^[[:space:]-]*//' > "$tmp/carried"
    nc="$(wc -l < "$tmp/carried" | tr -d ' ')"
    if [ "$nc" = 0 ]; then cworst=PASS; cline="carried-notes: PASS — none carried ($(basename "$brief"))"
    elif grep -qi 'carried' "$tmp/body"; then cworst=PASS; cline="carried-notes: PASS — $nc carried note(s), accounted for in the PR body"
    else cworst=NOT-RUN; cline="carried-notes: NOT-RUN — $nc carried note(s), no accounting in the PR body"; fi
    crows="$(sed 's/^/  - /' "$tmp/carried")"
  fi
  # ---- c: scope fence
  local fline frows="" fworst f dcl outside=""
  {
    awk '/^## /{ on = ($0 ~ /^## Touches/); next } on' "$itemf" 2>/dev/null | grep -o '`[^`]*`' | tr -d '`'
    [ -n "$brief" ] && sed -n 's/.*path: *"\([^"]*\)".*/\1/p; s/^ *- *"\([^"]*\)" *$/\1/p' "$brief"
  } 2>/dev/null | sed 's#^\./##' | awk 'index($0, "/") || index($0, ".")' | env LC_ALL=C sort -u > "$tmp/declared"
  if [ -z "$pr" ] || ! "$LANES_GH" pr diff "$pr" --name-only > "$tmp/files" 2>/dev/null; then
    fworst=NOT-RUN; fline="scope-fence: NOT-RUN — gh pr diff unreadable${pr:+ ($pr)}${pr:-: no PR recorded}"
  else
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      case "$f" in changelog.d/*) continue ;; esac
      local okf=0
      while IFS= read -r dcl; do
        [ -n "$dcl" ] || continue
        case "$f" in "$dcl"|*/"$dcl") okf=1; break ;; esac
        case "$dcl" in */) case "$f" in "$dcl"*) okf=1; break ;; esac ;; esac
        case "$dcl" in *'*'*) case "$f" in $dcl) okf=1; break ;; esac ;; esac
      done < "$tmp/declared"
      [ "$okf" = 1 ] || outside="$outside$f
"
    done < "$tmp/files"
    if [ -z "$outside" ]; then fworst=PASS; fline="scope-fence: PASS — $(grep -c . "$tmp/files" | tr -d ' ') file(s) within the declared files + changelog.d/"
    else fworst=FAIL; fline="scope-fence: FAIL — file(s) outside the declared files + changelog.d/"; frows="$(printf '%s' "$outside" | sed '/^$/d; s/^/  - /')"; fi
  fi
  # ---- d: gates
  local gline grows="" gworst=PASS cj cs
  if [ -z "$pr" ]; then gworst=NOT-RUN; grows="  - required checks: NOT-RUN — no PR recorded"
  else
    cj="$("$LANES_GH" pr checks "$pr" --required --json name,bucket 2>/dev/null)" || true
    if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$cj"; then gworst=NOT-RUN; grows="  - required checks: NOT-RUN — unreadable"
    else
      cs="$(jq -r --arg h "$head" 'if length == 0 then "NOT-RUN — no required checks reported"
        elif any(.[]; .bucket == "fail" or .bucket == "cancel") then "FAIL — " + ([.[] | select(.bucket == "fail" or .bucket == "cancel") | .name] | join(", "))
        elif all(.[]; .bucket == "pass" or .bucket == "skipping") then "PASS — \(length) required check(s) green on \($h)"
        else "NOT-RUN — pending: " + ([.[] | select(.bucket != "pass" and .bucket != "skipping") | .name] | join(", ")) end' <<<"$cj")"
      grows="  - required checks: $cs"
      case "$cs" in FAIL*) gworst=FAIL ;; NOT-RUN*) gworst=NOT-RUN ;; esac
    fi
  fi
  case "$pd" in
    ''|0) grows="$grows
  - dismissed findings: PASS — none pending an owner decision" ;;
    *[!0-9]*) grows="$grows
  - dismissed findings: NOT-RUN — pending_decisions unreadable ($pd)"; [ "$gworst" = FAIL ] || gworst=NOT-RUN ;;
    *) grows="$grows
  - dismissed findings: FAIL — $pd without an owner decision"; gworst=FAIL ;;
  esac
  if grep -qiE 'children[-_ ]settled' "$rf" 2>/dev/null; then
    grows="$grows
  - children-settled: PASS — $(grep -iE 'children[-_ ]settled' "$rf" | tail -1 | sed 's/^- //' | cut -c1-160)"
  else
    grows="$grows
  - children-settled: NOT-RUN — not recorded in the run file"; [ "$gworst" = FAIL ] || gworst=NOT-RUN
  fi
  gline="gates: $gworst"
  # ---- score
  local pass=0 total=5 bad="" w lbl
  for w in "validation:$vworst" "carried-notes:$cworst" "scope-fence:$fworst" "gates:$gworst" "headline-repro:$eworst"; do
    lbl="${w%%:*}"; st="${w#*:}"
    if [ "$st" = PASS ]; then pass=$((pass + 1)); else
      [ "$lbl" = validation ] && lbl="${vlabel:-validation}"
      bad="$bad${bad:+, }$lbl $st"
    fi
  done
  local summary="ready ($pass/$total)"; [ -n "$bad" ] && summary="ready ($pass/$total: $bad)"
  {
    echo "# Merge readiness: $LN_RUN"
    echo
    echo "- item: ${item:-unknown} | pr: ${pr:-none} | head: $head | written: $(now_utc)"
    echo "- score: $pass/$total | summary: $summary"
    echo "- advisory only: this report never merges; the owner merges by hand."
    echo
    echo "## Checks"
    echo "- $vline"; [ -n "$vrows" ] && printf '%s' "$vrows"
    echo "- $cline"; [ -n "$crows" ] && printf '%s\n' "$crows"
    echo "- $fline"; [ -n "$frows" ] && printf '%s\n' "$frows"
    echo "- $gline"; printf '%s\n' "$grows"
    echo "- $eline"; [ -n "$erows" ] && printf '%s' "$erows"
  } > "$out.tmp.$$" 2>/dev/null && mv "$out.tmp.$$" "$out" || { rm -f "$out.tmp.$$"; rm -rf "$tmp"; echo "lane-readiness: $LN_LANE — report not written (unwritable): $out"; return 0; }
  rm -rf "$tmp"
  echo "lane-readiness: $LN_LANE ($LN_RUN) — $summary — $out"
  return 0
}

_lanes_usage() { awk 'NR >= 9 && /^#$/ { exit } NR >= 9' "$SELF"; }

lanes_main() {
  local sub="${1:-}"; shift 2>/dev/null || true
  case "$sub" in
    lane-create) lanes_create "$@" ;;
    lane-launch) lanes_launch "$@" ;;
    relay-hook) lanes_relay_hook "$@" ;;
    lane-answer) lanes_answer "$@" ;;
    lane-remove) lanes_remove "$@" ;;
    lane-info) lanes_info "$@" ;;
    init-check) lanes_init_check "$@" ;;
    pick-guard) lanes_pick_guard "$@" ;;
    branch-check) lanes_branch_check "$@" ;;
    lane-status) lanes_status "$@" ;;
    lane-feed) lanes_feed "$@" ;;
    lane-readiness) lanes_readiness "$@" ;;
    _lane-run) lanes_run_wrapper "$@" ;;
    _merge-hooks) _lanes_merge_hooks "$@" ;;
    -h|--help|help) _lanes_usage ;;
    *) _lanes_usage >&2; return 2 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then lanes_main "$@"; exit $?; fi
