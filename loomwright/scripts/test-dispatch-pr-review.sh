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
#  36. regime probe: defaultMode 'acceptEdits' also classifies as permissive
#      (PR #248 review finding #1 — acceptEdits auto-approves file edits without
#      prompting and was missing from the permissive case, a fail-open gap).
#  45. (af/39e) process registry: a real launch registers ONE wrapper `drain` entry for
#      the detached wrapper's own pid (repo, runner session id, stop hint, default cap);
#      an unwritable registry still launches with exit/stdout unchanged; a mutant with
#      the wrapper's registration line deleted registers no wrapper entry. The suite exports
#      its own LOOMWRIGHT_PROC_REGISTRY_DIR, so a standalone run never touches the real home.
#  46. (af/39e review) `proc-registry.sh reap --apply` of an overdue drain entry: the
#      wrapper passes the TERM on to its background runner and tears down only after
#      it exits (the stub sees its worktree + lock still present at exit; .died then
#      recorded, entries removed); a mutant without the wrapper's TERM pass-on tears
#      down under the live runner.
#  47. (af/39e review 2) the wrapper registers its runner session as a SECOND drain
#      entry (pid = the runner, owner_pid = the wrapper, hashed after the exec: running);
#      a mutant with that one line deleted registers no session entry.
#  48. (af/39e review 2) a TERM that lands before the runner starts (during the wrapper's
#      own registration): the runner never runs, the exit is 143, teardown completes and
#      .died records it; a mutant without the pre-launch `_term` check starts the runner.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DISPATCH="$HERE/dispatch-pr-review.sh"
. "$HERE/wait-lib.sh"
# af/39e: the suite's own process registry (every real launch registers its wrapper); removed on exit
PROC_REG_TMP="$(mktemp -d)"
export LOOMWRIGHT_PROC_REGISTRY_DIR="$PROC_REG_TMP/procs"
trap 'rm -rf "$PROC_REG_TMP"' EXIT

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
# inside <workdir>. Captures stdout in RUN_OUT, rc in RUN_RC. HOME is ISOLATED
# to a per-workdir dir that does NOT exist unless a test populates it — the
# regime probe (permissions.defaultMode) must never read the real operator's
# ~/.claude/settings.json. A test that wants to exercise the regime probe sets
# RUN_HOME to a fixture dir before calling; unset (the default) after.
run_dispatch() {
  local wd="$1"; shift
  local h="${RUN_HOME:-$wd/.fakehome}"
  RUN_OUT="$( cd "$wd" && HOME="$h" LOOMWRIGHT_REVIEW_DISPATCH_DRY_RUN=1 bash "$DISPATCH" "$@" 2>/dev/null )"
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
  # `--help` is special-cased and answered WITHOUT logging to FX_CLAUDE_LOG —
  # it is the dispatcher's step-②b permission-regime-pinnable PROBE, not a
  # real launch, and every existing "claude never really launched" assertion
  # (NO_CLAUDE / claude log empty) below depends on the probe staying silent
  # in that log. The fake help text advertises exactly the flags the
  # dispatcher's ②b check greps for, so the happy-path fixture stays pinnable.
  # DEFAULT SHAPE prints a terminal REVIEW_HEAL_RESULT line to its OWN stdout
  # (captured by the wrapper's RUN_LOG redirect, `$_log`) so every EXISTING
  # "real launch" case below is a COMPLETED drain, never a died one, by
  # default — death-detection cases (§ "death detection") override this file
  # with stub_claude_no_result() below.
  cat > "$FX_BIN/stub-claude" <<CLEOF
#!/usr/bin/env bash
if [ "\$1" = "--help" ]; then
  printf -- '--permission-mode <mode> (choices: "acceptEdits", "auto", "bypassPermissions", "manual", "dontAsk", "plan")\n'
  printf -- '--allowedTools, --allowed-tools <tools...>\n'
  printf -- '--disallowedTools, --disallowed-tools <tools...>\n'
  exit 0
fi
printf 'cwd=%s args=%s fork=%s\n' "\$(pwd)" "\$*" "\${LOOMWRIGHT_PR_IS_FORK:-unset}" >> "$FX_CLAUDE_LOG"
printf '## REVIEW_HEAL_RESULT\n- schema_version: 1\n- decision: PASS\n'
exit 0
CLEOF
  chmod +x "$FX_BIN/stub-claude"
  printf '%s' "$FX_REPO"
}

# stub_claude_no_result <bin_dir> — overwrite stub-claude so it exits WITHOUT
# ever printing a REVIEW_HEAL_RESULT block (a drain that died mid-run — e.g.
# a backgrounded wait the model ended its turn on under `claude -p`). Still
# logs cwd/args to FX_CLAUDE_LOG (unaffected — only its OWN stdout, the part
# the wrapper's RUN_LOG redirect captures, differs from the default fixture).
stub_claude_no_result() {
  local bin="$1"
  cat > "$bin/stub-claude" <<CLEOF
#!/usr/bin/env bash
if [ "\$1" = "--help" ]; then
  printf -- '--permission-mode <mode> (choices: "acceptEdits", "auto", "bypassPermissions", "manual", "dontAsk", "plan")\n'
  printf -- '--allowedTools, --allowed-tools <tools...>\n'
  printf -- '--disallowedTools, --disallowed-tools <tools...>\n'
  exit 0
fi
printf 'cwd=%s args=%s fork=%s\n' "\$(pwd)" "\$*" "\${LOOMWRIGHT_PR_IS_FORK:-unset}" >> "$FX_CLAUDE_LOG"
printf 'partial output, then the process just... stops (simulated background-wait death)\n'
exit 0
CLEOF
  chmod +x "$bin/stub-claude"
}

# run_real <repo> <args...> — run the dispatcher for real (NOT dry-run) from the
# repo, with the stub bin on PATH and LOOMWRIGHT_CLAUDE_BIN -> stub-claude.
# Captures rc in RUN_RC. Stub git fetch failures are tolerated (no origin remote).
# HOME is ISOLATED (see run_dispatch) — RUN_HOME overrides for regime-probe tests.
run_real() {
  local repo="$1"; shift
  local h="${RUN_HOME:-$repo/.fakehome}"
  ( cd "$repo" && PATH="$FX_BIN:$PATH" \
      HOME="$h" \
      LOOMWRIGHT_CLAUDE_BIN="$FX_BIN/stub-claude" \
      bash "$DISPATCH" "$@" >/dev/null 2>&1 )
  RUN_RC=$?
}

# worktree_gone <repo> <wt_path> — the sibling is gone from disk AND the admin list.
worktree_gone() {
  local repo="$1" wt="$2"
  [ ! -d "$wt" ] && ! ( cd "$repo" && grep -qF "$wt" < <(git worktree list 2>/dev/null) )
}

# wait_for_no_worktree <repo> <wt_path> — poll until the detached wrapper's trap
# removes the sibling worktree (or timeout). Returns 0 if removed. This is an
# INTERMEDIATE state of the trap (git unlinks dir + admin entry; the wrapper then
# still forks `rm -rf "$_wt"` and `rm -rf "$_lock"`) — fine for cases that only
# need the worktree gone; a case that also asserts on the lock syncs with
# wait_for_teardown below, or it reads the lock inside that window (the CI-only
# `lock_present` flake in test-worktree-salvage.sh AC-7c, run 35596258321).
wait_for_no_worktree() {
  local repo="$1" wt="$2" i
  for i in $(seq 1 50); do
    worktree_gone "$repo" "$wt" && return 0
    sleep 0.2
  done
  return 1
}

