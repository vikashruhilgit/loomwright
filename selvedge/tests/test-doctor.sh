#!/usr/bin/env bash
# test-doctor.sh — pins `selvedge doctor` (bin/selvedge's Node pre-check + lib/doctor.mjs): with every
# prerequisite present it prints one `ok <check>` line per check and exits 0; removing each one at a
# time prints that check's `FAIL <check>: <fix>` line with its fix literal and exits 1:
#   Node absent or older than 18   install Node.js >= 18  (+ `skipped: the other checks need Node`)
#   Playwright library missing     npm i -D playwright
#   Chromium browser missing       npx playwright install chromium (also when executablePath() is
#                                  empty or throws)
#   selvedge.json absent / invalid selvedge env init --port
#   hooks not approved             selvedge env approve
#   no planner                     or set SELVEDGE_PLANNER
#
# Hermetic: a temp HOME, a temp git repo, a stub Playwright (SELVEDGE_PLAYWRIGHT_MODULE, or a stub
# `playwright` package in the repo's node_modules) whose chromium.executablePath() is $STUB_EXE (or
# throws $STUB_THROW when set), and
# every doctor run under `env -i` with a PATH built here (only the tools it needs; no `claude` unless
# a case adds a stub one, no `node` in the Node-absent cases). Nothing outside $TMP is read or written.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$TESTS_DIR/.." && pwd)"
CLI="$PLUGIN_DIR/bin/selvedge"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "  ok   $1"; }
ko() { fail=$((fail + 1)); echo "  FAIL $1"; }

if ! command -v node >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  echo "  SKIP node or git is not on PATH (doctor's Node checks need both)"
  echo "test-doctor: 0 passed, 0 failed (skipped)"
  exit 0
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/selvedge-doctor.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"

# PATH dirs: the userland bin/selvedge and doctor use, with and without node.
BIN_BASE="$TMP/bin-base"; BIN_NODE="$TMP/bin-node"; BIN_OLDNODE="$TMP/bin-oldnode"; BIN_CLAUDE="$TMP/bin-claude"
mkdir -p "$BIN_BASE" "$BIN_NODE" "$BIN_OLDNODE" "$BIN_CLAUDE"
for t in git dirname basename readlink grep head sed cat; do
  p="$(command -v "$t")" || { echo "setup: $t not found"; exit 1; }
  ln -s "$p" "$BIN_BASE/$t"
done
ln -s "$(command -v node)" "$BIN_NODE/node"
# An old Node: answers `node -p process.versions.node` with 16.20.2 and runs nothing else.
printf '#!/bin/sh\necho 16.20.2\n' > "$BIN_OLDNODE/node"; chmod +x "$BIN_OLDNODE/node"
printf '#!/bin/sh\nexit 0\n' > "$BIN_CLAUDE/claude"; chmod +x "$BIN_CLAUDE/claude"
PATH_OK="$BIN_NODE:$BIN_BASE"

# The stub Playwright: chromium.launch exists (resolvePlaywright needs it); executablePath() is $STUB_EXE.
STUB_PW="$TMP/stub-pw/index.mjs"
mkdir -p "$TMP/stub-pw"
cat > "$STUB_PW" <<'EOF'
export const chromium = {
  launch: async () => { throw new Error('stub playwright: no browser here'); },
  executablePath: () => {
    if (process.env.STUB_THROW) throw new Error(process.env.STUB_THROW);
    return process.env.STUB_EXE || '';
  },
};
EOF
STUB_EXE="$TMP/fake-chromium"
: > "$STUB_EXE"

REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
CFG_OK='{"schema_version": 1, "origins": ["http://localhost:4173"], "allow_remote": false, "allow_remote_mutation": false}'
CFG_HOOKS='{"schema_version": 1, "origins": ["http://localhost:4173"], "allow_remote": false, "allow_remote_mutation": false, "hooks": {"seed": "echo seeded"}}'
printf '%s\n' "$CFG_OK" > "$REPO/selvedge.json"

# doctor [VAR=value…] — run `selvedge doctor` in $REPO under env -i; sets OUT and RC. Defaults (all
# present): PATH=$PATH_OK, the stub Playwright, STUB_EXE existing, SELVEDGE_PLANNER set. A later
# VAR=value overrides an earlier one (env applies them in order).
doctor() {
  OUT="$(cd "$REPO" && env -i HOME="$HOME" PATH="$PATH_OK" SELVEDGE_PLAYWRIGHT_MODULE="$STUB_PW" \
    STUB_EXE="$STUB_EXE" SELVEDGE_PLANNER="true" "$@" "$BASH" "$CLI" doctor 2>&1)"
  RC=$?
}
has() { grep -qF -- "$1" <<<"$OUT"; }
line_of() { grep -E "^(ok|FAIL) $1" <<<"$OUT" | head -n 1; }

