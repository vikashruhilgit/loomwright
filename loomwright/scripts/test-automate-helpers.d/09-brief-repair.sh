# =============================================================================
echo "== G. brief-repair (fail-SAFE, evidence-positive engine seam; ONE mover) =="

GK=".supervisor/requirements/r/03.md"
GU="https://github.com/o/r/pull/7"
# NEW (self-resolving) ctx shape — the 6 allowed keys only. `review_heal_result_path`
# points at a nonexistent file so gate-eval PARKs deterministically at the cond-1
# cross-check (`PARK: review_heal_result_unreadable`) WITHOUT depending on any
# gh/classify-risk.sh stub behavior — this ctx is used only as a STRUCTURAL control
# (gate.before == gate.after), never asserted against a specific PARK reason here.
PARK_CTX='{"drain_result":"READY","termination_reason":"converged","ready_sha":"a","trust_unprotected":false,"review_heal_result_path":"/no/such/review-heal-result.md","supervisor_result_path":"/no/such/supervisor-result.md"}'

# g_repo — a fixture repo: run file (## Status: paused, one - [ ] Queue item, a
# ## Current line), a PARK gate-eval ctx, and the stranded brief b.md whose
# pointer is $GK (requirement file ABSENT — the worktree shape). Prints the dir.
g_repo() {
  local r; r="$(mktemp -d)"
  mkdir -p "$r/.supervisor/jobs/in-progress" "$r/.supervisor/jobs/done" "$r/.supervisor/automate" "$r/.supervisor/requirements/r"
  printf '# run\n## Status: paused\n## Queue\n- [ ] %s\n## Current\n- item: %s | status: awaiting_merge | pr: %s\n## Progress\n' "$GK" "$GK" "$GU" > "$r/.supervisor/automate/run.md"
  printf '%s' "$PARK_CTX" > "$r/ctx.json"
  printf '# b\n\n## Environment\n- **Source requirement:** %s\n' "$GK" > "$r/.supervisor/jobs/in-progress/b.md"
  printf '%s' "$r"
}
# g_stub <dir> — fresh stub gh + GH_STUB_DIR for that fixture (MERGED by default).
g_stub() {
  make_stub_bin "$1/bin"; mkdir -p "$1/ghstub"
  printf '{"state":"MERGED","mergedAt":"2026-09-11T00:00:00Z"}\n' > "$1/ghstub/pr-view.json"
}
# g_run <dir> <helper> <item> <url> — run brief-repair FROM the fixture dir with
# the stub gh on PATH; sets RUN_OUT / RUN_RC.
g_run() {
  RUN_OUT="$(cd "$1" && GH_STUB_DIR="$1/ghstub" PATH="$1/bin:$PATH" bash "$2" brief-repair "$3" "$4" 2>/dev/null)"; RUN_RC=$?
}
# gate_snapshot <dir> — gate-eval's decision on the PARK ctx (STRUCTURAL control,
# see G6). Prints it.
gate_snapshot() { (cd "$1" && GH_STUB_DIR="$1/ghstub" PATH="$1/bin:$PATH" bash "$H" gate-eval "$GU" "$1/ctx.json" 2>/dev/null); }

# G1. AC-1 helper-level: MERGED stub ⇒ brief moved, ONE ## Outcome with the url and
#     the engine sentence, stdout one `repaired` line, rc 0.
R="$(g_repo)"; g_stub "$R"
g_run "$R" "$H" "$GK" "$GU"
DONE="$R/.supervisor/jobs/done/b.md"
if [ "$RUN_RC" -eq 0 ] && [ -f "$DONE" ] && [ ! -e "$R/.supervisor/jobs/in-progress/b.md" ] \
   && [ "$(grep -c '^## Outcome' "$DONE")" = "1" ] \
   && grep -qF -- "- **PR:** $GU" "$DONE" && grep -qF 'automate engine supplied merge evidence' "$DONE" \
   && [ "$(printf '%s\n' "$RUN_OUT" | wc -l | tr -d ' ')" = "1" ]; then
  case "$RUN_OUT" in "brief-repair: repaired "*) ok "G1 AC-1: MERGED ⇒ brief moved to done/, one ## Outcome with PR + engine sentence, one 'repaired' line, rc 0" ;; *) no "G1 stdout not a repaired line: $RUN_OUT" ;; esac
