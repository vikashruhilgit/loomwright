#!/usr/bin/env bash
# guard-finalize-publish.sh — FINALIZE point 5 by mechanism (automate-followups/33, Part B).
#
# Two modes, one file (so the marker format has exactly one writer and one reader):
#
#   guard-finalize-publish.sh                      PreToolUse[Bash] fail-CLOSED deny gate. Its
#                                                  hooks.json leaf carries NO `|| true` (CLAUDE.md
#                                                  §"Plugin Hooks"; the second fail-CLOSED command
#                                                  hook after guard-test-integrity.sh).
#   guard-finalize-publish.sh write-marker [--skip-children-check] [--expect-id <id>]...
#                                                  The ONLY writer of the finalize-gate marker.
#                                                  Flags in any order; an unknown one refuses
#                                                  (`bad_args`).
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
# EXPECTED IDS (agnostic-phase1/02): the check is run with one `--expect-id` per worker id this run
# recorded — the `### {worker-id} ({subtask-id})` headings and `agent_id:` / `worker_id:` keys under
# state.md's `## Worker Results` (read_worker_result_ids) plus any explicit `--expect-id <id>`
# argument — so a recorded worker with no terminal row refuses `children_unsettled` even when its
# agent_identity row never landed, instead of recording `no_identity_rows`. A `## Worker Results`
# section with content but no readable id (a table, prose) refuses `worker_results_unparsed` (fail
# CLOSED; `--skip-children-check` is the escape). No section / an empty one and no argument ⇒ the
# check runs exactly as before.
# Any other outcome (unsettled / unverifiable / no active session / no HEAD) writes nothing and
# exits 1. HEAD moving after the marker invalidates it: re-run write-marker before every publish
# (Phase 4.5 heal pushes included) — it re-checks the children each time.
#
# WHERE: `.supervisor/` is read from the MAIN worktree (loom_main_root, loom-log-owner.sh — the same
# anchoring build-state.sh and the emitters use, sourced), so a session whose project dir is a LINKED
# worktree still sees the run. HEAD and the current branch are read from the project dir
# (`${CLAUDE_PROJECT_DIR:-$PWD}`) — the checkout the publish runs from.
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

