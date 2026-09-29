#!/usr/bin/env bash
# test-rules-gate-verdict.sh — self-tests for rules-gate-verdict.sh (the fail-CLOSED gate verdict over
# human-stamped, gate-COUNTABLE must-checks), for rules-check.sh's `binds` hash-binding and
# --list-gateable classification, and for the shared rules-replay-lib.sh
# (rule-enforcement-at-review-and-merge, subtask 1). Every case runs inside ISOLATED temp git repos
# (`mktemp -d` + `git init`) with its OWN sandbox HOME, so neither the real .agent/rules/ nor the real
# user-scope rules-check stamp is ever touched. All temp state lives under ONE $ROOT so a single trap
# cleans it. Exit 0 = all pass, 1 = any failure (auto-registered by ci.yml's test-*.sh glob).
#
# Cases (the helper halves of the brief's acceptance criteria):
#   (ac1)  stamped, countable, FAILING check  => verdict fail, id in failing, exit 0, one JSON line
#   (ac2)  stamped, countable, PASSING check  => verdict ok, checks_passed "1/1"
#   (ac3)  unstamped (stamp absent; one byte of the check edited after stamping) => verdict unstamped,
#          no `[RUN ]`, the canary the check would touch stays absent; positive control proves it can fire
#   (ac4)  RULES_CHECK_NO_CMD=1 => verdict cmd_disabled, --if-stamped NEVER invoked (argv spy), canary
#          absent; the spy also proves: sibling resolution (PATH decoy never called), never --confirm,
#          an ambient RULES_CHECK_CONFIRM=1 never reaches the checker, exactly four calls
#   (ac6)  --list-gateable fixtures (a1) binds:[] grep-only => countable/no_invocations; (a2) no key or
#          null => advisory/binds_undeclared; (b) `bash scripts/lint.sh` + binds:[] => advisory/unbound;
#          (c) + binds:["scripts/lint.sh"] => countable/bound:1; (d) a tracked `#!` script named bare
#          is detected; (e) an untracked path is not; (f) absolute / `..` / `~` / untracked bind or a
#          non-array => advisory/binds_invalid — each executes nothing (canary) and exits 0
#   (ac7)  caveat (d): fixture (c) stamped+failing, a second commit edits scripts/lint.sh so the check
#          would pass => `--if-stamped` prints `[SKIP] all (unstamped)` and the verdict is unstamped;
#          fixture (b) stamped+failing => verdict none with the id under advisory (never counted), the
#          advisory FAIL still reported; an all-advisory listing stays none under every replay shape and
#          under RULES_CHECK_NO_CMD=1; a trailer failure lists ONLY countable ids as unresolved
#   (ac8)  binds-free stores (no key / null / []) hash and print BYTE-IDENTICALLY under the pre-change
#          checker (git show HEAD:) and the current one; the stamp hash also matches an independent
#          jq+sha256 computation (meaningful even once HEAD carries this change)
#   (ac10) forgery legs: pre-printed `  [PASS] <id>`; a forged unstamped line beside a `[RUN ]` line;
#          pre-print-then-kill with a forged COMPLETE trailer; an `M ≠ |selected|` trailer => every
#          countable id unresolved, verdict never ok
#   (unr)  the unreadable legs: bad/valueless --root, unknown arg, non-git dir, checker absent, lib
#          absent, malformed --list-gateable, id-set mismatch, empty --if-stamped stdout; and the
#          `none` legs: no store, all-advisory store
#   (m1)   gated mutant: delete the lib's `M == listed` comparison => the M-mismatch leg flips to ok
#   (m2)   gated mutant: the verdict helper treats advisory ids as countable => the (ac7-b) leg flips
#   (m3)   gated mutant: the checker collapses `[]` and an absent `binds` => (ac6 a2) flips
#   (cs)   the countable-set binding (review iteration 1): a stamped, countable, FAILING check beside a
#          passing countable one, then — with NO re-confirm — (1) `binds: []` dropped, (2) `binds` made a
#          string, (3) `chmod +x` on the data file a `binds: []` grep-check reads, (4) `must`→`should` on
#          the last countable rule, (5) a corrupted rules JSON, (6) a stamp written before the
#          `countable` field existed => verdict never ok/none ((1)-(4),(6) unstamped; (5) unreadable);
#          the legacy stamp over an empty countable set stays none; a re-confirm overwrites the
#          recorded set; --gate-state executes nothing and writes no stamp
#   (m4)   gated mutant: delete the recorded-vs-live set comparison => the (cs 1) leg flips to ok
#   (ur)   the optional `unstamped_reason` (present only on `unstamped`): never_confirmed for (ac3a)/
#          (ac3c), countable_set_drift for (cs 1)/(cs 4) — (cs 4) with ZERO live countable ids —
#          legacy_stamp for (cs 6); absent on a `fail` verdict
#
# Structure: each case is a self-contained `echo "== (...)"` section. New sections are appended just
# above the RESULT footer at the bottom (marked), so the pass/fail tally stays the last thing printed.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/rules-gate-verdict.sh"
CHECKER="$SCRIPT_DIR/rules-check.sh"
LIB="$SCRIPT_DIR/rules-replay-lib.sh"

# The caller's own valve/confirm settings must not leak into any case.
unset RULES_CHECK_NO_CMD RULES_CHECK_CONFIRM

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT" 2>/dev/null' EXIT
# Physical path: git reports physical paths (macOS /var -> /private/var), keep comparisons honest.
ROOT="$(cd "$ROOT" && pwd -P)"

# STAMP_REL — the stamp's path relative to $HOME; must match rules-check.sh's RULES_CHECK_STAMP_FILE.
STAMP_REL=".claude/loomwright/rules-check-stamp.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "test-rules-gate-verdict: jq absent on this host — skipping data assertions."
  echo "RESULT: 0 passed, 0 failed (jq absent, vacuous)"
  exit 0
fi

_t_sha256_file() {
  local f="$1"
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$f" 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$f" 2>/dev/null | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha256 "$f" 2>/dev/null | awk '{print $NF}'
  fi
}

# new_repo <name> — a committed temp git repo under $ROOT carrying a TRACKED `scripts/lint.sh` (+x,
# exits 1 — the failing fixture), a tracked `scripts/hb.sh` (`#!`-headed, NOT +x), a tracked
# `scripts/plain.py` (no `#!`, not +x) and an UNTRACKED `untracked.sh`; prints its path.
new_repo() {
  local r="$ROOT/$1"
  mkdir -p "$r/scripts"
  printf '#!/bin/sh\nexit 1\n' > "$r/scripts/lint.sh"; chmod +x "$r/scripts/lint.sh"
  printf '#!/bin/sh\nexit 0\n' > "$r/scripts/hb.sh"
  printf 'print(1)\n' > "$r/scripts/plain.py"
  printf 'exit 0\n' > "$r/untracked.sh"
  ( cd "$r" && git init -q && git config user.email t@t && git config user.name t \
      && echo init > f && git add f scripts && git commit -qm init ) >/dev/null 2>&1
  printf '%s' "$r"
}

# new_home <name> — an empty sandbox HOME; prints its path.
new_home() { local h="$ROOT/home-$1"; mkdir -p "$h"; printf '%s' "$h"; }

# rule_obj <id> <check> — one valid `must` rule object WITHOUT a `binds` key (compact JSON, built by
# jq so any check text is encoded byte-exact).
rule_obj() {
  jq -cn --arg id "$1" --arg c "$2" \
    '{id:$id, category:"test", statement:("s " + $id), enforcement:"must", check:$c, provenance:{source:"test"}}'
}
# rule_objb <id> <check> <binds-json> — the same WITH a `binds` key holding the given JSON value.
rule_objb() {
  jq -cn --arg id "$1" --arg c "$2" --argjson b "$3" \
    '{id:$id, category:"test", statement:("s " + $id), enforcement:"must", check:$c, binds:$b, provenance:{source:"test"}}'
}

# seed_rules <repo> <obj>... — write .agent/rules/r.json holding the given objects as one array.
seed_rules() {
  local repo="$1"; shift
  mkdir -p "$repo/.agent/rules"
  printf '%s\n' "$@" | jq -s '.' > "$repo/.agent/rules/r.json"
}

# confirm <repo> <home> — a genuine `rules-check.sh --confirm` (runs every check AND writes the stamp).
confirm() { ( cd "$1" && HOME="$2" bash "$CHECKER" --confirm </dev/null >/dev/null 2>&1 ); }