else
  no "G1 AC-1 wrong (rc=$RUN_RC out='$RUN_OUT' done=$([ -f "$DONE" ] && echo y || echo n))"
fi
[ ! -f "$R/ghstub/merge.log" ] && ok "G1b no gh pr merge was issued" || no "G1b merge.log exists — a second merge executor"
rm -rf "$R"

# G2. AC-2 safe-mode seam: reconcile-item returns merged FIRST, then brief-repair.
R="$(g_repo)"; g_stub "$R"
rec="$(cd "$R" && GH_STUB_DIR="$R/ghstub" PATH="$R/bin:$PATH" bash "$H" reconcile-item "$GU" awaiting_merge 2>/dev/null)"
g_run "$R" "$H" "$GK" "$GU"
if [ "$rec" = "merged" ] && [ -f "$R/.supervisor/jobs/done/b.md" ] && grep -qF -- "- **PR:** $GU" "$R/.supervisor/jobs/done/b.md"; then
  ok "G2 AC-2: reconcile-item ⇒ merged, then brief-repair repairs exactly as AC-1"
else
  no "G2 AC-2 wrong (rec='$rec' out='$RUN_OUT')"
fi
rm -rf "$R"

# G3. AC-3 helper-level: enq.md (the item) + other.md (stranded_closed decoy) ⇒ only enq moves.
R="$(g_repo)"; g_stub "$R"
mv "$R/.supervisor/jobs/in-progress/b.md" "$R/.supervisor/jobs/in-progress/enq.md"
printf '# other\n\n- **Source requirement:** .supervisor/requirements/r/09.md\n' > "$R/.supervisor/jobs/in-progress/other.md"
printf '# r\n\n## Status: done\n' > "$R/.supervisor/requirements/r/09.md"
cp "$R/.supervisor/jobs/in-progress/other.md" "$R/other.before"
g_run "$R" "$H" "$GK" "$GU"
if [ -f "$R/.supervisor/jobs/done/enq.md" ] && [ -f "$R/.supervisor/jobs/in-progress/other.md" ] && cmp -s "$R/other.before" "$R/.supervisor/jobs/in-progress/other.md"; then
  ok "G3 AC-3: enq.md moved; stranded_closed decoy other.md cmp-identical and still in-progress"
else
  no "G3 AC-3 wrong (out='$RUN_OUT')"
fi
rm -rf "$R"

# G4. AC-8 idempotent: second identical call ⇒ dest cmp-identical, one ## Outcome, source absent.
R="$(g_repo)"; g_stub "$R"
g_run "$R" "$H" "$GK" "$GU"; rc1=$RUN_RC
cp "$R/.supervisor/jobs/done/b.md" "$R/done.after1"
g_run "$R" "$H" "$GK" "$GU"
if [ "$rc1" -eq 0 ] && [ "$RUN_RC" -eq 0 ] && cmp -s "$R/done.after1" "$R/.supervisor/jobs/done/b.md" \
   && [ "$(grep -c '^## Outcome' "$R/.supervisor/jobs/done/b.md")" = "1" ] && [ ! -e "$R/.supervisor/jobs/in-progress/b.md" ] \
   && [ "$RUN_OUT" = "brief-repair: skipped — no in-progress brief matches $GK" ]; then
  ok "G4 AC-8: second call ⇒ 'skipped — no in-progress brief matches', dest unchanged, one ## Outcome"
else
  no "G4 AC-8 wrong (rc=$rc1/$RUN_RC out='$RUN_OUT')"
fi
rm -rf "$R"

