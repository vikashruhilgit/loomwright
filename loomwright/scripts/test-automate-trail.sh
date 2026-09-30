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
#   O. crash-recovery orphan — a remote chore/<run_id>-trail-<n> with no PR is
#      REUSED (no trail-<n+1>), with and without a new change, and exactly one
#      PR is opened for it.
#   U. PICK-time trail-unstage — after trail-pr the trail paths are staged and
#      recorded (gitignored `<run_id>.trail-staged`); trail-unstage clears the
#      index (working copies untouched), then `checkout -b` + `add new.txt` +
#      plain `git commit` holds exactly new.txt; re-run / missing run file skip.
#   B2. park → PICK un-stage → next park (pushed, and the no-diff skip) re-stages
#      EVERY path the reused trail PR carries, from the trail-branch tip (a live
#      local edit stays unstaged; no duplicate record lines); after the owner
#      merges it, a hand `git checkout main && git pull` succeeds. trail-unstage
#      clears a recorded path that is no longer a candidate.
#   V0. portable 3.2 parse guard — a static scan (any bash) for an apostrophe
#      in a heredoc body opened inside `$(` (the 866529f trap), with a
#      mutation control; carries the guard where leg V has no 3.x binary.
#   V. bash 3.2 — `/bin/bash -n` (when it is 3.x) on both new scripts, the helper
#      and this file; sidecar-check / trail-pr / trail-unstage / closeout run
#      with a 3.2 `bash` first on PATH, so the child is not a Homebrew bash.
#   K. SKILL text — trail-after-merge (v15.114.2): trail-pr runs only in
#      closeout (after its merge gate), at `## Status: done` and on a
#      skip/abandon check-off (each before the lock release); NO park path
#      (awaiting_merge/escalated/rate_limit/drain_died/token_ceiling/
#      limit_reached) calls it; old heading referenced nowhere.
#
# Part B legs:
#   C. closeout — squash-merged fixture PR (a new commit on origin/main, not the
#      branch tip): the PR's worktree + local branch removed, an unrelated
#      branch + worktree untouched, main fast-forwarded over trail-pr's staged
#      paths, stamp + `- [x]` (never `# skipped: done`), trail-pr invoked via the
#      dispatcher (spy) under the closeout lock; second run all `skipped`, no
#      mutation/push; guards (tip != headRefOid, dirty worktree salvaged + kept,
#      OPEN, primary dirty outside trail paths, gh absent, missing run file);
#      RECONCILE re-entry (--session-id re-enters `automate:<run_id>`, which
#      survives; without it ⇒ `skipped — run lock held`). After a PICK
#      un-stage over a merged trail PR, closeout's sync still fast-forwards (it
#      re-stages the recorded landed blobs); a no-record control refuses.
#      A head-branch worktree whose HEAD != headRefOid is kept with its
#      gitignored .env intact (matching tip ⇒ removed); a refused pull restores
#      the re-staged index entries (mutant without the restore = control); a
#      Queue item naming a tracked source file is never committed by trail-pr.
#   W. merge watcher — OPEN → MERGED ⇒ one closeout + one notify (pid_source
#      ppid in the lock meta), CLOSED ⇒ `gone` line + no cleanup, lifetime cap,
#      single instance + TERM + dead-pid reclaim, marker gone on every exit;
#      a transient `gh unavailable` closeout skip is retried (one successful
#      closeout + one notify); a terminal guard skip ⇒ Progress line + failure
#      notify, never the success notify. A launch for ANOTHER PR of the same
#      run replaces the live watcher promptly (interruptible nap; Progress line;
#      no notify from the replaced one); a live marker pid that is not our
#      watcher is never signalled (reclaimed as stale); MERGED seen + transient
#      closeout skips until the cap ⇒ failure notify + a Progress line naming
#      the merge and the last skip reason.
#   E. evidence-gated stamps (decision 2) — a sentinel-led done /
#      done_with_escalation requirement stamp (and a done/ brief's Outcome PR)
#      rides only when its PR reads MERGED: OPEN, CLOSED, gh failing, a stamp
#      naming no PR ⇒ excluded + named; unstamped ⇒ committed with no gh call;
#      a skipped item's done stamp for a CLOSED PR ⇒ excluded; a mutant without
#      the _evidence_gate call commits the OPEN-PR stamp (control).
#   D3. checkout contract re-examined for trail-after-merge (decision 3), from
#      closeout's own trail (primary on main): (i) trail-unstage still needed
#      (control: the next commit sweeps the run file); (ii) _stage_tip still
#      needed for the owner's hand pull (control: neutered ⇒ refuses); (iii)
#      the .trail-staged re-stage still needed for closeout #2's sync after a
#      PICK un-stage (control: no record ⇒ refuses). All KEPT.
#   K. SKILL text (Part B) — watcher named, §6 step 1 closeout --session-id
#      before PICK, decision-9 grep clean, commands/automate.md surface.

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
    [ -f "$d/pr-view-fail" ] && exit 1
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
  "auth status")
    # auth-fail-once: one transient `gh auth status` failure (closeout's gh guard)
    if [ -f "$d/auth-fail-once" ]; then rm -f "$d/auth-fail-once"; exit 1; fi
    exit 0 ;;
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
for s in sidecar-check trail-pr closeout trail-unstage; do
  if grep -q "^  $s " <<<"$helpout"; then ok "--help lists $s"; else no "--help missing $s"; fi
