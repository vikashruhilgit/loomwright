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
#      mutation/push; a second run AFTER the first run's trail PR merged (its
#      sync moves main) leaves the run file byte-identical, trails `skipped —
#      trail already up to date` and opens no PR (control: `did=1` restored on
#      the synced line ⇒ skip-only Progress lines + a fresh trail PR); guards (tip != headRefOid, dirty worktree salvaged + kept,
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
#   WE. escalated park (automate-followups/31) — the watcher armed at an
#      `escalated` park closes out on merge; check_red/findings/other/another
#      PR ⇒ no check polling; check_pending → green ⇒ one `now mergeable` line +
#      one `automate_escalation_recheck` notify (latched, also across a
#      restart), non-green ⇒ one `still failing … rerun: gh run rerun <id>
#      --failed`; check_red_unrelated reports only at a NEWER attempt; the
#      check-runs API path when no run id; a same-PR double arm keeps ONE
#      watcher (already-running line, first pid alive, marker pid unchanged,
#      one closeout) with a valid mutant deleting that branch; static scan: no
#      executed gh run rerun / gh pr merge / git push. Review iteration 1: a
#      recorded sha that is not the PR head ⇒ silent; closeout clears the line
#      (idempotent); another rollup check pending/red/unreadable, or a run view
#      without headSha ⇒ no 'now mergeable'.
#      Review iteration 2: the AC9 re-park flow (line dropped by `running`, a
#      fresh check_pending line, `already running`) ⇒ the kept watcher reports
#      once (content-keyed latch; mutant restoring the permanent latch fails);
#      a restart over the same line never re-reports.
#      Review iteration 3 (E14): a re-park recording a newer attempt, then a
#      still newer failing attempt ⇒ a SECOND still-failing line (the restart
#      latch is the reported-line sidecar, keyed on item + PR + line content);
#      the same line across a restart, or another item's sidecar ⇒ as keyed;
#      mutant restoring the whole-run-file search fails.
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
#   G. PICK-time trail gate — an open trail PR ⇒ PARK naming it, primary
#      untouched (control: the OPEN filter dropped ⇒ clear), plus the #345/#347
#      incident reproduced without the gate (next branch BEHIND); a merged trail
#      PR ⇒ clear + sync, next branch carries it and holds only its own file
#      (control: sync removed ⇒ BEHIND); CLOSED / other run / non-numeric suffix
#      ⇒ clear; gh list failing / gh absent / missing run file ⇒ PARK, exit 0.
#   K. SKILL text (Part B) — watcher named, §6 step 1 closeout --session-id
#      before PICK, decision-9 grep clean, commands/automate.md surface.
#   DS. done stamp only post-merge (automate-followups/37) — a requirement at
#      `## Status: pending` after Phase 4.5 (its step-2.5 stamp block, if any,
#      applied) + closeout with the PR OPEN is byte-identical; MERGED ⇒ exactly
#      one closeout-printf block; the self-heal skill instructs no stamp.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/wait-lib.sh"   # bounded condition waits (iq02 T07)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
H="$HERE/automate-helpers.sh"
T="$HERE/automate-trail.sh"
SKILL="$HERE/../skills/automate-loop/SKILL.md"

pass=0; fail=0
# A shadow tally the summary cross-checks: a leg that reuses `pass`/`fail` as a loop
# variable clobbers the counter silently (CL5's `for pass in 1 2` once printed
# '40 passed' for 504 ok lines). The `_tally_` prefix keeps it out of any leg's namespace.
_tally_ok=0; _tally_no=0
ok() { echo "  ok: $1"; pass=$((pass+1)); _tally_ok=$((_tally_ok+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); _tally_no=$((_tally_no+1)); }

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
  "run view"|"api "*)
    # automate-followups/31 settle re-check: run-seq / api-seq hold one JSON
    # document per line, popped per call (the last line is sticky). Absent ⇒
    # the stub's old silent `exit 0`, so no earlier leg changes behavior.
    if [ "${1:-}" = run ]; then sq="$d/run-seq"; else sq="$d/api-seq"; fi
    [ -f "$sq" ] || exit 0
    [ -f "$sq-fail" ] && exit 1
    if [ "$(wc -l < "$sq" | tr -d ' ')" -gt 1 ]; then
      head -n1 "$sq"; tail -n +2 "$sq" > "$sq.tmp"; mv "$sq.tmp" "$sq"
    else cat "$sq"; fi
    exit 0 ;;
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
no_trail_on '^   \*\*PICK-time trail gate' "trail_pr_open park"
no_trail_on '^   \*\*PICK-time run-lock acquire' "live_lane park (PICK-time lane guard)"
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

# =============================================================================
# Part B — closeout + merge watcher
# =============================================================================
PRURL="https://github.com/acme/widgets/pull/7"
RF_REL=".supervisor/automate/$RUN_ID.md"

