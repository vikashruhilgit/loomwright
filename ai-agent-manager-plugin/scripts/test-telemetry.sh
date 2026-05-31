#!/usr/bin/env bash
# test-telemetry.sh — Fixture-driven verification harness for send-telemetry-core.sh
#
# Subtask #4 of the GitHub Issues Telemetry System.
#
# WHAT THIS DOES
#   For each fixture in telemetry-fixtures/*.json, runs the core script with
#   --dry-run under three consent states (none / always_allow without repo /
#   always_allow with repo) and asserts the WOULD_EXIT line matches the
#   expected value documented in .supervisor/worker-summaries/subtask-2b.md.
#
#   It then layers on:
#     1. Determinism check  — one fixture, two runs, normalised diff = empty.
#     2. Privacy bait check — every fixture whose name starts with
#        'secrets-bait-' MUST yield WOULD_EXIT=2 in every consent state.
#     3. No-gh check         — --dry-run must never invoke `gh issue create`
#                              (asserted by absence of a 'gh issue create'
#                              line in the dry-run output).
#     4. Golden diff (optional) — if a golden file exists for a
#        fixture×state, normalise volatile fields and diff against it.
#
# REGENERATING GOLDENS
#   Run:  WRITE_GOLDENS=1 ./test-telemetry.sh
#   This (re)creates .golden.txt files from the current output rather than
#   diffing against them. Inspect the diffs in `git diff` before committing.
#
# ORDER-OF-OPERATIONS PIN (matches docs/TELEMETRY.md §Interest filter)
#   The canonical order is:
#     raw-privacy -> consent -> target-repo -> body-privacy -> interest -> dedup -> gh
#   This was REORDERED in heal iter 1 of v11.2.0 to close a loophole where a
#   healthy run (score>=5 + status=completed/PASS) whose payload contained a
#   secret would short-circuit on the interest filter (exit 5) without the
#   PRIVACY_BLOCKED audit-log entry firing first. Now privacy runs strictly
#   first in stage 1, then bash drives consent -> repo -> interest -> dedup.
#
#   Concretely:
#     supervisor-pass.json [none]            -> 3 (no_consent)        — was 5
#     supervisor-pass.json [allow_no_repo]   -> 4 (no_repo_configured) — was 5
#     supervisor-pass.json [allow_with_repo] -> 5 (filter_skipped)     — unchanged
#
#   The harness pins the new order via the order-of-operations test below
#   (asserts supervisor-pass.json [none] yields WOULD_EXIT=3, and that
#   secrets-bait fixtures still produce WOULD_EXIT=2 in every consent state
#   to prove privacy still runs first).
#
# EXIT
#   0 on full pass, 1 on any failure.

set -u
set -o pipefail

# ---- Locate repo root + scripts dir ------------------------------------------
SCRIPT_PATH="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CORE="$SCRIPT_DIR/send-telemetry-core.sh"
FIXTURES_DIR="$SCRIPT_DIR/telemetry-fixtures"
GOLDENS_DIR="$FIXTURES_DIR/golden"
CONSENT_FILE="$REPO_ROOT/.supervisor/telemetry-consent.json"
CONSENT_BACKUP=""
WRITE_GOLDENS="${WRITE_GOLDENS:-0}"

mkdir -p "$GOLDENS_DIR" 2>/dev/null || true

if [ ! -x "$CORE" ]; then
  echo "FATAL  core script not found or not executable: $CORE" >&2
  exit 1
fi

if [ ! -d "$FIXTURES_DIR" ]; then
  echo "FATAL  fixtures dir not found: $FIXTURES_DIR" >&2
  exit 1
fi

# ---- Backup + restore consent file via trap ---------------------------------
backup_consent() {
  if [ -f "$CONSENT_FILE" ]; then
    CONSENT_BACKUP="$(mktemp)"
    cp "$CONSENT_FILE" "$CONSENT_BACKUP"
  fi
}

