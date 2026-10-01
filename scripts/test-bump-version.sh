#!/usr/bin/env bash
# test-bump-version.sh — hermetic self-test for scripts/bump-version.sh and the bump-without-script
# guard in scripts/check-doc-currency.sh (parallel-automate item 01).
#
# Every case runs in a throwaway git repo under a temp dir; the checked-in repo is never written.
# Fixture manifests mirror the real layout, including the stackpack / mysql-mcp descriptions'
# six-character — escapes — the bytes a `jq .` round-trip would silently re-encode.
#
# The post-write validators are injected through bump-version.sh's BUMP_VERSION_VALIDATORS seam
# (real validate-version.sh + a stub for the doc-currency gate, which needs the whole plugin tree);
# the guard cases at the end instead run the REAL check-doc-currency.sh against a git copy of the
# tracked tree.
#
# Root caveat: the read-only-directory controls need a non-root user (root ignores directory
# permissions); under root they are reported as SKIP, never as a pass.
#
# Portability: bash 3.2 (macOS /bin/bash) and GNU bash; no sed -i, no mapfile.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../loomwright/scripts/hermetic-test-env.sh"
set -uo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
BUMP="$repo_root/scripts/bump-version.sh"
VALIDATE="$repo_root/scripts/validate-version.sh"
GATE="$repo_root/scripts/check-doc-currency.sh"
for f in "$BUMP" "$VALIDATE" "$GATE"; do [ -f "$f" ] || { echo "FAIL: missing $f" >&2; exit 1; }; done
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq required" >&2; exit 1; }

