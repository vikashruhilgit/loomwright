#!/usr/bin/env bash
# test-resolve-egress-config.sh — direct unit tests for resolve-egress-config.sh
#
# red-team-hardening item 02: consent + webhook destination now resolve
# through ~/.claude/loomwright/egress.json, keyed by repo slug — a
# repo-relative file (.supervisor/telemetry-consent.json,
# .supervisor/config.json's webhook_url) can only ever REQUEST. This harness
# tests the resolver script directly: repo-slug derivation (origin normalized
# / local: fallback / not-a-git-repo), user-scope-only sourcing, fail-closed
# behaviour on an unreadable/malformed user-scope file, env-var precedence,
# and the REPO_REQUESTED_* informational fields.
#
# ISOLATION: every case runs with $HOME pointed at a fresh mktemp fixture
# (the test-session-probe.sh pattern this repo already established) so this
# harness never reads/writes the real operator's egress.json.
#
# EXIT: 0 on full pass, 1 on any failure.

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/resolve-egress-config.sh"

if [ ! -f "$RESOLVER" ]; then
  echo "FATAL  resolve-egress-config.sh not found: $RESOLVER" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "FATAL  jq required to run these self-tests" >&2
  exit 1
fi
if ! command -v git >/dev/null 2>&1; then
  echo "FATAL  git required to run these self-tests" >&2
  exit 1
fi

# Ambient env vars must never leak into a "should resolve empty" assertion.
unset LOOMWRIGHT_TELEMETRY_REPO 2>/dev/null || true
unset LOOMWRIGHT_WEBHOOK_URL 2>/dev/null || true

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS  $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL  $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then pass "$label"; else fail "$label  expected='$expected' actual='$actual'"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

SLUG="resolver-owner/resolver-repo"

# get_field <resolver_output> <key>
get_field() {
  printf '%s' "$1" | sed -nE "s/^$2=(.*)\$/\1/p" | head -n1
}

user_scope_write() { # $1=homedir $2=json fragment for repos.<SLUG>
  local homedir="$1" frag="$2"
  mkdir -p "$homedir/.claude/loomwright"
  python3 -c '
import json, sys
frag = json.loads(sys.argv[1])
doc = {"schema_version": 1, "repos": {sys.argv[2]: frag}}
open(sys.argv[3], "w").write(json.dumps(doc))
' "$frag" "$SLUG" "$homedir/.claude/loomwright/egress.json"
}

new_repo() { # $1=dir, $2=origin url or empty for no-origin
  mkdir -p "$1/.supervisor"
  git -C "$1" init -q
  if [ -n "${2:-}" ]; then
    git -C "$1" remote add origin "$2"
  fi
}

echo "==== Group 1: repo-slug derivation ===="

R1="$TMP/repo1"; H1="$TMP/home1"; mkdir -p "$H1"
new_repo "$R1" "https://github.com/${SLUG}.git"
OUT="$( ( cd "$R1" && HOME="$H1" bash "$RESOLVER" ) )"
assert_eq "https_origin_normalized" "$SLUG" "$(get_field "$OUT" REPO_SLUG)"

R1b="$TMP/repo1b"; H1b="$TMP/home1b"; mkdir -p "$H1b"
new_repo "$R1b" "git@github.com:${SLUG}.git"
OUT="$( ( cd "$R1b" && HOME="$H1b" bash "$RESOLVER" ) )"
assert_eq "ssh_shorthand_origin_normalized" "$SLUG" "$(get_field "$OUT" REPO_SLUG)"

R1c="$TMP/repo1c"; H1c="$TMP/home1c"; mkdir -p "$H1c"
new_repo "$R1c" "ssh://git@github.com/${SLUG}.git"
OUT="$( ( cd "$R1c" && HOME="$H1c" bash "$RESOLVER" ) )"
assert_eq "ssh_url_origin_normalized" "$SLUG" "$(get_field "$OUT" REPO_SLUG)"

