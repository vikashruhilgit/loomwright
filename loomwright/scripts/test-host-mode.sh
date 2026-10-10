#!/usr/bin/env bash
# test-host-mode.sh — behavioural suite for host mode (host-contract/02): with LOOMWRIGHT_HOST_MODE=1
# no Loomwright hook creates or modifies anything in the session's repo; redirected state goes to
# LOOMWRIGHT_HOST_STATE_DIR when it is valid, else (owner decision D1) gate state goes to the
# per-user gate root ${TMPDIR}/loomwright-host-<uid>/<repo-hash>/ and every other write skips; and
# the fail-CLOSED gates keep enforcing. Contract: docs/HOOKS.md §"Host mode"; resolver:
# scripts/host-mode.sh.
#
# HOW A HOOK IS RUN: every leaf comes out of hooks/hooks.json at run time and is executed as its
# command string, verbatim, with `sh -c` from the repo dir, the plugin-root and project-dir variables
# set and the payload on stdin from a file (never a pipe: an inert leaf that exits without reading
# stdin must not turn into an EPIPE). A leaf runs when its group matcher matches the event's
# discriminator (agent_type / tool_name / notification_type / reason) the way the runtime matches
# one: an absent matcher matches everything, else an unanchored regex. Nothing is restated: a leaf
# added to hooks.json is fired by the next run, and leg (a) fails when a script hooks.json invokes
# was never fired.
#
# HERMETIC: each case gets a throwaway `git init` repo, its own HOME, its own TMPDIR and its own
# state dir under one mktemp root; `gh` and `claude` are PATH stubs that log and fail; curl, the OS
# notifiers and the egress env are handled by hermetic-test-env.sh. No network. Inherited flags are
# scrubbed: the suite unsets them once, and every leg runs through `env -u` (off legs:
# `env -u LOOMWRIGHT_HOST_MODE -u LOOMWRIGHT_HOST_STATE_DIR`; every leg also drops
# LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS, without which the guard denies below would be vacuous).
#
# LEGS
#   (a)  host mode + valid state dir: one full session of hook firings (SessionStart startup and
#        resume, PreToolUse Agent|Task / Bash / Write|Edit / the ask-user tool, PostToolUse Task /
#        Bash / Write|Edit / the ask-user tool, Notification, a subagent stop for every agent hooks.json
#        names, the inline StopFailure leaf, Stop, SessionEnd) against a seeded repo (a committed,
#        agent-written `.supervisor/state.md`) and a bare one. Asserts `git status --porcelain
#        --ignored` is empty, the working tree is byte-identical (empty dirs included), every leaf
#        exits 0, HOME and TMPDIR are untouched, and the events, state.md and failures.log line are
#        in the state dir.
#   (b)  host mode, no state dir (D1): the same session. Asserts the same repo checks, every leaf
#        exits 0, HOME and the unused state dir untouched, TMPDIR holds ONLY loomwright-host-<uid>/
#        <repo-hash> (mode 700, hash derived here independently of the resolver), the gate state is
#        there, and no non-gate file (failures.log, telemetry.log, worktrees.log, notifications.log,
#        a nudge marker) was written anywhere.
#   (c)  guard-test-integrity under host mode, state-dir and D1: unarmed -> a protected edit is
#        allowed; armed through the PreToolUse[Agent|Task] leaf -> the marker is in the gate dir, and
#        a protected edit, a hook-bypass commit, an edit of the redirected guard dir, an edit of
#        host-mode.sh and an rm of the marker (plain, and through a case-variant spelling where the
#        volume is case-insensitive) are all denied; disarmed by SessionEnd -> allowed.
#   (c2) guard-finalize-publish under host mode, state-dir and D1: `gh pr create` is denied for a
#        live run whose state.md + session log are in the gate dir, and for a live run whose ONLY
#        state.md is the agent-written repo copy; after write-marker (marker lands in the gate dir)
#        the same publish is allowed.
#   (c3) stale gate copy, state-dir and D1: a gate state.md (complete, old session) beside a repo
#        state.md (running, new session): lw_state_md_read returns the repo copy, the publish is
#        denied for the NEW session, and a worker's subagent stop projects the NEW session into the
#        gate dir (emit-progress-event + build-state), after which lw_state_md_read returns it.
#   (d)  off mode unchanged: the same session writes `.supervisor/` (and, telemetry on,
#        the project-local settings file) in the repo as before, nothing under TMPDIR; the off-mode
#        STOP_FAILURE line keeps its byte format; LOOMWRIGHT_HOST_MODE=true is off too; and the
#        host-mode JSONL lines carry the same keys per event as the off-mode ones (AC2 line format).
#   (e)  mutation control: a scratch plugin root identical but for emit-agent-identity.sh with its
#        host-mode block removed (mutant gated: non-empty, differs, `bash -n` clean, resolver gone)
#        makes leg (a) FAIL with the repo dirtied.
#   (f)  an invalid LOOMWRIGHT_HOST_STATE_DIR (relative, missing, a file, inside the repo, a symlink
#        into the repo, a case-variant spelling of the repo or of a dir in it) is rejected: the gate dir is D1, a worker session leaves the repo clean and
#        writes nothing through the bad dir (AC5).
#   (g)  an unsafe TMPDIR (relative, a dir inside the repo, or a case-variant spelling of one) is
#        not the D1 base: the repo stays
#        clean and the gate root falls back to /tmp (removed again on exit).
#   (h)  a hostile pre-created D1 root ($TMPDIR/loomwright-host-<uid> a symlink to a foreign dir,
#        mode 500, or mode 777): the gate dir is unresolvable, nothing lands in the foreign dir,
#        arming writes no marker, and both guards DENY (guard_unavailable / gate_dir_unresolvable).
#   (i)  a linked-worktree session: a state dir inside the linked worktree or inside the main one is
#        rejected by every caller alike (emitters anchor on the main worktree, the guards on the
#        project dir) — both worktrees stay clean and the marker and events share the D1 gate dir.
#   (j)  check-children-settled.sh under host mode reads a repo-shaped `--log` (relative and
#        absolute) from the gate dir, judging a state dir named `.supervisor` against the real repo
#        root (an outside one is valid, an in-repo one maps to D1); off mode does not; an unloadable helper is `unverifiable`, and
#        the guards fail CLOSED on it (deny / write-marker `helper_missing`).
#   (k)  mutation control: host-mode.sh with its D1 ownership/symlink check neutered makes leg (h)'s
#        symlink case FAIL (the marker lands in the foreign dir).
#
# HONEST LIMITS: "nothing written outside the repo" is observed on the repo, the case HOME, the case
# TMPDIR and the state dir — a write to some other absolute path would not be seen. Hooks run with
# `sh -c`; the runtime's own choice of shell is not probed here. Exit: 0 on full pass, 1 otherwise.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HERE/.." && pwd)"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass + 1)); }
no() { echo "  FAIL: $1"; fail=$((fail + 1)); }

for c in jq git python3 bash sh cksum awk; do
  command -v "$c" >/dev/null 2>&1 || { echo "FATAL $c required" >&2; exit 1; }
done
for f in hooks/hooks.json scripts/host-mode.sh scripts/emit-agent-identity.sh; do
  [ -f "$PLUGIN_ROOT/$f" ] || { echo "FATAL missing $PLUGIN_ROOT/$f" >&2; exit 1; }
done

