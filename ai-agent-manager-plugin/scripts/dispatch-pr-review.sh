#!/usr/bin/env bash
# dispatch-pr-review.sh — POST-/supervisor REVIEW-DRAIN DISPATCHER (review-heal)
#
# Canonical names are coined in skills/review-heal/SKILL.md — consumed VERBATIM here:
#   legacy enable : auto_review: true   in .supervisor/config.json (legacy
#                   .supervisor/notify-config.json still read as a fallback) (or --auto-review)
#   opt-out flag  : --no-auto-review    (suppresses the dispatch entirely)
#   runner agent  : ai-agent-manager-plugin:review-pr-runner
#   until-mergeable signal (S2-pinned env-var contract — §"Until-Mergeable Dispatch Signal"):
#     AI_AGENT_MANAGER_UNTIL_MERGEABLE     — export "1" by default (opt-out)
#     AI_AGENT_MANAGER_CHECK_WAIT_TIMEOUT  — optional; export when --check-wait-timeout / config set
#     AI_AGENT_MANAGER_REVIEW_CHECK_PATTERN — optional; export when --review-check-pattern / config set
#   until-mergeable opt-out: --no-until-mergeable (or auto_until_mergeable: false; DEFAULT true)
#
# CONTRACT
# --------
#   INVARIANT: ALWAYS exits 0. Called from Supervisor Phase 4.5's completion tail
#   (a LOAD-BEARING path) — it must NEVER hard-fail the tail. Every failure mode
#   (missing claude/jq/config, malformed config, already-dispatched, disabled) is
#   absorbed: log exactly ONE line to stderr and exit 0. Fire-and-forget.
#
#   DISPATCH GATING (config-file-driven, NOT env-var inheritance — AC5). The review
#   drain now dispatches BY DEFAULT after PR creation (AC7) — there is exactly ONE
#   dispatch per PR. It is dispatched UNLESS suppressed:
#     1. SUPPRESSED when --no-auto-review is passed, OR config `.auto_review == false`.
#     2. Otherwise ENABLED (default ON; --auto-review / `.auto_review == true` are the
#        legacy explicit-enable signals, now redundant with the default but still honored).
#   Reading config from a repo-local JSON file (via jq) — rather than an exported
#   env var — sidesteps the known ~/.zshrc env-propagation failure class where a
#   var exported only in an interactive rc never reaches a non-interactive
#   subprocess (same rationale as send-webhook.sh's webhook_url resolution).
#
#   UNTIL-MERGEABLE SIGNAL (AC7 — DEFAULT ON, opt-out). When a dispatch fires, the
#   detached runner is launched with AI_AGENT_MANAGER_UNTIL_MERGEABLE=1 EXPORTED by
#   default, so the runner forwards `--until-mergeable` to its inline /review-pr (the
#   external-channel drain). This is opt-out via --no-until-mergeable OR config
#   `.auto_until_mergeable == false` — when opted out the env var is NOT exported and
#   the runner runs the plain diff-only /review-pr loop. The signal is threaded via
#   ENV VARS (NOT a /review-pr slash string, NOT a new positional) — the --agent
#   runner form has no flag surface, which deliberately avoids the 11.1.1 spawn-depth
#   auto-delegation trap (see skills/review-heal/SKILL.md §"Until-Mergeable Dispatch
#   Signal"). --check-wait-timeout / --review-check-pattern (or their config keys
#   check_wait_timeout / review_check_pattern) are forwarded ONLY when set, via
#   AI_AGENT_MANAGER_CHECK_WAIT_TIMEOUT / AI_AGENT_MANAGER_REVIEW_CHECK_PATTERN.
#
#   COST / RUNAWAY GUARD + ISOLATION LIFECYCLE (AC4a, PINNED ORDER). Two distinct
#   guards key the dispatch off .supervisor/review-dispatch/:
#     - an ATOMIC per-PR LOCK (mkdir <pr_hash>.lock) = "someone is dispatching",
#       taken BEFORE the worktree so a concurrent dispatch (step 5.5 vs the
#       PostToolUse hook) loses the race and exits 0. Stale-lock reclaim (pid-dead
#       + no-marker + past-TTL) closes the crash-between-mkdir-and-marker wedge.
#     - a durable per-PR MARKER (<pr_hash>) = "a dispatch genuinely started",
#       written ONLY AFTER the worktree + RUN_LOG header succeed (never before), so
#       the marker NEVER lies: marker present <=> a dispatch genuinely started.
#   PINNED fail-safe order (do NOT reorder): (1) existing-marker-wins exit 0 ->
#   (2) verify claude launchable (else exit 0, NO marker) -> (3) atomic lock ->
#   (4) sibling worktree -> (5) RUN_LOG header -> (6) marker -> (7) launch wrapper.
#   A given PR is dispatched AT MOST ONCE (re-dispatch on a --continue re-run is
#   blocked by guard (1)). /review-pr NEVER creates a PR, so no review->review
#   recursion.
#
#   ISOLATED SIBLING WORKTREE (AC1/AC2/AC2b). The detached drain runs in its OWN
#   git worktree — a plugin-owned SIBLING of the primary checkout, OUTSIDE the
#   tracked tree (../{project}-review-{pr_hash_short}), created detached-HEAD at the
#   PR head SHA (`git worktree add --detach <path> <sha>`). This means the drain
#   NEVER shares a working tree/index with the inline Phase 4.5 self-heal — it
#   cannot be swept by an inline `git add -A` and pollutes nothing in `git status`.
#   Detached-HEAD avoids "branch already checked out" when the PR head == the inline
#   session's current branch (the same-branch case). A sibling path (never nested)
#   is what makes the collision the prior 4 PRs kept re-exposing structurally
#   impossible. See skills/review-heal/SKILL.md and agents/supervisor.md step 5.5.
#
#   FRESH DETACHED PROCESS + TRAP-OWNED CLEANUP (AC3). The launch is a brand-new
#   detached HEADLESS `claude -p --agent ai-agent-manager-plugin:review-pr-runner
#   <pr-url>` OS process, wrapped in a small `bash -c` process that OWNS
#   `trap cleanup EXIT`. On EXIT (normal, error, OR crash) the trap removes ONLY
#   this hash-keyed worktree + lock dir (executable cleanup, NOT a prompt
#   instruction the agent can skip — the exact reliability failure this saga is
#   about). The trap cd's OUT of the worktree and uses `git -C <main-gitdir>` so it
#   never runs from inside the dir being deleted. A fresh OS process means the
#   runner is the MAIN agent of its own session and can spawn child agents
#   (code-reviewer / fix worker) — see skills/review-heal/SKILL.md "Two entry
#   senses of fresh" (a). `-p` does NOT make the runner a subagent.
#
#   `-p`/--print is REQUIRED (mirrors dispatch-pr-postmortem.sh's fix in PR #63).
#   `--agent` ONLY selects which agent — it does NOT switch to headless mode; the
#   session is interactive by default (`claude --help`: "starts an interactive
#   session by default, use -p/--print for non-interactive output"). Detached with
#   stdin from /dev/null and no TTY, the no-`-p` form is fragile: depending on the
#   Claude Code version it can hang on the first permission prompt (no TTY to answer
#   it) rather than exit. `-p` runs the prompt non-interactively, makes permission
#   handling deterministic (auto-deny instead of a blocking prompt), and exits.
#
#   PERMISSIONS — deliberately NO --permission-mode / --dangerously-skip-permissions
#   (consistent with dispatch-pr-postmortem.sh). The detached run relies on the
#   project's EXISTING permission settings — best-effort posture. A fire-and-forget,
#   unattended dispatcher must NOT silently grant itself bypass-all-permissions
#   authority to run arbitrary edits + `git push`; that is a security decision the
#   user opts into via their own project settings. Consequence: in a locked-down
#   project the runner's fixes/pushes may be auto-denied under `-p` (review-only,
#   best-effort) — but it still exits cleanly and never hangs the dispatcher.
#
# USAGE
#   dispatch-pr-review.sh <pr-url> [--no-auto-review|--auto-review] \
#       [--no-until-mergeable] [--check-wait-timeout N] [--review-check-pattern <glob>]
#   dispatch-pr-review.sh --pr-url <pr-url> [--no-auto-review|--auto-review] \
#       [--no-until-mergeable] [--check-wait-timeout N] [--review-check-pattern <glob>]
#
# ENV (test/escape hatches — all optional)
#   AI_AGENT_MANAGER_REVIEW_DISPATCH_DRY_RUN=1
#     When set non-empty, the gating decision runs to completion but the real
#     `claude` process is NOT launched; instead the would-be command is printed
#     to stdout as `DRY_RUN_DISPATCH: <cmd>` and the marker is still written.
#     Used by test-dispatch-pr-review.sh so the self-test never spawns claude.
#   AI_AGENT_MANAGER_CLAUDE_BIN
#     Override the claude binary name (default `claude`). Lets a test point at a
#     stub on PATH if it ever wants to exercise the launch path.
#
# Style/structure mirrors send-webhook.sh (sibling fire-and-forget wrapper).

