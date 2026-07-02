#!/usr/bin/env bash
# test-dispatch-pr-review.sh — self-tests for the post-/supervisor auto-review
# dispatcher (review-heal). Runs in an isolated temp dir (never touches the real
# .supervisor/). Exit 0 = all pass, 1 = any failure. Mirrors test-twin-graph.sh
# convention. UNCOUNTED by the doc-currency gate (test-*.sh).
#
# The dispatcher's ALWAYS-exit-0 invariant means every case below also asserts
# rc == 0; the behavioral assertion is the gating SIDE EFFECT (did/didn't write a
# marker, did/didn't emit DRY_RUN_DISPATCH). The real `claude` process is NEVER
# launched: LOOMWRIGHT_REVIEW_DISPATCH_DRY_RUN=1 short-circuits the launch
# path while still exercising all the gating + marker logic.
#
# Covers:
#   1. ENABLED-by-default dispatch (no config, no flag) -> marker + DRY_RUN, exit 0
#      (AC7 — the review drain now dispatches by default after PR creation).
#   2. missing-config dispatch (no config file at all) -> still dispatches (default ON).
#   3. config auto_review:true -> dispatch (DRY_RUN line emitted, marker written).
#   4. --auto-review flag -> dispatch even without config.
#   5. marker-prevents-re-dispatch: 2nd call on same PR -> no new dispatch.
#   6. --no-auto-review suppression wins even with config auto_review:true -> no dispatch.
#   6b. config auto_review:false suppresses the default-ON dispatch -> no dispatch.
#   7. --auto-review + --no-auto-review -> suppression wins (no dispatch).
#   8. missing PR url -> graceful no-op, exit 0.
#   9. launch-form contract: emitted command is headless `nohup claude -p --agent <runner> <url>`
#      (regression guard — `claude --agent <runner> "<prompt>"` WITHOUT -p starts an
#      interactive session that hangs when detached; --agent does NOT imply headless).
#  10. until-mergeable signal present BY DEFAULT (AC7): LOOMWRIGHT_UNTIL_MERGEABLE=1
#      is exported into the dispatched invocation by default.
#  11. --no-until-mergeable opt-out: the signal env var is NOT set (plain diff-only run).
#  11b. config auto_until_mergeable:false opt-out: the signal env var is NOT set.
#  12. optional tuning forwarded only when set: --check-wait-timeout / --review-check-pattern
#      thread LOOMWRIGHT_CHECK_WAIT_TIMEOUT / LOOMWRIGHT_REVIEW_CHECK_PATTERN.
#  13. real-launch RUN_LOG header: a stubbed-claude (non-dry-run) launch writes a
#      synchronous, non-empty, self-documenting header (DISPATCHED + url + until_mergeable)
#      BEFORE detaching — so an in-flight drain no longer looks like a 0-byte no-op.
#  --- Isolated-worktree dispatch lifecycle (G1 lifecycle units / G2 real launch /
#      G3 failure-injection matrix) — these run against a REAL git-repo fixture with
#      stubbed gh+claude on PATH (fresh_git_repo / run_real), NEVER a real claude: ---
#  14. G2 real launch: sibling worktree REMOVED by trap, marker EXISTS, lock GONE,
#      RUN_LOG header present, inline repo CLEAN, claude ran INSIDE the worktree.
#  15. G1/AC2 same-branch detached-HEAD: worktree created at head SHA even when the
#      repo is parked ON the head branch (no 'branch already checked out').
#  16. G3 failed `git worktree add` (bad head SHA) => exit 0, NO marker, lock released.
#  17. G3 missing claude => exit 0, NO marker, NO lock (binary check precedes both).
#  18. G3 existing marker => exit 0, no lock, no worktree, no gh, no second launch.
#  19. G3 `gh pr view` failure => exit 0, NO marker, lock released.
#  20. G3/AC2a fork PR => fork-status queried + threaded, still dispatches, exit 0.
#  21. G1 lock lost to a LIVE concurrent dispatch (fresh lock, live pid) => no relaunch.
#  22. G1 NON-reclaim: dead pid but within-TTL fresh lock => lock kept, no relaunch.
#  23. G1 stale-lock RECLAIM: pid-dead + no-marker + past-TTL => proceeds, marker written.
#  24. G1 marker wins over a stale lock: marker present => short-circuit before lock.
#  25. G1/G2 READ-ONLY toward the inline checkout: working tree+index+HEAD unchanged.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DISPATCH="$HERE/dispatch-pr-review.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

PR="https://github.com/acme/widgets/pull/42"
PR2="https://github.com/acme/widgets/pull/99"

# fresh_repo — make an isolated temp working dir with a .supervisor/ skeleton.
fresh_repo() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/.supervisor"
  printf '%s' "$d"
}

# run_dispatch <workdir> <args...> — run the dispatcher in DRY_RUN mode from
# inside <workdir>. Captures stdout in RUN_OUT, rc in RUN_RC.
run_dispatch() {
  local wd="$1"; shift
  RUN_OUT="$( cd "$wd" && LOOMWRIGHT_REVIEW_DISPATCH_DRY_RUN=1 bash "$DISPATCH" "$@" 2>/dev/null )"
  RUN_RC=$?
}

# marker_count <workdir> — number of marker files written under review-dispatch.
# Excludes lock dirs (*.lock) and their meta — only true markers count.
marker_count() {
  local wd="$1"
  ls -1 "$wd/.supervisor/review-dispatch" 2>/dev/null | grep -v '\.lock$' | grep -c . || true
}

# ----------------------------------------------------------------------------
# Real-launch harness (G1/G2/G3): the isolated-worktree dispatch path needs a
# REAL git repo (for `git worktree add`) and a stubbed `gh` + `claude` on PATH.
# These helpers build an isolated git-repo fixture with a `.supervisor/` skeleton,
# a feature branch + head commit, a stub `gh` that answers `gh pr view --json`,
# and put the stub bin dir on PATH. NEVER spawns a real claude; the stub claude is
# pointed at via LOOMWRIGHT_CLAUDE_BIN. All under temp dirs.
# ----------------------------------------------------------------------------

