#!/usr/bin/env bash
# test-postmortem-approach-baseline.sh — self-tests for the read-only approach_challenged baseline
# script (postmortem-approach-baseline.sh) and the `approach_challenged` / `approach_challenges`
# contract surfaces of /pr-postmortem.
#
# Every case runs in a `mktemp -d` fixture dir with its own results.jsonl; no network; `gh` is a
# PATH stub — a logging stub that serves the gather's read calls, or (for --no-gh) a stub that
# records a marker if it is ever called. Exit 0 = all pass, 1 = any failure.
#
# Covers:
#   1. Step 5's own jq program, extracted from the SKILL and executed: approach_challenges: 1,
#      schema_version: 1, per-round approach_challenged booleans.
#   2. phrase match on `evidence` (rows 1 and 3 true, 2 and 4 false; exact summary line).
#   3. a recorded flag wins over the guess (`recorded:false`, counted apart from guessed rounds).
#   4. gather OR via the stubbed `gh` (row true, `1 gathered`), plus a non-matching control.
#   5. never writes: ledger byte-identical (cmp), no file created under the fixture dir, gh call log
#      read-only; under --no-gh the fail-stub is never called.
#   6. fail-safe: absent ledger, malformed line, curation exclusion, jq absent, and the curation
#      parity case against read-postmortem.sh.
#   7. no injection through evidence text ($(…), backticks, tab → space).
#   8. mutants: phrase array emptied → 0 of 4; summary appended to the ledger → cmp fails.
#   9. prompt surfaces: the SKILL H3 / Step 4 token / Step 5 counter / trend-table row, the command,
#      the schema docs, and the 6-class table byte-identical to the base commit's.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
export LC_ALL=C
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/postmortem-approach-baseline.sh"
READ="$HERE/read-postmortem.sh"
SKILL="$HERE/../skills/pr-postmortem/SKILL.md"
CMD="$HERE/../commands/pr-postmortem.md"
SCHEMA="$HERE/../docs/result-schemas/postmortem-result.md"
VERS="$HERE/../docs/result-schemas/schema-versioning.md"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed — every case needs it"; exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" 2>/dev/null' EXIT

# --- gh stubs (never inside a fixture dir) ---------------------------------------------------
# Fail stub: placed first on PATH for --no-gh runs; any call leaves a marker and exits 1.
BIN_FAIL="$TMP/bin-fail"; mkdir -p "$BIN_FAIL"
GH_CALLED="$TMP/gh-called"
cat > "$BIN_FAIL/gh" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$GH_CALLED"
exit 1
STUB
chmod +x "$BIN_FAIL/gh"

# Logging stub: serves the gather's three read paths from fixture files and logs every call.
BIN_STUB="$TMP/bin-stub"; mkdir -p "$BIN_STUB"
GH_LOG="$TMP/gh-calls.log"
PRVIEW_MATCH="$TMP/prview-match.json"
PRVIEW_PLAIN="$TMP/prview-plain.json"
cat > "$PRVIEW_MATCH" <<'FIX'
{"number": 42, "title": "Add a job queue", "body": "Adds a queue.", "additions": 10, "deletions": 1, "changedFiles": 1,
 "commits": [{"messageHeadline": "feat: add job queue", "committedDate": "2026-01-01T08:00:00Z"},
             {"messageHeadline": "fix: address review feedback", "committedDate": "2026-01-02T08:00:00Z"}],
 "reviews": [{"author": {"login": "alice"}, "body": "This is simpler to use the platform's queue than a hand-rolled one", "state": "CHANGES_REQUESTED", "submittedAt": "2026-01-01T10:00:00Z"}],
 "statusCheckRollup": [], "url": "https://github.com/acme/widgets/pull/42", "headRefName": "feature/q", "files": [{"path": "src/q.ts"}]}