# verdict <home> <cwd> [args...] — run the helper; stdout only (stderr diagnostics dropped).
verdict() {
  local h="$1" d="$2"; shift 2
  ( cd "$d" && HOME="$h" bash "$HELPER" "$@" </dev/null 2>/dev/null )
}
# vf <json> <jq-filter> — a raw field of the verdict object.
vf() { printf '%s' "$1" | jq -r "$2" 2>/dev/null; }
# has_id <json> <array-field> <id> — 0 iff <id> is an element of .<field>.
has_id() { printf '%s' "$1" | jq -e --arg id "$3" ".$2 | index([\$id]) != null" >/dev/null 2>&1; }
# json_ok <json> — 0 iff ONE line, a JSON object with exactly the 8 contract keys — plus the
# OPTIONAL `unstamped_reason`, which must be present (one of its 3 values) exactly when the
# verdict is `unstamped` and absent on every other verdict.
json_ok() {
  [ "$(printf '%s\n' "$1" | awk 'NF{n++} END{print n+0}')" -eq 1 ] \
    && printf '%s' "$1" | jq -e 'type == "object"
      and ((keys - ["unstamped_reason"]) | sort) == ["advisory","checks_passed","countable","failing","passed","selected","unresolved","verdict"]
      and (if .verdict == "unstamped"
           then (.unstamped_reason | IN("never_confirmed", "countable_set_drift", "legacy_stamp"))
           else has("unstamped_reason") | not end)' >/dev/null 2>&1
}
# lg <repo> <home> — the checker's raw --list-gateable stdout.
lg() { ( cd "$1" && HOME="$2" bash "$CHECKER" --list-gateable </dev/null 2>/dev/null ); }
# ifs <repo> <home> — the checker's raw --if-stamped stdout.
ifs() { ( cd "$1" && HOME="$2" bash "$CHECKER" --if-stamped </dev/null 2>/dev/null ); }
# nlines <text> — number of non-empty lines.
nlines() { printf '%s\n' "$1" | awk 'NF{n++} END{print n+0}'; }
TAB="$(printf '\t')"

# ============================================================================
echo "== (ac1) stamped, countable, FAILING must-check => verdict fail, id in failing, exit 0 =="
R1="$(new_repo r1)"; H1="$(new_home 1)"
seed_rules "$R1" "$(rule_objb ac1-fails 'false' '[]')"
confirm "$R1" "$H1"
[ -s "$H1/$STAMP_REL" ] && ok "(ac1 pre) --confirm wrote the stamp" || no "(ac1 pre) no stamp written — fixture broken"
o1="$(verdict "$H1" "$R1" --root "$R1")"; rc1=$?
[ "$rc1" -eq 0 ] && ok "(ac1) exits 0" || no "(ac1) exit $rc1"
json_ok "$o1" && ok "(ac1) stdout is ONE line holding a JSON object with exactly the 8 contract keys" || no "(ac1) bad JSON shape: [$o1]"
[ "$(vf "$o1" .verdict)" = "fail" ] && ok "(ac1) verdict: fail" || no "(ac1) verdict=[$(vf "$o1" .verdict)]"
has_id "$o1" failing ac1-fails && ok "(ac1) ac1-fails is in failing" || no "(ac1) failing=[$(vf "$o1" .failing)]"
has_id "$o1" countable ac1-fails && ok "(ac1) ac1-fails is countable (binds: [] on a grep-free check)" || no "(ac1) countable=[$(vf "$o1" .countable)]"
[ "$(vf "$o1" .checks_passed)" = "0/1" ] && ok "(ac1) checks_passed is \"0/1\"" || no "(ac1) checks_passed=[$(vf "$o1" .checks_passed)]"

# ============================================================================
echo "== (ac2) stamped, countable, PASSING must-check => verdict ok, checks_passed 1/1 =="
R2="$(new_repo r2)"; H2="$(new_home 2)"
seed_rules "$R2" "$(rule_objb ac2-ok 'true' '[]')"
confirm "$R2" "$H2"
o2="$(verdict "$H2" "$R2" --root "$R2")"; rc2=$?
[ "$rc2" -eq 0 ] && [ "$(vf "$o2" .verdict)" = "ok" ] && ok "(ac2) verdict: ok, exit 0" || no "(ac2) rc=$rc2 out=[$o2]"
[ "$(vf "$o2" .checks_passed)" = "1/1" ] && has_id "$o2" passed ac2-ok && [ "$(vf "$o2" '.failing | length')" = "0" ] \
  && ok "(ac2) checks_passed \"1/1\", ac2-ok in passed, failing empty" || no "(ac2) out=[$o2]"

# ============================================================================
echo "== (ac3) unstamped (absent stamp / one-byte edit) => verdict unstamped, no [RUN ], canary absent =="
R3="$(new_repo r3)"; H3="$(new_home 3)"
CANARY="$R3/CANARY"
seed_rules "$R3" "$(rule_objb ac3-canary "touch $CANARY" '[]')"
rm -f "$CANARY"
o3a="$(verdict "$H3" "$R3" --root "$R3")"
raw3a="$(ifs "$R3" "$H3")"
if [ "$(vf "$o3a" .verdict)" = "unstamped" ] && [ ! -e "$CANARY" ] && ! grep -q '^  \[RUN \] ' <<<"$raw3a"; then
  ok "(ac3a) stamp absent: verdict unstamped, CANARY absent, no [RUN ] line in the replay"
else
  no "(ac3a) verdict=[$(vf "$o3a" .verdict)] canary=$([ -e "$CANARY" ] && echo PRESENT || echo absent) raw=[$raw3a]"
fi
has_id "$o3a" countable ac3-canary && ok "(ac3a) the id is still listed as countable (the consumer can PARK rules_unstamped on it)" \
  || no "(ac3a) countable=[$(vf "$o3a" .countable)]"
# Positive control: --confirm runs the check itself (CANARY appears) and stamps the set.
confirm "$R3" "$H3"
[ -e "$CANARY" ] && [ -s "$H3/$STAMP_REL" ] && ok "(ac3b pre) --confirm ran the check (canary CAN fire) and stamped the set" \
  || no "(ac3b pre) --confirm did not run/stamp — positive control broken"
rm -f "$CANARY"
o3b="$(verdict "$H3" "$R3" --root "$R3")"
[ "$(vf "$o3b" .verdict)" = "ok" ] && [ -e "$CANARY" ] && ok "(ac3b) stamped: the helper's replay re-created CANARY and the verdict is ok" \
  || no "(ac3b) verdict=[$(vf "$o3b" .verdict)] canary=$([ -e "$CANARY" ] && echo PRESENT || echo absent)"
rm -f "$CANARY"
# One byte of the check edited after stamping (a trailing comment char) ⇒ the hash moved.
seed_rules "$R3" "$(rule_objb ac3-canary "touch $CANARY #" '[]')"
o3c="$(verdict "$H3" "$R3" --root "$R3")"
raw3c="$(ifs "$R3" "$H3")"
if [ "$(vf "$o3c" .verdict)" = "unstamped" ] && [ ! -e "$CANARY" ] && ! grep -q '^  \[RUN \] ' <<<"$raw3c" \
   && [ "$(printf '%s\n' "$raw3c" | sed -n 1p)" = "  [SKIP] all (unstamped)" ]; then
  ok "(ac3c) one-byte edit after stamping: verdict unstamped, '[SKIP] all (unstamped)', CANARY absent"
else
  no "(ac3c) verdict=[$(vf "$o3c" .verdict)] canary=$([ -e "$CANARY" ] && echo PRESENT || echo absent) raw=[$raw3c]"
fi

# ============================================================================
echo "== (ac4) RULES_CHECK_NO_CMD=1 => verdict cmd_disabled, --if-stamped NEVER invoked, canary absent =="
seed_rules "$R3" "$(rule_objb ac3-canary "touch $CANARY" '[]')"   # back to the STAMPED check text
rm -f "$CANARY"
o4="$( cd "$R3" && HOME="$H3" RULES_CHECK_NO_CMD=1 bash "$HELPER" --root "$R3" </dev/null 2>/dev/null )"
[ "$(vf "$o4" .verdict)" = "cmd_disabled" ] && [ ! -e "$CANARY" ] \
  && ok "(ac4) stamped + RULES_CHECK_NO_CMD=1: verdict cmd_disabled, CANARY absent" \
  || no "(ac4) verdict=[$(vf "$o4" .verdict)] canary=$([ -e "$CANARY" ] && echo PRESENT || echo absent)"
has_id "$o4" countable ac3-canary && ok "(ac4) countable ids still listed under cmd_disabled (gate-eval PARKs rules_cmd_disabled on countable != [])" \
  || no "(ac4) countable=[$(vf "$o4" .countable)]"

echo "  -- argv/PATH spy: a sibling rules-check.sh stub in a temp copy of the helper's dir"
SPY="$ROOT/spy"; mkdir -p "$SPY" "$ROOT/decoy"
cp "$HELPER" "$SPY/rules-gate-verdict.sh"
cp "$LIB" "$SPY/rules-replay-lib.sh"
SPYLOG="$ROOT/spy.log"; DECOYLOG="$ROOT/decoy.log"
cat > "$SPY/rules-check.sh" <<EOF
#!/usr/bin/env bash
printf 'argv=%s confirm_env=%s\n' "\$*" "\${RULES_CHECK_CONFIRM:-}" >> "$SPYLOG"
case "\$1" in
  --list-selected) echo spy-id ;;
  --list-gateable) printf 'spy-id\tcountable\tno_invocations\n' ;;
  --gate-state) printf 'store\tok\nstamp\trecorded\ncountable\tspy-id\n' ;;
  --if-stamped) printf '  [RUN ] spy-id: x\n  [FAIL] spy-id\nChecks passed: 0/1\n'; exit 1 ;;