# fresh_git_repo [--fork] [--head-ref REF] — create an isolated git repo fixture.
# Echoes the repo path. Sets globals: FX_REPO, FX_BIN, FX_HEAD_SHA, FX_HEAD_REF,
# FX_GH_LOG (records gh calls), FX_CLAUDE_LOG (records claude calls + cwd).
fresh_git_repo() {
  local is_fork="false" head_ref="feature/x" parent_suffix=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --fork) is_fork="true"; shift ;;
      --head-ref) head_ref="$2"; shift 2 ;;
      --parent-suffix) parent_suffix="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  local d; d="$(mktemp -d)"
  local rbase="$d"
  # Optionally nest the repo under a parent dir whose name carries shell
  # metacharacters (space, $) — used to prove the detached-launch wrapper is
  # quote/$-safe (finding #1). FX_BIN + logs stay on the clean $d path.
  if [ -n "$parent_suffix" ]; then rbase="$d/$parent_suffix"; mkdir -p "$rbase"; fi
  FX_REPO="$rbase/repo"
  FX_BIN="$d/bin"
  FX_GH_LOG="$d/gh-calls.log"
  FX_CLAUDE_LOG="$d/claude-calls.log"
  mkdir -p "$FX_REPO" "$FX_BIN"
  ( cd "$FX_REPO"
    git init -q
    git config user.email t@t.t; git config user.name t
    git config commit.gpgsign false
    # Mirror the real repo: .supervisor/ is gitignored, so the dispatcher's markers,
    # locks, and logs never appear in `git status` (the READ-ONLY-toward-inline check).
    printf '.supervisor/\n' > .gitignore
    printf 'base\n' > base.txt
    git add -A; git commit -qm base
    git checkout -q -b "$head_ref"
    printf 'head\n' > head.txt
    git add -A; git commit -qm head
  )
  FX_HEAD_REF="$head_ref"
  FX_HEAD_SHA="$( cd "$FX_REPO" && git rev-parse HEAD )"
  mkdir -p "$FX_REPO/.supervisor"
  # Park the repo on the head branch so a real (non-isolated) checkout would
  # collide — the detached worktree must NOT need the branch.

  # Stub gh: answer `gh pr view <url> --json ...` with our fixture metadata.
  cat > "$FX_BIN/gh" <<GHEOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$FX_GH_LOG"
if [ "\$1" = "pr" ] && [ "\$2" = "view" ]; then
  printf '{"headRefOid":"%s","headRefName":"%s","isCrossRepository":%s,"headRepositoryOwner":{"login":"o"}}\n' \\
    "$FX_HEAD_SHA" "$FX_HEAD_REF" "$is_fork"
  exit 0
fi
exit 0
GHEOF
  chmod +x "$FX_BIN/gh"

  # Stub claude: record the cwd it was launched in + its args, then exit 0.
  cat > "$FX_BIN/stub-claude" <<CLEOF
#!/usr/bin/env bash
printf 'cwd=%s args=%s\n' "\$(pwd)" "\$*" >> "$FX_CLAUDE_LOG"
exit 0
CLEOF
  chmod +x "$FX_BIN/stub-claude"
  printf '%s' "$FX_REPO"
}

# run_real <repo> <args...> — run the dispatcher for real (NOT dry-run) from the
# repo, with the stub bin on PATH and LOOMWRIGHT_CLAUDE_BIN -> stub-claude.
# Captures rc in RUN_RC. Stub git fetch failures are tolerated (no origin remote).
run_real() {
  local repo="$1"; shift
  ( cd "$repo" && PATH="$FX_BIN:$PATH" \
      LOOMWRIGHT_CLAUDE_BIN="$FX_BIN/stub-claude" \
      bash "$DISPATCH" "$@" >/dev/null 2>&1 )
  RUN_RC=$?
}

# wait_for_no_worktree <repo> <wt_path> — poll until the detached wrapper's trap
# removes the sibling worktree (or timeout). Returns 0 if removed.
wait_for_no_worktree() {
  local repo="$1" wt="$2" i
  for i in $(seq 1 50); do
    if [ ! -d "$wt" ] && ! ( cd "$repo" && git worktree list 2>/dev/null | grep -qF "$wt" ); then
      return 0
    fi
    sleep 0.2
  done
  return 1
}

# expected_wt_path <repo> — compute the deterministic sibling worktree path the
# dispatcher would create for $PR (mirrors the dispatcher's PR_HASH_SHORT logic).
# Canonicalize via `git rev-parse --show-toplevel` exactly like the dispatcher, so
# the path matches the dispatcher's (macOS /var vs /private/var symlink).
expected_wt_path() {
  local repo="$1" h short top
  if command -v shasum >/dev/null 2>&1; then
    h="$(printf '%s' "$PR" | shasum | cut -d' ' -f1)"
  else
    h="$(printf '%s' "$PR" | sha1sum | cut -d' ' -f1)"
  fi
  short="$(printf '%s' "$h" | cut -c1-12)"
  top="$( cd "$repo" && git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$repo" )"
  printf '%s/%s-review-%s' "$(dirname "$top")" "$(basename "$top")" "$short"
}

# pr_hash — the full hash the dispatcher uses to key the marker/lock.
pr_hash() {
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$PR" | shasum | cut -d' ' -f1
  else
    printf '%s' "$PR" | sha1sum | cut -d' ' -f1
  fi
}

echo "== 1. ENABLED by default (no config, no flag) -> dispatch (AC7) =="
WD="$(fresh_repo)"
run_dispatch "$WD" "$PR"
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 1 ]; then
  ok "enabled-by-default: exit 0, dispatch emitted, 1 marker"
else
  no "enabled-by-default wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 2. missing config file -> still dispatches (default ON), exit 0 =="
WD="$(mktemp -d)"   # NO .supervisor at all
run_dispatch "$WD" "$PR"
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH'; then
  ok "missing-config: exit 0, dispatch emitted (default ON)"
else
  no "missing-config wrong (rc=$RUN_RC out='$RUN_OUT')"
fi
rm -rf "$WD"

