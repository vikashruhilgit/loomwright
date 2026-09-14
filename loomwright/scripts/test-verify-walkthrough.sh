#!/usr/bin/env bash
# test-verify-walkthrough.sh — self-tests for the `/verify <ticket>` walkthrough seam: the mechanized
# main-thread steps in verify-run.sh (`acs` / `preflight` / `verdict` / `finish`), the browser arms
# (`walk`, appended by Subtask 2 below the marked anchor) and the prompt-surface arms (command / skill /
# agent, appended by Subtask 3 below the second anchor). Schema authority: docs/RESULT_SCHEMAS.md
# §VERIFY_EVIDENCE (every line recorded) and §VERIFY_RESULT (the block the agent emits).
#
# WRITE CONTAINMENT AND CALL CONTAINMENT ARE THE POINT OF THIS FILE'S SHAPE. Every fixture lives under
# a `mktemp -d`; the script under test is a COPY staged beside a STUB `verify-env.sh` that tees every
# invocation to a call log and does nothing else, so the arms can assert not only what was written but
# what was CALLED — AC1's "no executor call of any kind" and AC2's "assert-non-prod only, never start"
# are call-log facts. One arm (AC2-real) swaps the REAL executor in, so the stub's answers are proven
# to match the executor's on the two paths this seam depends on (`cmd: false` refuses with the same
# bracketed token; `cmd: true` passes). Precedent: test-verify-seam.sh / test-verify-evidence.sh.
#
# Static-only (this half): no network, no `gh`, no Docker, no browser. Exit 0 = all pass, 1 = any
# failure (auto-registered by ci.yml's `loomwright/scripts/test-*.sh` glob).
#
# Arms:
#   (AC1)  absent contract       → stdout names the absence AND the bootstrap line (propose-verify.sh,
#                                  --non-prod, --confirm — three separate greps), exit 3, NO
#                                  .supervisor/verify/ dir, call log EMPTY
#   (AC2)  non_prod_assert fails → exit 1, reason non_prod_assert_failed on stdout, evidence.jsonl is
#                                  EXACTLY run_start + the env fail line, no ac line, call log is ONE
#                                  `assert-non-prod …` line and no `start`
#   (AC2r) the REAL executor     → the same contract (`cmd: false`) refuses through verify-env.sh with
#                                  the same token; the positive control (`cmd: true`) passes: env pass
#                                  line, acs.json (3 entries), diff.stat, `run_dir=` LAST on stdout
#   (AC6)  acs on both kinds     → requirement: 3 entries AC1..AC3, a wrapped bullet folded; brief: 2
#                                  entries, checkbox + `ACn` label stripped; ticket_kind per path; a
#                                  README path / a header-less file → exit 2 [ticket_unresolved]
#   (AC5s) verdict               → NOT_VERIFIABLE appends the ac line (classification null, reason
#                                  verbatim, text from acs.json); PASS → exit 2 [pass_requires_
#                                  observation]; FAIL → exit 2 [fail_requires_observation]; BLOCKED
#                                  defaults ENVIRONMENT_ISSUE; unknown ac_id refused; no `playwright`
#                                  token in the call log; two observed PASS lines (appended the way
#                                  walk's ingest does, through evidence-append) + one NOT_VERIFIABLE
#                                  ⇒ `PASS: 2 · FAIL: 0 · BLOCKED: 0 · NOT_VERIFIABLE: 1 · total: 3`
#   (FIN)  finish                → appends run_end WITHOUT counts, prints the counts row; --status
#                                  aborted accepted; a bogus status is a usage error (exit 2)
#   (RUN)  run-dir uniqueness    → two preflights in the same second get DIFFERENT run dirs (the
#                                  helper's run-id is second-resolution; a reused dir would merge runs)
#   (S)    static shape          → `bash -n`; --help lists the subcommands; verify-run.sh never writes
#                                  evidence.jsonl itself (only through evidence-append); no browser-
#                                  harness product token (`grep -cE 'Claude_Browser|computer-use|mcp__'` = 0)

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$HERE/verify-run.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

for f in "$RUNNER" "$HERE/verify-helpers.sh" "$HERE/validate-verify-evidence.py" "$HERE/read-verify.sh" \
         "$HERE/propose-verify.sh" "$HERE/verify-env.sh"; do
  if [ ! -f "$f" ]; then
    echo "  FAIL: required file not found at $f"
    echo "RESULT: 0 passed, 1 failed"
    exit 1
  fi
done
for tool in python3 jq git; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "  FAIL: $tool is required by this suite"
    echo "RESULT: 0 passed, 1 failed"
    exit 1
  fi