done
if grep -q 'delegated to the sibling' "$H" && grep -q '`automate-trail.sh`, which is a git/`gh pr create` mutator' "$H"; then
  ok "helper header names the automate-trail.sh carve-out"
else
  no "helper header carve-out sentence missing"
fi
if grep -qE 'sidecar-check\|trail-pr\|closeout\|trail-unstage\) exec bash "\$\(dirname "\$0"\)/automate-trail.sh"' "$H"; then ok "dispatcher exec row present"; else no "dispatcher row missing"; fi

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
RF_REL0=".supervisor/automate/$RUN_ID.md"
new_fixture 1
out="$(cd "$P" && bash "$H" trail-pr ".supervisor/automate/$RUN_ID.md" --reason closeout)"; rc=$?
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
  want="$(git -C "$P" diff --name-only "$(git -C "$P" merge-base origin/main "$tip")" "$tip" | LC_ALL=C sort)"
  got="$(git -C "$P" diff --cached --name-only | LC_ALL=C sort)"
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
    idx1="$(git -C "$P" ls-files -s | LC_ALL=C sort)"
    (cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason done >/dev/null 2>&1) || true
    recn2="$(wc -l < "$P/.supervisor/automate/$RUN_ID.trail-staged" | tr -d ' ')"
    [ "$recn" = "$recn2" ] && [ "$idx1" = "$(git -C "$P" ls-files -s | LC_ALL=C sort)" ] && ok "[$b2mode] re-run is idempotent (same index, no duplicate record lines)" || no "[$b2mode] re-run changed state (record $recn -> $recn2)"
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
hd_bad="$(heredoc_apos_in_comsub "$T" "$HERE/automate-merge-watch.sh")"
[ -z "$hd_bad" ] && ok "no apostrophe in a heredoc body opened inside \$( (automate-trail.sh, automate-merge-watch.sh)" || no "3.2-unparseable heredoc body: $hd_bad"
HDM="$TOP/heredoc-mut"; mkdir -p "$HDM"
# mutation control: re-inject an apostrophe into the first body line of the
# python heredoc inside sidecar-check's $( — the 866529f regression.
awk 'done == 0 && prev ~ /\$\(python3 .*<</ { print "# it" "\047" "s back"; done = 1 } { print; prev = $0 }' "$T" > "$HDM/automate-trail.sh"
if [ -s "$HDM/automate-trail.sh" ] && ! cmp -s "$T" "$HDM/automate-trail.sh"; then
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
  for f in "$T" "$HERE/automate-merge-watch.sh" "$HERE/automate-helpers.sh" "$0"; do
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
cp "$T" "$HERE/result_block_parser.py" "$HERE/brief-pointer.sh" "$HERE/worktree-salvage.sh" "$SPY/"
printf '#!/usr/bin/env bash\necho "$*" >> "%s/runlock.log"\n' "$SPY" > "$SPY/run-lock.sh"
out="$(cd "$P" && bash "$SPY/automate-trail.sh" trail-pr ".supervisor/automate/$RUN_ID.md" --reason done)"
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
grep -q '^### Trail PR after merge and at run end$' "$SKILL" && ok "SKILL trail section present (after merge and at run end)" || no "trail section missing"
OLDH="Trail PR at every"" park"   # split so this file is not a hit of its own sweep
hits="$(grep -rnF "$OLDH" "$HERE/.." 2>/dev/null || true)"
[ -z "$hits" ] && ok "old heading referenced nowhere under loomwright/" || no "stale old-heading refs: $hits"
for s in sidecar-check trail-pr closeout trail-unstage; do
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
co_fn="$(awk '/^closeout\(\) \{/{s=1} s{print} s&&/^}/{exit}' "$T" | grep -vE '^[[:space:]]*#')"
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
no_trail_on '^- \*\*Safe mode \(default\):' "§9 awaiting_merge park"
no_trail_on '^\*\*`ESCALATED` never merges' "§9 escalated park"
grep -qE '^On the \*\*`## Status: done`\*\* exit ONLY.*the `limit_reached` exit is a park and releases the lock without a trail' "$SKILL" && ok "Termination limit_reached: no trail-pr at this park" || no "Termination limit_reached still trails"
hits="$(grep -nE 'trail-pr --reason (awaiting_merge|escalated|rate_limit|drain_died|token_ceiling|limit_reached)' "$SKILL" "$HERE/../commands/automate.md" "$T" "$H" "$HERE/automate-merge-watch.sh" || true)"
[ -z "$hits" ] && ok "no trail-pr --reason <park_reason> anywhere (SKILL, command, scripts)" || no "park-reason trail calls: $hits"
sect="$(awk '/^### Trail PR after merge and at run end/{s=1;next} s&&/^##/{exit} s' "$SKILL")"
when="$(grep -m1 -F -- '- **When — this is the ONE authoritative trigger list' <<<"$sect")"
for t in '`--reason closeout`' '`--reason done`' '`--reason skipped`' '`--reason abandoned`' 'MERGED'; do
  grep -qF -- "$t" <<<"$when" && ok "trigger list names $t" || no "trigger list missing $t"
