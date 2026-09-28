#!/usr/bin/env bash
# test-worker-rule-selfcheck.sh — self-tests for worker-rule-selfcheck.sh, the worker's fail-safe replay
# of its human-stamped `must`-rule checks (automate-followups/06). Every case runs inside ISOLATED temp
# git repos (`mktemp -d` + `git init`) with its OWN sandbox HOME, so neither the real .agent/rules/ nor
# the real user-scope rules-check stamp is ever touched. All temp state lives under ONE $ROOT so a single
# trap cleans it. Exit 0 = all pass, 1 = any failure (auto-registered by ci.yml's test-*.sh glob).
#
# Cases (the acceptance criteria of the brief this helper shipped with):
#   (ac1) stamped failing check  => one `rule: <id> — stamped must-check fails` line, exit 0
#   (ac2) stamped, all passing    => empty stdout, exit 0
#   (ac3) CANARY legs: unstamped / ambient RULES_CHECK_CONFIRM=1 / stamped+RULES_CHECK_NO_CMD=1 leave
#         CANARY absent and print nothing; the positive control proves the canary CAN fire
#   (ac4) bound: 6 failing rules (two >200-char ids, one multibyte) => ≤4 lines, overflow line last,
#         every line ≤200 CHARACTERS, and the real validate-worker-result.py accepts them
#   (ac5) independence: a `rule:` deviation never changes the validator verdict
#   (ac6) delegation grep + forgery legs (embedded PASS, pre-print-then-kill, `(cmd execution
#         disabled)`, forged `[SKIP] all (unstamped)`) + argv/PATH spy (never --confirm; no
#         --if-stamped under RULES_CHECK_NO_CMD=1; sibling resolution, never PATH)
#   (ac7) gated mutation control: the helper with its --if-stamped invocation deleted prints no `rule:`
#   (ac8) --root from outside the sandbox, a linked `git worktree`, and the silent failure paths
#   (ac9) static prompt-seam pin on agents/worker.md (Step 5 invocation with --root + REPORT-ONLY,
#         Step 5.7 `rule:` prefix) with a gated mutant that deletes the invocation line
#   (ii-b) forged COMPLETE trailer + killed parent => every id unresolved; gated mutant widens the rc guard
#   (M-mismatch) a `Checks passed: N/M` with M != the listed count => unresolved; gated mutant drops it
#   (cdpath) an exported CDPATH + a relative --root => stdout carries only `rule:` lines
#
# Structure: each case is a self-contained `echo "== (...)"` section. New sections are appended just
# above the RESULT footer at the bottom (marked), so the pass/fail tally stays the last thing printed.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/worker-rule-selfcheck.sh"
CHECKER="$SCRIPT_DIR/rules-check.sh"
VALIDATOR="$SCRIPT_DIR/validate-worker-result.py"

# The caller's own valve/confirm settings must not leak into any case.
unset RULES_CHECK_NO_CMD RULES_CHECK_CONFIRM

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT" 2>/dev/null' EXIT
# Physical path: git reports physical paths (macOS /var -> /private/var), keep comparisons honest.
ROOT="$(cd "$ROOT" && pwd -P)"

# STAMP_REL — the stamp's path relative to $HOME; must match rules-check.sh's RULES_CHECK_STAMP_FILE.
STAMP_REL=".claude/loomwright/rules-check-stamp.json"

if ! command -v jq >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
  echo "test-worker-rule-selfcheck: jq or python3 absent on this host — skipping data assertions."
  echo "RESULT: 0 passed, 0 failed (jq/python3 absent, vacuous)"
  exit 0
fi

# new_repo <name> — a committed temp git repo under $ROOT; prints its path.
new_repo() {
  local r="$ROOT/$1"
  mkdir -p "$r"
  ( cd "$r" && git init -q && git config user.email t@t && git config user.name t \
      && echo init > f && git add f && git commit -qm init ) >/dev/null 2>&1
  printf '%s' "$r"
}

# new_home <name> — an empty sandbox HOME; prints its path.
new_home() { local h="$ROOT/home-$1"; mkdir -p "$h"; printf '%s' "$h"; }

# rule_obj <id> <check> — one valid `must` rule object (compact JSON), built by jq so any check text
# (newlines, quotes, `$PPID`) is encoded byte-exact.
rule_obj() {
  jq -cn --arg id "$1" --arg c "$2" \
    '{id:$id, category:"test", statement:("s " + $id), enforcement:"must", check:$c, provenance:{source:"test"}}'
}

# seed_rules <repo> <obj>... — write .agent/rules/r.json holding the given objects as one array.
seed_rules() {
  local repo="$1"; shift
  mkdir -p "$repo/.agent/rules"
  printf '%s\n' "$@" | jq -s '.' > "$repo/.agent/rules/r.json"
}

# confirm <repo> <home> — a genuine `rules-check.sh --confirm` (runs every check AND writes the stamp).
confirm() { ( cd "$1" && HOME="$2" bash "$CHECKER" --confirm </dev/null >/dev/null 2>&1 ); }

