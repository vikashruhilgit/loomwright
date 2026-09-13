#!/usr/bin/env bash
# test-classify-risk.sh — static self-tests for classify-risk.sh (the ONE high-risk-diff
# heuristic behind `automate-helpers.sh gate-eval` condition 6 and the Phase 4.5 red-team lens).
# Builds a fixture git repo in `mktemp -d` and runs the script from a DIFFERENT cwd with --root,
# proving the read-only / never-cd contract. No network, nothing outside the temp dir is touched.
# Exit 0 = all pass, 1 = any failure. Mirrors test-verify-provides.sh. UNCOUNTED by the doc-currency
# gate (a plain script, not an agent/command/skill/hook).
#
# Covers (AC3 / AC4 / AC5 / AC8 of brief 2026-09-13-high-risk-park-in-trusted-merge-gate):
#   A. output contract — one JSON object, always exit 0, fixed key set, source field
#   B. generic branches: (a) path match, (a) content-only match on an innocuous path, (b) workflow
#      directory, (b) word, (c) size by lines (>400), (c) size by files (>15); a clean small diff ⇒
#      false with reasons []; reasons are prefixed + name the pattern; case-insensitive
#   C. .agent/risk.json — `paths` glob (`**` across `/`) and `content` literal extend; malformed
#      (string `paths`, non-object root, invalid JSON) ⇒ generic-only + `risk_json_malformed` on
#      stderr, never null; `exclude` ⇒ ignored + `risk_json_exclude_ignored`, never honoured;
#      absent ⇒ silent; --root decides where it is read
#   D. unclassifiable ⇒ null + `unclassifiable: <reason>` + stderr, exit 0: bad ref, not a git
#      repo, bad args (missing refs, --root with no value, empty --root, unknown option); jq off
#      PATH ⇒ the ONE shell-templated object is still valid JSON
#   E. --kind-table == the docs/RESULT_SCHEMAS.md `<!-- risk-table:begin/end -->` block byte-for-byte
#   F. validate-supervisor-result.py accepts a SUPERVISOR_RESULT carrying the nested
#      `risk_classification` object (additive, schema_version stays 1)
#   G. read-only: the fixture repo's worktree and index are unchanged after every run
#   H. mutation control (LESSONS fa32a308): delete the content-match branch from a COPY of the
#      script (gated on non-empty + differs + `bash -n`) ⇒ the content-only case goes red while
#      the path case stays green — the case tests the branch, not the harness

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/classify-risk.sh"
SCHEMAS="$HERE/../docs/RESULT_SCHEMAS.md"
VALIDATOR="$HERE/validate-supervisor-result.py"
BASH_BIN="$(command -v bash)"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "test-classify-risk.sh: jq is required to run this suite"; echo "RESULT: 0 passed, 1 failed"; exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ELSEWHERE="$TMP/elsewhere"; mkdir -p "$ELSEWHERE"

# --- fixture repo -------------------------------------------------------------------------
# main: README.md + src/utils/format.ts; one branch per case, each ONE commit off main.
R="$TMP/repo"; mkdir -p "$R"
( cd "$R" && git init -q . && git config user.email t@example.com && git config user.name t \
  && git checkout -qb main && mkdir -p src/utils billing docs \
  && printf 'hello\n' > README.md && printf 'export const a = 1;\n' > src/utils/format.ts \
  && printf 'x\n' > billing/base.ts && git add -A && git commit -qm base )

