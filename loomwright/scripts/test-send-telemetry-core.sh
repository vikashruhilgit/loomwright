#!/usr/bin/env bash
# test-send-telemetry-core.sh — direct deterministic unit tests for send-telemetry-core.sh
#
# Review-remediation item 02 (P0, tests-only). The core's privacy/consent/dedup logic is
# the one component whose regression could leak user data to a public GitHub issue;
# test-telemetry.sh covers the wrapper-level fixture matrix, but this harness unit-tests
# the core directly: the stage-1 Python privacy scan (all 9 PRIVACY_PATTERNS labels),
# redaction markers, the v11.2.0 privacy-before-consent ordering guarantee, the consent
# matrix (incl. malformed-JSON fail-closed + nullable/missing-key discipline), the
# interest filter, and dedup determinism.
#
# GUARANTEES / DESIGN
#   - No network, no gh: every core invocation runs with a PATH-prepended `gh` shim that
#     fails loudly (exit 97) and appends to a marker file; the harness asserts the marker
#     never appears AND that live-path invocations always short-circuit (exit 2/3/4/5)
#     before the gh step. Would-send paths use --dry-run + WOULD_EXIT assertions only.
#   - Sandbox isolation: the core resolves .supervisor/telemetry-consent.json and
#     .supervisor/logs/ from $PWD (send-telemetry-core.sh:42-44), so every invocation
#     runs with CWD inside a mktemp sandbox. The real repo .supervisor/ is snapshotted
#     before and asserted byte-identical after.
#   - Fixtures are generated at runtime (python3, into the sandbox) following the
#     test-telemetry.sh transcript-fallback precedent — deliberately NOT committed into
#     telemetry-fixtures/*.json, whose flat glob is auto-discovered by test-telemetry.sh's
#     consent-state matrix (committed files there would add SKIP noise to that harness).
#   - Group 7 (redaction) needs the production redact_text()/PRIVACY_PATTERNS: a payload
#     containing a secret always exits 2 in stage 1 and never prints its redacted body,
#     so the harness extracts the STAGE1_PY heredoc verbatim from the core and exec()s it
#     with a clean payload, then calls the REAL redact_text/scan_for_secret from the
#     resulting namespace. This tests production code, not a copy.
#   - bash-3.2-safe: no mapfile, no associative arrays, no `;&` fallthrough; small
#     fixtures only (no pattern-substitution on large strings); no `stat`-based probes,
#     timestamps come from python3 datetime (portable across BSD/GNU).
#
# KNOWN ACCEPTED TRADE-OFF (do not "fix"):
#   The email regex ([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}) over-matches
#   non-PII strings such as scoped decorators or user@host.domain identifiers in code.
#   That over-match is fail-closed (blocks a send that might have been fine) and is an
#   accepted trade-off per docs/TELEMETRY.md — this harness pins the label, not the
#   regex's precision.
#
# EXIT: 0 on full pass, 1 on any failed assertion.

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CORE="$SCRIPT_DIR/send-telemetry-core.sh"

if [ ! -f "$CORE" ]; then
  echo "FATAL  core script not found: $CORE" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  # The core itself hard-requires python3; without it there is nothing meaningful
  # to test and the sibling test-telemetry.sh would already be failing loudly.
  echo "FATAL  python3 not available — cannot test send-telemetry-core.sh" >&2
  exit 1
fi

# The env override for the target repo must not leak into the consent-matrix
# assertions (allow_no_repo must be exit 4, not env-resolved).
unset LOOMWRIGHT_TELEMETRY_REPO 2>/dev/null || true

