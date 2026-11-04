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
external_requires:
  - "a live session able to run /launch-pad on a fixture"
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
out="$(cd "$SCR" && bash "$S" scope-outside reqs/known.md brief.md --bogus 2>"$T/sc.err")"; rc=$?
check "SC1b an unknown option ⇒ exit 1, empty stdout" "$rc|$out" "1|"
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

# The brief's external_requires prose line holds a `/` and so matches the `- "…"` form; SC1 already pins
# that it is never listed, and SC9d removes the whitespace filter (the false outside path it exists for).
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
sc_red "SC9d the whitespace filter removed lists the external_requires prose line, turning SC1 red" \
  "$(sc_mut prose " && !/[[:space:]]/' | env LC_ALL=C sort -u" 's# \&\& !/\[\[:space:]]/##')" \
  "$SC_OUT_WANT" reqs/known.md brief.md

# ---- SG: the scope re-gate (lane-scope-regate Part B): lane-scope-check / lane-scope-decide, the held-lane readers ------
# A synthetic wave of two lanes cloned from a scratch origin (lane.json, run files, the lane table written by hand; the
# real planner, the REAL automate-helpers.sh writers). Groups: SG1 two saved briefs share a file ⇒ overlap · SG2 a file
# only the reverse direction finds · SG3 a sibling with no saved brief is read by its reserved Touches · SG4 clear
# (changelog.d/ exempt) · SG5 unreadable (no saved brief; a sibling's Touches unreadable) — never clear · SG6 a pending
# widening is listed · SG7 a removed lane / an item outside the wave line is not compared · SD lane-scope-decide (refusals,
# continue, revise, serialize, defer) · SI --inbox and --json · SGd the Stop guard · SM the brief's Pin mutations.
SGR="$T/sg"; SGPAR=automate-2026-11-04-100000; SGP="$SGR/primary"; SGL="$SGR/primary-lanes/$SGPAR"; SGO="$SGR/origin.git"
SGRF="$SGP/.supervisor/automate/$SGPAR.md"; SGT="$SGP/.supervisor/automate/$SGPAR.lanes"; SGH="$HERE/automate-helpers.sh"
mkdir -p "$SGR/seed/reqs" "$SGR/seed/src/a" "$SGR/seed/src/b" "$SGP/.supervisor/automate" "$SGL" "$SGR/bin"
git init -q --bare "$SGO"; git --git-dir="$SGO" symbolic-ref HEAD refs/heads/main
git init -q "$SGR/seed"; git -C "$SGR/seed" checkout -q -b main
printf '.supervisor/\n' > "$SGR/seed/.gitignore"
printf '# x\n## Touches\nsrc/a/\n## Depends on\nnone\n' > "$SGR/seed/reqs/x.md"
printf '# y\n## Touches\nsrc/b/\n## Depends on\nnone\n' > "$SGR/seed/reqs/y.md"
echo a > "$SGR/seed/src/a/one.ts"; echo b > "$SGR/seed/src/b/two.ts"; echo s > "$SGR/seed/src/shared.ts"
git -C "$SGR/seed" add -A; git -C "$SGR/seed" commit -qm seed; git -C "$SGR/seed" remote add origin "$SGO"; git -C "$SGR/seed" push -q origin main 2>/dev/null
cat > "$SGR/bin/gh" <<'GHEOF'
#!/usr/bin/env bash
case "$*" in "pr view"*) [ -n "${SG_GH_JSON:-}" ] && { printf '%s\n' "$SG_GH_JSON"; exit 0; } ;; esac
exit 1
GHEOF
chmod +x "$SGR/bin/gh"
printf 'echo "LAUNCH $*" >> %s; echo "lane-launch: continued"\n' "$SGR/launch.log" > "$SGR/launch.sh"
# sg_lane <n> <item> <brief lines|-> [<pause>] — (re)build lane L<n>: a clone, lane.json, its run file (+ a saved brief)
sg_lane() {
  local d="$SGL/L$1" run="$SGPAR-L$1" p="${4:-scope_hold}"
  rm -rf "$d"; git clone -q "$SGO" "$d" 2>/dev/null; mkdir -p "$d/.supervisor/automate" "$d/.supervisor/jobs/pending"
  jq -n --arg l "L$1" --arg r "$run" --arg pa "$SGPAR" --arg pr "$SGP" '{schema_version: 1, lane: $l, run_id: $r, parent_run_id: $pa, primary: $pr, parallel: 2}' > "$d/.supervisor/lane.json"
  { printf '# Automate Run: %s\n\n## Status: %s\n\n## Queue\n- [ ] %s\n\n## Current\n- item: %s | status: running | pr: null | branch: null\n- pause_reason: %s\n\n## Progress\n- 2026-11-04T10:00:00Z picked %s\n' \
      "$run" "$([ "$p" = null ] && echo running || echo paused)" "$2" "$2" "$p" "$2"
    if [ "$3" != - ]; then printf -- '- 2026-11-04T10:05:00Z launch-pad saved .supervisor/jobs/pending/L%s.md\n' "$1"; fi
    [ "$p" != scope_hold ] || printf -- '- 2026-11-04T10:05:01Z scope_hold — .supervisor/jobs/pending/L%s.md saved; held before the Supervisor phase\n' "$1"
  } > "$d/.supervisor/automate/$run.md"
  [ "$3" = - ] || printf '# Supervisor Job: L%s\n## Subtask Contracts\nlanes:\n%s\n' "$1" "$3" > "$d/.supervisor/jobs/pending/L$1.md"
}
sg_wave() { # the parent run file + lane table for L1 (reqs/x.md) and L2 (reqs/y.md)
  printf '# Automate Run: %s\n\n## Status: running\n\n## Run Config\n- parallel: 2\n\n## Queue\n- [ ] reqs/x.md\n- [ ] reqs/y.md\n\n## Current\n- item: null | status: null\n- wave: 1 | items: reqs/x.md, reqs/y.md\n- pause_reason: null\n\n## Progress\n- 2026-11-04T09:59:00Z run created\n' "$SGPAR" > "$SGRF"
  { printf '%s\n' "$LT_HEADER"
    printf 'L1\t%s\treqs/x.md\t%s-L1\t-\t-\t-\trunning\t-\t-\n' "$SGL/L1" "$SGPAR"
    printf 'L2\t%s\treqs/y.md\t%s-L2\t-\t-\t-\trunning\t-\t-\n' "$SGL/L2" "$SGPAR"; } > "$SGT"
}
LT_HEADER="$(printf '#lane\tpath\titem\trun_id\tpid\tpid_start\tsession_id\tstate\tlast_launch_utc\tblocked_reason')"
sgc() { bash "$1" lane-scope-check "$SGL/L2" 2>&1; }   # <entry>
sgd() { local e="$1"; shift; LOOMWRIGHT_LANES_HELPERS="$SGH" LOOMWRIGHT_LANES_SCOPE_LAUNCH="bash $SGR/launch.sh" LOOMWRIGHT_GH_BIN="$SGR/bin/gh" bash "$e" lane-scope-decide "$SGL/L2" "$@" 2>&1; }
SG_B1='  - "src/a/one.ts"
  - "src/shared.ts"'