# wait_for_teardown <repo> <wt_path> <lock_dir> — poll until the trap's TERMINAL
# action has happened: lock dir gone (released LAST by design — it covers the
# worktree's whole lifetime) AND worktree gone. Returns 0 if both within 10s.
wait_for_teardown() {
  local repo="$1" wt="$2" lock="$3" i
  for i in $(seq 1 50); do
    if [ ! -d "$lock" ] && worktree_gone "$repo" "$wt"; then return 0; fi
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
if [ "$RUN_RC" -eq 0 ] && grep -q 'DRY_RUN_DISPATCH' < <(printf '%s' "$RUN_OUT") && [ "$(marker_count "$WD")" -eq 1 ]; then
  ok "enabled-by-default: exit 0, dispatch emitted, 1 marker"
else
  no "enabled-by-default wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 2. missing config file -> still dispatches (default ON), exit 0 =="
WD="$(mktemp -d)"   # NO .supervisor at all
run_dispatch "$WD" "$PR"
if [ "$RUN_RC" -eq 0 ] && grep -q 'DRY_RUN_DISPATCH' < <(printf '%s' "$RUN_OUT"); then
  ok "missing-config: exit 0, dispatch emitted (default ON)"
else
  no "missing-config wrong (rc=$RUN_RC out='$RUN_OUT')"
fi
rm -rf "$WD"

echo "== 3. config auto_review:true -> dispatch =="
WD="$(fresh_repo)"
printf '{"auto_review": true}\n' > "$WD/.supervisor/config.json"
run_dispatch "$WD" "$PR"
if [ "$RUN_RC" -eq 0 ] && grep -q 'DRY_RUN_DISPATCH' < <(printf '%s' "$RUN_OUT") && [ "$(marker_count "$WD")" -eq 1 ]; then
  ok "config-enabled: dispatch emitted + 1 marker written"
else
  no "config-enabled wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 4. --auto-review flag (no config) -> dispatch =="
WD="$(fresh_repo)"
run_dispatch "$WD" "$PR" --auto-review
if [ "$RUN_RC" -eq 0 ] && grep -q 'DRY_RUN_DISPATCH' < <(printf '%s' "$RUN_OUT") && [ "$(marker_count "$WD")" -eq 1 ]; then
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
   && ! grep -q 'DRY_RUN_DISPATCH' < <(printf '%s' "$RUN_OUT") \
   && [ "$(marker_count "$WD")" -eq 1 ]; then
  ok "re-dispatch blocked: 2nd call no-op, still exactly 1 marker"
else
  no "re-dispatch guard wrong (2nd rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
# sanity: a DIFFERENT PR still dispatches (marker is per-PR)
run_dispatch "$WD" "$PR2"
if grep -q 'DRY_RUN_DISPATCH' < <(printf '%s' "$RUN_OUT") && [ "$(marker_count "$WD")" -eq 2 ]; then
  ok "different PR dispatches independently (2 markers)"
else
  no "per-PR marker keying wrong (out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 6. --no-auto-review suppresses even with config auto_review:true =="
WD="$(fresh_repo)"
printf '{"auto_review": true}\n' > "$WD/.supervisor/config.json"
run_dispatch "$WD" "$PR" --no-auto-review
if [ "$RUN_RC" -eq 0 ] && ! grep -q 'DRY_RUN_DISPATCH' < <(printf '%s' "$RUN_OUT") && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "--no-auto-review: suppressed despite config, no dispatch, no marker"
else
  no "--no-auto-review wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 6b. config auto_review:false suppresses the default-ON dispatch =="
WD="$(fresh_repo)"
printf '{"auto_review": false}\n' > "$WD/.supervisor/config.json"
run_dispatch "$WD" "$PR"          # no flag — config false must suppress the default ON
if [ "$RUN_RC" -eq 0 ] && ! grep -q 'DRY_RUN_DISPATCH' < <(printf '%s' "$RUN_OUT") && [ "$(marker_count "$WD")" -eq 0 ]; then
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
if [ "$RUN_RC" -eq 0 ] && ! grep -q 'DRY_RUN_DISPATCH' < <(printf '%s' "$RUN_OUT") && [ "$(marker_count "$WD")" -eq 0 ]; then
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
if [ "$RUN_RC" -eq 0 ] && ! grep -q 'DRY_RUN_DISPATCH' < <(printf '%s' "$RUN_OUT") && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "both-present: new config.json wins (suppressed), legacy true ignored"
else
  no "both-present wrong — new file should win (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 7. --no-auto-review beats --auto-review (suppress wins) =="
WD="$(fresh_repo)"
run_dispatch "$WD" "$PR" --auto-review --no-auto-review
if [ "$RUN_RC" -eq 0 ] && ! grep -q 'DRY_RUN_DISPATCH' < <(printf '%s' "$RUN_OUT") && [ "$(marker_count "$WD")" -eq 0 ]; then
  ok "suppress beats force: no dispatch"
else
  no "suppress-vs-force wrong (rc=$RUN_RC out='$RUN_OUT' markers=$(marker_count "$WD"))"
fi
rm -rf "$WD"

echo "== 8. missing PR url -> graceful no-op =="
WD="$(fresh_repo)"
printf '{"auto_review": true}\n' > "$WD/.supervisor/config.json"
run_dispatch "$WD" --auto-review            # enabled, but no PR url
if [ "$RUN_RC" -eq 0 ] && ! grep -q 'DRY_RUN_DISPATCH' < <(printf '%s' "$RUN_OUT") && [ "$(marker_count "$WD")" -eq 0 ]; then
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
   && grep -Eq '(^| )-p( |$)|(^| )--print( |$)' < <(printf '%s' "$LINE") \
   && grep -q -- '--agent loomwright:review-pr-runner' < <(printf '%s' "$LINE") \
   && grep -q -- "$PR" < <(printf '%s' "$LINE") \
   && ! grep -q -- '/review-pr' < <(printf '%s' "$LINE"); then
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
   && grep -q -- 'LOOMWRIGHT_UNTIL_MERGEABLE=1' < <(printf '%s' "$LINE"); then
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
   && grep -q 'DRY_RUN_DISPATCH' < <(printf '%s' "$LINE") \
   && ! grep -q -- 'LOOMWRIGHT_UNTIL_MERGEABLE' < <(printf '%s' "$LINE"); then
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
   && grep -q 'DRY_RUN_DISPATCH' < <(printf '%s' "$LINE") \
   && ! grep -q -- 'LOOMWRIGHT_UNTIL_MERGEABLE' < <(printf '%s' "$LINE"); then
  ok "config auto_until_mergeable:false: dispatch fires, signal NOT set ($LINE)"
else
  no "config-until-mergeable-false wrong (signal should be absent) (line='$LINE')"
fi
rm -rf "$WD"

echo "== 11c. fix floor resolved in the dispatching checkout and forwarded in BOTH loops =="
WD="$(fresh_repo)"
run_dispatch "$WD" "$PR"          # no config — the default floor
LINE="$(printf '%s' "$RUN_OUT" | grep 'DRY_RUN_DISPATCH' || true)"
if [ "$RUN_RC" -eq 0 ] && grep -q -- 'LOOMWRIGHT_FIX_FLOOR=MEDIUM ' < <(printf '%s' "$LINE"); then
  ok "fix floor default: LOOMWRIGHT_FIX_FLOOR=MEDIUM ($LINE)"
else
  no "fix floor default missing (line='$LINE')"
fi
rm -rf "$WD"
WD="$(fresh_repo)"
printf '{"fix_floor": "high", "auto_until_mergeable": false}\n' > "$WD/.supervisor/config.json"
run_dispatch "$WD" "$PR"          # configured floor + the plain diff-only loop
LINE="$(printf '%s' "$RUN_OUT" | grep 'DRY_RUN_DISPATCH' || true)"
if [ "$RUN_RC" -eq 0 ] && grep -q -- 'LOOMWRIGHT_FIX_FLOOR=HIGH ' < <(printf '%s' "$LINE") \
   && ! grep -q -- 'LOOMWRIGHT_UNTIL_MERGEABLE' < <(printf '%s' "$LINE"); then
  ok "fix floor from config, forwarded to the plain diff-only loop too ($LINE)"
else
  no "configured fix floor not forwarded in the plain loop (line='$LINE')"
fi
rm -rf "$WD"
WD="$(fresh_repo)"
printf '{"fix_floor": "bogus"}\n' > "$WD/.supervisor/config.json"
run_dispatch "$WD" "$PR"          # an invalid floor is forwarded as `invalid`, never defaulted
LINE="$(printf '%s' "$RUN_OUT" | grep 'DRY_RUN_DISPATCH' || true)"
if [ "$RUN_RC" -eq 0 ] && grep -q -- 'LOOMWRIGHT_FIX_FLOOR=invalid ' < <(printf '%s' "$LINE"); then
  ok "invalid fix floor forwarded as 'invalid' so the drain refuses visibly ($LINE)"
else
  no "invalid fix floor not forwarded as 'invalid' (line='$LINE')"
fi
rm -rf "$WD"

echo "== 12. optional tuning forwarded only when set (timeout + pattern) =="
WD="$(fresh_repo)"
run_dispatch "$WD" "$PR" --check-wait-timeout 300 --review-check-pattern 'claude*'
LINE="$(printf '%s' "$RUN_OUT" | grep 'DRY_RUN_DISPATCH' || true)"
if [ "$RUN_RC" -eq 0 ] \
   && grep -q -- 'LOOMWRIGHT_UNTIL_MERGEABLE=1' < <(printf '%s' "$LINE") \
   && grep -q -- 'LOOMWRIGHT_CHECK_WAIT_TIMEOUT=300' < <(printf '%s' "$LINE") \
   && grep -q -- 'LOOMWRIGHT_REVIEW_CHECK_PATTERN=claude\*' < <(printf '%s' "$LINE"); then
  ok "tuning forwarded: timeout + pattern present ($LINE)"
else
  no "tuning forwarding wrong (line='$LINE')"
fi
# sanity: tuning vars ABSENT by default (only forwarded when set)
WD2="$(fresh_repo)"
run_dispatch "$WD2" "$PR"
LINE2="$(printf '%s' "$RUN_OUT" | grep 'DRY_RUN_DISPATCH' || true)"
if ! grep -q -- 'LOOMWRIGHT_CHECK_WAIT_TIMEOUT' < <(printf '%s' "$LINE2") \
   && ! grep -q -- 'LOOMWRIGHT_REVIEW_CHECK_PATTERN' < <(printf '%s' "$LINE2"); then
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
   && grep -q 'DISPATCHED' < <(printf '%s' "$HDR") \
   && grep -q -- 'until_mergeable=1' < <(printf '%s' "$HDR") \
   && grep -qF "url=$PR" < <(printf '%s' "$HDR"); then
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
# Wait for the detached wrapper's trap to finish (its LAST action is the lock
# release), then assert worktree-gone and lock-gone independently.
LOCK="$FX_REPO/.supervisor/review-dispatch/$H.lock"
wait_for_teardown "$FX_REPO" "$WT" "$LOCK" || true
REMOVED_OK=0; worktree_gone "$FX_REPO" "$WT" && REMOVED_OK=1
LOCK_GONE=0; [ ! -d "$LOCK" ] && LOCK_GONE=1
# Header present + non-empty.
HDR="$(cat "$FX_REPO"/.supervisor/logs/review-pr-dispatch-*.log 2>/dev/null || true)"
HDR_OK=0; grep -q 'DISPATCHED' < <(printf '%s' "$HDR") && HDR_OK=1
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
if [ "\$1" = "--help" ]; then
  printf -- '--permission-mode <mode> (choices: "acceptEdits", "auto", "bypassPermissions", "manual", "dontAsk", "plan")\n'
  printf -- '--allowedTools, --allowed-tools <tools...>\n'
  printf -- '--disallowedTools, --disallowed-tools <tools...>\n'
  exit 0
fi
printf 'cwd=%s args=%s fork=%s\n' "\$(pwd)" "\$*" "\${LOOMWRIGHT_PR_IS_FORK:-unset}" >> "$FX_CLAUDE_LOG"
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

# =============================================================================
# Permission pin + regime probe (red-team-hardening item 01, decisions R1/R2)
# =============================================================================

echo "== 28. DRY_RUN permission pin (AC1): --permission-mode + full --allowedTools + --disallowedTools =="
WD="$(fresh_repo)"
run_dispatch "$WD" "$PR"
LINE="$(printf '%s' "$RUN_OUT" | grep 'DRY_RUN_DISPATCH' || true)"
if [ "$RUN_RC" -eq 0 ] \
   && grep -q -- '--permission-mode dontAsk' < <(printf '%s' "$LINE") \
   && grep -q -- 'Read,Grep,Glob,Task' < <(printf '%s' "$LINE") \
   && grep -q -- 'Bash(git fetch:\*)' < <(printf '%s' "$LINE") \
   && grep -q -- 'Bash(git checkout:\*)' < <(printf '%s' "$LINE") \
   && grep -q -- 'Bash(git add:\*)' < <(printf '%s' "$LINE") \
   && grep -q -- 'Bash(git commit:\*)' < <(printf '%s' "$LINE") \
   && grep -qF -- 'Write(./**),Edit(./**)' < <(printf '%s' "$LINE") \
   && grep -qF -- 'Bash(git push origin HEAD:HEAD_REF),' < <(printf '%s' "$LINE") \
   && grep -q -- 'Bash(gh pr view:\*)' < <(printf '%s' "$LINE") \
   && grep -q -- 'Bash(gh pr diff:\*)' < <(printf '%s' "$LINE") \
   && grep -q -- 'Bash(gh pr comment:\*)' < <(printf '%s' "$LINE") \
   && grep -qF -- "Bash(bash $HERE/drain-gh-read.sh *)" < <(printf '%s' "$LINE") \
   && grep -q -- '--disallowedTools WebFetch,WebSearch' < <(printf '%s' "$LINE"); then
  ok "DRY_RUN permission pin: --permission-mode dontAsk + full allowedTools list + disallowedTools present"
else
  no "DRY_RUN permission pin wrong (line='$LINE')"
fi

# 28b. (BLOCKING — F1) the allowlist's SHAPE is checked against what the real CLI
# honours (scripts/fixtures/drain-allowlist-probe.json), not against the string the
# code happens to build. Test 28 used to pin `Bash(gh api repos/*:*)` — a rule the
# runtime treats as matching nothing — so a passing suite proved only that the code
# chose that string. Each assertion below is a probed fact.
echo "== 28b. (BLOCKING) drain allowlist: no merge vector, only rule shapes the CLI honours, every drain script admitted =="
AT28="$(printf '%s' "$LINE" | perl -ne 'print $1 if /--allowedTools (.*?) --disallowedTools /')"
DT28="$(printf '%s' "$LINE" | perl -ne 'print $1 if /--disallowedTools (.*?) --agent /')"
f28=""
[ -n "$AT28" ] || f28="$f28 allowlist-unparsed"
# No raw GitHub API and no merge: `gh api graphql` admits mergePullRequest, `gh api
# repos/...` admits `-X PUT .../merge` (probe: current_list results).
case "$AT28" in *"gh api"*) f28="$f28 raw-gh-api" ;; esac
case "$AT28" in *"gh pr merge"*) f28="$f28 gh-pr-merge" ;; esac
# automate-helpers.sh also holds gate-eval (the merge executor): only escalation-cause.
AT28_LINES="$(printf '%s' "$AT28" | tr ',' '\n')"
grep -vqF 'automate-helpers.sh escalation-cause *)' < <(grep -F 'automate-helpers.sh' <<<"$AT28_LINES") && f28="$f28 automate-helpers-unscoped"
# A `*` before the legacy trailing `:*` is a literal character (probe: previous_list).
grep -Eq '\*.*:\*\)$' <<<"$AT28_LINES" && f28="$f28 literal-star-before-colon-star"
# A rule carrying `${...}` never matches (probe: rule_shape_checks).
case "$AT28" in *'${'*) f28="$f28 unexpanded-variable" ;; esac
# The push entry is exact — no wildcard after HEAD:<ref> (extra refspec / --force).
grep -vqxF 'Bash(git push origin HEAD:HEAD_REF)' < <(grep -F 'git push' <<<"$AT28_LINES") && f28="$f28 push-not-exact"
# Files that would re-point git or re-grant permissions mid-session stay denied.
for d in 'Write(./.git)' 'Write(./.git/**)' 'Edit(./.git/**)' 'Write(./.claude/**)' 'Edit(./.claude/**)' 'Write(./.mcp.json)'; do
  case ",$DT28," in *",$d,"*) ;; *) f28="$f28 not-denied:$d" ;; esac
