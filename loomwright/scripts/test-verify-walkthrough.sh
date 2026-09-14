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
# The first half is static: no network, no `gh`, no Docker, no browser. The browser arms (below the
# Subtask 2 anchor) obtain `@playwright/test` + chromium into a persistent cache and drive the
# fixture app for real — see their own header for the bimodal $CI install rule. Exit 0 = all pass,
# 1 = any failure (auto-registered by ci.yml's `loomwright/scripts/test-*.sh` glob).
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

# contract <T> <cmd> [<base_url>] — write a well-formed .agent/verify.json whose non_prod_assert.cmd
# is <cmd> (base_url defaults to localhost:3000; the browser arms point it at the fixture app).
contract() {
  mkdir -p "$1/repo/.agent"
  jq -n --arg cmd "$2" --arg url "${3:-http://localhost:3000}" '{start: null, base_url: $url, health: "/",
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
# Vendor-neutral core: no plugin-root variable of any vendor (`*_PLUGIN_ROOT`) and no harness install
# path (`/plugins/`) — the pattern is generic on purpose, so this line itself carries no vendor token
# for the root ratchet (scripts/check-vendor-coupling.sh) to count.
[ "$(grep -cE '_PLUGIN_ROOT|/plugins/' "$RUNNER")" -eq 0 ] && grep -q '^HERE="\$(cd "\$(dirname "\$0")" && pwd)"$' "$RUNNER" \
  && ok "(S) vendor-neutral: siblings located relative to the script, no plugin-root variable" || no "(S) a plugin-root variable / harness install path appears in verify-run.sh, or HERE is not dirname-relative"
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

# ============================================================================
# Browser arms (Subtask 2). They need `@playwright/test` + chromium, which this repo does NOT ship:
# they are obtained ONCE into a persistent cache (idempotent — a present install is a no-op) and
# the fixture repo's `node_modules` is SYMLINKED to it, so `npx --no-install playwright` resolves
# from the repo exactly as it would in a user project. Acquisition failure is bimodal by design
# (AC11): under $CI it is a HARD failure — `no()` with reason playwright_install_failed, never a
# vacuous green — outside $CI the two browser arms SKIP with the printed reason and every other
# arm still runs and decides the exit. The fixture app is verify-fixture-app.py (stdlib http.server)
# on a free port, killed in the trap; `--broken` is the mutation control.
#
#   (AC11i) install rule      → this very suite re-run in a sandbox where npm cannot install: with
#                                CI set it exits 1 naming playwright_install_failed; with CI unset it
#                                prints SKIP (playwright_install_failed…) and exits 0 (all other arms
#                                green) — the bimodal rule proven, not described
#   (AC11)  harness absent    → `walk` with npx shadowed by a PATH stub exiting 127 ⇒ a BLOCKED
#                                [playwright_unavailable] ENVIRONMENT_ISSUE line for EVERY AC, exit 3,
#                                no config / report written, no executor call
#   (AC3)   healthy app       → the two template specs PASS: EXACTLY two ac lines, each with a .png
#                                artifact that EXISTS under <run_dir>/, counts row
#                                PASS: 2 · FAIL: 0 · BLOCKED: 0 · NOT_VERIFIABLE: 0 · total: 2
#   (AC4)   mutation control  → gate: the --broken server's /submit really differs from the healthy
#                                one (else UNPROVEN = no()); then the SAME specs on a fresh run dir:
#                                AC2 FAIL / REAL_BUG / non-empty ANSI-free reason / .html + .png
#                                artifacts, AC1 still PASS, PASS: 1 · FAIL: 1 · … · total: 2
#   (NS)    no_spec           → an AC with a spec and one decided by `verdict` are left alone; an AC
#                                with neither ⇒ BLOCKED [no_spec]; a run with NO specs at all launches
#                                no browser (no report.json) and BLOCKs every AC [no_spec], exit 0

FIXTURE_APP="$HERE/verify-fixture-app.py"
PW_CACHE="${LOOMWRIGHT_VERIFY_TEST_CACHE:-${TMPDIR:-/tmp}/loomwright-verify-walkthrough}"
export PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-$PW_CACHE/browsers}"
PW_READY=0; PW_SKIP=""
SERVER_PIDS=""
kill_servers() { local p; for p in $SERVER_PIDS; do kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; done; return 0; }
trap 'kill_servers; rm -rf "$ROOT" 2>/dev/null' EXIT

