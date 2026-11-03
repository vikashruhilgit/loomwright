#!/usr/bin/env bash
# test-lane-policy.sh — self-tests for lane-policy.sh (parallel-automate/21 Part B, B1 / B3–B6 / B9):
# the gate catalog and its LANE_GATES.md mirror, wave-set, resolve (the stamped project policy through
# rules-check.sh's stamp valve, plus the wave policy) and decide (the exact lookup a lane's relay hook
# calls). Hermetic: every repo, rule store, policy file, run file and HOME lives under one `mktemp -d`
# root; the real rules-check.sh and automate-helpers.sh run against them; no network, no gh.
#
# Groups:
#   (cat)  catalog — row shape over the three tiers (allowed | auto | human-only), the `!` auto-label
#          marker (exactly one per auto row, none elsewhere), codes <= 12 chars, the `allowed` and the
#          `auto` gates as two exact closed sets, the LANE_GATES.md mirror parsed back to TSV equals
#          `catalog` (with a drifted-copy control), --markdown block
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
#   (aw)   AUT-WAIVE (the validation-unrun waiver) is human-only and decide answers human under a policy
#          naming it; MUTATION CONTROL — the row flipped to `allowed` ⇒ (aw1) FAILS
#   (ro)   resolve's --stamp-state read executes no check (a marker-writing must-check leaves no marker)
#   (op)   optional (`?`) labels — LP-SAVE's last-attempt core ask gets the policy answer, any other subset
#          is human; MUTATION CONTROL — the core match removed ⇒ (op1) FAILS
#   (gh)   check-gate-headers.sh — clean on the real tree; one mutation per rule G1–G5 fires; fail CLOSED
#   (pa)   policy answerability (D1, _lp_policy_answerable) — the base-`allowed` auto codes (AUT-QUEUE,
#          AUT-RESUME, LP-SAVE) stay answered by wave-set / resolve / decide; LP-SAVE-NOTE is refused by
#          all three; MUTATION CONTROLS — _LP_POLICY_EXEMPT emptied, the helper narrowed to `allowed`
#   (ga)   gate-auto.sh — the auto tier answers each auto code; each escalation trigger (off from every
#          source, not_auto, label, destructive, severity, high_risk) asks; errors ask; record / list;
#          MUTATION CONTROLS — one per trigger line, each gated on landed + bash -n

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
# A phase session exports LOOMWRIGHT_PHASE_DIR; gate-auto.sh resolves a run file from it, so a test run
# inside one would append records to the LIVE run file. Every run file here is a scratch one.
unset LOOMWRIGHT_PHASE_DIR
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
bad_shape="$(printf '%s\n' "$cat_tsv" | awk -F'\t' 'NF != 4 || $1 == "" || ($2 != "allowed" && $2 != "auto" && $2 != "human-only") || $3 == "" || $4 == ""')"
[ -z "$bad_shape" ] && ok "(cat2) every row is code<TAB>allowed|auto|human-only<TAB>labels<TAB>purpose" || no "(cat2) bad rows: $bad_shape"
# (cat2b) the `!` auto-label marker: exactly one per `auto` row, none on any other row.
bad_bang="$(printf '%s\n' "$cat_tsv" | awk -F'\t' '{ n = 0; m = split($3, l, "|"); for (i = 1; i <= m; i++) if (l[i] ~ /!$/) n++
  if (($2 == "auto" && n != 1) || ($2 != "auto" && n != 0)) print $1 }')"
[ -z "$bad_bang" ] && ok "(cat2b) every auto row carries exactly one ! label and no other row carries any" || no "(cat2b) rows: $bad_bang"
long="$(printf '%s\n' "$cat_tsv" | awk -F'\t' 'length($1) > 12 { print $1 }')"
[ -z "$long" ] && ok "(cat3) no code is longer than 12 characters (the ask tool's header limit)" || no "(cat3) codes over 12 chars: $long"
dups="$(printf '%s\n' "$cat_tsv" | cut -f1 | sort | uniq -d)"
[ -z "$dups" ] && ok "(cat4) codes are unique" || no "(cat4) duplicate codes: $dups"
allowed="$(printf '%s\n' "$cat_tsv" | awk -F'\t' '$2 == "allowed" { print $1 "=" $3 }' | env LC_ALL=C sort)"
want_allowed="$(printf '%s\n' 'AUT-SUMMARY=Keep summary|Drop summary' \
  'SUP-CHILDREN=proceed anyway|investigate|abort' | env LC_ALL=C sort)"
auto="$(printf '%s\n' "$cat_tsv" | awk -F'\t' '$2 == "auto" { print $1 "=" $3 }' | env LC_ALL=C sort)"
want_auto="$(printf '%s\n' 'AUT-QUEUE=Process!|Stop' 'AUT-RESUME=Continue!|Start new|Archive' \
  'LP-SAVE=Save and exit!|Refine further?|Edit sections?|Discard' \
  'LP-SAVE-NOTE=Save and exit!|Refine further?|Edit sections?|Discard' | env LC_ALL=C sort)"
