#!/usr/bin/env bash
# test-lane-policy.sh — self-tests for lane-policy.sh (parallel-automate/21 Part B, B1 / B3–B6 / B9):
# the gate catalog and its LANE_GATES.md mirror, wave-set, resolve (the stamped project policy through
# rules-check.sh's stamp valve, plus the wave policy) and decide (the exact lookup a lane's relay hook
# calls). Hermetic: every repo, rule store, policy file, run file and HOME lives under one `mktemp -d`
# root; the real rules-check.sh and automate-helpers.sh run against them; no network, no gh.
#
# Groups:
#   (cat)  catalog — row shape, codes <= 12 chars, the five `allowed` gates exactly, the LANE_GATES.md
#          mirror parsed back to TSV equals `catalog` (with a drifted-copy control), --markdown block
#   (ws)   wave-set — writes + Progress line; refuses a human-only code, an unknown label, a duplicate,
#          a non-run file (exit 1, nothing written)
#   (st)   resolve — a stamped project policy applies; a human-only code in it is dropped and reported;
#          unstamped (rule missing / binds missing / --stamp-state mismatch / absent / untracked file)
#          ⇒ ignored and reported, and decide sends every question to the human; the wave wins per code;
#          no policy at all ⇒ the empty object
#   (dc)   decide — applied answer (the question's own label), unknown header, multi-question call with
#          one human question, label-set mismatch, multiSelect, tampered policy_sha, no / null policy,
#          the drifted v2 resume phrasings vs the coded AUT-RESUME form, input forms, garbage
#   (rp)   replay — the reconstructed S1 v2 fixture: 15 questions / 10 calls, exactly 7 to the human
#   (mut)  MUTATION CONTROL — decide with the policy check removed honours a human-only code ⇒ (dc7) FAILS
#   (ro)   resolve's --stamp-state read executes no check (a marker-writing must-check leaves no marker)

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LP="$SCRIPT_DIR/lane-policy.sh"
RULES_CHECK="$SCRIPT_DIR/rules-check.sh"
MD="$SCRIPT_DIR/../docs/LANE_GATES.md"
FIX="$SCRIPT_DIR/fixtures/lane-policy/s1-v2-replay.json"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "test-lane-policy: jq absent on this host — lane-policy.sh answers human / empty. Skipping."
  echo "RESULT: 0 passed, 0 failed (jq absent, vacuous)"
  exit 0
fi

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT" 2>/dev/null' EXIT
TAB="$(printf '\t')"

# Independent sha256 of a string (the test's own chain, never lane-policy.sh's code path).
_t_sha() {
  if command -v shasum >/dev/null 2>&1; then printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then printf '%s' "$1" | sha256sum | awk '{print $1}'
  else printf '%s' "$1" | openssl dgst -sha256 | awk '{print $NF}'; fi
}

# A git repo with a run file `.supervisor/automate/<rid>.md` (title + ## Progress), printed path.
new_repo() {
  local r; r="$(mktemp -d "$ROOT/repo.XXXXXX")"
  ( cd "$r" && git init -q && git config user.email t@t && git config user.name t \
      && echo init > f && git add f && git commit -qm init ) >/dev/null 2>&1
  mkdir -p "$r/.supervisor/automate"
  printf '# Automate Run: wave1\n\n## Status: running\n\n## Progress\n- 2026-10-10T00:00:00Z started\n\n## Queue\n- [ ] a.md\n' \
    > "$r/.supervisor/automate/wave1.md"
  printf '%s' "$r"
}
RID_FILE=".supervisor/automate/wave1.md"

# The documented lane-policy rule (LANE_GATES.md): must, a check that passes on a valid file, binds.
RULE_OK='{"id":"lane-policy","category":"process","statement":"lane policy answers are human-stamped","enforcement":"must","check":"jq -e .schema_version .agent/lane-policy.json","binds":[".agent/lane-policy.json"],"provenance":{"source":"test"}}'
RULE_NOBINDS='{"id":"lane-policy","category":"process","statement":"lane policy answers are human-stamped","enforcement":"must","check":"jq -e .schema_version .agent/lane-policy.json","provenance":{"source":"test"}}'
RULE_OTHER='{"id":"other-rule","category":"process","statement":"another must rule","enforcement":"must","check":"true","provenance":{"source":"test"}}'

# seed_policy <repo> <answers_json> <rules_json_array> — writes + commits the policy file and rule store.
seed_policy() {
  local r="$1" a="$2" rules="$3"
  mkdir -p "$r/.agent/rules"
  jq -n --argjson a "$a" '{schema_version: 1, answers: $a}' > "$r/.agent/lane-policy.json"
  printf '%s\n' "$rules" > "$r/.agent/rules/process.json"
  ( cd "$r" && git add .agent && git commit -qm "policy + rules" ) >/dev/null 2>&1
}
stamp() { ( cd "$1" && HOME="$2" bash "$RULES_CHECK" --confirm </dev/null >/dev/null 2>&1 ); }
resolve() { ( cd "$1" && HOME="$2" bash "$LP" resolve "$RID_FILE" --root "$1" 2>"$ROOT/resolve.err" </dev/null ); }
# lane_json <resolve_object> <file> — the lane.json shape lane-create writes (policy null when empty).
lane_json() { jq -n --argjson p "$1" '{lane: "L1", policy: (if ($p.answers | length) == 0 then null else $p end)}' > "$2"; }

