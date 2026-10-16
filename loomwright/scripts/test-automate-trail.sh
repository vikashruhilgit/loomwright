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
#      Since automate-followups/20 the item-10 SUPERVISOR_RESULT FAILS (its
#      `ground_truth` lacks `checked` — the #311 shape); SN legs add one negative
#      per nested object / list item (missing required key, non-schema key, wrong
#      shape), valid nested sidecars of both kinds as positives, and a mutation
#      control: with the NESTED loop disabled every SN negative reads `ok`.
#      The skip form ({checked: false, status: skipped|unverified}, counts
#      omitted) passes; three skip-rule mutants (off / ignores checked / also
#      excuses checked) each turn the leg they target red.
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
#      holder_env in the lock meta: the closeout process itself, dead once it
#      exits — run under a live non-shell ancestor whose CLAUDE_PID names it,
#      so neither the ancestor nor the launching session is ever recorded),
#      CLOSED ⇒ `gone` line + no cleanup, lifetime cap,
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
#      PR ⇒ no check polling; validation_unrun (af36-remainder/01) ⇒ no polling and
#      never `now mergeable`, even with a green run on the head (E2b);
#      check_pending → green ⇒ one `now mergeable` line +
#      one `automate_escalation_recheck` notify (latched, also across a
#      restart), non-green ⇒ one `still failing … rerun: gh run rerun <id>
#      --failed`; check_red_unrelated reports only at a NEWER attempt; the
#      check-runs API path when no run id (E6b: a spaced matrix name, V5); a same-PR double arm keeps ONE
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
#   NT. closeout --no-trail (automate-followups/38) — the same steps, run file
#      and requirement bytes as plain closeout, no trail-pr (spy), classified
#      `complete`; OPEN ⇒ nothing; the --auto-merge SYNC close-out (pending
#      requirement ⇒ one done block, one `- [x]`, no trail PR, trail-gate
#      clear); the strict sentinel guard (quoted ⇒ stamps; real block ⇒
#      skipped); SKILL / --help / command wiring.
#   SW. sweep (af/39a) — branches: MERGED at the tip ⇒ would-remove / removed;
#      moved tip, newest OPEN, CLOSED unmerged, no PR, gh failure, unparseable ⇒
#      `sweep: kept branch`; current / base / held-in-a-kept-worktree never cost a
#      gh call, and a removable worktree + its branch cost ONE gh read in total
#      (SW8, the per-run memo). Worktrees (judged first): clean merged sibling (a path with a
#      space) and a worktree-audit `created` path ⇒ removed after its 3 gitignored
#      entries land byte-identical under <salvage>/ignored/; dirty, detached,
#      live-process cwd (stubbed lsof; real lsof when it can see a child), lsof
#      absent/failing, forced copy failure ⇒ kept; app (`kept app`, clean+merged,
#      still present after --apply), lane (`use lane-remove`), other (`origin
#      unknown`). Dry run: `git worktree list --porcelain` + `git branch -v`
#      checksum unchanged, no salvage written. Exit 0 and ONE last summary line
#      everywhere. closeout 3a: the same --ignored gate (2 entries salvaged; a copy
#      failure keeps it in the `skipped — kept worktree …` form closeout-classify
#      reads). F1 carries the finalize-empty run-end line (one, after the trail
#      line). Review fixes: a gitignored `.env` (no salvage list covers it) ⇒
#      `kept worktree <p> — unsalvaged ignored content: .env` in the dry run AND
#      under --apply (the secret intact), while only allowlisted `node_modules/` ⇒
#      removed; a non-ASCII worktree path (`proj-café`) whose live cwd lsof prints
#      escaped (stubbed C-locale n-line; real lsof under `env -u LANG -u LC_ALL -u
#      LC_CTYPE` when it can see a child) ⇒ kept, liveness unverifiable, the dir
#      remains. Pin mutations, each observed RED: tip comparison deleted, the app
#      worktree-root exclusion deleted, the sweep verdict ignored, the closeout 3a
#      verdict ignored, the coverage check ignored, the escaped-byte check deleted.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/wait-lib.sh"   # bounded condition waits (iq02 T07)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
H="$HERE/automate-helpers.sh"
T="$HERE/automate-trail.sh"

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
# TB — automate-trail.sh as ONE file: the entry point's own _trail_bundle expansion (each
# automate-trail.d/ module inlined at its source line, automate-speed/19). Every TEXT read of the
# script below — a sed/awk/grep mutant source, its cmp -s gate, a static scan, a parse check —
# reads TB, so it still finds the moved code and a mutant written from it is self-contained; every
# RUN still runs the real entry point $T. Named automate-trail.sh so a basename in a leg label is
# unchanged. Fails the whole suite if the bundle cannot be built.
mkdir -p "$TOP/bundle"; TB="$TOP/bundle/automate-trail.sh"
eval "$(awk '/^_trail_bundle\(\) \{$/,/^}$/' "$T")"
_trail_bundle "$T" > "$TB" && [ -s "$TB" ] || { echo "  FAIL: could not build the automate-trail.sh bundle"; exit 1; }
# The automate-loop skill and /automate's command body are split indexes (parallel-automate/22): the SKILL
# text legs read the skill's documented-order assembly (index segments + split files), and the absence
# scans read the command body's assembly too, so text moved into a split file stays covered.
ASM="$HERE/fixtures/automate-loop-split/assemble.sh"
SKILL="$TOP/automate-loop-skill.md"; bash "$ASM" "$HERE/../skills/automate-loop/SKILL.md" "$SKILL" || no "cannot assemble skills/automate-loop/SKILL.md (index + split files)"
CMD_ALL="$TOP/automate-command-all.md"; bash "$ASM" "$HERE/../commands/automate.md" "$CMD_ALL" || no "cannot assemble commands/automate.md (index + split files)"

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

# ---- legs: test-automate-trail.d/<part>.sh (automate-speed/19) ---------------
# The legs below moved verbatim, in base order, into test-automate-trail.d/. Each part is sourced
# BY NAME (never a glob) at top level, so it shares this file's setup, stubs, helpers and counters;
# a missing or unreadable part aborts the suite (exit 1, the part named) instead of silently
# dropping its legs. Part A: 01. Part B: 02–06.
TAT_D="$HERE/test-automate-trail.d"
tat_part() { [ -f "$TAT_D/$1.sh" ] && [ -r "$TAT_D/$1.sh" ] || { echo "  FAIL: missing test part: test-automate-trail.d/$1.sh"; exit 1; }; }
tat_part 01-sidecar-trail-pr;          . "$TAT_D/01-sidecar-trail-pr.sh"
tat_part 02-closeout;                  . "$TAT_D/02-closeout.sh"
tat_part 03-stamps-gate;               . "$TAT_D/03-stamps-gate.sh"
tat_part 04-watcher-branch-mode;       . "$TAT_D/04-watcher-branch-mode.sh"
tat_part 05-finalize-closeout-others;  . "$TAT_D/05-finalize-closeout-others.sh"
tat_part 06-sweep;                     . "$TAT_D/06-sweep.sh"

if [ "$pass" != "$_tally_ok" ] || [ "$fail" != "$_tally_no" ]; then
  echo "  FAIL: summary counter clobbered — pass=$pass vs $_tally_ok ok lines, fail=$fail vs $_tally_no FAIL lines (a leg reused pass/fail as a variable)"
  fail=$((_tally_no+1)); pass=$_tally_ok
fi
echo
echo "test-automate-trail: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
