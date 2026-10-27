#!/usr/bin/env bash
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
# test-resolve-base-branch.sh — table-driven self-tests for resolve-base-branch.sh.
# Exit 0 = all pass, 1 = any failure. UNCOUNTED by the doc-currency gate (test-*.sh).
#
# Every fixture is a throwaway repo under a mktemp dir with a local bare `origin` (no network);
# HOME and the git global/system config are sandboxed, and every case runs with a gh STUB first on
# PATH (or with no gh on PATH at all), so the real gh is never reached.
#
# Covers:
#   P.  precedence: flag > brief > config `.base_branch` > origin/HEAD > gh (AC1–AC4), including
#       an empty --flag / --brief meaning "not given", and a brief whose `Base Branch:` sits outside
#       `## Configuration` being ignored.
#   H.  origin/HEAD unset or dangling ⇒ ONE `git remote set-head origin -a` sets it (AC5), with the
#       set-head chatter kept off stdout.
#   U.  nothing answers ⇒ exit 1, `base_branch_unresolved` as the first stderr line, EMPTY stdout
#       — no gh on PATH, a failing gh, and a gh printing an invalid name (AC6).
#   V.  explicit values fail CLOSED and never fall through (AC7): invalid flag / brief / config
#       value, `@{-1}` and a leading `-`, unreadable brief, unparseable / non-object / trailing-junk
#       config, non-string and empty-string `.base_branch`, jq missing while a config exists.
#   E.  --explain prints `<branch> (source: <step>)` for every step (AC8).
#   R.  --repo from an unrelated cwd, the default repo = the cwd's git top-level (a subdirectory
#       still finds the root config), and gh running inside the --repo dir.
#   X.  usage errors exit 2 with empty stdout.
#   K.  MUTATION CONTROLS against COPIES (the brief's Pin mutations rows): the fall-through
#       printing a fixed branch, the config check-ref-format deleted, the set-head line deleted,
#       flag/config order swapped, the brief step deleted, --explain's source suffix dropped.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/resolve-base-branch.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-rbb.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

export HOME="$TMP/home"; mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$TMP/home/.gitconfig"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
unset GH_REPO GH_HOST 2>/dev/null || true
export GIT_CEILING_DIRECTORIES="$TMP"   # cwd $HOME is never inside an enclosing repo
BASH_BIN="${BASH:-bash}"              # absolute: a case PATH need not contain bash
: > "$GIT_CONFIG_GLOBAL"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

# --- gh stubs + a PATH with no gh at all ------------------------------------------------------
GH_FAIL="$TMP/bin-ghfail"; GH_OK="$TMP/bin-ghok"; NOGH="$TMP/bin-nogh"
mkdir -p "$GH_FAIL" "$GH_OK" "$NOGH"
printf '#!/bin/sh\necho "gh: not authenticated" >&2\nexit 1\n' > "$GH_FAIL/gh"
# prints $GH_STUB_OUT for `gh repo view --json defaultBranchRef …` and records the cwd it ran in
printf '#!/bin/sh\npwd -P > "$GH_STUB_CWD"\ncase "$*" in "repo view --json defaultBranchRef"*) printf "%%s\\n" "$GH_STUB_OUT"; exit 0 ;; esac\nexit 1\n' > "$GH_OK/gh"
chmod +x "$GH_FAIL/gh" "$GH_OK/gh"
export GH_STUB_CWD="$TMP/gh-cwd" GH_STUB_OUT=""
for tool in git jq; do ln -s "$(command -v "$tool")" "$NOGH/$tool"; done
nogh_path="$NOGH"
_ifs="$IFS"; IFS=:
for d in $PATH; do [ -n "$d" ] && [ ! -x "$d/gh" ] && nogh_path="$nogh_path:$d"; done
IFS="$_ifs"
P_GHFAIL="$GH_FAIL:$PATH"; P_GHOK="$GH_OK:$PATH"; P_NOGH="$nogh_path"
P_NOJQ="$GH_FAIL:$TMP/bin-nojq"
mkdir -p "$TMP/bin-nojq"
for tool in git awk sed tr cat head dirname pwd; do
  p="$(command -v "$tool" 2>/dev/null)" && [ -n "$p" ] && [ "${p#/}" != "$p" ] && ln -s "$p" "$TMP/bin-nojq/$tool"
