#!/usr/bin/env bash
#
# run-probe.sh — the executable half of loomwright/docs/SPIKES/CROSS_PLUGIN_RESOLUTION.md
#
# Measures three cross-plugin resolution unknowns against a live Claude Code install by
# generating TWO throwaway plugins, registering them through a throwaway marketplace at
# --scope local, observing each unknown from a FRESH `claude -p` process, and tearing the
# whole thing down on every exit path.
#
#   Unknown A — does an agent's `skills:` frontmatter preload resolve ACROSS plugins?
#   Unknown B — what does ${CLAUDE_PLUGIN_ROOT} resolve to inside a SECOND plugin's hooks.json?
#   Unknown C — does Task(subagent_type: "<other-plugin>:<agent>") resolve from a loomwright surface?
#   Unknown D — does a SubagentStop MATCHER declared in plugin X fire for an agent OWNED by
#               plugin Y — and in which namespace is the matcher written (single- or
#               doubled-prefix)?
#
# Re-run (from the repo root):
#
#     bash loomwright/docs/SPIKES/cross-plugin-probe/run-probe.sh
#
# A run writes a FRESH set of transcripts under a run-scoped prefix (PROBE_DATE, which
# defaults to a to-the-second timestamp), and REFUSES to overwrite an existing transcript
# unless PROBE_OVERWRITE=1. The committed measurement is therefore safe from a bare re-run
# by construction, not by the operator remembering to set a variable. The prefix actually
# used is printed at the top of the run; diff the new files against the committed ones to
# see whether Claude Code's behaviour has changed since the recorded measurement.
#
# PROBE_ONLY selects which phases run (default: all). E.g. PROBE_ONLY="d control" runs
# preflight + install + the two later-added arms only, leaving the A/B/C transcripts of an
# earlier run untouched.
#
# ---------------------------------------------------------------------------------------
# DESIGN CONSTRAINTS (each exists because of a specific, recorded failure mode)
#
# 1. NO TRACKED FILE IS MUTATED. The nonce lives in a plugin this script authors, so
#    mutation-target == preload-source holds by construction. A nonce written into this
#    repo's own loomwright/skills/ could never reach the *installed* body (a separate
#    snapshot under ~/.claude/plugins/cache/), so that design's only reachable outcome is
#    a false DOES NOT RESOLVE.
# 2. --scope local ONLY. Never `user` (machine-global), never `project` (would write
#    .claude/settings.json into the repo and leak into a PR). `.claude/settings.local.json`
#    is backed up byte-for-byte and restored at teardown.
# 3. NO PERMISSION-BYPASS FLAGS. --dangerously-skip-permissions and
#    --permission-mode bypassPermissions are a standing project prohibition; unused here.
# 4. BOUNDED WAIT ON EVERY NESTED `claude` CALL — probes, installs, AND teardown. Stock
#    macOS has no `timeout(1)`, and a nested headless `claude` can hang on a permission
#    prompt with no TTY (this repo has a recorded wedge from exactly that shape). Every
#    nested call runs in the background and is collected through a FIFO using
#    `IFS= read -r -d '' -t N`. On deadline expiry the step is recorded as UNMEASURED,
#    naming the timeout as the blocker, and the run CONTINUES to teardown.
# 5. HEADLESS `claude` MUST USE -p. Plain `claude` and `claude --agent X` are
#    interactive-by-default and hang without a TTY.
# 6. TOOL ISOLATION AT BOTH LEVELS. The probe agents are declared with no filesystem-read
#    capability, and the observing parent session runs with $PARENT_TOOLS so the parent
#    cannot read the sentinel off disk and relay it either. Without this a false RESOLVES
#    is possible — the sentinel would prove only that *something* in the process tree could
#    read a file.
#
#    "No tools at all" is NOT an available isolation setting, and the residual tool was
#    chosen by measurement rather than taste. Two earlier, UNRECORDED runs of this probe
#    first surfaced the ladder:
#      run 1, every tool subtracted -> "would be spawned with zero tools — refusing"
#      run 2, only TaskOutput left  -> "not available to subagents [TaskOutput]"
#    NEITHER of those two runs has a committed transcript — they predate the harness being
#    committed, so they are recollection, not evidence. Both rungs are therefore preserved
#    as CONTROL ARMS that re-measure them on every run and leave a checkable record:
#    `probe-zero-tools-agent` (rung 1) and `probe-taskoutput-agent` (rung 2). Cite the
#    control-arm transcripts, never the two lost runs.
#    So the agent's resolved tool list must be non-empty AND must contain something that is
#    both subagent-eligible and present in the observing session. `WebSearch` is the weakest
#    tool meeting all three conditions, and it cannot read the local filesystem, so it opens
#    no channel to the sentinel.
# ---------------------------------------------------------------------------------------

set -uo pipefail
# Deliberately NOT `set -e`: a failed probe is a RESULT to record, not a reason to abort,
# and teardown must run on every path.

# ---------------------------------------------------------------------------------------
# Paths and identifiers
# ---------------------------------------------------------------------------------------

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../../.." && pwd)"
TRANSCRIPTS="$HERE/transcripts"
mkdir -p "$TRANSCRIPTS"

# Run-scoped transcript prefix. The default carries SECONDS, so two runs never collide and
# a bare re-run cannot land on the committed `2026-08-20-*` set. An explicit PROBE_DATE is
# how a run that is meant to BE the record names itself.
PROBE_DATE="${PROBE_DATE:-$(date +%Y-%m-%dT%H%M%S)}"
LOG_A="$TRANSCRIPTS/${PROBE_DATE}-unknown-a.log"
LOG_B="$TRANSCRIPTS/${PROBE_DATE}-unknown-b.log"
LOG_C="$TRANSCRIPTS/${PROBE_DATE}-unknown-c.log"
LOG_0="$TRANSCRIPTS/${PROBE_DATE}-phase0.log"
LOG_D="$TRANSCRIPTS/${PROBE_DATE}-unknown-d.log"
LOG_CTL="$TRANSCRIPTS/${PROBE_DATE}-control-taskoutput.log"
LOG_T="$TRANSCRIPTS/${PROBE_DATE}-teardown.log"

# Which phases to run. Default: everything.
PROBE_ONLY="${PROBE_ONLY:-all}"
wants() {
  case " $PROBE_ONLY " in
    *" all "*) return 0 ;;
    *" $1 "*)  return 0 ;;
    *)         return 1 ;;
  esac
}

# Deadlines (seconds). Override with PROBE_DEADLINE / PROBE_CLI_DEADLINE.
# 240 is the value the RECORDED run used; the default matches it so the committed
# re-run command is the command that produced the committed transcripts.
DEADLINE="${PROBE_DEADLINE:-240}"          # a nested `claude -p` model turn
CLI_DEADLINE="${PROBE_CLI_DEADLINE:-120}"  # a non-model `claude plugin ...` subcommand

# ---------------------------------------------------------------------------------------
# Clobber guard
#
# A transcript is EVIDENCE. Overwriting one silently destroys the record the findings doc
# cites, so a run refuses to start if any transcript it would write already exists. This
# runs BEFORE the teardown trap is installed on purpose: an abort here must not fire a
# teardown that would itself write (and thus clobber) the teardown log.
# ---------------------------------------------------------------------------------------
CLOBBER=""
for _lg in \
  "$(wants a && echo "$LOG_A")" \
  "$(wants a || echo "$LOG_0")" \
  "$(wants b && echo "$LOG_B")" \
  "$(wants c && echo "$LOG_C")" \
  "$(wants d && echo "$LOG_D")" \
  "$(wants control && echo "$LOG_CTL")" \
  "$LOG_T"; do
  [ -n "$_lg" ] && [ -e "$_lg" ] && CLOBBER="$CLOBBER
  $_lg"
done
if [ -n "$CLOBBER" ] && [ "${PROBE_OVERWRITE:-0}" != "1" ]; then
  cat >&2 <<EOF
run-probe.sh: refusing to start — these transcripts already exist and would be overwritten:$CLOBBER

Pick a fresh run label instead (the default already carries seconds):

    PROBE_DATE=\$(date +%Y-%m-%dT%H%M%S) bash "$0"

or, if you really do intend to replace the recorded evidence:

    PROBE_OVERWRITE=1 bash "$0"
EOF
  exit 2
fi

MARKET_NAME="xplugin-probe"
HOST_PLUGIN="probe-host"
CONSUMER_PLUGIN="probe-consumer"

