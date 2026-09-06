#!/usr/bin/env bash
# test-audit-rules.sh — self-tests for audit-rules.sh, the READ-ONLY correctness audit over the
# committed .agent/rules/ store. Runs the engine inside ISOLATED temp git repos via `mktemp -d` +
# `git init`, so it NEVER touches the real repo's store except for ONE deliberately read-only
# byte-identity assertion at the end. Mirrors the test-add-rule.sh / test-read-rules.sh harness
# convention: pass/fail counters, ok()/no() helpers, a "RESULT: N passed, M failed" tail, exit 1 on
# any failure (auto-registered by ci.yml's test-*.sh glob).
#
# THE SMALL-N PROBLEM THIS SUITE EXISTS TO SOLVE. The live store holds three rules, all `advisory`,
# all `check: null`. NOT ONE of the five store-wide conditions occurs in it naturally, so a suite
# that ran the engine over the live store would go green while proving nothing about any of them.
# Every store-wide assertion below therefore runs against a PURPOSE-BUILT FIXTURE store in a temp
# repo, and each one is MUTATION-CONTROLLED: the mechanism is deleted, the assertion is proven to go
# RED, and the mechanism is restored. An assertion that still passes with its mechanism deleted is
# vacuous, and this repo has shipped that defect before.
#
# Covers:
#   (a) the engine exists and parses.
#   (b) READ-ONLY POSTURE — static: no eval / `bash -c` / `source` of a rule's `check`, no write
#       primitive aimed at the store. Behavioural: `--fix` / `--write` / `--apply` are REFUSED
#       (not silently ignored), and every scenario leaves the store byte-identical (AC6).
#   (c) AC1 — the five SHARED checks are re-run per standing rule and the report names them.
#   (d) AC8 — the engine's OWN output states the store size and frames "0 findings" as a small-N
#       result. Asserted on the engine's stdout, not on a doc.
#   (e) AC2 — a `must` rule with `check: null` is reported as an enforcement claim with no mechanism.
#   (f) AC3 — an `applies_to` glob matching zero repo paths is reported as a rule that can never fire.
#   (g) AC4 — a `supersedes` naming an absent id is reported as a dangling target.
#   (h) AC5 — a rule superseded by a later rule is reported as dead.
#   (i) AC5b — a rule contradicted by a rule added AFTER it is reported (the drift case a write-time
#       gate structurally cannot ask).
#   (j) AC7 — NO code path executes a rule's `check`. Proven with a `check` whose value would create
#       a canary file, asserting the canary NEVER appears — plus a mutation control proving an
#       EXECUTING engine WOULD create it, so the absence assertion is not vacuous.
#   (k) AC9 — a missing / unparseable / truncated / sentinel-less validator makes the run report
#       UNEXAMINED and exit 2, never clean. Plus the `|| true` load-guard mutation control.
#   (l) AC10 — an rc-2 "could not decide" from a shared check surfaces as UNKNOWN and exits 2, never
#       as clean. Three-part: the correct one-line-per-rule corpus DECIDES; a wrong-shaped corpus
#       yields UNCOMPARABLE_SHAPE and is reported UNKNOWN; and a mutant that absorbs rc 2 as clean
#       goes green, proving the UNKNOWN assertion has a mechanism behind it.
#   (m) every recommendation names an EXISTING action (`/rules add --supersedes` / `--retract`).
#   (o) a CONCURRENT WRITER that ADDS or REMOVES a store file mid-run is DETECTED (the fingerprint
#       covers the re-enumerated file SET, not only the content of a once-enumerated list), with the
#       pre-fix once-enumerated fingerprint as the mutation control and a clean run as the converse.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$SCRIPT_DIR/audit-rules.sh"
VALIDATOR="$SCRIPT_DIR/validate-entry.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT" 2>/dev/null' EXIT
MUT="$ROOT/mutants"; mkdir -p "$MUT"

if ! command -v jq >/dev/null 2>&1; then
  echo "test-audit-rules: jq absent on this host — audit-rules.sh requires jq. Skipping data assertions."
  echo "RESULT: 0 passed, 0 failed (jq absent, vacuous)"
  exit 0
fi

# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------
# new_repo — a temp git repo with a small TRACKED tree. Tracked matters: the "glob matches zero repo
# paths" check reads `git ls-files`, deliberately (a committed rule scopes itself to the committed
# tree; an on-disk find would make the verdict depend on stray build artefacts).
new_repo() {
  local r; r="$(mktemp -d "$ROOT/repo.XXXXXX")"
  (
    cd "$r" || exit 1
    git init -q
    git config user.email t@t
    git config user.name t
    mkdir -p src docs
    echo a > src/alpha.ts
    echo b > src/beta.ts
    echo c > docs/guide.md
    echo d > CLAUDE.md
    git add -A
    git commit -qm init
  ) >/dev/null 2>&1
  printf '%s' "$r"
}

# seed_store <repo> <file-stem> <json>
# The fixtures are written DIRECTLY rather than through add-rule.sh, and that is deliberate: several
# of the conditions under test (a dangling supersedes, an unorderable timestamp, a `must` rule with a
# null check) are shapes the sole writer REFUSES to author. The audit's job is to find them in a
# store that already drifted, so the fixture has to be able to express a store that drifted.
seed_store() {
  local repo="$1" stem="$2" json="$3"
  mkdir -p "$repo/.agent/rules"
  printf '%s\n' "$json" > "$repo/.agent/rules/$stem.json"
}

# fingerprint <repo> — content of every store file, name-tagged, in LC_ALL=C order.
fingerprint() {
  local d="$1/.agent/rules" f
  [ -d "$d" ] || { printf 'NOSTORE'; return 0; }
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    printf '%s\n' "--- $f"
    cat "$f"
  done < <(LC_ALL=C find "$d" -type f 2>/dev/null | LC_ALL=C sort)
}

