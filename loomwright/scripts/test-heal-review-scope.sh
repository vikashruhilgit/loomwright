#!/usr/bin/env bash
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
# test-heal-review-scope.sh — self-tests for heal-review-scope.sh (Phase 4.5 converging re-review).
# Exit 0 = all pass, 1 = any failure. UNCOUNTED by the doc-currency gate (test-*.sh).
#
# Covers:
#   M.  mode: absent file / absent key => shadow; shadow / files / full => itself; unknown string,
#       non-string, null, non-object, malformed JSON, jq absent => full.
#   S.  scope over a scratch repo: round 1 => `scope: full` with no fallback line; a two-commit fix
#       => exactly the changed files; a deleted file is excluded; non-ancestor prev, a merge commit
#       in prev..head, a deletion-only fix, `-` / unknown prev => the named scope_fallback; a --head
#       that is not a commit and a bad --round are usage errors (exit 2).
#   F.  fingerprint: {file, issue_category, rule}, rule = 12 hex of git hash-object over the
#       normalised description, drift => drift:<kind>, no prose in the output.
#   R.  record: valid lines appended (parent dir created); a prose key, a missing run_id, a value
#       outside a closed set refused with ONE `heal_round_record_failed:` line; exit 0 always.
#   P.  prev-sha: the current run's last round only; other runs and junk lines ignored.
#   U.  suppress: a same-run dismissed repeat is dropped; a fixed repeat is kept and listed in
#       repeat_of_fixed; a higher-severity repeat and another run's dismissal are kept;
#       --count-only keeps everything; fail-safe paths.
#   H.  --shadow-report: exact output, --since filtering with `unreachable`, and that it writes
#       nothing (tree, .git and the records dir byte-identical before and after).
#   K.  MUTATION CONTROL against a COPY: `scope` printing `scope: full` before computing anything
#       must turn every round >= 2 scope case red (the mutant is checked non-empty, different from
#       the original and `bash -n` clean before it is trusted).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/heal-review-scope.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-hrs.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

NL='
'

# ------------------------------------------------------------------ scratch repo for scope
REPO="$TMP/repo"
g() { git -C "$REPO" -c user.name=t -c user.email=t@x -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }
mkdir -p "$REPO"
git -c init.defaultBranch=main init -q "$REPO"
printf 'a\n' > "$REPO/a.txt"; printf 'b\n' > "$REPO/b.txt"; printf 'c\n' > "$REPO/c.txt"; printf 'g\n' > "$REPO/gone.txt"
g add -A && g commit -q -m A
SHA_A="$(g rev-parse HEAD)"
# B: modify a.txt, add d/new.txt, delete gone.txt — the two-commit fix.
printf 'a2\n' > "$REPO/a.txt"; mkdir -p "$REPO/d"; printf 'n\n' > "$REPO/d/new.txt"; rm "$REPO/gone.txt"
g add -A && g commit -q -m B
SHA_B="$(g rev-parse HEAD)"
# C: a side commit off A — never an ancestor of main.
g checkout -q -b side "$SHA_A"
printf 'c-side\n' > "$REPO/c.txt"; g add -A && g commit -q -m C
SHA_C="$(g rev-parse HEAD)"
# M: a --no-ff merge of a feature branch on top of B.
g checkout -q -b feat "$SHA_B"
printf 'c-feat\n' > "$REPO/c.txt"; g add -A && g commit -q -m F
g checkout -q main
g merge -q --no-ff -m M feat
SHA_M="$(g rev-parse HEAD)"
# E: a deletion-only fix on top of M.
rm "$REPO/b.txt"; g add -A && g commit -q -m E
SHA_E="$(g rev-parse HEAD)"