R2="$TMP/repo2"; H2="$TMP/home2"; mkdir -p "$H2"
new_repo "$R2" ""
OUT="$( ( cd "$R2" && HOME="$H2" bash "$RESOLVER" ) )"
assert_eq "no_origin_falls_back_to_local_prefix" "local:$(basename "$R2")" "$(get_field "$OUT" REPO_SLUG)"

R3="$TMP/repo3"; H3="$TMP/home3"; mkdir -p "$H3"
new_repo "$R3" "not-a-valid-owner-repo-shape"
OUT="$( ( cd "$R3" && HOME="$H3" bash "$RESOLVER" ) )"
assert_eq "malformed_origin_falls_back_to_local_prefix" "local:$(basename "$R3")" "$(get_field "$OUT" REPO_SLUG)"

R4="$TMP/notgit"; H4="$TMP/home4"; mkdir -p "$R4" "$H4"
OUT="$( ( cd "$R4" && HOME="$H4" bash "$RESOLVER" ) )"
assert_eq "not_a_git_repo_slug_empty" "" "$(get_field "$OUT" REPO_SLUG)"
assert_eq "not_a_git_repo_rc=0" "0" "$?"

echo ""
echo "==== Group 2: user-scope is the SOLE source of TELEMETRY/TELEMETRY_REPO/WEBHOOK_URL ===="

RG="$TMP/repoG"; HG="$TMP/homeG"; mkdir -p "$HG"
new_repo "$RG" "https://github.com/${SLUG}.git"

# (a) no user-scope file at all -> everything empty.
OUT="$( ( cd "$RG" && HOME="$HG" bash "$RESOLVER" ) )"
assert_eq "no_user_scope_telemetry_empty" "" "$(get_field "$OUT" TELEMETRY)"
assert_eq "no_user_scope_telemetry_repo_empty" "" "$(get_field "$OUT" TELEMETRY_REPO)"
assert_eq "no_user_scope_webhook_empty" "" "$(get_field "$OUT" WEBHOOK_URL)"
RC="$?"
assert_eq "no_user_scope_exit=0" "0" "$RC"

# (b) matching entry -> values come through verbatim.
user_scope_write "$HG" '{"telemetry":"always_allow","telemetry_repo":"example/repo","webhook_url":"https://example.invalid/hook"}'
OUT="$( ( cd "$RG" && HOME="$HG" bash "$RESOLVER" ) )"
assert_eq "user_scope_telemetry" "always_allow" "$(get_field "$OUT" TELEMETRY)"
assert_eq "user_scope_telemetry_repo" "example/repo" "$(get_field "$OUT" TELEMETRY_REPO)"
assert_eq "user_scope_webhook_url" "https://example.invalid/hook" "$(get_field "$OUT" WEBHOOK_URL)"
EXPECT_SHA="$(printf '%s' "https://example.invalid/hook" | { command -v shasum >/dev/null 2>&1 && shasum -a 256 || sha256sum; } | awk '{print $1}')"
assert_eq "user_scope_webhook_url_sha256" "$EXPECT_SHA" "$(get_field "$OUT" WEBHOOK_URL_SHA256)"

# (c) malformed user-scope file -> fail CLOSED, everything empty, exit 0.
printf 'not valid json at all' > "$HG/.claude/loomwright/egress.json"
OUT="$( ( cd "$RG" && HOME="$HG" bash "$RESOLVER" ) )"
RC="$?"
assert_eq "malformed_user_scope_exit=0" "0" "$RC"
assert_eq "malformed_user_scope_telemetry_empty" "" "$(get_field "$OUT" TELEMETRY)"
assert_eq "malformed_user_scope_telemetry_repo_empty" "" "$(get_field "$OUT" TELEMETRY_REPO)"
assert_eq "malformed_user_scope_webhook_empty" "" "$(get_field "$OUT" WEBHOOK_URL)"