SG_B2='  - "src/b/two.ts"
  - "src/shared.ts"
  - "changelog.d/y.md"'
SG_OV_WANT="overlap — src/shared.ts shared with L1 (saved brief)"
# the SG fixtures each leg (and each mutant) rebuilds
sg_fx1() { sg_wave; sg_lane 1 reqs/x.md "$SG_B1" null; sg_lane 2 reqs/y.md "$SG_B2"; }
sg_fx2() { sg_wave; sg_lane 1 reqs/x.md '  - "src/b/x.ts"' null; sg_lane 2 reqs/y.md '  - "src/b/two.ts"'; }
sg_fx3() { sg_wave; sg_lane 1 reqs/x.md - null; sg_lane 2 reqs/y.md '  - "src/b/two.ts"
  - "src/a/k.ts"'; }
sg_fx5() { sg_wave; sg_lane 1 reqs/x.md "$SG_B1" null; sg_lane 2 reqs/y.md -; }

sg_fx1; check "SG1 two lanes whose saved briefs share a file ⇒ overlap — <file> shared with L1 (saved brief)" "$(sgc "$S")" "$SG_OV_WANT"
sg_fx2; check "SG2 a file only the reverse direction finds (L2's Touches src/b/ holds L1's brief path)" "$(sgc "$S")" "overlap — src/b/x.ts shared with L1 (saved brief)"
sg_fx3; check "SG3 a sibling with no saved brief is compared by its reserved Touches" "$(sgc "$S")" "overlap — src/a/k.ts shared with L1 (reserved Touches)"
sg_wave; sg_lane 1 reqs/x.md "$SG_B1" null; sg_lane 2 reqs/y.md '  - "src/b/two.ts"
  - "changelog.d/y.md"'
check "SG4 disjoint sets (changelog.d/ exempt) ⇒ clear" "$(sgc "$S")" "clear"
sg_fx5; check "SG5 no saved brief this pass ⇒ unreadable, never clear" "$(sgc "$S")" "unreadable — L2 has no saved brief this pass (no launch-pad saved line in its run file)"
sg_fx1; rm -f "$SGL/L1/reqs/x.md"
check "SG5b a sibling's Touches unreadable ⇒ unreadable — L1 Touches" "$(sgc "$S")" "unreadable — L1 Touches (plan-waves --touches failed)"
sg_fx1; printf '\n## Scope widening\n- src/c/new.ts — the new module\n- decision: pending-coordinator\n' >> "$SGL/L2/.supervisor/jobs/pending/L2.md"
check "SG6 a pending-coordinator widening is listed after the comparison" "$(sgc "$S")" "$(printf '%s\nwidening — src/c/new.ts' "$SG_OV_WANT")"
sg_fx1; awk -F'\t' -v OFS='\t' '$1 == "L1" { $8 = "removed" } { print }' "$SGT" > "$SGT.t" && mv "$SGT.t" "$SGT"
check "SG7 a removed lane is not compared" "$(sgc "$S")" "clear"
sg_fx1; sed -i.bak 's/^- wave: 1 | items: .*/- wave: 1 | items: reqs\/y.md/' "$SGRF"
check "SG7b a lane whose item the wave line does not name is not compared" "$(sgc "$S")" "clear"
out="$(bash "$S" lane-scope-check 2>&1)"; rc=$?; check "SG8 usage ⇒ exit 1" "$rc" "1"

# SD — lane-scope-decide
sg_fx1; sg_before="$(cksum < "$SGL/L2/.supervisor/automate/$SGPAR-L2.md")"
out="$(sgd "$S" continue --owner-command '/automate --parallel 2')"; rc=$?
check "SD1 continue on an overlap without --gate AUT-OVERLAP ⇒ refused exit 1, nothing written" \
  "$rc|$(cksum < "$SGL/L2/.supervisor/automate/$SGPAR-L2.md")" "1|$sg_before"
out="$(sgd "$S" continue --gate AUT-OVERLAP)"; rc=$?
check "SD2 no owner command ⇒ BLOCKED exit 3" "$rc|$out" "3|lane-scope-decide: BLOCKED — L2 — no owner-invoked command — need the owner"
sg_wave; sg_lane 1 reqs/x.md "$SG_B1" null; sg_lane 2 reqs/y.md '  - "src/b/two.ts"'; : > "$SGR/launch.log"
out="$(sgd "$S" continue --owner-command '/automate --parallel 2')"; rc=$?
sg_lrf="$SGL/L2/.supervisor/automate/$SGPAR-L2.md"
if [ "$rc" = 0 ] && grep -qx '## Status: running' "$sg_lrf" && grep -qx -- '- pause_reason: null' "$sg_lrf" \
   && grep -q ' scope re-gate released (continue)$' "$sg_lrf" && grep -q ' scope re-gate: L2 clear$' "$SGRF" \
   && grep -qF "LAUNCH $SGL/L2 --continue --owner-command /automate --parallel 2" "$SGR/launch.log"; then
  ok "SD3 continue on clear ⇒ ## Status: running, pause_reason null, the release line, parent 'scope re-gate: L2 clear', lane-launch --continue"
else bad "SD3 continue on clear" "rc=$rc out=[$out] $(tr '\n' '|' < "$sg_lrf" | tail -c 300) launch=[$(cat "$SGR/launch.log")]"; fi
out="$(sgd "$S" continue --owner-command x)"; rc=$?
check "SD3b a released lane is not held ⇒ refused exit 1" "$rc|${out%% (*}" "1|lane-scope-decide: refused — L2 — not held"
sg_fx1; out="$(sgd "$S" continue --gate AUT-OVERLAP --owner-command x)"; rc=$?
has "SD4 continue in parallel (the owner's AUT-OVERLAP answer) ⇒ the parent line names the files and lanes" \
  "$rc|$(cat "$SGRF")" "scope re-gate: L2 continue in parallel — shares src/shared.ts with L1"
sg_fx1; printf '\n## Scope widening\n- src/c/new.ts — the new module\n- decision: pending-coordinator\n' >> "$SGL/L2/.supervisor/jobs/pending/L2.md"
out="$(sgd "$S" continue --gate AUT-OVERLAP --owner-command x)"
if grep -qx -- "- accepted: AUT-OVERLAP $(date -u +%Y-%m-%d)" "$SGL/L2/.supervisor/jobs/pending/L2.md" && ! grep -q pending-coordinator "$SGL/L2/.supervisor/jobs/pending/L2.md" \
   && grep -q 'widening accepted (AUT-OVERLAP): src/c/new.ts' "$SGRF"; then ok "SD4b the answer that lists a pending widening accepts it in the brief (- accepted: AUT-OVERLAP <date>)"
else bad "SD4b widening accepted" "$out"; fi
sg_fx1; out="$(sgd "$S" revise --gate AUT-OVERLAP --owner-command x)"
has "SD5 revise ⇒ released with the files to keep off (the driver re-plans)" "$(cat "$SGL/L2/.supervisor/automate/$SGPAR-L2.md")" "scope re-gate released (revise) — keep off: src/shared.ts"
# serialize: L1 not yet parked ⇒ stays held, scope_wait recorded once; L1 ready_for_release ⇒ its exact PR head merged, released
sg_fx1; out="$(sgd "$S" serialize --after L1 --gate AUT-OVERLAP --owner-command x)"; rc=$?
out2="$(sgd "$S" serialize --after L1 --gate AUT-OVERLAP --owner-command x)"
if [ "$rc" = 0 ] && case "$out" in "lane-scope-decide: held — L2 waits for L1"*) true ;; *) false ;; esac \
   && [ "$(grep -c 'scope re-gate: scope_wait L1 (serialize)$' "$sg_lrf")" = 1 ] && grep -qx -- '- pause_reason: scope_hold' "$sg_lrf"; then
  ok "SD6 serialize before L1 parks ⇒ held, scope_wait recorded once (a re-run adds none)"
