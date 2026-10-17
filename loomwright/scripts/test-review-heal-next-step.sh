#!/usr/bin/env bash
# test-review-heal-next-step.sh — self-test for review-heal-next-step.sh, the `/review-pr --until-mergeable`
# drain loop's driver (automate-speed/12). One tally (`PASS: <n> FAIL: <m>`, exit 1 on any failure).
# Hermetic: every case runs in its own `mktemp -d` sandbox (HOME sandboxed, a stub `gh` first on PATH —
# no network); the scoped wait, the CI probe, the rules gate and the escalation classifier are sequential
# stubs fed from the case's `<name>.lines`, and the notify / postmortem seams are recorders, all through
# the driver's RH_*_CMD command lines. The real drain-rounds.sh, classify-bot-review.sh,
# wrap-external-text.sh, fix-floor.sh and drain-subfloor-decision.sh run.
#
# LEGS
#   G   GOLDEN PARITY (AC1). Every case under fixtures/review-heal-golden/ (MAP.tsv names each and the
#       branch it pins; REQUIRED_BRANCHES below must all be mapped, every case dir must have one row) is
#       driven through the driver by its `drive` file; the transcript (each call's instruction + exit
#       code), the REVIEW_HEAL_RESULT block, the drain-rounds ledger, the PR comments and the side-effect
#       recorder must equal the case's expected.* files byte for byte after normalisation (sandbox root →
#       <ROOT>, the driver's directory → <SCRIPTS>). Every emitted block passes
#       `automate-helpers.sh sidecar-check`, and equals the `done` instruction's review_heal_result.
#   I   IDEMPOTENCY (AC3). After every call that printed an instruction, two calls with no --result print
#       it byte for byte and change nothing (every file under the sandbox .supervisor/, the PR-comment,
#       side-effect and stub-call logs); `--start drain` while a spawn is pending re-prints it too.
#   A   EARNED FALLBACK (AC2). Exactly ONE `fallback review` spawn in the two no-lens cases and in the
#       once-per-run case (none in any other case, none in the unknown-channel case); `--start fallback`
#       while that spawn is pending and after the run's `done` exits 2 with
#       `review-heal-next-step: fallback_already_spawned — …` on stderr, prints nothing, writes nothing;
#       before the run spawned it, it exits 2 `fallback_not_earned`, nothing written.
#   S   NO MERGE / NO FORCE (AC4). No printed instruction in any leg contains `gh pr merge` or `--force`;
#       the driver text holds neither; the fix-worker push is `git push origin HEAD:<head_ref>`; this
#       change's files add no line to the CLAUDE.md invariant grep (its negation filter included).
#   E   CLOSED ENUMS. Every printed instruction's `do` is spawn|done (the driver's subset of item 06's
#       closed spawn|ask|park|done), every `what` is in WHAT_ENUM, every `step` is a driver `case` arm.
#   D   DOC MIRROR. The schema doc's `what` table equals WHAT_ENUM and its step table equals the driver's
#       `case` arms; RESULT_SCHEMAS.md points at the schema doc.
#   R   REPORT VALIDATION. Malformed reports (an unknown / missing id, a bad verdict, a multi-line finding,
#       confirmed without auto_fixable, a fix report without a self_review line ⇒ `self_review_missing`,
#       a non-hex pushed_sha, a --result with nothing pending) exit 2, print nothing and write nothing; a
#       report re-sent after it was taken re-prints the pending instruction and writes nothing.
#   W   RESUMABLE WAIT. A CONTINUE line ⇒ exit 3, nothing printed; the next no-result call re-calls the
#       wait with `--continue` and reaches the validate spawn.
#   B   BRANCHES the goldens do not reach: confirmed-not-auto-fixable ⇒ ESCALATED findings; a rules gate
#       `unresolved` ⇒ ESCALATED other with termination_reason unset; a fork PR ⇒ no fix spawn, ESCALATED.
#   M   MUTATION CONTROLS — each mutant gated non-empty + differs from the driver + `bash -n` (its anchor
#       occurring exactly once); each must turn its leg red:
#         MF  the line that emits the `fallback review` spawn deleted   ⇒ G fallback-no-review-lens (AC8)
#         MA  the fallback_already_spawned refusal branch removed       ⇒ A
#         MI  the no-result re-print replaced by a re-run of the step  ⇒ I
#         MP  `--force` added to the fix worker's push line             ⇒ S
#         MB  the bound-hit termination_reason flipped to converged     ⇒ G bound-hit-escalated
#         MS  one unguarded merge-command line appended (built here at run time from pieces, so this file
#             never holds the positive literal on one line)            ⇒ S
#
# ENV: RH_CASES="<a> <b>" runs only those golden cases (G/I only); RH_SKIP_MUTANTS=1 skips M;
# RH_GOLDEN_ACTUAL=<dir> copies each case's actual outputs there (for inspecting a diff — never into
# the fixtures). Bash 3.2 / BSD-userland safe; everything lives under one work dir removed in a trap.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
FIX="$HERE/fixtures/review-heal-golden"
DRIVER="$HERE/review-heal-next-step.sh"
SCHEMA_DOC="$REPO/loomwright/docs/result-schemas/review-heal-next-step.md"
PR="https://github.com/acme/widgets/pull/7"
WHAT_ENUM="validate findings
fallback review
fix worker"
REQUIRED_BRANCHES="converged bound_hit sub_floor_converged ci_untrusted fix_round no_review_lens_posted
no_review_lens_posted_ambiguous channel_unknown fix_floor_invalid fallback_review_ran"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass + 1)); }
no() { echo "FAIL: $1"; fail=$((fail + 1)); }

