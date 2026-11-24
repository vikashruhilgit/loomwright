#!/usr/bin/env bash
# test-request-step.sh — pins the `request` step and its reply reads (requirement qa-split/08b):
# the step registry and lint (lib/plan-steps.mjs, lib/plan-validate.mjs), the one executor
# (runner/steps.mjs sendRequest / readValue), the runner (runner/execute.mjs, runner/run.mjs), the
# evidence line (runner/evidence.mjs), the snapshot prefix (lib/snapshot.mjs) and the comment
# (lib/comment-render.mjs). Every arm was checked red under its own mutation of the code it pins.
#
# Three parts:
#   1. no-browser arms (always run): tests/fixtures/request-unit.mjs computes the validator, lint,
#      placeholder, reply-read, evidence and comment results; plus static arms on the executor.
#   2. real-Chromium guard arms: tests/fixtures/request-driver.mjs sends request steps through the
#      guarded browser (route layer and proxy) and through executeCriterion — the 2026-11-23 probe
#      as a fixture, including that context.request is never seen by the route layer.
#   3. real-Chromium `selvedge run` and `selvedge snapshot` arms against the fixture app
#      (tests/fixtures/app-server.mjs: /api/forecast, /api/login, /api/big), plans hand-written by
#      tests/lib/run-helpers.sh and frozen with plan --init + --freeze (no planner).
# Parts 2 and 3 take Playwright from tests/lib/playwright-cache.sh: under CI an install failure is
# a hard FAIL (playwright_install_failed); outside CI they SKIP and part 1 decides.
# Hermetic: a fresh temp HOME (PLAYWRIGHT_BROWSERS_PATH is exported by the helper BEFORE HOME
# moves), temp git repos, no model and no network beyond the helper's pinned install.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$TESTS_DIR/.." && pwd)"
CLI="$PLUGIN_DIR/bin/selvedge"
LIB="$PLUGIN_DIR/lib"
APP="$TESTS_DIR/fixtures/app-server.mjs"
export SELVEDGE_LIB="$LIB"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "  ok   $1"; }
ko() { fail=$((fail + 1)); echo "  FAIL $1"; }
finish() { echo "test-request-step: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }

for tool in node git; do
  command -v "$tool" >/dev/null 2>&1 || { echo "  FAIL $tool is not on PATH (test-request-step.sh needs it)"; echo "test-request-step: 0 passed, 1 failed"; exit 1; }
done

# shellcheck source=lib/playwright-cache.sh
. "$TESTS_DIR/lib/playwright-cache.sh"   # exports PLAYWRIGHT_BROWSERS_PATH while HOME is still real

TMP="$(mktemp -d "${TMPDIR:-/tmp}/selvedge-request.XXXXXX")" || exit 1
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
mkdir -p "$HOME" "$TMP/o" "$TMP/logs"
unset SELVEDGE_PLANNER SELVEDGE_PLAYWRIGHT_MODULE SELVEDGE_ENTRY SELVEDGE_RUN_BUDGET_MS SELVEDGE_RUN_DIR SELVEDGE_BASE \
  SELVEDGE_PLANNER_TOKEN_BUDGET SELVEDGE_STEP_TIMEOUT_MS PLAYWRIGHT_DISABLE_FORCED_CHROMIUM_PROXIED_LOOPBACK NODE_PATH PASS

# jcheck <results file> <label> <js expression over R> — R is the driver's JSON; zero(f) is true when
# the fixture log f records no connection and no request.
jcheck() {
  local file="$1" label="$2" expr="$3" got
  got="$(node -e '
const fs = require("fs");
const R = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const zero = (f) => { try { return JSON.parse(fs.readFileSync(f, "utf8")).length === 0; } catch { return false; } };
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
let v;
try { v = eval(process.argv[2]); } catch (e) { v = "error: " + e.message; }
process.stdout.write(v === true ? "true" : "false " + String(v).slice(0, 200));
' "$file" "$expr" 2>&1)"
  if [ "$got" = "true" ]; then ok "$label"; else ko "$label — $got"; fi
}

echo "-- static: the request step is a page fetch, never context.request or a Node HTTP client"
STEPS="$LIB/runner/steps.mjs"
n="$(grep -hE "context\(\)\.request|context\.request|\.request\.(get|post|put|patch|delete|fetch)\(" "$STEPS" "$LIB/runner/execute.mjs" "$LIB/snapshot.mjs" | grep -cvE '^[[:space:]]*//')"
[ "$n" = "0" ] && ok "steps.mjs, execute.mjs and snapshot.mjs never call Playwright's APIRequestContext (it bypasses context.route)" || ko "an APIRequestContext call ($n hits)"
n="$(grep -cE "from ['\"](node:)?(http|https|net|tls|undici)['\"]|import\(['\"](node:)?(http|https|undici)" "$STEPS" "$LIB/runner/execute.mjs" | awk -F: '{s += $2} END {print s + 0}')"
[ "$n" = "0" ] && ok "steps.mjs and execute.mjs import no Node HTTP client" || ko "a Node HTTP client import ($n hits)"
grep -qE "page\.evaluate\(pageFetch, \[step\.method, url, body, " "$STEPS" \
  && ok "sendRequest runs the one runner-owned pageFetch with the method, URL and body as arguments (never as source)" \
  || ko "sendRequest does not pass the request as page.evaluate arguments to pageFetch"

echo "-- the step, its lint, placeholders, reply reads, evidence and comment (no browser)"
U="$TMP/unit.json"
if node "$TESTS_DIR/fixtures/request-unit.mjs" "$LIB" >"$U" 2>"$TMP/unit.err" && node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$U" 2>/dev/null; then
  jcheck "$U" "a GET request and a POST with a nested json body to the page's own origin are valid steps" 'same(R.valid_get, []) && same(R.valid_post, [])'
  jcheck "$U" "a method outside GET/POST/PUT/PATCH/DELETE, a GET with json, a json that is a string or an array, or nests past 6: plan_schema_violation" \
    '["bad_method", "get_with_json", "json_not_object", "json_array", "json_too_deep"].every((k) => same(R[k], ["1:plan_schema_violation"]))'
  jcheck "$U" "request headers (name to string, {{NAME}} allowed) and a raw body on a non-GET are valid steps" 'same(R.header_field, []) && same(R.raw_body, [])'
  jcheck "$U" "a header fetch forbids page code to set (Cookie, Sec-*), a non-string header value, json and body together, a body on a GET or a body that is not a string: plan_schema_violation" \
    '["forbidden_header", "sec_header", "header_not_string", "body_and_json", "get_with_body", "body_not_string"].every((k) => R[k].includes("1:plan_schema_violation"))'
  jcheck "$U" "{{NAME}} in a raw body and a header value is a placeholder (resolved at run time, redacted like a json leaf)" 'same(R.body_placeholders, ["BODY_K", "HDR_T"])'
  jcheck "$U" "the origin rule: a request to another listed origin than its page's, or before any goto, is origin_not_allowed; after a goto to that origin it is valid" \
    'same(R.cross_origin, ["1:origin_not_allowed"]) && same(R.no_goto_first, ["0:origin_not_allowed"]) && same(R.after_second_goto, [])'
  jcheck "$U" "a request to an origin selvedge.json does not list is origin_not_allowed" 'R.unlisted_origin.includes("1:origin_not_allowed")'
  jcheck "$U" "code-like content in a json leaf or a json key is code_like_content" 'same(R.code_like_leaf, ["1:code_like_content"]) && same(R.code_like_key, ["1:code_like_content"])'
  jcheck "$U" "response_status, response_text, response_json:<pointer> (~0 / ~1 escapes) and cookie:<name> take no locator; with one, or a pointer that is not RFC 6901, plan_schema_violation" \
    'same(R.reads_no_locator, []) && same(R.reads_with_locator, ["2:plan_schema_violation", "3:plan_schema_violation"]) && same(R.bad_pointer, ["2:plan_schema_violation", "3:plan_schema_violation", "4:plan_schema_violation"])'
  jcheck "$U" "isActionStep: a GET request is not an action; POST, PUT, PATCH and DELETE are (as click is; goto is not)" 'same(R.is_action, [false, true, true, true, true, true, false])'
  jcheck "$U" "snapshot prefix: a GET request from the snapshot's page is allowed; a POST or DELETE is prefix_mutation_refused" \
    'same(R.prefix_get, []) && same(R.prefix_post, ["prefix_mutation_refused"]) && same(R.prefix_delete, ["prefix_mutation_refused"])'
  jcheck "$U" "Acceptance 1 lint: goto, request GET, read response_status, expect equals 401 is a clean plan" 'same(R.lint_acceptance, [])'
  jcheck "$U" "a read response_status or response_json with no request before it in the criterion (or before the first request) is response_without_request" \
    'same(R.lint_no_request, ["response_without_request"]) && same(R.lint_json_no_request, ["response_without_request"]) && same(R.lint_read_before_request, ["response_without_request"])'
  jcheck "$U" "cookie:<name>: changed_from true against a baseline read is clean; without the baseline, or with matches / contains / gt / equals, existence_only_expect" \
    'same(R.lint_cookie_changed, []) && same(R.lint_cookie_no_baseline, ["existence_only_expect"]) && ["lint_cookie_matches", "lint_cookie_gt", "lint_cookie_equals"].every((k) => same(R[k], ["existence_only_expect"])) && R.lint_cookie_contains.length >= 1 && R.lint_cookie_contains.every((c) => c === "existence_only_expect")'
  jcheck "$U" "a negative criterion whose first action is a POST request needs a baseline read before it (negative_without_baseline); a GET is not an action" \
    'same(R.lint_negative_post_no_baseline, ["negative_without_baseline"]) && same(R.lint_negative_get_no_baseline, [])'
  jcheck "$U" "PLAN_PROBLEMS lists response_without_request and prefix_mutation_refused" 'R.problems.includes("response_without_request") && R.problems.includes("prefix_mutation_refused")'
  jcheck "$U" "{{NAME}} in json string leaves (nested, in arrays): named, resolved literally from env, the input left as written; an unset name is BLOCKED placeholder_unset" \
    'same(R.placeholder_names, ["SHOP_USER", "PASS"]) && same(R.placeholder_resolved, { email: "alice", password: "hunter2$&", deep: { list: ["hunter2$&-x", 2] } }) && same(R.placeholder_input_kept, { email: "{{SHOP_USER}}", password: "{{PASS}}", deep: { list: ["{{PASS}}-x", 2] } }) && R.placeholder_unset === "placeholder_unset|true|PASS"'
  jcheck "$U" "response_json:<pointer>: a string, number or boolean; null for a missing key, an index out of range or with a leading zero, JSON null, an object, an array, or a body that is not JSON" \
    'const p = R.pointer; p.name === "Ada" && p.escaped === 7 && p.bool === true && p.index === 2 && ["missing", "out_of_range", "leading_zero", "json_null", "object", "array", "not_json"].every((k) => p[k] === null)'
  jcheck "$U" "cookieFingerprint: sha256: + 16 hex, stable for one value, different for another, never holding the value" \
    'const f = R.fingerprint; /^sha256:[0-9a-f]{16}$/.test(f.fp) && f.fp === f.again && f.fp !== f.other && !f.fp.includes("apisess")'
  jcheck "$U" "the reply text cap is 64 KiB" 'R.text_cap === 65536'
  jcheck "$U" "a request step's evidence line: value null and request {method, url, json_keys (sorted), status}; never the body, the {{NAME}} or its value" \
    'const l = R.evidence_line; R.evidence_line_problem === null && l.value === null && same(l.request, { method: "POST", url: "http://localhost:4100/api/forecast", json_keys: ["email", "password"], status: 200 }) && !JSON.stringify(l).includes("PASS") && !JSON.stringify(l).includes("a@b.c")'
  jcheck "$U" "the evidence reader refuses a request field on a click line, a request line without one, and a request field carrying a body" \
    'R.evidence_request_on_click !== null && R.evidence_request_missing !== null && R.evidence_request_body !== null'
  jcheck "$U" "comment (read_values on): a criterion that reads a cookie publishes no read value and no fingerprint; a request step shows its method and path, never its json" \
    'const c = R.comment; !c.includes(R.fp_hex) && c.includes("not published (a cookie read is never published)") && c.includes("`request` POST /api/forecast") && !c.includes("{{PASS}}") && !c.includes("password") && c.includes("- **Read value:** \"401\"")'
else
  ko "request-unit.mjs ran: $(tail -n 5 "$TMP/unit.err")"
fi

echo "-- real Chromium: the guard refuses request steps (the probe as a fixture)"
HOME="$REAL_HOME" pw_require_or_skip; pwrc=$?
if [ "$pwrc" -eq 1 ]; then
  ko "playwright_install_failed under CI: no browser arm can run"
  finish
fi
[ "$pwrc" -eq 2 ] && finish

B="$TMP/browser.json"
if node "$TESTS_DIR/fixtures/request-driver.mjs" "$LIB" "$TMP/logs" browser >"$B" 2>"$B.err" && node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$B" 2>/dev/null; then
  jcheck "$B" "Acceptance 2 (route layer): a request step to an unlisted origin throws GuardRefusal host_not_allowed; the route layer records it and the host records nothing" \
    'const a = R.route_unlisted; a.r.guard === true && a.r.reason === "host_not_allowed" && a.blocks.length === 1 && a.blocks[0].layer === "route" && a.blocks[0].url === a.want && a.seen.some((s) => s.url === a.want) && zero(a.logs.U)'
  jcheck "$B" "Acceptance 3 (route layer): a request POST to a listed remote with allow_remote_mutation off throws GuardRefusal remote_mutation_refused; the route layer records it and the remote records nothing" \
    'const a = R.route_remote_post; a.r.guard === true && a.r.reason === "remote_mutation_refused" && a.blocks.length === 1 && a.blocks[0].layer === "route" && a.blocks[0].method === "POST" && a.blocks[0].url === a.want && zero(a.logs.R)'
  jcheck "$B" "a remote GET the route layer allows is refused by the proxy (remote_resolves_private, its 403 header), and the request step names that reason" \
    'const a = R.proxy_remote_get; a.r.guard === true && a.r.reason === "remote_resolves_private" && a.blocks.some((b) => b.layer === "proxy") && zero(a.logs.R)'
  jcheck "$B" "with the route layer off (test-only), the proxy alone refuses the unlisted origin and the request step finds its record (host_not_allowed)" \
    'const a = R.proxy_only_unlisted; a.r.guard === true && a.r.reason === "host_not_allowed" && a.blocks.length === 1 && a.blocks[0].layer === "proxy" && zero(a.logs.U)'
  jcheck "$B" "a listed request whose connection drops mid-reply throws a plain Error (not GuardRefusal) naming the failure; no guard layer records a block, and the host did receive it" \
    'const a = R.network_drop; a.r.ok === false && a.r.guard === false && a.r.reason === null && a.r.error.includes("the request failed") && a.r.error.includes(a.want) && a.blocks.length === 0 && !zero(a.logs.A)'
  jcheck "$B" "the probe: Playwright's context.request is never seen by the route layer (the reason the runner never uses it)" \
    'const a = R.probe_context_request; Array.isArray(a.seen) && a.seen.length === 0 && zero(a.logs.U)'
  jcheck "$B" "Acceptance 2 (executeCriterion): the criterion ends BLOCKED host_not_allowed at the request step (failed_step 1, a failed request line, no read), the host records nothing" \
    'const a = R.exec_unlisted; a.end.outcome === "blocked" && a.end.reason === "host_not_allowed" && a.end.failed_step === 1 && a.lines.length === 2 && a.lines[1].type === "request" && a.lines[1].outcome === "failed" && a.lines[1].request.status === null && zero(a.logs.U)'
  jcheck "$B" "Acceptance 3 (executeCriterion): a remote request POST ends BLOCKED remote_mutation_refused at the request step; the remote records nothing" \
    'const a = R.exec_remote_post; a.end.outcome === "blocked" && a.end.reason === "remote_mutation_refused" && a.end.failed_step === 1 && a.lines[1].type === "request" && a.lines[1].outcome === "failed" && zero(a.logs.R)'
  jcheck "$B" "executeCriterion: a request whose connection drops ends step_failed (not BLOCKED) at the request step, with a failed request line and no read" \
    'const a = R.exec_network_drop; a.end.outcome === "step_failed" && a.end.reason === "step_failed" && a.end.failed_step === 1 && a.lines.length === 2 && a.lines[1].type === "request" && a.lines[1].outcome === "failed" && a.lines[1].request.status === null'
else
  ko "request-driver.mjs ran: $(tail -n 5 "$B.err") $(head -c 400 "$B")"
fi

echo "-- real Chromium: selvedge run and snapshot against the fixture app"
# shellcheck source=lib/run-helpers.sh
. "$TESTS_DIR/lib/run-helpers.sh"
rh_start_app
rh_setup
R="$TMP/repo"; newrepo "$R"
PW="SELVEDGE_PLAYWRIGHT_MODULE=$PW_MODULE"
export API_PREFIX="apisess-7f3c9d-" PASS_VALUE="s3cr3t-Pa55-xyz"

# run <label> <run-dir> [<env args>…] — selvedge run in $R; sets OUT / ERR / RC / DIR.
run() {
  local label="$1" dir="$2"; shift 2
  OUT="$TMP/o/$label.out"; ERR="$TMP/o/$label.err"
  (cd "$R" && env "SELVEDGE_PLANNER=sh $TMP/planner-shim.sh" "PATH=$TMP/stubbin:$PATH" "$@" bash "$CLI" run "$dir" >"$OUT" 2>"$ERR"); RC=$?
  DIR="$dir"
  export OUT ERR RC DIR
}
hits() { node -e 'fetch(process.argv[1]).then((r) => r.text()).then((t) => process.stdout.write(t.trim()))' "$AURL/control/hits?path=/api/login"; }
# check <label> <js expression> — over the last run(): out err rc, ev (evidence lines), vj (verdict.json),
# ids (plan.json's criterion ids), vc(i), f(n) (a run-folder file's text), all(), every text file of the folder.
check() {
  local label="$1" expr="$2" got
  got="$(node -e '
const fs = require("fs");
const path = require("path");
const E = process.env;
const txt = (p) => { try { return fs.readFileSync(p, "utf8"); } catch { return ""; } };
const out = txt(E.OUT), err = txt(E.ERR), rc = Number(E.RC);
const f = (n) => { try { return fs.readFileSync(path.join(E.DIR, n), "utf8"); } catch { return null; } };
const ev = (f("evidence.jsonl") || "").split("\n").filter((l) => l.trim() !== "").map((l) => JSON.parse(l));
const vj = f("verdict.json") === null ? null : JSON.parse(f("verdict.json"));
const ids = Object.keys(JSON.parse(f("plan.json") || "{\"steps_by_criterion\":{}}").steps_by_criterion);
const vc = (i) => vj.criteria[ids[i]];
const evOf = (i) => ev.filter((l) => l.criterion === ids[i]);
const walk = (d) => fs.readdirSync(d).sort().flatMap((n) => { const p = path.join(d, n); return fs.statSync(p).isDirectory() ? walk(p) : [p]; });
const all = () => walk(E.DIR).filter((p) => !p.endsWith(".png")).map((p) => txt(p)).join("\n");
let v;
try { v = eval(process.argv[1]); } catch (e) { v = "error: " + e.message; }
if (v === true) process.stdout.write("true");
else process.stdout.write("false (" + String(v).slice(0, 80) + ") rc=" + E.RC + " out=" + JSON.stringify(out.slice(0, 400)) + " err=" + JSON.stringify(err.slice(-700)) + " verdict=" + JSON.stringify(vj && vj.criteria).slice(0, 700));
' "$expr" 2>&1)"
  if [ "$got" = "true" ]; then ok "$label"; else ko "$label — $got"; fi
}

REQ_GET='{"type":"goto","url":"$O/"},{"type":"request","method":"GET","url":"$O/api/forecast"}'
F1="$(folder anon "$R" '{"criteria":[
{"text":"GET /api/forecast without a session answers 401","steps":['"$REQ_GET"',{"type":"read","property":"response_status"},{"type":"expect","op":"equals","value":401}]},
{"text":"GET /api/forecast without a session answers 200","steps":['"$REQ_GET"',{"type":"read","property":"response_status"},{"type":"expect","op":"equals","value":200}]},
{"text":"The anonymous forecast reply names the error \"unauthorized\"","steps":['"$REQ_GET"',{"type":"read","property":"response_json:/error"},{"type":"expect","op":"equals","value":"unauthorized"}]},
{"text":"The anonymous forecast reply text contains \"unauthorized\"","steps":['"$REQ_GET"',{"type":"read","property":"response_text"},{"type":"expect","op":"contains","value":"unauthorized"}]},
{"text":"The anonymous forecast reply has a field nope equal to \"x\"","steps":['"$REQ_GET"',{"type":"read","property":"response_json:/nope"},{"type":"expect","op":"equals","value":"x"}]},
{"text":"The big reply holds exactly 64 KiB of text","steps":[{"type":"goto","url":"$O/"},{"type":"request","method":"GET","url":"$O/api/big"},{"type":"read","property":"response_text"},{"type":"expect","op":"matches","value":"^x{65536}$"}]},
{"text":"GET /api/ok answers the text ok","steps":[{"type":"goto","url":"$O/"},{"type":"request","method":"GET","url":"$O/api/ok"},{"type":"read","property":"response_text"},{"type":"expect","op":"equals","value":"ok"}]}]}')"
[ -n "$F1" ] && ok "setup: the anonymous-reply plan freezes (the lint accepts request steps and reply reads)" || ko "setup: folder anon: $(cat "$TMP/o/freeze-anon.err" "$TMP/o/init-anon.err" 2>/dev/null)"
run anon "$F1" "$PW"
check "Acceptance 1: goto, request GET /api/forecast, read response_status, expect equals 401: PASS, derived from the status read (read_value 401)" \
  'const c = vc(0); c.verdict === "PASS" && c.read_value === 401 && c.matched === true && c.expected.op === "equals" && c.expected.value === 401'