# spy copy of the scripts dir: automate-helpers.sh is a logging shim that execs
# the real helper (renamed), and captures the run-lock meta while trail-pr runs;
# notify-desktop.sh / send-webhook.sh are counters. Everything else is real.
# Every scripts-dir copy here also takes automate-helpers.d/ — the dispatcher
# sources its helper families from beside itself (parallel-automate/11).
SPYD="$TOP/spyd"; mkdir -p "$SPYD"
cp "$HERE"/*.sh "$HERE"/*.py "$SPYD/"; cp -R "$HERE/automate-helpers.d" "$SPYD/"
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
# iq02 T04: seed the item's session id + pick/park so closeout's item_timing has a record to write.
# An EARLIER item (20 min, its own session) precedes it: the record must be THIS item's segment
# (closeout passes --item), never the run's first pick/park (which read 1200 s, not 3600 s).
printf -- '- 2026-10-01T08:00:00Z picked earlier.md\n- 2026-10-01T08:10:00Z session_id sess-early (earlier.md)\n- 2026-10-01T08:20:00Z parked awaiting_merge\n' >> "$P/$RF_REL"
printf -- '- 2026-10-01T10:00:00Z picked %s\n- 2026-10-01T10:30:00Z session_id sess-it (%s)\n- 2026-10-01T11:00:00Z parked awaiting_merge\n' "$REQ" "$REQ" >> "$P/$RF_REL"
mkdir -p "$P/.supervisor/logs"
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
IT="$(jq -c 'select(.event=="item_timing")' "$P/.supervisor/logs/sess-it.jsonl" 2>/dev/null)"
[ "$(printf '%s' "$IT" | jq -r '"\(.pr_url) \(.item.pick_to_park.seconds) \(has("ts"))"' 2>/dev/null)" = "$PRURL 3600 true" ] && ok "T04: closeout appends ONE item_timing event (phase-timing.sh --run --item: this item's segment, not the earlier item's) to the item's session log" || no "T04: item_timing missing/wrong: $IT"
case "$out" in *item_timing*|*phase-timing*) no "T04: item_timing step printed output (closeout prints only closeout: lines)" ;; *) ok "T04: the item_timing append is silent" ;; esac

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
it_count() { jq -c 'select(.event=="item_timing")' "$1" 2>/dev/null | wc -l | tr -d ' '; }
[ "$(it_count "$P/.supervisor/logs/sess-it.jsonl")" = 1 ] && ok "AC11: the session log holds exactly ONE item_timing after the second closeout (the append is idempotent)" || no "AC11: item_timing rows after the re-run: $(it_count "$P/.supervisor/logs/sess-it.jsonl")"
grep -q '^pr merge' "$GH_STUB_DIR/argv.log" && no "gh pr merge called" || ok "closeout never calls gh pr merge"
# Control: the same two closeouts through a gated copy WITHOUT the idempotence guard append a
# second item_timing — so the exactly-ONE assertion above is load-bearing (red on the pre-fix code).
MUTI="$TOP/mutd-itiming"; mkdir -p "$MUTI"; cp "$HERE"/*.sh "$HERE"/*.py "$MUTI/"; cp -R "$HERE/automate-helpers.d" "$MUTI/"
if [ "$(grep -c 'item_timing-idempotence guard' "$T")" != 1 ]; then no "item_timing mutant anchor is not unique"
else
  grep -v 'item_timing-idempotence guard' "$T" > "$MUTI/automate-trail.sh"
  if [ ! -s "$MUTI/automate-trail.sh" ] || cmp -s "$T" "$MUTI/automate-trail.sh" || ! bash -n "$MUTI/automate-trail.sh"; then no "item_timing mutant not built"
  else
    closeout_fixture 112
    printf -- '- 2026-10-01T10:00:00Z picked %s\n- 2026-10-01T10:30:00Z session_id sess-it (%s)\n- 2026-10-01T11:00:00Z parked awaiting_merge\n' "$REQ" "$REQ" >> "$P/$RF_REL"
    mkdir -p "$P/.supervisor/logs"
    (cd "$P" && bash "$MUTI/automate-helpers.sh" closeout "$RF_REL" "$REQ" "$PRURL" >/dev/null 2>&1)
    (cd "$P" && bash "$MUTI/automate-helpers.sh" closeout "$RF_REL" "$REQ" "$PRURL" >/dev/null 2>&1)
    [ "$(it_count "$P/.supervisor/logs/sess-it.jsonl")" = 2 ] && ok "control: without the guard the re-run appends a second item_timing (the AC11 exactly-ONE assertion is load-bearing)" || no "control: unguarded re-run left $(it_count "$P/.supervisor/logs/sess-it.jsonl") item_timing row(s), expected 2 — the control does not exercise the guard"
  fi
fi

echo "== C. closeout idempotent AFTER its own trail PR merged (the sync moves; nothing else may) =="
# Run automate-2026-10-01-142337: the watcher's closeout opened trail PR #329,
# the owner merged it, and RECONCILE's re-run printed only skips plus
# `synced — main at <the #329 merge>`. The sync set `did`, so the six step lines
# were appended to ## Progress and trail-pr opened #330 carrying only them. The
# AC11 leg above never merges the trail PR between runs, so its sync skips and
# it stayed green. Control: the same world with `did=1` restored on the synced
# line turns every assertion red.
MUTS="$TOP/mutd-sync"; mkdir -p "$MUTS"; cp "$HERE"/*.sh "$HERE"/*.py "$MUTS/"; cp -R "$HERE/automate-helpers.d" "$MUTS/"
[ "$(grep -c '^    sy="closeout: synced — ' "$T")" = 1 ] || no "sync mutant anchor is not unique"
awk 'index($0, "sy=\"closeout: synced — ")==5 { print $0 "; did=1"; next } { print }' "$T" > "$MUTS/automate-trail.sh"
for v in fixed mutant; do
  if [ "$v" = fixed ]; then closeout_fixture 110; D="$SPYD"; else closeout_fixture 111; D="$MUTS"; fi
  if [ "$v" = mutant ] && { cmp -s "$T" "$D/automate-trail.sh" || ! bash -n "$D/automate-trail.sh"; }; then no "sync mutant not built"; continue; fi
  out1="$(cd "$P" && bash "$D/automate-helpers.sh" closeout "$RF_REL" "$REQ" "$PRURL")"
  case "$out1" in *"trail-pr: opened "*) ;; *) no "[$v] first closeout opened no trail PR: $out1"; continue ;; esac
  # The owner squash-merges the trail PR; the stub now reports it MERGED.
  TM="$FX/tmerger"; git clone -q "$FX/origin.git" "$TM" 2>/dev/null
  ( cd "$TM" && git checkout -q main && git merge -q --squash "origin/chore/$RUN_ID-trail-1" >/dev/null && git commit -qm "squash trail" && git push -q origin main 2>/dev/null )
  jq --arg h "chore/$RUN_ID-trail-1" 'map(if .headRefName == $h then .state = "MERGED" else . end)' "$GH_STUB_DIR/prs.json" > "$GH_STUB_DIR/p.tmp" && mv "$GH_STUB_DIR/p.tmp" "$GH_STUB_DIR/prs.json"
  cp "$P/$RF_REL" "$FX/rf.before"; cp "$P/$REQ" "$FX/req.before"; creates_before="$(count_creates)"
  out2="$(cd "$P" && bash "$D/automate-helpers.sh" closeout "$RF_REL" "$REQ" "$PRURL" --session-id SESS-RECONCILE)"
  printf '%s\n' "$out2" | sed "s/^/    [$v] | /"
  trail2="$(printf '%s\n' "$out2" | tail -n1)"
  if [ "$v" = fixed ]; then
    case "$out2" in *"closeout: synced — main at "*) ok "re-run after the trail merge: the sync really moved main (the leg exercises the bug's trigger)" ;; *) no "re-run did not sync — the leg does not reproduce the incident: $out2" ;; esac
    badl="$(printf '%s\n' "$out2" | sed '$d' | grep -v 'skipped — ' | grep -v '^closeout: synced — ' || true)"
    [ -z "$badl" ] && ok "re-run: every item line is skipped (only the sync moved)" || no "re-run non-skip item line(s): $badl"
    cmp -s "$FX/rf.before" "$P/$RF_REL" && ok "re-run: run file byte-identical (no skip-only ## Progress lines)" || no "re-run mutated the run file: $(diff "$FX/rf.before" "$P/$RF_REL" | tr '\n' '|')"
    cmp -s "$FX/req.before" "$P/$REQ" && ok "re-run: requirement byte-identical" || no "re-run mutated the requirement"
    case "$trail2" in "trail-pr: skipped — trail already up to date"*) ok "re-run: trail reads skipped — trail already up to date" ;; *) no "re-run trail line: $trail2" ;; esac
    [ "$creates_before" = "$(count_creates)" ] && ok "re-run: no new trail PR opened" || no "re-run opened a trail PR (the #330 incident)"
  else
    if ! cmp -s "$FX/rf.before" "$P/$RF_REL" && case "$trail2" in "trail-pr: opened "*) true ;; *) false ;; esac && [ "$creates_before" != "$(count_creates)" ]; then
      ok "control: with did=1 on the synced line the re-run appends skip lines and opens a fresh trail PR (the incident; the assertions above are load-bearing)"
    else
      no "sync control did not reproduce the incident: $trail2"
    fi
  fi
done

echo "== C. closeout reconciles a MATCHING ## Current, never a different one =="
# loomwright-studio run automate-2026-09-30-211858: after the watcher's closeout
# the Queue read `- [x] …02…` while ## Current still said awaiting_merge — a
# self-contradictory run file whose next resume re-ran reconcile + closeout.
cur_block() { awk '/^## Current/{c=1} /^## Progress/{c=0} c' "$1"; }
# (i) matching item + PR, ## Status: paused ⇒ status done, pause_reason awaiting_go.
closeout_fixture 101
out="$(run_closeout)"
grep -qxF -- "- item: $REQ | status: done | pr: $PRURL | branch: feature/x" "$P/$RF_REL" \
  && grep -qxF -- "- pause_reason: awaiting_go" "$P/$RF_REL" \
  && ok "## Current (matching item+PR, paused): status done + pause_reason awaiting_go" || no "## Current not reconciled: $(cur_block "$P/$RF_REL" | tr '\n' '|')"
grep -qxF -- "## Status: paused" "$P/$RF_REL" && ok "## Status is never rewritten by closeout" || no "## Status changed: $(grep '^## Status' "$P/$RF_REL")"
grep -qE "^- .* closeout $PRURL: closeout: reconciled — ## Current " "$P/$RF_REL" && ok "## Progress records the ## Current reconcile" || no "no Progress line for the reconcile"
case "$out" in *"closeout: reconciled — ## Current $REQ status done, pause_reason awaiting_go"*) ok "closeout prints the reconciled line" ;; *) no "reconciled line missing: $out" ;; esac
# Control (red without the fix): closeout with step 7b deleted leaves the studio state.
MUTD="$TOP/mutd-current"; mkdir -p "$MUTD"; cp "$HERE"/*.sh "$HERE"/*.py "$MUTD/"; cp -R "$HERE/automate-helpers.d" "$MUTD/"
sed '/^  cu="\$(_co_current "\$rf_rel" "\$item" "\$pr_url")"$/d' "$HERE/automate-trail.sh" > "$MUTD/automate-trail.sh"
if ! cmp -s "$HERE/automate-trail.sh" "$MUTD/automate-trail.sh" && bash -n "$MUTD/automate-trail.sh"; then
  closeout_fixture 102
  (cd "$P" && bash "$MUTD/automate-helpers.sh" closeout "$RF_REL" "$REQ" "$PRURL" >/dev/null)
  grep -qxF -- "- [x] $REQ" "$P/$RF_REL" && grep -qxF -- "- pause_reason: awaiting_merge" "$P/$RF_REL" \
    && ok "control: without step 7b the item is checked off while ## Current still says awaiting_merge (the incident)" || no "control did not reproduce the incident: $(cur_block "$P/$RF_REL" | tr '\n' '|')"
else
  no "control mutant not built"
fi
# (iii) matching item + PR inside a LIVE loop (RECONCILE's closeout, ## Status:
#       running) ⇒ status done + pause_reason null (a running run is not paused).
closeout_fixture 105
(cd "$P" && sed -i.bak 's/^## Status: paused$/## Status: running/' "$RF_REL" && rm -f "$RF_REL.bak")
run_closeout >/dev/null
grep -qxF -- "- item: $REQ | status: done | pr: $PRURL | branch: feature/x" "$P/$RF_REL" \
  && grep -qxF -- "- pause_reason: null" "$P/$RF_REL" && grep -qxF -- "## Status: running" "$P/$RF_REL" \
  && ok "## Current (matching item+PR, running): status done + pause_reason null; ## Status stays running" || no "running-branch reconcile wrong: $(cur_block "$P/$RF_REL" | tr '\n' '|')"
# Control (red without the branch): want forced to awaiting_go regardless of status.
MUTW="$TOP/mutd-want"; mkdir -p "$MUTW"; cp "$HERE"/*.sh "$HERE"/*.py "$MUTW/"; cp -R "$HERE/automate-helpers.d" "$MUTW/"
sed 's/^  if \[ "\$run_status" = "paused" \]; then want="awaiting_go"; else want="null"; fi$/  want="awaiting_go"/' "$HERE/automate-trail.sh" > "$MUTW/automate-trail.sh"
if ! cmp -s "$HERE/automate-trail.sh" "$MUTW/automate-trail.sh" && bash -n "$MUTW/automate-trail.sh"; then
  closeout_fixture 106
  (cd "$P" && sed -i.bak 's/^## Status: paused$/## Status: running/' "$RF_REL" && rm -f "$RF_REL.bak")
  (cd "$P" && bash "$MUTW/automate-helpers.sh" closeout "$RF_REL" "$REQ" "$PRURL" >/dev/null)
  grep -qxF -- "- pause_reason: awaiting_go" "$P/$RF_REL" \
    && ok "control: without the status branch a running run is mis-written awaiting_go (the null assertion is load-bearing)" || no "want control did not discriminate: $(cur_block "$P/$RF_REL" | tr '\n' '|')"
else
  no "want mutant not built"
fi
# (ii) ## Current names a LATER item/PR (the watcher fired after the owner
#      resumed and picked 02-b) ⇒ ## Current byte-identical; the check-off still lands.
closeout_fixture 103
LATER=".supervisor/requirements/f/02-b.md"
( cd "$P"
  awk -v L="$LATER" '/^- item: /{print "- item: " L " | status: running | pr: https://github.com/acme/widgets/pull/8 | branch: feature/y"; next}
       /^- pause_reason:/{print "- pause_reason: null"; next} {print}' "$RF_REL" > "$RF_REL.tmp" && mv "$RF_REL.tmp" "$RF_REL"
  sed -i.bak 's/^## Status: paused$/## Status: running/' "$RF_REL" && rm -f "$RF_REL.bak" )
before_cur="$(cur_block "$P/$RF_REL")"
out="$(run_closeout)"
[ "$before_cur" = "$(cur_block "$P/$RF_REL")" ] && ok "## Current naming a different item/PR is left byte-identical" || no "## Current clobbered: $(cur_block "$P/$RF_REL" | tr '\n' '|')"
case "$out" in *"closeout: skipped — ## Current is $LATER (https://github.com/acme/widgets/pull/8), not this item/PR"*) ok "closeout names the non-matching ## Current it skipped" ;; *) no "non-matching skip line missing: $out" ;; esac
grep -qxF -- "- [x] $REQ" "$P/$RF_REL" && ok "the closed-out item is still checked off" || no "check-off lost"
# Control (red without the guard): the same world, closeout with the item/PR
# comparison neutered, overwrites the later item's ## Current.
MUTG="$TOP/mutd-guard"; mkdir -p "$MUTG"; cp "$HERE"/*.sh "$HERE"/*.py "$MUTG/"; cp -R "$HERE/automate-helpers.d" "$MUTG/"
sed 's/^  if \[ "\$cur_item" != "\$item" \] || \[ "\$cur_pr" != "\$pr" \]; then$/  if false; then/' "$HERE/automate-trail.sh" > "$MUTG/automate-trail.sh"
if ! cmp -s "$HERE/automate-trail.sh" "$MUTG/automate-trail.sh" && bash -n "$MUTG/automate-trail.sh"; then
  closeout_fixture 104
  ( cd "$P"
    awk -v L="$LATER" '/^- item: /{print "- item: " L " | status: running | pr: https://github.com/acme/widgets/pull/8 | branch: feature/y"; next}
         /^- pause_reason:/{print "- pause_reason: null"; next} {print}' "$RF_REL" > "$RF_REL.tmp" && mv "$RF_REL.tmp" "$RF_REL" )
  (cd "$P" && bash "$MUTG/automate-helpers.sh" closeout "$RF_REL" "$REQ" "$PRURL" >/dev/null)
  grep -qF -- "- item: $LATER | status: done" "$P/$RF_REL" \
    && ok "control: without the item/PR guard the later item's ## Current is clobbered to done" || no "guard control did not discriminate: $(cur_block "$P/$RF_REL" | tr '\n' '|')"
else
  no "guard mutant not built"
fi

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
L6D="$TOP/l6d"; mkdir -p "$L6D"; cp "$SPYD"/*.sh "$SPYD"/*.py "$L6D/"; cp -R "$SPYD/automate-helpers.d" "$L6D/"
cat > "$L6D/automate-helpers.sh" <<'SHIM'
#!/usr/bin/env bash
if [ "${1:-}" = trail-pr ]; then echo "trail-pr: skipped — stubbed"; exit 0; fi
exec bash "$(dirname "$0")/automate-helpers.real.sh" "$@"
SHIM
L6M="$TOP/l6m"; mkdir -p "$L6M"; cp "$L6D"/*.sh "$L6D"/*.py "$L6M/"; cp -R "$L6D/automate-helpers.d" "$L6M/"
sed 's/^\([[:space:]]*\)_restore_prior$/\1:/' "$L6D/automate-trail.sh" > "$L6M/automate-trail.sh"
for variant in fixed mutant; do
  if [ "$variant" = fixed ]; then closeout_fixture 33; D="$L6D"; else closeout_fixture 34; D="$L6M"; fi
  (cd "$P" && bash "$H" trail-pr "$RF_REL" --reason closeout >/dev/null)
  TM="$FX/tmerger"; git clone -q "$FX/origin.git" "$TM" 2>/dev/null
  ( cd "$TM" && git checkout -q main && git merge -q --squash "origin/chore/$RUN_ID-trail-1" >/dev/null && git commit -qm "squash trail" && git push -q origin main 2>/dev/null )
  (cd "$P" && bash "$H" trail-unstage "$RF_REL" >/dev/null)
  git -C "$P" commit -q --allow-empty -m "local diverging commit"
  pre_idx="$(git -C "$P" ls-files -s | env LC_ALL=C sort)"
  out="$(cd "$P" && bash "$D/automate-helpers.sh" closeout "$RF_REL" "$REQ" "$PRURL")"
  case "$out" in *"closeout: skipped — git pull --ff-only refused"*) ok "[$variant] diverged main ⇒ the pull refuses" ;; *) no "[$variant] pull did not refuse: $out" ;; esac
  post_idx="$(git -C "$P" ls-files -s | env LC_ALL=C sort)"
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
EGM="$TOP/egmut"; mkdir -p "$EGM"; cp "$HERE"/*.sh "$HERE"/*.py "$EGM/"; cp -R "$HERE/automate-helpers.d" "$EGM/"
sed 's/^\([[:space:]]*\)_evidence_gate$/\1:/' "$T" > "$EGM/automate-trail.sh"
if ! cmp -s "$T" "$EGM/automate-trail.sh" && bash -n "$EGM/automate-trail.sh"; then
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
ABM="$TOP/abmut"; mkdir -p "$ABM"; cp "$HERE"/*.sh "$HERE"/*.py "$ABM/"; cp -R "$HERE/automate-helpers.d" "$ABM/"
awk '/if \(!\(index\(\$0, ab\) == 1/ { print "      if ($0 !~ /ABANDONED/) { inb = 1; seen = 0 }"; next } { print }' "$T" > "$ABM/automate-trail.sh"
if ! cmp -s "$T" "$ABM/automate-trail.sh" && bash -n "$ABM/automate-trail.sh"; then
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
RETM="$TOP/retmut"; mkdir -p "$RETM"; cp "$HERE"/*.sh "$HERE"/*.py "$RETM/"; cp -R "$HERE/automate-helpers.d" "$RETM/"
sed 's/^\([[:space:]]*\)retract="\${retract:+.*$/\1:/' "$T" > "$RETM/automate-trail.sh"
cmp -s "$T" "$RETM/automate-trail.sh" && no "retract mutant not generated"
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
STM="$TOP/d3stm"; mkdir -p "$STM"; cp "$HERE"/*.sh "$HERE"/*.py "$STM/"; cp -R "$HERE/automate-helpers.d" "$STM/"
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
TGM="$TOP/tgm"; mkdir -p "$TGM"; cp "$HERE"/*.sh "$HERE"/*.py "$TGM/"; cp -R "$HERE/automate-helpers.d" "$TGM/"
sed 's/select((.state \/\/ "") == "OPEN") | //' "$T" > "$TGM/automate-trail.sh"
if cmp -s "$T" "$TGM/automate-trail.sh"; then no "[G1] mutation control: the patch changed nothing — inconclusive"
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
TGS="$TOP/tgs"; mkdir -p "$TGS"; cp "$HERE"/*.sh "$HERE"/*.py "$TGS/"; cp -R "$HERE/automate-helpers.d" "$TGS/"
sed 's/^  if _sync_primary "\$rf_rel" "\$run_id" "\$base_branch" "" "\$bm"; then$/  if false; then/' "$T" > "$TGS/automate-trail.sh"
if cmp -s "$T" "$TGS/automate-trail.sh"; then no "[G2] mutation control: the patch changed nothing — inconclusive"
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
  body="$(awk -v f="^$fn\\\\(\\\\) \\\\{" '$0 ~ f {s=1} s{print} s&&/^}/{exit}' "$T" | grep -vE '^[[:space:]]*#')"
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
i=0; while [ ! -s "$P/$MARK" ] && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i+1)); done
wpid="$(awk -F'\t' '$1=="pid"{print $2}' "$P/$MARK" 2>/dev/null)"
out="$(cd "$P" && bash "$WATCH" "$RF_REL" "$REQ" "$PRURL" </dev/null 2>&1)"
[ -n "$wpid" ] && [ "$out" = "merge-watch: already running pid=$wpid" ] && ok "AC13: second launch ⇒ already running, no second poller" || no "AC13 second launch: '$out' (pid=$wpid)"
[ "$(awk -F'\t' '$1=="pid"{print $2}' "$P/$MARK" 2>/dev/null)" = "$wpid" ] && ok "marker still names the first watcher" || no "marker overwritten"
[ -n "$wpid" ] && kill "$wpid" 2>/dev/null
i=0; while [ -e "$P/$MARK" ] && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i+1)); done
[ ! -e "$P/$MARK" ] && ok "AC13: marker gone after the watcher is terminated" || no "marker left after TERM"
( sleep 0 & echo $! > "$TOP/deadpid" )   # fixed-sleep-ok: `sleep 0` is the short-lived process whose pid goes dead, not a wait
# Wait until that pid IS dead before writing the marker — a fixed `sleep 0.2` assumed it (iq02 T07).
wait_for_pid_gone "$(cat "$TOP/deadpid")" 10 || no "dead-pid fixture: pid $(cat "$TOP/deadpid") never exited within 10 s"
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
i=0; while [ ! -s "$P/$MARK" ] && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i+1)); done
apid="$(awk -F'\t' '$1=="pid"{print $2}' "$P/$MARK" 2>/dev/null)"
sleep 0.5   # fixed-sleep-ok: settle — A is now inside its 30s interval nap (too short ⇒ B replaces A before its nap, a different path)
t0="$(date +%s)"
( cd "$P" && LOOMWRIGHT_MERGE_WATCH_INTERVAL=30 LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=600 nohup bash "$WATCH" "$RF_REL" "$REQ2" "$PRURL2" </dev/null >"$TOP/wb.log" 2>&1 & )
i=0; while [ "$(awk -F'\t' '$1=="pr_url"{print $2}' "$P/$MARK" 2>/dev/null)" != "$PRURL2" ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i+1)); done
bpid="$(awk -F'\t' '$1=="pid"{print $2}' "$P/$MARK" 2>/dev/null)"
t1="$(date +%s)"
# The replacing watcher writes its marker BEFORE its `replaced` Progress + log
# lines, so wait (bounded) for those instead of reading them at the flip.
i=0; while ! grep -qF "merge-watch: replaced pid=$apid" "$TOP/wb.log" 2>/dev/null && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i+1)); done
[ -n "$apid" ] && ! kill -0 "$apid" 2>/dev/null && [ $(( t1 - t0 )) -lt 15 ] && ok "M2: launch for another PR terminates the old watcher promptly (interruptible nap)" || no "M2: old watcher pid=$apid still alive / slow"
[ -n "$bpid" ] && [ "$bpid" != "$apid" ] && kill -0 "$bpid" 2>/dev/null && ok "M2: the marker now names the new watcher for $PRURL2" || no "M2: marker: $(cat "$P/$MARK" 2>/dev/null | tr '\n' '|')"
grep -qF "merge-watch: replaced pid=$apid watching $PRURL" "$TOP/wb.log" && ok "M2: the new watcher says whom it replaced" || no "M2: wb.log: $(cat "$TOP/wb.log")"
grep -qE "^- .* merge-watch: replaced watcher pid=$apid for $PRURL \(now watching $PRURL2\)" "$P/$RF_REL" && ok "M2: a Progress line names the PR that is no longer watched" || no "M2: replace Progress line missing"
[ ! -s "$SPYLOG.notify" ] && [ ! -s "$SPYLOG.webhook" ] && ok "M2: the replaced watcher sent no notify" || no "M2: notify sent on replace"
[ -n "$bpid" ] && kill "$bpid" 2>/dev/null
i=0; while [ -e "$P/$MARK" ] && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i+1)); done
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
# MAX=5, not 2: the watcher's clock is `date +%s` (whole seconds), so a start at
# x.9s plus the 1s retry nap can already read "2s elapsed" and hit a 2s cap
# before the retry — the 1-in-N 3.2 flake. 5s leaves room for >=2 closeouts.
wout="$(cd "$P" && SPYD_REAL="$SPYD" LOOMWRIGHT_MERGE_WATCH_INTERVAL=0 LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=5 bash "$TC/automate-merge-watch.sh" "$RF_REL" "$REQ" "$PRURL" </dev/null 2>&1)"
case "$wout" in *"merge-watch: lifetime cap reached (merged; closeout never ran — gh unavailable)"*) ok "M3: cap after MERGED names the merge + last skip" ;; *) no "M3: $wout" ;; esac
grep -qE "^- .* merge-watch: lifetime cap \(5s\) reached — $PRURL is MERGED but closeout never ran \(last skip: gh unavailable\)" "$P/$RF_REL" && ok "M3: Progress line says MERGED + the reason" || no "M3: Progress line missing"
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

echo "== WE. escalated park: watcher armed + settle re-check (automate-followups/31) =="
# Every leg runs the watcher against an `escalated` park whose ## Current carries
# the `- escalation_cause:` line Subtask 1's `current-escalation` writes.
ESHA="1e35336aaaabbbbccccddddeeeeffff000011112"
we_park() { # <cause> [current-escalation flags…] — turn the fixture's park into an escalated one
  local c="$1"; shift
  (cd "$P" && bash "$H" current-set "$RF_REL" --item "$REQ" --status escalated --pr "$PRURL" --branch feature/x --pause-reason escalated >/dev/null \
    && bash "$H" current-escalation "$RF_REL" --cause "$c" "$@" >/dev/null)
}
# we_open: the PR is OPEN at head $ESHA with an empty rollup (review iteration 1: the
# watcher reports only when the recorded sha IS the PR's current headRefOid and every
# OTHER rollup check is settled green — both read from the poll's own `gh pr view`).
we_open() { jq --arg h "$ESHA" '.[0].state = "OPEN" | .[0].headRefOid = $h | .[0].statusCheckRollup = []' "$GH_STUB_DIR/prs.json" > "$GH_STUB_DIR/p.tmp" && mv "$GH_STUB_DIR/p.tmp" "$GH_STUB_DIR/prs.json"; }
we_watch() { (cd "$P" && LOOMWRIGHT_MERGE_WATCH_INTERVAL=0 LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=60 bash "$WATCH" "$RF_REL" "$REQ" "$PRURL" </dev/null 2>&1); }
we_n() { grep -c -- "$1" "$P/$RF_REL" 2>/dev/null || true; }
we_calls() { grep -cE '^(run view|api )' "$GH_STUB_DIR/argv.log" 2>/dev/null || true; }
rj() { jq -cn --argjson a "$1" --arg s "$2" --arg c "$3" --arg h "${4:-$ESHA}" '{attempt:$a,status:$s,conclusion:$c,headSha:$h}'; }

# (E1, AC8 + AC12) escalated park, cause check_red ⇒ armed, merge closes it out,
# no check polling at all.
closeout_fixture 401; spy_reset; we_open
we_park check_red --check ci --run-id 555 --attempt 1 --sha "$ESHA"
grep -qE '^- escalation_cause: check_red \| check: ci' "$P/$RF_REL" && ok "(E1) fixture: ## Current carries the current-escalation line" || no "(E1) fixture line: $(cur_block "$P/$RF_REL" | tr '\n' '|')"
printf 'OPEN\nOPEN\nMERGED\n' > "$GH_STUB_DIR/state-seq"; rj 2 completed success > "$GH_STUB_DIR/run-seq"
wout="$(we_watch)"
[ "$(spy_count '^closeout ' "$SPYLOG")" = "1" ] && grep -qxF -- "- [x] $REQ" "$P/$RF_REL" && ok "(E1) AC8: an escalated park's watcher closes the item out on merge (one closeout)" || no "(E1) closeout: $wout"
[ "$(we_calls)" = "0" ] && [ "$(we_n 'merge-watch: now mergeable:')" = "0" ] && [ "$(spy_count automate_escalation_recheck "$SPYLOG.webhook")" = "0" ] && ok "(E1) AC12: check_red ⇒ no check polling, no re-check report" || no "(E1) check_red polled: calls=$(we_calls)"
[ "$(spy_count notify "$SPYLOG.notify")" = "1" ] && [ "$(spy_count automate_merge_watch "$SPYLOG.webhook")" = "1" ] && ok "(E1) one merge notify, as for awaiting_merge" || no "(E1) notify count"

# (E2, AC12) findings / other / a re-checkable cause naming ANOTHER PR ⇒ no polling.
closeout_fixture 402
for wc in findings other foreign; do
  spy_reset; we_open; : > "$GH_STUB_DIR/argv.log"
  if [ "$wc" = foreign ]; then
    we_park check_pending --check ci --run-id 555 --attempt 1 --sha "$ESHA"
    (cd "$P" && bash "$H" current-set "$RF_REL" --item "$REQ" --status escalated --pr "https://github.com/acme/widgets/pull/70" --branch feature/x --pause-reason escalated >/dev/null)
  else we_park "$wc"; fi
  printf 'OPEN\nOPEN\nCLOSED\n' > "$GH_STUB_DIR/state-seq"; rj 1 completed success > "$GH_STUB_DIR/run-seq"
  we_watch >/dev/null
  [ "$(we_calls)" = "0" ] && [ "$(spy_count automate_escalation_recheck "$SPYLOG.webhook")" = "0" ] && ok "(E2) AC12: $wc ⇒ no check polling" || no "(E2) $wc polled: $(we_calls)"
done

# (E3, AC10) check_pending → completes green ⇒ exactly one now-mergeable line +
# one recheck notify, then keeps watching and closes out on the merge.
closeout_fixture 403; spy_reset; we_open
we_park check_pending --check claude-review --run-id 555 --attempt 1 --sha "$ESHA"
printf 'OPEN\nOPEN\nOPEN\nOPEN\nMERGED\n' > "$GH_STUB_DIR/state-seq"
{ rj 1 in_progress ""; rj 1 completed success; } > "$GH_STUB_DIR/run-seq"
wout="$(we_watch)"
[ "$(we_n "merge-watch: now mergeable: claude-review green on $ESHA")" = "1" ] && ok "(E3) AC10: exactly one 'now mergeable: claude-review green on <sha>' Progress line" || no "(E3) now-mergeable lines: $(we_n 'now mergeable')"
[ "$(spy_count automate_escalation_recheck "$SPYLOG.webhook")" = "1" ] && [ "$(spy_count automate_merge_watch "$SPYLOG.webhook")" = "1" ] && [ "$(spy_count notify "$SPYLOG.notify")" = "2" ] && ok "(E3) AC10: one automate_escalation_recheck notify (distinct type) + the one merge notify" || no "(E3) webhook: $(cat "$SPYLOG.webhook" 2>/dev/null | tr '\n' '|')"
[ "$(we_calls)" = "2" ] && [ "$(spy_count '^closeout ' "$SPYLOG")" = "1" ] && ok "(E3) latched after the report (2 run-view polls), then the merge closed it out" || no "(E3) calls=$(we_calls) closeouts=$(spy_count '^closeout ' "$SPYLOG")"
grep -q '^run view 555 --json attempt,status,conclusion,headSha$' "$GH_STUB_DIR/argv.log" && ! grep -q '^run rerun\|^pr merge' "$GH_STUB_DIR/argv.log" && ok "(E3) polls via gh run view <run_id>; no rerun, no merge call" || no "(E3) argv: $(tr '\n' '|' < "$GH_STUB_DIR/argv.log")"

# (E4, AC10) check_pending → completes non-green ⇒ one still-failing line carrying
# the rerun command; a restarted watcher does not report it again.
closeout_fixture 404; spy_reset; we_open
we_park check_pending --check claude-review --run-id 555 --attempt 1 --sha "$ESHA"
printf 'OPEN\nOPEN\nOPEN\nCLOSED\n' > "$GH_STUB_DIR/state-seq"; rj 1 completed failure > "$GH_STUB_DIR/run-seq"
we_watch >/dev/null
[ "$(we_n 'merge-watch: still failing: claude-review failure — rerun: gh run rerun 555 --failed')" = "1" ] && [ "$(spy_count automate_escalation_recheck "$SPYLOG.webhook")" = "1" ] && ok "(E4) AC10: one 'still failing … — rerun: gh run rerun 555 --failed' line + one recheck notify" || no "(E4) still-failing: $(grep 'still failing' "$P/$RF_REL")"
spy_reset; printf 'OPEN\nCLOSED\n' > "$GH_STUB_DIR/state-seq"
we_watch >/dev/null
[ "$(we_n 'merge-watch: still failing:')" = "1" ] && [ "$(spy_count automate_escalation_recheck "$SPYLOG.webhook")" = "0" ] && ok "(E4) a restarted watcher finds the report in ## Progress and stays silent" || no "(E4) restart re-reported"

# (E5, AC11) check_red_unrelated: the recorded red attempt never reports; a NEWER
# attempt (a human rerun) green ⇒ one now-mergeable; non-green ⇒ one still-failing.
for wv in green red; do
  if [ "$wv" = green ]; then closeout_fixture 405; fin=success; else closeout_fixture 406; fin=failure; fi
  spy_reset; we_open
  we_park check_red_unrelated --check ci --run-id 777 --attempt 1 --sha "$ESHA"
  printf 'OPEN\nOPEN\nOPEN\nOPEN\nOPEN\nOPEN\nOPEN\nCLOSED\n' > "$GH_STUB_DIR/state-seq"
  { rj 1 completed failure; rj 1 completed failure; rj 1 completed failure; rj 2 in_progress ""; rj 2 completed "$fin"; } > "$GH_STUB_DIR/run-seq"
  we_watch >/dev/null
  if [ "$wv" = green ]; then
    [ "$(we_n "merge-watch: now mergeable: ci green on $ESHA")" = "1" ] && [ "$(we_n 'merge-watch: still failing:')" = "0" ] && ok "(E5) AC11: red attempt 1 silent; attempt 2 green ⇒ one now-mergeable" || no "(E5) green: $(grep -E 'mergeable|failing' "$P/$RF_REL" | tr '\n' '|')"
    [ "$(we_calls)" = "5" ] && ok "(E5) reported on the 5th poll (the first completed attempt 2), then latched" || no "(E5) calls=$(we_calls)"
  else
    [ "$(we_n 'merge-watch: still failing: ci failure — rerun: gh run rerun 777 --failed')" = "1" ] && [ "$(we_n 'merge-watch: now mergeable:')" = "0" ] && [ "$(spy_count automate_escalation_recheck "$SPYLOG.webhook")" = "1" ] && ok "(E5) AC11: attempt 2 red ⇒ one still-failing line with the rerun command" || no "(E5) red: $(grep -E 'mergeable|failing' "$P/$RF_REL" | tr '\n' '|')"
  fi
done

# (E6) no run id recorded ⇒ the check-runs API by name, on the recorded sha.
closeout_fixture 407; spy_reset; we_open
we_park check_pending --check claude-review --sha "$ESHA"
printf 'OPEN\nOPEN\nCLOSED\n' > "$GH_STUB_DIR/state-seq"
jq -cn '{check_runs:[{name:"ci",status:"completed",conclusion:"success",started_at:"t1"},{name:"claude-review",status:"completed",conclusion:"success",started_at:"t2",details_url:"https://github.com/acme/widgets/actions/runs/999/job/1"}]}' > "$GH_STUB_DIR/api-seq"
we_watch >/dev/null
grep -q "^api repos/acme/widgets/commits/$ESHA/check-runs" "$GH_STUB_DIR/argv.log" && [ "$(we_n "merge-watch: now mergeable: claude-review green on $ESHA")" = "1" ] && ok "(E6) no run id ⇒ gh api commits/<sha>/check-runs by name ⇒ one now-mergeable" || no "(E6) argv: $(tr '\n' '|' < "$GH_STUB_DIR/argv.log")"

# (E7, AC9) park → fix-now re-drain → re-park of the SAME PR: both parks run the
# documented launch line (`nohup bash <watcher> <runfile> <item> <pr_url> </dev/null >log &`;
# its env-unset prefix is omitted — the watcher unsets those vars itself, first line).
# dbl_arm <watcher> → DA1/DA2/DA3 = the three assertions.
dbl_arm() {
  local w="$1" i lg1 lg2
  lg1="$TOP/da1-$2.log"; lg2="$TOP/da2-$2.log"
  ( cd "$P" && LOOMWRIGHT_MERGE_WATCH_INTERVAL=1 LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=60 nohup bash "$w" "$RF_REL" "$REQ" "$PRURL" </dev/null >"$lg1" 2>&1 & )
  i=0; while [ ! -s "$P/$MARK" ] && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i+1)); done
  DPID="$(awk -F'\t' '$1=="pid"{print $2}' "$P/$MARK" 2>/dev/null)"
  # The second launcher's own pid is kept, and its EXIT is awaited before its log is read — it exits right
  # after `already running`. This replaced a fixed `sleep 0.3` quiet period (iq02 T07). Bounded: a
  # mutant whose second launch keeps running as a watcher is read after 5 s, its log then is not the
  # one-line `already running`, so DA1 still goes red.
  ( cd "$P" && LOOMWRIGHT_MERGE_WATCH_INTERVAL=1 LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=60 nohup bash "$w" "$RF_REL" "$REQ" "$PRURL" </dev/null >"$lg2" 2>&1 ) &
  DA_L2=$!
  i=0; while ! grep -qE 'already running|started|replaced' "$lg2" 2>/dev/null && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i+1)); done
  wait_for_pid_gone "$DA_L2" 5 2>/dev/null || :
  disown "$DA_L2" 2>/dev/null || :
  DA1=1; DA2=1; DA3=1
  [ -n "$DPID" ] && [ "$(cat "$lg2")" = "merge-watch: already running pid=$DPID" ] || DA1=0
  [ -n "$DPID" ] && kill -0 "$DPID" 2>/dev/null || DA2=0
  [ -n "$DPID" ] && [ "$(awk -F'\t' '$1=="pid"{print $2}' "$P/$MARK" 2>/dev/null)" = "$DPID" ] || DA3=0
}
closeout_fixture 408; spy_reset; we_open
we_park check_red --check ci --run-id 555 --attempt 1 --sha "$ESHA"
dbl_arm "$WATCH" fixed
[ "$DA1" = 1 ] && ok "(E7) AC9 (1): the second launch prints 'merge-watch: already running pid=<first pid>'" || no "(E7) second launch: $(cat "$TOP/da2-fixed.log")"
[ "$DA2" = 1 ] && ok "(E7) AC9 (2): the first watcher is still alive after the second launch" || no "(E7) first watcher pid=$DPID gone"
[ "$DA3" = 1 ] && ok "(E7) AC9 (3): the marker's pid field is unchanged" || no "(E7) marker: $(tr '\n' '|' < "$P/$MARK" 2>/dev/null)"
jq '.[0].state = "MERGED"' "$GH_STUB_DIR/prs.json" > "$GH_STUB_DIR/p.tmp" && mv "$GH_STUB_DIR/p.tmp" "$GH_STUB_DIR/prs.json"
i=0; while [ -e "$P/$MARK" ] && [ "$i" -lt 400 ]; do sleep 0.1; i=$((i+1)); done
[ ! -e "$P/$MARK" ] && [ "$(spy_count '^closeout ' "$SPYLOG")" = "1" ] && [ "$(spy_count automate_merge_watch "$SPYLOG.webhook")" = "1" ] && grep -qxF -- "- [x] $REQ" "$P/$RF_REL" && ok "(E7) AC9: the merge then yields exactly one closeout + one merge notify" || no "(E7) closeouts=$(spy_count '^closeout ' "$SPYLOG") marker=$([ -e "$P/$MARK" ] && echo left)"
[ -n "$DPID" ] && kill "$DPID" 2>/dev/null
# mutation control: delete EXACTLY the same-pr_url `already running` branch.
MUT9="$TOP/mut9"; mkdir -p "$MUT9"; cp -R "$SPYD"/* "$MUT9/"
awk 'skip { skip = 0; next } /elif \[ "\$v" -eq 0 \] && \[ "\$opr" = "\$pr_url" \]; then/ { skip = 1; next } { print }' "$WATCH" > "$MUT9/automate-merge-watch.sh"
if [ -s "$MUT9/automate-merge-watch.sh" ] && ! cmp -s "$WATCH" "$MUT9/automate-merge-watch.sh" && bash -n "$MUT9/automate-merge-watch.sh" \
   && [ "$(( $(wc -l < "$WATCH") - $(wc -l < "$MUT9/automate-merge-watch.sh") ))" = "2" ]; then
  ok "(E7) AC9 mutant is valid (non-empty, differs by exactly the 2-line branch, bash -n clean)"
  closeout_fixture 409; spy_reset; we_open
  we_park check_red --check ci --run-id 555 --attempt 1 --sha "$ESHA"
  dbl_arm "$MUT9/automate-merge-watch.sh" mut
  [ "$DA1$DA2$DA3" != 111 ] && ok "(E7) AC9 mutant (same-pr_url branch deleted) is detected: (1)(2)(3)=$DA1$DA2$DA3" || no "(E7) AC9 mutant survived the double-arm assertions"
  for kp in "$DPID" "$(awk -F'\t' '$1=="pid"{print $2}' "$P/$MARK" 2>/dev/null)"; do [ -n "$kp" ] && kill "$kp" 2>/dev/null; done
  i=0; while [ -e "$P/$MARK" ] && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i+1)); done
else no "(E7) AC9 mutant invalid (empty / identical / bash -n / not exactly 2 lines)"; fi

# (E8, AC13 watcher half) no executed `gh run rerun` / `gh pr merge` / `git push`
# / approval in the watcher (or the classifier); comment and string mentions excluded.
we_exec_re='(^|[;&|({]|then|do|else|&&|\|\|)[[:space:]]*("?\$\{?GH\}?"?|gh)[[:space:]]+(run[[:space:]]+rerun|pr[[:space:]]+merge|pr[[:space:]]+review)|(^|[;&|({]|then|do|else)[[:space:]]*git[[:space:]]+push'
for wf in "$HERE/automate-merge-watch.sh" "$HERE/automate-helpers.d/escalation.sh"; do
  bad="$(grep -vE '^[[:space:]]*#' "$wf" | grep -nE "$we_exec_re" || true)"
  [ -z "$bad" ] && ok "(E8) AC13: $(basename "$wf") executes no gh run rerun / gh pr merge / git push / approval" || no "(E8) $(basename "$wf"): $bad"
done
[ "$(printf '%s\n' '  "$GH" run rerun "$rid" --failed' 'gh pr merge --squash "$u"' '  then git push origin x' | grep -cE "$we_exec_re")" = 3 ] && ok "(E8) the scan's positive control matches executed forms" || no "(E8) scan regex vacuous"
grep -qF 'rerun: gh run rerun' "$HERE/automate-merge-watch.sh" && ok "(E8) the rerun command is printed for the owner (string), never run" || no "(E8) rerun string missing"

# (E9, review iteration 1 — stale per-item state) a recorded sha that is NOT the PR's
# current headRefOid (a later push, or a line left over from an earlier item) ⇒ no
# check polling, no report.
closeout_fixture 410; spy_reset; we_open; : > "$GH_STUB_DIR/argv.log"
we_park check_pending --check claude-review --run-id 555 --attempt 1 --sha aaaaaaa
printf 'OPEN\nOPEN\nCLOSED\n' > "$GH_STUB_DIR/state-seq"; rj 1 completed success aaaaaaa > "$GH_STUB_DIR/run-seq"
we_watch >/dev/null
[ "$(we_calls)" = "0" ] && [ "$(we_n 'merge-watch: now mergeable:')" = "0" ] && [ "$(spy_count automate_escalation_recheck "$SPYLOG.webhook")" = "0" ] && ok "(E9) recorded sha != PR head ⇒ no polling, no 'now mergeable', no recheck notify" || no "(E9) stale sha reported: calls=$(we_calls) $(grep 'mergeable' "$P/$RF_REL")"
grep -q -- '--json state,headRefOid,statusCheckRollup' "$GH_STUB_DIR/argv.log" && [ "$(grep -c '^pr view ' "$GH_STUB_DIR/argv.log")" = "3" ] && ok "(E9) head + rollup come from the poll's own gh pr view (3 polls = 3 calls, no extra one)" || no "(E9) argv: $(tr '\n' '|' < "$GH_STUB_DIR/argv.log")"
# mutation control: delete EXACTLY the head-mismatch latch ⇒ the stale line reports.
MUT10="$TOP/mut10"; mkdir -p "$MUT10"; cp -R "$SPYD"/* "$MUT10/"
grep -vxF '  case "$head" in "$sha"*) ;; *) case "$sha" in "$head"*) ;; *) recheck_done=1; return 0 ;; esac ;; esac' "$WATCH" > "$MUT10/automate-merge-watch.sh"
if [ -s "$MUT10/automate-merge-watch.sh" ] && ! cmp -s "$WATCH" "$MUT10/automate-merge-watch.sh" && bash -n "$MUT10/automate-merge-watch.sh" \
   && [ "$(( $(wc -l < "$WATCH") - $(wc -l < "$MUT10/automate-merge-watch.sh") ))" = "1" ]; then
  closeout_fixture 413; spy_reset; we_open
  we_park check_pending --check claude-review --run-id 555 --attempt 1 --sha aaaaaaa
  printf 'OPEN\nOPEN\nCLOSED\n' > "$GH_STUB_DIR/state-seq"; rj 1 completed success aaaaaaa > "$GH_STUB_DIR/run-seq"
  (cd "$P" && LOOMWRIGHT_MERGE_WATCH_INTERVAL=0 LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=60 bash "$MUT10/automate-merge-watch.sh" "$RF_REL" "$REQ" "$PRURL" </dev/null >/dev/null 2>&1)
  [ "$(we_n 'merge-watch: now mergeable: claude-review green on aaaaaaa')" = "1" ] && ok "(E9) mutant (head check deleted) reports the stale sha — the latch is load-bearing" || no "(E9) mutant did not discriminate"
else no "(E9) head-check mutant invalid (empty / identical / bash -n / not exactly 1 line)"; fi
# (E9b) the escalated item's merge: closeout's `current-set --status done` clears the
# line; a second closeout leaves the run file byte-identical.
closeout_fixture 411; spy_reset; we_open
we_park check_pending --check claude-review --run-id 555 --attempt 1 --sha "$ESHA"
jq '.[0].state = "MERGED"' "$GH_STUB_DIR/prs.json" > "$GH_STUB_DIR/p.tmp" && mv "$GH_STUB_DIR/p.tmp" "$GH_STUB_DIR/prs.json"
run_closeout >/dev/null
if ! grep -q '^- escalation_cause:' "$P/$RF_REL" && grep -q 'status: done' < <(cur_block "$P/$RF_REL"); then ok "(E9b) closeout clears the escalated item's escalation_cause line"; else no "(E9b) line survived closeout: $(cur_block "$P/$RF_REL" | tr '\n' '|')"; fi
we_ck="$(cksum < "$P/$RF_REL")"; run_closeout >/dev/null
[ "$(cksum < "$P/$RF_REL")" = "$we_ck" ] && ok "(E9b) a second closeout leaves the run file byte-identical" || no "(E9b) second closeout changed the run file"

# (E10, review iteration 1 — verdict before a more-severe signal) the recorded check
# completes green but ANOTHER rollup check is still pending / red / the rollup is
# unreadable ⇒ no 'now mergeable'; control: only the recorded check itself in the rollup ⇒ reported.
for wo in pending red unreadable self; do
  closeout_fixture 412; spy_reset; we_open
  case "$wo" in
    pending) rl='[{"name":"ci","status":"IN_PROGRESS","conclusion":""}]' ;;
    red) rl='[{"name":"ci","status":"COMPLETED","conclusion":"FAILURE"},{"context":"lint","state":"SUCCESS"}]' ;;
    unreadable) rl='null' ;;
    self) rl='[{"name":"claude-review","status":"IN_PROGRESS","conclusion":""},{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS"},{"context":"lint","state":"SUCCESS"}]' ;;
  esac
  jq --argjson r "$rl" '.[0].statusCheckRollup = $r' "$GH_STUB_DIR/prs.json" > "$GH_STUB_DIR/p.tmp" && mv "$GH_STUB_DIR/p.tmp" "$GH_STUB_DIR/prs.json"
  we_park check_pending --check claude-review --run-id 555 --attempt 1 --sha "$ESHA"
  printf 'OPEN\nOPEN\nOPEN\nCLOSED\n' > "$GH_STUB_DIR/state-seq"; rj 1 completed success > "$GH_STUB_DIR/run-seq"
  we_watch >/dev/null
  if [ "$wo" = self ]; then
    [ "$(we_n "merge-watch: now mergeable: claude-review green on $ESHA")" = "1" ] && ok "(E10) control: other rollup checks settled green (recorded check excluded by name) ⇒ one now-mergeable" || no "(E10) control did not report: $(grep -E 'mergeable|failing' "$P/$RF_REL" | tr '\n' '|')"
  else
    [ "$(we_n 'merge-watch: now mergeable:')" = "0" ] && [ "$(spy_count automate_escalation_recheck "$SPYLOG.webhook")" = "0" ] && ok "(E10) recorded check green but another check $wo ⇒ no 'now mergeable'" || no "(E10) $wo reported now mergeable"
  fi
done

# (E11, review iteration 1 — fail-open on incomplete evidence) a run view with no
# headSha is no evidence the run is for the recorded sha ⇒ no report.
closeout_fixture 414; spy_reset; we_open
we_park check_pending --check claude-review --run-id 555 --attempt 1 --sha "$ESHA"
printf 'OPEN\nOPEN\nCLOSED\n' > "$GH_STUB_DIR/state-seq"; jq -cn '{attempt:1,status:"completed",conclusion:"success"}' > "$GH_STUB_DIR/run-seq"
we_watch >/dev/null
[ "$(we_n 'merge-watch: now mergeable:')" = "0" ] && [ "$(spy_count automate_escalation_recheck "$SPYLOG.webhook")" = "0" ] && ok "(E11) a run view without headSha ⇒ no 'now mergeable'" || no "(E11) headSha-less run reported"

# (E12, review iteration 2 — permanent latch on an absent/stale line) the brief's AC9
# flow end to end: park (check_red line) arms the watcher → PICK's `running` drops the
# line → the re-park writes a FRESH check_pending line and its launch prints `already
# running` ⇒ the KEPT watcher still reports exactly once (the latch is keyed on the
# line's content, never permanent). we_pr <n> — `pr view` calls so far.
we_pr() { grep -c '^pr view ' "$GH_STUB_DIR/argv.log" 2>/dev/null || true; }
we_until_polls() { local n0 i=0; n0="$(we_pr)"; while [ "$(we_pr)" -lt $((n0 + $1)) ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i+1)); done; }
# repark_flow <watcher> <fixture_n> <tag> → RP_ALREADY (second launch line ok), RP_N (now-mergeable lines), RP_R (recheck notifies)
repark_flow() {
  local w="$1" i pid lg2="$TOP/rp2-$3.log"
  closeout_fixture "$2"; spy_reset; we_open; : > "$GH_STUB_DIR/argv.log"; rm -f "$GH_STUB_DIR/state-seq" "$GH_STUB_DIR/run-seq"
  we_park check_red --check ci --run-id 555 --attempt 1 --sha "$ESHA"
  rj 1 completed success > "$GH_STUB_DIR/run-seq"
  ( cd "$P" && LOOMWRIGHT_MERGE_WATCH_INTERVAL=1 LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=120 nohup bash "$w" "$RF_REL" "$REQ" "$PRURL" </dev/null >"$TOP/rp1-$3.log" 2>&1 & )
  i=0; while [ ! -s "$P/$MARK" ] && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i+1)); done
  pid="$(awk -F'\t' '$1=="pid"{print $2}' "$P/$MARK" 2>/dev/null)"
  we_until_polls 2
  (cd "$P" && bash "$H" current-set "$RF_REL" --item "$REQ" --status running >/dev/null)   # PICK drops the line
  we_until_polls 2
  we_park check_pending --check claude-review --run-id 555 --attempt 1 --sha "$ESHA"
  ( cd "$P" && LOOMWRIGHT_MERGE_WATCH_INTERVAL=1 LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=120 nohup bash "$w" "$RF_REL" "$REQ" "$PRURL" </dev/null >"$lg2" 2>&1 & )
  i=0; while ! grep -qE 'already running|started|replaced' "$lg2" 2>/dev/null && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i+1)); done
  RP_ALREADY=0; [ -n "$pid" ] && [ "$(cat "$lg2")" = "merge-watch: already running pid=$pid" ] && RP_ALREADY=1
  i=0; while [ "$(we_n 'merge-watch: now mergeable:')" = 0 ] && [ "$i" -lt 6 ]; do we_until_polls 1; i=$((i+1)); done
  we_until_polls 3   # further polls after any report must stay silent
  RP_N="$(we_n "merge-watch: now mergeable: claude-review green on $ESHA")"
  RP_R="$(spy_count automate_escalation_recheck "$SPYLOG.webhook")"
  jq '.[0].state = "MERGED"' "$GH_STUB_DIR/prs.json" > "$GH_STUB_DIR/p.tmp" && mv "$GH_STUB_DIR/p.tmp" "$GH_STUB_DIR/prs.json"
  i=0; while [ -e "$P/$MARK" ] && [ "$i" -lt 400 ]; do sleep 0.1; i=$((i+1)); done
  [ -n "$pid" ] && kill "$pid" 2>/dev/null
  return 0
}
repark_flow "$WATCH" 415 fixed
[ "$RP_ALREADY" = 1 ] && ok "(E12) AC9: the re-park's launch prints 'already running pid=<kept watcher>'" || no "(E12) second launch: $(cat "$TOP/rp2-fixed.log")"
[ "$RP_N" = 1 ] && [ "$RP_R" = 1 ] && ok "(E12) AC10 after a re-park: the kept watcher reads the fresh check_pending line ⇒ exactly one now-mergeable + one recheck notify" || no "(E12) kept watcher: now-mergeable=$RP_N notifies=$RP_R"
# mutation control: delete EXACTLY the content-change reset ⇒ the latch is permanent again.
MUT12="$TOP/mut12"; mkdir -p "$MUT12"; cp -R "$SPYD"/* "$MUT12/"
grep -vxF '       [ "$esc_now" = "$esc_seen" ] || { esc_seen="$esc_now"; recheck_done=0; }' "$WATCH" > "$MUT12/automate-merge-watch.sh"
if [ -s "$MUT12/automate-merge-watch.sh" ] && ! cmp -s "$WATCH" "$MUT12/automate-merge-watch.sh" && bash -n "$MUT12/automate-merge-watch.sh" \
   && [ "$(( $(wc -l < "$WATCH") - $(wc -l < "$MUT12/automate-merge-watch.sh") ))" = "1" ]; then
  repark_flow "$MUT12/automate-merge-watch.sh" 416 mut
  [ "$RP_N" = 0 ] && ok "(E12) mutant (permanent latch restored) misses the re-park's fresh line — the reset is load-bearing" || no "(E12) mutant did not discriminate: now-mergeable=$RP_N"
else no "(E12) permanent-latch mutant invalid (empty / identical / bash -n / not exactly 1 line)"; fi

# (E13) the content-keyed latch never re-reports one line: a restarted watcher over the
# SAME check_pending line finds its now-mergeable report in ## Progress and stays silent.
closeout_fixture 417; spy_reset; we_open; rm -f "$GH_STUB_DIR/run-seq"
we_park check_pending --check claude-review --run-id 555 --attempt 1 --sha "$ESHA"
printf 'OPEN\nOPEN\nOPEN\nCLOSED\n' > "$GH_STUB_DIR/state-seq"; rj 1 completed success > "$GH_STUB_DIR/run-seq"
we_watch >/dev/null
spy_reset; printf 'OPEN\nOPEN\nCLOSED\n' > "$GH_STUB_DIR/state-seq"
we_watch >/dev/null
[ "$(we_n "merge-watch: now mergeable: claude-review green on $ESHA")" = "1" ] && [ "$(spy_count automate_escalation_recheck "$SPYLOG.webhook")" = "0" ] && ok "(E13) one line, two watchers (restart) ⇒ still exactly one now-mergeable report" || no "(E13) restart re-reported: $(we_n 'now mergeable')"

# (E14, review iteration 3 — restart latch keyed on text that does not identify the
# event) check_red_unrelated park (ci, run 777, attempt 1) → attempt 2 fails ⇒ one
# still-failing line → re-park (running → escalated) recording attempt 2 → attempt 3
# fails ⇒ a SECOND still-failing line. The restart latch is the gitignored
# `<run_id>.merge-watch-reported` sidecar (item + PR + line content), never a search
# of the whole run file. e14_flow <watcher> <fixture_n> → E14_A (lines after the
# first watcher), E14_B (after the re-parked one), E14_R (its recheck notifies).
E14_SC=".supervisor/automate/$RUN_ID.merge-watch-reported"
E14_FAIL='merge-watch: still failing: ci failure — rerun: gh run rerun 777 --failed'
e14_run() { (cd "$P" && LOOMWRIGHT_MERGE_WATCH_INTERVAL=0 LOOMWRIGHT_MERGE_WATCH_MAX_SECONDS=60 bash "$1" "$RF_REL" "$REQ" "$PRURL" </dev/null >/dev/null 2>&1); }
e14_flow() {
  closeout_fixture "$2"; spy_reset; we_open; rm -f "$GH_STUB_DIR/run-seq"
  we_park check_red_unrelated --check ci --run-id 777 --attempt 1 --sha "$ESHA"
  printf 'OPEN\nOPEN\nOPEN\nCLOSED\n' > "$GH_STUB_DIR/state-seq"; rj 2 completed failure > "$GH_STUB_DIR/run-seq"
  e14_run "$1"; E14_A="$(we_n "$E14_FAIL")"
  (cd "$P" && bash "$H" current-set "$RF_REL" --item "$REQ" --status running >/dev/null)
  we_park check_red_unrelated --check ci --run-id 777 --attempt 2 --sha "$ESHA"
  spy_reset; printf 'OPEN\nOPEN\nOPEN\nCLOSED\n' > "$GH_STUB_DIR/state-seq"; rj 3 completed failure > "$GH_STUB_DIR/run-seq"
  e14_run "$1"; E14_B="$(we_n "$E14_FAIL")"; E14_R="$(spy_count automate_escalation_recheck "$SPYLOG.webhook")"
  return 0
}
e14_flow "$WATCH" 418
[ "$E14_A" = 1 ] && [ "$E14_B" = 2 ] && [ "$E14_R" = 1 ] && [ "$(we_n "$E14_FAIL (attempt 3)")" = 1 ] && ok "(E14) AC11 after a re-park: attempt 3 red ⇒ a second still-failing line naming its attempt + one recheck notify" || no "(E14) lines=$E14_A/$E14_B notifies=$E14_R: $(grep 'still failing' "$P/$RF_REL" | tr '\n' '|')"
git -C "$P" check-ignore -q "$E14_SC" && ok "(E14) the reported-line sidecar is gitignored (not *.md ⇒ never in a trail)" || no "(E14) sidecar not gitignored"
spy_reset; printf 'OPEN\nOPEN\nCLOSED\n' > "$GH_STUB_DIR/state-seq"
e14_run "$WATCH"
[ "$(we_n "$E14_FAIL")" = 2 ] && [ "$(spy_count automate_escalation_recheck "$SPYLOG.webhook")" = 0 ] && ok "(E14) the same line across a restart ⇒ no repeat (sidecar)" || no "(E14) restart re-reported: $(we_n "$E14_FAIL")"
printf 'other-item\t%s\t%s\n' "$PRURL" "$(cut -f3- "$P/$E14_SC")" > "$P/$E14_SC"
spy_reset; printf 'OPEN\nOPEN\nCLOSED\n' > "$GH_STUB_DIR/state-seq"
e14_run "$WATCH"
[ "$(we_n "$E14_FAIL")" = 3 ] && [ "$(spy_count automate_escalation_recheck "$SPYLOG.webhook")" = 1 ] && ok "(E14) another item's sidecar entry never silences this item's line" || no "(E14) foreign sidecar suppressed: $(we_n "$E14_FAIL")"
# mutation control: replace EXACTLY the sidecar comparison with the old whole-run-file search.
MUT14="$TOP/mut14"; mkdir -p "$MUT14"; cp -R "$SPYD"/* "$MUT14/"
cat > "$TOP/mut14.line" <<'ML'
  awk -v b="merge-watch: still failing: $chk " -v r="gh run rerun ${rid:-<run_id>} --failed" 'index($0, b) && index($0, r) { f = 1 } END { exit !f }' "$rf_abs" 2>/dev/null && return 0
ML
E14_T='  [ "$(cat "$REPORTED" 2>/dev/null)" = "$key" ] && return 0'
T="$E14_T" awk 'NR == FNR { r = $0; next } $0 == ENVIRON["T"] { print r; next } { print }' "$TOP/mut14.line" "$WATCH" > "$MUT14/automate-merge-watch.sh"
if [ -s "$MUT14/automate-merge-watch.sh" ] && ! cmp -s "$WATCH" "$MUT14/automate-merge-watch.sh" && bash -n "$MUT14/automate-merge-watch.sh" \
   && [ "$(grep -cxF "$E14_T" "$WATCH")" = 1 ] && [ "$(grep -cxF "$E14_T" "$MUT14/automate-merge-watch.sh")" = 0 ] \
   && [ "$(wc -l < "$WATCH")" = "$(wc -l < "$MUT14/automate-merge-watch.sh")" ]; then
  e14_flow "$MUT14/automate-merge-watch.sh" 419
  [ "$E14_A" = 1 ] && [ "$E14_B" = 1 ] && ok "(E14) mutant (whole-run-file search restored) swallows attempt 3's report — the line-keyed sidecar is load-bearing" || no "(E14) mutant did not discriminate: lines=$E14_A/$E14_B"
else no "(E14) whole-file-search mutant invalid (empty / identical / bash -n / not a 1-for-1 line swap)"; fi

echo "== K. SKILL wiring (Part B) =="
grep -qF 'automate-merge-watch.sh' "$SKILL" && ok "SKILL names automate-merge-watch.sh" || no "SKILL lacks the watcher"
step1="$(grep -m1 -E '^1\. \*\*RECONCILE' "$SKILL")"
a="${step1%%closeout*}"; b="${step1%%PICK*}"
if [ -n "$step1" ] && [ "$a" != "$step1" ] && grep -qF -- '--session-id' <<<"$step1" && [ "${#a}" -lt "${#b}" ]; then ok "AC14: §6 step 1 runs closeout --session-id before PICK"; else no "AC14: §6 step 1 closeout wiring"; fi
hits="$(grep -nE 're-checks the PR each tick|resumes once|resume[sd]? on merge' "$SKILL" "$HERE/../commands/automate.md" "$HERE/../docs/RESULT_SCHEMAS.md" "$HERE"/../docs/result-schemas/*.md || true)"
[ -z "$hits" ] && ok "AC14: decision-9 grep has no per-tick/auto-resume claim" || no "decision-9 hits: $hits"
grep -qF '/loop` re-invokes `/automate` each tick' "$SKILL" && ok "§12's accurate /loop tick sentence kept" || no "§12 /loop sentence changed"
grep -qF 'closeout' "$HERE/../commands/automate.md" && grep -qF 'trail-pr' "$HERE/../commands/automate.md" && ok "commands/automate.md mirrors the surface" || no "commands/automate.md surface missing"

echo "== BM. branch mode: trail-pr pushes to the metadata branch (no PR), evidence-gated, loud on failure =="
# skills/automate-loop/SKILL.md §"Branch mode". Hermetic: the fixture's LOCAL bare origin, never
# GitHub; the gh stub records every call and these cases FAIL if `pr create` is ever invoked.
# The committed sidecar fixtures cite vikashruhilgit/loomwright; the stub PRs cite acme/widgets.
export LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="acme/widgets,vikashruhilgit/loomwright"
BM_MEM="$HERE/setup-memory.sh"; BM_MS="$HERE/meta-sync.sh"; BMB="loomwright-meta"
# bm_switch: run history IGNORED (the post-migration shape, so a kept check-ignore drop would push
# nothing), the branch-mode block, an allowlisted ledger, and an initialised metadata branch.
bm_switch() {
  ( cd "$P"
    printf '.supervisor/\n' > .gitignore
    bash "$BM_MEM" --root "$P" apply --branch-mode "$BMB" >/dev/null 2>&1; rm -f .gitignore.backup.*
    printf '{"repo":"acme/widgets","automate_key":"%s\\u001fx","source":"automate_drain"}\n' "$RUN_ID" > .supervisor/postmortem/results.jsonl
    bash "$BM_MS" init --root "$P" --branch "$BMB" >/dev/null 2>&1 )
}
bm_tree() { git --git-dir="$FX/origin.git" ls-tree -r --name-only "refs/heads/$BMB" 2>/dev/null; }
bm_show() { git --git-dir="$FX/origin.git" show "refs/heads/$BMB:$1" 2>/dev/null; }
bm_trail() { (cd "$P" && bash "${BM_HELPER:-$H}" trail-pr "$RF_REL0" --reason "${1:-done}"); }

# (bm-a) merged item ⇒ meta-pushed, NO PR, no trail worktree; the branch holds the stamp + run file.
new_fixture 80; bm_switch
[ "$(bash "$BM_MEM" --root "$P" mode)" = "on $BMB" ] && ok "(bm-a) fixture is in branch mode" || no "(bm-a) fixture mode: $(bash "$BM_MEM" --root "$P" mode)"
git -C "$P" check-ignore -q -- "$RF_REL0" && ok "(bm-a) the run file is gitignored (a kept check-ignore drop would push nothing)" || no "(bm-a) run file not ignored in the fixture"
stamp_req "$REQ" done "$PRL"; set_pr "$PRURL" MERGED
wt_before="$(git -C "$P" worktree list | wc -l | tr -d ' ')"
out="$(bm_trail done)"; rc=$?
[ "$rc" -eq 0 ] && case "$out" in "trail-pr: meta-pushed $BMB"*) true ;; *) false ;; esac && ok "(bm-a) mode on ⇒ '$out', exit 0" || no "(bm-a) trail-pr: '$out' rc=$rc"
[ "$(count_creates)" = 0 ] && ok "(bm-a) gh pr create NEVER invoked in branch mode" || no "(bm-a) gh pr create was invoked: $(grep '^pr create' "$GH_STUB_DIR/argv.log")"
[ "$(git -C "$P" worktree list | wc -l | tr -d ' ')" = "$wt_before" ] && ok "(bm-a) no trail worktree created" || no "(bm-a) a worktree was added"
names="$(bm_tree)"
grep -qxF -- "$RF_REL0" <<<"$names" && ok "(bm-a) the branch holds the run file" || no "(bm-a) branch tree: $names"
grep -q '^## Status: done' < <(bm_show "$REQ") && ok "(bm-a) the branch holds the MERGED item's done stamp" || no "(bm-a) stamp not on the branch"
[ -z "$(git -C "$P" ls-remote --heads origin "chore/$RUN_ID-trail-*")" ] && ok "(bm-a) no chore/<run>-trail-* branch pushed" || no "(bm-a) a trail branch was pushed"
[ ! -f "$P/.supervisor/automate/$RUN_ID.trail-staged" ] && ok "(bm-a) no .trail-staged record written" || no "(bm-a) .trail-staged written"

# (bm-b) UNMERGED item ⇒ excluded and named; its done stamp is NOT on the branch.
bm_unmerged() {  # <helper> → sets BM_OUT; 0 when the unmerged stamp stayed off the branch
  new_fixture "$1"; bm_switch; stamp_req "$REQ" done "$PRL"; set_pr "$PRURL" OPEN
  BM_OUT="$(BM_HELPER="$2" bm_trail done)"
  ! grep -q '^## Status: done' < <(bm_show "$REQ")
}
if bm_unmerged 81 "$H"; then ok "(bm-b) unmerged item's done stamp is NOT on the branch"; else no "(bm-b) unmerged stamp reached the branch"; fi
case "$BM_OUT" in "trail-pr: meta-pushed $BMB"*"; excluded $REQ — pr not merged"*) ok "(bm-b) '$BM_OUT'" ;; *) no "(bm-b) output: '$BM_OUT'" ;; esac
# Mutation control (ii): a patched copy that bypasses _evidence_gate on the mode-on push list MUST
# turn (bm-b) red.
MUTD="$TOP/bm-mut"; mkdir -p "$MUTD"; cp "$HERE"/*.sh "$HERE"/*.py "$MUTD/" 2>/dev/null; cp -R "$HERE/automate-helpers.d" "$MUTD/"
awk 'skip && /^  _evidence_gate$/ { skip = 0; next } { skip = 0 } /^  TRAIL_SKIP_IGNORE_DROP=0$/ { skip = 1 } { print }' "$HERE/automate-trail.sh" > "$MUTD/automate-trail.sh"
if cmp -s "$HERE/automate-trail.sh" "$MUTD/automate-trail.sh"; then no "(bm-b) mutation control (ii): the patch changed nothing — control inconclusive"
elif bm_unmerged 82 "$MUTD/automate-helpers.sh"; then no "(bm-b) mutation control (ii) REFUTED: bypassing _evidence_gate still kept the stamp off the branch"
else ok "(bm-b) mutation control (ii): bypassing _evidence_gate puts the unmerged stamp on the branch — the assertion is load-bearing"; fi

# (bm-c) a dropped dismissed draft becomes a real deletion on the branch.
new_fixture 83; bm_switch; set_pr "$PRURL" OPEN
DRN="$RUN_ID--01-a--dismissed-1.md"; DRP=".supervisor/requirements/proposed/$DRN"
mkdir -p "$P/.supervisor/requirements/proposed"; printf '# draft\n## Status: proposed\n' > "$P/$DRP"
bm_trail done >/dev/null
grep -qxF -- "$DRP" < <(bm_tree) && ok "(bm-c) precondition: the undecided draft rode a push" || no "(bm-c) precondition: draft not on the branch"
rm -f "$P/$DRP"; printf '%s\tdrop\n' "$DRN" > "$P/.supervisor/automate/$RUN_ID.dismissed-decisions"
out="$(bm_trail done)"
grep -qxF -- "$DRP" < <(bm_tree) && no "(bm-c) the dropped draft is still on the branch ($out)" || ok "(bm-c) the dropped draft is DELETED on the branch ($out)"

# (bm-d) a push meta-sync refuses (scrub hit) is LOUD: exit 0, Progress line, notify, marker; the
# next successful push removes the marker.
new_fixture 84; bm_switch; set_pr "$PRURL" OPEN
printf -- '- t1 see /Users/someone/notes.txt\n' >> "$P/$RF_REL0"
spy_reset; : > "$SPYLOG"
out="$(cd "$P" && bash "$SPYD/automate-helpers.sh" trail-pr "$RF_REL0" --reason done)"; rc=$?
case "$out" in "trail-pr: meta-push FAILED — scrub "*) ok "(bm-d) scrub hit ⇒ '$out'" ;; *) no "(bm-d) scrub hit output: '$out'" ;; esac
[ "$rc" -eq 0 ] && ok "(bm-d) trail-pr exits 0 on a refused push" || no "(bm-d) rc=$rc"
grep -q '^- .*meta-push FAILED: scrub ' "$P/$RF_REL0" || grep -q 'meta-push FAILED: scrub ' "$P/$RF_REL0"; [ $? -eq 0 ] && ok "(bm-d) the 'meta-push FAILED:' line is in ## Progress" || no "(bm-d) no Progress line"
MK="$P/.supervisor/automate/$RUN_ID.meta-push-failed"
[ -f "$MK" ] && ok "(bm-d) the .meta-push-failed marker is written" || no "(bm-d) marker missing"
grep -q 'meta_sync: scrub ' "$MK" 2>/dev/null && ok "(bm-d) the marker carries the full scrub list" || no "(bm-d) marker lacks the scrub list"
[ "$(spy_count notify "$SPYLOG.notify")" -ge 1 ] && [ "$(spy_count automate_meta_push "$SPYLOG.webhook")" -ge 1 ] && ok "(bm-d) notify-desktop + send-webhook fired" || no "(bm-d) notify pair did not fire"
mp="$(bash "$H" meta-push-failed "$P/$RF_REL0")"
case "$mp" in *"scrub "*) ok "(bm-d) meta-push-failed prints the marker ($mp)" ;; *) no "(bm-d) meta-push-failed: '$mp'" ;; esac
[ "$(count_creates)" = 0 ] && ok "(bm-d) no gh pr create on the failure path" || no "(bm-d) pr create invoked"
grep -v '/Users/someone/' "$P/$RF_REL0" > "$P/rf.tmp" && mv "$P/rf.tmp" "$P/$RF_REL0"
out="$(bm_trail done)"
case "$out" in "trail-pr: meta-pushed $BMB"*) ok "(bm-d) the next push succeeds ($out)" ;; *) no "(bm-d) retry: '$out'" ;; esac
[ ! -f "$MK" ] && [ -z "$(bash "$H" meta-push-failed "$P/$RF_REL0")" ] && ok "(bm-d) a successful push removes the marker" || no "(bm-d) marker survived a successful push"

# (bm-e) mode unknown ⇒ loud failure, nothing pushed.
new_fixture 85; bm_switch
awk '{print} index($0, "# loomwright-meta-branch: ") == 1 {print "# loomwright-meta-branch: other"}' "$P/.gitignore" > "$P/g" && mv "$P/g" "$P/.gitignore"
out="$(bm_trail done)"
case "$out" in "trail-pr: meta-push FAILED — mode unknown "*) ok "(bm-e) mode unknown ⇒ '$out'" ;; *) no "(bm-e) mode unknown: '$out'" ;; esac
[ -f "$P/.supervisor/automate/$RUN_ID.meta-push-failed" ] && ok "(bm-e) mode unknown writes the marker" || no "(bm-e) no marker"

# (bm-f) trail-unstage in branch mode ⇒ skipped, index untouched.
new_fixture 86; bm_switch
(cd "$P" && git add -f "$RF_REL0" >/dev/null 2>&1)
idx_before="$(git -C "$P" diff --cached --name-only)"
out="$(cd "$P" && bash "$H" trail-unstage "$RF_REL0")"
[ "$out" = "trail-unstage: skipped — branch mode" ] && ok "(bm-f) '$out'" || no "(bm-f) trail-unstage: '$out'"
[ "$(git -C "$P" diff --cached --name-only)" = "$idx_before" ] && ok "(bm-f) the index is untouched" || no "(bm-f) index changed"

# (bm-g) closeout on a merged item in branch mode: no PR, the branch holds the run file + stamp.
closeout_fixture 87
( cd "$P" && git pull -q --ff-only origin main >/dev/null 2>&1 )
bm_switch
( cd "$P" && git add .gitignore && git commit -qm "branch mode" && git push -q origin main ) >/dev/null 2>&1
: > "$GH_STUB_DIR/argv.log"
out="$(cd "$P" && bash "$H" closeout "$RF_REL" "$REQ" "$PRURL")"
grep -q 'meta-pushed' <<<"$out" && ok "(bm-g) closeout's trail step meta-pushed" || no "(bm-g) closeout output: $out"
[ "$(count_creates)" = 0 ] && ok "(bm-g) closeout opened NO PR in branch mode" || no "(bm-g) pr create invoked by closeout"
grep -qxF -- "$RF_REL" < <(bm_tree) && ok "(bm-g) the branch holds the run file after closeout" || no "(bm-g) branch tree: $(bm_tree | tr '\n' ' ')"
grep -q '^## Status: done' < <(bm_show "$REQ") && ok "(bm-g) the branch holds the closed-out item's stamp" || no "(bm-g) closed-out stamp not on the branch"

# A1: the SKILL's "No park calls it" list carries meta_unreachable (it runs before the PICK lock).
case "$nopark" in *meta_unreachable*) ok "(bm) the no-park list names meta_unreachable" ;; *) no "(bm) meta_unreachable missing from the 'No park calls it' list" ;; esac

# (bm-h) a repo that NEVER opted in keeps the mode-off PR path even when its .gitignore is one the
# setup-memory WRITER refuses (read-only / conflict-marked): the mode reader decides `off` from
# content, so trail-pr must open its PR exactly as today — never route to a FAILED meta-push.
new_fixture 88; chmod 444 "$P/.gitignore"
out="$(bm_trail done)"; rc=$?
chmod 644 "$P/.gitignore"
case "$out" in "trail-pr: opened https://github.com/acme/widgets/pull/"*) [ "$rc" -eq 0 ] && ok "(bm-h) never opted in + read-only .gitignore ⇒ PR path ($out)" || no "(bm-h) read-only rc=$rc" ;; *) no "(bm-h) read-only, never opted in ⇒ '$out'" ;; esac
[ "$(count_creates)" = 1 ] && ok "(bm-h) read-only: exactly one gh pr create (mode-off path)" || no "(bm-h) read-only: pr create count $(count_creates)"
[ ! -f "$P/.supervisor/automate/$RUN_ID.meta-push-failed" ] && ok "(bm-h) read-only: no .meta-push-failed marker" || no "(bm-h) read-only: marker written"
grep -q 'meta-push FAILED' "$P/$RF_REL0" && no "(bm-h) read-only: a meta-push FAILED Progress line was appended" || ok "(bm-h) read-only: no meta-push FAILED Progress line"
new_fixture 89; printf '<<<<<<< HEAD\nzz-a/\n=======\nzz-b/\n>>>>>>> other\n' >> "$P/.gitignore"
out="$(bm_trail done)"
case "$out" in "trail-pr: opened https://github.com/acme/widgets/pull/"*) ok "(bm-h) never opted in + conflict-marked .gitignore ⇒ PR path ($out)" ;; *) no "(bm-h) conflict-marked, never opted in ⇒ '$out'" ;; esac
[ ! -f "$P/.supervisor/automate/$RUN_ID.meta-push-failed" ] && ok "(bm-h) conflict-marked: no .meta-push-failed marker" || no "(bm-h) conflict-marked: marker written"

# (bm-i) review iteration 3 — _branch_mode is FAIL-CLOSED on the answer's SHAPE. Only `off` and
# `on <non-empty>` pass through; an `on ` (empty-branch) answer is `unknown`, so trail-pr fails LOUD
# without ever invoking meta-sync; and a stripped copy (no sibling reader) treats near-miss mode text
# (no space after the colon) as `unknown`, never `off` (which would open a PR in a branch-mode repo).
BMI="$TOP/bm-i"; mkdir -p "$BMI/stub" "$BMI/strip"
cp "$HERE"/*.sh "$HERE"/*.py "$BMI/stub/" 2>/dev/null; cp -R "$HERE/automate-helpers.d" "$BMI/stub/"; cp "$HERE"/*.sh "$HERE"/*.py "$BMI/strip/" 2>/dev/null; cp -R "$HERE/automate-helpers.d" "$BMI/strip/"
printf '#!/bin/bash\necho "on "\n' > "$BMI/stub/setup-memory.sh"
rm -f "$BMI/strip/setup-memory.sh"
printf '#!/bin/bash\necho invoked >> "%s/ms.log"\nexit 0\n' "$BMI" > "$BMI/spy-ms.sh"
bmi_trail() { (cd "$P" && LOOMWRIGHT_META_SYNC_BIN="$BMI/spy-ms.sh" bash "$1/automate-helpers.sh" trail-pr "$RF_REL0" --reason done); }
new_fixture 90; bm_switch; rm -f "$BMI/ms.log"
out="$(bmi_trail "$BMI/stub")"
[ "$out" = "trail-pr: meta-push FAILED — mode unknown setup-memory.sh mode printed 'on '" ] && ok "(bm-i) an 'on ' (empty-branch) reader answer ⇒ '$out'" || no "(bm-i) 'on ' answer ⇒ '$out'"
[ ! -e "$BMI/ms.log" ] && ok "(bm-i) meta-sync was NEVER invoked on the empty-branch answer" || no "(bm-i) meta-sync invoked with an empty branch"
[ "$(count_creates)" = 0 ] && ok "(bm-i) no gh pr create on the empty-branch answer" || no "(bm-i) pr create invoked"
# Mutation control: the pre-fix _branch_mode (no shape check) passes `on ` through and runs meta-sync.
awk '/^  case "\$m" in$/ && !done { skip = 4; done = 1 } skip > 0 { skip--; next } { print }' "$BMI/stub/automate-trail.sh" > "$BMI/stub/at.mut" && mv "$BMI/stub/at.mut" "$BMI/stub/automate-trail.sh"
if cmp -s "$HERE/automate-trail.sh" "$BMI/stub/automate-trail.sh"; then no "(bm-i) mutation control: the patch changed nothing — inconclusive"
else
  new_fixture 91; bm_switch; rm -f "$BMI/ms.log"; bmi_trail "$BMI/stub" >/dev/null
  [ -e "$BMI/ms.log" ] && ok "(bm-i) mutation control: without the shape check meta-sync IS invoked on 'on ' — the assertion is load-bearing" || no "(bm-i) mutation control REFUTED: meta-sync still not invoked"
fi
# Stripped copy + a no-space near-miss inside the block ⇒ unknown (loud), not the mode-off PR path.
new_fixture 92; bm_switch
sed 's/^# loomwright-meta-branch: /# loomwright-meta-branch:/' "$P/.gitignore" > "$P/g" && mv "$P/g" "$P/.gitignore"
: > "$GH_STUB_DIR/argv.log"
out="$(bmi_trail "$BMI/strip")"
[ "$out" = "trail-pr: meta-push FAILED — mode unknown setup-memory.sh is missing beside automate-trail.sh" ] && ok "(bm-i) stripped copy + no-space near-miss ⇒ '$out'" || no "(bm-i) stripped copy + near-miss ⇒ '$out'"
[ "$(count_creates)" = 0 ] && ok "(bm-i) stripped copy + near-miss: no gh pr create" || no "(bm-i) stripped copy + near-miss opened a PR"
sed "s/grep -qF 'loomwright-meta-branch' /grep -q '^# loomwright-meta-branch: ' /" "$BMI/strip/automate-trail.sh" > "$BMI/strip/at.mut"
if cmp -s "$BMI/strip/automate-trail.sh" "$BMI/strip/at.mut"; then no "(bm-i) fallback mutation control: the patch changed nothing — inconclusive"
else
  mv "$BMI/strip/at.mut" "$BMI/strip/automate-trail.sh"
  out="$(bmi_trail "$BMI/strip")"
  case "$out" in *"mode unknown"*) no "(bm-i) fallback mutation control REFUTED: the prefix-only grep still reads unknown ($out)" ;; *) ok "(bm-i) fallback mutation control: the prefix-only grep reads the near-miss as off ($out) — the assertion is load-bearing" ;; esac
fi
unset LOOMWRIGHT_MEMORY_REPO_ALLOWLIST

# =============================================================================
echo "== F. finalize-empty / resume-glob --finalize (a closed-out run finalizes itself) =="
# SKILL §1.5 `finalize-empty` row, §3 "`done`", §4 step 1. closeout never writes
# `done`; a finished lane run stayed paused/awaiting_go and every RESUME listed it.
AUTD=".supervisor/automate"
fe_glob() { (cd "$P" && bash "${FE_H:-$SPYD/automate-helpers.sh}" resume-glob "$AUTD" --finalize 2>"$FX/fe.err"); }
fe_rf() { # <run_id> <status> <pause_reason> <REQ queue box> <current status>
  cat > "$P/$AUTD/$1.md" <<RF
# Automate Run: fixture $1
## Status: $2
## Queue
- [$4] $REQ
- [x] .supervisor/requirements/f/02-b.md  # skipped: owner said so
## Current
- item: $REQ | status: $5 | pr: $PRURL | branch: feature/x
- pause_reason: $3
## Progress
- t0 picked $REQ
RF
}

# (F0) invariant: a closeout that checks off the LAST Queue item leaves ## Status: paused.
fe_invariant() { # <fixture-n> <scripts-dir> → 0 when the run stayed paused/awaiting_go with remaining 0
  closeout_fixture "$1"
  (cd "$P" && bash "$2/automate-helpers.sh" closeout "$RF_REL" "$REQ" "$PRURL" >/dev/null)
  [ "$(bash "$H" remaining "$P/$RF_REL")" = 0 ] && grep -qxF -- "## Status: paused" "$P/$RF_REL" && grep -qxF -- "- pause_reason: awaiting_go" "$P/$RF_REL"
}
if fe_invariant 200 "$SPYD"; then ok "(F0) closeout checking off the last item leaves ## Status: paused / awaiting_go (remaining 0) — closeout never writes done"; else no "(F0) closeout state: $(grep -E '^## Status|^- pause_reason' "$P/$RF_REL" | tr '\n' '|')"; fi
MUTF="$TOP/mutd-done"; mkdir -p "$MUTF"; cp "$HERE"/*.sh "$HERE"/*.py "$MUTF/"; cp -R "$HERE/automate-helpers.d" "$MUTF/"
awk '{ print } index($0, "    echo \"closeout: reconciled — ## Current $item status done, pause_reason $want\"")==1 { print "    { sed \"s/^## Status: paused/## Status: done/\" \"$rf\" > \"$rf.m\" && mv \"$rf.m\" \"$rf\"; }" }' "$T" > "$MUTF/automate-trail.sh"
if cmp -s "$T" "$MUTF/automate-trail.sh" || ! bash -n "$MUTF/automate-trail.sh"; then no "(F0) closeout-writes-done mutant not built"
elif fe_invariant 201 "$MUTF"; then no "(F0) mutation control REFUTED: a closeout that writes done still passed the invariant leg"
else ok "(F0) control: a closeout mutant that writes '## Status: done' turns the invariant leg red ($(grep '^## Status' "$P/$RF_REL"))"
fi

# (F1) branch mode OFF: closeout leaves the eligible state; resume-glob --finalize finalizes it.
closeout_fixture 202
run_closeout >/dev/null
[ -n "$(git -C "$P" diff --cached --name-only)" ] && ok "(F1) precondition: closeout's trail-pr left trail blobs staged in the primary index" || no "(F1) precondition: nothing staged after closeout"
plain_before="$(cd "$P" && bash "$H" resume-glob "$AUTD")"
[ "$plain_before" = "$AUTD/$RUN_ID.md" ] && ok "(F1) plain resume-glob lists the closed-out run (the incident)" || no "(F1) plain list: $plain_before"
spy_reset
lst="$(fe_glob)"; rc=$?
sed 's/^/    | /' "$FX/fe.err"
[ "$rc" -eq 0 ] && [ -z "$lst" ] && ok "(F1) resume-glob --finalize: exit 0 and the finalized run is NOT listed" || no "(F1) rc=$rc list='$lst'"
grep -qxF -- "## Status: done" "$P/$RF_REL" && grep -qxF -- "- pause_reason: null" "$P/$RF_REL" && ok "(F1) ## Status: done + pause_reason: null" || no "(F1) state: $(grep -E '^## Status|^- pause_reason' "$P/$RF_REL" | tr '\n' '|')"
grep -qxF -- "- item: $REQ | status: done | pr: $PRURL | branch: feature/x" "$P/$RF_REL" && ok "(F1) ## Current item line byte-unchanged" || no "(F1) item line changed"
grep -qE '^- [^ ]+ auto-finalized: queue empty after closeout$' "$P/$RF_REL" && ok "(F1) Progress: auto-finalized: queue empty after closeout" || no "(F1) no auto-finalized line"
grep -qE "^trail-pr $P/$RF_REL --reason done\$" "$SPYLOG" && ok "(F1) trail-pr <runfile> --reason done via the dispatcher (the Termination call)" || no "(F1) trail-pr call: $(tr '\n' '|' < "$SPYLOG" 2>/dev/null)"
grep -qE '^- [^ ]+ trail-pr: (opened|pushed|skipped)' "$P/$RF_REL" && ok "(F1) the trail line is appended to ## Progress" || no "(F1) trail line not appended"
grep -qxF "finalize-empty: finalized $AUTD/$RUN_ID.md" < <(head -n1 "$FX/fe.err") && grep -q '^trail-unstage: ' "$FX/fe.err" && ok "(F1) stderr: finalized line + trail-unstage line" || no "(F1) stderr: $(tr '\n' '|' < "$FX/fe.err")"
stg="$(git -C "$P" diff --cached --name-only)"
[ -z "$stg" ] && ok "(F1) mode off: the primary index carries NO staged path of the finalized run" || no "(F1) still staged: $(printf '%s' "$stg" | tr '\n' ' ')"
[ ! -d "$P/.supervisor/run.lock" ] && ok "(F1) run lock released" || no "(F1) run lock leaked"
c1="$(cksum < "$P/$RF_REL")"
o2="$(cd "$P" && bash "$H" finalize-empty "$RF_REL")"
[ "$o2" = "finalize-empty: skipped — not paused" ] && [ "$c1" = "$(cksum < "$P/$RF_REL")" ] && ok "(F1) a second finalize is a no-op ('$o2')" || no "(F1) second finalize: '$o2'"
# Control: without the mode-off trail-unstage the finalized run's trail blobs stay staged.
MUTU="$TOP/mutd-unstage"; mkdir -p "$MUTU"; cp "$HERE"/*.sh "$HERE"/*.py "$MUTU/"; cp -R "$HERE/automate-helpers.d" "$MUTU/"
grep -v 'l="$(bash "$HLP" trail-unstage "$rf_abs"' "$T" > "$MUTU/automate-trail.sh"
if cmp -s "$T" "$MUTU/automate-trail.sh" || ! bash -n "$MUTU/automate-trail.sh"; then no "(F1) unstage mutant not built"
else
  closeout_fixture 203; run_closeout >/dev/null
  FE_H="$MUTU/automate-helpers.sh" fe_glob >/dev/null
  grep -qxF -- "## Status: done" "$P/$RF_REL" && [ -n "$(git -C "$P" diff --cached --name-only)" ] \
    && ok "(F1) control: without trail-unstage the finalized run leaves staged trail paths (the clean-index assertion is load-bearing)" || no "(F1) unstage control did not discriminate"
fi
# (F1b) the pause_reason line is authored by current-set (SKILL §3 "every write of …
# its `- pause_reason:` line is ONE current-set call"), run on the STAGED copy — the
# run file itself still changes in one runfile-write.
grep -qE "^current-set /[^ ]*/$AUTD/$RUN_ID\.md\.fe\.[A-Za-z0-9]+ --pause-reason null\$" "$SPYLOG" \
  && ok "(F1b) finalize-empty writes pause_reason via current-set --pause-reason null on the staged copy" \
  || no "(F1b) current-set call: $(grep '^current-set' "$SPYLOG" 2>/dev/null | tr '\n' '|')"