# run_audit <repo> [engine] [validator] — sets OUT and RC. Runs FROM INSIDE the repo so the engine's
# `git rev-parse --show-toplevel` resolves to the fixture, never to this checkout.
run_audit() {
  local repo="$1" engine="${2:-$ENGINE}" val="${3:-$VALIDATOR}"
  OUT="$( cd "$repo" && AUDIT_RULES_VALIDATOR="$val" bash "$engine" 2>&1 )"; RC=$?
}

# byte_identical <repo> <label> — the AC6 assertion, run after EVERY scenario rather than once.
byte_identical() {
  if [ "$(fingerprint "$1")" = "$2" ]; then ok "$3 — store byte-identical after the run (AC6)"
  else no "$3 — THE STORE CHANGED during a read-only audit run"; fi
}

# mutant_ok <file> <desc> — a mutation control that changed nothing, produced an empty file, or
# produced an unparseable script proves NOTHING. Gate every mutant on all three before crediting it.
mutant_ok() {
  if [ ! -s "$1" ];              then no "$2 — mutant is EMPTY (vacuous control)"; return 1; fi
  if cmp -s "$ENGINE" "$1";      then no "$2 — mutation changed NOTHING (vacuous control)"; return 1; fi
  if ! bash -n "$1" 2>/dev/null; then no "$2 — mutant does not parse (vacuous control)"; return 1; fi
  return 0
}

# code_only — the engine with comment-only lines removed, so a static assertion about what the code
# DOES is not satisfied (or falsified) by what a comment SAYS. This file's own header talks at length
# about `bash -c`; a naive grep over the whole file would be unaimable.
code_only() { grep -vE '^[[:space:]]*#' "$ENGINE"; }

ISO_A='2026-01-01T00:00:00Z'
ISO_B='2026-06-01T00:00:00Z'

# ============================================================================
echo "== (a) the engine exists and parses =="
[ -f "$ENGINE" ] && ok "audit-rules.sh exists" || no "audit-rules.sh MISSING ($ENGINE)"
bash -n "$ENGINE" 2>/dev/null && ok "audit-rules.sh parses" || no "audit-rules.sh does NOT parse"

# ============================================================================
echo "== (b) READ-ONLY posture: no write mode, no write flag, no check execution =="

# Static half 1 — no code path evals / bash -c's / sources anything. The engine sources the shared
# validator with `. "$VALIDATOR"`, which is the ONE dot-source it is allowed and is asserted below.
SRC_RE='\beval\b|bash -c|sh -c|(^|[[:space:];&|(]) *source +'
# `source` is anchored as a COMMAND, not as a word: `\bsource\b` also matches `provenance.source`
# and the validator's own `--source` flag, which would make this assertion unaimable.
if [ "$(code_only | grep -cE "$SRC_RE")" -eq 0 ]; then
  ok "(b1) no eval / bash -c / sh -c / source anywhere in the engine's code"
else
  no "(b1) the engine's code contains an execution primitive: $(code_only | grep -nE "$SRC_RE" | tr '\n' ' ')"
fi

# Static half 2 — the `check` value is read into $r_ckv and used ONLY as text. Every line mentioning
# it must be an assignment, a `case` glob (the whitespace-only lint) or a printf/diagnostic.
ckv_bad="$(code_only | grep -n 'r_ckv' | grep -vE 'read -r|r_ckv="|case "\$r_ckv"|printf|check=|block ' || true)"
if [ -z "$ckv_bad" ]; then
  ok "(b2) the \`check\` value is only ever assigned, case-matched and printed — never run"
else
  no "(b2) a line uses the \`check\` value in a non-textual position: $ckv_bad"
fi

# Static half 3 — no write primitive aimed at the store. (`rm -rf \"\$WORK\"` in the EXIT trap is the
# engine's own temp dir and is excluded by name, not by hand-waving.)
wr_bad="$(code_only | grep -nE '\b(rm|mv|cp|tee|truncate)\b' | grep -vE '\$WORK|rm -rf "\$WORK"' || true)"
if [ -z "$wr_bad" ]; then
  ok "(b3) no write primitive outside the engine's own temp work dir"
else
  no "(b3) a write primitive may reach outside the work dir: $wr_bad"
fi

# Static half 4 — the sanctioned load guard IS present, all three clauses, and `|| true` is NOT on
# the source line (the one line the contract forbids).
if grep -q '^  \. "\$VALIDATOR"$' "$ENGINE" \
   && grep -q '_ve_src_rc=\$?' "$ENGINE" \
   && grep -q 'for _vef in \$VALIDATOR_REQUIRED_FUNCS validate_entry_all' "$ENGINE" \
   && grep -q 'VALIDATE_ENTRY_CONTRACT_REQUIRED="validate-entry/2"' "$ENGINE"; then
  ok "(b4) the three-clause LOAD GUARD is present verbatim (captured source status; SEVEN names probed; hardcoded sentinel)"
else
  no "(b4) the LOAD GUARD is missing a clause — see validate-entry.sh's LOAD GUARD CONTRACT"
fi
if grep -nE '^\s*\. "\$VALIDATOR".*\|\| true' "$ENGINE" >/dev/null 2>&1; then
  no "(b5) '|| true' is on the source line — FORBIDDEN by the LOAD GUARD CONTRACT clause (i)"
else
  ok "(b5) '|| true' is NOT on the source line (LOAD GUARD clause (i))"
fi

# Static half 5 — the engine reimplements none of the five checks: it CALLS all five by name.
missing_calls=""
for fn in validate_duplicate validate_contradiction validate_provenance validate_dead_reference validate_cross_repo_reference; do
  code_only | grep -q "^ *$fn --entry" || missing_calls="$missing_calls $fn"
done
if [ -z "$missing_calls" ]; then
  ok "(b6) all FIVE shared checks are CALLED from validate-entry.sh (none reimplemented)"
