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
BUMP="${BUMP_VERSION_UNDER_TEST:-$repo_root/scripts/bump-version.sh}"   # override: run this suite against another copy (before/after evidence)
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

# One case per remaining refusal path. Each fixture is otherwise bumpable (a well-formed fragment
# is present where the refusal is not about fragments), so ONLY the named guard can stop it — and
# each input is chosen so that, with that guard deleted, the bump would go through or fail with a
# DIFFERENT message, which the message assertion then catches. tree_sum covers the three version
# files and every fragment.
refusal() { # refusal <dir> <fixed-string refusal message> <label>
  local d="$1" msg="$2" label="$3" before rc
  before="$(tree_sum "$d")"
  run_bump "$d"; rc=$?
  [ "$rc" -eq 1 ] && [ "$(tree_sum "$d")" = "$before" ] && [ -z "$(g "$d" status --porcelain -- "$PJ" "$MJ" "$CL")" ] \
    && [ -z "$(find "$d" -maxdepth 1 -name '.bump-version.*')" ]
  check $? "$label: exit 1, three files + fragments byte-unchanged"
  grep -qF -- "$msg" "$TMP/last.out"; check $? "$label: the refusal names the cause ('$msg')"
}

D="$TMP/t6d"; make_fixture "$D"; frag "$D" x.md 'Headline\n<!-- bump: minor -->\nbody\n'
refusal "$D" "malformed bump directive" "bump directive on a later line"

D="$TMP/t6e"; make_fixture "$D"; frag "$D" x.md '<!-- bump: minor -->\n## :\nbody\n'
refusal "$D" "x.md: empty headline" "headline empty after stripping '#' and ':'"

D="$TMP/t6f"; make_fixture "$D"; frag "$D" x.md '<!-- bump: minor -->\n\n'
refusal "$D" "x.md: fragment has no headline" "fragment with only a bump directive"

D="$TMP/t6g"; make_fixture "$D"
sed 's/"name": "loomwright"/"name": "loomwright-renamed"/' "$D/$MJ" > "$D/mj.tmp" && mv "$D/mj.tmp" "$D/$MJ"
g "$D" commit -q -am "no loomwright entry"; frag "$D" x.md 'X\n'
refusal "$D" "must list exactly one loomwright plugin (found 0)" "marketplace.json with no loomwright entry"

D="$TMP/t6h"; make_fixture "$D"
jq '.plugins += [.plugins[0]]' "$D/$MJ" > "$D/mj.tmp" && mv "$D/mj.tmp" "$D/$MJ"
g "$D" commit -q -am "two loomwright entries"; frag "$D" x.md 'X\n'
refusal "$D" "must list exactly one loomwright plugin (found 2)" "marketplace.json with two loomwright entries"

D="$TMP/t6i"; make_fixture "$D"
sed 's/^\*\*v\([0-9]\)/**release \1/' "$D/$CL" > "$D/cl.tmp" && mv "$D/cl.tmp" "$D/$CL"
g "$D" commit -q -am "no entry"; frag "$D" x.md 'X\n'
[ -z "$(grep -E '^\*\*v[0-9]' "$D/$CL")" ]; check $? "no-entry precondition: the fixture CHANGELOG carries no **vX.Y.Z entry"
refusal "$D" "has no '**vX.Y.Z" "CHANGELOG.md with no version entry"

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

# ---- 9b. the generated capability contract (loomwright/capabilities.json) is refreshed by the bump --
# capabilities.json restates plugin_version; bump-version.sh is the version's sole writer, so it must
# regenerate the contract (with the REAL generator) in the same bump, and restore it on any failure.
CJ="loomwright/capabilities.json"
GEN_SRC="$repo_root/loomwright/scripts/build-capabilities.sh"
# make_caps_fixture <dir> — make_fixture + a minimal plugin tree, the real generator, and a current contract.
make_caps_fixture() {
  local d="$1"
  make_fixture "$d"
  mkdir -p "$d/loomwright/scripts" "$d/loomwright/hooks" "$d/loomwright/agents" "$d/loomwright/commands" \
           "$d/loomwright/skills/s" "$d/loomwright/docs/result-schemas"
  cp "$GEN_SRC" "$d/loomwright/scripts/build-capabilities.sh"
  printf '{"hooks": {}}\n' > "$d/loomwright/hooks/hooks.json"
  printf '# Index\n\n## FIX_RESULT\n\nSee [result-schemas/fix.md](result-schemas/fix.md).\n' > "$d/loomwright/docs/RESULT_SCHEMAS.md"
  printf '# FIX_RESULT\n\nschema_version: 1\n' > "$d/loomwright/docs/result-schemas/fix.md"
  printf -- '---\nname: loomwright:a\ntools: Read, Bash\n---\nFIX_RESULT:\n' > "$d/loomwright/agents/a.md"
  printf -- '---\ndescription: c\n---\nbody\n' > "$d/loomwright/commands/c.md"
  printf -- '---\nname: s\n---\nbody\n' > "$d/loomwright/skills/s/SKILL.md"
  ( cd "$d" && bash loomwright/scripts/build-capabilities.sh ) || return 1
  g "$d" add -A && g "$d" commit -q -m "capability contract"
}
caps_snap() { cat "$1/$PJ" "$1/$MJ" "$1/$CL" "$1/$CJ" | cksum; }