# G5. AC-6 never repairs on absence: OPEN / CLOSED ⇒ skipped, brief stays, and the
#     reconciler is NOT invoked (a copied helper whose sibling reconcile-jobs.sh is
#     a marker-writing stub).
for st in OPEN CLOSED; do
  R="$(g_repo)"; g_stub "$R"
  printf '{"state":"%s","mergedAt":null}\n' "$st" > "$R/ghstub/pr-view.json"
  HB="$R/helper"; mkdir -p "$HB"; cp "$H" "$HB/automate-helpers.sh"
  printf '#!/usr/bin/env bash\ntouch "%s/recon-called"\nexit 0\n' "$R" > "$HB/reconcile-jobs.sh"; chmod +x "$HB/reconcile-jobs.sh"
  g_run "$R" "$HB/automate-helpers.sh" "$GK" "$GU"
  if [ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "brief-repair: skipped — PR not merged (state=$st)" ] \
     && [ -f "$R/.supervisor/jobs/in-progress/b.md" ] && ! grep -q '^## Outcome' "$R/.supervisor/jobs/in-progress/b.md" \
     && [ ! -e "$R/recon-called" ]; then
    ok "G5 AC-6: state=$st ⇒ 'skipped — PR not merged (state=$st)', brief untouched, reconciler NOT invoked"
  else
    no "G5 AC-6 $st wrong (rc=$RUN_RC out='$RUN_OUT' recon-called=$([ -e "$R/recon-called" ] && echo y || echo n))"
  fi
  rm -rf "$R"
done

# G6. AC-5 fail-safe — TEN separate groups. Each asserts: run file cmp-identical,
#     ## Status line unchanged, gate-eval PARK decision unchanged before/after
#     (STRUCTURAL control: gate-eval is a pure function of ctx.json, which the helper
#     never reads — this proves the helper touched neither ctx.json nor the stub
#     state; it is NOT behavioural coverage of the gate), merge.log absent, the
#     brief(s) still in in-progress/, exactly one `skipped — <reason>` line, rc 0.
g6_check() {  # g6_check <label> <dir> <expected-reason-prefix> <brief-names...>
  local label="$1" d="$2" want="$3"; shift 3
  local okk=1 why="" b
  cmp -s "$d/run.before" "$d/.supervisor/automate/run.md" || { okk=0; why="$why run-file-changed"; }
  [ "$(grep '^## Status' "$d/.supervisor/automate/run.md")" = "## Status: paused" ] || { okk=0; why="$why status-changed"; }
  [ "$(cat "$d/gate.before")" = "$(gate_snapshot "$d")" ] || { okk=0; why="$why gate-changed"; }
  [ ! -f "$d/ghstub/merge.log" ] || { okk=0; why="$why merge-issued"; }
  for b in "$@"; do [ -f "$d/.supervisor/jobs/in-progress/$b" ] || { okk=0; why="$why $b-moved"; }; done
  [ "$RUN_RC" -eq 0 ] || { okk=0; why="$why rc=$RUN_RC"; }
  [ "$(printf '%s\n' "$RUN_OUT" | wc -l | tr -d ' ')" = "1" ] || { okk=0; why="$why not-one-line"; }
  case "$RUN_OUT" in "brief-repair: skipped — $want"*) ;; *) okk=0; why="$why reason='$RUN_OUT'" ;; esac
  if [ "$okk" -eq 1 ]; then ok "G6 AC-5 $label ⇒ 'skipped — $want', run file/Status/gate/merge.log/brief all unchanged, rc 0"; else no "G6 AC-5 $label wrong:$why"; fi
}
g6_prep() {  # snapshot run file + gate decision
  cp "$1/.supervisor/automate/run.md" "$1/run.before"; gate_snapshot "$1" > "$1/gate.before"
  [ -s "$1/gate.before" ] || no "G6 (control) gate-eval produced no decision on the PARK ctx"
}
# (i) gh binary absent.
R="$(g_repo)"; g_stub "$R"; g6_prep "$R"
RUN_OUT="$(cd "$R" && LOOMWRIGHT_GH_BIN=/nonexistent/gh bash "$H" brief-repair "$GK" "$GU" 2>/dev/null)"; RUN_RC=$?
g6_check "(i) gh absent" "$R" "gh unavailable" b.md; rm -rf "$R"
# (ii) gh pr view exits 1.
R="$(g_repo)"; g_stub "$R"; touch "$R/ghstub/pr-view-fail"; g6_prep "$R"
g_run "$R" "$H" "$GK" "$GU"; g6_check "(ii) pr view fails" "$R" "gh pr view failed" b.md; rm -rf "$R"
# (iii) gh prints non-JSON.
R="$(g_repo)"; g_stub "$R"; echo 'not json' > "$R/ghstub/pr-view.json"; g6_prep "$R"
g_run "$R" "$H" "$GK" "$GU"; g6_check "(iii) unparseable output" "$R" "gh output unparseable" b.md; rm -rf "$R"
# (iv) brief unreadable (premise-probed: chmod 000 must actually deny reads here).
R="$(g_repo)"; g_stub "$R"; chmod 000 "$R/.supervisor/jobs/in-progress/b.md"
if [ -r "$R/.supervisor/jobs/in-progress/b.md" ]; then
  echo "  skipped: chmod 000 does not deny reads here"