FIX
cat > "$PRVIEW_PLAIN" <<'FIX'
{"number": 43, "title": "Fix guard", "body": "Fixes a guard.", "additions": 3, "deletions": 1, "changedFiles": 1,
 "commits": [{"messageHeadline": "fix: guard", "committedDate": "2026-01-01T08:00:00Z"}],
 "reviews": [{"author": {"login": "bob"}, "body": "the null check is inverted", "state": "CHANGES_REQUESTED", "submittedAt": "2026-01-01T10:00:00Z"}],
 "statusCheckRollup": [], "url": "https://github.com/acme/widgets/pull/43", "headRefName": "fix/g", "files": [{"path": "src/g.ts"}]}
FIX
cat > "$BIN_STUB/gh" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$GH_LOG"
if [ "\${1:-}" = "pr" ] && [ "\${2:-}" = "view" ]; then
  case "\${3:-}" in
    42) cat "$PRVIEW_MATCH" ;;
    43) cat "$PRVIEW_PLAIN" ;;
    *)  exit 1 ;;
  esac
  exit 0
fi
if [ "\${1:-}" = "api" ] && [ "\${2:-}" = "user" ]; then printf '%s\n' "operator"; exit 0; fi
if [ "\${1:-}" = "api" ]; then echo "[]"; exit 0; fi
exit 1
STUB
chmod +x "$BIN_STUB/gh"

# --- helpers --------------------------------------------------------------------------------
# listing <dir> — every path under <dir> (files and dirs), sorted; used to prove nothing is created.
listing() { ( cd "$1" && find . -print | sort ); }

# run_bl <label> <bindir> <fixture_dir> <args...> — run the script with <bindir> first on PATH and
# assert the never-writes contract (ledger byte-identical when present, no new path under the
# fixture dir). Sets OUT, ERR, RC.
run_bl() {
  local label="$1" bindir="$2" fx="$3"; shift 3
  local before pristine="$TMP/pristine.$$"
  before="$(listing "$fx")"
  [ -f "$fx/results.jsonl" ] && cp "$fx/results.jsonl" "$pristine"
  OUT="$( PATH="$bindir:$PATH" bash "$SCRIPT" "$@" 2>"$TMP/err" )"; RC=$?
  ERR="$(cat "$TMP/err")"
  [ "$RC" -eq 0 ] && ok "$label: exit 0" || no "$label: exit $RC"
  if [ -f "$pristine" ]; then
    cmp -s "$pristine" "$fx/results.jsonl" && ok "$label: ledger byte-identical (cmp)" \
      || no "$label: ledger CHANGED by the script"
    rm -f "$pristine"
  fi
  [ "$before" = "$(listing "$fx")" ] && ok "$label: no file created under the fixture dir" \
    || no "$label: fixture dir listing changed"
}
rows() { printf '%s\n' "$OUT" | sed '$d'; }
last() { printf '%s\n' "$OUT" | tail -n 1; }
col() { rows | awk -F'\t' -v r="$1" -v c="$2" 'NR == r { print $c }'; }

# fx_ac4 <dir> — the four-round evidence fixture.
fx_ac4() {
  mkdir -p "$1"
  jq -cn '{schema_version:1, repo:"o/r", number:1, pr_url:"https://github.com/o/r/pull/1",
           categories:[{round:1,class:"missing_context",self_heal_miss:false,flow_stage:"launch_pad",evidence:"why not use the SDK'"'"'s retry here"},
                       {round:2,class:"execution_bug",self_heal_miss:false,flow_stage:"worker",evidence:"off-by-one in the loop"},
                       {round:3,class:"missing_context",self_heal_miss:false,flow_stage:"launch_pad",evidence:"the harness already provides a lock — reinventing it"},
                       {round:4,class:"quality_gap",self_heal_miss:false,flow_stage:"worker",evidence:"missing test for the empty case"}]}' > "$1/results.jsonl"
}

echo "== 1. Step 5's own jq program (extracted from the SKILL) carries the flag and the counter =="
PROG="$(awk '
  $0 == "        '"'"'{" { f = 1; print "{"; next }
  f && /^         }'"'"'/ { print "}"; exit }
  f { print }' "$SKILL")"