pass=0; fail=0; skip=0
ok()   { pass=$((pass + 1)); echo "ok   - $1"; }
no()   { fail=$((fail + 1)); echo "FAIL - $1"; }
skp()  { skip=$((skip + 1)); echo "SKIP - $1"; }
check() { if [ "$1" -eq 0 ]; then ok "$2"; else no "$2"; fi; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/bump-version-test.XXXXXX")"
cleanup() { chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
export LC_ALL=C
BS="$(printf '\\')"   # one backslash

g() { local d="$1"; shift; git -C "$d" -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false "$@"; }

# Validators used by the bump cases: the real validate-version.sh + a passing stub.
export BUMP_VERSION_VALIDATORS="scripts/validate-version.sh:scripts/ok-validator.sh"

PJ="loomwright/.claude-plugin/plugin.json"
MJ=".claude-plugin/marketplace.json"
CL="CHANGELOG.md"

# make_fixture <dir> — a git repo at version 1.2.3 with the real script copied in, committed.
make_fixture() {
  local d="$1"
  mkdir -p "$d/loomwright/.claude-plugin" "$d/.claude-plugin" "$d/stackpack/.claude-plugin" \
           "$d/mysql-mcp/.claude-plugin" "$d/scripts" "$d/changelog.d"
  cat > "$d/$PJ" <<'EOF'
{
  "name": "loomwright",
  "version": "1.2.3",
  "description": "Fixture plugin."
}
EOF
  echo '{"name":"stackpack","version":"1.0.0"}' > "$d/stackpack/.claude-plugin/plugin.json"
  echo '{"name":"mysql-mcp","version":"1.0.1"}' > "$d/mysql-mcp/.claude-plugin/plugin.json"
  cat > "$d/$MJ" <<'EOF'
{
  "name": "atelier",
  "owner": {
    "name": "fixture owner"
  },
  "plugins": [
    {
      "name": "loomwright",
      "source": "./loomwright",
      "description": "Fixture loomwright card.",
      "version": "1.2.3",
      "author": {
        "name": "fixture owner"
      }
    },
    {
      "name": "stackpack",
      "source": "./stackpack",
      "description": "Stackpack v1.0.0 EMESC reference skills.",
      "version": "1.0.0",
      "author": {
        "name": "fixture owner"
      }
    },
    {
      "name": "mysql-mcp",
      "source": "./mysql-mcp",
      "description": "Mysql-mcp v1.0.1 EMESC read-only MySQL MCP server.",
      "version": "1.0.1",
      "author": {
        "name": "fixture owner"
      }
    }
  ]
}
EOF
  # The escape is spliced in at run time: it must never appear literally in this file's source.
  sed "s/EMESC/${BS}${BS}u2014/" "$d/$MJ" > "$d/mj.tmp" && mv "$d/mj.tmp" "$d/$MJ"
  cat > "$d/$CL" <<'EOF'
# Changelog

Header paragraph one.

> Header paragraph two — entries are historical.

**v1.2.3 — previous release:** previous body.

**v1.2.2 — older release:** older body.
EOF
  printf 'Fragments live here.\n' > "$d/changelog.d/README.md"
  cp "$BUMP" "$d/scripts/bump-version.sh"
  cp "$VALIDATE" "$d/scripts/validate-version.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/scripts/ok-validator.sh"
  git init -q "$d" && git -C "$d" symbolic-ref HEAD refs/heads/main
  g "$d" add -A && g "$d" commit -q -m base
}

frag() { printf '%b' "$3" > "$1/changelog.d/$2"; }   # frag <dir> <name> <content>
run_bump() { local d="$1"; shift; ( cd "$d" && bash scripts/bump-version.sh "$@" ) > "$TMP/last.out" 2>&1; }
ver_of() { # ver_of <dir> -> "plugin marketplace changelog"
  local d="$1"
  echo "$(jq -r .version "$d/$PJ") $(jq -r '.plugins[]|select(.name=="loomwright")|.version' "$d/$MJ") $(grep -m1 -E '^\*\*v[0-9]' "$d/$CL" | sed -E 's/^\*\*v([0-9.]+) .*/\1/')"
}
snapshot() { cat "$1/$PJ" "$1/$MJ" "$1/$CL" | cksum; }          # the three files' bytes
tree_sum() { ( cd "$1" && find . -path ./.git -prune -o -type f -print | sort | xargs cksum ) | cksum; }

# The two marketplace properties AC1 / AC6 assert, as functions so the jq control reuses them.
mkt_one_line() { # <dir>: exactly one changed line, and it is the loomwright version line
  local d="$1" n
  n="$(g "$d" diff --numstat HEAD -- "$MJ" | awk '{print $1 "+" $2}')"
  [ "$n" = "1+1" ] && grep -qE '^\+[[:space:]]*"version": "' < <(g "$d" diff -U0 HEAD -- "$MJ")
}
mkt_others_unchanged() { # <dir>: the stackpack + mysql-mcp text is byte-identical to HEAD
  local d="$1"
  [ "$(g "$d" show "HEAD:$MJ" | sed -n '/"name": "stackpack"/,$p' | cksum)" = "$(sed -n '/"name": "stackpack"/,$p' "$d/$MJ" | cksum)" ]
}

echo "# bump-version.sh"

# ---- 1. patch (default) arithmetic + three files agree + AC1 diff shape ---------------------
D="$TMP/t1"; make_fixture "$D"; frag "$D" fix.md 'Fix a thing\nThe body.\n'
g "$D" add -A && g "$D" commit -q -m "feature PR carries only its fragment"
run_bump "$D"; rc=$?
check $rc "patch: no level and no directive bumps (exit 0)"
[ "$(ver_of "$D")" = "1.2.4 1.2.4 1.2.4" ]; check $? "patch: 1.2.3 -> 1.2.4 in all three files"
( cd "$D" && bash scripts/validate-version.sh >/dev/null 2>&1 ); check $? "patch: validate-version.sh agrees afterwards"
[ "$(g "$D" status --porcelain | awk '{print $2}' | sort | tr '\n' ' ')" = ".claude-plugin/marketplace.json CHANGELOG.md changelog.d/fix.md loomwright/.claude-plugin/plugin.json " ]
check $? "AC1: the diff touches exactly the two manifests, CHANGELOG.md and the removed fragment"
mkt_one_line "$D"; check $? "AC1: marketplace.json diff is exactly ONE line (the loomwright version)"
mkt_others_unchanged "$D"; check $? "AC1: stackpack + mysql-mcp entries byte-unchanged"
[ "$(g "$D" diff --numstat HEAD -- "$PJ" | awk '{print $1 "+" $2}')" = "1+1" ]; check $? "plugin.json diff is exactly one line"
[ "$(grep -cF "${BS}u2014" "$D/$MJ")" = "2" ]; check $? "both backslash-u-2014 escapes survive the bump"
[ -z "$(find "$D" -maxdepth 1 -name '.bump-version.*')" ]; check $? "no scratch dir left behind"

# ---- 2. minor / major arithmetic; explicit argument beats the fragment request ---------------
D="$TMP/t2"; make_fixture "$D"; frag "$D" x.md 'X\n'
run_bump "$D" minor; [ "$(ver_of "$D")" = "1.3.0 1.3.0 1.3.0" ]; check $? "minor: 1.2.3 -> 1.3.0"
D="$TMP/t3"; make_fixture "$D"; frag "$D" x.md 'X\n'
run_bump "$D" major; [ "$(ver_of "$D")" = "2.0.0 2.0.0 2.0.0" ]; check $? "major: 1.2.3 -> 2.0.0"
D="$TMP/t3b"; make_fixture "$D"; frag "$D" x.md '<!-- bump: major -->\nX\n'
run_bump "$D" patch; [ "$(ver_of "$D")" = "1.2.4 1.2.4 1.2.4" ]; check $? "an explicit argument wins over a fragment's directive"

# ---- 3. highest <!-- bump: X --> wins; fold in filename order; header untouched -------------
D="$TMP/t4"; make_fixture "$D"
frag "$D" b-second.md '<!-- bump: minor -->\nSecond headline:\nsecond body\nmore second\n'
frag "$D" a-first.md '<!-- bump: patch -->\nFirst headline\n\nfirst body\n'
frag "$D" c-third.md 'Third headline\n'
run_bump "$D"; rc=$?
check $rc "fold: three fragments bump (exit 0)"
[ "$(ver_of "$D")" = "1.3.0 1.3.0 1.3.0" ]; check $? "fold: the highest requested level (minor) wins over patch / default"
[ "$(sed -n 7p "$D/$CL")" = "**v1.3.0 — First headline; Second headline; Third headline:** first body second body more second" ]
check $? "fold: ONE entry, fragments in filename order, in the **vX.Y.Z — headline:** body shape"
[ "$(sed -n 8p "$D/$CL")" = "" ] && [ "$(sed -n 9p "$D/$CL")" = "**v1.2.3 — previous release:** previous body." ]
check $? "fold: the new entry sits directly above the previous newest entry"
[ "$(sed -n 1,6p "$D/$CL" | cksum)" = "$(g "$D" show "HEAD:$CL" | sed -n 1,6p | cksum)" ]; check $? "fold: header paragraphs byte-unchanged"
[ ! -e "$D/changelog.d/a-first.md" ] && [ ! -e "$D/changelog.d/b-second.md" ] && [ ! -e "$D/changelog.d/c-third.md" ] && [ -f "$D/changelog.d/README.md" ]
check $? "fold: folded fragments deleted, changelog.d/README.md kept"
D="$TMP/t4b"; make_fixture "$D"; frag "$D" a.md '<!-- bump: minor -->\nA\n'; frag "$D" b.md '<!-- bump: major -->\nB\n'
run_bump "$D"; [ "$(ver_of "$D")" = "2.0.0 2.0.0 2.0.0" ]; check $? "fold: a major request beats a minor one"

# ---- 4. refusals leave everything byte-unchanged --------------------------------------------
D="$TMP/t5"; make_fixture "$D"; before="$(tree_sum "$D")"
run_bump "$D"; rc=$?
[ "$rc" -eq 1 ] && [ "$(tree_sum "$D")" = "$before" ] && [ -z "$(g "$D" status --porcelain)" ]
check $? "no fragment: exit 1, nothing written (git status empty)"
grep -q 'no changelog fragment' "$TMP/last.out"; check $? "no fragment: the refusal names the cause"

D="$TMP/t6"; make_fixture "$D"
sed 's/"version": "1.2.3"/"version": "1.2.9"/' "$D/$MJ" > "$D/mj.tmp" && mv "$D/mj.tmp" "$D/$MJ"
g "$D" commit -q -am disagree; frag "$D" x.md 'X\n'; before="$(tree_sum "$D")"
run_bump "$D"; rc=$?
[ "$rc" -eq 1 ] && [ "$(tree_sum "$D")" = "$before" ]; check $? "pre-existing manifest disagreement: exit 1, nothing written"
D="$TMP/t6b"; make_fixture "$D"
sed 's/^\*\*v1\.2\.3 /**v1.2.8 /' "$D/$CL" > "$D/cl.tmp" && mv "$D/cl.tmp" "$D/$CL"
g "$D" commit -q -am disagree; frag "$D" x.md 'X\n'; before="$(tree_sum "$D")"
run_bump "$D"; rc=$?
[ "$rc" -eq 1 ] && [ "$(tree_sum "$D")" = "$before" ]; check $? "pre-existing CHANGELOG disagreement: exit 1, nothing written"

D="$TMP/t6c"; make_fixture "$D"; frag "$D" x.md '<!-- bump: huge -->\nX\n'; before="$(tree_sum "$D")"
run_bump "$D"; rc=$?
[ "$rc" -eq 1 ] && [ "$(tree_sum "$D")" = "$before" ]; check $? "unknown bump level in a fragment: exit 1, nothing written"

# ---- 5. --dry-run writes nothing ---------------------------------------------------------------
D="$TMP/t7"; make_fixture "$D"; frag "$D" x.md '<!-- bump: minor -->\nDry headline\nbody\n'; before="$(tree_sum "$D")"
run_bump "$D" --dry-run; rc=$?
[ "$rc" -eq 0 ] && [ "$(tree_sum "$D")" = "$before" ]; check $? "--dry-run: exit 0 and the tree is unchanged (fragment kept)"
grep -q '1.2.3 -> 1.3.0' "$TMP/last.out" && grep -qF '**v1.3.0 — Dry headline:** body' "$TMP/last.out"
check $? "--dry-run: prints the planned version and entry"

# ---- 6. mutation control: read-only .claude-plugin/ DIRECTORY ⇒ no half bump -----------------
probe="$TMP/roprobe"; mkdir -p "$probe"; chmod 555 "$probe"
if ( : > "$probe/x" ) 2>/dev/null; then
  skp "read-only-directory controls (running as root: directory permissions are not enforced)"
else
  for ro in .claude-plugin loomwright/.claude-plugin; do
    D="$TMP/t8-$(echo "$ro" | tr '/.' '__')"; make_fixture "$D"; frag "$D" x.md 'X\n'
    snap="$(snapshot "$D")"; fsum="$(cksum < "$D/changelog.d/x.md")"
    chmod 555 "$D/$ro"
    run_bump "$D"; rc=$?
    chmod 755 "$D/$ro"
    [ "$rc" -eq 1 ] && [ "$(snapshot "$D")" = "$snap" ] && [ "$(cksum < "$D/changelog.d/x.md" 2>/dev/null)" = "$fsum" ] \
      && [ -z "$(g "$D" status --porcelain -- "$PJ" "$MJ" "$CL")" ] && [ -z "$(find "$D" -maxdepth 1 -name '.bump-version.*')" ]
    check $? "read-only $ro/ directory: exit 1, all three files AND the fragment byte-unchanged"
  done
  grep -q 'restored' "$TMP/last.out"; check $? "read-only directory: the rename-phase failure reports the restore"
fi
chmod 755 "$probe"

# ---- 7. a validator failing AFTER the rename restores the three files AND the fragments -------
D="$TMP/t9"; make_fixture "$D"; frag "$D" a.md 'A\n'; frag "$D" b.md 'B\n'
cat > "$D/scripts/bad-validator.sh" <<'EOF'
#!/usr/bin/env bash
# Records what it saw (proves it ran AFTER the rename and the fragment deletion), then fails.
echo "$(jq -r .version loomwright/.claude-plugin/plugin.json) $(ls changelog.d | tr '\n' ' ')" > validator-saw.txt
exit 1
EOF
g "$D" add -A && g "$D" commit -q -m bad
snap="$(snapshot "$D")"; fsum="$(cat "$D/changelog.d/a.md" "$D/changelog.d/b.md" | cksum)"
( cd "$D" && BUMP_VERSION_VALIDATORS="scripts/validate-version.sh:scripts/bad-validator.sh" bash scripts/bump-version.sh ) > "$TMP/last.out" 2>&1; rc=$?
[ "$(cat "$D/validator-saw.txt" 2>/dev/null)" = "1.2.4 README.md " ]; check $? "validator failure: the validator ran after the rename and the fragment deletion"
[ "$rc" -eq 1 ] && [ "$(snapshot "$D")" = "$snap" ] && [ "$(cat "$D/changelog.d/a.md" "$D/changelog.d/b.md" 2>/dev/null | cksum)" = "$fsum" ]
check $? "validator failure: exit 1, the three files restored AND both fragments re-created byte-identical"
rm -f "$D/validator-saw.txt"; [ -z "$(g "$D" status --porcelain)" ]; check $? "validator failure: git status clean afterwards"

# ---- 8. two branches, each adding only its own fragment, merge with no conflict ---------------
D="$TMP/t10"; make_fixture "$D"
g "$D" checkout -q -b lane-a && frag "$D" lane-a.md 'Lane A\n' && g "$D" add -A && g "$D" commit -q -m a
g "$D" checkout -q main && g "$D" checkout -q -b lane-b && frag "$D" lane-b.md 'Lane B\n' && g "$D" add -A && g "$D" commit -q -m b
g "$D" checkout -q lane-a && g "$D" merge -q --no-edit lane-b >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ -f "$D/changelog.d/lane-a.md" ] && [ -f "$D/changelog.d/lane-b.md" ]
check $? "two fragment-only branches from one base merge into each other with no conflict"
run_bump "$D"; [ "$(sed -n 7p "$D/$CL")" = "**v1.2.4 — Lane A; Lane B:**" ]; check $? "the merged fragments fold into one bump"

# ---- 9. `jq .` mutation control (Validation 4) --------------------------------------------------
# Swap the targeted edit for a `jq` round-trip. With the script's own one-line self-check also
# neutralized, the bump completes — and BOTH AC1 assertions above must now turn red. With the
# self-check left in place, the script itself refuses and writes nothing.
[ "$(g "$TMP/t1" show "HEAD:$MJ" | grep -cF "${BS}u2014")" = "2" ]; check $? "jq control precondition: the fixture carries two backslash-u-2014 escapes"
mutate() { # mutate <dir> <also-neutralize-selfcheck 0|1>
  awk -v neutral="$2" '
    /^# ---- 2\.\.6/ && !done {
      print "render_marketplace() { jq --arg v \"$new_ver\" \x27(.plugins[] | select(.name == \"loomwright\") | .version) = $v\x27 \"$1\" > \"$2\"; }"
      if (neutral == 1) print "verify_marketplace_edit() { return 0; }"
      done = 1
    }
    { print }' "$BUMP" > "$1/scripts/bump-version.sh"
}
D="$TMP/t11"; make_fixture "$D"; mutate "$D" 1; frag "$D" x.md 'X\n'
run_bump "$D"; rc=$?
if [ "$rc" -eq 0 ] && ! mkt_one_line "$D" && ! mkt_others_unchanged "$D"; then
  ok "jq control: a jq round-trip makes BOTH the one-changed-line and the byte-unchanged assertions fail"