else
  g6_prep "$R"; g_run "$R" "$H" "$GK" "$GU"; g6_check "(iv) brief unreadable" "$R" "no in-progress brief matches" b.md
fi
chmod 644 "$R/.supervisor/jobs/in-progress/b.md" 2>/dev/null; rm -rf "$R"
# (v) reconciler ABSENT beside a copied helper; then present but chmod 000.
R="$(g_repo)"; g_stub "$R"; HB="$R/helper"; mkdir -p "$HB"; cp "$H" "$HB/automate-helpers.sh"; g6_prep "$R"
g_run "$R" "$HB/automate-helpers.sh" "$GK" "$GU"; g6_check "(v) reconciler absent" "$R" "reconciler unavailable" b.md
cp "$HERE/reconcile-jobs.sh" "$HB/reconcile-jobs.sh"; chmod 000 "$HB/reconcile-jobs.sh"
if [ -r "$HB/reconcile-jobs.sh" ]; then
  echo "  skipped: chmod 000 does not deny reads here"
else
  g_run "$R" "$HB/automate-helpers.sh" "$GK" "$GU"; g6_check "(v) reconciler unreadable" "$R" "reconciler unavailable" b.md
fi
chmod 644 "$HB/reconcile-jobs.sh" 2>/dev/null; rm -rf "$R"
# (vi) MERGED but no in-progress brief matches the item.
R="$(g_repo)"; g_stub "$R"; g6_prep "$R"
g_run "$R" "$H" ".supervisor/requirements/r/99.md" "$GU"; g6_check "(vi) no matching brief" "$R" "no in-progress brief matches" b.md; rm -rf "$R"
# (vii) malformed item / malformed url — with a gh that would PROVE itself called.
for args in "/abs/req.md $GU" "$GK https://github.com/o/r/issues/7"; do
  R="$(g_repo)"; g_stub "$R"
  printf '#!/usr/bin/env bash\ntouch "%s/gh-called"\nexit 0\n' "$R" > "$R/bin/gh"; chmod +x "$R/bin/gh"
  g6_prep "$R"
  # shellcheck disable=SC2086
  g_run "$R" "$H" $args
  g6_check "(vii) malformed '$args'" "$R" "malformed item or pr_url" b.md
  [ ! -e "$R/gh-called" ] && ok "G6 AC-5 (vii) gh never called for '$args'" || no "G6 AC-5 (vii) gh WAS called for junk '$args'"
  rm -rf "$R"
done
# (viii) AMBIGUOUS: two in-progress briefs with the same key ⇒ neither moves.
R="$(g_repo)"; g_stub "$R"
printf '# b2\n\n- **Source requirement:** %s\n' "$GK" > "$R/.supervisor/jobs/in-progress/b2.md"
cp "$R/.supervisor/jobs/in-progress/b.md" "$R/b.before"; cp "$R/.supervisor/jobs/in-progress/b2.md" "$R/b2.before"
g6_prep "$R"; g_run "$R" "$H" "$GK" "$GU"
g6_check "(viii) ambiguous" "$R" "ambiguous match (2 briefs point at $GK)" b.md b2.md
cmp -s "$R/b.before" "$R/.supervisor/jobs/in-progress/b.md" && cmp -s "$R/b2.before" "$R/.supervisor/jobs/in-progress/b2.md" \
  && ok "G6 AC-5 (viii) both same-key briefs cmp-identical" || no "G6 AC-5 (viii) a same-key brief changed"