done

# --- fixtures ---------------------------------------------------------------------------------
# mk_origin <name> <default-branch> — a bare origin whose HEAD is <default-branch>; prints its path
mk_origin() {
  local o="$TMP/$1.git" s="$TMP/$1-seed"
  git init -q -b "$2" "$s" && git -C "$s" commit -q --allow-empty -m seed \
    && git init -q --bare "$o" && git -C "$s" push -q "$o" "$2" \
    && git -C "$o" symbolic-ref HEAD "refs/heads/$2" || { echo "fixture: mk_origin $1 failed" >&2; exit 1; }
  printf '%s' "$o"
}
# mk_clone <name> <origin> — a clone (origin/HEAD set by the clone); prints its path
mk_clone() {
  git clone -q "$2" "$TMP/$1" 2>/dev/null || { echo "fixture: clone $1 failed" >&2; exit 1; }
  printf '%s' "$TMP/$1"
}
# mk_bare_repo <name> — a repo with no remote at all; prints its path
mk_bare_repo() {
  git init -q -b trunk "$TMP/$1" && git -C "$TMP/$1" commit -q --allow-empty -m seed \
    || { echo "fixture: init $1 failed" >&2; exit 1; }
  printf '%s' "$TMP/$1"
}
# with_config <repo> <body> — write <repo>/.supervisor/config.json
with_config() { mkdir -p "$1/.supervisor"; printf '%s' "$2" > "$1/.supervisor/config.json"; }
# mk_brief <name> <body> — prints its path
mk_brief() { printf '%s\n' "$2" > "$TMP/$1.md"; printf '%s' "$TMP/$1.md"; }

O_DEV="$(mk_origin o-dev development)"
O_MAIN="$(mk_origin o-main main)"
O_TRUNK="$(mk_origin o-trunk trunk)"
R_DEV="$(mk_clone r-dev "$O_DEV")"                 # origin/HEAD → development, no config
R_REL="$(mk_clone r-rel "$O_MAIN")"; with_config "$R_REL" '{"base_branch":"release","auto_review":false}'
R_CFGDEV="$(mk_clone r-cfgdev "$O_MAIN")"; with_config "$R_CFGDEV" '{"base_branch":"development"}'
R_SETHEAD="$(mk_clone r-sethead "$O_TRUNK")"       # origin/HEAD removed before each use
R_NONE="$(mk_bare_repo r-none)"                    # no origin, no config
R_MAIN="$(mk_clone r-main "$O_MAIN")"              # origin/HEAD → main, configs swapped per case
mkdir -p "$R_CFGDEV/sub/dir"

B_DEV="$(mk_brief b-dev '# Supervisor Job: x

## Configuration
- **Workers:** 2
- **Base Branch:** `development`')"
B_NOLINE="$(mk_brief b-noline '# Supervisor Job: x

## Configuration
- **Workers:** 2')"
B_ELSEWHERE="$(mk_brief b-elsewhere '# Supervisor Job: x

## Environment
- **Base Branch:** elsewhere

## Configuration
- **Workers:** 2')"
B_BAD="$(mk_brief b-bad '## Configuration
- **Base Branch:** bad..name')"
B_CRLF="$TMP/b-crlf.md"; printf '## Configuration\r\n- **Base Branch:** crlf-branch\r\n' > "$B_CRLF"

