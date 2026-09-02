#!/usr/bin/env bash
# test-gen-color-legend.sh — STATIC, fixture-driven self-tests for gen-color-legend.sh and for
# its wiring into scripts/check-doc-currency.sh.
#
# STATIC ONLY: no network, no Docker, no GitHub — it runs on the plugin's Ubuntu CI like every
# other test-*.sh (auto-registered by ci.yml's `loomwright/scripts/test-*.sh` glob).
#
# Exit 0 = all pass, 1 = any assertion failed, 2 = FIXTURE SETUP is broken.
# 1 and 2 are deliberately distinct: 1 means the assertions ran and the script under test
# misbehaved; 2 means a fixture could not be BUILT as specified, so the assertions after it
# would be testing something other than what they name.
#
# Covers (each = an acceptance criterion):
#   (a) 14 rows against the REAL agents directory, and every row's hex byte-matches that
#       agent's frontmatter `color:` — asserted PER AGENT, never as a bulk count
#   (b) DELETING a `color:` line drops that row and makes `--check` FAIL; ADDING a 15th agent
#       makes it FAIL too — the drift the hand-maintained table could not notice
#   (c) a hex that is NOT a CSS named colour renders the em-dash fallback, never a guess. The 14
#       live hexes are all CSS names, so this branch is unreachable in production and would
#       otherwise ship untested
#   (d) a VALID CSS name from OUTSIDE the 14 in use (`#FA8072` -> `Salmon`) still resolves.
#       Paired with (c) this pins both branches: without it, a 14-entry subset implementation
#       passes (c) trivially by returning the em-dash for everything it does not know
#   (e) the marker pair is what the writer keys off — a doc without it gets
#       `LEGEND MARKERS MISSING` and is NOT rewritten (no guessing where the table goes), and
#       `--write` is idempotent (a second run is a byte no-op)
#   (f) the real committed ARCHITECTURE_CONTRACTS.md currently passes `--check`
#   (g) THE CALLER MUTATION CONTROL (AC 7) — see the long comment at group (g). This is the one
#       that proves the wired check EXECUTES rather than merely existing.
#
# NO `producer | grep -q` PIPELINES. Under `set -o pipefail`, `grep -q` exits at the first match
# and SIGPIPEs the producer, so the PIPELINE status becomes 141 even though grep matched. Every
# text assertion below captures stdout into a variable first and matches it with a here-string.

set -uo pipefail
export LC_ALL=C

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
GEN="$script_dir/gen-color-legend.sh"
DOC_CURRENCY="$repo_root/scripts/check-doc-currency.sh"
REAL_DOC="$repo_root/loomwright/docs/ARCHITECTURE_CONTRACTS.md"
REAL_AGENTS="$repo_root/loomwright/agents"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
no()  { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; return 0; }
setup_fail() { printf '  SETUP BROKEN: %s\n' "$1" >&2; exit 2; }
has()  { case "$1" in *"$2"*) return 0 ;; esac; return 1; }

TMPROOT="$(mktemp -d)" || setup_fail "mktemp -d failed"
trap 'rm -rf "$TMPROOT"' EXIT

[ -f "$GEN" ] || setup_fail "gen-color-legend.sh not found at $GEN"
[ -f "$DOC_CURRENCY" ] || setup_fail "check-doc-currency.sh not found at $DOC_CURRENCY"

# mkagent <dir> <file> <name> <color-or-OMIT>
mkagent() {
  local dir="$1" file="$2" name="$3" color="$4"
  mkdir -p "$dir"
  {
    echo '---'
    echo "name: loomwright:$name"
    echo "description: fixture agent"
    [ "$color" = "OMIT" ] || echo "color: \"$color\""
    echo '---'
    echo
    echo "# fixture body — a decoy \`color: \"#000000\"\` here must NOT be read as frontmatter."
  } > "$dir/$file" || setup_fail "could not write fixture agent $dir/$file"
}

echo "== (a) the real agents directory =="

out="$(bash "$GEN" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then
  no "(a1) emitting against the real agents dir exits 0" "rc=$rc: $out"
else
  ok "(a1) emitting against the real agents dir exits 0"
