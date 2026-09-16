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
#   (NOTIFY) --notify / notify-enable → `preflight --notify` creates `<run_dir>/.notify-enabled`,
#                                  plain `preflight` does NOT; `notify-enable <run_dir>` creates the
#                                  marker on an existing run (idempotent) and refuses a missing/invalid
#                                  run dir with exit 2 [run_dir_missing]; --help lists notify-enable

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
  # An `auth-probe` invocation is answered separately, per STUB_AUTH (authenticated|anonymous|
  # unreachable, default anonymous) — additive, never reached by any pre-item-04 test (they only ever
  # call assert-non-prod / start / stop through this stub).
  cat > "$T/bin/verify-env.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${STUB_CALLS:?STUB_CALLS unset}"
case "$1" in
  auth-probe)
    case "${STUB_AUTH:-anonymous}" in
      authenticated) echo "authenticated"; exit 0 ;;
      unreachable)   echo "verify-env: probe made no HTTP response [auth_probe_unreachable]" >&2; exit 1 ;;
      *)             echo "anonymous"; exit 0 ;;
    esac
    ;;
esac
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

# contract_auth <T> <method> [<storage_state_path>] [<probe_path>] — like contract() but with an
# `auth.method: storage_state` object (item 04's auth-check arms); non_prod_assert.cmd is always
# "true" since these arms drive the stub executor, never the real one.
contract_auth() {
  mkdir -p "$1/repo/.agent"
  jq -n --arg method "$2" --arg ssp "${3:-ss.json}" --arg probe "${4:-/probe}" \
    '{start: null, base_url: "http://localhost:3000", health: "/",
      auth: {method: $method, storage_state_path: $ssp, probe_path: $probe},
      non_prod_assert: {cmd: "true"}, seed: null, reset: null, stop: null}' > "$1/repo/.agent/verify.json"
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
echo "== (NOTIFY) preflight --notify / notify-enable: .notify-enabled marker =="
TN="$(mktmp)"; stage "$TN"; contract "$TN" true
run_bin "$TN" preflight "$REQ" --repo . --notify
rc=$?
RDN="$(last_run_dir)"
[ "$rc" -eq 0 ] && [ -n "$RDN" ] && [ -f "$RDN/.notify-enabled" ] \
  && ok "(NOTIFY) preflight --notify creates <run_dir>/.notify-enabled" \
  || no "(NOTIFY) preflight --notify: rc=$rc RDN=$RDN exists=$([ -f "$RDN/.notify-enabled" ] && echo yes || echo no)"

sleep 1   # run-id is second-resolution; keep the plain-preflight control in its own run dir
run_bin "$TN" preflight "$REQ" --repo .
rc=$?
RDNB="$(last_run_dir)"
[ "$rc" -eq 0 ] && [ -n "$RDNB" ] && [ ! -f "$RDNB/.notify-enabled" ] \
  && ok "(NOTIFY) plain preflight (no --notify) does NOT create .notify-enabled" \
  || no "(NOTIFY) plain preflight: rc=$rc RDNB=$RDNB exists=$([ -f "$RDNB/.notify-enabled" ] && echo yes || echo no)"

run_bin "$TN" notify-enable "$RDNB"
rc=$?
[ "$rc" -eq 0 ] && [ -f "$RDNB/.notify-enabled" ] \
  && ok "(NOTIFY) notify-enable <run_dir> creates the marker on an existing run dir" \
  || no "(NOTIFY) notify-enable on existing run dir: rc=$rc exists=$([ -f "$RDNB/.notify-enabled" ] && echo yes || echo no)"

run_bin "$TN" notify-enable "$RDNB"
rc=$?
[ "$rc" -eq 0 ] && ok "(NOTIFY) notify-enable is idempotent — touching an already-enabled run is a no-op" \
  || no "(NOTIFY) notify-enable re-run: rc=$rc"

run_bin "$TN" notify-enable "$TN/repo/.supervisor/verify/no-such-run"
rc=$?
[ "$rc" -eq 2 ] && grep -qF '[run_dir_missing]' "$LAST_ERR" \
  && ok "(NOTIFY) notify-enable on a missing run dir → exit 2 [run_dir_missing]" \
  || no "(NOTIFY) notify-enable missing run dir: rc=$rc err=$(cat "$LAST_ERR")"

run_bin "$TN" notify-enable
rc=$?
[ "$rc" -eq 2 ] && ok "(NOTIFY) notify-enable with no run_dir → usage exit 2" || no "(NOTIFY) notify-enable no-arg: rc=$rc err=$(cat "$LAST_ERR")"

# Item-04 auth-check / first-unverdicted arms below are tagged (I4-ACn) — item 03 already owns the
# bare (AC1)/(AC2)/(AC3)/(AC6) tags above for ITS OWN acceptance criteria, and the sandboxed
# (AC11i) self-check greps the literal substring `(AC3)` to prove no browser arm ran on a failed
# install; a bare `(AC3)` tag here would be a false positive on that grep (and confusing regardless
# of the grep) since these arms need no browser at all.
# ============================================================================
echo "== (I4-AC2) auth-check: auth.method none -> exit 0, ZERO executor calls, NO evidence line =="
T9="$(mktmp)"; stage "$T9"; contract "$T9" true
run_bin "$T9" preflight "$REQ" --repo .
RD9="$(last_run_dir)"
[ -n "$RD9" ] && [ -d "$RD9" ] || no "(I4-AC2) preflight fixture failed: $(cat "$LAST_ERR")"
: > "$T9/calls.log"
run_bin "$T9" auth-check "$RD9" --repo .
rc=$?
[ "$rc" -eq 0 ] && ok "(I4-AC2) auth-check: auth.method none -> exit 0" || no "(I4-AC2) auth-check method none: rc=$rc err=$(cat "$LAST_ERR")"
[ "$(ev_field "$RD9" 'select(.event == "auth")' | grep -c .)" -eq 0 ] && ok "(I4-AC2) no auth evidence line appended for method none" || no "(I4-AC2) an auth line was appended: $(ev_field "$RD9" 'select(.event == "auth")')"
[ "$(calls_count "$T9")" -eq 0 ] && ok "(I4-AC2) ZERO verify-env.sh calls of any kind for method none" || no "(I4-AC2) executor was called: $(cat "$T9/calls.log")"

# ============================================================================
echo "== (I4-AC1) auth-check: storage_state + anonymous probe -> auth/needs_auth + pause/needs_auth, exit 4, no ac line =="
T10="$(mktmp)"; stage "$T10"; contract_auth "$T10" storage_state
run_bin "$T10" preflight "$REQ" --repo .
RD10="$(last_run_dir)"
[ -n "$RD10" ] && [ -d "$RD10" ] || no "(I4-AC1) preflight fixture failed: $(cat "$LAST_ERR")"
: > "$T10/calls.log"
STUB_AUTH=anonymous run_bin "$T10" auth-check "$RD10" --repo .
rc=$?
[ "$rc" -eq 4 ] && ok "(I4-AC1) auth-check: needs_auth -> exit 4 (distinct from preflight's 1/2/3)" || no "(I4-AC1) auth-check needs_auth: rc=$rc err=$(cat "$LAST_ERR")"
[ "$(ev_field "$RD10" 'select(.event == "auth") | .state')" = "needs_auth" ] && ok "(I4-AC1) exactly one auth/needs_auth line" || no "(I4-AC1) auth line: $(ev_field "$RD10" 'select(.event == "auth")')"
[ "$(ev_field "$RD10" 'select(.event == "pause") | .reason')" = "needs_auth" ] && ok "(I4-AC1) exactly one pause/needs_auth line" || no "(I4-AC1) pause line: $(ev_field "$RD10" 'select(.event == "pause")')"
[ "$(ev_field "$RD10" 'select(.event == "ac")' | grep -c .)" -eq 0 ] && ok "(I4-AC1) no ac line was written and no spec authored" || no "(I4-AC1) an ac line exists"
grep -qF 'needs_auth' "$RD10/summary.md" && ok "(I4-AC1) summary.md rebuilt and names the pause" || no "(I4-AC1) summary.md: $(cat "$RD10/summary.md" 2>/dev/null)"
grep -q '^auth-probe ' "$T10/calls.log" && ok "(I4-AC1) the call log shows the auth-probe call" || no "(I4-AC1) calls: $(cat "$T10/calls.log")"
python3 "$T10/bin/validate-verify-evidence.py" "$RD10/evidence.jsonl" >/dev/null 2>&1 && ok "(I4-AC1) the store re-validates" || no "(I4-AC1) store invalid: $(python3 "$T10/bin/validate-verify-evidence.py" "$RD10/evidence.jsonl" 2>&1)"

# ============================================================================
echo "== (I4-AC3) auth-check: storage_state + authenticated probe -> one auth/authenticated line, exit 0, no pause/resume =="
sleep 1
run_bin "$T10" preflight "$REQ" --repo .
RD11="$(last_run_dir)"
: > "$T10/calls.log"
STUB_AUTH=authenticated run_bin "$T10" auth-check "$RD11" --repo .
rc=$?
[ "$rc" -eq 0 ] && ok "(I4-AC3) auth-check: authenticated -> exit 0" || no "(I4-AC3) auth-check authenticated: rc=$rc err=$(cat "$LAST_ERR")"
[ "$(ev_field "$RD11" 'select(.event == "auth") | .state')" = "authenticated" ] && ok "(I4-AC3) exactly one auth/authenticated line" || no "(I4-AC3) auth line: $(ev_field "$RD11" 'select(.event == "auth")')"
[ "$(ev_field "$RD11" 'select(.event == "pause")' | grep -c .)" -eq 0 ] && [ "$(ev_field "$RD11" 'select(.event == "resume")' | grep -c .)" -eq 0 ] \
  && ok "(I4-AC3) no pause line, no resume line" || no "(I4-AC3) pause/resume present: $(ev_field "$RD11" 'select(.event == "pause" or .event == "resume")')"

