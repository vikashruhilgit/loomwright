#!/usr/bin/env bash
# test-guard-test-integrity.sh — self-tests for guard-test-integrity.sh +
# guard-arm.sh (the six-phase-loop-gaps/02 test-integrity guard). Covers the
# full case matrix in the source requirement's Scope item 10
# (`.supervisor/requirements/six-phase-loop-gaps/02-test-integrity-guard.md`):
# every Bash pattern + its negation twin, every Write|Edit basename + allow
# case, the 6 gate cases, the guard-arm.sh subcommand cases, the concurrency
# case, the sentinel checks, and all 8 named mutation controls.
#
# Runs entirely in temp dirs (mktemp -d), never touches the real
# `.supervisor/`. Exit 0 = all pass, 1 = any failure (auto-registered by
# ci.yml's test-*.sh glob).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$SCRIPT_DIR/guard-test-integrity.sh"
ARM="$SCRIPT_DIR/guard-arm.sh"
HOOKS_JSON="$SCRIPT_DIR/../hooks/hooks.json"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass + 1)); }
no() { echo "  FAIL: $1"; fail=$((fail + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "test-guard-test-integrity: jq absent — guard denies closed without it. Skipping full matrix."
  echo "RESULT: 0 passed, 0 failed (jq absent, vacuous)"
  exit 0
fi

# ---------------------------------------------------------------------------
# harness helpers
# ---------------------------------------------------------------------------
new_guarded_dir() {
  local d sid
  d="$(mktemp -d)"
  sid="${1:-sess-guard-test}"
  mkdir -p "$d/.supervisor/guard"
  printf '{\n  "session_id": "%s",\n  "armed_at": "%s",\n  "by": "test"\n}\n' "$sid" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$d/.supervisor/guard/$sid.json"
  printf '%s' "$d"
}

# bash_rc <guard_dir> <session_id> <command> [agent_type]
bash_rc() {
  local d="$1" sid="$2" cmd="$3" at="${4:-}"
  local payload
  payload="$(jq -n --arg sid "$sid" --arg cmd "$cmd" --arg at "$at" \
    'if $at == "" then {session_id:$sid, tool_name:"Bash", tool_input:{command:$cmd}}
     else {session_id:$sid, agent_type:$at, tool_name:"Bash", tool_input:{command:$cmd}} end')"
  printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$d" bash "$GUARD" >/dev/null 2>/tmp/.guard-test-stderr.$$
  echo $?
}

bash_stderr() { cat /tmp/.guard-test-stderr.$$ 2>/dev/null; }

# edit_rc <guard_dir> <session_id> <tool_name> <file_path>
edit_rc() {
  local d="$1" sid="$2" tool="$3" fp="$4"
  local payload
  payload="$(jq -n --arg sid "$sid" --arg tool "$tool" --arg fp "$fp" '{session_id:$sid, tool_name:$tool, tool_input:{file_path:$fp}}')"
  printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$d" bash "$GUARD" >/dev/null 2>/tmp/.guard-test-stderr.$$
  echo $?
}

assert_rc() {
  local desc="$1" got="$2" want="$3"
  if [ "$got" = "$want" ]; then ok "$desc"; else no "$desc (want rc=$want got rc=$got, stderr=[$(bash_stderr)])"; fi
}

D="$(new_guarded_dir sess-A)"
SID="sess-A"

# ---------------------------------------------------------------------------
# Bash-matcher patterns + negation twins
# ---------------------------------------------------------------------------
assert_rc "git commit -m x — allow"                              "$(bash_rc "$D" "$SID" 'git commit -m x')" 0
assert_rc "git commit -n -m x — deny"                             "$(bash_rc "$D" "$SID" 'git commit -n -m x')" 2
assert_rc "git commit -qm x --no-veri — deny"                     "$(bash_rc "$D" "$SID" 'git commit -qm x --no-veri')" 2
assert_rc "git push -n — allow"                                   "$(bash_rc "$D" "$SID" 'git push -n')" 0
assert_rc "git push --no-verify — deny"                           "$(bash_rc "$D" "$SID" 'git push --no-verify')" 2
assert_rc "HUSKY=0 git commit -m x — deny"                        "$(bash_rc "$D" "$SID" 'HUSKY=0 git commit -m x')" 2
assert_rc "export HUSKY=0; git commit -m x — deny"                "$(bash_rc "$D" "$SID" 'export HUSKY=0; git commit -m x')" 2
assert_rc "CI_SKIP=1 npm test — allow"                             "$(bash_rc "$D" "$SID" 'CI_SKIP=1 npm test')" 0
assert_rc "git -c core.hooksPath=/dev/null commit — deny"          "$(bash_rc "$D" "$SID" 'git -c core.hooksPath=/dev/null commit')" 2
assert_rc "git config --get core.hooksPath — allow"                "$(bash_rc "$D" "$SID" 'git config --get core.hooksPath')" 0
assert_rc "git config core.hooksPath /dev/null — deny"             "$(bash_rc "$D" "$SID" 'git config core.hooksPath /dev/null')" 2
assert_rc 'GIT_CONFIG_PARAMETERS=... git commit — deny'            "$(bash_rc "$D" "$SID" "GIT_CONFIG_PARAMETERS=\"'core.hooksPath=/dev/null'\" git commit")" 2
assert_rc "git clean -fdx — deny"                                  "$(bash_rc "$D" "$SID" 'git clean -fdx')" 2
assert_rc "git clean -fd — allow"                                  "$(bash_rc "$D" "$SID" 'git clean -fd')" 0
assert_rc "grep -- '--no-verify' docs/HOOKS.md — allow"            "$(bash_rc "$D" "$SID" "grep -- '--no-verify' docs/HOOKS.md")" 0
assert_rc "cat > jest.config.js <<EOF — deny"                      "$(bash_rc "$D" "$SID" 'cat > jest.config.js <<EOF')" 2
assert_rc "git diff jest.config.ts > /tmp/d.patch — allow"         "$(bash_rc "$D" "$SID" 'git diff jest.config.ts > /tmp/d.patch')" 0
assert_rc "sed -i '' s/a/b/ vitest.config.ts — deny"                "$(bash_rc "$D" "$SID" "sed -i '' s/a/b/ vitest.config.ts")" 2
assert_rc "rm .supervisor/guard/<sid>.json — deny"                 "$(bash_rc "$D" "$SID" "rm .supervisor/guard/$SID.json")" 2
assert_rc "bash guard-arm.sh disarm-session — deny"                "$(bash_rc "$D" "$SID" "bash $ARM disarm-session")" 2
assert_rc "bash guard-arm.sh arm-from-payload — deny"              "$(bash_rc "$D" "$SID" "bash $ARM arm-from-payload")" 2
assert_rc "bash guard-arm.sh arm supervisor — allow"               "$(bash_rc "$D" "$SID" "bash $ARM arm supervisor")" 0
# PR #258 review finding: an `arm` invocation is only "harmless by construction"
# when it can only name the CALLER's own session id — a --session-id flag lets
# a tool call arm an ARBITRARY other session, which is the real capability
# --session-id exists to grant, so it must be denied from a tool call (the
# only legitimate caller, dispatch-pr-review.sh, invokes guard-arm.sh directly
# as a subprocess, never through a tool call this matcher sees).
assert_rc "bash guard-arm.sh arm x --session-id <arbitrary-id> — deny (arbitrary-session arm)" "$(bash_rc "$D" "$SID" "bash $ARM arm x --session-id arbitrary-id")" 2
assert_rc "bash guard-arm.sh arm x --session-id=<arbitrary-id> — deny (= form)" "$(bash_rc "$D" "$SID" "bash $ARM arm x --session-id=arbitrary-id")" 2
assert_rc "cat guard-arm.sh — allow"                                "$(bash_rc "$D" "$SID" "cat $ARM")" 0
assert_rc "sed -n 1,40p guard-arm.sh — allow"                       "$(bash_rc "$D" "$SID" "sed -n 1,40p $ARM")" 0
assert_rc "shellcheck guard-arm.sh — allow (tool absence is not the point)" "$(bash_rc "$D" "$SID" "shellcheck $ARM")" 0
assert_rc "printf 'x' > notes.md — allow"                          "$(bash_rc "$D" "$SID" "printf 'x' > notes.md")" 0
assert_rc "sed -i s/a/b/ guard-test-integrity.sh — deny"            "$(bash_rc "$D" "$SID" "sed -i s/a/b/ $GUARD")" 2

# ---------------------------------------------------------------------------
# Write|Edit-matcher basenames + allow cases
# ---------------------------------------------------------------------------
assert_rc "Edit jest.config.ts — deny"                              "$(edit_rc "$D" "$SID" Edit "jest.config.ts")" 2
assert_rc "Edit ../repo-sub/jest.config.ts — deny"                  "$(edit_rc "$D" "$SID" Edit "../repo-sub/jest.config.ts")" 2
assert_rc "Edit .claude/settings.json — deny"                       "$(edit_rc "$D" "$SID" Edit ".claude/settings.json")" 2
assert_rc "Edit ~/.claude/settings.local.json — deny"               "$(edit_rc "$D" "$SID" Edit "/home/x/.claude/settings.local.json")" 2
assert_rc "Edit cache-path guard-test-integrity.sh — deny"          "$(edit_rc "$D" "$SID" Edit "/home/x/.claude/plugins/cache/atelier/loomwright/1/scripts/guard-test-integrity.sh")" 2
assert_rc "Edit hooks.json — deny"                                  "$(edit_rc "$D" "$SID" Edit "loomwright/hooks/hooks.json")" 2
assert_rc "Edit guard-arm.sh — deny"                                "$(edit_rc "$D" "$SID" Edit "loomwright/scripts/guard-arm.sh")" 2
assert_rc "Edit src/foo.test.ts — allow"                            "$(edit_rc "$D" "$SID" Edit "src/foo.test.ts")" 0
assert_rc "Edit package.json — allow"                               "$(edit_rc "$D" "$SID" Edit "package.json")" 0
assert_rc "Edit docs/jest.config.md — allow"                        "$(edit_rc "$D" "$SID" Edit "docs/jest.config.md")" 0
assert_rc "Write new/dir/file.ts — allow"                           "$(edit_rc "$D" "$SID" Write "new/dir/file.ts")" 0
assert_rc "Write new/dir/conftest.py — allow (not a git toplevel)"  "$(edit_rc "$D" "$SID" Write "new/dir/conftest.py")" 0
assert_rc "Edit .vscode/settings.json — allow"                      "$(edit_rc "$D" "$SID" Edit ".vscode/settings.json")" 0
assert_rc "Edit config/settings.json — allow"                       "$(edit_rc "$D" "$SID" Edit "config/settings.json")" 0
assert_rc "Edit .github/workflows/ci.yml — allow by default"        "$(edit_rc "$D" "$SID" Edit ".github/workflows/ci.yml")" 0
gextra_rc="$(LOOMWRIGHT_GUARD_EXTRA_GLOBS='.github/workflows/*' bash -c "printf '%s' \"\$(jq -n --arg sid '$SID' '{session_id:\$sid, tool_name:\"Edit\", tool_input:{file_path:\".github/workflows/ci.yml\"}}}')\" 2>/dev/null" 2>/dev/null || true)"
gextra_rc="$(printf '%s' "$(jq -n --arg sid "$SID" '{session_id:$sid, tool_name:"Edit", tool_input:{file_path:".github/workflows/ci.yml"}}')" | CLAUDE_PROJECT_DIR="$D" LOOMWRIGHT_GUARD_EXTRA_GLOBS='.github/workflows/*' bash "$GUARD" >/dev/null 2>&1; echo $?)"
assert_rc "Edit .github/workflows/ci.yml — deny under LOOMWRIGHT_GUARD_EXTRA_GLOBS" "$gextra_rc" 2

# ---------------------------------------------------------------------------
# Gate cases
# ---------------------------------------------------------------------------
EMPTY_D="$(mktemp -d)"
assert_rc "guard/ absent — allow"                                  "$(bash_rc "$EMPTY_D" "$SID" 'git commit -n -m x')" 0

FOREIGN_D="$(mktemp -d)"; mkdir -p "$FOREIGN_D/.supervisor/guard"
echo '{"session_id":"other","armed_at":"2026-09-23T00:00:00Z","by":"test"}' > "$FOREIGN_D/.supervisor/guard/other.json"
assert_rc "guard/ holds only a foreign-id file — allow"            "$(bash_rc "$FOREIGN_D" "$SID" 'git commit -n -m x')" 0

optout_rc="$(printf '%s' "$(jq -n --arg sid "$SID" --arg cmd 'git commit -n -m x' '{session_id:$sid, tool_name:"Bash", tool_input:{command:$cmd}}')" | CLAUDE_PROJECT_DIR="$D" LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS=1 bash "$GUARD" >/dev/null 2>&1; echo $?)"
assert_rc "env opt-out — allow"                                    "$optout_rc" 0

nojq_deny_rc="$(printf '%s' "$(jq -n --arg sid "$SID" '{session_id:$sid, tool_name:"Bash", tool_input:{command:"echo hi"}}')" | env -i PATH=/bin CLAUDE_PROJECT_DIR="$D" bash "$GUARD" >/dev/null 2>&1; echo $?)"
assert_rc "no jq + own-id file present — guard_unavailable deny"   "$nojq_deny_rc" 2

nojq_allow_rc="$(printf '%s' "$(jq -n '{session_id:"x", tool_name:"Bash", tool_input:{command:"echo hi"}}')" | env -i PATH=/bin CLAUDE_PROJECT_DIR="$EMPTY_D" bash "$GUARD" >/dev/null 2>&1; echo $?)"
assert_rc "no jq + empty guard/ — allow"                           "$nojq_allow_rc" 0

# ---------------------------------------------------------------------------
# guard-arm.sh subcommand cases
# ---------------------------------------------------------------------------
ARM_D="$(mktemp -d)"
unset_rc="$(cd "$ARM_D" && env -u CLAUDE_CODE_SESSION_ID CLAUDE_PROJECT_DIR="$ARM_D" bash "$ARM" arm supervisor >/dev/null 2>&1; echo $?)"
assert_rc "arm with CLAUDE_CODE_SESSION_ID unset — exit 3, no file" "$unset_rc" 3
[ ! -e "$ARM_D/.supervisor/guard" ] || [ -z "$(ls -A "$ARM_D/.supervisor/guard" 2>/dev/null)" ] && ok "arm unset-env writes no file" || no "arm unset-env writes no file"

set_rc="$(CLAUDE_PROJECT_DIR="$ARM_D" CLAUDE_CODE_SESSION_ID=sess-arm-1 bash "$ARM" arm supervisor >/dev/null 2>&1; echo $?)"
assert_rc "arm with session id set — exit 0" "$set_rc" 0
[ -e "$ARM_D/.supervisor/guard/sess-arm-1.json" ] && ok "arm writes <id>.json" || no "arm writes <id>.json"

idem_before="$(cat "$ARM_D/.supervisor/guard/sess-arm-1.json")"
CLAUDE_PROJECT_DIR="$ARM_D" CLAUDE_CODE_SESSION_ID=sess-arm-1 bash "$ARM" arm supervisor >/dev/null 2>&1
idem_after="$(cat "$ARM_D/.supervisor/guard/sess-arm-1.json")"
[ "$idem_before" = "$idem_after" ] && ok "arm same id twice — unchanged (idempotent)" || no "arm same id twice — unchanged (idempotent)"

CLAUDE_PROJECT_DIR="$ARM_D" CLAUDE_CODE_SESSION_ID=sess-arm-2 bash "$ARM" arm x >/dev/null 2>&1
[ -e "$ARM_D/.supervisor/guard/sess-arm-1.json" ] && [ -e "$ARM_D/.supervisor/guard/sess-arm-2.json" ] && ok "second arm under different env id creates a second file and keeps the first" || no "second arm under different env id creates a second file and keeps the first"
after2="$(cat "$ARM_D/.supervisor/guard/sess-arm-1.json")"
[ "$idem_after" = "$after2" ] && ok "first file byte-identical after a second session's arm" || no "first file byte-identical after a second session's arm"

CLAUDE_PROJECT_DIR="$ARM_D" bash "$ARM" arm dispatcher --session-id uuid-disp-1 >/dev/null 2>&1
[ -e "$ARM_D/.supervisor/guard/uuid-disp-1.json" ] && ok "arm dispatcher --session-id X writes X.json" || no "arm dispatcher --session-id X writes X.json"

afp_match="$(printf '%s' "$(jq -n '{session_id:"sess-afp-1", tool_input:{subagent_type:"loomwright:loomwright:worker"}}')" | CLAUDE_PROJECT_DIR="$ARM_D" bash "$ARM" arm-from-payload >/dev/null 2>&1; echo $?)"
[ -e "$ARM_D/.supervisor/guard/sess-afp-1.json" ] && ok "arm-from-payload arms on namespaced :worker subagent_type" || no "arm-from-payload arms on namespaced :worker subagent_type"

printf '%s' "$(jq -n '{session_id:"sess-afp-2", tool_input:{subagent_type:"general-purpose"}}')" | CLAUDE_PROJECT_DIR="$ARM_D" bash "$ARM" arm-from-payload >/dev/null 2>&1
[ ! -e "$ARM_D/.supervisor/guard/sess-afp-2.json" ] && ok "arm-from-payload does not arm on general-purpose" || no "arm-from-payload does not arm on general-purpose"

printf '%s' "$(jq -n '{session_id:"sess-afp-3", tool_input:{subagent_type:"my-worker"}}')" | CLAUDE_PROJECT_DIR="$ARM_D" bash "$ARM" arm-from-payload >/dev/null 2>&1
[ ! -e "$ARM_D/.supervisor/guard/sess-afp-3.json" ] && ok "arm-from-payload does not arm on unnamespaced my-worker" || no "arm-from-payload does not arm on unnamespaced my-worker"

printf '%s' "$(jq -n '{session_id:"sess-arm-1"}')" | CLAUDE_PROJECT_DIR="$ARM_D" bash "$ARM" disarm-session >/dev/null 2>&1
[ ! -e "$ARM_D/.supervisor/guard/sess-arm-1.json" ] && [ -e "$ARM_D/.supervisor/guard/sess-arm-2.json" ] && ok "disarm-session removes only the payload's own id" || no "disarm-session removes only the payload's own id"

# prune: 8-day-old file removed, 6-day-old file kept
PRUNE_D="$(mktemp -d)"; mkdir -p "$PRUNE_D/.supervisor/guard"
echo '{"session_id":"old8","armed_at":"x","by":"test"}' > "$PRUNE_D/.supervisor/guard/old8.json"
echo '{"session_id":"old6","armed_at":"x","by":"test"}' > "$PRUNE_D/.supervisor/guard/old6.json"
old8_epoch=$(( $(date -u +%s) - (8 * 86400) ))
old6_epoch=$(( $(date -u +%s) - (6 * 86400) ))
old8_ts="$(date -u -r "$old8_epoch" +%Y%m%d%H%M.%S 2>/dev/null || date -u -d "@$old8_epoch" +%Y%m%d%H%M.%S 2>/dev/null)"
old6_ts="$(date -u -r "$old6_epoch" +%Y%m%d%H%M.%S 2>/dev/null || date -u -d "@$old6_epoch" +%Y%m%d%H%M.%S 2>/dev/null)"
touch -t "$old8_ts" "$PRUNE_D/.supervisor/guard/old8.json" 2>/dev/null || true
touch -t "$old6_ts" "$PRUNE_D/.supervisor/guard/old6.json" 2>/dev/null || true
CLAUDE_PROJECT_DIR="$PRUNE_D" CLAUDE_CODE_SESSION_ID=sess-prune-trigger bash "$ARM" arm x >/dev/null 2>&1
[ ! -e "$PRUNE_D/.supervisor/guard/old8.json" ] && [ -e "$PRUNE_D/.supervisor/guard/old6.json" ] && ok "arm prunes an 8-day-old marker and keeps a 6-day-old one" || no "arm prunes an 8-day-old marker and keeps a 6-day-old one"

# ---------------------------------------------------------------------------
# Concurrency case
# ---------------------------------------------------------------------------
CONC_D="$(mktemp -d)"; mkdir -p "$CONC_D/.supervisor/guard"
echo '{"session_id":"A","armed_at":"2026-09-23T00:00:00Z","by":"test"}' > "$CONC_D/.supervisor/guard/A.json"
before_denied="$(bash_rc "$CONC_D" A 'git commit -n -m x')"
CLAUDE_PROJECT_DIR="$CONC_D" CLAUDE_CODE_SESSION_ID=B bash "$ARM" arm-from-payload <<<'{}' >/dev/null 2>&1 || true
CLAUDE_PROJECT_DIR="$CONC_D" CLAUDE_CODE_SESSION_ID=B bash "$ARM" arm supervisor >/dev/null 2>&1
after_denied="$(bash_rc "$CONC_D" A 'git commit -n -m x')"
if [ "$before_denied" = 2 ] && [ "$after_denied" = 2 ]; then
  ok "concurrency: payload A stays denied after B's arm runs"
else
  no "concurrency: payload A stays denied after B's arm runs (before=$before_denied after=$after_denied)"
fi

# ---------------------------------------------------------------------------
# Sentinels
# ---------------------------------------------------------------------------
if [ -f "$HOOKS_JSON" ]; then
  bash_leaf="$(jq -r '.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]?.command // empty' "$HOOKS_JSON" 2>/dev/null)"
  editleaf="$(jq -r '.hooks.PreToolUse[]? | select(.matcher == "Write|Edit") | .hooks[]?.command // empty' "$HOOKS_JSON" 2>/dev/null)"
  case "$bash_leaf$editleaf" in
    *guard-test-integrity.sh*) ok "hooks.json guard leaves reference guard-test-integrity.sh" ;;
    *) no "hooks.json guard leaves reference guard-test-integrity.sh" ;;
  esac
  case "$bash_leaf" in
    *'|| true'*) no "PreToolUse[Bash] guard leaf must NOT carry || true" ;;
    *) ok "PreToolUse[Bash] guard leaf has no || true" ;;
  esac
  case "$editleaf" in
    *'|| true'*) no "PreToolUse[Write|Edit] guard leaf must NOT carry || true" ;;
    *) ok "PreToolUse[Write|Edit] guard leaf has no || true" ;;
  esac