set -u
# Intentionally NO `set -e` / pipefail — wrapper must absorb every child failure.

log() { printf 'dispatch-pr-review: %s\n' "$1" >&2; }

# Back-compatible config path: prefer the new .supervisor/config.json, fall back
# to the legacy .supervisor/notify-config.json (new path wins when both exist).
# Resolution is file-level, not a key merge: a partial config.json shadows the legacy file entirely, so migrate the whole file.
CONFIG_FILE=".supervisor/config.json"
[ -r "$CONFIG_FILE" ] || CONFIG_FILE=".supervisor/notify-config.json"
DISPATCH_DIR=".supervisor/review-dispatch"
LOG_DIR=".supervisor/logs"
CLAUDE_BIN="${AI_AGENT_MANAGER_CLAUDE_BIN:-claude}"
RUNNER="ai-agent-manager-plugin:review-pr-runner"
DRY_RUN="${AI_AGENT_MANAGER_REVIEW_DISPATCH_DRY_RUN:-}"

# ---- Parse args -------------------------------------------------------------
# First bare (non-flag) argument is treated as the PR URL. --pr-url <url> also
# supported. --no-auto-review / --auto-review set the suppress/force signals.
# --no-until-mergeable opts out of the default until-mergeable signal;
# --check-wait-timeout / --review-check-pattern thread the optional tuning vars.
PR_URL=""
SUPPRESS=0            # --no-auto-review seen
FORCE=0               # --auto-review seen
NO_UNTIL_MERGEABLE=0  # --no-until-mergeable seen
CHECK_WAIT_TIMEOUT="" # --check-wait-timeout value (CLI overrides config)
REVIEW_CHECK_PATTERN="" # --review-check-pattern value (CLI overrides config)