WORK="$(mktemp -d)" || { echo "FAIL: mktemp -d"; exit 1; }
WORK_P="$(cd "$WORK" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT
EMITTED="$WORK/emitted.jsonl"; : > "$EMITTED"   # every instruction any leg saw (S / E legs)

# --------------------------------------------------------------------------------------
# stubs
# --------------------------------------------------------------------------------------
GH_STUB_BODY='#!/usr/bin/env bash
all="$*"
printf "%s\n" "$all" | head -n 1 >> "$RH_CALLS"
if [ "${1:-} ${2:-}" = "pr comment" ]; then printf "%s\n----\n" "${5:-}" >> "$RH_COMMENTS"; fi
n=0
while IFS="	" read -r rc times pat out || [ -n "$rc" ]; do
  n=$((n + 1))
  case "$rc" in ""|"#"*) continue ;; esac
  # shellcheck disable=SC2254
  case "$all" in $pat) ;; *) continue ;; esac
  if [ "$times" != "*" ]; then
    used="$(cat "$RH_GH_STATE/$n" 2>/dev/null || echo 0)"
    [ "$used" -lt "$times" ] || continue
    echo $((used + 1)) > "$RH_GH_STATE/$n"
  fi
  case "$out" in @*) cat "$RH_CASE/${out#@}" ;; "") ;; *) printf "%s\n" "$out" ;; esac
  exit "$rc"
done < "$RH_GH_TABLE"
echo "gh-stub: unmatched: $all" >&2
exit 1
'
SEQ_STUB_BODY='#!/usr/bin/env bash
name="$1"; shift
printf "%s %s\n" "$name" "$*" >> "$RH_CALLS"
f="$RH_SEQ_DIR/$name.lines"
[ -f "$f" ] || exit 0
k="$(cat "$RH_SEQ_STATE/$name" 2>/dev/null || echo 0)"; k=$((k + 1)); echo "$k" > "$RH_SEQ_STATE/$name"
total="$(grep -c "" "$f")"; [ "$k" -le "$total" ] || k="$total"
sed -n "${k}p" "$f"
'
REC_STUB_BODY='#!/usr/bin/env bash
printf "%s\n" "$*" >> "$RH_SIDE_LOG"
exit 0
'

# setup_case <fixture case dir> — a fresh sandbox; sets C C_ROOT C_ROOT_P C_BIN C_HOME C_CASE
setup_case() {
  local cd_="$1" nm
  C="$(mktemp -d "$WORK/case.XXXXXX")" || return 1
  C_CASE="$cd_"; C_ROOT="$C/root"; C_BIN="$C/bin"; C_HOME="$C/home"
  mkdir -p "$C_ROOT" "$C_BIN" "$C_HOME" "$C/seq" "$C/seqstate" "$C/ghstate"
  C_ROOT_P="$(cd "$C_ROOT" && pwd -P)"
  printf '%s' "$GH_STUB_BODY" > "$C_BIN/gh"; printf '%s' "$SEQ_STUB_BODY" > "$C_BIN/seq"
  printf '%s' "$REC_STUB_BODY" > "$C_BIN/rec"; chmod +x "$C_BIN/gh" "$C_BIN/seq" "$C_BIN/rec"
  : > "$C/side.log"; : > "$C/comments.log"; : > "$C/calls.log"
  for nm in wait probe rules escalation; do
    if [ -f "$cd_/$nm.lines" ]; then cp "$cd_/$nm.lines" "$C/seq/"
    elif [ -f "$FIX/_common/$nm.lines" ]; then cp "$FIX/_common/$nm.lines" "$C/seq/"; fi
  done
  if [ -f "$cd_/gh.table" ]; then cp "$cd_/gh.table" "$C/gh.table"; else : > "$C/gh.table"; fi
}

# drv <driver> <args…> — one driver call in the sandbox; sets OUT ERR RCV (files: $C/last.out / last.err)
drv() {
  local d="$1"; shift
  (
    cd "$C_ROOT" || exit 98
    unset LOOMWRIGHT_GH_BIN RH_FROM RH_UNTIL GH
    export HOME="$C_HOME" PATH="$C_BIN:$PATH" RH_GH_TABLE="$C/gh.table" RH_CASE="$C_CASE" RH_GH_STATE="$C/ghstate"
    export RH_SEQ_DIR="$C/seq" RH_SEQ_STATE="$C/seqstate" RH_SIDE_LOG="$C/side.log" RH_COMMENTS="$C/comments.log"
    export RH_CALLS="$C/calls.log"
    export RH_WAIT_CMD="$C_BIN/seq wait" RH_PROBE_CMD="$C_BIN/seq probe" RH_RULES_CMD="$C_BIN/seq rules"
    export RH_ESCALATION_CMD="$C_BIN/seq escalation" RH_NOTIFY_CMD="$C_BIN/rec notify" RH_POSTMORTEM_CMD="$C_BIN/rec postmortem"
    bash "$d" "$PR" "$@"
  ) > "$C/last.out" 2> "$C/last.err"
  RCV=$?
  OUT="$(cat "$C/last.out")"; ERR="$(cat "$C/last.err")"
  [ -n "$OUT" ] && printf '%s\n' "$OUT" >> "$EMITTED"
  return 0
}
# snapshot — every file the driver can write, plus the stub logs
snapshot() {
  {
    find "$C_ROOT/.supervisor" -type f 2>/dev/null | env LC_ALL=C sort | while IFS= read -r f; do
      printf '%s ' "${f#"$C_ROOT"/}"; cksum < "$f"
    done
    for f in side.log comments.log calls.log; do printf '%s ' "$f"; cksum < "$C/$f"; done
  }
}
norm_text() { # <driver dir> — stdin → stdout
  local t
  t="$(cat; printf x)"; t="${t%x}"
  t="${t//"$C_ROOT_P"/<ROOT>}"; t="${t//"$C_ROOT"/<ROOT>}"
  t="${t//"$1"/<SCRIPTS>}"
  printf '%s' "$t"
}