else
  no "jq control: expected rc=0 with both assertions red (rc=$rc; one-line=$(mkt_one_line "$D" && echo green || echo red); others=$(mkt_others_unchanged "$D" && echo green || echo red))"
fi
D="$TMP/t11b"; make_fixture "$D"; mutate "$D" 0; frag "$D" x.md 'X\n'; before="$(tree_sum "$D")"
run_bump "$D"; rc=$?
[ "$rc" -eq 1 ] && [ "$(tree_sum "$D")" = "$before" ]; check $? "jq control: the script's own self-check refuses a jq round-trip and writes nothing"

# ---- 10. check-doc-currency.sh bump-without-script guard (AC5) ----------------------------------
echo "# check-doc-currency.sh bump-fragment-guard"
G="$TMP/guard"; mkdir -p "$G"
( cd "$repo_root" && git ls-files ) | while IFS= read -r f; do [ -f "$repo_root/$f" ] && printf '%s\n' "$f"; done > "$TMP/files.lst"
( cd "$repo_root" && tar -cf - -T "$TMP/files.lst" ) | ( cd "$G" && tar -xf - )
cp "$GATE" "$G/scripts/check-doc-currency.sh"
rm -rf "$G/changelog.d"; mkdir -p "$G/changelog.d"; printf 'Fragments live here.\n' > "$G/changelog.d/README.md"
git init -q "$G" && g "$G" symbolic-ref HEAD refs/heads/main && g "$G" add -A -f && g "$G" commit -q -m base
g "$G" update-ref refs/remotes/origin/main HEAD
gate() { ( cd "$G" && bash "${1:-scripts/check-doc-currency.sh}" ) > "$TMP/gate.out" 2>&1; }
base_ver="$(jq -r .version "$G/$PJ")"
set_ver() { jq --arg v "$1" '.version = $v' "$G/$PJ" > "$G/pj.tmp" && mv "$G/pj.tmp" "$G/$PJ"; }

