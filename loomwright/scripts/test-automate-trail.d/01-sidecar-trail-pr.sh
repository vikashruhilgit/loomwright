# =============================================================================
echo "== S. sidecar-check =="
SD="$TOP/sc"; mkdir -p "$SD"
printf '%s\n' "$RH_GOOD" > "$SD/rh-good.md"
printf '%s\n' "$SUP_GOOD" > "$SD/sup-good.md"
# Provenance of the positive control: equal to the committed bytes when reachable.
REPO="$(cd "$HERE/../.." && pwd)"
if git -C "$REPO" cat-file -e d8662b3 2>/dev/null; then
  if [ "$(git -C "$REPO" show d8662b3:.supervisor/automate/automate-2026-09-26-115755.review-heal-result.md)" = "$RH_GOOD" ] \
     && [ "$(git -C "$REPO" show d8662b3:.supervisor/automate/automate-2026-09-26-115755.supervisor-result.md)" = "$SUP_GOOD" ]; then
    ok "positive-control fixtures equal git show d8662b3 content"
  else
    no "positive-control fixtures drifted from d8662b3"
  fi
else
  echo "  note: d8662b3 not reachable (shallow checkout) — provenance leg skipped"
fi
r="$(bash "$H" sidecar-check "$SD/rh-good.md")"; [ "$r" = "ok $SD/rh-good.md" ] && ok "item-10 REVIEW_HEAL_RESULT passes" || no "rh-good: $r"
# automate-followups/20: the item-10 SUPERVISOR_RESULT is the requirement's own example —
# its `ground_truth` lacks `checked`, so the nested check now fails it.
r="$(bash "$H" sidecar-check "$SD/sup-good.md")"
[ "$r" = "fail $SD/sup-good.md: SUPERVISOR_RESULT ground_truth missing required key checked" ] \
  && ok "item-10 SUPERVISOR_RESULT (ground_truth without checked) fails" || no "sup-good: $r"
printf '%s\n' "$RH_GOOD" | grep -v '^- rounds:' > "$SD/rh-norounds.md"
r="$(bash "$H" sidecar-check "$SD/rh-norounds.md")"
case "$r" in "fail $SD/rh-norounds.md: "*"missing required key rounds") ok "v2 missing rounds fails" ;; *) no "missing rounds: $r" ;; esac
{ printf '%s\n' "$RH_GOOD"; echo '- ready_sha: 69698dbca64616657596c3ef54b0bf4762da4c8d'; } > "$SD/rh-readysha.md"
r="$(bash "$H" sidecar-check "$SD/rh-readysha.md")"
case "$r" in "fail $SD/rh-readysha.md: "*"non-schema key ready_sha") ok "ready_sha fails" ;; *) no "ready_sha: $r" ;; esac
printf '%s\n' "$SUP_GOOD" | sed 's/^  risk_classification: .*/  risk_classification: {high_risk: true}/' > "$SD/sup-noreasons.md"
r="$(bash "$H" sidecar-check "$SD/sup-noreasons.md")"
case "$r" in "fail $SD/sup-noreasons.md: risk_classification present without reasons") ok "risk_classification without reasons fails" ;; *) no "noreasons: $r" ;; esac
printf '%s\n' "$RH_GOOD" | sed 's/^- channels_scanned: .*/- channels_scanned: [checks, reviews, review_threads]/' > "$SD/rh-chan.md"
r="$(bash "$H" sidecar-check "$SD/rh-chan.md")"
case "$r" in "fail $SD/rh-chan.md: non-canonical channels_scanned token checks") ok "non-canonical channel fails" ;; *) no "channel: $r" ;; esac
# automate-followups/31: the five escalation_* keys are schema keys (RH_V2_ALLOWED), so a
# sidecar carrying them passes; a genuinely non-schema key still fails (ready_sha above).
{ printf '%s\n' "$RH_GOOD"; printf '%s\n' '- escalation_cause: check_pending' '- escalation_check: claude-review' \
    '- escalation_run_id: 37259136927' '- escalation_attempt: 1' '- escalation_sha: 1e35336'; } > "$SD/rh-escalation.md"
r="$(bash "$H" sidecar-check "$SD/rh-escalation.md")"
[ "$r" = "ok $SD/rh-escalation.md" ] && ok "escalation_* keys pass sidecar-check" || no "rh-escalation: $r"
{ printf '%s\n' "$RH_GOOD"; echo '- escalation_reason: check_pending'; } > "$SD/rh-escreason.md"
r="$(bash "$H" sidecar-check "$SD/rh-escreason.md")"
case "$r" in "fail $SD/rh-escreason.md: "*"non-schema key escalation_reason") ok "a non-schema escalation_reason key still fails" ;; *) no "escalation_reason: $r" ;; esac
r="$(bash "$H" sidecar-check "$SD/absent.md")"; rc=$?
[ "$r" = "fail $SD/absent.md: file not found" ] && [ "$rc" -eq 0 ] && ok "missing file ⇒ fail line, exit 0" || no "absent: $r rc=$rc"