if [ -n "$PROG" ] && grep -q 'schema_version: 1' <<<"$PROG"; then
  ok "extracted the Step 5 jq object literal from the SKILL ($(printf '%s\n' "$PROG" | wc -l | tr -d ' ') lines)"
else
  no "could not extract the Step 5 jq object literal from the SKILL"
fi
GATHERED='{"repo":"o/r","number":7,"agent_generated_guess":true,"review_rounds":3,"additions":1,"deletions":1,"changed_files":1,"pr_url":"https://github.com/o/r/pull/7","branch":"b","changed_paths":["a.sh"]}'
CATS='[{"round":1,"class":"missing_context","self_heal_miss":false,"dismissed_then_raised":false,"approach_challenged":true,"flow_stage":"launch_pad","evidence":"why not use X"},{"round":2,"class":"execution_bug","self_heal_miss":false,"dismissed_then_raised":false,"approach_challenged":false,"flow_stage":"worker","evidence":"off-by-one"},{"round":3,"class":"quality_gap","self_heal_miss":true,"dismissed_then_raised":false,"approach_challenged":false,"flow_stage":"self_heal","evidence":"missing test"}]'
LINE="$(printf '%s' "$GATHERED" | jq -c \
  --arg ts "2026-11-11T00:00:00Z" \
  --argjson categories "$CATS" \
  --argjson self_heal_misses 1 \
  --argjson approach_challenges 1 \
  --argjson flow_stages '{"launch_pad":1,"worker":1,"self_heal":1,"unknowable":0}' \
  --arg summary "s" \
  --arg plugin_version "0.0.0" \
  "$PROG" 2>/dev/null)"
if printf '%s' "$LINE" | jq -e '.approach_challenges == 1 and .schema_version == 1
     and ([.categories[].approach_challenged] == [true, false, false])' >/dev/null 2>&1; then
  ok "Step 5 line carries approach_challenges: 1, schema_version: 1 and per-round booleans"
else
  no "Step 5 line wrong: [$LINE]"
fi
grep -qF -- '--argjson approach_challenges "$APPROACH_CHALLENGES"' "$SKILL" \
  && ok "Step 5 passes the counter via --argjson (injection-safe)" || no "Step 5 lacks --argjson approach_challenges"

echo "== 2. phrase match on evidence (--no-gh) =="
FX="$TMP/fx-ac4"; fx_ac4 "$FX"; rm -f "$GH_CALLED"
run_bl "ac4" "$BIN_FAIL" "$FX" --fixture "$FX" --no-gh
[ "$(rows | wc -l | tr -d ' ')" = "4" ] && ok "four rows" || no "row count wrong: [$OUT]"
[ "$(col 1 4)$(col 2 4)$(col 3 4)$(col 4 4)" = "truefalsetruefalse" ] \
  && ok "rows 1 and 3 true, rows 2 and 4 false" || no "guess column wrong: [$(col 1 4) $(col 2 4) $(col 3 4) $(col 4 4)]"
[ "$(rows | awk -F'\t' 'NF != 5' | wc -l | tr -d ' ')" = "0" ] && ok "every row has 5 TSV columns" || no "a row is not 5 columns"
[ "$(last)" = "approach_challenged: 2 of 4 categorized rounds (guess; 1 entries, 0 gathered, 1 gather-unavailable)" ] \
  && ok "exact summary line" || no "summary wrong: [$(last)]"
[ ! -e "$GH_CALLED" ] && ok "--no-gh: the fail-stub gh was never called" || no "--no-gh called gh: $(cat "$GH_CALLED")"

echo "== 3. a recorded flag wins over the guess =="
FX="$TMP/fx-rec"; mkdir -p "$FX"
jq -cn '{schema_version:1, repo:"o/r", number:2, pr_url:"https://github.com/o/r/pull/2",
         categories:[{round:1,class:"missing_context",approach_challenged:false,evidence:"why not use the queue"},
                     {round:2,class:"execution_bug",evidence:"null check"}]}' > "$FX/results.jsonl"
