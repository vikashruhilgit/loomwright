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
#   COST / RUNAWAY GUARD. A per-PR dispatch marker file under
#   .supervisor/review-dispatch/ (keyed by a hash of the PR URL) ensures a given
#   PR is dispatched AT MOST ONCE. If the marker already exists, log one line and
#   exit 0 — this prevents a re-dispatch loop (e.g. a Supervisor --continue that
#   re-runs the completion tail on the same PR). Combined with the fact that
#   /review-pr NEVER creates a PR, there is no review->review recursion.
#
#   FRESH DETACHED PROCESS. When enabled + not yet dispatched, launch a brand-new
#   detached HEADLESS `claude -p --agent ai-agent-manager-plugin:review-pr-runner <pr-url>`
#   OS process (nohup + background + full stdio redirection to a log under
#   .supervisor/logs/). A fresh OS process means the runner is the MAIN agent of
#   its own session and can therefore spawn its own child agents (code-reviewer /
#   fix worker) — see skills/review-heal/SKILL.md "Two entry senses of fresh" (a).
#   `-p` does NOT make the runner a subagent: it is still the top-level/main agent
#   of its headless session, so Task-spawning children works exactly as before.
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

if [ -e "$MARKER" ]; then
  log "PR already dispatched this run (marker exists: $MARKER) — skipping re-dispatch"
  exit 0
fi

# ---- Dry-run short-circuit (honored BEFORE requiring the claude binary) ------
# In dry-run the claude process is never launched, so its presence on PATH is
# irrelevant. Emit the would-be command + write the marker (so the marker-guard
# path is still exercised) WITHOUT requiring the binary. This keeps the self-test
# (test-dispatch-pr-review.sh) claude-independent on CI runners that have no
# `claude` on PATH — previously the claude check below short-circuited first,
# making the dry-run a no-op on CI.
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

# ---- Require the claude binary ----------------------------------------------
if ! command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
  log "'$CLAUDE_BIN' not on PATH — cannot launch review-pr-runner, skipping"
  exit 0
fi

# ---- Launch the fresh detached review-pr-runner process ---------------------
mkdir -p "$LOG_DIR" 2>/dev/null || true
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo unknown)"
RUN_LOG="$LOG_DIR/review-pr-dispatch-$TIMESTAMP-$PR_HASH.log"

# Write the marker BEFORE launching so a crash mid-launch still blocks re-dispatch
# (fail-closed against runaway). The marker records the PR URL + dispatch time.
printf '%s\t%s\n' "$TIMESTAMP" "$PR_URL" > "$MARKER" 2>/dev/null || true

# Thread the S2-pinned until-mergeable env-var signal into the detached process by
# EXPORTING the vars before the launch subshell (they are inherited by the child).
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

# Synchronous, non-empty RUN_LOG header — written BEFORE the detached launch so the
# log is never an ambiguous 0-byte file. The detached `claude -p` buffers its stdout
# until exit, so without this an in-flight drain looks identical to a failed no-op
# (the exact false-negative that made a prior run misreport "not dispatched"). This
# header self-documents the dispatch (machine-greppable `DISPATCHED` token + url +
# until_mergeable flag + marker) and states plainly that an empty body below means
# IN FLIGHT, not failed. `>` truncates a fresh, uniquely-named file; the launch
# appends with `>>`.
{
  printf 'DISPATCHED\tts=%s\turl=%s\tuntil_mergeable=%s\trunner=%s\n' "$TIMESTAMP" "$PR_URL" "$UNTIL_MERGEABLE" "$RUNNER"
  printf '# marker: %s\n' "$MARKER"
  printf '# detached `claude -p` buffers stdout until exit — an otherwise-empty body below this\n'
  printf '# header means the drain is IN FLIGHT, not failed. Liveness: pgrep -lf review-pr-runner\n'
  printf '# ---- runner output follows ----\n'
} > "$RUN_LOG" 2>/dev/null || true

# Fire-and-forget: fully detached so the Supervisor completion tail returns
# immediately. nohup + background subshell + all stdio redirected away from the
# caller's inherited pipes (a backgrounded child still holding the tail's stdout
# would keep the tail "running" until it exits). HEADLESS `claude -p` (print-mode):
# `--agent` selects the runner but does NOT imply headless — without `-p` this is an
# interactive session that, detached + no TTY, can hang on a permission prompt
# instead of exiting (see header "FRESH DETACHED PROCESS"). No permission-bypass
# flags by design — relies on the project's existing permission settings. The
# until-mergeable signal rides as exported env vars (NOT a /review-pr slash string,
# NOT a positional) — the --agent form has no flag surface, avoiding the 11.1.1 trap.
( nohup "$CLAUDE_BIN" -p --agent "$RUNNER" "$PR_URL" >>"$RUN_LOG" 2>&1 </dev/null & ) >/dev/null 2>&1 || true

log "dispatched review-pr-runner for $PR_URL (log: $RUN_LOG)"
exit 0