done

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT" 2>/dev/null' EXIT
mktmp() { mktemp -d "$ROOT/d.XXXXXX"; }

# ---------------------------------------------------------------------------
# Harness: stage() builds $T/bin (a COPY of the runner + its real siblings + the executor STUB) and
# $T/repo (a git repo with one commit, a requirement ticket, a brief ticket, a README).
# ---------------------------------------------------------------------------
LAST_OUT="$ROOT/last-stdout.txt"
LAST_ERR="$ROOT/last-stderr.txt"

stage() {
  local T="$1"
  mkdir -p "$T/bin" "$T/repo/.supervisor/requirements/verify-walkthrough" "$T/repo/.supervisor/jobs/done"
  cp "$RUNNER" "$HERE/verify-helpers.sh" "$HERE/validate-verify-evidence.py" "$HERE/read-verify.sh" \
     "$HERE/propose-verify.sh" "$T/bin/"
  # The executor STUB: tees "$*" to the call log; answers per STUB_NONPROD (pass|fail) with the real
  # executor's stdout line / bracketed stderr token so the runner's parsing is exercised for real.
  cat > "$T/bin/verify-env.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${STUB_CALLS:?STUB_CALLS unset}"
case "${STUB_NONPROD:-pass}" in
  fail) echo "verify-env: every non_prod_assert member failed (1 evaluated) — this target could be production; refusing [non_prod_assert_failed]" >&2; exit 1 ;;
  *)    echo "non-prod asserted"; exit 0 ;;
esac
STUB
  chmod +x "$T/bin/"*.sh
  cat > "$T/repo/.supervisor/requirements/verify-walkthrough/03-echo-form.md" <<'EOF'
# 03 — echo form

## Problem
A form that echoes.

## Acceptance criteria
- Given the form page, when it loads, then a Value field and a Submit button are visible.
- Given the Value field, when `hello` is submitted, then the follow-up page shows `hello`
  in the echo paragraph.
- Given 200 bookings, when submitted under 200 concurrent users, then no double-booking occurs.

## Notes
- this bullet is NOT an acceptance criterion
EOF
  cat > "$T/repo/.supervisor/jobs/done/2026-09-14-echo-form.md" <<'EOF'
# Supervisor Job: echo form

## Task
Ship it.

## Acceptance Criteria
- [ ] AC1 Given the form page, when it loads, then the field is visible.
- [x] AC2: Given `hello`, when submitted, then the echo shows `hello`.

## Outcomes Rubric
- something
EOF
  cat > "$T/repo/.supervisor/requirements/verify-walkthrough/99-no-header.md" <<'EOF'
# 99 — no acceptance criteria section

## Goal
- Given nothing, when nothing, then nothing.
EOF
  printf '# fixture\n' > "$T/repo/README.md"
  ( cd "$T/repo" && git init -q && git add -A >/dev/null 2>&1 \
    && git -c user.email=t@example.invalid -c user.name=t commit -q -m init ) || { echo "  FAIL: fixture git init"; exit 1; }
}

# contract <T> <cmd> — write a well-formed .agent/verify.json whose non_prod_assert.cmd is <cmd>.
contract() {
  mkdir -p "$1/repo/.agent"
  jq -n --arg cmd "$2" '{start: null, base_url: "http://localhost:3000", health: "/",
    auth: {method: "none", storage_state_path: null, probe_path: null},
    non_prod_assert: {cmd: $cmd}, seed: null, reset: null, stop: null}' > "$1/repo/.agent/verify.json"
}

# run_bin <T> <args…> — runs the STAGED runner (cwd = the fixture repo); stdout/stderr to fixed files;
# the function's status is the runner's (capture `$?` in the very next statement).
run_bin() {
  local T="$1"; shift
  : > "$LAST_OUT"; : > "$LAST_ERR"
  ( cd "$T/repo" && STUB_CALLS="$T/calls.log" bash "$T/bin/verify-run.sh" "$@" ) >"$LAST_OUT" 2>"$LAST_ERR"
}
last_run_dir() { grep '^run_dir=' "$LAST_OUT" | tail -1 | sed 's/^run_dir=//'; }
calls_count() { if [ -f "$1/calls.log" ]; then grep -c . "$1/calls.log"; else echo 0; fi; }
ev_lines() { if [ -f "$1/evidence.jsonl" ]; then grep -c . "$1/evidence.jsonl"; else echo 0; fi; }
ev_field() { jq -r "$2" "$1/evidence.jsonl" 2>/dev/null; }   # <run_dir> <jq over every line>

