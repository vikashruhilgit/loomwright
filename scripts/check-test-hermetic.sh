#!/usr/bin/env bash
# check-test-hermetic.sh — CI gate (ratchet): every self-test sources the egress-hermetic helper.
#
# WHY: a test that inherits the caller's environment can reach a real egress channel — a terminal
# exporting LOOMWRIGHT_WEBHOOK_URL made fixture events reach a real ntfy topic, and a staged real
# notify-desktop.sh fired a real macOS banner. loomwright/scripts/hermetic-test-env.sh scrubs the
# egress env and shims the OS notifiers + curl/wget; this gate makes sourcing it non-optional, so a
# NEW test is covered without anyone remembering to opt in.
#
# RULE: for every covered test —
#     loomwright/scripts/test-*.sh
#     loomwright/scripts/adapters/*/test-*.sh
#     scripts/test-*.sh
#   the FIRST EXECUTABLE line (line 1's shebang, comment lines and blank lines skipped) must be the
#   self-resolving source statement
#     . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/<rel>hermetic-test-env.sh"
#   and <rel>hermetic-test-env.sh must exist relative to the test's own directory. A source line
#   placed after `set -u` or after any other code is a failure: the helper must run before the test
#   does anything, including before a `set` line that could make an unguarded expansion fatal.
#
# FAILS CLOSED (exit 1, no `|| true`) naming every offender, and on zero covered files (a
# 0-file run of a fail-closed gate is a false green — mirrors check-token-budget.sh's guard).
# Green prints the covered count; that count is evidence for a PR body, never restated in docs.
#
# usage: check-test-hermetic.sh [--root DIR]   (default: the repo root this script lives in)
# Self-test: scripts/test-check-test-hermetic.sh (offline fixtures).
# Portability: bash 3.2 safe (macOS) + Linux CI. No GNU-only flags, no mapfile, no sed -i.
set -uo pipefail
shopt -s nullglob

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root) [ "$#" -ge 2 ] || { echo "check-test-hermetic: --root needs a directory" >&2; exit 1; }
            root="$2"; shift 2 ;;
    *) echo "check-test-hermetic: unknown argument: $1" >&2; exit 1 ;;
  esac
done
[ -d "$root" ] || { echo "check-test-hermetic: root is not a directory: $root" >&2; exit 1; }
cd "$root" || exit 1

files=(loomwright/scripts/test-*.sh loomwright/scripts/adapters/*/test-*.sh scripts/test-*.sh)
if [ "${#files[@]}" -eq 0 ]; then
  echo "check-test-hermetic: FAIL — no covered test files found under $root (the globs matched nothing)" >&2
  exit 1
fi

# The literal prefix every source line must start with (the part before <rel>hermetic-test-env.sh).
prefix='. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/'

offenders=0
for f in "${files[@]}"; do
  first="$(awk 'NR==1 && /^#!/ {next} /^[[:space:]]*#/ || /^[[:space:]]*$/ {next} {print; exit}' "$f")"
  case "$first" in
    "$prefix"*'hermetic-test-env.sh"')
      rel="${first#"$prefix"}"; rel="${rel%\"}"
      if [ -f "$(dirname "$f")/$rel" ]; then continue; fi
      echo "check-test-hermetic: OFFENDER $f — sources '$rel', which does not exist relative to the test" >&2 ;;
    *hermetic-test-env.sh*)
      echo "check-test-hermetic: OFFENDER $f — first executable line is not the canonical self-resolving source statement: $first" >&2 ;;
    *)
      echo "check-test-hermetic: OFFENDER $f — first executable line does not source hermetic-test-env.sh (found: ${first:-<none>})" >&2 ;;
  esac
  offenders=$((offenders + 1))
done

if [ "$offenders" -gt 0 ]; then
  echo "check-test-hermetic: FAIL — $offenders of ${#files[@]} covered tests are not egress-hermetic." >&2
  echo "  Fix: make this the first executable line (before the test's \`set\` line):" >&2
  echo "    ${prefix}<path-to-loomwright/scripts>/hermetic-test-env.sh\"" >&2
  exit 1
fi
echo "check-test-hermetic: OK — ${#files[@]}/${#files[@]} covered tests source hermetic-test-env.sh as their first executable line"
