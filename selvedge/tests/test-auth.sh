#!/usr/bin/env bash
# test-auth.sh — pins the `auth` key of selvedge.json, the auth state path and modes, and
# `selvedge auth setup [--headed]` (selvedge/lib/env-config.mjs, auth-state.mjs, auth.mjs, the
# guarded-browser options in runner/route-guard.mjs): qa-split item 05 AC1–AC4 and AC10. Every arm
# turns red under its row of the brief's pin-mutation table.
#
# Hermetic: a fresh temp HOME (the user's ~/.local/state/selvedge and ~/.claude/selvedge are never
# touched), temp git repos, the stub Playwright (tests/fixtures/stub-playwright.mjs, no Chromium), no
# network. Needs node (>= 18) and git; a missing one is a FAIL, never a skip.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$TESTS_DIR/.." && pwd)"
CLI="$PLUGIN_DIR/bin/selvedge"
STUB_PW="$TESTS_DIR/fixtures/stub-playwright.mjs"
export SELVEDGE_LIB="$PLUGIN_DIR/lib"
export STUB_PW_MODULE="$STUB_PW"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "  ok   $1"; }
ko() { fail=$((fail + 1)); echo "  FAIL $1"; }

for tool in node git; do
  command -v "$tool" >/dev/null 2>&1 || { echo "  FAIL $tool is not on PATH (test-auth.sh needs it)"; echo "test-auth: 0 passed, 1 failed"; exit 1; }
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/selvedge-auth.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd)" # no `//` from a TMPDIR ending in a slash: paths are compared as printed
export HOME="$TMP/home"
mkdir -p "$HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_CONFIG_NOSYSTEM=1
unset SELVEDGE_PLAYWRIGHT_MODULE SELVEDGE_AUTH_TIMEOUT_MS SELVEDGE_STORAGE_STATE PLAYWRIGHT_DISABLE_FORCED_CHROMIUM_PROXIED_LOOPBACK APP_USER APP_PASS
APPROVALS="$HOME/.claude/selvedge/approvals.json"
USER_VALUE='fixture-user-7Qx'
PASS_VALUE='fixture-pass-Zk93-never-printed'

# run <dir> <cli args…> — sets $rc, $out (stdout), $err (stderr); stdin is /dev/null (no TTY).
run() {
  local dir="$1"; shift
  out="$(cd "$dir" && bash "$CLI" "$@" 2>"$TMP/stderr" </dev/null)"; rc=$?
  err="$(cat "$TMP/stderr")"
}

# mkrepo <dir> — an empty git repo on branch main.
mkrepo() { mkdir -p "$1" && git -C "$1" init -q && git -C "$1" symbolic-ref HEAD refs/heads/main; }

# cfg <file> <auth_setup hook or ""> <auth JSON or ""> [<origins JSON>] — writes selvedge.json.
cfg() {
  node -e 'const [f, h, a, o] = process.argv.slice(1);
const c = { schema_version: 1, origins: JSON.parse(o || "[\"http://localhost:3000\"]") };
if (o && JSON.parse(o).some((x) => !/^http:\/\/(localhost|127\.0\.0\.1)(:|$)/.test(x))) c.allow_remote = true;
if (h) c.hooks = { auth_setup: h };
if (a) c.auth = JSON.parse(a);
require("fs").writeFileSync(f, JSON.stringify(c));' "$@"
}

# sha256 hex of a literal string — independent of env-approvals.mjs's canonicalization.
sha_of() { node -e 'process.stdout.write(require("crypto").createHash("sha256").update(process.argv[1]).digest("hex"))' "$1"; }

# approve_hook <identity> <hook command> — a hand-written approval of {"auth_setup": <cmd>} (one key,
# so JSON.stringify is the canonical form).
approve_hook() {
  local canon
  canon="$(node -e 'process.stdout.write(JSON.stringify({ auth_setup: process.argv[1] }))' "$2")"
  mkdir -p "$(dirname "$APPROVALS")"
  node -e 'const fs = require("fs"); const [f, i, s] = process.argv.slice(1);
let d = { schema_version: 1, approvals: {} }; try { d = JSON.parse(fs.readFileSync(f, "utf8")); } catch {}
d.approvals[i] = { hooks_sha256: s }; fs.writeFileSync(f, JSON.stringify(d));' "$APPROVALS" "$1" "$(sha_of "$canon")"
}