else
  echo "  (hooks.json not found yet at $HOOKS_JSON — skipping hooks.json sentinel)"
fi

grep_hits="$(grep -rln ALLOW_GATE_CONFIG_EDITS "$SCRIPT_DIR/../agents" "$SCRIPT_DIR/../skills" 2>/dev/null || true)"
[ -z "$grep_hits" ] && ok "ALLOW_GATE_CONFIG_EDITS never named in agents/skills prose" || no "ALLOW_GATE_CONFIG_EDITS named in: $grep_hits"

deny_line1="$(bash_rc "$D" "$SID" 'git commit -n -m x' >/dev/null; bash_stderr)"
deny_line2="$(bash_rc "$D" "$SID" 'git commit -n -m x' 'general-purpose' >/dev/null; bash_stderr)"
sentinel_clean=1
for term in ALLOW_GATE '.json' settings config.json guard-arm; do
  case "$deny_line1$deny_line2" in
    *"$term"*) sentinel_clean=0 ;;
  esac
done
[ "$sentinel_clean" = 1 ] && ok "deny lines contain none of ALLOW_GATE/.json/settings/config.json/guard-arm" || no "deny lines contain a forbidden substring: [$deny_line1] / [$deny_line2]"

# ---------------------------------------------------------------------------
# Mutation controls (a)-(h) — each demonstrates the guard fails CLOSED-to-open
# (or open-to-closed) when the named mechanism is broken, and passes on the
# real script. Each mutant is a throwaway COPY, gated non-empty + cmp-different
# + `bash -n` clean, never the real file.
# ---------------------------------------------------------------------------
MUT_D="$(mktemp -d)"

