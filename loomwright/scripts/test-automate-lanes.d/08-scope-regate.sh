declare -F tal_pgrep >/dev/null && [ -n "${T:-}" ] && [ -d "$T" ] || { echo "${BASH_SOURCE[0]##*/}: run via test-automate-lanes.sh, never standalone (its kills need the suite's \$T)" >&2; exit 2; }
# ---- SC: scope-outside (automate-lanes.d/scope.sh, lane-scope-regate Part A) -----------------------------------
# The brief's planned paths (Subtask Contracts `path:` + `lanes:` lines) outside the item's Touches, read through
# _lanes_declared's own `plan-waves --touches` call (companions included) and compared by _lanes_is_declared.
# Every leg runs the REAL entry point against a scratch git repo $SCR (the real planner, never the $HELPERS stub).
# Groups: SC1 outside (changelog.d/ exempt, a Touches directory covers its files) · SC2 companions included (+ the
# no-companions control) · SC3 inside · SC4 unknown Touches ⇒ `unknown`, no list · SC5 unreadable Touches (missing
# item, malformed companions) ⇒ `unreadable <n>` + every brief path · SC6 absolute item · SC7 usage / unreadable
# brief ⇒ exit 1, empty stdout · SC8 _lanes_declared's LD_TOUCHES stays known | unknown, LD_TOUCHES_READ tells
# unreadable apart · SC9 the brief's Pin mutations (each one-line mutant built from $SB, gated: anchor once,
# non-empty, differs, bash -n; run beside symlinks of every other scripts/ entry so the real planner resolves).
SCR="$T/sc8"; mkdir -p "$SCR/reqs" "$SCR/src/a" "$SCR/docs"
git init -q "$SCR"
printf '# known\n## Touches\nsrc/a/\ndocs/x.md\n## Depends on\nnone\n' > "$SCR/reqs/known.md"
printf '# unknown\n## Touches\nunknown\n## Depends on\nnone\n' > "$SCR/reqs/unknown.md"
cat > "$SCR/brief.md" <<'EOF'
# Supervisor Job: sc
## Subtask Contracts
```yaml
# Subtask 1
provides:
  - {kind: "file", path: "src/a/one.ts"}
  - {kind: "symbol", path: "src/b/two.ts", name: "Two"}
lanes:
  - "src/a/one.ts"
  - "src/b/two.ts"
  - "docs/x.md"
  - "docs/y.md"
  - "changelog.d/sc.md"
```
EOF
printf '# Supervisor Job: in\nlanes:\n  - "src/a/deep/x.ts"\n  - "docs/x.md"\n  - "changelog.d/in.md"\n' > "$SCR/brief-in.md"
SC_OUT_WANT="$(printf 'outside 2\ndocs/y.md\nsrc/b/two.ts')"
SC_UNR_WANT="$(printf 'unreadable 4\ndocs/x.md\ndocs/y.md\nsrc/a/one.ts\nsrc/b/two.ts')"
# sc <entry> <item> <brief> [<root>] — stdout only (stderr dropped), from inside the scratch repo
sc() { ( cd "$SCR" && bash "$1" scope-outside "$2" "$3" ${4:+--root "$4"} 2>/dev/null ); }

check "SC1 two brief paths outside Touches ⇒ outside 2 + both (changelog.d/ exempt, src/a/ covers src/a/one.ts)" \
  "$(sc "$S" reqs/known.md brief.md)" "$SC_OUT_WANT"
mkdir -p "$SCR/.agent"
printf '{"schema_version":1,"companions":[{"when":"src/a/*","add":["src/b/two.ts"]}]}\n' > "$SCR/.agent/companions.json"
check "SC2 a companion-added path is inside (companions included)" "$(sc "$S" reqs/known.md brief.md)" "$(printf 'outside 1\ndocs/y.md')"
rm -f "$SCR/.agent/companions.json"
check "SC2b control: the same brief with no companions.json lists it again" "$(sc "$S" reqs/known.md brief.md)" "$SC_OUT_WANT"
check "SC3 every brief path inside Touches ⇒ the one line inside" "$(sc "$S" reqs/known.md brief-in.md)" "inside"
check "SC4 Touches unknown ⇒ the one line unknown (no list)" "$(sc "$S" reqs/unknown.md brief.md)" "unknown"
check "SC5 plan-waves --touches fails (missing item) ⇒ unreadable 4 + EVERY brief path" "$(sc "$S" reqs/missing.md brief.md)" "$SC_UNR_WANT"
check "SC5b an item whose every path is inside still reads unreadable when Touches cannot be read" \
  "$(sc "$S" reqs/missing.md brief-in.md)" "$(printf 'unreadable 2\ndocs/x.md\nsrc/a/deep/x.ts')"
echo '{bad' > "$SCR/.agent/companions.json"
check "SC5c malformed companions.json (plan-waves exits 1) ⇒ unreadable, never inside" "$(sc "$S" reqs/known.md brief-in.md)" \
  "$(printf 'unreadable 2\ndocs/x.md\nsrc/a/deep/x.ts')"
