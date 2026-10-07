#!/usr/bin/env bash
# test-guard-finalize-publish.sh — static suite for guard-finalize-publish.sh (automate-followups/33
# Part B): the FINALIZE point 5 marker writer and the fail-CLOSED PreToolUse[Bash] publish guard.
#
# Every case runs in a mktemp git repo with a hand-built `.supervisor/state.md` + session log; the
# guard is driven with CLAUDE_PROJECT_DIR pointed at it and a synthetic PreToolUse[Bash] payload on
# stdin. No network, no gh, no Docker. bash 3.2 / BSD userland safe.
#
# Covers (V3): push before the check -> denied (exit 2 + permissionDecision deny); gh pr create and
# chained `cd … && git push` / `git -C … push` forms -> denied; after a passing check -> allowed; HEAD
# moved after the check -> denied; --skip-children-check -> allowed and recorded `skipped`;
# non-Supervisor session / terminal session / drain push from another branch / non-publish command
# -> allowed; the inert path needs no jq; session join via the log-owner cc_session_id (state.md
# plugin id != payload id, owner == payload id -> ACTIVE); a resumed run (owner != payload id) ->
# still denied (the documented B2 choice); the writer refuses on `unsettled` (no marker) and removes
# a stale marker; the hooks.json leaf exists with NO `|| true`; MUTATION CONTROL: removing the marker
# check flips "push before check" to allowed.
#
# EXPLICIT LIMIT: this pins the script and its wiring; it cannot prove the installed runtime loads the
# leaf (hooks load from the installed plugin version).

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$HERE/guard-finalize-publish.sh"
HOOKS="$HERE/../hooks/hooks.json"
REALBASH="$(command -v bash)"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }
for c in jq git; do command -v "$c" >/dev/null 2>&1 || { echo "FATAL $c required" >&2; exit 1; }; done
[ -f "$GUARD" ] || { echo "FATAL missing $GUARD" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/guard-finalize-publish.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PSID="plugsess-0001"
BR="feature/x"
# new_repo <status> [owner_cc_sid] — repo on $BR with a ## Session block and a session log whose
# first line names the owner cc_session_id.
new_repo() {
  local st="$1" owner="${2:-cc-uuid-1}" d
  d="$(mktemp -d "$TMP/repo.XXXXXX")"
  ( cd "$d" && git init -q . && git config user.email t@e.x && git config user.name t \
      && echo a > a && git add a && git commit -qm init && git branch -M "$BR" ) >/dev/null 2>&1
  mkdir -p "$d/.supervisor/logs"
  printf '# State\n\n## Session\n- session_id: %s\n- branch: %s\n- status: %s\n\n## Config\n- status: running\n' \
    "$PSID" "$BR" "$st" > "$d/.supervisor/state.md"
  printf '{"event":"session_start","session_id":"%s","cc_session_id":"%s"}\n' "$PSID" "$owner" > "$d/.supervisor/logs/$PSID.jsonl"
  printf '%s' "$d"
}
settle_children() { printf '{"event":"agent_identity","agent_id":"c1"}\n{"event":"agent_lifecycle","state":"ended","agent_id":"c1","seam":"subagent_stop"}\n' >> "$1/.supervisor/logs/$PSID.jsonl"; }
hang_child() { printf '{"event":"agent_identity","agent_id":"c2"}\n' >> "$1/.supervisor/logs/$PSID.jsonl"; }
payload() { jq -n -c --arg c "$1" --arg s "${2:-cc-uuid-1}" '{session_id:$s, hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:$c}}'; }
# run_guard <repo> <command> [payload_sid] [script] -> sets RC / OUT
run_guard() {
  local s="${4:-$GUARD}"
  OUT="$(payload "$2" "${3:-cc-uuid-1}" | CLAUDE_PROJECT_DIR="$1" "$REALBASH" "$s" 2>/dev/null)"; RC=$?
}
write_marker() { WOUT="$(cd "$1" && CLAUDE_PROJECT_DIR="$1" "$REALBASH" "$GUARD" write-marker ${2:-} 2>/dev/null)"; WRC=$?; }
expect() { # expect <label> <want rc> [reason substring]
  if [ "$RC" = "$2" ] && { [ -z "${3:-}" ] || printf '%s' "$OUT" | grep -qF -- "$3"; }; then ok "$1"
  else no "$1 (rc=$RC want $2; out=$OUT)"; fi
}

echo "== non-Supervisor / inert paths =="
R0="$(mktemp -d "$TMP/plain.XXXXXX")"
run_guard "$R0" "git push origin main"; expect "no state.md -> push allowed" 0
OUT="$(payload "git push" | CLAUDE_PROJECT_DIR="$R0" PATH="/nonexistent" "$REALBASH" "$GUARD" 2>/dev/null)"; RC=$?
expect "inert path needs no jq (empty PATH) -> allowed" 0
RT="$(new_repo done)"
run_guard "$RT" "git push"; expect "terminal session status -> allowed" 0
RS="$(new_repo running)"
run_guard "$RS" "git status && echo push"; expect "non-publish command mentioning push -> allowed" 0

echo "== push / PR before the check -> denied =="
run_guard "$RS" "git push -u origin $BR"; expect "git push before check -> denied" 2 "run FINALIZE point 5 first"
printf '%s' "$OUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 \
  && ok "deny carries permissionDecision: deny JSON" || no "deny JSON shape"
run_guard "$RS" "gh pr create --title t --body b"; expect "gh pr create before check -> denied" 2
run_guard "$RS" "cd /tmp && git push origin HEAD"; expect "chained cd && git push -> denied" 2
run_guard "$RS" "GIT_TRACE=0 git -C . push"; expect "VAR= git -C . push -> denied" 2
run_guard "$RS" "git push" "cc-uuid-1"; expect "join: owner == payload sid -> active, reason names this session" 2 "this session"

echo "== marker writer =="
hang_child "$RS"
write_marker "$RS"
[ "$WRC" = 1 ] && [ ! -e "$RS/.supervisor/logs/$PSID.finalize-gate" ] \
  && ok "writer refuses on unsettled children -> exit 1, no marker" || no "writer on unsettled: rc=$WRC out=$WOUT"
RA="$(new_repo running)"; settle_children "$RA"
write_marker "$RA"
MK="$RA/.supervisor/logs/$PSID.finalize-gate"
[ "$WRC" = 0 ] && [ "$(jq -r .children_check "$MK" 2>/dev/null)" = "settled" ] \
  && [ "$(jq -r .head_sha "$MK")" = "$(git -C "$RA" rev-parse HEAD)" ] \
  && ok "writer on settled children -> marker {children_check: settled, head_sha: HEAD}" || no "writer on settled: rc=$WRC out=$WOUT"
run_guard "$RA" "git push -u origin $BR"; expect "push after a passing check -> allowed" 0
run_guard "$RA" "gh pr create --fill"; expect "gh pr create after a passing check -> allowed" 0
( cd "$RA" && echo b > b && git add b && git commit -qm two ) >/dev/null 2>&1
run_guard "$RA" "git push"; expect "HEAD moved after the check -> denied" 2 "HEAD moved"
hang_child "$RA"
write_marker "$RA"
[ "$WRC" = 1 ] && [ ! -e "$MK" ] && ok "re-run on unsettled removes the stale marker" || no "stale marker kept: rc=$WRC"
write_marker "$RA" --skip-children-check
[ "$WRC" = 0 ] && [ "$(jq -r .children_check "$MK" 2>/dev/null)" = "skipped" ] \
  && ok "--skip-children-check -> marker recorded children_check: skipped" || no "skip marker: rc=$WRC out=$WOUT"
run_guard "$RA" "git push"; expect "push after --skip-children-check -> allowed" 0
RN="$(new_repo done)"; write_marker "$RN"
[ "$WRC" = 1 ] && printf '%s' "$WOUT" | grep -q no_active_session && ok "writer refuses with no active session" || no "writer no session: $WOUT"

echo "== scope: drain / other-branch push, session join, resumed run =="
RD="$(new_repo running)"
( cd "$RD" && git checkout -qb fix/drain ) >/dev/null 2>&1
run_guard "$RD" "git push origin fix/drain"; expect "push from a branch other than the run's feature branch -> allowed" 0
RJ="$(new_repo running cc-uuid-9)"
run_guard "$RJ" "git push" "cc-uuid-9"; expect "plugin id != payload id but log owner == payload id -> guard ACTIVE" 2 "this session"
run_guard "$RJ" "git push" "cc-uuid-new"; expect "resumed run (owner != payload id) -> still denied (B2 decision)" 2 "resumed run"
settle_children "$RJ"; write_marker "$RJ"
run_guard "$RJ" "git push" "cc-uuid-new"; expect "resumed run after a passing check -> allowed" 0

echo "== wiring =="
leaf="$(jq -r '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | .command | select(test("guard-finalize-publish.sh"))' "$HOOKS" 2>/dev/null)"
if [ -n "$leaf" ] && ! printf '%s' "$leaf" | grep -q '|| true'; then
  ok "hooks.json PreToolUse[Bash] leaf invokes guard-finalize-publish.sh with NO || true"
else
  no "hooks.json leaf missing or carries || true: '$leaf'"
fi
grep -q 'loom-log-owner.sh' "$GUARD" && grep -q 'loom-log-owner.sh' "$HERE/emit-lifecycle.sh" \
  && ! grep -q '_first="\$(head -1' "$GUARD" \
  && ok "session join sources the shared loom_log_owner rule (not restated)" || no "loom_log_owner not shared"

echo "== (m) mutation control =="
MUT="$TMP/mutant.sh"
sed 's/^\[ -f "\$MARKER" \] || deny/[ -f "$MARKER" ] || allow #/' "$GUARD" > "$MUT"
cp "$HERE/loom-log-owner.sh" "$TMP/" ; cp "$HERE/check-children-settled.sh" "$TMP/"
if cmp -s "$MUT" "$GUARD"; then
  no "mutation control: marker-check line not found, control inconclusive"
else
  RM="$(new_repo running)"
  run_guard "$RM" "git push" cc-uuid-1 "$MUT"
  [ "$RC" = 0 ] && ok "mutation control: removing the marker check flips 'push before check' to allowed" \
    || no "mutation control: mutant still rc=$RC — the marker check is vacuous"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
