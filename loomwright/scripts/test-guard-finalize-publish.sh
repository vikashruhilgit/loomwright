#!/usr/bin/env bash
# test-guard-finalize-publish.sh — static suite for guard-finalize-publish.sh (automate-followups/33
# Part B): the FINALIZE point 5 marker writer and the fail-CLOSED PreToolUse[Bash] publish guard.
#
# Every case runs in a mktemp git repo with a hand-built `.supervisor/state.md` + session log; the
# guard is driven with CLAUDE_PROJECT_DIR pointed at it and a synthetic PreToolUse[Bash] payload on
# stdin. No network, no gh, no Docker. bash 3.2 / BSD userland safe.
#
# Covers (V3): push before the check -> denied (exit 2 + permissionDecision deny); gh pr create and
# chained `cd … && git push` / `git -C … push` forms and git/gh GLOBAL options before the subcommand
# (`git --no-pager push`, `gh -R o/r pr create`) -> denied, with a fixed-regex mutation control;
# after a passing check -> allowed; HEAD moved after the check -> denied; --skip-children-check -> allowed and recorded `skipped`;
# non-Supervisor session / terminal session / drain push from another branch / non-publish command
# -> allowed; the inert path needs no jq; session join via the log-owner cc_session_id (state.md
# plugin id != payload id, owner == payload id -> ACTIVE); another session (owner != payload id) ->
# allowed (B2 narrowed, 2026-11-12 — see the "scope by publish target and owner" block); the writer refuses on `unsettled` (no marker) and removes
# a stale marker; the hooks.json leaf exists with NO `|| true`; MUTATION CONTROL: removing the marker
# check flips "push before check" to allowed.
# Hardening (fix-now re-pass): F2 a missing session log -> writer refuses, no marker; zero identity
# rows -> marker `no_identity_rows` (never `settled`) that the guard accepts. F3 a linked-worktree
# project dir finds the main worktree's `.supervisor/` (guard ACTIVE, write-marker writes there); the
# detached review-drain sibling stays allowed; bold-format state.md is read. F4 wrapper / nesting /
# quoting / continuation forms of a publish -> denied, non-publish look-alikes -> allowed. Each fix
# has a mutation control that removes it and watches its cases flip.
# Re-drain round 1: redirections — a redirect's `&` (`2>&1`, `>&2`, `&>f`) never cuts a segment and
# redirect words (`>/dev/null`, `2>err.log`) never stand in for the subcommand, so `git 2>&1 push` /
# `gh 2>&1 pr create` are denied while a real background `x & git push` still splits and
# `git stash push 2>&1` stays allowed; two mutation controls (no AMP swap, no redirect tokenizing).
# expect-id (agnostic-phase1/02): a worker id recorded under state.md's `## Worker Results` with no
# terminal row -> writer refuses children_unsettled, no marker, even with no agent_identity row; its
# terminal row -> settled; an explicit `--expect-id` arg is checked too; `--skip-children-check` works
# in any position; an unknown argument refuses bad_args; a mutation control drops the recorded ids.
# worker_results_unparsed (fix-now, owner decision): the heading, `agent_id:` bullet, `worker_id:`,
# pipe-separated bold bullet and YAML-continuation shapes each yield their id; a table-only section
# (and a table row carrying the key) refuses worker_results_unparsed, removing a stale marker and
# writing none; an empty / `(empty)` section is unchanged; `--skip-children-check` still writes
# `skipped`; a mutation control drops the refusal and watches the table-only case pass again.
# #717: label headings (`### worker-1`, `### subtask-1-worker`) beside settled real ids in a log WITH
# identity rows -> marker settled, labels listed under ignored_worker_result_labels; an unsettled
# identity row, an id-shaped heading with no row (either case), and a label with NO identity rows still refuse;
# a mutation control expects the labels again and watches the settled run refuse.
#
# HARNESS RULE: never pipe a producer into the guard — the inert paths exit 0 without reading stdin,
# so a piped `jq` can hit EPIPE and pipefail turns that race into a spurious rc 2/141; build the
# payload into a variable and feed it with a here-string (`<<<"$p"`).
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
  local s="${4:-$GUARD}" p
  p="$(payload "$2" "${3:-cc-uuid-1}")"
  OUT="$(CLAUDE_PROJECT_DIR="$1" "$REALBASH" "$s" 2>/dev/null <<<"$p")"; RC=$?
}
write_marker() { WOUT="$(cd "$1" && CLAUDE_PROJECT_DIR="$1" "$REALBASH" "$GUARD" write-marker ${2:-} 2>/dev/null)"; WRC=$?; }
expect() { # expect <label> <want rc> [reason substring]
  if [ "$RC" = "$2" ] && { [ -z "${3:-}" ] || grep -qF -- "$3" <<<"$OUT"; }; then ok "$1"
  else no "$1 (rc=$RC want $2; out=$OUT)"; fi
}

echo "== non-Supervisor / inert paths =="
R0="$(mktemp -d "$TMP/plain.XXXXXX")"
run_guard "$R0" "git push origin main"; expect "no state.md -> push allowed" 0
P0="$(payload "git push")"
OUT="$(CLAUDE_PROJECT_DIR="$R0" PATH="/nonexistent" "$REALBASH" "$GUARD" 2>/dev/null <<<"$P0")"; RC=$?
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
run_guard "$RS" "cd $RS && git push origin HEAD"; expect "chained cd <run checkout> && git push -> denied" 2
run_guard "$RS" "GIT_TRACE=0 git -C . push"; expect "VAR= git -C . push -> denied" 2
run_guard "$RS" "git push" "cc-uuid-1"; expect "join: owner == payload sid -> active, reason names this session" 2 "this session"

echo "== global options before the publish subcommand -> still denied =="
GLOBAL_DENY_CASES=(
  "git --no-pager push origin main"
  "git -p push"
  "git --git-dir=.git push"
  "git --git-dir .git push"
  "command git --no-pager -C . push"
  "gh -R o/r pr create --fill"
  "gh --repo o/r pr create --fill"
  "gh pr --repo o/r create --fill"
)
for c in "${GLOBAL_DENY_CASES[@]}"; do run_guard "$RS" "$c"; expect "$c -> denied" 2; done
run_guard "$RS" "git --no-pager stash push"; expect "git --no-pager stash push -> allowed" 0
run_guard "$RS" "git stash push -m x"; expect "git stash push -> allowed" 0
run_guard "$RS" "gh --repo o/r pr view 1"; expect "gh --repo o/r pr view -> allowed" 0

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
[ "$WRC" = 1 ] && grep -q no_active_session <<<"$WOUT" && ok "writer refuses with no active session" || no "writer no session: $WOUT"