esac
exit 0
EOF
cat > "$ROOT/decoy/rules-check.sh" <<EOF
#!/usr/bin/env bash
echo "decoy \$*" >> "$DECOYLOG"
EOF
chmod +x "$SPY/rules-check.sh" "$ROOT/decoy/rules-check.sh"
RS="$(new_repo rspy)"; HS="$(new_home spy)"
: > "$SPYLOG"
os1="$( cd "$RS" && HOME="$HS" PATH="$ROOT/decoy:$PATH" RULES_CHECK_CONFIRM=1 bash "$SPY/rules-gate-verdict.sh" --root "$RS" </dev/null 2>/dev/null )"
if [ "$(sed -n 1p "$SPYLOG")" = "argv=--list-selected confirm_env=" ] && [ "$(sed -n 2p "$SPYLOG")" = "argv=--list-gateable confirm_env=" ] \
   && [ "$(sed -n 3p "$SPYLOG")" = "argv=--gate-state confirm_env=" ] \
   && [ "$(sed -n 4p "$SPYLOG")" = "argv=--if-stamped confirm_env=" ] && [ "$(nlines "$(cat "$SPYLOG")")" -eq 4 ] \
   && [ "$(vf "$os1" .verdict)" = "fail" ]; then
  ok "(ac4 spy) exactly four calls in order (--list-selected, --list-gateable, --gate-state, --if-stamped) and the stub's FAIL => verdict fail"
else
  no "(ac4 spy) log=[$(cat "$SPYLOG")] out=[$os1]"
fi
! grep -q -- '--confirm' "$SPYLOG" && ok "(ac4 spy) the helper never passes --confirm" || no "(ac4 spy) --confirm reached the checker"
! grep -q 'confirm_env=1' "$SPYLOG" && ok "(ac4 spy) an ambient RULES_CHECK_CONFIRM=1 never reaches the checker" \
  || no "(ac4 spy) RULES_CHECK_CONFIRM leaked to the checker"
[ ! -e "$DECOYLOG" ] && ok "(ac4 spy) the checker is resolved as a sibling — a PATH decoy is never called" \
  || no "(ac4 spy) the PATH decoy was invoked: $(cat "$DECOYLOG")"
: > "$SPYLOG"
os2="$( cd "$RS" && HOME="$HS" RULES_CHECK_NO_CMD=1 bash "$SPY/rules-gate-verdict.sh" --root "$RS" </dev/null 2>/dev/null )"
if [ "$(vf "$os2" .verdict)" = "cmd_disabled" ] && grep -q 'argv=--list-selected' "$SPYLOG" && ! grep -q -- '--if-stamped' "$SPYLOG"; then
  ok "(ac4 spy) RULES_CHECK_NO_CMD=1: verdict cmd_disabled and --if-stamped is NEVER invoked"
else
  no "(ac4 spy) no-cmd: log=[$(cat "$SPYLOG")] out=[$os2]"
fi

# ============================================================================
echo "== (ac6) --list-gateable fixtures: exact classification lines, executes nothing, exit 0 =="
R6="$(new_repo r6)"; H6="$(new_home 6)"
CANARY6="$R6/CANARY6"; rm -f "$CANARY6"
seed_rules "$R6" \
  "$(rule_objb a1 'grep -q init f' '[]')" \
  "$(rule_obj a2-absent 'grep -q init f')" \
  "$(rule_objb a2-null 'grep -q init f' 'null')" \
  "$(rule_objb b 'bash scripts/lint.sh' '[]')" \
  "$(rule_objb c 'bash scripts/lint.sh' '["scripts/lint.sh"]')" \
  "$(rule_objb d 'scripts/hb.sh' '[]')" \
  "$(rule_objb e 'bash untracked.sh' '[]')" \
  "$(rule_objb f-abs 'true' '["/etc/passwd"]')" \
  "$(rule_objb f-dotdot 'true' '["scripts/../f"]')" \
  "$(rule_objb f-tilde 'true' '["~/f"]')" \
  "$(rule_objb f-untracked 'true' '["untracked.sh"]')" \
  "$(rule_objb f-nonarray 'true' '"scripts/lint.sh"')" \
  "$(rule_objb f-nonstring 'true' '[1]')" \
  "$(rule_objb g-interp 'python3 scripts/plain.py' '["scripts/plain.py"]')" \
  "$(rule_objb g-interp-unbound 'python3 scripts/plain.py' '[]')" \
  "$(rule_objb g-noninterp 'cat scripts/plain.py' '[]')" \
  "$(rule_objb g-quoted "bash './scripts/lint.sh'" '["scripts/lint.sh"]')" \
  "$(rule_objb g-two 'bash scripts/lint.sh && scripts/hb.sh' '["scripts/lint.sh"]')" \
  "$(rule_objb canary "touch $CANARY6" '[]')"
o6="$(lg "$R6" "$H6")"; rc6=$?
[ "$rc6" -eq 0 ] && ok "(ac6) --list-gateable exits 0" || no "(ac6) rc=$rc6"
[ ! -e "$CANARY6" ] && ok "(ac6) executes NOTHING (the canary check did not run)" || no "(ac6) a check RAN under --list-gateable"
lg_line() { grep -F -- "$1$TAB" <<<"$o6" | grep -- "^$1$TAB" ; }
exp6() {  # exp6 <id> <class> <reason>
  local got; got="$(lg_line "$1")"
  [ "$got" = "$1$TAB$2$TAB$3" ] && ok "(ac6 $1) $2 / $3" || no "(ac6 $1) expected [$1<TAB>$2<TAB>$3] got [$got]"
}
exp6 a1 countable no_invocations
exp6 a2-absent advisory binds_undeclared
exp6 a2-null advisory binds_undeclared
exp6 b advisory unbound:scripts/lint.sh
exp6 c countable bound:1
exp6 d advisory unbound:scripts/hb.sh
exp6 e countable no_invocations
exp6 f-abs advisory binds_invalid
exp6 f-dotdot advisory binds_invalid
exp6 f-tilde advisory binds_invalid
exp6 f-untracked advisory binds_invalid
exp6 f-nonarray advisory binds_invalid
exp6 f-nonstring advisory binds_invalid
exp6 g-interp countable bound:1
exp6 g-interp-unbound advisory unbound:scripts/plain.py
exp6 g-noninterp countable no_invocations
exp6 g-quoted countable bound:1
exp6 g-two advisory unbound:scripts/hb.sh
exp6 canary countable no_invocations
[ "$(nlines "$o6")" -eq 19 ] && ok "(ac6) exactly one line per selected id (19)" || no "(ac6) $(nlines "$o6") lines: [$o6]"
[ "$o6" = "$(printf '%s\n' "$o6" | LC_ALL=C sort)" ] && ok "(ac6) lines are LC_ALL=C sorted" || no "(ac6) not sorted"
sel6="$( cd "$R6" && HOME="$H6" bash "$CHECKER" --list-selected </dev/null 2>/dev/null )"
[ "$(printf '%s\n' "$o6" | cut -f1)" = "$sel6" ] && ok "(ac6) the id column equals --list-selected exactly" || no "(ac6) id column differs from --list-selected"
for combo in "--list-gateable --confirm" "--confirm --list-gateable" "--no-cmd --if-stamped --confirm --list-gateable"; do
  # shellcheck disable=SC2086 — word-splitting the combo into argv is the point.
  oc="$( cd "$R6" && HOME="$H6" RULES_CHECK_CONFIRM=1 bash "$CHECKER" $combo </dev/null 2>/dev/null )"; rcc=$?
  [ "$rcc" -eq 0 ] && [ "$oc" = "$o6" ] && [ ! -e "$CANARY6" ] && [ ! -e "$H6/$STAMP_REL" ] \
    && ok "(ac6) '$combo' (+ ambient confirm) => same listing, nothing executed, no stamp written" \
    || no "(ac6) '$combo' rc=$rcc canary=$([ -e "$CANARY6" ] && echo PRESENT || echo absent)"
done
ols="$( cd "$R6" && HOME="$H6" bash "$CHECKER" --list-selected --list-gateable </dev/null 2>/dev/null )"
[ "$ols" = "$sel6" ] && ok "(ac6) --list-selected wins over --list-gateable when both are given" || no "(ac6) precedence: [$ols]"
RE="$(new_repo r6empty)"
oe="$(lg "$RE" "$H6")"; rce=$?
[ -z "$oe" ] && [ "$rce" -eq 0 ] && ok "(ac6) no store => EMPTY stdout, exit 0 (no 'Checks passed: 0/0' leak)" || no "(ac6) empty store: rc=$rce out=[$oe]"
# Positive control: the SAME store under a plain --confirm DOES run the canary check.
confirm "$R6" "$H6"
[ -e "$CANARY6" ] && ok "(ac6) positive control: plain --confirm on the same store DOES create the canary" \
  || no "(ac6) positive control broken: --confirm did not create the canary — the canary legs are VACUOUS"
