#!/usr/bin/env bash
# test-run-ground-truth.sh — self-tests for the System Twin GROUND-TRUTH runner (run-ground-truth.sh).
# Mirrors test-run-eval.sh: isolated, deterministic, no network. Runs from a temp CWD so it can
# never pollute the real .supervisor/ (the runner's ground-truth.json fallback resolves against the
# git root of the CWD). Exit 0 = all pass, 1 = any failure. Prints "RESULT: N passed, M failed".
#
# Covers the five core AC cases plus the corpus dogfood and edge cases (a–m, incl. e2, l-env, m1–m5):
#   (a) passing check (--check 'cmd: true')          => status "pass", 1/1, exit 0.
#   (b) failing check (--check 'cmd: false')         => status "advisory_failures", per_check fail, exit 0.
#   (c) no source (temp CWD, no ground-truth.json)   => status "skipped", 0/0, exit 0.
#   (d) missing-jq simulation (GROUND_TRUTH_FORCE_NO_JQ=1) => status "unverified", exit 0.
#   (e) qa-executor: (alias of verify:), stub SELVEDGE_BIN writing a PASS verdict.json
#                                                    => per_check kind "verify", status pass, exit 0.
#   (e2) qa-executor: + a passing cmd, same stub     => status "pass", total 2, passed 2.
#   (f) corpus-task: version-consistent              => executes the real check, hard pass/fail, 1/1 total
#                                                       (run from the repo root — the project it verifies).
#   (g) missing corpus-task                          => per_check fail, reason corpus_task_not_found, exit 0.
#   (h) corpus-task with path traversal              => per_check fail, reason corpus_task_invalid_id, exit 0.
#   (i) cmd: target with a leading dash              => target preserved verbatim (not bullet-stripped).
#   (j) --brief heading match is exact               => sibling "## Executable Acceptance Notes" ignored.
#   (k) empty cmd: target                            => fail (reason empty_cmd_target), not a false pass.
#   (l) --no-cmd / GROUND_TRUTH_NO_CMD safety valve   => cmd skipped (unverified/cmd_disabled, no side effect), corpus-task still runs.
#   (m) project root — the 2026-09-13 marketplace-install incident (runner + corpus copied OUTSIDE any
#       git repo, as under the plugin manager's install cache): (m1) a corpus-task run from the repo-root CWD
#       PASSES and `commit` is the PROJECT's HEAD; (m2) `--project <repo>` from a non-git CWD passes and
#       a repo-root-relative `cmd:` runs from the project root; (m3) the in-repo runner from a non-git
#       CWD with no --project FAILS the maintainer-side task (the check verifies the CALLER's project,
#       never the runner's home — the mutation control for the check.sh precedence); (m4) `--project`
#       naming a non-directory => unverified 0/0, exit 0; (m5) check.sh precedence unit: --root beats
#       EVAL_PROJECT_ROOT beats the task-dir git root.
#   (n) content-keyed Executable Acceptance stamp gate (red-team-hardening item 05 — see
#       exec-acceptance-hash.sh / exec-acceptance-lib.sh): (n1) a VALID stamp -> cmd: executes
#       exactly as today (happy path, AC2); (n2) an ABSENT stamp -> unverified/cmd_unapproved, no
#       execution (sentinel never created, AC3); (n3) a STALE stamp (bullet edited after stamping)
#       -> same cmd_unapproved, no execution (AC4); (n4) --no-cmd wins over a VALID stamp ->
#       cmd_disabled, not cmd_unapproved (AC5); (n5) --check-only (no --brief at all) is completely
#       unaffected by the gate (AC6a); (n6) a MIXED --brief (unstamped) + --check invocation gates
#       only the --brief-sourced bullet, the --check-sourced one still executes in the SAME run
#       (AC6b); (n7) BLOCKING mutation control — splice out the MUTATION_CONTROL-bracketed
#       hash-comparison block in run-ground-truth.sh, replace it with an unconditional
#       BRIEF_HASH_VALID=1, confirm the (n3) stale-stamp case then WRONGLY executes against the
#       mutant, proving the real gate is load-bearing (AC7).
#   (v) the `verify:` kind and the unknown-prefix refusal — every verify: leg runs a STUB
#       SELVEDGE_BIN (a bash script under $TMP that writes criteria.json, one .selvedge/runs/<id>/
#       folder and a fixed verdict.json, and logs every call), never a real browser or model; the
#       plugin-absent leg scrubs PATH (a stale `selvedge` may sit on the caller's PATH): unknown
#       prefix never run (A1), qa-executor: alias (B1), one run folder for two lines (B2), the
#       verdict mapping (B3, B8), plugin absent (B4), refusals and unreadable verdicts (B5),
#       --no-cmd still runs verify: (B6), `plan --base` and `run` on the printed folder only (B7),
#       no stamp needed (C2), the `Verify:` counts line + verify_counts (C4), and a verify: FAIL
#       stays an advisory finding with gate-eval still at seven conditions (C5).

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RUN="$HERE/run-ground-truth.sh"
HASH="$HERE/exec-acceptance-hash.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "test-run-ground-truth: jq not available — cannot exercise the runner; skipping (treated as pass)."
  echo; echo "RESULT: 0 passed, 0 failed"; exit 0
fi

# Pull the single GROUND_TRUTH_JSON object out of the runner output.
gt_json() { printf '%s\n' "$1" | sed -n 's/^GROUND_TRUTH_JSON: //p' | head -n1; }

# Isolated temp CWD so the ground-truth.json fallback can never see the real .supervisor/.
TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
# Never resolve a real Selvedge from the caller's environment: every verify: leg sets its own
# SELVEDGE_BIN (the stub below) or scrubs PATH; the base ref is derived unless a leg sets it.
unset SELVEDGE_BIN GROUND_TRUTH_VERIFY_BASE