mk_branch() {  # mk_branch <name> <shell snippet run inside the repo>  — commits everything
  ( cd "$R" && git checkout -q main && git checkout -qb "$1" && eval "$2" && git add -A && git commit -qm "$1" ) >/dev/null 2>&1
}
mk_branch clean       'printf "one\ntwo\nthree\n" >> README.md'
mk_branch path-auth   'mkdir -p src/Auth && printf "x\n" > src/Auth/login.ts'
mk_branch content-tok 'printf "const token = \"abc\";\n" >> src/utils/format.ts'
mk_branch wf-dir      'mkdir -p .github/workflows && printf "on: push\n" > .github/workflows/ci.yml'
mk_branch skills-dir  'mkdir -p loomwright/skills/x && printf "y\n" > loomwright/skills/x/SKILL.md'
mk_branch word-path   'mkdir -p docs; printf "z\n" > docs/Orchestration.md'
mk_branch big-lines   'i=0; while [ $i -lt 401 ]; do printf "line %s\n" $i >> README.md; i=$((i+1)); done'
mk_branch many-files  'mkdir -p docs; i=0; while [ $i -lt 16 ]; do printf "f\n" > "docs/f$i.md"; i=$((i+1)); done'
mk_branch billing     'printf "charge()\n" > billing/x.ts'
mk_branch stripe      'printf "call Stripe here\n" >> README.md'
mk_branch stub-header 'printf "++x\n" >> README.md'

run() {  # run <base> <head> [extra args...] — from ELSEWHERE; sets OUT / ERR / RC
  OUT="$(cd "$ELSEWHERE" && bash "$S" "$@" --root "$R" 2>"$TMP/err")"; RC=$?
  ERR="$(cat "$TMP/err")"
}
j() { printf '%s' "$OUT" | jq -r "$1"; }
jc() { printf '%s' "$OUT" | jq -c "$1"; }
one_json() { [ "$(printf '%s\n' "$OUT" | grep -c .)" -eq 1 ] && printf '%s' "$OUT" | jq -e . >/dev/null 2>&1; }
rm_rj() { rm -f "$R/.agent/risk.json"; }

# =============================================================================
echo "== A. output contract =="
run main clean
if [ "$RC" -eq 0 ] && one_json && [ "$(j '.source')" = "classify-risk.sh" ] \
   && [ "$(j 'keys|join(",")')" = "changed_files,changed_lines,high_risk,reasons,source" ]; then
  ok "A1 one JSON object, exit 0, fixed key set {high_risk,reasons,changed_files,changed_lines,source}"
else
  no "A1 output contract (rc=$RC out='$OUT')"
fi

# =============================================================================
echo "== B. generic heuristic branches =="
run main clean
if [ "$(j '.high_risk')" = "false" ] && [ "$(j '.reasons|length')" = "0" ] \
   && [ "$(j '.changed_files')" = "1" ] && [ "$(j '.changed_lines')" = "3" ]; then
  ok "B1 clean 3-line README change ⇒ high_risk=false, reasons=[], changed_files=1, changed_lines=3"
else
  no "B1 clean diff wrong ($OUT)"
fi

run main path-auth
if [ "$(j '.high_risk')" = "true" ] && [ "$(j '.reasons|index(["path: src/auth/login.ts matched *auth*"])')" != "null" ]; then
  ok "B2 (a) path match: src/Auth/login.ts ⇒ true with 'path: … matched *auth*' (case-insensitive)"
else
  no "B2 path-auth wrong ($OUT)"
fi

run main content-tok
if [ "$(j '.high_risk')" = "true" ] && [ "$(jc '.reasons')" = "$(jq -nc '["content: 1 changed line(s) matched *token*"]')" ]; then
  ok "B3 (a) content-only match: 'const token' on an innocuous path ⇒ true with ONLY the content reason"
else
  no "B3 content-tok wrong ($OUT)"
fi

run main wf-dir
if [ "$(j '.high_risk')" = "true" ] && [ "$(j '.reasons|index(["path: .github/workflows/ci.yml matched .github/workflows/"])')" != "null" ]; then
  ok "B4 (b) workflow directory ⇒ true with the directory reason"
else
  no "B4 wf-dir wrong ($OUT)"
fi
# .github/workflows/ci.yml also contains the (b) word "workflow" as a path substring — both fire.
[ "$(j '.reasons|index(["path: .github/workflows/ci.yml matched workflow"])')" != "null" ] \
  && ok "B4b (b) word 'workflow' also matched on the same path (path OR content, verbatim)" \
  || no "B4b word match on workflow path missing ($OUT)"

