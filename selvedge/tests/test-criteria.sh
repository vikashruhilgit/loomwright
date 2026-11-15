#!/usr/bin/env bash
# test-criteria.sh — pins `selvedge criteria from-pr|from-md|from-text|check` and
# selvedge/lib/criteria.mjs (plus schemas/criteria.schema.json): the three inputs give byte-identical
# criteria.json, ids are c- + 12 hex of sha256(normalized text), criteriaSha256 is sha256 of the
# canonical criteria array, no criteria → criteria_not_found, the deterministic vague-phrase
# pre-check with its rewrite, the schema equal to the validator's key sets, and no reason named as a
# string literal in the new modules. Every arm turns red under its row of the brief's pin-mutation
# table.
#
# Hermetic: a fresh temp HOME, a temp git repo, `gh` is a PATH stub (no network). Needs node (>= 18)
# and git; a missing one is a FAIL, never a skip.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$TESTS_DIR/.." && pwd)"
CLI="$PLUGIN_DIR/bin/selvedge"
export SELVEDGE_LIB="$PLUGIN_DIR/lib"
export SELVEDGE_CRITERIA_SCHEMA="$PLUGIN_DIR/schemas/criteria.schema.json"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "  ok   $1"; }
ko() { fail=$((fail + 1)); echo "  FAIL $1"; }

for tool in node git; do
  command -v "$tool" >/dev/null 2>&1 || { echo "  FAIL $tool is not on PATH (test-criteria.sh needs it)"; echo "test-criteria: 0 passed, 1 failed"; exit 1; }
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/selvedge-criteria.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
R="$TMP/repo"
mkdir -p "$R" && git -C "$R" init -q

# run [stdin-file] -- <cli args…> — sets $rc, $out (stdout), $err (stderr); runs in the repo. The
# exact stdout bytes stay in $TMP/stdout ($(…) would strip a trailing newline).
run() {
  local input=/dev/null
  if [ "$1" != "--" ]; then input="$1"; shift; fi
  shift
  (cd "$R" && bash "$CLI" "$@" >"$TMP/stdout" 2>"$TMP/stderr" <"$input"); rc=$?
  out="$(cat "$TMP/stdout")"
  err="$(cat "$TMP/stderr")"
}

# node_eval <js> — an ES module with C (criteria) imported.
node_eval() {
  node --input-type=module -e "
import { pathToFileURL } from 'node:url';
const C = await import(pathToFileURL(process.env.SELVEDGE_LIB + '/criteria.mjs').href);
$1"
}

# sha256 hex of a literal string — independent of criteria.mjs.
sha_of() { node -e 'process.stdout.write(require("crypto").createHash("sha256").update(process.argv[1]).digest("hex"))' "$1"; }

# The three criteria, normalized.
T1='The cart total shows "12" when the quantity is 2'
T2='Removing the last item shows the text "Your cart is empty"'
T3='The Checkout button is disabled while the cart is empty'

# gh stub: records argv; `gh pr view 42 --json body` prints a PR body with the criteria under an
# "Acceptance criteria" heading (plus a list elsewhere that must be ignored).
STUB="$TMP/stub-bin"; mkdir -p "$STUB"
cat > "$TMP/pr-body.md" <<EOF
## Summary

- this bullet is not a criterion

## Acceptance criteria

- [ ] $T1
- [x] $T2
* $T3

## Notes

- nor is this one
EOF
cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_ARGV_LOG"
if [ "$1 $2 $3" = "pr view 42" ] && [ "$4 $5" = "--json body" ]; then
  node -e 'process.stdout.write(JSON.stringify({ body: require("fs").readFileSync(process.argv[1], "utf8") }))' "$GH_PR_BODY"
  exit 0
fi
if [ "$1 $2 $3" = "pr view 43" ]; then
  printf '{"body":"## Summary\\n\\n- no criteria heading here\\n"}'
  exit 0
fi
echo "gh stub: no such PR" >&2
exit 1
EOF
chmod +x "$STUB/gh"
export GH_ARGV_LOG="$TMP/gh-argv.log" GH_PR_BODY="$TMP/pr-body.md"
export PATH="$STUB:$PATH"