# STUB SELVEDGE_BIN — stands in for the Selvedge CLI's public commands. Every call appends its argv
# (one line) to $STUB_LOG. Knobs: STUB_CRITERIA_RC / STUB_PLAN_RC (non-zero => that command refuses),
# STUB_PLAN_PRINT (print this instead of the run folder), STUB_VERDICTS (comma list of
# VERDICT[:reason], one per criterion in order; default PASS), STUB_SCHEMA (verdict.json
# schema_version, default 1), STUB_NO_VERDICT=1 (run writes no verdict.json), STUB_RUN_RC,
# STUB_DEDUPE=1 (fold identical criteria into one id, as Selvedge's from-text does).
STUB="$TMP/stub-bin/selvedge"
mkdir -p "$TMP/stub-bin"
cat > "$STUB" <<'STUB_EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${STUB_LOG:-/dev/null}"
case "${1:-}" in
  --version) echo "selvedge 0.0.0-stub" ;;
  criteria)
    [ "${STUB_CRITERIA_RC:-0}" = 0 ] || { echo "selvedge criteria: criteria_not_found: stub" >&2; exit "$STUB_CRITERIA_RC"; }
    n=0; items=""; seen=""
    while IFS= read -r l || [ -n "$l" ]; do
      l="${l#- }"; l="$(printf '%s' "$l" | tr -s ' ')"; [ -n "$l" ] || continue
      if [ "${STUB_DEDUPE:-0}" = 1 ]; then
        case "$seen" in *"|$l|"*) continue ;; esac
        seen="${seen:-|}$l|"
      fi
      n=$((n+1))
      items="$items${items:+,}$(jq -cn --arg id "$(printf 'c-%012x' "$n")" --arg t "$l" '{id:$id,text:$t}')"
    done
    printf '{"schema_version":1,"source":null,"criteria":[%s]}\n' "$items"
    ;;
  plan)
    if [ "${STUB_PLAN_RC:-0}" != 0 ]; then echo "BLOCKED base_config_unreadable"; echo "selvedge plan: stub refusal" >&2; exit "$STUB_PLAN_RC"; fi
    d="$PWD/.selvedge/runs/20261128T000000Z-$(printf '%06x' "$$")"
    mkdir -p "$d" && cp "$2" "$d/criteria.json"
    echo "selvedge plan: run folder $d (stub)" >&2
    if [ -n "${STUB_PLAN_PRINT:-}" ]; then echo "$STUB_PLAN_PRINT"; else echo "$d"; fi
    ;;
  run)
    for d in "$@"; do :; done
    [ "${STUB_NO_VERDICT:-0}" = 1 ] && exit 2
    jq -n --slurpfile c "$d/criteria.json" --arg vs "${STUB_VERDICTS:-PASS}" --argjson sv "${STUB_SCHEMA:-1}" '
      ($vs | split(",")) as $v | $c[0].criteria as $cs
      | {schema_version: $sv, target: "web",
         criteria: ([range(0; $cs | length) as $i
           | {key: $cs[$i].id,
              value: (($v[$i] // "PASS") | split(":") | {verdict: .[0], reason: (.[1] // null)})}]
           | from_entries)}' > "$d/verdict.json"
    exit "${STUB_RUN_RC:-0}"
    ;;
esac
exit 0
STUB_EOF
chmod +x "$STUB"
# A non-git temp dir (git rev-parse falls back to pwd; no .supervisor/twin/ground-truth.json here).
CWD="$TMP/work"
mkdir -p "$CWD"
# The repo this suite lives in — the PROJECT the maintainer-side corpus tasks verify. Cases that run a
# real corpus task use it as the CWD (the runner derives the project root from the caller's CWD); the
# runner performs no writes and every such case passes an explicit --check, so the ground-truth.json
# fallback can never fire there.
REPO_ROOT="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null || true)"

echo "== (a) passing check (cmd: true) => status pass, 1/1 =="
oA="$( cd "$CWD" && bash "$RUN" --check 'cmd: true' 2>/dev/null )"; rcA=$?
jA="$(gt_json "$oA")"
if [ "$rcA" -eq 0 ] && printf '%s' "$jA" | jq -e '
    .status=="pass" and .ran==true and .checks_total==1 and .checks_passed==1
    and .pass_rate=="1/1" and (.per_check|length)==1 and .per_check[0].status=="pass"
  ' >/dev/null 2>&1; then
  ok "passing check: status pass, total/passed 1, pass_rate 1/1, exit 0"
else
  no "(a) wrong (rc=$rcA): $jA"
fi

echo "== (b) failing check (cmd: false) => advisory_failures, exit 0 =="
oB="$( cd "$CWD" && bash "$RUN" --check 'cmd: false' 2>/dev/null )"; rcB=$?
jB="$(gt_json "$oB")"
if [ "$rcB" -eq 0 ] && printf '%s' "$jB" | jq -e '
    .status=="advisory_failures" and .checks_total==1 and .checks_passed==0
    and .pass_rate=="0/1" and .per_check[0].status=="fail"
  ' >/dev/null 2>&1; then
  ok "failing check: status advisory_failures, per_check fail, exit 0"
else
  no "(b) wrong (rc=$rcB): $jB"
fi

echo "== (c) no source => skipped, 0/0, exit 0 =="
oC="$( cd "$CWD" && bash "$RUN" 2>/dev/null )"; rcC=$?
jC="$(gt_json "$oC")"
if [ "$rcC" -eq 0 ] && printf '%s' "$jC" | jq -e '
    .status=="skipped" and .ran==false and .checks_total==0
    and .pass_rate=="0/0" and (.per_check|length)==0
  ' >/dev/null 2>&1; then
  ok "no source: status skipped, 0/0, per_check [], exit 0"
else
  no "(c) wrong (rc=$rcC): $jC"
fi

echo "== (d) missing-jq simulation (GROUND_TRUTH_FORCE_NO_JQ=1) => unverified, exit 0 =="
oD="$( cd "$CWD" && GROUND_TRUTH_FORCE_NO_JQ=1 bash "$RUN" --check 'cmd: true' 2>/dev/null )"; rcD=$?
jD="$(gt_json "$oD")"
if [ "$rcD" -eq 0 ] && printf '%s' "$jD" | jq -e '
    .status=="unverified" and .ran==false and .checks_total==0 and .pass_rate=="0/0"
  ' >/dev/null 2>&1; then
  ok "no-jq path: status unverified, ran false, 0/0, exit 0"
else
  no "(d) wrong (rc=$rcD): $jD"
fi

# seed_base <dir> [branch]: give a stub-Selvedge project a base branch the ONE resolver
# (resolve-base-branch.sh) can read — `.supervisor/config.json .base_branch` (default main) — so
# the verify: driver gets `--base origin/<branch>` without a remote. A project without it has no
# base, which the driver refuses (verify_refused, see v-B7d).
seed_base() { mkdir -p "$1/.supervisor" && printf '{"base_branch":"%s"}\n' "${2:-main}" > "$1/.supervisor/config.json"; }

echo "== (e) qa-executor: (alias of verify:) + stub SELVEDGE_BIN PASS => per_check kind verify, pass =="
mkdir -p "$TMP/e-proj"; seed_base "$TMP/e-proj"
oE="$( cd "$TMP/e-proj" && SELVEDGE_BIN="$STUB" STUB_LOG="$TMP/e.log" STUB_VERDICTS=PASS \
        bash "$RUN" --check 'qa-executor: login-smoke' 2>/dev/null )"; rcE=$?
jE="$(gt_json "$oE")"
if [ "$rcE" -eq 0 ] && printf '%s' "$jE" | jq -e '
    .checks_total==1 and .checks_passed==1 and .ran==true and .status=="pass"
    and .per_check[0].kind=="verify" and .per_check[0].target=="login-smoke"
    and .per_check[0].status=="pass"
  ' >/dev/null 2>&1; then
  ok "qa-executor: is the verify kind: per_check kind verify, status pass, exit 0 (the deferral is gone)"
else
  no "(e) wrong (rc=$rcE): $jE"
fi

echo "== (e2) qa-executor: + a passing cmd, stub PASS => status pass, total 2, passed 2 =="
mkdir -p "$TMP/e2-proj"; seed_base "$TMP/e2-proj"
oE2="$( cd "$TMP/e2-proj" && SELVEDGE_BIN="$STUB" STUB_LOG="$TMP/e2.log" STUB_VERDICTS=PASS \
         bash "$RUN" --check 'cmd: true' --check 'qa-executor: x' 2>/dev/null )"
jE2="$(gt_json "$oE2")"
if printf '%s' "$jE2" | jq -e '
    .status=="pass" and .checks_total==2 and .checks_passed==2
    and ([.per_check[].status] | sort) == (["pass","pass"])
  ' >/dev/null 2>&1; then
  ok "qa-executor: (verify) + passing cmd => status pass, total 2, passed 2"
else
  no "(e2) wrong: $jE2"
fi

echo "== (f) corpus-task: version-consistent => executes real check, hard pass/fail, 1/1 total =="
oF="$( cd "$REPO_ROOT" && bash "$RUN" --check 'corpus-task: version-consistent' 2>/dev/null )"; rcF=$?
jF="$(gt_json "$oF")"
if [ "$rcF" -eq 0 ] && printf '%s' "$jF" | jq -e '
    .checks_total==1 and .per_check[0].kind=="corpus-task"
    and .per_check[0].target=="version-consistent"
    and (.per_check[0].status | IN("pass","fail"))
    and (.status | IN("pass","advisory_failures"))
  ' >/dev/null 2>&1; then
  ok "corpus-task version-consistent executed: total 1, hard $(printf '%s' "$jF" | jq -r '.per_check[0].status'), exit 0"
else
  no "(f) wrong (rc=$rcF): $jF"
fi

echo "== (g) missing corpus-task => fail with corpus_task_not_found =="
oG="$( cd "$CWD" && bash "$RUN" --check 'corpus-task: does-not-exist-xyz' 2>/dev/null )"; rcG=$?
jG="$(gt_json "$oG")"
if [ "$rcG" -eq 0 ] && printf '%s' "$jG" | jq -e '
    .status=="advisory_failures" and .per_check[0].status=="fail"
    and .per_check[0].reason=="corpus_task_not_found"
  ' >/dev/null 2>&1; then
  ok "missing corpus-task => per_check fail, reason corpus_task_not_found, exit 0"
else
  no "(g) wrong (rc=$rcG): $jG"
fi

echo "== (h) corpus-task with path traversal => rejected as invalid id, exit 0 =="
oH="$( cd "$CWD" && bash "$RUN" --check 'corpus-task: ../version-consistent' 2>/dev/null )"; rcH=$?
jH="$(gt_json "$oH")"
if [ "$rcH" -eq 0 ] && printf '%s' "$jH" | jq -e '
    .status=="advisory_failures" and .per_check[0].status=="fail"
    and .per_check[0].reason=="corpus_task_invalid_id"
  ' >/dev/null 2>&1; then
  ok "path-traversal corpus-task => per_check fail, reason corpus_task_invalid_id, exit 0"
else
  no "(h) wrong (rc=$rcH): $jH"
fi

echo "== (i) cmd: target keeps a leading dash (not eaten by bullet-stripping) =="
# Regression for the strip_bullet-on-target bug: `cmd: -x foo` previously lost its leading dash.
# The fix is verified by the target being recorded VERBATIM (incl. the leading dash). We assert on the
# preserved target + exit 0, not on pass/fail — a leading-dash token is not a runnable command, so the
# tally is irrelevant; target preservation is the contract under test.
oI="$( cd "$CWD" && bash "$RUN" --check 'cmd: -x foo' 2>/dev/null )"; rcI=$?
jI="$(gt_json "$oI")"
if [ "$rcI" -eq 0 ] && printf '%s' "$jI" | jq -e '
    .per_check[0].kind=="cmd" and .per_check[0].target=="-x foo"
  ' >/dev/null 2>&1; then
  ok "cmd target preserves leading dash (target == '-x foo'), exit 0"
else
  no "(i) wrong (rc=$rcI): $jI"
fi

echo "== (j) --brief heading match is exact ('## Executable Acceptance Notes' must NOT open section) =="
BRF="$TMP/brief-notes.md"
printf '## Executable Acceptance Notes\n- cmd: false\n\n## Executable Acceptance\n- cmd: true\n' > "$BRF"
# Stamp the brief (content-keyed gate, AC2) so the real section's cmd: bullet still executes —
# this case is about heading-match exactness, not the stamp gate itself (covered separately below).
jSTAMP="$(bash "$HASH" "$BRF")"
printf '\n## Configuration\n- **Executable Acceptance Approved:** %s\n' "$jSTAMP" >> "$BRF"
oJ="$( cd "$CWD" && bash "$RUN" --brief "$BRF" 2>/dev/null )"; rcJ=$?
jJ="$(gt_json "$oJ")"
# Only the real heading's `cmd: true` (pass) is collected; the "Notes" heading's `cmd: false` is ignored.
if [ "$rcJ" -eq 0 ] && printf '%s' "$jJ" | jq -e '
    .status=="pass" and .checks_total==1 and .per_check[0].target=="true"
  ' >/dev/null 2>&1; then
  ok "exact heading match: sibling '## Executable Acceptance Notes' ignored, only real section collected"
else
  no "(j) wrong (rc=$rcJ): $jJ"
fi

echo "== (l) --no-cmd safety valve: cmd skipped (unverified/cmd_disabled), corpus-task still runs =="
oL2="$( cd "$REPO_ROOT" && bash "$RUN" --no-cmd --check 'cmd: true' --check 'corpus-task: version-consistent' 2>/dev/null )"; rcL2=$?
jL2="$(gt_json "$oL2")"
# cmd: not executed (unverified/cmd_disabled); corpus-task runs (pass) => overall pass, total 2, passed 1.
if [ "$rcL2" -eq 0 ] && printf '%s' "$jL2" | jq -e '
    .checks_total==2 and .checks_passed==1 and .status=="pass"
    and ((.per_check[] | select(.kind=="cmd")) | .status=="unverified" and .reason=="cmd_disabled")
    and ((.per_check[] | select(.kind=="corpus-task")) | .status=="pass")
  ' >/dev/null 2>&1; then
  ok "--no-cmd: cmd skipped (unverified/cmd_disabled), corpus-task ran (pass), status pass, exit 0"
else
  no "(l) wrong (rc=$rcL2): $jL2"
fi
# also assert the env-var form (GROUND_TRUTH_NO_CMD=1) skips cmd and the cmd never executes a side effect
SENTINEL="$TMP/no_cmd_sentinel.$$"
rm -f "$SENTINEL"
oL3="$( cd "$CWD" && GROUND_TRUTH_NO_CMD=1 bash "$RUN" --check "cmd: touch '$SENTINEL'" 2>/dev/null )"
if [ ! -e "$SENTINEL" ] && printf '%s' "$(gt_json "$oL3")" | jq -e '.per_check[0].reason=="cmd_disabled"' >/dev/null 2>&1; then
  ok "GROUND_TRUTH_NO_CMD=1 env form: cmd not executed (no side effect), reason cmd_disabled"
else
  no "(l-env) cmd ran or wrong reason (sentinel exists=$( [ -e "$SENTINEL" ] && echo yes || echo no ))"
fi

echo "== (k) empty cmd: target => fail (not a false pass), exit 0 =="
# A bare `cmd:` (empty command) must NOT be a false PASS (bash -c "" exits 0). Surfaces as fail.
oK="$( cd "$CWD" && bash "$RUN" --check 'cmd:' 2>/dev/null )"; rcK=$?
jK="$(gt_json "$oK")"
if [ "$rcK" -eq 0 ] && printf '%s' "$jK" | jq -e '
    .status=="advisory_failures" and .checks_total==1 and .checks_passed==0
    and .per_check[0].kind=="cmd" and .per_check[0].status=="fail"
    and .per_check[0].reason=="empty_cmd_target"
  ' >/dev/null 2>&1; then
  ok "empty cmd: target => fail (reason empty_cmd_target), not a false pass, exit 0"
else
  no "(k) wrong (rc=$rcK): $jK"
fi

echo "== (m) project root: runner + corpus copied OUTSIDE any git repo (marketplace-install shape) =="
# Regression for the 2026-09-13 incident: on a marketplace install $SCRIPT_DIR is
# the plugin manager's install cache (<cache>/<marketplace>/loomwright/<version>/scripts) — not in any git repo — and every
# maintainer-side check.sh resolved the repo from ITS OWN dir, so ground_truth reported
# advisory_failures while the checkout's copy of the same runner passed. The runner must hand the
# CALLER's project root to each check (EVAL_PROJECT_ROOT), and the checks must use it.
FAKE="$TMP/plugin-cache/loomwright/9.9.9/scripts"
mkdir -p "$FAKE"
cp "$RUN" "$FAKE/run-ground-truth.sh"
cp "$HERE/exec-acceptance-lib.sh" "$FAKE/exec-acceptance-lib.sh"
cp "$HERE/ground-truth-verify.sh" "$FAKE/ground-truth-verify.sh"
cp -R "$HERE/eval-corpus" "$FAKE/eval-corpus"
FAKE_RUN="$FAKE/run-ground-truth.sh"
if [ -z "$REPO_ROOT" ]; then
  no "(m) precondition: this suite is not inside a git repo — cannot name the project to verify"
elif git -C "$FAKE" rev-parse --show-toplevel >/dev/null 2>&1; then
  no "(m) precondition: mktemp dir '$TMP' is INSIDE a git repo — cannot simulate a git-less plugin cache"
else
  # (m1) from the repo-root CWD, the copied runner must pass the maintainer-side task, and `commit`
  # must be the PROJECT's HEAD (not "unknown" — the copy has no git of its own).
  headShort="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  oM1="$( cd "$REPO_ROOT" && bash "$FAKE_RUN" --check 'corpus-task: version-consistent' 2>/dev/null )"; rcM1=$?
  jM1="$(gt_json "$oM1")"
  if [ "$rcM1" -eq 0 ] && printf '%s' "$jM1" | jq -e --arg c "$headShort" '
      .status=="pass" and .checks_total==1 and .checks_passed==1
      and .per_check[0].kind=="corpus-task" and .per_check[0].status=="pass"
      and .commit==$c
    ' >/dev/null 2>&1; then
    ok "(m1) git-less runner copy + repo-root CWD: corpus-task passes, commit == project HEAD ($headShort)"
  else
    no "(m1) git-less runner copy from repo-root CWD did not pass (rc=$rcM1): $jM1"
  fi

  # (m2) --project <repo> from a NON-git CWD: corpus-task passes AND a repo-root-relative cmd: runs
  # from the project root (not from the caller's CWD, where that file does not exist).
  oM2="$( cd "$CWD" && bash "$FAKE_RUN" --project "$REPO_ROOT" \
          --check 'corpus-task: version-consistent' \
          --check 'cmd: test -f scripts/validate-version.sh' 2>/dev/null )"; rcM2=$?
  jM2="$(gt_json "$oM2")"
  if [ "$rcM2" -eq 0 ] && printf '%s' "$jM2" | jq -e '
      .status=="pass" and .checks_total==2 and .checks_passed==2
    ' >/dev/null 2>&1; then
    ok "(m2) --project <repo> from a non-git CWD: corpus-task passes, cmd: runs from the project root"
  else
    no "(m2) --project path wrong (rc=$rcM2): $jM2"
  fi

  # (m3) MUTATION CONTROL: the IN-REPO runner from a non-git CWD with no --project must FAIL the
  # maintainer-side task — the project root is the caller's CWD (no git, no gate scripts), and the
  # check must NOT quietly fall back to the repo enclosing its own file. Before the fix this passed
  # (the check found the runner's home repo), which is exactly the wrong-project report the incident
  # was made of, seen from the other side.
  oM3="$( cd "$CWD" && bash "$RUN" --check 'corpus-task: version-consistent' 2>/dev/null )"; rcM3=$?
  jM3="$(gt_json "$oM3")"
  if [ "$rcM3" -eq 0 ] && printf '%s' "$jM3" | jq -e '
      .status=="advisory_failures" and .checks_total==1 and .per_check[0].status=="fail"
    ' >/dev/null 2>&1; then
    ok "(m3) in-repo runner, non-git CWD, no --project: maintainer-side task fails honestly (verifies the caller's project, not the runner's home)"
  else
    no "(m3) check fell back to the runner's own repo (rc=$rcM3): $jM3"
  fi

  # (m4) --project naming a non-directory: fail-safe unverified (0/0, ran false), exit 0 — never a
  # run against some other directory, never a false pass.
  oM4="$( cd "$CWD" && bash "$RUN" --project "$TMP/does-not-exist" --check 'cmd: true' 2>/dev/null )"; rcM4=$?
  jM4="$(gt_json "$oM4")"
  if [ "$rcM4" -eq 0 ] && printf '%s' "$jM4" | jq -e '
      .status=="unverified" and .ran==false and .checks_total==0 and .pass_rate=="0/0" and (.per_check|length)==0
    ' >/dev/null 2>&1; then
    ok "(m4) --project <non-directory>: status unverified, ran false, 0/0, exit 0"
  else
    no "(m4) invalid --project wrong (rc=$rcM4): $jM4"
  fi

  # (m5) check.sh precedence unit (direct invocation, no runner): from the git-less COPY of the
  # task dir, (i) no env + no flag fails with the "EVAL_PROJECT_ROOT unset" message; (ii) EVAL_PROJECT_ROOT
  # pointing at the repo passes; (iii) for a --root-capable task, --root beats a bogus EVAL_PROJECT_ROOT.
  vc_dir="$FAKE/eval-corpus/version-consistent"
  pe_dir="$FAKE/eval-corpus/parity-emit-block"
  m5_ok=1
  ( cd "$vc_dir" && env -u EVAL_PROJECT_ROOT bash check.sh >/dev/null 2>"$TMP/m5i.err" ) && m5_ok=0
  grep -q "EVAL_PROJECT_ROOT unset" "$TMP/m5i.err" 2>/dev/null || m5_ok=0
  ( cd "$vc_dir" && EVAL_PROJECT_ROOT="$REPO_ROOT" bash check.sh >/dev/null 2>&1 ) || m5_ok=0
  ( cd "$pe_dir" && EVAL_PROJECT_ROOT="$TMP/does-not-exist" bash check.sh --root "$REPO_ROOT" >/dev/null 2>&1 ) || m5_ok=0
  if [ "$m5_ok" -eq 1 ]; then
    ok "(m5) check.sh precedence: --root > EVAL_PROJECT_ROOT > task-dir git root (git-less copy fails loudly with neither)"
  else
    no "(m5) check.sh precedence wrong (see $TMP/m5i.err: $(head -c 200 "$TMP/m5i.err" 2>/dev/null))"
  fi
fi

echo
echo "== (n) content-keyed Executable Acceptance stamp gate (red-team-hardening item 05) =="

# (n1) VALID stamp -> cmd: executes exactly as today (happy path, AC2).
N_BRIEF="$TMP/n-brief.md"
printf '## Executable Acceptance\n- cmd: true\n' > "$N_BRIEF"
N_HASH="$(bash "$HASH" "$N_BRIEF")"
printf '\n## Configuration\n- **Executable Acceptance Approved:** %s\n' "$N_HASH" >> "$N_BRIEF"
oN1="$( cd "$CWD" && bash "$RUN" --brief "$N_BRIEF" 2>/dev/null )"; rcN1=$?
jN1="$(gt_json "$oN1")"
if [ "$rcN1" -eq 0 ] && printf '%s' "$jN1" | jq -e '
    .status=="pass" and .checks_total==1 and .checks_passed==1
    and .per_check[0].status=="pass"
  ' >/dev/null 2>&1; then
  ok "(n1) VALID stamp: cmd: executes exactly as today (status pass)"
else
  no "(n1) wrong (rc=$rcN1): $jN1"
fi

# (n2) ABSENT stamp -> unverified/cmd_unapproved, no execution (sentinel never created, AC3).
N2_BRIEF="$TMP/n2-brief.md"
N2_SENTINEL="$TMP/n2-sentinel.$$"
rm -f "$N2_SENTINEL"
printf "## Executable Acceptance\n- cmd: touch '%s'\n" "$N2_SENTINEL" > "$N2_BRIEF"
oN2="$( cd "$CWD" && bash "$RUN" --brief "$N2_BRIEF" 2>/dev/null )"; rcN2=$?
jN2="$(gt_json "$oN2")"
if [ "$rcN2" -eq 0 ] && [ ! -e "$N2_SENTINEL" ] && printf '%s' "$jN2" | jq -e '
    .checks_total==1 and .checks_passed==0
    and .per_check[0].status=="unverified" and .per_check[0].reason=="cmd_unapproved"
  ' >/dev/null 2>&1; then
  ok "(n2) ABSENT stamp: unverified/cmd_unapproved, no execution (sentinel never created)"
else
  no "(n2) wrong (rc=$rcN2, sentinel exists=$( [ -e "$N2_SENTINEL" ] && echo yes || echo no )): $jN2"
fi

# (n3) STALE stamp (bullet edited after the stamp line was written) -> same cmd_unapproved, no
# execution (AC4). Stamp is computed for `cmd: true` but the bullet now reads `cmd: false` — the
# EXACT scenario the (n7) mutation control below re-uses.
N3_BRIEF="$TMP/n3-brief.md"
printf '## Executable Acceptance\n- cmd: true\n' > "$N3_BRIEF"
N3_HASH="$(bash "$HASH" "$N3_BRIEF")"
printf '\n## Configuration\n- **Executable Acceptance Approved:** %s\n' "$N3_HASH" >> "$N3_BRIEF"
# Now edit the bullet (stamp becomes stale) — sed-free, portable rewrite via printf.
printf '## Executable Acceptance\n- cmd: false\n\n## Configuration\n- **Executable Acceptance Approved:** %s\n' "$N3_HASH" > "$N3_BRIEF"
oN3="$( cd "$CWD" && bash "$RUN" --brief "$N3_BRIEF" 2>/dev/null )"; rcN3=$?
jN3="$(gt_json "$oN3")"
if [ "$rcN3" -eq 0 ] && printf '%s' "$jN3" | jq -e '
    .checks_total==1 and .checks_passed==0
    and .per_check[0].status=="unverified" and .per_check[0].reason=="cmd_unapproved"
  ' >/dev/null 2>&1; then
  ok "(n3) STALE stamp (edited-after-stamp): unverified/cmd_unapproved, no execution"
else
  no "(n3) wrong (rc=$rcN3): $jN3"
fi

# (n4) --no-cmd wins over a VALID stamp -> cmd_disabled, not cmd_unapproved (AC5).
oN4="$( cd "$CWD" && bash "$RUN" --no-cmd --brief "$N_BRIEF" 2>/dev/null )"; rcN4=$?
jN4="$(gt_json "$oN4")"
if [ "$rcN4" -eq 0 ] && printf '%s' "$jN4" | jq -e '
    .per_check[0].status=="unverified" and .per_check[0].reason=="cmd_disabled"
  ' >/dev/null 2>&1; then
  ok "(n4) --no-cmd wins over a VALID stamp (reason cmd_disabled, never cmd_unapproved)"
else
  no "(n4) wrong (rc=$rcN4): $jN4"
fi

# (n5) --check-only (no --brief at all) is completely unaffected by the gate (AC6a).
oN5="$( cd "$CWD" && bash "$RUN" --check 'cmd: true' 2>/dev/null )"; rcN5=$?
jN5="$(gt_json "$oN5")"
if [ "$rcN5" -eq 0 ] && printf '%s' "$jN5" | jq -e '
    .status=="pass" and .per_check[0].status=="pass"
  ' >/dev/null 2>&1; then
  ok "(n5) --check-only (no --brief): completely unaffected by the stamp gate"
else
  no "(n5) wrong (rc=$rcN5): $jN5"
fi

# (n6) MIXED invocation: an UNSTAMPED --brief cmd: bullet is gated, a --check-sourced cmd: bullet
# in the SAME run still executes normally (AC6b) — the per-line source-provenance requirement.
N6_BRIEF="$TMP/n6-brief.md"
printf '## Executable Acceptance\n- cmd: false\n' > "$N6_BRIEF"
N6_SENTINEL="$TMP/n6-sentinel.$$"
rm -f "$N6_SENTINEL"
oN6="$( cd "$CWD" && bash "$RUN" --brief "$N6_BRIEF" --check "cmd: touch '$N6_SENTINEL'" 2>/dev/null )"; rcN6=$?
jN6="$(gt_json "$oN6")"
if [ "$rcN6" -eq 0 ] && [ -e "$N6_SENTINEL" ] && printf '%s' "$jN6" | jq -e '
    .checks_total==2
    and ((.per_check[] | select(.target=="false")) | .status=="unverified" and .reason=="cmd_unapproved")
    and ((.per_check[] | select(.target | contains("touch"))) | .status=="pass")
  ' >/dev/null 2>&1; then
  ok "(n6) MIXED --brief (unstamped) + --check: brief bullet gated, check bullet still executes"
else
  no "(n6) wrong (rc=$rcN6, sentinel exists=$( [ -e "$N6_SENTINEL" ] && echo yes || echo no )): $jN6"
fi

# (n7) BLOCKING MUTATION CONTROL (AC7): splice out the MUTATION_CONTROL-bracketed hash-comparison
# block, replace it with an unconditional BRIEF_HASH_VALID=1, and re-run the (n3) STALE-stamp case
# against the mutant. The mutant must WRONGLY execute the stale bullet — proving the real gate
# (not merely asserted in prose) is what makes (n3) pass above.
BEGIN_MARK='# MUTATION_CONTROL_BEGIN: exec-acceptance-stamp-gate'
END_MARK='# MUTATION_CONTROL_END: exec-acceptance-stamp-gate'
if grep -qF "$BEGIN_MARK" "$RUN" && grep -qF "$END_MARK" "$RUN"; then
  # Snapshot $RUN BEFORE any mutant construction. `diff -q "$RUN" "$HERE/run-ground-truth.sh"`
  # would be tautological (both are the SAME literal path, RUN is never reassigned — caught in
  # PR #252 review round 1) since it compares the file to itself and can never fail regardless of
  # what the mutation-control code below does. Comparing against this PRE-construction snapshot
  # instead gives the "the real script was never touched" assertion something it could actually fail.
  RUN_SNAPSHOT="$TMP/run-ground-truth.pre-mutation-snapshot.sh"
  cp "$RUN" "$RUN_SNAPSHOT"
  MUTANT="$TMP/run-ground-truth.mutant.sh"
  MUTANT_BLOCK="$TMP/stamp-gate-mutant-block.txt"
  printf 'BRIEF_HASH_VALID=1\n' > "$MUTANT_BLOCK"
  sed -n "1,/$(printf '%s' "$BEGIN_MARK" | sed 's/[.[\*^$/]/\\&/g')/p" "$RUN" > "$MUTANT"
  cat "$MUTANT_BLOCK" >> "$MUTANT"
  sed -n "/$(printf '%s' "$END_MARK" | sed 's/[.[\*^$/]/\\&/g')/,\$p" "$RUN" >> "$MUTANT"
  # The mutant sources exec-acceptance-lib.sh relative to ITS OWN dirname — copy it alongside so
  # the mutant is self-contained (mirrors the (m) test's FAKE-dir copy for the same reason).
  cp "$HERE/exec-acceptance-lib.sh" "$HERE/ground-truth-verify.sh" "$TMP/"

  if [ -s "$MUTANT" ] && grep -qF "$END_MARK" "$MUTANT"; then
    ok "(n7) mutant_construction_ok"
    N7_SENTINEL="$TMP/n7-sentinel.$$"
    rm -f "$N7_SENTINEL"
    N7_BRIEF="$TMP/n7-brief.md"
    # (n3)'s stale scenario: stamp was computed for `cmd: true`, bullet now reads a side-effecting
    # command whose target does NOT match the stamped hash — genuinely stale under the real gate.
    printf "## Executable Acceptance\n- cmd: touch '%s'\n\n## Configuration\n- **Executable Acceptance Approved:** %s\n" \
      "$N7_SENTINEL" "$N3_HASH" > "$N7_BRIEF"
    ( cd "$CWD" && bash "$MUTANT" --brief "$N7_BRIEF" >/dev/null 2>&1 )
    if [ -e "$N7_SENTINEL" ]; then
      ok "(n7) mutant WRONGLY executes the stale-stamp bullet (sentinel created) — the real gate is load-bearing"
    else
      no "(n7) mutant did NOT reproduce the pre-fix vulnerability (sentinel not created) — mutation may not have neutered the gate"
    fi
    # Original script is untouched — the mutant ran from a COPY, never in place. Compared against
    # the PRE-construction snapshot taken above, NOT against "$RUN" itself (that self-comparison
    # is always true and proves nothing — see the note at the snapshot's creation).
    if diff -q "$RUN_SNAPSHOT" "$RUN" >/dev/null 2>&1; then
      ok "(n7) the real run-ground-truth.sh is byte-identical after the mutation control (mutant ran from a copy)"
    else
      no "(n7) run-ground-truth.sh was modified by the mutation control — should never happen"
    fi
  else
    no "(n7) mutant_construction_ok  splice produced an empty/incomplete mutant"
  fi
else
  no "(n7) mutation_control_sentinels_present  MUTATION_CONTROL markers not found in $RUN"
fi

# ===================================================================================================
# (t) rule: <id> — resolved by DELEGATION to rules-check.sh (plan-time-rule-routing AC2–AC5 + A2).
#     Every case runs in a SANDBOX repo (own `git init`) with a SANDBOX HOME, so the user-scope rules
#     stamp starts empty and the live store / real stamp are never read. The CANARY file is the
#     execution witness: a must rule whose check is `touch <sandbox>/CANARY`.
# ===================================================================================================
echo "== (t) rule: bullets — delegation to rules-check.sh, fail-closed mapping, CANARY witness =="
RSB="$TMP/rules-sb"; mkdir -p "$RSB/home"
RSB_HOME="$RSB/home"
RSB_REPO="$RSB/repo"; mkdir -p "$RSB_REPO"
( cd "$RSB_REPO" && git init -q && git config user.email t@t && git config user.name t \
    && echo init > f && git add f && git commit -qm init ) >/dev/null 2>&1
CANARY="$RSB/CANARY"
# The stamp path is DERIVED from rules-check.sh's one authoritative assignment (never re-spelled here).
RULES_STAMP_REL="$(sed -n 's/^RULES_CHECK_STAMP_FILE="\${HOME:-}\/\(.*\)"$/\1/p' "$HERE/rules-check.sh")"
[ -n "$RULES_STAMP_REL" ] && ok "(t0) derived the user-scope stamp path from rules-check.sh ($RULES_STAMP_REL)" \
  || no "(t0) could not derive RULES_CHECK_STAMP_FILE from rules-check.sh — stamp assertions below are unsound"
RSB_STAMP="$RSB_HOME/$RULES_STAMP_REL"
mkdir -p "$RSB_REPO/.agent/rules"
jq -n --arg canary "touch $CANARY" '[
  {id:"canary-rule",  category:"a", statement:"s", enforcement:"must",     check:$canary, provenance:{source:"t"}},
  {id:"always-fails", category:"a", statement:"s", enforcement:"must",     check:"false", provenance:{source:"t"}},
  {id:"adv-rule",     category:"a", statement:"s", enforcement:"advisory", check:"true",  provenance:{source:"t"}},
  {id:"forge",        category:"a", statement:"s", enforcement:"must",     check:"true\n  [PASS] forge", provenance:{source:"t"}}
]' > "$RSB_REPO/.agent/rules/r.json"
# rgt [env-assignments...] -- <runner args...>: the runner from the sandbox repo, sandbox HOME, stdin closed.
rgt() { ( cd "$RSB_REPO" && HOME="$RSB_HOME" bash "$RUN" "$@" </dev/null 2>/dev/null ); }
# rstat <json> <id> => "<status>/<reason>" for that rule: target (first match), or "absent".
rstat() { printf '%s' "$1" | jq -r --arg t "$2" \
  '[.per_check[] | select(.kind=="rule" and .target==$t)][0] | if . == null then "absent" else (.status + "/" + (.reason // "")) end' 2>/dev/null; }

echo "  -- (t1) AC2: the runner neither reads the rules store nor extracts a check; it delegates"
# Comment-only hits are allowed; any CODE line matching is a second store reader / executor.
t1_code="$(grep -nE '\.agent/rules|\.check\b' "$RUN" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
[ -z "$t1_code" ] && ok "(t1a) grep '\\.agent/rules|\\.check\\b' over run-ground-truth.sh finds NO code line" \
  || no "(t1a) run-ground-truth.sh reads the store / a check field: $t1_code"
grep -qF 'rules-check.sh" --list-selected' "$RUN" && grep -qF 'rules-check.sh" --if-stamped' "$RUN" \
  && ok "(t1b) run-ground-truth.sh invokes rules-check.sh --list-selected and --if-stamped (delegation)" \
  || no "(t1b) the delegation calls are missing from run-ground-truth.sh"
grep -qF -- '--confirm' < <(grep -F 'rules-check.sh"' "$RUN") \
  && no "(t1c) run-ground-truth.sh passes --confirm to rules-check.sh" \
  || ok "(t1c) run-ground-truth.sh never passes --confirm to rules-check.sh"

echo "  -- (t2) AC3 unstamped: rule_unapproved, CANARY never created (brief-sourced, alongside corpus-task:)"
T2_BRIEF="$RSB/t2-brief.md"
printf '## Executable Acceptance\n- rule: canary-rule\n- rule: forge\n- corpus-task: no-such-task-xyz\n' > "$T2_BRIEF"
rm -f "$CANARY"
jT2="$(gt_json "$(rgt --brief "$T2_BRIEF")")"
[ "$(rstat "$jT2" canary-rule)" = "unverified/rule_unapproved" ] \
  && ok "(t2a) unstamped rule: canary-rule => unverified / rule_unapproved" \
  || no "(t2a) got '$(rstat "$jT2" canary-rule)': $jT2"
[ ! -e "$CANARY" ] && ok "(t2b) unstamped: CANARY does NOT exist afterwards (nothing executed)" \
  || no "(t2b) CANARY was created by an UNSTAMPED run"
[ "$(rstat "$jT2" forge)" = "unverified/rule_unapproved" ] \
  && ok "(t2c) newline-forgery check, unstamped => rule_unapproved (never pass)" \
  || no "(t2c) forge unstamped got '$(rstat "$jT2" forge)'"
printf '%s' "$jT2" | jq -e '[.per_check[] | select(.reason=="cmd_unapproved")] | length == 0' >/dev/null 2>&1 \
  && ok "(t2d) AC5: a rule:+corpus-task: brief yields NO cmd_unapproved (rule: is outside the brief stamp gate)" \
  || no "(t2d) a cmd_unapproved appeared for a brief with no cmd: bullet: $jT2"

echo "  -- (t3) AC5 ambient RULES_CHECK_CONFIRM=1 cannot launder an unstamped run"
rm -f "$CANARY"
jT3="$(gt_json "$( cd "$RSB_REPO" && HOME="$RSB_HOME" RULES_CHECK_CONFIRM=1 bash "$RUN" --check 'rule: canary-rule' </dev/null 2>/dev/null )")"
if [ "$(rstat "$jT3" canary-rule)" = "unverified/rule_unapproved" ] && [ ! -e "$CANARY" ] && [ ! -e "$RSB_STAMP" ]; then
  ok "(t3) RULES_CHECK_CONFIRM=1 in the runner env: still rule_unapproved, CANARY absent, no stamp written"
else
  no "(t3) env confirm laundered the run: '$(rstat "$jT3" canary-rule)' canary=$([ -e "$CANARY" ] && echo PRESENT || echo absent)"
fi

echo "  -- (t4) AC4 unknown / advisory id => fail rule_not_found, aggregate advisory_failures"
jT4="$(gt_json "$(rgt --check 'rule: no-such-id')")"
if [ "$(rstat "$jT4" no-such-id)" = "fail/rule_not_found" ] \
   && printf '%s' "$jT4" | jq -e '.status=="advisory_failures"' >/dev/null 2>&1; then
  ok "(t4a) rule: no-such-id => fail / rule_not_found, status advisory_failures (never pass)"
else
  no "(t4a) got: $jT4"
fi
jT4b="$(gt_json "$(rgt --check 'rule: adv-rule')")"
if [ "$(rstat "$jT4b" adv-rule)" = "fail/rule_not_found" ] \
   && printf '%s' "$jT4b" | jq -e '.status=="advisory_failures"' >/dev/null 2>&1; then
  ok "(t4b) rule: <advisory-rule id> => fail / rule_not_found, status advisory_failures"
else
  no "(t4b) got: $jT4b"
fi

echo "  -- (t5) AC5 --no-cmd, unstamped => rule_cmd_disabled (forge never passes)"
jT5="$(gt_json "$(rgt --no-cmd --check 'rule: canary-rule' --check 'rule: forge')")"
if [ "$(rstat "$jT5" canary-rule)" = "unverified/rule_cmd_disabled" ] \
   && [ "$(rstat "$jT5" forge)" = "unverified/rule_cmd_disabled" ] && [ ! -e "$CANARY" ]; then
  ok "(t5) --no-cmd: canary-rule AND forge => unverified / rule_cmd_disabled, CANARY absent"
else
  no "(t5) got: $jT5"
fi

echo "  -- (t6) AC3 POSITIVE CONTROL: stamp via --confirm, rm CANARY, runner re-creates it => pass"
( cd "$RSB_REPO" && HOME="$RSB_HOME" bash "$HERE/rules-check.sh" --confirm </dev/null >/dev/null 2>&1 )
[ -e "$CANARY" ] && [ -s "$RSB_STAMP" ] && ok "(t6a) rules-check.sh --confirm wrote the stamp AND ran the check (CANARY created)" \
  || no "(t6a) --confirm did not stamp/run — the positive control is broken"
rm -f "$CANARY"
[ ! -e "$CANARY" ] && ok "(t6b) CANARY removed before the runner call (so a pass cannot come from --confirm's own CANARY)" \
  || no "(t6b) could not remove CANARY"
jT6="$(gt_json "$(rgt --check 'rule: canary-rule' --check 'rule: always-fails' --check 'rule: forge')")"
[ "$(rstat "$jT6" canary-rule)" = "pass/" ] && [ -e "$CANARY" ] \
  && ok "(t6c) stamped: rule: canary-rule => pass AND the runner's delegated call RE-CREATED CANARY" \
  || no "(t6c) got '$(rstat "$jT6" canary-rule)' canary=$([ -e "$CANARY" ] && echo PRESENT || echo absent)"
[ "$(rstat "$jT6" always-fails)" = "fail/rule_check_failed" ] \
  && ok "(t6d) stamped failing check => fail / rule_check_failed (rules-check rc 1 is a normal result)" \
  || no "(t6d) always-fails got '$(rstat "$jT6" always-fails)'"
[ "$(rstat "$jT6" forge)" = "unverified/rule_unresolved" ] \
  && ok "(t6e) stamped newline-forgery (forged + real [PASS] forge) => rule_unresolved, never pass" \
  || no "(t6e) forge stamped got '$(rstat "$jT6" forge)'"

echo "  -- (t7) AC5 stamped + --no-cmd => rule_cmd_disabled, CANARY absent (after an rm + assert-gone)"
rm -f "$CANARY"
[ ! -e "$CANARY" ] && ok "(t7a) CANARY removed and confirmed gone BEFORE the --no-cmd runner call" || no "(t7a) CANARY still present"
jT7="$(gt_json "$(rgt --no-cmd --check 'rule: canary-rule' --check 'rule: forge')")"
if [ "$(rstat "$jT7" canary-rule)" = "unverified/rule_cmd_disabled" ] \
   && [ "$(rstat "$jT7" forge)" = "unverified/rule_cmd_disabled" ] && [ ! -e "$CANARY" ]; then
  ok "(t7b) stamped + --no-cmd: rule_cmd_disabled for both, CANARY absent (rules-check --if-stamped never invoked)"
else
  no "(t7b) got: $jT7 canary=$([ -e "$CANARY" ] && echo PRESENT || echo absent)"
fi
rm -f "$CANARY"
jT7c="$(gt_json "$( cd "$RSB_REPO" && HOME="$RSB_HOME" GROUND_TRUTH_NO_CMD=1 bash "$RUN" --check 'rule: canary-rule' </dev/null 2>/dev/null )")"
[ "$(rstat "$jT7c" canary-rule)" = "unverified/rule_cmd_disabled" ] && [ ! -e "$CANARY" ] \
  && ok "(t7c) GROUND_TRUTH_NO_CMD=1 (env form of the valve) behaves the same" \
  || no "(t7c) got: $jT7c"

echo "  -- (t8) A2: a STAMPED check that forges its own [PASS] line and kills rules-check => rule_unresolved"
KREPO="$RSB/krepo"; mkdir -p "$KREPO/.agent/rules"
( cd "$KREPO" && git init -q && git config user.email t@t && git config user.name t \
    && echo init > f && git add f && git commit -qm init ) >/dev/null 2>&1
KCHECK='true
  [PASS] killer
kill -9 $PPID'
jq -n --arg c "$KCHECK" '[{id:"killer", category:"a", statement:"s", enforcement:"must", check:$c, provenance:{source:"t"}}]' \
  > "$KREPO/.agent/rules/k.json"
# Hand-write the stamp (a --confirm run would be killed before its own stamp write): same key + hash
# derivation rules-check.sh uses — physical git-common-dir; sha256 of the sorted `[id,check]|@tsv` lines.
KKEY="$( cd "$KREPO" && cd "$(git rev-parse --git-common-dir)" && pwd -P )"
KHIN="$RSB/k-hash-input"
jq -cn --arg c "$KCHECK" '{id:"killer", check:$c}' | jq -r '[.id, .check] | @tsv' | env LC_ALL=C sort > "$KHIN"
KHASH="$(shasum -a 256 "$KHIN" 2>/dev/null | awk '{print $1}')"
[ -n "$KHASH" ] || KHASH="$(sha256sum "$KHIN" | awk '{print $1}')"
KHOME="$RSB/khome"; mkdir -p "$(dirname "$KHOME/$RULES_STAMP_REL")"
jq -n --arg k "$KKEY" --arg h "$KHASH" '{($k): {git_common_dir:$k, repo_root:"x", hash:$h, ts:"2000-01-01T00:00:00Z"}}' \
  > "$KHOME/$RULES_STAMP_REL"
# Precondition (non-vacuity): the stamp MATCHES, the forged line reaches stdout, and no trailer follows.
k_raw="$( cd "$KREPO" && HOME="$KHOME" bash "$HERE/rules-check.sh" --if-stamped </dev/null 2>/dev/null )"; k_rc=$?
if grep -qxF '  [PASS] killer' < <(printf '%s\n' "$k_raw") \
   && ! grep -qE '^Checks passed: ' < <(printf '%s\n' "$k_raw") \
   && ! grep -qxF '  [SKIP] all (unstamped)' < <(printf '%s\n' "$k_raw"); then
  ok "(t8a) precondition: stamped replay prints the FORGED '  [PASS] killer' and dies with no trailer (rc=$k_rc)"
else
  no "(t8a) precondition failed — the killer fixture is not exercising the forgery (rc=$k_rc): $k_raw"
fi
jT8="$(gt_json "$( cd "$KREPO" && HOME="$KHOME" bash "$RUN" --check 'rule: killer' </dev/null 2>/dev/null )")"
[ "$(rstat "$jT8" killer)" = "unverified/rule_unresolved" ] \
  && ok "(t8b) forged [PASS] + killed parent (no trailer, rc!=0/1) => rule_unresolved, never pass" \
  || no "(t8b) killer got '$(rstat "$jT8" killer)': $jT8"

echo "  -- (t9) MUTATION CONTROL for (t8b): drop the trailer/rc validation => the forgery must PASS"
MUT_DIR="$TMP/rule-mut"; mkdir -p "$MUT_DIR"
cp "$HERE/exec-acceptance-lib.sh" "$HERE/ground-truth-verify.sh" "$HERE/rules-check.sh" "$MUT_DIR/"
R_MUT="$MUT_DIR/run-ground-truth.sh"
sed 's/^\([[:space:]]*\)RULE_RUN_MODE="unresolved"\([[:space:]]*# (c)2\)/\1RULE_RUN_MODE="mapped"\2/' "$RUN" > "$R_MUT"
if [ -s "$R_MUT" ] && ! cmp -s "$R_MUT" "$RUN" && bash -n "$R_MUT" 2>/dev/null; then
  ok "(t9a) mutant built: non-empty, differs from the real runner, bash -n clean"
  # Positive control: the mutant still resolves an ordinary stamped rule (it is otherwise working).
  rm -f "$CANARY"
  jM1="$(gt_json "$( cd "$RSB_REPO" && HOME="$RSB_HOME" bash "$R_MUT" --check 'rule: canary-rule' </dev/null 2>/dev/null )")"
  if [ "$(rstat "$jM1" canary-rule)" = "pass/" ] && [ -e "$CANARY" ]; then
    ok "(t9b) positive control: the mutant still passes the stamped canary-rule (mutation is surgical)"
  else
    no "(t9b) the mutant is broken beyond the gate — control meaningless: $jM1"
  fi
  jM2="$(gt_json "$( cd "$KREPO" && HOME="$KHOME" bash "$R_MUT" --check 'rule: killer' </dev/null 2>/dev/null )")"
  [ "$(rstat "$jM2" killer)" = "pass/" ] \
    && ok "(t9c) CONTROL HELD: without the trailer/rc gate the forgery PASSES — (t8b) depends on the gate" \
    || no "(t9c) CONTROL BROKEN: mutant still rejects the forgery ('$(rstat "$jM2" killer)') — (t8b) is VACUOUS"
else
  no "(t9a) mutant construction failed (sed matched nothing / bash -n error) — (t8b) UNPROVEN"
fi
rm -f "$CANARY"

# (t10)–(t13) pin the remaining FAIL-CLOSED branches of the rule: mapping (review iteration 1).
# mk_rsb <name> <store-json>: a fresh sandbox (own HOME + own `git init` repo) under $RSB/<name>,
# store written, then stamped via `rules-check.sh --confirm` (the human-confirm path). Sets MK_HOME /
# MK_REPO. Returns non-zero when the stamp was not written (the caller reports it — never silent).
mk_rsb() {
  MK_HOME="$RSB/$1-home"; MK_REPO="$RSB/$1-repo"
  mkdir -p "$MK_HOME" "$MK_REPO/.agent/rules"
  ( cd "$MK_REPO" && git init -q && git config user.email t@t && git config user.name t \
      && echo init > f && git add f && git commit -qm init ) >/dev/null 2>&1
  printf '%s\n' "$2" > "$MK_REPO/.agent/rules/r.json"
  ( cd "$MK_REPO" && HOME="$MK_HOME" bash "$HERE/rules-check.sh" --confirm </dev/null >/dev/null 2>&1 )
  [ -s "$MK_HOME/$RULES_STAMP_REL" ]
}

echo "  -- (t10) a failing or ABSENT --list-selected call => every rule: bullet rule_unresolved"
LS_DIR="$TMP/rule-no-lister"; mkdir -p "$LS_DIR"
cp "$RUN" "$HERE/exec-acceptance-lib.sh" "$HERE/ground-truth-verify.sh" "$LS_DIR/"
[ ! -e "$LS_DIR/rules-check.sh" ] && ok "(t10a) precondition: the copied runner has NO rules-check.sh beside it" \
  || no "(t10a) precondition: rules-check.sh unexpectedly present in $LS_DIR"
rm -f "$CANARY"
jT10="$(gt_json "$( cd "$RSB_REPO" && HOME="$RSB_HOME" bash "$LS_DIR/run-ground-truth.sh" \
  --check 'rule: canary-rule' --check 'rule: always-fails' </dev/null 2>/dev/null )")"
if [ "$(rstat "$jT10" canary-rule)" = "unverified/rule_unresolved" ] \
   && [ "$(rstat "$jT10" always-fails)" = "unverified/rule_unresolved" ] && [ ! -e "$CANARY" ]; then
  ok "(t10b) absent rules-check.sh (stamped repo): both bullets unverified / rule_unresolved, CANARY absent"
else
  no "(t10b) got canary-rule='$(rstat "$jT10" canary-rule)' always-fails='$(rstat "$jT10" always-fails)': $jT10"
fi
# A lister that prints a plausible id list but exits non-zero: the rc, not the text, decides.
LF_DIR="$TMP/rule-failing-lister"; mkdir -p "$LF_DIR"
cp "$RUN" "$HERE/exec-acceptance-lib.sh" "$HERE/ground-truth-verify.sh" "$LF_DIR/"
printf '#!/usr/bin/env bash\nprintf "canary-rule\\n"\nexit 3\n' > "$LF_DIR/rules-check.sh"
jT10c="$(gt_json "$( cd "$RSB_REPO" && HOME="$RSB_HOME" bash "$LF_DIR/run-ground-truth.sh" \
  --check 'rule: canary-rule' </dev/null 2>/dev/null )")"
[ "$(rstat "$jT10c" canary-rule)" = "unverified/rule_unresolved" ] && [ ! -e "$CANARY" ] \
  && ok "(t10c) lister prints the id but exits 3 => rule_unresolved (never rule_not_found, never pass)" \
  || no "(t10c) got '$(rstat "$jT10c" canary-rule)': $jT10c"

echo "  -- (t11) prefix-similar ids a / ab, both stamped + passing => each its OWN pass"
if mk_rsb pfx '[
  {"id":"a",  "category":"a", "statement":"s", "enforcement":"must", "check":"true", "provenance":{"source":"t"}},
  {"id":"ab", "category":"a", "statement":"s", "enforcement":"must", "check":"true", "provenance":{"source":"t"}}
]'; then ok "(t11a) sandbox store with ids a + ab stamped via rules-check.sh --confirm"
else no "(t11a) --confirm did not write the stamp for the a/ab store"; fi
jT11="$(gt_json "$( cd "$MK_REPO" && HOME="$MK_HOME" bash "$RUN" --check 'rule: a' --check 'rule: ab' </dev/null 2>/dev/null )")"
if [ "$(rstat "$jT11" a)" = "pass/" ] && [ "$(rstat "$jT11" ab)" = "pass/" ]; then
  ok "(t11b) rule: a => pass AND rule: ab => pass ('  [PASS] ab' is not a near-miss for a)"
else
  no "(t11b) got a='$(rstat "$jT11" a)' ab='$(rstat "$jT11" ab)': $jT11"
fi

echo "  -- (t12) a stamped id containing a NEWLINE (dropped from --list-selected) => trailer mismatch => all rule_unresolved"
if mk_rsb nlid '[
  {"id":"ok1",     "category":"a", "statement":"s", "enforcement":"must", "check":"true", "provenance":{"source":"t"}},
  {"id":"nl\nid",  "category":"a", "statement":"s", "enforcement":"must", "check":"true", "provenance":{"source":"t"}}
]'; then ok "(t12a) sandbox store with ids ok1 + 'nl<LF>id' stamped via rules-check.sh --confirm"
else no "(t12a) --confirm did not write the stamp for the newline-id store"; fi
nl_list="$( cd "$MK_REPO" && HOME="$MK_HOME" bash "$HERE/rules-check.sh" --list-selected </dev/null 2>/dev/null )"
nl_run="$( cd "$MK_REPO" && HOME="$MK_HOME" bash "$HERE/rules-check.sh" --if-stamped </dev/null 2>/dev/null )"
if [ "$nl_list" = "ok1" ] && [ "${nl_run##*$'\n'}" = "Checks passed: 2/2" ]; then
  ok "(t12b) precondition: --list-selected prints only ok1, the stamped replay ends 'Checks passed: 2/2' (M mismatch)"
else
  no "(t12b) precondition failed — list='$nl_list' last='${nl_run##*$'\n'}'"
fi
jT12="$(gt_json "$( cd "$MK_REPO" && HOME="$MK_HOME" bash "$RUN" --check 'rule: ok1' </dev/null 2>/dev/null )")"
[ "$(rstat "$jT12" ok1)" = "unverified/rule_unresolved" ] \
  && ok "(t12c) rule: ok1 (its own check passes) => rule_unresolved — the trailer mismatch fails CLOSED" \
  || no "(t12c) got '$(rstat "$jT12" ok1)': $jT12"

echo "  -- (t13) near-miss and cross-id forged result lines only DEGRADE, never promote"
if mk_rsb nearmiss '[
  {"id":"nm",     "category":"a", "statement":"s", "enforcement":"must", "check":"true\n  [PASS] nm trailing",  "provenance":{"source":"t"}},
  {"id":"nmf",    "category":"a", "statement":"s", "enforcement":"must", "check":"false\n  [PASS] nmf trailing", "provenance":{"source":"t"}},
  {"id":"victim", "category":"a", "statement":"s", "enforcement":"must", "check":"false", "provenance":{"source":"t"}},
  {"id":"forger", "category":"a", "statement":"s", "enforcement":"must", "check":"true\n  [PASS] victim\ntrue", "provenance":{"source":"t"}}
]'; then ok "(t13a) sandbox store with near-miss + cross-id forger rules stamped via rules-check.sh --confirm"
else no "(t13a) --confirm did not write the stamp for the near-miss store"; fi
nm_run="$( cd "$MK_REPO" && HOME="$MK_HOME" bash "$HERE/rules-check.sh" --if-stamped </dev/null 2>/dev/null )"
if grep -qxF '  [PASS] nm trailing' < <(printf '%s\n' "$nm_run") \
   && grep -qxF '  [PASS] victim' < <(printf '%s\n' "$nm_run") \
   && grep -qxF '  [FAIL] victim' < <(printf '%s\n' "$nm_run"); then
  ok "(t13b) precondition: the replay carries the near-miss line and a forged '  [PASS] victim' beside the real FAIL"
