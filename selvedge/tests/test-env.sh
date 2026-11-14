#!/usr/bin/env bash
# test-env.sh — pins `selvedge env check|init|approve|hook` and the modules behind them
# (selvedge/lib/env-config.mjs, env-approvals.mjs, env.mjs, schemas/selvedge-config.schema.json):
# the exact-origin allowlist and its reasons, the --base read from git, user-scoped sha256 hook
# approvals, the TTY-only approve (driven through a real pseudo-terminal), env init, and the schema /
# validator key-set equality, and the README reasons table kept in sync with REASONS. Every arm turns
# red under its row of the brief's pin-mutation table.
#
# Hermetic: a fresh temp HOME (the user's ~/.claude/selvedge/approvals.json is never touched), temp
# git repos, no network. Needs node (>= 18), git and python3 (for the pty arms); a missing node is a
# FAIL, never a skip.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$TESTS_DIR/.." && pwd)"
CLI="$PLUGIN_DIR/bin/selvedge"
export SELVEDGE_LIB="$PLUGIN_DIR/lib"
export SELVEDGE_SCHEMA="$PLUGIN_DIR/schemas/selvedge-config.schema.json"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "  ok   $1"; }
ko() { fail=$((fail + 1)); echo "  FAIL $1"; }

for tool in node git python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "  FAIL $tool is not on PATH (test-env.sh needs it)"; echo "test-env: 0 passed, 1 failed"; exit 1; }
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/selvedge-env.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_CONFIG_NOSYSTEM=1
APPROVALS="$HOME/.claude/selvedge/approvals.json"

# A pseudo-terminal driver: pty.spawn feeds our stdin to the child's terminal. The master_read raises
# at EOF because Python 3.9's pty._copy otherwise loops forever on macOS once the child exits (Linux
# raises EIO itself). Exit status is the child's.
PTY_PY='import os, pty, sys
def rd(fd):
    d = os.read(fd, 1024)
    if not d:
        raise OSError("eof")
    return d
s = pty.spawn(sys.argv[1:], rd)
sys.exit((s >> 8) & 255)'

# run <dir> <cli args…> — sets $rc, $out (stdout), $err (stderr); stdin is /dev/null (no TTY).
run() {
  local dir="$1"; shift
  out="$(cd "$dir" && bash "$CLI" "$@" 2>"$TMP/stderr" </dev/null)"; rc=$?
  err="$(cat "$TMP/stderr")"
}

# mkrepo <dir> — an empty git repo on branch main.
mkrepo() {
  mkdir -p "$1" && git -C "$1" init -q && git -C "$1" symbolic-ref HEAD refs/heads/main
}

# node_eval <js> — runs an ES module with E (env-config) and A (env-approvals) imported.
node_eval() {
  node --input-type=module -e "
import { pathToFileURL } from 'node:url';
const E = await import(pathToFileURL(process.env.SELVEDGE_LIB + '/env-config.mjs').href);
const A = await import(pathToFileURL(process.env.SELVEDGE_LIB + '/env-approvals.mjs').href);
$1"
}

# sha256 hex of a literal string — independent of env-approvals.mjs's canonicalization.
sha_of() { node -e 'process.stdout.write(require("crypto").createHash("sha256").update(process.argv[1]).digest("hex"))' "$1"; }

# write_approval <identity> <sha> — a hand-written approvals.json (the user's own file).
write_approval() {
  mkdir -p "$(dirname "$APPROVALS")"
  node -e 'const [f,i,s]=process.argv.slice(1); require("fs").writeFileSync(f, JSON.stringify({schema_version:1,approvals:{[i]:{hooks_sha256:s}}}))' "$APPROVALS" "$1" "$2"
}

file_mode() { node -e 'process.stdout.write((require("fs").statSync(process.argv[1]).mode & 0o777).toString(8))' "$1"; }

echo "-- CLI dispatch"
out="$(bash "$CLI" 2>&1)"
grep -qE '^ +env <check\|init\|approve\|hook>' <<<"$out" && ok "help lists the env commands" || ko "help has no env line: '$out'"
nonode="$TMP/nonode-bin"; mkdir -p "$nonode"
for c in dirname basename readlink grep head sed cat; do
  p="$(command -v "$c")" && ln -s "$p" "$nonode/$c"
