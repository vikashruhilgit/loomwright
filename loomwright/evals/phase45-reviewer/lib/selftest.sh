#!/usr/bin/env bash
# selftest.sh — the phase45-reviewer eval suite checked WITHOUT a model and without the network.
#
#   bash selftest.sh                      one tally `PASS: <n> FAIL: <m>`, exit 1 on any failure
#   PHASE45_GRADE=<grader> bash selftest.sh   the same checks through another grader (the always-CAUGHT
#                                         mutant leg: its `mutation-control` check must then print a line
#                                         starting `FAIL: mutation-control`)
#
# Hermetic: every fixture lives in a `mktemp -d` dir — a scratch SOURCE repo laid out like this one (the
# suite's lib/ and the live self-heal-advisory SKILL.md copied in, a committed fixture corpus table), its case
# dirs staged by their own scaffold.sh into scratch sandboxes, canned reviewer replies, a fixture eval JSON and
# kept-sandbox dirs. The expected-file value is a per-run token, so no file under the plugin root can carry it.
#   G   the grader (through PHASE45_GRADE): hit ⇒ CAUGHT; plain miss and empty-issues miss ⇒ MISSED; wrong
#       file ⇒ MISSED; below the floor ⇒ MISSED; the LAST block wins; unparseable ⇒ MISSED (unparseable);
#       no reply file ⇒ MISSED (no reply); a control with one HIGH (and one MEDIUM) ⇒ NOISE, NOISE: 1; the
#       mutation control — a deliberately wrong EXPECTED_FILE against the hit reply — is never CAUGHT
#   P   lib/render-prompt.sh over the live skills/self-heal-advisory/SKILL.md: EXECUTION DIRECTIVE and
#       CODE_REVIEW_RESULT v3 present, no `{`, no PIN-MUTATION VERDICTS; a broken anchor and a stray
#       placeholder each fail closed
#   Y   every case.yaml (case-template.yaml and each [0-9]*/case.yaml) is byte-identical from `execution:` on;
#       no case dir carries an expectation (case.env keys, the committed corpus table's expected files)
#   S   lib/stage-case.sh: a staged case's scratch repo diff is exactly the pre-drain diff; the sandbox holds
#       no expectation (`.eval/` is exactly case-id/base_sha/head_sha/review-prompt.md, no corpus table, no
#       suite dir, no expected-file token); the source repo is untouched; a nonexistent sha ⇒ `.eval/unstageable`
#   M   lib/summarize.sh over the fixture corpus + kept sandboxes ⇒ caught: 1/4, unstageable: 1, no_reply: 1,
#       noise: 1 BLOCKING/HIGH on 1 controls, and a `?` row for the case with no kept sandbox
#   R   lib/run.sh with a PATH stub shadowing `claude` (exit 1): non-zero, the missing-tool line on stderr, no
#       `caught:` line, and the stub's marker proves the stub was the binary invoked
# bash 3.2 + BSD userland + git + jq + python3.
set -uo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE="$(cd "$LIB/.." && pwd)"
PLUGIN="$(cd "$SUITE/../.." && pwd)"
REPO="$(cd "$PLUGIN/.." && pwd)"
PHASE45_GRADE="${PHASE45_GRADE:-$LIB/grade.sh}"
export PHASE45_GRADE
pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass + 1)); }
no() { echo "FAIL: $1"; fail=$((fail + 1)); }
WORK="$(mktemp -d)" || { echo "FAIL: mktemp -d"; exit 1; }
trap 'chmod -R u+rwx "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT
TAB="$(printf '\t')"
shopt -s nullglob

echo "== phase45-reviewer eval selftest ($SUITE; grader: $PHASE45_GRADE)"
for t in git jq python3; do command -v "$t" >/dev/null 2>&1 || no "required tool missing: $t"; done
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=selftest GIT_AUTHOR_EMAIL=selftest@example.invalid \
  GIT_COMMITTER_NAME=selftest GIT_COMMITTER_EMAIL=selftest@example.invalid
HOME="$WORK/home"; export HOME; mkdir -p "$HOME"