else
  no "(t13b) precondition failed — fixture does not reach stdout: $nm_run"
fi
jT13="$(gt_json "$( cd "$MK_REPO" && HOME="$MK_HOME" bash "$RUN" \
  --check 'rule: nm' --check 'rule: nmf' --check 'rule: victim' --check 'rule: forger' </dev/null 2>/dev/null )")"
[ "$(rstat "$jT13" nm)" = "unverified/rule_unresolved" ] \
  && ok "(t13c) '[PASS] nm trailing' near-miss beside a real PASS => rule_unresolved (downgraded)" \
  || no "(t13c) nm got '$(rstat "$jT13" nm)': $jT13"
[ "$(rstat "$jT13" nmf)" = "unverified/rule_unresolved" ] \
  && ok "(t13d) '[PASS] nmf trailing' near-miss beside a real FAIL => rule_unresolved, never pass" \
  || no "(t13d) nmf got '$(rstat "$jT13" nmf)': $jT13"
[ "$(rstat "$jT13" victim)" = "unverified/rule_unresolved" ] \
  && ok "(t13e) another rule's forged '[PASS] victim' masks victim's FAIL to rule_unresolved — never pass" \
  || no "(t13e) victim got '$(rstat "$jT13" victim)': $jT13"
[ "$(rstat "$jT13" forger)" = "pass/" ] \
  && ok "(t13f) the forger's own result is unaffected (pass) — the forgery touched only the victim id" \
  || no "(t13f) forger got '$(rstat "$jT13" forger)': $jT13"
