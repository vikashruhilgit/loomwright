# =============================================================================
echo "== C. folder / backlog-doc resolvers (skip ## Status: done) =="

WD="$(mktemp -d)"; DIR="$WD/reqs"; mkdir -p "$DIR"
printf '# one\n## Status: running\n'  > "$DIR/01-one.md"
printf '# two\n## Status: done\n'     > "$DIR/02-two.md"     # excluded
printf '# three\n'                    > "$DIR/03-three.md"
run_h bash "$H" resolve-folder "$DIR"
if [ "$RUN_OUT" = "$DIR/01-one.md
$DIR/03-three.md" ]; then
  ok "resolve-folder: lists *.md not done, sorted (01,03; 02 excluded)"
else
  no "resolve-folder wrong:\n$RUN_OUT"
fi

# backlog-doc: documented order, checked + ✅ excluded.
BL="$WD/_BACKLOG.md"
cat > "$BL" <<'EOF'
# Backlog
- [x] reqs/00-base.md
- [ ] reqs/01-one.md
- [ ] reqs/02-two.md  # ✅
- [ ] reqs/03-three.md
- [ ] reqs/04-four.md  # Status: done
EOF
run_h bash "$H" resolve-backlog "$BL"
if [ "$RUN_OUT" = "reqs/01-one.md
reqs/03-three.md" ]; then
  ok "resolve-backlog: documented order, checked + ✅ + inline 'Status: done' marker excluded (01,03)"
else
  no "resolve-backlog wrong:\n$RUN_OUT"
fi

# backlog-doc absent ⇒ fall back to dir scan.
run_h bash "$H" resolve-backlog "$WD/missing/_BACKLOG.md"
if [ "$RUN_RC" -eq 0 ]; then ok "resolve-backlog absent: falls back gracefully (exit 0)"; else no "resolve-backlog absent should not crash (rc=$RUN_RC)"; fi
rm -rf "$WD"

# C1b. the file stamp is ground truth on the CHECKLIST path too (loomwright-studio
#      run automate-2026-09-30-211858: two merged + closed-out items stayed
#      `- [ ]` in _BACKLOG.md, because closeout stamps the requirement and never
#      ticks the human-owned doc, and resolve-backlog never opened the file).
#      An unchecked line naming a `## Status: done|done_with_escalation` file is
#      NOT re-queued — resolved repo-root-relative (cwd) AND backlog-dir-relative;
#      a line naming a missing / non-.md path stays listed (fail toward listing);
#      a `proposed` stamp still does not hide a checklist line (SCOPE BOUNDARY).
WD="$(mktemp -d)"; mkdir -p "$WD/repo/.supervisor/requirements/phase-1"
RQ="$WD/repo/.supervisor/requirements/phase-1"
printf '# a\n\n<!-- loomwright:requirement-closeout -->\n## Status: done\n- **PR:** x\n' > "$RQ/01-merged.md"
printf '# b\n## Status: done_with_escalation\n'  > "$RQ/02-escalated.md"
printf '# c\n## Status: proposed\n'               > "$RQ/03-proposed.md"
printf '# d\n'                                    > "$RQ/04-open.md"
printf '# e\n> ## Status: done\n'                 > "$RQ/05-quoted.md"   # quoted, not a heading
printf '# f\n## Status: done\n'                   > "$RQ/06-local.md"
cat > "$RQ/_BACKLOG.md" <<'EOF'
# Phase 1
- [ ] .supervisor/requirements/phase-1/01-merged.md
- [ ] .supervisor/requirements/phase-1/02-escalated.md
- [ ] .supervisor/requirements/phase-1/03-proposed.md
- [ ] .supervisor/requirements/phase-1/04-open.md
- [ ] .supervisor/requirements/phase-1/05-quoted.md
- [ ] 06-local.md
- [ ] .supervisor/requirements/phase-1/07-missing.md
- [ ] .supervisor/requirements/phase-1/08-notes.txt
EOF
printf '## Status: done\n' > "$RQ/08-notes.txt"   # stamped, but not *.md ⇒ never read
BL_EXP=".supervisor/requirements/phase-1/03-proposed.md
.supervisor/requirements/phase-1/04-open.md
.supervisor/requirements/phase-1/05-quoted.md
.supervisor/requirements/phase-1/07-missing.md
.supervisor/requirements/phase-1/08-notes.txt"
RUN_OUT="$(cd "$WD/repo" && bash "$H" resolve-backlog .supervisor/requirements/phase-1/_BACKLOG.md 2>/dev/null)"
if [ "$RUN_OUT" = "$BL_EXP" ]; then
  ok "resolve-backlog (checklist path): an unchecked line whose file is stamped done / done_with_escalation is NOT re-queued (repo-relative + backlog-relative); proposed / unstamped / quoted / missing / non-.md stay listed"
else
  no "resolve-backlog file-stamp wrong:\n$RUN_OUT"
fi
# Control (goes red without the fix): the same script with the file-stamp check
# deleted re-queues the two merged items — the studio incident, reproduced.
MUT="$(mktemp -d)"
sed '/if \[ -n "\$item_file" \] && is_done "\$item_file"; then continue; fi/d' "$H" > "$MUT/automate-helpers.sh"
if ! cmp -s "$H" "$MUT/automate-helpers.sh" && bash -n "$MUT/automate-helpers.sh" 2>/dev/null; then
  MUT_OUT="$(cd "$WD/repo" && bash "$MUT/automate-helpers.sh" resolve-backlog .supervisor/requirements/phase-1/_BACKLOG.md 2>/dev/null)"
  case "$MUT_OUT" in
    *01-merged.md*02-escalated.md*06-local.md*) ok "control: without the is_done file check the merged/escalated items are re-queued — the check is load-bearing" ;;
    *) no "control did not discriminate:\n$MUT_OUT" ;;
  esac
