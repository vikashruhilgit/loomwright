echo "== E. evidence-gated stamps: a done claim rides only when its PR merged (decision 2) =="
# A done stamp on the requirement (and the done/ brief's Outcome) that can exist BEFORE
# any merge — Phase 4.5 wrote one until automate-followups/37; older runs, older
# installed plugins and hand edits still can. trail-pr
# must commit such a stamp only when the PR it names reads MERGED; everything else
# is excluded, named in the one output line, and fails CLOSED.
stamp_req() { # <path> <status> <pr-line or empty>
  printf '# req\n\n<!-- loomwright:requirement-closeout -->\n## Status: %s\n- **Completed:** 2026-01-01T00:00:00Z\n- **Brief:** .supervisor/jobs/done/brief-a.md\n%s' "$2" "$3" > "$P/$1"
}
set_pr() { # <url> <state> [<url> <state>]
  jq -n --arg u "$1" --arg s "$2" --arg u2 "${3:-}" --arg s2 "${4:-}" \
    '[{number:7,url:$u,state:$s,headRefName:"feature/x"}] + (if $u2 == "" then [] else [{number:8,url:$u2,state:$s2,headRefName:"feature/y"}] end)' > "$GH_STUB_DIR/prs.json"
}
trail_names() { git -C "$FX/origin.git" show --name-only --format= "refs/heads/chore/$RUN_ID-trail-1" 2>/dev/null; }
PRL="- **PR:** $PRURL
"
# (a) stamped + OPEN ⇒ excluded + named, not committed; the run file still rides
new_fixture 50; stamp_req "$REQ" done "$PRL"; set_pr "$PRURL" OPEN
out="$(cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason done)"; rc=$?
case "$out" in "trail-pr: opened "*"; excluded $REQ — pr not merged"*) ok "(a) stamped + PR OPEN ⇒ requirement excluded and named ($out)" ;; *) no "(a) stamped+OPEN: $out" ;; esac
names="$(trail_names)"
if ! grep -qxF -- "$REQ" <<<"$names" && grep -qxF -- "$RF_REL0" <<<"$names"; then ok "(a) requirement NOT committed; the run file is"; else no "(a) trail names: $names"; fi
[ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = "1" ] && ok "(a) one line, exit 0" || no "(a) rc=$rc"
# (a') done_with_escalation + OPEN, and a done stamp naming no PR ⇒ excluded
new_fixture 51; stamp_req "$REQ" done_with_escalation "$PRL"; set_pr "$PRURL" OPEN
out="$(cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason done)"
case "$out" in *"; excluded $REQ — pr not merged"*) ok "(a') done_with_escalation + PR OPEN ⇒ excluded" ;; *) no "(a') dwe: $out" ;; esac
new_fixture 52; stamp_req "$REQ" done ""; set_pr "$PRURL" MERGED
out="$(cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason done)"
case "$out" in *"; excluded $REQ — pr not merged"*) ok "(a') a done stamp naming no PR ⇒ excluded (fail closed)" ;; *) no "(a') no-pr stamp: $out" ;; esac
# (b) stamped + MERGED ⇒ committed, no exclusion
new_fixture 53; stamp_req "$REQ" done "$PRL"; set_pr "$PRURL" MERGED
out="$(cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason closeout)"
case "$out" in *"excluded $REQ"*) no "(b) merged stamp excluded: $out" ;; "trail-pr: opened "*) ok "(b) stamped + PR MERGED ⇒ not excluded" ;; *) no "(b): $out" ;; esac
grep -qxF -- "$REQ" < <(trail_names) && ok "(b) the merged item's stamped requirement is committed" || no "(b) requirement missing: $(trail_names)"
# (c) gh pr view failing ⇒ excluded (fail closed); pr list still answers
new_fixture 54; stamp_req "$REQ" done "$PRL"; set_pr "$PRURL" MERGED; touch "$GH_STUB_DIR/pr-view-fail"
out="$(cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason done)"
case "$out" in "trail-pr: opened "*"; excluded $REQ — pr not merged"*) ok "(c) gh pr view failing ⇒ excluded (fail closed)" ;; *) no "(c) gh fail: $out" ;; esac
grep -qxF -- "$REQ" < <(trail_names) && no "(c) requirement committed despite unreadable PR" || ok "(c) requirement not committed"
rm -f "$GH_STUB_DIR/pr-view-fail"
# (e) done/ brief: same rule on its `## Outcome` `- **PR:**`
BA=".supervisor/jobs/done/brief-a.md"
for bstate in OPEN MERGED; do
  if [ "$bstate" = OPEN ]; then new_fixture 56; else new_fixture 57; fi
  printf '# Brief\n## Environment\n- **Source requirement:** %s\n\n## Outcome\n- **Status:** completed\n- **PR:** %s\n' "$REQ" "$PRURL" > "$P/$BA"
  set_pr "$PRURL" "$bstate"
  out="$(cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason done)"
  names="$(trail_names)"
  if [ "$bstate" = OPEN ]; then
    case "$out" in *"; excluded $BA — pr not merged"*) ! grep -qxF -- "$BA" <<<"$names" && ok "(e) done brief whose Outcome PR is OPEN ⇒ excluded + named, not committed" || no "(e) OPEN brief committed" ;; *) no "(e) OPEN brief: $out" ;; esac
    grep -qxF -- "$REQ" <<<"$names" && ok "(e) the unstamped requirement beside it still rides" || no "(e) requirement lost"
  else
    case "$out" in *"excluded $BA"*) no "(e) merged brief excluded: $out" ;; *) grep -qxF -- "$BA" <<<"$names" && ok "(e) done brief whose Outcome PR MERGED ⇒ committed" || no "(e) merged brief missing: $names" ;; esac
  fi
