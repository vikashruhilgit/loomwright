#!/usr/bin/env bash
# run-pin-mutations.sh — check a brief's `## Pin mutations` rows by script, once per code state.
#
# USAGE
#   run-pin-mutations.sh <brief> [--root <checkout>] [--cache <file>] [--only-paths <glob>...]
#                        [--timeout <secs>]
#
# WHY: since the Pin mutations section exists, the Phase 4.5 reviewer re-applied every row on every
# iteration (PR #533: 16 rows, ~32 suite runs per review). This script does that mechanical work once
# per code state: the Phase 3 deterministic gate runs it after each worker hands back, Phase 4.5 runs it
# at the top of each iteration, and `--cache` skips a row whose files did not change. The reviewer reads
# the verdict lines as DATA and applies a mutation itself only for a row reported `unverified` (the D1
# fallback, agents/code-reviewer.md §5 "Pin mutations").
#
# ROW GRAMMAR (skills/supervisor-readiness/SKILL.md §"Pin mutations" is the authoring rule):
#   Pin cell       its FIRST backticked token is the pin's test file — resolved as written against the
#                  checkout's file list, else by a UNIQUE suffix match (`/<token>`); zero or several
#                  matches ⇒ `unverified (pin_not_found)`. Only `*.sh` pins run (`bash <file>`); any other
#                  pin ⇒ `unverified (unsupported_pin_runner)`.
#   Mutation cell  exactly two machine-applicable forms (text after the path's closing backtick is
#                  ignored, e.g. a trailing "⇒ leg red"):
#                    delete `<literal>` in `<path>`      remove the ONE line containing <literal>
#                    flip `<A>` → `<B>` in `<path>`      replace the ONE occurrence of <A> with <B>
#                                                        (`->` accepted for `→`)
#                  `\|` inside a backticked literal or path reads as `|` (markdown table escaping).
#                  Zero or several matches ⇒ `unverified (mutation_does_not_apply: <n> matches)`; a
#                  target that resolves to no single file ⇒ `unverified (target_not_found)`; any other
#                  wording ⇒ `unverified (not_machine_applicable)`. Literals are matched as FIXED strings
#                  (awk index() over ENVIRON), never as a regex and never through sed/perl interpolation.
#
# PER ROW (the order is the contract): parse → resolve pin + target → cache lookup → count matches →
# build the mutant and VALIDATE it (non-empty, differs from the original, `bash -n` clean for `.sh`,
# `jq empty` clean for `.json`; else `unverified (invalid_mutant: <why>)`) → run the pin UNMUTATED
# (once per distinct pin file per invocation; non-zero ⇒ `unverified (pin_red_unmutated)`) → run it on
# the mutant: non-zero ⇒ `held`, zero ⇒ `not_held`; a run past --timeout ⇒ `unverified (timeout)`.
#
# VERDICTS — the closed set this script owns (prose elsewhere references it, never restates another):
#   held | not_held | unverified (<reason>)
# FAILS CLOSED: any doubt is `unverified`, never `held`.
#
# OUTPUT (stdout, stable): one line per examined row, then one summary line:
#   pin-mutation <n>: <held|not_held|unverified (<reason>)>[ (cached)] — <pin file> :: <mutation cell>
#   pin-mutations: <h> held, <x> not_held, <u> unverified (<c> cached)
# <n> is the row's 1-based position in the section (stable under --only-paths). A brief with no
# `## Pin mutations` section (or a section with no rows) prints `pin-mutations: none`; --only-paths that
# selects no row prints `pin-mutations: none selected`. Both exit 0.
# EXIT: 0 every examined row held (or nothing to examine); 1 any `not_held` (wins over unverified);
#       2 any `unverified` and no `not_held`, and on a usage error / unreadable brief / a --root that is
#       not a git checkout (one `pin-mutations: unverified (<reason>)` line).
#
# SCRATCH: every pin runs in ONE `mktemp -d` copy of the WORKING TREE (`git ls-files --cached --others
# --exclude-standard`, existing files only — so uncommitted and untracked worker edits are included),
# `git init`-ed and committed so a pin that needs a repo has one, and reset (`checkout -f` + `clean -fdx`)
# before every run so one pin's leftovers never reach the next. `HOME`, `XDG_STATE_HOME` and
# `CLAUDE_PROJECT_DIR` are relocated into the scratch dir. Watchdog: no `timeout(1)` (absent on stock
# macOS) — the pin runs in the background, is polled, and on expiry its process tree is TERMed then
# KILLed (run-self-tests.sh's idiom). The checkout is only READ (ls-files, hash-object without -w): its
# working tree, index and `git worktree list` are untouched — also under a caller-exported GIT_DIR /
# GIT_INDEX_FILE / GIT_WORK_TREE (that family is unset before the first git call). The EXIT trap removes
# the scratch dir.
#
# --cache <file>  TSV `row_key<TAB>verdict<TAB>target_hash<TAB>pin_hash`; row_key = git hash of the
#                 trimmed row text, hashes = `git hash-object` of the target and the pin file in the
#                 working tree. A row whose key and BOTH hashes match is not re-run: its previous verdict
#                 prints with ` (cached)`. Only `held` / `not_held` are written (never `unverified`);
#                 entries for rows this run did not examine are kept; the file is written atomically
#                 (temp + mv). Convention used by both callers:
#                 `.supervisor/pin-mutations/<brief basename without .md>.tsv`.
#                 HONEST LIMIT: a pin whose result depends on files other than its target and its own
#                 test file is not re-run when only those files change.
# --only-paths <glob>...  keep only rows whose mutation target path (resolved, else as written) matches a
#                 glob — bash pattern matching where `*` crosses `/`, and a glob ending in `/` is a
#                 directory prefix (the `lanes:` reading). Other rows print nothing. Rows outside the
#                 two forms have no target and are never selected.
# --timeout <s>   per pin run (default 300).
#
# Bash 3.2 / BSD userland safe. Self-test: test-run-pin-mutations.sh.

