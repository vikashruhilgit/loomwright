#!/usr/bin/env bash
# worktree-audit.sh — record / note / report for the worktrees THIS PLUGIN creates.
#
# WHY THIS EXISTS (measured 2026-09-11T12:51:30Z, not inferred). Until v15.66.0 the
# plugin shipped `WorktreeCreate` / `WorktreeRemove` hooks that appended the raw
# hook payload to `.supervisor/logs/worktrees.log` and echoed `worktree_path` back
# to the harness. A real `WorktreeCreate` firing was captured and the payload
# carries exactly seven keys — `session_id`, `transcript_path`, `cwd`,
# `scratchpad_dir`, `prompt_id`, `hook_event_name`, `name` — and NO
# `worktree_path` (fixture: fixtures/worktreecreate-real-firing.json, values
# sanitized, key set and order byte-exact). Per the hooks reference a
# `WorktreeCreate` hook REPLACES the harness's own git behavior and must print the
# path of a worktree it created itself; ours created nothing and printed an empty
# line, so every native worktree creation failed with
# `hook succeeded but returned no worktree path`. The log said WORKTREE_CREATED;
# nothing was. Both hooks are gone. This script records the population the plugin
# is actually responsible for — the Supervisor's `../{project}-{subtask}` siblings
# and the review drain's `../{project}-review-{hash}` — through two entry points,
# and reads the result back as an ORPHAN REPORT that defers to git.
#
# ENTRY POINTS (every one ALWAYS exits 0 — this is an emitter/reader, never a gate):
#   record            stdin = a PostToolUse payload (the shape
#                     fixtures/posttooluse-gh-pr-create.json carries). Reads ONLY
#                     `tool_name`, `tool_input.command`, `cwd`, `session_id`. For
#                     every `git [-C <dir>] worktree add|remove|prune …` occurrence
#                     in the command (segments split on `&&`, `||`, `;`, newline)
#                     it appends one JSON line. Non-Bash tools, commands without a
#                     worktree verb, garbage stdin, jq absent ⇒ silent no-op.
#   note <created|removed> <abs_path> [branch]
#                     direct entry for creations a script performs itself — the
#                     Bash-tool observer only ever sees `bash …/some-script.sh`, so
#                     dispatch-pr-review.sh calls this right after its own
#                     `git worktree add --detach` succeeds. Same line shape,
#                     `source: "direct"`.
#   report            read-only. Folds the log by absolute path (last event wins;
#                     a `removed` clears a candidate ONLY when its `confirmed` is
#                     true or null — a FAILED `git worktree remove` on a dirty tree
#                     still fires PostToolUse and must not hide a live worktree),
#                     intersects the `created` survivors with
#                     `git worktree list --porcelain` run from $PWD, and prints one
#                     tab-separated `orphan\t<path>\t<branch|->\t<ts>\t<session|->`
#                     row per candidate that is STILL LIVE. Gone is gone: a path
#                     the log never saw removed but git no longer lists is not an
#                     orphan. Log absent/unreadable, git absent/failing ⇒ prints
#                     nothing. It never removes anything; salvage is a human's.
#
# LINE SHAPE (one JSON object per line, built with `jq -n --arg` only — never
# string-interpolated — so a path or command can never break the log):
#   {"ts","event":"created|removed|pruned","path":<abs>|null,"branch":<name>|null,
#    "confirmed":true|false|null,"session_id":<id>|null,
#    "source":"posttooluse_bash"|"direct","command":<matched fragment ≤200 chars>}
#   `confirmed` is GROUND TRUTH AT RECORD TIME: `git worktree list --porcelain`
#   is run and the path's presence (add) / absence (remove) is stored; any git
#   failure stores null. `pruned` lines have no path and never affect the fold.
#
# LOG LOCATION: `<log-root>/.supervisor/logs/worktrees.log`, where <log-root> is
# found WITHOUT git — walk up from the git base (record: the `-C <dir>` when one
# is given, else the payload `cwd`; note/report: $PWD) to the nearest directory
# containing a `.git` entry, FILE OR DIRECTORY
# (a linked worktree's `.git` is a file), falling back to the start directory.
# Writer and reader share the walk, so they always agree; `--show-toplevel` vs
# `--git-common-dir` divergence never enters. Legacy `[ts] WORKTREE_CREATED {…}`
# lines in an existing log are non-JSON and are skipped by the reader.
#
# HONEST LIMITS (documented, not engineered around):
#   (a) A hard kill (SIGKILL, power loss) between the git call and the hook skips
#       in-process recording, so the log can never be complete. It is a
#       RECONCILIATION INPUT; `git worktree list` is the ground truth, and
#       `report` is written so that the log can only ever under-report.
#   (b) The observer sees only literal `git worktree …` commands executed through
#       the Bash tool. A creation inside a script is invisible to it and needs the
#       `note` entry point — the review-drain dispatcher is wired; any future
#       script that creates a worktree must wire itself.
#   (c) Native harness worktrees (agent isolation, `--worktree`, background
#       sessions) are the harness's own population, created AND removed by it,
#       and are deliberately NOT logged — observing a native create would require
#       the plugin to become a VCS provider again, which is exactly the defect.
#   (d) Hooks come from the INSTALLED plugin: the fixed hook set only takes effect
#       in sessions started after a reinstall.
#
# Vendor-neutral by construction (CORE, allowance 0): no harness env var, no
# harness-specific path, siblings resolved via `dirname "$0"`. bash 3.2-clean.

