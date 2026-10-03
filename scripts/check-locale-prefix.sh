#!/usr/bin/env bash
# check-locale-prefix.sh — CI gate (ratchet): no shell script runs a command under a TEMPORARY
# locale assignment (`LC_ALL=C sort`, `LANG=C grep …`). Write `env LC_ALL=C sort` instead.
#
# WHY: Homebrew bash 5.3 on macOS (the `bash` on PATH, so the one tests and hooks run) SEGFAULTs
# when it disposes a temporary locale assignment inside a forked subshell. Restoring the locale
# after the command calls setlocale() → libintl → CoreFoundation (`dispose_temporary_env →
# sv_locale → reset_locale_vars → libintl_setlocale → CFLocaleCopyPreferredLanguages →
# _os_log_preferences_refresh`), and CoreFoundation is not fork-safe: a few percent of fresh
# `bash script.sh` processes die in the subshell with exit 139 and EMPTY output, which a fail-safe
# reader then reports as a clean answer (setup-memory.sh read_mode printed nothing ⇒ "off").
# Measured with LANG unset, 150 fresh processes per shape: `$(LC_ALL=C sort f; echo x)` 8/150,
# a function doing `LC_ALL=C grep …; echo` called in `$( )` 8/150; the `env LC_ALL=C …` form,
# `export LC_ALL=C`, `local LC_ALL=C` and a plain `LC_ALL=C` statement 0/150 each. /bin/bash 3.2
# never reproduced it, and Linux CI (glibc) cannot.
#
# Whether a given site is exposed depends on bash's exec optimisation: the sole/last command of a
# `$( )` or a single-command pipeline element is exec'd without disposing the temp env, so it
# never crashes, while the same text as a non-last command, inside a function, or under `if`
# does. That is an implementation detail of one bash version, not a contract, so the rule bans
# the shape everywhere rather than trying to tell exposed sites from safe ones.
#
# RULE: in every *.sh / *.bash file in the scanned set (below), a non-comment
# line must not carry a locale assignment (LC_ALL, LC_<CATEGORY>, LANG, LANGUAGE) at COMMAND
# POSITION followed by a command word: line start, after one of | ; & ( { ! or a backtick (so
# `$(` and `<(` too), or after if / elif / while / until / then / do / else / time.
#   offender:  x="$(… | LC_ALL=C sort -u)"     if LC_ALL=C grep -q …     LANG=C tr …
#   allowed:   x="$(… | env LC_ALL=C sort -u)" export LC_ALL=C (script scope, main process)
#              comment lines, and prose such as  echo "… in LC_ALL=C sort order"
# FIX by what follows the prefix:
#   an external command   `env LC_ALL=C cmd` — byte-identical to `LC_ALL=C cmd`: the child gets the
#                         same environment, and bash never touches its own locale.
#   a builtin / function  NOT env — env only execs a binary on PATH (`env LC_ALL=C read` fails, or
#   (read, printf, eval,  runs a separate /usr/bin/read whose result never reaches the shell). Set
#   a shell function)     the locale for the whole shell instead: `export LC_ALL=C` once at script
#                         scope, or as the first statement of the subshell, so it is never restored
#                         (an export inside a subshell measured 0/150).
#
# SCANNED SET = what CI sees. When the root is the top level of a git work tree, the files are
# `git ls-files --cached --others --exclude-standard` (tracked + untracked-but-not-ignored), minus
# index entries deleted from disk, symlinks and gitlinks. A .gitignore'd file is never scanned: a
# CI checkout has none, so a `find` walk made local runs fail on stale salvage copies under the
# ignored .supervisor/ (and, in the main checkout, on every nested ignored git-worktree tree) that CI
# could never see. Untracked-unignored files ARE scanned, so a new script is caught before it is
# staged. Only a root that is not a work-tree top level (a fixture dir, an unpacked tarball) falls
# back to a `find` walk. node_modules/ is dropped in both modes, .git/ in the walk.
#
# FAILS CLOSED (exit 1, no `|| true`) naming every offender as file:line, and on zero scanned
# files (a 0-file run of a fail-closed gate is a false green — mirrors check-test-hermetic.sh).
# Green prints the scanned count; that count is evidence for a PR body, never restated in docs.
#
# usage: check-locale-prefix.sh [--root DIR]   (default: the repo root this script lives in)
# Self-test: scripts/test-check-locale-prefix.sh (offline fixtures + a mutation control).
# Portability: bash 3.2 safe (macOS) + Linux CI. No GNU-only flags, no mapfile, no sed -i.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root) [ "$#" -ge 2 ] || { echo "check-locale-prefix: --root needs a directory" >&2; exit 1; }
            root="$2"; shift 2 ;;
    *) echo "check-locale-prefix: unknown argument: $1" >&2; exit 1 ;;
  esac