# Inherited flags never reach a leg (each leg sets exactly what it needs through hm_env).
unset LOOMWRIGHT_HOST_MODE LOOMWRIGHT_HOST_STATE_DIR LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS \
  LOOMWRIGHT_GUARD_EXTRA_GLOBS CLAUDE_ENV_FILE CLAUDE_PROJECT_DIR
export PYTHONDONTWRITEBYTECODE=1

# The harness names this suite must spell, each written exactly once (the vendor-coupling ratchet
# counts literals; every later use goes through these variables).
EV_SUBSTOP="SubagentStop"; TOOL_ASK="AskUserQuestion"; KEY_SPAWN_TYPE="subagent_type"

BASE="$(mktemp -d "${TMPDIR:-/tmp}/test-host-mode.XXXXXX")" || { echo "FATAL mktemp" >&2; exit 1; }
BASE="$(cd "$BASE" && pwd -P)"
# (g) falls back to the real /tmp; each per-repo gate dir it makes there is listed here and removed.
trap 'while IFS= read -r p; do [ -n "$p" ] && rm -rf "$p"; done < "$BASE/cleanup.list" 2>/dev/null
  chmod -R u+rwx "$BASE" 2>/dev/null; rm -rf "$BASE"' EXIT
: > "$BASE/cleanup.list"

mkdir -p "$BASE/bin" "$BASE/in"
for s in gh claude; do
  printf '#!/bin/sh\nprintf "%%s %%s\\n" "${0##*/}" "$*" >> "%s/stub.log"\nexit 1\n' "$BASE" > "$BASE/bin/$s"
  chmod +x "$BASE/bin/$s"
done
PATH="$BASE/bin:$PATH"; export PATH
export HERMETIC_EGRESS_LOG="$BASE/egress.log"

UID_N="$(id -u)"
CC="cc-host-0001"        # the Claude Code session id every payload carries
RUN="hmrun0001"          # the plugin run the seeded repo state.md names
# A session transcript (input only, outside every observed dir) so the token ledger has a byte proxy.
printf '%s\n' '{"type":"user"}' > "$BASE/in/$CC.jsonl"

SUBAGENT_TYPES="$(jq -r --arg e "$EV_SUBSTOP" '.hooks[$e][] | .matcher // empty' "$PLUGIN_ROOT/hooks/hooks.json" | sed 's/^loomwright://')"
ALL_SCRIPTS="$(jq -r '[.. | objects | select(.type? == "command") | .command] | .[]' "$PLUGIN_ROOT/hooks/hooks.json" \
  | grep -oE 'scripts/[A-Za-z0-9_.-]+' | env LC_ALL=C sort -u)"

# ---- per-case context ---------------------------------------------------------------------------
# C_DIR case root; C_MODE off|offval|sd|d1; C_ROOT plugin root; C_REPO / C_HOME / C_TMP / C_SD;
# C_MAIN the repo's main worktree as git prints it; C_GATE lw_gate_state_dir for this mode.
seed_state() {  # seed_state <session_id> <status>
  printf '# Supervisor State\n\n## Session\n- session_id: %s\n- branch: main\n- status: %s\n- phase: execute\n\n## Decisions Log\n- seeded by test-host-mode.sh\n' "$1" "$2"
}

hm_env() {  # hm_env <cmd...> — run <cmd> under the current case's mode, from the current dir
  local -a pre
  case "$C_MODE" in
    off)    pre=(-u LOOMWRIGHT_HOST_MODE -u LOOMWRIGHT_HOST_STATE_DIR) ;;
    offval) pre=(LOOMWRIGHT_HOST_MODE=true "LOOMWRIGHT_HOST_STATE_DIR=$C_SD") ;;
    sd)     pre=(LOOMWRIGHT_HOST_MODE=1 "LOOMWRIGHT_HOST_STATE_DIR=$C_SD") ;;
    d1)     pre=(-u LOOMWRIGHT_HOST_STATE_DIR LOOMWRIGHT_HOST_MODE=1) ;;
  esac
  env -u LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS -u LOOMWRIGHT_DESKTOP_NOTIFICATIONS "${pre[@]}" \
    "HOME=$C_HOME" "TMPDIR=$C_TMP" "CLAUDE_PLUGIN_ROOT=$C_ROOT" "CLAUDE_PROJECT_DIR=$C_REPO" \
    CLAUDE_CODE_ENABLE_TELEMETRY=1 "$@"
}

gate_dir() {  # the resolver's answer for this case (the real helper, whatever C_ROOT is)
  ( cd "$C_REPO" && hm_env bash -c '. "$1" && lw_gate_state_dir "$2"' _ "$PLUGIN_ROOT/scripts/host-mode.sh" "$C_MAIN" )
}
state_md_read() {
  ( cd "$C_REPO" && hm_env bash -c '. "$1" && lw_state_md_read "$2"' _ "$PLUGIN_ROOT/scripts/host-mode.sh" "$C_MAIN" )
}

snap() {  # every path under the repo (minus .git), files with a checksum — empty dirs show too
  ( cd "$C_REPO" && find . -path ./.git -prune -o -print | env LC_ALL=C sort | while IFS= read -r p; do
      if [ -f "$p" ]; then printf '%s %s\n' "$p" "$(cksum < "$p")"; else printf '%s\n' "$p"; fi
    done )
}
listing() { find "$1" -mindepth 1 2>/dev/null | env LC_ALL=C sort; }

new_case() {  # new_case <name> <mode> <bare|seeded> [plugin_root]
  C_DIR="$BASE/$1"; C_MODE="$2"; C_ROOT="${4:-$PLUGIN_ROOT}"
  C_REPO="$C_DIR/repo"; C_HOME="$C_DIR/home"; C_TMP="$C_DIR/tmp"; C_SD="$C_DIR/state"
  C_RC="$C_DIR/rc.log"; C_CHECKS="$C_DIR/checks"
  mkdir -p "$C_REPO" "$C_HOME" "$C_TMP" "$C_SD"; : > "$C_RC"; : > "$C_CHECKS"
  (
    cd "$C_REPO" || exit 1
    export HOME="$C_HOME" GIT_CONFIG_NOSYSTEM=1
    git init -q . && git symbolic-ref HEAD refs/heads/main && printf 'host mode fixture\n' > README.md || exit 1
    if [ "$3" = seeded ]; then mkdir -p .supervisor && seed_state "$RUN" running > .supervisor/state.md; fi
    git add -A && git -c user.name=t -c user.email=t@e.x commit -q -m init
  ) >/dev/null 2>&1 || { echo "FATAL fixture repo $1" >&2; exit 1; }
  C_MAIN="$(git -C "$C_REPO" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
  C_GATE="$(gate_dir)"
  C_SNAP0="$(snap)"
}

