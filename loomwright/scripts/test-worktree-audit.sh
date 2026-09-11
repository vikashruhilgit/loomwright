#!/usr/bin/env bash
# test-worktree-audit.sh — self-tests for worktree-audit.sh (record / note / report)
# and for the removal of the destructive WorktreeCreate / WorktreeRemove hooks.
#
# Every case runs in an ISOLATED temp git repo (mktemp -d + git init) with a REAL
# `git worktree add`, so `confirmed` and the ground-truth arm are exercised for
# real, never simulated. PostToolUse payloads are DERIVED by jq from the checked-in
# real fixture fixtures/posttooluse-gh-pr-create.json (only `.tool_input.command`
# and `.cwd` substituted) — never hand-invented. Every mutant is gated (non-empty,
# cmp-different, `bash -n` clean) and copied beside its `dirname "$0"` siblings.
# Exit 0 = all pass, 1 = any failure (auto-registered by ci.yml's test-*.sh glob).
#
# Covers AC-1 … AC-10 of the v15.66.0 brief plus its Post-PASS notes (the
# `removed`/`confirmed:false` fold rule, the 1-byte defect pin, the AC-7 live
# sibling control) and the review-iteration additions: the branch-keyed
# fallback for an unexpanded path token (`$(basename $(pwd))`, whitespace inside
# quotes — exact `refs/heads/<branch>` match, no fallback for a literal absent
# path), the `.supervisor/` population gate (no line, no directory created in a
# repo the plugin never ran in), the `note removed` direct dismissal, and one
# gated mutant for each of the three.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AUDIT="$SCRIPT_DIR/worktree-audit.sh"
HOOKS_JSON="$REPO_ROOT/loomwright/hooks/hooks.json"
REAL_FIX="$SCRIPT_DIR/fixtures/posttooluse-gh-pr-create.json"
WC_FIX="$SCRIPT_DIR/fixtures/worktreecreate-real-firing.json"
DISPATCHER="$SCRIPT_DIR/dispatch-pr-review.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "test-worktree-audit: jq absent — worktree-audit.sh no-ops (exit 0). Skipping."
  echo "RESULT: 0 passed, 0 failed (jq absent, vacuous)"
  exit 0
fi

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT" 2>/dev/null' EXIT
mktmp() { mktemp -d "$ROOT/d.XXXXXX"; }

sha() {
  if   command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" 2>/dev/null | cut -d' ' -f1
  elif command -v shasum    >/dev/null 2>&1; then shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
  else cksum "$1" 2>/dev/null | cut -d' ' -f1; fi
}

# new_repo — an isolated repo named `repo` inside its own parent dir, so the
# documented `../<repo>-<sub>` sibling shape lands in a private parent. Prints
# the CANONICAL path (pwd -P) so it compares byte-for-byte with git's porcelain.
# Carries an EMPTY `.supervisor/` — the plugin-has-run-here signal the writers
# gate on; `bare_repo` below is the same thing WITHOUT it.
new_repo() {
  local p; p="$(mktmp)"
  ( cd "$p" && mkdir repo && cd repo && git init -q && git config user.email t@t \
      && git config user.name t && echo init > f && git add f && git commit -qm init \
      && mkdir .supervisor ) >/dev/null 2>&1
  ( cd "$p/repo" && pwd -P )
}
bare_repo() { local r; r="$(new_repo)"; rmdir "$r/.supervisor"; printf '%s' "$r"; }
LOG_REL=".supervisor/logs/worktrees.log"
log_of() { printf '%s/%s' "$1" "$LOG_REL"; }
log_lines() { [ -f "$(log_of "$1")" ] && wc -l < "$(log_of "$1")" | tr -d ' ' || printf '0'; }

# payload <command> <cwd> — derive a PostToolUse payload from the REAL fixture.
payload() { jq -c --arg c "$1" --arg d "$2" '.tool_input.command = $c | .cwd = $d' "$REAL_FIX"; }