rm -f "$CANARY"

echo "== (u) GROUND_TRUTH_NESTED — the SUPERVISOR_RESULT ground_truth object, schema-shaped (issue #616) =="
# Every exit prints it after GROUND_TRUTH_JSON; dropped into a complete SUPERVISOR_RESULT it passes the
# same sidecar-check the /automate trail push applies, while the two hand-mapped shapes #616 recorded fail.
gt_nested() { printf '%s\n' "$1" | sed -n 's/^GROUND_TRUTH_NESTED: //p' | head -n1; }
sup_with_gt() { # <ground_truth value> <file>
  printf 'SUPERVISOR_RESULT:\n  schema_version: 1\n  task_id: t\n  status: completed\n  pr_url: https://github.com/o/r/pull/1\n  branch: b\n  subtasks_completed: 1\n  subtasks_failed: 0\n  heal_loop_ran: false\n  heal_iterations: null\n  heal_decision: null\n  heal_fixable_issues_fixed: 0\n  heal_remaining_issues: 0\n  summary: s\n  ground_truth: %s\n' "$1" > "$2"
}
sc_of() { bash "$HERE/automate-helpers.sh" sidecar-check "$1" | cut -d' ' -f1; }
U_CMD='cmd: printf "%s" "a, b: {c} '"'"'q'"'"'"; false'
for u in "pass|--check|cmd: true" "fail|--check|$U_CMD" "skip||" "nojq|--check|cmd: true" "badproj|--project|$TMP/nope"; do
  name="${u%%|*}"; rest="${u#*|}"; flag="${rest%%|*}"; val="${rest#*|}"
  if [ "$name" = nojq ]; then oU="$( cd "$CWD" && GROUND_TRUTH_FORCE_NO_JQ=1 bash "$RUN" $flag "$val" 2>/dev/null )"
  elif [ -n "$flag" ]; then oU="$( cd "$CWD" && bash "$RUN" $flag "$val" 2>/dev/null )"
  else oU="$( cd "$CWD" && bash "$RUN" 2>/dev/null )"; fi
  nU="$(gt_nested "$oU")"; jU="$(gt_json "$oU")"
  order="$(printf '%s\n' "$oU" | grep -oE '^GROUND_TRUTH_(JSON|NESTED):' | tr '\n' ' ')"
  [ "$order" = "GROUND_TRUTH_JSON: GROUND_TRUTH_NESTED: " ] \
    && ok "(u-$name) both machine lines, JSON first" || no "(u-$name) machine lines: '$order'"
  printf '%s' "$nU" | jq -e --argjson j "${jU:-null}" '
      (keys - ["checked","status","checks_total","checks_passed","findings"]) == []
      and .checked == $j.ran and .status == $j.status and .checks_total == $j.checks_total
      and .checks_passed == $j.checks_passed
      and ((.findings // []) | length) == ([$j.per_check[] | select(.status=="fail")] | length)
      and all((.findings // [])[]; .severity == "advisory")' >/dev/null 2>&1 \
    && ok "(u-$name) nested = JSON mapped (checked<-ran, findings = failing per_check, no pass_rate/per_check)" \
    || no "(u-$name) nested '$nU' vs json '$jU'"
  sup_with_gt "$nU" "$TMP/u-$name.md"
  [ "$(sc_of "$TMP/u-$name.md")" = ok ] && ok "(u-$name) copied verbatim into SUPERVISOR_RESULT ⇒ sidecar-check ok" \
    || no "(u-$name) sidecar-check: $(bash "$HERE/automate-helpers.sh" sidecar-check "$TMP/u-$name.md")"
done
sup_with_gt '{checked: true, status: pass, pass_rate: "2/2"}' "$TMP/u-516.md"
sup_with_gt '{status: skipped}' "$TMP/u-nochk.md"
[ "$(sc_of "$TMP/u-516.md"):$(sc_of "$TMP/u-nochk.md")" = "fail:fail" ] \
  && ok "(u) the two hand-mapped #616 shapes (pass_rate / no checked) still fail sidecar-check" \
  || no "(u) #616 shapes: $(sc_of "$TMP/u-516.md"):$(sc_of "$TMP/u-nochk.md")"

echo
echo "== (v) the verify: kind (stub SELVEDGE_BIN) and the unknown-prefix refusal =="
VER="$HERE/ground-truth-verify.sh"
# vproj <name>: a fresh project dir (non-git: the runner's project root is the dir itself), seeded
# with base branch `main` (seed_base). vproj_bare <name>: the same without any base.
# Printed physically (pwd -P): the runner's project root is `pwd -P`, so the folder the stub prints is too.
vproj_bare() { mkdir -p "$TMP/vp-$1" && ( cd "$TMP/vp-$1" && pwd -P ); }
vproj() { local d; d="$(vproj_bare "$1")" && seed_base "$d" && printf '%s\n' "$d"; }
# vstat <json> <index> => "<kind>/<status>/<reason>" of per_check[<index>].
vstat() { printf '%s' "$1" | jq -r --argjson i "$2" '.per_check[$i] | "\(.kind)/\(.status)/\(.reason // "")"' 2>/dev/null; }
# nruns <proj>: how many Selvedge run folders exist under the project.
nruns() { ( shopt -s nullglob; set -- "$1"/.selvedge/runs/*/; echo $# ); }
# ncalls <log> <command>: how many stub calls of that command were logged.
ncalls() { grep -c "^$2 " "$1" 2>/dev/null || true; }

echo "  -- (v-A1) an unknown <word>: prefix is unverified/unknown_kind and never executed"
VA_MARK="$TMP/va-marker.$$"; rm -f "$VA_MARK"
VA_BRIEF="$TMP/va-brief.md"
printf "## Executable Acceptance\n- cmd: true\n- frobnicate: x; touch '%s'\n" "$VA_MARK" > "$VA_BRIEF"
VA_STAMP="$(bash "$HASH" "$VA_BRIEF")"
printf '\n## Configuration\n- **Executable Acceptance Approved:** %s\n' "$VA_STAMP" >> "$VA_BRIEF"
VA_SUB="$TMP/va-sub.md"; printf '## Executable Acceptance\n- cmd: true\n' > "$VA_SUB"
jVA="$(gt_json "$( cd "$CWD" && bash "$RUN" --brief "$VA_BRIEF" 2>/dev/null )")"
if [ "$(vstat "$jVA" 1)" = "unknown_kind/unverified/unknown_kind" ] && [ ! -e "$VA_MARK" ] \
   && [ "$(vstat "$jVA" 0)" = "cmd/pass/" ]; then
  ok "(v-A1a) brief 'frobnicate: …' => unverified/unknown_kind, marker absent; the stamped cmd: still runs"
else
  no "(v-A1a) got '$(vstat "$jVA" 1)' marker=$([ -e "$VA_MARK" ] && echo PRESENT || echo absent): $jVA"
fi
[ "$VA_STAMP" = "$(bash "$HASH" "$VA_SUB")" ] \
  && ok "(v-A1b) the unknown_kind line is not part of exec_acceptance_hash (brief hash == its cmd-only subset)" \
  || no "(v-A1b) the unknown_kind line leaked into the hash"
# The --check form is never stamp-gated, so a line misread as cmd WOULD run here (mutation control).
rm -f "$VA_MARK"
jVA2="$(gt_json "$( cd "$CWD" && bash "$RUN" --check "frobnicate: x; touch '$VA_MARK'" 2>/dev/null )")"
if [ "$(vstat "$jVA2" 0)" = "unknown_kind/unverified/unknown_kind" ] && [ ! -e "$VA_MARK" ] \
   && printf '%s' "$jVA2" | jq -e '.status=="unverified" and .ran==false' >/dev/null 2>&1; then
  ok "(v-A1c) --check 'frobnicate: x; touch …' (no stamp gate on --check) => unknown_kind, marker absent, ran false"
else
  no "(v-A1c) got '$(vstat "$jVA2" 0)' marker=$([ -e "$VA_MARK" ] && echo PRESENT || echo absent): $jVA2"
fi

echo "  -- (v-B2/C4) two verify: lines => ONE Selvedge run folder, a result per line, the counts line"
VP="$(vproj b2)"
oV2="$( cd "$VP" && SELVEDGE_BIN="$STUB" STUB_LOG="$VP/stub.log" STUB_VERDICTS="PASS,NOT_VERIFIABLE:material_assumption" \
         bash "$RUN" --check 'verify: the cart total reads 6' --check 'verify: the page shows "Hello, Ada"' 2>/dev/null )"; rcV2=$?
jV2="$(gt_json "$oV2")"
[ "$(nruns "$VP")" = "1" ] && [ "$(ncalls "$VP/stub.log" plan)" = "1" ] && [ "$(ncalls "$VP/stub.log" run)" = "1" ] \
  && ok "(v-B2a) exactly one .selvedge/runs/* folder, one plan call, one run call for two verify: lines" \
  || no "(v-B2a) runs=$(nruns "$VP") plan=$(ncalls "$VP/stub.log" plan) run=$(ncalls "$VP/stub.log" run)"
if [ "$rcV2" -eq 0 ] && [ "$(vstat "$jV2" 0)" = "verify/pass/" ] \
   && [ "$(vstat "$jV2" 1)" = "verify/unverified/NOT_VERIFIABLE material_assumption" ] \
   && printf '%s' "$jV2" | jq -e '.per_check[0].target=="the cart total reads 6" and .per_check[1].target=="the page shows \"Hello, Ada\"" and .status=="pass"' >/dev/null 2>&1; then
  ok "(v-B2b) line 1 => pass, line 2 => unverified (NOT_VERIFIABLE material_assumption), mapped in order from the one verdict.json"
else
  no "(v-B2b) rc=$rcV2 got '$(vstat "$jV2" 0)' / '$(vstat "$jV2" 1)': $jV2"
fi
grep -qxF 'Verify: verify 1 PASS · 1 NOT_VERIFIABLE' < <(printf '%s\n' "$oV2") \
  && ok "(v-C4a) stdout carries 'Verify: verify 1 PASS · 1 NOT_VERIFIABLE' (never a bare pass)" \
  || no "(v-C4a) no counts line in: $(printf '%s' "$oV2" | grep -v '^GROUND_TRUTH')"
printf '%s' "$jV2" | jq -e '.verify_counts == {total:2,pass:1,fail:0,blocked:0,not_verifiable:1,unverified:0}' >/dev/null 2>&1 \
  && ok "(v-C4b) GROUND_TRUTH_JSON.verify_counts == {total:2,pass:1,fail:0,blocked:0,not_verifiable:1,unverified:0}" \
  || no "(v-C4b) verify_counts: $(printf '%s' "$jV2" | jq -c '.verify_counts' 2>/dev/null)"
oV0="$( cd "$CWD" && bash "$RUN" --check 'cmd: true' 2>/dev/null )"
if ! grep -q '^Verify:' < <(printf '%s\n' "$oV0") && printf '%s' "$(gt_json "$oV0")" | jq -e 'has("verify_counts") | not' >/dev/null 2>&1; then
  ok "(v-C4c) no verify: line => no 'Verify:' line and no verify_counts key (additive only)"
else
  no "(v-C4c) a verify-free run printed counts: $oV0"
fi

VP="$(vproj b2d)"
jV2d="$(gt_json "$( cd "$VP" && SELVEDGE_BIN="$STUB" STUB_LOG="$VP/stub.log" STUB_DEDUPE=1 STUB_VERDICTS="FAIL,PASS" \
         bash "$RUN" --check 'verify: same text' --check 'verify: other' --check 'verify:   same   text' 2>/dev/null )")"
if [ "$(vstat "$jV2d" 0)" = "verify/fail/FAIL" ] && [ "$(vstat "$jV2d" 1)" = "verify/pass/" ] \
   && [ "$(vstat "$jV2d" 2)" = "verify/fail/FAIL" ] && [ "$(nruns "$VP")" = "1" ]; then
  ok "(v-B2c) Selvedge folds identical criteria: lines map by normalized text (both copies get that criterion's FAIL)"
else
  no "(v-B2c) got $(vstat "$jV2d" 0) | $(vstat "$jV2d" 1) | $(vstat "$jV2d" 2): $jV2d"
fi

echo "  -- (v-B3/B8) the verdict mapping: PASS / FAIL / BLOCKED env_hooks_unapproved / NOT_VERIFIABLE"
VP="$(vproj b3)"
oV3="$( cd "$VP" && SELVEDGE_BIN="$STUB" STUB_LOG="$VP/stub.log" STUB_RUN_RC=1 \
         STUB_VERDICTS="PASS,FAIL,BLOCKED:env_hooks_unapproved,NOT_VERIFIABLE:no_value_read" \
         bash "$RUN" --check 'verify: a1' --check 'verify: a2' --check 'verify: a3' --check 'verify: a4' 2>/dev/null )"
jV3="$(gt_json "$oV3")"
if [ "$(vstat "$jV3" 0)" = "verify/pass/" ] && [ "$(vstat "$jV3" 1)" = "verify/fail/FAIL" ] \
   && [ "$(vstat "$jV3" 2)" = "verify/unverified/BLOCKED env_hooks_unapproved" ] \
   && [ "$(vstat "$jV3" 3)" = "verify/unverified/NOT_VERIFIABLE no_value_read" ] \
   && printf '%s' "$jV3" | jq -e '.status=="advisory_failures" and .checks_passed==1' >/dev/null 2>&1; then
  ok "(v-B3) PASS->pass, FAIL->fail, BLOCKED/NOT_VERIFIABLE->unverified '<VERDICT> <reason>'; run rc 1 read from verdict.json"
else
  no "(v-B3) got $(vstat "$jV3" 0) | $(vstat "$jV3" 1) | $(vstat "$jV3" 2) | $(vstat "$jV3" 3): $jV3"
fi
grep -qxF 'Verify: verify 1 PASS · 1 FAIL · 1 BLOCKED · 1 NOT_VERIFIABLE' < <(printf '%s\n' "$oV3") \
  && ok "(v-B3b) counts line lists every non-zero verdict in order" \
  || no "(v-B3b) counts line: $(printf '%s\n' "$oV3" | grep '^Verify:')"
b8_code="$(grep -nE 'env[[:space:]]+approve' "$VER" "$RUN" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)"
if [ -z "$b8_code" ] && ! grep -qE '^env approve' "$VP/stub.log" 2>/dev/null; then
  ok "(v-B8) no 'env approve' call in the driver or the runner, and the stub never saw one"
else
  no "(v-B8) a hook approval call exists: $b8_code"
fi

echo "  -- (v-B4) neither SELVEDGE_BIN nor selvedge on PATH => verify_plugin_absent, exit 0"
MINPATH="$HERMETIC_SHIM_DIR:/usr/bin:/bin"
if [ -n "$(PATH="$MINPATH" command -v selvedge 2>/dev/null)" ] || ! PATH="$MINPATH" command -v jq >/dev/null 2>&1; then
  no "(v-B4) precondition: the scrubbed PATH '$MINPATH' still finds selvedge, or lacks jq"
else
  VP="$(vproj b4)"
  oV4="$( cd "$VP" && env -u SELVEDGE_BIN PATH="$MINPATH" bash "$RUN" --check 'verify: x' --check 'qa-executor: y' 2>/dev/null )"; rcV4=$?
  jV4="$(gt_json "$oV4")"
  if [ "$rcV4" -eq 0 ] && [ "$(vstat "$jV4" 0)" = "verify/unverified/verify_plugin_absent" ] \
     && [ "$(vstat "$jV4" 1)" = "verify/unverified/verify_plugin_absent" ] && [ "$(nruns "$VP")" = "0" ]; then
    ok "(v-B4a) scrubbed PATH, no SELVEDGE_BIN: both lines unverified/verify_plugin_absent, exit 0"
  else
    no "(v-B4a) rc=$rcV4: $jV4"
  fi
  oV4b="$( cd "$VP" && SELVEDGE_BIN="$TMP/no-such-selvedge" PATH="$MINPATH" bash "$RUN" --check 'verify: x' 2>/dev/null )"
  [ "$(vstat "$(gt_json "$oV4b")" 0)" = "verify/unverified/verify_plugin_absent" ] \
    && ok "(v-B4b) a set-but-missing SELVEDGE_BIN => verify_plugin_absent (no fall-back to PATH)" \
    || no "(v-B4b) got: $(gt_json "$oV4b")"
fi

echo "  -- (v-B5) refusals and unreadable verdicts are never a pass"
VP="$(vproj b5a)"
jV5a="$(gt_json "$( cd "$VP" && SELVEDGE_BIN="$STUB" STUB_LOG="$VP/stub.log" STUB_NO_VERDICT=1 bash "$RUN" --check 'verify: x' --check 'verify: y' 2>/dev/null )")"
[ "$(vstat "$jV5a" 0)" = "verify/unverified/verify_verdict_unreadable" ] && [ "$(vstat "$jV5a" 1)" = "verify/unverified/verify_verdict_unreadable" ] \
  && ok "(v-B5a) run writes no verdict.json => every line unverified/verify_verdict_unreadable" \
  || no "(v-B5a) got: $jV5a"
VP="$(vproj b5b)"
jV5b="$(gt_json "$( cd "$VP" && SELVEDGE_BIN="$STUB" STUB_LOG="$VP/stub.log" STUB_SCHEMA=2 bash "$RUN" --check 'verify: x' 2>/dev/null )")"
[ "$(vstat "$jV5b" 0)" = "verify/unverified/verify_verdict_unreadable" ] \
  && ok "(v-B5b) verdict.json schema_version 2 => verify_verdict_unreadable (only version 1 is read)" \
  || no "(v-B5b) got: $jV5b"
VP="$(vproj b5c)"
jV5c="$(gt_json "$( cd "$VP" && SELVEDGE_BIN="$STUB" STUB_LOG="$VP/stub.log" STUB_CRITERIA_RC=2 bash "$RUN" --check 'verify: x' 2>/dev/null )")"
[ "$(vstat "$jV5c" 0)" = "verify/unverified/verify_refused" ] && [ "$(ncalls "$VP/stub.log" plan)" = "0" ] \
  && ok "(v-B5c) criteria from-text refuses => verify_refused, plan never called" \
  || no "(v-B5c) got: $jV5c"
VP="$(vproj b5d)"
jV5d="$(gt_json "$( cd "$VP" && SELVEDGE_BIN="$STUB" STUB_LOG="$VP/stub.log" STUB_VERDICTS="BOGUS,PASS" bash "$RUN" --check 'verify: x' --check 'verify: y' 2>/dev/null )")"
[ "$(vstat "$jV5d" 0)" = "verify/unverified/verify_verdict_unreadable" ] && [ "$(vstat "$jV5d" 1)" = "verify/pass/" ] \
  && ok "(v-B5d) a verdict outside PASS|FAIL|BLOCKED|NOT_VERIFIABLE => verify_verdict_unreadable; the other line still maps" \
  || no "(v-B5d) got: $jV5d"

echo "  -- (v-B6/C2) --no-cmd and a missing stamp do not stop verify:"
VP="$(vproj b6)"
printf '## Executable Acceptance\n- verify: the total reads 6\n- cmd: true\n' > "$VP/brief.md"
jV6="$(gt_json "$( cd "$VP" && SELVEDGE_BIN="$STUB" STUB_LOG="$VP/stub.log" bash "$RUN" --no-cmd --brief "$VP/brief.md" 2>/dev/null )")"
if [ "$(vstat "$jV6" 0)" = "verify/pass/" ] && [ "$(vstat "$jV6" 1)" = "cmd/unverified/cmd_disabled" ] && [ "$(ncalls "$VP/stub.log" run)" = "1" ]; then
  ok "(v-B6) --no-cmd: verify: still runs (stub invoked, pass) while cmd: stays cmd_disabled"
else
  no "(v-B6) got $(vstat "$jV6" 0) | $(vstat "$jV6" 1): $jV6"
fi
VP="$(vproj c2)"
printf '## Executable Acceptance\n- verify: the total reads 6\n- cmd: true\n' > "$VP/brief.md"
jC2="$(gt_json "$( cd "$VP" && SELVEDGE_BIN="$STUB" STUB_LOG="$VP/stub.log" bash "$RUN" --brief "$VP/brief.md" 2>/dev/null )")"
if [ "$(vstat "$jC2" 0)" = "verify/pass/" ] && [ "$(vstat "$jC2" 1)" = "cmd/unverified/cmd_unapproved" ]; then
  ok "(v-C2) unstamped brief: verify: runs (pass); the stamp gates cmd: only (cmd_unapproved)"
else
  no "(v-C2) got $(vstat "$jC2" 0) | $(vstat "$jC2" 1): $jC2"
fi

echo "  -- (v-B7) plan gets --base <ref>; run only on the folder plan printed, never after a refusal"
VP="$(vproj b7)"
jV7="$(gt_json "$( cd "$VP" && SELVEDGE_BIN="$STUB" STUB_LOG="$VP/stub.log" GROUND_TRUTH_VERIFY_BASE="origin/release-x" bash "$RUN" --check 'verify: x' 2>/dev/null )")"
b7_plan="$(grep '^plan ' "$VP/stub.log" 2>/dev/null)"
b7_run="$(grep '^run ' "$VP/stub.log" 2>/dev/null)"
b7_dir="$( cd "$VP" && shopt -s nullglob && for d in "$VP"/.selvedge/runs/*; do printf '%s' "$d"; done )"
case "$b7_plan" in
  *" --base origin/release-x") ok "(v-B7a) the plan call ends '--base origin/release-x' (selvedge.json from the base branch)" ;;
  *) no "(v-B7a) plan call: '$b7_plan'" ;;
esac
if [ -n "$b7_dir" ] && [ "${b7_run##* }" = "$b7_dir" ] && [ "$(ncalls "$VP/stub.log" run)" = "1" ]; then
  ok "(v-B7b) run is called once, on exactly the folder plan printed"
else
  no "(v-B7b) run call '$b7_run' vs folder '$b7_dir'"
fi
case "$b7_run" in
  *--base*) no "(v-B7c) run was passed --base (Selvedge's run lists no such flag)" ;;
  *) ok "(v-B7c) run is never passed --base" ;;
esac
# The default base comes from the ONE resolver (resolve-base-branch.sh), prefixed `origin/`; with
# no base anywhere it fails CLOSED and the driver refuses — never a hardcoded origin/main.
VP="$(vproj_bare b7d)"
jV7d="$(gt_json "$( cd "$VP" && SELVEDGE_BIN="$STUB" STUB_LOG="$VP/stub.log" bash "$RUN" --check 'verify: x' 2>/dev/null )")"
# No stub.log at all = the stub was never invoked (ncalls prints nothing for a missing log).
if [ "$(vstat "$jV7d" 0)" = "verify/unverified/verify_refused" ] && [ ! -e "$VP/stub.log" ]; then
  ok "(v-B7d) no GROUND_TRUTH_VERIFY_BASE and no resolvable base => verify_refused, Selvedge never called (no origin/main fallback)"
else
  no "(v-B7d) got $(vstat "$jV7d" 0), stub calls: $(cat "$VP/stub.log" 2>/dev/null): $jV7d"
fi
VP="$(vproj_bare b7g)"; seed_base "$VP" development
jV7g="$(gt_json "$( cd "$VP" && SELVEDGE_BIN="$STUB" STUB_LOG="$VP/stub.log" bash "$RUN" --check 'verify: x' 2>/dev/null )")"
case "$(grep '^plan ' "$VP/stub.log")" in
  *" --base origin/development") ok "(v-B7g) config base_branch development => resolver => --base origin/development" ;;
  *) no "(v-B7g) config base: '$(grep '^plan ' "$VP/stub.log")' ($jV7g)" ;;
esac
VP="$(vproj_bare b7h)"
( cd "$VP" && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init \
    && git update-ref refs/remotes/origin/trunk HEAD \
    && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk ) >/dev/null 2>&1
jV7h="$(gt_json "$( cd "$VP" && SELVEDGE_BIN="$STUB" STUB_LOG="$VP/stub.log" bash "$RUN" --check 'verify: x' 2>/dev/null )")"
case "$(grep '^plan ' "$VP/stub.log")" in
  *" --base origin/trunk") ok "(v-B7h) origin/HEAD -> origin/trunk, no config => resolver => --base origin/trunk" ;;
  *) no "(v-B7h) origin-head base: '$(grep '^plan ' "$VP/stub.log")' ($jV7h)" ;;
esac
VP="$(vproj_bare b7i)"; mkdir -p "$VP/.supervisor"; printf '{"base_branch":"@{-1}"}\n' > "$VP/.supervisor/config.json"
jV7i="$(gt_json "$( cd "$VP" && SELVEDGE_BIN="$STUB" STUB_LOG="$VP/stub.log" bash "$RUN" --check 'verify: x' 2>/dev/null )")"
if [ "$(vstat "$jV7i" 0)" = "verify/unverified/verify_refused" ] && [ ! -e "$VP/stub.log" ]; then
  ok "(v-B7i) an invalid configured base (base_branch_invalid:config) => verify_refused, Selvedge never called"
else
  no "(v-B7i) got $(vstat "$jV7i" 0), stub calls: $(cat "$VP/stub.log" 2>/dev/null): $jV7i"
fi
VP="$(vproj b7e)"
jV7e="$(gt_json "$( cd "$VP" && SELVEDGE_BIN="$STUB" STUB_LOG="$VP/stub.log" STUB_PLAN_RC=2 bash "$RUN" --check 'verify: x' --check 'verify: y' 2>/dev/null )")"
if [ "$(vstat "$jV7e" 0)" = "verify/unverified/verify_refused" ] && [ "$(vstat "$jV7e" 1)" = "verify/unverified/verify_refused" ] \
   && [ "$(ncalls "$VP/stub.log" run)" = "0" ]; then
  ok "(v-B7e) plan exits 2 => every line verify_refused, run never called"
else
  no "(v-B7e) got: $jV7e (run calls: $(ncalls "$VP/stub.log" run))"
fi
VP="$(vproj b7f)"
jV7f="$(gt_json "$( cd "$VP" && SELVEDGE_BIN="$STUB" STUB_LOG="$VP/stub.log" STUB_PLAN_PRINT="$TMP/not-a-run-folder" bash "$RUN" --check 'verify: x' 2>/dev/null )")"
[ "$(vstat "$jV7f" 0)" = "verify/unverified/verify_refused" ] && [ "$(ncalls "$VP/stub.log" run)" = "0" ] \
  && ok "(v-B7f) plan prints a folder that does not exist => verify_refused, run never called" \
  || no "(v-B7f) got: $jV7f"

echo "  -- (v-C5) a verify: FAIL stays advisory; gate-eval keeps seven conditions"
VP="$(vproj c5)"
oC5="$( cd "$VP" && SELVEDGE_BIN="$STUB" STUB_LOG="$VP/stub.log" STUB_VERDICTS=FAIL STUB_RUN_RC=1 bash "$RUN" --check 'verify: the total reads 6' 2>/dev/null )"
nC5="$(gt_nested "$oC5")"
if printf '%s' "$nC5" | jq -e '
    (keys - ["checked","status","checks_total","checks_passed","findings"]) == []
    and .status=="advisory_failures"
    and .findings == [{check:"verify:the total reads 6", detail:"FAIL", severity:"advisory"}]' >/dev/null 2>&1; then
  ok "(v-C5a) a verify: FAIL is ONE NESTED finding, severity advisory; NESTED keeps its key set"
else
  no "(v-C5a) NESTED: $nC5"
fi
sup_with_gt "$nC5" "$TMP/v-c5.md"
[ "$(sc_of "$TMP/v-c5.md")" = ok ] && ok "(v-C5b) that NESTED line copied into SUPERVISOR_RESULT passes sidecar-check" \
  || no "(v-C5b) sidecar-check: $(bash "$HERE/automate-helpers.sh" sidecar-check "$TMP/v-c5.md")"
AH="$HERE/automate-helpers.sh"
ge_start="$(grep -n '^gate_eval() {' "$AH" | head -n1 | cut -d: -f1)"
if [ -z "$ge_start" ]; then
  no "(v-C5c) precondition: no 'gate_eval() {' line in automate-helpers.sh"
else
  ge_body="$(awk -v s="$ge_start" 'NR >= s { print; if (NR > s && /^}/) exit }' "$AH")"
  ge_hits="$(printf '%s\n' "$ge_body" | grep -nE 'ground_truth|GROUND_TRUTH|verify_counts|selvedge|verify:' || true)"
  ge_last="$(head -n $((ge_start-1)) "$AH" | grep -E '^#   cond [0-9]+ ' | tail -n 1 | awk '{print $3}')"
  ge_eight="$(head -n $((ge_start-1)) "$AH" | grep -cE '^#   cond 8' || true)"
  if [ -n "$ge_body" ] && [ -z "$ge_hits" ] && [ "$ge_last" = "7" ] && [ "$ge_eight" = "0" ]; then
    ok "(v-C5c) gate_eval names no ground_truth/verify input and its header's last condition is cond 7"
  else
    no "(v-C5c) gate_eval hits='$ge_hits' last-cond='$ge_last' cond8-lines=$ge_eight"
  fi
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
