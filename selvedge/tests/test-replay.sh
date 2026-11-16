#!/usr/bin/env bash
# test-replay.sh — pins `selvedge run --replay` (replayRun in selvedge/lib/runner/run.mjs), `run
# --trace` (runner/execute.mjs) with its zip redaction (runner/trace-redact.mjs: redactTraceZip) and
# the README's run / verdict documentation. Every arm turns red under its row of the brief's
# pin-mutation table.
#
# Three parts:
#   1. trace-redact.mjs on hand-built zips (always run): deflated entries with data descriptors,
#      stored entries and a binary one, read back by Python's zipfile (an independent reader); and
#      the zips it must drop (not a zip, encryption, an unknown method, zip64, a bad CRC-32, a
#      binary entry holding a secret).
#   2. no-browser arms (always run): SELVEDGE_PLAYWRIGHT_MODULE is tests/fixtures/stub-playwright.mjs,
#      whose chromium.launch appends `launch` to $STUB_PW_LOG: AC22 (replay of a PASSed run), AC24
#      (an edited frozen plan, with and without its plan.sha256), the replay refusals, AC27.
#   3. real-Chromium arms against the fixture app (tests/fixtures/app-server.mjs) with Playwright from
#      tests/lib/playwright-cache.sh: AC22 on the modal plan, AC23 (the renamed "Open cart" control),
#      AC25 (a kept trace holds no cookie, bearer or {{NAME}} value). Under CI an install failure is a
#      hard FAIL (playwright_install_failed); outside CI it is a SKIP and parts 1 and 2 decide.
#
# Plans are hand-written (the generator in tests/lib/run-helpers.sh, shared with test-run.sh) and frozen with
# `selvedge plan --init` + `--freeze` (no planner), except AC22/AC23's modal plan, which
# tests/fixtures/stub-planner.sh mode `modal` writes. Every run gets a recording SELVEDGE_PLANNER and
# a PATH-stub `claude`; AC17/AC22 assert neither was ever called. Hermetic: a fresh temp HOME
# (PLAYWRIGHT_BROWSERS_PATH is exported by the helper BEFORE HOME moves), temp git repos as target
# projects, no model and no network beyond the helper's pinned install. One fixture app process for
# the whole file, stopped on exit. Needs node (>= 18), git and python3.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$TESTS_DIR/.." && pwd)"
CLI="$PLUGIN_DIR/bin/selvedge"
LIB="$PLUGIN_DIR/lib"
APP="$TESTS_DIR/fixtures/app-server.mjs"
export STUB_PW="$TESTS_DIR/fixtures/stub-playwright.mjs"
export SELVEDGE_LIB="$LIB" APP

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "  ok   $1"; }
ko() { fail=$((fail + 1)); echo "  FAIL $1"; }
finish() { echo "test-replay: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }

for tool in node git python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "  FAIL $tool is not on PATH (test-replay.sh needs it)"; echo "test-replay: 0 passed, 1 failed"; exit 1; }
done

# shellcheck source=lib/playwright-cache.sh
. "$TESTS_DIR/lib/playwright-cache.sh"   # exports PLAYWRIGHT_BROWSERS_PATH while HOME is still real

TMP="$(mktemp -d "${TMPDIR:-/tmp}/selvedge-replay.XXXXXX")" || exit 1
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
# Every variable an arm asserts the unset path of starts unset; arms that set one pass it explicitly.
unset SELVEDGE_PLANNER SELVEDGE_PLAYWRIGHT_MODULE SELVEDGE_ENTRY SELVEDGE_RUN_BUDGET_MS \
  SELVEDGE_PLANNER_TOKEN_BUDGET SELVEDGE_STEP_TIMEOUT_MS SELVEDGE_RUN_DIR SELVEDGE_BASE NODE_PATH \
  PLAYWRIGHT_DISABLE_FORCED_CHROMIUM_PROXIED_LOOPBACK STUB_PW_GOTO_MS STUB_PW_TEXT STUB_PLANNER_MODE \
  STUB_PLANNER_LOG SHOP_USER

echo "-- static: no string-literal reason, no zip tool, one redactValues"
reasons="$(node --input-type=module -e "
import { pathToFileURL } from 'node:url';
const E = await import(pathToFileURL(process.env.SELVEDGE_LIB + '/env-config.mjs').href);
console.log(Object.keys(E.REASONS).join('|'));")"
hits="$(cd "$LIB/runner" && grep -nE "['\"\`]($reasons)['\"\`]" trace-redact.mjs run.mjs execute.mjs)"
{ [ -n "$reasons" ] && [ -z "$hits" ]; } && ok "AC1 runner/trace-redact.mjs, run.mjs and execute.mjs name no reason as a string literal (REASONS only)" || ko "string-literal reasons: $hits"
{ ! grep -qE "child_process|(from|import\() *['\"](jszip|yauzl|yazl|adm-zip)" "$LIB/runner/trace-redact.mjs" \
  && grep -qE "import \{[^}]*redactValues[^}]*\} from '../snapshot.mjs'" "$LIB/runner/trace-redact.mjs" \
  && grep -qE "import \{[^}]*redactTraceZip[^}]*\} from './trace-redact.mjs'" "$LIB/runner/execute.mjs"; } \
  && ok "trace-redact.mjs spawns no zip tool and imports no zip library; it takes redactValues from snapshot.mjs; execute.mjs keeps a trace only through redactTraceZip" \
  || ko "a second zip path or redactor"

