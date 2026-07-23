#!/usr/bin/env bash
# test-add-rule.sh — self-tests for add-rule.sh, the SOLE WRITER for the committed .agent/rules/
# house-rules substrate (slice #3b-ii). Runs the writer inside ISOLATED temp git repos via
# `mktemp -d` + `git init` so it NEVER touches the real repo's .agent/rules/. The writer does
# `git rev-parse --show-toplevel` then anchors .agent/rules/ there, so we `cd` into each temp repo.
# Mirrors the test-read-rules.sh harness convention. Exit 0 = all pass, 1 = any failure
# (auto-registered by ci.yml's test-*.sh glob).
#
# Covers:
#   (A) hostile categories REJECTED (non-zero, diagnostic, NO file written outside .agent/rules/):
#       ../escape, a/b, .hidden, foo;rm -rf, foo`x, and empty "".
#   (B) clean category ("Testing Standards") + --confirm writes EXACTLY .agent/rules/testing-standards.json
#       (single [a-z0-9-] slug) as a valid array containing the object.
#   (C) array-only parse-gate ABORTS (never clobbers) on a pre-existing non-array/malformed target.
#   (D) deterministic-id collision suffix (-2) when the same category+statement is added twice.
#   (E) provenance.source + provenance.added stamped.
#   (F) atomic write + read-back verify (written file parses + contains the new id).
#   (G) value validation: bad --enforcement (blocking), empty --statement, non-string non-null check.
#   (H) confirm-only: no --confirm + non-TTY ⇒ DRY-RUN (plan printed, NO file written).

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRITER="$SCRIPT_DIR/add-rule.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT" 2>/dev/null' EXIT
mktmp() { mktemp -d "$ROOT/d.XXXXXX"; }

new_repo() {
  local r; r="$(mktmp)"
  ( cd "$r" && git init -q && git config user.email t@t && git config user.name t \
      && echo init > f && git add f && git commit -qm init ) >/dev/null 2>&1
  printf '%s' "$r"
}

# Run the writer inside a temp repo. All extra args forwarded. Captures stdout+stderr and rc.
# Usage: run_writer <repo> [args...]   → sets globals OUT and RC.
run_writer() {
  local repo="$1"; shift
  OUT="$( ( cd "$repo" && bash "$WRITER" "$@" ) 2>&1 )"; RC=$?
}

# Count *.json files that exist anywhere under a repo's .agent/ dir (to assert no traversal escape).
count_rule_files() {
  find "$1/.agent" -type f -name '*.json' 2>/dev/null | wc -l | tr -d '[:space:]'
}

if ! command -v jq >/dev/null 2>&1; then
  echo "test-add-rule: jq absent on this host — add-rule.sh requires jq. Skipping data assertions."
  echo "RESULT: 0 passed, 0 failed (jq absent, vacuous)"
  exit 0
fi

# ============================================================================
echo "== (A) hostile categories are REJECTED (non-zero, diagnostic, NO escape) =="
# For each hostile category: rc must be non-zero, a diagnostic present, and NO *.json anywhere under
# .agent/ (proving neither a traversal write NOR a silent-sanitized fallback write occurred).
hostile_reject() {
  local label="$1" repo cat_arg
  repo="$(new_repo)"
  cat_arg="$2"
  # Also drop a sentinel dir the writer must never escape into.
  mkdir -p "$repo/escape-target"
  run_writer "$repo" --category "$cat_arg" --statement "some rule" --confirm
  local files; files="$(count_rule_files "$repo")"
  # No escaped file next to the repo either (../escape would land one level up = under $ROOT/d.* parent).
  local escaped=0
  [ -e "$repo/../escape.json" ] && escaped=1
  [ -e "$repo/.agent/../etc.json" ] && escaped=1
  if [ "$RC" -ne 0 ] && [ -n "$OUT" ] && [ "$files" = "0" ] && [ "$escaped" -eq 0 ]; then
    ok "hostile category [$label] rejected (rc=$RC, diagnostic present, 0 files written)"
  else
    no "hostile category [$label] NOT properly rejected (rc=$RC files=$files escaped=$escaped out=$OUT)"
  fi
}
hostile_reject "../escape" "../escape"
hostile_reject "a/b"       "a/b"
hostile_reject ".hidden"   ".hidden"
hostile_reject "foo;rm-rf" 'foo;rm -rf'
hostile_reject "backtick"  'foo`x`'
hostile_reject "empty"     ""

