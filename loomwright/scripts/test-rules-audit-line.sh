#!/usr/bin/env bash
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
# test-rules-audit-line.sh — self-tests for rules-audit-line.sh (the Phase 4.5 rules-store audit line)
# and for audit-rules.sh's REVISIT TRIGGER (automate-followups/09). Every behavioural leg runs in a
# SANDBOX: its own `git init` repo under `mktemp -d`, its own HOME, stdin </dev/null — never this
# checkout's store.
#
# Covers (AC numbers are the brief's):
#   AC1  STATIC PIN — self-heal-advisory/SKILL.md invokes the helper in its RUNTIME form (the quoted
#        plugin-install-root prefix, $INVOKE), with a gated delete-the-line mutant and an MROOT mutant
#        that strips the prefix to the developer-side `scripts/…` form; both must make the pin FAIL.
#   AC2  a `must` rule with `check: null` ⇒ `rules_audit: findings 1 (no_mechanism)`, store unchanged.
#   AC3  an advisory-only store, and a tree with NO .agent/rules/, ⇒ `rules_audit: clean`.
#   AC4  could-not-examine is NEVER clean: (a) validator absent (engine rc 2), (b) unreadable rule file,
#        (c) a stub engine whose rc and header disagree, (d) the engine absent ⇒ `unexamined`; plus the
#        `# CLEAN-PREDICATE` mutation control (a mutant that also accepts rc 2 flips (a) to clean).
#   AC5  the `rules_gate_trigger:` line on BOTH surfaces, its negative legs, exit-code neutrality, a
#        CANARY proving no `check` executes, and the proposed file's hash unchanged.
#   AC7  the helper's CODE lines carry no `bash -c` / `eval ` / `rules-check.sh` / `.agent/rules` /
#        `.check` (comment-only hits allowed).
#   Every helper invocation must exit 0.
#
# Fixtures follow test-audit-rules.sh's known-clean rule shape (valid ISO provenance.added, a real
# provenance.source, applies_to null, a committed tree) — otherwise the engine records UNKNOWN (rc 2)
# and every positive leg would read `unexamined`.
#
# Portability: bash 3.2 (macOS) + Linux; no GNU-only flags, no mapfile, no sed -i.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
HELPER="$HERE/rules-audit-line.sh"
ENGINE="$HERE/audit-rules.sh"
PROPOSED_REL=".supervisor/requirements/proposed/automate-followups-08-setup-rules-ci-offer.md"
TRIGGER_PREFIX="rules_gate_trigger: 1 must rule(s) now carry a check — $PROPOSED_REL"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass + 1)); }
no() { echo "  FAIL: $1"; fail=$((fail + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "test-rules-audit-line: jq absent — audit-rules.sh requires jq. Skipping behavioural legs."
  echo "RESULT: 0 passed, 0 failed (jq absent, vacuous)"
  exit 0
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/rules-audit-line.XXXXXX")" || { echo "mktemp failed"; exit 1; }
trap 'chmod -R u+rwX "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"

ISO="2026-01-01T00:00:00Z"
ADV_RULE='{"id":"p-adv","category":"process","statement":"prefer the narrow probe over the unrequested sweep in review pr-138","enforcement":"advisory","check":null,"provenance":{"source":"pr-138","added":"'"$ISO"'"},"applies_to":null}'
MUST_NULL='{"id":"p-must-null","category":"process","statement":"every gate names its own failure reason in review pr-138","enforcement":"must","check":null,"provenance":{"source":"pr-138","added":"'"$ISO"'"},"applies_to":null}'
MUST_WS='{"id":"p-must-ws","category":"process","statement":"every gate names its own failure reason in review pr-138","enforcement":"must","check":"   ","provenance":{"source":"pr-138","added":"'"$ISO"'"},"applies_to":null}'
# must_canary <repo> — a `must` rule whose check WOULD create <repo>/CANARY if anything executed it.
must_canary() {
  printf '%s' '{"id":"p-must-ck","category":"process","statement":"every gate names its own failure reason in review pr-138","enforcement":"must","check":"touch '"$1"'/CANARY","provenance":{"source":"pr-138","added":"'"$ISO"'"},"applies_to":null}'
}

# new_repo — a sandbox git repo with one committed file. Prints its path.
new_repo() {
  local r; r="$(mktemp -d "$TMP/repo.XXXXXX")"
  (
    cd "$r" || exit 1
    git init -q && git config user.email t@t && git config user.name t
    echo a > README.md && git add -A && git commit -qm init
  ) >/dev/null 2>&1 </dev/null
  printf '%s' "$r"
}
# seed <repo> <json-array-body>
seed() { mkdir -p "$1/.agent/rules"; printf '[%s]\n' "$2" > "$1/.agent/rules/process.json"; }
# propose <repo> — create the parked item-08 file.
propose() { mkdir -p "$1/$(dirname "$PROPOSED_REL")"; printf '# parked item 08\n' > "$1/$PROPOSED_REL"; }
# hash_store <repo> — a sorted per-file content hash of .agent/rules/*.json.
hash_store() {
  local f
  for f in "$1"/.agent/rules/*.json; do
    [ -e "$f" ] || continue
    printf '%s %s\n' "$(basename "$f")" "$(cksum < "$f")"
  done | env LC_ALL=C sort
}
# line <helper> <root> — run a helper; sets OUT and RC.
line() { OUT="$(bash "$1" --root "$2" </dev/null 2>/dev/null)"; RC=$?; }
# audit <root> — run the engine; sets AOUT and ARC.
audit() { AOUT="$(bash "$ENGINE" --root "$1" </dev/null 2>/dev/null)"; ARC=$?; }

# expect_line <label> <expected-stdout>
expect_line() {
  if [ "$RC" -eq 0 ] && [ "$OUT" = "$2" ]; then ok "$1"
  else no "$1 — rc=$RC stdout=[$OUT] expected=[$2]"; fi
}

echo "== AC1: Phase 4.5 prose pin (runtime invocation form) =="
SKILL_REL="loomwright/skills/self-heal-advisory/SKILL.md"
INVOKE='bash "${CLAUDE_PLUGIN_ROOT}/scripts/rules-audit-line.sh" --root'
# pin_ok <skill-file> — the invocation, the one-line contract and all three states are present.
pin_ok() {
  local f="$1" n
  [ -r "$f" ] || return 1
  grep -qF -- "$INVOKE" "$f" || return 1
  grep -qF -- '### Rules-store audit' "$f" || return 1
  for n in 'rules_audit: clean' 'rules_audit: findings' 'rules_audit: unexamined' 'heal_decision` is unchanged'; do
    grep -qF -- "$n" "$f" || return 1
  done
  return 0
}
if pin_ok "$REPO/$SKILL_REL"; then ok "AC1 self-heal-advisory pins the runtime invocation + three states"
else no "AC1 self-heal-advisory is missing the rules-audit-line invocation / state trace"; fi
c="$(grep -c 'audit-rules\|rules-audit-line' "$REPO/$SKILL_REL")"
if [ "$c" -ge 1 ]; then ok "AC1 grep -c audit-rules|rules-audit-line = $c (>= 1)"; else no "AC1 grep count is 0"; fi
# gated mutants: positive control on an unmutated copy first.
cp "$REPO/$SKILL_REL" "$TMP/skill.orig"
if pin_ok "$TMP/skill.orig"; then
  grep -vF -- "$INVOKE" "$TMP/skill.orig" > "$TMP/skill.mdel"
  if [ ! -s "$TMP/skill.mdel" ] || cmp -s "$TMP/skill.mdel" "$TMP/skill.orig"; then no "AC1 MDEL mutant empty or unchanged (gate)"
  elif pin_ok "$TMP/skill.mdel"; then no "AC1 MDEL deleting the invocation line left the pin passing"
  else ok "AC1 MDEL deleting the invocation line fails the pin"; fi
  sed 's|"${CLAUDE_PLUGIN_ROOT}/scripts/rules-audit-line.sh"|scripts/rules-audit-line.sh|' "$TMP/skill.orig" > "$TMP/skill.mroot"
  if [ ! -s "$TMP/skill.mroot" ] || cmp -s "$TMP/skill.mroot" "$TMP/skill.orig"; then no "AC1 MROOT mutant empty or unchanged (gate)"
  elif pin_ok "$TMP/skill.mroot"; then no "AC1 MROOT a repo-relative helper path left the pin passing"
  else ok "AC1 MROOT the repo-relative helper path fails the pin (the runtime prefix is load-bearing)"; fi
else
  no "AC1 positive control: the unmutated copy fails the pin"
fi

echo "== AC2: no_mechanism => findings, store byte-identical =="
r="$(new_repo)"; seed "$r" "$MUST_NULL"
before="$(hash_store "$r")"
line "$HELPER" "$r"; expect_line "AC2 must+check:null => findings 1 (no_mechanism)" "rules_audit: findings 1 (no_mechanism)"
if [ -n "$before" ] && [ "$before" = "$(hash_store "$r")" ]; then ok "AC2 store hash identical before/after"
else no "AC2 store hash changed (or empty)"; fi

echo "== AC3: clean =="
r="$(new_repo)"; seed "$r" "$ADV_RULE"
line "$HELPER" "$r"; expect_line "AC3 advisory-only store => clean" "rules_audit: clean"
r="$(new_repo)"
line "$HELPER" "$r"; expect_line "AC3 no .agent/rules/ dir => clean (small-N)" "rules_audit: clean"

echo "== AC4: could-not-examine is never clean =="
r4="$(new_repo)"; seed "$r4" "$ADV_RULE"
OUT="$(AUDIT_RULES_VALIDATOR="$TMP/does-not-exist.sh" bash "$HELPER" --root "$r4" </dev/null 2>/dev/null)"; RC=$?
expect_line "AC4(a) validator absent (engine rc 2) => unexamined" "rules_audit: unexamined"
# (b) unreadable rule file
rb="$(new_repo)"; seed "$rb" "$ADV_RULE"; chmod 000 "$rb/.agent/rules/process.json"
if [ -r "$rb/.agent/rules/process.json" ]; then
  echo "  SKIP: AC4(b) the chmod 000 file is still readable (running as root)"
else
  line "$HELPER" "$rb"; expect_line "AC4(b) unreadable rule file => unexamined" "rules_audit: unexamined"
fi
chmod 644 "$rb/.agent/rules/process.json" 2>/dev/null
# (c) stub engine: rc 0 but BLOCKING (3); and rc 1 with BLOCKING (0); and a duplicated header.
stub() {  # stub <dir> <rc> <body> — a temp helper copy beside a stub audit-rules.sh
  mkdir -p "$1"; cp "$HELPER" "$1/rules-audit-line.sh"
  printf '#!/usr/bin/env bash\nprintf %%s %q\nexit %s\n' "$3" "$2" > "$1/audit-rules.sh"
}
stub "$TMP/stubc" 0 $'## Findings — BLOCKING (3)\n\n  [no_mechanism] rule: x\n'
line "$TMP/stubc/rules-audit-line.sh" "$r4"; expect_line "AC4(c) stub rc 0 + BLOCKING (3) => unexamined" "rules_audit: unexamined"
stub "$TMP/stubc2" 1 $'## Findings — BLOCKING (0)\n'
line "$TMP/stubc2/rules-audit-line.sh" "$r4"; expect_line "AC4(c) stub rc 1 + BLOCKING (0) => unexamined" "rules_audit: unexamined"
stub "$TMP/stubc3" 0 $'## Findings — BLOCKING (0)\n## Findings — BLOCKING (0)\n'
line "$TMP/stubc3/rules-audit-line.sh" "$r4"; expect_line "AC4(c) stub duplicated header => unexamined" "rules_audit: unexamined"
stub "$TMP/stubc4" 0 ''
line "$TMP/stubc4/rules-audit-line.sh" "$r4"; expect_line "AC4(c) stub empty output => unexamined" "rules_audit: unexamined"
stub "$TMP/stubc5" 1 $'## Findings — BLOCKING (2)\n\n  [dead_rule] rule: a\n  [dangling_supersedes] rule: b\n  [dead_rule] rule: c\n\n## Findings — ADVISORY (1)\n\n  [dead_reference] rule: d\n'
line "$TMP/stubc5/rules-audit-line.sh" "$r4"; expect_line "stub rc 1 + two kinds => sorted, de-duplicated, BLOCKING-only kinds" "rules_audit: findings 2 (dangling_supersedes, dead_rule)"
stub "$TMP/stubc6" 1 $'## Findings — BLOCKING (1)\n\n  garbled\n'
line "$TMP/stubc6/rules-audit-line.sh" "$r4"; expect_line "stub rc 1 + no parsable kind => unparsed" "rules_audit: findings 1 (unparsed)"
# (d) engine absent beside a helper copy
mkdir -p "$TMP/noengine"; cp "$HELPER" "$TMP/noengine/rules-audit-line.sh"
line "$TMP/noengine/rules-audit-line.sh" "$r4"; expect_line "AC4(d) engine absent => unexamined" "rules_audit: unexamined"
# bad args are fail-safe too
OUT="$(bash "$HELPER" --bogus </dev/null 2>/dev/null)"; RC=$?
expect_line "unknown argument => unexamined, exit 0" "rules_audit: unexamined"
# Mutation control on the # CLEAN-PREDICATE line: also accept rc 2 ⇒ leg (a) must flip to clean.
mkdir -p "$TMP/mut"; cp "$ENGINE" "$TMP/mut/audit-rules.sh"; cp "$HERE/validate-entry.sh" "$TMP/mut/validate-entry.sh" 2>/dev/null
sed '/# CLEAN-PREDICATE/s/; then LINE1="rules_audit: clean"/ || [ "$RC" -eq 2 ]; then LINE1="rules_audit: clean"/' "$HELPER" > "$TMP/mut/rules-audit-line.sh"
if [ ! -s "$TMP/mut/rules-audit-line.sh" ] || cmp -s "$TMP/mut/rules-audit-line.sh" "$HELPER" || ! bash -n "$TMP/mut/rules-audit-line.sh"; then
  no "AC4 CLEAN-PREDICATE mutant empty, unchanged or unparsable (gate)"
else
  OUT="$(AUDIT_RULES_VALIDATOR="$TMP/does-not-exist.sh" bash "$HELPER" --root "$r4" </dev/null 2>/dev/null)"
  MOUT="$(AUDIT_RULES_VALIDATOR="$TMP/does-not-exist.sh" bash "$TMP/mut/rules-audit-line.sh" --root "$r4" </dev/null 2>/dev/null)"
  if [ "$OUT" = "rules_audit: unexamined" ] && [ "$MOUT" = "rules_audit: clean" ]; then
    ok "AC4 mutation control: accepting rc 2 in CLEAN-PREDICATE flips leg (a) to clean (unmutated: unexamined)"
  else
    no "AC4 mutation control did not flip — unmutated=[$OUT] mutant=[$MOUT]"
  fi
fi

echo "== AC5: rules_gate_trigger on both surfaces =="
# count_trigger <text> — number of column-0 lines starting rules_gate_trigger:
count_trigger() { printf '%s\n' "$1" | grep -c '^rules_gate_trigger: '; }
rt="$(new_repo)"; seed "$rt" "$(must_canary "$rt")"; propose "$rt"
phash_before="$(cksum < "$rt/$PROPOSED_REL")"
audit "$rt"; rc_with="$ARC"
if [ "$(count_trigger "$AOUT")" = "1" ] && grep -qF -- "$TRIGGER_PREFIX" <<<"$AOUT" \
   && grep -qx '## Revisit triggers' <<<"$AOUT"; then
  ok "AC5 audit-rules.sh prints exactly one column-0 rules_gate_trigger line under ## Revisit triggers"
else no "AC5 audit-rules.sh trigger line missing or duplicated (rc $ARC)"; fi
tline="$(printf '%s\n' "$AOUT" | grep '^rules_gate_trigger: ' | head -n 1)"
if [ "$(printf '%s\n' "$AOUT" | grep -n '^## Revisit triggers$' | cut -d: -f1)" -lt "$(printf '%s\n' "$AOUT" | grep -n '^## Store integrity$' | cut -d: -f1)" ] 2>/dev/null; then
  ok "AC5 ## Revisit triggers precedes ## Store integrity"
else no "AC5 ## Revisit triggers is not before ## Store integrity"; fi
line "$HELPER" "$rt"
l1="$(printf '%s\n' "$OUT" | sed -n 1p)"; l2="$(printf '%s\n' "$OUT" | sed -n 2p)"; nl="$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
if [ "$RC" -eq 0 ] && [ "$l1" = "rules_audit: clean" ] && [ -n "$tline" ] && [ "$l2" = "$tline" ] && [ "$nl" = "2" ]; then
  ok "AC5 rules-audit-line.sh echoes the same trigger line as line 2"
else no "AC5 helper line 2 mismatch — rc=$RC out=[$OUT] expected line2=[$tline]"; fi
rm -f "$rt/$PROPOSED_REL"
audit "$rt"; rc_without="$ARC"
if [ "$rc_with" = "$rc_without" ]; then ok "AC5 the trigger never changes audit-rules.sh's exit code ($rc_with == $rc_without)"
else no "AC5 exit code moved with the trigger: $rc_with vs $rc_without"; fi
if [ "$(count_trigger "$AOUT")" = "0" ] && ! grep -q '^## Revisit triggers' <<<"$AOUT"; then
  ok "AC5(ii) proposed file absent => no trigger (engine)"
else no "AC5(ii) trigger printed with the proposed file absent (engine)"; fi
line "$HELPER" "$rt"
if [ "$RC" -eq 0 ] && [ "$(count_trigger "$OUT")" = "0" ]; then ok "AC5(ii) proposed file absent => no trigger (helper)"
else no "AC5(ii) helper printed a trigger with the proposed file absent"; fi
propose "$rt"
if [ "$phash_before" = "$(cksum < "$rt/$PROPOSED_REL")" ]; then ok "AC5 proposed file content hash unchanged"; else no "AC5 proposed file changed"; fi
# (i) zero qualifying rules, proposed file present
for fx in MUST_NULL MUST_WS ADV_RULE; do
  case "$fx" in MUST_NULL) body="$MUST_NULL" ;; MUST_WS) body="$MUST_WS" ;; *) body="$ADV_RULE" ;; esac
  rn="$(new_repo)"; seed "$rn" "$body"; propose "$rn"
  audit "$rn"; line "$HELPER" "$rn"
  if [ "$(count_trigger "$AOUT")" = "0" ] && ! grep -q '^## Revisit triggers' <<<"$AOUT" \
     && [ "$(count_trigger "$OUT")" = "0" ] && [ "$RC" -eq 0 ]; then
    ok "AC5(i) $fx + proposed file => no trigger on either surface"
  else no "AC5(i) $fx printed a trigger (engine rc $ARC, helper [$OUT])"; fi
done
if [ ! -e "$rt/CANARY" ]; then ok "AC5 CANARY absent — no check was executed"; else no "AC5 CANARY exists — a check was EXECUTED"; fi

echo "== AC7: helper static invariants =="
hits="$(grep -nE 'bash -c|eval |rules-check\.sh|\.agent/rules|\.check\b' "$HELPER" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
if [ -z "$hits" ]; then ok "AC7 no bash -c / eval / rules-check.sh / .agent/rules / .check on a helper code line"
else no "AC7 forbidden token on a code line: $hits"; fi
redir="$(grep -nE '(>|>>) *"?\$ROOT' "$HELPER" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
if [ -z "$redir" ]; then ok "AC7 no write redirection into the audited root"
else no "AC7 helper redirects output into the audited root"; fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