free_port() {
  python3 -c 'import socket
s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()' 2>/dev/null
}

# start_app <port> [--broken] — the fixture app in the background; waits (≤5s) for /health.
start_app() {
  local port="$1" flag="${2:-}" i=0
  # shellcheck disable=SC2086
  python3 "$FIXTURE_APP" --port "$port" $flag >/dev/null 2>&1 &
  SERVER_PIDS="$SERVER_PIDS $!"
  while [ "$i" -lt 50 ]; do
    curl -sf "http://127.0.0.1:$port/health" >/dev/null 2>&1 && return 0
    sleep 0.1; i=$((i+1))
  done
  return 1
}

# acquire_playwright — idempotent; sets PW_READY=1 or PW_SKIP=<reason>. The cache holds
# node_modules/@playwright/test (npm i --prefix) and browsers/ (PLAYWRIGHT_BROWSERS_PATH);
# `--with-deps` (apt, needs the runner's sudo) only under $CI.
acquire_playwright() {
  local log="$ROOT/pw-install.log" tool
  for tool in node npm npx curl; do
    command -v "$tool" >/dev/null 2>&1 || { PW_SKIP="$tool is not on PATH"; return 1; }
  done
  [ -f "$FIXTURE_APP" ] || { PW_SKIP="fixture app missing at $FIXTURE_APP"; return 1; }
  mkdir -p "$PW_CACHE" 2>/dev/null || { PW_SKIP="cannot create $PW_CACHE"; return 1; }
  if [ ! -d "$PW_CACHE/node_modules/@playwright/test" ]; then
    npm i --prefix "$PW_CACHE" --no-audit --no-fund @playwright/test@1 >"$log" 2>&1 \
      || { PW_SKIP="npm i @playwright/test@1 into $PW_CACHE failed: $(tail -1 "$log" 2>/dev/null)"; return 1; }
  fi
  [ -x "$PW_CACHE/node_modules/.bin/playwright" ] || { PW_SKIP="no playwright bin under $PW_CACHE/node_modules/.bin"; return 1; }
  # shellcheck disable=SC2086 — ${CI:+--with-deps} is deliberately unquoted: empty ⇒ no argument
  "$PW_CACHE/node_modules/.bin/playwright" install ${CI:+--with-deps} chromium >"$log" 2>&1 \
    || { PW_SKIP="playwright install chromium into $PLAYWRIGHT_BROWSERS_PATH failed: $(tail -1 "$log" 2>/dev/null)"; return 1; }
  PW_READY=1
  return 0
}

# write_specs <dir> — the two agent-authored-style specs in EXACTLY the shape the skill's template
# prescribes (title `[ACn] …`, role-based locators, the afterEach page-body attach on any unexpected
# status, the non-2xx response attach), so the ingest contract is exercised end-to-end.
write_specs() {
  mkdir -p "$1"
  cat > "$1/AC1.spec.ts" <<'SPEC'
import { test, expect } from '@playwright/test';

test.beforeEach(async ({ page }, testInfo) => {
  page.on('response', async (response) => {
    const status = response.status();
    if (status < 200 || status >= 300) {
      let body = '';
      try { body = await response.text(); } catch (e) { body = ''; }
      try { await testInfo.attach(`response-${status}`, { body, contentType: 'text/plain' }); } catch (e) { /* test already over */ }
    }
  });
});

test.afterEach(async ({ page }, testInfo) => {
  if (testInfo.status !== testInfo.expectedStatus)
    await testInfo.attach('page-body', { body: await page.content(), contentType: 'text/html' });
});

test('[AC1] Given the form page, when it loads, then a Value field and Submit button are visible', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByLabel('Value')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Submit' })).toBeVisible();
});
SPEC
  cat > "$1/AC2.spec.ts" <<'SPEC'