RCFILE="$ROOT/.rc"
lastrc() { cat "$RCFILE" 2>/dev/null || printf '99'; }
# run_record <audit> <repo> <command> — execute the command FOR REAL in the repo,
# then feed the derived payload to `record`. rc of the audit script → RCFILE.
run_record() {
  local audit="$1" repo="$2" cmd="$3" rc
  ( cd "$repo" && eval "$cmd" ) >/dev/null 2>&1 || true
  ( cd "$repo" && payload "$cmd" "$repo" | bash "$audit" record ); rc=$?
  printf '%s' "$rc" > "$RCFILE"
}
# record_only <audit> <repo> <command> — feed WITHOUT executing (for remove-fail
# and no-op cases where the caller controls execution).
record_only() {
  local audit="$1" repo="$2" cmd="$3" rc
  ( cd "$repo" && payload "$cmd" "$repo" | bash "$audit" record ); rc=$?
  printf '%s' "$rc" > "$RCFILE"
}
run_report() { local rc out; out="$( cd "$2" && bash "$1" report )"; rc=$?; printf '%s' "$rc" > "$RCFILE"; printf '%s' "$out"; }
rows() { [ -n "$1" ] && printf '%s\n' "$1" | grep -c '^orphan' || printf '0'; }
field() { printf '%s' "$1" | jq -r "$2" 2>/dev/null; }
last_line() { tail -1 "$(log_of "$1")" 2>/dev/null; }
live_paths() { ( cd "$1" && git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' ); }

# gate_mutant <original> <mutant> <label>
gate_mutant() {
  local orig="$1" mut="$2" label="$3" okk=1
  [ -s "$mut" ] && ok "$label mutant is non-empty" || { no "$label mutant is EMPTY"; okk=0; }
  if cmp -s "$orig" "$mut"; then no "$label mutant is byte-identical to the original"; okk=0
  else ok "$label mutant is byte-different from the original"; fi
  bash -n "$mut" 2>/dev/null && ok "$label mutant parses (bash -n)" || { no "$label mutant does not parse"; okk=0; }
  [ "$okk" -eq 1 ]
}
# copy_with_siblings <dir> — worktree-audit.sh has no script siblings today; the
# copy still lands in a dir of its own so a future sibling dependency shows up
# here rather than in a red mutant.
copy_with_siblings() { cp "$AUDIT" "$1/worktree-audit.sh"; }

# ============================================================================
echo "== AC-1: the payload shape is measured, not assumed =="
keys="$(jq -c 'keys' "$WC_FIX" 2>/dev/null)"
[ "$keys" = '["cwd","hook_event_name","name","prompt_id","scratchpad_dir","session_id","transcript_path"]' ] \
  && ok "AC-1 fixture key set is exactly the seven measured keys" || no "AC-1 fixture keys: $keys"
[ "$(jq -r '.hook_event_name' "$WC_FIX")" = "WorktreeCreate" ] && ok "AC-1 hook_event_name == WorktreeCreate" || no "AC-1 hook_event_name wrong"
jq -r '.name' "$WC_FIX" | grep -qE '^agent-[0-9a-f]{17}$' && ok "AC-1 name matches ^agent-[0-9a-f]{17}\$" || no "AC-1 name shape wrong"
[ "$(jq -r 'has("worktree_path")' "$WC_FIX")" = "false" ] && ok "AC-1 has(\"worktree_path\") is false" || no "AC-1 worktree_path present"
for f in "$REPO_ROOT/CHANGELOG.md" "$REPO_ROOT/loomwright/docs/HOOKS.md"; do
  grep -qF 'hook succeeded but returned no worktree path' "$f" && ok "AC-1 $(basename "$f") quotes the harness error" || no "AC-1 $(basename "$f") lacks the harness error string"
  miss=""; for k in session_id transcript_path cwd scratchpad_dir prompt_id hook_event_name name; do grep -q "\`$k\`" "$f" || miss="$miss $k"; done
  [ -z "$miss" ] && ok "AC-1 $(basename "$f") lists the seven measured keys" || no "AC-1 $(basename "$f") misses:$miss"
done

# record_programs <script> — every `jq -r '<program>'` inside record() { … } only.
record_programs() {
  awk '/^record\(\) \{/{inb=1; next} inb && /^\}/{inb=0} inb' "$1" \
    | grep -o "jq -r '[^']*'" | sed -e "s/^jq -r '//" -e "s/'$//"
}
# check_payload_reads <script> — 0 iff ≥3 programs extracted and every .path is allowed.
check_payload_reads() {
  local progs n bad="" p path
  progs="$(record_programs "$1")"
  n="$( [ -n "$progs" ] && printf '%s\n' "$progs" | wc -l | tr -d ' ' || printf 0 )"
  [ "$n" -ge 3 ] || return 1
  while IFS= read -r p; do
    for path in $(printf '%s' "$p" | grep -oE '\.[a-z_]+(\.[a-z_]+)?'); do
      case "$path" in .tool_name|.tool_input.command|.cwd|.session_id) ;; *) bad="$bad $path" ;; esac
    done
  done <<< "$progs"
  [ -z "$bad" ]
}
n_progs="$(record_programs "$AUDIT" | wc -l | tr -d ' ')"
[ "$n_progs" -ge 3 ] && ok "AC-1 positive control: $n_progs jq -r programs extracted from record() (≥3)" || no "AC-1 extracted only $n_progs programs — the check would be vacuous"
check_payload_reads "$AUDIT" && ok "AC-1 record() reads only .tool_name/.tool_input.command/.cwd/.session_id" || no "AC-1 record() reads a payload field outside the measured set"
d="$(mktmp)"; : > "$d/empty.sh"
check_payload_reads "$d/empty.sh" && no "AC-1 an empty extraction PASSED (vacuous)" || ok "AC-1 an empty extraction FAILS (not vacuous)"

# ============================================================================
echo "== AC-2: no empty-string extraction =="
[ "$(jq '.hooks | has("WorktreeCreate") or has("WorktreeRemove")' "$HOOKS_JSON")" = "false" ] \
  && ok "AC-2 hooks.json has neither WorktreeCreate nor WorktreeRemove" || no "AC-2 a destructive worktree hook survives in hooks.json"
[ "$(jq '[.hooks[][].hooks[]] | length' "$HOOKS_JSON")" = "36" ] && ok "AC-2 leaf hook count is 36" || no "AC-2 leaf hook count != 36"
[ "$(jq '[.hooks.PostToolUse[] | select(.matcher == "Bash")] | length' "$HOOKS_JSON")" = "1" ] && ok "AC-2 exactly ONE PostToolUse Bash matcher-object" || no "AC-2 Bash matcher-object count != 1"
[ "$(jq -r '.hooks.PostToolUse[] | select(.matcher == "Bash") | .hooks | length' "$HOOKS_JSON")" = "3" ] && ok "AC-2 the Bash matcher carries three leaves" || no "AC-2 Bash matcher leaf count != 3"
jq -r '.hooks.PostToolUse[] | select(.matcher == "Bash") | .hooks[].command' "$HOOKS_JSON" | grep -q 'worktree-audit.sh" record || true' \
  && ok "AC-2 the third leaf runs worktree-audit.sh record with || true" || no "AC-2 observer leaf missing/unshaped"

# The OLD command string, verbatim, kept here as the defect pin (NOT in hooks.json).
OLD_CMD="$(cat <<'EOF'
INPUT=$(cat) && mkdir -p .supervisor/logs && echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] WORKTREE_CREATED $INPUT" >> .supervisor/logs/worktrees.log && echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('worktree_path',''))" 2>/dev/null || true
EOF
)"
if old_hooks="$(git -C "$REPO_ROOT" show 03d9e2b:loomwright/hooks/hooks.json 2>/dev/null)" && [ -n "$old_hooks" ]; then
  [ "$OLD_CMD" = "$(jq -r '.hooks.WorktreeCreate[0].hooks[0].command' <<< "$old_hooks")" ] \
    && ok "AC-2 the embedded OLD command equals 03d9e2b's verbatim (local cross-check)" || no "AC-2 embedded OLD command drifted from 03d9e2b"
else echo "  skipped: 03d9e2b unavailable for the OLD_CMD cross-check"; fi
r="$(new_repo)"
old_out="$( cd "$r" && bash -c "$OLD_CMD" < "$WC_FIX" )"
[ "${#old_out}" -eq 0 ] && [ "$(cd "$r" && bash -c "$OLD_CMD" < "$WC_FIX" | wc -c | tr -d ' ')" = "1" ] \
  && ok "AC-2 defect pin: the old hook prints exactly ONE byte (an empty line) for the real firing" \
  || no "AC-2 defect pin: old hook stdout was not exactly one empty line"
grep -q 'WORKTREE_CREATED' "$(log_of "$r")" 2>/dev/null && ok "AC-2 defect pin: the old hook wrote WORKTREE_CREATED for a creation that never happened" || no "AC-2 old hook did not append (cwd?)"