echo "== scope: drain / other-branch push, session join, resumed run =="
RD="$(new_repo running)"
( cd "$RD" && git checkout -qb fix/drain ) >/dev/null 2>&1
run_guard "$RD" "git push origin fix/drain"; expect "push from a branch other than the run's feature branch -> allowed" 0
RJ="$(new_repo running cc-uuid-9)"
run_guard "$RJ" "git push" "cc-uuid-9"; expect "plugin id != payload id but log owner == payload id -> guard ACTIVE" 2 "this session"
run_guard "$RJ" "git push" "cc-uuid-new"; expect "another session (owner != payload id) -> allowed (B2 narrowed)" 0
settle_children "$RJ"; write_marker "$RJ"
run_guard "$RJ" "git push" "cc-uuid-new"; expect "resumed run after a passing check -> allowed" 0

echo "== scope by publish target and owner: an unrelated session / worktree is not this run (2026-11-12) =="
# The incident: session B (cwd = the run's main checkout, which is on the run's branch) ran
# `cd <its own linked worktree> && git push -u origin <its branch>; gh pr create …` while session A's
# Supervisor run was live, and both were denied as a "resumed run (log owner differs)". Two causes,
# each pinned here and by its own mutation control below: the scope read the PROJECT dir instead of
# the checkout the publish runs in, and every non-owner session was treated as a resumed run.
# run_guard_json <project dir> <payload json> [script] -> RC / OUT
run_guard_json() { OUT="$(CLAUDE_PROJECT_DIR="$1" "$REALBASH" "${3:-$GUARD}" 2>/dev/null <<<"$2")"; RC=$?; }
# payload_full <command> <session id> [cwd] [agent_type] — a PreToolUse[Bash] payload with cwd / agent fields
payload_full() {
  jq -n -c --arg c "$1" --arg s "$2" --arg w "${3:-}" --arg t "${4:-}" \
    '{session_id:$s, hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:$c}}
     + (if $w == "" then {} else {cwd:$w} end)
     + (if $t == "" then {} else {agent_id:"a0123456789abcdef", agent_type:$t} end)'
}
RU="$(new_repo running)"; FWT="$TMP/wt-foreign.$$"
( cd "$RU" && git worktree add -q -b fix/unrelated "$FWT" ) >/dev/null 2>&1
[ -e "$FWT/.git" ] || no "fixture: foreign linked worktree not created"
PLAIN_Q="$(mktemp -d "$TMP/plain-q.XXXXXX")"   # a non-git dir: out of scope on its own
INCIDENT="cd $FWT && git push -q -u origin fix/unrelated 2>&1 | tail -2; gh pr create --base main --head fix/unrelated --title t --body b"
# owner session, publish targets a foreign worktree of the same repo -> allowed (scope alone)
run_guard_json "$RU" "$(payload_full "$INCIDENT" cc-uuid-1 "$RU")"; expect "own session: cd <foreign worktree> && git push; gh pr create -> allowed" 0
run_guard_json "$RU" "$(payload_full "git -C $FWT push origin fix/unrelated" cc-uuid-1 "$RU")"; expect "own session: git -C <foreign worktree> push -> allowed" 0
run_guard_json "$RU" "$(payload_full "git push" cc-uuid-1 "$FWT")"; expect "own session: payload cwd is a foreign worktree (project dir = run checkout) -> allowed" 0
# a foreign SESSION -> allowed, even on the run's own checkout and branch
run_guard_json "$RU" "$(payload_full "$INCIDENT" cc-foreign-9 "$RU")"; expect "foreign session: the incident command -> allowed" 0
run_guard_json "$RU" "$(payload_full "git push -u origin $BR" cc-foreign-9 "$RU")"; expect "foreign session id on the run's checkout + branch -> allowed" 0
# the run's own session / subagent / worker payloads -> still denied without the marker
run_guard_json "$RU" "$(payload_full "git push -u origin $BR" cc-uuid-1 "$RU")"; expect "own session on the run checkout -> denied" 2 "this session"
run_guard_json "$RU" "$(payload_full "git push -u origin $BR" cc-uuid-1 "$RU" loomwright:loomwright:supervisor-runner)"; expect "own subagent payload (agent_type set, parent session id) -> denied" 2
run_guard_json "$RU" "$(payload_full "gh pr create --fill" cc-uuid-1 "$RU" loomwright:loomwright:worker)"; expect "own worker payload gh pr create -> denied" 2
run_guard_json "$FWT" "$(payload_full "cd $RU && git push" cc-uuid-1 "$FWT")"; expect "own session: cd <run checkout> from a foreign worktree -> denied" 2
# every publish counts, and a subshell's cd never leaks out
run_guard_json "$RU" "$(payload_full "cd $FWT && git push; cd $RU && git push" cc-uuid-1 "$RU")"; expect "own session: second publish back in the run checkout -> denied" 2
run_guard_json "$RU" "$(payload_full "(cd $FWT && git status); git push" cc-uuid-1 "$RU")"; expect "own session: (cd foreign) restores the dir, then git push -> denied" 2
run_guard_json "$RU" "$(payload_full "echo \$(cd $FWT && pwd) && git push" cc-uuid-1 "$RU")"; expect "own session: \$(cd foreign) restores the dir -> denied" 2
run_guard_json "$RU" "$(payload_full "bash -c 'cd $FWT && git push'; git push" cc-uuid-1 "$RU")"; expect "own session: bash -c's cd does not leak -> denied" 2
run_guard_json "$RU" "$(payload_full "bash -c 'git -C $FWT push'" cc-uuid-1 "$RU")"; expect "own session: bash -c 'git -C foreign push' starts in the segment's dir -> allowed" 0
# (a quoted `cd x && git push` is split before quotes are read — deny-leaning, see the header)
# a QUOTED paren never moves the subshell stack, and makes the target unknown (PR #897 review): the
# `:)` used to pop `( cd <run> …` early, so the push inside the subshell was judged at the outer dir
QUOTED_PAREN_CASES=(
  "(cd $RU && git commit -m \"Looks good :)\" ; git push)"
  "(cd $RU && git commit -m 'see note)' ; git push)"
  "echo \"\$(cd $PLAIN_Q)\"; git push"
)
for c in "${QUOTED_PAREN_CASES[@]}"; do run_guard_json "$RU" "$(payload_full "$c" cc-uuid-1 "$PLAIN_Q")"; expect "own session, quoted paren [$c] -> denied" 2; done
run_guard_json "$RU" "$(payload_full "(cd $FWT && git commit -m \"fix(x): y\"; git push)" cc-uuid-1 "$RU")"; expect "own session, quoted paren in a foreign-worktree push -> denied (fail CLOSED, needs the marker)" 2
# unknown targets fail CLOSED
UNKNOWN_CASES=(
  'cd "$WT" && git push'
  'cd $(git rev-parse --show-toplevel) && git push'
  'cd - && git push'
  "cd $TMP/no-such-dir.$$ ; git push"
  'GIT_DIR=/x/.git git push'
  "git --work-tree=$FWT push"
  "env -C $FWT git push"
  'popd; git push'
  'pushd; git push'
  'pushd -q; git push'
)
for c in "${UNKNOWN_CASES[@]}"; do run_guard_json "$FWT" "$(payload_full "$c" cc-uuid-1 "$FWT")"; expect "own session, unknown target [$c] -> denied" 2; done
# another repository on the same branch name, and a plain non-git dir -> allowed
OTHER="$(mktemp -d "$TMP/other.XXXXXX")"
( cd "$OTHER" && git init -q . && git config user.email t@e.x && git config user.name t \
    && echo a > a && git add a && git commit -qm init && git branch -M "$BR" ) >/dev/null 2>&1