# --- SN. nested-object key tables (automate-followups/20) ---------------------
# SUP_VALID: the item-10 block with a schema-complete ground_truth plus every other
# nested SUPERVISOR_RESULT object and list, flow and block style mixed.
SUP_VALID="$(printf '%s\n' "$SUP_GOOD" | sed 's/^  ground_truth: .*/  ground_truth: {checked: true, status: advisory_failures, checks_total: 2, checks_passed: 1, findings: [{check: "cmd:make test", detail: "exit 1", severity: advisory}]}/')
  contract_conformance:
    checked: true
    status: advisory_violations
    contracts_evaluated: 1
    violations: 1
    findings:
      - {subsystem: hooks, invariant: \"always exit 0\", severity: advisory, detail: \"exit 2 on a normal path\"}
  benchmark_result: {ran: true, status: pass, name: system-twin-selftest, metric: selftest_pass_count, value: 4, baseline: null, delta: null, unit: assertions}
  heal_dismissed:
    - {finding: \"a nit\", reason: nit, source: code_reviewer, severity: LOW}
    - {finding: \"old bug\", reason: pre_existing, source: code_reviewer}"
printf '%s\n' "$SUP_VALID" > "$SD/sn-sup-valid.md"
r="$(bash "$H" sidecar-check "$SD/sn-sup-valid.md")"
[ "$r" = "ok $SD/sn-sup-valid.md" ] && ok "SN: a schema-complete nested SUPERVISOR_RESULT passes" || no "sn-sup-valid: $r"
# The parse-miss benchmark shape (ran + status only) and an absent findings list are legal.
printf '%s\n' "$SUP_VALID" | sed -e 's/^  benchmark_result: .*/  benchmark_result: {ran: false, status: unverified}/' \
  -e 's/^  ground_truth: .*/  ground_truth: {checked: false, status: skipped, checks_total: 0, checks_passed: 0}/' > "$SD/sn-sup-min.md"
r="$(bash "$H" sidecar-check "$SD/sn-sup-min.md")"
[ "$r" = "ok $SD/sn-sup-min.md" ] && ok "SN: minimal benchmark_result / ground_truth without findings pass" || no "sn-sup-min: $r"
RH_VALID="$(printf '%s\n' "$RH_GOOD" | sed -e 's/^- sub_floor_fixed: .*/- sub_floor_fixed: [{finding: "typo", severity: LOW}]/' \
  -e 's/^- checks_untrusted: .*/- checks_untrusted: [{check: ci, reason: startup_failure, run_id: null}]/')
- dismissed: [{finding: \"stale\", reason: \"already fixed\", source: reviews}, {finding: \"x\", reason: \"y\", source: check_outputs, severity: INFO}]"
printf '%s\n' "$RH_VALID" > "$SD/sn-rh-valid.md"
r="$(bash "$H" sidecar-check "$SD/sn-rh-valid.md")"
[ "$r" = "ok $SD/sn-rh-valid.md" ] && ok "SN: a nested REVIEW_HEAL_RESULT (dismissed, checks_untrusted, sub_floor_fixed items) passes" || no "sn-rh-valid: $r"

# One negative per nested object / list item: <file>|<base>|<sed expr>|<expected reason>.
SN_NEG="$TOP/sn-neg.txt"
cat > "$SN_NEG" <<'SNEOF'
sn-gt-checked|SUP|s/{checked: true, status: advisory_failures/{status: advisory_failures/|SUPERVISOR_RESULT ground_truth missing required key checked
sn-gt-extra|SUP|s/checks_passed: 1, findings/checks_passed: 1, pass_rate: half, findings/|SUPERVISOR_RESULT ground_truth carries non-schema key pass_rate
sn-gt-shape|SUP|s/^  ground_truth: .*/  ground_truth: pass/|SUPERVISOR_RESULT ground_truth is not a mapping
sn-gt-finding|SUP|s/, detail: "exit 1", severity: advisory}/, severity: advisory}/|SUPERVISOR_RESULT ground_truth.findings[0] missing required key detail
sn-cc-violations|SUP|/^    violations: 1$/d|SUPERVISOR_RESULT contract_conformance missing required key violations
sn-cc-finding|SUP|s/invariant: "always exit 0", //|SUPERVISOR_RESULT contract_conformance.findings[0] missing required key invariant
sn-bench-status|SUP|s/{ran: true, status: pass, name/{ran: true, name/|SUPERVISOR_RESULT benchmark_result missing required key status
sn-rc-highrisk|SUP|s/{high_risk: true, reasons/{reasons/|SUPERVISOR_RESULT risk_classification missing required key high_risk
sn-hd-source|SUP|s/reason: pre_existing, source: code_reviewer}/reason: pre_existing}/|SUPERVISOR_RESULT heal_dismissed[1] missing required key source
sn-rh-dismissed|RH|s/reason: "already fixed", //|REVIEW_HEAL_RESULT dismissed[0] missing required key reason
sn-rh-untrusted|RH|s/, run_id: null}/}/|REVIEW_HEAL_RESULT checks_untrusted[0] missing required key run_id
sn-rh-subfloor|RH|s/^- sub_floor_fixed: .*/- sub_floor_fixed: [typo]/|REVIEW_HEAL_RESULT sub_floor_fixed[0] is not a mapping
sn-gt-passrate|SUP|s/^  ground_truth: .*/  ground_truth: {checked: true, status: pass, checks_total: 2, checks_passed: 2, pass_rate: "2\/2"}/|SUPERVISOR_RESULT ground_truth carries non-schema key pass_rate
sn-gt-skip-nochecked|SUP|s/^  ground_truth: .*/  ground_truth: {status: skipped}/|SUPERVISOR_RESULT ground_truth missing required key checked
sn-gt-skip-checkedtrue|SUP|s/^  ground_truth: .*/  ground_truth: {checked: true, status: skipped}/|SUPERVISOR_RESULT ground_truth missing required key checks_total
SNEOF
sn_build() {  # sn_build <base> <sed expr> <out>
  if [ "$1" = SUP ]; then printf '%s\n' "$SUP_VALID"; else printf '%s\n' "$RH_VALID"; fi | sed "$2" > "$3"
}
while IFS='|' read -r f base expr want; do
  [ -n "$f" ] || continue
  sn_build "$base" "$expr" "$SD/$f.md"
  if cmp -s "$SD/$f.md" "$SD/sn-$(echo "$base" | tr 'A-Z' 'a-z')-valid.md"; then
    no "SN $f: the sed changed nothing (fixture drifted)"; continue
  fi
  r="$(bash "$H" sidecar-check "$SD/$f.md")"
  [ "$r" = "fail $SD/$f.md: $want" ] && ok "SN $f ⇒ $want" || no "SN $f: got '$r'"
done < "$SN_NEG"

# Skip form (automate-followups/20 amendment): checked false + status skipped|unverified makes
# the counts/findings optional — the shape Phase 4.5 writes when nothing was checked.
{ printf '%s\n' "$SUP_GOOD" | sed 's/^  ground_truth: .*/  ground_truth: {checked: false, status: skipped}/'
  echo '  contract_conformance: {checked: false, status: unverified}'; } > "$SD/sn-sup-skip.md"
r="$(bash "$H" sidecar-check "$SD/sn-sup-skip.md")"
[ "$r" = "ok $SD/sn-sup-skip.md" ] && ok "SN: skip form {checked: false, status: skipped|unverified} without counts passes" || no "sn-sup-skip: $r"

# Skip-form mutants: each relaxes the skip rule differently; each leg it targets must turn red.
#   off   — no skip relaxation at all        ⇒ the skip-form positive reads fail
#   any   — relaxation ignores `checked`     ⇒ {checked: true, status: skipped} reads ok
#   nochk — any + `checked` also dropped     ⇒ {status: skipped} reads ok
sn_skip_mutant() {  # sn_skip_mutant <name> <sed program> → $TOP/sn-skip-<name>/automate-trail.sh
  local d="$TOP/sn-skip-$1"; mkdir -p "$d"; cp "$HERE/result_block_parser.py" "$d/"
  sed "$2" "$TB" > "$d/automate-trail.sh"
  cmp -s "$TB" "$d/automate-trail.sh" && { no "SN skip mutant $1: sed changed nothing"; return 1; }
  return 0
}
if sn_skip_mutant off 's/    if key in SKIP_OPTIONAL and isinstance/    if False and isinstance/'; then
  r="$(bash "$TOP/sn-skip-off/automate-trail.sh" sidecar-check "$SD/sn-sup-skip.md")"
  case "$r" in "fail "*) ok "SN skip mutant off: the skip-form leg is red without the rule ($r)" ;; *) no "SN skip mutant off: $r" ;; esac
fi
if sn_skip_mutant any 's/and R.as_bool(val.get("checked"))\[0\] is False/and True/'; then
  r="$(bash "$TOP/sn-skip-any/automate-trail.sh" sidecar-check "$SD/sn-gt-skip-checkedtrue.md")"
  [ "$r" = "ok $SD/sn-gt-skip-checkedtrue.md" ] && ok "SN skip mutant any: {checked: true, status: skipped} leg is red when checked is ignored" || no "SN skip mutant any: $r"
fi
if sn_skip_mutant nochk 's/and R.as_bool(val.get("checked"))\[0\] is False/and True/; s/if k not in SKIP_OPTIONAL\[key\]\]/if k not in SKIP_OPTIONAL[key] + ["checked"]]/'; then
  r="$(bash "$TOP/sn-skip-nochk/automate-trail.sh" sidecar-check "$SD/sn-gt-skip-nochecked.md")"
  [ "$r" = "ok $SD/sn-gt-skip-nochecked.md" ] && ok "SN skip mutant nochk: {status: skipped} leg is red when the skip form excuses checked" || no "SN skip mutant nochk: $r"
fi

# Mutation control: a scratch copy of automate-trail.sh whose NESTED loop iterates an empty
# table. Every SN negative must then read `ok` — so each leg above is red without the check.
SNM="$TOP/sn-mutant"; mkdir -p "$SNM"
cp "$HERE/result_block_parser.py" "$SNM/"
sed 's/in sorted(NESTED\[name\]\.items()):/in sorted({}.items()):/' "$TB" > "$SNM/automate-trail.sh"
if cmp -s "$TB" "$SNM/automate-trail.sh"; then
  no "SN mutant: the sed did not change automate-trail.sh (NESTED loop line moved?)"
else
  sn_mut_ok=0; sn_mut_n=0
  while IFS='|' read -r f base expr want; do
    [ -n "$f" ] || continue
    sn_mut_n=$((sn_mut_n+1))
    r="$(bash "$SNM/automate-trail.sh" sidecar-check "$SD/$f.md")"
    if [ "$r" = "ok $SD/$f.md" ]; then sn_mut_ok=$((sn_mut_ok+1)); else echo "  note: SN mutant $f: $r"; fi
  done < "$SN_NEG"
  if [ "$sn_mut_n" -gt 0 ] && [ "$sn_mut_ok" = "$sn_mut_n" ]; then
    ok "SN mutant (NESTED loop disabled): all $sn_mut_n nested negatives read ok — every SN leg is load-bearing"
  else
    no "SN mutant: only $sn_mut_ok/$sn_mut_n nested negatives read ok without the check"
  fi
  r="$(bash "$SNM/automate-trail.sh" sidecar-check "$SD/sup-good.md")"
  [ "$r" = "ok $SD/sup-good.md" ] && ok "SN mutant: the item-10 ground_truth-without-checked sidecar passes without the check (the #311 blind spot)" || no "SN mutant sup-good: $r"
fi

# =============================================================================
echo "== D. dispatcher =="
helpout="$(bash "$H" --help)"
for s in sidecar-check trail-pr closeout trail-unstage trail-gate; do
  if grep -q "^  $s " <<<"$helpout"; then ok "--help lists $s"; else no "--help missing $s"; fi
done
if grep -q 'delegated to the sibling' "$H" && grep -q '`automate-trail.sh`, which is a git/`gh pr create` mutator' "$H"; then
  ok "helper header names the automate-trail.sh carve-out"
else
  no "helper header carve-out sentence missing"
fi
if grep -qE 'sidecar-check\|trail-pr\|closeout\|trail-unstage\|trail-gate\) exec bash "\$\(dirname "\$0"\)/automate-trail.sh"' "$H"; then ok "dispatcher exec row present"; else no "dispatcher row missing"; fi

# =============================================================================
# fixture builder: bare origin + primary clone on a feature branch with trail state
RUN_ID="automate-2026-01-01-000000"
REQ=".supervisor/requirements/f/01-a.md"
new_fixture() {
  FX="$TOP/fx$1"; mkdir -p "$FX"
  git init -q --bare "$FX/origin.git"
  git -C "$FX/origin.git" symbolic-ref HEAD refs/heads/main
  git clone -q "$FX/origin.git" "$FX/primary" 2>/dev/null
  P="$FX/primary"
  ( cd "$P"
    git checkout -q -b main 2>/dev/null || true
    cat > .gitignore <<'GI'
.supervisor/*
!.supervisor/requirements/
!.supervisor/jobs/
.supervisor/jobs/*
!.supervisor/jobs/done/
!.supervisor/jobs/failed/
!.supervisor/automate/
.supervisor/automate/*
!.supervisor/automate/*.md
!.supervisor/postmortem/
.supervisor/postmortem/*
!.supervisor/postmortem/results.jsonl
GI
    mkdir -p .supervisor/requirements/f .supervisor/postmortem
    echo "# req a" > "$REQ"; echo "# req b" > .supervisor/requirements/f/02-b.md
    echo "base readme" > README
    echo '{"automate_key":"old-run\u001fx","source":"automate_drain"}' > .supervisor/postmortem/results.jsonl
    git add .gitignore README .supervisor/requirements .supervisor/postmortem/results.jsonl
    git commit -qm init; git push -q origin main 2>/dev/null
    git remote set-head origin main >/dev/null 2>&1
    git checkout -q -b feature/x; echo feat > feat.txt; git add feat.txt; git commit -qm feat
    mkdir -p .supervisor/automate .supervisor/jobs/done .supervisor/jobs/in-progress
    cat > ".supervisor/automate/$RUN_ID.md" <<RF
# Automate Run: fixture
## Status: paused
## Queue
- [ ] $REQ
- [x] .supervisor/requirements/f/02-b.md  # skipped: owner said so
## Current
- item: $REQ | status: awaiting_merge | pr: https://github.com/acme/widgets/pull/7 | branch: feature/x
- pause_reason: awaiting_merge
## Progress
- t0 picked $REQ
RF
    printf '# req a\n\nlocal notes (no done heading: Phase 4.5 stamps are set per leg)\n' > "$REQ"
    printf '# Brief\n## Environment\n- **Source requirement:** %s\n' "$REQ" > .supervisor/jobs/done/brief-a.md
    printf '# Brief\n## Environment\n- **Source requirement:** .supervisor/requirements/zz.md\n' > .supervisor/jobs/done/brief-other.md
    printf '# Brief\n- **Source requirement:** %s\n' "$REQ" > .supervisor/jobs/in-progress/brief-live.md
    printf '%s\n' "$RH_GOOD" > ".supervisor/automate/$RUN_ID.review-heal-result.md"
    printf '%s\n' "$SUP_GOOD" | sed 's/^  risk_classification: .*/  risk_classification: {high_risk: true}/' > ".supervisor/automate/$RUN_ID.supervisor-result.md"
    printf '{"automate_key":"%s\\u001f%s\\u001fpr7\\u001fautomate_drain\\u001fcomplete","source":"automate_drain"}\n' "$RUN_ID" "$REQ" >> .supervisor/postmortem/results.jsonl
    echo '{"automate_key":"other-run\u001fy","source":"automate_drain"}' >> .supervisor/postmortem/results.jsonl
    echo stray > stray.txt
    echo "edited readme" > README
  )
  export GH_STUB_DIR="$FX/gh"; mkdir -p "$GH_STUB_DIR"; echo '[]' > "$GH_STUB_DIR/prs.json"; : > "$GH_STUB_DIR/argv.log"
}
count_creates() { grep -c '^pr create' "$GH_STUB_DIR/argv.log" 2>/dev/null || true; }

# =============================================================================
echo "== T. trail-pr =="
RF_REL0=".supervisor/automate/$RUN_ID.md"
new_fixture 1
out="$(cd "$P" && bash "$H" trail-pr ".supervisor/automate/$RUN_ID.md" --reason closeout)"; rc=$?
lines="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
case "$out" in "trail-pr: opened https://github.com/acme/widgets/pull/100"*) ok "first run opens a PR ($out)" ;; *) no "first run: $out" ;; esac
[ "$rc" -eq 0 ] && [ "$lines" = "1" ] && ok "exactly one line, exit 0" || no "rc=$rc lines=$lines"
BR="chore/$RUN_ID-trail-1"
names="$(git -C "$FX/origin.git" show --name-only --format= "refs/heads/$BR" 2>/dev/null | env LC_ALL=C sort)"
want="$(printf '%s\n' ".supervisor/automate/$RUN_ID.md" ".supervisor/automate/$RUN_ID.review-heal-result.md" ".supervisor/jobs/done/brief-a.md" ".supervisor/postmortem/results.jsonl" "$REQ" | env LC_ALL=C sort)"
[ "$names" = "$want" ] && ok "trail commit holds exactly the trail paths" || no "commit names: [$names] want [$want]"
case "$names" in *stray.txt*|*README*|*feat.txt*|*brief-other*|*brief-live*|*supervisor-result*) no "non-trail path committed" ;; *) ok "stray untracked + unrelated modified + unrelated/in-progress briefs absent" ;; esac
case "$out" in *"excluded .supervisor/automate/$RUN_ID.supervisor-result.md — risk_classification present without reasons"*) ok "failing sidecar named in the output line" ;; *) no "exclusion not named: $out" ;; esac
led="$(git -C "$FX/origin.git" show "refs/heads/$BR:.supervisor/postmortem/results.jsonl")"
if grep -q "old-run" <<<"$led" && grep -q "$RUN_ID" <<<"$led" && ! grep -q "other-run" <<<"$led"; then ok "ledger = base + this run's lines only"; else no "ledger content: $led"; fi
[ "$(git -C "$FX/origin.git" log -1 --format=%s "refs/heads/$BR")" = "chore(supervisor): $RUN_ID trail (closeout)" ] && ok "commit subject names run + reason" || no "subject"
wt_n="$(git -C "$P" worktree list --porcelain | grep -c '^worktree ')"
[ "$wt_n" = "1" ] && ok "temporary worktree removed" || no "worktrees leaked: $wt_n"
[ "$(git -C "$P" rev-parse --abbrev-ref HEAD)" = "feature/x" ] && ok "primary stays on its branch" || no "primary branch moved"