D="$TMP/t12"; make_caps_fixture "$D"
[ "$(jq -r .plugin_version "$D/$CJ")" = "1.2.3" ]; check $? "caps precondition: the fixture contract is generated and at 1.2.3"
frag "$D" x.md 'X\n'; g "$D" add -A && g "$D" commit -q -m "feature PR carries only its fragment"
run_bump "$D"; rc=$?
check $rc "caps: a bump with a capability contract present succeeds (exit 0)"
[ "$(jq -r .plugin_version "$D/$CJ")" = "1.2.4" ]; check $? "caps: capabilities.json plugin_version follows the bump (1.2.4)"
( cd "$D" && bash loomwright/scripts/build-capabilities.sh --check ) >/dev/null 2>&1; check $? "caps: build-capabilities.sh --check passes right after the bump (no red CI on release)"
[ "$(g "$D" diff --numstat HEAD -- "$CJ" | awk '{print $1 "+" $2}')" = "1+1" ]; check $? "caps: capabilities.json diff is exactly one line (plugin_version)"
[ "$(g "$D" status --porcelain | awk '{print $2}' | sort | tr '\n' ' ')" = ".claude-plugin/marketplace.json CHANGELOG.md changelog.d/x.md loomwright/.claude-plugin/plugin.json loomwright/capabilities.json " ]
check $? "caps: the bump touches the two manifests, CHANGELOG.md, the contract and the fragment — nothing else"
grep -qF 'CHANGELOG.md, capabilities.json, removed fragments' "$TMP/last.out"; check $? "caps: the 'next:' line tells the operator to commit capabilities.json too"
[ -z "$(find "$D" -maxdepth 1 -name '.bump-version.*')" ]; check $? "caps: no scratch dir (or shadow-root symlink) left behind"

# A contract that is ALREADY stale before the bump is refused, never silently folded into the bump commit.
D="$TMP/t13"; make_caps_fixture "$D"
printf -- '---\nname: loomwright:b\ntools: Read\n---\nbody\n' > "$D/loomwright/agents/b.md"
g "$D" add -A && g "$D" commit -q -m "agent added without regenerating the contract"; frag "$D" x.md 'X\n'
before="$(tree_sum "$D")"; run_bump "$D"; rc=$?
[ "$rc" -eq 1 ] && [ "$(tree_sum "$D")" = "$before" ] && [ -z "$(find "$D" -maxdepth 1 -name '.bump-version.*')" ]
check $? "caps: a contract stale BEFORE the bump: exit 1, nothing written"
grep -qF 'the committed contract is stale' "$TMP/last.out"; check $? "caps: the stale-contract refusal names the cause"

# Exactly one of contract / generator present => refused (the restated copy cannot drop out of the bump).
D="$TMP/t14"; make_caps_fixture "$D"; g "$D" rm -q "$CJ" && g "$D" commit -q -m "contract lost"; frag "$D" x.md 'X\n'
refusal "$D" "exactly one of $CJ" "generator present, capabilities.json missing"

# A validator failing AFTER the rename restores capabilities.json byte-identical too.
D="$TMP/t15"; make_caps_fixture "$D"; frag "$D" x.md 'X\n'
printf '#!/usr/bin/env bash\nexit 1\n' > "$D/scripts/bad-validator.sh"; g "$D" add -A && g "$D" commit -q -m bad
snap="$(caps_snap "$D")"; fsum="$(cksum < "$D/changelog.d/x.md")"
( cd "$D" && BUMP_VERSION_VALIDATORS="scripts/bad-validator.sh" bash scripts/bump-version.sh ) > "$TMP/last.out" 2>&1; rc=$?
[ "$rc" -eq 1 ] && [ "$(caps_snap "$D")" = "$snap" ] && [ "$(cksum < "$D/changelog.d/x.md" 2>/dev/null)" = "$fsum" ] && [ -z "$(g "$D" status --porcelain)" ]
check $? "caps: validator failure restores plugin.json, marketplace.json, CHANGELOG.md AND capabilities.json byte-identical"

# --dry-run names the contract and writes nothing.
D="$TMP/t16"; make_caps_fixture "$D"; frag "$D" x.md 'X\n'; before="$(tree_sum "$D")"
run_bump "$D" --dry-run; rc=$?
[ "$rc" -eq 0 ] && [ "$(tree_sum "$D")" = "$before" ] && grep -qF "also regenerates: $CJ" "$TMP/last.out"
check $? "caps: --dry-run names the regenerated contract and writes nothing"