echo "-- trace-redact.mjs on hand-built zips"
# zipgen.mjs <kind> <out.zip> — a hand-built zip (its own writer, independent of trace-redact.mjs).
cat > "$TMP/zipgen.mjs" <<'EOF'
import { writeFileSync } from 'node:fs';
import { deflateRawSync } from 'node:zlib';
const [kind, out] = process.argv.slice(2);
const T = new Uint32Array(256).map((_, n) => { let c = n; for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
const crc = (b) => { let c = 0xffffffff; for (const x of b) c = T[(c ^ x) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
const net = [
  { type: 'resource-snapshot', snapshot: { request: { url: 'http://localhost/a?u=alice-trace', headers: [{ name: 'Cookie', value: 'sid=COOKIEVAL1; theme=darkmode' }, { name: 'Authorization', value: 'Bearer TOKENVAL1' }, { name: 'Accept', value: 'text/html' }], cookies: [{ name: 'sid', value: 'COOKIEVAL1' }] }, response: { headers: [{ name: 'set-cookie', value: 'sid2=COOKIEVAL2; Path=/; HttpOnly' }], cookies: [{ name: 'sid2', value: 'COOKIEVAL2', path: '/' }] } } },
].map((l) => JSON.stringify(l)).join('\n') + '\n';
const trace = [
  { type: 'before', method: 'fill', params: { selector: 'internal:label="User"', value: 'alice-trace' } },
  { type: 'frame-snapshot', snapshot: { html: ['INPUT', { __playwright_value_: 'alice-trace' }] } },
].map((l) => JSON.stringify(l)).join('\n') + '\n';
const html = "<p>COOKIEVAL2 echoed</p><script>fetch('/', { headers: { Authorization: 'Bearer TOKENVAL1' } })</script>\nCookie: sid=COOKIEVAL1\n";
const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0xff, 0xfe, 0x00, 0x01, 0x80, 0x81]);
let entries = [
  { name: 'trace.network', data: Buffer.from(net), method: 8, descriptor: true },
  { name: 'trace.trace', data: Buffer.from(trace), method: 0 },
  { name: 'resources/page.html', data: Buffer.from(html), method: 8 },
  { name: 'resources/img.png', data: png, method: 0 },
];
let flags = 0, method = null, badCrc = false, zip64 = false;
if (kind === 'encrypted') flags = 1;
if (kind === 'bzip2') method = 12;
if (kind === 'badcrc') badCrc = true;
if (kind === 'zip64') zip64 = true;
if (kind === 'leaky-binary') entries[3] = { name: 'resources/img.png', data: Buffer.concat([png, Buffer.from('COOKIEVAL1')]), method: 0 };
if (kind === 'garbage') { writeFileSync(out, 'this is not a zip file at all, just text\n'.repeat(3)); process.exit(0); }
const parts = [], cds = [];
let off = 0;
for (const e of entries) {
  const m = method === null ? e.method : method;
  const body = m === 8 ? deflateRawSync(e.data) : e.data;
  const c = badCrc ? (crc(e.data) ^ 1) >>> 0 : crc(e.data);
  const name = Buffer.from(e.name);
  const f = flags | (e.descriptor ? 8 : 0);
  const lh = Buffer.alloc(30);
  lh.writeUInt32LE(0x04034b50, 0); lh.writeUInt16LE(20, 4); lh.writeUInt16LE(f, 6); lh.writeUInt16LE(m, 8);
  if (!e.descriptor) { lh.writeUInt32LE(c, 14); lh.writeUInt32LE(body.length, 18); lh.writeUInt32LE(e.data.length, 22); }
  lh.writeUInt16LE(name.length, 26);
  const dd = Buffer.alloc(e.descriptor ? 16 : 0);
  if (e.descriptor) { dd.writeUInt32LE(0x08074b50, 0); dd.writeUInt32LE(c, 4); dd.writeUInt32LE(body.length, 8); dd.writeUInt32LE(e.data.length, 12); }
  const ch = Buffer.alloc(46);
  ch.writeUInt32LE(0x02014b50, 0); ch.writeUInt16LE(20, 4); ch.writeUInt16LE(20, 6); ch.writeUInt16LE(f, 8); ch.writeUInt16LE(m, 10);
  ch.writeUInt32LE(c, 16); ch.writeUInt32LE(body.length, 20); ch.writeUInt32LE(e.data.length, 24); ch.writeUInt16LE(name.length, 28); ch.writeUInt32LE(off, 42);
  parts.push(lh, name, body, dd); cds.push(ch, name);
  off += 30 + name.length + body.length + dd.length;
}
const cd = Buffer.concat(cds);
const end = Buffer.alloc(22);
end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(zip64 ? 0xffff : entries.length, 8); end.writeUInt16LE(zip64 ? 0xffff : entries.length, 10);
end.writeUInt32LE(cd.length, 12); end.writeUInt32LE(off, 16);
writeFileSync(out, Buffer.concat([...parts, cd, end]));
EOF
# redact <in.zip> <out.zip> — prints redactTraceZip's result as JSON ({{SHOP_USER}} = alice-trace).
redact() {
  node --input-type=module -e "
import { pathToFileURL } from 'node:url';
const R = await import(pathToFileURL(process.env.SELVEDGE_LIB + '/runner/trace-redact.mjs').href);
process.stdout.write(JSON.stringify(R.redactTraceZip(process.argv[1], process.argv[2], { secrets: [{ name: 'SHOP_USER', value: 'alice-trace' }] })));" "$1" "$2"
}
# unzip_all <zip> <dir> — Python's zipfile (CRC-checked by testzip) extracts every entry into <dir>.
unzip_all() {
  python3 -c 'import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
bad = z.testzip()
if bad: sys.exit("bad CRC: " + bad)
z.extractall(sys.argv[2])
print("\n".join(z.namelist()))' "$1" "$2"
}
node "$TMP/zipgen.mjs" good "$TMP/good.zip"
res="$(redact "$TMP/good.zip" "$TMP/good-out.zip")"
names="$(unzip_all "$TMP/good-out.zip" "$TMP/good-x" 2>&1)"
{ grep -qF '"kept":true' <<<"$res" && [ "$names" = "$(printf 'trace.network\ntrace.trace\nresources/page.html\nresources/img.png')" ]; } \
  && ok "a deflated / stored / data-descriptor zip is kept: Python's zipfile reads the output whole (CRC-32s good), every entry in order" \
  || ko "good zip: res=$res names=$names"
export GX="$TMP/good-x"
# zcheck <label> <js> — over the extracted good zip: all (every entry's text), net (trace.network's
# JSON lines), tr (trace.trace's), html, png (Buffer).
zcheck() {
  local got
  got="$(node -e '
const fs = require("fs"), path = require("path"), d = process.env.GX;
const rd = (n) => fs.readFileSync(path.join(d, n));
const jl = (n) => rd(n).toString("utf8").split("\n").filter((l) => l.trim() !== "").map((l) => JSON.parse(l));
const all = ["trace.network", "trace.trace", "resources/page.html", "resources/img.png"].map((n) => rd(n).toString("latin1")).join("\n");
const net = jl("trace.network"), tr = jl("trace.trace"), html = rd("resources/page.html").toString("utf8"), png = rd("resources/img.png");
const headers = net.flatMap((l) => [...l.snapshot.request.headers, ...l.snapshot.response.headers]);
let v; try { v = eval(process.argv[1]); } catch (e) { v = "error: " + e.message; }
process.stdout.write(v === true ? "true" : "false (" + String(v).slice(0, 80) + ") html=" + JSON.stringify(html) + " net=" + JSON.stringify(net).slice(0, 400));
' "$2" 2>&1)"
  if [ "$got" = "true" ]; then ok "$1"; else ko "$1 — $got"; fi
}
zcheck "AC25 every cookie value seen in a Cookie / Set-Cookie header (COOKIEVAL1, COOKIEVAL2, darkmode) is gone from every entry, the page HTML and HAR cookies included" \
  '!/COOKIEVAL1|COOKIEVAL2|darkmode/.test(all) && net[0].snapshot.request.cookies[0].value === "[redacted]" && html.includes("<p>[redacted] echoed</p>")'
zcheck "AC25 Cookie, Set-Cookie and Authorization header values read [redacted] (a JSON header object and a raw header line); other headers are kept" \
  'headers.filter((h) => /^(cookie|set-cookie|authorization)$/i.test(h.name)).length === 3 && headers.every((h) => /^(cookie|set-cookie|authorization)$/i.test(h.name) ? h.value === "[redacted]" : h.value === "text/html") && html.includes("Cookie: [redacted]") && !all.includes("TOKENVAL1")'
zcheck "AC25 every resolved {{NAME}} value is written back as {{NAME}} (the fill action, the DOM snapshot, a url)" \
  '!all.includes("alice-trace") && tr[0].params.value === "{{SHOP_USER}}" && tr[1].snapshot.html[1].__playwright_value_ === "{{SHOP_USER}}" && net[0].snapshot.request.url.endsWith("u={{SHOP_USER}}")'
zcheck "a binary entry holding no secret is copied byte for byte" 'png.equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0xff, 0xfe, 0x00, 0x01, 0x80, 0x81]))'
for spec in 'garbage|not a zip' 'encrypted|encrypted' 'bzip2|compression method 12' 'zip64|zip64' 'badcrc|CRC-32' 'leaky-binary|binary entry holds a secret'; do
  kind="${spec%%|*}"; why="${spec#*|}"
  node "$TMP/zipgen.mjs" "$kind" "$TMP/$kind.zip"
  res="$(redact "$TMP/$kind.zip" "$TMP/$kind-out.zip")"
  { grep -qF '"kept":false' <<<"$res" && grep -qF "$why" <<<"$res" && [ ! -e "$TMP/$kind-out.zip" ] && [ -z "$(ls "$TMP" | grep -F "$kind-out.zip.tmp")" ]; } \
    && ok "a zip it cannot redact whole ($kind) is dropped, never written: $why" || ko "drop $kind: res=$res"
done

# shellcheck source=lib/run-helpers.sh
. "$TESTS_DIR/lib/run-helpers.sh"   # the fixture app, newrepo, folder, stub_spec, the planner shims
rh_start_app
rh_setup
R="$TMP/repo"; newrepo "$R"; export R
export STUB_PW_LOG="$TMP/launches.log"

# runs_list <repo> — the run folders under <repo>/.selvedge/runs, one per line, sorted.
runs_list() { ls -1 "$1/.selvedge/runs" 2>/dev/null | sort; }

# sel <label> <selvedge args…> — `env $RUN_ENV… selvedge <args>` in ${RUN_CWD:-$R} with the recording
# planner shims; sets OUT / ERR (files), RC and NEW (the run folder that appeared, "" for none); the
# launch log is emptied first. RUN_ENV holds extra VAR=value words.
sel() {
  local label="$1" before; shift
  OUT="$TMP/o/$label.out"; ERR="$TMP/o/$label.err"
  : > "$STUB_PW_LOG"
  before="$(runs_list "${RUN_CWD:-$R}")"
  # shellcheck disable=SC2086
  (cd "${RUN_CWD:-$R}" && env "SELVEDGE_PLANNER=sh $TMP/planner-shim.sh" "PATH=$TMP/stubbin:$PATH" ${RUN_ENV:-} bash "$CLI" "$@" >"$OUT" 2>"$ERR"); RC=$?
  NEW="$(comm -13 <(printf '%s\n' "$before") <(runs_list "${RUN_CWD:-$R}") | grep -v '^$' | tr '\n' ' ' | sed 's/ $//')"
  [ -n "$NEW" ] && NEW="${RUN_CWD:-$R}/.selvedge/runs/$NEW"
  export OUT ERR RC NEW
}

# check <label> <js expression> — evaluated over the last sel(), with:
#   out err rc        the call's stdout, stderr and exit code
#   NEW               the new run folder ("" for none); FROZEN ($FROZEN), the folder replayed
#   j(d, n) t(d, n)   a folder's JSON file / text (null when absent); ev(d) its evidence lines
#   runs(repo)        <repo>/.selvedge/runs.jsonl lines; launches() the stub's launch lines
#   hashes(d)         {file: sha256} of every file under folder d; id(d) a folder's run id
check() {
  local label="$1" expr="$2" got
  got="$(node -e '
const fs = require("fs"), path = require("path"), crypto = require("crypto");
const E = process.env;
const txt = (p) => { try { return fs.readFileSync(p, "utf8"); } catch { return ""; } };
const jl = (p) => txt(p).split("\n").filter((l) => l.trim() !== "").map((l) => JSON.parse(l));
const out = txt(E.OUT), err = txt(E.ERR), rc = Number(E.RC), NEW = E.NEW || "", FROZEN = E.FROZEN || "";
const t = (d, n) => { try { return fs.readFileSync(path.join(d, n), "utf8"); } catch { return null; } };
const j = (d, n) => (t(d, n) === null ? null : JSON.parse(t(d, n)));
const ev = (d) => jl(path.join(d, "evidence.jsonl"));
const runs = (repo) => jl(path.join(repo, ".selvedge", "runs.jsonl"));
const id = (d) => path.basename(d);
const launches = () => txt(E.STUB_PW_LOG).split("\n").filter((l) => l === "launch").length;
const walk = (d) => fs.readdirSync(d).sort().flatMap((n) => { const p = path.join(d, n); return fs.statSync(p).isDirectory() ? walk(p) : [p]; });
const hashes = (d) => Object.fromEntries(walk(d).map((p) => [path.relative(d, p), crypto.createHash("sha256").update(fs.readFileSync(p)).digest("hex")]));
let v;
try { v = eval(process.argv[1]); } catch (e) { v = "error: " + e.message; }
if (v === true) process.stdout.write("true");
else process.stdout.write("false (" + String(v).slice(0, 80) + ") rc=" + E.RC + " new=" + NEW + " out=" + JSON.stringify(out.slice(0, 400)) + " err=" + JSON.stringify(err.slice(-900)));
' "$expr" 2>&1)"
  if [ "$got" = "true" ]; then ok "$label"; else ko "$label — $got"; fi
}

# hash_file <dir> <out.json> — {file: sha256} of every file under <dir> (the same as check's hashes).
hash_file() {
  node -e 'const fs = require("fs"), path = require("path"), crypto = require("crypto"); const d = process.argv[1]; const walk = (x) => fs.readdirSync(x).sort().flatMap((n) => { const p = path.join(x, n); return fs.statSync(p).isDirectory() ? walk(p) : [p]; }); fs.writeFileSync(process.argv[2], JSON.stringify(Object.fromEntries(walk(d).map((p) => [path.relative(d, p), crypto.createHash("sha256").update(fs.readFileSync(p)).digest("hex")]))));' "$1" "$2"
}

STUB="SELVEDGE_PLAYWRIGHT_MODULE=$STUB_PW"

echo "-- CLI surface"
sel help run help
check "selvedge run help documents --replay and --trace" 'rc === 0 && out.includes("--replay <frozen-run-dir>") && out.includes("--trace")'
sel replay-extra run --replay "$TMP" "$TMP"
check "--replay with a <run-dir> as well: a usage error (exit 2)" 'rc === 2 && err.includes("--replay takes the frozen run folder") && NEW === ""'
sel replay-nodir run --replay "$TMP/no-such-dir"
check "--replay of a path that is not a directory: exit 2, no new folder" 'rc === 2 && err.includes("is not a directory") && NEW === ""'

echo "-- AC22 replay of a frozen run that PASSed (stub browser)"
F22="$(folder ac22 "$R" "$(SPEC_EXTRA=',"usage":{"input_tokens":111,"output_tokens":22}' stub_spec 1 2)")"
export FROZEN="$F22"
RUN_ENV="$STUB" sel ac22-run run "$F22"
check "setup: the frozen folder runs and PASSes (its run line carries planner_tokens 133)" 'rc === 0 && runs(E.R).filter((l) => l.event === "run").pop().planner_tokens === 133'
hash_file "$F22" "$TMP/f22.json"; export F22_HASHES="$TMP/f22.json"
FREEZES="$(grep -c '"event":"freeze"' "$R/.selvedge/runs.jsonl")"; export FREEZES
RUN_ENV="$STUB SELVEDGE_PLANNER_TOKEN_BUDGET=100" sel ac22 run --replay "$F22"
check "AC22 run --replay: exit 0, a NEW run folder, verdict PASS for every criterion" \
  'rc === 0 && NEW !== "" && NEW !== FROZEN && Object.values(j(NEW, "verdict.json").criteria).every((c) => c.verdict === "PASS") && out.includes("verdict PASS " + path.join(fs.realpathSync(NEW), "verdict.json"))'
check "AC22 the replayed plan.json is byte-identical (same plan_sha256), with plan.sha256, freeze.json and criteria.json copied" \
  'fs.readFileSync(path.join(NEW, "plan.json")).equals(fs.readFileSync(path.join(FROZEN, "plan.json"))) && ["plan.sha256", "freeze.json", "criteria.json"].every((n) => t(NEW, n) === t(FROZEN, n)) && j(NEW, "verdict.json").plan_sha256 === j(FROZEN, "verdict.json").plan_sha256'
check "AC22 verdict.json and run_start carry replay_of: <frozen run id> and the unchanged plan_revision" \
  'const v = j(NEW, "verdict.json"); v.replay_of === id(FROZEN) && ev(NEW)[0].replay_of === id(FROZEN) && v.plan_revision === j(FROZEN, "verdict.json").plan_revision && v.plan_revision === 1'
check "AC22 the run line carries replay_of, plan_revision 1 and planner_tokens 0 (the replay spends none; the token budget 100 < 133 did not apply)" \
  'const l = runs(E.R).filter((x) => x.event === "run").pop(); l.run_id === id(NEW) && l.replay_of === id(FROZEN) && l.plan_revision === 1 && l.planner_tokens === 0 && l.verdict === "PASS" && l.plan_sha256 === j(NEW, "verdict.json").plan_sha256'
check "AC22 the frozen folder is unchanged and runs.jsonl gains no freeze line" \
  'JSON.stringify(hashes(FROZEN)) === txt(E.F22_HASHES) && runs(E.R).filter((l) => l.event === "freeze").length === Number(E.FREEZES)'
export REPLAY1="$NEW"
RUN_ENV="$STUB" sel ac22-again run --replay "$F22"
check "AC22 a second replay of the same folder makes another new folder (a replay never reuses one)" 'rc === 0 && NEW !== "" && NEW !== E.REPLAY1 && j(NEW, "verdict.json").replay_of === id(FROZEN)'
RUN_ENV="$STUB" sel ac22-trace-stub run --replay "$F22" --trace
check "--trace where the browser cannot trace (the stub): the trace is dropped with its reason, the run still PASSes, no traces/ kept" \
  'rc === 0 && err.includes("trace: dropped (tracing did not start") && !fs.existsSync(path.join(NEW, "traces"))'

echo "-- AC24 an edited frozen plan is refused before a folder exists (stub browser)"
cp "$F22/plan.json" "$TMP/f22-plan.json"; cp "$F22/plan.sha256" "$TMP/f22-plan.sha256"
node -e 'const fs = require("fs"); const f = process.argv[1]; const b = fs.readFileSync(f); const i = b.indexOf("stub"); b[i] = "S".charCodeAt(0); fs.writeFileSync(f, b);' "$F22/plan.json"
RUN_ENV="$STUB" sel ac24 run --replay "$F22"
check "AC24 one byte of the frozen plan.json edited: exit 2 plan_modified, no new run folder, no browser launched" \
  'rc === 2 && err.includes("plan_modified") && NEW === "" && launches() === 0'
printf '%s  plan.json\n' "$(node -e 'process.stdout.write(require("crypto").createHash("sha256").update(require("fs").readFileSync(process.argv[1])).digest("hex"))' "$F22/plan.json")" > "$F22/plan.sha256"
RUN_ENV="$STUB" sel ac24-both run --replay "$F22"
check "AC24 plan.json and plan.sha256 edited consistently: still exit 2 plan_modified (runs.jsonl's freeze line disagrees), no new folder, no launch" \
  'rc === 2 && err.includes("plan_modified") && err.includes("freeze line for run " + id(FROZEN)) && NEW === "" && launches() === 0'
cp "$TMP/f22-plan.json" "$F22/plan.json"; cp "$TMP/f22-plan.sha256" "$F22/plan.sha256"
RUN_ENV="$STUB" sel ac24-replay-of-replay run --replay "$REPLAY1"
check "AC24 a replay folder has no freeze line of its own: plan_modified, naming the run it copies; no new folder" \
  'rc === 2 && err.includes("plan_modified") && err.includes("replay that folder") && err.includes(id(FROZEN)) && NEW === ""'
F24n="$(cd "$R" && bash "$CLI" plan --init "$TMP/crit-ac22.json" 2>/dev/null)"
RUN_ENV="$STUB" sel ac24-notfrozen run --replay "$F24n"
check "replay of a folder with no plan.sha256: exit 2 not_frozen, no new folder" 'rc === 2 && err.includes("not_frozen") && NEW === ""'
RUN_ENV="$STUB SELVEDGE_ENTRY=nightly" sel ac24-badentry run --replay "$F22"
check "replay with a bad SELVEDGE_ENTRY: a usage error (exit 2) before any folder exists" 'rc === 2 && err.includes("SELVEDGE_ENTRY") && NEW === ""'
RF="$TMP/repo-failing-hook"; newrepo "$RF"
FF="$(folder failhook "$RF" "$(stub_spec 3)")"
printf '{"schema_version":1,"origins":["%s"],"hooks":{"reset":"exit 7"}}\n' "$AURL" > "$RF/selvedge.json"
(cd "$RF" && node --input-type=module -e "
import { pathToFileURL } from 'node:url';
const A = await import(pathToFileURL(process.env.SELVEDGE_LIB + '/env-approvals.mjs').href);
const E = await import(pathToFileURL(process.env.SELVEDGE_LIB + '/env-config.mjs').href);
const { config, root } = E.loadConfig();
A.writeApproval({ root, identity: A.repoIdentity(root), sha256: A.hooksSha256(config.hooks) });")
RUN_CWD="$RF" RUN_ENV="$STUB" sel failhook run --replay "$FF"
check "a replay whose approved reset hook fails: exit 1 and no new run folder is left behind" 'rc === 1 && err.includes("hook reset failed") && NEW === "" && launches() === 0'

echo "-- AC27 the README documents run and verdict"
RD="$PLUGIN_DIR/README.md"
missing=""
for s in 'selvedge run' '--replay' '--trace' 'selvedge verdict' 'evidence.jsonl' 'verdict.json' 'runs.jsonl' 'run_start' 'criterion_end' 'run_end' 'replay_of' 'SELVEDGE_ENTRY' 'SELVEDGE_RUN_BUDGET_MS' 'SELVEDGE_STEP_TIMEOUT_MS' 'stable wait' 'traces/<criterion-id>.zip' '[redacted]'; do
  grep -qF -- "$s" "$RD" || missing="$missing [$s]"
done
grep -qE '^- `SELVEDGE_RUN_BUDGET_MS`' "$RD" || missing="$missing [SELVEDGE_RUN_BUDGET_MS bullet]"
grep -qF 'running a plan arrives in later releases' "$RD" && missing="$missing [stale: running a plan arrives later]"
[ -z "$missing" ] && ok "AC27 README.md names run (--replay, --trace), verdict, the evidence files and line kinds, replay_of, SELVEDGE_ENTRY, a SELVEDGE_RUN_BUDGET_MS bullet and the stable wait" \
  || ko "AC27 README misses:$missing"

echo "-- real Chromium: AC22, AC23, AC25"
HOME="$REAL_HOME" pw_require_or_skip; pwrc=$?
if [ "$pwrc" -eq 1 ]; then
  ko "playwright_install_failed under CI: no browser arm can run"
  finish
fi
if [ "$pwrc" -eq 0 ]; then
  PW="SELVEDGE_PLAYWRIGHT_MODULE=$PW_MODULE"
  control() { node -e 'fetch(process.argv[1]).then((r) => r.text()).then((t) => process.stdout.write(t.trim()), () => process.stdout.write("fetch failed"))' "$AURL/control/cart-label$1"; }

  R23="$TMP/repo23"; newrepo "$R23"; export R23
  printf -- '- Opening the cart and setting Quantity to 2 shows the Total "12"\n' | (cd "$R23" && bash "$CLI" criteria from-text) > "$TMP/modal-criteria.json" 2>/dev/null
  F23="$(cd "$R23" && env "SELVEDGE_PLANNER=bash $TESTS_DIR/fixtures/stub-planner.sh" STUB_PLANNER_MODE=modal STUB_PLANNER_LOG="$TMP/log-modal" "$PW" bash "$CLI" plan "$TMP/modal-criteria.json" 2>"$TMP/o/plan23.err")"
  export FROZEN="$F23"
  RUN_CWD="$R23" RUN_ENV="$PW" sel ac23-run run "$F23"
  check "setup: the modal plan (stub-planner.sh mode modal) runs and PASSes; without --trace no trace is written" \
    'rc === 0 && Object.values(j(FROZEN, "verdict.json").criteria)[0].verdict === "PASS" && !fs.existsSync(path.join(FROZEN, "traces")) && !fs.readdirSync(FROZEN).some((n) => n.endsWith(".zip"))'
  RUN_CWD="$R23" RUN_ENV="$PW" sel ac22-real run --replay "$F23"
  check "AC22 run --replay of the modal folder against the same app: PASS again, plan.json byte-identical, replay_of the frozen id; no trace without --trace" \
    'rc === 0 && Object.values(j(NEW, "verdict.json").criteria)[0].verdict === "PASS" && fs.readFileSync(path.join(NEW, "plan.json")).equals(fs.readFileSync(path.join(FROZEN, "plan.json"))) && j(NEW, "verdict.json").replay_of === id(FROZEN) && !fs.existsSync(path.join(NEW, "traces"))'
  [ "$(control '?name=View%20basket')" = "ok" ] && ok "setup: the fixture renames the Open cart button's accessible name to \"View basket\"" || ko "setup: control request failed"
  RUN_CWD="$R23" RUN_ENV="$PW SELVEDGE_STEP_TIMEOUT_MS=1000" sel ac23 run --replay "$F23"
  check "AC23 after the rename, run --replay: BLOCKED step_failed naming the click's step index (not PASS)" \
    'const steps = Object.values(j(NEW, "plan.json").steps_by_criterion)[0].steps; const ci = steps.findIndex((s) => s.type === "click" && s.locator.name === "Open cart"); const c = Object.values(j(NEW, "verdict.json").criteria)[0]; rc === 2 && ci >= 0 && c.verdict === "BLOCKED" && c.reason === "step_failed" && c.failed_step === ci'
  check "AC23 the replayed plan.json still holds the original locator (role button, name \"Open cart\"), byte-identical to the frozen one" \
    't(NEW, "plan.json").includes("\"name\": \"Open cart\"") && fs.readFileSync(path.join(NEW, "plan.json")).equals(fs.readFileSync(path.join(FROZEN, "plan.json")))'
  [ "$(control '')" = "ok" ] && ok "setup: the fixture's Open cart name is reset" || ko "setup: reset control request failed"

  F25="$(folder ac25 "$R" '{"criteria":[
{"text":"The account page shows \"signed in\"","steps":[{"type":"goto","url":"$O/silent-cookie"},{"type":"read","property":"text","locator":{"testid":"whoami"}},{"type":"expect","op":"equals","value":"signed in"}]},
{"text":"After the account page, filling User shows \"Reversed: resu-ecart-ecila\"","steps":[{"type":"goto","url":"$O/silent-cookie"},{"type":"goto","url":"$O/echo"},{"type":"fill","locator":{"label":"User"},"value":"{{SHOP_USER}}"},{"type":"read","property":"text","locator":{"testid":"echo-reversed"}},{"type":"expect","op":"equals","value":"Reversed: resu-ecart-ecila"}]}]}')"
  export FROZEN="$F25"
  RUN_ENV="$PW SHOP_USER=alice-trace-user" sel ac25 run --trace "$F25"
  SECRETS="$(node --input-type=module -e "
import { pathToFileURL } from 'node:url';
const A = await import(pathToFileURL(process.env.APP).href);
process.stdout.write(A.SILENT_COOKIE_VALUE + ' ' + A.BEARER_TOKEN);")"
  export COOKIE_VALUE="${SECRETS% *}" BEARER="${SECRETS#* }"
  ids="$(node -e 'console.log(Object.keys(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).steps_by_criterion).join(" "))' "$F25/plan.json")"
  xs=""
  for cid in $ids; do
    unzip_all "$F25/traces/$cid.zip" "$TMP/trace-$cid" >/dev/null 2>"$TMP/o/unzip-$cid.err" && xs="$xs $TMP/trace-$cid"
  done
  export XS="$xs"
  check "AC25 run --trace: both criteria PASS (the cookie was sent, the bearer fetch answered, the page got the value) and each kept traces/<criterion-id>.zip, which Python's zipfile reads whole" \
    'const dirs = E.XS.trim().split(" ").filter(Boolean); rc === 0 && Object.values(j(FROZEN, "verdict.json").criteria).every((c) => c.verdict === "PASS") && dirs.length === 2 && err.includes("(redacted)")'
  # every extracted trace file's text, and its network header objects
  cat > "$TMP/trace-scan.cjs" <<'EOF'
const fs = require('fs'), path = require('path');
const walk = (d) => fs.readdirSync(d).flatMap((n) => { const p = path.join(d, n); return fs.statSync(p).isDirectory() ? walk(p) : [p]; });
const files = process.env.XS.trim().split(' ').filter(Boolean).flatMap(walk);
const all = files.map((p) => fs.readFileSync(p).toString('latin1')).join('\n');
const headers = [];
for (const p of files.filter((f) => f.endsWith('.network'))) {
  for (const l of fs.readFileSync(p, 'utf8').split('\n')) {
    if (!l.trim()) continue;
    const s = JSON.parse(l).snapshot;
    if (s) headers.push(...(s.request.headers || []), ...(s.response.headers || []));
  }
}
module.exports = { files, all, headers };
EOF
  export SCAN="$TMP/trace-scan.cjs"
  check "AC25 the unzipped traces hold no occurrence of the cookie value (set by a page that never prints it) or of the bearer token" \
    'const S = require(E.SCAN); S.files.length > 0 && !S.all.includes(E.COOKIE_VALUE) && !S.all.includes(E.BEARER)'
  check "AC25 the unzipped traces hold no resolved {{NAME}} value (alice-trace-user); the fill they record reads {{SHOP_USER}}" 'const S = require(E.SCAN); S.files.length > 0 && !S.all.includes("alice-trace-user") && S.all.includes("{{SHOP_USER}}")'
  check "AC25 every Cookie, Set-Cookie and Authorization header in the trace network log reads [redacted] (each of the three is present)" \
    'const S = require(E.SCAN); const h = S.headers.filter((x) => /^(cookie|set-cookie|authorization)$/i.test(x.name)); ["cookie", "set-cookie", "authorization"].every((n) => h.some((x) => x.name.toLowerCase() === n)) && h.every((x) => x.value === "[redacted]")'
  check "AC25 only the redacted zips are kept in the run folder (no raw trace)" \
    'const walk = (d) => fs.readdirSync(d).flatMap((n) => { const p = path.join(d, n); return fs.statSync(p).isDirectory() ? walk(p) : [p]; }); const zips = walk(FROZEN).filter((p) => /\.zip|\.tmp-/.test(p)); zips.length === 2 && zips.every((p) => p.startsWith(path.join(FROZEN, "traces") + path.sep) && p.endsWith(".zip"))'
else
  echo "  (browser arms skipped outside CI; parts 1 and 2 above decide)"
fi

echo "-- AC17/AC22 no model in any run or replay"
check "AC22 the recording SELVEDGE_PLANNER and the PATH-stub claude recorded zero calls across every run and replay above" \
  '!fs.existsSync(E.PLANNER_CALLS) && !fs.existsSync(E.CLAUDE_CALLS)'

finish
