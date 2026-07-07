#!/usr/bin/env bash
# test-curate-postmortem.sh — self-tests for the churn-ledger curation writer + the
# curation/staleness-aware reader filtering. (New file — knowledge-corpus curation; mirrors
# the test-lessons.sh / test-read-postmortem.sh convention.)
# Runs in isolated temp git repos (never touches the real .supervisor/postmortem).
# Exit 0 = all pass, 1 = any failure. bash-3.2-safe; no GNU-only flags (stale-entry fixtures
# use hard-coded old ISO strings instead of `date -d`).
#
# Covers:
#   1. dry-run (no --confirm) writes nothing, exit 1, prints the exact JSON line
#   2. --confirm appends exactly one valid JSONL line (fields round-trip; dir auto-created)
#   3. hostile --reason strings round-trip EXACTLY (quotes, backslashes, $(id), newlines
#      allowed-and-escaped for reason; newlines REJECTED for --target)
#   4. validation failures fail loud (exit 2): retract+--replacement, missing --target,
#      whitespace-only --target, missing --reason, bad action — nothing written on any of them
#   5. supersede replacement semantics (url present vs explicit null when omitted)
#   6. reader hides a retracted entry by automate_key (sibling entries stay live)
#   7. reader hides a superseded entry by pr_url
#   8. a curation record is NEVER a churn hit itself (even an adversarial one carrying
#      changed_paths)
#   9. malformed curation records (missing target_key; explicit null target_key) leave the
#      targeted entry LIVE
#  10. staleness: ts 2020 excluded by default; missing/unparseable ts fail-open (still hit);
#      CHURN_STALE_DAYS override honored; non-numeric override falls back to 180
#  11. reader still exits 0 on every path incl. malformed corpus lines
#  12. worktree guard (red-team F1): writer refuses from a linked worktree (exit 3), nothing
#      written in EITHER location (worktree or main checkout)

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CURATE="$HERE/curate-postmortem.sh"
READ="$HERE/read-postmortem.sh"
CORPUS=".supervisor/postmortem/results.jsonl"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

newrepo() { local d; d="$(mktemp -d)"; ( cd "$d" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i ); printf '%s' "$d"; }

# Portable "now" ISO stamp for FRESH fixture entries (works on BSD and GNU date alike).
NOW_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# write_data <repo-dir> <changed_path> <automate_key|""=omit> <pr_url> <class> <ts|""=omit>
# Appends one POSTMORTEM_RESULT-shaped data line to the sandbox ledger. newrepo() has no git
# remote, so the reader's repo scoping stays UNSCOPED (fail-open) in every case below.
write_data() {
  mkdir -p "$1/.supervisor/postmortem"
  jq -cn --arg p "$2" --arg ak "$3" --arg pu "$4" --arg cls "$5" --arg ts "$6" '
    {schema_version:1, repo:"o/r", pr_url:$pu, changed_paths:[$p],
     categories:[{round:1, class:$cls, self_heal_miss:false, flow_stage:"worker", evidence:"e"}],
     self_heal_misses:0, flow_stages:{worker:1}, summary:"s"}
    + (if $ak != "" then {automate_key:$ak} else {} end)
    + (if $ts != "" then {ts:$ts} else {} end)
  ' >> "$1/$CORPUS"
}

echo "== 1. dry-run (no --confirm): writes nothing, exit 1, prints the JSON line =="
TMP="$(newrepo)"
out="$( cd "$TMP" && bash "$CURATE" retract --target K1 --reason "bad data" 2>"$TMP/err.txt" )"; rc=$?
[ "$rc" -eq 1 ] && ok "dry-run exits 1" || no "dry-run exit wrong ($rc)"
[ ! -e "$TMP/$CORPUS" ] && ok "dry-run wrote nothing (ledger absent)" || no "dry-run created the ledger"
if printf '%s' "$out" | jq -e '(.schema_version == 1) and (.source == "curation")
    and (.curation_action == "retract") and (.target_key == "K1")
    and (has("replacement")) and (.replacement == null) and (.reason == "bad data")' >/dev/null 2>&1; then
  ok "dry-run stdout is the exact would-append JSON line"
