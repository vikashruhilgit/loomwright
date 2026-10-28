#!/usr/bin/env bash
# test-lens-roles.sh — self-tests for lens-roles.sh (the role registry) and for
# lens-run.sh's role handling: the registered-role gate, the role's output-contract
# preamble, and the `text` role's result_text / marker rule.
#
# The provider is the REAL provider-cursor.sh table file driven by a PATH-stub
# `cursor-agent`, so this suite writes nothing into the providers directory (unlike
# test-lens-run.sh, which needs its own table entries). Every run is hermetic: a scratch
# HOME whose user-scope egress.json (EGRESS_FILE below) grants `cursor` for a scratch repo's
# pinned slug (lens-run.sh refuses an ungranted provider and has no bypass), a scratch
# repo as the invoking checkout, no network.
#
# Covers:
#   R. registry vs the seat list: every id `resolve-routing.sh seats` prints is a
#      registered role whose kind follows the seat's marker column (`-` = issues,
#      else text carrying that marker) and whose contract is non-empty — a seat added
#      to `seats` with no arm in lens-roles.sh fails HERE; `review` is registered;
#      unregistered / malformed role names are not
#   C. contract text: the `review` contract is byte-identical to the one lens-run.sh
#      always sent; a text contract names its marker and asks for plain text
#   U. an unregistered --role -> lens_unparseable, notes "unknown role", no sandbox,
#      the stub CLI never started
#   T. a text role: marker present -> ok + result_text round-tripped exactly (newlines,
#      quotes, backslash, non-ASCII), issues [], cost "unknown"; marker absent ->
#      lens_unparseable and no result_text; over the byte bound -> lens_unparseable
#      (never truncated); exactly at the bound -> ok (transport is not argv-limited)
#   P. the composed prompt carries the role's contract (text role: marker sentence and
#      no issues[] JSON; review role: the unchanged issues[] JSON)
#   I. issues-envelope seats (heal_voter, refute) and review: ok with normalized issues
#      and NO result_text key; the review output keeps exactly its original key set
#   G. the grant gate applies to a text role too: no grant (or an unreadable grant file,
#      or only a repo-config request) -> provider_not_granted, the stub never started;
#      with the grant the same run is ok
#   (U also covers a lens-run.sh with no lens-roles.sh beside it: fail closed)
#
# Exit 0 = all pass, 1 = any failure.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LENS="$HERE/lens-run.sh"
ROLES="$HERE/lens-roles.sh"
ROUTING="$HERE/../../resolve-routing.sh"
BASH_BIN="$(command -v bash)"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then ok "$label"; else no "$label (expected [$expected] got [$actual])"; fi
}
assert_true() {
  local label="$1" cond="$2"
  if [ "$cond" = "1" ]; then ok "$label"; else no "$label (condition false)"; fi
}
# has <needle> <haystack> -> 1 when the literal needle is in the haystack
has() { case "$2" in *"$1"*) echo 1 ;; *) echo 0 ;; esac; }

if ! command -v jq >/dev/null 2>&1; then
  echo "test-lens-roles.sh: jq is required to run this suite"; echo "RESULT: 0 passed, 1 failed"; exit 1
fi
for f in "$LENS" "$ROLES" "$ROUTING"; do
  if [ ! -f "$f" ]; then
    echo "test-lens-roles.sh: not found: $f"; echo "RESULT: 0 passed, 1 failed"; exit 1
  fi
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# ---- scratch HOME + scratch repo (pinned slug) + grant for `cursor` ---------------
export HOME="$TMP/home"
mkdir -p "$HOME"
EGRESS_FILE="$HOME/.claude/loomwright/egress.json"
SCRATCH_SLUG="lens-roles-owner/lens-roles-repo"
REPO_ROOT="$TMP/repo"
mkdir -p "$REPO_ROOT"
git -C "$REPO_ROOT" init -q
git -C "$REPO_ROOT" remote add origin "https://github.com/${SCRATCH_SLUG}.git"
printf 'scratch\n' > "$REPO_ROOT/README.txt"
git -C "$REPO_ROOT" add README.txt
git -C "$REPO_ROOT" -c user.name=lens-test -c user.email=lens-test@example.invalid -c commit.gpgsign=false commit -q -m "scratch commit"
# write_grants [provider-name...] — rewrites the scratch user-scope grant file.
write_grants() {
  mkdir -p "$(dirname "$EGRESS_FILE")"
  if [ "$#" -eq 0 ]; then
    jq -n --arg slug "$SCRATCH_SLUG" '{schema_version: 1, repos: {($slug): {providers: []}}}' > "$EGRESS_FILE"
  else
    printf '%s\n' "$@" | jq -R . | jq -s --arg slug "$SCRATCH_SLUG" \
      '{schema_version: 1, repos: {($slug): {providers: .}}}' > "$EGRESS_FILE"
  fi
}
write_grants cursor