# --- runners ----------------------------------------------------------------------------------
# run_r <script> <PATH> <cwd> <args...> — sets OUT, ERR, ERR1 (first stderr line), RC
run_r() {
  local s="$1" p="$2" cwd="$3"; shift 3
  OUT="$(cd "$cwd" && PATH="$p" "$BASH_BIN" "$s" "$@" 2>"$TMP/err")"; RC=$?
  ERR="$(cat "$TMP/err")"; ERR1="$(printf '%s\n' "$ERR" | head -n 1)"
}
# expect <script> <desc> <want-stdout> <PATH> <cwd> <args...> — exit 0, exact stdout, empty stderr
expect() {
  local s="$1" desc="$2" want="$3" p="$4" cwd="$5"; shift 5
  run_r "$s" "$p" "$cwd" "$@"
  if [ "$RC" -eq 0 ] && [ "$OUT" = "$want" ] && [ -z "$ERR" ]; then ok "$desc"
  else no "$desc — rc=$RC got [$OUT] want [$want] err [$ERR]"; fi
}
# refused <script> <desc> <rc> <token> <PATH> <cwd> <args...> — exit <rc>, EMPTY stdout, first
# stderr line exactly <token> (a <token> of "-" means: a usage line, no status token)
refused() {
  local s="$1" desc="$2" rc="$3" tok="$4" p="$5" cwd="$6"; shift 6
  run_r "$s" "$p" "$cwd" "$@"
  if [ "$RC" -eq "$rc" ] && [ -z "$OUT" ] \
     && { { [ "$tok" = "-" ] && [ -n "$ERR" ] && [ "${ERR1#base_branch_}" = "$ERR1" ]; } || [ "$ERR1" = "$tok" ]; }; then
    ok "$desc"
  else no "$desc — rc=$RC (want $rc) out [$OUT] err1 [$ERR1] (want $tok)"; fi
}
unset_head() { git -C "$1" remote set-head origin -d >/dev/null 2>&1; git -C "$1" symbolic-ref -q refs/remotes/origin/HEAD >/dev/null 2>&1 && { echo "fixture: origin/HEAD still set" >&2; exit 1; }; return 0; }

