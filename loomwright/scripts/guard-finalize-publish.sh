#!/usr/bin/env bash
# guard-finalize-publish.sh — FINALIZE point 5 by mechanism (automate-followups/33, Part B).
#
# Two modes, one file (so the marker format has exactly one writer and one reader):
#
#   guard-finalize-publish.sh                      PreToolUse[Bash] fail-CLOSED deny gate. Its
#                                                  hooks.json leaf carries NO `|| true` (CLAUDE.md
#                                                  §"Plugin Hooks"; the second fail-CLOSED command
#                                                  hook after guard-test-integrity.sh).
#   guard-finalize-publish.sh write-marker [--skip-children-check]
#                                                  The ONLY writer of the finalize-gate marker.
#
# WHY: FINALIZE point 5 (the children-settled check) was a numbered prose step, and a lane ran it
# AFTER pushing and opening its PR — nothing refused that. Now a Supervisor run cannot `git push` /
# `gh pr create` until this script itself has run check-children-settled.sh for the current plugin
# session and HEAD. The marker is written by a script that runs the check, never by prose and never
# by a hand `Write` (which would let the same agent forge it).
#
# MARKER: `.supervisor/logs/<plugin_session_id>.finalize-gate` — keyed by the PLUGIN session id (the
# `## Session` block's `- session_id:` in `.supervisor/state.md`), never the Claude Code UUID:
#   {"children_check":"settled"|"no_identity_rows"|"skipped","children_status":"<join status>","head_sha":"<sha>","ts":"<utc>"}
# write-marker removes any stale marker FIRST, then writes one ONLY when check-children-settled.sh
# --all reads `settled` or `no_identity_rows` (recorded VERBATIM — nothing to check is a pass, never
# evidence of settlement), or when `--skip-children-check` is given (recorded as `skipped`). It
# refuses (`session_log_missing`) when the session log is absent or unreadable: the check reports
# that as `no_identity_rows` for its own fail-SAFE callers, and a gate must not consume it as a pass.
# Any other outcome (unsettled / unverifiable / no active session / no HEAD) writes nothing and
# exits 1. HEAD moving after the marker invalidates it: re-run write-marker before every publish
# (Phase 4.5 heal pushes included) — it re-checks the children each time.
#
# WHERE: `.supervisor/` is read from the MAIN worktree (loom_main_root, loom-log-owner.sh — the same
# anchoring build-state.sh and the emitters use, sourced), so a session whose project dir is a LINKED
# worktree still sees the run. HEAD and the current branch are read from the project dir
# (`${CLAUDE_PROJECT_DIR:-$PWD}`) — the checkout the publish runs from.
#
# HOST MODE (`LOOMWRIGHT_HOST_MODE=1`, host-mode.sh — sourced, the one resolver): the marker and the
# session log (+ its `.owner`) live in `lw_gate_state_dir "$ROOT"`/logs, never the repo; state.md is
# READ via `lw_state_md_read`. The run is LIVE on the UNION (read_live_session): the repo state.md
# (the agent-written seed) OR the gate-dir copy reads running|checkpoint; the session id and branch
# come from the copy that reads live (lw_state_md_read's file when both do). A missing or stale
# gate-dir copy never makes the gate allow. Off: the paths above, unchanged. host-mode.sh failing
# to load with the switch ON denies every publish (`guard_unavailable`) and write-marker refuses
# `helper_missing` — the marker dir is unknowable;
# likewise an unresolvable gate dir (an unsafe/unwritable per-user D1 root, host-mode.sh header)
# denies every publish and write-marker refuses `gate_dir_unresolvable`.
#
# GUARD EVALUATION ORDER (cheap-first; no jq and no fork on the inert path):
#   (i)   raw payload contains neither `push` nor `create`         -> allow
#   (ii)  no `.supervisor/state.md`, no session_id, or status not running|checkpoint
#         (canonical `- status:` or bold `- **status:**`)          -> allow (non-Supervisor / finished)
#   (iii) jq missing / payload unparseable                         -> deny guard_unavailable
#   (iv)  no `git push` / `gh pr create` simple command anywhere in the command string -> allow.
#         Backslash-newlines are joined; segments are cut on && || ; | & ( ) backticks and newlines
#         (so `$(…)`, subshells, `cmd&` cut) — but NOT on the `&` of a redirection operator (`2>&1`,
#         `>&2`, `<&3`, `&>f`, `&>>f`, `>&-`), so `git 2>&1 push` stays one command; words are read
#         quote-aware (`"git"`, `-C "my dir"`, `X="a b"`) and unquoted redirections are dropped
#         whole, operator + fd + target, spaced or glued (`git >/dev/null push`, `git push>log`);
#         then skipped: VAR=x assignments, shell keywords (if/then/do/!/{),
#         wrapper words env/time/nohup/exec/sudo/doas/xargs/nice/timeout/command/builtin and their
#         options; the program's basename is matched (`/usr/bin/git`); git/gh GLOBAL options before
#         the subcommand are walked (`git --no-pager push`, `gh -R o/r pr create`); `bash|sh|zsh|dash|
#         ksh -c <string>` and `eval <words>` are unwrapped (nesting depth <= 3).
#   (v)   the project dir is a DETACHED linked worktree (the review-drain sibling) -> allow; or
#         state.md records a `- branch:` and the checkout is on a different branch -> allow
#   (vi)  session join (below)                                     -> deny unless the marker exists,
#         names children_check settled|no_identity_rows|skipped, and its head_sha equals HEAD.
#
# KNOWN LIMITS (allowed, not detected — the guard is a tripwire for the documented publish steps,
# not a sandbox): a publish behind a variable or alias (`$G push`, `g=git; $g push`, a git alias such
# as `git -c alias.p=push p`, a shell function); a script file (`bash publish.sh`, `make release`);
# other wrappers (`ssh host git push`, `watch`, `parallel`, `caffeinate`, `script`, `env -S "…"`);
# nesting deeper than 3; other publish channels (`gh api …/pulls -X POST`, `git send-pack`, `curl` to
# the API, `hub`); a push from a detached linked worktree; a redirection whose target is itself a
# command substitution (`git >"$(…)" push` is cut at `(`). Splitting inside quotes is deliberate and
# deny-leaning: `git commit -m "a && git push"` is denied, `git commit -m "push it"` is not.
#
# WHICH PUBLISHES ARE GATED (decision): every push from the run's feature-branch checkout while
# `## Session` is running|checkpoint — FINALIZE's push + `gh pr create` AND each Phase 4.5 heal push
# (self-heal-advisory runs write-marker before each one). Inline drains — `/automate`'s owned
# `/review-pr --until-mergeable` drain, its fix-now re-drain, `/autonomous` EVALUATE's review-heal —
# share the Claude Code session but run only after the inner Supervisor's `session_end` made the
# status terminal, so the guard is inert for them by design (their own children never touch the
# finished run's log). If `session_end` never landed (a crashed run), a drain push on the run's
# branch IS gated: run write-marker, or close the stranded run (close-stranded-run.sh).
#
# SESSION JOIN (B2): the plugin session id comes from `.supervisor/state.md`; its log owner is read
# by loom_log_owner (loom-log-owner.sh — the SAME rule emit-lifecycle.sh uses, sourced, never
# restated). Owner == payload `session_id` -> this session's run. Owner empty -> adopt (the shared
# rule's "unknown owner means adopt"). Owner != payload session_id -> a RESUMED run (`/supervisor
# --continue` in a new Claude Code session) of the same checkout: DECISION — still require the marker
# (fail CLOSED), because `--continue` is a documented Supervisor path that also reaches FINALIZE and a
# non-terminal `## Session` block means a run is in flight in THIS checkout. Consequence (accepted): a
# human pushing the run's feature branch from another tab while the run is non-terminal is refused
# too; the escape is `write-marker --skip-children-check`, which records the skip.
#
# DENY MECHANICS: exit 2 AND `hookSpecificOutput.permissionDecision: "deny"` JSON on stdout, one
# stderr line — exactly guard-test-integrity.sh's shape. bash 3.2 / BSD userland safe.
#
# Co-located static suite: test-guard-finalize-publish.sh.
set -u