# ---- 9c. --check: the content rule (#512) ------------------------------------------------------
# P7's invariant is the CONTENT of the version files, not the position of the bump commit. Each case
# is a branch off a base that origin/main points at, so the merge base is real.
echo "# bump-version.sh --check (content rule) and the re-fold"
run_check() { local d="$1"; shift; ( cd "$d" && bash scripts/bump-version.sh --check "$@" ) > "$TMP/last.out" 2>&1; }
# make_branch <dir> — fixture + origin/main at the base + a feature branch carrying fragment a.md.
make_branch() {
  make_fixture "$1"
  g "$1" update-ref refs/remotes/origin/main HEAD
  g "$1" checkout -q -b feature
  frag "$1" a.md 'Alpha headline\nAlpha body.\n'
  echo "feature code" > "$1/feature.txt"
  g "$1" add -A && g "$1" commit -q -m "feature + its fragment"
}
bump_commit() { run_bump "$1" "${@:2}" && g "$1" add -A && g "$1" commit -q -m "chore(release): bump"; }
entries() { grep -cE '^\*\*v[0-9]+\.[0-9]+\.[0-9]+ — ' "$1/$CL"; }   # CHANGELOG entry count
expect_fail() { # expect_fail <dir> <fixed message> <label>
  run_check "$1"; local rc=$?
  [ "$rc" -eq 1 ] && grep -qF 'check FAILED' "$TMP/last.out" && grep -qF -- "$2" "$TMP/last.out"
  check $? "$3 (exit 1, names: $2)"
}

D="$TMP/c1"; make_branch "$D"
run_check "$D"; rc=$?
[ "$rc" -eq 0 ] && grep -qF 'check OK — not bumped (version 1.2.3' "$TMP/last.out"; check $? "check: a fragment-only branch is consistent (not bumped, 1 pending — legal)"
bump_commit "$D"
run_check "$D"; rc=$?
[ "$rc" -eq 0 ] && grep -qF 'check OK — bumped 1.2.3 -> 1.2.4 (patch); the entry is the fold of: a.md' "$TMP/last.out"; check $? "check: a correct scripted bump passes and names the folded fragment"
# The #367 shape: heal / drain commits land AFTER the bump and touch no release file.
echo "heal fix 1" >> "$D/feature.txt"; g "$D" commit -q -am "fix: address review feedback (iteration 1)"
echo "heal fix 2" >> "$D/feature.txt"; g "$D" commit -q -am "fix: address drain review feedback (round 1)"
[ "$(g "$D" log -1 --format=%s)" != "chore(release): bump" ]; check $? "#367 precondition: the bump commit is NOT the last commit"
run_check "$D"; rc=$?
[ "$rc" -eq 0 ] && grep -qF 'check OK — bumped 1.2.3 -> 1.2.4' "$TMP/last.out"; check $? "check: the #367 shape (bump not last, content right) passes"

# Right after the script ran, before the commit: the working tree is checked (the fragment's text is
# read back from the commit that carried it).
D="$TMP/c1b"; make_branch "$D"; run_bump "$D"
run_check "$D"; rc=$?
[ "$rc" -eq 0 ] && grep -qF 'check OK — bumped 1.2.3 -> 1.2.4' "$TMP/last.out"; check $? "check: an uncommitted fresh bump passes (fragment text read from history)"

# A fragment added after the bump is left unfolded.
D="$TMP/c2"; make_branch "$D"; bump_commit "$D"
frag "$D" b.md 'Late heal fragment\n'; g "$D" add -A && g "$D" commit -q -m "fix: a heal round adds a fragment"
expect_fail "$D" "fragment(s) pending after this branch's bump 1.2.3 -> 1.2.4: changelog.d/b.md" "check: a fragment added after the bump FAILS"
grep -qF 're-run bash scripts/bump-version.sh (it re-folds' "$TMP/last.out"; check $? "check: the pending-fragment finding names the one-command fix"
cp -R "$D" "$TMP/c2-refold"   # reused by the re-fold cases below

