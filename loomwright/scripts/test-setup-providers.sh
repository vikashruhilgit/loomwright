#!/usr/bin/env bash
# test-setup-providers.sh — stub-backed self-tests for setup-providers.sh
# `check`. Fake CLIs on PATH plus a temp providers dir (LOOMWRIGHT_PROVIDERS_DIR)
# drive every case, the convention test-lens-run.sh uses; the real provider
# dir is only READ (case T, the table contract), never written, so a
# concurrent test-lens-run.sh / test-lens-compare.sh cannot collide with it.
#
# Every engine run gets a temp HOME (holding a fake tool config tree), its own
# TMPDIR, and the fake CLIs first on PATH. Each fake CLI is baked at generation
# time and records what it saw (smoke ran, cwd, HOME, prompt, pids) under this
# run's $TMP/marks — never a machine-wide name match.
#
# Covers:
#   W. write-containment (AC3): repo `git status --porcelain` before = after
#      (a concurrent test-lens-run.sh's transient teststub file excluded),
#      the temp HOME tree (incl. its tool config tree) byte-identical, the
#      engine's own scratch dir gone (its TMPDIR is empty again), exit 0
#   A. absent binary -> `installed: no`, install hint, `not usable: installed`
#   P. installed + auth ok + headless pass + pin tokens advertised + the
#      permission probe REFUSED (no file in its cwd) -> `permissions pinnable`,
#      browser yes, `usable for write seats`; the probe ran isolated, from an
#      empty throwaway cwd under the engine's scratch dir (removed after), with
#      the fixed write-request prompt LAST
#   Q. permission probe (AC5): a CLI that IGNORES its pin flags and writes the
#      file -> `permissions: unpinnable (pin flags not enforced)`, never write
#      seats; tokens advertised but no probe_perm_argv, or a failing smoke (the
#      probe is then NOT run), or a probe that exits non-zero with no file, or
#      one that timed out (case H) ->
#      `permissions: pin flags advertised (unverified)`, never write seats
#   I. login isolation (AC1/AC2 check half): a CLI that works only when
#      $HOME/.fake/auth.json exists -> declared as its login file: `auth ok`,
#      `=> usable for …` (auth command and smoke-only providers alike); NOT
#      declared: `auth: not_logged_in_isolated (ok in your shell)`, a `fix:`
#      line naming the declared login env vars, `=> not usable: auth` (the
#      auth-command provider's smoke is not run; the smoke-only provider's
#      isolated smoke ran, then one diagnosis smoke under the real HOME)
#   R. pin token missing from --help -> `permissions: unpinnable`, browser no,
#      `usable for read-only seats`; pin tokens present only as prefixes of
#      longer flags (`--allow-all`, `--deny-x` for `--allow --deny`) ->
#      `permissions: unpinnable` (whole-token match, never substring)
#   X. declared `none` (lone auto-approve flag in --help) -> unpinnable, never
#      write seats
#   U. no pin flags declared -> `permissions: unknown`, browser unknown
#   N. auth not_logged_in (in the shell too) -> login hint, `headless: not
#      run`, smoke NOT run, `not usable: auth`, never not_logged_in_isolated
#   K. auth output unrecognised + garbage smoke -> `auth: unknown`,
#      `headless: fail:unparseable`, `not usable: auth`, login hint QUALIFIED
#      (`login (only if not logged in):`)
#   G. auth ok + garbage smoke, or a well-formed envelope carrying the wrong
#      reply -> `headless: fail:unparseable`, `not usable: headless`; the
#      fixed reply inside a markdown code fence still passes
#   S. no auth command + passing smoke -> `auth ok (via smoke)`
#   O. no ok-pattern -> auth decided by the auth command's exit 0; a failing
#      version command -> `installed (version unknown)`; empty help output ->
#      `permissions: unknown`
#   L. no auth command + smoke failing with the not-logged-in wording ->
#      `auth: not_logged_in (via smoke)`, `headless: fail:exit1`; the smoke DID
#      run (AC6's "smoke not run" covers only auth-command providers, case N)
#   F. no auth command + smoke failing another way -> `auth: unknown (smoke
#      failed: unparseable)`, `not usable: auth`, login hint qualified
#   C. smoke context (AC10): cwd a throwaway dir under the engine's TMPDIR
#      (never the repo) and removed after, HOME = an isolated per-call HOME
#      under the engine's TMPDIR (NOT the HOME the engine got) and removed
#      after, prompt = the fixed probe string
#   Z. provider files with no probe entries (a lens-only teststub) or a name
#      outside the allowlist are skipped: never reported, their CLI never run
#   H. hung smoke (TERM ignored) + timeout 2 -> `headless: fail:timeout`, the
#      stub's recorded pid/pgid/child are gone, the run ends well before the
#      stub's own 30s sleep (so the KILL step fired), exit 0; a hung permission
#      probe -> `permissions: pin flags advertised (unverified)`
#   J. jq unavailable -> `headless: not run (jq not found)`, exit 0; a provider
#      with no auth command -> `auth: unknown (smoke not run)`; invalid
#      timeout values fall back to the defaults
#   E. usage errors (no subcommand / extra arg) -> exit 64
#   T. table contract (AC13): every real provider-<name>.sh (test-only
#      teststub files excluded) keeps the lens contract and declares the probe
#      entries; both argv builders (and probe_perm_argv where defined) put the
#      prompt LAST
#   V. setup-providers.sh names no provider's CLI or table name (AC15), read
#      from the real table files rather than a restated list
#
# Exit 0 = all pass, 1 = any failure.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$HERE/setup-providers.sh"
REAL_PDIR="$HERE/adapters/providers"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }
has() { # has <label> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then ok "$1"; else no "$1 (missing [$3] in [$2])"; fi
}
lacks() { # lacks <label> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then no "$1 (unexpected [$3] in [$2])"; else ok "$1"; fi
}
assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (expected [$2] got [$3])"; fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "test-setup-providers.sh: jq is required"; echo "RESULT: 0 passed, 1 failed"; exit 1
fi
if [ ! -f "$ENGINE" ]; then
  echo "test-setup-providers.sh: $ENGINE not found"; echo "RESULT: 0 passed, 1 failed"; exit 1