check "Acceptance 1: the same plan expecting 200 is FAIL (read_value 401, matched false), so the run exits 1" 'rc === 1 && vc(1).verdict === "FAIL" && vc(1).read_value === 401 && vc(1).matched === false'
check "the request step's evidence line records method, url, status 401 and no json keys; the reply text is evidence only through its read" \
  'const l = evOf(0).find((x) => x.type === "request"); l && l.outcome === "ok" && l.value === null && l.request.method === "GET" && l.request.url.endsWith("/api/forecast") && l.request.status === 401 && l.request.json_keys === null'
check "response_json:/error reads \"unauthorized\" and response_text contains it: both PASS" 'vc(2).verdict === "PASS" && vc(2).read_value === "unauthorized" && vc(3).verdict === "PASS"'
check "a pointer that names nothing reads no value: NOT_VERIFIABLE no_value_read, never PASS" 'vc(4).verdict === "NOT_VERIFIABLE" && vc(4).reason === "no_value_read"'
check "a 70000-character reply is kept to the 64 KiB cap" 'vc(5).verdict === "PASS" && evOf(5).filter((x) => x.type === "read").every((x) => x.value.length === 65536)'
check "response_text is trimmed like a text read: a body \"ok\\n\" equals \"ok\" (PASS, read_value \"ok\")" 'vc(6).verdict === "PASS" && vc(6).read_value === "ok"'