# Hand-edited version files.
D="$TMP/c3"; make_branch "$D"; bump_commit "$D"
jq '.version = "1.2.9"' "$D/$PJ" > "$D/pj.tmp" && mv "$D/pj.tmp" "$D/$PJ"; g "$D" commit -q -am "hand edit"
expect_fail "$D" "version 1.2.9 is not one patch/minor/major step above the merge base's 1.2.3" "check: a hand-edited plugin.json version FAILS"
grep -qF "marketplace.json loomwright version 1.2.4 differs from" "$TMP/last.out"; check $? "check: ... and the marketplace mismatch is reported too"
D="$TMP/c3b"; make_branch "$D"
sed 's/"version": "1.2.3"/"version": "1.2.4"/' "$D/$PJ" > "$D/pj.tmp" && mv "$D/pj.tmp" "$D/$PJ"
sed 's/"version": "1.2.3"/"version": "1.2.4"/' "$D/$MJ" > "$D/mj.tmp" && mv "$D/mj.tmp" "$D/$MJ"
awk '!d && /^\*\*v1\.2\.3 / { print "**v1.2.4 — A hand-written entry:** no fragment says this."; print ""; d = 1 } { print }' "$D/$CL" > "$D/cl.tmp" && mv "$D/cl.tmp" "$D/$CL"
rm -f "$D/changelog.d/a.md"; g "$D" add -A && g "$D" commit -q -m "hand bump, consistent across the three files"
( cd "$D" && bash scripts/validate-version.sh >/dev/null 2>&1 ); check $? "hand-bump precondition: the three files agree (validate-version.sh is blind to it)"
expect_fail "$D" "entry is not the fold of any set of fragments this branch carried" "check: a consistent HAND bump (entry no fragment produces) FAILS"
# A hand-reworded entry after a scripted bump.
D="$TMP/c4"; make_branch "$D"; bump_commit "$D"
sed 's/^\*\*v1\.2\.4 — Alpha headline:\*\* Alpha body\./**v1.2.4 — Alpha headline:** Alpha body, reworded by a heal fix./' "$D/$CL" > "$D/cl.tmp" && mv "$D/cl.tmp" "$D/$CL"
g "$D" commit -q -am "fix: reword the changelog entry"
expect_fail "$D" "entry is not the fold of any set of fragments" "check: a hand-reworded CHANGELOG entry after the bump FAILS"
# An older entry edited: CHANGELOG.md is the base's plus exactly the one entry, nothing else.
D="$TMP/c4b"; make_branch "$D"; bump_commit "$D"
sed 's/older body\./older body, edited./' "$D/$CL" > "$D/cl.tmp" && mv "$D/cl.tmp" "$D/$CL"; g "$D" commit -q -am "edit an old entry"
expect_fail "$D" "is not the merge base's plus exactly the one new entry" "check: an edited OLDER entry FAILS"
# Not bumped, but CHANGELOG.md edited by hand; a fragment on the base deleted without a bump.
D="$TMP/c5"; make_branch "$D"
sed 's/previous body\./previous body (edited)./' "$D/$CL" > "$D/cl.tmp" && mv "$D/cl.tmp" "$D/$CL"; g "$D" commit -q -am "hand edit"
expect_fail "$D" "differs from the merge base's but the version did not change" "check: a hand CHANGELOG edit with no bump FAILS"
D="$TMP/c5b"; make_fixture "$D"; frag "$D" onmain.md 'Merged unfolded on main\n'; g "$D" add -A && g "$D" commit -q -m "main merged a fragment"
g "$D" update-ref refs/remotes/origin/main HEAD; g "$D" checkout -q -b feature; g "$D" rm -q changelog.d/onmain.md && g "$D" commit -q -m "lost it"
expect_fail "$D" "changelog.d/onmain.md (on the merge base) was deleted without a bump" "check: deleting main's unfolded fragment without a bump FAILS"
# A bump must fold the base's unfolded fragments too.
D="$TMP/c5c"; make_fixture "$D"; frag "$D" onmain.md 'Merged unfolded on main\n'; g "$D" add -A && g "$D" commit -q -m "main merged a fragment"
g "$D" update-ref refs/remotes/origin/main HEAD; g "$D" checkout -q -b feature; frag "$D" a.md 'Alpha headline\n'; g "$D" add -A && g "$D" commit -q -m frag
bump_commit "$D"
run_check "$D"; rc=$?
[ "$rc" -eq 0 ] && grep -qF 'the entry is the fold of: a.md onmain.md' "$TMP/last.out"; check $? "check: a bump that folded main's unfolded fragment with its own passes"

# capabilities.json drift (the generated copy of the version).
D="$TMP/c6"; make_caps_fixture "$D"; g "$D" update-ref refs/remotes/origin/main HEAD; g "$D" checkout -q -b feature
frag "$D" a.md 'Alpha headline\n'; g "$D" add -A && g "$D" commit -q -m frag; bump_commit "$D"
run_check "$D"; rc=$?
[ "$rc" -eq 0 ]; check $? "check: a scripted bump with a capability contract passes"
set_caps_version_t() { sed "s/\"plugin_version\": \"$2\"/\"plugin_version\": \"$3\"/" "$1/$CJ" > "$1/cj.tmp" && mv "$1/cj.tmp" "$1/$CJ"; }
set_caps_version_t "$D" 1.2.4 1.2.3; g "$D" commit -q -am "caps drift"
expect_fail "$D" "capabilities.json plugin_version 1.2.3 differs from" "check: a capabilities.json plugin_version drift FAILS"
D="$TMP/c6b"; make_caps_fixture "$D"; g "$D" update-ref refs/remotes/origin/main HEAD; g "$D" checkout -q -b feature
set_caps_version_t "$D" 1.2.3 1.2.4; g "$D" commit -q -am "caps hand-bumped alone"
expect_fail "$D" "capabilities.json plugin_version 1.2.4 differs from" "check: a hand-bumped capabilities.json with no bump FAILS"