done
nopark="${when#*No park calls it:\*\*}"
[ "$nopark" != "$when" ] && ok "trigger list carries the one 'No park calls it' park-path list" || no "no-park list missing"
for pr in awaiting_merge escalated rate_limit drain_died token_ceiling limit_reached run_lock_held resume_ambiguous; do
  grep -qF -- "\`$pr\`" <<<"$nopark" && ok "no-park list names $pr" || no "no-park list missing $pr"
done
grep -qF -- '- **Evidence-gated stamps' <<<"$sect" && ok "trail section documents the evidence gate" || no "evidence-gate bullet missing"
grep -qF -- '- **Committing a done stamp for unmerged work.**' "$SKILL" && ok "Anti-Pattern: committing a done stamp for unmerged work" || no "anti-pattern missing"
grep -qF 'never at a park' "$HERE/../commands/automate.md" && ok "commands/automate.md trail bullet: never at a park" || no "commands/automate.md trail bullet stale"

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
(cd "$P" && bash "$H" trail-pr "$RF_REL" --reason closeout >/dev/null)   # stages trail blobs in the primary index
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

echo "== C. closeout after a PICK un-stage (decision 4 kept) =="
# trail PR squash-merged, then trail-unstage (as PICK runs it), then the live
# run file gains bytes: closeout's sync must still fast-forward — it re-stages
# the recorded trail blobs that landed on origin/main right before its pull.
for variant in record no-record; do
  if [ "$variant" = record ]; then closeout_fixture 13; else closeout_fixture 14; fi
  (cd "$P" && bash "$H" trail-pr "$RF_REL" --reason closeout >/dev/null)
  TM="$FX/tmerger"; git clone -q "$FX/origin.git" "$TM" 2>/dev/null
  ( cd "$TM" && git checkout -q main && git merge -q --squash "origin/chore/$RUN_ID-trail-1" >/dev/null && git commit -qm "squash trail" && git push -q origin main 2>/dev/null )
  (cd "$P" && bash "$H" trail-unstage "$RF_REL" >/dev/null)
  echo "- t9 live progress after the un-stage" >> "$P/$RF_REL"
  [ "$variant" = no-record ] && rm -f "$P/.supervisor/automate/$RUN_ID.trail-staged"
  out="$(run_closeout)"
  if [ "$variant" = record ]; then
    [ -z "$(printf '%s' "$out" | grep 'git pull --ff-only refused')" ] && case "$out" in *"closeout: synced — main at "*) true ;; *) false ;; esac \
      && ok "after un-stage: closeout's sync fast-forwards over the merged trail" || no "after un-stage sync: $out"
    [ "$(git -C "$P" rev-parse HEAD)" = "$(git -C "$FX/origin.git" rev-parse main)" ] && ok "after un-stage: primary main == origin/main" || no "after un-stage: main not synced"
    grep -q 't9 live progress' "$P/$RF_REL" && grep -q 'other-run' "$P/.supervisor/postmortem/results.jsonl" && ok "after un-stage: live run-file bytes + other-run ledger lines survive" || no "after un-stage: local bytes lost"
  else
    case "$out" in *"closeout: skipped — git pull --ff-only refused"*) ok "control: without the record the same pull refuses (the re-stage is load-bearing)" ;; *) no "control did not refuse: $out" ;; esac
  fi