HERE="${BASH_SOURCE[0]%/*}"
[ "$HERE" = "${BASH_SOURCE[0]}" ] && HERE="."
PROJ="${CLAUDE_PROJECT_DIR:-$PWD}"
REASON_FIRST="run FINALIZE point 5 first"
NL='
'

# The shared rules (main-worktree anchoring + log ownership) — sourced, never restated.
HELPER_OK=0
# shellcheck source=loom-log-owner.sh
. "$HERE/loom-log-owner.sh" 2>/dev/null && HELPER_OK=1
# Host mode (header): HOST_ON is the switch; HOST_HELPER_OK says the resolver loaded.
HOST_HELPER_OK=0; HOST_ON=0
# shellcheck source=host-mode.sh
. "$HERE/host-mode.sh" 2>/dev/null && HOST_HELPER_OK=1
if [ "$HOST_HELPER_OK" = 1 ]; then lw_host_mode && HOST_ON=1
elif [ "${LOOMWRIGHT_HOST_MODE:-}" = "1" ]; then HOST_ON=1; fi

# ---- shared: where `.supervisor/` lives -----------------------------------------------------------
# The MAIN worktree, resolved by loom_main_root — the same place build-state.sh and the emitters write
# it — so a session whose project dir is a LINKED worktree still finds the run's state.md. Falls back
# to the project dir when unresolvable (not a git repo, helper missing).
ROOT=""; STATE_MD=""; LOG_DIR=""; REPO_STATE_MD=""; GATE_STATE_MD=""; GATE_UNRESOLVED=0
resolve_root() {
  [ "$HELPER_OK" = 1 ] && ROOT="$(loom_main_root "$PROJ" 2>/dev/null)"
  [ -n "$ROOT" ] || ROOT="$PROJ"
  STATE_MD="$ROOT/.supervisor/state.md"
  LOG_DIR="$ROOT/.supervisor/logs"
  REPO_STATE_MD="$STATE_MD"; GATE_STATE_MD="$STATE_MD"
  # host mode only: the writers' own resolver (host-mode.sh). Off it would reprint the two paths
  # above, so it is skipped — no forks on the cheap-first guard path.
  if [ "$HOST_HELPER_OK" = 1 ] && [ "$HOST_ON" = 1 ]; then
    if LOG_DIR="$(lw_gate_state_dir "$ROOT")"; then
      LOG_DIR="$LOG_DIR/logs"; GATE_STATE_MD="${LOG_DIR%/logs}/state.md"
      STATE_MD="$(lw_state_md_read "$ROOT")"
    else
      # host mode only: unsafe/unwritable per-user D1 root — the marker dir is unknowable
      LOG_DIR=""; GATE_UNRESOLVED=1
    fi
  fi
}