done
out="$(PATH="$nonode" "$BASH" "$CLI" env check 2>&1)"; rc=$?
{ [ "$rc" -eq 1 ] && grep -qF 'need Node.js >= 18' <<<"$out"; } && ok "env with no node on PATH exits 1 naming the need" || ko "env without node: rc=$rc out='$out'"
out="$(PATH="$nonode" "$BASH" "$CLI" --version 2>&1)"; rc=$?
{ [ "$rc" -eq 0 ] && grep -qE '^selvedge [0-9]' <<<"$out"; } && ok "--version still runs with no node on PATH" || ko "--version without node: rc=$rc out='$out'"
run "$TMP" env no-such; [ "$rc" -eq 2 ] && ok "unknown env command exits 2" || ko "unknown env command: rc=$rc"

echo "-- REASONS (the closed list)"
out="$(node_eval '
const want = ["host_not_allowed","remote_resolves_private","remote_mutation_refused","proxy_loopback_disabled","proxy_unavailable","env_hooks_unapproved","env_hooks_remote_origin","origins_empty","origin_invalid","remote_origin_without_allow_remote","config_absent","config_invalid_json","config_schema_violation","base_config_unreadable","approve_requires_tty","port_required"];
const keys = Object.keys(E.REASONS).sort();
const okSet = JSON.stringify(keys) === JSON.stringify([...want].sort());
const okVals = keys.every((k) => E.REASONS[k] === k);
console.log(Object.isFrozen(E.REASONS) && okSet && okVals ? "yes" : "no " + JSON.stringify(keys));' 2>&1)"
[ "$out" = "yes" ] && ok "REASONS is frozen and holds exactly the 16 named reasons (value == key)" || ko "REASONS: $out"
# README sync: the README's reasons table (rows `| \`<reason>\` | …`) and REASONS hold the same keys,
# so a reason added to the code without a documented row (or a stale row) turns this red.
export SELVEDGE_README="$PLUGIN_DIR/README.md"
out="$(node_eval '
const md = (await import("node:fs")).readFileSync(process.env.SELVEDGE_README, "utf8");
const rows = [...md.matchAll(/^\| `([a-z_]+)` \|/gm)].map((m) => m[1]);
const keys = Object.keys(E.REASONS);
const missing = keys.filter((k) => !rows.includes(k));
const extra = rows.filter((r) => !keys.includes(r));
const dupes = rows.filter((r, i) => rows.indexOf(r) !== i);
console.log(missing.length || extra.length || dupes.length ? JSON.stringify({ missing, extra, dupes }) : "yes");' 2>&1)"
[ "$out" = "yes" ] && ok "README sync: every REASONS key has exactly one row in README's reasons table, and no row is unknown" || ko "README reasons table out of sync: $out"

echo "-- origin parsing and the allowlist match (AC2, AC14)"
out="$(node_eval '
const cfg = { origins: ["http://localhost:4001"] };
const r = [
  E.isOriginAllowed(cfg, "http://localhost:4001"),
  E.isOriginAllowed(cfg, "http://localhost:4001/some/path?q=1"),
  E.isOriginAllowed(cfg, "http://localhost:4002"),
  E.isOriginAllowed(cfg, "https://localhost:4001"),
  E.isOriginAllowed(cfg, "http://127.0.0.1:4001"),
  E.isOriginAllowed({ origins: ["http://localhost:80"] }, "http://localhost"),
  E.isOriginAllowed({ origins: ["http://localhost"] }, "http://localhost:80"),
  E.isOriginAllowed({ origins: ["http://localhost:3000"] }, "https://shop.example.com/?next=localhost"),
  E.isOriginAllowed({ origins: ["http://localhost:3000"] }, "http://localhost:3000.evil.example"),
];
console.log(JSON.stringify(r));')"
[ "$out" = '[true,true,false,false,false,false,true,false,false]' ] \
  && ok "isOriginAllowed matches scheme, host AND port exactly (localhost:4001 listed, localhost:4002 refused)" || ko "isOriginAllowed: $out"
out="$(node_eval '
const p = (s) => { const o = E.parseOrigin(s); return o ? o.origin + "|" + o.port : null; };
console.log(JSON.stringify([p("http://localhost:3000"), p("https://example.com"), p("http://[::1]:8080"),
  p("http://localhost:3000/"), p("http://localhost:3000/app"), p("http://localhost:3000?x=1"), p("http://u:p@localhost:3000"),
  p("ftp://localhost:21"), p("localhost:3000"), p("http://LOCALHOST:3000"), p("http://localhost:80"), p(""), p(42),
  E.isLocalOrigin("http://127.0.0.1:1"), E.isLocalOrigin("http://[::1]:1"), E.isLocalOrigin("http://localhost.example.com:1")]));')"