TOKEN="p45st-$$-$(date +%s)"            # built at run time: never a literal in any committed file
EXP="fixture/$TOKEN/expected.sh"
OTHER="fixture/$TOKEN/other.sh"

# mkreply <out> <decision> [<severity> <file>]... — a CODE_REVIEW_RESULT v3 reply with prose around it
mkreply() {
  local out="$1" dec="$2"; shift 2
  {
    echo "I reviewed the integrated diff. Findings below."
    echo
    echo "CODE_REVIEW_RESULT:"
    echo "  schema_version: 3"
    echo "  review_mode: diff_review"
    echo "  audit_focus: []"
    echo "  trigger_paths_detected: []"
    echo "  scope_expanded: []"
    echo "  files_checked: [app.txt]"
    echo "  decision: $dec"
    if [ "$#" -eq 0 ]; then echo "  issues: []"; else
      echo "  issues:"
      while [ "$#" -ge 2 ]; do
        printf '    - severity: %s\n      category: new\n      file: %s\n      line: 3\n      description: "a finding"\n      suggestion: "fix it"\n' "$1" "$2"
        shift 2
      done
    fi
    echo "  summary: \"fixture reply\""
  } > "$out"
}
# grade <reply> <case_id> <corpus> — the grader's RESULT and NOISE lines, space-joined
grade() { bash "$PHASE45_GRADE" "$1" "$2" "$3" 2>&1 | tr '\n' ' ' | sed 's/ $//'; }

# ---- G: the grader ------------------------------------------------------------------------------------------
GC="$WORK/grade-corpus.tsv"
{
  printf 'case_id\tpr\tkind\texpected_file\tseverity_floor\n'
  printf 'g-miss\t1\tmiss\t%s\tHIGH\n' "$EXP"
  printf 'g-mutation-control\t2\tmiss\tfixture/%s/not-the-expected-file.sh\tHIGH\n' "$TOKEN"
  printf 'g-control\t3\tcontrol\t\t\n'
} > "$GC"
R="$WORK/replies"; mkdir -p "$R"
mkreply "$R/hit" FAIL MEDIUM "$OTHER" HIGH "$EXP"
mkreply "$R/plain-miss" PASS LOW "$OTHER"
mkreply "$R/empty-miss" PASS
mkreply "$R/wrong-file" FAIL BLOCKING "$OTHER"
mkreply "$R/below-floor" PASS MEDIUM "$EXP"
mkreply "$R/control-high" FAIL HIGH "$OTHER" MEDIUM "$EXP"
{ mkreply "$R/x" FAIL HIGH "$EXP"; cat "$R/x"; echo; echo "Restated, final:"; echo; cat "$R/plain-miss"; } > "$R/last-wins"
printf 'The review found problems in %s but I ran out of turns before the result block.\n' "$EXP" > "$R/unparseable"

