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
#   (M) --applies-to (PATH ROUTING): REPEATABLE (N flags ⇒ N-element array, order preserved), a single
#       flag still authors an ARRAY, OMITTED ⇒ present-and-null (repo-wide, historical default),
#       traversal/hostile patterns (`../`, `a/../b`, absolute `/…`, `~/…`, empty, whitespace-only,
#       embedded newline, embedded 0x1F unit separator) REJECTED non-zero
#       with NO file written, one bad pattern among repeated flags aborts the WHOLE write, the flag is
#       rejected alongside --retract, and a writer→reader ROUND TRIP proves what is authored is what
#       read-rules.sh actually routes on.

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
run_writer "$RE" --category "prov" --statement "stamp me" --source "unit-test:pr-1" --confirm
src_e="$(jq -r '.[0].provenance.source' "$RE/.agent/rules/prov.json" 2>/dev/null)"
added_e="$(jq -r '.[0].provenance.added' "$RE/.agent/rules/prov.json" 2>/dev/null)"
[ "$src_e" = "unit-test:pr-1" ] && ok "(E) provenance.source stamped from --source" || no "(E) source=[$src_e]"
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

# ============================================================================
echo "== (M) --applies-to (PATH ROUTING): repeatable, defaults to null, rejects traversal =="

# (M1) REPEATABLE — N flags author an N-element array, in the order supplied.
RM1="$(new_repo)"
run_writer "$RM1" --category "Routing" --statement "Scoped rule one" \
  --applies-to "loomwright/scripts/*" --applies-to "*.sh" --confirm
if [ "$RC" -eq 0 ]; then
  got="$(jq -c '.[0].applies_to' "$RM1/.agent/rules/routing.json" 2>/dev/null)"
  [ "$got" = '["loomwright/scripts/*","*.sh"]' ] \
    && ok "(M1) two --applies-to flags author a 2-element array in order" \
    || no "(M1) expected [\"loomwright/scripts/*\",\"*.sh\"], got: $got"
else
  no "(M1) write with two --applies-to flags failed (rc=$RC): $OUT"
fi

# (M1b) a SINGLE flag authors a 1-element array (not a bare string).
RM1B="$(new_repo)"
run_writer "$RM1B" --category "Routing" --statement "Single scope" --applies-to "src/**" --confirm
got="$(jq -c '.[0].applies_to' "$RM1B/.agent/rules/routing.json" 2>/dev/null)"
[ "$RC" -eq 0 ] && [ "$got" = '["src/**"]' ] \
  && ok "(M1b) one --applies-to flag authors a 1-element ARRAY (never a bare string)" \
  || no "(M1b) expected [\"src/**\"], got: $got (rc=$RC)"

# (M2) OMITTED ⇒ applies_to is explicitly null (repo-wide) — the historical default, unchanged.
RM2="$(new_repo)"
run_writer "$RM2" --category "Routing" --statement "Repo wide rule" --confirm
if [ "$RC" -eq 0 ]; then
  got="$(jq -c '.[0].applies_to' "$RM2/.agent/rules/routing.json" 2>/dev/null)"
  [ "$got" = "null" ] \
    && ok "(M2) --applies-to omitted ⇒ applies_to: null (repo-wide default preserved)" \
    || no "(M2) expected null applies_to when the flag is omitted, got: $got"
  # ...and the key is PRESENT (null is a meaningful value here, not an omitted member like supersedes).
  jq -e '.[0] | has("applies_to")' "$RM2/.agent/rules/routing.json" >/dev/null 2>&1 \
    && ok "(M2) the applies_to key is present-and-null (not omitted)" \
    || no "(M2) applies_to key missing entirely"
else
  no "(M2) plain write failed (rc=$RC): $OUT"
fi