restore_consent() {
  if [ -n "$CONSENT_BACKUP" ] && [ -f "$CONSENT_BACKUP" ]; then
    cp "$CONSENT_BACKUP" "$CONSENT_FILE"
    rm -f "$CONSENT_BACKUP"
  else
    # No pre-existing file — make sure we leave none behind.
    rm -f "$CONSENT_FILE"
  fi
}

trap 'restore_consent' EXIT INT TERM

backup_consent

# ---- Consent-state setters ---------------------------------------------------
set_state_none() {
  rm -f "$CONSENT_FILE"
}

set_state_allow_no_repo() {
  mkdir -p "$(dirname "$CONSENT_FILE")"
  printf '%s\n' '{"telemetry": "always_allow"}' > "$CONSENT_FILE"
}

set_state_allow_with_repo() {
  mkdir -p "$(dirname "$CONSENT_FILE")"
  printf '%s\n' '{"telemetry": "always_allow", "telemetry_repo": "example/repo"}' > "$CONSENT_FILE"
}

# ---- Counters ---------------------------------------------------------------
PASS_COUNT=0
FAIL_COUNT=0
declare -a FAIL_LINES=()

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "PASS  $label"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    local line="FAIL  $label  expected=$expected  actual=$actual"
    echo "$line"
    FAIL_LINES+=("$line")
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