[ "$out" = '["http://localhost:3000|3000","https://example.com|443","http://[::1]:8080|8080",null,null,null,null,null,null,null,null,null,null,true,true,false]' ] \
  && ok "parseOrigin accepts only exact scheme://host[:port]; isLocalOrigin is localhost/127.0.0.1/[::1]" || ko "parseOrigin/isLocalOrigin: $out"

echo "-- env check: origins (AC1, AC2)"
R="$TMP/r-origins"; mkrepo "$R"
printf '{"schema_version":1,"origins":["http://localhost:3000","https://shop.example.com"]}' > "$R/selvedge.json"
run "$R" env check
{ [ "$rc" -eq 2 ] && grep -qF 'remote_origin_without_allow_remote' <<<"$err" && grep -qF 'https://shop.example.com' <<<"$err"; } \
  && ok "AC1 a non-local origin without allow_remote exits 2 naming the reason and the origin" || ko "AC1: rc=$rc err='$err'"
printf '{"schema_version":1,"origins":["http://localhost:3000","https://shop.example.com"],"allow_remote":true}' > "$R/selvedge.json"
run "$R" env check
[ "$rc" -eq 0 ] && grep -qF 'https://shop.example.com (remote)' <<<"$out" && ok "AC1 the same origin with allow_remote: true passes" || ko "AC1 allow_remote: rc=$rc out='$out' err='$err'"
for cfg in '{"schema_version":1}' '{"schema_version":1,"origins":[]}'; do
  printf '%s' "$cfg" > "$R/selvedge.json"; run "$R" env check
  { [ "$rc" -eq 2 ] && grep -qF 'origins_empty' <<<"$err" && grep -qF 'http://localhost:' <<<"$err"; } \
    && ok "AC2 $cfg exits 2 origins_empty with an example http://localhost:<port> line" || ko "AC2 origins_empty $cfg: rc=$rc err='$err'"
done
for bad in 'http://localhost:3000/' 'http://localhost:3000/app' 'http://localhost:3000?next=x' 'http://u:p@localhost:3000' \
           'ftp://localhost:2121' 'localhost:3000' 'http://LOCALHOST:3000' 'http://localhost:3000#x'; do
  printf '{"schema_version":1,"origins":["%s"]}' "$bad" > "$R/selvedge.json"; run "$R" env check
  { [ "$rc" -eq 2 ] && grep -qF 'origin_invalid' <<<"$err" && grep -qF "$bad" <<<"$err"; } \
    && ok "AC2 '$bad' exits 2 origin_invalid naming it" || ko "AC2 origin_invalid '$bad': rc=$rc err='$err'"
done
for good in 'http://localhost:3000' 'http://127.0.0.1:8080' 'http://[::1]:5173'; do
  printf '{"schema_version":1,"origins":["%s"]}' "$good" > "$R/selvedge.json"; run "$R" env check
  [ "$rc" -eq 0 ] && ok "AC2 '$good' is a valid local origin" || ko "AC2 valid '$good': rc=$rc err='$err'"
done
rm -f "$R/selvedge.json"; run "$R" env check
{ [ "$rc" -eq 2 ] && grep -qF 'config_absent' <<<"$err"; } && ok "no selvedge.json exits 2 config_absent" || ko "config_absent: rc=$rc err='$err'"
printf '{"schema_version":1,' > "$R/selvedge.json"; run "$R" env check
{ [ "$rc" -eq 2 ] && grep -qF 'config_invalid_json' <<<"$err"; } && ok "malformed JSON exits 2 config_invalid_json" || ko "config_invalid_json: rc=$rc err='$err'"

echo "-- env check: schema (AC10)"
for cfg in '{"schema_version":1,"origins":["http://localhost:3000"],"allowed_hosts":["x"]}' \
           '{"schema_version":1,"origins":["http://localhost:3000"],"hooks":{"seed":"true","teardown":"true"}}' \
           '{"schema_version":2,"origins":["http://localhost:3000"]}' \
           '{"origins":["http://localhost:3000"]}' \
           '{"schema_version":1,"origins":["http://localhost:3000"],"allow_remote":"yes"}' \
           '{"schema_version":1,"origins":"http://localhost:3000"}' \
           '{"schema_version":1,"origins":["http://localhost:3000"],"hooks":{"seed":1}}' \
           '[1]'; do
  printf '%s' "$cfg" > "$R/selvedge.json"; run "$R" env check
  { [ "$rc" -eq 2 ] && grep -qF 'config_schema_violation' <<<"$err"; } \
    && ok "AC10 $cfg exits 2 config_schema_violation" || ko "AC10 $cfg: rc=$rc err='$err'"
