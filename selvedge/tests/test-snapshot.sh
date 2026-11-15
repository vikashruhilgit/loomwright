#!/usr/bin/env bash
# test-snapshot.sh — pins `selvedge snapshot` (selvedge/lib/snapshot.mjs) and its Playwright
# resolution (selvedge/lib/snapshot-playwright.mjs): the pre-launch origin checks on the url and on
# every prefix goto, the prefix lint (validateSteps, prefix mode), {{NAME}} placeholders, the
# per-run-folder budget, the snapshots.jsonl line, the failing-step report and a fresh browser
# context per call. Every arm turns red under its row of the brief's pin-mutation table.
#
# Two parts:
#   1. no-browser arms (always run): the pre-launch refusals, run with SELVEDGE_PLAYWRIGHT_MODULE
#      pointing at a STUB Playwright whose chromium.launch only records the call (then throws), so
#      "nothing launched" is read from the stub's own log; the project-resolve path through a stub
#      `playwright` package in a temp repo's node_modules; and playwright_unavailable in a temp repo
#      with no node_modules.
#   2. real-Chromium arms against the fixture app (tests/fixtures/app-server.mjs): Playwright comes
#      from tests/lib/playwright-cache.sh. Under CI an install failure is a hard FAIL
#      (playwright_install_failed, exit 1); outside CI it is a SKIP and part 1 decides.
#
# Hermetic: a fresh temp HOME (PLAYWRIGHT_BROWSERS_PATH is exported by the helper BEFORE HOME moves),
# a temp git repo as the target project, no network beyond the helper's pinned install. The fixture
# app and the zero-connection recorder U (servers.mjs) run in one background process this script
# stops on exit. Needs node (>= 18) and git; a missing one is a FAIL, never a skip.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$TESTS_DIR/.." && pwd)"
CLI="$PLUGIN_DIR/bin/selvedge"
LIB="$PLUGIN_DIR/lib"
APP="$TESTS_DIR/fixtures/app-server.mjs"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "  ok   $1"; }
ko() { fail=$((fail + 1)); echo "  FAIL $1"; }
finish() { echo "test-snapshot: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }

for tool in node git; do
  command -v "$tool" >/dev/null 2>&1 || { echo "  FAIL $tool is not on PATH (test-snapshot.sh needs it)"; echo "test-snapshot: 0 passed, 1 failed"; exit 1; }
done

# shellcheck source=lib/playwright-cache.sh
. "$TESTS_DIR/lib/playwright-cache.sh"   # exports PLAYWRIGHT_BROWSERS_PATH while HOME is still real

TMP="$(mktemp -d "${TMPDIR:-/tmp}/selvedge-snapshot.XXXXXX")" || exit 1
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
# Every variable an arm asserts the unset path of starts unset; arms that set one pass it explicitly.
unset PLAYWRIGHT_DISABLE_FORCED_CHROMIUM_PROXIED_LOOPBACK SELVEDGE_RUN_DIR SELVEDGE_SNAPSHOT_BUDGET \
  SELVEDGE_PLAYWRIGHT_MODULE NODE_PATH SHOP_USER

# The fixture app + the recorder U, in one background process.
node "$APP" serve "$TMP/servers.json" "$TMP/logs" >"$TMP/servers.log" 2>&1 &
SRV_PID=$!
i=0
while [ ! -s "$TMP/servers.json" ] && [ "$i" -lt 100 ]; do i=$((i + 1)); sleep 0.1; done
info() { node -e 'const d = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); console.log(process.argv[2].split(".").reduce((o, k) => o[k], d))' "$TMP/servers.json" "$1"; }
A="$(info app.port 2>/dev/null)"; U="$(info U.port 2>/dev/null)"; ULOG="$(info U.logFile 2>/dev/null)"
[ -n "$A" ] && [ -n "$U" ] && [ -f "$ULOG" ] && ok "setup: fixture app on localhost:$A, recorder U on localhost:$U" \
  || { ko "setup: app-server.mjs did not start: $(cat "$TMP/servers.log")"; finish; }
export ULOG A U

# The target project: selvedge.json lists only the app's origin. No package.json, no node_modules.
R="$TMP/repo"
mkdir -p "$R" && git -C "$R" init -q
printf '{"schema_version":1,"origins":["http://localhost:%s"]}\n' "$A" > "$R/selvedge.json"

# A stub Playwright: chromium.launch records the call in $STUB_LOG, then throws (nothing runs).
STUB="$TMP/stub-pw"
mkdir -p "$STUB"
printf '{"name":"playwright","version":"0.0.0-stub"}\n' > "$STUB/package.json"
cat > "$STUB/index.mjs" <<'EOF'
import { appendFileSync } from 'node:fs';
export const chromium = {
  launch: async () => {
    appendFileSync(process.env.STUB_LOG, 'launch\n');
    throw new Error('stub chromium: launch recorded, nothing runs');
  },
};
EOF
export STUB_LOG="$TMP/stub-launches.log"

# snap <label> [<env args>…] -- <snapshot args>…  runs `selvedge snapshot` in the target repo ($R,
# or $SNAP_CWD) with `env <env args>` (BSD env: every `-u NAME` before any NAME=value); sets OUT / ERR (files) and RC, and empties the stub's log.
snap() {
  local label="$1"; shift
  local envs=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  [ "$#" -gt 0 ] && shift
  OUT="$TMP/o/$label.out"; ERR="$TMP/o/$label.err"
  : > "$STUB_LOG"
  (cd "${SNAP_CWD:-$R}" && env ${envs[@]+"${envs[@]}"} bash "$CLI" snapshot "$@" >"$OUT" 2>"$ERR"); RC=$?
  export OUT ERR RC
}

# check <label> <js expression> — evaluated over the last snap() and the run folder $D, with:
#   out err rc   the call's stdout, stderr and exit code
#   recs rec     every snapshots.jsonl line of $D (parsed) and the last one
#   json()       stdout parsed as JSON
#   launches()   the stub chromium's launch count for this call
#   zero(f)      a servers.mjs log records no connection and no request
check() {
  local label="$1" expr="$2" got
  got="$(D="$D" node -e '
const fs = require("fs");
const E = process.env;
const txt = (f) => { try { return fs.readFileSync(f, "utf8"); } catch { return ""; } };
const out = txt(E.OUT), err = txt(E.ERR), rc = Number(E.RC);
let recs = [];
try { recs = txt(E.D + "/snapshots.jsonl").split("\n").filter((l) => l.trim() !== "").map((l) => JSON.parse(l)); } catch (e) { recs = ["unparsable: " + e.message]; }
const rec = recs.length ? recs[recs.length - 1] : null;
const json = () => JSON.parse(out);
const launches = () => txt(E.STUB_LOG).split("\n").filter(Boolean).length;
const zero = (f) => { try { return JSON.parse(fs.readFileSync(f, "utf8")).length === 0; } catch { return false; } };
let v;
try { v = eval(process.argv[1]); } catch (e) { v = "error: " + e.message; }
if (v === true) process.stdout.write("true");
else process.stdout.write("false (" + String(v).slice(0, 80) + ") rc=" + E.RC + " out=" + JSON.stringify(out.slice(0, 700)) + " err=" + JSON.stringify(err.slice(-700)) + " rec=" + JSON.stringify(rec).slice(0, 700) + " launches=" + launches());
' "$expr" 2>&1)"
  if [ "$got" = "true" ]; then ok "$label"; else ko "$label — $got"; fi
}

# steps <name> <json> — writes a prefix file, prints its path.
steps() { printf '%s\n' "$2" > "$TMP/$1.json"; printf '%s' "$TMP/$1.json"; }
# rundir <name> [<pre-recorded line count>] — a fresh run folder, optionally holding N recorded calls.
rundir() {
  local d="$TMP/runs/$1" n="${2:-0}" k=0
  mkdir -p "$d"
  while [ "$k" -lt "$n" ]; do printf '{"seeded":%s}\n' "$k" >> "$d/snapshots.jsonl"; k=$((k + 1)); done
  printf '%s' "$d"
}

AURL="http://localhost:$A"
UURL="http://localhost:$U"
STUBENV="SELVEDGE_PLAYWRIGHT_MODULE=$STUB/index.mjs"

echo "-- static: the one validator, the guard, no Playwright import, no string-literal reason"
n="$(grep -cE "(from|import\() *['\"]playwright" "$LIB/snapshot.mjs" "$LIB/snapshot-playwright.mjs" | awk -F: '{s += $2} END {print s + 0}')"
[ "$n" = "0" ] && ok "snapshot*.mjs never import playwright by name (it is resolved at run time)" || ko "snapshot*.mjs import playwright ($n hits)"
{ grep -qE "import \{[^}]*validateSteps[^}]*\} from './plan-steps.mjs'" "$LIB/snapshot.mjs" \
  && grep -qE "import \{[^}]*resolvePlaceholders[^}]*\} from './plan-steps.mjs'" "$LIB/snapshot.mjs" \
  && grep -qE "import \{[^}]*openGuardedContext[^}]*\} from './runner/route-guard.mjs'" "$LIB/snapshot.mjs" \
  && grep -qE "import \{[^}]*isOriginAllowed[^}]*\} from './env-config.mjs'" "$LIB/snapshot.mjs"; } \
  && ok "snapshot.mjs imports validateSteps/resolvePlaceholders, openGuardedContext and isOriginAllowed (never a second validator, guard or origin parser)" \
  || ko "snapshot.mjs does not import the shared validator / guard / origin parser"
reasons="$(node --input-type=module -e "
import { pathToFileURL } from 'node:url';
const E = await import(pathToFileURL(process.argv[1]).href);
console.log(Object.keys(E.REASONS).join('|'));" "$LIB/env-config.mjs")"
hits="$(cd "$LIB" && grep -nE "['\"\`]($reasons)['\"\`]" snapshot.mjs snapshot-playwright.mjs)"
{ [ -n "$reasons" ] && [ -z "$hits" ]; } && ok "snapshot*.mjs name no reason as a string literal (REASONS only)" || ko "string-literal reasons: $hits"

echo "-- CLI surface and usage"
out="$(bash "$CLI" 2>&1)"
grep -qE '^ +snapshot <url> ' <<<"$out" && ok "the CLI help lists snapshot" || ko "help: '$out'"
D="$TMP/none"
snap help -- help
check "selvedge snapshot help exits 0 and documents --run-dir and the exit codes" 'rc === 0 && out.includes("--run-dir") && out.includes("3 NOT_VERIFIABLE")'
snap no-rundir "$STUBENV" -- "$AURL/"
check "no --run-dir and no SELVEDGE_RUN_DIR: exit 2 naming --run-dir; nothing launched" 'rc === 2 && err.includes("--run-dir") && launches() === 0'
snap no-url "$STUBENV" -- --run-dir "$TMP/runs/no-url"
check "no <url>: exit 2" 'rc === 2 && err.includes("needs a <url>") && launches() === 0'
D="$(rundir bad-budget)"
snap bad-budget "$STUBENV" SELVEDGE_SNAPSHOT_BUDGET=lots -- "$AURL/" --run-dir "$D"
check "SELVEDGE_SNAPSHOT_BUDGET=lots: exit 2 (a usage error); nothing launched" 'rc === 2 && err.includes("SELVEDGE_SNAPSHOT_BUDGET") && launches() === 0'
D="$(rundir env-rundir)"
snap env-rundir "$STUBENV" SELVEDGE_RUN_DIR="$D" -- "$UURL/"
check "SELVEDGE_RUN_DIR stands in for --run-dir (the call is recorded there)" 'rc === 2 && recs.length === 1'

echo "-- AC7 an unlisted url is refused before any browser launches"
D="$(rundir ac7)"
snap ac7 "$STUBENV" -- "$UURL/" --run-dir "$D"
check "AC7 localhost:<U> with only localhost:<A> listed: stdout BLOCKED host_not_allowed, exit 2, chromium.launch never called, U records zero connections" \
  'rc === 2 && out.split("\n").includes("BLOCKED host_not_allowed") && launches() === 0 && zero(E.ULOG)'
check "AC7 the refused call is still counted: one snapshots.jsonl line, outcome blocked, browser_launched false, origin localhost:<U>" \
  'recs.length === 1 && rec.outcome === "blocked" && rec.browser_launched === false && rec.origin === "http://localhost:" + E.U && rec.plan_time_actions === 0 && rec.failed_step === null'

echo "-- AC9 the prefix lint and prefix goto origins (nothing launches)"
D="$(rundir ac9)"
snap ac9-unknown "$STUBENV" -- "$AURL/" --run-dir "$D" --steps "$(steps unknown '[{"type":"hover","locator":{"text":"x"}}]')"
check "AC9 an unknown step type: exit 2, stderr plan_invalid: (prefix): unknown_step_type; nothing launched" \
  'rc === 2 && /plan_invalid: \(prefix\): unknown_step_type: steps\[0\]/.test(err) && launches() === 0 && rec.outcome === "invalid" && rec.browser_launched === false'
snap ac9-read "$STUBENV" -- "$AURL/" --run-dir "$D" --steps "$(steps read '[{"type":"goto","url":"'"$AURL"'/"},{"type":"read","property":"url"}]')"
check "AC9 a read step in the prefix: exit 2 plan_invalid prefix_step_not_allowed naming steps[1]; nothing launched" \
  'rc === 2 && /plan_invalid: \(prefix\): prefix_step_not_allowed: steps\[1\]: read/.test(err) && launches() === 0'
snap ac9-expect "$STUBENV" -- "$AURL/" --run-dir "$D" --steps "$(steps expect '[{"type":"expect","op":"equals","value":"x"}]')"
check "AC9 an expect step in the prefix: exit 2 plan_invalid prefix_step_not_allowed; nothing launched" \
  'rc === 2 && /plan_invalid: \(prefix\): prefix_step_not_allowed: steps\[0\]: expect/.test(err) && launches() === 0'
click='{"type":"click","locator":{"role":"button","name":"Open cart"}}'
fifteen="[{\"type\":\"goto\",\"url\":\"$AURL/cart\"}"; k=0; while [ "$k" -lt 14 ]; do fifteen="$fifteen,$click"; k=$((k + 1)); done
snap ac9-16 "$STUBENV" -- "$AURL/" --run-dir "$D" --steps "$(steps sixteen "$fifteen,$click]")"
check "AC9 a 16-step prefix: exit 2 plan_invalid prefix_too_long; nothing launched" \
  'rc === 2 && /plan_invalid: \(prefix\): prefix_too_long/.test(err) && launches() === 0'
snap ac9-15 "$STUBENV" -- "$AURL/" --run-dir "$D" --steps "$(steps fifteen "$fifteen]")"
check "AC9 control: a 15-step prefix passes the lint and reaches the launch (the stub records it)" \
  'rc === 1 && !err.includes("plan_invalid") && launches() === 1'
snap ac9-many "$STUBENV" -- "$AURL/" --run-dir "$D" --steps "$(steps many '[{"type":"hover"},{"type":"read","property":"url"},{"type":"click","locator":{"css":"#x"}}]')"
check "AC9 a prefix with three problems lists all three, one stderr line each" \
  'rc === 2 && err.split("\n").filter((l) => l.includes("plan_invalid: (prefix): ")).length === 3 && launches() === 0'
snap ac9-goto "$STUBENV" -- "$AURL/" --run-dir "$D" --steps "$(steps gotou '[{"type":"goto","url":"'"$UURL"'/"}]')"
check "AC9 a prefix goto to the unlisted localhost:<U>: stdout BLOCKED host_not_allowed naming steps[0], exit 2, nothing launched, U records zero connections" \
  'rc === 2 && out.split("\n").includes("BLOCKED host_not_allowed") && err.includes("steps[0].url") && launches() === 0 && zero(E.ULOG) && rec.outcome === "blocked" && rec.browser_launched === false'
check "AC9 every refused call above was counted in snapshots.jsonl (one line each)" 'recs.length === 7'
D="$(rundir prefix-file)"
snap prefix-missing "$STUBENV" -- "$AURL/" --run-dir "$D" --steps "$TMP/no-such-prefix.json"
check "a --steps file that cannot be read: exit 2 plan_invalid plan_schema_violation; nothing launched; still recorded" \
  'rc === 2 && /plan_invalid: \(prefix\): plan_schema_violation: cannot read/.test(err) && launches() === 0 && rec.outcome === "invalid"'
snap prefix-object "$STUBENV" -- "$AURL/" --run-dir "$D" --steps "$(steps object '{"steps":[]}')"
check "a --steps file that is not a JSON array: exit 2 plan_invalid plan_schema_violation; nothing launched" \
  'rc === 2 && /plan_invalid: \(prefix\): plan_schema_violation: .* must hold a JSON array/.test(err) && launches() === 0 && recs.length === 2'
NOCFG="$TMP/repo-nocfg"; mkdir -p "$NOCFG" && git -C "$NOCFG" init -q
D="$(rundir no-config)"
SNAP_CWD="$NOCFG" snap no-config "$STUBENV" -- "$AURL/" --run-dir "$D"
check "no selvedge.json in the repo: exit 2 config_absent on stderr (origins are never assumed); nothing launched; recorded as invalid" \
  'rc === 2 && err.includes("config_absent") && !out.includes("BLOCKED") && launches() === 0 && rec.outcome === "invalid"'

echo "-- AC16 an unset {{NAME}} is BLOCKED before launch"
D="$(rundir ac16-unset)"
FILL="$(steps fill '[{"type":"fill","locator":{"label":"User"},"value":"{{SHOP_USER}}"}]')"
snap ac16-unset -u SHOP_USER "$STUBENV" -- "$AURL/echo" --run-dir "$D" --steps "$FILL"
check "AC16 SHOP_USER unset: stdout BLOCKED placeholder_unset, stderr names SHOP_USER, exit 2, nothing launched" \
  'rc === 2 && out.split("\n").includes("BLOCKED placeholder_unset") && err.includes("SHOP_USER") && launches() === 0 && rec.prefix_steps[0].value === "{{SHOP_USER}}"'

echo "-- AC10 the snapshot budget (20 calls per run folder by default)"
D="$(rundir ac10-20 20)"
snap ac10-20 -u SELVEDGE_SNAPSHOT_BUDGET "$STUBENV" -- "$AURL/" --run-dir "$D"
check "AC10 budget unset, 20 calls recorded: the 21st prints NOT_VERIFIABLE exploration_budget, exit 3, nothing launched" \
  'rc === 3 && out.split("\n").includes("NOT_VERIFIABLE exploration_budget") && launches() === 0'
check "AC10 the refused 21st call is recorded too (outcome not_verifiable, browser_launched false)" \
  'recs.length === 21 && rec.outcome === "not_verifiable" && rec.browser_launched === false'
D="$(rundir ac10-19 19)"
snap ac10-19 -u SELVEDGE_SNAPSHOT_BUDGET "$STUBENV" -- "$AURL/" --run-dir "$D"
check "AC10 control: with 19 recorded, the 20th call is within the budget and reaches the launch" 'rc === 1 && launches() === 1 && !out.includes("NOT_VERIFIABLE")'
D="$(rundir ac10-env 2)"
snap ac10-env "$STUBENV" SELVEDGE_SNAPSHOT_BUDGET=2 -- "$AURL/" --run-dir "$D"
check "AC10 SELVEDGE_SNAPSHOT_BUDGET=2, 2 recorded: the 3rd call prints NOT_VERIFIABLE exploration_budget, exit 3, nothing launched" \
  'rc === 3 && out.split("\n").includes("NOT_VERIFIABLE exploration_budget") && launches() === 0'
D="$(rundir ac10-env-1 1)"
snap ac10-env-1 "$STUBENV" SELVEDGE_SNAPSHOT_BUDGET=2 -- "$AURL/" --run-dir "$D"
check "AC10 control: SELVEDGE_SNAPSHOT_BUDGET=2 with 1 recorded, the 2nd call reaches the launch" 'rc === 1 && launches() === 1'
D="$(rundir ac10-prec 20)"
snap ac10-prec -u SELVEDGE_SNAPSHOT_BUDGET "$STUBENV" -- "$UURL/" --run-dir "$D"
check "budget spent AND an unlisted url: BLOCKED host_not_allowed, exit 2 (D7 precedence 2 > 3)" \
  'rc === 2 && out.split("\n").includes("BLOCKED host_not_allowed") && !out.includes("NOT_VERIFIABLE") && launches() === 0'

echo "-- AC17 how Playwright is found"
D="$(rundir ac17)"
snap ac17 -u SELVEDGE_PLAYWRIGHT_MODULE -u NODE_PATH -- "$AURL/" --run-dir "$D"
check "AC17 SELVEDGE_PLAYWRIGHT_MODULE unset, no playwright under the repo: stdout BLOCKED playwright_unavailable, exit 2, browser_launched false" \
  'rc === 2 && out.split("\n").includes("BLOCKED playwright_unavailable") && err.includes("SELVEDGE_PLAYWRIGHT_MODULE") && rec.outcome === "blocked" && rec.browser_launched === false'
snap ac17-bad "SELVEDGE_PLAYWRIGHT_MODULE=$TMP/no-such/index.mjs" -- "$AURL/" --run-dir "$D"
check "AC17 SELVEDGE_PLAYWRIGHT_MODULE naming a file that does not load: BLOCKED playwright_unavailable, exit 2" \
  'rc === 2 && out.split("\n").includes("BLOCKED playwright_unavailable") && err.includes("does not load")'
# A second target repo whose own node_modules holds a stub `playwright` (CommonJS, as the real one is).
R2="$TMP/repo2"
mkdir -p "$R2/node_modules/playwright" && git -C "$R2" init -q
cp "$R/selvedge.json" "$R2/selvedge.json"
printf '{"name":"playwright","version":"9.9.9-stub","main":"index.js"}\n' > "$R2/node_modules/playwright/package.json"
cat > "$R2/node_modules/playwright/index.js" <<'EOF'
const fs = require('node:fs');
exports.chromium = { launch: async () => { fs.appendFileSync(process.env.STUB_LOG, 'launch\n'); throw new Error('repo stub chromium: launch recorded'); } };
EOF
SNAP_CWD="$R2" snap ac17-repo -u SELVEDGE_PLAYWRIGHT_MODULE -- "$AURL/" --run-dir "$D"
check "project-resolve: unset SELVEDGE_PLAYWRIGHT_MODULE loads the repo's own node_modules/playwright (version 9.9.9-stub, source repo) and launches through it" \
  'rc === 1 && err.includes("playwright 9.9.9-stub from repo") && launches() === 1'
SNAP_CWD="$R2" snap ac17-nofallback "SELVEDGE_PLAYWRIGHT_MODULE=$TMP/no-such/index.mjs" -- "$AURL/" --run-dir "$D"
check "a set SELVEDGE_PLAYWRIGHT_MODULE that does not load is playwright_unavailable even when the repo has playwright (no silent fall-back)" \
  'rc === 2 && out.split("\n").includes("BLOCKED playwright_unavailable") && launches() === 0'
out="$(node --input-type=module -e "
import { pathToFileURL } from 'node:url';
const P = await import(pathToFileURL(process.argv[1]).href);
const a = await P.resolvePlaywright({ root: process.argv[2], env: {} });
const b = await P.resolvePlaywright({ root: process.argv[3], env: { SELVEDGE_PLAYWRIGHT_MODULE: process.argv[4] } });
let c; try { await P.resolvePlaywright({ root: process.argv[3], env: {} }); c = 'resolved'; } catch (e) { c = [e.reason, e.blocked].join('|'); }
console.log(JSON.stringify([a.version, a.source, typeof a.chromium.launch, b.version, b.source, c]));" \
  "$LIB/snapshot-playwright.mjs" "$R2" "$R" "$STUB/index.mjs" 2>&1)"
[ "$out" = '["9.9.9-stub","repo","function","0.0.0-stub","SELVEDGE_PLAYWRIGHT_MODULE","playwright_unavailable|true"]' ] \
  && ok "resolvePlaywright returns { chromium, version, source } for both lookups, and throws BLOCKED playwright_unavailable when neither resolves" \
  || ko "resolvePlaywright: $out"

echo "-- real Chromium"
HOME="$REAL_HOME" pw_require_or_skip; pwrc=$?
if [ "$pwrc" -eq 1 ]; then
  ko "playwright_install_failed under CI: no browser arm can run"
  finish
fi
if [ "$pwrc" -eq 2 ]; then
  echo "  (browser arms skipped outside CI; the no-browser arms above decide)"
  finish
fi
PWENV="SELVEDGE_PLAYWRIGHT_MODULE=$PW_MODULE"

D="$(rundir plain)"
snap plain "$PWENV" -- "$AURL/" --run-dir "$D"
check "a plain page: exit 0; stdout is exactly {schema_version, url, steps_run, failed_step, error, aria_snapshot} with the page heading in the tree" \
  'rc === 0 && (() => { const j = json(); return Object.keys(j).join() === "schema_version,url,steps_run,failed_step,error,aria_snapshot" && j.schema_version === 1 && j.url === "http://localhost:" + E.A + "/" && j.steps_run === 0 && j.failed_step === null && j.error === null && j.aria_snapshot.includes("heading \"Plain page\""); })()'
check "a plain page: the snapshots.jsonl line says outcome ok, browser_launched true" 'recs.length === 1 && rec.outcome === "ok" && rec.browser_launched === true && rec.plan_time_actions === 0'

D="$(rundir cart)"
snap cart "$PWENV" -- "$AURL/cart" --run-dir "$D"
check "fixture /cart without a prefix: the tree has the Open cart button and no dialog controls" \
  'rc === 0 && json().aria_snapshot.includes("button \"Open cart\"") && !json().aria_snapshot.includes("Quantity") && !json().aria_snapshot.includes("dialog")'

echo "-- AC7 / AC9 with real Chromium: still refused before launch"
D="$(rundir ac7-real)"
snap ac7-real "$PWENV" -- "$UURL/" --run-dir "$D"
check "AC7 (real Playwright) localhost:<U>: BLOCKED host_not_allowed, exit 2, browser_launched false, U records zero connections" \
  'rc === 2 && out.split("\n").includes("BLOCKED host_not_allowed") && rec.browser_launched === false && zero(E.ULOG)'
snap ac9-goto-real "$PWENV" -- "$AURL/" --run-dir "$D" --steps "$TMP/gotou.json"
check "AC9 (real Playwright) a prefix goto to localhost:<U>: BLOCKED host_not_allowed, exit 2, browser_launched false, U records zero connections" \
  'rc === 2 && out.split("\n").includes("BLOCKED host_not_allowed") && rec.browser_launched === false && zero(E.ULOG)'

echo "-- AC15 a failing prefix step"
D="$(rundir ac15)"
snap ac15 "$PWENV" -- "$AURL/cart" --run-dir "$D" --steps "$(steps ac15 '[{"type":"click","locator":{"role":"button","name":"Open cart"}},{"type":"click","locator":{"role":"button","name":"No such button"}}]')"
check "AC15 the 2nd step clicks nothing: exit 1, failed_step 1 (0-based), steps_run 1, error is the error's first line" \
  'rc === 1 && (() => { const j = json(); return j.failed_step === 1 && j.steps_run === 1 && typeof j.error === "string" && j.error.length > 0 && !j.error.includes("\n"); })()'
check "AC15 the tree is the page as it was at the failing step (the dialog step 0 opened, with its Quantity spinbutton and Total)" \
  'const t = json().aria_snapshot; t.includes("dialog \"Cart\"") && t.includes("spinbutton \"Quantity\"") && t.includes("Total")'
check "AC15 the snapshots.jsonl line: outcome step_failed, failed_step 1" 'rec.outcome === "step_failed" && rec.failed_step === 1 && rec.browser_launched === true'

echo "-- AC16 a set {{NAME}} reaches the page; the record keeps the placeholder"
D="$(rundir ac16)"
snap ac16 "$PWENV" SHOP_USER=alice-from-env -- "$AURL/echo" --run-dir "$D" --steps "$FILL"
check "AC16 SHOP_USER=alice-from-env: exit 0 and the page received the value (the fixture echoes it into the tree)" \
  'rc === 0 && json().aria_snapshot.includes("Hello, alice-from-env")'
check "AC16 snapshots.jsonl records the step with the literal {{SHOP_USER}}, never the value" \
  'rec.prefix_steps[0].value === "{{SHOP_USER}}" && !require("fs").readFileSync(E.D + "/snapshots.jsonl", "utf8").includes("alice-from-env")'

echo "-- AC11a the snapshots.jsonl line"
D="$(rundir ac11a)"
snap ac11a "$PWENV" -- "$AURL/echo" --run-dir "$D" --steps "$(steps ac11a '[{"type":"goto","url":"'"$AURL"'/echo"},{"type":"click","locator":{"role":"button","name":"Reset"}},{"type":"fill","locator":{"label":"User"},"value":"bob"}]')"
check "AC11a goto + click + fill: exit 0, one line {ts, origin, prefix_steps, plan_time_actions: 2, browser_launched, outcome, failed_step}" \
  'rc === 0 && recs.length === 1 && Object.keys(rec).join() === "ts,origin,prefix_steps,plan_time_actions,browser_launched,outcome,failed_step" && rec.plan_time_actions === 2 && rec.browser_launched === true && rec.outcome === "ok" && rec.failed_step === null && rec.origin === "http://localhost:" + E.A && rec.prefix_steps.length === 3 && !Number.isNaN(Date.parse(rec.ts))'
check "AC11a the line carries no page text and no tree" \
  'const line = require("fs").readFileSync(E.D + "/snapshots.jsonl", "utf8"); !line.includes("Hello") && !line.includes("aria") && !line.includes("heading") && json().aria_snapshot.includes("Hello, bob")'

echo "-- every prefix step type runs"
D="$(rundir all-types)"
snap all-types "$PWENV" -- "$AURL/echo" --run-dir "$D" --steps "$(steps alltypes '[{"type":"goto","url":"'"$AURL"'/echo"},{"type":"wait_for","locator":{"label":"User"},"state":"visible"},{"type":"fill","locator":{"label":"User"},"value":"carol"},{"type":"press","key":"End","locator":{"label":"User"}},{"type":"select","locator":{"label":"Size"},"value":"L"},{"type":"check","locator":{"label":"Gift wrap"}},{"type":"press","key":"Escape"}]')"
check "goto, wait_for, fill, press (with and without a locator), select and check all run: exit 0, steps_run 7, the page shows each effect" \
  'rc === 0 && (() => { const j = json(); return j.steps_run === 7 && j.failed_step === null && j.aria_snapshot.includes("Hello, carol") && j.aria_snapshot.includes("size L, gift wrap yes, last key Escape"); })()'
check "plan_time_actions counts the five action steps (fill, press, select, check, press) and never goto or wait_for" \
  'rec.plan_time_actions === 5 && rec.outcome === "ok"'

echo "-- the url itself does not load"
C="$(node -e 'const s = require("net").createServer().listen(0, "127.0.0.1", () => { console.log(s.address().port); s.close(); })')"
R3="$TMP/repo3"; mkdir -p "$R3" && git -C "$R3" init -q
printf '{"schema_version":1,"origins":["http://localhost:%s","http://localhost:%s"]}\n' "$A" "$C" > "$R3/selvedge.json"
D="$(rundir closed)"
SNAP_CWD="$R3" snap closed "$PWENV" -- "http://localhost:$C/" --run-dir "$D"
check "a listed origin with nothing listening: exit 1, failed_step null, error is the navigation error's first line; recorded as failed with browser_launched true" \
  'rc === 1 && (() => { const j = json(); return j.failed_step === null && typeof j.error === "string" && j.error.includes("HTTP 502") && !j.error.includes("\n"); })() && rec.outcome === "failed" && rec.browser_launched === true'
D="$(rundir goto-404)"
snap goto-404 "$PWENV" -- "$AURL/" --run-dir "$D" --steps "$(steps goto404 '[{"type":"goto","url":"'"$AURL"'/no-such-page"}]')"
check "a prefix goto answered HTTP 404 fails that step: exit 1, failed_step 0, error names the status" \
  'rc === 1 && json().failed_step === 0 && json().error.includes("HTTP 404") && rec.outcome === "step_failed"'

echo "-- AC11a a fresh browser context per call (two calls in one process)"
D="$(rundir fresh)"
COOKIE_PREFIX="$(steps cookie '[{"type":"goto","url":"'"$AURL"'/cookie"}]')"
# The module path goes in through the environment: as argv[1] it would make snapshot.mjs's own
# isMain() run the CLI on import. The result is written to a file and the driver exits explicitly
# (with a watchdog), so a browser left open between calls can fail the arm but never hang it.
OUT="$TMP/o/fresh.out"; ERR="$TMP/o/fresh.err"
(cd "$R" && SNAP_MODULE="$LIB/snapshot.mjs" SNAP_OUT="$OUT" SELVEDGE_PLAYWRIGHT_MODULE="$PW_MODULE" node --input-type=module -e "
import { writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
setTimeout(() => { writeFileSync(process.env.SNAP_OUT, JSON.stringify({ watchdog: 'fresh-context driver timed out' })); process.exit(3); }, 120000);
const S = await import(pathToFileURL(process.env.SNAP_MODULE).href);
const [base, dir, prefix] = process.argv.slice(1);
const tree = (r) => { try { return JSON.parse(r.stdout).aria_snapshot; } catch { return 'no tree: ' + r.code + ' ' + r.stderr; } };
const one = await S.runSnapshot([base + '/cookie?set=1', '--run-dir', dir, '--steps', prefix]);
const two = await S.runSnapshot([base + '/cookie', '--run-dir', dir]);
writeFileSync(process.env.SNAP_OUT, JSON.stringify({ one: [one.code, tree(one)], two: [two.code, tree(two)] }));
process.exit(0);" \
  "$AURL" "$D" "$COOKIE_PREFIX" >"$ERR" 2>&1); RC=$?
export OUT ERR RC
check "AC11a control: within one call the cookie set by the page is sent back (cookie: selvedge_fixture=seen)" \
  'const j = json(); rc === 0 && j.one[0] === 0 && j.one[1].includes("cookie: selvedge_fixture=seen")'
check "AC11a the next call in the same process starts from a fresh context: the cookie is gone (cookie: none)" \
  'const j = json(); j.two[0] === 0 && j.two[1].includes("cookie: none") && !j.two[1].includes("selvedge_fixture")'

finish