[ "$allowed" = "$want_allowed" ] && [ "$auto" = "$want_auto" ] \
  && ok "(cat5) the allowed gates and the auto gates are EXACTLY their two closed sets, with their exact labels and ! labels" \
  || no "(cat5) tier sets drifted: allowed=[$allowed] auto=[$auto]"
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
  sed 's/`Process!` · `Stop`/`Process!` · `Halt`/' "$MD" > "$ROOT/drift.md"
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
sed '/THE POLICY CHECK (B9 mutation control)/s/(answerable(\$h; \$row) | not)/false/' "$LP" > "$MUT"
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
echo "== (aw) AUT-WAIVE — the validation-unrun waiver is human-only and never auto-answered =="
# The owner's waiver of an unrun running-system Validation step (af36-remainder/01, AC4): a lane's
# relay hook must never answer it from policy, even a policy that names it with a valid sha.
AW_CANON='{"AUT-WAIVE":"Waive this step"}'
jq -n --argjson a "$AW_CANON" --arg s "$(_t_sha "$AW_CANON")" '{policy_sha: $s, sources: [], answers: $a}' > "$ROOT/pol-aw.json"
Q_AW="$(q1 AUT-WAIVE '["Waive this step","Keep parked"]')"
# aw_check <lane-policy script> — 0 iff AUT-WAIVE's catalog row is human-only with its exact labels
# AND decide answers `human` for the coded AUT-WAIVE question under a policy naming it.
aw_check() {
  [ "$(bash "$1" catalog 2>/dev/null | awk -F'\t' '$1 == "AUT-WAIVE" { print $1 "\t" $2 "\t" $3 }')" \
      = "AUT-WAIVE${TAB}human-only${TAB}Waive this step|Keep parked" ] \
    && [ "$(bash "$1" decide "$Q_AW" --policy-json "$ROOT/pol-aw.json" 2>/dev/null)" = "human" ]
}
aw_check "$LP" && ok "(aw1) AUT-WAIVE is human-only ('Waive this step|Keep parked') and decide answers human even when a valid policy names it" \
  || no "(aw1) AUT-WAIVE is not human-only, or decide auto-answered the waiver: catalog=[$(bash "$LP" catalog | grep '^AUT-WAIVE')] decide=[$(bash "$LP" decide "$Q_AW" --policy-json "$ROOT/pol-aw.json" 2>/dev/null)]"
# Mutation control (the brief's pin): flip AUT-WAIVE's policy to `allowed` ⇒ (aw1) must FAIL.
MUT_AW="$ROOT/lane-policy.mut-aw.sh"
sed '/_lp_row AUT-WAIVE /s/human-only/allowed   /' "$LP" > "$MUT_AW"
if [ -s "$MUT_AW" ] && ! cmp -s "$LP" "$MUT_AW" && bash -n "$MUT_AW" 2>/dev/null \
   && grep -qF '_lp_row AUT-WAIVE    allowed    ' "$MUT_AW"; then
  ok "(aw2) the AUT-WAIVE mutant is valid: non-empty, differs from the original, passes bash -n, the hunk landed"
  if aw_check "$MUT_AW"; then
    no "(aw3) REFUTED: with AUT-WAIVE flipped to allowed, (aw1) still passes — the pin is vacuous"
  else
    ok "(aw3) CONFIRMED: with AUT-WAIVE flipped to allowed, (aw1) FAILS (decide=$(bash "$MUT_AW" decide "$Q_AW" --policy-json "$ROOT/pol-aw.json" 2>/dev/null)) — the pin is load-bearing"
  fi
else
  no "(aw2) the AUT-WAIVE mutation did not land cleanly (empty / identical / bash -n failed / hunk missing)"
fi

# ============================================================================
echo "== (op) optional labels — the LP-SAVE last-attempt ask (wave 7) =="
# Run automate-2026-10-15-163325 wave 7: the owner set LP-SAVE=Save and exit, but a PASS on the third and
# last Plan Review attempt offers only `Save and exit` · `Discard` (no attempt left to Refine or Edit), so
# decide's exact-set match sent it to the human. The catalog now marks Refine / Edit `?`: the ask offers
# every label or exactly the non-`?` core, and decide matches either — never another subset.
POL_SV='{"LP-SAVE":"Save and exit"}'
jq -n --argjson a "$POL_SV" --arg s "$(_t_sha "$POL_SV")" '{policy_sha: $s, sources: [], answers: $a}' > "$ROOT/pol-sv.json"
Q_SV_CORE="$(q1 LP-SAVE '["Save and exit (Recommended)","Discard"]')"
[ "$(dec "$Q_SV_CORE" "$ROOT/pol-sv.json")" = '{"0":"Save and exit (Recommended)"}' ] \
  && ok "(op1) the last-attempt LP-SAVE ask (core labels only) gets the policy answer" || no "(op1) $(dec "$Q_SV_CORE" "$ROOT/pol-sv.json")"
[ "$(dec "$(q1 LP-SAVE '["Save and exit","Refine further","Edit sections","Discard"]')" "$ROOT/pol-sv.json")" = '{"0":"Save and exit"}' ] \
  && ok "(op2) the full LP-SAVE ask still gets it" || no "(op2)"
[ "$(dec "$(q1 LP-SAVE '["Save and exit","Refine further","Discard"]')" "$ROOT/pol-sv.json")" = "human" ] \
  && ok "(op3) any other subset (one optional label dropped) ⇒ human" || no "(op3)"
[ "$(dec "$(q1 LP-SAVE '["Save and exit"]')" "$ROOT/pol-sv.json")" = "human" ] && ok "(op4) a core label missing ⇒ human" || no "(op4)"
[ "$(dec "$(q1 LP-SAVE-NOTE '["Save and exit","Discard"]')" "$ROOT/pol-sv.json")" = "human" ] \
  && ok "(op5) the same core under LP-SAVE-NOTE (auto, policy-exempt; no policy answer) ⇒ human" || no "(op5)"