Q_QUEUE='{"questions":[{"header":"AUT-QUEUE","question":"Process the queue?","multiSelect":false,"options":[{"label":"Process (Recommended)"},{"label":"Stop"}]}]}'

# ============================================================================
echo "== (cat) catalog — the ONE authority, its shape, and the LANE_GATES.md mirror =="
cat_tsv="$(bash "$LP" catalog)"; rc=$?
[ "$rc" -eq 0 ] && [ -n "$cat_tsv" ] && ok "(cat1) catalog exits 0 and prints rows" || no "(cat1) rc=$rc"
bad_shape="$(printf '%s\n' "$cat_tsv" | awk -F'\t' 'NF != 4 || $1 == "" || ($2 != "allowed" && $2 != "human-only") || $3 == "" || $4 == ""')"
[ -z "$bad_shape" ] && ok "(cat2) every row is code<TAB>allowed|human-only<TAB>labels<TAB>purpose" || no "(cat2) bad rows: $bad_shape"
long="$(printf '%s\n' "$cat_tsv" | awk -F'\t' 'length($1) > 12 { print $1 }')"
[ -z "$long" ] && ok "(cat3) no code is longer than 12 characters (the ask tool's header limit)" || no "(cat3) codes over 12 chars: $long"
dups="$(printf '%s\n' "$cat_tsv" | cut -f1 | sort | uniq -d)"
[ -z "$dups" ] && ok "(cat4) codes are unique" || no "(cat4) duplicate codes: $dups"
allowed="$(printf '%s\n' "$cat_tsv" | awk -F'\t' '$2 == "allowed" { print $1 "=" $3 }' | env LC_ALL=C sort)"
want_allowed="$(printf '%s\n' 'AUT-QUEUE=Process|Stop' 'AUT-RESUME=Continue|Start new|Archive' \
  'AUT-SUMMARY=Keep summary|Drop summary' 'LP-SAVE=Save and exit|Refine further|Edit sections|Discard' \
  'SUP-CHILDREN=proceed anyway|investigate|abort' | env LC_ALL=C sort)"
[ "$allowed" = "$want_allowed" ] && ok "(cat5) the allowed gates are EXACTLY the five B1 names, with their exact labels" \
  || no "(cat5) allowed set drifted: [$allowed]"
rec="$(printf '%s\n' "$cat_tsv" | cut -f3 | grep -c 'Recommended')"
[ "$rec" -eq 0 ] && ok "(cat6) no catalog label carries a (Recommended) marker" || no "(cat6) $rec rows carry (Recommended)"