# AC4 idempotency
out2="$(cd "$P" && bash "$H" trail-pr ".supervisor/automate/$RUN_ID.md" --reason closeout)"
case "$out2" in "trail-pr: skipped — trail already up to date"*) ok "no-diff re-run skips" ;; *) no "no-diff re-run: $out2" ;; esac
[ "$(count_creates)" = "1" ] && ok "gh pr create called once after re-run" || no "create count $(count_creates)"
tip1="$(git -C "$FX/origin.git" rev-parse "refs/heads/$BR")"
echo "- t1 trail-pr: opened …" >> "$P/.supervisor/automate/$RUN_ID.md"
out3="$(cd "$P" && bash "$H" trail-pr ".supervisor/automate/$RUN_ID.md" --reason done)"
case "$out3" in "trail-pr: pushed https://github.com/acme/widgets/pull/100"*) ok "changed re-run pushes to the open PR" ;; *) no "changed re-run: $out3" ;; esac
[ "$(count_creates)" = "1" ] && ok "still one gh pr create" || no "create count $(count_creates)"
tip2="$(git -C "$FX/origin.git" rev-parse "refs/heads/$BR")"
if [ "$tip1" != "$tip2" ] && git -C "$FX/origin.git" merge-base --is-ancestor "$tip1" "$tip2"; then ok "push was a fast-forward"; else no "not a fast-forward"; fi
if grep -q 'pr merge' "$GH_STUB_DIR/argv.log" || [ -f "$GH_STUB_DIR/merge.log" ]; then no "gh pr merge was called"; else ok "gh pr merge never called"; fi