else
  no "(b6) shared check(s) never called:$missing_calls"
fi

# Behavioural half — write-shaped flags are REFUSED, not ignored.
r="$(new_repo)"
seed_store "$r" "process" '[{"id":"p-1","category":"process","statement":"prefer the narrow probe over the unrequested sweep","enforcement":"advisory","check":null,"provenance":{"source":"pr-138","added":"'"$ISO_A"'"},"applies_to":null}]'
fp="$(fingerprint "$r")"
for flag in --fix --write --apply --confirm; do
  OUT="$( cd "$r" && AUDIT_RULES_VALIDATOR="$VALIDATOR" bash "$ENGINE" "$flag" 2>&1 )"; RC=$?
  if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'unknown option'; then
    ok "(b7) write-shaped flag '$flag' is REFUSED (exit $RC), not silently ignored"
  else
    no "(b7) write-shaped flag '$flag' was ACCEPTED (exit $RC) — a read-only engine must refuse it"
  fi
done
byte_identical "$r" "$fp" "(b8)"

# ============================================================================
echo "== (c)/(d) AC1 + AC8: the five shared checks are re-run, and the engine states its own small-N limit =="
r="$(new_repo)"
seed_store "$r" "process" '[
 {"id":"p-1","category":"process","statement":"prefer the narrow probe over the unrequested sweep in review pr-138","enforcement":"advisory","check":null,"provenance":{"source":"pr-138","added":"'"$ISO_A"'"},"applies_to":null},
 {"id":"p-2","category":"process","statement":"a schema change ships with the migration that applies it in issue #42","enforcement":"advisory","check":null,"provenance":{"source":"dreaming:auto-2026-01-02-abc123","added":"'"$ISO_B"'"},"applies_to":["src/*"]}
]'
fp="$(fingerprint "$r")"
run_audit "$r"
[ "$RC" -eq 0 ] && ok "(c1) a clean fixture store audits clean (exit 0)" \
                || no "(c1) a clean fixture store did not audit clean (exit $RC): $(printf '%s' "$OUT" | head -20)"
five_named=1
for tok in duplicate contradiction provenance dead-reference cross-repo; do
  printf '%s' "$OUT" | grep -q -- "$tok" || five_named=0
done
[ "$five_named" -eq 1 ] && ok "(c2) the report names all FIVE shared checks it re-ran (AC1)" \
                        || no "(c2) the report does not name all five shared checks"
printf '%s' "$OUT" | grep -q 'STANDING rules audited: 2' \
  && ok "(c3) the engine prints the store size (AC8)" \
  || no "(c3) the engine did not print the standing-rule count"
printf '%s' "$OUT" | grep -qi 'SMALL-N RESULT, NOT EVIDENCE THE STORE IS SOUND' \
  && ok "(c4) the engine's OWN output frames 0 findings as a small-N result, not soundness (AC8)" \
  || no "(c4) MISSING the small-N framing in the engine's own output"
printf '%s' "$OUT" | grep -q 'BYTE-IDENTICAL' \
  && ok "(c5) the engine asserts store byte-identity from its own run (AC6)" \
  || no "(c5) the engine does not state the byte-identity result"
byte_identical "$r" "$fp" "(c6)"

# ============================================================================
echo "== (e) AC2: a \`must\` rule with check:null is an enforcement claim with no mechanism =="
mk_no_mechanism() {
  local repo="$1"
  seed_store "$repo" "process" '[
   {"id":"p-must","category":"process","statement":"every gate names its own failure reason in review pr-138","enforcement":"must","check":null,"provenance":{"source":"pr-138","added":"'"$ISO_A"'"},"applies_to":null}
  ]'
}
r="$(new_repo)"; mk_no_mechanism "$r"; fp="$(fingerprint "$r")"
run_audit "$r"
if printf '%s' "$OUT" | grep -q '\[no_mechanism\]' && [ "$RC" -eq 1 ]; then
  ok "(e1) a must-rule with a null check is reported [no_mechanism] and the run exits 1"
else
  no "(e1) no_mechanism NOT reported (exit $RC)"
fi
printf '%s' "$OUT" | grep -q 'enforcement=must check=null' \
  && ok "(e2) the finding carries its EVIDENCE (the enforcement/check pair), not a bare verdict" \
  || no "(e2) the no_mechanism finding carries no evidence"
byte_identical "$r" "$fp" "(e3)"

# (e4) MUTATION CONTROL — break the null-check detector; (e1) must go RED.
sed -e 's/ck_empty=1$/ck_empty=0/' "$ENGINE" > "$MUT/no-mech.sh"
if mutant_ok "$MUT/no-mech.sh" "(e4) no_mechanism mutant" && ! cmp -s "$ENGINE" "$MUT/no-mech.sh"; then
  run_audit "$r" "$MUT/no-mech.sh"
  if ! printf '%s' "$OUT" | grep -q '\[no_mechanism\]' && [ "$RC" -eq 0 ]; then
    ok "(e4) MUTATION CONTROL: with the null-check detector broken the finding DISAPPEARS (exit 0) — (e1) is not vacuous"
  else
    no "(e4) MUTATION CONTROL: the mutant STILL reported no_mechanism (exit $RC) — (e1) may pass for another reason"
  fi
fi

# ============================================================================
echo "== (f) AC3: an applies_to glob matching zero repo paths is a rule that can never fire =="
r="$(new_repo)"
seed_store "$r" "process" '[
 {"id":"p-scope","category":"process","statement":"a renamed module keeps its rule scope in review pr-138","enforcement":"advisory","check":null,"provenance":{"source":"pr-138","added":"'"$ISO_A"'"},"applies_to":["legacy/removed-dir/*"]}
]'
fp="$(fingerprint "$r")"
run_audit "$r"
if printf '%s' "$OUT" | grep -q '\[never_fires\]' && [ "$RC" -eq 1 ]; then
  ok "(f1) a rule whose every glob matches zero tracked paths is reported [never_fires] (exit 1)"