# ---- shared: where `.supervisor/` lives -----------------------------------------------------------
# The MAIN worktree, resolved by loom_main_root — the same place build-state.sh and the emitters write
# it — so a session whose project dir is a LINKED worktree still finds the run's state.md. Falls back
# to the project dir when unresolvable (not a git repo, helper missing).
ROOT=""; STATE_MD=""; LOG_DIR=""
resolve_root() {
  [ "$HELPER_OK" = 1 ] && ROOT="$(loom_main_root "$PROJ" 2>/dev/null)"
  [ -n "$ROOT" ] || ROOT="$PROJ"
  STATE_MD="$ROOT/.supervisor/state.md"
  LOG_DIR="$ROOT/.supervisor/logs"
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

# ---- write-marker: the worker ids this run recorded (no jq) --------------------------------------
# `## Worker Results` is written by an LLM (Context-Keeper's `record_worker_result`), so its shape
# varies between runs. Two shapes are READ; every other non-empty shape is REFUSED by write-marker
# (`worker_results_unparsed`), never read as "no workers" — that would silently restore the
# `no_identity_rows` pass for a run that did spawn workers.
#
# One id per line, from either form (both may appear; duplicates are deduped by the join):
#  (1) HEADING — the first word of every `### {worker-id} ({subtask-id})` heading, the template form;
#      {worker-id} is the worker's Task-returned agent id (the same id the per-subtask `--agent-id`
#      gates join on). `**` / backticks / CR are stripped. A leading LABEL word is tolerated
#      (case-insensitive `worker` / `agent`, optionally followed by `:`, spaced or glued —
#      `### Worker agent-xxx (1)`, `### worker: a0fef8ff (1)`, `### agent:a0fef8ff`): the id is the
#      word after it. Fail direction kept: a label with no id word after it (`### Worker (1)`) and any
#      other unrecognised heading still yields its FIRST word — a recorded heading is never silently
#      dropped (an unmatched expected id refuses; it never passes).
#  (2) KEY — an `agent_id: <id>` or `worker_id: <id>` key (case-insensitive) on any non-table line:
#      a bullet (`- agent_id: a1b2`), a YAML-style continuation line (`  agent_id: a1b2` under
#      `- subtask: 1`), or a pipe-separated bullet (`- **subtask: 1** | agent_id: a1b2 | status: …`).
#      `*` / backticks / quotes / CR are stripped; the key must not be glued to a preceding word
#      character (`parent_agent_id:` is not read); the id ends at whitespace, `|`, `,` or `;`.
# NOT read (deliberately — a parser for every free shape is a parser nobody can review): table rows
# (a line whose first non-blank character is `|`), free prose, and any other key. No section prints
# nothing; worker_results_has_content says whether a section with zero ids must be refused.
read_worker_result_ids() {
  [ -f "$STATE_MD" ] || return 0
  local line in_block=0 tok rest nxt kl
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "## Worker Results"*) in_block=1; continue ;;
      "## "*) [ "$in_block" = 1 ] && break; continue ;;
    esac
    [ "$in_block" = 1 ] || continue
    case "$line" in
      "### "*) ;;
      *)
        # (2) KEY form. A table row is never read (its first non-blank character is `|`).
        kl="$(printf '%s' "$line" | tr -d "\`*\"'\r")"
        kl="${kl#"${kl%%[![:space:]]*}"}"
        case "$kl" in "|"*) continue ;; esac
        kl=" $kl"   # so a key at line start is preceded by a non-word character too
        case "$kl" in
          *[!A-Za-z0-9_][Aa][Gg][Ee][Nn][Tt]_[Ii][Dd]:*) rest="${kl#*[!A-Za-z0-9_][Aa][Gg][Ee][Nn][Tt]_[Ii][Dd]:}" ;;
          *[!A-Za-z0-9_][Ww][Oo][Rr][Kk][Ee][Rr]_[Ii][Dd]:*) rest="${kl#*[!A-Za-z0-9_][Ww][Oo][Rr][Kk][Ee][Rr]_[Ii][Dd]:}" ;;
          *) continue ;;
        esac
        rest="${rest#"${rest%%[![:space:]]*}"}"
        tok="${rest%%[[:space:]|,;]*}"
        [ -n "$tok" ] && printf '%s\n' "$tok"
        continue ;;
    esac
    case "$line" in
      "### "*)
        rest="$(printf '%s' "${line#\#\#\# }" | tr -d '`*\r')"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        tok="${rest%%[[:space:]]*}"
        case "$tok" in
          [Ww][Oo][Rr][Kk][Ee][Rr]|[Ww][Oo][Rr][Kk][Ee][Rr]:|[Aa][Gg][Ee][Nn][Tt]|[Aa][Gg][Ee][Nn][Tt]:)
            nxt="${rest#"$tok"}"
            nxt="${nxt#"${nxt%%[![:space:]]*}"}"
            nxt="${nxt%%[[:space:]]*}"
            case "$nxt" in ""|"("*) ;; *) tok="$nxt" ;; esac ;;
          [Ww][Oo][Rr][Kk][Ee][Rr]:?*|[Aa][Gg][Ee][Nn][Tt]:?*) tok="${tok#*:}" ;;
        esac
        [ -n "$tok" ] && printf '%s\n' "$tok" ;;
    esac
  done < "$STATE_MD"
  return 0
}

# worker_results_has_content — exit 0 when state.md has a `## Worker Results` section carrying any
# line other than blanks and an `(empty)` / `(none)` placeholder (`*` / `_` / backticks stripped, case
# ignored); exit 1 otherwise (no file, no section, or an empty one). write-marker pairs it with a zero
# id count: content that yields no id is a shape this script cannot read, and is refused.
worker_results_has_content() {
  [ -f "$STATE_MD" ] || return 1
  local line in_block=0 t
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "## Worker Results"*) in_block=1; continue ;;
      "## "*) [ "$in_block" = 1 ] && break; continue ;;
    esac
    [ "$in_block" = 1 ] || continue
    t="$(printf '%s' "$line" | tr -d '[:space:]*_`' | tr '[:upper:]' '[:lower:]')"
    case "$t" in ""|"(empty)"|"(none)") ;; *) return 0 ;; esac
  done < "$STATE_MD"
  return 1
}

