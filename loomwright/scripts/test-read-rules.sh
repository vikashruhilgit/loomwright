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

# (c2) valid JSON but NOT an array (a bare object / scalar) → skipped with diagnostic, NOT crash; a
# valid-array sibling still emits. The schema requires each *.json be a JSON ARRAY ("never a bare
# object"); this exercises the reader's `if type=="array" … else empty` non-array branch, distinct
# from (c)'s truly-malformed-JSON case.
RC2="$(new_repo)"
seed_rules_file "$RC2" "good.json" '[
  {"id":"c2-good","category":"safety","statement":"Array sibling survives the non-array file","enforcement":"advisory","check":null,"provenance":{"source":"test"}}
]'
seed_rules_file "$RC2" "object.json" '{"id":"not-an-array","category":"safety","statement":"bare object, not an array","enforcement":"advisory","check":null,"provenance":{"source":"test"}}'
seed_rules_file "$RC2" "scalar.json" '42'
outC2="$(run_reader "$RC2")"; rcC2=$?
[ "$rcC2" -eq 0 ] && ok "(c2 valid-JSON non-array) exits 0" || no "expected exit 0, got $rcC2"
if echo "$outC2" | grep -qF -- "- Array sibling survives the non-array file" \
   && ! echo "$outC2" | grep -qF "bare object, not an array"; then
  ok "(c2) non-array JSON file SKIPPED, array sibling still emitted"
else
  no "(c2) non-array JSON file must be skipped while the array sibling emits"
fi

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

# (g6) bad-category: non-string `category` → SKIPPED; valid sibling survives. (validation branch)
RG6="$(new_repo)"
seed_rules_file "$RG6" "g6.json" '[
  {"id":"g6-bad","category":123,"statement":"non-string category","enforcement":"advisory","check":null,"provenance":{"source":"test"}},
  {"id":"g6-good","category":"safety","statement":"Valid sibling g6 survives","enforcement":"advisory","check":null,"provenance":{"source":"test"}}
]'
outG6="$(run_reader "$RG6")"; rcG6=$?
[ "$rcG6" -eq 0 ] && ok "(g6 bad category) exits 0" || no "expected exit 0, got $rcG6"
echo "$outG6" | grep -qF -- "- Valid sibling g6 survives" && ! echo "$outG6" | grep -qF "non-string category" \
  && ok "(g6) non-string-category object SKIPPED, valid sibling emitted" \
  || no "(g6) bad-category skip incorrect"

# (g7) bad-provenance: non-object `provenance` → SKIPPED; valid sibling survives. (validation branch)
RG7="$(new_repo)"
seed_rules_file "$RG7" "g7.json" '[
  {"id":"g7-bad","category":"safety","statement":"string provenance not object","enforcement":"advisory","check":null,"provenance":"oops"},
  {"id":"g7-good","category":"safety","statement":"Valid sibling g7 survives","enforcement":"advisory","check":null,"provenance":{"source":"test"}}
]'
outG7="$(run_reader "$RG7")"; rcG7=$?
[ "$rcG7" -eq 0 ] && ok "(g7 bad provenance) exits 0" || no "expected exit 0, got $rcG7"
echo "$outG7" | grep -qF -- "- Valid sibling g7 survives" && ! echo "$outG7" | grep -qF "string provenance not object" \
  && ok "(g7) non-object-provenance object SKIPPED, valid sibling emitted" \
  || no "(g7) bad-provenance skip incorrect"

# (g8) present-but-non-string `check` (e.g. a number) → SKIPPED via the bad-check elif. Distinct from
# g4 (missing key) and g5 (explicit null): here the key is present but neither string nor null.
RG8="$(new_repo)"
seed_rules_file "$RG8" "g8.json" '[
  {"id":"g8-bad","category":"safety","statement":"numeric check is invalid","enforcement":"advisory","check":123,"provenance":{"source":"test"}},
  {"id":"g8-good","category":"safety","statement":"Valid sibling g8 survives","enforcement":"advisory","check":null,"provenance":{"source":"test"}}
]'
outG8="$(run_reader "$RG8")"; rcG8=$?
[ "$rcG8" -eq 0 ] && ok "(g8 non-string check) exits 0" || no "expected exit 0, got $rcG8"
echo "$outG8" | grep -qF -- "- Valid sibling g8 survives" && ! echo "$outG8" | grep -qF "numeric check is invalid" \
  && ok "(g8) non-string-check object SKIPPED, valid sibling emitted" \
  || no "(g8) bad-check (non-string) skip incorrect"