else
  no "dry-run stdout not the expected JSON: [$out]"
fi
grep -q "dry-run, pass --confirm to write" "$TMP/err.txt" 2>/dev/null && ok "dry-run notice printed" || no "dry-run notice missing"
rm -rf "$TMP"

echo "== 2. --confirm appends exactly one valid line (dir auto-created) =="
TMP="$(newrepo)"
( cd "$TMP" && bash "$CURATE" retract --target K1 --reason "bad data" --confirm ) >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "--confirm exits 0" || no "--confirm exit wrong ($rc)"
[ -d "$TMP/.supervisor/postmortem" ] && ok "ledger dir auto-created" || no "ledger dir missing"
cnt="$(wc -l < "$TMP/$CORPUS" 2>/dev/null | tr -d ' ')"
[ "$cnt" = "1" ] && ok "exactly one line appended" || no "line count wrong ($cnt)"
if jq -e '(.schema_version == 1) and (.source == "curation") and (.curation_action == "retract")
    and (.target_key == "K1") and (.replacement == null) and (.reason == "bad data")
    and ((.ts | type) == "string") and (.ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$"))' \
    "$TMP/$CORPUS" >/dev/null 2>&1; then
  ok "appended record round-trips with correct fields + ISO ts"
else
  no "appended record fields wrong: [$(cat "$TMP/$CORPUS")]"
fi
# Append-only: a second confirm ADDS a line (never rewrites the first).
( cd "$TMP" && bash "$CURATE" retract --target K2 --reason "also bad" --confirm ) >/dev/null 2>&1
cnt2="$(wc -l < "$TMP/$CORPUS" | tr -d ' ')"
first_target="$(head -n 1 "$TMP/$CORPUS" | jq -r '.target_key' 2>/dev/null)"
if [ "$cnt2" = "2" ] && [ "$first_target" = "K1" ]; then
  ok "append-only: second write added a line, first line untouched"
else
  no "append-only violated (cnt=$cnt2 first_target=$first_target)"
fi
rm -rf "$TMP"

echo "== 3. hostile --reason round-trips exactly; newline --target rejected =="
TMP="$(newrepo)"
hostile='he said "hi" \back\slash $(id) `id` $HOME'
( cd "$TMP" && bash "$CURATE" retract --target KH --reason "$hostile" --confirm ) >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "hostile-reason write accepted (exit 0)" || no "hostile-reason write failed ($rc)"
got="$(tail -n 1 "$TMP/$CORPUS" | jq -r '.reason' 2>/dev/null)"
[ "$got" = "$hostile" ] && ok "quotes/backslashes/\$(id) round-trip EXACTLY (jq-only boundary)" || no "hostile reason corrupted: [$got]"
# A reason with an embedded REAL newline is allowed — escaped by jq to \n, ONE ledger line.
ml=$'line one\nline two'
before="$(wc -l < "$TMP/$CORPUS" | tr -d ' ')"
( cd "$TMP" && bash "$CURATE" retract --target KM --reason "$ml" --confirm ) >/dev/null 2>&1
after="$(wc -l < "$TMP/$CORPUS" | tr -d ' ')"
[ "$((after - before))" -eq 1 ] && ok "newline reason escaped onto ONE JSONL line" || no "newline reason split lines ($before -> $after)"
gotml="$(tail -n 1 "$TMP/$CORPUS" | jq -r '.reason' 2>/dev/null)"
[ "$gotml" = "$ml" ] && ok "newline reason round-trips exactly" || no "newline reason corrupted: [$gotml]"
# A --target with an embedded newline is REJECTED (exit 2, nothing appended).
nlkey=$'K\nEVIL'
before="$(wc -l < "$TMP/$CORPUS" | tr -d ' ')"
( cd "$TMP" && bash "$CURATE" retract --target "$nlkey" --reason r --confirm ) >/dev/null 2>&1; rc=$?
after="$(wc -l < "$TMP/$CORPUS" | tr -d ' ')"
[ "$rc" -eq 2 ] && ok "newline --target rejected (exit 2)" || no "newline --target not rejected ($rc)"
[ "$before" = "$after" ] && ok "newline --target wrote nothing" || no "newline --target leaked a write"
rm -rf "$TMP"

echo "== 4. validation failures fail loud (exit 2, nothing written) =="
TMP="$(newrepo)"
( cd "$TMP" && bash "$CURATE" retract --target K --reason r --replacement "u" --confirm ) >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "retract with --replacement rejected (exit 2)" || no "retract+replacement not rejected ($rc)"
( cd "$TMP" && bash "$CURATE" retract --reason r --confirm ) >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "missing --target rejected (exit 2)" || no "missing --target not rejected ($rc)"
ws=$'  \t '
( cd "$TMP" && bash "$CURATE" retract --target "$ws" --reason r --confirm ) >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "whitespace-only --target rejected (exit 2)" || no "whitespace-only --target not rejected ($rc)"
( cd "$TMP" && bash "$CURATE" retract --target K --confirm ) >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "missing --reason rejected (exit 2)" || no "missing --reason not rejected ($rc)"
( cd "$TMP" && bash "$CURATE" nuke --target K --reason r --confirm ) >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "bad action rejected (exit 2)" || no "bad action not rejected ($rc)"
( cd "$TMP" && bash "$CURATE" --target K --reason r --confirm ) >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "missing action rejected (exit 2)" || no "missing action not rejected ($rc)"
[ ! -e "$TMP/$CORPUS" ] && ok "no rejected invocation wrote anything" || no "a rejected invocation wrote the ledger"
rm -rf "$TMP"

echo "== 5. supersede replacement semantics =="
TMP="$(newrepo)"
( cd "$TMP" && bash "$CURATE" supersede --target uOLD --replacement "https://x/pr/9" --reason "replaced" --confirm ) >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "supersede with --replacement accepted" || no "supersede+replacement failed ($rc)"
if tail -n 1 "$TMP/$CORPUS" | jq -e '(.curation_action == "supersede") and (.replacement == "https://x/pr/9")' >/dev/null 2>&1; then
  ok "replacement pr_url recorded"
else
  no "replacement pr_url wrong"
fi
( cd "$TMP" && bash "$CURATE" supersede --target uOLD2 --reason "no repl" --confirm ) >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "supersede without --replacement accepted" || no "supersede sans replacement failed ($rc)"
if tail -n 1 "$TMP/$CORPUS" | jq -e '(has("replacement")) and (.replacement == null)' >/dev/null 2>&1; then
  ok "omitted replacement recorded as explicit null (key present)"
else
  no "omitted replacement not explicit null"
fi
rm -rf "$TMP"

echo "== 6. reader hides a retracted entry by automate_key =="
TMP="$(newrepo)"
write_data "$TMP" "src/a.ts" "KA" "uA" "alpha" "$NOW_TS"
write_data "$TMP" "src/b.ts" "KB" "uB" "beta"  "$NOW_TS"
out="$( cd "$TMP" && bash "$READ" "src/a.ts" 2>/dev/null )"
echo "$out" | grep -q "src/a.ts" && ok "sanity: entry LIVE before curation" || no "sanity pre-curation hit missing"
( cd "$TMP" && bash "$CURATE" retract --target KA --reason "noise" --confirm ) >/dev/null 2>&1
out="$( cd "$TMP" && bash "$READ" "src/a.ts" 2>/dev/null )"; rc=$?
[ "$rc" -eq 0 ] && ok "reader exit 0 after retract" || no "reader non-zero after retract ($rc)"
[ -z "$out" ] && ok "retracted entry (by automate_key) hidden → EMPTY output" || no "retracted entry still hits: [$out]"
out2="$( cd "$TMP" && bash "$READ" "src/b.ts" 2>/dev/null )"
echo "$out2" | grep -q "beta" && ok "sibling entry stays LIVE (retract is targeted)" || no "sibling entry wrongly hidden"
rm -rf "$TMP"

echo "== 7. reader hides a superseded entry by pr_url =="
TMP="$(newrepo)"
write_data "$TMP" "src/b.ts" "KB" "uB" "beta" "$NOW_TS"
( cd "$TMP" && bash "$CURATE" supersede --target uB --replacement "https://x/pr/9" --reason "superseded" --confirm ) >/dev/null 2>&1
out="$( cd "$TMP" && bash "$READ" "src/b.ts" 2>/dev/null )"; rc=$?
[ "$rc" -eq 0 ] && ok "reader exit 0 after supersede" || no "reader non-zero after supersede ($rc)"
[ -z "$out" ] && ok "superseded entry (by pr_url) hidden → EMPTY output" || no "superseded entry still hits: [$out]"
rm -rf "$TMP"

echo "== 8. a curation record is NEVER a churn hit itself =="
TMP="$(newrepo)"
mkdir -p "$TMP/.supervisor/postmortem"
# Adversarial curation line that ALSO carries changed_paths + categories — must still never hit.
jq -cn --arg ts "$NOW_TS" '{schema_version:1, source:"curation", curation_action:"retract",
  target_key:"ZZZ", replacement:null, reason:"r", ts:$ts,
  changed_paths:["src/cur.ts"],
  categories:[{round:1, class:"leak", self_heal_miss:false, flow_stage:"worker", evidence:"x"}]}' \
  >> "$TMP/$CORPUS"