file_mode() { node -e 'process.stdout.write((require("fs").lstatSync(process.argv[1]).mode & 0o777).toString(8))' "$1" 2>/dev/null || echo none; }

# state_file <repo> [<identity>] — where the state must be: $HOME/.local/state/selvedge/<sha256 of the
# repo identity>/auth/storageState.json, computed here, not by auth-state.mjs.
state_file() {
  local ident="${2:-$(cd "$1" && pwd -P)}"
  printf '%s/.local/state/selvedge/%s/auth/storageState.json' "$HOME" "$(sha_of "$ident")"
}

# node_eval <js> [<arg>…] — an ES module with E (env-config), S (auth-state), G (route-guard)
# imported; the args are process.argv[1…].
node_eval() {
  local js="$1"; shift
  node --input-type=module -e "
import { pathToFileURL } from 'node:url';
const E = await import(pathToFileURL(process.env.SELVEDGE_LIB + '/env-config.mjs').href);
const S = await import(pathToFileURL(process.env.SELVEDGE_LIB + '/auth-state.mjs').href);
const G = await import(pathToFileURL(process.env.SELVEDGE_LIB + '/runner/route-guard.mjs').href);
$js" "$@"
}

CHECK_OK='{"env":["APP_USER","APP_PASS"],"signed_in_check":{"url":"http://localhost:3000/account","locator":{"role":"heading","name":"Account"}}}'

echo "-- static: dispatch, one home per rule"
grep -qE '^  auth\) shift; cmd_node auth "\$@" ;;$' "$CLI" && ok "bin/selvedge dispatches auth to lib/auth.mjs (cmd_node auth)" || ko "bin/selvedge has no auth arm"
out="$(bash "$CLI" 2>&1)"
grep -qE '^  auth setup \[--headed\]' <<<"$out" && ok "the CLI help lists 'auth setup [--headed]'" || ko "help has no auth line: '$out'"
reasons="$(node_eval 'console.log(Object.keys(E.REASONS).join("|"))')"
hits="$(cd "$SELVEDGE_LIB" && grep -nE "['\"\`]($reasons)['\"\`]" auth-state.mjs auth.mjs)"
{ [ -n "$reasons" ] && [ -z "$hits" ]; } && ok "auth-state.mjs and auth.mjs name no reason as a string literal (REASONS only)" || ko "string-literal reasons: $hits"
hits="$(cd "$SELVEDGE_LIB" && grep -nE '0o[0-7]{3}|function insideRepo|function repoIdentity' auth-state.mjs auth.mjs)"
{ [ -z "$hits" ] && grep -qF "import { DIR_MODE, FILE_MODE, insideRepo, repoIdentity } from './env-approvals.mjs';" "$SELVEDGE_LIB/auth-state.mjs"; } \
  && ok "auth-state.mjs reuses insideRepo, repoIdentity, FILE_MODE and DIR_MODE from env-approvals.mjs (no copy)" || ko "a copied store rule: $hits"

echo "-- AC1 the auth key: accepted, normalized, structurally validated by loadConfig"
R="$TMP/r-config"; mkrepo "$R"
cfg "$R/selvedge.json" "" "$CHECK_OK"
run "$R" env check
[ "$rc" -eq 0 ] && ok "AC1 an auth block (env names + signed_in_check url/locator) passes env check" || ko "AC1 valid auth: rc=$rc err='$err'"
out="$(node_eval '
const a = E.validateConfig({ schema_version: 1, origins: ["http://localhost:3000"], auth: JSON.parse(process.argv[1]) }).auth;
const n = E.validateConfig({ schema_version: 1, origins: ["http://localhost:3000"] }).auth;
console.log(JSON.stringify([a.env, a.signed_in_check.url, a.signed_in_check.locator, Object.isFrozen(a), Object.isFrozen(a.signed_in_check.locator), n]));' "$CHECK_OK" 2>&1)"
[ "$out" = '[["APP_USER","APP_PASS"],"http://localhost:3000/account",{"role":"heading","name":"Account"},true,true,null]' ] \
  && ok "AC1 validateConfig returns auth frozen (locator too), and null when absent" || ko "AC1 normalized auth: $out"
