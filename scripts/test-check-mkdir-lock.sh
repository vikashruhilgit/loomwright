#!/usr/bin/env bash
# test-check-mkdir-lock.sh — offline self-test for check-mkdir-lock.sh.
#
# Fixture trees in a temp dir assert the gate's discrimination, fail-CLOSED, one fact per case. The
# controls on the real tree copy it, strip one real justification or put one real bare lock back, and
# require the gate to fire on exactly that site, so a green run on the real tree means something.
#
# Portability: bash 3.2 safe (macOS) + Linux CI. No sed -i, no mapfile, offline.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../loomwright/scripts/hermetic-test-env.sh"
set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
GATE="$script_dir/check-mkdir-lock.sh"
REPO="$(cd "$script_dir/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "  PASS: $1"; }
no() { fail=$((fail + 1)); echo "  FAIL: $1"; }

# tree <name> <file text> — a fixture tree (no .git) with one covered script holding <file text>.
tree() {
  local d="$T/$1"; mkdir -p "$d/loomwright/scripts" "$d/scripts"
  printf '%s\n' "$2" > "$d/loomwright/scripts/thing.sh"
  printf '%s' "$d"
}
# fires <dir> <needle> — the gate is red on <dir> and names <needle>. A variable, not a pipe into
# grep -q: under pipefail the gate's own exit 1 would fail the pipeline even on a match.
fires() { local o; if o="$(bash "$GATE" --root "$1" 2>&1)"; then return 1; fi; case "$o" in *"$2"*) return 0 ;; esac; return 1; }
green() { # green <label> <text>
  local d out; d="$(tree "g$pass$fail" "$2")"
  if out="$(bash "$GATE" --root "$d" 2>&1)"; then ok "$1"; else no "$1 — gate fired: $out"; fi
}
red() { # red <label> <text>
  local d out; d="$(tree "r$pass$fail" "$2")"
  if out="$(bash "$GATE" --root "$d" 2>&1)"; then no "$1 — gate stayed green"
  elif grep -qF 'loomwright/scripts/thing.sh:1:' <<<"$out"; then ok "$1"
  else no "$1 — offender not named: $out"; fi
}

echo "== lock shapes fire"
red 'if mkdir'                  'if mkdir "$lock" 2>/dev/null; then :; fi'
red 'until mkdir'               'until mkdir "$lock" 2>/dev/null; do sleep 1; done'
red 'while ! mkdir'             'while ! mkdir "$lock"; do sleep 1; done'
red 'mkdir ... || return'       'mkdir "$lock" 2>/dev/null || return 1'
red 'after a semicolon'         '( umask 077; mkdir "$lock" )'
red 'in a brace group'          '{ mkdir "$lock"; }'
red 'in a command substitution' 'x="$(mkdir "$lock")"'
red 'by path'                   '/bin/mkdir "$lock"'
red 'with -m'                   'mkdir -m 700 "$lock"'
red 'with --'                   'mkdir -- "$lock"'
red 'a -p only in an operand'   'mkdir "$lock" -x-p'
red 'an empty justification'    'mkdir "$lock"  # mkdir-ok:'

echo "== everything else stays green"
green 'mkdir -p'                'mkdir -p "$dir"'
green 'mkdir -m 700 -p'         'mkdir -m 700 -p "$dir"'
green 'mkdir -pv'               'mkdir -pv "$dir"'
green 'mkdir --parents'         'mkdir --parents "$dir"'
green 'a comment line'          '# mkdir "$lock" is not exclusive'
green 'a trailing comment'      'x=1  # used to be: mkdir "$lock"'
green 'a word in a string'      'echo "cannot mkdir here"'
green 'justified on the line'   'mkdir "$d" 2>/dev/null || :  # mkdir-ok: status ignored, the stamp decides'
green 'justified on the line above' "$(printf '# mkdir-ok: a private scratch dir\nmkdir "$d"')"
green 'an O_EXCL lock'          '( set -C; : > "$lock" ) 2>/dev/null'

echo "== coverage"
d="$T/cov"; mkdir -p "$d/loomwright/scripts/fixtures" "$d/loomwright/scripts/test-x.d" "$d/scripts"
echo 'x=1' > "$d/loomwright/scripts/ok.sh"
echo 'mkdir "$l"' > "$d/loomwright/scripts/test-a.sh"
echo 'mkdir "$l"' > "$d/loomwright/scripts/test-x.d/01-part.sh"
echo 'mkdir "$l"' > "$d/loomwright/scripts/fixtures/f.sh"
if bash "$GATE" --root "$d" >/dev/null 2>&1; then ok 'tests and fixtures are not covered'; else no 'tests and fixtures are not covered'; fi
echo 'mkdir "$l"' > "$d/scripts/gate.sh"
if fires "$d" 'scripts/gate.sh:1:'; then ok 'root scripts/ is covered'; else no 'root scripts/ is covered'; fi
rm -f "$d/scripts/gate.sh"
mkdir -p "$d/loomwright/scripts/adapters/p"; echo 'mkdir "$l"' > "$d/loomwright/scripts/adapters/p/w.sh"
if fires "$d" 'adapters/p/w.sh:1:'; then ok 'a nested script is covered'; else no 'a nested script is covered'; fi
d="$T/empty"; mkdir -p "$d/scripts"
if bash "$GATE" --root "$d" >/dev/null 2>&1; then no 'zero covered files must not be green'; else ok 'zero covered files is red'; fi

echo "== the real tree, and controls that it can fire"
if out="$(bash "$GATE" --root "$REPO" 2>&1)"; then ok "the real tree is green ($out)"; else no "the real tree: $out"; fi
copy="$T/real"; mkdir -p "$copy"
( cd "$REPO" && tar cf - loomwright/scripts/run-lock.sh loomwright/scripts/stamp-requirement-status.sh ) | ( cd "$copy" && tar xf - )
mkdir -p "$copy/scripts"
if bash "$GATE" --root "$copy" >/dev/null 2>&1; then ok 'CONTROL baseline: the copied real files are green'; else no 'CONTROL baseline: the copied real files are red'; fi
sed 's/ *# mkdir-ok:.*$//' "$REPO/loomwright/scripts/run-lock.sh" > "$copy/loomwright/scripts/run-lock.sh"
if fires "$copy" 'loomwright/scripts/run-lock.sh:'; then ok 'CONTROL: run-lock.sh with its justification stripped fires'
else no 'CONTROL: run-lock.sh with its justification stripped did not fire'; fi
cp "$REPO/loomwright/scripts/run-lock.sh" "$copy/loomwright/scripts/run-lock.sh"
sed 's/^if ( set -C; : > "$LOCK" ) 2>\/dev\/null; then/if mkdir "$LOCK" 2>\/dev\/null; then/' "$REPO/loomwright/scripts/stamp-requirement-status.sh" > "$copy/loomwright/scripts/stamp-requirement-status.sh"
if cmp -s "$REPO/loomwright/scripts/stamp-requirement-status.sh" "$copy/loomwright/scripts/stamp-requirement-status.sh"; then no 'CONTROL could not stage the bare lock in stamp-requirement-status.sh'
elif fires "$copy" 'loomwright/scripts/stamp-requirement-status.sh:'; then ok 'CONTROL: the old bare lock put back in stamp-requirement-status.sh fires'
else no 'CONTROL: the old bare lock in stamp-requirement-status.sh did not fire'; fi

echo
echo "check-mkdir-lock self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