DIFF_FILE="$TMP/diff.txt"
PROMPT_FILE="$TMP/prompt.txt"
printf 'diff --git a/src/foo.py b/src/foo.py\n+bug here\n' > "$DIFF_FILE"
printf 'Do the job described here.\n' > "$PROMPT_FILE"

# ---- the PATH-stub cursor-agent ----------------------------------------------------
# make_stub <name> <result-text-file> — writes $TMP/stub-<name>/cursor-agent, which records
# that it ran ($TMP/ran-<name>), dumps the prompt it was handed (its LAST argv element,
# the provider-cursor.sh contract) to $TMP/prompt-<name>, and prints the cursor envelope
# {"result": <the text file's content>}. Paths are baked at generation time (the child
# env is scrubbed, so no env var could steer it).
make_stub() {
  local name="$1" textfile="$2" dir="$TMP/stub-$1"
  mkdir -p "$dir"
  jq -n --rawfile r "$textfile" '{result: $r}' > "$TMP/envelope-$name.json"
  cat > "$dir/cursor-agent" <<STUB
#!/usr/bin/env bash
printf 'ran\\n' >> "$TMP/ran-$name"
last=""
for a in "\$@"; do last="\$a"; done
printf '%s' "\$last" > "$TMP/prompt-$name"
cat "$TMP/envelope-$name.json"
STUB
  chmod +x "$dir/cursor-agent"
}

# run_role <role> <stub-name> <out-file> — lens-run.sh from the scratch repo, with the
# named stub first on PATH. The debug hatch records the sandbox path when one is made.
run_role() {
  local role="$1" name="$2" out="$3"
  ( cd "$REPO_ROOT" && PATH="$TMP/stub-$name:$PATH" \
      LOOMWRIGHT_LENS_DEBUG_WT_PATH_FILE="$TMP/wt-$name" "$BASH_BIN" "$LENS" \
      --provider cursor --role "$role" \
      --diff "$DIFF_FILE" --prompt "$PROMPT_FILE" --out "$out" )
}
ran() { [ -f "$TMP/ran-$1" ] && echo 1 || echo 0; }
sandboxed() { [ -f "$TMP/wt-$1" ] && echo 1 || echo 0; }

echo "==== R: the registry covers the seat list ===="
SEATS="$(bash "$ROUTING" seats 2>/dev/null)"
SEAT_COUNT=0
while read -r id home marker validator; do
  [ -n "$id" ] || continue
  SEAT_COUNT=$((SEAT_COUNT+1))
  got="$( . "$ROLES"; if lens_role_lookup "$id"; then printf '%s|%s' "$LENS_ROLE_KIND" "$LENS_ROLE_MARKER"; else printf 'UNREGISTERED'; fi )"
  if [ "$marker" = "-" ]; then want="issues|"; else want="text|$marker"; fi
  assert_eq "R seat $id is a registered role of the kind its marker column says" "$want" "$got"
  contract="$( . "$ROLES"; lens_role_contract "$id" 2>/dev/null )"
  assert_true "R seat $id has a non-empty output contract" "$( [ -n "$contract" ] && echo 1 || echo 0 )"
  if [ "$marker" != "-" ]; then
    assert_true "R seat $id contract names its marker $marker" "$(has "$marker" "$contract")"
  else
    assert_true "R seat $id contract is the issues[] JSON contract" "$(has '{"issues": [' "$contract")"
  fi