# The markdown file: a checkbox marker and double spaces (normalization must strip / collapse them).
printf '# Feature\n\nSome prose.\n\n- [ ] %s\n-   %s\n- %s\n' "$(printf '%s' "$T1" | sed 's/total shows/total  shows/')" "$T2" "$T3" > "$TMP/criteria.md"
printf '%s\n%s\n\n  %s  \n' "$T1" "$T2" "$T3" > "$TMP/criteria.txt"

echo "-- from-pr / from-md / from-text are byte-identical (AC5)"
run -- criteria from-pr 42; cp "$TMP/stdout" "$TMP/pr.json"; pr_rc=$rc; pr_err="$err"
run -- criteria from-md "$TMP/criteria.md"; cp "$TMP/stdout" "$TMP/md.json"; md_rc=$rc
run "$TMP/criteria.txt" -- criteria from-text; cp "$TMP/stdout" "$TMP/text.json"; text_rc=$rc
{ [ "$pr_rc" -eq 0 ] && [ "$md_rc" -eq 0 ] && [ "$text_rc" -eq 0 ]; } && ok "AC5 all three inputs exit 0" || ko "AC5 exit codes: pr=$pr_rc md=$md_rc text=$text_rc err='$err'"
grep -qxF 'pr view 42 --json body' "$GH_ARGV_LOG" && ok "AC5 from-pr runs gh pr view <n> --json body" || ko "AC5 gh argv: '$(cat "$GH_ARGV_LOG" 2>/dev/null)'"
{ cmp -s "$TMP/pr.json" "$TMP/md.json" && cmp -s "$TMP/md.json" "$TMP/text.json"; } \
  && ok "AC5 the three criteria.json outputs are byte-identical" || ko "AC5 differ: pr='$(cat "$TMP/pr.json")' md='$(cat "$TMP/md.json")' text='$(cat "$TMP/text.json")'"
# The expected bytes, built independently: ids from sha256 of the normalized text.
want="$TMP/want.json"
{
  printf '{\n  "schema_version": 1,\n  "source": null,\n  "criteria": [\n'
  i=0
  for t in "$T1" "$T2" "$T3"; do
    i=$((i + 1))
    id="c-$(sha_of "$t" | cut -c1-12)"
    q="$(node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$t")"
    printf '    {\n      "id": "%s",\n      "text": %s\n    }' "$id" "$q"
    [ "$i" -lt 3 ] && printf ',\n' || printf '\n'
  done
  printf '  ]\n}\n'
} > "$want"
cmp -s "$TMP/md.json" "$want" \
  && ok "AC5 the bytes are {schema_version: 1, source: null, criteria: [{id, text}]}, 2-space pretty, trailing newline, id = c- + 12 hex of sha256(normalized text)" \
  || ko "AC5 bytes: got='$(cat "$TMP/md.json")' want='$(cat "$want")'"
[ "$(tail -c 1 "$TMP/md.json" | od -An -c | tr -d ' ')" = '\n' ] && ok "AC5 the file ends in a newline" || ko "AC5 trailing newline"
grep -qF 'PR #42' <<<"$pr_err" && ok "AC5 provenance (PR #42) is printed on stderr, not in the file" || ko "AC5 provenance: err='$pr_err'"
run -- criteria from-md "$TMP/criteria.md" --source "ticket SHOP-7"
{ [ "$rc" -eq 0 ] && grep -qF '"source": "ticket SHOP-7"' <<<"$out"; } && ok "AC5 --source <label> is the only way source is set" || ko "AC5 --source: rc=$rc out='$out'"

echo "-- no criteria → criteria_not_found (AC5)"
run -- criteria from-pr 43
{ [ "$rc" -eq 2 ] && grep -qF 'criteria_not_found' <<<"$err" && [ -z "$out" ]; } \
  && ok "AC5 a PR body with no Acceptance criteria heading exits 2 criteria_not_found, prints nothing" || ko "AC5 from-pr none: rc=$rc out='$out' err='$err'"
printf '# Notes\n\nJust prose, no list.\n' > "$TMP/none.md"
run -- criteria from-md "$TMP/none.md"
{ [ "$rc" -eq 2 ] && grep -qF 'criteria_not_found' <<<"$err" && [ -z "$out" ]; } \
  && ok "AC5 a markdown file with no list items exits 2 criteria_not_found" || ko "AC5 from-md none: rc=$rc out='$out' err='$err'"
