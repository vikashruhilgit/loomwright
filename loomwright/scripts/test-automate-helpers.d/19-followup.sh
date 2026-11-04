# =============================================================================
# Run directly (`bash <this file>`, as run-pin-mutations.sh runs a pin), this fragment re-executes the
# suite for this one part, so its assertions run against the helpers beside it; sourced by the
# runner, BASH_SOURCE[0] is this file and $0 the runner, and the guard never fires.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test-automate-helpers.sh" 19-followup; fi
echo "== FU. followup-bundle / followup-nudge / dismissed-drafts after a bundle (dismissed-followups/01) =="
# Every leg builds its own git checkout in mktemp (dismissed-drafts resolves the repo root through git)
# and makes REAL drafts: dismissed-drafts over a hand-built SUPERVISOR_RESULT sidecar, then
# dismissed-decide follow-up. `gh` and `lane-status --json` are stubs for item-state; nothing reaches
# GitHub, and no leg reads the live .supervisor/.
FU="$(mktemp -d)"; FU="$(cd "$FU" && pwd -P)"
FU_MUT="$(dirname "$H")/fu-mutant.sh"
mkdir -p "$FU/bin"
printf '#!/usr/bin/env bash\ncase " $* " in *" pr list "*) printf "[]" ;; *) exit 1 ;; esac\n' > "$FU/bin/gh"
printf '#!/usr/bin/env bash\nprintf "{\\"lanes\\": []}"\n' > "$FU/bin/lanes"
chmod +x "$FU/bin/gh" "$FU/bin/lanes"
FU_PR="https://github.com/acme/widgets/pull/42"
FU_ITEM=".supervisor/requirements/f/01-a.md"
FU_RID="automate-2026-01-01-000000"
FU_INTO=".supervisor/requirements/q/01-bundle.md"
FU_F1='{finding: "the guard in src/app.sh skips empty input", reason: out_of_scope, source: code_reviewer, severity: MEDIUM}'
FU_F2='{finding: "lib/util.py swallows a parse error", reason: out_of_scope, source: red_team, severity: HIGH}'
FU_L1='{finding: "a low nit about naming", reason: below_severity_floor, source: code_reviewer, severity: LOW}'
fu_is() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 — got '$(printf '%s' "$2" | tr '\n' '|')', want '$(printf '%s' "$3" | tr '\n' '|')'"; fi; }
# fu_sum <root> — every entry under .supervisor (names) plus every file's cksum: a write, a removal or a
# created directory all change it
fu_sum() { (cd "$1" && find .supervisor -print | env LC_ALL=C sort && find .supervisor -type f -exec cksum {} \; | env LC_ALL=C sort); }
# fu_repo <name> <heal_dismissed flow list> — a fresh checkout with one run file and its Phase 4.5
# sidecar; runs dismissed-drafts and decides EVERY draft follow-up. Sets R, AD, RF, PROP.
fu_repo() {
  local f
  R="$FU/$1"; mkdir -p "$R/.supervisor/automate" "$R/src" "$R/lib"
  git init -q "$R"
  : > "$R/src/app.sh"; : > "$R/lib/util.py"
  AD="$R/.supervisor/automate"; RF="$AD/$FU_RID.md"; PROP="$R/.supervisor/requirements/proposed"
  printf '# Automate Run: fixture\n## Status: running\n## Queue\n- [ ] %s\n## Progress\n- t0 picked\n' "$FU_ITEM" > "$RF"
  printf 'SUPERVISOR_RESULT:\n  schema_version: 1\n  status: completed\n  heal_iterations: 1\n  heal_decision: PASS\n  heal_dismissed: %s\n' "$2" > "$AD/$FU_RID.supervisor-result.md"
  bash "$H" dismissed-drafts "$RF" "$FU_ITEM" "$FU_PR" > "$FU/dd.out" 2>&1
  for f in "$PROP"/*--dismissed-*.md; do [ -f "$f" ] && bash "$H" dismissed-decide "$RF" "$f" follow-up >/dev/null 2>&1; done
  return 0
}
fu_own() { find "$PROP" -maxdepth 1 -type f -name '*--dismissed-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f].md' | env LC_ALL=C sort; }
fu_summ() { find "$PROP" -maxdepth 1 -type f -name '*--dismissed-summary.md'; }
# fu_run <helper> <args...> — stdout FU_OUT, stderr FU_ERR, exit FU_RC
fu_run() { local h="$1"; shift; FU_RC=0; FU_OUT="$(LOOMWRIGHT_GH_BIN="$FU/bin/gh" LOOMWRIGHT_LANE_STATUS_BIN="$FU/bin/lanes" bash "$h" "$@" 2>"$FU/err")" || FU_RC=$?; FU_ERR="$(cat "$FU/err")"; }
# fu_mut_check <label> <anchor> <replacement|__DELETE__> <scenario_fn> <expected> — 18-backlog's
# bl_mut_check shape on a COPY of the bundle: the FIRST line holding <anchor> replaced (or deleted),
# trusted only when the anchor is unique, the mutant non-empty, different and `bash -n` clean.
fu_mut_check() {
  local got
  FU_A="$2" FU_R="$3" awk 'BEGIN { a = ENVIRON["FU_A"]; r = ENVIRON["FU_R"] }
    !d && index($0, a) { d = 1; if (r == "__DELETE__") next; print r; next } { print }' "$H" > "$FU_MUT"
  if [ "$(grep -cF -- "$2" "$H")" = 1 ] && [ -s "$FU_MUT" ] && ! cmp -s "$H" "$FU_MUT" && bash -n "$FU_MUT" 2>/dev/null; then
    got="$("$4" "$FU_MUT")"
    if [ "$got" != "$5" ]; then ok "FU mutant ($1) turns its leg red"; else no "FU mutant ($1) did NOT discriminate: '$got'"; fi
  else
    no "FU mutant ($1) not gated (anchor not unique, mutant empty, identical, or bash -n failed)"
  fi
  rm -f "$FU_MUT"
}
# fu_dmut_check — the same on automate-dismissed.sh (exec'd by the dispatcher from beside it): a scripts
# dir of symlinks with a mutated copy of automate-dismissed.sh and the bundle; <scenario_fn> gets its dispatcher.
fu_dmut_check() {
  local got md e src="$HERE/automate-dismissed.sh"
  md="$(mktemp -d)"
  for e in "$HERE"/*; do
    case "${e##*/}" in automate-dismissed.sh|automate-helpers.sh) ;; *) ln -s "$e" "$md/${e##*/}" ;; esac
  done
  cp "$H" "$md/automate-helpers.sh"
  FU_A="$2" FU_R="$3" awk 'BEGIN { a = ENVIRON["FU_A"]; r = ENVIRON["FU_R"] }
    !d && index($0, a) { d = 1; if (r == "__DELETE__") next; print r; next } { print }' "$src" > "$md/automate-dismissed.sh"
  if [ "$(grep -cF -- "$2" "$src")" = 1 ] && [ -s "$md/automate-dismissed.sh" ] && ! cmp -s "$src" "$md/automate-dismissed.sh" && bash -n "$md/automate-dismissed.sh" 2>/dev/null; then
    got="$("$4" "$md/automate-helpers.sh")"
    if [ "$got" != "$5" ]; then ok "FU mutant ($1) turns its leg red"; else no "FU mutant ($1) did NOT discriminate: '$got'"; fi
  else
    no "FU mutant ($1) not gated (anchor not unique, mutant empty, identical, or bash -n failed)"
  fi
  rm -rf "$md"
}