# =============================================================================
echo "== M. post-merge pull (decision 4) =="
MC="$FX/merger"; git clone -q "$FX/origin.git" "$MC" 2>/dev/null
( cd "$MC" && git checkout -q main && git merge -q --squash "origin/$BR" >/dev/null && git commit -qm "squash trail" && git push -q origin main 2>/dev/null )
echo "- t2 later progress (live file keeps changing)" >> "$P/.supervisor/automate/$RUN_ID.md"
pull_out="$(cd "$P" && git checkout -q main 2>&1 && git pull -q 2>&1)"; prc=$?
[ "$prc" -eq 0 ] && ok "plain git checkout main && git pull succeeds" || no "pull failed: $pull_out"
[ "$(git -C "$P" rev-parse HEAD)" = "$(git -C "$FX/origin.git" rev-parse main)" ] && ok "primary main == merged origin/main" || no "main not synced"
grep -q 't2 later progress' "$P/.supervisor/automate/$RUN_ID.md" && ok "live run-file bytes survive" || no "run file lost local lines"
grep -q 'other-run' "$P/.supervisor/postmortem/results.jsonl" && ok "other-run ledger lines survive locally" || no "ledger lost local lines"
[ -f "$P/stray.txt" ] && ok "stray file untouched" || no "stray file removed"