for bad in '{"users":["a"]}' \
           '{"env":["APP_USER"],"password":"x"}' \
           '{"signed_in_check":{"url":"http://localhost:3000/","locator":{"text":"Hi"},"timeout":5}}' \
           '{"env":[1]}' \
           '{"env":["app_user"]}' \
           '{"env":["APP-USER"]}' \
           '{"env":"APP_USER"}' \
           '{"signed_in_check":{"url":"http://localhost:4000/account","locator":{"text":"Hi"}}}' \
           '{"signed_in_check":{"url":"https://evil.example.com/","locator":{"text":"Hi"}}}' \
           '{"signed_in_check":{"url":"http://localhost:3000/","locator":"#account"}}' \
           '{"signed_in_check":{"url":"http://localhost:3000/","locator":[{"text":"Hi"}]}}' \
           '{"signed_in_check":{"locator":{"text":"Hi"}}}' \
           '{"signed_in_check":"http://localhost:3000/"}' \
           '["APP_USER"]'; do
  cfg "$R/selvedge.json" "" "$bad"; run "$R" env check
  { [ "$rc" -eq 2 ] && grep -qF 'config_schema_violation' <<<"$err"; } \
    && ok "AC1 auth $bad exits 2 config_schema_violation" || ko "AC1 auth $bad: rc=$rc err='$err'"
done
cfg "$R/selvedge.json" "true" '{"env":["APP_USER"],"pasword":"typo"}'
run "$R" auth setup
{ [ "$rc" -eq 2 ] && grep -qF 'config_schema_violation' <<<"$err" && grep -qF 'pasword' <<<"$err"; } \
  && ok "AC1 auth setup refuses an unknown auth sub-key through loadConfig (exit 2, names it)" || ko "AC1 auth setup sub-key: rc=$rc err='$err'"

echo "-- AC1 the locator FORM: validateSignedInCheck (plan-steps validateSteps)"
out="$(node_eval '
const cfg = (loc) => E.validateConfig({ schema_version: 1, origins: ["http://localhost:3000"], auth: { signed_in_check: { url: "http://localhost:3000/account", locator: loc } } });
const res = (loc) => { try { return JSON.stringify(S.validateSignedInCheck(cfg(loc))); } catch (e) { return e.reason + (e.message.includes("auth.signed_in_check.locator") ? "@locator" : ""); } };
console.log(JSON.stringify([
  res({ role: "heading", name: "Account" }), res({ css: ".account" }), res({ xpath: "//h1" }), res({ role: "heading", text: "x" }), res({}),
  res({ text: "<script>x" }), S.validateSignedInCheck(E.validateConfig({ schema_version: 1, origins: ["http://localhost:3000"] })),
]));' 2>&1)"
[ "$out" = '["[{\"type\":\"goto\",\"url\":\"http://localhost:3000/account\"},{\"type\":\"wait_for\",\"locator\":{\"role\":\"heading\",\"name\":\"Account\"},\"state\":\"attached\"}]","config_schema_violation@locator","config_schema_violation@locator","config_schema_violation@locator","config_schema_violation@locator","config_schema_violation@locator",null]' ] \
  && ok "AC1 validateSignedInCheck: one plan-step locator form passes; CSS, XPath, two forms, none and code-like are config_schema_violation; no check is null" || ko "AC1 validateSignedInCheck: $out"
LOG="$TMP/pw-css.log"
cfg "$R/selvedge.json" "" '{"signed_in_check":{"url":"http://localhost:3000/account","locator":{"css":"#account"}}}'
run "$R" env check
[ "$rc" -eq 0 ] && ok "AC1 a CSS locator is still a plain object, so loadConfig itself accepts it (the form is checked where it is used)" || ko "AC1 css via env check: rc=$rc err='$err'"
out="$(cd "$R" && SELVEDGE_PLAYWRIGHT_MODULE="$STUB_PW" STUB_PW_LOG="$LOG" bash "$CLI" auth setup --headed 2>"$TMP/stderr" </dev/null)"; rc=$?; err="$(cat "$TMP/stderr")"
{ [ "$rc" -eq 2 ] && grep -qF 'config_schema_violation' <<<"$err" && grep -qF 'CSS and XPath are never accepted' <<<"$err" && [ ! -e "$LOG" ] \
  && [ ! -e "$(state_file "$R")" ]; } \
  && ok "AC1 auth setup --headed with a CSS locator exits 2 config_schema_violation, nothing launched, nothing written" \
  || ko "AC1 css --headed: rc=$rc err='$err' launched=$( [ -e "$LOG" ] && echo yes || echo no)"