REQ=".supervisor/requirements/verify-walkthrough/03-echo-form.md"
BRIEF=".supervisor/jobs/done/2026-09-14-echo-form.md"

# ============================================================================
echo "== (AC1) absent contract → named absence + bootstrap line, exit 3, nothing created, nothing called =="
T1="$(mktmp)"; stage "$T1"
run_bin "$T1" preflight "$REQ" --repo .
rc=$?
[ "$rc" -eq 3 ] && ok "(AC1) exit 3" || no "(AC1) exit $rc, expected 3 (stdout: $(cat "$LAST_OUT") stderr: $(cat "$LAST_ERR"))"
grep -qF 'no verification contract at .agent/verify.json' "$LAST_OUT" && ok "(AC1) stdout names the absence" || no "(AC1) stdout does not name the absence: $(cat "$LAST_OUT")"
grep -qF 'propose-verify.sh' "$LAST_OUT" && ok "(AC1) bootstrap line names propose-verify.sh" || no "(AC1) no propose-verify.sh on stdout"
grep -qF -- '--non-prod' "$LAST_OUT" && ok "(AC1) bootstrap line carries --non-prod (required by the bootstrap)" || no "(AC1) no --non-prod on stdout"
grep -qF -- '--confirm' "$LAST_OUT" && ok "(AC1) bootstrap line carries --confirm" || no "(AC1) no --confirm on stdout"
[ ! -e "$T1/repo/.supervisor/verify" ] && ok "(AC1) no run dir created under .supervisor/verify/" || no "(AC1) .supervisor/verify/ was created: $(ls "$T1/repo/.supervisor/verify")"
[ "$(calls_count "$T1")" -eq 0 ] && ok "(AC1) call log EMPTY — no verify-env.sh call of any kind" || no "(AC1) executor was called: $(cat "$T1/calls.log")"

# ============================================================================
echo "== (AC2) non_prod_assert fails → exit 1, run_start + env fail line ONLY, assert-non-prod ONLY =="
T2="$(mktmp)"; stage "$T2"; contract "$T2" false
STUB_NONPROD=fail run_bin "$T2" preflight "$REQ" --repo .
rc=$?
RD2="$(last_run_dir)"
[ "$rc" -eq 1 ] && ok "(AC2) exit 1" || no "(AC2) exit $rc, expected 1 (stderr: $(cat "$LAST_ERR"))"
grep -qF 'non_prod_assert_failed' "$LAST_OUT" && ok "(AC2) stdout carries the reason non_prod_assert_failed" || no "(AC2) reason missing from stdout: $(cat "$LAST_OUT")"
[ -n "$RD2" ] && [ -d "$RD2" ] && ok "(AC2) run_dir=<path> printed and exists" || no "(AC2) no run_dir on stdout: $(cat "$LAST_OUT")"
[ "$(ev_lines "$RD2")" -eq 2 ] && ok "(AC2) evidence.jsonl holds EXACTLY two lines" || no "(AC2) evidence.jsonl has $(ev_lines "$RD2") lines: $(cat "$RD2/evidence.jsonl" 2>/dev/null)"
[ "$(sed -n 1p "$RD2/evidence.jsonl" | jq -r '.event')" = "run_start" ] && ok "(AC2) line 1 is run_start" || no "(AC2) line 1 is not run_start"
l2="$(sed -n 2p "$RD2/evidence.jsonl" | jq -r '[.event, .step, .outcome, .reason] | join("|")')"
[ "$l2" = "env|non_prod_assert|fail|non_prod_assert_failed" ] && ok "(AC2) line 2 is env/non_prod_assert/fail/non_prod_assert_failed" || no "(AC2) line 2 is '$l2'"
[ "$(ev_field "$RD2" 'select(.event == "ac") | .ac_id' | grep -c .)" -eq 0 ] && ok "(AC2) no ac line" || no "(AC2) an ac line exists"
[ "$(calls_count "$T2")" -eq 1 ] && ok "(AC2) call log has exactly ONE line" || no "(AC2) call log: $(cat "$T2/calls.log" 2>/dev/null)"
grep -q '^assert-non-prod' "$T2/calls.log" && ok "(AC2) the one call is assert-non-prod" || no "(AC2) the call is not assert-non-prod: $(cat "$T2/calls.log")"
! grep -qE '(^| )start( |$)' "$T2/calls.log" && ok "(AC2) start was NEVER called" || no "(AC2) start was called"
python3 "$T2/bin/validate-verify-evidence.py" "$RD2/evidence.jsonl" >/dev/null 2>&1 && ok "(AC2) the store re-validates in file mode" || no "(AC2) the store does not re-validate"