# ============================================================================
echo "== (I4-AC1u) auth-check: probe UNREACHABLE (nonzero rc, not just a wrong stdout string) -> same needs_auth/pause/exit-4 outcome =="
sleep 1
run_bin "$T10" preflight "$REQ" --repo .
RD10u="$(last_run_dir)"
: > "$T10/calls.log"
STUB_AUTH=unreachable run_bin "$T10" auth-check "$RD10u" --repo .
rc=$?
[ "$rc" -eq 4 ] && ok "(I4-AC1u) auth-check: unreachable probe -> exit 4 (same as a wrong-stdout anonymous)" || no "(I4-AC1u) auth-check unreachable: rc=$rc err=$(cat "$LAST_ERR")"
[ "$(ev_field "$RD10u" 'select(.event == "auth") | .state')" = "needs_auth" ] && ok "(I4-AC1u) a nonzero-rc probe still records auth/needs_auth, not a crash" || no "(I4-AC1u) auth line: $(ev_field "$RD10u" 'select(.event == "auth")')"
[ "$(ev_field "$RD10u" 'select(.event == "pause") | .reason')" = "needs_auth" ] && ok "(I4-AC1u) pause/needs_auth line appended" || no "(I4-AC1u) pause line: $(ev_field "$RD10u" 'select(.event == "pause")')"

# ============================================================================
echo "== (I4-AC6) verify-helpers.sh first-unverdicted: first uncovered ac_id, empty when fully verdicted =="
T11="$(mktmp)"; stage "$T11"; contract "$T11" true
run_bin "$T11" preflight "$REQ" --repo .
RD12="$(last_run_dir)"
out="$(bash "$T11/bin/verify-helpers.sh" first-unverdicted "$RD12")"; rc=$?
[ "$out" = "AC1" ] && [ "$rc" -eq 0 ] && ok "(I4-AC6) fresh run -> first-unverdicted prints AC1, exit 0" || no "(I4-AC6) fresh run: out='$out' rc=$rc"
run_bin "$T11" verdict "$RD12" AC1 NOT_VERIFIABLE --reason x
run_bin "$T11" verdict "$RD12" AC2 BLOCKED --reason y
out="$(bash "$T11/bin/verify-helpers.sh" first-unverdicted "$RD12")"; rc=$?
[ "$out" = "AC3" ] && [ "$rc" -eq 0 ] && ok "(I4-AC6) AC1+AC2 verdicted -> prints AC3, exit 0" || no "(I4-AC6) after 2: out='$out' rc=$rc"
run_bin "$T11" verdict "$RD12" AC3 NOT_VERIFIABLE --reason z
out="$(bash "$T11/bin/verify-helpers.sh" first-unverdicted "$RD12")"; rc=$?
[ -z "$out" ] && [ "$rc" -eq 0 ] && ok "(I4-AC6) every ac_id verdicted -> prints NOTHING, exit 0 (not an error)" || no "(I4-AC6) fully covered: out='$out' rc=$rc"

# ============================================================================
echo "== (I4-FIX1u) first-unverdicted unit check (no browser): a FORCED pause-verdict reason does NOT count as verdicted =="
# Same shape as the (I4-AC6) fixture above, but AC2's line carries one of the two FORCED-pause reasons
# `walk_apply_expiry_override` writes — this is the exact story a real session-expiry pause leaves
# behind, exercised here through the browser-less `verdict` subcommand for speed (no Playwright needed).
T11b="$(mktmp)"; stage "$T11b"; contract "$T11b" true
run_bin "$T11b" preflight "$REQ" --repo .
RD12b="$(last_run_dir)"
run_bin "$T11b" verdict "$RD12b" AC1 NOT_VERIFIABLE --reason x
run_bin "$T11b" verdict "$RD12b" AC2 BLOCKED --reason session_expired
run_bin "$T11b" verdict "$RD12b" AC3 BLOCKED --reason run_paused_session_expired
out="$(bash "$T11b/bin/verify-helpers.sh" first-unverdicted "$RD12b")"; rc=$?
[ "$out" = "AC2" ] && [ "$rc" -eq 0 ] \
  && ok "(I4-FIX1u) AC1 genuinely verdicted, AC2/AC3 carry the two FORCED-pause reasons -> first-unverdicted reopens AC2 (the first FORCED one), NOT empty" \
  || no "(I4-FIX1u) out='$out' rc=$rc (expected AC2)"
run_bin "$T11b" verdict "$RD12b" AC2 NOT_VERIFIABLE --reason "resumed and verified for real"
out="$(bash "$T11b/bin/verify-helpers.sh" first-unverdicted "$RD12b")"; rc=$?
[ "$out" = "AC3" ] && [ "$rc" -eq 0 ] \
  && ok "(I4-FIX1u) AC2 given a GENUINE verdict (latest wins) -> first-unverdicted advances to AC3 (still FORCED)" \
  || no "(I4-FIX1u) after AC2 retry: out='$out' rc=$rc (expected AC3)"
run_bin "$T11b" verdict "$RD12b" AC3 NOT_VERIFIABLE --reason "resumed and verified for real"
out="$(bash "$T11b/bin/verify-helpers.sh" first-unverdicted "$RD12b")"; rc=$?
[ -z "$out" ] && [ "$rc" -eq 0 ] \
  && ok "(I4-FIX1u) every ac_id now GENUINELY verdicted -> prints NOTHING, exit 0" \
  || no "(I4-FIX1u) fully covered: out='$out' rc=$rc"
# A real BLOCKED for an UNRELATED reason must still count as done (AC6's original contract, unchanged).
T11c="$(mktmp)"; stage "$T11c"; contract "$T11c" true
run_bin "$T11c" preflight "$REQ" --repo .
RD12c="$(last_run_dir)"
run_bin "$T11c" verdict "$RD12c" AC1 BLOCKED --reason "spec_skipped"
out="$(bash "$T11c/bin/verify-helpers.sh" first-unverdicted "$RD12c")"; rc=$?
[ "$out" = "AC2" ] && [ "$rc" -eq 0 ] \
  && ok "(I4-FIX1u) a REAL BLOCKED for an unrelated reason (spec_skipped) still counts as done -> advances past AC1 to AC2" \
  || no "(I4-FIX1u) unrelated BLOCKED: out='$out' rc=$rc (expected AC2)"

# ============================================================================
echo "== (S) static shape of verify-run.sh =="
bash -n "$RUNNER" 2>"$LAST_ERR" && ok "(S) bash -n" || no "(S) bash -n: $(cat "$LAST_ERR")"
bash "$RUNNER" --help > "$LAST_OUT" 2>&1
for sub in acs preflight walk verdict finish notify-enable; do
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
# PW_TEST_VERSION — the ONE pin for @playwright/test (and therefore for the chromium build it
# downloads). An exact version, never a range: `read-playwright-pin.sh` (the ONE reader of this
# line, anchored on `^PW_TEST_VERSION=<x.y.z>$`) feeds `.github/workflows/ci.yml`'s actions/cache
# key, so a range would give the cache nothing to key on and a hit would silently freeze whatever
# resolved first. Keep the assignment on its own line, exactly `PW_TEST_VERSION=<x.y.z>`, and only
# ONCE — the reader fails CLOSED (exit 1, empty stdout) on a range, a quoted value, a trailing
# comment, a missing line or a duplicate line (test-read-playwright-pin.sh commits each of those
# mutations; the (PWv) arm below ties the reader's output to this variable). Bumping this pin is
# the only way the CI cache turns over.
PW_TEST_VERSION=1.63.0
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
  # Reinstall on a version MISMATCH, not merely on absence: a cache dir left by an older pin
  # (a dev's /tmp, or a stale CI cache) must not keep satisfying the guard forever.
  local have=""
  [ -f "$PW_CACHE/node_modules/@playwright/test/package.json" ] \
    && have="$(node -p "require('$PW_CACHE/node_modules/@playwright/test/package.json').version" 2>/dev/null || true)"
  if [ "$have" != "$PW_TEST_VERSION" ]; then
    npm i --prefix "$PW_CACHE" --no-audit --no-fund "@playwright/test@$PW_TEST_VERSION" >"$log" 2>&1 \
      || { PW_SKIP="npm i @playwright/test@$PW_TEST_VERSION into $PW_CACHE failed: $(tail -1 "$log" 2>/dev/null)"; return 1; }
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