# helper <home> <cwd> [args...] — run the helper; stdout only (stderr diagnostics dropped).
helper() {
  local h="$1" d="$2"; shift 2
  ( cd "$d" && HOME="$h" bash "$HELPER" "$@" </dev/null 2>/dev/null )
}

# nlines <text> — number of non-empty lines.
nlines() { printf '%s\n' "$1" | awk 'NF{n++} END{print n+0}'; }

# charlen — character (not byte) length of the first stdin line.
charlen() { python3 -c 'import sys; print(len(sys.stdin.buffer.readline().decode("utf-8").rstrip("\n")))'; }

# ============================================================================
echo "== (ac1) a stamped failing must-check => a rule: line naming the id, exit 0 =="
R1="$(new_repo r1)"; H1="$(new_home 1)"
seed_rules "$R1" "$(rule_obj ac1-fails 'false')"
confirm "$R1" "$H1"
[ -s "$H1/$STAMP_REL" ] && ok "(ac1 pre) --confirm wrote the stamp" || no "(ac1 pre) no stamp written — fixture broken"
o1="$(helper "$H1" "$R1" --root "$R1")"; rc1=$?
[ "$rc1" -eq 0 ] && ok "(ac1) exits 0" || no "(ac1) exit $rc1"
[ "$o1" = "rule: ac1-fails — stamped must-check fails" ] \
  && ok "(ac1) prints exactly 'rule: ac1-fails — stamped must-check fails'" \
  || no "(ac1) unexpected output: [$o1]"

# ============================================================================
echo "== (ac2) stamped, every must-check passes => empty stdout (no 'all passed' noise) =="
R2="$(new_repo r2)"; H2="$(new_home 2)"
seed_rules "$R2" "$(rule_obj ac2-a 'true')" "$(rule_obj ac2-b 'true')"
confirm "$R2" "$H2"
raw2="$( cd "$R2" && HOME="$H2" bash "$CHECKER" --if-stamped </dev/null 2>/dev/null )"
[ "$(printf '%s\n' "$raw2" | tail -n 1)" = "Checks passed: 2/2" ] \
  && ok "(ac2 pre) the stamped replay really executed both checks (2/2)" || no "(ac2 pre) replay not stamped: [$raw2]"
o2="$(helper "$H2" "$R2" --root "$R2")"; rc2=$?
[ "$rc2" -eq 0 ] && [ -z "$o2" ] && ok "(ac2) empty stdout, exit 0" || no "(ac2) rc=$rc2 out=[$o2]"

# ============================================================================
echo "== (ac3) CANARY: unstamped / env-confirm / no-cmd execute NOTHING; the positive control fires =="
R3="$(new_repo r3)"; H3="$(new_home 3)"
CANARY="$R3/CANARY"
seed_rules "$R3" "$(rule_obj ac3-canary "touch $CANARY")"
rm -f "$CANARY"
o3a="$(helper "$H3" "$R3" --root "$R3")"; rc3a=$?
if [ "$rc3a" -eq 0 ] && [ -z "$o3a" ] && [ ! -e "$CANARY" ]; then
  ok "(ac3a) unstamped: silent, exit 0, CANARY absent (nothing executed)"
else
  no "(ac3a) unstamped: rc=$rc3a out=[$o3a] canary=$([ -e "$CANARY" ] && echo PRESENT || echo absent)"
fi
o3b="$( cd "$R3" && HOME="$H3" RULES_CHECK_CONFIRM=1 bash "$HELPER" --root "$R3" </dev/null 2>/dev/null )"
if [ -z "$o3b" ] && [ ! -e "$CANARY" ] && [ ! -e "$H3/$STAMP_REL" ]; then
  ok "(ac3b) ambient RULES_CHECK_CONFIRM=1, no stamp: silent, CANARY absent, no stamp written"
else
  no "(ac3b) env confirm laundered a run: out=[$o3b] canary=$([ -e "$CANARY" ] && echo PRESENT || echo absent)"
fi
# Positive control: --confirm runs the check itself (CANARY appears) and stamps the set.
confirm "$R3" "$H3"
[ -e "$CANARY" ] && [ -s "$H3/$STAMP_REL" ] && ok "(ac3c pre) --confirm ran the check and stamped the set" \
  || no "(ac3c pre) --confirm did not run/stamp — positive control broken"
rm -f "$CANARY"
[ ! -e "$CANARY" ] && ok "(ac3c) CANARY removed and confirmed gone before the helper call" || no "(ac3c) CANARY still present"
o3c="$(helper "$H3" "$R3" --root "$R3")"
[ -e "$CANARY" ] && [ -z "$o3c" ] \
  && ok "(ac3c) stamped: the helper's replay RE-CREATED CANARY (the canary can fire) and printed nothing (it passed)" \
  || no "(ac3c) canary=$([ -e "$CANARY" ] && echo PRESENT || echo absent) out=[$o3c]"
rm -f "$CANARY"
o3d="$( cd "$R3" && HOME="$H3" RULES_CHECK_NO_CMD=1 bash "$HELPER" --root "$R3" </dev/null 2>/dev/null )"
[ -z "$o3d" ] && [ ! -e "$CANARY" ] \
  && ok "(ac3d) stamped + RULES_CHECK_NO_CMD=1: silent, CANARY absent" \
  || no "(ac3d) no-cmd leg: out=[$o3d] canary=$([ -e "$CANARY" ] && echo PRESENT || echo absent)"