# Run-scoped nonce. Regenerated every run, so a stale copy can never satisfy the assertion.
NONCE="XPLUGIN-NONCE-$(date +%s)-${RANDOM}${RANDOM}"

# The pre-existing marker phrase asserted by Unknown A's read-only corroboration arm.
# Chosen for DISTINCTIVENESS, not convenience. The generic checklist lines in
# quality-checklist ("Test coverage >= 80%", "No secrets/PII in code or logs") are
# boilerplate a tool-isolated agent could emit from prior knowledge with no preload at
# all — a false RESOLVES through a channel tool isolation does not close. This phrase is a
# Loomwright coinage, and Phase 0 verifies it is unique within the installed body.
MARKER='Token budget estimated (Context7 needed?)'

# Tool set handed to the OBSERVING parent session, and the single source of truth for both
# the executed command and the command echoed into the transcript — a hand-written echo
# that drifts from the real invocation is exactly the kind of misleading evidence this
# spike exists to avoid.
#
# `Task` is needed to spawn at all. `WebSearch` is the residual tool the probe agents keep,
# and it is chosen by MEASUREMENT, not taste:
#   - subtracting every tool  -> "would be spawned with zero tools - refusing" (run 1)
#   - leaving only TaskOutput -> "not available to subagents [TaskOutput]"     (run 2)
# WebSearch is recognized, is available to subagents, and cannot read the local filesystem,
# so it keeps preload as the only channel to the sentinel.
PARENT_TOOLS="Task,WebSearch"

SCRATCH="${TMPDIR:-/tmp}/loomwright-xplugin-probe-$$"
MARKET_DIR="$SCRATCH/marketplace"
OUT_DIR="$SCRATCH/out"

LOCAL_SETTINGS="$REPO_ROOT/.claude/settings.local.json"
SETTINGS_BACKUP="$SCRATCH/settings.local.json.probe-backup"
SETTINGS_EXISTED="unknown"

banner() { echo; echo "==================== $* ===================="; echo; }

# count_matches <file> <fixed-pattern>
#   `grep -c` prints 0 AND exits 1 on no-match, so the common `grep -c ... || echo 0`
#   idiom emits TWO lines ("0" then "0") and corrupts the evidence. This wrapper keeps
#   grep's single line and swallows only the status.
count_matches() {
  local f="$1" pat="$2"
  if [ -f "$f" ]; then
    grep -cF -- "$pat" "$f" 2>/dev/null || true
  else
    echo "(no such file: $f)"
  fi
}

# ---------------------------------------------------------------------------------------
# Bounded execution (there is no `timeout(1)` on stock macOS)
# ---------------------------------------------------------------------------------------

# run_bounded <label> <deadline_seconds> <cmd...>
#   Runs <cmd...> in the background with stdout+stderr captured to $SCRATCH/<label>.out
#   and collects its exit status through a FIFO with a hard deadline.
#   Returns the command's status, or 124 on deadline expiry.
#
#   The FIFO is opened READ-WRITE (`exec 9<>`) on purpose: a plain `read ... < fifo`
#   blocks in open(2) until a writer appears, which happens only when the command has
#   ALREADY finished — so `read -t` would never get to arm its timeout and the bound
#   would be silently vacuous.
#
#   Expiry is ALSO signalled OUT OF BAND, via TIMED_OUT / INFRA_FAILED, because the exit
#   status is the WRAPPED COMMAND's channel: a command that genuinely exits 124 would
#   otherwise be mislabelled UNMEASURED, and an mkfifo failure (125) would produce no
#   banner at all. emit_capture reads the flags, never the number.
TIMED_OUT=0
INFRA_FAILED=""
run_bounded() {
  local label="$1" deadline="$2"; shift 2
  TIMED_OUT=0
  INFRA_FAILED=""
  local out="$SCRATCH/$label.out" fifo="$SCRATCH/$label.fifo"
  rm -f "$fifo" "$out"
  if ! mkfifo "$fifo" 2>/dev/null; then
    INFRA_FAILED="mkfifo failed for $fifo — the bounded-wait channel could not be created"
    return 125
  fi
  ( "$@" >"$out" 2>&1; printf '%s\0' "$?" >"$fifo" ) &
  local bg=$!
  exec 9<>"$fifo"
  local rc=""
  if IFS= read -r -d '' -t "$deadline" rc <&9; then
    exec 9>&-; rm -f "$fifo"
    return "$rc"
  fi
  exec 9>&-; rm -f "$fifo"
  # Kill the CHILDREN first: the subshell `exec`s into `claude`, so claude is its direct
  # child. Killing the subshell first would reparent claude to init and put it out of
  # reach of `pkill -P`.
  pkill -P "$bg" 2>/dev/null
  kill -TERM "$bg" 2>/dev/null
  TIMED_OUT=1
  return 124
}

# emit_capture <label> <status> [deadline]
#   Reads the OUT-OF-BAND flags set by the immediately preceding run_bounded call, never
#   the exit number: 124 and 125 are values a wrapped command may legitimately return.
emit_capture() {
  local label="$1" st="$2" dl="${3:-$DEADLINE}"
  echo "--- exit status: $st ---"
  if [ "$TIMED_OUT" = "1" ]; then
    echo "--- UNMEASURED: this step exceeded its ${dl}s bounded-wait deadline and was terminated."
    echo "--- blocker: bounded-wait deadline expiry (see run_bounded; macOS has no timeout(1))."
    echo "--- The run continues to teardown rather than stalling; the verdict for anything"
    echo "--- depending on this step is UNMEASURED, never an inferred yes/no."
  elif [ -n "$INFRA_FAILED" ]; then
    echo "--- UNMEASURED: the bounded-wait harness itself failed before the command ran."
    echo "--- blocker: $INFRA_FAILED"
    echo "--- Nothing was measured by this step; treat it as UNMEASURED, never as a result."
  fi
  echo "--- captured stdout+stderr (verbatim) ---"
  cat "$SCRATCH/$label.out" 2>/dev/null || echo "(no capture file)"
  echo "--- end capture ---"
}

# step <label> <deadline> <cmd...> — echo the command, run it bounded, print the capture.
step() {
  local label="$1" dl="$2"; shift 2
  echo "\$ $*"
  run_bounded "$label" "$dl" "$@"
  local st=$?
  emit_capture "$label" "$st" "$dl"
  return $st
}

# claude_bounded <label> <promptfile> [claude args...]
#   The prompt is fed on STDIN, never as a positional argument: `--tools` is variadic and
#   swallows a trailing positional prompt, which fails with
#   "Input must be provided either through stdin or as a prompt argument when using --print".
claude_bounded() {
  local label="$1" pf="$2"; shift 2
  run_bounded "$label" "$DEADLINE" bash -c 'exec claude -p "$@" < "$0"' "$pf" "$@"
}

# ---------------------------------------------------------------------------------------
# Teardown — trap-based, so it runs on success, failure, and interrupt alike
# ---------------------------------------------------------------------------------------

