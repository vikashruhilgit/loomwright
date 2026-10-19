# =============================================================================
echo "== D. resume reconcile (run-file BELIEF vs gh TRUTH) =="

WD="$(mktemp -d)"; BIN="$WD/bin"; make_stub_bin "$BIN"
export GH_STUB_DIR="$WD/ghstub"; mkdir -p "$GH_STUB_DIR"

# D0. resume-glob finds incomplete runs only.
AUT="$WD/automate"; mkdir -p "$AUT"
# Both fixtures carry the real run-file H1 (`# Automate Run:`, automate-followups/03)
# so is_run_file admits them and r2 is excluded by is_done — NOT by the shape
# check — keeping "r2 done excluded" a test of is_done. Expected output unchanged.
printf '# Automate Run: r1\n## Status: running\n' > "$AUT/r1.md"
printf '# Automate Run: r2\n## Status: done\n'    > "$AUT/r2.md"
run_h bash "$H" resume-glob "$AUT"
if [ "$RUN_OUT" = "$AUT/r1.md" ]; then ok "resume-glob: only not-done runs (r1; r2 done excluded)"; else no "resume-glob wrong:\n$RUN_OUT"; fi
# D0f. resume-glob --finalize (automate-followups/32 Part B; SKILL §4 step 1): an
#      ineligible run (not paused) is listed exactly as the plain form lists it,
#      untouched, with nothing on stderr; the flag is accepted before the dir too.
#      The finalize legs themselves (git, trail, lock) live in test-automate-trail.sh §F.
r1_sum="$(cksum < "$AUT/r1.md")"
fz_out="$(bash "$H" resume-glob "$AUT" --finalize 2>"$WD/fz.err")"; fz_rc=$?
fz_out2="$(bash "$H" resume-glob --finalize "$AUT" 2>>"$WD/fz.err")"
if [ "$fz_rc" -eq 0 ] && [ "$fz_out" = "$AUT/r1.md" ] && [ "$fz_out2" = "$fz_out" ] && [ ! -s "$WD/fz.err" ] && [ "$r1_sum" = "$(cksum < "$AUT/r1.md")" ]; then
  ok "resume-glob --finalize: an ineligible run is listed as the plain form lists it, byte-untouched, stderr silent"
else
  no "resume-glob --finalize ineligible leg wrong (rc=$fz_rc): '$fz_out' / '$fz_out2' / err: $(cat "$WD/fz.err")"
fi

# D0b. resume-glob lists only RUN FILES (is_run_file, automate-followups/03).
#      The §6 steps 2-3 per-run result sidecars share the directory and `.md`
#      extension but carry no `# Automate Run:` title and no `## Status:` line —
#      before is_run_file, is_done alone listed them as incomplete runs (and >1
#      "incomplete run" fails RESUME closed as resume_ambiguous).
SC="$WD/sidecars"; mkdir -p "$SC"
printf '# Automate Run: sc\n## Status: done\n## Queue\n' > "$SC/automate-x.md"
printf '## REVIEW_HEAL_RESULT\n- schema_version: 1\n- decision: READY\n' > "$SC/automate-x.review-heal-result.md"
printf '## SUPERVISOR_RESULT\n- schema_version: 1\n- status: completed\n- rubric_score: 5/5\n' > "$SC/automate-x.supervisor-result.md"
# AC1: done run + both sidecars ⇒ nothing listed, exit 0.
run_h bash "$H" resume-glob "$SC"
if [ "$RUN_RC" -eq 0 ] && [ -z "$RUN_OUT" ]; then
  ok "resume-glob: done run + both result sidecars ⇒ prints nothing, exit 0 (sidecars are not run files)"
else
  no "resume-glob sidecar exclusion wrong (rc=$RUN_RC):\n$RUN_OUT"
fi
# AC2: same fixture, run stamped paused ⇒ exactly the run file.
printf '# Automate Run: sc\n## Status: paused\n## Queue\n' > "$SC/automate-x.md"
run_h bash "$H" resume-glob "$SC"
if [ "$RUN_OUT" = "$SC/automate-x.md" ]; then
  ok "resume-glob: paused run + both result sidecars ⇒ exactly the run file"
else
  no "resume-glob paused-run-with-sidecars wrong:\n$RUN_OUT"
fi
# AC4 (decision 2): the title line is matched anywhere, not only on line 1 — a
# leading blank line must never hide a real incomplete run from RESUME.
BL="$WD/blankfirst"; mkdir -p "$BL"
printf '\n# Automate Run: late-title\n## Status: running\n' > "$BL/late.md"
run_h bash "$H" resume-glob "$BL"
if [ "$RUN_OUT" = "$BL/late.md" ]; then
  ok "resume-glob: a run file whose '# Automate Run:' title follows a blank line is STILL listed"
