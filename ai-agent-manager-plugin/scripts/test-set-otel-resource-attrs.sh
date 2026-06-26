#!/usr/bin/env bash
# test-set-otel-resource-attrs.sh — self-tests for set-otel-resource-attrs.sh,
# the fail-safe, telemetry-gated SessionStart helper that labels a project's
# OTEL_RESOURCE_ATTRIBUTES (service.name=<repo-basename>, service.version=<plugin version>).
#
# Mirrors test-build-bridge.sh's convention: runs in isolated mktemp temp dirs
# (temp HOME + temp git repos + a fixture CLAUDE_PLUGIN_ROOT manifest), trap
# cleanup, NEVER touches the real ~/.claude or any real repo. The harness itself
# fails LOUD (exit 1 on any genuine assertion failure) — a CI gate, distinct from
# the runtime script's always-exit-0 fail-safe contract, which this very test
# asserts on every path.
#
# The runtime script runs under bash, so it is always invoked via `bash`.
#
# Exit 0 = all pass, 1 = any failure.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/set-otel-resource-attrs.sh"
JQ="$(command -v jq || true)"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

if [ -z "$JQ" ]; then echo "jq unavailable — cannot self-test"; exit 1; fi

# ---- shared fixtures --------------------------------------------------------
FIXTURE_VERSION="9.9.9-fixture"
PLUGIN_ROOT="$(mktemp -d)"
mkdir -p "$PLUGIN_ROOT/.claude-plugin"
printf '{"name":"fixture","version":"%s"}\n' "$FIXTURE_VERSION" > "$PLUGIN_ROOT/.claude-plugin/plugin.json"

# Track everything to clean up.
TMPS=("$PLUGIN_ROOT")
cleanup() { for d in "${TMPS[@]}"; do rm -rf "$d" 2>/dev/null; done; }
trap cleanup EXIT

# newhome [telemetry_on]  — temp HOME with ~/.claude/settings.json.
#   telemetry_on="1"  → settings.json with CLAUDE_CODE_ENABLE_TELEMETRY="1"
#   telemetry_on="0"  → settings.json WITHOUT the flag (telemetry off)
#   telemetry_on="absent" → no settings.json at all
newhome() {
  local mode="${1:-0}" h
  h="$(mktemp -d)"; TMPS+=("$h")
  mkdir -p "$h/.claude"
  case "$mode" in
    1) "$JQ" -n '{env:{CLAUDE_CODE_ENABLE_TELEMETRY:"1"}}' > "$h/.claude/settings.json" ;;
    0) "$JQ" -n '{env:{SOMETHING_ELSE:"x"}}' > "$h/.claude/settings.json" ;;
    absent) : ;;  # no settings.json
  esac
  printf '%s' "$h"
}

# newrepo [basename]  — temp git repo (optionally under a chosen basename dir).
newrepo() {
  local name="${1:-}" parent d
  parent="$(mktemp -d)"; TMPS+=("$parent")
  if [ -n "$name" ]; then
    d="$parent/$name"; mkdir -p "$d"
  else
    d="$parent"
  fi
  ( cd "$d" && git init -q && git config user.email t@t && git config user.name t \
      && echo seed > seed.txt && git add seed.txt && git commit -qm seed ) >/dev/null 2>&1
  printf '%s' "$d"
}