echo "== 3. config auto_review:true -> dispatch =="
WD="$(fresh_repo)"
printf '{"auto_review": true}\n' > "$WD/.supervisor/config.json"
run_dispatch "$WD" "$PR"
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 1 ]; then
  ok "config-enabled: dispatch emitted + 1 marker written"
else
  no "config-enabled wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 4. --auto-review flag (no config) -> dispatch =="
WD="$(fresh_repo)"
run_dispatch "$WD" "$PR" --auto-review
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 1 ]; then
  ok "--auto-review: dispatch emitted + marker written without config"
else
  no "--auto-review wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 5. marker prevents re-dispatch (same PR twice) =="
WD="$(fresh_repo)"
printf '{"auto_review": true}\n' > "$WD/.supervisor/config.json"
run_dispatch "$WD" "$PR"                       # first dispatch
FIRST_RC=$RUN_RC
run_dispatch "$WD" "$PR"                        # second call, same PR
if [ "$FIRST_RC" -eq 0 ] && [ "$RUN_RC" -eq 0 ] \
   && ! printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' \
   && [ "$(marker_count "$WD")" -eq 1 ]; then
  ok "re-dispatch blocked: 2nd call no-op, still exactly 1 marker"
else
  no "re-dispatch guard wrong (2nd rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
# sanity: a DIFFERENT PR still dispatches (marker is per-PR)
run_dispatch "$WD" "$PR2"
if printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 2 ]; then
  ok "different PR dispatches independently (2 markers)"
else
  no "per-PR marker keying wrong (out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 6. --no-auto-review suppresses even with config auto_review:true =="
WD="$(fresh_repo)"
printf '{"auto_review": true}\n' > "$WD/.supervisor/config.json"
run_dispatch "$WD" "$PR" --no-auto-review
if [ "$RUN_RC" -eq 0 ] && ! printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "--no-auto-review: suppressed despite config, no dispatch, no marker"
else
  no "--no-auto-review wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 6b. config auto_review:false suppresses the default-ON dispatch =="
WD="$(fresh_repo)"
printf '{"auto_review": false}\n' > "$WD/.supervisor/config.json"
run_dispatch "$WD" "$PR"          # no flag — config false must suppress the default ON
if [ "$RUN_RC" -eq 0 ] && ! printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "config auto_review:false: suppressed despite default-ON, no dispatch, no marker"
else
  no "config-false-suppress wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 6c. legacy-path fallback: ONLY .supervisor/notify-config.json present -> read unchanged (AC1) =="
WD="$(fresh_repo)"
# Back-compat: an old install with ONLY the legacy file must still be read. Here
# the legacy file opts out via auto_review:false; if the legacy path were ignored
# the default-ON dispatch would fire (marker written). Suppression proves fallback.
printf '{"auto_review": false}\n' > "$WD/.supervisor/notify-config.json"
run_dispatch "$WD" "$PR"
if [ "$RUN_RC" -eq 0 ] && ! printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "legacy-fallback: legacy notify-config.json honored (suppressed), no dispatch, no marker"
else
  no "legacy-fallback wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 6d. both files present -> new .supervisor/config.json wins (AC2) =="
WD="$(fresh_repo)"
# New file opts out (auto_review:false); legacy file would enable (auto_review:true).
# If new-wins holds, the dispatch is suppressed (legacy true is ignored).
printf '{"auto_review": false}\n' > "$WD/.supervisor/config.json"
printf '{"auto_review": true}\n'  > "$WD/.supervisor/notify-config.json"
run_dispatch "$WD" "$PR"
if [ "$RUN_RC" -eq 0 ] && ! printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "both-present: new config.json wins (suppressed), legacy true ignored"
else
  no "both-present wrong — new file should win (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 7. --no-auto-review beats --auto-review (suppress wins) =="
WD="$(fresh_repo)"
run_dispatch "$WD" "$PR" --auto-review --no-auto-review
if [ "$RUN_RC" -eq 0 ] && ! printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "suppress beats force: no dispatch"
else
  no "suppress-vs-force wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 8. missing PR url -> graceful no-op =="
WD="$(fresh_repo)"
printf '{"auto_review": true}\n' > "$WD/.supervisor/config.json"
run_dispatch "$WD" --auto-review            # enabled, but no PR url
if [ "$RUN_RC" -eq 0 ] && ! printf '%s' "$RUN_OUT" | grep -q 'DRY_RUN_DISPATCH' && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "missing-pr-url: exit 0, no dispatch"
else
  no "missing-pr-url wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 9. launch-form contract: headless 'nohup claude -p --agent <runner> <url>' (regression guard for the interactive-session bug) =="
WD="$(fresh_repo)"
run_dispatch "$WD" "$PR"          # default dispatch so the form is emitted
LINE="$(printf '%s' "$RUN_OUT" | grep 'DRY_RUN_DISPATCH' || true)"
# Must be the --agent runner form: headless (-p present) AND select the review-pr-runner
# agent AND carry the PR url AND NOT be a /review-pr slash string (the 11.1.1 spawn-depth
# trap). `claude --agent <runner> "<prompt>"` WITHOUT -p starts an interactive session
# (--agent only selects the agent, it does NOT switch to headless) that hangs when detached.
if [ "$RUN_RC" -eq 0 ] \
   && printf '%s' "$LINE" | grep -Eq '(^| )-p( |$)|(^| )--print( |$)' \
   && printf '%s' "$LINE" | grep -q -- '--agent loomwright:review-pr-runner' \
   && printf '%s' "$LINE" | grep -q -- "$PR" \
   && ! printf '%s' "$LINE" | grep -q -- '/review-pr'; then
  ok "launch-form: headless -p + --agent <runner> + <url>, no slash string ($LINE)"
else
  no "launch-form wrong (missing -p / --agent <runner> / url, or a /review-pr slash present) (line='$LINE')"
fi
rm -rf "$WD"