# run_golden <case> <driver> <idem 0|1> — sets LEG_MSG / IDEM_MSG; the actuals are left in $C/actual.*
run_golden() {
  local case_="$1" d="$2" idem="$3" cd_ ddir line args first second s1 s2 rf
  cd_="$FIX/$case_"; ddir="$(cd "$(dirname "$d")" && pwd)"
  LEG_MSG=""; IDEM_MSG=""
  setup_case "$cd_" || { LEG_MSG="sandbox setup failed"; return 1; }
  : > "$C/actual.out"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in "call: "*) ;; *) continue ;; esac
    args="${line#call: }"
    # shellcheck disable=SC2034  # CASE is read by the eval'd call line ("$CASE/report-1.json")
    CASE="$cd_"
    eval "drv \"\$d\" $args"
    { printf '$ %s\n' "$line"; [ -n "$OUT" ] && printf '%s\n' "$OUT" | norm_text "$ddir"; printf '= %s\n' "$RCV"; } >> "$C/actual.out"
    if [ "$idem" = 1 ] && [ "$RCV" = 0 ] && [ -n "$OUT" ]; then
      first="$OUT"; s1="$(snapshot)"
      drv "$d"; second="$OUT"
      [ "$RCV" = 0 ] && [ "$second" = "$first" ] || IDEM_MSG="${IDEM_MSG:+$IDEM_MSG; }no-result call 1 after '$line' did not re-print (rc $RCV)"
      drv "$d"
      [ "$RCV" = 0 ] && [ "$OUT" = "$first" ] || IDEM_MSG="${IDEM_MSG:+$IDEM_MSG; }no-result call 2 after '$line' did not re-print (rc $RCV)"
      if [ "$(printf '%s' "$first" | jq -r '.do')" = spawn ]; then
        drv "$d" --start drain
        [ "$RCV" = 0 ] && [ "$OUT" = "$first" ] || IDEM_MSG="${IDEM_MSG:+$IDEM_MSG; }--start drain while a spawn is pending did not re-print (rc $RCV)"
      fi
      s2="$(snapshot)"
      [ "$s1" = "$s2" ] || IDEM_MSG="${IDEM_MSG:+$IDEM_MSG; }files changed on a no-result call after '$line'"
    fi
  done < "$cd_/drive"
  rf="$(ls "$C_ROOT"/.supervisor/review-heal/*.review-heal-result.md 2>/dev/null | head -n 1)"
  if [ -n "$rf" ]; then cp "$rf" "$C/actual.result.md"; else rm -f "$C/actual.result.md"; fi
  ( cd "$C_ROOT" && bash "$HERE/drain-rounds.sh" read "$PR" ) > "$C/actual.ledger.json" 2>/dev/null
  cp "$C/comments.log" "$C/actual.comments"
  norm_text "$ddir" < "$C/side.log" > "$C/actual.side"
  if [ -n "${RH_GOLDEN_ACTUAL:-}" ] && [ "$d" = "$DRIVER" ]; then
    mkdir -p "$RH_GOLDEN_ACTUAL/$case_" && cp "$C"/actual.* "$RH_GOLDEN_ACTUAL/$case_/"
  fi
  local f
  for f in out ledger.json comments side; do
    if [ -f "$cd_/expected.$f" ]; then
      cmp -s "$cd_/expected.$f" "$C/actual.$f" || { LEG_MSG="${LEG_MSG:+$LEG_MSG; }expected.$f differs"; }
    elif [ -s "$C/actual.$f" ]; then LEG_MSG="${LEG_MSG:+$LEG_MSG; }no expected.$f but the run produced one"; fi
  done
  if [ -f "$cd_/expected.result.md" ]; then
    { [ -f "$C/actual.result.md" ] && cmp -s "$cd_/expected.result.md" "$C/actual.result.md"; } \
      || LEG_MSG="${LEG_MSG:+$LEG_MSG; }expected.result.md differs"
  elif [ -f "$C/actual.result.md" ]; then LEG_MSG="${LEG_MSG:+$LEG_MSG; }no expected.result.md but a result file was written"; fi
  [ -z "$LEG_MSG" ]
}

# --------------------------------------------------------------------------------------
# G — golden parity (+ I idempotency on the same runs)
# --------------------------------------------------------------------------------------
echo "G/I: golden parity + idempotency"
[ -f "$FIX/MAP.tsv" ] || no "G: fixtures/review-heal-golden/MAP.tsv missing"
MAP_CASES="$(awk -F'\t' '!/^#/ && NF >= 2 {print $1}' "$FIX/MAP.tsv" 2>/dev/null)"
for b in $REQUIRED_BRANCHES; do
  if awk -F'\t' -v b="$b" '!/^#/ && $2 == b {f=1} END {exit !f}' "$FIX/MAP.tsv"; then ok "G: branch $b mapped"
  else no "G: branch $b has no MAP.tsv row"; fi
