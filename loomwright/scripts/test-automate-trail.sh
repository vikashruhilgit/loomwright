#!/usr/bin/env bash
# test-automate-trail.sh — self-tests for automate-trail.sh (the `/automate`
# engine's post-park lifecycle mutators), dispatched via automate-helpers.sh.
# Fixtures: a bare repo as `origin`, a primary clone, and a STUBBED `gh`
# (LOOMWRIGHT_GH_BIN) that answers `pr list` / `pr view` / `pr create` from files
# and logs its argv. Nothing real is pushed or merged. Exit 0 = all pass.
#
# Part A legs:
#   S. sidecar-check — three negatives (v2 REVIEW_HEAL_RESULT missing `rounds`,
#      one carrying `ready_sha`, a SUPERVISOR_RESULT whose risk_classification
#      lacks `reasons`) + a non-canonical channel + the positive control (the
#      committed item-10 sidecars, d8662b3, copied verbatim into this file).
#   D. dispatcher — automate-helpers.sh --help lists the three rows and the
#      header names the carve-out; sidecar-check/trail-pr dispatch.
#   T. trail-pr — commits ONLY trail paths (stray untracked + unrelated modified
#      tracked file absent), ledger = base + this run's lines only, failing
#      sidecar excluded + named, re-run opens no second PR, no-diff re-run
#      skips, a changed re-run pushes fast-forward to the same PR, gh failure /
#      gh absent / missing run file ⇒ one skipped line + exit 0, no worktree
#      leaked, never run-lock.sh / gh pr merge / force push; a gated mutant
#      (explicit add → `git add -A`) turns the stray-file assertion red.
#   M. post-merge pull (decision 4) — trail PR squash-merged into the fixture
#      remote ⇒ plain `git checkout main && git pull` succeeds with the live run
#      file and the ledger's other-run lines surviving as local modifications.
#   K. SKILL text — trail-pr precedes run-lock.sh release on every park path.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
H="$HERE/automate-helpers.sh"
T="$HERE/automate-trail.sh"
SKILL="$HERE/../skills/automate-loop/SKILL.md"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

TOP="$(mktemp -d "${TMPDIR:-/tmp}/test-automate-trail.XXXXXX")"
TOP="$(cd "$TOP" && pwd -P)"
cleanup_all() { rm -rf "$TOP"; }
trap cleanup_all EXIT

# ---- stub gh ---------------------------------------------------------------
STUBBIN="$TOP/bin"; mkdir -p "$STUBBIN"
cat > "$STUBBIN/gh" <<'STUB'
#!/usr/bin/env bash
# Stub gh: state lives in $GH_STUB_DIR (prs.json = array of {number,url,state,headRefName}).
set -u
d="$GH_STUB_DIR"; echo "$*" >> "$d/argv.log"
[ -f "$d/prs.json" ] || echo '[]' > "$d/prs.json"
case "${1:-} ${2:-}" in
  "pr list")
    [ -f "$d/pr-list-fail" ] && exit 1
    cat "$d/prs.json"; exit 0 ;;
  "pr create")
    [ -f "$d/pr-create-fail" ] && exit 1
    head=""; while [ $# -gt 0 ]; do [ "$1" = "--head" ] && head="${2:-}"; shift; done
    n=$(( $(jq 'length' "$d/prs.json") + 100 ))
    url="https://github.com/acme/widgets/pull/$n"
    jq --arg h "$head" --arg u "$url" --argjson n "$n" '. + [{number:$n,url:$u,state:"OPEN",headRefName:$h}]' "$d/prs.json" > "$d/prs.tmp" && mv "$d/prs.tmp" "$d/prs.json"
    echo "$url"; exit 0 ;;
  "pr view")
    key="${3:-}"
    # state-seq: one state per `pr view <url>` call, persisted into prs.json
    # (drives the merge watcher's OPEN → MERGED flip).
    case "$key" in https://*)
      if [ -s "$d/state-seq" ]; then
        nxt="$(head -n1 "$d/state-seq")"; tail -n +2 "$d/state-seq" > "$d/seq.tmp"; mv "$d/seq.tmp" "$d/state-seq"
        jq --arg h "$key" --arg s "$nxt" 'map(if .url == $h then .state = $s else . end)' "$d/prs.json" > "$d/prs.tmp" && mv "$d/prs.tmp" "$d/prs.json"
      fi ;;
    esac
    jq -e --arg h "$key" '[.[] | select(.headRefName == $h or .url == $h)] | last' "$d/prs.json" || exit 1
    exit 0 ;;
  "pr merge") echo "MERGE_CALLED $*" >> "$d/merge.log"; exit 0 ;;