r="$(new_repo)"
run_record "$AUDIT" "$r" "git branch feature/s1 && git worktree add ../repo-s1 feature/s1"
[ "$(lastrc)" -eq 0 ] && ok "AC-2 record exits 0" || no "AC-2 record rc $(lastrc)"
[ "$(log_lines "$r")" = "1" ] && ok "AC-2 exactly one JSON line appended" || no "AC-2 log lines: $(log_lines "$r")"
l="$(last_line "$r")"; p="$(field "$l" '.path')"
[ -n "$p" ] && [ "$p" != "null" ] && ok "AC-2 path is non-empty" || no "AC-2 path empty/null: $l"
live_paths "$r" | grep -qxF -- "$p" && ok "AC-2 path equals a git worktree list --porcelain row" || no "AC-2 path not in porcelain: $p"
[ "$p" = "$(dirname "$r")/repo-s1" ] && ok "AC-2 path is the absolute ../repo-s1" || no "AC-2 path != $(dirname "$r")/repo-s1: $p"
[ "$(field "$l" '.event')" = "created" ] && ok "AC-2 event == created" || no "AC-2 event: $l"
[ "$(field "$l" '.confirmed')" = "true" ] && ok "AC-2 confirmed == true" || no "AC-2 confirmed: $l"
[ "$(field "$l" '.branch')" = "feature/s1" ] && ok "AC-2 branch == feature/s1" || no "AC-2 branch: $l"
[ "$(field "$l" '.source')" = "posttooluse_bash" ] && ok "AC-2 source == posttooluse_bash" || no "AC-2 source: $l"

# ============================================================================
echo "== AC-3: create/remove correlate by absolute path =="
ac3() {  # <audit> <repo> → prints report; log must have 3 lines
  run_record "$1" "$2" "git worktree add -b feature/s1 ../repo-s1 && git worktree add -b feature/s2 ../repo-s2"
  run_record "$1" "$2" "git worktree remove ../repo-s1"
  run_report "$1" "$2"
}
r="$(new_repo)"; out="$(ac3 "$AUDIT" "$r")"
[ "$(log_lines "$r")" = "3" ] && ok "AC-3 two adds in one payload + one remove ⇒ 3 log lines" || no "AC-3 log lines: $(log_lines "$r")"
[ "$(rows "$out")" = "1" ] && ok "AC-3 report prints exactly one orphan row" || no "AC-3 rows: $(rows "$out") — $out"
printf '%s' "$out" | grep -q "^orphan	$(dirname "$r")/repo-s2	" && ok "AC-3 the row names s2 (s1 was paired by path)" || no "AC-3 row: $out"
# variant: -b <branch> <path> ordering with a git -C prefix from the parent dir
r="$(new_repo)"; parent="$(dirname "$r")"
( cd "$parent" && git -C repo worktree add -b feature/v1 ../repo-v1 && git -C "repo" worktree add -b feature/v2 '../repo-v2' ) >/dev/null 2>&1
( cd "$parent" && payload "git -C repo worktree add -b feature/v1 ../repo-v1 && git -C \"repo\" worktree add -b feature/v2 '../repo-v2'" "$parent" | bash "$AUDIT" record )
[ "$(log_lines "$r")" = "2" ] && ok "AC-3 variant: -C prefix + one layer of matching quotes ⇒ 2 lines under the repo's log root" || no "AC-3 variant lines: $(log_lines "$r")"
[ "$(jq -r '.path' "$(log_of "$r")" | sort | tr '\n' ' ')" = "$parent/repo-v1 $parent/repo-v2 " ] \
  && ok "AC-3 variant resolves the same absolute paths via -C" || no "AC-3 variant paths: $(jq -r '.path' "$(log_of "$r")" | tr '\n' ' ')"
[ "$(jq -r '.branch' "$(log_of "$r")" | tr '\n' ' ')" = "feature/v1 feature/v2 " ] && ok "AC-3 variant branches from -b" || no "AC-3 variant branches wrong"
[ "$(jq -r '.confirmed' "$(log_of "$r")" | sort -u)" = "true" ] && ok "AC-3 variant both confirmed" || no "AC-3 variant confirmed != true"
[ "$(jq -r '.resolved_by' "$(log_of "$r")" | sort -u)" = "path" ] && ok "AC-3 variant: a literal path is resolved_by path (no fallback)" || no "AC-3 variant resolved_by: $(jq -r '.resolved_by' "$(log_of "$r")" | tr '\n' ' ')"

# ============================================================================
echo "== AC-3f: branch-keyed fallback for a path token the shell would have expanded =="
# The async-orchestration skill documented `../$(basename $(pwd))-BD-XXa` for
# years; the payload carries it UNEXPANDED, so whitespace tokenization yields
# `../$(basename` as the path. The `-b` / positional branch is literal.
ac3f() {  # <audit> <repo> → report  (the documented shape, executed for real)
  run_record "$1" "$2" 'git branch feature/BD-XXa && git worktree add ../$(basename $(pwd))-BD-XXa feature/BD-XXa'
  run_report "$1" "$2"
}
r="$(new_repo)"; out="$(ac3f "$AUDIT" "$r")"; l="$(last_line "$r")"
[ "$(lastrc)" -eq 0 ] && [ "$(log_lines "$r")" = "1" ] && ok "AC-3f \$(basename \$(pwd)) shape ⇒ exactly one line, rc 0" || no "AC-3f lines=$(log_lines "$r") rc=$(lastrc)"
[ "$(field "$l" '.path')" = "$(dirname "$r")/repo-BD-XXa" ] && ok "AC-3f path is the REAL worktree (../repo-BD-XXa), not ../\$(basename" || no "AC-3f path: $l"
[ "$(field "$l" '.confirmed')" = "true" ] && [ "$(field "$l" '.resolved_by')" = "branch" ] && [ "$(field "$l" '.branch')" = "feature/BD-XXa" ] \
  && ok "AC-3f confirmed:true, resolved_by:branch, branch feature/BD-XXa" || no "AC-3f line: $l"
[ "$(rows "$out")" = "1" ] && printf '%s' "$out" | grep -q "^orphan	$(dirname "$r")/repo-BD-XXa	" && ok "AC-3f report lists the real worktree as an orphan" || no "AC-3f report: $out"
# whitespace inside quotes: `"../repo sp"` tokenizes to `"../repo` + `sp"`
r="$(new_repo)"
run_record "$AUDIT" "$r" 'git worktree add "../repo sp" -b feature/sp'
l="$(last_line "$r")"
[ "$(field "$l" '.path')" = "$(dirname "$r")/repo sp" ] && [ "$(field "$l" '.resolved_by')" = "branch" ] && [ "$(field "$l" '.confirmed')" = "true" ] \
  && ok "AC-3f a quoted path with whitespace is recovered via -b (resolved_by branch)" || no "AC-3f whitespace path: $l"