[ -z "$(cd "$P/$AUTD" && ls -A | grep -F '.fe.')" ] && ok "(F1b) no staged .fe. copy left behind" || no "(F1b) leftover: $(ls -A "$P/$AUTD" | tr '\n' ' ')"
# A refusing current-set leaves the run file byte-unchanged and still eligible
# (still listed; a later --finalize retries) — never a half-finalized done+awaiting_go.
MUTC="$TOP/mutd-cs"; mkdir -p "$MUTC"; cp "$HERE"/*.sh "$HERE"/*.py "$MUTC/"; cp -R "$HERE/automate-helpers.d" "$MUTC/"
mv "$MUTC/automate-helpers.sh" "$MUTC/automate-helpers.real.sh"
cat > "$MUTC/automate-helpers.sh" <<'SHIM'
#!/usr/bin/env bash
if [ "${1:-}" = current-set ]; then echo "current-set: refused — test" >&2; exit 1; fi
exec bash "$(dirname "$0")/automate-helpers.real.sh" "$@"
SHIM
closeout_fixture 206; run_closeout >/dev/null
c0="$(cksum < "$P/$RF_REL")"
lst="$(FE_H="$MUTC/automate-helpers.sh" fe_glob)"
[ "$lst" = "$AUTD/$RUN_ID.md" ] && [ "$c0" = "$(cksum < "$P/$RF_REL")" ] && grep -q 'not finalized — finalize-empty: skipped — runfile-write refused' "$FX/fe.err" \
  && [ -z "$(cd "$P/$AUTD" && ls -A | grep -F '.fe.')" ] && [ ! -d "$P/.supervisor/run.lock" ] \
  && ok "(F1b) current-set refusal ⇒ run file byte-unchanged, still listed, no staged copy, lock released" \
  || no "(F1b) refusal leg: list='$lst' stderr=$(tr '\n' '|' < "$FX/fe.err")"
lst="$(fe_glob)"
[ -z "$lst" ] && grep -qxF -- "## Status: done" "$P/$RF_REL" && grep -qxF -- "- pause_reason: null" "$P/$RF_REL" \
  && ok "(F1b) the next --finalize retries cleanly and finalizes" || no "(F1b) retry: list='$lst'"

# (F2) eligibility + lock: only paused/awaiting_go/remaining-0/Current-done runs finalize.
new_fixture 204
( cd "$P" && git checkout -q -- README; rm -f stray.txt; rm -f "$AUTD"/*.md )
fe_rf automate-a-eligible paused awaiting_go x done
fe_rf automate-b-unchecked paused awaiting_go ' ' done
fe_rf automate-c-otherreason paused awaiting_merge x done
fe_rf automate-d-curnotdone paused awaiting_go x awaiting_merge
fe_rf automate-e-eligible paused awaiting_go x done
want_all="$(printf '%s\n' "$AUTD/automate-a-eligible.md" "$AUTD/automate-b-unchecked.md" "$AUTD/automate-c-otherreason.md" "$AUTD/automate-d-curnotdone.md" "$AUTD/automate-e-eligible.md")"
[ "$(cd "$P" && bash "$H" resume-glob "$AUTD")" = "$want_all" ] && ok "(F2) plain resume-glob output unchanged (all five listed, sorted)" || no "(F2) plain list: $(cd "$P" && bash "$H" resume-glob "$AUTD" | tr '\n' ' ')"
sums() { (cd "$P/$AUTD" && cksum automate-*.md); }
s0="$(sums)"
bash "$HERE/run-lock.sh" acquire --owner fe-test-holder --root "$P" >/dev/null 2>&1
lst="$(fe_glob)"
[ "$lst" = "$want_all" ] && [ "$s0" = "$(sums)" ] && ok "(F2) run lock held ⇒ nothing finalized, every run listed, all byte-unchanged" || no "(F2) lock-held list: $(printf '%s' "$lst" | tr '\n' ' ')"
[ "$(grep -c 'not finalized — finalize-empty: skipped — run lock held by fe-test-holder' "$FX/fe.err")" = 2 ] && ok "(F2) stderr names the lock holder for both eligible runs" || no "(F2) stderr: $(tr '\n' '|' < "$FX/fe.err")"
bash "$HERE/run-lock.sh" release --owner fe-test-holder --root "$P" >/dev/null 2>&1
spy_reset
lst="$(fe_glob)"
sed 's/^/    | /' "$FX/fe.err"
want_rest="$(printf '%s\n' "$AUTD/automate-b-unchecked.md" "$AUTD/automate-c-otherreason.md" "$AUTD/automate-d-curnotdone.md")"
[ "$lst" = "$want_rest" ] && ok "(F2) lock released ⇒ the two eligible runs finalized; unchecked / other pause_reason / Current-not-done listed" || no "(F2) list: $(printf '%s' "$lst" | tr '\n' ' ')"
for r in automate-a-eligible automate-e-eligible; do grep -qxF -- "## Status: done" "$P/$AUTD/$r.md" || no "(F2) $r not done"; done
s1="$(sums | grep -v -e '-eligible\.md$')"; s0r="$(printf '%s\n' "$s0" | grep -v -e '-eligible\.md$')"
[ "$s1" = "$s0r" ] && ok "(F2) ineligible runs byte-untouched" || no "(F2) an ineligible run was modified"
[ "$(spy_count '^trail-pr .* --reason done$' "$SPYLOG")" = 2 ] && [ "$(count_creates)" = 2 ] && ok "(F2) mode off: one trail-pr --reason done (one trail PR) per finalized run" || no "(F2) trail calls: $(spy_count '^trail-pr' "$SPYLOG") creates: $(count_creates)"
[ "$(grep -c '^finalize-empty: finalized ' "$FX/fe.err")" = 2 ] && ! grep -q 'not finalized' "$FX/fe.err" && ok "(F2) stderr: two finalized lines, no ineligible noise" || no "(F2) stderr: $(tr '\n' '|' < "$FX/fe.err")"

# (F3) branch mode ON: finalized; trail-pr meta-pushes (no PR), no trail-unstage.
export LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="acme/widgets,vikashruhilgit/loomwright"
new_fixture 205; bm_switch
fe_rf "$RUN_ID" paused awaiting_go x done
: > "$GH_STUB_DIR/argv.log"
lst="$(fe_glob)"
sed 's/^/    | /' "$FX/fe.err"
[ -z "$lst" ] && grep -qxF -- "## Status: done" "$P/$RF_REL" && ok "(F3) branch mode: finalized and not listed" || no "(F3) list='$lst' status=$(grep '^## Status' "$P/$RF_REL")"
grep -q "^trail-pr: meta-pushed $BMB" "$FX/fe.err" && ! grep -q '^trail-unstage' "$FX/fe.err" && ok "(F3) trail meta-pushed; no trail-unstage in branch mode" || no "(F3) stderr: $(tr '\n' '|' < "$FX/fe.err")"
[ "$(count_creates)" = 0 ] && ok "(F3) no gh pr create in branch mode" || no "(F3) a PR was created"
grep -qxF -- "## Status: done" < <(bm_show "$RF_REL0") && ok "(F3) the metadata branch holds the finalized run file" || no "(F3) branch run file not done"
unset LOOMWRIGHT_MEMORY_REPO_ALLOWLIST

# =============================================================================
echo "== CL. closeout-classify: every closeout string is classified; kept/unknown/refusal ⇒ leftover (automate-followups/32 Part A) =="
# SKILL §1.5 `closeout-classify` row, §6 step 1 "Close-out leftover gate".
cls() { bash "$H" closeout-classify "$@"; }
# (CL1) table drift guard: every closeout string template automate-trail.sh can
# print (closeout, _co_current, _sync_primary's SYNC_SKIP) matches a CLOSEOUT_TABLE
# row — a new string must be classified on purpose, never fall through as unknown.
co_templates() { # <automate-trail.sh> → one sample line per closeout string template
  awk '/^_sync_primary\(\) \{/{on=1} /^# finalize-empty \(SKILL/{on=0} on && $0 !~ /^[[:space:]]*#/' "$1" \
    | grep -oE '((echo |=)"(\$S |closeout: )[^"]*"|SYNC_SKIP="[^"]*")' \
    | sed -E 's/^(echo |=)"//; s/^SYNC_SKIP="/closeout: skipped — /; s/"$//; s/^\$S /closeout: skipped — /' \
    | sed -E 's/\$\([^)]*\)/X/g; s/\$\{[^}]*\}/X/g; s/\$[A-Za-z_][A-Za-z0-9_]*/X/g' \
    | grep -vxE 'closeout: skipped —( X)? ?' | sed '/^$/d' | env LC_ALL=C sort -u   # "$S $SYNC_SKIP": the SYNC_SKIP templates carry it
}
cl_unknown() { # <automate-trail.sh> → the templates the classifier reads as unknown
  local t
  while IFS= read -r t; do
    grep -q "	unknown	" < <(printf '%s\n' "$t" | cls --run r --item i --pr p) && printf '%s\n' "$t"
  done <<CLT
$(co_templates "$1")
CLT
  return 0
}
ntpl="$(co_templates "$T" | wc -l | tr -d ' ')"
unk="$(cl_unknown "$T")"
[ "$ntpl" -ge 30 ] && [ -z "$unk" ] && ok "(CL1) all $ntpl closeout string templates in automate-trail.sh match a CLOSEOUT_TABLE row" || no "(CL1) templates=$ntpl unclassified: $(printf '%s' "$unk" | tr '\n' '|')"
MUTCL="$TOP/mutd-cl"; mkdir -p "$MUTCL"
awk '{ print } index($0, "  if [ \"$st\" != \"merged\" ]; then echo \"$S pr not merged")==1 { print "  echo \"$S a brand-new refusal nobody classified\"" }' "$T" > "$MUTCL/automate-trail.sh"
if cmp -s "$T" "$MUTCL/automate-trail.sh"; then no "(CL1) drift mutant not built"
else
  case "$(cl_unknown "$MUTCL/automate-trail.sh")" in *"a brand-new refusal nobody classified"*) ok "(CL1) control: a new unclassified closeout string is caught by the drift guard" ;; *) no "(CL1) control: drift guard missed a new string" ;; esac