else bad "SD6 serialize wait" "rc=$rc out=[$out] [$out2]"; fi
git -C "$SGL/L1" checkout -q -b feature/x && echo x > "$SGL/L1/src/a/x.ts" && git -C "$SGL/L1" add -A && git -C "$SGL/L1" commit -qm x && git -C "$SGL/L1" push -q origin feature/x 2>/dev/null
sg_sha="$(git -C "$SGL/L1" rev-parse HEAD)"
sed -i.bak 's#^- item: reqs/x.md | status: running | pr: null#- item: reqs/x.md | status: ready_for_release | pr: https://github.com/o/r/pull/7#; s/^- pause_reason: null/- pause_reason: ready_for_release/' "$SGL/L1/.supervisor/automate/$SGPAR-L1.md"
sg_js="{\"headRefOid\":\"$sg_sha\",\"headRefName\":\"feature/x\",\"state\":\"OPEN\"}"
out0="$(SG_GH_JSON="$sg_js" sgd "$S" serialize --after L1 --gate AUT-OVERLAP --owner-command x)"
case "$out0" in "lane-scope-decide: integrate — L2 stays held"*"
git merge --no-ff $sg_sha"*) ok "SD6a L1 ready ⇒ its exact head fetched and the merge PRINTED (the script runs no merge), still held" ;; *) bad "SD6a integrate line" "$out0" ;; esac
git -C "$SGL/L2" merge -q --no-ff "$sg_sha" -m "serialize" >/dev/null 2>&1
out="$(SG_GH_JSON="$sg_js" sgd "$S" serialize --after L1 --gate AUT-OVERLAP --owner-command x)"; rc=$?
if [ "$rc" = 0 ] && git -C "$SGL/L2" merge-base --is-ancestor "$sg_sha" HEAD && grep -qx -- '- pause_reason: null' "$sg_lrf" \
   && grep -q "scope re-gate released (serialized after L1 — merged PR #7 head ${sg_sha:0:12})" "$sg_lrf"; then
  ok "SD6b once the exact head is in L2's HEAD the re-run releases"