else
  no "(f1) never_fires NOT reported (exit $RC)"
fi
printf '%s' "$OUT" | grep -q 'legacy/removed-dir/\*' \
  && ok "(f2) the finding names the offending glob as EVIDENCE" \
  || no "(f2) the never_fires finding does not name the glob"
# A glob that DOES match must NOT be reported — the check is not just "any applies_to is a finding".
r2="$(new_repo)"
seed_store "$r2" "process" '[
 {"id":"p-scope-ok","category":"process","statement":"a renamed module keeps its rule scope in review pr-138","enforcement":"advisory","check":null,"provenance":{"source":"pr-138","added":"'"$ISO_A"'"},"applies_to":["src/*"]}
]'
run_audit "$r2"
if ! printf '%s' "$OUT" | grep -q '\[never_fires\]' && [ "$RC" -eq 0 ]; then
  ok "(f3) a glob that DOES match tracked paths is NOT reported (the check discriminates)"
else
  no "(f3) a MATCHING glob was reported as never-firing (exit $RC) — false positive"
fi
byte_identical "$r" "$fp" "(f4)"

# (f5) MUTATION CONTROL — make the zero-match condition unreachable; (f1) must go RED.
sed -e 's/\[ "\$live_globs" -eq 0 \]/[ "$live_globs" -lt 0 ]/' "$ENGINE" > "$MUT/never-fires.sh"
if mutant_ok "$MUT/never-fires.sh" "(f5) never_fires mutant"; then
  run_audit "$r" "$MUT/never-fires.sh"
  if ! printf '%s' "$OUT" | grep -q '\[never_fires\]'; then
    ok "(f5) MUTATION CONTROL: with the zero-match condition unreachable the finding DISAPPEARS — (f1) is not vacuous"
  else
    no "(f5) MUTATION CONTROL: the mutant STILL reported never_fires — (f1) may pass for another reason"
  fi
fi

# ============================================================================
echo "== (g) AC4: a supersedes naming an absent id is a dangling target =="
r="$(new_repo)"
seed_store "$r" "process" '[
 {"id":"p-new","category":"process","statement":"a replacement rule names the rule it retires in review pr-138","enforcement":"advisory","check":null,"provenance":{"source":"pr-138","added":"'"$ISO_A"'"},"applies_to":null,"supersedes":"p-does-not-exist"}
]'
fp="$(fingerprint "$r")"
run_audit "$r"
if printf '%s' "$OUT" | grep -q '\[dangling_supersedes\]' && [ "$RC" -eq 1 ]; then
  ok "(g1) a supersedes naming an absent id is reported [dangling_supersedes] (exit 1)"
else
  no "(g1) dangling_supersedes NOT reported (exit $RC)"
fi
printf '%s' "$OUT" | grep -q 'p-does-not-exist' \
  && ok "(g2) the finding names the unresolved target as EVIDENCE" \
  || no "(g2) the dangling finding does not name the target"
byte_identical "$r" "$fp" "(g3)"

# (g4) MUTATION CONTROL — disable the jq DANGLE emitter's absence test; (g1) must go RED.
sed -e 's/select( (\$ok_ids | index(\$tgt)) == null )/select(false)/' "$ENGINE" > "$MUT/dangle.sh"
if mutant_ok "$MUT/dangle.sh" "(g4) dangling mutant"; then
  run_audit "$r" "$MUT/dangle.sh"
  if ! printf '%s' "$OUT" | grep -q '\[dangling_supersedes\]'; then
    ok "(g4) MUTATION CONTROL: with the absent-target test disabled the finding DISAPPEARS — (g1) is not vacuous"
  else
    no "(g4) MUTATION CONTROL: the mutant STILL reported dangling_supersedes — (g1) may pass for another reason"
  fi
fi

# ============================================================================
echo "== (h) AC5: a rule superseded by a later rule is dead =="
r="$(new_repo)"
seed_store "$r" "process" '[
 {"id":"p-old","category":"process","statement":"the release notes are assembled by hand each tagged build in review pr-100","enforcement":"advisory","check":null,"provenance":{"source":"pr-100","added":"'"$ISO_A"'"},"applies_to":null},
 {"id":"p-newer","category":"process","statement":"the release notes are generated from the changelog on each tagged build in review pr-138","enforcement":"advisory","check":null,"provenance":{"source":"pr-138","added":"'"$ISO_B"'"},"applies_to":null,"supersedes":"p-old"}
]'
fp="$(fingerprint "$r")"
run_audit "$r"
if printf '%s' "$OUT" | grep -q '\[dead_rule\]' && [ "$RC" -eq 1 ]; then
  ok "(h1) a rule hidden by a later rule's supersedes is reported [dead_rule] (exit 1)"
else
  no "(h1) dead_rule NOT reported (exit $RC)"
fi
printf '%s' "$OUT" | grep -q 'p-newer -> p-old' \
  && ok "(h2) the finding names the hiding EDGE as evidence (hider -> hidden)" \
  || no "(h2) the dead_rule finding does not name the supersedes edge"
printf '%s' "$OUT" | grep -q 'superseded / hidden from the reader: 1' \
  && ok "(h3) the store summary counts the hidden rule separately from the standing ones" \
  || no "(h3) the store summary does not count hidden rules"
byte_identical "$r" "$fp" "(h4)"

# (h5) MUTATION CONTROL — emit no DEAD rows; (h1) must go RED.
sed -e 's/+ ( \$edges_live | map( "DEAD/+ ( [] | map( "DEAD/' "$ENGINE" > "$MUT/dead.sh"
if mutant_ok "$MUT/dead.sh" "(h5) dead_rule mutant"; then
  run_audit "$r" "$MUT/dead.sh"
  if ! printf '%s' "$OUT" | grep -q '\[dead_rule\]'; then
    ok "(h5) MUTATION CONTROL: with the DEAD emitter emptied the finding DISAPPEARS — (h1) is not vacuous"
  else
    no "(h5) MUTATION CONTROL: the mutant STILL reported dead_rule — (h1) may pass for another reason"
  fi