done
# Drift guard: every plugin script the drain prose names must be admitted. A new
# `scripts/<x>.sh` call in review-heal (every skills/review-heal/*.md) / the runner without an allowlist entry
# would be denied at runtime under dontAsk — the same silent breakage as F1.
# Exempt: scripts the prose names but the drain model never runs itself.
#   dispatch-pr-review.sh  — this dispatcher (the drain never re-dispatches itself)
#   worktree-salvage.sh    — run by this dispatcher's teardown trap, not the model
#   pr-postmortem-gather.sh, bump-version.sh — run INSIDE dispatch-pr-postmortem.sh /
#                            release-refold.sh, which are admitted
#   automate-helpers.sh    — admitted per subcommand (checked above)
EXEMPT28=" dispatch-pr-review.sh worktree-salvage.sh pr-postmortem-gather.sh bump-version.sh automate-helpers.sh "
for s28 in $(grep -ohE 'scripts/[a-z0-9_-]+\.(sh|py)' "$HERE/../skills/review-heal/"*.md "$HERE/../agents/review-pr.md" | sed 's#scripts/##' | sort -u); do
  case "$EXEMPT28" in *" $s28 "*) continue ;; esac
  case "$AT28" in *"Bash(bash $HERE/$s28 *)"*) ;; *) f28="$f28 script-not-admitted:$s28" ;; esac
done
# ...and the prose must not tell the drain to call raw `gh api` (it would be denied).
grep -nE '^(gh api|  *gh api)' "$HERE/../skills/review-heal/"*.md "$HERE/../agents/review-pr.md" >/dev/null && f28="$f28 prose-raw-gh-api"
if [ -z "$f28" ]; then
  ok "drain allowlist shape: no gh api / gh pr merge, gate-eval unreachable, exact push, no literal-star or \${} rules, .git/.claude denied, every drain script admitted"
else
  no "drain allowlist shape wrong:$f28"
fi
rm -rf "$WD"

echo "== 29. (BLOCKING — Real-path binding) real stubbed launch args= carries the SAME pinned flags, not just the DRY_RUN diagnostic =="
fresh_git_repo >/dev/null
run_real "$FX_REPO" "$PR"
RC29=$RUN_RC
# the launch is detached: wait for the stub's own log line before reading it (the wrapper's synchronous
# process-registry call runs before claude, so the line is never there the instant the dispatcher returns)
wait_for_file_content "$FX_CLAUDE_LOG" "cwd=$(expected_wt_path "$FX_REPO")" 15 || true
ARGS_LINE="$(grep -F "cwd=$(expected_wt_path "$FX_REPO")" "$FX_CLAUDE_LOG" 2>/dev/null || true)"
if [ "$RC29" -eq 0 ] \
   && grep -q -- '--permission-mode dontAsk' < <(printf '%s' "$ARGS_LINE") \
   && grep -q -- 'Read,Grep,Glob,Task' < <(printf '%s' "$ARGS_LINE") \
   && grep -q -- 'Bash(git push origin' < <(printf '%s' "$ARGS_LINE") \
   && grep -qF -- 'Write(./**),Edit(./**)' < <(printf '%s' "$ARGS_LINE") \
   && grep -q -- '--disallowedTools WebFetch,WebSearch' < <(printf '%s' "$ARGS_LINE") \
   && grep -q -- '--agent loomwright:review-pr-runner' < <(printf '%s' "$ARGS_LINE"); then
  ok "real-path binding: captured args= carries --permission-mode/--allowedTools/--disallowedTools (not just DRY_RUN_DISPATCH) (args='$ARGS_LINE')"
else
  no "real-path binding wrong — the REAL WRAPPER invocation must carry the pinned flags too (rc=$RC29 args='$ARGS_LINE')"
fi
WT="$(expected_wt_path "$FX_REPO")"; wait_for_no_worktree "$FX_REPO" "$WT" || true
rm -rf "$(dirname "$FX_REPO")"

# permissive_home [mode] — build an isolated HOME with ~/.claude/settings.json
# resolving permissions.defaultMode to [mode] (default "auto" — the
# owner-machine live-evidence value from the requirement; also seeded with
# "acceptEdits" by the PR #248 review finding #1 regression test — acceptEdits
# auto-approves file edits without prompting and must classify permissive the
# same as auto/bypassPermissions). Echoes the HOME path.
permissive_home() {
  local mode="${1:-auto}"
  local h; h="$(mktemp -d)"
  mkdir -p "$h/.claude"
  printf '{"permissions":{"defaultMode":"%s"}}\n' "$mode" > "$h/.claude/settings.json"
  printf '%s' "$h"
}

# malformed_home — an isolated HOME whose ~/.claude/settings.json is invalid
# JSON — the "unreadable" (malformed) fail-CLOSED case. Echoes the HOME path.
malformed_home() {
  local h; h="$(mktemp -d)"
  mkdir -p "$h/.claude"
  printf '{not valid json' > "$h/.claude/settings.json"
  printf '%s' "$h"
}

echo "== 30. regime probe (DRY_RUN): permissive defaultMode + no opt-out => LOOMWRIGHT_PR_IS_FORK=1 + marker regime=permissive_refused =="
WD="$(fresh_repo)"
RUN_HOME="$(permissive_home)"
run_dispatch "$WD" "$PR"
LINE="$(printf '%s' "$RUN_OUT" | grep 'DRY_RUN_DISPATCH' || true)"
MARKER_CONTENT="$(cat "$WD/.supervisor/review-dispatch/$(pr_hash)" 2>/dev/null || true)"
if [ "$RUN_RC" -eq 0 ] \
   && grep -q -- 'LOOMWRIGHT_PR_IS_FORK=1' < <(printf '%s' "$LINE") \
   && grep -q 'regime=permissive_refused' < <(printf '%s' "$MARKER_CONTENT"); then
  ok "regime probe DRY_RUN permissive-refused: LOOMWRIGHT_PR_IS_FORK=1 + marker regime=permissive_refused (line='$LINE')"