gate; rc=$?
[ "$rc" -eq 0 ] && ! grep -q 'bump-fragment-guard' "$TMP/gate.out"; check $? "guard: the unchanged tree passes"

# Merely BEHIND: main bumps after the fork; the branch carries only a fragment.
g "$G" checkout -q -b behind && printf 'Behind\n' > "$G/changelog.d/behind.md" && g "$G" add -A && g "$G" commit -q -m frag
g "$G" checkout -q main && set_ver 99.0.0 && g "$G" commit -q -am "main bumps" && g "$G" update-ref refs/remotes/origin/main HEAD
g "$G" checkout -q behind
gate; rc=$?
[ "$rc" -eq 0 ] && ! grep -q 'DRIFT \[bump-fragment-guard\]' "$TMP/gate.out"; check $? "guard: a merely-behind branch with a fragment stays green"

# THIS branch changed the version (uncommitted hand bump) with a fragment present.
set_ver 98.0.0
gate; rc=$?
[ "$rc" -eq 1 ] && grep -q 'DRIFT \[bump-fragment-guard\]' "$TMP/gate.out"; check $? "guard: a hand bump with a fragment present FAILS"
# Control: delete the single invocation line from a copy — the same case must now pass silently.
grep -v '^run_bump_fragment_guard || fail=1$' "$G/scripts/check-doc-currency.sh" > "$G/scripts/nog.sh"
[ "$(grep -c '^run_bump_fragment_guard || fail=1$' "$G/scripts/check-doc-currency.sh")" = "1" ]; check $? "guard control precondition: exactly one invocation line"
gate scripts/nog.sh; rc=$?
[ "$rc" -eq 0 ] && ! grep -q 'bump-fragment-guard' "$TMP/gate.out"; check $? "guard control: with the guard removed the hand bump goes undetected (the guard is what catches it)"
rm -f "$G/scripts/nog.sh"

# A scripted bump leaves no fragment: green even though the version changed.
rm -f "$G/changelog.d/behind.md"
gate; rc=$?
[ "$rc" -eq 0 ]; check $? "guard: a changed version with no fragment left passes (the honest limit)"

# origin/main unresolvable ⇒ visible skip note, not a failure.
printf 'Again\n' > "$G/changelog.d/again.md"
g "$G" update-ref -d refs/remotes/origin/main
gate; rc=$?
[ "$rc" -eq 0 ] && grep -q 'NOTE \[bump-fragment-guard\] skipped' "$TMP/gate.out"; check $? "guard: unresolvable origin/main skips with a visible note"
set_ver "$base_ver"

echo
echo "RESULT: $pass passed, $fail failed, $skip skipped"
[ "$fail" -eq 0 ] || exit 1
exit 0