import { test, expect } from '@playwright/test';

test.beforeEach(async ({ page }, testInfo) => {
  page.on('response', async (response) => {
    const status = response.status();
    if (status < 200 || status >= 300) {
      let body = '';
      try { body = await response.text(); } catch (e) { body = ''; }
      try { await testInfo.attach(`response-${status}`, { body, contentType: 'text/plain' }); } catch (e) { /* test already over */ }
    }
  });
});

test.afterEach(async ({ page }, testInfo) => {
  if (testInfo.status !== testInfo.expectedStatus)
    await testInfo.attach('page-body', { body: await page.content(), contentType: 'text/html' });
});

test('[AC2] Given the Value field, when hello is submitted, then the echo paragraph shows hello', async ({ page }) => {
  await page.goto('/');
  await page.getByLabel('Value').fill('hello');
  await page.getByRole('button', { name: 'Submit' }).click();
  await expect(page.locator('#echo')).toHaveText('hello');
});
SPEC
}

# stage_browser <T> <base_url> — stage() + a passing contract pointing at <base_url> + the
# node_modules symlink into the cache; leaves a preflighted run dir in RD_B (2-AC brief ticket).
stage_browser() {
  local T="$1"
  stage "$T"; contract "$T" true "$2"
  ln -s "$PW_CACHE/node_modules" "$T/repo/node_modules"
  run_bin "$T" preflight "$BRIEF" --repo .
  RD_B="$(last_run_dir)"
}
ac_lines() { ev_field "$1" 'select(.event == "ac") | .ac_id' | grep -c .; }
ac_get() { jq -r --arg id "$2" "select(.event == \"ac\" and .ac_id == \$id) | $3" "$1/evidence.jsonl" 2>/dev/null | tail -1; }   # <run_dir> <ac_id> <jq> — the LATEST line for that id
ESC="$(printf '\033')"
NL="$(printf '\nx')"; NL="${NL%x}"   # a bare $(printf '\n') is EMPTY (trailing newlines are stripped) — and *""* matches everything

# ============================================================================
echo "== (AC11i) the install rule is bimodal: CI ⇒ exit 1 playwright_install_failed; no CI ⇒ SKIP + exit 0 =="
# The suite itself, re-run in a sandbox where nothing can be installed: an empty cache dir under
# $ROOT and a PATH-first `npm` that fails. Guarded against recursion by LOOMWRIGHT_VERIFY_TEST_INNER.
if [ -z "${LOOMWRIGHT_VERIFY_TEST_INNER:-}" ]; then
  SB="$(mktmp)"; mkdir -p "$SB/bin" "$SB/cache"
  printf '#!/bin/sh\necho "npm: sandboxed — install refused" >&2\nexit 1\n' > "$SB/bin/npm"; chmod +x "$SB/bin/npm"
  ( cd "$SB" && env CI=1 LOOMWRIGHT_VERIFY_TEST_INNER=1 LOOMWRIGHT_VERIFY_TEST_CACHE="$SB/cache" PATH="$SB/bin:$PATH" \
      bash "$HERE/test-verify-walkthrough.sh" ) > "$SB/ci.out" 2>&1
  rc=$?
  [ "$rc" -eq 1 ] && grep -qF 'FAIL: (AC11) playwright_install_failed' "$SB/ci.out" \
    && ok "(AC11i) under CI an install failure is a HARD failure: exit 1, reason playwright_install_failed" \
    || no "(AC11i) under CI: rc=$rc (expected 1); tail: $(tail -3 "$SB/ci.out")"
  ! grep -qE '^  (ok|FAIL): \(AC3\)' "$SB/ci.out" && ok "(AC11i) under CI no browser arm ran on a failed install (no vacuous green)" || no "(AC11i) a browser arm ran without Playwright"
  ( cd "$SB" && env -u CI LOOMWRIGHT_VERIFY_TEST_INNER=1 LOOMWRIGHT_VERIFY_TEST_CACHE="$SB/cache" PATH="$SB/bin:$PATH" \
      bash "$HERE/test-verify-walkthrough.sh" ) > "$SB/local.out" 2>&1
  rc=$?
  [ "$rc" -eq 0 ] && grep -qF 'SKIP (playwright_install_failed' "$SB/local.out" \
    && ok "(AC11i) outside CI the same failure prints SKIP (playwright_install_failed: …) and the other arms decide: exit 0" \
    || no "(AC11i) outside CI: rc=$rc (expected 0); tail: $(tail -3 "$SB/local.out")"
  grep -qE '^  ok: \(AC11\) .*playwright_unavailable' "$SB/local.out" && grep -qE '^  ok: \(FIN\)' "$SB/local.out" \
    && ok "(AC11i) outside CI the non-browser arms (AC11 stub, FIN, …) still ran" || no "(AC11i) non-browser arms did not run in the SKIP mode"