run_guard_json "$RU" "$(payload_full "cd $OTHER && git push -u origin $BR" cc-uuid-1 "$RU")"; expect "own session: another repo on the same branch name -> allowed" 0
PLAIN="$(mktemp -d "$TMP/plain-dir.XXXXXX")"
run_guard_json "$RU" "$(payload_full "cd $PLAIN && git push" cc-uuid-1 "$RU")"; expect "own session: a non-git dir -> allowed" 0
# the run-creation seed wins over a foreign first log line (close-stranded-run.sh's precedence)
RSD="$(new_repo running cc-foreign-appender)"
printf 'cc_session_id=cc-uuid-1\nsession_id=%s\nstarted_at=2026-11-12T00:00:00Z\n' "$PSID" > "$RSD/.supervisor/logs/$PSID.owner"
run_guard_json "$RSD" "$(payload_full "git push" cc-uuid-1 "$RSD")"; expect "seed owner == payload id (log first line foreign) -> denied" 2 "this session"
run_guard_json "$RSD" "$(payload_full "git push" cc-foreign-appender "$RSD")"; expect "log-first-line session that is not the seed owner -> allowed" 0
# owner unknown / payload id missing -> adopted, denied
RUK="$(new_repo running)"; : > "$RUK/.supervisor/logs/$PSID.jsonl"
run_guard_json "$RUK" "$(payload_full "git push" cc-anyone "$RUK")"; expect "owner unknown (empty log, no seed) -> adopted, denied" 2 "owner unknown"
run_guard_json "$RU" "$(jq -n -c --arg c "git push" '{hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:$c}}')"; expect "payload with no session_id -> denied" 2
# after a passing check, the own session's publish from the run checkout is allowed
settle_children "$RU"; write_marker "$RU"
run_guard_json "$RU" "$(payload_full "git push -u origin $BR" cc-uuid-1 "$RU")"; expect "own session after a passing check -> allowed" 0

echo "== F2: write-marker never turns 'nothing to check' or 'no log' into settled =="
RL="$(new_repo running)"; rm -f "$RL/.supervisor/logs/$PSID.jsonl"
write_marker "$RL"
[ "$WRC" = 1 ] && grep -q session_log_missing <<<"$WOUT" && [ ! -e "$RL/.supervisor/logs/$PSID.finalize-gate" ] \
  && ok "missing session log -> writer refuses session_log_missing, no marker" || no "missing log: rc=$WRC out=$WOUT"
RI="$(new_repo running)"    # session_start only: zero agent_identity rows
write_marker "$RI"
[ "$WRC" = 0 ] && [ "$(jq -r .children_check "$RI/.supervisor/logs/$PSID.finalize-gate" 2>/dev/null)" = "no_identity_rows" ] \
  && ok "no identity rows -> marker children_check: no_identity_rows (never settled)" || no "no_identity_rows marker: rc=$WRC out=$WOUT"
run_guard "$RI" "git push"; expect "guard accepts a no_identity_rows marker at HEAD" 0

echo "== expect-id: recorded worker ids are checked even with no agent_identity row (agnostic-phase1/02) =="
# record_worker <repo> <worker-id> — a `## Worker Results` entry as Context-Keeper's record_worker_result writes it
record_worker() { printf '\n## Worker Results\n### %s (1)\n- files_modified: [a]\n- lines: +1 -0\n' "$2" >> "$1/.supervisor/state.md"; }
REX="$(new_repo running)"; record_worker "$REX" "w-recorded"     # session_start only: no identity row, no terminal row
write_marker "$REX"
[ "$WRC" = 1 ] && grep -q children_unsettled <<<"$WOUT" && grep -q '"w-recorded"' <<<"$WOUT" \
  && [ ! -e "$REX/.supervisor/logs/$PSID.finalize-gate" ] \
  && ok "expect-id: a recorded worker id with no terminal row -> writer refuses children_unsettled naming it, no marker (never no_identity_rows)" \
  || no "expect-id: recorded unsettled worker: rc=$WRC out=$WOUT"
printf '{"event":"subtask_complete","agent_id":"w-recorded","result_block_present":true}\n' >> "$REX/.supervisor/logs/$PSID.jsonl"
write_marker "$REX"
[ "$WRC" = 0 ] && [ "$(jq -r .children_check "$REX/.supervisor/logs/$PSID.finalize-gate" 2>/dev/null)" = "settled" ] \
  && ok "expect-id: the recorded worker's terminal row lands (still no identity row) -> marker settled" \
  || no "expect-id: recorded settled worker: rc=$WRC out=$WOUT"
WOUT="$(cd "$RI" && CLAUDE_PROJECT_DIR="$RI" "$REALBASH" "$GUARD" write-marker --expect-id w-explicit 2>/dev/null)"; WRC=$?
[ "$WRC" = 1 ] && grep -q children_unsettled <<<"$WOUT" && grep -q '"w-explicit"' <<<"$WOUT" \
  && ok "expect-id: an explicit --expect-id arg with no terminal row -> writer refuses children_unsettled" \
  || no "expect-id: explicit --expect-id: rc=$WRC out=$WOUT"
WOUT="$(cd "$RI" && CLAUDE_PROJECT_DIR="$RI" "$REALBASH" "$GUARD" write-marker --expect-id w-explicit --skip-children-check 2>/dev/null)"; WRC=$?
[ "$WRC" = 0 ] && [ "$(jq -r .children_check "$RI/.supervisor/logs/$PSID.finalize-gate" 2>/dev/null)" = "skipped" ] \
  && ok "expect-id: --skip-children-check after another flag still skips (any argument position)" \
  || no "expect-id: skip in second position: rc=$WRC out=$WOUT"
WOUT="$(cd "$RI" && CLAUDE_PROJECT_DIR="$RI" "$REALBASH" "$GUARD" write-marker --skip-children-chek 2>/dev/null)"; WRC=$?
# the previous call left a valid `skipped` marker: a bad_args refusal must still remove it first
[ "$WRC" = 1 ] && grep -q bad_args <<<"$WOUT" && [ ! -e "$RI/.supervisor/logs/$PSID.finalize-gate" ] \
  && ok "expect-id: an unknown write-marker argument (a misspelt flag) refuses bad_args AND removes the stale marker" \
  || no "expect-id: unknown arg: rc=$WRC out=$WOUT"