# A hostile category is REJECTED, never silently rewritten into a safe slug: assert no 'etc.json' /
# 'escape.json' / 'foo.json' safe-looking fallback was authored from '../etc'.
RSAN="$(new_repo)"
run_writer "$RSAN" --category "../etc" --statement "x" --confirm
if [ "$RC" -ne 0 ] && [ ! -e "$RSAN/.agent/rules/etc.json" ]; then
  ok "hostile '../etc' NOT silently sanitized into a safe-looking etc.json"
else
  no "hostile '../etc' produced a sanitized fallback file (rc=$RC)"
fi

# ============================================================================
echo "== (B) clean category + --confirm writes EXACTLY .agent/rules/testing-standards.json =="
RB="$(new_repo)"
run_writer "$RB" --category "Testing Standards" --statement "Always assert error type not just message" \
  --enforcement advisory --confirm
[ "$RC" -eq 0 ] && ok "clean add exits 0" || no "clean add expected 0, got $RC ($OUT)"
if [ -f "$RB/.agent/rules/testing-standards.json" ]; then
  ok "wrote EXACTLY .agent/rules/testing-standards.json (single [a-z0-9-] slug)"
else
  no "expected .agent/rules/testing-standards.json (got files: $(find "$RB/.agent" -type f 2>/dev/null))"
fi
# Exactly one rule file, and it is a valid array containing the object.
[ "$(count_rule_files "$RB")" = "1" ] && ok "exactly one rule file created" || no "expected 1 rule file"
if jq -e 'type=="array" and length==1
          and .[0].statement=="Always assert error type not just message"
          and .[0].category=="testing-standards"
          and .[0].enforcement=="advisory"' \
     "$RB/.agent/rules/testing-standards.json" >/dev/null 2>&1; then
  ok "target is a valid single-element array with the object"
else
  no "target array/object contents incorrect: $(cat "$RB/.agent/rules/testing-standards.json" 2>/dev/null)"
fi

# ============================================================================
echo "== (C) array-only parse-gate ABORTS (never clobbers) on pre-existing non-array/malformed =="
# (C1) valid JSON but NOT an array (a bare object) → abort, file byte-identical afterwards.
RC1="$(new_repo)"
mkdir -p "$RC1/.agent/rules"
printf '%s' '{"not":"an array"}' > "$RC1/.agent/rules/config.json"
before_c1="$(cat "$RC1/.agent/rules/config.json")"
run_writer "$RC1" --category "config" --statement "should not clobber" --confirm
after_c1="$(cat "$RC1/.agent/rules/config.json")"
if [ "$RC" -ne 0 ] && [ "$before_c1" = "$after_c1" ]; then
  ok "(C1) non-array target aborted, file left byte-identical (no clobber)"
else
  no "(C1) non-array target NOT protected (rc=$RC, changed=$([ "$before_c1" = "$after_c1" ] && echo no || echo YES))"
fi
# (C2) malformed JSON → abort, file untouched.
RC2="$(new_repo)"
mkdir -p "$RC2/.agent/rules"
printf '%s' '{ broken json ][' > "$RC2/.agent/rules/broken.json"
before_c2="$(cat "$RC2/.agent/rules/broken.json")"
run_writer "$RC2" --category "broken" --statement "should not clobber" --confirm
after_c2="$(cat "$RC2/.agent/rules/broken.json")"
if [ "$RC" -ne 0 ] && [ "$before_c2" = "$after_c2" ]; then
  ok "(C2) malformed target aborted, file left byte-identical (no clobber)"
else
  no "(C2) malformed target NOT protected (rc=$RC)"
fi