TEARDOWN_DONE=0
TEARDOWN_INCONCLUSIVE=0
teardown() {
  [ "$TEARDOWN_DONE" = "1" ] && return 0
  TEARDOWN_DONE=1
  {
    banner "TEARDOWN  ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
    echo "Runs from an EXIT/INT/TERM trap, so a crash or a Ctrl-C tears down too."
    echo "Every command below is bounded (${CLI_DEADLINE}s) — a teardown that hangs is a"
    echo "teardown that does not happen."
    echo

    step td-uninstall-consumer "$CLI_DEADLINE" \
      claude plugin uninstall "$CONSUMER_PLUGIN" --scope local -y
    step td-uninstall-host "$CLI_DEADLINE" \
      claude plugin uninstall "$HOST_PLUGIN" --scope local -y
    # No --scope: removes the declaration from EVERY scope. Safe, because this marketplace
    # name is created by this script and exists nowhere else.
    step td-market-remove "$CLI_DEADLINE" \
      claude plugin marketplace remove "$MARKET_NAME"

    banner "TEARDOWN ASSERTIONS (raw output)"
    #
    # EVERY assertion below is an ABSENCE test, and an absence test over a file that was
    # never written, or over the empty output of a command that timed out, is VACUOUSLY
    # true — it would print PASS for a teardown that fired before anything was installed.
    # That is the repo's own "vacuous guard" class, and it inverts the fail-CLOSED rule for
    # correctness gates. So each assertion is gated on POSITIVE EVIDENCE that the listing
    # actually happened: the command exited 0, the capture file exists, and it carries the
    # command's own header sentinel. Anything short of that prints INCONCLUSIVE — never
    # PASS — and the scratch directory is preserved for the operator.
    #
    local list_rc market_rc
    step td-plugin-list "$CLI_DEADLINE" claude plugin list
    list_rc=$?
    cp "$SCRATCH/td-plugin-list.out" "$SCRATCH/final-plugin-list.txt" 2>/dev/null
    step td-market-list "$CLI_DEADLINE" claude plugin marketplace list
    market_rc=$?
    cp "$SCRATCH/td-market-list.out" "$SCRATCH/final-marketplace-list.txt" 2>/dev/null

    # listing_usable <rc> <file> <sentinel>
    #   0 only when the command succeeded AND produced a file carrying its own header line.
    listing_usable() {
      [ "$1" = "0" ] || return 1
      [ -s "$2" ] || return 1
      grep -qF -- "$3" "$2" 2>/dev/null || return 1
      return 0
    }
    local PLUGIN_SENTINEL="Installed plugins:"
    local MARKET_SENTINEL="Configured marketplaces:"

    local plugin_list_ok=0 market_list_ok=0 baseline_ok=0
    listing_usable "$list_rc"   "$SCRATCH/final-plugin-list.txt"      "$PLUGIN_SENTINEL" && plugin_list_ok=1
    listing_usable "$market_rc" "$SCRATCH/final-marketplace-list.txt" "$MARKET_SENTINEL" && market_list_ok=1
    # The baseline was captured in preflight; it is only comparable if it, too, is a real listing.
    listing_usable 0 "$SCRATCH/baseline-plugin-list.txt" "$PLUGIN_SENTINEL" && baseline_ok=1

    echo
    echo "evidence gate: plugin-list rc=$list_rc usable=$plugin_list_ok | marketplace-list rc=$market_rc usable=$market_list_ok | baseline usable=$baseline_ok"
    echo "(an absence assertion over an unusable listing is vacuous, so it reports INCONCLUSIVE)"
    echo

    # assert_absent <label> <needle> <file> <usable-flag>
    assert_absent() {
      local label="$1" needle="$2" file="$3" ok="$4"
      if [ "$ok" != "1" ]; then
        echo "ASSERT $label ... INCONCLUSIVE (the listing this depends on is unusable — NOT a pass)"
        TEARDOWN_INCONCLUSIVE=1
        return 0
      fi
      if grep -qF -- "$needle" "$file" 2>/dev/null
        then echo "ASSERT $label ... FAIL (still present)"
        else echo "ASSERT $label ... PASS"; fi
    }
    assert_absent "probe-host absent from plugin list ......." "$HOST_PLUGIN" "$SCRATCH/final-plugin-list.txt" "$plugin_list_ok"
    assert_absent "probe-consumer absent from plugin list ..." "$CONSUMER_PLUGIN" "$SCRATCH/final-plugin-list.txt" "$plugin_list_ok"
    assert_absent "$MARKET_NAME absent from marketplace list" "$MARKET_NAME" "$SCRATCH/final-marketplace-list.txt" "$market_list_ok"

    # The run must not leave behind a loomwright registration it did not inherit.
    # Both sides must be REAL listings: with both files missing, count_matches returns the
    # identical "(no such file: ...)" string for each and the equality test would pass with
    # nothing measured at all.
    local before after
    if [ "$plugin_list_ok" = "1" ] && [ "$baseline_ok" = "1" ]; then
      before="$(count_matches "$SCRATCH/baseline-plugin-list.txt" loomwright)"
      after="$(count_matches "$SCRATCH/final-plugin-list.txt" loomwright)"
      if [ "$before" = "$after" ]
        then echo "ASSERT loomwright registrations unchanged ......... baseline=$before final=$after PASS"
        else echo "ASSERT loomwright registrations unchanged ......... baseline=$before final=$after FAIL"; fi
      echo "  baseline loomwright lines:"; grep 'loomwright' "$SCRATCH/baseline-plugin-list.txt" 2>/dev/null | sed 's/^/    /'
      echo "  final    loomwright lines:"; grep 'loomwright' "$SCRATCH/final-plugin-list.txt" 2>/dev/null | sed 's/^/    /'
    else
      echo "ASSERT loomwright registrations unchanged ......... INCONCLUSIVE (baseline usable=$baseline_ok, final usable=$plugin_list_ok — NOT a pass)"
      TEARDOWN_INCONCLUSIVE=1
    fi

    banner "LOCAL SETTINGS RESTORE"
    echo "target: $LOCAL_SETTINGS"
    echo "(gitignored via .gitignore '.claude/*' — verified before the run; this is why"
    echo " --scope local cannot leak into a PR, and why --scope project was forbidden)"
    echo "state before the run: $SETTINGS_EXISTED"
    local restore_ok=1
    if [ "$SETTINGS_EXISTED" = "present" ]; then
      if cp "$SETTINGS_BACKUP" "$LOCAL_SETTINGS" 2>/dev/null && cmp -s "$SETTINGS_BACKUP" "$LOCAL_SETTINGS"; then
        echo "restored byte-for-byte from backup"
        echo "ASSERT settings.local.json identical to pre-run backup ... PASS"
      else
        restore_ok=0
        echo "ASSERT settings.local.json identical to pre-run backup ... FAIL"
        echo "backup preserved at $SETTINGS_BACKUP (scratch is NOT removed below)"
      fi
    elif [ "$SETTINGS_EXISTED" = "absent" ]; then
      rm -f "$LOCAL_SETTINGS"
      if [ -e "$LOCAL_SETTINGS" ]
        then restore_ok=0; echo "ASSERT settings.local.json absent again ... FAIL"
        else echo "deleted (the file did not exist before the run)"; echo "ASSERT settings.local.json absent again ... PASS"; fi
    else
      echo "state was never captured (teardown fired before preflight) — left untouched"
    fi

    banner "UNKNOWN B EVIDENCE — WHOLE-RUN VIEW"
    # Read here, not mid-run: phase B's own `cat` sees only the sessions that had started by
    # then, so a claim like "the hook fired on every session" cannot be made from it. This
    # dump is the last thing before scratch removal, so it covers the ENTIRE run.
    echo "file: $OUT_DIR/unknown-b-plugin-root.txt"
    if [ -f "$OUT_DIR/unknown-b-plugin-root.txt" ]; then
      echo "\$ grep -c HOOK_FIRED_AT \$BFILE     # one record per session in which the hook fired"
      count_matches "$OUT_DIR/unknown-b-plugin-root.txt" "HOOK_FIRED_AT"
      echo "--- full file (verbatim) ---"
      cat "$OUT_DIR/unknown-b-plugin-root.txt" 2>&1
      echo "--- end file ---"
    else
      echo "(absent — either phase B did not run in this invocation, or the hook never fired)"
    fi

    banner "REPO CLEANLINESS"
    # Bounded like every other command here: `git status` can block on an index lock held by
    # a concurrent process, and a teardown that hangs is a teardown that does not happen.
    step td-git-status "$CLI_DEADLINE" \
      git -C "$REPO_ROOT" status --porcelain -- .claude .claude-plugin loomwright/skills loomwright/agents loomwright/commands loomwright/hooks
    echo "(empty capture above == no probe write leaked into a tracked plugin surface)"

    banner "SCRATCH REMOVAL"
    echo "scratch: $SCRATCH"
    if [ "$restore_ok" = "0" ]; then
      echo "PRESERVED — a restore assertion failed and the backup must survive for the operator."
    elif [ "$TEARDOWN_INCONCLUSIVE" = "1" ]; then
      echo "PRESERVED — at least one teardown assertion was INCONCLUSIVE, so the operator must"
      echo "be able to inspect the run's own listings and confirm the state by hand."
    else
      rm -rf "$SCRATCH" && echo "removed" || echo "removal FAILED"
    fi
    echo
    echo "teardown complete: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } 2>&1 | tee "$LOG_T"
}
# INT/TERM must TERMINATE, not fall through. A handler that returns 0 lets bash RESUME the
# script after the signal: teardown would uninstall everything and write the teardown log,
# then the remaining phases would run against a torn-down environment and overwrite their
# transcripts with junk — while TEARDOWN_DONE=1 suppressed the second, real teardown. The
# committed teardown log would then describe a state that was not the run's final state.
trap teardown EXIT
trap 'teardown; exit 130' INT
trap 'teardown; exit 143' TERM

# ---------------------------------------------------------------------------------------
# Phase 0 — preflight + fixtures + install. Logged into the Unknown A transcript when
# Unknown A runs, and into its own phase0 transcript when it does not.
# ---------------------------------------------------------------------------------------

phase0() {
  banner "PHASE 0 — PREFLIGHT  ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
  echo "repo root      : $REPO_ROOT"
  echo "scratch        : $SCRATCH"
  echo "probe deadline : ${DEADLINE}s per nested \`claude -p\`"
  echo "cli deadline   : ${CLI_DEADLINE}s per \`claude plugin ...\` subcommand"
  echo "nonce          : $NONCE"
  echo
  step pf-version "$CLI_DEADLINE" claude --version
  step pf-plugin-list "$CLI_DEADLINE" claude plugin list
  cp "$SCRATCH/pf-plugin-list.out" "$SCRATCH/baseline-plugin-list.txt" 2>/dev/null
  step pf-market-list "$CLI_DEADLINE" claude plugin marketplace list
  cp "$SCRATCH/pf-market-list.out" "$SCRATCH/baseline-marketplace-list.txt" 2>/dev/null

  banner "PHASE 0 — RESOLVE THE INSTALLED loomwright BODY (for Unknown A arm 2)"
  echo "Authority is the plugin manager's own installed_plugins.json record, cross-checked"
  echo "against \`claude plugin details\`. This is NOT an \`ls ~/.claude/plugins/cache/\`"
  echo "guess — that directory holds stale leftovers and is a recorded trap in this project."
  echo
  step pf-details "$CLI_DEADLINE" claude plugin details loomwright
  LOOMWRIGHT_INSTALL_PATH="$(python3 - <<'PY' 2>/dev/null
import json, os
p = os.path.expanduser("~/.claude/plugins/installed_plugins.json")
try:
    d = json.load(open(p))
except Exception:
    print(""); raise SystemExit
for key, entries in d.get("plugins", {}).items():
    if key.split("@")[0] == "loomwright":
        for e in entries:
            print(e.get("installPath", "")); raise SystemExit
print("")
PY
)"
  echo "LOOMWRIGHT_INSTALL_PATH=[$LOOMWRIGHT_INSTALL_PATH]"
  INSTALLED_SKILL="$LOOMWRIGHT_INSTALL_PATH/skills/quality-checklist/SKILL.md"
  echo "INSTALLED_SKILL=[$INSTALLED_SKILL]"
  echo "\$ ls -la \$INSTALLED_SKILL"
  ls -la "$INSTALLED_SKILL" 2>&1
  echo
  echo "marker asserted by arm 2: [$MARKER]"
  echo "\$ grep -cF \"\$MARKER\" \$INSTALLED_SKILL     # presence IN THE INSTALLED BODY, not the repo copy"
  count_matches "$INSTALLED_SKILL" "$MARKER"
  echo "\$ grep -rlF \"\$MARKER\" \$LOOMWRIGHT_INSTALL_PATH   # distinctiveness: which installed files carry it"
  grep -rlF -- "$MARKER" "$LOOMWRIGHT_INSTALL_PATH" 2>/dev/null
  echo "(exactly one file above == the phrase is unique in the installed body, so a hit in"
  echo " the agent's output cannot have come from some other preloaded skill)"

  banner "PHASE 0 — GENERATE THE THROWAWAY FIXTURES"
  mkdir -p "$MARKET_DIR/.claude-plugin" "$OUT_DIR"
  mkdir -p "$MARKET_DIR/$HOST_PLUGIN/.claude-plugin" "$MARKET_DIR/$HOST_PLUGIN/skills/probe-host-skill" "$MARKET_DIR/$HOST_PLUGIN/agents"
  mkdir -p "$MARKET_DIR/$CONSUMER_PLUGIN/.claude-plugin" "$MARKET_DIR/$CONSUMER_PLUGIN/agents" "$MARKET_DIR/$CONSUMER_PLUGIN/hooks"

  cat > "$MARKET_DIR/.claude-plugin/marketplace.json" <<JSON
{
  "name": "$MARKET_NAME",
  "owner": { "name": "cross-plugin resolution probe (throwaway)" },
  "plugins": [
    { "name": "$HOST_PLUGIN", "source": "./$HOST_PLUGIN", "description": "Throwaway probe plugin that OWNS the sentinel skill.", "version": "0.0.1" },
    { "name": "$CONSUMER_PLUGIN", "source": "./$CONSUMER_PLUGIN", "description": "Throwaway probe plugin whose agents preload skills owned by OTHER plugins.", "version": "0.0.1" }
  ]
}
JSON

  cat > "$MARKET_DIR/$HOST_PLUGIN/.claude-plugin/plugin.json" <<JSON
{
  "name": "$HOST_PLUGIN",
  "version": "0.0.1",
  "description": "Throwaway cross-plugin resolution probe — owns the sentinel skill.",
  "author": { "name": "cross-plugin resolution probe" },
  "license": "MIT"
}
JSON

  cat > "$MARKET_DIR/$HOST_PLUGIN/skills/probe-host-skill/SKILL.md" <<SKILL
---
name: probe-host-skill
description: Throwaway cross-plugin preload probe skill owned by probe-host. Carries a run-scoped sentinel.
version: "0.0.1"
---

# Probe host skill

The cross-plugin preload sentinel for this run is:

$NONCE

If you can see the sentinel above, this skill body was preloaded into your context.
SKILL

  # Unknown D needs an agent OWNED BY probe-host, so that a matcher declared in
  # probe-consumer's hooks.json is matching an agent from a DIFFERENT plugin.
  cat > "$MARKET_DIR/$HOST_PLUGIN/agents/probe-host-agent.md" <<'AGENT'
---
name: probe-host:probe-host-agent
description: Throwaway probe agent OWNED BY probe-host. Exists so a matcher declared in the OTHER plugin has a cross-plugin agent to match.
tools: Read, Write, Edit, Glob, Grep, Bash, Task, TaskOutput, LSP, WebSearch, WebFetch
disallowedTools: Read, Write, Edit, NotebookEdit, Glob, Grep, Bash, Task, TaskOutput, LSP, WebFetch
model: inherit
maxTurns: 3
---

# Probe host agent (Unknown D subject)

Output exactly one line and nothing else:

    HOSTAGENT: ok
AGENT

  cat > "$MARKET_DIR/$CONSUMER_PLUGIN/.claude-plugin/plugin.json" <<JSON
{
  "name": "$CONSUMER_PLUGIN",
  "version": "0.0.1",
  "description": "Throwaway cross-plugin resolution probe — agents preload OTHER plugins' skills; hooks print CLAUDE_PLUGIN_ROOT.",
  "author": { "name": "cross-plugin resolution probe" },
  "license": "MIT"
}
JSON

  # Tool isolation, following this repo's own `tools:` + `disallowedTools:` idiom
  # (loomwright/agents/plan-reviewer.md declares the full list, then subtracts down).
  # Here the subtraction removes every filesystem-read capability — no Read/Glob/Grep, and
  # no Bash/Task/WebFetch/TaskOutput either — leaving ONLY `WebSearch`, which reaches the
  # network and never the local filesystem. Preload is therefore the only channel by which
  # the sentinel can reach this agent's output.
  #
  # Why not subtract WebSearch too? Because a total subtraction is REFUSED at spawn — see
  # probe-zero-tools-agent below, which preserves that refusal as a control arm.
  cat > "$MARKET_DIR/$CONSUMER_PLUGIN/agents/probe-agent.md" <<'AGENT'
---
name: probe-consumer:probe-agent
description: Throwaway probe agent. Preloads a skill owned by a DIFFERENT plugin (probe-host) and echoes its sentinel.
tools: Read, Write, Edit, Glob, Grep, Bash, Task, TaskOutput, LSP, WebSearch, WebFetch
disallowedTools: Read, Write, Edit, NotebookEdit, Glob, Grep, Bash, Task, TaskOutput, LSP, WebFetch
model: inherit
maxTurns: 3
skills:
  - probe-host-skill
---

# Probe agent (cross-plugin preload sentinel)

You have NO tools. Answer from your context only.

Your preloaded skills — if cross-plugin preload resolves — contain a token beginning
`XPLUGIN-NONCE-`. Output that full token on one line prefixed with `SENTINEL: `.

If no such token is present in your context, output exactly:

    SENTINEL: ABSENT

Never invent, guess, reconstruct, or partially complete a token. Output the one line and
nothing else.
AGENT

  cat > "$MARKET_DIR/$CONSUMER_PLUGIN/agents/probe-checklist-agent.md" <<'AGENT'
---
name: probe-consumer:probe-checklist-agent
description: Throwaway probe agent. Preloads the REAL loomwright-owned `quality-checklist` skill (read-only corroboration arm).
tools: Read, Write, Edit, Glob, Grep, Bash, Task, TaskOutput, LSP, WebSearch, WebFetch
disallowedTools: Read, Write, Edit, NotebookEdit, Glob, Grep, Bash, Task, TaskOutput, LSP, WebFetch
model: inherit
maxTurns: 3
skills:
  - quality-checklist
---

# Probe agent (read-only corroboration arm)

You have NO tools. Answer from your context only.

If a skill named `quality-checklist` is present in your context, reproduce its
"Before Starting Any Task" checklist items VERBATIM, one per line, each prefixed with
`ITEM: `. Copy the text exactly as it appears — do not paraphrase, normalise or improve it.

If no skill named `quality-checklist` is present in your context, output exactly:

    CHECKLIST: ABSENT

Never reconstruct the checklist from memory or from general knowledge of what quality
checklists usually contain. If it is not in your context, say ABSENT.
AGENT

  # CONTROL ARM. Identical to probe-agent except that the subtraction is TOTAL. This
  # documents a spawn-time gate discovered by the first run of this probe: an agent whose
  # resolved tool list is empty is REFUSED before it ever runs. Kept as a fixture because
  # it is a real constraint on any companion plugin that tries to harden an agent by
  # subtracting tools — the refusal is silent in neither direction, it simply fails the
  # spawn, and a brief that assumed "no tools" was a valid hardening would be wrong.
  cat > "$MARKET_DIR/$CONSUMER_PLUGIN/agents/probe-zero-tools-agent.md" <<'AGENT'
---
name: probe-consumer:probe-zero-tools-agent
description: Throwaway CONTROL agent. Subtracts every tool, to record what happens at spawn time.
tools: Read, Write, Edit, Glob, Grep, Bash, Task, TaskOutput, LSP, WebSearch, WebFetch
disallowedTools: Read, Write, Edit, NotebookEdit, Glob, Grep, Bash, Task, TaskOutput, LSP, WebSearch, WebFetch
model: inherit
maxTurns: 3
skills:
  - probe-host-skill
---

# Control agent (total tool subtraction)

Output `SENTINEL: ` followed by the `XPLUGIN-NONCE-` token from your preloaded skills, or
`SENTINEL: ABSENT` if there is none.
AGENT

  # SECOND CONTROL ARM (rung 2 of the tool ladder). Identical to probe-agent except that
  # the residual tool is `TaskOutput` instead of `WebSearch`. The earlier, unrecorded run
  # that first hit this rung left no transcript, so the ladder's middle row was quoted from
  # recollection; this fixture re-measures it every run and leaves a checkable record.
  cat > "$MARKET_DIR/$CONSUMER_PLUGIN/agents/probe-taskoutput-agent.md" <<'AGENT'
---
name: probe-consumer:probe-taskoutput-agent
description: Throwaway CONTROL agent. Residual tool is TaskOutput only, to record what happens at spawn time.
tools: Read, Write, Edit, Glob, Grep, Bash, Task, TaskOutput, LSP, WebSearch, WebFetch
disallowedTools: Read, Write, Edit, NotebookEdit, Glob, Grep, Bash, Task, LSP, WebSearch, WebFetch
model: inherit
maxTurns: 3
skills:
  - probe-host-skill
---

# Control agent (TaskOutput as the only residual tool)

Output `SENTINEL: ` followed by the `XPLUGIN-NONCE-` token from your preloaded skills, or
`SENTINEL: ABSENT` if there is none.
AGENT

  # Unknown B. The hook writes to an ABSOLUTE scratch path (baked in below), because a
  # relative path would land in whatever cwd the triggering session happened to have.
  #
  #   RAW=           the literal ${CLAUDE_PLUGIN_ROOT} expansion, bracketed so that an
  #                  empty value is VISIBLE rather than invisible
  #   BRACE_DEFAULT= the same name with a shell default. If Claude Code substitutes the
  #                  token textually rather than exporting an env var, this longer form
  #                  will NOT match its substitution pattern, and what we see is the
  #                  shell's own expansion — which distinguishes the two mechanisms
  #   ENV_PRESENT=   whether CLAUDE_PLUGIN_ROOT exists in the hook process's environment
  #                  at all — this is what separates "unset" from "set but empty"
  #
  # `|| true` is present ON PURPOSE: it is this plugin family's convention, and it is
  # exactly why a green run proves nothing. The FILE CONTENT is the evidence, never the
  # exit status.
  #
  # Unknown D. FOUR SubagentStop matchers plus one unmatched (wildcard) entry, all declared
  # in probe-consumer, each appending a DISTINCT label. Between them they separate three
  # questions that a single matcher would conflate:
  #
  #   wildcard-any        -> does SubagentStop fire at all in this headless session?
  #                          (if this is absent, no other row means anything)
  #   same-plugin-*       -> the control: a matcher for an agent the DECLARING plugin owns
  #   cross-plugin-*      -> the actual unknown: a matcher for an agent ANOTHER plugin owns
  #   *-single vs *-doubled -> which NAMESPACE a matcher is written in. loomwright's own
  #                          hooks.json uses the SINGLE-prefix frontmatter name
  #                          ("loomwright:qa-executor"), which is NOT the doubled
  #                          Task(subagent_type:) string measured by Unknown C. Both forms
  #                          are declared here so the answer is measured, not assumed.
  #
  cat > "$MARKET_DIR/$CONSUMER_PLUGIN/hooks/hooks.json" <<'JSON'
{
  "description": "Throwaway cross-plugin resolution probe — records the expanded CLAUDE_PLUGIN_ROOT of a SECOND plugin, and which SubagentStop matcher forms fire.",
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "{ printf 'RAW=[%s]\\n' \"${CLAUDE_PLUGIN_ROOT}\"; printf 'BRACE_DEFAULT=[%s]\\n' \"${CLAUDE_PLUGIN_ROOT:-__UNSET_OR_EMPTY__}\"; printf 'ENV_PRESENT=[%s]\\n' \"$(env | grep -c '^CLAUDE_PLUGIN_ROOT=')\"; printf 'HOOK_CWD=[%s]\\n' \"$PWD\"; printf 'HOOK_FIRED_AT=[%s]\\n' \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"; } >> '@@OUT@@/unknown-b-plugin-root.txt' 2>&1 || true"
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "p=$(cat); printf 'MATCH=[wildcard-any] AT=[%s] PAYLOAD=[%s]\\n' \"$(date -u +%H:%M:%SZ)\" \"$(printf '%s' \"$p\" | tr -d '\\n' | cut -c1-400)\" >> '@@OUT@@/unknown-d-matcher.txt' 2>&1 || true"
          }
        ]
      },
      {
        "matcher": "probe-consumer:probe-agent",
        "hooks": [
          {
            "type": "command",
            "command": "p=$(cat); printf 'MATCH=[same-plugin-single] AT=[%s]\\n' \"$(date -u +%H:%M:%SZ)\" >> '@@OUT@@/unknown-d-matcher.txt' 2>&1 || true"
          }
        ]
      },
      {
        "matcher": "probe-consumer:probe-consumer:probe-agent",
        "hooks": [
          {
            "type": "command",
            "command": "p=$(cat); printf 'MATCH=[same-plugin-doubled] AT=[%s]\\n' \"$(date -u +%H:%M:%SZ)\" >> '@@OUT@@/unknown-d-matcher.txt' 2>&1 || true"
          }
        ]
      },
      {
        "matcher": "probe-host:probe-host-agent",
        "hooks": [
          {
            "type": "command",
            "command": "p=$(cat); printf 'MATCH=[cross-plugin-single] AT=[%s]\\n' \"$(date -u +%H:%M:%SZ)\" >> '@@OUT@@/unknown-d-matcher.txt' 2>&1 || true"
          }
        ]
      },
      {
        "matcher": "probe-host:probe-host:probe-host-agent",
        "hooks": [
          {
            "type": "command",
            "command": "p=$(cat); printf 'MATCH=[cross-plugin-doubled] AT=[%s]\\n' \"$(date -u +%H:%M:%SZ)\" >> '@@OUT@@/unknown-d-matcher.txt' 2>&1 || true"
          }
        ]
      }
    ]
  }
}
JSON
  # Bake the absolute output path in by substitution rather than with an unquoted heredoc,
  # so that ${CLAUDE_PLUGIN_ROOT} above survives VERBATIM into the generated JSON instead
  # of being expanded by this script's own shell.
  sed -i.bak "s|@@OUT@@|$OUT_DIR|g" "$MARKET_DIR/$CONSUMER_PLUGIN/hooks/hooks.json"
  rm -f "$MARKET_DIR/$CONSUMER_PLUGIN/hooks/hooks.json.bak"

  echo "\$ find \$MARKET_DIR -type f"
  find "$MARKET_DIR" -type f | sed "s|$SCRATCH/||" | sort
  echo
  echo "\$ cat probe-consumer/agents/probe-agent.md      # the tool-isolation frontmatter"
  cat "$MARKET_DIR/$CONSUMER_PLUGIN/agents/probe-agent.md"
  echo
  echo "\$ cat probe-consumer/agents/probe-checklist-agent.md"
  cat "$MARKET_DIR/$CONSUMER_PLUGIN/agents/probe-checklist-agent.md"
  echo
  echo "\$ cat probe-consumer/agents/probe-zero-tools-agent.md   # the control arm"
  cat "$MARKET_DIR/$CONSUMER_PLUGIN/agents/probe-zero-tools-agent.md"
  echo
  echo "\$ cat probe-consumer/hooks/hooks.json          # the Unknown B hook, absolute path baked in"
  cat "$MARKET_DIR/$CONSUMER_PLUGIN/hooks/hooks.json"
  echo
  echo "\$ python3 -c 'json.load(...)'                  # the generated hooks.json is valid JSON"
  python3 -c "import json,sys; json.load(open(sys.argv[1])); print('hooks.json: valid JSON')" \
    "$MARKET_DIR/$CONSUMER_PLUGIN/hooks/hooks.json" 2>&1

  banner "PHASE 0 — VALIDATE + INSTALL (--scope local ONLY)"
  step pf-validate-host "$CLI_DEADLINE" claude plugin validate "$MARKET_DIR/$HOST_PLUGIN"
  step pf-validate-consumer "$CLI_DEADLINE" claude plugin validate "$MARKET_DIR/$CONSUMER_PLUGIN"
  echo "state of $LOCAL_SETTINGS before install: $SETTINGS_EXISTED"
  echo
  cd "$REPO_ROOT" || return 1
  step in-market-add "$CLI_DEADLINE" claude plugin marketplace add "$MARKET_DIR" --scope local
  step in-install-host "$CLI_DEADLINE" claude plugin install "$HOST_PLUGIN@$MARKET_NAME" --scope local
  step in-install-consumer "$CLI_DEADLINE" claude plugin install "$CONSUMER_PLUGIN@$MARKET_NAME" --scope local
  step in-plugin-list "$CLI_DEADLINE" claude plugin list
  step in-details-consumer "$CLI_DEADLINE" claude plugin details "$CONSUMER_PLUGIN"

}