done
# (f) a skipped Queue item carrying a done stamp for an unmerged PR ⇒ excluded
REQB=".supervisor/requirements/f/02-b.md"
new_fixture 58; stamp_req "$REQB" done_with_escalation "- **PR:** https://github.com/acme/widgets/pull/8
"; set_pr "$PRURL" MERGED "https://github.com/acme/widgets/pull/8" CLOSED
out="$(cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason skipped)"
case "$out" in *"; excluded $REQB — pr not merged"*) ! grep -qxF -- "$REQB" < <(trail_names) && ok "(f) skipped item stamped done for a CLOSED PR ⇒ excluded" || no "(f) committed" ;; *) no "(f): $out" ;; esac
# mutation control: without the _evidence_gate call, (a)'s world commits the stamp
EGM="$TOP/egmut"; mkdir -p "$EGM"; cp "$HERE"/*.sh "$HERE"/*.py "$EGM/"; cp -R "$HERE/automate-helpers.d" "$EGM/"; cp -R "$HERE/automate-trail.d" "$EGM/"; cp -R "$HERE/setup-memory.d" "$HERE/meta-sync.d" "$EGM/"
sed 's/^\([[:space:]]*\)_evidence_gate$/\1:/' "$TB" > "$EGM/automate-trail.sh"
if ! cmp -s "$TB" "$EGM/automate-trail.sh" && bash -n "$EGM/automate-trail.sh"; then
  new_fixture 59; stamp_req "$REQ" done "$PRL"; set_pr "$PRURL" OPEN
  (cd "$P" && bash "$EGM/automate-helpers.sh" trail-pr "$RF_REL0" --reason done >/dev/null)
  grep -qxF -- "$REQ" < <(trail_names) && ok "mutation control: without _evidence_gate the OPEN-PR done stamp IS committed (leg (a) is load-bearing)" || no "mutant did not commit the stamp — leg (a) may be vacuous"
else
  no "evidence-gate mutant not generated"
fi

# (d) finding 3 — the gate keys on is_done's own predicate (any `## Status: done…`
# heading, sentinel or not). No done heading ⇒ committed with zero gh calls; a
# bare done heading needs a merged PR too; an ABANDONED stamp is an owner
# decision and rides without a gh call.
new_fixture 55; set_pr "$PRURL" OPEN
out="$(cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason done)"
case "$out" in *"excluded $REQ"*) no "(d) requirement without a done heading excluded: $out" ;; *) grep -qxF -- "$REQ" < <(trail_names) && ok "(d) a requirement with NO done heading is committed even with its PR OPEN" || no "(d) names: $(trail_names)" ;; esac
grep -q '^pr view' "$GH_STUB_DIR/argv.log" && no "(d) gh pr view called for unstamped paths" || ok "(d) zero gh pr view calls for a requirement without a done heading / an Outcome-less brief"
for dv in bare-open bare-nopr bare-merged abandoned; do
  case "$dv" in bare-open) new_fixture 70 ;; bare-nopr) new_fixture 71 ;; bare-merged) new_fixture 72 ;; abandoned) new_fixture 73 ;; esac
  case "$dv" in
    bare-open)   printf '# req a\n## Status: done\n- **PR:** %s\n' "$PRURL" > "$P/$REQ"; set_pr "$PRURL" OPEN ;;
    bare-nopr)   printf '# req a\n## Status: done\n' > "$P/$REQ"; set_pr "$PRURL" MERGED ;;
    bare-merged) printf '# req a\n## Status: done_with_escalation\n- **PR:** %s\n' "$PRURL" > "$P/$REQ"; set_pr "$PRURL" MERGED ;;
    abandoned)   printf '# req a\n\n## Status: done_with_escalation \342\200\224 ABANDONED (- [x] %s  # abandoned: owner)\n' "$REQ" > "$P/$REQ"; set_pr "$PRURL" OPEN ;;
  esac
  out="$(cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason done)"
  case "$dv" in
    bare-open|bare-nopr)
      case "$out" in *"; excluded $REQ — pr not merged"*) ! grep -qxF -- "$REQ" < <(trail_names) && ok "(d) [$dv] a bare (sentinel-less) done heading with no merged PR ⇒ excluded" || no "(d) [$dv] committed" ;; *) no "(d) [$dv]: $out" ;; esac ;;
    bare-merged)
      grep -qxF -- "$REQ" < <(trail_names) && ok "(d) [$dv] a bare done heading whose PR MERGED ⇒ committed" || no "(d) [$dv]: $out" ;;
    abandoned)
      grep -qxF -- "$REQ" < <(trail_names) && ! grep -q '^pr view' "$GH_STUB_DIR/argv.log" && ok "(d) [$dv] an ABANDONED stamp rides with no gh call (owner decision)" || no "(d) [$dv]: $out" ;;
  esac
done
# (d2) round-2 finding 1 — the ABANDONED exemption is anchored to the EXACT
# heading reconcile-status writes; a done heading that merely contains the word
# is a done claim like any other. Each spoof carries an OPEN PR ⇒ excluded.
EMD="$(printf '\342\200\224')"
spoof_leg() { # <fixture-n> <label> <heading> <helpers-dir>
  new_fixture "$1"
  printf '# req a\n%s\n- **PR:** %s\n' "$3" "$PRURL" > "$P/$REQ"; set_pr "$PRURL" OPEN
  out="$(cd "$P" && bash "$4/automate-helpers.sh" trail-pr "$RF_REL0" --reason done)"
}
n=83
for sp in "## Status: done $EMD ABANDONED" "## Status: done <!-- ABANDONED -->" "## Status: done $EMD not ABANDONED, shipped" "## Status: done_with_escalation $EMD ABANDONED (hand-typed, no queue row)"; do
  spoof_leg "$n" spoof "$sp" "$HERE"; n=$((n+1))
  case "$out" in *"; excluded $REQ — pr not merged"*) ! grep -qxF -- "$REQ" < <(trail_names) && ok "(d2) spoof [$sp] + PR OPEN ⇒ excluded" || no "(d2) spoof [$sp] committed" ;; *) no "(d2) spoof [$sp] rode: $out" ;; esac
done
# the genuine reconcile-status stamp — byte-for-byte what `reconcile-status --apply` writes
new_fixture 87; set_pr "$PRURL" OPEN
printf '# req a\n\n## Status: done_with_escalation \342\200\224 ABANDONED (%s)\n' "- [x] $REQ  # abandoned: owner dropped it" > "$P/$REQ"
out="$(cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason abandoned)"
grep -qxF -- "$REQ" < <(trail_names) && [ "$(grep -c '^pr view' "$GH_STUB_DIR/argv.log")" = "0" ] && ok "(d2) the genuine reconcile-status ABANDONED stamp rides with 0 gh calls" || no "(d2) genuine stamp: $out"
# mutation control: the pre-fix loose `/ABANDONED/` test lets the comment spoof ride
ABM="$TOP/abmut"; mkdir -p "$ABM"; cp "$HERE"/*.sh "$HERE"/*.py "$ABM/"; cp -R "$HERE/automate-helpers.d" "$ABM/"; cp -R "$HERE/automate-trail.d" "$ABM/"; cp -R "$HERE/setup-memory.d" "$HERE/meta-sync.d" "$ABM/"
awk '/if \(!\(index\(\$0, ab\) == 1/ { print "      if ($0 !~ /ABANDONED/) { inb = 1; seen = 0 }"; next } { print }' "$TB" > "$ABM/automate-trail.sh"
if ! cmp -s "$TB" "$ABM/automate-trail.sh" && bash -n "$ABM/automate-trail.sh"; then
  spoof_leg 88 mutant "## Status: done <!-- ABANDONED -->" "$ABM"
  grep -qxF -- "$REQ" < <(trail_names) && ok "mutation control: with the loose /ABANDONED/ test the spoof rides (the anchor is load-bearing)" || no "loose mutant excluded the spoof — the anchor leg may be vacuous: $out"
else
  no "ABANDONED-anchor mutant not generated"
fi
# (g2) round-2 finding 2 — a markdown-link / angle-bracket PR value yields the bare URL
for lv in link angle; do
  if [ "$lv" = link ]; then new_fixture 89; pv="[$PRURL]($PRURL)"; else new_fixture 90; pv="<$PRURL>"; fi
  stamp_req "$REQ" done "- **PR:** $pv
"; set_pr "$PRURL" MERGED
  out="$(cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason done)"
  case "$out" in *"excluded $REQ"*) no "(g2) [$lv] merged PR excluded: $out" ;; *) grep -qxF -- "$REQ" < <(trail_names) && ok "(g2) [$lv] a $lv PR value reads MERGED and rides" || no "(g2) [$lv] names" ;; esac
  grep -qE "^pr view $PRURL --json" "$GH_STUB_DIR/argv.log" && ok "(g2) [$lv] gh pr view got the bare URL" || no "(g2) [$lv] argv: $(grep '^pr view' "$GH_STUB_DIR/argv.log")"
done
# (g) finding 4 — an annotated PR value: the first …/pull/<n> token is what gh reads
for gv in req brief; do
  if [ "$gv" = req ]; then new_fixture 74; stamp_req "$REQ" done "- **PR:** $PRURL (merged by the owner, squash)
"; else new_fixture 75; printf '# Brief\n- **Source requirement:** %s\n\n## Outcome\n- **PR:** %s (merged 2026-01-01)\n' "$REQ" "$PRURL" > "$P/.supervisor/jobs/done/brief-a.md"; fi
  set_pr "$PRURL" MERGED
  out="$(cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason done)"
  case "$out" in *"excluded "*"pr not merged"*) no "(g) [$gv] annotated merged PR excluded: $out" ;; *) ok "(g) [$gv] an annotated merged PR value is not excluded" ;; esac
  grep -qE "^pr view $PRURL --json" "$GH_STUB_DIR/argv.log" && ok "(g) [$gv] gh pr view got the bare URL token" || no "(g) [$gv] argv: $(grep '^pr view' "$GH_STUB_DIR/argv.log")"
done
# (h) finding 2 — Outcome heading variants fail CLOSED on the brief side too
BA=".supervisor/jobs/done/brief-a.md"
n=91   # 91-97 (81-82 belong to leg R, 83-90 to d2/g2)
for hv in '## Outcome — ESCALATED' '## Outcome:' '### Outcome' 'nopr' 'rubric' '##Outcome' '## Outcome-ish'; do
  new_fixture "$n"; n=$((n+1)); set_pr "$PRURL" OPEN
  case "$hv" in
    nopr)   printf '# Brief\n- **Source requirement:** %s\n\n## Outcome\n- **Status:** completed\n- **Branch:** feature/x\n' "$REQ" > "$P/$BA"; set_pr "$PRURL" MERGED ;;
    rubric) printf '# Brief\n- **Source requirement:** %s\n\n## Outcomes Rubric\n- **PR:** %s\n' "$REQ" "$PRURL" > "$P/$BA" ;;
    *)      printf '# Brief\n- **Source requirement:** %s\n\n%s\n- **PR:** %s\n' "$REQ" "$hv" "$PRURL" > "$P/$BA" ;;
  esac
  out="$(cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason done)"
  if [ "$hv" = rubric ] || [ "$hv" = '##Outcome' ] || [ "$hv" = '## Outcome-ish' ]; then
    grep -qxF -- "$BA" < <(trail_names) && ok "(h) [$hv] is not an Outcome section — the brief rides" || no "(h) $hv: $out"
  else
    case "$out" in *"; excluded $BA — pr not merged"*) ! grep -qxF -- "$BA" < <(trail_names) && ok "(h) [$hv] ⇒ brief excluded (fail closed)" || no "(h) [$hv] committed" ;; *) no "(h) [$hv]: $out" ;; esac
  fi
done

echo "== R. retract: a reused OPEN trail branch never keeps a done claim for unmerged work (finding 1) =="
# An earlier push (a v15.114.0/.1 park-time trail, replayed here by the gate-less
# mutant) committed an OPEN-PR done stamp to chore/<run>-trail-1 and staged it.
# The next trail-pr reuses that branch: it must retract the stamp at the tip
# (main's version, or removed when main lacks the file), name it, and leave no
# done blob staged. REQ3 is a requirement main does not have.
REQ3=".supervisor/requirements/f/03-c.md"
RETM="$TOP/retmut"; mkdir -p "$RETM"; cp "$HERE"/*.sh "$HERE"/*.py "$RETM/"; cp -R "$HERE/automate-helpers.d" "$RETM/"; cp -R "$HERE/automate-trail.d" "$RETM/"; cp -R "$HERE/setup-memory.d" "$HERE/meta-sync.d" "$RETM/"
sed 's/^\([[:space:]]*\)retract="\${retract:+.*$/\1:/' "$TB" > "$RETM/automate-trail.sh"
cmp -s "$TB" "$RETM/automate-trail.sh" && no "retract mutant not generated"
for rv in fixed mutant; do
  if [ "$rv" = fixed ]; then new_fixture 81; D="$HERE"; else new_fixture 82; D="$RETM"; fi
  stamp_req "$REQ" done "$PRL"; stamp_req "$REQ3" done "$PRL"
  awk -v r="$REQ3" '{print} /^## Queue$/{print "- [ ] " r}' "$P/$RF_REL0" > "$TOP/rf8x" && mv "$TOP/rf8x" "$P/$RF_REL0"
  set_pr "$PRURL" OPEN
  (cd "$P" && bash "$EGM/automate-helpers.sh" trail-pr "$RF_REL0" --reason awaiting_merge >/dev/null)
  BR1="refs/heads/chore/$RUN_ID-trail-1"
  old="$(git -C "$FX/origin.git" rev-parse "$BR1:$REQ" 2>/dev/null)"
  grep -q '^## Status: done' < <(git -C "$FX/origin.git" show "$BR1:$REQ" 2>/dev/null) && [ "$(git -C "$P" ls-files -s -- "$REQ" | awk '{print $2}')" = "$old" ] \
    && ok "[$rv] setup: the old trail branch tip AND the primary index carry the OPEN-PR done stamp" || no "[$rv] setup failed"
  echo "- t1 later" >> "$P/$RF_REL0"
  out="$(cd "$P" && bash "$D/automate-helpers.sh" trail-pr "$RF_REL0" --reason done)"
  if [ "$rv" = fixed ]; then
    case "$out" in "trail-pr: pushed "*) ;; *) no "[fixed] not a push: $out" ;; esac
    bad=""; for x in "; excluded $REQ — pr not merged" "; retracted $REQ" "; retracted $REQ3"; do case "$out" in *"$x"*) ;; *) bad="$bad [$x]" ;; esac; done
    [ -z "$bad" ] && ok "[fixed] reused branch: excluded AND retracted, each named ($out)" || no "[fixed] output lacks$bad: $out"
    [ "$(git -C "$FX/origin.git" rev-parse "$BR1:$REQ")" = "$(git -C "$FX/origin.git" rev-parse "main:$REQ")" ] && ok "[fixed] trail tip holds main's version of the requirement (no done stamp)" || no "[fixed] tip still: $(git -C "$FX/origin.git" show "$BR1:$REQ")"
    git -C "$FX/origin.git" rev-parse -q --verify "$BR1:$REQ3" >/dev/null && no "[fixed] REQ3 still on the tip" || ok "[fixed] a requirement main lacks is removed from the tip"
    idx="$(git -C "$P" ls-files -s -- "$REQ" | awk '{print $2}')"
    [ "$idx" != "$old" ] && [ -z "$(git -C "$P" ls-files -s -- "$REQ3")" ] && ok "[fixed] no done-stamp blob left staged in the primary index" || no "[fixed] index still holds the stamp"
    grep -q '^## Status: done' "$P/$REQ" && ok "[fixed] the working copy is untouched" || no "[fixed] working copy changed"
    out2="$(cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason done)"
    case "$out2" in "trail-pr: skipped — trail already up to date"*) case "$out2" in *retracted*) no "[fixed] re-run retracts again: $out2" ;; *) ok "[fixed] re-run: no-diff skip, nothing left to retract" ;; esac ;; *) no "[fixed] re-run: $out2" ;; esac
  else
    grep -q '^## Status: done' < <(git -C "$FX/origin.git" show "$BR1:$REQ") && ok "mutation control: without the retract the reused tip keeps the done stamp (leg R is load-bearing)" || no "mutant retracted anyway — leg R may be vacuous"
  fi
done

echo "== X. dismissed-finding drafts ride the trail; dropped ones never do (and are retracted) =="
# mk_drafts — real drafts via automate-dismissed.sh (dismissed-drafts): the drain
# sidecar briefly carries a `dismissed` list, then goes back to the committed
# item-10 shape. XK quotes a `## Status: done` + `- **PR:**` line (evidence-gate
# canary); XD is the one the owner drops.
mk_drafts() {
  local sc="$P/.supervisor/automate/$RUN_ID.review-heal-result.md"
  { printf '%s\n' "$RH_GOOD"; printf '%s\n' '- dismissed: [{finding: "keep me\n## Status: done\n- **PR:** https://x/pull/1", reason: stale, source: reviews, severity: MEDIUM}, {finding: "drop me", reason: stale, source: reviews, severity: HIGH}]'; } > "$sc"
  XOUT="$(cd "$P" && bash "$H" dismissed-drafts "$RF_REL0" "$REQ" "$PRURL")"
  printf '%s\n' "$RH_GOOD" > "$sc"
  XK=".supervisor/requirements/proposed/$(grep -lxF '> keep me' "$P"/.supervisor/requirements/proposed/"$RUN_ID"--*.md | xargs basename)"
  XD=".supervisor/requirements/proposed/$(grep -lxF '> drop me' "$P"/.supervisor/requirements/proposed/"$RUN_ID"--*.md | xargs basename)"
}
tip_has() { git -C "$FX/origin.git" rev-parse -q --verify "refs/heads/chore/$RUN_ID-trail-1:$1" >/dev/null 2>&1; }
new_fixture 195; mk_drafts
case "$XOUT" in *"dismissed-drafts: 2 per-finding + 0 summary"*) ok "setup: two real drafts written" ;; *) no "setup drafts: $XOUT" ;; esac
(cd "$P" && bash "$H" dismissed-decide "$RF_REL0" "$XD" drop >/dev/null)
: > "$GH_STUB_DIR/argv.log"
out="$(cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason closeout)"
case "$out" in "trail-pr: opened "*) ok "trail-pr opened ($out)" ;; *) no "trail-pr: $out" ;; esac
tip_has "$XK" && ok "an undecided draft is a trail candidate and rides the trail commit" || no "draft did not ride: $(trail_names)"
tip_has "$XD" && no "the dropped draft rode the trail" || ok "the dropped draft does not ride"
case "$out" in *"excluded $XK"*) no "draft excluded by the evidence gate: $out" ;; *) ok "the draft quoting '## Status: done' / '- **PR:**' is not gated (no column-0 done heading)" ;; esac
grep -q '^pr view' "$GH_STUB_DIR/argv.log" && no "evidence gate called gh pr view: $(grep '^pr view' "$GH_STUB_DIR/argv.log")" || ok "the evidence gate made no gh call for the drafts"
# Retraction: both drafts pushed UNDECIDED, then XD dropped, XK deleted by hand
# with NO ledger row; the next trail-pr reuses the open branch.
new_fixture 196; mk_drafts
out="$(cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason done)"
tip_has "$XK" && tip_has "$XD" && ok "setup: both undecided drafts on the trail tip" || no "retract setup: $out / $(trail_names)"
(cd "$P" && bash "$H" dismissed-decide "$RF_REL0" "$XD" drop >/dev/null)
rm -f "$P/$XK"
out="$(cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason done)"
case "$out" in "trail-pr: pushed "*"; retracted $XD"*) ok "next trail-pr retracts the dropped draft, named ($out)" ;; *) no "retract output: $out" ;; esac
tip_has "$XD" && no "dropped draft still on the trail tip" || ok "the dropped draft is removed from the trail tip"
tip_has "$XK" && ok "an absent draft with NO ledger row is left untouched on the tip" || no "unledgered absent draft was removed"
case "$out" in *"retracted $XK"*) no "unledgered draft named retracted" ;; *) ok "only the ledger-dropped draft is named" ;; esac
[ -z "$(git -C "$P" ls-files -s -- "$XD")" ] && ok "the dropped draft is not left staged in the primary index" || no "dropped draft still staged"
out2="$(cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason done)"
case "$out2" in *"retracted"*) no "re-run retracts again: $out2" ;; "trail-pr: skipped — trail already up to date"*) ok "re-run: no-diff skip, nothing left to retract" ;; *) no "re-run: $out2" ;; esac
# A finding that MOVED buckets (its UNDECIDED own draft already on the trail tip,
# then re-dismissed LOW ⇒ automate-dismissed.sh retires the own draft with a
# `moved` ledger row and lists it in the summary): the next trail-pr retracts the
# stale own-draft blob, so the trail never carries the finding twice.
new_fixture 197; mk_drafts
out="$(cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason done)"
tip_has "$XD" && ok "moved: setup, the undecided own draft is on the trail tip" || no "moved setup: $out / $(trail_names)"
sc="$P/.supervisor/automate/$RUN_ID.review-heal-result.md"
{ printf '%s\n' "$RH_GOOD"; printf '%s\n' '- dismissed: [{finding: "keep me\n## Status: done\n- **PR:** https://x/pull/1", reason: stale, source: reviews, severity: MEDIUM}, {finding: "drop me", reason: stale, source: reviews, severity: LOW}]'; } > "$sc"
XOUT="$(cd "$P" && bash "$H" dismissed-drafts "$RF_REL0" "$REQ" "$PRURL")"
printf '%s\n' "$RH_GOOD" > "$sc"
# the per-item namespace: <run_id>--<stem>-<first 6 hex of sha1(full Queue item path)>
XIH="$(printf '%s' "$REQ" | python3 -c 'import hashlib,sys; print(hashlib.sha1(sys.stdin.buffer.read()).hexdigest()[:6])')"
XS=".supervisor/requirements/proposed/$RUN_ID--$(basename "$REQ" .md)-$XIH--dismissed-summary.md"
case "$XOUT" in *"retired ${XD##*/}"*) ok "moved: the own draft is retired when its finding drops below the threshold" ;; *) no "moved retire: $XOUT" ;; esac
[ ! -e "$P/$XD" ] && [ -f "$P/$XS" ] && ok "moved: own draft gone on disk, the summary lists the finding" || no "moved disk state: $(ls "$P/.supervisor/requirements/proposed")"
out="$(cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason done)"
case "$out" in *"retracted $XD"*) ok "moved: next trail-pr retracts the stale own-draft blob ($out)" ;; *) no "moved retract: $out" ;; esac
tip_has "$XD" && no "moved: the stale own draft is still on the trail tip" || ok "moved: the stale own draft is removed from the trail tip"
tip_has "$XS" && ok "moved: the summary carrying the finding rides the trail (listed once)" || no "moved: summary not on tip: $(trail_names)"
# Lane drafts use ONE digits-only definition (automate-dismissed.sh's _dismissed_lane_id):
# `<run_id>-L2--…` is a lane draft and rides; `<run_id>-L2x--…` is not and never does.
new_fixture 198
XL=".supervisor/requirements/proposed/$RUN_ID-L2--01-a-abc123--dismissed-1.md"
XLX=".supervisor/requirements/proposed/$RUN_ID-L2x--01-a-abc123--dismissed-1.md"
mkdir -p "$P/.supervisor/requirements/proposed"
printf '# Dismissed finding\n\n> lane finding\n' > "$P/$XL"; printf '# Dismissed finding\n\n> not a lane\n' > "$P/$XLX"
out="$(cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason done)"
case "$out" in "trail-pr: opened "*) ok "lane-draft shape: trail-pr opened ($out)" ;; *) no "lane-draft shape trail-pr: $out" ;; esac
tip_has "$XL" && ok "a <run_id>-L<digits>--… draft is a lane draft and rides the trail" || no "lane draft did not ride: $(trail_names)"
tip_has "$XLX" && no "a <run_id>-L2x--… draft rode the trail as a lane draft" || ok "a <run_id>-L2x--… draft is NOT a lane draft (digits-only definition)"