# ============================================================================
echo "== (AC2r) the REAL executor: cmd false refuses with the same token; cmd true passes =="
T3="$(mktmp)"; stage "$T3"; cp "$HERE/verify-env.sh" "$T3/bin/verify-env.sh"; contract "$T3" false
run_bin "$T3" preflight "$REQ" --repo .
rc=$?
RD3="$(last_run_dir)"
[ "$rc" -eq 1 ] && grep -qF 'non_prod_assert_failed' "$LAST_OUT" \
  && [ "$(sed -n 2p "$RD3/evidence.jsonl" | jq -r '.reason')" = "non_prod_assert_failed" ] \
  && ok "(AC2r) real executor, cmd false → exit 1, env fail line reason non_prod_assert_failed" \
  || no "(AC2r) real executor cmd false: rc=$rc stdout=$(cat "$LAST_OUT") line2=$(sed -n 2p "$RD3/evidence.jsonl" 2>/dev/null)"
sleep 1   # run-id is second-resolution; keep the positive control in its own run dir
contract "$T3" true
run_bin "$T3" preflight "$REQ" --repo . --branch main
rc=$?
RD3="$(last_run_dir)"
[ "$rc" -eq 0 ] && ok "(AC2r) real executor, cmd true → exit 0" || no "(AC2r) cmd true: exit $rc stderr=$(cat "$LAST_ERR")"
[ "$(tail -1 "$LAST_OUT")" = "run_dir=$RD3" ] && ok "(AC2r) run_dir=<path> is the LAST stdout line" || no "(AC2r) last stdout line: $(tail -1 "$LAST_OUT")"
l2="$(sed -n 2p "$RD3/evidence.jsonl" | jq -r '[.event, .step, .outcome] | join("|")')"
[ "$l2" = "env|non_prod_assert|pass" ] && ok "(AC2r) env pass line recorded" || no "(AC2r) line 2 is '$l2'"
rs="$(sed -n 1p "$RD3/evidence.jsonl")"
[ "$(printf '%s' "$rs" | jq -r '.ticket_kind')" = "requirement" ] && [ "$(printf '%s' "$rs" | jq -r '.branch')" = "main" ] \
  && [ "$(printf '%s' "$rs" | jq -r '.head_sha | length')" -eq 40 ] \
  && [ "$(printf '%s' "$rs" | jq -r '.env_contract_hash | length')" -eq 64 ] \
  && ok "(AC2r) run_start carries ticket_kind/branch/40-char head_sha/64-char env_contract_hash" \
  || no "(AC2r) run_start line: $rs"
[ "$(jq -r '.acs | length' "$RD3/acs.json" 2>/dev/null)" = "3" ] && ok "(AC2r) acs.json written with 3 entries" || no "(AC2r) acs.json: $(cat "$RD3/acs.json" 2>/dev/null)"
[ -f "$RD3/diff.stat" ] && ok "(AC2r) diff.stat exists (advisory; may be empty)" || no "(AC2r) diff.stat missing"
[ -f "$RD3/summary.md" ] && grep -q '^PASS: 0 · FAIL: 0 · BLOCKED: 0 · NOT_VERIFIABLE: 0 · total: 0$' "$RD3/summary.md" \
  && ok "(AC2r) summary.md derived with an all-zero counts row" || no "(AC2r) summary.md counts row: $(grep '^PASS: ' "$RD3/summary.md" 2>/dev/null)"

# ============================================================================
echo "== (AC6) acs → ordinal ac_ids, checkbox/label stripped, ticket_kind by path, ticket_unresolved =="
run_bin "$T1" acs "$REQ"
rc=$?
n="$(jq -r '.acs | length' "$LAST_OUT" 2>/dev/null)"
ids="$(jq -r '[.acs[].ac_id] | join(",")' "$LAST_OUT" 2>/dev/null)"
[ "$rc" -eq 0 ] && [ "$n" = "3" ] && [ "$ids" = "AC1,AC2,AC3" ] && ok "(AC6) requirement: 3 entries, ids AC1,AC2,AC3" || no "(AC6) requirement: rc=$rc n=$n ids=$ids out=$(cat "$LAST_OUT")"
[ "$(jq -r '.ticket_kind' "$LAST_OUT")" = "requirement" ] && ok "(AC6) ticket_kind requirement for a .supervisor/requirements/ path" || no "(AC6) ticket_kind: $(jq -r '.ticket_kind' "$LAST_OUT")"
t2="$(jq -r '.acs[1].text' "$LAST_OUT")"
case "$t2" in
  *'shows `hello` in the echo paragraph.') ok "(AC6) a wrapped bullet is folded into one text" ;;
  *) no "(AC6) wrapped bullet not folded: '$t2'" ;;