echo "-- AC2 auth setup runs the approved hook and keeps the state outside the repo"
A="$TMP/r-hook"; mkrepo "$A"
MARK="$TMP/mark-a"
HOOK="umask 000; [ \"\$APP_USER\" = '$USER_VALUE' ] && [ -n \"\$APP_PASS\" ] || exit 9; touch '$MARK'; printf '{\"cookies\":[],\"origins\":[]}' > \"\$SELVEDGE_STORAGE_STATE\""
cfg "$A/selvedge.json" "$HOOK" '{"env":["APP_USER","APP_PASS"]}'
git -C "$A" add selvedge.json && git -C "$A" commit -q -m base
approve_hook "$(cd "$A" && pwd -P)" "$HOOK"
before="$(git -C "$A" status --porcelain --ignored)"
out="$(cd "$A" && umask 022 && APP_USER="$USER_VALUE" APP_PASS="$PASS_VALUE" bash "$CLI" auth setup 2>"$TMP/stderr" </dev/null)"; rc=$?; err="$(cat "$TMP/stderr")"
after="$(git -C "$A" status --porcelain --ignored)"
SF="$(state_file "$A")"
{ [ "$rc" -eq 0 ] && [ -f "$SF" ] && [ -e "$MARK" ] && grep -qF "$SF" <<<"$out"; } \
  && ok "AC2 exit 0; the hook ran with the auth.env values and the state is at \$HOME/.local/state/selvedge/<sha256(repo identity)>/auth/storageState.json" \
  || ko "AC2 setup: rc=$rc out='$out' err='$err' file=$( [ -f "$SF" ] && echo present || echo absent)"
[ "$(file_mode "$SF")" = "600" ] && ok "AC2 the state file is mode 0600 although the hook wrote it under umask 000" || ko "AC2 file mode: $(file_mode "$SF")"
[ "$(file_mode "$(dirname "$SF")")" = "700" ] && ok "AC2 the auth directory is mode 0700" || ko "AC2 dir mode: $(file_mode "$(dirname "$SF")")"
[ "$before" = "$after" ] && ok "AC2 git status --porcelain --ignored in the repo is byte-identical before and after" || ko "AC2 repo changed: before='$before' after='$after'"
leftover="$(find "$(dirname "$SF")" -type f ! -name storageState.json | wc -l | tr -d ' ')"
[ "$leftover" = "0" ] && ok "AC2 no temp file is left beside the state" || ko "AC2 temp files left: $leftover"
{ ! grep -qF "$PASS_VALUE" <<<"$out$err" && ! grep -qF "$USER_VALUE" <<<"$out$err"; } && ok "AC2 neither credential value appears on stdout or stderr" || ko "AC2 a value was printed"
out="$(node_eval 'console.log(JSON.stringify([S.authStatePath({ root: process.argv[1] }) === process.argv[2], S.hasState({ root: process.argv[1] }), S.hasState({ root: process.argv[1], env: {} }), S.authStatePath({ root: process.argv[1], env: {} })]));' "$A" "$SF" 2>&1)"
[ "$out" = '[true,true,false,null]' ] && ok "AC2 authStatePath is that path and hasState sees the file; with no HOME there is no path and no state" || ko "AC2 authStatePath/hasState: $out"
chmod 755 "$(dirname "$SF")"; chmod 644 "$SF"
(cd "$A" && APP_USER="$USER_VALUE" APP_PASS="$PASS_VALUE" bash "$CLI" auth setup >/dev/null 2>&1 </dev/null); rc=$?
{ [ "$rc" -eq 0 ] && [ "$(file_mode "$SF")" = "600" ] && [ "$(file_mode "$(dirname "$SF")")" = "700" ]; } \
  && ok "AC2 a re-run rewrites the state 0600 and tightens an existing directory to 0700" || ko "AC2 re-run modes: rc=$rc file $(file_mode "$SF") dir $(file_mode "$(dirname "$SF")")"
