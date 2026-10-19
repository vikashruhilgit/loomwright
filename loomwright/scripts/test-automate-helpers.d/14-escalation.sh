# =============================================================================
echo "== ESC. escalation-cause classifier + current-escalation writer (automate-followups/31) =="
# Replay fixtures (fixtures/escalation-cause/) through a stubbed gh: s2-c (`ci` red only in
# scripts/test-ci-local.sh, which PR #381 does not touch) and s2-d (`claude-review` still
# IN_PROGRESS). The stub reads its answers from files in $ESC_D so each leg edits one input.
ESC_FX="$HERE/fixtures/escalation-cause"
ESC_T="$(mktemp -d)"
ESC_C_SHA="a7f995344bbb9c33663b58fb7d0f691ddd9d513f"
ESC_C_URL="https://github.com/vikashruhilgit/loomwright/pull/381"
ESC_D_URL="https://github.com/vikashruhilgit/loomwright/pull/386"
cat > "$ESC_T/gh" <<'ESC_GH'
#!/usr/bin/env bash
d="$ESC_D"
case "$*" in
  *"--json baseRefName"*) printf '{"baseRefName":"main"}\n'; exit 0 ;;
  *"--json headRefOid,statusCheckRollup"*|*"--json statusCheckRollup"*)
    [ -f "$d/rollup.json" ] || exit 1; cat "$d/rollup.json"; exit 0 ;;
  *"--json changedFiles,files"*) [ -f "$d/files.json" ] || exit 1; cat "$d/files.json"; exit 0 ;;
  *"--paginate"*) [ -f "$d/paginate.txt" ] || exit 1; cat "$d/paginate.txt"; exit 0 ;;
  "api repos/"*"/protection")
    [ -f "$d/prot.err" ] && { cat "$d/prot.err" >&2; exit 1; }
    [ -f "$d/prot.json" ] && { cat "$d/prot.json"; exit 0; }
    printf '{"required_status_checks":{"contexts":["ci"]}}\n'; exit 0 ;;
  "run view "*" --json attempt") printf '{"attempt":%s}\n' "$(cat "$d/attempt" 2>/dev/null || echo 1)"; exit 0 ;;
  "run view "*" --log-failed")
    f="$d/log-$3.txt"; [ -f "$f" ] || exit 1; cat "$f"; exit 0 ;;
esac
exit 1
ESC_GH
chmod +x "$ESC_T/gh"
# esc_case <name> — a fresh answer dir seeded with the s2-c replay.
esc_case() {
  ESC_D="$ESC_T/$1"; mkdir -p "$ESC_D"
  cp "$ESC_FX/s2c-rollup.json" "$ESC_D/rollup.json"
  cp "$ESC_FX/s2c-files.json" "$ESC_D/files.json"
  cp "$ESC_FX/s2c-log-failed.txt" "$ESC_D/log-37254186674.txt"
  echo 1 > "$ESC_D/attempt"
}
# esc_run <helper> <url> <sha> — sets ESC_OUT / ESC_RC.
esc_run() {
  ESC_OUT="$(ESC_D="$ESC_D" LOOMWRIGHT_GH_BIN="$ESC_T/gh" bash "$1" escalation-cause "$2" --sha "$3" 2>/dev/null)"; ESC_RC=$?
}
# esc_expect <label> <want_line>
esc_expect() {
  if [ "$ESC_RC" -eq 0 ] && [ "$ESC_OUT" = "$2" ]; then ok "ESC $1: $ESC_OUT"; else no "ESC $1 (rc=$ESC_RC): got '$ESC_OUT' want '$2'"; fi
}
ESC_RED_C="escalation_cause: check_red check=ci run_id=37254186674 attempt=1 sha=$ESC_C_SHA"
ESC_RED_NULL="escalation_cause: check_red check=null run_id=null attempt=null sha=$ESC_C_SHA"

esc_case e1; esc_run "$H" "$ESC_C_URL" "$ESC_C_SHA"
esc_expect "AC1 s2-c replay ⇒ check_red_unrelated" "escalation_cause: check_red_unrelated check=ci run_id=37254186674 attempt=1 sha=$ESC_C_SHA"

esc_case e2; cp "$ESC_FX/s2d-rollup.json" "$ESC_D/rollup.json"; echo 1 > "$ESC_D/attempt"
esc_run "$H" "$ESC_D_URL" "1e35336"
esc_expect "AC2 s2-d replay ⇒ check_pending" "escalation_cause: check_pending check=claude-review run_id=37259136927 attempt=1 sha=1e35336"