# (d) unreadable user-scope file -> fail CLOSED (skip under a UID that can
#     still read 000 files, e.g. root, per the same guard test-webhook.sh uses).
user_scope_write "$HG" '{"telemetry":"always_allow","telemetry_repo":"example/repo"}'
chmod 000 "$HG/.claude/loomwright/egress.json"
if [ -r "$HG/.claude/loomwright/egress.json" ]; then
  echo "SKIP  unreadable_user_scope_fails_closed (platform reports 000 file readable, e.g. root)"
else
  OUT="$( ( cd "$RG" && HOME="$HG" bash "$RESOLVER" ) )"
  assert_eq "unreadable_user_scope_telemetry_empty" "" "$(get_field "$OUT" TELEMETRY)"
fi
chmod 644 "$HG/.claude/loomwright/egress.json" 2>/dev/null || true

# (e) entry present for a DIFFERENT slug -> this repo's values stay empty.
user_scope_write "$HG" '{"telemetry":"always_allow","telemetry_repo":"example/repo"}'
python3 -c '
import json
p = "'"$HG"'/.claude/loomwright/egress.json"
d = json.load(open(p))
d["repos"]["some-other/repo"] = d["repos"].pop("'"$SLUG"'")
open(p, "w").write(json.dumps(d))
'
OUT="$( ( cd "$RG" && HOME="$HG" bash "$RESOLVER" ) )"
assert_eq "wrong_slug_telemetry_empty" "" "$(get_field "$OUT" TELEMETRY)"

# (f) non-string field types (defence in depth — nullable/missing-key lesson).
user_scope_write "$HG" '{"telemetry": 42, "telemetry_repo": null, "webhook_url": ["a"]}'
OUT="$( ( cd "$RG" && HOME="$HG" bash "$RESOLVER" ) )"
assert_eq "nonstring_telemetry_empty" "" "$(get_field "$OUT" TELEMETRY)"
assert_eq "null_telemetry_repo_empty" "" "$(get_field "$OUT" TELEMETRY_REPO)"
assert_eq "array_webhook_url_empty" "" "$(get_field "$OUT" WEBHOOK_URL)"

echo ""
echo "==== Group 3: repo-relative REQUESTS are informational only ===="

RR="$TMP/repoR"; HR="$TMP/homeR"; mkdir -p "$HR"
new_repo "$RR" "https://github.com/${SLUG}.git"
printf '{"telemetry":"always_allow","telemetry_repo":"attacker/sink"}' > "$RR/.supervisor/telemetry-consent.json"
printf '{"webhook_url":"https://attacker.example/hook"}' > "$RR/.supervisor/config.json"

# (a) empty user scope -> repo request is printed informationally, but
#     TELEMETRY/TELEMETRY_REPO/WEBHOOK_URL stay empty (never fed from it).
OUT="$( ( cd "$RR" && HOME="$HR" bash "$RESOLVER" ) )"
assert_eq "repro_telemetry_empty" "" "$(get_field "$OUT" TELEMETRY)"
assert_eq "repro_telemetry_repo_empty" "" "$(get_field "$OUT" TELEMETRY_REPO)"
assert_eq "repro_webhook_url_empty" "" "$(get_field "$OUT" WEBHOOK_URL)"
assert_eq "repro_repo_requested_telemetry_repo" "attacker/sink" "$(get_field "$OUT" REPO_REQUESTED_TELEMETRY_REPO)"
assert_eq "repro_repo_requested_webhook_url" "https://attacker.example/hook" "$(get_field "$OUT" REPO_REQUESTED_WEBHOOK_URL)"

# (b) legacy notify-config.json fallback (same precedence send-webhook.sh has
#     always used) still feeds REPO_REQUESTED_WEBHOOK_URL when the new path
#     is absent.
RR2="$TMP/repoR2"; HR2="$TMP/homeR2"; mkdir -p "$HR2"
new_repo "$RR2" "https://github.com/${SLUG}.git"
printf '{"webhook_url":"https://legacy.example/hook"}' > "$RR2/.supervisor/notify-config.json"
OUT="$( ( cd "$RR2" && HOME="$HR2" bash "$RESOLVER" ) )"
assert_eq "legacy_notify_config_requested" "https://legacy.example/hook" "$(get_field "$OUT" REPO_REQUESTED_WEBHOOK_URL)"