else
  no "regime probe DRY_RUN permissive-refused wrong (line='$LINE' marker='$MARKER_CONTENT')"
fi
rm -rf "$WD" "$RUN_HOME"; unset RUN_HOME

echo "== 31. regime probe (DRY_RUN): permissive defaultMode + LOOMWRIGHT_DRAIN_ALLOW_PERMISSIVE=1 opt-out => dispatches normally =="
WD="$(fresh_repo)"
RUN_HOME="$(permissive_home)"
RUN_OUT="$( cd "$WD" && HOME="$RUN_HOME" LOOMWRIGHT_REVIEW_DISPATCH_DRY_RUN=1 LOOMWRIGHT_DRAIN_ALLOW_PERMISSIVE=1 bash "$DISPATCH" "$PR" 2>/dev/null )"
RUN_RC=$?
LINE="$(printf '%s' "$RUN_OUT" | grep 'DRY_RUN_DISPATCH' || true)"
MARKER_CONTENT="$(cat "$WD/.supervisor/review-dispatch/$(pr_hash)" 2>/dev/null || true)"
if [ "$RUN_RC" -eq 0 ] \
   && ! grep -q -- 'LOOMWRIGHT_PR_IS_FORK' < <(printf '%s' "$LINE") \
   && ! grep -q 'permissive_refused' < <(printf '%s' "$MARKER_CONTENT"); then
  ok "regime probe DRY_RUN opt-out: dispatches normally, no forced fork-degrade, marker not permissive_refused (line='$LINE')"
else
  no "regime probe DRY_RUN opt-out wrong (line='$LINE' marker='$MARKER_CONTENT')"
fi
rm -rf "$WD" "$RUN_HOME"; unset RUN_HOME

echo "== 32. regime probe: unreadable (malformed JSON) settings => treated as permissive => refused (fail CLOSED) =="
WD="$(fresh_repo)"
RUN_HOME="$(malformed_home)"
run_dispatch "$WD" "$PR"
LINE="$(printf '%s' "$RUN_OUT" | grep 'DRY_RUN_DISPATCH' || true)"
MARKER_CONTENT="$(cat "$WD/.supervisor/review-dispatch/$(pr_hash)" 2>/dev/null || true)"
if [ "$RUN_RC" -eq 0 ] \
   && grep -q -- 'LOOMWRIGHT_PR_IS_FORK=1' < <(printf '%s' "$LINE") \
   && grep -q 'regime=permissive_refused' < <(printf '%s' "$MARKER_CONTENT"); then
  ok "regime probe malformed-JSON: treated as unreadable => permissive => refused (never assumed safe)"
else
  no "regime probe malformed-JSON wrong (line='$LINE' marker='$MARKER_CONTENT') — unreadable settings must fail CLOSED"
fi
rm -rf "$WD" "$RUN_HOME"; unset RUN_HOME

echo "== 33. regime probe (REAL path): permissive settings propagate LOOMWRIGHT_PR_IS_FORK=1 into the actual launch env =="
fresh_git_repo >/dev/null
RUN_HOME="$(permissive_home)"
run_real "$FX_REPO" "$PR"
RC33=$RUN_RC
WT="$(expected_wt_path "$FX_REPO")"
wait_for_file_content "$FX_CLAUDE_LOG" "cwd=$WT" 15 || true   # detached launch (see case 29)
ARGS_LINE="$(grep -F "cwd=$WT" "$FX_CLAUDE_LOG" 2>/dev/null || true)"
H="$(pr_hash)"
MARKER_CONTENT="$(cat "$FX_REPO/.supervisor/review-dispatch/$H" 2>/dev/null || true)"
if [ "$RC33" -eq 0 ] \
   && grep -q 'fork=1' < <(printf '%s' "$ARGS_LINE") \
   && grep -q 'regime=permissive_refused' < <(printf '%s' "$MARKER_CONTENT"); then
  ok "regime probe REAL permissive-refused: launched env carries fork=1, marker regime=permissive_refused"
else
  no "regime probe REAL permissive-refused wrong (rc=$RC33 args='$ARGS_LINE' marker='$MARKER_CONTENT')"
fi
wait_for_no_worktree "$FX_REPO" "$WT" || true
rm -rf "$(dirname "$FX_REPO")" "$RUN_HOME"; unset RUN_HOME

echo "== 34. (AC — PERMISSION_REGIME_UNPINNABLE) claude build whose --help lacks --permission-mode => exit 0, NO marker, no real launch =="
fresh_git_repo >/dev/null
# Overwrite stub-claude so --help answers WITHOUT --permission-mode/dontAsk — simulates
# an incompatible/older claude build. The dispatcher must refuse rather than guess.
cat > "$FX_BIN/stub-claude" <<'CLEOF'
#!/usr/bin/env bash
if [ "$1" = "--help" ]; then
  printf -- '--some-other-flag <x>\n'
  exit 0
fi
printf 'cwd=%s args=%s\n' "$(pwd)" "$*" >> "$FX_CLAUDE_LOG_PATH"
exit 0
CLEOF
# Substitute the log path (avoids re-deriving the CLEOF-quoting dance above).
sed -i.bak "s#FX_CLAUDE_LOG_PATH#$FX_CLAUDE_LOG#" "$FX_BIN/stub-claude" && rm -f "$FX_BIN/stub-claude.bak"
chmod +x "$FX_BIN/stub-claude"
run_real "$FX_REPO" "$PR"
RC34=$RUN_RC
H="$(pr_hash)"
NO_MARKER=0; [ ! -e "$FX_REPO/.supervisor/review-dispatch/$H" ] && NO_MARKER=1
NO_LOCK=0; [ ! -d "$FX_REPO/.supervisor/review-dispatch/$H.lock" ] && NO_LOCK=1
NO_REAL_LAUNCH=0; [ ! -s "$FX_CLAUDE_LOG" ] && NO_REAL_LAUNCH=1
if [ "$RC34" -eq 0 ] && [ "$NO_MARKER" -eq 1 ] && [ "$NO_LOCK" -eq 1 ] && [ "$NO_REAL_LAUNCH" -eq 1 ]; then
  ok "PERMISSION_REGIME_UNPINNABLE: exit 0, no marker, no lock, no real launch (probe ran, refused to dispatch)"
else
  no "PERMISSION_REGIME_UNPINNABLE wrong (rc=$RC34 no_marker=$NO_MARKER no_lock=$NO_LOCK no_real_launch=$NO_REAL_LAUNCH)"
fi
rm -rf "$(dirname "$FX_REPO")"

echo "== 35. MUTATION CONTROL: deleting the regime-probe guard flips BOTH the DRY_RUN and REAL permissive-refused assertions =="
MUT="$(mktemp -d)/dispatch-mutant.sh"
# Neutralize the ONE condition that gates REGIME_REFUSED — force it permanently
# false, so a permissive/unreadable regime is never refused regardless of input.
sed 's/if \[ "\$PERMISSIVE" -eq 1 \]/if [ "0" -eq 1 ]/' "$DISPATCH" > "$MUT"
chmod +x "$MUT"
if cmp -s "$MUT" "$DISPATCH"; then
  no "mutation control: could not build the mutant — the guard line was not found, control inconclusive"
else
  # DRY_RUN half.
  WD="$(fresh_repo)"
  RUN_HOME="$(permissive_home)"
  MUT_OUT="$( cd "$WD" && HOME="$RUN_HOME" LOOMWRIGHT_REVIEW_DISPATCH_DRY_RUN=1 bash "$MUT" "$PR" 2>/dev/null )"
  MUT_LINE="$(printf '%s' "$MUT_OUT" | grep 'DRY_RUN_DISPATCH' || true)"
  DRY_FLIPPED=0
  grep -q -- 'LOOMWRIGHT_PR_IS_FORK' < <(printf '%s' "$MUT_LINE") || DRY_FLIPPED=1
  rm -rf "$WD"
  # Real-path half.
  fresh_git_repo >/dev/null
  ( cd "$FX_REPO" && PATH="$FX_BIN:$PATH" HOME="$RUN_HOME" LOOMWRIGHT_CLAUDE_BIN="$FX_BIN/stub-claude" bash "$MUT" "$PR" >/dev/null 2>&1 )
  WT="$(expected_wt_path "$FX_REPO")"
  wait_for_no_worktree "$FX_REPO" "$WT" || true
  H="$(pr_hash)"
  REAL_MARKER="$(cat "$FX_REPO/.supervisor/review-dispatch/$H" 2>/dev/null || true)"
  REAL_FLIPPED=0
  grep -q 'permissive_refused' < <(printf '%s' "$REAL_MARKER") || REAL_FLIPPED=1
  rm -rf "$(dirname "$FX_REPO")" "$RUN_HOME"
  if [ "$DRY_FLIPPED" -eq 1 ] && [ "$REAL_FLIPPED" -eq 1 ]; then
    ok "mutation control: removing the regime-probe guard flips BOTH dry-run and real-path permissive-refused to non-refused — the guard is load-bearing"
  else
    no "mutation control: mutant still refused (dry_flipped=$DRY_FLIPPED real_flipped=$REAL_FLIPPED) — the guard may be vacuous or the mutant missed it"
  fi
fi
rm -rf "$(dirname "$MUT")"
unset RUN_HOME

echo "== 36. regime probe (DRY_RUN): acceptEdits defaultMode => LOOMWRIGHT_PR_IS_FORK=1 + marker regime=permissive_refused (PR #248 finding #1) =="
WD="$(fresh_repo)"
RUN_HOME="$(permissive_home acceptEdits)"
run_dispatch "$WD" "$PR"
LINE="$(printf '%s' "$RUN_OUT" | grep 'DRY_RUN_DISPATCH' || true)"
MARKER_CONTENT="$(cat "$WD/.supervisor/review-dispatch/$(pr_hash)" 2>/dev/null || true)"
if [ "$RUN_RC" -eq 0 ] \
   && grep -q -- 'LOOMWRIGHT_PR_IS_FORK=1' < <(printf '%s' "$LINE") \
   && grep -q 'regime=permissive_refused' < <(printf '%s' "$MARKER_CONTENT"); then
  ok "regime probe DRY_RUN acceptEdits-refused: LOOMWRIGHT_PR_IS_FORK=1 + marker regime=permissive_refused (line='$LINE')"