else bad "SD6b serialize release" "rc=$rc out=[$out]"; fi
sg_fx1; out="$(SG_GH_JSON='{"headRefOid":"0000000000000000000000000000000000000000","headRefName":"feature/x"}' sgd "$S" serialize --after L1 --gate AUT-OVERLAP --owner-command x)"
# defer: the item leaves the wave unchecked; the lane is gone and abandoned in the table
sg_fx1; out="$(sgd "$S" defer --gate AUT-OVERLAP)"; rc=$?
if [ "$rc" = 0 ] && [ ! -d "$SGL/L2" ] && [ "$(awk -F'\t' '$1 == "L2" { s = $8 } END { print s }' "$SGT")" = abandoned ] \
   && grep -qx -- '- wave: 1 | items: reqs/x.md' "$SGRF" && grep -qxF -- '- [ ] reqs/y.md' "$SGRF" \
   && grep -q 'scope re-gate: L2 defer to next wave — reqs/y.md left unchecked' "$SGRF" && ls -d "$SGL"/salvage/L2-deferred-* >/dev/null 2>&1; then
  ok "SD7 defer ⇒ salvaged, removed, table state abandoned (no lane claims it), the wave line drops it, its Queue row stays - [ ]"
else bad "SD7 defer" "rc=$rc dir=$([ -d "$SGL/L2" ] && echo kept) state=$(awk -F'\t' '$1 == "L2" { s = $8 } END { print s }' "$SGT") salv=$(ls "$SGL/salvage" 2>&1 | tr '\n' ' ') $(grep -E 'wave:|reqs/y' "$SGRF" | tr '\n' '|')"; fi
sg_fx1; out="$(sgd "$S" defer)"; rc=$?; check "SD7b defer without --gate (no owner answer) ⇒ refused exit 1, the lane kept" "$rc|$([ -d "$SGL/L2" ] && echo kept)" "1|kept"