while [ $# -gt 0 ]; do
  case "$1" in
    --pr-url)
      PR_URL="${2:-}"
      shift; [ $# -gt 0 ] && shift
      ;;
    --pr-url=*)
      PR_URL="${1#--pr-url=}"
      shift
      ;;
    --no-auto-review)
      SUPPRESS=1
      shift
      ;;
    --auto-review)
      FORCE=1
      shift
      ;;
    --no-until-mergeable)
      NO_UNTIL_MERGEABLE=1
      shift
      ;;
    --check-wait-timeout)
      CHECK_WAIT_TIMEOUT="${2:-}"
      shift; [ $# -gt 0 ] && shift
      ;;
    --check-wait-timeout=*)
      CHECK_WAIT_TIMEOUT="${1#--check-wait-timeout=}"
      shift
      ;;
    --review-check-pattern)
      REVIEW_CHECK_PATTERN="${2:-}"
      shift; [ $# -gt 0 ] && shift
      ;;
    --review-check-pattern=*)
      REVIEW_CHECK_PATTERN="${1#--review-check-pattern=}"
      shift
      ;;
    --*)
      # Unknown flag — ignore (forward compat).
      shift
      ;;
    *)
      # First bare argument is the PR URL; later bare args ignored.
      [ -z "$PR_URL" ] && PR_URL="$1"
      shift
      ;;
  esac
done

# ---- Opt-out short-circuit --------------------------------------------------
if [ "$SUPPRESS" -eq 1 ]; then
  log "--no-auto-review passed — review-drain dispatch suppressed"
  exit 0
fi

# ---- Require a PR URL -------------------------------------------------------
if [ -z "$PR_URL" ]; then
  log "no PR URL supplied — nothing to dispatch"
  exit 0
fi

# ---- Resolve enable signal (DEFAULT ON — AC7) -------------------------------
# The review drain now dispatches BY DEFAULT after PR creation. It is suppressed
# ONLY by --no-auto-review (handled above) OR config `.auto_review == false`.
# --auto-review / `.auto_review == true` are the legacy explicit-enable signals —
# now redundant with the default-ON behavior but still honored (they never DISABLE).
# Config is read via jq (NOT env var) — see header AC5 rationale.
ENABLED=1
if [ "$FORCE" -ne 1 ] && [ -r "$CONFIG_FILE" ] && command -v jq >/dev/null 2>&1; then
  # Read the RAW value (NOT `// empty`) — `.auto_review // empty` coerces the falsy
  # boolean `false` to empty, which would silently FAIL to suppress (the very case
  # this gate must honor). Test against the literal "false".
  AUTO_REVIEW="$(jq -r '.auto_review' "$CONFIG_FILE" 2>/dev/null || true)"
  if [ "$AUTO_REVIEW" = "false" ]; then
    ENABLED=0
  fi