# write_expiry_specs <dir> — item 04's AC5 mutation control: AC1 (harmless nav, unrelated to auth),
# AC2 (logs in then hits /protected TWICE — the 2nd hit is the one that observes the 401 once
# --auth-expire-after 1 is in effect; the spec's OWN assertion still PASSES despite it, per AC5's
# "the override must win over a spec that happens to still succeed"), AC3 (harmless nav, runs clean
# — AC5 requires the override fire on AC3 "even though AC3's spec ... ran clean").
write_expiry_specs() {
  mkdir -p "$1"
  cat > "$1/AC1.spec.ts" <<'SPEC'
import { test, expect } from '@playwright/test';

test('[AC1] Given the form page, when it loads, then a Value field is visible', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByLabel('Value')).toBeVisible();
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

test('[AC2] Given a session that dies mid-walk, when /protected is hit past the expiry threshold, then the app itself answers 401 (this assertion still passes)', async ({ page }) => {
  await page.request.post('/login', { form: { x: '1' } });
  await page.goto('/protected');
  await page.goto('/protected');
  await expect(page).toHaveURL(/\/protected$/);
});
SPEC
  cat > "$1/AC3.spec.ts" <<'SPEC'
import { test, expect } from '@playwright/test';

test('[AC3] Given the form page, when it loads again, then it is still visible (unrelated to auth)', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByLabel('Value')).toBeVisible();
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
echo "== (PWv) acquire_playwright reinstalls on a version MISMATCH or on absence, never on a match (stub npm — nothing is downloaded) =="
# The guard under test is the `have != PW_TEST_VERSION` branch: a matching package.json must NOT
# trigger `npm i` (the CI cache hit is then free), while a stale or absent one MUST. Every case runs
# in a SUBSHELL with its own fresh cache dir under $ROOT and a PATH-first `npm` stub that appends its
# argv to a log and exits 1, so the real $PW_CACHE, PW_READY and PW_SKIP are untouched and no case can
# reach the network. Each case is expected to RETURN 1 (there is never a playwright bin to find) — the
# assertions are on the npm log and on WHICH refusal PW_SKIP carries, which proves the guard was
# passed (match) or taken (mismatch / absent) rather than short-circuited by an earlier check.
PWV_BIN="$(mktmp)"; PWV_LOG="$PWV_BIN/npm.log"
cat > "$PWV_BIN/npm" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$PWV_LOG"
exit 1
EOF
chmod +x "$PWV_BIN/npm"
# pwv_case <label> <package.json version | ""(absent)> — leaves the npm argv log in $PWV_LOG and
# the subshell's PW_SKIP in $PWV_SKIP.
pwv_case() {
  local label="$1" ver="$2" c
  c="$(mktmp)"; : > "$PWV_LOG"
  if [ -n "$ver" ]; then
    mkdir -p "$c/node_modules/@playwright/test"
    printf '{"version":"%s"}\n' "$ver" > "$c/node_modules/@playwright/test/package.json"
  fi
  # The return code is deliberately not asserted (always 1 here — no bin); the subshell exits 0 so
  # the caller's flow is decided by the log + PW_SKIP assertions, never by the expected refusal.
  ( PW_CACHE="$c"; PATH="$PWV_BIN:$PATH"; acquire_playwright; printf '%s\n' "$PW_SKIP" > "$c/skip.txt"; exit 0 )
  PWV_SKIP="$(cat "$c/skip.txt")"
  [ ! -e "$c/node_modules/.bin/playwright" ] || no "($label) a playwright bin appeared in the fresh cache — the stub did not hold"
}
pwv_case PWv-match "$PW_TEST_VERSION"
[ ! -s "$PWV_LOG" ] && ok "(PWv-match) package.json at $PW_TEST_VERSION ⇒ npm NOT invoked (no reinstall on a matching version)" \
  || no "(PWv-match) npm was invoked on a matching version: $(cat "$PWV_LOG")"
case "$PWV_SKIP" in "no playwright bin"*) ok "(PWv-match) PW_SKIP starts with \`no playwright bin\` — the version guard was PASSED, not short-circuited" ;;
  *) no "(PWv-match) PW_SKIP='$PWV_SKIP' (expected the no-playwright-bin refusal)" ;; esac
for pwv in "PWv-mismatch:0.0.0" "PWv-absent:"; do
  pwv_label="${pwv%%:*}"; pwv_ver="${pwv#*:}"
  pwv_case "$pwv_label" "$pwv_ver"
  [ "$(wc -l < "$PWV_LOG" | tr -d ' ')" -eq 1 ] && ok "($pwv_label) npm invoked EXACTLY once" || no "($pwv_label) npm log has $(wc -l < "$PWV_LOG" | tr -d ' ') lines: $(cat "$PWV_LOG")"
  grep -qF -- "@playwright/test@$PW_TEST_VERSION" "$PWV_LOG" && ok "($pwv_label) the install names @playwright/test@$PW_TEST_VERSION (the exact pin, not a range)" \
    || no "($pwv_label) npm argv: $(cat "$PWV_LOG")"
  case "$PWV_SKIP" in "npm i @playwright/test@$PW_TEST_VERSION"*) ok "($pwv_label) PW_SKIP starts with \`npm i @playwright/test@$PW_TEST_VERSION\` — the reinstall branch was taken" ;;
    *) no "($pwv_label) PW_SKIP='$PWV_SKIP' (expected the npm-failed refusal)" ;; esac
done
[ "$PW_READY" -eq 0 ] && [ -z "$PW_SKIP" ] && ok "(PWv) the outer PW_READY / PW_SKIP are untouched by the subshell cases" || no "(PWv) outer state leaked: PW_READY=$PW_READY PW_SKIP='$PW_SKIP'"
[ "$(bash "$HERE/read-playwright-pin.sh" 2>/dev/null)" = "$PW_TEST_VERSION" ] && ok "(PWv) read-playwright-pin.sh prints exactly \$PW_TEST_VERSION ($PW_TEST_VERSION) — the CI cache key and this pin are one value" \
  || no "(PWv) read-playwright-pin.sh printed '$(bash "$HERE/read-playwright-pin.sh" 2>&1)' vs PW_TEST_VERSION=$PW_TEST_VERSION"

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
  echo "== (I4-AC5) mutation control: a real 401 mid-walk forces BLOCKED onto that AC and every later one =="
  PORT_HEALTHY="$(free_port)"
  PORT_EXPIRE="$(free_port)"
  if start_app "$PORT_HEALTHY" && start_app "$PORT_EXPIRE" "--auth-expire-after 1"; then
    # Positive gate (AC5's own mutation-control requirement): prove --auth-expire-after really
    # differs from the healthy fixture BEFORE trusting any override result — a stub `walk` that
    # always pauses must not be able to pass this arm.
    curl -s -c "$ROOT/i4ac5-h.txt" -d 'x=1' "http://127.0.0.1:$PORT_HEALTHY/login" >/dev/null
    curl -s -c "$ROOT/i4ac5-e.txt" -d 'x=1' "http://127.0.0.1:$PORT_EXPIRE/login" >/dev/null
    h1="$(curl -s -o /dev/null -w '%{http_code}' -b "$ROOT/i4ac5-h.txt" "http://127.0.0.1:$PORT_HEALTHY/protected")"
    h2="$(curl -s -o /dev/null -w '%{http_code}' -b "$ROOT/i4ac5-h.txt" "http://127.0.0.1:$PORT_HEALTHY/protected")"
    e1="$(curl -s -o /dev/null -w '%{http_code}' -b "$ROOT/i4ac5-e.txt" "http://127.0.0.1:$PORT_EXPIRE/protected")"
    e2="$(curl -s -o /dev/null -w '%{http_code}' -b "$ROOT/i4ac5-e.txt" "http://127.0.0.1:$PORT_EXPIRE/protected")"
    if [ "$h1" = "200" ] && [ "$h2" = "200" ] && [ "$e1" = "200" ] && [ "$e2" = "401" ]; then
      ok "(I4-AC5) gate: --auth-expire-after 1 really produces a 401 on request 2 while the healthy fixture stays 200 (the signal genuinely differs)"

      T12="$(mktmp)"; stage "$T12"; contract "$T12" true "http://127.0.0.1:$PORT_HEALTHY"
      ln -s "$PW_CACHE/node_modules" "$T12/repo/node_modules"
      run_bin "$T12" preflight "$REQ" --repo .
      RD13="$(last_run_dir)"
      write_expiry_specs "$RD13/specs"
      run_bin "$T12" walk "$RD13" --repo .
      rc=$?
      [ "$rc" -eq 0 ] && ok "(I4-AC5) POSITIVE control (never-expiring fixture): walk -> exit 0 (never 5)" || no "(I4-AC5) positive control: rc=$rc err=$(cat "$LAST_ERR")"
      [ "$(ev_field "$RD13" 'select(.event == "ac") | [.ac_id, .verdict] | join("=")' | tr '\n' ',')" = "AC1=PASS,AC2=PASS,AC3=PASS," ] \
        && ok "(I4-AC5) POSITIVE control: AC1/AC2/AC3 all show their REAL verdicts (PASS) — no override fired" \
        || no "(I4-AC5) positive control verdicts: $(ev_field "$RD13" 'select(.event == "ac") | [.ac_id, .verdict, .reason] | join("|")')"
      [ "$(ev_field "$RD13" 'select(.event == "auth")' | grep -c .)" -eq 0 ] && [ "$(ev_field "$RD13" 'select(.event == "pause")' | grep -c .)" -eq 0 ] \
        && ok "(I4-AC5) POSITIVE control: no auth/expired line, no pause line" \
        || no "(I4-AC5) positive control unexpectedly carries an auth/pause line"

      T13="$(mktmp)"; stage "$T13"; contract "$T13" true "http://127.0.0.1:$PORT_EXPIRE"
      ln -s "$PW_CACHE/node_modules" "$T13/repo/node_modules"
      run_bin "$T13" preflight "$REQ" --repo .
      RD14="$(last_run_dir)"
      write_expiry_specs "$RD14/specs"
      run_bin "$T13" walk "$RD14" --repo .
      rc=$?
      [ "$rc" -eq 5 ] && ok "(I4-AC5) NEGATIVE (expiring fixture): walk -> exit 5, distinct from the normal 0" || no "(I4-AC5) negative: rc=$rc err=$(cat "$LAST_ERR")"
      [ "$(ac_get "$RD14" AC1 '.verdict')" = "PASS" ] && ok "(I4-AC5) AC1 (ordinal < N) keeps its REAL verdict, untouched" || no "(I4-AC5) AC1: $(ac_get "$RD14" AC1 '.verdict')"
      v2="$(ac_get "$RD14" AC2 '[.verdict, .classification, .reason] | join("|")')"
      [ "$v2" = "BLOCKED|ENVIRONMENT_ISSUE|session_expired" ] \
        && ok "(I4-AC5) AC2 (the ordinal that saw the 401) forced BLOCKED/ENVIRONMENT_ISSUE/session_expired REGARDLESS of its own passing assertion" \
        || no "(I4-AC5) AC2: $v2"
      v3="$(ac_get "$RD14" AC3 '[.verdict, .classification, .reason] | join("|")')"
      [ "$v3" = "BLOCKED|ENVIRONMENT_ISSUE|run_paused_session_expired" ] \
        && ok "(I4-AC5) AC3 (ordinal > N) forced BLOCKED/ENVIRONMENT_ISSUE/run_paused_session_expired even though its own spec ran clean" \
        || no "(I4-AC5) AC3: $v3"
      [ "$(ev_field "$RD14" 'select(.event == "auth") | .state' | grep -c .)" -eq 1 ] && [ "$(ev_field "$RD14" 'select(.event == "auth") | .state')" = "expired" ] \
        && ok "(I4-AC5) exactly ONE auth/expired line (not one per forced AC)" \
        || no "(I4-AC5) auth lines: $(ev_field "$RD14" 'select(.event == "auth")')"
      [ "$(ev_field "$RD14" 'select(.event == "pause") | .reason' | grep -c .)" -eq 1 ] && [ "$(ev_field "$RD14" 'select(.event == "pause") | .reason')" = "session_expired" ] \
        && ok "(I4-AC5) exactly ONE pause/session_expired line (not one per forced AC)" \
        || no "(I4-AC5) pause lines: $(ev_field "$RD14" 'select(.event == "pause")')"
      python3 "$T13/bin/validate-verify-evidence.py" "$RD14/evidence.jsonl" >/dev/null 2>&1 \
        && ok "(I4-AC5) the store re-validates" || no "(I4-AC5) store invalid: $(python3 "$T13/bin/validate-verify-evidence.py" "$RD14/evidence.jsonl" 2>&1)"

      # ------------------------------------------------------------------------
      echo "== (I4-FIX1) resume round-trip: first-unverdicted reopens the forced pause-verdicts; a second walk with a healthy session overwrites them with real verdicts =="
      # RD14 is the NEGATIVE arm above: AC1=PASS (real, untouched), AC2=BLOCKED/session_expired
      # (forced, the min ordinal), AC3=BLOCKED/run_paused_session_expired (forced), walk exited 5.
      # This is the item-04 review-fix regression: WITHOUT the fix, every ac_id already carries an
      # `ac` line at this point, so first-unverdicted would print NOTHING and the resumed run would
      # have no ACs left to re-author specs for — a permanently stranded pause.
      out="$(bash "$T13/bin/verify-helpers.sh" first-unverdicted "$RD14")"; rc=$?
      [ "$out" = "AC2" ] && [ "$rc" -eq 0 ] \
        && ok "(I4-FIX1) after the forced session-expiry pause, first-unverdicted reopens AC2 (the min forced ordinal) — NOT empty" \
        || no "(I4-FIX1) first-unverdicted after pause: out='$out' rc=$rc (expected AC2)"
      # Simulate the human sign-in: author fresh specs for ONLY the reopened set (AC2, AC3) against
      # the NEVER-EXPIRING healthy fixture — AC1 is NOT re-authored, mirroring the real resume flow's
      # first-unverdicted-scoped spec set (agents/qa-executor.md step 6).
      rm -f "$RD14/specs/AC1.spec.ts"
      cat > "$RD14/specs/AC2.spec.ts" <<'SPEC'
