#!/usr/bin/env bash
# test-automate-helpers.sh — self-tests for automate-helpers.sh (the `/automate`
# engine's pure-logic helpers). Runs in isolated temp dirs (never touches the real
# .supervisor/). Puts a STUBBED `gh` (and `git`) on PATH so reconcile + the
# auto-merge gate are exercised without any real GitHub call — NOTHING is ever
# merged. Exit 0 = all pass, 1 = any failure. Mirrors test-dispatch-pr-review.sh /
# test-measure-heal-signal.sh conventions. UNCOUNTED by the doc-currency gate.
#
# Covers (per the brief's Outcomes Rubric "Scriptable self-tests pass"):
#   A. config suppress/restore: normal restore, absent-file restore DELETES config,
#      malformed pre-existing config ABORTS (exit 2), crash-stranded backup restored;
#      AND (A7) config-orig is CALL-ORDER-INDEPENDENT — after config-suppress has
#      rewritten the live config to auto_review:false it reads the backup, so the
#      recorded auto_review_original keeps true/false/absent distinguishable;
#      plus both arms of the backup-given-but-missing FALLBACK (load-bearing
#      pre-suppress; a pinned known limit post-suppress).
#   B. run-file: atomic write produces a parseable file; append-only ## Progress
#      never loses prior lines; queue check-off flips the box (+ skipped form);
#      `remaining` counts ONLY "- [ ]" lines; (B9) runfile-write / progress-append /
#      queue-checkoff fail CLOSED — empty stdin, no title, no Status/Queue, a dropped
#      Progress prefix, the failed-awk pipe shape and a titleless target all leave the
#      run file byte-unchanged, with positive controls and a validation-removed mutant.
#      (B10, automate-followups/32 Part C) `## Current` moves only through a helper:
#      current-set's byte-diff (only the item/pause_reason lines move), every refusal
#      (exit 1, byte-unchanged), idempotency, pr/branch retention vs reset, the
#      run-level form; progress-append's current_not_set guard (exit 3, line kept;
#      `parked ` not guarded; the picked-mismatch arm with `./` and suffix forms) and
#      a w1-10 replay; current-rebuild against a stubbed gh (OPEN/MERGED/CLOSED/failing)
#      and its pause_reason null (B10i2, automate-followups/36 A3, mutant-controlled)
#      with foreign-PR, not-in-Queue and no-picked negatives; three gated mutants.
#      (ESC, automate-followups/31) escalation-cause: the s2-c/s2-d replays
#      (check_red_unrelated / check_pending), the related-file and tested-script
#      cases, every unreadable case failing closed to check_red, `other`, a gated
#      name-only-classifier mutant, a no-rerun/merge/push static scan; and
#      current-escalation's placement, idempotency, null removal and refusals.
#      Review iteration 1: every command of a failed step counts (two-command step,
#      mixed failed steps, no Run block ⇒ check_red; valid mutant), red before pending,
#      and current-set dropping the line on leaving `escalated` / a changed item.
#      V5: spaced (matrix) check names — `test (18.x)` pending and `build (ubuntu-latest)`
#      red keep the whole name + run id through the shared wait-for-checks-line.sh reader
#      and current-escalation; the shared word-split reader mutant; missing reader ⇒ check_red.
#   C. folder / backlog-doc resolvers (skip ## Status: done; documented order).
#   D. resume-glob lists only run files (is_run_file: `# Automate Run:` title) not
#      done — §6 result sidecars excluded, with a validated is_run_file mutant;
#      (D0b, automate-followups/19) the TOLERATED title forms — BOM, extra/no/inner
#      whitespace, lower case, 3-space indent — are listed one fixture each, while H2,
#      4-space- and tab-indented lines stay unlisted; the write validators accept a
#      tolerated title; two gated mutants (exact-match restored, indent cap lifted);
#      resume reconcile: belief pending but gh says merged ⇒ merged; belief checked
#      but gh says open ⇒ awaiting_merge; gh unreadable ⇒ awaiting_merge (fail closed);
#      gh CLOSED-unmerged ⇒ gone.
#   E. auto-merge gate fail-CLOSED on EACH of conditions 1-6 individually (incl.
#      both arms of cond. 2 base/SHA, both blocking reviewDecision arms CHANGES_REQUESTED
#      and REVIEW_REQUIRED of cond. 3, both arms of cond. 5 checks/rubric, and cond. 6
#      high_risk on `true` / `null` / missing / a non-boolean string / the JSON STRING
#      `"false"` (type-erasure guard: MERGE only on the JSON boolean; the same string-`"false"`
#      guard on cond. 3 `unresolved_human_thread`) — plus
#      `trust_unprotected: true` NOT overriding cond. 6), plus malformed-ctx
#      (ctx_unreadable) and a merge-command failure (merge_command_failed); AND the
#      all-pass MERGE case (`high_risk: false` + every other condition) fires
#      `gh pr merge --squash --match-head-commit <checked head>` exactly once; AND a head
#      that moves between the checks and the merge parks merge_command_failed with
#      nothing merged (the stub models GitHub's SHA-pin refusal); AND a mutation control (cond 6 deleted from a
#      COPY of gate_eval, gated on non-empty + differs + `bash -n`) turns the cond-6 PARK
#      cases red while the MERGE case stays green.
#   R. gate-eval condition 7 — the rules gate (section letter "R": "F" is already
#      learning-emit). A stub sibling rules-gate-verdict.sh (default verdict `none`, so
#      every Section E case is unchanged) drives: fail ⇒ PARK: rules_check_failed (<≤3
#      countable ids>), ok ⇒ MERGE, unresolved ⇒ rules_check_unresolved, unstamped with
#      countable ⇒ rules_unstamped (message text picked by the optional
#      unstamped_reason: drift with 0 live countable / legacy stamp get their own text, an
#      unknown reason still parks), none (advisory-only, even failing) ⇒ MERGE,
#      cmd_disabled ⇒ rules_cmd_disabled, every unreadable shape (non-JSON, empty,
#      non-object, missing/null/non-string/unknown verdict, non-zero exit, helper absent)
#      ⇒ rules_gate_unreadable; the refused ctx keys rules_gate/rules_ok/rules_check with
#      a call-log proof the helper never ran; cond-6-before-cond-7 precedence; two gated
#      mutants (PARK test deleted ⇒ MERGE; invocation commented out ⇒ fail-closed
#      rules_gate_unreadable) + a positive control; and an end-to-end leg against the
#      REAL rules-gate-verdict.sh / rules-check.sh / rules-replay-lib.sh siblings.
#      R11 (automate-followups/16): cond 7's checkout pin, on the harness's REAL git
#      checkout ($E_ROOT, whose HEAD the gh stub reports) — stale HEAD / non-checkout /
#      no-commit / missing root ⇒ rules_gate_head_mismatch; tracked edit, deletion,
#      staged file, untracked file (also under status.showUntrackedFiles=no), dirt in
#      the harness dir outside agent-memory, a nested x/.supervisor/, dirt seen from a
#      subdirectory --root, and a failing `git status` ⇒ rules_gate_dirty_tree — each
#      with 0 merges and the helper never called; .supervisor/-only, agent-memory-only
#      and ignored-only dirt still let the verdict decide; cond 6 still precedes the
#      pin; gated mutants (each pin deleted ⇒ its leg MERGEs) with an un-mutated control.
#      R11f (review iteration 1): local-only git state cannot hide dirt — assume-unchanged
#      and skip-worktree flags, .git/info/exclude, core.excludesFile, a self-ignoring
#      untracked .gitignore, env-injected config (GIT_CONFIG_COUNT) and a --root inside
#      .git/ (show-toplevel fails) all park rules_gate_dirty_tree; an untracked .gitignore
#      inside a committed-ignored directory does not; each new read has a gated mutant.
#      R11j-m (owner fix-now): a global excludesFile reached through [include] /
#      [includeIf] is honoured; one spelled through a directory alias of the checkout, or a
#      symlink into it, is not; submodules under a committed ignore=all (dirty, stale
#      commit, own info/exclude, own assume-unchanged) park while a clean pinned one
#      merges with both index files untouched; gated mutants for each.
#   F. learning-emit (engine-native ground-truth POSTMORTEM_RESULT line): happy path
#      (fix_cycles>0 → one drain_churn entry, review_rounds==fix_cycles), the zero-rule
#      (fix_cycles==0 non-escalated → categories:[] + review_rounds:0), zero-cycle
#      ESCALATED (→ review_rounds:1 + one drain_escalation entry), idempotency skip,
#      missing-field degrade, jq-absent no-write, fetch-fail integer-0 degrade,
#      injection-safe jq args, self_heal_misses derivation, read-postmortem visibility,
#      and the degraded-then-corrective emit (a degraded first emit must NOT block a
#      later complete one) with a legacy-key mutation control + skip-arm no-regression,
#      the REALISTIC degraded shape (--number passed, so both lines share repo#number)
#      + the floor-raising downstream join, degraded-after-degraded in isolation, and
#      empty-string-only changed_paths classified DEGRADED; PLUS --self-heal-rounds
#      (F14–F19): self_heal_rounds + one self_heal_churn entry asserted through the REAL
#      read-postmortem.sh output, a no-flag byte-identity pin against the base-commit
#      helper, fail-safe normalization + the restated zero-rule, self-heal-before-drain
#      ordering, key-unchanged idempotency, and a validated mutation control; PLUS (F20)
#      a flag-first call (ledger path omitted: --repo / --run-id / --help / empty first
#      arg) writes nothing in the cwd and prints ONE stderr usage line, with a mutation control.
#   G. brief-repair (fail-SAFE evidence-positive engine seam, v15.65.0): MERGED ⇒
#      the sibling reconcile-jobs.sh --repair --evidence moves the brief (AC-1/2/3/8),
#      OPEN/CLOSED ⇒ skipped with the reconciler NOT invoked (AC-6), TEN separate
#      fail-safe groups each proving run file / ## Status / gate-eval decision /
#      merge.log / brief unchanged (AC-5) — incl. the reconciler-REFUSED branch
#      (a colliding done/ file) and the missing-argument guard with gh never
#      asked — the two SKILL §6 seam pins with per-line
#      mutants (AC-9a), and the invocation-removed helper mutant beside real siblings
#      behind a positive gate (AC-9b).
#   H6. reconcile-status promotes a `## Status: brief-shipped` requirement on the
#      same merged-PR evidence as any other not-done file (owner decision
#      2026-10-13, #447): a plan row in the dry run, the §6 shape APPENDED under
#      the kept heading under --apply, an idempotent re-run; with no evidence (PR
#      open, self-citing diff, all-.supervisor/ diff, trail PR, no candidate) or a
#      parked heading, only the info row and a byte-unchanged file; mutation
#      control — the old unconditional early return restored ⇒ never promoted.
#   H7. reconcile-status never takes the engine's own trail PR as evidence: a
#      proposed/ draft and a Queue requirement cited ONLY by a merged
#      chore/<run_id>-trail-<n> PR body get no plan line (run
#      automate-2026-10-01-142337: proposed/ drafts read "would stamp done
#      (PR #321)", a trail PR); a trail candidate ahead of the real PR is
#      skipped, not fatal (the plan names the real PR); a near-miss branch
#      (`chore/x-trail-final`) is still evidence; mutation control — the
#      exclusion line neutered in a copy of the helper ⇒ the draft plans again.
#   H8. reconcile-status judges a body citation by the PR's DIFF: a PR that adds
#      the cited requirement (PR #359 queued meta-sync-followups/04 and read
#      "would stamp done") gets no plan line, while the same PR without it in
#      its diff does; an all-.supervisor/ diff is never evidence, on the
#      body-citation AND the branch-slug path (H8e); an unreadable
#      or truncated diff is no evidence, and a >100-file diff is re-read through
#      the paginated REST endpoint; mutation controls neuter each of the two
#      new checks in a copy of the helper and watch the leg go red.
#   H9. reconcile-status takes a body citation only on an IMPLEMENTS-shaped
#      line (2026-10-11: PR #470/#482/#457 bodies MENTIONED five requirements
#      and the dry run planned them done; PR #484's short-form citation was
#      missed because GitHub search does not find the full path): a passing
#      mention plans nothing; `Implements <full path>`, `Implements <short
#      slug>`, `Closes <id> (<path>)` and bold `Requirement:` plan; second-
#      clause, longer-slug, nested-dir and verb-prefix near misses do not; a
#      `proposed`/`parked` heading and a top-level task plan are never
#      candidates; mutation controls restore the any-mention rule, the
#      full-path search, the status gate and the task-plan skip, each red.
#   I. ceiling-check (red-team-hardening/06, PICK-time token ceiling; section letter
#      "I" — "H" is already used in-body by the reconcile-status H1-H9 tests above):
#      under-max
#      prints OK; over-max prints PARK: token_ceiling + non-zero total/max; a
#      LEDGER_UNREADABLE=1 reader answer PARKs as ledger_unreadable (fail CLOSED);
#      a missing run file dies (bad usage); a non-integer max_tokens dies; PLUS the
#      AC-mandated mutation control — a read-token-ledger.sh mutant whose numf()
#      always returns 0 makes the known-over-ceiling seam fixture wrongly print OK,
#      proving the breach-parks check is load-bearing, not vacuous.
#   W. plan-waves (parallel-automate/04, read-only wave planner; fixtures in mktemp -d with --root
#      = the fixture root): disjoint items share a wave; literal-prefix intersection; companion
#      expansion (file rules, "new" rules, directory entries); dependency ordering incl. an in-set
#      ../other dep; run-file merged-done / skipped / ABANDONED / two-heading done; a BOM +
#      lower-case titled run file still parsed as a run file (W6c); parked, pending
#      and transitive blocks; missing/unknown/malformed Touches runs alone; undeclared queue = one
#      per wave; explicit + implicit cycles, unknown ids and missing plan-set items exit 1 with empty
#      stdout; --max; malformed
#      or jq-less companions fail closed; fenced sections ignored; the harness-port shape; the
#      five-item fixture byte-for-byte; usage errors; read-only (spy git/gh); every real
#      parallel-automate Touches parses (SKIP when the gitignored queue is absent); the shipped
#      companions.json new rules cover check-doc-currency.sh FILES; two mutation controls.
#   X. plan-waves --explain / --lint (parallel-automate/10, same W harness): every --explain reason
#      shape on a fixture that produces it, the wave/blocked lines unchanged under --explain, errors
#      still exit 1 with empty stdout; --lint flags every malformed Touches / Depends on shape with
#      its line and reason, a declared `unknown` is `ok (declared unknown)` (exit 0), a missing
#      Depends on alone exits 1, dir / run-file / item-list / single-item inputs, no --max needed;
#      lint `ok` ⇔ the planner reads the section as known on every shape (one grammar); read-only;
#      a mutation control (a grammar copy that accepts a parenthetical turns X3 red); --explain
#      state never leaks into a later default call in the same shell (X2b); the three hand-copied
#      Touches grammars (helper / automate-dismissed.sh / propose-from-verify.sh) agree token-for-token (X7).
#   QG. automate-speed/01 (unanswered questions never hold a curated or parked run): queue-confirm
#      (QG1) — backlog n ≤ limit skips with the exact line (n == limit included), n > limit asks,
#      folder/prompt/unknown sources ask, --lane-backlog prints intake.md's lane reason byte for
#      byte, a signed / non-integer / leading-zero / >9-digit count asks with nothing on stderr,
#      a 9-digit count (the largest accepted) is judged normally,
#      a missing or extra argument exits 1; park-ask-gate (QG2, stubbed gh) — fix-now allowed only
#      on a written awaiting_merge park + this PR's merge-watch marker + an exact OPEN read,
#      MERGED / CLOSED / other / unreadable / `{}` ⇒ unavailable, a closed-out (done) item ⇒
#      unavailable, a `running` item, a missing or foreign marker, a foreign item or PR, a
#      missing / unreadable / item-less run file ⇒ refuse, usage errors exit 1, READ-ONLY, the
#      delayed-marker leg (marker ~2s after a --wait 5 call ⇒ ask) and a --wait 1 refusal; the
#      park-first order leg (QG3) over automate-next-step.sh's park / decide steps and the intake.md leg (QG4).
#      Every leg has a gated mutant (anchor unique, non-empty, differs, `bash -n`; prose mutants:
#      non-empty, differs, no line lost) that turns it red.
# >>> runner-only
#
# Layout (automate-speed/21): this file is the runner (header, shared setup, summary). The legs moved
# verbatim, in base order, into test-automate-helpers.d/NN-<name>.sh, sourced BY NAME at top level; a
# missing part aborts (exit 1). Section E's all-pass MERGE leg stays inline here, after 05-gate-eval.
# `bash test-automate-helpers.sh [<part>...]` (names without .sh) runs only those parts plus their
# prerequisites (05-gate-eval / 06-gate-eval-tail / 07-rules-gate need 05-gate-eval-harness), in order.
# <<< runner-only

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# $H is ONE file: the dispatcher's own _ah_bundle expansion of automate-helpers.sh with its
# automate-helpers.d/ family files inlined (parallel-automate/11), written beside a symlink to
# every other scripts/ entry — so each mutation `sed … "$H"` finds its text and every
# `$(dirname "$0")` sibling lookup resolves. Fails the whole suite if the bundle cannot be built.
ah_build_bundle() {
  local d e
  d="$(mktemp -d)" || return 1
  eval "$(awk '/^_ah_bundle\(\) \{$/,/^}$/' "$HERE/automate-helpers.sh")"
  for e in "$HERE"/*; do
    [ "$e" = "$HERE/automate-helpers.sh" ] || ln -s "$e" "$d/$(basename "$e")" || return 1
  done
  _ah_bundle "$HERE/automate-helpers.sh" > "$d/automate-helpers.sh" && [ -s "$d/automate-helpers.sh" ] || return 1
  echo "$d/automate-helpers.sh"
}
H="$(ah_build_bundle)" || { echo "FAIL: could not build the automate-helpers.sh bundle"; exit 1; }

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

PR="https://github.com/acme/widgets/pull/42"

# ---- stub harness: a fake `gh` (+ `git`) on PATH, behavior driven by files in
# $STUBDIR so each test sets up the GitHub "reality" it wants. -----------------
make_stub_bin() {
  local bin="$1"
  mkdir -p "$bin"
  cat > "$bin/gh" <<'STUB'
#!/usr/bin/env bash
# Stub gh: reads canned responses from $GH_STUB_DIR.
#   pr view <url> --json ...<reviewDecision>...   -> cat pr-view-rd.json (or exit 1 if pr-view-rd-fail marker)
#   pr view <url> --json ... (any OTHER field set) -> cat pr-view.json (or exit 1 if pr-view-fail marker)
#   pr merge --squash [--match-head-commit SHA] <url>
#                                                  -> append a line to merge.log, exit per marker;
#                                                     a merge-time-head file models a push that landed
#                                                     AFTER the gate's reads: like GitHub, a given
#                                                     --match-head-commit that differs from it is
#                                                     refused (MERGE_REFUSED, exit 1), and a merge
#                                                     WITHOUT the flag goes through regardless
#   api graphql -f query=...                       -> cat graphql.json (or exit 1 if graphql-fail marker)
#   api repos/.../branches/main/protection          -> cat protection.json; protection-404 marker exits 1
#                                                      with "Not Found (HTTP 404)"; protection-fail
#                                                      marker exits 1 with an unrelated (non-404) error
set -u
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "view" ]; then
  shift 2
  json_arg=""
  while [ $# -gt 0 ]; do
    if [ "$1" = "--json" ]; then json_arg="${2:-}"; fi
    shift
  done
  case "$json_arg" in
    *reviewDecision*)
      if [ -f "$GH_STUB_DIR/pr-view-rd-fail" ]; then exit 1; fi
      cat "$GH_STUB_DIR/pr-view-rd.json"
      exit 0
      ;;
    *)
      if [ -f "$GH_STUB_DIR/pr-view-fail" ]; then exit 1; fi
      cat "$GH_STUB_DIR/pr-view.json"
      exit 0
      ;;
  esac
fi
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "merge" ]; then
  if [ -f "$GH_STUB_DIR/merge-time-head" ]; then
    mhc=""; prev=""
    for a in "$@"; do [ "$prev" = "--match-head-commit" ] && mhc="$a"; prev="$a"; done
    if [ -n "$mhc" ] && [ "$mhc" != "$(cat "$GH_STUB_DIR/merge-time-head")" ]; then
      echo "MERGE_REFUSED $*" >> "$GH_STUB_DIR/merge.log"; exit 1
    fi
  fi
  echo "MERGE_CALLED $*" >> "$GH_STUB_DIR/merge.log"
  if [ -f "$GH_STUB_DIR/merge-fail" ]; then exit 1; fi
  exit 0
fi
if [ "${1:-}" = "api" ] && [ "${2:-}" = "graphql" ]; then
  if [ -f "$GH_STUB_DIR/graphql-fail" ]; then exit 1; fi
  cat "$GH_STUB_DIR/graphql.json"
  exit 0
fi
if [ "${1:-}" = "api" ]; then
  if [ -f "$GH_STUB_DIR/protection-404" ]; then echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi
  if [ -f "$GH_STUB_DIR/protection-fail" ]; then echo "gh: Internal Server Error (HTTP 500)" >&2; exit 1; fi
  cat "$GH_STUB_DIR/protection.json"
  exit 0
fi
exit 0
STUB
  chmod +x "$bin/gh"
}

run_h() { RUN_OUT="$( "$@" 2>/dev/null )"; RUN_RC=$?; }

# The automate-loop skill and the AUTOMATE_RUN doc are split indexes (parallel-automate/22): the prose
# seams below read their documented-order assembly (index segments + split files), never the index alone.
SPLIT_D="$(mktemp -d)"; SKILL_FILE="$SPLIT_D/automate-loop-skill.md"; RUN_DOC="$SPLIT_D/automate-run-all.md"
bash "$HERE/fixtures/automate-loop-split/assemble.sh" "$HERE/../skills/automate-loop/SKILL.md" "$SKILL_FILE" || no "cannot assemble skills/automate-loop/SKILL.md (index + split files)"
bash "$HERE/fixtures/automate-loop-split/assemble.sh" "$HERE/../docs/result-schemas/automate-run.md" "$RUN_DOC" || no "cannot assemble result-schemas/automate-run.md (index + split files)"
# >>> runner-only

# ---- legs: test-automate-helpers.d/<part>.sh (automate-speed/21) -------------------------------
# TAH_PARTS is the ONE part list (base order), tah_prereq the ONE prerequisite map; no argument = every
# part, as before. "$@" is cleared before any part is sourced, so legs see the empty "$@" of base.
TAH_D="$HERE/test-automate-helpers.d"
TAH_PARTS="01-config 02-runfile 03-intake 04-resume 05-gate-eval-harness 05-gate-eval 06-gate-eval-tail 07-rules-gate 08-learning-emit 09-brief-repair 10-reconcile-status 11-ceiling 12-meta 13-plan-waves 14-escalation 15-lane-seams 16-queue-gates"
tah_prereq() { case "$1" in 05-gate-eval|06-gate-eval-tail|07-rules-gate) echo 05-gate-eval-harness ;; esac; }
# A part that does not parse would make `.` fail, skip every leg in it and leave the suite green, which
# the one-file base could not do. So a part must also pass `bash -n` before anything is sourced.
tah_part() {
  [ -f "$TAH_D/$1.sh" ] && [ -r "$TAH_D/$1.sh" ] || { echo "  FAIL: missing test part: test-automate-helpers.d/$1.sh"; exit 1; }
  bash -n "$TAH_D/$1.sh" 2>/dev/null || { echo "  FAIL: test part does not parse (bash -n): test-automate-helpers.d/$1.sh"; exit 1; }
}
TAH_ONLY=""; TAH_SEL=" $TAH_PARTS "
if [ "$#" -gt 0 ]; then
  TAH_ONLY=1; TAH_SEL=" "
  for tah_a in "$@"; do
    tah_k=""; for tah_p in $TAH_PARTS; do [ "$tah_p" = "$tah_a" ] && tah_k=1; done
    [ -n "$tah_k" ] || { echo "  FAIL: unknown test part: $tah_a (known: $TAH_PARTS)"; exit 1; }
    for tah_p in $(tah_prereq "$tah_a") "$tah_a"; do
      case "$TAH_SEL" in *" $tah_p "*) ;; *) TAH_SEL="$TAH_SEL$tah_p " ;; esac
    done
  done
fi
set --
tah_sel() { case "$TAH_SEL" in *" $1 "*) return 0 ;; esac; return 1; }
tah_run() { tah_sel "$1" || return 1; tah_part "$1"; }
tah_list=""; for tah_p in $TAH_PARTS; do tah_sel "$tah_p" && { tah_part "$tah_p"; tah_list="$tah_list $tah_p"; }; done
if [ -n "$TAH_ONLY" ]; then echo "== test-automate-helpers: parts$tah_list (in this order, prerequisites included) =="; fi
# <<< runner-only
tah_run 01-config && . "$TAH_D/01-config.sh"
tah_run 02-runfile && . "$TAH_D/02-runfile.sh"
tah_run 03-intake && . "$TAH_D/03-intake.sh"
tah_run 04-resume && . "$TAH_D/04-resume.sh"
tah_run 05-gate-eval-harness && . "$TAH_D/05-gate-eval-harness.sh"
tah_run 05-gate-eval && . "$TAH_D/05-gate-eval.sh"
# >>> runner-only
if tah_sel 05-gate-eval; then
# <<< runner-only
# --- All-pass MERGE fires `gh pr merge --squash` EXACTLY once, and the stub
# call log shows classify-risk.sh, gh pr view, gh api branches/.../protection,
# and the GraphQL threads query were each ACTUALLY invoked (AC1). ---
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ] \
   && grep -q -- '--squash' "$GH_STUB_DIR/merge.log" \
   && grep -qF -- "--match-head-commit $E_PR_HEAD" "$GH_STUB_DIR/merge.log" \
   && grep -qF "$PR" "$GH_STUB_DIR/merge.log"; then
  ok "gate all-pass: MERGE fires 'gh pr merge --squash --match-head-commit <checked head> <url>' exactly once"
else
  no "gate all-pass wrong (out='$RUN_OUT' merges=$(merges) log='$(cat "$GH_STUB_DIR/merge.log" 2>/dev/null)')"
fi

# >>> runner-only
fi
# <<< runner-only
tah_run 06-gate-eval-tail && . "$TAH_D/06-gate-eval-tail.sh"
tah_run 07-rules-gate && . "$TAH_D/07-rules-gate.sh"
tah_run 08-learning-emit && . "$TAH_D/08-learning-emit.sh"
tah_run 09-brief-repair && . "$TAH_D/09-brief-repair.sh"
tah_run 10-reconcile-status && . "$TAH_D/10-reconcile-status.sh"
tah_run 11-ceiling && . "$TAH_D/11-ceiling.sh"
tah_run 12-meta && . "$TAH_D/12-meta.sh"
tah_run 13-plan-waves && . "$TAH_D/13-plan-waves.sh"
tah_run 14-escalation && . "$TAH_D/14-escalation.sh"
tah_run 15-lane-seams && . "$TAH_D/15-lane-seams.sh"
tah_run 16-queue-gates && . "$TAH_D/16-queue-gates.sh"
# >>> runner-only
if [ -n "$TAH_ONLY" ]; then rm -rf "$SPLIT_D"; fi
# <<< runner-only
echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