assert_match() {
  # Pass when haystack contains needle.
  local label="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    echo "PASS  $label"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    local line="FAIL  $label  needle='$needle' not found"
    echo "$line"
    FAIL_LINES+=("$line")
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

assert_not_match() {
  local label="$1" needle="$2" haystack="$3"
  if ! printf '%s' "$haystack" | grep -qF -- "$needle"; then
    echo "PASS  $label"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    local line="FAIL  $label  unexpected '$needle' present"
    echo "$line"
    FAIL_LINES+=("$line")
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# ---- Helpers -----------------------------------------------------------------
extract_would_exit() {
  printf '%s' "$1" | grep -E '^WOULD_EXIT=' | tail -1 | cut -d= -f2 | tr -d '[:space:]'
}

# Strip volatile lines for golden diff. We keep BODY content stable because
# the core is intentionally deterministic — no timestamps inside dry-run.
# We strip only safety-net patterns in case the core ever grows volatile output.
normalise_for_golden() {
  # Remove lines that contain runtime-varying tokens. Currently a no-op for
  # the core's output, but kept defensively.
  sed -E \
    -e '/^Generated: /d' \
    -e '/^Hash: /d' \
    -e '/^Timestamp: /d'
}

run_core_dry_run() {
  # Stdin = fixture JSON; stdout+stderr captured.
  local fixture="$1"
  bash "$CORE" --dry-run < "$fixture" 2>&1
}

# Expected-WOULD_EXIT matrix (post heal-iter-1 reorder).
# Authoritative source: docs/TELEMETRY.md §Interest filter — order is
# raw-privacy -> consent -> repo -> body-privacy -> interest -> dedup -> gh.
#
# Fixture                              | none | allow_no_repo | allow_with_repo
# -------------------------------------+------+---------------+----------------
# supervisor-pass.json                 |  3   |       4       |       5         (consent first; filter only fires once repo is resolved)
# supervisor-pass-lastmsg.json         |  3   |       4       |       5         (v14.2.1: result carried in REAL `last_assistant_message` field, not `result_block`)
# supervisor-escalated.json            |  3   |       4       |       0
# supervisor-escalated-yaml.json       |  3   |       4       |       0         (heal-iter-2: real agent YAML mapping form, not bullet form)
# qa-failed.json                       |  3   |       4       |       0
# secrets-bait-ghp.json                |  2   |       2       |       2         (privacy fail-closed in stage1, before consent)
# secrets-bait-email.json              |  2   |       2       |       2         (privacy fail-closed in stage1, before consent)
# secrets-bait-lastmsg-ghp.json        |  2   |       2       |       2         (v14.2.1: secret in `last_assistant_message` still fails closed)
#
# v14.2.1 DISCRIMINATOR: the two *-lastmsg-* fixtures omit `result_block`
# entirely and carry the agent output in `last_assistant_message` (the field
# real Claude Code SubagentStop payloads actually populate). Under the pre-fix
# reader (which read only `.result_block`) `last_assistant_message` would be
# ignored → empty result text → schema `no_known_result_block` → WOULD_EXIT=5
# at EVERY consent state (and bait would short-circuit to 5 BEFORE the privacy
# scan, exposing the secret to a later POST). The expected values below
# (3/4/5 for pass, 2/2/2 for bait) therefore FAIL on the buggy reader and PASS
# only once `last_assistant_message` is honoured.
expected_would_exit() {
  local fixture_name="$1" state="$2"
  case "$fixture_name" in
    secrets-bait-*)
      printf '2\n'
      return
      ;;
  esac
  case "$fixture_name:$state" in
    supervisor-pass.json:none)             printf '3\n' ;;
    supervisor-pass.json:allow_no_repo)    printf '4\n' ;;
    supervisor-pass.json:allow_with_repo)  printf '5\n' ;;
    supervisor-pass-lastmsg.json:none)             printf '3\n' ;;
    supervisor-pass-lastmsg.json:allow_no_repo)    printf '4\n' ;;
    supervisor-pass-lastmsg.json:allow_with_repo)  printf '5\n' ;;
    supervisor-escalated.json:none)      printf '3\n' ;;
    supervisor-escalated.json:allow_no_repo) printf '4\n' ;;
    supervisor-escalated.json:allow_with_repo) printf '0\n' ;;
    supervisor-escalated-yaml.json:none)             printf '3\n' ;;
    supervisor-escalated-yaml.json:allow_no_repo)    printf '4\n' ;;
    supervisor-escalated-yaml.json:allow_with_repo)  printf '0\n' ;;
    code-review-fail.json:none)            printf '3\n' ;;
    code-review-fail.json:allow_no_repo)   printf '4\n' ;;
    code-review-fail.json:allow_with_repo) printf '0\n' ;;
    code-review-shuffled.json:none)            printf '3\n' ;;
    code-review-shuffled.json:allow_no_repo)   printf '4\n' ;;
    code-review-shuffled.json:allow_with_repo) printf '0\n' ;;
    qa-failed.json:none)                 printf '3\n' ;;
    qa-failed.json:allow_no_repo)        printf '4\n' ;;
    qa-failed.json:allow_with_repo)      printf '0\n' ;;
    *)
      # Unknown fixture — caller will note skip rather than assert.
      printf 'UNKNOWN\n'
      ;;
  esac
}