r="$(grade "$R/hit" g-miss "$GC")"
[ "$r" = "RESULT: CAUGHT" ] && ok "G hit (HIGH on the expected file, floor HIGH) ⇒ CAUGHT" || no "G hit graded '$r'"
r="$(grade "$R/plain-miss" g-miss "$GC")"
[ "$r" = "RESULT: MISSED" ] && ok "G plain miss (one LOW elsewhere) ⇒ MISSED" || no "G plain miss graded '$r'"
r="$(grade "$R/empty-miss" g-miss "$GC")"
[ "$r" = "RESULT: MISSED" ] && ok "G empty-issues miss ⇒ MISSED" || no "G empty-issues miss graded '$r'"
r="$(grade "$R/wrong-file" g-miss "$GC")"
[ "$r" = "RESULT: MISSED" ] && ok "G wrong-file finding (BLOCKING elsewhere) ⇒ MISSED" || no "G wrong-file graded '$r'"
r="$(grade "$R/below-floor" g-miss "$GC")"
[ "$r" = "RESULT: MISSED" ] && ok "G below-floor finding (MEDIUM on the expected file, floor HIGH) ⇒ MISSED" || no "G below-floor graded '$r'"
r="$(grade "$R/last-wins" g-miss "$GC")"
[ "$r" = "RESULT: MISSED" ] && ok "G the LAST CODE_REVIEW_RESULT block wins (an earlier hit block is ignored)" || no "G last-block graded '$r'"
r="$(grade "$R/unparseable" g-miss "$GC")"
[ "$r" = "RESULT: MISSED (unparseable)" ] && ok "G no parseable block ⇒ MISSED (unparseable)" || no "G unparseable graded '$r'"
printf 'CODE_REVIEW_RESULT:\n  schema_version: 3\n  review_mode: diff_review\n' > "$R/truncated"   # cut off before decision
r="$(grade "$R/truncated" g-miss "$GC")"
[ "$r" = "RESULT: MISSED (unparseable)" ] && ok "G a block cut off before its decision ⇒ MISSED (unparseable)" || no "G truncated block graded '$r'"
r="$(grade "$R/no-such-reply" g-miss "$GC")"
[ "$r" = "RESULT: MISSED (no reply)" ] && ok "G staged case with no reply file ⇒ MISSED (no reply)" || no "G no reply graded '$r'"
r="$(grade "$R/control-high" g-control "$GC")"
[ "$r" = "RESULT: NOISE NOISE: 1" ] && ok "G control with one HIGH (and one MEDIUM) ⇒ NOISE, NOISE: 1" || no "G control graded '$r'"
r="$(grade "$R/empty-miss" g-control "$GC")"
[ "$r" = "RESULT: CLEAN NOISE: 0" ] && ok "G control with no issues ⇒ CLEAN, NOISE: 0" || no "G clean control graded '$r'"
r="$(grade "$R/hit" g-mutation-control "$GC")"
case "$r" in
  "RESULT: MISSED") ok "mutation-control: a deliberately wrong EXPECTED_FILE against the hit reply ⇒ MISSED" ;;
  *) no "mutation-control: a deliberately wrong EXPECTED_FILE against the hit reply graded '$r' (want RESULT: MISSED — a grader that always matches is broken)" ;;
esac

# ---- P: the rendered prompt ---------------------------------------------------------------------------------
if prompt="$(bash "$LIB/render-prompt.sh" 2>"$WORK/render.err")"; then
  miss=""
  case "$prompt" in *"EXECUTION DIRECTIVE"*) ;; *) miss="$miss no-EXECUTION-DIRECTIVE" ;; esac
  case "$prompt" in *"CODE_REVIEW_RESULT v3"*) ;; *) miss="$miss no-CODE_REVIEW_RESULT-v3" ;; esac
  case "$prompt" in *"{"*) miss="$miss has-{" ;; esac
  case "$prompt" in *"PIN-MUTATION VERDICTS"*) miss="$miss has-PIN-MUTATION-VERDICTS" ;; esac
  case "$prompt" in *"include this line ONLY when"*) miss="$miss has-a-conditional-paragraph" ;; esac
  [ -z "$miss" ] && ok "P the live Phase 4.5 prompt renders: EXECUTION DIRECTIVE + CODE_REVIEW_RESULT v3, no '{', no PIN-MUTATION VERDICTS" \
    || no "P rendered prompt:$miss"
else
  no "P render-prompt.sh failed on the live SKILL.md: $(head -n 2 "$WORK/render.err" | tr '\n' ' ')"
fi
BAD="$WORK/bad-plugin/skills/self-heal-advisory"; mkdir -p "$BAD"
sed 's/"loomwright:code-reviewer",$/"loomwright:renamed-reviewer",/' \
  "$PLUGIN/skills/self-heal-advisory/SKILL.md" > "$BAD/SKILL.md"
if bash "$LIB/render-prompt.sh" "$WORK/bad-plugin" >"$WORK/bad.out" 2>"$WORK/bad.err"; then no "P a missing anchor rendered anyway"
elif [ -s "$WORK/bad.out" ] || ! grep -q 'anchor' "$WORK/bad.err"; then no "P a missing anchor: stdout not empty or the anchor not named"
else ok "P a missing anchor fails closed and names the anchor"; fi
sed 's/^\( *\)BASE_BRANCH={BASE_BRANCH}$/\1BASE_BRANCH={BASE_BRANCH} {new_input}/' \
  "$PLUGIN/skills/self-heal-advisory/SKILL.md" > "$BAD/SKILL.md"