# ---- shared: the `## Session` block of state.md (no jq) ------------------------------------------
# FORMAT-TOLERANT (as hook-dispatch-on-pr-create.sh): canonical `- status: running` and the bold
# `- **status:** running` / `- **Status:** running` forms. Keys read: session_id, status, branch.
# A state.md with no `## Session` header at all is read by first occurrence of each key in the file.
SESSION_ID=""; SESSION_STATUS=""; SESSION_BRANCH=""
read_session_block() {
  [ -f "$STATE_MD" ] || return 1
  local line val in_block=0 saw=0 b_id="" b_st="" b_br="" a_id="" a_st="" a_br=""
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "## Session"*) saw=1; in_block=1; continue ;;
      "## "*) [ "$in_block" = 1 ] && break; continue ;;
    esac
    line="${line//\*\*/}"
    val="${line#*:}"
    if [ "$in_block" = 1 ]; then
      case "$line" in
        "- "[Ss]"ession_id:"*) [ -n "$b_id" ] || b_id="$val" ;;
        "- "[Ss]"tatus:"*) [ -n "$b_st" ] || b_st="$val" ;;
        "- "[Bb]"ranch:"*) [ -n "$b_br" ] || b_br="$val" ;;
      esac
    elif [ "$saw" = 0 ]; then
      case "$line" in
        "- "[Ss]"ession_id:"*) [ -n "$a_id" ] || a_id="$val" ;;
        "- "[Ss]"tatus:"*) [ -n "$a_st" ] || a_st="$val" ;;
        "- "[Bb]"ranch:"*) [ -n "$a_br" ] || a_br="$val" ;;
      esac
    fi
  done < "$STATE_MD"
  if [ "$saw" = 0 ]; then b_id="$a_id"; b_st="$a_st"; b_br="$a_br"; fi
  SESSION_ID="$(printf '%s' "$b_id" | tr -cd 'A-Za-z0-9_-')"
  SESSION_STATUS="$(printf '%s' "$b_st" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
  SESSION_BRANCH="$(printf '%s' "$b_br" | tr -d '[:space:]')"
  [ -n "$SESSION_ID" ] || return 1
  case "$SESSION_STATUS" in
    running|checkpoint) return 0 ;;
  esac
  return 1
}