else
  no "regime probe DRY_RUN acceptEdits-refused wrong — acceptEdits must be treated as permissive, not fallen-through (line='$LINE' marker='$MARKER_CONTENT')"
fi
rm -rf "$WD" "$RUN_HOME"; unset RUN_HOME

echo "== 37. (death detection) real launch with NO REVIEW_HEAL_RESULT => .died marker (ts/pr_url/exit_code/last_log_line/attempt), DRAIN_DIED in log, marker still exists =="
fresh_git_repo >/dev/null
stub_claude_no_result "$FX_BIN"
run_real "$FX_REPO" "$PR"
RC37=$RUN_RC
WT="$(expected_wt_path "$FX_REPO")"
H="$(pr_hash)"
LOCK="$FX_REPO/.supervisor/review-dispatch/$H.lock"
wait_for_teardown "$FX_REPO" "$WT" "$LOCK" || true
DIED="$FX_REPO/.supervisor/review-dispatch/$H.died"
D_TS="$(awk -F'\t' '$1=="ts"{print $2; exit}' "$DIED" 2>/dev/null || true)"
D_PR="$(awk -F'\t' '$1=="pr_url"{print $2; exit}' "$DIED" 2>/dev/null || true)"
D_EC="$(awk -F'\t' '$1=="exit_code"{print $2; exit}' "$DIED" 2>/dev/null || true)"
D_LAST="$(awk -F'\t' '$1=="last_log_line"{print $2; exit}' "$DIED" 2>/dev/null || true)"
D_ATT="$(awk -F'\t' '$1=="attempt"{print $2; exit}' "$DIED" 2>/dev/null || true)"
HDR="$(cat "$FX_REPO"/.supervisor/logs/review-pr-dispatch-*.log 2>/dev/null || true)"
DRAIN_DIED_OK=0; grep -q '^DRAIN_DIED' < <(printf '%s' "$HDR") && DRAIN_DIED_OK=1
MARKER_STILL_THERE=0; [ -f "$FX_REPO/.supervisor/review-dispatch/$H" ] && MARKER_STILL_THERE=1
if [ "$RC37" -eq 0 ] && [ -f "$DIED" ] && [ -n "$D_TS" ] && [ "$D_PR" = "$PR" ] \
   && [ -n "$D_EC" ] && [ -n "$D_LAST" ] && [ "$D_ATT" = "1" ] \
   && [ "$DRAIN_DIED_OK" -eq 1 ] && [ "$MARKER_STILL_THERE" -eq 1 ]; then
  ok "death detection: .died written with all 4 fields + attempt=1, DRAIN_DIED in log, durable marker untouched"
else
  no "death detection wrong (rc=$RC37 died_exists=$([ -f "$DIED" ] && echo 1 || echo 0) ts='$D_TS' pr='$D_PR' ec='$D_EC' last='$D_LAST' attempt='$D_ATT' drain_died=$DRAIN_DIED_OK marker=$MARKER_STILL_THERE)"
fi
rm -rf "$(dirname "$FX_REPO")"

echo "== 38. (death detection) real launch that DOES print REVIEW_HEAL_RESULT => NO .died marker written =="
fresh_git_repo >/dev/null
run_real "$FX_REPO" "$PR"
RC38=$RUN_RC
WT="$(expected_wt_path "$FX_REPO")"
H="$(pr_hash)"
LOCK="$FX_REPO/.supervisor/review-dispatch/$H.lock"
wait_for_teardown "$FX_REPO" "$WT" "$LOCK" || true
DIED="$FX_REPO/.supervisor/review-dispatch/$H.died"
if [ "$RC38" -eq 0 ] && [ ! -e "$DIED" ]; then
  ok "no .died marker written when the runner produced a real REVIEW_HEAL_RESULT"
else
  no "unexpected .died marker for a completed drain (rc=$RC38 died_exists=$([ -e "$DIED" ] && echo 1 || echo 0))"
fi
rm -rf "$(dirname "$FX_REPO")"

echo "== 39/40/41. (bounded re-dispatch) exactly ONE automatic re-dispatch after a death; a SECOND death writes attempt=2; a THIRD dispatch is refused (bounded, never unbounded) =="
fresh_git_repo >/dev/null
stub_claude_no_result "$FX_BIN"
H="$(pr_hash)"
DIED="$FX_REPO/.supervisor/review-dispatch/$H.died"
WT="$(expected_wt_path "$FX_REPO")"
LOCK="$FX_REPO/.supervisor/review-dispatch/$H.lock"

# Attempt 1: dispatch dies -> .died written with attempt=1 (first death, default).
run_real "$FX_REPO" "$PR"; RC_A1=$RUN_RC
wait_for_teardown "$FX_REPO" "$WT" "$LOCK" || true
ATTEMPT1="$(awk -F'\t' '$1=="attempt"{print $2; exit}' "$DIED" 2>/dev/null || true)"
CALLS_AFTER_1="$(wc -l < "$FX_CLAUDE_LOG" 2>/dev/null | tr -d ' ' || echo 0)"

# Attempt 2 (the ONE automatic re-dispatch, since marker+died-attempt=1 count as
# "not dispatched"): dies again -> .died OVERWRITTEN with attempt=2.
run_real "$FX_REPO" "$PR"; RC_A2=$RUN_RC
wait_for_teardown "$FX_REPO" "$WT" "$LOCK" || true
ATTEMPT2="$(awk -F'\t' '$1=="attempt"{print $2; exit}' "$DIED" 2>/dev/null || true)"
CALLS_AFTER_2="$(wc -l < "$FX_CLAUDE_LOG" 2>/dev/null | tr -d ' ' || echo 0)"

# Attempt 3: marker + died-attempt=2 now count as GENUINELY dispatched/exhausted
# -> refused, NO third claude launch (bounded, never unbounded).
run_real "$FX_REPO" "$PR"; RC_A3=$RUN_RC
CALLS_AFTER_3="$(wc -l < "$FX_CLAUDE_LOG" 2>/dev/null | tr -d ' ' || echo 0)"

if [ "$RC_A1" -eq 0 ] && [ "$RC_A2" -eq 0 ] && [ "$RC_A3" -eq 0 ] \
   && [ "$ATTEMPT1" = "1" ] && [ "$ATTEMPT2" = "2" ] \
   && [ "$CALLS_AFTER_2" -gt "$CALLS_AFTER_1" ] \
   && [ "$CALLS_AFTER_3" -eq "$CALLS_AFTER_2" ]; then
  ok "bounded re-dispatch: 1st death attempt=1, exactly ONE automatic re-dispatch ran (2nd death attempt=2), 3rd dispatch refused (no 3rd launch) — bounded, never unbounded"
else
  no "bounded re-dispatch wrong (rc1=$RC_A1 rc2=$RC_A2 rc3=$RC_A3 attempt1='$ATTEMPT1' attempt2='$ATTEMPT2' calls1=$CALLS_AFTER_1 calls2=$CALLS_AFTER_2 calls3=$CALLS_AFTER_3)"
fi
rm -rf "$(dirname "$FX_REPO")"

echo "== 42. MUTATION CONTROL (BLOCKING): deleting the trap's REVIEW_HEAL_RESULT grep => the .died-marker assertion for the no-result case now FAILS =="
MUT42="$(mktemp -d)/dispatch-mutant-death.sh"
# Neutralize the ONE condition that gates death-detection: force the trap to
# ALWAYS take the "a result was produced" branch, regardless of what (if
# anything) the runner ever printed to $_log. If death detection is genuinely
# driven by this grep (not merely asserted in a comment), the mutant must
# NEVER write a .died marker even for the no-result stub — proving the
# .died-marker assertion in case 37 above is load-bearing, not vacuous.
sed 's#grep -q "REVIEW_HEAL_RESULT" "$_log" 2>/dev/null#true#' "$DISPATCH" > "$MUT42"
chmod +x "$MUT42"
if cmp -s "$MUT42" "$DISPATCH"; then
  no "MUTATION CONTROL (BLOCKING): could not build the mutant — the trap grep line was not found, control inconclusive"
elif ! bash -n "$MUT42" 2>/dev/null; then
  no "MUTATION CONTROL (BLOCKING): the mutant does not parse — cannot discriminate anything"
else
  fresh_git_repo >/dev/null
  stub_claude_no_result "$FX_BIN"
  H="$(pr_hash)"
  DIED="$FX_REPO/.supervisor/review-dispatch/$H.died"
  WT="$(expected_wt_path "$FX_REPO")"
  LOCK="$FX_REPO/.supervisor/review-dispatch/$H.lock"
  ( cd "$FX_REPO" && PATH="$FX_BIN:$PATH" HOME="$FX_REPO/.fakehome" \
      LOOMWRIGHT_CLAUDE_BIN="$FX_BIN/stub-claude" bash "$MUT42" "$PR" >/dev/null 2>&1 )
  wait_for_teardown "$FX_REPO" "$WT" "$LOCK" || true
  if [ ! -e "$DIED" ]; then
    ok "MUTATION CONTROL (BLOCKING) CONFIRMED: with the trap grep neutralized, the no-result case no longer writes .died (assertion 37 flips to FAIL against the mutant) — death detection IS driven by that grep, not merely asserted"
  else
    no "MUTATION CONTROL (BLOCKING) REFUTED: the mutant STILL wrote a .died marker for the no-result case — death detection may not actually be driven by the grep (or the mutation did not take effect at runtime)"
  fi
  rm -rf "$(dirname "$FX_REPO")"
fi
rm -rf "$(dirname "$MUT42")"