# ---------------------------------------------------------------------------------------
# Unknown A — the three arms (logged into the same transcript as Phase 0)
# ---------------------------------------------------------------------------------------

phase_a() {
  # ---------------------------------------------------------------------------------
  banner "UNKNOWN A — ARM 1 (PRIMARY): run-scoped nonce in a generated fixture"
  # ---------------------------------------------------------------------------------
  echo "mutation-target == preload-source? YES, BY CONSTRUCTION. This script authored"
  echo "  $MARKET_DIR/$HOST_PLUGIN/skills/probe-host-skill/SKILL.md"
  echo "and that same file is what the marketplace install copied. No tracked file is"
  echo "involved anywhere, so the 'nonce written to a snapshot the session never loads'"
  echo "failure — which can only ever produce a FALSE 'DOES NOT RESOLVE' — is impossible here."
  echo
  echo "\$ grep -cF \"\$NONCE\" probe-host/skills/probe-host-skill/SKILL.md"
  count_matches "$MARKET_DIR/$HOST_PLUGIN/skills/probe-host-skill/SKILL.md" "$NONCE"

  cat > "$SCRATCH/prompt-a1.txt" <<PROMPT
Run id $NONCE-PARENT-A1.
Use the Task tool exactly once, with subagent_type "probe-consumer:probe-consumer:probe-agent",
and give it this prompt: "Output your sentinel line as instructed."
Then output ONLY these two lines and nothing else:
SPAWN: ok
RELAY: <the subagent's final message, verbatim>
If the Task call errors, instead output ONLY:
SPAWN: error
RELAY: <the verbatim error text>
Do not add commentary. Do not invent or complete any token yourself.
PROMPT

  echo
  echo "\$ claude -p --tools \"$PARENT_TOOLS\" < prompt-a1.txt   (bounded ${DEADLINE}s)"
  echo "  The parent session's tool set is restricted to [$PARENT_TOOLS] — no Read, Glob,"
  echo "  Grep or Bash — so the parent cannot read the sentinel off disk and relay it."
  echo "  Isolation therefore holds at BOTH levels: the subagent has no filesystem-read"
  echo "  tool, and neither does the process observing it."
  echo "--- prompt (verbatim) ---"; cat "$SCRATCH/prompt-a1.txt"; echo "--- end prompt ---"
  claude_bounded a1 "$SCRATCH/prompt-a1.txt" --tools "$PARENT_TOOLS"
  emit_capture a1 "$?"
  echo
  echo "\$ grep -cF \"\$NONCE\" <arm 1 captured output>    # <== THE assertion for Unknown A arm 1"
  count_matches "$SCRATCH/a1.out" "$NONCE"
  echo "(>=1 == the nonce reached the agent's output through preload; 0 == it did not)"

  # ---------------------------------------------------------------------------------
  banner "UNKNOWN A — ARM 2 (CORROBORATION, STRICTLY READ-ONLY): the real loomwright skill"
  # ---------------------------------------------------------------------------------
  echo "installed loomwright body (resolved in Phase 0): $LOOMWRIGHT_INSTALL_PATH"
  echo "marker asserted:                                 [$MARKER]"
  echo "This arm writes nothing. It only spawns an agent whose skills: names quality-checklist."
  echo
  echo "EVIDENTIAL WEIGHT: this arm CORROBORATES arm 1 and NEVER OVERRIDES it. Unlike the"
  echo "run-scoped nonce, a pre-existing phrase cannot fully exclude reproduction from the"
  echo "model's prior knowledge, so a hit here is strictly weaker evidence than a hit in"
  echo "arm 1. If the two arms disagree, that disagreement is the finding — arm 1 rules."

  cat > "$SCRATCH/prompt-a2.txt" <<PROMPT
Run id $NONCE-PARENT-A2.
Use the Task tool exactly once, with subagent_type "probe-consumer:probe-consumer:probe-checklist-agent",
and give it this prompt: "Reproduce your checklist as instructed."
Then output ONLY these two lines and nothing else:
SPAWN: ok
RELAY: <the subagent's final message, verbatim>
If the Task call errors, instead output ONLY:
SPAWN: error
RELAY: <the verbatim error text>
Do not add commentary. Do not write the checklist yourself.
PROMPT

  echo
  echo "\$ claude -p --tools \"$PARENT_TOOLS\" < prompt-a2.txt   (bounded ${DEADLINE}s)"
  echo "--- prompt (verbatim) ---"; cat "$SCRATCH/prompt-a2.txt"; echo "--- end prompt ---"
  claude_bounded a2 "$SCRATCH/prompt-a2.txt" --tools "$PARENT_TOOLS"
  emit_capture a2 "$?"
  echo
  echo "\$ grep -cF \"\$MARKER\" <arm 2 captured output>   # <== THE assertion for Unknown A arm 2"
  count_matches "$SCRATCH/a2.out" "$MARKER"

  # ---------------------------------------------------------------------------------
  banner "UNKNOWN A — CONTROL ARM: what a TOTAL tool subtraction does at spawn time"
  # ---------------------------------------------------------------------------------
  echo "probe-zero-tools-agent is identical to probe-agent except that disallowedTools"
  echo "subtracts EVERY tool, including the WebSearch that probe-agent keeps. This arm"
  echo "exists because the first run"
  echo "of this probe accidentally shipped that configuration and learned something the"
  echo "brief did not anticipate. It is kept as a designed control rather than discarded."
  echo
  echo "It also protects the two arms above from a specific misreading: if arm 1 had"
  echo "returned no sentinel, one might conclude 'cross-plugin preload does not resolve'."
  echo "This arm shows the OTHER thing that produces no sentinel — a refused spawn — so the"
  echo "two are distinguishable in the record instead of being conflated."

  cat > "$SCRATCH/prompt-a0.txt" <<PROMPT
Run id $NONCE-PARENT-A0.
Use the Task tool exactly once with subagent_type "probe-consumer:probe-consumer:probe-zero-tools-agent"
and the prompt "Output your sentinel line as instructed."
Then output ONLY these two lines and nothing else:
OUTCOME: <resolved|error>
DETAIL: <the subagent's final message verbatim if it resolved, otherwise the VERBATIM error text>
Do not paraphrase the error. Do not retry with a different subagent_type.
PROMPT
  echo
  echo "\$ claude -p --tools \"$PARENT_TOOLS\" < prompt-a0.txt   (bounded ${DEADLINE}s)"
  echo "--- prompt (verbatim) ---"; cat "$SCRATCH/prompt-a0.txt"; echo "--- end prompt ---"
  claude_bounded a0 "$SCRATCH/prompt-a0.txt" --tools "$PARENT_TOOLS"
  emit_capture a0 "$?"
}