make_mutant() {
  local out="$1"; shift
  cp "$GUARD" "$out"
  "$@" "$out"
  [ -s "$out" ] || { no "mutant $out is empty — aborting this control"; return 1; }
  cmp -s "$GUARD" "$out" && { no "mutant $out is byte-identical to the original — aborting this control"; return 1; }
  bash -n "$out" || { no "mutant $out fails bash -n — aborting this control"; return 1; }
  return 0
}

mut_rc() {
  local mutant="$1" d="$2" sid="$3" cmd="$4"
  printf '%s' "$(jq -n --arg sid "$sid" --arg cmd "$cmd" '{session_id:$sid, tool_name:"Bash", tool_input:{command:$cmd}}')" \
    | CLAUDE_PROJECT_DIR="$d" bash "$mutant" >/dev/null 2>&1
  echo $?
}

# (a) delete `exit 2` from deny() -> git commit -n case fails (no longer denies)
MUT_A="$MUT_D/mut-a.sh"
if make_mutant "$MUT_A" perl -pi -e 's/^  exit 2\n$// if $. > 60 && $. < 75' 2>/dev/null; then
  rc="$(mut_rc "$MUT_A" "$D" "$SID" 'git commit -n -m x')"
  [ "$rc" != "2" ] && ok "(a) mutation control: removing exit 2 from deny() breaks the commit -n case" || no "(a) mutation control did not break the case (still rc=2)"