run_table() {
  local s="$1" got
  # P — precedence
  expect "$s" "P1 AC1 origin/HEAD → development, no config ⇒ development" development "$P_GHFAIL" "$R_DEV"
  expect "$s" "P2 AC2 config release beats origin/HEAD main" release "$P_GHFAIL" "$R_REL"
  expect "$s" "P3 AC3 flag beats config" feat/x "$P_GHFAIL" "$R_CFGDEV" --flag feat/x
  expect "$s" "P4 AC4 brief beats origin/HEAD (no flag, no config)" development "$P_GHFAIL" "$R_MAIN" --brief "$B_DEV"
  expect "$s" "P5 brief beats config" development "$P_GHFAIL" "$R_REL" --brief "$B_DEV"
  expect "$s" "P6 flag beats brief" feat/x "$P_GHFAIL" "$R_MAIN" --flag feat/x --brief "$B_DEV"
  expect "$s" "P7 empty --flag is 'not given' ⇒ config" release "$P_GHFAIL" "$R_REL" --flag ""
  expect "$s" "P8 empty --brief is 'not given' ⇒ config" release "$P_GHFAIL" "$R_REL" --brief ""
  expect "$s" "P9 brief without the line falls through to config" release "$P_GHFAIL" "$R_REL" --brief "$B_NOLINE"
  expect "$s" "P10 Base Branch outside ## Configuration is ignored" main "$P_GHFAIL" "$R_MAIN" --brief "$B_ELSEWHERE"
  expect "$s" "P11 CRLF brief line is read without the CR" crlf-branch "$P_GHFAIL" "$R_MAIN" --brief "$B_CRLF"
  expect "$s" "P12 origin/HEAD beats gh" development "$P_GHOK" "$R_DEV"
  with_config "$R_MAIN" '{"auto_review":false}'
  expect "$s" "P13 config without the key falls through to origin/HEAD" main "$P_GHFAIL" "$R_MAIN"
  with_config "$R_MAIN" '{"base_branch":null}'
  expect "$s" "P14 config null falls through to origin/HEAD" main "$P_GHFAIL" "$R_MAIN"
  rm -rf "$R_MAIN/.supervisor"

  # H — set-head -a
  unset_head "$R_SETHEAD"
  expect "$s" "H1 AC5 origin/HEAD unset ⇒ set-head -a, prints trunk" trunk "$P_GHFAIL" "$R_SETHEAD"
  got="$(git -C "$R_SETHEAD" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"
  if [ "$got" = "origin/trunk" ]; then ok "H2 AC5 origin/HEAD was set to origin/trunk"; else no "H2 AC5 origin/HEAD after run: [$got]"; fi
  git -C "$R_SETHEAD" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/gone
  expect "$s" "H3 dangling origin/HEAD ⇒ set-head -a repairs it" trunk "$P_GHFAIL" "$R_SETHEAD"
  unset_head "$R_SETHEAD"
  expect "$s" "H4 set-head path under --explain" "trunk (source: origin-head)" "$P_NOGH" "$R_SETHEAD" --explain

  # U — unresolved
  refused "$s" "U1 AC6 no origin, no config, no gh on PATH ⇒ base_branch_unresolved" 1 base_branch_unresolved "$P_NOGH" "$R_NONE"
  refused "$s" "U2 no origin, gh fails ⇒ base_branch_unresolved" 1 base_branch_unresolved "$P_GHFAIL" "$R_NONE"
  GH_STUB_OUT='bad..name'
  refused "$s" "U3 gh prints an invalid name ⇒ unresolved (discovered value skipped)" 1 base_branch_unresolved "$P_GHOK" "$R_NONE"
  GH_STUB_OUT=''
  refused "$s" "U4 gh prints nothing ⇒ unresolved" 1 base_branch_unresolved "$P_GHOK" "$R_NONE"
  refused "$s" "U5 not a git repo at all ⇒ unresolved" 1 base_branch_unresolved "$P_GHFAIL" "$HOME"
  refused "$s" "U6 --explain changes nothing on failure" 1 base_branch_unresolved "$P_NOGH" "$R_NONE" --explain

  # V — explicit values fail CLOSED, no fall-through (origin/HEAD main is present in R_MAIN)
  with_config "$R_MAIN" '{"base_branch":"bad..name"}'
  refused "$s" "V1 AC7 config bad..name ⇒ base_branch_invalid:config (no fall-through)" 2 base_branch_invalid:config "$P_GHFAIL" "$R_MAIN"
  refused "$s" "V2 AC7 flag bad..name ⇒ base_branch_invalid:flag" 2 base_branch_invalid:flag "$P_GHFAIL" "$R_CFGDEV" --flag bad..name
  refused "$s" "V3 AC7 brief bad..name ⇒ base_branch_invalid:brief (valid config ignored)" 2 base_branch_invalid:brief "$P_GHFAIL" "$R_CFGDEV" --brief "$B_BAD"
  refused "$s" "V4 flag @{-1} is refused (no shorthand expansion)" 2 base_branch_invalid:flag "$P_GHFAIL" "$R_CFGDEV" --flag '@{-1}'
  refused "$s" "V5 flag with a leading dash is refused" 2 base_branch_invalid:flag "$P_GHFAIL" "$R_CFGDEV" --flag --help
  refused "$s" "V6 invalid flag beats a valid brief" 2 base_branch_invalid:flag "$P_GHFAIL" "$R_MAIN" --flag 'a b' --brief "$B_DEV"
  refused "$s" "V7 unreadable brief ⇒ base_branch_invalid:brief" 2 base_branch_invalid:brief "$P_GHFAIL" "$R_CFGDEV" --brief "$TMP/no-such-brief.md"
  with_config "$R_MAIN" '{"base_branch":7}'
  refused "$s" "V8 non-string .base_branch ⇒ invalid:config" 2 base_branch_invalid:config "$P_GHFAIL" "$R_MAIN"
  with_config "$R_MAIN" '{"base_branch":""}'
  refused "$s" "V9 empty-string .base_branch ⇒ invalid:config" 2 base_branch_invalid:config "$P_GHFAIL" "$R_MAIN"
  with_config "$R_MAIN" 'not json'
  refused "$s" "V10 unparseable config ⇒ invalid:config" 2 base_branch_invalid:config "$P_GHFAIL" "$R_MAIN"
  with_config "$R_MAIN" '{"base_branch":"main"} junk'
  refused "$s" "V11 trailing junk after the object ⇒ invalid:config" 2 base_branch_invalid:config "$P_GHFAIL" "$R_MAIN"
  with_config "$R_MAIN" '["main"]'
  refused "$s" "V12 non-object config ⇒ invalid:config" 2 base_branch_invalid:config "$P_GHFAIL" "$R_MAIN"
  with_config "$R_MAIN" '{"base_branch":"release"}'
  refused "$s" "V13 jq missing while a config exists ⇒ invalid:config" 2 base_branch_invalid:config "$P_NOJQ" "$R_MAIN"
  expect "$s" "V14 a valid flag never reads a broken config" feat/x "$P_GHFAIL" "$R_MAIN" --flag feat/x
  rm -rf "$R_MAIN/.supervisor"

  # E — --explain labels
  expect "$s" "E1 AC8 --explain config" "development (source: config)" "$P_GHFAIL" "$R_CFGDEV" --explain
  expect "$s" "E2 --explain flag" "feat/x (source: flag)" "$P_GHFAIL" "$R_CFGDEV" --explain --flag feat/x
  expect "$s" "E3 --explain brief" "development (source: brief)" "$P_GHFAIL" "$R_MAIN" --brief "$B_DEV" --explain
  expect "$s" "E4 --explain origin-head" "development (source: origin-head)" "$P_GHFAIL" "$R_DEV" --explain
  GH_STUB_OUT='develop'
  expect "$s" "E5 --explain gh" "develop (source: gh)" "$P_GHOK" "$R_NONE" --explain
  GH_STUB_OUT=''

  # R — repo selection
  expect "$s" "R1 --repo from an unrelated cwd" development "$P_GHFAIL" "$HOME" --repo "$R_DEV"
  expect "$s" "R2 default repo = the cwd's top-level (subdir finds the root config)" development "$P_GHFAIL" "$R_CFGDEV/sub/dir"
  GH_STUB_OUT='develop'; rm -f "$GH_STUB_CWD"
  expect "$s" "R3 gh step from an unrelated cwd" develop "$P_GHOK" "$HOME" --repo "$R_NONE"
  got="$(cat "$GH_STUB_CWD" 2>/dev/null)"
  if [ "$got" = "$R_NONE" ]; then ok "R4 gh ran inside the --repo dir"; else no "R4 gh ran in [$got], want [$R_NONE]"; fi
  GH_STUB_OUT=''

  # X — usage
  refused "$s" "X1 unknown argument" 2 - "$P_GHFAIL" "$R_DEV" --nope
  refused "$s" "X2 --flag with no value" 2 - "$P_GHFAIL" "$R_DEV" --flag
  refused "$s" "X3 --repo is not a directory" 2 - "$P_GHFAIL" "$R_DEV" --repo "$TMP/no-such-dir"
}