esac
exit 0
STUB
chmod +x "$STUBBIN/gh"
export LOOMWRIGHT_GH_BIN="$STUBBIN/gh"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# Committed item-10 sidecars (git show d8662b3:<path>), copied verbatim.
RH_GOOD='## REVIEW_HEAL_RESULT
- schema_version: 2
- decision: READY
- termination_reason: converged
- iterations: 2
- rounds: 2
- fix_cycles: 1
- issues_fixed: 1
- remaining_issues: 0
- pr_url: "https://github.com/vikashruhilgit/loomwright/pull/301"
- notified: false
- channels_scanned: [reviews, reviewThreads, issue_comments, check_outputs]
- checks_waited: [ci, claude-review]
- findings_validated: 1
- findings_dismissed: 0
- sub_floor_fixed: []
- repeat_check_failure: false
- unresolved_bot_feedback: false
- rejected_instruction_like: 0
- checks_untrusted: []
- rules_gate: none'
SUP_GOOD='SUPERVISOR_RESULT:
  schema_version: 1
  task_id: automate-followups-10
  status: completed
  pr_url: https://github.com/vikashruhilgit/loomwright/pull/301
  branch: feature/automate-followups-10-rules-reach-standalone-review
  branch_base: main
  subtasks_completed: 1
  subtasks_failed: 0
  heal_loop_ran: true
  heal_iterations: 2
  heal_decision: PASS
  heal_fixable_issues_fixed: 1
  heal_remaining_issues: 0
  error: null
  summary: "Code Reviewer reads house rules itself (step 4a, Phase 4.5 dedupe); seam test covers the reviewer with D-mut/C-cov/C-mut; v15.113.0. Iter 1 FAIL (HIGH (C) vacuous) → fix 8f0a0ef → iter 2 PASS; 6 below-floor dismissed. red_team_advisory: disabled."
  cost_profile: null
  rubric_score: null
  ground_truth: {status: pass, checks_passed: 2, checks_total: 2}
  risk_classification: {high_risk: true, reasons: ["content: 11 changed line(s) matched *auth*", "path: loomwright/agents/code-reviewer.md matched agents/", "path: loomwright/commands/agent-help.md matched commands/", "path: loomwright/commands/code-reviewer.md matched commands/", "path: loomwright/commands/rules.md matched commands/", "path: loomwright/skills/rules/skill.md matched skills/"]}
  until_mergeable_dispatched: false'

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
r="$(bash "$H" sidecar-check "$SD/sup-good.md")"; [ "$r" = "ok $SD/sup-good.md" ] && ok "item-10 SUPERVISOR_RESULT passes" || no "sup-good: $r"
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
r="$(bash "$H" sidecar-check "$SD/absent.md")"; rc=$?
[ "$r" = "fail $SD/absent.md: file not found" ] && [ "$rc" -eq 0 ] && ok "missing file ⇒ fail line, exit 0" || no "absent: $r rc=$rc"

# =============================================================================
echo "== D. dispatcher =="
helpout="$(bash "$H" --help)"
for s in sidecar-check trail-pr closeout; do
  if grep -q "^  $s " <<<"$helpout"; then ok "--help lists $s"; else no "--help missing $s"; fi
done
if grep -q 'delegated to the sibling' "$H" && grep -q '`automate-trail.sh`, which is a git/`gh pr create` mutator' "$H"; then
  ok "helper header names the automate-trail.sh carve-out"
else
  no "helper header carve-out sentence missing"