done
for dir in "$FIX"/*/; do
  n="$(basename "$dir")"; [ "$n" = _common ] && continue
  c="$(awk -F'\t' -v n="$n" '!/^#/ && $1 == n' "$FIX/MAP.tsv" | grep -c .)"
  [ "$c" = 1 ] && ok "G: case $n has one MAP row" || no "G: case $n has $c MAP rows"
done
for n in $MAP_CASES; do [ -d "$FIX/$n" ] || no "G: MAP row $n has no case directory"; done
for n in ${RH_CASES:-$MAP_CASES}; do
  if run_golden "$n" "$DRIVER" 1; then ok "G: $n byte-identical"; else no "G: $n — $LEG_MSG"; fi
  if [ -z "$IDEM_MSG" ]; then ok "I: $n no-result re-prints, nothing written"; else no "I: $n — $IDEM_MSG"; fi
  cp "$C/actual.out" "$WORK/transcript.$n"
  if [ -f "$C/actual.result.md" ]; then
    sc="$(bash "$HERE/automate-helpers.sh" sidecar-check "$C/actual.result.md" 2>/dev/null)"
    case "$sc" in ok*) ok "G: $n result block passes sidecar-check" ;; *) no "G: $n sidecar-check: $sc" ;; esac
    last="$(grep -v '^\$ \|^= ' "$C/actual.out" | tail -n 1)"
    if [ "$(printf '%s' "$last" | jq -r '.review_heal_result')" = "$(cat "$C/actual.result.md")" ]; then
      ok "G: $n done carries the block verbatim"
    else no "G: $n done's review_heal_result differs from the result file"; fi
  fi
done

# --------------------------------------------------------------------------------------
# A — the earned fallback: once per run, refusals by name
# --------------------------------------------------------------------------------------
echo "A: earned fallback"
count_fallback() { grep -c '"what":"fallback review"' "$WORK/transcript.$1" 2>/dev/null || true; }
if [ -z "${RH_CASES:-}" ]; then
  for n in fallback-no-review-lens fallback-ambiguous-output fallback-once-per-run; do
    [ "$(count_fallback "$n")" = 1 ] && ok "A: $n spawns exactly one fallback review" || no "A: $n spawned $(count_fallback "$n") fallback reviews"
  done
  for n in converged-ready bound-hit-escalated sub-floor-converged-ready ci-untrusted-escalated fix-round-pushed \
           unknown-channel-escalated fix-floor-invalid-escalated; do
    [ "$(count_fallback "$n")" = 0 ] && ok "A: $n spawns no fallback review" || no "A: $n spawned a fallback review"
  done
  if grep -q '"decision":"ESCALATED"' "$WORK/transcript.unknown-channel-escalated" \
     && ! grep -q '"what":"fallback review"' "$WORK/transcript.unknown-channel-escalated"; then
    ok "A: unknown channel ⇒ ESCALATED, the fallback trigger never evaluated"
  else no "A: the unknown-channel case did not escalate ahead of the fallback"; fi
fi
# a_refusal <driver> <expected name> <label>
a_refusal() {
  local d="$1" want="$2" lbl="$3" s1 s2
  s1="$(snapshot)"; drv "$d" --start fallback; s2="$(snapshot)"
  if [ "$RCV" = 2 ] && [ -z "$OUT" ] && printf '%s' "$ERR" | grep -q "^review-heal-next-step: $want — " && [ "$s1" = "$s2" ]; then
    ok "A: $lbl ⇒ exit 2 $want, nothing printed or written"; return 0
  fi
  no "A: $lbl ⇒ rc $RCV, stdout '${OUT:0:60}', stderr '${ERR:0:120}', files $( [ "$s1" = "$s2" ] && echo same || echo changed)"; return 1
}
leg_a() { # <driver> — 0 when every refusal holds
  local d="$1" r=0
  setup_case "$FIX/fallback-no-review-lens"
  drv "$d" --start drain
  [ "$(printf '%s' "$OUT" | jq -r '.what' 2>/dev/null)" = "fallback review" ] || { no "A: the no-lens case did not print the fallback spawn first"; return 1; }
  a_refusal "$d" fallback_already_spawned "a second request while the spawn is pending" || r=1
  drv "$d" --result-file "$FIX/fallback-no-review-lens/report-1.json"
  a_refusal "$d" fallback_already_spawned "a second request after the run's done" || r=1
  setup_case "$FIX/converged-ready"
  drv "$d" --start drain
  a_refusal "$d" fallback_not_earned "a request before the run spawned it" || r=1
  return "$r"
}
leg_a "$DRIVER" || true

# --------------------------------------------------------------------------------------
# S — no merge, no force
# --------------------------------------------------------------------------------------
echo "S: no merge / no force"
MP_A="gh pr"; MP_B="merge"; MP_C="--squash"
leg_s() { # <driver> <instructions file> — 0 when clean
  local d="$1" f="$2" pos
  if grep -F -- "$MP_A $MP_B" "$f" >/dev/null 2>&1 || grep -F -- "--force" "$f" >/dev/null 2>&1; then
    LEG_MSG="an instruction carries a merge command or --force"; return 1; fi
  if grep -nF -- "$MP_A $MP_B" "$d" >/dev/null 2>&1; then LEG_MSG="the driver text holds a merge command"; return 1; fi
  if grep -nF -- "--force" "$d" >/dev/null 2>&1; then LEG_MSG="the driver text holds --force"; return 1; fi
  pos="$(grep -n -- "$MP_A $MP_B $MP_C" "$d" "$HERE/test-review-heal-next-step.sh" "$SCHEMA_DOC" 2>/dev/null | grep -viE "no |never |not ")"
  [ -z "$pos" ] || { LEG_MSG="a positive invariant-grep line: $pos"; return 1; }
  return 0
}
if leg_s "$DRIVER" "$EMITTED"; then ok "S: no instruction / driver line carries a merge command or --force; no new invariant surface"
else no "S: $LEG_MSG"; fi
if grep -h '"what":"fix worker"' "$EMITTED" | jq -r '.push[1]' | grep -qx 'git push origin HEAD:feature/widget-config'; then
  ok "S: the fix worker's push is the regular explicit-refspec push"
else no "S: the fix worker's push line is not git push origin HEAD:<head_ref>"; fi

# --------------------------------------------------------------------------------------
# E — closed enums;  D — doc mirror
# --------------------------------------------------------------------------------------
echo "E/D: closed enums and the schema doc"
ARMS="$(sed -n '/^rh_dispatch() {/,/^}/p' "$DRIVER" | sed -n 's/^    \([a-z-]*\)) rh_.*/\1/p')"
bad="$(jq -r '.do' "$EMITTED" | grep -vxE 'spawn|done' | sort -u)"
[ -z "$bad" ] && ok "E: every do is spawn|done" || no "E: unlisted do value(s): $bad"
bad="$(jq -r 'select(.do == "spawn") | .what' "$EMITTED" | sort -u | while IFS= read -r w; do printf '%s\n' "$WHAT_ENUM" | grep -qxF "$w" || echo "$w"; done)"
[ -z "$bad" ] && ok "E: every spawn.what is in the closed what enum" || no "E: unlisted what value(s): $bad"
bad="$(jq -r '.step' "$EMITTED" | sort -u | while IFS= read -r s; do printf '%s\n' "$ARMS" | grep -qxF "$s" || echo "$s"; done)"
[ -z "$bad" ] && ok "E: every step is a driver case arm" || no "E: step(s) not a case arm: $bad"
if [ -f "$SCHEMA_DOC" ]; then
  doc_what="$(sed -n '/<!-- what-enum:begin -->/,/<!-- what-enum:end -->/p' "$SCHEMA_DOC" | sed -n 's/^| `"\([^"]*\)"` |.*/\1/p')"
  [ "$(printf '%s\n' "$doc_what" | sort)" = "$(printf '%s\n' "$WHAT_ENUM" | sort)" ] && ok "D: the doc's what table equals the closed enum" \
    || no "D: the doc's what table ($(printf '%s' "$doc_what" | tr '\n' ',')) differs from the enum"
  doc_steps="$(sed -n '/<!-- steps:begin -->/,/<!-- steps:end -->/p' "$SCHEMA_DOC" | sed -n 's/^| `\([a-z-]*\)` |.*/\1/p')"
  [ "$doc_steps" = "$ARMS" ] && ok "D: the doc's step table equals the driver's case arms, in order" \
    || no "D: the doc's step table differs from the case arms"
  grep -qF -- 'fallback_already_spawned' "$SCHEMA_DOC" && ok "D: the doc names fallback_already_spawned" || no "D: the doc does not name fallback_already_spawned"
else no "D: $SCHEMA_DOC missing"; fi
grep -qF 'See [result-schemas/review-heal-next-step.md](result-schemas/review-heal-next-step.md).' "$REPO/loomwright/docs/RESULT_SCHEMAS.md" \
  && ok "D: RESULT_SCHEMAS.md points at the schema doc" || no "D: RESULT_SCHEMAS.md has no pointer to the schema doc"

# --------------------------------------------------------------------------------------
# R — report validation (exit 2, nothing written) and replay
# --------------------------------------------------------------------------------------
echo "R: report validation"
r_refuse() { # <label> <json> [stderr pattern]
  local s1 s2
  s1="$(snapshot)"; drv "$DRIVER" --result "$2"; s2="$(snapshot)"
  if [ "$RCV" = 2 ] && [ -z "$OUT" ] && [ "$s1" = "$s2" ] && { [ -z "${3:-}" ] || printf '%s' "$ERR" | grep -q -- "$3"; }; then
    ok "R: $1 ⇒ exit 2, nothing printed or written"
  else no "R: $1 ⇒ rc $RCV stdout '${OUT:0:60}' stderr '${ERR:0:100}' files $( [ "$s1" = "$s2" ] && echo same || echo changed)"; fi
}
setup_case "$FIX/converged-ready"
drv "$DRIVER" --result '{"findings":[]}'
[ "$RCV" = 2 ] && [ -z "$OUT" ] && [ ! -e "$C_ROOT/.supervisor" ] && ok "R: --result with nothing pending ⇒ exit 2, nothing written" \
  || no "R: --result with nothing pending ⇒ rc $RCV"
drv "$DRIVER" --start drain; PEND="$OUT"
r_refuse "an unknown id" '{"findings":[{"id":"r9-9","verdict":"dismissed","finding":"x","reason":"stale"}]}' 'every candidate id'
r_refuse "a missing id" '{"findings":[]}' 'every candidate id'
r_refuse "a bad verdict" '{"findings":[{"id":"r1-1","verdict":"maybe","finding":"x","reason":"stale"}]}' 'malformed'
r_refuse "a multi-line finding" '{"findings":[{"id":"r1-1","verdict":"dismissed","finding":"a\nb","reason":"stale"}]}' 'malformed'
r_refuse "confirmed without auto_fixable" '{"findings":[{"id":"r1-1","verdict":"confirmed","finding":"x"}]}' 'malformed'
r_refuse "an unknown severity" '{"findings":[{"id":"r1-1","verdict":"confirmed","finding":"x","auto_fixable":true,"severity":"CRITICAL"}]}' 'malformed'
r_refuse "a non-object --result" '[1]' 'not a JSON object'
GOOD='{"findings":[{"id":"r1-1","verdict":"confirmed","finding":"load_config ignores the exit status of jq","auto_fixable":true}]}'
drv "$DRIVER" --result "$GOOD"; FIXSPAWN="$OUT"
[ "$(printf '%s' "$FIXSPAWN" | jq -r '.what')" = "fix worker" ] && ok "R: a well-formed report is taken (fix worker spawn)" || no "R: the good report did not reach the fix worker"
s1="$(snapshot)"; drv "$DRIVER" --result "$GOOD"; s2="$(snapshot)"
[ "$RCV" = 0 ] && [ "$OUT" = "$FIXSPAWN" ] && [ "$s1" = "$s2" ] && ok "R: the taken report re-sent ⇒ the pending spawn re-prints, nothing written" \
  || no "R: replay ⇒ rc $RCV"
r_refuse "a fix report without self_review" '{"pushed":true,"pushed_sha":"b2c3d4e5f60718293a4b5c6d7e8f901234567890"}' 'self_review_missing'
r_refuse "a non-hex pushed_sha" '{"pushed":true,"pushed_sha":"not-a-sha","self_review":"self_review: clean"}' 'hex'
r_refuse "a validate report at the fix spawn" '{"findings":[]}' 'pushed true|false'

# --------------------------------------------------------------------------------------
# W — resumable wait
# --------------------------------------------------------------------------------------
echo "W: resumable wait"
setup_case "$FIX/converged-ready"
{ echo "CONTINUE sha=a1b2c3d4e5f60718293a4b5c6d7e8f9012345678 remaining=600 pending=ci"; cat "$FIX/converged-ready/wait.lines"; } > "$C/seq/wait.lines"
drv "$DRIVER" --start drain
[ "$RCV" = 3 ] && [ -z "$OUT" ] && printf '%s' "$ERR" | grep -q CONTINUE && ok "W: CONTINUE ⇒ exit 3, nothing printed" || no "W: CONTINUE ⇒ rc $RCV stdout '${OUT:0:60}'"
drv "$DRIVER"
if [ "$RCV" = 0 ] && [ "$(printf '%s' "$OUT" | jq -r '.what')" = "validate findings" ] && grep -q '^wait .* --continue$' "$C/calls.log"; then
  ok "W: the next no-result call resumes the wait with --continue"
else no "W: resume ⇒ rc $RCV, what $(printf '%s' "$OUT" | jq -r '.what' 2>/dev/null)"; fi

# --------------------------------------------------------------------------------------
# B — branches the goldens do not reach
# --------------------------------------------------------------------------------------
echo "B: other terminal branches"
setup_case "$FIX/converged-ready"
drv "$DRIVER" --start drain
drv "$DRIVER" --result '{"findings":[{"id":"r1-1","verdict":"confirmed","finding":"load_config ignores the exit status of jq","auto_fixable":false}]}'
if [ "$(printf '%s' "$OUT" | jq -r '.decision')" = ESCALATED ] && printf '%s' "$OUT" | jq -r '.review_heal_result' | grep -qx '  escalation_cause: findings' \
   && printf '%s' "$OUT" | jq -r '.review_heal_result' | grep -qx '  remaining_issues: 1'; then
  ok "B: confirmed-not-auto-fixable ⇒ ESCALATED findings, remaining 1"
else no "B: needs-human ⇒ $(printf '%s' "$OUT" | jq -c '{do, decision}' 2>/dev/null)"; fi
setup_case "$FIX/fallback-no-review-lens"
printf '%s\n' '{"verdict":"unresolved","selected":["R1"],"countable":["R1"],"advisory":[],"passed":[],"failing":[],"unresolved":["R1"],"checks_passed":null}' > "$C/seq/rules.lines"
drv "$DRIVER" --start drain
blk="$(printf '%s' "$OUT" | jq -r '.review_heal_result' 2>/dev/null)"
if [ "$(printf '%s' "$OUT" | jq -r '.do')" = done ] && printf '%s' "$blk" | grep -qx '  rules_gate: unresolved' \
   && ! printf '%s' "$blk" | grep -q 'termination_reason' && printf '%s' "$blk" | grep -qx '  escalation_cause: other'; then
  ok "B: rules gate unresolved ⇒ ESCALATED other, termination_reason unset, no fallback"
else no "B: rules unresolved ⇒ $(printf '%s' "$OUT" | jq -c '{do, what, decision}' 2>/dev/null)"; fi
setup_case "$FIX/converged-ready"
sed 's#@../_common/meta.json#{"baseRefName":"main","headRefName":"feature/widget-config","isCrossRepository":true}#' "$C/gh.table" > "$C/gh.t" && mv "$C/gh.t" "$C/gh.table"
drv "$DRIVER" --start drain
drv "$DRIVER" --result "$GOOD"
if [ "$(printf '%s' "$OUT" | jq -r '.decision')" = ESCALATED ] && [ "$(printf '%s' "$OUT" | jq -r '.message')" = fork_no_push ] \
   && ! grep -q '"what":"fix worker"' "$C/last.out"; then
  ok "B: a fork PR ⇒ no fix spawn, ESCALATED fork_no_push"
else no "B: fork ⇒ $(printf '%s' "$OUT" | jq -c '{do, what, decision, message}' 2>/dev/null)"; fi
SHA_A=a1b2c3d4e5f60718293a4b5c6d7e8f9012345678; SHA_B=b2c3d4e5f60718293a4b5c6d7e8f901234567890
b_block() { printf '%s' "$OUT" | jq -r '.review_heal_result' 2>/dev/null; }
# the scoped wait elapsed ⇒ ESCALATED, the classifier's line copied field by field
setup_case "$FIX/converged-ready"
echo "ELAPSED sha=$SHA_A required=green review_producing=elapsed pending=claude-review" > "$C/seq/wait.lines"
echo "escalation_cause: check_pending check=claude-review run_id=1002 attempt=1 sha=$SHA_A" > "$C/seq/escalation.lines"
drv "$DRIVER" --start drain
if [ "$(printf '%s' "$OUT" | jq -r '.message')" = check_wait_elapsed ] && b_block | grep -qx '  escalation_cause: check_pending' \
   && b_block | grep -qx '  escalation_check: "claude-review"' && b_block | grep -qx '  escalation_run_id: "1002"' \
   && b_block | grep -qx '  escalation_attempt: 1' && ! b_block | grep -q termination_reason \
   && grep -qx "escalation escalation-cause $PR --sha $SHA_A" "$C/calls.log"; then
  ok "B: the scoped wait ELAPSED ⇒ ESCALATED with the classifier's cause, check, run id and attempt"
else no "B: wait elapsed ⇒ $(printf '%s' "$OUT" | jq -c '{do, decision, message}' 2>/dev/null)"; fi
# a truncated thread read is UNKNOWN
setup_case "$FIX/converged-ready"
sed 's#@../_common/threads-empty.json#{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":true},"nodes":[]}}}}}#' "$C/gh.table" > "$C/gh.t" && mv "$C/gh.t" "$C/gh.table"
drv "$DRIVER" --start drain
[ "$(printf '%s' "$OUT" | jq -r '.message')" = channel_unknown ] && b_block | grep -qx '  escalation_cause: other' \
  && ok "B: reviewThreads hasNextPage ⇒ UNKNOWN ⇒ ESCALATED" || no "B: truncated threads ⇒ $(printf '%s' "$OUT" | jq -c '{do, what, message}' 2>/dev/null)"
# the release re-fold refused ⇒ no push ⇒ ESCALATED other
setup_case "$FIX/converged-ready"
drv "$DRIVER" --start drain; drv "$DRIVER" --result "$GOOD"
drv "$DRIVER" --result '{"pushed":false,"refold_refused":"CHANGELOG.md was hand-edited"}'
[ "$(printf '%s' "$OUT" | jq -r '.message')" = release_refold_refused ] && b_block | grep -qx '  escalation_cause: other' \
  && b_block | grep -qx '  fix_cycles: 0' && grep -q 'CHANGELOG.md was hand-edited' "$C/comments.log" \
  && ok "B: refold_refused ⇒ ESCALATED other, its reason posted, no fix cycle counted" || no "B: refold refused ⇒ $(printf '%s' "$OUT" | jq -c '{do, message}' 2>/dev/null)"
# the sub-floor confirming pass red on the pushed sha ⇒ ESCALATED, the ledger still bumped
setup_case "$FIX/sub-floor-converged-ready"
{ head -n 1 "$FIX/sub-floor-converged-ready/wait.lines"; echo "SETTLED sha=$SHA_B required=red review_producing=settled pending_names=none red_names=ci@1003"; } > "$C/seq/wait.lines"
echo "escalation_cause: check_red check=ci run_id=1003 attempt=1 sha=$SHA_B" > "$C/seq/escalation.lines"
drv "$DRIVER" --start drain; drv "$DRIVER" --result-file "$FIX/sub-floor-converged-ready/report-1.json"
drv "$DRIVER" --result-file "$FIX/sub-floor-converged-ready/report-2.json"
if [ "$(printf '%s' "$OUT" | jq -r '.message')" = confirming_pass_failed ] && b_block | grep -qx '  escalation_cause: check_red' \
   && b_block | grep -qx '  rounds: 1' && ! b_block | grep -q 'termination_reason' && ! b_block | grep -q sub_floor_fixed \
   && grep -q "^wait $PR --sha $SHA_B .*--required-only --names" "$C/calls.log"; then
  ok "B: a red confirming pass ⇒ ESCALATED check_red, never READY, the ledger bumped"
else no "B: red confirming pass ⇒ $(printf '%s' "$OUT" | jq -c '{do, decision, message}' 2>/dev/null)"; fi
# a rules gate `fail` ⇒ a rules_replay finding goes to the fix worker (and the fallback is not earned)
setup_case "$FIX/fallback-no-review-lens"
printf '%s\n' '{"verdict":"fail","selected":["R7"],"countable":["R7"],"advisory":[],"passed":[],"failing":["R7"],"unresolved":[],"checks_passed":"0/1"}' > "$C/seq/rules.lines"
drv "$DRIVER" --start drain
[ "$(printf '%s' "$OUT" | jq -r '.what')" = "fix worker" ] && [ "$(printf '%s' "$OUT" | jq -r '.findings[0].source')" = rules_replay ] \
  && [ "$(printf '%s' "$OUT" | jq -r '.findings[0].severity')" = BLOCKING ] \
  && ok "B: rules gate fail ⇒ one BLOCKING rules_replay finding to the fix worker, no fallback" \
  || no "B: rules fail ⇒ $(printf '%s' "$OUT" | jq -c '{do, what}' 2>/dev/null)"

# --------------------------------------------------------------------------------------
# M — mutation controls
# --------------------------------------------------------------------------------------
# build_mutant <name> <anchor> <replacement|-append:<line>> — a driver copy beside symlinks to every other
# scripts/ entry; prints its path; gated: anchor once, non-empty, differs, bash -n
build_mutant() {
  local name="$1" anchor="$2" repl="$3" d c e
  d="$WORK/mut-$name"; mkdir -p "$d"
  for e in "$HERE"/*; do [ "$e" = "$DRIVER" ] || ln -s "$e" "$d/$(basename "$e")"; done
  case "$repl" in
    -append:*) cp "$DRIVER" "$d/review-heal-next-step.sh"; printf '%s\n' "${repl#-append:}" >> "$d/review-heal-next-step.sh" ;;
    *)
      c="$(grep -cF -- "$anchor" "$DRIVER")"
      [ "$c" = 1 ] || { echo "anchor occurs $c time(s)" >&2; return 1; }
      AN="$anchor" RE="$repl" awk 'BEGIN { a = ENVIRON["AN"]; r = ENVIRON["RE"] }
        { i = index($0, a); if (i > 0 && !d) { $0 = substr($0, 1, i - 1) r substr($0, i + length(a)); d = 1 } print }' \
        "$DRIVER" > "$d/review-heal-next-step.sh" ;;
  esac
  [ -s "$d/review-heal-next-step.sh" ] || { echo "mutant empty" >&2; return 1; }
  ! cmp -s "$DRIVER" "$d/review-heal-next-step.sh" || { echo "mutant does not differ" >&2; return 1; }
  bash -n "$d/review-heal-next-step.sh" 2>/dev/null || { echo "mutant fails bash -n" >&2; return 1; }
  echo "$d/review-heal-next-step.sh"
}
if [ "${RH_SKIP_MUTANTS:-0}" != 1 ] && [ -z "${RH_CASES:-}" ]; then
  echo "M: mutation controls"
  # MF (AC8) — the fallback spawn line deleted (the whole physical line replaced by `:`)
  anchor='      rh_emit spawn fallback "$('
  if grep -cF -- "$anchor" "$DRIVER" | grep -qx 1; then
    lineno="$(grep -nF -- "$anchor" "$DRIVER" | cut -d: -f1)"
    d="$WORK/mut-F"; mkdir -p "$d"; for e in "$HERE"/*; do [ "$e" = "$DRIVER" ] || ln -s "$e" "$d/$(basename "$e")"; done
    awk -v n="$lineno" 'NR == n {print "      :"; next} {print}' "$DRIVER" > "$d/review-heal-next-step.sh"
    if [ -s "$d/review-heal-next-step.sh" ] && ! cmp -s "$DRIVER" "$d/review-heal-next-step.sh" && bash -n "$d/review-heal-next-step.sh"; then
      if run_golden fallback-no-review-lens "$d/review-heal-next-step.sh" 0; then no "MF: deleting the fallback spawn left G green"
      else ok "MF: deleting the fallback spawn turns G fallback-no-review-lens red"; fi
    else no "MF: mutant not built"; fi
  else no "MF: anchor not found exactly once"; fi
  # MA — the fallback_already_spawned refusal removed
  if m="$(build_mutant A 'rh_die2 "fallback_already_spawned' ': "fallback_already_spawned')"; then
    # a subshell: the mutant's own ok/no lines must not reach the tally
    if ( leg_a "$m" ) >/dev/null 2>&1; then no "MA: removing the refusal left A green"; else ok "MA: removing the fallback_already_spawned refusal turns A red"; fi
  else no "MA: mutant not built"; fi
  # MI (AC3) — the no-result path re-runs the step that printed the pending instruction
  if m="$(build_mutant I "  if [ -n \"\$pending\" ]; then printf '%s\\n' \"\$pending\"; exit 0; fi" '  if [ -n "$pending" ]; then st_set failed "$(st emit_step)"; fi')"; then
    red=0
    for n in fallback-no-review-lens converged-ready; do
      run_golden "$n" "$m" 1 >/dev/null 2>&1; [ -n "$IDEM_MSG" ] && red=1
    done
    [ "$red" = 1 ] && ok "MI: re-running the step on a no-result call turns I red" || no "MI: re-running the step left I green"
  else no "MI: mutant not built"; fi
  # MP (AC4) — --force on the fix worker's push line
  if m="$(build_mutant P '"git push origin HEAD:" + $ref' '"git push --force origin HEAD:" + $ref')"; then
    : > "$EMITTED.mp"; save="$EMITTED"; EMITTED="$EMITTED.mp"
    run_golden fix-round-pushed "$m" 0 >/dev/null 2>&1
    EMITTED="$save"
    if leg_s "$m" "$EMITTED.mp"; then no "MP: --force on the push left S green"; else ok "MP: --force on the push turns S red"; fi
  else no "MP: mutant not built"; fi
  # MB (AC1) — bound_hit flipped to converged
  if m="$(build_mutant B 'st_set termination_reason bound_hit' 'st_set termination_reason converged')"; then
    if run_golden bound-hit-escalated "$m" 0; then no "MB: flipping bound_hit left G green"; else ok "MB: flipping bound_hit to converged turns G bound-hit-escalated red"; fi
  else no "MB: mutant not built"; fi
  # MS — one unguarded merge-command line appended
  if m="$(build_mutant S - "-append:$(printf '%s %s %s "$PR"' "$MP_A" "$MP_B" "$MP_C")")"; then
    if leg_s "$m" /dev/null; then no "MS: an appended merge line left S green"; else ok "MS: an appended merge line turns S red"; fi
  else no "MS: mutant not built"; fi
fi

echo "PASS: $pass FAIL: $fail"
[ "$fail" -eq 0 ]
