#!/usr/bin/env bash
# test-comment.sh — pins `selvedge comment <run-dir> --pr <n>` (selvedge/lib/comment.mjs,
# selvedge/lib/comment-render.mjs) and the `comment` key of selvedge.json (selvedge/lib/env-config.mjs,
# schemas/selvedge-config.schema.json): the key's validation and defaults; ONE comment found by its
# marker on a comment by the signed-in login and updated in place (an unmarked comment by the same
# account untouched, a marked comment by another login never PATCHed, an unreadable login fails
# closed); a text-only body
# with no URL origin or query, header name, fill value, {{NAME}} value or evidence file name; read
# values unpublished by default, opted in only from the base ref, refused on a repo that is not
# private, and redacted when shown; the per-criterion revision cell; the confirmation, the run-folder
# refusals and a failing gh; and the body reaching gh byte for byte as a file. Every arm turns red
# under its row of the brief's pin-mutation table.
#
# Hermetic: a fresh temp HOME, a temp git repo whose refs carry the base-branch selvedge.json, `gh`
# is a PATH stub that keeps the PR's comments in a temp JSON file and records every argv (no network,
# no browser: the run folders are written here). Needs node (>= 18) and git; a missing one is a FAIL,
# never a skip.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$TESTS_DIR/.." && pwd)"
CLI="$PLUGIN_DIR/bin/selvedge"
export SELVEDGE_LIB="$PLUGIN_DIR/lib"
export SELVEDGE_SCHEMA="$PLUGIN_DIR/schemas/selvedge-config.schema.json"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "  ok   $1"; }
ko() { fail=$((fail + 1)); echo "  FAIL $1"; }

for tool in node git; do
  command -v "$tool" >/dev/null 2>&1 || { echo "  FAIL $tool is not on PATH (test-comment.sh needs it)"; echo "test-comment: 0 passed, 1 failed"; exit 1; }
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/selvedge-comment.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_CONFIG_NOSYSTEM=1

# The fixture secret {{APP_PASS}} stands for: it must never reach a body.
export APP_PASS='s3cr3t-fixture-pass-QZXW'

R="$TMP/repo"
mkdir -p "$R" && git -C "$R" init -q && git -C "$R" symbolic-ref HEAD refs/heads/main

# base_ref <name> <selvedge.json text> — a commit holding that selvedge.json, as refs/remotes/origin/<name>.
base_ref() {
  printf '%s\n' "$2" > "$R/selvedge.json"
  git -C "$R" add selvedge.json && git -C "$R" commit -q -m "base $1" --allow-empty
  git -C "$R" update-ref "refs/remotes/origin/$1" HEAD
  rm -f "$R/selvedge.json"
}
base_ref plain '{"schema_version":1,"origins":["http://localhost:4100"]}'
base_ref optin '{"schema_version":1,"origins":["http://localhost:4100"],"comment":{"read_values":true,"redact":["ORD-[0-9]+"]}}'
git -C "$R" rm -q --cached selvedge.json 2>/dev/null; git -C "$R" commit -q -m 'no config on the working branch' --allow-empty

# ---- the gh stub ------------------------------------------------------------------------------
# State: $GH_COMMENTS (a JSON array of {id, body, user}); every argv is appended as one JSON line to
# $GH_ARGV_LOG; each body received from a file is also kept as $GH_BODIES/<n>. Serves `pr view <n>
# --json baseRefName` ($GH_BASE), `repo view --json visibility` ($GH_VISIBILITY; FAIL → exit 1),
# `api user --jq .login` ($GH_LOGIN, default "me"; FAIL → exit 1),
# `api --paginate --slurp …/issues/<n>/comments` (PR 99: exit 1), `api -X PATCH …/issues/comments/<id>
# -F body=@<file>` and `pr comment <n> --body-file <file>`. A body is read ONLY from a file argument.
STUB="$TMP/stub-bin"; mkdir -p "$STUB" "$TMP/bodies"
cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env node
const fs = require('fs');
const argv = process.argv.slice(2);
fs.appendFileSync(process.env.GH_ARGV_LOG, JSON.stringify(argv) + '\n');
const load = () => JSON.parse(fs.readFileSync(process.env.GH_COMMENTS, 'utf8'));
const save = (c) => fs.writeFileSync(process.env.GH_COMMENTS, JSON.stringify(c, null, 2));
const keep = (body) => {
  const n = fs.readdirSync(process.env.GH_BODIES).length + 1;
  fs.writeFileSync(`${process.env.GH_BODIES}/${n}`, body);
};
const die = (m) => { process.stderr.write(`gh stub: ${m}\n`); process.exit(1); };
const a = argv.join(' ');
if (/^pr view [0-9]+ --json baseRefName$/.test(a)) {
  if (argv[2] === '99') die('no such PR');
  process.stdout.write(JSON.stringify({ baseRefName: process.env.GH_BASE || 'plain' }));
  process.exit(0);
}
if (a === 'repo view --json visibility') {
  if (process.env.GH_VISIBILITY === 'FAIL') die('cannot read the repo');
  process.stdout.write(JSON.stringify({ visibility: process.env.GH_VISIBILITY || 'PUBLIC' }));
  process.exit(0);
}
if (a === 'api user --jq .login') {
  if (process.env.GH_LOGIN === 'FAIL') die('HTTP 401');
  process.stdout.write(`${process.env.GH_LOGIN || 'me'}\n`);
  process.exit(0);
}
let m = a.match(/^api --paginate --slurp repos\/\{owner\}\/\{repo\}\/issues\/([0-9]+)\/comments$/);
if (m) {
  if (m[1] === '99') die('HTTP 404');
  process.stdout.write(JSON.stringify([load()]));
  process.exit(0);
}
if (argv[0] === 'api' && argv.includes('PATCH')) {
  const target = argv.find((x) => /^repos\/\{owner\}\/\{repo\}\/issues\/comments\/[0-9]+$/.test(x));
  const field = argv.find((x) => x.startsWith('body=@'));
  if (!target || !field) die(`unsupported PATCH: ${a}`);
  const id = Number(target.split('/').pop());
  const body = fs.readFileSync(field.slice('body=@'.length), 'utf8');
  const all = load();
  const c = all.find((x) => x.id === id);
  if (!c) die('HTTP 404');
  c.body = body; save(all); keep(body);
  process.stdout.write(JSON.stringify({ id, html_url: `https://github.example/o/r/pull/42#issuecomment-${id}` }));
  process.exit(0);
}
if (argv[0] === 'pr' && argv[1] === 'comment') {
  const i = argv.indexOf('--body-file');
  if (i < 0 || !argv[i + 1]) die(`unsupported pr comment: ${a}`);
  const body = fs.readFileSync(argv[i + 1], 'utf8');
  const all = load();
  const id = all.reduce((n, x) => Math.max(n, x.id), 100) + 1;
  all.push({ id, body, user: { login: process.env.GH_LOGIN || 'me' } }); save(all); keep(body);
  process.stdout.write(`https://github.example/o/r/pull/${argv[2]}#issuecomment-${id}\n`);
  process.exit(0);
}
die(`unsupported: ${a}`);
EOF
chmod +x "$STUB/gh"
export GH_ARGV_LOG="$TMP/gh-argv.log" GH_COMMENTS="$TMP/comments.json" GH_BODIES="$TMP/bodies"
export PATH="$STUB:$PATH"

