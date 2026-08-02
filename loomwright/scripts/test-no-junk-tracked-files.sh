#!/usr/bin/env bash
# test-no-junk-tracked-files.sh — no flag-shaped or option-shaped path may be git-tracked.
#
# WHY THIS EXISTS (measured, three times):
#   A fail-safe helper whose ledger path is POSITIONAL (`learning-emit … <ledger_path>`) writes
#   its record to a file named after the FLAG when the path argument is omitted — producing a
#   tracked file literally called `--run-id` at the repo root. It happened twice before being
#   written down in project memory, and a third time it was swept into a commit by a routine
#   `git add -A` and shipped in a PR.
#
# Why a gate rather than a .gitignore line alone: `.gitignore` only stops the NEXT one, only for
# the exact name guessed in advance, and does nothing for a file already tracked (git ignores
# .gitignore for tracked paths). The failure is silent at every step — the helper exits 0 by
# contract, the junk file looks like noise in `git status`, and no existing gate reads filenames.
# So assert the invariant on the tracked set itself.
#
# WHAT COUNTS AS JUNK: a path whose basename begins with `-`. That is never a legitimate source
# filename in this repo, and it is exactly the shape every instance of this bug produces. It is
# also independently hostile: a leading dash makes the path parse as an OPTION in almost every
# shell command (`rm --run-id`, `grep pattern --run-id`), which is why such files resist cleanup.
#
# Fail-CLOSED: a junk tracked file exits 1. This is a correctness gate, not a fail-safe emitter.
# CI runs it automatically via the existing `loomwright/scripts/test-*.sh` self-test loop, so it
# needs no `.github/workflows/` edit (which would make `claude-code-action` self-skip the PR's
# own review — see CLAUDE.md).
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"

PASS=0
FAIL=0
ok() { echo "PASS: $1"; PASS=$((PASS + 1)); }
no() { echo "FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

cd "$REPO_ROOT" 2>/dev/null || { echo "FAIL: cannot cd to repo root" >&2; exit 1; }

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "SKIP: not a git repository — junk-tracked-file gate not run"
  exit 0
fi

# `git ls-files -z` + awk on the BASENAME. NUL-delimited so a pathological filename cannot
# smuggle a newline past the scan.
JUNK="$(git ls-files -z 2>/dev/null | tr '\0' '\n' | awk -F/ '{ if ($NF ~ /^-/) print }')"

if [ -z "$JUNK" ]; then
  ok "no flag-shaped tracked files (no basename begins with '-')"
else
  while IFS= read -r j; do
    [ -n "$j" ] || continue
    no "flag-shaped file is git-tracked: '$j' — almost certainly a helper invoked without its POSITIONAL output-path argument (e.g. \`learning-emit … <ledger_path>\`), which wrote its record to a file named after the flag. Remove it with \`git rm -- ./$j\` (the leading \`./\` is required — without it the path parses as an option), confirm the record is not needed in its real ledger, and re-run the helper WITH the path."
  done <<EOF
$JUNK
EOF
fi

# ---------------------------------------------------------------------------
# Self-test: the gate must actually CATCH one. A guard that cannot fail is the same
# class of defect it exists to prevent, so prove it against a fixture repo.
# ---------------------------------------------------------------------------
TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
(
  cd "$TMPD" || exit 1
  git init -q . 2>/dev/null
  git config user.email t@t.local; git config user.name t
  : > normal-file.txt
  : > ./--run-id
  git add -A 2>/dev/null
) >/dev/null 2>&1

_c_junk="$(cd "$TMPD" && git ls-files -z 2>/dev/null | tr '\0' '\n' | awk -F/ '{ if ($NF ~ /^-/) print }')"
_c_normal="$(cd "$TMPD" && git ls-files -z 2>/dev/null | tr '\0' '\n' | awk -F/ '{ if ($NF !~ /^-/) print }')"
if [ "$_c_junk" = "--run-id" ] && [ "$_c_normal" = "normal-file.txt" ]; then
  ok "self-test: the gate catches a tracked '--run-id' and does NOT flag an ordinary filename"
else
  no "self-test: mis-tuned — junk=[$_c_junk] normal=[$_c_normal]; expected exactly '--run-id' / 'normal-file.txt'"
fi

echo "----"
echo "test-no-junk-tracked-files: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