# ============================================================================
echo "== (D) deterministic-id collision suffix (-2) on same category+statement twice =="
RD="$(new_repo)"
run_writer "$RD" --category "dedup" --statement "one convention" --confirm
[ "$RC" -eq 0 ] && ok "(D) first add ok" || no "(D) first add failed ($OUT)"
run_writer "$RD" --category "dedup" --statement "one convention" --confirm
[ "$RC" -eq 0 ] && ok "(D) second add ok" || no "(D) second add failed ($OUT)"
ids_d="$(jq -r '.[].id' "$RD/.agent/rules/dedup.json" 2>/dev/null | LC_ALL=C sort | tr '\n' ',')"
if [ "$ids_d" = "dedup-one-convention,dedup-one-convention-2," ]; then
  ok "(D) collision produced deterministic base id + -2 suffix"
else
  no "(D) expected [dedup-one-convention,dedup-one-convention-2,], got [$ids_d]"
fi

# (D2) cross-file collision: same id would collide with a DIFFERENT file → global merged-set dedup.
RD2="$(new_repo)"
mkdir -p "$RD2/.agent/rules"
# Pre-seed a DIFFERENT category file that already owns the id "dedup-shared-rule".
printf '%s' '[{"id":"dedup-shared-rule","category":"other","statement":"pre","enforcement":"advisory","check":null,"provenance":{"source":"seed","added":"2026-01-01T00:00:00Z"}}]' \
  > "$RD2/.agent/rules/other.json"
run_writer "$RD2" --category "dedup" --statement "shared rule" --confirm
new_id_d2="$(jq -r '.[0].id' "$RD2/.agent/rules/dedup.json" 2>/dev/null)"
if [ "$new_id_d2" = "dedup-shared-rule-2" ]; then
  ok "(D2) cross-file id collision suffixed against the MERGED set (-2)"
else
  no "(D2) expected dedup-shared-rule-2 (cross-file), got [$new_id_d2]"
fi

# ============================================================================
echo "== (E) provenance.source + provenance.added stamped =="
RE="$(new_repo)"
run_writer "$RE" --category "prov" --statement "stamp me" --source "unit-test" --confirm
src_e="$(jq -r '.[0].provenance.source' "$RE/.agent/rules/prov.json" 2>/dev/null)"
added_e="$(jq -r '.[0].provenance.added' "$RE/.agent/rules/prov.json" 2>/dev/null)"
[ "$src_e" = "unit-test" ] && ok "(E) provenance.source stamped from --source" || no "(E) source=[$src_e]"
# ISO-8601 UTC shape: YYYY-MM-DDThh:mm:ssZ
if printf '%s' "$added_e" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; then
  ok "(E) provenance.added is UTC ISO-8601 ($added_e)"
else
  no "(E) provenance.added not ISO-8601: [$added_e]"
fi
# Default source when --source omitted.
RE2="$(new_repo)"
run_writer "$RE2" --category "prov" --statement "default source" --confirm
[ "$(jq -r '.[0].provenance.source' "$RE2/.agent/rules/prov.json" 2>/dev/null)" = "/rules add" ] \
  && ok "(E) default provenance.source is '/rules add'" || no "(E) default source wrong"

# ============================================================================
echo "== (F) atomic write + read-back verify (parses + contains new id) =="
RF="$(new_repo)"
run_writer "$RF" --category "verify" --statement "read back" --confirm
[ "$RC" -eq 0 ] && ok "(F) write reported success (read-back verify passed internally)" || no "(F) rc=$RC ($OUT)"
# No leftover temp files in the rules dir (atomic mv cleaned up).
leftover="$(find "$RF/.agent/rules" -name '.add-rule.*' 2>/dev/null | wc -l | tr -d '[:space:]')"
[ "$leftover" = "0" ] && ok "(F) no leftover temp files (atomic mv)" || no "(F) $leftover temp files left"
# The success message names the id.
echo "$OUT" | grep -q "verify-read-back" && ok "(F) success output names the written id" || no "(F) id not in output"

# ============================================================================
echo "== (G) value validation: bad enforcement / empty statement / non-string check =="
# (G1) bad --enforcement (blocking) rejected, no file written.
RG1="$(new_repo)"
run_writer "$RG1" --category "gval" --statement "x" --enforcement blocking --confirm
if [ "$RC" -ne 0 ] && [ "$(count_rule_files "$RG1")" = "0" ]; then
  ok "(G1) bad --enforcement 'blocking' rejected, nothing written"