# md_tsv <markdown file> — INDEPENDENT parse of the mirrored table back into catalog TSV.
md_tsv() {
  awk '/<!-- lane-policy catalog: BEGIN/ { f = 1; next } /<!-- lane-policy catalog: END/ { f = 0 } f' "$1" \
    | tail -n +3 | awk '{
        line = $0; sub(/^\| /, "", line); sub(/ \|$/, "", line)
        n = split(line, c, / \| /)
        if (n != 4) { print "BADROW\t" $0; next }
        code = c[1]; gsub(/`/, "", code)
        m = split(c[3], l, / · /); labs = ""
        for (i = 1; i <= m; i++) { x = l[i]; sub(/^`/, "", x); sub(/`$/, "", x); labs = labs (i > 1 ? "|" : "") x }
        printf "%s\t%s\t%s\t%s\n", code, c[2], labs, c[4]
      }'
}
if [ -r "$MD" ]; then
  md_rows="$(md_tsv "$MD")"
  [ -n "$md_rows" ] && [ "$md_rows" = "$cat_tsv" ] \
    && ok "(cat7) LANE_GATES.md's table, parsed back to TSV, equals lane-policy.sh catalog (no drift)" \
    || no "(cat7) LANE_GATES.md drifted from the catalog — regenerate with 'lane-policy.sh catalog --markdown'. diff: $(diff <(printf '%s\n' "$cat_tsv") <(printf '%s\n' "$md_rows") | head -5)"
  # Control: the comparison is not vacuous — a one-label edit in a copy is detected.
  sed 's/`Process` · `Stop`/`Process` · `Halt`/' "$MD" > "$ROOT/drift.md"
  if ! cmp -s "$MD" "$ROOT/drift.md" && [ "$(md_tsv "$ROOT/drift.md")" != "$cat_tsv" ]; then
    ok "(cat8) control: a drifted copy of LANE_GATES.md (one label changed) is detected"
  else
    no "(cat8) control broken: the drift edit did not land or was not detected — (cat7) may be vacuous"
  fi
  block="$(awk '/<!-- lane-policy catalog: BEGIN/ { f = 1; next } /<!-- lane-policy catalog: END/ { f = 0 } f' "$MD")"
  [ "$block" = "$(bash "$LP" catalog --markdown)" ] \
    && ok "(cat9) the embedded block is byte-identical to 'catalog --markdown'" || no "(cat9) embedded block differs from --markdown output"
else
  no "(cat7) LANE_GATES.md not readable at $MD"
fi
bash "$LP" catalog --bogus >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "(cat10) an unknown catalog argument is a usage error (exit 2)" || no "(cat10) rc=$rc"

# ============================================================================
echo "== (ws) wave-set — the per-wave owner answer set =="
RW="$(new_repo)"
before="$(cat "$RW/$RID_FILE")"
out="$( cd "$RW" && bash "$LP" wave-set "$RID_FILE" 'AUT-QUEUE=Process' 'AUT-SUMMARY=Drop summary' 2>&1 )"; rc=$?
WPF="$RW/.supervisor/automate/wave1.wave-policy.json"
[ "$rc" -eq 0 ] && [ -f "$WPF" ] && ok "(ws1) wave-set exits 0 and writes <run_id>.wave-policy.json" || no "(ws1) rc=$rc out=$out"
jq -e '.schema_version == 1 and .run_id == "wave1" and .answers == {"AUT-QUEUE":"Process","AUT-SUMMARY":"Drop summary"}
       and (.set_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$"))' "$WPF" >/dev/null 2>&1 \
  && ok "(ws2) the file is {schema_version:1, run_id, answers, set_at}" || no "(ws2) $(cat "$WPF" 2>/dev/null)"
grep -qxF -- '- wave policy: AUT-QUEUE=Process, AUT-SUMMARY=Drop summary' "$RW/$RID_FILE" \
  && ok "(ws3) one parent ## Progress line 'wave policy: <code>=<label>, …'" || no "(ws3) run file: $(cat "$RW/$RID_FILE")"
snap_rf="$(cat "$RW/$RID_FILE")"; snap_wp="$(cat "$WPF")"
ws_refused() {  # ws_refused <label> <args…> — exit 1, run file + wave file unchanged
  local label="$1"; shift
  local o r
  o="$( cd "$RW" && bash "$LP" wave-set "$RID_FILE" "$@" 2>&1 )"; r=$?
  if [ "$r" -eq 1 ] && [ "$(cat "$RW/$RID_FILE")" = "$snap_rf" ] && [ "$(cat "$WPF")" = "$snap_wp" ] \
     && [ -z "$(find "$RW/.supervisor/automate" -name 'wave1.wave-policy.json.*' 2>/dev/null)" ]; then
    ok "$label (exit 1, nothing written: $(printf '%s' "$o" | head -1 | cut -c1-90))"
  else
    no "$label rc=$r out=$o"
  fi
}
ws_refused "(ws4) a human-only code is refused" 'SUP-OVERLAP=proceed-anyway'
ws_refused "(ws5) a label not in the catalog is refused" 'AUT-QUEUE=Go'
ws_refused "(ws6) an unknown code is refused" 'NOPE=Process'
ws_refused "(ws7) one bad pair refuses the WHOLE call" 'AUT-QUEUE=Stop' 'LP-SAVE=Ship it'
ws_refused "(ws8) a code given twice with different labels is refused" 'AUT-QUEUE=Process' 'AUT-QUEUE=Stop'
ws_refused "(ws9) a pair without '=' is refused" 'AUT-QUEUE'
ws_refused "(ws10) a '(Recommended)'-marked label is not a catalog label" 'AUT-QUEUE=Process (Recommended)'
printf 'not a run file\n' > "$RW/.supervisor/automate/notrun.md"
o="$( cd "$RW" && bash "$LP" wave-set .supervisor/automate/notrun.md 'AUT-QUEUE=Process' 2>&1 )"; rc=$?
[ "$rc" -eq 1 ] && [ ! -e "$RW/.supervisor/automate/notrun.wave-policy.json" ] \
  && [ "$(cat "$RW/.supervisor/automate/notrun.md")" = "not a run file" ] \
  && ok "(ws11) a parent file with no '# Automate Run:' title is refused, nothing written" || no "(ws11) rc=$rc out=$o"
[ "$before" != "$snap_rf" ] && ok "(ws12) premise: (ws4)-(ws10) compared against a run file ws1 really changed" || no "(ws12) premise broken"

# ============================================================================
echo "== (st) resolve — stamped project policy, unstamped variants, wave precedence =="
EMPTY_POL='{"policy_sha":null,"sources":[],"answers":{}}'
# (st0) no policy anywhere ⇒ the empty object (B10: lane-create writes policy null).
R0="$(new_repo)"; H0="$ROOT/h0"; mkdir -p "$H0"
out="$(resolve "$R0" "$H0")"; rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "$EMPTY_POL" ] && [ ! -s "$ROOT/resolve.err" ] \
  && ok "(st0) no project file and no wave file ⇒ $EMPTY_POL, exit 0, nothing reported" || no "(st0) rc=$rc out=$out err=$(cat "$ROOT/resolve.err")"

# (st1) stamped project policy applies.
R1="$(new_repo)"; H1="$ROOT/h1"; mkdir -p "$H1"
seed_policy "$R1" '{"AUT-QUEUE":"Process","LP-SAVE":"Save and exit","SUP-OVERLAP":"proceed-anyway","NOPE":"x","AUT-RESUME":"Restart"}' "[$RULE_OK, $RULE_OTHER]"
stamp "$R1" "$H1"
st_state="$( cd "$R1" && HOME="$H1" bash "$RULES_CHECK" --stamp-state </dev/null 2>/dev/null )"
[ "$st_state" = "stamp${TAB}match" ] && ok "(st1a) premise: the fixture repo is stamped (--stamp-state match)" || no "(st1a) premise: $st_state"
out1="$(resolve "$R1" "$H1")"; err1="$(cat "$ROOT/resolve.err")"
want_ans='{"AUT-QUEUE":"Process","LP-SAVE":"Save and exit"}'
[ "$(jq -cS '.answers' <<<"$out1")" = "$want_ans" ] \
  && ok "(st1b) a stamped project policy is applied: only its allowed, validly-labelled codes are kept" || no "(st1b) out=$out1"
[ "$(jq -r '.policy_sha' <<<"$out1")" = "$(_t_sha "$want_ans")" ] \
  && ok "(st1c) policy_sha = sha256 of the compact key-sorted answers (independent recomputation)" || no "(st1c) sha=$(jq -r .policy_sha <<<"$out1")"
[ "$(jq -c '.sources' <<<"$out1")" = '[{"kind":"project","path":".agent/lane-policy.json"}]' ] \
  && ok "(st1d) sources names the project policy" || no "(st1d) $(jq -c .sources <<<"$out1")"
grep -qF 'lane-policy: dropped project SUP-OVERLAP — human-only' <<<"$err1" \
  && ok "(st2a) a human-only code in the stamped policy is IGNORED and REPORTED" || no "(st2a) err=$err1"
grep -qF 'lane-policy: dropped project NOPE — not a catalog code' <<<"$err1" \
  && grep -qF 'lane-policy: dropped project AUT-RESUME=Restart — not one of its catalog labels' <<<"$err1" \
  && ok "(st2b) an unknown code and an unknown label are dropped and reported too" || no "(st2b) err=$err1"
lane_json "$out1" "$ROOT/lane1.json"
d="$(bash "$LP" decide "$Q_QUEUE" --policy-json "$ROOT/lane1.json" 2>/dev/null)"
[ "$d" = '{"0":"Process (Recommended)"}' ] \
  && ok "(st3) decide applies the stamped answer with the question's OWN label ('Process (Recommended)')" || no "(st3) decide=$d"

# unstamped(<label>, <repo>, <home>, <reason-substring>) — ignored + reported, empty answers, decide ⇒ human.
unstamped() {
  local label="$1" r="$2" h="$3" why="$4" o e dd
  o="$(resolve "$r" "$h")"; e="$(cat "$ROOT/resolve.err")"
  lane_json "$o" "$ROOT/lane-u.json"
  dd="$(bash "$LP" decide "$Q_QUEUE" --policy-json "$ROOT/lane-u.json" 2>/dev/null)"
  if [ "$o" = "$EMPTY_POL" ] && grep -qF "lane-policy: project policy ignored — " <<<"$e" && grep -qF -- "$why" <<<"$e" \
     && [ "$dd" = "human" ] && [ "$(jq -c '.policy' "$ROOT/lane-u.json")" = "null" ]; then
    ok "$label ⇒ ignored + reported ('$why'), lane.json policy null, decide ⇒ human"
  else
    no "$label out=$o err=$e decide=$dd"
  fi
}
# (st4a) rule missing — the policy file is tracked and the store holds only another rule.
R4="$(new_repo)"; H4="$ROOT/h4"; mkdir -p "$H4"
seed_policy "$R4" '{"AUT-QUEUE":"Process"}' "[$RULE_OTHER]"; stamp "$R4" "$H4"
unstamped "(st4a) rule lane-policy missing" "$R4" "$H4" "no selected must-rule with id lane-policy"
# (st4b) binds missing — stamped, but the rule does not bind the policy file.
R5="$(new_repo)"; H5="$ROOT/h5"; mkdir -p "$H5"
seed_policy "$R5" '{"AUT-QUEUE":"Process"}' "[$RULE_NOBINDS]"; stamp "$R5" "$H5"
unstamped "(st4b) binds missing" "$R5" "$H5" "does not bind .agent/lane-policy.json"
# (st4c) mismatch — the policy file is edited after the stamp.
R6="$(new_repo)"; H6="$ROOT/h6"; mkdir -p "$H6"
seed_policy "$R6" '{"AUT-QUEUE":"Process"}' "[$RULE_OK]"; stamp "$R6" "$H6"
pre6="$(resolve "$R6" "$H6")"
[ "$(jq -c '.answers' <<<"$pre6")" = '{"AUT-QUEUE":"Process"}' ] && ok "(st4c-premise) before the edit the policy IS applied" || no "(st4c-premise) $pre6"
jq '.answers["AUT-QUEUE"] = "Stop"' "$R6/.agent/lane-policy.json" > "$ROOT/p6" && mv "$ROOT/p6" "$R6/.agent/lane-policy.json"
unstamped "(st4c) --stamp-state mismatch (policy edited after the stamp)" "$R6" "$H6" "rules stamp mismatch"
# (st4d) absent — the same stamped repo under a HOME that holds no stamp.
H7="$ROOT/h7"; mkdir -p "$H7"
( cd "$R6" && git checkout -q -- .agent/lane-policy.json )
unstamped "(st4d) --stamp-state absent (no stamp on this machine)" "$R6" "$H7" "rules stamp absent"
# (st4e) untracked policy file — its content is not covered by the stamp hash.
R8="$(new_repo)"; H8="$ROOT/h8"; mkdir -p "$H8"
seed_policy "$R8" '{"AUT-QUEUE":"Process"}' "[$RULE_OK]"
( cd "$R8" && git rm -q --cached .agent/lane-policy.json && git commit -qm untrack ) >/dev/null 2>&1
stamp "$R8" "$H8"
unstamped "(st4e) policy file not git-tracked" "$R8" "$H8" "not git-tracked"
# (st4f) the rule edited after the stamp (the check text changes) ⇒ mismatch.
R9="$(new_repo)"; H9="$ROOT/h9"; mkdir -p "$H9"
seed_policy "$R9" '{"AUT-QUEUE":"Process"}' "[$RULE_OK]"; stamp "$R9" "$H9"
jq '.[0].check = "jq -e .answers .agent/lane-policy.json"' "$R9/.agent/rules/process.json" > "$ROOT/r9" && mv "$ROOT/r9" "$R9/.agent/rules/process.json"
unstamped "(st4f) the lane-policy rule edited after the stamp" "$R9" "$H9" "rules stamp mismatch"
# (st4g) stamped, but the file's SHAPE is wrong (answers not an object) — the rule's check still passes.
R10="$(new_repo)"; H10="$ROOT/h10"; mkdir -p "$H10"
seed_policy "$R10" '{}' "[$RULE_OK]"
printf '{"schema_version":1,"answers":["AUT-QUEUE=Process"]}\n' > "$R10/.agent/lane-policy.json"
( cd "$R10" && git commit -qam "malformed policy" ) >/dev/null 2>&1; stamp "$R10" "$H10"
st10="$( cd "$R10" && HOME="$H10" bash "$RULES_CHECK" --stamp-state </dev/null 2>/dev/null )"
[ "$st10" = "stamp${TAB}match" ] && ok "(st4g-premise) the malformed file IS stamped (the rule's check passed)" || no "(st4g-premise) $st10"
unstamped "(st4g) a stamped policy whose answers are not an object" "$R10" "$H10" "is malformed"

# (st5) the wave wins per code over the project, and adds its own codes.
( cd "$R1" && bash "$LP" wave-set "$RID_FILE" 'AUT-QUEUE=Stop' 'SUP-CHILDREN=abort' >/dev/null 2>&1 )
out5="$(resolve "$R1" "$H1")"
[ "$(jq -cS '.answers' <<<"$out5")" = '{"AUT-QUEUE":"Stop","LP-SAVE":"Save and exit","SUP-CHILDREN":"abort"}' ] \
  && [ "$(jq -r '[.sources[].kind] | join(",")' <<<"$out5")" = "project,wave" ] \
  && ok "(st5) project + wave merge, the wave wins per code (AUT-QUEUE=Stop), both sources listed" || no "(st5) $out5"
# (st6) a malformed wave file (another run's id) is ignored and reported; the project policy still applies.
jq '.run_id = "other"' "$R1/.supervisor/automate/wave1.wave-policy.json" > "$ROOT/w6" && mv "$ROOT/w6" "$R1/.supervisor/automate/wave1.wave-policy.json"
out6="$(resolve "$R1" "$H1")"
[ "$(jq -cS '.answers' <<<"$out6")" = "$want_ans" ] && grep -qF 'lane-policy: wave policy ignored' "$ROOT/resolve.err" \
  && ok "(st6) a wave file naming another run is ignored and reported" || no "(st6) $out6 err=$(cat "$ROOT/resolve.err")"
# (st7) usage errors exit 2 and print nothing on stdout (lane-create then writes policy null).
u1="$(bash "$LP" resolve 2>/dev/null)"; r1=$?
u2="$(bash "$LP" resolve "$RID_FILE" --bogus 2>/dev/null)"; r2=$?
u3="$(bash "$LP" resolve "$RID_FILE" --root 2>/dev/null)"; r3=$?
[ "$r1$r2$r3" = "222" ] && [ -z "$u1$u2$u3" ] && ok "(st7) resolve usage errors (no run file / unknown flag / --root without a value) exit 2, empty stdout" \
  || no "(st7) rcs=$r1$r2$r3 out=[$u1$u2$u3]"

# (nj) no jq on PATH: resolve ⇒ the empty policy, decide ⇒ human, wave-set refuses with nothing written.
NJ="$ROOT/nojq-bin"; mkdir -p "$NJ"
for t in dirname git; do ln -s "$(command -v "$t")" "$NJ/$t"; done
BASH_BIN="$(command -v bash)"
nj1="$( cd "$R0" && PATH="$NJ" "$BASH_BIN" "$LP" resolve "$RID_FILE" --root "$R0" 2>/dev/null )"; nr1=$?
# lane1.json is (st3)'s policy, which DOES answer Q_QUEUE when jq is present — so `human` here is the no-jq path.
nj2="$( PATH="$NJ" "$BASH_BIN" "$LP" decide "$Q_QUEUE" --policy-json "$ROOT/lane1.json" 2>/dev/null )"; nr2=$?
nj3="$( cd "$R0" && PATH="$NJ" "$BASH_BIN" "$LP" wave-set "$RID_FILE" 'AUT-QUEUE=Process' 2>/dev/null )"; nr3=$?
if [ "$nj1" = "$EMPTY_POL" ] && [ "$nr1" -eq 0 ] && [ "$nj2" = "human" ] && [ "$nr2" -eq 0 ] && [ "$nr3" -eq 1 ] \
   && [ ! -e "$R0/.supervisor/automate/wave1.wave-policy.json" ]; then
  ok "(nj) no jq ⇒ resolve prints the empty policy (exit 0), decide prints human (exit 0), wave-set refuses (exit 1, nothing written)"
else
  no "(nj) resolve=[$nj1] rc=$nr1 decide=[$nj2] rc=$nr2 wave-set rc=$nr3"
fi

# ============================================================================
echo "== (dc) decide — the exact lookup =="
# A hand-built policy (valid sha) covering every allowed code, as a bare resolve object.
POL_ANS='{"AUT-QUEUE":"Process","AUT-RESUME":"Start new","AUT-SUMMARY":"Drop summary","LP-SAVE":"Save and exit","SUP-CHILDREN":"proceed anyway"}'
POL_CANON="$(jq -cS . <<<"$POL_ANS")"
jq -n --argjson a "$POL_CANON" --arg s "$(_t_sha "$POL_CANON")" '{policy_sha: $s, sources: [], answers: $a}' > "$ROOT/pol.json"
dec() { bash "$LP" decide "$1" --policy-json "${2:-$ROOT/pol.json}" 2>/dev/null; }
q1() { jq -cn --arg h "$1" --argjson o "$2" '{questions: [{header: $h, question: "q", multiSelect: false, options: ($o | map({label: .}))}]}'; }
[ "$(dec "$(q1 AUT-QUEUE '["Process","Stop"]')")" = '{"0":"Process"}' ] && ok "(dc1) an allowed coded question with exact labels ⇒ the policy answer" || no "(dc1)"
[ "$(dec "$(q1 Queue '["Process","Stop"]')")" = "human" ] && ok "(dc2) an unknown header ⇒ human" || no "(dc2)"
multi="$(jq -cn '{questions: [
  {header: "AUT-QUEUE", question: "a", options: [{label: "Process"}, {label: "Stop"}]},
  {header: "Fix now?", question: "b", options: [{label: "Fix now on this PR"}, {label: "Drop"}]}]}')"
[ "$(dec "$multi")" = "human" ] && ok "(dc3) a multi-question call with ONE human question ⇒ human (never a partial answer)" || no "(dc3)"
multi_ok="$(jq -cn '{questions: [
  {header: "AUT-SUMMARY", question: "a", options: [{label: "Keep summary"}, {label: "Drop summary (Recommended)"}]},
  {header: "AUT-SUMMARY", question: "b", options: [{label: "Drop summary"}, {label: "Keep summary"}]}]}')"
[ "$(dec "$multi_ok")" = '{"0":"Drop summary (Recommended)","1":"Drop summary"}' ] \
  && ok "(dc4) a multi-question call of routine questions ⇒ one answer per index, each the question's own label" || no "(dc4) $(dec "$multi_ok")"
[ "$(dec "$(q1 AUT-QUEUE '["Process"]')")" = "human" ] && ok "(dc5a) a missing option (label set differs) ⇒ human" || no "(dc5a)"
[ "$(dec "$(q1 AUT-QUEUE '["Process","Stop","Later"]')")" = "human" ] && ok "(dc5b) an extra option ⇒ human" || no "(dc5b)"
[ "$(dec "$(q1 AUT-QUEUE '["Process","Process (Recommended)","Stop"]')")" = "human" ] && ok "(dc5c) a duplicated label after stripping ⇒ human" || no "(dc5c)"
ms="$(jq -cn '{questions: [{header: "AUT-QUEUE", question: "q", multiSelect: true, options: [{label: "Process"}, {label: "Stop"}]}]}')"
[ "$(dec "$ms")" = "human" ] && ok "(dc6) a multiSelect question ⇒ human" || no "(dc6)"
# (dc7) a human-only code in the policy AND as the header ⇒ human. This is the case (mut) breaks.
HO_CANON='{"SUP-OVERLAP":"proceed-anyway"}'
jq -n --argjson a "$HO_CANON" --arg s "$(_t_sha "$HO_CANON")" '{policy_sha: $s, sources: [], answers: $a}' > "$ROOT/pol-ho.json"
Q_HO="$(q1 SUP-OVERLAP '["proceed-anyway","revise-scope","abort"]')"
dc7_check() { [ "$(bash "$1" decide "$Q_HO" --policy-json "$ROOT/pol-ho.json" 2>/dev/null)" = "human" ]; }
dc7_check "$LP" && ok "(dc7) a human-only code is NEVER honoured, even when the policy names it and the header carries it" \
  || no "(dc7) SECURITY REGRESSION: decide answered a human-only gate from policy"
jq '.answers["AUT-QUEUE"] = "Stop"' "$ROOT/pol.json" > "$ROOT/pol-tamper.json"
[ "$(dec "$(q1 AUT-QUEUE '["Process","Stop"]')" "$ROOT/pol-tamper.json")" = "human" ] \
  && ok "(dc8) answers edited without their policy_sha ⇒ human" || no "(dc8)"
[ "$(bash "$LP" decide "$(q1 AUT-QUEUE '["Process","Stop"]')" 2>/dev/null)" = "human" ] && ok "(dc9a) no --policy-json ⇒ human" || no "(dc9a)"
printf '{"lane":"L1","policy":null}\n' > "$ROOT/lane-null.json"
[ "$(dec "$(q1 AUT-QUEUE '["Process","Stop"]')" "$ROOT/lane-null.json")" = "human" ] && ok "(dc9b) lane.json policy null ⇒ human" || no "(dc9b)"
# (dc10) the two drifted v2 resume phrasings map to human; the coded AUT-RESUME form maps to the answer.
v2a="$(q1 'Resume' '["Continue","Start new (Recommended)","Archive"]')"
v2b="$(q1 'Resume?' '["Continue","Start new run (Recommended)","Archive"]')"
coded="$(q1 'AUT-RESUME' '["Continue","Start new (Recommended)","Archive"]')"
[ "$(dec "$v2a")" = "human" ] && [ "$(dec "$v2b")" = "human" ] \
  && ok "(dc10a) the drifted v2 phrasings ('Resume'/'Start new (Recommended)', 'Resume?'/'Start new run (Recommended)') ⇒ human (no code)" || no "(dc10a)"
[ "$(dec "$coded")" = '{"0":"Start new (Recommended)"}' ] && ok "(dc10b) the coded AUT-RESUME form ⇒ the policy answer" || no "(dc10b) $(dec "$coded")"
# (dc11) input forms: a question FILE ({id, asked_at, questions}), a bare array, the hook payload shape.
jq -n --argjson q "$(q1 AUT-QUEUE '["Process","Stop"]')" '{id: "toolu_1", asked_at: "2026-10-10T00:00:00Z", questions: $q.questions}' > "$ROOT/qfile.json"
hook="$(jq -cn --argjson q "$(q1 AUT-QUEUE '["Process","Stop"]')" '{tool_use_id: "toolu_1", tool_input: {questions: $q.questions}}')"
arr="$(jq -c '.questions' <<<"$(q1 AUT-QUEUE '["Process","Stop"]')")"
[ "$(dec "$ROOT/qfile.json")" = '{"0":"Process"}' ] && [ "$(dec "$hook")" = '{"0":"Process"}' ] && [ "$(dec "$arr")" = '{"0":"Process"}' ] \
  && ok "(dc11) question file, hook payload and bare array forms all decide alike" || no "(dc11)"
d12="$(bash "$LP" decide 'not json {' --policy-json "$ROOT/pol.json" 2>/dev/null)"; rc=$?
[ "$d12" = "human" ] && [ "$rc" -eq 0 ] && ok "(dc12) garbage question JSON ⇒ human, exit 0" || no "(dc12) $d12 rc=$rc"
printf '[]' > "$ROOT/empty-q.json"
[ "$(dec "$ROOT/empty-q.json")" = "human" ] && ok "(dc13) an empty question list ⇒ human" || no "(dc13)"
d14="$(bash "$LP" decide 2>/dev/null)"; rc=$?
[ "$d14" = "human" ] && [ "$rc" -eq 2 ] && ok "(dc14) a usage error still prints human (exit 2)" || no "(dc14) $d14 rc=$rc"

# ============================================================================
echo "== (rp) replay — the reconstructed S1 v2 questions, policy covering the routine codes =="
if [ -r "$FIX" ]; then
  RP_CANON="$(jq -cS '.policy_answers' "$FIX")"
  jq -n --argjson a "$RP_CANON" --arg s "$(_t_sha "$RP_CANON")" '{lane: "v2", policy: {policy_sha: $s, sources: [], answers: $a}}' > "$ROOT/rp-lane.json"
  n_calls="$(jq '.calls | length' "$FIX")"; n_q="$(jq '[.calls[].questions | length] | add' "$FIX")"
  human_q=0; routine_q=0; wrong=""
  i=0
  while [ "$i" -lt "$n_calls" ]; do
    call="$(jq -c ".calls[$i]" "$FIX")"
    kind="$(jq -r '.kind' <<<"$call")"; nq="$(jq '.questions | length' <<<"$call")"
    d="$(dec "$call" "$ROOT/rp-lane.json")"
    if [ "$d" = "human" ]; then
      human_q=$((human_q + nq)); [ "$kind" = "human" ] || wrong="$wrong call$i(routine→human)"
    else
      routine_q=$((routine_q + nq)); [ "$kind" = "routine" ] || wrong="$wrong call$i(human→answered)"
      # every answer is one of that question's own labels (what _lanes_validate_answers requires)
      jq -e --argjson d "$d" '[.questions | to_entries[] | . as $e | ($d[($e.key | tostring)]) as $a
          | any($e.value.options[]; .label == $a)] | all' <<<"$call" >/dev/null 2>&1 || wrong="$wrong call$i(label)"
    fi
    i=$((i + 1))
  done
  [ "$n_calls" -eq "$(jq '.expect.calls' "$FIX")" ] && [ "$n_q" -eq "$(jq '.expect.questions' "$FIX")" ] \
    && ok "(rp1) premise: the fixture holds $n_q questions in $n_calls calls" || no "(rp1) premise: $n_q questions / $n_calls calls"
  [ "$human_q" -eq 7 ] && [ "$routine_q" -eq 8 ] && [ -z "$wrong" ] \
    && ok "(rp2) exactly 7 questions reach the human; the 8 routine ones are answered, each with its own label" \
    || no "(rp2) human=$human_q routine=$routine_q misrouted:$wrong"
  # Control: with NO policy every one of the 15 goes to the human (B10's unchanged path).
  all_h=0; i=0
  while [ "$i" -lt "$n_calls" ]; do
    [ "$(dec "$(jq -c ".calls[$i]" "$FIX")" "$ROOT/lane-null.json")" = "human" ] && all_h=$((all_h + $(jq ".calls[$i].questions | length" "$FIX")))
    i=$((i + 1))
  done
  [ "$all_h" -eq "$n_q" ] && ok "(rp3) control: with policy null all $n_q questions go to the human" || no "(rp3) only $all_h of $n_q"
else
  no "(rp) fixture not readable: $FIX"
fi

# ============================================================================
echo "== (mut) MUTATION CONTROL — decide honouring a human-only code must make (dc7) FAIL =="
MUT="$ROOT/lane-policy.mut.sh"
sed '/THE POLICY CHECK (B9 mutation control)/s/\$row\.policy != "allowed"/false/' "$LP" > "$MUT"
if [ -s "$MUT" ] && ! cmp -s "$LP" "$MUT" && bash -n "$MUT" 2>/dev/null \
   && grep -qF 'elif false then null                     # THE POLICY CHECK' "$MUT"; then
  ok "(mut0) the mutant is valid: non-empty, differs from the original, passes bash -n, the hunk landed"
  if dc7_check "$MUT"; then
    no "(mut1) REFUTED: with the policy check removed decide STILL answered human — (dc7) is vacuous"
  else
    ok "(mut1) CONFIRMED: with the policy check removed, decide answers a human-only gate from policy and (dc7) FAILS — the check is load-bearing"
  fi
else
  no "(mut0) the mutation did not land cleanly (empty / identical / bash -n failed / marker missing)"
fi

# ============================================================================
echo "== (ro) resolve's stamp read executes no check =="
RR="$(new_repo)"; HR="$ROOT/hr"; mkdir -p "$HR"
MARK="$ROOT/ro_marker_$$"
RULE_MARK="$(jq -cn --arg c "touch $MARK" '{id: "zz-marker", category: "process", statement: "writes a marker", enforcement: "must", check: $c, provenance: {source: "test"}}')"
seed_policy "$RR" '{"AUT-QUEUE":"Process"}' "[$RULE_OK, $RULE_MARK]"
stamp "$RR" "$HR"
[ -e "$MARK" ] && ok "(ro0) positive control: the marker-writing must-check DOES run under --confirm" || no "(ro0) control broken — (ro1) would be vacuous"
rm -f "$MARK"
outr="$(resolve "$RR" "$HR")"
[ ! -e "$MARK" ] && [ "$(jq -c '.answers' <<<"$outr")" = '{"AUT-QUEUE":"Process"}' ] \
  && ok "(ro1) resolve read the stamp (match ⇒ policy applied) and executed NO check (no marker)" || no "(ro1) marker=$([ -e "$MARK" ] && echo PRESENT || echo absent) out=$outr"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