echo "== 10. until-mergeable signal present BY DEFAULT (AC7) =="
WD="$(fresh_repo)"
run_dispatch "$WD" "$PR"          # no flag — until-mergeable must be ON by default
LINE="$(printf '%s' "$RUN_OUT" | grep 'DRY_RUN_DISPATCH' || true)"
if [ "$RUN_RC" -eq 0 ] \
   && printf '%s' "$LINE" | grep -q -- 'LOOMWRIGHT_UNTIL_MERGEABLE=1'; then
  ok "default until-mergeable: LOOMWRIGHT_UNTIL_MERGEABLE=1 present ($LINE)"
else
  no "default until-mergeable signal missing (line='$LINE')"
fi
rm -rf "$WD"

echo "== 11. --no-until-mergeable opt-out: signal env var NOT set =="
WD="$(fresh_repo)"
run_dispatch "$WD" "$PR" --no-until-mergeable
LINE="$(printf '%s' "$RUN_OUT" | grep 'DRY_RUN_DISPATCH' || true)"
# Dispatch still fires (auto-review default ON) but WITHOUT the until-mergeable signal.
if [ "$RUN_RC" -eq 0 ] \
   && printf '%s' "$LINE" | grep -q 'DRY_RUN_DISPATCH' \
   && ! printf '%s' "$LINE" | grep -q -- 'LOOMWRIGHT_UNTIL_MERGEABLE'; then
  ok "--no-until-mergeable: dispatch fires, signal NOT set ($LINE)"
else
  no "--no-until-mergeable wrong (signal should be absent) (line='$LINE')"
fi
rm -rf "$WD"

echo "== 11b. config auto_until_mergeable:false opt-out: signal env var NOT set =="
WD="$(fresh_repo)"
printf '{"auto_until_mergeable": false}\n' > "$WD/.supervisor/config.json"
run_dispatch "$WD" "$PR"          # no flag — config opts out of until-mergeable only
LINE="$(printf '%s' "$RUN_OUT" | grep 'DRY_RUN_DISPATCH' || true)"
if [ "$RUN_RC" -eq 0 ] \
   && printf '%s' "$LINE" | grep -q 'DRY_RUN_DISPATCH' \
   && ! printf '%s' "$LINE" | grep -q -- 'LOOMWRIGHT_UNTIL_MERGEABLE'; then
  ok "config auto_until_mergeable:false: dispatch fires, signal NOT set ($LINE)"
else
  no "config-until-mergeable-false wrong (signal should be absent) (line='$LINE')"
fi
rm -rf "$WD"

echo "== 12. optional tuning forwarded only when set (timeout + pattern) =="
WD="$(fresh_repo)"
run_dispatch "$WD" "$PR" --check-wait-timeout 300 --review-check-pattern 'claude*'
LINE="$(printf '%s' "$RUN_OUT" | grep 'DRY_RUN_DISPATCH' || true)"
if [ "$RUN_RC" -eq 0 ] \
   && printf '%s' "$LINE" | grep -q -- 'LOOMWRIGHT_UNTIL_MERGEABLE=1' \
   && printf '%s' "$LINE" | grep -q -- 'LOOMWRIGHT_CHECK_WAIT_TIMEOUT=300' \
   && printf '%s' "$LINE" | grep -q -- 'LOOMWRIGHT_REVIEW_CHECK_PATTERN=claude\*'; then
  ok "tuning forwarded: timeout + pattern present ($LINE)"
else
  no "tuning forwarding wrong (line='$LINE')"
fi
# sanity: tuning vars ABSENT by default (only forwarded when set)
WD2="$(fresh_repo)"
run_dispatch "$WD2" "$PR"
LINE2="$(printf '%s' "$RUN_OUT" | grep 'DRY_RUN_DISPATCH' || true)"
if ! printf '%s' "$LINE2" | grep -q -- 'LOOMWRIGHT_CHECK_WAIT_TIMEOUT' \
   && ! printf '%s' "$LINE2" | grep -q -- 'LOOMWRIGHT_REVIEW_CHECK_PATTERN'; then
  ok "tuning absent by default (only forwarded when set) ($LINE2)"
else
  no "tuning leaked when unset (line='$LINE2')"
fi
rm -rf "$WD" "$WD2"

echo "== 13. real-launch RUN_LOG header: synchronous, non-empty, self-documenting (0-byte-log fix) =="
# NOT dry-run: exercise the actual isolated-worktree launch path against a REAL git
# repo with stubbed gh+claude. The header is emitted BEFORE the detached launch, so
# it is present regardless of what the stub does — proving an in-flight drain no
# longer looks like a 0-byte no-op.
fresh_git_repo >/dev/null
run_real "$FX_REPO" "$PR"
RC13=$RUN_RC
HDR="$(cat "$FX_REPO"/.supervisor/logs/review-pr-dispatch-*.log 2>/dev/null || true)"
if [ "$RC13" -eq 0 ] \
   && [ -n "$HDR" ] \
   && printf '%s' "$HDR" | grep -q 'DISPATCHED' \
   && printf '%s' "$HDR" | grep -q -- 'until_mergeable=1' \
   && printf '%s' "$HDR" | grep -qF "url=$PR"; then
  ok "real-launch RUN_LOG header present + greppable (DISPATCHED + until_mergeable=1 + url)"
else
  no "real-launch RUN_LOG header missing/wrong (rc=$RC13 hdr='$HDR')"
fi
WT="$(expected_wt_path "$FX_REPO")"
wait_for_no_worktree "$FX_REPO" "$WT" || true
rm -rf "$(dirname "$FX_REPO")"