POL_RF='{"LP-SAVE":"Refine further"}'
jq -n --argjson a "$POL_RF" --arg s "$(_t_sha "$POL_RF")" '{policy_sha: $s, sources: [], answers: $a}' > "$ROOT/pol-rf.json"
[ "$(dec "$Q_SV_CORE" "$ROOT/pol-rf.json")" = "human" ] \
  && ok "(op6) a policy answer the core ask does not offer (Refine further) ⇒ human" || no "(op6)"
RFOP="$ROOT/op-run.md"; printf '# Automate Run: op-run\n\n## Progress\n' > "$RFOP"
bash "$LP" wave-set "$RFOP" 'LP-SAVE=Refine further?' >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && [ ! -e "$ROOT/op-run.wave-policy.json" ] && ok "(op7) wave-set refuses a label spelled with its ? marker (the marker is not part of the label)" || no "(op7) rc=$rc"
# (op8) MUTATION CONTROL: decide's core branch removed ⇒ (op1) fails (the wave 7 incident).
MUT_OP="$ROOT/lane-policy-op.sh"
sed 's/| (\$ql != (\$row.labels | sort)) and (\$ql != (\$row.core | sort)) then null/| ($ql != ($row.labels | sort)) then null/' "$LP" > "$MUT_OP"
if ! cmp -s "$LP" "$MUT_OP" && bash -n "$MUT_OP" \
   && [ "$(bash "$MUT_OP" decide "$Q_SV_CORE" --policy-json "$ROOT/pol-sv.json" 2>/dev/null)" = "human" ]; then
  ok "(op8) CONFIRMED: without the core match the last-attempt LP-SAVE ask goes to the human — (op1) is load-bearing"
else
  no "(op8) the core-match mutation did not land, or did not change the decision"
fi