fi
# (CL2) literal lines.
cl_one() { printf '%s\n' "$1" | cls --run R1 --item q/01.md --pr "$PRURL"; }
for l in "closeout: synced — main at abc1234" "closeout: skipped — already synced (main at origin/main)" "closeout: skipped — ## Current is q/02.md (https://x/pull/9), not this item/PR" "closeout: skipped — ## Current already done" "closeout: removed — branch feature/x (tip == merged head abc)"; do
  [ "$(cl_one "$l")" = complete ] && ok "(CL2) complete: ${l#closeout: }" || no "(CL2) not complete: $l ⇒ $(cl_one "$l")"
done
want_row() { [ "$(cl_one "$1")" = "leftover	R1	q/01.md	$PRURL	$2	${1#closeout: }" ]; }
want_row "closeout: removed — worktree /w/a; kept /w/b still dirty after salvage" worktree && ok "(CL2) mixed 'removed — worktree A; kept B' ⇒ ONE worktree leftover row (kept wins over the verb)" || no "(CL2) mixed line: $(cl_one "closeout: removed — worktree /w/a; kept /w/b still dirty after salvage")"
# (CL2k) S3 wave-1 review: "kept" inside a NAME never flips a clean line — only the partial-removal form counts.
for l in "closeout: checked — - [x] reqs/kept-sessions.md" "closeout: skipped — already removed (no worktree on feat/kept-x)" \
         "closeout: removed — branch feat/kept-x (tip == merged head abc123def456)" "closeout: removed — worktree /w/kept-a"; do
  [ "$(cl_one "$l")" = complete ] && ok "(CL2k) a name containing 'kept' stays complete: ${l#closeout: }" || no "(CL2k) flipped to leftover: $l ⇒ $(cl_one "$l")"