# ---------------------------------------------------------------------------------------
# Unknown B
# ---------------------------------------------------------------------------------------

phase_b() {
  banner "UNKNOWN B — \${CLAUDE_PLUGIN_ROOT} INSIDE A SECOND PLUGIN'S hooks.json"
  BFILE="$OUT_DIR/unknown-b-plugin-root.txt"
  echo "hook source     : $MARKET_DIR/$CONSUMER_PLUGIN/hooks/hooks.json   (SessionStart)"
  echo "hook output file: $BFILE"
  echo
  echo "\$ cat probe-consumer/hooks/hooks.json"
  cat "$MARKET_DIR/$CONSUMER_PLUGIN/hooks/hooks.json" 2>&1
  echo
  echo "pre-trigger state:"
  echo "\$ ls -la \$BFILE"; ls -la "$BFILE" 2>&1
  echo
  echo "trigger: a fresh \`claude -p\` session — SessionStart fires on session creation."
  echo "\$ claude -p --tools \"\" < prompt-b.txt            (bounded ${DEADLINE}s)"
  printf '%s' "Run id $NONCE-PARENT-B. Reply with exactly: TRIGGERED" > "$SCRATCH/prompt-b.txt"
  claude_bounded b "$SCRATCH/prompt-b.txt" --tools ""
  emit_capture b "$?"
  echo
  echo "post-trigger state:"
  echo "\$ ls -la \$BFILE"; ls -la "$BFILE" 2>&1
  echo
  echo "\$ cat \$BFILE      # <== THE evidence for Unknown B. Exit status proves NOTHING here:"
  echo "                     #     the '|| true' convention makes an unset expansion exit 0."
  if [ -f "$BFILE" ]; then
    cat "$BFILE" 2>&1
    echo "--- end file ---"
    echo
    echo "HOW TO READ THE DISCRIMINATOR:"
    echo "  RAW=[<path>]                   -> it expanded; the path IS the answer (per-plugin or not)"
    echo "  RAW=[]  with ENV_PRESENT=[1]   -> the variable EXISTS but is EMPTY  (silent no-op under '|| true')"
    echo "  RAW=[]  with ENV_PRESENT=[0]   -> the variable is UNSET             (silent no-op under '|| true')"
    echo "  RAW=[\${CLAUDE_PLUGIN_ROOT}]    -> no substitution at all; the literal token reached the shell"
  else
    echo "FILE ABSENT."
    echo "This is a RECORDED RESULT, not an inconclusive skip: either the second plugin's"
    echo "hooks.json was never registered (so the hook did not fire at all), or it fired and"
    echo "wrote nothing. Either way the QA telemetry / token-ledger fan-out that Unknown B"
    echo "exists to protect would be silently lost."
    echo "\$ ls -la \$OUT_DIR"; ls -la "$OUT_DIR" 2>&1
  fi
}