# exactness: feature/sp AND feature/sp-2 both live — each add pairs with ITS OWN worktree
run_record "$AUDIT" "$r" 'git worktree add "../repo sp2" -b feature/sp-2'
l="$(last_line "$r")"
[ "$(field "$l" '.path')" = "$(dirname "$r")/repo sp2" ] && [ "$(field "$l" '.branch')" = "feature/sp-2" ] \
  && ok "AC-3f the fallback matches the WHOLE refs/heads line (feature/sp-2 does not pair with feature/sp's worktree)" || no "AC-3f prefix pairing: $l"
[ "$(jq -r '.path' "$(log_of "$r")" | sort -u | wc -l | tr -d ' ')" = "2" ] && ok "AC-3f two distinct paths recorded for two prefix-sharing branches" || no "AC-3f paths collapsed: $(jq -r '.path' "$(log_of "$r")" | tr '\n' ' ')"
# a LITERAL path git does not list (the add FAILED: the branch is checked out
# elsewhere) is recorded as written with confirmed:false — NO fallback, or a
# failed add would pair with the pre-existing worktree and over-report.
r="$(new_repo)"
run_record "$AUDIT" "$r" "git worktree add -b feature/held ../repo-held"
run_record "$AUDIT" "$r" "git worktree add ../repo-again feature/held"
l="$(last_line "$r")"
[ "$(field "$l" '.path')" = "$(dirname "$r")/repo-again" ] && [ "$(field "$l" '.confirmed')" = "false" ] && [ "$(field "$l" '.resolved_by')" = "path" ] \
  && ok "AC-3f a literal absent path (failed add) stays confirmed:false with NO branch fallback" || no "AC-3f failed-add line: $l"
out="$(run_report "$AUDIT" "$r")"
[ "$(rows "$out")" = "1" ] && printf '%s' "$out" | grep -q "repo-held" && ok "AC-3f report still lists only the real worktree (the failed add's path is not live)" || no "AC-3f report after failed add: $out"

# ============================================================================
echo "== AC-4: the Supervisor's documented worktree commands appear =="
r="$(new_repo)"
grep -qF 'git worktree add ../{project}-{subtask_id} feature/{subtask_id}' "$REPO_ROOT/loomwright/agents/execute-manager.md" \
  && ok "AC-4 execute-manager.md still documents the exact add form" || no "AC-4 the documented form moved — update this test"
run_record "$AUDIT" "$r" "git branch feature/BD-15a && git worktree add ../repo-BD-15a feature/BD-15a"
l="$(last_line "$r")"
[ "$(log_lines "$r")" = "1" ] && [ "$(field "$l" '.event')" = "created" ] && [ "$(field "$l" '.confirmed')" = "true" ] \
  && ok "AC-4 the exact documented form ⇒ one created line, confirmed: true" || no "AC-4 documented form: $l"
[ "$(field "$l" '.path')" = "$(dirname "$r")/repo-BD-15a" ] && ok "AC-4 path is the subtask sibling" || no "AC-4 path: $l"
run_record "$AUDIT" "$r" "git worktree add -b feature/BD-15-b-dep ../repo-b-dep feature/BD-15a"
l="$(last_line "$r")"
[ "$(field "$l" '.branch')" = "feature/BD-15-b-dep" ] && ok "AC-4 dependent one-shot form ⇒ branch from -b" || no "AC-4 dep form branch: $l"
[ "$(field "$l" '.confirmed')" = "true" ] && ok "AC-4 dependent form confirmed" || no "AC-4 dep form confirmed: $l"
# note: a copy of the dispatcher's call-site shape
wt="$(dirname "$r")/repo-review-abc1234"
( cd "$r" && git worktree add --detach "$wt" HEAD ) >/dev/null 2>&1
( cd "$r" && WT_PATH="$wt" && bash "$(dirname "$AUDIT")/worktree-audit.sh" note created "$WT_PATH" 2>/dev/null || true ); rc=$?
l="$(last_line "$r")"
[ "$rc" -eq 0 ] && [ "$(field "$l" '.source')" = "direct" ] && [ "$(field "$l" '.confirmed')" = "true" ] && [ "$(field "$l" '.path')" = "$wt" ] \
  && ok "AC-4 note created (dispatcher call-site shape) ⇒ source direct, confirmed true" || no "AC-4 note: rc=$rc $l"
# static seam pin
n_note="$(grep -c 'worktree-audit.sh" note created' "$DISPATCHER")"
[ "$n_note" = "1" ] && ok "AC-4 dispatch-pr-review.sh wires exactly one note-created call" || no "AC-4 note-created wiring count: $n_note"
add_ln="$(grep -n 'git worktree add --detach "\$WT_PATH"' "$DISPATCHER" | head -1 | cut -d: -f1)"
note_ln="$(grep -n 'worktree-audit.sh" note created' "$DISPATCHER" | head -1 | cut -d: -f1)"
[ -n "$add_ln" ] && [ -n "$note_ln" ] && [ "$note_ln" -gt "$add_ln" ] && ok "AC-4 the note call sits AFTER the git worktree add --detach line ($add_ln < $note_ln)" || no "AC-4 note call not after add: add=$add_ln note=$note_ln"
grep -q 'worktree-audit.sh" note created "\$WT_PATH" 2>/dev/null || true' "$DISPATCHER" && ok "AC-4 the wiring is fail-safe (2>/dev/null || true)" || no "AC-4 wiring not fail-safe"

# ============================================================================
echo "== AC-5: orphan positive =="
ac5() { run_record "$1" "$2" "git worktree add -b feature/o1 ../repo-o1"; run_report "$1" "$2"; }
r="$(new_repo)"; out="$(ac5 "$AUDIT" "$r")"; l="$(last_line "$r")"
[ "$(lastrc)" -eq 0 ] && ok "AC-5 report exits 0" || no "AC-5 rc $(lastrc)"
[ "$(rows "$out")" = "1" ] && ok "AC-5 one orphan row" || no "AC-5 rows: $(rows "$out")"
exp="orphan	$(dirname "$r")/repo-o1	feature/o1	$(field "$l" '.ts')	$(field "$l" '.session_id')"
[ "$out" = "$exp" ] && ok "AC-5 row carries path, branch, ts, session_id" || no "AC-5 row mismatch: got=[$out] exp=[$exp]"