fi

# (b) append `|| true` to a guard hook string in a hooks.json copy -> sentinel fails
if [ -f "$HOOKS_JSON" ]; then
  MUT_B="$MUT_D/hooks-mut-b.json"
  jq '(.hooks.PreToolUse[] | select(.matcher=="Bash") | .hooks[] | select(.command|test("guard-test-integrity")) | .command) |= . + " || true"' "$HOOKS_JSON" > "$MUT_B" 2>/dev/null || true
  if [ -s "$MUT_B" ] && ! cmp -s "$HOOKS_JSON" "$MUT_B"; then
    leaf="$(jq -r '.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]?.command // empty' "$MUT_B" 2>/dev/null)"
    case "$leaf" in
      *'|| true'*) ok "(b) mutation control: appending || true to the guard leaf breaks the sentinel" ;;
      *) no "(b) mutation control did not break the sentinel" ;;
    esac
  else
    echo "  (b) skipped: could not construct mutant hooks.json)"
  fi
fi

# (c) make the guard read a fixed armed.json instead of <sid>.json -> the
#     foreign-id-only case fails (now denies on a marker that isn't its own)
MUT_C="$MUT_D/mut-c.sh"
if make_mutant "$MUT_C" perl -pi -e 's/\$GUARD_DIR\/\$SESSION_ID\.json/\$GUARD_DIR\/armed.json/g'; then
  cp "$FOREIGN_D/.supervisor/guard/other.json" "$FOREIGN_D/.supervisor/guard/armed.json" 2>/dev/null || true
  rc="$(mut_rc "$MUT_C" "$FOREIGN_D" "$SID" 'git commit -n -m x')"
  [ "$rc" = "2" ] && ok "(c) mutation control: fixed armed.json filename denies on a foreign marker" || no "(c) mutation control did not break the foreign-id-only case (rc=$rc)"