rm -f "$SF"; ln -s "$TMP/elsewhere.json" "$SF"; printf '{}' > "$TMP/elsewhere.json"
out="$(node_eval 'console.log(S.hasState({ root: process.argv[1] }));' "$A" 2>&1)"
[ "$out" = "false" ] && ok "AC2 hasState does not take a symlink at the state path as a state" || ko "AC2 hasState symlink: $out"
rm -f "$SF"
# the identity: the origin remote URL without userinfo, so a token in the remote never names a path
I="$TMP/r-ident"; mkrepo "$I"
git -C "$I" remote add origin 'https://someone:s3cr3t-token@example.invalid/o/r.git'
cfg "$I/selvedge.json" "$HOOK" '{"env":["APP_USER","APP_PASS"]}'
approve_hook 'https://example.invalid/o/r.git' "$HOOK"
(cd "$I" && APP_USER="$USER_VALUE" APP_PASS="$PASS_VALUE" bash "$CLI" auth setup >/dev/null 2>&1 </dev/null); rc=$?
{ [ "$rc" -eq 0 ] && [ -f "$(state_file "$I" 'https://example.invalid/o/r.git')" ] && ! find "$HOME/.local/state" | grep -qF 's3cr3t'; } \
  && ok "AC2 with an origin remote, <repo-id> is the sha256 of the remote URL without its userinfo" || ko "AC2 remote identity: rc=$rc"
# never inside the repo: a HOME that points into the repo is refused before the hook runs
rm -f "$MARK"
out="$(cd "$A" && HOME="$A" APP_USER="$USER_VALUE" APP_PASS="$PASS_VALUE" bash "$CLI" auth setup 2>"$TMP/stderr" </dev/null)"; rc=$?; err="$(cat "$TMP/stderr")"
{ [ "$rc" -eq 1 ] && grep -qF 'inside the repo' <<<"$err" && [ ! -e "$A/.local" ] && [ ! -e "$MARK" ] && [ -z "$(git -C "$A" status --porcelain)" ]; } \
  && ok "a state path that resolves inside the repo is refused (exit 1): no hook ran, nothing written" || ko "inside repo: rc=$rc err='$err'"

echo "-- AC3 an unapproved auth_setup hook is BLOCKED and never runs"
U="$TMP/r-unapproved"; mkrepo "$U"
MARK_U="$TMP/mark-u"
HOOK_U="touch '$MARK_U'; printf '{}' > \"\$SELVEDGE_STORAGE_STATE\""
cfg "$U/selvedge.json" "$HOOK_U" '{"env":["APP_USER"]}'
out="$(cd "$U" && APP_USER="$USER_VALUE" bash "$CLI" auth setup 2>"$TMP/stderr" </dev/null)"; rc=$?; err="$(cat "$TMP/stderr")"
{ [ "$rc" -eq 2 ] && grep -qxF 'BLOCKED env_hooks_unapproved' <<<"$out" && [ ! -e "$MARK_U" ] && [ ! -e "$(state_file "$U")" ]; } \
  && ok "AC3 no approval: stdout 'BLOCKED env_hooks_unapproved', exit 2, the hook did not run, no state" || ko "AC3 no approval: rc=$rc out='$out' err='$err'"
approve_hook "$(cd "$U" && pwd -P)" "touch '$MARK_U'"
out="$(cd "$U" && APP_USER="$USER_VALUE" bash "$CLI" auth setup 2>"$TMP/stderr" </dev/null)"; rc=$?; err="$(cat "$TMP/stderr")"
{ [ "$rc" -eq 2 ] && grep -qxF 'BLOCKED env_hooks_unapproved' <<<"$out" && [ ! -e "$MARK_U" ] && [ ! -e "$(state_file "$U")" ]; } \
  && ok "AC3 an approval of other hook text: BLOCKED env_hooks_unapproved, exit 2, nothing ran or was written" || ko "AC3 other text: rc=$rc out='$out' err='$err'"