fi

if [ "$ENABLED" -ne 1 ]; then
  # Explicitly suppressed via config — silent-ish no-op path.
  log "review-drain disabled (config .auto_review == false) — skipping"
  exit 0
fi

# ---- Resolve until-mergeable signal (DEFAULT ON — AC7, opt-out) -------------
# Default ON: export AI_AGENT_MANAGER_UNTIL_MERGEABLE=1 into the detached runner so
# it forwards --until-mergeable. Opt-out via --no-until-mergeable OR config
# `.auto_until_mergeable == false`. Note: read the RAW value (not `// empty`) and
# test against the literal "false" so the falsy boolean is not silently coerced
# (mirrors dispatch-pr-postmortem.sh's auto_postmortem handling).
UNTIL_MERGEABLE=1
if [ "$NO_UNTIL_MERGEABLE" -eq 1 ]; then
  UNTIL_MERGEABLE=0
elif [ -r "$CONFIG_FILE" ] && command -v jq >/dev/null 2>&1; then
  AUTO_UM="$(jq -r '.auto_until_mergeable' "$CONFIG_FILE" 2>/dev/null || true)"
  if [ "$AUTO_UM" = "false" ]; then
    UNTIL_MERGEABLE=0
  fi
fi

# Optional tuning — fall back to config keys when the CLI flag was not supplied.
if [ -z "$CHECK_WAIT_TIMEOUT" ] && [ -r "$CONFIG_FILE" ] && command -v jq >/dev/null 2>&1; then
  CHECK_WAIT_TIMEOUT="$(jq -r '.check_wait_timeout // empty' "$CONFIG_FILE" 2>/dev/null || true)"
fi
if [ -z "$REVIEW_CHECK_PATTERN" ] && [ -r "$CONFIG_FILE" ] && command -v jq >/dev/null 2>&1; then
  REVIEW_CHECK_PATTERN="$(jq -r '.review_check_pattern // empty' "$CONFIG_FILE" 2>/dev/null || true)"
fi

# ---- Per-PR dispatch marker (cost / runaway guard) --------------------------
# Key the marker by a hash of the PR URL so a given PR dispatches at most once.
mkdir -p "$DISPATCH_DIR" 2>/dev/null || true
PR_HASH=""
if command -v shasum >/dev/null 2>&1; then
  PR_HASH="$(printf '%s' "$PR_URL" | shasum 2>/dev/null | cut -d' ' -f1 || true)"
elif command -v sha1sum >/dev/null 2>&1; then
  PR_HASH="$(printf '%s' "$PR_URL" | sha1sum 2>/dev/null | cut -d' ' -f1 || true)"
fi
# Fallback to a sanitized URL if no hashing tool is present (still unique per PR).
if [ -z "$PR_HASH" ]; then
  PR_HASH="$(printf '%s' "$PR_URL" | tr -c 'A-Za-z0-9' '-' )"
fi
MARKER="$DISPATCH_DIR/$PR_HASH"
LOCK_DIR="$DISPATCH_DIR/$PR_HASH.lock"
LOCK_META="$LOCK_DIR/meta"
LOCK_TTL_SECONDS=1800   # conservative stale-lock TTL (30 min) — see AC4a-(i) reclaim

# A short hash slice for the SIBLING worktree path (deterministic from PR hash so
# the trap-cleanup can target exactly it — AC2b). Keep it short to bound the path.
PR_HASH_SHORT="$(printf '%s' "$PR_HASH" | cut -c1-12)"

# Resolve the primary repo's main gitdir + project basename so the worktree is a
# SIBLING of the primary checkout (../{project}-review-{hash}), NEVER nested under
# the repo working dir (a nested worktree could be swept by an inline `git add -A`,
# re-creating the very collision this change removes — AC2b).
REPO_TOPLEVEL="$(git rev-parse --show-toplevel 2>/dev/null || true)"
PROJECT_BASENAME="$(basename "${REPO_TOPLEVEL:-$PWD}")"
PARENT_DIR="$(dirname "${REPO_TOPLEVEL:-$PWD}")"
WT_PATH="$PARENT_DIR/${PROJECT_BASENAME}-review-${PR_HASH_SHORT}"