import { test, expect } from '@playwright/test';

test('[AC2] Given a session that dies mid-walk, when /protected is hit past the expiry threshold, then the app itself answers 401 (this assertion still passes)', async ({ page }) => {
  await page.request.post('/login', { form: { x: '1' } });
  await page.goto('/protected');
  await expect(page).toHaveURL(/\/protected$/);
});
SPEC
      cat > "$RD14/specs/AC3.spec.ts" <<'SPEC'
import { test, expect } from '@playwright/test';

test('[AC3] Given the form page, when it loads again, then it is still visible (unrelated to auth)', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByLabel('Value')).toBeVisible();
});
SPEC
      run_bin "$T13" walk "$RD14" --repo . --base-url "http://127.0.0.1:$PORT_HEALTHY"
      rc=$?
      [ "$rc" -eq 0 ] && ok "(I4-FIX1) resumed walk against the healthy session -> exit 0 (no new expiry)" || no "(I4-FIX1) resumed walk: rc=$rc err=$(cat "$LAST_ERR")"
      [ "$(ac_get "$RD14" AC2 '.verdict')" = "PASS" ] \
        && ok "(I4-FIX1) AC2's forced BLOCKED/session_expired is overwritten by a real PASS (latest-per-ac_id wins)" \
        || no "(I4-FIX1) AC2 latest verdict: $(ac_get "$RD14" AC2 '[.verdict,.classification,.reason] | join("|")')"
      [ "$(ac_get "$RD14" AC3 '.verdict')" = "PASS" ] \
        && ok "(I4-FIX1) AC3's forced BLOCKED/run_paused_session_expired is overwritten by a real PASS" \
        || no "(I4-FIX1) AC3 latest verdict: $(ac_get "$RD14" AC3 '[.verdict,.classification,.reason] | join("|")')"
      [ "$(ac_get "$RD14" AC1 '.verdict')" = "PASS" ] \
        && ok "(I4-FIX1) AC1 (never reopened, never re-authored) still shows its original real PASS" \
        || no "(I4-FIX1) AC1 verdict: $(ac_get "$RD14" AC1 '.verdict')"
      # AC2's own spec assertion PASSES despite the 401 (AC5's own requirement — "the override must
      # win over a spec that happens to still succeed"), so the first walk already left AC2 with TWO
      # lines (the real ingest PASS, THEN the forced BLOCKED/session_expired override); the resumed
      # walk appends a THIRD — the real PASS that finally supersedes the forced one.
      [ "$(ev_field "$RD14" 'select(.event == "ac" and .ac_id == "AC2") | .verdict' | grep -c .)" -eq 3 ] \
        && ok "(I4-FIX1) evidence.jsonl is append-only: AC2 now carries THREE ac lines (real PASS, forced BLOCKED, real PASS again) — history preserved, latest wins" \
        || no "(I4-FIX1) AC2 ac-line count: $(ev_field "$RD14" 'select(.event == "ac" and .ac_id == "AC2") | .verdict' | grep -c .)"
      out="$(bash "$T13/bin/verify-helpers.sh" first-unverdicted "$RD14")"; rc=$?
      [ -z "$out" ] && [ "$rc" -eq 0 ] \
        && ok "(I4-FIX1) after the real retry verdicts land, first-unverdicted is empty again — fully (genuinely) verdicted" \
        || no "(I4-FIX1) first-unverdicted after retry: out='$out' rc=$rc"
      grep -q '^PASS: 3 · FAIL: 0 · BLOCKED: 0 · NOT_VERIFIABLE: 0 · total: 3$' "$RD14/summary.md" \
        && ok "(I4-FIX1) counts row now shows all 3 real PASSes (the forced pause verdicts no longer count)" || no "(I4-FIX1) counts row: $(grep '^PASS: ' "$RD14/summary.md")"
      python3 "$T13/bin/validate-verify-evidence.py" "$RD14/evidence.jsonl" >/dev/null 2>&1 \
        && ok "(I4-FIX1) the store re-validates after the resume round-trip" || no "(I4-FIX1) store invalid: $(python3 "$T13/bin/validate-verify-evidence.py" "$RD14/evidence.jsonl" 2>&1)"
    else
      no "(I4-AC5) UNPROVEN — --auth-expire-after did not produce the expected 200/200/200/401 pattern (healthy: $h1/$h2, expiring: $e1/$e2); the mutation control cannot prove anything"
    fi
  else
    no "(I4-AC5) fixture app(s) did not answer /health on ports $PORT_HEALTHY / $PORT_EXPIRE"
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
# Prompt-surface arms (Subtask 3): the command / skill / agent files that CONSUME verify-run.sh.
# These are grep pins on committed prose — the "claim no check backs" class: every rule the brief
# states about the prompt surfaces has a literal assertion here, so deleting the carve-out sentence,
# re-wording the Level-1 rule, or adding a harness-specific browser tool fails this suite.
# ============================================================================
echo "== (AC7a) Level-1 rule byte-identical + exactly one carve-out sentence =="
PLUGIN_DIR="$(cd "$HERE/.." && pwd)"
AGENT="$PLUGIN_DIR/agents/qa-executor.md"
VERIFY_CMD="$PLUGIN_DIR/commands/verify.md"
QA_CMD="$PLUGIN_DIR/commands/qa-executor.md"
SKILL="$PLUGIN_DIR/skills/verify-walkthrough/SKILL.md"
for f in "$AGENT" "$VERIFY_CMD" "$QA_CMD" "$SKILL"; do
  [ -f "$f" ] && ok "(AC7) prompt surface present: ${f#"$PLUGIN_DIR"/}" || no "(AC7) prompt surface missing: $f"
done
L1_RULE='- **No destructive actions:** Never submit forms during discovery, never click delete/logout/payment buttons'
n="$(grep -cF -- "$L1_RULE" "$AGENT")"
[ "$n" -eq 1 ] && ok "(AC7a) the Level-1 rule line is present exactly once, byte-identical" || no "(AC7a) Level-1 rule literal count: $n (expected 1)"
CARVE="mode's mutation carve-out is defined in \`skills/verify-walkthrough/SKILL.md\` and applies there only"
n="$(grep -cF -- "$CARVE" "$AGENT")"
[ "$n" -eq 1 ] && ok "(AC7a) exactly one carve-out sentence points at the skill" || no "(AC7a) carve-out sentence count: $n (expected 1)"
# The sentence must FOLLOW the rule: the line after the rule carries it (continuation line).
after="$(grep -nF -- "$L1_RULE" "$AGENT" | cut -d: -f1)"
[ -n "$after" ] && sed -n "$((after+1))p" "$AGENT" | grep -qF -- "$CARVE" \
  && ok "(AC7a) the carve-out sentence is the line immediately following the rule" || no "(AC7a) carve-out sentence does not immediately follow the rule"

echo "== (AC7b) --verify branch: keeps Phase 2, skips every other phase with the fixed reason =="
grep -qF -- '### VERIFY MODE (`--verify <run_dir>`)' "$AGENT" && ok "(AC7b) the provides symbol \`### VERIFY MODE (--verify <run_dir>)\` header exists (H3)" || no "(AC7b) VERIFY MODE H3 header missing"
for ph in 1 3 3.6 4 5 6 7 8 9 10 11 12; do
  grep -qF -- "⊘ Phase $ph SKIPPED. Reason: --verify mode" "$AGENT" && ok "(AC7b) Phase $ph skipped with the --verify reason" || no "(AC7b) Phase $ph skip line missing"