# run <repo> <home> [env-assignments...]  — invoke the runtime script from inside
# <repo> with HOME=<home> and CLAUDE_PLUGIN_ROOT=<fixture>. Echoes its exit code
# into RC. Extra leading "K=V" args are exported for the call.
RC=0
run() {
  local repo="$1" home="$2"; shift 2
  # `env -u CLAUDE_CODE_ENABLE_TELEMETRY` SCRUBS any inherited telemetry flag
  # from the developer's / CI's real environment so the telemetry-OFF fixtures
  # actually test the off path. Callers that exercise the env-only branch
  # re-add it as a trailing "CLAUDE_CODE_ENABLE_TELEMETRY=1" arg (applied AFTER
  # the -u removal by env's left-to-right semantics). Extra "K=V" args pass
  # straight through; "$@" is set -u-safe even when empty (unlike a named array).
  ( cd "$repo" && env -u CLAUDE_CODE_ENABLE_TELEMETRY \
      HOME="$home" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$@" \
      bash "$SCRIPT" ) >/dev/null 2>&1
  RC=$?
}

# read the written OTEL_RESOURCE_ATTRIBUTES (empty if file/key absent).
attrs_of() { "$JQ" -r '.env.OTEL_RESOURCE_ATTRIBUTES // empty' "$1/.claude/settings.local.json" 2>/dev/null; }

# stat perms portable (GNU -c %a / BSD -f %A).
perms_of() {
  if stat -c %a "$1" >/dev/null 2>&1; then stat -c %a "$1"; else stat -f %A "$1"; fi
}

# ============================================================================
echo "== 1. Telemetry OFF (no flag, env unset) ⇒ no-op, exit 0 =="
R="$(newrepo)"; H="$(newhome 0)"
run "$R" "$H"
[ "$RC" -eq 0 ] && ok "exit 0 when telemetry off" || no "non-zero exit telemetry off ($RC)"
[ ! -f "$R/.claude/settings.local.json" ] && ok "no settings.local.json written when telemetry off" || no "wrote settings.local.json with telemetry off"

echo "== 1b. Telemetry settings.json ABSENT + env unset ⇒ no-op, exit 0 =="
R="$(newrepo)"; H="$(newhome absent)"
run "$R" "$H"
[ "$RC" -eq 0 ] && ok "exit 0 when settings.json absent" || no "non-zero exit absent settings ($RC)"
[ ! -f "$R/.claude/settings.local.json" ] && ok "no write when settings.json absent + env unset" || no "wrote with absent settings + env unset"

echo "== 1c. HOME UNSET ⇒ fail-safe (exit 0); env-var branch still labels (set -u guard) =="
# Regression: bare \$HOME under `set -u` aborts with 'HOME: unbound variable'.
# The settings-file gate must be skipped when HOME is empty; the env-var branch
# must still work. (a) HOME unset + no telemetry flag ⇒ silent no-op exit 0.
R="$(newrepo homeoff)"
( cd "$R" && env -u HOME -u CLAUDE_CODE_ENABLE_TELEMETRY \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$SCRIPT" ) >/dev/null 2>&1; RC=$?
[ "$RC" -eq 0 ] && ok "exit 0 with HOME unset + telemetry off" || no "non-zero exit HOME-unset off ($RC)"
[ ! -f "$R/.claude/settings.local.json" ] && ok "no write with HOME unset + telemetry off" || no "wrote with HOME unset + off"
# (b) HOME unset + env-var telemetry ON ⇒ still labels, exit 0.
R="$(newrepo homeon)"
( cd "$R" && env -u HOME CLAUDE_CODE_ENABLE_TELEMETRY=1 \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$SCRIPT" ) >/dev/null 2>&1; RC=$?
[ "$RC" -eq 0 ] && ok "exit 0 with HOME unset + env telemetry on" || no "non-zero exit HOME-unset on ($RC)"
A="$(attrs_of "$R")"
[ "$A" = "service.name=homeon,service.version=${FIXTURE_VERSION}" ] \
  && ok "HOME-unset env-only branch still labels" || no "HOME-unset label wrong (got: [$A])"

echo "== 1d. Version fallback — unresolvable plugin.json ⇒ service.version=unknown, exit 0 =="
# CLAUDE_PLUGIN_ROOT points at a dir with no manifest; the script must still
# label service.name and fall back to 'unknown' (never error).
R="$(newrepo verfb)"; H="$(newhome 1)"; NOMANIFEST="$(mktemp -d)"; TMPS+=("$NOMANIFEST")
( cd "$R" && env -u CLAUDE_CODE_ENABLE_TELEMETRY \
    HOME="$H" CLAUDE_PLUGIN_ROOT="$NOMANIFEST" bash "$SCRIPT" ) >/dev/null 2>&1; RC=$?
[ "$RC" -eq 0 ] && ok "exit 0 with unresolvable plugin.json" || no "non-zero exit no-manifest ($RC)"
A="$(attrs_of "$R")"
[ "$A" = "service.name=verfb,service.version=unknown" ] \
  && ok "service.version falls back to 'unknown'" || no "version fallback wrong (got: [$A])"

echo "== 2. Telemetry ON via settings.json ⇒ writes labeled attrs =="
R="$(newrepo myproj)"; H="$(newhome 1)"
run "$R" "$H"
[ "$RC" -eq 0 ] && ok "exit 0 telemetry-on (settings.json)" || no "non-zero exit ($RC)"
A="$(attrs_of "$R")"
[ "$A" = "service.name=myproj,service.version=${FIXTURE_VERSION}" ] \
  && ok "wrote service.name=myproj,service.version=${FIXTURE_VERSION}" \
  || no "attrs wrong (got: [$A])"

echo "== 3. Telemetry ON via env var ONLY (no endpoint anywhere) ⇒ writes =="
# Proves the OR branch AND that the gate does NOT require OTEL_EXPORTER_OTLP_ENDPOINT.
R="$(newrepo envproj)"; H="$(newhome 0)"   # settings.json has NO telemetry flag
run "$R" "$H" CLAUDE_CODE_ENABLE_TELEMETRY=1
[ "$RC" -eq 0 ] && ok "exit 0 telemetry-on (env var only)" || no "non-zero exit env-only ($RC)"
A="$(attrs_of "$R")"
[ "$A" = "service.name=envproj,service.version=${FIXTURE_VERSION}" ] \
  && ok "env-only telemetry (console/no-endpoint mode) still labels" \
  || no "env-only attrs wrong (got: [$A])"

echo "== 4. Preserves existing JSON keys (unrelated env + top-level) =="
R="$(newrepo keepkeys)"; H="$(newhome 1)"
mkdir -p "$R/.claude"
"$JQ" -n '{topkey:"keepme", env:{FOO:"bar"}}' > "$R/.claude/settings.local.json"
run "$R" "$H"
[ "$RC" -eq 0 ] && ok "exit 0 preserving keys" || no "non-zero exit ($RC)"
TOP="$("$JQ" -r '.topkey // empty' "$R/.claude/settings.local.json" 2>/dev/null)"
FOO="$("$JQ" -r '.env.FOO // empty' "$R/.claude/settings.local.json" 2>/dev/null)"
A="$(attrs_of "$R")"
[ "$TOP" = "keepme" ] && ok "top-level key survived" || no "top-level key lost ($TOP)"
[ "$FOO" = "bar" ] && ok "unrelated .env.FOO survived" || no "env.FOO lost ($FOO)"
[ "$A" = "service.name=keepkeys,service.version=${FIXTURE_VERSION}" ] && ok "OTEL attrs added alongside" || no "attrs wrong (got: [$A])"

echo "== 5. Value-level merge — preserves OTHER OTel attrs, replaces stale name =="
R="$(newrepo mergeproj)"; H="$(newhome 1)"
mkdir -p "$R/.claude"
"$JQ" -n '{env:{OTEL_RESOURCE_ATTRIBUTES:"deployment.environment=dev,service.name=old"}}' \
  > "$R/.claude/settings.local.json"
run "$R" "$H"
[ "$RC" -eq 0 ] && ok "exit 0 value-merge" || no "non-zero exit ($RC)"
A="$(attrs_of "$R")"
printf '%s' "$A" | grep -q 'deployment.environment=dev' && ok "deployment.environment=dev preserved" || no "deployment.environment dropped (got: [$A])"
printf '%s' "$A" | grep -q "service.name=mergeproj" && ok "service.name replaced with new computed value" || no "service.name not updated (got: [$A])"
printf '%s' "$A" | grep -q "service.name=old" && no "stale service.name=old still present (got: [$A])" || ok "stale service.name=old removed (not duplicated)"
printf '%s' "$A" | grep -q "service.version=${FIXTURE_VERSION}" && ok "service.version present" || no "service.version missing (got: [$A])"
# exactly one service.name and one service.version pair.
NCOUNT="$(printf '%s' "$A" | tr ',' '\n' | grep -c '^service\.name=')"
VCOUNT="$(printf '%s' "$A" | tr ',' '\n' | grep -c '^service\.version=')"
[ "$NCOUNT" = "1" ] && [ "$VCOUNT" = "1" ] && ok "exactly one service.name + one service.version (no dupes)" || no "duplicate service pairs (name=$NCOUNT version=$VCOUNT)"

echo "== 6. Special-character repo name ⇒ sanitized =="
R="$(newrepo 'my,repo=x y')"; H="$(newhome 1)"
run "$R" "$H"
[ "$RC" -eq 0 ] && ok "exit 0 special-char repo" || no "non-zero exit ($RC)"
A="$(attrs_of "$R")"
# comma / '=' / space must all be replaced by '_'.
NAME_PAIR="$(printf '%s' "$A" | tr ',' '\n' | grep '^service\.name=' | head -1)"
[ "$NAME_PAIR" = "service.name=my_repo_x_y" ] && ok "special chars sanitized → $NAME_PAIR" || no "sanitization wrong (got: [$NAME_PAIR] full=[$A])"
# the full value must parse as exactly the two intended pairs (no extra/broken attrs).
PAIRS="$(printf '%s' "$A" | tr ',' '\n' | sort | tr '\n' ' ')"
[ "$PAIRS" = "service.name=my_repo_x_y service.version=${FIXTURE_VERSION} " ] \
  && ok "OTEL_RESOURCE_ATTRIBUTES parses to exactly the intended pairs (no broken extras)" \
  || no "value has stray/broken attributes (got: [$PAIRS])"

echo "== 7. Idempotent — second run with current value ⇒ byte-identical + mtime unchanged =="
R="$(newrepo idemproj)"; H="$(newhome 1)"
run "$R" "$H"
SL="$R/.claude/settings.local.json"
C1="$(cat "$SL")"
M1="$(if stat -c %Y "$SL" >/dev/null 2>&1; then stat -c %Y "$SL"; else stat -f %m "$SL"; fi)"
sleep 1   # avoid same-second mtime collision masking a rewrite
run "$R" "$H"
C2="$(cat "$SL")"
M2="$(if stat -c %Y "$SL" >/dev/null 2>&1; then stat -c %Y "$SL"; else stat -f %m "$SL"; fi)"
[ "$RC" -eq 0 ] && ok "exit 0 second (idempotent) run" || no "non-zero exit idempotent ($RC)"
[ "$C1" = "$C2" ] && ok "file content byte-identical after re-run" || no "content changed on idempotent re-run"
[ "$M1" = "$M2" ] && ok "mtime unchanged on idempotent re-run (no write)" || no "mtime changed (a rewrite happened) m1=$M1 m2=$M2"

echo "== 8. Unparseable settings.local.json ⇒ no clobber, exit 0 =="
R="$(newrepo badjson)"; H="$(newhome 1)"
mkdir -p "$R/.claude"
printf '{ this is not valid json,,,' > "$R/.claude/settings.local.json"
B1="$(cat "$R/.claude/settings.local.json")"
run "$R" "$H"
B2="$(cat "$R/.claude/settings.local.json")"
[ "$RC" -eq 0 ] && ok "exit 0 on unparseable settings.local.json" || no "non-zero exit unparseable ($RC)"
[ "$B1" = "$B2" ] && ok "unparseable file byte-identical (NOT clobbered)" || no "unparseable file was clobbered"

echo "== 9. Non-git cwd ⇒ cwd-basename fallback, still labels, exit 0 =="
NG="$(mktemp -d)"; TMPS+=("$NG")
NGD="$NG/notgit"; mkdir -p "$NGD"   # NOT a git repo
H="$(newhome 1)"
run "$NGD" "$H"
[ "$RC" -eq 0 ] && ok "exit 0 in non-git cwd" || no "non-zero exit non-git ($RC)"
A="$(attrs_of "$NGD")"
[ "$A" = "service.name=notgit,service.version=${FIXTURE_VERSION}" ] \
  && ok "non-git cwd fell back to cwd-basename (notgit)" \
  || no "non-git fallback wrong (got: [$A])"

echo "== 10. Created-file perms 600 =="
R="$(newrepo permproj)"; H="$(newhome 1)"
run "$R" "$H"
SL="$R/.claude/settings.local.json"
[ -f "$SL" ] && ok "settings.local.json created" || no "settings.local.json not created"
P="$(perms_of "$SL")"
[ "$P" = "600" ] && ok "created file is 0600" || no "created file perms wrong ($P)"

echo "== 11. Version source — written service.version == jq .version of fixture plugin.json =="
R="$(newrepo verproj)"; H="$(newhome 1)"
run "$R" "$H"
A="$(attrs_of "$R")"
EXPECT_VER="$("$JQ" -r '.version' "$PLUGIN_ROOT/.claude-plugin/plugin.json")"
GOT_VER="$(printf '%s' "$A" | tr ',' '\n' | grep '^service\.version=' | sed 's/^service\.version=//')"
[ "$GOT_VER" = "$EXPECT_VER" ] && ok "service.version=$GOT_VER matches fixture plugin.json .version" || no "version mismatch (got $GOT_VER expected $EXPECT_VER)"

echo "== 12. Always exit 0 — every path above returned 0 (re-assert a fresh run) =="
R="$(newrepo finalproj)"; H="$(newhome 1)"
run "$R" "$H"
[ "$RC" -eq 0 ] && ok "runtime script returned 0" || no "runtime script non-zero ($RC)"

# ---- summary ----------------------------------------------------------------
echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