# ---- ① existing-marker-wins (AC4a, PINNED order — BEFORE lock/worktree) ------
# If a durable marker already exists for this PR, a dispatch genuinely started —
# never launch again. This preserves today's double-dispatch protection and must
# come BEFORE taking any lock or creating any worktree.
if [ -e "$MARKER" ]; then
  log "PR already dispatched this run (marker exists: $MARKER) — skipping re-dispatch"
  exit 0
fi

# ---- Dry-run short-circuit (TEST-ONLY exception — claude-independent) ---------
# In dry-run the claude process is never launched (no lock/worktree taken), so its
# presence on PATH is irrelevant. Emit the would-be command + write the marker (so
# the marker-guard path is still exercised) WITHOUT requiring the binary. This keeps
# the self-test (test-dispatch-pr-review.sh) claude-independent on CI runners that
# have no `claude` on PATH. DRY-RUN is the ONLY path that writes a marker without a
# real launch (or worktree/lock).
if [ -n "$DRY_RUN" ]; then
  # Emit the would-be exported env signal prefix (only the vars actually set) so the
  # self-test can assert the pinned until-mergeable contract without launching claude.
  ENV_PREFIX=""
  if [ "$UNTIL_MERGEABLE" -eq 1 ]; then
    ENV_PREFIX="AI_AGENT_MANAGER_UNTIL_MERGEABLE=1 "
    [ -n "$CHECK_WAIT_TIMEOUT" ] && ENV_PREFIX="${ENV_PREFIX}AI_AGENT_MANAGER_CHECK_WAIT_TIMEOUT=${CHECK_WAIT_TIMEOUT} "
    [ -n "$REVIEW_CHECK_PATTERN" ] && ENV_PREFIX="${ENV_PREFIX}AI_AGENT_MANAGER_REVIEW_CHECK_PATTERN=${REVIEW_CHECK_PATTERN} "
  fi
  printf 'DRY_RUN_DISPATCH: %snohup %s -p --agent %s %s\n' "$ENV_PREFIX" "$CLAUDE_BIN" "$RUNNER" "$PR_URL"
  printf '%s\n' "$PR_URL" > "$MARKER" 2>/dev/null || true
  exit 0
fi

# ---- ② verify the launcher is launchable (BEFORE lock/worktree/marker) -------
# A missing binary must NEVER leave a marker (the AC4a binary-check-precedes-marker
# invariant). This precedes the lock + worktree so we never create artifacts we
# then have to tear down for a launcher we cannot run.
if ! command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
  log "'$CLAUDE_BIN' not on PATH — cannot launch review-pr-runner, skipping (no marker)"
  exit 0
fi

# ---- ③ atomic per-PR lock BEFORE worktree creation (AC4a-i) -----------------
# `mkdir` is atomic: it fails if a concurrent dispatch (step 5.5 vs the PostToolUse
# hook) already holds the lock. The winner records metadata in the lock dir. The
# loser exits 0. Stale-lock reclaim (pid-dead + no-marker + past-TTL) closes the
# crash-between-mkdir-and-marker wedge.
DISPATCH_PID="$$"
NOW_EPOCH="$(date -u +%s 2>/dev/null || echo 0)"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo unknown)"
RUN_LOG="$LOG_DIR/review-pr-dispatch-$TIMESTAMP-$PR_HASH.log"

write_lock_meta() {
  {
    printf 'pr_url\t%s\n' "$PR_URL"
    printf 'pid\t%s\n' "$DISPATCH_PID"
    printf 'ts\t%s\n' "$NOW_EPOCH"
    printf 'worktree\t%s\n' "$WT_PATH"
    printf 'run_log\t%s\n' "$RUN_LOG"
  } > "$LOCK_META" 2>/dev/null || true
}