rm -rf "$R"
# (ix) RECONCILER REFUSED: the key matches (MERGED stub, one brief) but a colliding
#      .supervisor/jobs/done/b.md already exists, so repair() refuses and the row
#      comes back `stranded_merged` with the engine prefix + url and no `repaired`
#      row — the helper's refused=1 branch, the one reason nothing else here hits.
R="$(g_repo)"; g_stub "$R"
printf '# an earlier b\n' > "$R/.supervisor/jobs/done/b.md"
cp "$R/.supervisor/jobs/in-progress/b.md" "$R/b.before"; cp "$R/.supervisor/jobs/done/b.md" "$R/done.before"
g6_prep "$R"; g_run "$R" "$H" "$GK" "$GU"
g6_check "(ix) reconciler refused (done/ collision)" "$R" "reconciler refused the move" b.md
cmp -s "$R/b.before" "$R/.supervisor/jobs/in-progress/b.md" && cmp -s "$R/done.before" "$R/.supervisor/jobs/done/b.md" \
  && ok "G6 AC-5 (ix) in-progress brief and the colliding done/ file both cmp-identical" || no "G6 AC-5 (ix) a brief changed under a refused move"
rm -rf "$R"
# (x) MISSING ARGUMENT: one arg ⇒ the guard fires BEFORE the forge read. The
#     stub dir carries NO pr-view.json, so an asked `gh pr view` surfaces as
#     'gh output unparseable' (the stub cats nothing and exits 0 — probed, not
#     assumed) — the missing-argument reason proves gh was never asked.
R="$(g_repo)"; g_stub "$R"; rm -f "$R/ghstub/pr-view.json"; g6_prep "$R"
RUN_OUT="$(cd "$R" && GH_STUB_DIR="$R/ghstub" PATH="$R/bin:$PATH" bash "$H" brief-repair "$GK" 2>/dev/null)"; RUN_RC=$?
g6_check "(x) missing argument" "$R" "missing argument" b.md
[ "$RUN_OUT" = "brief-repair: skipped — missing argument" ] && ok "G6 AC-5 (x) reason is the missing-argument one, not 'gh output unparseable' (gh never asked)" || no "G6 AC-5 (x) unexpected reason: $RUN_OUT"
rm -rf "$R"

# G7. AC-9(a) static seam pins on the SKILL, with per-line mutants (step 5 is the per-item-loop.md
#     `5. **SYNC — run next-step.**` pointer since automate-speed/08 retired legacy-tail.md). The assertion
#     helper takes the SKILL path so the SAME code runs on the real file and on
#     each mutant.
seam_has() {  # seam_has <skill_path> <anchor> -> 0 when the line starting with <anchor> contains brief-repair
  local line; line="$(grep -F -- "$2" "$1" | head -1)"
  [ -n "$line" ] || return 1
  case "$line" in *brief-repair*) return 0 ;; *) return 1 ;; esac
}
seam_has "$SKILL_FILE" '1. **RECONCILE**' && ok "G7 AC-2 prose seam: SKILL §6 step 1 (RECONCILE) names brief-repair" || no "G7 §6 step 1 lacks brief-repair"
seam_has "$SKILL_FILE" '5. **SYNC'        && ok "G7 AC-1 prose seam: SKILL §6 step 5 (SYNC) names brief-repair"      || no "G7 §6 step 5 lacks brief-repair"
grep -q 'brief-repair' < <(grep -F -- '**PR merged?**' "$SKILL_FILE") && ok "G7 §4 step 2 'PR merged?' bullet references the repair" || no "G7 §4 'PR merged?' bullet lacks the reference"
skill_mutant() {  # skill_mutant <anchor> <out> — strip every `brief-repair` token from the anchored line only
  awk -v a="$1" 'index($0,a)==1 {gsub(/brief-repair/,"brief_removed")} {print}' "$SKILL_FILE" > "$2"
}
MW="$(mktemp -d)"
skill_mutant '5. **SYNC' "$MW/no-step5.md"; skill_mutant '1. **RECONCILE**' "$MW/no-step1.md"
for m in no-step5 no-step1; do
  [ -s "$MW/$m.md" ] && ! cmp -s "$SKILL_FILE" "$MW/$m.md" || no "G7 mutant $m not gated (empty or identical)"