fi

rows="$(printf '%s\n' "$out" | grep -c '^| .* | .* | `#' || true)"
agents_with_color=0
for f in "$REAL_AGENTS"/*.md; do
  [ -f "$f" ] || continue
  c="$(awk '/^---$/{n++; next} n==1 && /^color:/ {sub(/^color:[[:space:]]*/,""); print; exit}' "$f")"
  [ -n "$c" ] && agents_with_color=$((agents_with_color+1))
done
[ "$agents_with_color" -gt 0 ] || setup_fail "no agent frontmatter declares a color: — fixture-free assertions below would be vacuous"
if [ "$rows" = "$agents_with_color" ] && [ "$rows" = "14" ]; then
  ok "(a2) the generated legend has one row per colour-declaring agent, and that is 14"
else
  no "(a2) the generated legend has one row per colour-declaring agent, and that is 14" \
     "rows=$rows agents_with_color=$agents_with_color (AC 6 pins 14)"
fi

# Per-agent hex parity — asserted one agent at a time, never as a bulk claim.
mismatch=""
for f in "$REAL_AGENTS"/*.md; do
  [ -f "$f" ] || continue
  n="$(awk '/^---$/{n++; next} n==1 && /^name:/ {sub(/^name:[[:space:]]*/,""); print; exit}' "$f")"
  c="$(awk '/^---$/{n++; next} n==1 && /^color:/ {sub(/^color:[[:space:]]*/,""); print; exit}' "$f")"
  [ -n "$c" ] || continue
  c="${c%\"}"; c="${c#\"}"
  n="${n#loomwright:}"
  has "$out" "| $n |" || { mismatch="$mismatch $n(no-row)"; continue; }
  row="$(printf '%s\n' "$out" | grep -F "| $n |" | head -1)"
  has "$row" "\`$c\`" || mismatch="$mismatch $n(hex)"
done
if [ -z "$mismatch" ]; then
  ok "(a3) every row's hex byte-matches that agent's frontmatter color:"
else
  no "(a3) every row's hex byte-matches that agent's frontmatter color:" "offenders:$mismatch"
fi

echo "== (b) drift detection =="

# A fixture doc whose block is CORRECT for the fixture agents, so any later mutation of the
# agents is the only thing that can make --check fail.
FB="$TMPROOT/b"; mkdir -p "$FB/agents" "$FB/docs"
mkagent "$FB/agents" "alpha.md" "alpha" "#FFD700"
mkagent "$FB/agents" "beta.md"  "beta"  "#1E90FF"
{ echo "# doc"; echo; bash "$GEN" --agents-dir "$FB/agents"; echo; } > "$FB/docs/D.md" \
  || setup_fail "could not seed the (b) fixture doc"
base="$(bash "$GEN" --agents-dir "$FB/agents" --doc "$FB/docs/D.md" --check 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || setup_fail "the (b) baseline fixture does not pass --check (rc=$rc): $base"

# b1 — delete a color: line
cp "$FB/agents/beta.md" "$FB/beta.bak" || setup_fail "could not stash beta.md"
grep -v '^color:' "$FB/beta.bak" > "$FB/agents/beta.md" || setup_fail "could not strip beta's color:"
out="$(bash "$GEN" --agents-dir "$FB/agents" --doc "$FB/docs/D.md" --check 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && has "$out" "LEGEND DRIFT"; then
  ok "(b1) deleting a color: line FAILS --check with the LEGEND DRIFT diagnostic"
else
  no "(b1) deleting a color: line FAILS --check with the LEGEND DRIFT diagnostic" "rc=$rc: $out"
fi
cp "$FB/beta.bak" "$FB/agents/beta.md" || setup_fail "could not restore beta.md"

# b2 — add a third agent (the "15th agent" case, scaled to the fixture)
mkagent "$FB/agents" "gamma.md" "gamma" "#32CD32"
out="$(bash "$GEN" --agents-dir "$FB/agents" --doc "$FB/docs/D.md" --check 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && has "$out" "LEGEND DRIFT"; then
  ok "(b2) adding an agent FAILS --check with the LEGEND DRIFT diagnostic"