fi

TMP="$(mktemp -d)"
RUN_TAG="$$"
cleanup() {
  # A hung-smoke stub left behind by an interrupted case H: kill only the pids
  # this run recorded, and only while they still sit in the recorded group (a
  # recycled pid is never touched).
  local p pid g
  g="$(cat "$TMP/marks/hang.pgid" 2>/dev/null)"
  for p in "$TMP/marks/hang.pid" "$TMP/marks/hang.child"; do
    [ -f "$p" ] && [ -n "$g" ] || continue
    pid="$(cat "$p" 2>/dev/null)"
    [ -n "$pid" ] || continue
    [ "$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')" = "$g" ] && kill -9 "$pid" 2>/dev/null
  done
  rm -rf "$TMP"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

BIN="$TMP/bin"; PDIR="$TMP/providers"; MARK="$TMP/marks"; THOME="$TMP/home"; ETMP="$TMP/engine-tmp"
mkdir -p "$BIN" "$PDIR" "$MARK" "$THOME" "$ETMP"
# A fake tool config tree inside the temp HOME; it must be byte-identical after.
CFG="$THOME/.claude"
mkdir -p "$CFG"
printf '{"fixture":true}\n' > "$CFG/settings.json"
printf 'keep\n' > "$THOME/.profile-fixture"
# The fake login the I-case CLIs need (they read only its existence).
mkdir -p "$THOME/.fake"
printf '{"fixture-login":true}\n' > "$THOME/.fake/auth.json"
LOGIN_REL=".fake/auth.json"
PERM_PROMPT='Create a file named probe.txt in the current directory containing the single word loomwright. Use your file-writing tool and do not ask for confirmation. Then reply with one short sentence saying whether the file was written.'

cli_of() { printf 'lwprobe%s-%s' "$RUN_TAG" "$1"; }

# make_stub <name> <auth-output> <help-text> <smoke-mode> [<perm-mode>] [<login-rel>]
# perm-mode (the `--perm-probe` call): refuse (answers, writes nothing) | write
# (writes probe.txt into its cwd, then answers) | hang | fail (exit 3, no file). login-rel: when set, the
# CLI is logged in only while $HOME/<login-rel> exists (else its auth-check and
# smoke print the not-logged-in wording) — the per-run fake of a login file.
make_stub() {
  local cli; cli="$(cli_of "$1")"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'CLI=%q\nAUTH_OUT=%q\nHELP_TEXT=%q\nSMOKE=%q\nMARK=%q\nPERM=%q\nLOGIN_REL=%q\n' \
      "$1" "$2" "$3" "$4" "$MARK" "${5:-refuse}" "${6:-}"
    cat <<'STUB'
LOGGED=1
[ -n "$LOGIN_REL" ] && [ ! -f "$HOME/$LOGIN_REL" ] && LOGGED=0
case "${1:-}" in
  --version)  [ "$HELP_TEXT" = "__silent__" ] && exit 1; printf '9.9.9-%s\n' "$CLI"; exit 0 ;;
  auth-check) if [ "$LOGGED" = 1 ]; then printf '%s\n' "$AUTH_OUT"; else printf 'NOT-LOGGED-IN\n'; fi; exit 0 ;;
  --help)     [ "$HELP_TEXT" = "__silent__" ] && exit 0; printf '%s\n' "$HELP_TEXT"; exit 0 ;;
  --perm-probe)
    : > "$MARK/$CLI.perm-ran"
    pwd -P > "$MARK/$CLI.perm-cwd"
    printf '%s' "$HOME" > "$MARK/$CLI.perm-home"
    printf '%s' "${@: -1}" > "$MARK/$CLI.perm-prompt"
    case "$PERM" in
      write) printf 'loomwright\n' > probe.txt; printf '%s\n' '{"result":"Done: probe.txt written."}' ;;
      hang)  sleep 30 ;;
      fail)  printf 'Error: tool backend unavailable\n' >&2; exit 3 ;;
      *)     printf '%s\n' '{"result":"I was not permitted to write the file."}' ;;
    esac
    exit 0 ;;
  -p)         : ;;
  *)          : > "$MARK/$CLI.unexpected"; exit 2 ;;
esac
if [ -e "$MARK/$CLI.smoke-ran" ]; then : > "$MARK/$CLI.smoke-ran2"; fi
: > "$MARK/$CLI.smoke-ran"
[ "$LOGGED" = 1 ] || { printf 'Error: NOT-LOGGED-IN, please log in\n' >&2; exit 1; }
pwd -P > "$MARK/$CLI.smoke-cwd"
printf '%s' "$HOME" > "$MARK/$CLI.smoke-home"
printf '%s' "${@: -1}" > "$MARK/$CLI.smoke-prompt"
case "$SMOKE" in
  pass)      printf '%s\n' '{"result":"{\"probe\":\"loomwright-ok\"}"}' ;;
  garbage)   printf 'this is not json {{{\n' ;;
  wrongreply) printf '%s\n' '{"result":"{\"probe\":\"something-else\"}"}' ;;
  fenced)    printf '%s\n' '{"result":"```json\n{\"probe\":\"loomwright-ok\"}\n```"}' ;;
  notlogged) printf 'Error: NOT-LOGGED-IN, please log in\n' >&2; exit 1 ;;
  hang)
    printf '%s\n' "$$" > "$MARK/$CLI.pid"
    ps -o pgid= -p $$ | tr -d ' ' > "$MARK/$CLI.pgid"
    trap '' TERM
    sleep 30 &
    printf '%s\n' "$!" > "$MARK/$CLI.child"
    wait
    ;;