done
printf '{"schema_version":1,"origins":["http://localhost:3000"],"hooks":{"seed":"a","reset":"b","auth_setup":"c"}}' > "$R/selvedge.json"
run "$R" env check
[ "$rc" -eq 0 ] && ok "AC10 all three hook keys (seed, reset, auth_setup) are accepted" || ko "AC10 hook keys: rc=$rc err='$err'"
out="$(node_eval '
const s = JSON.parse((await import("node:fs")).readFileSync(process.env.SELVEDGE_SCHEMA, "utf8"));
const eq = (a, b) => JSON.stringify([...a].sort()) === JSON.stringify([...b].sort());
const checks = [
  s["$schema"] === "https://json-schema.org/draft/2020-12/schema",
  s.additionalProperties === false,
  eq(Object.keys(s.properties), E.CONFIG_KEYS),
  s.properties.schema_version.const === 1,
  s.properties.origins.type === "array" && s.properties.origins.items.type === "string",
  s.properties.allow_remote.type === "boolean" && s.properties.allow_remote_mutation.type === "boolean",
  s.properties.hooks.additionalProperties === false,
  eq(Object.keys(s.properties.hooks.properties), E.HOOK_KEYS),
  Object.values(s.properties.hooks.properties).every((p) => p.type === "string"),
];
console.log(JSON.stringify(checks));')"
[ "$out" = '[true,true,true,true,true,true,true,true,true]' ] \
  && ok "AC10 the schema (draft 2020-12) property names equal the validator's key sets, top level and hooks" || ko "AC10 schema/validator equality: $out"

echo "-- env check --base reads the committed config (AC3)"
B="$TMP/r-base"; mkrepo "$B"
printf '{"schema_version":1,"origins":["http://localhost:3000"],"hooks":{"seed":"echo main-seed"}}' > "$B/selvedge.json"
git -C "$B" add selvedge.json && git -C "$B" commit -q -m base
git -C "$B" checkout -q -b pr
printf '{"schema_version":1,"origins":["http://localhost:3000","https://evil.example.com"],"allow_remote":true,"hooks":{"seed":"echo pr-seed"}}' > "$B/selvedge.json"
run "$B" env check --base main
{ [ "$rc" -eq 0 ] && grep -qF 'config source: main (git show main:selvedge.json)' <<<"$out" && grep -qF 'echo main-seed' <<<"$out" \
  && ! grep -qF 'evil.example.com' <<<"$out" && ! grep -qF 'pr-seed' <<<"$out"; } \
  && ok "AC3 --base main reports main's content and ignores the working-tree edit" || ko "AC3 --base: rc=$rc out='$out' err='$err'"
mkdir -p "$B/sub"; run "$B/sub" env check --base main
{ [ "$rc" -eq 0 ] && grep -qF 'echo main-seed' <<<"$out"; } && ok "AC3 --base resolves selvedge.json from the repo root when run in a subdirectory" || ko "AC3 --base from sub: rc=$rc err='$err'"
run "$B" env check
{ [ "$rc" -eq 0 ] && grep -qxF 'config source: working tree (no --base)' <<<"$out" && grep -qF 'evil.example.com' <<<"$out"; } \
  && ok "AC3 without --base it reads the working tree and says 'config source: working tree (no --base)'" || ko "AC3 no --base: rc=$rc out='$out'"
run "$B" env check --base no-such-ref
{ [ "$rc" -eq 2 ] && grep -qF 'base_config_unreadable' <<<"$err"; } && ok "AC3 an unknown ref exits 2 base_config_unreadable" || ko "AC3 unknown ref: rc=$rc out='$out' err='$err'"
git -C "$B" checkout -q main && git -C "$B" checkout -q -b nocfg && git -C "$B" rm -qf selvedge.json && git -C "$B" commit -q -m drop
git -C "$B" checkout -q pr
printf '{"schema_version":1,"origins":["http://localhost:3000"]}' > "$B/selvedge.json"
run "$B" env check --base nocfg
{ [ "$rc" -eq 2 ] && grep -qF 'base_config_unreadable' <<<"$err"; } \
  && ok "AC3 a ref with no selvedge.json exits 2 base_config_unreadable (no working-tree fallback)" || ko "AC3 missing at ref: rc=$rc out='$out' err='$err'"
run "$B" env check --base --output=x
{ [ "$rc" -eq 2 ] && grep -qF 'base_config_unreadable' <<<"$err" && [ ! -e "$B/x:selvedge.json" ]; } \
  && ok "AC3 a ref that looks like an option is refused" || ko "AC3 option-like ref: rc=$rc err='$err'"