else
  no "(G1) bad enforcement not rejected (rc=$RC)"
fi
# (G2) empty --statement rejected.
RG2="$(new_repo)"
run_writer "$RG2" --category "gval" --statement "" --confirm
if [ "$RC" -ne 0 ] && [ "$(count_rule_files "$RG2")" = "0" ]; then
  ok "(G2) empty --statement rejected, nothing written"
else
  no "(G2) empty statement not rejected (rc=$RC)"
fi
# (G3) statement with no [a-z0-9-] content (only punctuation) → empty statement-slug → rejected.
RG3="$(new_repo)"
run_writer "$RG3" --category "gval" --statement "!!! ???" --confirm
if [ "$RC" -ne 0 ] && [ "$(count_rule_files "$RG3")" = "0" ]; then
  ok "(G3) statement with no sluggable content rejected"
else
  no "(G3) unsluggable statement not rejected (rc=$RC)"
fi
# (G4) non-string non-null check at the SCHEMA level: the CLI always passes a string, so we assert the
# reader-compatibility property directly — a rule authored by this writer with a --check value produces
# a STRING check (never a number), which read-rules.sh accepts. (A numeric check can only arise from a
# hand-edited file, which the reader itself SKIPs — covered by test-read-rules.sh g8.)
RG4="$(new_repo)"
run_writer "$RG4" --category "gval" --statement "with a check" --check "bash scripts/validate.sh" --confirm
check_type_g4="$(jq -r '.[0].check | type' "$RG4/.agent/rules/gval.json" 2>/dev/null)"
[ "$check_type_g4" = "string" ] && ok "(G4) --check authored as a STRING (reader-compatible)" \
  || no "(G4) check type is [$check_type_g4], expected string"
# And an omitted --check yields explicit null (also reader-valid).
RG5="$(new_repo)"
run_writer "$RG5" --category "gval" --statement "no check here" --confirm
[ "$(jq -r '.[0].check | type' "$RG5/.agent/rules/gval.json" 2>/dev/null)" = "null" ] \
  && ok "(G4b) omitted --check yields explicit null" || no "(G4b) omitted check not null"

# ============================================================================
echo "== (H) confirm-only: no --confirm + non-TTY ⇒ DRY-RUN (plan printed, NO file written) =="
RH="$(new_repo)"
# run_writer already runs in a non-TTY subshell context; omit --confirm.
run_writer "$RH" --category "dryrun" --statement "planned only"
if [ "$RC" -eq 0 ] && [ "$(count_rule_files "$RH")" = "0" ] && echo "$OUT" | grep -q "PLANNED WRITE"; then
  ok "(H) no --confirm + non-TTY prints planned write and writes NOTHING (rc 0)"
else
  no "(H) dry-run behavior incorrect (rc=$RC files=$(count_rule_files "$RH"))"
fi

# ============================================================================
echo "== (I) --supersedes (curation/anti-rot ST-1): stamps the field on the ADD action =="
RI1="$(new_repo)"
run_writer "$RI1" --category "sup" --statement "replacement rule" --supersedes "old-id-123" --confirm
[ "$RC" -eq 0 ] && ok "(I1) add with --supersedes exits 0" || no "(I1) expected 0, got $RC ($OUT)"
sup_val="$(jq -r '.[0].supersedes' "$RI1/.agent/rules/sup.json" 2>/dev/null)"
[ "$sup_val" = "old-id-123" ] && ok "(I1) supersedes field stamped onto the new rule object" \
  || no "(I1) expected supersedes=old-id-123, got [$sup_val]"

# (I2) omitted --supersedes ⇒ the member is OMITTED entirely (not stamped as an explicit null).
RI2="$(new_repo)"
run_writer "$RI2" --category "sup" --statement "no supersedes here" --confirm
has_key="$(jq -r '.[0] | has("supersedes")' "$RI2/.agent/rules/sup.json" 2>/dev/null)"
[ "$has_key" = "false" ] && ok "(I2) --supersedes omitted ⇒ 'supersedes' member entirely absent (not null)" \
  || no "(I2) expected the supersedes key to be absent, has(\"supersedes\")=[$has_key]"