out="$( cd "$TMP" && bash "$READ" "src/cur.ts" 2>/dev/null )"; rc=$?
[ "$rc" -eq 0 ] && ok "reader exit 0 on curation-only corpus" || no "reader non-zero on curation-only corpus ($rc)"
[ -z "$out" ] && ok "curation record excluded from hits (even with changed_paths)" || no "curation record leaked a hit: [$out]"
rm -rf "$TMP"

echo "== 9. malformed curation records leave the targeted entry LIVE =="
TMP="$(newrepo)"
write_data "$TMP" "src/m.ts" "KM" "uM" "gamma" "$NOW_TS"
# (a) curation line with target_key MISSING entirely.
jq -cn --arg ts "$NOW_TS" '{schema_version:1, source:"curation", curation_action:"retract",
  replacement:null, reason:"missing key", ts:$ts}' >> "$TMP/$CORPUS"
out="$( cd "$TMP" && bash "$READ" "src/m.ts" 2>/dev/null )"; rc=$?
[ "$rc" -eq 0 ] && ok "reader exit 0 with missing-target_key curation line" || no "reader non-zero missing-key ($rc)"
echo "$out" | grep -q "gamma" && ok "missing target_key ⇒ entry stays LIVE" || no "missing target_key wrongly hid the entry"
# (b) curation line with EXPLICIT null target_key (presence discipline: has() alone is not enough).
jq -cn --arg ts "$NOW_TS" '{schema_version:1, source:"curation", curation_action:"retract",
  target_key:null, replacement:null, reason:"null key", ts:$ts}' >> "$TMP/$CORPUS"