WOUT="$(cd "$RI" && CLAUDE_PROJECT_DIR="$RI" "$REALBASH" "$GUARD" write-marker --skip-children-check 2>/dev/null)"; WRC=$?
[ "$WRC" = 0 ] && [ -f "$RI/.supervisor/logs/$PSID.finalize-gate" ] || no "fixture: re-seed skipped marker: rc=$WRC out=$WOUT"
WOUT="$(cd "$RI" && CLAUDE_PROJECT_DIR="$RI" "$REALBASH" "$GUARD" write-marker --expect-id 2>/dev/null)"; WRC=$?
[ "$WRC" = 1 ] && grep -q bad_args <<<"$WOUT" && [ ! -e "$RI/.supervisor/logs/$PSID.finalize-gate" ] \
  && ok "expect-id: a trailing --expect-id with no value refuses bad_args AND removes the stale marker" \
  || no "expect-id: valueless --expect-id: rc=$WRC out=$WOUT"

echo "== expect-id: a labelled Worker Results heading yields the id, not the label =="
# heading text after `### ` (record_worker appends ` (1)`) | the id the writer must name
LABEL_CASES=(
  "Worker w-lab1|w-lab1"
  "worker: w-lab2|w-lab2"
  "AGENT w-lab3|w-lab3"
  "agent:w-lab4|w-lab4"
  "**Worker** \`w-lab5\`|w-lab5"
  "w-plain|w-plain"
  "Worker|Worker"
)
for lc in "${LABEL_CASES[@]}"; do
  head_txt="${lc%|*}"; want="${lc##*|}"
  RLB="$(new_repo running)"; record_worker "$RLB" "$head_txt"
  write_marker "$RLB"
  if [ "$WRC" = 1 ] && grep -q children_unsettled <<<"$WOUT" && grep -q "\"$want\"" <<<"$WOUT" \
     && { [ "$want" = Worker ] || ! grep -q '"Worker"\|"worker:"\|"AGENT"\|"agent:' <<<"$WOUT"; }; then
    ok "labelled heading '### $head_txt (1)' -> expected id $want"
  else
    no "labelled heading '### $head_txt (1)': rc=$WRC out=$WOUT"
  fi
done

echo "== worker_results_unparsed: real-run Worker Results shapes (read or refused, never silently empty) =="
# record_section <repo> <body> — a `## Worker Results` section with a verbatim body, then a following section
record_section() { printf '\n## Worker Results\n%s\n\n## Error Log\n| # | Phase | Error |\n' "$2" >> "$1/.supervisor/state.md"; }
TABLE_SECTION='| Worker | Subtask | Status |
| ac5cbd23 | 2 | completed |'
# label | section body | id the writer must name in children_unsettled (no terminal row exists for it)
SHAPE_CASES=(
  "heading form (unchanged)|### w-head (1)
- files_modified: [a]|w-head"
  "agent_id: bullet|- agent_id: w-bullet
  - status: completed|w-bullet"
  "worker_id: bullet|- Worker_ID: \`w-wid\`|w-wid"
  "pipe-separated bold bullet|- **subtask: 1** | agent_id: w-pipe | status: completed | files: 10|w-pipe"
  "YAML-style continuation key|- subtask: 1
  agent_id: w-yaml
  status: completed|w-yaml"
)
for sc in "${SHAPE_CASES[@]}"; do
  label="${sc%%|*}"; rest="${sc#*|}"; want="${rest##*|}"; body="${rest%|*}"
  RSH="$(new_repo running)"; record_section "$RSH" "$body"
  write_marker "$RSH"
  if [ "$WRC" = 1 ] && grep -q children_unsettled <<<"$WOUT" && grep -q "\"$want\"" <<<"$WOUT" \
     && [ ! -e "$RSH/.supervisor/logs/$PSID.finalize-gate" ]; then
    ok "shape: $label -> expected id $want read (children_unsettled, no marker)"
  else
    no "shape: $label: rc=$WRC out=$WOUT"
  fi
done
# a key glued to a preceding word is not the key (parent_agent_id:) — the section then has no id
RPG="$(new_repo running)"; record_section "$RPG" "- parent_agent_id: w-parent"
write_marker "$RPG"
[ "$WRC" = 1 ] && grep -q worker_results_unparsed <<<"$WOUT" && ! grep -q w-parent <<<"$WOUT" \
  && ok "shape: parent_agent_id: is not read as agent_id: (section refused worker_results_unparsed)" \
  || no "shape: parent_agent_id: rc=$WRC out=$WOUT"
# table-only section: zero ids from non-empty content -> refused, stale marker removed first, no marker
RTB="$(new_repo running)"; record_section "$RTB" "$TABLE_SECTION"
write_marker "$RTB" --skip-children-check     # seed a valid stale marker the refusal must remove
[ "$WRC" = 0 ] && [ -f "$RTB/.supervisor/logs/$PSID.finalize-gate" ] || no "fixture: seed skipped marker: rc=$WRC out=$WOUT"
write_marker "$RTB"
[ "$WRC" = 1 ] && [ "$(jq -r '.status + ":" + .reason' <<<"$WOUT" 2>/dev/null)" = "refused:worker_results_unparsed" ] \
  && [ ! -e "$RTB/.supervisor/logs/$PSID.finalize-gate" ] \
  && ok "table-only Worker Results section -> refused worker_results_unparsed, stale marker removed, no marker written" \
  || no "table-only section: rc=$WRC out=$WOUT"
# a table row carrying the key form is still a table row (not parsed)
RTK="$(new_repo running)"; record_section "$RTK" "| agent_id: w-cell | 1 | completed |"
write_marker "$RTK"
[ "$WRC" = 1 ] && grep -q worker_results_unparsed <<<"$WOUT" \
  && ok "a table row carrying agent_id: is not parsed -> refused worker_results_unparsed" \
  || no "table row with key: rc=$WRC out=$WOUT"
# the escape hatch still works on an unparsed section
write_marker "$RTB" --skip-children-check
[ "$WRC" = 0 ] && [ "$(jq -r .children_check "$RTB/.supervisor/logs/$PSID.finalize-gate" 2>/dev/null)" = "skipped" ] \
  && ok "--skip-children-check on an unparsed section -> marker children_check: skipped" \
  || no "skip on unparsed section: rc=$WRC out=$WOUT"
# empty / placeholder-only sections keep today's behaviour (no expected ids -> no_identity_rows)
for eb in "(empty)" "_(empty)_" "" "   "; do
  REM="$(new_repo running)"; record_section "$REM" "$eb"
  write_marker "$REM"
  [ "$WRC" = 0 ] && [ "$(jq -r .children_check "$REM/.supervisor/logs/$PSID.finalize-gate" 2>/dev/null)" = "no_identity_rows" ] \
    && ok "Worker Results section body '$eb' -> unchanged (marker no_identity_rows)" \
    || no "empty section '$eb': rc=$WRC out=$WOUT"
done