fi

# ============================================================================
echo "== (i) AC5b: a rule contradicted by a rule added AFTER it (the drift case) =="
# The two statements differ ONLY by a negation: overlap excludes negation tokens, so they score 100%
# on shared terms while their POLARITY differs — which is precisely what validate_contradiction judges.
r="$(new_repo)"
seed_store "$r" "process" '[
 {"id":"p-first","category":"process","statement":"the release notes are generated from the changelog by the release script on every tagged build in pr-100","enforcement":"advisory","check":null,"provenance":{"source":"pr-100","added":"'"$ISO_A"'"},"applies_to":null},
 {"id":"p-later","category":"process","statement":"the release notes are never generated from the changelog by the release script on every tagged build in pr-138","enforcement":"advisory","check":null,"provenance":{"source":"pr-138","added":"'"$ISO_B"'"},"applies_to":null}
]'
fp="$(fingerprint "$r")"
run_audit "$r"
if printf '%s' "$OUT" | grep -q '\[later_contradiction\]' && [ "$RC" -eq 1 ]; then
  ok "(i1) a rule contradicted by a LATER rule is reported [later_contradiction] (exit 1)"
else
  no "(i1) later_contradiction NOT reported (exit $RC): $(printf '%s' "$OUT" | grep -A2 'BLOCKING' | head -6)"
fi
printf '%s' "$OUT" | grep -q 'REFUSE_CONTRADICTION' \
  && ok "(i2) the finding carries the validator's OWN message (the matched stored text) as evidence" \
  || no "(i2) the later_contradiction finding carries no validator evidence"
# Direction matters: only the OLDER rule is reported as contradicted-by-a-later-one.
if [ "$(printf '%s' "$OUT" | grep -c '\[later_contradiction\] rule: p-first')" -eq 1 ] \
   && [ "$(printf '%s' "$OUT" | grep -c '\[later_contradiction\] rule: p-later')" -eq 0 ]; then
  ok "(i3) the check is DIRECTIONAL — the older rule is reported, the later one is not"
else
  no "(i3) the later-rule check is not directional"
fi
byte_identical "$r" "$fp" "(i4)"

# (i5) MUTATION CONTROL — empty the later-rules corpus filter; (i1) must go RED.
awk '/c_added/ && /after/ && /continue/ { print "      continue"; next } { print }' "$ENGINE" > "$MUT/later.sh"
if mutant_ok "$MUT/later.sh" "(i5) later_contradiction mutant"; then
  run_audit "$r" "$MUT/later.sh"
  if ! printf '%s' "$OUT" | grep -q '\[later_contradiction\]'; then
    ok "(i5) MUTATION CONTROL: with the later-rules corpus emptied the finding DISAPPEARS — (i1) is not vacuous"
  else
    no "(i5) MUTATION CONTROL: the mutant STILL reported later_contradiction — (i1) may pass for another reason"
  fi
fi

# ============================================================================
echo "== (j) AC7: NO code path executes a rule's \`check\` (canary) =="
# The canary is the whole point: an absence assertion over an inert store proves nothing, so the
# fixture's `check` is a command with an OBSERVABLE SIDE EFFECT. If any code path ran it, the file
# would exist. The mutation control below proves an executing engine WOULD create it.
r="$(new_repo)"
CANARY="$r/CANARY-EXECUTED"
seed_store "$r" "security" '[
 {"id":"s-canary","category":"security","statement":"a check value is arbitrary shell and is never run unattended in pr-138","enforcement":"must","check":"touch '"$CANARY"'","provenance":{"source":"pr-138","added":"'"$ISO_A"'"},"applies_to":null}
]'
fp="$(fingerprint "$r")"
rm -f "$CANARY"
run_audit "$r"
if [ ! -e "$CANARY" ]; then
  ok "(j1) the audit did NOT execute the rule's \`check\` — the canary file was never created (AC7)"
else
  no "(j1) THE CANARY EXISTS — the audit EXECUTED a rule's check. This breaks the sole-executor invariant."
fi
printf '%s' "$OUT" | grep -q 'check` strings EXECUTED by this audit: 0' \
  && ok "(j2) the engine states in its own output that it executed zero checks" \
  || no "(j2) the engine does not state that it executed zero checks"
byte_identical "$r" "$fp" "(j3)"

# (j4) MUTATION CONTROL — an engine that DOES run the check must create the canary. Without this,
# (j1) would pass just as happily against an engine that never reached the rule at all.
awk '/^  n_rules=\$\(\(n_rules \+ 1\)\)$/ { print; print "  [ \"$r_ckk\" = \"string\" ] && bash -c \"$r_ckv\" >/dev/null 2>&1"; next } { print }' \
  "$ENGINE" > "$MUT/exec-check.sh"
if mutant_ok "$MUT/exec-check.sh" "(j4) check-execution mutant"; then
  rm -f "$CANARY"
  run_audit "$r" "$MUT/exec-check.sh"
  if [ -e "$CANARY" ]; then
    ok "(j4) MUTATION CONTROL: an engine that DOES run the check creates the canary — (j1) is a real absence, not an unreached path"
  else
    no "(j4) MUTATION CONTROL: even the executing mutant produced no canary — (j1) proves nothing"
  fi
  rm -f "$CANARY"
fi