acquire_lock() {
  # Returns 0 when the lock is held by us, 1 when lost to a live/fresh dispatch.
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    write_lock_meta
    return 0
  fi
  # Lock exists — consider stale-lock reclaim. ALL THREE must hold:
  #   (a) NO durable marker (asserted — ① already guaranteed this), AND
  #   (b) recorded pid is NOT alive, AND
  #   (c) lock ts is older than LOCK_TTL_SECONDS.
  if [ -e "$MARKER" ]; then
    log "lost to a genuine dispatch (marker appeared) — skipping"
    return 1
  fi
  local lk_pid lk_ts age
  lk_pid="$(awk -F'\t' '$1=="pid"{print $2; exit}' "$LOCK_META" 2>/dev/null || true)"
  lk_ts="$(awk -F'\t' '$1=="ts"{print $2; exit}' "$LOCK_META" 2>/dev/null || true)"
  # (b) pid alive?
  if [ -n "$lk_pid" ] && kill -0 "$lk_pid" 2>/dev/null; then
    log "lost to a live dispatch (pid $lk_pid alive) — skipping"
    return 1
  fi
  # (c) past TTL?
  age=-1
  if [ -n "$lk_ts" ] && [ "$lk_ts" -ge 0 ] 2>/dev/null; then
    age=$(( NOW_EPOCH - lk_ts ))
  fi
  if [ "$age" -lt "$LOCK_TTL_SECONDS" ]; then
    log "lost to a fresh dispatch (lock age ${age}s < ${LOCK_TTL_SECONDS}s TTL) — skipping"
    return 1
  fi
  # Reclaim: clear ONLY this hash-keyed lock dir, then retry the atomic mkdir.
  log "reclaiming stale lock (pid ${lk_pid:-?} dead, age ${age}s ≥ ${LOCK_TTL_SECONDS}s TTL)"
  rm -rf "$LOCK_DIR" 2>/dev/null || true
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    write_lock_meta
    return 0
  fi
  log "lost the reclaim race to a concurrent dispatch — skipping"
  return 1
}

if ! acquire_lock; then
  exit 0
fi
# From here on we OWN the lock; release it on any early-return failure path.

# ---- ④ create the isolated SIBLING worktree (detached-HEAD, AC2/AC2b) --------
# Detached-HEAD at the PR head SHA avoids "branch already checked out" when the PR
# head == the inline session's current branch (AC2). Resolve head SHA + fork status
# via gh; absorb a gh failure (release lock, exit 0). For same-repo PRs fetch first
# so the SHA is present locally.
mkdir -p "$LOG_DIR" 2>/dev/null || true

PR_META="$(gh pr view "$PR_URL" --json headRefOid,headRefName,isCrossRepository 2>/dev/null || true)"
if [ -z "$PR_META" ]; then
  log "gh pr view failed for $PR_URL — cannot resolve head SHA, skipping (no marker)"
  rm -rf "$LOCK_DIR" 2>/dev/null || true
  exit 0
fi
HEAD_SHA=""
HEAD_REF=""
IS_FORK=""
if command -v jq >/dev/null 2>&1; then
  HEAD_SHA="$(printf '%s' "$PR_META" | jq -r '.headRefOid // empty' 2>/dev/null || true)"
  HEAD_REF="$(printf '%s' "$PR_META" | jq -r '.headRefName // empty' 2>/dev/null || true)"
  IS_FORK="$(printf '%s' "$PR_META" | jq -r '.isCrossRepository // false' 2>/dev/null || true)"
fi
if [ -z "$HEAD_SHA" ]; then
  log "could not resolve head SHA from gh pr view — skipping (no marker)"
  rm -rf "$LOCK_DIR" 2>/dev/null || true
  exit 0
fi

# Make the PR head SHA present locally before the detached worktree checkout. Prefer
# the GitHub PR head ref `refs/pull/<n>/head` — it exists for BOTH same-repo AND fork
# PRs on the BASE repo's origin, so a fork's head (which is on NO origin branch, and
# which a bare-SHA fetch is usually server-refused for) is still retrievable. This is
# what makes the AC2a fork "review-only ESCALATED + posted comment" path REACHABLE:
# without a local head SHA, `git worktree add` fails and the runner never starts to
# post the escalation. Fall back to a SHA / all-branches fetch for non-GitHub remotes.
# All best-effort; a failure is non-fatal (the worktree-add below then fails safely —
# no marker). The PR number is parsed from the URL's /pull/<n> segment.
PR_NUMBER="$(printf '%s' "$PR_URL" | sed -n 's#.*/pull/\([0-9][0-9]*\).*#\1#p')"
if [ -n "$PR_NUMBER" ]; then
  git fetch origin "refs/pull/$PR_NUMBER/head" >/dev/null 2>&1 || true
fi
git fetch origin "$HEAD_SHA" >/dev/null 2>&1 || git fetch origin >/dev/null 2>&1 || true