run main skills-dir
if [ "$(j '.high_risk')" = "true" ] && [ "$(jc '.reasons')" = "$(jq -nc '["path: loomwright/skills/x/skill.md matched skills/"]')" ]; then
  ok "B5 (b) skills/ anywhere below the root (loomwright/skills/…) ⇒ true, one-line change is enough"
else
  no "B5 skills-dir wrong ($OUT)"
fi

run main word-path
if [ "$(j '.high_risk')" = "true" ] && [ "$(jc '.reasons')" = "$(jq -nc '["path: docs/orchestration.md matched orchestration"]')" ]; then
  ok "B6 (b) word in path (Orchestration.md, case-insensitive) ⇒ true"
else
  no "B6 word-path wrong ($OUT)"
fi

run main big-lines
if [ "$(j '.high_risk')" = "true" ] && [ "$(j '.changed_lines')" = "401" ] && [ "$(jc '.reasons')" = "$(jq -nc '["size: changed_lines 401 > 400"]')" ]; then
  ok "B7 (c) 401 added lines ⇒ true with 'size: changed_lines 401 > 400' (400 itself is not > 400)"
else
  no "B7 big-lines wrong ($OUT)"
fi

run main many-files
if [ "$(j '.high_risk')" = "true" ] && [ "$(j '.changed_files')" = "16" ] && [ "$(jc '.reasons')" = "$(jq -nc '["size: changed_files 16 > 15"]')" ]; then
  ok "B8 (c) 16 changed files ⇒ true with 'size: changed_files 16 > 15'"
else
  no "B8 many-files wrong ($OUT)"
fi

run main stub-header
if [ "$(j '.high_risk')" = "false" ] && [ "$(j '.changed_lines')" = "0" ]; then
  ok "B9 honest limit pinned: an added line beginning '++' diffs as '+++x', indistinguishable from a header, and is not counted"
else
  no "B9 header-lookalike wrong ($OUT)"
fi