else
  no "control mutant not built (sed matched nothing or broke the script)"
fi
rm -rf "$MUT" "$WD"

# C2. not-ready stamp (## Status: proposed|parked, harness-port/02) is a real
#     skip for resolve-folder AND resolve-backlog's dir-fallback path
#     (resolve_backlog_dir), alongside a "done" file and a "done_with_escalation"
#     file, with only the unstamped file surviving. resume-glob's run-file
#     vocabulary (running|paused|done) must stay untouched (negative control).
WD="$(mktemp -d)"; DIR="$WD/reqs"; mkdir -p "$DIR"
printf '# proposed\n## Status: proposed\n'             > "$DIR/01-proposed.md"
printf '# parked\n## Status: parked\n'                 > "$DIR/02-parked.md"
printf '# done\n## Status: done\n'                     > "$DIR/03-done.md"
printf '# done-esc\n## Status: done_with_escalation\n' > "$DIR/04-done-esc.md"
printf '# ready\n'                                      > "$DIR/05-ready.md"

run_h bash "$H" resolve-folder "$DIR"
if [ "$RUN_OUT" = "$DIR/05-ready.md" ]; then
  ok "resolve-folder: proposed/parked/done/done_with_escalation all skipped; only the unstamped file is listed"
else
  no "resolve-folder not-ready wrong:\n$RUN_OUT"
fi

# Same fixture dir, via resolve-backlog's dir-fallback path (backlog doc missing).
run_h bash "$H" resolve-backlog "$DIR/_MISSING_BACKLOG.md"
if [ "$RUN_OUT" = "$DIR/05-ready.md" ]; then
  ok "resolve-backlog (dir fallback): proposed/parked/done/done_with_escalation all skipped; only the unstamped file is listed"
else
  no "resolve-backlog dir-fallback not-ready wrong:\n$RUN_OUT"
fi