fi

# (d) --no-ver[a-z]* -> --no-verify (exact match only) -> --no-veri case fails
MUT_D2="$MUT_D/mut-d.sh"
if make_mutant "$MUT_D2" perl -pi -e 's/--no-ver\[a-z\]\*\|--no-verify\)/--no-verify)/g'; then
  rc="$(mut_rc "$MUT_D2" "$D" "$SID" 'git commit -qm x --no-veri')"
  [ "$rc" != "2" ] && ok "(d) mutation control: exact --no-verify match misses --no-veri" || no "(d) mutation control did not break the --no-veri case (rc=$rc)"
fi

# (i) drop the --session-id scan from the `arm` exemption -> a tool call can
#     arm an ARBITRARY other session again (PR #258 review finding — closes
#     the demonstrated bypass, proving the new check is load-bearing)
MUT_I="$MUT_D/mut-i.sh"
if make_mutant "$MUT_I" perl -0pi -e 's/    local w2\n    for w2 in "\$\{words\[\@\]:\$\(\(ga_idx \+ 2\)\)\}"; do\n      case "\$w2" in\n        --session-id\|--session-id=\*\)\n          deny_variant bash "internal control script invocation"\n          ;;\n      esac\n    done\n//'; then
  rc="$(mut_rc "$MUT_I" "$D" "$SID" "bash $ARM arm x --session-id arbitrary-id")"
  [ "$rc" != "2" ] && ok "(i) mutation control: dropping the --session-id scan re-opens the arbitrary-session-arm bypass" || no "(i) mutation control did not break the case (still rc=2)"