esac
exit 0
STUB
  } > "$BIN/$cli"
  chmod +x "$BIN/$cli"
}

# write_provider <dir> <name> <auth: cmd|none> <pin-flags> <browser> [<auth-ok-re>]
write_provider() {
  local dir="$1" name="$2" authmode="$3" pins="$4" browser="$5" okre="${6-LOGGED-IN-OK}"
  {
    printf '#!/usr/bin/env bash\n# TEST-ONLY provider-table entry written by test-setup-providers.sh.\n'
    printf 'PROVIDER_CLI_NAME=%q\n' "$(cli_of "$name")"
    cat <<'P'
PROVIDER_WORKSPACE_FLAG=0
PROVIDER_HOME_SCRUB=1
provider_build_argv() { PROVIDER_ARGV=("-p" "$PROMPT_CONTENT"); }
provider_extract_text() {
  PROVIDER_EXTRACTED=""
  [ -s "$1" ] || return 1
  "$JQ" -e 'type == "object"' "$1" >/dev/null 2>&1 || return 1
  PROVIDER_EXTRACTED="$("$JQ" -r '.result // empty' "$1" 2>/dev/null)"
  [ -n "$PROVIDER_EXTRACTED" ]
}
PROBE_VERSION_ARGV=("--version")
PROBE_AUTH_NOT_LOGGED_IN_RE='NOT-LOGGED-IN'
PROBE_HELP_ARGV=("--help")
probe_smoke_argv() { PROBE_ARGV=("-p" "$PROBE_PROMPT"); }
P
    printf 'PROBE_AUTH_OK_RE=%q\n' "$okre"
    if [ "$authmode" = "cmd" ]; then printf 'PROBE_AUTH_ARGV=("auth-check")\n'; else printf 'PROBE_AUTH_ARGV=()\n'; fi
    printf 'PROBE_PERM_PIN_FLAGS=%q\nPROBE_BROWSER=%q\n' "$pins" "$browser"
    printf 'PROBE_INSTALL_HINT=%q\nPROBE_LOGIN_HINT=%q\n' "install-hint-$name" "login-hint-$name"
  } > "$dir/provider-$name.sh"
}

# add_perm_probe <dir> <name> — give a provider file a probe_perm_argv.
add_perm_probe() {
  printf '%s\n' 'probe_perm_argv() { PROBE_ARGV=("--perm-probe" "$PROBE_PROMPT"); }' >> "$1/provider-$2.sh"
}
# add_login <dir> <name> — declare the fake login file (and a login env var name).
add_login() {
  printf 'PROVIDER_LOGIN_FILES=(%q)\n' "$LOGIN_REL" >> "$1/provider-$2.sh"
}
# add_login_env <dir> <name> — declare only a login env var NAME (never set here).
add_login_env() {
  printf 'PROVIDER_LOGIN_ENV=("LWPROBE_FAKE_API_KEY")\n' >> "$1/provider-$2.sh"
}

# run_check <outfile> [ENV=VAL ...] — the engine under the temp HOME/TMPDIR,
# fake CLIs first on PATH. Prints the engine's exit status.
run_check() {
  local out="$1"; shift
  env HOME="$THOME" TMPDIR="$ETMP" PATH="$BIN:$PATH" \
    LOOMWRIGHT_PROVIDERS_DIR="$PDIR" \
    LOOMWRIGHT_PROVIDER_SMOKE_TIMEOUT=20 LOOMWRIGHT_PROVIDER_QUICK_TIMEOUT=10 \
    "$@" bash "$ENGINE" check > "$out" 2>"$out.err" </dev/null
  echo $?
}

row_args() { # row_args <outfile> <name> — the provider's row line
  grep -F -- "$2 ($(cli_of "$2")): " "$1" 2>/dev/null | head -1
}
hint_of() { # hint_of <outfile> <name> — the indented line right after the row
  awk -v p="$2 ($(cli_of "$2")): " 'f { print; exit } index($0, p) == 1 { f = 1 }' "$1"
}
# repo_status — the repo's `git status --porcelain`, minus the ONE transient a concurrent sibling
# legitimately writes: test-lens-run.sh's `provider-teststub<RUN_TAG>.sh` in the real providers dir
# (removed by its EXIT trap). Run in the same ci-local pool, it can appear mid-run; this engine never
# writes that name (it writes only inside its own scratch dir).
repo_status() {
  git -C "$REPO_ROOT" status --porcelain 2>/dev/null \
    | grep -vE '^\?\? loomwright/scripts/adapters/providers/provider-teststub[0-9]+\.sh$'
  return 0
}
tree_sig() { # tree_sig <dir> — path + checksum of every entry, sorted
  (cd "$1" && find . -print | env LC_ALL=C sort | while IFS= read -r p; do
     if [ -f "$p" ]; then printf '%s %s\n' "$p" "$(cksum < "$p")"; else printf '%s\n' "$p"; fi
   done)
}