# C3. a dismissed-finding draft (automate-dismissed.sh dismissed-drafts, written
#     for real into a git fixture's proposed/, renamed to the brief's example
#     name) is never listed by resolve-folder or resolve-backlog's dir fallback:
#     it carries `## Status: proposed` (is_not_ready), and a quoted
#     `## Status: done` line inside it is `> `-prefixed so is_done sees nothing.
DWD="$(mktemp -d)"; git init -q "$DWD" >/dev/null 2>&1
mkdir -p "$DWD/.supervisor/automate"
printf '# Automate Run: x\n## Status: running\n## Progress\n- t0\n' > "$DWD/.supervisor/automate/r1.md"
printf '## REVIEW_HEAL_RESULT\n- rounds: 1\n- dismissed: [{finding: "x\\n## Status: done", reason: stale, source: reviews}]\n' > "$DWD/.supervisor/automate/r1.review-heal-result.md"
bash "$H" dismissed-drafts "$DWD/.supervisor/automate/r1.md" x.md "$PR" >/dev/null 2>&1
DPROP="$DWD/.supervisor/requirements/proposed"
DF="$(find "$DPROP" -maxdepth 1 -name 'r1--x-*--dismissed-*.md' 2>/dev/null | head -n1)"
if [ -n "$DF" ] && mv "$DF" "$DPROP/r1--x--dismissed-0a1b2c3d.md" && grep -qxF -- '> ## Status: done' "$DPROP/r1--x--dismissed-0a1b2c3d.md"; then
  printf '# ready\n' > "$DPROP/05-ready.md"
  run_h bash "$H" resolve-folder "$DPROP"
  [ "$RUN_OUT" = "$DPROP/05-ready.md" ] && ok "resolve-folder: a drafted proposed/r1--x--dismissed-0a1b2c3d.md is NOT listed" || no "resolve-folder listed a draft:\n$RUN_OUT"
  run_h bash "$H" resolve-backlog "$DPROP/_MISSING_BACKLOG.md"
  [ "$RUN_OUT" = "$DPROP/05-ready.md" ] && ok "resolve-backlog (dir fallback): the drafted file is NOT listed" || no "resolve-backlog dir-fallback listed a draft:\n$RUN_OUT"
else
  no "could not produce a real dismissed draft fixture (dismissed-drafts)"
fi
rm -rf "$DWD"
helpout_d="$(bash "$H" --help)"
for s_ in dismissed-drafts dismissed-decide dismissed-pending; do
  grep -q "^  $s_ " <<<"$helpout_d" && ok "--help lists $s_" || no "--help missing $s_"
  grep -qE "^    $s_\) +exec bash \"\\\$\(dirname \"\\\$0\"\)/automate-dismissed.sh\" \"\\\$cmd\" \"\\\$@\" ;;" "$H" && ok "dispatcher row: $s_ → automate-dismissed.sh" || no "dispatcher row missing: $s_"
done