# read_live_session — read_session_block on $STATE_MD, plus host mode's UNION (header): when that file
# is not live but the OTHER copy (repo seed vs gate-dir projection) is, the run is still LIVE, and the
# session id AND branch are the LIVE copy's — never the non-live file's. A finished prior run's branch
# must not scope the live run out of the gate (step (v) would allow a push from the live run's own
# branch), and its id must not key the marker or the session-log join. write-marker and the guard both
# call this, so the marker key matches on both sides. $STATE_MD is left on lw_state_md_read's file
# either way. Off: exactly read_session_block.
read_live_session() {
  local keep="$STATE_MD" other rc
  SESSION_ID=""; SESSION_STATUS=""; SESSION_BRANCH=""
  read_session_block && return 0
  [ "$HOST_ON" = 1 ] || return 1
  other="$GATE_STATE_MD"; [ "$keep" = "$GATE_STATE_MD" ] && other="$REPO_STATE_MD"
  [ "$other" != "$keep" ] || return 1
  STATE_MD="$other"; SESSION_ID=""; SESSION_STATUS=""; SESSION_BRANCH=""
  read_session_block; rc=$?
  STATE_MD="$keep"
  return "$rc"
}

# ======================================================================================
# write-marker mode
# ======================================================================================
if [ "${1:-}" = "write-marker" ]; then
  skip=0
  [ "${2:-}" = "--skip-children-check" ] && skip=1
  refuse() { printf '{"status":"refused","reason":"%s"}\n' "$1"; exit 1; }
  command -v jq >/dev/null 2>&1 || refuse "jq_missing"
  [ "$HELPER_OK" = 1 ] || refuse "helper_missing"
  [ "$HOST_ON" = 1 ] && [ "$HOST_HELPER_OK" != 1 ] && refuse "helper_missing"
  resolve_root
  [ "$GATE_UNRESOLVED" = 1 ] && refuse "gate_dir_unresolvable"
  read_live_session || refuse "no_active_session"
  MARKER="$LOG_DIR/$SESSION_ID.finalize-gate"
  SESSION_LOG="$LOG_DIR/$SESSION_ID.jsonl"
  rm -f "$MARKER" 2>/dev/null
  [ -e "$MARKER" ] && refuse "stale_marker_unremovable"
  # HEAD of the session's OWN checkout (the one the publish runs from), not the main worktree's.
  head_sha="$(git -C "$PROJ" rev-parse HEAD 2>/dev/null)"
  [ -n "$head_sha" ] || refuse "no_head"
  if [ "$skip" = 1 ]; then
    check="skipped"; children_status="skipped"
  else
    # check-children-settled.sh reads a missing/unreadable log as `no_identity_rows` (fail-SAFE for
    # its own callers). A gate must not consume that as a pass: no log is no evidence at all.
    [ -f "$SESSION_LOG" ] && [ -r "$SESSION_LOG" ] || refuse "session_log_missing"
    # Host mode runs it from $PROJ: the checker anchors its gate dir on the cwd's repo, which must be
    # the session repo resolve_root anchored on (never wherever the caller's shell happens to be).
    # $HERE may be relative, so the checker's path is made absolute BEFORE the cd. Off: unchanged.
    if [ "$HOST_ON" = 1 ]; then
      ccs="$(cd "$HERE" 2>/dev/null && pwd)/check-children-settled.sh"
      res="$(cd "$PROJ" 2>/dev/null && bash "$ccs" --log "$SESSION_LOG" --all 2>/dev/null)"
    else
      res="$(bash "$HERE/check-children-settled.sh" --log "$SESSION_LOG" --all 2>/dev/null)"
    fi
    children_status="$(printf '%s' "$res" | jq -r '.status // empty' 2>/dev/null)"
    case "$children_status" in
      # recorded verbatim — `no_identity_rows` is a pass, never `settled` (async-orchestration point 5)
      settled|no_identity_rows) check="$children_status" ;;
      *)
        printf '{"status":"refused","reason":"children_%s","children":%s}\n' \
          "${children_status:-unverifiable}" "$(printf '%s' "${res:-null}" | jq -c . 2>/dev/null || echo null)"
        exit 1 ;;
    esac
  fi
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
  [ "$HOST_ON" = 1 ] && umask 077
  mkdir -p "$LOG_DIR" 2>/dev/null || refuse "log_dir_unwritable"
  body="$(jq -n -c --arg c "$check" --arg cs "$children_status" --arg h "$head_sha" --arg t "$ts" \
    '{children_check: $c, children_status: $cs, head_sha: $h, ts: $t}')"
  tmp="$MARKER.tmp.$$"
  { printf '%s\n' "$body" > "$tmp"; } 2>/dev/null && mv -f "$tmp" "$MARKER" 2>/dev/null \
    || { rm -f "$tmp" 2>/dev/null; refuse "marker_write_failed"; }
  printf '%s\n' "$body"
  exit 0