if grep -q '{new_input}' "$BAD/SKILL.md" && ! bash "$LIB/render-prompt.sh" "$WORK/bad-plugin" >/dev/null 2>"$WORK/bad.err" \
  && grep -q '{new_input}' "$WORK/bad.err"; then ok "P an unsubstituted placeholder fails closed and is named"
else no "P an unsubstituted placeholder was not refused"; fi

# ---- Y: one protocol, no expectation in the case dirs -------------------------------------------------------
body() { awk '/^execution:/ { f = 1 } f' "$1"; }
first="$(body "$SUITE/case-template.yaml")"
case "$first" in "execution:"*) ok "Y case-template.yaml has an execution: block" ;; *) no "Y case-template.yaml has no execution: block" ;; esac
for c in "$SUITE"/[0-9]*/case.yaml; do
  cid="$(basename "$(dirname "$c")")"
  [ "$(body "$c")" = "$first" ] && ok "Y $cid/case.yaml is byte-identical to the template from execution: on" \
    || no "Y $cid/case.yaml differs from case-template.yaml from execution: on (one protocol for every case)"
done
for e in "$SUITE"/[0-9]*/case.env; do
  cid="$(basename "$(dirname "$e")")"
  bad="$(grep -vE '^(PR|BASE_SHA|HEAD_SHA)=|^#|^[[:space:]]*$' "$e" | head -n 1)"
  [ -z "$bad" ] && ok "Y $cid/case.env holds only PR= / BASE_SHA= / HEAD_SHA=" || no "Y $cid/case.env carries more than the staging inputs: $bad"
done
RC="$REPO/docs/evidence/phase45-reviewer-corpus.tsv"
if [ -f "$RC" ]; then
  while IFS="$TAB" read -r id _pr kind exp _floor; do
    [ "$kind" = miss ] && [ -n "$exp" ] || continue
    hit="$(grep -rlF -- "$exp" "$SUITE"/[0-9]*/ 2>/dev/null | head -n 1)"
    [ -z "$hit" ] && ok "Y $id's expected file is in no case dir" || no "Y $id's expected file leaks into the plugin: $hit"
  done < "$RC"
fi

# ---- the scratch source repo (laid out like this one) -------------------------------------------------------
SRC="$WORK/src"; SL="$SRC/loomwright/evals/phase45-reviewer"
mkdir -p "$SL/lib" "$SRC/loomwright/skills/self-heal-advisory" "$SRC/docs/evidence" || no "mkdir $SRC"
for f in stage-case.sh render-prompt.sh; do cp "$LIB/$f" "$SL/lib/$f" || no "copy lib/$f"; done
cp "$PLUGIN/skills/self-heal-advisory/SKILL.md" "$SRC/loomwright/skills/self-heal-advisory/SKILL.md" || no "copy SKILL.md"
SC="$SRC/docs/evidence/phase45-reviewer-corpus.tsv"
{
  printf 'case_id\tpr\tkind\texpected_file\tseverity_floor\n'
  for n in 90 91 92 93 94; do printf '%s-miss-pr9%s\t9%s\tmiss\t%s\tHIGH\n' "$n" "$n" "$n" "$EXP"; done   # 90-miss-pr990 …
  printf '95-control-pr995\t995\tcontrol\t\t\n'
} > "$SC"
printf 'one\ntwo\nthree\n' > "$SRC/app.txt"
G() { git -C "$SRC" -c commit.gpgSign=false "$@"; }
{ G init -q && G symbolic-ref HEAD refs/heads/main && G add -A && G commit -qm base; } >/dev/null 2>&1 || no "scratch source: base commit"
BASE="$(G rev-parse HEAD)"
printf 'one\nTWO\nthree\n' > "$SRC/app.txt"; printf 'new\n' > "$SRC/new.txt"; printf '\000\001\002' > "$SRC/bin.dat"
printf 'late\tedit\n' >> "$SC"; printf '# a later suite edit\n' >> "$SL/lib/stage-case.sh"
{ G add -A && G commit -qm pre-drain; } >/dev/null 2>&1 || no "scratch source: pre-drain commit"
HEAD="$(G rev-parse HEAD)"
G checkout -q "$BASE" 2>/dev/null   # the suite's own lib/ as of BASE stages every case
mkcase() {   # mkcase <id> <base> <head> — a case dir shaped as the corpus builder writes it
  mkdir -p "$SL/$1"
  printf 'PR=%s\nBASE_SHA=%s\nHEAD_SHA=%s\n' "$(printf '%s' "$1" | sed 's/.*-pr//')" "$2" "$3" > "$SL/$1/case.env"
  printf '#!/usr/bin/env bash\n# %s — stages the pre-drain diff into the eval sandbox (cwd) through the shared stager\nexec bash "$(dirname "${BASH_SOURCE[0]}")/../lib/stage-case.sh" "$(dirname "${BASH_SOURCE[0]}")"\n' "$1" > "$SL/$1/scaffold.sh"
}
for id in 90-miss-pr990 91-miss-pr991 93-miss-pr993 94-miss-pr994 95-control-pr995; do mkcase "$id" "$BASE" "$HEAD"; done
mkcase 92-miss-pr992 deadbeefdeadbeefdeadbeefdeadbeefdeadbeef "$HEAD"
SRC_BEFORE="$(G status --porcelain; G for-each-ref)"