else
  no "(b2) adding an agent FAILS --check with the LEGEND DRIFT diagnostic" "rc=$rc: $out"
fi
rm -f "$FB/agents/gamma.md"
out="$(bash "$GEN" --agents-dir "$FB/agents" --doc "$FB/docs/D.md" --check 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
  ok "(b3) control — with the mutations reverted, the same fixture passes --check again"
else
  no "(b3) control — with the mutations reverted, the same fixture passes --check again" "rc=$rc: $out"
fi

echo "== (c)/(d) the colour lookup is the published standard, not a subset =="

FC="$TMPROOT/c"; mkdir -p "$FC/agents"
# #123456 is not a CSS named colour; #FA8072 is Salmon — a CSS name that NO live agent uses.
mkagent "$FC/agents" "nocss.md"  "nocss"  "#123456"
mkagent "$FC/agents" "salmon.md" "salmon" "#FA8072"
out="$(bash "$GEN" --agents-dir "$FC/agents" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || setup_fail "the (c)/(d) fixture did not generate (rc=$rc): $out"

row="$(printf '%s\n' "$out" | grep -F '| nocss |' | head -1)"
if has "$row" '| nocss | — | `#123456` |'; then
  ok "(c) a hex with no CSS name renders the em-dash fallback rather than a guess"
else
  no "(c) a hex with no CSS name renders the em-dash fallback rather than a guess" "row=$row"
fi

row="$(printf '%s\n' "$out" | grep -F '| salmon |' | head -1)"
if has "$row" '| salmon | Salmon | `#FA8072` |'; then
  ok "(d) a CSS name from OUTSIDE the 14 in use (#FA8072) resolves to Salmon — the lookup is the published standard"
else
  no "(d) a CSS name from OUTSIDE the 14 in use (#FA8072) resolves to Salmon — the lookup is the published standard" \
     "row=$row — an em-dash here means the table is a subset keyed to today's agent set"
fi

# The two assertions above are only a PAIR if the fallback and the hit are distinguishable.
if has "$out" '| nocss | — |' && has "$out" '| salmon | Salmon |'; then
  ok "(d2) both branches are exercised in ONE generation — the fallback cannot be masking a subset"
else
  no "(d2) both branches are exercised in ONE generation — the fallback cannot be masking a subset" "$out"
fi

echo "== (e) markers, refusal, and write idempotency =="

FE="$TMPROOT/e"; mkdir -p "$FE/agents" "$FE/docs"
mkagent "$FE/agents" "one.md" "one" "#FF6347"
printf '# doc\n\n## Color Legend (Status Line)\n\nno markers here\n' > "$FE/docs/D.md" \
  || setup_fail "could not seed the (e) marker-less doc"
before="$(cat "$FE/docs/D.md")"
out="$(bash "$GEN" --agents-dir "$FE/agents" --doc "$FE/docs/D.md" --write 2>&1)"; rc=$?
after="$(cat "$FE/docs/D.md")"
if [ "$rc" -ne 0 ] && has "$out" "LEGEND MARKERS MISSING" && [ "$before" = "$after" ]; then
  ok "(e1) --write REFUSES a doc with no marker pair, with the specific diagnostic, and leaves it byte-identical"
else
  no "(e1) --write REFUSES a doc with no marker pair, with the specific diagnostic, and leaves it byte-identical" \
     "rc=$rc changed=$([ "$before" = "$after" ] && echo no || echo YES): $out"
fi

out="$(bash "$GEN" --agents-dir "$FE/agents" --doc "$FE/docs/D.md" --check 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && has "$out" "LEGEND MARKERS MISSING"; then
  ok "(e2) --check on a marker-less doc FAILS with LEGEND MARKERS MISSING (never a silent pass)"
else
  no "(e2) --check on a marker-less doc FAILS with LEGEND MARKERS MISSING (never a silent pass)" "rc=$rc: $out"
fi

printf '# doc\n\n<!-- loomwright:color-legend BEGIN (generated by gen-color-legend.sh) -->\nSTALE\n<!-- loomwright:color-legend END -->\n\ntail line\n' > "$FE/docs/M.md" \
  || setup_fail "could not seed the (e) marked doc"
