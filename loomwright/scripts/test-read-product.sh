#!/usr/bin/env bash
# test-read-product.sh — self-tests for read-product.sh, the fail-safe ADVISORY reader for the
# committed `.agent/product.json` product-context store.
#
# WRITE CONTAINMENT: every fixture is written into a `mktemp -d` scratch dir and the reader is pointed
# at it with `--store` / `--repo` (or the `PRODUCT_STORE` env override), so this test NEVER reads or
# writes the real repo's `.agent/`. It deliberately does NOT create `.agent/product.json` anywhere in
# this repo — the store is created per-project at runtime by the bootstrap, not by this reader and not
# by its tests. `--repo` also redirects the reader's best-effort `.supervisor/logs/memory.log` append
# into the scratch dir. Static-only: no Docker, no network, no `gh`.
# Exit 0 = all pass, 1 = any failure (auto-registered by ci.yml's `loomwright/scripts/test-*.sh` glob).
#
# Covers cases (a)–(k), mapped to the job's acceptance criteria:
#   (a) AC2  absent store              → EMPTY stdout, reason named on stderr, exit 0
#   (b) AC1  well-formed fixture       → TRACEABILITY: every emitted value is compared against the
#                                        value jq reads back from the FIXTURE (never against a string
#                                        copied out of the reader), and the emitted competitor COUNT
#                                        equals the fixture's — so the reader can neither invent nor
#                                        drop a record
#   (c) AC2  malformed store           → (c1) unparseable JSON, (c2) a root that is not a JSON object:
#                                        EMPTY stdout, reason on stderr, exit 0 in both
#   (d) AC2  jq unavailable            → EMPTY stdout, reason on stderr, exit 0 (PATH-stubbed; the
#                                        simulation is verified effective before it is trusted)
#   (e) AC3  last_fetched EXPLICIT NULL → renders "never fetched" — never a date, never "stale" —
#                                        while a dated sibling in the SAME fixture renders its date
#   (f) AC3  last_fetched KEY MISSING   → a SEPARATE case from (e), deliberately not collapsed: it must
#                                        NOT render "never fetched", must name the missing key on
#                                        stderr, and must still emit the rest of the store
#   (g) AC4  stance drives the derived stance_default_action → three fixtures (product / tool / no
#                                        stance key): product's action DIFFERS from tool's, and the
#                                        stance-less fixture emits `stance: unset` AND
#                                        `stance_default_action: unset` — substituting NEITHER default.
#                                        (g4) an out-of-enum stance also yields `unset` (never a guess)
#   (h)      determinism                → the same fixture run twice ⇒ byte-identical stdout
#   (i)      MUTATION CONTROL for (f)   → the same missing-key fixture is re-run against a COPY of the
#                                        reader whose `has("last_fetched")` presence guard is disabled
#                                        (exactly the `//`-default collapse this schema exists to
#                                        prevent). Under the mutant the missing key MUST render as
#                                        "never fetched" — if it did not, (f) would be passing for some
#                                        reason other than the presence check, i.e. vacuously
#   (j)      store override mechanism   → the `PRODUCT_STORE` env override resolves the same fixture as
#                                        `--store`, and a `--store` flag WINS over the env var
#   (k)      pure-read                  → the fixture's bytes are unchanged after a run, and the reader
#                                        creates no `.agent/` in the scratch repo

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
READER="$SCRIPT_DIR/read-product.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT" 2>/dev/null' EXIT
mktmp() { mktemp -d "$ROOT/d.XXXXXX"; }

# A scratch "repo" dir for the reader's --repo (keeps its memory.log append out of the real repo).
FAKE_REPO="$(mktmp)"

# write_fixture <path> <json> — fixture files live under $ROOT only.
write_fixture() { printf '%s' "$2" > "$1"; }

# run_reader <store-path> [reader-override] — stdout on stdout, stderr into the FIXED file $LAST_ERR.
# The path is a constant assigned OUTSIDE the function on purpose: every call site captures stdout with
# `$( ... )`, which runs the function in a SUBSHELL, so a path assigned inside would never be visible to
# the assertions that follow (an exported-status/variable-lost-across-subshell trap). The file itself is
# written by the redirect and does survive.
LAST_ERR="$ROOT/last-stderr.txt"
run_reader() {
  local store="$1" reader="${2:-$READER}"
  : > "$LAST_ERR"
  bash "$reader" --store "$store" --repo "$FAKE_REPO" 2>"$LAST_ERR"
}