# ---- fixtures for the main run ------------------------------------------------
PIN_HELP='usage: stub [--pin-a] [--pin-b] [--always-approve]'
make_stub writer      'LOGGED-IN-OK as someone' "$PIN_HELP"                 pass
make_stub reader      'LOGGED-IN-OK'            'usage: stub [--pin-a]'      pass
make_stub autoapprove 'LOGGED-IN-OK'            'usage: stub [--always-approve]' pass
make_stub permunknown 'LOGGED-IN-OK'            "$PIN_HELP"                 pass
make_stub notlogged   'NOT-LOGGED-IN'           "$PIN_HELP"                 pass
make_stub authunknown 'status: who knows'       "$PIN_HELP"                 garbage
make_stub garbage     'LOGGED-IN-OK'            "$PIN_HELP"                 garbage
make_stub wrongreply  'LOGGED-IN-OK'            "$PIN_HELP"                 wrongreply
make_stub fenced      'LOGGED-IN-OK'            "$PIN_HELP"                 fenced
make_stub viasmoke    'unused'                  "$PIN_HELP"                 pass
make_stub viasmokenl  'unused'                  "$PIN_HELP"                 notlogged
make_stub viasmokefail 'unused'                 "$PIN_HELP"                 garbage
make_stub prefixonly  'LOGGED-IN-OK'            'usage: stub [--allow-all] [--deny-x] [--allowed=TOOLS]' pass
make_stub rcauth      'any text at all'         "$PIN_HELP"                 pass
make_stub silent      'LOGGED-IN-OK'            '__silent__'                pass
make_stub lensonly    'LOGGED-IN-OK'            "$PIN_HELP"                 pass
make_stub badname     'LOGGED-IN-OK'            "$PIN_HELP"                 pass
make_stub permwrite   'LOGGED-IN-OK'            "$PIN_HELP"                 pass write
make_stub helponly    'LOGGED-IN-OK'            "$PIN_HELP"                 pass
make_stub permfail    'LOGGED-IN-OK'            "$PIN_HELP"                 pass fail
make_stub permnosmoke 'LOGGED-IN-OK'            "$PIN_HELP"                 garbage write
make_stub logindecl   'LOGGED-IN-OK'            "$PIN_HELP"                 pass refuse "$LOGIN_REL"
make_stub loginundecl 'LOGGED-IN-OK'            "$PIN_HELP"                 pass refuse "$LOGIN_REL"
make_stub smokedecl   'unused'                  "$PIN_HELP"                 pass refuse "$LOGIN_REL"
make_stub smokeundecl 'unused'                  "$PIN_HELP"                 pass refuse "$LOGIN_REL"
# `absent` gets a provider file but NO stub binary.

write_provider "$PDIR" absent      cmd  "--pin-a"         unknown
write_provider "$PDIR" writer      cmd  "--pin-a --pin-b" yes
write_provider "$PDIR" reader      cmd  "--pin-a --pin-b" no
write_provider "$PDIR" autoapprove cmd  "none"            unknown
write_provider "$PDIR" permunknown cmd  ""                unknown
write_provider "$PDIR" notlogged   cmd  "--pin-a"         unknown
write_provider "$PDIR" authunknown cmd  "--pin-a"         unknown
write_provider "$PDIR" garbage     cmd  "--pin-a"         unknown
write_provider "$PDIR" wrongreply  cmd  "--pin-a"         unknown
write_provider "$PDIR" fenced      cmd  "--pin-a"         unknown
write_provider "$PDIR" viasmoke    none "--pin-a"         unknown
write_provider "$PDIR" rcauth      cmd  "--pin-a"         unknown ""
write_provider "$PDIR" silent      cmd  "--pin-a"         unknown
write_provider "$PDIR" viasmokenl  none "--pin-a"         unknown
write_provider "$PDIR" viasmokefail none "--pin-a"        unknown
write_provider "$PDIR" prefixonly  cmd  "--allow --deny"  unknown
add_perm_probe "$PDIR" writer
add_perm_probe "$PDIR" viasmoke
write_provider "$PDIR" permwrite   cmd  "--pin-a --pin-b" unknown
add_perm_probe "$PDIR" permwrite
write_provider "$PDIR" helponly    cmd  "--pin-a --pin-b" unknown
write_provider "$PDIR" permfail    cmd  "--pin-a --pin-b" unknown
add_perm_probe "$PDIR" permfail
write_provider "$PDIR" permnosmoke cmd  "--pin-a"         unknown
add_perm_probe "$PDIR" permnosmoke
write_provider "$PDIR" logindecl   cmd  ""                unknown
add_login "$PDIR" logindecl
write_provider "$PDIR" loginundecl cmd  ""                unknown
add_login_env "$PDIR" loginundecl
write_provider "$PDIR" smokedecl   none ""                unknown
add_login "$PDIR" smokedecl
write_provider "$PDIR" smokeundecl none ""                unknown
# Z: a lens-only file (no probe entries — the shape of test-lens-run.sh's
# transient teststub) and a probe-bearing file whose name fails the allowlist.
{
  printf '#!/usr/bin/env bash\nPROVIDER_CLI_NAME=%q\n' "$(cli_of lensonly)"
  printf 'PROVIDER_WORKSPACE_FLAG=0\nPROVIDER_HOME_SCRUB=1\n'
  printf 'provider_build_argv() { PROVIDER_ARGV=("$PROMPT_CONTENT"); }\n'
  printf 'provider_extract_text() { PROVIDER_EXTRACTED="$(cat "$1")"; }\n'
} > "$PDIR/provider-teststub$RUN_TAG.sh"
write_provider "$PDIR" badname cmd "--pin-a" unknown
mv "$PDIR/provider-badname.sh" "$PDIR/provider-bad.name.sh"

echo "== W/A/P/Q/I/R/X/U/N/K/G/S/L/F/C/Z: main run =="
GIT_BEFORE="$(repo_status)"
HOME_BEFORE="$(tree_sig "$THOME")"
OUT="$TMP/main.out"
rc="$(run_check "$OUT")"
GIT_AFTER="$(repo_status)"
HOME_AFTER="$(tree_sig "$THOME")"
REPORT="$(cat "$OUT")"