else
  no "resume-glob blank-first-line run wrong:\n$RUN_OUT"
fi
# AC3 mutation control: a sed-built mutant whose is_run_file is forced to
# `return 0` must leak BOTH sidecars back into the AC1 fixture's output — proves
# the resume_glob call is load-bearing (not defined-but-uncalled, not called
# after echo). Gated like the harness-port/02 is_not_ready mutant: non-empty,
# differs from the original, `bash -n` clean, override actually injected.
printf '# Automate Run: sc\n## Status: done\n## Queue\n' > "$SC/automate-x.md"
MUT="$(mktemp -d)"
# Re-targeted at the tolerant body (automate-followups/19: `env LC_ALL=C grep -qE "$RUN_TITLE_ERE"`).
sed 's/^is_run_file() { env LC_ALL=C grep -qE .*$/is_run_file() { return 0; }/' "$H" > "$MUT/automate-helpers.sh"
if [ -s "$MUT/automate-helpers.sh" ] && ! cmp -s "$H" "$MUT/automate-helpers.sh" && bash -n "$MUT/automate-helpers.sh" 2>/dev/null \
   && grep -qF 'is_run_file() { return 0; }' "$MUT/automate-helpers.sh"; then
  MUT_RG_OUT="$(bash "$MUT/automate-helpers.sh" resume-glob "$SC" 2>/dev/null)"
  EXPECTED_RG_MUT="$SC/automate-x.review-heal-result.md
$SC/automate-x.supervisor-result.md"
  if [ "$MUT_RG_OUT" = "$EXPECTED_RG_MUT" ]; then
    ok "mutation control: is_run_file forced to always-true ⇒ exactly the two sidecars leak into resume-glob (sorted) — the shape check is load-bearing"
  else
    no "is_run_file mutation control did NOT discriminate (out='$MUT_RG_OUT' expected='$EXPECTED_RG_MUT')"
  fi
  CTRL_RG_OUT="$(bash "$H" resume-glob "$SC" 2>/dev/null)"
  if [ -z "$CTRL_RG_OUT" ]; then
    ok "is_run_file mutation positive control: the unmutated script, same fixture, still prints nothing"
  else
    no "is_run_file mutation positive control failed (out='$CTRL_RG_OUT') — cannot trust the mutation result without this"
  fi
else
  no "is_run_file mutation control not gated (mutant empty, identical to original, bash -n failed, or the is_run_file override was not injected)"
fi
rm -rf "$MUT"

# D0b (automate-followups/19) — TOLERATED title forms. is_run_file matches RUN_TITLE_ERE: an
# optional UTF-8 BOM, 0-3 leading spaces, any case, flexible whitespace, exactly one `#`. One
# fixture dir per form so each is asserted separately. Title lines go through printf %b; the BOM
# is the octal byte string \0357\0273\0277 (BSD tools have no `\x`).
TT="$WD/tolerant"; mkdir -p "$TT"
tt_form() {  # <dir> <title line (printf %b)> [status]
  mkdir -p "$1"
  { printf '%b\n' "$2"; printf '## Status: %s\n## Queue\n' "${3:-paused}"; } > "$1/run.md"
}
TT_FORMS="bom extra-space no-space inner-spaces lower-case indent3"
tt_form "$TT/bom"          '\0357\0273\0277# Automate Run: x'
tt_form "$TT/extra-space"  '#  Automate Run: x'
tt_form "$TT/no-space"     '#Automate Run: x'
tt_form "$TT/inner-spaces" '# Automate   Run : x'
tt_form "$TT/lower-case"   '# automate run: x'
tt_form "$TT/indent3"      '   # Automate Run: x'
tt_form "$TT/exact"        '# Automate Run: x'
if [ "$(head -c 3 "$TT/bom/run.md" | od -An -tx1 | tr -d ' \n')" = "efbbbf" ]; then
  ok "precondition: the BOM fixture's first three bytes are EF BB BF"
else
  no "precondition: the BOM fixture does not start with EF BB BF — the BOM leg would be vacuous"
fi
# AC1: each tolerated form is listed.
for form in $TT_FORMS; do
  run_h bash "$H" resume-glob "$TT/$form"
  if [ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "$TT/$form/run.md" ]; then
    ok "resume-glob: a paused run file with the tolerated '$form' title form is listed"
  else
    no "resume-glob: tolerated '$form' title form NOT listed (rc=$RUN_RC out='$RUN_OUT')"
  fi