# AC3: the failing test file, or its tested script, is in the PR's files ⇒ check_red.
esc_case e3a
jq -c '.changedFiles += 1 | .files += [{"path":"scripts/test-ci-local.sh"}]' "$ESC_FX/s2c-files.json" > "$ESC_D/files.json"
esc_run "$H" "$ESC_C_URL" "$ESC_C_SHA"; esc_expect "AC3 failing test file in the PR ⇒ check_red" "$ESC_RED_C"
esc_case e3b
jq -c '.changedFiles += 1 | .files += [{"path":"scripts/ci-local.sh"}]' "$ESC_FX/s2c-files.json" > "$ESC_D/files.json"
esc_run "$H" "$ESC_C_URL" "$ESC_C_SHA"; esc_expect "AC3 tested script <stem>.sh in the PR ⇒ check_red" "$ESC_RED_C"
esc_case e3c; echo 2 > "$ESC_D/attempt"
esc_run "$H" "$ESC_C_URL" "$ESC_C_SHA"
esc_expect "attempt is read from gh run view (attempt 2)" "escalation_cause: check_red_unrelated check=ci run_id=37254186674 attempt=2 sha=$ESC_C_SHA"

# AC4: every unreadable case fails CLOSED to check_red.
esc_case e4a; rm -f "$ESC_D/log-37254186674.txt"
esc_run "$H" "$ESC_C_URL" "$ESC_C_SHA"; esc_expect "AC4 unreadable --log-failed ⇒ check_red" "$ESC_RED_C"
esc_case e4b; rm -f "$ESC_D/files.json"
esc_run "$H" "$ESC_C_URL" "$ESC_C_SHA"; esc_expect "AC4 unreadable PR file list ⇒ check_red" "$ESC_RED_C"
esc_case e4c; jq -c '.changedFiles = 9' "$ESC_FX/s2c-files.json" > "$ESC_D/files.json"
esc_run "$H" "$ESC_C_URL" "$ESC_C_SHA"; esc_expect "AC4 incomplete PR file list (8 of 9, paginated re-read fails) ⇒ check_red" "$ESC_RED_C"
esc_case e4d; grep -v 'group\]Run bash' "$ESC_FX/s2c-log-failed.txt" > "$ESC_D/log-37254186674.txt"
esc_run "$H" "$ESC_C_URL" "$ESC_C_SHA"; esc_expect "AC4 no extractable failing test file ⇒ check_red" "$ESC_RED_C"
esc_case e4e; rm -f "$ESC_D/rollup.json"
esc_run "$H" "$ESC_C_URL" "$ESC_C_SHA"; esc_expect "AC4 gh snapshot read fails ⇒ check_red" "$ESC_RED_NULL"
esc_case e4f; echo 'gh: Resource not accessible by integration (HTTP 403)' > "$ESC_D/prot.err"
esc_run "$H" "$ESC_C_URL" "$ESC_C_SHA"; esc_expect "required=unknown (protection read 403) ⇒ check_red" "$ESC_RED_NULL"
esc_case e4g; jq -c 'del(.statusCheckRollup[0].detailsUrl)' "$ESC_FX/s2c-rollup.json" > "$ESC_D/rollup.json"
esc_run "$H" "$ESC_C_URL" "$ESC_C_SHA"
esc_expect "AC4 red check with no run id ⇒ check_red" "escalation_cause: check_red check=ci run_id=null attempt=null sha=$ESC_C_SHA"
esc_case e4h; esc_run "$H" "$ESC_C_URL" "0000000000"
esc_expect "AC4 snapshot for a different sha ⇒ check_red" "escalation_cause: check_red check=null run_id=null attempt=null sha=0000000000"
esc_case e5; jq -c '.statusCheckRollup[0].conclusion = "SUCCESS"' "$ESC_FX/s2c-rollup.json" > "$ESC_D/rollup.json"
esc_run "$H" "$ESC_C_URL" "$ESC_C_SHA"; esc_expect "nothing pending, nothing red ⇒ other" "escalation_cause: other check=null run_id=null attempt=null sha=$ESC_C_SHA"
esc_case e6; ESC_OUT="$(LOOMWRIGHT_GH_BIN="$ESC_T/gh" bash "$H" escalation-cause "$ESC_C_URL" 2>/dev/null)"; ESC_RC=$?
esc_expect "missing --sha ⇒ check_red, exit 0" "escalation_cause: check_red check=null run_id=null attempt=null sha=null"

# Review iteration 1 (fail-open on incomplete evidence): EVERY command of each failed
# (job, step) counts — a two-command step whose SECOND (non-test) command failed, an
# extra failed step running a non-test script, and a failed step with no Run block all
# fail CLOSED to check_red, even though the s2-c test file is unrelated.
esc_l() { printf '%s\t%s\t2026-10-07T00:00:00.0000000Z %s\n' "ci" "$1" "$2"; }
ESC_E=$'\033'
esc_case e7a
{ esc_l "Doc currency" "##[group]Run bash scripts/test-check-doc-currency.sh"
  esc_l "Doc currency" "${ESC_E}[36;1mbash scripts/test-check-doc-currency.sh${ESC_E}[0m"
  esc_l "Doc currency" "${ESC_E}[36;1mbash scripts/check-doc-currency.sh${ESC_E}[0m"
  esc_l "Doc currency" "##[endgroup]"
  esc_l "Doc currency" "FAIL: README claims 13 agents"; } > "$ESC_D/log-37254186674.txt"