# (c) new config.json wins over legacy when both present (same precedence).
printf '{"webhook_url":"https://new.example/hook"}' > "$RR2/.supervisor/config.json"
OUT="$( ( cd "$RR2" && HOME="$HR2" bash "$RESOLVER" ) )"
assert_eq "new_config_wins_over_legacy_requested" "https://new.example/hook" "$(get_field "$OUT" REPO_REQUESTED_WEBHOOK_URL)"

# (d) malformed repo-relative file -> informational fields stay empty (fail closed).
RR3="$TMP/repoR3"; HR3="$TMP/homeR3"; mkdir -p "$HR3"
new_repo "$RR3" "https://github.com/${SLUG}.git"
printf 'not valid json' > "$RR3/.supervisor/telemetry-consent.json"
OUT="$( ( cd "$RR3" && HOME="$HR3" bash "$RESOLVER" ) )"
assert_eq "malformed_repo_relative_requested_empty" "" "$(get_field "$OUT" REPO_REQUESTED_TELEMETRY_REPO)"

echo ""
echo "==== Group 4: process-env overrides (highest precedence for VALUES only) ===="

RE="$TMP/repoE"; HE="$TMP/homeE"; mkdir -p "$HE"
new_repo "$RE" "https://github.com/${SLUG}.git"
user_scope_write "$HE" '{"telemetry":"always_allow","telemetry_repo":"user-scope/repo","webhook_url":"https://user-scope.example/hook"}'

OUT="$( ( cd "$RE" && HOME="$HE" LOOMWRIGHT_TELEMETRY_REPO="env-owner/env-repo" LOOMWRIGHT_WEBHOOK_URL="https://env.example/hook" bash "$RESOLVER" ) )"
assert_eq "env_telemetry_repo_wins" "env-owner/env-repo" "$(get_field "$OUT" TELEMETRY_REPO)"
assert_eq "env_webhook_url_wins" "https://env.example/hook" "$(get_field "$OUT" WEBHOOK_URL)"
assert_eq "env_never_grants_consent_itself" "always_allow" "$(get_field "$OUT" TELEMETRY)"

# env override with NO user-scope entry at all: repo/URL resolve from env, but
# TELEMETRY (consent) stays empty — env can supply a target, never a grant.
RE2="$TMP/repoE2"; HE2="$TMP/homeE2"; mkdir -p "$HE2"
new_repo "$RE2" "https://github.com/${SLUG}.git"
OUT="$( ( cd "$RE2" && HOME="$HE2" LOOMWRIGHT_TELEMETRY_REPO="env-owner/env-repo" bash "$RESOLVER" ) )"
assert_eq "env_repo_without_user_scope_still_resolves" "env-owner/env-repo" "$(get_field "$OUT" TELEMETRY_REPO)"
assert_eq "env_repo_without_user_scope_consent_stays_empty" "" "$(get_field "$OUT" TELEMETRY)"

echo ""
echo "==== Group 5: always exits 0 (fail-safe emitter contract) ===="
# Unreadable HOME entirely (points at a file, not a dir) must not crash.
RF="$TMP/repoF"; HF="$TMP/home-is-a-file"; mkdir -p "$RF"
new_repo "$RF" "https://github.com/${SLUG}.git"
: > "$HF"
OUT="$( ( cd "$RF" && HOME="$HF" bash "$RESOLVER" ) )"
RC="$?"
assert_eq "unreadable_home_path_exit=0" "0" "$RC"

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo "=========================================="
echo "RESULT  total=$TOTAL  passed=$PASS_COUNT  failed=$FAIL_COUNT"
echo "=========================================="
if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