# Cannot check ⇒ exit 2, fail CLOSED (never a silent pass).
D="$TMP/c7"; make_fixture "$D"
run_check "$D"; rc=$?
[ "$rc" -eq 2 ] && grep -qF "check CANNOT RUN — the base ref 'origin/main' is not resolvable" "$TMP/last.out"; check $? "check: no base ref ⇒ exit 2 (cannot check), never 0"
run_check "$D" --base main; rc=$?
[ "$rc" -eq 0 ]; check $? "check: --base <ref> overrides the default base"
D="$TMP/c7b"; git clone -q --depth 1 "file://$TMP/c1" "$D" 2>/dev/null; g "$D" update-ref refs/remotes/origin/main HEAD
run_check "$D"; rc=$?
[ "$rc" -eq 2 ] && grep -qF 'shallow' "$TMP/last.out"; check $? "check: a shallow clone ⇒ exit 2 (the folded fragments may be missing)"
run_bump "$TMP/c1" --check minor; rc=$?
[ "$rc" -eq 1 ] && grep -qF -- '--check takes no bump level' "$TMP/last.out"; check $? "check: --check refuses a bump level"

# ---- 9d. the re-fold: a re-run on a branch that already carries a bump ----------------------------
D="$TMP/c2-refold"; before_ver="$(ver_of "$D")"
run_bump "$D"; rc=$?
[ "$rc" -eq 0 ] && grep -qF 're-folded this branch' "$TMP/last.out"; check $? "re-fold: a plain re-run over an existing bump with a pending fragment re-folds (exit 0)"
[ "$before_ver" = "1.2.4 1.2.4 1.2.4" ] && [ "$(ver_of "$D")" = "1.2.4 1.2.4 1.2.4" ]; check $? "re-fold: the version stays 1.2.4 — ONE bump, never a double bump"
[ "$(entries "$D")" = "3" ] && [ "$(sed -n 7p "$D/$CL")" = "**v1.2.4 — Alpha headline; Late heal fragment:** Alpha body." ]
check $? "re-fold: exactly ONE new entry, folding the earlier and the late fragment in filename order"
[ ! -e "$D/changelog.d/a.md" ] && [ ! -e "$D/changelog.d/b.md" ]; check $? "re-fold: no fragment left behind"
grep -qF "refold-touched: CHANGELOG.md $PJ $MJ changelog.d/b.md" "$TMP/last.out"; check $? "re-fold: the machine line names exactly the paths to commit"
g "$D" add -A && g "$D" commit -q -m "chore(release): re-fold"
run_check "$D"; rc=$?
[ "$rc" -eq 0 ] && grep -qF 'the entry is the fold of: a.md b.md' "$TMP/last.out"; check $? "re-fold: --check passes on the re-folded branch"
[ -z "$(find "$D" -maxdepth 1 -name '.bump-version.*')" ]; check $? "re-fold: no scratch dir left behind"

# The previous bump's explicit level is kept; a fragment asking for more raises it.
D="$TMP/c8"; make_branch "$D"; bump_commit "$D" minor
frag "$D" b.md 'Late\n'; g "$D" add -A && g "$D" commit -q -m late
run_bump "$D"; [ "$(ver_of "$D")" = "1.3.0 1.3.0 1.3.0" ] && [ "$(entries "$D")" = "3" ]; check $? "re-fold: an explicit 'minor' on the first bump is kept (1.3.0, one entry)"
D="$TMP/c8b"; make_branch "$D"; bump_commit "$D"
frag "$D" b.md '<!-- bump: minor -->\nLate minor\n'; g "$D" add -A && g "$D" commit -q -m late
run_bump "$D"; [ "$(ver_of "$D")" = "1.3.0 1.3.0 1.3.0" ] && [ "$(entries "$D")" = "3" ] && ! grep -qF '**v1.2.4' "$D/$CL"
check $? "re-fold: a later minor fragment raises the ONE bump to 1.3.0 (no 1.2.4 entry left)"
# A fragment of the same name re-added with new text after its fold: the newer text wins.
D="$TMP/c8c"; make_branch "$D"; bump_commit "$D"
frag "$D" a.md 'Alpha headline v2\nAlpha body v2.\n'; g "$D" add -A && g "$D" commit -q -m "re-add a.md with new text"
run_bump "$D"; rc=$?; g "$D" add -A && g "$D" commit -q -m refold
[ "$rc" -eq 0 ] && [ "$(sed -n 7p "$D/$CL")" = "**v1.2.4 — Alpha headline v2:** Alpha body v2." ]; check $? "re-fold: a re-added fragment's newer text replaces its folded text"
run_check "$D"; check $? "re-fold: --check passes after a same-name re-fold"