# --- all present -------------------------------------------------------------------------------
doctor
nok="$(grep -c '^ok ' <<<"$OUT")"
{ [ "$RC" -eq 0 ] && [ "$nok" -eq 6 ] && ! has "FAIL"; } \
  && ok "all present: six ok lines, no FAIL, exit 0" || ko "all present: rc=$RC out='$OUT'"
for c in "Node >= 18" "Playwright library" "Chromium browser" "selvedge.json" "hook approvals" "planner"; do
  [ -n "$(line_of "$c")" ] || ko "all present: no line for $c: '$OUT'"
done
has "ok hook approvals (no hooks)" && ok "no hooks in selvedge.json reads 'no hooks'" || ko "no-hooks line: '$OUT'"
[ "$(wc -l <<<"$OUT" | tr -d ' ')" = "6" ] && ok "exactly one line per check" || ko "line count: '$OUT'"

# --- Node absent / too old (bash, before any .mjs loads) ----------------------------------------
doctor PATH="$BIN_BASE"
{ [ "$RC" -eq 1 ] && grep -qE '^FAIL Node >= 18: .*install Node\.js >= 18' <<<"$OUT"; } \
  && ok "Node absent: FAIL Node >= 18 with 'install Node.js >= 18', exit 1" || ko "Node absent: rc=$RC out='$OUT'"
{ has "skipped: the other checks need Node" && [ "$(wc -l <<<"$OUT" | tr -d ' ')" = "2" ]; } \
  && ok "Node absent: one 'skipped: the other checks need Node' line, no per-check lines" || ko "Node absent skipped line: '$OUT'"
has "node not found" && ok "Node absent: says node was not found" || ko "Node absent detail: '$OUT'"
doctor PATH="$BIN_OLDNODE:$BIN_BASE"
{ [ "$RC" -eq 1 ] && has "install Node.js >= 18" && has "found 16.20.2" && has "skipped: the other checks need Node"; } \
  && ok "Node 16: FAIL naming the version found, exit 1" || ko "old Node: rc=$RC out='$OUT'"

# --- Playwright library -------------------------------------------------------------------------
doctor SELVEDGE_PLAYWRIGHT_MODULE=
l="$(line_of "Playwright library")"
{ [ "$RC" -eq 1 ] && grep -qF "FAIL Playwright library: " <<<"$l" && grep -qF "npm i -D playwright" <<<"$l"; } \
  && ok "Playwright missing: FAIL Playwright library with 'npm i -D playwright', exit 1" || ko "Playwright missing: rc=$RC out='$OUT'"
grep -qE '^FAIL Chromium browser: npx playwright install chromium \(after the Playwright library' <<<"$OUT" \
  && ok "Playwright missing: the browser line says to install the library first" || ko "browser line without a library: '$OUT'"
doctor SELVEDGE_PLAYWRIGHT_MODULE="$TMP/no-such/index.mjs"
l="$(line_of "Playwright library")"
{ [ "$RC" -eq 1 ] && grep -qF "SELVEDGE_PLAYWRIGHT_MODULE does not load" <<<"$l" && grep -qF "npm i -D playwright" <<<"$l"; } \
  && ok "a SELVEDGE_PLAYWRIGHT_MODULE that does not load is a FAIL naming it (no fall-back)" || ko "bad module: rc=$RC out='$OUT'"
# Found from the repo's own node_modules, as `run` finds it.
mkdir -p "$REPO/node_modules/playwright"
printf '{"name": "playwright", "version": "9.9.9", "main": "index.js"}\n' > "$REPO/node_modules/playwright/package.json"
printf 'exports.chromium = { launch: async () => { throw new Error("stub"); }, executablePath: () => process.env.STUB_EXE || "" };\n' \
  > "$REPO/node_modules/playwright/index.js"
doctor SELVEDGE_PLAYWRIGHT_MODULE=
{ [ "$RC" -eq 0 ] && has "ok Playwright library (9.9.9, from this repo)"; } \
  && ok "Playwright in the repo's node_modules (no SELVEDGE_PLAYWRIGHT_MODULE): ok, from this repo" || ko "repo Playwright: rc=$RC out='$OUT'"
rm -rf "$REPO/node_modules"

# --- Chromium browser ---------------------------------------------------------------------------
doctor STUB_EXE="$TMP/no-such-chromium"
l="$(line_of "Chromium browser")"
{ [ "$RC" -eq 1 ] && grep -qF "FAIL Chromium browser: " <<<"$l" && grep -qF "npx playwright install chromium" <<<"$l" \
  && has "ok Playwright library"; } \
  && ok "browser missing: FAIL Chromium browser with 'npx playwright install chromium', exit 1" || ko "browser missing: rc=$RC out='$OUT'"

doctor STUB_EXE=
{ [ "$RC" -eq 1 ] && grep -qE '^FAIL Chromium browser: npx playwright install chromium \(this Playwright reports no browser path' <<<"$OUT"; } \
  && ok "a Playwright that reports no browser path: FAIL Chromium browser, exit 1" || ko "no browser path: rc=$RC out='$OUT'"