fi
if grep -qE 'sidecar-check\|trail-pr\|closeout\) exec bash "\$\(dirname "\$0"\)/automate-trail.sh"' "$H"; then ok "dispatcher exec row present"; else no "dispatcher row missing"; fi

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
    printf '# req a\n## Status: done\n' > "$REQ"
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
new_fixture 1
out="$(cd "$P" && bash "$H" trail-pr ".supervisor/automate/$RUN_ID.md" --reason awaiting_merge)"; rc=$?
lines="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
case "$out" in "trail-pr: opened https://github.com/acme/widgets/pull/100"*) ok "first run opens a PR ($out)" ;; *) no "first run: $out" ;; esac
[ "$rc" -eq 0 ] && [ "$lines" = "1" ] && ok "exactly one line, exit 0" || no "rc=$rc lines=$lines"
BR="chore/$RUN_ID-trail-1"
names="$(git -C "$FX/origin.git" show --name-only --format= "refs/heads/$BR" 2>/dev/null | LC_ALL=C sort)"
want="$(printf '%s\n' ".supervisor/automate/$RUN_ID.md" ".supervisor/automate/$RUN_ID.review-heal-result.md" ".supervisor/jobs/done/brief-a.md" ".supervisor/postmortem/results.jsonl" "$REQ" | LC_ALL=C sort)"
[ "$names" = "$want" ] && ok "trail commit holds exactly the trail paths" || no "commit names: [$names] want [$want]"
case "$names" in *stray.txt*|*README*|*feat.txt*|*brief-other*|*brief-live*|*supervisor-result*) no "non-trail path committed" ;; *) ok "stray untracked + unrelated modified + unrelated/in-progress briefs absent" ;; esac
case "$out" in *"excluded .supervisor/automate/$RUN_ID.supervisor-result.md — risk_classification present without reasons"*) ok "failing sidecar named in the output line" ;; *) no "exclusion not named: $out" ;; esac
led="$(git -C "$FX/origin.git" show "refs/heads/$BR:.supervisor/postmortem/results.jsonl")"
if grep -q "old-run" <<<"$led" && grep -q "$RUN_ID" <<<"$led" && ! grep -q "other-run" <<<"$led"; then ok "ledger = base + this run's lines only"; else no "ledger content: $led"; fi
[ "$(git -C "$FX/origin.git" log -1 --format=%s "refs/heads/$BR")" = "chore(supervisor): $RUN_ID trail (awaiting_merge)" ] && ok "commit subject names run + reason" || no "subject"
wt_n="$(git -C "$P" worktree list --porcelain | grep -c '^worktree ')"
[ "$wt_n" = "1" ] && ok "temporary worktree removed" || no "worktrees leaked: $wt_n"
[ "$(git -C "$P" rev-parse --abbrev-ref HEAD)" = "feature/x" ] && ok "primary stays on its branch" || no "primary branch moved"

# AC4 idempotency
out2="$(cd "$P" && bash "$H" trail-pr ".supervisor/automate/$RUN_ID.md" --reason awaiting_merge)"
case "$out2" in "trail-pr: skipped — trail already up to date"*) ok "no-diff re-run skips" ;; *) no "no-diff re-run: $out2" ;; esac
[ "$(count_creates)" = "1" ] && ok "gh pr create called once after re-run" || no "create count $(count_creates)"
tip1="$(git -C "$FX/origin.git" rev-parse "refs/heads/$BR")"
echo "- t1 trail-pr: opened …" >> "$P/.supervisor/automate/$RUN_ID.md"
out3="$(cd "$P" && bash "$H" trail-pr ".supervisor/automate/$RUN_ID.md" --reason escalated)"
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
cp "$T" "$HERE/result_block_parser.py" "$HERE/brief-pointer.sh" "$HERE/worktree-salvage.sh" "$SPY/"
printf '#!/usr/bin/env bash\necho "$*" >> "%s/runlock.log"\n' "$SPY" > "$SPY/run-lock.sh"
out="$(cd "$P" && bash "$SPY/automate-trail.sh" trail-pr ".supervisor/automate/$RUN_ID.md" --reason limit_reached)"
case "$out" in "trail-pr: opened "*) ok "spy copy ran trail-pr ($out)" ;; *) no "spy run: $out" ;; esac
[ ! -f "$SPY/runlock.log" ] && ok "trail-pr never invokes run-lock.sh" || no "run-lock.sh was invoked"
code_lines="$(grep -vE '^[[:space:]]*#' "$T")"
bad="$(grep -E 'pr merge|push[^#]*(--force|--force-with-lease| -f |[[:space:]]\+)' <<<"$code_lines")"
[ -z "$bad" ] && ok "script has no gh pr merge / force push" || no "script contains merge/force-push: $bad"
bad="$(grep -E '(^|[^a-z-])timeout |sed -i|stat -c|date -d' <<<"$code_lines")"
[ -z "$bad" ] && ok "no timeout / GNU-only forms" || no "GNU-only / timeout form in script: $bad"
bash -n "$T" && ok "bash -n automate-trail.sh" || no "bash -n failed"