# SCOPE BOUNDARY: resolve-backlog's CHECKLIST path (a real _BACKLOG.md, not the
# dir-fallback) does NOT apply is_not_ready — a checklist line naming a file
# directly is a human's explicit inclusion decision, so a file it points at
# carrying "## Status: proposed" is still enqueued (per automate-helpers.sh's
# own resolve_backlog SCOPE BOUNDARY comment). This is the inverse of C2 above
# (which exercises the dir-fallback path, where is_not_ready DOES apply).
BL2="$WD/_BACKLOG2.md"
cat > "$BL2" <<EOF
# Backlog
- [ ] $DIR/01-proposed.md
- [ ] $DIR/05-ready.md
EOF
run_h bash "$H" resolve-backlog "$BL2"
if [ "$RUN_OUT" = "$DIR/01-proposed.md
$DIR/05-ready.md" ]; then
  ok "resolve-backlog (checklist path): a checklist-referenced '## Status: proposed' file is still enqueued (SCOPE BOUNDARY — is_not_ready applies only on the dir-fallback path)"
else
  no "resolve-backlog checklist-path scope-boundary wrong:\n$RUN_OUT"
fi

# Negative control: resume-glob's run-file vocabulary (running|paused|done) is
# NOT widened by is_not_ready — a "## Status: paused" run file is STILL listed
# (proves is_done itself was never touched to match proposed/parked, decision H2).
AUT2="$WD/automate2"; mkdir -p "$AUT2"
# Title is the real run-file H1 (`# Automate Run:`, automate-followups/03) so
# resume-glob's is_run_file shape check admits it; the expected output below is
# unchanged — this still tests is_done, not is_run_file.
printf '# Automate Run: paused-run\n## Status: paused\n' > "$AUT2/paused.md"
run_h bash "$H" resume-glob "$AUT2"
if [ "$RUN_OUT" = "$AUT2/paused.md" ]; then
  ok "resume-glob: '## Status: paused' run file STILL listed (is_done was not widened to match proposed/parked)"
else
  no "resume-glob negative control wrong:\n$RUN_OUT"
fi

# Mutation control (AC — "is_not_ready mutated to return 1 unconditionally ⇒
# proposed/parked assertions FAIL"). Mirrors the gate cond-6 (~line 919) /
# I7 ceiling-check (~line 1905) sed-based CODE-mutation pattern — build a
# mutant COPY of automate-helpers.sh via sed, confirm it's non-empty, differs
# from the original, and still parses (bash -n) — NOT the H2/H3 fixture-value
# mutation pattern (~line 1724), which mutates a fixture, not the script.
MUT="$(mktemp -d)"
sed 's/^is_not_ready() { grep -qE .*$/is_not_ready() { return 1; }/' "$H" > "$MUT/automate-helpers.sh"
if [ -s "$MUT/automate-helpers.sh" ] && ! cmp -s "$H" "$MUT/automate-helpers.sh" && bash -n "$MUT/automate-helpers.sh" 2>/dev/null \
   && grep -qF 'is_not_ready() { return 1; }' "$MUT/automate-helpers.sh"; then
  MUT_FOLDER_OUT="$(bash "$MUT/automate-helpers.sh" resolve-folder "$DIR" 2>/dev/null)"
  MUT_BACKLOG_OUT="$(bash "$MUT/automate-helpers.sh" resolve-backlog "$DIR/_MISSING_BACKLOG.md" 2>/dev/null)"
  EXPECTED_MUT="$DIR/01-proposed.md
$DIR/02-parked.md
$DIR/05-ready.md"
  if [ "$MUT_FOLDER_OUT" = "$EXPECTED_MUT" ] && [ "$MUT_BACKLOG_OUT" = "$EXPECTED_MUT" ]; then
    ok "mutation control: is_not_ready forced to always-false ⇒ proposed/parked leak back into BOTH resolve-folder and resolve-backlog (dir-fallback) output — proves the check is load-bearing, not vacuous"
  else
    no "mutation control did NOT discriminate (folder='$MUT_FOLDER_OUT' backlog='$MUT_BACKLOG_OUT' expected='$EXPECTED_MUT')"
  fi
  # Positive control: the SAME (unmutated) script, on the SAME fixture, excludes
  # proposed/parked — showing the mutant's leak above is caused by the deleted
  # check, not by some other difference between the two invocations.
  CTRL_FOLDER_OUT="$(bash "$H" resolve-folder "$DIR" 2>/dev/null)"
  if [ "$CTRL_FOLDER_OUT" = "$DIR/05-ready.md" ]; then
    ok "mutation control positive control: the unmutated script, same fixture, still excludes proposed/parked (only 05-ready.md)"
  else
    no "mutation control positive control failed (out='$CTRL_FOLDER_OUT') — cannot trust the mutation result without this"
  fi
else
  no "mutation control not gated (mutant empty, identical to original, bash -n failed, or the is_not_ready override was not injected)"
fi
rm -rf "$MUT"
rm -rf "$WD"