# (M3) TRAVERSAL / hostile patterns REJECTED with a non-zero exit and NO file written — mirroring the
# hostile-category rejection in section (A). A rejected pattern is never silently sanitized.
for badpat in "../escape/*" "a/../b" "/etc/passwd" "~/secrets/*" ""; do
  RM3="$(new_repo)"
  run_writer "$RM3" --category "Routing" --statement "Hostile pattern rule" --applies-to "$badpat" --confirm
  if [ "$RC" -ne 0 ] && [ "$(count_rule_files "$RM3")" = "0" ]; then
    ok "(M3) --applies-to '$badpat' REJECTED (rc=$RC) with no file written"
  else
    no "(M3) --applies-to '$badpat' NOT rejected (rc=$RC files=$(count_rule_files "$RM3"))"
  fi
done
# (M3b) a rejection among REPEATED flags aborts the whole write — one bad pattern poisons the add,
# it is never partially applied.
RM3B="$(new_repo)"
run_writer "$RM3B" --category "Routing" --statement "Mixed patterns" \
  --applies-to "src/*" --applies-to "../escape" --confirm
if [ "$RC" -ne 0 ] && [ "$(count_rule_files "$RM3B")" = "0" ]; then
  ok "(M3b) one hostile pattern among repeated flags aborts the entire write (no partial apply)"
else
  no "(M3b) mixed good/hostile --applies-to was not rejected (rc=$RC files=$(count_rule_files "$RM3B"))"
fi

# (M3c) EMBEDDED NEWLINE REJECTED — the accumulator is newline-TERMINATED, so an embedded newline
# would be swallowed as its own delimiter and ONE flag would silently become TWO patterns (the A2
# validation loop runs after that split and can never see it). Three doc surfaces assert newline is
# rejected (add-rule.sh's A2 table, skills/rules/SKILL.md §1, commands/rules.md); this pins that the
# reject actually fires, in the parsing arm, before the split.
RM3C="$(new_repo)"
run_writer "$RM3C" --category "Routing" --statement "Newline pattern rule" \
  --applies-to "$(printf 'src/*\ndocs/*')" --confirm
if [ "$RC" -ne 0 ] && [ "$(count_rule_files "$RM3C")" = "0" ]; then
  ok "(M3c) a newline-bearing --applies-to is REJECTED (rc=$RC) with no file written"
else
  no "(M3c) newline in --applies-to NOT rejected (rc=$RC files=$(count_rule_files "$RM3C")) — one flag silently became two patterns"
fi

# (M3d) 0x1F (UNIT SEPARATOR) REJECTED — read-rules.sh's `route_spec` strips 0x1F with the same gsub
# as tab/newline, AND 0x1F is the route cell's own join delimiter. Accepting one would store a pattern
# the reader then silently alters — the exact "sanitized into a safe-looking form instead of rejected"
# outcome A1 exists to prevent.
RM3D="$(new_repo)"
run_writer "$RM3D" --category "Routing" --statement "Unit separator pattern rule" \
  --applies-to "$(printf 'src/\037x')" --confirm
if [ "$RC" -ne 0 ] && [ "$(count_rule_files "$RM3D")" = "0" ]; then
  ok "(M3d) a 0x1F-bearing --applies-to is REJECTED (rc=$RC) with no file written"
else
  no "(M3d) 0x1F in --applies-to NOT rejected (rc=$RC files=$(count_rule_files "$RM3D")) — the reader would silently strip it"
fi

# (M3e) WHITESPACE-ONLY REJECTED — passes the non-empty check but matches nothing (no touched path is
# a bare space), so it is a silent dead rule for the same reason the empty pattern is. Mirrors the
# `--target` whitespace-only guard in the retract path. A lone TAB is deliberately NOT in this list:
# it is whitespace, but the guard order puts the tab-specific reject FIRST, so it belongs to (M3f).
for wspat in " " "   "; do
  RM3E="$(new_repo)"
  run_writer "$RM3E" --category "Routing" --statement "Whitespace pattern rule" \
    --applies-to "$wspat" --confirm
  if [ "$RC" -ne 0 ] && [ "$(count_rule_files "$RM3E")" = "0" ]; then
    ok "(M3e) a whitespace-only --applies-to is REJECTED (rc=$RC) with no file written"
  else
    no "(M3e) whitespace-only --applies-to NOT rejected (rc=$RC files=$(count_rule_files "$RM3E")) — a silent dead rule"
  fi
