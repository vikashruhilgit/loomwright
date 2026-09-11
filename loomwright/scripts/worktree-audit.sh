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
#                     POPULATION GATE: a line is appended ONLY when the log root
#                     already holds a `.supervisor/` directory — the signal that
#                     the plugin has run in that repo. A scratch worktree added in
#                     a repo the plugin never touched is nobody's business: nothing
#                     is written and `.supervisor/` is NEVER created here.
#                     PATH PARSING is whitespace tokenization of the command
#                     string, the path expression RE-JOINED across tokens while
#                     it is still open (unbalanced `(`, an odd `"`/`'`/backtick),
#                     plus one layer of matching quotes — so `"../repo sp"` is
#                     one literal path and `../$(basename $(pwd))-X` one
#                     expression: the payload carries the command UNEXPANDED.
#                     When the path expression still carries shell syntax
#                     (`$VAR`, `${VAR}`, `$(…)`, a backtick, `~`, an unmatched
#                     quote) and git does not list it, the `add` arm falls back
#                     to a BRANCH-keyed lookup — the `-b` argument / the
#                     positional branch tokens are literal — over the porcelain
#                     block whose `branch refs/heads/<branch>` line matches
#                     EXACTLY, and ACCEPTS the hit only when that block's
#                     `worktree <path>` ends with the expression's non-empty
#                     literal tail (`literal_tail`: what follows the last `)`,
#                     `}`, backtick or `$NAME` — `-mine` for
#                     `../$(basename $(pwd))-mine`). Accepted ⇒ `confirmed:true`,
#                     `resolved_by:"branch"`, that path. Rejected (no hit, an
#                     empty tail, or a hit whose path does not end with the
#                     tail — a failed add whose branch is checked out in some
#                     OTHER worktree) ⇒ the expression is recorded as written
#                     with `confirmed:false`, `resolved_by:"path"`, and `branch`
#                     null unless `-b`/`-B` gave one (a positional after an
#                     unresolved expression may be a SHA or a tag). A LITERAL
#                     path git does not list is recorded as written with
#                     `confirmed:false` (the add failed, or resolved against a
#                     `cd` the observer cannot see) and never falls back.
#   note <created|removed> <abs_path> [branch]
#                     direct entry for creations a script performs itself — the
#                     Bash-tool observer only ever sees `bash …/some-script.sh`, so
#                     dispatch-pr-review.sh calls this right after its own
#                     `git worktree add --detach` succeeds. Same line shape,
#                     `source: "direct"`, same population gate. It is also the
#                     hand-run dismissal for a stale entry: `note removed
#                     <abs_path>` from the repo appends a confirmed `removed`
#                     line and the reader stops listing that path.
#   report            read-only. Folds the log by absolute path (last event wins;
#                     an OBSERVED `removed` clears a candidate ONLY when its
#                     `confirmed` is true or null — a FAILED `git worktree remove`
#                     on a dirty tree still fires PostToolUse and must not hide a
#                     live worktree; a `source:"direct"` `removed` — the `note`
#                     entry, a deliberate statement rather than an observed
#                     command that may have failed — clears it regardless, which
#                     is what makes `note removed` the hand-run dismissal),
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
#    "source":"posttooluse_bash"|"direct","resolved_by":"path"|"branch"|null,
#    "command":<matched fragment ≤200 chars>}
#   `confirmed` is GROUND TRUTH AT RECORD TIME: `git worktree list --porcelain`
#   is run and the path's presence (add) / absence (remove) is stored; any git
#   failure stores null. `resolved_by` says how `path` was obtained: `"path"` =
#   parsed from the command / given to `note`; `"branch"` = the add arm's
#   branch-keyed fallback (above); null on `pruned` lines, which have no path
#   and never affect the fold.
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
#   (e) The command string is parsed, never executed, so shell syntax the shell
#       would have expanded is NOT: `$VAR`, `${VAR}`, `$(…)`, backticks, `~`,
#       and a `cd` inside a subshell (`( cd sub && git worktree add ../x … )`
#       resolves against the payload cwd, not `sub`). Whitespace inside
#       matching quotes IS handled — the tokenizer re-joins the expression. The
#       `add` arm recovers the expanded forms through the branch-keyed fallback
#       ONLY when the branch argument is literal AND the porcelain hit's path
#       ends with the expression's non-empty literal tail; a hit that fails the
#       tail rule is dropped, and the line stays `confirmed:false` /
#       `resolved_by:"path"` (test AC-3f: a failed add whose branch lives at
#       `../repo-foreign` never pairs with it). A `remove` with such a path
#       records the expression as written (its `confirmed` is meaningless for a
#       path that never existed) and the live list decides whether the real
#       worktree is still an orphan. Every one of these fails toward
#       UNDER-report: `report` prints only paths git still lists, and the only
#       path the fallback can ever write is one whose porcelain entry ends with
#       a suffix this command literally named.
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