done <<EOF
$SEATS
EOF
assert_true "R the seat list was non-empty (the loop above is not vacuous)" "$( [ "$SEAT_COUNT" -gt 0 ] && echo 1 || echo 0 )"
assert_eq "R review is a registered issues role" "issues|" "$( . "$ROLES"; lens_role_lookup review && printf '%s|%s' "$LENS_ROLE_KIND" "$LENS_ROLE_MARKER" )"
for bad in worker supervisor Review REVIEW nosuchrole "../review" "review;x" "two words" ""; do
  rc=0; ( . "$ROLES"; lens_role_lookup "$bad" ) || rc=$?
  assert_eq "R unregistered/malformed role [$bad] is not registered" "1" "$rc"
done
rc=0; ( . "$ROLES"; LENS_ROLES_ROUTING="$TMP/no-such-resolver.sh"; lens_role_lookup qa_strategist ) || rc=$?
assert_eq "R a missing resolve-routing.sh fails closed (no seat role registered)" "1" "$rc"
assert_eq "R ...but review stays registered without it" "0" "$( . "$ROLES"; LENS_ROLES_ROUTING="$TMP/no-such-resolver.sh"; lens_role_lookup review; echo $? )"

echo ""
echo "==== C: contract text ===="
LEGACY_REVIEW_CONTRACT='Respond with ONLY a single JSON object, no prose outside it, matching exactly:
{"issues": [{"severity": "BLOCKING|HIGH|MEDIUM|LOW", "category": "new|pre_existing|nit", "file": "<path>", "line": <integer or null>, "description": "<string>", "suggestion": "<string or null>"}]}'
assert_eq "C review contract is byte-identical to the one lens-run.sh always sent" "$LEGACY_REVIEW_CONTRACT" "$( . "$ROLES"; lens_role_contract review )"
C_TEXT="$( . "$ROLES"; lens_role_contract qa_strategist )"
assert_true "C a text contract asks for plain text" "$(has 'Respond in plain text only' "$C_TEXT")"
assert_true "C a text contract carries the MUST-contain marker sentence" "$(has 'Your answer MUST contain this exact token, verbatim: Classification' "$C_TEXT")"
assert_true "C a text contract does not ask for the issues[] JSON" "$( [ "$(has '"issues"' "$C_TEXT")" = "0" ] && echo 1 || echo 0 )"

echo ""
echo "==== U: an unregistered role -> lens_unparseable, 'unknown role', nothing started ===="
printf 'irrelevant\n' > "$TMP/text-u"; make_stub u "$TMP/text-u"
for badrole in worker Review 'bogus;touch x'; do
  OUT_U="$TMP/out-u.json"; rm -f "$OUT_U" "$TMP/ran-u" "$TMP/wt-u"
  RC_U=0; run_role "$badrole" u "$OUT_U" || RC_U=$?
  assert_eq "U [$badrole] rc=0" "0" "$RC_U"
  assert_eq "U [$badrole] lens_status=lens_unparseable" "lens_unparseable" "$(jq -r '.lens_status' "$OUT_U" 2>/dev/null)"
  assert_true "U [$badrole] notes say 'unknown role'" "$(has 'unknown role' "$(jq -r '.notes // empty' "$OUT_U" 2>/dev/null)")"
  assert_eq "U [$badrole] issues empty" "[]" "$(jq -c '.issues' "$OUT_U" 2>/dev/null)"
  assert_eq "U [$badrole] no sandbox created" "0" "$(sandboxed u)"
  assert_eq "U [$badrole] provider CLI never started" "0" "$(ran u)"
done