leftover="$(find "$(dirname "$(state_file "$U")")" -type f 2>/dev/null | wc -l | tr -d ' ')"
[ "$leftover" = "0" ] && ok "AC3 a BLOCKED setup leaves no file in the state directory" || ko "AC3 files left: $leftover"
REM="$TMP/r-remote"; mkrepo "$REM"
cfg "$REM/selvedge.json" "$HOOK_U" '{"env":["APP_USER"]}' '["http://localhost:3000","https://staging.example.com"]'
approve_hook "$(cd "$REM" && pwd -P)" "$HOOK_U"
out="$(cd "$REM" && APP_USER="$USER_VALUE" bash "$CLI" auth setup 2>"$TMP/stderr" </dev/null)"; rc=$?; err="$(cat "$TMP/stderr")"
{ [ "$rc" -eq 2 ] && grep -qxF 'BLOCKED env_hooks_remote_origin' <<<"$out" && [ ! -e "$MARK_U" ] && [ ! -e "$(state_file "$REM")" ]; } \
  && ok "a remote origin: BLOCKED env_hooks_remote_origin, exit 2, the hook did not run" || ko "remote origin: rc=$rc out='$out' err='$err'"

echo "-- AC4 unset credentials, a hook that writes nothing, and no way to sign in"
B="$TMP/r-unset"; mkrepo "$B"
MARK_B="$TMP/mark-b"
HOOK_B="touch '$MARK_B'; printf '{}' > \"\$SELVEDGE_STORAGE_STATE\""
cfg "$B/selvedge.json" "$HOOK_B" '{"env":["APP_USER","APP_PASS"]}'
approve_hook "$(cd "$B" && pwd -P)" "$HOOK_B"
out="$(cd "$B" && APP_USER="$USER_VALUE" bash "$CLI" auth setup 2>"$TMP/stderr" </dev/null)"; rc=$?; err="$(cat "$TMP/stderr")"
{ [ "$rc" -eq 2 ] && grep -qxF 'BLOCKED placeholder_unset' <<<"$out" && grep -qF 'APP_PASS' <<<"$err" && ! grep -qF "$USER_VALUE" <<<"$out$err" \
  && [ ! -e "$MARK_B" ] && [ ! -e "$(state_file "$B")" ]; } \
  && ok "AC4 an unset auth.env name: BLOCKED placeholder_unset, stderr names APP_PASS (no value), exit 2, the hook did not run" \
  || ko "AC4 unset: rc=$rc out='$out' err='$err' marker=$( [ -e "$MARK_B" ] && echo present || echo absent)"
for spec in "true|exits 0 without writing \$SELVEDGE_STORAGE_STATE" \
            "printf 'not json' > \"\$SELVEDGE_STORAGE_STATE\"|writes a file that is not JSON" \
            "printf '[1]' > \"\$SELVEDGE_STORAGE_STATE\"|writes JSON that is not an object" \
            "printf '{}' > '$TMP/target.json'; ln -s '$TMP/target.json' \"\$SELVEDGE_STORAGE_STATE\"|leaves a symlink" \
            "printf '{}' > \"\$SELVEDGE_STORAGE_STATE\"; exit 7|exits 7"; do
  hook="${spec%%|*}"; what="${spec#*|}"
  W="$TMP/r-write-$((pass + fail))"; mkrepo "$W"
  cfg "$W/selvedge.json" "$hook" '{"env":["APP_USER","APP_PASS"]}'
  approve_hook "$(cd "$W" && pwd -P)" "$hook"
  out="$(cd "$W" && APP_USER="$USER_VALUE" APP_PASS="$PASS_VALUE" bash "$CLI" auth setup 2>"$TMP/stderr" </dev/null)"; rc=$?; err="$(cat "$TMP/stderr")"
  sd="$(dirname "$(state_file "$W")")"
  left="$(find "$sd" ! -type d 2>/dev/null | wc -l | tr -d ' ')"
  { [ "$rc" -eq 1 ] && [ ! -e "$(state_file "$W")" ] && [ "$left" = "0" ]; } \
    && ok "AC4 a hook that $what: exit 1, no state file, nothing left in the state directory" || ko "AC4 hook that $what: rc=$rc left=$left err='$err'"
done
N="$TMP/r-nohook"; mkrepo "$N"
cfg "$N/selvedge.json" "" '{"env":["APP_USER"]}'
run "$N" auth setup
{ [ "$rc" -eq 2 ] && grep -qF -- '--headed' <<<"$err" && grep -qF 'hooks.auth_setup' <<<"$err" && [ -z "$out" ]; } \
  && ok "AC4 no auth_setup hook and no --headed: usage error (exit 2) naming --headed and hooks.auth_setup" || ko "AC4 no hook: rc=$rc out='$out' err='$err'"