rm -f "$CANARY6"

# ============================================================================
echo "== (ac7) caveat (d): editing a BOUND file after stamping => unstamped; an unbound rule is never counted =="
R7="$(new_repo r7)"; H7="$(new_home 7)"
seed_rules "$R7" "$(rule_objb c 'bash scripts/lint.sh' '["scripts/lint.sh"]')"
confirm "$R7" "$H7"
o7a="$(verdict "$H7" "$R7" --root "$R7")"
[ "$(vf "$o7a" .verdict)" = "fail" ] && has_id "$o7a" failing c && ok "(ac7a) fixture (c) stamped + failing => verdict fail" \
  || no "(ac7a) out=[$o7a]"
# The "PR" commit: scripts/lint.sh now exits 0 — the check WOULD pass, but the bound content moved.
( cd "$R7" && printf '#!/bin/sh\nexit 0\n' > scripts/lint.sh && git commit -qam "pr: make lint pass" ) >/dev/null 2>&1
( cd "$R7" && bash scripts/lint.sh ) && ok "(ac7b pre) after the edit the check itself would PASS" || no "(ac7b pre) lint.sh still fails — fixture broken"
raw7="$(ifs "$R7" "$H7")"
[ "$raw7" = "$(printf '  [SKIP] all (unstamped)\nChecks passed: 0/0')" ] \
  && ok "(ac7b) --if-stamped prints '[SKIP] all (unstamped)' — the bound file's content is in the hash" \
  || no "(ac7b) raw=[$raw7]"
o7b="$(verdict "$H7" "$R7" --root "$R7")"
[ "$(vf "$o7b" .verdict)" = "unstamped" ] && has_id "$o7b" countable c \
  && ok "(ac7b) verdict unstamped (c still countable) — the edit could NOT turn the failure into a counted pass" \
  || no "(ac7b) out=[$o7b]"
confirm "$R7" "$H7"
o7c="$(verdict "$H7" "$R7" --root "$R7")"
[ "$(vf "$o7c" .verdict)" = "ok" ] && ok "(ac7c) a human re-confirm re-stamps the edited bound file: verdict ok" || no "(ac7c) out=[$o7c]"
# Fixture (b): unbound (binds: [] but the check invokes scripts/lint.sh), stamped and FAILING.
R7b="$(new_repo r7b)"; H7b="$(new_home 7b)"
seed_rules "$R7b" "$(rule_objb b 'bash scripts/lint.sh' '[]')"
confirm "$R7b" "$H7b"
o7d="$(verdict "$H7b" "$R7b" --root "$R7b")"
if [ "$(vf "$o7d" .verdict)" = "none" ] && [ "$(vf "$o7d" '.advisory[] | select(.id == "b") | .reason')" = "unbound:scripts/lint.sh" ] \
   && [ "$(vf "$o7d" '.countable | length')" = "0" ]; then
  ok "(ac7d) fixture (b) stamped + failing => verdict none, b under advisory with reason unbound:scripts/lint.sh"
else
  no "(ac7d) out=[$o7d]"
fi
# Mixed store: a passing countable rule + the failing advisory rule => ok, the advisory FAIL is REPORTED only.
R7m="$(new_repo r7m)"; H7m="$(new_home 7m)"
seed_rules "$R7m" "$(rule_objb ok-c 'true' '[]')" "$(rule_objb b 'bash scripts/lint.sh' '[]')"
confirm "$R7m" "$H7m"
o7e="$(verdict "$H7m" "$R7m" --root "$R7m")"
if [ "$(vf "$o7e" .verdict)" = "ok" ] && has_id "$o7e" failing b && has_id "$o7e" passed ok-c && [ "$(vf "$o7e" .checks_passed)" = "1/2" ]; then
  ok "(ac7e) mixed store: the advisory id's FAIL is reported in failing but the verdict is ok (never counted)"
else
  no "(ac7e) out=[$o7e]"
fi
# ...and a failing countable + a failing advisory => fail, both reported.
R7f="$(new_repo r7f)"; H7f="$(new_home 7f)"
seed_rules "$R7f" "$(rule_objb bad-c 'false' '[]')" "$(rule_objb b 'bash scripts/lint.sh' '[]')"
confirm "$R7f" "$H7f"
o7f="$(verdict "$H7f" "$R7f" --root "$R7f")"
[ "$(vf "$o7f" .verdict)" = "fail" ] && has_id "$o7f" failing bad-c && has_id "$o7f" failing b \
  && ok "(ac7f) failing countable + failing advisory => fail, both in failing" || no "(ac7f) out=[$o7f]"
# (ac7g) the all-advisory store still REPLAYS for the report line (today's `passed n/m` survives), but
# the replay's FAIL never leaves `none`.
has_id "$o7d" failing b && [ "$(vf "$o7d" .checks_passed)" = "0/1" ] \
  && ok "(ac7g) all-advisory stamped store: b reported in failing, checks_passed \"0/1\" — verdict still none" \
  || no "(ac7g) out=[$o7d]"
# (ac7h) stub checker — an all-advisory listing: a FAIL replay, a trailer-less replay, an empty replay
# and RULES_CHECK_NO_CMD=1 all stay `none`; the no-cmd leg never invokes --if-stamped.
mkadv() {  # mkadv <dir> <ifstamped-printf-fmt>
  mkdir -p "$1"; cp "$HELPER" "$1/rules-gate-verdict.sh"; cp "$LIB" "$1/rules-replay-lib.sh"
  printf '#!/usr/bin/env bash\necho "$*" >> "%s/calls.log"\ncase "$1" in\n  --list-selected) echo x ;;\n  --list-gateable) printf '"'"'x\\tadvisory\\tbinds_undeclared\\n'"'"' ;;\n  --gate-state) printf '"'"'store\\tok\\nstamp\\tabsent\\n'"'"' ;;\n  --if-stamped) printf '"'"'%s'"'"' ;;\nesac\nexit 0\n' "$1" "$2" > "$1/rules-check.sh"
  chmod +x "$1/rules-check.sh"
}
R7h="$(new_repo r7h)"; H7h="$(new_home 7h)"
for leg in "fail|  [RUN ] x: false\n  [FAIL] x\nChecks passed: 0/1\n" "notrailer|  [RUN ] x: true\n  [PASS] x\n" "empty|"; do
  lname="${leg%%|*}"; lfmt="${leg#*|}"
  mkadv "$ROOT/adv-$lname" "$lfmt"
  oa="$( cd "$R7h" && HOME="$H7h" bash "$ROOT/adv-$lname/rules-gate-verdict.sh" --root "$R7h" </dev/null 2>/dev/null )"
  [ "$(vf "$oa" .verdict)" = "none" ] && json_ok "$oa" && [ "$(vf "$oa" '.countable | length')" = "0" ] \
    && ok "(ac7h $lname) all-advisory listing + a '$lname' replay => verdict none" || no "(ac7h $lname) out=[$oa]"
done
mkadv "$ROOT/adv-nocmd" '  [RUN ] x: false\n  [FAIL] x\nChecks passed: 0/1\n'
oan="$( cd "$R7h" && HOME="$H7h" RULES_CHECK_NO_CMD=1 bash "$ROOT/adv-nocmd/rules-gate-verdict.sh" --root "$R7h" </dev/null 2>/dev/null )"
if [ "$(vf "$oan" .verdict)" = "none" ] && grep -qx -- '--list-gateable' "$ROOT/adv-nocmd/calls.log" \
   && ! grep -q -- '--if-stamped' "$ROOT/adv-nocmd/calls.log"; then
  ok "(ac7h nocmd) all-advisory + RULES_CHECK_NO_CMD=1 => none (countable==[] ranks above cmd_disabled), --if-stamped never invoked"
else
  no "(ac7h nocmd) out=[$oan] calls=[$(cat "$ROOT/adv-nocmd/calls.log" 2>/dev/null)]"
fi
grep -qx -- '--if-stamped' "$ROOT/adv-fail/calls.log" \
  && ok "(ac7h control) without the valve the all-advisory helper DOES replay (the nocmd leg is not vacuous)" \
  || no "(ac7h control) calls=[$(cat "$ROOT/adv-fail/calls.log" 2>/dev/null)]"