done

# (M3f) CR and TAB REJECTED BY THEIR OWN SPECIFIC ARMS — both as a lone character and embedded in an
# otherwise non-whitespace pattern. CR rejection is documented in three places (this writer's A2 table,
# skills/rules/SKILL.md §7, and the PR narrative) and had no check at all; and because a lone CR / lone
# TAB is entirely whitespace under `[:space:]`, those arms are only reachable while the specific
# control-character `case` runs BEFORE the whitespace-only catch-all. Asserting the SPECIFIC message
# (not merely rc!=0) is what makes a future re-reorder fail here instead of passing silently.
for cpat_label in \
  "lone-CR|$(printf '\r')|carriage-return" \
  "embedded-CR|src/$(printf '\r')foo|carriage-return" \
  "lone-TAB|$(printf '\t')|tab" \
  "embedded-TAB|src/$(printf '\t')foo|tab"; do
  cf_name="${cpat_label%%|*}"
  cf_rest="${cpat_label#*|}"
  cf_pat="${cf_rest%|*}"
  cf_msg="${cf_rest##*|}"
  RM3F="$(new_repo)"
  run_writer "$RM3F" --category "Routing" --statement "Control character pattern rule" \
    --applies-to "$cf_pat" --confirm
  if [ "$RC" -ne 0 ] && [ "$(count_rule_files "$RM3F")" = "0" ] \
     && printf '%s' "$OUT" | grep -qF -- "may not contain $cf_msg characters"; then
    ok "(M3f) $cf_name --applies-to REJECTED (rc=$RC) with no file written and the $cf_msg-specific diagnostic"
  else
    no "(M3f) $cf_name --applies-to did not hit the $cf_msg-specific reject (rc=$RC files=$(count_rule_files "$RM3F")): $OUT"
  fi
done

# (M4) --applies-to is an ADD-only flag: combining it with --retract is rejected outright (R1).
RM4="$(new_repo)"
run_writer "$RM4" --retract --target "x" --reason "y" --applies-to "src/*" --confirm
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -qF -- "--applies-to"; then
  ok "(M4) --retract + --applies-to REJECTED, and the diagnostic names the offending flag"
else
  no "(M4) --retract + --applies-to not rejected with a naming diagnostic (rc=$RC): $OUT"
fi

# (M5) ROUND-TRIP: what this writer authors is exactly what read-rules.sh routes on. Guards the
# writer/reader contract seam — a pattern that writes fine but never matches would be a dead rule.
RM5="$(new_repo)"
run_writer "$RM5" --category "Routing" --statement "Round trip scoped rule" \
  --applies-to "loomwright/scripts/*" --confirm
if [ "$RC" -eq 0 ]; then
  rt_in="$( cd "$RM5" && bash "$SCRIPT_DIR/read-rules.sh" loomwright/scripts/x.sh 2>/dev/null )"
  rt_out="$( cd "$RM5" && bash "$SCRIPT_DIR/read-rules.sh" docs/x.md 2>/dev/null )"
  rt_noarg="$( cd "$RM5" && bash "$SCRIPT_DIR/read-rules.sh" 2>/dev/null )"
  if echo "$rt_in" | grep -qF -- "- Round trip scoped rule" \
     && ! echo "$rt_out" | grep -qF "Round trip scoped rule" \
     && echo "$rt_noarg" | grep -qF -- "- Round trip scoped rule"; then
    ok "(M5) writer→reader round trip: in-scope emits, out-of-scope ABSENT, no-arg repo-wide"
  else
    no "(M5) round trip failed — in:[$rt_in] out:[$rt_out] noarg:[$rt_noarg]"
  fi
else
  no "(M5) round-trip write failed (rc=$RC): $OUT"
fi