esc_run "$H" "$ESC_C_URL" "$ESC_C_SHA"; esc_expect "two-command step (test-X.sh then X.sh) ⇒ check_red" "$ESC_RED_C"
esc_case e7b
{ cat "$ESC_FX/s2c-log-failed.txt"
  esc_l "Command sync" "##[group]Run bash scripts/check-command-sync.sh"
  esc_l "Command sync" "${ESC_E}[36;1mbash scripts/check-command-sync.sh${ESC_E}[0m"
  esc_l "Command sync" "##[endgroup]"; } > "$ESC_D/log-37254186674.txt"
esc_run "$H" "$ESC_C_URL" "$ESC_C_SHA"; esc_expect "mixed failed steps (unrelated test + non-test check) ⇒ check_red" "$ESC_RED_C"
esc_case e7c
{ cat "$ESC_FX/s2c-log-failed.txt"; esc_l "Set up job" "##[error]runner lost"; } > "$ESC_D/log-37254186674.txt"
esc_run "$H" "$ESC_C_URL" "$ESC_C_SHA"; esc_expect "a failed step with no Run block ⇒ check_red" "$ESC_RED_C"
esc_case e7d
{ esc_l "Doc currency" "##[group]Run bash scripts/test-check-doc-currency.sh"
  esc_l "Doc currency" "${ESC_E}[36;1mbash scripts/test-check-doc-currency.sh${ESC_E}[0m"
  esc_l "Doc currency" "${ESC_E}[36;1mbash scripts/test-check-token-budget.sh --self-test${ESC_E}[0m"
  esc_l "Doc currency" "##[endgroup]"; } > "$ESC_D/log-37254186674.txt"