esac
[ "$(jq -r '.acs[0].text' "$LAST_OUT")" = "Given the form page, when it loads, then a Value field and a Submit button are visible." ] \
  && ok "(AC6) requirement bullet text is verbatim (no leading '- ')" || no "(AC6) AC1 text: $(jq -r '.acs[0].text' "$LAST_OUT")"
[ "$(jq -r '.acs | length' "$LAST_OUT")" = "3" ] && ! jq -r '.acs[].text' "$LAST_OUT" | grep -q 'NOT an acceptance criterion' \
  && ok "(AC6) extraction stops at the next ## header" || no "(AC6) a bullet from a later section leaked in"

run_bin "$T1" acs "$BRIEF"
rc=$?
n="$(jq -r '.acs | length' "$LAST_OUT" 2>/dev/null)"
[ "$rc" -eq 0 ] && [ "$n" = "2" ] && [ "$(jq -r '[.acs[].ac_id] | join(",")' "$LAST_OUT")" = "AC1,AC2" ] && ok "(AC6) brief: 2 entries, ids AC1,AC2" || no "(AC6) brief: rc=$rc n=$n out=$(cat "$LAST_OUT")"
[ "$(jq -r '.ticket_kind' "$LAST_OUT")" = "brief" ] && ok "(AC6) ticket_kind brief for a .supervisor/jobs/ path" || no "(AC6) ticket_kind: $(jq -r '.ticket_kind' "$LAST_OUT")"
[ "$(jq -r '.acs[0].text' "$LAST_OUT")" = "Given the form page, when it loads, then the field is visible." ] \
  && ok "(AC6) '- [ ] AC1 ' checkbox + label stripped" || no "(AC6) AC1 text: $(jq -r '.acs[0].text' "$LAST_OUT")"
[ "$(jq -r '.acs[1].text' "$LAST_OUT")" = 'Given `hello`, when submitted, then the echo shows `hello`.' ] \
  && ok "(AC6) '- [x] AC2: ' checkbox + label + colon stripped" || no "(AC6) AC2 text: $(jq -r '.acs[1].text' "$LAST_OUT")"

run_bin "$T1" acs README.md
rc=$?
[ "$rc" -eq 2 ] && grep -qF '[ticket_unresolved]' "$LAST_ERR" && [ ! -s "$LAST_OUT" ] && ok "(AC6) README.md → exit 2 [ticket_unresolved], empty stdout" || no "(AC6) README path: rc=$rc err=$(cat "$LAST_ERR")"
run_bin "$T1" acs .supervisor/requirements/verify-walkthrough/99-no-header.md
rc=$?
[ "$rc" -eq 2 ] && grep -qF '[ticket_unresolved]' "$LAST_ERR" && ok "(AC6) a ticket with no '## Acceptance Criteria' header → exit 2 [ticket_unresolved]" || no "(AC6) header-less: rc=$rc err=$(cat "$LAST_ERR")"
run_bin "$T1" acs .supervisor/requirements/verify-walkthrough/does-not-exist.md
rc=$?
[ "$rc" -eq 2 ] && grep -qF '[ticket_unresolved]' "$LAST_ERR" && ok "(AC6) a missing ticket file → exit 2 [ticket_unresolved]" || no "(AC6) missing file: rc=$rc"
run_bin "$T1" preflight .supervisor/requirements/verify-walkthrough/99-no-header.md --repo .
rc=$?
[ "$rc" -eq 2 ] && [ ! -e "$T1/repo/.supervisor/verify" ] && [ "$(calls_count "$T1")" -eq 0 ] \
  && ok "(AC6) preflight on an unresolvable ticket → exit 2, nothing created, nothing called" || no "(AC6) preflight unresolvable: rc=$rc"

# ============================================================================
echo "== (AC5s) verdict → NOT_VERIFIABLE appended; PASS/FAIL refused; PASS count unaffected =="
# RD3 is the AC2r positive-control run (3 ACs, env pass). Two OBSERVED PASS lines are appended the
# way walk's ingest does — through evidence-append, the store's only writer — never through verdict.
RUN_ID3="$(sed -n 1p "$RD3/evidence.jsonl" | jq -r '.run_id')"
for id in AC1 AC2; do
  jq -cn --arg run_id "$RUN_ID3" --arg id "$id" --arg text "$(jq -r --arg id "$id" '.acs[] | select(.ac_id == $id) | .text' "$RD3/acs.json")" \
    '{schema_version: 1, ts: "2026-09-14T10:00:00Z", run_id: $run_id, event: "ac", ac_id: $id, text: $text,
      scope: "ticket", verdict: "PASS", classification: null, steps: ["open /"], artifacts: ["artifacts/\($id)/then.png"]}' \
    | bash "$T3/bin/verify-helpers.sh" evidence-append "$RD3" - >/dev/null 2>&1 || no "(AC5s) fixture PASS line for $id was refused"