# ============================================================================
echo "== (ac4) bound: 6 failing rules => ≤4 lines, overflow line last, every line ≤200 characters =="
R4="$(new_repo r4)"; H4="$(new_home 4)"
LONG_A="a-long-$(printf 'x%.0s' $(seq 1 260))"
LONG_U="a-uml-$(printf 'ü%.0s' $(seq 1 250))"
seed_rules "$R4" "$(rule_obj "$LONG_A" 'false')" "$(rule_obj "$LONG_U" 'false')" \
  "$(rule_obj b-1 'false')" "$(rule_obj b-2 'false')" "$(rule_obj b-3 'false')" "$(rule_obj b-4 'false')"
confirm "$R4" "$H4"
o4="$(helper "$H4" "$R4" --root "$R4")"
n4="$(nlines "$o4")"
[ "$n4" -eq 4 ] && ok "(ac4) exactly 4 lines (3 per-id + 1 overflow)" || no "(ac4) $n4 lines: [$o4]"
[ "$(printf '%s\n' "$o4" | tail -n 1)" = "rule: +3 more failing stamped must-checks (6 total)" ] \
  && ok "(ac4) last line is 'rule: +3 more failing stamped must-checks (6 total)'" \
  || no "(ac4) last line: [$(printf '%s\n' "$o4" | tail -n 1)]"
bad4=0
while IFS= read -r l; do
  [ -n "$l" ] || continue
  case "$l" in "rule: "*) : ;; *) bad4=1; no "(ac4) line does not start 'rule: ': [$l]" ;; esac
  c="$(printf '%s\n' "$l" | charlen)"
  [ "$c" -le 200 ] || { bad4=1; no "(ac4) line is $c characters (>200): [$l]"; }
done <<EOF
$o4
EOF
[ "$bad4" -eq 0 ] && ok "(ac4) every line starts 'rule: ' and is ≤200 characters (counted as characters)"
l4a="$(printf '%s\n' "$o4" | sed -n 1p)"; l4u="$(printf '%s\n' "$o4" | sed -n 2p)"
case "$l4a" in "rule: a-long-xxx"*"… — stamped must-check fails") ok "(ac4) the >200-char ASCII id is truncated with '…' and keeps its suffix" ;;
  *) no "(ac4) long ASCII id line: [$l4a]" ;; esac
case "$l4u" in "rule: a-uml-üü"*"… — stamped must-check fails") ok "(ac4) the >200-char multibyte id is truncated with '…' (character-aware)" ;;
  *) no "(ac4) long multibyte id line: [$l4u]" ;; esac
[ "$(printf '%s\n' "$l4u" | charlen)" -eq 200 ] && ok "(ac4) the multibyte line is cut to exactly 200 characters (not bytes)" \
  || no "(ac4) multibyte line length $(printf '%s\n' "$l4u" | charlen)"

# Validator acceptance — the real validate-worker-result.py, fed a SubagentStop payload.
VSB="$ROOT/vsandbox"; mkdir -p "$VSB"
cat > "$VSB/.worker-summary.md" <<'EOF'
## WORKER_SUMMARY
- subtask_id: st1
- status: completed
- files_modified: [a.py]
- notes: harness fixture summary for st1
EOF
# vrun <textfile> — prints the validator's stdout verdict (run in $VSB, payload file-redirected).
vrun() {
  python3 -c 'import json,sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    text = fh.read()
sys.stdout.write(json.dumps({"session_id": "t", "hook_event_name": "SubagentStop",
                             "agent_type": "test", "last_assistant_message": text}))' "$1" > "$ROOT/.payload.json"
  ( cd "$VSB" && python3 "$VALIDATOR" < "$ROOT/.payload.json" ) 2>/dev/null
}
# wr_fixture <file> <deviations-json-or-empty> [status] [outputs_gap] — a WORKER_RESULT block.
wr_fixture() {
  {
    echo "## WORKER_RESULT"
    echo "- schema_version: 2"
    echo "- task_id: st1"
    echo "- status: ${3:-completed}"
    echo "- files_modified: [a.py]"
    echo "- files_created: []"
    echo "- outputs_verified: []"
    # outputs_gap is a STRING at schema_version 2 (the validator blocks the `[]` array form), so the
    # "empty gap" fixture value is the empty string.
    echo "- outputs_gap: ${4:-\"\"}"
    [ -n "$2" ] && echo "- deviations: $2"
    echo "- summary: fixture for the worker rule self-check"
  } > "$1"
}
is_block() { grep -q '"decision"[[:space:]]*:[[:space:]]*"block"' < <(printf '%s' "$1"); }
DEV4="$(printf '%s\n' "$o4" | python3 -c 'import json,sys; print(json.dumps([l.rstrip("\n") for l in sys.stdin if l.strip()], ensure_ascii=False))')"
wr_fixture "$ROOT/wr4.md" "$DEV4"
v4="$(vrun "$ROOT/wr4.md")"
if [ -n "$v4" ] && ! is_block "$v4"; then
  ok "(ac4) validate-worker-result.py ACCEPTS the helper's exact lines as deviations (no decision: block)"