done
want_row "closeout: skipped — pr not merged (awaiting_merge)" gate && ok "(CL2) 'skipped — pr not merged …' ⇒ leftover (gate)" || no "(CL2) pr not merged"
want_row "closeout: frobnicated — something new" unknown && ok "(CL2) an unknown closeout: line ⇒ leftover (unknown)" || no "(CL2) unknown line: $(cl_one 'closeout: frobnicated — something new')"
want_row "closeout: skipped — uncommitted changes outside the trail paths (README)" sync && ok "(CL2) sync skipped on a dirty primary ⇒ leftover (sync)" || no "(CL2) dirty sync"
want_row "closeout: skipped — no done brief" stamp && ok "(CL2) 'skipped — no done brief' ⇒ leftover (stamp)" || no "(CL2) no done brief"
o="$(printf 'brief-repair: repaired x\ntrail-pr: skipped — gh failed\n' | cls --run R1)"
[ "$o" = "leftover	R1	-	-	none	no closeout: line in the input" ] && ok "(CL2) no closeout: line at all ⇒ one leftover row (nothing proves the close-out ran); brief-repair/trail-pr lines ignored" || no "(CL2) no closeout line: $o"
bash "$H" closeout-classify --bogus </dev/null >/dev/null 2>&1; [ $? -eq 1 ] && ok "(CL2) usage error exits 1" || no "(CL2) usage error rc"