LOGIN='{"type":"request","method":"POST","url":"$O/api/login","json":{"email":"ada@example.com","password":"{{PASS}}"}}'
F2="$(folder signin "$R" '{"criteria":[
{"text":"Signing in by request sets a session cookie","steps":[{"type":"goto","url":"$O/"},{"type":"read","property":"cookie:selvedge_api"},'"$LOGIN"',{"type":"read","property":"cookie:selvedge_api"},{"type":"expect","op":"changed_from","value":true}]},
{"text":"Signing in by request answers with the user email ada@example.com","steps":[{"type":"goto","url":"$O/"},'"$LOGIN"',{"type":"read","property":"response_json:/user/email"},{"type":"expect","op":"equals","value":"ada@example.com"}]},
{"text":"The sign-in reply text contains ada","steps":[{"type":"goto","url":"$O/"},'"$LOGIN"',{"type":"read","property":"response_text"},{"type":"expect","op":"contains","value":"ada"}]},
{"text":"A signed-in GET /api/forecast answers 200","steps":[{"type":"goto","url":"$O/"},'"$LOGIN"',{"type":"request","method":"GET","url":"$O/api/forecast"},{"type":"read","property":"response_status"},{"type":"expect","op":"equals","value":200}]},
{"text":"A later criterion starts with no session: GET /api/forecast answers 401","steps":['"$REQ_GET"',{"type":"read","property":"response_status"},{"type":"expect","op":"equals","value":401}]}]}')"
[ -n "$F2" ] && ok "setup: the sign-in plan freezes" || ko "setup: folder signin: $(cat "$TMP/o/freeze-signin.err" 2>/dev/null)"
before="$(hits)"
run signin "$F2" "$PW" "PASS=$PASS_VALUE"
check "a POST request with a json body signs in: the cookie read changed_from its baseline (PASS), the reply's email reads ada@example.com (PASS), the reply text contains ada (PASS)" \
  'rc === 0 && vc(0).verdict === "PASS" && vc(1).verdict === "PASS" && vc(1).read_value === "ada@example.com" && vc(2).verdict === "PASS"'