# (ac7i) mixed listing + a trailer failure => verdict unresolved, ONLY the countable id listed (D-b).
MX="$ROOT/mixed-trailer"; mkdir -p "$MX"; cp "$HELPER" "$MX/rules-gate-verdict.sh"; cp "$LIB" "$MX/rules-replay-lib.sh"
cat > "$MX/rules-check.sh" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  --list-selected) printf 'adv\ncnt\n' ;;
  --list-gateable) printf 'adv\tadvisory\tbinds_undeclared\ncnt\tcountable\tno_invocations\n' ;;
  --gate-state) printf 'store\tok\nstamp\trecorded\ncountable\tcnt\n' ;;
  --if-stamped) printf '  [RUN ] adv: true\n  [PASS] adv\n  [RUN ] cnt: true\n  [PASS] cnt\n' ;;
esac
exit 0
EOF
chmod +x "$MX/rules-check.sh"
omx="$( cd "$R7h" && HOME="$H7h" bash "$MX/rules-gate-verdict.sh" --root "$R7h" </dev/null 2>/dev/null )"
[ "$(vf "$omx" .verdict)" = "unresolved" ] && [ "$(vf "$omx" '.unresolved | join(",")')" = "cnt" ] && [ "$(vf "$omx" .checks_passed)" = "null" ] \
  && ok "(ac7i) trailer missing on a mixed store => unresolved lists ONLY the countable id, checks_passed null" \
  || no "(ac7i) out=[$omx]"

# ============================================================================
echo "== (ac8) binds-free stores hash + print BYTE-IDENTICALLY under the pre-change checker; independent hash =="
PRE="$ROOT/pre"; mkdir -p "$PRE"
PREFIX="$(git -C "$SCRIPT_DIR" rev-parse --show-prefix 2>/dev/null)"
if git -C "$SCRIPT_DIR" show "HEAD:${PREFIX}rules-check.sh" > "$PRE/rules-check.sh" 2>/dev/null && [ -s "$PRE/rules-check.sh" ]; then
  HAVE_PRE=1
  ok "(ac8 pre) the HEAD revision of rules-check.sh is available for the before/after comparison"
else
  HAVE_PRE=0
  echo "  note: (ac8) git show HEAD:rules-check.sh unavailable — before/after legs skipped; the independent-hash legs still run"
fi
for variant in absent null empty; do
  RA="$(new_repo "r8-$variant")"; HA="$(new_home "8a-$variant")"; HB="$(new_home "8b-$variant")"
  case "$variant" in
    absent) seed_rules "$RA" "$(rule_obj v-one 'true')" "$(rule_obj v-two 'false')" ;;
    null)   seed_rules "$RA" "$(rule_objb v-one 'true' 'null')" "$(rule_objb v-two 'false' 'null')" ;;
    empty)  seed_rules "$RA" "$(rule_objb v-one 'true' '[]')" "$(rule_objb v-two 'false' '[]')" ;;
  esac
  # Independent recomputation — jq+sha256 in THIS test over `[id, check] | @tsv` only (no binds term).
  T8="$ROOT/hash-$variant"
  { jq -cn '{id:"v-one", check:"true"}'; jq -cn '{id:"v-two", check:"false"}'; } \
    | jq -r '[.id, .check] | @tsv' | LC_ALL=C sort > "$T8"
  exp8="$(_t_sha256_file "$T8")"
  key8="$( cd "$RA" && cd "$(git rev-parse --git-common-dir)" && pwd -P )"
  outB="$( cd "$RA" && HOME="$HB" bash "$CHECKER" --confirm </dev/null 2>/dev/null )"; rcB=$?
  hashB="$(jq -r --arg k "$key8" '.[$k].hash // ""' "$HB/$STAMP_REL" 2>/dev/null)"
  [ -n "$hashB" ] && [ "$hashB" = "$exp8" ] \
    && ok "(ac8 $variant) the CURRENT checker's stamp hash equals the independent id/check-only hash (no binds term)" \
    || no "(ac8 $variant) current hash=[$hashB] independent=[$exp8]"
  replB="$( cd "$RA" && HOME="$HB" bash "$CHECKER" --if-stamped </dev/null 2>/dev/null )"; rrB=$?
  [ "$(printf '%s\n' "$replB" | tail -n 1)" = "Checks passed: 1/2" ] && [ "$rrB" -eq 1 ] \
    && ok "(ac8 $variant) --if-stamped replays the set (1/2, rc 1)" || no "(ac8 $variant) replay=[$replB] rc=$rrB"
  if [ "$HAVE_PRE" -eq 1 ]; then
    outA="$( cd "$RA" && HOME="$HA" bash "$PRE/rules-check.sh" --confirm </dev/null 2>/dev/null )"; rcA=$?
    hashA="$(jq -r --arg k "$key8" '.[$k].hash // ""' "$HA/$STAMP_REL" 2>/dev/null)"
    replA="$( cd "$RA" && HOME="$HA" bash "$PRE/rules-check.sh" --if-stamped </dev/null 2>/dev/null )"; rrA=$?
    [ "$outA" = "$outB" ] && [ "$rcA" -eq "$rcB" ] && ok "(ac8 $variant) --confirm stdout + rc byte-identical pre/post" \
      || no "(ac8 $variant) --confirm differs: pre=[$outA] post=[$outB]"
    [ -n "$hashA" ] && [ "$hashA" = "$hashB" ] && ok "(ac8 $variant) the written stamp hash is byte-identical pre/post (existing stamps stay valid)" \
      || no "(ac8 $variant) hash pre=[$hashA] post=[$hashB]"
    [ "$replA" = "$replB" ] && [ "$rrA" -eq "$rrB" ] && ok "(ac8 $variant) --if-stamped stdout + rc byte-identical pre/post" \
      || no "(ac8 $variant) --if-stamped differs: pre=[$replA] post=[$replB]"
  fi
done
# Cross-validity: a stamp written by the PRE-change checker is honoured by the CURRENT --if-stamped.
if [ "$HAVE_PRE" -eq 1 ]; then
  RX="$(new_repo r8x)"; HX="$(new_home 8x)"
  seed_rules "$RX" "$(rule_obj x-one 'true')"
  ( cd "$RX" && HOME="$HX" bash "$PRE/rules-check.sh" --confirm </dev/null >/dev/null 2>&1 )
  ox="$(verdict "$HX" "$RX" --root "$RX")"
  [ "$(vf "$ox" .verdict)" = "none" ] && [ "$(vf "$ox" '.advisory[0].reason')" = "binds_undeclared" ] \
    && ok "(ac8 x) a binds-free rule stamped by the PRE-change checker: still stamped, but advisory (binds_undeclared) => verdict none" \
    || no "(ac8 x) out=[$ox]"
  replX="$( cd "$RX" && HOME="$HX" bash "$CHECKER" --if-stamped </dev/null 2>/dev/null )"
  [ "$(printf '%s\n' "$replX" | tail -n 1)" = "Checks passed: 1/1" ] \
    && ok "(ac8 x) the current --if-stamped honours the pre-change stamp (replays 1/1)" || no "(ac8 x) replay=[$replX]"
fi

# ============================================================================
echo "== (ac10) forgery legs => every countable id unresolved, verdict never ok =="
echo "  -- (i) embedded '  [PASS] <own id>' + the real FAIL; (iv) forged unstamped line beside a [RUN ] line"
RF="$(new_repo rf)"; HF="$(new_home f)"
seed_rules "$RF" \
  "$(rule_objb f-conflict 'false
  [PASS] f-conflict' '[]')" \
  "$(rule_objb f-skip 'false
  [SKIP] all (unstamped)' '[]')"
confirm "$RF" "$HF"
rawf="$(ifs "$RF" "$HF")"
if grep -qxF '  [PASS] f-conflict' <<<"$rawf" && grep -qxF '  [SKIP] all (unstamped)' <<<"$rawf" && grep -q '^  \[RUN \] ' <<<"$rawf"; then
  ok "(ac10 pre) the stamped replay really carries the forged PASS and the forged unstamped line beside RUN lines"
else
  no "(ac10 pre) forgery fixture not exercised: [$rawf]"
fi
of="$(verdict "$HF" "$RF" --root "$RF")"
[ "$(vf "$of" .verdict)" != "ok" ] && [ "$(vf "$of" .verdict)" != "unstamped" ] && ok "(ac10) verdict is neither ok nor unstamped: $(vf "$of" .verdict)" \
  || no "(ac10) verdict=[$(vf "$of" .verdict)]"
has_id "$of" unresolved f-conflict && ok "(ac10 i) the pre-printed PASS + real FAIL => f-conflict unresolved (never passed)" \
  || no "(ac10 i) out=[$of]"
has_id "$of" failing f-skip && ok "(ac10 iv) the forged unstamped line beside a RUN line does not hide f-skip's FAIL" \
  || no "(ac10 iv) out=[$of]"
[ "$(vf "$of" .verdict)" = "fail" ] && ok "(ac10) a countable FAIL outranks an unresolved: verdict fail" || no "(ac10) verdict=[$(vf "$of" .verdict)]"