echo "-- env hook: approvals (AC4, AC5, AC6)"
H="$TMP/r-hooks"; mkrepo "$H"
H_REAL="$(cd "$H" && pwd -P)"
hooks_json='{"seed":"touch marker-seed","reset":"true"}'
printf '{"schema_version":1,"origins":["http://localhost:3000"],"hooks":%s}' "$hooks_json" > "$H/selvedge.json"
canon='{"reset":"true","seed":"touch marker-seed"}'   # sorted keys, no whitespace
canon_sha="$(sha_of "$canon")"
out="$(node_eval 'console.log(A.hooksSha256({ seed: "touch marker-seed", reset: "true" }));')"
[ "$out" = "$canon_sha" ] && ok "AC5 hooksSha256 is sha256 of the canonical hooks JSON (sorted keys, no whitespace)" || ko "AC5 hooksSha256: $out want $canon_sha"
run "$H" env hook seed
{ [ "$rc" -eq 2 ] && grep -qxF 'BLOCKED env_hooks_unapproved' <<<"$out" && [ ! -e "$H/marker-seed" ]; } \
  && ok "AC4 no approvals file: hook not run, stdout 'BLOCKED env_hooks_unapproved', exit 2" || ko "AC4 no file: rc=$rc out='$out' err='$err' marker=$( [ -e "$H/marker-seed" ] && echo present || echo absent)"
write_approval "/some/other/repo" "$canon_sha"
run "$H" env hook seed
{ [ "$rc" -eq 2 ] && grep -qxF 'BLOCKED env_hooks_unapproved' <<<"$out" && [ ! -e "$H/marker-seed" ]; } \
  && ok "AC4 an approval for another repo only: hook not run, BLOCKED env_hooks_unapproved" || ko "AC4 other repo: rc=$rc out='$out' err='$err'"
write_approval "$H_REAL" "$canon_sha"
run "$H" env hook seed
{ [ "$rc" -eq 0 ] && [ -e "$H/marker-seed" ]; } && ok "AC5 a matching approval for this repo (its realpath) runs the hook at the repo root" || ko "AC5 approved: rc=$rc out='$out' err='$err'"
rm -f "$H/marker-seed"; mkdir -p "$H/deep/er"
run "$H/deep/er" env hook seed
{ [ "$rc" -eq 0 ] && [ -e "$H/marker-seed" ] && [ ! -e "$H/deep/er/marker-seed" ]; } && ok "AC5 the hook runs at the repo root even from a subdirectory" || ko "AC5 cwd: rc=$rc err='$err'"
rm -f "$H/marker-seed"
printf '{"schema_version":1,"origins":["http://localhost:3000"],"hooks":{"seed":"touch marker-seed ","reset":"true"}}' > "$H/selvedge.json"
run "$H" env hook seed
{ [ "$rc" -eq 2 ] && grep -qxF 'BLOCKED env_hooks_unapproved' <<<"$out" && [ ! -e "$H/marker-seed" ]; } \
  && ok "AC5 one changed byte in a hook re-blocks it and the marker is not rewritten" || ko "AC5 one byte: rc=$rc out='$out' err='$err'"
printf '{"schema_version":1,"origins":["http://localhost:3000"],"hooks":%s}' "$hooks_json" > "$H/selvedge.json"
# The documented limit, pinned: --base pins the hook COMMAND TEXT, not the script it runs. main has
# {"seed":"bash seed.sh"} approved; a pr branch edits only seed.sh; `hook seed --base main` runs the
# pr's seed.sh. If this ever changes, update README "Where approvals live" and the approve prompt.
S="$TMP/r-hook-script"; mkrepo "$S"
printf '{"schema_version":1,"origins":["http://localhost:3000"],"hooks":{"seed":"bash seed.sh"}}' > "$S/selvedge.json"
printf 'touch marker-main\n' > "$S/seed.sh"
git -C "$S" add selvedge.json seed.sh && git -C "$S" commit -q -m base && git -C "$S" checkout -q -b pr
printf 'touch marker-pr\n' > "$S/seed.sh"
git -C "$S" commit -qam 'pr edits only the script'
write_approval "$(cd "$S" && pwd -P)" "$(sha_of '{"seed":"bash seed.sh"}')"
run "$S" env hook seed --base main
{ [ "$rc" -eq 0 ] && [ -e "$S/marker-pr" ] && [ ! -e "$S/marker-main" ]; } \
  && ok "documented limit: with --base main an approved 'bash seed.sh' runs the checkout's (pr's) seed.sh" || ko "hook script limit: rc=$rc out='$out' err='$err'"