jq -cn '{schema_version:1, repo:"o/r", number:3, pr_url:"https://github.com/o/r/pull/3",
         categories:[{round:1,class:"plan_gap",approach_challenged:true,evidence:"spec gap"}]}' >> "$FX/results.jsonl"
run_bl "recorded" "$BIN_FAIL" "$FX" --fixture "$FX" --no-gh
[ "$(col 1 4)" = "recorded:false" ] && ok "a recorded false prints recorded:false despite a 'why not' evidence" || no "row 1: [$(col 1 4)]"
[ "$(col 2 4)" = "false" ] && ok "an unflagged round of the same entry is guessed" || no "row 2: [$(col 2 4)]"
[ "$(col 3 4)" = "recorded:true" ] && ok "a recorded true prints recorded:true" || no "row 3: [$(col 3 4)]"
[ "$(last)" = "approach_challenged: 0 of 1 categorized rounds (guess; 2 entries, 0 gathered, 1 gather-unavailable; recorded: 1 of 2 rounds)" ] \
  && ok "recorded rounds counted apart from guessed ones" || no "summary wrong: [$(last)]"

echo "== 4. gather OR through the stubbed gh =="
FX="$TMP/fx-gather"; mkdir -p "$FX"; : > "$GH_LOG"
jq -cn '{schema_version:1, repo:"acme/widgets", number:42, pr_url:"https://github.com/acme/widgets/pull/42",
         categories:[{round:1,class:"execution_bug",evidence:"null check"}]}' > "$FX/results.jsonl"
jq -cn '{schema_version:1, repo:"acme/widgets", number:43, pr_url:"https://github.com/acme/widgets/pull/43",
         categories:[{round:1,class:"execution_bug",evidence:"inverted guard"}]}' >> "$FX/results.jsonl"
# PR 44: the stub's `pr view` fails, so the gather answers unavailable for this entry.
jq -cn '{schema_version:1, repo:"acme/widgets", number:44, pr_url:"https://github.com/acme/widgets/pull/44",
         categories:[{round:1,class:"quality_gap",evidence:"missing test"}]}' >> "$FX/results.jsonl"
run_bl "gather" "$BIN_STUB" "$FX" --fixture "$FX"
[ "$(col 1 4)" = "true" ] && ok "a matching PR comment ('simpler to …') ORs the row to true" || no "row 1: [$(col 1 4)] out=[$OUT] err=[$ERR]"
[ "$(col 2 4)" = "false" ] && ok "control: a gathered PR with no matching comment stays false" || no "row 2: [$(col 2 4)]"
[ "$(col 3 4)" = "false" ] && ok "a PR the gather cannot read falls back to the evidence guess" || no "row 3: [$(col 3 4)]"
[ "$(last)" = "approach_challenged: 1 of 3 categorized rounds (guess; 3 entries, 2 gathered, 1 gather-unavailable)" ] \
  && ok "summary counts gathered and gather-unavailable entries" || no "summary wrong: [$(last)]"
if [ -s "$GH_LOG" ]; then
  ok "the gather actually called the stub ($(wc -l < "$GH_LOG" | tr -d ' ') calls)"
  bad="$(grep -vE '^(pr view [0-9]+ |api user( |$)|api repos/[^ ]+/comments)' "$GH_LOG" || true)"
  [ -z "$bad" ] && ok "gh call log holds only read calls (pr view / api …/comments / api user)" || no "unexpected gh calls: [$bad]"
  grep -qE 'pr (comment|edit|merge|close|review)|(-X|--method)[ =]?(POST|PATCH|PUT|DELETE)' "$GH_LOG" \
    && no "a mutating gh call was made" || ok "no mutating gh call (pr comment/edit, -X POST|PATCH|PUT|DELETE)"
else
  no "the stub gh was never called — the gather OR is untested"
fi