echo "== D3. checkout contract re-examined for trail-after-merge (decision 3) =="
# With trail-pr only after merge / at run end, the trail that matters is closeout's
# own, which runs AFTER closeout's sync — the primary is on main. Each piece of
# the contract is re-proved from THAT state, each with a control that turns red.
# (i) closeout's trail still stages into the primary index; the next PICK branches
#     off that main ⇒ trail-unstage is still needed.
for v in control unstage; do
  if [ "$v" = control ]; then closeout_fixture 60; else closeout_fixture 61; fi
  out="$(run_closeout)"
  case "$out" in *"closeout: synced — main at "*"trail-pr: opened "*) ;; *) no "[D3i $v] closeout: $out" ;; esac
  [ "$(git -C "$P" symbolic-ref --short HEAD)" = main ] && [ -n "$(git -C "$P" diff --cached --name-only)" ] && ok "[D3i $v] after closeout's trail the primary is on main WITH staged trail paths" || no "[D3i $v] nothing staged / not on main"
  [ "$v" = unstage ] && (cd "$P" && bash "$H" trail-unstage "$RF_REL" >/dev/null)
  names="$(cd "$P" && git checkout -q -b feature/next && echo n > new.txt && git add new.txt && git commit -qm next && git show --name-only --format= HEAD)"
  if [ "$v" = control ]; then
    grep -qxF -- "$RF_REL" <<<"$names" && ok "[D3i control] without trail-unstage the next item's plain commit sweeps the trail (run file in it)" || no "[D3i control] no sweep — trail-unstage would be dead: [$names]"
  else
    [ "$names" = "new.txt" ] && ok "[D3i] with trail-unstage the next item's commit holds exactly new.txt — trail-unstage KEPT" || no "[D3i] swept: [$names]"
  fi