# stage <case id> <sandbox cwd> — the case's own scaffold, run in that cwd
stage() { mkdir -p "$2" && ( cd "$2" && bash "$SL/$1/scaffold.sh" ) > "$WORK/stage.log" 2>&1; }

# ---- S: staging ---------------------------------------------------------------------------------------------
SB="$WORK/kept/90/sealed/s/cwd"
if stage 90-miss-pr990 "$SB"; then
  ok "S a reachable case stages (exit 0)"
  got="$(cd "$SB/.eval" && ls -A | tr '\n' ' ')"
  [ "$got" = "base_sha case-id head_sha review-prompt.md " ] && ok "S .eval/ holds exactly case-id, base_sha, head_sha, review-prompt.md" \
    || no "S .eval/ holds more than the staging inputs: $got"
  [ "$(cat "$SB/.eval/case-id")" = 90-miss-pr990 ] && ok "S .eval/case-id names the case dir" || no "S .eval/case-id is '$(cat "$SB/.eval/case-id")'"
  leak="$(find "$SB" -name 'phase45-reviewer-corpus.tsv' -o -path "$SB/loomwright/evals/phase45-reviewer" 2>/dev/null | head -n 1)"
  [ -z "$leak" ] && ok "S no corpus table and no suite dir in the sandbox (the archive and the diff exclude them)" || no "S the sandbox carries $leak"
  leak="$(grep -rlF --exclude-dir=.git -- "$TOKEN" "$SB" 2>/dev/null | head -n 1)"
  [ -z "$leak" ] && ok "S no file in the sandbox names the expected file" || no "S the expected file leaks into the sandbox: $leak"
  leak="$(cat "$SB/.eval/case-id" "$SB/.eval/base_sha" "$SB/.eval/head_sha" | grep -E 'BLOCKING|HIGH|MEDIUM|LOW' | head -n 1)"
  [ -z "$leak" ] && ok "S no severity floor in the staging inputs" || no "S a severity floor in .eval/: $leak"
  d="$(git -C "$SB" diff --name-only "origin/main...HEAD" 2>/dev/null | tr '\n' ' ')"
  [ "$d" = "app.txt bin.dat new.txt " ] && ok "S git diff origin/main...HEAD is exactly the pre-drain diff (suite and table edits excluded)" \
    || no "S the replay diff is '$d'"
  [ "$(git -C "$SB" show HEAD:app.txt 2>/dev/null)" = "$(G show "$HEAD:app.txt")" ] && cmp -s "$SB/bin.dat" <(G show "$HEAD:bin.dat") \
    && ok "S the replay branch carries the pre-drain head's content (text and binary)" || no "S the replay content differs from the pre-drain head"
  [ "$(git -C "$SB" symbolic-ref --short HEAD 2>/dev/null)" = replay ] && [ -z "$(git -C "$SB" status --porcelain 2>/dev/null)" ] \
    && ok "S the sandbox is on branch replay, clean (.eval/ excluded)" || no "S the sandbox branch/status is wrong: $(git -C "$SB" status --short 2>&1 | head -n 3 | tr '\n' ' ')"
  [ "$(cat "$SB/.eval/review-prompt.md")" = "$(bash "$LIB/render-prompt.sh" 2>/dev/null)" ] && ok "S .eval/review-prompt.md is the rendered Phase 4.5 prompt" \
    || no "S .eval/review-prompt.md is not the rendered prompt"