# ============================================================================
echo "== (k) AC9: a degraded validator makes the run report UNEXAMINED and exit 2 =="
# The three degraded shapes are aimed one per LOAD GUARD clause, exactly as test-add-rule.sh's are:
#   unparse    -> clause (i):   a trailing syntax error makes `source` exit non-zero, yet every
#                               function ABOVE the error is defined AND the sentinel is set.
#   partial    -> clause (ii):  cut above validate_dead_reference, so some validators exist and
#                               validate_entry_all does not — the shape a one-name probe waves through.
#   nosentinel -> clause (iii): everything defined and working, only the contract sentinel missing.
VD="$ROOT/degraded"; mkdir -p "$VD"
cp "$VALIDATOR" "$VD/unparse.sh"; printf '\nif [ ; then\n' >> "$VD/unparse.sh"
awk '/^validate_dead_reference\(\)/{exit} {print}' "$VALIDATOR" > "$VD/partial.sh"
awk '/^VALIDATE_ENTRY_CONTRACT="/{exit} {print}'  "$VALIDATOR" > "$VD/nosentinel.sh"
if bash -n "$VD/partial.sh" 2>/dev/null && bash -n "$VD/nosentinel.sh" 2>/dev/null \
   && ! bash -n "$VD/unparse.sh" 2>/dev/null; then
  ok "(k0) the degraded-validator fixtures are each the shape they claim (one per guard clause)"
else
  no "(k0) a degraded-validator fixture is not the shape it claims — the clause labels below are unreliable"
fi

r="$(new_repo)"
seed_store "$r" "process" '[{"id":"p-1","category":"process","statement":"prefer the narrow probe in pr-138","enforcement":"advisory","check":null,"provenance":{"source":"pr-138","added":"'"$ISO_A"'"},"applies_to":null}]'
fp="$(fingerprint "$r")"
degraded_case() {  # <label> <validator-path>
  run_audit "$r" "$ENGINE" "$2"
  if [ "$RC" -eq 2 ] \
     && printf '%s' "$OUT" | grep -q 'REFUSE_VALIDATOR_UNAVAILABLE' \
     && printf '%s' "$OUT" | grep -q 'UNEXAMINED'; then
    ok "(k) AC9 $1 — UNEXAMINED, named reason, exit 2 (never reported clean)"
  else
    no "(k) AC9 $1 — expected exit 2 + REFUSE_VALIDATOR_UNAVAILABLE + UNEXAMINED, got exit $RC"
  fi
}
degraded_case "validator absent"        "$VD/no-such-file.sh"
degraded_case "validator unparseable"   "$VD/unparse.sh"
degraded_case "validator truncated"     "$VD/partial.sh"
degraded_case "validator sentinel-less" "$VD/nosentinel.sh"
byte_identical "$r" "$fp" "(k5)"

# (k6) MUTATION CONTROL — replace the WHOLE load guard with the repo's pervasive `|| true`, the one
# line clause (i) forbids. Paired with the SENTINEL-LESS validator deliberately: with an absent or
# truncated helper the engine still fails closed BY ACCIDENT (validate_entry_all is undefined, the
# call returns 127), but with a sentinel-less helper every validator works, so dropping the guard
# lets an UNVERIFIED-CONTRACT run go all the way through and report the store CLEAN.
awk '/---- LOAD GUARD BEGIN/{s=1; print "  . \"$VALIDATOR\" || true"; next} /---- LOAD GUARD END/{s=0; next} !s' \
  "$ENGINE" > "$MUT/guard.sh"
if mutant_ok "$MUT/guard.sh" "(k6) load-guard mutant"; then
  if grep -q '|| true' "$MUT/guard.sh"; then
    run_audit "$r" "$MUT/guard.sh" "$VD/nosentinel.sh"
    if [ "$RC" -ne 2 ] && ! printf '%s' "$OUT" | grep -q 'REFUSE_VALIDATOR_UNAVAILABLE'; then
      ok "(k6) MUTATION CONTROL: with the guard replaced by '|| true' an unverified-contract validator audits the store CLEAN (exit $RC) — the AC9 assertions are not vacuous"
    else
      no "(k6) MUTATION CONTROL: the '|| true' mutant did not go RED (exit $RC) — AC9 may pass for another reason"
    fi
  else
    no "(k6) MUTATION CONTROL: the '|| true' replacement did not land in the mutant"
  fi
fi

# ============================================================================
echo "== (l) AC10: rc 2 from a shared check surfaces as UNKNOWN, never absorbed as clean =="
# Two rules whose statements are IDENTICAL. Against the correct one-line-per-rule corpus the
# duplicate check can DECIDE (rc 1). Against a document-split-into-lines corpus every store line is
# smaller than the entry, no single line can reach the 90% threshold, and the shape guard returns 2
# — "could not decide". That is the exact trap this engine's corpus discipline exists to avoid.
DUP_STMT="the deterministic identifier is derived from the category slug and the statement slug in pr-138"
r="$(new_repo)"
seed_store "$r" "process" '[
 {"id":"p-a","category":"process","statement":"'"$DUP_STMT"'","enforcement":"advisory","check":null,"provenance":{"source":"pr-138","added":"'"$ISO_A"'"},"applies_to":null},
 {"id":"p-b","category":"process","statement":"'"$DUP_STMT"'","enforcement":"advisory","check":null,"provenance":{"source":"pr-139","added":"'"$ISO_B"'"},"applies_to":null}
]'
fp="$(fingerprint "$r")"
run_audit "$r"
if printf '%s' "$OUT" | grep -q '\[duplicate\]' && [ "$RC" -eq 1 ]; then
  ok "(l1) with the ONE-LINE-PER-RULE corpus the duplicate check DECIDES (a real rc-1 finding, exit 1)"
else
  no "(l1) the correctly-shaped corpus did not produce a duplicate verdict (exit $RC)"
fi
byte_identical "$r" "$fp" "(l2)"