if ! command -v jq >/dev/null 2>&1; then
  echo "test-read-product: jq absent on this host — read-product.sh no-ops (exit 0). Skipping data assertions."
  echo "RESULT: 0 passed, 0 failed (jq absent, vacuous)"
  exit 0
fi

BANNER="## Product context — advisory, subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)"

# The canonical well-formed fixture: one DATED competitor and one EXPLICIT-NULL competitor, so case
# (e) can assert both renderings from a single store. The third shape — a competitor with the
# `last_fetched` key ABSENT — is deliberately kept in its OWN fixture in case (f), because AC3 requires
# the missing-key and explicit-null cases to be asserted separately rather than collapsed.
FULL_JSON='{
  "domain": "B2B invoicing API for mid-market finance teams",
  "stance": "product",
  "audience": "finance ops leads (assumed — no user research yet)",
  "competitors": [
    {"name": "Acme Billing", "url": "https://acme.example", "last_fetched": "2026-08-01T00:00:00Z"},
    {"name": "Beta Invoice", "url": "https://beta.example", "last_fetched": null}
  ],
  "written_at": "2026-09-07T10:00:00Z",
  "head_sha": "b6f52a6f75c393b8a178c0645597d53e00765569"
}'

# ============================================================================
echo "== (a) AC2 absent store → empty stdout, reason on stderr, exit 0 =="
A_DIR="$(mktmp)"
outA="$(run_reader "$A_DIR/product.json")"; rcA=$?
[ "$rcA" -eq 0 ] && ok "(a) exits 0 with no store" || no "(a) expected exit 0, got $rcA"
[ -z "$outA" ] && ok "(a) emits NOTHING on stdout" || no "(a) expected empty stdout; got: $outA"
[ -s "$LAST_ERR" ] && ok "(a) names the reason on stderr" || no "(a) expected a stderr diagnostic, got none"
grep -qF "no product context store" "$LAST_ERR" \
  && ok "(a) the stderr diagnostic names the missing store" \
  || no "(a) stderr did not name the missing store: $(cat "$LAST_ERR")"

# ============================================================================
echo "== (b) AC1 well-formed fixture → every emitted value traces to a key in the FIXTURE =="
B_DIR="$(mktmp)"; FIX="$B_DIR/product.json"
write_fixture "$FIX" "$FULL_JSON"
outB="$(run_reader "$FIX")"; rcB=$?
[ "$rcB" -eq 0 ] && ok "(b) exits 0" || no "(b) expected exit 0, got $rcB"
# No `... | head -1 | grep -q` here: under `set -o pipefail` an early-closing consumer can make the
# whole pipeline report SIGPIPE (141) even on a match, so the first line is extracted and compared as
# a plain string instead.
first_line="$(printf '%s\n' "$outB" | sed -n '1p')"
[ "$first_line" = "$BANNER" ] \
  && ok "(b) first line is the subordination banner" \
  || no "(b) missing/incorrect banner; got: $first_line"

# Scalars: compare each emitted value against jq's read of the SAME key in the fixture.
for k in domain stance audience written_at head_sha; do
  emitted="$(printf '%s\n' "$outB" | sed -n "s/^- $k: //p")"
  expected="$(jq -r --arg k "$k" '.[$k]' "$FIX")"
  if [ -n "$emitted" ] && [ "$emitted" = "$expected" ]; then
    ok "(b) '$k' emits the fixture's value verbatim"
  else
    no "(b) '$k' not traceable to the fixture: emitted='$emitted' fixture='$expected'"
  fi
done

# Competitor COUNT: neither invented nor dropped.
n_fix="$(jq '.competitors | length' "$FIX")"
n_out="$(printf '%s\n' "$outB" | awk '/^  - name: /{n++} END{print n+0}')"
[ "$n_out" = "$n_fix" ] \
  && ok "(b) emits exactly the fixture's $n_fix competitor rows" \
  || no "(b) competitor row count $n_out != fixture's $n_fix"

