#!/usr/bin/env bash
# test-no-pipefail-grep-q.sh — gate: no self-test may pipe INTO `grep -q` while `pipefail` is on.
#
# Why: `grep -q` exits on its first match. If the producer is still writing, it gets EPIPE (or
# SIGPIPE), and under `set -o pipefail` the PIPELINE fails although grep matched — an assertion
# that goes red on a correct result. It only bites when the scheduler lets grep exit between two
# of the producer's writes, so it is rare on an idle machine and common on a loaded one: once CI
# ran the suite concurrently (run-self-tests.sh) it failed test-retention-sweep.sh's AC-11 upper-bound
# arm and test-verify-provides.sh's em_gate_ok helper on the same run, both `write error: Broken
# pipe`. ~840 sites were
# rewritten to `grep -q PAT < <(producer)` — the same bytes reach grep, and a process
# substitution's status is not part of the pipeline, so a writer's EPIPE can no longer decide the
# assertion. This gate keeps new ones out.
#
# Scope: loomwright/scripts/test-*.sh, loomwright/scripts/adapters/*/test-*.sh and root
# scripts/test-*.sh — every file that mentions `pipefail`. Comment lines are ignored. Exit 0 = clean,
# 1 = a violation (or a broken detector — see the controls).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

# a `|` that is not half of `||`, then `grep` with q in ANY of its leading flag tokens — `-q`, `-qF`,
# and split forms like `-F -q` / `-v -q` alike (a first-token-only match missed the split forms)
RE='(^[[:space:]]*|[^|])\|[[:space:]]*grep([[:space:]]+-[A-Za-z]+)*[[:space:]]+-[A-Za-z]*q'

# scan <file...> — prints file:line:text for each violation
scan() {
  local f
  for f in "$@"; do
    grep -q pipefail "$f" 2>/dev/null || continue
    grep -nE "$RE" "$f" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#' | sed "s|^|$f:|"
  done
  return 0
}

T="$(mktemp -d "${TMPDIR:-/tmp}/test-no-pipefail-grep-q.XXXXXX")" || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT

echo "== detector controls (fixtures are assembled at runtime so this file never contains the pattern) =="
P='|'
{ echo 'set -uo pipefail'; printf '%s %s grep -q y && echo hit\n' 'printf "%s" "$x"' "$P"; } > "$T/bad-inline.sh"
{ echo 'set -uo pipefail'; printf '%s \\\n  %s grep -qF y\n' 'some_fn "$x"' "$P"; } > "$T/bad-continued.sh"
{ echo 'set -uo pipefail'; printf '%s %s grep -F -q y\n' 'printf "%s" "$x"' "$P"; } > "$T/bad-split.sh"
{ echo 'set -uo pipefail'; printf '%s %s grep -F -i y\n' 'printf "%s" "$x"' "$P"; } > "$T/good-noq.sh"
{ echo 'set -uo pipefail'; echo 'grep -q y < <(printf "%s" "$x") && echo hit'; } > "$T/good-procsub.sh"
{ echo 'set -uo pipefail'; printf 'a %s%s grep -q y "$f"\n' "$P" "$P"; } > "$T/good-or.sh"
{ echo 'set -uo pipefail'; printf '# %s %s grep -q y\n' 'printf "%s" "$x"' "$P"; } > "$T/good-comment.sh"
{ printf '%s %s grep -q y\n' 'printf "%s" "$x"' "$P"; } > "$T/good-nopipefail.sh"

[ -n "$(scan "$T/bad-inline.sh")" ] && ok "a producer piped into grep -q under pipefail IS flagged" \
  || no "detector missed an inline producer piped into grep -q — the gate below would be vacuous"
[ -n "$(scan "$T/bad-continued.sh")" ] && ok "a backslash-continued pipe into grep -qF on its own line IS flagged" \
  || no "detector missed a continued-line pipe into grep -qF"
[ -n "$(scan "$T/bad-split.sh")" ] && ok "a split flag form (grep -F -q) IS flagged" \
  || no "detector missed a split flag form — q in a later flag token slips past"
[ -z "$(scan "$T/good-noq.sh")" ] && ok "a pipe into grep with NO q flag (reads to EOF) is NOT flagged" \
  || no "detector flags a grep that never exits early"
[ -z "$(scan "$T/good-procsub.sh")" ] && ok "'grep -q PAT < <(producer)' (the fix) is NOT flagged" \
  || no "detector flags the sanctioned process-substitution form"
[ -z "$(scan "$T/good-or.sh")" ] && ok "'a || grep -q' is NOT flagged (|| is not a pipe)" \
  || no "detector mistakes || for a pipe"
[ -z "$(scan "$T/good-comment.sh")" ] && ok "a comment line is NOT flagged" \
  || no "detector flags comment lines"
[ -z "$(scan "$T/good-nopipefail.sh")" ] && ok "a file without pipefail is NOT flagged (the hazard needs pipefail)" \
  || no "detector flags a file that never sets pipefail"

echo "== the suite =="
shopt -s nullglob
files=("$REPO_ROOT"/loomwright/scripts/test-*.sh "$REPO_ROOT"/loomwright/scripts/adapters/*/test-*.sh "$REPO_ROOT"/scripts/test-*.sh)
[ "${#files[@]}" -gt 10 ] && ok "scanned ${#files[@]} test files" || no "only ${#files[@]} test files found — the scan set is wrong"
hits="$(scan "${files[@]}")"
if [ -z "$hits" ]; then
  ok "no test pipes into grep -q under pipefail"
else
  no "these pipe into grep -q under pipefail — rewrite as: grep -q PAT < <(producer)"
  printf '%s\n' "$hits" | sed "s|^$REPO_ROOT/|    |"
fi

echo
echo "test-no-pipefail-grep-q: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