esc_run "$H" "$ESC_C_URL" "$ESC_C_SHA"
esc_expect "control: a two-command step of only unrelated test files ⇒ check_red_unrelated" "escalation_cause: check_red_unrelated check=ci run_id=37254186674 attempt=1 sha=$ESC_C_SHA"
# MUTATION CONTROL: a parser that ignores a step's non-test commands (the pre-fix
# header-only behaviour) must turn the two-command leg check_red_unrelated.
ESC_MUT="$(mktemp -d)"
for e in "$(dirname "$H")"/*; do [ "$e" = "$H" ] || ln -s "$e" "$ESC_MUT/$(basename "$e")"; done
sed 's/^      } else bad = 1$/      }/' "$H" > "$ESC_MUT/automate-helpers.sh"
if [ -s "$ESC_MUT/automate-helpers.sh" ] && ! cmp -s "$H" "$ESC_MUT/automate-helpers.sh" && bash -n "$ESC_MUT/automate-helpers.sh" 2>/dev/null \
   && [ "$(diff "$H" "$ESC_MUT/automate-helpers.sh" | grep -c '^[<>]')" = 2 ]; then
  ESC_D="$ESC_T/e7a"; esc_run "$ESC_MUT/automate-helpers.sh" "$ESC_C_URL" "$ESC_C_SHA"
  case "$ESC_OUT" in "escalation_cause: check_red_unrelated "*) ok "ESC mutation control: ignoring a step's non-test command flips the two-command leg ($ESC_OUT)" ;;
    *) no "ESC mutation control did NOT discriminate: '$ESC_OUT'" ;; esac
else
  no "ESC mutation control (multi-command): could not build a valid mutant -- control inconclusive"
fi
rm -rf "$ESC_MUT"

# Review iteration 1 (verdict before a more-severe signal): red is examined BEFORE
# pending — a red check beside an IN_PROGRESS one is never check_pending.
esc_case e8a
jq -c '.statusCheckRollup[1].status = "IN_PROGRESS" | .statusCheckRollup[1].conclusion = ""' "$ESC_FX/s2c-rollup.json" > "$ESC_D/rollup.json"
jq -c '.changedFiles += 1 | .files += [{"path":"scripts/test-ci-local.sh"}]' "$ESC_FX/s2c-files.json" > "$ESC_D/files.json"
esc_run "$H" "$ESC_C_URL" "$ESC_C_SHA"; esc_expect "related red ci + pending claude-review ⇒ check_red (not check_pending)" "$ESC_RED_C"
esc_case e8b
jq -c '.statusCheckRollup[1].status = "IN_PROGRESS" | .statusCheckRollup[1].conclusion = ""' "$ESC_FX/s2c-rollup.json" > "$ESC_D/rollup.json"
esc_run "$H" "$ESC_C_URL" "$ESC_C_SHA"
esc_expect "unrelated red ci + pending claude-review ⇒ check_red_unrelated on ci (not check_pending)" "escalation_cause: check_red_unrelated check=ci run_id=37254186674 attempt=1 sha=$ESC_C_SHA"

# Review iteration 2 (fail-open parse trusting a PREFIX of log text): the WHOLE script
# line must be the test command — a shell operator / substitution / redirect after
# the test path is a non-test command ⇒ check_red; plain-word args stay a test line.
# esc_sub <case> <replacement for the s2-c script line's command> — one edited replay.
esc_sub() {
  esc_case "$1"
  ESC_SUB_R="$2" awk 'BEGIN { r = ENVIRON["ESC_SUB_R"] }
    { i = index($0, "mbash scripts/test-ci-local.sh"); if (i) $0 = substr($0, 1, i) r substr($0, i + 30) } { print }' \
    "$ESC_FX/s2c-log-failed.txt" > "$ESC_D/log-37254186674.txt"
}
ESC_UNREL_C="escalation_cause: check_red_unrelated check=ci run_id=37254186674 attempt=1 sha=$ESC_C_SHA"
esc_n=0
for esc_cmd in 'bash scripts/test-ci-local.sh && bash scripts/ci-local.sh' 'bash scripts/test-ci-local.sh || true' \
               'bash scripts/test-ci-local.sh | tee out.log' 'bash scripts/test-ci-local.sh & wait' \
               'bash scripts/test-ci-local.sh > out.log' 'bash scripts/test-ci-local.sh < in.txt' \
               'bash scripts/test-ci-local.sh $(cat args)' 'bash scripts/test-ci-local.sh `cat args`' \
               'bash scripts/test-ci-local.sh "a b"'; do
  esc_n=$((esc_n + 1)); esc_sub "e9op$esc_n" "$esc_cmd"
  esc_run "$H" "$ESC_C_URL" "$ESC_C_SHA"; esc_expect "a chained/redirected script line ($esc_cmd) ⇒ check_red" "$ESC_RED_C"
done
esc_sub e9plain 'bash scripts/test-ci-local.sh --self-test -v name=x'
esc_run "$H" "$ESC_C_URL" "$ESC_C_SHA"; esc_expect "control: a test line with plain-word args ⇒ check_red_unrelated" "$ESC_UNREL_C"
# MUTATION CONTROL: restore the prefix-only match (path then ` ` or end) ⇒ the `&&` leg
# turns check_red_unrelated.
ESC_MUT="$(mktemp -d)"
for e in "$(dirname "$H")"/*; do [ "$e" = "$H" ] || ln -s "$e" "$ESC_MUT/$(basename "$e")"; done
sed 's#test-\[A-Za-z0-9._-\]+\\\.sh( +\[A-Za-z0-9._\\/=:,@%+-\]+)\*\$/#test-[A-Za-z0-9._-]+\\.sh( |$)/#' "$H" > "$ESC_MUT/automate-helpers.sh"
if [ -s "$ESC_MUT/automate-helpers.sh" ] && ! cmp -s "$H" "$ESC_MUT/automate-helpers.sh" && bash -n "$ESC_MUT/automate-helpers.sh" 2>/dev/null \
   && [ "$(diff "$H" "$ESC_MUT/automate-helpers.sh" | grep -c '^[<>]')" = 2 ]; then
  ESC_D="$ESC_T/e9op1"; esc_run "$ESC_MUT/automate-helpers.sh" "$ESC_C_URL" "$ESC_C_SHA"
  [ "$ESC_OUT" = "$ESC_UNREL_C" ] && ok "ESC mutation control: a prefix-only test-line match flips the && leg ($ESC_OUT)" \
    || no "ESC prefix-only mutation control did NOT discriminate: '$ESC_OUT'"
else
  no "ESC prefix-only mutation control: could not build a valid mutant -- control inconclusive"
fi
rm -rf "$ESC_MUT"

# Review iteration 2 (path arithmetic assuming a `/`): AC3 for a BARE / `./` test path —
# `bash test-ci-local.sh` tests `ci-local.sh`, so a PR changing <dir>/ci-local.sh ⇒
# check_red; a `.`/`..` segment cannot be resolved ⇒ check_red (fail CLOSED).
for esc_bp in 'bash test-ci-local.sh' 'bash ./test-ci-local.sh' 'bash ./scripts/test-ci-local.sh'; do
  esc_n=$((esc_n + 1)); esc_sub "e10b$esc_n" "$esc_bp"
  jq -c '.changedFiles += 1 | .files += [{"path":"loomwright/scripts/ci-local.sh"}]' "$ESC_FX/s2c-files.json" > "$ESC_D/files.json"
  [ -n "${ESC_BARE_D:-}" ] || ESC_BARE_D="$ESC_D"
  esc_run "$H" "$ESC_C_URL" "$ESC_C_SHA"; esc_expect "AC3 '$esc_bp' + PR changes loomwright/scripts/ci-local.sh ⇒ check_red" "$ESC_RED_C"
  esc_n=$((esc_n + 1)); esc_sub "e10c$esc_n" "$esc_bp"
  esc_run "$H" "$ESC_C_URL" "$ESC_C_SHA"; esc_expect "control: '$esc_bp' with the tested script NOT in the PR ⇒ check_red_unrelated" "$ESC_UNREL_C"
done
esc_sub e10dot 'bash ../scripts/test-ci-local.sh'
esc_run "$H" "$ESC_C_URL" "$ESC_C_SHA"; esc_expect "a '..' test path (unresolvable) ⇒ check_red" "$ESC_RED_C"
# MUTATION CONTROL: restore the unconditional `${t%/*}/…` arithmetic ⇒ the bare leg
# (e10b first case) turns check_red_unrelated.
ESC_MUT="$(mktemp -d)"
for e in "$(dirname "$H")"/*; do [ "$e" = "$H" ] || ln -s "$e" "$ESC_MUT/$(basename "$e")"; done
sed 's#^  case "\$t" in \*/\*) script="\${t%/\*}/\${base\#test-}" ;; \*) script="\${base\#test-}" ;; esac$#  script="${t%/*}/${base\#test-}"#' "$H" > "$ESC_MUT/automate-helpers.sh"
if [ -s "$ESC_MUT/automate-helpers.sh" ] && ! cmp -s "$H" "$ESC_MUT/automate-helpers.sh" && bash -n "$ESC_MUT/automate-helpers.sh" 2>/dev/null \
   && [ "$(diff "$H" "$ESC_MUT/automate-helpers.sh" | grep -c '^[<>]')" = 2 ]; then
  ESC_D="$ESC_BARE_D"; esc_run "$ESC_MUT/automate-helpers.sh" "$ESC_C_URL" "$ESC_C_SHA"
  [ "$ESC_OUT" = "$ESC_UNREL_C" ] && ok "ESC mutation control: slash-assuming path arithmetic flips the bare-path AC3 leg ($ESC_OUT)" \
    || no "ESC bare-path mutation control did NOT discriminate: '$ESC_OUT'"