# A lens-run.sh with no lens-roles.sh beside it fails closed: no role resolves, nothing starts.
mkdir -p "$TMP/nolr"
cp "$LENS" "$TMP/nolr/lens-run.sh"; cp "$HERE/provider-cursor.sh" "$TMP/nolr/provider-cursor.sh"
rm -f "$TMP/ran-u" "$TMP/wt-u"
RC_U2=0
( cd "$REPO_ROOT" && PATH="$TMP/stub-u:$PATH" LOOMWRIGHT_LENS_DEBUG_WT_PATH_FILE="$TMP/wt-u" "$BASH_BIN" "$TMP/nolr/lens-run.sh" \
    --provider cursor --role review --diff "$DIFF_FILE" --prompt "$PROMPT_FILE" --out "$TMP/out-u2.json" ) || RC_U2=$?
assert_eq "U lens-roles.sh missing: rc=0" "0" "$RC_U2"
assert_eq "U lens-roles.sh missing: lens_unparseable" "lens_unparseable" "$(jq -r '.lens_status' "$TMP/out-u2.json" 2>/dev/null)"
assert_true "U lens-roles.sh missing: notes name the missing registry" "$(has 'lens-roles.sh is missing' "$(jq -r '.notes // empty' "$TMP/out-u2.json" 2>/dev/null)")"
assert_eq "U lens-roles.sh missing: provider CLI never started" "0" "$(ran u)"

echo ""
echo "==== T: a text role -> result_text, marker rule, byte bound ===="
# Text with newlines, quotes, a backslash and non-ASCII, ending in the marker line.
printf 'Strategy line 1\n"quoted" and back\\slash and caf\xc3\xa9\nClassification: HIGH risk\nlast line' > "$TMP/text-t1"
make_stub t1 "$TMP/text-t1"
OUT_T1="$TMP/out-t1.json"
RC_T1=0; run_role qa_strategist t1 "$OUT_T1" || RC_T1=$?
assert_eq "T ok rc=0" "0" "$RC_T1"
assert_eq "T ok lens_status=ok" "ok" "$(jq -r '.lens_status' "$OUT_T1" 2>/dev/null)"
assert_true "T ok result_text is the provider's text, byte for byte" "$( jq -j '.result_text' "$OUT_T1" 2>/dev/null | cmp -s - "$TMP/text-t1" && echo 1 || echo 0 )"
assert_eq "T ok issues is []" "[]" "$(jq -c '.issues' "$OUT_T1" 2>/dev/null)"
assert_eq "T ok cost is honestly 'unknown', never 0" "unknown" "$(jq -r '.cost' "$OUT_T1" 2>/dev/null)"
assert_eq "T ok model is null" "null" "$(jq -c '.model' "$OUT_T1" 2>/dev/null)"
assert_eq "T ok provider field" "cursor" "$(jq -r '.provider' "$OUT_T1" 2>/dev/null)"
assert_eq "T ok no notes on an ok result" "false" "$(jq 'has("notes")' "$OUT_T1" 2>/dev/null)"
assert_eq "T ok sandbox was removed after the run" "0" "$( [ -s "$TMP/wt-t1" ] && [ -e "$(cat "$TMP/wt-t1")" ] && echo 1 || echo 0 )"

# A marker with a slash (orchestrator) matches literally, not as a pattern.
printf 'Context Read\nWork/Results\nRisks' > "$TMP/text-t2"; make_stub t2 "$TMP/text-t2"
run_role orchestrator t2 "$TMP/out-t2.json" || true
assert_eq "T orchestrator text containing Work/Results -> ok" "ok" "$(jq -r '.lens_status' "$TMP/out-t2.json" 2>/dev/null)"
printf 'Context Read\nWork Results\nRisks' > "$TMP/text-t3"; make_stub t3 "$TMP/text-t3"
run_role orchestrator t3 "$TMP/out-t3.json" || true
assert_eq "T orchestrator text WITHOUT the exact marker -> lens_unparseable" "lens_unparseable" "$(jq -r '.lens_status' "$TMP/out-t3.json" 2>/dev/null)"
assert_eq "T no marker -> no result_text key in the output" "false" "$(jq 'has("result_text")' "$TMP/out-t3.json" 2>/dev/null)"
assert_true "T no marker -> notes name the role marker" "$(has 'role marker' "$(jq -r '.notes // empty' "$TMP/out-t3.json" 2>/dev/null)")"
assert_eq "T no marker -> issues is []" "[]" "$(jq -c '.issues' "$TMP/out-t3.json" 2>/dev/null)"