# ============================================================================
echo "== AC-6: orphan negative + pruned + failed remove =="
r="$(new_repo)"
run_record "$AUDIT" "$r" "git worktree add -b feature/n1 ../repo-n1"
run_record "$AUDIT" "$r" "git worktree remove ../repo-n1"
out="$(run_report "$AUDIT" "$r")"
[ "$(rows "$out")" = "0" ] && [ "$(log_lines "$r")" = "2" ] && ok "AC-6 created then removed (both observed) ⇒ zero rows" || no "AC-6 rows: $(rows "$out") lines: $(log_lines "$r")"
# (a) pruned only, directory live
r="$(new_repo)"
run_record "$AUDIT" "$r" "git worktree add -b feature/p1 ../repo-p1"
run_record "$AUDIT" "$r" "git worktree prune"
[ "$(field "$(last_line "$r")" '.event')" = "pruned" ] && [ "$(field "$(last_line "$r")" '.path')" = "null" ] && ok "AC-6(a) prune ⇒ a pruned line with null path" || no "AC-6(a) prune line: $(last_line "$r")"
out="$(run_report "$AUDIT" "$r")"
[ "$(rows "$out")" = "1" ] && ok "AC-6(a) pruned only, directory live ⇒ one orphan row" || no "AC-6(a) rows: $(rows "$out")"
# (b) directory deleted out of band, then pruned
r="$(new_repo)"
run_record "$AUDIT" "$r" "git worktree add -b feature/p2 ../repo-p2"
rm -rf "$(dirname "$r")/repo-p2"
run_record "$AUDIT" "$r" "git worktree prune"
out="$(run_report "$AUDIT" "$r")"
[ "$(rows "$out")" = "0" ] && ok "AC-6(b) deleted out of band then pruned ⇒ zero rows (absence from the live list clears it)" || no "AC-6(b) rows: $(rows "$out")"
# (c) dirty worktree, REAL remove without --force FAILS ⇒ removed/confirmed:false, still an orphan
ac6c() {  # <audit> <repo> → report
  run_record "$1" "$2" "git worktree add -b feature/d1 ../repo-d1"
  echo dirty > "$(dirname "$2")/repo-d1/untracked.txt"
  ( cd "$2" && git worktree remove ../repo-d1 ) >/dev/null 2>&1 && echo "  (unexpected: dirty remove succeeded)"
  record_only "$1" "$2" "git worktree remove ../repo-d1"
  run_report "$1" "$2"
}
r="$(new_repo)"; out="$(ac6c "$AUDIT" "$r")"; l="$(last_line "$r")"
[ "$(field "$l" '.event')" = "removed" ] && [ "$(field "$l" '.confirmed')" = "false" ] && ok "AC-6(c) failed remove ⇒ removed line with confirmed: false" || no "AC-6(c) line: $l"
[ "$(rows "$out")" = "1" ] && printf '%s' "$out" | grep -q "repo-d1" && ok "AC-6(c) report STILL prints the live worktree (unconfirmed removed never clears)" || no "AC-6(c) rows: $(rows "$out") — $out"
# (d) the hand-run dismissal: a DIRECT `note removed <abs>` on a worktree that is
# still live (confirmed:false, source:direct) clears the candidate — it is a
# deliberate statement, not an observed command that may have failed like (c).
ac6d() {  # <audit> <repo> → report
  run_record "$1" "$2" "git worktree add -b feature/keep ../repo-keep"
  ( cd "$2" && bash "$1" note removed "$(dirname "$2")/repo-keep" ) >/dev/null 2>&1
  run_report "$1" "$2"
}
r="$(new_repo)"; out="$(ac6d "$AUDIT" "$r")"; l="$(last_line "$r")"
[ "$(field "$l" '.event')" = "removed" ] && [ "$(field "$l" '.confirmed')" = "false" ] && [ "$(field "$l" '.source')" = "direct" ] \
  && ok "AC-6(d) note removed on a live worktree ⇒ removed / confirmed:false / source:direct (the log tells the truth)" || no "AC-6(d) line: $l"
[ "$(rows "$out")" = "0" ] && ok "AC-6(d) the direct dismissal clears the candidate ⇒ zero rows while the worktree stays live" || no "AC-6(d) rows: $(rows "$out") — $out"
live_paths "$r" | grep -qF -- "$(dirname "$r")/repo-keep" && ok "AC-6(d) the dismissed worktree is still live (nothing was removed)" || no "AC-6(d) worktree vanished"

# ============================================================================
echo "== AC-7: ground truth wins (with a live sibling as self-control) =="
ac7() {  # <audit> <repo> → report
  run_record "$1" "$2" "git worktree add -b feature/g1 ../repo-g1 && git worktree add -b feature/g2 ../repo-g2"
  ( cd "$2" && git worktree remove ../repo-g1 ) >/dev/null 2>&1   # out of band: NO hook
  run_report "$1" "$2"
}
r="$(new_repo)"; before="$ROOT/ac7.before"
run_record "$AUDIT" "$r" "git worktree add -b feature/g1 ../repo-g1 && git worktree add -b feature/g2 ../repo-g2"
( cd "$r" && git worktree remove ../repo-g1 ) >/dev/null 2>&1
cp "$(log_of "$r")" "$before"
out="$(run_report "$AUDIT" "$r")"
[ "$(rows "$out")" = "1" ] && ok "AC-7 exactly one row (the out-of-band-removed path is NOT reported)" || no "AC-7 rows: $(rows "$out") — $out"
printf '%s' "$out" | grep -q "^orphan	$(dirname "$r")/repo-g2	" && ok "AC-7 the row names the LIVE sibling g2" || no "AC-7 row: $out"
printf '%s' "$out" | grep -q "repo-g1" && no "AC-7 g1 leaked" || ok "AC-7 g1 (gone from git) is absent"
cmp -s "$before" "$(log_of "$r")" && ok "AC-7 the log is untouched by report (cmp)" || no "AC-7 report edited the log"
grep -c '"event":"created"' "$(log_of "$r")" | grep -qx 2 && ok "AC-7 both created lines are still in the log (input, not authority)" || no "AC-7 log content changed"

# ============================================================================
echo "== AC-8: fail-safe per case =="
r="$(new_repo)"
out="$(run_report "$AUDIT" "$r")"; [ "$(lastrc)" -eq 0 ] && [ -z "$out" ] && ok "AC-8(i) log absent ⇒ nothing, rc 0" || no "AC-8(i) rc=$(lastrc) out=$out"
if [ "$(id -u)" -eq 0 ]; then echo "  skipped: AC-8(ii) running as root"; else
  r="$(new_repo)"; run_record "$AUDIT" "$r" "git worktree add -b feature/u1 ../repo-u1"; chmod 000 "$(log_of "$r")"
  out="$(run_report "$AUDIT" "$r")"; [ "$(lastrc)" -eq 0 ] && [ -z "$out" ] && ok "AC-8(ii) log unreadable ⇒ nothing, rc 0" || no "AC-8(ii) rc=$(lastrc) out=$out"
  chmod 644 "$(log_of "$r")"