# sc <case-id> <desc> <script> <want-stdout> <args...> — exit 0 and exact stdout.
sc() {
  local id="$1" desc="$2" s="$3" want="$4"; shift 4
  local got rc
  got="$(bash "$s" scope --root "$REPO" "$@" 2>/dev/null)"; rc=$?
  if [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; then ok "$id $desc"; else no "$id $desc — rc=$rc got [$got] want [$want]"; fi
}

run_scope_table() {
  local s="$1" got rc
  sc S1 "round 1 => scope: full, no fallback line" "$s" "scope: full" --round 1 --prev - --head "$SHA_B"
  sc S2 "two-commit fix => exactly the changed files" "$s" "scope: files${NL}a.txt${NL}d/new.txt" \
    --round 2 --prev "$SHA_A" --head "$SHA_B"
  got="$(bash "$s" scope --root "$REPO" --round 2 --prev "$SHA_A" --head "$SHA_B" 2>/dev/null)"
  if [ "$(printf '%s\n' "$got" | head -n 1)" = "scope: files" ] && ! printf '%s\n' "$got" | grep -qx 'gone.txt'; then
    ok "S3 deleted file excluded from a files scope"
  else
    no "S3 deleted file excluded from a files scope — got [$got]"
  fi
  sc S4 "prev not an ancestor => not_ancestor" "$s" "scope: full${NL}scope_fallback: not_ancestor" \
    --round 2 --prev "$SHA_C" --head "$SHA_B"
  sc S5 "merge commit in prev..head => merge_commit" "$s" "scope: full${NL}scope_fallback: merge_commit" \
    --round 3 --prev "$SHA_B" --head "$SHA_M"
  sc S6 "deletion-only fix => empty_scope" "$s" "scope: full${NL}scope_fallback: empty_scope" \
    --round 2 --prev "$SHA_M" --head "$SHA_E"
  sc S7 "prev '-' => missing_prev_sha" "$s" "scope: full${NL}scope_fallback: missing_prev_sha" \
    --round 2 --prev - --head "$SHA_B"
  sc S8 "unknown prev sha => missing_prev_sha" "$s" "scope: full${NL}scope_fallback: missing_prev_sha" \
    --round 2 --prev 0123456789abcdef0123456789abcdef01234567 --head "$SHA_B"
  got="$(bash "$s" scope --root "$REPO" --round 2 --prev "$SHA_A" --head nosuchref 2>/dev/null)"; rc=$?
  if [ "$rc" -eq 2 ] && [ -z "$got" ]; then ok "S9 --head not a commit => usage error"; else no "S9 --head not a commit — rc=$rc got [$got]"; fi
  got="$(bash "$s" scope --root "$REPO" --round two --head "$SHA_B" 2>/dev/null)"; rc=$?
  if [ "$rc" -eq 2 ] && [ -z "$got" ]; then ok "S10 bad --round => usage error"; else no "S10 bad --round — rc=$rc got [$got]"; fi
}

# ------------------------------------------------------------------ M — mode
root_with() {
  local r="$TMP/roots/$1"
  mkdir -p "$r/.supervisor"
  if [ "$2" != "ABSENT" ]; then printf '%s' "$2" > "$r/.supervisor/config.json"; fi
  printf '%s' "$r"
}
md() {
  local id="$1" desc="$2" want="$3" r="$4" got rc
  got="$(bash "$SCRIPT" mode --root "$r" 2>/dev/null)"; rc=$?
  if [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; then ok "$id $desc"; else no "$id $desc — rc=$rc got [$got] want [$want]"; fi
}

echo "M — mode"
md M1 "absent config file => shadow" shadow "$(root_with none ABSENT)"
md M2 "absent key => shadow" shadow "$(root_with nokey '{"fix_floor":"HIGH"}')"
md M3 "files => files" files "$(root_with files '{"heal_review_scope":"files"}')"
md M4 "full => full" full "$(root_with full '{"heal_review_scope":"full"}')"
md M5 "shadow => shadow" shadow "$(root_with shadow '{"heal_review_scope":"shadow"}')"
md M6 "unknown string => full" full "$(root_with unknown '{"heal_review_scope":"narrow"}')"
md M7 "non-string => full" full "$(root_with num '{"heal_review_scope":2}')"
md M8 "null => full" full "$(root_with null '{"heal_review_scope":null}')"
md M9 "malformed JSON => full" full "$(root_with junk '{"heal_review_scope": "files",')"
md M10 "non-object config => full" full "$(root_with arr '["files"]')"
got="$(JQ="$TMP/no-such-jq" bash "$SCRIPT" mode --root "$TMP/roots/files" 2>/dev/null)"
if [ "$got" = "full" ]; then ok "M11 jq absent with a config => full"; else no "M11 jq absent — got [$got]"; fi

echo "S — scope"
run_scope_table "$SCRIPT"

# ------------------------------------------------------------------ F — fingerprint
echo "F — fingerprint"
fpr() { printf '%s' "$1" | bash "$SCRIPT" fingerprint 2>/dev/null; }
f1="$(fpr '{"severity":"HIGH","category":"new","file":"src/x.sh","line":3,"description":"Foo   BAR\n\tbaz ","suggestion":"fix it"}')"
f2="$(fpr '{"severity":"LOW","category":"new","file":"src/x.sh","description":"foo bar baz"}')"
f3="$(fpr '{"severity":"LOW","category":"new","file":"src/x.sh","description":"foo bar qux"}')"
want_rule="$(printf '%s' 'foo bar baz' | git hash-object --stdin | cut -c1-12)"
if [ "$(printf '%s' "$f1" | jq -c 'keys')" = '["file","issue_category","rule"]' ]; then ok "F1 exactly {file, issue_category, rule}"; else no "F1 keys — got [$f1]"; fi
if [ "$(printf '%s' "$f1" | jq -r '.rule')" = "$want_rule" ]; then ok "F2 rule = 12 hex of git hash-object over the normalised description"; else no "F2 rule — got [$f1] want rule $want_rule"; fi
if [ -n "$f1" ] && [ "$f1" = "$f2" ]; then ok "F3 case / whitespace differences fingerprint the same"; else no "F3 normalisation — [$f1] vs [$f2]"; fi
if [ -n "$f3" ] && [ "$f1" != "$f3" ]; then ok "F4 a different description fingerprints differently"; else no "F4 — [$f1] vs [$f3]"; fi
fd="$(fpr '{"severity":"MEDIUM","category":"drift","drift_kind":"doc","file":"README.md","description":"d"}')"
if [ "$(printf '%s' "$fd" | jq -r '.issue_category + " " + .file')" = "drift:doc README.md" ]; then ok "F5 drift => drift:<drift_kind>"; else no "F5 drift — got [$fd]"; fi
if ! printf '%s' "$f1" | grep -qi 'foo\|fix it'; then ok "F6 no finding prose in the fingerprint"; else no "F6 prose leaked — [$f1]"; fi
out="$(printf '[1,2]' | bash "$SCRIPT" fingerprint 2>/dev/null)"; rc=$?
if [ "$rc" -eq 2 ] && [ -z "$out" ]; then ok "F7 non-object stdin => usage error"; else no "F7 — rc=$rc out [$out]"; fi

# ------------------------------------------------------------------ R — record
echo "R — record"
RF="$TMP/rec/.supervisor/heal-rounds/brief.jsonl"
lines() { if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }
# rec <stdin> — runs record into $RF; sets RC, ERR.
rec() {
  printf '%s' "$1" | bash "$SCRIPT" record --file "$RF" 2>"$TMP/rec.err" >"$TMP/rec.out"; RC=$?
  ERR="$(cat "$TMP/rec.err")"
}
ROUND='{"kind":"round","run_id":"r1","iteration":2,"reviewed_sha":"abc","pr":7,"mode":"shadow","scope":"full","scope_files":1,"full_files":3,"would_scope":["a.txt"],"scope_fallback":null,"would_suppress":[],"suppressed_repeat":0,"repeat_of_fixed":[],"review_started_at":"2026-11-01T10:00:00Z","review_ended_at":"2026-11-01T10:05:00Z"}'
FIND='{"kind":"finding","run_id":"r1","iteration":2,"reviewed_sha":"abc","pr":7,"file":"a.txt","issue_category":"new","rule":"0123456789ab","severity":"HIGH","outcome":"fixed","fix_commit":"def","in_would_scope":true}'
rec "$ROUND$NL$FIND$NL"
if [ "$RC" -eq 0 ] && [ -z "$ERR" ] && [ "$(lines "$RF")" = 2 ]; then ok "R1 valid round + finding appended (parent dir created)"; else no "R1 — rc=$RC err [$ERR] lines $(lines "$RF")"; fi
before="$(cat "$RF")"
rec '{"kind":"finding","run_id":"r1","iteration":2,"file":"a.txt","outcome":"dismissed","description":"SECRET PROSE"}'
if [ "$RC" -eq 0 ] && [ "$(cat "$RF")" = "$before" ] && printf '%s' "$ERR" | grep -q '^heal_round_record_failed: '; then
  ok "R2 a record carrying a prose key is refused (file unchanged, one failure line, exit 0)"
else
  no "R2 prose key — rc=$RC err [$ERR] file now [$(cat "$RF")]"
fi
if ! grep -q 'SECRET PROSE' "$RF"; then ok "R3 refused prose never reaches the file"; else no "R3 prose reached the file"; fi
rec '{"kind":"finding","iteration":2,"file":"a.txt","outcome":"fixed"}'
if [ "$RC" -eq 0 ] && [ "$(cat "$RF")" = "$before" ] && printf '%s' "$ERR" | grep -q '^heal_round_record_failed: .*run_id'; then ok "R4 missing run_id refused"; else no "R4 — rc=$RC err [$ERR]"; fi
rec '{"kind":"finding","run_id":"r1","outcome":"ignored"}'
if [ "$(cat "$RF")" = "$before" ] && [ -n "$ERR" ]; then ok "R5 outcome outside its closed set refused"; else no "R5 — err [$ERR]"; fi
rec '{"kind":"round","run_id":"r1","scope_fallback":"because"}'
if [ "$(cat "$RF")" = "$before" ] && [ -n "$ERR" ]; then ok "R6 scope_fallback outside its closed set refused"; else no "R6 — err [$ERR]"; fi
rec '{"kind":"round","run_id":"r1","would_suppress":[{"file":"a","issue_category":"new","rule":"x","finding":"prose"}]}'
if [ "$(cat "$RF")" = "$before" ] && [ -n "$ERR" ]; then ok "R7 prose nested in a fingerprint array refused"; else no "R7 — err [$ERR]"; fi
rec "$FIND${NL}not json${NL}{\"kind\":\"finding\",\"run_id\":\"r1\",\"finding\":\"x\"}$NL"
nerr="$(printf '%s\n' "$ERR" | grep -c . || true)"
if [ "$RC" -eq 0 ] && [ "$(lines "$RF")" = 3 ] && [ "$nerr" = 1 ] && printf '%s' "$ERR" | grep -q '2 record(s) refused'; then
  ok "R8 mixed batch: the valid line appended, the rest refused on ONE stderr line"
else
  no "R8 mixed batch — rc=$RC lines $(lines "$RF") err [$ERR]"
fi
: > "$TMP/afile"
out="$(printf '%s\n' "$FIND" | bash "$SCRIPT" record --file "$TMP/afile/x.jsonl" 2>&1 >/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^heal_round_record_failed: '; then ok "R9 an unwritable path fails SAFE (exit 0, one line)"; else no "R9 — rc=$rc out [$out]"; fi
out="$(printf '%s\n' "$FIND" | JQ="$TMP/no-such-jq" bash "$SCRIPT" record --file "$TMP/nojq.jsonl" 2>&1 >/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "heal_round_record_failed: jq not found" ] && [ ! -e "$TMP/nojq.jsonl" ]; then ok "R10 jq absent fails SAFE"; else no "R10 — rc=$rc out [$out]"; fi

# ------------------------------------------------------------------ P — prev-sha
echo "P — prev-sha"
PF="$TMP/prev.jsonl"
{
  echo '{"kind":"round","run_id":"r1","iteration":1,"reviewed_sha":"s1"}'
  echo '{"kind":"round","run_id":"r2","iteration":1,"reviewed_sha":"s9"}'
  echo 'junk {'
  echo '{"kind":"finding","run_id":"r1","iteration":2,"reviewed_sha":"sf"}'
  echo '{"kind":"round","run_id":"r1","iteration":2,"reviewed_sha":"s2"}'
  echo '{"kind":"round","run_id":"r2","iteration":2,"reviewed_sha":"s8"}'
} > "$PF"
got="$(bash "$SCRIPT" prev-sha --file "$PF" --run-id r1 2>/dev/null)"
if [ "$got" = "s2" ]; then ok "P1 the current run's last round sha; another run's later round ignored"; else no "P1 — got [$got]"; fi
got="$(bash "$SCRIPT" prev-sha --file "$PF" --run-id r3 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && [ -z "$got" ]; then ok "P2 a run with no rounds prints nothing"; else no "P2 — rc=$rc got [$got]"; fi
got="$(bash "$SCRIPT" prev-sha --file "$TMP/missing.jsonl" --run-id r1 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && [ -z "$got" ]; then ok "P3 a missing record file prints nothing"; else no "P3 — rc=$rc got [$got]"; fi

# ------------------------------------------------------------------ U — suppress
echo "U — suppress"
fp_of() { printf '{"category":"new","file":"%s","description":"%s"}' "$1" "$2" | bash "$SCRIPT" fingerprint; }
FPX="$(fp_of x.sh 'x is wrong')"; FPY="$(fp_of y.sh 'y is wrong')"; FPZ="$(fp_of z.sh 'z is wrong')"
SF="$TMP/sup.jsonl"
finding_rec() { printf '%s' "$2" | jq -c --arg run "$1" --arg out "$3" --arg sev "$4" \
  '{kind:"finding", run_id:$run, iteration:1} + . + {outcome:$out, severity:$sev}'; }
{
  finding_rec r1 "$FPX" dismissed MEDIUM
  finding_rec r1 "$FPY" fixed HIGH
  finding_rec r0 "$FPZ" dismissed HIGH
} > "$SF"
ISSUES='[
 {"severity":"MEDIUM","category":"new","file":"x.sh","description":"x is wrong"},
 {"severity":"HIGH","category":"new","file":"y.sh","description":"y is wrong"},
 {"severity":"LOW","category":"new","file":"z.sh","description":"z is wrong"},
 {"severity":"HIGH","category":"new","file":"x.sh","description":"X  is wrong"},
 {"severity":"low","category":"new","file":"x.sh","description":"x is wrong"},
 {"category":"new","file":"x.sh","description":"x is wrong"}
]'
res="$(printf '%s' "$ISSUES" | bash "$SCRIPT" suppress --file "$SF" --run-id r1 2>"$TMP/sup.err")"; rc=$?
kept="$(printf '%s' "$res" | jq -c '[.kept[] | "\(.severity // "none"):\(.file)"]' 2>/dev/null)"
if [ "$rc" -eq 0 ] && printf '%s' "$kept" | grep -qv '"MEDIUM:x.sh"' && [ "$(printf '%s' "$res" | jq '.count' 2>/dev/null)" -ge 1 ] 2>/dev/null; then
  ok "U1 a same-run dismissed fingerprint at the same severity is dropped"
else
  no "U1 dismissed repeat — rc=$rc res [$res]"
fi
if printf '%s' "$kept" | grep -q '"HIGH:y.sh"' \
   && [ "$(printf '%s' "$res" | jq -c '.repeat_of_fixed' 2>/dev/null)" = "[$FPY]" ]; then
  ok "U2 a fixed fingerprint is NOT dropped; it is counted in repeat_of_fixed"
else
  no "U2 fixed repeat — res [$res]"
fi
if printf '%s' "$kept" | grep -q '"LOW:z.sh"'; then ok "U3 another run's dismissed fingerprint is NOT dropped"; else no "U3 other run — kept [$kept]"; fi
if printf '%s' "$kept" | grep -q '"HIGH:x.sh"'; then ok "U4 a dismissed fingerprint re-reported at a HIGHER severity is NOT dropped"; else no "U4 higher severity — kept [$kept]"; fi
if [ "$kept" = '["HIGH:y.sh","LOW:z.sh","HIGH:x.sh","none:x.sh"]' ] \
   && [ "$(printf '%s' "$res" | jq -c '[.count, .suppressed]')" = "[2,[$FPX,$FPX]]" ] && [ ! -s "$TMP/sup.err" ]; then
  ok "U5 exact result: order kept, lower-case severity ranks, an unranked severity is never dropped"
else
  no "U5 exact — kept [$kept] res [$res] err [$(cat "$TMP/sup.err")]"
fi
res="$(printf '%s' "$ISSUES" | bash "$SCRIPT" suppress --file "$SF" --run-id r1 --count-only 2>/dev/null)"
if [ "$(printf '%s' "$res" | jq -c '[(.kept | length), .count, (.suppressed | length), (.repeat_of_fixed | length)]')" = "[6,2,2,1]" ]; then
  ok "U6 --count-only keeps every issue and reports the would-suppress count"
else
  no "U6 count-only — res [$res]"
fi
res="$(printf '%s' "$ISSUES" | bash "$SCRIPT" suppress --file "$TMP/none.jsonl" --run-id r1 2>"$TMP/sup.err")"
if [ "$(printf '%s' "$res" | jq -c '[(.kept | length), .count]')" = "[6,0]" ] && [ ! -s "$TMP/sup.err" ]; then
  ok "U7 a missing record file suppresses nothing"
else
  no "U7 — res [$res]"
fi
res="$(printf 'not json' | bash "$SCRIPT" suppress --file "$SF" --run-id r1 2>"$TMP/sup.err")"; rc=$?
if [ "$rc" -eq 0 ] && [ -z "$res" ] && grep -q '^heal_review_suppress_failed: ' "$TMP/sup.err"; then
  ok "U8 stdin that is not an array: nothing on stdout, one stderr line, exit 0"
else
  no "U8 — rc=$rc res [$res]"
fi
res="$(printf '%s' "$ISSUES" | JQ="$TMP/no-such-jq" bash "$SCRIPT" suppress --file "$SF" --run-id r1 2>"$TMP/sup.err")"
if [ "$(printf '%s' "$res" | jq -c '[(.kept | length), .count]')" = "[6,0]" ] && [ -s "$TMP/sup.err" ]; then
  ok "U9 jq absent keeps every issue (fails toward reporting more)"
else
  no "U9 — res [$res]"
fi
cp "$SF" "$TMP/sup-locked.jsonl"; chmod 000 "$TMP/sup-locked.jsonl"
if [ -r "$TMP/sup-locked.jsonl" ]; then
  ok "U10 skipped — running as a user that can read a mode-000 file"
else
  res="$(printf '%s' "$ISSUES" | bash "$SCRIPT" suppress --file "$TMP/sup-locked.jsonl" --run-id r1 2>"$TMP/sup.err")"
  if [ "$(printf '%s' "$res" | jq -c '[(.kept | length), .count]')" = "[6,0]" ] && grep -q '^heal_review_suppress_failed: cannot read' "$TMP/sup.err"; then
    ok "U10 an unreadable record file keeps every issue, one stderr line"
  else
    no "U10 — res [$res] err [$(cat "$TMP/sup.err")]"
  fi
fi
chmod 600 "$TMP/sup-locked.jsonl"

# ------------------------------------------------------------------ H — --shadow-report
echo "H — --shadow-report"
HD="$REPO/.supervisor/heal-rounds"
mkdir -p "$HD"
{
  echo '{"kind":"round","run_id":"ra","iteration":1,"reviewed_sha":"'"$SHA_A"'","pr":101,"mode":"shadow","scope":"full","scope_files":4,"full_files":4,"review_started_at":"2026-11-01T09:00:00Z","review_ended_at":"2026-11-01T10:00:00Z"}'
  echo '{"kind":"finding","run_id":"ra","iteration":1,"file":"q.txt","issue_category":"new","rule":"aaaaaaaaaaa0","outcome":"fixed","in_would_scope":false}'
  echo '{"kind":"round","run_id":"ra","iteration":2,"reviewed_sha":"'"$SHA_B"'","pr":101,"mode":"shadow","scope":"full","scope_files":1,"full_files":4,"would_scope":["a.txt"],"scope_fallback":null,"would_suppress":[{"file":"w.txt","issue_category":"new","rule":"aaaaaaaaaaa3"}],"suppressed_repeat":0,"repeat_of_fixed":[{"file":"a.txt","issue_category":"new","rule":"aaaaaaaaaaa4"}],"review_started_at":"2026-11-01T10:00:00Z","review_ended_at":"2026-11-01T10:30:00Z"}'
  echo '{"kind":"finding","run_id":"ra","iteration":2,"file":"a.txt","issue_category":"new","rule":"aaaaaaaaaaa4","severity":"HIGH","outcome":"fixed","in_would_scope":true}'
  echo '{"kind":"finding","run_id":"ra","iteration":2,"file":"c.txt","issue_category":"new","rule":"aaaaaaaaaaa1","severity":"LOW","outcome":"dismissed","in_would_scope":false}'
  echo '{"kind":"round","run_id":"ra","iteration":3,"reviewed_sha":"'"$SHA_M"'","pr":101,"mode":"shadow","scope":"full","scope_files":0,"full_files":4,"scope_fallback":"merge_commit","review_started_at":"2026-11-01T11:00:00Z","review_ended_at":"2026-11-01T11:20:00Z"}'
  echo '{"kind":"finding","run_id":"ra","iteration":3,"file":"c.txt","issue_category":"new","rule":"aaaaaaaaaaa5","severity":"HIGH","outcome":"remaining","in_would_scope":true}'
  echo '{"kind":"round","run_id":"rz","iteration":2,"reviewed_sha":"'"$SHA_B"'","pr":101,"mode":"files","scope":"files","scope_files":1,"full_files":4,"review_started_at":"2026-11-01T12:00:00Z","review_ended_at":"2026-11-01T13:00:00Z"}'
  echo '{"kind":"finding","run_id":"rz","iteration":2,"file":"k.txt","issue_category":"new","rule":"aaaaaaaaaaa9","outcome":"fixed","in_would_scope":false}'
} > "$HD/item-a.jsonl"
{
  echo '{"kind":"round","run_id":"rb","iteration":2,"reviewed_sha":"ffffffffffffffffffffffffffffffffffffffff","pr":202,"mode":"shadow","scope":"full","scope_files":1,"full_files":2,"scope_fallback":null,"would_suppress":[],"repeat_of_fixed":[],"review_started_at":"2026-11-01T10:00:00Z","review_ended_at":"2026-11-01T10:10:00Z"}'
  echo 'junk line'
  echo '{"kind":"finding","run_id":"rb","iteration":2,"file":"z.txt","issue_category":"drift:doc","rule":"aaaaaaaaaaa2","severity":"MEDIUM","outcome":"dismissed","in_would_scope":false}'
} > "$HD/item-b.jsonl"

EST="(estimate: sum of review minutes x (1 - scope_files / full_files) over non-fallback rounds)"
WANT_ALL="heal-review-scope shadow report (read-only)
dir: .supervisor/heal-rounds
rounds: 3
findings_total: 4
outside_scope: 2
  - c.txt|new|aaaaaaaaaaa1 pr=101
  - z.txt|drift:doc|aaaaaaaaaaa2 pr=202
would_suppress: 1
  - w.txt|new|aaaaaaaaaaa3 pr=101
repeat_of_fixed: 1
  - a.txt|new|aaaaaaaaaaa4 pr=101
skipped_review_minutes_est: 27.5 $EST
fallbacks: merge_commit=1"
WANT_SINCE="heal-review-scope shadow report (read-only)
dir: $HD
rounds: 2
findings_total: 3
outside_scope: 1
  - c.txt|new|aaaaaaaaaaa1 pr=101
would_suppress: 1
  - w.txt|new|aaaaaaaaaaa3 pr=101
repeat_of_fixed: 1
  - a.txt|new|aaaaaaaaaaa4 pr=101
skipped_review_minutes_est: 22.5 $EST
fallbacks: merge_commit=1
unreachable: 1"

snapshot() { (cd "$REPO" && find . -print | env LC_ALL=C sort && find . -type f -exec cksum {} + | env LC_ALL=C sort); }
snap0="$(snapshot)"
got="$(cd "$REPO" && bash "$SCRIPT" --shadow-report 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$got" = "$WANT_ALL" ]; then ok "H1 report over rounds >= 2 in shadow: totals, outside-scope / would-suppress / repeat-of-fixed lines with PR, minutes estimate, fallbacks"; else no "H1 report — rc=$rc${NL}got:${NL}$got${NL}want:${NL}$WANT_ALL"; fi
snap1="$(snapshot)"
if [ -n "$snap0" ] && [ "$snap0" = "$snap1" ]; then ok "H2 --shadow-report writes nothing (tree, .git and records dir byte-identical)"; else no "H2 the report wrote something"; fi
got="$(bash "$SCRIPT" --shadow-report --since "$SHA_A" --dir "$HD" --root "$REPO" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$got" = "$WANT_SINCE" ]; then ok "H3 --since keeps descendants only and counts an unreachable sha"; else no "H3 --since — rc=$rc${NL}got:${NL}$got${NL}want:${NL}$WANT_SINCE"; fi
snap2="$(snapshot)"
if [ "$snap0" = "$snap2" ]; then ok "H4 --shadow-report --since writes nothing"; else no "H4 the --since report wrote something"; fi
got="$(bash "$SCRIPT" --shadow-report --dir "$TMP/no-such-dir" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s\n' "$got" | grep -qx 'rounds: 0' && [ ! -e "$TMP/no-such-dir" ]; then ok "H5 a missing records dir reports zero and creates nothing"; else no "H5 — rc=$rc got [$got]"; fi
got="$(bash "$SCRIPT" --shadow-report --since nosuchref --dir "$HD" --root "$REPO" 2>/dev/null)"; rc=$?
if [ "$rc" -eq 2 ] && [ -z "$got" ]; then ok "H6 an unresolvable --since is a usage error"; else no "H6 — rc=$rc got [$got]"; fi

