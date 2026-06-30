#!/usr/bin/env bash
# test-read-rules.sh — self-tests for read-rules.sh, the fail-safe ADVISORY reader for the committed
# .agent/rules/ house-rules substrate (Subtask 3 of the rules-substrate job). Runs the reader inside
# ISOLATED temp git repos via `mktemp -d` + `git init` so it NEVER touches the real .agent/rules/
# (which ships ONLY README.md and no live *.json — this test must not leave any fixture *.json there).
# The reader does `git rev-parse --show-toplevel` then cd's there and globs .agent/rules/*.json, so we
# `cd` into each temp repo to point it at that repo's fixture store. Mirrors the test-build-handoff.sh
# harness convention. Exit 0 = all pass, 1 = any failure (auto-registered by ci.yml's test-*.sh glob).
#
# Covers cases (a)–(h):
#   (a) absent .agent/rules/                  → no output, exit 0
#   (b) populated valid fixture (must+advisory)→ banner present, must flagged, advisory unflagged
#   (c) malformed *.json sibling              → fail-safe (no crash, exit 0), valid sibling still emitted
#   (d) jq-absent simulation                  → emit nothing, exit 0
#   (e) THE INVARIANT — check is DATA not EXEC → marker file NOT created; check string IS in stdout
#   (f) empty / all-invalid                    → EMPTY stdout (no banner), exit 0
#   (g) object validation skip-cases          → (g1) missing field, (g2) bad enforcement, (g3) dup id,
#                                                (g4) missing required `check` key, (g5) explicit
#                                                check:null still valid; invalid SKIPPED, valid emit; exit 0
#   (h) deterministic ordering                 → multi-rule fixture run twice ⇒ byte-identical stdout

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
READER="$SCRIPT_DIR/read-rules.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

# All temp dirs live under ONE root so a single trap reliably cleans everything (incl. invariant marker).
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT" 2>/dev/null' EXIT

# Allocate a fresh temp subdir UNDER $ROOT and echo its path.
mktmp() { mktemp -d "$ROOT/d.XXXXXX"; }

# Create an isolated temp git repo (so the reader's `git rev-parse --show-toplevel` resolves to it).
new_repo() {
  local r; r="$(mktmp)"
  ( cd "$r" && git init -q && git config user.email t@t && git config user.name t \
      && echo init > f && git add f && git commit -qm init ) >/dev/null 2>&1
  printf '%s' "$r"
}

# Write a *.json rule file under a repo's .agent/rules/. $1 repo  $2 filename  $3 JSON content.
seed_rules_file() {
  local repo="$1" fname="$2" content="$3"
  mkdir -p "$repo/.agent/rules"
  printf '%s' "$content" > "$repo/.agent/rules/$fname"
}

# Run the reader inside a temp repo; capture stdout only (cd so --show-toplevel = the temp repo).
run_reader() { ( cd "$1" && bash "$READER" ); }

if ! command -v jq >/dev/null 2>&1; then
  echo "test-read-rules: jq absent on this host — read-rules.sh no-ops (exit 0). Skipping data assertions."
  echo "RESULT: 0 passed, 0 failed (jq absent, vacuous)"
  exit 0
fi

BANNER="## Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)"

# ============================================================================
echo "== (a) absent .agent/rules/ → no output, exit 0 =="
RA="$(new_repo)"   # bare repo: no .agent/ at all
outA="$(run_reader "$RA")"; rcA=$?
[ "$rcA" -eq 0 ] && ok "exits 0 with no .agent/rules/" || no "expected exit 0, got $rcA"
[ -z "$outA" ] && ok "emits no output when .agent/rules/ absent" || no "expected empty output; got: $outA"

# ============================================================================
echo "== (b) populated valid fixture (must + advisory) → banner, must flagged, advisory unflagged =="
RB="$(new_repo)"
seed_rules_file "$RB" "core.json" '[
  {"id":"r-must","category":"safety","statement":"Always verify before asserting state","enforcement":"must","check":"echo verify","provenance":{"source":"test"}},
  {"id":"r-adv","category":"style","statement":"Prefer descriptive anchors","enforcement":"advisory","check":null,"provenance":{"source":"test"}}
]'
outB="$(run_reader "$RB")"; rcB=$?
[ "$rcB" -eq 0 ] && ok "exits 0" || no "expected exit 0, got $rcB"
echo "$outB" | grep -qF "$BANNER" && ok "advisory banner present" || no "banner missing"
# `must` rule is flagged with the [MUST] marker on its statement line.
echo "$outB" | grep -qF -- "- [MUST] Always verify before asserting state" \
  && ok "must rule flagged with [MUST]" || no "must rule not flagged with [MUST]"