out="$( cd "$TMP" && bash "$READ" "src/m.ts" 2>/dev/null )"; rc=$?
[ "$rc" -eq 0 ] && ok "reader exit 0 with null-target_key curation line" || no "reader non-zero null-key ($rc)"
echo "$out" | grep -q "gamma" && ok "explicit null target_key ⇒ entry stays LIVE" || no "null target_key wrongly hid the entry"
rm -rf "$TMP"

echo "== 10. staleness: old excluded, missing/unparseable ts fail-open, override honored =="
TMP="$(newrepo)"
write_data "$TMP" "src/old.ts"   "KO" "uO" "old-class"   "2020-01-01T00:00:00Z"
write_data "$TMP" "src/nots.ts"  "KN" "uN" "nots-class"  ""
write_data "$TMP" "src/bad.ts"   "KX" "uX" "bad-class"   "not-a-date"
write_data "$TMP" "src/fresh.ts" "KF" "uF" "fresh-class" "$NOW_TS"
out="$( cd "$TMP" && bash "$READ" "src/old.ts" 2>/dev/null )"; rc=$?
[ "$rc" -eq 0 ] && ok "reader exit 0 on stale query" || no "reader non-zero stale query ($rc)"
[ -z "$out" ] && ok "ts 2020 excluded at default 180-day horizon" || no "stale entry still hits: [$out]"
out="$( cd "$TMP" && bash "$READ" "src/nots.ts" 2>/dev/null )"
echo "$out" | grep -q "nots-class" && ok "missing ts ⇒ FRESH (fail-open, still counted)" || no "missing-ts entry wrongly excluded"
out="$( cd "$TMP" && bash "$READ" "src/bad.ts" 2>/dev/null )"
echo "$out" | grep -q "bad-class" && ok "unparseable ts ⇒ FRESH (fail-open, still counted)" || no "unparseable-ts entry wrongly excluded"
out="$( cd "$TMP" && bash "$READ" "src/fresh.ts" 2>/dev/null )"
echo "$out" | grep -q "fresh-class" && ok "fresh entry still hits at default horizon" || no "fresh entry lost"
# Override: a huge horizon makes the 2020 entry fresh again.
out="$( cd "$TMP" && CHURN_STALE_DAYS=100000 bash "$READ" "src/old.ts" 2>/dev/null )"; rc=$?
[ "$rc" -eq 0 ] && ok "reader exit 0 with CHURN_STALE_DAYS override" || no "reader non-zero with override ($rc)"
echo "$out" | grep -q "old-class" && ok "CHURN_STALE_DAYS=100000 makes the 2020 entry fresh again" || no "override not honored"
# Non-numeric override falls back to 180 (validated in shell, never crosses into jq).
out="$( cd "$TMP" && CHURN_STALE_DAYS=abc bash "$READ" "src/old.ts" 2>/dev/null )"; rc=$?
[ "$rc" -eq 0 ] && ok "reader exit 0 with non-numeric CHURN_STALE_DAYS" || no "reader non-zero non-numeric override ($rc)"
[ -z "$out" ] && ok "non-numeric override fell back to 180 (2020 entry excluded)" || no "non-numeric override leaked: [$out]"
out="$( cd "$TMP" && CHURN_STALE_DAYS=abc bash "$READ" "src/fresh.ts" 2>/dev/null )"
echo "$out" | grep -q "fresh-class" && ok "non-numeric override: fresh entry still hits" || no "non-numeric override lost the fresh hit"
rm -rf "$TMP"