run "$H" env hook auth_setup
{ [ "$rc" -eq 0 ] && grep -qF 'no auth_setup hook' <<<"$out"; } && ok "a hook name not in selvedge.json is a no-op (exit 0)" || ko "undefined hook: rc=$rc out='$out'"
run "$H" env hook teardown
[ "$rc" -eq 2 ] && ok "an unknown hook name is a usage error (exit 2)" || ko "unknown hook name: rc=$rc"
printf '{"schema_version":1,"origins":["http://localhost:3000"],"hooks":{"seed":"exit 7"}}' > "$H/selvedge.json"
write_approval "$H_REAL" "$(sha_of '{"seed":"exit 7"}')"
run "$H" env hook seed
[ "$rc" -eq 1 ] && ok "a failing approved hook exits 1" || ko "failing hook: rc=$rc err='$err'"

# AC6: a remote origin blocks hooks even with allow_remote and a matching approval.
remote_hooks='{"seed":"touch marker-seed"}'
printf '{"schema_version":1,"origins":["http://localhost:3000","https://staging.example.com"],"allow_remote":true,"hooks":%s}' "$remote_hooks" > "$H/selvedge.json"
write_approval "$H_REAL" "$(sha_of "$remote_hooks")"
run "$H" env check
grep -qxF 'hook approval: approved' <<<"$out" && ok "AC6 setup: the remote-origin config's hooks are approved" || ko "AC6 setup: out='$out' err='$err'"
run "$H" env hook seed
{ [ "$rc" -eq 2 ] && grep -qxF 'BLOCKED env_hooks_remote_origin' <<<"$out" && [ ! -e "$H/marker-seed" ]; } \
  && ok "AC6 any non-local origin: no hook runs, BLOCKED env_hooks_remote_origin, exit 2" || ko "AC6: rc=$rc out='$out' err='$err'"

# Repo identity: the origin remote URL (userinfo stripped), not the path, once a remote exists.
I="$TMP/r-ident"; mkrepo "$I"
git -C "$I" remote add origin 'https://someone:s3cr3t-token@example.invalid/o/r.git'
printf '{"schema_version":1,"origins":["http://localhost:3000"],"hooks":%s}' "$remote_hooks" > "$I/selvedge.json"
write_approval "$(cd "$I" && pwd -P)" "$(sha_of "$remote_hooks")"
run "$I" env hook seed
{ [ "$rc" -eq 2 ] && [ ! -e "$I/marker-seed" ]; } && ok "identity: with an origin remote, a path-keyed approval does not count" || ko "identity path: rc=$rc out='$out'"
write_approval 'https://example.invalid/o/r.git' "$(sha_of "$remote_hooks")"
run "$I" env hook seed
{ [ "$rc" -eq 0 ] && [ -e "$I/marker-seed" ]; } && ok "identity: the origin remote URL (userinfo stripped) keys the approval" || ko "identity url: rc=$rc out='$out' err='$err'"

# Nothing inside the repo is read as an approval: HOME pointing into the repo is ignored.
J="$TMP/r-inrepo"; mkrepo "$J"
printf '{"schema_version":1,"origins":["http://localhost:3000"],"hooks":%s}' "$remote_hooks" > "$J/selvedge.json"
mkdir -p "$J/.claude/selvedge"
node -e 'const [f,i,s]=process.argv.slice(1); require("fs").writeFileSync(f, JSON.stringify({schema_version:1,approvals:{[i]:{hooks_sha256:s}}}))' \
  "$J/.claude/selvedge/approvals.json" "$(cd "$J" && pwd -P)" "$(sha_of "$remote_hooks")"
out="$(cd "$J" && HOME="$J" bash "$CLI" env hook seed 2>/dev/null </dev/null)"; rc=$?
{ [ "$rc" -eq 2 ] && grep -qxF 'BLOCKED env_hooks_unapproved' <<<"$out" && [ ! -e "$J/marker-seed" ]; } \
  && ok "an approvals file inside the repo is never read as an approval" || ko "in-repo approvals: rc=$rc out='$out'"

echo "-- env approve (AC7)"
P="$TMP/r-approve"; mkrepo "$P"
printf '{"schema_version":1,"origins":["http://localhost:3000"],"hooks":{"seed":"touch marker-seed"}}' > "$P/selvedge.json"
p_sha="$(sha_of '{"seed":"touch marker-seed"}')"
export HOME="$TMP/home-approve"; mkdir -p "$HOME"; APPROVALS="$HOME/.claude/selvedge/approvals.json"
out="$(cd "$P" && printf 'y\n' | bash "$CLI" env approve 2>"$TMP/stderr")"; rc=$?; err="$(cat "$TMP/stderr")"
{ [ "$rc" -eq 2 ] && grep -qF 'approve_requires_tty' <<<"$err" && [ ! -e "$APPROVALS" ]; } \
  && ok "AC7 no TTY (y piped on stdin): exit 2 approve_requires_tty, nothing written" || ko "AC7 no TTY: rc=$rc out='$out' err='$err' file=$( [ -e "$APPROVALS" ] && echo written || echo absent)"