# ---- Sandbox -----------------------------------------------------------------
SANDBOX="$(mktemp -d 2>/dev/null)" || { echo "FATAL  mktemp failed" >&2; exit 1; }
cleanup() { rm -rf "$SANDBOX" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

FIXDIR="$SANDBOX/fixtures"
SHIM_DIR="$SANDBOX/bin"
GH_MARKER="$SANDBOX/gh-invoked.marker"
SB_CONSENT="$SANDBOX/.supervisor/telemetry-consent.json"
SB_SENT_LOG="$SANDBOX/.supervisor/logs/telemetry-sent.log"
mkdir -p "$FIXDIR" "$SHIM_DIR"

# ---- gh shim: fails loudly if ANY core invocation ever reaches the gh step ----
{
  printf '#!/bin/sh\n'
  printf 'echo "FATAL gh invoked during test-send-telemetry-core: $*" >&2\n'
  printf 'echo "gh $*" >> "%s"\n' "$GH_MARKER"
  printf 'exit 97\n'
} > "$SHIM_DIR/gh"
chmod +x "$SHIM_DIR/gh"

# ---- Snapshot the REAL repo .supervisor state (must be untouched at the end) --
REAL_CONSENT="$REPO_ROOT/.supervisor/telemetry-consent.json"
REAL_SENT_LOG="$REPO_ROOT/.supervisor/logs/telemetry-sent.log"
snapshot_real() {
  if [ -f "$REAL_CONSENT" ]; then cksum < "$REAL_CONSENT"; else echo "consent:ABSENT"; fi
  if [ -f "$REAL_SENT_LOG" ]; then cksum < "$REAL_SENT_LOG"; else echo "sentlog:ABSENT"; fi
}
REAL_BEFORE="$(snapshot_real)"

# ---- Assert helpers (test-telemetry.sh convention) ----------------------------
PASS_COUNT=0
FAIL_COUNT=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "PASS  $label"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL  $label  expected=$expected  actual=$actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

assert_match() {
  local label="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    echo "PASS  $label"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL  $label  needle='$needle' not found"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

assert_not_match() {
  local label="$1" needle="$2" haystack="$3"
  if ! printf '%s' "$haystack" | grep -qF -- "$needle"; then
    echo "PASS  $label"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL  $label  unexpected '$needle' present"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

extract_would_exit() {
  printf '%s' "$1" | grep -E '^WOULD_EXIT=' | tail -1 | cut -d= -f2 | tr -d '[:space:]'
}

# ---- Core invocation helper (always sandbox-CWD + gh shim) --------------------
# Usage: out="$(run_core <fixture> [--dry-run])"; rc=$?
run_core() {
  local fixture="$1"; shift
  ( cd "$SANDBOX" && PATH="$SHIM_DIR:$PATH" bash "$CORE" "$@" < "$fixture" 2>&1 )
}

# ---- Consent-state setters (sandbox-scoped) -----------------------------------
consent_none()  { rm -f "$SB_CONSENT"; }
consent_write() { mkdir -p "$(dirname "$SB_CONSENT")"; printf '%s\n' "$1" > "$SB_CONSENT"; }

# ---- Generate fixtures + label/secret table ------------------------------------
# One SUPERVISOR_RESULT payload per privacy label, each secret constructed so it
# matches ITS pattern and no EARLIER pattern in PRIVACY_PATTERNS list order (first
# match wins, so this makes the emitted label assertion exact).
python3 - "$FIXDIR" <<'PY'
import json, os, sys

outdir = sys.argv[1]

# (label, secret) — list order mirrors PRIVACY_PATTERNS in send-telemetry-core.sh.
SECRETS = [
    ("openai-key",      "sk-AAAAAAAAAAAAAAAAAAAAAAAA1234"),
    ("github-token",    "ghp_ABCDEFGHIJKLMNOPQRSTUVWX"),
    ("api-key",         "api_key = super-secret-value-123"),
    ("bearer",          "Bearer abc123def456token"),
    ("password",        "password: hunter2-secret-value"),
    ("macos-home-path", "/Users/testuser/secret/project/file.txt"),
    ("linux-home-path", "/home/testuser/secret/project/"),
    # Known accepted trade-off: this regex over-matches (see header comment).
    ("email",           "contact was test.user@example.org during run"),
    ("env-assignment",  "DATABASE_URL=postgres-secret-dsn-value"),
]

with open(os.path.join(outdir, "secrets.tsv"), "w") as fh:
    for label, secret in SECRETS:
        fh.write("%s\t%s\n" % (label, secret))

def block(task_id, status, extra_lines):
    lines = [
        "## SUPERVISOR_RESULT",
        "- schema_version: 1",
        "- task_id: %s" % task_id,
        "- status: %s" % status,
    ]
    lines.extend(extra_lines)
    return "\n".join(lines) + "\n"

def write(name, result_block):
    payload = {
        "session_id": "fixture-core-%s" % os.path.splitext(name)[0],
        "agent_type": "loomwright:supervisor-runner",
        "result_block": result_block,
    }
    with open(os.path.join(outdir, name), "w") as fh:
        json.dump(payload, fh)

# Group 1: privacy true-positives (one fixture per label).
for label, secret in SECRETS:
    if label == "env-assignment":
        # ^-anchored MULTILINE pattern: the secret must sit on its own line.
        secret_line = secret
    else:
        secret_line = "- detail: %s" % secret
    write("priv-%s.json" % label, block(
        "priv-%s" % label, "failed",
        ["- subtasks_failed: []",
         "- summary: privacy true-positive fixture",
         secret_line]))

# Group 2: privacy true-negatives (near-misses that must NOT trip the scan).
write("negatives.json", block(
    "neg-nearmiss", "failed",
    ["- subtasks_failed: []",
     "- summary: near-misses sk-short and ghp_short plus apikey mentioned in prose and a bare /Users/ segment"]))

# Group 3: ordering — healthy (interest-filter-skippable) payload WITH a secret,
# plus its clean twin proving the counterfactual (clean twin -> exit 5).
write("order-healthy-secret.json", block(
    "order-healthy", "completed",
    ["- heal_decision: PASS",
     "- heal_remaining_issues: 0",
     "- subtasks_failed: []",
     "- summary: healthy run that leaks ghp_ORDERINGREGRESSION0123456789 token"]))
write("order-healthy-clean.json", block(
    "order-healthy", "completed",
    ["- heal_decision: PASS",
     "- heal_remaining_issues: 0",
     "- subtasks_failed: []",
     "- summary: healthy run with no secret at all"]))

# Groups 4/5: escalated (NOT interest-skipped) payload for the consent matrix.
write("consent-escalated.json", block(
    "consent-matrix-task", "completed_with_escalation",
    ["- heal_decision: ESCALATED",
     "- heal_remaining_issues: 2",
     "- subtasks_failed: []",
     "- summary: escalated run for consent and dedup matrix"]))

# Group 6: dedup pair — same task_id, different primary_error (subtasks_failed[0]).
write("dedup-a.json", block(
    "dedup-task-A", "failed",
    ["- subtasks_failed: [BD-9x]",
     "- summary: dedup determinism fixture A"]))
write("dedup-b.json", block(
    "dedup-task-A", "failed",
    ["- subtasks_failed: [BD-7z]",
     "- summary: dedup determinism fixture B"]))
PY
if [ ! -f "$FIXDIR/secrets.tsv" ]; then
  echo "FATAL  fixture generation failed" >&2
  exit 1
fi

echo "==== test-send-telemetry-core ===="
echo "Core:    $CORE"
echo "Sandbox: $SANDBOX"
echo ""

# ---- Group 0: sanity — shim precedence + degenerate stdin ---------------------
echo "==== Group 0: sanity (gh shim precedence, degenerate stdin) ===="
SHIM_RESOLVED="$( cd "$SANDBOX" && PATH="$SHIM_DIR:$PATH" command -v gh )"
assert_eq "gh_shim_first_in_path" "$SHIM_DIR/gh" "$SHIM_RESOLVED"

out="$( ( cd "$SANDBOX" && PATH="$SHIM_DIR:$PATH" bash "$CORE" </dev/null 2>&1 ) )"
rc=$?
assert_eq "empty_stdin_exit=5" "5" "$rc"
assert_match "empty_stdin_marker" "empty_stdin" "$out"

printf 'this is not json' > "$FIXDIR/notjson.txt"
out="$(run_core "$FIXDIR/notjson.txt")"
rc=$?
assert_eq "nonjson_stdin_exit=5" "5" "$rc"
assert_match "nonjson_stdin_marker" "json_parse_failed" "$out"

# Sanity that sandbox-CWD isolation is in effect (core mkdir'd its logs there).
if [ -d "$SANDBOX/.supervisor/logs" ]; then
  assert_eq "sandbox_cwd_isolation_logs_dir" "present" "present"
else
  assert_eq "sandbox_cwd_isolation_logs_dir" "present" "absent"
fi

# ---- Group 1: privacy true-positives — one payload per PRIVACY_PATTERNS label --
# Live (non-dry-run) invocations: privacy blocks in stage 1, BEFORE consent, so
# the real exit code must be 2 with a PRIVACY_BLOCKED stderr line naming the label.
echo ""
echo "==== Group 1: privacy true-positives (9 labels, exit 2 + label) ===="
consent_none
LABELS_SEEN=0
while IFS="$(printf '\t')" read -r label secret; do
  [ -z "$label" ] && continue
  LABELS_SEEN=$((LABELS_SEEN + 1))
  out="$(run_core "$FIXDIR/priv-$label.json")"
  rc=$?
  assert_eq "privacy_exit=2 [$label]" "2" "$rc"
  assert_match "privacy_label [$label]" "PRIVACY_BLOCKED pattern=$label" "$out"
done < "$FIXDIR/secrets.tsv"
assert_eq "privacy_label_count" "9" "$LABELS_SEEN"

# ---- Group 2: privacy true-negatives — near-misses must NOT exit 2 ------------
echo ""
echo "==== Group 2: privacy true-negatives (near-misses pass the scan) ===="
consent_none
out="$(run_core "$FIXDIR/negatives.json")"
rc=$?
# Passes privacy, then stops at missing consent (exit 3) — NOT privacy-blocked.
assert_eq "negatives_exit=3_not_2" "3" "$rc"
assert_not_match "negatives_no_privacy_block" "PRIVACY_BLOCKED" "$out"
assert_match "negatives_reached_consent" "consent_uninitialised" "$out"

# ---- Group 3: ordering guarantee — privacy BEFORE consent/interest ------------
# v11.2.0 regression pin: a healthy (score>=5, success) payload with a secret must
# exit 2, never 5, even when consent+repo are fully configured. The clean twin
# proves the counterfactual: same shape without the secret IS interest-skipped (5).
echo ""
echo "==== Group 3: ordering guarantee (secret+healthy => 2, clean twin => 5) ===="
consent_write '{"telemetry": "always_allow", "telemetry_repo": "example/repo"}'
out="$(run_core "$FIXDIR/order-healthy-secret.json")"
rc=$?
assert_eq "ordering_secret_exit=2" "2" "$rc"
assert_match "ordering_privacy_marker" "PRIVACY_BLOCKED pattern=github-token" "$out"
assert_not_match "ordering_no_filter_skip" "filter_skipped" "$out"

out="$(run_core "$FIXDIR/order-healthy-clean.json")"
rc=$?
assert_eq "ordering_clean_twin_exit=5" "5" "$rc"
assert_match "ordering_clean_twin_interest_filter" "filter_skipped reason=interest_filter" "$out"

# ---- Group 4: consent matrix ---------------------------------------------------
echo ""
echo "==== Group 4: consent matrix ===="
# (a) consent file absent -> exit 3, uninitialised state=missing.
consent_none
out="$(run_core "$FIXDIR/consent-escalated.json")"
rc=$?
assert_eq "consent_absent_exit=3" "3" "$rc"
assert_match "consent_absent_marker" "consent_uninitialised state=missing" "$out"

# (b) explicit opt-out -> exit 3 with the distinct denied marker.
consent_write '{"telemetry": "no"}'
out="$(run_core "$FIXDIR/consent-escalated.json")"
rc=$?
assert_eq "consent_no_exit=3" "3" "$rc"
assert_match "consent_no_denied_marker" "denied — skipped" "$out"
assert_not_match "consent_no_not_uninitialised" "consent_uninitialised" "$out"

# (c) malformed JSON -> FAIL-CLOSED. Verified against the code first
#     (send-telemetry-core.sh:841-843 emits CONSENT=parse_error on any parse
#     exception; :873-884 routes parse_error into the uninitialised exit-3 arm).
consent_write '{not valid json'
out="$(run_core "$FIXDIR/consent-escalated.json")"
rc=$?
assert_eq "consent_malformed_fails_closed_exit=3" "3" "$rc"
assert_match "consent_malformed_state" "consent_uninitialised state=parse_error" "$out"

# (d) always_allow without any repo -> exit 4 (env override unset at top).
consent_write '{"telemetry": "always_allow"}'
out="$(run_core "$FIXDIR/consent-escalated.json")"
rc=$?
assert_eq "consent_allow_no_repo_exit=4" "4" "$rc"
assert_match "consent_allow_no_repo_marker" "no_repo_configured" "$out"

# (e) always_allow + telemetry_repo + --dry-run -> would-send (WOULD_EXIT=0).
consent_write '{"telemetry": "always_allow", "telemetry_repo": "example/repo"}'
out="$(run_core "$FIXDIR/consent-escalated.json" --dry-run)"
rc=$?
assert_eq "would_send_dry_run_rc=0" "0" "$rc"
assert_eq "would_send_would_exit=0" "0" "$(extract_would_exit "$out")"
assert_match "would_send_target_repo" "TARGET_REPO=example/repo" "$out"
assert_match "would_send_body_present" "BODY_BEGIN" "$out"
assert_not_match "would_send_no_gh_line" "gh issue create" "$out"

# (f) env var wins over consent-file repo resolution (documented precedence).
consent_write '{"telemetry": "always_allow"}'
out="$( ( cd "$SANDBOX" && PATH="$SHIM_DIR:$PATH" LOOMWRIGHT_TELEMETRY_REPO="env-owner/env-repo" bash "$CORE" --dry-run < "$FIXDIR/consent-escalated.json" 2>&1 ) )"
rc=$?
assert_eq "env_repo_dry_run_rc=0" "0" "$rc"
assert_match "env_repo_resolved" "TARGET_REPO=env-owner/env-repo" "$out"

# ---- Group 5: nullable/missing-key discipline (PR #84 lesson) ------------------
# Missing key and explicit null must BOTH fail closed, for both consent fields.
echo ""
echo "==== Group 5: nullable/missing-key discipline ===="
# telemetry key MISSING entirely -> default "prompt" -> exit 3.
consent_write '{}'
out="$(run_core "$FIXDIR/consent-escalated.json")"
rc=$?
assert_eq "telemetry_key_missing_exit=3" "3" "$rc"
assert_match "telemetry_key_missing_state" "consent_uninitialised state=prompt" "$out"

# telemetry explicit null -> non-string guard -> "prompt" -> exit 3.
consent_write '{"telemetry": null}'
out="$(run_core "$FIXDIR/consent-escalated.json")"
rc=$?
assert_eq "telemetry_explicit_null_exit=3" "3" "$rc"
assert_match "telemetry_explicit_null_state" "consent_uninitialised state=prompt" "$out"

# telemetry non-string (number) -> same guard -> exit 3.
consent_write '{"telemetry": 42}'
out="$(run_core "$FIXDIR/consent-escalated.json")"
rc=$?
assert_eq "telemetry_nonstring_exit=3" "3" "$rc"
assert_match "telemetry_nonstring_state" "consent_uninitialised state=prompt" "$out"

# telemetry_repo key MISSING (always_allow) -> exit 4 (covered in 4d; re-pin here).
consent_write '{"telemetry": "always_allow"}'
out="$(run_core "$FIXDIR/consent-escalated.json")"
rc=$?
assert_eq "repo_key_missing_exit=4" "4" "$rc"

# telemetry_repo explicit null -> non-string guard -> "" -> exit 4.
consent_write '{"telemetry": "always_allow", "telemetry_repo": null}'
out="$(run_core "$FIXDIR/consent-escalated.json")"
rc=$?
assert_eq "repo_explicit_null_exit=4" "4" "$rc"
assert_match "repo_explicit_null_marker" "no_repo_configured" "$out"

# ---- Group 6: dedup determinism -------------------------------------------------
# Hash contract pin (send-telemetry-core.sh:735): sha256("task_id::bucket::primary_error").
# dedup-a.json: task_id=dedup-task-A, status=failed (base 2.0) minus 0.5 for one
# failed subtask => score 1.5 => bucket "low"; primary_error=BD-9x (subtasks_failed[0]).
# telemetry-sent.log is appended ONLY on the live send path, so we SEED it here.
# If the hash contract drifted, the seeded entry would not match, the core would
# fall through toward the live gh step, and the shim would fail the run loudly.
echo ""
echo "==== Group 6: dedup determinism ===="
consent_write '{"telemetry": "always_allow", "telemetry_repo": "example/repo"}'
DEDUP_HASH_A="$(python3 -c 'import hashlib; print(hashlib.sha256(b"dedup-task-A::low::BD-9x").hexdigest())')"
TS_NOW="$(python3 -c 'from datetime import datetime, timezone; print(datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))')"
TS_STALE="$(python3 -c 'from datetime import datetime, timezone, timedelta; print((datetime.now(timezone.utc) - timedelta(hours=10)).strftime("%Y-%m-%dT%H:%M:%SZ"))')"

mkdir -p "$(dirname "$SB_SENT_LOG")"
# (i) same hash within the 6h window -> second occurrence exits 5 (dedup_hit).
printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$TS_NOW" "$DEDUP_HASH_A" "dedup-task-A" "2" "low" "https://example.invalid/issues/1" > "$SB_SENT_LOG"
out="$(run_core "$FIXDIR/dedup-a.json")"
rc=$?
assert_eq "dedup_same_hash_within_window_exit=5" "5" "$rc"
assert_match "dedup_hit_marker" "dedup_hit hash=$DEDUP_HASH_A" "$out"

# (ii) different primary_error (BD-7z) -> different hash -> NOT deduped -> would-send.
out="$(run_core "$FIXDIR/dedup-b.json" --dry-run)"
rc=$?
assert_eq "dedup_different_error_rc=0" "0" "$rc"
assert_eq "dedup_different_error_would_exit=0" "0" "$(extract_would_exit "$out")"
assert_not_match "dedup_different_error_no_hit" "dedup_hit" "$out"

# (iii) same hash but OUTSIDE the 6h window -> NOT deduped -> would-send.
printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$TS_STALE" "$DEDUP_HASH_A" "dedup-task-A" "2" "low" "https://example.invalid/issues/1" > "$SB_SENT_LOG"
out="$(run_core "$FIXDIR/dedup-a.json" --dry-run)"
rc=$?
assert_eq "dedup_stale_entry_rc=0" "0" "$rc"
assert_eq "dedup_stale_entry_would_exit=0" "0" "$(extract_would_exit "$out")"
assert_not_match "dedup_stale_entry_no_hit" "dedup_hit" "$out"
rm -f "$SB_SENT_LOG"

# ---- Group 7: redaction visibility ([REDACTED:<label>] markers) ----------------
# A secret-bearing payload exits 2 before the body ever prints, so the ONLY way to
# observe redaction end-to-end is to run the production stage-1 code directly:
# extract the STAGE1_PY heredoc from the core verbatim, exec it with a clean
# payload, then exercise its redact_text()/scan_for_secret()/PRIVACY_PATTERNS.
echo ""
echo "==== Group 7: redaction markers via extracted production stage-1 code ===="
# Anchor: the PRIVACY_PATTERNS identifier must exist in the core.
if grep -q 'PRIVACY_PATTERNS' "$CORE"; then
  assert_eq "core_privacy_patterns_anchor" "present" "present"
else
  assert_eq "core_privacy_patterns_anchor" "present" "absent"
fi

awk '/STAGE1_PY <</{grab=1; next} grab && $0=="PY"{exit} grab{print}' "$CORE" > "$SANDBOX/stage1.py"
if [ -s "$SANDBOX/stage1.py" ] && grep -q 'PRIVACY_PATTERNS' "$SANDBOX/stage1.py"; then
  assert_eq "stage1_extraction" "ok" "ok"
else
  assert_eq "stage1_extraction" "ok" "failed"
fi

# NOTE: the harness is written to a file first (NOT a heredoc inside $(...)) —
# bash 3.2 mis-parses command substitutions whose embedded heredoc body contains
# a single quote (memory: bash32 parser quirks; reproduced here).
cat > "$SANDBOX/harness.py" <<'PY'
import io, sys

stage1_path, clean_fixture, secrets_tsv = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(stage1_path).read()
clean_stdin = open(clean_fixture).read()

ns = {"__name__": "stage1_under_test"}
real_stdout, real_stdin = sys.stdout, sys.stdin
sys.stdin = io.StringIO(clean_stdin)
sys.stdout = io.StringIO()
err = None
try:
    exec(compile(src, stage1_path, "exec"), ns)
except SystemExit:
    pass
except Exception as e:  # noqa: BLE001 — report, don't crash the harness
    err = e
finally:
    sys.stdout, sys.stdin = real_stdout, real_stdin

if err is not None:
    print("HARNESS_FAIL exec_error=%r" % err)
    sys.exit(1)

pats = ns.get("PRIVACY_PATTERNS")
redact = ns.get("redact_text")
scan = ns.get("scan_for_secret")
if not pats or not callable(redact) or not callable(scan):
    print("HARNESS_FAIL missing_symbols")
    sys.exit(1)

labels = [label for _, label in pats]
expected = ["openai-key", "github-token", "api-key", "bearer", "password",
            "macos-home-path", "linux-home-path", "email", "env-assignment"]
if labels != expected:
    print("HARNESS_FAIL label_drift got=%s" % labels)
    sys.exit(1)
print("PATTERN_LABELS_OK count=%d" % len(labels))

ok = True
for line in open(secrets_tsv):
    line = line.rstrip("\n")
    if not line:
        continue
    label, secret = line.split("\t", 1)
    if label == "env-assignment":
        # ^-anchored MULTILINE pattern: must be tested at line start.
        sample = secret
    else:
        sample = "prefix %s suffix" % secret
    out = redact(sample)
    marker = "[REDACTED:%s]" % label
    if marker in out and secret not in out:
        print("REDACT_OK label=%s" % label)
    else:
        print("REDACT_FAIL label=%s out=%r" % (label, out))
        ok = False
    got = scan(secret)
    if got == label:
        print("SCAN_OK label=%s" % label)
    else:
        print("SCAN_FAIL label=%s got=%s" % (label, got))
        ok = False
sys.exit(0 if ok else 1)
PY

REDACT_OUT="$(python3 "$SANDBOX/harness.py" "$SANDBOX/stage1.py" "$FIXDIR/consent-escalated.json" "$FIXDIR/secrets.tsv" 2>&1)"
REDACT_RC=$?
printf '%s\n' "$REDACT_OUT"
assert_eq "redaction_harness_rc=0" "0" "$REDACT_RC"
assert_match "redaction_pattern_labels_pin" "PATTERN_LABELS_OK count=9" "$REDACT_OUT"
while IFS="$(printf '\t')" read -r label secret; do
  [ -z "$label" ] && continue
  assert_match "redaction_marker [$label]" "REDACT_OK label=$label" "$REDACT_OUT"
done < "$FIXDIR/secrets.tsv"

# ---- Final invariants: gh never invoked; real .supervisor untouched -------------
echo ""
echo "==== Final invariants ===="
if [ -e "$GH_MARKER" ]; then
  echo "FAIL  gh_never_invoked  shim marker present:"
  cat "$GH_MARKER"
  FAIL_COUNT=$((FAIL_COUNT + 1))
else
  echo "PASS  gh_never_invoked"
  PASS_COUNT=$((PASS_COUNT + 1))
fi

REAL_AFTER="$(snapshot_real)"
assert_eq "real_supervisor_untouched" "$REAL_BEFORE" "$REAL_AFTER"

# ---- Summary --------------------------------------------------------------------
TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo ""
echo "=========================================="
echo "RESULT  total=$TOTAL  passed=$PASS_COUNT  failed=$FAIL_COUNT"
echo "=========================================="

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