echo "  -- (ii) pre-print-then-kill with a forged COMPLETE trailer"
RK="$(new_repo rk)"; HK="$(new_home k)"
KCHECK='kill $PPID
  [PASS] 0b
  [PASS] a
Checks passed: 2/2'
seed_rules "$RK" "$(rule_objb 0b 'true' '[]')" "$(rule_objb a "$KCHECK" '[]')"
# Hand-written stamp (a --confirm run is killed before its own stamp write) with rules-check.sh's own
# key + hash derivation: physical git-common-dir; sha256 of the sorted `[id,check]|@tsv` lines — a
# `binds: []` rule contributes NO binds term, so this derivation is still exact — plus the `countable`
# set a genuine --confirm records (both ids are `binds: []` + no invocations ⇒ countable).
KKEY="$( cd "$RK" && cd "$(git rev-parse --git-common-dir)" && pwd -P )"
{ jq -cn '{id:"0b", check:"true"}'; jq -cn --arg c "$KCHECK" '{id:"a", check:$c}'; } \
  | jq -r '[.id, .check] | @tsv' | LC_ALL=C sort > "$ROOT/k-hash-input"
KHASH="$(_t_sha256_file "$ROOT/k-hash-input")"
mkdir -p "$(dirname "$HK/$STAMP_REL")"
jq -n --arg k "$KKEY" --arg h "$KHASH" '{($k): {git_common_dir:$k, repo_root:"x", hash:$h, ts:"2000-01-01T00:00:00Z", countable:["0b","a"]}}' > "$HK/$STAMP_REL"
rawk="$(ifs "$RK" "$HK")"; rck=$?
if [ "$(printf '%s\n' "$rawk" | tail -n 1)" = "Checks passed: 2/2" ] && grep -qxF '  [PASS] a' <<<"$rawk" \
   && ! grep -qxF '  [FAIL] a' <<<"$rawk" && [ "$rck" -ne 0 ] && [ "$rck" -ne 1 ]; then
  ok "(ac10 ii pre) the replay ends in the FORGED 'Checks passed: 2/2', carries a forged '[PASS] a', no real FAIL, rc=$rck"
else
  no "(ac10 ii pre) fixture not exercising the forged trailer: rc=$rck out=[$rawk]"
fi
ok10="$(verdict "$HK" "$RK" --root "$RK")"
[ "$(vf "$ok10" .verdict)" = "unresolved" ] && has_id "$ok10" unresolved a && has_id "$ok10" unresolved 0b \
  && [ "$(vf "$ok10" .checks_passed)" = "null" ] \
  && ok "(ac10 ii) forged complete trailer after a signal death => verdict unresolved, BOTH ids unresolved, checks_passed null" \
  || no "(ac10 ii) out=[$ok10]"

echo "  -- (M) a trailer whose M differs from the listed count (stub checker)"
SPYM="$ROOT/spym"; mkdir -p "$SPYM"
cp "$HELPER" "$SPYM/rules-gate-verdict.sh"
cp "$LIB" "$SPYM/rules-replay-lib.sh"
cat > "$SPYM/rules-check.sh" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  --list-selected) echo x ;;
  --list-gateable) printf 'x\tcountable\tno_invocations\n' ;;
  --gate-state) printf 'store\tok\nstamp\trecorded\ncountable\tx\n' ;;
  --if-stamped) printf '  [RUN ] x: true\n  [PASS] x\nChecks passed: 1/2\n' ;;
esac
exit 0
EOF
chmod +x "$SPYM/rules-check.sh"
RM="$(new_repo rmis)"; HM="$(new_home mis)"
om="$( cd "$RM" && HOME="$HM" bash "$SPYM/rules-gate-verdict.sh" --root "$RM" </dev/null 2>/dev/null )"
[ "$(vf "$om" .verdict)" = "unresolved" ] && has_id "$om" unresolved x \
  && ok "(ac10 M) 'Checks passed: 1/2' with ONE listed id => x unresolved, verdict unresolved (PASS line notwithstanding)" \
  || no "(ac10 M) out=[$om]"

# ============================================================================
echo "== (unr) the unreadable legs and the none legs =="
RU="$(new_repo ru)"; HU="$(new_home u)"
seed_rules "$RU" "$(rule_objb u-c 'true' '[]')"
confirm "$RU" "$HU"
unr() {  # unr <label> <json> — verdict must be unreadable, one JSON line
  [ "$(vf "$2" .verdict)" = "unreadable" ] && json_ok "$2" && ok "(unr) $1 => unreadable" || no "(unr) $1 => [$2]"
}
o="$(verdict "$HU" "$RU" --root "$ROOT/does-not-exist")"; unr "a bad --root" "$o"
o="$(verdict "$HU" "$RU" --root)"; unr "--root with no value" "$o"
o="$(verdict "$HU" "$RU" --rot "$RU")"; unr "an unrecognized argument (never judges the wrong tree)" "$o"
NG="$ROOT/nongit"; mkdir -p "$NG"; seed_rules "$NG" "$(rule_objb ng 'true' '[]')"
o="$( cd "$ROOT" && GIT_CEILING_DIRECTORIES="$ROOT" HOME="$HU" bash "$HELPER" --root "$NG" </dev/null 2>/dev/null )"; unr "a non-git dir" "$o"
NC="$ROOT/nochecker"; mkdir -p "$NC"; cp "$HELPER" "$NC/rules-gate-verdict.sh"; cp "$LIB" "$NC/rules-replay-lib.sh"
o="$( cd "$RU" && HOME="$HU" bash "$NC/rules-gate-verdict.sh" --root "$RU" </dev/null 2>/dev/null )"; unr "sibling rules-check.sh absent" "$o"
NL="$ROOT/nolib"; mkdir -p "$NL"; cp "$HELPER" "$NL/rules-gate-verdict.sh"; cp "$CHECKER" "$NL/rules-check.sh"
o="$( cd "$RU" && HOME="$HU" bash "$NL/rules-gate-verdict.sh" --root "$RU" </dev/null 2>/dev/null )"; unr "sibling rules-replay-lib.sh absent (fail-CLOSED source, unlike the worker helper)" "$o"
mkstub() {  # mkstub <dir> <gateable-printf-fmt> <ifstamped-printf-fmt> [<gatestate-printf-fmt>]
  mkdir -p "$1"; cp "$HELPER" "$1/rules-gate-verdict.sh"; cp "$LIB" "$1/rules-replay-lib.sh"
  printf '#!/usr/bin/env bash\ncase "$1" in\n  --list-selected) echo x ;;\n  --list-gateable) printf '"'"'%s'"'"' ;;\n  --gate-state) printf '"'"'%s'"'"' ;;\n  --if-stamped) printf '"'"'%s'"'"' ;;\nesac\nexit 0\n' "$2" "${4:-store\\tok\\nstamp\\trecorded\\ncountable\\tx\\n}" "$3" > "$1/rules-check.sh"
  chmod +x "$1/rules-check.sh"
}
mkstub "$ROOT/st-malformed" 'x\n' '  [RUN ] x: true\n  [PASS] x\nChecks passed: 1/1\n'
o="$( cd "$RU" && HOME="$HU" bash "$ROOT/st-malformed/rules-gate-verdict.sh" --root "$RU" </dev/null 2>/dev/null )"; unr "a malformed --list-gateable line (no class/reason)" "$o"
mkstub "$ROOT/st-mismatch" 'y\tcountable\tno_invocations\n' '  [RUN ] x: true\n  [PASS] x\nChecks passed: 1/1\n'
o="$( cd "$RU" && HOME="$HU" bash "$ROOT/st-mismatch/rules-gate-verdict.sh" --root "$RU" </dev/null 2>/dev/null )"; unr "a --list-gateable id set that differs from --list-selected" "$o"
mkstub "$ROOT/st-badclass" 'x\tmaybe\tno_invocations\n' '  [RUN ] x: true\n  [PASS] x\nChecks passed: 1/1\n'
o="$( cd "$RU" && HOME="$HU" bash "$ROOT/st-badclass/rules-gate-verdict.sh" --root "$RU" </dev/null 2>/dev/null )"; unr "an unknown class word" "$o"
mkstub "$ROOT/st-empty" 'x\tcountable\tno_invocations\n' ''
o="$( cd "$RU" && HOME="$HU" bash "$ROOT/st-empty/rules-gate-verdict.sh" --root "$RU" </dev/null 2>/dev/null )"; unr "an EMPTY --if-stamped stdout" "$o"
mkstub "$ROOT/st-ok" 'x\tcountable\tno_invocations\n' '  [RUN ] x: true\n  [PASS] x\nChecks passed: 1/1\n'
o="$( cd "$RU" && HOME="$HU" bash "$ROOT/st-ok/rules-gate-verdict.sh" --root "$RU" </dev/null 2>/dev/null )"
[ "$(vf "$o" .verdict)" = "ok" ] && ok "(unr control) the same stub shape with a well-formed listing + replay => ok (the unreadable legs are not vacuous)" || no "(unr control) [$o]"
RN="$(new_repo rnone)"
o="$(verdict "$HU" "$RN" --root "$RN")"
[ "$(vf "$o" .verdict)" = "none" ] && [ "$(vf "$o" '.selected | length')" = "0" ] && json_ok "$o" && ok "(none) no store => verdict none, selected []" || no "(none) no store: [$o]"
seed_rules "$RN" "$(rule_obj adv-only 'false')"
o="$(verdict "$HU" "$RN" --root "$RN")"
[ "$(vf "$o" .verdict)" = "none" ] && has_id "$o" selected adv-only && [ "$(vf "$o" '.advisory[0].reason')" = "binds_undeclared" ] \
  && ok "(none) an all-advisory store => verdict none, the id listed under advisory (reported, never counted)" || no "(none) advisory-only: [$o]"