out="$(cd "$P" && printf 'n\n' | python3 -c "$PTY_PY" bash "$CLI" env approve 2>&1)"; rc=$?
{ [ "$rc" -eq 1 ] && [ ! -e "$APPROVALS" ] && grep -qF 'nothing was written' <<<"$out"; } \
  && ok "AC7 on a TTY, answering n writes nothing" || ko "AC7 pty n: rc=$rc out='$out' file=$( [ -e "$APPROVALS" ] && echo written || echo absent)"
out="$(cd "$P" && printf 'y\n' | python3 -c "$PTY_PY" bash "$CLI" env approve 2>&1)"; rc=$?
{ [ "$rc" -eq 0 ] && grep -qF 'seed: "touch marker-seed"' <<<"$out" && grep -qF "$p_sha" <<<"$out" && [ -f "$APPROVALS" ]; } \
  && ok "AC7 on a TTY it prints every hook and the hash, and y writes the approval" || ko "AC7 pty y: rc=$rc out='$out'"
grep -qF 'limit: the approval pins the hook command text, not the files it runs' <<<"$out" \
  && ok "AC7 the approve prompt states the limit: the approval pins the command text, not the files a hook runs" || ko "AC7 approve limit line missing: out='$out'"
out="$(node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); console.log(d.approvals[process.argv[2]] && d.approvals[process.argv[2]].hooks_sha256)' "$APPROVALS" "$(cd "$P" && pwd -P)" 2>&1)"
[ "$out" = "$p_sha" ] && ok "AC7 the recorded approval is this repo's identity -> the canonical hooks sha256" || ko "AC7 recorded: '$out' want $p_sha"
{ [ "$(file_mode "$APPROVALS")" = "600" ] && [ "$(file_mode "$(dirname "$APPROVALS")")" = "700" ]; } \
  && ok "AC7 approvals.json is mode 0600 and its directory 0700" || ko "AC7 modes: file $(file_mode "$APPROVALS") dir $(file_mode "$(dirname "$APPROVALS")")"
leftover="$(find "$(dirname "$APPROVALS")" -name '*.tmp' | wc -l | tr -d ' ')"
[ "$leftover" = "0" ] && ok "AC7 the atomic write leaves no temp file behind" || ko "AC7 temp files left: $leftover"
run "$P" env hook seed
{ [ "$rc" -eq 0 ] && [ -e "$P/marker-seed" ]; } && ok "AC7 a hook approved through the TTY then runs" || ko "AC7 run after approve: rc=$rc out='$out' err='$err'"
chmod 755 "$(dirname "$APPROVALS")"; chmod 644 "$APPROVALS"
printf '{"schema_version":1,"origins":["http://localhost:3000"],"hooks":{"seed":"touch marker-two"}}' > "$P/selvedge.json"
out="$(cd "$P" && printf 'y\n' | python3 -c "$PTY_PY" bash "$CLI" env approve 2>&1)"; rc=$?
{ [ "$rc" -eq 0 ] && [ "$(file_mode "$APPROVALS")" = "600" ] && [ "$(file_mode "$(dirname "$APPROVALS")")" = "700" ]; } \
  && ok "AC7 re-approving rewrites the file 0600 and tightens an existing directory to 0700" || ko "AC7 re-approve modes: rc=$rc file $(file_mode "$APPROVALS") dir $(file_mode "$(dirname "$APPROVALS")")"
printf 'not json' > "$APPROVALS"
printf '{"schema_version":1,"origins":["http://localhost:3000"],"hooks":{"seed":"touch marker-three"}}' > "$P/selvedge.json"
out="$(cd "$P" && printf 'y\n' | python3 -c "$PTY_PY" bash "$CLI" env approve 2>&1)"; rc=$?
{ [ "$rc" -eq 1 ] && [ "$(cat "$APPROVALS")" = "not json" ]; } && ok "AC7 a malformed approvals file is never overwritten" || ko "AC7 malformed: rc=$rc out='$out'"
run "$P" env hook seed
{ [ "$rc" -eq 2 ] && grep -qxF 'BLOCKED env_hooks_unapproved' <<<"$out"; } && ok "a malformed approvals file reads as unapproved (fail closed)" || ko "malformed read: rc=$rc out='$out'"
export HOME="$TMP/home"; APPROVALS="$HOME/.claude/selvedge/approvals.json"