# plugin_present <root> — the population gate: the plugin has run in this repo
# iff `<root>/.supervisor/` already exists. Checked by every writer BEFORE any
# git call or line build; this script never creates `.supervisor/` itself.
plugin_present() { [ -d "$1/.supervisor" ]; }

# unexpanded <token> — true when the token cannot be a literal path because it
# still carries shell syntax the payload never expanded.
unexpanded() {
  case "$1" in *'$'*|*'`'*|'~'*|*\"*|*\'*) return 0 ;; esac
  return 1
}

# expr_open <expr> — true while a whitespace-split path expression is still
# OPEN: more `(` than `)`, or an odd number of `"`, `'` or backticks. The
# tokenizer joins the following token onto the expression while this holds, so
# `../$(basename $(pwd))-mine` and `"../repo sp"` are each ONE path expression
# rather than a path token plus stray positionals (which the branch fallback
# would otherwise try as branch names). Counts are per character on a short
# token, never on the whole command.
expr_open() {
  local s="$1" o c q
  o="${s//[^(]/}"; c="${s//[^)]/}"
  [ "${#o}" -gt "${#c}" ] && return 0
  q="${s//[^\"]/}";  [ $(( ${#q} % 2 )) -eq 1 ] && return 0
  q="${s//[^\']/}";  [ $(( ${#q} % 2 )) -eq 1 ] && return 0
  q="${s//[^\`]/}";  [ $(( ${#q} % 2 )) -eq 1 ] && return 0
  return 1
}

# literal_tail <expr> — the part of an unexpanded path expression the shell
# would have left AS WRITTEN: everything after the last `)`, `}` or backtick;
# then, if a bare `$NAME` remains, everything after that name; a leading
# `~[user]` is cut too. `../$(basename $(pwd))-mine` ⇒ `-mine`;
# `${WT_ROOT}/repo-x` ⇒ `/repo-x`; `$PROJ-BD-1` ⇒ `-BD-1`; `~/wt/repo-x` ⇒
# `/wt/repo-x`; `../$(basename $(pwd))` ⇒ EMPTY. The add arm's branch fallback
# accepts a porcelain hit ONLY when its `worktree <path>` ends with a non-empty
# tail — a failed add whose branch is checked out in some OTHER worktree cannot
# be paired with that worktree, because that path does not end with this
# command's literal suffix.
literal_tail() {
  local t="$1"
  case "$t" in *[\)\}\`]*) t="${t##*[\)\}\`]}" ;; esac
  case "$t" in *'$'*)
    t="${t##*\$}"
    while :; do case "$t" in [A-Za-z0-9_]*) t="${t#?}" ;; *) break ;; esac; done ;;
  esac
  case "$t" in '~'*) t="${t#\~}"; t="${t#"${t%%/*}"}" ;; esac
  printf '%s' "$t"
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

# branch_lookup <git_dir> <candidate>… — the add arm's fallback. Sets
# LOOKUP_PATH / LOOKUP_BRANCH to the porcelain block whose
# `branch refs/heads/<candidate>` line matches the WHOLE line (a branch is
# checked out in at most one worktree, and an exact match cannot pair
# `feature/x` with `feature/x-2`). Candidates are tried in order; first hit wins.
LOOKUP_PATH=""
LOOKUP_BRANCH=""
branch_lookup() {
  local gdir="$1" live rc cand line cur=""
  shift
  LOOKUP_PATH=""; LOOKUP_BRANCH=""
  command -v git >/dev/null 2>&1 || return 0
  live="$(git -C "$gdir" worktree list --porcelain 2>/dev/null)"; rc=$?
  [ "$rc" -eq 0 ] || return 0
  for cand in "$@"; do
    [ -n "$cand" ] || continue
    cur=""
    while IFS= read -r line; do
      case "$line" in
        "worktree "*) cur="${line#worktree }" ;;
        "branch refs/heads/"*)
          if [ "$line" = "branch refs/heads/$cand" ] && [ -n "$cur" ]; then
            LOOKUP_PATH="$cur"; LOOKUP_BRANCH="$cand"; return 0
          fi ;;
      esac
    done <<< "$live"
  done
  return 0
}

# emit <root> <event> <path|""> <branch|""> <confirmed> <session|""> <source> <resolved_by|""> <command>
emit() {
  local root="$1" event="$2" path="$3" branch="$4" confirmed="$5" sid="$6" src="$7" res="$8" cmd="$9"
  local dir="$root/.supervisor/logs" line
  plugin_present "$root" || return 0
  cmd="$(printf '%s' "$cmd" | head -c 200)"
  line="$(jq -nc --arg ts "$(now_ts)" --arg event "$event" --arg path "$path" \
    --arg branch "$branch" --argjson confirmed "$confirmed" --arg sid "$sid" \
    --arg src "$src" --arg res "$res" --arg cmd "$cmd" \
    '{ts:$ts, event:$event,
      path:(if $path == "" then null else $path end),
      branch:(if $branch == "" then null else $branch end),
      confirmed:$confirmed,
      session_id:(if $sid == "" then null else $sid end),
      source:$src,
      resolved_by:(if $res == "" then null else $res end),
      command:$cmd}' 2>/dev/null)"
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
  # optional -C <dir>, repeatable per git: each subsequent RELATIVE -C resolves
  # against the preceding one (`git -C a -C b` ⇒ `a/b`), an absolute one resets.
  while [ "$i" -lt "$n" ] && [ "${toks[$i]}" = "-C" ]; do
    cdir="$(strip_quotes "${toks[$((i+1))]:-}")"
    [ -n "$cdir" ] && base="$(abs_path "$base" "$cdir")"
    i=$((i+2))
  done
  [ "$i" -lt "$n" ] && [ "${toks[$i]}" = "worktree" ] || return 0
  i=$((i+1))
  [ "$i" -lt "$n" ] || return 0
  verb="${toks[$i]}"; i=$((i+1))
  # The log root walks up from the git base — the `-C` dir when one is given,
  # else the payload cwd — so a `git -C <repo> …` run from elsewhere still lands
  # in <repo>'s log, where `report` (run from the repo) will read it.
  local root; root="$(log_root "$base")"
  # Population gate BEFORE the git probe: a repo the plugin never ran in gets
  # no git call, no line, and no `.supervisor/` directory.
  plugin_present "$root" || return 0
  local frag; frag="$(printf '%s' "$seg" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  case "$verb" in
    prune)
      emit "$root" pruned "" "" null "$sid" posttooluse_bash "" "$frag"
      return 0 ;;
    add)
      # The path is the first positional, RE-JOINED across whitespace while the
      # expression is still open (`expr_open`) — `../$(basename $(pwd))-X` is one
      # expression, not `../$(basename` plus a stray `$(pwd))-X` positional.
      # `cands` = branch-keyed fallback candidates: the `-b` argument when given,
      # else every positional after the path expression, in order.
      local -a cands
      local b_flag=0 resolved=path rawpath=""
      while [ "$i" -lt "$n" ]; do
        t="${toks[$i]}"
        case "$t" in
          -b|-B)        branch="$(strip_quotes "${toks[$((i+1))]:-}")"; b_flag=1; i=$((i+2)); continue ;;
          --reason|--orphan-branch) i=$((i+2)); continue ;;
          -*)           i=$((i+1)); continue ;;
        esac
        if [ "$pos" -eq 0 ]; then
          rawpath="$t"; i=$((i+1))
          while [ "$i" -lt "$n" ] && expr_open "$rawpath"; do rawpath="$rawpath ${toks[$i]}"; i=$((i+1)); done
          path="$(strip_quotes "$rawpath")"; pos=1; continue
        fi
        t="$(strip_quotes "$t")"
        [ "$pos" -eq 1 ] && [ -z "$branch" ] && branch="$t"
        cands[${#cands[@]}]="$t"; pos=2
        i=$((i+1))
      done
      [ -n "$path" ] || return 0
      rawpath="$path"
      path="$(abs_path "$base" "$path")"
      probe "$base" "$path" 1
      # Branch-keyed fallback: ONLY for a token the shell would have expanded
      # (a literal path git does not list means the add failed — pairing it
      # with a pre-existing worktree on the same branch would over-report).
      # A hit is ACCEPTED only when its porcelain path ends with the
      # expression's non-empty literal tail: `git worktree add
      # ../$(basename $(pwd))-mine feature/held` fails when feature/held is
      # already checked out at ../repo-foreign, and `repo-foreign` does not end
      # with `-mine` — the hit is rejected and the line stays confirmed:false /
      # resolved_by:"path", the honest under-report.
      if [ "$PROBE_CONFIRMED" = false ] && unexpanded "$rawpath"; then
        local tail; tail="$(literal_tail "$rawpath")"
        if [ "$b_flag" -eq 1 ]; then branch_lookup "$base" "$branch"
        else branch_lookup "$base" ${cands[@]+"${cands[@]}"}; fi
        if [ -n "$LOOKUP_PATH" ] && [ -n "$tail" ]; then
          case "$LOOKUP_PATH" in *"$tail")
            path="$LOOKUP_PATH"; branch="$LOOKUP_BRANCH"; PROBE_CONFIRMED=true; PROBE_BRANCH=""
            resolved=branch ;;
          esac
        fi
        # An unexpanded path the fallback could not resolve has no trustworthy
        # branch: a positional after it may be a SHA, a tag, or (`--detach`)
        # nothing branch-shaped at all. Only an explicit -b/-B survives.
        [ "$resolved" = path ] && [ "$b_flag" -eq 0 ] && branch=""
      fi
      [ -n "$PROBE_BRANCH" ] && branch="$PROBE_BRANCH"
      emit "$root" created "$path" "$branch" "$PROBE_CONFIRMED" "$sid" posttooluse_bash "$resolved" "$frag"
      return 0 ;;
    remove)
      while [ "$i" -lt "$n" ]; do
        t="${toks[$i]}"
        case "$t" in -*) i=$((i+1)); continue ;; esac
        i=$((i+1))
        while [ "$i" -lt "$n" ] && expr_open "$t"; do t="$t ${toks[$i]}"; i=$((i+1)); done
        path="$(strip_quotes "$t")"; break
      done
      [ -n "$path" ] || return 0
      path="$(abs_path "$base" "$path")"
      probe "$base" "$path" 0
      emit "$root" removed "$path" "" "$PROBE_CONFIRMED" "$sid" posttooluse_bash path "$frag"
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
  # Cheapest gate first: the 99.9% non-worktree path pays one `cat` and one
  # substring test on the RAW payload — no jq, no git. Only a payload that
  # mentions `worktree` at all is parsed.
  case "$payload" in *worktree*) ;; *) return 0 ;; esac
  printf '%s' "$payload" | jq -e 'type == "object"' >/dev/null 2>&1 || return 0
  tool="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)"
  [ "$tool" = "Bash" ] || return 0
  cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)"
  [ -n "$cmd" ] || return 0
  grep -qE 'git([[:space:]]+-C[[:space:]]+[^[:space:]]+)*[[:space:]]+worktree[[:space:]]+(add|remove|prune)' <<< "$cmd" || return 0
  cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)"
  sid="$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)"
  [ -n "$cwd" ] || cwd="$PWD"
  cwd="$(abs_path "$PWD" "$cwd")"
  while IFS= read -r seg; do
    [ -n "$seg" ] || continue
    grep -qE 'git([[:space:]]+-C[[:space:]]+[^[:space:]]+)*[[:space:]]+worktree[[:space:]]+(add|remove|prune)' <<< "$seg" || continue
    handle_segment "$seg" "$cwd" "$sid"
  done <<< "$(printf '%s\n' "$cmd" | awk '{ gsub(/&&|[|][|]|;/, "\n"); print }')"
  return 0
}

# ---- note -------------------------------------------------------------------
note() {
  command -v jq >/dev/null 2>&1 || return 0
  local event="${1:-}" path="${2:-}" branch="${3:-}" root expect
  case "$event" in created) expect=1 ;; removed) expect=0 ;; *) return 0 ;; esac
  # A relative path is refused, NOT silently: one line to stderr (never stdout —
  # a hook envelope is built from stdout), nothing appended, still exit 0.
  case "$path" in /*) ;; *) printf 'worktree-audit: note needs an absolute path (got '"'"'%s'"'"')\n' "$path" >&2; return 0 ;; esac
  path="$(abs_path "/" "$path")"
  root="$(log_root "$PWD")"
  plugin_present "$root" || return 0
  probe "$PWD" "$path" "$expect"
  [ -n "$PROBE_BRANCH" ] && branch="$PROBE_BRANCH"
  emit "$root" "$event" "$path" "$branch" "$PROBE_CONFIRMED" "" direct path "note $event"
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
  # A `removed` clears a candidate when it was CONFIRMED (true) or UNPROBEABLE
  # (null), or when it is a DIRECT `note removed` (a deliberate statement — the
  # hand-run dismissal); an observed `removed` with confirmed:false is a failed
  # command and leaves the live list to decide.
  candidates="$(jq -n -R -r '
    [inputs | fromjson? | select(type == "object" and (.event | type) == "string")]
    | reduce .[] as $e ({};
        if ($e.path | type) != "string" then .
        elif $e.event == "created" then .[$e.path] = $e
        elif $e.event == "removed" and ($e.confirmed == true or $e.confirmed == null or $e.source == "direct") then .[$e.path] = $e
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