# ============================================================================
echo "== (m1) MUTATION CONTROL: delete the lib's M == listed comparison => the (M) leg flips to ok =="
MUT1="$ROOT/mut1"; mkdir -p "$MUT1"
cp "$HELPER" "$MUT1/rules-gate-verdict.sh"; cp "$SPYM/rules-check.sh" "$MUT1/rules-check.sh"
sed 's/ && \[ "\$_m" -eq "\$_listed_n" \]//' "$LIB" > "$MUT1/rules-replay-lib.sh"
if [ ! -s "$MUT1/rules-replay-lib.sh" ] || cmp -s "$LIB" "$MUT1/rules-replay-lib.sh" \
   || ! bash -n "$MUT1/rules-replay-lib.sh" 2>/dev/null || [ "$(vf "$om" .verdict)" != "unresolved" ]; then
  no "(m1) mutant gate: mutant empty, identical, bash -n dirty, or the positive control failed"
else
  om1="$( cd "$RM" && HOME="$HM" bash "$MUT1/rules-gate-verdict.sh" --root "$RM" </dev/null 2>/dev/null )"
  [ "$(vf "$om1" .verdict)" = "ok" ] && ok "(m1) mutant lib without the trailer-count check says ok on the mismatched trailer (the check is live)" \
    || no "(m1) mutant still says $(vf "$om1" .verdict) — the (M) leg is VACUOUS"
fi

# ============================================================================
echo "== (m2) MUTATION CONTROL: the helper treats advisory ids as countable => the (ac7d) leg flips =="
MUT2="$ROOT/mut2"; mkdir -p "$MUT2"
cp "$CHECKER" "$MUT2/rules-check.sh"; cp "$LIB" "$MUT2/rules-replay-lib.sh"
sed 's/^    countable) COUNTABLE=/    countable|advisory) COUNTABLE=/' "$HELPER" > "$MUT2/rules-gate-verdict.sh"
if [ ! -s "$MUT2/rules-gate-verdict.sh" ] || cmp -s "$HELPER" "$MUT2/rules-gate-verdict.sh" \
   || ! bash -n "$MUT2/rules-gate-verdict.sh" 2>/dev/null || [ "$(vf "$o7d" .verdict)" != "none" ]; then
  no "(m2) mutant gate: mutant empty, identical, bash -n dirty, or the positive control failed"
else
  om2="$( cd "$R7b" && HOME="$H7b" bash "$MUT2/rules-gate-verdict.sh" --root "$R7b" </dev/null 2>/dev/null )"
  # The mutant's live countable set ({b}) differs from the one the stamp recorded ({}), so the
  # countable-set binding answers `unstamped` before the replay; either way the verdict leaves `none`.
  case "$(vf "$om2" .verdict)" in
    fail|unstamped) ok "(m2) mutant counting advisory ids leaves none on fixture (b): $(vf "$om2" .verdict) (countability is live)" ;;
    *) no "(m2) mutant still says $(vf "$om2" .verdict) — the (ac7d) leg is VACUOUS" ;;
  esac
fi

# ============================================================================
echo "== (m3) MUTATION CONTROL: the checker collapses [] and an absent binds => (ac6 a2) flips =="
MUT3="$ROOT/mut3"; mkdir -p "$MUT3"
sed 's/if has("binds") then {binds: .binds} else {} end/{binds: (.binds \/\/ [])}/' "$CHECKER" > "$MUT3/rules-check.sh"
if [ ! -s "$MUT3/rules-check.sh" ] || cmp -s "$CHECKER" "$MUT3/rules-check.sh" \
   || ! bash -n "$MUT3/rules-check.sh" 2>/dev/null || [ "$(lg_line a2-absent)" != "a2-absent${TAB}advisory${TAB}binds_undeclared" ]; then
  no "(m3) mutant gate: mutant empty, identical, bash -n dirty, or the positive control failed"
else
  om3="$( cd "$R6" && HOME="$H6" bash "$MUT3/rules-check.sh" --list-gateable </dev/null 2>/dev/null | grep "^a2-absent$TAB" )"
  [ "$om3" = "a2-absent${TAB}countable${TAB}no_invocations" ] \
    && ok "(m3) mutant with \`// []\` promotes the undeclared rule to countable (the has(\"binds\") distinction is live)" \
    || no "(m3) mutant output [$om3] — the (ac6 a2) leg is VACUOUS"
fi

# ============================================================================
echo "== (cs) the countable-set binding: which rules COUNT is tied to the human confirmation =="
# cs_repo <name> <home> — a repo with a tracked data file + the base store (cs-fail countable+failing,
# cs-ok countable+passing), confirmed by a genuine --confirm; prints the repo path.
cs_repo() {
  local r; r="$(new_repo "$1")"
  printf 'hello\n' > "$r/data.txt"
  ( cd "$r" && git add data.txt && git commit -qm data ) >/dev/null 2>&1
  seed_rules "$r" "$(rule_objb cs-fail 'grep -q nomatch data.txt' '[]')" "$(rule_objb cs-ok 'true' '[]')"
  confirm "$r" "$2"
  printf '%s' "$r"
}
not_ok_none() {  # not_ok_none <label> <json> <expected-verdict>
  local v; v="$(vf "$2" .verdict)"
  if [ "$v" = "$3" ] && json_ok "$2"; then ok "(cs) $1 => verdict $v (never ok/none)"; else no "(cs) $1 => [$2] (expected $3)"; fi
}
HC="$(new_home cs)"
RC0="$(cs_repo rcs0 "$HC")"
oc0="$(verdict "$HC" "$RC0" --root "$RC0")"
[ "$(vf "$oc0" .verdict)" = "fail" ] && has_id "$oc0" failing cs-fail \
  && ok "(cs pre) positive control: the stamped store's verdict is fail (cs-fail countable + failing)" || no "(cs pre) out=[$oc0]"
key_cs() { ( cd "$1" && cd "$(git rev-parse --git-common-dir)" && pwd -P ); }
[ "$(jq -c --arg k "$(key_cs "$RC0")" '.[$k].countable' "$HC/$STAMP_REL" 2>/dev/null)" = '["cs-fail","cs-ok"]' ] \
  && ok "(cs pre) the genuine --confirm recorded countable [\"cs-fail\",\"cs-ok\"] beside the hash" \
  || no "(cs pre) stamp=[$(cat "$HC/$STAMP_REL" 2>/dev/null)]"
raw0="$(ifs "$RC0" "$HC")"
# (1) drop `binds: []` — hashes exactly like before, so the replay still runs; the id is no longer countable.
H1c="$(new_home cs1)"; R1c="$(cs_repo rcs1 "$H1c")"
seed_rules "$R1c" "$(rule_obj cs-fail 'grep -q nomatch data.txt')" "$(rule_objb cs-ok 'true' '[]')"
[ "$(printf '%s\n' "$(ifs "$R1c" "$H1c")" | tail -n 1)" = "Checks passed: 1/2" ] \
  && ok "(cs 1 pre) the hash did NOT move (the replay still runs 1/2) — only the countable set can catch this" \
  || no "(cs 1 pre) replay=[$(ifs "$R1c" "$H1c")]"