echo "== 43. (guard pre-arm, six-phase-loop-gaps/02) DRY_RUN names the guard uuid TWICE: --session-id flag + a DRY_RUN_GUARD_ARM line, same value =="
WD="$(fresh_repo)"
run_dispatch "$WD" "$PR"
SID_FLAG="$(printf '%s' "$RUN_OUT" | grep -o -- '--session-id [^ ]*' | head -1 | awk '{print $2}')"
SID_GUARD_LINE="$(printf '%s' "$RUN_OUT" | grep '^DRY_RUN_GUARD_ARM:' | awk '{print $2}')"
if [ -n "$SID_FLAG" ] && [ "$SID_FLAG" = "$SID_GUARD_LINE" ]; then
  ok "DRY_RUN names the guard uuid twice, identically (--session-id $SID_FLAG == DRY_RUN_GUARD_ARM $SID_GUARD_LINE)"
else
  no "DRY_RUN guard-uuid mismatch (--session-id='$SID_FLAG' DRY_RUN_GUARD_ARM='$SID_GUARD_LINE')"
fi
rm -rf "$WD"

echo "== 44. (guard pre-arm) real launch: <worktree>/.supervisor/guard/<uuid>.json exists BEFORE the launch, named by the SAME uuid passed via --session-id =="
fresh_git_repo >/dev/null
# A slow stub (captures args, sleeps briefly before exiting) gives this test a
# reliable window to inspect the sibling worktree BEFORE the trap's teardown
# removes it — the guard marker lives inside the worktree and is gone once
# teardown completes, unlike the durable `.supervisor/review-dispatch/` marker.
cat > "$FX_BIN/stub-claude" <<CLEOF
#!/usr/bin/env bash
if [ "\$1" = "--help" ]; then
  printf -- '--permission-mode <mode> (choices: "acceptEdits", "auto", "bypassPermissions", "manual", "dontAsk", "plan")\n'
  printf -- '--allowedTools, --allowed-tools <tools...>\n'
  printf -- '--disallowedTools, --disallowed-tools <tools...>\n'
  exit 0
fi
printf 'cwd=%s args=%s\n' "\$(pwd)" "\$*" >> "$FX_CLAUDE_LOG"
sleep 1.5
printf 'REVIEW_HEAL_RESULT\n'
exit 0
CLEOF
chmod +x "$FX_BIN/stub-claude"
run_real "$FX_REPO" "$PR"
WT="$(expected_wt_path "$FX_REPO")"
GUARD_SID=""
GUARD_FILE_FOUND=0
for _i in $(seq 1 20); do
  if [ -d "$WT/.supervisor/guard" ]; then
    GUARD_SID="$(ls "$WT/.supervisor/guard" 2>/dev/null | sed 's/\.json$//' | head -1)"
    [ -n "$GUARD_SID" ] && [ -f "$WT/.supervisor/guard/$GUARD_SID.json" ] && GUARD_FILE_FOUND=1 && break
  fi
  sleep 0.1
done
wait_for_file_content "$FX_CLAUDE_LOG" "--session-id" 15 || true   # detached launch (see case 29)
CAPTURED_ARGS="$(cat "$FX_CLAUDE_LOG" 2>/dev/null || true)"
ARG_SID="$(printf '%s' "$CAPTURED_ARGS" | grep -o -- '--session-id [^ ]*' | head -1 | awk '{print $2}')"
H="$(pr_hash)"
LOCK="$FX_REPO/.supervisor/review-dispatch/$H.lock"
wait_for_teardown "$FX_REPO" "$WT" "$LOCK" || true
if [ "$GUARD_FILE_FOUND" -eq 1 ] && [ -n "$ARG_SID" ] && [ "$GUARD_SID" = "$ARG_SID" ]; then
  ok "real launch: guard marker <worktree>/.supervisor/guard/$GUARD_SID.json existed pre-teardown, matches --session-id $ARG_SID passed to claude"
else
  no "real launch guard pre-arm wrong (guard_sid='$GUARD_SID' found=$GUARD_FILE_FOUND arg_sid='$ARG_SID' args='$CAPTURED_ARGS')"
fi
rm -rf "$(dirname "$FX_REPO")"