else
  echo "  (inner run — the install-rule self-check is not recursed)"
fi

# ============================================================================
echo "== (AC11) walk with npx unresolvable → BLOCKED playwright_unavailable for every AC, exit 3 =="
T5="$(mktmp)"; stage "$T5"; contract "$T5" true
mkdir -p "$T5/stubbin"; printf '#!/bin/sh\nexit 127\n' > "$T5/stubbin/npx"; chmod +x "$T5/stubbin/npx"
run_bin "$T5" preflight "$REQ" --repo .
RD5="$(last_run_dir)"
[ -n "$RD5" ] && [ -d "$RD5" ] || no "(AC11) preflight fixture failed: $(cat "$LAST_ERR")"
PATH="$T5/stubbin:$PATH" run_bin "$T5" walk "$RD5" --repo .
rc=$?
[ "$rc" -eq 3 ] && ok "(AC11) walk → exit 3" || no "(AC11) walk: rc=$rc (expected 3) err=$(cat "$LAST_ERR")"
grep -qF '[playwright_unavailable]' "$LAST_ERR" && ok "(AC11) stderr names [playwright_unavailable]" || no "(AC11) stderr: $(cat "$LAST_ERR")"
[ "$(ac_lines "$RD5")" -eq 3 ] && ok "(AC11) one ac line per AC (3)" || no "(AC11) $(ac_lines "$RD5") ac lines"
[ "$(ev_field "$RD5" 'select(.event == "ac") | [.verdict, .classification, .reason] | join("|")' | sort -u)" = "BLOCKED|ENVIRONMENT_ISSUE|playwright_unavailable" ] \
  && ok "(AC11) every line is BLOCKED / ENVIRONMENT_ISSUE / playwright_unavailable" || no "(AC11) lines: $(ev_field "$RD5" 'select(.event == "ac") | [.ac_id, .verdict, .classification, .reason] | join("|")')"