echo "== CL. a real close-out that kept a worktree + a branch (tip != merged head); 'Clean up now' never forces =="
REALGIT="$(command -v git)"
GSHIM="$TOP/gshim"; mkdir -p "$GSHIM"
printf '#!/usr/bin/env bash\necho "git $*" >> "$GITLOG"\nexec "%s" "$@"\n' "$REALGIT" > "$GSHIM/git"; chmod +x "$GSHIM/git"
CUD="$TOP/cud"; mkdir -p "$CUD"; cp "$SPYD"/*.sh "$SPYD"/*.py "$CUD/"; cp -R "$SPYD/automate-helpers.d" "$CUD/"
cat > "$CUD/automate-helpers.sh" <<'SHIM'
#!/usr/bin/env bash
if [ "${1:-}" = trail-pr ]; then echo "trail-pr: skipped — stubbed"; exit 0; fi
exec bash "$(dirname "$0")/automate-helpers.real.sh" "$@"
SHIM
mv "$CUD/worktree-salvage.sh" "$CUD/worktree-salvage.real.sh"
printf '#!/usr/bin/env bash\necho "SALVAGE $1" >> "$GITLOG"\nexec bash "$(dirname "$0")/worktree-salvage.real.sh" "$@"\n' > "$CUD/worktree-salvage.sh"
export GITLOG="$TOP/git.log"
cu_closeout() { (cd "$P" && PATH="$GSHIM:$PATH" bash "$CUD/automate-helpers.sh" closeout "$RF_REL" "$REQ" "$PRURL"); }
closeout_fixture 301
( cd "$FX/wt-pr" && echo more > more.txt && git add more.txt && git commit -qm "other work, same branch name" )
moved_tip="$(git -C "$P" rev-parse feature/x)"
: > "$GITLOG"
out="$(cu_closeout)"
rows="$(printf '%s\n' "$out" | cls --run "$RUN_ID" --item "$REQ" --pr "$PRURL")"
printf '%s\n' "$rows" | sed 's/^/    | /'
[ "$(printf '%s\n' "$rows" | cut -f5 | tr '\n' ' ')" = "worktree branch " ] && ok "(CL3) one leftover row per kept step: worktree + branch" || no "(CL3) rows: $(printf '%s' "$rows" | cut -f5 | tr '\n' ' ')"
[ "$(printf '%s\n' "$rows" | cut -f1-4 | env LC_ALL=C sort -u)" = "leftover	$RUN_ID	$REQ	$PRURL" ] && ok "(CL3) every row carries run_id / item / pr (a 'Clean up now' target)" || no "(CL3) row targets: $(printf '%s' "$rows" | cut -f1-4 | tr '\n' '|')"
# "Clean up now" = re-run closeout, re-classify ONCE.
out2="$(cu_closeout)"
rows2="$(printf '%s\n' "$out2" | cls --run "$RUN_ID" --item "$REQ" --pr "$PRURL")"
[ "$(printf '%s\n' "$rows2" | cut -f5 | tr '\n' ' ')" = "worktree branch " ] && ok "(CL4) 'Clean up now' re-run: both leftovers survive (reported, asked Keep/Stop only)" || no "(CL4) re-run rows: $rows2"
[ -d "$FX/wt-pr" ] && [ "$(git -C "$P" rev-parse feature/x)" = "$moved_tip" ] && ok "(CL4) the worktree and the branch at a foreign tip are still there" || no "(CL4) foreign-tip worktree/branch removed"
grep -F "worktree remove $FX/wt-pr" "$GITLOG" >/dev/null && no "(CL4) a foreign-tip worktree was removed" || ok "(CL4) never 'git worktree remove' on the foreign-tip worktree"
grep -E '^git (.* )?branch -D' "$GITLOG" >/dev/null && no "(CL4) git branch -D ran on a foreign tip" || ok "(CL4) never 'git branch -D' on a foreign tip"
grep -E '^git (.* )?(reset|stash)( |$)|--force|^git (.* )?push( .*)? (-f|\+)' "$GITLOG" >/dev/null && no "(CL4) a reset/stash/force: $(grep -E 'reset|stash|--force' "$GITLOG" | head -3 | tr '\n' '|')" || ok "(CL4) never a reset, a stash or a force (git argv log)"
# Matching tip: the worktree is removed, and only AFTER worktree-salvage.sh ran on it.
closeout_fixture 302
: > "$GITLOG"
cu_closeout >/dev/null
ls_="$(grep -nF "SALVAGE $FX/wt-pr" "$GITLOG" | head -n1 | cut -d: -f1)"
lr_="$(grep -nF "worktree remove $FX/wt-pr" "$GITLOG" | head -n1 | cut -d: -f1)"
[ -n "$ls_" ] && [ -n "$lr_" ] && [ "$ls_" -lt "$lr_" ] && [ ! -d "$FX/wt-pr" ] && ok "(CL4) a merged-head worktree is removed only after worktree-salvage.sh ran on it (log lines $ls_ < $lr_)" || no "(CL4) salvage/remove order: salvage=$ls_ remove=$lr_"

echo "== CL. an already closed-out item: complete, nothing asked, ≤1 'nothing to close out' line after two passes =="
closeout_fixture 303
o0="$(run_closeout)"
[ "$(printf '%s\n' "$o0" | cls --run "$RUN_ID" --item "$REQ" --pr "$PRURL" --record "$P/$RF_REL")" = complete ] && ok "(CL5) the first, real close-out classifies complete" || no "(CL5) first close-out: $(printf '%s\n' "$o0" | cls)"
grep -q 'nothing to close out' "$P/$RF_REL" && no "(CL5) a close-out that changed things recorded 'nothing to close out'" || ok "(CL5) a close-out that changed things records no 'nothing to close out' line"
for cl5_pass in 1 2; do
  o="$(run_closeout)"
  v="$(printf '%s\n' "$o" | cls --run "$RUN_ID" --item "$REQ" --pr "$PRURL" --record "$P/$RF_REL")"
  [ "$v" = complete ] || no "(CL5) pass $cl5_pass: $v"
  [ "$cl5_pass" = 1 ] && { cp "$P/$RF_REL" "$FX/rf.p1"; cp "$P/$REQ" "$FX/req.p1"; }
done
n_nt="$(grep -c "closeout: nothing to close out — $REQ\$" "$P/$RF_REL")"
[ "$n_nt" = 1 ] && ok "(CL5) two idempotent passes ⇒ complete both times, exactly ONE 'closeout: nothing to close out' line" || no "(CL5) nothing-to-close-out lines: $n_nt"
cmp -s "$FX/rf.p1" "$P/$RF_REL" && cmp -s "$FX/req.p1" "$P/$REQ" && ok "(CL5) the second pass mutates nothing (run file + requirement byte-identical)" || no "(CL5) second pass mutated files"

echo "== CO. closeout-others: another run's merged item is closed out before PICK (cross-run close-out) =="
RB="automate-2026-01-02-000000"; RBF=".supervisor/automate/$RB.md"
mk_rb() { printf '# Automate Run: current\n## Status: running\n## Queue\n- [ ] .supervisor/requirements/f/02-b.md\n## Current\n- item: null | status: null | pr: null | branch: null\n- pause_reason: null\n## Progress\n- t0 run created\n' > "$P/$RBF"; }
co_others() { (cd "$P" && bash "${CO_H:-$SPYD/automate-helpers.sh}" closeout-others .supervisor/automate "$@"); }
closeout_fixture 310; mk_rb; spy_reset
out="$(co_others --record "$RBF")"; rc=$?
printf '%s\n' "$out" | sed 's/^/    | /'
[ "$rc" -eq 0 ] && grep -qxF "closeout-others: $RUN_ID $REQ $PRURL" <<<"$out" && ok "(CO1) header names A's run, item and PR; exit 0" || no "(CO1) rc=$rc header missing"
grep -qxF -- "- [x] $REQ" "$P/$RF_REL" && grep -qF -- "- **PR:** $PRURL" "$P/$REQ" && [ ! -d "$FX/wt-pr" ] && ok "(CO1) A closed out: check-off, stamp, PR worktree removed" || no "(CO1) A not closed out"
grep -qE "^trail-pr $P/$RF_REL --reason closeout\$" "$SPYLOG" && ok "(CO1) A's trail via the dispatcher" || no "(CO1) no trail-pr call for A"
grep -qE "^closeout $P/$RF_REL $REQ $PRURL\$" "$SPYLOG" && ! grep -q -- '--session-id' "$SPYLOG" && ok "(CO1) closeout called without --session-id (its own lock)" || no "(CO1) closeout call: $(grep '^closeout' "$SPYLOG" | tr '\n' '|')"
grep -qE '^- .* closeout https://github.com/acme/widgets/pull/7: closeout: checked' "$P/$RF_REL" && ok "(CO1) A's Progress carries its closeout lines" || no "(CO1) A Progress missing closeout lines"
grep -qx complete <<<"$out" && grep -qxF "closeout-others: recorded — cross-run closeout $RUN_ID $REQ: complete" <<<"$out" && ok "(CO1) classify answer 'complete' + 'recorded — cross-run closeout …' line" || no "(CO1) verdict/record lines missing"
grep -qE "^- [^ ]+ cross-run closeout $RUN_ID $REQ: complete\$" "$P/$RBF" && ! grep -q 'https\?://' "$P/$RBF" && ok "(CO1) B's Progress records the cross-run close-out and carries NO PR URL" || no "(CO1) B record: $(grep cross-run "$P/$RBF")"
[ -z "$(git -C "$P" diff --cached --name-only)" ] && grep -q '^trail-unstage: unstaged' <<<"$out" && ok "(CO1) mode off: no A trail path left staged in the primary index" || no "(CO1) staged: $(git -C "$P" diff --cached --name-only | tr '\n' ' ')"
o2="$(co_others --record "$RBF")"
[ -z "$o2" ] && ok "(CO1) a second run is silent (A's item is now done)" || no "(CO1) second run: $o2"
MUTCO="$TOP/mutd-co"; mkdir -p "$MUTCO"; cp "$SPYD"/*.sh "$SPYD"/*.py "$MUTCO/"; cp -R "$SPYD/automate-helpers.d" "$MUTCO/"
grep -vF 'l="$(bash "$HLP" trail-unstage "$f"' "$T" > "$MUTCO/automate-trail.sh"
if cmp -s "$T" "$MUTCO/automate-trail.sh" || ! bash -n "$MUTCO/automate-trail.sh"; then no "(CO1) unstage mutant not built"
else
  closeout_fixture 311; mk_rb
  CO_H="$MUTCO/automate-helpers.sh" co_others --record "$RBF" >/dev/null
  grep -qxF -- "- [x] $REQ" "$P/$RF_REL" && [ -n "$(git -C "$P" diff --cached --name-only)" ] && ok "(CO1) control: without trail-unstage A's trail paths stay staged (the clean-index assertion is load-bearing)" || no "(CO1) unstage control did not discriminate"
fi
for v in OPEN CLOSED unreadable done; do
  closeout_fixture "31$(case $v in OPEN) echo 2;; CLOSED) echo 3;; unreadable) echo 4;; done) echo 5;; esac)"; mk_rb
  case "$v" in
    OPEN|CLOSED) jq --arg s "$v" '.[0].state = $s' "$GH_STUB_DIR/prs.json" > "$GH_STUB_DIR/p.tmp" && mv "$GH_STUB_DIR/p.tmp" "$GH_STUB_DIR/prs.json" ;;
    unreadable) touch "$GH_STUB_DIR/pr-view-fail" ;;
    done) sed "s#^- item: $REQ | status: awaiting_merge#- item: $REQ | status: done#" "$P/$RF_REL" > "$P/rf.t" && mv "$P/rf.t" "$P/$RF_REL" ;;
  esac
  a0="$(cksum < "$P/$RF_REL")"; q0="$(cksum < "$P/$REQ")"; b0="$(cksum < "$P/$RBF")"
  o="$(co_others --record "$RBF")"
  [ -z "$o" ] && [ "$a0" = "$(cksum < "$P/$RF_REL")" ] && [ "$q0" = "$(cksum < "$P/$REQ")" ] && [ "$b0" = "$(cksum < "$P/$RBF")" ] && [ -d "$FX/wt-pr" ] \
    && ok "(CO2) A $v ⇒ A, its requirement and B byte-untouched, no line" || no "(CO2) $v: out='$o'"
done
# No --record file yet (a new run): the record line is printed for the engine to append once the run file exists.
closeout_fixture 316
o="$(co_others --record .supervisor/automate/not-created-yet.md)"
grep -qxF "closeout-others: record — cross-run closeout $RUN_ID $REQ: complete" <<<"$o" && ok "(CO3) no run file yet ⇒ 'record — …' printed, nothing appended" || no "(CO3) $o"

# (CO4)-(CO6) the LEFTOVER summary path (S3 wave-1 review: CO1-CO3 cover complete / untouched / no record file only).
# (CO4) real: a dirty primary makes A's close-out a sync leftover; B's Progress records it, no PR URL.
closeout_fixture 317; mk_rb
echo "local edit" >> "$P/README"
o="$(co_others --record "$RBF")"
git -C "$P" checkout -q -- README
grep -qE "^leftover	$RUN_ID	" <<<"$o" \
  && grep -qE "^closeout-others: recorded — cross-run closeout $RUN_ID $REQ: leftover sync — " <<<"$o" \
  && grep -qE "^- [^ ]+ cross-run closeout $RUN_ID $REQ: leftover sync — " "$P/$RBF" && ! grep -q 'https\?://' "$P/$RBF" \
  && ok "(CO4) a dirty primary ⇒ A's close-out is a sync leftover; B records 'leftover sync — …' with no PR URL" \
  || no "(CO4) out=$(printf '%s' "$o" | tr '\n' '|') B=$(grep 'cross-run' "$P/$RBF")"
# (CO5)/(CO6) a stubbed closeout-classify (everything else is the real helper).
CLD="$TOP/clstub"; mkdir -p "$CLD"; cp -R "$SPYD"/* "$CLD/"
cat > "$CLD/automate-helpers.sh" <<'SHIM'
#!/usr/bin/env bash
if [ "${1:-}" = closeout-classify ]; then
  cat >/dev/null
  case "${CL_STUB:-}" in
    empty) exit 0 ;;
    url) printf 'leftover\t-\t-\t-\tgate\tsee https://github.com/acme/widgets/pull/7 for details\n'; exit 0 ;;
  esac
fi
exec bash "$(dirname "$0")/automate-helpers.real.sh" "$@"
SHIM
closeout_fixture 318; mk_rb
o="$(CL_STUB=empty CO_H="$CLD/automate-helpers.sh" co_others --record "$RBF")"
grep -qxF "closeout-others: recorded — cross-run closeout $RUN_ID $REQ: leftover classify — closeout-classify printed nothing" <<<"$o" \
  && ok "(CO5) classify printed nothing ⇒ fallback 'leftover classify — closeout-classify printed nothing' recorded" \
  || no "(CO5) out=$(printf '%s' "$o" | tr '\n' '|')"
closeout_fixture 319; mk_rb
o="$(CL_STUB=url CO_H="$CLD/automate-helpers.sh" co_others --record "$RBF")"
grep -qxF "closeout-others: recorded — cross-run closeout $RUN_ID $REQ: leftover gate — see <url> for details" <<<"$o" \
  && ! grep -q 'https\?://' "$P/$RBF" \
  && ok "(CO6) a leftover detail carrying a PR URL reaches B's Progress as <url> — the record line never carries the URL" \
  || no "(CO6) out=$(printf '%s' "$o" | tr '\n' '|') B=$(grep 'cross-run' "$P/$RBF")"

echo "== K. SKILL wiring (Part A, automate-followups/32) =="
s6="$(awk '/^## §6 /{s=1;next} s&&/^## /{exit} s' "$SKILL")"
gate="$(grep -m1 -F '**Close-out leftover gate' <<<"$s6")"
for t in 'closeout-classify --run <run_id> --item <item> --pr <pr_url> --record <runfile>`' '**Clean up now**' '**Keep and continue**' '**Stop**' 'ONE owner question batching ≤4 leftovers' 'never proceeds silently' '`current-set <runfile> --pause-reason closeout_leftover`' '`worktree-salvage.sh` runs before any `git worktree remove`' 're-classifies ONCE' 'closeout leftover kept: <run_id> <step> <detail>' '`run-lock.sh release`'; do
  grep -qF -- "$t" <<<"$gate" && ok "§6 step 1 leftover gate names $t" || no "§6 step 1 leftover gate missing $t"
done
s4="$(awk '/^## §4 /{s=1;next} s&&/^## /{exit} s' "$SKILL")"
grep -qF -- '`meta-entry` (branch mode) → **`closeout-others`** → `resume-glob --finalize` (step 1) → list / ask (step 4)' <<<"$s4" && ok "§4 start order: meta-entry → closeout-others → resume-glob --finalize → list/ask" || no "§4 start order missing"
grep -qF -- '`closeout_leftover`, `limit_reached` write the park state' "$SKILL" && ok "trail no-park list names closeout_leftover" || no "no-park list missing closeout_leftover"
grep -qF -- '**Other runs'"'"' merged items (`closeout-others`' "$SKILL" && ok "§8 names the cross-run close-out" || no "§8 cross-run bullet missing"
grep -qF 'nothing surfaces a live watcher at SessionStart' "$SKILL" && no "SKILL still says nothing surfaces a live watcher" || ok "SKILL's SessionStart honest limit updated"
for s in closeout-classify closeout-others; do
  grep -q "^| \`$s\` |" "$SKILL" && ok "§1.5 row: $s" || no "§1.5 row missing: $s"
  grep -q "^  $s " <<<"$(bash "$H" --help)" && ok "--help lists $s" || no "--help missing $s"
done
grep -qE '^    closeout-others\) exec bash "\$\(dirname "\$0"\)/automate-trail.sh" "\$cmd" "\$@" ;;' "$H" && ok "dispatcher row: closeout-others → automate-trail.sh" || no "closeout-others dispatcher row missing"
grep -qF 'closeout-classify' "$HERE/../commands/automate.md" && grep -qF 'closeout-others' "$HERE/../commands/automate.md" && ok "commands/automate.md overview names closeout-classify + closeout-others" || no "commands/automate.md surface missing"

echo "== LN. parallel-automate/05: a lane clone never closes out / finalizes another run (Scope 3 amendment, D2) =="
# Two-lane fleet against the same old unfinished run A (merged PR): each lane skips with ONE line and
# touches nothing; the coordinator (no lane.json — the primary) then closes A out exactly once.
closeout_fixture 340; mk_rb; spy_reset
a0="$(cksum < "$P/$RF_REL")"; q0="$(cksum < "$P/$REQ")"; ln_lane_out=""
for ln_l in L1 L2; do
  printf '{"schema_version":1,"lane":"%s","run_id":"par-9-%s","parent_run_id":"par-9"}\n' "$ln_l" "$ln_l" > "$P/.supervisor/lane.json"
  ln_o="$(co_others --record "$RBF")"; ln_lane_out="$ln_lane_out$ln_o"$'\n'
  [ "$ln_o" = "closeout-others: skipped — lane clone" ] && ok "(LN1) lane $ln_l: closeout-others prints ONE 'skipped — lane clone' line" || no "(LN1) lane $ln_l: '$ln_o'"
done
{ [ "$a0" = "$(cksum < "$P/$RF_REL")" ] && [ "$q0" = "$(cksum < "$P/$REQ")" ] && [ -d "$FX/wt-pr" ] && [ -z "$(grep -v '^closeout-others ' "$SPYLOG" 2>/dev/null)" ]; } \
  && ok "(LN1) neither lane touched A, its requirement or its PR worktree, and made no dispatcher call beyond closeout-others itself" || no "(LN1) a lane mutated A / called out: $(tr '\n' '|' < "$SPYLOG" 2>/dev/null)"
[ "$(grep -c '^closeout-others: '"$RUN_ID " <<<"$ln_lane_out")" = 0 ] && ok "(LN1) zero closeout lines in either lane" || no "(LN1) lane closeout lines: $ln_lane_out"
rm -f "$P/.supervisor/lane.json"
ln_o="$(co_others --record "$RBF")"
[ "$(grep -c "^closeout-others: $RUN_ID $REQ $PRURL\$" <<<"$ln_o")" = 1 ] && grep -qxF -- "- [x] $REQ" "$P/$RF_REL" \
  && ok "(LN1) the coordinator (primary, no lane.json) closes A out exactly once" || no "(LN1) coordinator closeout: $ln_o"
# Mutation control: TWO independent layers keep a lane out of the cross-run closeout — the
# `_in_lane_clone` guard in closeout_others and resume-glob's lane scoping (a lane clone lists only
# its own run). Dropping the guard alone leaves the lane silent (defense in depth, LN2a); dropping
# both lets the lane close A out, so the LN1 assertion is load-bearing (LN2b).
closeout_fixture 341; mk_rb; spy_reset
MUTLN="$TOP/mutln"; mkdir -p "$MUTLN"; cp -R "$SPYD"/* "$MUTLN/"
sed '/^  if _in_lane_clone "\$root"; then echo "\$S lane clone"; return 0; fi$/d' "$SPYD/automate-trail.sh" > "$MUTLN/automate-trail.sh"
printf '{"schema_version":1,"lane":"L1","run_id":"par-9-L1","parent_run_id":"par-9"}\n' > "$P/.supervisor/lane.json"
if ! cmp -s "$SPYD/automate-trail.sh" "$MUTLN/automate-trail.sh" && bash -n "$MUTLN/automate-trail.sh"; then
  ln_o="$(CO_H="$MUTLN/automate-helpers.sh" co_others --record "$RBF")"
  [ -z "$ln_o" ] && ok "(LN2a) guard dropped alone: resume-glob's lane scoping still keeps A out of the lane (empty output)" || no "(LN2a) guard-only mutant: '$ln_o'"
  sed '/^    if \[ -f "\$dir\/\.\.\/lane\.json" \]; then \[ -n "\$own" \]/d' "$SPYD/automate-helpers.d/resume.sh" > "$MUTLN/automate-helpers.d/resume.sh"
  if ! cmp -s "$SPYD/automate-helpers.d/resume.sh" "$MUTLN/automate-helpers.d/resume.sh" && bash -n "$MUTLN/automate-helpers.d/resume.sh"; then
    ln_o="$(CO_H="$MUTLN/automate-helpers.sh" co_others --record "$RBF")"
    grep -qxF "closeout-others: $RUN_ID $REQ $PRURL" <<<"$ln_o" && ok "(LN2b) mutation control: both layers dropped ⇒ the lane closes out A — the lane assertion is load-bearing" || no "(LN2b) mutation control inconclusive: '$ln_o'"
  else
    no "(LN2b) mutation control: could not build the resume.sh mutant"
  fi
else
  no "(LN2) mutation control: could not build the mutant"
fi
rm -f "$P/.supervisor/lane.json"
# finalize-empty in a lane clone: another run's eligible file is refused untouched; the lane's own run is not refused.
closeout_fixture 342
fe_rf other-run paused awaiting_go x done; fe_rf par-9-L1 paused awaiting_go x done
printf '{"schema_version":1,"lane":"L1","run_id":"par-9-L1","parent_run_id":"par-9"}\n' > "$P/.supervisor/lane.json"
ln_c="$(cksum < "$P/$AUTD/other-run.md")"
ln_o="$(cd "$P" && bash "$H" finalize-empty "$AUTD/other-run.md")"
[ "$ln_o" = "finalize-empty: skipped — lane clone (not this lane's run)" ] && [ "$ln_c" = "$(cksum < "$P/$AUTD/other-run.md")" ] \
  && ok "(LN3) finalize-empty in a lane: another run's eligible file ⇒ 'skipped — lane clone (not this lane's run)', byte-untouched" || no "(LN3) other run: '$ln_o'"
ln_o="$(cd "$P" && bash "$H" finalize-empty "$AUTD/par-9-L1.md" 2>/dev/null | head -n1)"
case "$ln_o" in *"lane clone"*) no "(LN3) the lane's own run was refused: '$ln_o'" ;; *) ok "(LN3) finalize-empty in a lane: its own run is not refused by the lane guard ('$ln_o')" ;; esac
rm -f "$P/.supervisor/lane.json" "$P/$AUTD/other-run.md" "$P/$AUTD/par-9-L1.md"

echo "== DS. automate-followups/37: a requirement's done stamp is written only by the post-merge closeout =="
# The fixture mirrors the end state of a sequential `/autonomous` + owned drain whose PR is still
# OPEN: the requirement at `## Status: pending`, its done brief in jobs/done/ pointing at it (with
# the `## Outcome` Phase 4.5 writes), the PR stubbed OPEN. Phase 4.5's completion tail is prose, so
# it is simulated by APPLYING whatever requirement stamp block the self-heal skill's step 2.5
# instructs (extracted, never hand-typed): on the base commit that block is a sentinel-led
# `## Status: done` and DS1 fails; since this item the step instructs none and the file is untouched.
DS_SKILL="$HERE/../skills/self-heal-advisory/SKILL.md"
# ds_tail_stamp <skill> — the first requirement stamp block the completion tail's step 2.5 tells the
# agent to write: the lines from an un-backticked sentinel line to the closing code fence, de-indented.
ds_tail_stamp() {
  awk '/^2\.5\. /{s=1} /^2\.6\. /{s=0} s' "$1" | awk '
    !d && /<!-- loomwright:requirement-closeout -->/ && !/`/ { b = 1 }
    b && /^[[:space:]]*```/ { b = 0; d = 1; next }
    b { sub(/^[[:space:]]+/, ""); print }'
}
# (control) the extractor is not vacuous: a step 2.5 shaped like the base commit's yields its block.
printf '%s\n' '2.5. **Requirement close-out:**' '      ```markdown' '      <!-- loomwright:requirement-closeout -->' \
  '      ## Status: done' '      - **PR:** {PR URL}' '      ```' '2.6. **Next**' > "$TOP/ds-base-shape.md"
[ "$(ds_tail_stamp "$TOP/ds-base-shape.md" | sed -n 2p)" = "## Status: done" ] \
  && ok "(DS0) control: the step-2.5 stamp extractor finds a base-shaped sentinel block" || no "(DS0) extractor is vacuous: $(ds_tail_stamp "$TOP/ds-base-shape.md" | tr '\n' '|')"
closeout_fixture 370
printf '# req a\n\n## Status: pending\n' > "$P/$REQ"
printf '\n## Outcome\n- **Status:** completed\n- **PR:** %s\n- **Heal decision:** PASS\n' "$PRURL" >> "$P/.supervisor/jobs/done/brief-a.md"
rm -f "$P/.supervisor/jobs/in-progress/brief-live.md"   # step 2 moved the run's brief; none is left in progress
ds_stamp="$(ds_tail_stamp "$DS_SKILL")"
[ -z "$ds_stamp" ] || printf '\n%s\n' "$ds_stamp" >> "$P/$REQ"   # the simulated completion tail
jq '.[0].state = "OPEN"' "$GH_STUB_DIR/prs.json" > "$GH_STUB_DIR/p.tmp" && mv "$GH_STUB_DIR/p.tmp" "$GH_STUB_DIR/prs.json"
printf '# req a\n\n## Status: pending\n' > "$TOP/ds-req-pending"
out="$(run_closeout)"
[ "$out" = "closeout: skipped — pr not merged (awaiting_merge)" ] && ok "(DS1) PR OPEN ⇒ closeout prints one 'pr not merged' line" || no "(DS1) OPEN closeout: $out"
cmp -s "$P/$REQ" "$TOP/ds-req-pending" && ! grep -qE '^## Status:[[:space:]]*done' "$P/$REQ" \
  && ok "(DS1) PR OPEN after Phase 4.5 + closeout ⇒ the requirement is byte-identical (## Status: pending) and carries no ## Status: done" \
  || no "(DS1) PR OPEN: requirement changed or claims done: $(tr '\n' '|' < "$P/$REQ")"
jq '.[0].state = "MERGED"' "$GH_STUB_DIR/prs.json" > "$GH_STUB_DIR/p.tmp" && mv "$GH_STUB_DIR/p.tmp" "$GH_STUB_DIR/prs.json"
out="$(run_closeout)"
case "$out" in *"closeout: stamped — $REQ (## Status: done, brief .supervisor/jobs/done/brief-a.md)"*) ok "(DS2) PR MERGED ⇒ closeout stamps the requirement" ;; *) no "(DS2) MERGED closeout: $(printf '%s' "$out" | tr '\n' '|')" ;; esac
[ "$(grep -cF '<!-- loomwright:requirement-closeout -->' "$P/$REQ")" = 1 ] && [ "$(grep -cE '^## Status:[[:space:]]*done' "$P/$REQ")" = 1 ] \
  && ok "(DS2) exactly one sentinel-led done block" || no "(DS2) sentinel/done count: $(tr '\n' '|' < "$P/$REQ")"
grep -qE '^- \*\*Completed:\*\* [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$P/$REQ" && ok "(DS2) Completed is a UTC ISO-8601 timestamp" || no "(DS2) Completed line malformed"
{ cat "$TOP/ds-req-pending"
  printf '\n<!-- loomwright:requirement-closeout -->\n## Status: done\n- **Completed:** <TS>\n- **Brief:** .supervisor/jobs/done/brief-a.md\n- **PR:** %s\n' "$PRURL"; } > "$TOP/ds-req-want"
sed -E 's/^(- \*\*Completed:\*\* ).*/\1<TS>/' "$P/$REQ" > "$TOP/ds-req-got"
cmp -s "$TOP/ds-req-got" "$TOP/ds-req-want" && ok "(DS2) the requirement is the pending bytes + the closeout printf block, byte for byte (Completed normalised)" \
  || no "(DS2) stamped bytes differ: $(diff "$TOP/ds-req-want" "$TOP/ds-req-got" | tr '\n' '|')"