# (I3) self-reference guard: --supersedes naming the about-to-be-created id itself is rejected,
# nothing written.
RI3="$(new_repo)"
run_writer "$RI3" --category "sup" --statement "self ref test" --supersedes "sup-self-ref-test" --confirm
if [ "$RC" -ne 0 ] && [ "$(count_rule_files "$RI3")" = "0" ]; then
  ok "(I3) self-referential --supersedes rejected, nothing written"
else
  no "(I3) self-referential --supersedes NOT rejected (rc=$RC files=$(count_rule_files "$RI3"))"
fi

# ============================================================================
echo "== (J) --retract removes the target rule object from the JSON array =="
RJ="$(new_repo)"
mkdir -p "$RJ/.agent/rules"
printf '%s' '[
  {"id":"j-keep","category":"safety","statement":"kept sibling","enforcement":"advisory","check":null,"provenance":{"source":"seed","added":"2026-01-01T00:00:00Z"}},
  {"id":"j-gone","category":"safety","statement":"retracted target","enforcement":"advisory","check":null,"provenance":{"source":"seed","added":"2026-01-01T00:00:00Z"}}
]' > "$RJ/.agent/rules/safety.json"
run_writer "$RJ" --retract --target "j-gone" --reason "superseded by a clearer rule" --confirm
[ "$RC" -eq 0 ] && ok "(J) --retract exits 0" || no "(J) expected 0, got $RC ($OUT)"
if jq -e 'type=="array" and length==1 and .[0].id=="j-keep"' "$RJ/.agent/rules/safety.json" >/dev/null 2>&1; then
  ok "(J) retracted object REMOVED from the array; sibling survives, file remains a valid array"
else
  no "(J) array not correctly reduced to the surviving sibling: $(cat "$RJ/.agent/rules/safety.json" 2>/dev/null)"
fi
if jq -e --arg t "j-gone" 'any(.[]?; (type=="object") and (.id==$t))' "$RJ/.agent/rules/safety.json" >/dev/null 2>&1; then
  no "(J) REGRESSION: retracted id still present in the file"
else
  ok "(J) retracted id no longer present anywhere in the file"
fi

# (J2) --retract PRINTS a one-line provenance reason to stdout (there is no in-store home for it —
# the commit that lands the removal is the durable record; test asserts on the printed text).
echo "$OUT" | grep -qF "j-gone" && echo "$OUT" | grep -qF "superseded by a clearer rule" \
  && ok "(J2) retract prints a one-line provenance reason naming the target id + reason" \
  || no "(J2) provenance reason not printed to stdout: $OUT"

# ============================================================================
echo "== (K) refused/invalid retract leaves the store byte-identical =="
seed_store() {
  # $1 repo — seeds a fixed one-rule store and echoes its content for a before/after comparison.
  mkdir -p "$1/.agent/rules"
  printf '%s' '[{"id":"k-untouched","category":"safety","statement":"must survive every invalid retract","enforcement":"advisory","check":null,"provenance":{"source":"seed","added":"2026-01-01T00:00:00Z"}}]' \
    > "$1/.agent/rules/safety.json"
  cat "$1/.agent/rules/safety.json"
}

# (K1) --retract with --replacement is REJECTED (replacement has no meaning on a pure retract).
RK1="$(new_repo)"; before_k1="$(seed_store "$RK1")"
run_writer "$RK1" --retract --target "k-untouched" --reason "x" --replacement "some-new-id" --confirm
after_k1="$(cat "$RK1/.agent/rules/safety.json")"
if [ "$RC" -ne 0 ] && [ "$before_k1" = "$after_k1" ]; then
  ok "(K1) --replacement on --retract rejected, store left byte-identical"
else
  no "(K1) --replacement on --retract NOT rejected/protected (rc=$RC)"
fi