set -u

out() { printf '%s\n' "$1"; }
die() { out "pin-mutations: unverified ($1)"; exit 2; }

BRIEF=""; ROOT="."; CACHE=""; TIMEOUT=300; HAVE_ONLY=0; ONLY=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) sed -n '2,/^# Bash 3.2/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --root) [ $# -ge 2 ] || die "usage: --root needs a value"; ROOT="$2"; shift 2 ;;
    --cache) [ $# -ge 2 ] || die "usage: --cache needs a value"; CACHE="$2"; shift 2 ;;
    --timeout) [ $# -ge 2 ] || die "usage: --timeout needs a value"; TIMEOUT="$2"; shift 2 ;;
    --only-paths)
      HAVE_ONLY=1; shift
      while [ $# -gt 0 ]; do case "$1" in --*) break ;; esac; ONLY+=("$1"); shift; done ;;
    --*) die "usage: unknown option $1" ;;
    *) [ -z "$BRIEF" ] || die "usage: extra argument $1"; BRIEF="$1"; shift ;;
  esac
done
[ -n "$BRIEF" ] || die "usage: run-pin-mutations.sh <brief> [--root <checkout>] [--cache <file>] [--only-paths <glob>...] [--timeout <secs>]"
case "$TIMEOUT" in ''|*[!0-9]*|0) die "usage: --timeout must be a positive integer" ;; esac
[ -f "$BRIEF" ] && [ -r "$BRIEF" ] || die "brief_unreadable"
# Every git call below names its repo explicitly (`--root`'s checkout, or the scratch copy). A caller's
# exported GIT_DIR / GIT_INDEX_FILE / … would override that and point the scratch copy's init/add/commit
# and checkout/clean (and the pin child) at the CALLER's repo and index — a commit on the caller's branch,
# staged edits in the real index. Cleared once here, so ls-files, sgit and the pin run all inherit none.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE
ROOT_ABS="$(cd "$ROOT" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)" || ROOT_ABS=""
[ -n "$ROOT_ABS" ] && [ -d "$ROOT_ABS" ] || die "root_not_git"

trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }
unesc() { local s="$1" r=""; while :; do case "$s" in *'\|'*) r="$r${s%%\\|*}|"; s="${s#*\\|}" ;; *) break ;; esac; done; printf '%s' "$r$s"; }