# =============================================================================
echo "== O. crash-recovery orphan: remote trail branch with NO linked PR =="
# A crash between trail-pr's push and its `gh pr create` leaves
# chore/<run_id>-trail-<n> on the remote with no PR. The next trail-pr must
# REUSE that branch (never push trail-<n+1>) and open exactly one PR for it —
# both with nothing new to push and with a new change to push first.
for omode in nodiff changed; do
  if [ "$omode" = "nodiff" ]; then new_fixture 41; else new_fixture 42; fi
  BR="chore/$RUN_ID-trail-1"
  (cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason closeout >/dev/null)
  git -C "$FX/origin.git" rev-parse -q --verify "refs/heads/$BR" >/dev/null && ok "[$omode] setup: $BR pushed" || no "[$omode] setup: $BR not pushed"
  otip1="$(git -C "$FX/origin.git" rev-parse "refs/heads/$BR" 2>/dev/null)"
  echo '[]' > "$GH_STUB_DIR/prs.json"; : > "$GH_STUB_DIR/argv.log"   # the crash: branch pushed, no PR
  [ "$omode" = "changed" ] && echo "- t1 parked again after the crash" >> "$P/$RF_REL0"
  out="$(cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason done)"; rc=$?
  case "$out" in "trail-pr: opened https://github.com/acme/widgets/pull/"*) [ "$rc" -eq 0 ] && ok "[$omode] orphan re-run opens a PR, exit 0 ($out)" || no "[$omode] rc=$rc" ;; *) no "[$omode] orphan re-run: $out" ;; esac
  [ "$(count_creates)" = "1" ] && ok "[$omode] exactly one gh pr create" || no "[$omode] create count $(count_creates)"
  grep -q -- "--head $BR " "$GH_STUB_DIR/argv.log" && ok "[$omode] the PR is opened for the orphan branch $BR" || no "[$omode] pr create head: $(grep '^pr create' "$GH_STUB_DIR/argv.log")"
  [ -z "$(git -C "$FX/origin.git" for-each-ref "refs/heads/chore/$RUN_ID-trail-2")" ] && ok "[$omode] no trail-2 branch pushed" || no "[$omode] trail-2 pushed"
  otip2="$(git -C "$FX/origin.git" rev-parse "refs/heads/$BR" 2>/dev/null)"
  if [ "$omode" = "nodiff" ]; then
    [ "$otip1" = "$otip2" ] && ok "[$omode] orphan tip unchanged (nothing new to push)" || no "[$omode] orphan tip moved"
  else
    if [ "$otip1" != "$otip2" ] && git -C "$FX/origin.git" merge-base --is-ancestor "$otip1" "$otip2"; then ok "[$omode] new change fast-forwarded onto the orphan branch"; else no "[$omode] orphan push not a fast-forward"; fi
    grep -q 'parked again after the crash' < <(git -C "$FX/origin.git" show "refs/heads/$BR:$RF_REL0") && ok "[$omode] orphan tip carries the new run-file bytes" || no "[$omode] new bytes not pushed"
  fi
done

# =============================================================================
echo "== U. PICK-time trail-unstage (the next item's commit carries no trail path) =="
new_fixture 12
(cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason closeout >/dev/null)
pre="$(git -C "$P" diff --cached --name-only)"
[ -n "$pre" ] && ok "trail-pr left trail paths staged (the hazard this leg guards)" || no "nothing staged after trail-pr"
[ -s "$P/.supervisor/automate/$RUN_ID.trail-staged" ] && ok "trail-pr recorded the staged blobs in <run_id>.trail-staged" || no "trail-staged record missing"
git -C "$P" check-ignore -q ".supervisor/automate/$RUN_ID.trail-staged" && ok "the record is gitignored (not *.md)" || no "record not gitignored"
out="$(cd "$P" && bash "$H" trail-unstage "$RF_REL0")"; rc=$?
case "$out" in "trail-unstage: unstaged "*" path(s) — "*) ok "trail-unstage prints one unstaged line ($out)" ;; *) no "trail-unstage: $out" ;; esac
[ "$rc" -eq 0 ] && [ -z "$(git -C "$P" diff --cached --name-only)" ] && ok "index clean after trail-unstage, exit 0" || no "still staged: $(git -C "$P" diff --cached --name-only | tr '\n' ' ')"
[ -f "$P/$RF_REL0" ] && grep -q 't0 picked' "$P/$RF_REL0" && [ -f "$P/.supervisor/jobs/done/brief-a.md" ] && ok "working copies untouched" || no "trail-unstage touched working copies"
names="$(cd "$P" && git checkout -q -b feature/next && echo n > new.txt && git add new.txt && git commit -qm next && git show --name-only --format= HEAD)"
[ "$names" = "new.txt" ] && ok "next item's commit (checkout -b, add, plain commit) holds exactly new.txt" || no "next commit swept: [$names]"
out="$(cd "$P" && bash "$H" trail-unstage "$RF_REL0")"
[ "$out" = "trail-unstage: skipped — nothing staged" ] && ok "trail-unstage re-run: skipped — nothing staged" || no "re-run: $out"
out="$(cd "$P" && bash "$H" trail-unstage ".supervisor/automate/nope.md")"; rc=$?
[ "$out" = "trail-unstage: skipped — run file not found" ] && [ "$rc" -eq 0 ] && ok "missing run file ⇒ skipped, exit 0" || no "missing run file: $out"

# =============================================================================
echo "== B2. park → PICK un-stage → next park re-stages EVERY trail path (hand pull after merge) =="
# The reused trail PR carries paths from BOTH pushes; the second trail-pr must
# re-stage all of them (from the trail-branch tip, never the working copy), in
# the pushed mode AND in the no-diff "already up to date" skip.
for b2mode in pushed nodiff; do
  if [ "$b2mode" = "pushed" ]; then new_fixture 21; else new_fixture 22; fi
  BR="chore/$RUN_ID-trail-1"
  (cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason closeout >/dev/null)
  (cd "$P" && bash "$H" trail-unstage "$RF_REL0" >/dev/null)
  [ -z "$(git -C "$P" diff --cached --name-only)" ] && ok "[$b2mode] PICK un-stage cleared the index" || no "[$b2mode] still staged after un-stage"
  if [ "$b2mode" = "pushed" ]; then
    echo "- t1 parked again" >> "$P/$RF_REL0"
    out="$(cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason done)"
    case "$out" in "trail-pr: pushed "*) ok "[$b2mode] second park pushes to the reused PR" ;; *) no "[$b2mode] second park: $out" ;; esac
  else
    out="$(cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason done)"
    case "$out" in "trail-pr: skipped — trail already up to date"*) ok "[$b2mode] second park is the no-diff skip" ;; *) no "[$b2mode] second park: $out" ;; esac
  fi
  tip="$(git -C "$P" rev-parse "refs/remotes/origin/$BR")"
  want="$(git -C "$P" diff --name-only "$(git -C "$P" merge-base origin/main "$tip")" "$tip" | env LC_ALL=C sort)"
  got="$(git -C "$P" diff --cached --name-only | env LC_ALL=C sort)"
  [ -n "$want" ] && [ "$got" = "$want" ] && ok "[$b2mode] every path the trail PR carries is staged again" || no "[$b2mode] staged [$got] want [$want]"
  bad=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ "$(git -C "$P" ls-files -s -- "$p" | awk '{print $2}')" = "$(git -C "$P" rev-parse "$tip:$p")" ] || bad="$bad $p"
  done <<EOF