done
: > "$T3/calls.log"
run_bin "$T3" verdict "$RD3" AC3 NOT_VERIFIABLE --reason "load/concurrency claim not observable through the UI"
rc=$?
last="$(tail -1 "$RD3/evidence.jsonl")"
[ "$rc" -eq 0 ] && ok "(AC5s) verdict NOT_VERIFIABLE → exit 0" || no "(AC5s) verdict NOT_VERIFIABLE: rc=$rc err=$(cat "$LAST_ERR")"
[ "$(printf '%s' "$last" | jq -r '[.event, .ac_id, .verdict, .scope] | join("|")')" = "ac|AC3|NOT_VERIFIABLE|ticket" ] \
  && ok "(AC5s) the appended line is ac/AC3/NOT_VERIFIABLE/ticket" || no "(AC5s) last line: $last"
[ "$(printf '%s' "$last" | jq -r 'if has("classification") and .classification == null then "null" else "other" end')" = "null" ] \
  && ok "(AC5s) classification is PRESENT and null" || no "(AC5s) classification: $(printf '%s' "$last" | jq -c '.classification')"
[ "$(printf '%s' "$last" | jq -r '.reason')" = "load/concurrency claim not observable through the UI" ] && ok "(AC5s) reason verbatim" || no "(AC5s) reason: $(printf '%s' "$last" | jq -r '.reason')"
[ "$(printf '%s' "$last" | jq -r '.text')" = "$(jq -r '.acs[2].text' "$RD3/acs.json")" ] && ok "(AC5s) text taken from acs.json by ac_id" || no "(AC5s) text: $(printf '%s' "$last" | jq -r '.text')"
[ "$(printf '%s' "$last" | jq -c '[.steps, .artifacts]')" = "[[],[]]" ] && ok "(AC5s) steps and artifacts are empty arrays" || no "(AC5s) steps/artifacts: $(printf '%s' "$last" | jq -c '[.steps, .artifacts]')"
[ "$(calls_count "$T3")" -eq 0 ] && ! grep -qi 'playwright' "$T3/calls.log" && ok "(AC5s) no executor call and no playwright invocation for a browser-less verdict" || no "(AC5s) calls: $(cat "$T3/calls.log")"
grep -q '^PASS: 2 · FAIL: 0 · BLOCKED: 0 · NOT_VERIFIABLE: 1 · total: 3$' "$RD3/summary.md" \
  && ok "(AC5s) counts row: PASS: 2 · FAIL: 0 · BLOCKED: 0 · NOT_VERIFIABLE: 1 · total: 3 (PASS unaffected)" || no "(AC5s) counts row: $(grep '^PASS: ' "$RD3/summary.md")"

before="$(ev_lines "$RD3")"
run_bin "$T3" verdict "$RD3" AC1 PASS --reason "looked fine"
rc=$?
[ "$rc" -eq 2 ] && grep -qF '[pass_requires_observation]' "$LAST_ERR" && ok "(AC5s) verdict PASS → REFUSED exit 2 [pass_requires_observation]" || no "(AC5s) verdict PASS: rc=$rc err=$(cat "$LAST_ERR")"
run_bin "$T3" verdict "$RD3" AC1 FAIL --reason "looked broken" --classification REAL_BUG
rc=$?
[ "$rc" -eq 2 ] && grep -qF '[fail_requires_observation]' "$LAST_ERR" && ok "(AC5s) verdict FAIL → REFUSED exit 2 [fail_requires_observation]" || no "(AC5s) verdict FAIL: rc=$rc err=$(cat "$LAST_ERR")"
run_bin "$T3" verdict "$RD3" AC9 NOT_VERIFIABLE --reason "no such criterion"
rc=$?
[ "$rc" -eq 2 ] && grep -qF '[ac_id_unknown]' "$LAST_ERR" && ok "(AC5s) an ac_id not in acs.json → exit 2 [ac_id_unknown]" || no "(AC5s) unknown ac_id: rc=$rc err=$(cat "$LAST_ERR")"
run_bin "$T3" verdict "$RD3" AC3 NOT_VERIFIABLE
rc=$?
[ "$rc" -eq 2 ] && grep -qF '[reason_required]' "$LAST_ERR" && ok "(AC5s) a non-PASS verdict without --reason → exit 2 [reason_required]" || no "(AC5s) no reason: rc=$rc err=$(cat "$LAST_ERR")"
run_bin "$T3" verdict "$RD3" AC3 NOT_VERIFIABLE --reason x --classification REAL_BUG
rc=$?
[ "$rc" -eq 2 ] && grep -qF '[classification_not_allowed]' "$LAST_ERR" && ok "(AC5s) NOT_VERIFIABLE with a classification → exit 2 [classification_not_allowed]" || no "(AC5s) NV+class: rc=$rc"
[ "$(ev_lines "$RD3")" -eq "$before" ] && ok "(AC5s) every refusal left the store byte-count unchanged ($before lines)" || no "(AC5s) refusals changed the store: $before → $(ev_lines "$RD3")"
run_bin "$T3" verdict "$RD3" AC2 BLOCKED --reason "login wall — storage state absent"
rc=$?
last="$(tail -1 "$RD3/evidence.jsonl")"
[ "$rc" -eq 0 ] && [ "$(printf '%s' "$last" | jq -r '[.verdict, .classification] | join("|")')" = "BLOCKED|ENVIRONMENT_ISSUE" ] \
  && ok "(AC5s) verdict BLOCKED defaults classification ENVIRONMENT_ISSUE" || no "(AC5s) BLOCKED: rc=$rc last=$last"