# gated mutant: explicit `git add -- <path>` → `git add -A` must make the stray file leak
new_fixture 3
MUT="$TOP/mut"; mkdir -p "$MUT"; cp "$SPY"/*.py "$SPY"/brief-pointer.sh "$SPY"/worktree-salvage.sh "$MUT/"
# (the mutant also copies stray.txt into its worktree so an -A add can see it)
sed -e 's|git -C "\$TRAIL_WT" add -- "\$p"|git -C "$TRAIL_WT" add -A|' \
    -e 's|mkdir -p "\$TRAIL_WT/\$(dirname "\$p")"|mkdir -p "$TRAIL_WT/$(dirname "$p")"; cp stray.txt "$TRAIL_WT/" 2>/dev/null|' \
    "$T" > "$MUT/automate-trail.sh"
if [ -s "$MUT/automate-trail.sh" ] && ! cmp -s "$T" "$MUT/automate-trail.sh" && bash -n "$MUT/automate-trail.sh"; then
  (cd "$P" && bash "$MUT/automate-trail.sh" trail-pr ".supervisor/automate/$RUN_ID.md" >/dev/null)
  mn="$(git -C "$FX/origin.git" show --name-only --format= "refs/heads/$BR" 2>/dev/null)"
  case "$mn" in *stray.txt*) ok "mutation control: an -A add leaks stray.txt (the AC3 assertion is load-bearing)" ;; *) no "mutant did not leak — assertion may be vacuous" ;; esac
else
  no "mutant not generated"
fi

# =============================================================================
echo "== K. SKILL wiring =="
grep -q '^### Trail PR at every park and at run end' "$SKILL" && ok "SKILL trail section present" || no "trail section missing"
for s in sidecar-check trail-pr closeout; do
  grep -qE "^\| \`$s\` \|" "$SKILL" && ok "§1.5 row $s" || no "§1.5 row $s missing"
done
# trail-pr precedes run-lock.sh release on the named lines
precedes() { # <regex identifying the line> <label>
  local line; line="$(grep -m1 -E "$1" "$SKILL")"
  local a="${line%%trail-pr*}" b="${line%%run-lock.sh release*}"
  if [ -n "$line" ] && [ "$a" != "$line" ] && [ "$b" != "$line" ] && [ "${#a}" -lt "${#b}" ]; then ok "$2: trail-pr before run-lock.sh release"; else no "$2: ordering not stated"; fi
}
precedes '^6\. \*\*CHECK OFF' "§6 step 6"
precedes '^   \*\*PICK-time token-ceiling check' "token_ceiling park"
precedes '^- \*\*Classified hit' "rate_limit park"
precedes '^- \*\*Safe mode \(default\):' "§9 awaiting_merge park"
precedes '^\*\*`ESCALATED` never merges' "§9 escalated park"
precedes '^Before the run-lock release' "Termination (done + limit_reached)"
sect="$(awk '/^### Trail PR at every park and at run end/{s=1;next} s&&/^##/{exit} s' "$SKILL")"
for pr in awaiting_merge escalated limit_reached rate_limit drain_died token_ceiling '## Status: done' run_lock_held resume_ambiguous; do
  grep -qF -- "$pr" <<<"$sect" && ok "trail section names $pr" || no "trail section missing $pr"
done

# =============================================================================
# Part B — closeout + merge watcher
# =============================================================================
PRURL="https://github.com/acme/widgets/pull/7"
RF_REL=".supervisor/automate/$RUN_ID.md"

# spy copy of the scripts dir: automate-helpers.sh is a logging shim that execs
# the real helper (renamed), and captures the run-lock meta while trail-pr runs;
# notify-desktop.sh / send-webhook.sh are counters. Everything else is real.
SPYD="$TOP/spyd"; mkdir -p "$SPYD"
cp "$HERE"/*.sh "$HERE"/*.py "$SPYD/"
mv "$SPYD/automate-helpers.sh" "$SPYD/automate-helpers.real.sh"
cat > "$SPYD/automate-helpers.sh" <<'SHIM'
#!/usr/bin/env bash
echo "$*" >> "$SPYLOG"
if [ "${1:-}" = trail-pr ]; then cat .supervisor/run.lock/meta >> "$SPYLOG.meta" 2>/dev/null; echo "--" >> "$SPYLOG.meta"; fi
exec bash "$(dirname "$0")/automate-helpers.real.sh" "$@"
SHIM
printf '#!/usr/bin/env bash\ncat >/dev/null\necho notify >> "$SPYLOG.notify"\nexit 0\n' > "$SPYD/notify-desktop.sh"
printf '#!/usr/bin/env bash\necho "$*" >> "$SPYLOG.webhook"\nexit 0\n' > "$SPYD/send-webhook.sh"
export SPYLOG="$TOP/spy.log"
spy_reset() { rm -f "$SPYLOG" "$SPYLOG.meta" "$SPYLOG.notify" "$SPYLOG.webhook"; }
spy_count() { grep -c "$1" "$2" 2>/dev/null || true; }

# closeout_fixture <n> [oid-override]: new_fixture, then a merged-PR world —
# feature/x pushed and SQUASH-merged into origin/main (a new commit, not the
# branch tip), the primary back on main with the PR's branch in its own
# worktree, plus an unrelated branch+worktree, and the feature PR in the stub.
closeout_fixture() {
  new_fixture "$1"
  ( cd "$P"
    git checkout -q -- README; rm -f stray.txt
    git push -q origin feature/x 2>/dev/null
    git checkout -q main
    git worktree add -q "$FX/wt-pr" feature/x 2>/dev/null
    git worktree add -q -b other "$FX/wt-other" main 2>/dev/null
  )
  git clone -q "$FX/origin.git" "$FX/merger" 2>/dev/null
  ( cd "$FX/merger" && git checkout -q main && git merge -q --squash origin/feature/x >/dev/null 2>&1 && git commit -qm "feat (#7)" && git push -q origin main 2>/dev/null )
  OID="${2:-$(git -C "$P" rev-parse feature/x)}"
  jq -n --arg u "$PRURL" --arg o "$OID" '[{number:7,url:$u,state:"MERGED",headRefName:"feature/x",headRefOid:$o}]' > "$GH_STUB_DIR/prs.json"
}
run_closeout() { (cd "$P" && bash "$SPYD/automate-helpers.sh" closeout "$RF_REL" "$REQ" "$PRURL" "$@"); }

echo "== C. closeout =="
closeout_fixture 4
(cd "$P" && bash "$H" trail-pr "$RF_REL" --reason awaiting_merge >/dev/null)   # stages trail blobs in the primary index
spy_reset
out="$(run_closeout)"; rc=$?
printf '%s\n' "$out" | sed 's/^/    | /'
[ "$rc" -eq 0 ] && ok "closeout exits 0" || no "closeout rc=$rc"
[ ! -d "$FX/wt-pr" ] && ok "AC9: the PR's worktree is removed" || no "AC9: wt-pr still present"
git -C "$P" rev-parse -q --verify refs/heads/feature/x >/dev/null && no "AC9: feature/x still present" || ok "AC9: the PR's local branch is deleted (squash-merged; tip == headRefOid)"
[ -d "$FX/wt-other" ] && git -C "$P" rev-parse -q --verify refs/heads/other >/dev/null && ok "AC9: unrelated branch + worktree untouched" || no "AC9: unrelated branch/worktree touched"
case "$out" in *"closeout: synced — main at "*) ok "sync: primary fast-forwarded over the staged trail paths" ;; *) no "sync line missing" ;; esac
[ "$(git -C "$P" rev-parse HEAD)" = "$(git -C "$FX/origin.git" rev-parse main)" ] && ok "primary main == origin/main" || no "primary not at origin/main"
grep -qxF -- "- [x] $REQ" "$P/$RF_REL" && ok "AC12: run file reads - [x] <item>" || no "AC12: item not checked off"
grep -qF '# skipped: done' "$P/$RF_REL" && no "AC12: '# skipped: done' written" || ok "AC12: never '# skipped: done'"
grep -qE "^trail-pr $P/$RF_REL --reason closeout\$" "$SPYLOG" && ok "AC12: closeout invokes trail-pr via the dispatcher (spy)" || no "AC12: trail-pr not invoked: $(cat "$SPYLOG" 2>/dev/null | tr '\n' '|')"
grep -qF '<!-- loomwright:requirement-closeout -->' "$P/$REQ" && grep -qF -- "- **PR:** $PRURL" "$P/$REQ" && grep -qF -- '- **Brief:** .supervisor/jobs/done/' "$P/$REQ" && ok "stamp: PASS-shape footer with the done/ brief" || no "stamp missing"
grep -q '^owner	automate-closeout:'"$RUN_ID"'$' "$SPYLOG.meta" && ok "trail-pr ran under the closeout's run lock" || no "lock meta during trail-pr: $(cat "$SPYLOG.meta" 2>/dev/null | tr '\n' '|')"
[ ! -d "$P/.supervisor/run.lock" ] && ok "run lock released after closeout" || no "run lock leaked"
grep -qE '^- .* closeout https://github.com/acme/widgets/pull/7: closeout: checked' "$P/$RF_REL" && ok "## Progress carries the step lines" || no "Progress lines missing"

echo "== C. closeout idempotent (AC11) =="
before_rf="$(cksum < "$P/$RF_REL")"; before_req="$(cksum < "$P/$REQ")"
before_trail="$(git -C "$FX/origin.git" for-each-ref --format='%(objectname)' 'refs/heads/chore/*')"
creates_before="$(count_creates)"
out2="$(run_closeout)"; rc=$?
printf '%s\n' "$out2" | sed 's/^/    | /'
badl="$(printf '%s\n' "$out2" | grep -v 'skipped — ' || true)"
[ -z "$badl" ] && [ "$rc" -eq 0 ] && ok "AC11: second run is all skipped lines, exit 0" || no "AC11: non-skipped line(s): $badl"
[ "$before_rf" = "$(cksum < "$P/$RF_REL")" ] && [ "$before_req" = "$(cksum < "$P/$REQ")" ] && ok "AC11: run file + requirement unchanged" || no "AC11: second run mutated files"
[ "$before_trail" = "$(git -C "$FX/origin.git" for-each-ref --format='%(objectname)' 'refs/heads/chore/*')" ] && [ "$creates_before" = "$(count_creates)" ] && ok "AC11: no push, no PR create on the second run" || no "AC11: second run pushed/created"
grep -q '^pr merge' "$GH_STUB_DIR/argv.log" && no "gh pr merge called" || ok "closeout never calls gh pr merge"

echo "== C. closeout guards (AC10, AC11) =="
closeout_fixture 5 "0000000000000000000000000000000000000000"
( cd "$P" && echo "edited readme" > README )
out="$(run_closeout)"
case "$out" in *"closeout: skipped — local tip "*" != merged head 000000000000 (feature/x kept)"*) ok "AC10: tip != headRefOid ⇒ branch kept + skipped" ;; *) no "AC10 tip: $out" ;; esac
git -C "$P" rev-parse -q --verify refs/heads/feature/x >/dev/null && ok "AC10: feature/x still present" || no "AC10: branch deleted despite tip mismatch"
case "$out" in *"closeout: skipped — uncommitted changes outside the trail paths (README)"*) ok "AC10: primary dirty outside trail paths ⇒ sync skipped" ;; *) no "AC10 dirty sync: $out" ;; esac

closeout_fixture 6
echo scratch > "$FX/wt-pr/wip.txt"
out="$(run_closeout)"
salv="$(ls -d "$P"/.supervisor/salvage/wt-pr-* 2>/dev/null | head -n1)"
[ -n "$salv" ] && [ -f "$salv/untracked/wip.txt" ] && ok "AC10: dirty worktree salvaged ($salv)" || no "AC10: no salvage dir"
[ -d "$FX/wt-pr" ] && ok "AC10: still-dirty worktree kept (decision 6 step 3: remove only when clean after salvage)" || no "AC10: dirty worktree removed"
case "$out" in *"closeout: skipped — kept worktree $FX/wt-pr still dirty after salvage"*) ok "AC10: kept line names the salvage" ;; *) no "AC10 kept line: $out" ;; esac
git -C "$P" rev-parse -q --verify refs/heads/feature/x >/dev/null && ok "branch in a kept worktree is not deleted" || no "branch deleted under a kept worktree"

closeout_fixture 7
jq '.[0].state = "OPEN"' "$GH_STUB_DIR/prs.json" > "$GH_STUB_DIR/p.tmp" && mv "$GH_STUB_DIR/p.tmp" "$GH_STUB_DIR/prs.json"
out="$(run_closeout)"
[ "$out" = "closeout: skipped — pr not merged (awaiting_merge)" ] && ok "AC10: OPEN ⇒ one skipped line" || no "AC10 OPEN: $out"
[ -d "$FX/wt-pr" ] && git -C "$P" rev-parse -q --verify refs/heads/feature/x >/dev/null && grep -qxF -- "- [ ] $REQ" "$P/$RF_REL" && ok "AC10: OPEN ⇒ nothing removed or checked off" || no "AC10: OPEN mutated state"
out="$(cd "$P" && LOOMWRIGHT_GH_BIN="$TOP/no-such-gh" bash "$H" closeout "$RF_REL" "$REQ" "$PRURL")"; rc=$?
[ "$out" = "closeout: skipped — gh unavailable" ] && [ "$rc" -eq 0 ] && ok "AC11: gh absent ⇒ skipped, exit 0" || no "gh absent: $out rc=$rc"
out="$(cd "$P" && bash "$H" closeout ".supervisor/automate/nope.md" "$REQ" "$PRURL")"; rc=$?
[ "$out" = "closeout: skipped — run file not found" ] && [ "$rc" -eq 0 ] && ok "missing run file ⇒ skipped, exit 0" || no "missing run file: $out rc=$rc"

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

co_body="$(awk '/^closeout\(\) \{/{s=1} s{print} s&&/^}/{exit}' "$T" | grep -vE '^[[:space:]]*#')"
bad="$(grep -nE 'git (-C [^ ]+ )?(commit|reset|stash|merge)|branch -d |merge-base|pr merge|push' <<<"$co_body" || true)"
[ -n "$co_body" ] && [ -z "$bad" ] && ok "closeout never commits/resets/stashes/merges/pushes in the primary" || no "closeout body: $bad"
bad="$(grep -nE 'release [^#]*--session-id' <<<"$(grep -vE '^[[:space:]]*#' "$T")" || true)"
[ -z "$bad" ] && ok "closeout releases with --owner only" || no "release forwards --session-id: $bad"

# =============================================================================
echo "== W. merge watcher =="
WATCH="$SPYD/automate-merge-watch.sh"
cp "$HERE/automate-merge-watch.sh" "$WATCH"
bash -n "$HERE/automate-merge-watch.sh" && ok "bash -n automate-merge-watch.sh" || no "bash -n watcher failed"
MARK=".supervisor/automate/$RUN_ID.merge-watch"

closeout_fixture 9
spy_reset
printf 'OPEN\nOPEN\nMERGED\n' > "$GH_STUB_DIR/state-seq"
jq '.[0].state = "OPEN"' "$GH_STUB_DIR/prs.json" > "$GH_STUB_DIR/p.tmp" && mv "$GH_STUB_DIR/p.tmp" "$GH_STUB_DIR/prs.json"
wout="$(cd "$P" && CLAUDECODE=1 LOOMWRIGHT_MERGE_WATCH_INTERVAL=0 LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=60 bash "$WATCH" "$RF_REL" "$REQ" "$PRURL" </dev/null 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "watcher exits 0" || no "watcher rc=$rc"
[ "$(spy_count '^closeout ' "$SPYLOG")" = "1" ] && ok "AC13: OPEN → MERGED ⇒ exactly one closeout" || no "AC13: closeout count $(spy_count '^closeout ' "$SPYLOG")"
[ "$(spy_count notify "$SPYLOG.notify")" = "1" ] && [ "$(spy_count 'automate_merge_watch' "$SPYLOG.webhook")" = "1" ] && ok "AC13: exactly one notify (desktop + webhook)" || no "AC13: notify count"
[ ! -d "$FX/wt-pr" ] && grep -qxF -- "- [x] $REQ" "$P/$RF_REL" && ok "watcher-driven closeout cleaned up + checked off" || no "watcher closeout: $wout"
grep -q '^pid_source	ppid$' "$SPYLOG.meta" && ok "AC14: watcher-driven closeout records pid_source ppid (CLAUDECODE unset by the watcher)" || no "pid_source: $(cat "$SPYLOG.meta" 2>/dev/null | tr '\n' '|')"
[ ! -e "$P/$MARK" ] && ok "AC13: marker gone after MERGED exit" || no "marker left after MERGED"

closeout_fixture 10
spy_reset
jq '.[0].state = "CLOSED"' "$GH_STUB_DIR/prs.json" > "$GH_STUB_DIR/p.tmp" && mv "$GH_STUB_DIR/p.tmp" "$GH_STUB_DIR/prs.json"
(cd "$P" && LOOMWRIGHT_MERGE_WATCH_INTERVAL=0 bash "$WATCH" "$RF_REL" "$REQ" "$PRURL" </dev/null >/dev/null 2>&1)
[ "$(spy_count '^closeout ' "$SPYLOG")" = "0" ] && [ -d "$FX/wt-pr" ] && git -C "$P" rev-parse -q --verify refs/heads/feature/x >/dev/null && ok "AC13: CLOSED ⇒ no closeout, no cleanup" || no "AC13: CLOSED cleaned up"
grep -qE "^- .* merge-watch: $REQ gone — $PRURL closed unmerged" "$P/$RF_REL" && ok "AC13: CLOSED ⇒ a gone Progress line" || no "AC13: gone line missing"
[ "$(spy_count notify "$SPYLOG.notify")" = "1" ] && [ ! -e "$P/$MARK" ] && ok "AC13: CLOSED ⇒ one notify, marker gone" || no "AC13: CLOSED notify/marker"

closeout_fixture 11
jq '.[0].state = "OPEN"' "$GH_STUB_DIR/prs.json" > "$GH_STUB_DIR/p.tmp" && mv "$GH_STUB_DIR/p.tmp" "$GH_STUB_DIR/prs.json"
t0="$(date +%s)"
(cd "$P" && LOOMWRIGHT_MERGE_WATCH_INTERVAL=1 LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=2 bash "$WATCH" "$RF_REL" "$REQ" "$PRURL" </dev/null >/dev/null 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ $(( $(date +%s) - t0 )) -lt 20 ] && ok "AC13: lifetime cap ⇒ clean exit" || no "AC13: cap exit rc=$rc"
grep -qE "^- .* merge-watch: lifetime cap \(2s\) reached watching $PRURL" "$P/$RF_REL" && ok "AC13: cap ⇒ a Progress line" || no "AC13: cap Progress line missing"
[ ! -e "$P/$MARK" ] && [ -d "$FX/wt-pr" ] && ok "AC13: cap ⇒ marker gone, nothing cleaned" || no "AC13: cap marker/cleanup"

# single instance: a live watcher blocks a second launch; a dead pid is reclaimed
( cd "$P" && LOOMWRIGHT_MERGE_WATCH_INTERVAL=1 LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=60 nohup bash "$WATCH" "$RF_REL" "$REQ" "$PRURL" </dev/null >"$TOP/w1.log" 2>&1 & )
i=0; while [ ! -s "$P/$MARK" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i+1)); done
wpid="$(awk -F'\t' '$1=="pid"{print $2}' "$P/$MARK" 2>/dev/null)"
out="$(cd "$P" && bash "$WATCH" "$RF_REL" "$REQ" "$PRURL" </dev/null 2>&1)"
[ -n "$wpid" ] && [ "$out" = "merge-watch: already running pid=$wpid" ] && ok "AC13: second launch ⇒ already running, no second poller" || no "AC13 second launch: '$out' (pid=$wpid)"
[ "$(awk -F'\t' '$1=="pid"{print $2}' "$P/$MARK" 2>/dev/null)" = "$wpid" ] && ok "marker still names the first watcher" || no "marker overwritten"
[ -n "$wpid" ] && kill "$wpid" 2>/dev/null
i=0; while [ -e "$P/$MARK" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i+1)); done
[ ! -e "$P/$MARK" ] && ok "AC13: marker gone after the watcher is terminated" || no "marker left after TERM"
( sleep 0 & echo $! > "$TOP/deadpid" ); sleep 0.2
printf 'pid\t%s\npr_url\t%s\nstarted\tx\n' "$(cat "$TOP/deadpid")" "$PRURL" > "$P/$MARK"
out="$(cd "$P" && LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=0 bash "$WATCH" "$RF_REL" "$REQ" "$PRURL" </dev/null 2>&1)"
case "$out" in *"merge-watch: started pid="*) ok "dead-pid marker is reclaimed" ;; *) no "dead-pid reclaim: $out" ;; esac
w_code="$(grep -vE '^[[:space:]]*#' "$HERE/automate-merge-watch.sh")"
bad="$(grep -nE 'pr merge|/autonomous|(^|[^a-z-])timeout |setsid|sed -i|stat -c|date -d' <<<"$w_code" || true)"
[ -z "$bad" ] && ok "watcher: no merge, no /autonomous, no timeout/setsid/GNU-only forms" || no "watcher forms: $bad"

echo "== K. SKILL wiring (Part B) =="
grep -qF 'automate-merge-watch.sh' "$SKILL" && ok "SKILL names automate-merge-watch.sh" || no "SKILL lacks the watcher"
step1="$(grep -m1 -E '^1\. \*\*RECONCILE' "$SKILL")"
a="${step1%%closeout*}"; b="${step1%%PICK*}"
if [ -n "$step1" ] && [ "$a" != "$step1" ] && grep -qF -- '--session-id' <<<"$step1" && [ "${#a}" -lt "${#b}" ]; then ok "AC14: §6 step 1 runs closeout --session-id before PICK"; else no "AC14: §6 step 1 closeout wiring"; fi
hits="$(grep -nE 're-checks the PR each tick|resumes once|resume[sd]? on merge' "$SKILL" "$HERE/../commands/automate.md" "$HERE/../docs/RESULT_SCHEMAS.md" || true)"
[ -z "$hits" ] && ok "AC14: decision-9 grep has no per-tick/auto-resume claim" || no "decision-9 hits: $hits"
grep -qF '/loop` re-invokes `/automate` each tick' "$SKILL" && ok "§12's accurate /loop tick sentence kept" || no "§12 /loop sentence changed"
grep -qF 'closeout' "$HERE/../commands/automate.md" && grep -qF 'trail-pr' "$HERE/../commands/automate.md" && ok "commands/automate.md mirrors the surface" || no "commands/automate.md surface missing"

echo
echo "test-automate-trail: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