$want
EOF
  [ -z "$bad" ] && ok "[$b2mode] index holds the trail-TIP blobs" || no "[$b2mode] index != tip for:$bad"
  if [ "$b2mode" = "nodiff" ]; then
    recn="$(wc -l < "$P/.supervisor/automate/$RUN_ID.trail-staged" | tr -d ' ')"
    idx1="$(git -C "$P" ls-files -s | env LC_ALL=C sort)"
    (cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason done >/dev/null 2>&1) || true
    recn2="$(wc -l < "$P/.supervisor/automate/$RUN_ID.trail-staged" | tr -d ' ')"
    [ "$recn" = "$recn2" ] && [ "$idx1" = "$(git -C "$P" ls-files -s | env LC_ALL=C sort)" ] && ok "[$b2mode] re-run is idempotent (same index, no duplicate record lines)" || no "[$b2mode] re-run changed state (record $recn -> $recn2)"
  fi
  echo "- t9 live edit after the push" >> "$P/$RF_REL0"
  [ "$(git -C "$P" ls-files -s -- "$RF_REL0" | awk '{print $2}')" != "$(git -C "$P" hash-object -- "$RF_REL0")" ] && ok "[$b2mode] live local edit not staged" || no "[$b2mode] live edit staged"
  MC="$FX/merger"; git clone -q "$FX/origin.git" "$MC" 2>/dev/null
  ( cd "$MC" && git checkout -q main && git merge -q --squash "origin/$BR" >/dev/null && git commit -qm "squash trail" && git push -q origin main 2>/dev/null )
  pull_out="$(cd "$P" && git checkout -q main 2>&1 && git pull -q 2>&1)"; prc=$?
  [ "$prc" -eq 0 ] && ok "[$b2mode] hand git checkout main && git pull succeeds after merging the reused trail PR" || no "[$b2mode] hand pull refused: $pull_out"
  grep -q 't9 live edit' "$P/$RF_REL0" && ok "[$b2mode] live run-file bytes survive" || no "[$b2mode] live bytes lost"
done
# trail-unstage clears the union of the record and today's candidates: a
# recorded path that is no longer a candidate is still unstaged.
new_fixture 23
(cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason closeout >/dev/null)
NC=".supervisor/jobs/done/brief-a.md"
grep -qxF -- "$NC" < <(git -C "$P" diff --cached --name-only) && ok "done brief staged by trail-pr" || no "done brief not staged"
printf '# Brief\n## Environment\n- **Source requirement:** .supervisor/requirements/zz.md\n' > "$P/$NC"
case "$(cd "$P" && bash "$H" trail-unstage "$RF_REL0" >/dev/null; git -C "$P" diff --cached --name-only)" in *"$NC"*) no "recorded non-candidate brief left staged" ;; *) ok "brief re-pointed away is still unstaged (from the record)" ;; esac
[ -z "$(git -C "$P" diff --cached --name-only)" ] && ok "trail-unstage cleared the recorded non-candidate path too" || no "left staged: $(git -C "$P" diff --cached --name-only | tr '\n' ' ')"

# =============================================================================
echo "== V0. portable 3.2 parse guard (runs on ANY bash, incl. CI's bash 5) =="
# macOS /bin/bash 3.2 cannot parse an apostrophe inside the BODY of a heredoc
# (quoted `<<'X'` or not) that is opened inside a `$(` command substitution —
# the exact trap fixed in 866529f (rc=2 for every subcommand). Leg V below proves
# 3.2 directly but is skipped where no 3.x binary exists (CI's ubuntu runner),
# so this static scan carries the guard there. Honest limit: it only sees a
# heredoc whose `$(` is on the SAME line as the `<<` opener.
heredoc_apos_in_comsub() {  # prints file:line of each offending body line
  awk '
    inbody {
      t = $0; if (strip) sub(/^\t+/, "", t)
      if (t == tag) { inbody = 0; next }
      if (index($0, "\047")) print FILENAME ":" FNR ": " $0
      next
    }
    /\$\(/ && /(^|[^<])<<-?[ \t]*[\047"\\]?[A-Za-z_][A-Za-z0-9_]*/ {
      r = $0; sub(/^.*\$\(/, "", r)
      if (!match(r, /(^|[^<])<<-?[ \t]*[\047"\\]?[A-Za-z_][A-Za-z0-9_]*/)) next
      op = substr(r, RSTART, RLENGTH); sub(/^[^<]/, "", op)
      strip = (substr(op, 3, 1) == "-")
      tag = op; sub(/^<<-?[ \t]*[\047"\\]?/, "", tag)
      inbody = 1
    }
  ' "$@"
}
hd_bad="$(heredoc_apos_in_comsub "$TB" "$HERE/automate-merge-watch.sh")"
[ -z "$hd_bad" ] && ok "no apostrophe in a heredoc body opened inside \$( (automate-trail.sh, automate-merge-watch.sh)" || no "3.2-unparseable heredoc body: $hd_bad"
HDM="$TOP/heredoc-mut"; mkdir -p "$HDM"
# mutation control: re-inject an apostrophe into the first body line of the
# python heredoc inside sidecar-check's $( — the 866529f regression.
awk 'done == 0 && prev ~ /\$\(python3 .*<</ { print "# it" "\047" "s back"; done = 1 } { print; prev = $0 }' "$TB" > "$HDM/automate-trail.sh"
if [ -s "$HDM/automate-trail.sh" ] && ! cmp -s "$TB" "$HDM/automate-trail.sh"; then
  hd_mut="$(heredoc_apos_in_comsub "$HDM/automate-trail.sh")"
  [ -n "$hd_mut" ] && ok "mutation control: an apostrophe injected into the \$( heredoc body IS flagged" || no "mutant not flagged — guard is vacuous"
else
  no "heredoc mutant not generated"
fi

echo "== V. macOS bash 3.2 (the child is really 3.2, not a Homebrew bash) =="
B32=""
for cand in /bin/bash /usr/local/bin/bash3 /opt/bash3/bin/bash; do
  [ -x "$cand" ] || continue
  [ "$("$cand" -c 'echo ${BASH_VERSINFO[0]}' 2>/dev/null)" = "3" ] && { B32="$cand"; break; }
done
if [ -z "$B32" ]; then
  echo "  (no bash 3.x on this host — 3.2 legs not applicable)"
else
  for f in "$TB" "$HERE/automate-merge-watch.sh" "$HERE/automate-helpers.sh" "$0"; do
    "$B32" -n "$f" 2>/dev/null && ok "$B32 -n $(basename "$f")" || no "$B32 cannot parse $(basename "$f")"
  done
  B32DIR="$TOP/bash32"; mkdir -p "$B32DIR"; ln -sf "$B32" "$B32DIR/bash"
  new_fixture 24
  out="$(cd "$P" && PATH="$B32DIR:$PATH" bash -c 'echo ${BASH_VERSINFO[0]}')"
  [ "$out" = "3" ] && ok "3.2 bash is first on PATH for the legs below" || no "PATH bash is $out"
  out="$(cd "$P" && PATH="$B32DIR:$PATH" bash "$H" sidecar-check ".supervisor/automate/$RUN_ID.review-heal-result.md")"; rc=$?
  [ "$out" = "ok .supervisor/automate/$RUN_ID.review-heal-result.md" ] && [ "$rc" -eq 0 ] && ok "3.2: sidecar-check ok, exit 0" || no "3.2 sidecar-check: $out rc=$rc"
  out="$(cd "$P" && PATH="$B32DIR:$PATH" bash "$H" trail-pr "$RF_REL0" --reason closeout)"; rc=$?
  case "$out" in "trail-pr: opened "*) [ "$rc" -eq 0 ] && ok "3.2: trail-pr opens a PR, exit 0" || no "3.2 trail-pr rc=$rc" ;; *) no "3.2 trail-pr: $out" ;; esac
  out="$(cd "$P" && PATH="$B32DIR:$PATH" bash "$H" trail-unstage "$RF_REL0")"; rc=$?
  case "$out" in "trail-unstage: unstaged "*) [ "$rc" -eq 0 ] && ok "3.2: trail-unstage, exit 0" || no "3.2 trail-unstage rc=$rc" ;; *) no "3.2 trail-unstage: $out" ;; esac
  out="$(cd "$P" && PATH="$B32DIR:$PATH" bash "$H" closeout "$RF_REL0" "$REQ" https://github.com/acme/widgets/pull/7)"; rc=$?
  [ "$rc" -eq 0 ] && [ -n "$out" ] && ok "3.2: closeout runs (guarded), exit 0" || no "3.2 closeout rc=$rc out=$out"
fi

# =============================================================================
echo "== T. fail-safe legs =="
new_fixture 2
touch "$GH_STUB_DIR/pr-list-fail"
out="$(cd "$P" && bash "$H" trail-pr ".supervisor/automate/$RUN_ID.md")"; rc=$?
case "$out" in "trail-pr: skipped — gh pr list failed"*) ok "gh failure ⇒ skipped line" ;; *) no "gh fail: $out" ;; esac
[ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = "1" ] && ok "gh failure: one line, exit 0" || no "gh fail rc=$rc"
[ -z "$(git -C "$FX/origin.git" for-each-ref 'refs/heads/chore/')" ] && ok "gh failure: nothing pushed" || no "pushed despite gh failure"
rm -f "$GH_STUB_DIR/pr-list-fail"
out="$(cd "$P" && LOOMWRIGHT_GH_BIN="$TOP/no-such-gh" bash "$H" trail-pr ".supervisor/automate/$RUN_ID.md")"; rc=$?
[ "$out" = "trail-pr: skipped — gh unavailable" ] && [ "$rc" -eq 0 ] && ok "gh absent ⇒ skipped, exit 0" || no "gh absent: $out rc=$rc"
out="$(cd "$P" && bash "$H" trail-pr ".supervisor/automate/nope.md")"; rc=$?
[ "$out" = "trail-pr: skipped — run file not found" ] && [ "$rc" -eq 0 ] && ok "missing run file ⇒ skipped, exit 0" || no "missing: $out"

# run-lock spy: a copy of the script beside a spy run-lock.sh
SPY="$TOP/spy"; mkdir -p "$SPY"
cp "$T" "$HERE/result_block_parser.py" "$HERE/brief-pointer.sh" "$HERE/worktree-salvage.sh" "$SPY/"; cp -R "$HERE/automate-trail.d" "$SPY/"
printf '#!/usr/bin/env bash\necho "$*" >> "%s/runlock.log"\n' "$SPY" > "$SPY/run-lock.sh"
out="$(cd "$P" && bash "$SPY/automate-trail.sh" trail-pr ".supervisor/automate/$RUN_ID.md" --reason done)"
case "$out" in "trail-pr: opened "*) ok "spy copy ran trail-pr ($out)" ;; *) no "spy run: $out" ;; esac
[ ! -f "$SPY/runlock.log" ] && ok "trail-pr never invokes run-lock.sh" || no "run-lock.sh was invoked"
code_lines="$(grep -vE '^[[:space:]]*#' "$TB")"
bad="$(grep -E 'pr merge|push[^#]*(--force|--force-with-lease| -f |[[:space:]]\+)' <<<"$code_lines")"
[ -z "$bad" ] && ok "script has no gh pr merge / force push" || no "script contains merge/force-push: $bad"
bad="$(grep -E '(^|[^a-z-])timeout |sed -i|stat -c|date -d' <<<"$code_lines")"
[ -z "$bad" ] && ok "no timeout / GNU-only forms" || no "GNU-only / timeout form in script: $bad"
bash -n "$TB" && ok "bash -n automate-trail.sh" || no "bash -n failed"