# ---- FU2 (AC2) dry run prints the exact file and writes nothing; --confirm writes ONE file, removes
# exactly the named drafts, appends one Progress line per draft whose run file exists.
fu_repo t2 "[$FU_F1, $FU_F2, $FU_L1]"
FU_D1="$(fu_own | sed -n 1p)"; FU_D2="$(fu_own | sed -n 2p)"; FU_DS="$(fu_summ)"
fu_is "FU2 the fixture holds two per-finding follow-up drafts and one follow-up summary draft (real shape: ## Status: proposed first)" \
  "$(fu_own | wc -l | tr -d ' ') $([ -f "$FU_DS" ] && echo summary) $(grep -h -m1 '^## Status:' "$FU_D1" "$FU_DS" | sort -u) $(grep -h -m1 '^- \*\*Decision:\*\*' "$FU_D1" "$FU_D2" "$FU_DS" | sort -u)" \
  "2 summary ## Status: proposed - **Decision:** follow-up"
FU_B2="$(fu_sum "$R")"
fu_run "$H" followup-bundle "$FU_D1" "$FU_D2" "$FU_DS" --into "$FU_INTO" --root "$R"
printf '%s\n' "$FU_OUT" > "$FU/dry.md"
fu_is "FU2 a dry run exits 0, prints the requirement file (first status line pending), says so on stderr, and writes / removes nothing" \
  "$FU_RC|$(grep -m1 '^## Status:' "$FU/dry.md")|$(grep -c 'dry run' <<<"$FU_ERR")|$([ "$(fu_sum "$R")" = "$FU_B2" ] && echo unchanged)" \
  "0|## Status: pending|1|unchanged"