echo "== 5. fail-safe =="
# (a) absent ledger
FX="$TMP/fx-absent"; mkdir -p "$FX"
run_bl "absent" "$BIN_FAIL" "$FX" --fixture "$FX" --no-gh
[ "$OUT" = "approach_challenged: 0 of 0 categorized rounds (ledger unreadable: absent)" ] \
  && ok "absent ledger: no rows, the unreadable summary" || no "absent ledger output: [$OUT]"
[ -n "$ERR" ] && ok "absent ledger: reason on stderr" || no "absent ledger: stderr empty"
# (b) malformed line among valid ones
FX="$TMP/fx-malformed"; mkdir -p "$FX"
{ jq -cn '{pr_url:"https://github.com/o/r/pull/5", categories:[{round:1,class:"a",evidence:"why not X"}]}'
  printf '%s\n' 'this is { not json'
  printf '%s\n' '[1,2'
  jq -cn '{pr_url:"https://github.com/o/r/pull/6", categories:[{round:1,class:"b",evidence:"typo"}, "not-an-object"]}'
} > "$FX/results.jsonl"
run_bl "malformed" "$BIN_FAIL" "$FX" --fixture "$FX" --no-gh
[ "$(rows | wc -l | tr -d ' ')" = "2" ] && ok "malformed line skipped, both valid rounds printed" || no "malformed: [$OUT]"
[ "$(last)" = "approach_challenged: 1 of 2 categorized rounds (guess; 2 entries, 0 gathered, 2 gather-unavailable)" ] \
  && ok "malformed: summary over the valid rounds only" || no "malformed summary: [$(last)]"
# (c) curation retract excludes the entry; the curation record prints no row
FX="$TMP/fx-cur"; mkdir -p "$FX"
{ jq -cn '{pr_url:"https://github.com/o/r/pull/7", categories:[{round:1,class:"retracted_cls",evidence:"why not X"}]}'
  jq -cn '{pr_url:"https://github.com/o/r/pull/8", categories:[{round:1,class:"live_cls",evidence:"typo"}]}'
  jq -cn '{schema_version:1, source:"curation", curation_action:"retract", target_key:"https://github.com/o/r/pull/7", replacement:null, reason:"wrong", ts:"2026-11-11T00:00:00Z"}'
} > "$FX/results.jsonl"
run_bl "curation" "$BIN_FAIL" "$FX" --fixture "$FX" --no-gh
[ "$(rows | awk -F'\t' '{print $3}' | tr '\n' ' ')" = "live_cls " ] \
  && ok "retracted entry excluded; the curation record prints no row" || no "curation rows: [$OUT]"
# (d) jq absent: empty stdout, exit 0, reason on stderr
MASK="$TMP/mask"; mkdir -p "$MASK"
for t in bash sh git dirname cat sed; do
  p="$(command -v "$t" 2>/dev/null || true)"; [ -n "$p" ] && ln -sf "$p" "$MASK/$t"