# ======================================================================================
# write-marker mode
# ======================================================================================
if [ "${1:-}" = "write-marker" ]; then
  refuse() { printf '{"status":"refused","reason":"%s"}\n' "$1"; exit 1; }
  shift
  skip=0; bad_args=0
  EXPECT_ARGS=()   # explicit `--expect-id <id>` args, forwarded verbatim to the join
  # Flags in any order. An unknown argument refuses (`bad_args`) rather than being ignored: a
  # misspelt `--expect-id` silently dropped would pass the check on less evidence than asked for.
  # The refusal is only RECORDED here and issued after the stale marker is removed below, so a
  # refused call never leaves an earlier run's marker in place.
  while [ $# -gt 0 ]; do
    case "$1" in
      --skip-children-check) skip=1; shift ;;
      --expect-id)
        if [ $# -ge 2 ] && [ -n "$2" ]; then
          EXPECT_ARGS[${#EXPECT_ARGS[@]}]="--expect-id"; EXPECT_ARGS[${#EXPECT_ARGS[@]}]="$2"; shift 2
        else
          bad_args=1; break
        fi ;;
      --expect-id=?*) EXPECT_ARGS[${#EXPECT_ARGS[@]}]="--expect-id"; EXPECT_ARGS[${#EXPECT_ARGS[@]}]="${1#--expect-id=}"; shift ;;
      *) bad_args=1; break ;;
    esac
  done
  command -v jq >/dev/null 2>&1 || refuse "jq_missing"
  [ "$HELPER_OK" = 1 ] || refuse "helper_missing"
  resolve_root
  read_session_block || refuse "no_active_session"
  MARKER="$LOG_DIR/$SESSION_ID.finalize-gate"
  SESSION_LOG="$LOG_DIR/$SESSION_ID.jsonl"
  rm -f "$MARKER" 2>/dev/null
  [ -e "$MARKER" ] && refuse "stale_marker_unremovable"
  [ "$bad_args" = 1 ] && refuse "bad_args"
  # HEAD of the session's OWN checkout (the one the publish runs from), not the main worktree's.
  head_sha="$(git -C "$PROJ" rev-parse HEAD 2>/dev/null)"
  [ -n "$head_sha" ] || refuse "no_head"
  if [ "$skip" = 1 ]; then
    check="skipped"; children_status="skipped"
  else
    # check-children-settled.sh reads a missing/unreadable log as `no_identity_rows` (fail-SAFE for
    # its own callers). A gate must not consume that as a pass: no log is no evidence at all.
    [ -f "$SESSION_LOG" ] && [ -r "$SESSION_LOG" ] || refuse "session_log_missing"
    # The ids this run spawned and recorded (`## Worker Results` headings / agent_id: keys) are
    # EXPECTED: each must have a terminal row even when its agent_identity row never landed. No
    # section, or an empty one => no --expect-id => the join runs exactly as before. A section with
    # content but ZERO readable ids is refused (fail CLOSED): reading it as "no workers" would let a
    # run that spawned workers pass as no_identity_rows. Escape: --skip-children-check, after checking.
    worker_ids="$(read_worker_result_ids)"
    [ -n "$worker_ids" ] || ! worker_results_has_content || refuse "worker_results_unparsed"
    while IFS= read -r wid; do
      [ -n "$wid" ] || continue
      EXPECT_ARGS[${#EXPECT_ARGS[@]}]="--expect-id"; EXPECT_ARGS[${#EXPECT_ARGS[@]}]="$wid"
    done <<EOF
$worker_ids
EOF
    # `${arr[@]+…}`: an empty array under `set -u` is an unbound-variable error on bash 3.2
    res="$(bash "$HERE/check-children-settled.sh" --log "$SESSION_LOG" --all ${EXPECT_ARGS[@]+"${EXPECT_ARGS[@]}"} 2>/dev/null)"
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

# (ii) not a live Supervisor run of this repo -> allow (no jq)
resolve_root
read_session_block || allow

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