else
  no "S staging a reachable case failed: $(tail -n 3 "$WORK/stage.log" | tr '\n' ' ')"
fi
SU="$WORK/kept/92/sealed/s/cwd"
if stage 92-miss-pr992 "$SU" && [ -f "$SU/.eval/unstageable" ] && [ ! -e "$SU/.git" ] && [ ! -e "$SU/.eval/review-prompt.md" ]; then
  ok "S a nonexistent BASE_SHA ⇒ exit 0 with .eval/unstageable and nothing staged"
else
  no "S unstageable: exit/marker wrong — $(tail -n 2 "$WORK/stage.log" | tr '\n' ' ')"
fi
for id in 91 93 95; do
  case "$id" in 95) cid=95-control-pr995 ;; *) cid="$id-miss-pr99${id#9}" ;; esac
  stage "$cid" "$WORK/kept/$id/sealed/s/cwd" || no "S staging $cid failed: $(tail -n 2 "$WORK/stage.log" | tr '\n' ' ')"
done
[ "$(G status --porcelain; G for-each-ref)" = "$SRC_BEFORE" ] && ok "S nothing was written into the source repo" || no "S staging changed the source repo"
leak="$(grep -rlF -- "$TOKEN" "$PLUGIN" "$SRC/loomwright" 2>/dev/null | head -n 1)"
[ -z "$leak" ] && ok "S no file under the plugin root carries the fixture table's expected file" || no "S the expected file leaks under a plugin root: $leak"

# ---- M: summarize over the fixture corpus + kept sandboxes --------------------------------------------------
[ ! -d "$WORK/kept/90/sealed/s/cwd/.eval" ] || mkreply "$WORK/kept/90/sealed/s/cwd/.eval/reviewer-reply.md" FAIL HIGH "$EXP"
[ ! -d "$WORK/kept/91/sealed/s/cwd/.eval" ] || mkreply "$WORK/kept/91/sealed/s/cwd/.eval/reviewer-reply.md" PASS LOW "$OTHER"
[ ! -d "$WORK/kept/95/sealed/s/cwd/.eval" ] || mkreply "$WORK/kept/95/sealed/s/cwd/.eval/reviewer-reply.md" FAIL HIGH "$OTHER" MEDIUM "$OTHER"
mkdir -p "$WORK/kept/96/sealed/s/cwd/.eval" "$WORK/kept/97/sealed/s/cwd"   # 96: a case not in the table; 97: no case-id
printf '96-not-in-corpus\n' > "$WORK/kept/96/sealed/s/cwd/.eval/case-id"
runs='[]'
for id in 90 91 92 93 94 95 96 97; do
  mkdir -p "$WORK/kept/$id/out"
  [ "$id" = 94 ] || printf '%s\n' '{"type":"system","subtype":"init","model":"fixture-model"}' '{"type":"result","num_turns":3}' > "$WORK/kept/$id/out/trace.jsonl"
  [ ! -d "$WORK/kept/$id/sealed" ] || chmod 000 "$WORK/kept/$id/sealed"   # sealed, as --keep-temp leaves it
  runs="$(jq -c --arg n "case-$id" --arg tp "$WORK/kept/$id/out/trace.jsonl" '. + [{name: $n, arms: {with: [{score: 1, turns: 3, costUsd: 0.5, tracePath: $tp}]}}]' <<<"$runs")"