fi

# ======================================================================================
# PreToolUse[Bash] guard mode
# ======================================================================================
json_escape() { local o="$1"; o="${o//\\/\\\\}"; o="${o//\"/\\\"}"; printf '%s' "$o"; }
deny() {
  local msg="finalize_publish_guard: denied — $1"
  printf '%s\n' "$msg" >&2
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$(json_escape "$msg")"
  exit 2
}
allow() { exit 0; }

# builtin read, no fork: the inert path below needs no external program at all
PAYLOAD=""
IFS= read -r -d '' PAYLOAD || true
# (i) cheap substring pre-filter -> allow (no jq, no git)
case "$PAYLOAD" in
  # `*create*`, not `*"pr create"*`: a gh global flag may sit between `pr` and `create`
  *push*|*create*) ;;
  *) allow ;;
esac

# (ii) not a live Supervisor run of this repo -> allow (no jq). Host mode with an unloadable resolver
# cannot tell, so it is never "not live": it falls through and every publish is denied after (iv).
resolve_root
HOST_UNRESOLVED=0
if [ "$HOST_ON" = 1 ] && { [ "$HOST_HELPER_OK" != 1 ] || [ "$GATE_UNRESOLVED" = 1 ]; }; then HOST_UNRESOLVED=1
else read_live_session || allow; fi

# (iii)
command -v jq >/dev/null 2>&1 || deny "guard_unavailable: jq missing"
printf '%s' "$PAYLOAD" | jq -e 'type == "object"' >/dev/null 2>&1 || deny "guard_unavailable: payload unparseable"
CMD="$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.command // empty' 2>/dev/null)"

# (iv) is any simple command a publish?
# A token walk, not a fixed regex: git and gh both accept GLOBAL options between the program and its
# subcommand (`git --no-pager push`, `gh -R o/r pr create`), commands take prefix words (`env`,
# `sudo`, `xargs` …), and shells nest (`bash -c "git push"`, `$(git push)`); a regex that tolerates
# only a named few silently allows the rest. Mirrors guard-test-integrity.sh's git-subcommand walk.

# AMP stands in for an `&` that belongs to a redirection operator (`2>&1`, `>&2`, `<&3`, `&>f`,
# `&>>f`, `>&-`): cmd_has_publish swaps it in BEFORE the segment split, so only a control-operator
# `&` (background) cuts a segment, and tokenize below reads it back as part of the redirection.
AMP=$'\001'
RE_FD='^([0-9]+|[{][A-Za-z_][A-Za-z0-9_]*[}])$'