run "$N" auth
[ "$rc" -eq 2 ] && ok "'selvedge auth' with no command is a usage error (exit 2)" || ko "bare auth: rc=$rc"
run "$N" auth setup --nope
[ "$rc" -eq 2 ] && ok "an unknown auth setup option is a usage error (exit 2)" || ko "unknown option: rc=$rc"

echo "-- AC10 auth setup --headed against the stub Playwright"
H="$TMP/r-headed"; mkrepo "$H"
cfg "$H/selvedge.json" "" "$CHECK_OK"
OPTS="$TMP/opts-h.log"; COUNTS="$TMP/counts.json"
printf '{}' > "$COUNTS"
headed() { # headed <repo> <timeout ms> → runs auth setup --headed in the foreground
  out="$(cd "$1" && SELVEDGE_PLAYWRIGHT_MODULE="$STUB_PW" STUB_PW_OPTS_LOG="$OPTS" STUB_PW_COUNTS_FILE="$COUNTS" SELVEDGE_AUTH_TIMEOUT_MS="$2" \
    bash "$CLI" auth setup --headed 2>"$TMP/stderr" </dev/null)"; rc=$?; err="$(cat "$TMP/stderr")"
}
rm -f "$OPTS"; headed "$H" 20000
HF="$(state_file "$H")"
{ [ "$rc" -eq 0 ] && [ -f "$HF" ] && grep -qF "$HF" <<<"$out"; } && ok "AC10 --headed exits 0 and writes the context's storage state to the state path" || ko "AC10 headed: rc=$rc out='$out' err='$err'"
out="$(node -e 'const fs = require("fs"); const lines = fs.readFileSync(process.argv[1], "utf8").trim().split("\n");
const launch = JSON.parse(lines.find((l) => l.startsWith("launch ")).slice(7));
const ctx = lines.find((l) => l.startsWith("newContext ")).slice(11);
console.log(JSON.stringify([launch.headless, Object.keys(launch).sort().join(), /^http:\/\/127\.0\.0\.1:\d+$/.test(launch.proxy.server), ctx, lines.filter((l) => l === "storageState").length]));' "$OPTS" 2>&1)"
[ "$out" = '[false,"headless,proxy",true,"{\"serviceWorkers\":\"block\"}",1]' ] \
  && ok "AC10 the launch receives headless: false beside the guard's proxy, the context is exactly { serviceWorkers: 'block' }, storageState read once" || ko "AC10 options: $out"
[ "$(file_mode "$HF")" = "600" ] && [ "$(file_mode "$(dirname "$HF")")" = "700" ] && ok "AC10 the headed state file is 0600 in a 0700 directory" || ko "AC10 modes: file $(file_mode "$HF") dir $(file_mode "$(dirname "$HF")")"
out="$(node --input-type=module -e "import { STUB_STATE } from '$STUB_PW'; import fs from 'node:fs'; console.log(JSON.stringify(JSON.parse(fs.readFileSync(process.argv[1], 'utf8'))) === JSON.stringify(STUB_STATE));" "$HF" 2>&1)"
[ "$out" = "true" ] && ok "AC10 the file holds exactly what context.storageState() returned" || ko "AC10 content: $out"
# it waits for the locator: count 0 → nothing written yet; count 1 → written
rm -f "$HF"; printf '{"role:heading:Account":0}' > "$COUNTS"
( cd "$H" && SELVEDGE_PLAYWRIGHT_MODULE="$STUB_PW" STUB_PW_COUNTS_FILE="$COUNTS" SELVEDGE_AUTH_TIMEOUT_MS=30000 \
    bash "$CLI" auth setup --headed >"$TMP/bg.out" 2>"$TMP/bg.err" </dev/null; echo "rc=$?" > "$TMP/bg.rc" ) &