done
FX="$TMP/fx-ac4-nojq"; fx_ac4 "$FX"
out="$( PATH="$MASK" bash "$SCRIPT" --fixture "$FX" --no-gh 2>"$TMP/err" )"; rc=$?
[ "$rc" -eq 0 ] && ok "jq absent: exit 0" || no "jq absent: exit $rc"
[ -z "$out" ] && ok "jq absent: stdout empty" || no "jq absent: stdout [$out]"
[ -s "$TMP/err" ] && ok "jq absent: reason on stderr" || no "jq absent: stderr empty"
# (e) curation parity with read-postmortem.sh over ONE ledger (unscoped repo, no ts, shared path).
PREPO="$TMP/parity-repo"; mkdir -p "$PREPO/.supervisor/postmortem"
( cd "$PREPO" && git init -q && git config user.email t@t && git config user.name t && echo i > f && git add f && git commit -qm i )
PL="$PREPO/.supervisor/postmortem/results.jsonl"
{
  jq -cn '{schema_version:1, repo:"o/r", number:21, pr_url:"https://github.com/o/r/pull/21", changed_paths:["src/shared.ts"], categories:[{round:1,class:"cls_by_url",flow_stage:"worker",evidence:"e1"}]}'
  jq -cn '{schema_version:1, repo:"o/r", number:22, pr_url:"https://github.com/o/r/pull/22", automate_key:"key-22", source:"automate_drain", changed_paths:["src/shared.ts"], categories:[{round:1,class:"cls_by_key",flow_stage:"self_heal",evidence:"e2"}]}'
  jq -cn '{schema_version:1, repo:"o/r", number:23, pr_url:"https://github.com/o/r/pull/23", changed_paths:["src/shared.ts"], categories:[{round:1,class:"cls_missing_tk",flow_stage:"worker",evidence:"e3"}]}'
  jq -cn '{schema_version:1, repo:"o/r", number:24, pr_url:"https://github.com/o/r/pull/24", changed_paths:["src/shared.ts"], categories:[{round:1,class:"cls_empty_tk",flow_stage:"worker",evidence:"e4"}]}'
  jq -cn '{schema_version:1, repo:"o/r", number:25, pr_url:"https://github.com/o/r/pull/25", changed_paths:["src/shared.ts"], categories:[{round:1,class:"cls_nonstring_tk",flow_stage:"worker",evidence:"e5"}]}'
  jq -cn '{schema_version:1, repo:"o/r", number:26, pr_url:"https://github.com/o/r/pull/26", changed_paths:["src/shared.ts"], categories:[{round:1,class:"cls_untouched",flow_stage:"worker",evidence:"e6"}]}'
  jq -cn '{schema_version:1, source:"curation", curation_action:"retract", target_key:"https://github.com/o/r/pull/21", replacement:null, reason:"r"}'
  jq -cn '{schema_version:1, source:"curation", curation_action:"retract", target_key:"key-22", replacement:null, reason:"r"}'
  jq -cn '{schema_version:1, source:"curation", curation_action:"retract", replacement:null, reason:"meant https://github.com/o/r/pull/23"}'
  jq -cn '{schema_version:1, source:"curation", curation_action:"retract", target_key:"", replacement:null, reason:"meant 24"}'
  jq -cn '{schema_version:1, source:"curation", curation_action:"retract", target_key:25, replacement:null, reason:"meant 25"}'
} > "$PL"
reader_out="$( cd "$PREPO" && bash "$READ" "src/shared.ts" 2>/dev/null )"
reader_set="$(printf '%s\n' "$reader_out" | sed -n 's/^- recurring root-cause classes: //p' | tr ',' '\n' \
  | sed -E 's/^ +//; s/ \([0-9]+\)$//' | sort | tr '\n' ' ')"
run_bl "parity" "$BIN_FAIL" "$PREPO/.supervisor/postmortem" --ledger "$PL" --no-gh
base_set="$(rows | awk -F'\t' '{print $3}' | sort | tr '\n' ' ')"
expect="cls_empty_tk cls_missing_tk cls_nonstring_tk cls_untouched "
[ "$reader_set" = "$expect" ] && ok "reader excludes exactly the two well-formed targets" || no "reader set: [$reader_set] out=[$reader_out]"
[ "$base_set" = "$reader_set" ] && ok "baseline and reader exclude the same entries" || no "parity broken: baseline [$base_set] vs reader [$reader_set]"

# (f) a ledger path that is a directory → not_a_file; (g) an unknown argument → exit 0, no stdout.
FX="$TMP/fx-dir"; mkdir -p "$FX/results.jsonl"
run_bl "not-a-file" "$BIN_FAIL" "$FX" --fixture "$FX" --no-gh
[ "$OUT" = "approach_challenged: 0 of 0 categorized rounds (ledger unreadable: not_a_file)" ] \
  && ok "a directory ledger path reads as not_a_file" || no "not_a_file output: [$OUT]"
out="$( PATH="$BIN_FAIL:$PATH" bash "$SCRIPT" --bogus 2>"$TMP/err" )"; rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && [ -s "$TMP/err" ] && ok "unknown argument: exit 0, empty stdout, usage on stderr" \
  || no "unknown argument: rc=$rc out=[$out]"