# --refold is a no-op unless there is a bump AND a pending fragment (the lane shape stays untouched).
D="$TMP/c9"; make_branch "$D"; before="$(tree_sum "$D")"
run_bump "$D" --refold; rc=$?
[ "$rc" -eq 0 ] && [ "$(tree_sum "$D")" = "$before" ] && grep -qF 'this branch carries no bump' "$TMP/last.out"; check $? "--refold: a fragments-only branch (a parallel lane) is left byte-identical"
bump_commit "$D"; before="$(tree_sum "$D")"
run_bump "$D" --refold; rc=$?
[ "$rc" -eq 0 ] && [ "$(tree_sum "$D")" = "$before" ] && grep -qF 'already folds every fragment' "$TMP/last.out"; check $? "--refold: a current bump is left byte-identical"
run_bump "$D"; rc=$?
[ "$rc" -eq 1 ] && [ "$(tree_sum "$D")" = "$before" ] && grep -qF 'already folds every fragment; nothing to bump' "$TMP/last.out"; check $? "plain re-run on a current bump: refused, nothing written (never a double bump)"
D="$TMP/c9b"; make_fixture "$D"; frag "$D" x.md 'X\n'; before="$(tree_sum "$D")"
run_bump "$D" --refold; rc=$?
[ "$rc" -eq 0 ] && [ "$(tree_sum "$D")" = "$before" ] && grep -qF 'cannot tell whether this branch carries a bump' "$TMP/last.out"; check $? "--refold: no base ⇒ no-op with the reason (CI's --check is the gate)"

# The re-fold refuses when the existing bump is not reproducible, and restores on a failure.
D="$TMP/c10"; make_branch "$D"; bump_commit "$D"
sed 's/Alpha body\./Alpha body, hand-edited./' "$D/$CL" > "$D/cl.tmp" && mv "$D/cl.tmp" "$D/$CL"; g "$D" commit -q -am "hand edit"
frag "$D" b.md 'Late\n'; g "$D" add -A && g "$D" commit -q -m late; before="$(tree_sum "$D")"
run_bump "$D"; rc=$?
[ "$rc" -eq 1 ] && [ "$(tree_sum "$D")" = "$before" ] && grep -qF 'refusing to re-fold' "$TMP/last.out" && grep -qF 'revert this branch' "$TMP/last.out"
check $? "re-fold: a hand-edited existing bump is refused, nothing written, the fix named"
D="$TMP/c11"; make_branch "$D"; bump_commit "$D"
frag "$D" b.md 'Late\n'; printf '#!/usr/bin/env bash\nexit 1\n' > "$D/scripts/bad-validator.sh"; g "$D" add -A && g "$D" commit -q -m late
before="$(tree_sum "$D")"
( cd "$D" && BUMP_VERSION_VALIDATORS="scripts/bad-validator.sh" bash scripts/bump-version.sh ) > "$TMP/last.out" 2>&1; rc=$?
[ "$rc" -eq 1 ] && [ "$(tree_sum "$D")" = "$before" ] && [ ! -e "$D/changelog.d/a.md" ] && [ -z "$(g "$D" status --porcelain)" ] \
  && [ -z "$(find "$D" -maxdepth 1 -name '.bump-version.*')" ]
check $? "re-fold: a failing validator restores every file byte-identical (the restored a.md removed again)"
D="$TMP/c12"; make_branch "$D"; bump_commit "$D"; frag "$D" b.md 'Late\n'; g "$D" add -A && g "$D" commit -q -m late
before="$(tree_sum "$D")"; run_bump "$D" --dry-run; rc=$?
[ "$rc" -eq 0 ] && [ "$(tree_sum "$D")" = "$before" ] && grep -qF 're-fold:' "$TMP/last.out"; check $? "re-fold: --dry-run prints the plan and writes nothing"

# ---- 9e. mutation controls: each --check rule is what catches its case -----------------------------
mutant() { # mutant <dir> <awk program applied to a copy of the script>
  awk "$2" "$BUMP" > "$1/scripts/bump-version.sh"
}
cp -R "$TMP/c2" "$TMP/m1"
mutant "$TMP/m1" '{ sub(/\[ "\$ignore_pending" -eq 0 \]/, "[ \"$ignore_pending\" -eq 9 ]"); print }'
run_check "$TMP/m1"; rc=$?
[ "$rc" -eq 0 ]; check $? "mutation control: without the pending-after-bump rule, the late fragment goes undetected"
cp -R "$TMP/c4" "$TMP/m2"
mutant "$TMP/m2" '/^chk\(\) \{/ { print "search_fold() { FOLD_IDX=(); return 0; }" } { print }'
run_check "$TMP/m2"; rc=$?
[ "$rc" -eq 0 ]; check $? "mutation control: without the fold search, a hand-reworded entry goes undetected"
cp -R "$TMP/c6" "$TMP/m3"
mutant "$TMP/m3" '{ sub(/\[ "\$W_CAPS" != "\$W_VER" \]/, "false"); print }'
run_check "$TMP/m3"; rc=$?
[ "$rc" -eq 0 ]; check $? "mutation control: without the capabilities compare, the drift goes undetected"
cp -R "$TMP/c2" "$TMP/m4"
mutant "$TMP/m4" '{ sub(/if \[ "\$old_ver" != "\$BASE_VER" \]; then/, "if false; then"); print }'
run_bump "$TMP/m4"; [ "$(entries "$TMP/m4")" = "4" ] && [ "$(ver_of "$TMP/m4")" = "1.2.5 1.2.5 1.2.5" ]
check $? "mutation control: without the re-fold dispatch, a re-run double-bumps (1.2.5, two new entries) — the old behaviour"