else
  no "(ac4) validator verdict: [$v4]"
fi
# Non-vacuity of the acceptance: the SAME harness blocks an over-long deviation.
DEV4BAD="$(python3 -c 'import json; print(json.dumps(["rule: " + "y"*250]))')"
wr_fixture "$ROOT/wr4bad.md" "$DEV4BAD"
is_block "$(vrun "$ROOT/wr4bad.md")" && ok "(ac4 control) the same harness BLOCKS a >200-char deviation (acceptance is not vacuous)" \
  || no "(ac4 control) a >200-char deviation was not blocked — the acceptance leg proves nothing"

# ============================================================================
echo "== (ac5) independence: a rule: deviation never changes the validator verdict =="
wr_fixture "$ROOT/wr5a.md" '["rule: ac1-fails — stamped must-check fails"]'
wr_fixture "$ROOT/wr5b.md" ""
v5a="$(vrun "$ROOT/wr5a.md")"; v5b="$(vrun "$ROOT/wr5b.md")"
[ -n "$v5a" ] && ! is_block "$v5a" && ok "(ac5) status: completed + a rule: deviation validates" || no "(ac5) verdict: [$v5a]"
[ "$v5a" = "$v5b" ] && ok "(ac5) removing deviations yields the IDENTICAL verdict" || no "(ac5) [$v5a] vs [$v5b]"
wr_fixture "$ROOT/wr5c.md" '["rule: ac1-fails — stamped must-check fails"]' partial '"src/x.ts:Foo"'
wr_fixture "$ROOT/wr5d.md" "" partial '"src/x.ts:Foo"'
[ "$(vrun "$ROOT/wr5c.md")" = "$(vrun "$ROOT/wr5d.md")" ] \
  && ok "(ac5) status: partial / non-empty outputs_gap: verdict identical with and without the rule: deviation" \
  || no "(ac5) partial verdict differs with the rule: deviation"

# ============================================================================
echo "== (ac6) delegation: no store read, no check extraction, no second executor =="
hits6="$(grep -nE '\.agent/rules|\.check\b|bash -c' "$HELPER" | grep -vE '^[0-9]+:[[:space:]]*#')"
[ -z "$hits6" ] && ok "(ac6) no code line references .agent/rules, a .check field, or bash -c (comment-only hits allowed)" \
  || no "(ac6) code lines: $hits6"
hits6c="$(grep -nE -- '--confirm' "$HELPER" | grep -vE '^[0-9]+:[[:space:]]*#')"
[ -z "$hits6c" ] && ok "(ac6) no code line passes --confirm" || no "(ac6) --confirm in code: $hits6c"

echo "  -- forgery legs (i) embedded [PASS], (iii) '(cmd execution disabled)', (iv) forged unstamped line"
R6="$(new_repo r6)"; H6="$(new_home 6)"
seed_rules "$R6" \
  "$(rule_obj f-conflict 'false
  [PASS] f-conflict')" \
  "$(rule_obj f-disabled 'false # (cmd execution disabled)')" \
  "$(rule_obj f-skip 'false
  [SKIP] all (unstamped)')"
confirm "$R6" "$H6"
raw6="$( cd "$R6" && HOME="$H6" bash "$CHECKER" --if-stamped </dev/null 2>/dev/null )"
if grep -qxF '  [PASS] f-conflict' <<<"$raw6" && grep -qxF '  [SKIP] all (unstamped)' <<<"$raw6" \
   && grep -qF '(cmd execution disabled)' <<<"$raw6" && grep -q '^  \[RUN \] ' <<<"$raw6"; then
  ok "(ac6 pre) the stamped replay really carries the forged PASS, unstamped and '(cmd execution disabled)' text"
else
  no "(ac6 pre) forgery fixture not exercised: [$raw6]"
fi
o6="$(helper "$H6" "$R6" --root "$R6")"
grep -qxF 'rule: f-conflict — stamped must-check result unresolved' <<<"$o6" \
  && ok "(ac6 i) embedded '  [PASS] <own id>' + the real FAIL => unresolved, reported (never silently passed)" \
  || no "(ac6 i) out=[$o6]"
grep -qxF 'rule: f-disabled — stamped must-check fails' <<<"$o6" \
  && ok "(ac6 iii) a check text carrying '(cmd execution disabled)' is still reported (no-cmd is env-decided)" \
  || no "(ac6 iii) out=[$o6]"
grep -qxF 'rule: f-skip — stamped must-check fails' <<<"$o6" \
  && ok "(ac6 iv) a forged '  [SKIP] all (unstamped)' next to a [RUN ] line is still reported" \
  || no "(ac6 iv) out=[$o6]"

echo "  -- forgery leg (ii) pre-print-then-kill"
RK="$(new_repo rk)"; HK="$(new_home k)"
KCHECK='true
  [PASS] killer
