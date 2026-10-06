#!/usr/bin/env bash
# test-skills-index-companion.sh — the shipped .agent/companions.json no longer drags
# loomwright/skills/SKILLS_INDEX.md into every item that edits a skill body
# (parallel-automate/11, AC3). SKILLS_INDEX.md is now GENERATED from SKILL.md frontmatter
# by scripts/check-skills-index-sync.sh --write, so two items editing two different
# skills' SKILL.md bodies can share one plan-waves wave.
#
# What it proves, in a temp checkout whose .agent/companions.json is a byte copy of the
# REAL file:
#   1. two items whose Touches name two different EXISTING loomwright/skills/<x>/SKILL.md
#      land together in `wave 1` of `automate-helpers.sh plan-waves … --max 5`;
#   2. --explain prints no `conflicts with` line for them;
#   3. the real table carries no rule that adds loomwright/skills/SKILLS_INDEX.md;
#   4. MUTATION CONTROL: the same items under a copy with the old
#      `loomwright/skills/*/SKILL.md ⇒ SKILLS_INDEX.md` rule re-added split into two
#      waves, naming that rule — so assertion 1 is load-bearing, not vacuous.
#
# automate-helpers.sh is invoked IN PLACE (its real path beside this script, never a
# copy), so this keeps working however that helper is laid out on disk.
# Exit 0 = all pass, 1 = any failure. UNCOUNTED by the doc-currency gate.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
H="$HERE/automate-helpers.sh"
REAL_CJ="$REPO/.agent/companions.json"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass + 1)); }
no() { echo "  FAIL: $1"; fail=$((fail + 1)); }

[ -f "$H" ] || { echo "FAIL: helper not found: $H"; exit 1; }
[ -f "$REAL_CJ" ] || { echo "FAIL: companions table not found: $REAL_CJ"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq required (plan-waves reads the companions table with it)"; exit 1; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# make_root <dir> <companions.json source> — a minimal checkout: the table, two EXISTING
# skill bodies (so the `"new": true` rule for loomwright/skills/* does not fire), two items.
make_root() {
  mkdir -p "$1/.agent" "$1/q" "$1/loomwright/skills/alpha" "$1/loomwright/skills/beta"
  cp "$2" "$1/.agent/companions.json"
  printf -- '---\nname: alpha\n---\n# Alpha\n' > "$1/loomwright/skills/alpha/SKILL.md"
  printf -- '---\nname: beta\n---\n# Beta\n' > "$1/loomwright/skills/beta/SKILL.md"
  printf '# alpha body edit\n\n## Depends on\nnone\n\n## Touches\nloomwright/skills/alpha/SKILL.md\n' > "$1/q/01-alpha.md"
  printf '# beta body edit\n\n## Depends on\nnone\n\n## Touches\nloomwright/skills/beta/SKILL.md\n' > "$1/q/02-beta.md"
  printf 'q/01-alpha.md\nq/02-beta.md\n' > "$1/list"
}

# run_pw <root> [extra args…] — sets RC / OUT / ERR.
run_pw() {
  local root="$1"; shift
  RC=0
  OUT="$(bash "$H" plan-waves "$root/list" --max 5 --root "$root" "$@" 2>"$T/err")" || RC=$?
  ERR="$(cat "$T/err")"
}

echo "== real .agent/companions.json: two different skill bodies share one wave =="
R="$T/real"
make_root "$R" "$REAL_CJ"
if cmp -s "$REAL_CJ" "$R/.agent/companions.json"; then ok "fixture table is a byte copy of the real file"
else no "fixture table differs from the real file"; fi

if jq -e '[.companions[] | select(.add | index("loomwright/skills/SKILLS_INDEX.md"))] | length == 0' "$REAL_CJ" >/dev/null 2>&1; then
  ok "real table has no rule adding loomwright/skills/SKILLS_INDEX.md"
else no "real table still adds loomwright/skills/SKILLS_INDEX.md: $(jq -c '[.companions[] | select(.add | index("loomwright/skills/SKILLS_INDEX.md"))]' "$REAL_CJ" 2>&1)"; fi

run_pw "$R"
if [ "$RC" -eq 0 ] && [ "$OUT" = "wave 1: q/01-alpha.md q/02-beta.md" ]; then
  ok "plan-waves --max 5 puts both items in wave 1"
else no "expected 'wave 1: q/01-alpha.md q/02-beta.md' (rc 0), got rc=$RC out=$(printf '%s' "$OUT" | tr '\n' '|') err=$ERR"; fi
case "$ERR" in
  *"no companion expansion"*) no "plan-waves did not read the fixture table: $ERR" ;;
  *) ok "plan-waves read the companions table (no 'absent table' note)" ;;
esac

run_pw "$R" --explain
if [ "$RC" -eq 0 ] && ! grep -q 'conflicts with' <<<"$OUT"; then
  ok "--explain prints no 'conflicts with' line"
else no "--explain rc=$RC out=$(printf '%s' "$OUT" | tr '\n' '|')"; fi

echo "== mutation control: the old SKILL.md ⇒ SKILLS_INDEX.md rule re-added splits them =="
M_CJ="$T/companions-old-rule.json"
jq '.companions = [{"when": "loomwright/skills/*/SKILL.md", "add": ["loomwright/skills/SKILLS_INDEX.md"]}] + .companions' \
  "$REAL_CJ" > "$M_CJ" 2>/dev/null
if [ ! -s "$M_CJ" ] || cmp -s "$M_CJ" "$REAL_CJ"; then
  no "mutant table is empty or identical to the real file — control would be vacuous"
else
  M="$T/mutant"
  make_root "$M" "$M_CJ"
  run_pw "$M"
  if [ "$RC" -eq 0 ] && [ "$OUT" = "$(printf 'wave 1: q/01-alpha.md\nwave 2: q/02-beta.md')" ]; then
    ok "MUTATION CONTROL: old rule re-added ⇒ the items split into two waves (assertion above is load-bearing)"
  else no "mutation control did not split: rc=$RC out=$(printf '%s' "$OUT" | tr '\n' '|') err=$ERR"; fi
  run_pw "$M" --explain
  if grep -qF 'conflicts with q/01-alpha.md on loomwright/skills/SKILLS_INDEX.md (companion: loomwright/skills/*/SKILL.md)' <<<"$OUT"; then
    ok "MUTATION CONTROL: --explain names the re-added rule as the conflict"
  else no "mutation control --explain did not name the rule: $(printf '%s' "$OUT" | tr '\n' '|')"; fi
fi

echo "test-skills-index-companion: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