echo "test-resolve-base-branch.sh"
run_table "$SCRIPT"

# K — mutation controls: each mutant must turn at least one case red.
mutant() {
  local name="$1" expr="$2" m="$TMP/mut-$1.sh"
  sed -e "$expr" "$SCRIPT" > "$m"
  if [ ! -s "$m" ] || cmp -s "$m" "$SCRIPT" || ! bash -n "$m" 2>/dev/null; then
    no "K $name — mutant did not apply"; return 1
  fi
  printf '%s' "$m"
}
for spec in \
  'unresolved-prints-a-branch|s/^fail_unresolved$/emit main fallback/' \
  'config-not-validated|/valid_branch "\$v" || fail_invalid config/d' \
  'no-set-head|/GIT_TERMINAL_PROMPT=0 git -C "\$REPO" remote set-head origin -a/d' \
  'config-before-flag|s/^step_flag$/step_SWAP/;s/^step_config$/step_flag/;s/^step_SWAP$/step_config/' \
  'no-brief-step|/^step_brief$/d' \
  'explain-without-source|s/ (source: %s)//'; do
  name="${spec%%|*}"; expr="${spec#*|}"
  m="$(mutant "$name" "$expr")" || continue
  saved_pass=$pass; saved_fail=$fail
  mout="$(run_table "$m")"
  pass=$saved_pass; fail=$saved_fail
  reds="$(printf '%s\n' "$mout" | grep -c '  FAIL: ' || true)"
  if [ "${reds:-0}" -ge 1 ]; then ok "K $name — mutant turns $reds case(s) red"; else no "K $name — mutant SURVIVED the table"; fi
done

echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