done
grep -qF -- "⊘ Phase 13 audit SKIPPED. Reason: --verify mode" "$AGENT" && ok "(AC7b) Phase 13's audit half skipped; EMIT half kept" || no "(AC7b) Phase 13 audit skip line missing"
n="$(grep -cF -- '⊘ Phase 2 SKIPPED. Reason: --verify mode' "$AGENT")"
[ "$n" -eq 0 ] && ok "(AC7b) Phase 2 is NOT skipped in --verify mode" || no "(AC7b) Phase 2 carries a --verify skip line"
grep -qF -- 'verify-run.sh walk <run_dir>' "$AGENT" && ok "(AC7b) the branch shells out to verify-run.sh walk" || no "(AC7b) no verify-run.sh walk shell-out in the agent"
grep -qF -- 'verify-run.sh finish <run_dir>' "$AGENT" && ok "(AC7b) the branch shells out to verify-run.sh finish" || no "(AC7b) no verify-run.sh finish shell-out in the agent"
grep -qF -- 'VERIFY_RESULT:' "$AGENT" && grep -qF -- 'counts: {pass:' "$AGENT" \
  && ok "(AC7b) VERIFY_RESULT emission template present with a counts object" || no "(AC7b) VERIFY_RESULT template missing"
grep -qF -- 'skills/verify-walkthrough/SKILL.md' "$AGENT" && ok "(AC7b) the agent Reads the skill at mode entry" || no "(AC7b) agent never names the skill"
# Read on demand, NOT preloaded: the frontmatter skills: list must not carry it (token budget, AC7d).
fm="$(awk 'NR==1 && /^---$/ {c=1; next} c==1 && /^---$/ {exit} c==1 {print}' "$AGENT")"
printf '%s\n' "$fm" | grep -q -- '- verify-walkthrough' \
  && no "(AC7d) verify-walkthrough is PRELOADED in the agent frontmatter (budget breach risk)" || ok "(AC7d) verify-walkthrough is NOT in the frontmatter skills: list (Read on demand)"

echo "== (AC7c) no harness-specific browser tool on any of the four verify surfaces =="
for f in "$AGENT" "$VERIFY_CMD" "$SKILL" "$RUNNER"; do
  n="$(grep -cE 'Claude_Browser|computer-use|mcp__' "$f")"
  [ "$n" -eq 0 ] && ok "(AC7c) ${f#"$PLUGIN_DIR"/}: 0 harness-browser-tool mentions" || no "(AC7c) ${f#"$PLUGIN_DIR"/}: $n harness-browser-tool mentions"
done

echo "== (AC5-skill) derivation fixtures + the four verdicts =="
grep -qF -- '### Derivation fixtures' "$SKILL" && ok "(AC5) the skill carries a \`### Derivation fixtures\` table" || no "(AC5) no \`### Derivation fixtures\` header in the skill"
grep -F -- 'under 200 concurrent users' "$SKILL" | grep -qF -- 'NOT_VERIFIABLE' \
  && ok "(AC5) the concurrency row (\`under 200 concurrent users\`) maps to NOT_VERIFIABLE on the same line" || no "(AC5) concurrency row missing or not NOT_VERIFIABLE"
n="$(grep -cE '^\| Given .*\| (`?\[AC[0-9n]+\]`?|none) ' "$SKILL")"
[ "$n" -ge 5 ] && ok "(AC5) ≥5 derivation-fixture rows ($n)" || no "(AC5) only $n derivation-fixture rows (need ≥5)"
grep -qF -- 'pass_requires_observation' "$SKILL" && ok "(AC5) the skill states PASS comes only from walk's ingest" || no "(AC5) skill does not name pass_requires_observation"
grep -qF -- 'test.afterEach' "$SKILL" && grep -qF -- "attach('page-body'" "$SKILL" \
  && ok "(AC5) the spec template carries the afterEach page-body attach" || no "(AC5) spec template lacks the afterEach page-body attach"
grep -qF -- 'Payment, logout and account-deletion actions stay forbidden everywhere' "$SKILL" \
  && ok "(AC5) V7 carve-out keeps payment/logout/account-delete forbidden" || no "(AC5) carve-out's forbidden set missing"
grep -qF -- 'version: "1.2.0"' "$SKILL" && ok "(AC5) skill frontmatter version pinned at 1.2.0 (item 06 bump)" || no "(AC5) skill frontmatter version not 1.2.0"

echo "== (AC10-command) /verify surface + commands/qa-executor.md sync =="
grep -qF -- '/loomwright:verify' "$VERIFY_CMD" && ok "(cmd) commands/verify.md names the namespaced /loomwright:verify form" || no "(cmd) /loomwright:verify missing from commands/verify.md"
grep -qF -- 'verify-run.sh" preflight' "$VERIFY_CMD" || grep -qF -- 'verify-run.sh preflight' "$VERIFY_CMD" \
  && ok "(cmd) commands/verify.md shells out to verify-run.sh preflight" || no "(cmd) commands/verify.md does not shell to verify-run.sh preflight"
grep -qF -- 'subagent_type: "loomwright:qa-executor"' "$VERIFY_CMD" && ok "(cmd) commands/verify.md spawns loomwright:qa-executor via Task" || no "(cmd) Task spawn of loomwright:qa-executor missing"
grep -qF -- '--verify <run_dir>' "$VERIFY_CMD" && ok "(cmd) commands/verify.md passes --verify <run_dir> to the executor" || no "(cmd) --verify <run_dir> missing from commands/verify.md"
grep -qF -- '--verify' "$QA_CMD" && ok "(cmd) commands/qa-executor.md mentions --verify" || no "(cmd) commands/qa-executor.md does not mention --verify"

# ============================================================================
# Item 04 Subtask 2 arms: auth pause/resume on the prompt surfaces (AC4, AC8, AC10).
# ============================================================================
echo "== (AC10-resume) commands/verify.md --resume flow =="
grep -qF -- '/verify --resume <run_id>' "$VERIFY_CMD" && ok "(AC10) --resume <run_id> is documented in Usage" || no "(AC10) --resume <run_id> missing from Usage"
grep -qF -- '--resume <run_id>' "$VERIFY_CMD" && ok "(AC10) --resume <run_id> appears in the Parameters table" || no "(AC10) --resume <run_id> missing from Parameters"
grep -qF -- 'auth-check' "$VERIFY_CMD" && ok "(AC10) commands/verify.md shells out to verify-run.sh auth-check" || no "(AC10) auth-check missing from commands/verify.md"
grep -qF -- 'event: resume, reason: "human_signed_in"' "$VERIFY_CMD" || grep -qF -- 'event: "resume", reason: "human_signed_in"' "$VERIFY_CMD" \
  && ok "(AC10) commands/verify.md appends the resume/human_signed_in evidence line" || no "(AC10) resume/human_signed_in jq object missing from commands/verify.md"
grep -qF -- 'never silently start' "$VERIFY_CMD" || grep -qF -- 'never silently starting a fresh run' "$VERIFY_CMD" \
  && ok "(AC10) --resume errors rather than silently starting a fresh run under the same id" || no "(AC10) missing dir / no-silent-start guard not documented"
grep -qF -- 'git -C <dir> check-ignore -q' "$VERIFY_CMD" && ok "(AC10) the one-shot storage-state gitignore warning shells to git check-ignore" || no "(AC10) git check-ignore warning missing from commands/verify.md"
grep -qF -- 'run_end") | .status' "$VERIFY_CMD" && ok "(I4-FIX1) --resume guards against a run dir that already finished (reads the run_end status before proceeding)" || no "(I4-FIX1) the already-finished-run guard is missing from commands/verify.md's resume flow"
grep -qF -- 'nothing paused to resume' "$VERIFY_CMD" && ok "(I4-FIX1) the guard names the reason: nothing paused to resume" || no "(I4-FIX1) 'nothing paused to resume' missing from commands/verify.md"

echo "== (AC4-pause) commands/verify.md pause instruction =="
grep -qF -- 'npx playwright codegen --save-storage=' "$VERIFY_CMD" && ok "(AC4) the pause instruction names the codegen --save-storage= form" || no "(AC4) codegen instruction missing from commands/verify.md"
grep -qF -- 'sign in, close the window' "$VERIFY_CMD" && ok "(AC4) the pause instruction includes 'sign in, close the window'" || no "(AC4) sign-in line missing from commands/verify.md"
grep -qF -- '/verify --resume <run_id>' "$VERIFY_CMD" && ok "(AC4) the pause instruction names /verify --resume <run_id>" || no "(AC4) resume line missing from the pause instruction"
n="$(grep -cF -- 'pause_reason' "$VERIFY_CMD")"
[ "$n" -ge 1 ] && ok "(AC4) commands/verify.md reads VERIFY_RESULT.pause_reason ($n mentions)" || no "(AC4) commands/verify.md never mentions pause_reason"

echo "== (AC-propose) commands/verify.md step 5 auto-dispatch trigger fires on issue-only runs too =="
# propose-from-verify.sh drafts every `issue` line unconditionally, regardless of any AC's
# verdict, so a run with 0 FAILs and >=1 issue line WOULD still produce a draft - the step 5
# trigger must not be FAIL-only, or it would silently never invoke the script for that run.
grep -qF -- '.event == "issue"' "$VERIFY_CMD" \
  && ok "(AC-propose) the auto-dispatch jq trigger also matches issue-only lines" \
  || no "(AC-propose) the auto-dispatch jq trigger checks only FAIL ac lines - an issue-only run never auto-dispatches propose-from-verify.sh"
grep -qF -- '.event == "ac" and .verdict == "FAIL"' "$VERIFY_CMD" \
  && ok "(AC-propose) the trigger still matches FAIL ac lines (the issue-only fix did not drop the original arm)" \
  || no "(AC-propose) the FAIL ac arm of the auto-dispatch trigger is missing from commands/verify.md"
grep -qF -- 'propose-from-verify.sh" "$run_dir"' "$VERIFY_CMD" \
  && ok "(AC-propose) the trigger still dispatches propose-from-verify.sh against \$run_dir" \
  || no "(AC-propose) the propose-from-verify.sh dispatch line is missing from commands/verify.md"