# SI — the held lane on lane-status --inbox and --json
sg_fx1
sg_inbox="$(LOOMWRIGHT_LANES_HELPERS="$SGH" bash "$S" lane-status "$SGRF" --inbox 2>&1)"
has "SI1 --inbox lists the held lane under AUT-OVERLAP" "$sg_inbox" "L2 scope_hold AUT-OVERLAP — L2 is held before its Supervisor phase (scope_hold)"
has "SI1b … with the catalog's AUT-OVERLAP labels" "$sg_inbox" "options: Serialize | Continue in parallel | Defer to next wave | Revise"
sg_json() { LOOMWRIGHT_LANES_HELPERS="$SGH" bash "$1" lane-status "$SGRF" --json 2>/dev/null | jq -r '.lanes[] | select(.lane == "L2") | .state + " " + ([.timeline.steps[]? | select(.state == "waiting")] | length | tostring)' 2>/dev/null; }
check "SI2 --json: the lane's state is scope_hold and its current step reads waiting" "$(sg_json "$S")" "scope_hold 1"

# SGd — the coordinator's Stop hook blocks while a held lane has no decision
mkdir -p "$SGP/.supervisor/run.lock"; printf 'pid\t1\nowner\tautomate-lanes:%s\nsession_id\tcoord-s\n' "$SGPAR" > "$SGP/.supervisor/run.lock/meta"
sg_guard() { printf '{"session_id":"coord-s","cwd":"%s"}' "$SGP" | bash "$1" 2>/dev/null; }
sg_fx1
has "SGd1 an undecided scope_hold lane blocks the coordinator's turn end, naming it" "$(sg_guard "$HERE/guard-lane-wait-armed.sh")" '"decision":"block","reason":"A --parallel lane is held before its Supervisor phase (scope_hold) with no scope re-gate decision: L2.'
printf -- '- 2026-11-04T10:06:00Z scope re-gate: scope_wait L1 (serialize)\n' >> "$sg_lrf"
check "SGd2 a recorded decision (serialize's scope_wait) no longer blocks" "$(sg_guard "$HERE/guard-lane-wait-armed.sh")" "{}"
rm -rf "$SGP/.supervisor/run.lock"