# (l3) The SHAPE TRAP, reproduced end-to-end: make the corpus a document split into lines (one WORD
# per line) and the very same store must become UNKNOWN + exit 2, never clean.
awk '/^  build_compare_corpus "\$CORPUS" "\$rid" ""$/ {
       print
       print "  tr \" \" \"\\n\" < \"$CORPUS\" > \"$CORPUS.w\" && mv \"$CORPUS.w\" \"$CORPUS\""
       next
     } { print }' "$ENGINE" > "$MUT/badshape.sh"
if mutant_ok "$MUT/badshape.sh" "(l3) wrong-corpus-shape mutant"; then
  run_audit "$r" "$MUT/badshape.sh"
  if [ "$RC" -eq 2 ] \
     && printf '%s' "$OUT" | grep -q 'UNCOMPARABLE_SHAPE' \
     && printf '%s' "$OUT" | grep -q 'UNKNOWN, NOT clean'; then
    ok "(l3) a wrong-shaped corpus yields rc 2 and is surfaced as UNKNOWN with exit 2 — never absorbed as clean (AC10)"
  else
    no "(l3) the wrong-shaped corpus did not surface as UNKNOWN/exit 2 (exit $RC)"
  fi

  # (l4) MUTATION CONTROL for (l3): an engine that ABSORBS rc 2 as clean reports the same store as
  # clean and exits 0. This is the fail-open (l3) exists to forbid, and without it (l3) would be
  # satisfied by any engine that happened to exit 2 for an unrelated reason.
  sed -e 's/^      \*) unknown "duplicate"/      *) : "duplicate"/' \
      -e 's/^      \*) unknown "contradiction"/      *) : "contradiction"/' \
      "$MUT/badshape.sh" > "$MUT/absorb.sh"
  if [ ! -s "$MUT/absorb.sh" ] || cmp -s "$MUT/badshape.sh" "$MUT/absorb.sh" || ! bash -n "$MUT/absorb.sh" 2>/dev/null; then
    no "(l4) MUTATION CONTROL: the rc-2-absorbing mutant did not land (vacuous control)"
  else
    run_audit "$r" "$MUT/absorb.sh"
    if [ "$RC" -ne 2 ] && ! printf '%s' "$OUT" | grep -q 'UNKNOWN, NOT clean'; then
      ok "(l4) MUTATION CONTROL: an engine that absorbs rc 2 reports the SAME store clean (exit $RC) — (l3) is not vacuous"
    else
      no "(l4) MUTATION CONTROL: the rc-2-absorbing mutant still reported UNKNOWN (exit $RC)"
    fi
  fi
fi

# ============================================================================
echo "== (m) every recommendation names an EXISTING action; no new write path is invented =="
r="$(new_repo)"; mk_no_mechanism "$r"
run_audit "$r"
if printf '%s' "$OUT" | grep -q '/rules add --supersedes' \
   && printf '%s' "$OUT" | grep -q 'add-rule.sh --retract --target'; then
  ok "(m1) recommendations name the two EXISTING actions (/rules add --supersedes, add-rule.sh --retract)"
else
  no "(m1) a recommendation does not name an existing action"
fi
if ! printf '%s' "$OUT" | grep -qiE 'audit-rules\.sh (--fix|--write|--apply)|run this script with --'; then
  ok "(m2) no recommendation proposes a write performed by this script (it has no write path)"
else
  no "(m2) a recommendation proposes a write by the audit itself"
fi

# ============================================================================
echo "== (n) the LIVE store is read without being touched =="
# Deliberately read-only, and deliberately NOT an assertion about the live store's CONTENTS: the
# live store is small enough that any content assertion would be a small-N claim dressed as a test.
LIVE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
if [ -d "$LIVE_ROOT/.agent/rules" ]; then
  live_fp="$(fingerprint "$LIVE_ROOT")"
  ( cd "$LIVE_ROOT" && bash "$ENGINE" >/dev/null 2>&1 )
  live_rc=$?
  if [ "$(fingerprint "$LIVE_ROOT")" = "$live_fp" ]; then
    ok "(n1) a run against the LIVE store left it byte-identical (exit $live_rc)"
  else
    no "(n1) A RUN AGAINST THE LIVE STORE CHANGED IT"
  fi
  if [ "$live_rc" -ne 2 ]; then
    ok "(n2) the live store is EXAMINABLE (exit $live_rc — not the could-not-examine code)"
  else
    no "(n2) the live store reported UNEXAMINED/UNKNOWN (exit 2)"
  fi
else
  ok "(n1) no live .agent/rules store in this checkout — nothing to assert (not vacuous: the fixture cases above carry the coverage)"
fi

# ============================================================================
echo "== (o) a CONCURRENT WRITER that adds/removes a store file mid-run is DETECTED =="
# The defect this closes: the before/after fingerprint enumerated the store ONCE, then hashed that
# fixed list twice. A writer that ADDED a rule file mid-run added a file that was never in the list,
# so it was never hashed, every listed file was unchanged, and the run printed "the store is
# BYTE-IDENTICAL to how this run found it" over a store that had grown underneath it. The guarantee
# the code made was the narrower "no enumerated file changed content".
# The seam: validate_duplicate is called per rule, i.e. strictly between FP_BEFORE and FP_AFTER, so a
# validator wrapper is a real concurrent writer from the engine's point of view.

# mk_cw_validator <outfile> <action-shell> — the REAL validator plus a shim that fires <action-shell>
# once, on the first validate_duplicate call. The engine's LOAD GUARD still passes: all seven names
# and the contract sentinel come from the real file, which is copied verbatim.
mk_cw_validator() {
  local out="$1" action="$2"
  cat "$VALIDATOR" > "$out"
  {
    printf '\n# ---- test shim: a concurrent writer, fired mid-run ----\n'
    printf '_cw_fired=0\n'
    printf 'eval "$(declare -f validate_duplicate | sed "1s/^validate_duplicate/_cw_orig_validate_duplicate/")"\n'
    printf 'validate_duplicate() {\n'
    printf '  if [ "$_cw_fired" -eq 0 ]; then _cw_fired=1; %s; fi\n' "$action"
    printf '  _cw_orig_validate_duplicate "$@"\n'
    printf '}\n'
  } >> "$out"
}