check "the context's cookies go with a later request of the same criterion (200), and none carries to the next criterion (401)" 'vc(3).verdict === "PASS" && vc(3).read_value === 200 && vc(4).verdict === "PASS" && vc(4).read_value === 401'
check "Acceptance 4: the cookie reads are fingerprints (null before, sha256:<16 hex> after); no evidence, verdict, stdout or stderr line holds the cookie value" \
  'const r = evOf(0).filter((x) => x.type === "read"); r[0].value === null && /^sha256:[0-9a-f]{16}$/.test(r[r.length - 1].value) && ![all(), out, err].some((t) => t.includes(E.API_PREFIX))'
check "Acceptance 5: plan.json holds {{PASS}}, never its value; no evidence, verdict, stdout or stderr line holds the value (the reply that echoes it is written back as {{PASS}})" \
  'f("plan.json").includes("{{PASS}}") && ![all(), out, err].some((t) => t.includes(E.PASS_VALUE)) && evOf(2).filter((x) => x.type === "read").every((x) => x.value.includes("{{PASS}}"))'
check "Acceptance 5: a request line records the json keys [email, password], never the body" \
  'const l = evOf(1).find((x) => x.type === "request"); JSON.stringify(l.request.json_keys) === "[\"email\",\"password\"]" && !JSON.stringify(l).includes("ada@") && l.request.status === 200'