grep -qF "printf '\n<!-- loomwright:requirement-closeout -->\n## Status: done\n- **Completed:** %s\n- **Brief:** %s\n- **PR:** %s\n'" "$T" \
  && ok "(DS2) closeout's step-5 printf is unchanged in automate-trail.sh" || no "(DS2) closeout printf changed"
# Contract: the completion tail instructs no requirement `## Status:` stamp (fails on the base commit).
[ -z "$(grep -A1 -F '<!-- loomwright:requirement-closeout -->' "$DS_SKILL" | grep '## Status')" ] \
  && ok "(DS3) contract: self-heal-advisory carries no sentinel-led requirement ## Status block" || no "(DS3) self-heal-advisory still carries a requirement stamp block"
ds25="$(awk '/^2\.5\. /{s=1} /^2\.6\. /{s=0} s' "$DS_SKILL")"
if grep -q '^2\.5\. \*\*Requirement close-out' <<<"$ds25" && ! grep -qE '^[[:space:]]*## Status:' <<<"$ds25" \
   && grep -qF 'writes NOTHING to the requirement' <<<"$ds25" && grep -qF '`automate-helpers.sh closeout`' <<<"$ds25"; then
  ok "(DS3) contract: step 2.5 (Requirement close-out) defers to closeout and stamps no ## Status: line"
else
  no "(DS3) step 2.5 still stamps, or no longer names the deferral to closeout"
fi

if [ "$pass" != "$_tally_ok" ] || [ "$fail" != "$_tally_no" ]; then
  echo "  FAIL: summary counter clobbered — pass=$pass vs $_tally_ok ok lines, fail=$fail vs $_tally_no FAIL lines (a leg reused pass/fail as a variable)"
  fail=$((_tally_no+1)); pass=$_tally_ok
fi
echo
echo "test-automate-trail: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