# Per-competitor: each rendered cell traces to that entry's key in the fixture. `last_fetched` is
# expected per the CONTRACT (present+null ⇒ "never fetched"; key absent ⇒ "unset (key missing)"),
# derived here from the fixture — not copied out of the reader.
i=0
while [ "$i" -lt "$n_fix" ]; do
  row="$(printf '%s\n' "$outB" | awk -v want="$((i+1))" '/^  - name: /{c++; if (c==want) print}')"
  e_name="$(jq -r --argjson i "$i" '.competitors[$i].name' "$FIX")"
  e_url="$(jq -r --argjson i "$i" '.competitors[$i].url' "$FIX")"
  if jq -e --argjson i "$i" '.competitors[$i] | has("last_fetched")' "$FIX" >/dev/null 2>&1; then
    if jq -e --argjson i "$i" '.competitors[$i].last_fetched == null' "$FIX" >/dev/null 2>&1; then
      e_lf="never fetched"
    else
      e_lf="$(jq -r --argjson i "$i" '.competitors[$i].last_fetched' "$FIX")"
    fi
  else
    e_lf="unset (key missing)"
  fi
  want_row="  - name: $e_name | url: $e_url | last_fetched: $e_lf"
  [ "$row" = "$want_row" ] \
    && ok "(b) competitor[$i] row traces to the fixture" \
    || no "(b) competitor[$i] row mismatch: got '$row' want '$want_row'"
  i=$((i+1))
done

# ============================================================================
echo "== (c) AC2 malformed store → empty stdout, reason on stderr, exit 0 =="
C_DIR="$(mktmp)"
write_fixture "$C_DIR/bad.json" '{"domain": "unterminated'
outC1="$(run_reader "$C_DIR/bad.json")"; rcC1=$?
[ "$rcC1" -eq 0 ] && ok "(c1) unparseable JSON exits 0" || no "(c1) expected exit 0, got $rcC1"
[ -z "$outC1" ] && ok "(c1) unparseable JSON emits NOTHING on stdout" || no "(c1) expected empty stdout; got: $outC1"
[ -s "$LAST_ERR" ] && ok "(c1) unparseable JSON names the reason on stderr" || no "(c1) expected a stderr diagnostic"

write_fixture "$C_DIR/arr.json" '["not", "an", "object"]'
outC2="$(run_reader "$C_DIR/arr.json")"; rcC2=$?
[ "$rcC2" -eq 0 ] && ok "(c2) non-object root exits 0" || no "(c2) expected exit 0, got $rcC2"
[ -z "$outC2" ] && ok "(c2) non-object root emits NOTHING on stdout" || no "(c2) expected empty stdout; got: $outC2"
grep -qF "not a JSON object" "$LAST_ERR" \
  && ok "(c2) stderr names the non-object root" \
  || no "(c2) stderr did not name the non-object root: $(cat "$LAST_ERR")"

# ============================================================================
echo "== (d) AC2 jq unavailable → empty stdout, reason on stderr, exit 0 =="
D_DIR="$(mktmp)"; write_fixture "$D_DIR/product.json" "$FULL_JSON"
STUBBIN="$(mktmp)/bin"; mkdir -p "$STUBBIN"
for b in git date mkdir dirname rm cat sed grep env bash sh mktemp printf; do
  src="$(command -v "$b" 2>/dev/null)"
  [ -n "$src" ] && ln -sf "$src" "$STUBBIN/$b"
done
# Confirm the simulation actually hides jq before trusting the assertion. The probe runs in a FRESH
# `bash -c` rather than `PATH=... command -v jq` in this shell: bash caches resolved command paths in
# its hash table, and `command -v` consults that cache, so an in-shell probe reports the ALREADY-HASHED
# jq and the check passes while the simulation is doing nothing.
if PATH="$STUBBIN" bash -c 'command -v jq' >/dev/null 2>&1; then
  no "(d) jq-absent simulation failed — jq still resolvable on the stub PATH"
else
  ok "(d) jq-absent simulation effective — jq not resolvable on the stub PATH"
  errD="$(mktmp)/err"
  outD="$(PATH="$STUBBIN" bash "$READER" --store "$D_DIR/product.json" --repo "$FAKE_REPO" 2>"$errD")"; rcD=$?
  [ "$rcD" -eq 0 ] && ok "(d) exits 0 with jq unavailable" || no "(d) expected exit 0, got $rcD"
  [ -z "$outD" ] && ok "(d) emits NOTHING on stdout with jq unavailable" || no "(d) expected empty stdout; got: $outD"
  grep -qF "jq unavailable" "$errD" \
    && ok "(d) stderr names jq as the reason" \
    || no "(d) stderr did not name jq: $(cat "$errD")"
fi

