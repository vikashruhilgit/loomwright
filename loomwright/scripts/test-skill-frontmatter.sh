#!/usr/bin/env bash
# test-skill-frontmatter.sh — every plugin skill's frontmatter `name` equals its directory name.
#
# WHY: a skill's directory name and its frontmatter `name` are two invocable ids for one skill. When
# they differ, the host lists both (`loomwright:commit (loomwright:commit-skill)`), a caller can bind
# to the stray one, and a later fix of the mismatch silently removes an id somebody used. Two skills
# had drifted (`commit` named `commit-skill`, stackpack's `nestjs-drizzle` named
# `nestjs-repository-patterns`; agnostic-phase1/05 item 6). Nothing checked it, so this does.
#
# RULE, for every <plugin>/skills/<dir>/SKILL.md under the repo root:
#   - line 1 is `---` (the frontmatter LEADS the file — a block after a heading is not frontmatter);
#   - the frontmatter carries exactly one `name:` key and its value equals <dir>.
# The template (loomwright/skills/SKILL_TEMPLATE.md) lives outside any <dir>, so it is checked
# separately: leading frontmatter with a `name:` and a `description:` key.
#
# A built-in mutant (a copied tree with one name changed) proves the check fails when it should,
# so a regression that makes the checker vacuous turns this suite red instead of green.
#
# Exit 0 = all pass, 1 = any assertion failed, 2 = fixture setup broken.
# Portability: bash 3.2 safe (macOS) + Linux CI. No GNU-only flags, no mapfile, no sed -i.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

SCRATCH="$(mktemp -d 2>/dev/null)"
[ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] || { echo "SETUP FAILURE: mktemp -d failed" >&2; exit 2; }
trap '[ -n "${SCRATCH:-}" ] && rm -rf "$SCRATCH"' EXIT

# frontmatter <file> → the frontmatter body (between a LEADING `---` and the next `---`); empty when
# line 1 is not `---` or the block never closes.
frontmatter() {
  awk 'NR == 1 { if ($0 != "---") exit; next } $0 == "---" { closed = 1; exit } { buf = buf $0 "\n" }
       END { if (closed) printf "%s", buf }' "$1"
}

# fm_values <frontmatter> <key> → every value of a top-level `<key>:` line, unquoted, comment-stripped.
fm_values() {
  awk -v k="$2" 'BEGIN { q = sprintf("%c", 39) }
    index($0, k ":") == 1 {
      v = substr($0, length(k) + 2); sub(/^[ \t]+/, "", v); sub(/[ \t]+#.*$/, "", v); sub(/[ \t]+$/, "", v)
      f = substr(v, 1, 1); l = substr(v, length(v), 1)
      if (length(v) >= 2 && ((f == "\"" && l == "\"") || (f == q && l == q))) v = substr(v, 2, length(v) - 2)
      print v }' <<< "$1"
}

# check_root <root> → prints one line per violation; prints nothing when every skill conforms.
# Also prints `COUNT <n>` last, so a caller can refuse a 0-file run (a vacuous green).
check_root() {
  local root="$1" f dir fm names n count=0
  for f in "$root"/*/skills/*/SKILL.md; do
    [ -f "$f" ] || continue
    count=$((count + 1))
    dir="$(basename "$(dirname "$f")")"
    fm="$(frontmatter "$f")"
    if [ -z "$fm" ]; then echo "VIOLATION ${f#"$root"/}: no leading frontmatter block"; continue; fi
    names="$(fm_values "$fm" name)"
    n="$(printf '%s' "$names" | grep -c .)"
    if [ "$n" -ne 1 ]; then echo "VIOLATION ${f#"$root"/}: $n 'name:' keys (want exactly 1)"; continue; fi
    [ "$names" = "$dir" ] || echo "VIOLATION ${f#"$root"/}: name '$names' != directory '$dir'"
  done
  echo "COUNT $count"
}

echo "== (1) every plugin skill's frontmatter name equals its directory =="
out="$(check_root "$REPO")"
count="$(sed -n 's/^COUNT //p' <<< "$out")"
viol="$(grep '^VIOLATION' <<< "$out" || true)"
[ "${count:-0}" -gt 0 ] && ok "(1) scanned $count SKILL.md files" || no "(1) scanned 0 SKILL.md files — a 0-file run would be a vacuous green"
if [ -z "$viol" ]; then ok "(1) no name/directory mismatch and every SKILL.md leads with frontmatter"
else no "(1) violations:"; printf '%s\n' "$viol" | sed 's/^/      /'; fi

echo "== (2) SKILL_TEMPLATE.md leads with frontmatter carrying name + description =="
TPL="$REPO/loomwright/skills/SKILL_TEMPLATE.md"
if [ -f "$TPL" ]; then
  tfm="$(frontmatter "$TPL")"
  [ -n "$tfm" ] && ok "(2) the template's line 1 opens a closed frontmatter block" || no "(2) the template has no LEADING frontmatter block"
  [ -n "$(fm_values "$tfm" name)" ] && ok "(2) the template carries a name: placeholder" || no "(2) the template frontmatter has no name:"
  [ -n "$(fm_values "$tfm" description)" ] && ok "(2) the template carries a description: placeholder" || no "(2) the template frontmatter has no description:"
else
  no "(2) $TPL is missing"
fi

echo "== (3) mutation self-check: the checker fails on a renamed skill and on a trailing block =="
M="$SCRATCH/repo"
mkdir -p "$M/p/skills/alpha" "$M/p/skills/beta" "$M/q/skills/gamma" \
  || { echo "SETUP FAILURE: mkdir under $SCRATCH failed" >&2; exit 2; }
printf -- '---\nname: alpha\ndescription: a\n---\n# A\n' > "$M/p/skills/alpha/SKILL.md"
printf -- '---\nname: "beta"  # quoted, with a comment\ndescription: b\n---\n# B\n' > "$M/p/skills/beta/SKILL.md"
printf -- '---\nname: gamma\ndescription: g\n---\n# G\n' > "$M/q/skills/gamma/SKILL.md"
base="$(check_root "$M")"
[ -z "$(grep '^VIOLATION' <<< "$base" || true)" ] && ok "(3) the conforming fixture (incl. a quoted, commented name) passes" \
  || no "(3) the conforming fixture was rejected: $(grep '^VIOLATION' <<< "$base" | head -n1)"
# Mutant A — the defect this suite exists for: a name that differs from its directory.
printf -- '---\nname: gamma-skill\ndescription: g\n---\n# G\n' > "$M/q/skills/gamma/SKILL.md"
mutA="$(check_root "$M")"
grep -q "^VIOLATION q/skills/gamma/SKILL.md: name 'gamma-skill' != directory 'gamma'" <<< "$mutA" \
  && ok "(3) a renamed skill (gamma-skill in gamma/) is reported" || no "(3) the renamed-skill mutant was NOT caught: $mutA"
# Mutant B — frontmatter after a heading (the old SKILL_TEMPLATE.md shape) is not frontmatter.
printf -- '# A\n\n---\nname: alpha\n---\n' > "$M/p/skills/alpha/SKILL.md"
mutB="$(check_root "$M")"
grep -q "^VIOLATION p/skills/alpha/SKILL.md: no leading frontmatter block" <<< "$mutB" \
  && ok "(3) a frontmatter block placed after a heading is reported" || no "(3) the trailing-block mutant was NOT caught: $mutB"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