# advisory rule statement line carries NO [MUST] flag.
if echo "$outB" | grep -qF -- "- Prefer descriptive anchors" \
   && ! echo "$outB" | grep -qF "[MUST] Prefer descriptive anchors"; then
  ok "advisory rule unflagged (no [MUST])"
else
  no "advisory rule flagging incorrect"
fi
# category + check-data lines render (using the reader's EXACT prefixes).
echo "$outB" | grep -qF "  - category: safety" && ok "category line renders" || no "category line missing"
echo "$outB" | grep -qF "  - check (data only, NOT executed by this reader): echo verify" \
  && ok "check-as-data line renders verbatim" || no "check-as-data line missing"

# ============================================================================
echo "== (c) malformed *.json sibling alongside a valid file → fail-safe, valid sibling still emitted =="
RC="$(new_repo)"
seed_rules_file "$RC" "good.json" '[
  {"id":"c-good","category":"safety","statement":"This valid rule survives","enforcement":"advisory","check":null,"provenance":{"source":"test"}}
]'
seed_rules_file "$RC" "bad.json" '{ this is not valid json at all ]['
outC="$(run_reader "$RC")"; rcC=$?
[ "$rcC" -eq 0 ] && ok "exits 0 despite malformed sibling (fail-safe)" || no "expected exit 0, got $rcC"
echo "$outC" | grep -qF -- "- This valid rule survives" \
  && ok "valid sibling still emitted past the malformed file" || no "valid sibling not emitted"

# ============================================================================
echo "== (d) jq-absent simulation → emit nothing, exit 0 =="
RD="$(new_repo)"
seed_rules_file "$RD" "core.json" '[
  {"id":"d-1","category":"safety","statement":"Would render if jq present","enforcement":"advisory","check":null,"provenance":{"source":"test"}}
]'
# Robust jq-absent simulation: run with a PATH that contains ONLY a coreutils dir but NO jq. We point
# PATH at a temp bin holding symlinks to the binaries the reader needs (git/find/sort/date/mkdir/...)
# but deliberately OMIT jq, so the reader's `command -v jq` fails. Confirm the simulation actually
# hides jq before trusting the assertion.
STUBBIN="$(mktmp)/bin"; mkdir -p "$STUBBIN"
for b in git find sort date mkdir dirname rm cat sed grep env bash sh; do
  src="$(command -v "$b" 2>/dev/null)"
  [ -n "$src" ] && ln -sf "$src" "$STUBBIN/$b"
done
# Sanity: jq must NOT be resolvable on this stub PATH.
if PATH="$STUBBIN" command -v jq >/dev/null 2>&1; then
  no "jq-absent simulation failed — jq still resolvable on stub PATH"
else
  ok "jq-absent simulation effective — jq not resolvable on stub PATH"
  outD="$( cd "$RD" && PATH="$STUBBIN" bash "$READER" )"; rcD=$?
  [ "$rcD" -eq 0 ] && ok "exits 0 with jq unavailable" || no "expected exit 0, got $rcD"
  [ -z "$outD" ] && ok "emits nothing when jq unavailable" || no "expected empty output; got: $outD"
fi

# ============================================================================
echo "== (e) THE INVARIANT — check is emitted as DATA but NEVER executed =="
RE="$(new_repo)"
MARKER="$ROOT/INVARIANT_MARKER_$$_should_not_exist"
rm -f "$MARKER" 2>/dev/null
# A rule whose `check` would CREATE the marker file IF (and only if) the reader ever executed it.
seed_rules_file "$RE" "danger.json" "[
  {\"id\":\"e-evil\",\"category\":\"safety\",\"statement\":\"Side-effecting check must stay inert\",\"enforcement\":\"must\",\"check\":\"touch $MARKER\",\"provenance\":{\"source\":\"test\"}}
]"
outE="$(run_reader "$RE")"; rcE=$?
[ "$rcE" -eq 0 ] && ok "exits 0" || no "expected exit 0, got $rcE"
# Load-bearing: the marker file must NOT exist — the check was NOT executed.
[ ! -e "$MARKER" ] && ok "INVARIANT: check NOT executed (marker file absent)" \
  || no "SECURITY REGRESSION: check WAS executed (marker file created at $MARKER)"