# ---- 9f. the capability-scan reminder on a minor / major bump --------------------------------------
# The reminder reads plugin_version_at_last_scan live from the baseline. make_fixture carries NO
# baseline, so every case above is also the missing-baseline shape; with_baseline adds one.
echo "# bump-version.sh capability-scan reminder"
CB="loomwright/docs/CAPABILITY_BASELINE.json"
REM='capability baseline last scanned at 1.0.0; run /capability-check'
with_baseline() { # with_baseline <dir> <file content> — write the fixture baseline and commit it
  mkdir -p "$1/loomwright/docs" && printf '%s\n' "$2" > "$1/$CB" && g "$1" add -A && g "$1" commit -q -m "capability baseline"
}
GOOD_CB='{"schema_version": 1, "baseline_date": "2026-01-01", "plugin_version_at_last_scan": "1.0.0"}'
rem_count() { grep -cF -- "${1:-$REM}" "$TMP/last.out"; }
# scan_case <dir> <baseline content | ""> <bump args...> — fixture (+ baseline) + one fragment, then the bump.
scan_case() {
  local d="$1" cb="$2"; shift 2
  make_fixture "$d"; [ -z "$cb" ] || with_baseline "$d" "$cb"; frag "$d" x.md 'X\n'
  run_bump "$d" "$@"
}

scan_case "$TMP/s1" "$GOOD_CB" minor; rc=$?
[ "$rc" -eq 0 ] && [ "$(ver_of "$TMP/s1")" = "1.3.0 1.3.0 1.3.0" ] && [ "$(rem_count)" = "1" ]
check $? "scan reminder: a minor bump exits 0, bumps, and prints exactly one '$REM' line"
[ "$(grep -c '^bump-version: capability baseline' "$TMP/last.out")" = "1" ] \
  && [ "$(sed -n 's/^bump-version: bumped [^ ]* -> \([^ ]*\) .*/\1/p' "$TMP/last.out" | tail -1)" = "1.3.0" ]
check $? "scan reminder: the line carries the bump-version: prefix, and the wave release step's version parse still reads 1.3.0"
scan_case "$TMP/s2" "$GOOD_CB" major; rc=$?
[ "$rc" -eq 0 ] && [ "$(ver_of "$TMP/s2")" = "2.0.0 2.0.0 2.0.0" ] && [ "$(rem_count)" = "1" ]
check $? "scan reminder: a major bump exits 0, bumps, and prints exactly one reminder line"
scan_case "$TMP/s3" "$GOOD_CB"; rc=$?
[ "$rc" -eq 0 ] && [ "$(ver_of "$TMP/s3")" = "1.2.4 1.2.4 1.2.4" ] && [ "$(rem_count 'capability baseline last scanned')" = "0" ]
check $? "scan reminder: a patch bump (no level, no directive) prints no reminder"
D="$TMP/s4"; make_fixture "$D"; with_baseline "$D" "$GOOD_CB"; frag "$D" x.md 'X\n'; before="$(tree_sum "$D")"
run_bump "$D" minor --dry-run; rc=$?
[ "$rc" -eq 0 ] && [ "$(tree_sum "$D")" = "$before" ] && [ "$(rem_count)" = "1" ]
check $? "scan reminder: 'minor --dry-run' exits 0, writes nothing, and prints the reminder"

# Fail-SAFE: each unreadable shape exits 0, bumps, and prints neither the line nor jq's stderr.
scan_safe() { # scan_safe <dir> <baseline content | ""> <label>
  scan_case "$1" "$2" minor; local rc=$?
  [ "$rc" -eq 0 ] && [ "$(ver_of "$1")" = "1.3.0 1.3.0 1.3.0" ] && [ "$(rem_count 'capability baseline')" = "0" ] && ! grep -q 'jq:' "$TMP/last.out"
  check $? "scan reminder fail-SAFE: $3 — minor bump exits 0 and bumps, no reminder, no jq: error text"
}
scan_safe "$TMP/s5" "" "(i) no baseline file"
[ ! -e "$TMP/s5/$CB" ]; check $? "scan reminder fail-SAFE (i) precondition: the fixture has no baseline"
scan_safe "$TMP/s6" '{"plugin_version_at_last_scan": "1.0.0",' "(ii) invalid JSON"
scan_safe "$TMP/s7" '{"schema_version": 1}' "(iii) valid JSON, plugin_version_at_last_scan absent"
scan_safe "$TMP/s7b" '{"plugin_version_at_last_scan": "1.0"}' "(iii) valid JSON, plugin_version_at_last_scan not X.Y.Z"