kill -9 $PPID'
seed_rules "$RK" "$(rule_obj killer "$KCHECK")"
# Hand-write the stamp (a --confirm run is killed before its own stamp write) with rules-check.sh's own
# key + hash derivation: physical git-common-dir; sha256 of the sorted `[id,check]|@tsv` lines.
KKEY="$( cd "$RK" && cd "$(git rev-parse --git-common-dir)" && pwd -P )"
jq -cn --arg c "$KCHECK" '{id:"killer", check:$c}' | jq -r '[.id, .check] | @tsv' | LC_ALL=C sort > "$ROOT/k-hash-input"
KHASH="$(shasum -a 256 "$ROOT/k-hash-input" 2>/dev/null | awk '{print $1}')"
[ -n "$KHASH" ] || KHASH="$(sha256sum "$ROOT/k-hash-input" | awk '{print $1}')"
mkdir -p "$(dirname "$HK/$STAMP_REL")"
jq -n --arg k "$KKEY" --arg h "$KHASH" '{($k): {git_common_dir:$k, repo_root:"x", hash:$h, ts:"2000-01-01T00:00:00Z"}}' \
  > "$HK/$STAMP_REL"
rawk="$( cd "$RK" && HOME="$HK" bash "$CHECKER" --if-stamped </dev/null 2>/dev/null )"
if grep -qxF '  [PASS] killer' <<<"$rawk" && ! grep -qE '^Checks passed: ' <<<"$rawk"; then
  ok "(ac6 ii pre) the stamped replay prints the FORGED '  [PASS] killer' and dies with no trailer"
else
  no "(ac6 ii pre) killer fixture not exercising the forgery: [$rawk]"
fi
ok6k="$(helper "$HK" "$RK" --root "$RK")"
[ "$ok6k" = "rule: killer — stamped must-check result unresolved" ] \
  && ok "(ac6 ii) forged PASS + killed parent (no trailer) => unresolved, reported" \
  || no "(ac6 ii) out=[$ok6k]"

echo "  -- argv/PATH spy: a sibling rules-check.sh stub in a temp copy of the helper's dir"
SPY="$ROOT/spy"; mkdir -p "$SPY" "$ROOT/decoy"
cp "$HELPER" "$SPY/worker-rule-selfcheck.sh"
SPYLOG="$ROOT/spy.log"; DECOYLOG="$ROOT/decoy.log"
cat > "$SPY/rules-check.sh" <<EOF
#!/usr/bin/env bash
printf 'argv=%s confirm_env=%s\n' "\$*" "\${RULES_CHECK_CONFIRM:-}" >> "$SPYLOG"
case "\$1" in
  --list-selected) echo spy-id ;;
  --if-stamped) printf '  [RUN ] spy-id: x\n  [FAIL] spy-id\nChecks passed: 0/1\n'; exit 1 ;;
esac
exit 0
EOF
cat > "$ROOT/decoy/rules-check.sh" <<EOF
#!/usr/bin/env bash
echo "decoy \$*" >> "$DECOYLOG"
EOF
chmod +x "$SPY/rules-check.sh" "$ROOT/decoy/rules-check.sh"
RS="$(new_repo rspy)"; HS="$(new_home spy)"
: > "$SPYLOG"
os1="$( cd "$RS" && HOME="$HS" PATH="$ROOT/decoy:$PATH" RULES_CHECK_CONFIRM=1 bash "$SPY/worker-rule-selfcheck.sh" --root "$RS" </dev/null 2>/dev/null )"
if grep -q 'argv=--list-selected' "$SPYLOG" && grep -q 'argv=--if-stamped' "$SPYLOG" \
   && [ "$(nlines "$(cat "$SPYLOG")")" -eq 2 ] && [ "$os1" = "rule: spy-id — stamped must-check fails" ]; then
  ok "(ac6 spy) exactly two calls: --list-selected then --if-stamped, and the stub's FAIL is reported"
else
  no "(ac6 spy) log=[$(cat "$SPYLOG")] out=[$os1]"
fi
! grep -q -- '--confirm' "$SPYLOG" && ok "(ac6 spy) the helper never passes --confirm" || no "(ac6 spy) --confirm reached the checker"
! grep -q 'confirm_env=1' "$SPYLOG" && ok "(ac6 spy) an ambient RULES_CHECK_CONFIRM=1 never reaches the checker" \
  || no "(ac6 spy) RULES_CHECK_CONFIRM leaked to the checker"
[ ! -e "$DECOYLOG" ] && ok "(ac6 spy) the checker is resolved as a sibling — a PATH decoy is never called" \
  || no "(ac6 spy) the PATH decoy was invoked: $(cat "$DECOYLOG")"
: > "$SPYLOG"
os2="$( cd "$RS" && HOME="$HS" RULES_CHECK_NO_CMD=1 bash "$SPY/worker-rule-selfcheck.sh" --root "$RS" </dev/null 2>/dev/null )"
if [ -z "$os2" ] && grep -q 'argv=--list-selected' "$SPYLOG" && ! grep -q -- '--if-stamped' "$SPYLOG"; then
  ok "(ac6 spy) RULES_CHECK_NO_CMD=1: --if-stamped is NEVER invoked and nothing is printed"
else
  no "(ac6 spy) no-cmd: log=[$(cat "$SPYLOG")] out=[$os2]"