# tokenize <segment> -> TOK: shell-ish words with quotes removed and quoted spaces kept, so
# `"git"` -> git, `-C "my dir"` -> -C + `my dir`, `X="a b"` -> one assignment word. An unterminated
# quote just ends at the segment end (segments are cut before quotes are read — see split below).
# UNQUOTED redirections are dropped whole, wherever they sit and whether or not they are spaced:
# the operator (`>` `>>` `<` `<<` `<<<` `<>` `>&` `<&` `&>` `&>>`), an fd word glued in front of it
# (`2>`, `{fd}>`), and its target (`/dev/null`, `err.log`, the `1` of `2>&1`, the `-` of `>&-`).
# So `git 2>&1 push`, `git >/dev/null push` and `git push>/dev/null` all read as `git push`.
TOK=()
tokenize() {
  local s="$1" i=0 n="${#1}" c q="" w="" have=0 wq=0 drop=0 op nx
  TOK=()
  while [ "$i" -lt "$n" ]; do
    c="${s:$i:1}"
    if [ -n "$q" ]; then
      if [ "$c" = "$q" ]; then q=""
      elif [ "$q" = '"' ] && [ "$c" = '\' ]; then i=$((i + 1)); w="$w${s:$i:1}"
      elif [ "$c" = "$AMP" ]; then w="$w&"
      else w="$w$c"; fi
    else
      nx="${s:$((i + 1)):1}"
      case "$c" in
        "'"|'"') q="$c"; have=1; wq=1 ;;
        '\') i=$((i + 1)); w="$w${s:$i:1}"; have=1; wq=1 ;;
        ' '|'	')
          if [ "$have" = 1 ]; then
            if [ "$drop" = 1 ]; then drop=0; else TOK[${#TOK[@]}]="$w"; fi
          fi
          w=""; have=0; wq=0 ;;
        '>'|'<'|"$AMP")
          if [ "$c" = "$AMP" ] && [ "$nx" != '>' ]; then
            w="$w&"; have=1             # an AMP not opening `&>`: keep it as a literal `&`
          else
            # a redirection: an unquoted fd word glued in front (`2`, `{fd}`) is dropped with it
            if [ "$have" = 1 ] && [ "$wq" = 0 ] && [[ "$w" =~ $RE_FD ]] && [ "$drop" = 0 ]; then have=0; fi
            if [ "$have" = 1 ]; then
              if [ "$drop" = 1 ]; then drop=0; else TOK[${#TOK[@]}]="$w"; fi
            fi
            w=""; have=0; wq=0
            # read the whole operator: any run of `<` `>` AMP (`>>`, `<<<`, `<>`, `>&`, `&>>` …)
            op="$c"
            while :; do
              nx="${s:$((i + 1)):1}"
              case "$nx" in
                '>'|'<'|"$AMP") op="$op$nx"; i=$((i + 1)) ;;
                *) break ;;
              esac
            done
            drop=1                      # the next word is the redirection's target
            if [ "${op%"$AMP"}" != "$op" ]; then
              # dup/close (`>&1`, `<&3`, `>&-`, `>&3-`): an fd target is glued on; `>&file` (no
              # digits) falls through to the next-word target like `&>file`
              nx="${s:$((i + 1)):1}"
              if [ "$nx" = '-' ]; then i=$((i + 1)); drop=0
              else
                while :; do
                  nx="${s:$((i + 1)):1}"
                  case "$nx" in [0-9]) i=$((i + 1)); drop=0 ;; *) break ;; esac
                done
                if [ "$drop" = 0 ] && [ "${s:$((i + 1)):1}" = '-' ]; then i=$((i + 1)); fi
              fi
            fi
          fi ;;
        *) w="$w$c"; have=1 ;;
      esac
    fi
    i=$((i + 1))
  done
  [ "$have" = 1 ] && [ "$drop" = 0 ] && TOK[${#TOK[@]}]="$w"
  return 0
}

# skip_opts <key> <start idx> — echoes the index of the first non-option word in $words, consuming
# the following value for the value-taking options named per program. `--` ends options.
skip_opts() {
  local key="$1" i="$2"
  while [ "$i" -lt "${#words[@]}" ]; do
    case "$key:${words[$i]}" in
      git:-C|git:-c|git:--git-dir|git:--work-tree|git:--namespace|git:--exec-path|git:--config-env|git:--super-prefix|git:--attr-source)
        i=$((i + 2)) ;;
      gh:-R|gh:--repo|gh:--hostname)
        i=$((i + 2)) ;;
      sudo:-u|sudo:-g|sudo:-h|sudo:-p|sudo:-C|sudo:-D|sudo:-r|sudo:-t|sudo:-U|sudo:-T|sudo:-R|doas:-u|doas:-C)
        i=$((i + 2)) ;;
      env:-u|env:-C|env:--unset|env:--chdir|nice:-n|time:-f|time:-o|exec:-a|timeout:-s|timeout:-k|gtimeout:-s|gtimeout:-k)
        i=$((i + 2)) ;;
      xargs:-I|xargs:-L|xargs:-n|xargs:-P|xargs:-s|xargs:-E|xargs:-d|xargs:-a|xargs:-J|xargs:-R|xargs:-S)
        i=$((i + 2)) ;;
      *:--) i=$((i + 1)); break ;;
      *:--*=*|*:-*)
        i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  printf '%s' "$i"
}

