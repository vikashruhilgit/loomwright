#!/usr/bin/env bash
# check.sh — review-churn-canary eval task.
# Canary for the heal/drain loop churning on nits: >=STREAK consecutive commits
# that are each tiny (<= MAX_LINES changed lines) review-drain fixes.
#
# Two modes:
#   default (eval mode) — FIXTURE-BASED and hermetic: builds two throwaway git
#     repos in a temp dir (one with a 3-commit micro-drain streak that MUST
#     fire, one boundary/clean repo that MUST NOT) and asserts the scanner's
#     exact streak counts. Deterministic pass/fail; no dependence on this
#     repo's real history (which contains a known historical true positive —
#     scoring it would turn the eval permanently red).
#   --live — scans the enclosing repo's real history (advisory diagnostic;
#     exit 1 when a streak >= STREAK is found). Not used by run-eval.sh.
#
# Usage: bash check.sh [--live] [--window N] [--max-lines N] [--streak N]
#   defaults: window 15, max-lines 6, streak 3
set -uo pipefail

LIVE=0; WINDOW=15; STREAK=3; MAX_LINES=6
while [ $# -gt 0 ]; do
  case "$1" in
    --live) LIVE=1 ;;
    --window)    WINDOW="${2:?--window requires a number}"; shift ;;
    --max-lines) MAX_LINES="${2:?--max-lines requires a number}"; shift ;;
    --streak)    STREAK="${2:?--streak requires a number}"; shift ;;
    *) echo "review-churn-canary: unknown arg '$1'" >&2; exit 2 ;;
  esac
  shift
done
# Fail CLOSED on non-numeric knobs (a garbage threshold must not silently pass).
for v in "$WINDOW" "$MAX_LINES" "$STREAK"; do
  case "$v" in ''|*[!0-9]*) echo "review-churn-canary: non-numeric knob '$v'" >&2; exit 2 ;; esac
done

# Drain-subject vocabulary. The salvaged original only knew `drain cycle` /
# `address review` / `review follow-up`; this repo's real drain commits say
# "drain round N", "heal iter N", "heal residual", "bot-review" — matched here
# so --live actually recognizes the loop's own output.
PATTERN='drain round|drain cycle|address(es|ing)? review|review follow-?up|bot-review|heal iter|heal residual'

# scan_repo <repo-dir>: print the max streak (stdout) of consecutive commits in
# the last $WINDOW on HEAD whose subject matches $PATTERN AND whose total
# changed lines (insertions+deletions, binary files counted 1) <= $MAX_LINES.
# Per-commit diagnostics go to stderr.
scan_repo() {
  local dir="$1" max=0 s=0 sha subject lines
  while IFS= read -r sha; do
    [ -n "$sha" ] || continue
    subject="$(git -C "$dir" log -1 --format='%s' "$sha")"
    if grep -qiE "$PATTERN" <<<"$subject"; then
      lines="$(git -C "$dir" show --numstat --format='' "$sha" \
        | awk '{a += ($1 == "-" ? 1 : $1) + ($2 == "-" ? 0 : $2)} END {print a+0}')"
      if [ "$lines" -le "$MAX_LINES" ]; then
        s=$((s + 1))
        [ "$s" -gt "$max" ] && max=$s
        echo "  drain-micro: ${sha:0:8} (${lines} lines) $subject" >&2
        continue
      fi
      echo "  drain-large: ${sha:0:8} (${lines} lines, > ${MAX_LINES}) $subject" >&2
    fi
    s=0
  done < <(git -C "$dir" rev-list --max-count="$WINDOW" HEAD)
  echo "$max"
}

# ---- live mode: scan the enclosing repo -----------------------------------
if [ "$LIVE" -eq 1 ]; then
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "review-churn-canary: not inside a git repo" >&2
    exit 1
  }
  max="$(scan_repo "$repo_root")"
  if [ "$max" -ge "$STREAK" ]; then
    echo "✗ review-churn-canary [--live]: $max consecutive micro review-fix commits (<= $MAX_LINES lines each) in the last $WINDOW — the drain is churning on nits." >&2
    exit 1
  fi
  echo "✓ review-churn-canary [--live]: no micro review-drain streak >= $STREAK in the last $WINDOW (max streak: $max)."
  exit 0
fi

# ---- eval mode: hermetic fixtures -----------------------------------------
# Build throwaway repos with fully pinned config so the scan exercises the real
# git invocation without touching the enclosing repo or the user's git config.
tmp="$(mktemp -d "${TMPDIR:-/tmp}/churn-canary.XXXXXX")" || exit 1
trap 'rm -rf "$tmp"' EXIT

g() { # g <repo-dir> <git args...> — hermetic git wrapper
  local dir="$1"; shift
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
    git -C "$dir" -c user.name=eval-canary -c user.email=eval@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}
mkrepo() { mkdir -p "$1" && g "$1" init -q; }
append_commit() { # append_commit <repo> <n-lines> <subject>
  local dir="$1" n="$2" subj="$3" i
  for ((i = 1; i <= n; i++)); do echo "pad line $i for '$subj'" >>"$dir/app.txt"; done
  # Appended lines are pure insertions; the scanner reads numstat counts only.
  g "$dir" add -A && g "$dir" commit -q -m "$subj"
}

fail=0

# Fixture A — churn: seed + exactly 3 consecutive micro drain commits (2, 3,
# and the 6-line boundary). Expected max streak: exactly 3 => canary FIRES.
churn="$tmp/churn"
mkrepo "$churn"
append_commit "$churn" 20 "feat: seed corpus fixture"
append_commit "$churn" 2  "fix: address review nits (drain round 1)"
append_commit "$churn" 3  "style: drain cycle nit polish (drain round 2)"
append_commit "$churn" 6  "docs: review follow-up wording (drain round 3)"
got="$(scan_repo "$churn")"
if [ "$got" -ne 3 ]; then
  echo "FAIL: churn fixture expected max streak 3, scanner reported $got" >&2
  fail=1
elif [ "$got" -lt "$STREAK" ]; then
  echo "FAIL: churn fixture streak $got did not reach firing threshold $STREAK" >&2
  fail=1
fi

# Fixture B — boundary/clean: a drain-subject commit that is too big (10 > 6),
# a tiny non-drain commit, then only a 2-streak of micro drain commits.
# Expected max streak: exactly 2 => canary must NOT fire.
clean="$tmp/clean"
mkrepo "$clean"
append_commit "$clean" 20 "feat: seed corpus fixture"
append_commit "$clean" 10 "fix: address review findings (drain round 1)"   # pattern, but > 6 lines
append_commit "$clean" 2  "feat: add widget"                               # tiny, but not drain
append_commit "$clean" 3  "fix: address review nit (drain round 2)"
append_commit "$clean" 1  "docs: review follow-up typo"
got="$(scan_repo "$clean")"
if [ "$got" -ne 2 ]; then
  echo "FAIL: clean fixture expected max streak 2, scanner reported $got" >&2
  fail=1
elif [ "$got" -ge "$STREAK" ]; then
  echo "FAIL: clean fixture streak $got wrongly reaches firing threshold $STREAK" >&2
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "✗ review-churn-canary: fixture assertions failed — the canary mechanism is broken." >&2
  exit 1
fi
echo "✓ review-churn-canary: mechanism verified on fixtures (fires on 3-streak, silent on boundary/clean)."