done
# AC2: H2, 4-space indent (indented code block), tab indent, and the two sidecars beside a done run
# ⇒ nothing listed, exit 0. Each negative is stamped `paused`, so only the shape check excludes it.
NEG="$WD/tolerant-neg"; mkdir -p "$NEG"
printf '# Automate Run: neg\n## Status: done\n## Queue\n' > "$NEG/automate-x.md"
printf '## Automate Run: x\n## Status: paused\n## Queue\n'     > "$NEG/h2.md"
printf '    # Automate Run: x\n## Status: paused\n## Queue\n' > "$NEG/indent4.md"
printf '\t# Automate Run: x\n## Status: paused\n## Queue\n'   > "$NEG/tab.md"
printf '## REVIEW_HEAL_RESULT\n- schema_version: 1\n- decision: READY\n' > "$NEG/automate-x.review-heal-result.md"
printf '## SUPERVISOR_RESULT\n- schema_version: 1\n- status: completed\n' > "$NEG/automate-x.supervisor-result.md"
run_h bash "$H" resume-glob "$NEG"
if [ "$RUN_RC" -eq 0 ] && [ -z "$RUN_OUT" ]; then
  ok "resume-glob: H2 / 4-space-indented / tab-indented title lines and both sidecars are NOT run files ⇒ prints nothing, exit 0"
else
  no "resume-glob tolerant negatives leaked (rc=$RUN_RC):\n$RUN_OUT"
fi
# AC3: the write validators share the predicate — a COMPLETE run file whose title is a tolerated
# non-exact form is accepted by progress-append, queue-checkoff and runfile-write (exit 0).
for form in bom lower-case; do
  case "$form" in bom) tline='\0357\0273\0277# Automate Run: w' ;; *) tline='# automate run: w' ;; esac
  TW="$WD/tolerant-write-$form"; mkdir -p "$TW"; RFW="$TW/run.md"
  { printf '%b\n' "$tline"; printf '## Status: running\n## Queue\n- [ ] q/a.md\n- [ ] q/b.md\n## Progress\n- t0 picked\n'; } > "$RFW"
  run_h bash "$H" progress-append "$RFW" "t1 tolerant"
  if [ "$RUN_RC" -eq 0 ] && grep -qxF -- '- t1 tolerant' "$RFW"; then
    ok "progress-append: accepts a run file with the tolerated '$form' title (exit 0, line appended)"
  else
    no "progress-append refused the tolerated '$form' title (rc=$RUN_RC)"
  fi
  run_h bash "$H" queue-checkoff "$RFW" "q/a.md"
  if [ "$RUN_RC" -eq 0 ] && grep -qxF -- '- [x] q/a.md' "$RFW"; then
    ok "queue-checkoff: accepts a run file with the tolerated '$form' title (exit 0, box flipped)"
  else
    no "queue-checkoff refused the tolerated '$form' title (rc=$RUN_RC)"
  fi
  cp "$RFW" "$TW/staged.in"
  RUN_OUT="$(bash "$H" runfile-write "$RFW" < "$TW/staged.in" 2>/dev/null)"; RUN_RC=$?
  if [ "$RUN_RC" -eq 0 ] && cmp -s "$RFW" "$TW/staged.in"; then
    ok "runfile-write: accepts the same content with the tolerated '$form' title on stdin (exit 0, installed)"
  else
    no "runfile-write refused the tolerated '$form' title (rc=$RUN_RC)"
  fi
done
# AC5 mutation control 1 — "is_run_file exact-match mutant": RUN_TITLE_ERE restored to the old exact
# `^# Automate Run:`. Every tolerant fixture must then go UNLISTED (the tolerance is what lists it),
# while the exact-form fixture stays listed (the mutant still works — not a dead helper). Gated:
# non-empty, differs, `bash -n` clean, override line present.
MUT="$(mktemp -d)"
sed "s|^RUN_TITLE_ERE=.*\$|RUN_TITLE_ERE='^# Automate Run:'|" "$H" > "$MUT/automate-helpers.sh"
if [ -s "$MUT/automate-helpers.sh" ] && ! cmp -s "$H" "$MUT/automate-helpers.sh" && bash -n "$MUT/automate-helpers.sh" 2>/dev/null \
   && grep -qxF "RUN_TITLE_ERE='^# Automate Run:'" "$MUT/automate-helpers.sh"; then
  for form in $TT_FORMS; do
    MUT_OUT="$(bash "$MUT/automate-helpers.sh" resume-glob "$TT/$form" 2>/dev/null)"
    if [ -z "$MUT_OUT" ]; then
      ok "is_run_file exact-match mutant: the '$form' fixture is NOT listed — the new tolerance is what lists it"
    else
      no "is_run_file exact-match mutant still lists the '$form' fixture ('$MUT_OUT') — the tolerance leg is not load-bearing"
    fi
  done
  MUT_OUT="$(bash "$MUT/automate-helpers.sh" resume-glob "$TT/exact" 2>/dev/null)"
  if [ "$MUT_OUT" = "$TT/exact/run.md" ]; then
    ok "is_run_file exact-match mutant positive control: the exact '# Automate Run:' fixture is still listed"
  else
    no "is_run_file exact-match mutant positive control failed (out='$MUT_OUT') — the mutant is broken, not discriminating"
  fi
