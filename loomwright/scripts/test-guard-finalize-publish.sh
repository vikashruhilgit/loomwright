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
# plugin id != payload id, owner == payload id -> ACTIVE); a resumed run (owner != payload id) ->
# still denied (the documented B2 choice); the writer refuses on `unsettled` (no marker) and removes
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
run_guard "$RS" "cd /tmp && git push origin HEAD"; expect "chained cd && git push -> denied" 2
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
run_guard "$RJ" "git push" "cc-uuid-new"; expect "resumed run (owner != payload id) -> still denied (B2 decision)" 2 "resumed run"
settle_children "$RJ"; write_marker "$RJ"
run_guard "$RJ" "git push" "cc-uuid-new"; expect "resumed run after a passing check -> allowed" 0

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
mutant m-expect 's/^\$(read_worker_result_ids)$//'
RMX="$(new_repo running)"; record_worker "$RMX" "w-recorded"
WRC="$(cd "$RMX" && CLAUDE_PROJECT_DIR="$RMX" "$REALBASH" "$MUTF" write-marker >/dev/null 2>&1; echo $?)"
[ "$MUTOK" = 1 ] && [ -s "$MUTF" ] && bash -n "$MUTF" 2>/dev/null && [ "$WRC" = 0 ] \
  && [ "$(jq -r .children_check "$RMX/.supervisor/logs/$PSID.finalize-gate" 2>/dev/null)" = "no_identity_rows" ] \
  && ok "mutation (expect-id): without the recorded ids the unsettled worker passes as no_identity_rows — the wiring is load-bearing" \
  || no "mutation (expect-id): inconclusive (changed=$MUTOK rc=$WRC)"
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
mutant m-f3c '/\[ -z "\$cur_branch" \] && \[ -n "\$CHECKOUT" \]/d'
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
f4_mut "separators" "s/for sep in '&&' '||' ';' '|' '&' '(' ')' '\`'; do/for sep in '\&\&' '||' ';' '|'; do/" \
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
