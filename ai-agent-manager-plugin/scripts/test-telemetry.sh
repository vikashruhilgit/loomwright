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
# OBSERVED ORDER-OF-OPERATIONS DIVERGENCE FROM docs/TELEMETRY.md
#   docs/TELEMETRY.md §"Interest filter" says the order is
#   privacy -> target-repo -> interest -> dedup. The current core
#   short-circuits the interest filter inside stage 1 (python), BEFORE
#   reading the consent file or resolving the target repo. Concretely,
#   supervisor-pass.json (score 9, completed/PASS) yields WOULD_EXIT=5
#   even with `consent: missing`, proving interest-filter-runs-before-
#   consent. The harness pins this behaviour so any future re-ordering
#   becomes a visible test failure (the WOULD_EXIT for supervisor-pass
#   would flip from 5 to 3 if consent were checked first).
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

# Expected-WOULD_EXIT matrix per .supervisor/worker-summaries/subtask-2b.md
#
# Fixture                       | none | allow_no_repo | allow_with_repo
# ------------------------------+------+---------------+----------------
# supervisor-pass.json          |  5   |       5       |       5         (interest filter wins early)
# supervisor-escalated.json     |  3   |       4       |       0
# qa-failed.json                |  3   |       4       |       0
# secrets-bait-ghp.json         |  2   |       2       |       2         (privacy fail-closed in stage1)
# secrets-bait-email.json       |  2   |       2       |       2         (privacy fail-closed in stage1)
expected_would_exit() {
  local fixture_name="$1" state="$2"
  case "$fixture_name" in
    secrets-bait-*)
      printf '2\n'
      return
      ;;
  esac
  case "$fixture_name:$state" in
    supervisor-pass.json:*)              printf '5\n' ;;
    supervisor-escalated.json:none)      printf '3\n' ;;
    supervisor-escalated.json:allow_no_repo) printf '4\n' ;;
    supervisor-escalated.json:allow_with_repo) printf '0\n' ;;
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

# ---- Order-of-operations divergence pin -------------------------------------
# Pins the observed (NOT documented) order: interest-filter runs before
# consent. If supervisor-pass.json yields anything other than WOULD_EXIT=5
# in state=none, the order has changed and this assertion will fire so
# Phase 4.5 can decide to accept the change or revert.
echo ""
echo "==== Order-of-operations pin (interest-vs-consent) ===="
set_state_none
out="$(run_core_dry_run "$FIXTURES_DIR/supervisor-pass.json")"
we="$(extract_would_exit "$out")"
assert_eq "interest_filter_runs_before_consent (supervisor-pass:none)" "5" "$we"
assert_match "stage1_early_exit_marker" "stage1_early_exit=5" "$out"

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