[ "$(hits)" = "$((before + 4))" ] && ok "the four sign-in requests reached the app once each (no retry, no second send)" || ko "/api/login hits: before $before, after $(hits)"

RAW='{"type":"request","method":"POST","url":"$O/api/login","body":"{not json","headers":{"content-type":"application/json"}}'
F3="$(folder vocab "$R" '{"criteria":[
{"text":"POST /api/login with a body that is not JSON answers 400","steps":[{"type":"goto","url":"$O/"},'"$RAW"',{"type":"read","property":"response_status"},{"type":"expect","op":"equals","value":400}]},
{"text":"The forecast reply is sent as JSON","steps":['"$REQ_GET"',{"type":"read","property":"response_header:Content-Type"},{"type":"expect","op":"contains","value":"application/json"}]},
{"text":"The forecast reply has no X-Nope header","steps":['"$REQ_GET"',{"type":"read","property":"response_header:x-nope"},{"type":"expect","op":"equals","value":"x"}]},
{"text":"Signing in sets the session cookie HttpOnly","steps":[{"type":"goto","url":"$O/"},'"$LOGIN"',{"type":"read","property":"cookie_attribute:selvedge_api:http_only"},{"type":"expect","op":"equals","value":true}]},
{"text":"The session cookie is scoped to path /","steps":[{"type":"goto","url":"$O/"},'"$LOGIN"',{"type":"read","property":"cookie_attribute:selvedge_api:path"},{"type":"expect","op":"equals","value":"/"}]},
{"text":"Pressing Tab on /controls first focuses Do nothing","steps":[{"type":"goto","url":"$O/controls"},{"type":"press","key":"Tab"},{"type":"read","property":"focused"},{"type":"expect","op":"contains","value":"Do nothing"}]},
{"text":"Tabbing on /controls never reaches Hidden action","steps":[{"type":"goto","url":"$O/controls"},{"type":"press","key":"Tab"},{"type":"read","property":"focused"},{"type":"expect","op":"absent","value":"Hidden action"},{"type":"press","key":"Tab"},{"type":"read","property":"focused"},{"type":"expect","op":"absent","value":"Hidden action"}]}]}')"
[ -n "$F3" ] && ok "setup: the plan with a raw body, headers, response_header, cookie_attribute and focused reads freezes" || ko "setup: folder vocab: $(cat "$TMP/o/freeze-vocab.err" 2>/dev/null)"
before="$(hits)"
run vocab "$F3" "$PW" "PASS=$PASS_VALUE"
check "a raw non-JSON body with a content-type header reaches the app and is answered 400 (PASS)" 'vc(0).verdict === "PASS" && vc(0).read_value === 400'
check "response_header:Content-Type reads the reply header (any case; PASS), an absent header reads no value (NOT_VERIFIABLE no_value_read, never PASS)" \
  'vc(1).verdict === "PASS" && vc(1).read_value.includes("application/json") && vc(2).verdict === "NOT_VERIFIABLE" && vc(2).reason === "no_value_read"'