fi

# (e) delete the empty-id check in arm -> the unset-env case fails (writes a
#     file instead of exit 3)
MUT_E="$MUT_D/guard-arm-mut-e.sh"
cp "$ARM" "$MUT_E"
python3 - "$MUT_E" <<'PYEOF' 2>/dev/null || true
import sys
p = sys.argv[1]
with open(p) as f:
    c = f.read()
old = '  if ! valid_session_id "$sid"; then\n    printf \'guard_arm_failed: no session id\\n\' >&2\n    exit 3\n  fi\n'
new = '  if false; then\n    printf \'guard_arm_failed: no session id\\n\' >&2\n    exit 3\n  fi\n'
assert old in c, "anchor not found for mutation (e)"
c = c.replace(old, new, 1)
with open(p, 'w') as f:
    f.write(c)
PYEOF
if [ -s "$MUT_E" ] && ! cmp -s "$ARM" "$MUT_E" && bash -n "$MUT_E" 2>/dev/null; then
  ARM_MUT_D="$(mktemp -d)"
  rc="$(cd "$ARM_MUT_D" && env -u CLAUDE_CODE_SESSION_ID CLAUDE_PROJECT_DIR="$ARM_MUT_D" bash "$MUT_E" arm supervisor >/dev/null 2>&1; echo $?)"
  [ "$rc" != "3" ] && ok "(e) mutation control: removing the empty-id check no longer exits 3" || no "(e) mutation control did not break the unset-env case (rc=$rc)"
  rm -rf "$ARM_MUT_D"