# An issues[] answer from a text role is not a pass: no marker, no ok.
printf '{"issues":[]}' > "$TMP/text-t4"; make_stub t4 "$TMP/text-t4"
run_role rubric_grader t4 "$TMP/out-t4.json" || true
assert_eq "T an issues[] answer to a text role (no marker) -> lens_unparseable" "lens_unparseable" "$(jq -r '.lens_status' "$TMP/out-t4.json" 2>/dev/null)"

# Byte bound: LENS_RESULT_TEXT_MAX is read from the registry, not restated here.
BOUND="$( . "$ROLES"; printf '%s' "$LENS_RESULT_TEXT_MAX" )"
# (a function, not a case inside $( ): bash 3.2 mis-parses the `)` of a case pattern there)
is_posint() { case "$1" in ""|*[!0-9]*|0) echo 0 ;; *) echo 1 ;; esac; }
assert_true "T the bound is a positive integer" "$(is_posint "$BOUND")"
# gen_text <total-bytes> <file>: the marker, then filler up to exactly total-bytes bytes.
gen_text() {
  printf 'Classification' > "$2"
  head -c "$(( $1 - 14 ))" /dev/zero | tr '\0' 'a' >> "$2"
}
gen_text "$BOUND" "$TMP/text-t5"; make_stub t5 "$TMP/text-t5"
run_role qa_strategist t5 "$TMP/out-t5.json" || true
assert_eq "T exactly at the bound ($BOUND bytes) -> ok (result_text is not argv-limited)" "ok" "$(jq -r '.lens_status' "$TMP/out-t5.json" 2>/dev/null)"
assert_true "T exactly at the bound -> result_text is intact" "$( jq -j '.result_text' "$TMP/out-t5.json" 2>/dev/null | cmp -s - "$TMP/text-t5" && echo 1 || echo 0 )"
gen_text "$(( BOUND + 1 ))" "$TMP/text-t6"; make_stub t6 "$TMP/text-t6"
run_role qa_strategist t6 "$TMP/out-t6.json" || true
assert_eq "T one byte over the bound -> lens_unparseable (never a truncated ok)" "lens_unparseable" "$(jq -r '.lens_status' "$TMP/out-t6.json" 2>/dev/null)"
assert_eq "T over the bound -> no result_text key" "false" "$(jq 'has("result_text")' "$TMP/out-t6.json" 2>/dev/null)"
assert_true "T over the bound -> notes name the bound" "$(has 'bound' "$(jq -r '.notes // empty' "$TMP/out-t6.json" 2>/dev/null)")"

echo ""
echo "==== P: the composed prompt carries the role's contract ===="
PROMPT_T1="$(cat "$TMP/prompt-t1" 2>/dev/null)"
assert_true "P text role: prompt names the role" "$(has 'Role: qa_strategist' "$PROMPT_T1")"
assert_true "P text role: prompt has the OUTPUT CONTRACT section" "$(has '--- OUTPUT CONTRACT ---' "$PROMPT_T1")"
assert_true "P text role: prompt carries the MUST-contain marker sentence" "$(has 'Your answer MUST contain this exact token, verbatim: Classification' "$PROMPT_T1")"
assert_true "P text role: prompt carries the role's own shape sentence" "$(has 'risk-based test strategy' "$PROMPT_T1")"
assert_true "P text role: prompt does NOT ask for the issues[] JSON" "$( [ "$(has '{"issues": [' "$PROMPT_T1")" = "0" ] && echo 1 || echo 0 )"
assert_true "P text role: the caller's prompt and the diff are still folded in" "$( [ "$(has 'Do the job described here.' "$PROMPT_T1")" = "1" ] && [ "$(has '+bug here' "$PROMPT_T1")" = "1" ] && echo 1 || echo 0 )"