check "cookie_attribute reads the HttpOnly flag (true) and the path (/) of the session cookie, never its value" \
  'vc(3).verdict === "PASS" && vc(3).read_value === true && vc(4).verdict === "PASS" && vc(4).read_value === "/" && !all().includes(E.API_PREFIX)'
check "focused reads the element holding focus after a key press (button \"Do nothing\"); absent on it checks a hidden button is never reached" \
  'vc(5).verdict === "PASS" && vc(5).read_value.startsWith("button") && vc(6).verdict === "PASS"'
[ "$(hits)" = "$((before + 3))" ] && ok "the raw-body request and the two sign-ins reached the app once each" || ko "/api/login hits (vocab): before $before, after $(hits)"
node --input-type=module -e "
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
const { renderComment } = await import(pathToFileURL(process.env.SELVEDGE_LIB + '/comment-render.mjs').href);
const d = process.argv[1];
const j = (n) => JSON.parse(readFileSync(d + '/' + n, 'utf8'));
process.stdout.write(renderComment({ verdict: j('verdict.json'), plan: j('plan.json'), criteria: j('criteria.json').criteria, readValues: true }));
" "$F2" >"$TMP/comment.md" 2>"$TMP/comment.err"
if [ -s "$TMP/comment.md" ] && ! grep -qF "$PASS_VALUE" "$TMP/comment.md" && ! grep -qF "$API_PREFIX" "$TMP/comment.md" && ! grep -qE "sha256:[0-9a-f]{16}" "$TMP/comment.md" && grep -qF "a cookie read is never published" "$TMP/comment.md"; then
  ok "Acceptances 4 and 5: the comment (read_values on) holds neither the {{PASS}} value, the cookie value nor its fingerprint"