# The pre-fix engine: store_fingerprint hashing the ONCE-enumerated $FILES_LIST, with no file set in
# the value. This is the mutation control for every assertion in this group — without it, "the add is
# detected" could be passing for some unrelated reason.
FIXED_FP_MUT="$MUT/fixed-fingerprint.sh"
awk '
  /^store_fingerprint\(\) \{$/ {
    inf = 1
    print "store_fingerprint() {"
    print "  local f"
    print "  while IFS= read -r f; do"
    print "    [ -n \"$f\" ] || continue"
    print "    hash_one \"$f\""
    print "  done < \"$FILES_LIST\""
    next
  }
  inf && /^\}$/ { inf = 0; print "}"; next }
  inf { next }
  { print }
' "$ENGINE" > "$FIXED_FP_MUT"

r="$(new_repo)"
seed_store "$r" "process" '[
 {"id":"p-one","category":"process","statement":"a gate names its own failure reason in review pr-138","enforcement":"advisory","check":null,"provenance":{"source":"pr-138","added":"'"$ISO_A"'"},"applies_to":null}
]'
CWVAL_ADD="$MUT/cw-add-validator.sh"
mk_cw_validator "$CWVAL_ADD" "printf '%s\\n' '[{\"id\":\"cw-added\",\"category\":\"process\",\"statement\":\"this file appeared mid-run\",\"enforcement\":\"advisory\",\"check\":null,\"provenance\":{\"source\":\"concurrent\",\"added\":\"2026-01-01T00:00:00Z\"},\"applies_to\":null}]' > '$r/.agent/rules/zz-appeared.json'"

rm -f "$r/.agent/rules/zz-appeared.json"
run_audit "$r" "$ENGINE" "$CWVAL_ADD"
if [ -f "$r/.agent/rules/zz-appeared.json" ]; then
  ok "(o0) the shim really did add a store file mid-run (the scenario is not vacuous)"
else
  no "(o0) the shim never fired — every (o) assertion below would be vacuous"
fi
if printf '%s' "$OUT" | grep -q 'THE STORE CHANGED DURING THIS RUN'; then
  ok "(o1) a rule file ADDED mid-run trips the store-integrity mismatch"
else
  no "(o1) A FILE ADDED MID-RUN WAS NOT DETECTED — the run reported the store unchanged"
fi
[ "$RC" -eq 2 ] && ok "(o2) the mid-run add exits 2 (could-not-examine), not 0/1" \
                || no "(o2) the mid-run add exited $RC, not the could-not-examine code 2"

# Mutation control: the pre-fix fixed-list fingerprint must MISS the same add.
if mutant_ok "$FIXED_FP_MUT" "(o3)"; then
  rm -f "$r/.agent/rules/zz-appeared.json"
  run_audit "$r" "$FIXED_FP_MUT" "$CWVAL_ADD"
  if printf '%s' "$OUT" | grep -q 'BYTE-IDENTICAL'; then
    ok "(o3) the once-enumerated fingerprint MISSES the add (so (o1) has a mechanism, not a coincidence)"
  else
    no "(o3) the once-enumerated mutant also detected the add — (o1) proves nothing"
  fi
fi

# REMOVE: already caught before the fix (the vanishing hash line), asserted so it stays caught.
r2="$(new_repo)"
seed_store "$r2" "process" '[
 {"id":"p-one","category":"process","statement":"a gate names its own failure reason in review pr-138","enforcement":"advisory","check":null,"provenance":{"source":"pr-138","added":"'"$ISO_A"'"},"applies_to":null}
]'
seed_store "$r2" "zz-doomed" '[
 {"id":"z-one","category":"zz-doomed","statement":"this file is removed by a concurrent writer mid-run","enforcement":"advisory","check":null,"provenance":{"source":"pr-138","added":"'"$ISO_A"'"},"applies_to":null}
]'
CWVAL_RM="$MUT/cw-rm-validator.sh"
mk_cw_validator "$CWVAL_RM" "rm -f '$r2/.agent/rules/zz-doomed.json'"
run_audit "$r2" "$ENGINE" "$CWVAL_RM"
if [ ! -f "$r2/.agent/rules/zz-doomed.json" ] && printf '%s' "$OUT" | grep -q 'THE STORE CHANGED DURING THIS RUN'; then
  ok "(o4) a rule file REMOVED mid-run trips the store-integrity mismatch"
else
  no "(o4) a file removed mid-run was not detected (shim fired: $([ -f "$r2/.agent/rules/zz-doomed.json" ] && echo no || echo yes))"
fi
[ "$RC" -eq 2 ] && ok "(o5) the mid-run remove exits 2" || no "(o5) the mid-run remove exited $RC, not 2"

# A CLEAN run must still say BYTE-IDENTICAL and exit 0/1 — the new set-sensitivity must not make
# every ordinary run look like it was written to.
r3="$(new_repo)"
seed_store "$r3" "process" '[
 {"id":"p-one","category":"process","statement":"a gate names its own failure reason in review pr-138","enforcement":"advisory","check":null,"provenance":{"source":"pr-138","added":"'"$ISO_A"'"},"applies_to":null}
]'
fp="$(fingerprint "$r3")"
run_audit "$r3"
if printf '%s' "$OUT" | grep -q 'BYTE-IDENTICAL' && [ "$RC" -ne 2 ]; then
  ok "(o6) an ordinary run with no concurrent writer still reports BYTE-IDENTICAL (exit $RC)"
else
  no "(o6) an ordinary run no longer reports byte-identity (exit $RC) — the fingerprint is unstable"
fi
byte_identical "$r3" "$fp" "(o7)"

# ============================================================================
echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