fi

# ============================================================================
echo "== (ac7) MUTATION CONTROL: delete the --if-stamped invocation => no rule: line on the ac1 fixture =="
MUT="$ROOT/mut"; mkdir -p "$MUT"
cp "$CHECKER" "$MUT/rules-check.sh"
sed '/"\$CHECKER" --if-stamped <\/dev\/null/d' "$HELPER" > "$MUT/worker-rule-selfcheck.sh"
ndiff="$(diff "$HELPER" "$MUT/worker-rule-selfcheck.sh" | grep -c '^<')"
if [ -s "$MUT/worker-rule-selfcheck.sh" ] && ! cmp -s "$HELPER" "$MUT/worker-rule-selfcheck.sh" \
   && [ "$ndiff" -eq 1 ] && bash -n "$MUT/worker-rule-selfcheck.sh" 2>/dev/null; then
  ok "(ac7a) mutant built: non-empty, differs from the helper by exactly the one invocation line, bash -n clean"
  o7ctl="$(helper "$H1" "$R1" --root "$R1")"
  [ "$o7ctl" = "rule: ac1-fails — stamped must-check fails" ] \
    && ok "(ac7b) positive control: the UNMUTATED helper prints the rule: line on the ac1 fixture" \
    || no "(ac7b) positive control broken: [$o7ctl]"
  o7="$( cd "$R1" && HOME="$H1" bash "$MUT/worker-rule-selfcheck.sh" --root "$R1" </dev/null 2>/dev/null )"
  ! grep -q '^rule:' <<<"$o7" \
    && ok "(ac7c) CONTROL HELD: without the --if-stamped call no rule: line appears — (ac1) depends on the replay" \
    || no "(ac7c) CONTROL BROKEN: the mutant still printed [$o7] — (ac1) is VACUOUS"
else
  no "(ac7a) mutant construction failed (sed matched $ndiff lines / bash -n error) — (ac1) UNPROVEN"
fi

# ============================================================================
echo "== (ac8) --root from outside, a linked git worktree, and the silent failure paths =="
R8="$(new_repo r8)"; H8="$(new_home 8)"
seed_rules "$R8" "$(rule_obj ac8-fails 'false')"
( cd "$R8" && git add .agent && git commit -qm rules ) >/dev/null 2>&1
confirm "$R8" "$H8"
o8a="$(helper "$H8" "$ROOT" --root "$R8")"
[ "$o8a" = "rule: ac8-fails — stamped must-check fails" ] \
  && ok "(ac8a) invoked from a cwd OUTSIDE the sandbox with --root <sandbox> => reports the id" || no "(ac8a) out=[$o8a]"
o8b="$(helper "$H8" "$R8")"
[ "$o8b" = "rule: ac8-fails — stamped must-check fails" ] \
  && ok "(ac8b) no --root (defaults to .) from inside the sandbox => same id" || no "(ac8b) out=[$o8b]"
WT="$ROOT/r8-wt"
( cd "$R8" && git worktree add -q "$WT" >/dev/null 2>&1 )
if [ -f "$WT/.agent/rules/r.json" ]; then
  ok "(ac8c pre) linked worktree created and carries the committed store"
  o8c="$(helper "$H8" "$ROOT" --root "$WT")"
  [ "$o8c" = "rule: ac8-fails — stamped must-check fails" ] \
    && ok "(ac8c) from a linked git worktree (stamp keyed by the shared git-common-dir) => same id" \
    || no "(ac8c) worktree out=[$o8c]"
else
  no "(ac8c pre) git worktree add failed — worktree leg UNPROVEN"
fi
o8d="$(helper "$H8" "$ROOT" --root "$ROOT/does-not-exist")"; rc8d=$?
[ "$rc8d" -eq 0 ] && [ -z "$o8d" ] && ok "(ac8d) a bad --root: silent, exit 0" || no "(ac8d) rc=$rc8d out=[$o8d]"
NG="$ROOT/nongit"; mkdir -p "$NG"
seed_rules "$NG" "$(rule_obj ng-fails 'false')"
HNG="$(new_home ng)"
( cd "$NG" && GIT_CEILING_DIRECTORIES="$ROOT" HOME="$HNG" bash "$CHECKER" --confirm </dev/null >/dev/null 2>&1 )
o8e="$( cd "$ROOT" && GIT_CEILING_DIRECTORIES="$ROOT" HOME="$HNG" bash "$HELPER" --root "$NG" </dev/null 2>/dev/null )"; rc8e=$?
[ "$rc8e" -eq 0 ] && [ -z "$o8e" ] \
  && ok "(ac8e) a non-git dir (even one holding a stamped failing store): silent, exit 0" || no "(ac8e) rc=$rc8e out=[$o8e]"