# gated mutant: explicit `git add -- <path>` → `git add -A` must make the stray file leak
new_fixture 3
MUT="$TOP/mut"; mkdir -p "$MUT"; cp "$SPY"/*.py "$SPY"/brief-pointer.sh "$SPY"/worktree-salvage.sh "$MUT/"
# (the mutant also copies stray.txt into its worktree so an -A add can see it)
sed -e 's|git -C "\$TRAIL_WT" add -- "\$p"|git -C "$TRAIL_WT" add -A|' \
    -e 's|mkdir -p "\$TRAIL_WT/\$(dirname "\$p")"|mkdir -p "$TRAIL_WT/$(dirname "$p")"; cp stray.txt "$TRAIL_WT/" 2>/dev/null|' \
    "$TB" > "$MUT/automate-trail.sh"
if [ -s "$MUT/automate-trail.sh" ] && ! cmp -s "$TB" "$MUT/automate-trail.sh" && bash -n "$MUT/automate-trail.sh"; then
  (cd "$P" && bash "$MUT/automate-trail.sh" trail-pr ".supervisor/automate/$RUN_ID.md" >/dev/null)
  mn="$(git -C "$FX/origin.git" show --name-only --format= "refs/heads/$BR" 2>/dev/null)"
  case "$mn" in *stray.txt*) ok "mutation control: an -A add leaks stray.txt (the AC3 assertion is load-bearing)" ;; *) no "mutant did not leak — assertion may be vacuous" ;; esac
else
  no "mutant not generated"
fi

# =============================================================================
echo "== K. SKILL wiring =="
grep -q '^### Trail PR after merge and at run end$' "$SKILL" && ok "SKILL trail section present (after merge and at run end)" || no "trail section missing"
OLDH="Trail PR at every"" park"   # split so this file is not a hit of its own sweep
hits="$(grep -rnF "$OLDH" "$HERE/.." 2>/dev/null || true)"
[ -z "$hits" ] && ok "old heading referenced nowhere under loomwright/" || no "stale old-heading refs: $hits"
for s in sidecar-check trail-pr closeout trail-unstage trail-gate; do
  grep -qE "^\| \`$s\` \|" "$SKILL" && ok "§1.5 row $s" || no "§1.5 row $s missing"
done
# The three triggers: trail-pr precedes run-lock.sh release where the loop runs it.
precedes() { # <regex identifying the line> <label>
  local line; line="$(grep -m1 -E "$1" "$SKILL")"
  local a="${line%%trail-pr*}" b="${line%%run-lock.sh release*}"
  if [ -n "$line" ] && [ "$a" != "$line" ] && [ "$b" != "$line" ] && [ "${#a}" -lt "${#b}" ]; then ok "$2: trail-pr before run-lock.sh release"; else no "$2: ordering not stated"; fi
}
precedes '^6\. \*\*CHECK OFF' "§6 step 6 (skip/abandon check-off + done)"
precedes '^On the \*\*`## Status: done`\*\* exit ONLY' "Termination (done)"
grep -qE '^6\. \*\*CHECK OFF.*`# skipped:`/`# abandoned:`.*`## Status: done`.*no park path runs it' "$SKILL" && ok "§6 step 6 scopes trail-pr to skip/abandon + done, no park" || no "§6 step 6 trail scope"
grep -qE '^1\. \*\*RECONCILE.*`# skipped:`/`# abandoned:` by a human.*trail-pr <runfile> --reason skipped\|abandoned.*BEFORE PICK' "$SKILL" && ok "RECONCILE runs trail-pr for a human skip/abandon, before PICK" || no "RECONCILE human skip trigger missing"
grep -qE '\*\*trail\*\* via `automate-helpers.sh trail-pr <runfile> --reason closeout`' "$SKILL" && ok "closeout steps end with trail-pr --reason closeout" || no "closeout trail step missing"
co_fn="$(awk '/^closeout\(\) \{/{s=1} s{print} s&&/^}/{exit}' "$TB" | grep -vE '^[[:space:]]*#')"
ln_gate="$(grep -n 'reconcile-item' <<<"$co_fn" | head -n1 | cut -d: -f1)"
ln_trail="$(grep -n 'trail-pr' <<<"$co_fn" | head -n1 | cut -d: -f1)"
[ -n "$ln_gate" ] && [ -n "$ln_trail" ] && [ "$ln_gate" -lt "$ln_trail" ] && ok "script: closeout calls trail-pr only after its reconcile-item merge gate" || no "closeout gate/trail order ($ln_gate/$ln_trail)"
# No park path calls trail-pr: each park line says so, and no `trail-pr --reason <park>` anywhere.
no_trail_on() { # <regex identifying the park line> <label>
  local line; line="$(grep -m1 -E "$1" "$SKILL")"
  if [ -n "$line" ] && ! grep -qF 'trail-pr --reason' <<<"$line" && grep -qiE 'no `trail-pr`|without a trail' <<<"$line"; then ok "$2: no trail-pr at this park"; else no "$2: park line still runs trail-pr (or does not say it does not)"; fi
}
no_trail_on '^   \*\*PICK-time token-ceiling check' "token_ceiling park"
no_trail_on '^- \*\*Classified hit' "rate_limit park"
no_trail_on '^   \*\*PICK-time trail gate' "trail_pr_open park"
no_trail_on '^   \*\*PICK-time run-lock acquire' "live_lane park (PICK-time lane guard)"
no_trail_on '^- \*\*Safe mode \(default\):' "§9 awaiting_merge park"
no_trail_on '^\*\*`ESCALATED` never merges' "§9 escalated park"
grep -qE '^On the \*\*`## Status: done`\*\* exit ONLY.*the `limit_reached` exit is a park and releases the lock without a trail' "$SKILL" && ok "Termination limit_reached: no trail-pr at this park" || no "Termination limit_reached still trails"
hits="$(grep -nE 'trail-pr --reason (awaiting_merge|escalated|rate_limit|drain_died|token_ceiling|limit_reached)' "$SKILL" "$CMD_ALL" "$TB" "$H" "$HERE/automate-merge-watch.sh" || true)"
[ -z "$hits" ] && ok "no trail-pr --reason <park_reason> anywhere (SKILL, command, scripts)" || no "park-reason trail calls: $hits"
sect="$(awk '/^### Trail PR after merge and at run end/{s=1;next} s&&/^##/{exit} s' "$SKILL")"
when="$(grep -m1 -F -- '- **When — this is the ONE authoritative trigger list' <<<"$sect")"
for t in '`--reason closeout`' '`--reason done`' '`--reason skipped`' '`--reason abandoned`' 'MERGED'; do
  grep -qF -- "$t" <<<"$when" && ok "trigger list names $t" || no "trigger list missing $t"
done
nopark="${when#*No park calls it:\*\*}"
[ "$nopark" != "$when" ] && ok "trigger list carries the one 'No park calls it' park-path list" || no "no-park list missing"
for pr in awaiting_merge escalated rate_limit drain_died token_ceiling trail_pr_open limit_reached run_lock_held resume_ambiguous; do
  grep -qF -- "\`$pr\`" <<<"$nopark" && ok "no-park list names $pr" || no "no-park list missing $pr"
done
grep -qF -- '`live_lane`' <<<"$nopark" && ok "no-park list names live_lane" || no "no-park list missing live_lane"
grep -qF -- '- **Evidence-gated stamps' <<<"$sect" && ok "trail section documents the evidence gate" || no "evidence-gate bullet missing"
eg="$(grep -m1 -F -- '- **Evidence-gated stamps' <<<"$sect")"
for t in '`is_done`' '`## Status: done_with_escalation — ABANDONED (- [x] <path>  # abandoned: <reason>)`' 'merely contains' '### Outcome' 'Outcomes Rubric' '`[]()<>`' '`; retracted <path>`' 'never stages a gate-excluded path' 'transient `gh pr view` failure'; do
  grep -qF -- "$t" <<<"$eg" && ok "evidence-gate bullet names $t" || no "evidence-gate bullet missing $t"
done
ln_gate="$(grep -n '^   \*\*PICK-time trail gate' "$SKILL" | head -n1 | cut -d: -f1)"
ln_unst="$(grep -n '^   \*\*PICK-time trail un-stage' "$SKILL" | head -n1 | cut -d: -f1)"
[ -n "$ln_gate" ] && [ -n "$ln_unst" ] && [ "$ln_gate" -lt "$ln_unst" ] && ok "§6 step 1: the trail gate precedes the trail un-stage" || no "§6 step 1 gate/un-stage order ($ln_gate/$ln_unst)"
s8="$(awk '/^## §8 /{s=1;next} s&&/^## /{exit} s' "$SKILL")"
for t in 'or this run'"'"'s own trail PR is open' '`trail_pr_open`' '`mergeStateStatus: BEHIND`' '(a) Refresh a READY-but-BEHIND PR' '(c) Exempt `.supervisor/**`-only changes' 'not possible' 'Honest limits.'; do
  grep -qF -- "$t" <<<"$s8" && ok "§8 names $t" || no "§8 missing $t"
done
grep -qF '`trail-gate`' "$HERE/../commands/automate.md" && ok "commands/automate.md per-item loop names trail-gate" || no "commands/automate.md missing trail-gate"
grep -qF -- '- **Committing a done stamp for unmerged work.**' "$SKILL" && ok "Anti-Pattern: committing a done stamp for unmerged work" || no "anti-pattern missing"
grep -qF 'never at a park' "$HERE/../commands/automate.md" && ok "commands/automate.md trail bullet: never at a park" || no "commands/automate.md trail bullet stale"