else
  no "(e) mutation control: could not construct mutant"
fi

# (f) drop the same-simple-command rule (treat the whole line as one blob) ->
#     git diff jest.config.ts > /tmp/d.patch case fails
MUT_F2="$MUT_D/mut-f2.sh"
cp "$GUARD" "$MUT_F2"
python3 - "$MUT_F2" <<'PYEOF' 2>/dev/null || true
import sys
p = sys.argv[1]
with open(p) as f:
    c = f.read()
anchor = 'evaluate_bash_command() {\n  local full_cmd="$1"'
inject = 'evaluate_bash_command() {\n  local full_cmd="$1"\n  case "$full_cmd" in *jest.config*|*vitest.config*) deny_variant bash "protected configuration write" ;; esac'
c = c.replace(anchor, inject, 1)
with open(p, 'w') as f:
    f.write(c)
PYEOF
if [ -s "$MUT_F2" ] && ! cmp -s "$GUARD" "$MUT_F2" && bash -n "$MUT_F2" 2>/dev/null; then
  rc="$(mut_rc "$MUT_F2" "$D" "$SID" 'git diff jest.config.ts > /tmp/d.patch')"
  [ "$rc" = "2" ] && ok "(f) mutation control: dropping the same-simple-command rule breaks the git-diff-redirect case" || no "(f) mutation control did not break the case (rc=$rc)"