# =============================================================================
# AC1 / AC2 / AC10b — WRITE-TIME VALIDATION AND THE NEW WORKTREE GUARD.
#
# Wiring add-rule.sh to validate-entry.sh makes test-validate-entry.sh green and this suite green,
# and NEITHER proves this writer ever CALLS the validator — a writer that `source`s the helper and
# never invokes it passes both. The per-writer coverage below is what pins the call site.
#
# THREE SEPARATE ASSERTIONS PER CASE (AC2), and the separation is the point: this writer commits via
# temp file + atomic `mv`, so "byte-unchanged" is ALSO true of a crash, an arg-parse rejection and a
# `command not found`. Each case asserts (i) the refusal EXIT STATUS, (ii) a NAMED, GREPPABLE reason
# on stderr, and (iii) the store byte-unchanged — via `cmp` against a saved copy, not a digest
# (`md5 -q` is BSD-only and this suite runs on Linux CI too).
#
# AC10b is NEW BEHAVIOUR here, not a re-verification: this writer shipped with NO worktree guard.
# The guard is two behaviours and both are pinned below, because copying only half of
# write-lessons.sh's guard is the plausible mistake — see the AC10b block.
# Long-form rationale for the shared fixture design lives in test-lessons.sh's equivalent section.
# =============================================================================
echo "== AC1/AC2/AC10b: write-time validation + the new worktree guard =="
VETMP="$(mktemp -d)"
VEFILE="$SCRIPT_DIR/validate-entry.sh"
VE_ERR="$VETMP/stderr"
VE_ALLOW=""
VESTORE=".agent/rules/ve.json"

ve_repo() {
  local r; r="$(mktemp -d "$VETMP/r.XXXXXX")"
  ( cd "$r" && git init -q && git config user.email t@t && git config user.name t \
      && echo init > f && git add f && git commit -qm init ) >/dev/null 2>&1
  printf '%s' "$r"
}