echo "== (AC8) agents/qa-executor.md auth-check/resume/pause wiring =="
grep -qF -- 'verify-run.sh auth-check <run_dir> --repo <dir>' "$AGENT" && ok "(AC8) VERIFY MODE step shells out to verify-run.sh auth-check" || no "(AC8) auth-check shell-out missing from agents/qa-executor.md"
n="$(grep -cF -- 'auth-probe: anonymous' "$AGENT")"
[ "$n" -eq 0 ] && ok "(AC8) the old auth-probe: anonymous per-AC fallback is fully removed" || no "(AC8) auth-probe: anonymous still present ($n mentions) — should be unreachable"
grep -qF -- 'RESUME DETECTION' "$AGENT" && ok "(AC8) the agent documents resume-detection before start/seed" || no "(AC8) RESUME DETECTION guard missing"
grep -qF -- 'first-unverdicted' "$AGENT" && ok "(AC8) the agent scopes resumed spec-authoring to first-unverdicted's remaining set" || no "(AC8) first-unverdicted not referenced in agents/qa-executor.md"
grep -qF -- 'Exit 5' "$AGENT" && ok "(AC8) the agent branches on walk's exit 5 (session_expired)" || no "(AC8) walk exit-5 branch missing from agents/qa-executor.md"
grep -qF -- 'pause_reason: needs_auth' "$AGENT" && grep -qF -- 'pause_reason: session_expired' "$AGENT" \
  && ok "(AC8) both pause_reason values (needs_auth, session_expired) appear in the VERIFY_RESULT wiring" || no "(AC8) one or both pause_reason values missing from agents/qa-executor.md"
grep -qF -- 'status: paused' "$AGENT" && ok "(AC8) the agent's VERIFY_RESULT template documents status: paused" || no "(AC8) status: paused missing from the VERIFY_RESULT template"

echo "== (skill) verify-walkthrough documents pause/resume, forward-reference resolved =="
n="$(grep -cF -- 'item 04 adds the pause-for-auth' "$SKILL")"
[ "$n" -eq 0 ] && ok "(skill) the item-04 forward-reference is resolved (0 remaining mentions)" || no "(skill) forward-reference still present ($n mentions)"
grep -qF -- '## 8. Auth pause and resume' "$SKILL" && ok "(skill) a dedicated pause/resume section exists" || no "(skill) no pause/resume section in the skill"
grep -qF -- 'response-40' "$SKILL" && ok "(skill) the skill documents the response-40[13] expiry signal" || no "(skill) expiry signal not documented in the skill"


# ============================================================================
# Item 06 "impact pass" arms (mechanical: diff / brief-surfaces / record-surfaces / prior-acs;
# browser: the two-routes-sharing-a-component fixture + mutation control). Tag: (I06-*).
# ============================================================================
echo "== (I06-diff) impact diff: mechanical git diff --name-only base_sha...head_sha =="
TI1="$(mktmp)"
mkdir -p "$TI1/repo/shared" "$TI1/repo/.supervisor/verify/runA"
( cd "$TI1/repo" && git init -q \
  && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base )
printf 'orig\n' > "$TI1/repo/shared/component.js"
printf 'readme\n' > "$TI1/repo/README.md"
( cd "$TI1/repo" && git add -A && git -c user.email=t@t -c user.name=t commit -q -m first )
BASE_SHA="$(cd "$TI1/repo" && git rev-parse HEAD)"
printf 'changed\n' > "$TI1/repo/shared/component.js"
( cd "$TI1/repo" && git add -A && git -c user.email=t@t -c user.name=t commit -q -m second )
HEAD_SHA="$(cd "$TI1/repo" && git rev-parse HEAD)"
RDI1="$TI1/repo/.supervisor/verify/runA"
jq -cn --arg base "$BASE_SHA" --arg head "$HEAD_SHA" \
  '{schema_version:1, ts:"2026-09-16T00:00:00Z", run_id:"verify-20260916T000000Z-runa", event:"run_start",
    ticket_path:"x.md", ticket_kind:"brief", branch:"b", head_sha:$head, base_sha:$base, env_contract_hash:null}' \
  > "$RDI1/evidence.jsonl"
diff_out="$(bash "$RUNNER" impact diff "$RDI1" --repo "$TI1/repo")"
echo "$diff_out" | jq -e '. == ["shared/component.js"]' >/dev/null 2>&1 \
  && ok "(I06-diff) impact diff prints exactly the mechanically-changed file" \
  || no "(I06-diff) impact diff: $diff_out"

echo "== (I06-brief) impact brief-surfaces: no matching brief -> [] (never fails) =="
brief_out="$(bash "$RUNNER" impact brief-surfaces "$RDI1" --repo "$TI1/repo")"
[ "$brief_out" = "[]" ] && ok "(I06-brief) no matching .supervisor/jobs/done/ brief -> []" || no "(I06-brief) brief_out=$brief_out"

echo "== (I06-brief) impact brief-surfaces: a matching brief with a populated Blast-Radius section =="
mkdir -p "$TI1/repo/.supervisor/jobs/done"
cat > "$TI1/repo/.supervisor/jobs/done/2026-09-01-done-one.md" <<EOF
# Supervisor Job: done one

## Environment
- **Source requirement:** x.md

## Risk Assessment

### Blast-Radius
- auth-service
- billing-worker
EOF
brief_out="$(bash "$RUNNER" impact brief-surfaces "$RDI1" --repo "$TI1/repo")"
echo "$brief_out" | jq -e '. == ["auth-service", "billing-worker"]' >/dev/null 2>&1 \
  && ok "(I06-brief) a matching brief's Blast-Radius bullets are extracted verbatim" \
  || no "(I06-brief) brief_out=$brief_out"
rm -f "$TI1/repo/.supervisor/jobs/done/2026-09-01-done-one.md"

echo "== (I06-record) impact record-surfaces: merges agent classification + mechanical diff + brief names =="
rec_out="$(printf '%s' '{"surfaces":{"home":["shared/component.js"],"echo":["shared/component.js"]},"unmapped":["README.md"]}' \
  | bash "$RUNNER" impact record-surfaces "$RDI1" - --repo "$TI1/repo" --impact-limit 7)"
rc=$?
[ "$rc" -eq 0 ] && ok "(I06-record) record-surfaces exits 0" || no "(I06-record) rc=$rc"
last="$(tail -1 "$RDI1/evidence.jsonl")"
[ "$(printf '%s' "$last" | jq -r '.event')" = "impact_surfaces" ] && ok "(I06-record) exactly one impact_surfaces event appended" || no "(I06-record) last line: $last"
[ "$(printf '%s' "$last" | jq -c '.files')" = '["shared/component.js"]' ] && ok "(I06-record) files is the mechanical diff listing, not the agent's own claim" || no "(I06-record) files: $(printf '%s' "$last" | jq -c '.files')"
[ "$(printf '%s' "$last" | jq -r '.surfaces.home[0]')" = "shared/component.js" ] && [ "$(printf '%s' "$last" | jq -r '.surfaces.echo[0]')" = "shared/component.js" ] \
  && ok "(I06-record) both routes (home, echo) map to the shared component" || no "(I06-record) surfaces: $(printf '%s' "$last" | jq -c '.surfaces')"
[ "$(printf '%s' "$last" | jq -c '.unmapped')" = '["README.md"]' ] && ok "(I06-record) README.md lands in unmapped, never guessed" || no "(I06-record) unmapped: $(printf '%s' "$last" | jq -c '.unmapped')"
[ "$(printf '%s' "$last" | jq -r '.limit')" = "7" ] && ok "(I06-record) limit is recorded from --impact-limit" || no "(I06-record) limit: $(printf '%s' "$last" | jq -r '.limit')"
python3 "$HERE/validate-verify-evidence.py" "$RDI1/evidence.jsonl" >/dev/null 2>&1 && ok "(I06-record) the store re-validates in file mode" || no "(I06-record) store invalid"

echo "== (I06-record) completeness self-heal: a diffed file left out of both surfaces and unmapped folds into unmapped, no crash =="
TI4="$(mktmp)"
mkdir -p "$TI4/repo/shared" "$TI4/repo/.supervisor/verify/runD"
( cd "$TI4/repo" && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base )
printf 'orig\n' > "$TI4/repo/shared/a.js"
printf 'orig\n' > "$TI4/repo/shared/b.js"
( cd "$TI4/repo" && git add -A && git -c user.email=t@t -c user.name=t commit -q -m first )
D_BASE="$(cd "$TI4/repo" && git rev-parse HEAD)"
printf 'changed\n' > "$TI4/repo/shared/a.js"
printf 'changed\n' > "$TI4/repo/shared/b.js"
( cd "$TI4/repo" && git add -A && git -c user.email=t@t -c user.name=t commit -q -m second )
D_HEAD="$(cd "$TI4/repo" && git rev-parse HEAD)"
RDI4="$TI4/repo/.supervisor/verify/runD"
jq -cn --arg base "$D_BASE" --arg head "$D_HEAD" \
  '{schema_version:1, ts:"2026-09-16T00:00:00Z", run_id:"verify-20260916T000000Z-rund", event:"run_start",
    ticket_path:"x.md", ticket_kind:"brief", branch:"b", head_sha:$head, base_sha:$base, env_contract_hash:null}' \
  > "$RDI4/evidence.jsonl"
rec_out="$(printf '%s' '{"surfaces":{"home":["shared/a.js"]},"unmapped":[]}' \
  | bash "$RUNNER" impact record-surfaces "$RDI4" - --repo "$TI4/repo" --impact-limit 7)"
rc=$?
[ "$rc" -eq 0 ] && ok "(I06-record) completeness gap self-heals instead of crashing (exit 0, never dies)" || no "(I06-record) rc=$rc"
last4="$(tail -1 "$RDI4/evidence.jsonl")"
[ "$(printf '%s' "$last4" | jq -c '.unmapped')" = '["shared/b.js"]' ] \
  && ok "(I06-record) the uncovered file (shared/b.js) folds into unmapped, not silently dropped" \
  || no "(I06-record) unmapped: $(printf '%s' "$last4" | jq -c '.unmapped')"