echo "== #717: a label heading is not an expected id when identity rows record the spawns =="
# settle_real <repo> <id>... — an identity row plus a terminal row for each real agent id
settle_real() { local r="$1" i; shift; for i in "$@"; do printf '{"event":"agent_identity","agent_id":"%s"}\n{"event":"subtask_complete","agent_id":"%s","result_block_present":true}\n' "$i" "$i" >> "$r/.supervisor/logs/$PSID.jsonl"; done; }
REAL1=a4058c536893f25cd; REAL2=aab4fa0cd08c63928; REAL3=af2afe61c9c94cb32
for lbls in "subtask-1-worker subtask-2-worker subtask-3-worker" "worker-1 worker-2 worker-3"; do
  R717="$(new_repo running)"; settle_real "$R717" "$REAL1" "$REAL2" "$REAL3"
  body=""; n=0; for l in $lbls; do n=$((n+1)); body="$body### $l (subtask-$n)
- status: completed
"; done
  record_section "$R717" "$body"
  write_marker "$R717"
  MK717="$R717/.supervisor/logs/$PSID.finalize-gate"
  [ "$WRC" = 0 ] && ! grep -q children_unsettled <<<"$WOUT" \
    && [ "$(jq -r .children_check "$MK717" 2>/dev/null)" = settled ] \
    && [ "$(jq -r '.ignored_worker_result_labels | join(" ")' "$MK717" 2>/dev/null)" = "$lbls" ] \
    && ok "#717: '$lbls' headings + settled real ids -> marker settled, labels recorded as ignored" \
    || no "#717: '$lbls': rc=$WRC out=$WOUT"
done
# fail-CLOSED controls: the label rule must not hide a real unsettled child
R717U="$(new_repo running)"; settle_real "$R717U" "$REAL1"; hang_child "$R717U"
record_section "$R717U" "### worker-1 (subtask-1)"
write_marker "$R717U"
[ "$WRC" = 1 ] && grep -q children_unsettled <<<"$WOUT" && grep -q '"c2"' <<<"$WOUT" \
  && [ "$(jq -r '.ignored_worker_result_labels[0]' <<<"$WOUT" 2>/dev/null)" = worker-1 ] \
  && ok "#717: a dropped label never hides an unsettled identity row (refused naming c2, label listed)" \
  || no "#717: unsettled identity row with a label: rc=$WRC out=$WOUT"
R717I="$(new_repo running)"; settle_real "$R717I" "$REAL1"
record_section "$R717I" "### a0123456789abcdef (subtask-2)"
write_marker "$R717I"
[ "$WRC" = 1 ] && grep -q children_unsettled <<<"$WOUT" && grep -q '"a0123456789abcdef"' <<<"$WOUT" \
  && ok "#717: an id-shaped heading with no log row stays expected (refused children_unsettled)" \
  || no "#717: id-shaped unknown heading: rc=$WRC out=$WOUT"
R717C="$(new_repo running)"; settle_real "$R717C" "$REAL1"
record_section "$R717C" "### A1B2C3D4E5F6A7B8C (subtask-2)"   # an id transcribed in upper case
write_marker "$R717C"
[ "$WRC" = 1 ] && grep -q children_unsettled <<<"$WOUT" && grep -q '"A1B2C3D4E5F6A7B8C"' <<<"$WOUT" \
  && ok "#717: an upper-case id-shaped heading with no log row stays expected (case-insensitive hex test)" \
  || no "#717: upper-case id-shaped heading: rc=$WRC out=$WOUT"
R717N="$(new_repo running)"; record_section "$R717N" "### worker-1 (subtask-1)"   # no identity rows at all
write_marker "$R717N"
[ "$WRC" = 1 ] && grep -q children_unsettled <<<"$WOUT" && grep -q '"worker-1"' <<<"$WOUT" \
  && ok "#717: with no identity rows a label heading stays expected (agnostic-phase1/02 unchanged)" \
  || no "#717: label with no identity rows: rc=$WRC out=$WOUT"

echo "== F3: .supervisor/ is found from a linked worktree; detached sibling + bold state.md =="
RW="$(new_repo running)"; WT="$TMP/wt-linked.$$"; SIB="$TMP/wt-sibling.$$"
( cd "$RW" && git checkout -qb other && git worktree add -q "$WT" "$BR" && git worktree add -q --detach "$SIB" HEAD ) >/dev/null 2>&1
[ -d "$WT/.git" ] || [ -f "$WT/.git" ] || no "fixture: linked worktree not created"
[ ! -e "$WT/.supervisor" ] && ok "fixture: linked worktree has no .supervisor of its own" || no "fixture: linked worktree has .supervisor"
run_guard "$WT" "git push -u origin $BR"; expect "linked-worktree project dir on the run branch -> guard ACTIVE, denied without marker" 2 "run FINALIZE point 5 first"
run_guard "$SIB" "git push origin HEAD:$BR"; expect "detached sibling worktree (review drain) -> allowed" 0
settle_children "$RW"
WOUT="$(cd "$WT" && CLAUDE_PROJECT_DIR="$WT" "$REALBASH" "$GUARD" write-marker 2>/dev/null)"; WRC=$?
[ "$WRC" = 0 ] && [ -f "$RW/.supervisor/logs/$PSID.finalize-gate" ] && [ ! -e "$WT/.supervisor" ] \
  && ok "write-marker from the linked worktree writes into the main worktree's .supervisor/logs" || no "linked write-marker: rc=$WRC out=$WOUT"
run_guard "$WT" "git push -u origin $BR"; expect "linked worktree after a passing check -> allowed" 0
RB="$(new_repo running)"
printf '# State\n\n## Session\n- **session_id:** %s\n- **Branch:** %s\n- **Status:** Running\n' "$PSID" "$BR" > "$RB/.supervisor/state.md"
run_guard "$RB" "git push"; expect "bold-format ## Session block -> guard ACTIVE, denied" 2 "run FINALIZE point 5 first"
RBN="$(new_repo running)"
printf '# State\n- **session_id:** %s\n- **branch:** %s\n- **status:** running\n' "$PSID" "$BR" > "$RBN/.supervisor/state.md"
run_guard "$RBN" "git push"; expect "bold-format state.md with no ## Session header -> guard ACTIVE, denied" 2
printf '# State\n- **session_id:** %s\n- **status:** completed\n' "$PSID" > "$RBN/.supervisor/state.md"
run_guard "$RBN" "git push"; expect "bold-format terminal status -> allowed" 0