assert_eq "W: exit 0" "0" "$rc"
assert_eq "W: repo git status unchanged" "$GIT_BEFORE" "$GIT_AFTER"
assert_eq "W: temp HOME tree (incl. tool config tree) unchanged" "$HOME_BEFORE" "$HOME_AFTER"
assert_eq "W: engine scratch dir removed (its TMPDIR is empty)" "" "$(ls -A "$ETMP")"
has "W: header says the smoke runs under the isolated launcher" "$REPORT" "HOME: an isolated per-call HOME under the shared launcher"
has "W: header says never the real HOME" "$REPORT" "never the real HOME"
lacks "W: header no longer claims the real HOME" "$REPORT" "HOME: the REAL HOME"
has "W: header states the permission probe's cost (AC6)" "$REPORT" "permission probe: one model call per candidate provider"
has "W: header says the smoke cwd is a throwaway dir" "$REPORT" "cwd: a throwaway mktemp -d dir, never the repo"
has "W: header says the prompt is fixed" "$REPORT" "fixed prompt (no repo content)"

r="$(row_args "$OUT" absent)"
has "A: installed: no" "$r" "installed: no"
has "A: verdict not usable: installed" "$r" "=> not usable: installed"
lacks "A: no other column run" "$r" "auth"
assert_eq "A: install hint printed" "    install: install-hint-absent" "$(hint_of "$OUT" absent)"

r="$(row_args "$OUT" writer)"
has "P: installed <ver>" "$r" "installed 9.9.9-writer"
has "P: auth ok" "$r" "auth ok ·"
has "P: headless pass" "$r" "headless pass"
has "P: permissions pinnable" "$r" "permissions pinnable"
has "P: browser yes" "$r" "browser yes"
has "P: verdict usable for write seats" "$r" "=> usable for write seats"
case "$(hint_of "$OUT" writer)" in
  "    "*) no "P: no hint line under a passing row" ;;
  *) ok "P: no hint line under a passing row" ;;