[ "$(ev_field "$RD5" 'select(.event == "ac") | .ac_id' | tr '\n' ',')" = "AC1,AC2,AC3," ] && ok "(AC11) in acs.json order AC1,AC2,AC3" || no "(AC11) order: $(ev_field "$RD5" 'select(.event == "ac") | .ac_id' | tr '\n' ',')"
[ ! -e "$RD5/playwright.config.mjs" ] && [ ! -e "$RD5/report.json" ] && ok "(AC11) no config and no report written — the harness was never reached" || no "(AC11) config/report written despite no harness"
[ "$(calls_count "$T5")" -eq 1 ] && ok "(AC11) walk made no executor call (call log still the one assert-non-prod)" || no "(AC11) calls: $(cat "$T5/calls.log")"
grep -q '^PASS: 0 · FAIL: 0 · BLOCKED: 3 · NOT_VERIFIABLE: 0 · total: 3$' "$RD5/summary.md" && ok "(AC11) counts row BLOCKED: 3 · total: 3" || no "(AC11) counts row: $(grep '^PASS: ' "$RD5/summary.md")"
python3 "$T5/bin/validate-verify-evidence.py" "$RD5/evidence.jsonl" >/dev/null 2>&1 && ok "(AC11) the store re-validates" || no "(AC11) store invalid: $(python3 "$T5/bin/validate-verify-evidence.py" "$RD5/evidence.jsonl" 2>&1)"
run_bin "$T5" walk "$T5/repo/.supervisor/verify/no-such-run" --repo .
rc=$?
[ "$rc" -eq 2 ] && grep -qF '[run_dir_missing]' "$LAST_ERR" && ok "(AC11) walk on a missing run dir → exit 2 [run_dir_missing]" || no "(AC11) missing run dir: rc=$rc"

# ============================================================================
echo "== (PW) obtain @playwright/test + chromium into the test cache (idempotent) =="
if acquire_playwright; then
  ok "(PW) @playwright/test $("$PW_CACHE/node_modules/.bin/playwright" --version 2>/dev/null | tr -d '\n') + chromium under $PW_CACHE"
elif [ -n "${CI:-}" ]; then
  no "(AC11) playwright_install_failed: $PW_SKIP"
else
  echo "  SKIP (playwright_install_failed: $PW_SKIP) — browser arms AC3 / AC4 / NS skipped; the other arms decide the exit"
fi