echo ""
echo "==== I: issues-envelope roles keep the existing shape and gain no result_text ===="
printf '%s' '{"issues":[{"severity":"high","category":"new","file":"src/foo.py","line":42,"description":"unhandled error","suggestion":"add try/catch"}]}' > "$TMP/text-i1"
make_stub i1 "$TMP/text-i1"
EXPECTED_I='[{"severity":"HIGH","category":"new","file":"src/foo.py","line":42,"description":"unhandled error","suggestion":"add try/catch"}]'
for r in review heal_voter refute; do
  OUT_I="$TMP/out-i-$r.json"
  RC_I=0; run_role "$r" i1 "$OUT_I" || RC_I=$?
  assert_eq "I [$r] rc=0" "0" "$RC_I"
  assert_eq "I [$r] lens_status=ok" "ok" "$(jq -r '.lens_status' "$OUT_I" 2>/dev/null)"
  assert_eq "I [$r] issues normalized (severity upcased)" "$EXPECTED_I" "$(jq -c '.issues' "$OUT_I" 2>/dev/null)"
  assert_eq "I [$r] no result_text key" "false" "$(jq 'has("result_text")' "$OUT_I" 2>/dev/null)"
done
assert_eq "I review output keeps exactly its original key set" '["cost","issues","lens_status","model","provider"]' "$(jq -c 'keys' "$TMP/out-i-review.json" 2>/dev/null)"
assert_eq "I review cost is 'unknown'" "unknown" "$(jq -r '.cost' "$TMP/out-i-review.json" 2>/dev/null)"
PROMPT_I1="$(cat "$TMP/prompt-i1" 2>/dev/null)"
assert_true "I review prompt carries the unchanged issues[] JSON contract" "$(has "$LEGACY_REVIEW_CONTRACT" "$PROMPT_I1")"
assert_true "I the issues roles' prompt has no marker sentence" "$( [ "$(has 'MUST contain this exact token' "$PROMPT_I1")" = "0" ] && echo 1 || echo 0 )"

echo ""
echo "==== G: the grant gate applies to a text role ===="
write_grants
printf 'Classification\n' > "$TMP/text-g"; make_stub g "$TMP/text-g"
RC_G=0; run_role qa_strategist g "$TMP/out-g.json" || RC_G=$?
assert_eq "G rc=0" "0" "$RC_G"
assert_eq "G no grant -> provider_not_granted" "provider_not_granted" "$(jq -r '.lens_status' "$TMP/out-g.json" 2>/dev/null)"
assert_eq "G no grant -> no result_text key" "false" "$(jq 'has("result_text")' "$TMP/out-g.json" 2>/dev/null)"
assert_eq "G no grant -> no sandbox created" "0" "$(sandboxed g)"
assert_eq "G no grant -> provider CLI never started" "0" "$(ran g)"
# An unreadable user-scope file is no grant; a repo's own config can only REQUEST, never grant.
printf '{not json' > "$EGRESS_FILE"
run_role qa_strategist g "$TMP/out-g3.json" || true
assert_eq "G malformed egress.json -> provider_not_granted" "provider_not_granted" "$(jq -r '.lens_status' "$TMP/out-g3.json" 2>/dev/null)"
write_grants
mkdir -p "$REPO_ROOT/.supervisor"
printf '{"routing":{"seats":{"qa_strategist":"cursor"}},"providers":["cursor"]}\n' > "$REPO_ROOT/.supervisor/config.json"
run_role qa_strategist g "$TMP/out-g4.json" || true
rm -rf "$REPO_ROOT/.supervisor"
assert_eq "G a repo-config request for the provider does not grant" "provider_not_granted" "$(jq -r '.lens_status' "$TMP/out-g4.json" 2>/dev/null)"
assert_eq "G ...and the CLI still never started" "0" "$(ran g)"
write_grants cursor
RC_G2=0; run_role qa_strategist g "$TMP/out-g2.json" || RC_G2=$?
assert_eq "G control: granted -> the same run is ok" "ok" "$(jq -r '.lens_status' "$TMP/out-g2.json" 2>/dev/null)"
assert_eq "G control: granted -> the CLI did run" "1" "$(ran g)"

echo ""
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && exit 0 || exit 1