# Defensive pre-add cleanup: a hard crash on a prior dispatch (SIGKILL/power-loss in
# the narrow window between this `git worktree add` and the marker write) can leave a
# stale dir at the deterministic $WT_PATH with NO marker — a later `git worktree add`
# would then fail on the existing path and wedge re-dispatch for this PR forever. We
# hold the per-PR lock here, so clearing ONLY this hash-keyed path is safe (no other
# dispatch for the same PR can own it). Prune drops any orphaned admin entry the
# removed dir left behind. (The post-success prune below cannot pre-clean this.)
git worktree remove --force "$WT_PATH" >/dev/null 2>&1 || true
rm -rf "$WT_PATH" 2>/dev/null || true
git worktree prune >/dev/null 2>&1 || true

if ! git worktree add --detach "$WT_PATH" "$HEAD_SHA" >/dev/null 2>&1; then
  log "git worktree add failed for $WT_PATH @ $HEAD_SHA — skipping (no marker)"
  rm -rf "$LOCK_DIR" 2>/dev/null || true
  exit 0
fi

# ---- ⑤ write the RUN_LOG header (non-empty, machine-greppable) --------------
# Written BEFORE the marker + launch so an in-flight drain is never an ambiguous
# 0-byte file. If the header write fails, treat it as a failure: tear down the
# worktree + lock and exit 0 with NO marker (truthful: no dispatch started).
# Resolve RUN_LOG to ABSOLUTE up-front (via the repo top-level) so BOTH this header
# write AND the wrapper's `>>` append below target the SAME file regardless of the
# dispatcher's cwd — a relative path would split/misplace the log if the dispatcher
# were ever invoked from a subdirectory (today both call sites run at repo root).
MAIN_GITDIR="${REPO_TOPLEVEL:-$PWD}"
case "$RUN_LOG" in
  /*) RUN_LOG_ABS="$RUN_LOG" ;;
  *)  RUN_LOG_ABS="$MAIN_GITDIR/$RUN_LOG" ;;
esac
if ! {
  printf 'DISPATCHED\tts=%s\turl=%s\tuntil_mergeable=%s\trunner=%s\n' "$TIMESTAMP" "$PR_URL" "$UNTIL_MERGEABLE" "$RUNNER"
  printf '# marker: %s\n' "$MARKER"
  printf '# worktree: %s (isolated sibling, detached HEAD @ %s)\n' "$WT_PATH" "$HEAD_SHA"
  printf '# detached `claude -p` buffers stdout until exit — an otherwise-empty body below this\n'
  printf '# header means the drain is IN FLIGHT, not failed. Liveness: pgrep -lf review-pr-runner\n'
  printf '# ---- runner output follows ----\n'
} > "$RUN_LOG_ABS" 2>/dev/null; then
  log "RUN_LOG header write failed ($RUN_LOG_ABS) — tearing down worktree+lock, skipping (no marker)"
  git worktree remove --force "$WT_PATH" >/dev/null 2>&1 || true
  rm -rf "$LOCK_DIR" 2>/dev/null || true
  exit 0
fi

# ---- ⑥ write the durable marker (AC4a-ii — ONLY after worktree+header) ------
# Lock = "someone is dispatching"; marker = "a dispatch genuinely started". The
# marker is written ONLY now (worktree + header both succeeded) but still BEFORE
# the launch, so a marker can never claim a dispatch that did not actually start.
printf '%s\t%s\n' "$TIMESTAMP" "$PR_URL" > "$MARKER" 2>/dev/null || true

# ---- Thread the until-mergeable + fork env-var signal into the wrapper -------
# Default ON: export AI_AGENT_MANAGER_UNTIL_MERGEABLE=1 unless opted out. The runner
# reads these and translates them into the corresponding inline /review-pr flags
# (§"Until-Mergeable Dispatch Signal"). Only export the two optional tuning vars
# when set; never export them in the opted-out (plain diff-only) case.
if [ "$UNTIL_MERGEABLE" -eq 1 ]; then
  export AI_AGENT_MANAGER_UNTIL_MERGEABLE=1
  [ -n "$CHECK_WAIT_TIMEOUT" ] && export AI_AGENT_MANAGER_CHECK_WAIT_TIMEOUT="$CHECK_WAIT_TIMEOUT"
  [ -n "$REVIEW_CHECK_PATTERN" ] && export AI_AGENT_MANAGER_REVIEW_CHECK_PATTERN="$REVIEW_CHECK_PATTERN"
  log "until-mergeable drain ENABLED (AI_AGENT_MANAGER_UNTIL_MERGEABLE=1)"
else
  log "until-mergeable drain opted out — runner runs plain diff-only /review-pr"
fi

# Fork/cross-repo signal (AC2a): the runner reads this to degrade to review-only
# (ESCALATED + posted comment) for a fork PR whose head is NOT on origin — a
# `git push origin HEAD:<ref>` would update the wrong ref or fail. Same-repo PRs
# push via explicit refspec; the runner reads the head ref for that refspec.
if [ "$IS_FORK" = "true" ]; then
  export AI_AGENT_MANAGER_PR_IS_FORK=1
  log "fork/cross-repo PR — runner degrades to review-only (no push to origin)"
else
  export AI_AGENT_MANAGER_PR_IS_FORK=0
fi
[ -n "$HEAD_REF" ] && export AI_AGENT_MANAGER_PR_HEAD_REF="$HEAD_REF"

# Bounded prune of provably-stale DISPATCHER-OWNED worktree paths only. `git
# worktree prune` removes administrative entries for worktree dirs that no longer
# exist on disk — it NEVER deletes a live worktree dir, so it cannot catch a
# concurrent drain's worktree. NO broad `*-review-*` glob removal.
git worktree prune >/dev/null 2>&1 || true

# ---- ⑦ launch the detached wrapper that OWNS `trap cleanup EXIT` (AC3) -------
# The wrapper backgrounds with nohup + full stdio redirection. It sets a trap that
# removes ONLY this hash-keyed worktree + lock dir on EXIT (normal, error, OR
# crash) — executable cleanup, not a prompt instruction. The trap uses `git -C`
# against the MAIN repo gitdir and cd's OUT of the worktree before removing it, so
# cleanup never runs from inside the directory being deleted. `-p` is REQUIRED; no
# permission-bypass flags by design.
# MAIN_GITDIR + RUN_LOG_ABS were already resolved at the header-write step above.
# The wrapper cd's INTO the worktree before launching, so RUN_LOG_ABS (and the lock
# dir under .supervisor/) must be ABSOLUTE — a relative path would resolve inside the
# worktree (where .supervisor/logs/ does not exist), the `>>` redirect would fail,
# and bash would abort the command before claude ever runs.
case "$LOCK_DIR" in
  /*) LOCK_DIR_ABS="$LOCK_DIR" ;;
  *)  LOCK_DIR_ABS="$MAIN_GITDIR/$LOCK_DIR" ;;
esac
# Build the wrapper body as a FULLY SINGLE-QUOTED string (no interpolation) and pass
# the runtime values as POSITIONAL ARGS to `bash -c`. This is metacharacter-safe: a
# `$`, backtick, double-quote, or backslash in any value (most plausibly a repo path)
# can never break the wrapper string or be re-evaluated by the inner shell. The prior
# interpolated `'\''"$VAR"'\''` form embedded values inside double quotes, so a single
# quote was safe but a `$`/backtick/`"` in a path silently corrupted the worktree path
# (failed cd -> leaked worktree) AFTER the marker was written — the exact silent-drop
# class this change exists to remove. The trap captures the args into named vars FIRST
# (a trap function sees its OWN empty positionals on EXIT, not the script's $1..$7).
WRAPPER='
_mg="$1"; _wt="$2"; _lock="$3"; _bin="$4"; _runner="$5"; _pr="$6"; _log="$7"
trap_cleanup() {
  cd "$_mg" 2>/dev/null || cd / 2>/dev/null || true
  git -C "$_mg" worktree remove --force "$_wt" >/dev/null 2>&1 || true
  rm -rf "$_wt" 2>/dev/null || true
  rm -rf "$_lock" 2>/dev/null || true
}
trap trap_cleanup EXIT
cd "$_wt" || exit 0
"$_bin" -p --agent "$_runner" "$_pr" >>"$_log" 2>&1 </dev/null
'
( nohup bash -c "$WRAPPER" _ "$MAIN_GITDIR" "$WT_PATH" "$LOCK_DIR_ABS" "$CLAUDE_BIN" "$RUNNER" "$PR_URL" "$RUN_LOG_ABS" >/dev/null 2>&1 & ) >/dev/null 2>&1 || true

log "dispatched review-pr-runner for $PR_URL (worktree: $WT_PATH, log: $RUN_LOG)"
exit 0