done

echo "== C. closeout: a self-staged trail path that is no longer a candidate =="
# park1 commits a good review-heal sidecar → PICK trail-unstage → the sidecar is
# rewritten and now FAILS sidecar-check → park2 pushes (sidecar excluded) but
# _stage_tip re-stages its tip blob (AM). That entry is this run's own trail
# (in the trail-staged record), so closeout's sync must not call it "outside";
# a genuinely foreign modification in the same world must still refuse.
SC=".supervisor/automate/$RUN_ID.review-heal-result.md"
for variant in own foreign; do
  if [ "$variant" = own ]; then closeout_fixture 15; else closeout_fixture 16; fi
  (cd "$P" && bash "$H" trail-pr "$RF_REL" --reason closeout >/dev/null)
  (cd "$P" && bash "$H" trail-unstage "$RF_REL" >/dev/null)
  echo "not a result block" > "$P/$SC"
  echo "- t5 parked again" >> "$P/$RF_REL"
  out="$(cd "$P" && bash "$H" trail-pr "$RF_REL" --reason done)"
  case "$out" in "trail-pr: pushed "*"excluded $SC"*) ok "[$variant] second park pushes with the sidecar excluded" ;; *) no "[$variant] second park: $out" ;; esac
  case "$(git -C "$P" status --porcelain --untracked-files=no -- "$SC")" in "AM $SC") ok "[$variant] sidecar is self-staged (AM) from the trail tip" ;; *) no "[$variant] sidecar status: $(git -C "$P" status --porcelain -- "$SC")" ;; esac
  [ "$variant" = foreign ] && ( cd "$P" && echo "foreign edit" > README )
  out="$(run_closeout)"
  if [ "$variant" = own ]; then
    case "$out" in *"outside the trail paths"*) no "own: self-staged sidecar counted as outside: $out" ;; *"closeout: synced — main at "*) ok "own: closeout syncs over its own self-staged non-candidate sidecar" ;; *) no "own: sync line: $out" ;; esac
    [ "$(git -C "$P" rev-parse HEAD)" = "$(git -C "$FX/origin.git" rev-parse main)" ] && ok "own: primary main == origin/main" || no "own: main not synced"
  else
    case "$out" in *"closeout: skipped — uncommitted changes outside the trail paths (README)"*) ok "foreign: a foreign modification still refuses, and only it is named" ;; *) no "foreign: $out" ;; esac
  fi
done

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

echo "== C. closeout 3a: a head-branch worktree at another tip is kept (M1) =="
# `git worktree remove` (no --force) deletes GITIGNORED content, which
# worktree-salvage.sh skips by design; a same-named branch reused for other work
# (worktree HEAD != headRefOid) must be kept with its gitignored .env intact.
for variant in moved match; do
  if [ "$variant" = moved ]; then closeout_fixture 31; else closeout_fixture 32; fi
  mkdir -p "$P/.git/info"; echo ".env" >> "$P/.git/info/exclude"
  echo "SECRET=1" > "$FX/wt-pr/.env"
  git -C "$FX/wt-pr" check-ignore -q .env && ok "[$variant] setup: .env is gitignored in the PR worktree" || no "[$variant] .env not ignored"
  [ "$variant" = moved ] && ( cd "$FX/wt-pr" && echo more > more.txt && git add more.txt && git commit -qm "other work, same branch name" )
  out="$(run_closeout)"
  if [ "$variant" = moved ]; then
    [ -d "$FX/wt-pr" ] && [ "$(cat "$FX/wt-pr/.env" 2>/dev/null)" = "SECRET=1" ] && ok "moved: worktree at another tip kept, gitignored .env intact" || no "moved: worktree/.env lost"
    case "$out" in *"closeout: skipped — kept worktree $FX/wt-pr (tip "*" != merged head "*) ok "moved: the kept line names the tip mismatch" ;; *) no "moved: kept line: $out" ;; esac
    git -C "$P" rev-parse -q --verify refs/heads/feature/x >/dev/null && ok "moved: branch at another tip kept" || no "moved: branch deleted"
  else
    [ ! -d "$FX/wt-pr" ] && ok "match: worktree at the merged head is removed" || no "match: worktree kept: $out"
  fi