UNMARKED_BODY="an unrelated note by the same account, it's \\ here
second line"

# reset_gh — no recorded calls, no kept bodies, and the PR holds one unmarked comment by the same account.
reset_gh() {
  : > "$GH_ARGV_LOG"
  rm -f "$GH_BODIES"/*
  node -e 'require("fs").writeFileSync(process.env.GH_COMMENTS, JSON.stringify([{ id: 101, body: process.argv[1], user: { login: "me" } }], null, 2))' "$UNMARKED_BODY"
  unset GH_VISIBILITY GH_LOGIN; export GH_BASE=plain
}

# run [stdin-file] -- <cli args…> — sets $rc, $out, $err; runs in the repo.
run() {
  local input=/dev/null
  if [ "$1" != "--" ]; then input="$1"; shift; fi
  shift
  (cd "$R" && bash "$CLI" "$@" >"$TMP/stdout" 2>"$TMP/stderr" <"$input"); rc=$?
  out="$(cat "$TMP/stdout")"
  err="$(cat "$TMP/stderr")"
}

# The marker comment's body as the stub holds it (empty when none), and how many hold the marker.
marked_body() { node -e 'const c = JSON.parse(require("fs").readFileSync(process.env.GH_COMMENTS, "utf8")).filter((x) => x.body.includes("<!-- selvedge:verdict -->")); process.stdout.write(c.length ? c[0].body : "")'; }
marked_count() { node -e 'process.stdout.write(String(JSON.parse(require("fs").readFileSync(process.env.GH_COMMENTS, "utf8")).filter((x) => x.body.includes("<!-- selvedge:verdict -->")).length))'; }
posted() { grep -cE '"PATCH"|"pr","comment"' "$GH_ARGV_LOG" 2>/dev/null || true; }

# ---- run-folder fixtures --------------------------------------------------------------------------
# mkrun <run-id> <spec.json> — writes .selvedge/runs/<run-id>/ in the repo: criteria.json, plan.json,
# plan.sha256, verdict.json (plan_sha256 = the plan's real sha256), plus an evidence.jsonl and a
# screenshot that must never reach a body.
cat > "$TMP/mkrun.cjs" <<'EOF'
const fs = require('fs'); const path = require('path'); const crypto = require('crypto');
const [dir, specFile] = process.argv.slice(2);
const spec = JSON.parse(fs.readFileSync(specFile, 'utf8'));
fs.mkdirSync(path.join(dir, 'screenshots'), { recursive: true });
const pretty = (v) => JSON.stringify(v, null, 2) + '\n';
fs.writeFileSync(path.join(dir, 'criteria.json'), pretty({ schema_version: 1, source: null, criteria: spec.criteria }));
const plan = pretty(spec.plan);
fs.writeFileSync(path.join(dir, 'plan.json'), plan);
const sha = crypto.createHash('sha256').update(plan).digest('hex');
fs.writeFileSync(path.join(dir, 'plan.sha256'), `${sha}  plan.json\n`);
const base = { schema_version: 1, target: 'web', plan_sha256: sha, playwright_version: '1.0.0', plan_revision: spec.plan.plan_revision, prior_revisions: [], replay_of: null, data_state: 'managed', hooks_run: [] };
fs.writeFileSync(path.join(dir, 'verdict.json'), pretty({ ...base, ...spec.verdict }));
fs.writeFileSync(path.join(dir, 'evidence.jsonl'), '{"kind":"run_start"}\n');
for (const id of Object.keys(spec.verdict.criteria)) fs.writeFileSync(path.join(dir, 'screenshots', `${id}.png`), 'png');
EOF
RUNS="$R/.selvedge/runs"
mkrun() { mkdir -p "$RUNS/$1" && node "$TMP/mkrun.cjs" "$RUNS/$1" "$2"; }

# A criterion verdict entry (node expression helper inside the spec builders).
SHA_A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

# Fixture "main": four criteria, every verdict kind, the AC3 hazards in the plan and texts.
cat > "$TMP/spec-main.json" <<EOF
{
  "criteria": [
    { "id": "c-aaaaaaaaaaa1", "text": "The cart at https://shop.example.test/cart?id=9 shows the total, it's a\\\\b path" },
    { "id": "c-aaaaaaaaaaa2", "text": "The profile shows the user's name" },
    { "id": "c-aaaaaaaaaaa3", "text": "The orders page lists the last order" },
    { "id": "c-aaaaaaaaaaa4", "text": "The badge shows the plan tier" }
  ],
  "plan": {
    "schema_version": 1, "target": "web", "criteria_sha256": "$SHA_A", "plan_revision": 1,
    "origins": ["http://localhost:4100"],
    "steps_by_criterion": {
      "c-aaaaaaaaaaa1": { "interpretation": "Open https://shop.example.test/cart?id=9 and read the total", "polarity": "positive",
        "unverified_assumptions": [{ "text": "The cart already holds two items", "material": false }],
        "steps": [
          { "type": "goto", "url": "http://localhost:4100/account?token=abc" },
          { "type": "fill", "locator": { "label": "Password {{APP_PASS}}" }, "value": "{{APP_PASS}}" },
          { "type": "fill", "locator": { "label": "Nickname" }, "value": "literal-fill-value-QQ" },
          { "type": "select", "locator": { "label": "Size" }, "value": "select-value-ZZ" },
          { "type": "click", "locator": { "text": "Authorization" } },
          { "type": "read", "property": "text", "locator": { "testid": "cart-total" } },
          { "type": "expect", "op": "equals", "value": "https://shop.example.test/cart?id=9" }
        ] },
      "c-aaaaaaaaaaa2": { "interpretation": "Read the profile name", "polarity": "positive", "unverified_assumptions": [],
        "steps": [ { "type": "goto", "url": "http://localhost:4100/profile" }, { "type": "read", "property": "text", "locator": { "role": "heading", "name": "Profile" } }, { "type": "expect", "op": "equals", "value": "John" } ] },
      "c-aaaaaaaaaaa3": { "interpretation": "Read the last order", "polarity": "positive", "unverified_assumptions": [],
        "steps": [ { "type": "goto", "url": "http://localhost:4100/orders" }, { "type": "read", "property": "text", "locator": { "testid": "last-order" } }, { "type": "expect", "op": "contains", "value": "ORD" } ] },
      "c-aaaaaaaaaaa4": { "interpretation": "Read the tier badge", "polarity": "positive",
        "unverified_assumptions": [{ "text": "The account is on the paid tier", "material": true }],
        "steps": [ { "type": "goto", "url": "http://localhost:4100/" }, { "type": "read", "property": "text", "locator": { "testid": "tier" } }, { "type": "expect", "op": "equals", "value": "Pro" } ] }
    }
  },
  "verdict": { "criteria": {
    "c-aaaaaaaaaaa1": { "verdict": "PASS", "evidence_class": "structured-read", "read_value": "jane.doe@example.test", "matched": true,
      "expected": { "op": "equals", "value": "https://shop.example.test/cart?id=9" }, "reason": null, "failed_step": null,
      "interpretation": "Open https://shop.example.test/cart?id=9 and read the total",
      "unverified_assumptions": [{ "text": "The cart already holds two items", "material": false }], "steps": [] },
    "c-aaaaaaaaaaa2": { "verdict": "FAIL", "evidence_class": "structured-read", "read_value": "Jane Doe", "matched": false,
      "expected": { "op": "equals", "value": "John" }, "reason": null, "failed_step": null, "interpretation": "Read the profile name", "unverified_assumptions": [], "steps": [] },
    "c-aaaaaaaaaaa3": { "verdict": "BLOCKED", "evidence_class": "structured-read", "read_value": null, "matched": null,
      "expected": { "op": "contains", "value": "ORD" }, "reason": "needs_auth", "failed_step": null, "interpretation": "Read the last order", "unverified_assumptions": [], "steps": [] },
    "c-aaaaaaaaaaa4": { "verdict": "NOT_VERIFIABLE", "evidence_class": "structured-read", "read_value": "Pro", "matched": true,
      "expected": { "op": "equals", "value": "Pro" }, "reason": "material_assumption", "failed_step": null, "interpretation": "Read the tier badge",
      "unverified_assumptions": [{ "text": "The account is on the paid tier", "material": true }], "steps": [] }
  } }
}
EOF
MAIN="$RUNS/20261101T000000Z-aaaaa1"
mkrun 20261101T000000Z-aaaaa1 "$TMP/spec-main.json"

echo "-- the comment config key (AC1)"
C="$TMP/cfg"; mkdir -p "$C" && git -C "$C" init -q
cfg_check() { printf '%s\n' "$1" > "$C/selvedge.json"; (cd "$C" && bash "$CLI" env check >/dev/null 2>"$TMP/stderr" </dev/null); rc=$?; err="$(cat "$TMP/stderr")"; }
cfg_check '{"schema_version":1,"origins":["http://localhost:3000"],"comment":{"read_values":true,"redact":["ORD-[0-9]+"]}}'
[ "$rc" -eq 0 ] && ok "AC1 \"comment\": {read_values: true, redact: [\"ORD-[0-9]+\"]} is accepted" || ko "AC1 valid comment: rc=$rc err='$err'"
for bad in '{"read_values":true,"publish":true}' '{"read_values":"yes"}' '{"redact":true}' '{"redact":["(unclosed"]}' '{"redact":[5]}' '[]'; do
  cfg_check "{\"schema_version\":1,\"origins\":[\"http://localhost:3000\"],\"comment\":$bad}"
  { [ "$rc" -eq 2 ] && grep -qF 'config_schema_violation' <<<"$err"; } \
    && ok "AC1 comment $bad is refused config_schema_violation (exit 2)" || ko "AC1 comment $bad: rc=$rc err='$err'"
done
out="$(cd "$C" && node --input-type=module -e '
import { pathToFileURL } from "node:url";
const E = await import(pathToFileURL(process.env.SELVEDGE_LIB + "/env-config.mjs").href);
const fs = await import("node:fs");
fs.writeFileSync("selvedge.json", JSON.stringify({ schema_version: 1, origins: ["http://localhost:3000"] }));
const d = E.loadConfig({ cwd: process.cwd() }).config.comment;
fs.writeFileSync("selvedge.json", JSON.stringify({ schema_version: 1, origins: ["http://localhost:3000"], comment: { redact: ["x+"] } }));
const p = E.loadConfig({ cwd: process.cwd() }).config.comment;
const ok = d.read_values === false && Array.isArray(d.redact) && d.redact.length === 0 && Object.isFrozen(d) && Object.isFrozen(d.redact)
  && p.read_values === false && JSON.stringify(p.redact) === "[\"x+\"]"
  && E.CONFIG_KEYS.includes("comment") && JSON.stringify(E.COMMENT_KEYS) === "[\"read_values\",\"redact\"]" && Object.isFrozen(E.COMMENT_KEYS);
console.log(ok ? "yes" : "no " + JSON.stringify({ d, p }));' 2>&1)"
[ "$out" = "yes" ] && ok "AC1 defaults: read_values false, redact [] (frozen) when absent; comment in CONFIG_KEYS; COMMENT_KEYS = read_values, redact" || ko "AC1 defaults: $out"
out="$(node -e '
const s = JSON.parse(require("fs").readFileSync(process.env.SELVEDGE_SCHEMA, "utf8")).properties.comment;
const ok = s && s.type === "object" && s.additionalProperties === false
  && JSON.stringify(Object.keys(s.properties).sort()) === "[\"read_values\",\"redact\"]"
  && s.properties.read_values.type === "boolean" && s.properties.read_values.default === false
  && s.properties.redact.type === "array" && s.properties.redact.items.type === "string";
console.log(ok ? "yes" : "no");' 2>&1)"
[ "$out" = "yes" ] && ok "AC1 the schema's comment object: read_values boolean, redact string array, additionalProperties false" || ko "AC1 schema comment: $out"

echo "-- one comment, found by its marker and updated in place (AC2)"
reset_gh
run -- comment "$MAIN" --pr 42 --yes
first_rc=$rc; first_out="$out"; first_body="$(marked_body)"
first_id="$(node -e 'const c = JSON.parse(require("fs").readFileSync(process.env.GH_COMMENTS, "utf8")).find((x) => x.body.includes("<!-- selvedge:verdict -->")); process.stdout.write(c ? String(c.id) : "")')"
{ [ "$first_rc" -eq 0 ] && [ -n "$first_id" ] && grep -qF "issuecomment-$first_id" <<<"$first_out"; } \
  && ok "AC2 the first run creates the marker comment and prints its URL (stdout), not the body" || ko "AC2 first run: rc=$first_rc out='$first_out' err='$err'"
grep -qF '<!-- selvedge:verdict -->' <<<"$first_out" && ko "AC2 the body was printed on stdout" || ok "AC2 stdout carries no body"
grep -qE '"pr","comment","42","--body-file"' "$GH_ARGV_LOG" && ok "AC2 created with gh pr comment <n> --body-file <file>" || ko "AC2 create argv: $(cat "$GH_ARGV_LOG")"
# Someone comments after the marker comment (so "the last comment" is no longer selvedge's).
node -e 'const f = process.env.GH_COMMENTS; const c = JSON.parse(require("fs").readFileSync(f, "utf8")); c.push({ id: 900, body: "a later note by the same account", user: { login: "me" } }); require("fs").writeFileSync(f, JSON.stringify(c, null, 2))'
# The verdict changes: the profile criterion now passes.
node -e 'const f = process.argv[1]; const v = JSON.parse(require("fs").readFileSync(f, "utf8")); Object.assign(v.criteria["c-aaaaaaaaaaa2"], { verdict: "PASS", matched: true }); require("fs").writeFileSync(f, JSON.stringify(v, null, 2) + "\n")' "$MAIN/verdict.json"
: > "$GH_ARGV_LOG"
run -- comment "$MAIN" --pr 42 --yes
second_body="$(marked_body)"
last_kept="$(ls "$GH_BODIES" | sort -n | tail -n 1)"
{ [ "$rc" -eq 0 ] && [ "$(marked_count)" = 1 ]; } && ok "AC2 after two runs the PR holds exactly ONE marker comment" || ko "AC2 marker comments: $(marked_count) rc=$rc err='$err'"
{ [ "$second_body" != "$first_body" ] && [ "$second_body" = "$(cat "$GH_BODIES/$last_kept")" ] && grep -qF '2 PASS' <<<"$second_body"; } \
  && ok "AC2 its body is the second run's body" || ko "AC2 second body: '$second_body'"
{ grep -qE "\"api\",\"-X\",\"PATCH\",\"repos/\\{owner\\}/\\{repo\\}/issues/comments/$first_id\"" "$GH_ARGV_LOG" && ! grep -qE '"pr","comment"' "$GH_ARGV_LOG"; } \
  && ok "AC2 the second run PATCHed comment $first_id and created none" || ko "AC2 second argv: $(cat "$GH_ARGV_LOG")"
out="$(node -e 'const c = JSON.parse(require("fs").readFileSync(process.env.GH_COMMENTS, "utf8")); const a = c.find((x) => x.id === 101); const b = c.find((x) => x.id === 900); process.stdout.write(a && b && a.body === process.argv[1] && b.body === "a later note by the same account" ? "yes" : "no")' "$UNMARKED_BODY")"
[ "$out" = yes ] && ok "AC2 the unmarked comments by the same account are unchanged byte for byte" || ko "AC2 unmarked comments changed: $(cat "$GH_COMMENTS")"
grep -qF 'selvedge:verdict' "$GH_ARGV_LOG" && ko "AC2 the body travelled in argv" || ok "AC2 no argv carries the body (it travels as a file)"
grep -qF '["api","user","--jq",".login"]' "$GH_ARGV_LOG" && ok "AC2 the author is checked against the signed-in login (gh api user --jq .login)" || ko "AC2 no login lookup: $(cat "$GH_ARGV_LOG")"
# Round trip: the stub's body equals renderComment's output for the same folder, byte for byte (the
# criterion text holds a single quote and a backslash; the body has newlines).
node --input-type=module -e '
import { pathToFileURL } from "node:url";
const C = await import(pathToFileURL(process.env.SELVEDGE_LIB + "/comment.mjs").href);
const R = await import(pathToFileURL(process.env.SELVEDGE_LIB + "/comment-render.mjs").href);
const run = C.readRunFolder(process.argv[1]);
process.stdout.write(R.renderComment({ ...run, history: C.criterionHistory(null, run), readValues: false, redact: [] }));' "$MAIN" > "$TMP/want-body" 2>&1
{ cmp -s "$TMP/want-body" "$GH_BODIES/$last_kept" && grep -qF "it's a\\b path" "$GH_BODIES/$last_kept"; } \
  && ok "round trip: the body gh received is renderComment's, byte for byte (single quote, backslash, newlines)" || ko "round trip differs: want='$(cat "$TMP/want-body")' got='$(cat "$GH_BODIES/$last_kept")'"

# A marker comment by ANOTHER account (the marker is public text) is never taken over: the run
# creates its own comment and leaves the other one byte for byte.
reset_gh
node -e 'const f = process.env.GH_COMMENTS; const c = JSON.parse(require("fs").readFileSync(f, "utf8")); c.push({ id: 500, body: "<!-- selvedge:verdict --> planted by someone else", user: { login: "mallory" } }); require("fs").writeFileSync(f, JSON.stringify(c, null, 2))'
run -- comment "$MAIN" --pr 42 --yes
out="$(node -e 'const c = JSON.parse(require("fs").readFileSync(process.env.GH_COMMENTS, "utf8")); const p = c.find((x) => x.id === 500); const mine = c.filter((x) => x.id !== 500 && x.user.login === "me" && x.body.includes("<!-- selvedge:verdict -->")); process.stdout.write(p && p.body === "<!-- selvedge:verdict --> planted by someone else" && mine.length === 1 ? "yes" : "no")')"
{ [ "$rc" -eq 0 ] && [ "$out" = yes ] && grep -qE '"pr","comment","42","--body-file"' "$GH_ARGV_LOG" && ! grep -qF '"PATCH"' "$GH_ARGV_LOG"; } \
  && ok "AC2 a marker comment by another login is not PATCHed: a new comment is created, the other left byte for byte" || ko "AC2 foreign marker: rc=$rc err='$err' argv=$(cat "$GH_ARGV_LOG") comments=$(cat "$GH_COMMENTS")"
# The signed-in login cannot be read: fail closed (exit 1), nothing posted.
reset_gh; export GH_LOGIN=FAIL
run -- comment "$MAIN" --pr 42 --yes
{ [ "$rc" -eq 1 ] && grep -qF 'gh api user failed' <<<"$err" && [ "$(posted)" = 0 ] && [ "$(marked_count)" = 0 ]; } \
  && ok "AC2 an unreadable gh login exits 1 and posts nothing (fails closed, never matches any author)" || ko "AC2 login failure: rc=$rc err='$err' argv=$(cat "$GH_ARGV_LOG")"
unset GH_LOGIN

echo "-- text only: no URL origin, header name, fill value, secret or evidence file (AC3)"
B="$first_body"
grep -qiE 'https?://' <<<"$B" && ko "AC3 the body holds an http(s):// URL" || ok "AC3 no http:// or https:// anywhere in the body"
{ ! grep -qF 'token=abc' <<<"$B" && ! grep -qF 'localhost:4100' <<<"$B" && grep -qF '`goto` /account' <<<"$B"; } \
  && ok "AC3 a goto shows its URL's path only (no origin, no query)" || ko "AC3 goto: $(grep -n goto <<<"$B")"
{ ! grep -qF 'shop.example.test' <<<"$B" && ! grep -qF 'id=9' <<<"$B" && grep -qF 'The cart at /cart shows the total' <<<"$B" \
  && grep -qF 'Open /cart and read the total' <<<"$B" && grep -qF 'equals "/cart"' <<<"$B"; } \
  && ok "AC3 a URL in criterion text, interpretation and expected value renders as its path (/cart)" || ko "AC3 free-text URL: $(grep -n -i 'cart' <<<"$B")"
grep -qiE 'cookie|authorization' <<<"$B" && ko "AC3 the body names Cookie / Set-Cookie / Authorization: $(grep -niE 'cookie|authorization' <<<"$B")" || ok "AC3 no Cookie, Set-Cookie or Authorization (any case)"
grep -qF "$APP_PASS" <<<"$B" && ko "AC3 the APP_PASS value is in the body" || ok "AC3 the {{APP_PASS}} value never appears"
{ ! grep -qF 'literal-fill-value-QQ' <<<"$B" && ! grep -qF 'select-value-ZZ' <<<"$B" && grep -qF '`fill` label "Nickname"' <<<"$B" && grep -qF '`select` label "Size"' <<<"$B"; } \
  && ok "AC3 fill / select steps show type + locator only, never the value" || ko "AC3 fill/select: $(grep -nE 'fill|select' <<<"$B")"
grep -qE '\.png|trace\.zip|evidence\.jsonl' <<<"$B" && ko "AC3 an evidence file name is in the body" || ok "AC3 no evidence file name (.png, trace.zip, evidence.jsonl)"
grep -qxF '**1 PASS · 1 FAIL · 1 BLOCKED · 1 NOT_VERIFIABLE**' <<<"$B" && ok "AC3 the summary line: 1 PASS · 1 FAIL · 1 BLOCKED · 1 NOT_VERIFIABLE" || ko "AC3 summary: $(sed -n 4p <<<"$B")"
grep -qxF '**2 PASS · 1 BLOCKED · 1 NOT_VERIFIABLE**' <<<"$second_body" && ok "AC3 zero counts are omitted (2 PASS · 1 BLOCKED · 1 NOT_VERIFIABLE)" || ko "AC3 zero counts: $(sed -n 4p <<<"$second_body")"
sha12="$(cut -c1-12 "$MAIN/plan.sha256")"
out="$(node -e '
const b = require("fs").readFileSync(0, "utf8"); const sha = process.argv[1];
const blocks = b.split("<details>").slice(1);
const need = ["- **Criterion:**", "- **Verdict:**", "- **Interpretation:**", "- **Unverified assumptions:**", "- **Steps:**", "- **Expected:**", "- **Matched:**", "- **Evidence class:** structured-read", "- **Plan:** `" + sha + "` · revision 1"];
const bad = blocks.filter((x) => !need.every((n) => x.includes(n)) || !x.includes("</details>"));
console.log(blocks.length === 4 && bad.length === 0 ? "yes" : "no " + blocks.length + " " + JSON.stringify(bad));' "$sha12" <<<"$B")"
[ "$out" = yes ] && ok "AC3 one <details> block per criterion, each with criterion, verdict, interpretation, assumptions, steps, expected, matched, evidence class, short sha + revision" || ko "AC3 blocks: $out"
{ grep -qF '**(material)** The account is on the paid tier' <<<"$B" && grep -qF '  - The cart already holds two items' <<<"$B"; } \
  && ok "AC3 assumptions listed, the material one marked" || ko "AC3 assumptions"
{ grep -qF -- '- **Matched:** yes' <<<"$B" && grep -qF -- '- **Matched:** no' <<<"$B" && grep -qF -- '- **Expected:** equals "John"' <<<"$B"; } \
  && ok "AC3 matched yes/no and the expected op + value" || ko "AC3 matched/expected"
{ grep -qF -- '- **Reason:** `needs_auth` — run `selvedge auth setup`' <<<"$B" && grep -qF -- '- **Reason:** `material_assumption` — ' <<<"$B"; } \
  && ok "AC3 BLOCKED / NOT_VERIFIABLE show the reason and its unblock hint" || ko "AC3 reasons: $(grep -n Reason <<<"$B")"

echo "-- read values unpublished by default (AC4)"
{ ! grep -qF 'jane.doe@example.test' <<<"$B" && ! grep -qF 'Jane Doe' <<<"$B" && grep -qF 'not published (`comment.read_values` is off)' <<<"$B"; } \
  && ok "AC4 neither the email nor the name a run read appears (default config)" || ko "AC4 read values leaked: $(grep -n 'Read value' <<<"$B")"

echo "-- the read_values opt-in: base ref only, private repos, redacted (AC5)"
cat > "$TMP/spec-values.json" <<EOF
{
  "criteria": [ { "id": "c-bbbbbbbbbbb1", "text": "The confirmation shows the order" } ],
  "plan": { "schema_version": 1, "target": "web", "criteria_sha256": "$SHA_A", "plan_revision": 1, "origins": ["http://localhost:4100"],
    "steps_by_criterion": { "c-bbbbbbbbbbb1": { "interpretation": "Read the confirmation", "polarity": "positive", "unverified_assumptions": [],
      "steps": [ { "type": "read", "property": "text", "locator": { "testid": "confirmation" } }, { "type": "expect", "op": "contains", "value": "Order" } ] } } },
  "verdict": { "criteria": { "c-bbbbbbbbbbb1": { "verdict": "PASS", "evidence_class": "structured-read",
    "read_value": "Jane Doe jane.doe@example.test Order 1234567 at /search?q=shoes key abcdefABCDEFghijklGHIJKLmnopqrMNOPQRstuv ref ORD-42 end",
    "matched": true, "expected": { "op": "contains", "value": "Order" }, "reason": null, "failed_step": null, "interpretation": "Read the confirmation", "unverified_assumptions": [], "steps": [] } } }
}
EOF
VALS="$RUNS/20261101T000000Z-bbbbb1"
mkrun 20261101T000000Z-bbbbb1 "$TMP/spec-values.json"
for vis in PUBLIC INTERNAL FAIL; do
  reset_gh; export GH_BASE=optin GH_VISIBILITY=$vis
  run -- comment "$VALS" --pr 42 --yes
  { [ "$rc" -eq 2 ] && grep -qF 'read_values_public_repo' <<<"$err" && [ "$(posted)" = 0 ]; } \
    && ok "AC5 read_values on + visibility $vis → exit 2 read_values_public_repo, no create, no PATCH" || ko "AC5 $vis: rc=$rc err='$err' argv=$(cat "$GH_ARGV_LOG")"
done
grep -qF '"pr","view","42","--json","baseRefName"' "$GH_ARGV_LOG" && ok "AC5 the base ref comes from gh pr view <n> --json baseRefName" || ko "AC5 base lookup argv: $(cat "$GH_ARGV_LOG")"
check_redacted() {
  local b="$1"
  { ! grep -qF 'jane.doe@example.test' <<<"$b" && grep -qF 'Jane Doe [redacted] Order' <<<"$b"; } && ok "AC5 $2: an email is redacted (the name, matched by no pattern, shows)" || ko "AC5 $2 email: $(grep -n 'Read value' <<<"$b")"
  { ! grep -qF '1234567' <<<"$b" && grep -qF 'Order [redacted] at' <<<"$b"; } && ok "AC5 $2: a run of 6+ digits is redacted" || ko "AC5 $2 digits: $(grep -n 'Read value' <<<"$b")"
  { ! grep -qF 'q=shoes' <<<"$b" && grep -qF 'at /search[redacted] key' <<<"$b"; } && ok "AC5 $2: a URL query string is redacted" || ko "AC5 $2 query: $(grep -n 'Read value' <<<"$b")"
  { ! grep -qF 'abcdefABCDEFghijklGHIJKLmnopqrMNOPQRstuv' <<<"$b" && grep -qF 'key [redacted] ref' <<<"$b"; } && ok "AC5 $2: a 32+ character token is redacted" || ko "AC5 $2 token: $(grep -n 'Read value' <<<"$b")"
  { ! grep -qF 'ORD-42' <<<"$b" && grep -qF 'ref [redacted] end' <<<"$b"; } && ok "AC5 $2: the configured redact pattern ORD-[0-9]+ applies on top of the defaults" || ko "AC5 $2 configured: $(grep -n 'Read value' <<<"$b")"
}
reset_gh; export GH_BASE=optin GH_VISIBILITY=PRIVATE
run -- comment "$VALS" --pr 42 --yes
{ [ "$rc" -eq 0 ] && [ "$(marked_count)" = 1 ]; } && ok "AC5 a PRIVATE repo posts with read values" || ko "AC5 PRIVATE: rc=$rc err='$err'"
check_redacted "$(marked_body)" PRIVATE
reset_gh; export GH_BASE=optin GH_VISIBILITY=PUBLIC
run -- comment "$VALS" --pr 42 --yes --allow-public-values
{ [ "$rc" -eq 0 ] && [ "$(marked_count)" = 1 ]; } && ok "AC5 --allow-public-values posts on a PUBLIC repo" || ko "AC5 --allow-public-values: rc=$rc err='$err'"
check_redacted "$(marked_body)" "--allow-public-values"
# The opt-in only in the working tree: the base ref (plain) has none, so values stay unpublished.
printf '%s\n' '{"schema_version":1,"origins":["http://localhost:4100"],"comment":{"read_values":true}}' > "$R/selvedge.json"
reset_gh; export GH_BASE=plain GH_VISIBILITY=PRIVATE
run -- comment "$VALS" --pr 42 --yes
b="$(marked_body)"
{ [ "$rc" -eq 0 ] && ! grep -qF 'Jane Doe' <<<"$b" && grep -qF 'not published' <<<"$b"; } \
  && ok "AC5 an opt-in only in the working tree's selvedge.json publishes nothing (read from the base ref only)" || ko "AC5 working-tree opt-in: rc=$rc err='$err' body=$(grep -n 'Read value' <<<"$b")"
rm -f "$R/selvedge.json"
reset_gh
run -- comment "$VALS" --pr 42 --yes --base origin/optin --allow-public-values
{ [ "$rc" -eq 0 ] && grep -qF 'Jane Doe [redacted]' <<<"$(marked_body)" && ! grep -qF '"pr","view"' "$GH_ARGV_LOG"; } \
  && ok "AC5 --base <ref> names the config ref (no gh pr view)" || ko "AC5 --base: rc=$rc err='$err'"
reset_gh; export GH_VISIBILITY=PRIVATE
run -- comment "$VALS" --pr 42 --yes --base origin/no-such-ref
b="$(marked_body)"
{ [ "$rc" -eq 0 ] && ! grep -qF 'Jane Doe' <<<"$b" && grep -qF 'not published' <<<"$b" && grep -qF 'using the defaults' <<<"$err" && ! grep -qF '"repo","view"' "$GH_ARGV_LOG"; } \
  && ok "AC5 a base ref with no readable selvedge.json keeps the defaults: posts, values unpublished, no visibility lookup" || ko "AC5 unreadable base: rc=$rc err='$err'"

echo "-- per-criterion revision history (AC6)"
SHA_6=6666666666666666666666666666666666666666666666666666666666666666
SHA_7=7777777777777777777777777777777777777777777777777777777777777777
SHA_8=8888888888888888888888888888888888888888888888888888888888888888
# rev_spec <criteria sha> <revision> <prior_revisions json> <A verdict> <B verdict> [<C verdict>]
rev_spec() {
  node -e '
const [sha, rev, prior, ...vs] = process.argv.slice(1);
const ids = ["c-ccccccccccc1", "c-ccccccccccc2", "c-ccccccccccc3"].slice(0, vs.length);
const entry = (v) => ({ verdict: v, evidence_class: "structured-read", read_value: "x", matched: v === "PASS", expected: { op: "equals", value: "x" }, reason: null, failed_step: null, interpretation: "i", unverified_assumptions: [], steps: [] });
process.stdout.write(JSON.stringify({
  criteria: ids.map((id, i) => ({ id, text: "Criterion " + "ABC"[i] })),
  plan: { schema_version: 1, target: "web", criteria_sha256: sha, plan_revision: Number(rev), origins: ["http://localhost:4100"],
    steps_by_criterion: Object.fromEntries(ids.map((id) => [id, { interpretation: "i", polarity: "positive", unverified_assumptions: [], steps: [] }])) },
  verdict: { plan_revision: Number(rev), prior_revisions: JSON.parse(prior), criteria: Object.fromEntries(ids.map((id, i) => [id, entry(vs[i])])) },
}));' "$@"
}
run_line() { printf '{"event":"run","run_id":"%s","criteria_sha256":"%s","plan_revision":%s,"replay_of":null,"verdict":"%s"}\n' "$1" "$2" "$3" "$4" >> "$R/.selvedge/runs.jsonl"; }
# Plan 1 of SHA_6 ran: A FAIL, B PASS, C absent from its verdict.json. Plan 2: all PASS.
rev_spec "$SHA_6" 1 '[]' FAIL PASS > "$TMP/s6-1.json"; mkrun 20261102T000000Z-666661 "$TMP/s6-1.json"
run_line 20261102T000000Z-666661 "$SHA_6" 1 FAIL
# A replay of plan 1 with the opposite verdicts must be ignored (replay_of not null).
printf '{"event":"run","run_id":"20261102T000000Z-666663","criteria_sha256":"%s","plan_revision":1,"replay_of":"20261102T000000Z-666661","verdict":"PASS"}\n' "$SHA_6" >> "$R/.selvedge/runs.jsonl"
rev_spec "$SHA_6" 2 '[{"revision":1,"verdict":"FAIL"}]' PASS PASS PASS > "$TMP/s6-2.json"; mkrun 20261102T000000Z-666662 "$TMP/s6-2.json"
reset_gh
run -- comment "$RUNS/20261102T000000Z-666662" --pr 42 --yes
b="$(marked_body)"
{ [ "$rc" -eq 0 ] && [ "$(grep -cF -- '- **Verdict:** FAIL on plan 1 → PASS on plan 2' <<<"$b")" = 1 ]; } \
  && ok "AC6 A (FAIL on plan 1) reads exactly 'FAIL on plan 1 → PASS on plan 2'" || ko "AC6 A: rc=$rc err='$err' $(grep -n 'Verdict' <<<"$b")"
grep -qF -- '- **Verdict:** PASS on plan 1 → PASS on plan 2' <<<"$b" && ok "AC6 B (its own PASS on plan 1) reads 'PASS on plan 1 → PASS on plan 2', not the run's FAIL" || ko "AC6 B: $(grep -n 'Verdict' <<<"$b")"
grep -qxF -- '- **Verdict:** PASS' <<<"$b" && ko "AC6 a bare PASS while prior_revisions is non-empty" || ok "AC6 no bare PASS cell while prior_revisions is non-empty"
grep -qF -- '- **Verdict:** FAIL on plan 1 (whole run) → PASS on plan 2' <<<"$b" && ok "AC6 C (no entry in plan 1's verdict.json) shows the run-level verdict labelled (whole run)" || ko "AC6 C: $(grep -n 'Verdict' <<<"$b")"
grep -qxF '**2 PASS · 1 PASS after revision**' <<<"$b" && ok "AC6 summary: A under '1 PASS after revision', B and C (whole-run fallback) in the plain PASS count" || ko "AC6 summary: $(sed -n 4p <<<"$b")"
# Plan 1 of SHA_7 has a run line but its folder is gone.
run_line 20261103T000000Z-777771 "$SHA_7" 1 FAIL
rev_spec "$SHA_7" 2 '[{"revision":1,"verdict":"FAIL"}]' PASS > "$TMP/s7.json"; mkrun 20261103T000000Z-777772 "$TMP/s7.json"
reset_gh
run -- comment "$RUNS/20261103T000000Z-777772" --pr 42 --yes
b="$(marked_body)"
{ grep -qF -- '- **Verdict:** FAIL on plan 1 (whole run) → PASS on plan 2' <<<"$b" && grep -qxF '**1 PASS**' <<<"$b"; } \
  && ok "AC6 a missing earlier run folder: 'FAIL on plan 1 (whole run) → PASS on plan 2', counted in the plain PASS count" || ko "AC6 missing folder: rc=$rc $(grep -n 'Verdict' <<<"$b") $(sed -n 4p <<<"$b")"
# Plan 1 of SHA_8 never ran.
rev_spec "$SHA_8" 2 '[{"revision":1,"verdict":null}]' PASS > "$TMP/s8.json"; mkrun 20261104T000000Z-888882 "$TMP/s8.json"
reset_gh
run -- comment "$RUNS/20261104T000000Z-888882" --pr 42 --yes
b="$(marked_body)"
{ grep -qF -- '- **Verdict:** not run on plan 1 → PASS on plan 2' <<<"$b" && grep -qxF '**1 PASS**' <<<"$b"; } \
  && ok "AC6 a revision that never ran reads 'not run on plan 1'" || ko "AC6 not run: rc=$rc $(grep -n 'Verdict' <<<"$b")"

echo "-- confirmation, run-folder refusals, gh failure (AC7)"
reset_gh
run -- comment "$MAIN" --pr 42
{ [ "$rc" -eq 2 ] && grep -qF 'comment_requires_yes' <<<"$err" && [ "$(posted)" = 0 ]; } \
  && ok "AC7 no --yes and stdin not a terminal: exit 2 comment_requires_yes, nothing posted" || ko "AC7 no --yes: rc=$rc err='$err'"
confirm() {
  (cd "$R" && node --input-type=module -e '
import { pathToFileURL } from "node:url";
const C = await import(pathToFileURL(process.env.SELVEDGE_LIB + "/comment.mjs").href);
const code = await C.runComment([process.argv[1], "--pr", "42"], { interactive: true, readLine: async () => process.argv[2] });
console.log("code=" + code);' "$MAIN" "$1" 2>/dev/null | grep '^code=')
}
reset_gh
out="$(confirm n)"
{ [ "$out" = "code=0" ] && [ "$(posted)" = 0 ] && [ "$(marked_count)" = 0 ]; } && ok "AC7 a confirmation answered 'n' posts nothing and exits 0" || ko "AC7 declined: out='$out' argv=$(cat "$GH_ARGV_LOG")"
reset_gh
out="$(confirm yes)"
{ [ "$out" = "code=0" ] && [ "$(posted)" = 0 ]; } && ok "AC7 anything but 'y' ('yes') posts nothing" || ko "AC7 'yes': out='$out'"
reset_gh
out="$(confirm y)"
{ [ "$out" = "code=0" ] && [ "$(marked_count)" = 1 ]; } && ok "AC7 a confirmation answered 'y' posts" || ko "AC7 'y': out='$out' argv=$(cat "$GH_ARGV_LOG")"
cp -R "$MAIN" "$TMP/no-verdict" && rm "$TMP/no-verdict/verdict.json"
reset_gh
run -- comment "$TMP/no-verdict" --pr 42 --yes
{ [ "$rc" -eq 2 ] && grep -qF 'verdict_missing' <<<"$err" && [ "$(posted)" = 0 ]; } \
  && ok "AC7 no verdict.json: exit 2 verdict_missing, nothing posted" || ko "AC7 verdict_missing: rc=$rc err='$err'"
cp -R "$MAIN" "$TMP/modified" && printf ' ' >> "$TMP/modified/plan.json"
reset_gh
run -- comment "$TMP/modified" --pr 42 --yes
{ [ "$rc" -eq 2 ] && grep -qF 'plan_modified' <<<"$err" && [ "$(posted)" = 0 ]; } \
  && ok "AC7 plan.json sha256 not verdict.json's plan_sha256: exit 2 plan_modified, nothing posted" || ko "AC7 plan_modified: rc=$rc err='$err'"
reset_gh
run -- comment "$MAIN" --pr 99 --yes --base origin/plain
[ "$rc" -eq 1 ] && ok "AC7 a failing gh exits 1" || ko "AC7 gh failure: rc=$rc err='$err'"
run -- comment "$MAIN" --pr 99 --yes
[ "$rc" -eq 1 ] && ok "a failing gh pr view (base lookup) exits 1" || ko "gh pr view failure: rc=$rc err='$err'"
run -- comment "$MAIN" --pr abc --yes
[ "$rc" -eq 2 ] && ok "a non-numeric --pr is a usage error (exit 2)" || ko "--pr abc: rc=$rc"
run -- comment --pr 42 --yes
[ "$rc" -eq 2 ] && ok "no <run-dir> is a usage error (exit 2)" || ko "no run-dir: rc=$rc"

echo "-- the planner's note for a not_planned criterion"
out="$(node --input-type=module -e '
import { pathToFileURL } from "node:url";
const R = await import(pathToFileURL(process.env.SELVEDGE_LIB + "/comment-render.mjs").href);
const nv = (reason) => ({ verdict: "NOT_VERIFIABLE", evidence_class: "structured-read", read_value: null, matched: null, expected: null, reason, failed_step: null, interpretation: null, unverified_assumptions: [], steps: [] });
const verdict = { plan_sha256: "a".repeat(64), plan_revision: 1, criteria: { "c-000000000001": nv("side_effect_not_observable"), "c-000000000002": nv("criterion_not_testable"), "c-000000000003": nv("exploration_budget") } };
const plan = { steps_by_criterion: {}, not_planned: [
  { id: "c-000000000001", reason: "side_effect_not_observable", detail: "looked at https://shop.test/orders and /outbox; the send is an email, secret-QQ" },
  { id: "c-000000000002", reason: "criterion_not_testable", rewrite: "The page shows the heading \"Welcome\"" },
  { id: "c-000000000003", reason: "exploration_budget", detail: "  " } ] };
const b = R.renderComment({ verdict, plan, redact: ["secret-QQ"] });
const blocks = b.split("<details>").slice(1);
const ok = blocks[0].includes("- **Planner note:** looked at /orders and /outbox; the send is an email, [redacted]")
  && !b.includes("secret-QQ") && !b.includes("https://")
  && blocks[1].includes("- **Suggested rewrite:** The page shows the heading \"Welcome\"")
  && !blocks[1].includes("Planner note") && !blocks[2].includes("Planner note") && !blocks[2].includes("Suggested rewrite");
process.stdout.write(ok ? "yes" : "no\n" + b);')"
[ "$out" = yes ] && ok "a not_planned criterion shows the planner's detail (URL as path, redacted) and rewrite under its reason; a blank detail adds nothing" || ko "planner note: $out"

echo "-- no reason is a string literal in the comment modules"
lit="$(grep -nE "'(read_values_public_repo|comment_requires_yes|verdict_missing|plan_modified|not_frozen|base_config_unreadable)'" "$PLUGIN_DIR/lib/comment.mjs" "$PLUGIN_DIR/lib/comment-render.mjs" || true)"
[ -z "$lit" ] && ok "comment.mjs / comment-render.mjs name reasons through REASONS only" || ko "reason literals: $lit"

echo "test-comment: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