fi
r="$(new_repo)"; run_record "$AUDIT" "$r" "git worktree add -b feature/m1 ../repo-m1"
valid="$(last_line "$r")"
{ echo 'this is not json {'; echo "[2026-09-11T12:51:30Z] WORKTREE_CREATED $(cat "$WC_FIX" | jq -c .)"; echo '{"path":"/nowhere","ts":"x"}'; echo "$valid"; echo '42'; } > "$(log_of "$r")"
out="$(run_report "$AUDIT" "$r")"
[ "$(lastrc)" -eq 0 ] && [ "$(rows "$out")" = "1" ] && printf '%s' "$out" | grep -q "repo-m1" && ok "AC-8(iii) malformed + legacy + event-less lines interleaved ⇒ exactly the valid orphan row, rc 0" || no "AC-8(iii) rc=$(lastrc) rows=$(rows "$out") out=$out"
# (iv) git absent — PATH with only the non-git tools the script needs
shim="$(mktmp)"; for t in bash jq awk sed grep date mkdir dirname head cat wc tail tr cut env sort; do p="$(command -v "$t" 2>/dev/null)"; [ -n "$p" ] && ln -s "$p" "$shim/$t"; done
r="$(new_repo)"; ( cd "$r" && git worktree add -b feature/x1 ../repo-x1 ) >/dev/null 2>&1
( cd "$r" && payload "git worktree add -b feature/x1 ../repo-x1" "$r" | PATH="$shim" bash "$AUDIT" record ); rc=$?
l="$(last_line "$r")"
[ "$rc" -eq 0 ] && [ "$(log_lines "$r")" = "1" ] && [ "$(field "$l" '.confirmed')" = "null" ] && [ "$(field "$l" '.path')" = "$(dirname "$r")/repo-x1" ] \
  && ok "AC-8(iv) git absent ⇒ record still appends, confirmed: null, same log path" || no "AC-8(iv) record: rc=$rc lines=$(log_lines "$r") $l"
out="$( cd "$r" && PATH="$shim" bash "$AUDIT" report )"; rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "AC-8(iv) git absent ⇒ report prints nothing, rc 0" || no "AC-8(iv) report: rc=$rc out=$out"
out="$(run_report "$AUDIT" "$r")"
[ "$(rows "$out")" = "1" ] && printf '%s' "$out" | grep -q repo-x1 && ok "AC-8(iv) POSITIVE CONTROL: PATH restored, same log ⇒ one orphan row (silence was the missing tool)" || no "AC-8(iv) positive control failed: $out"
# (v) jq absent
nojq="$(mktmp)"; for t in bash git awk sed grep date mkdir dirname head cat wc tail tr cut env sort; do p="$(command -v "$t" 2>/dev/null)"; [ -n "$p" ] && ln -s "$p" "$nojq/$t"; done
r="$(new_repo)"; ( cd "$r" && git worktree add -b feature/j1 ../repo-j1 ) >/dev/null 2>&1
pl="$(payload "git worktree add -b feature/j1 ../repo-j1" "$r")"
( cd "$r" && printf '%s' "$pl" | PATH="$nojq" bash "$AUDIT" record ); rc=$?
[ "$rc" -eq 0 ] && [ "$(log_lines "$r")" = "0" ] && ok "AC-8(v) jq absent ⇒ nothing appended, rc 0" || no "AC-8(v) rc=$rc lines=$(log_lines "$r")"
# (vi) non-Bash tool / no git worktree / garbage
r="$(new_repo)"
( cd "$r" && payload "git worktree add ../repo-z1" "$r" | jq -c '.tool_name = "Write"' | bash "$AUDIT" record ); rc=$?
[ "$rc" -eq 0 ] && [ "$(log_lines "$r")" = "0" ] && ok "AC-8(vi) non-Bash tool ⇒ nothing, rc 0" || no "AC-8(vi) non-Bash: rc=$rc lines=$(log_lines "$r")"
record_only "$AUDIT" "$r" "git status && ls ../repo-worktree"
[ "$(lastrc)" -eq 0 ] && [ "$(log_lines "$r")" = "0" ] && ok "AC-8(vi) Bash without a worktree verb ⇒ nothing, rc 0" || no "AC-8(vi) no-verb: rc=$(lastrc) lines=$(log_lines "$r")"
( cd "$r" && printf 'not json at all {{{' | bash "$AUDIT" record ); rc=$?
[ "$rc" -eq 0 ] && [ "$(log_lines "$r")" = "0" ] && ok "AC-8(vi) garbage stdin ⇒ nothing, rc 0" || no "AC-8(vi) garbage: rc=$rc lines=$(log_lines "$r")"
( cd "$r" && printf '' | bash "$AUDIT" record ); rc=$?
[ "$rc" -eq 0 ] && [ "$(log_lines "$r")" = "0" ] && ok "AC-8(vi) empty stdin ⇒ nothing, rc 0" || no "AC-8(vi) empty: rc=$rc"
( cd "$r" && bash "$AUDIT" bogus-subcommand ); rc=$?
[ "$rc" -eq 0 ] && ok "AC-8 unknown subcommand ⇒ rc 0" || no "AC-8 unknown subcommand rc=$rc"
# (vii) note with missing / relative path
( cd "$r" && bash "$AUDIT" note created ); rc=$?
[ "$rc" -eq 0 ] && [ "$(log_lines "$r")" = "0" ] && ok "AC-8(vii) note with a missing path ⇒ nothing, rc 0" || no "AC-8(vii) missing: rc=$rc"
( cd "$r" && bash "$AUDIT" note created ../repo-rel ); rc=$?
[ "$rc" -eq 0 ] && [ "$(log_lines "$r")" = "0" ] && ok "AC-8(vii) note with a relative path ⇒ nothing, rc 0" || no "AC-8(vii) relative: rc=$rc"
( cd "$r" && bash "$AUDIT" note exploded /abs/path ); rc=$?
[ "$rc" -eq 0 ] && [ "$(log_lines "$r")" = "0" ] && ok "AC-8(vii) note with an unknown event ⇒ nothing, rc 0" || no "AC-8(vii) event: rc=$rc"
# log root walk accepts a `.git` FILE (linked worktree) — record from inside a worktree
# (the worktree gets its own `.supervisor/`, as a plugin-run linked checkout has).
r="$(new_repo)"; ( cd "$r" && git worktree add -b feature/lw ../repo-lw && mkdir ../repo-lw/.supervisor ) >/dev/null 2>&1
[ -f "$(dirname "$r")/repo-lw/.git" ] && ok "AC-8 precondition: a linked worktree's .git is a FILE" || no "AC-8 precondition: .git is not a file"
( cd "$(dirname "$r")/repo-lw" && bash "$AUDIT" note created "$(dirname "$r")/repo-lw" ); rc=$?
[ "$rc" -eq 0 ] && [ -f "$(dirname "$r")/repo-lw/$LOG_REL" ] && ok "AC-8 the log-root walk stops at a .git FILE (linked worktree) — no git needed" || no "AC-8 log root from a linked worktree: $(ls "$(dirname "$r")/repo-lw" 2>/dev/null)"