# ---- running hooks.json leaves ------------------------------------------------------------------
leaves() {  # leaves <event> <discriminator> -> "<group> <leaf>" per matching type:command leaf
  jq -r --arg ev "$1" --arg d "$2" '(.hooks[$ev] // []) | to_entries[] | .key as $g | .value as $grp
    | select((($grp.matcher // "") == "") or ($d | test($grp.matcher)))
    | $grp.hooks | to_entries[] | select(.value.type == "command") | "\($g) \(.key)"' "$C_ROOT/hooks/hooks.json"
}
leaf_cmd() {
  jq -r --arg ev "$1" --argjson g "$2" --argjson l "$3" '.hooks[$ev][$g].hooks[$l].command' "$C_ROOT/hooks/hooks.json"
}
run_cmd() {  # run_cmd <command-string> [env assignments...] — LAST_RC / LAST_OUT; payload in $C_DIR/payload.json
  local cmd="$1"; shift
  ( cd "$C_REPO" && hm_env env "$@" sh -c "$cmd" < "$C_DIR/payload.json" > "$C_DIR/last.out" 2> "$C_DIR/last.err" )
  LAST_RC=$?
  LAST_OUT="$(cat "$C_DIR/last.out" 2>/dev/null)"
}
fire() {  # fire <event> <discriminator> <payload> — every matching leaf, verbatim; logged to $C_RC
  local ev="$1" d="$2" g l cmd lst
  printf '%s' "$3" > "$C_DIR/payload.json"
  lst="$(leaves "$ev" "$d")"
  if [ -z "$lst" ]; then printf '%s(%s) nomatch\n' "$ev" "$d" >> "$C_RC"; return 0; fi
  while read -r g l; do
    cmd="$(leaf_cmd "$ev" "$g" "$l")"
    run_cmd "$cmd"
    printf '%s[%s].%s rc=%s %s\n' "$ev" "$g" "$l" "$LAST_RC" \
      "$(printf '%s' "$cmd" | grep -oE 'scripts/[A-Za-z0-9_.-]+' | tr '\n' ' ')" >> "$C_RC"
  done <<EOF
$lst
EOF
}
fire_one() {  # fire_one <event> <discriminator> <script basename> <payload> [env...] — that leaf only
  local ev="$1" d="$2" want="$3" g l cmd
  printf '%s' "$4" > "$C_DIR/payload.json"; shift 4
  LAST_RC=99; LAST_OUT=""
  while read -r g l; do
    [ -n "$g" ] || continue
    cmd="$(leaf_cmd "$ev" "$g" "$l")"
    case "$cmd" in *"scripts/$want"*) run_cmd "$cmd" "$@"; return 0 ;; esac
  done <<EOF
$(leaves "$ev" "$d")
EOF
}

p_sub() {  # subagent-stop payload for agent type <t>
  jq -nc --arg ev "$EV_SUBSTOP" --arg cc "$CC" --arg t "loomwright:loomwright:$1" --arg in "$BASE/in" \
    '{hook_event_name:$ev, session_id:$cc, transcript_path:($in + "/" + $cc + ".jsonl"), agent_id:"a1", agent_type:$t}'
}
spawn_input() { jq -nc --arg k "$KEY_SPAWN_TYPE" '{($k):"loomwright:worker", description:"d", prompt:"p"}'; }
p_tool() {  # p_tool <PreToolUse|PostToolUse> <tool_name> <tool_input json> [tool_response json]
  jq -nc --arg cc "$CC" --arg ev "$1" --arg tn "$2" --argjson ti "$3" --argjson tr "${4:-null}" \
    '{hook_event_name:$ev, session_id:$cc, tool_name:$tn, tool_use_id:"tu-0001", tool_input:$ti}
     + (if $tr == null then {} else {tool_response:$tr} end)'
}
p_bash() { p_tool PreToolUse Bash "$(jq -nc --arg c "$1" '{command:$c}')"; }
p_write() { p_tool PreToolUse Write "$(jq -nc --arg f "$1" '{file_path:$f, content:"x"}')"; }
STOPFAIL_PAYLOAD="$(jq -nc --arg cc "$CC" '{hook_event_name:"StopFailure", session_id:$cc, agent_id:"a1", error:"rate_limit"}')"

session_events() {  # session_events <all|worker> — one session's hook firings, in a plausible order
  local a types="worker"
  [ "$1" = all ] && types="$SUBAGENT_TYPES"
  fire SessionStart startup "$(jq -nc --arg cc "$CC" '{hook_event_name:"SessionStart", session_id:$cc, source:"startup"}')"
  fire SessionStart resume "$(jq -nc --arg cc "$CC" '{hook_event_name:"SessionStart", session_id:$cc, source:"resume"}')"
  fire PreToolUse Task "$(p_tool PreToolUse Task "$(spawn_input)")"
  fire PreToolUse Bash "$(p_bash 'ls')"
  fire PreToolUse Write "$(p_write "$C_MAIN/README.md")"
  fire PostToolUse Task "$(p_tool PostToolUse Agent "$(spawn_input)" \
    '{"agentId":"a2","agentType":"loomwright:worker","status":"completed"}')"
  fire PostToolUse Bash "$(p_tool PostToolUse Bash '{"command":"git worktree add ../hm-wt && gh pr create --fill"}' \
    '{"stdout":"https://github.com/o/r/pull/7\n","stderr":""}')"
  fire PostToolUse Write "$(p_tool PostToolUse Write "$(jq -nc --arg f "$C_MAIN/.supervisor/state.md" '{file_path:$f, content:"x"}')")"
  fire PreToolUse "$TOOL_ASK" "$(p_tool PreToolUse "$TOOL_ASK" '{"questions":[{"question":"q?"}]}')"
  fire PostToolUse "$TOOL_ASK" "$(p_tool PostToolUse "$TOOL_ASK" '{"questions":[{"question":"q?"}]}' '{"answers":{}}')"
  fire Notification idle_prompt "$(jq -nc --arg cc "$CC" '{hook_event_name:"Notification", session_id:$cc, notification_type:"idle_prompt", message:"waiting"}')"
  for a in $types; do fire "$EV_SUBSTOP" "loomwright:loomwright:$a" "$(p_sub "$a")"; done
  fire StopFailure "" "$STOPFAIL_PAYLOAD"
  fire Stop "" "$(jq -nc --arg cc "$CC" '{hook_event_name:"Stop", session_id:$cc}')"
  fire SessionEnd other "$(jq -nc --arg cc "$CC" '{hook_event_name:"SessionEnd", session_id:$cc, reason:"other"}')"
}

# ---- shared checks (recorded to $C_CHECKS, replayed by the caller) ------------------------------
rec() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1${3:+ — $3}"; fi >> "$C_CHECKS"; }
replay() {
  local line
  while IFS= read -r line; do
    case "$line" in PASS\ *) ok "${line#PASS }" ;; FAIL\ *) no "${line#FAIL }" ;; esac
  done < "$C_CHECKS"
  : > "$C_CHECKS"
}
repo_clean_checks() {  # repo_clean_checks <label>
  local st bad
  st="$(git -C "$C_REPO" status --porcelain --ignored 2>&1)"
  [ -z "$st" ]; rec "$1: git status --porcelain --ignored is empty" $? "$(printf '%s' "$st" | tr '\n' ' ')"
  [ "$(snap)" = "$C_SNAP0" ]; rec "$1: working tree byte-identical, empty dirs included" $?
  [ -z "$(listing "$C_HOME")" ]; rec "$1: HOME untouched" $? "$(listing "$C_HOME" | tr '\n' ' ')"
  bad="$(grep -v ' rc=0 ' "$C_RC")"
  [ -z "$bad" ]; rec "$1: every leaf matched and exited 0" $? "$(printf '%s' "$bad" | tr '\n' ' ')"
}
events_in() {  # distinct event names across <dir>/logs/*.jsonl
  cat "$1"/logs/*.jsonl 2>/dev/null | jq -r '.event // .type // empty' 2>/dev/null | env LC_ALL=C sort -u | tr '\n' ' '
}
has_events() {  # has_events <dir> <label> <where, for the label>
  local ev got
  got="$(events_in "$1")"
  for ev in agent_lifecycle agent_identity token_ledger subtask_complete pr_created; do
    case " $got" in *" $ev "*) rec "$2: $ev line in $3" 0 ;; *) rec "$2: $ev line in $3" 1 "got: $got" ;; esac
  done
}
stopfail_line_ok() {  # the STOP_FAILURE line keeps the off-mode byte format: [<utc>] STOP_FAILURE <payload>
  local f="$1" line
  line="$(tail -1 "$f" 2>/dev/null)"
  grep -qE '^\[[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\] STOP_FAILURE ' <<<"$line" \
    && [ "${line#*] STOP_FAILURE }" = "$STOPFAIL_PAYLOAD" ]
}
key_sig() {  # per-event key sets of every JSONL line under <logs dir>
  cat "$1"/*.jsonl 2>/dev/null | jq -c 'select(type == "object") | {e: (.event // .type), k: (keys - ["ts"])}' 2>/dev/null \
    | env LC_ALL=C sort -u
}

host_leg() {  # host_leg <label> <bare|seeded> — leg (a) (C_MODE=sd) or (b) (C_MODE=d1) checks
  local lbl="$1" fx="$2" fired s miss="" top
  repo_clean_checks "$lbl"
  if [ "$fx" = seeded ]; then
    fired="$(cat "$C_RC")"
    for s in $ALL_SCRIPTS; do case "$fired" in *"$s "*) ;; *) miss="$miss $s" ;; esac; done
    [ -z "$miss" ]; rec "$lbl: every script hooks.json invokes was fired" $? "never fired:$miss"
    grep -q '^StopFailure\[0\]\.0 rc=0 ' "$C_RC"; rec "$lbl: the inline StopFailure leaf ran" $?
  fi
  has_events "$C_GATE" "$lbl" "the gate dir's logs/"
  if [ "$fx" = seeded ]; then
    grep -q "^- session_id: $RUN\$" "$C_GATE/state.md" 2>/dev/null
    rec "$lbl: state.md projected into the gate dir (the run the repo seed names)" $?
    [ "$(seed_state "$RUN" running)" = "$(cat "$C_REPO/.supervisor/state.md")" ]
    rec "$lbl: the agent-written repo state.md is unchanged" $?
  fi
  if [ "$C_MODE" = sd ]; then
    [ "$C_GATE" = "$C_SD" ]; rec "$lbl: lw_gate_state_dir is LOOMWRIGHT_HOST_STATE_DIR" $? "$C_GATE"
    [ -z "$(listing "$C_TMP")" ]; rec "$lbl: TMPDIR untouched (no D1 gate root with a valid state dir)" $? "$(listing "$C_TMP" | tr '\n' ' ')"
    stopfail_line_ok "$C_SD/logs/failures.log"; rec "$lbl: STOP_FAILURE line in the state dir, off-mode byte format" $?
    [ -f "$C_SD/logs/worktrees.log" ]; rec "$lbl: worktrees.log redirected to the state dir" $?
    if [ "$fx" = seeded ]; then   # only the seeded run fires the agents whose leaves call send-telemetry.sh
      [ -f "$C_SD/logs/telemetry.log" ]; rec "$lbl: telemetry.log redirected to the state dir" $?
    fi
  else
    top="$C_TMP/loomwright-host-$UID_N"
    [ "$C_GATE" = "$top/$(d1_hash)" ]; rec "$lbl: lw_gate_state_dir is \$TMPDIR/loomwright-host-<uid>/<sha256(main path)[:12]>" $? "$C_GATE"
    s="$(listing "$C_TMP" | awk -v t="$top" -v g="$C_GATE" '$0 != t && $0 != g && index($0, g "/") != 1')"
    [ -z "$s" ] && [ -d "$C_GATE" ]
    rec "$lbl: outside the repo, writes landed only under \$TMPDIR/loomwright-host-<uid>/<hash>" $? "elsewhere: $(printf '%s' "$s" | tr '\n' ' ')"
    [ "$(ls -ld "$top" | cut -c1-10)" = "drwx------" ] && [ "$(ls -ld "$C_GATE" | cut -c1-10)" = "drwx------" ]
    rec "$lbl: the per-user gate root is mode 700" $?
    [ -z "$(listing "$C_SD")" ]; rec "$lbl: the (unset) state dir untouched" $?
    s="$(find "$C_TMP" "$C_REPO" "$C_HOME" \( -name failures.log -o -name telemetry.log -o -name worktrees.log \
      -o -name notifications.log -o -name .notified-ids -o -name '*nudge-shown' \) 2>/dev/null)"
    [ -z "$s" ]; rec "$lbl: every non-gate write skipped (D1)" $? "$(printf '%s' "$s" | tr '\n' ' ')"
  fi
}
d1_hash() {  # D1's <repo-hash>, derived here from the spec, not from the resolver
  local h
  h="$(printf '%s' "$C_MAIN" | shasum -a 256 2>/dev/null | cut -c1-12)"
  [ -n "$h" ] || h="$(printf '%s' "$C_MAIN" | sha256sum 2>/dev/null | cut -c1-12)"
  printf '%s' "$h"
}

# =================================================================================================
echo "== (a) host mode + valid state dir =="
for fx in seeded bare; do
  new_case "a-$fx" sd "$fx"
  if [ "$fx" = seeded ]; then session_events all; else session_events worker; fi
  host_leg "(a) $fx" "$fx"; replay
  [ "$fx" = seeded ] && A_SIG="$(key_sig "$C_SD/logs")"
done

echo "== (b) host mode, no state dir (D1) =="
for fx in seeded bare; do
  new_case "b-$fx" d1 "$fx"
  if [ "$fx" = seeded ]; then session_events all; else session_events worker; fi
  host_leg "(b) $fx" "$fx"; replay
done

# =================================================================================================
echo "== (c) guard-test-integrity keeps denying under host mode =="
is_deny() { [ "$LAST_RC" = 2 ] && grep -q '"permissionDecision":"deny"' <<<"$LAST_OUT"; }
for m in sd d1; do
  new_case "c-$m" "$m" bare
  fire_one PreToolUse Write guard-test-integrity.sh "$(p_write "$C_MAIN/jest.config.js")"
  [ "$LAST_RC" = 0 ]; rec "(c) $m: unarmed session -> protected edit allowed (control)" $? "rc=$LAST_RC"
  fire_one PreToolUse Task guard-arm.sh "$(p_tool PreToolUse Task "$(spawn_input)")"
  [ -f "$C_GATE/guard/$CC.json" ]; rec "(c) $m: PreToolUse[Agent|Task] armed the session in the gate dir" $? "$(listing "$C_GATE" | tr '\n' ' ')"
  fire_one PreToolUse Write guard-test-integrity.sh "$(p_write "$C_MAIN/jest.config.js")"
  is_deny; rec "(c) $m: armed -> protected edit denied" $? "rc=$LAST_RC out=$LAST_OUT"
  fire_one PreToolUse Write guard-test-integrity.sh "$(p_write "$C_MAIN/jest.config.js")" LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS=1
  [ "$LAST_RC" = 0 ]; rec "(c) $m: control — the session opt-out flips it, so the scrubbed env is what makes the deny meaningful" $? "rc=$LAST_RC"
  fire_one PreToolUse Bash guard-test-integrity.sh "$(p_bash 'git commit --no-verify -m x')"
  is_deny; rec "(c) $m: armed -> hook-bypass commit denied" $? "rc=$LAST_RC"
  fire_one PreToolUse Write guard-test-integrity.sh "$(p_write "$C_GATE/guard/other.json")"
  is_deny; rec "(c) $m: armed -> edit inside the redirected guard dir denied" $? "rc=$LAST_RC"
  fire_one PreToolUse Write guard-test-integrity.sh "$(p_write "$C_ROOT/scripts/host-mode.sh")"
  is_deny; rec "(c) $m: armed -> edit of host-mode.sh denied" $? "rc=$LAST_RC"
  fire_one PreToolUse Bash guard-test-integrity.sh "$(p_bash "rm -f $C_GATE/guard/$CC.json")"
  is_deny; rec "(c) $m: armed -> rm of the redirected marker denied" $? "rc=$LAST_RC"
  # a case-variant spelling of the gate dir names the SAME dir on a case-insensitive volume
  CV_GATE="$C_DIR/$(printf '%s' "${C_GATE#"$C_DIR"/}" | tr '[:lower:]' '[:upper:]')"
  if [ "$CV_GATE" -ef "$C_GATE" ]; then
    fire_one PreToolUse Write guard-test-integrity.sh "$(p_write "$CV_GATE/GUARD/other.json")"
    is_deny; rec "(c) $m: armed -> edit of a case-variant guard-dir path denied" $? "rc=$LAST_RC out=$LAST_OUT"
    fire_one PreToolUse Bash guard-test-integrity.sh "$(p_bash "rm -f $CV_GATE/GUARD/$CC.json")"
    is_deny; rec "(c) $m: armed -> rm of the case-variant marker path denied" $? "rc=$LAST_RC out=$LAST_OUT"
  else
    echo "  skip: (c) $m case-variant guard paths — the scratch filesystem is case-sensitive"
  fi
  fire_one SessionEnd other guard-arm.sh "$(jq -nc --arg cc "$CC" '{hook_event_name:"SessionEnd", session_id:$cc, reason:"other"}')"
  [ ! -e "$C_GATE/guard/$CC.json" ]; rec "(c) $m: SessionEnd disarm removed the gate-dir marker" $?
  fire_one PreToolUse Write guard-test-integrity.sh "$(p_write "$C_MAIN/jest.config.js")"
  [ "$LAST_RC" = 0 ]; rec "(c) $m: disarmed -> allowed again" $? "rc=$LAST_RC"
  : > "$C_RC"; repo_clean_checks "(c) $m"
  replay
done

# =================================================================================================
echo "== (c2) guard-finalize-publish denies an unmarked publish under host mode =="
PUBLISH="gh pr create --fill"
write_marker() {
  ( cd "$C_REPO" && hm_env bash "$C_ROOT/scripts/guard-finalize-publish.sh" write-marker > "$C_DIR/wm.out" 2>&1 )
}
for m in sd d1; do
  # setup 1: state.md + session log in the gate dir, nothing in the repo
  new_case "c2-gate-$m" "$m" bare
  ( umask 077; mkdir -p "$C_GATE/logs" ) && seed_state run2 running > "$C_GATE/state.md"
  jq -nc --arg cc "$CC" '{event:"session_start", session_id:"run2", cc_session_id:$cc}' > "$C_GATE/logs/run2.jsonl"
  fire_one PreToolUse Bash guard-finalize-publish.sh "$(p_bash "$PUBLISH")"
  is_deny; rec "(c2) $m gate-dir run: unmarked publish denied" $? "rc=$LAST_RC out=$LAST_OUT"
  write_marker; rc=$?
  [ "$rc" = 0 ] && [ -f "$C_GATE/logs/run2.finalize-gate" ]
  rec "(c2) $m gate-dir run: write-marker wrote the marker into the gate dir" $? "rc=$rc $(cat "$C_DIR/wm.out")"
  fire_one PreToolUse Bash guard-finalize-publish.sh "$(p_bash "$PUBLISH")"
  [ "$LAST_RC" = 0 ]; rec "(c2) $m gate-dir run: after write-marker the publish is allowed" $? "rc=$LAST_RC out=$LAST_OUT"
  : > "$C_RC"; repo_clean_checks "(c2) $m gate-dir run"; replay

  # setup 2: the ONLY state.md is the agent-written repo copy
  new_case "c2-repo-$m" "$m" seeded
  [ ! -e "$C_GATE/state.md" ]; rec "(c2) $m repo-only run: no gate-dir state.md (precondition)" $?
  fire_one PreToolUse Bash guard-finalize-publish.sh "$(p_bash "$PUBLISH")"
  is_deny && grep -q "plugin session $RUN" <<<"$LAST_OUT"
  rec "(c2) $m repo-only run: unmarked publish denied for the repo seed's session" $? "rc=$LAST_RC out=$LAST_OUT"
  ( umask 077; mkdir -p "$C_GATE/logs" )
  jq -nc --arg cc "$CC" --arg r "$RUN" '{event:"session_start", session_id:$r, cc_session_id:$cc}' > "$C_GATE/logs/$RUN.jsonl"
  write_marker; rc=$?
  [ "$rc" = 0 ] && [ -f "$C_GATE/logs/$RUN.finalize-gate" ]
  rec "(c2) $m repo-only run: write-marker wrote the marker into the gate dir" $? "rc=$rc $(cat "$C_DIR/wm.out")"
  fire_one PreToolUse Bash guard-finalize-publish.sh "$(p_bash "$PUBLISH")"
  [ "$LAST_RC" = 0 ]; rec "(c2) $m repo-only run: after write-marker the publish is allowed" $? "rc=$LAST_RC out=$LAST_OUT"
  : > "$C_RC"; repo_clean_checks "(c2) $m repo-only run"; replay
done

# =================================================================================================
echo "== (c3) a stale gate-dir state.md never hides a newer repo seed =="
for m in sd d1; do
  new_case "c3-$m" "$m" seeded           # repo seed: $RUN, running
  ( umask 077; mkdir -p "$C_GATE/logs" ) && seed_state oldrun complete > "$C_GATE/state.md"
  [ "$(state_md_read)" = "$C_MAIN/.supervisor/state.md" ]
  rec "(c3) $m: lw_state_md_read returns the repo copy over a stale gate copy" $? "$(state_md_read)"
  fire_one PreToolUse Bash guard-finalize-publish.sh "$(p_bash "$PUBLISH")"
  is_deny && grep -q "plugin session $RUN" <<<"$LAST_OUT"
  rec "(c3) $m: publish denied for the NEW session" $? "rc=$LAST_RC out=$LAST_OUT"
  fire "$EV_SUBSTOP" loomwright:loomwright:worker "$(p_sub worker)"
  grep -q "^- session_id: $RUN\$" "$C_GATE/state.md"
  rec "(c3) $m: a worker's subagent stop projected the NEW session into the gate dir" $? "$(grep 'session_id' "$C_GATE/state.md" | tr '\n' ' ')"
  grep -q '"subtask_complete"' "$C_GATE/logs/$RUN.jsonl" 2>/dev/null
  rec "(c3) $m: subtask_complete landed in the gate dir's NEW session log" $?
  [ "$(state_md_read)" = "$C_GATE/state.md" ]
  rec "(c3) $m: lw_state_md_read now returns the gate copy (session ids match)" $? "$(state_md_read)"
  repo_clean_checks "(c3) $m"; replay
done

# =================================================================================================
echo "== (d) off mode is unchanged =="
for fx in seeded bare; do
  new_case "d-$fx" off "$fx"
  if [ "$fx" = seeded ]; then session_events all; else session_events worker; fi
  bad="$(grep -v ' rc=0 ' "$C_RC")"
  [ -z "$bad" ]; rec "(d) $fx: every leaf matched and exited 0" $? "$bad"
  [ "$C_GATE" = "$C_MAIN/.supervisor" ]; rec "(d) $fx: lw_gate_state_dir is <repo>/.supervisor" $? "$C_GATE"
  has_events "$C_REPO/.supervisor" "(d) $fx" "the repo's .supervisor/logs/"
  st="$(git -C "$C_REPO" status --porcelain --ignored)"
  grep -q '\.supervisor/' <<<"$st"; rec "(d) $fx: the repo's .supervisor/ was written, as before" $? "$st"
  [ -f "$C_REPO/.claude/settings.local.json" ]; rec "(d) $fx: the project-local settings file written (telemetry on), as before" $?
  stopfail_line_ok "$C_REPO/.supervisor/logs/failures.log"; rec "(d) $fx: STOP_FAILURE line in the repo failures.log, byte format kept" $?
  [ -z "$(listing "$C_TMP")" ] && [ -z "$(listing "$C_SD")" ]
  rec "(d) $fx: nothing under TMPDIR or the state dir" $? "$(listing "$C_TMP" | tr '\n' ' ')"
  if [ "$fx" = seeded ]; then
    [ "$(seed_state "$RUN" running)" != "$(cat "$C_REPO/.supervisor/state.md")" ]
    rec "(d) seeded: the repo state.md is projected in place, as before" $?
    D_SIG="$(key_sig "$C_REPO/.supervisor/logs")"
  fi
  replay
done
new_case "d-offval" offval seeded
fire StopFailure "" "$STOPFAIL_PAYLOAD"
stopfail_line_ok "$C_REPO/.supervisor/logs/failures.log" && [ -z "$(listing "$C_SD")" ]
rec "(d) LOOMWRIGHT_HOST_MODE=true is OFF: STOP_FAILURE goes to the repo, state dir ignored" $?
replay
[ -n "${A_SIG:-}" ] && [ "${A_SIG:-}" = "${D_SIG:-}" ]
rec "(a)/(d): host-mode JSONL lines carry the same keys per event as off mode (AC2 line format)" $? \
  "$(diff <(printf '%s\n' "${A_SIG:-}") <(printf '%s\n' "${D_SIG:-}") | tr '\n' ' ')"
replay

# =================================================================================================
echo "== (e) mutation control: a hook without its host-mode block fails leg (a) =="
MUT="$BASE/mutant-root"
mkdir -p "$MUT"
cp -R "$PLUGIN_ROOT/scripts" "$PLUGIN_ROOT/hooks" "$PLUGIN_ROOT/.claude-plugin" "$MUT/" 2>/dev/null
M_FILE="$MUT/scripts/emit-agent-identity.sh"
awk '/^if \. .*host-mode\.sh/ { skip = 1; next } skip && /^fi$/ { skip = 0; next } !skip { print }' \
  "$PLUGIN_ROOT/scripts/emit-agent-identity.sh" > "$M_FILE.new" && mv -f "$M_FILE.new" "$M_FILE"
if [ -s "$M_FILE" ] && ! cmp -s "$M_FILE" "$PLUGIN_ROOT/scripts/emit-agent-identity.sh" \
   && bash -n "$M_FILE" 2>/dev/null && ! grep -q 'lw_gate_state_dir' "$M_FILE"; then
  ok "(e) mutant is non-empty, differs from the original, passes bash -n, and no longer resolves through host-mode.sh"
  d="$(diff -rq "$PLUGIN_ROOT/scripts" "$MUT/scripts" 2>&1)"
  [ "$(printf '%s\n' "$d" | grep -c .)" = 1 ] && grep -q 'emit-agent-identity.sh' <<<"$d"
  rec "(e) the scratch plugin root differs from the real one in that one file only" $? "$d"
  replay
  # The exact run "(a) bare" passed above, against the mutant root: its repo-clean check must fail.
  new_case "e-mutant" sd bare "$MUT"
  session_events worker
  host_leg "(e-mutant)" bare
  m_checks="$(cat "$C_CHECKS")"
  m_status="$(git -C "$C_REPO" status --porcelain --ignored)"
  : > "$C_CHECKS"
  grep -q '^FAIL (e-mutant): git status --porcelain --ignored is empty' <<<"$m_checks" \
    && grep -q '\.supervisor/' <<<"$m_status"
  rec "(e) leg (a) FAILS against the mutant: its repo-clean check fails, the repo gained .supervisor/" $? "status: $m_status"
  replay
else
  no "(e) mutant gate failed (empty, identical, bash -n error, or the resolver call survived) — control is void"
fi

# =================================================================================================
helper_ans() {  # helper_ans <fn> <root> — "<rc>|<stdout>" of the real helper for this case
  local o rc
  o="$( cd "$C_REPO" && hm_env bash -c '. "$1" && "$2" "$3"' _ "$PLUGIN_ROOT/scripts/host-mode.sh" "$1" "$2" )"; rc=$?
  printf '%s|%s' "$rc" "$o"
}
use_sd() {  # use_sd <value> — point this case's LOOMWRIGHT_HOST_STATE_DIR at <value>, re-baseline
  C_SD="$1"; C_GATE="$(gate_dir)"; C_SNAP0="$(snap)"
}

echo "== (f) an invalid LOOMWRIGHT_HOST_STATE_DIR is rejected (AC5) =="
for kind in relative missing file inside symlink casesub caseroot; do
  new_case "f-$kind" sd bare
  case "$kind" in case*)
    # a case-variant spelling of the repo (case-insensitive APFS: `REPO` IS `repo`)
    if ! [ "$C_DIR/REPO" -ef "$C_REPO" ]; then
      echo "  skip: (f) $kind — the scratch filesystem is case-sensitive"; continue
    fi ;;
  esac
  case "$kind" in
    casesub)  mkdir -p "$C_REPO/sdin"; use_sd "$C_DIR/REPO/SDIN" ;;
    caseroot) use_sd "$C_DIR/REPO" ;;
    relative) use_sd "state" ;;
    missing)  use_sd "$C_DIR/nope" ;;
    file)     : > "$C_DIR/afile"; use_sd "$C_DIR/afile" ;;
    inside)   mkdir -p "$C_REPO/sdin"; use_sd "$C_REPO/sdin" ;;
    symlink)  mkdir -p "$C_REPO/sdin"; ln -s "$C_REPO/sdin" "$C_DIR/link"; use_sd "$C_DIR/link" ;;
  esac
  a="$(helper_ans lw_host_state_dir "$C_MAIN")"
  [ "$a" = "1|" ]; rec "(f) $kind: lw_host_state_dir rejects it" $? "$a"
  [ "$C_GATE" = "$C_TMP/loomwright-host-$UID_N/$(d1_hash)" ]; rec "(f) $kind: gate state falls back to D1" $? "$C_GATE"
  session_events worker
  repo_clean_checks "(f) $kind"
  case "$kind" in inside|symlink|casesub)
    [ -z "$(listing "$C_REPO/sdin")" ]; rec "(f) $kind: nothing written through the rejected dir" $? ;;
  esac
  s="$(find "$C_TMP" -name failures.log 2>/dev/null)"
  [ -z "$s" ]; rec "(f) $kind: the non-gate failures.log write skipped" $? "$s"
  replay
done

# =================================================================================================
echo "== (g) an unsafe TMPDIR is never the D1 base =="
for kind in relative inside casevar; do
  new_case "g-$kind" d1 bare
  if [ "$kind" = casevar ] && ! [ "$C_DIR/REPO" -ef "$C_REPO" ]; then
    echo "  skip: (g) $kind — the scratch filesystem is case-sensitive"; continue
  fi
  case "$kind" in
    relative) C_TMP="reltmp" ;;
    inside)   mkdir -p "$C_REPO/tmpx"; C_TMP="$C_REPO/tmpx" ;;
    casevar)  mkdir -p "$C_REPO/tmpx"; C_TMP="$C_DIR/REPO/TMPX" ;;
  esac
  C_SNAP0="$(snap)"; C_GATE="$(gate_dir)"
  want="/tmp/loomwright-host-$UID_N/$(d1_hash)"
  [ -d "$want" ] && printf '%s\n' "$want" >> "$BASE/cleanup.list"
  [ "$C_GATE" = "$want" ]; rec "(g) $kind: the gate dir falls back to /tmp/loomwright-host-<uid>/<hash>" $? "$C_GATE"
  fire_one PreToolUse Task guard-arm.sh "$(p_tool PreToolUse Task "$(spawn_input)")"
  [ -f "$want/guard/$CC.json" ]; rec "(g) $kind: the marker landed in the /tmp gate dir" $?
  fire StopFailure "" "$STOPFAIL_PAYLOAD"
  fire "$EV_SUBSTOP" loomwright:loomwright:worker "$(p_sub worker)"
  st="$(git -C "$C_REPO" status --porcelain --ignored 2>&1)"
  [ -z "$st" ] && [ "$(snap)" = "$C_SNAP0" ]; rec "(g) $kind: the repo is untouched" $? "$(printf '%s' "$st" | tr '\n' ' ')"
  bad="$(grep -v ' rc=0 ' "$C_RC")"; [ -z "$bad" ]; rec "(g) $kind: every leaf exited 0" $? "$bad"
  replay
done

# =================================================================================================
echo "== (h) a hostile pre-created D1 root makes the gate dir unresolvable and the guards deny =="
plant_root() {  # plant_root <symlink|mode500|mode777> — replace this case's D1 root with a hostile one
  local top="$C_TMP/loomwright-host-$UID_N"
  chmod -R u+rwx "$top" 2>/dev/null; rm -rf "$top"; mkdir -p "$C_DIR/foreign"
  case "$1" in
    symlink) ln -s "$C_DIR/foreign" "$top" ;;
    mode500) mkdir "$top" && chmod 500 "$top" ;;
    mode777) mkdir "$top" && chmod 777 "$top" ;;
  esac
}
hostile_leg() {  # hostile_leg <kind> <label> — the checks, recorded
  local kind="$1" lbl="$2" a
  plant_root "$kind"
  a="$(helper_ans lw_gate_state_dir "$C_MAIN")"
  [ "$a" = "1|" ]; rec "$lbl: lw_gate_state_dir is unresolvable" $? "$a"
  fire_one PreToolUse Task guard-arm.sh "$(p_tool PreToolUse Task "$(spawn_input)")"
  [ "$LAST_RC" = 0 ]; rec "$lbl: arming still exits 0 (fail-SAFE)" $? "rc=$LAST_RC"
  s="$(find "$C_DIR/foreign" "$C_TMP" -name "$CC.json" 2>/dev/null)"
  [ -z "$s" ]; rec "$lbl: no marker written anywhere" $? "$s"
  fire_one PreToolUse Write guard-test-integrity.sh "$(p_write "$C_MAIN/pytest.ini")"
  is_deny && grep -q 'guard_unavailable' <<<"$LAST_OUT"
  rec "$lbl: a protected edit is DENIED (guard_unavailable), never allowed unguarded" $? "rc=$LAST_RC out=$LAST_OUT"
  fire_one PreToolUse Bash guard-finalize-publish.sh "$(p_bash "$PUBLISH")"
  is_deny && grep -q 'guard_unavailable' <<<"$LAST_OUT"
  rec "$lbl: a publish in the live run is DENIED (guard_unavailable)" $? "rc=$LAST_RC out=$LAST_OUT"
  write_marker; a=$?
  [ "$a" != 0 ] && grep -q 'gate_dir_unresolvable' "$C_DIR/wm.out"
  rec "$lbl: write-marker refuses gate_dir_unresolvable" $? "rc=$a $(cat "$C_DIR/wm.out")"
  : > "$C_RC"
  fire "$EV_SUBSTOP" loomwright:loomwright:worker "$(p_sub worker)"
  fire StopFailure "" "$STOPFAIL_PAYLOAD"
  [ -z "$(listing "$C_DIR/foreign")" ]; rec "$lbl: nothing landed in the foreign dir" $? "$(listing "$C_DIR/foreign" | tr '\n' ' ')"
  repo_clean_checks "$lbl"
}
for kind in symlink mode500 mode777; do
  new_case "h-$kind" d1 seeded
  hostile_leg "$kind" "(h) $kind"
  replay
done

# =================================================================================================
echo "== (i) a linked-worktree session: every caller applies one root rule =="
for where in linked main; do
  new_case "i-$where" sd bare
  WT="$C_DIR/wt"
  ( export HOME="$C_HOME" GIT_CONFIG_NOSYSTEM=1; git -C "$C_REPO" worktree add -q -b side "$WT" ) >/dev/null 2>&1 \
    || { no "(i) $where: fixture worktree add failed"; continue; }
  MAIN_REPO="$C_REPO"
  if [ "$where" = linked ]; then C_SD="$WT/.st"; else C_SD="$MAIN_REPO/.st2"; fi
  mkdir -p "$C_SD"
  C_REPO="$WT"                       # the session runs in the LINKED worktree (project dir = it)
  C_GATE="$(gate_dir)"
  a="$(helper_ans lw_gate_state_dir "$WT")"
  [ "$C_GATE" = "$C_TMP/loomwright-host-$UID_N/$(d1_hash)" ] && [ "$a" = "0|$C_GATE" ]
  rec "(i) $where: main- and linked-anchored callers both resolve the D1 gate dir" $? "main=$C_GATE linked=$a"
  session_events worker
  for r in "$MAIN_REPO" "$WT"; do
    st="$(git -C "$r" status --porcelain --ignored 2>&1)"
    [ -z "$st" ]; rec "(i) $where: $(basename "$r") worktree status clean" $? "$(printf '%s' "$st" | tr '\n' ' ')"
  done
  [ -z "$(listing "$C_SD")" ]; rec "(i) $where: nothing written into the in-worktree state dir" $? "$(listing "$C_SD" | tr '\n' ' ')"
  # session_events ends with SessionEnd (disarm), so arm once more from the linked worktree
  fire_one PreToolUse Task guard-arm.sh "$(p_tool PreToolUse Task "$(spawn_input)")"
  [ -f "$C_GATE/guard/$CC.json" ] && [ -z "$(git -C "$MAIN_REPO" status --porcelain --ignored)" ] && [ -z "$(listing "$C_SD")" ]
  rec "(i) $where: the guard marker is in the shared gate dir, not the state dir" $? "$(listing "$C_SD" | tr '\n' ' ')"
  grep -qs '"agent_identity"' "$C_GATE"/logs/*.jsonl; rec "(i) $where: the emitters' events are in the same gate dir" $?
  replay
done

# =================================================================================================
echo "== (j) check-children-settled.sh reads the gate dir's log under host mode =="
settled_rows() {
  jq -nc --arg r "$RUN" --arg cc "$CC" '{event:"agent_identity", session_id:$r, cc_session_id:$cc, agent_id:"a1", agent_type:"loomwright:worker"}'
  jq -nc --arg r "$RUN" '{event:"subtask_complete", session_id:$r, agent_id:"a1", result_block_present:true}'
}
ccs() {  # ccs <args...> — the .status of check-children-settled.sh under this case's mode, from the repo
  ( cd "$C_REPO" && hm_env bash "$C_ROOT/scripts/check-children-settled.sh" "$@" 2>/dev/null ) | jq -r '.status // empty' 2>/dev/null
}
for m in sd d1; do
  new_case "j-$m" "$m" seeded
  ( umask 077; mkdir -p "$C_GATE/logs" ) && settled_rows > "$C_GATE/logs/$RUN.jsonl"
  st="$(ccs --log ".supervisor/logs/$RUN.jsonl" --agent-id a1)"
  [ "$st" = settled ]; rec "(j) $m: relative repo --log, --agent-id -> settled from the gate dir" $? "$st"
  st="$(ccs --log ".supervisor/logs/$RUN.jsonl" --all)"
  [ "$st" = settled ]; rec "(j) $m: relative repo --log, --all -> settled (not a vacuous no_identity_rows)" $? "$st"
  st="$(ccs --log "$C_MAIN/.supervisor/logs/$RUN.jsonl" --all)"
  [ "$st" = settled ]; rec "(j) $m: absolute main-worktree --log, --all -> settled" $? "$st"
  st="$(ccs --log "$C_GATE/logs/$RUN.jsonl" --all)"
  [ "$st" = settled ]; rec "(j) $m: the gate path itself is read as given" $? "$st"
  repo_clean_checks "(j) $m"; replay
done
# a state dir INSIDE the repo (the repo's own .supervisor) is invalid: the log comes from D1, and the
# check runs under the checker's `set -o pipefail` (the worktree scan must not be flipped by it)
new_case "j-sdin" sd seeded
use_sd "$C_MAIN/.supervisor"
( umask 077; mkdir -p "$C_GATE/logs" ) && settled_rows > "$C_GATE/logs/$RUN.jsonl"
st="$(ccs --log ".supervisor/logs/$RUN.jsonl" --all)"
[ "$st" = settled ] && [ "$C_GATE" = "$C_TMP/loomwright-host-$UID_N/$(d1_hash)" ]
rec "(j) an in-repo state dir is rejected by the checker too: the log is read from D1" $? "st=$st gate=$C_GATE"
replay
# a VALID state dir OUTSIDE the repo that is itself named `.supervisor`: the checker must judge it
# against the real repo root, not the `<outside>` prefix its own path shape suggests
new_case "j-sdout" sd seeded
mkdir -p "$C_DIR/outside/.supervisor"; use_sd "$C_DIR/outside/.supervisor"
( umask 077; mkdir -p "$C_SD/logs" ) && settled_rows > "$C_SD/logs/$RUN.jsonl"
[ "$C_GATE" = "$C_SD" ]; rec "(j) outside .supervisor state dir: it is the gate dir (precondition)" $? "$C_GATE"
st="$(ccs --log "$C_SD/logs/$RUN.jsonl" --all)"
[ "$st" = settled ]; rec "(j) outside .supervisor state dir: its own log path -> settled" $? "$st"
st="$(ccs --log ".supervisor/logs/$RUN.jsonl" --all)"
[ "$st" = settled ]; rec "(j) outside .supervisor state dir: relative repo --log -> settled" $? "$st"
repo_clean_checks "(j) outside .supervisor state dir"; replay
new_case "j-off" off seeded
st="$(ccs --log ".supervisor/logs/$RUN.jsonl" --all)"
[ "$st" = no_identity_rows ]; rec "(j) off: the repo --log is read as given (no repo log -> no_identity_rows, as before)" $? "$st"
replay
NOH="$BASE/nohelper-root"
mkdir -p "$NOH"
cp -R "$PLUGIN_ROOT/scripts" "$PLUGIN_ROOT/hooks" "$PLUGIN_ROOT/.claude-plugin" "$NOH/" 2>/dev/null
rm -f "$NOH/scripts/host-mode.sh"
for m in sd d1; do
  new_case "j-nohelper-$m" "$m" seeded "$NOH"
  st="$(ccs --log ".supervisor/logs/$RUN.jsonl" --all)"
  [ "$st" = unverifiable ]; rec "(j) $m, host-mode.sh unloadable: check-children-settled is unverifiable" $? "$st"
  fire_one PreToolUse Write guard-test-integrity.sh "$(p_write "$C_MAIN/README.md")"
  is_deny && grep -q 'guard_unavailable' <<<"$LAST_OUT"
  rec "(j) $m, host-mode.sh unloadable: guard-test-integrity denies (guard_unavailable)" $? "rc=$LAST_RC out=$LAST_OUT"
  write_marker; a=$?
  [ "$a" != 0 ] && grep -q 'helper_missing' "$C_DIR/wm.out"
  rec "(j) $m, host-mode.sh unloadable: write-marker refuses helper_missing" $? "rc=$a $(cat "$C_DIR/wm.out")"
  fire_one PreToolUse Bash guard-finalize-publish.sh "$(p_bash "$PUBLISH")"
  is_deny; rec "(j) $m, host-mode.sh unloadable: an unmarked publish is denied" $? "rc=$LAST_RC out=$LAST_OUT"
  replay
done

# =================================================================================================
echo "== (k) mutation control: a resolver without the D1 ownership/symlink check fails leg (h) =="
MUT2="$BASE/mutant-d1"
mkdir -p "$MUT2"
cp -R "$PLUGIN_ROOT/scripts" "$PLUGIN_ROOT/hooks" "$PLUGIN_ROOT/.claude-plugin" "$MUT2/" 2>/dev/null
K_FILE="$MUT2/scripts/host-mode.sh"
awk '{ print } /^_lw_private_dir\(\) \{$/ { print "  [ -d \"$1\" ]; return" }' "$PLUGIN_ROOT/scripts/host-mode.sh" > "$K_FILE.new" \
  && mv -f "$K_FILE.new" "$K_FILE"
if [ -s "$K_FILE" ] && ! cmp -s "$K_FILE" "$PLUGIN_ROOT/scripts/host-mode.sh" && bash -n "$K_FILE" 2>/dev/null; then
  ok "(k) mutant host-mode.sh is non-empty, differs from the original and passes bash -n"
  new_case "k-mutant" d1 seeded "$MUT2"
  plant_root symlink
  fire_one PreToolUse Task guard-arm.sh "$(p_tool PreToolUse Task "$(spawn_input)")"
  s="$(find "$C_DIR/foreign" -name "$CC.json" 2>/dev/null)"
  [ -n "$s" ]; rec "(k) against the mutant the marker lands in the foreign dir, so leg (h) would FAIL" $? "$(listing "$C_DIR/foreign" | tr '\n' ' ')"
  replay
else
  no "(k) mutant gate failed (empty, identical, or bash -n error) — control is void"
fi

echo
echo "test-host-mode.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