echo "== 14. (G2) real stubbed launch: sibling worktree removed, marker exists, lock gone, repo clean =="
fresh_git_repo >/dev/null
PRE_STATUS="$( cd "$FX_REPO" && git status --porcelain )"
run_real "$FX_REPO" "$PR"
RC14=$RUN_RC
WT="$(expected_wt_path "$FX_REPO")"
H="$(pr_hash)"
# Marker must exist immediately (written before launch).
MARKER_OK=0; [ -f "$FX_REPO/.supervisor/review-dispatch/$H" ] && MARKER_OK=1
# Wait for the detached wrapper's trap to clean up.
REMOVED_OK=0; wait_for_no_worktree "$FX_REPO" "$WT" && REMOVED_OK=1
# Lock dir gone after cleanup.
LOCK_GONE=0; [ ! -d "$FX_REPO/.supervisor/review-dispatch/$H.lock" ] && LOCK_GONE=1
# Header present + non-empty.
HDR="$(cat "$FX_REPO"/.supervisor/logs/review-pr-dispatch-*.log 2>/dev/null || true)"
HDR_OK=0; printf '%s' "$HDR" | grep -q 'DISPATCHED' && HDR_OK=1
# Inline repo clean (no stray worktree pollution; status unchanged).
POST_STATUS="$( cd "$FX_REPO" && git status --porcelain )"
CLEAN_OK=0; [ "$PRE_STATUS" = "$POST_STATUS" ] && CLEAN_OK=1
# The stub claude recorded being launched from INSIDE the sibling worktree.
CLAUDE_CWD_OK=0; grep -qF "cwd=$WT" "$FX_CLAUDE_LOG" 2>/dev/null && CLAUDE_CWD_OK=1
if [ "$RC14" -eq 0 ] && [ "$MARKER_OK" -eq 1 ] && [ "$REMOVED_OK" -eq 1 ] \
   && [ "$LOCK_GONE" -eq 1 ] && [ "$HDR_OK" -eq 1 ] && [ "$CLEAN_OK" -eq 1 ] \
   && [ "$CLAUDE_CWD_OK" -eq 1 ]; then
  ok "G2: worktree removed, marker exists, lock gone, header present, repo clean, claude ran in worktree"
else
  no "G2 wrong (rc=$RC14 marker=$MARKER_OK removed=$REMOVED_OK lock_gone=$LOCK_GONE hdr=$HDR_OK clean=$CLEAN_OK claude_cwd=$CLAUDE_CWD_OK wt=$WT)"
fi
rm -rf "$(dirname "$FX_REPO")"

echo "== 15. (G1/AC2) same-branch detached-HEAD: worktree created at head SHA even when repo is ON the head branch =="
# Repo is parked on the head branch (fresh_git_repo leaves us there). A non-detached
# checkout would fail 'branch already checked out'; --detach must succeed.
fresh_git_repo >/dev/null
ON_BRANCH="$( cd "$FX_REPO" && git rev-parse --abbrev-ref HEAD )"
run_real "$FX_REPO" "$PR"
RC15=$RUN_RC
H="$(pr_hash)"
MARKER_OK=0; [ -f "$FX_REPO/.supervisor/review-dispatch/$H" ] && MARKER_OK=1
# Confirm the launched worktree was detached at the head SHA (claude log proves the
# wrapper cd'd into it + ran; the marker proves worktree+header succeeded).
if [ "$RC15" -eq 0 ] && [ "$ON_BRANCH" = "$FX_HEAD_REF" ] && [ "$MARKER_OK" -eq 1 ]; then
  ok "same-branch: detached worktree created + dispatched while repo on head branch ($ON_BRANCH)"
else
  no "same-branch detached path wrong (rc=$RC15 on_branch=$ON_BRANCH head_ref=$FX_HEAD_REF marker=$MARKER_OK)"
fi
WT="$(expected_wt_path "$FX_REPO")"; wait_for_no_worktree "$FX_REPO" "$WT" || true
rm -rf "$(dirname "$FX_REPO")"

echo "== 16. (G3/AC4a) failed 'git worktree add' => NO marker, lock released, exit 0 =="
fresh_git_repo >/dev/null
# Sabotage: stub gh returns a head SHA that does NOT exist in the repo, so
# `git worktree add --detach <path> <bad-sha>` fails.
cat > "$FX_BIN/gh" <<'GHEOF'
#!/usr/bin/env bash
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  printf '{"headRefOid":"%s","headRefName":"feature/x","isCrossRepository":false,"headRepositoryOwner":{"login":"o"}}\n' \
    "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  exit 0
fi
exit 0
GHEOF
chmod +x "$FX_BIN/gh"
run_real "$FX_REPO" "$PR"
RC16=$RUN_RC
H="$(pr_hash)"
NO_MARKER=0; [ ! -e "$FX_REPO/.supervisor/review-dispatch/$H" ] && NO_MARKER=1
LOCK_GONE=0; [ ! -d "$FX_REPO/.supervisor/review-dispatch/$H.lock" ] && LOCK_GONE=1
NO_CLAUDE=0; [ ! -s "$FX_CLAUDE_LOG" ] && NO_CLAUDE=1
if [ "$RC16" -eq 0 ] && [ "$NO_MARKER" -eq 1 ] && [ "$LOCK_GONE" -eq 1 ] && [ "$NO_CLAUDE" -eq 1 ]; then
  ok "G3 worktree-add-fail: exit 0, NO marker, lock released, no launch (truthful marker state)"
else
  no "G3 worktree-add-fail wrong (rc=$RC16 no_marker=$NO_MARKER lock_gone=$LOCK_GONE no_claude=$NO_CLAUDE)"
fi
rm -rf "$(dirname "$FX_REPO")"

echo "== 17. (G3/AC4a) missing claude => exit 0, NO marker (binary check precedes marker) =="
fresh_git_repo >/dev/null
# Point CLAUDE_BIN at a non-existent binary; run with the stub bin on PATH for gh.
( cd "$FX_REPO" && PATH="$FX_BIN:$PATH" LOOMWRIGHT_CLAUDE_BIN="definitely-not-a-real-claude-xyz" \
    bash "$DISPATCH" "$PR" >/dev/null 2>&1 )
RC17=$?
H="$(pr_hash)"
NO_MARKER=0; [ ! -e "$FX_REPO/.supervisor/review-dispatch/$H" ] && NO_MARKER=1
NO_LOCK=0; [ ! -d "$FX_REPO/.supervisor/review-dispatch/$H.lock" ] && NO_LOCK=1
if [ "$RC17" -eq 0 ] && [ "$NO_MARKER" -eq 1 ] && [ "$NO_LOCK" -eq 1 ]; then
  ok "G3 missing-claude: exit 0, NO marker, NO lock (binary check precedes lock+marker)"
else
  no "G3 missing-claude wrong (rc=$RC17 no_marker=$NO_MARKER no_lock=$NO_LOCK)"