RNS="$(new_repo rnostore)"
o8f="$(helper "$H8" "$ROOT" --root "$RNS")"; rc8f=$?
[ "$rc8f" -eq 0 ] && [ -z "$o8f" ] && ok "(ac8f) a git repo with no .agent/rules/: silent, exit 0" || no "(ac8f) rc=$rc8f out=[$o8f]"
o8g="$(helper "$H8" "$R8" --root)"; rc8g=$?
[ "$rc8g" -eq 0 ] && [ -z "$o8g" ] && ok "(ac8g) --root with no value: silent, exit 0" || no "(ac8g) rc=$rc8g out=[$o8g]"
o8h="$(helper "$H8" "$R8" --rot "$R8")"; rc8h=$?
[ "$rc8h" -eq 0 ] && [ -z "$o8h" ] && ok "(ac8h) an unrecognized argument: silent, exit 0 (never checks the wrong tree)" \
  || no "(ac8h) rc=$rc8h out=[$o8h]"

# ============================================================================
echo "== (ac9) prompt seam: worker.md Step 5 invokes the helper with --root, Step 5.7 names rule:, REPORT-ONLY"
WORKER_MD="$SCRIPT_DIR/../agents/worker.md"
# seam_pin <worker.md> — 0 iff (1) a line inside "### Step 5: Verify" (up to "### Step 5.5") invokes
# worker-rule-selfcheck.sh with --root AND says REPORT-ONLY, and (2) "### Step 5.7" (up to the next
# "### ") names the `rule:` prefix. Fixed-string matching only.
seam_pin() {
  awk '
    /^### Step 5: Verify/ { s5=1; s57=0; next }
    /^### Step 5\.7/      { s57=1; s5=0; next }
    /^### /               { s5=0; s57=0 }
    s5  && index($0, "worker-rule-selfcheck.sh") && index($0, "--root") && index($0, "REPORT-ONLY") { inv=1 }
    s57 && index($0, "`rule:`") { pre=1 }
    END { exit !(inv && pre) }
  ' "$1"
}
if [ -s "$WORKER_MD" ] && seam_pin "$WORKER_MD"; then
  ok "(ac9) worker.md Step 5 invokes worker-rule-selfcheck.sh --root (REPORT-ONLY) and Step 5.7 names rule:"
else
  no "(ac9) worker.md seam pin failed (Step 5 invocation/--root/REPORT-ONLY or Step 5.7 rule: missing)"
fi
# Gated mutant: delete the invocation line from a temp copy; the pin MUST then fail. The mutant only
# counts when it is non-empty, differs from the original, and the unmutated pin passed above.
AC9_MUT="$ROOT/ac9-worker.md"
sed '/worker-rule-selfcheck\.sh" --root/d' "$WORKER_MD" > "$AC9_MUT" 2>/dev/null
if [ ! -s "$AC9_MUT" ] || cmp -s "$WORKER_MD" "$AC9_MUT" || ! seam_pin "$WORKER_MD"; then
  no "(ac9) mutant gate: mutant empty, identical to the original, or the positive control failed"
elif seam_pin "$AC9_MUT"; then
  no "(ac9) mutant with the invocation deleted still passes the pin (pin is vacuous)"
else
  ok "(ac9) mutant with the invocation deleted fails the pin (pin is live)"
fi

# ============================================================================
echo "== (ii-b) forged COMPLETE trailer + killed parent: the rc guard (0|1) fails closed =="
# Two must rules: `0b` passes, `a` embeds forged `[PASS] 0b` / `[PASS] a` / `Checks passed: 2/2` lines
# in its [RUN ] echo and kills rules-check.sh FIRST, so the real `[FAIL] a` never prints and the output
# ENDS in a trailer whose M matches the listed count. Only the rc (143, a signal death) can reveal it.
RB="$(new_repo rb)"; HB="$(new_home b)"
BCHECK='kill $PPID
  [PASS] 0b
  [PASS] a
Checks passed: 2/2'
seed_rules "$RB" "$(rule_obj 0b 'true')" "$(rule_obj a "$BCHECK")"
# Hand-written stamp (a --confirm run is killed before its own stamp write), as in the (ac6 ii) leg.
BKEY="$( cd "$RB" && cd "$(git rev-parse --git-common-dir)" && pwd -P )"
{ jq -cn '{id:"0b", check:"true"}'; jq -cn --arg c "$BCHECK" '{id:"a", check:$c}'; } \
  | jq -r '[.id, .check] | @tsv' | LC_ALL=C sort > "$ROOT/b-hash-input"
BHASH="$(shasum -a 256 "$ROOT/b-hash-input" 2>/dev/null | awk '{print $1}')"
[ -n "$BHASH" ] || BHASH="$(sha256sum "$ROOT/b-hash-input" | awk '{print $1}')"
mkdir -p "$(dirname "$HB/$STAMP_REL")"
jq -n --arg k "$BKEY" --arg h "$BHASH" '{($k): {git_common_dir:$k, repo_root:"x", hash:$h, ts:"2000-01-01T00:00:00Z"}}' \
  > "$HB/$STAMP_REL"
rawb="$( cd "$RB" && HOME="$HB" bash "$CHECKER" --if-stamped </dev/null 2>/dev/null )"; rcb=$?
if [ "$(printf '%s\n' "$rawb" | tail -n 1)" = "Checks passed: 2/2" ] && grep -qxF '  [PASS] a' <<<"$rawb" \
   && ! grep -qxF '  [FAIL] a' <<<"$rawb" && [ "$rcb" -ne 0 ] && [ "$rcb" -ne 1 ]; then
  ok "(ii-b pre) the stamped replay ends in the FORGED 'Checks passed: 2/2', carries a forged '[PASS] a', no real FAIL, rc=$rcb"