if [ "$PW_READY" -eq 1 ]; then
  # ==========================================================================
  echo "== (AC3) healthy app: both template specs PASS with .png artifacts, counts 2/0/0/0/2 =="
  PORT_OK="$(free_port)"
  if start_app "$PORT_OK"; then
    T6="$(mktmp)"; stage_browser "$T6" "http://127.0.0.1:$PORT_OK"; RD6="$RD_B"
    write_specs "$RD6/specs"
    run_bin "$T6" walk "$RD6" --repo .
    rc=$?
    [ "$rc" -eq 0 ] && ok "(AC3) walk → exit 0" || no "(AC3) walk: rc=$rc err=$(cat "$LAST_ERR")"
    [ -f "$RD6/playwright.config.mjs" ] && grep -qF "baseURL: \"http://127.0.0.1:$PORT_OK\"" "$RD6/playwright.config.mjs" \
      && ok "(AC3) per-run playwright.config.mjs generated with the contract's base_url" || no "(AC3) config: $(cat "$RD6/playwright.config.mjs" 2>/dev/null)"
    [ -s "$RD6/report.json" ] && jq -e '.stats' "$RD6/report.json" >/dev/null 2>&1 && ok "(AC3) report.json is the JSON reporter's output" || no "(AC3) no reporter output"
    [ "$(ac_lines "$RD6")" -eq 2 ] && ok "(AC3) EXACTLY two ac lines" || no "(AC3) $(ac_lines "$RD6") ac lines: $(ev_field "$RD6" 'select(.event == "ac") | [.ac_id, .verdict, .reason] | join("|")')"
    [ "$(ev_field "$RD6" 'select(.event == "ac") | [.ac_id, .verdict] | join("=")' | tr '\n' ',')" = "AC1=PASS,AC2=PASS," ] \
      && ok "(AC3) AC1 PASS and AC2 PASS" || no "(AC3) verdicts: $(ev_field "$RD6" 'select(.event == "ac") | [.ac_id, .verdict, .reason] | join("|")')"
    for id in AC1 AC2; do
      png="$(ac_get "$RD6" "$id" '.artifacts | map(select(endswith(".png"))) | first // ""')"
      [ -n "$png" ] && [ -f "$RD6/$png" ] && ok "(AC3) $id has a .png artifact that EXISTS under <run_dir>/ ($png)" || no "(AC3) $id .png artifact: '$png' (artifacts: $(ac_get "$RD6" "$id" '.artifacts | join(",")'))"
      case "$png" in /*|../*|*/../*) no "(AC3) $id artifact path is not relative to <run_dir>/: $png" ;; *) ok "(AC3) $id artifact path is relative" ;; esac
    done
    [ "$(ac_get "$RD6" AC1 '.classification')" = "null" ] && ok "(AC3) a PASS carries a null classification" || no "(AC3) AC1 classification: $(ac_get "$RD6" AC1 '.classification')"
    [ "$(ac_get "$RD6" AC1 '.text')" = "$(jq -r '.acs[0].text' "$RD6/acs.json")" ] && ok "(AC3) ac text taken from acs.json by ac_id" || no "(AC3) AC1 text: $(ac_get "$RD6" AC1 '.text')"
    grep -q '^PASS: 2 · FAIL: 0 · BLOCKED: 0 · NOT_VERIFIABLE: 0 · total: 2$' "$RD6/summary.md" \
      && ok "(AC3) counts row PASS: 2 · FAIL: 0 · BLOCKED: 0 · NOT_VERIFIABLE: 0 · total: 2" || no "(AC3) counts row: $(grep '^PASS: ' "$RD6/summary.md")"
    [ "$(calls_count "$T6")" -eq 1 ] && ok "(AC3) walk made no executor call" || no "(AC3) calls: $(cat "$T6/calls.log")"
    python3 "$T6/bin/validate-verify-evidence.py" "$RD6/evidence.jsonl" >/dev/null 2>&1 && ok "(AC3) the store re-validates" || no "(AC3) store invalid: $(python3 "$T6/bin/validate-verify-evidence.py" "$RD6/evidence.jsonl" 2>&1)"
    run_bin "$T6" finish "$RD6"
    rc=$?
    [ "$rc" -eq 0 ] && [ "$(cat "$LAST_OUT")" = "PASS: 2 · FAIL: 0 · BLOCKED: 0 · NOT_VERIFIABLE: 0 · total: 2" ] && ok "(AC3) finish prints the same row (what VERIFY_RESULT.counts copies)" || no "(AC3) finish: rc=$rc out=$(cat "$LAST_OUT")"
  else
    no "(AC3) fixture app did not answer /health on port $PORT_OK"
  fi

  # ==========================================================================
  echo "== (AC4) mutation control: broken form flips PASS to FAIL =="
  PORT_BAD="$(free_port)"
  if start_app "$PORT_BAD" --broken; then
    healthy="$(curl -s -d v=hello "http://127.0.0.1:$PORT_OK/submit")"
    broken="$(curl -s -d v=hello "http://127.0.0.1:$PORT_BAD/submit")"
    gate=0
    case "$healthy" in *'<p id="echo">hello</p>'*) gate=1 ;; esac
    case "$broken" in *hello*) gate=0 ;; *'<p id="echo">wrong</p>'*) : ;; *) gate=0 ;; esac
    if [ "$gate" -eq 1 ]; then
      ok "(AC4) gate: healthy /submit echoes hello; --broken /submit renders wrong (the mutant differs)"
      T7="$(mktmp)"; stage_browser "$T7" "http://127.0.0.1:$PORT_BAD"; RD7="$RD_B"
      write_specs "$RD7/specs"
      run_bin "$T7" walk "$RD7" --repo .
      rc=$?
      [ "$rc" -eq 0 ] && ok "(AC4) walk → exit 0 (the reporter is the oracle; a FAIL is a recorded fact, not a harness error)" || no "(AC4) walk: rc=$rc err=$(cat "$LAST_ERR")"
      [ "$(ac_lines "$RD7")" -eq 2 ] && ok "(AC4) EXACTLY two ac lines" || no "(AC4) $(ac_lines "$RD7") ac lines"
      [ "$(ac_get "$RD7" AC2 '.verdict')" = "FAIL" ] && ok "(AC4) AC2 verdict FAIL — observed, not claimed" || no "(AC4) AC2 verdict: $(ac_get "$RD7" AC2 '.verdict') reason: $(ac_get "$RD7" AC2 '.reason')"
      [ "$(ac_get "$RD7" AC2 '.classification')" = "REAL_BUG" ] && ok "(AC4) AC2 classification REAL_BUG" || no "(AC4) AC2 classification: $(ac_get "$RD7" AC2 '.classification')"
      reason="$(ac_get "$RD7" AC2 '.reason // ""')"
      [ -n "$reason" ] && [ "$reason" != "null" ] && ok "(AC4) AC2 reason non-empty: $reason" || no "(AC4) AC2 reason empty"
      case "$reason" in *"$ESC"*) no "(AC4) reason carries ANSI escapes" ;; *"$NL"*) no "(AC4) reason is more than one line" ;; *) ok "(AC4) reason is ONE ANSI-free line (the first line of Playwright's error)" ;; esac
      case "$reason" in *toHaveText*) ok "(AC4) reason names the contradicted assertion (toHaveText)" ;; *) no "(AC4) reason does not name toHaveText: $reason" ;; esac
      html="$(ac_get "$RD7" AC2 '.artifacts | map(select(endswith(".html"))) | first // ""')"
      png="$(ac_get "$RD7" AC2 '.artifacts | map(select(endswith(".png"))) | first // ""')"
      [ -n "$html" ] && [ -f "$RD7/$html" ] && ok "(AC4) AC2 has a page-body .html artifact that EXISTS ($html)" || no "(AC4) AC2 .html artifact: '$html' (artifacts: $(ac_get "$RD7" AC2 '.artifacts | join(",")'))"
      [ -n "$html" ] && grep -qF '<p id="echo">wrong</p>' "$RD7/$html" 2>/dev/null && ok "(AC4) the .html artifact IS the broken page body (contains wrong)" || no "(AC4) .html artifact does not carry the broken echo"
      [ -n "$png" ] && [ -f "$RD7/$png" ] && ok "(AC4) AC2 has a .png artifact that EXISTS ($png)" || no "(AC4) AC2 .png artifact: '$png'"
      [ "$(ac_get "$RD7" AC1 '.verdict')" = "PASS" ] && ok "(AC4) AC1 stays PASS (the form still renders)" || no "(AC4) AC1 verdict: $(ac_get "$RD7" AC1 '.verdict')"
      grep -q '^PASS: 1 · FAIL: 1 · BLOCKED: 0 · NOT_VERIFIABLE: 0 · total: 2$' "$RD7/summary.md" \
        && ok "(AC4) counts row PASS: 1 · FAIL: 1 · BLOCKED: 0 · NOT_VERIFIABLE: 0 · total: 2" || no "(AC4) counts row: $(grep '^PASS: ' "$RD7/summary.md")"
      python3 "$T7/bin/validate-verify-evidence.py" "$RD7/evidence.jsonl" >/dev/null 2>&1 && ok "(AC4) the store re-validates" || no "(AC4) store invalid: $(python3 "$T7/bin/validate-verify-evidence.py" "$RD7/evidence.jsonl" 2>&1)"
    else
      no "(AC4) UNPROVEN — the --broken server does not differ from the healthy one (healthy: $healthy / broken: $broken); the mutation control cannot prove anything"
    fi
  else
    no "(AC4) --broken fixture app did not answer /health on port $PORT_BAD"
  fi

  # ==========================================================================
  echo "== (NS) no_spec: decided ACs are left alone; an AC with neither spec nor verdict is BLOCKED no_spec =="
  T8="$(mktmp)"; stage "$T8"; contract "$T8" true "http://127.0.0.1:$PORT_OK"
  ln -s "$PW_CACHE/node_modules" "$T8/repo/node_modules"
  run_bin "$T8" preflight "$REQ" --repo .
  RD8="$(last_run_dir)"
  write_specs "$RD8/specs"
  run_bin "$T8" verdict "$RD8" AC3 NOT_VERIFIABLE --reason "load/concurrency claim not observable through the UI"
  run_bin "$T8" walk "$RD8" --repo .
  rc=$?
  [ "$rc" -eq 0 ] && ok "(NS) walk → exit 0" || no "(NS) walk: rc=$rc err=$(cat "$LAST_ERR")"
  [ "$(ac_get "$RD8" AC3 '.verdict')" = "NOT_VERIFIABLE" ] && [ "$(ev_field "$RD8" 'select(.event == "ac" and .ac_id == "AC3") | .verdict' | grep -c .)" -eq 1 ] \
    && ok "(NS) an AC already decided by verdict (AC3 NOT_VERIFIABLE) is left alone — no no_spec line" || no "(NS) AC3 lines: $(ev_field "$RD8" 'select(.event == "ac" and .ac_id == "AC3") | .verdict' | tr '\n' ',')"
  grep -q '^PASS: 2 · FAIL: 0 · BLOCKED: 0 · NOT_VERIFIABLE: 1 · total: 3$' "$RD8/summary.md" \
    && ok "(NS) counts row PASS: 2 · FAIL: 0 · BLOCKED: 0 · NOT_VERIFIABLE: 1 · total: 3 (AC5's row over the AC3 fixture)" || no "(NS) counts row: $(grep '^PASS: ' "$RD8/summary.md")"
  sleep 1
  run_bin "$T8" preflight "$REQ" --repo .
  RD9="$(last_run_dir)"
  write_specs "$RD9/specs"
  run_bin "$T8" walk "$RD9" --repo .
  rc=$?
  [ "$rc" -eq 0 ] && [ "$(ac_get "$RD9" AC3 '[.verdict, .classification, .reason] | join("|")')" = "BLOCKED|ENVIRONMENT_ISSUE|no_spec" ] \
    && ok "(NS) an AC with neither a spec nor a verdict line → BLOCKED / ENVIRONMENT_ISSUE / no_spec" || no "(NS) rc=$rc AC3: $(ac_get "$RD9" AC3 '[.verdict, .classification, .reason] | join("|")')"
  grep -q '^PASS: 2 · FAIL: 0 · BLOCKED: 1 · NOT_VERIFIABLE: 0 · total: 3$' "$RD9/summary.md" && ok "(NS) counts row PASS: 2 · BLOCKED: 1 · total: 3" || no "(NS) counts row: $(grep '^PASS: ' "$RD9/summary.md")"
  sleep 1
  run_bin "$T8" preflight "$REQ" --repo .
  RD10="$(last_run_dir)"
  run_bin "$T8" walk "$RD10" --repo .
  rc=$?
  [ "$rc" -eq 0 ] && [ "$(ev_field "$RD10" 'select(.event == "ac") | [.verdict, .reason] | join("|")' | sort -u)" = "BLOCKED|no_spec" ] && [ "$(ac_lines "$RD10")" -eq 3 ] \
    && ok "(NS) a run with NO specs at all → every AC BLOCKED no_spec, exit 0" || no "(NS) no specs: rc=$rc lines: $(ev_field "$RD10" 'select(.event == "ac") | [.ac_id, .verdict, .reason] | join("|")' | tr '\n' ' ')"
  [ ! -e "$RD10/report.json" ] && [ ! -e "$RD10/playwright.config.mjs" ] && ok "(NS) no browser launched for a spec-less run (no report.json, no config)" || no "(NS) a spec-less run produced a report/config"
fi

# --- prompt-surface arms (Subtask 3 appends below this line) ---

# ============================================================================
echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