rm -f "$SCR/.agent/companions.json"
check "SC6 an absolute item under the root reads as the relative one" "$(sc "$S" "$SCR/reqs/known.md" brief.md)" "$SC_OUT_WANT"
check "SC6b --root from another cwd" "$(cd / && bash "$S" scope-outside reqs/known.md "$SCR/brief.md" --root "$SCR" 2>/dev/null)" "$SC_OUT_WANT"
out="$(cd "$SCR" && bash "$S" scope-outside reqs/known.md nope.md 2>"$T/sc.err")"; rc=$?
check "SC7 an unreadable brief ⇒ exit 1, empty stdout, named on stderr" "$rc|$out|$(cat "$T/sc.err")" \
  "1||automate-lanes: scope-outside: brief unreadable: nope.md"
out="$(cd "$SCR" && bash "$S" scope-outside reqs/known.md 2>"$T/sc.err")"; rc=$?
check "SC7b a missing <brief> ⇒ exit 1 usage, empty stdout" "$rc|$out|$(cat "$T/sc.err")" \
  "1||automate-lanes: scope-outside: usage: scope-outside <item> <brief> [--root <dir>]"
# SC8 — _lanes_declared's contract for its two other consumers (the scope fence, wave-build's overlap check).
sc_ld() { ( cd "$SCR" && bash -c '. "$1" >/dev/null 2>&1; _lanes_declared "$2" "$3" "" "$4/sc-ld.out"; echo "$LD_TOUCHES $LD_TOUCHES_READ"' _ "$S" "$SCR" "$1" "$T" ); }
check "SC8 known Touches ⇒ LD_TOUCHES known, read ok" "$(sc_ld reqs/known.md)" "known ok"
check "SC8b declared unknown ⇒ LD_TOUCHES unknown, read ok" "$(sc_ld reqs/unknown.md)" "unknown ok"
check "SC8c plan-waves fails ⇒ LD_TOUCHES unknown (never a third value), read failed" "$(sc_ld reqs/missing.md)" "unknown failed"

# SC9: the brief's Pin mutations for scope-outside — each one-line edit turns its pin red.
SCB="$T/scmut-base"; mkdir -p "$SCB"
for e in "$HERE"/*; do case "${e##*/}" in automate-lanes.sh|automate-lanes.d) ;; *) ln -s "$e" "$SCB/${e##*/}" ;; esac; done
# sc_mut <name> <anchor (fixed string, must occur once in $SB)> <sed program> — the mutant's path, or nothing.
sc_mut() {
  local d="$T/scmut/$1"; mkdir -p "$d"
  for e in "$SCB"/*; do ln -s "$(readlink "$e")" "$d/${e##*/}" 2>/dev/null; done
  [ "$(grep -cF -- "$2" "$SB")" = 1 ] || return 0
  sed "$3" "$SB" > "$d/automate-lanes.sh"
  if [ -s "$d/automate-lanes.sh" ] && ! cmp -s "$SB" "$d/automate-lanes.sh" && bash -n "$d/automate-lanes.sh"; then printf '%s' "$d/automate-lanes.sh"; fi
}
# sc_red <leg> <mutant> <want> <item> <brief> — the mutant must NOT print <want> (which the real script prints).
sc_red() {
  local got
  if [ -z "$2" ]; then bad "$1 mutant not built (anchor not once, empty, no difference, or bash -n failed)"; return; fi
  got="$(sc "$2" "$4" "$5")"
  if [ "$got" != "$3" ]; then ok "$1 (mutant prints: $(printf '%s' "$got" | tr '\n' ' ' | cut -c1-120))"; else bad "$1 — the mutant still passes: the pin is vacuous"; fi
}
# control: the unmutated bundle, laid out the same way, passes SC1 (else every red below would be meaningless)
SCC="$(sc_mut control 'lanes_scope_outside() {' 's/^lanes_scope_outside() {$/lanes_scope_outside() { : control;/')"
if [ -n "$SCC" ] && [ "$(sc "$SCC" reqs/known.md brief.md)" = "$SC_OUT_WANT" ]; then ok "SC9 control: a no-op mutant beside the scripts/ symlinks passes SC1"
else bad "SC9 control: the mutant layout cannot run scope-outside (got: $( [ -n "$SCC" ] && sc "$SCC" reqs/known.md brief.md | head -2 | tr '\n' ' '))"; fi
sc_red "SC9a the _lanes_is_declared test removed (every path reads inside) turns SC1 red" \
  "$(sc_mut inside '_lanes_is_declared "$f" "$tmp/touches" || printf' 's#_lanes_is_declared "$f" "$tmp/touches" || printf#true || printf#')" \
  "$SC_OUT_WANT" reqs/known.md brief.md
sc_red "SC9b the unknown arm falling through to the outside listing turns SC4 red" \
  "$(sc_mut unknown 'elif [ "$LD_TOUCHES" = unknown ]; then' 's#elif \[ "\$LD_TOUCHES" = unknown \]; then#elif false; then#')" \
  "unknown" reqs/unknown.md brief.md
sc_red "SC9c the unreadable arm printing inside turns SC5 red" \
  "$(sc_mut unreadable 'echo "unreadable ${n:-0}"; cat "$tmp/brief"' 's#echo "unreadable \${n:-0}"; cat "\$tmp/brief"#echo inside#')" \
  "$SC_UNR_WANT" reqs/missing.md brief.md