# ---------------------------------------------------------------------------------------
# Unknown C
# ---------------------------------------------------------------------------------------

phase_c() {
  banner "UNKNOWN C — CROSS-PLUGIN Task(subagent_type:) FROM A LOOMWRIGHT SURFACE"
  echo "Both forms are attempted AGAINST THE PROBE PLUGIN. The loomwright precedent"
  echo "(loomwright:loomwright:<role> resolves, single-prefix errors — measured 2026-08-08)"
  echo "is advisory context ONLY and is never substituted for this measurement."
  echo
  echo "probe agent frontmatter name : probe-consumer:probe-agent"
  echo "  single-prefix form attempted : probe-consumer:probe-agent"
  echo "  doubled-prefix form attempted: probe-consumer:probe-consumer:probe-agent"
  echo
  echo "The observing session runs with cwd=$REPO_ROOT and the loomwright plugin enabled,"
  echo "so the spawn originates from a loomwright surface, as the unknown requires."

  local form label
  for form in "probe-consumer:probe-agent" "probe-consumer:probe-consumer:probe-agent"; do
    label="c-$(echo "$form" | tr ':' '_')"
    echo
    echo "-------- attempting subagent_type: \"$form\" --------"
    cat > "$SCRATCH/prompt-$label.txt" <<PROMPT
Run id $NONCE-PARENT-C.
Use the Task tool exactly once with subagent_type "$form" and the prompt
"Output your sentinel line as instructed."
Then output ONLY these three lines and nothing else:
SUBAGENT_TYPE: $form
OUTCOME: <resolved|error>
DETAIL: <the subagent's final message verbatim if it resolved, otherwise the VERBATIM error text you received>
Do not paraphrase the error. Do not retry with a different subagent_type.
PROMPT
    echo "--- prompt (verbatim) ---"; cat "$SCRATCH/prompt-$label.txt"; echo "--- end prompt ---"
    claude_bounded "$label" "$SCRATCH/prompt-$label.txt" --tools "$PARENT_TOOLS"
    emit_capture "$label" "$?"
    echo "\$ grep -cF \"\$NONCE\" <captured output>   # did the sentinel come back through this form?"
    count_matches "$SCRATCH/$label.out" "$NONCE"
  done
}