# ---- Discover fixtures -------------------------------------------------------
declare -a FIXTURES=()
shopt -s nullglob
for f in "$FIXTURES_DIR"/*.json; do
  FIXTURES+=("$f")
done
shopt -u nullglob

if [ "${#FIXTURES[@]}" -eq 0 ]; then
  echo "FATAL  no fixtures discovered in $FIXTURES_DIR" >&2
  exit 1
fi

echo "==== Fixture × consent-state matrix ===="
echo "Repo root: $REPO_ROOT"
echo "Core:      $CORE"
echo "Fixtures:  ${#FIXTURES[@]} discovered"
echo ""

# ---- Main matrix -------------------------------------------------------------
declare -a OBSERVED_MATRIX=()  # human-readable summary collected for the run

for fixture in "${FIXTURES[@]}"; do
  fname="$(basename "$fixture")"
  for state in none allow_no_repo allow_with_repo; do
    case "$state" in
      none)             set_state_none ;;
      allow_no_repo)    set_state_allow_no_repo ;;
      allow_with_repo)  set_state_allow_with_repo ;;
    esac

    output="$(run_core_dry_run "$fixture")"
    rc=$?
    actual_we="$(extract_would_exit "$output")"

    expected_we="$(expected_would_exit "$fname" "$state")"

    label="$fname [$state]"

    if [ "$expected_we" = "UNKNOWN" ]; then
      echo "SKIP  $label  (no expected WOULD_EXIT entry — observed=$actual_we rc=$rc)"
    else
      assert_eq "would_exit  $label" "$expected_we" "$actual_we"
    fi

    # The dry-run path itself must always exit 0 regardless of WOULD_EXIT,
    # so a non-zero rc here is an additional bug.
    assert_eq "dry_run_rc=0  $label" "0" "$rc"

    # No `gh issue create` invocation should appear in dry-run output.
    assert_not_match "no_gh_call  $label" "gh issue create" "$output"

    OBSERVED_MATRIX+=("$fname [$state] -> WOULD_EXIT=$actual_we (expected=$expected_we)")

    # Golden write/diff (only for state allow_with_repo on non-bait fixtures —
    # those produce stable BODY content; other states produce a 3-line dry-run
    # short form that's not worth diffing.)
    case "$fname" in
      secrets-bait-*) ;;  # bait fixtures never reach the body-print branch
      *)
        if [ "$state" = "allow_with_repo" ]; then
          golden_path="$GOLDENS_DIR/${fname%.json}__${state}.golden.txt"
          normalised="$(printf '%s' "$output" | normalise_for_golden)"
          if [ "$WRITE_GOLDENS" = "1" ]; then
            printf '%s' "$normalised" > "$golden_path"
            echo "WROTE  golden  $(basename "$golden_path")"
            PASS_COUNT=$((PASS_COUNT + 1))
          elif [ -f "$golden_path" ]; then
            golden_content="$(cat "$golden_path")"
            if [ "$normalised" = "$golden_content" ]; then
              echo "PASS  golden_diff  $(basename "$golden_path")"
              PASS_COUNT=$((PASS_COUNT + 1))
            else
              echo "FAIL  golden_diff  $(basename "$golden_path")"
              echo "----- diff (expected vs actual) -----"
              diff <(printf '%s' "$golden_content") <(printf '%s' "$normalised") || true
              echo "-------------------------------------"
              FAIL_LINES+=("FAIL  golden_diff  $(basename "$golden_path")")
              FAIL_COUNT=$((FAIL_COUNT + 1))
            fi
          else
            echo "INFO  no golden file yet for $(basename "$golden_path")  (run with WRITE_GOLDENS=1 to create)"
          fi
        fi
        ;;
    esac
  done
done

# ---- Determinism test --------------------------------------------------------
# Run the same fixture twice in identical state; output must be byte-identical.
echo ""
echo "==== Determinism ===="
DET_FIXTURE="$FIXTURES_DIR/supervisor-escalated.json"
if [ -f "$DET_FIXTURE" ]; then
  set_state_allow_with_repo
  out1="$(run_core_dry_run "$DET_FIXTURE" | normalise_for_golden)"
  out2="$(run_core_dry_run "$DET_FIXTURE" | normalise_for_golden)"
  if [ "$out1" = "$out2" ]; then
    echo "PASS  determinism  supervisor-escalated.json (allow_with_repo) — byte-identical across two runs"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL  determinism  outputs differ"
    diff <(printf '%s' "$out1") <(printf '%s' "$out2") || true
    FAIL_LINES+=("FAIL  determinism  supervisor-escalated.json")
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
else
  echo "SKIP  determinism  fixture missing: $DET_FIXTURE"
fi

# ---- Privacy bait test (already covered above, but assert at least one ran) --
echo ""
echo "==== Privacy bait coverage ===="
BAIT_COUNT=0
for fixture in "${FIXTURES[@]}"; do
  case "$(basename "$fixture")" in
    secrets-bait-*) BAIT_COUNT=$((BAIT_COUNT + 1)) ;;
  esac
done
if [ "$BAIT_COUNT" -ge 1 ]; then
  echo "PASS  bait_fixtures_present  count=$BAIT_COUNT"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "FAIL  bait_fixtures_present  expected>=1  actual=0"
  FAIL_LINES+=("FAIL  bait_fixtures_present")
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ---- Order-of-operations pin (canonical post-heal-iter-1 order) -------------
# Pins the DOCUMENTED order: raw-privacy -> consent -> repo -> body-privacy
# -> interest -> dedup. supervisor-pass.json with state=none must yield
# WOULD_EXIT=3 (consent missing — interest filter never reached). Privacy
# bait fixtures must still yield WOULD_EXIT=2 in state=none, proving raw
# privacy scan runs before consent so PRIVACY_BLOCKED is always logged on a
# healthy-but-leaky payload.
echo ""
echo "==== Order-of-operations pin (consent-before-interest, privacy-before-consent) ===="
set_state_none
out_pass="$(run_core_dry_run "$FIXTURES_DIR/supervisor-pass.json")"
we_pass="$(extract_would_exit "$out_pass")"
assert_eq "consent_before_interest_filter (supervisor-pass:none)" "3" "$we_pass"
assert_match "consent_uninitialised_marker (supervisor-pass:none)" "consent_uninitialised" "$out_pass"

if [ -f "$FIXTURES_DIR/secrets-bait-ghp.json" ]; then
  set_state_none
  out_bait="$(run_core_dry_run "$FIXTURES_DIR/secrets-bait-ghp.json")"
  we_bait="$(extract_would_exit "$out_bait")"
  assert_eq "raw_privacy_before_consent (secrets-bait-ghp:none)" "2" "$we_bait"
  assert_match "privacy_blocked_marker (secrets-bait-ghp:none)" "PRIVACY_BLOCKED" "$out_bait"
fi

# ---- Consent-denied marker test ---------------------------------------------
# When consent is exactly "no", core must emit `denied — skipped` on stderr
# (distinguishable from `consent_uninitialised` so the wrapper can suppress
# the pending notice for users who have already opted out).
echo ""
echo "==== Consent-denied marker (denied — skipped) ===="
DENIED_TMP="$(mktemp)"
mkdir -p "$(dirname "$CONSENT_FILE")"
printf '%s\n' '{"telemetry": "no"}' > "$CONSENT_FILE"
out_denied="$(run_core_dry_run "$FIXTURES_DIR/supervisor-escalated.json" 2>"$DENIED_TMP" || true)"
# run_core_dry_run already merges stderr into stdout, so we re-run capturing
# stderr separately for assertions.
out_denied_full="$(bash "$CORE" --dry-run < "$FIXTURES_DIR/supervisor-escalated.json" 2>&1 || true)"
we_denied="$(extract_would_exit "$out_denied_full")"
assert_eq "consent_no_exit (supervisor-escalated:no)" "3" "$we_denied"
assert_match "denied_skipped_marker (supervisor-escalated:no)" "denied — skipped" "$out_denied_full"
assert_not_match "no_uninitialised_when_denied (supervisor-escalated:no)" "consent_uninitialised" "$out_denied_full"
rm -f "$DENIED_TMP"

# ---- Transcript-fallback test (v14.2.1) -------------------------------------
# When the SubagentStop payload carries NO inline result text (no
# last_assistant_message / result_block / output / agent_output), the core must
# fall back to reading the LAST assistant message out of the transcript JSONL —
# preferring the subagent-scoped `agent_transcript_path`, then the shared
# `transcript_path`. We synthesise a real on-disk transcript (absolute path, so
# os.path.exists resolves regardless of CWD) carrying an ESCALATED
# SUPERVISOR_RESULT and assert the core reaches the gh-send path (WOULD_EXIT=0
# at allow_with_repo) rather than short-circuiting on `no_known_result_block`.
echo ""
echo "==== Transcript fallback (no inline result text) ===="
TRANSCRIPT_TMPDIR="$(mktemp -d 2>/dev/null || echo "/tmp/telemetry-transcript-$$")"
mkdir -p "$TRANSCRIPT_TMPDIR" 2>/dev/null || true
set_state_allow_with_repo

# Build a transcript JSONL + two payloads (agent_transcript_path-only and
# transcript_path-only) via python3 to avoid bash JSON-escaping hazards.
python3 - "$TRANSCRIPT_TMPDIR" <<'PY'
import json, os, sys
d = sys.argv[1]
result_text = (
    "## SUPERVISOR_RESULT\n"
    "- schema_version: 1\n"
    "- task_id: fixture-transcript-fallback-task-0021\n"
    "- status: completed_with_escalation\n"
    "- heal_loop_ran: true\n"
    "- heal_decision: ESCALATED\n"
    "- heal_iterations: 3\n"
    "- heal_fixable_issues_fixed: 1\n"
    "- heal_remaining_issues: 2\n"
    "- subtasks_total: 2\n"
    "- subtasks_completed: 2\n"
    "- subtasks_failed: []\n"
    "- pr_url: https://github.com/example/repo/pull/77\n"
    "- summary: Result text recovered from the transcript JSONL fallback, not an inline field.\n"
)
transcript = os.path.join(d, "subagent.jsonl")
with open(transcript, "w", encoding="utf-8") as fh:
    # A couple of non-assistant / noise lines, then the real last assistant msg.
    fh.write(json.dumps({"type": "user", "message": {"role": "user", "content": "go"}}) + "\n")
    fh.write("this line is deliberately not valid json\n")
    fh.write(json.dumps({"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": "intermediate, ignore me"}]}}) + "\n")
    fh.write(json.dumps({"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": result_text}]}}) + "\n")

# Payload variant A: only agent_transcript_path (subagent-scoped) is present.
with open(os.path.join(d, "payload-agent-tp.json"), "w", encoding="utf-8") as fh:
    json.dump({
        "session_id": "fixture-sess-transcript-fallback-0021",
        "agent_type": "ai-agent-manager-plugin:supervisor-runner",
        "agent_transcript_path": transcript,
    }, fh)

# Payload variant B: only the shared transcript_path is present.
with open(os.path.join(d, "payload-shared-tp.json"), "w", encoding="utf-8") as fh:
    json.dump({
        "session_id": "fixture-sess-transcript-fallback-0021",
        "agent_type": "ai-agent-manager-plugin:supervisor-runner",
        "transcript_path": transcript,
    }, fh)
PY

for variant in payload-agent-tp payload-shared-tp; do
  out_tr="$(run_core_dry_run "$TRANSCRIPT_TMPDIR/$variant.json")"
  we_tr="$(extract_would_exit "$out_tr")"
  assert_eq "transcript_fallback would_exit ($variant)" "0" "$we_tr"
  assert_not_match "transcript_fallback schema_detected ($variant)" "no_known_result_block" "$out_tr"
  assert_match "transcript_fallback body_from_transcript ($variant)" "recovered from the transcript JSONL fallback" "$out_tr"
done

rm -rf "$TRANSCRIPT_TMPDIR" 2>/dev/null || true

# ---- Summary ----------------------------------------------------------------
TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo ""
echo "=========================================="
echo "RESULT  total=$TOTAL  passed=$PASS_COUNT  failed=$FAIL_COUNT"
echo "=========================================="
echo ""
echo "==== Observed WOULD_EXIT matrix ===="
printf '  %s\n' "${OBSERVED_MATRIX[@]}"

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo ""
  echo "==== Failures ===="
  printf '  %s\n' "${FAIL_LINES[@]}"
  exit 1
fi

exit 0