fi
rm -rf "$(dirname "$FX_REPO")"

echo "== 18. (G3/AC4a) existing marker => exit 0, no new worktree, no second launch =="
fresh_git_repo >/dev/null
H="$(pr_hash)"
mkdir -p "$FX_REPO/.supervisor/review-dispatch"
printf 'pre-existing\t%s\n' "$PR" > "$FX_REPO/.supervisor/review-dispatch/$H"
run_real "$FX_REPO" "$PR"
RC18=$RUN_RC
NO_LOCK=0; [ ! -d "$FX_REPO/.supervisor/review-dispatch/$H.lock" ] && NO_LOCK=1
NO_CLAUDE=0; [ ! -s "$FX_CLAUDE_LOG" ] && NO_CLAUDE=1
NO_GH=0; [ ! -s "$FX_GH_LOG" ] && NO_GH=1   # gh pr view never called (short-circuit before ④)
WT="$(expected_wt_path "$FX_REPO")"
NO_WT=0; [ ! -d "$WT" ] && NO_WT=1
if [ "$RC18" -eq 0 ] && [ "$NO_LOCK" -eq 1 ] && [ "$NO_CLAUDE" -eq 1 ] && [ "$NO_GH" -eq 1 ] && [ "$NO_WT" -eq 1 ]; then
  ok "G3 existing-marker: exit 0, no lock, no worktree, no gh, no second launch"
else
  no "G3 existing-marker wrong (rc=$RC18 no_lock=$NO_LOCK no_claude=$NO_CLAUDE no_gh=$NO_GH no_wt=$NO_WT)"
fi
rm -rf "$(dirname "$FX_REPO")"

echo "== 19. (G3/AC4a) gh pr view failure => exit 0, NO marker, lock released =="
fresh_git_repo >/dev/null
# Sabotage gh to fail (non-zero, empty output) for pr view.
cat > "$FX_BIN/gh" <<'GHEOF'
#!/usr/bin/env bash
[ "$1" = "pr" ] && [ "$2" = "view" ] && exit 7
exit 0
GHEOF
chmod +x "$FX_BIN/gh"
run_real "$FX_REPO" "$PR"
RC19=$RUN_RC
H="$(pr_hash)"
NO_MARKER=0; [ ! -e "$FX_REPO/.supervisor/review-dispatch/$H" ] && NO_MARKER=1
LOCK_GONE=0; [ ! -d "$FX_REPO/.supervisor/review-dispatch/$H.lock" ] && LOCK_GONE=1
if [ "$RC19" -eq 0 ] && [ "$NO_MARKER" -eq 1 ] && [ "$LOCK_GONE" -eq 1 ]; then
  ok "G3 gh-fail: exit 0, NO marker, lock released"
else
  no "G3 gh-fail wrong (rc=$RC19 no_marker=$NO_MARKER lock_gone=$LOCK_GONE)"
fi
rm -rf "$(dirname "$FX_REPO")"

echo "== 20. (G3/AC2a) fork PR => fork signal threaded, still dispatches, exit 0 =="
fresh_git_repo --fork >/dev/null
# Fork head SHA exists locally in this fixture (we reuse the same repo), so the
# worktree still creates; the AC2a degrade-to-review-only is the RUNNER's job — the
# dispatcher's contract is to DETECT + THREAD the fork signal. We assert the launch
# happened (marker) and the fork env var was set for the wrapper. The harder case —
# a fork head that is NOT local and must be fetched via refs/pull/<n>/head — is
# covered by case 27 (this case alone would mask that gap).
run_real "$FX_REPO" "$PR"
RC20=$RUN_RC
H="$(pr_hash)"
MARKER_OK=0; [ -f "$FX_REPO/.supervisor/review-dispatch/$H" ] && MARKER_OK=1
# gh was asked for isCrossRepository (proves fork detection path ran).
GH_FORK_QUERY=0; grep -q 'isCrossRepository' "$FX_GH_LOG" 2>/dev/null && GH_FORK_QUERY=1
if [ "$RC20" -eq 0 ] && [ "$MARKER_OK" -eq 1 ] && [ "$GH_FORK_QUERY" -eq 1 ]; then
  ok "G3 fork: exit 0, dispatched, fork-status queried via gh --json isCrossRepository"
else
  no "G3 fork wrong (rc=$RC20 marker=$MARKER_OK gh_fork_query=$GH_FORK_QUERY)"
fi
WT="$(expected_wt_path "$FX_REPO")"; wait_for_no_worktree "$FX_REPO" "$WT" || true
rm -rf "$(dirname "$FX_REPO")"

echo "== 21. (G1/AC4a-i) lock lost to a LIVE concurrent dispatch (fresh lock, pid alive) => exit 0, no second launch =="
fresh_git_repo >/dev/null
H="$(pr_hash)"
mkdir -p "$FX_REPO/.supervisor/review-dispatch/$H.lock"
# Record a LIVE pid (this test process) + a FRESH ts => no reclaim.
{
  printf 'pr_url\t%s\n' "$PR"
  printf 'pid\t%s\n' "$$"
  printf 'ts\t%s\n' "$(date -u +%s)"
  printf 'worktree\t/tmp/other\n'
} > "$FX_REPO/.supervisor/review-dispatch/$H.lock/meta"
run_real "$FX_REPO" "$PR"
RC21=$RUN_RC
NO_MARKER=0; [ ! -e "$FX_REPO/.supervisor/review-dispatch/$H" ] && NO_MARKER=1
LOCK_KEPT=0; [ -d "$FX_REPO/.supervisor/review-dispatch/$H.lock" ] && LOCK_KEPT=1
NO_CLAUDE=0; [ ! -s "$FX_CLAUDE_LOG" ] && NO_CLAUDE=1
if [ "$RC21" -eq 0 ] && [ "$NO_MARKER" -eq 1 ] && [ "$LOCK_KEPT" -eq 1 ] && [ "$NO_CLAUDE" -eq 1 ]; then
  ok "G1 lock-lost-live: exit 0, no marker, did NOT steal the live lock, no launch"