echo "== F4: wrapper / nesting / quoting forms of a publish -> denied =="
EVASION_CASES=(
  "env X=1 git push"
  "env -u FOO git push"
  "time git push"
  "nohup git push"
  "exec git push"
  "sudo -u me git push"
  "echo x | xargs git push"
  "xargs -I{} git push"
  "timeout 60 git push"
  'bash -c "git push"'
  "sh -c 'cd x && git push'"
  'zsh -lc "git push origin HEAD"'
  'eval "git push"'
  'echo $(git push)'
  'echo `git push`'
  "(cd repo && git push)"
  "git push&"
  "gh pr create --fill &"
  '"git" push'
  "'git' push"
  "/usr/bin/git push"
  "/opt/homebrew/bin/gh pr create --fill"
  'GIT_SSH_COMMAND="ssh -i k" git push'
  'git -C "my dir" push'
  "$(printf 'git \\\npush')"
  "if true; then git push; fi"
  "! git push"
)
for c in "${EVASION_CASES[@]}"; do run_guard "$RS" "$c"; expect "[${c//$'\n'/\\n}] -> denied" 2; done
ALLOW_CASES=(
  "git stash push"
  "echo push"
  'git commit -m "push it"'
  'echo "git push"'
  "printf '%s' 'git push'"
  'bash -c "echo push"'
  "git log --grep push"
  "gh pr view 1 --json title # create"
)
for c in "${ALLOW_CASES[@]}"; do run_guard "$RS" "$c"; expect "[$c] -> allowed" 0; done

echo "== redirections: a redirect's & never cuts, redirect words never hide the subcommand =="
# re-drain round 1: splitting on the `&` of `2>&1` sheared `git 2>&1 push` into `git 2>` + `1 push`.
REDIRECT_DENY_CASES=(
  "git 2>&1 push"
  "gh 2>&1 pr create --fill"
  "git >&2 push"
  "git &>/dev/null push"
  "git &>>log push"
  "git >/dev/null push"
  "git 2>err.log push"
  "git 2> err.log push"
  "git > /dev/null push"
  "git <&0 push"
  "git >&- push"
  "git {fd}>&1 push"
  ">out git push"
  "2>&1 git push"
  "cat <<EOF >f; git push"
  "gh pr 2>&1 create"
  "git push>/dev/null"
  "git push 2>&1"
  "git push &>/dev/null"
  "git push 2>&1 | tee log"
  "git push &"
  "x & git push"
  "x 2>&1 & git push"
)
for c in "${REDIRECT_DENY_CASES[@]}"; do run_guard "$RS" "$c"; expect "[$c] -> denied" 2; done
REDIRECT_ALLOW_CASES=(
  "git stash push 2>&1"
  "git stash push >/dev/null 2>&1"
  "git 2>&1 stash push"
  "echo push >&2"
  "git log --grep push 2>&1"
)
for c in "${REDIRECT_ALLOW_CASES[@]}"; do run_guard "$RS" "$c"; expect "[$c] -> allowed" 0; done

echo "== (m) mutation controls for the F2-F4 hardening =="
cp "$HERE/loom-log-owner.sh" "$TMP/" ; cp "$HERE/check-children-settled.sh" "$TMP/"
# mutant <name> <sed program> — writes $TMP/<name>.sh; MUTOK=1 only when sed changed the guard
mutant() { MUTF="$TMP/$1.sh"; sed "$2" "$GUARD" > "$MUTF"; if cmp -s "$MUTF" "$GUARD"; then MUTOK=0; else MUTOK=1; fi; }
# F2: drop the session-log existence refusal -> a missing log writes a marker again
mutant m-f2 '/|| refuse "session_log_missing"/d'
RML="$(new_repo running)"; rm -f "$RML/.supervisor/logs/$PSID.jsonl"
WRC="$(cd "$RML" && CLAUDE_PROJECT_DIR="$RML" "$REALBASH" "$MUTF" write-marker >/dev/null 2>&1; echo $?)"
[ "$MUTOK" = 1 ] && [ "$WRC" = 0 ] && [ -f "$RML/.supervisor/logs/$PSID.finalize-gate" ] \
  && ok "mutation (F2): without the log check a missing log writes a marker — the case is load-bearing" \
  || no "mutation (F2): inconclusive (changed=$MUTOK rc=$WRC)"
# expect-id: stop feeding the recorded worker ids -> a recorded unsettled worker writes no_identity_rows again
mutant m-expect 's/^\$worker_ids$//'
RMX="$(new_repo running)"; record_worker "$RMX" "w-recorded"
WRC="$(cd "$RMX" && CLAUDE_PROJECT_DIR="$RMX" "$REALBASH" "$MUTF" write-marker >/dev/null 2>&1; echo $?)"
[ "$MUTOK" = 1 ] && [ -s "$MUTF" ] && bash -n "$MUTF" 2>/dev/null && [ "$WRC" = 0 ] \
  && [ "$(jq -r .children_check "$RMX/.supervisor/logs/$PSID.finalize-gate" 2>/dev/null)" = "no_identity_rows" ] \
  && ok "mutation (expect-id): without the recorded ids the unsettled worker passes as no_identity_rows — the wiring is load-bearing" \
  || no "mutation (expect-id): inconclusive (changed=$MUTOK rc=$WRC)"
# worker_results_unparsed: drop the zero-ids refusal -> the table-only section passes as no_identity_rows again
mutant m-unparsed '/|| refuse "worker_results_unparsed"/d'
RMU="$(new_repo running)"; record_section "$RMU" "$TABLE_SECTION"
WRC="$(cd "$RMU" && CLAUDE_PROJECT_DIR="$RMU" "$REALBASH" "$MUTF" write-marker >/dev/null 2>&1; echo $?)"
[ "$MUTOK" = 1 ] && [ -s "$MUTF" ] && bash -n "$MUTF" 2>/dev/null && [ "$WRC" = 0 ] \
  && [ "$(jq -r .children_check "$RMU/.supervisor/logs/$PSID.finalize-gate" 2>/dev/null)" = "no_identity_rows" ] \
  && ok "mutation (unparsed): without the refusal a table-only Worker Results section passes as no_identity_rows — the refusal is load-bearing" \
  || no "mutation (unparsed): inconclusive (changed=$MUTOK rc=$WRC)"
# #717: stop resolving the recorded tokens -> a label heading refuses a settled run again
mutant m-717 's/| resolve_worker_result_ids "\$SESSION_LOG")"/| sed "s|^|id |")"/'
RM7="$(new_repo running)"; settle_real "$RM7" "$REAL1"; record_section "$RM7" "### worker-1 (subtask-1)"
WOUT="$(cd "$RM7" && CLAUDE_PROJECT_DIR="$RM7" "$REALBASH" "$MUTF" write-marker 2>/dev/null)"; WRC=$?
[ "$MUTOK" = 1 ] && bash -n "$MUTF" 2>/dev/null && [ "$WRC" = 1 ] && grep -q children_unsettled <<<"$WOUT" \
  && ok "mutation (#717): expecting the labels again refuses a settled run — the resolver is load-bearing" \
  || no "mutation (#717): inconclusive (changed=$MUTOK rc=$WRC out=$WOUT)"
# F3a: resolve .supervisor/ from the project dir only -> the linked worktree reads inert
mutant m-f3a 's/ROOT="\$(loom_main_root "\$PROJ" 2>\/dev\/null)"/ROOT=""/'
RML2="$(new_repo running)"; WT2="$TMP/wt-linked2.$$"
( cd "$RML2" && git checkout -qb other && git worktree add -q "$WT2" "$BR" ) >/dev/null 2>&1
run_guard "$WT2" "git push" cc-uuid-1 "$MUTF"
[ "$MUTOK" = 1 ] && [ "$RC" = 0 ] && ok "mutation (F3): project-dir-only root lets the linked-worktree push through" \
  || no "mutation (F3): inconclusive (changed=$MUTOK rc=$RC)"