doctor STUB_THROW="stub: no browser for this platform"
{ [ "$RC" -eq 1 ] && grep -qE '^FAIL Chromium browser: npx playwright install chromium \(this Playwright reports no browser path: stub: no browser for this platform\)$' <<<"$OUT"; } \
  && ok "a Playwright whose executablePath() throws: FAIL Chromium browser naming the error, exit 1" || ko "executablePath throws: rc=$RC out='$OUT'"

# --- selvedge.json ------------------------------------------------------------------------------
rm "$REPO/selvedge.json"
doctor
l="$(line_of "selvedge.json")"
{ [ "$RC" -eq 1 ] && grep -qF "FAIL selvedge.json: " <<<"$l" && grep -qF "selvedge env init --port" <<<"$l"; } \
  && ok "no selvedge.json: FAIL selvedge.json with 'selvedge env init --port', exit 1" || ko "no selvedge.json: rc=$RC out='$OUT'"
has "ok hook approvals (no hooks: no valid selvedge.json yet)" \
  && ok "no selvedge.json: hook approvals reads 'no hooks: no valid selvedge.json yet'" || ko "approvals without a config: '$OUT'"
printf '{\n' > "$REPO/selvedge.json"
doctor
l="$(line_of "selvedge.json")"
{ [ "$RC" -eq 1 ] && grep -qF "config_invalid_json" <<<"$l" && grep -qF "selvedge env init --port" <<<"$l"; } \
  && ok "an invalid selvedge.json: FAIL naming config_invalid_json, exit 1" || ko "invalid selvedge.json: rc=$RC out='$OUT'"
printf '%s\n' "$CFG_OK" > "$REPO/selvedge.json"

# --- hook approvals -----------------------------------------------------------------------------
printf '%s\n' "$CFG_HOOKS" > "$REPO/selvedge.json"
doctor
l="$(line_of "hook approvals")"
{ [ "$RC" -eq 1 ] && grep -qF "FAIL hook approvals: " <<<"$l" && grep -qF "selvedge env approve" <<<"$l"; } \
  && ok "unapproved hooks: FAIL hook approvals with 'selvedge env approve', exit 1" || ko "unapproved hooks: rc=$RC out='$OUT'"
# Approved: the approvals file env approve writes, built with the same helpers (identity, sha256).
SELVEDGE_LIB="$PLUGIN_DIR/lib" REPO="$REPO" HOME="$HOME" node --input-type=module -e '
import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
const a = await import(pathToFileURL(path.join(process.env.SELVEDGE_LIB, "env-approvals.mjs")).href);
const file = a.approvalsPath(process.env);
mkdirSync(path.dirname(file), { recursive: true });
const approvals = { [a.repoIdentity(process.env.REPO)]: { hooks_sha256: a.hooksSha256({ seed: "echo seeded" }) } };
writeFileSync(file, JSON.stringify({ approvals }));
' || ko "setup: could not write the approvals file"
doctor
{ [ "$RC" -eq 0 ] && has "ok hook approvals (approved)"; } \
  && ok "approved hooks: ok hook approvals (approved), exit 0" || ko "approved hooks: rc=$RC out='$OUT'"
rm -rf "$HOME/.claude"
printf '%s\n' "$CFG_OK" > "$REPO/selvedge.json"

# --- planner ------------------------------------------------------------------------------------
doctor SELVEDGE_PLANNER=
l="$(line_of "planner")"
{ [ "$RC" -eq 1 ] && grep -qF "FAIL planner: " <<<"$l" && grep -qF "or set SELVEDGE_PLANNER" <<<"$l"; } \
  && ok "no planner (no claude on PATH, SELVEDGE_PLANNER unset): FAIL planner with 'or set SELVEDGE_PLANNER', exit 1" \
  || ko "no planner: rc=$RC out='$OUT'"
doctor SELVEDGE_PLANNER="   "
{ [ "$RC" -eq 1 ] && has "FAIL planner: "; } \
  && ok "a blank SELVEDGE_PLANNER counts as unset (as plan treats it): FAIL planner" || ko "blank planner: rc=$RC out='$OUT'"
doctor SELVEDGE_PLANNER= PATH="$BIN_CLAUDE:$PATH_OK"
{ [ "$RC" -eq 0 ] && grep -qE '^ok planner \(claude at .*/bin-claude/claude\)$' <<<"$OUT"; } \
  && ok "claude on PATH: ok planner" || ko "claude on PATH: rc=$RC out='$OUT'"

# --- usage --------------------------------------------------------------------------------------
OUT="$(cd "$REPO" && env -i HOME="$HOME" PATH="$PATH_OK" "$BASH" "$CLI" doctor --bogus 2>&1)"; RC=$?
[ "$RC" -eq 2 ] && ok "doctor with an argument is a usage error (exit 2)" || ko "doctor --bogus: rc=$RC out='$OUT'"

echo "test-doctor: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