# The check string must appear in stdout as data.
echo "$outE" | grep -qF "  - check (data only, NOT executed by this reader): touch $MARKER" \
  && ok "INVARIANT: check string emitted verbatim as data in stdout" || no "check string not emitted as data"

# ============================================================================
echo "== (f) empty / all-invalid → EMPTY stdout (no banner), exit 0 =="
# (f1) a *.json that is a valid-but-EMPTY array.
RF="$(new_repo)"
seed_rules_file "$RF" "empty.json" '[]'
outF="$(run_reader "$RF")"; rcF=$?
[ "$rcF" -eq 0 ] && ok "(empty array) exits 0" || no "expected exit 0, got $rcF"
[ -z "$outF" ] && ok "(empty array) EMPTY stdout (no banner)" || no "expected empty output; got: $outF"
# (f2) a *.json whose only object is invalid (all rules dropped) ⇒ no banner.
RF2="$(new_repo)"
seed_rules_file "$RF2" "allbad.json" '[
  {"id":"f-bad","category":"safety","statement":"missing enforcement field","check":null,"provenance":{"source":"test"}}
]'
outF2="$(run_reader "$RF2")"; rcF2=$?
[ "$rcF2" -eq 0 ] && ok "(all-invalid) exits 0" || no "expected exit 0, got $rcF2"
[ -z "$outF2" ] && ok "(all-invalid) EMPTY stdout (no banner)" || no "expected empty output; got: $outF2"

# ============================================================================
echo "== (g) object validation skip-cases: missing field / bad enforcement / duplicate id =="
# (g1) missing-required-field object dropped; valid sibling survives.
RG1="$(new_repo)"
seed_rules_file "$RG1" "g1.json" '[
  {"id":"g1-bad","category":"safety","enforcement":"advisory","check":null,"provenance":{"source":"test"}},
  {"id":"g1-good","category":"safety","statement":"Valid sibling g1 survives","enforcement":"advisory","check":null,"provenance":{"source":"test"}}
]'
outG1="$(run_reader "$RG1")"; rcG1=$?
[ "$rcG1" -eq 0 ] && ok "(g1 missing field) exits 0" || no "expected exit 0, got $rcG1"
if echo "$outG1" | grep -qF -- "- Valid sibling g1 survives" \
   && ! echo "$outG1" | grep -qF "g1-bad"; then
  ok "(g1) missing-field object SKIPPED, valid sibling emitted"
else
  no "(g1) missing-field skip incorrect"
fi
# (g2) unknown enforcement value dropped; valid sibling survives.
RG2="$(new_repo)"
seed_rules_file "$RG2" "g2.json" '[
  {"id":"g2-bad","category":"safety","statement":"unknown enforcement","enforcement":"mandatory","check":null,"provenance":{"source":"test"}},
  {"id":"g2-good","category":"safety","statement":"Valid sibling g2 survives","enforcement":"must","check":null,"provenance":{"source":"test"}}
]'
outG2="$(run_reader "$RG2")"; rcG2=$?
[ "$rcG2" -eq 0 ] && ok "(g2 bad enforcement) exits 0" || no "expected exit 0, got $rcG2"
if echo "$outG2" | grep -qF -- "- [MUST] Valid sibling g2 survives" \
   && ! echo "$outG2" | grep -qF "unknown enforcement"; then
  ok "(g2) unknown-enforcement object SKIPPED, valid sibling emitted"
else
  no "(g2) unknown-enforcement skip incorrect"
fi
# (g3) duplicate id — first-seen wins, the later duplicate is dropped.
RG3="$(new_repo)"
seed_rules_file "$RG3" "g3.json" '[
  {"id":"dup","category":"safety","statement":"First seen dup wins","enforcement":"advisory","check":null,"provenance":{"source":"test"}},
  {"id":"dup","category":"safety","statement":"Second dup is dropped","enforcement":"advisory","check":null,"provenance":{"source":"test"}}
]'
outG3="$(run_reader "$RG3")"; rcG3=$?
[ "$rcG3" -eq 0 ] && ok "(g3 duplicate id) exits 0" || no "expected exit 0, got $rcG3"
if echo "$outG3" | grep -qF -- "- First seen dup wins" \
   && ! echo "$outG3" | grep -qF "Second dup is dropped"; then
  ok "(g3) duplicate id: first-seen wins, later duplicate SKIPPED"