# F3b: no bold stripping -> the bold state.md reads inert
mutant m-f3b '/line="\${line\/\/\\\*\\\*\/}"/d'
run_guard "$RB" "git push" cc-uuid-1 "$MUTF"
[ "$MUTOK" = 1 ] && [ "$RC" = 0 ] && ok "mutation (F3): without bold stripping the bold state.md push goes through" \
  || no "mutation (F3 bold): inconclusive (changed=$MUTOK rc=$RC)"
# F3c: no detached-sibling allow -> the review-drain sibling push is denied
mutant m-f3c '/\[ -z "\$br" \] && \[ "\$top" != "\$ROOT" \]/d'
RMS="$(new_repo running)"; SIB2="$TMP/wt-sibling2.$$"    # no marker anywhere: only the sibling rule allows
( cd "$RMS" && git worktree add -q --detach "$SIB2" HEAD ) >/dev/null 2>&1
run_guard "$SIB2" "git push origin HEAD:$BR"; expect "detached sibling with no marker -> allowed by the sibling rule alone" 0
run_guard "$SIB2" "git push origin HEAD:$BR" cc-uuid-1 "$MUTF"
[ "$MUTOK" = 1 ] && [ "$RC" = 2 ] && ok "mutation (F3): without the detached-sibling rule the drain sibling push is denied" \
  || no "mutation (F3 sibling): inconclusive (changed=$MUTOK rc=$RC)"
# F4: each hardening piece removed -> its evasion forms are allowed again
f4_mut() { # f4_mut <label> <sed program> <case...>
  local label="$1" prog="$2" missed=0 total=0 c; shift 2
  mutant m-f4 "$prog"
  for c in "$@"; do total=$((total+1)); run_guard "$RS" "$c" cc-uuid-1 "$MUTF"; [ "$RC" = 0 ] && missed=$((missed+1)); done
  [ "$MUTOK" = 1 ] && [ "$missed" = "$total" ] && ok "mutation (F4 $label): mutant allows all $total forms" \
    || no "mutation (F4 $label): changed=$MUTOK, mutant allowed only $missed/$total"
}
f4_mut "separators" "s/for sep in '&&' '||' ';' '|' '&' '(' ')' '\`'; do/for sep in '\&\&' '||' ';' '|'; do/;/NL\\\$OPEN\\\$NL/d;/NL\\\$CLOSE\\\$NL/d" \
  'echo $(git push)' 'echo `git push`' "git push&" "(cd repo && git push)"
f4_mut "prefix words" '/^      command|exec|time|env|sudo|doas|xargs|nice)$/,/continue ;;$/d' \
  "env -u FOO git push" "sudo -u me git push" "echo x | xargs git push" "exec git push"
f4_mut "line continuation" '/s="\${s\/\/\\\\\$NL\/ }"/d' "$(printf 'git \\\npush')"
f4_mut "path basename" '/prog="\${prog##\*\/}"/d' "/usr/bin/git push" "/opt/homebrew/bin/gh pr create --fill"
f4_mut "shell -c unwrap" 's/^    bash|sh|zsh|dash|ksh)$/    no-such-shell)/' 'bash -c "git push"' 'zsh -lc "git push origin HEAD"'
f4_mut "quote-aware tokens" "s/\"'\"|'\"') q=\"\$c\"; have=1; wq=1 ;;/\"'\"|'\"') w=\"\$w\$c\"; have=1 ;;/" \
  '"git" push' 'GIT_SSH_COMMAND="ssh -i k" git push' 'git -C "my dir" push'
# redirect-aware split: without the AMP swap, the redirect's `&` cuts and the subcommand is sheared off
f4_mut "redirect-aware split" '/s="\${s\/\/">&"\/\$GT\$AMP}"/d' \
  "git 2>&1 push" "gh 2>&1 pr create --fill" "git >&2 push" "git &>/dev/null push"
# redirect-dropping tokenizer: treating `<` `>` as ordinary word chars keeps `>/dev/null` as the "subcommand"
f4_mut "redirect tokens" "s/^        '>'|'<'|\"\$AMP\")\$/        no-redirect-chars)/" \
  "git >/dev/null push" "git 2>err.log push" "git > /dev/null push" "git push>/dev/null"

# scope / owner (2026-11-12): each of the two root causes, restored alone, re-denies the incident
cp "$HERE/loom-log-owner.sh" "$HERE/check-children-settled.sh" "$TMP/" 2>/dev/null
RMI="$(new_repo running)"; MWT="$TMP/wt-foreign-m.$$"
( cd "$RMI" && git worktree add -q -b fix/unrelated "$MWT" ) >/dev/null 2>&1
MINC="cd $MWT && git push -q -u origin fix/unrelated; gh pr create --head fix/unrelated --fill"
#  (a) scope read from the base dir only (the old project-dir rule): the own session's incident push is denied
mutant m-scope 's/publish_in_scope "\$pd" \&\& scoped=0/publish_in_scope "$BASE_DIR" \&\& scoped=0/'
run_guard_json "$RMI" "$(payload_full "$MINC" cc-uuid-1 "$RMI")" "$MUTF"
[ "$MUTOK" = 1 ] && [ "$RC" = 2 ] && ok "mutation (scope): judging the base dir instead of the publish target denies the incident push — the walk is load-bearing" \
  || no "mutation (scope): inconclusive (changed=$MUTOK rc=$RC)"
#  (b) every non-owner is a resumed run again: a foreign session on the run checkout is denied
mutant m-owner '/\[ "\$owner" != "\$payload_sid" \] && allow$/d'
run_guard_json "$RMI" "$(payload_full "git push -u origin $BR" cc-foreign-9 "$RMI")" "$MUTF"
[ "$MUTOK" = 1 ] && [ "$RC" = 2 ] && ok "mutation (owner): treating a foreign session as a resumed run denies it — the join is load-bearing" \
  || no "mutation (owner): inconclusive (changed=$MUTOK rc=$RC)"
#  (c) both restored: the exact incident (foreign session, cd into its own worktree) is denied again
mutant m-both 's/publish_in_scope "\$pd" \&\& scoped=0/publish_in_scope "$BASE_DIR" \&\& scoped=0/;/\[ "\$owner" != "\$payload_sid" \] && allow$/d'
run_guard_json "$RMI" "$(payload_full "$MINC" cc-foreign-9 "$RMI")" "$MUTF"
[ "$MUTOK" = 1 ] && [ "$RC" = 2 ] && grep -qF "run FINALIZE point 5 first" <<<"$OUT" \
  && ok "mutation (incident): with both causes restored the 2026-11-12 incident is denied again" \
  || no "mutation (incident): inconclusive (changed=$MUTOK rc=$RC)"