# Never `set -e`/`set -u`: an emitter that dies is a gate.
set +e

now_ts() { date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf 'unknown'; }

# log_root <start_dir> — nearest ancestor (inclusive) holding a `.git` entry.
log_root() {
  local d="$1"
  case "$d" in /*) ;; *) d="$PWD/$d" ;; esac
  d="$(cd "$d" 2>/dev/null && pwd -P)" || d="$1"
  local cur="$d"
  while [ -n "$cur" ] && [ "$cur" != "/" ]; do
    if [ -e "$cur/.git" ]; then printf '%s' "$cur"; return 0; fi
    cur="$(dirname "$cur")"
  done
  printf '%s' "$d"
}

# lexical_norm <path> — collapse `.`/`..`/`//` without touching the filesystem.
lexical_norm() {
  local in="$1" out="" seg
  local IFS='/'
  set -f
  # shellcheck disable=SC2086
  set -- $in
  set +f
  for seg in "$@"; do
    case "$seg" in
      ''|.) ;;
      ..)   out="${out%/*}" ;;
      *)    out="$out/$seg" ;;
    esac
  done
  printf '%s' "${out:-/}"
}

# abs_path <base_abs> <path> — absolute; canonical (`pwd -P`) when the directory
# exists, lexical otherwise (a just-removed worktree no longer exists).
abs_path() {
  local base="$1" p="$2" joined canon
  case "$p" in /*) joined="$p" ;; *) joined="$base/$p" ;; esac
  if [ -d "$joined" ]; then
    canon="$(cd "$joined" 2>/dev/null && pwd -P)"
    if [ -n "$canon" ]; then printf '%s' "$canon"; return 0; fi
  fi
  lexical_norm "$joined"
}

# strip_quotes <token> — one layer of matching single or double quotes.
strip_quotes() {
  local t="$1"
  case "$t" in
    \"*\") [ "${#t}" -ge 2 ] && t="${t#\"}" && t="${t%\"}" ;;
    \'*\') [ "${#t}" -ge 2 ] && t="${t#\'}" && t="${t%\'}" ;;
  esac
  printf '%s' "$t"
}

# probe <git_dir> <abs_path> <expect_present:1|0> — sets PROBE_CONFIRMED to
# true|false|null and PROBE_BRANCH to the live `branch refs/heads/…` (or empty).
PROBE_CONFIRMED=null
PROBE_BRANCH=""
probe() {
  local gdir="$1" want="$2" expect="$3" live rc present=0 line cur=""
  PROBE_CONFIRMED=null; PROBE_BRANCH=""
  command -v git >/dev/null 2>&1 || return 0
  live="$(git -C "$gdir" worktree list --porcelain 2>/dev/null)"; rc=$?
  [ "$rc" -eq 0 ] || return 0
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) cur="${line#worktree }"; [ "$cur" = "$want" ] && present=1 ;;
      "branch refs/heads/"*) [ "$cur" = "$want" ] && PROBE_BRANCH="${line#branch refs/heads/}" ;;
    esac
  done <<< "$live"
  if [ "$expect" -eq 1 ]; then
    [ "$present" -eq 1 ] && PROBE_CONFIRMED=true || PROBE_CONFIRMED=false
  else
    [ "$present" -eq 0 ] && PROBE_CONFIRMED=true || PROBE_CONFIRMED=false
  fi
  return 0
}

# emit <root> <event> <path|""> <branch|""> <confirmed> <session|""> <source> <command>
emit() {
  local root="$1" event="$2" path="$3" branch="$4" confirmed="$5" sid="$6" src="$7" cmd="$8"
  local dir="$root/.supervisor/logs" line
  cmd="$(printf '%s' "$cmd" | head -c 200)"
  line="$(jq -nc --arg ts "$(now_ts)" --arg event "$event" --arg path "$path" \
    --arg branch "$branch" --argjson confirmed "$confirmed" --arg sid "$sid" \
    --arg src "$src" --arg cmd "$cmd" \
    '{ts:$ts, event:$event,
      path:(if $path == "" then null else $path end),
      branch:(if $branch == "" then null else $branch end),
      confirmed:$confirmed,
      session_id:(if $sid == "" then null else $sid end),
      source:$src, command:$cmd}' 2>/dev/null)"
  [ -n "$line" ] || return 0
  mkdir -p "$dir" 2>/dev/null || return 0
  printf '%s\n' "$line" >> "$dir/worktrees.log" 2>/dev/null || true
  return 0
}

# handle_segment <segment> <cwd_abs> <session_id> — one command segment; emits a
# line for each `git [-C d] worktree add|remove|prune` it carries (at most one
# per segment since a segment has one verb).
handle_segment() {
  local seg="$1" cwd="$2" sid="$3"
  local -a toks
  read -ra toks <<< "$seg" 2>/dev/null || return 0
  local n="${#toks[@]}" i=0 t base="$cwd" cdir="" verb="" path="" branch="" pos=0
  [ "$n" -gt 0 ] || return 0
  # locate `git`
  while [ "$i" -lt "$n" ]; do
    [ "${toks[$i]}" = "git" ] && break
    i=$((i+1))
  done
  [ "$i" -lt "$n" ] || return 0
  i=$((i+1))
  # optional -C <dir> (repeatable per git; last wins, resolved against cwd)
  while [ "$i" -lt "$n" ] && [ "${toks[$i]}" = "-C" ]; do
    cdir="$(strip_quotes "${toks[$((i+1))]:-}")"
    i=$((i+2))
  done
  [ -n "$cdir" ] && base="$(abs_path "$cwd" "$cdir")"
  [ "$i" -lt "$n" ] && [ "${toks[$i]}" = "worktree" ] || return 0
  i=$((i+1))
  [ "$i" -lt "$n" ] || return 0
  verb="${toks[$i]}"; i=$((i+1))
  # The log root walks up from the git base — the `-C` dir when one is given,
  # else the payload cwd — so a `git -C <repo> …` run from elsewhere still lands
  # in <repo>'s log, where `report` (run from the repo) will read it.
  local root; root="$(log_root "$base")"
  local frag; frag="$(printf '%s' "$seg" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  case "$verb" in
    prune)
      emit "$root" pruned "" "" null "$sid" posttooluse_bash "$frag"
      return 0 ;;
    add)
      while [ "$i" -lt "$n" ]; do
        t="${toks[$i]}"
        case "$t" in
          -b|-B)        branch="$(strip_quotes "${toks[$((i+1))]:-}")"; i=$((i+2)); continue ;;
          --reason|--orphan-branch) i=$((i+2)); continue ;;
          -*)           i=$((i+1)); continue ;;
        esac
        t="$(strip_quotes "$t")"
        if [ "$pos" -eq 0 ]; then path="$t"; pos=1
        elif [ "$pos" -eq 1 ]; then [ -n "$branch" ] || branch="$t"; pos=2
        fi
        i=$((i+1))
      done
      [ -n "$path" ] || return 0
      path="$(abs_path "$base" "$path")"
      probe "$base" "$path" 1
      [ -n "$PROBE_BRANCH" ] && branch="$PROBE_BRANCH"
      emit "$root" created "$path" "$branch" "$PROBE_CONFIRMED" "$sid" posttooluse_bash "$frag"
      return 0 ;;
    remove)
      while [ "$i" -lt "$n" ]; do
        t="${toks[$i]}"
        case "$t" in -*) i=$((i+1)); continue ;; esac
        path="$(strip_quotes "$t")"; break
      done
      [ -n "$path" ] || return 0
      path="$(abs_path "$base" "$path")"
      probe "$base" "$path" 0
      emit "$root" removed "$path" "" "$PROBE_CONFIRMED" "$sid" posttooluse_bash "$frag"
      return 0 ;;
    *) return 0 ;;
  esac
}

# ---- record -----------------------------------------------------------------
# Every payload read below is a `jq -r '<program>'` on its own line: the test
# extracts those programs from THIS function body and asserts each path is one
# of .tool_name / .tool_input.command / .cwd / .session_id — the fields shown to
# exist on a real PostToolUse[Bash] payload — and nothing else.
record() {
  command -v jq >/dev/null 2>&1 || return 0
  local payload tool cmd cwd sid seg
  payload="$(cat 2>/dev/null)"
  [ -n "$payload" ] || return 0
  printf '%s' "$payload" | jq -e 'type == "object"' >/dev/null 2>&1 || return 0
  tool="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)"
  [ "$tool" = "Bash" ] || return 0
  cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)"
  [ -n "$cmd" ] || return 0
  # Cheapest gate first: the 99.9% non-worktree path pays one grep and no git.
  grep -qE 'git( -C [^ ]+)? worktree (add|remove|prune)' <<< "$cmd" || return 0
  cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)"
  sid="$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)"
  [ -n "$cwd" ] || cwd="$PWD"
  cwd="$(abs_path "$PWD" "$cwd")"
  while IFS= read -r seg; do
    [ -n "$seg" ] || continue
    grep -qE 'git( -C [^ ]+)? worktree (add|remove|prune)' <<< "$seg" || continue
    handle_segment "$seg" "$cwd" "$sid"
  done <<< "$(printf '%s\n' "$cmd" | awk '{ gsub(/&&|[|][|]|;/, "\n"); print }')"
  return 0
}

# ---- note -------------------------------------------------------------------
note() {
  command -v jq >/dev/null 2>&1 || return 0
  local event="${1:-}" path="${2:-}" branch="${3:-}" root expect
  case "$event" in created) expect=1 ;; removed) expect=0 ;; *) return 0 ;; esac
  case "$path" in /*) ;; *) return 0 ;; esac
  path="$(abs_path "/" "$path")"
  root="$(log_root "$PWD")"
  probe "$PWD" "$path" "$expect"
  [ -n "$PROBE_BRANCH" ] && branch="$PROBE_BRANCH"
  emit "$root" "$event" "$path" "$branch" "$PROBE_CONFIRMED" "" direct "note $event"
  return 0
}

# ---- report -----------------------------------------------------------------
report() {
  command -v jq >/dev/null 2>&1 || return 0
  command -v git >/dev/null 2>&1 || return 0
  local root log candidates live rc line path branch ts sid cur
  root="$(log_root "$PWD")"
  log="$root/.supervisor/logs/worktrees.log"
  [ -r "$log" ] || return 0
  # Fold in ONE jq pass: garbage / legacy / event-less lines vanish via fromjson?.
  candidates="$(jq -n -R -r '
    [inputs | fromjson? | select(type == "object" and (.event | type) == "string")]
    | reduce .[] as $e ({};
        if ($e.path | type) != "string" then .
        elif $e.event == "created" then .[$e.path] = $e
        elif $e.event == "removed" and ($e.confirmed == true or $e.confirmed == null) then .[$e.path] = $e
        else . end)
    | [.[] | select(.event == "created")]
    | .[] | [.path, (if (.branch|type) == "string" then .branch else "-" end),
             (if (.ts|type) == "string" then .ts else "-" end),
             (if (.session_id|type) == "string" then .session_id else "-" end)]
    | @tsv' "$log" 2>/dev/null)"
  [ -n "$candidates" ] || return 0
  live="$(git worktree list --porcelain 2>/dev/null)"; rc=$?
  [ "$rc" -eq 0 ] || return 0
  # The live-list intersection: a candidate git no longer lists is NOT an orphan.
  while IFS=$'\t' read -r path branch ts sid; do
    [ -n "$path" ] || continue
    cur=0
    while IFS= read -r line; do
      [ "$line" = "worktree $path" ] && { cur=1; break; }
    done <<< "$live"
    [ "$cur" -eq 1 ] || continue
    printf 'orphan\t%s\t%s\t%s\t%s\n' "$path" "$branch" "$ts" "$sid"
  done <<< "$candidates"
  return 0
}

case "${1:-}" in
  record) record ;;
  note)   shift; note "$@" ;;
  report) shift; report "$@" ;;
  *) ;;
esac
exit 0