# ---- the section's table lines (heading outside a fence; ends at the next `#`/`##` heading) -------
ROWS="$(awk '
  /^[[:space:]]*```/ { fence = !fence; next }
  fence { next }
  /^##?[[:space:]]/ { if (sec) exit; if ($0 ~ /^##[[:space:]]+Pin mutations[[:space:]]*$/) { sec = 1; found = 1 } next }
  sec && /^[[:space:]]*\|/ { print }
  END { if (!found) print "__PM_NO_SECTION__" }
' "$BRIEF" 2>/dev/null)" || die "brief_unreadable"
case "$ROWS" in "__PM_NO_SECTION__"|"") out "pin-mutations: none"; exit 0 ;; esac

SCRATCH=""; CUR_PID=""
cleanup() {
  if [ -n "$CUR_PID" ]; then kill -TERM "$CUR_PID" 2>/dev/null; wait "$CUR_PID" 2>/dev/null; fi
  if [ -n "$SCRATCH" ]; then rm -rf "$SCRATCH"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/run-pin-mutations.XXXXXX" 2>/dev/null)" || SCRATCH=""
[ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] || { SCRATCH=""; die "scratch_failed"; }
mkdir -p "$SCRATCH/home" "$SCRATCH/state" "$SCRATCH/logs" "$SCRATCH/mut"

# The checkout's file list (existing files only): resolution reads it, the scratch copy is made from it.
FILES="$SCRATCH/files.lst"; FILESZ="$SCRATCH/files.z"; : > "$FILES"; : > "$FILESZ"
while IFS= read -r -d '' f; do
  if [ -f "$ROOT_ABS/$f" ] || [ -L "$ROOT_ABS/$f" ]; then printf '%s\n' "$f" >> "$FILES"; printf '%s\0' "$f" >> "$FILESZ"; fi
done < <(git -C "$ROOT_ABS" ls-files -z --cached --others --exclude-standard 2>/dev/null)
[ -s "$FILES" ] || die "root_unreadable"

# resolve <token> — prints the unique repo-relative path for the token, or returns 1.
resolve() {
  local tok="${1#./}"
  [ -n "$tok" ] || return 1
  PM_TOK="$tok" awk '
    BEGIN { t = ENVIRON["PM_TOK"]; s = "/" t; ls = length(s) }
    $0 == t { exact = $0 }
    length($0) > ls && substr($0, length($0) - ls + 1) == s { n++; hit = $0 }
    END { if (exact != "") { print exact; exit 0 } if (n == 1) { print hit; exit 0 } exit 1 }
  ' "$FILES"
}

# count_matches <kind> <literal> <file> — delete: lines containing the literal; flip: occurrences.
count_matches() {
  PM_KIND="$1" PM_A="$2" env LC_ALL=C awk '
    BEGIN { k = ENVIRON["PM_KIND"]; a = ENVIRON["PM_A"]; la = length(a) }
    {
      if (k == "delete") { if (index($0, a)) n++ ; next }
      s = $0
      while ((i = index(s, a)) > 0) { n++; s = substr(s, i + la) }
    }
    END { print n + 0 }
  ' "$3"
}

# build_mutant <kind> <A> <B> <src> <dst> — fixed-string edit of the ONE match; keeps a missing final
# newline missing, so "differs from the original" is never satisfied by a newline alone.
build_mutant() {
  local nonl=0
  if [ -s "$4" ] && [ "$(tail -c 1 "$4" | wc -l | tr -d ' ')" = 0 ]; then nonl=1; fi
  PM_KIND="$1" PM_A="$2" PM_B="$3" PM_NONL="$nonl" env LC_ALL=C awk '
    BEGIN { k = ENVIRON["PM_KIND"]; a = ENVIRON["PM_A"]; b = ENVIRON["PM_B"]; nonl = ENVIRON["PM_NONL"]; n = 0 }
    {
      i = index($0, a)
      if (i && !done) {
        done = 1
        if (k == "delete") next
        $0 = substr($0, 1, i - 1) b substr($0, i + length(a))
      }
      line[++n] = $0
    }
    END { for (j = 1; j <= n; j++) { printf "%s", line[j]; if (j < n || nonl != "1") printf "\n" } }
  ' "$4" > "$5"
}

# validate_mutant <orig> <mutant> <path> — prints the invalid reason, or nothing when valid.
validate_mutant() {
  if [ ! -s "$2" ]; then echo "empty"; return; fi
  if cmp -s "$1" "$2"; then echo "unchanged"; return; fi
  case "$3" in
    *.sh) bash -n "$2" >/dev/null 2>&1 || { echo "bash -n"; return; } ;;
    *.json)
      command -v jq >/dev/null 2>&1 || { echo "jq_missing"; return; }
      jq empty "$2" >/dev/null 2>&1 || { echo "jq empty"; return; } ;;
  esac
}

sgit() { HOME="$SCRATCH/home" GIT_CONFIG_NOSYSTEM=1 git -C "$SCRATCH/tree" -c user.name=pin-mutations -c user.email=pin-mutations@localhost -c commit.gpgsign=false "$@"; }

# prepare_scratch — the ONE working-tree copy per invocation (lazy: a fully cached run makes none).
SCRATCH_READY=0; SCRATCH_BASE=""; SCRATCH_BR=""
prepare_scratch() {
  [ "$SCRATCH_READY" -eq 0 ] || return 0
  SCRATCH_READY=2
  mkdir -p "$SCRATCH/tree" || return 1
  ( cd "$ROOT_ABS" && COPYFILE_DISABLE=1 tar -cf - --null -T "$FILESZ" ) 2>/dev/null \
    | ( cd "$SCRATCH/tree" && tar -xf - ) 2>/dev/null || return 1
  sgit init -q >/dev/null 2>&1 && sgit add -A -f >/dev/null 2>&1 \
    && sgit commit -q --no-verify -m "pin-mutations scratch copy" >/dev/null 2>&1 || return 1
  SCRATCH_BASE="$(sgit rev-parse HEAD 2>/dev/null)" && SCRATCH_BR="$(sgit symbolic-ref --short HEAD 2>/dev/null)" || return 1
  [ -n "$SCRATCH_BASE" ] && [ -n "$SCRATCH_BR" ] || return 1
  SCRATCH_READY=1
}
reset_scratch() { sgit checkout -q -f -B "$SCRATCH_BR" "$SCRATCH_BASE" >/dev/null 2>&1 && sgit clean -q -f -d -x >/dev/null 2>&1; }

descendants() {
  local c
  for c in $(ps -A -o pid= -o ppid= 2>/dev/null | awk -v p="$1" '$2 == p { print $1 }'); do echo "$c"; descendants "$c"; done
}
# run_pin <pin rel path> <log> — sets RUN_RC and RUN_TIMED_OUT. The caller resets the scratch first.
RUN_RC=0; RUN_TIMED_OUT=0
run_pin() {
  local pid start k tree
  RUN_TIMED_OUT=0
  ( cd "$SCRATCH/tree" && exec env HOME="$SCRATCH/home" XDG_STATE_HOME="$SCRATCH/state" \
      CLAUDE_PROJECT_DIR="$SCRATCH/tree" GIT_CONFIG_NOSYSTEM=1 bash "$1" ) > "$2" 2>&1 < /dev/null &
  pid=$!; CUR_PID="$pid"
  start=$SECONDS
  while kill -0 "$pid" 2>/dev/null; do
    if [ $((SECONDS - start)) -ge "$TIMEOUT" ]; then RUN_TIMED_OUT=1; break; fi
    sleep 0.1
  done
  if [ "$RUN_TIMED_OUT" -eq 1 ]; then
    tree="$( { echo "$pid"; descendants "$pid"; } | grep -E '^[0-9]+$')"
    for k in $tree; do kill -TERM "$k" 2>/dev/null; done
    sleep 1
    for k in $tree; do kill -KILL "$k" 2>/dev/null; done
    wait "$pid" 2>/dev/null
    RUN_RC=124
  else
    RUN_RC=0; wait "$pid" || RUN_RC=$?
  fi
  CUR_PID=""
}

# unmutated <pin> — memoised per invocation; sets UNMUT_V = ok | red | timeout | scratch_failed. Called
# in the MAIN shell (never inside $(...)): it may create the scratch copy, whose state must persist.
UNMUT="$SCRATCH/unmutated.tsv"; : > "$UNMUT"; UNMUT_V=""
unmutated() {
  UNMUT_V="$(PM_P="$1" awk -F'\t' '$1 == ENVIRON["PM_P"] { print $2; exit }' "$UNMUT")"
  [ -z "$UNMUT_V" ] || return 0
  if ! prepare_scratch || ! reset_scratch; then UNMUT_V="scratch_failed"
  else
    run_pin "$1" "$SCRATCH/logs/unmutated.log"
    if [ "$RUN_TIMED_OUT" -eq 1 ]; then UNMUT_V="timeout"; elif [ "$RUN_RC" -ne 0 ]; then UNMUT_V="red"; else UNMUT_V="ok"; fi
  fi
  printf '%s\t%s\n' "$1" "$UNMUT_V" >> "$UNMUT"
}

# ---- cache ------------------------------------------------------------------------------------------
CACHE_NEW="$SCRATCH/cache.new"; CACHE_SEEN="$SCRATCH/cache.seen"; : > "$CACHE_NEW"; : > "$CACHE_SEEN"
cache_lookup() {   # <key> <target_hash> <pin_hash> — prints held|not_held, or nothing
  [ -n "$CACHE" ] && [ -f "$CACHE" ] || return 0
  PM_K="$1" PM_T="$2" PM_P="$3" awk -F'\t' '
    NF == 4 && $1 == ENVIRON["PM_K"] && $3 == ENVIRON["PM_T"] && $4 == ENVIRON["PM_P"] \
      && ($2 == "held" || $2 == "not_held") && $3 ~ /^[0-9a-f]+$/ && $4 ~ /^[0-9a-f]+$/ { v = $2 }
    END { if (v != "") print v }
  ' "$CACHE" 2>/dev/null
}

# ---- rows -------------------------------------------------------------------------------------------
H=0; X=0; U=0; C=0; SELECTED=0; idx=0; table_line=0
re_del='^delete `([^`]+)` in `([^`]+)`'
re_flip='^flip `([^`]+)` (->|→) `([^`]+)` in `([^`]+)`'

# fd 3, not stdin: nothing a row runs can swallow the remaining rows.
while IFS= read -r line <&3; do
  table_line=$((table_line + 1))
  [ "$table_line" -gt 1 ] || continue                           # the header row
  inner="$(trim "$line")"; inner="${inner#|}"; inner="${inner%|}"
  case "$(trim "$inner")" in '') continue ;; *[!:\|[:space:]-]*) ;; *) continue ;; esac   # blank / |---|---| rows
  idx=$((idx + 1))
  pin_cell="$(trim "${inner%%|*}")"
  mut_cell="$(trim "${inner#*|}")"
  row_text="$(trim "$line")"

  kind=""; lit_a=""; lit_b=""; tpath=""
  if [[ "$mut_cell" =~ $re_del ]]; then
    kind="delete"; lit_a="$(unesc "${BASH_REMATCH[1]}")"; tpath="$(unesc "${BASH_REMATCH[2]}")"
  elif [[ "$mut_cell" =~ $re_flip ]]; then
    kind="flip"; lit_a="$(unesc "${BASH_REMATCH[1]}")"; lit_b="$(unesc "${BASH_REMATCH[3]}")"; tpath="$(unesc "${BASH_REMATCH[4]}")"
  fi
  target=""
  if [ -n "$kind" ]; then target="$(resolve "$tpath")" || target=""; fi

  if [ "$HAVE_ONLY" -eq 1 ]; then
    [ -n "$kind" ] || continue
    sel_path="${target:-${tpath#./}}"; hit=0
    for g in ${ONLY[@]+"${ONLY[@]}"}; do
      case "$g" in */) g="$g*" ;; esac
      case "$sel_path" in $g) hit=1; break ;; esac
    done
    [ "$hit" -eq 1 ] || continue
  fi
  SELECTED=$((SELECTED + 1))

  pin_tok=""
  case "$pin_cell" in *'`'*'`'*) pin_tok="${pin_cell#*\`}"; pin_tok="$(unesc "${pin_tok%%\`*}")" ;; esac
  pin=""; [ -n "$pin_tok" ] && { pin="$(resolve "$pin_tok")" || pin=""; }
  shown="${pin:-${pin_tok:--}}"

  verdict=""; cached=""; key=""; th=""; ph=""
  if [ -z "$kind" ]; then verdict="unverified (not_machine_applicable)"
  elif [ -z "$pin" ]; then verdict="unverified (pin_not_found)"
  else
    case "$pin" in *.sh) ;; *) verdict="unverified (unsupported_pin_runner)" ;; esac
  fi
  if [ -z "$verdict" ] && [ -z "$target" ]; then verdict="unverified (target_not_found)"; fi

  if [ -z "$verdict" ]; then
    key="$(printf '%s' "$row_text" | git -C "$ROOT_ABS" hash-object --stdin 2>/dev/null)"
    th="$(git -C "$ROOT_ABS" hash-object -- "$target" 2>/dev/null)"
    ph="$(git -C "$ROOT_ABS" hash-object -- "$pin" 2>/dev/null)"
    if [ -n "$key" ] && [ -n "$th" ] && [ -n "$ph" ]; then
      printf '%s\n' "$key" >> "$CACHE_SEEN"
      cv="$(cache_lookup "$key" "$th" "$ph")"
      if [ -n "$cv" ]; then verdict="$cv"; cached=" (cached)"; fi
    fi
  fi

  if [ -z "$verdict" ]; then
    n="$(count_matches "$kind" "$lit_a" "$ROOT_ABS/$target")"
    if [ "$n" != "1" ]; then verdict="unverified (mutation_does_not_apply: $n matches)"; fi
  fi
  if [ -z "$verdict" ]; then
    mutant="$SCRATCH/mut/$idx"
    if ! build_mutant "$kind" "$lit_a" "$lit_b" "$ROOT_ABS/$target" "$mutant"; then verdict="unverified (invalid_mutant: build failed)"
    else
      why="$(validate_mutant "$ROOT_ABS/$target" "$mutant" "$target")"
      [ -z "$why" ] || verdict="unverified (invalid_mutant: $why)"
    fi
  fi
  if [ -z "$verdict" ]; then
    unmutated "$pin"
    case "$UNMUT_V" in
      ok) ;;
      red) verdict="unverified (pin_red_unmutated)" ;;
      timeout) verdict="unverified (timeout)" ;;
      *) verdict="unverified (scratch_failed)" ;;
    esac
  fi
  if [ -z "$verdict" ]; then
    if ! reset_scratch || ! cat "$mutant" > "$SCRATCH/tree/$target"; then verdict="unverified (scratch_failed)"
    else
      run_pin "$pin" "$SCRATCH/logs/mutated.$idx.log"
      mrc="$RUN_RC"
      if [ "$RUN_TIMED_OUT" -eq 1 ]; then verdict="unverified (timeout)"
      elif [ "$mrc" -ne 0 ]; then verdict="held"
      else verdict="not_held"
      fi
    fi
  fi

  case "$verdict" in
    held) H=$((H + 1)) ;;
    not_held) X=$((X + 1)) ;;
    *) U=$((U + 1)) ;;
  esac
  [ -z "$cached" ] || C=$((C + 1))
  case "$verdict" in held|not_held) printf '%s\t%s\t%s\t%s\n' "$key" "$verdict" "$th" "$ph" >> "$CACHE_NEW" ;; esac
  out "pin-mutation $idx: $verdict$cached — $shown :: $mut_cell"
done 3<<EOF_PM_ROWS
$ROWS
EOF_PM_ROWS

if [ "$SELECTED" -eq 0 ]; then
  if [ "$HAVE_ONLY" -eq 1 ] && [ "$idx" -gt 0 ]; then out "pin-mutations: none selected"; else out "pin-mutations: none"; fi
  exit 0
fi

# Cache write: entries this run did not examine are kept; examined ones are replaced by this run's
# held/not_held (an examined row that is now unverified loses its entry). Atomic temp + mv.
if [ -n "$CACHE" ]; then
  cdir="$(dirname "$CACHE")"
  if mkdir -p "$cdir" 2>/dev/null && tmpc="$(mktemp "$cdir/.pin-cache.XXXXXX" 2>/dev/null)"; then
    {
      if [ -f "$CACHE" ]; then
        # FILENAME, not NR == FNR: an empty seen-list would make every cache line read as "seen".
        awk -F'\t' -v seenf="$CACHE_SEEN" 'FILENAME == seenf { seen[$0] = 1; next } NF == 4 && !($1 in seen)' "$CACHE_SEEN" "$CACHE" 2>/dev/null
      fi
      cat "$CACHE_NEW"
    } > "$tmpc" && mv "$tmpc" "$CACHE" || { rm -f "$tmpc"; echo "run-pin-mutations: could not write the cache $CACHE" >&2; }
  else
    echo "run-pin-mutations: could not write the cache $CACHE" >&2
  fi
fi

out "pin-mutations: $H held, $X not_held, $U unverified ($C cached)"
if [ "$X" -gt 0 ]; then exit 1; fi
if [ "$U" -gt 0 ]; then exit 2; fi
exit 0