else
  no "(f) mutation control: could not construct mutant"
fi

# (g) let arm write a file named from a caller-supplied id (the `by`
#     positional) OUTSIDE the `dispatcher --session-id` shape -> a bare,
#     Bash-tool-reachable `arm <by>` call now writes a file named after an
#     ARBITRARY caller-chosen value instead of always $CLAUDE_CODE_SESSION_ID
#     (the exact invariant the AC pins: "arm never writes a file whose name
#     is not its own CLAUDE_CODE_SESSION_ID, or — dispatcher shape only —
#     the explicit --session-id").
MUT_G="$MUT_D/guard-arm-mut-g.sh"
cp "$ARM" "$MUT_G"
python3 - "$MUT_G" <<'PYEOF' 2>/dev/null || true
import sys
p = sys.argv[1]
with open(p) as f:
    c = f.read()
old = '  if [ "$saw_flag" -eq 0 ]; then\n    sid="${CLAUDE_CODE_SESSION_ID:-}"\n  fi\n'
new = '  if [ "$saw_flag" -eq 0 ]; then\n    sid="$by"\n  fi\n'
assert old in c, "anchor not found for mutation (g)"
c = c.replace(old, new, 1)
with open(p, 'w') as f:
    f.write(c)
PYEOF
if [ -s "$MUT_G" ] && ! cmp -s "$ARM" "$MUT_G" && bash -n "$MUT_G" 2>/dev/null; then
  MUT_G_D="$(mktemp -d)"
  CLAUDE_PROJECT_DIR="$MUT_G_D" CLAUDE_CODE_SESSION_ID=B bash "$MUT_G" arm FOREIGN-CALLER-ID >/dev/null 2>&1
  if [ -e "$MUT_G_D/.supervisor/guard/FOREIGN-CALLER-ID.json" ] && [ ! -e "$MUT_G_D/.supervisor/guard/B.json" ]; then
    ok "(g) mutation control: a bare tool-reachable 'arm <by>' now names the marker from the caller-supplied value, not the session id"
  else
    no "(g) mutation control did not break the own-id-only invariant"
  fi
  rm -rf "$MUT_G_D"
else
  no "(g) mutation control: could not construct mutant"
fi

# (h) drop the namespace-colon requirement from arm-from-payload -> the
#     my-worker case fails (now arms on an unnamespaced suffix match)
MUT_H="$MUT_D/guard-arm-mut-h.sh"
cp "$ARM" "$MUT_H"
python3 - "$MUT_H" <<'PYEOF' 2>/dev/null || true
import sys
p = sys.argv[1]
with open(p) as f:
    c = f.read()
old = '    *:worker|*:execute-manager|*:supervisor-runner|*:review-pr-runner) ;;\n'
new = '    *worker|*execute-manager|*supervisor-runner|*review-pr-runner) ;;\n'
assert old in c, "anchor not found for mutation (h)"
c = c.replace(old, new, 1)
with open(p, 'w') as f:
    f.write(c)
PYEOF
if [ -s "$MUT_H" ] && ! cmp -s "$ARM" "$MUT_H" && bash -n "$MUT_H" 2>/dev/null; then
  MUT_H_D="$(mktemp -d)"
  printf '%s' "$(jq -n '{session_id:"sess-h", tool_input:{subagent_type:"my-worker"}}')" | CLAUDE_PROJECT_DIR="$MUT_H_D" bash "$MUT_H" arm-from-payload >/dev/null 2>&1
  if [ -e "$MUT_H_D/.supervisor/guard/sess-h.json" ]; then
    ok "(h) mutation control: dropping the namespace-colon requirement arms on unnamespaced my-worker"
  else
    no "(h) mutation control did not break the my-worker case"
  fi
  rm -rf "$MUT_H_D"
else
  no "(h) mutation control: could not construct mutant"
fi

rm -f /tmp/.guard-test-stderr.$$
rm -rf "$D" "$EMPTY_D" "$FOREIGN_D" "$ARM_D" "$PRUNE_D" "$CONC_D" "$MUT_D"

echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