# (g9) non-object array element (null / scalar inside the array) → SKIPPED via the not-an-object
# branch; a valid object sibling in the same array still emits.
RG9="$(new_repo)"
seed_rules_file "$RG9" "g9.json" '[
  null,
  42,
  {"id":"g9-good","category":"safety","statement":"Valid object among non-object elements","enforcement":"advisory","check":null,"provenance":{"source":"test"}}
]'
outG9="$(run_reader "$RG9")"; rcG9=$?
[ "$rcG9" -eq 0 ] && ok "(g9 non-object element) exits 0" || no "expected exit 0, got $rcG9"
echo "$outG9" | grep -qF -- "- Valid object among non-object elements" \
  && ok "(g9) non-object array elements SKIPPED, valid object sibling emitted" \
  || no "(g9) not-an-object handling incorrect"

# (g10) CROSS-FILE first-seen-id dedup: the SAME id appears in two files; LC_ALL=C path-sort means the
# alphabetically-earlier filename wins. "aaa.json" sorts before "zzz.json", so aaa's statement emits
# and zzz's same-id statement is dropped — proving the dedup spans files, not just within one array.
RG10="$(new_repo)"
seed_rules_file "$RG10" "zzz.json" '[
  {"id":"crossdup","category":"safety","statement":"From zzz — should be DROPPED (later in path sort)","enforcement":"advisory","check":null,"provenance":{"source":"test"}}
]'
seed_rules_file "$RG10" "aaa.json" '[
  {"id":"crossdup","category":"safety","statement":"From aaa — first-seen across files WINS","enforcement":"advisory","check":null,"provenance":{"source":"test"}}
]'
outG10="$(run_reader "$RG10")"; rcG10=$?
[ "$rcG10" -eq 0 ] && ok "(g10 cross-file dup) exits 0" || no "expected exit 0, got $rcG10"
if echo "$outG10" | grep -qF -- "- From aaa — first-seen across files WINS" \
   && ! echo "$outG10" | grep -qF "From zzz"; then
  ok "(g10) cross-file duplicate id: LC_ALL=C path-sort first-file wins, later file's dup SKIPPED"
else
  no "(g10) cross-file dedup incorrect — earlier-path file must win"
fi

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
# Assert the EXPECTED sort_by([category,id]) order, not just determinism: categories access(alpha,beta),
# middleware(mid), zoning(zeta) → alpha, beta, mid, zeta. Extract the statement-bearing rule lines
# (the "- <statement>" header line of each rule; the [MUST] flag prefixes alpha) in order.
order="$(printf '%s\n' "$outH1" | grep -E '^- ' | sed -E 's/^- (\[MUST\] )?//' | tr '\n' '|')"
[ "$order" = "Alpha rule|Beta rule|Mid rule|Zeta rule|" ] \
  && ok "(ordering) rules emitted in sort_by([category,id]) order (alpha,beta,mid,zeta)" \
  || no "(ordering) wrong order: got [$order], expected [Alpha rule|Beta rule|Mid rule|Zeta rule|]"

# ============================================================================
echo "== (i) SUPERSESSION (curation/anti-rot ST-1) — single-hop, non-transitive, demote-never-crash =="

# (i1) a live rule's `supersedes` hides the rule it names (acceptance criterion #1, mechanical test).
RI1="$(new_repo)"
seed_rules_file "$RI1" "core.json" '[
  {"id":"i1-new","category":"safety","statement":"New replaces old","enforcement":"advisory","check":null,"provenance":{"source":"test"},"supersedes":"i1-old"},
  {"id":"i1-old","category":"safety","statement":"Old rule hidden","enforcement":"advisory","check":null,"provenance":{"source":"test"}}
]'
outI1="$(run_reader "$RI1")"; rcI1=$?
[ "$rcI1" -eq 0 ] && ok "(i1 supersession) exits 0" || no "(i1) expected exit 0, got $rcI1"
if echo "$outI1" | grep -qF -- "- New replaces old" && ! echo "$outI1" | grep -qF "Old rule hidden"; then
  ok "(i1) superseding rule visible, superseded target HIDDEN from reader output"