#  (d) the subshell restore removed: (cd foreign); git push escapes the gate
mutant m-paren '/NL\$OPEN\$NL/d;/NL\$CLOSE\$NL/d'
run_guard_json "$RMI" "$(payload_full "(cd $MWT && git status); git push" cc-uuid-1 "$RMI")" "$MUTF"
[ "$MUTOK" = 1 ] && [ "$RC" = 0 ] && ok "mutation (subshell): without the ( ) restore a subshell cd leaks and the push escapes — the restore is load-bearing" \
  || no "mutation (subshell): inconclusive (changed=$MUTOK rc=$RC)"

#  (e) quoted parens trusted again (no PAREN_UNSURE target): the review's `:)` case is still denied
#      by mark_parens alone; restoring the old quote-UNAWARE marking as well lets it escape
mutant m-unsure '/\[ "\$PAREN_UNSURE" = 1 \] && PUB_DIRS/d'
RCQ="(cd $RMI && git commit -m \"Looks good :)\" ; git push)"
MPLAIN="$(mktemp -d "$TMP/plain-m.XXXXXX")"
run_guard_json "$RMI" "$(payload_full "$RCQ" cc-uuid-1 "$MPLAIN")" "$MUTF"
[ "$MUTOK" = 1 ] && [ "$RC" = 2 ] && ok "mutation (unsure): quote-aware marking alone keeps the subshell open past a quoted ')'" \
  || no "mutation (unsure): inconclusive (changed=$MUTOK rc=$RC)"
run_guard_json "$RMI" "$(payload_full "echo \"\$(cd $MPLAIN)\"; git push" cc-uuid-1 "$RMI")" "$MUTF"
[ "$MUTOK" = 1 ] && [ "$RC" = 0 ] && ok "mutation (unsure): without PAREN_UNSURE a cd inside a quoted \$( ) leaks and the push escapes — the flag is load-bearing" \
  || no "mutation (unsure, quoted subst): inconclusive (changed=$MUTOK rc=$RC)"
mutant m-quoteblind 's/  mark_parens "\$s"; s="\$MARKED"/  s="${s\/\/"("\/$NL$OPEN$NL}"; s="${s\/\/")"\/$NL$CLOSE$NL}"/;/\[ "\$PAREN_UNSURE" = 1 \] \&\& PUB_DIRS/d'
run_guard_json "$RMI" "$(payload_full "$RCQ" cc-uuid-1 "$MPLAIN")" "$MUTF"
[ "$MUTOK" = 1 ] && [ "$RC" = 0 ] && ok "mutation (quote-blind parens): the review's '(cd <run> && git commit -m \"…:)\"; git push)' escapes — the quote-aware marking is load-bearing" \
  || no "mutation (quote-blind parens): inconclusive (changed=$MUTOK rc=$RC)"

#  (f) bare `pushd` read as `cd $HOME` again: from the run's checkout the push escapes (HOME is not it)
mutant m-pushd 's/      elif \[ "\$prog" = cd \]; then CUR_DIR="\$HOME"/      elif :; then CUR_DIR="$HOME"/'
run_guard_json "$RMI" "$(payload_full "pushd; git push -u origin $BR" cc-uuid-1 "$RMI")" "$MUTF"
[ "$MUTOK" = 1 ] && [ "$RC" = 0 ] && ok "mutation (bare pushd): reading it as cd \$HOME lets the run checkout's push escape — the unknown rule is load-bearing" \
  || no "mutation (bare pushd): inconclusive (changed=$MUTOK rc=$RC)"
run_guard_json "$RMI" "$(payload_full "pushd; git push -u origin $BR" cc-uuid-1 "$RMI")"; expect "own session: bare pushd; git push from the run checkout -> denied" 2

echo "== wiring =="
leaf="$(jq -r '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | .command | select(test("guard-finalize-publish.sh"))' "$HOOKS" 2>/dev/null)"
if [ -n "$leaf" ] && ! grep -q '|| true' <<<"$leaf"; then
  ok "hooks.json PreToolUse[Bash] leaf invokes guard-finalize-publish.sh with NO || true"
else
  no "hooks.json leaf missing or carries || true: '$leaf'"
fi
grep -q 'loom-log-owner.sh' "$GUARD" && grep -q 'loom-log-owner.sh' "$HERE/emit-lifecycle.sh" \
  && ! grep -q '_first="\$(head -1' "$GUARD" \
  && ok "session join sources the shared loom_log_owner rule (not restated)" || no "loom_log_owner not shared"
grep -q 'loom_main_root' "$GUARD" && grep -q 'loom_main_root' "$HERE/emit-lifecycle.sh" \
  && ! grep -q 'worktree list --porcelain' "$GUARD" \
  && ok "main-worktree anchoring sources the shared loom_main_root rule (not restated)" || no "loom_main_root not shared"

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
# The pre-fix fixed-regex detector (only `-C`/`-c` tolerated after git, nothing after gh) must FAIL
# the global-option deny cases above — proves those cases exercise the token walk.
MUT2="$TMP/mutant-regex.sh"
awk '
  /^seg_is_publish\(\) \{/ {
    print "seg_is_publish() {"
    print "  local seg=\"$1\""
    print "  local re_assign='"'"'^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+'"'"'"
    print "  while [[ \"$seg\" =~ $re_assign ]]; do seg=\"${seg#\"${BASH_REMATCH[0]}\"}\"; done"
    print "  local re_git='"'"'^(command[[:space:]]+)?git([[:space:]]+(-C|-c)[[:space:]]+[^[:space:]]+)*[[:space:]]+push([[:space:]]|$)'"'"'"
    print "  local re_gh='"'"'^(command[[:space:]]+)?gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)'"'"'"
    print "  [[ \"$seg\" =~ $re_git ]] && return 0"
    print "  [[ \"$seg\" =~ $re_gh ]] && return 0"
    print "  return 1"
    print "}"
    skip = 1; next
  }
  skip && /^\}/ { skip = 0; next }
  !skip { print }
' "$GUARD" > "$MUT2"
if cmp -s "$MUT2" "$GUARD" || ! grep -q 're_git=' "$MUT2"; then
  no "mutation control (regex): seg_is_publish not found, control inconclusive"
else
  RM2="$(new_repo running)"
  run_guard "$RM2" "git push" cc-uuid-1 "$MUT2"
  [ "$RC" = 2 ] || no "mutation control (regex): mutant does not deny plain git push (rc=$RC) — mutant broken"
  missed=0
  for c in "${GLOBAL_DENY_CASES[@]}"; do run_guard "$RM2" "$c" cc-uuid-1 "$MUT2"; [ "$RC" = 0 ] && missed=$((missed+1)); done
  [ "$missed" = "${#GLOBAL_DENY_CASES[@]}" ] \
    && ok "mutation control (regex): the fixed-regex detector allows all $missed global-option publish forms" \
    || no "mutation control (regex): fixed-regex detector allowed only $missed/${#GLOBAL_DENY_CASES[@]} — a case does not exercise the walk"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