# (K2) --retract without --target is rejected, store untouched.
RK2="$(new_repo)"; before_k2="$(seed_store "$RK2")"
run_writer "$RK2" --retract --reason "x" --confirm
after_k2="$(cat "$RK2/.agent/rules/safety.json")"
if [ "$RC" -ne 0 ] && [ "$before_k2" = "$after_k2" ]; then
  ok "(K2) --retract without --target rejected, store left byte-identical"
else
  no "(K2) missing --target NOT rejected/protected (rc=$RC)"
fi

# (K3) --retract without --reason is rejected, store untouched.
RK3="$(new_repo)"; before_k3="$(seed_store "$RK3")"
run_writer "$RK3" --retract --target "k-untouched" --confirm
after_k3="$(cat "$RK3/.agent/rules/safety.json")"
if [ "$RC" -ne 0 ] && [ "$before_k3" = "$after_k3" ]; then
  ok "(K3) --retract without --reason rejected, store left byte-identical"
else
  no "(K3) missing --reason NOT rejected/protected (rc=$RC)"
fi

# (K4) --retract combined with an add-only flag (--category) is rejected, store untouched.
RK4="$(new_repo)"; before_k4="$(seed_store "$RK4")"
run_writer "$RK4" --retract --category "x" --target "k-untouched" --reason "x" --confirm
after_k4="$(cat "$RK4/.agent/rules/safety.json")"
if [ "$RC" -ne 0 ] && [ "$before_k4" = "$after_k4" ]; then
  ok "(K4) --retract combined with --category rejected, store left byte-identical"
else
  no "(K4) --retract+--category NOT rejected/protected (rc=$RC)"
fi

# (K5) --retract of a nonexistent target is rejected, store untouched.
RK5="$(new_repo)"; before_k5="$(seed_store "$RK5")"
run_writer "$RK5" --retract --target "no-such-id" --reason "x" --confirm
after_k5="$(cat "$RK5/.agent/rules/safety.json")"
if [ "$RC" -ne 0 ] && [ "$before_k5" = "$after_k5" ]; then
  ok "(K5) --retract of a nonexistent target rejected, store left byte-identical"
else
  no "(K5) nonexistent-target retract NOT rejected/protected (rc=$RC)"
fi

# (K6) the ADD action rejects retract-only flags (--target/--reason/--replacement) without --retract.
RK6="$(new_repo)"; before_k6="$(seed_store "$RK6")"
run_writer "$RK6" --category "safety" --statement "should not write" --target "k-untouched" --reason "x" --confirm
after_k6="$(cat "$RK6/.agent/rules/safety.json")"
if [ "$RC" -ne 0 ] && [ "$before_k6" = "$after_k6" ]; then
  ok "(K6) ADD action rejects --target/--reason without --retract, store left byte-identical"
else
  no "(K6) ADD action did not reject retract-only flags (rc=$RC)"
fi

# ============================================================================
echo "== (L) existing hostile-category REJECT + traversal guards still fire alongside new flags =="
# Defense-in-depth: confirm the new --supersedes flag does not create a bypass path around the
# pre-existing category containment guard from section (A).
RL1="$(new_repo)"
run_writer "$RL1" --category "../escape" --statement "x" --supersedes "y" --confirm
if [ "$RC" -ne 0 ] && [ "$(count_rule_files "$RL1")" = "0" ]; then
  ok "(L1) hostile category still REJECTED when combined with --supersedes (no bypass)"
else
  no "(L1) hostile category + --supersedes NOT rejected (rc=$RC files=$(count_rule_files "$RL1"))"
fi
# And --retract itself does not bypass category containment either — a hostile category alongside
# --retract is rejected by the mode-exclusivity guard (K4-style), so no traversal write can occur.
RL2="$(new_repo)"
run_writer "$RL2" --retract --category "../escape" --target "x" --reason "y" --confirm
if [ "$RC" -ne 0 ] && [ "$(count_rule_files "$RL2")" = "0" ]; then
  ok "(L2) hostile category alongside --retract still rejected, no traversal write"
else
  no "(L2) hostile category + --retract NOT rejected (rc=$RC files=$(count_rule_files "$RL2"))"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