esac
assert_eq "P: the permission probe ran" "present" "$([ -e "$MARK/writer.perm-ran" ] && echo present || echo absent)"
PERM_CWD="$(cat "$MARK/writer.perm-cwd" 2>/dev/null)"
case "$PERM_CWD" in
  "$(cd "$ETMP" && pwd -P)"/*) ok "P: probe cwd is under the engine's own scratch dir" ;;
  *) no "P: probe cwd is under the engine's own scratch dir (got [$PERM_CWD])" ;;
esac
assert_eq "P: probe cwd removed after the run" "gone" "$([ -n "$PERM_CWD" ] && [ ! -e "$PERM_CWD" ] && echo gone || echo present)"
assert_eq "P: probe prompt is the fixed write request" "$PERM_PROMPT" "$(cat "$MARK/writer.perm-prompt" 2>/dev/null)"
case "$(cat "$MARK/writer.perm-home" 2>/dev/null)" in
  "$THOME"|"") no "P: probe ran under an isolated HOME (got [$(cat "$MARK/writer.perm-home" 2>/dev/null)])" ;;
  *) ok "P: probe ran under an isolated HOME, not the engine's HOME" ;;
esac

r="$(row_args "$OUT" permwrite)"
has "Q: CLI ignores its pin flags and writes -> unpinnable (pin flags not enforced)" "$r" "permissions: unpinnable (pin flags not enforced)"
lacks "Q: write-anyway CLI is never pinnable" "$r" "permissions pinnable"
lacks "Q: write-anyway CLI never gets write seats" "$r" "write seats"
has "Q: write-anyway CLI verdict usable for read-only seats" "$r" "=> usable for read-only seats"
r="$(row_args "$OUT" helponly)"
has "Q: tokens advertised, no probe defined -> pin flags advertised (unverified)" "$r" "permissions: pin flags advertised (unverified)"
lacks "Q: help-only never gets write seats" "$r" "write seats"
r="$(row_args "$OUT" permfail)"
has "Q: probe exits non-zero, no file -> pin flags advertised (unverified)" "$r" "permissions: pin flags advertised (unverified)"
assert_eq "Q: failing probe did run" "present" "$([ -e "$MARK/permfail.perm-ran" ] && echo present || echo absent)"
r="$(row_args "$OUT" permnosmoke)"
has "Q: smoke not passing -> pin flags advertised (unverified)" "$r" "permissions: pin flags advertised (unverified)"
assert_eq "Q: smoke not passing -> the permission probe is NOT run" "absent" "$([ -e "$MARK/permnosmoke.perm-ran" ] && echo present || echo absent)"

r="$(row_args "$OUT" logindecl)"
has "I: declared login file -> auth ok (auth command, isolated)" "$r" "auth ok ·"
has "I: declared login file -> usable" "$r" "=> usable for "
r="$(row_args "$OUT" smokedecl)"
has "I: declared login file -> auth ok (via smoke)" "$r" "auth ok (via smoke)"
has "I: declared login file (smoke-only) -> usable" "$r" "=> usable for "
r="$(row_args "$OUT" loginundecl)"
has "I: undeclared login -> auth: not_logged_in_isolated (ok in your shell)" "$r" "auth: not_logged_in_isolated (ok in your shell) ·"
has "I: undeclared login -> not usable: auth" "$r" "=> not usable: auth"
has "I: undeclared login -> headless not run" "$r" "headless: not run (auth not ok)"
assert_eq "I: undeclared login (auth command) -> smoke NOT run" "absent" "$([ -e "$MARK/loginundecl.smoke-ran" ] && echo present || echo absent)"
case "$(hint_of "$OUT" loginundecl)" in
  "    fix: "*"env vars: LWPROBE_FAKE_API_KEY"*"Set one of the declared env vars"*) ok "I: fix hint names the declared login env var" ;;
  *) no "I: fix hint names the declared login env var (got [$(hint_of "$OUT" loginundecl)])" ;;
esac
r="$(row_args "$OUT" smokeundecl)"
has "I: undeclared login (smoke-only) -> auth: not_logged_in_isolated (ok in your shell)" "$r" "auth: not_logged_in_isolated (ok in your shell) ·"
has "I: undeclared login (smoke-only) -> not usable: auth" "$r" "=> not usable: auth"
has "I: undeclared login (smoke-only) -> the isolated smoke failed" "$r" "headless: fail:exit1"
assert_eq "I: smoke-only diagnosis -> the isolated smoke AND one shell rerun ran" "present" \
  "$([ -e "$MARK/smokeundecl.smoke-ran2" ] && echo present || echo absent)"
case "$(hint_of "$OUT" smokeundecl)" in
  "    fix: "*"declared login files: none; env vars: none"*"Declare where this CLI keeps its login"*) ok "I: fix hint with nothing declared says to declare it" ;;
  *) no "I: fix hint with nothing declared says to declare it (got [$(hint_of "$OUT" smokeundecl)])" ;;
esac

r="$(row_args "$OUT" reader)"
has "R: permissions: unpinnable (token missing from --help)" "$r" "permissions: unpinnable"
has "R: browser: no" "$r" "browser: no"
has "R: verdict usable for read-only seats" "$r" "=> usable for read-only seats"

r="$(row_args "$OUT" prefixonly)"
has "R: pin tokens only as prefixes of longer flags -> permissions: unpinnable" "$r" "permissions: unpinnable"
lacks "R: prefix-only pin tokens never give write seats" "$r" "write seats"

r="$(row_args "$OUT" autoapprove)"
has "X: permissions: unpinnable (declared none)" "$r" "permissions: unpinnable"
lacks "X: never usable for write seats" "$r" "write seats"
has "X: verdict usable for read-only seats" "$r" "=> usable for read-only seats"

r="$(row_args "$OUT" permunknown)"
has "U: permissions: unknown" "$r" "permissions: unknown"
has "U: browser: unknown" "$r" "browser: unknown"
has "U: verdict usable for read-only seats" "$r" "=> usable for read-only seats"

r="$(row_args "$OUT" notlogged)"
has "N: auth: not_logged_in" "$r" "auth: not_logged_in ·"
lacks "N: logged out in the shell too -> never not_logged_in_isolated" "$r" "not_logged_in_isolated"
has "N: headless: not run" "$r" "headless: not run"
has "N: verdict not usable: auth" "$r" "=> not usable: auth"
assert_eq "N: login hint printed" "    login: login-hint-notlogged" "$(hint_of "$OUT" notlogged)"
assert_eq "N: smoke NOT run" "absent" "$([ -e "$MARK/notlogged.smoke-ran" ] && echo present || echo absent)"

r="$(row_args "$OUT" authunknown)"
has "K: auth: unknown" "$r" "auth: unknown"
has "K: headless: fail:unparseable" "$r" "headless: fail:unparseable"
has "K: verdict not usable: auth" "$r" "=> not usable: auth"
assert_eq "K: login hint qualified (auth unknown, not seen logged out)" \
  "    login (only if not logged in): login-hint-authunknown" "$(hint_of "$OUT" authunknown)"

r="$(row_args "$OUT" garbage)"
has "G: auth ok" "$r" "auth ok ·"
has "G: headless: fail:unparseable" "$r" "headless: fail:unparseable"
has "G: verdict not usable: headless" "$r" "=> not usable: headless"

r="$(row_args "$OUT" wrongreply)"
has "G: well-formed envelope, wrong reply -> headless: fail:unparseable" "$r" "headless: fail:unparseable"
has "G: wrong reply verdict not usable: headless" "$r" "=> not usable: headless"

r="$(row_args "$OUT" fenced)"
has "G: reply inside a markdown code fence -> headless pass" "$r" "headless pass"

r="$(row_args "$OUT" rcauth)"
has "O: no ok-pattern declared -> auth ok from the auth command's exit 0" "$r" "auth ok ·"

r="$(row_args "$OUT" silent)"
has "O: failing version command -> installed (version unknown)" "$r" "installed (version unknown)"
has "O: empty help output -> permissions: unknown" "$r" "permissions: unknown"

r="$(row_args "$OUT" viasmoke)"
has "S: auth ok (via smoke)" "$r" "auth ok (via smoke)"
has "S: headless pass" "$r" "headless pass"
has "S: verdict usable for write seats" "$r" "=> usable for write seats"

r="$(row_args "$OUT" viasmokenl)"
has "L: auth: not_logged_in (via smoke)" "$r" "auth: not_logged_in (via smoke)"
lacks "L: logged out in the shell too -> never not_logged_in_isolated" "$r" "not_logged_in_isolated"
has "L: headless: fail:exit1" "$r" "headless: fail:exit1"
has "L: verdict not usable: auth" "$r" "=> not usable: auth"
assert_eq "L: no auth command -> the smoke DID run (it is the only auth signal)" "present" \
  "$([ -e "$MARK/viasmokenl.smoke-ran" ] && echo present || echo absent)"
assert_eq "L: login hint printed unqualified (not_logged_in was seen)" \
  "    login: login-hint-viasmokenl" "$(hint_of "$OUT" viasmokenl)"

r="$(row_args "$OUT" viasmokefail)"
has "F: auth: unknown (smoke failed: unparseable)" "$r" "auth: unknown (smoke failed: unparseable)"
has "F: headless: fail:unparseable" "$r" "headless: fail:unparseable"
has "F: verdict not usable: auth (first failing column)" "$r" "=> not usable: auth"
assert_eq "F: login hint qualified, never an unconditional 'log in'" \
  "    login (only if not logged in): login-hint-viasmokefail" "$(hint_of "$OUT" viasmokefail)"

SMOKE_CWD="$(cat "$MARK/writer.smoke-cwd" 2>/dev/null)"
ETMP_REAL="$(cd "$ETMP" && pwd -P)"
case "$SMOKE_CWD" in
  "$ETMP_REAL"/*) ok "C: smoke cwd is under the engine's own scratch dir" ;;
  *) no "C: smoke cwd is under the engine's own scratch dir (got [$SMOKE_CWD])" ;;
esac
case "$SMOKE_CWD" in
  "$(cd "$REPO_ROOT" && pwd -P)"*) no "C: smoke cwd is not the repo (got [$SMOKE_CWD])" ;;
  *) ok "C: smoke cwd is not the repo" ;;
esac
assert_eq "C: smoke cwd removed after the run" "gone" "$([ -n "$SMOKE_CWD" ] && [ ! -e "$SMOKE_CWD" ] && echo gone || echo present)"
SMOKE_HOME="$(cat "$MARK/writer.smoke-home" 2>/dev/null)"
case "$SMOKE_HOME" in
  "$THOME"|"") no "C: smoke HOME is an isolated HOME, NOT the HOME the engine got (got [$SMOKE_HOME])" ;;
  *) ok "C: smoke HOME is an isolated HOME, NOT the HOME the engine got" ;;
esac
case "$SMOKE_HOME" in
  "$ETMP"/*|"$ETMP_REAL"/*) ok "C: smoke HOME is a temp dir under the engine's TMPDIR" ;;
  *) no "C: smoke HOME is a temp dir under the engine's TMPDIR (got [$SMOKE_HOME])" ;;
esac
assert_eq "C: smoke HOME removed after the run" "gone" "$([ -n "$SMOKE_HOME" ] && [ ! -e "$SMOKE_HOME" ] && echo gone || echo present)"
assert_eq "C: smoke prompt is the fixed probe string" \
  'Reply with exactly this JSON and nothing else: {"probe":"loomwright-ok"}' \
  "$(cat "$MARK/writer.smoke-prompt" 2>/dev/null)"
assert_eq "C: no stub saw an unexpected argv" "" "$(cd "$MARK" && ls *.unexpected 2>/dev/null)"

lacks "Z: lens-only teststub file not reported" "$REPORT" "teststub$RUN_TAG"
lacks "Z: lens-only teststub CLI not reported" "$REPORT" "$(cli_of lensonly)"
assert_eq "Z: lens-only teststub CLI never run" "absent" "$([ -e "$MARK/lensonly.smoke-ran" ] && echo present || echo absent)"
lacks "Z: allowlist-failing name not reported" "$REPORT" "$(cli_of badname)"
assert_eq "Z: allowlist-failing provider's CLI never run" "absent" "$([ -e "$MARK/badname.smoke-ran" ] && echo present || echo absent)"

echo "== H: hung smoke, TERM ignored, timeout 2 =="
HDIR="$TMP/providers-h"; mkdir -p "$HDIR"
make_stub hang 'LOGGED-IN-OK' "$PIN_HELP" hang
write_provider "$HDIR" hang cmd "--pin-a" unknown
make_stub permhang 'LOGGED-IN-OK' "$PIN_HELP" pass hang
write_provider "$HDIR" permhang cmd "--pin-a" unknown
add_perm_probe "$HDIR" permhang
OUT_H="$TMP/hang.out"
H_START="$(date +%s)"
rc="$(run_check "$OUT_H" LOOMWRIGHT_PROVIDERS_DIR="$HDIR" LOOMWRIGHT_PROVIDER_SMOKE_TIMEOUT=2)"
H_ELAPSED=$(( $(date +%s) - H_START ))
r="$(row_args "$OUT_H" hang)"
assert_eq "H: exit 0" "0" "$rc"
has "H: headless: fail:timeout" "$r" "headless: fail:timeout"
has "H: verdict not usable: headless" "$r" "=> not usable: headless"
if [ "$H_ELAPSED" -lt 20 ]; then ok "H: run ended in ${H_ELAPSED}s (< the stub's 30s sleep: KILL fired)"; else no "H: run took ${H_ELAPSED}s (the TERM-ignoring stub was not KILLed)"; fi
H_PID="$(cat "$MARK/hang.pid" 2>/dev/null)"
H_PGID="$(cat "$MARK/hang.pgid" 2>/dev/null)"
H_CHILD="$(cat "$MARK/hang.child" 2>/dev/null)"
if [ -n "$H_PID" ] && [ -n "$H_CHILD" ]; then ok "H: stub recorded its pid and child"; else no "H: stub recorded its pid and child"; fi
assert_eq "H: smoke ran as its own process group (pgid = pid)" "$H_PID" "$H_PGID"
if [ -n "$H_PID" ] && kill -0 "$H_PID" 2>/dev/null; then no "H: stub leader still alive"; else ok "H: stub leader gone"; fi
if [ -n "$H_CHILD" ] && kill -0 "$H_CHILD" 2>/dev/null; then no "H: stub child still alive"; else ok "H: stub child gone"; fi
if [ -n "$H_PGID" ] && command -v pgrep >/dev/null 2>&1 && [ -n "$(pgrep -g "$H_PGID" 2>/dev/null)" ]; then
  no "H: stub process group still has members"
else
  ok "H: stub process group empty"
fi
r="$(row_args "$OUT_H" permhang)"
has "H: hung permission probe -> pin flags advertised (unverified)" "$r" "permissions: pin flags advertised (unverified)"
lacks "H: hung permission probe never gets write seats" "$r" "write seats"
assert_eq "H: engine scratch dir removed" "" "$(ls -A "$ETMP")"

echo "== J: jq unavailable =="
JDIR="$TMP/providers-j"; mkdir -p "$JDIR"
make_stub jqless 'LOGGED-IN-OK' "$PIN_HELP" pass
write_provider "$JDIR" jqless cmd "--pin-a" unknown
make_stub jqlessnoauth 'unused' "$PIN_HELP" pass
write_provider "$JDIR" jqlessnoauth none "--pin-a" unknown
OUT_J="$TMP/jq.out"
rc="$(run_check "$OUT_J" LOOMWRIGHT_PROVIDERS_DIR="$JDIR" LOOMWRIGHT_JQ_BIN="$TMP/no-such-jq" \
  LOOMWRIGHT_PROVIDER_SMOKE_TIMEOUT=abc LOOMWRIGHT_PROVIDER_QUICK_TIMEOUT=0)"
assert_eq "J: exit 0" "0" "$rc"
has "J: headless: not run (jq not found)" "$(row_args "$OUT_J" jqless)" "headless: not run (jq not found)"
has "J: header names the missing jq" "$(cat "$OUT_J")" "jq not found on PATH"
has "J: invalid timeout values fall back to the defaults" "$(cat "$OUT_J")" "timeout 120s (other calls 20s)"
assert_eq "J: smoke not run" "absent" "$([ -e "$MARK/jqless.smoke-ran" ] && echo present || echo absent)"
has "J: no auth command + jq missing -> auth: unknown (smoke not run)" "$(row_args "$OUT_J" jqlessnoauth)" "auth: unknown (smoke not run)"

echo "== E: usage errors =="
bash "$ENGINE" >/dev/null 2>&1; assert_eq "E: no subcommand -> 64" "64" "$?"
bash "$ENGINE" check extra >/dev/null 2>&1; assert_eq "E: extra argument -> 64" "64" "$?"
bash "$ENGINE" nope >/dev/null 2>&1; assert_eq "E: unknown subcommand -> 64" "64" "$?"

echo "== T: real provider-table files keep the lens contract and declare probe entries =="
EXPECTED_PROMPT='Reply with exactly this JSON and nothing else: {"probe":"loomwright-ok"}'
# table_verdict <provider-file> — "ok" or the missing items. A function called
# inside $( ) rather than an inline body: bash 3.2 (macOS /bin/bash) closes a
# $( ) early at the bare ')' of a case pattern written inside it.
table_verdict() {
  local f="$1"
  (
    set +u
    PROMPT_CONTENT="LENS-PROMPT-SENTINEL"; MODEL="m"; WORKSPACE_DIR="/nonexistent"
    PROBE_PROMPT="$EXPECTED_PROMPT"; PROBE_CWD="/nonexistent"; JQ=jq
    # shellcheck disable=SC1090
    . "$f" >/dev/null 2>&1
    miss=""
    [ -n "${PROVIDER_CLI_NAME:-}" ] || miss="$miss PROVIDER_CLI_NAME"
    case "${PROVIDER_WORKSPACE_FLAG:-}" in 0|1) ;; *) miss="$miss PROVIDER_WORKSPACE_FLAG" ;; esac
    case "${PROVIDER_HOME_SCRUB:-}" in 0|1) ;; *) miss="$miss PROVIDER_HOME_SCRUB" ;; esac
    for fn in provider_build_argv provider_extract_text probe_smoke_argv; do
      declare -F "$fn" >/dev/null 2>&1 || miss="$miss $fn"
    done
    for v in PROBE_VERSION_ARGV PROBE_AUTH_ARGV PROBE_AUTH_OK_RE PROBE_AUTH_NOT_LOGGED_IN_RE PROBE_HELP_ARGV PROBE_PERM_PIN_FLAGS; do
      declare -p "$v" >/dev/null 2>&1 || miss="$miss $v"
    done
    [ "${#PROBE_VERSION_ARGV[@]}" -gt 0 ] 2>/dev/null || miss="$miss PROBE_VERSION_ARGV(empty)"
    case "${PROBE_BROWSER:-}" in yes|no|unknown) ;; *) miss="$miss PROBE_BROWSER" ;; esac
    [ -n "${PROBE_INSTALL_HINT:-}" ] || miss="$miss PROBE_INSTALL_HINT"
    [ -n "${PROBE_LOGIN_HINT:-}" ] || miss="$miss PROBE_LOGIN_HINT"
    if declare -F provider_build_argv >/dev/null 2>&1; then
      PROVIDER_ARGV=(); provider_build_argv
      [ "${PROVIDER_ARGV[${#PROVIDER_ARGV[@]}-1]}" = "LENS-PROMPT-SENTINEL" ] || miss="$miss lens-prompt-not-last"
    fi
    if declare -F probe_smoke_argv >/dev/null 2>&1; then
      PROBE_ARGV=(); probe_smoke_argv
      [ "${PROBE_ARGV[${#PROBE_ARGV[@]}-1]}" = "$EXPECTED_PROMPT" ] || miss="$miss smoke-prompt-not-last"
    fi
    if declare -F probe_perm_argv >/dev/null 2>&1; then
      PROBE_ARGV=(); probe_perm_argv
      [ "${PROBE_ARGV[${#PROBE_ARGV[@]}-1]}" = "$EXPECTED_PROMPT" ] || miss="$miss perm-prompt-not-last"
    fi
    printf '%s' "${miss:-ok}"
  )
}
nreal=0
for f in "$REAL_PDIR"/provider-*.sh; do
  [ -f "$f" ] || continue
  base="${f##*/}"
  case "$base" in provider-teststub*) continue ;; esac   # transient test-only files
  nreal=$((nreal + 1))
  verdict="$(table_verdict "$f")"
  assert_eq "T: $base keeps the lens contract + declares probe entries" "ok" "$verdict"
done
if [ "$nreal" -gt 0 ]; then ok "T: found $nreal real provider-table file(s)"; else no "T: no real provider-table files found under $REAL_PDIR"; fi

echo "== V: setup-providers.sh names no provider CLI or table name =="
for f in "$REAL_PDIR"/provider-*.sh; do
  [ -f "$f" ] || continue
  base="${f##*/}"
  case "$base" in provider-teststub*) continue ;; esac
  tname="${base#provider-}"; tname="${tname%.sh}"
  cname="$( . "$f" >/dev/null 2>&1; printf '%s' "${PROVIDER_CLI_NAME:-}" )"
  for word in "$tname" "$cname"; do
    [ -n "$word" ] || continue
    if grep -qiF -- "$word" "$ENGINE"; then no "V: engine names '$word' (from $base)"; else ok "V: engine does not name '$word'"; fi
  done
done

echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
