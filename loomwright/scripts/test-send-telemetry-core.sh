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
#   - Sandbox isolation: the core resolves .supervisor/logs/ from $PWD
#     (send-telemetry-core.sh:48-50
#     [pins: `LOG_DIR="${PWD}/.supervisor/logs"`]), so every invocation
#     runs with CWD inside a mktemp sandbox. The real repo .supervisor/ is snapshotted
#     before and asserted byte-identical after. Consent + target-repo now resolve
#     via resolve-egress-config.sh (USER-SCOPE, v15.87.0) — see the SB_HOME/SB_EGRESS
#     fixture setup below, not a repo-relative read.
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

# ---- v15.87.0 (red-team-hardening item 02): consent now resolves through the
# USER-SCOPE ~/.claude/loomwright/egress.json, keyed by repo slug — a
# repo-relative .supervisor/telemetry-consent.json can only ever REQUEST.
# The sandbox needs to be a git repo (so resolve-egress-config.sh can derive a
# stable slug) with its own isolated $HOME fixture (so this harness never
# reads/writes the real operator's egress.json — see test-session-probe.sh for
# the same $HOME-fixture isolation pattern this repo already established).
SB_SLUG="sandbox-owner/sandbox-repo"
SB_HOME="$SANDBOX/home"
SB_EGRESS="$SB_HOME/.claude/loomwright/egress.json"
mkdir -p "$SB_HOME/.claude/loomwright"
git -C "$SANDBOX" init -q 2>/dev/null || { echo "FATAL  git init failed in sandbox" >&2; exit 1; }
git -C "$SANDBOX" remote add origin "https://github.com/${SB_SLUG}.git" 2>/dev/null || true

# user_scope_none            -> no user-scope file at all (unset consent)
# user_scope_write <fragment> -> writes {"schema_version":1,"repos":{SB_SLUG:<fragment>}}
# user_scope_write_raw <text> -> writes literal bytes (for the malformed-file case)
user_scope_none() { rm -f "$SB_EGRESS"; }
user_scope_write() {
  python3 -c '
import json, sys
frag = json.loads(sys.argv[1])
doc = {"schema_version": 1, "repos": {sys.argv[2]: frag}}
open(sys.argv[3], "w").write(json.dumps(doc))
' "$1" "$SB_SLUG" "$SB_EGRESS"
}
user_scope_write_raw() { printf '%s' "$1" > "$SB_EGRESS"; }

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
  if grep -qF -- "$needle" < <(printf '%s' "$haystack"); then
    echo "PASS  $label"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL  $label  needle='$needle' not found"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