# SM — the brief's Pin mutations for Part B: each one-line edit turns its pin red (built from $SB like SC9, gated)
sg_mut() { # <name> <anchor (once in $SB)> <replacement> — the mutant entry's path, or nothing
  local d="$T/sgmut/$1" c
  mkdir -p "$d"; for e in "$SCB"/*; do ln -s "$(readlink "$e")" "$d/${e##*/}" 2>/dev/null; done
  c="$(grep -cF -- "$2" "$SB")"; [ "$c" = 1 ] || return 0
  AN="$2" RE="$3" awk 'BEGIN { a = ENVIRON["AN"]; r = ENVIRON["RE"] } { i = index($0, a); if (i > 0 && !d) { $0 = substr($0, 1, i - 1) r substr($0, i + length(a)); d = 1 } print }' "$SB" > "$d/automate-lanes.sh"
  if [ -s "$d/automate-lanes.sh" ] && ! cmp -s "$SB" "$d/automate-lanes.sh" && bash -n "$d/automate-lanes.sh"; then printf '%s' "$d/automate-lanes.sh"; fi
}
sg_red() { # <leg> <mutant> <fixture fn> <want> <command: check|json|…>
  local got
  [ -n "$2" ] || { bad "$1 mutant not built (anchor not once, empty, no difference, or bash -n failed)"; return; }
  "$3"; case "$5" in check) got="$(sgc "$2")" ;; json) got="$(sg_json "$2")" ;; continue) sgd "$2" continue --owner-command x >/dev/null; got="$(grep -c 'pause_reason: null' "$sg_lrf")" ;;
    defer) sgd "$2" defer --gate AUT-OVERLAP >/dev/null; got="$(awk -F'\t' '$1 == "L2" { s = $8 } END { print s }' "$SGT")" ;; esac
  if [ "$got" != "$4" ]; then ok "$1 (mutant: $(printf '%s' "$got" | tr '\n' ' ' | cut -c1-100))"; else bad "$1 — the mutant still passes: the pin is vacuous"; fi
}
sg_fx4() { sg_wave; sg_lane 1 reqs/x.md "$SG_B1" null; sg_lane 2 reqs/y.md '  - "src/b/two.ts"'; }
sg_red "SM1 the reverse-direction _lanes_is_declared call dropped turns SG2 red" \
  "$(sg_mut reverse 'if _lanes_is_declared "$f" "$tmp/me"; then' 'if false; then')" sg_fx2 "overlap — src/b/x.ts shared with L1 (saved brief)" check
sg_red "SM2 a sibling read without its Touches half (brief only) turns SG3 red" \
  "$(sg_mut notouches 'if [ ! -d "$sp" ] || ! _lanes_sg_set "$sp" "$si" "$sb" "$tmp/o"; then' 'if ! { : > "$tmp/o"; [ -z "$sb" ] || _lanes_brief_paths "$sb" > "$tmp/o"; }; then')" \
  sg_fx3 "overlap — src/a/k.ts shared with L1 (reserved Touches)" check
sg_red "SM3 the unreadable branch reading clear turns SG5 red" \
  "$(sg_mut unreadclear 'if [ -s "$tmp/un" ]; then SG_KIND=unreadable;' 'if false; then SG_KIND=unreadable;')" \
  sg_fx5 "unreadable — L2 has no saved brief this pass (no launch-pad saved line in its run file)" check
sg_red "SM4 lane-scope-decide skipping its current-set (the lane stays scope_hold) turns SD3 red" \
  "$(sg_mut nocurset 'bash "$HELPERS" current-set "$stg" --pause-reason null' 'true')" sg_fx4 1 continue
sg_red "SM5 defer skipping the un-claim (table state) turns SD7 red" \
  "$(sg_mut noclaim '_lt_set "$LN_TABLE" "$LN_LANE" 8 abandoned ||' 'true ||')" sg_fx1 abandoned defer
sg_red "SM6 scope_hold dropped from the step-state waiting regex turns SI2 red" \
  "$(sg_mut nowait 'answer_pending|scope_hold|ready_for_release' 'answer_pending|ready_for_release')" sg_fx1 "scope_hold 1" json
# the guard's mutant: its scope-hold condition disabled ⇒ SGd1 red
sg_gd="$T/sgmut/guard"; mkdir -p "$sg_gd"
for e in "$HERE"/*; do [ "${e##*/}" = guard-lane-wait-armed.sh ] || ln -s "$e" "$sg_gd/${e##*/}" 2>/dev/null; done
sed 's/^  if \[ -n "\$UNDEC" \]; then$/  if false; then/' "$HERE/guard-lane-wait-armed.sh" > "$sg_gd/guard-lane-wait-armed.sh"
if ! cmp -s "$HERE/guard-lane-wait-armed.sh" "$sg_gd/guard-lane-wait-armed.sh" && bash -n "$sg_gd/guard-lane-wait-armed.sh"; then
  mkdir -p "$SGP/.supervisor/run.lock"; printf 'pid\t1\nowner\tautomate-lanes:%s\nsession_id\tcoord-s\n' "$SGPAR" > "$SGP/.supervisor/run.lock/meta"
  sg_fx1; case "$(sg_guard "$sg_gd/guard-lane-wait-armed.sh")" in *'scope_hold'*) bad "SM7 the guard mutant still blocks on scope_hold — the pin is vacuous" ;; *) ok "SM7 the guard's scope-hold condition disabled turns SGd1 red" ;; esac
  rm -rf "$SGP/.supervisor/run.lock"
else bad "SM7 guard mutant not built"; fi