else
  ko "comment: $(cat "$TMP/comment.err") $(grep -nE "sha256:|$PASS_VALUE|$API_PREFIX|Read value" "$TMP/comment.md" | head -5)"
fi

F3="$(folder unset "$R" '{"criteria":[{"text":"Signing in answers with the user email ada@example.com","steps":[{"type":"goto","url":"$O/"},'"$LOGIN"',{"type":"read","property":"response_json:/user/email"},{"type":"expect","op":"equals","value":"ada@example.com"}]}]}')"
before="$(hits)"
run unset "$F3" "$PW"
check "Acceptance 5: an unset PASS is BLOCKED placeholder_unset (exit 2) naming PASS, before any request" 'rc === 2 && vc(0).verdict === "BLOCKED" && vc(0).reason === "placeholder_unset" && err.includes("PASS") && ev.filter((x) => x.type === "request").length === 0'
[ "$(hits)" = "$before" ] && ok "Acceptance 5: with PASS unset no sign-in request reached the app" || ko "/api/login hits with PASS unset: before $before, after $(hits)"

echo "-- snapshot: a GET request in a prefix shows the reply; a POST is refused before launch"
snap() {
  local label="$1"; shift
  printf '%s\n' "$1" > "$TMP/prefix-$label.json"
  (cd "$R" && env "$PW" bash "$CLI" snapshot "$AURL/" --steps "$TMP/prefix-$label.json" --run-dir "$TMP/snap-$label" >"$TMP/o/snap-$label.out" 2>"$TMP/o/snap-$label.err"); echo $?
}
rc="$(snap get "[{\"type\":\"request\",\"method\":\"GET\",\"url\":\"$AURL/api/forecast\"},{\"type\":\"request\",\"method\":\"GET\",\"url\":\"$AURL/api/big\"}]")"
out="$(node -e '
const fs = require("fs");
const j = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const rec = JSON.parse(fs.readFileSync(process.argv[2], "utf8").trim().split("\n").pop());
const [a, b] = j.replies || [];
const okA = a && a.step === 0 && a.method === "GET" && a.status === 401 && a.body.includes("unauthorized") && a.truncated === false && a.content_type.startsWith("application/json");
const okB = b && b.step === 1 && b.status === 200 && Buffer.byteLength(b.body) === 2048 && b.truncated === true;
console.log(okA && okB && j.steps_run === 2 && rec.plan_time_actions === 0 ? "yes" : JSON.stringify({ replies: j.replies && j.replies.map((r) => ({ ...r, body: r.body.slice(0, 40) })), rec }));
' "$TMP/o/snap-get.out" "$TMP/snap-get/snapshots.jsonl" 2>&1)"
{ [ "$rc" = "0" ] && [ "$out" = "yes" ]; } && ok "a GET request in a prefix: exit 0; replies holds each status and the first 2 KiB of the body (truncated past it); no plan-time action" || ko "snapshot GET prefix: rc=$rc $out $(tail -n 3 "$TMP/o/snap-get.err")"
before="$(hits)"
rc="$(snap post "[{\"type\":\"request\",\"method\":\"POST\",\"url\":\"$AURL/api/login\",\"json\":{\"email\":\"a\",\"password\":\"b\"}}]")"
{ [ "$rc" = "2" ] && grep -qF "prefix_mutation_refused" "$TMP/o/snap-post.err" && node -e 'const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8").trim()); process.exit(r.browser_launched === false && r.outcome === "invalid" ? 0 : 1)' "$TMP/snap-post/snapshots.jsonl" && [ "$(hits)" = "$before" ]; } \
  && ok "a POST request in a prefix: exit 2 plan_invalid prefix_mutation_refused; no browser launched, nothing reached the app" \
  || ko "snapshot POST prefix: rc=$rc $(tail -n 3 "$TMP/o/snap-post.err")"
rc="$(snap cross "[{\"type\":\"request\",\"method\":\"GET\",\"url\":\"http://localhost:1/api\"}]")"
{ [ "$rc" = "2" ] && grep -qF "BLOCKED host_not_allowed" "$TMP/o/snap-cross.out"; } && ok "a prefix request to an unlisted origin: BLOCKED host_not_allowed before launch" || ko "snapshot unlisted prefix request: rc=$rc $(cat "$TMP/o/snap-cross.out")"

finish