echo "-- env init (AC8)"
N="$TMP/r-init"; mkrepo "$N"
run "$N" env init
{ [ "$rc" -eq 2 ] && grep -qF 'port_required' <<<"$err" && [ ! -e "$N/selvedge.json" ]; } \
  && ok "AC8 no --port, nothing detectable, no TTY: exit 2 port_required, nothing written" || ko "AC8 port_required: rc=$rc out='$out' err='$err'"
for bad in 0 65536 abc; do
  run "$N" env init --port "$bad"
  { [ "$rc" -eq 2 ] && [ ! -e "$N/selvedge.json" ]; } && ok "AC8 --port $bad is refused (exit 2, nothing written)" || ko "AC8 --port $bad: rc=$rc"
done
run "$N" env init --port 4321
want='{"schema_version":1,"origins":["http://localhost:4321"],"allow_remote":false,"allow_remote_mutation":false}'
got="$(node -e 'console.log(JSON.stringify(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))))' "$N/selvedge.json" 2>&1)"
{ [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; } && ok "AC8 --port 4321 writes exactly schema_version 1, one local origin, both allow_* false, no hooks" || ko "AC8 init: rc=$rc got='$got'"
run "$N" env check; [ "$rc" -eq 0 ] && ok "AC8 the written file passes env check" || ko "AC8 check after init: rc=$rc err='$err'"
cp "$N/selvedge.json" "$TMP/init.orig"
run "$N" env init --port 9999
{ [ "$rc" -ne 0 ] && grep -qF 'refusing to overwrite' <<<"$err" && cmp -s "$N/selvedge.json" "$TMP/init.orig"; } \
  && ok "AC8 init refuses to overwrite an existing selvedge.json" || ko "AC8 overwrite: rc=$rc err='$err'"
for spec in 'vite --port 5173|5173' 'next dev -p 3001|3001' 'PORT=8080 node server.js|8080' 'astro dev --port=4322|4322'; do
  script="${spec%|*}"; port="${spec##*|}"
  D="$TMP/r-detect-$port"; mkrepo "$D"
  node -e 'require("fs").writeFileSync(process.argv[1], JSON.stringify({scripts:{dev:process.argv[2]}}))' "$D/package.json" "$script"
  run "$D" env init
  { [ "$rc" -eq 0 ] && grep -qF "\"http://localhost:$port\"" "$D/selvedge.json"; } \
    && ok "AC8 detects port $port from scripts.dev '$script'" || ko "AC8 detect '$script': rc=$rc err='$err'"
done
D="$TMP/r-detect-start"; mkrepo "$D"
printf '{"scripts":{"dev":"vite","start":"serve -p 7001"}}' > "$D/package.json"
run "$D" env init
{ [ "$rc" -eq 0 ] && grep -qF '"http://localhost:7001"' "$D/selvedge.json"; } && ok "AC8 falls back to scripts.start" || ko "AC8 scripts.start: rc=$rc err='$err'"

echo "-- env check output (AC9)"
C="$TMP/r-check"; mkrepo "$C"
printf '{"schema_version":1,"origins":["http://localhost:3000"]}' > "$C/selvedge.json"
run "$C" env check
{ [ "$rc" -eq 0 ] && grep -qF 'the guard covers the browser only' <<<"$out" && grep -qF "the verifier's shell is not behind the proxy" <<<"$out"; } \
  && ok "AC9 a passing check states the guard covers the browser only and the shell is not behind the proxy" || ko "AC9 scope: rc=$rc out='$out'"
grep -qxF 'hook approval: no hooks' <<<"$out" && ok "AC9 approval state 'no hooks'" || ko "AC9 no hooks: out='$out'"
printf '{"schema_version":1,"origins":["http://localhost:3000"],"hooks":{"seed":"true"}}' > "$C/selvedge.json"
run "$C" env check
{ [ "$rc" -eq 0 ] && grep -qE '^hook approval: unapproved' <<<"$out"; } && ok "AC9 approval state 'unapproved'" || ko "AC9 unapproved: out='$out'"
write_approval "$(cd "$C" && pwd -P)" "$(sha_of '{"seed":"true"}')"
run "$C" env check
grep -qxF 'hook approval: approved' <<<"$out" && ok "AC9 approval state 'approved'" || ko "AC9 approved: out='$out'"

echo "test-env: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