bash "$GEN" --agents-dir "$FE/agents" --doc "$FE/docs/M.md" --write >/dev/null 2>&1 \
  || setup_fail "the first --write on the marked fixture failed"
first="$(cat "$FE/docs/M.md")"
bash "$GEN" --agents-dir "$FE/agents" --doc "$FE/docs/M.md" --write >/dev/null 2>&1
second="$(cat "$FE/docs/M.md")"
if [ "$first" = "$second" ]; then
  ok "(e3) --write is idempotent — a second run is a byte no-op"
else
  no "(e3) --write is idempotent — a second run is a byte no-op" "the doc changed on the second write"
fi
if has "$first" "tail line" && ! has "$first" "STALE"; then
  ok "(e4) --write replaces only the marked block — the stale body is gone and text after END survives"
else
  no "(e4) --write replaces only the marked block — the stale body is gone and text after END survives" "$first"
fi

echo "== (f) the committed document =="

out="$(bash "$GEN" --check 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
  ok "(f) the committed ARCHITECTURE_CONTRACTS.md passes --check"
else
  no "(f) the committed ARCHITECTURE_CONTRACTS.md passes --check" "rc=$rc: $out"
fi
doc_txt="$(cat "$REAL_DOC" 2>/dev/null)"
if has "$doc_txt" '<!-- loomwright:color-legend BEGIN (generated by gen-color-legend.sh) -->'; then
  ok "(f2) the committed document carries the BEGIN sentinel verbatim"
else
  no "(f2) the committed document carries the BEGIN sentinel verbatim"
fi

echo "== (g) CALLER mutation control — does the wired check actually EXECUTE? =="

# WHY THIS IS A CALLER MUTATION, NOT A GENERATOR ONE.
# Groups (a)-(f) prove gen-color-legend.sh --check WORKS. They prove nothing about whether
# scripts/check-doc-currency.sh ever RUNS it — a reachable-but-uncalled check is exactly the
# "guard that cannot fire" class this repo keeps rediscovering. So the mutation is applied to
# the CALLER, across trees: a verbatim copy of check-doc-currency.sh with the single
# `run_legend_check || fail=1` line deleted must WRONGLY PASS on a fixture where legend and
# frontmatter genuinely disagree, while the unmutated copy FAILS on the identical fixture.
#
# THE CONTROL IS GATED SO IT CANNOT BE VACUOUS. A mutant that is empty, identical to the
# original, or syntactically broken would "prove" the point by accident — and a non-zero exit
# alone is no evidence either, because a syntax error also exits non-zero. So: the mutant must
# differ from the original, be non-empty, pass `bash -n`, AND still reach the end of the gate
# (asserted by its own `✓ doc-currency` line). And the FAILING side must emit the SPECIFIC
# `LEGEND DRIFT` diagnostic, not merely rc!=0.

FG="$TMPROOT/g"
mkdir -p "$FG/scripts" "$FG/loomwright/scripts" "$FG/loomwright/agents" "$FG/loomwright/docs" \
         "$FG/loomwright/.claude-plugin" "$FG/loomwright/hooks" "$FG/loomwright/commands" "$FG/loomwright/skills" \
  || setup_fail "could not build the (g) fixture tree"
cp "$DOC_CURRENCY" "$FG/scripts/check-doc-currency.sh" || setup_fail "could not copy check-doc-currency.sh"
cp "$GEN" "$FG/loomwright/scripts/gen-color-legend.sh" || setup_fail "could not copy gen-color-legend.sh"
printf '{"version":"9.9.9"}\n' > "$FG/loomwright/.claude-plugin/plugin.json" || setup_fail "could not seed plugin.json"
printf '{"hooks":{}}\n' > "$FG/loomwright/hooks/hooks.json" || setup_fail "could not seed hooks.json"
mkagent "$FG/loomwright/agents" "one.md" "one" "#FFD700"
mkagent "$FG/loomwright/agents" "two.md" "two" "#DC143C"