grep -q '^PASS: 1 · FAIL: 0 · BLOCKED: 1 · NOT_VERIFIABLE: 1 · total: 3$' "$RD3/summary.md" \
  && ok "(AC5s) latest-per-ac_id: AC2's BLOCKED supersedes its PASS in the derived counts" || no "(AC5s) counts after BLOCKED: $(grep '^PASS: ' "$RD3/summary.md")"
run_bin "$T3" verdict "$RD3" AC2 BLOCKED --reason x --classification BOGUS
rc=$?
[ "$rc" -eq 2 ] && grep -qF '[classification_unknown]' "$LAST_ERR" && ok "(AC5s) an out-of-enum classification → exit 2 [classification_unknown]" || no "(AC5s) bogus class: rc=$rc"

# ============================================================================
echo "== (FIN) finish → run_end without counts, counts row printed; --status validated =="
run_bin "$T3" finish "$RD3"
rc=$?
last="$(tail -1 "$RD3/evidence.jsonl")"
[ "$rc" -eq 0 ] && ok "(FIN) finish → exit 0" || no "(FIN) finish: rc=$rc err=$(cat "$LAST_ERR")"
[ "$(printf '%s' "$last" | jq -r '[.event, .status] | join("|")')" = "run_end|completed" ] && ok "(FIN) run_end/completed appended" || no "(FIN) last line: $last"
[ "$(printf '%s' "$last" | jq -r '[.. | objects | (has("counts") or has("totals"))] | any')" = "false" ] && ok "(FIN) run_end carries NO counts/totals key" || no "(FIN) run_end carries counts: $last"
[ "$(cat "$LAST_OUT")" = "PASS: 1 · FAIL: 0 · BLOCKED: 1 · NOT_VERIFIABLE: 1 · total: 3" ] && ok "(FIN) stdout is exactly the derived counts row" || no "(FIN) stdout: $(cat "$LAST_OUT")"
[ "$(cat "$LAST_OUT")" = "$(grep '^PASS: ' "$RD3/summary.md")" ] && ok "(FIN) the printed row IS summary.md's row (the agent copies it, never tallies)" || no "(FIN) printed row differs from summary.md"
python3 "$T3/bin/validate-verify-evidence.py" "$RD3/evidence.jsonl" >/dev/null 2>&1 && ok "(FIN) the whole store re-validates in file mode" || no "(FIN) store does not re-validate: $(python3 "$T3/bin/validate-verify-evidence.py" "$RD3/evidence.jsonl" 2>&1)"
run_bin "$T3" finish "$RD2" --status aborted
rc=$?
[ "$rc" -eq 0 ] && [ "$(tail -1 "$RD2/evidence.jsonl" | jq -r '.status')" = "aborted" ] && ok "(FIN) --status aborted accepted and recorded" || no "(FIN) --status aborted: rc=$rc"
before="$(ev_lines "$RD2")"
run_bin "$T3" finish "$RD2" --status green
rc=$?
[ "$rc" -eq 2 ] && [ "$(ev_lines "$RD2")" -eq "$before" ] && ok "(FIN) --status green → usage exit 2, nothing appended" || no "(FIN) bogus status: rc=$rc"
run_bin "$T3" finish "$T3/repo/.supervisor/verify/no-such-run"
rc=$?
[ "$rc" -eq 2 ] && grep -qF '[run_dir_missing]' "$LAST_ERR" && ok "(FIN) a missing run dir → exit 2 [run_dir_missing]" || no "(FIN) missing run dir: rc=$rc"