done
[ -d "$root" ] || { echo "check-locale-prefix: root is not a directory: $root" >&2; exit 1; }
cd "$root" || exit 1

list="$(mktemp "${TMPDIR:-/tmp}/check-locale-prefix.XXXXXX")" || exit 1
trap 'rm -f "$list" "$list.z"' EXIT
# Git mode only when the root IS the work-tree top level (physical paths: /tmp vs /private/tmp):
# a fixture dir nested inside some other repo, possibly under an ignored path, must not inherit
# that repo's ignore rules and silently scan nothing.
mode=walk
top="$(git rev-parse --show-toplevel 2>/dev/null)" && [ -n "$top" ] \
  && [ "$(cd "$top" && pwd -P)" = "$(pwd -P)" ] && mode=git
if [ "$mode" = git ]; then
  git -c core.quotePath=false ls-files -z --cached --others --exclude-standard -- '*.sh' '*.bash' > "$list.z" \
    || { echo "check-locale-prefix: FAIL — git ls-files failed under $root" >&2; rm -f "$list.z"; exit 1; }
  tr '\0' '\n' < "$list.z" | while IFS= read -r f; do
    case "/$f" in */node_modules/*) continue ;; esac
    [ -f "$f" ] && [ ! -L "$f" ] && printf '%s\n' "$f"
  done | env LC_ALL=C sort -u > "$list"
  rm -f "$list.z"
else
  find . \( -name .git -o -name node_modules \) -prune -o -type f \( -name '*.sh' -o -name '*.bash' \) -print \
    | sed 's#^\./##' | sort > "$list"
fi
total="$(wc -l < "$list" | tr -d ' ')"
if [ "$total" -eq 0 ]; then
  echo "check-locale-prefix: FAIL — no *.sh / *.bash files found under $root ($mode mode; the scan matched nothing)" >&2
  exit 1
fi

# One awk pass per file. The value alternatives cover "quoted", 'quoted' and bare words; the
# assignment run must be followed by a command word (not `#`, `;`, `&`, `|`, `)` or end of line),
# so a plain statement `LC_ALL=C` alone on its line is not an offender (measured 0/150).
offenders="$(while IFS= read -r f; do
  awk -v f="$f" '
    BEGIN {
      v   = "(\"[^\"]*\"|\047[^\047]*\047|[^ \t;&|()\"\047]*)"
      a   = "(LC_[A-Z]+|LANG|LANGUAGE)=" v "[ \t]+"
      pos = "(^|[|;&({!`]|(^|[ \t])(if|elif|while|until|then|do|else|time)[ \t])"
      re  = pos "[ \t]*(" a ")+[^ \t#;&|)]"
    }
    /^[ \t]*#/ { next }
    $0 ~ re { printf "%s:%d: %s\n", f, FNR, $0 }
  ' "$f"
done < "$list")"

if [ -n "$offenders" ]; then
  n="$(printf '%s\n' "$offenders" | wc -l | tr -d ' ')"
  printf '%s\n' "$offenders" | sed 's/^/check-locale-prefix: OFFENDER /' >&2
  echo "check-locale-prefix: FAIL — $n temporary locale assignment(s) at command position in $total scanned shell files." >&2
  echo "  Fix: an external command -> prefix it with env (\`env LC_ALL=C sort\`)." >&2
  echo "       a builtin or shell function (read, printf, eval, a function) -> NOT env (it can only exec a binary);" >&2
  echo "       \`export LC_ALL=C\` once at script scope, or as the subshell's first statement." >&2
  echo "  Why: Homebrew bash 5.3 segfaults restoring the locale in a forked subshell (see this script's header)." >&2
  exit 1
fi
echo "check-locale-prefix: OK — $total/$total scanned shell files ($mode mode) carry no temporary locale assignment at command position"