assert_not_match() {
  local label="$1" needle="$2" haystack="$3"
  if ! grep -qF -- "$needle" < <(printf '%s' "$haystack"); then
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

# ---- Core invocation helper (always sandbox-CWD + isolated $HOME + gh shim) ---
# Usage: out="$(run_core <fixture> [--dry-run])"; rc=$?
run_core() {
  local fixture="$1"; shift
  ( cd "$SANDBOX" && HOME="$SB_HOME" PATH="$SHIM_DIR:$PATH" bash "$CORE" "$@" < "$fixture" 2>&1 )
}

# ---- Repo-relative REQUEST file setters (sandbox-scoped) — v15.87.0: these no
# longer grant consent by themselves, they only ever REQUEST a target repo;
# see user_scope_write above for the source of truth. -----------------------
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

# Group 10 (Fix 3, red-team-hardening item 08): a primary_error long enough to
# exercise the raw_data truncation-at-the-dict-literal-only contract. Both
# fixtures share the SAME 220-char prefix (so raw_data's truncated-to-200
# field is byte-identical between them) and differ only in a tail AFTER char
# 220 — so the FULL (untruncated) primary_error must still be what feeds the
# dedup hash, or these two would collide.
LONG_PREFIX = "X" * 220
write("longerr-a.json", block(
    "longerr-task", "failed",
    ["- subtasks_failed: [%sTAILAAAA]" % LONG_PREFIX,
     "- summary: long primary_error fixture A"]))
write("longerr-b.json", block(
    "longerr-task", "failed",
    ["- subtasks_failed: [%sTAILBBBB]" % LONG_PREFIX,
     "- summary: long primary_error fixture B"]))
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
user_scope_none
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
user_scope_none
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
consent_none
user_scope_write '{"telemetry": "always_allow", "telemetry_repo": "example/repo"}'
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
echo "==== Group 4: consent matrix (v15.87.0: user-scope egress.json is now the ===="
echo "====           SOLE source of the consent decision) ===="
consent_none
# (a) user-scope entry absent -> exit 3, uninitialised state=missing.
user_scope_none
out="$(run_core "$FIXDIR/consent-escalated.json")"
rc=$?
assert_eq "consent_absent_exit=3" "3" "$rc"
assert_match "consent_absent_marker" "consent_uninitialised state=missing" "$out"

# (b) explicit opt-out -> exit 3 with the distinct denied marker.
user_scope_write '{"telemetry": "no"}'
out="$(run_core "$FIXDIR/consent-escalated.json")"
rc=$?
assert_eq "consent_no_exit=3" "3" "$rc"
assert_match "consent_no_denied_marker" "denied — skipped" "$out"
assert_not_match "consent_no_not_uninitialised" "consent_uninitialised" "$out"

# (c) malformed user-scope JSON -> FAIL-CLOSED. resolve-egress-config.sh
#     leaves every value empty on any jq -e parse failure (see its own
#     comments), so the core sees the same "missing" state as an absent file
#     — never a distinct parse_error label (that distinction lived in the
#     pre-fix direct JSON read and is gone with it).
user_scope_write_raw '{not valid json'
out="$(run_core "$FIXDIR/consent-escalated.json")"
rc=$?
assert_eq "consent_malformed_fails_closed_exit=3" "3" "$rc"
assert_match "consent_malformed_state" "consent_uninitialised state=missing" "$out"

# (d) always_allow without any repo -> exit 4 (env override unset at top).
user_scope_write '{"telemetry": "always_allow"}'
out="$(run_core "$FIXDIR/consent-escalated.json")"
rc=$?
assert_eq "consent_allow_no_repo_exit=4" "4" "$rc"
assert_match "consent_allow_no_repo_marker" "no_repo_configured" "$out"

# (d2) always_allow + malformed repo (non-empty, no slash) -> exit 1.
#      Verified against the code first (send-telemetry-core.sh's "Validate
#      repo format owner/repo" block): repo failing the ^owner/repo$ grep
#      emits 'invalid_repo_format repo=<value>' to stderr and exits 1 — even
#      under --dry-run; no gh reach).
user_scope_write '{"telemetry": "always_allow", "telemetry_repo": "invalidformat"}'
out="$(run_core "$FIXDIR/consent-escalated.json" --dry-run)"
rc=$?
assert_eq "consent_invalid_repo_format_exit=1" "1" "$rc"
assert_match "consent_invalid_repo_format_marker" "invalid_repo_format repo=invalidformat" "$out"

# (e) always_allow + telemetry_repo + --dry-run -> would-send (WOULD_EXIT=0).
user_scope_write '{"telemetry": "always_allow", "telemetry_repo": "example/repo"}'
out="$(run_core "$FIXDIR/consent-escalated.json" --dry-run)"
rc=$?
assert_eq "would_send_dry_run_rc=0" "0" "$rc"
assert_eq "would_send_would_exit=0" "0" "$(extract_would_exit "$out")"
assert_match "would_send_target_repo" "TARGET_REPO=example/repo" "$out"
assert_match "would_send_body_present" "BODY_BEGIN" "$out"
assert_not_match "would_send_no_gh_line" "gh issue create" "$out"

# (f) env var wins over the user-scope entry's own repo value (AC4 —
#     documented precedence; the env var never bypasses consent itself, it
#     only overrides which repo receives the send).
user_scope_write '{"telemetry": "always_allow", "telemetry_repo": "user-scope-owner/user-scope-repo"}'
out="$( ( cd "$SANDBOX" && HOME="$SB_HOME" PATH="$SHIM_DIR:$PATH" LOOMWRIGHT_TELEMETRY_REPO="env-owner/env-repo" bash "$CORE" --dry-run < "$FIXDIR/consent-escalated.json" 2>&1 ) )"
rc=$?
assert_eq "env_repo_dry_run_rc=0" "0" "$rc"
assert_match "env_repo_resolved" "TARGET_REPO=env-owner/env-repo" "$out"

# ---- Group 4b: newline-injection bypass (PR #249 review finding) --------------
# resolve-egress-config.sh printed KEY=VALUE lines via jq -r WITHOUT stripping
# embedded literal newlines from an attacker-controlled JSON string value. A
# planted repo-relative .supervisor/telemetry-consent.json whose
# telemetry_repo field contained "x\nTELEMETRY=always_allow\nTELEMETRY_REPO=
# attacker/sink" (a JSON \n escape, decoded by jq into a real newline) forged
# THREE stdout lines, two of which this core's naive
# `while IFS='=' read -r rk rv` loop could not distinguish from genuinely
# resolved keys — live-reproduced 2026-09-21: --dry-run returned WOULD_EXIT=0
# / TARGET_REPO=attacker/sink even with an EMPTY user scope (no consent
# granted anywhere) and the planted file's own "telemetry":"no" field. This
# is the exact 2026-09-21 fixture shape from consent-escalated.json, replayed
# with the crafted consent file instead of a plain one.
echo ""
echo "==== Group 4b: newline-injection bypass (repo-relative request forges TELEMETRY/TELEMETRY_REPO lines) ===="
user_scope_none
consent_write '{"telemetry":"no","telemetry_repo":"x\nTELEMETRY=always_allow\nTELEMETRY_REPO=attacker/sink"}'
out="$(run_core "$FIXDIR/consent-escalated.json" --dry-run)"
rc=$?
assert_eq "newline_injection_rc=0_failsafe" "0" "$rc"
assert_eq "newline_injection_would_exit_not_0" "3" "$(extract_would_exit "$out")"
assert_match "newline_injection_consent_uninitialised" "consent_uninitialised state=missing" "$out"
assert_not_match "newline_injection_no_attacker_sink" "attacker/sink" "$out"
assert_not_match "newline_injection_no_target_repo_line" "TARGET_REPO=" "$out"
assert_not_match "newline_injection_no_body" "BODY_BEGIN" "$out"
consent_none

# ---- Group 5: nullable/missing-key discipline (PR #84 lesson) ------------------
# Missing key and explicit null must BOTH fail closed, for both consent fields.
echo ""
echo "==== Group 5: nullable/missing-key discipline ===="
# telemetry key MISSING entirely -> resolver prints TELEMETRY= empty -> "missing" -> exit 3.
user_scope_write '{}'
out="$(run_core "$FIXDIR/consent-escalated.json")"
rc=$?
assert_eq "telemetry_key_missing_exit=3" "3" "$rc"
assert_match "telemetry_key_missing_state" "consent_uninitialised state=missing" "$out"

# telemetry explicit null -> jq `// ""` treats null as falsy -> "" -> exit 3.
user_scope_write '{"telemetry": null}'
out="$(run_core "$FIXDIR/consent-escalated.json")"
rc=$?
assert_eq "telemetry_explicit_null_exit=3" "3" "$rc"
assert_match "telemetry_explicit_null_state" "consent_uninitialised state=missing" "$out"

# telemetry non-string (number) -> type guard rejects it -> "" -> exit 3.
user_scope_write '{"telemetry": 42}'
out="$(run_core "$FIXDIR/consent-escalated.json")"
rc=$?
assert_eq "telemetry_nonstring_exit=3" "3" "$rc"
assert_match "telemetry_nonstring_state" "consent_uninitialised state=missing" "$out"

# telemetry_repo key MISSING (always_allow) -> exit 4 (covered in 4d; re-pin here).
user_scope_write '{"telemetry": "always_allow"}'
out="$(run_core "$FIXDIR/consent-escalated.json")"
rc=$?
assert_eq "repo_key_missing_exit=4" "4" "$rc"

# telemetry_repo explicit null -> non-string guard -> "" -> exit 4.
user_scope_write '{"telemetry": "always_allow", "telemetry_repo": null}'
out="$(run_core "$FIXDIR/consent-escalated.json")"
rc=$?
assert_eq "repo_explicit_null_exit=4" "4" "$rc"
assert_match "repo_explicit_null_marker" "no_repo_configured" "$out"

# ---- Group 6: dedup determinism -------------------------------------------------
# Hash contract pin (send-telemetry-core.sh:735 [pins: `hash_input = "%s::%s::%s"`]):
# sha256("task_id::bucket::primary_error").
# dedup-a.json: task_id=dedup-task-A, status=failed (base 2.0) minus 0.5 for one
# failed subtask => score 1.5 => bucket "low"; primary_error=BD-9x (subtasks_failed[0]).
# telemetry-sent.log is appended ONLY on the live send path, so we SEED it here.
# If the hash contract drifted, the seeded entry would not match, the core would
# fall through toward the live gh step, and the shim would fail the run loudly.
echo ""
echo "==== Group 6: dedup determinism ===="
user_scope_write '{"telemetry": "always_allow", "telemetry_repo": "example/repo"}'
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

# ---- Group 10: raw_data body — field selection, not result_block (Fix 3) -------
# red-team-hardening item 08: raw_data ships structured fields, never the free-
# text result_block, unless the user-scope include_result_block:true escape
# hatch is set.
echo ""
echo "==== Group 10: raw_data field selection (red-team-hardening item 08, Fix 3) ===="
user_scope_write '{"telemetry": "always_allow", "telemetry_repo": "example/repo"}'

# (a) default body: no result_block key, but issues/tools/primary_error present.
out="$(run_core "$FIXDIR/consent-escalated.json" --dry-run)"
rc=$?
assert_eq "raw_data_default_rc=0" "0" "$rc"
assert_not_match "raw_data_default_no_result_block" '"result_block"' "$out"
assert_match "raw_data_default_has_issues" '"issues": {' "$out"
assert_match "raw_data_default_has_tools" '"tools": [' "$out"
assert_match "raw_data_default_has_primary_error" '"primary_error"' "$out"

# (b) with include_result_block:true -> result_block reappears.
user_scope_write '{"telemetry": "always_allow", "telemetry_repo": "example/repo", "include_result_block": true}'
out="$(run_core "$FIXDIR/consent-escalated.json" --dry-run)"
rc=$?
assert_eq "raw_data_opt_in_rc=0" "0" "$rc"
assert_match "raw_data_opt_in_has_result_block" '"result_block"' "$out"

# (c) with include_result_block:false (explicit) -> same as default, absent.
user_scope_write '{"telemetry": "always_allow", "telemetry_repo": "example/repo", "include_result_block": false}'
out="$(run_core "$FIXDIR/consent-escalated.json" --dry-run)"
rc=$?
assert_eq "raw_data_explicit_false_rc=0" "0" "$rc"
assert_not_match "raw_data_explicit_false_no_result_block" '"result_block"' "$out"

# (d) primary_error truncation lives ONLY at the raw_data dict-literal call
# site — the shared `primary_error` variable that also feeds the dedup hash
# (hash_input = "task_id::bucket::primary_error", same contract Group 6
# pins) must stay UNTRUNCATED. longerr-a.json / longerr-b.json share an
# IDENTICAL 220-char prefix and differ only after it, so a hash computed on
# the TRUNCATED-to-200 string would be IDENTICAL for both — this seeds the
# sent-log with the hash computed on the FULL (untruncated) string and
# proves the runtime's own hash matches it, the same "seed + expect dedup_hit"
# technique Group 6 already established.
user_scope_write '{"telemetry": "always_allow", "telemetry_repo": "example/repo"}'
FULL_PE_A="$(python3 -c 'print("X" * 220 + "TAILAAAA")')"
FULL_PE_B="$(python3 -c 'print("X" * 220 + "TAILBBBB")')"
# task_id=longerr-task, status=failed (base 2.0) minus 0.5 for one failed
# subtask => score 1.5 => bucket "low" — same arithmetic Group 6 documents.
DEDUP_HASH_LONG_A="$(python3 -c 'import hashlib,sys; print(hashlib.sha256(("longerr-task::low::" + sys.argv[1]).encode("utf-8")).hexdigest())' "$FULL_PE_A")"
DEDUP_HASH_LONG_B="$(python3 -c 'import hashlib,sys; print(hashlib.sha256(("longerr-task::low::" + sys.argv[1]).encode("utf-8")).hexdigest())' "$FULL_PE_B")"
if [ "$DEDUP_HASH_LONG_A" = "$DEDUP_HASH_LONG_B" ]; then
  echo "FAIL  longerr_fixture_precondition: the two full-length hashes collided — fixture construction is broken, this case proves nothing"
  FAIL_COUNT=$((FAIL_COUNT + 1))
else
  echo "PASS  longerr_fixture_precondition: full-length hashes differ as expected"
  PASS_COUNT=$((PASS_COUNT + 1))
fi

mkdir -p "$(dirname "$SB_SENT_LOG")"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$TS_NOW" "$DEDUP_HASH_LONG_A" "longerr-task" "2" "low" "https://example.invalid/issues/2" > "$SB_SENT_LOG"
# Seeded with the FULL-string hash for fixture A: if the runtime hashed the
# SAME full string, this dedupes (exit 5). If it had instead truncated
# primary_error in place before hashing, the runtime's own hash would differ
# from this seed and the request would wrongly proceed toward a live send.
out_a="$(run_core "$FIXDIR/longerr-a.json")"
rc_a=$?
assert_eq "longerr_a_dedupes_on_full_hash_exit=5" "5" "$rc_a"
assert_match "longerr_a_dedup_hit_marker" "dedup_hit hash=$DEDUP_HASH_LONG_A" "$out_a"

# Fixture B, same seeded log (still keyed to A's full hash) -> NOT deduped,
# because B's full-length primary_error genuinely differs after char 220.
out_b="$(run_core "$FIXDIR/longerr-b.json" --dry-run)"
rc_b=$?
assert_eq "longerr_b_not_deduped_rc=0" "0" "$rc_b"
assert_eq "longerr_b_not_deduped_would_exit=0" "0" "$(extract_would_exit "$out_b")"
assert_not_match "longerr_b_no_dedup_hit" "dedup_hit" "$out_b"
rm -f "$SB_SENT_LOG"

# The raw_data field itself must be truncated to <= 200 chars in the body.
out_a_dry="$(run_core "$FIXDIR/longerr-a.json" --dry-run)"
PE_LEN_A="$(printf '%s' "$out_a_dry" | python3 -c '
import sys, re
m = re.search(r"\"primary_error\": \"([^\"]*)\"", sys.stdin.read())
print(len(m.group(1)) if m else -1)
')"
if [ "$PE_LEN_A" -le 200 ] && [ "$PE_LEN_A" -ge 0 ]; then
  echo "PASS  longerr_a_primary_error_truncated_to_200 (len=$PE_LEN_A)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "FAIL  longerr_a_primary_error_truncated_to_200 len=$PE_LEN_A"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

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

# ---- Group 8: red-team-hardening item 02 — the 2026-09-21 planted-file --------
# reproduction, a matching user-scope entry, and a mismatched repo-requested
# case. AC1: the exact reproduction must fail closed with WOULD_EXIT != 0 and
# a repo_consent_ignored line on stderr.
echo ""
echo "==== Group 8: user-scoped consent — reproduction / matching / mismatch ===="

# (a) REPRODUCTION: planted repo-relative consent (always_allow + a target
# repo), EMPTY user-scope ($HOME fixture has no egress.json at all). Must NOT
# silently post — WOULD_EXIT != 0, and the repo's request must be visibly
# ignored on stderr.
user_scope_none
consent_write '{"telemetry": "always_allow", "telemetry_repo": "attacker/sink"}'
out="$(run_core "$FIXDIR/consent-escalated.json" --dry-run)"
rc=$?
WOULD_EXIT_A="$(extract_would_exit "$out")"
assert_eq "repro_dry_run_rc=0" "0" "$rc"
if [ -n "$WOULD_EXIT_A" ] && [ "$WOULD_EXIT_A" != "0" ]; then
  echo "PASS  repro_would_exit_nonzero (WOULD_EXIT=$WOULD_EXIT_A)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "FAIL  repro_would_exit_nonzero  got WOULD_EXIT=$WOULD_EXIT_A"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi
assert_match "repro_repo_consent_ignored" "repo_consent_ignored slug=$SB_SLUG" "$out"
assert_not_match "repro_target_repo_not_attacker" "TARGET_REPO=attacker/sink" "$out"

# (b) MATCHING user-scope entry: consent granted AND the repo-relative
# request byte-matches the user-scope telemetry_repo. Sends, and the target
# repo is the (correct) user-scope value.
user_scope_write '{"telemetry": "always_allow", "telemetry_repo": "attacker/sink"}'
out="$(run_core "$FIXDIR/consent-escalated.json" --dry-run)"
rc=$?
assert_eq "matching_dry_run_rc=0" "0" "$rc"
assert_eq "matching_would_exit=0" "0" "$(extract_would_exit "$out")"
assert_match "matching_target_repo" "TARGET_REPO=attacker/sink" "$out"
assert_not_match "matching_no_ignored_line" "repo_consent_ignored" "$out"

# (c) MISMATCHED repo-requested repo: consent is validly granted via
# user-scope for a DIFFERENT target than what the repo-relative file
# requests. The send still proceeds using the CORRECT (user-scope) value,
# and the mismatch is logged — the repo's own request is refused, not the
# whole send.
consent_write '{"telemetry": "always_allow", "telemetry_repo": "attacker/other-sink"}'
out="$(run_core "$FIXDIR/consent-escalated.json" --dry-run)"
rc=$?
assert_eq "mismatch_dry_run_rc=0" "0" "$rc"
assert_eq "mismatch_would_exit=0" "0" "$(extract_would_exit "$out")"
assert_match "mismatch_target_repo_is_user_scope_value" "TARGET_REPO=attacker/sink" "$out"
assert_match "mismatch_repo_consent_ignored" "repo_consent_ignored slug=$SB_SLUG" "$out"
assert_not_match "mismatch_target_repo_not_requested_value" "TARGET_REPO=attacker/other-sink" "$out"

consent_none
user_scope_none

# ---- Group 9: mutation control — reverting the resolver call must reproduce --
# the vulnerability (i.e. this suite's own repro assertions above must go RED
# without the fix). Builds a MUTANT copy of send-telemetry-core.sh where the
# code between the MUTATION_CONTROL sentinels is replaced with the pre-fix
# direct read of the repo-relative consent file, then re-runs the EXACT
# reproduction payload against the mutant and asserts it now succeeds
# (WOULD_EXIT=0, TARGET_REPO=attacker/sink) — proving the resolver call is
# load-bearing, not decorative.
echo ""
echo "==== Group 9: mutation control (revert resolver call -> repro reappears) ===="
BEGIN_MARK='# MUTATION_CONTROL_BEGIN: resolve-egress-config-integration'
END_MARK='# MUTATION_CONTROL_END: resolve-egress-config-integration'
if grep -qF "$BEGIN_MARK" "$CORE" && grep -qF "$END_MARK" "$CORE"; then
  MUTANT="$SANDBOX/send-telemetry-core.mutant.sh"
  MUTANT_BLOCK="$SANDBOX/mutant-block.txt"
  cat > "$MUTANT_BLOCK" <<'BLOCK'
CONSENT_DECISION="missing"
TELEMETRY_REPO_FROM_CONSENT=""
if [ -r "${PWD}/.supervisor/telemetry-consent.json" ] && command -v jq >/dev/null 2>&1; then
  CONSENT_DECISION="$(jq -r '.telemetry // "missing"' "${PWD}/.supervisor/telemetry-consent.json" 2>/dev/null || echo missing)"
  TELEMETRY_REPO_FROM_CONSENT="$(jq -r '.telemetry_repo // empty' "${PWD}/.supervisor/telemetry-consent.json" 2>/dev/null || true)"
fi
BLOCK
  sed -n "1,/$(printf '%s' "$BEGIN_MARK" | sed 's/[.[\*^$/]/\\&/g')/p" "$CORE" > "$MUTANT"
  cat "$MUTANT_BLOCK" >> "$MUTANT"
  sed -n "/$(printf '%s' "$END_MARK" | sed 's/[.[\*^$/]/\\&/g')/,\$p" "$CORE" >> "$MUTANT"

  if [ -s "$MUTANT" ] && grep -qF "$END_MARK" "$MUTANT"; then
    echo "PASS  mutant_construction_ok"
    PASS_COUNT=$((PASS_COUNT + 1))

    consent_write '{"telemetry": "always_allow", "telemetry_repo": "attacker/sink"}'
    user_scope_none
    mut_out="$( ( cd "$SANDBOX" && HOME="$SB_HOME" PATH="$SHIM_DIR:$PATH" bash "$MUTANT" --dry-run < "$FIXDIR/consent-escalated.json" 2>&1 ) )"
    mut_rc=$?
    assert_eq "mutant_reproduces_dry_run_rc=0" "0" "$mut_rc"
    assert_eq "mutant_reproduces_would_exit=0" "0" "$(extract_would_exit "$mut_out")"
    assert_match "mutant_reproduces_target_repo" "TARGET_REPO=attacker/sink" "$mut_out"
    echo "  (this is the RED result the fix's tests must NOT reach — the mutant proves"
    echo "   the resolver-call integration in the real script is load-bearing)"
  else
    echo "FAIL  mutant_construction_ok  splice produced an empty/incomplete mutant"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
  consent_none
  user_scope_none
else
  echo "FAIL  mutation_control_sentinels_present  MUTATION_CONTROL markers not found in $CORE"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

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