# ============================================================================
echo "== (e) AC3 last_fetched EXPLICIT NULL → 'never fetched', never a date, never 'stale' =="
E_DIR="$(mktmp)"
write_fixture "$E_DIR/product.json" "$FULL_JSON"   # carries a dated AND a null entry
outE="$(run_reader "$E_DIR/product.json")"
null_row="$(printf '%s\n' "$outE" | awk '/^  - name: Beta Invoice /{print}')"
dated_row="$(printf '%s\n' "$outE" | awk '/^  - name: Acme Billing /{print}')"
case "$null_row" in
  *"last_fetched: never fetched") ok "(e) the explicit-null entry renders 'never fetched'" ;;
  *) no "(e) explicit-null entry rendered as: '$null_row'" ;;
esac
case "$null_row" in
  *20[0-9][0-9]-*) no "(e) explicit-null entry leaked a DATE: '$null_row'" ;;
  *) ok "(e) the explicit-null entry renders no date" ;;
esac
case "$null_row" in
  *[Ss]tale*) no "(e) explicit-null entry claimed staleness: '$null_row'" ;;
  *) ok "(e) the explicit-null entry never says 'stale' (unknown is not old)" ;;
esac
case "$dated_row" in
  *"last_fetched: 2026-08-01T00:00:00Z") ok "(e) the dated sibling still renders its own date" ;;
  *) no "(e) dated sibling rendered as: '$dated_row'" ;;
esac

# ============================================================================
echo "== (f) AC3 last_fetched KEY MISSING → a SEPARATE case; NOT 'never fetched' =="
F_DIR="$(mktmp)"; F_FIX="$F_DIR/product.json"
write_fixture "$F_FIX" '{
  "domain": "d", "stance": "tool", "audience": "a",
  "competitors": [ {"name": "Gamma Pay", "url": "https://gamma.example"} ],
  "written_at": "2026-09-07T10:00:00Z", "head_sha": "abc1234"
}'
outF="$(run_reader "$F_FIX")"; rcF=$?
miss_row="$(printf '%s\n' "$outF" | awk '/^  - name: Gamma Pay /{print}')"
[ "$rcF" -eq 0 ] && ok "(f) exits 0 on an incomplete competitor record" || no "(f) expected exit 0, got $rcF"
case "$miss_row" in
  *"never fetched"*) no "(f) a MISSING last_fetched key collapsed into 'never fetched': '$miss_row'" ;;
  *) ok "(f) a MISSING key does NOT render as 'never fetched'" ;;
esac
case "$miss_row" in
  *"last_fetched: unset (key missing)") ok "(f) a MISSING key renders as 'unset (key missing)'" ;;
  *) no "(f) missing-key entry rendered as: '$miss_row'" ;;
esac
grep -qF "missing the required \`last_fetched\` key" "$LAST_ERR" \
  && ok "(f) stderr names the missing required key" \
  || no "(f) stderr did not name the missing key: $(cat "$LAST_ERR")"
case "$outF" in
  *"- domain: d"*) ok "(f) the rest of the store is still emitted (demote-never-crash)" ;;
  *) no "(f) the incomplete record suppressed the rest of the store" ;;
esac

# ============================================================================
echo "== (g) AC4 stance drives the derived stance_default_action =="
G_DIR="$(mktmp)"
write_fixture "$G_DIR/product.json" '{"domain":"d","stance":"product","audience":"a","competitors":[],"written_at":"t","head_sha":"s"}'
write_fixture "$G_DIR/tool.json"    '{"domain":"d","stance":"tool","audience":"a","competitors":[],"written_at":"t","head_sha":"s"}'
write_fixture "$G_DIR/none.json"    '{"domain":"d","audience":"a","competitors":[],"written_at":"t","head_sha":"s"}'
write_fixture "$G_DIR/weird.json"   '{"domain":"d","stance":"platform","audience":"a","competitors":[],"written_at":"t","head_sha":"s"}'
act() { printf '%s\n' "$1" | sed -n 's/^- stance_default_action: //p'; }
stc() { printf '%s\n' "$1" | sed -n 's/^- stance: //p'; }

outG1="$(run_reader "$G_DIR/product.json")"; a1="$(act "$outG1")"
outG2="$(run_reader "$G_DIR/tool.json")";    a2="$(act "$outG2")"
outG3="$(run_reader "$G_DIR/none.json")";    a3="$(act "$outG3")"; s3="$(stc "$outG3")"
outG4="$(run_reader "$G_DIR/weird.json")";   a4="$(act "$outG4")"

[ -n "$a1" ] && ok "(g1) stance: product emits a stance_default_action ('$a1')" \
             || no "(g1) stance: product emitted no stance_default_action"
[ -n "$a2" ] && ok "(g2) stance: tool emits a stance_default_action ('$a2')" \
             || no "(g2) stance: tool emitted no stance_default_action"