# ---------------------------------------------------------------------------------------
# Unknown D — does a SubagentStop MATCHER declared in one plugin fire for another plugin's
#             agent, and in WHICH namespace is the matcher written?
#
# This exists because the chosen Unknown B fallback (keep the shared-script fan-out hooks in
# loomwright, matched on the companion plugin's agent) rests on it, and Unknown C does NOT
# establish it: Unknown C measured the `Task(subagent_type:)` namespace, which is a
# different namespace from the one a hook matcher is written in. Loomwright's own
# hooks.json matchers are single-prefix frontmatter names.
# ---------------------------------------------------------------------------------------

phase_d() {
  banner "UNKNOWN D — CROSS-PLUGIN SubagentStop MATCHER RESOLUTION"
  DFILE="$OUT_DIR/unknown-d-matcher.txt"
  echo "matchers declared in : $MARKET_DIR/$CONSUMER_PLUGIN/hooks/hooks.json  (plugin: $CONSUMER_PLUGIN)"
  echo "matcher output file  : $DFILE"
  echo
  echo "The five declared SubagentStop entries, and what each one isolates:"
  echo "  (no matcher)                                -> wildcard-any        : does SubagentStop fire at all here?"
  echo "  probe-consumer:probe-agent                  -> same-plugin-single  : control, own plugin, single prefix"
  echo "  probe-consumer:probe-consumer:probe-agent   -> same-plugin-doubled : control, own plugin, doubled prefix"
  echo "  probe-host:probe-host-agent                 -> cross-plugin-single : THE unknown, single prefix"
  echo "  probe-host:probe-host:probe-host-agent      -> cross-plugin-doubled: THE unknown, doubled prefix"
  echo
  echo "\$ cat probe-consumer/hooks/hooks.json"
  cat "$MARKET_DIR/$CONSUMER_PLUGIN/hooks/hooks.json" 2>&1
  echo
  echo "pre-trigger state:"
  echo "\$ ls -la \$DFILE"; ls -la "$DFILE" 2>&1

  # Trigger 1 — spawn the agent OWNED BY probe-host (the cross-plugin case).
  cat > "$SCRATCH/prompt-d1.txt" <<PROMPT
Run id $NONCE-PARENT-D1.
Use the Task tool exactly once with subagent_type "probe-host:probe-host:probe-host-agent"
and the prompt "Output your line as instructed."
Then output ONLY these two lines and nothing else:
OUTCOME: <resolved|error>
DETAIL: <the subagent's final message verbatim if it resolved, otherwise the VERBATIM error text>
Do not paraphrase the error. Do not retry with a different subagent_type.
PROMPT
  echo
  echo "-------- trigger 1: spawn probe-host's agent (cross-plugin) --------"
  echo "\$ claude -p --tools \"$PARENT_TOOLS\" < prompt-d1.txt   (bounded ${DEADLINE}s)"
  echo "--- prompt (verbatim) ---"; cat "$SCRATCH/prompt-d1.txt"; echo "--- end prompt ---"
  claude_bounded d1 "$SCRATCH/prompt-d1.txt" --tools "$PARENT_TOOLS"
  emit_capture d1 "$?"

  # Trigger 2 — spawn probe-consumer's OWN agent (the same-plugin control). Without this,
  # an empty result for the cross-plugin rows would be unreadable: it could mean the
  # matcher namespace is wrong, or that SubagentStop matchers do not fire in this setup at
  # all. The control separates those.
  cat > "$SCRATCH/prompt-d2.txt" <<PROMPT
Run id $NONCE-PARENT-D2.
Use the Task tool exactly once with subagent_type "probe-consumer:probe-consumer:probe-agent"
and the prompt "Output your sentinel line as instructed."
Then output ONLY these two lines and nothing else:
OUTCOME: <resolved|error>
DETAIL: <the subagent's final message verbatim if it resolved, otherwise the VERBATIM error text>
Do not paraphrase the error. Do not retry with a different subagent_type.
PROMPT
  echo
  echo "-------- trigger 2: spawn probe-consumer's own agent (same-plugin control) --------"
  echo "\$ claude -p --tools \"$PARENT_TOOLS\" < prompt-d2.txt   (bounded ${DEADLINE}s)"
  echo "--- prompt (verbatim) ---"; cat "$SCRATCH/prompt-d2.txt"; echo "--- end prompt ---"
  claude_bounded d2 "$SCRATCH/prompt-d2.txt" --tools "$PARENT_TOOLS"
  emit_capture d2 "$?"

  echo
  echo "post-trigger state:"
  echo "\$ ls -la \$DFILE"; ls -la "$DFILE" 2>&1
  echo
  echo "\$ cat \$DFILE      # <== THE evidence for Unknown D. Exit status proves NOTHING here:"
  echo "                     #     '|| true' makes a hook that never fired indistinguishable"
  echo "                     #     from one that fired and succeeded, by status alone."
  if [ -f "$DFILE" ]; then
    cat "$DFILE" 2>&1
    echo "--- end file ---"
    echo
    echo "labels observed:"
    for lbl in wildcard-any same-plugin-single same-plugin-doubled cross-plugin-single cross-plugin-doubled; do
      printf '  %-22s %s\n' "$lbl" "$(count_matches "$DFILE" "MATCH=[$lbl]")"
    done
    echo
    echo "HOW TO READ IT:"
    echo "  wildcard-any absent            -> SubagentStop did not fire at all; EVERY other row"
    echo "                                    below is UNMEASURED, not a NO."
    echo "  cross-plugin-* present         -> a matcher declared in one plugin DOES fire for an"
    echo "                                    agent owned by another; the fallback (d) is viable."
    echo "  which of -single / -doubled    -> that is the namespace a matcher must be written in."
    echo "                                    It is NOT necessarily the Task(subagent_type:) form."
  else
    echo "FILE ABSENT — no SubagentStop hook declared by this plugin wrote anything for either"
    echo "spawn. Recorded as a RESULT for the wildcard row and therefore as UNMEASURED for the"
    echo "matcher-namespace question: with the wildcard silent too, nothing distinguishes 'the"
    echo "matcher did not match' from 'the event never reached this plugin's hooks'."
    echo "\$ ls -la \$OUT_DIR"; ls -la "$OUT_DIR" 2>&1
  fi
}