else
  no "G1 lock-lost-live wrong (rc=$RC21 no_marker=$NO_MARKER lock_kept=$LOCK_KEPT no_claude=$NO_CLAUDE)"
fi
rm -rf "$(dirname "$FX_REPO")"

echo "== 22. (G1/AC4a-i) lock lost to a FRESH lock (dead pid but within TTL) => no reclaim, exit 0 =="
fresh_git_repo >/dev/null
H="$(pr_hash)"
mkdir -p "$FX_REPO/.supervisor/review-dispatch/$H.lock"
# Dead pid (99999 unlikely alive) but FRESH ts => within TTL => must NOT reclaim.
{
  printf 'pr_url\t%s\n' "$PR"
  printf 'pid\t99999\n'
  printf 'ts\t%s\n' "$(date -u +%s)"
} > "$FX_REPO/.supervisor/review-dispatch/$H.lock/meta"
run_real "$FX_REPO" "$PR"
RC22=$RUN_RC
NO_MARKER=0; [ ! -e "$FX_REPO/.supervisor/review-dispatch/$H" ] && NO_MARKER=1
LOCK_KEPT=0; [ -d "$FX_REPO/.supervisor/review-dispatch/$H.lock" ] && LOCK_KEPT=1
if [ "$RC22" -eq 0 ] && [ "$NO_MARKER" -eq 1 ] && [ "$LOCK_KEPT" -eq 1 ]; then
  ok "G1 lock-fresh-dead-pid: within-TTL fresh lock NOT reclaimed (dead pid alone insufficient)"
else
  no "G1 lock-fresh-dead-pid wrong (rc=$RC22 no_marker=$NO_MARKER lock_kept=$LOCK_KEPT)"
fi
rm -rf "$(dirname "$FX_REPO")"

echo "== 23. (G1/AC4a-i) stale-lock RECLAIM (pid-dead + no-marker + past-TTL) => proceeds, marker written =="
fresh_git_repo >/dev/null
H="$(pr_hash)"
mkdir -p "$FX_REPO/.supervisor/review-dispatch/$H.lock"
# Dead pid + ts far in the past (> 1800s TTL) + NO marker => ALL THREE hold => reclaim.
{
  printf 'pr_url\t%s\n' "$PR"
  printf 'pid\t99999\n'
  printf 'ts\t%s\n' "$(( $(date -u +%s) - 4000 ))"
} > "$FX_REPO/.supervisor/review-dispatch/$H.lock/meta"
run_real "$FX_REPO" "$PR"
RC23=$RUN_RC
MARKER_OK=0; [ -f "$FX_REPO/.supervisor/review-dispatch/$H" ] && MARKER_OK=1
if [ "$RC23" -eq 0 ] && [ "$MARKER_OK" -eq 1 ]; then
  ok "G1 stale-reclaim: dead pid + past-TTL + no-marker => reclaimed, dispatched, marker written"
else
  no "G1 stale-reclaim wrong (rc=$RC23 marker=$MARKER_OK)"
fi
WT="$(expected_wt_path "$FX_REPO")"; wait_for_no_worktree "$FX_REPO" "$WT" || true
rm -rf "$(dirname "$FX_REPO")"

echo "== 24. (G1/AC4a-i) NO reclaim when a MARKER exists (even past-TTL + dead pid) — marker wins =="
fresh_git_repo >/dev/null
H="$(pr_hash)"
# Marker present => ① existing-marker-wins short-circuits BEFORE the lock is ever
# considered; the stale lock is irrelevant. Asserts the marker is never reclaimed-over.
mkdir -p "$FX_REPO/.supervisor/review-dispatch/$H.lock"
{
  printf 'pid\t99999\n'
  printf 'ts\t%s\n' "$(( $(date -u +%s) - 4000 ))"
} > "$FX_REPO/.supervisor/review-dispatch/$H.lock/meta"
printf 'pre-existing\t%s\n' "$PR" > "$FX_REPO/.supervisor/review-dispatch/$H"
run_real "$FX_REPO" "$PR"
RC24=$RUN_RC
NO_CLAUDE=0; [ ! -s "$FX_CLAUDE_LOG" ] && NO_CLAUDE=1
NO_GH=0; [ ! -s "$FX_GH_LOG" ] && NO_GH=1
if [ "$RC24" -eq 0 ] && [ "$NO_CLAUDE" -eq 1 ] && [ "$NO_GH" -eq 1 ]; then
  ok "G1 marker-wins-over-stale-lock: exit 0, no relaunch, no gh (marker short-circuits before lock)"
else
  no "G1 marker-wins wrong (rc=$RC24 no_claude=$NO_CLAUDE no_gh=$NO_GH)"
fi
rm -rf "$(dirname "$FX_REPO")"

echo "== 25. (G1/G2) READ-ONLY toward the inline checkout: working tree + index byte-identical before/after =="
fresh_git_repo >/dev/null
# Capture a fingerprint of the inline working tree + index BEFORE dispatch.
PRE_TREE="$( cd "$FX_REPO" && git status --porcelain && git rev-parse HEAD && git write-tree 2>/dev/null )"
run_real "$FX_REPO" "$PR"
RC25=$RUN_RC
WT="$(expected_wt_path "$FX_REPO")"
wait_for_no_worktree "$FX_REPO" "$WT" || true
POST_TREE="$( cd "$FX_REPO" && git status --porcelain && git rev-parse HEAD && git write-tree 2>/dev/null )"
if [ "$RC25" -eq 0 ] && [ "$PRE_TREE" = "$POST_TREE" ]; then
  ok "READ-ONLY: inline working tree + index + HEAD unchanged by the isolated drain"
else
  no "READ-ONLY violated (rc=$RC25) — pre/post tree differ"
fi
rm -rf "$(dirname "$FX_REPO")"