# =============================================================================
echo "== C. .agent/risk.json project extension (add-only) =="
mkdir -p "$R/.agent"
printf '{"schema_version":1,"paths":["billing/**"],"content":["stripe"]}\n' > "$R/.agent/risk.json"
run main billing
if [ "$(j '.high_risk')" = "true" ] && [ "$(jc '.reasons')" = "$(jq -nc '["project: billing/x.ts matched billing/**"]')" ] && [ -z "$ERR" ]; then
  ok "C1 paths glob billing/** + billing/x.ts diff ⇒ true with a project: reason, no stderr"
else
  no "C1 billing wrong ($OUT err='$ERR')"
fi
run main stripe
if [ "$(j '.high_risk')" = "true" ] && [ "$(jc '.reasons')" = "$(jq -nc '["project: 1 changed line(s) matched stripe"]')" ]; then
  ok "C2 content literal 'stripe' matches 'Stripe' in a changed line (case-insensitive) ⇒ project: reason"
else
  no "C2 stripe wrong ($OUT)"
fi
run main clean
[ "$(j '.high_risk')" = "false" ] && ok "C3 the extension only ADDS: the clean diff stays false with risk.json present" || no "C3 clean diff flipped by risk.json ($OUT)"

printf '{"schema_version":1,"paths":"billing/**"}\n' > "$R/.agent/risk.json"
run main billing
if [ "$(j '.high_risk')" = "false" ] && printf '%s' "$ERR" | grep -q 'risk_json_malformed'; then
  ok "C4 paths as a string (not array) ⇒ generic-only (false) + risk_json_malformed on stderr, never null"
else
  no "C4 malformed-string wrong ($OUT err='$ERR')"
fi
printf '[1,2]\n' > "$R/.agent/risk.json"
run main billing
[ "$(j '.high_risk')" = "false" ] && printf '%s' "$ERR" | grep -q 'risk_json_malformed' \
  && ok "C5 non-object root ⇒ generic-only + risk_json_malformed" || no "C5 non-object wrong ($OUT err='$ERR')"
printf '{not json\n' > "$R/.agent/risk.json"
run main billing
[ "$(j '.high_risk')" = "false" ] && printf '%s' "$ERR" | grep -q 'risk_json_malformed' \
  && ok "C6 invalid JSON ⇒ generic-only + risk_json_malformed" || no "C6 invalid-json wrong ($OUT err='$ERR')"
printf '{"schema_version":1,"paths":["billing/**"],"exclude":["billing/**"]}\n' > "$R/.agent/risk.json"
run main billing
if [ "$(j '.high_risk')" = "true" ] && printf '%s' "$ERR" | grep -q 'risk_json_exclude_ignored'; then
  ok "C7 exclude key is IGNORED (still true) + risk_json_exclude_ignored on stderr — never honoured (R5)"
else
  no "C7 exclude wrong ($OUT err='$ERR')"
fi
printf '{"schema_version":1,"exclude":["*"]}\n' > "$R/.agent/risk.json"
run main path-auth
[ "$(j '.high_risk')" = "true" ] && ok "C8 an exclude-only file cannot lower a generic classification" || no "C8 exclude lowered generic ($OUT)"
rm_rj
run main billing
[ "$(j '.high_risk')" = "false" ] && [ -z "$ERR" ] && ok "C9 absent risk.json ⇒ silent generic-only (billing diff is false)" || no "C9 absent wrong ($OUT err='$ERR')"
# --root decides where the file is read from: a risk.json in the CWD must not be picked up.
mkdir -p "$ELSEWHERE/.agent"; printf '{"schema_version":1,"paths":["billing/**"]}\n' > "$ELSEWHERE/.agent/risk.json"
run main billing
[ "$(j '.high_risk')" = "false" ] && ok "C10 a .agent/risk.json in the caller's cwd is NOT read — --root decides" || no "C10 cwd risk.json was read ($OUT)"
rm -rf "$ELSEWHERE/.agent"

# =============================================================================
echo "== D. unclassifiable ⇒ null, always exit 0 =="
unc() {  # unc <label> <reason> <args...>
  local label="$1" reason="$2"; shift 2
  OUT="$(cd "$ELSEWHERE" && bash "$S" "$@" 2>"$TMP/err")"; RC=$?; ERR="$(cat "$TMP/err")"
  if [ "$RC" -eq 0 ] && one_json && [ "$(j '.high_risk')" = "null" ] \
     && [ "$(jc '.reasons')" = "$(jq -nc --arg r "unclassifiable: $reason" '[$r]')" ] \
     && printf '%s' "$ERR" | grep -q "$reason"; then
    ok "$label ⇒ null + [\"unclassifiable: $reason\"] + stderr, exit 0"
  else
    no "$label wrong (rc=$RC out='$OUT' err='$ERR')"
  fi
}
unc "D1 bad head ref"           bad_ref         main no-such-branch --root "$R"
unc "D2 bad base ref"           bad_ref         no-such-branch clean --root "$R"
unc "D3 not a git repo"         not_a_git_repo  main clean --root "$ELSEWHERE"
unc "D4 missing refs"           bad_args        --root "$R"
unc "D5 --root with no value"   bad_args        main clean --root
unc "D6 empty --root"           bad_args        main clean --root=
unc "D7 unknown option"         bad_args        main clean --exclude x --root "$R"
OUT="$(cd "$ELSEWHERE" && PATH=/nonexistent "$BASH_BIN" "$S" main clean --root "$R" 2>"$TMP/err")"; RC=$?; ERR="$(cat "$TMP/err")"
if [ "$RC" -eq 0 ] && one_json && [ "$(j '.high_risk')" = "null" ] && [ "$(j '.reasons[0]')" = "unclassifiable: jq_missing" ] \
   && [ "$(j '.source')" = "classify-risk.sh" ] && printf '%s' "$ERR" | grep -q jq_missing; then
  ok "D8 jq off PATH ⇒ the ONE shell-templated object is valid JSON with null + unclassifiable: jq_missing"
else
  no "D8 jq-missing wrong (rc=$RC out='$OUT' err='$ERR')"
fi
OUT="$(cd "$ELSEWHERE" && PATH=/nonexistent "$BASH_BIN" "$S" --root 2>/dev/null)"; RC=$?
[ "$RC" -eq 0 ] && one_json && [ "$(j '.reasons[0]')" = "unclassifiable: bad_args" ] \
  && ok "D9 bad_args seen before jq is known ⇒ templated object, still valid JSON" || no "D9 templated bad_args wrong (out='$OUT')"

# =============================================================================
echo "== E. --kind-table is the single source; RESULT_SCHEMAS carries its ONE copy =="
bash "$S" --kind-table > "$TMP/table"; RC=$?
awk '$0=="<!-- risk-table:end -->"{p=0} p{print} $0=="<!-- risk-table:begin -->"{p=1}' "$SCHEMAS" > "$TMP/doc"
if [ "$RC" -eq 0 ] && [ -s "$TMP/table" ] && [ -s "$TMP/doc" ] && cmp -s "$TMP/table" "$TMP/doc"; then
  ok "E1 --kind-table output == RESULT_SCHEMAS <!-- risk-table:begin/end --> block byte-for-byte"
else
  no "E1 risk-table drift (regenerate the block from \`classify-risk.sh --kind-table\`):"; diff "$TMP/doc" "$TMP/table" | head -10
fi
[ "$(grep -c '^<!-- risk-table:begin -->$' "$SCHEMAS")" -eq 1 ] && ok "E2 exactly ONE committed copy of the table" || no "E2 marker count != 1"
grep -q '`\*token\*`' "$TMP/table" && grep -q 'changed_lines > 400' "$TMP/table" && grep -q 'changed_files > 15' "$TMP/table" \
  && grep -q '`skills/`' "$TMP/table" && grep -q 'NO `exclude` key' "$TMP/table" \
  && ok "E3 the table names every branch's data (a/b/c + project, no exclude)" || no "E3 table content incomplete"
# The lens and the loop POINT at the table instead of restating the pattern list.
LENS="$HERE/../skills/self-heal-advisory/SKILL.md"; LOOP="$HERE/../skills/automate-loop/SKILL.md"
grep -q 'classify-risk.sh' "$LENS" && ! grep -q '\*authz\*' "$LENS" \
  && ok "E4 self-heal-advisory lens calls classify-risk.sh and no longer restates the pattern list" || no "E4 lens still restates the heuristic or lacks the call"
grep -q 'classify-risk.sh' "$LOOP" && ! grep -q '\*authz\*' "$LOOP" \
  && ok "E5 automate-loop §10 cond 6 calls classify-risk.sh and does not restate the pattern list" || no "E5 loop restates or lacks the call"

# =============================================================================
echo "== F. validate-supervisor-result.py accepts the nested risk_classification object =="
cat > "$TMP/block.md" <<'EOF'
Phase 4.5 completed.

```yaml
SUPERVISOR_RESULT:
  schema_version: 1
  task_id: 2026-09-13-example
  status: completed
  pr_url: https://github.com/owner/repo/pull/1
  branch: feature/example
  subtasks_completed: 1
  subtasks_failed: 0
  heal_loop_ran: true
  heal_iterations: 0
  heal_decision: PASS
  heal_fixable_issues_fixed: 0
  heal_remaining_issues: 0
  error: null
  summary: "1/1 subtasks completed. red_team_advisory: skipped_low_risk"
  risk_classification:
    high_risk: false
    reasons: []
```
EOF
python3 -c 'import json,sys
sys.stdout.write(json.dumps({"session_id":"test-classify-risk","hook_event_name":"SubagentStop","agent_type":"test","last_assistant_message":open(sys.argv[1]).read()}))' "$TMP/block.md" > "$TMP/payload.json"
VOUT="$(cd "$ELSEWHERE" && python3 "$VALIDATOR" < "$TMP/payload.json" 2>/dev/null)"; VRC=$?
if [ "$VRC" -eq 0 ] && printf '%s' "$VOUT" | jq -e '.ok == true' >/dev/null 2>&1; then
  ok "F1 a SUPERVISOR_RESULT carrying risk_classification {high_risk:false, reasons:[]} validates (additive, schema_version 1)"
else
  no "F1 validator rejected the nested object (rc=$VRC out='$VOUT')"
fi
sed -e 's/high_risk: false/high_risk: null/' -e 's/reasons: \[\]/reasons: ["unclassifiable: bad_ref"]/' "$TMP/block.md" > "$TMP/block2.md"
python3 -c 'import json,sys
sys.stdout.write(json.dumps({"session_id":"test-classify-risk","hook_event_name":"SubagentStop","agent_type":"test","last_assistant_message":open(sys.argv[1]).read()}))' "$TMP/block2.md" > "$TMP/payload2.json"
VOUT="$(cd "$ELSEWHERE" && python3 "$VALIDATOR" < "$TMP/payload2.json" 2>/dev/null)"; VRC=$?
[ "$VRC" -eq 0 ] && printf '%s' "$VOUT" | jq -e '.ok == true' >/dev/null 2>&1 \
  && ok "F2 high_risk: null + an unclassifiable reason also validates" || no "F2 validator rejected null form (out='$VOUT')"

# =============================================================================
echo "== G. read-only =="
( cd "$R" && git checkout -q main ) 2>/dev/null
before="$(cd "$R" && git status --porcelain && git rev-parse HEAD && ls -a)"
run main path-auth; run main big-lines; run main no-such
after="$(cd "$R" && git status --porcelain && git rev-parse HEAD && ls -a)"
[ "$before" = "$after" ] && ok "G1 worktree, index, HEAD and directory listing unchanged after runs (incl. a failing one)" || no "G1 repo mutated: $(diff <(printf '%s' "$before") <(printf '%s' "$after"))"

# =============================================================================
echo "== H. mutation control — delete the content-match branch from a COPY =="
MUT="$TMP/mut"; mkdir -p "$MUT"
# Remove the two lines that record the content hit in the generic (a)/(b)-word loop.
awk '/^  n="\$\(content_hits "\$lit"\)"$/ {getline; next} {print}' "$S" > "$MUT/classify-risk.sh"
if [ -s "$MUT/classify-risk.sh" ] && ! cmp -s "$S" "$MUT/classify-risk.sh" && bash -n "$MUT/classify-risk.sh" 2>/dev/null \
   && ! grep -q 'content: \$n changed line(s) matched \$pat' "$MUT/classify-risk.sh"; then
  M_OUT="$(cd "$ELSEWHERE" && bash "$MUT/classify-risk.sh" main content-tok --root "$R" 2>/dev/null)"
  if [ "$(printf '%s' "$M_OUT" | jq -r '.high_risk')" = "false" ]; then
    ok "H1 (mutant) content branch deleted ⇒ the content-only case reads false — B3 is live, not vacuous"
  else
    no "H1 mutant not discriminated (out='$M_OUT')"
  fi
  M_OUT="$(cd "$ELSEWHERE" && bash "$MUT/classify-risk.sh" main path-auth --root "$R" 2>/dev/null)"
  [ "$(printf '%s' "$M_OUT" | jq -r '.high_risk')" = "true" ] \
    && ok "H2 (mutant) the path case stays green on the mutant" || no "H2 path case went red on the content mutant (out='$M_OUT')"
else
  no "H1 mutant not gated (empty, identical, bash -n failed, or the branch was not removed)"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