else
  no "(i1) supersession not honored: $outI1"
fi

# (i2) malformed `supersedes` shapes (non-string / wrong type / empty) are IGNORED — the carrying
# entry is still emitted, and (since the field is invalid) nothing is hidden by it.
RI2="$(new_repo)"
seed_rules_file "$RI2" "core.json" '[
  {"id":"i2-numeric","category":"safety","statement":"Numeric supersedes is ignored","enforcement":"advisory","check":null,"provenance":{"source":"test"},"supersedes":42},
  {"id":"i2-object","category":"safety","statement":"Object supersedes is ignored","enforcement":"advisory","check":null,"provenance":{"source":"test"},"supersedes":{"x":1}},
  {"id":"i2-empty","category":"safety","statement":"Empty-string supersedes is ignored","enforcement":"advisory","check":null,"provenance":{"source":"test"},"supersedes":""},
  {"id":"i2-null","category":"safety","statement":"Explicit null supersedes is ignored","enforcement":"advisory","check":null,"provenance":{"source":"test"},"supersedes":null}
]'
outI2="$(run_reader "$RI2")"; rcI2=$?
[ "$rcI2" -eq 0 ] && ok "(i2 malformed supersedes) exits 0" || no "(i2) expected exit 0, got $rcI2"
if echo "$outI2" | grep -qF -- "- Numeric supersedes is ignored" \
   && echo "$outI2" | grep -qF -- "- Object supersedes is ignored" \
   && echo "$outI2" | grep -qF -- "- Empty-string supersedes is ignored" \
   && echo "$outI2" | grep -qF -- "- Explicit null supersedes is ignored"; then
  ok "(i2) malformed supersedes (numeric/object/empty-string/null) all IGNORED — every carrier still emitted"
else
  no "(i2) a malformed-supersedes carrier was wrongly hidden/dropped: $outI2"
fi

# (i3) self-referential `supersedes` (an entry naming its own id) is IGNORED — still emitted.
RI3="$(new_repo)"
seed_rules_file "$RI3" "core.json" '[
  {"id":"i3-self","category":"safety","statement":"Self-referential supersedes is ignored","enforcement":"advisory","check":null,"provenance":{"source":"test"},"supersedes":"i3-self"}
]'
outI3="$(run_reader "$RI3")"; rcI3=$?
[ "$rcI3" -eq 0 ] && ok "(i3 self-referential) exits 0" || no "(i3) expected exit 0, got $rcI3"
echo "$outI3" | grep -qF -- "- Self-referential supersedes is ignored" \
  && ok "(i3) self-referential supersedes IGNORED — entry still emitted, does not hide itself" \
  || no "(i3) self-referential supersedes wrongly hid its own entry: $outI3"

# (i4) dangling `supersedes` (names an id absent from the store entirely) is IGNORED — still emitted.
RI4="$(new_repo)"
seed_rules_file "$RI4" "core.json" '[
  {"id":"i4-dangling","category":"safety","statement":"Dangling supersedes is ignored","enforcement":"advisory","check":null,"provenance":{"source":"test"},"supersedes":"no-such-rule-id-anywhere"}
]'
outI4="$(run_reader "$RI4")"; rcI4=$?
[ "$rcI4" -eq 0 ] && ok "(i4 dangling target) exits 0" || no "(i4) expected exit 0, got $rcI4"
echo "$outI4" | grep -qF -- "- Dangling supersedes is ignored" \
  && ok "(i4) dangling supersedes IGNORED — carrying entry still emitted" \
  || no "(i4) dangling supersedes wrongly suppressed its carrier: $outI4"