python3 "$HERE/validate-verify-evidence.py" "$RDI4/evidence.jsonl" >/dev/null 2>&1 && ok "(I06-record) the completeness-healed store re-validates" || no "(I06-record) store invalid after self-heal"

echo "== (I06-record) --no-impact: pure no-op, nothing appended =="
before_lines="$(wc -l < "$RDI1/evidence.jsonl" | tr -d ' ')"
bash "$RUNNER" impact record-surfaces "$RDI1" '{}' --repo "$TI1/repo" --no-impact
rc=$?
after_lines="$(wc -l < "$RDI1/evidence.jsonl" | tr -d ' ')"
[ "$rc" -eq 0 ] && [ "$before_lines" -eq "$after_lines" ] && ok "(I06-record) --no-impact exits 0 and appends nothing" || no "(I06-record) --no-impact: rc=$rc before=$before_lines after=$after_lines"

echo "== (I06-prior) impact prior-acs: zero prior runs -> [] silently (fresh clone/worktree/CI) =="
TI2="$(mktmp)"
mkdir -p "$TI2/repo/.supervisor/verify/solo"
( cd "$TI2/repo" && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base )
RDI2="$TI2/repo/.supervisor/verify/solo"
jq -cn '{schema_version:1, ts:"2026-09-16T00:00:00Z", run_id:"verify-20260916T000000Z-solo", event:"run_start",
  ticket_path:"x.md", ticket_kind:"brief", branch:"b", head_sha:"h", base_sha:"h", env_contract_hash:null}
' > "$RDI2/evidence.jsonl"
printf '{}' | bash "$RUNNER" impact record-surfaces "$RDI2" - --repo "$TI2/repo" --impact-limit 10 >/dev/null
prior_out="$(bash "$RUNNER" impact prior-acs "$RDI2" --repo "$TI2/repo" --impact-limit 10)"
[ "$prior_out" = "[]" ] && ok "(I06-prior) no sibling run dirs exist -> [] (never a failure)" || no "(I06-prior) prior_out=$prior_out"

echo "== (I06-prior) impact prior-acs: bounded most-recent-first, --impact-limit 1 keeps exactly one =="
mkdir -p "$TI1/repo/.supervisor/verify/verify-20260101T000000Z-priorold"
mkdir -p "$TI1/repo/.supervisor/verify/verify-20260201T000000Z-priornew"
jq -cn '{schema_version:1, ts:"2026-01-01T00:00:00Z", run_id:"verify-20260101T000000Z-priorold", event:"ac",
  ac_id:"AC1", text:"home works (old)", scope:"ticket", verdict:"PASS", classification:null, steps:[], artifacts:[], surfaces:["home"]}
' > "$TI1/repo/.supervisor/verify/verify-20260101T000000Z-priorold/evidence.jsonl"
jq -cn '{schema_version:1, ts:"2026-02-01T00:00:00Z", run_id:"verify-20260201T000000Z-priornew", event:"ac",
  ac_id:"AC2", text:"echo works (new)", scope:"ticket", verdict:"PASS", classification:null, steps:[], artifacts:[], surfaces:["echo"]}
' > "$TI1/repo/.supervisor/verify/verify-20260201T000000Z-priornew/evidence.jsonl"
prior_out="$(bash "$RUNNER" impact prior-acs "$RDI1" --repo "$TI1/repo" --impact-limit 10)"
n="$(printf '%s' "$prior_out" | jq 'length')"
[ "$n" -eq 2 ] && ok "(I06-prior) both sibling PASS acs (home, echo) match on impact_surfaces, unbounded" || no "(I06-prior) n=$n out=$prior_out"
first_rid="$(printf '%s' "$prior_out" | jq -r '.[0].run_id')"
[ "$first_rid" = "verify-20260201T000000Z-priornew" ] && ok "(I06-prior) most-recent-first ordering (the newer prior run sorts first)" || no "(I06-prior) first_rid=$first_rid"
limited_out="$(bash "$RUNNER" impact prior-acs "$RDI1" --repo "$TI1/repo" --impact-limit 1)"
n2="$(printf '%s' "$limited_out" | jq 'length')"
[ "$n2" -eq 1 ] && [ "$(printf '%s' "$limited_out" | jq -r '.[0].run_id')" = "verify-20260201T000000Z-priornew" ] \
  && ok "(I06-prior) --impact-limit 1 keeps exactly the one most-recent match" || no "(I06-prior) n2=$n2 out=$limited_out"

echo "== (I06-prior) same-run ticket/impact scope collision on ac_id: ticket-scope PASS survives a scope-blind latest_by =="
mkdir -p "$TI1/repo/.supervisor/verify/verify-20260301T000000Z-priorcollide"
RDICOL="$TI1/repo/.supervisor/verify/verify-20260301T000000Z-priorcollide"
{
  jq -cn '{schema_version:1, ts:"2026-03-01T00:00:00Z", run_id:"verify-20260301T000000Z-priorcollide", event:"ac",
    ac_id:"AC2", text:"home works (ticket scope)", scope:"ticket", verdict:"PASS", classification:null, steps:[], artifacts:[], surfaces:["home"]}'
  jq -cn '{schema_version:1, ts:"2026-03-01T00:00:01Z", run_id:"verify-20260301T000000Z-priorcollide", event:"ac",
    ac_id:"AC2", text:"unrelated impact-scope ac reusing the same id string (a ticket id and an impact id of the same string are tracked independently)", scope:"impact", verdict:"FAIL", classification:null, steps:[], artifacts:[], surfaces:["unrelated-surface"]}'
} > "$RDICOL/evidence.jsonl"
collide_out="$(bash "$RUNNER" impact prior-acs "$RDI1" --repo "$TI1/repo" --impact-limit 10)"
collide_ac2="$(printf '%s' "$collide_out" | jq -c '[.[] | select(.run_id == "verify-20260301T000000Z-priorcollide" and .ac_id == "AC2")]')"
n3="$(printf '%s' "$collide_ac2" | jq 'length')"
[ "$n3" -eq 1 ] && [ "$(printf '%s' "$collide_ac2" | jq -r '.[0].surfaces[0]')" = "home" ] \
  && ok "(I06-prior) the ticket-scope PASS/AC2 line still surfaces as a prior candidate (latest_by is scope-partitioned, not just ac_id)" \
  || no "(I06-prior) collide_ac2=$collide_ac2 (a scope-blind latest_by would let the later impact-scope FAIL line silently win and drop this)"

# ============================================================================
echo "== (I06-browser) two routes sharing a component: impact_surfaces maps both, a seeded prior PASS ac for route B is re-run, README.md unmapped, --impact-limit 1 re-runs exactly one, mutation control flips route B to FAIL while the ticket score is unchanged =="
if [ "$PW_READY" -eq 1 ]; then
  PORT_I="$(free_port)"
  if start_app "$PORT_I"; then
    TI3="$(mktmp)"
    mkdir -p "$TI3/repo/shared"
    ( cd "$TI3/repo" && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base )
    printf 'orig\n' > "$TI3/repo/shared/component.js"; printf 'readme\n' > "$TI3/repo/README.md"
    ( cd "$TI3/repo" && git add -A && git -c user.email=t@t -c user.name=t commit -q -m first )
    IBASE="$(cd "$TI3/repo" && git rev-parse HEAD)"
    printf 'changed\n' > "$TI3/repo/shared/component.js"
    ( cd "$TI3/repo" && git add -A && git -c user.email=t@t -c user.name=t commit -q -m second )
    IHEAD="$(cd "$TI3/repo" && git rev-parse HEAD)"
    ln -s "$PW_CACHE/node_modules" "$TI3/repo/node_modules"
    RDI3="$TI3/repo/.supervisor/verify/verify-20260916T010000Z-impactrun"
    mkdir -p "$RDI3"
    jq -cn --arg base "$IBASE" --arg head "$IHEAD" '{schema_version:1, ts:"2026-09-16T01:00:00Z",
      run_id:"verify-20260916T010000Z-impactrun", event:"run_start", ticket_path:"x.md", ticket_kind:"brief",
      branch:"b", head_sha:$head, base_sha:$base, env_contract_hash:null}' > "$RDI3/evidence.jsonl"
    jq -cn '{schema_version:1, ts:"2026-09-16T01:00:01Z", run_id:"verify-20260916T010000Z-impactrun", event:"ac",
      ac_id:"AC1", text:"ticket AC unaffected by the impact pass", scope:"ticket", verdict:"PASS",
      classification:null, steps:[], artifacts:[]}' | bash "$HERE/verify-helpers.sh" evidence-append "$RDI3" - >/dev/null
    mkdir -p "$TI3/repo/.supervisor/verify/verify-20260101T020000Z-priorroute"
    jq -cn '{schema_version:1, ts:"2026-01-01T02:00:00Z", run_id:"verify-20260101T020000Z-priorroute",
      event:"ac", ac_id:"AC2", text:"route B (echo) works", scope:"ticket", verdict:"PASS", classification:null,
      steps:[], artifacts:[], surfaces:["routeB"]}' > "$TI3/repo/.supervisor/verify/verify-20260101T020000Z-priorroute/evidence.jsonl"
    printf '{"surfaces":{"routeA":["shared/component.js"],"routeB":["shared/component.js"]},"unmapped":["README.md"]}' \
      | bash "$RUNNER" impact record-surfaces "$RDI3" - --repo "$TI3/repo" --impact-limit 10 >/dev/null
    ise="$(jq -c 'select(.event=="impact_surfaces")' "$RDI3/evidence.jsonl" | tail -1)"
    [ "$(printf '%s' "$ise" | jq -r '.surfaces.routeA[0]')" = "shared/component.js" ] && [ "$(printf '%s' "$ise" | jq -r '.surfaces.routeB[0]')" = "shared/component.js" ] \
      && ok "(I06-browser) impact_surfaces names both routeA and routeB from the shared component" || no "(I06-browser) surfaces: $(printf '%s' "$ise" | jq -c '.surfaces')"
    [ "$(printf '%s' "$ise" | jq -c '.unmapped')" = '["README.md"]' ] && ok "(I06-browser) README.md lands in unmapped" || no "(I06-browser) unmapped: $(printf '%s' "$ise" | jq -c '.unmapped')"
    matched="$(bash "$RUNNER" impact prior-acs "$RDI3" --repo "$TI3/repo" --impact-limit 1)"
    n="$(printf '%s' "$matched" | jq 'length')"
    [ "$n" -eq 1 ] && [ "$(printf '%s' "$matched" | jq -r '.[0].ac_id')" = "AC2" ] \
      && ok "(I06-browser) --impact-limit 1 re-runs exactly the one seeded prior PASS ac for route B" || no "(I06-browser) matched=$matched"
    mkdir -p "$RDI3/impact-specs"
    cat > "$RDI3/impact-specs/prior-routeb.spec.ts" <<'SPECI'