else
  no "is_run_file exact-match mutant not gated (mutant empty, identical to original, bash -n failed, or the exact RUN_TITLE_ERE override was not injected)"
fi
rm -rf "$MUT"
# AC5 mutation control 2 — "is_run_file indent-cap mutant": the 0-3-space cap lifted to any leading
# whitespace. The AC2 negative fixture must then LIST the 4-space- and tab-indented files (proving
# the cap is what excludes them); the unmutated helper on the same fixture prints nothing (AC2 leg).
MUT="$(mktemp -d)"
sed '/^RUN_TITLE_ERE=/s/ {0,3}#/[[:space:]]*#/' "$H" > "$MUT/automate-helpers.sh"
MUT_LINE="$(grep -E '^RUN_TITLE_ERE=' "$MUT/automate-helpers.sh" 2>/dev/null)"
if [ -s "$MUT/automate-helpers.sh" ] && ! cmp -s "$H" "$MUT/automate-helpers.sh" && bash -n "$MUT/automate-helpers.sh" 2>/dev/null \
   && case "$MUT_LINE" in *'?[[:space:]]*#[[:blank:]]*[Aa]'*) true ;; *) false ;; esac \
   && case "$MUT_LINE" in *' {0,3}'*) false ;; *) true ;; esac; then
  MUT_OUT="$(bash "$MUT/automate-helpers.sh" resume-glob "$NEG" 2>/dev/null)"
  EXPECTED_INDENT_MUT="$NEG/indent4.md
$NEG/tab.md"
  if [ "$MUT_OUT" = "$EXPECTED_INDENT_MUT" ]; then
    ok "is_run_file indent-cap mutant: lifting the 0-3-space cap lists exactly the 4-space- and tab-indented negatives — the cap is load-bearing"
  else
    no "is_run_file indent-cap mutant did NOT discriminate (out='$MUT_OUT' expected='$EXPECTED_INDENT_MUT')"
  fi
else
  no "is_run_file indent-cap mutant not gated (mutant empty, identical to original, bash -n failed, or the lifted-cap override was not injected)"
fi
rm -rf "$MUT"

# D1. belief says pending but gh says MERGED ⇒ corrected to merged (check it off).
printf '{"state":"MERGED","mergedAt":"2026-06-20T00:00:00Z"}\n' > "$GH_STUB_DIR/pr-view.json"
rm -f "$GH_STUB_DIR/pr-view-fail"
run_h env PATH="$BIN:$PATH" bash "$H" reconcile-item "$PR" "awaiting_merge"
if [ "$RUN_OUT" = "merged" ]; then ok "reconcile: belief=pending, gh=MERGED ⇒ merged"; else no "reconcile merged wrong ($RUN_OUT)"; fi

# D2. belief says checked but gh says OPEN/unmerged ⇒ awaiting_merge (premature check-off corrected).
printf '{"state":"OPEN","mergedAt":null}\n' > "$GH_STUB_DIR/pr-view.json"
run_h env PATH="$BIN:$PATH" bash "$H" reconcile-item "$PR" "merged"
if [ "$RUN_OUT" = "awaiting_merge" ]; then ok "reconcile: belief=merged, gh=OPEN ⇒ awaiting_merge"; else no "reconcile open wrong ($RUN_OUT)"; fi

# D3. gh unreadable ⇒ fail closed to awaiting_merge (never assume merged).
touch "$GH_STUB_DIR/pr-view-fail"
run_h env PATH="$BIN:$PATH" bash "$H" reconcile-item "$PR" "merged"
if [ "$RUN_OUT" = "awaiting_merge" ]; then ok "reconcile: gh unreadable ⇒ fail closed (awaiting_merge)"; else no "reconcile unreadable wrong ($RUN_OUT)"; fi
rm -f "$GH_STUB_DIR/pr-view-fail"

# D4. belief checked but gh says CLOSED-unmerged ⇒ gone (neither merged nor live; §4 human-resolve).
printf '{"state":"CLOSED","mergedAt":null}\n' > "$GH_STUB_DIR/pr-view.json"
run_h env PATH="$BIN:$PATH" bash "$H" reconcile-item "$PR" "merged"
if [ "$RUN_OUT" = "gone" ]; then ok "reconcile: gh=CLOSED-unmerged ⇒ gone"; else no "reconcile gone wrong ($RUN_OUT)"; fi

unset GH_STUB_DIR
rm -rf "$WD"