echo "== 6. no injection through evidence text =="
FX="$TMP/fx-inject"; mkdir -p "$FX"; MARK="$TMP/injected-marker"; MARK2="$TMP/injected-marker2"
EV="$(printf 'a $(touch %s) b `touch %s`\tc' "$MARK" "$MARK2")"
jq -cn --arg ev "$EV" '{pr_url:"https://github.com/o/r/pull/9", categories:[{round:1,class:"x",evidence:$ev}]}' > "$FX/results.jsonl"
run_bl "inject" "$BIN_FAIL" "$FX" --fixture "$FX" --no-gh
[ ! -e "$MARK" ] && [ ! -e "$MARK2" ] && ok "no marker file created" || no "evidence text was executed"
[ "$(rows | wc -l | tr -d ' ')" = "1" ] && ok "one TSV row for the round" || no "row count: [$OUT]"
want="$(printf 'a $(touch %s) b `touch %s` c' "$MARK" "$MARK2")"
[ "$(col 1 5)" = "$want" ] && ok "snippet holds the text verbatim with the tab replaced by a space" || no "snippet: [$(col 1 5)]"

echo "== 7. mutants =="
MUT_DIR="$TMP/mutants"; mkdir -p "$MUT_DIR"
# (a) phrase array emptied → the AC 4 case prints 0 of 4.
sed "s/^APPROACH_PHRASES_JSON=.*/APPROACH_PHRASES_JSON='[]'/" "$SCRIPT" > "$MUT_DIR/a.sh"
if ! cmp -s "$SCRIPT" "$MUT_DIR/a.sh"; then
  FX="$TMP/fx-mut-a"; fx_ac4 "$FX"
  m_out="$( PATH="$BIN_FAIL:$PATH" bash "$MUT_DIR/a.sh" --fixture "$FX" --no-gh 2>/dev/null | tail -n 1 )"
  case "$m_out" in
    "approach_challenged: 0 of 4 "*) ok "mutant (a) empty phrase array → 0 of 4" ;;
    *) no "mutant (a) not caught: [$m_out]" ;;
  esac
else
  no "mutant (a) identical to the original — the mutation did not apply"
fi
# (b) a copy that appends the summary line to the ledger → the byte-identical check fails.
awk '{ lines[NR] = $0 } END { for (i = 1; i <= NR; i++) {
       if (i == NR && lines[i] == "exit 0") print "printf '"'"'%s\\n'"'"' \"$(printf '"'"'%s\\n'"'"' \"$OUT\" | tail -n 1)\" >> \"$LEDGER\"";
       print lines[i] } }' "$SCRIPT" > "$MUT_DIR/b.sh"
if ! cmp -s "$SCRIPT" "$MUT_DIR/b.sh"; then
  FX="$TMP/fx-mut-b"; fx_ac4 "$FX"; cp "$FX/results.jsonl" "$TMP/mut-b-pristine"
  PATH="$BIN_FAIL:$PATH" bash "$MUT_DIR/b.sh" --fixture "$FX" --no-gh >/dev/null 2>&1
  cmp -s "$TMP/mut-b-pristine" "$FX/results.jsonl" \
    && no "mutant (b) (writes the summary to the ledger) passed the byte-identical check" \
    || ok "mutant (b) writing the ledger fails the byte-identical check"
else
  no "mutant (b) identical to the original — the mutation did not apply"
fi

echo "== 8. prompt surfaces =="
H3='### Optional `approach_challenged` flag (boolean, per round)'
grep -qxF -- "$H3" "$SKILL" && ok "SKILL carries the H3" || no "SKILL H3 missing"
first="$(awk -v h="$H3" '$0 == h { f = 1; next } f && NF { print; exit }' "$SKILL")"
case "$first" in
  '**Not a 7th root-cause class.**'*) ok "the H3 section opens with 'Not a 7th root-cause class.'" ;;
  *) no "H3 section opens with: [$first]" ;;