# seg_is_publish <segment> <depth>
seg_is_publish() {
  local depth="$2" i=0 j w prog rest
  tokenize "$1"
  [ "${#TOK[@]}" -gt 0 ] || return 1
  local words=("${TOK[@]}")
  # prefix words: VAR=x assignments, redirections, shell keywords, and wrapper commands
  while [ "$i" -lt "${#words[@]}" ]; do
    w="${words[$i]}"
    case "$w" in
      # (unquoted redirections never reach here — tokenize drops them, operator + target)
      '{'|'!'|if|then|else|elif|do|while|until|nohup|builtin) i=$((i + 1)); continue ;;
      command|exec|time|env|sudo|doas|xargs|nice)
        i="$(skip_opts "$w" $((i + 1)))"; continue ;;
      timeout|gtimeout)
        i="$(skip_opts "$w" $((i + 1)))"; i=$((i + 1)); continue ;;
      eval)
        rest="${words[*]:$((i + 1))}"
        [ "$depth" -lt 3 ] && cmd_has_publish "$rest" $((depth + 1)) && return 0
        return 1 ;;
    esac
    if [[ "$w" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then i=$((i + 1)); continue; fi
    break
  done
  prog="${words[$i]:-}"
  prog="${prog##*/}"            # `/usr/bin/git` -> git
  case "$prog" in
    git)
      i="$(skip_opts git $((i + 1)))"
      [ "${words[$i]:-}" = "push" ] && return 0 ;;
    gh)
      i="$(skip_opts gh $((i + 1)))"
      [ "${words[$i]:-}" = "pr" ] || return 1
      # gh's persistent flags (-R/--repo) are also accepted between `pr` and `create`
      i="$(skip_opts gh $((i + 1)))"
      [ "${words[$i]:-}" = "create" ] && return 0 ;;
    bash|sh|zsh|dash|ksh)
      # unwrap `<shell> [opts] -c <string>` (also -lc / -ec …): the string is a command line
      j=$((i + 1))
      while [ "$j" -lt "${#words[@]}" ]; do
        case "${words[$j]}" in
          --rcfile|--init-file|-o|+o|-O|+O) j=$((j + 2)) ;;
          --*) j=$((j + 1)) ;;
          -*c*)
            [ "$depth" -lt 3 ] && cmd_has_publish "${words[$((j + 1))]:-}" $((depth + 1)) && return 0
            return 1 ;;
          -*|+*) j=$((j + 1)) ;;
          *) return 1 ;;          # a script file: not unwrapped (KNOWN LIMIT)
        esac
      done ;;
  esac
  return 1
}