done

echo "== C. closeout: a refused pull restores the re-staged index entries (L6) =="
# After a PICK un-stage over a merged trail PR, closeout re-stages the landed
# blobs right before its pull; when that pull refuses (a local commit diverges
# main), the index must go back to its prior state. trail-pr is stubbed out so
# its own checkout-contract staging does not mask the assertion; a mutant
# without the restore call is the control.
L6D="$TOP/l6d"; mkdir -p "$L6D"; cp "$SPYD"/*.sh "$SPYD"/*.py "$L6D/"
cat > "$L6D/automate-helpers.sh" <<'SHIM'
#!/usr/bin/env bash
if [ "${1:-}" = trail-pr ]; then echo "trail-pr: skipped — stubbed"; exit 0; fi
exec bash "$(dirname "$0")/automate-helpers.real.sh" "$@"
SHIM
L6M="$TOP/l6m"; mkdir -p "$L6M"; cp "$L6D"/*.sh "$L6D"/*.py "$L6M/"
sed 's/^\([[:space:]]*\)_restore_prior$/\1:/' "$L6D/automate-trail.sh" > "$L6M/automate-trail.sh"
for variant in fixed mutant; do
  if [ "$variant" = fixed ]; then closeout_fixture 33; D="$L6D"; else closeout_fixture 34; D="$L6M"; fi
  (cd "$P" && bash "$H" trail-pr "$RF_REL" --reason closeout >/dev/null)
  TM="$FX/tmerger"; git clone -q "$FX/origin.git" "$TM" 2>/dev/null
  ( cd "$TM" && git checkout -q main && git merge -q --squash "origin/chore/$RUN_ID-trail-1" >/dev/null && git commit -qm "squash trail" && git push -q origin main 2>/dev/null )
  (cd "$P" && bash "$H" trail-unstage "$RF_REL" >/dev/null)
  git -C "$P" commit -q --allow-empty -m "local diverging commit"
  pre_idx="$(git -C "$P" ls-files -s | LC_ALL=C sort)"
  out="$(cd "$P" && bash "$D/automate-helpers.sh" closeout "$RF_REL" "$REQ" "$PRURL")"
  case "$out" in *"closeout: skipped — git pull --ff-only refused"*) ok "[$variant] diverged main ⇒ the pull refuses" ;; *) no "[$variant] pull did not refuse: $out" ;; esac
  post_idx="$(git -C "$P" ls-files -s | LC_ALL=C sort)"
  if [ "$variant" = fixed ]; then
    [ "$pre_idx" = "$post_idx" ] && [ -z "$(git -C "$P" diff --cached --name-only)" ] && ok "fixed: index restored to its pre-closeout state (nothing staged)" || no "fixed: index changed: $(git -C "$P" diff --cached --name-only | tr '\n' ' ')"
  else
    [ "$pre_idx" != "$post_idx" ] && ok "mutation control: without _restore_prior the re-staged entries stay staged" || no "mutant left the index unchanged — the restore assertion is vacuous"
  fi
done

echo "== T. Queue candidates are requirement files only (L5) =="
new_fixture 35
( cd "$P" && mkdir -p src && echo "v1" > src/app.py && git add src/app.py && git commit -qm app && echo "local WIP" >> src/app.py )
awk '{print} /^## Queue$/{print "- [ ] src/app.py"}' "$P/$RF_REL0" > "$TOP/rf35" && mv "$TOP/rf35" "$P/$RF_REL0"
grep -qxF -- '- [ ] src/app.py' "$P/$RF_REL0" && ok "setup: a Queue item names a tracked source file" || no "setup: Queue edit failed"
(cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason closeout >/dev/null)
names="$(git -C "$FX/origin.git" show --name-only --format= "refs/heads/chore/$RUN_ID-trail-1" 2>/dev/null)"
case "$names" in *src/app.py*) no "L5: source file's local WIP committed into the trail: $names" ;; *"$REQ"*) ok "L5: source-file Queue item not committed; requirement still is" ;; *) no "L5: trail names: $names" ;; esac

echo "== E. evidence-gated stamps: a done claim rides only when its PR merged (decision 2) =="
# The requirement (and the done/ brief) Phase 4.5 stamps BEFORE any merge. trail-pr
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
# (d) an unstamped requirement (no sentinel — the fixture's bare `## Status: done`) rides regardless
new_fixture 55; set_pr "$PRURL" OPEN
out="$(cd "$P" && bash "$H" trail-pr "$RF_REL0" --reason done)"
case "$out" in *"excluded $REQ"*) no "(d) unstamped requirement excluded: $out" ;; *) grep -qxF -- "$REQ" < <(trail_names) && ok "(d) unstamped requirement committed even with its PR OPEN" || no "(d) names: $(trail_names)" ;; esac
grep -q '^pr view' "$GH_STUB_DIR/argv.log" && no "(d) gh pr view called for unstamped paths" || ok "(d) no gh pr view for an unstamped requirement / Outcome-less brief"
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
EGM="$TOP/egmut"; mkdir -p "$EGM"; cp "$HERE"/*.sh "$HERE"/*.py "$EGM/"
sed 's/^\([[:space:]]*\)_evidence_gate$/\1:/' "$T" > "$EGM/automate-trail.sh"
if ! cmp -s "$T" "$EGM/automate-trail.sh" && bash -n "$EGM/automate-trail.sh"; then
  new_fixture 59; stamp_req "$REQ" done "$PRL"; set_pr "$PRURL" OPEN
  (cd "$P" && bash "$EGM/automate-helpers.sh" trail-pr "$RF_REL0" --reason done >/dev/null)
  grep -qxF -- "$REQ" < <(trail_names) && ok "mutation control: without _evidence_gate the OPEN-PR done stamp IS committed (leg (a) is load-bearing)" || no "mutant did not commit the stamp — leg (a) may be vacuous"
else
  no "evidence-gate mutant not generated"
fi

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
STM="$TOP/d3stm"; mkdir -p "$STM"; cp "$HERE"/*.sh "$HERE"/*.py "$STM/"
awk '{ if ($0 == "_stage_tip() {") { print "_stage_tip() { return 0; }"; print "_stage_tip_dead() {" } else print }' "$T" > "$STM/automate-trail.sh"
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

# M2: the marker is per RUN; a launch for ANOTHER PR of the same run replaces
# the live watcher (verified as ours by ps), a same-PR launch does not (above).
PRURL2="https://github.com/acme/widgets/pull/8"
REQ2=".supervisor/requirements/f/02-b.md"
closeout_fixture 38
spy_reset
jq --arg u "$PRURL2" '.[0].state = "OPEN" | . + [{number:8,url:$u,state:"OPEN",headRefName:"feature/y",headRefOid:"0"}]' "$GH_STUB_DIR/prs.json" > "$GH_STUB_DIR/p.tmp" && mv "$GH_STUB_DIR/p.tmp" "$GH_STUB_DIR/prs.json"
( cd "$P" && LOOMWRIGHT_MERGE_WATCH_INTERVAL=30 LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=600 nohup bash "$WATCH" "$RF_REL" "$REQ" "$PRURL" </dev/null >"$TOP/wa.log" 2>&1 & )
i=0; while [ ! -s "$P/$MARK" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i+1)); done
apid="$(awk -F'\t' '$1=="pid"{print $2}' "$P/$MARK" 2>/dev/null)"
sleep 0.5   # A is now inside its 30s interval nap
t0="$(date +%s)"
( cd "$P" && LOOMWRIGHT_MERGE_WATCH_INTERVAL=30 LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=600 nohup bash "$WATCH" "$RF_REL" "$REQ2" "$PRURL2" </dev/null >"$TOP/wb.log" 2>&1 & )
i=0; while [ "$(awk -F'\t' '$1=="pr_url"{print $2}' "$P/$MARK" 2>/dev/null)" != "$PRURL2" ] && [ "$i" -lt 150 ]; do sleep 0.1; i=$((i+1)); done
bpid="$(awk -F'\t' '$1=="pid"{print $2}' "$P/$MARK" 2>/dev/null)"
[ -n "$apid" ] && ! kill -0 "$apid" 2>/dev/null && [ $(( $(date +%s) - t0 )) -lt 10 ] && ok "M2: launch for another PR terminates the old watcher promptly (interruptible nap)" || no "M2: old watcher pid=$apid still alive / slow"
[ -n "$bpid" ] && [ "$bpid" != "$apid" ] && kill -0 "$bpid" 2>/dev/null && ok "M2: the marker now names the new watcher for $PRURL2" || no "M2: marker: $(cat "$P/$MARK" 2>/dev/null | tr '\n' '|')"
grep -qF "merge-watch: replaced pid=$apid watching $PRURL" "$TOP/wb.log" && ok "M2: the new watcher says whom it replaced" || no "M2: wb.log: $(cat "$TOP/wb.log")"
grep -qE "^- .* merge-watch: replaced watcher pid=$apid for $PRURL \(now watching $PRURL2\)" "$P/$RF_REL" && ok "M2: a Progress line names the PR that is no longer watched" || no "M2: replace Progress line missing"
[ ! -s "$SPYLOG.notify" ] && [ ! -s "$SPYLOG.webhook" ] && ok "M2: the replaced watcher sent no notify" || no "M2: notify sent on replace"
[ -n "$bpid" ] && kill "$bpid" 2>/dev/null
i=0; while [ -e "$P/$MARK" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i+1)); done
[ ! -e "$P/$MARK" ] && ok "M2: marker gone after the new watcher exits" || no "M2: marker left"

# stale-pid safety: a LIVE pid that is not our watcher is never signalled — the
# marker is reclaimed as stale, for the same PR and for another PR.
for spr in "$PRURL" "$PRURL2"; do
  sleep 30 </dev/null >/dev/null 2>&1 &
  foreign=$!
  printf 'pid\t%s\npr_url\t%s\nstarted\tx\n' "$foreign" "$PRURL" > "$P/$MARK"
  out="$(cd "$P" && LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=0 bash "$WATCH" "$RF_REL" "$REQ" "$spr" </dev/null 2>&1)"
  case "$out" in *"replaced"*) no "stale pid ($spr): treated as our watcher: $out" ;; *"merge-watch: started pid="*) ok "stale live pid, launch for $spr: reclaimed, not replaced" ;; *) no "stale pid ($spr): $out" ;; esac
  kill -0 "$foreign" 2>/dev/null && ok "stale live pid ($spr): the foreign process was not signalled" || no "stale pid ($spr): foreign process killed"
  kill "$foreign" 2>/dev/null; wait "$foreign" 2>/dev/null
done

# M3: MERGED seen, but closeout returns a transient skip until the lifetime cap
# ⇒ a failure-style notify + a Progress line naming the merge and the reason.
closeout_fixture 39
spy_reset
TC="$TOP/tcap"; mkdir -p "$TC"
cp "$WATCH" "$SPYD/notify-desktop.sh" "$SPYD/send-webhook.sh" "$TC/"
cat > "$TC/automate-helpers.sh" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$SPYLOG"
case "${1:-}" in
  closeout) echo "closeout: skipped — gh unavailable" ;;
  *) exec bash "$SPYD_REAL/automate-helpers.real.sh" "$@" ;;
esac
FAKE
wout="$(cd "$P" && SPYD_REAL="$SPYD" LOOMWRIGHT_MERGE_WATCH_INTERVAL=0 LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=2 bash "$TC/automate-merge-watch.sh" "$RF_REL" "$REQ" "$PRURL" </dev/null 2>&1)"
case "$wout" in *"merge-watch: lifetime cap reached (merged; closeout never ran — gh unavailable)"*) ok "M3: cap after MERGED names the merge + last skip" ;; *) no "M3: $wout" ;; esac
grep -qE "^- .* merge-watch: lifetime cap \(2s\) reached — $PRURL is MERGED but closeout never ran \(last skip: gh unavailable\)" "$P/$RF_REL" && ok "M3: Progress line says MERGED + the reason" || no "M3: Progress line missing"
grep -q 'after the merge' "$P/$RF_REL" && no "M3: Progress still says 'after the merge'" || ok "M3: never tells the owner to resume 'after the merge'"
[ "$(spy_count notify "$SPYLOG.notify")" = "1" ] && grep -q 'could not run.*lifetime cap reached, last skip: gh unavailable' "$SPYLOG.webhook" && ok "M3: one failure-style notify naming the reason" || no "M3 notify: $(cat "$SPYLOG.webhook" 2>/dev/null)"
[ "$(spy_count '^closeout ' "$SPYLOG")" -ge 2 ] && ok "M3: closeout was retried before the cap" || no "M3: closeout calls $(spy_count '^closeout ' "$SPYLOG")"

w_code="$(grep -vE '^[[:space:]]*#' "$HERE/automate-merge-watch.sh")"
bad="$(grep -nE 'pr merge|/autonomous|(^|[^a-z-])timeout |setsid|sed -i|stat -c|date -d' <<<"$w_code" || true)"
[ -z "$bad" ] && ok "watcher: no merge, no /autonomous, no timeout/setsid/GNU-only forms" || no "watcher forms: $bad"

# transient gh failure inside closeout: fails once, then succeeds ⇒ exactly one
# successful closeout + one notify (never a success notify for the guard skip)
closeout_fixture 36   # fresh id: 15/16 are the C legs above (a reused dir fails its clone)
spy_reset
touch "$GH_STUB_DIR/auth-fail-once"
wout="$(cd "$P" && LOOMWRIGHT_MERGE_WATCH_INTERVAL=0 LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=60 bash "$WATCH" "$RF_REL" "$REQ" "$PRURL" </dev/null 2>&1)"
case "$wout" in *"closeout: skipped — gh unavailable"*"merge-watch: closeout did not run (gh unavailable) — retry in "*"merge-watch: closeout done"*) ok "W: gh unavailable ⇒ retried, then closeout done" ;; *) no "W transient: $wout" ;; esac
[ "$(spy_count '^closeout ' "$SPYLOG")" = "2" ] && ok "W: two closeout calls (one guard skip + one real)" || no "W: closeout calls $(spy_count '^closeout ' "$SPYLOG")"
[ "$(printf '%s\n' "$wout" | grep -c '^closeout: checked — ')" = "1" ] && grep -qxF -- "- [x] $REQ" "$P/$RF_REL" && ok "W: exactly one successful closeout (checked off once)" || no "W: successful closeout count"
[ "$(spy_count notify "$SPYLOG.notify")" = "1" ] && [ "$(spy_count 'automate_merge_watch' "$SPYLOG.webhook")" = "1" ] && ok "W: exactly one notify" || no "W: notify count $(spy_count notify "$SPYLOG.notify")"

# terminal guard skip: one Progress line + a failure notify, never the success notify
closeout_fixture 37
spy_reset
TG="$TOP/tguard"; mkdir -p "$TG"
cp "$WATCH" "$SPYD/notify-desktop.sh" "$SPYD/send-webhook.sh" "$TG/"
cat > "$TG/automate-helpers.sh" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$SPYLOG"
case "${1:-}" in
  closeout) echo "closeout: skipped — not a git checkout" ;;
  *) exec bash "$SPYD_REAL/automate-helpers.real.sh" "$@" ;;
esac
FAKE
wout="$(cd "$P" && SPYD_REAL="$SPYD" LOOMWRIGHT_MERGE_WATCH_INTERVAL=0 LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=60 bash "$TG/automate-merge-watch.sh" "$RF_REL" "$REQ" "$PRURL" </dev/null 2>&1)"
[ "$(spy_count '^closeout ' "$SPYLOG")" = "1" ] && case "$wout" in *"merge-watch: closeout skipped — not a git checkout"*) true ;; *) false ;; esac && ok "W: terminal guard ⇒ one closeout call, exit" || no "W terminal: $wout"
grep -qE "^- .* merge-watch: closeout for $PRURL could not run — skipped: not a git checkout" "$P/$RF_REL" && ok "W: terminal guard ⇒ a Progress line naming it" || no "W terminal Progress line missing"
[ "$(spy_count notify "$SPYLOG.notify")" = "1" ] && grep -q 'could not run' "$SPYLOG.webhook" && ! grep -q 'closeout ran' "$SPYLOG.webhook" && ok "W: terminal guard ⇒ failure notify, never the success notify" || no "W terminal notify: $(cat "$SPYLOG.webhook" 2>/dev/null)"

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