done
jq -n --argjson c "$runs" '{cases: $c}' > "$WORK/eval.json"
if sum="$(bash "$LIB/summarize.sh" "$WORK/eval.json" "$SUITE" "$SC" 2>"$WORK/sum.err")"; then
  for want in "caught: 1/4" "unstageable: 1" "no_reply: 1" "noise: 1 BLOCKING/HIGH on 1 controls" "model: fixture-model" "turns: 24"; do
    grep -qxF "$want" <<<"$sum" && ok "M summarize prints '$want'" || no "M summarize lacks '$want'"
  done
  for want in "| 90-miss-pr990 | miss | 990 | CAUGHT |" "| 91-miss-pr991 | miss | 991 | MISSED |" \
    "| 92-miss-pr992 | miss | 992 | UNSTAGEABLE |" "| 93-miss-pr993 | miss | 993 | MISSED (no reply) |" \
    "| 94-miss-pr994 | miss | 994 | ? |" "| 95-control-pr995 | control | 995 | NOISE | 1 |" \
    "| 96-not-in-corpus | ? | ? | NOT_IN_CORPUS (not counted) |" "| ? (case-97 run 1) | ? | ? | ? (kept sandbox has no .eval/case-id) |"; do
    grep -qF "$want" <<<"$sum" && ok "M row $want" || no "M no row '$want'"
  done
else
  no "M summarize.sh failed: $(head -n 3 "$WORK/sum.err" | tr '\n' ' ')"
fi
# a grader that cannot grade: every graded row reads `?`, a miss stays in Y as not caught, nothing is guessed
printf '#!/usr/bin/env bash\necho "grader broke" >&2\nexit 2\n' > "$WORK/broken-grade.sh"
sum="$(PHASE45_GRADE="$WORK/broken-grade.sh" bash "$LIB/summarize.sh" "$WORK/eval.json" "$SUITE" "$SC" 2>/dev/null)"
grep -qxF "caught: 0/4" <<<"$sum" && grep -qF "| 91-miss-pr991 | miss | 991 | ? (grade error: grader broke) |" <<<"$sum" \
  && grep -qxF "noise: 0 BLOCKING/HIGH on 0 controls" <<<"$sum" \
  && ok "M a grader error ⇒ a '? (grade error …)' row, kept in Y as not caught (caught: 0/4), no control measured" \
  || no "M a grader error was not reported as '?' rows: $(printf '%s\n' "$sum" | grep -E '^caught|^noise|91-miss' | tr '\n' ' ')"
chmod -R u+rwx "$WORK/kept" 2>/dev/null

# ---- R: the missing-tool path, through a PATH stub that shadows `claude` ------------------------------------
STUB="$WORK/stub"; MARK="$WORK/stub-invoked"; mkdir -p "$STUB" "$WORK/run-tmp" "$WORK/run-home"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\nexit 1\n' "$MARK" > "$STUB/claude"; chmod +x "$STUB/claude"
# Belt and braces should a mutated run.sh ever reach a real `claude`: an emptied environment (no credential
# variable survives `env -i`), a scratch HOME, a case filter that matches nothing and a zero cost ceiling, so
# no eval run can launch.
( cd "$WORK" && env -i PATH="$STUB:$PATH" HOME="$WORK/run-home" TMPDIR="$WORK/run-tmp" \
    bash "$LIB/run.sh" --case '__phase45_selftest_matches_no_case__' --max-cost-usd 0 ) > "$WORK/run.out" 2> "$WORK/run.err"
rrc=$?
[ "$rrc" -ne 0 ] && ok "R run.sh exits non-zero when claude plugin eval is unavailable" || no "R run.sh exited 0 with the tool unavailable"
grep -qxF "phase45-reviewer: missing tool: claude plugin eval" "$WORK/run.err" && ok "R the missing tool is named on stderr" \
  || no "R stderr lacks the missing-tool line: $(head -n 2 "$WORK/run.err" | tr '\n' ' ')"
grep -q '^caught:' "$WORK/run.out" && no "R a caught: line was printed with the tool unavailable" || ok "R no caught: line"
[ -f "$MARK" ] && grep -qxF "plugin eval --help" "$MARK" && ok "R the PATH stub was the binary invoked (claude plugin eval --help)" \
  || no "R the PATH stub was not invoked — run.sh did not resolve claude through PATH"

echo "PASS: $pass FAIL: $fail"
[ "$fail" -eq 0 ]