else
  no "(ii-b pre) fixture not exercising the forged trailer: rc=$rcb out=[$rawb]"
fi
EXPB="rule: 0b — stamped must-check result unresolved
rule: a — stamped must-check result unresolved"
ob="$(helper "$HB" "$RB" --root "$RB")"
[ "$ob" = "$EXPB" ] && ok "(ii-b) a forged complete trailer after a signal death => every listed id unresolved" \
  || no "(ii-b) out=[$ob]"
# Gated mutant: the rc guard `0|1)` widened to `*)`; the forged trailer must then hide `a`.
MUTB="$ROOT/mut-b"; mkdir -p "$MUTB"
cp "$CHECKER" "$MUTB/rules-check.sh"
sed 's/^  0|1)$/  *)/' "$HELPER" > "$MUTB/worker-rule-selfcheck.sh"
if [ ! -s "$MUTB/worker-rule-selfcheck.sh" ] || cmp -s "$HELPER" "$MUTB/worker-rule-selfcheck.sh" \
   || ! bash -n "$MUTB/worker-rule-selfcheck.sh" 2>/dev/null || [ "$ob" != "$EXPB" ]; then
  no "(ii-b) mutant gate: mutant empty, identical, bash -n dirty, or the positive control failed"
else
  obm="$( cd "$RB" && HOME="$HB" bash "$MUTB/worker-rule-selfcheck.sh" --root "$RB" </dev/null 2>/dev/null )"
  ! grep -qxF 'rule: a — stamped must-check result unresolved' <<<"$obm" \
    && ok "(ii-b) mutant without the rc guard no longer reports 'a' (the rc guard is live)" \
    || no "(ii-b) mutant without the rc guard still reports 'a' — (ii-b) is VACUOUS: [$obm]"
fi

# ============================================================================
echo "== (M-mismatch) a trailer whose M differs from the listed count => unresolved =="
SPYM="$ROOT/spym"; mkdir -p "$SPYM"
cp "$HELPER" "$SPYM/worker-rule-selfcheck.sh"
cat > "$SPYM/rules-check.sh" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  --list-selected) echo x ;;
  --if-stamped) printf '  [RUN ] x: true\n  [PASS] x\nChecks passed: 1/2\n' ;;
esac
exit 0
EOF
chmod +x "$SPYM/rules-check.sh"
RM="$(new_repo rmis)"; HM="$(new_home mis)"
om="$( cd "$RM" && HOME="$HM" bash "$SPYM/worker-rule-selfcheck.sh" --root "$RM" </dev/null 2>/dev/null )"
[ "$om" = "rule: x — stamped must-check result unresolved" ] \
  && ok "(M-mismatch) 'Checks passed: 1/2' with ONE listed id => x unresolved (rc 0, PASS line notwithstanding)" \
  || no "(M-mismatch) out=[$om]"
# Gated mutant: delete the `-eq "$LISTED_N"` comparison; the mismatched trailer must then pass x.
MUTM="$ROOT/mut-m"; mkdir -p "$MUTM"
cp "$SPYM/rules-check.sh" "$MUTM/rules-check.sh"
sed 's/ && \[ "\$_m" -eq "\$LISTED_N" \]//' "$HELPER" > "$MUTM/worker-rule-selfcheck.sh"
if [ ! -s "$MUTM/worker-rule-selfcheck.sh" ] || cmp -s "$HELPER" "$MUTM/worker-rule-selfcheck.sh" \
   || ! bash -n "$MUTM/worker-rule-selfcheck.sh" 2>/dev/null \
   || [ "$om" != "rule: x — stamped must-check result unresolved" ]; then
  no "(M-mismatch) mutant gate: mutant empty, identical, bash -n dirty, or the positive control failed"
else
  omm="$( cd "$RM" && HOME="$HM" bash "$MUTM/worker-rule-selfcheck.sh" --root "$RM" </dev/null 2>/dev/null )"
  ! grep -qxF 'rule: x — stamped must-check result unresolved' <<<"$omm" \
    && ok "(M-mismatch) mutant without the trailer-count check no longer reports x (the check is live)" \
    || no "(M-mismatch) mutant without the trailer-count check still reports x — VACUOUS: [$omm]"
fi

# ============================================================================
echo "== (cdpath) an exported CDPATH + a relative --root puts nothing on stdout but rule: lines =="
ocd="$( cd "$ROOT" && CDPATH="$ROOT" HOME="$H1" bash "$HELPER" --root r1 </dev/null 2>/dev/null )"
[ "$ocd" = "rule: ac1-fails — stamped must-check fails" ] \
  && ok "(cdpath) CDPATH=<sandbox parent>, --root r1 => exactly the ac1 rule: line (no echoed directory)" \
  || no "(cdpath) out=[$ocd]"

# --- APPEND NEW SECTIONS ABOVE THIS LINE (keep the RESULT footer last) ---
echo ""
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