# ============================================================================
echo "== AC-8g: population gate — a repo the plugin never ran in is left alone =="
ac8g() {  # <audit> <bare_repo> — record + note against a repo with NO .supervisor/
  run_record "$1" "$2" "git worktree add -b feature/scratch ../repo-scratch"
  ( cd "$2" && bash "$1" note created "$(dirname "$2")/repo-scratch" ) >/dev/null 2>&1
}
b="$(bare_repo)"
[ ! -d "$b/.supervisor" ] && ok "AC-8g precondition: the bare repo has no .supervisor/" || no "AC-8g precondition failed"
ac8g "$AUDIT" "$b"
[ "$(lastrc)" -eq 0 ] && ok "AC-8g record exits 0 without .supervisor/" || no "AC-8g rc $(lastrc)"
[ ! -e "$b/.supervisor" ] && ok "AC-8g no .supervisor/ was created (record AND note)" || no "AC-8g .supervisor/ appeared: $(ls -a "$b/.supervisor" 2>/dev/null | tr '\n' ' ')"
[ "$(log_lines "$b")" = "0" ] && ok "AC-8g nothing appended without .supervisor/" || no "AC-8g lines: $(log_lines "$b")"
live_paths "$b" | grep -q "repo-scratch" && ok "AC-8g control: the worktree itself WAS created (silence is the gate, not a failed add)" || no "AC-8g control: worktree missing"
# positive control: the SAME commands in a repo WITH .supervisor/ append two lines
r="$(new_repo)"; ac8g "$AUDIT" "$r"
[ "$(log_lines "$r")" = "2" ] && ok "AC-8g POSITIVE CONTROL: with .supervisor/ present the same record + note append 2 lines" || no "AC-8g positive control lines: $(log_lines "$r")"
# a `-C <dir>` add from OUTSIDE the repo is gated on the -C target's root, not $PWD
b="$(bare_repo)"; parent="$(dirname "$b")"
( cd "$parent" && git -C repo worktree add -b feature/c1 ../repo-c1 ) >/dev/null 2>&1
( cd "$parent" && payload "git -C repo worktree add -b feature/c1 ../repo-c1" "$parent" | bash "$AUDIT" record ); rc=$?
[ "$rc" -eq 0 ] && [ ! -e "$b/.supervisor" ] && [ ! -e "$parent/.supervisor" ] && ok "AC-8g git -C into a bare repo ⇒ nothing, and no .supervisor/ at either the repo or the cwd" || no "AC-8g -C bare: rc=$rc"

# ============================================================================
echo "== AC-9: report is read-only =="
r="$(new_repo)"; parent="$(dirname "$r")"
run_record "$AUDIT" "$r" "git worktree add -b feature/r1 ../repo-r1 && git worktree add -b feature/r2 ../repo-r2"
stamp="$ROOT/ac9.stamp"; touch "$stamp"; sleep 1
b_find="$(find "$parent" -newer "$stamp" 2>/dev/null | sort)"; b_live="$(live_paths "$r")"; b_sha="$(sha "$(log_of "$r")")"
out="$(run_report "$AUDIT" "$r")"
[ "$(rows "$out")" = "2" ] && ok "AC-9 fixture yields two orphans" || no "AC-9 rows: $(rows "$out")"
[ "$(find "$parent" -newer "$stamp" 2>/dev/null | sort)" = "$b_find" ] && ok "AC-9 find -newer listing identical before/after" || no "AC-9 something was written: $(find "$parent" -newer "$stamp")"
[ "$(live_paths "$r")" = "$b_live" ] && ok "AC-9 git worktree list identical" || no "AC-9 worktree list changed"
[ "$(sha "$(log_of "$r")")" = "$b_sha" ] && ok "AC-9 log sha identical" || no "AC-9 log changed"

# ============================================================================
echo "== AC-10: mutation controls =="
# (a) hooks.json mutant re-adding the old WorktreeCreate bucket (embedded, not from hooks.json)
mut_json="$ROOT/hooks.mutant.json"
jq --argjson wc "$(cat <<'EOF'
[{"hooks":[{"type":"command","command":"INPUT=$(cat) && mkdir -p .supervisor/logs && echo \"[$(date -u +%Y-%m-%dT%H:%M:%SZ)] WORKTREE_CREATED $INPUT\" >> .supervisor/logs/worktrees.log && echo \"$INPUT\" | python3 -c \"import sys,json; print(json.load(sys.stdin).get('worktree_path',''))\" 2>/dev/null || true"}]}]
EOF
)" '.hooks.WorktreeCreate = $wc' "$HOOKS_JSON" > "$mut_json"
[ -s "$mut_json" ] && ! cmp -s "$mut_json" "$HOOKS_JSON" && jq -e . "$mut_json" >/dev/null 2>&1 && ok "AC-10(a) hooks.json mutant gated (non-empty, different, valid JSON)" || no "AC-10(a) mutant gate failed"
[ "$(jq '.hooks | has("WorktreeCreate") or has("WorktreeRemove")' "$mut_json")" = "true" ] && ok "AC-10(a) the mutant turns the AC-2 has() assertion red" || no "AC-10(a) mutant not detected"
gerr="$ROOT/gerr"
if old_json="$(git -C "$REPO_ROOT" show 03d9e2b:loomwright/hooks/hooks.json 2>"$gerr")" && [ -n "$old_json" ]; then
  [ "$(printf '%s' "$old_json" | jq '.hooks.WorktreeCreate[0].hooks[0].command')" = "$(jq '.hooks.WorktreeCreate[0].hooks[0].command' "$mut_json")" ] \
    && ok "AC-10(a) local cross-check: the embedded bucket equals 03d9e2b's verbatim" || no "AC-10(a) embedded bucket drifted from 03d9e2b"
else
  echo "  skipped: 03d9e2b unavailable ($(tr '\n' ' ' < "$gerr" | cut -c1-120))"