# cmd_has_publish <command string> <depth> — split into simple-command segments and walk each.
# The split runs BEFORE quotes are read, on && || ; | & ( ) and backticks (so `$(…)`, subshells and
# a background `&` cut cleanly) plus newlines, after joining backslash-newlines. An `&` that belongs
# to a redirection operator (`>&` `<&` `&>`) is first swapped for AMP so it does NOT cut: splitting
# `git 2>&1 push` there would shear the program from its subcommand. `>|` (noclobber override) is
# folded to `>` for the same reason. It also cuts inside quotes: a quoted `a && git push` is then
# treated as a command (deny-leaning, accepted), while a quoted bare word such as `-m "push it"`
# stays an argument.
cmd_has_publish() {
  local s="$1" depth="${2:-0}" sep seg GT='>' LT='<'
  s="${s//\\$NL/ }"
  # replacements are plain variable expansions: bash 3.2 keeps literal quotes in a quoted replacement
  s="${s//">|"/$GT}"
  s="${s//"&&"/$NL}"            # before the redirect swap: `x&&>f` is `x && >f`, never `x & &>f`
  s="${s//">&"/$GT$AMP}"; s="${s//"<&"/$LT$AMP}"; s="${s//"&>"/$AMP$GT}"
  for sep in '&&' '||' ';' '|' '&' '(' ')' '`'; do s="${s//"$sep"/$NL}"; done
  while IFS= read -r seg; do
    seg="${seg#"${seg%%[![:space:]]*}"}"
    [ -n "$seg" ] || continue
    seg_is_publish "$seg" "$depth" && return 0
  done <<EOF
$s
EOF
  return 1
}
cmd_has_publish "$CMD" 0 || allow
[ "$HOST_UNRESOLVED" = 1 ] && deny "guard_unavailable: host-mode.sh missing or gate state dir unresolvable (host mode cannot locate the run's state)"

# (v) scope: only a publish from the run's own feature-branch checkout is this run's publish.
# A DETACHED LINKED worktree (the dispatcher's review-drain sibling, `git push origin HEAD:<ref>`)
# is not the run's checkout -> allow. A checkout on a branch other than the `## Session` block's
# `- branch:` (a drain fix push / human push from another branch) -> allow.
CHECKOUT="$(git -C "$PROJ" rev-parse --path-format=absolute --show-toplevel 2>/dev/null)"
cur_branch="$(git -C "$PROJ" branch --show-current 2>/dev/null)"
[ -z "$cur_branch" ] && [ -n "$CHECKOUT" ] && [ "$CHECKOUT" != "$ROOT" ] && allow
if [ -n "$SESSION_BRANCH" ]; then
  [ -n "$cur_branch" ] && [ "$cur_branch" != "$SESSION_BRANCH" ] && allow
fi

# (vi) session join — reuse THE ownership rule (loom-log-owner.sh), never a restated copy
[ "$HELPER_OK" = 1 ] || deny "guard_unavailable: loom-log-owner.sh missing"
owner="$(loom_log_owner "$LOG_DIR/$SESSION_ID.jsonl" | tr -cd 'A-Za-z0-9_-')"
payload_sid="$(printf '%s' "$PAYLOAD" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9_-')"
# owner == payload_sid: this session's run. owner empty: adopt. owner != payload_sid: a resumed run
# of this checkout — the header's documented DECISION is to require the marker all the same.
# All three paths therefore converge on the marker check below; the join is computed so the deny
# reason names which case fired.
if [ -z "$owner" ] || [ "$owner" = "$payload_sid" ]; then
  join="this session"
else
  join="resumed run (log owner differs)"
fi

MARKER="$LOG_DIR/$SESSION_ID.finalize-gate"
[ -f "$MARKER" ] || deny "$REASON_FIRST (no finalize-gate marker for plugin session $SESSION_ID, $join; run: bash \${CLAUDE_PLUGIN_ROOT}/scripts/guard-finalize-publish.sh write-marker)"
m_check="$(jq -r '.children_check // empty' "$MARKER" 2>/dev/null)"
m_head="$(jq -r '.head_sha // empty' "$MARKER" 2>/dev/null)"
case "$m_check" in
  settled|no_identity_rows|skipped) ;;
  *) deny "$REASON_FIRST (finalize-gate marker unreadable or children_check='$m_check')" ;;
esac
cur_head="$(git -C "$PROJ" rev-parse HEAD 2>/dev/null)"
[ -n "$cur_head" ] && [ "$m_head" = "$cur_head" ] \
  || deny "$REASON_FIRST (HEAD moved since the check: marker ${m_head:-none} != HEAD ${cur_head:-unknown}; re-run write-marker)"
allow