# --check and the --refold no-op paths never print it; a real re-fold prints it once, before the machine line.
D="$TMP/s8"; make_branch "$D"; with_baseline "$D" "$GOOD_CB"
run_check "$D"; rc=$?
[ "$rc" -eq 0 ] && [ "$(rem_count 'capability baseline')" = "0" ]; check $? "scan reminder: --check (not bumped) prints none"
run_bump "$D" --refold; rc=$?
[ "$rc" -eq 0 ] && grep -qF 'this branch carries no bump' "$TMP/last.out" && [ "$(rem_count 'capability baseline')" = "0" ]
check $? "scan reminder: the --refold no-op on a fragments-only branch prints none"
bump_commit "$D" minor
run_check "$D"; rc=$?
[ "$rc" -eq 0 ] && [ "$(rem_count 'capability baseline')" = "0" ]; check $? "scan reminder: --check (bumped) prints none"
run_bump "$D" --refold; rc=$?
[ "$rc" -eq 0 ] && grep -qF 'already folds every fragment' "$TMP/last.out" && [ "$(rem_count 'capability baseline')" = "0" ]
check $? "scan reminder: the --refold no-op on a current bump prints none"
frag "$D" b.md 'Late\n'; g "$D" add -A && g "$D" commit -q -m late
run_bump "$D"; rc=$?
[ "$rc" -eq 0 ] && [ "$(rem_count)" = "1" ] && [ "$(sed -n 's/^bump-version: refold-touched: //p' "$TMP/last.out" | wc -l | tr -d ' ')" = "1" ] \
  && grep -q '^bump-version: refold-touched: ' < <(grep '^bump-version: ' "$TMP/last.out" | tail -n 1)
check $? "scan reminder: a minor re-fold prints it once (the child bump) and refold-touched: stays the last line"

# Mutation controls: each guard is what its case above catches (the pinned literals in the brief).
scan_mutant() { # scan_mutant <dir> <awk program> — the fixture's script becomes a mutated copy; 1 if it is unchanged
  awk "$2" "$BUMP" > "$1/scripts/bump-version.sh"; ! cmp -s "$BUMP" "$1/scripts/bump-version.sh"
}
D="$TMP/sm1"; make_fixture "$D"; with_baseline "$D" "$GOOD_CB"; frag "$D" x.md 'X\n'
scan_mutant "$D" '{ sub(/-ge 2 \] \|\| return 0/, "-ge 4 ] || return 0"); print }' && run_bump "$D" minor && [ "$(rem_count)" = "0" ]
check $? "mutation control: with the level guard at -ge 4, a minor bump prints no reminder (the minor case would be red)"
D="$TMP/sm2"; make_fixture "$D"; with_baseline "$D" "$GOOD_CB"; frag "$D" x.md 'X\n'
scan_mutant "$D" '{ sub(/-ge 2 \] \|\| return 0/, "-ge 1 ] || return 0"); print }' && run_bump "$D" && [ "$(rem_count)" = "1" ]
check $? "mutation control: with the level guard at -ge 1, a patch bump prints the reminder (the patch case would be red)"
D="$TMP/sm3"; make_fixture "$D"; with_baseline "$D" '{"schema_version": 1}'; frag "$D" x.md 'X\n'
scan_mutant "$D" '{ sub(/semver_ok "\$v" \|\| return 0/, ": || return 0"); print }' && run_bump "$D" minor && grep -q 'capability baseline' "$TMP/last.out"
check $? "mutation control: without the X.Y.Z guard, a baseline lacking the key prints a reminder (case iii would be red)"
for shape in missing invalid; do
  D="$TMP/sm4-$shape"; make_fixture "$D"; [ "$shape" = invalid ] && with_baseline "$D" '{"plugin_version_at_last_scan":'; frag "$D" x.md 'X\n'
  scan_mutant "$D" '{ sub(/"\$CAP_BASELINE" 2>\/dev\/null\)/, "\"$CAP_BASELINE\")"); print }' && run_bump "$D" minor && grep -q 'jq:' "$TMP/last.out"
  check $? "mutation control: without the stderr guard, the $shape-baseline shape leaks jq: error text (case i / ii would be red)"
done
D="$TMP/sm5"; make_fixture "$D"; frag "$D" x.md 'X\n'
scan_mutant "$D" '{ sub(/2>\/dev\/null\)" \|\| return 0/, "2>/dev/null)\" || exit 1"); print }' && { run_bump "$D" minor; [ "$?" -ne 0 ]; }
check $? "mutation control: with the jq-line guard exiting 1, a missing baseline fails the bump (case i would be red)"
D="$TMP/sm6"; make_fixture "$D"; with_baseline "$D" "$GOOD_CB"; frag "$D" x.md 'X\n'
scan_mutant "$D" 'prev ~ /^  printf .%s\\n. "\$entry"$/ && /^  scan_reminder "\$level"$/ { prev = $0; next } { prev = $0; print }' && run_bump "$D" minor --dry-run && [ "$(rem_count)" = "0" ]
check $? "mutation control: without the dry-run call, 'minor --dry-run' prints no reminder (the dry-run case would be red)"

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
# The same state is reached by a scripted bump left stale after main moved (rebased onto a main
# that merged a legal unfolded fragment); a re-run there now RE-FOLDS (#512) instead of
# double-bumping, so the DRIFT text must say so and point at the content check.
grep -q 'DRIFT \[bump-fragment-guard\].*re-folds into that ONE bump instead of double-bumping.*--check verifies' "$TMP/gate.out"; check $? "guard: the DRIFT message names the re-run-re-folds remedy and the --check"
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