run -- criteria from-text
{ [ "$rc" -eq 2 ] && grep -qF 'criteria_not_found' <<<"$err"; } && ok "AC5 empty stdin exits 2 criteria_not_found" || ko "AC5 from-text none: rc=$rc err='$err'"
run -- criteria from-pr 99
[ "$rc" -eq 1 ] && ok "a failing gh exits 1 (an operation failed)" || ko "gh failure: rc=$rc err='$err'"
run -- criteria from-pr abc
[ "$rc" -eq 2 ] && ok "a non-numeric PR number is a usage error (exit 2)" || ko "from-pr abc: rc=$rc"
run -- criteria no-such
[ "$rc" -eq 2 ] && ok "an unknown criteria command exits 2" || ko "unknown criteria command: rc=$rc"

cat > "$TMP/pr-bold.md" <<EOF
Intro text.

**Acceptance criteria:**

1. $T1
2) $T2
- $T3

**Out of scope**

- not a criterion
EOF
export GH_PR_BODY="$TMP/pr-bold.md"
run -- criteria from-pr 42
export GH_PR_BODY="$TMP/pr-body.md"
{ [ "$rc" -eq 0 ] && cmp -s "$TMP/stdout" "$TMP/md.json"; } \
  && ok "a bold-line Acceptance criteria heading and numbered items give the same criteria.json; the next bold heading ends the section" || ko "bold heading: rc=$rc out='$out' err='$err'"

echo "-- normalization and stable ids"
out="$(node_eval '
const n = C.normalizeCriterionText;
console.log(JSON.stringify([n("- [ ]  a   b "), n("* [x] c"), n("1. d\te"), n("  plain  ")]));')"
[ "$out" = '["a b","c","d e","plain"]' ] && ok "normalization strips list and checkbox markers and surrounding whitespace, collapses inner whitespace" || ko "normalize: $out"
printf -- '- First line of a criterion\n  continued here\n    - folded sub-point\n- Second\n- Second\n' > "$TMP/fold.md"
run -- criteria from-md "$TMP/fold.md"
got="$(node -e 'const d=JSON.parse(process.argv[1]); console.log(d.criteria.map(c=>c.text).join("|"))' "$out" 2>&1)"
[ "$got" = 'First line of a criterion continued here folded sub-point|Second' ] \
  && ok "continuation lines and nested items fold into their parent; a repeated criterion appears once" || ko "fold: '$got'"

echo "-- criteriaSha256"
out="$(node_eval '
const arr = [{ id: "c-aaaaaaaaaaaa", text: "x" }, { id: "c-bbbbbbbbbbbb", text: "y \"z\"" }];
console.log(C.criteriaSha256(arr));')"
want_sha="$(sha_of '[{"id":"c-aaaaaaaaaaaa","text":"x"},{"id":"c-bbbbbbbbbbbb","text":"y \"z\""}]')"
[ "$out" = "$want_sha" ] && ok "criteriaSha256 is sha256 of the canonical criteria array (source excluded)" || ko "criteriaSha256: $out want $want_sha"

echo "-- check: the testability pre-check (AC4)"
printf -- '- the page looks good\n- %s\n' "$T1" | (cd "$R" && bash "$CLI" criteria from-text) > "$TMP/mixed.json" 2>/dev/null
vid="c-$(sha_of 'the page looks good' | cut -c1-12)"
tid="c-$(sha_of "$T1" | cut -c1-12)"
run -- criteria check "$TMP/mixed.json"
{ [ "$rc" -eq 0 ] && grep -qE "^vague $vid .*rewrite: .+" <<<"$out" && grep -qxF "testable $tid" <<<"$out"; } \
  && ok "AC4 'the page looks good' prints vague <id> with a rewrite; a criterion with a quoted value is testable" || ko "AC4 check: rc=$rc out='$out' err='$err'"