echo "== 45. (af/39e AC12/AC16) real launch => ONE drain entry for the detached wrapper's pid; an unwritable registry still launches; mutation control =="
# drain_reg_run <dispatcher> <registry dir> — a fresh G2 fixture, a real launch through <dispatcher> with a stub
# claude that also records its parent pid (the wrapper runs claude as a child, so that IS the wrapper's `$$`),
# then waits for teardown. Sets DR_RC DR_OUT DR_PPID DR_SID DR_TOP.
drain_reg_run() {
  local disp="$1" reg="$2" wt lock h
  fresh_git_repo >/dev/null
  cat > "$FX_BIN/stub-claude" <<CLEOF
#!/usr/bin/env bash
if [ "\$1" = "--help" ]; then
  printf -- '--permission-mode <mode> (choices: "acceptEdits", "auto", "bypassPermissions", "manual", "dontAsk", "plan")\n'
  printf -- '--allowedTools, --allowed-tools <tools...>\n'
  printf -- '--disallowedTools, --disallowed-tools <tools...>\n'
  exit 0
fi
printf 'ppid=%s args=%s\n' "\$PPID" "\$*" >> "$FX_CLAUDE_LOG"
printf '## REVIEW_HEAL_RESULT\n- schema_version: 1\n- decision: PASS\n'
exit 0
CLEOF
  chmod +x "$FX_BIN/stub-claude"
  DR_OUT="$( cd "$FX_REPO" && unset LOOMWRIGHT_PROC_MAX_S_DRAIN && PATH="$FX_BIN:$PATH" HOME="$FX_REPO/.fakehome" \
      LOOMWRIGHT_CLAUDE_BIN="$FX_BIN/stub-claude" LOOMWRIGHT_PROC_REGISTRY_DIR="$reg" bash "$disp" "$PR" 2>/dev/null )"
  DR_RC=$?
  wt="$(expected_wt_path "$FX_REPO")"; h="$(pr_hash)"; lock="$FX_REPO/.supervisor/review-dispatch/$h.lock"
  wait_for_teardown "$FX_REPO" "$wt" "$lock" || true
  DR_PPID="$(sed -n 's/^ppid=\([0-9]*\) .*/\1/p' "$FX_CLAUDE_LOG" 2>/dev/null | head -1)"
  DR_SID="$(grep -o -- '--session-id [^ ]*' "$FX_CLAUDE_LOG" 2>/dev/null | head -1 | awk '{print $2}')"
  DR_TOP="$( cd "$FX_REPO" && git rev-parse --show-toplevel 2>/dev/null )"
}
drain_entries() { { cat "$1"/*.json 2>/dev/null || true; } | jq -c -s '[.[] | select(.kind == "drain")]' 2>/dev/null || echo '[]'; }
# the wrapper's own entries (no owner_pid); its runner session's entry carries owner_pid = the wrapper (case 47)
wrapper_entries() { drain_entries "$1" | jq -c '[.[] | select(.owner_pid == null)]' 2>/dev/null || echo '[]'; }
REG45="$(mktemp -d)/procs"
drain_reg_run "$DISPATCH" "$REG45"
E45="$(wrapper_entries "$REG45")"
BAD45="$(jq -r --arg p "${DR_PPID:-0}" --arg top "$DR_TOP" --arg sid "$DR_SID" --arg pr "$PR" '
  if length != 1 then "\(length) drain entries (want 1)" else .[0] | [
    (if (.pid | tostring) != $p then "pid \(.pid) is not the wrapper pid \($p)" else empty end),
    (if .repo != $top then "repo \(.repo) (want \($top))" else empty end),
    (if .max_lifetime_s != 14400 then "max_lifetime_s \(.max_lifetime_s) (want the 4h default 14400)" else empty end),
    (if ((.stop_hint // "") | contains("kill -TERM \($p)")) | not then "stop_hint \(.stop_hint)" else empty end),
    (if .session_id != $sid then "session_id \(.session_id) (want the runner session \($sid))" else empty end),
    (if ((.purpose // "") | contains($pr)) | not then "purpose \(.purpose)" else empty end)
  ] | join("; ") end' <<<"$E45" 2>/dev/null)" || BAD45="unreadable entries: $E45"
if [ "$DR_RC" -eq 0 ] && [ -n "$DR_PPID" ] && [ -z "$BAD45" ]; then
  ok "real launch registered ONE drain entry: pid = the wrapper ($DR_PPID), repo, runner session id, stop hint, 4h default cap"
else
  no "drain registration wrong (rc=$DR_RC ppid='$DR_PPID': $BAD45)"
fi
OUT45_OK="$DR_OUT"
rm -rf "$(dirname "$FX_REPO")"
# AC16: the registry dir is a regular file (unwritable) — the drain still launches, exit and stdout unchanged
: > "$(dirname "$REG45")/not-a-dir"
drain_reg_run "$DISPATCH" "$(dirname "$REG45")/not-a-dir"
M45=0; [ -f "$FX_REPO/.supervisor/review-dispatch/$(pr_hash)" ] && M45=1
if [ "$DR_RC" -eq 0 ] && [ "$DR_OUT" = "$OUT45_OK" ] && [ -n "$DR_PPID" ] && [ "$M45" -eq 1 ]; then
  ok "unwritable registry: the drain still launched (claude ran, marker written), exit 0, stdout unchanged"
else
  no "unwritable registry changed the launch (rc=$DR_RC ran_ppid='$DR_PPID' marker=$M45 out='$DR_OUT' vs '$OUT45_OK')"
fi
rm -rf "$(dirname "$FX_REPO")"
# mutation control: a scripts/ dir whose dispatch-pr-review.sh lacks its ONE registration call line (gated: the
# line occurs once in WRAPPER, the copy non-empty, differing, bash -n) ⇒ the registration assertion goes red
MUTD45="$(mktemp -d)"
for e in "$HERE"/*; do [ "$(basename "$e")" = dispatch-pr-review.sh ] || ln -s "$e" "$MUTD45/$(basename "$e")"; done
C45="$(grep -c 'register --pid "$$"' "$DISPATCH")"
grep -v 'register --pid "$$"' "$DISPATCH" > "$MUTD45/dispatch-pr-review.sh"
if [ "$C45" != 1 ] || [ ! -s "$MUTD45/dispatch-pr-review.sh" ] || cmp -s "$DISPATCH" "$MUTD45/dispatch-pr-review.sh" \
   || ! bash -n "$MUTD45/dispatch-pr-review.sh" 2>/dev/null; then
  no "drain-registration mutant not built (registration lines=$C45)"
else
  REGM45="$(dirname "$REG45")/procs-mut"
  drain_reg_run "$MUTD45/dispatch-pr-review.sh" "$REGM45"
  if [ -n "$DR_PPID" ] && [ "$(wrapper_entries "$REGM45" | jq 'length' 2>/dev/null)" = 0 ]; then
    ok "MUTATION: the registration line deleted from WRAPPER ⇒ the launch ran but no wrapper drain entry (the registration assertion goes red)"
  else
    no "MUTATION did not discriminate (ran_ppid='$DR_PPID' entries=$(wrapper_entries "$REGM45"))"
  fi
  rm -rf "$(dirname "$FX_REPO")"
fi
rm -rf "$MUTD45" "$(dirname "$REG45")"

echo "== 46. (af/39e review) reaping the drain entry stops the runner BEFORE teardown; mutation control =="
# The registered pid is the WRAPPER (a WRAPPER KIND, proc-registry.sh header): `reap --apply` TERMs it, the
# wrapper must pass the TERM on to its background runner and wait for it, so trap_cleanup (salvage, worktree
# removal, lock release) runs only once the runner is gone. The stub runner records, when it exits, whether its
# worktree and the lock still existed — `present` proves teardown waited for it.
# drain_reap_run <dispatcher> — sets DQ_PID (stub runner pid) DQ_OUT (reap output) DQ_EXIT (stub's exit line)
# DQ_WT DQ_LOCK DQ_MARKER DQ_REG
drain_overdue() { [ "$(LOOMWRIGHT_PROC_REGISTRY_DIR="$1" bash "$HERE/proc-registry.sh" list | awk -F'\t' '$2 == "drain" && $5 != "overdue" { n++ } $2 == "drain" { m++ } END { print (m > 0 && n == 0) ? "overdue" : "no" }')" = overdue ]; }
# dq_kill — stop a leftover stub runner (and its sleep) after an assertion; a no-op when it is gone
dq_kill() { [ -n "$DQ_PID" ] || return 0; pkill -KILL -P "$DQ_PID" 2>/dev/null; kill -KILL "$DQ_PID" 2>/dev/null; return 0; }
drain_reap_run() {
  local disp="$1" wt lock
  fresh_git_repo >/dev/null
  wt="$(expected_wt_path "$FX_REPO")"; lock="$FX_REPO/.supervisor/review-dispatch/$(pr_hash).lock"
  DQ_WT="$wt"; DQ_LOCK="$lock"; DQ_MARKER="$FX_REPO/.supervisor/review-dispatch/$(pr_hash)"
  DQ_REG="$(dirname "$FX_REPO")/procs"; DQ_PID=""; DQ_OUT=""; DQ_EXIT=""
  cat > "$FX_BIN/stub-claude" <<CLEOF
#!/usr/bin/env bash
if [ "\$1" = "--help" ]; then
  printf -- '--permission-mode <mode> (choices: "acceptEdits", "auto", "bypassPermissions", "manual", "dontAsk", "plan")\n'
  printf -- '--allowedTools, --allowed-tools <tools...>\n'
  printf -- '--disallowedTools, --disallowed-tools <tools...>\n'
  exit 0
fi
printf '%s\n' "\$\$" > "$FX_REPO.stub.pid"
on_term() {
  kill "\$c" 2>/dev/null
  sleep 0.5   # fixed-sleep-ok: a simulated graceful shutdown, not a wait — teardown must not start under it
  printf 'exit wt=%s lock=%s\n' "\$([ -d "$wt" ] && echo present || echo gone)" "\$([ -d "$lock" ] && echo present || echo gone)" >> "$FX_CLAUDE_LOG"
  exit 0
}
trap on_term TERM
sleep 30 & c=\$!   # fixed-sleep-ok: the runner's long-lived body, ended by its TERM handler
wait "\$c"
CLEOF
  chmod +x "$FX_BIN/stub-claude"
  ( cd "$FX_REPO" && PATH="$FX_BIN:$PATH" HOME="$FX_REPO/.fakehome" LOOMWRIGHT_PROC_MAX_S_DRAIN=1 \
      LOOMWRIGHT_CLAUDE_BIN="$FX_BIN/stub-claude" LOOMWRIGHT_PROC_REGISTRY_DIR="$DQ_REG" bash "$disp" "$PR" >/dev/null 2>&1 )
  wait_for_cmd 15 test -s "$FX_REPO.stub.pid" && DQ_PID="$(cat "$FX_REPO.stub.pid")"
  [ -n "$DQ_PID" ] || return 0
  WAIT_LIB_WHAT="the drain entry to read overdue" wait_for_cmd 15 drain_overdue "$DQ_REG"
  DQ_OUT="$(LOOMWRIGHT_PROC_REGISTRY_DIR="$DQ_REG" bash "$HERE/proc-registry.sh" reap --apply 2>/dev/null)"
  wait_for_pid_gone "$DQ_PID" 10 || true
  wait_for_teardown "$FX_REPO" "$wt" "$lock" || true
  DQ_EXIT="$(grep '^exit wt=' "$FX_CLAUDE_LOG" 2>/dev/null | head -1)"
}
drain_reap_run "$DISPATCH"
DQ_ALIVE=0; [ -n "$DQ_PID" ] && kill -0 "$DQ_PID" 2>/dev/null && DQ_ALIVE=1
if [ -n "$DQ_PID" ] && [ "$DQ_ALIVE" -eq 0 ] && [ "$DQ_EXIT" = "exit wt=present lock=present" ] \
   && [ ! -d "$DQ_LOCK" ] && [ ! -d "$DQ_WT" ] && [ -f "$DQ_MARKER.died" ] \
   && [ "$(drain_entries "$DQ_REG" | jq 'length' 2>/dev/null)" = 0 ] && grep -q 'stopped (TERM' <<<"$DQ_OUT"; then
  ok "reap --apply of the drain entry: the runner got the TERM and exited while worktree + lock still existed; teardown then completed (.died recorded, entry removed)"
else
  no "drain reap orphaned or raced the runner (pid='$DQ_PID' alive=$DQ_ALIVE exit_line='$DQ_EXIT' lock_left=$([ -d "$DQ_LOCK" ] && echo y || echo n) wt_left=$([ -d "$DQ_WT" ] && echo y || echo n) died=$([ -f "$DQ_MARKER.died" ] && echo y || echo n) reap='$DQ_OUT')"
fi
dq_kill
rm -rf "$(dirname "$FX_REPO")"
# mutation control: WRAPPER without its TERM pass-on (`trap _fwd TERM INT HUP` deleted; gated: exactly one such
# line, the copy non-empty, differing, bash -n) ⇒ the reap kills the wrapper alone and the runner is orphaned
MUTD46="$(mktemp -d)"
for e in "$HERE"/*; do [ "$(basename "$e")" = dispatch-pr-review.sh ] || ln -s "$e" "$MUTD46/$(basename "$e")"; done
C46="$(grep -c '^trap _fwd TERM INT HUP$' "$DISPATCH")"
grep -v '^trap _fwd TERM INT HUP$' "$DISPATCH" > "$MUTD46/dispatch-pr-review.sh"
if [ "$C46" != 1 ] || [ ! -s "$MUTD46/dispatch-pr-review.sh" ] || cmp -s "$DISPATCH" "$MUTD46/dispatch-pr-review.sh" \
   || ! bash -n "$MUTD46/dispatch-pr-review.sh" 2>/dev/null; then
  no "drain TERM-forward mutant not built (trap lines=$C46)"
else
  drain_reap_run "$MUTD46/dispatch-pr-review.sh"
  DQ_ALIVE=0; [ -n "$DQ_PID" ] && kill -0 "$DQ_PID" 2>/dev/null && DQ_ALIVE=1
  if [ -n "$DQ_PID" ] && { [ "$DQ_ALIVE" -eq 1 ] || [ "$DQ_EXIT" != "exit wt=present lock=present" ]; }; then
    ok "MUTATION: the TERM pass-on deleted ⇒ the reaped wrapper tears down under its live runner (the leg goes red)"
  else
    no "MUTATION did not discriminate (pid='$DQ_PID' alive=$DQ_ALIVE exit_line='$DQ_EXIT')"
  fi
  dq_kill
  rm -rf "$(dirname "$FX_REPO")"
fi
rm -rf "$MUTD46"

echo "== 47. (af/39e review 2) the wrapper registers its runner session as its own drain entry; mutation control =="
# drain_session_run <dispatcher> — a real launch whose stub runner stays up (records its pid, sleeps until TERMed),
# then the registry read once the session entry is settled. Sets DS_PID DS_WRAP DS_E DS_CLS DS_REG.
drain_session_run() {
  local disp="$1" wt lock
  fresh_git_repo >/dev/null
  wt="$(expected_wt_path "$FX_REPO")"; lock="$FX_REPO/.supervisor/review-dispatch/$(pr_hash).lock"
  DS_REG="$(dirname "$FX_REPO")/procs"; DS_PID=""; DS_WRAP=""; DS_E="[]"; DS_CLS=""
  cat > "$FX_BIN/stub-claude" <<CLEOF
#!/usr/bin/env bash
if [ "\$1" = "--help" ]; then
  printf -- '--permission-mode <mode> (choices: "acceptEdits", "auto", "bypassPermissions", "manual", "dontAsk", "plan")\n'
  printf -- '--allowedTools, --allowed-tools <tools...>\n'
  printf -- '--disallowedTools, --disallowed-tools <tools...>\n'
  exit 0
fi
printf '%s %s\n' "\$\$" "\$PPID" > "$FX_REPO.stub.pid"
trap 'kill "\$c" 2>/dev/null; exit 0' TERM
sleep 30 & c=\$!   # fixed-sleep-ok: the runner's long-lived body, ended by its TERM handler
wait "\$c"
CLEOF
  chmod +x "$FX_BIN/stub-claude"
  ( cd "$FX_REPO" && PATH="$FX_BIN:$PATH" HOME="$FX_REPO/.fakehome" \
      LOOMWRIGHT_CLAUDE_BIN="$FX_BIN/stub-claude" LOOMWRIGHT_PROC_REGISTRY_DIR="$DS_REG" bash "$disp" "$PR" >/dev/null 2>&1 )
  wait_for_cmd 15 test -s "$FX_REPO.stub.pid" || return 0
  read -r DS_PID DS_WRAP < "$FX_REPO.stub.pid"
  # the session registration is backgrounded with a bounded (~2.5 s) --expect wait: settle on its entry, or time out
  WAIT_LIB_WHAT="the session entry" wait_for_cmd 8 eval '[ "$(drain_entries "$DS_REG" | jq --arg p "$DS_PID" "[.[] | select((.pid | tostring) == \$p)] | length" 2>/dev/null)" = 1 ]' || true
  DS_E="$(drain_entries "$DS_REG")"
  DS_CLS="$(LOOMWRIGHT_PROC_REGISTRY_DIR="$DS_REG" bash "$HERE/proc-registry.sh" list | awk -F'\t' -v p="$DS_PID" '$3 == p { print $5 }')"
  kill -TERM "$DS_WRAP" 2>/dev/null
  wait_for_pid_gone "$DS_PID" 10 || true
  wait_for_teardown "$FX_REPO" "$wt" "$lock" || true
}
drain_session_run "$DISPATCH"
BAD47="$(jq -r --arg p "${DS_PID:-0}" --arg w "${DS_WRAP:-0}" --arg pr "$PR" '
  [.[] | select((.pid | tostring) == $p)] | if length != 1 then "\(length) session entries (want 1)" else .[0] | [
    (if (.owner_pid | tostring) != $w then "owner_pid \(.owner_pid) is not the wrapper \($w)" else empty end),
    (if ((.purpose // "") | test("session")) and ((.purpose // "") | contains($pr)) | not then "purpose \(.purpose)" else empty end),
    (if .max_lifetime_s != 14400 then "max_lifetime_s \(.max_lifetime_s) (want the drain default)" else empty end)
  ] | join("; ") end' <<<"$DS_E" 2>/dev/null)" || BAD47="unreadable entries: $DS_E"
if [ -n "$DS_PID" ] && [ -z "$BAD47" ] && [ "$DS_CLS" = running ]; then
  ok "the wrapper registered its runner session: pid = the runner ($DS_PID), owner_pid = the wrapper ($DS_WRAP), hashed after the exec (running)"
else
  no "runner session registration wrong (pid='$DS_PID' wrapper='$DS_WRAP' class='$DS_CLS': $BAD47)"
fi
rm -rf "$(dirname "$FX_REPO")"
# mutation control: the session's ONE registration line deleted (gated: one such line, the copy non-empty, differing,
# bash -n) ⇒ the runner runs but no session entry
MUTD47="$(mktemp -d)"
for e in "$HERE"/*; do [ "$(basename "$e")" = dispatch-pr-review.sh ] || ln -s "$e" "$MUTD47/$(basename "$e")"; done
C47="$(grep -c 'register --pid "$_cp"' "$DISPATCH")"
grep -v 'register --pid "$_cp"' "$DISPATCH" > "$MUTD47/dispatch-pr-review.sh"
if [ "$C47" != 1 ] || [ ! -s "$MUTD47/dispatch-pr-review.sh" ] || cmp -s "$DISPATCH" "$MUTD47/dispatch-pr-review.sh" \
   || ! bash -n "$MUTD47/dispatch-pr-review.sh" 2>/dev/null; then
  no "session-registration mutant not built (lines=$C47)"
else
  drain_session_run "$MUTD47/dispatch-pr-review.sh"
  if [ -n "$DS_PID" ] && [ "$(jq --arg p "$DS_PID" '[.[] | select((.pid | tostring) == $p)] | length' <<<"$DS_E" 2>/dev/null)" = 0 ]; then
    ok "MUTATION: the session registration line deleted ⇒ the runner ran but no session entry (the leg goes red)"
  else
    no "MUTATION did not discriminate (pid='$DS_PID' entries=$DS_E)"
  fi
  rm -rf "$(dirname "$FX_REPO")"
fi
rm -rf "$MUTD47"

echo "== 48. (af/39e review 2) a TERM before the runner starts: the runner never runs, exit 143, teardown + .died; mutation control =="
# A scripts/ dir whose proc-registry.sh is a STUB that logs each call (with its parent — the wrapper) and sleeps
# through the wrapper's own registration; the TERM lands then, so bash runs the wrapper's trap only once that
# foreground call returns — before the launch line. The stub runner logs `ran` if it is ever started.
# drain_preterm_run <scripts dir> — sets DP_WRAP DP_CALLS DP_RAN DP_DIED_RC DP_WT DP_LOCK DP_MARKER
drain_preterm_run() {
  local dir="$1" calls
  fresh_git_repo >/dev/null
  DP_WT="$(expected_wt_path "$FX_REPO")"; DP_LOCK="$FX_REPO/.supervisor/review-dispatch/$(pr_hash).lock"
  DP_MARKER="$FX_REPO/.supervisor/review-dispatch/$(pr_hash)"; DP_WRAP=""; DP_CALLS=0; DP_RAN=0; DP_DIED_RC=""
  calls="$FX_REPO.reg.calls"
  cat > "$dir/proc-registry.sh" <<REGEOF
#!/usr/bin/env bash
printf '%s %s\n' "\$PPID" "\$*" >> "$calls"
case " \$* " in *" --owner-pid "*) ;; *) sleep 2 ;; esac   # fixed-sleep-ok: holds the wrapper inside its own registration
exit 0
REGEOF
  chmod +x "$dir/proc-registry.sh"
  cat > "$FX_BIN/stub-claude" <<CLEOF
#!/usr/bin/env bash
if [ "\$1" = "--help" ]; then
  printf -- '--permission-mode <mode> (choices: "acceptEdits", "auto", "bypassPermissions", "manual", "dontAsk", "plan")\n'
  printf -- '--allowedTools, --allowed-tools <tools...>\n'
  printf -- '--disallowedTools, --disallowed-tools <tools...>\n'
  exit 0
fi
echo ran >> "$FX_CLAUDE_LOG"
exit 0
CLEOF
  chmod +x "$FX_BIN/stub-claude"
  ( cd "$FX_REPO" && PATH="$FX_BIN:$PATH" HOME="$FX_REPO/.fakehome" \
      LOOMWRIGHT_CLAUDE_BIN="$FX_BIN/stub-claude" bash "$dir/dispatch-pr-review.sh" "$PR" >/dev/null 2>&1 )
  wait_for_cmd 15 test -s "$calls" || return 0
  DP_WRAP="$(head -1 "$calls" | cut -d' ' -f1)"
  kill -TERM "$DP_WRAP" 2>/dev/null
  wait_for_pid_gone "$DP_WRAP" 15 || true
  wait_for_teardown "$FX_REPO" "$DP_WT" "$DP_LOCK" || true
  sleep 0.5   # fixed-sleep-ok: lets a (mutant) runner and its backgrounded session registration log, if they ever started
  DP_CALLS="$(awk 'END { print NR }' "$calls")"
  grep -qx ran "$FX_CLAUDE_LOG" 2>/dev/null && DP_RAN=1
  DP_DIED_RC="$(awk -F'\t' '$1 == "exit_code" { print $2 }' "$DP_MARKER.died" 2>/dev/null)"
}
MUTD48="$(mktemp -d)"
for e in "$HERE"/*; do case "$(basename "$e")" in proc-registry.sh) ;; *) ln -s "$e" "$MUTD48/$(basename "$e")" ;; esac; done
drain_preterm_run "$MUTD48"
if [ -n "$DP_WRAP" ] && [ "$DP_RAN" = 0 ] && [ "$DP_CALLS" = 1 ] && [ "$DP_DIED_RC" = 143 ] \
   && [ ! -d "$DP_LOCK" ] && [ ! -d "$DP_WT" ]; then
  ok "TERM during the wrapper's own registration: the runner never ran, exit 143 in .died, worktree + lock torn down"
else
  no "pre-launch TERM wrong (wrapper='$DP_WRAP' ran=$DP_RAN registry_calls=$DP_CALLS died_exit='$DP_DIED_RC' lock_left=$([ -d "$DP_LOCK" ] && echo y || echo n) wt_left=$([ -d "$DP_WT" ] && echo y || echo n))"
fi
rm -rf "$(dirname "$FX_REPO")"
# mutation control: the pre-launch `_term` check deleted (gated: one such line, the copy non-empty, differing,
# bash -n) ⇒ the runner is started (it runs, or at least its session registration is called) despite the TERM
rm -f "$MUTD48/dispatch-pr-review.sh"
C48="$(grep -c '^\[ -z "\$_term" \] || { _exit_code=143; exit 143; }$' "$DISPATCH")"
grep -v '^\[ -z "\$_term" \] || { _exit_code=143; exit 143; }$' "$DISPATCH" > "$MUTD48/dispatch-pr-review.sh"
if [ "$C48" != 1 ] || [ ! -s "$MUTD48/dispatch-pr-review.sh" ] || cmp -s "$DISPATCH" "$MUTD48/dispatch-pr-review.sh" \
   || ! bash -n "$MUTD48/dispatch-pr-review.sh" 2>/dev/null; then
  no "pre-launch TERM mutant not built (lines=$C48)"
else
  drain_preterm_run "$MUTD48"
  if [ -n "$DP_WRAP" ] && { [ "$DP_RAN" = 1 ] || [ "$DP_CALLS" != 1 ]; }; then
    ok "MUTATION: the pre-launch _term check deleted ⇒ the runner is started after the TERM (the leg goes red)"
  else
    no "MUTATION did not discriminate (wrapper='$DP_WRAP' ran=$DP_RAN registry_calls=$DP_CALLS)"
  fi
  rm -rf "$(dirname "$FX_REPO")"
fi
rm -rf "$MUTD48"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
