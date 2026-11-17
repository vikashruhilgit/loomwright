#!/usr/bin/env bash
# test-auth-run.sh — pins what `selvedge run` does with sign-in (selvedge/lib/runner/run.mjs,
# runner/auth-check.mjs, the storage state through runner/execute.mjs): qa-split item 05 AC1 (the
# `run` half), AC5–AC9. Every arm turns red under its row of the brief's pin-mutation table.
#
# Two parts:
#   1. no-browser arms (always run): SELVEDGE_PLAYWRIGHT_MODULE is tests/fixtures/stub-playwright.mjs
#      (chromium.launch appends `launch` to $STUB_PW_LOG; with $STUB_PW_OPTS_LOG it logs each
#      newContext's options; $STUB_PW_COUNTS makes the sign-in locator match nothing). The sign-in
#      session itself is real: `selvedge auth setup` runs an approved auth_setup hook that signs in to
#      the fixture app (tests/fixtures/app-server.mjs /login) and writes its cookie as a storage state.
#   2. real-Chromium arms against the fixture app's login wall (/account, whose requests the app
#      counts: "exactly one check request" reads that counter) with Playwright from
#      tests/lib/playwright-cache.sh. Under CI an install failure is a hard FAIL; outside CI a SKIP.
#
# Plans are hand-written (the generator in tests/lib/run-helpers.sh) and frozen with `selvedge plan
# --init` + `--freeze`, no planner; AC9's planner arm runs the default planner against a PATH-stub
# `claude` (tests/fixtures/stub-claude.sh) that records its argv (the prompt) and what the
# `selvedge snapshot` it runs hands back. Hermetic: a fresh temp HOME (PLAYWRIGHT_BROWSERS_PATH is
# exported BEFORE HOME moves), temp git repos, a recording SELVEDGE_PLANNER and PATH-stub claude for
# every run (asserted never called), no network beyond the helper's pinned install. stdin is /dev/null for every run (not a terminal). Needs node and git.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$TESTS_DIR/.." && pwd)"
CLI="$PLUGIN_DIR/bin/selvedge"
LIB="$PLUGIN_DIR/lib"
APP="$TESTS_DIR/fixtures/app-server.mjs"
export STUB_PW="$TESTS_DIR/fixtures/stub-playwright.mjs"
export SELVEDGE_LIB="$LIB"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "  ok   $1"; }
ko() { fail=$((fail + 1)); echo "  FAIL $1"; }
finish() { echo "test-auth-run: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }

for tool in node git; do
  command -v "$tool" >/dev/null 2>&1 || { echo "  FAIL $tool is not on PATH (test-auth-run.sh needs it)"; echo "test-auth-run: 0 passed, 1 failed"; exit 1; }
done

# shellcheck source=lib/playwright-cache.sh
. "$TESTS_DIR/lib/playwright-cache.sh"   # exports PLAYWRIGHT_BROWSERS_PATH while HOME is still real

TMP="$(mktemp -d "${TMPDIR:-/tmp}/selvedge-auth-run.XXXXXX")" || exit 1
TMP="$(cd "$TMP" && pwd)"
SRV_PID=""
cleanup() {
  if [ -n "$SRV_PID" ]; then
    kill "$SRV_PID" 2>/dev/null
    wait "$SRV_PID" 2>/dev/null
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
REAL_HOME="$HOME"
export HOME="$TMP/home"
export GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$TMP/o"
unset SELVEDGE_PLANNER SELVEDGE_PLAYWRIGHT_MODULE SELVEDGE_ENTRY SELVEDGE_RUN_BUDGET_MS \
  SELVEDGE_PLANNER_TOKEN_BUDGET SELVEDGE_STEP_TIMEOUT_MS SELVEDGE_RUN_DIR SELVEDGE_BASE NODE_PATH \
  PLAYWRIGHT_DISABLE_FORCED_CHROMIUM_PROXIED_LOOPBACK STUB_PW_GOTO_MS STUB_PW_TEXT STUB_PW_COUNTS \
  STUB_PW_COUNTS_FILE STUB_PW_OPTS_LOG STUB_PLANNER_MODE STUB_PLANNER_LOG SELVEDGE_STORAGE_STATE \
  SELVEDGE_AUTH_TIMEOUT_MS
export APP_USER='alice-7Qx'
export APP_PASS='pw-Zk93-fixture-never-printed'
export AUTH_HOOK_MARKER="$TMP/auth-hook-ran.log"

# shellcheck source=lib/run-helpers.sh
. "$TESTS_DIR/lib/run-helpers.sh"   # the fixture app, newrepo, folder, stub_spec, the planner shims
rh_start_app
rh_setup
export STUB_PW_LOG="$TMP/launches.log"
export STUB_PW_OPTS_LOG="$TMP/opts.log"
STUB="SELVEDGE_PLAYWRIGHT_MODULE=$STUB_PW"
FAST="SELVEDGE_STEP_TIMEOUT_MS=400"   # a failing sign-in check waits this long for its locator
NOMATCH='STUB_PW_COUNTS={"testid:signed-in-as":0}'

# run <label> <run-dir> [<env args>…] — `selvedge run $RUN_FLAGS <run-dir>` in $RUN_CWD with the
# recording planner shims, `env <env args>` and stdin /dev/null; sets OUT / ERR (files), RC and DIR;
# empties the launch and options logs first. A run-dir of "-" passes only $RUN_FLAGS (--replay).
run() {
  local label="$1" dir="$2"; shift 2
  OUT="$TMP/o/$label.out"; ERR="$TMP/o/$label.err"
  : > "$STUB_PW_LOG"; : > "$STUB_PW_OPTS_LOG"
  local args=()
  # shellcheck disable=SC2206  # RUN_FLAGS is a space-separated flag list on purpose
  [ -n "${RUN_FLAGS:-}" ] && args=($RUN_FLAGS)
  [ "$dir" != "-" ] && args+=("$dir")
  (cd "$RUN_CWD" && env "SELVEDGE_PLANNER=sh $TMP/planner-shim.sh" "PATH=$TMP/stubbin:$PATH" "$@" bash "$CLI" run "${args[@]}" >"$OUT" 2>"$ERR" </dev/null); RC=$?
  DIR="$dir"
  export OUT ERR RC DIR
}

# check <label> <js expression> — over the last run(): out err rc, ev (evidence lines), vj ids vc(i),
# has(n) f(n), txt(p) jl(p), launches() (`launch` lines), ctxs() (each newContext's options, parsed),
# runLines(repo) (the event:"run" lines of <repo>/.selvedge/runs.jsonl).
check() {
  local label="$1" expr="$2" got
  got="$(node -e '
const fs = require("fs");
const path = require("path");
const E = process.env;
const txt = (p) => { try { return fs.readFileSync(p, "utf8"); } catch { return ""; } };
const jl = (p) => txt(p).split("\n").filter((l) => l.trim() !== "").map((l) => JSON.parse(l));
const out = txt(E.OUT), err = txt(E.ERR), rc = Number(E.RC);
const f = (n) => { try { return fs.readFileSync(path.join(E.DIR, n), "utf8"); } catch { return null; } };
const has = (n) => fs.existsSync(path.join(E.DIR, n));
const ev = jl(path.join(E.DIR, "evidence.jsonl"));
const vj = f("verdict.json") === null ? null : JSON.parse(f("verdict.json"));
const ids = Object.keys(JSON.parse(f("plan.json") || "{\"steps_by_criterion\":{}}").steps_by_criterion);
const vc = (i) => vj.criteria[ids[i]];
const launches = () => txt(E.STUB_PW_LOG).split("\n").filter((l) => l === "launch").length;
const ctxs = () => txt(E.STUB_PW_OPTS_LOG).split("\n").filter((l) => l.startsWith("newContext ")).map((l) => JSON.parse(l.slice(11)));
const runLines = (repo) => jl(repo + "/.selvedge/runs.jsonl").filter((l) => l.event === "run");
const lastOut = () => out.trim().split("\n").pop();
let v;
try { v = eval(process.argv[1]); } catch (e) { v = "error: " + e.message; }
if (v === true) process.stdout.write("true");
else process.stdout.write("false (" + String(v).slice(0, 80) + ") rc=" + E.RC + " out=" + JSON.stringify(out.slice(0, 400)) + " err=" + JSON.stringify(err.slice(-900)) + " verdict=" + JSON.stringify(vj && vj.criteria).slice(0, 500));
' "$expr" 2>&1)"
  if [ "$got" = "true" ]; then ok "$label"; else ko "$label — $got"; fi
}

# approve <repo> — records the approval of the repo's current hooks (as `selvedge env approve` would).
approve() {
  (cd "$1" && node --input-type=module -e "
import { pathToFileURL } from 'node:url';
const A = await import(pathToFileURL(process.env.SELVEDGE_LIB + '/env-approvals.mjs').href);
const E = await import(pathToFileURL(process.env.SELVEDGE_LIB + '/env-config.mjs').href);
const { config, root } = E.loadConfig();
A.writeApproval({ root, identity: A.repoIdentity(root), sha256: A.hooksSha256(config.hooks) });")
}

# state_of <repo> — the storage state path selvedge keeps for the repo (auth-state.mjs authStatePath).
state_of() {
  (cd "$1" && node --input-type=module -e "
import { pathToFileURL } from 'node:url';
const S = await import(pathToFileURL(process.env.SELVEDGE_LIB + '/auth-state.mjs').href);
const E = await import(pathToFileURL(process.env.SELVEDGE_LIB + '/env-config.mjs').href);
process.stdout.write(S.authStatePath({ root: E.repoRoot() }));")
}

# authrepo <dir> <locator JSON> — a repo whose selvedge.json has the auth block (env APP_USER /
# APP_PASS, the check at /account with <locator>) and an auth_setup hook that signs in to the fixture
# app and writes the cookie as a storage state (appending a line to $AUTH_HOOK_MARKER each time it
# runs); the hook is approved.
authrepo() {
  local dir="$1" loc="$2"
  newrepo "$dir"
  cat > "$dir/login-hook.mjs" <<'EOF'
import { appendFileSync, writeFileSync } from 'node:fs';
import http from 'node:http';
appendFileSync(process.env.AUTH_HOOK_MARKER, 'auth_setup\n');
const body = new URLSearchParams({ user: process.env.APP_USER, pass: process.env.APP_PASS }).toString();
const port = new URL(process.env.AURL).port;
const req = http.request({ host: '127.0.0.1', port, path: '/login', method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded', 'content-length': Buffer.byteLength(body) } }, (res) => {
  res.resume();
  const pair = String((res.headers['set-cookie'] || [])[0] || '').split(';')[0];
  const eq = pair.indexOf('=');
  if (res.statusCode !== 303 || eq < 1) { process.stderr.write('the fixture app refused the sign-in\n'); process.exit(1); }
  const cookie = { name: pair.slice(0, eq), value: pair.slice(eq + 1), domain: 'localhost', path: '/', expires: -1, httpOnly: true, secure: false, sameSite: 'Lax' };
  writeFileSync(process.env.SELVEDGE_STORAGE_STATE, JSON.stringify({ cookies: [cookie], origins: [] }));
});
req.on('error', (e) => { process.stderr.write(`${e.message}\n`); process.exit(1); });
req.end(body);
EOF
  node -e 'const [f, o, loc] = process.argv.slice(1); require("fs").writeFileSync(f, JSON.stringify({ schema_version: 1, origins: [o], hooks: { auth_setup: "node login-hook.mjs" }, auth: { env: ["APP_USER", "APP_PASS"], signed_in_check: { url: o + "/account", locator: JSON.parse(loc) } } }));' \
    "$dir/selvedge.json" "$AURL" "$loc"
  approve "$dir"
}

# hits — how many requests /account has had (the fixture app's counter).
hits() { node -e 'fetch(process.env.AURL + "/control/hits?path=/account").then((r) => r.text()).then((t) => process.stdout.write(t.trim()))'; }

marker_lines() { [ -f "$AUTH_HOOK_MARKER" ] && grep -c '^auth_setup$' "$AUTH_HOOK_MARKER" || echo 0; }

# AUTH_C — one criterion reading the walled page's "Signed in as" line; PW_C — one reading the line
# that shows the password.
AUTH_C='{"text":"The account page reads \"Signed in as alice-7Qx\"","steps":[{"type":"goto","url":"$O/account"},{"type":"read","property":"text","locator":{"testid":"signed-in-as"}},{"type":"expect","op":"equals","value":"Signed in as alice-7Qx"}]}'
PW_C='{"text":"The account page shows \"Your password is\"","steps":[{"type":"goto","url":"$O/account"},{"type":"read","property":"text","locator":{"testid":"password-echo"}},{"type":"expect","op":"contains","value":"Your password is"}]}'

echo "-- static: auth-check.mjs is imported, never copied"
{ grep -qE "import \{[^}]*signedInGate[^}]*\} from './auth-check.mjs'" "$LIB/runner/run.mjs" \
  && grep -qE "import \{[^}]*validateSignedInCheck[^}]*\} from '../auth-state.mjs'" "$LIB/runner/run.mjs" \
  && ! grep -qE "^(export )?(async )?function (checkSignedIn|signedInGate)\b" "$LIB/runner/run.mjs" \
  && grep -qE "^export const RUN_HOOKS = Object.freeze\(\['reset', 'seed'\]\);" "$LIB/runner/run.mjs"; } \
  && ok "run.mjs imports signedInGate and validateSignedInCheck (defines neither check) and RUN_HOOKS stays reset, seed" \
  || ko "run.mjs copies the sign-in check, or RUN_HOOKS changed"
n="$(grep -cE "(from|import\() *['\"]playwright" "$LIB/runner/auth-check.mjs")"
[ "$n" = "0" ] && ok "auth-check.mjs never imports playwright by name" || ko "auth-check.mjs imports playwright ($n)"

echo "-- AC11 the README documents auth setup, the auth key, where the session lives, needs_auth and the honest limit"
RD="$PLUGIN_DIR/README.md"
missing=""
for s in 'selvedge auth setup [--headed]' '## `auth` and the sign-in check' '- `auth` — optional' \
  '$HOME/.local/state/selvedge/<repo-id>/auth/storageState.json' '`0700`' '`0600`' '--non-interactive' \
  'BLOCKED `needs_auth`' 'There is no retry loop' 'SELVEDGE_AUTH_TIMEOUT_MS' 'SELVEDGE_STORAGE_STATE' \
  'An agent with shell access can read any file you can' \
  'selvedge keeps secrets out of plans, evidence, PR comments and model' 'does not claim they are out of reach'; do
  grep -qF -- "$s" "$RD" || missing="$missing [$s]"
done
grep -qE '^\| `needs_auth` \| BLOCKED \|' "$RD" || missing="$missing [needs_auth reasons row]"
[ -z "$missing" ] && ok "AC11 README.md documents selvedge auth setup [--headed], the auth key, the state path and modes, needs_auth (one check, no retry, --non-interactive) and the honest-limit paragraph" \
  || ko "AC11 README misses:$missing"

echo "-- AC1 run refuses a CSS sign-in locator before anything is claimed or launched (stub browser)"
RC1="$TMP/repo-css"; authrepo "$RC1" '{"testid":"signed-in-as"}'
F1="$(folder ac1 "$RC1" "$(stub_spec 1)")"
[ -n "$F1" ] && ok "setup: a frozen folder in a repo with auth.signed_in_check" || ko "setup: folder ac1: $(cat "$TMP/o/freeze-ac1.err" 2>/dev/null)"
RUN_CWD="$RC1" run ac1-ok "$F1" "$STUB"
check "setup: with a testid locator the folder runs (exit 0, PASS)" 'rc === 0 && vc(0).verdict === "PASS"'
F1b="$(folder ac1b "$RC1" "$(stub_spec 2)")"
node -e 'const f = process.argv[1]; const c = JSON.parse(require("fs").readFileSync(f, "utf8")); c.auth.signed_in_check.locator = { css: "#account .name" }; require("fs").writeFileSync(f, JSON.stringify(c));' "$RC1/selvedge.json"
RUN_CWD="$RC1" run ac1-css "$F1b" "$STUB"
check "AC1 a CSS sign-in locator: selvedge run exits 2 config_schema_violation naming auth.signed_in_check; no run.claim, no evidence, nothing launched" \
  'rc === 2 && err.includes("config_schema_violation") && err.includes("auth.signed_in_check") && !has("run.claim") && !has("evidence.jsonl") && launches() === 0 && !out.includes("BLOCKED")'
before="$(find "$RC1/.selvedge/runs" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
RUN_FLAGS="--replay $F1" RUN_CWD="$RC1" run ac1-replay - "$STUB"
after="$(find "$RC1/.selvedge/runs" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
check "AC1 --replay under a CSS sign-in locator: exit 2 config_schema_violation, nothing launched" \
  'rc === 2 && err.includes("config_schema_violation") && launches() === 0'
[ "$before" = "$after" ] && ok "AC1 --replay refused: no new run folder is left behind" || ko "replay left a folder ($before -> $after)"

echo "-- AC5 no session, nobody to sign in: every criterion BLOCKED needs_auth after ONE check (stub browser)"
R5="$TMP/repo5"; authrepo "$R5" '{"testid":"signed-in-as"}'; export R5
F5="$(folder ac5 "$R5" "$(stub_spec 3 4)")"
RUN_FLAGS="--non-interactive" RUN_CWD="$R5" run ac5 "$F5" "$STUB" "$FAST" "$NOMATCH"
check "AC5 --non-interactive, the check locator matches nothing: exit 2, every criterion BLOCKED needs_auth, stdout ends \`verdict BLOCKED …\`" \
  'rc === 2 && ids.length === 2 && ids.every((id) => vj.criteria[id].verdict === "BLOCKED" && vj.criteria[id].reason === "needs_auth") && lastOut().startsWith("verdict BLOCKED ")'
check "AC5 exactly one browser launch (the one check; no retry), no criterion step ran, run_start first and run_end written, one runs.jsonl line" \
  'launches() === 1 && ev.filter((l) => l.kind === "step").length === 0 && ev[0].kind === "run_start" && ev[ev.length - 1].kind === "run_end" && runLines(E.R5).filter((l) => l.run_id === path.basename(E.DIR)).length === 1'
check "AC5 stderr says needs_auth and names \`selvedge auth setup --headed\`" 'err.includes("needs_auth") && err.includes("selvedge auth setup --headed")'
F5b="$(folder ac5b "$R5" "$(stub_spec 5)")"
RUN_CWD="$R5" run ac5-notty "$F5b" "$STUB" "$FAST" "$NOMATCH"
check "AC5 no --non-interactive but stdin not a terminal: the same outcome (BLOCKED needs_auth, exit 2, one launch)" \
  'rc === 2 && vc(0).reason === "needs_auth" && launches() === 1 && ev.filter((l) => l.kind === "step").length === 0'

echo "-- AC6 the stored session reaches the check and every criterion context (stub browser)"
F6n="$(folder ac6-nostate "$R5" "$(stub_spec 6 7)")"
RUN_CWD="$R5" run ac6-nostate "$F6n" "$STUB"
check "AC6 no state file (the check passes on the stub): every newContext gets exactly {serviceWorkers: \"block\"}, one per check + criterion" \
  'rc === 0 && ctxs().length === 3 && ctxs().every((o) => JSON.stringify(o) === JSON.stringify({ serviceWorkers: "block" }))'
(cd "$R5" && bash "$CLI" auth setup >"$TMP/o/setup5.out" 2>"$TMP/o/setup5.err" </dev/null); src=$?
S5="$(state_of "$R5")"; export S5
{ [ "$src" -eq 0 ] && [ -f "$S5" ] && [ "$(marker_lines)" = "1" ]; } && ok "setup: selvedge auth setup (the approved hook signs in to the fixture app) saved the session" \
  || ko "setup: auth setup rc=$src state=$S5: $(cat "$TMP/o/setup5.err")"
F6="$(folder ac6 "$R5" "$(stub_spec 8 9)")"
RUN_CWD="$R5" run ac6 "$F6" "$STUB"
check "AC6 with the state file: exit 0 PASS, and the check context and both criterion contexts got storageState: <the state path>" \
  'rc === 0 && vc(0).verdict === "PASS" && vc(1).verdict === "PASS" && ctxs().length === 3 && ctxs().every((o) => o.storageState === E.S5 && o.serviceWorkers === "block" && Object.keys(o).length === 2)'
RN="$TMP/repo-noauth"; newrepo "$RN"
FN="$(folder noauth "$RN" "$(stub_spec 10 11)")"
RUN_CWD="$RN" run noauth "$FN" "$STUB" "$NOMATCH"
check "no auth key in selvedge.json: no sign-in check (one launch per criterion), every newContext exactly {serviceWorkers: \"block\"}" \
  'rc === 0 && launches() === 2 && ctxs().every((o) => JSON.stringify(o) === JSON.stringify({ serviceWorkers: "block" }))'

echo "-- AC7 a rejected session: needs_auth after one check; run never runs auth_setup (stub browser)"
F7="$(folder ac7 "$R5" "$(stub_spec 12 13)")"
RUN_FLAGS="--non-interactive" RUN_CWD="$R5" run ac7 "$F7" "$STUB" "$FAST" "$NOMATCH"
check "AC7 a stored session the check rejects: every criterion BLOCKED needs_auth, exit 2, one launch, opened with the state" \
  'rc === 2 && ids.every((id) => vj.criteria[id].reason === "needs_auth") && launches() === 1 && ctxs().length === 1 && ctxs()[0].storageState === E.S5 && err.includes("stored session")'
[ "$(marker_lines)" = "1" ] && ok "AC7 the auth_setup hook ran only for \`selvedge auth setup\` (marker: 1 line), never from a run" \
  || ko "AC7 the auth_setup hook ran $(marker_lines) times"
cp "$S5" "$TMP/state-copy.json"
printf '{"cookies": [' > "$S5"
F7c="$(folder ac7-corrupt "$R5" "$(stub_spec 14)")"
RUN_FLAGS="--non-interactive" RUN_CWD="$R5" run ac7-corrupt "$F7c" "$STUB"
check "a stored session file that is not JSON: BLOCKED needs_auth naming the file (never playwright_unavailable), no browser opened" \
  'rc === 2 && vc(0).reason === "needs_auth" && err.includes("is not valid JSON") && err.includes(E.S5) && launches() === 0'
cp "$TMP/state-copy.json" "$S5"

echo "-- AC8 the interactive gate: one prompt, one line, one more check (stub browser)"
export COUNTS_FILE="$TMP/counts.json"
gate="$(STUB_PW_COUNTS_FILE="$COUNTS_FILE" node --input-type=module -e "
import { readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
const A = await import(pathToFileURL(process.env.SELVEDGE_LIB + '/runner/auth-check.mjs').href);
const { chromium } = await import(pathToFileURL(process.env.STUB_PW).href);
const E = process.env;
const config = { schema_version: 1, origins: [E.AURL], allow_remote: false, allow_remote_mutation: false, hooks: {}, auth: { env: [], signed_in_check: { url: E.AURL + '/account', locator: { testid: 'signed-in-as' } } } };
const launches = () => readFileSync(E.STUB_PW_LOG, 'utf8').split('\n').filter((l) => l === 'launch').length;
const scenario = async (name, { interactive, first, onRead }) => {
  writeFileSync(E.STUB_PW_LOG, '');
  writeFileSync(E.COUNTS_FILE, JSON.stringify({ 'testid:signed-in-as': first }));
  const said = [];
  let reads = 0;
  const r = await A.signedInGate({ chromium, config, interactive, stepTimeoutMs: 200, say: (l) => said.push(l),
    readLine: async () => { reads += 1; if (onRead !== undefined) writeFileSync(E.COUNTS_FILE, JSON.stringify({ 'testid:signed-in-as': onRead })); return ''; } });
  return { name, signedIn: r.signedIn, reason: r.reason || null, reads, launches: launches(), said: said.join(' | ') };
};
const out = [];
out.push(await scenario('fixed', { interactive: true, first: 0, onRead: 1 }));
out.push(await scenario('still', { interactive: true, first: 0, onRead: 0 }));
out.push(await scenario('nonint', { interactive: false, first: 0, onRead: 1 }));
out.push(await scenario('fine', { interactive: true, first: 1 }));
process.stdout.write(JSON.stringify(out));
" 2>"$TMP/o/gate.err")"
export GATE="$gate"
g() {
  local label="$1" expr="$2" got
  got="$(node -e 'let v; try { const G = Object.fromEntries(JSON.parse(process.env.GATE).map((s) => [s.name, s])); v = eval(process.argv[1]); } catch (e) { v = "error: " + e.message; } process.stdout.write(v === true ? "true" : "false (" + String(v).slice(0, 80) + ") gate=" + String(process.env.GATE).slice(0, 900));' "$expr" 2>&1)"
  if [ "$got" = "true" ]; then ok "$label"; else ko "$label — $got $(tail -n 3 "$TMP/o/gate.err")"; fi
}
g "AC8 interactive, the first check fails and the person signs in: the gate names \`selvedge auth setup --headed\`, reads exactly one line, checks once more (two launches) and goes on" \
  'const s = G.fixed; s.signedIn === true && s.reads === 1 && s.launches === 2 && s.said.includes("selvedge auth setup --headed")'
g "AC8 interactive, the second check fails too: needs_auth after exactly two checks and one read (never a third check)" \
  'const s = G.still; s.signedIn === false && s.reason === "needs_auth" && s.reads === 1 && s.launches === 2'
g "AC8 non-interactive: readLine is never called and the check runs once (needs_auth)" \
  'const s = G.nonint; s.signedIn === false && s.reason === "needs_auth" && s.reads === 0 && s.launches === 1 && s.said.includes("selvedge auth setup --headed")'
g "AC8 a first check that passes: no prompt, no read, one check" \
  'const s = G.fine; s.signedIn === true && s.reads === 0 && s.launches === 1 && s.said === ""'

echo "-- AC9 auth.env values never reach evidence, verdict, runs.jsonl, stdout / stderr or the planner prompt"
F9="$(folder ac9 "$R5" '{"criteria":[{"text":"The account line shows \"Your password is\"","steps":[{"type":"goto","url":"$O/"},{"type":"read","property":"text","locator":{"testid":"x"}},{"type":"expect","op":"contains","value":"Your password is"}]}]}')"
RUN_CWD="$R5" run ac9 "$F9" "$STUB" "STUB_PW_TEXT=Your password is $APP_PASS"
check "AC9 (stub) a page that shows APP_PASS: PASS, and its read is written as {{APP_PASS}} in evidence.jsonl and verdict.json" \
  'rc === 0 && vc(0).verdict === "PASS" && ev.find((l) => l.type === "read").value === "Your password is {{APP_PASS}}" && vc(0).read_value === "Your password is {{APP_PASS}}"'
leak="$(grep -rlF --exclude-dir=screenshots "$APP_PASS" "$F9" "$R5/.selvedge/runs.jsonl" "$OUT" "$ERR" 2>/dev/null)"
[ -z "$leak" ] && ok "AC9 (stub) grep -rF \$APP_PASS over the run folder (screenshots aside), runs.jsonl and the run's stdout / stderr finds nothing" \
  || ko "AC9 (stub) the password leaked into: $leak"
STUBCLAUDE="$TMP/stubclaude"; mkdir -p "$STUBCLAUDE"
printf '#!/bin/sh\nexec bash "%s" "$@"\n' "$TESTS_DIR/fixtures/stub-claude.sh" > "$STUBCLAUDE/claude"
chmod +x "$STUBCLAUDE/claude"
printf -- '- The account page reads "Signed in as alice-7Qx"\n' | (cd "$R5" && bash "$CLI" criteria from-text) > "$TMP/crit-plan9.json" 2>/dev/null
# The planner looks at a page that shows APP_PASS (the stub page's text) through `selvedge snapshot`,
# as a model would; what snapshot hands back is what reaches the model besides the prompt.
SNAP9="$TMP/claude-snapshot.txt"
P9="$(cd "$R5" && env -u SELVEDGE_PLANNER "PATH=$STUBCLAUDE:$PATH" STUB_CLAUDE_ARGV="$TMP/claude-argv.json" STUB_CLAUDE_SNAPSHOT_OUT="$SNAP9" \
  "$STUB" "STUB_PW_TEXT=Your password is $APP_PASS" bash "$CLI" plan "$TMP/crit-plan9.json" 2>"$TMP/o/plan9.err" </dev/null)"; prc=$?
{ [ "$prc" -eq 0 ] && [ -s "$TMP/claude-argv.json" ] && grep -qF 'Signed in as alice-7Qx' "$TMP/claude-argv.json"; } \
  && ok "setup: selvedge plan ran the default planner (the PATH-stub claude recorded its prompt)" || ko "setup: plan rc=$prc: $(tail -n 3 "$TMP/o/plan9.err")"
grep -qF 'Your password is {{APP_PASS}}' "$SNAP9" \
  && ok "AC9 the planner's snapshot of a page that shows APP_PASS reads it back as {{APP_PASS}} (auth.env values are snapshot's redaction list too)" \
  || ko "AC9 the planner's snapshot did not show {{APP_PASS}}: $(head -c 600 "$SNAP9" 2>/dev/null)"
leak="$(grep -rlF "$APP_PASS" "$TMP/claude-argv.json" "$SNAP9" "$P9" "$TMP/o/plan9.err" 2>/dev/null)"
[ -z "$leak" ] && ok "AC9 the planner prompt (claude's argv), the snapshot it read, the plan folder and plan's stderr do not contain APP_PASS" \
  || ko "AC9 the password reached the planner: $leak"

echo "-- a stored session Playwright would not load, with auth but no signed_in_check: needs_auth, no browser (stub browser)"
RS="$TMP/repo-nocheck"; newrepo "$RS"
node -e 'const [f, o] = process.argv.slice(1); require("fs").writeFileSync(f, JSON.stringify({ schema_version: 1, origins: [o], auth: { env: ["APP_USER", "APP_PASS"] } }));' "$RS/selvedge.json" "$AURL"
SS="$(state_of "$RS")"; export SS
mkdir -p "$(dirname "$SS")"
printf '{"cookies": [' > "$SS"
FS1="$(folder nocheck-json "$RS" "$(stub_spec 15)")"
RUN_CWD="$RS" run nocheck-json "$FS1" "$STUB"
check "no signed_in_check, a stored session that is not JSON: BLOCKED needs_auth naming the file (never playwright_unavailable), no browser opened" \
  'rc === 2 && vc(0).reason === "needs_auth" && err.includes("is not valid JSON") && err.includes(E.SS) && launches() === 0 && ev[ev.length - 1].kind === "run_end"'
printf '{"cookies": [{"name": "s", "value": "v"}]}' > "$SS"
FS2="$(folder nocheck-shape "$RS" "$(stub_spec 16)")"
RUN_CWD="$RS" run nocheck-shape "$FS2" "$STUB"
check "no signed_in_check, a JSON object Playwright refuses (a cookie with no url and no domain/path): BLOCKED needs_auth, no browser opened" \
  'rc === 2 && vc(0).reason === "needs_auth" && err.includes("cookies[0]") && launches() === 0'
printf '{"cookies": "none"}' > "$S5"
F7s="$(folder ac7-shape "$R5" "$(stub_spec 17)")"
RUN_FLAGS="--non-interactive" RUN_CWD="$R5" run ac7-shape "$F7s" "$STUB"
check "with signed_in_check, a JSON object Playwright refuses (cookies not an array): BLOCKED needs_auth from the check, no browser opened" \
  'rc === 2 && vc(0).reason === "needs_auth" && err.includes("cookies is not an array") && launches() === 0'
cp "$TMP/state-copy.json" "$S5"
printf '{"cookies":[],"origins":[]}' > "$SS"
FS3="$(folder nocheck-ok "$RS" "$(stub_spec 18)")"
RUN_CWD="$RS" run nocheck-ok "$FS3" "$STUB"
check "no signed_in_check, a stored session Playwright loads: the criterion runs (PASS) from it" \
  'rc === 0 && vc(0).verdict === "PASS" && ctxs().length === 1 && ctxs()[0].storageState === E.SS'

echo "-- real Chromium: AC5, AC6, AC7, AC9 against the fixture app's login wall"
HOME="$REAL_HOME" pw_require_or_skip; pwrc=$?
if [ "$pwrc" -eq 1 ]; then
  ko "playwright_install_failed under CI: no browser arm can run"
  finish
fi
if [ "$pwrc" -eq 0 ]; then
  PW="SELVEDGE_PLAYWRIGHT_MODULE=$PW_MODULE"
  RR="$TMP/repo-real"; authrepo "$RR" '{"testid":"signed-in-as"}'; export RR
  : > "$AUTH_HOOK_MARKER"

  FR5="$(folder r5 "$RR" "{\"criteria\":[$AUTH_C,$PW_C]}")"
  h0="$(hits)"
  RUN_FLAGS="--non-interactive" RUN_CWD="$RR" run r5 "$FR5" "$PW" SELVEDGE_STEP_TIMEOUT_MS=1000
  h1="$(hits)"
  check "AC5 (Chromium) no session, --non-interactive: every criterion BLOCKED needs_auth, exit 2, stdout ends \`verdict BLOCKED …\`, no step line, run_end written" \
    'rc === 2 && ids.every((id) => vj.criteria[id].reason === "needs_auth") && lastOut().startsWith("verdict BLOCKED ") && ev.filter((l) => l.kind === "step").length === 0 && ev[ev.length - 1].kind === "run_end"'
  [ "$((h1 - h0))" -eq 1 ] && ok "AC5 (Chromium) the fixture app counted exactly ONE request to the check URL" || ko "AC5 /account requests: $h0 -> $h1"

  FR5b="$(folder r5b "$RR" "{\"criteria\":[$AUTH_C]}")"
  h0="$(hits)"
  RUN_CWD="$RR" run r5b "$FR5b" "$PW" SELVEDGE_STEP_TIMEOUT_MS=1000
  h1="$(hits)"
  check "AC5 (Chromium) stdin not a terminal, no flag: BLOCKED needs_auth, exit 2" 'rc === 2 && vc(0).reason === "needs_auth"'
  [ "$((h1 - h0))" -eq 1 ] && ok "AC5 (Chromium) stdin not a terminal: one check request" || ko "AC5 notty /account requests: $h0 -> $h1"

  (cd "$RR" && bash "$CLI" auth setup >"$TMP/o/setupR.out" 2>"$TMP/o/setupR.err" </dev/null) \
    && ok "setup: selvedge auth setup signed in to the fixture app" || ko "setup: auth setup failed: $(cat "$TMP/o/setupR.err")"
  FR6="$(folder r6 "$RR" "{\"criteria\":[$AUTH_C,$PW_C]}")"
  h0="$(hits)"
  RUN_CWD="$RR" run r6 "$FR6" "$PW"
  h1="$(hits)"
  check "AC6 (Chromium) with the stored session the walled criteria PASS (\"Signed in as alice-7Qx\", read back as {{APP_USER}}: every auth.env value is redacted)" \
    'rc === 0 && vc(0).verdict === "PASS" && vc(0).read_value === "Signed in as {{APP_USER}}" && vc(1).verdict === "PASS"'
  [ "$((h1 - h0))" -eq 3 ] && ok "AC6 (Chromium) one check request plus one per criterion (3)" || ko "AC6 /account requests: $h0 -> $h1"
  check "AC9 (Chromium) the page shows APP_PASS: evidence.jsonl and verdict.json carry {{APP_PASS}}" \
    'f("evidence.jsonl").includes("Your password is {{APP_PASS}}") && vc(1).read_value === "Your password is {{APP_PASS}}"'
  leak="$(grep -rlF --exclude-dir=screenshots "$APP_PASS" "$FR6" "$RR/.selvedge/runs.jsonl" "$OUT" "$ERR" 2>/dev/null)"
  [ -z "$leak" ] && ok "AC9 (Chromium) grep -rF \$APP_PASS over the run folder (screenshots aside), runs.jsonl and stdout / stderr finds nothing" \
    || ko "AC9 (Chromium) the password leaked into: $leak"

  node -e 'fetch(process.env.AURL + "/control/expire-sessions").then((r) => r.text())' >/dev/null
  FR7="$(folder r7 "$RR" "{\"criteria\":[$AUTH_C]}")"
  h0="$(hits)"
  RUN_FLAGS="--non-interactive" RUN_CWD="$RR" run r7 "$FR7" "$PW" SELVEDGE_STEP_TIMEOUT_MS=1000
  h1="$(hits)"
  check "AC7 (Chromium) the app no longer accepts the stored cookie: BLOCKED needs_auth, exit 2, no step line" \
    'rc === 2 && vc(0).reason === "needs_auth" && ev.filter((l) => l.kind === "step").length === 0'
  [ "$((h1 - h0))" -eq 1 ] && ok "AC7 (Chromium) one check request" || ko "AC7 /account requests: $h0 -> $h1"
  [ "$(marker_lines)" = "1" ] && ok "AC7 (Chromium) run never ran auth_setup (only \`selvedge auth setup\` did, once)" || ko "AC7 marker: $(marker_lines)"
else
  echo "  (browser arms skipped outside CI; the no-browser arms above decide)"
fi

echo "-- no model in any run"
check "the recording SELVEDGE_PLANNER and the PATH-stub claude of every run recorded zero calls" \
  '!fs.existsSync(E.PLANNER_CALLS) && !fs.existsSync(E.CLAUDE_CALLS)'

finish