# ve_write <dir> <statement> <source> [validator-override] [writer-path] -> sets VE_RC, writes VE_ERR.
# --confirm is passed because the validator call site sits BEFORE the confirm gate and the write must
# actually be attempted; a dry-run would exit 0 without ever reaching the store.
# An EMPTY validator-override leaves $ADD_RULE_VALIDATOR empty, which is what makes the writer fall
# back to its own resolution — the real path, not a test-only one.
ve_write() {
  local repo="$1" txt="$2" src="$3" val="${4:-}" prog="${5:-$WRITER}"
  ( cd "$repo" \
      && if [ -n "$VE_ALLOW" ]; then export LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$VE_ALLOW"; fi \
      && ADD_RULE_VALIDATOR="$val" bash "$prog" --category ve --statement "$txt" \
           --source "$src" --confirm \
  ) >/dev/null 2>"$VE_ERR"
  VE_RC=$?
}

ve_refused() { # <label> <want-rc> <want-token> <store> <saved-copy>
  local label="$1" wrc="$2" tok="$3" st="$4" b4="$5"
  if [ "$VE_RC" -eq "$wrc" ]; then ok "$label (i) refused with exit $wrc"
  else no "$label (i) exit $VE_RC, want $wrc"; fi
  if grep -q "$tok" "$VE_ERR" 2>/dev/null; then ok "$label (ii) stderr names $tok"
  else no "$label (ii) stderr does NOT name $tok — got: $(tr '\n' ' ' < "$VE_ERR" | cut -c1-160)"; fi
  if cmp -s "$st" "$b4"; then ok "$label (iii) store byte-unchanged"
  else no "$label (iii) the refusal MUTATED the store"; fi
}

# Each seed violates EXACTLY ONE check, because validate_entry_all returns the FIRST non-zero verdict
# in a fixed order — a seed that tripped an earlier check would assert nothing about the later one.
#
# The seeds are DELIBERATELY LONG (14 significant tokens), and that is a measured requirement here
# rather than padding. This writer's store is a JSON array, so the stored side of the comparison is
# the pretty-printed `"statement": "..."` line, which carries one extra significant token (`statement`)
# that the entry does not. Overlap is scored over the LARGER token set, so the duplicate check sees
# N/(N+1) and the 90% threshold needs N >= 9. The 8-token seed used elsewhere scored 88 and passed —
# the check working correctly, not a bug, but a fixture that would have asserted nothing.
VE_BASE="release candidates promote through staging validation before production rollout begins across every regional cluster"
VE_DUP="across every regional cluster release candidates promote through staging validation before production rollout begins"
VE_CON="release candidates never promote through staging validation before production rollout begins across every regional cluster"
VE_PROV="the shared cache layer warms lazily on its very first read"
VE_DEAD="the retry helper now lives at loomwright/scripts/no-such-helper-xyz.sh"
VE_XREPO="the same defect was fixed in OTHERSVC #146"
VE_CLEAN="observability dashboards refresh their panels whenever a new deployment finishes rolling out"
VE_SRC="session:ve-0001"
VE_OURS="vikashruhilgit/loomwright"

# The cross-repo allowlist is supplied through this test's OWN environment; the live
# .supervisor/config.json is never touched and no foreign slug is ever added to it (R0/R8).
ve_case() { # <label> <text> <source> <want-token> [allowlist]
  local label="$1" txt="$2" src="$3" tok="$4" allow="${5:-}"
  local r st; r="$(ve_repo)"; st="$r/$VESTORE"
  ve_write "$r" "$VE_BASE" "$VE_SRC"
  if [ ! -f "$st" ]; then no "$label — SEED FAILED (no rules file; the fixture asserts nothing)"; return; fi
  cp "$st" "$VETMP/before"
  VE_ALLOW="$allow"; ve_write "$r" "$txt" "$src"; VE_ALLOW=""
  ve_refused "AC1 $label:" 1 "$tok" "$st" "$VETMP/before"
}

ve_case "duplicate"      "$VE_DUP"   "$VE_SRC"   "REFUSE_DUPLICATE"
ve_case "contradiction"  "$VE_CON"   "$VE_SRC"   "REFUSE_CONTRADICTION"
ve_case "provenance"     "$VE_PROV"  "dreaming"  "REFUSE_PROVENANCE"
ve_case "dead-reference" "$VE_DEAD"  "$VE_SRC"   "REFUSE_DEAD_REFERENCE"
ve_case "cross-repo"     "$VE_XREPO" "$VE_SRC"   "REFUSE_CROSS_REPO" "$VE_OURS"

# AC2 — the degraded-helper shapes, each built from the REAL helper (so they cannot drift from it)
# and each aimed at a DIFFERENT clause of the three-clause load guard:
#   absent     -> the `[ -f ] || [ -r ]` pre-check
#   unparse    -> clause (i): a trailing syntax error makes `source` exit non-zero. Bash still
#                 defines every function above the error, so this shape has ALL five validators AND
#                 the sentinel — only the source status distinguishes it.
#   partial    -> clause (ii): cut above validate_dead_reference, so three validators are defined and
#                 validate_entry_all is not. This is the shape a one-function `command -v` probe
#                 would wave through as "examined and clean".
#   nosentinel -> clause (iii): everything defined and working, only the contract sentinel missing.
#                 Nothing but clause (iii) can catch it, which is why it is also the vehicle for the
#                 `|| true` mutation control below.
cp "$VEFILE" "$VETMP/unparse.sh"; printf '\nif [ ; then\n' >> "$VETMP/unparse.sh"
awk '/^validate_dead_reference\(\)/{exit} {print}'  "$VEFILE" > "$VETMP/partial.sh"
awk '/^VALIDATE_ENTRY_CONTRACT="/{exit} {print}'    "$VEFILE" > "$VETMP/nosentinel.sh"

if bash -n "$VETMP/partial.sh" 2>/dev/null && bash -n "$VETMP/nosentinel.sh" 2>/dev/null \
   && ! bash -n "$VETMP/unparse.sh" 2>/dev/null; then
  ok "AC2 fixtures: partial+nosentinel parse cleanly, unparse does not (each aimed at its own clause)"
else
  no "AC2 fixtures: a degraded-helper variant is not the shape it claims — the clause labels below are unreliable"
fi

ve_degraded() { # <label> <validator-path>; attempted with a CLEAN entry, so the ONLY reason to
                # refuse is the broken helper.
  local label="$1" val="$2" r st; r="$(ve_repo)"; st="$r/$VESTORE"
  ve_write "$r" "$VE_BASE" "$VE_SRC"
  if [ ! -f "$st" ]; then no "AC2 $label — SEED FAILED"; return; fi
  cp "$st" "$VETMP/before"
  ve_write "$r" "$VE_CLEAN" "$VE_SRC" "$val"
  ve_refused "AC2 $label:" 2 "REFUSE_VALIDATOR_UNAVAILABLE" "$st" "$VETMP/before"
}
ve_degraded "helper absent"        "$VETMP/no-such-validator.sh"
ve_degraded "helper unparseable"   "$VETMP/unparse.sh"
ve_degraded "helper truncated"     "$VETMP/partial.sh"
ve_degraded "helper sentinel-less" "$VETMP/nosentinel.sh"

# MUTATION CONTROLS. Both mutants are COPIES in $VETMP: the writer on disk is never edited, which
# makes "this writer goes RED while the other four stay green" true by construction rather than by a
# sibling run — a temp-file copy provably cannot reach the other four writers. Each mutant is gated
# on being non-empty, actually different, and still parseable before anything is credited to it.
ve_mutant_ok() { # <file> <desc>
  if [ ! -s "$1" ];              then no "$2 — mutant is EMPTY (vacuous control)"; return 1; fi
  if cmp -s "$WRITER" "$1";      then no "$2 — mutation changed NOTHING (vacuous control)"; return 1; fi
  if ! bash -n "$1" 2>/dev/null; then no "$2 — mutant does not parse (vacuous control)"; return 1; fi
  return 0
}

# (a) AC1's mandated per-writer control: script the VALIDATOR CALL block out. REPLACED with `:`
# rather than deleted, so no enclosing block is left with an empty body (a bash syntax error, and a
# mutant that cannot run proves nothing).
awk '/---- VALIDATOR CALL BEGIN/{s=1; print "  :"; next} /---- VALIDATOR CALL END/{s=0; next} !s' \
  "$WRITER" > "$VETMP/mut-call.sh"
if ve_mutant_ok "$VETMP/mut-call.sh" "AC1 call-site mutant"; then
  r="$(ve_repo)"; st="$r/$VESTORE"
  ve_write "$r" "$VE_BASE" "$VE_SRC"
  cp "$st" "$VETMP/before"
  ve_write "$r" "$VE_CON" "$VE_SRC" "$VEFILE" "$VETMP/mut-call.sh"
  if [ "$VE_RC" -eq 0 ] && ! cmp -s "$st" "$VETMP/before"; then
    ok "AC1 mutation control: deleting the VALIDATOR CALL lets the contradiction seed through (exit 0, store grew) — the fixtures above are RED because of the call site, not the source line"
  else
    no "AC1 mutation control: the call-site mutant STILL refused (exit $VE_RC) — the AC1 fixtures may be passing for some other reason"
  fi
fi

# (b) AC2's mandated control: replace the whole load guard with the repo's pervasive `|| true`
# convention — the one line decision (a) forbids on the source. Paired with the sentinel-less helper
# because that is the shape where the mutation is OBSERVABLE: with an absent or truncated helper the
# writer still fails closed by accident (validate_entry_all is undefined, the call returns 127, the
# writer exits 2 with no named reason), but with a sentinel-less helper every validator works, so
# dropping the guard lets an UNVERIFIED-CONTRACT write go all the way through. All three AC2
# assertions go RED at once: exit 0, no named reason, store MUTATED.
awk '/---- LOAD GUARD BEGIN/{s=1; print "  . \"$VALIDATOR\" || true"; next} /---- LOAD GUARD END/{s=0; next} !s' \
  "$WRITER" > "$VETMP/mut-guard.sh"
if ve_mutant_ok "$VETMP/mut-guard.sh" "AC2 load-guard mutant"; then
  if grep -q '|| true' "$VETMP/mut-guard.sh"; then
    r="$(ve_repo)"; st="$r/$VESTORE"
    ve_write "$r" "$VE_BASE" "$VE_SRC"
    cp "$st" "$VETMP/before"
    ve_write "$r" "$VE_CLEAN" "$VE_SRC" "$VETMP/nosentinel.sh" "$VETMP/mut-guard.sh"
    if [ "$VE_RC" -eq 0 ] && ! grep -q REFUSE_VALIDATOR_UNAVAILABLE "$VE_ERR" 2>/dev/null \
       && ! cmp -s "$st" "$VETMP/before"; then
      ok "AC2 mutation control: replacing the load guard with '|| true' turns all three assertions RED (exit 0, no named reason, store mutated)"
    else
      no "AC2 mutation control: the '|| true' mutant did not go RED (exit $VE_RC) — AC2 may be passing for some other reason"
    fi
  else
    no "AC2 mutation control: the '|| true' replacement did not land in the mutant"
  fi
fi

# ---------------------------------------------------------------------------
# AC10b — THE NEW WORKTREE GUARD. This writer shipped with NONE: `git rev-parse --show-toplevel` in a
# linked worktree returns the WORKTREE's own toplevel, so a worker running there wrote to the
# worktree's .agent/rules/ and lost it on `git worktree remove`.
#
# The guard is TWO behaviours and both are asserted, because copying write-lessons.sh's guard
# WHOLESALE is the plausible mistake and only half of it transfers:
#   (i)  a worktree CWD refuses with exit 3;
#   (ii) the non-git-repo fallback stays UNCHANGED — this writer deliberately falls back to `pwd`
#        (fixtures and temp stores are legitimate callers), and write-lessons.sh's hard `exit 2`
#        outside a repo must NOT come across. Asserting only (i) would leave a guard that passes
#        while having broken every non-repo caller.
# The worktree case additionally runs with a deliberately ABSENT validator, proving the worktree
# guard sits AHEAD of the validator load guard: otherwise a worktree write would start reporting
# "could not examine" (exit 2) and the F1 refusal would be masked by AC2's.
# ---------------------------------------------------------------------------
VEWT="$(ve_repo)"
git -C "$VEWT" worktree add -q "$VEWT-wt" -b vewt >/dev/null 2>&1
if [ -d "$VEWT-wt" ]; then
  ve_write "$VEWT-wt" "$VE_CLEAN" "$VE_SRC" "$VETMP/no-such-validator.sh"
  if [ "$VE_RC" -eq 3 ] && grep -q worktree "$VE_ERR" 2>/dev/null; then
    ok "AC10b(i): a worktree CWD refuses with exit 3, ahead of the validator load guard (absent helper does not mask it)"
  else
    no "AC10b(i): worktree refusal is exit $VE_RC (want 3): $(tr '\n' ' ' < "$VE_ERR" | cut -c1-160)"
  fi
  if [ -e "$VEWT-wt/.agent/rules" ]; then no "AC10b(i): a rules file leaked into the worktree"
  else ok "AC10b(i): nothing written under the worktree"; fi
  git -C "$VEWT" worktree remove --force "$VEWT-wt" >/dev/null 2>&1
else
  no "AC10b(i): could not create the fixture worktree — the assertion would be vacuous"
fi

VENOGIT="$(mktemp -d "$VETMP/nogit.XXXXXX")"
if git -C "$VENOGIT" rev-parse --show-toplevel >/dev/null 2>&1; then
  no "AC10b(ii): the fixture dir is inside a git repo — the non-repo assertion would be vacuous"
else
  ve_write "$VENOGIT" "$VE_CLEAN" "$VE_SRC"
  if [ "$VE_RC" -eq 0 ] && [ -f "$VENOGIT/$VESTORE" ]; then
    ok "AC10b(ii): outside a git repo the writer still falls back to pwd and writes (exit 0) — write-lessons.sh's hard exit 2 was NOT copied across"
  else
    no "AC10b(ii): the non-git-repo fallback REGRESSED (exit $VE_RC, store $([ -f "$VENOGIT/$VESTORE" ] && echo written || echo absent)): $(tr '\n' ' ' < "$VE_ERR" | cut -c1-160)"
  fi
fi
rm -rf "$VETMP" "$VEWT-wt" 2>/dev/null

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