esac
grep -qF 'approach_challenged=<bool>' "$SKILL" && ok "Step 4 per-round token approach_challenged=" || no "Step 4 token missing"
grep -qF -- '- `APPROACH_CHALLENGES` — integer count' "$SKILL" && ok "Step 5 builder list names APPROACH_CHALLENGES" || no "builder list entry missing"
grep -qE '^\| `approach_challenges` \| int \|' "$SKILL" && ok "trend-line schema table carries approach_challenges" || no "trend-table row missing"
grep -qF '[{round, class, self_heal_miss, dismissed_then_raised, approach_challenged, flow_stage, evidence}]' "$SKILL" \
  && ok "CATEGORIES_JSON shape names approach_challenged" || no "CATEGORIES_JSON shape lacks the field"
grep -qF 'approach_challenged' "$CMD" && ok "commands/pr-postmortem.md names approach_challenged" || no "command does not name the flag"
grep -qF -- '- `approach_challenges` — integer' "$SCHEMA" && ok "postmortem-result.md documents approach_challenges" || no "schema doc lacks approach_challenges bullet"
grep -qF 'approach_challenged' "$SCHEMA" && ok "postmortem-result.md documents approach_challenged" || no "schema doc lacks approach_challenged"
grep -qxF -- '- `schema_version` — integer, required, always `1`.' "$SCHEMA" && ok "schema_version still always 1" || no "schema_version line changed"
grep -qF -- '**POSTMORTEM_RESULT additive `approach_challenged` + `approach_challenges`**' "$VERS" \
  && ok "schema-versioning.md carries the additive entry" || no "schema-versioning entry missing"
# The 6-class table: byte-identical to the base commit's block (captured at test-authoring time).
EXPECTED_TABLE="$TMP/class-table.expected"
cat > "$EXPECTED_TABLE" <<'CLASS_TABLE'
## The 6 Root-Cause Classes

Each categorized review round is assigned **exactly ONE** class (a round with no concrete evidence is not categorized at all — Step 3 omits it). Definitions are crisp so categorization is reproducible across runs:

| Class | Definition (assign when the round's evidence shows…) |
|---|---|
| `plan_gap` | The brief/plan itself was incomplete or wrong — a requirement, acceptance criterion, or edge case was never specified, so the implementation faithfully built the wrong/partial thing. The reviewer is pointing at *missing intent*, not a coding mistake. |
| `missing_context` | The implementation was reasonable given what the worker saw, but it lacked context that existed elsewhere in the codebase (an existing helper, a sibling module's pattern, a prior decision). Reviewer says "we already have X" / "this duplicates Y" / "see existing Z". |
| `convention_mismatch` | The code works but violates a project convention, style, naming, structure, or doc-currency rule (e.g. count claims, lint, formatting, import order, frontmatter keys). Reviewer is enforcing *how we do things here*, not correctness. |
| `execution_bug` | A genuine defect in the produced code — wrong logic, off-by-one, null/falsy coercion, a broken branch, an unhandled case, a typo that changes behavior. The intent and context were fine; the code is wrong. |
| `quality_gap` | Non-defect quality shortfalls: missing tests, missing error handling, weak validation parity, missing branch coverage, inadequate logging — the code is correct but under-hardened. (Distinct from `execution_bug`: nothing is *wrong*, something is *missing*.) |
| `scope_too_large` | The PR tried to do too much at once, making review hard and churn likely — the reviewer asks to split, descope, or the round exists mostly because the diff was sprawling. Size/`changed_files`/`additions` are the dominant signal. |

CLASS_TABLE
awk '/^## The 6 Root-Cause Classes$/ { f = 1 } f && /^### / { exit } f { print }' "$SKILL" > "$TMP/class-table.got"
cmp -s "$EXPECTED_TABLE" "$TMP/class-table.got" && ok "the 6-class table is byte-identical to the base commit's" \
  || no "the 6-class table changed: $(diff "$EXPECTED_TABLE" "$TMP/class-table.got" | head -5)"
[ "$(grep -cE '^\| `[a-z_]+` \|' "$TMP/class-table.got")" = "6" ] && ok "exactly six class rows" || no "class row count changed"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