# The fixture doc's legend GENUINELY disagrees with the fixture frontmatter: `two` is missing
# and `one`'s hex is wrong. This is real drift, not a formatting nit.
cat > "$FG/loomwright/docs/ARCHITECTURE_CONTRACTS.md" <<'DOCEOF'
# Architecture Contracts (fixture)

## Color Legend (Status Line)

<!-- loomwright:color-legend BEGIN (generated by gen-color-legend.sh) -->
| Agent | Color | Hex |
|-------|-------|-----|
| one | Crimson | `#DC143C` |
<!-- loomwright:color-legend END -->
DOCEOF
[ -s "$FG/loomwright/docs/ARCHITECTURE_CONTRACTS.md" ] || setup_fail "could not seed the drifted fixture doc"

# The drift must be REAL — prove it independently of the caller before using it as a fixture.
probe="$(bash "$FG/loomwright/scripts/gen-color-legend.sh" --check 2>&1)"; prc=$?
if [ "$prc" -eq 0 ]; then
  setup_fail "the (g) fixture is NOT drifted — the control would prove nothing: $probe"
fi

orig_out="$(cd "$FG" && bash scripts/check-doc-currency.sh 2>&1)"; orig_rc=$?
if [ "$orig_rc" -ne 0 ] && has "$orig_out" "LEGEND DRIFT"; then
  ok "(g1) the UNMUTATED gate FAILS on the drifted fixture and emits the specific LEGEND DRIFT diagnostic"
else
  no "(g1) the UNMUTATED gate FAILS on the drifted fixture and emits the specific LEGEND DRIFT diagnostic" \
     "rc=$orig_rc: $orig_out"
fi

# Build the mutant: delete exactly the one-line invocation. The function stays defined and
# uncalled — a faithful "the wiring was reverted" mutation.
MUT="$FG/scripts/check-doc-currency.mutant.sh"
grep -v '^run_legend_check || fail=1$' "$FG/scripts/check-doc-currency.sh" > "$MUT" \
  || setup_fail "could not build the mutant"

mut_ok=1
[ -s "$MUT" ] || { no "(g2) mutant gate: the mutant is non-empty"; mut_ok=0; }
if ! diff -q "$FG/scripts/check-doc-currency.sh" "$MUT" >/dev/null 2>&1; then :; else
  no "(g2) mutant gate: the mutant DIFFERS from the original (the deletion actually landed)"; mut_ok=0
fi
bash -n "$MUT" 2>/dev/null || { no "(g2) mutant gate: the mutant is syntactically valid (bash -n)"; mut_ok=0; }
if [ "$mut_ok" -eq 1 ]; then
  ok "(g2) mutant gate: non-empty, differs from the original, and bash -n clean"
fi

if [ "$mut_ok" -eq 1 ]; then
  mut_out="$(cd "$FG" && bash scripts/check-doc-currency.mutant.sh 2>&1)"; mut_rc=$?
  if has "$mut_out" "doc-currency: all checked version/count claims match"; then
    ok "(g3) the mutant still RAN the rest of the gate (it reached its own success line — not a crash)"
  else
    no "(g3) the mutant still RAN the rest of the gate (it reached its own success line — not a crash)" "$mut_out"
  fi
  if [ "$mut_rc" -eq 0 ] && ! has "$mut_out" "LEGEND DRIFT"; then
    ok "(g4) with the CALLER's invocation reverted, the gate WRONGLY PASSES the drifted fixture — the wired check is what executed"
  else
    no "(g4) with the CALLER's invocation reverted, the gate WRONGLY PASSES the drifted fixture — the wired check is what executed" \
       "rc=$mut_rc (expected 0, and no LEGEND DRIFT): $mut_out"
  fi
else
  no "(g3/g4) skipped — the mutant failed its validity gate, so it is not evidence"
fi

# The one line the control depends on must exist in the REAL caller, not just in the copy.
real_txt="$(cat "$DOC_CURRENCY")"
if has "$real_txt" 'run_legend_check || fail=1'; then
  ok "(g5) the real scripts/check-doc-currency.sh carries the invocation this control mutates"
else
  no "(g5) the real scripts/check-doc-currency.sh carries the invocation this control mutates" \
     "the mutation above deleted nothing in the real gate — the control is measuring a copy that has drifted from it"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