import { test, expect } from '@playwright/test';
test('[prior-routeb] Given the Value field, when hello is submitted, then the echo shows hello', async ({ page }) => {
  await page.goto('/');
  await page.getByLabel('Value').fill('hello');
  await page.getByRole('button', { name: 'Submit' }).click();
  await expect(page.locator('#echo')).toHaveText('hello');
});
SPECI
    jq -n '[{id:"prior-routeb", text:"route B (echo) re-run", source:"prior_ac:verify-20260101T020000Z-priorroute/AC2", surfaces:["routeB"]}]' > "$RDI3/impact-manifest.json"
    : > "$LAST_OUT"; : > "$LAST_ERR"
    ( cd "$TI3/repo" && bash "$RUNNER" walk "$RDI3" --repo . --base-url "http://127.0.0.1:$PORT_I" --scope impact --specs-dir impact-specs --manifest "$RDI3/impact-manifest.json" ) >"$LAST_OUT" 2>"$LAST_ERR"
    rc=$?
    [ "$rc" -eq 0 ] && ok "(I06-browser) impact walk (healthy app) → exit 0" || no "(I06-browser) impact walk healthy: rc=$rc err=$(cat "$LAST_ERR")"
    last="$(jq -c 'select(.event=="ac" and .ac_id=="prior-routeb")' "$RDI3/evidence.jsonl" | tail -1)"
    [ "$(printf '%s' "$last" | jq -r '[.verdict,.scope,.source] | join("|")')" = "PASS|impact|prior_ac:verify-20260101T020000Z-priorroute/AC2" ] \
      && ok "(I06-browser) route B re-run recorded scope:impact verdict:PASS source:prior_ac:<run_id>/<ac_id>" \
      || no "(I06-browser) route B ac line: $last"
    grep -q '^PASS: 1 · FAIL: 0 · BLOCKED: 0 · NOT_VERIFIABLE: 0 · total: 1$' "$RDI3/summary.md" \
      && ok "(I06-browser) the ticket's own counts row is unaffected: still PASS:1 total:1" || no "(I06-browser) ticket row: $(grep '^PASS: ' "$RDI3/summary.md")"

    echo "-- mutation control: break route B (echo), re-run on a FRESH run dir, verdict flips FAIL, ticket unaffected --"
    kill_servers
    PORT_BROKEN="$(free_port)"
    if start_app "$PORT_BROKEN" --broken; then
      RDI4="$TI3/repo/.supervisor/verify/verify-20260916T020000Z-impactbroken"
      mkdir -p "$RDI4/impact-specs"
      cp "$RDI3/impact-specs/prior-routeb.spec.ts" "$RDI4/impact-specs/prior-routeb.spec.ts"
      cp "$RDI3/impact-manifest.json" "$RDI4/impact-manifest.json"
      jq -cn --arg base "$IBASE" --arg head "$IHEAD" '{schema_version:1, ts:"2026-09-16T02:00:00Z",
        run_id:"verify-20260916T020000Z-impactbroken", event:"run_start", ticket_path:"x.md", ticket_kind:"brief",
        branch:"b", head_sha:$head, base_sha:$base, env_contract_hash:null}' > "$RDI4/evidence.jsonl"
      jq -cn '{schema_version:1, ts:"2026-09-16T02:00:01Z", run_id:"verify-20260916T020000Z-impactbroken",
        event:"ac", ac_id:"AC1", text:"ticket AC unaffected by the impact pass", scope:"ticket", verdict:"PASS",
        classification:null, steps:[], artifacts:[]}' | bash "$HERE/verify-helpers.sh" evidence-append "$RDI4" - >/dev/null
      before_ticket_row="$(grep '^PASS: ' "$RDI4/summary.md")"
      : > "$LAST_OUT"; : > "$LAST_ERR"
      ( cd "$TI3/repo" && bash "$RUNNER" walk "$RDI4" --repo . --base-url "http://127.0.0.1:$PORT_BROKEN" --scope impact --specs-dir impact-specs --manifest "$RDI4/impact-manifest.json" ) >"$LAST_OUT" 2>"$LAST_ERR"
      last="$(jq -c 'select(.event=="ac" and .ac_id=="prior-routeb")' "$RDI4/evidence.jsonl" | tail -1)"
      [ "$(printf '%s' "$last" | jq -r '[.verdict,.classification,.scope] | join("|")')" = "FAIL|REAL_BUG|impact" ] \
        && ok "(I06-mutation) route B broken → the impact-scope verdict flips to FAIL/REAL_BUG (observed, not claimed)" \
        || no "(I06-mutation) route B (broken) ac line: $last"
      after_ticket_row="$(grep '^PASS: ' "$RDI4/summary.md")"
      [ "$after_ticket_row" = "$before_ticket_row" ] && [ "$after_ticket_row" = "PASS: 1 · FAIL: 0 · BLOCKED: 0 · NOT_VERIFIABLE: 0 · total: 1" ] \
        && ok "(I06-mutation) the ticket's own counts row is BYTE-IDENTICAL before/after the impact-scope FAIL ($after_ticket_row)" \
        || no "(I06-mutation) ticket row before='$before_ticket_row' after='$after_ticket_row'"
    else
      no "(I06-mutation) could not start the --broken fixture app"
    fi
  else
    no "(I06-browser) could not start the healthy fixture app"
  fi
else
  echo "  SKIP (I06-browser / I06-mutation) — playwright unavailable ($PW_SKIP); mechanical (I06-*) arms above still decide the exit"
fi

# ============================================================================
echo "== (I06-noimpact) --no-impact: ticket counts in summary.md are byte-identical with/without the impact pass =="
TI5="$(mktmp)"
mkdir -p "$TI5/repo/.supervisor/verify/withimpact" "$TI5/repo/.supervisor/verify/noimpact"
( cd "$TI5/repo" && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base )
for rd_name in withimpact noimpact; do
  RD="$TI5/repo/.supervisor/verify/$rd_name"
  jq -cn --arg rid "verify-20260916T000000Z-$rd_name" '{schema_version:1, ts:"2026-09-16T00:00:00Z", run_id:$rid,
    event:"run_start", ticket_path:"x.md", ticket_kind:"brief", branch:"b", head_sha:"h", base_sha:"h", env_contract_hash:null}
  ' > "$RD/evidence.jsonl"
  jq -cn --arg rid "verify-20260916T000000Z-$rd_name" '{schema_version:1, ts:"2026-09-16T00:00:01Z", run_id:$rid,
    event:"ac", ac_id:"AC1", text:"t", scope:"ticket", verdict:"PASS", classification:null, steps:[], artifacts:[]}
  ' | bash "$HERE/verify-helpers.sh" evidence-append "$RD" - >/dev/null
done
bash "$RUNNER" impact record-surfaces "$TI5/repo/.supervisor/verify/noimpact" '{}' --repo "$TI5/repo" --no-impact
printf '{"surfaces":{"home":[]},"unmapped":[]}' | bash "$RUNNER" impact record-surfaces "$TI5/repo/.supervisor/verify/withimpact" - --repo "$TI5/repo" --impact-limit 10 >/dev/null
jq -cn '{schema_version:1, ts:"2026-09-16T00:00:02Z", run_id:"verify-20260916T000000Z-withimpact", event:"ac",
  ac_id:"smoke-home", text:"home smoke", scope:"impact", verdict:"FAIL", classification:"REAL_BUG",
  reason:"broke", steps:[], artifacts:[], source:"smoke"}' \
  | bash "$HERE/verify-helpers.sh" evidence-append "$TI5/repo/.supervisor/verify/withimpact" - >/dev/null
row_no="$(grep '^PASS: ' "$TI5/repo/.supervisor/verify/noimpact/summary.md")"
row_with="$(grep '^PASS: ' "$TI5/repo/.supervisor/verify/withimpact/summary.md")"
[ "$row_no" = "$row_with" ] && [ "$row_no" = "PASS: 1 · FAIL: 0 · BLOCKED: 0 · NOT_VERIFIABLE: 0 · total: 1" ] \
  && ok "(I06-noimpact) ticket PASS/FAIL/BLOCKED/NOT_VERIFIABLE row is byte-identical with/without the impact pass ($row_no)" \
  || no "(I06-noimpact) no-impact row='$row_no' with-impact row='$row_with'"

echo "== (I06-docs) skill §9 + qa-executor Impact Pass step + verify.md flags are present =="
grep -qF -- '## 9. Impact pass' "$SKILL" && ok "(I06-docs) skill has a ## 9. Impact pass section" || no "(I06-docs) skill missing ## 9. Impact pass"
grep -qF -- "ticket's own PASS/FAIL/BLOCKED/NOT_VERIFIABLE counts are unchanged by it" "$SKILL" \
  && ok "(I06-docs) the checklist asserts the ticket-score-isolation invariant" || no "(I06-docs) checklist bullet missing"
grep -qF -- '**Impact Pass**' "$AGENT" && ok "(I06-docs) qa-executor.md names the Impact Pass step" || no "(I06-docs) Impact Pass step missing from qa-executor.md"
grep -qF -- '--impact-limit' "$VERIFY_CMD" && grep -qF -- '--no-impact' "$VERIFY_CMD" \
  && ok "(I06-docs) commands/verify.md documents --impact-limit and --no-impact" || no "(I06-docs) impact flags missing from commands/verify.md"

# ============================================================================
echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