# ---------------------------------------------------------------------------------------
# Control arm — rung 2 of the tool ladder (TaskOutput as the only residual tool)
# ---------------------------------------------------------------------------------------

phase_control() {
  banner "CONTROL ARM — TaskOutput AS THE ONLY RESIDUAL TOOL"
  echo "Rung 2 of the tool ladder. The run that first hit this rung left no transcript, so"
  echo "the ladder's middle row was recollection. This arm re-measures it and commits the"
  echo "raw text, so the row can be cited from evidence instead of memory."
  echo
  echo "\$ cat probe-consumer/agents/probe-taskoutput-agent.md"
  cat "$MARKET_DIR/$CONSUMER_PLUGIN/agents/probe-taskoutput-agent.md" 2>&1
  cat > "$SCRATCH/prompt-ctl.txt" <<PROMPT
Run id $NONCE-PARENT-CTL.
Use the Task tool exactly once with subagent_type "probe-consumer:probe-consumer:probe-taskoutput-agent"
and the prompt "Output your sentinel line as instructed."
Then output ONLY these two lines and nothing else:
OUTCOME: <resolved|error>
DETAIL: <the subagent's final message verbatim if it resolved, otherwise the VERBATIM error text>
Do not paraphrase the error. Do not retry with a different subagent_type.
PROMPT
  # The OBSERVING session must itself hold TaskOutput here. The zero-tools refusal text
  # ("recognized but matched no tools in this session") shows the agent's resolved list is
  # intersected with the session's tool set — so observing this arm through the standard
  # $PARENT_TOOLS (Task,WebSearch) would empty the list and reproduce RUNG 1 instead of
  # rung 2, silently conflating the two. TaskOutput cannot read the local filesystem, so
  # adding it to the parent opens no channel to the sentinel.
  local ctl_tools="Task,TaskOutput"
  echo
  echo "\$ claude -p --tools \"$ctl_tools\" < prompt-ctl.txt   (bounded ${DEADLINE}s)"
  echo "  (parent tool set differs from the other arms ON PURPOSE — see the comment in source)"
  echo "--- prompt (verbatim) ---"; cat "$SCRATCH/prompt-ctl.txt"; echo "--- end prompt ---"
  claude_bounded ctl "$SCRATCH/prompt-ctl.txt" --tools "$ctl_tools"
  emit_capture ctl "$?"
}

# ---------------------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------------------

mkdir -p "$SCRATCH" "$OUT_DIR"

# Every nested `claude` call must run with cwd == the repo root: `--scope local` writes to
# (and is read back from) the local settings of the CURRENT project directory, so a probe
# observed from anywhere else would simply not see the plugins this run installed.
cd "$REPO_ROOT" || { echo "cannot cd to repo root $REPO_ROOT" >&2; exit 1; }

# Capture and back up the local settings file BEFORE anything touches plugin state.
if [ -f "$LOCAL_SETTINGS" ]; then
  SETTINGS_EXISTED="present"
  cp "$LOCAL_SETTINGS" "$SETTINGS_BACKUP"
else
  SETTINGS_EXISTED="absent"
fi

echo "transcript prefix: $PROBE_DATE   (phases: $PROBE_ONLY)"
echo "transcripts will be written under: $TRANSCRIPTS"

# Phase 0 always runs — nothing else can be observed without the install. It shares the
# Unknown A transcript when Unknown A runs, and gets its own file when it does not, so the
# preflight that a partial run depends on is never left unrecorded.
if wants a; then
  { phase0; phase_a; } 2>&1 | tee "$LOG_A"
else
  phase0 2>&1 | tee "$LOG_0"
fi
wants b       && phase_b       2>&1 | tee "$LOG_B"
wants c       && phase_c       2>&1 | tee "$LOG_C"
wants d       && phase_d       2>&1 | tee "$LOG_D"
wants control && phase_control 2>&1 | tee "$LOG_CTL"

# Teardown runs from the EXIT trap.
exit 0