oc1="$(verdict "$H1c" "$R1c" --root "$R1c")"; not_ok_none "(1) binds:[] dropped from the failing rule" "$oc1" unstamped
# (2) `binds` made a non-array string.
H2c="$(new_home cs2)"; R2c="$(cs_repo rcs2 "$H2c")"
seed_rules "$R2c" "$(rule_objb cs-fail 'grep -q nomatch data.txt' '"data.txt"')" "$(rule_objb cs-ok 'true' '[]')"
oc2="$(verdict "$H2c" "$R2c" --root "$R2c")"; not_ok_none "(2) binds set to a string" "$oc2" unstamped
# (3) chmod +x on the data file the binds:[] grep-check reads — the rule turns `unbound`, the hash does not move.
H3c="$(new_home cs3)"; R3c="$(cs_repo rcs3 "$H3c")"
seed_rules "$R3c" "$(rule_objb cs-fail 'grep -q nomatch data.txt' '[]')"
confirm "$R3c" "$H3c"
[ "$(vf "$(verdict "$H3c" "$R3c" --root "$R3c")" .verdict)" = "fail" ] && ok "(cs 3 pre) single-rule store stamped: fail" || no "(cs 3 pre) not fail"
chmod +x "$R3c/data.txt"
[ "$(lg "$R3c" "$H3c")" = "cs-fail${TAB}advisory${TAB}unbound:data.txt" ] && ok "(cs 3 pre) +x demoted cs-fail to unbound" || no "(cs 3 pre) lg=[$(lg "$R3c" "$H3c")]"
oc3="$(verdict "$H3c" "$R3c" --root "$R3c")"; not_ok_none "(3) chmod +x on the data file" "$oc3" unstamped
# (4) must -> should on the LAST countable rule (the rule leaves the selection entirely).
H4c="$(new_home cs4)"; R4c="$(cs_repo rcs4 "$H4c")"
seed_rules "$R4c" "$(rule_objb cs-fail 'grep -q nomatch data.txt' '[]')"
confirm "$R4c" "$H4c"
seed_rules "$R4c" "$(rule_objb cs-fail 'grep -q nomatch data.txt' '[]' | jq -c '.enforcement = "should"')"
oc4="$(verdict "$H4c" "$R4c" --root "$R4c")"; not_ok_none "(4) must->should on the last countable rule" "$oc4" unstamped
# (5) a corrupted rules JSON file.
H5c="$(new_home cs5)"; R5c="$(cs_repo rcs5 "$H5c")"
printf '[{"id": "cs-fail",\n' > "$R5c/.agent/rules/r.json"
oc5="$(verdict "$H5c" "$R5c" --root "$R5c")"; not_ok_none "(5) corrupted rules JSON" "$oc5" unreadable
printf '{"not":"an array"}\n' > "$R5c/.agent/rules/r.json"
oc5b="$(verdict "$H5c" "$R5c" --root "$R5c")"; not_ok_none "(5b) a rules file that is valid JSON but not an array" "$oc5b" unreadable
# (6) a stamp that predates the `countable` field (the hash still matches) over a countable store.
H6c="$(new_home cs6)"; R6c="$(cs_repo rcs6 "$H6c")"
jq 'with_entries(.value |= del(.countable))' "$H6c/$STAMP_REL" > "$H6c/stamp.tmp" && mv "$H6c/stamp.tmp" "$H6c/$STAMP_REL"
[ "$(printf '%s\n' "$(ifs "$R6c" "$H6c")" | tail -n 1)" = "Checks passed: 1/2" ] \
  && ok "(cs 6 pre) the pre-field stamp's hash still matches (the replay runs)" || no "(cs 6 pre) replay=[$(ifs "$R6c" "$H6c")]"
oc6="$(verdict "$H6c" "$R6c" --root "$R6c")"; not_ok_none "(6) a stamp without a recorded countable set, countable ids present" "$oc6" unstamped
# ...a legacy stamp over an EMPTY countable set (binds-free store) keeps today's none.
H6n="$(new_home cs6n)"; R6n="$(new_repo rcs6n)"
seed_rules "$R6n" "$(rule_obj adv 'false')"
confirm "$R6n" "$H6n"
jq 'with_entries(.value |= del(.countable))' "$H6n/$STAMP_REL" > "$H6n/stamp.tmp" && mv "$H6n/stamp.tmp" "$H6n/$STAMP_REL"
[ "$(vf "$(verdict "$H6n" "$R6n" --root "$R6n")" .verdict)" = "none" ] \
  && ok "(cs 6n) a legacy stamp over a binds-free (all-advisory) store is still none — that path is unchanged" || no "(cs 6n) not none"
# A re-confirm OVERWRITES the recorded set (vector 1's tree): the human accepted the new classification.
confirm "$R1c" "$H1c"
[ "$(jq -c --arg k "$(key_cs "$R1c")" '.[$k].countable' "$H1c/$STAMP_REL" 2>/dev/null)" = '["cs-ok"]' ] \
  && [ "$(vf "$(verdict "$H1c" "$R1c" --root "$R1c")" .verdict)" = "ok" ] \
  && ok "(cs re-confirm) a human re-confirm rewrites countable to [\"cs-ok\"] and the verdict follows it (ok)" \
  || no "(cs re-confirm) stamp=[$(cat "$H1c/$STAMP_REL" 2>/dev/null)]"
# --gate-state is a read-only listing: executes nothing, writes no stamp, exits 0.
HG="$(new_home csg)"; RG="$(new_repo rcsg)"; CANG="$RG/CANARYG"
seed_rules "$RG" "$(rule_objb g "touch $CANG" '[]')"
og="$( cd "$RG" && HOME="$HG" RULES_CHECK_CONFIRM=1 bash "$CHECKER" --gate-state --confirm </dev/null 2>/dev/null )"; rcg=$?
[ "$rcg" -eq 0 ] && [ "$og" = "$(printf 'store\tok\nstamp\tabsent')" ] && [ ! -e "$CANG" ] && [ ! -e "$HG/$STAMP_REL" ] \
  && ok "(cs gate-state) --gate-state (+ --confirm + ambient confirm) prints store/stamp only, runs nothing, writes no stamp" \
  || no "(cs gate-state) rc=$rcg out=[$og] canary=$([ -e "$CANG" ] && echo PRESENT || echo absent)"

# ============================================================================
echo "== (m4) MUTATION CONTROL: delete the recorded-vs-live countable comparison => (cs 1) flips to ok =="
MUT4="$ROOT/mut4"; mkdir -p "$MUT4"
cp "$CHECKER" "$MUT4/rules-check.sh"; cp "$LIB" "$MUT4/rules-replay-lib.sh"
sed 's/if \[ "\$_sorted_rec" != "\$_sorted_cnt" \]; then/if false; then/' "$HELPER" > "$MUT4/rules-gate-verdict.sh"
if [ ! -s "$MUT4/rules-gate-verdict.sh" ] || cmp -s "$HELPER" "$MUT4/rules-gate-verdict.sh" \
   || ! bash -n "$MUT4/rules-gate-verdict.sh" 2>/dev/null || [ "$(vf "$oc1" .verdict)" != "unstamped" ]; then
  no "(m4) mutant gate: mutant empty, identical, bash -n dirty, or the positive control failed"
else
  # A fresh copy of vector (1) — the (cs re-confirm) leg above re-stamped R1c.
  H1m="$(new_home cs1m)"; R1m="$(cs_repo rcs1m "$H1m")"
  seed_rules "$R1m" "$(rule_obj cs-fail 'grep -q nomatch data.txt')" "$(rule_objb cs-ok 'true' '[]')"
  om4="$( cd "$R1m" && HOME="$H1m" bash "$MUT4/rules-gate-verdict.sh" --root "$R1m" </dev/null 2>/dev/null )"
  [ "$(vf "$om4" .verdict)" = "ok" ] && ok "(m4) without the comparison, dropping binds:[] turns a stamped FAIL into ok (the comparison is load-bearing)" \
    || no "(m4) mutant says $(vf "$om4" .verdict) — the (cs 1) leg is VACUOUS"
fi

# ============================================================================
echo "== (ur) unstamped_reason names WHY the verdict is unstamped (message text for gate-eval, never a decision input) =="
# ur_is <label> <json> <expected-reason>
ur_is() {
  if [ "$(vf "$2" .verdict)" = "unstamped" ] && [ "$(vf "$2" .unstamped_reason)" = "$3" ] && json_ok "$2"; then
    ok "(ur) $1 => unstamped_reason $3"
  else no "(ur) $1 => [$2] (expected unstamped / $3)"; fi
}
ur_is "(ac3a) stamp absent" "$o3a" never_confirmed
ur_is "(ac3c) one-byte edit after stamping" "$o3c" never_confirmed
ur_is "(cs 1) binds:[] dropped (countable set drifted)" "$oc1" countable_set_drift
ur_is "(cs 4) must->should on the last countable rule (drift to ZERO live countable)" "$oc4" countable_set_drift
[ "$(vf "$oc4" '.countable | length')" = "0" ] \
  && ok "(ur) (cs 4) is the drift-with-zero-live-countable case the gate-eval message must not render as \"0 … never confirmed\"" \
  || no "(ur) (cs 4) countable=[$(vf "$oc4" .countable)] — fixture no longer exercises zero live countable"
ur_is "(cs 6) legacy stamp over a countable store" "$oc6" legacy_stamp
{ [ "$(vf "$o1" 'has("unstamped_reason")')" = "false" ] && [ "$(vf "$oc0" 'has("unstamped_reason")')" = "false" ]; } \
  && ok "(ur) a non-unstamped verdict (fail) carries no unstamped_reason key" || no "(ur) unstamped_reason leaked onto a fail verdict"

# --- APPEND NEW SECTIONS ABOVE THIS LINE (keep the RESULT footer last) ---
echo ""
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