done
# (ii) the owner merges closeout's trail PR, then hand-pulls main ⇒ needs _stage_tip.
STM="$TOP/d3stm"; mkdir -p "$STM"; cp "$HERE"/*.sh "$HERE"/*.py "$STM/"; cp -R "$HERE/automate-helpers.d" "$STM/"; cp -R "$HERE/automate-trail.d" "$STM/"; cp -R "$HERE/setup-memory.d" "$HERE/meta-sync.d" "$STM/"
awk '{ if ($0 == "_stage_tip() {") { print "_stage_tip() { return 0; }"; print "_stage_tip_dead() {" } else print }' "$TB" > "$STM/automate-trail.sh"
for v in kept mutant; do
  if [ "$v" = kept ]; then closeout_fixture 62; D="$SPYD"; else closeout_fixture 63; D="$STM"; fi
  out="$(cd "$P" && bash "$D/automate-helpers.sh" closeout "$RF_REL" "$REQ" "$PRURL")"
  case "$out" in *"trail-pr: opened "*) ;; *) no "[D3ii $v] closeout trail: $out" ;; esac
  TM="$FX/tmerger"; git clone -q "$FX/origin.git" "$TM" 2>/dev/null
  ( cd "$TM" && git checkout -q main && git merge -q --squash "origin/chore/$RUN_ID-trail-1" >/dev/null && git commit -qm "squash trail" && git push -q origin main 2>/dev/null )
  echo "- t9 live progress after closeout" >> "$P/$RF_REL"
  pull_out="$(cd "$P" && git pull -q 2>&1)"; prc=$?
  if [ "$v" = kept ]; then
    [ "$prc" -eq 0 ] && [ "$(git -C "$P" rev-parse HEAD)" = "$(git -C "$FX/origin.git" rev-parse main)" ] && grep -q 't9 live progress' "$P/$RF_REL" && ok "[D3ii] hand git pull over closeout's merged trail PR fast-forwards, live bytes kept — _stage_tip KEPT" || no "[D3ii] hand pull: $pull_out"
  else
    [ "$prc" -ne 0 ] && ok "[D3ii control] without _stage_tip the same hand pull refuses (the staged blobs are load-bearing)" || no "[D3ii control] pull succeeded without staging — _stage_tip would be dead"
  fi
done
# (iii) closeout #1's trail PR merged → PICK un-stage → item 2's PR merged →
#       closeout #2's sync ⇒ needs the .trail-staged re-stage.
PRURL8="https://github.com/acme/widgets/pull/8"
for v in record no-record; do
  if [ "$v" = record ]; then closeout_fixture 64; else closeout_fixture 65; fi
  run_closeout >/dev/null
  TM="$FX/tmerger"; git clone -q "$FX/origin.git" "$TM" 2>/dev/null
  ( cd "$TM" && git checkout -q main && git merge -q --squash "origin/chore/$RUN_ID-trail-1" >/dev/null && git commit -qm "squash trail" && git push -q origin main 2>/dev/null \
    && git checkout -q -b feature/y && echo y > y.txt && git add y.txt && git commit -qm y && git push -q origin feature/y 2>/dev/null \
    && git checkout -q main && git merge -q --squash feature/y >/dev/null && git commit -qm "y (#8)" && git push -q origin main 2>/dev/null )
  OID8="$(git -C "$TM" rev-parse feature/y)"
  jq --arg u "$PRURL8" --arg o "$OID8" '. + [{number:8,url:$u,state:"MERGED",headRefName:"feature/y",headRefOid:$o}]' "$GH_STUB_DIR/prs.json" > "$GH_STUB_DIR/p.tmp" && mv "$GH_STUB_DIR/p.tmp" "$GH_STUB_DIR/prs.json"
  (cd "$P" && bash "$H" trail-unstage "$RF_REL" >/dev/null)
  echo "- t10 live progress after the PICK un-stage" >> "$P/$RF_REL"
  [ "$v" = no-record ] && rm -f "$P/.supervisor/automate/$RUN_ID.trail-staged"
  out="$(cd "$P" && bash "$SPYD/automate-helpers.sh" closeout "$RF_REL" "$REQB" "$PRURL8")"
  if [ "$v" = record ]; then
    case "$out" in *"closeout: synced — main at "*) [ "$(git -C "$P" rev-parse HEAD)" = "$(git -C "$FX/origin.git" rev-parse main)" ] && grep -q 't10 live progress' "$P/$RF_REL" && ok "[D3iii] closeout #2's sync fast-forwards over closeout #1's merged trail — the .trail-staged re-stage KEPT" || no "[D3iii] synced but state wrong" ;; *) no "[D3iii] sync: $out" ;; esac
  else
    case "$out" in *"closeout: skipped — git pull --ff-only refused"*) ok "[D3iii control] without the record closeout #2's pull refuses (the re-stage is load-bearing)" ;; *) no "[D3iii control] did not refuse — _restage_landed would be dead: $out" ;; esac
  fi
done

echo "== G. PICK-time trail gate: the single-open-PR invariant counts this run's trail PR =="
# Run automate-2026-10-01-142337: closeout opened trail PR #345, the owner gave
# the next go first, item 03's branch was cut, THEN #345 merged — with strict
# required checks PR #347 read BEHIND. trail-gate parks while the trail PR is
# open and, once it merged, syncs the primary over it before the next branch.
TG_URL="https://github.com/acme/widgets/pull/101"
tg_merge_trail() {  # squash-merge this run's trail-1 branch into origin/main; the stub reads it MERGED
  local TM="$FX/tgmerger"; rm -rf "$TM"; git clone -q "$FX/origin.git" "$TM" 2>/dev/null
  ( cd "$TM" && git checkout -q main && git merge -q --squash "origin/chore/$RUN_ID-trail-1" >/dev/null && git commit -qm "squash trail (#101)" && git push -q origin main 2>/dev/null )
  jq --arg u "$TG_URL" 'map(if .url == $u then .state = "MERGED" else . end)' "$GH_STUB_DIR/prs.json" > "$GH_STUB_DIR/p.tmp" && mv "$GH_STUB_DIR/p.tmp" "$GH_STUB_DIR/prs.json"
}
tg_gate() { (cd "$P" && bash "${TG_H:-$H}" trail-gate "$RF_REL"); }
tg_next_branch() {  # the next item's branch, cut from the primary as PICK leaves it: prints its commit's file names
  (cd "$P" && git checkout -q -b feature/next && echo n > new.txt && git add new.txt && git commit -qm next && git show --name-only --format= HEAD)
}

# G1. open trail PR ⇒ PARK naming it; nothing in the primary moves.
closeout_fixture 120
out="$(run_closeout)"
case "$out" in *"trail-pr: opened $TG_URL"*) ok "[G1] setup: closeout opened trail PR #101" ;; *) no "[G1] setup: $out" ;; esac
head0="$(git -C "$P" rev-parse HEAD)"; idx0="$(git -C "$P" ls-files -s | cksum)"
out="$(tg_gate)"; rc=$?
[ "$out" = "trail-gate: PARK — trail PR open $TG_URL (merge or close it, then --resume)" ] && [ "$rc" -eq 0 ] && ok "[G1] open trail PR ⇒ '$out', exit 0" || no "[G1] open trail PR ⇒ '$out' rc=$rc"
[ "$head0" = "$(git -C "$P" rev-parse HEAD)" ] && [ "$idx0" = "$(git -C "$P" ls-files -s | cksum)" ] && ok "[G1] a PARK touches neither HEAD nor the index" || no "[G1] PARK moved the primary"
# Mutation control: the OPEN filter neutered ⇒ the same state reads clear (the PARK is load-bearing).
TGM="$TOP/tgm"; mkdir -p "$TGM"; cp "$HERE"/*.sh "$HERE"/*.py "$TGM/"; cp -R "$HERE/automate-helpers.d" "$TGM/"; cp -R "$HERE/automate-trail.d" "$TGM/"; cp -R "$HERE/setup-memory.d" "$HERE/meta-sync.d" "$TGM/"
sed 's/select((.state \/\/ "") == "OPEN") | //' "$TB" > "$TGM/automate-trail.sh"
if cmp -s "$TB" "$TGM/automate-trail.sh"; then no "[G1] mutation control: the patch changed nothing — inconclusive"
else
  sed 's/select((.headRefName \/\/ "") | startswith($p)) | select((.headRefName | ltrimstr($p)) | test("^\[0-9\]+$")) | .url\] | join/select(false) | .url] | join/' "$TGM/automate-trail.sh" > "$TGM/at.mut" && mv "$TGM/at.mut" "$TGM/automate-trail.sh"
  out="$(TG_H="$TGM/automate-helpers.sh" tg_gate)"
  case "$out" in "trail-gate: clear — "*) ok "[G1] mutation control: with the open-PR filter dropped the same state reads '$out' — the PARK is load-bearing" ;; *) no "[G1] mutation control REFUTED: $out" ;; esac
fi
# The incident, reproduced without the gate (PICK before this fix): un-stage, cut the
# next branch, THEN the owner merges the trail PR ⇒ the next branch is BEHIND origin/main.
(cd "$P" && bash "$H" trail-unstage "$RF_REL" >/dev/null)
tg_next_branch >/dev/null
tg_merge_trail; git -C "$P" fetch -q origin
git -C "$P" merge-base --is-ancestor origin/main feature/next && no "[G1] incident repro: next branch is up to date (the fixture no longer shows BEHIND)" || ok "[G1] incident repro: next branch cut while the trail PR was open is BEHIND once it merges (#345 under #347)"

# G2. trail PR merged ⇒ clear + sync; the next branch carries it and holds only its own file.
closeout_fixture 121
run_closeout >/dev/null
tg_merge_trail
echo "- t11 live progress after the trail merged" >> "$P/$RF_REL"
out="$(tg_gate)"; rc=$?
case "$out" in "trail-gate: clear — no open trail PR; synced — main at "*) [ "$rc" -eq 0 ] && ok "[G2] merged trail PR ⇒ '$out'" || no "[G2] rc=$rc" ;; *) no "[G2] merged trail PR ⇒ '$out'" ;; esac
[ "$(git -C "$P" rev-parse HEAD)" = "$(git -C "$FX/origin.git" rev-parse main)" ] && ok "[G2] primary main == origin/main (fast-forwarded over the merged trail)" || no "[G2] primary not synced"
grep -q 't11 live progress' "$P/$RF_REL" && ok "[G2] live run-file bytes survive the sync" || no "[G2] live bytes lost"
(cd "$P" && bash "$H" trail-unstage "$RF_REL" >/dev/null)
names="$(tg_next_branch)"
[ "$names" = "new.txt" ] && ok "[G2] next item's commit holds exactly new.txt" || no "[G2] next commit swept: [$names]"
git -C "$P" merge-base --is-ancestor "$(git -C "$FX/origin.git" rev-parse main)" feature/next && ok "[G2] next branch carries the merged trail (not BEHIND)" || no "[G2] next branch BEHIND origin/main"
out="$(tg_gate)"
case "$out" in "trail-gate: clear — no open trail PR; sync skipped — primary checkout is on feature/next, not main") ok "[G2] primary on a feature branch ⇒ '$out' (reported, never a park)" ;; *) no "[G2] on feature branch ⇒ '$out'" ;; esac
# Mutation control: the sync removed ⇒ the primary stays behind and the next branch is BEHIND.
closeout_fixture 122
run_closeout >/dev/null
tg_merge_trail
TGS="$TOP/tgs"; mkdir -p "$TGS"; cp "$HERE"/*.sh "$HERE"/*.py "$TGS/"; cp -R "$HERE/automate-helpers.d" "$TGS/"; cp -R "$HERE/automate-trail.d" "$TGS/"; cp -R "$HERE/setup-memory.d" "$HERE/meta-sync.d" "$TGS/"
sed 's/^  if _sync_primary "\$rf_rel" "\$run_id" "\$base_branch" "" "\$bm"; then$/  if false; then/' "$TB" > "$TGS/automate-trail.sh"
if cmp -s "$TB" "$TGS/automate-trail.sh"; then no "[G2] mutation control: the patch changed nothing — inconclusive"
else
  TG_H="$TGS/automate-helpers.sh" tg_gate >/dev/null
  (cd "$P" && bash "$H" trail-unstage "$RF_REL" >/dev/null)
  tg_next_branch >/dev/null
  git -C "$P" merge-base --is-ancestor "$(git -C "$FX/origin.git" rev-parse main)" feature/next && no "[G2] mutation control REFUTED: next branch up to date without the sync" || ok "[G2] mutation control: without the gate's sync the next branch is BEHIND — the sync is load-bearing"
fi

# G3. what does NOT count: a CLOSED trail PR, another run's open trail PR, a non-numeric suffix.
closeout_fixture 123
run_closeout >/dev/null
jq --arg u "$TG_URL" 'map(if .url == $u then .state = "CLOSED" else . end)
  + [{number:200,url:"https://github.com/acme/widgets/pull/200",state:"OPEN",headRefName:"chore/automate-2099-01-01-000000-trail-1"},
     {number:201,url:"https://github.com/acme/widgets/pull/201",state:"OPEN",headRefName:("chore/'"$RUN_ID"'-trail-x")}]' \
  "$GH_STUB_DIR/prs.json" > "$GH_STUB_DIR/p.tmp" && mv "$GH_STUB_DIR/p.tmp" "$GH_STUB_DIR/prs.json"
out="$(tg_gate)"
case "$out" in "trail-gate: clear — "*) ok "[G3] CLOSED trail PR + another run's trail PR + a non-numeric suffix ⇒ clear" ;; *) no "[G3] ⇒ '$out'" ;; esac

# G4. fail CLOSED: anything that stops the read parks; exit 0 always.
closeout_fixture 124
run_closeout >/dev/null
tg_merge_trail
touch "$GH_STUB_DIR/pr-list-fail"
out="$(tg_gate)"; rc=$?
[ "$out" = "trail-gate: PARK — trail PR state unreadable (gh pr list failed)" ] && [ "$rc" -eq 0 ] && ok "[G4] gh pr list failing ⇒ '$out', exit 0" || no "[G4] list fail ⇒ '$out' rc=$rc"
rm -f "$GH_STUB_DIR/pr-list-fail"
out="$(cd "$P" && LOOMWRIGHT_GH_BIN="$TOP/no-such-gh" bash "$H" trail-gate "$RF_REL")"; rc=$?
[ "$out" = "trail-gate: PARK — gh unavailable" ] && [ "$rc" -eq 0 ] && ok "[G4] gh absent ⇒ '$out', exit 0" || no "[G4] gh absent ⇒ '$out' rc=$rc"
out="$(cd "$P" && bash "$H" trail-gate ".supervisor/automate/nope.md")"; rc=$?
[ "$out" = "trail-gate: PARK — run file not found" ] && [ "$rc" -eq 0 ] && ok "[G4] missing run file ⇒ '$out', exit 0" || no "[G4] missing run file ⇒ '$out' rc=$rc"
[ "$(git -C "$P" rev-parse HEAD)" != "$(git -C "$FX/origin.git" rev-parse main)" ] && ok "[G4] no PARK synced the primary" || no "[G4] a PARK synced the primary"
grep -q '^pr merge' "$GH_STUB_DIR/argv.log" && no "[G] gh pr merge called" || ok "[G] trail-gate never calls gh pr merge"
for fn in trail_gate _sync_primary; do
  body="$(awk -v f="^$fn\\\\(\\\\) \\\\{" '$0 ~ f {s=1} s{print} s&&/^}/{exit}' "$TB" | grep -vE '^[[:space:]]*#')"
  bad="$(grep -nE 'git (-C [^ ]+ )?(commit|reset|stash|merge|push)|pr merge|--force' <<<"$body" || true)"
  [ -n "$body" ] && [ -z "$bad" ] && ok "[G] $fn never commits/resets/stashes/merges/pushes" || no "[G] $fn body: ${bad:-<function not found>}"
done

echo "== C. RECONCILE re-entry (AC14) =="
closeout_fixture 8
bash "$HERE/run-lock.sh" acquire --owner "automate:$RUN_ID" --session-id SESS-1 --root "$P" >/dev/null
out="$(run_closeout)"
case "$out" in *"closeout: skipped — run lock held by automate:$RUN_ID"*) ok "AC14: without --session-id ⇒ skipped — run lock held" ;; *) no "AC14 no-sid: $out" ;; esac
[ -d "$FX/wt-pr" ] && grep -qxF -- "- [ ] $REQ" "$P/$RF_REL" && ok "AC14: lock held ⇒ steps 3–7 did not run" || no "AC14: steps ran under a foreign lock"
out="$(run_closeout --session-id SESS-1)"
[ ! -d "$FX/wt-pr" ] && grep -qxF -- "- [x] $REQ" "$P/$RF_REL" && ok "AC14: --session-id re-enters ⇒ steps 3–7 ran" || no "AC14 re-entry: $out"
grep -q "^owner	automate:$RUN_ID\$" "$P/.supervisor/run.lock/meta" 2>/dev/null && ok "AC14: outer lock still held by automate:<run_id> afterwards" || no "AC14: outer lock lost"
bash "$HERE/run-lock.sh" release --owner "automate:$RUN_ID" --root "$P" >/dev/null

# (AC14w) one lock dir per checkout, linked worktrees included: the engine's PICK acquire
# passes no --root (run-lock.sh resolves the MAIN worktree root), so a closeout of a run
# file living in a LINKED worktree must meet that same lock — refused without --session-id,
# re-entered with it, and never a second .supervisor/run.lock in the linked worktree.
# Mutant: closeout's lock helper passes `--root <run file's toplevel>` (the old divergent
# root) ⇒ it locks <linked>/.supervisor/run.lock beside the engine's and runs steps 3–7.
WT_LINK_LEG() { # <scripts dir> — closeout_fixture'd world; run file + item copied into wt-other
  local d="$1" W="$FX/wt-other"
  mkdir -p "$W/.supervisor/automate" "$W/$(dirname "$REQ")"
  cp "$P/$RF_REL" "$W/$RF_REL"; cp "$P/$REQ" "$W/$REQ"
  (cd "$W" && bash "$HERE/run-lock.sh" acquire --owner "automate:$RUN_ID" --session-id SESS-1 >/dev/null)
  (cd "$W" && bash "$d/automate-helpers.sh" closeout "$RF_REL" "$REQ" "$PRURL" 2>/dev/null)
}
closeout_fixture 131
out="$(WT_LINK_LEG "$SPYD")"
case "$out" in *"closeout: skipped — run lock held by automate:$RUN_ID"*) ok "AC14w: linked worktree, engine lock (no --root) held ⇒ closeout refused" ;; *) no "AC14w no-sid: $out" ;; esac
[ -d "$FX/wt-pr" ] && grep -qxF -- "- [ ] $REQ" "$FX/wt-other/$RF_REL" && [ ! -e "$FX/wt-other/.supervisor/run.lock" ] \
  && ok "AC14w: refused ⇒ steps 3–7 did not run, no second lock dir in the linked worktree" || no "AC14w: steps ran / second lock dir (wt-pr: $([ -d "$FX/wt-pr" ] && echo kept || echo gone); queue: $(grep -F -- "$REQ" "$FX/wt-other/$RF_REL" | head -n1); lock: $(ls -d "$FX/wt-other/.supervisor/run.lock" 2>&1))"
out="$(cd "$FX/wt-other" && bash "$SPYD/automate-helpers.sh" closeout "$RF_REL" "$REQ" "$PRURL" --session-id SESS-1 2>/dev/null)"
grep -qxF -- "- [x] $REQ" "$FX/wt-other/$RF_REL" && grep -q "^owner	automate:$RUN_ID\$" "$P/.supervisor/run.lock/meta" 2>/dev/null && [ ! -e "$FX/wt-other/.supervisor/run.lock" ] \
  && ok "AC14w: --session-id re-enters the main-root lock from a linked worktree; outer owner kept" || no "AC14w re-entry: $out"
bash "$HERE/run-lock.sh" release --owner "automate:$RUN_ID" --root "$P" >/dev/null
MUTW="$TOP/mutd-wtroot"; mkdir -p "$MUTW"; cp -R "$SPYD"/. "$MUTW/"
sed 's|( cd "$dir" 2>/dev/null \&\& bash "$HERE/run-lock.sh" "$@" )|( bash "$HERE/run-lock.sh" "$@" --root "$dir" )|' "$TB" > "$MUTW/automate-trail.sh"
if [ -s "$MUTW/automate-trail.sh" ] && ! cmp -s "$TB" "$MUTW/automate-trail.sh" && bash -n "$MUTW/automate-trail.sh"; then
  closeout_fixture 132
  out="$(WT_LINK_LEG "$MUTW")"
  case "$out" in *"run lock held"*) no "AC14w mutant: the divergent --root still refused — the leg is vacuous" ;;
    *) [ -e "$FX/wt-other/.supervisor/run.lock" ] || grep -qxF -- "- [x] $REQ" "$FX/wt-other/$RF_REL" \
         && ok "AC14w mutation control: a --root <linked toplevel> closeout takes a second lock and runs past the engine's" \
         || no "AC14w mutant: not refused yet no second lock / check-off: $out" ;;
  esac
  bash "$HERE/run-lock.sh" release --owner "automate:$RUN_ID" --root "$P" >/dev/null
else
  no "AC14w mutant not built"
fi

co_body="$(awk '/^closeout\(\) \{/{s=1} s{print} s&&/^}/{exit}' "$TB" | grep -vE '^[[:space:]]*#')"
bad="$(grep -nE 'git (-C [^ ]+ )?(commit|reset|stash|merge)|branch -d |merge-base|pr merge|push' <<<"$co_body" || true)"
[ -n "$co_body" ] && [ -z "$bad" ] && ok "closeout never commits/resets/stashes/merges/pushes in the primary" || no "closeout body: $bad"
bad="$(grep -nE 'release [^#]*--session-id' <<<"$(grep -vE '^[[:space:]]*#' "$TB")" || true)"
[ -z "$bad" ] && ok "closeout releases with --owner only" || no "release forwards --session-id: $bad"

