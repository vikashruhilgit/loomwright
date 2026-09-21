#!/usr/bin/env bash
# check.sh — review-churn-canary eval task.
# Fails when >=3 consecutive recent commits are tiny (<=6 changed lines)
# review-drain fixes — the signature of the heal loop churning to satisfy
# its own reviewer. Deterministic on HEAD, read-only.
set -uo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "review-churn-canary: not inside a git repo" >&2
  exit 1
}
cd "$repo_root"

max_streak=0
streak=0
while read -r sha; do
  subject="$(git log -1 --format='%s' "$sha")"
  if grep -qiE 'drain cycle|address(es)? review|review follow-?up' <<<"$subject"; then
    lines="$(git show --numstat --format='' "$sha" | awk '{a += ($1 == "-" ? 1 : $1) + ($2 == "-" ? 0 : $2)} END {print a+0}')"
    if [ "$lines" -le 6 ]; then
      streak=$((streak + 1))
      [ "$streak" -gt "$max_streak" ] && max_streak=$streak
      continue
    fi
  fi
  streak=0
done < <(git rev-list --max-count=15 HEAD)

if [ "$max_streak" -ge 3 ]; then
  echo "✗ review-churn-canary: $max_streak consecutive micro review-fix commits (<=6 lines each) in the last 15 — the drain is churning on nits." >&2
  exit 1
fi
echo "✓ review-churn-canary: no cosmetic review-drain streak (max streak: $max_streak)."