[ -n "$a1" ] && [ -n "$a2" ] && [ "$a1" != "$a2" ] \
  && ok "(g3) product's action DIFFERS from tool's ('$a1' vs '$a2') — the mapping is keyed on data" \
  || no "(g3) product and tool produced the same stance_default_action ('$a1' vs '$a2')"
[ "$a1" != "unset" ] && [ "$a2" != "unset" ] \
  && ok "(g3) both enum values resolve to a real action" \
  || no "(g3) an enum stance resolved to 'unset' (a1='$a1' a2='$a2')"
[ "$s3" = "unset" ] && ok "(g4) a store with no stance key emits 'stance: unset'" \
                    || no "(g4) stance-less store emitted stance='$s3'"
[ "$a3" = "unset" ] \
  && ok "(g4) a store with no stance key emits 'stance_default_action: unset' — NEITHER default substituted" \
  || no "(g4) stance-less store substituted a default: '$a3'"
[ "$a4" = "unset" ] \
  && ok "(g5) an out-of-enum stance also yields 'unset' (never a guess)" \
  || no "(g5) out-of-enum stance produced '$a4'"

# ============================================================================
echo "== (h) determinism → same fixture twice ⇒ byte-identical stdout =="
H1="$(run_reader "$FIX")"
H2="$(run_reader "$FIX")"
[ "$H1" = "$H2" ] && ok "(h) two runs over the same fixture are byte-identical" \
                  || no "(h) output differs between two runs of the same fixture"

# ============================================================================
echo "== (i) MUTATION CONTROL for (f) — disable the has() presence guard =="
MUT="$(mktmp)/read-product-mutant.sh"
# Disable ONLY the last_fetched presence check: with the has() branch unreachable, a MISSING key falls
# through to the `== null` branch — precisely the `//`-default collapse the schema forbids.
sed 's/if (\$c | has("last_fetched") | not) then/if (false) then/' "$READER" > "$MUT"
if [ ! -s "$MUT" ] || cmp -s "$MUT" "$READER"; then
  no "(i) mutation control could not be applied (sed matched nothing?) — case (f) is UNPROVEN"
else
  ok "(i) mutant differs from the original and is non-empty"
  mut_out="$(run_reader "$F_FIX" "$MUT")"; mut_rc=$?
  mut_row="$(printf '%s\n' "$mut_out" | awk '/^  - name: Gamma Pay /{print}')"
  [ "$mut_rc" -eq 0 ] && ok "(i) the mutant still runs (the mutation disabled only the presence guard)" \
                      || no "(i) the mutant is broken beyond the guard (rc=$mut_rc) — the control is meaningless"
  case "$mut_row" in
    *"never fetched"*)
      ok "(i) CONTROL HELD: with the presence guard disabled the MISSING key renders 'never fetched' ⇒ (f) is NOT vacuous" ;;
    *)
      no "(i) CONTROL BROKEN: the mutant did not collapse the missing key ('$mut_row') — (f) may pass for another reason" ;;
  esac
fi

# ============================================================================
echo "== (j) store override mechanism → PRODUCT_STORE env, and --store wins over it =="
J_ERR="$(mktmp)/err"
outJ1="$(PRODUCT_STORE="$FIX" PRODUCT_REPO_DIR="$FAKE_REPO" bash "$READER" 2>"$J_ERR")"
[ "$outJ1" = "$H1" ] && ok "(j) PRODUCT_STORE resolves the same store as --store" \
                     || no "(j) PRODUCT_STORE produced different output than --store"
outJ2="$(PRODUCT_STORE="$C_DIR/bad.json" bash "$READER" --store "$FIX" --repo "$FAKE_REPO" 2>/dev/null)"
[ "$outJ2" = "$H1" ] && ok "(j) --store WINS over the PRODUCT_STORE env var (documented precedence)" \
                     || no "(j) --store did not take precedence over PRODUCT_STORE"

# ============================================================================
echo "== (k) pure-read → the store is never modified and no .agent/ is created =="
before="$(cksum < "$FIX")"
run_reader "$FIX" >/dev/null
after="$(cksum < "$FIX")"
[ "$before" = "$after" ] && ok "(k) the store's bytes are unchanged after a run" \
                         || no "(k) the reader MODIFIED the store"
[ ! -e "$FAKE_REPO/.agent" ] && ok "(k) the reader created no .agent/ in the scratch repo" \
                             || no "(k) the reader created $FAKE_REPO/.agent — it must never write the store"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