echo "== 26. (G3/finding#1) metacharacter in repo path: detached-launch wrapper is quote/\$-safe =="
# The repo lives under a parent dir containing a space AND a '$'. The OLD wrapper
# interpolated values into a `bash -c` string with the values inside double quotes —
# a single quote was safe, but a '$' silently expanded inside the inner shell and
# corrupted $WT_PATH (failed cd -> claude never ran in the worktree -> leaked worktree)
# AFTER the marker was written: a silent-drop. The positional-args wrapper is immune.
fresh_git_repo --parent-suffix 'we$ird dir' >/dev/null
DROOT="$(dirname "$(dirname "$FX_REPO")")"   # the mktemp root, for cleanup
run_real "$FX_REPO" "$PR"
RC26=$RUN_RC
WT="$(expected_wt_path "$FX_REPO")"
H="$(pr_hash)"
MARKER_OK=0; [ -f "$FX_REPO/.supervisor/review-dispatch/$H" ] && MARKER_OK=1
# Wait for the detached wrapper's trap to finish FIRST (claude runs before cleanup),
# so the claude log is guaranteed populated before we read it (mirrors case 14 — the
# detached wrapper is async, so checking the log before the wait is a race).
REMOVED_OK=0; wait_for_no_worktree "$FX_REPO" "$WT" && REMOVED_OK=1
# Proof the wrapper survived the metachar path: claude ran from INSIDE the worktree
# whose path contains the space + '$'. With the OLD interpolation this cwd would be
# wrong (the '$' expanded away inside the inner shell), so this grep would miss.
CLAUDE_CWD_OK=0; grep -qF "cwd=$WT" "$FX_CLAUDE_LOG" 2>/dev/null && CLAUDE_CWD_OK=1
if [ "$RC26" -eq 0 ] && [ "$MARKER_OK" -eq 1 ] && [ "$CLAUDE_CWD_OK" -eq 1 ] && [ "$REMOVED_OK" -eq 1 ]; then
  ok "metachar-path: wrapper quote/\$-safe — claude ran in the worktree, marker written, trap cleaned up"
else
  no "metachar-path wrong (rc=$RC26 marker=$MARKER_OK claude_cwd=$CLAUDE_CWD_OK removed=$REMOVED_OK wt=$WT)"
fi
rm -rf "$DROOT"

echo "== 27. (G3/AC2a) fork PR whose head is NOT local: dispatcher fetches refs/pull/<n>/head =="
# Faithful fork sim (unlike case 20, which keeps the fork SHA local): a bare "origin"
# holds the PR head ONLY under refs/pull/42/head (on NO branch); the working repo does
# NOT have that commit. The OLD fetch (`git fetch origin <sha>` / `git fetch origin`)
# cannot retrieve a non-branch ref, so the worktree-add would fail and the AC2a
# review-only-ESCALATED+comment path would be UNREACHABLE. The new
# `git fetch origin refs/pull/<n>/head` makes the head local => worktree creates =>
# runner launches (fork signal threaded) => marker written.
fork_root="$(mktemp -d)"
ORIGIN="$fork_root/origin.git"; git init -q --bare "$ORIGIN"
SEED="$fork_root/seed"; mkdir -p "$SEED"
( cd "$SEED"; git init -q; git config user.email t@t.t; git config user.name t; git config commit.gpgsign false
  printf 'base\n' > f; git add -A; git commit -qm base; git branch -M main
  git remote add origin "$ORIGIN"; git push -q origin main
  printf 'forkhead\n' > f; git commit -qam forkhead
  git push -q origin "HEAD:refs/pull/42/head" )   # PR head as a pull ref ONLY, not a branch
FORK_SHA="$( cd "$SEED" && git rev-parse HEAD )"
FX_REPO="$fork_root/repo"
# --no-local forces the real fetch transport: a LOCAL clone would hardlink the ENTIRE
# object DB (incl. the unreferenced forkhead), defeating the not-local premise. With
# --no-local only main's reachable objects transfer, so FORK_SHA stays absent until the
# dispatcher fetches refs/pull/42/head.
git clone -q --no-local --branch main "$ORIGIN" "$FX_REPO" 2>/dev/null
FX_BIN="$fork_root/bin"; FX_GH_LOG="$fork_root/gh.log"; FX_CLAUDE_LOG="$fork_root/claude.log"
mkdir -p "$FX_BIN" "$FX_REPO/.supervisor"
cat > "$FX_BIN/gh" <<GHEOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$FX_GH_LOG"
[ "\$1" = pr ] && [ "\$2" = view ] && printf '{"headRefOid":"%s","headRefName":"feature/forked","isCrossRepository":true}\n' "$FORK_SHA"
exit 0
GHEOF
cat > "$FX_BIN/stub-claude" <<CLEOF
#!/usr/bin/env bash
printf 'cwd=%s args=%s\n' "\$(pwd)" "\$*" >> "$FX_CLAUDE_LOG"
exit 0
CLEOF
chmod +x "$FX_BIN/gh" "$FX_BIN/stub-claude"
# Sanity: FORK_SHA must NOT be present locally before dispatch (proves the test is real).
PRESENT_BEFORE=1; ( cd "$FX_REPO" && git cat-file -e "${FORK_SHA}^{commit}" 2>/dev/null ) || PRESENT_BEFORE=0
run_real "$FX_REPO" "$PR"
RC27=$RUN_RC
H="$(pr_hash)"
MARKER_OK=0; [ -f "$FX_REPO/.supervisor/review-dispatch/$H" ] && MARKER_OK=1
WT="$(expected_wt_path "$FX_REPO")"
REMOVED_OK=0; wait_for_no_worktree "$FX_REPO" "$WT" && REMOVED_OK=1
RAN_OK=0; grep -qF "cwd=$WT" "$FX_CLAUDE_LOG" 2>/dev/null && RAN_OK=1
if [ "$RC27" -eq 0 ] && [ "$PRESENT_BEFORE" -eq 0 ] && [ "$MARKER_OK" -eq 1 ] && [ "$RAN_OK" -eq 1 ] && [ "$REMOVED_OK" -eq 1 ]; then
  ok "fork-not-local: refs/pull/N/head fetched => worktree created + runner launched (AC2a path reachable)"
else
  no "fork-not-local wrong (rc=$RC27 present_before=$PRESENT_BEFORE marker=$MARKER_OK ran=$RAN_OK removed=$REMOVED_OK)"
fi
rm -rf "$fork_root"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