echo "== 11. reader still exits 0 on every path incl. malformed corpus lines =="
TMP="$(newrepo)"
write_data "$TMP" "src/a.ts" "KA" "uA" "alpha" "$NOW_TS"
( cd "$TMP" && bash "$CURATE" retract --target KZ --reason "unrelated" --confirm ) >/dev/null 2>&1
printf '%s\n' 'this is { not json at all' >> "$TMP/$CORPUS"
printf '%s\n' '' >> "$TMP/$CORPUS"
out="$( cd "$TMP" && bash "$READ" "src/a.ts" 2>/dev/null )"; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0 despite malformed/blank lines + curation records" || no "non-zero with malformed lines ($rc)"
echo "$out" | grep -q "alpha" && ok "valid data line still hits past malformed + curation lines" || no "valid hit lost"
out="$( cd "$TMP" && bash "$READ" "src/never/touched.ts" 2>/dev/null )"; rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "no-overlap stays EMPTY + exit 0 with curation records present" || no "no-overlap contract broken (rc=$rc out=[$out])"
rm -rf "$TMP"

echo "== 12. worktree guard (red-team F1): refuses from a linked worktree, exit 3 =="
TMP="$(newrepo)"
git -C "$TMP" worktree add -q "$TMP-wt" -b wt >/dev/null 2>&1
( cd "$TMP-wt" && bash "$CURATE" retract --target K1 --reason "should be refused" --confirm ) >/dev/null 2>&1; rc=$?
[ "$rc" -eq 3 ] && ok "curator refuses from a worktree (exit 3)" || no "curator did NOT refuse worktree (exit $rc)"
[ ! -e "$TMP-wt/$CORPUS" ] && ok "no ledger written under the worktree" || no "ledger leaked into the worktree"
[ ! -e "$TMP/$CORPUS" ] && ok "no ledger written in the main checkout either" || no "ledger leaked into the main checkout"
git -C "$TMP" worktree remove --force "$TMP-wt" >/dev/null 2>&1
rm -rf "$TMP" "$TMP-wt"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