# ============================================================================
echo "== (gh) check-gate-headers.sh — every engine ask carries its catalog code and labels =="
CGH="$SCRIPT_DIR/check-gate-headers.sh"
out="$(bash "$CGH" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "(gh1) the real tree is clean (exit 0, no drift lines)" || no "(gh1) rc=$rc: $(printf '%s\n' "$out" | head -5)"
# gh_tree — a scratch plugin: the engine prose and the emitters, copied (the check reads nothing else).
gh_tree() {
  local t="$ROOT/gh-$1"; rm -rf "$t"; mkdir -p "$t/scripts"
  cp -R "$SCRIPT_DIR/../agents" "$SCRIPT_DIR/../commands" "$SCRIPT_DIR/../skills" "$t/"
  cp "$LP" "$CGH" "$SCRIPT_DIR"/*-next-step.sh "$t/scripts/"
  printf '%s' "$t"
}
# gh_mut <name> <file under the tree> <python old> <python new> <rule> <expected line fragment>
gh_mut() {
  local t; t="$(gh_tree "$1")"
  if ! python3 - "$t/$2" "$3" "$4" <<'PY'
import sys
p, a, b = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if s.count(a) != 1: sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
  then no "(gh-$1) mutation did not land in $2"; return; fi
  out="$(bash "$t/scripts/check-gate-headers.sh" 2>&1)"; rc=$?
  case "$out" in *"check-gate-headers: $5 "*"$6"*) [ "$rc" -eq 1 ] && ok "(gh-$1) $5 fires: $6" || no "(gh-$1) rc=$rc" ;;
    *) no "(gh-$1) $5 did not fire (rc=$rc): $(printf '%s\n' "$out" | head -3)" ;; esac
}
t="$(gh_tree clean)"; out="$(bash "$t/scripts/check-gate-headers.sh" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "(gh2) control: the unmutated scratch copy is clean" || no "(gh2) scratch copy red (mutations would be meaningless): $out"
# G1 — wave 7's AUT-WAIVE ask, as it was emitted
gh_mut g1 scripts/automate-next-step.sh 'header: "AUT-WAIVE", options: ["Waive this step", "Keep parked"]' \
  'header: "", options: ["Waive this step", "Keep parked"]' G1 'an empty header'
# G2 — an invented code
gh_mut g2 skills/automate-loop/intake.md 'Ask it with `header: "AUT-QUEUE"`' 'Ask it with `header: "AUT-QUEUED"`' G2 'header "AUT-QUEUED" is not a catalog code'
# G3 — the code kept, a label paraphrased away
gh_mut g3 skills/automate-loop/resume.md '`Continue` · `Start new` · `Archive`' '`Continue` · `Start over` · `Archive`' G3 'the AUT-RESUME ask does not offer its catalog label(s) "Start new"'
# G4 — options spelled out with the code dropped (the pre-fix NO-GO line)
gh_mut g4 agents/launch-pad.md 'with `header: "LP-NO-GO"` and 3 options:' 'with 3 options:' G4 'agents/launch-pad.md'
# G5 — the pre-fix LP-SAVE contract (a noted PASS "gets no code") leaves LP-SAVE-NOTE with no ask site
gh_mut g5 agents/launch-pad.md '`header: "LP-SAVE-NOTE"` (an `auto` gate by owner decision, asked whenever its auto answer escalates) when it carries any issue or note' \
  'no code when it carries any issue or note' G5 'LP-SAVE-NOTE has no'
bash "$CGH" --bogus >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "(gh3) an unknown argument is a usage error (exit 2)" || no "(gh3) rc=$rc"
bash "$CGH" --root "$ROOT/gh-none" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "(gh4) a missing plugin dir fails CLOSED (exit 2, never a clean read)" || no "(gh4) rc=$rc"

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

# ============================================================================
echo "== (pa) policy answerability (D1) — base-allowed auto codes answered, LP-SAVE-NOTE refused =="
# A policy naming every code that was `allowed` before the auto tier, with a valid sha.
PA_ANS='{"AUT-QUEUE":"Process","AUT-RESUME":"Continue","LP-SAVE":"Save and exit"}'
PA_CANON="$(jq -cS . <<<"$PA_ANS")"
jq -n --argjson a "$PA_CANON" --arg s "$(_t_sha "$PA_CANON")" '{policy_sha: $s, sources: [], answers: $a}' > "$ROOT/pol-pa.json"
SN_CANON='{"LP-SAVE-NOTE":"Save and exit"}'
jq -n --argjson a "$SN_CANON" --arg s "$(_t_sha "$SN_CANON")" '{policy_sha: $s, sources: [], answers: $a}' > "$ROOT/pol-sn.json"
Q_PA_Q="$(q1 AUT-QUEUE '["Process (Recommended)","Stop"]')"
Q_PA_R="$(q1 AUT-RESUME '["Continue","Start new","Archive"]')"
Q_PA_S="$(q1 LP-SAVE '["Save and exit","Discard"]')"
Q_SN="$(q1 LP-SAVE-NOTE '["Save and exit","Refine further","Edit sections","Discard"]')"
# pa_base_ok <lane-policy script> — 0 iff the three base-allowed auto codes are still policy-answered by
# decide AND accepted by wave-set (a scratch run file).
pa_base_ok() {
  local rf="$ROOT/pa-$RANDOM.md"
  printf '# Automate Run: pa\n\n## Progress\n' > "$rf"
  [ "$(bash "$1" decide "$Q_PA_Q" --policy-json "$ROOT/pol-pa.json" 2>/dev/null)" = '{"0":"Process (Recommended)"}' ] \
    && [ "$(bash "$1" decide "$Q_PA_R" --policy-json "$ROOT/pol-pa.json" 2>/dev/null)" = '{"0":"Continue"}' ] \
    && [ "$(bash "$1" decide "$Q_PA_S" --policy-json "$ROOT/pol-pa.json" 2>/dev/null)" = '{"0":"Save and exit"}' ] \
    && LOOMWRIGHT_LANE_POLICY_HELPERS="$SCRIPT_DIR/automate-helpers.sh" \
       bash "$1" wave-set "$rf" 'AUT-QUEUE=Process' 'AUT-RESUME=Continue' 'LP-SAVE=Save and exit' >/dev/null 2>&1
}
# pa_sn_refused <lane-policy script> — 0 iff LP-SAVE-NOTE is refused by wave-set (exit 1, nothing written)
# AND by decide (human) under a valid policy naming it.
pa_sn_refused() {
  local rf="$ROOT/pa-sn-$RANDOM.md" r
  printf '# Automate Run: pasn\n\n## Progress\n' > "$rf"
  LOOMWRIGHT_LANE_POLICY_HELPERS="$SCRIPT_DIR/automate-helpers.sh" bash "$1" wave-set "$rf" 'LP-SAVE-NOTE=Save and exit' >/dev/null 2>&1; r=$?
  [ "$r" -eq 1 ] && [ ! -e "${rf%.md}.wave-policy.json" ] \
    && [ "$(bash "$1" decide "$Q_SN" --policy-json "$ROOT/pol-sn.json" 2>/dev/null)" = "human" ]
}
pa_base_ok "$LP" && ok "(pa1) AUT-QUEUE / AUT-RESUME / LP-SAVE (auto, base-allowed) are still answered by decide and accepted by wave-set" \
  || no "(pa1) a base-allowed auto code lost its policy answer (AC12)"
pa_sn_refused "$LP" && ok "(pa2) LP-SAVE-NOTE is refused by wave-set (exit 1, nothing written) and decide answers human under a valid policy naming it" \
  || no "(pa2) LP-SAVE-NOTE was policy-answered (D1 broken)"
# (pa3) resolve drops LP-SAVE-NOTE from a STAMPED project policy and reports it; the base-allowed codes stay.
RPA="$(new_repo)"; HPA="$ROOT/hpa"; mkdir -p "$HPA"
seed_policy "$RPA" '{"AUT-RESUME":"Continue","LP-SAVE":"Save and exit","LP-SAVE-NOTE":"Save and exit"}' "[$RULE_OK]"; stamp "$RPA" "$HPA"
opa="$(resolve "$RPA" "$HPA")"; epa="$(cat "$ROOT/resolve.err")"
[ "$(jq -cS '.answers' <<<"$opa")" = '{"AUT-RESUME":"Continue","LP-SAVE":"Save and exit"}' ] \
  && grep -qF 'lane-policy: dropped project LP-SAVE-NOTE — auto (never answered by policy)' <<<"$epa" \
  && ok "(pa3) resolve keeps AUT-RESUME / LP-SAVE, drops LP-SAVE-NOTE and reports it" || no "(pa3) out=$opa err=$epa"
# MUTATION CONTROLS (the brief's pins): an emptied exemption list ⇒ (pa2) fails; the helper narrowed to
# `allowed` only ⇒ (pa1) fails.
MUT_EX="$ROOT/lane-policy.mut-ex.sh"
sed 's/^_LP_POLICY_EXEMPT="LP-SAVE-NOTE"/_LP_POLICY_EXEMPT=""/' "$LP" > "$MUT_EX"
if ! cmp -s "$LP" "$MUT_EX" && bash -n "$MUT_EX" 2>/dev/null && grep -q '^_LP_POLICY_EXEMPT=""' "$MUT_EX"; then
  pa_sn_refused "$MUT_EX" && no "(pa4) REFUTED: with _LP_POLICY_EXEMPT emptied LP-SAVE-NOTE is still refused — (pa2) is vacuous" \
    || ok "(pa4) CONFIRMED: with _LP_POLICY_EXEMPT emptied a policy answers LP-SAVE-NOTE and (pa2) FAILS"
else
  no "(pa4) the exemption mutation did not land"
fi
MUT_AN="$ROOT/lane-policy.mut-an.sh"
sed 's/ or (\$row\.policy == "auto" and (\[%s\] | any(\.\[\]; \. == \$code) | not))//' "$LP" > "$MUT_AN"
# Gate: the mutant still answers an `allowed` code (a jq error would print human and confirm vacuously).
if ! cmp -s "$LP" "$MUT_AN" && bash -n "$MUT_AN" 2>/dev/null \
   && [ "$(bash "$MUT_AN" decide "$(q1 AUT-SUMMARY '["Keep summary","Drop summary"]')" --policy-json "$ROOT/pol.json" 2>/dev/null)" = '{"0":"Drop summary"}' ]; then
  pa_base_ok "$MUT_AN" && no "(pa5) REFUTED: with the helper narrowed to allowed, the base-allowed auto codes are still answered — (pa1) is vacuous" \
    || ok "(pa5) CONFIRMED: with _lp_policy_answerable narrowed to allowed, (pa1) FAILS"
else
  no "(pa5) the answerability mutation did not land"
fi

# ============================================================================
echo "== (ga) gate-auto.sh — the deterministic auto tier =="
GA="$SCRIPT_DIR/gate-auto.sh"
GR="$(new_repo)"   # a scratch checkout: its own .supervisor/, never the real one
GRF="$GR/$RID_FILE"
printf 'README.md\n./docs/guide.md\n\n' > "$ROOT/ga-low.txt"
printf 'docs/guide.md\nloomwright/agents/worker.md\n' > "$ROOT/ga-agents.txt"
printf 'src/oauth/login.ts\n' > "$ROOT/ga-auth.txt"
QO=(--offered 'Process (Recommended)' --offered Stop)
RO=(--offered Continue --offered 'Start new' --offered Archive)
SF=(--offered 'Save and exit' --offered 'Refine further' --offered 'Edit sections' --offered Discard)
SC=(--offered 'Save and exit (Recommended)' --offered Discard)
# ga <script> <decide args…> — runs decide in the scratch checkout; prints its one stdout line.
ga() { local s="$1"; shift; ( cd "$GR" && bash "$s" decide "$@" --root "$GR" 2>/dev/null </dev/null ); }
gaeq() {  # gaeq <label> <want> <decide args…> — one leg against the real script
  local label="$1" want="$2" got; shift 2
  got="$(ga "$GA" "$@")"
  [ "$got" = "$want" ] && ok "$label ⇒ '$want'" || no "$label: got '$got', want '$want'"
}
gaeq "(ga1) AUT-QUEUE with its catalog labels" "answer Process" AUT-QUEUE "${QO[@]}"
gaeq "(ga2) AUT-RESUME with its labels and --recommended Continue" "answer Continue" AUT-RESUME "${RO[@]}" --recommended Continue
gaeq "(ga3) LP-SAVE, full labels, NONE, low-risk paths" "answer Save and exit" LP-SAVE "${SF[@]}" --max-severity NONE --risk-paths "$ROOT/ga-low.txt"
gaeq "(ga4) LP-SAVE-NOTE, core labels, LOW, low-risk paths" "answer Save and exit" LP-SAVE-NOTE "${SC[@]}" --max-severity LOW --risk-paths "$ROOT/ga-low.txt"
# off — each source alone.
gaeq "(ga5) --off" "ask off" AUT-QUEUE "${QO[@]}" --off
printf '# Automate Run: ga\n\n## Status: running\n\n## Run Config\n- mode: safe | limit: 5\n- auto_gates: off\n\n## Queue\n- [ ] a.md\n\n## Progress\n- 2026-11-03T00:00:00Z started\n' > "$ROOT/ga-off.md"
printf '# Automate Run: ga\n\n## Status: running\n\n## Run Config\n- mode: safe | limit: 5\n\n## Queue\n- [ ] a.md\n\n## Progress\n- 2026-11-03T00:00:00Z started\n- 2026-11-03T00:00:01Z note: auto_gates: off\n' > "$ROOT/ga-on.md"
gaeq "(ga6) ## Run Config '- auto_gates: off'" "ask off" AUT-QUEUE "${QO[@]}" --runfile "$ROOT/ga-off.md"
gaeq "(ga6b) control: the same text outside ## Run Config is not the switch" "answer Process" AUT-QUEUE "${QO[@]}" --runfile "$ROOT/ga-on.md"
mkdir -p "$ROOT/ga-off.phase/launch-pad"
got="$( cd "$GR" && LOOMWRIGHT_PHASE_DIR="$ROOT/ga-off.phase/launch-pad" bash "$GA" decide AUT-QUEUE "${QO[@]}" --root "$GR" 2>/dev/null )"
[ "$got" = "ask off" ] && ok "(ga6c) the run file resolved from LOOMWRIGHT_PHASE_DIR (<run>.phase/<phase> ⇒ <run>.md) carries the switch ⇒ 'ask off'" || no "(ga6c) got '$got'"
gaeq "(ga6d) a --runfile that does not exist cannot be read ⇒ asks" "ask runfile_unreadable" AUT-QUEUE "${QO[@]}" --runfile "$ROOT/none.md"
printf '{"schema_version":1,"lane":"L1","auto_gates":false}\n' > "$GR/.supervisor/lane.json"
gaeq "(ga7) lane.json auto_gates: false" "ask off" AUT-QUEUE "${QO[@]}"
printf '{"schema_version":1,"lane":"L1","policy":null}\n' > "$GR/.supervisor/lane.json"
gaeq "(ga7b) control: a lane.json without auto_gates" "answer Process" AUT-QUEUE "${QO[@]}"
printf '{"lane":' > "$GR/.supervisor/lane.json"
gaeq "(ga7c) an unreadable lane.json fails toward asking" "ask lane_json_unreadable" AUT-QUEUE "${QO[@]}"
rm -f "$GR/.supervisor/lane.json"
printf '{"auto_review":false,"auto_gates":false}\n' > "$GR/.supervisor/config.json"
gaeq "(ga8) config.json {\"auto_gates\": false} (has(), never // empty)" "ask off" AUT-QUEUE "${QO[@]}"
printf '{"auto_gates":true}\n' > "$GR/.supervisor/config.json"
gaeq "(ga8b) control: config.json auto_gates true" "answer Process" AUT-QUEUE "${QO[@]}"
printf '{"auto_gates":"no"}\n' > "$GR/.supervisor/config.json"
gaeq "(ga8c) a non-boolean auto_gates value fails toward asking" "ask off" AUT-QUEUE "${QO[@]}"
printf 'not json\n' > "$GR/.supervisor/config.json"
gaeq "(ga8d) an unreadable config.json fails toward asking" "ask config_unreadable" AUT-QUEUE "${QO[@]}"
rm -f "$GR/.supervisor/config.json"
# not_auto — human-only stays human; allowed is not auto either.
gaeq "(ga9) a human-only code (LP-NO-GO) with its exact labels" "ask not_auto" LP-NO-GO --offered 'Override and continue' --offered 'Revise goal' --offered Abort
gaeq "(ga9b) an allowed code (AUT-SUMMARY) is not auto-answered" "ask not_auto" AUT-SUMMARY --offered 'Keep summary' --offered 'Drop summary'
gaeq "(ga9c) an unknown code" "ask unknown_code" AUT-QUEUED "${QO[@]}"
# label
gaeq "(ga10) a missing option" "ask label" AUT-QUEUE --offered Process
gaeq "(ga10b) an extra option" "ask label" AUT-QUEUE "${QO[@]}" --offered Later
gaeq "(ga10c) no --offered at all" "ask label" AUT-QUEUE
gaeq "(ga10d) --recommended not the ! label" "ask label" AUT-QUEUE "${QO[@]}" --recommended Stop
gaeq "(ga10e) LP-SAVE with a non-core subset" "ask label" LP-SAVE --offered 'Save and exit' --offered 'Refine further' --offered Discard --max-severity NONE
MUT_NB="$ROOT/lane-policy.mut-nobang.sh"
sed "/_lp_row AUT-QUEUE /s/'Process!|Stop'/'Process|Stop'/" "$LP" > "$MUT_NB"
if ! cmp -s "$LP" "$MUT_NB" && bash -n "$MUT_NB" 2>/dev/null; then
  got="$( cd "$GR" && LOOMWRIGHT_GATE_AUTO_LANE_POLICY="$MUT_NB" bash "$GA" decide AUT-QUEUE "${QO[@]}" --root "$GR" 2>/dev/null )"
  [ "$got" = "ask label" ] && ok "(ga10f) a row with no ! label (AUT-QUEUE's ! removed in a copy) ⇒ 'ask label', so (ga1) depends on the marker" || no "(ga10f) got '$got'"
else
  no "(ga10f) the no-! mutation did not land"
fi
# destructive / severity / high_risk
gaeq "(ga11) --destructive" "ask destructive" AUT-QUEUE "${QO[@]}" --destructive
gaeq "(ga12) --max-severity MEDIUM" "ask severity" LP-SAVE-NOTE "${SC[@]}" --max-severity MEDIUM --risk-paths "$ROOT/ga-low.txt"
gaeq "(ga12b) --max-severity high (any case)" "ask severity" LP-SAVE-NOTE "${SC[@]}" --max-severity high --risk-paths "$ROOT/ga-low.txt"
gaeq "(ga12c) --max-severity BLOCKING" "ask severity" LP-SAVE "${SF[@]}" --max-severity BLOCKING
gaeq "(ga12d) LP-SAVE-NOTE with no --max-severity" "ask severity" LP-SAVE-NOTE "${SC[@]}" --risk-paths "$ROOT/ga-low.txt"
gaeq "(ga12e) an unparseable --max-severity" "ask severity" LP-SAVE-NOTE "${SC[@]}" --max-severity CRITICALISH --risk-paths "$ROOT/ga-low.txt"
gaeq "(ga13) --risk-paths listing a path under agents/" "ask high_risk" LP-SAVE-NOTE "${SC[@]}" --max-severity LOW --risk-paths "$ROOT/ga-agents.txt"
gaeq "(ga13b) --risk-paths matching *auth*" "ask high_risk" LP-SAVE "${SF[@]}" --risk-paths "$ROOT/ga-auth.txt"
gaeq "(ga13c) an unreadable --risk-paths list (classify-risk null)" "ask high_risk" LP-SAVE "${SF[@]}" --risk-paths "$ROOT/no-such-list.txt"
GB0="$(git -C "$GR" rev-parse --abbrev-ref HEAD)"
( cd "$GR" && git checkout -qb ga-low && printf 'more\n' >> f && git commit -qam low \
    && git checkout -qb ga-high && mkdir -p agents && printf 'x\n' > agents/a.md && git add agents && git commit -qm high \
    && git checkout -q - ) >/dev/null 2>&1
gaeq "(ga13d) --risk-diff over a diff touching agents/" "ask high_risk" AUT-RESUME "${RO[@]}" --risk-diff ga-low ga-high
gaeq "(ga13e) --risk-diff over a low-risk diff" "answer Continue" AUT-RESUME "${RO[@]}" --risk-diff "$GB0" ga-low
gaeq "(ga13f) --risk-diff with a bad ref (classify-risk null)" "ask high_risk" AUT-RESUME "${RO[@]}" --risk-diff nope-ref ga-low
# usage / errors
u="$( cd "$GR" && bash "$GA" decide 2>/dev/null )"; urc=$?
[ "$u" = "ask usage" ] && [ "$urc" -eq 2 ] && ok "(ga14) a usage error prints 'ask usage' and exits 2" || no "(ga14) out='$u' rc=$urc"
u="$( cd "$GR" && bash "$GA" decide AUT-QUEUE --bogus 2>/dev/null )"; urc=$?
[ "$u" = "ask usage" ] && [ "$urc" -eq 2 ] && ok "(ga14b) an unknown flag is a usage error too" || no "(ga14b) out='$u' rc=$urc"
NJG="$ROOT/nojq-ga"; mkdir -p "$NJG"; for t in dirname git cat awk; do ln -s "$(command -v "$t")" "$NJG/$t"; done
u="$( cd "$GR" && PATH="$NJG" "$BASH_BIN" "$GA" decide AUT-QUEUE "${QO[@]}" --root "$GR" 2>/dev/null )"; urc=$?
[ "$u" = "ask jq_missing" ] && [ "$urc" -eq 0 ] && ok "(ga14c) no jq ⇒ 'ask jq_missing', exit 0" || no "(ga14c) out='$u' rc=$urc"
printf '#!/usr/bin/env bash\nexit 0\n' > "$ROOT/empty-catalog.sh"
u="$( cd "$GR" && LOOMWRIGHT_GATE_AUTO_LANE_POLICY="$ROOT/empty-catalog.sh" bash "$GA" decide AUT-QUEUE "${QO[@]}" --root "$GR" 2>/dev/null )"
[ "$u" = "ask catalog_unreadable" ] && ok "(ga14d) a catalog that prints nothing ⇒ 'ask catalog_unreadable'" || no "(ga14d) out='$u'"
u="$( cd "$GR" && bash "$GA" decide AUT-QUEUE "${QO[@]}" --root "$ROOT/no-such-dir" 2>/dev/null )"
[ "$u" = "ask root_unreadable" ] && ok "(ga14e) a --root that is not a directory ⇒ 'ask root_unreadable' (its off switches cannot be read)" || no "(ga14e) out='$u'"

# record / list
before="$(cat "$GRF")"
bash "$GA" record "$GRF" AUT-QUEUE Process "queue-confirm asked; no trigger" >/dev/null 2>&1; r1=$?
bash "$GA" record "$GRF" LP-SAVE-NOTE 'Save and exit' "PASS max LOW
second line" --item a.md >/dev/null 2>&1
bash "$GA" record "$GRF" LP-SAVE --escalated high_risk --item b.md >/dev/null 2>&1
bash "$GA" record "$GRF" AUT-QUEUE --escalated off >/dev/null 2>&1
added="$(diff <(printf '%s\n' "$before") "$GRF" | sed -n 's/^> //p')"
re_ts='^- [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z '
if [ "$r1" -eq 0 ] && [ "$(printf '%s\n' "$added" | grep -c .)" -eq 3 ] \
   && grep -qE "${re_ts}auto-answered AUT-QUEUE: Process — queue-confirm asked; no trigger\$" < <(sed -n 1p <<<"$added") \
   && grep -qE "${re_ts}auto-answered LP-SAVE-NOTE: Save and exit — PASS max LOW second line \(item a\.md\)\$" < <(sed -n 2p <<<"$added") \
   && grep -qE "${re_ts}auto-escalated LP-SAVE: high_risk \(item b\.md\)\$" < <(sed -n 3p <<<"$added"); then
  ok "(ga15) record appends one ## Progress line each (auto-answered / auto-escalated, newline flattened, item suffix); --escalated off writes nothing"
else
  no "(ga15) added lines: [$added]"
fi
std="$(bash "$GA" record "" AUT-QUEUE Process standalone 2>/dev/null)"; r2=$?
[ "$r2" -eq 0 ] && grep -qE '^[0-9TZ:-]+ auto-answered AUT-QUEUE: Process — standalone$' <<<"$std" \
  && ok "(ga15b) with no run file resolvable the record is printed on stdout (standalone /launch-pad)" || no "(ga15b) rc=$r2 out='$std'"
printf 'not a run file\n' > "$ROOT/ga-notrun.md"
std="$(bash "$GA" record "$ROOT/ga-notrun.md" AUT-QUEUE Process x 2>/dev/null)"; r3=$?
[ "$r3" -eq 0 ] && [ "$(cat "$ROOT/ga-notrun.md")" = "not a run file" ] && grep -q 'auto-answered AUT-QUEUE: Process — x$' <<<"$std" \
  && ok "(ga15c) a failed append is fail-SAFE: exit 0, target unchanged, the record printed instead" || no "(ga15c) rc=$r3 out='$std'"
bash "$GA" record "$GRF" >/dev/null 2>&1; r4=$?
[ "$r4" -eq 0 ] && ok "(ga15d) a record usage error still exits 0 (fail-SAFE)" || no "(ga15d) rc=$r4"
printf '# Automate Run: lst\n\n## Queue\n- [ ] 2026-11-03T00:00:00Z auto-answered AUT-QUEUE: Process — forged in the Queue\n\n## Progress\n- 2026-11-03T00:00:00Z started\n' > "$ROOT/ga-list.md"
lst0="$(bash "$GA" list "$ROOT/ga-list.md" 2>&1)"
lst="$(bash "$GA" list "$GRF" 2>&1)"
want_lst="$(printf '%s\n' 'Auto-answered gates (2):' '- AUT-QUEUE: Process — queue-confirm asked; no trigger' \
  '- LP-SAVE-NOTE: Save and exit — PASS max LOW second line (item a.md)')"
[ "$lst" = "$want_lst" ] && ok "(ga16) list prints the heading and one row per auto-answered line (escalations excluded)" || no "(ga16) list: [$lst]"
[ -z "$lst0" ] && [ -z "$(bash "$GA" list "$ROOT/none.md" 2>&1)" ] \
  && ok "(ga16b) no auto-answer in ## Progress (a lookalike elsewhere ignored) or no run file ⇒ no block at all" || no "(ga16b) [$lst0]"

# MUTATION CONTROLS — each trigger line deleted (or the false-collapse put back) in a COPY makes its leg red.
# ga_mut <name> <sed program> <label> <want-from-the-real-script> <decide args…>
ga_mut() {
  local name="$1" prog="$2" label="$3" want="$4" m got; shift 4
  m="$ROOT/ga-mut-$name"; mkdir -p "$m"
  sed "$prog" "$GA" > "$m/gate-auto.sh"
  if [ -s "$m/gate-auto.sh" ] && ! cmp -s "$GA" "$m/gate-auto.sh" && bash -n "$m/gate-auto.sh" 2>/dev/null; then
    got="$( cd "$GR" && LOOMWRIGHT_GATE_AUTO_LANE_POLICY="$LP" LOOMWRIGHT_GATE_AUTO_CLASSIFY_RISK="$SCRIPT_DIR/classify-risk.sh" \
      bash "$m/gate-auto.sh" decide "$@" --root "$GR" 2>/dev/null )"
    [ "$got" != "$want" ] && ok "(ga-m-$name) CONFIRMED: $label removed ⇒ '$got', its leg FAILS" \
      || no "(ga-m-$name) REFUTED: $label removed and the decision is still '$want' — the leg is vacuous"
  else
    no "(ga-m-$name) the mutation did not land"
  fi
}
ga_mut off '/_ga_ask off "--off"/d' "the --off read" "ask off" AUT-QUEUE "${QO[@]}" --off
ga_mut runcfg '/_ga_runconfig_off "\$rf" &&/d' "the ## Run Config read" "ask off" AUT-QUEUE "${QO[@]}" --runfile "$ROOT/ga-off.md"
printf '{"lane":"L1","auto_gates":false}\n' > "$GR/.supervisor/lane.json"
ga_mut lanejson '/_ga_ask off "lane.json/d' "the lane.json read" "ask off" AUT-QUEUE "${QO[@]}"
rm -f "$GR/.supervisor/lane.json"
printf '{"auto_gates":false}\n' > "$GR/.supervisor/config.json"
ga_mut collapse 's/if has("auto_gates") then (\.auto_gates | tojson) else empty end/.auto_gates \/\/ empty/' \
  "has(\"auto_gates\") (replaced by the // empty false-collapse)" "ask off" AUT-QUEUE "${QO[@]}"
rm -f "$GR/.supervisor/config.json"
ga_mut tier '/_ga_ask not_auto/d' "the policy == auto tier check" "ask not_auto" LP-NO-GO --offered 'Override and continue' --offered 'Revise goal' --offered Abort
ga_mut label '/_ga_ask label "offered labels/s/|| {.*}/|| :/' "the offered-labels-vs-catalog comparison" "ask label" AUT-QUEUE --offered Process
ga_mut destructive '/_ga_ask destructive/d' "the --destructive line" "ask destructive" AUT-QUEUE "${QO[@]}" --destructive
ga_mut severity '/BLOCKING|HIGH|MEDIUM) _ga_ask severity/d' "the MEDIUM-or-higher line" "ask severity" LP-SAVE-NOTE "${SC[@]}" --max-severity MEDIUM --risk-paths "$ROOT/ga-low.txt"
ga_mut highrisk '/_ga_ask high_risk/d' "the high_risk true/null line" "ask high_risk" LP-SAVE-NOTE "${SC[@]}" --max-severity LOW --risk-paths "$ROOT/ga-agents.txt"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
