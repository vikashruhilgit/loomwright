#!/usr/bin/env bash
# check-mkdir-lock.sh — CI gate: the `mkdir` command is never the test of a lock.
#
# WHY: uutils `mkdir`, the default on Ubuntu 26.04 and `ubuntu-latest`, exits 0 when mkdir(2) returns
# EEXIST and the path is a directory, even without -p. Two racers can both "win" a bare `mkdir` lock.
# Measured on a runner: 24 double wins in 4000 two-way races, 0 in 4000 for a bash noclobber create.
# A lock is `( set -C; : > "$lock" )` (O_EXCL, in bash itself). A lock that keeps a directory because
# its readers need one is held by the O_EXCL create of its stamp file inside that directory.
#
# RULE: a non-recursive `mkdir` command in a shipped script fails this gate unless the same line, or
# the line above it, carries `# mkdir-ok: <why exclusivity does not matter here>`. `mkdir -p` passes,
# because it cannot be a test of anything. So a NEW lock cannot slip in by accident, and every site
# that remains says why it is safe where a reader will see it.
#
# COVERS: every tracked file under loomwright/scripts/ and scripts/ except self-tests (test-*, and
# files under a test-*.d/ dir) and fixtures/. Tests build older-build lock directories on purpose.
# Comment lines and trailing comments are not code, so prose about `mkdir` never trips it.
#
# FAILS CLOSED (exit 1, naming every offender), including on zero files covered: a 0-file run of a
# fail-closed gate is a false green.
#
# usage: check-mkdir-lock.sh [--root DIR]   (default: the repo root this script lives in)
# Self-test: scripts/test-check-mkdir-lock.sh (offline fixtures, including a control on the real tree).
# Portability: bash 3.2 safe (macOS) + Linux CI. No GNU-only flags, no mapfile, no sed -i.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ "${1:-}" = "--root" ]; then
  [ "$#" -ge 2 ] || { echo "check-mkdir-lock: --root needs a value" >&2; exit 2; }
  ROOT="$2"
fi
cd "$ROOT" || { echo "check-mkdir-lock: cannot enter $ROOT" >&2; exit 1; }

# A file list from git when ROOT is a checkout, else from find (the self-test's plain fixture trees).
list_files() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    { git ls-files -- loomwright/scripts scripts; git ls-files -o --exclude-standard -- loomwright/scripts scripts; }
  else
    find loomwright/scripts scripts -type f 2>/dev/null
  fi
}

covered=0; bad=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  case "/$f" in
    */fixtures/*|*/test-*) continue ;;
  esac
  env LC_ALL=C grep -Iq . "$f" 2>/dev/null || continue   # binary or empty
  covered=$((covered + 1))
  out="$(env LC_ALL=C awk -v F="$f" '
    function code(l) {                         # the line without a trailing or whole-line comment
      sub(/^[ \t]*#.*/, "", l)
      gsub(/[ \t]#.*$/, "", l)
      return l
    }
    {
      c = code($0)
      # the word mkdir as a command: at the start, after a separator or a path, or after a keyword
      if (c ~ /(^|[;&|({!`]|\$\(|\/)[ \t]*mkdir([ \t]|$)/ ||
          c ~ /(^|[ \t;&|({])(if|then|else|elif|do|while|until|command|exec|xargs|sudo|env|time)[ \t]+mkdir([ \t]|$)/) {
        s = c
        sub(/^.*mkdir/, "", s)
        # recursive when a -p (alone or in a flag cluster) or --parents comes before the first operand
        recursive = 0
        n = split(s, w, /[ \t]+/)
        for (i = 1; i <= n; i++) {
          if (w[i] == "") continue
          if (w[i] ~ /^--parents$/ || w[i] ~ /^-[a-zA-Z]*p[a-zA-Z]*$/) { recursive = 1; break }
          if (w[i] == "-m" || w[i] == "--mode") { i++; continue }   # its value is not an operand
          if (w[i] !~ /^-/) break
        }
        if (!recursive && $0 !~ /# mkdir-ok: [^ ]/ && prev !~ /^[ \t]*# mkdir-ok: [^ ]/)
          printf "%s:%d: %s\n", F, NR, $0
      }
      prev = $0
    }' "$f")"
  if [ -n "$out" ]; then
    printf '%s\n' "$out" >&2
    bad=$((bad + $(printf '%s\n' "$out" | wc -l)))
  fi
done <<EOF
$(list_files)
EOF

if [ "$covered" -eq 0 ]; then
  echo "check-mkdir-lock: FAIL — covered 0 files under $ROOT (a gate that scans nothing proves nothing)" >&2
  exit 1
fi
if [ "$bad" -gt 0 ]; then
  {
    echo "check-mkdir-lock: FAIL — $bad bare mkdir site(s). The mkdir command is not exclusive (uutils exits 0 on an existing directory)."
    echo "  A lock: use an O_EXCL create, ( set -C; : > \"\$lock\" ), or the O_EXCL create of a stamp inside a directory its readers need."
    echo "  Not a lock: add '# mkdir-ok: <why exclusivity does not matter here>' on that line or the line above."
  } >&2
  exit 1
fi
echo "check-mkdir-lock: PASS — $covered files scanned, no unjustified bare mkdir"