# ------------------------------------------------------------------ X — usage
echo "X — usage"
got="$(bash "$SCRIPT" 2>/dev/null)"; rc=$?
if [ "$rc" -eq 2 ] && [ -z "$got" ]; then ok "X1 no subcommand => 2"; else no "X1 — rc=$rc"; fi
got="$(bash "$SCRIPT" bogus 2>/dev/null)"; rc=$?
if [ "$rc" -eq 2 ] && [ -z "$got" ]; then ok "X2 unknown subcommand => 2"; else no "X2 — rc=$rc"; fi

# ------------------------------------------------------------------ K — mutation control
echo "K — mutation control (scope prints 'scope: full' before computing the file list)"
M="$TMP/mutant-scope-full.sh"
sed 's/^cmd_scope() {$/cmd_scope() { echo "scope: full"; exit 0/' "$SCRIPT" > "$M"
if [ ! -s "$M" ] || cmp -s "$M" "$SCRIPT" || ! bash -n "$M" 2>/dev/null; then
  no "K0 mutant did not apply (empty, identical to the original, or not bash -n clean)"
else
  ok "K0 mutant applied (non-empty, differs, bash -n clean)"
  mout="$(run_scope_table "$M")"
  for id in S2 S3 S4 S5 S6 S7 S8; do
    if printf '%s\n' "$mout" | grep -q "^  FAIL: $id "; then ok "K-$id the scope-full mutant turns $id red"; else no "K-$id the scope-full mutant SURVIVED $id"; fi
  done
  if printf '%s\n' "$mout" | grep -q '^  ok: S1 '; then ok "K-S1 round 1 stays green under the mutant (the control is targeted)"; else no "K-S1 round 1 went red under the mutant"; fi
fi

echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