# ============================================================================
echo "== (RUN) two preflights in the same second get different run dirs =="
T4="$(mktmp)"; stage "$T4"; contract "$T4" true
run_bin "$T4" preflight "$REQ" --repo .; rcA=$?; RDA="$(last_run_dir)"
run_bin "$T4" preflight "$REQ" --repo .; rcB=$?; RDB="$(last_run_dir)"
[ "$rcA" -eq 0 ] && [ "$rcB" -eq 0 ] && [ -n "$RDA" ] && [ "$RDA" != "$RDB" ] && ok "(RUN) back-to-back preflights → distinct run dirs" || no "(RUN) rcA=$rcA rcB=$rcB A=$RDA B=$RDB"
[ "$(ev_lines "$RDA")" -eq 2 ] && [ "$(ev_lines "$RDB")" -eq 2 ] && ok "(RUN) each store holds exactly its own two lines (no merge)" || no "(RUN) A=$(ev_lines "$RDA") B=$(ev_lines "$RDB") lines"
[ "$(calls_count "$T4")" -eq 2 ] && ok "(RUN) exactly one assert-non-prod call per preflight" || no "(RUN) calls: $(cat "$T4/calls.log")"

# ============================================================================
echo "== (S) static shape of verify-run.sh =="
bash -n "$RUNNER" 2>"$LAST_ERR" && ok "(S) bash -n" || no "(S) bash -n: $(cat "$LAST_ERR")"
bash "$RUNNER" --help > "$LAST_OUT" 2>&1
for sub in acs preflight walk verdict finish; do
  grep -qE "^  $sub " "$LAST_OUT" && ok "(S) --help lists $sub" || no "(S) --help does not list $sub"
done
writes="$(grep -cE '>>?[[:space:]]*"?\$[A-Za-z_{}]*/?evidence\.jsonl|evidence\.jsonl"?[[:space:]]*<' "$RUNNER")"
[ "$writes" -eq 0 ] && ok "(S) verify-run.sh never redirects into evidence.jsonl (only evidence-append writes)" || no "(S) $writes direct evidence.jsonl write(s) in verify-run.sh"
[ "$(grep -c 'evidence-append' "$RUNNER")" -ge 4 ] && ok "(S) every recorded line goes through verify-helpers.sh evidence-append" || no "(S) too few evidence-append call sites"
[ "$(grep -cE 'Claude_Browser|computer-use|mcp__' "$RUNNER")" -eq 0 ] && ok "(S) no browser-harness product token in verify-run.sh (Playwright-from-Bash only)" || no "(S) a browser-harness product token appears in verify-run.sh"
[ "$(grep -cE 'CLAUDE_PLUGIN_ROOT|\.claude/plugins' "$RUNNER")" -eq 0 ] && ok "(S) vendor-neutral: siblings located relative to the script" || no "(S) a harness install path appears in verify-run.sh"
grep -q '^## VERIFY_RESULT$' "$HERE/../docs/RESULT_SCHEMAS.md" && ok "(S) docs/RESULT_SCHEMAS.md carries ## VERIFY_RESULT" || no "(S) ## VERIFY_RESULT missing from RESULT_SCHEMAS.md"
n_evd="$(grep -n '^## VERIFY_EVIDENCE$' "$HERE/../docs/RESULT_SCHEMAS.md" | cut -d: -f1 | head -1)"
n_res="$(grep -n '^## VERIFY_RESULT$' "$HERE/../docs/RESULT_SCHEMAS.md" | cut -d: -f1 | head -1)"
n_loc="$(grep -n '^## Validation Location$' "$HERE/../docs/RESULT_SCHEMAS.md" | cut -d: -f1 | head -1)"
if [ -n "$n_evd" ] && [ -n "$n_res" ] && [ -n "$n_loc" ] && [ "$n_evd" -lt "$n_res" ] && [ "$n_res" -lt "$n_loc" ]; then
  ok "(S) ## VERIFY_RESULT sits after ## VERIFY_EVIDENCE and before ## Validation Location"
else
  no "(S) section placement: VERIFY_EVIDENCE=$n_evd VERIFY_RESULT=$n_res Validation Location=$n_loc"
fi

# --- browser arms (Subtask 2 appends below this line) ---

# --- prompt-surface arms (Subtask 3 appends below this line) ---

# ============================================================================
echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