else
  no "(g3) duplicate-id handling incorrect"
fi

# (g4) missing `check` key entirely — `check` is a REQUIRED field (schema: string OR null),
# so an object with NO `check` key is SKIPPED, just like a missing id/statement/etc. Guards the
# spec-vs-impl gap where a missing key (jq null) slipped past the present-but-wrong-type guard.
RG4="$(new_repo)"
seed_rules_file "$RG4" "g4.json" '[
  {"id":"g4-bad","category":"safety","statement":"missing the required check key","enforcement":"advisory","provenance":{"source":"test"}},
  {"id":"g4-good","category":"safety","statement":"Valid sibling g4 survives","enforcement":"advisory","check":null,"provenance":{"source":"test"}}
]'
outG4="$(run_reader "$RG4")"; rcG4=$?
[ "$rcG4" -eq 0 ] && ok "(g4 missing check key) exits 0" || no "expected exit 0, got $rcG4"
if echo "$outG4" | grep -qF -- "- Valid sibling g4 survives" \
   && ! echo "$outG4" | grep -qF "missing the required check key"; then
  ok "(g4) missing-check object SKIPPED, valid sibling emitted"
else
  no "(g4) missing-check skip incorrect — a rule with no check key must be dropped"
fi

# (g5) explicit "check": null is STILL valid (present key, null value) — guards against the g4
# fix over-correcting into rejecting legitimate null checks.
RG5="$(new_repo)"
seed_rules_file "$RG5" "g5.json" '[
  {"id":"g5-nullcheck","category":"safety","statement":"Explicit null check is valid","enforcement":"advisory","check":null,"provenance":{"source":"test"}}
]'
outG5="$(run_reader "$RG5")"; rcG5=$?
[ "$rcG5" -eq 0 ] && ok "(g5 explicit null check) exits 0" || no "expected exit 0, got $rcG5"
echo "$outG5" | grep -qF -- "- Explicit null check is valid" \
  && ok "(g5) explicit check:null rule still emitted" \
  || no "(g5) explicit check:null rule should remain valid"
# (g5b) and a null check renders as the literal "(none)" sentinel (the `(.check // "(none)")` branch).
echo "$outG5" | grep -qF -- "check (data only, NOT executed by this reader): (none)" \
  && ok "(g5b) null check renders as (none)" \
  || no "(g5b) null check should render as (none)"

# ============================================================================
echo "== (h) deterministic ordering: multi-rule fixture run twice ⇒ byte-identical stdout =="
RH="$(new_repo)"
# Spread across multiple files + unsorted categories/ids to exercise the sort_by([category,id]) path.
seed_rules_file "$RH" "z-file.json" '[
  {"id":"zeta","category":"zoning","statement":"Zeta rule","enforcement":"advisory","check":null,"provenance":{"source":"test"}},
  {"id":"alpha","category":"access","statement":"Alpha rule","enforcement":"must","check":"echo a","provenance":{"source":"test"}}
]'
seed_rules_file "$RH" "a-file.json" '[
  {"id":"mid","category":"middleware","statement":"Mid rule","enforcement":"advisory","check":null,"provenance":{"source":"test"}},
  {"id":"beta","category":"access","statement":"Beta rule","enforcement":"advisory","check":null,"provenance":{"source":"test"}}
]'
outH1="$(run_reader "$RH")"; rcH1=$?
outH2="$(run_reader "$RH")"; rcH2=$?
[ "$rcH1" -eq 0 ] && [ "$rcH2" -eq 0 ] && ok "(ordering) both runs exit 0" || no "expected exit 0 on both runs ($rcH1/$rcH2)"
if [ "$outH1" = "$outH2" ]; then
  ok "stdout byte-identical across two runs (deterministic order)"
else
  no "stdout differs across runs (non-deterministic ordering)"
fi
# Sanity: all four valid rules are present in the deterministic output.
n_rules="$(printf '%s\n' "$outH1" | grep -cE '^- ')"
[ "$n_rules" -eq 4 ] && ok "(ordering) all 4 valid rules rendered" || no "(ordering) expected 4 rules, got $n_rules"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