done
if ! seam_has "$MW/no-step5.md" '5. **SYNC' && seam_has "$MW/no-step5.md" '1. **RECONCILE**'; then ok "G7 (mutant) token gone from step 5 only ⇒ AC-1 pin red, AC-2 pin green"; else no "G7 step-5 mutant not discriminated"; fi
if ! seam_has "$MW/no-step1.md" '1. **RECONCILE**' && seam_has "$MW/no-step1.md" '5. **SYNC'; then ok "G7 (mutant) token gone from step 1 only ⇒ AC-2 pin red, AC-1 pin green"; else no "G7 step-1 mutant not discriminated"; fi
rm -rf "$MW"

# G8. AC-9(b) helper mutant: the `bash "$recon" …` invocation removed. Post-PASS
#     rule: the mutant sits beside the REAL reconcile-jobs.sh + brief-pointer.sh
#     (the helper finds the reconciler by dirname "$0"; alone, every copy yields
#     'reconciler unavailable' whether or not the invocation was removed), and an
#     UNMUTATED copy in that exact layout must FIRST keep AC-1 green.
lay="$(mktemp -d)"; cp "$H" "$lay/automate-helpers.sh"; cp "$HERE/reconcile-jobs.sh" "$HERE/brief-pointer.sh" "$lay/"
R="$(g_repo)"; g_stub "$R"; g_run "$R" "$lay/automate-helpers.sh" "$GK" "$GU"
if [ -f "$R/.supervisor/jobs/done/b.md" ]; then
  ok "G8 (positive gate) unmutated helper copy beside the real siblings keeps AC-1 green"
  mut="$(mktemp -d)"; cp "$HERE/reconcile-jobs.sh" "$HERE/brief-pointer.sh" "$mut/"
  awk 'index($0,"rows=\"$(bash \"$recon\" --repair --porcelain --evidence")==3 {print "  rows=\"\""; next} {print}' "$H" > "$mut/automate-helpers.sh"
  if [ -s "$mut/automate-helpers.sh" ] && ! cmp -s "$H" "$mut/automate-helpers.sh" && bash -n "$mut/automate-helpers.sh" 2>/dev/null; then
    R2="$(g_repo)"; g_stub "$R2"; g_run "$R2" "$mut/automate-helpers.sh" "$GK" "$GU"
    if [ ! -e "$R2/.supervisor/jobs/done/b.md" ] && [ -f "$R2/.supervisor/jobs/in-progress/b.md" ] \
       && [ "$RUN_OUT" = "brief-repair: skipped — no in-progress brief matches $GK" ]; then
      ok "G8 (mutant) reconciler invocation removed ⇒ AC-1 red (brief NOT moved; reason is 'no in-progress brief matches', not 'reconciler unavailable')"
    else
      no "G8 mutant not discriminated (out='$RUN_OUT')"
    fi
    R3="$(g_repo)"; g_stub "$R3"; printf '{"state":"OPEN","mergedAt":null}\n' > "$R3/ghstub/pr-view.json"
    g_run "$R3" "$mut/automate-helpers.sh" "$GK" "$GU"
    [ "$RUN_OUT" = "brief-repair: skipped — PR not merged (state=OPEN)" ] && [ -f "$R3/.supervisor/jobs/in-progress/b.md" ] \
      && ok "G8 (mutant) AC-6 group stays green on the mutant (OPEN ⇒ skipped, brief untouched)" || no "G8 AC-6 went red on the mutant: $RUN_OUT"
    rm -rf "$R2" "$R3"
  else
    no "G8 helper mutant not gated (empty, identical, or bash -n failed)"
  fi
  rm -rf "$mut"
else
  no "G8 positive gate failed (out='$RUN_OUT') — mutant not run"
fi
rm -rf "$R" "$lay"