out="$(node_eval '
const phrases = ["works well", "looks good", "looks right", "looks nice", "user-friendly", "intuitive", "as expected", "properly", "correctly", "seamless"];
const c = (t) => C.classifyTestability(t);
const r = {
  frozen: Object.isFrozen(C.VAGUE_PHRASES) && JSON.stringify([...C.VAGUE_PHRASES]) === JSON.stringify(phrases),
  each: phrases.every((p) => c("The checkout " + p).testability === "vague"),
  rewrite: phrases.every((p) => { const x = c("The checkout " + p); return typeof x.rewrite === "string" && x.rewrite.length > 0 && x.phrase === p; }),
  digit: c("The total is computed correctly as 12").testability,
  quoted: c("The banner looks good and says \"Saved\"").testability,
  plain: c("The Save button stores the draft").testability,
  word: c("The improperly named field").testability,
  rewriteTestable: phrases.every((p) => c(c("The checkout " + p).rewrite).testability === "testable"),
};
console.log(JSON.stringify(r));')"
[ "$out" = '{"frozen":true,"each":true,"rewrite":true,"digit":"testable","quoted":"testable","plain":"testable","word":"testable","rewriteTestable":true}' ] \
  && ok "AC4 the fixed vague-phrase list: each phrase is vague with a rewrite; a digit or a quoted literal exempts; whole words only" || ko "AC4 classify: $out"
printf '{"schema_version":1,"source":null,"criteria":[{"id":"c-000000000000","text":"x"}]}' > "$TMP/badid.json"
run -- criteria check "$TMP/badid.json"
{ [ "$rc" -eq 2 ] && grep -qF 'criteria_invalid' <<<"$err"; } && ok "an id that is not its text's hash is criteria_invalid" || ko "bad id: rc=$rc err='$err'"
printf '{"schema_version":1,' > "$TMP/badjson.json"
run -- criteria check "$TMP/badjson.json"
{ [ "$rc" -eq 2 ] && grep -qF 'criteria_invalid' <<<"$err"; } && ok "malformed criteria.json is criteria_invalid" || ko "bad json: rc=$rc err='$err'"
run -- criteria check "$TMP/no-such.json"
{ [ "$rc" -eq 2 ] && grep -qF 'criteria_not_found' <<<"$err"; } && ok "a missing criteria.json is criteria_not_found" || ko "missing: rc=$rc err='$err'"

echo "-- the schema equals the validator's key sets (AC20)"
out="$(node_eval '
const s = JSON.parse((await import("node:fs")).readFileSync(process.env.SELVEDGE_CRITERIA_SCHEMA, "utf8"));
const eq = (a, b) => JSON.stringify([...a].sort()) === JSON.stringify([...b].sort());
const item = s.properties.criteria.items;
console.log(JSON.stringify([
  s["$schema"] === "https://json-schema.org/draft/2020-12/schema",
  s.additionalProperties === false && item.additionalProperties === false,
  eq(Object.keys(s.properties), C.CRITERIA_KEYS) && eq(s.required, C.CRITERIA_KEYS),
  eq(Object.keys(item.properties), C.CRITERION_KEYS) && eq(item.required, C.CRITERION_KEYS),
  item.properties.id.pattern === C.CRITERION_ID_PATTERN,
]));')"
[ "$out" = '[true,true,true,true,true]' ] && ok "AC20 criteria.schema.json (draft 2020-12, closed) names equal criteria.mjs's key sets and id pattern" || ko "AC20 criteria schema: $out"

echo "-- CLI and reasons"
out="$(bash "$CLI" 2>&1)"
{ grep -qE '^ +criteria <from-pr\|from-md\|from-text\|check>' <<<"$out" && grep -qE '^ +plan --validate' <<<"$out"; } \
  && ok "the CLI help lists criteria and plan" || ko "help: '$out'"
reasons="$(node --input-type=module -e "
import { pathToFileURL } from 'node:url';
const E = await import(pathToFileURL(process.env.SELVEDGE_LIB + '/env-config.mjs').href);
console.log(Object.keys(E.REASONS).join('|'));")"
mods="$(cd "$SELVEDGE_LIB" && bash -c 'shopt -s nullglob; echo criteria*.mjs plan*.mjs snapshot*.mjs')"
hits="$(cd "$SELVEDGE_LIB" && grep -nE "['\"\`]($reasons)['\"\`]" $mods)"
{ [ -n "$reasons" ] && [ -n "$mods" ] && [ -z "$hits" ]; } \
  && ok "AC20 no new module ($mods) names a reason as a string literal (REASONS only)" || ko "AC20 string-literal reasons: $hits"

echo "test-criteria: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