# (i4b) dangling supersedes where the "target" is a REAL id but only inside a SKIPped/invalid object
# (never validation-survived) — still counts as dangling (target never entered the OK set), so the
# carrier is unaffected and still emitted; the invalid sibling stays dropped for its own reasons.
RI4B="$(new_repo)"
seed_rules_file "$RI4B" "core.json" '[
  {"id":"i4b-carrier","category":"safety","statement":"Points at an invalid, never-OK sibling","enforcement":"advisory","check":null,"provenance":{"source":"test"},"supersedes":"i4b-invalid"},
  {"id":"i4b-invalid","category":"safety","enforcement":"advisory","check":null,"provenance":{"source":"test"}}
]'
outI4B="$(run_reader "$RI4B")"; rcI4B=$?
[ "$rcI4B" -eq 0 ] && ok "(i4b dangling-via-invalid-target) exits 0" || no "(i4b) expected exit 0, got $rcI4B"
echo "$outI4B" | grep -qF -- "- Points at an invalid, never-OK sibling" \
  && ok "(i4b) supersedes targeting a never-OK (SKIPped) sibling is dangling — carrier still emitted" \
  || no "(i4b) carrier wrongly suppressed when its target never validation-survived: $outI4B"

# (i5) mutually-cyclic supersedes (A supersedes B AND B supersedes A) is IGNORED on BOTH sides — BOTH
# entries stay visible. Proves single-hop non-transitivity: hiding both halves of a 2-cycle would
# silently drop two rules from one misconfiguration, contradicting the fail-safe "read it anyway,
# never hide it" default (the pinned contract explicitly lists "cyclic" alongside malformed/self-ref/
# dangling as an IGNORED shape).
RI5="$(new_repo)"
seed_rules_file "$RI5" "core.json" '[
  {"id":"i5-a","category":"safety","statement":"Cycle member A stays visible","enforcement":"advisory","check":null,"provenance":{"source":"test"},"supersedes":"i5-b"},
  {"id":"i5-b","category":"safety","statement":"Cycle member B stays visible","enforcement":"advisory","check":null,"provenance":{"source":"test"},"supersedes":"i5-a"}
]'
outI5="$(run_reader "$RI5")"; rcI5=$?
[ "$rcI5" -eq 0 ] && ok "(i5 mutual cycle) exits 0" || no "(i5) expected exit 0, got $rcI5"
if echo "$outI5" | grep -qF -- "- Cycle member A stays visible" \
   && echo "$outI5" | grep -qF -- "- Cycle member B stays visible"; then
  ok "(i5) mutually-cyclic supersedes IGNORED on both sides — BOTH entries remain visible (single-hop, non-transitive)"
else
  no "(i5) a mutual-cycle member was wrongly hidden: $outI5"
fi

# (i6) non-cyclic one-way chain (A supersedes B, and B — independently — supersedes C) hides BOTH B
# and C: each live rule's own supersedes is applied independently (no transitive "chase" needed for
# this to happen — it falls out of evaluating every live rule's own edge once, not from A reaching
# through B to C).
RI6="$(new_repo)"
seed_rules_file "$RI6" "core.json" '[
  {"id":"i6-a","category":"safety","statement":"Chain head A stays visible","enforcement":"advisory","check":null,"provenance":{"source":"test"},"supersedes":"i6-b"},
  {"id":"i6-b","category":"safety","statement":"Chain middle B is hidden by A","enforcement":"advisory","check":null,"provenance":{"source":"test"},"supersedes":"i6-c"},
  {"id":"i6-c","category":"safety","statement":"Chain tail C is hidden by B","enforcement":"advisory","check":null,"provenance":{"source":"test"}}
]'
outI6="$(run_reader "$RI6")"; rcI6=$?
[ "$rcI6" -eq 0 ] && ok "(i6 one-way chain) exits 0" || no "(i6) expected exit 0, got $rcI6"
if echo "$outI6" | grep -qF -- "- Chain head A stays visible" \
   && ! echo "$outI6" | grep -qF "Chain middle B is hidden by A" \
   && ! echo "$outI6" | grep -qF "Chain tail C is hidden by B"; then
  ok "(i6) chain head A visible; B (hidden by A) and C (hidden by B) both absent"
else
  no "(i6) one-way chain hiding incorrect: $outI6"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