fu_s2d() { fu_run "$1" followup-bundle "$FU_D1" --into "$FU_INTO" --root "$R"; [ "$(fu_sum "$R")" = "$FU_B2" ] && echo unchanged || echo written; }
fu_mut_check "pin AC2: the --confirm gate deleted (a dry run writes)" '  if [ "$confirm" != 1 ]; then cat "$_FU_TMP/bundle.md";' __DELETE__ fu_s2d "unchanged"
# the mutant above may have written: rebuild the checkout before the real --confirm
rm -rf "$R"; fu_repo t2 "[$FU_F1, $FU_F2, $FU_L1]"
FU_D1="$(fu_own | sed -n 1p)"; FU_D2="$(fu_own | sed -n 2p)"; FU_DS="$(fu_summ)"
cp "$FU_DS" "$FU/summary.orig"
fu_run "$H" followup-bundle "$FU_D1" "$FU_D2" --into "$FU_INTO" --root "$R"
FU_T12="$(awk 'f { print } /^## Touches$/ { f = 1 }' <<<"$FU_OUT" | tr '\n' ' ')"
( cd "$R" && find .supervisor -type f | env LC_ALL=C sort ) > "$FU/before.lst"
fu_run "$H" followup-bundle "$FU_D1" "$FU_D2" "$FU_DS" --into "$FU_INTO" --root "$R"
printf '%s\n' "$FU_OUT" > "$FU/dry.md"
FU_RC0="$FU_RC"
fu_run "$H" followup-bundle "$FU_D1" "$FU_D2" "$FU_DS" --into "$FU_INTO" --root "$R" --confirm
( cd "$R" && find .supervisor -type f | env LC_ALL=C sort ) > "$FU/after.lst"
FU_W="$R/$FU_INTO"
fu_is "FU2 --confirm exits 0; the only file added is the target and the only files removed are the three named drafts (the run file changes in place)" \
  "$FU_RC0 $FU_RC|$(env LC_ALL=C comm -13 "$FU/before.lst" "$FU/after.lst" | tr '\n' ' ')|$(env LC_ALL=C comm -23 "$FU/before.lst" "$FU/after.lst" | sed 's#.*/##' | tr '\n' ' ')" \
  "0 0|$FU_INTO |$(printf '%s\n' "${FU_D1##*/}" "${FU_D2##*/}" "${FU_DS##*/}" | env LC_ALL=C sort | tr '\n' ' ')"
fu_is "FU2 the dry run printed exactly the file --confirm wrote (byte for byte)" "$(cmp -s "$FU/dry.md" "$FU_W" && echo same)" "same"
fu_is "FU2 the file's section order: # title, ## Status: pending, ## Findings, ## Acceptance criteria, ## Depends on, ## Touches" \
  "$(grep -E '^##? ' "$FU_W" | sed -E 's/^(# Follow-up bundle):.*/\1/' | tr '\n' '|')" \
  "# Follow-up bundle|## Status: pending|## Findings|## Acceptance criteria|## Depends on|## Touches|"
FU_H1="${FU_D1##*--dismissed-}"; FU_H1="${FU_H1%.md}"; FU_H2="${FU_D2##*--dismissed-}"; FU_H2="${FU_H2%.md}"
FU_HS="$(awk -F '\t' '$1 == "summary-member" { print $2 }' "$AD/$FU_RID.dismissed-decisions")"
fu_is "FU2 the provenance quote names each source draft with its run, its PR and its Key (h8)" \
  "$(grep -cxF "> - ${FU_D1##*/} — run $FU_RID, PR $FU_PR, Key $FU_H1" "$FU_W") $(grep -cxF "> - ${FU_D2##*/} — run $FU_RID, PR $FU_PR, Key $FU_H2" "$FU_W") $(grep -cxF "> - ${FU_DS##*/} — run $FU_RID, PR $FU_PR, Key $FU_HS" "$FU_W") $(sed -n '5p' "$FU_W" | cut -c1-17)" \
  "1 1 1 > **Provenance:**"
fu_is "FU2 each finding is > -quoted under its own ### Finding heading, and gets one re-verify criterion" \
  "$(grep -c '^> the guard in src/app.sh skips empty input$' "$FU_W") $(grep -c '^> lib/util.py swallows a parse error$' "$FU_W") $(grep -c '^> a low nit about naming$' "$FU_W") $(grep -c '^### Finding [0-9] (Key [0-9a-f]\{8\})$' "$FU_W") $(grep -c '^- \[ \] Finding [0-9] (Key [0-9a-f]\{8\}): re-verify it on `main`; if it still reproduces, fix it, otherwise record it here as not reproducible' "$FU_W")" \
  "1 1 1 3 3"
fu_is "FU2 ## Depends on is none; ## Touches is the union of two drafts' Touches (sorted, once each), and unknown once the summary draft (its nit names no file: Touches unknown) joins" \
  "$(awk '/^## Depends on$/ { getline; print; exit }' "$FU_W")|$FU_T12|$(grep -A1 '^## Touches$' "$FU/summary.orig" | tail -n1)|$(awk 'f { print } /^## Touches$/ { f = 1 }' "$FU_W" | tr '\n' ' ')" "none|lib/util.py src/app.sh |unknown|unknown "
fu_is "FU2 one 'dismissed: bundled <draft> → <file>' Progress line per draft (the run file exists)" \
  "$(for d in "$FU_D1" "$FU_D2" "$FU_DS"; do grep -cE "^- [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z dismissed: bundled ${d##*/} → $FU_INTO\$" "$RF"; done | tr '\n' ' ')" "1 1 1 "
fu_run "$H" plan-waves "$FU_W" --lint --root "$R"
fu_is "FU2 the planner lints the bundle clean (its own Touches / Depends on parser)" "$FU_RC" "0"
# a draft whose run file does not exist: bundled, removed, and no Progress line, silently
fu_repo t2b "[$FU_F1]"
FU_X="$PROP/automate-2099-01-01-000000--x-000000--dismissed-0badc0de.md"
sed "s/$FU_RID/automate-2099-01-01-000000/" "$(fu_own | sed -n 1p)" > "$FU_X"
fu_run "$H" followup-bundle "$FU_X" --into .supervisor/requirements/q/02-orphan.md --root "$R" --confirm
fu_is "FU2 a draft with no run file is bundled and removed with no Progress line and nothing on stderr" \
  "$FU_RC|$([ -f "$R/.supervisor/requirements/q/02-orphan.md" ] && echo written)|$([ -e "$FU_X" ] || echo removed)|$FU_ERR|$(ls "$AD" | grep -c '^automate-2099')" "0|written|removed||0"
# one draft whose Touches the planner reads unknown makes the union unknown
FU_O2="$(fu_own | sed -n 1p)"; FU_U="$PROP/automate-2026-01-01-000000--x-000000--dismissed-0ddba11a.md"
awk '/^## Touches$/ { print; print "unknown"; skip = 1; next } skip && /^## / { skip = 0 } !skip' "$FU_O2" > "$FU_U"
fu_run "$H" followup-bundle "$FU_O2" "$FU_U" --into .supervisor/requirements/q/03-mixed.md --root "$R"
fu_is "FU2 any draft with an unknown Touches makes the union unknown" "$(awk 'f { print } /^## Touches$/ { f = 1 }' <<<"$FU_OUT")" "unknown"

# ---- FU3 (AC3) every refusal: exit non-zero naming the reason, nothing written or removed, with and
# without --confirm; every draft is validated before the first write.
fu_repo t3 "[$FU_F1, $FU_F2]"
FU_G="$(fu_own | sed -n 1p)"
fu_refuse() { # <label> <reason substring> <args...>
  local l="$1" why="$2" b rc1 rc2; shift 2
  b="$(fu_sum "$R")"
  bash "$H" followup-bundle "$@" --root "$R" >/dev/null 2>"$FU/e1"; rc1=$?
  bash "$H" followup-bundle "$@" --root "$R" --confirm >/dev/null 2>"$FU/e2"; rc2=$?
  fu_is "FU3 refused: $l (non-zero exit naming the reason, nothing written or removed, with and without --confirm)" \
    "$([ "$rc1" -ne 0 ] && [ "$rc2" -ne 0 ] && echo nonzero) $(grep -cF -- "$why" "$FU/e1") $(grep -cF -- "$why" "$FU/e2") $([ "$(fu_sum "$R")" = "$b" ] && echo unchanged)" \
    "nonzero 1 1 unchanged"
}
mkdir -p "$PROP/automate-2026-01-01-000000--d--dismissed-dddddddd.md"
fu_refuse "a draft that is a directory" "not a regular file" "$PROP/automate-2026-01-01-000000--d--dismissed-dddddddd.md" --into "$FU_INTO"
rmdir "$PROP/automate-2026-01-01-000000--d--dismissed-dddddddd.md"
ln -s "$FU_G" "$PROP/automate-2026-01-01-000000--l--dismissed-11111111.md"
fu_refuse "a draft that is a symlink" "not a regular file" "$PROP/automate-2026-01-01-000000--l--dismissed-11111111.md" --into "$FU_INTO"
rm -f "$PROP/automate-2026-01-01-000000--l--dismissed-11111111.md"
fu_refuse "a draft that does not exist" "not a regular file" "$PROP/automate-2026-01-01-000000--n--dismissed-22222222.md" --into "$FU_INTO"
mkdir -p "$PROP/sub"; cp "$FU_G" "$PROP/sub/${FU_G##*/}"
fu_refuse "a draft not directly under proposed/" "not directly under .supervisor/requirements/proposed/" "$PROP/sub/${FU_G##*/}" --into "$FU_INTO"
rm -rf "$PROP/sub"
cp "$FU_G" "$PROP/hand-written.md"
fu_refuse "a draft not named *--dismissed-*.md" "not a dismissed-finding draft" "$PROP/hand-written.md" --into "$FU_INTO"
rm -f "$PROP/hand-written.md"
FU_UD="$PROP/automate-2026-01-01-000000--u--dismissed-33333333.md"
sed 's/^- \*\*Decision:\*\* follow-up$/- **Decision:** undecided/' "$FU_G" > "$FU_UD"
fu_refuse "a draft whose decision is not follow-up" "its first Decision is not follow-up" "$FU_UD" --into "$FU_INTO"
fu_refuse "an --into outside .supervisor/requirements/" "is outside .supervisor/requirements/" "$FU_G" --into .supervisor/automate/01-x.md
fu_refuse "an --into with a .. segment" "a . or .. segment" "$FU_G" --into .supervisor/requirements/q/../../automate/01-x.md
fu_refuse "an --into inside proposed/" "is inside proposed/" "$FU_G" --into .supervisor/requirements/proposed/01-x.md
fu_refuse "an --into in a new dir under proposed/" "is inside proposed/" "$FU_G" --into .supervisor/requirements/proposed/q/01-x.md
# a case-insensitive FS (macOS APFS default) resolves PROPOSED/ to proposed/ while `pwd -P` keeps the
# typed case: the refusal must decide by identity, not by spelling. Same for a draft named twice.
FU_CI=0; [ -d "$R/.supervisor/requirements/PROPOSED" ] && FU_CI=1
FU_GV="$PROP/$(printf '%s' "${FU_G##*/}" | sed 's/^automate-/AUTOMATE-/')"
if [ "$FU_CI" = 1 ]; then
  fu_refuse "an --into in a case-variant PROPOSED/" "is inside proposed/" "$FU_G" --into .supervisor/requirements/PROPOSED/99-b.md
  fu_refuse "an --into in a new dir under a case-variant Proposed/" "is inside proposed/" "$FU_G" --into .supervisor/requirements/Proposed/q/99-b.md
  fu_refuse "the same draft named twice, once by a case-variant spelling" "named twice" "$FU_G" "$FU_GV" --into "$FU_INTO"
else
  echo "  SKIP: FU3 case-variant PROPOSED/ and draft legs — the scratch filesystem is case-sensitive"
fi
mkdir -p "$R/.supervisor/requirements/q"; printf '# taken\n' > "$R/.supervisor/requirements/q/01-taken.md"
fu_refuse "an existing target file" "the target already exists" "$FU_G" --into .supervisor/requirements/q/01-taken.md
fu_refuse "one bad draft among good ones (the bad one named last)" "its first Decision is not follow-up" "$FU_G" "$(fu_own | sed -n 2p)" "$FU_UD" --into "$FU_INTO"
fu_refuse "the same draft named twice" "named twice" "$FU_G" "$FU_G" --into "$FU_INTO"
fu_refuse "an --into that is not a .md file" "must name a .md file" "$FU_G" --into .supervisor/requirements/q/01-x.txt
fu_refuse "an --into below an existing FILE" "nearest existing parent is not a directory" "$FU_G" --into .supervisor/requirements/q/01-taken.md/x.md
fu_refuse "an --into carrying a control character" "a control character in --into" "$FU_G" --into "$(printf '.supervisor/requirements/q/01-\033x.md')"
fu_refuse "an unknown option" "unknown option --bogus" "$FU_G" --into "$FU_INTO" --bogus
# a draft without its quoted finding block (hand-edited) cannot be bundled without losing its text
FU_NB="$PROP/automate-2026-01-01-000000--b--dismissed-44444444.md"
grep -v '^```\|^> ' "$FU_G" > "$FU_NB"
fu_refuse "a draft with no quoted finding block" "no quoted finding block" "$FU_NB" --into "$FU_INTO"
rm -f "$FU_NB"
fu_s3() { fu_run "$1" followup-bundle "$2" --into "$3" --root "$R"; printf '%s' "$FU_RC"; }
fu_s3d() { fu_s3 "$1" "$FU_UD" "$FU_INTO"; }
fu_mut_check "pin AC3: the decision-is-follow-up refusal deleted" '    [ "$dec" = follow-up ] || _fu_fail' __DELETE__ fu_s3d "1"
fu_s3p() { fu_s3 "$1" "$FU_G" .supervisor/requirements/proposed/01-x.md; }
fu_mut_check "pin AC3: the --into-inside-proposed/ refusal deleted" '  if _fu_in_proposed "$req" "$phys"; then' __DELETE__ fu_s3p "1"
if [ "$FU_CI" = 1 ]; then
  fu_s3pc() { fu_s3 "$1" "$FU_G" .supervisor/requirements/PROPOSED/99-b.md; }
  fu_mut_check "pin AC3: the proposed/ inode test reduced to a string match (PROPOSED/ slips through)" \
    '    if [ -e "$a" ] && [ "$a" -ef "$req/proposed" ]; then return 0; fi' '    if [ "$a" = "$req/proposed" ]; then return 0; fi' fu_s3pc "1"
  fu_s3dv() { fu_run "$1" followup-bundle "$FU_G" "$FU_GV" --into "$FU_INTO" --root "$R"; printf '%s' "$FU_RC"; }
  fu_mut_check "pin AC3: the by-identity named-twice refusal deleted (a case-variant twin is bundled twice)" \
    '    for c in ${abs[@]+"${abs[@]}"}; do if [ "$c" -ef "$prop/$name" ]; then' __DELETE__ fu_s3dv "1"
fi
fu_s3e() { fu_s3 "$1" "$FU_G" .supervisor/requirements/q/01-taken.md; }
fu_mut_check "pin AC3: the existing-target refusal deleted" '  if [ -e "$phys" ] || [ -L "$phys" ]; then _fu_fail "the target already exists' __DELETE__ fu_s3e "1"
fu_is "FU3 usage: no draft, or no --into, exits 1 with nothing on stdout" \
  "$(fu_run "$H" followup-bundle --into "$FU_INTO" --root "$R"; printf '%s|%s' "$FU_RC" "$FU_OUT") $(fu_run "$H" followup-bundle "$FU_G" --root "$R"; printf '%s|%s' "$FU_RC" "$FU_OUT")" "1| 1|"

# ---- FU3c two concurrent --confirm bundles of the SAME draft: one bundler at a time (proposed/'s mkdir
# lock), so exactly one target is written and the other run is refused; no lock is left behind.
fu_race() { # <helper> — the number of targets written per trial, 3 trials
  local i p
  for i in 1 2 3; do
    rm -rf "$FU/t3c"; fu_repo t3c "[$FU_L1]"; p="$(fu_summ)"
    bash "$1" followup-bundle "$p" --into .supervisor/requirements/q/a.md --root "$R" --confirm >/dev/null 2>&1 &
    bash "$1" followup-bundle "$p" --into .supervisor/requirements/q/b.md --root "$R" --confirm >/dev/null 2>&1 &
    wait
    printf '%s%s ' "$(find "$R/.supervisor/requirements/q" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')" "$([ -e "$PROP/.followup-bundle.lock" ] && echo +lock)"
  done
}
fu_is "FU3c two concurrent bundles of one draft write ONE queue item (3 trials) and release the lock" "$(fu_race "$H")" "1 1 1 "
fu_mut_check "pin: the bundle lock removed (concurrent bundles both write)" '    until mkdir "$prop/.followup-bundle.lock" 2>/dev/null; do' '    until true; do' fu_race "1 1 1 "
mkdir "$PROP/.followup-bundle.lock"
fu_run "$H" followup-bundle "$(fu_summ)" --into .supervisor/requirements/q/c.md --root "$R" --confirm
fu_is "FU3c a lock another bundler holds ⇒ refused after the wait, naming the lock, nothing written, the lock left in place" \
  "$FU_RC|$(grep -c 'holds .supervisor/requirements/proposed/.followup-bundle.lock' <<<"$FU_ERR")|$([ -e "$R/.supervisor/requirements/q/c.md" ] || echo none)|$([ -d "$PROP/.followup-bundle.lock" ] && echo kept)" "1|1|none|kept"
rmdir "$PROP/.followup-bundle.lock"

# ---- FU4 (AC4) a bundled follow-up draft is not recreated or re-reported by dismissed-drafts over the
# same sidecars: one leg per draft kind (per-finding, summary).
fu_repo t4 "[$FU_F1, $FU_L1]"
FU_4O="$(fu_own | sed -n 1p)"; FU_4S="$(fu_summ)"
bash "$H" followup-bundle "$FU_4O" --into .supervisor/requirements/q/01-own.md --root "$R" --confirm >/dev/null 2>&1
fu_s4o() { # <dispatcher> — `<recreated?>|<draft rows naming the absent draft>|<summary line>`
  local out; out="$(bash "$1" dismissed-drafts "$RF" "$FU_ITEM" "$FU_PR" 2>&1)"
  printf '%s|%s|%s' "$([ -e "$FU_4O" ] && echo recreated || echo absent)" "$(grep -cF -- "${FU_4O##*/}" <<<"$out")" "$(grep '^dismissed-drafts: [0-9]' <<<"$out")"
}
fu_is "FU4 per-finding: the bundled draft is not recreated, no draft row names it, and it is not counted (the kept summary still is)" \
  "$(fu_s4o "$H")" "absent|0|dismissed-drafts: 0 per-finding + 1 summary (1 listed in summary)"
fu_dmut_check "pin AC4: the on_disk(name) guard on a kept follow-up deleted" '            if on_disk(name):  # a kept follow-up' \
  __DELETE__ fu_s4o "absent|0|dismissed-drafts: 0 per-finding + 1 summary (1 listed in summary)"
bash "$H" followup-bundle "$FU_4S" --into .supervisor/requirements/q/02-summary.md --root "$R" --confirm >/dev/null 2>&1
fu_s4s() {
  local out; out="$(bash "$1" dismissed-drafts "$RF" "$FU_ITEM" "$FU_PR" 2>&1)"
  printf '%s|%s|%s' "$([ -e "$FU_4S" ] && echo recreated || echo absent)" "$(grep -cF -- "${FU_4S##*/}" <<<"$out")" "$(grep '^dismissed-drafts: [0-9]' <<<"$out")"
}
fu_is "FU4 summary: the bundled summary draft is not recreated, has no keep summary row, and its entries are not counted in m" \
  "$(fu_s4s "$H")" "absent|0|dismissed-drafts: 0 per-finding + 0 summary (0 listed in summary)"
fu_dmut_check "pin AC4: the on-disk guard on a kept follow-up summary deleted" '        if on_disk(nm):  # the same rule for a kept summary' \
  __DELETE__ fu_s4s "absent|0|dismissed-drafts: 0 per-finding + 0 summary (0 listed in summary)"

# ---- FU5 (AC5) finding text with a backtick, $(…), a `#` line and a fake `## Status: done` line is
# bundled as quoted data: nothing runs, every such line is `> `-prefixed, item-state reads open.
FU_CAN="$FU/canary"
fu_repo t5 "[{finding: \"run \$(touch $FU_CAN) and \`touch ${FU_CAN}2\` here\\n# not a heading\\n## Status: done\\n- **PR:** https://x/pull/1\", reason: stale, source: reviews, severity: HIGH}]"
FU_5="$(fu_own | sed -n 1p)"
fu_run "$H" followup-bundle "$FU_5" --into .supervisor/requirements/q/05-canary.md --root "$R" --confirm
FU_W5="$R/.supervisor/requirements/q/05-canary.md"
fu_is "FU5 the canary finding is bundled (exit 0) and nothing it names ran" \
  "$FU_RC $([ -f "$FU_W5" ] && echo written) $([ -e "$FU_CAN" ] || [ -e "${FU_CAN}2" ] || echo not-run)" "0 written not-run"
fu_is "FU5 every injected line is > -prefixed (backtick, \$(…), # line, ## Status: done, - **PR:**)" \
  "$(grep -cF "> run \$(touch $FU_CAN) and \`touch ${FU_CAN}2\` here" "$FU_W5") $(grep -cx '> # not a heading' "$FU_W5") $(grep -cx '> ## Status: done' "$FU_W5") $(grep -cx '> - \*\*PR:\*\* https://x/pull/1' "$FU_W5")" "1 1 1 1"
fu_s5() { # <helper> — `<## Status: lines> <foreign # lines>`
  local f="$R/.supervisor/requirements/q/05-m.md"
  rm -f "$f"; cp "$FU/t5-draft" "$FU_5" 2>/dev/null
  bash "$1" followup-bundle "$FU_5" --into .supervisor/requirements/q/05-m.md --root "$R" --confirm >/dev/null 2>&1
  printf '%s %s' "$(grep -c '^## Status:' "$f" 2>/dev/null)" \
    "$(grep -E '^#' "$f" 2>/dev/null | grep -cvE '^(# Follow-up bundle: [0-9]+ dismissed findings? from [0-9]+ follow-up drafts?|## Status: pending|## Findings|### Finding [0-9]+ \(Key ([0-9a-f]{8}|unknown)\)|## Acceptance criteria|## Depends on|## Touches)$')"
}
fu_repo t5m "[{finding: \"x\\n## Status: done\\n# fake\", reason: stale, source: reviews, severity: HIGH}]"
FU_5="$(fu_own | sed -n 1p)"; cp "$FU_5" "$FU/t5-draft"
fu_is "FU5 exactly one ## Status: line and no heading the bundler did not write" "$(fu_s5 "$H")" "1 0"
fu_mut_check "pin AC5: the line that > -prefixes finding text deleted" '    q = ["> " + t for t in q]' __DELETE__ fu_s5 "1 0"
fu_run "$H" item-state .supervisor/requirements/q/05-canary.md --root "$FU/t5"
fu_is "FU5 item-state on the written file reads open (its first ## Status: is pending), never done" "$(cut -f1 <<<"$FU_OUT")" "open"

# ---- FU6 (AC6, the subcommand) followup-nudge: ONE line when the oldest follow-up draft is older than
# LOOMWRIGHT_FOLLOWUP_NUDGE_DAYS (default 14), else nothing; always exit 0. The ledger rows are the
# real decide's ts (now), so LOOMWRIGHT_FOLLOWUP_NOW = now + <d> days ages every draft <d> days.
fu_repo t6 "[$FU_F1, $FU_F2, $FU_L1]"
FU_NOW="$(date -u +%s)"
fu_nudge() { # <helper> <days ahead> [<nudge days>] [<root>] — `<exit>|<stdout>`
  local out rc=0
  out="$(LOOMWRIGHT_FOLLOWUP_NOW="$((FU_NOW + $2 * 86400))" LOOMWRIGHT_FOLLOWUP_NUDGE_DAYS="${3:-}" bash "$1" followup-nudge --root "${4:-$R}" 2>/dev/null)" || rc=$?
  printf '%s|%s' "$rc" "$out"
}
FU_LINE20="automate: 3 follow-up drafts, oldest 20d — /backlog --state follow_up, then followup-bundle"
fu_is "FU6 the oldest follow-up older than 14 days ⇒ exactly the one nudge line, exit 0" "$(fu_nudge "$H" 20)" "0|$FU_LINE20"
fu_is "FU6 all younger than the default (10d), or exactly at it (14d) ⇒ nothing, exit 0" "$(fu_nudge "$H" 10) $(fu_nudge "$H" 14)" "0| 0|"
fu_s6() { fu_nudge "$1" 10; }
fu_mut_check "pin AC6: the default threshold 14 flipped to 0 (the nudge fires below it)" '_FU_NUDGE_DAYS_DEFAULT=14' '_FU_NUDGE_DAYS_DEFAULT=0' fu_s6 "0|"
fu_is "FU6 LOOMWRIGHT_FOLLOWUP_NUDGE_DAYS=5 at 10d ⇒ the line; a non-integer reads as 14 (silent at 10d, fires at 20d)" \
  "$(fu_nudge "$H" 10 5) $(fu_nudge "$H" 10 abc) $(fu_nudge "$H" 20 -3)" \
  "0|automate: 3 follow-up drafts, oldest 10d — /backlog --state follow_up, then followup-bundle 0| 0|$FU_LINE20"
# an undecided draft is no follow-up: it neither counts nor ages the nudge
fu_repo t6u "[$FU_F1]"; printf 'SUPERVISOR_RESULT:\n  schema_version: 1\n  status: completed\n  heal_iterations: 1\n  heal_decision: PASS\n  heal_dismissed: [%s, %s]\n' "$FU_F1" "$FU_F2" > "$AD/$FU_RID.supervisor-result.md"
bash "$H" dismissed-drafts "$RF" "$FU_ITEM" "$FU_PR" >/dev/null 2>&1
FU_NOW="$(date -u +%s)"   # after t6u's decide, so its row is no later than the clock reference
fu_is "FU6 an undecided draft beside one follow-up is not counted" "$(fu_nudge "$H" 20)" \
  "0|automate: 1 follow-up drafts, oldest 20d — /backlog --state follow_up, then followup-bundle"
mkdir -p "$FU/t6e/.supervisor/requirements/proposed" "$FU/t6n/.supervisor/requirements"
fu_is "FU6 no drafts, or no proposed/ dir, or no .supervisor at all ⇒ nothing, exit 0" \
  "$(fu_nudge "$H" 99 '' "$FU/t6e") $(fu_nudge "$H" 99 '' "$FU/t6n") $(fu_nudge "$H" 99 '' "$FU/bin")" "0| 0| 0|"
if [ "$(id -u)" = 0 ]; then
  echo "  SKIP: FU6 unreadable proposed/ — running as root, chmod 000 does not deny reads"
else
  chmod 000 "$FU/t6/.supervisor/requirements/proposed"
  fu_is "FU6 an unreadable proposed/ ⇒ nothing, exit 0" "$(fu_nudge "$H" 99 '' "$FU/t6")" "0|"
  chmod 755 "$FU/t6/.supervisor/requirements/proposed"
fi
fu_is "FU6 usage errors still exit 0 with nothing on stdout" \
  "$(bash "$H" followup-nudge --bogus 2>/dev/null; echo "rc=$?") $(bash "$H" followup-nudge --root 2>/dev/null; echo "rc=$?")" "rc=0 rc=0"
fu_is "FU6 the nudge and the board read the same drafts (one age helper): backlog --state follow_up lists 3, aged 20d" \
  "$(LOOMWRIGHT_FOLLOWUP_NOW="$((FU_NOW + 20 * 86400))" LOOMWRIGHT_GH_BIN="$FU/bin/gh" LOOMWRIGHT_LANE_STATUS_BIN="$FU/bin/lanes" bash "$H" backlog --json --offline --state follow_up --root "$FU/t6" 2>/dev/null | jq -r '"\(.items | length) \([.items[].evidence | test("^follow-up 20d — run ")] | all)"')" "3 true"
rm -rf "$FU"