bg=$!
sleep 2
{ [ ! -e "$HF" ] && [ ! -e "$TMP/bg.rc" ]; } && ok "AC10 while the locator matches nothing, it keeps waiting and writes nothing" || ko "AC10 wrote before the locator matched: $(cat "$TMP/bg.rc" 2>/dev/null) err='$(cat "$TMP/bg.err")'"
printf '{"role:heading:Account":1}' > "$COUNTS"
i=0; while [ ! -e "$TMP/bg.rc" ] && [ "$i" -lt 100 ]; do sleep 0.2; i=$((i + 1)); done
wait "$bg" 2>/dev/null
{ [ "$(cat "$TMP/bg.rc" 2>/dev/null)" = "rc=0" ] && [ -f "$HF" ]; } && ok "AC10 once the locator matches, it saves the state and exits 0" || ko "AC10 after match: $(cat "$TMP/bg.rc" 2>/dev/null) err='$(cat "$TMP/bg.err")'"
rm -f "$HF"; printf '{"role:heading:Account":0}' > "$COUNTS"
headed "$H" 400
{ [ "$rc" -eq 1 ] && [ ! -e "$HF" ] && grep -qF 'SELVEDGE_AUTH_TIMEOUT_MS' <<<"$err"; } && ok "AC10 the locator never matching: exit 1 after SELVEDGE_AUTH_TIMEOUT_MS, nothing written" || ko "AC10 timeout: rc=$rc err='$err'"
headed "$H" abc
[ "$rc" -eq 2 ] && ok "AC10 a SELVEDGE_AUTH_TIMEOUT_MS that is not a positive number is a usage error" || ko "AC10 bad timeout: rc=$rc"
printf '{}' > "$COUNTS"
NC="$TMP/r-nocheck"; mkrepo "$NC"
cfg "$NC/selvedge.json" "true" '{"env":["APP_USER"]}'
LOG="$TMP/pw-nocheck.log"
out="$(cd "$NC" && SELVEDGE_PLAYWRIGHT_MODULE="$STUB_PW" STUB_PW_LOG="$LOG" bash "$CLI" auth setup --headed 2>"$TMP/stderr" </dev/null)"; rc=$?; err="$(cat "$TMP/stderr")"
{ [ "$rc" -eq 2 ] && grep -qF 'auth.signed_in_check' <<<"$err" && [ ! -e "$LOG" ]; } \
  && ok "AC10 --headed without auth.signed_in_check: usage error (exit 2) naming it, nothing launched" || ko "AC10 no check: rc=$rc err='$err'"

echo "-- AC10 the guarded-browser options (route-guard.mjs)"
out="$(node_eval '
const plain = G.buildLaunchOptions({ proxyPort: 4242 });
const off = G.buildLaunchOptions({ proxyPort: 4242, headed: false });
const on = G.buildLaunchOptions({ proxyPort: 4242, headed: true });
console.log(JSON.stringify([plain, off, on]));' 2>&1)"
[ "$out" = '[{"proxy":{"server":"http://127.0.0.1:4242"}},{"proxy":{"server":"http://127.0.0.1:4242"}},{"proxy":{"server":"http://127.0.0.1:4242"},"headless":false}]' ] \
  && ok "AC10 buildLaunchOptions is exactly { proxy } unless headed, which adds only headless: false" || ko "AC10 buildLaunchOptions: $out"
out="$(node_eval '
const { chromium } = await import(process.env.STUB_PW_MODULE);
const calls = [];
const spy = { launch: async (o) => { calls.push("launch " + JSON.stringify(o)); const b = await chromium.launch(o); return { ...b, newContext: async (c) => { calls.push("newContext " + JSON.stringify(c)); return b.newContext(c); } }; } };
const cfg = E.validateConfig({ schema_version: 1, origins: ["http://localhost:3000"] });
for (const opts of [{}, { storageState: "/x/storageState.json" }, { storageState: null }]) { const g = await G.openGuardedContext({ chromium: spy, config: cfg, ...opts }); await g.close(); }
let refused = false; try { await G.openGuardedContext({ chromium: spy, config: cfg, storageState: 42 }); } catch (e) { refused = e instanceof TypeError; }
console.log(JSON.stringify([calls.filter((c) => c.startsWith("newContext")), calls.filter((c) => c.startsWith("launch")).every((c) => !c.includes("headless")), refused]));' 2>&1)"
[ "$out" = '[["newContext {\"serviceWorkers\":\"block\"}","newContext {\"serviceWorkers\":\"block\",\"storageState\":\"/x/storageState.json\"}","newContext {\"serviceWorkers\":\"block\"}"],true,true]' ] \
  && ok "AC10 openGuardedContext passes storageState to newContext only when a path is given (no undefined key), and is never headed by default" || ko "AC10 openGuardedContext: $out"

echo "test-auth: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