else
  no "ESC bare-path mutation control: could not build a valid mutant -- control inconclusive"
fi
rm -rf "$ESC_MUT"

# AC5 MUTATION CONTROL: a classifier that decides by test name alone (no PR-files comparison —
# every failing test file read as unrelated) must turn the AC3 related legs red.
ESC_MUT="$(mktemp -d)"
for e in "$(dirname "$H")"/*; do [ "$e" = "$H" ] || ln -s "$e" "$ESC_MUT/$(basename "$e")"; done
sed 's/^_esc_related() {$/_esc_related() { return 1/' "$H" > "$ESC_MUT/automate-helpers.sh"
if [ -s "$ESC_MUT/automate-helpers.sh" ] && ! cmp -s "$H" "$ESC_MUT/automate-helpers.sh" && bash -n "$ESC_MUT/automate-helpers.sh" 2>/dev/null \
   && grep -qxF '_esc_related() { return 1' "$ESC_MUT/automate-helpers.sh"; then
  ESC_D="$ESC_T/e3a"; esc_run "$ESC_MUT/automate-helpers.sh" "$ESC_C_URL" "$ESC_C_SHA"; esc_m1="$ESC_OUT"
  ESC_D="$ESC_T/e3b"; esc_run "$ESC_MUT/automate-helpers.sh" "$ESC_C_URL" "$ESC_C_SHA"; esc_m2="$ESC_OUT"
  if [ "$esc_m1" != "$ESC_RED_C" ] && [ "$esc_m2" != "$ESC_RED_C" ]; then
    ok "ESC AC5 mutation control: a name-only classifier fails both AC3 legs ($esc_m1)"
  else
    no "ESC AC5 mutation control did NOT discriminate (m1='$esc_m1' m2='$esc_m2')"
  fi
else
  no "ESC AC5 mutation control: could not build a valid mutant -- control inconclusive"
fi
rm -rf "$ESC_MUT"

# V5 (spaced check names): matrix-style required checks carry spaces. The snapshot line is read
# by the shared reader (wait-for-checks-line.sh), so the WHOLE name is recorded and its run id
# found — the word-splitting parse recorded `check=test run_id=null` and the merge watcher then
# polled a check named `test` that does not exist.
esc_prot() { printf '{"required_status_checks":{"contexts":%s}}\n' "$1" > "$ESC_D/prot.json"; }
esc_case e11a
jq -c '.statusCheckRollup[0] |= (.name = "test (18.x)" | .status = "IN_PROGRESS" | .conclusion = "")
       | .statusCheckRollup[1] |= (.status = "COMPLETED" | .conclusion = "SUCCESS")' "$ESC_FX/s2d-rollup.json" > "$ESC_D/rollup.json"
esc_prot '["test (18.x)"]'
esc_run "$H" "$ESC_D_URL" "1e35336"
ESC_SP_PEND="escalation_cause: check_pending check=test (18.x) run_id=37259136900 attempt=1 sha=1e35336"
esc_expect "V5 pending required 'test (18.x)' ⇒ check_pending on the whole name, run id from the rollup" "$ESC_SP_PEND"
esc_case e11b
jq -c '.statusCheckRollup[0].name = "build (ubuntu-latest)"' "$ESC_FX/s2c-rollup.json" > "$ESC_D/rollup.json"
esc_prot '["build (ubuntu-latest)"]'
esc_run "$H" "$ESC_C_URL" "$ESC_C_SHA"
ESC_SP_UNREL="escalation_cause: check_red_unrelated check=build (ubuntu-latest) run_id=37254186674 attempt=1 sha=$ESC_C_SHA"
esc_expect "V5 red 'build (ubuntu-latest)' in an unrelated test only ⇒ check_red_unrelated on the whole name" "$ESC_SP_UNREL"
esc_case e11c
jq -c '.statusCheckRollup[0].name = "build (ubuntu-latest)"' "$ESC_FX/s2c-rollup.json" > "$ESC_D/rollup.json"
jq -c '.changedFiles += 1 | .files += [{"path":"scripts/test-ci-local.sh"}]' "$ESC_FX/s2c-files.json" > "$ESC_D/files.json"
esc_prot '["build (ubuntu-latest)"]'
esc_run "$H" "$ESC_C_URL" "$ESC_C_SHA"
esc_expect "V5 red 'build (ubuntu-latest)' related to the PR ⇒ check_red, whole name + run id kept" \
  "escalation_cause: check_red check=build (ubuntu-latest) run_id=37254186674 attempt=1 sha=$ESC_C_SHA"
esc_case e11d
jq -c '.statusCheckRollup[0].name = "test (18.x)"
       | .statusCheckRollup += [(.statusCheckRollup[0] | .name = "build (ubuntu-latest)")]' "$ESC_FX/s2c-rollup.json" > "$ESC_D/rollup.json"
esc_prot '["test (18.x)","build (ubuntu-latest)"]'
esc_run "$H" "$ESC_C_URL" "$ESC_C_SHA"
esc_expect "V5 two spaced red checks, both unrelated ⇒ check_red_unrelated on the first whole name" \
  "escalation_cause: check_red_unrelated check=test (18.x) run_id=37254186674 attempt=1 sha=$ESC_C_SHA"
# The recorded line carries the spaced name through current-escalation (refuses only `|`/newline)
# and back out through the ` | ` field split the merge watcher's esc_fields uses.
ESC_SPRF="$ESC_T/sp-run.md"
printf '# Automate Run: esc\n## Status: paused\n## Source\n- folder f\n## Run Config\n- mode: safe | limit: 5\n## Queue\n- [ ] a.md\n## Current\n- item: a.md | status: escalated | pr: %s | branch: f/a\n- pause_reason: null\n## Progress\n- t0 run created\n' "$ESC_D_URL" > "$ESC_SPRF"
RUN_OUT="$(bash "$H" current-escalation "$ESC_SPRF" --cause check_pending --check "test (18.x)" --run-id 37259136900 --attempt 1 --sha 1e35336 2>&1)"; RUN_RC=$?
ESC_SP_FLD="$(awk '/^- escalation_cause: / { n = split($0, a, / \| /); for (i = 1; i <= n; i++) if (index(a[i], "check: ") == 1) print substr(a[i], 8) }' "$ESC_SPRF")"
if [ "$RUN_RC" -eq 0 ] && [ "$ESC_SP_FLD" = "test (18.x)" ] \
   && grep -qxF -- '- escalation_cause: check_pending | check: test (18.x) | run_id: 37259136900 | attempt: 1 | sha: 1e35336' "$ESC_SPRF"; then
  ok "V5 current-escalation records the spaced name and the ' | ' field split reads it back whole ($ESC_SP_FLD)"
else
  no "V5 spaced name lost in current-escalation (rc=$RUN_RC out=$RUN_OUT field='$ESC_SP_FLD')"
fi
# MUTATION CONTROL (class level): the SHARED reader reverted to word-splitting
# (fixtures/wait-for-checks-line/wsplit.sed, the mutant the reader's own and the drain suites
# also run) must cut the names again — every V5 leg turns red.
ESC_MUT="$(mktemp -d)"
for e in "$(dirname "$H")"/*; do [ "$(basename "$e")" = wait-for-checks-line.sh ] || ln -s "$e" "$ESC_MUT/$(basename "$e")"; done
sed -f "$HERE/fixtures/wait-for-checks-line/wsplit.sed" "$HERE/wait-for-checks-line.sh" > "$ESC_MUT/wait-for-checks-line.sh"
if [ -s "$ESC_MUT/wait-for-checks-line.sh" ] && ! cmp -s "$HERE/wait-for-checks-line.sh" "$ESC_MUT/wait-for-checks-line.sh" \
   && bash -n "$ESC_MUT/wait-for-checks-line.sh" 2>/dev/null; then
  ESC_D="$ESC_T/e11a"; esc_run "$ESC_MUT/automate-helpers.sh" "$ESC_D_URL" "1e35336"; esc_m1="$ESC_OUT"
  ESC_D="$ESC_T/e11b"; esc_run "$ESC_MUT/automate-helpers.sh" "$ESC_C_URL" "$ESC_C_SHA"; esc_m2="$ESC_OUT"
  if [ "$esc_m1" != "$ESC_SP_PEND" ] && [ "$esc_m2" != "$ESC_SP_UNREL" ]; then
    ok "ESC V5 mutation control: a word-splitting shared reader cuts both spaced names ($esc_m1 | $esc_m2)"
  else
    no "ESC V5 mutation control did NOT discriminate (m1='$esc_m1' m2='$esc_m2')"
  fi
else
  no "ESC V5 mutation control: could not build a valid reader mutant -- control inconclusive"
fi
# The reader is required: without it every snapshot is unreadable ⇒ check_red (fail CLOSED).
rm -f "$ESC_MUT/wait-for-checks-line.sh"
ESC_D="$ESC_T/e11a"; esc_run "$ESC_MUT/automate-helpers.sh" "$ESC_D_URL" "1e35336"
esc_expect "V5 shared reader missing ⇒ check_red, exit 0" "escalation_cause: check_red check=null run_id=null attempt=null sha=1e35336"
rm -rf "$ESC_MUT"

# AC13 (classifier half): no executed rerun / merge / push / approval in the family file.
ESC_CODE="$(grep -vE '^[[:space:]]*#' "$HERE/automate-helpers.d/escalation.sh")"
if [ -n "$ESC_CODE" ] && ! grep -qE 'run rerun|pr merge|git push|--approve|pr review' <<<"$ESC_CODE"; then
  ok "ESC AC13: escalation.sh executes no gh run rerun / gh pr merge / git push / approval (comments excluded)"
else
  no "ESC AC13: escalation.sh code mentions a rerun/merge/push/approval"
fi

# AC7: current-escalation — the ONLY writer of ## Current's escalation_cause line.
ESC_RF="$ESC_T/r.md"
esc_rf() { # esc_rf [with_pause=1]
  {
    printf '# Automate Run: esc\n## Status: paused\n## Source\n- folder f\n## Run Config\n- mode: safe | limit: 5\n## Queue\n- [ ] a.md\n## Current\n'
    printf '%s\n' '- item: a.md | status: escalated | pr: https://github.com/acme/widgets/pull/1 | branch: f/a'
    [ "${1:-1}" = 1 ] && printf '%s\n' '- pause_reason: null'
    printf '%s\n' '- owned_drain_started: t9 | owned_drain_result: ESCALATED | suppressed_default_dispatch: true'
    printf '## Progress\n- t0 run created\n'
  } > "$ESC_RF"
}
ESC_LINE="- escalation_cause: check_pending | check: claude-review | run_id: 37259136927 | attempt: 1 | sha: 1e35336"
esc_rf; cp "$ESC_RF" "$ESC_T/before"
run_h bash "$H" current-escalation "$ESC_RF" --cause check_pending --check claude-review --run-id 37259136927 --attempt 1 --sha 1e35336
if [ "$RUN_RC" -eq 0 ] && [ "$(grep -A1 -xF -- '- pause_reason: null' "$ESC_RF" | tail -1)" = "$ESC_LINE" ] \
   && [ "$(diff "$ESC_T/before" "$ESC_RF" | grep -c '^[<>]')" = 1 ] \
   && cmp -s "$ESC_T/before" <(grep -vxF -- "$ESC_LINE" "$ESC_RF"); then
  ok "ESC current-escalation: one line inserted right after pause_reason, every other line byte-unchanged"
else
  no "ESC current-escalation insert wrong (rc=$RUN_RC): $(diff "$ESC_T/before" "$ESC_RF" | tr '\n' '|')"
fi
cp "$ESC_RF" "$ESC_T/set1"
run_h bash "$H" current-escalation "$ESC_RF" --cause check_pending --check claude-review --run-id 37259136927 --attempt 1 --sha 1e35336
if [ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "current-escalation: unchanged" ] && cmp -s "$ESC_T/set1" "$ESC_RF"; then
  ok "ESC current-escalation: identical values ⇒ unchanged, byte-identical"
else
  no "ESC current-escalation not idempotent (rc=$RUN_RC out=$RUN_OUT)"
fi
run_h bash "$H" current-escalation "$ESC_RF" --cause findings
if [ "$RUN_RC" -eq 0 ] && [ "$(grep -c '^- escalation_cause:' "$ESC_RF")" = 1 ] \
   && grep -qxF -- '- escalation_cause: findings | check: null | run_id: null | attempt: null | sha: null' "$ESC_RF"; then
  ok "ESC current-escalation: replaces in place; omitted fields are null"
else
  no "ESC current-escalation replace wrong (rc=$RUN_RC): $(grep -n escalation_cause "$ESC_RF" | tr '\n' '|')"
fi
run_h bash "$H" current-escalation "$ESC_RF" --cause null
if [ "$RUN_RC" -eq 0 ] && cmp -s "$ESC_T/before" "$ESC_RF"; then
  ok "ESC current-escalation: --cause null removes the line (file back to byte-identical)"
else
  no "ESC current-escalation --cause null wrong (rc=$RUN_RC)"
fi
run_h bash "$H" current-escalation "$ESC_RF" --cause null
if [ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "current-escalation: unchanged" ]; then ok "ESC current-escalation: --cause null on an absent line ⇒ unchanged"; else no "ESC null-absent wrong (rc=$RUN_RC out=$RUN_OUT)"; fi
esc_rf 0; cp "$ESC_RF" "$ESC_T/nopause"
run_h bash "$H" current-escalation "$ESC_RF" --cause other
if [ "$RUN_RC" -eq 0 ] && [ "$(grep -B1 -xF '## Progress' "$ESC_RF" | head -1)" = "- escalation_cause: other | check: null | run_id: null | attempt: null | sha: null" ] \
   && [ "$(diff "$ESC_T/nopause" "$ESC_RF" | grep -c '^[<>]')" = 1 ]; then
  ok "ESC current-escalation: no pause_reason line ⇒ appended at the end of the ## Current block"
else
  no "ESC current-escalation append wrong (rc=$RUN_RC): $(diff "$ESC_T/nopause" "$ESC_RF" | tr '\n' '|')"
fi
esc_rf; cp "$ESC_RF" "$ESC_T/ref"
esc_bad=""
for args in "--cause bogus" "--check x" "--cause check_red --check a|b" \
            "--cause check_red --attempt two" "--cause check_red --run-id 12x" "--cause null --check ci" "--cause"; do
  # shellcheck disable=SC2086
  run_h bash "$H" current-escalation "$ESC_RF" $args
  { [ "$RUN_RC" -eq 1 ] && cmp -s "$ESC_T/ref" "$ESC_RF"; } || esc_bad="$esc_bad [$args rc=$RUN_RC]"
done
run_h bash "$H" current-escalation "$ESC_RF" --cause check_red --sha "$(printf 'a\nb')"
{ [ "$RUN_RC" -eq 1 ] && cmp -s "$ESC_T/ref" "$ESC_RF"; } || esc_bad="$esc_bad [newline sha rc=$RUN_RC]"
if [ -z "$esc_bad" ]; then ok "ESC current-escalation: every refusal exits 1 with the file byte-unchanged"; else no "ESC current-escalation refusals wrong:$esc_bad"; fi
# af36-remainder/01: validation_unrun — validation-gate's unrun verdict at a READY park, the step as --check.
esc_rf; cp "$ESC_T/ref" "$ESC_T/vu-before"
run_h bash "$H" current-escalation "$ESC_RF" --cause validation_unrun --check "V2 Running system" --sha 1e35336
if [ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "current-escalation: written" ] \
   && [ "$(grep -A1 -xF -- '- pause_reason: null' "$ESC_RF" | tail -1)" = "- escalation_cause: validation_unrun | check: V2 Running system | run_id: null | attempt: null | sha: 1e35336" ] \
   && [ "$(diff "$ESC_T/vu-before" "$ESC_RF" | grep -c '^[<>]')" = 1 ]; then
  ok "ESC current-escalation: --cause validation_unrun --check \"V<n> <title>\" accepted (one line, after pause_reason)"
else
  no "ESC current-escalation validation_unrun refused or misplaced (rc=$RUN_RC out=$RUN_OUT): $(grep -n escalation_cause "$ESC_RF" | tr '\n' '|')"
fi
# Review iteration 1 (stale per-item state): the escalation line is per-item park state.
esc_rf; run_h bash "$H" current-escalation "$ESC_RF" --cause check_pending --check claude-review --run-id 37259136927 --attempt 1 --sha 1e35336
cp "$ESC_RF" "$ESC_T/esc-on"
run_h bash "$H" current-set "$ESC_RF" --item a.md --status escalated --pause-reason escalated
run_h bash "$H" current-set "$ESC_RF" --pause-reason awaiting_go
if grep -qxF -- "$ESC_LINE" "$ESC_RF"; then ok "ESC current-set: the same item staying escalated (and the run-level form) keeps the escalation line"; else no "ESC current-set dropped a live escalated park's line"; fi
cp "$ESC_T/esc-on" "$ESC_RF"
run_h bash "$H" current-set "$ESC_RF" --item a.md --status done --pause-reason awaiting_go
cp "$ESC_RF" "$ESC_T/esc-done"
if [ "$RUN_RC" -eq 0 ] && ! grep -q '^- escalation_cause:' "$ESC_RF" && grep -qF -- '- item: a.md | status: done | pr: https://github.com/acme/widgets/pull/1 | branch: f/a' "$ESC_RF" \
   && [ "$(diff "$ESC_T/esc-on" "$ESC_RF" | grep -c '^[<>]')" = 5 ]; then
  ok "ESC current-set: status done (closeout) removes the escalation line; item keeps pr/branch"
else
  no "ESC current-set done did not clear (rc=$RUN_RC): $(diff "$ESC_T/esc-on" "$ESC_RF" | tr '\n' '|')"
fi
run_h bash "$H" current-set "$ESC_RF" --item a.md --status done --pause-reason awaiting_go
if [ "$RUN_OUT" = "current-set: unchanged" ] && cmp -s "$ESC_T/esc-done" "$ESC_RF"; then ok "ESC current-set: a second identical done write is unchanged, byte-identical"; else no "ESC current-set done not idempotent: $RUN_OUT"; fi
cp "$ESC_T/esc-on" "$ESC_RF"
run_h bash "$H" current-set "$ESC_RF" --item b.md --status escalated --pr https://github.com/acme/widgets/pull/2
if [ "$RUN_RC" -eq 0 ] && ! grep -q '^- escalation_cause:' "$ESC_RF"; then ok "ESC current-set: a changed item (PICK of the next item) removes the previous item's escalation line"; else no "ESC current-set changed item kept a stale line"; fi
rm -rf "$ESC_T"