fi
# (b) record reads .worktree_path instead of .tool_input.command
d="$(mktmp)"; copy_with_siblings "$d"; MB="$d/worktree-audit.sh"
sed -i.bak 's/\.tool_input\.command \/\/ empty/.worktree_path \/\/ empty/' "$MB" && rm -f "$MB.bak"
if gate_mutant "$AUDIT" "$MB" "AC-10(b)"; then
  check_payload_reads "$MB" && no "AC-10(b) AC-1's payload-read check stayed GREEN on the .worktree_path mutant" || ok "AC-10(b) the mutant turns AC-1's payload-read check red (named control)"
  r="$(new_repo)"; run_record "$MB" "$r" "git branch feature/s1 && git worktree add ../repo-s1 feature/s1"
  [ "$(log_lines "$r")" = "0" ] && ok "AC-10(b) mutant appends nothing ⇒ AC-2's non-empty-path assertion red" || no "AC-10(b) mutant still appended: $(last_line "$r")"
  r="$(new_repo)"; out="$(ac3 "$MB" "$r")"
  [ "$(rows "$out")" = "1" ] && no "AC-10(b) AC-3 pairing stayed green on the mutant" || ok "AC-10(b) AC-3's pairing turns red on the mutant ($(rows "$out") rows, $(log_lines "$r") lines)"
fi
# (c) report drops the live-list intersection
d="$(mktmp)"; copy_with_siblings "$d"; MC="$d/worktree-audit.sh"
sed -i.bak 's/\[ "\$cur" -eq 1 \] || continue/: "intersection dropped"/' "$MC" && rm -f "$MC.bak"
if gate_mutant "$AUDIT" "$MC" "AC-10(c)"; then
  r="$(new_repo)"; out="$(ac7 "$MC" "$r")"
  [ "$(rows "$out")" = "2" ] && ok "AC-10(c) mutant reports the out-of-band-removed path ⇒ AC-7 red" || no "AC-10(c) AC-7 stayed green on the mutant: $out"
  r="$(new_repo)"; out="$(ac5 "$MC" "$r")"
  [ "$(rows "$out")" = "1" ] && ok "AC-10(c) AC-5 stays GREEN on the mutant (the red is AC-7's alone)" || no "AC-10(c) AC-5 went red — the mutant is merely broken"
fi
# (d) fold ignores `confirmed` on removed
d="$(mktmp)"; copy_with_siblings "$d"; MD="$d/worktree-audit.sh"
sed -i.bak 's/(\$e\.confirmed == true or \$e\.confirmed == null or \$e\.source == "direct")/true/' "$MD" && rm -f "$MD.bak"
if gate_mutant "$AUDIT" "$MD" "AC-10(d)"; then
  r="$(new_repo)"; out="$(ac6c "$MD" "$r")"
  [ "$(rows "$out")" = "0" ] && ok "AC-10(d) mutant hides the live worktree behind an unconfirmed removed ⇒ AC-6(c) red" || no "AC-10(d) AC-6(c) stayed green: $out"
  r="$(new_repo)"; out="$(ac5 "$MD" "$r")"
  [ "$(rows "$out")" = "1" ] && ok "AC-10(d) AC-5 stays green on the mutant" || no "AC-10(d) AC-5 went red"
  r="$(new_repo)"; out="$(ac7 "$MD" "$r")"
  [ "$(rows "$out")" = "1" ] && printf '%s' "$out" | grep -q repo-g2 && ok "AC-10(d) AC-7 stays green on the mutant" || no "AC-10(d) AC-7 went red"
fi
# (e) the add arm's branch-keyed fallback is dropped
d="$(mktmp)"; copy_with_siblings "$d"; ME="$d/worktree-audit.sh"
sed -i.bak 's/if \[ "\$PROBE_CONFIRMED" = false \] && unexpanded "\$rawpath"; then/if false; then/' "$ME" && rm -f "$ME.bak"
if gate_mutant "$AUDIT" "$ME" "AC-10(e)"; then
  r="$(new_repo)"; out="$(ac3f "$ME" "$r")"; l="$(last_line "$r")"
  [ "$(field "$l" '.confirmed')" = "false" ] && [ "$(rows "$out")" = "0" ] && ok "AC-10(e) mutant records ../\$(basename with confirmed:false and reports NO orphan ⇒ AC-3f red" || no "AC-10(e) AC-3f stayed green: $l / $out"
  r="$(new_repo)"; out="$(ac5 "$ME" "$r")"
  [ "$(rows "$out")" = "1" ] && ok "AC-10(e) AC-5 (literal path) stays green on the mutant" || no "AC-10(e) AC-5 went red"
fi
# (f) the .supervisor/ population gate is dropped
d="$(mktmp)"; copy_with_siblings "$d"; MF="$d/worktree-audit.sh"
sed -i.bak 's/^plugin_present() { \[ -d "\$1\/\.supervisor" \]; }$/plugin_present() { :; }/' "$MF" && rm -f "$MF.bak"
if gate_mutant "$AUDIT" "$MF" "AC-10(f)"; then
  b="$(bare_repo)"; ac8g "$MF" "$b"
  [ -d "$b/.supervisor" ] && [ "$(log_lines "$b")" = "2" ] && ok "AC-10(f) mutant creates .supervisor/ and appends in a repo the plugin never ran in ⇒ AC-8g red" || no "AC-10(f) AC-8g stayed green: dir=$([ -d "$b/.supervisor" ] && echo yes || echo no) lines=$(log_lines "$b")"
  r="$(new_repo)"; ac8g "$MF" "$r"
  [ "$(log_lines "$r")" = "2" ] && ok "AC-10(f) the positive control stays green on the mutant (the red is the gate's alone)" || no "AC-10(f) positive control went red"
fi
# (g) the fold ignores `source == "direct"` on removed
d="$(mktmp)"; copy_with_siblings "$d"; MG="$d/worktree-audit.sh"
sed -i.bak 's/ or \$e\.source == "direct")/)/' "$MG" && rm -f "$MG.bak"
if gate_mutant "$AUDIT" "$MG" "AC-10(g)"; then
  r="$(new_repo)"; out="$(ac6d "$MG" "$r")"
  [ "$(rows "$out")" = "1" ] && ok "AC-10(g) mutant keeps listing a dismissed worktree ⇒ AC-6(d) red" || no "AC-10(g) AC-6(d) stayed green: $out"
  r="$(new_repo)"; out="$(ac6c "$MG" "$r")"
  [ "$(rows "$out")" = "1" ] && ok "AC-10(g) AC-6(c) stays green on the mutant (an observed failed remove is still not a dismissal)" || no "AC-10(g) AC-6(c) went red"
fi

echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
