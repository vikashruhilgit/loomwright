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
#      with foreign-PR, not-in-Queue and no-picked negatives; three gated mutants.
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
#      `gh pr merge --squash` exactly once; AND a mutation control (cond 6 deleted from a
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
#      ordering, key-unchanged idempotency, and a validated mutation control.
#   G. brief-repair (fail-SAFE evidence-positive engine seam, v15.65.0): MERGED ⇒
#      the sibling reconcile-jobs.sh --repair --evidence moves the brief (AC-1/2/3/8),
#      OPEN/CLOSED ⇒ skipped with the reconciler NOT invoked (AC-6), TEN separate
#      fail-safe groups each proving run file / ## Status / gate-eval decision /
#      merge.log / brief unchanged (AC-5) — incl. the reconciler-REFUSED branch
#      (a colliding done/ file) and the missing-argument guard with gh never
#      asked — the two SKILL §6 seam pins with per-line
#      mutants (AC-9a), and the invocation-removed helper mutant beside real siblings
#      behind a positive gate (AC-9b).
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
#   I. ceiling-check (red-team-hardening/06, PICK-time token ceiling; section letter
#      "I" — "H" is already used in-body by the reconcile-status H1-H6 tests above):
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

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
H="$HERE/automate-helpers.sh"

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
#   pr merge --squash <url>                        -> append a line to merge.log, exit per marker
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

# =============================================================================
echo "== A. config suppress / restore =="

# A1. normal restore: backup byte-for-byte, suppress sets auto_review=false, restore brings the ORIGINAL back.
WD="$(mktemp -d)"; CFG="$WD/config.json"; BAK="$WD/run.config-backup.json"
printf '{"auto_review": true, "notify": "x"}\n' > "$CFG"
ORIG_BYTES="$(cat "$CFG")"
bash "$H" config-suppress "$CFG" "$BAK"
if [ "$(jq -r '.auto_review' "$CFG")" = "false" ] && [ "$(jq -r '.notify' "$CFG")" = "x" ] && [ -f "$BAK" ]; then
  ok "suppress: auto_review->false, other keys preserved, backup written"
else
  no "suppress wrong (cfg='$(cat "$CFG")' bak-exists=$([ -f "$BAK" ] && echo y || echo n))"
fi
bash "$H" config-restore "$CFG" "$BAK"
if [ "$(cat "$CFG")" = "$ORIG_BYTES" ] && [ ! -f "$BAK" ]; then
  ok "restore: original config restored byte-for-byte, backup deleted"
else
  no "restore wrong (cfg='$(cat "$CFG")' bak-exists=$([ -f "$BAK" ] && echo y || echo n))"
fi
rm -rf "$WD"

# A2. absent-file restore DELETES config (never leaves a partial config.json).
WD="$(mktemp -d)"; CFG="$WD/config.json"; BAK="$WD/run.config-backup.json"
# no pre-existing config
bash "$H" config-suppress "$CFG" "$BAK"
if [ -f "$CFG" ] && [ "$(jq -r '.auto_review' "$CFG")" = "false" ]; then
  ok "absent: suppress writes a minimal auto_review:false config"
else
  no "absent-suppress wrong (cfg-exists=$([ -f "$CFG" ] && echo y || echo n))"
fi
bash "$H" config-restore "$CFG" "$BAK"
if [ ! -f "$CFG" ] && [ ! -f "$BAK" ]; then
  ok "absent: restore DELETES config (no partial config shadowing notify-config.json)"
else
  no "absent-restore should delete config (cfg-exists=$([ -f "$CFG" ] && echo y || echo n))"
fi
rm -rf "$WD"

# A3. malformed pre-existing config ABORTS (exit 2) — never clobber a hand-edited config.
WD="$(mktemp -d)"; CFG="$WD/config.json"; BAK="$WD/run.config-backup.json"
printf '{ this is not json \n' > "$CFG"
MAL_BYTES="$(cat "$CFG")"
run_h bash "$H" config-suppress "$CFG" "$BAK"
if [ "$RUN_RC" -eq 2 ] && [ "$(cat "$CFG")" = "$MAL_BYTES" ] && [ ! -f "$BAK" ]; then
  ok "malformed: suppress aborts (exit 2), config untouched, no backup written"
else
  no "malformed-abort wrong (rc=$RUN_RC cfg-unchanged=$([ "$(cat "$CFG")" = "$MAL_BYTES" ] && echo y || echo n))"
fi
rm -rf "$WD"

# A4. crash-stranded backup restored at reconcile time (the backup persisted across a crash).
WD="$(mktemp -d)"; CFG="$WD/config.json"; BAK="$WD/run.config-backup.json"
printf '{"auto_review": true}\n' > "$CFG"
ORIG_BYTES="$(cat "$CFG")"
bash "$H" config-suppress "$CFG" "$BAK"     # simulate: tick set suppress, then "crashed" (no restore)
# config now shows auto_review:false, backup stranded on disk. RECONCILE restores it:
bash "$H" config-restore "$CFG" "$BAK"
if [ "$(cat "$CFG")" = "$ORIG_BYTES" ] && [ ! -f "$BAK" ]; then
  ok "crash-stranded backup restored on reconcile (original back, backup cleaned)"
else
  no "crash-restore wrong (cfg='$(cat "$CFG")')"
fi
rm -rf "$WD"

# A5. config-orig reports the recorded original .auto_review across present-true,
#     present-false, and absent-config (the value stamped into ## Run Config).
WD="$(mktemp -d)"; CFG="$WD/config.json"
printf '{"auto_review": true, "notify": "x"}\n' > "$CFG"
run_h bash "$H" config-orig "$CFG"
if [ "$RUN_OUT" = "true" ] && [ "$RUN_RC" -eq 0 ]; then
  ok "config-orig: present auto_review:true ⇒ 'true'"
else
  no "config-orig present-true wrong (out='$RUN_OUT' rc=$RUN_RC)"
fi
printf '{"auto_review": false, "notify": "x"}\n' > "$CFG"
run_h bash "$H" config-orig "$CFG"
if [ "$RUN_OUT" = "false" ] && [ "$RUN_RC" -eq 0 ]; then
  ok "config-orig: present auto_review:false ⇒ 'false'"
else
  no "config-orig present-false wrong (out='$RUN_OUT' rc=$RUN_RC)"
fi
rm -f "$CFG"   # absent config
run_h bash "$H" config-orig "$CFG"
if [ "$RUN_OUT" = "absent" ] && [ "$RUN_RC" -eq 0 ]; then
  ok "config-orig: absent config ⇒ 'absent'"
else
  no "config-orig absent wrong (out='$RUN_OUT' rc=$RUN_RC)"
fi
# A6. config-orig on a MALFORMED config ABORTS (exit 2) — never silently report a value.
printf '{ not json \n' > "$CFG"
run_h bash "$H" config-orig "$CFG"
if [ "$RUN_RC" -eq 2 ]; then
  ok "config-orig: malformed config ⇒ abort (exit 2)"
else
  no "config-orig malformed should abort (rc=$RUN_RC out='$RUN_OUT')"
fi
rm -rf "$WD"

# A7. CALL-ORDER HAZARD (§7) — the defect this assertion exists to catch.
#     §7's sequence is backup -> suppress -> record `auto_review_original`, so a
#     caller following the prose queries AFTER config-suppress has run, and by then
#     the LIVE config says auto_review:false for EVERY original. Only the byte-for-byte
#     backup still holds the truth. Observed 2026-09-04 on a real /automate run: a
#     config with NO auto_review key was recorded as `false` when the true original
#     was `absent`. Contract: `config-orig <cfg> [<bak>]` reports the TRUE original
#     regardless of call order, and keeps true/false/absent DISTINGUISHABLE (the same
#     distinction config_orig's own body is careful to preserve against jq's `//`).
echo "== A7. config-orig is call-order-independent (post-suppress, via the backup) =="

# A7a. THE OBSERVED DEFECT: no `auto_review` key at all -> must stay 'absent' after suppress.
WD="$(mktemp -d)"; CFG="$WD/config.json"; BAK="$WD/run.config-backup.json"
printf '{"notify": "x"}\n' > "$CFG"
run_h bash "$H" config-orig "$CFG"          # pre-suppress, 1-arg form: already correct
PRE_OUT="$RUN_OUT"
bash "$H" config-suppress "$CFG" "$BAK"
run_h bash "$H" config-orig "$CFG" "$BAK"   # post-suppress, contract form
if [ "$PRE_OUT" = "absent" ] && [ "$RUN_OUT" = "absent" ] && [ "$RUN_RC" -eq 0 ]; then
  ok "config-orig: no auto_review key ⇒ 'absent' BOTH before and after suppress"
else
  no "config-orig call-order: no-key original should be 'absent' (pre='$PRE_OUT' post='$RUN_OUT' rc=$RUN_RC)"
fi
# Live config really is suppressed — proves the assertion above is not vacuous.
if [ "$(jq -r '.auto_review' "$CFG")" = "false" ]; then
  ok "config-orig: (control) live config IS auto_review:false at query time"
else
  no "control failed: live config not suppressed (cfg='$(cat "$CFG")')"
fi
rm -rf "$WD"

# A7b. a GENUINE `false` original must NOT collapse to 'absent' via the backup path
#      either (the falsy-coercion hazard config_orig guards against on the live path).
WD="$(mktemp -d)"; CFG="$WD/config.json"; BAK="$WD/run.config-backup.json"
printf '{"auto_review": false, "notify": "x"}\n' > "$CFG"
bash "$H" config-suppress "$CFG" "$BAK"
run_h bash "$H" config-orig "$CFG" "$BAK"
if [ "$RUN_OUT" = "false" ] && [ "$RUN_RC" -eq 0 ]; then
  ok "config-orig: genuine false original ⇒ 'false' after suppress (not 'absent')"
else
  no "config-orig call-order: false original wrong (out='$RUN_OUT' rc=$RUN_RC)"
fi
rm -rf "$WD"

# A7c. a `true` original must survive suppress (the case the live path silently loses).
WD="$(mktemp -d)"; CFG="$WD/config.json"; BAK="$WD/run.config-backup.json"
printf '{"auto_review": true, "notify": "x"}\n' > "$CFG"
bash "$H" config-suppress "$CFG" "$BAK"
run_h bash "$H" config-orig "$CFG" "$BAK"
if [ "$RUN_OUT" = "true" ] && [ "$RUN_RC" -eq 0 ]; then
  ok "config-orig: true original ⇒ 'true' after suppress"
else
  no "config-orig call-order: true original wrong (out='$RUN_OUT' rc=$RUN_RC)"
fi
rm -rf "$WD"

# A7d. originally-ABSENT config: suppress writes the __ABSENT__ marker backup; the
#      recorded original must be 'absent', not the 'false' the synthesized config shows.
WD="$(mktemp -d)"; CFG="$WD/config.json"; BAK="$WD/run.config-backup.json"
bash "$H" config-suppress "$CFG" "$BAK"     # no pre-existing config
run_h bash "$H" config-orig "$CFG" "$BAK"
if [ "$RUN_OUT" = "absent" ] && [ "$RUN_RC" -eq 0 ]; then
  ok "config-orig: __ABSENT__ marker backup ⇒ 'absent' after suppress"
else
  no "config-orig call-order: absent-original wrong (out='$RUN_OUT' rc=$RUN_RC)"
fi
rm -rf "$WD"

# A7e. a MALFORMED backup ABORTS (exit 2) — same never-silently-report-a-value rule
#      as A6, so a corrupted sidecar can't fabricate an auto_review_original.
WD="$(mktemp -d)"; CFG="$WD/config.json"; BAK="$WD/run.config-backup.json"
printf '{"auto_review": true}\n' > "$CFG"
bash "$H" config-suppress "$CFG" "$BAK"
printf '{ not json \n' > "$BAK"
run_h bash "$H" config-orig "$CFG" "$BAK"
if [ "$RUN_RC" -eq 2 ]; then
  ok "config-orig: malformed backup ⇒ abort (exit 2)"
else
  no "config-orig malformed backup should abort (rc=$RUN_RC out='$RUN_OUT')"
fi
rm -rf "$WD"

# A7f. BRANCH COVERAGE for "backup path GIVEN but NOT FOUND" — the fallback branch.
#      Missing is NOT treated like malformed (which aborts, A7e) because the two are
#      not the same kind of event: a malformed backup can never be legitimate, whereas
#      a MISSING one is the normal state of a correct PRE-suppress 2-arg call. Aborting
#      on missing would re-introduce call-order dependence in the opposite direction —
#      exactly what this fix exists to remove. So the fallback is INTENTIONAL, and both
#      of its arms are pinned here so that changing it is a visible test change.

# A7f-i. LOAD-BEARING arm: 2-arg call BEFORE suppress (backup not created yet) must
#        fall back to the live config, which at that moment IS the original.
WD="$(mktemp -d)"; CFG="$WD/config.json"; BAK="$WD/run.config-backup.json"
printf '{"auto_review": true, "notify": "x"}\n' > "$CFG"
run_h bash "$H" config-orig "$CFG" "$BAK"   # $BAK deliberately does not exist yet
if [ "$RUN_OUT" = "true" ] && [ "$RUN_RC" -eq 0 ] && [ ! -f "$BAK" ]; then
  ok "config-orig: 2-arg call pre-suppress (no backup yet) falls back to live ⇒ 'true'"
else
  no "config-orig pre-suppress 2-arg fallback wrong (out='$RUN_OUT' rc=$RUN_RC)"
fi
rm -rf "$WD"

# A7f-ii. CHARACTERIZATION arm (pins a KNOWN LIMIT, not a desired outcome): if the
#         backup goes missing AFTER suppress — stale/reused run_id, partial cleanup, a
#         race with a concurrent restore — the fallback reads the SUPPRESSED live config
#         and reports 'false' for an original that was 'absent'. The helper cannot tell
#         this apart from A7f-i: both are "2 args, no backup on disk", and only the
#         CALLER knows whether suppress has run. Documented in SKILL.md §7 and in the
#         function's own comment. If this is ever changed to abort, THIS assertion is
#         the one that must be edited — deliberately and visibly.
WD="$(mktemp -d)"; CFG="$WD/config.json"; BAK="$WD/run.config-backup.json"
printf '{"notify": "x"}\n' > "$CFG"        # no auto_review key ⇒ true original is 'absent'
bash "$H" config-suppress "$CFG" "$BAK"
rm -f "$BAK"                                # backup lost after suppress
run_h bash "$H" config-orig "$CFG" "$BAK"
if [ "$RUN_OUT" = "false" ] && [ "$RUN_RC" -eq 0 ]; then
  ok "config-orig: (known limit, pinned) backup lost post-suppress ⇒ falls back to live 'false'"
else
  no "config-orig lost-backup fallback changed behavior (out='$RUN_OUT' rc=$RUN_RC) — intentional? update SKILL.md §7 + this arm"
fi
rm -rf "$WD"

# =============================================================================
echo "== B. run-file atomic write + append-only Progress + check-off + remaining =="

WD="$(mktemp -d)"; RF="$WD/automate/run-1.md"
bash "$H" runfile-write "$RF" <<'EOF'
# Automate Run: demo
## Status: running
## Source
- demo
## Run Config
- mode: safe | limit: 5
## Queue
- [ ] a.md
- [ ] b.md
- [x] c.md
## Current
- item: a.md | status: running
## Progress
- t0 picked a.md
EOF
# B1. atomic write produced a parseable file with all sections.
if [ -f "$RF" ] && grep -q '^## Queue' "$RF" && grep -q '^## Progress' "$RF"; then
  ok "atomic write: run file present + parseable (Queue/Progress sections)"
else
  no "atomic write produced a bad file"
fi

# B2. remaining counts ONLY "- [ ]" lines (2 unchecked; c.md checked is excluded).
run_h bash "$H" remaining "$RF"
if [ "$RUN_OUT" = "2" ]; then ok "remaining: counts only unchecked (2)"; else no "remaining wrong ($RUN_OUT, want 2)"; fi

# B3. append-only Progress never loses prior lines. The 2nd line carries a literal
#     backslash sequence (\t/\n) to ALSO guard the ENVIRON[...]-not-awk-v fix in
#     progress_append — backslashes must be stored VERBATIM, never interpreted.
bash "$H" progress-append "$RF" "t1 ran /autonomous"
bash "$H" progress-append "$RF" 't2 drain READY path\twith\nbackslashes'
if grep -q '^- t0 picked a.md' "$RF" \
   && grep -q '^- t1 ran /autonomous' "$RF" \
   && grep -qF -- '- t2 drain READY path\twith\nbackslashes' "$RF" \
   && [ "$(grep -c '^- t0 picked a.md' "$RF")" -eq 1 ]; then
  ok "append-only Progress: prior line intact, new lines appended in order (backslashes verbatim)"
else
  no "progress-append lost/duplicated lines or mangled backslashes:\n$(grep -n '^- t' "$RF")"
fi
# the new lines must be UNDER ## Progress, not elsewhere
if awk '/^## Progress/{p=1} p&&/^- t2 drain READY/{found=1} END{exit !found}' "$RF"; then
  ok "appended line lives under ## Progress"
else
  no "appended line not under ## Progress"
fi

# B4. check-off flips - [ ] -> - [x]; remaining drops.
bash "$H" queue-checkoff "$RF" "a.md"
run_h bash "$H" remaining "$RF"
if grep -q '^- \[x\] a.md$' "$RF" && [ "$RUN_OUT" = "1" ]; then
  ok "check-off: a.md flipped to [x], remaining now 1"
else
  no "check-off wrong (remaining=$RUN_OUT, line=$(grep 'a.md' "$RF"))"
fi

# B5. skipped form: check-off with a reason; remaining drops; never re-counted.
#     Reason carries a literal backslash sequence (why\tbecause) to ALSO guard the
#     ENVIRON[...]-not-awk-v fix in queue_checkoff: \t must be stored verbatim,
#     never interpreted as a tab.
bash "$H" queue-checkoff "$RF" "b.md" 'blocked upstream why\tbecause'
run_h bash "$H" remaining "$RF"
if grep -qF -- '- [x] b.md  # skipped: blocked upstream why\tbecause' "$RF" && [ "$RUN_OUT" = "0" ]; then
  ok "skipped form: b.md checked off with reason (backslash verbatim), remaining now 0 (skipped excluded)"
else
  no "skipped-form wrong (remaining=$RUN_OUT, line=$(grep 'b.md' "$RF"))"
fi

# B6. idempotency: check-off an ALREADY-[x] item leaves it untouched (no dup line).
before_c="$(grep -c '^- \[x\] c.md$' "$RF")"
bash "$H" queue-checkoff "$RF" "c.md"
after_c="$(grep -c '^- \[x\] c.md$' "$RF")"
if [ "$before_c" = "1" ] && [ "$after_c" = "1" ]; then
  ok "check-off idempotent: already-[x] c.md untouched (no duplicate)"
else
  no "idempotency wrong (before=$before_c after=$after_c)"
fi

# B7. abandoned mark: check-off with mark=abandoned writes the "# abandoned:" form (§5).
RF2="$WD/automate/run-2.md"
bash "$H" runfile-write "$RF2" <<'EOF'
# Automate Run: demo2
## Status: running
## Queue
- [ ] x.md
## Progress
- t0
EOF
bash "$H" queue-checkoff "$RF2" "x.md" "no longer needed" "abandoned"
if grep -qF -- '- [x] x.md  # abandoned: no longer needed' "$RF2"; then
  ok "abandoned mark: x.md checked off with '# abandoned:' form (§5)"
else
  no "abandoned-mark wrong (line=$(grep 'x.md' "$RF2"))"
fi

# B8. progress-append CREATES a "## Progress" section when the file lacks one (no drop).
RF3="$WD/automate/run-3.md"
bash "$H" runfile-write "$RF3" <<'EOF'
# Automate Run: demo3
## Status: running
## Queue
- [ ] y.md
EOF
bash "$H" progress-append "$RF3" "t0 created section"
if grep -q '^## Progress' "$RF3" && grep -qF -- '- t0 created section' "$RF3"; then
  ok "progress-append: creates ## Progress section when absent (no event dropped)"
else
  no "progress-create-section wrong:\n$(cat "$RF3")"
fi
rm -rf "$WD"

# =============================================================================
echo "== B9. fail-CLOSED run-file writes (SKILL §3 \"Validate before rename\") =="
# 2026-10-01 incident (loomwright-studio automate-2026-09-30-211858): BSD awk
# rejected a newline inside an `awk -v cur=…` value, exited non-zero and printed
# nothing; `runfile-write` accepted the empty stdin and renamed a 0-byte file over
# the ONLY copy of resume state, then three `progress-append`s fabricated a
# titleless `## Progress` stub on it (remaining → 0, resume-glob stops listing it).
# Every case asserts the run file is BYTE-UNCHANGED and no temp file is left.
# b9_scenarios <helper> <tag> — runs each corrupting input against <helper> and
# prints one "<case>=kept|CORRUPTED" token per case (used for the real helper AND
# for the mutation control below, which must print CORRUPTED).
B9_RF_BODY='# Automate Run: b9
## Status: running
## Source
- demo
## Run Config
- mode: safe | limit: 5
## Queue
- [ ] a.md
- [ ] b.md
## Current
- item: a.md | status: running
- pending_decisions: 0 | fix_now_reentered: false
## Progress
- t0 picked a.md
- t1 ran /autonomous'
b9_seed() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$B9_RF_BODY" > "$1"; cp "$1" "$1.orig-copy"; mv "$1.orig-copy" "$2"; }
b9_verdict() {  # <rf> <orig> <dir> → kept|CORRUPTED (also CORRUPTED when a temp is left)
  local extra; extra="$(ls -A "$3" | grep -vxF "$(basename "$1")" || true)"
  if cmp -s "$1" "$2" && [ -z "$extra" ]; then echo kept; else echo CORRUPTED; fi
}
b9_scenarios() {
  local helper="$1" d rf orig out=""
  d="$(mktemp -d)"; rf="$d/automate/run.md"; orig="$d/orig.md"
  # (1) empty stdin
  b9_seed "$rf" "$orig"; : | bash "$helper" runfile-write "$rf" >/dev/null 2>&1
  out="$out empty=$(b9_verdict "$rf" "$orig" "$d/automate")"
  # (2) stdin missing the title line
  b9_seed "$rf" "$orig"; grep -v '^# Automate Run:' "$orig" | bash "$helper" runfile-write "$rf" >/dev/null 2>&1
  out="$out no_title=$(b9_verdict "$rf" "$orig" "$d/automate")"
  # (3) the incident's exact pipe shape, literally: `awk -v cur="<multi-line>" … $RF | runfile-write $RF`.
  #     BSD awk (macOS) dies "newline in string" and prints nothing — the real
  #     reproduction; GNU awk/mawk accept it and `{print}` re-emits the file, an
  #     identity rewrite. Either way the bytes must come out unchanged.
  b9_seed "$rf" "$orig"
  awk -v cur="- item: b.md | status: running
- pause_reason: null" '{ print }' "$rf" 2>/dev/null | bash "$helper" runfile-write "$rf" >/dev/null 2>&1
  out="$out incident_awk=$(b9_verdict "$rf" "$orig" "$d/automate")"
  # (3b) the same pipe shape with a generator that fails on EVERY awk (syntax
  #      error ⇒ non-zero, no output) — the portable form of (3), so CI on GNU
  #      userland exercises the empty-stdin path too.
  b9_seed "$rf" "$orig"; awk '{ print ' "$rf" 2>/dev/null | bash "$helper" runfile-write "$rf" >/dev/null 2>&1
  out="$out failed_awk=$(b9_verdict "$rf" "$orig" "$d/automate")"
  # (4) progress-append + queue-checkoff on a titleless file (the cascade's second
  #     defect): an emptied run file and a sidecar-shaped stub.
  : > "$rf"; cp "$rf" "$orig"
  bash "$helper" progress-append "$rf" "t2 a" >/dev/null 2>&1
  bash "$helper" progress-append "$rf" "t3 b" >/dev/null 2>&1
  bash "$helper" progress-append "$rf" "t4 c" >/dev/null 2>&1
  out="$out append_on_empty=$(b9_verdict "$rf" "$orig" "$d/automate")"
  printf '## Progress\n- t0 stub\n' > "$rf"; cp "$rf" "$orig"
  bash "$helper" progress-append "$rf" "t2 a" >/dev/null 2>&1
  out="$out append_titleless=$(b9_verdict "$rf" "$orig" "$d/automate")"
  printf '## Queue\n- [ ] a.md\n' > "$rf"; cp "$rf" "$orig"
  bash "$helper" queue-checkoff "$rf" "a.md" >/dev/null 2>&1
  out="$out checkoff_titleless=$(b9_verdict "$rf" "$orig" "$d/automate")"
  # (5) missing ## Status: / missing ## Queue (both mandated by the §3 template)
  b9_seed "$rf" "$orig"; grep -v '^## Status:' "$orig" | bash "$helper" runfile-write "$rf" >/dev/null 2>&1
  out="$out no_status=$(b9_verdict "$rf" "$orig" "$d/automate")"
  b9_seed "$rf" "$orig"; grep -v '^## Queue' "$orig" | bash "$helper" runfile-write "$rf" >/dev/null 2>&1
  out="$out no_queue=$(b9_verdict "$rf" "$orig" "$d/automate")"
  # (6) a generator that died part-way: header sections intact, Progress tail lost
  b9_seed "$rf" "$orig"; sed '$d' "$orig" | bash "$helper" runfile-write "$rf" >/dev/null 2>&1
  out="$out truncated_progress=$(b9_verdict "$rf" "$orig" "$d/automate")"
  rm -rf "$d"
  printf '%s' "${out# }"
}
B9_WANT="empty=kept no_title=kept incident_awk=kept failed_awk=kept append_on_empty=kept append_titleless=kept checkoff_titleless=kept no_status=kept no_queue=kept truncated_progress=kept"
B9_OUT="$(b9_scenarios "$H")"
if [ "$B9_OUT" = "$B9_WANT" ]; then
  ok "B9 fail-closed: every corrupting payload refused, run file byte-unchanged, no temp left ($B9_OUT)"
else
  no "B9 fail-closed: some payload got through:\n  got:  $B9_OUT\n  want: $B9_WANT"
fi

# B9 refusal surface: exit 1 + the [runfile_write_refused] tag on stderr.
WD="$(mktemp -d)"; RF="$WD/automate/run.md"; b9_seed "$RF" "$WD/orig.md"
B9_ERR="$( : | bash "$H" runfile-write "$RF" 2>&1 >/dev/null)"; B9_RC=$?
if [ "$B9_RC" -eq 1 ] && grep -qF 'runfile_write_refused' <<<"$B9_ERR" && grep -qF 'empty content' <<<"$B9_ERR"; then
  ok "B9 refusal: exit 1 with a named reason + [runfile_write_refused] tag"
else
  no "B9 refusal surface wrong (rc=$B9_RC err='$B9_ERR')"
fi

# B9 positive controls — the guard must not block legitimate writes:
#   (a) a ## Current rewrite that SHRINKS the file (pending_decisions dropped) and
#       appends a Progress line; (b) first creation; (c) a human recovery write
#       over an emptied (non-run) file; (d) progress-append/queue-checkoff on a
#       valid run file still work through the validated rename.
sed -e '/^- pending_decisions:/d' -e 's/^- item: a.md | status: running$/- item: b.md | status: running/' "$WD/orig.md" > "$WD/new.md"
printf -- '- t2 picked b.md\n' >> "$WD/new.md"
bash "$H" runfile-write "$RF" < "$WD/new.md" 2>/dev/null; B9_A=$?
RF_NEW="$WD/automate/fresh.md"; printf '%s\n' "$B9_RF_BODY" | bash "$H" runfile-write "$RF_NEW" 2>/dev/null; B9_B=$?
RF_EMPTY="$WD/automate/emptied.md"; : > "$RF_EMPTY"
bash "$H" runfile-write "$RF_EMPTY" < "$WD/orig.md" 2>/dev/null; B9_C=$?
bash "$H" progress-append "$RF" "t3 ok" 2>/dev/null && bash "$H" queue-checkoff "$RF" "a.md" 2>/dev/null; B9_D=$?
if [ "$B9_A" -eq 0 ] && grep -qxF -- '- item: b.md | status: running' "$RF" && ! grep -q '^- pending_decisions:' "$RF" \
   && [ "$B9_B" -eq 0 ] && cmp -s "$RF_NEW" "$WD/orig.md" \
   && [ "$B9_C" -eq 0 ] && cmp -s "$RF_EMPTY" "$WD/orig.md" \
   && [ "$B9_D" -eq 0 ] && grep -qxF -- '- [x] a.md' "$RF" && [ "$(tail -n1 "$RF")" = "- t3 ok" ] \
   && [ "$(ls -A "$WD/automate" | wc -l | tr -d ' ')" = "3" ]; then
  ok "B9 positive controls: shrinking ## Current rewrite, first creation, recovery over an emptied file, and append/check-off on a valid run file all succeed"
else
  no "B9 positive controls blocked a legitimate write (a=$B9_A b=$B9_B c=$B9_C d=$B9_D):\n$(cat "$RF")\n$(ls -A "$WD/automate")"
fi
rm -rf "$WD"

# B9 mutation control: a COPY of the helper with the validation removed (the
# pre-rename refusal forced empty, both is_run_file pre-checks deleted) must let
# the SAME scenarios corrupt the file — proves the cases above are not vacuous.
MUTDIR="$(mktemp -d)"
sed -e 's/^  why="\$(_runfile_refusal .*$/  why=""/' \
    -e '/^  is_run_file "\$out" || die "progress-append: refused/d' \
    -e '/^  is_run_file "\$out" || die "queue-checkoff: refused/d' \
    "$H" > "$MUTDIR/automate-helpers.sh"
if [ -s "$MUTDIR/automate-helpers.sh" ] && ! cmp -s "$H" "$MUTDIR/automate-helpers.sh" && bash -n "$MUTDIR/automate-helpers.sh" 2>/dev/null \
   && grep -qxF '  why=""' "$MUTDIR/automate-helpers.sh" \
   && ! grep -q 'refused — \$out has no' "$MUTDIR/automate-helpers.sh"; then
  B9_MUT="$(b9_scenarios "$MUTDIR/automate-helpers.sh")"
  # incident_awk stays "kept" on GNU awk (identity rewrite) — every OTHER case must turn red.
  B9_MUT_RED=1
  for c in empty no_title failed_awk append_on_empty append_titleless checkoff_titleless no_status no_queue truncated_progress; do
    case " $B9_MUT " in *" $c=CORRUPTED "*) ;; *) B9_MUT_RED=0 ;; esac
  done
  if [ "$B9_MUT_RED" -eq 1 ]; then
    ok "B9 mutation control: validation removed ⇒ every corrupting case turns red ($B9_MUT)"
  else
    no "B9 mutation control did NOT discriminate — a case passes without the guard: $B9_MUT"
  fi
else
  no "B9 mutation control: could not build the mutant (sed did not apply or bash -n failed) -- control inconclusive"
fi
rm -rf "$MUTDIR"

# =============================================================================
echo "== B10. ## Current moves only through a helper (current-set / progress-append current_not_set guard / current-rebuild) =="
# automate-followups/32 Part C: lane w1-10 (run automate-2026-10-04-103627) wrote
# ## Current once at creation and never again — every later event was a
# progress-append — so a RESUME mid-drain would have read "nothing in flight".
CWD="$(mktemp -d)"
# cs_fixture <path> <first ## Current line> [<pause_reason line | "-" for none>]
cs_fixture() {
  local p="$1" il="$2" pl="${3:-- pause_reason: awaiting_go}"
  {
    printf '# Automate Run: cs\n## Status: running\n## Source\n- folder f\n## Run Config\n- mode: safe | limit: 5\n## Queue\n- [ ] a.md\n- [ ] b.md\n## Current\n'
    printf '%s\n' "$il"
    if [ "$pl" != "-" ]; then printf '%s\n' "$pl"; fi
    printf '%s\n' '- owned_drain_started: t9 | owned_drain_result: READY | suppressed_default_dispatch: true'
    printf '%s\n' '- pending_decisions: 2 | fix_now_reentered: false'
    printf '## Progress\n- t0 run created\n'
  } > "$p"
}
CRF="$CWD/r.md"
NULL_ITEM="- item: null | status: null | pr: null | branch: null"

# B10a. byte-diff: only the item + pause_reason lines change; owned_drain_*/pending_decisions untouched.
cs_fixture "$CRF" "$NULL_ITEM"; cp "$CRF" "$CWD/before"
run_h bash "$H" current-set "$CRF" --item a.md --status running --pr null --branch null --pause-reason null
if [ "$RUN_RC" -eq 0 ] && grep -qxF -- '- item: a.md | status: running | pr: null | branch: null' "$CRF" \
   && grep -qxF -- '- pause_reason: null' "$CRF" \
   && [ "$(diff "$CWD/before" "$CRF" | grep -c '^[<>]')" = 4 ] \
   && cmp -s <(grep -vE '^- (item|pause_reason):' "$CWD/before") <(grep -vE '^- (item|pause_reason):' "$CRF"); then
  ok "current-set: only the ## Current item + pause_reason lines change (owned_drain_*/pending_decisions and every other line byte-unchanged)"
else
  no "current-set byte-diff wrong (rc=$RUN_RC): $(diff "$CWD/before" "$CRF" | tr '\n' '|')"
fi
# B10b. idempotent: re-setting the identical values rewrites nothing.
cp "$CRF" "$CWD/set1"
run_h bash "$H" current-set "$CRF" --item a.md --status running --pr null --branch null --pause-reason null
if [ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "current-set: unchanged" ] && cmp -s "$CWD/set1" "$CRF"; then
  ok "current-set: identical values ⇒ 'current-set: unchanged', file byte-identical"
else
  no "current-set re-set not idempotent (rc=$RUN_RC out=$RUN_OUT)"
fi
# B10c. refusals: exit 1, file byte-unchanged.
cs_fixture "$CWD/base" "- item: a.md | status: running | pr: https://github.com/acme/widgets/pull/1 | branch: f/a"
cs_refuse() {
  local label="$1"; shift
  cp "$CWD/base" "$CRF"
  bash "$H" current-set "$CRF" "$@" >/dev/null 2>&1; local rc=$?
  if [ "$rc" -eq 1 ] && cmp -s "$CWD/base" "$CRF"; then ok "current-set refuses $label (exit 1, byte-unchanged)"; else no "current-set $label: rc=$rc or the file changed"; fi
}
cs_refuse "an unknown status" --item a.md --status parked
cs_refuse "an unknown pause_reason (run-level form)" --pause-reason bogus
cs_refuse "an unknown pause_reason (item form)" --item a.md --status running --pause-reason parked
cs_refuse "a half-null item form (item null, status set)" --item null --status running
cs_refuse "a half-null item form (item set, status null)" --item a.md --status null
cs_refuse "an item form missing --status" --item a.md
cs_refuse "an item form missing --item" --status running
cs_refuse "a run-level form missing --pause-reason" --pr https://github.com/acme/widgets/pull/2
cs_refuse "no arguments at all"
cs_refuse "a '|'-bearing item" --item 'a.md | status: done' --status running
cs_refuse "a '|'-bearing pr" --item a.md --status running --pr 'x|y'
cs_refuse "a newline-bearing item" --item "$(printf 'a.md\nb.md')" --status running
cs_refuse "an empty value" --item a.md --status running --branch ''
cs_refuse "an unknown flag" --item a.md --status running --owner me
printf '## Status: running\n## Queue\n## Current\n- item: null | status: null\n## Progress\n' > "$CWD/norun.md"; cp "$CWD/norun.md" "$CWD/norun.before"
bash "$H" current-set "$CWD/norun.md" --item a.md --status running >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && cmp -s "$CWD/norun.before" "$CWD/norun.md" && ok "current-set refuses a non-run file (no title; exit 1, byte-unchanged)" || no "current-set on a non-run file: rc=$rc"
printf '# Automate Run: x\n## Status: running\n## Queue\n- [ ] a.md\n## Progress\n- t0\n' > "$CWD/nocur.md"; cp "$CWD/nocur.md" "$CWD/nocur.before"
bash "$H" current-set "$CWD/nocur.md" --pause-reason null >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && cmp -s "$CWD/nocur.before" "$CWD/nocur.md" && ok "current-set refuses a run file with no ## Current heading (exit 1, byte-unchanged)" || no "current-set on a Current-less file: rc=$rc"
# B10d. pr/branch retention: same item keeps them; a CHANGED item resets omitted ones to null.
cs_retention() {  # cs_retention <helper> — prints the two item lines it produced, '|'-joined
  local h="$1"
  cs_fixture "$CRF" "$NULL_ITEM"
  bash "$h" current-set "$CRF" --item a.md --status running --pr https://github.com/acme/widgets/pull/1 --branch f/a >/dev/null 2>&1
  bash "$h" current-set "$CRF" --item a.md --status awaiting_merge >/dev/null 2>&1
  printf '%s' "$(grep '^- item: ' "$CRF")"
  bash "$h" current-set "$CRF" --item b.md --status running >/dev/null 2>&1
  printf ' || %s' "$(grep '^- item: ' "$CRF")"
}
CS_WANT='- item: a.md | status: awaiting_merge | pr: https://github.com/acme/widgets/pull/1 | branch: f/a || - item: b.md | status: running | pr: null | branch: null'
cs_got="$(cs_retention "$H")"
[ "$cs_got" = "$CS_WANT" ] && ok "current-set: same --item keeps pr/branch; a changed --item resets omitted pr/branch to null" || no "current-set retention wrong: $cs_got"
# mutation control: without the reset, the previous item's PR rides into the new item.
CSM="$CWD/mut"; mkdir -p "$CSM"
sed '/^      if \[ "\$hp" = 0 \]; then pr=null; hp=1; fi$/d' "$H" > "$CSM/automate-helpers.sh"
if ! cmp -s "$H" "$CSM/automate-helpers.sh" && bash -n "$CSM/automate-helpers.sh" 2>/dev/null; then
  case "$(cs_retention "$CSM/automate-helpers.sh")" in
    *"- item: b.md | status: running | pr: https://github.com/acme/widgets/pull/1 |"*) ok "mutation control: without the item-change reset the old PR rides into b.md (the retention leg is load-bearing)" ;;
    *) no "pr-reset mutant did not carry the PR — the retention leg may be vacuous" ;;
  esac
else
  no "pr-reset mutant not built"
fi
# B10e. run-level form: --pause-reason closeout_leftover leaves the item line byte-unchanged.
cp "$CWD/base" "$CRF"
run_h bash "$H" current-set "$CRF" --pause-reason closeout_leftover
if [ "$RUN_RC" -eq 0 ] && grep -qxF -- '- pause_reason: closeout_leftover' "$CRF" \
   && cmp -s <(grep -v '^- pause_reason:' "$CWD/base") <(grep -v '^- pause_reason:' "$CRF"); then
  ok "current-set run-level form (--pause-reason closeout_leftover): item line and every other line byte-unchanged"
else
  no "run-level form wrong (rc=$RUN_RC): $(diff "$CWD/base" "$CRF" | tr '\n' '|')"
fi
# B10f. a block with no pause_reason line gets one appended INSIDE ## Current; a block
#       with no item line gets one right under the heading.
cs_fixture "$CRF" "- reason_hint: rate_limit" "-"
bash "$H" current-set "$CRF" --item a.md --status running --pause-reason awaiting_merge >/dev/null 2>&1
cs_blk="$(awk '/^## Current/{c=1;next} /^## /{c=0} c' "$CRF" | tr '\n' '|')"
[ "$cs_blk" = "- item: a.md | status: running | pr: null | branch: null|- reason_hint: rate_limit|- owned_drain_started: t9 | owned_drain_result: READY | suppressed_default_dispatch: true|- pending_decisions: 2 | fix_now_reentered: false|- pause_reason: awaiting_merge|" ] \
  && ok "current-set: absent item line inserted under the heading, absent pause_reason appended inside the block" || no "current-set insertion wrong: $cs_blk"

# B10g. progress-append current_not_set guard (exit 3, line still appended).
PRF="$CWD/g.md"
pg_case() {  # pg_case <label> <## Current item line> <line> <want rc>
  cs_fixture "$PRF" "$2"
  local err rc; err="$(bash "$H" progress-append "$PRF" "$3" 2>&1 >/dev/null)"; rc=$?
  if [ "$rc" -ne "$4" ]; then no "guard $1: rc=$rc want $4 (stderr: $err)"; return; fi
  if ! grep -qxF -- "- $3" "$PRF"; then no "guard $1: line not appended"; return; fi
  if [ "$4" -eq 3 ] && [ "$err" != "current_not_set: $3" ]; then no "guard $1: stderr '$err'"; return; fi
  ok "guard $1 ⇒ exit $4, line appended"
}
SET_A="- item: a.md | status: running | pr: null | branch: null"
pg_case "null item + '<ts> picked a.md'" "$NULL_ITEM" "t1 picked a.md" 3
pg_case "null item + 'picked a.md' (no ts)" "$NULL_ITEM" "picked a.md" 3
pg_case "null item + 'ran /autonomous → PR <url>'" "$NULL_ITEM" "t1 ran /autonomous → PR $PR" 3
pg_case "null item + 'owned drain started: …'" "$NULL_ITEM" "t1 owned drain started: /review-pr $PR --until-mergeable" 3
pg_case "absent item line + picked" "- reason_hint: x" "t1 picked a.md" 3
pg_case "empty item value + picked" "- item:  | status: running" "t1 picked a.md" 3
pg_case "null item + '<ts> parked …' (not guarded)" "$NULL_ITEM" "t1 parked limit_reached — remaining 2" 0
pg_case "null item + a run-level run_lock_held park line" "$NULL_ITEM" "t1 run_lock_held owner=automate:x pid=1 age=3 — paused" 0
pg_case "null item + a closeout step line" "$NULL_ITEM" "t1 closeout $PR: closeout: checked — - [x] a.md" 0
pg_case "Current set + picked a.md" "$SET_A" "t1 picked a.md" 0
pg_case "Current set + ran /autonomous" "$SET_A" "t1 ran /autonomous → PR $PR" 0
pg_case "Current set + owned drain started" "$SET_A" "t1 owned drain started: x" 0
pg_case "picked b.md while ## Current names non-done a.md" "$SET_A" "t5 picked b.md" 3
pg_case "picked b.md, (comma suffix) while a.md running" "$SET_A" "t5 picked b.md, owner go" 3
pg_case "picked b.md while a.md is done" "- item: a.md | status: done | pr: $PR | branch: f/a" "t5 picked b.md" 0
pg_case "'picked a.md (run-lock acquired; …)' with Current a.md" "$SET_A" "t5 picked a.md (run-lock acquired; session x)" 0
pg_case "'picked a.md (run-lock acquired; …)' with Current ./a.md" "- item: ./a.md | status: running | pr: null | branch: null" "t5 picked a.md (run-lock acquired; session x)" 0
pg_case "'picked ./a.md; suppressed …' with Current a.md" "$SET_A" "t5 picked ./a.md; suppressed auto_review" 0
# mutation control: the guard call deleted ⇒ the null-item picked case exits 0.
PGM="$CWD/pgm"; mkdir -p "$PGM"
sed '/^  _progress_current_guard "\$out" "\$line"$/d' "$H" > "$PGM/automate-helpers.sh"
if ! cmp -s "$H" "$PGM/automate-helpers.sh" && bash -n "$PGM/automate-helpers.sh" 2>/dev/null; then
  cs_fixture "$PRF" "$NULL_ITEM"
  bash "$PGM/automate-helpers.sh" progress-append "$PRF" "t1 picked a.md" >/dev/null 2>&1 \
    && ok "mutation control: without the guard a null-Current picked line exits 0 (the exit-3 legs are load-bearing)" || no "guard mutant still refused"
else
  no "guard mutant not built"
fi
# B10h. w1-10 replay (automate-2026-10-04-103627): the creation write, then its
#       Progress-only history — the guard refuses at the FIRST picked line.
W10="$CWD/w10.md"
W10_ITEM=".supervisor/requirements/parallel-automate/10-touches-backfill-lint-and-explain.md"
W10_PR="https://github.com/vikashruhilgit/loomwright/pull/377"
bash "$H" runfile-write "$W10" <<EOF
# Automate Run: S1 v2 lane w1-10 — item 10
## Status: running
## Source
- backlog .supervisor/s1-backlog.md
## Run Config
- mode: safe | limit: 5 | trust_unprotected: false
- auto_review_original: absent | config_backup: automate-2026-10-04-103627.config-backup.json
## Queue
- [ ] $W10_ITEM
## Current
- item: null | status: null | pr: null | branch: null
- pause_reason: null
## Progress
- 2026-10-04T10:36:27Z run created; queue confirmed by owner (1 item, start new — other incomplete runs left untouched)
EOF
w10_first=""; w10_n=0
while IFS= read -r l; do
  w10_n=$((w10_n+1))
  bash "$H" progress-append "$W10" "$l" >/dev/null 2>&1; rc=$?
  if [ "$rc" -ne 0 ] && [ -z "$w10_first" ]; then w10_first="$w10_n:$rc:$l"; fi
done <<EOF
trail-gate: clear — no open trail PR; sync skipped — already synced (main at origin/main)
trail-unstage: skipped — branch mode
2026-10-04T10:39:26Z picked $W10_ITEM
reconcile-status: would stamp .supervisor/requirements/token-economy/07-verify-spec-replay.md (done (PR #269, merge e319536))
2026-10-04T11:44:52Z session_id fa3574db (.supervisor/requirements/parallel-automate/10-touches-backfill-lint-and-explain.md)
2026-10-04T11:44:52Z ran /autonomous → PR $W10_PR (heal PASS after 1 fix iteration)
2026-10-04T11:45:12Z owned drain started: /review-pr $W10_PR --until-mergeable --no-auto-postmortem (suppressed_default_dispatch: true)
2026-10-04T14:19:45Z gate (safe mode): parked awaiting_merge — PR $W10_PR READY, left open for a human merge
2026-10-04T14:27:00Z closeout $W10_PR: closeout: synced — main at 2bdb2b7
EOF
[ "$w10_first" = "3:3:2026-10-04T10:39:26Z picked $W10_ITEM" ] \
  && ok "w1-10 replay: the guard refuses (exit 3) at the first picked line, every earlier line exits 0" || no "w1-10 replay first refusal wrong: $w10_first"
grep -qxF -- "- 2026-10-04T14:27:00Z closeout $W10_PR: closeout: synced — main at 2bdb2b7" "$W10" \
  && ok "w1-10 replay: every line is still appended (loud, not lossy)" || no "w1-10 replay lost a line"

# B10i. current-rebuild (stubbed gh: OPEN / MERGED / CLOSED / failing).
CBIN="$CWD/bin"; make_stub_bin "$CBIN"; CGH="$CWD/ghstub"; mkdir -p "$CGH"
cr_fixture() {  # cr_fixture <path> <progress line>...
  local p="$1" l; shift
  {
    printf '# Automate Run: cr\n## Status: paused\n## Source\n- folder q\n## Run Config\n- mode: safe | limit: 5\n## Queue\n- [x] q/01-a.md\n- [ ] q/02-b.md\n## Current\n'
    printf '%s\n' "$NULL_ITEM" '- pause_reason: awaiting_merge' '## Progress'
    for l in "$@"; do printf -- '- %s\n' "$l"; done
  } > "$p"
}
cr_run() { RUN_OUT="$(PATH="$CBIN:$PATH" GH_STUB_DIR="$CGH" bash "${CR_H:-$H}" current-rebuild "$1" 2>/dev/null)"; RUN_RC=$?; }
CRB="$CWD/cr.md"; B_PR="https://github.com/acme/widgets/pull/9"
for st in OPEN MERGED CLOSED fail; do
  rm -f "$CGH/pr-view-fail"
  case "$st" in
    fail) : > "$CGH/pr-view-fail"; want_state=unknown; want_br=null ;;
    MERGED) printf '{"state":"MERGED","mergedAt":"2026-10-05T00:00:00Z","headRefName":"feature/b"}\n' > "$CGH/pr-view.json"; want_state=MERGED; want_br=feature/b ;;
    *) printf '{"state":"%s","mergedAt":null,"headRefName":"feature/b"}\n' "$st" > "$CGH/pr-view.json"; want_state="$st"; want_br=feature/b ;;
  esac
  cr_fixture "$CRB" "t0 picked q/01-a.md" "t0 ran /autonomous → PR https://github.com/acme/widgets/pull/3" \
    "t1 picked q/02-b.md; suppressed auto_review (backup cr.config-backup.json)" "t2 ran /autonomous → PR $B_PR (heal PASS)"
  cr_run "$CRB"
  want_line="current_rebuilt: q/02-b.md pr $B_PR state $want_state"
  if [ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "$want_line" ] \
     && grep -qxF -- "- item: q/02-b.md | status: running | pr: $B_PR | branch: $want_br" "$CRB" \
     && [ "$(tail -n1 "$CRB")" = "- $want_line" ]; then
    ok "current-rebuild ($st): ## Current rebuilt status running + pr + branch $want_br, '$want_line' printed and appended"
  else
    no "current-rebuild ($st) wrong (rc=$RUN_RC out=$RUN_OUT): $(grep '^- item:' "$CRB")"
  fi
done
rm -f "$CGH/pr-view-fail"
cp "$CRB" "$CWD/cr.set"; cr_run "$CRB"
[ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "current-rebuild: skipped — ## Current set" ] && cmp -s "$CWD/cr.set" "$CRB" \
  && ok "current-rebuild second run: 'skipped — ## Current set', nothing written" || no "current-rebuild second run wrong (rc=$RUN_RC out=$RUN_OUT)"
# B10j. A `done` ## Current left behind by a PICK that skipped its current-set after a
# close-out (the guard exempts a done Current, so both lines append with exit 0) is
# stale: current-rebuild repairs it from the LAST picked line. Before the fix it
# printed 'skipped — ## Current set' and Current kept naming a.md while b's PR was open.
A_PR="https://github.com/acme/widgets/pull/3"; B2_PR="https://github.com/acme/widgets/pull/2"
crd_fixture() {  # crd_fixture <path> <progress line>...
  local p="$1" l; shift
  {
    printf '# Automate Run: crd\n## Status: running\n## Source\n- folder q\n## Run Config\n- mode: safe | limit: 5\n## Queue\n- [x] q/01-a.md\n- [ ] q/02-b.md\n## Current\n'
    printf '%s\n' "- item: q/01-a.md | status: done | pr: $A_PR | branch: feature/a" '- pause_reason: null' '## Progress'
    for l in "$@"; do printf -- '- %s\n' "$l"; done
  } > "$p"
}
crd_stale() {  # the reviewer's repro: a done a.md, then 'picked b' + 'ran → PR 2' with no current-set
  crd_fixture "$CRB" "t0 picked q/01-a.md" "t0 ran /autonomous → PR $A_PR" "t1 closeout $A_PR: closeout: checked — - [x] q/01-a.md"
  local r1 r2
  bash "$H" progress-append "$CRB" "t2 picked q/02-b.md; suppressed auto_review" 2>/dev/null; r1=$?
  bash "$H" progress-append "$CRB" "t3 ran /autonomous → PR $B2_PR" 2>/dev/null; r2=$?
  CRD_APPEND_RC="$r1/$r2"
  cr_run "$CRB"
}
printf '{"state":"OPEN","mergedAt":null,"headRefName":"feature/b"}\n' > "$CGH/pr-view.json"
crd_stale
[ "$CRD_APPEND_RC" = "0/0" ] && ok "(B10j) the guard lets 'picked b' + 'ran /autonomous' over a done a.md through (exit 0/0 — the documented exemption)" || no "(B10j) append rcs: $CRD_APPEND_RC"
[ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "current_rebuilt: q/02-b.md pr $B2_PR state OPEN" ] \
  && grep -qxF -- "- item: q/02-b.md | status: running | pr: $B2_PR | branch: feature/b" "$CRB" \
  && ok "(B10j) current-rebuild repairs a stale done ## Current to the last picked item (b, its PR, running)" \
  || no "(B10j) stale done Current not rebuilt (rc=$RUN_RC out=$RUN_OUT): $(grep '^- item:' "$CRB")"
# Mutation control (the before-state): a done Current treated as 'set' ⇒ the repro is skipped.
CRDM="$CWD/crdm"; mkdir -p "$CRDM"
sed 's|^    \[ "\$cs" = done \] \|\| { echo "\$R ## Current set"; return 0; }$|    { echo "$R ## Current set"; return 0; }|' "$H" > "$CRDM/automate-helpers.sh"
if ! cmp -s "$H" "$CRDM/automate-helpers.sh" && bash -n "$CRDM/automate-helpers.sh" 2>/dev/null; then
  CR_H="$CRDM/automate-helpers.sh" crd_stale
  [ "$RUN_OUT" = "current-rebuild: skipped — ## Current set" ] && grep -q '^- item: q/01-a.md | status: done' "$CRB" \
    && ok "(B10j) mutation control: the pre-fix rule skips the repro and leaves a.md named" || no "(B10j) mutant did not reproduce the bug ($RUN_OUT)"
else
  no "(B10j) done-exemption mutant not built"
fi
# Negatives: a done Current that IS the last picked item (a correct close-out), and a
# done Current with a './'-prefixed picked token naming it, are never rebuilt.
crd_fixture "$CRB" "t0 picked q/01-a.md" "t0 ran /autonomous → PR $A_PR" "t1 closeout $A_PR: closeout: checked — - [x] q/01-a.md"
cp "$CRB" "$CWD/crd.same"; cr_run "$CRB"
[ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "current-rebuild: skipped — ## Current set" ] && cmp -s "$CWD/crd.same" "$CRB" \
  && ok "(B10j) a done Current naming the last picked item ⇒ skipped, nothing written" || no "(B10j) same-item done wrong (rc=$RUN_RC out=$RUN_OUT)"
crd_fixture "$CRB" "t0 picked ./q/01-a.md (run-lock acquired; session x)"
cp "$CRB" "$CWD/crd.dot"; cr_run "$CRB"
[ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "current-rebuild: skipped — ## Current set" ] && cmp -s "$CWD/crd.dot" "$CRB" \
  && ok "(B10j) a done Current vs './'-prefixed picked token of the same item ⇒ skipped" || no "(B10j) ./ compare wrong (rc=$RUN_RC out=$RUN_OUT)"
crd_fixture "$CRB" "t0 run created"
cp "$CRB" "$CWD/crd.np"; cr_run "$CRB"
[ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "current-rebuild: skipped — ## Current set" ] && cmp -s "$CWD/crd.np" "$CRB" \
  && ok "(B10j) a done Current with no picked line ⇒ skipped, nothing written" || no "(B10j) no-picked done wrong (rc=$RUN_RC out=$RUN_OUT)"
# Negative: foreign PR URLs on closeout / trail / cross-run lines and no ran
# /autonomous after the last picked ⇒ pr stays null ('(owner …)' suffix parsed).
cr_foreign() {
  cr_fixture "$CRB" "t0 picked q/01-a.md" "t0 ran /autonomous → PR https://github.com/acme/widgets/pull/3" \
    "t1 picked q/02-b.md (owner go)" "t2 closeout https://github.com/acme/widgets/pull/5: closeout: checked — - [x] q/01-a.md" \
    "trail-pr: opened https://github.com/acme/widgets/pull/6 (chore/cr-trail-1)" \
    "t3 cross-run closeout automate-x q/01-a.md https://github.com/acme/widgets/pull/4: complete"
  cr_run "$CRB"
}
cr_foreign
[ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "current_rebuilt: q/02-b.md pr null state none" ] \
  && grep -qxF -- "- item: q/02-b.md | status: running | pr: null | branch: null" "$CRB" \
  && ok "current-rebuild: foreign PR URLs (closeout/trail/cross-run lines, an earlier item's ran line) never attach — pr null" || no "current-rebuild attached a foreign PR (out=$RUN_OUT): $(grep '^- item:' "$CRB")"
# mutation control: reading the PR from ANY later Progress line attaches a foreign one.
CRM="$CWD/crm"; mkdir -p "$CRM"
sed 's|^    NR > ENVIRON\["PN"\]+0 && /^- (\[^ \]+ )?ran \\/autonomous/ {$|    NR > ENVIRON["PN"]+0 {|' "$H" > "$CRM/automate-helpers.sh"
if ! cmp -s "$H" "$CRM/automate-helpers.sh" && bash -n "$CRM/automate-helpers.sh" 2>/dev/null; then
  CR_H="$CRM/automate-helpers.sh" cr_foreign
  case "$RUN_OUT" in *"pr null"*) no "foreign-PR mutant still null — the negative leg may be vacuous ($RUN_OUT)" ;; *) ok "mutation control: reading any Progress line attaches a foreign PR ($RUN_OUT)" ;; esac
else
  no "foreign-PR mutant not built"
fi
cr_fixture "$CRB" "t1 picked q/09-z.md" "t2 ran /autonomous → PR $B_PR"; cp "$CRB" "$CWD/cr.nq"; cr_run "$CRB"
[ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "current-rebuild: skipped — picked item not in Queue" ] && cmp -s "$CWD/cr.nq" "$CRB" \
  && ok "current-rebuild: picked item not in the Queue ⇒ skipped, nothing written" || no "current-rebuild not-in-Queue wrong (rc=$RUN_RC out=$RUN_OUT)"
cr_fixture "$CRB" "t1 run created"; cp "$CRB" "$CWD/cr.np"; cr_run "$CRB"
[ "$RUN_RC" -eq 0 ] && [ "$RUN_OUT" = "current-rebuild: skipped — no picked line in ## Progress" ] && cmp -s "$CWD/cr.np" "$CRB" \
  && ok "current-rebuild: no picked line ⇒ skipped, nothing written" || no "current-rebuild no-picked wrong (rc=$RUN_RC out=$RUN_OUT)"
# The w1-10 replay above, rebuilt (gh says MERGED): the ran line names PR 377.
printf '{"state":"MERGED","mergedAt":"2026-10-04T14:26:00Z","headRefName":"feature/parallel-automate-10-touches-lint-and-explain"}\n' > "$CGH/pr-view.json"
cr_run "$W10"
[ "$RUN_OUT" = "current_rebuilt: $W10_ITEM pr $W10_PR state MERGED" ] \
  && grep -qxF -- "- item: $W10_ITEM | status: running | pr: $W10_PR | branch: feature/parallel-automate-10-touches-lint-and-explain" "$W10" \
  && ok "current-rebuild on the w1-10 replay: item + PR 377 + branch, status running (never awaiting_merge)" || no "w1-10 rebuild wrong: $RUN_OUT"
rm -rf "$CWD"

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

# =============================================================================
# =============================================================================
echo "== E. auto-merge gate (SELF-RESOLVING, red-team-hardening/03): fail CLOSED on EACH condition; ctx-owned-key refusal; all-pass MERGE fires once =="

WD="$(mktemp -d)"; WD="$(cd "$WD" && pwd -P)"; BIN="$WD/bin"; make_stub_bin "$BIN"
export GH_STUB_DIR="$WD/ghstub"; mkdir -p "$GH_STUB_DIR"

# E_ROOT — the `--root` every gate case hands the gate: a REAL git checkout
# (automate-followups/16 — condition 7 now pins `--root` to the live PR head and a
# clean tree before it trusts the rules verdict). Its committed tree tracks one file
# under each engine-owned path (.supervisor/ and $E_MEM, the agent-memory store) plus a
# .gitignore, so Section R can dirty them. Every fixture file (ctx.json, stubs, result
# artifacts) lives in $WD OUTSIDE the checkout, so the harness never dirties it.
# E_PR_HEAD is the head the stubbed `gh pr view` reports AND pass_ctx's `ready_sha`
# (cond 2 holds); it defaults to the checkout's own HEAD (E_HEAD), so every
# pre-existing case reaches cond 7 on an at-head, clean checkout exactly as before.
# E_TIP is a real child commit the checkout is NOT on (built with commit-tree, so the
# working tree is untouched) — the "PR moved on, the checkout did not" head.
# gate() runs with GIT_CEILING_DIRECTORIES=$WD so a non-checkout root under $WD can
# never be resolved to some enclosing repo of the temp dir.
E_ROOT="$WD/checkout"
E_MEM=".claude/agent-memory"   # the gate's second engine-owned exclusion (repo-relative)
mkdir -p "$E_ROOT/sub" "$E_ROOT/.supervisor/automate" "$E_ROOT/$E_MEM/loomwright:code-reviewer"
( cd "$E_ROOT" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false \
    && echo a > sub/a && echo run > .supervisor/automate/run.md \
    && echo mem > "$E_MEM/loomwright:code-reviewer/MEMORY.md" \
    && printf 'ignored.log\nignored-dir/\n' > .gitignore && git add -A && git commit -qm init ) >/dev/null 2>&1
E_HEAD="$(git -C "$E_ROOT" rev-parse --verify -q HEAD 2>/dev/null)" || E_HEAD=""
E_TIP="$(git -C "$E_ROOT" commit-tree "HEAD^{tree}" -p HEAD -m tip 2>/dev/null)" || E_TIP=""
E_PR_HEAD="$E_HEAD"
if [ -n "$E_HEAD" ] && [ -n "$E_TIP" ] && [ "$E_HEAD" != "$E_TIP" ] \
   && [ -z "$(git -C "$E_ROOT" status --porcelain -uall 2>/dev/null)" ]; then
  ok "E harness: a real, clean git checkout at E_HEAD plus a distinct child commit E_TIP"
else
  no "E harness: could not build the git checkout (head='$E_HEAD' tip='$E_TIP') — every gate case below is meaningless"
fi

# The gate now finds classify-risk.sh via a SIBLING lookup ($(dirname "$0")), so
# tests run against a scratch COPY of automate-helpers.sh alongside a STUBBED
# classify-risk.sh (never the real git-diffing script) — mirrors the brief_repair
# sibling-lookup precedent already used by Section G.
GWD="$WD/gharness"; mkdir -p "$GWD"
cp "$H" "$GWD/automate-helpers.sh"
cat > "$GWD/classify-risk.sh" <<'RISK'
#!/usr/bin/env bash
set -u
if [ -n "${GH_STUB_DIR:-}" ] && [ -f "$GH_STUB_DIR/risk.json" ]; then
  cat "$GH_STUB_DIR/risk.json"
else
  echo '{"high_risk": false, "reasons": [], "changed_files": 0, "changed_lines": 0, "source": "classify-risk.sh"}'
fi
RISK
chmod +x "$GWD/classify-risk.sh"
# Condition 7's sibling rules-gate-verdict.sh — likewise a STUB beside the gate copy
# (never the real checker): it logs its argv to rules-called.log (the call-log
# assertions prove cond 7 is gate-owned and self-resolved) and echoes rules.json.
# reset_live re-baselines rules.json to verdict `none` (nothing countable ⇒ the
# condition holds), so every PRE-EXISTING gate case MERGEs/PARKs exactly as before.
RULES_NONE='{"verdict":"none","selected":[],"countable":[],"advisory":[],"passed":[],"failing":[],"unresolved":[],"checks_passed":null}'
cat > "$GWD/rules-gate-verdict.sh" <<'RULES'
#!/usr/bin/env bash
set -u
if [ -n "${GH_STUB_DIR:-}" ]; then
  printf '%s\n' "$*" >> "$GH_STUB_DIR/rules-called.log"
  if [ -f "$GH_STUB_DIR/rules.json" ]; then cat "$GH_STUB_DIR/rules.json"; fi
  if [ -f "$GH_STUB_DIR/rules-exit" ]; then exit "$(cat "$GH_STUB_DIR/rules-exit")"; fi
fi
exit 0
RULES
chmod +x "$GWD/rules-gate-verdict.sh"

# Fixture artifact files the gate cross-checks/parses ITSELF (cond 1 cross-check,
# cond 5 rubric) — no longer caller-asserted ctx fields.
RHR="$WD/review-heal-result.md"
printf '## REVIEW_HEAL_RESULT\n- schema_version: 2\n- decision: READY\n- termination_reason: converged\n' > "$RHR"
RHR_ESCALATED="$WD/review-heal-result-escalated.md"
printf '## REVIEW_HEAL_RESULT\n- schema_version: 2\n- decision: ESCALATED\n- termination_reason: bound_hit\n' > "$RHR_ESCALATED"
SUP_NA="$WD/supervisor-result-na.md"
printf '## SUPERVISOR_RESULT\n- status: completed\n- heal_decision: PASS\n' > "$SUP_NA"
SUP_OK="$WD/supervisor-result-ok.md"
printf '## SUPERVISOR_RESULT\n- rubric_score: 7/7\n' > "$SUP_OK"
SUP_BAD="$WD/supervisor-result-bad.md"
printf '## SUPERVISOR_RESULT\n- rubric_score: 6/7\n' > "$SUP_BAD"

# reset_live — re-baseline every LIVE gh/api/classify-risk fixture to a fully
# passing state (each test then mutates ONE fixture to its failing shape).
reset_live() {
  printf '{"headRefOid":"%s","baseRefName":"main","statusCheckRollup":[{"name":"ci","conclusion":"SUCCESS"}]}\n' "$E_PR_HEAD" > "$GH_STUB_DIR/pr-view.json"
  rm -f "$GH_STUB_DIR/pr-view-fail"
  printf '{"reviewDecision":"APPROVED"}\n' > "$GH_STUB_DIR/pr-view-rd.json"
  rm -f "$GH_STUB_DIR/pr-view-rd-fail"
  printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false},"nodes":[]}}}}}\n' > "$GH_STUB_DIR/graphql.json"
  rm -f "$GH_STUB_DIR/graphql-fail"
  printf '{"required_pull_request_reviews":{"required_approving_review_count":1},"required_status_checks":{"contexts":["ci"]}}\n' > "$GH_STUB_DIR/protection.json"
  rm -f "$GH_STUB_DIR/protection-404" "$GH_STUB_DIR/protection-fail"
  printf '{"high_risk": false, "reasons": [], "changed_files": 0, "changed_lines": 0, "source": "classify-risk.sh"}\n' > "$GH_STUB_DIR/risk.json"
  rm -f "$GH_STUB_DIR/merge-fail"
  printf '%s\n' "$RULES_NONE" > "$GH_STUB_DIR/rules.json"
  rm -f "$GH_STUB_DIR/rules-exit" "$GH_STUB_DIR/rules-called.log"
}

# A fully-passing ctx (the SHRUNK shape — exactly the 6 allowed keys).
pass_ctx() {
  cat <<EOF
{
  "drain_result": "READY", "termination_reason": "converged",
  "ready_sha": "$E_PR_HEAD",
  "trust_unprotected": false,
  "review_heal_result_path": "$RHR",
  "supervisor_result_path": "$SUP_NA"
}
EOF
}

gate() {  # gate <ctx-json-string> -> sets RUN_OUT/RUN_RC, isolates a fresh merge.log; --root = ${E_GATE_ROOT:-$E_ROOT}
  rm -f "$GH_STUB_DIR/merge.log"
  printf '%s' "$1" > "$WD/ctx.json"
  RUN_OUT="$( env PATH="$BIN:$PATH" GH_STUB_DIR="$GH_STUB_DIR" HOME="$WD/nohome" GIT_CEILING_DIRECTORIES="$WD" bash "$GWD/automate-helpers.sh" gate-eval "$PR" "$WD/ctx.json" --root "${E_GATE_ROOT:-$E_ROOT}" 2>/dev/null )"; RUN_RC=$?
}
merges() { [ -f "$GH_STUB_DIR/merge.log" ] && grep -c MERGE_CALLED "$GH_STUB_DIR/merge.log" || echo 0; }

reset_live

# --- ctx-owned-key REFUSAL (AC2, the single most important new behavior) ---
# A ctx that tries to hand the gate a pre-computed verdict for ANY now-gate-owned
# key is refused BEFORE anything else runs, regardless of the value it carries.
for K in high_risk risk_reasons head_sha base review_decision \
         unresolved_human_thread protection_enforceable checks_green rubric_satisfied; do
  gate "$(pass_ctx | jq --arg k "$K" '.[$k]=false')"
  if [ "$RUN_OUT" = "PARK: ctx_carries_gate_owned_key" ] && [ "$(merges)" -eq 0 ]; then
    ok "gate refuses gate-owned ctx key '$K' ⇒ PARK: ctx_carries_gate_owned_key, no merge"
  else
    no "gate did NOT refuse gate-owned ctx key '$K' (out='$RUN_OUT' merges=$(merges))"
  fi
done

# --- Condition 1 / 1b (unchanged ctx reads) ---
gate "$(pass_ctx | jq '.drain_result="ESCALATED"')"
if [ "$RUN_OUT" = "PARK: drain_not_ready" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: drain ESCALATED ⇒ PARK, no merge"
else
  no "gate drain wrong (out='$RUN_OUT' merges=$(merges))"
fi
gate "$(pass_ctx | jq '.termination_reason="sub_floor_converged"')"
if [ "$RUN_OUT" = "PARK: sub_floor_not_merge_eligible" ] && [ "$(merges)" -eq 0 ]; then
  ok "AC9 fail-closed: sub_floor_converged READY ⇒ PARK, no merge"
else
  no "AC9 sub_floor_converged wrong (out='$RUN_OUT' merges=$(merges))"
fi
gate "$(pass_ctx | jq 'del(.termination_reason)')"
if [ "$RUN_OUT" = "PARK: sub_floor_not_merge_eligible" ] && [ "$(merges)" -eq 0 ]; then
  ok "AC9 fail-closed: MISSING termination_reason ⇒ PARK (no fail-open)"
else
  no "AC9 missing-termination_reason FAILED OPEN (out='$RUN_OUT' merges=$(merges))"
fi

# --- Condition 1c (ci-trust-probe-01) — `ci_untrusted` is NEVER merge-eligible.
# Two cases, both must PARK (brief AC): the well-formed shape a real drain
# actually emits (drain_result ESCALATED, since an untrusted_infra required
# check still blocks READY) AND, as a defense-in-depth mutation control, a
# deliberately-malformed drain_result READY + termination_reason ci_untrusted
# combination — proving even a hypothetically-corrupted ctx can't merge on
# this reason. ---
gate "$(pass_ctx | jq '.drain_result="ESCALATED" | .termination_reason="ci_untrusted"')"
if [ "$RUN_OUT" = "PARK: drain_not_ready" ] && [ "$(merges)" -eq 0 ]; then
  ok "ci-trust-probe-01: well-formed ci_untrusted (ESCALATED) ⇒ PARK: drain_not_ready, no merge"
else
  no "ci-trust-probe-01 well-formed ci_untrusted wrong (out='$RUN_OUT' merges=$(merges))"
fi
gate "$(pass_ctx | jq '.termination_reason="ci_untrusted"')"   # drain_result stays "READY" from pass_ctx — the mutation
if [ "$RUN_OUT" = "PARK: ci_untrusted_not_merge_eligible" ] && [ "$(merges)" -eq 0 ]; then
  ok "ci-trust-probe-01: mutation control — corrupted READY+ci_untrusted ctx still ⇒ PARK, no merge"
else
  no "ci-trust-probe-01 mutation-control ci_untrusted FAILED OPEN (out='$RUN_OUT' merges=$(merges))"
fi

# --- Condition 1 cross-check (NEW) — the drain's self-report must match the
# REVIEW_HEAL_RESULT artifact it actually wrote. ---
gate "$(pass_ctx | jq '.review_heal_result_path="/no/such/file"')"
if [ "$RUN_OUT" = "PARK: review_heal_result_unreadable" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: unreadable review_heal_result_path ⇒ PARK, no merge"
else
  no "gate review_heal_result unreadable wrong (out='$RUN_OUT' merges=$(merges))"
fi
gate "$(pass_ctx | jq --arg p "$RHR_ESCALATED" '.review_heal_result_path=$p')"
if [ "$RUN_OUT" = "PARK: drain_result_mismatch" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: ctx drain_result disagrees with the REVIEW_HEAL_RESULT artifact ⇒ PARK, no merge (the drain's self-report is corroborated, never trusted blind)"
else
  no "gate drain_result_mismatch wrong (out='$RUN_OUT' merges=$(merges))"
fi

# --- Condition 2 — self-resolved via live `gh pr view` (headRefOid/baseRefName) ---
J_MOVE_SHA='{"headRefOid":"def456","baseRefName":"main","statusCheckRollup":[{"name":"ci","conclusion":"SUCCESS"}]}'
printf '%s\n' "$J_MOVE_SHA" > "$GH_STUB_DIR/pr-view.json"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: head_sha_moved" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: live headRefOid != ctx ready_sha ⇒ PARK: head_sha_moved, no merge (never caller-asserted)"
else
  no "gate moved-sha wrong (out='$RUN_OUT' merges=$(merges))"
fi
reset_live

printf '{"headRefOid":"%s","baseRefName":"develop","statusCheckRollup":[{"name":"ci","conclusion":"SUCCESS"}]}\n' "$E_PR_HEAD" > "$GH_STUB_DIR/pr-view.json"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: base_not_main" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: live baseRefName != main ⇒ PARK: base_not_main, no merge"
else
  no "gate base-not-main wrong (out='$RUN_OUT' merges=$(merges))"
fi
reset_live

touch "$GH_STUB_DIR/pr-view-fail"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: head_sha_moved" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: gh pr view (headRefOid read) fails entirely ⇒ PARK: head_sha_moved, no merge"
else
  no "gate pr-view-fail wrong (out='$RUN_OUT' merges=$(merges))"
fi
reset_live

# --- Condition 3 — self-resolved via a SEPARATE `gh pr view --json reviewDecision` ---
printf '{"reviewDecision":"CHANGES_REQUESTED"}\n' > "$GH_STUB_DIR/pr-view-rd.json"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: review_decision_blocking" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: live reviewDecision CHANGES_REQUESTED ⇒ PARK, no merge"
else
  no "gate changes-requested wrong (out='$RUN_OUT' merges=$(merges))"
fi
printf '{"reviewDecision":"REVIEW_REQUIRED"}\n' > "$GH_STUB_DIR/pr-view-rd.json"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: review_decision_blocking" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: live reviewDecision REVIEW_REQUIRED ⇒ PARK, no merge"
else
  no "gate review-required wrong (out='$RUN_OUT' merges=$(merges))"
fi
touch "$GH_STUB_DIR/pr-view-rd-fail"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: review_decision_unreadable" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: gh pr view (reviewDecision read) fails ⇒ PARK: review_decision_unreadable (independently reachable — not masked by cond 2), no merge"
else
  no "gate review-decision-unreadable wrong (out='$RUN_OUT' merges=$(merges))"
fi
rm -f "$GH_STUB_DIR/pr-view-rd-fail"

# "none" reviewDecision (reviews-not-required — a successfully-read null) defers
# to cond 4 rather than parking here (the checks-only / --trust-unprotected
# reachability fix).
printf '{"reviewDecision":null}\n' > "$GH_STUB_DIR/pr-view-rd.json"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ]; then
  ok "gate: null (successfully-read) reviewDecision + enforceable checks-only protection ⇒ MERGE (cond 4 reachable)"
else
  no "gate none+protected wrong (out='$RUN_OUT' merges=$(merges))"
fi
printf '{"required_pull_request_reviews":{"required_approving_review_count":0},"required_status_checks":{"contexts":[]}}\n' > "$GH_STUB_DIR/protection.json"
gate "$(pass_ctx | jq '.trust_unprotected=true')"
if [ "$RUN_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ]; then
  ok "gate: null reviewDecision + unprotected + --trust-unprotected ⇒ MERGE (escape hatch reachable)"
else
  no "gate none+trust wrong (out='$RUN_OUT' merges=$(merges))"
fi
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: unprotected_branch" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: null reviewDecision + unprotected + no trust ⇒ PARK"
else
  no "gate none+unprotected-no-trust wrong (out='$RUN_OUT' merges=$(merges))"
fi
reset_live

# unresolved human/untrusted-actor thread (GraphQL, self-computed).
printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false},"nodes":[{"isResolved":false,"comments":{"nodes":[{"author":{"login":"someone","__typename":"User"}}]}}]}}}}}\n' > "$GH_STUB_DIR/graphql.json"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: unresolved_human_thread" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: unresolved thread whose actor is NOT in the trusted-actor set ⇒ PARK, no merge"
else
  no "gate human-thread wrong (out='$RUN_OUT' merges=$(merges))"
fi
# ...but an exact-listed trusted actor's unresolved thread does NOT block.
mkdir -p "$WD/trustedhome/.claude/loomwright"
printf '["someone"]\n' > "$WD/trustedhome/.claude/loomwright/trusted-actors.json"
rm -f "$GH_STUB_DIR/merge.log"
printf '%s' "$(pass_ctx)" > "$WD/ctx.json"
RUN_OUT="$( env PATH="$BIN:$PATH" GH_STUB_DIR="$GH_STUB_DIR" HOME="$WD/trustedhome" bash "$GWD/automate-helpers.sh" gate-eval "$PR" "$WD/ctx.json" --root "${E_GATE_ROOT:-$E_ROOT}" 2>/dev/null )"; RUN_RC=$?
if [ "$RUN_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ]; then
  ok "gate: unresolved thread whose actor IS exact-listed in the trusted-actor set ⇒ NOT blocking (MERGE)"
else
  no "gate trusted-actor wrong (out='$RUN_OUT' merges=$(merges))"
fi
reset_live
# hasNextPage truncation (>100 threads) fails CLOSED even with zero visible nodes.
printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":true},"nodes":[]}}}}}\n' > "$GH_STUB_DIR/graphql.json"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: unresolved_human_thread" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: reviewThreads hasNextPage=true (truncated >100) ⇒ PARK, no merge"
else
  no "gate truncated-threads wrong (out='$RUN_OUT' merges=$(merges))"
fi
reset_live
touch "$GH_STUB_DIR/graphql-fail"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: unresolved_human_thread" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: GraphQL review-threads read errors ⇒ PARK, no merge"
else
  no "gate graphql-fail wrong (out='$RUN_OUT' merges=$(merges))"
fi
reset_live

# --- Condition 4 — self-resolved via `gh api repos/.../branches/main/protection` ---
printf '{"required_pull_request_reviews":{"required_approving_review_count":0},"required_status_checks":{"contexts":[]}}\n' > "$GH_STUB_DIR/protection.json"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: unprotected_branch" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: toothless (no reviews, no checks) protection ⇒ PARK: unprotected_branch, no merge"
else
  no "gate unprotected wrong (out='$RUN_OUT' merges=$(merges))"
fi
gate "$(pass_ctx | jq '.trust_unprotected=true')"
if [ "$RUN_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ]; then
  ok "gate: --trust-unprotected overrides only the protection condition (MERGE)"
else
  no "trust-unprotected override wrong (out='$RUN_OUT' merges=$(merges))"
fi
reset_live
touch "$GH_STUB_DIR/protection-404"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: unprotected_branch" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: branches/main/protection 404 ⇒ unprotected (false), no trust ⇒ PARK, no merge"
else
  no "gate protection-404 wrong (out='$RUN_OUT' merges=$(merges))"
fi
reset_live
touch "$GH_STUB_DIR/protection-fail"
gate "$(pass_ctx | jq '.trust_unprotected=true')"
if [ "$RUN_OUT" = "PARK: protection_unreadable" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: a NON-404 protection read error ⇒ PARK: protection_unreadable, NEVER treated as either protected or unprotected (not even with --trust-unprotected)"
else
  no "gate protection-unreadable wrong (out='$RUN_OUT' merges=$(merges))"
fi
reset_live

# --- Condition 5 — checks (self-resolved from the SAME protection payload's
# required-context list, cross-referenced against statusCheckRollup) + rubric
# (now a FILE READ, never caller-asserted). ---
printf '{"headRefOid":"%s","baseRefName":"main","statusCheckRollup":[{"name":"ci","conclusion":"FAILURE"}]}\n' "$E_PR_HEAD" > "$GH_STUB_DIR/pr-view.json"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: checks_not_green" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: required check 'ci' not green ⇒ PARK, no merge"
else
  no "gate checks-not-green wrong (out='$RUN_OUT' merges=$(merges))"
fi
reset_live
gate "$(pass_ctx | jq --arg p "$SUP_OK" '.supervisor_result_path=$p')"
if [ "$RUN_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ]; then
  ok "gate: rubric_score N==M (parsed from the file itself) ⇒ MERGE"
else
  no "gate rubric-true wrong (out='$RUN_OUT' merges=$(merges))"
fi
gate "$(pass_ctx | jq --arg p "$SUP_BAD" '.supervisor_result_path=$p')"
if [ "$RUN_OUT" = "PARK: rubric_unsatisfied" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: rubric_score 6/7 (parsed from the file) ⇒ PARK: rubric_unsatisfied, no merge"
else
  no "gate rubric-false wrong (out='$RUN_OUT' merges=$(merges))"
fi
gate "$(pass_ctx | jq '.supervisor_result_path="/no/such/supervisor-result.md"')"
if [ "$RUN_OUT" = "PARK: supervisor_result_unreadable" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: unreadable supervisor_result_path ⇒ PARK: supervisor_result_unreadable, no merge"
else
  no "gate supervisor-result-unreadable wrong (out='$RUN_OUT' merges=$(merges))"
fi
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ]; then
  ok "gate: no rubric_score line in the file ⇒ 'na' (not a blocker) ⇒ MERGE"
else
  no "gate rubric-na wrong (out='$RUN_OUT' merges=$(merges))"
fi

# --- malformed ctx.json ---
gate 'this is not json {'
if [ "$RUN_OUT" = "PARK: ctx_unreadable" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: malformed ctx.json ⇒ PARK: ctx_unreadable, no merge"
else
  no "gate ctx-unreadable wrong (out='$RUN_OUT' merges=$(merges))"
fi

# --- Condition 6 — the gate ITSELF invokes classify-risk.sh; NO ctx input feeds
# this condition any more (that is exactly what the ctx-owned-key loop above
# already proved is refused). ---
printf '{"high_risk": true, "reasons": ["path: src/auth/x.ts matched *auth*","content: 2 changed line(s) matched *token*","size: changed_lines 512 > 400","path: skills/x/SKILL.md matched skills/"], "source":"classify-risk.sh"}\n' > "$GH_STUB_DIR/risk.json"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: high_risk_diff (path: src/auth/x.ts matched *auth*; content: 2 changed line(s) matched *token*; size: changed_lines 512 > 400)" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: gate-computed high_risk=true ⇒ PARK: high_risk_diff (first 3 reasons quoted), no merge"
else
  no "gate high-risk-true wrong (out='$RUN_OUT' merges=$(merges))"
fi
printf '{"high_risk": null, "reasons": ["unclassifiable: bad_ref"], "source":"classify-risk.sh"}\n' > "$GH_STUB_DIR/risk.json"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: high_risk_diff (unclassifiable: bad_ref)" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: gate-computed high_risk=null (unclassifiable) ⇒ PARK, no merge"
else
  no "gate high-risk-null wrong (out='$RUN_OUT' merges=$(merges))"
fi
printf '{"high_risk": "false", "reasons": [], "source":"classify-risk.sh"}\n' > "$GH_STUB_DIR/risk.json"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: high_risk_diff (no risk_reasons recorded)" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: JSON STRING \"false\" high_risk ⇒ PARK (boolean false only — no type erasure), no merge"
else
  no "gate string-false-high-risk FAILED OPEN (out='$RUN_OUT' merges=$(merges))"
fi
# --trust-unprotected is cond 4 ONLY — it must NOT override cond 6.
printf '{"required_pull_request_reviews":{"required_approving_review_count":0},"required_status_checks":{"contexts":[]}}\n' > "$GH_STUB_DIR/protection.json"
printf '{"high_risk": true, "reasons": ["path: billing/x.ts matched billing/**"], "source":"classify-risk.sh"}\n' > "$GH_STUB_DIR/risk.json"
gate "$(pass_ctx | jq '.trust_unprotected=true')"
if [ "$RUN_OUT" = "PARK: high_risk_diff (path: billing/x.ts matched billing/**)" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: trust_unprotected=true + gate-computed high_risk=true ⇒ PARK (the override is scoped to cond 4), no merge"
else
  no "gate trust-unprotected-vs-high-risk wrong (out='$RUN_OUT' merges=$(merges))"
fi
reset_live

# --- All-pass MERGE fires `gh pr merge --squash` EXACTLY once, and the stub
# call log shows classify-risk.sh, gh pr view, gh api branches/.../protection,
# and the GraphQL threads query were each ACTUALLY invoked (AC1). ---
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ] \
   && grep -q -- '--squash' "$GH_STUB_DIR/merge.log" \
   && grep -qF "$PR" "$GH_STUB_DIR/merge.log"; then
  ok "gate all-pass: MERGE fires 'gh pr merge --squash <url>' exactly once"
else
  no "gate all-pass wrong (out='$RUN_OUT' merges=$(merges) log='$(cat "$GH_STUB_DIR/merge.log" 2>/dev/null)')"
fi

# --- merge command itself fails ---
touch "$GH_STUB_DIR/merge-fail"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: merge_command_failed" ]; then
  ok "gate fail-closed: gh pr merge fails ⇒ PARK: merge_command_failed (no successful merge)"
else
  no "gate merge-command-failed wrong (out='$RUN_OUT' merges=$(merges))"
fi
rm -f "$GH_STUB_DIR/merge-fail"
reset_live

# --- BLOCKING mutation control (AC — "Mutation control … proves condition 6 is
# load-bearing, not asserted"). Comment out the classify-risk.sh invocation
# inside a COPY of gate_eval (mirrors the pre-existing cond-6-deletion mutant
# pattern) — the all-green case must NOT merge: with the call never made,
# risk_json stays empty ⇒ hr="__MISSING__" ⇒ PARK: high_risk_diff. This proves
# the all-green MERGE case genuinely depends on the classify-risk.sh call
# happening, not on any value the ctx happened to carry (it can't — cond 6 has
# no ctx input at all any more). ---
MUT="$(mktemp -d)"
sed 's/^\(  if \[ -r "\$risk_bin" \]; then\)$/  if false \&\& [ -r "$risk_bin" ]; then/' "$GWD/automate-helpers.sh" > "$MUT/automate-helpers.sh"
if [ -s "$MUT/automate-helpers.sh" ] && ! cmp -s "$GWD/automate-helpers.sh" "$MUT/automate-helpers.sh" && bash -n "$MUT/automate-helpers.sh" 2>/dev/null \
   && grep -q 'if false && \[ -r "\$risk_bin" \]; then' "$MUT/automate-helpers.sh"; then
  cp "$GWD/classify-risk.sh" "$MUT/classify-risk.sh"
  cp "$GWD/rules-gate-verdict.sh" "$MUT/rules-gate-verdict.sh"
  # Instrument the stub classify-risk.sh to prove (positively) whether it was called.
  printf '#!/usr/bin/env bash\necho called >> "%s/classify-risk-called.log"\necho '"'"'{"high_risk": false, "reasons": [], "source": "classify-risk.sh"}'"'"'\n' "$WD" > "$MUT/classify-risk.sh"
  chmod +x "$MUT/classify-risk.sh"
  rm -f "$WD/classify-risk-called.log"
  rm -f "$GH_STUB_DIR/merge.log"
  printf '%s' "$(pass_ctx)" > "$WD/ctx.json"
  MUT_OUT="$( env PATH="$BIN:$PATH" GH_STUB_DIR="$GH_STUB_DIR" HOME="$WD/nohome" bash "$MUT/automate-helpers.sh" gate-eval "$PR" "$WD/ctx.json" --root "${E_GATE_ROOT:-$E_ROOT}" 2>/dev/null )"
  if [ "$MUT_OUT" != "MERGE" ] && [ "$(merges)" -eq 0 ] && [ ! -f "$WD/classify-risk-called.log" ]; then
    ok "gate (mutant) classify-risk.sh invocation commented out ⇒ the all-green case does NOT merge, and the stub log proves classify-risk.sh was never called — condition 6 is genuinely load-bearing on the call happening"
  else
    no "gate cond-6 mutation control FAILED to discriminate (mutant out='$MUT_OUT' merges=$(merges) called_log=$([ -f "$WD/classify-risk-called.log" ] && echo yes || echo no)) — the all-green MERGE case must depend on the classify-risk.sh call, not survive its removal"
  fi
  # Positive control: the REAL (non-mutant) harness, given the SAME instrumented
  # classify-risk.sh, DOES call it (the log proves it) and DOES merge — showing
  # the mutant's failure above is caused by the DELETED invocation, not by the
  # instrumentation itself (the harness under test differs by exactly one line).
  CTRL="$(mktemp -d)"
  cp "$GWD/automate-helpers.sh" "$CTRL/automate-helpers.sh"
  cp "$MUT/classify-risk.sh" "$CTRL/classify-risk.sh"
  cp "$GWD/rules-gate-verdict.sh" "$CTRL/rules-gate-verdict.sh"
  rm -f "$WD/classify-risk-called.log" "$GH_STUB_DIR/merge.log"
  printf '%s' "$(pass_ctx)" > "$WD/ctx.json"
  CTRL_OUT="$( env PATH="$BIN:$PATH" GH_STUB_DIR="$GH_STUB_DIR" HOME="$WD/nohome" bash "$CTRL/automate-helpers.sh" gate-eval "$PR" "$WD/ctx.json" --root "${E_GATE_ROOT:-$E_ROOT}" 2>/dev/null )"
  if [ "$CTRL_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ] && [ -f "$WD/classify-risk-called.log" ]; then
    ok "gate (positive control) the SAME instrumented classify-risk.sh, on the UN-mutated gate, IS called and DOES merge — the mutant's non-merge above is caused by the deleted invocation, not the instrumentation"
  else
    no "gate cond-6 mutation control's positive control failed (out='$CTRL_OUT' merges=$(merges) called_log=$([ -f "$WD/classify-risk-called.log" ] && echo yes || echo no)) — cannot trust the mutation result without this"
  fi
  rm -rf "$CTRL"
else
  no "gate cond-6 mutation control not gated (mutant empty, identical to original, bash -n failed, or the invocation guard was not injected)"
fi
rm -rf "$MUT"

# =============================================================================
echo "== R. gate-eval condition 7 — rules gate (self-resolved via sibling rules-gate-verdict.sh; named PARK reasons; refused ctx keys; gated mutants) =="
# Section letter "R" (rules): "F" is already this file's learning-emit section.
# Reuses Section E's harness ($GWD gate copy + stub rules-gate-verdict.sh, gate(),
# pass_ctx, merges, reset_live). Every case runs on an otherwise ALL-GREEN PR
# (conditions 1–6 hold), so the ONLY variable is the verdict the stub returns.

# rules_fixture <verdict> <countable-json> <failing-json> <unresolved-json> [advisory-json]
# — write a well-formed verdict object (every field, the helper's own contract shape).
rules_fixture() {
  jq -nc --arg v "$1" --argjson c "$2" --argjson f "$3" --argjson u "$4" --argjson a "${5:-[]}" \
    '{verdict:$v, selected:(($c + ($a|map(.id))) | unique), countable:$c, advisory:$a,
      passed:[], failing:$f, unresolved:$u, checks_passed:null}' > "$GH_STUB_DIR/rules.json"
}
rules_called() { [ -f "$GH_STUB_DIR/rules-called.log" ]; }
# R_EXP_ROOT — the argv the gate must hand its sibling: `--root <the checkout gate() passed>`.
R_EXP_ROOT="--root $E_ROOT"

# R1 (AC1 gate half) — a stamped, countable, FAILING must-check ⇒ PARK: rules_check_failed (<id>).
reset_live
rules_fixture fail '["r-lint"]' '["r-lint"]' '[]'
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: rules_check_failed (r-lint)" ] && [ "$(merges)" -eq 0 ] \
   && rules_called && [ "$(cat "$GH_STUB_DIR/rules-called.log")" = "$R_EXP_ROOT" ]; then
  ok "R1 cond 7: verdict fail ⇒ PARK: rules_check_failed (r-lint), 0 merges, and the gate ITSELF called its sibling with '$R_EXP_ROOT'"
else
  no "R1 cond-7 fail wrong (out='$RUN_OUT' merges=$(merges) argv='$(cat "$GH_STUB_DIR/rules-called.log" 2>/dev/null)')"
fi

# R1b — ids: at most 3, "; "-joined, COUNTABLE only (a failing ADVISORY id never names a blocker).
reset_live
rules_fixture fail '["a","b","c","d"]' '["adv-x","a","b","c","d"]' '[]' '[{"id":"adv-x","reason":"binds_undeclared"}]'
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: rules_check_failed (a; b; c)" ] && [ "$(merges)" -eq 0 ]; then
  ok "R1b cond 7: fail reason names up to 3 COUNTABLE failing ids joined by '; ' (advisory adv-x excluded)"
else
  no "R1b cond-7 id list wrong (out='$RUN_OUT')"
fi

# R2 (AC2 gate half) — verdict ok ⇒ the condition holds ⇒ MERGE (1 merge).
reset_live
rules_fixture ok '["r-lint"]' '[]' '[]'
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ] && rules_called; then
  ok "R2 cond 7: verdict ok ⇒ MERGE (exactly 1 merge; the helper WAS consulted)"
else
  no "R2 cond-7 ok wrong (out='$RUN_OUT' merges=$(merges))"
fi

# R3 (AC10 gate half) — unresolved (a forged / truncated replay) ⇒ PARK: rules_check_unresolved (<ids>).
reset_live
rules_fixture unresolved '["r-lint","r-fmt"]' '[]' '["r-lint","r-fmt"]'
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: rules_check_unresolved (r-lint; r-fmt)" ] && [ "$(merges)" -eq 0 ]; then
  ok "R3 cond 7: verdict unresolved ⇒ PARK: rules_check_unresolved (r-lint; r-fmt), 0 merges"
else
  no "R3 cond-7 unresolved wrong (out='$RUN_OUT' merges=$(merges))"
fi

# R4 (AC3 / AC7 gate legs, D3 middle form) — unstamped WITH countable must-checks ⇒ PARK;
# the helper answers `none` when nothing is countable (all advisory, even one FAILING) ⇒ MERGE.
reset_live
rules_fixture unstamped '["r-lint","r-fmt"]' '[]' '[]'
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: rules_unstamped (2 countable must-check(s) never confirmed on this machine)" ] && [ "$(merges)" -eq 0 ]; then
  ok "R4 cond 7: unstamped with 2 countable ⇒ PARK: rules_unstamped (2 countable must-check(s) never confirmed on this machine)"
else
  no "R4 cond-7 unstamped wrong (out='$RUN_OUT' merges=$(merges))"
fi
reset_live
rules_fixture none '[]' '["r-lint"]' '[]' '[{"id":"r-lint","reason":"unbound:scripts/lint.sh"}]'
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ] && rules_called; then
  ok "R4b cond 7: verdict none (only advisory must-checks — here an unbound one that FAILS) ⇒ MERGE: nothing uncounted gates"
else
  no "R4b cond-7 none-with-advisory wrong (out='$RUN_OUT' merges=$(merges))"
fi
# R4c — unstamped by COUNTABLE-SET DRIFT with ZERO live countable ids (the last stamped,
# failing countable rule demoted away — test-rules-gate-verdict.sh (cs 4)) ⇒ PARK with the
# drift text, never the self-contradictory "0 countable must-check(s) never confirmed".
reset_live
rules_fixture unstamped '[]' '[]' '[]'
jq -c '. + {unstamped_reason: "countable_set_drift"}' "$GH_STUB_DIR/rules.json" > "$GH_STUB_DIR/rules.tmp" && mv "$GH_STUB_DIR/rules.tmp" "$GH_STUB_DIR/rules.json"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: rules_unstamped (countable rule set changed since the last /rules check --confirm on this machine)" ] && [ "$(merges)" -eq 0 ]; then
  ok "R4c cond 7: unstamped by countable-set drift with 0 live countable ⇒ PARK: rules_unstamped (countable rule set changed …), 0 merges"
else
  no "R4c cond-7 drift unstamped wrong (out='$RUN_OUT' merges=$(merges))"
fi
# R4d — unstamped by a LEGACY stamp ⇒ its own text; still 0 merges.
reset_live
rules_fixture unstamped '["r-lint"]' '[]' '[]'
jq -c '. + {unstamped_reason: "legacy_stamp"}' "$GH_STUB_DIR/rules.json" > "$GH_STUB_DIR/rules.tmp" && mv "$GH_STUB_DIR/rules.tmp" "$GH_STUB_DIR/rules.json"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: rules_unstamped (the stamp predates the recorded countable rule set; re-run /rules check --confirm on this machine)" ] && [ "$(merges)" -eq 0 ]; then
  ok "R4d cond 7: unstamped by a legacy stamp ⇒ PARK: rules_unstamped (the stamp predates …), 0 merges"
else
  no "R4d cond-7 legacy unstamped wrong (out='$RUN_OUT' merges=$(merges))"
fi
# R4e — an UNKNOWN / non-string unstamped_reason is message text only: it still PARKs
# (never-confirmed text), because the park is keyed on the verdict.
reset_live
rules_fixture unstamped '["r-lint"]' '[]' '[]'
jq -c '. + {unstamped_reason: {"x":1}}' "$GH_STUB_DIR/rules.json" > "$GH_STUB_DIR/rules.tmp" && mv "$GH_STUB_DIR/rules.tmp" "$GH_STUB_DIR/rules.json"
gate "$(pass_ctx)"
R4E_A="$RUN_OUT"; R4E_MA="$(merges)"
reset_live
rules_fixture unstamped '["r-lint"]' '[]' '[]'
jq -c '. + {unstamped_reason: "something_new"}' "$GH_STUB_DIR/rules.json" > "$GH_STUB_DIR/rules.tmp" && mv "$GH_STUB_DIR/rules.tmp" "$GH_STUB_DIR/rules.json"
gate "$(pass_ctx)"
R4E_EXP="PARK: rules_unstamped (1 countable must-check(s) never confirmed on this machine)"
if [ "$R4E_A" = "$R4E_EXP" ] && [ "$R4E_MA" -eq 0 ] && [ "$RUN_OUT" = "$R4E_EXP" ] && [ "$(merges)" -eq 0 ]; then
  ok "R4e cond 7: a non-string or unknown unstamped_reason still PARKs rules_unstamped (never-confirmed text), 0 merges"
else
  no "R4e cond-7 unknown reason wrong (a='$R4E_A'/$R4E_MA b='$RUN_OUT'/$(merges))"
fi

# R5 (AC4 gate leg) — cmd_disabled ⇒ PARK: rules_cmd_disabled (the gate cannot verify).
reset_live
rules_fixture cmd_disabled '["r-lint"]' '[]' '[]'
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: rules_cmd_disabled" ] && [ "$(merges)" -eq 0 ]; then
  ok "R5 cond 7: verdict cmd_disabled ⇒ PARK: rules_cmd_disabled, 0 merges"
else
  no "R5 cond-7 cmd_disabled wrong (out='$RUN_OUT' merges=$(merges))"
fi

# R6 — every unreadable shape fails CLOSED on ONE named reason: rules_gate_unreadable.
r6_case() {  # r6_case <label> <rules.json body or __NONE__> [exit-code]
  reset_live
  if [ "$2" = "__NONE__" ]; then rm -f "$GH_STUB_DIR/rules.json"; else printf '%s\n' "$2" > "$GH_STUB_DIR/rules.json"; fi
  [ -n "${3:-}" ] && printf '%s' "$3" > "$GH_STUB_DIR/rules-exit"
  gate "$(pass_ctx)"
  if [ "$RUN_OUT" = "PARK: rules_gate_unreadable" ] && [ "$(merges)" -eq 0 ]; then
    ok "R6 cond 7 fail-closed: $1 ⇒ PARK: rules_gate_unreadable, 0 merges"
  else
    no "R6 cond-7 $1 FAILED OPEN or misnamed (out='$RUN_OUT' merges=$(merges))"
  fi
}
r6_case "verdict unreadable"            '{"verdict":"unreadable","selected":[],"countable":[],"advisory":[],"passed":[],"failing":[],"unresolved":[],"checks_passed":null}'
r6_case "non-JSON helper output"        'Checks passed: 1/1'
r6_case "empty helper output"           '__NONE__'
r6_case "JSON that is not an object"    '["ok"]'
r6_case "missing .verdict"              '{"selected":[],"countable":[]}'
r6_case "non-string .verdict (true)"    '{"verdict":true}'
r6_case "null .verdict"                 '{"verdict":null}'
r6_case "unrecognised verdict string"   '{"verdict":"OK"}'
r6_case "non-zero helper exit with an ok body" '{"verdict":"ok","selected":[],"countable":[],"advisory":[],"passed":[],"failing":[],"unresolved":[],"checks_passed":null}' 3
# Helper ABSENT beside the gate — moved away, then restored.
reset_live
mv "$GWD/rules-gate-verdict.sh" "$WD/rules-gate-verdict.sh.away"
gate "$(pass_ctx)"
mv "$WD/rules-gate-verdict.sh.away" "$GWD/rules-gate-verdict.sh"
if [ "$RUN_OUT" = "PARK: rules_gate_unreadable" ] && [ "$(merges)" -eq 0 ]; then
  ok "R6 cond 7 fail-closed: sibling rules-gate-verdict.sh ABSENT ⇒ PARK: rules_gate_unreadable, 0 merges"
else
  no "R6 cond-7 helper-absent FAILED OPEN (out='$RUN_OUT' merges=$(merges))"
fi

# R7 (AC5) — the three new gate-owned ctx keys are REFUSED before anything runs; the
# rules helper is NEVER called (call-log) — even a value asserting a pass cannot help.
for K in rules_gate rules_ok rules_check; do
  for V in 'true' '"ok"' 'false'; do
    reset_live
    rules_fixture ok '["r-lint"]' '[]' '[]'
    gate "$(pass_ctx | jq --arg k "$K" --argjson v "$V" '.[$k]=$v')"
    if [ "$RUN_OUT" = "PARK: ctx_carries_gate_owned_key" ] && [ "$(merges)" -eq 0 ] && ! rules_called; then
      ok "R7 refuses ctx key '$K'=$V ⇒ PARK: ctx_carries_gate_owned_key, 0 merges, helper never called"
    else
      no "R7 ctx key '$K'=$V NOT refused (out='$RUN_OUT' merges=$(merges) called=$(rules_called && echo yes || echo no))"
    fi
  done
done

# R8 — precedence: cond 7 is evaluated AFTER cond 6 (a high-risk diff parks on its own
# reason and the rules helper is never even called).
reset_live
printf '{"high_risk": true, "reasons": ["path: billing/x.ts matched billing/**"], "source":"classify-risk.sh"}\n' > "$GH_STUB_DIR/risk.json"
rules_fixture fail '["r-lint"]' '["r-lint"]' '[]'
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: high_risk_diff (path: billing/x.ts matched billing/**)" ] && [ "$(merges)" -eq 0 ] && ! rules_called; then
  ok "R8 precedence: cond 6 PARK wins over a failing cond 7, and cond 7's helper is not called (evaluated after cond 6)"
else
  no "R8 cond-6/7 precedence wrong (out='$RUN_OUT' called=$(rules_called && echo yes || echo no))"
fi

# R9 (AC9(b)) — GATED mutation controls. Each mutant is a sed COPY of the gate, trusted only
# if non-empty, differs from the original, passes `bash -n`, and carries the injected marker.
# (i) the cond-7 PARK test disabled (the condition deleted) ⇒ the AC1 failing case prints MERGE.
# (ii) ONLY the helper invocation commented out ⇒ the AC1 failing case does NOT merge — it
#      fails CLOSED on rules_gate_unreadable (removing the call can never open the gate) —
#      and the instrumented call log proves the helper was never called.
# Positive control: the UN-mutated gate copy, same stubs, calls the helper on the all-green
# path (log proves it, MERGE) and PARKs the failing case on rules_check_failed.
r9_run() {  # r9_run <dir> — gate-eval from <dir>'s copy; sets R9_OUT
  rm -f "$GH_STUB_DIR/merge.log" "$GH_STUB_DIR/rules-called.log"
  printf '%s' "$(pass_ctx)" > "$WD/ctx.json"
  R9_OUT="$( env PATH="$BIN:$PATH" GH_STUB_DIR="$GH_STUB_DIR" HOME="$WD/nohome" bash "$1/automate-helpers.sh" gate-eval "$PR" "$WD/ctx.json" --root "${E_GATE_ROOT:-$E_ROOT}" 2>/dev/null )"
}
r9_dir() {  # r9_dir <sed-expr> <marker-regex> — prints a gated mutant dir, or nothing
  local d; d="$(mktemp -d)"
  sed "$1" "$GWD/automate-helpers.sh" > "$d/automate-helpers.sh"
  if [ -s "$d/automate-helpers.sh" ] && ! cmp -s "$GWD/automate-helpers.sh" "$d/automate-helpers.sh" \
     && bash -n "$d/automate-helpers.sh" 2>/dev/null && grep -q "$2" "$d/automate-helpers.sh"; then
    cp "$GWD/classify-risk.sh" "$GWD/rules-gate-verdict.sh" "$d/"
    printf '%s' "$d"
  else
    rm -rf "$d"
  fi
}
reset_live
M_PARK="$(r9_dir 's/^\(  if \[ "\$rules_ok" != "true" \]; then\)$/  if false \&\& [ "$rules_ok" != "true" ]; then/' 'if false && \[ "\$rules_ok" != "true" \]; then')"
M_CALL="$(r9_dir 's/^\(  if \[ -r "\$rules_bin" \]; then\)$/  if false \&\& [ -r "$rules_bin" ]; then/' 'if false && \[ -r "\$rules_bin" \]; then')"
if [ -n "$M_PARK" ] && [ -n "$M_CALL" ]; then
  rules_fixture fail '["r-lint"]' '["r-lint"]' '[]'
  r9_run "$M_PARK"
  if [ "$R9_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ]; then
    ok "R9 (mutant i) cond-7 PARK test deleted ⇒ the AC1 failing-check case prints MERGE — condition 7 is what parks it"
  else
    no "R9 mutant (i) did NOT flip the failing case to MERGE (out='$R9_OUT' merges=$(merges)) — the cond-7 PARK is not load-bearing"
  fi
  r9_run "$M_CALL"
  if [ "$R9_OUT" = "PARK: rules_gate_unreadable" ] && [ "$(merges)" -eq 0 ] && [ ! -f "$GH_STUB_DIR/rules-called.log" ]; then
    ok "R9 (mutant ii) invocation commented out ⇒ helper never called (log absent) and the failing case parks rules_gate_unreadable, not rules_check_failed — fail CLOSED, never MERGE"
  else
    no "R9 mutant (ii) wrong (out='$R9_OUT' merges=$(merges) called=$([ -f "$GH_STUB_DIR/rules-called.log" ] && echo yes || echo no))"
  fi
  # Positive control on the UN-mutated copy.
  CTRL="$(mktemp -d)"; cp "$GWD/automate-helpers.sh" "$GWD/classify-risk.sh" "$GWD/rules-gate-verdict.sh" "$CTRL/"
  r9_run "$CTRL"
  R9_FAIL_OUT="$R9_OUT"; R9_FAIL_MERGES="$(merges)"
  rules_fixture ok '["r-lint"]' '[]' '[]'
  r9_run "$CTRL"
  if [ "$R9_FAIL_OUT" = "PARK: rules_check_failed (r-lint)" ] && [ "$R9_FAIL_MERGES" -eq 0 ] \
     && [ "$R9_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ] && [ -f "$GH_STUB_DIR/rules-called.log" ]; then
    ok "R9 (positive control) the UN-mutated gate PARKs the failing case on rules_check_failed and, on the all-green path, DOES call the helper (log) and MERGE — the mutants' outcomes are caused by their one-line edits"
  else
    no "R9 positive control failed (fail-case='$R9_FAIL_OUT'/$R9_FAIL_MERGES green='$R9_OUT'/$(merges)) — cannot trust the mutation results without it"
  fi
  rm -rf "$CTRL"
else
  no "R9 cond-7 mutation controls not gated (a mutant was empty, identical to the original, failed bash -n, or lacked its injected marker)"
fi
rm -rf "${M_PARK:-/nonexistent-r9}" "${M_CALL:-/nonexistent-r9}"

# R10 — END-TO-END against the REAL siblings (rules-gate-verdict.sh + rules-check.sh +
# rules-replay-lib.sh beside the gate copy; only gh and classify-risk.sh stubbed): a real
# fixture store stamped by a genuine `rules-check.sh --confirm` in a sandboxed HOME.
# A countable (binds: []) FAILING must-check ⇒ PARK: rules_check_failed (<id>); the same
# store with the check PASSING ⇒ MERGE. Proves the stub's JSON shape is the real one.
TAB_CHAR="$(printf '\t')"
reset_live
rm -f "$GH_STUB_DIR/rules.json"
IWD="$(mktemp -d)"; IWD="$(cd "$IWD" && pwd -P)"
cp "$GWD/automate-helpers.sh" "$GWD/classify-risk.sh" "$IWD/"
cp "$HERE/rules-gate-verdict.sh" "$HERE/rules-check.sh" "$HERE/rules-replay-lib.sh" "$IWD/"
r10_store() {  # r10_store <name> <check> — a committed temp repo + stamped store; prints "<repo>\t<home>"
  local r="$IWD/$1" h="$IWD/home-$1"
  mkdir -p "$r/.agent/rules" "$h"
  jq -cn --arg id "e2e-$1" --arg c "$2" \
    '[{id:$id, category:"test", statement:("s " + $id), enforcement:"must", check:$c, binds:[], provenance:{source:"test"}}]' \
    > "$r/.agent/rules/r.json"
  # The store is COMMITTED with `f` (automate-followups/16): an untracked store would leave the
  # checkout dirty and park every leg rules_gate_dirty_tree before the real helper ever ran.
  # `--confirm` runs AFTER the commit, on the committed bytes (the stamp lives in HOME).
  ( cd "$r" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false \
      && echo init > f && git add f .agent && git commit -qm init ) >/dev/null 2>&1
  ( cd "$r" && env -u RULES_CHECK_NO_CMD -u RULES_CHECK_STAMP_FILE HOME="$h" bash "$IWD/rules-check.sh" --confirm </dev/null >/dev/null 2>&1 )
  printf '%s\t%s' "$r" "$h"
}
r10_gate() {  # r10_gate <repo> <home> [<pr-head>] — sets R10_OUT; the stubbed live head (and ctx ready_sha)
  # is <pr-head>, defaulting to <repo>'s OWN real HEAD so the cond-7 pin sees an at-head checkout.
  local ph; ph="${3:-$(git -C "$1" rev-parse HEAD 2>/dev/null)}"
  rm -f "$GH_STUB_DIR/merge.log"
  printf '{"headRefOid":"%s","baseRefName":"main","statusCheckRollup":[{"name":"ci","conclusion":"SUCCESS"}]}\n' "$ph" > "$GH_STUB_DIR/pr-view.json"
  printf '%s' "$(pass_ctx | jq --arg s "$ph" '.ready_sha=$s')" > "$WD/ctx.json"
  R10_OUT="$( cd "$1" && env -u RULES_CHECK_NO_CMD -u RULES_CHECK_STAMP_FILE PATH="$BIN:$PATH" GH_STUB_DIR="$GH_STUB_DIR" HOME="$2" bash "$IWD/automate-helpers.sh" gate-eval "$PR" "$WD/ctx.json" --root "$1" 2>/dev/null )"
}
IFS="$TAB_CHAR" read -r R10_REPO R10_HOME <<R10A
$(r10_store fails false)
R10A
r10_gate "$R10_REPO" "$R10_HOME"
if [ "$R10_OUT" = "PARK: rules_check_failed (e2e-fails)" ] && [ "$(merges)" -eq 0 ]; then
  ok "R10 end-to-end (real siblings): stamped countable FAILING must-check ⇒ PARK: rules_check_failed (e2e-fails), 0 merges"
else
  no "R10 end-to-end failing case wrong (out='$R10_OUT' merges=$(merges))"
fi
IFS="$TAB_CHAR" read -r R10_REPO R10_HOME <<R10B
$(r10_store passes true)
R10B
r10_gate "$R10_REPO" "$R10_HOME"
if [ "$R10_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ]; then
  ok "R10 end-to-end (real siblings): the same store shape with the check PASSING ⇒ MERGE (1 merge)"
else
  no "R10 end-to-end passing case wrong (out='$R10_OUT' merges=$(merges))"
fi
# R10 stale-HEAD leg (automate-followups/16) — the SAME passing store, real siblings, but the live
# PR head is a real child commit the checkout is NOT on ⇒ the pin parks before the real helper
# runs, even though that helper would have answered `ok` (the leg just above MERGEd on it).
R10_TIP="$(git -C "$R10_REPO" commit-tree "HEAD^{tree}" -p HEAD -m tip 2>/dev/null)" || R10_TIP=""
r10_gate "$R10_REPO" "$R10_HOME" "$R10_TIP"
if [ -n "$R10_TIP" ] && [ "$R10_OUT" = "PARK: rules_gate_head_mismatch" ] && [ "$(merges)" -eq 0 ]; then
  ok "R10 end-to-end (real siblings): the passing store, but the live PR head is a commit the checkout is not on ⇒ PARK: rules_gate_head_mismatch, 0 merges"
else
  no "R10 end-to-end stale-HEAD leg wrong (tip='$R10_TIP' out='$R10_OUT' merges=$(merges))"
fi
rm -rf "$IWD"
reset_live

# R11 (automate-followups/16) — cond 7's CHECKOUT PIN, evaluated BEFORE the rules helper:
# `--root` must be AT the live head cond 2 confirmed (else rules_gate_head_mismatch) and clean
# outside .supervisor/ and $E_MEM (else rules_gate_dirty_tree). Every PARK leg
# runs with the stub verdict `ok`, so the ONLY thing standing between it and a MERGE is the pin;
# every leg also asserts the helper was NOT called (the pin runs first). Each leg restores the
# checkout and r11_restored proves it, so no leg leaks dirt into the next.
r11_restored() {  # r11_restored <label> — the shared checkout is back at E_HEAD and clean
  if [ "$(git -C "$E_ROOT" rev-parse HEAD 2>/dev/null)" != "$E_HEAD" ] \
     || [ -n "$(git -C "$E_ROOT" status --porcelain -uall --ignored 2>/dev/null)" ]; then
    no "R11 $1: the shared checkout was NOT restored (head/dirt leaked) — later cases are untrustworthy"
  fi
}
r11_park() {  # r11_park <label> <expected-reason> — assert PARK <reason>, 0 merges, helper never called
  if [ "$RUN_OUT" = "PARK: $2" ] && [ "$(merges)" -eq 0 ] && ! rules_called; then
    ok "R11 $1 ⇒ PARK: $2, 0 merges, rules helper never called"
  else
    no "R11 $1 wrong (out='$RUN_OUT' merges=$(merges) called=$(rules_called && echo yes || echo no))"
  fi
}
r11_decides() {  # r11_decides <label> — the verdict still decides: fail ⇒ rules_check_failed, ok ⇒ MERGE
  reset_live; rules_fixture fail '["r-lint"]' '["r-lint"]' '[]'; gate "$(pass_ctx)"
  local fo="$RUN_OUT" fm; fm="$(merges)"
  local fargv; fargv="$(cat "$GH_STUB_DIR/rules-called.log" 2>/dev/null)"
  reset_live; rules_fixture ok '["r-lint"]' '[]' '[]'; gate "$(pass_ctx)"
  if [ "$fo" = "PARK: rules_check_failed (r-lint)" ] && [ "$fm" -eq 0 ] \
     && [ "$fargv" = "--root ${E_GATE_ROOT:-$E_ROOT}" ] \
     && [ "$RUN_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ] && rules_called; then
    ok "R11 $1 ⇒ pin passes and the verdict decides (fail ⇒ rules_check_failed, ok ⇒ MERGE; helper called with --root unchanged)"
  else
    no "R11 $1 wrong (fail-case='$fo'/$fm argv='$fargv' ok-case='$RUN_OUT'/$(merges))"
  fi
}

# R11a (AC1) — stale HEAD: the live PR head (and ready_sha, so cond 2 holds) is E_TIP, a real
# commit the checkout is not on.
E_PR_HEAD="$E_TIP"; reset_live; rules_fixture ok '["r-lint"]' '[]' '[]'
gate "$(pass_ctx)"
r11_park "stale HEAD (checkout at E_HEAD, live PR head E_TIP)" rules_gate_head_mismatch
# Control — the SAME stubs with the checkout moved ONTO E_TIP ⇒ MERGE: HEAD is the only variable.
git -C "$E_ROOT" checkout -q --detach "$E_TIP" >/dev/null 2>&1
rm -f "$GH_STUB_DIR/rules-called.log"; gate "$(pass_ctx)"
if [ "$RUN_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ] && rules_called; then
  ok "R11a control: the same stubs with the checkout AT the PR head ⇒ MERGE (HEAD is the only variable)"
else
  no "R11a control wrong (out='$RUN_OUT' merges=$(merges))"
fi
git -C "$E_ROOT" checkout -q - >/dev/null 2>&1
E_PR_HEAD="$E_HEAD"; reset_live
r11_restored "R11a"

# R11a' — cond 6 still takes precedence over the pin (a high-risk, stale-HEAD PR parks high_risk_diff).
E_PR_HEAD="$E_TIP"; reset_live; rules_fixture ok '["r-lint"]' '[]' '[]'
printf '{"high_risk": true, "reasons": ["path: billing/x.ts matched billing/**"], "source":"classify-risk.sh"}\n' > "$GH_STUB_DIR/risk.json"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: high_risk_diff (path: billing/x.ts matched billing/**)" ] && [ "$(merges)" -eq 0 ] && ! rules_called; then
  ok "R11a' precedence: cond 6 PARK wins over a stale-HEAD cond 7 pin"
else
  no "R11a' cond-6-over-pin precedence wrong (out='$RUN_OUT')"
fi
E_PR_HEAD="$E_HEAD"; reset_live

# R11b (AC2) — an unreadable HEAD fails CLOSED, never a match: not a checkout, a repo with no
# commit, a path that does not exist.
mkdir -p "$WD/nogit"
( cd "$WD" && git init -q emptyrepo ) >/dev/null 2>&1
for R11_ROOT in "$WD/nogit" "$WD/emptyrepo" "$WD/does-not-exist"; do
  reset_live; rules_fixture ok '["r-lint"]' '[]' '[]'
  E_GATE_ROOT="$R11_ROOT"; gate "$(pass_ctx)"; E_GATE_ROOT=""
  r11_park "unreadable HEAD (--root ${R11_ROOT#$WD/})" rules_gate_head_mismatch
done

# R11c (AC3) — dirt outside the engine-owned paths ⇒ rules_gate_dirty_tree. Each case: dirty, gate, undo.
r11_dirty() {  # r11_dirty <label> — run the gate on the (already dirtied) checkout, assert the dirty PARK
  reset_live; rules_fixture ok '["r-lint"]' '[]' '[]'
  gate "$(pass_ctx)"
  r11_park "$1" rules_gate_dirty_tree
}
echo more >> "$E_ROOT/sub/a"
r11_dirty "tracked modification (sub/a)"
git -C "$E_ROOT" checkout -q -- sub/a; r11_restored "tracked modification"
rm "$E_ROOT/sub/a"
r11_dirty "tracked deletion (sub/a)"
git -C "$E_ROOT" checkout -q -- sub/a; r11_restored "tracked deletion"
echo s > "$E_ROOT/staged.txt"; git -C "$E_ROOT" add staged.txt
r11_dirty "staged new file"
git -C "$E_ROOT" rm -q --cached staged.txt >/dev/null 2>&1; rm -f "$E_ROOT/staged.txt"; r11_restored "staged new file"
echo u > "$E_ROOT/untracked.txt"
r11_dirty "untracked non-ignored file at the top level"
git -C "$E_ROOT" config status.showUntrackedFiles no
r11_dirty "untracked file under the repo's status.showUntrackedFiles=no (the pin's -uall overrides it)"
git -C "$E_ROOT" config --unset status.showUntrackedFiles; rm -f "$E_ROOT/untracked.txt"; r11_restored "untracked file"
E_MEM_SIB="$E_ROOT/$(dirname "$E_MEM")/other"   # a sibling of the agent-memory dir, same parent
mkdir -p "$E_MEM_SIB"; echo o > "$E_MEM_SIB/o.md"
r11_dirty "untracked file beside, but OUTSIDE, $E_MEM"
rm -rf "$E_MEM_SIB"; r11_restored "agent-memory sibling"
mkdir -p "$E_ROOT/sub/.supervisor"; echo n > "$E_ROOT/sub/.supervisor/n.md"
r11_dirty "a NESTED sub/.supervisor/ file (the exclusion is anchored at the repo top level)"
rm -rf "$E_ROOT/sub/.supervisor"; r11_restored "nested .supervisor"
# Subdirectory --root: dirt elsewhere in the repo is still seen (the porcelain read is whole-repo).
echo u > "$E_ROOT/top.txt"
E_GATE_ROOT="$E_ROOT/sub"; r11_dirty "subdirectory --root (sub/) with an untracked file at the repo top level"; E_GATE_ROOT=""
rm -f "$E_ROOT/top.txt"; r11_restored "subdirectory root"
# A FAILING `git status` (corrupt index; `rev-parse HEAD` still reads fine) parks the same way.
cp "$E_ROOT/.git/index" "$WD/index.bak"; printf 'garbage' > "$E_ROOT/.git/index"
r11_dirty "git status fails (corrupt index)"
cp "$WD/index.bak" "$E_ROOT/.git/index"; r11_restored "corrupt index"

# R11d (AC4) — dirt ONLY under the engine-owned paths (tracked edits AND new untracked files)
# or only gitignored ⇒ the pin passes and the verdict decides exactly as today.
echo y >> "$E_ROOT/.supervisor/automate/run.md"; echo '{}' > "$E_ROOT/.supervisor/automate/run.sidecar.json"
r11_decides ".supervisor/-only dirt (tracked run-file edit + untracked sidecar)"
E_GATE_ROOT="$E_ROOT/sub"; r11_decides ".supervisor/-only dirt with a SUBDIRECTORY --root (exclusion still anchored at the top)"; E_GATE_ROOT=""
git -C "$E_ROOT" checkout -q -- .supervisor; rm -f "$E_ROOT/.supervisor/automate/run.sidecar.json"; r11_restored ".supervisor dirt"
echo y >> "$E_ROOT/$E_MEM/loomwright:code-reviewer/MEMORY.md"
mkdir -p "$E_ROOT/$E_MEM/loomwright:qa-executor"; echo n > "$E_ROOT/$E_MEM/loomwright:qa-executor/MEMORY.md"
r11_decides "$E_MEM-only dirt (tracked memory edit + untracked new agent dir)"
git -C "$E_ROOT" checkout -q -- "$E_MEM"; rm -rf "$E_ROOT/$E_MEM/loomwright:qa-executor"; r11_restored "agent-memory dirt"
echo i > "$E_ROOT/ignored.log"
r11_decides "gitignored-only file"
rm -f "$E_ROOT/ignored.log"; r11_restored "ignored file"

# R11f (review iteration 1) — LOCAL-ONLY git state must not hide dirt from the pin. Each
# leg below is invisible to a plain `git status --porcelain -uall` (the pre-fix pin MERGEd
# every one), so each parks only because of the reads the fix added.
r11_env_on() { export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.fileMode GIT_CONFIG_VALUE_0=false; }
r11_env_off() { unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0; }
for R11_FLAG in assume-unchanged skip-worktree; do
  git -C "$E_ROOT" update-index --"$R11_FLAG" sub/a
  r11_dirty "tracked file flagged $R11_FLAG, unedited (any hiding flag parks)"
  echo more >> "$E_ROOT/sub/a"
  if [ -z "$(git -C "$E_ROOT" status --porcelain -uall 2>/dev/null)" ]; then
    r11_dirty "tracked edit hidden from git status by $R11_FLAG"
  else
    no "R11f $R11_FLAG: git status still shows the edit — the leg does not exercise the hiding flag"
  fi
  git -C "$E_ROOT" update-index --no-"$R11_FLAG" sub/a; git -C "$E_ROOT" checkout -q -- sub/a
  r11_restored "$R11_FLAG"
done
cp "$E_ROOT/.git/info/exclude" "$WD/exclude.bak" 2>/dev/null || : > "$WD/exclude.bak"
echo hid.txt >> "$E_ROOT/.git/info/exclude"; echo h > "$E_ROOT/hid.txt"
r11_dirty "untracked file hidden by .git/info/exclude"
cp "$WD/exclude.bak" "$E_ROOT/.git/info/exclude"; rm -f "$E_ROOT/hid.txt"; r11_restored "info/exclude"
echo hid.txt > "$WD/xfile"; git -C "$E_ROOT" config core.excludesFile "$WD/xfile"; echo h > "$E_ROOT/hid.txt"
r11_dirty "untracked file hidden by the repo's core.excludesFile"
git -C "$E_ROOT" config --unset core.excludesFile; rm -f "$E_ROOT/hid.txt"; r11_restored "core.excludesFile"
mkdir -p "$E_ROOT/evil"; echo '*' > "$E_ROOT/evil/.gitignore"; echo e > "$E_ROOT/evil/f"
# The park reads `evil/.gitignore` out of `ls-files -o -i --directory`; it relies on git
# LISTING the contents of a directory no rule ignores (observed on git 2.54/2.55) rather than
# collapsing it to `evil/`. Assert that assumption on the harness git, so a git that collapses
# turns this red with a named cause instead of a bare wrong-outcome leg.
if grep -qx 'evil/\.gitignore' <<<"$(git -C "$E_ROOT" ls-files -o -i --directory --exclude-per-directory=.gitignore 2>/dev/null)"; then
  ok "R11f precondition: this git lists evil/.gitignore under ls-files -o -i --directory (no collapse to evil/)"
else
  no "R11f precondition: this git ($(git --version 2>/dev/null)) collapses the self-ignoring directory — the untracked-.gitignore park cannot see it"
fi
r11_dirty "self-ignoring untracked evil/.gitignore hiding its whole directory"
rm -rf "$E_ROOT/evil"; r11_restored "self-ignoring .gitignore"
chmod +x "$E_ROOT/sub/a"; r11_env_on
r11_dirty "mode change hidden by env-injected core.fileMode=false (GIT_CONFIG_COUNT)"
r11_env_off; chmod -x "$E_ROOT/sub/a"; r11_restored "env-injected config"
E_GATE_ROOT="$E_ROOT/.git"; r11_dirty "--root inside .git/ at the live head (rev-parse --show-toplevel fails)"; E_GATE_ROOT=""
# Control: an untracked .gitignore inside a COMMITTED-ignored directory (node_modules/-style)
# is never read by git, so it is not dirt — the verdict still decides.
mkdir -p "$E_ROOT/ignored-dir/pkg"; echo '*' > "$E_ROOT/ignored-dir/pkg/.gitignore"; echo z > "$E_ROOT/ignored-dir/pkg/z"
r11_decides "untracked .gitignore nested in a committed-ignored directory"
rm -rf "$E_ROOT/ignored-dir"; r11_restored "ignored-dir"

# R11h (review iteration 2) — LIVENESS: the USER's global excludes file is honoured, so an
# at-head, otherwise-clean checkout holding a globally-only-ignored file (.DS_Store, .idea/,
# settings.local.json) still lets the verdict decide. Precondition first: with no global
# ignore the same file IS dirt (so each MERGE below is caused by the global file, nothing else).
# Relocated XDG_CONFIG_HOME / HOME fixtures only; the real user config is never read.
R11_XDG="$WD/xdg"; mkdir -p "$R11_XDG/git" "$WD/nohome/.config/git"
r11_gfix() { echo n > "$E_ROOT/notes.local"; mkdir -p "$E_ROOT/.idea"; echo i > "$E_ROOT/.idea/ws.xml"; }
r11_gundo() { rm -rf "$E_ROOT/notes.local" "$E_ROOT/.idea"; }
r11_gfix
r11_dirty "globally-ignorable files with NO global ignore configured (precondition: they are dirt)"
printf 'notes.local\n.idea/\n' > "$R11_XDG/git/ignore"; export XDG_CONFIG_HOME="$R11_XDG"
r11_decides "untracked files ignored only by \$XDG_CONFIG_HOME/git/ignore (user global ignore)"
unset XDG_CONFIG_HOME; rm -f "$R11_XDG/git/ignore"
printf 'notes.local\n.idea/\n' > "$WD/nohome/.config/git/ignore"
r11_decides "untracked files ignored only by \$HOME/.config/git/ignore (XDG unset fallback)"
rm -f "$WD/nohome/.config/git/ignore"
printf 'notes.local\n.idea/\n' > "$WD/gx-ignore"
printf '[core]\n\texcludesFile = %s\n' "$WD/gx-ignore" > "$WD/nohome/.gitconfig"
r11_decides "untracked files ignored only by core.excludesFile in the user's ~/.gitconfig"
# A RELATIVE global excludesFile would resolve against the checkout (repo bytes as ignore source).
mkdir -p "$E_ROOT/ignored-dir"; cp "$WD/gx-ignore" "$E_ROOT/ignored-dir/gx"
printf '[core]\n\texcludesFile = ignored-dir/gx\n' > "$WD/nohome/.gitconfig"
r11_dirty "global core.excludesFile given as a RELATIVE path (resolves into the checkout) is not honoured"
printf '[core]\n\texcludesFile = %s\n' "$E_ROOT/ignored-dir/gx" > "$WD/nohome/.gitconfig"
r11_dirty "global core.excludesFile pointing INSIDE the checkout (a committed-ignored file) is not honoured"
rm -f "$WD/nohome/.gitconfig"; rm -rf "$E_ROOT/ignored-dir"
# Env-injected excludesFile stays refused: GIT_CONFIG_COUNT and GIT_CONFIG_GLOBAL both unset by _ge_git.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.excludesFile GIT_CONFIG_VALUE_0="$WD/gx-ignore"
r11_dirty "env-injected core.excludesFile (GIT_CONFIG_COUNT) is not honoured"
r11_env_off
printf '[core]\n\texcludesFile = %s\n' "$WD/gx-ignore" > "$WD/gcfg-injected"
export GIT_CONFIG_GLOBAL="$WD/gcfg-injected"
r11_dirty "env-injected global config (GIT_CONFIG_GLOBAL) naming an excludesFile is not honoured"
unset GIT_CONFIG_GLOBAL
r11_gundo; rm -f "$WD/gcfg-injected"; r11_restored "global ignore legs"
# info/exclude stays refused even WITH a global ignore configured (only the user-scope file is read).
printf 'unrelated\n' > "$R11_XDG/git/ignore"; export XDG_CONFIG_HOME="$R11_XDG"
echo hid.txt >> "$E_ROOT/.git/info/exclude"; echo h > "$E_ROOT/hid.txt"
r11_dirty "untracked file hidden by .git/info/exclude while a user global ignore is configured"
cp "$WD/exclude.bak" "$E_ROOT/.git/info/exclude"; rm -f "$E_ROOT/hid.txt"
unset XDG_CONFIG_HOME; rm -f "$R11_XDG/git/ignore"; r11_restored "info/exclude with global ignore"

# R11j (owner fix-now B2) — LIVENESS: a global core.excludesFile set through an [include] or
# [includeIf "gitdir:…"] in the user's ~/.gitconfig is followed exactly as git follows it, so
# the globally-ignored file does not park (the R11h precondition leg proved it is dirt without).
r11_gfix
printf '[core]\n\texcludesFile = %s\n' "$WD/gx-ignore" > "$WD/gx-inc"
printf '[include]\n\tpath = %s\n' "$WD/gx-inc" > "$WD/nohome/.gitconfig"
r11_decides "global core.excludesFile reached through an [include] in ~/.gitconfig"
printf '[includeIf "gitdir:%s/"]\n\tpath = %s\n' "$E_ROOT" "$WD/gx-inc" > "$WD/nohome/.gitconfig"
r11_decides "global core.excludesFile reached through an [includeIf \"gitdir:<checkout>/\"] in ~/.gitconfig"
rm -f "$WD/nohome/.gitconfig"

# R11k (owner fix-now B3) — the "outside the checkout" test is PHYSICAL: a directory alias of
# the checkout (a symlinked directory — the /tmp vs /private/tmp class) and a symlink outside
# the checkout whose target is an in-repo file are both refused, so the in-repo ignore is NOT
# honoured and the globally-ignorable files park. Control: a symlinked dotfile whose target
# is OUTSIDE the checkout (how dotfile managers install ~/.gitignore_global) is honoured.
mkdir -p "$E_ROOT/ignored-dir"; cp "$WD/gx-ignore" "$E_ROOT/ignored-dir/gx"
ln -s "$E_ROOT" "$WD/alias-co"; ln -s "$E_ROOT/ignored-dir/gx" "$WD/gx-link-in"; ln -s "$WD/gx-ignore" "$WD/gx-link-out"
printf '[core]\n\texcludesFile = %s\n' "$WD/alias-co/ignored-dir/gx" > "$WD/nohome/.gitconfig"
r11_dirty "global core.excludesFile spelled through a directory ALIAS of the checkout is not honoured"
printf '[core]\n\texcludesFile = %s\n' "$WD/gx-link-in" > "$WD/nohome/.gitconfig"
r11_dirty "global core.excludesFile that is a symlink OUTSIDE the checkout pointing at an in-repo file is not honoured"
printf '[core]\n\texcludesFile = %s\n' "$WD/gx-link-out" > "$WD/nohome/.gitconfig"
r11_decides "global core.excludesFile that is a symlink to a file OUTSIDE the checkout (control: honoured)"
rm -f "$WD/nohome/.gitconfig"; rm -rf "$E_ROOT/ignored-dir"; r11_gundo; r11_restored "global ignore include/physical legs"

# R11l (owner fix-now B1) — SUBMODULES. A separate superproject ($SM_TOP, submodule `lib`
# from $SM_LIB over a local path, protocol.file.allow only inside this fixture) whose COMMITTED
# .gitmodules says `ignore = all`. Precondition legs prove a plain `git status` sees nothing,
# so each PARK is the pin's own doing; the control (clean, correctly-pinned submodule) MERGEs
# and the gate leaves both index files untouched (it writes nothing, no submodule refresh).
SM_LIB="$WD/smlib"; SM_TOP="$WD/smtop"
r11_sm_git() { git -c user.email=t@t -c user.name=t -c commit.gpgsign=false -c protocol.file.allow=always "$@"; }
( git init -q "$SM_LIB" && cd "$SM_LIB" && echo l > l && git add l && r11_sm_git commit -qm l \
    && echo l2 > l2 && git add l2 && r11_sm_git commit -qm l2 \
  && git init -q "$SM_TOP" && cd "$SM_TOP" && echo t > t && git add t && r11_sm_git commit -qm t \
    && r11_sm_git submodule add -q "$SM_LIB" lib && r11_sm_git commit -qm sub \
    && git config -f .gitmodules submodule.lib.ignore all && git add .gitmodules && r11_sm_git commit -qm ign ) >/dev/null 2>&1
SM_HEAD="$(git -C "$SM_TOP" rev-parse --verify -q HEAD 2>/dev/null)" || SM_HEAD=""
SM_GD="$(cd "$SM_TOP/lib" 2>/dev/null && git rev-parse --absolute-git-dir 2>/dev/null)" || SM_GD=""
r11_sm_clean() {  # the fixture is back: lib at its recorded commit, nothing dirty anywhere
  [ -n "$SM_HEAD" ] && [ -n "$SM_GD" ] \
    && [ -z "$(git -C "$SM_TOP" status --porcelain -uall --ignored --ignore-submodules=none 2>/dev/null)" ] \
    && [ -z "$(git -C "$SM_TOP/lib" status --porcelain -uall --ignored 2>/dev/null)" ]
}
if r11_sm_clean && [ -f "$SM_TOP/lib/l2" ]; then
  ok "R11l harness: superproject with a checked-out, correctly-pinned submodule and a committed ignore=all"
else
  no "R11l harness: could not build the submodule fixture (head='$SM_HEAD' gd='$SM_GD') — the R11l legs are meaningless"
fi
E_PR_HEAD="$SM_HEAD"; E_GATE_ROOT="$SM_TOP"
touch -t 200001010000 "$SM_TOP/.git/index" "$SM_GD/index"; touch -t 200101010000 "$WD/sm-ref"
r11_decides "clean superproject with a clean, correctly-pinned submodule (control)"
if [ -z "$(find "$SM_TOP/.git/index" "$SM_GD/index" -newer "$WD/sm-ref" 2>/dev/null)" ] && r11_sm_clean; then
  ok "R11l the gate wrote neither the superproject's nor the submodule's index (no refresh, no lock)"
else
  no "R11l the gate rewrote an index file (gate must write nothing)"
fi
echo dirt >> "$SM_TOP/lib/l"
r11_dirty "tracked edit inside a submodule whose committed .gitmodules says ignore=all"
git -C "$SM_TOP/lib" checkout -q -- l
git -C "$SM_TOP/lib" checkout -q HEAD~1 >/dev/null 2>&1
if [ -z "$(git -C "$SM_TOP" status --porcelain -uall 2>/dev/null)" ] && [ -n "$(git -C "$SM_TOP" status --porcelain --ignore-submodules=none 2>/dev/null)" ]; then
  r11_dirty "submodule checked out at a commit OTHER than the recorded one (hidden by committed ignore=all)"
else
  no "R11l stale-commit precondition: plain git status should be blind and --ignore-submodules=none should see it"
fi
git -C "$SM_TOP/lib" checkout -q - >/dev/null 2>&1
cp "$SM_GD/info/exclude" "$WD/sm-exclude.bak" 2>/dev/null || : > "$WD/sm-exclude.bak"
echo u >> "$SM_GD/info/exclude"; echo u > "$SM_TOP/lib/u"
if [ -z "$(git -C "$SM_TOP" status --porcelain -uall --ignore-submodules=none 2>/dev/null)" ]; then
  r11_dirty "untracked file inside a submodule hidden by the SUBMODULE's own info/exclude"
else
  no "R11l submodule info/exclude precondition: the top-level status should be blind to it"
fi
cp "$WD/sm-exclude.bak" "$SM_GD/info/exclude"; rm -f "$SM_TOP/lib/u"
git -C "$SM_TOP/lib" update-index --assume-unchanged l; echo dirt >> "$SM_TOP/lib/l"
r11_dirty "tracked edit inside a submodule hidden by the submodule's assume-unchanged flag"
git -C "$SM_TOP/lib" update-index --no-assume-unchanged l; git -C "$SM_TOP/lib" checkout -q -- l
E_PR_HEAD="$E_HEAD"; E_GATE_ROOT=""; reset_live
r11_sm_clean || no "R11l: the submodule fixture was NOT restored"

# R11e (AC6) — GATED mutation controls: delete each pin (its `if` line becomes `if false; then`)
# ⇒ the leg that pin guards turns into a MERGE, proving each leg can fail. Trusted only if the
# mutant is non-empty, differs from the original, passes `bash -n`, and carries its marker; the
# UN-mutated copy is run on the same two legs first (positive control).
M_HEAD="$(r9_dir 's/^  if \[ "\$root_head_rc" -ne 0 \] .*; then$/  if false; then # R11-MUTANT-HEAD/' 'R11-MUTANT-HEAD')"
M_DIRTY="$(r9_dir 's/^  if \[ "\$root_dirt_rc" -ne 0 \] .*; then$/  if false; then # R11-MUTANT-DIRTY/' 'R11-MUTANT-DIRTY')"
if [ -n "$M_HEAD" ] && [ -n "$M_DIRTY" ]; then
  CTRL="$(mktemp -d)"; cp "$GWD/automate-helpers.sh" "$GWD/classify-risk.sh" "$GWD/rules-gate-verdict.sh" "$CTRL/"
  # stale-HEAD leg: original parks, mutant merges.
  E_PR_HEAD="$E_TIP"; reset_live; rules_fixture ok '["r-lint"]' '[]' '[]'
  r9_run "$CTRL"; R11_CO="$R9_OUT"; R11_CM="$(merges)"
  r9_run "$M_HEAD"
  if [ "$R11_CO" = "PARK: rules_gate_head_mismatch" ] && [ "$R11_CM" -eq 0 ] && [ "$R9_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ]; then
    ok "R11e (mutant) HEAD pin deleted ⇒ the stale-HEAD leg MERGEs (control: the un-mutated gate parks it rules_gate_head_mismatch) — the leg can fail"
  else
    no "R11e HEAD-pin mutant did not discriminate (control='$R11_CO'/$R11_CM mutant='$R9_OUT'/$(merges))"
  fi
  E_PR_HEAD="$E_HEAD"; reset_live; rules_fixture ok '["r-lint"]' '[]' '[]'
  # dirty-tree leg: original parks, mutant merges. A TRACKED edit (not an untracked file),
  # because untracked files are now also caught by the ls-files read below the status one.
  echo more >> "$E_ROOT/sub/a"
  r9_run "$CTRL"; R11_CO="$R9_OUT"; R11_CM="$(merges)"
  r9_run "$M_DIRTY"
  if [ "$R11_CO" = "PARK: rules_gate_dirty_tree" ] && [ "$R11_CM" -eq 0 ] && [ "$R9_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ]; then
    ok "R11e (mutant) dirty-tree pin deleted ⇒ the dirty-tree leg MERGEs (control: the un-mutated gate parks it rules_gate_dirty_tree) — the leg can fail"
  else
    no "R11e dirty-pin mutant did not discriminate (control='$R11_CO'/$R11_CM mutant='$R9_OUT'/$(merges))"
  fi
  git -C "$E_ROOT" checkout -q -- sub/a; r11_restored "R11e"
  rm -rf "$CTRL"
else
  no "R11e pin mutation controls not gated (a mutant was empty, identical to the original, failed bash -n, or lacked its marker)"
fi
rm -rf "${M_HEAD:-/nonexistent-r11}" "${M_DIRTY:-/nonexistent-r11}"

# R11g (review iteration 1) — GATED mutants for each read the fix added: disable ONE read's
# park (or the env unset, or the show-toplevel fail-closed branch) ⇒ the R11f leg that only
# that read catches MERGEs; the un-mutated copy parks the same leg first (positive control).
r11g() {  # r11g <mutant-dir> <label> <setup> <undo> — control parks, mutant merges
  local co cm
  reset_live; rules_fixture ok '["r-lint"]' '[]' '[]'
  eval "$3"
  r9_run "$CTRL"; co="$R9_OUT"; cm="$(merges)"
  r9_run "$1"
  if [ "$co" = "PARK: rules_gate_dirty_tree" ] && [ "$cm" -eq 0 ] && [ "$R9_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ]; then
    ok "R11g (mutant) $2 ⇒ its leg MERGEs (control: the un-mutated gate parks it rules_gate_dirty_tree) — the read is load-bearing"
  else
    no "R11g $2 mutant did not discriminate (control='$co'/$cm mutant='$R9_OUT'/$(merges))"
  fi
  eval "$4"; r11_restored "R11g $2"
}
M_FLAGS="$(r9_dir 's/^  if \[ "\$root_flags_rc" -ne 0 \] .*; then$/  if false; then # R11-MUTANT-FLAGS/' 'R11-MUTANT-FLAGS')"
M_UNT="$(r9_dir 's/^  if \[ "\$root_unt_rc" -ne 0 \] .*; then$/  if false; then # R11-MUTANT-UNT/' 'R11-MUTANT-UNT')"
M_IGN="$(r9_dir 's/^  if \[ "\$root_ign_rc" -ne 0 \] .*; then$/  if false; then # R11-MUTANT-IGN/' 'R11-MUTANT-IGN')"
M_ENV="$(r9_dir 's/ -u GIT_CONFIG_COUNT / -u R11_MUTANT_ENV /' 'R11_MUTANT_ENV')"
M_TOP="$(r9_dir 's/^    root_dirt_rc=1$/    root_dirt_rc=0 # R11-MUTANT-TOP/' 'R11-MUTANT-TOP')"
M_INREPO="$(r9_dir 's/ || _ge_inside "\$ge_xf_p" "\$root_top"; then / ; then : R11-MUTANT-INREPO; /' 'R11-MUTANT-INREPO')"
# Owner fix-now mutants: B3 (symlink resolution dropped; physical resolution AND the -ef walk
# both reverted to the old lexical compare) and B1 (the submodule recursion's park deleted;
# `--ignore-submodules=none` dropped from the top-level status read).
M_LINK="$(r9_dir 's/^    while \[ -L "\$p" \]; do$/    while false; do # R11-MUTANT-LINK/' 'R11-MUTANT-LINK')"
M_LEX="$(r9_dir 's/^      ge_xf_p="\$(_ge_phys "\$ge_xf")" || ge_xf_p=""$/      ge_xf_p="$ge_xf" # R11-MUTANT-LEX/;s/^      \[ "\$d" -ef "\$2" \] \&\& return 0$/      [ "$d" = "$2" ] \&\& return 0/' 'R11-MUTANT-LEX')"
M_SUBS="$(r9_dir 's/^  if \[ "\$root_subs_rc" -ne 0 \]; then$/  if false; then # R11-MUTANT-SUBS/' 'R11-MUTANT-SUBS')"
M_SUBFLAG="$(r9_dir 's/^\(    root_dirt=.* status --porcelain -uall\) --ignore-submodules=none \(.*\)$/\1 \2 # R11-MUTANT-SUBFLAG/' 'R11-MUTANT-SUBFLAG')"
if [ -n "$M_FLAGS" ] && [ -n "$M_UNT" ] && [ -n "$M_IGN" ] && [ -n "$M_ENV" ] && [ -n "$M_TOP" ] && [ -n "$M_INREPO" ] \
   && [ -n "$M_LINK" ] && [ -n "$M_LEX" ] && [ -n "$M_SUBS" ] && [ -n "$M_SUBFLAG" ]; then
  CTRL="$(mktemp -d)"; cp "$GWD/automate-helpers.sh" "$GWD/classify-risk.sh" "$GWD/rules-gate-verdict.sh" "$CTRL/"
  r11g "$M_FLAGS" "assume-unchanged read deleted" \
    'git -C "$E_ROOT" update-index --assume-unchanged sub/a; echo more >> "$E_ROOT/sub/a"' \
    'git -C "$E_ROOT" update-index --no-assume-unchanged sub/a; git -C "$E_ROOT" checkout -q -- sub/a'
  r11g "$M_UNT" "committed-.gitignore-only untracked read deleted" \
    'echo hid.txt >> "$E_ROOT/.git/info/exclude"; echo h > "$E_ROOT/hid.txt"' \
    'cp "$WD/exclude.bak" "$E_ROOT/.git/info/exclude"; rm -f "$E_ROOT/hid.txt"'
  r11g "$M_IGN" "untracked-.gitignore read deleted" \
    'mkdir -p "$E_ROOT/evil"; echo "*" > "$E_ROOT/evil/.gitignore"; echo e > "$E_ROOT/evil/f"' \
    'rm -rf "$E_ROOT/evil"'
  r11g "$M_ENV" "GIT_CONFIG_COUNT unset removed" \
    'chmod +x "$E_ROOT/sub/a"; r11_env_on' \
    'r11_env_off; chmod -x "$E_ROOT/sub/a"'
  r11g "$M_TOP" "show-toplevel failure no longer fails closed" \
    'E_GATE_ROOT="$E_ROOT/.git"' \
    'E_GATE_ROOT=""'
  r11g "$M_INREPO" "in-checkout global excludesFile refusal removed" \
    'mkdir -p "$E_ROOT/ignored-dir"; printf "notes.local\n" > "$E_ROOT/ignored-dir/gx"; printf "[core]\n\texcludesFile = %s\n" "$E_ROOT/ignored-dir/gx" > "$WD/nohome/.gitconfig"; echo n > "$E_ROOT/notes.local"' \
    'rm -rf "$E_ROOT/ignored-dir" "$E_ROOT/notes.local" "$WD/nohome/.gitconfig"'
  r11g "$M_LINK" "symlinked global excludesFile no longer resolved" \
    'mkdir -p "$E_ROOT/ignored-dir"; printf "notes.local\n" > "$E_ROOT/ignored-dir/gx"; printf "[core]\n\texcludesFile = %s\n" "$WD/gx-link-in" > "$WD/nohome/.gitconfig"; echo n > "$E_ROOT/notes.local"' \
    'rm -rf "$E_ROOT/ignored-dir" "$E_ROOT/notes.local" "$WD/nohome/.gitconfig"'
  r11g "$M_LEX" "outside-the-checkout test reverted to a lexical prefix compare" \
    'mkdir -p "$E_ROOT/ignored-dir"; printf "notes.local\n" > "$E_ROOT/ignored-dir/gx"; printf "[core]\n\texcludesFile = %s\n" "$WD/alias-co/ignored-dir/gx" > "$WD/nohome/.gitconfig"; echo n > "$E_ROOT/notes.local"' \
    'rm -rf "$E_ROOT/ignored-dir" "$E_ROOT/notes.local" "$WD/nohome/.gitconfig"'
  E_PR_HEAD="$SM_HEAD"
  r11g "$M_SUBS" "submodule recursion park deleted" \
    'E_GATE_ROOT="$SM_TOP"; echo u >> "$SM_GD/info/exclude"; echo u > "$SM_TOP/lib/u"' \
    'E_GATE_ROOT=""; cp "$WD/sm-exclude.bak" "$SM_GD/info/exclude"; rm -f "$SM_TOP/lib/u"'
  r11g "$M_SUBFLAG" "--ignore-submodules=none dropped from the top-level status" \
    'E_GATE_ROOT="$SM_TOP"; git -C "$SM_TOP/lib" checkout -q HEAD~1 >/dev/null 2>&1' \
    'E_GATE_ROOT=""; git -C "$SM_TOP/lib" checkout -q - >/dev/null 2>&1'
  E_PR_HEAD="$E_HEAD"; reset_live
  r11_sm_clean || no "R11g: the submodule fixture was NOT restored after its mutants"
  rm -rf "$CTRL"
else
  no "R11g read mutation controls not gated (a mutant was empty, identical to the original, failed bash -n, or lacked its marker)"
fi
rm -rf "${M_FLAGS:-/nonexistent-r11}" "${M_UNT:-/nonexistent-r11}" "${M_IGN:-/nonexistent-r11}" "${M_ENV:-/nonexistent-r11}" "${M_TOP:-/nonexistent-r11}" "${M_INREPO:-/nonexistent-r11}" \
  "${M_LINK:-/nonexistent-r11}" "${M_LEX:-/nonexistent-r11}" "${M_SUBS:-/nonexistent-r11}" "${M_SUBFLAG:-/nonexistent-r11}"

# R11i (review iteration 2) — GATED liveness mutant: drop the global `--exclude-from` ⇒ the
# R11h XDG leg PARKs again (the iteration-1 behaviour), while the un-mutated copy MERGEs it.
M_XF="$(r9_dir 's/^    if \[ -n "\$ge_xf" \] && \[ -f "\$ge_xf" \] && \[ -r "\$ge_xf" \]; then ge_xargs=.*$/    : # R11-MUTANT-XF/' 'R11-MUTANT-XF')"
if [ -n "$M_XF" ]; then
  CTRL="$(mktemp -d)"; cp "$GWD/automate-helpers.sh" "$GWD/classify-risk.sh" "$GWD/rules-gate-verdict.sh" "$CTRL/"
  reset_live; rules_fixture ok '["r-lint"]' '[]' '[]'
  printf 'notes.local\n' > "$R11_XDG/git/ignore"; export XDG_CONFIG_HOME="$R11_XDG"; echo n > "$E_ROOT/notes.local"
  r9_run "$CTRL"; R11_CO="$R9_OUT"; R11_CM="$(merges)"
  r9_run "$M_XF"
  if [ "$R11_CO" = "MERGE" ] && [ "$R11_CM" -eq 1 ] && [ "$R9_OUT" = "PARK: rules_gate_dirty_tree" ] && [ "$(merges)" -eq 0 ]; then
    ok "R11i (mutant) global --exclude-from dropped ⇒ the globally-ignored-file leg PARKs (control: the un-mutated gate MERGEs it) — the liveness leg can fail"
  else
    no "R11i global-ignore mutant did not discriminate (control='$R11_CO'/$R11_CM mutant='$R9_OUT'/$(merges))"
  fi
  unset XDG_CONFIG_HOME; rm -f "$R11_XDG/git/ignore" "$E_ROOT/notes.local"; r11_restored "R11i"
  rm -rf "$CTRL"
else
  no "R11i global-ignore mutation control not gated (mutant empty, identical to the original, failed bash -n, or lacked its marker)"
fi
rm -rf "${M_XF:-/nonexistent-r11}"

# R11m (owner fix-now B2) — GATED liveness mutant: drop `--includes` from the global
# excludesFile read ⇒ the R11j [include] leg PARKs (git's own lookup would have followed the
# include), while the un-mutated copy MERGEs it.
M_INC="$(r9_dir 's/ config --global --includes --path --get core\.excludesFile / config --global --path --get core.excludesFile /;s/^\(    ge_xf=.*core\.excludesFile .*\)$/\1 # R11-MUTANT-INC/' 'R11-MUTANT-INC')"
if [ -n "$M_INC" ]; then
  CTRL="$(mktemp -d)"; cp "$GWD/automate-helpers.sh" "$GWD/classify-risk.sh" "$GWD/rules-gate-verdict.sh" "$CTRL/"
  reset_live; rules_fixture ok '["r-lint"]' '[]' '[]'
  printf '[include]\n\tpath = %s\n' "$WD/gx-inc" > "$WD/nohome/.gitconfig"; echo n > "$E_ROOT/notes.local"
  r9_run "$CTRL"; R11_CO="$R9_OUT"; R11_CM="$(merges)"
  r9_run "$M_INC"
  if [ "$R11_CO" = "MERGE" ] && [ "$R11_CM" -eq 1 ] && [ "$R9_OUT" = "PARK: rules_gate_dirty_tree" ] && [ "$(merges)" -eq 0 ]; then
    ok "R11m (mutant) --includes dropped ⇒ the [include]-reached global ignore leg PARKs (control: the un-mutated gate MERGEs it) — the liveness leg can fail"
  else
    no "R11m --includes mutant did not discriminate (control='$R11_CO'/$R11_CM mutant='$R9_OUT'/$(merges))"
  fi
  rm -f "$WD/nohome/.gitconfig" "$E_ROOT/notes.local"; r11_restored "R11m"
  rm -rf "$CTRL"
else
  no "R11m --includes mutation control not gated (mutant empty, identical to the original, failed bash -n, or lacked its marker)"
fi
rm -rf "${M_INC:-/nonexistent-r11}"
reset_live

unset GH_STUB_DIR
rm -rf "$WD"

# =============================================================================
echo "== F. learning-emit (engine-native ground-truth POSTMORTEM_RESULT line) =="

# F1. happy path fix_cycles>0 → exactly ONE drain_churn categories[] entry,
#     review_rounds == fix_cycles, valid JSON, source==automate_drain, changed_paths populated.
WD="$(mktemp -d)"; LED="$WD/results.jsonl"
bash "$H" learning-emit "$LED" \
  --repo "acme/widgets" --number 42 --pr-url "$PR" --run-id "run1" --item "item-a" \
  --fix-cycles 3 --drain-result READY \
  --repeat-check-failure false --unresolved-bot-feedback false \
  --changed-paths-json '["src/a.ts","src/b.ts"]' --additions 10 --deletions 2 --changed-files 2 \
  --summary "automate drain churn"
if [ -f "$LED" ] && [ "$(wc -l < "$LED" | tr -d ' ')" = "1" ] \
   && jq -e . "$LED" >/dev/null 2>&1 \
   && [ "$(jq -r '.source' "$LED")" = "automate_drain" ] \
   && [ "$(jq -r '.review_rounds' "$LED")" = "3" ] \
   && [ "$(jq -r '.categories | length' "$LED")" = "1" ] \
   && [ "$(jq -r '.categories[0].class' "$LED")" = "drain_churn" ] \
   && [ "$(jq -r '.categories[0].round' "$LED")" = "3" ] \
   && [ "$(jq -r '.changed_paths | length' "$LED")" = "2" ] \
   && [ "$(jq -r '.flow_stages.self_heal' "$LED")" = "3" ] \
   && [ "$(jq -r '.schema_version' "$LED")" = "1" ]; then
  ok "happy path fix_cycles>0: one drain_churn entry, review_rounds==fix_cycles, changed_paths populated, valid JSON"
else
  no "happy-path wrong (line='$(cat "$LED" 2>/dev/null)')"
fi
rm -rf "$WD"

# F2. fix_cycles==0 non-escalated → categories: [] AND review_rounds: 0 (zero-rule; NO synthetic entry).
WD="$(mktemp -d)"; LED="$WD/results.jsonl"
bash "$H" learning-emit "$LED" \
  --repo "acme/widgets" --number 43 --pr-url "$PR" --run-id "run2" --item "item-b" \
  --fix-cycles 0 --drain-result READY \
  --repeat-check-failure false --unresolved-bot-feedback false \
  --changed-paths-json '["src/c.ts"]' --additions 1 --deletions 0 --changed-files 1 \
  --summary "clean merge"
if jq -e . "$LED" >/dev/null 2>&1 \
   && [ "$(jq -r '.categories | length' "$LED")" = "0" ] \
   && [ "$(jq -r '.review_rounds' "$LED")" = "0" ] \
   && [ "$(jq -r '.flow_stages.self_heal' "$LED")" = "0" ]; then
  ok "zero-rule: fix_cycles==0 non-escalated ⇒ categories:[] AND review_rounds:0 (no fake churn)"
else
  no "zero-rule wrong (line='$(cat "$LED" 2>/dev/null)')"
fi
rm -rf "$WD"

# F3. zero-cycle ESCALATED (fix_cycles==0, drain_result==ESCALATED) → review_rounds:1 + ONE drain_escalation entry.
WD="$(mktemp -d)"; LED="$WD/results.jsonl"
bash "$H" learning-emit "$LED" \
  --repo "acme/widgets" --number 44 --pr-url "$PR" --run-id "run3" --item "item-c" \
  --fix-cycles 0 --drain-result ESCALATED \
  --repeat-check-failure false --unresolved-bot-feedback false \
  --changed-paths-json '["src/d.ts"]' --additions 5 --deletions 5 --changed-files 1 \
  --summary "escalated before any fix cycle"
if jq -e . "$LED" >/dev/null 2>&1 \
   && [ "$(jq -r '.review_rounds' "$LED")" = "1" ] \
   && [ "$(jq -r '.categories | length' "$LED")" = "1" ] \
   && [ "$(jq -r '.categories[0].class' "$LED")" = "drain_escalation" ] \
   && [ "$(jq -r '.categories[0].round' "$LED")" = "1" ] \
   && [ "$(jq -r '.flow_stages.self_heal' "$LED")" = "1" ]; then
  ok "zero-cycle ESCALATED: review_rounds:1 + ONE drain_escalation entry"
else
  no "zero-cycle-escalated wrong (line='$(cat "$LED" 2>/dev/null)')"
fi
rm -rf "$WD"

# F4. idempotency: two calls with the SAME run_id+item+pr_url+source → ledger has exactly ONE line.
WD="$(mktemp -d)"; LED="$WD/results.jsonl"
for i in 1 2; do
  bash "$H" learning-emit "$LED" \
    --repo "acme/widgets" --number 45 --pr-url "$PR" --run-id "run4" --item "item-d" \
    --fix-cycles 2 --drain-result READY \
    --repeat-check-failure false --unresolved-bot-feedback false \
    --changed-paths-json '["src/e.ts"]' --additions 3 --deletions 1 --changed-files 1 \
    --summary "dup attempt"
done
if [ "$(wc -l < "$LED" | tr -d ' ')" = "1" ]; then
  ok "idempotency: duplicate run_id+item+pr_url+source key ⇒ exactly ONE line"
else
  no "idempotency wrong (lines=$(wc -l < "$LED" 2>/dev/null | tr -d ' '))"
fi
rm -rf "$WD"

# F5. missing-field degrade (omit --changed-paths-json) → still exit 0, line written with changed_paths: [].
WD="$(mktemp -d)"; LED="$WD/results.jsonl"
run_h bash "$H" learning-emit "$LED" \
  --repo "acme/widgets" --number 46 --pr-url "$PR" --run-id "run5" --item "item-e" \
  --fix-cycles 1 --drain-result READY \
  --repeat-check-failure false --unresolved-bot-feedback false \
  --summary "no changed-paths arg"
if [ "$RUN_RC" -eq 0 ] && jq -e . "$LED" >/dev/null 2>&1 \
   && [ "$(jq -r '.changed_paths | length' "$LED")" = "0" ] \
   && [ "$(jq -r '.changed_paths | type' "$LED")" = "array" ]; then
  ok "missing-field degrade: exit 0, line written, changed_paths:[]"
else
  no "missing-field-degrade wrong (rc=$RUN_RC line='$(cat "$LED" 2>/dev/null)')"
fi
rm -rf "$WD"

# F6. jq-absent → exit 0, NO write (point LOOMWRIGHT_JQ_BIN at a nonexistent binary).
WD="$(mktemp -d)"; LED="$WD/results.jsonl"
run_h env LOOMWRIGHT_JQ_BIN="$WD/no-such-jq-binary" bash "$H" learning-emit "$LED" \
  --repo "acme/widgets" --number 47 --pr-url "$PR" --run-id "run6" --item "item-f" \
  --fix-cycles 1 --drain-result READY --summary "jq absent"
if [ "$RUN_RC" -eq 0 ] && [ ! -f "$LED" ]; then
  ok "jq-absent: exit 0, NO write"
else
  no "jq-absent wrong (rc=$RUN_RC led-exists=$([ -f "$LED" ] && echo y || echo n))"
fi
rm -rf "$WD"

# F7. fetch-fail degrade → changed_paths: [] AND additions/deletions/changed_files are integer 0 (NOT null).
WD="$(mktemp -d)"; LED="$WD/results.jsonl"
# Simulate the loop's degraded call: changed_paths_json defaults to [], size fields to 0.
bash "$H" learning-emit "$LED" \
  --repo "acme/widgets" --number 48 --pr-url "$PR" --run-id "run7" --item "item-g" \
  --fix-cycles 0 --drain-result READY \
  --changed-paths-json '[]' --additions 0 --deletions 0 --changed-files 0 \
  --summary "fetch failed, degraded"
if jq -e . "$LED" >/dev/null 2>&1 \
   && [ "$(jq -r '.changed_paths | length' "$LED")" = "0" ] \
   && [ "$(jq -r '.additions | type' "$LED")" = "number" ] \
   && [ "$(jq -r '.additions' "$LED")" = "0" ] \
   && [ "$(jq -r '.deletions' "$LED")" = "0" ] \
   && [ "$(jq -r '.changed_files' "$LED")" = "0" ]; then
  ok "fetch-fail degrade: changed_paths:[], additions/deletions/changed_files integer 0 (not null)"
else
  no "fetch-fail-degrade wrong (line='$(cat "$LED" 2>/dev/null)')"
fi
rm -rf "$WD"

# F8. injection-safe: --summary / --pr-url with ";, $(...), quotes → still valid single-line JSON, value verbatim.
WD="$(mktemp -d)"; LED="$WD/results.jsonl"
INJ_SUMMARY='evil"; rm -rf / $(touch /tmp/pwned) `id` end'
INJ_URL='https://github.com/a/b/pull/1"; echo hacked #'
bash "$H" learning-emit "$LED" \
  --repo "acme/widgets" --number 49 --pr-url "$INJ_URL" --run-id "run8" --item "item-h" \
  --fix-cycles 1 --drain-result READY \
  --changed-paths-json '["src/x.ts"]' --additions 1 --deletions 0 --changed-files 1 \
  --summary "$INJ_SUMMARY"
if [ "$(wc -l < "$LED" | tr -d ' ')" = "1" ] && jq -e . "$LED" >/dev/null 2>&1 \
   && [ "$(jq -r '.summary' "$LED")" = "$INJ_SUMMARY" ] \
   && [ "$(jq -r '.pr_url' "$LED")" = "$INJ_URL" ] \
   && [ ! -f /tmp/pwned ]; then
  ok "injection-safe: malicious summary/pr_url preserved verbatim, still valid single-line JSON"
else
  no "injection-safe wrong (line='$(cat "$LED" 2>/dev/null)')"
fi
rm -f /tmp/pwned
rm -rf "$WD"

# F9. self_heal_misses derivation: repeat_check_failure=true → self_heal_misses:1 and entry self_heal_miss:true.
WD="$(mktemp -d)"; LED="$WD/results.jsonl"
bash "$H" learning-emit "$LED" \
  --repo "acme/widgets" --number 50 --pr-url "$PR" --run-id "run9" --item "item-i" \
  --fix-cycles 2 --drain-result READY \
  --repeat-check-failure true --unresolved-bot-feedback false \
  --changed-paths-json '["src/y.ts"]' --additions 4 --deletions 2 --changed-files 1 \
  --summary "repeat check failure"
if [ "$(jq -r '.self_heal_misses' "$LED")" = "1" ] \
   && [ "$(jq -r '.categories[0].self_heal_miss' "$LED")" = "true" ]; then
  ok "self_heal_misses: repeat_check_failure=true ⇒ self_heal_misses:1 + entry self_heal_miss:true"
else
  no "self_heal_misses wrong (line='$(cat "$LED" 2>/dev/null)')"
fi
rm -rf "$WD"

# F10. read-postmortem.sh visibility (reasoned via the reader's OWN selection jq):
#      read-postmortem.sh:159 [pins: `changed_paths overlap the query set`] keeps a corpus
#      line iff (a) repo matches the reader's
#      current repo case-insensitively WHEN the reader's repo is determinable, AND (b) its
#      changed_paths overlaps the query path set; then it counts each categories[] element as
#      one prior-churn round. We replicate BOTH predicates faithfully (an earlier version of
#      this test omitted the repo clause — PR #77 review finding #3 — so it could not have
#      caught an empty-repo line being dropped; that blind spot is closed below + in F11).
# reader_select <ledger> <query_path> <cur_repo>  -> JSON array of {rounds} for matching lines.
reader_select() {
  jq -R 'fromjson? // empty' "$1" \
    | jq -s --arg q "$2" --arg cur_repo "$3" '
        [ .[]
          | . as $e
          | select($cur_repo == "" or ((($e.repo) // "") | ascii_downcase) == ($cur_repo | ascii_downcase))
          | select(((($e.changed_paths) // []) | map(select(. == $q)) | length) > 0)
          | {rounds: ((($e.categories) // []) | length)}
        ]' 2>/dev/null
}
WD="$(mktemp -d)"; LED="$WD/results.jsonl"
bash "$H" learning-emit "$LED" \
  --repo "acme/widgets" --number 51 --pr-url "$PR" --run-id "run10" --item "item-j" \
  --fix-cycles 2 --drain-result READY \
  --repeat-check-failure false --unresolved-bot-feedback false \
  --changed-paths-json '["src/visible.ts"]' --additions 3 --deletions 1 --changed-files 1 \
  --summary "visible to reader"
# F10a: matching repo (exact + case-insensitive) AND path overlap ⇒ 1 hit, 1 round.
HITS="$(reader_select "$LED" "src/visible.ts" "acme/widgets")"
HITS_CI="$(reader_select "$LED" "src/visible.ts" "ACME/Widgets")"
if [ "$(printf '%s' "$HITS" | jq 'length')" = "1" ] \
   && [ "$(printf '%s' "$HITS" | jq '.[0].rounds')" = "1" ] \
   && [ "$(printf '%s' "$HITS_CI" | jq 'length')" = "1" ]; then
  ok "read-postmortem visibility: automate_drain line IS a prior-churn hit (repo match (case-insensitive) + changed_paths overlap + 1 categories round)"
else
  no "read-postmortem visibility wrong (hits='$HITS' hits_ci='$HITS_CI')"
fi
rm -rf "$WD"

# F11. --repo is load-bearing for visibility (the PR #77 finding #1 failure mode): a line
#      emitted with an EMPTY --repo carries repo:"" (NOT null) and is DROPPED by the reader
#      whenever the reader's repo resolves — yet stays visible only when the reader's repo is
#      undeterminable (cur_repo=="", the vacuously-true arm). This is the regression guard that
#      would have surfaced finding #1.
WD="$(mktemp -d)"; LED="$WD/results.jsonl"
bash "$H" learning-emit "$LED" \
  --repo "" --number 52 --pr-url "$PR" --run-id "run11" --item "item-k" \
  --fix-cycles 1 --drain-result READY \
  --changed-paths-json '["src/visible.ts"]' --additions 1 --deletions 0 --changed-files 1 \
  --summary "empty repo"
EMITTED_REPO="$(tail -1 "$LED" | jq -r '.repo')"
DROPPED="$(reader_select "$LED" "src/visible.ts" "acme/widgets" | jq 'length')"
KEPT_WHEN_UNDET="$(reader_select "$LED" "src/visible.ts" "" | jq 'length')"
if [ "$EMITTED_REPO" = "" ] \
   && [ "$DROPPED" = "0" ] \
   && [ "$KEPT_WHEN_UNDET" = "1" ]; then
  ok "read-postmortem visibility: empty --repo emits repo:\"\" and is DROPPED when the reader's repo resolves (--repo is load-bearing)"
else
  no "empty-repo visibility wrong (emitted_repo='$EMITTED_REPO' dropped='$DROPPED' kept_when_undet='$KEPT_WHEN_UNDET')"
fi
rm -rf "$WD"

# F12. DEGRADED-then-CORRECTIVE emit (the PR #126 defect). A first emit that degraded
#      (the single `gh pr view` fetch failed, or the caller omitted the fetch args)
#      writes changed_paths:[] — a line PERMANENTLY INVISIBLE to read-postmortem.sh.
#      Before the degradation-aware key, that line poisoned the automate_key and every
#      later complete emit was silently skipped. Asserted against the REAL
#      read-postmortem.sh (NOT the reader_select jq mirror, which could drift from the
#      reader it models) inside a throwaway git repo whose origin remote makes the
#      reader's CUR_REPO resolve, so repo scoping is exercised too.
WD="$(mktemp -d)"
( cd "$WD" && git init -q && git config user.email t@t && git config user.name t \
    && git remote add origin https://github.com/acme/widgets.git \
    && echo i > f && git add f && git commit -qm i ) >/dev/null 2>&1
LED="$WD/.supervisor/postmortem/results.jsonl"
READ_PM="$HERE/read-postmortem.sh"

# 1st emit: DEGRADED — no --changed-paths-json / --number / size args (fetch failed).
bash "$H" learning-emit "$LED" \
  --repo "acme/widgets" --pr-url "$PR" --run-id "run12" --item "item-l" \
  --fix-cycles 4 --drain-result READY \
  --repeat-check-failure true --unresolved-bot-feedback false \
  --summary "degraded: gh pr view failed"
# 2nd emit: CORRECTIVE — same run_id+item+pr_url+source, now WITH the real data.
bash "$H" learning-emit "$LED" \
  --repo "acme/widgets" --number 126 --pr-url "$PR" --run-id "run12" --item "item-l" \
  --fix-cycles 4 --drain-result READY \
  --repeat-check-failure true --unresolved-bot-feedback false \
  --changed-paths-json '["src/corrected.ts"]' --additions 9 --deletions 3 --changed-files 1 \
  --summary "corrective: full data"

# The load-bearing assertion: the REAL reader now returns a prior-churn hit for the path,
# and the ledger carries exactly ONE complete (visible) line — no duplicate good lines.
READER_OUT="$( cd "$WD" && bash "$READ_PM" "src/corrected.ts" 2>/dev/null )"
N_COMPLETE="$(jq -R 'fromjson? // empty' "$LED" 2>/dev/null \
  | jq -s '[ .[] | select(((.changed_paths // []) | length) > 0) ] | length' 2>/dev/null)"
if grep -q "src/corrected.ts" < <(printf '%s' "$READER_OUT") && [ "$N_COMPLETE" = "1" ]; then
  ok "degraded-then-corrective: corrective emit NOT skipped and read-postmortem.sh returns it (exactly ONE complete line)"
else
  no "degraded-then-corrective wrong (reader_out='$READER_OUT' n_complete='$N_COMPLETE' ledger='$(cat "$LED" 2>/dev/null)')"
fi

# F12b. MUTATION CONTROL — proves F12 is load-bearing, not vacuously green. Pre-seed a
#       ledger with the OLD (pre-discriminator) degraded key shape, i.e. byte-for-byte
#       what the buggy version wrote for PR #126. Under the old "any key match ⇒ skip"
#       rule the corrective emit is suppressed and the reader stays silent forever;
#       under the fix the legacy degraded line is a match that does NOT block a complete
#       emit. BEFORE must be empty and AFTER must hit — if the skip rule ever regresses,
#       this case flips to FAIL.
WD2="$(mktemp -d)"
( cd "$WD2" && git init -q && git config user.email t@t && git config user.name t \
    && git remote add origin https://github.com/acme/widgets.git \
    && echo i > f && git add f && git commit -qm i ) >/dev/null 2>&1
LED2="$WD2/.supervisor/postmortem/results.jsonl"; mkdir -p "$(dirname "$LED2")"
LEGACY_KEY="$(jq -rn --arg a run13 --arg b item-m --arg c "$PR" --arg d automate_drain \
  '[$a,$b,$c,$d] | join("\u001f")')"
NOW_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq -cn --arg k "$LEGACY_KEY" --arg u "$PR" --arg ts "$NOW_TS" \
  '{schema_version:1, ts:$ts, repo:"acme/widgets", number:0, review_rounds:4,
    categories:[{round:4,class:"drain_churn",self_heal_miss:true,flow_stage:"self_heal",evidence:"legacy"}],
    self_heal_misses:1, changed_paths:[], pr_url:$u,
    source:"automate_drain", automate_key:$k}' > "$LED2"
BEFORE="$( cd "$WD2" && bash "$READ_PM" "src/corrected.ts" 2>/dev/null )"
bash "$H" learning-emit "$LED2" \
  --repo "acme/widgets" --number 126 --pr-url "$PR" --run-id "run13" --item "item-m" \
  --fix-cycles 4 --drain-result READY \
  --repeat-check-failure true --unresolved-bot-feedback false \
  --changed-paths-json '["src/corrected.ts"]' --additions 9 --deletions 3 --changed-files 1 \
  --summary "corrective over a LEGACY degraded key"
AFTER="$( cd "$WD2" && bash "$READ_PM" "src/corrected.ts" 2>/dev/null )"
if [ -z "$BEFORE" ] && grep -q "src/corrected.ts" < <(printf '%s' "$AFTER"); then
  ok "mutation control: a LEGACY (pre-discriminator) degraded key is invisible BEFORE and correctable AFTER (skip rule is load-bearing)"
else
  no "legacy-degraded correction wrong (before='$BEFORE' after='$AFTER' ledger='$(cat "$LED2" 2>/dev/null)')"
fi

# F12c. No-regression on the two skip arms the fix must NOT loosen: a DEGRADED emit
#       AFTER a complete one must be skipped (never regress a good line to an invisible
#       one), and a second COMPLETE emit must be skipped (at most one good line).
bash "$H" learning-emit "$LED2" \
  --repo "acme/widgets" --pr-url "$PR" --run-id "run13" --item "item-m" \
  --fix-cycles 4 --drain-result READY --summary "late degraded retry"
bash "$H" learning-emit "$LED2" \
  --repo "acme/widgets" --number 126 --pr-url "$PR" --run-id "run13" --item "item-m" \
  --fix-cycles 4 --drain-result READY \
  --changed-paths-json '["src/corrected.ts"]' --additions 9 --deletions 3 --changed-files 1 \
  --summary "duplicate complete"
if [ "$(wc -l < "$LED2" | tr -d ' ')" = "2" ]; then
  ok "no-regression: degraded-after-complete AND complete-after-complete are both skipped (ledger stays at 2 lines)"
else
  no "skip-arm regression (lines=$(wc -l < "$LED2" 2>/dev/null | tr -d ' ') ledger='$(cat "$LED2" 2>/dev/null)')"
fi
rm -rf "$WD" "$WD2"

# F13. The REALISTIC degraded shape: --number IS passed. F12/F12b/F12c all degrade by
#      omitting --number, which matches the helper's internal default but NOT the real
#      /automate invocation: skills/automate-loop/SKILL.md 6 derives `repo` AND `number`
#      from pr_url in the "inputs the engine already holds" bullet, BEFORE and independent
#      of "the ONE added fetch" that is the thing that actually degrades. So a
#      contract-compliant degraded emit carries the REAL number, and the degraded and
#      corrective lines SHARE the repo#number key that build-loop-evidence.sh and
#      measure-heal-signal.py join on. Pins that the correction still lands in that shape
#      (the earlier "number:0 quarantines the degraded line" rationale was wrong).
WD3="$(mktemp -d)"
( cd "$WD3" && git init -q && git config user.email t@t && git config user.name t \
    && git remote add origin https://github.com/acme/widgets.git \
    && echo i > f && git add f && git commit -qm i ) >/dev/null 2>&1
LED3="$WD3/.supervisor/postmortem/results.jsonl"
# Degraded, but WITH the pr_url-derived --number (only the fetch-dependent args degrade).
bash "$H" learning-emit "$LED3" \
  --repo "acme/widgets" --number 77 --pr-url "$PR" --run-id "run14" --item "item-n" \
  --fix-cycles 2 --drain-result READY \
  --changed-paths-json '[]' --additions 0 --deletions 0 --changed-files 0 \
  --summary "degraded WITH real number"
# Corrective, after a resume that added fix cycles (2 -> 5): the floor RISES.
bash "$H" learning-emit "$LED3" \
  --repo "acme/widgets" --number 77 --pr-url "$PR" --run-id "run14" --item "item-n" \
  --fix-cycles 5 --drain-result READY \
  --changed-paths-json '["src/shared.ts"]' --additions 7 --deletions 2 --changed-files 1 \
  --summary "corrective WITH real number"
N3="$(wc -l < "$LED3" | tr -d ' ')"
SAME_KEY="$(jq -R 'fromjson? // empty' "$LED3" 2>/dev/null \
  | jq -s '[ .[] | ((.repo|ascii_downcase) + "#" + (.number|tostring)) ] | unique | length' 2>/dev/null)"
VIS3="$( cd "$WD3" && bash "$READ_PM" "src/shared.ts" 2>/dev/null )"
if [ "$N3" = "2" ] && [ "$SAME_KEY" = "1" ] && grep -q "src/shared.ts" < <(printf '%s' "$VIS3"); then
  ok "realistic degraded shape (--number passed): correction still appends, both lines SHARE repo#number, reader returns the complete one"
else
  no "realistic-degraded wrong (lines='$N3' distinct_repo_number_keys='$SAME_KEY' reader='$VIS3')"
fi

# F13b. The downstream consequence of F13, shown at the EMIT site: with both lines under ONE
#       repo#number key, a first-wins join reports the STALE lower review_rounds. Append order
#       is degraded(2) then complete(5), so `head -1` yields 2 and floor-raising yields 5.
#       SCOPE — read this before trusting it: the jq below is a hand-copied MIRROR of
#       build-loop-evidence.sh's projection + representative pick, and a mirror can silently
#       drift from the script it models (the exact objection F12 raises against reader_select).
#       It is kept only to make the trap legible next to the emit it originates from. The
#       AUTHORITATIVE regression net for that join is test-build-loop-evidence.sh case (13),
#       which drives the REAL builder over a two-line fixture; if this mirror and case (13)
#       ever disagree, case (13) is right.
PMPROJ="$(jq -R 'fromjson? // empty' "$LED3" 2>/dev/null | jq -c '
  { key: (((.repo // "") | tostring | ascii_downcase) + "#" + ((.number // "") | tostring)),
    review_rounds: (.review_rounds // null), ts: ((.ts // "") | tostring) }')"
FIRST_WINS="$(printf '%s\n' "$PMPROJ" | head -1 | jq -r '.review_rounds')"
FLOOR_WINS="$(printf '%s\n' "$PMPROJ" | jq -s -r 'max_by([(.review_rounds // -1), (.ts // "")]) | .review_rounds')"
if [ "$FIRST_WINS" = "2" ] && [ "$FLOOR_WINS" = "5" ]; then
  ok "floor-raising join is load-bearing: first-wins would report the STALE 2, max-review_rounds reports the true 5"
else
  no "floor-raising join wrong (first_wins='$FIRST_WINS' floor_wins='$FLOOR_WINS')"
fi
rm -rf "$WD3"

# F13c. A second DEGRADED emit when ONLY a degraded line exists (no complete line yet).
#       F12c exercises the degraded skip arm only in a ledger that ALSO holds a complete
#       line, so this pins the arm in isolation: still exactly one line, still no duplicate
#       invisible entry.
WD4="$(mktemp -d)"; LED4="$WD4/results.jsonl"
for i in 1 2; do
  bash "$H" learning-emit "$LED4" \
    --repo "acme/widgets" --number 78 --pr-url "$PR" --run-id "run15" --item "item-o" \
    --fix-cycles 1 --drain-result READY --summary "degraded twice"
done
if [ "$(wc -l < "$LED4" | tr -d ' ')" = "1" ]; then
  ok "degraded-after-degraded (no complete line present): skipped ⇒ exactly ONE line"
else
  no "degraded-twice wrong (lines=$(wc -l < "$LED4" 2>/dev/null | tr -d ' '))"
fi
rm -rf "$WD4"

# F13d. changed_paths of only EMPTY strings is DEGRADED, not complete. An empty string is
#       not a usable path — read-postmortem.sh drops empty query paths before matching, so
#       `[""]` is exactly as invisible as `[]`. Classing it complete would re-open this very
#       defect: an unusable line permanently blocking its own correction.
WD5="$(mktemp -d)"; LED5="$WD5/results.jsonl"
bash "$H" learning-emit "$LED5" \
  --repo "acme/widgets" --number 79 --pr-url "$PR" --run-id "run16" --item "item-p" \
  --fix-cycles 1 --drain-result READY --changed-paths-json '[""]' --summary "empty-string path"
bash "$H" learning-emit "$LED5" \
  --repo "acme/widgets" --number 79 --pr-url "$PR" --run-id "run16" --item "item-p" \
  --fix-cycles 1 --drain-result READY --changed-paths-json '["src/real.ts"]' --summary "corrective"
if [ "$(wc -l < "$LED5" | tr -d ' ')" = "2" ] \
   && [ "$(tail -1 "$LED5" | jq -r '.changed_paths[0]')" = "src/real.ts" ]; then
  ok "empty-string-only changed_paths is DEGRADED (not complete) — it cannot block its own correction"
else
  no "empty-string-path classification wrong (lines=$(wc -l < "$LED5" 2>/dev/null | tr -d ' ') ledger='$(cat "$LED5" 2>/dev/null)')"
fi
rm -rf "$WD5"

# F14–F19. --self-heal-rounds (the Phase 4.5 self-heal churn the PR absorbed BEFORE the
#          drain; the OBSERVED SUPERVISOR_RESULT.heal_iterations). The PR #267 shape:
#          self-heal round 1 FAIL → fix → round 2 PASS, drain 0 fix cycles — before this
#          flag the line read review_rounds:0 + categories:[] and the reader called the
#          most-churned area clean. Every visibility claim below runs the REAL
#          read-postmortem.sh (not the reader_select mirror) in a throwaway repo whose
#          origin resolves to the emitted line's repo, ledger at the reader's default path.
SHR_PR="https://github.com/acme/widgets/pull/267"
SHR_ITEM=".supervisor/requirements/automate-followups/01-learning-emit-counts-self-heal-rounds.md"
# shr_emit <helper> <ledger> <run_id> [extra learning-emit args...] — the AC1 base call.
shr_emit() {
  local helper="$1" led="$2" rid="$3"; shift 3
  bash "$helper" learning-emit "$led" \
    --repo "acme/widgets" --number 267 --pr-url "$SHR_PR" --run-id "$rid" --item "$SHR_ITEM" \
    --repeat-check-failure false --unresolved-bot-feedback false \
    --changed-paths-json '["src/heal.ts","src/other.ts"]' --additions 5 --deletions 1 --changed-files 2 \
    --plugin-version 9.9.9 --branch feat/x "$@"
}
# shr_repo — a throwaway git repo whose origin makes the reader's CUR_REPO acme/widgets.
shr_repo() {
  local d; d="$(mktemp -d)"
  ( cd "$d" && git init -q && git config user.email t@t && git config user.name t \
      && git remote add origin https://github.com/acme/widgets.git \
      && echo i > f && git add f && git commit -qm i ) >/dev/null 2>&1
  printf '%s' "$d"
}
# shr_ac1_holds <helper> — 0 iff the AC1 claim holds for <helper>: the emitted line carries
# self_heal_rounds:2 + review_rounds:0 + exactly one self_heal_churn{round:2} entry, AND the
# REAL reader prints `self_heal_churn (1)` on its classes line and `1` on its rounds line.
# Parametrised on the helper so the F19 mutant is judged by the identical predicate.
SHR_OUT=""; SHR_LINE=""
shr_ac1_holds() {
  local helper="$1" d led
  d="$(shr_repo)"; led="$d/.supervisor/postmortem/results.jsonl"
  shr_emit "$helper" "$led" "run-shr-ac1" --self-heal-rounds 2 --fix-cycles 0 --drain-result READY
  SHR_LINE="$(cat "$led" 2>/dev/null)"
  SHR_OUT="$( cd "$d" && bash "$READ_PM" "src/heal.ts" 2>/dev/null )"
  rm -rf "$d"
  [ "$(printf '%s' "$SHR_LINE" | jq -r '.self_heal_rounds' 2>/dev/null)" = "2" ] || return 1
  [ "$(printf '%s' "$SHR_LINE" | jq -r '.review_rounds' 2>/dev/null)" = "0" ] || return 1
  [ "$(printf '%s' "$SHR_LINE" | jq -c '[.categories[] | {class, round}]' 2>/dev/null)" \
      = '[{"class":"self_heal_churn","round":2}]' ] || return 1
  grep -qxF -- "- recurring root-cause classes: self_heal_churn (1)" < <(printf '%s\n' "$SHR_OUT") || return 1
  grep -qE -- '^- prior churn rounds: 1 \(' < <(printf '%s\n' "$SHR_OUT") || return 1
  return 0
}

# F14 (AC1). self-heal 2, drain 0 ⇒ self_heal_rounds:2, review_rounds:0, ONE self_heal_churn
#      entry — and the REAL reader surfaces it as a prior-churn hit (the false-0 closed).
if shr_ac1_holds "$H"; then
  ok "self-heal-rounds: --self-heal-rounds 2 + drain 0 ⇒ self_heal_rounds:2, review_rounds:0, one self_heal_churn(round 2); REAL reader prints 'self_heal_churn (1)' + rounds 1"
else
  no "self-heal-rounds AC1 wrong (line='$SHR_LINE' reader='$SHR_OUT')"
fi

# F15 (AC2). BACK-COMPAT PIN: the same call WITHOUT the flag is byte-identical (after
#      deleting ts) to the PRE-CHANGE helper's line, and carries no self_heal_rounds key.
#      Frozen golden = `git show 05ad3057a9628992e7f7fbf6f3f62868ca97f85a:loomwright/scripts/automate-helpers.sh`
#      run on these exact args, piped through `jq -c 'del(.ts)'` (the pinned base commit,
#      never a moving origin/main). A frozen literal, so a shallow CI clone that lacks the
#      base commit still enforces it; when the base commit IS reachable the live base helper
#      is ALSO run as a cross-check that the golden was transcribed correctly.
SHR_GOLDEN='{"schema_version":1,"repo":"acme/widgets","number":267,"agent_generated_guess":true,"review_rounds":0,"additions":5,"deletions":1,"changed_files":2,"categories":[],"self_heal_misses":0,"flow_stages":{"launch_pad":0,"worker":0,"self_heal":0,"unknowable":0},"summary":"automate drain: no churn","plugin_version":"9.9.9","pr_url":"https://github.com/acme/widgets/pull/267","branch":"feat/x","changed_paths":["src/heal.ts","src/other.ts"],"brief_path":null,"job_path":null,"source":"automate_drain","automate_key":"run-shr-ac2\u001f.supervisor/requirements/automate-followups/01-learning-emit-counts-self-heal-rounds.md\u001fhttps://github.com/acme/widgets/pull/267\u001fautomate_drain\u001fcomplete"}'
WD6="$(mktemp -d)"
shr_emit "$H" "$WD6/new.jsonl" "run-shr-ac2" --fix-cycles 0 --drain-result READY
NEW_NOFLAG="$(jq -c 'del(.ts)' "$WD6/new.jsonl" 2>/dev/null)"
HAS_KEY="$(jq -r 'has("self_heal_rounds")' "$WD6/new.jsonl" 2>/dev/null)"
BASE_REV="05ad3057a9628992e7f7fbf6f3f62868ca97f85a"
BASE_XCHECK="skipped (base commit not reachable — frozen golden is authoritative)"
if git -C "$HERE" cat-file -e "$BASE_REV^{commit}" 2>/dev/null \
   && git -C "$HERE" show "$BASE_REV:loomwright/scripts/automate-helpers.sh" > "$WD6/base-helpers.sh" 2>/dev/null \
   && [ -s "$WD6/base-helpers.sh" ]; then
  shr_emit "$WD6/base-helpers.sh" "$WD6/base.jsonl" "run-shr-ac2" --fix-cycles 0 --drain-result READY
  if [ "$(jq -c 'del(.ts)' "$WD6/base.jsonl" 2>/dev/null)" = "$SHR_GOLDEN" ]; then
    BASE_XCHECK="ok"
  else
    BASE_XCHECK="MISMATCH"
  fi
fi
if [ "$NEW_NOFLAG" = "$SHR_GOLDEN" ] && [ "$HAS_KEY" = "false" ] && [ "$BASE_XCHECK" != "MISMATCH" ]; then
  ok "self-heal-rounds back-compat: no flag ⇒ byte-identical (minus ts) to the pre-change helper's line, no self_heal_rounds key (live base cross-check: $BASE_XCHECK)"
else
  no "self-heal-rounds back-compat wrong (has_key='$HAS_KEY' base_xcheck='$BASE_XCHECK' new='$NEW_NOFLAG')"
fi
rm -rf "$WD6"

# F16 (AC3). normalization is fail-SAFE: abc / -1 / 1.5 / "" ⇒ exit 0, line emitted,
#      self_heal_rounds:0, NO self_heal_churn entry. And the restated zero-rule: an explicit
#      0 with drain 0 READY ⇒ self_heal_rounds:0, review_rounds:0, categories:[] exactly.
SHR_BAD=""
for v in "abc" "-1" "1.5" ""; do
  WD7="$(mktemp -d)"; LED7="$WD7/results.jsonl"
  run_h shr_emit "$H" "$LED7" "run-shr-ac3" --self-heal-rounds "$v" --fix-cycles 0 --drain-result READY
  if [ "$RUN_RC" -ne 0 ] || [ "$(wc -l < "$LED7" 2>/dev/null | tr -d ' ')" != "1" ] \
     || [ "$(jq -r '.self_heal_rounds' "$LED7" 2>/dev/null)" != "0" ] \
     || [ "$(jq -r '[.categories[] | select(.class == "self_heal_churn")] | length' "$LED7" 2>/dev/null)" != "0" ]; then
    SHR_BAD="$SHR_BAD [v='$v' rc=$RUN_RC line=$(cat "$LED7" 2>/dev/null)]"
  fi
  rm -rf "$WD7"
done
WD7="$(mktemp -d)"; LED7="$WD7/results.jsonl"
shr_emit "$H" "$LED7" "run-shr-ac3z" --self-heal-rounds 0 --fix-cycles 0 --drain-result READY
if [ -z "$SHR_BAD" ] \
   && [ "$(jq -r '.self_heal_rounds' "$LED7")" = "0" ] \
   && [ "$(jq -r '.review_rounds' "$LED7")" = "0" ] \
   && [ "$(jq -c '.categories' "$LED7")" = "[]" ]; then
  ok "self-heal-rounds normalization: abc/-1/1.5/\"\" ⇒ exit 0 + self_heal_rounds:0 + no self_heal_churn; explicit 0 + drain 0 ⇒ categories:[] exactly (zero-rule)"
else
  no "self-heal-rounds normalization/zero-rule wrong (bad=$SHR_BAD zero_line='$(cat "$LED7" 2>/dev/null)')"
fi
rm -rf "$WD7"

# F16b. surrounding whitespace is trimmed before the digit check (a grep/awk-extracted
#       " 2" / "2 " / "3\n" must NOT be silently recorded as 0 — the false-0 this item
#       exists to prevent); INTERNAL whitespace ("1 2") and whitespace-only still ⇒ 0.
SHR_WS_BAD=""
for pair in " 2|2" "2 |2" $'3\n|3' $'\t4 |4' "1 2|0" "  |0"; do
  v="${pair%|*}"; want="${pair##*|}"
  WD7="$(mktemp -d)"; LED7="$WD7/results.jsonl"
  run_h shr_emit "$H" "$LED7" "run-shr-ws" --self-heal-rounds "$v" --fix-cycles 0 --drain-result READY
  got="$(jq -r '.self_heal_rounds' "$LED7" 2>/dev/null)"
  if [ "$RUN_RC" -ne 0 ] || [ "$got" != "$want" ]; then
    SHR_WS_BAD="$SHR_WS_BAD [v='$v' want=$want got=$got rc=$RUN_RC]"
  fi
  rm -rf "$WD7"
done
if [ -z "$SHR_WS_BAD" ]; then
  ok "self-heal-rounds trims surrounding whitespace (' 2'/'2 '/'3\\n'/tab ⇒ value) while internal/whitespace-only ⇒ 0"
else
  no "self-heal-rounds whitespace handling wrong:$SHR_WS_BAD"
fi

# F17 (AC3b + AC4). ordering — self-heal precedes the drain, and review_rounds stays
#      DRAIN-ONLY. 1 + zero-cycle ESCALATED ⇒ [self_heal_churn(1), drain_escalation(1)],
#      review_rounds:1. 1 + fix_cycles 3 READY ⇒ [self_heal_churn(1), drain_churn(3)],
#      review_rounds:3, and the REAL reader's rounds line reports 2.
WD8="$(mktemp -d)"; LED8="$WD8/esc.jsonl"
shr_emit "$H" "$LED8" "run-shr-ac3b" --self-heal-rounds 1 --fix-cycles 0 --drain-result ESCALATED
D8="$(shr_repo)"; LED8B="$D8/.supervisor/postmortem/results.jsonl"
shr_emit "$H" "$LED8B" "run-shr-ac4" --self-heal-rounds 1 --fix-cycles 3 --drain-result READY
READ8="$( cd "$D8" && bash "$READ_PM" "src/heal.ts" 2>/dev/null )"
if [ "$(jq -r '.review_rounds' "$LED8")" = "1" ] \
   && [ "$(jq -r '.self_heal_rounds' "$LED8")" = "1" ] \
   && [ "$(jq -c '[.categories[] | {class, round}]' "$LED8")" = '[{"class":"self_heal_churn","round":1},{"class":"drain_escalation","round":1}]' ] \
   && [ "$(jq -r '.review_rounds' "$LED8B")" = "3" ] \
   && [ "$(jq -r '.self_heal_rounds' "$LED8B")" = "1" ] \
   && [ "$(jq -r '.flow_stages.self_heal' "$LED8B")" = "3" ] \
   && [ "$(jq -c '[.categories[] | {class, round}]' "$LED8B")" = '[{"class":"self_heal_churn","round":1},{"class":"drain_churn","round":3}]' ] \
   && grep -qE -- '^- prior churn rounds: 2 \(' < <(printf '%s\n' "$READ8") \
   && grep -qF "self_heal_churn (1)" < <(grep -E -- '^- recurring root-cause classes: ' < <(printf '%s\n' "$READ8")) \
   && grep -qF "drain_churn (1)" < <(grep -E -- '^- recurring root-cause classes: ' < <(printf '%s\n' "$READ8")); then
  ok "self-heal-rounds ordering: self_heal_churn precedes drain_escalation/drain_churn; review_rounds + flow_stages.self_heal stay drain-only; REAL reader rounds 2"
else
  no "self-heal-rounds ordering wrong (esc='$(cat "$LED8" 2>/dev/null)' combined='$(cat "$LED8B" 2>/dev/null)' reader='$READ8')"
fi
rm -rf "$WD8" "$D8"

# F18 (AC5). idempotency: the automate_key is byte-identical with and without the flag,
#      and a re-entry for the same run/item/PR writes nothing new — in BOTH orders.
WD9="$(mktemp -d)"
shr_emit "$H" "$WD9/a.jsonl" "run-shr-ac5" --self-heal-rounds 2 --fix-cycles 1 --drain-result READY
shr_emit "$H" "$WD9/b.jsonl" "run-shr-ac5" --fix-cycles 1 --drain-result READY
KEY_A="$(jq -r '.automate_key' "$WD9/a.jsonl" 2>/dev/null)"
KEY_B="$(jq -r '.automate_key' "$WD9/b.jsonl" 2>/dev/null)"
# a.jsonl already holds the WITH-flag line: re-enter with AND without the flag.
shr_emit "$H" "$WD9/a.jsonl" "run-shr-ac5" --self-heal-rounds 2 --fix-cycles 1 --drain-result READY
shr_emit "$H" "$WD9/a.jsonl" "run-shr-ac5" --fix-cycles 1 --drain-result READY
# b.jsonl already holds the WITHOUT-flag line: re-enter WITH the flag.
shr_emit "$H" "$WD9/b.jsonl" "run-shr-ac5" --self-heal-rounds 2 --fix-cycles 1 --drain-result READY
if [ -n "$KEY_A" ] && [ "$KEY_A" = "$KEY_B" ] \
   && [ "$(wc -l < "$WD9/a.jsonl" | tr -d ' ')" = "1" ] \
   && [ "$(wc -l < "$WD9/b.jsonl" | tr -d ' ')" = "1" ]; then
  ok "self-heal-rounds idempotency: automate_key identical with/without the flag; re-entry (either order) writes nothing new"
else
  no "self-heal-rounds idempotency wrong (key_a='$KEY_A' key_b='$KEY_B' a_lines=$(wc -l < "$WD9/a.jsonl" | tr -d ' ') b_lines=$(wc -l < "$WD9/b.jsonl" | tr -d ' '))"
fi
rm -rf "$WD9"

# F19 (AC6). MUTATION CONTROL — proves F14 is load-bearing: a COPY of the helper whose
#      parsed --self-heal-rounds value is never plumbed into the record (the jq arg is
#      forced to 0) must FAIL the identical shr_ac1_holds predicate. The mutant is trusted
#      only when non-empty, differs from the original, and passes `bash -n` (lesson
#      fa32a308: an unvalidated mutant that silently equals the original, or does not
#      parse, "fails" for the wrong reason and proves nothing).
WD10="$(mktemp -d)"; MUT="$WD10/automate-helpers.sh"
sed 's/--argjson shr "\$shr_json"/--argjson shr 0/' "$H" > "$MUT"
if [ -s "$MUT" ] && ! cmp -s "$H" "$MUT" && bash -n "$MUT" 2>/dev/null \
   && [ "$(grep -c -- '--argjson shr 0' "$MUT")" = "1" ]; then
  if shr_ac1_holds "$MUT"; then
    no "self-heal-rounds mutation control: F14's predicate still PASSES against a mutant that never plumbs the value (vacuous)"
  elif shr_ac1_holds "$H"; then
    ok "self-heal-rounds mutation control: a validated mutant (value forced to 0) FAILS the F14 predicate while the real helper passes it"
  else
    no "self-heal-rounds mutation control: real helper no longer passes the F14 predicate"
  fi
else
  no "self-heal-rounds mutation control: mutant invalid (empty / identical to original / bash -n failed / anchor not found)"
fi
rm -rf "$WD10"

# =============================================================================
echo "== G. brief-repair (fail-SAFE, evidence-positive engine seam; ONE mover) =="

SKILL_FILE="$HERE/../skills/automate-loop/SKILL.md"
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

# G7. AC-9(a) static seam pins on the SKILL, with per-line mutants. The assertion
#     helper takes the SKILL path so the SAME code runs on the real file and on
#     each mutant.
seam_has() {  # seam_has <skill_path> <anchor> -> 0 when the line starting with <anchor> contains brief-repair
  local line; line="$(grep -F -- "$2" "$1" | head -1)"
  [ -n "$line" ] || return 1
  case "$line" in *brief-repair*) return 0 ;; *) return 1 ;; esac
}
seam_has "$SKILL_FILE" '1. **RECONCILE**' && ok "G7 AC-2 prose seam: SKILL §6 step 1 (RECONCILE) names brief-repair" || no "G7 §6 step 1 lacks brief-repair"
seam_has "$SKILL_FILE" '5. **SYNC**'      && ok "G7 AC-1 prose seam: SKILL §6 step 5 (SYNC) names brief-repair"      || no "G7 §6 step 5 lacks brief-repair"
grep -q 'brief-repair' < <(grep -F -- '**PR merged?**' "$SKILL_FILE") && ok "G7 §4 step 2 'PR merged?' bullet references the repair" || no "G7 §4 'PR merged?' bullet lacks the reference"
skill_mutant() {  # skill_mutant <anchor> <out> — strip every `brief-repair` token from the anchored line only
  awk -v a="$1" 'index($0,a)==1 {gsub(/brief-repair/,"brief_removed")} {print}' "$SKILL_FILE" > "$2"
}
MW="$(mktemp -d)"
skill_mutant '5. **SYNC**' "$MW/no-step5.md"; skill_mutant '1. **RECONCILE**' "$MW/no-step1.md"
for m in no-step5 no-step1; do
  [ -s "$MW/$m.md" ] && ! cmp -s "$SKILL_FILE" "$MW/$m.md" || no "G7 mutant $m not gated (empty or identical)"
done
if ! seam_has "$MW/no-step5.md" '5. **SYNC**' && seam_has "$MW/no-step5.md" '1. **RECONCILE**'; then ok "G7 (mutant) token gone from step 5 only ⇒ AC-1 pin red, AC-2 pin green"; else no "G7 step-5 mutant not discriminated"; fi
if ! seam_has "$MW/no-step1.md" '1. **RECONCILE**' && seam_has "$MW/no-step1.md" '5. **SYNC**'; then ok "G7 (mutant) token gone from step 1 only ⇒ AC-2 pin red, AC-1 pin green"; else no "G7 step-1 mutant not discriminated"; fi
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

# =============================================================================
echo "== H. reconcile-status (queue-hygiene/01: dry-run-default requirement Status reconciler) =="

# rs_key <s> — the stub's filename-safe key (mirrors the stub script's own key()).
rs_key() { printf '%s' "$1" | tr -c 'A-Za-z0-9' '_'; }

# rs_stub_bin <dir> — a gh stub keyed on `pr list --search <term>` and
# `pr view <url>`, reading canned JSON from $GH_STUB_DIR/list-<key>.json /
# view-<key>.json (absent list ⇒ "[]", absent view ⇒ exit 1), plus `api …
# repos/<o>/<r>/pulls/<n>/files` (the >100-file diff fallback) from
# api-<key>.txt, one path per line (absent ⇒ exit 1). Dedicated to
# this section (not make_stub_bin) because reconcile-status's evidence-lookup
# needs TWO gh verbs discriminated by argument, not one fixed response file.
rs_stub_bin() {
  local bin="$1"
  mkdir -p "$bin"
  cat > "$bin/gh" <<'STUB'
#!/usr/bin/env bash
set -u
key() { printf '%s' "$1" | tr -c 'A-Za-z0-9' '_'; }
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "list" ]; then
  shift 2; term=""
  while [ "$#" -gt 0 ]; do case "$1" in --search) term="${2:-}"; shift 2 ;; *) shift ;; esac; done
  f="$GH_STUB_DIR/list-$(key "$term").json"
  [ -f "$f" ] && cat "$f" || printf '[]'
  exit 0
fi
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "view" ]; then
  url="${3:-}"
  f="$GH_STUB_DIR/view-$(key "$url").json"
  [ -f "$f" ] && cat "$f" || exit 1
  exit 0
fi
if [ "${1:-}" = "api" ]; then
  ep=""
  for a in "$@"; do case "$a" in repos/*) ep="$a" ;; esac; done
  f="$GH_STUB_DIR/api-$(key "$ep").txt"
  [ -f "$f" ] && cat "$f" || exit 1
  exit 0
fi
exit 0
STUB
  chmod +x "$bin/gh"
}

# rs_repo — fixture root per AC-1/2/3/5/9: (a) done, (b) pending+merged+cited,
# (c) pending+open, (d) operator-run/, (e) 00-index. Returns "<repo>\t<rel_b>".
RS_URL="https://github.com/acme/widgets/pull/42"
rs_repo() {
  local r rq relb
  r="$(mktemp -d)"
  mkdir -p "$r/.supervisor/requirements/qh/operator-run" "$r/.supervisor/jobs/done" "$r/.supervisor/automate" "$r/bin" "$r/ghstub"
  rq="$r/.supervisor/requirements/qh"
  printf '# a\n\n## Status: done (PR #1, merge abcdef1)\n' > "$rq/01-a-done.md"
  relb=".supervisor/requirements/qh/02-b-merged.md"
  printf '# b\n\nSome prose.\n\n## Status: pending\n' > "$r/$relb"
  printf '# c\n\n## Status: pending\n' > "$rq/03-c-open.md"
  printf '# d\n\n## Status: pending\n' > "$rq/operator-run/04-d.md"
  printf '# index\n' > "$rq/00-index.md"
  rs_stub_bin "$r/bin"
  jq -n --arg url "$RS_URL" '[{url:$url}]' > "$r/ghstub/list-$(rs_key "$relb").json"
  jq -n --arg rel "$relb" --arg url "$RS_URL" \
    '{state:"MERGED",mergedAt:"2026-09-01T00:00:00Z",number:42,body:("Ships "+$rel),mergeCommit:{oid:"abcdef1234567890"},headRefName:"feature/b",changedFiles:1,files:[{path:"src/b.sh"}]}' \
    > "$r/ghstub/view-$(rs_key "$RS_URL").json"
  printf '[]' > "$r/ghstub/list-$(rs_key ".supervisor/requirements/qh/03-c-open.md").json"
  printf '%s\t%s' "$r" "$relb"
}
rs_run() {
  # rs_run <repo> <args...> — RUN_OUT / RUN_RC set. RS_H overrides the helper (mutation controls).
  local r="$1"; shift
  RUN_OUT="$(GH_STUB_DIR="$r/ghstub" PATH="$r/bin:$PATH" LOOMWRIGHT_GH_BIN=gh bash "${RS_H:-$H}" reconcile-status "$@" 2>/dev/null)"; RUN_RC=$?
}

# H1. AC-1: dry run over the 5-file fixture prints exactly ONE plan line (b), writes nothing.
IFS=$'\t' read -r R RELB <<<"$(rs_repo)"
BEFORE="$(cd "$R" && find .supervisor/requirements -type f -exec sh -c 'echo "$1" $(cksum < "$1")' _ {} \; | sort)"
rs_run "$R" "$R/.supervisor/requirements/qh"
nplan="$(printf '%s\n' "$RUN_OUT" | grep -c '^plan	')"
AFTER="$(cd "$R" && find .supervisor/requirements -type f -exec sh -c 'echo "$1" $(cksum < "$1")' _ {} \; | sort)"
if [ "$nplan" = "1" ] && grep -qF "plan	$RELB	done (PR #42, merge abcdef1)" < <(printf '%s\n' "$RUN_OUT") && [ "$BEFORE" = "$AFTER" ]; then
  ok "H1 AC-1: dry run prints exactly one plan line for (b), root untouched (diff -r equivalent)"
else
  no "H1 AC-1 wrong (nplan=$nplan out='$RUN_OUT' unchanged=$([ "$BEFORE" = "$AFTER" ] && echo y || echo n))"
fi
rm -rf "$R"

# H2. AC-2: --apply stamps (b) ONLY — §6 shape byte-for-byte, stale trailing
#     '## Status: pending' removed, is_done() true for (b) only.
IFS=$'\t' read -r R RELB <<<"$(rs_repo)"
rs_run "$R" "$R/.supervisor/requirements/qh" --apply
B="$R/$RELB"
if grep -qF '## Status: done (PR #42, merge abcdef1)' "$B" \
   && grep -qE '^- \*\*Completed:\*\* [0-9]{4}-' "$B" \
   && grep -qF -- '- **PR:** '"$RS_URL" "$B" \
   && ! grep -qE '^## Status:[[:space:]]*pending[[:space:]]*$' "$B"; then
  ok "H2 AC-2: (b) stamped byte-shape 'done (PR #n, merge sha7)' + Completed/Brief/PR, stale pending line removed"
else
  no "H2 AC-2 stamp shape wrong: $(cat "$B")"
fi
if grep -qE '^## Status:[[:space:]]*done\b' "$B" && ! grep -qE '^## Status:[[:space:]]*done\b' "$R/.supervisor/requirements/qh/03-c-open.md"; then
  ok "H2 is_done()-shape true for (b) only (c stays pending)"
else
  no "H2 (c) unexpectedly stamped"
fi
rm -rf "$R"

# H3. AC-3 mutation control: delete the path citation from (b)'s PR-body fixture ⇒ no plan line, no stamp.
IFS=$'\t' read -r R RELB <<<"$(rs_repo)"
jq -n --arg url "$RS_URL" '{state:"MERGED",mergedAt:"2026-09-01T00:00:00Z",number:42,body:"unrelated prose, no path here",mergeCommit:{oid:"abcdef1234567890"},headRefName:"feature/b",changedFiles:1,files:[{path:"src/b.sh"}]}' \
  > "$R/ghstub/view-$(rs_key "$RS_URL").json"
rs_run "$R" "$R/.supervisor/requirements/qh"
DRY_OUT="$RUN_OUT"
rs_run "$R" "$R/.supervisor/requirements/qh" --apply
if [ -z "$DRY_OUT" ] && ! grep -qE '^## Status:[[:space:]]*done\b' "$R/$RELB"; then
  ok "H3 AC-3 mutation control: citation deleted ⇒ no plan line, no stamp"
else
  no "H3 mutation control failed (dry='$DRY_OUT' apply_status=$(grep '^## Status' "$R/$RELB"))"
fi
rm -rf "$R"

# H4. AC-4: a run-file `# abandoned:` Queue row stamps done_with_escalation;
#     a row without the marker stamps nothing.
R="$(mktemp -d)"
mkdir -p "$R/.supervisor/requirements/qh" "$R/.supervisor/automate" "$R/.supervisor/jobs/done" "$R/bin" "$R/ghstub"
rs_stub_bin "$R/bin"
printf '# ab\n\n## Status: pending\n' > "$R/.supervisor/requirements/qh/05-abandoned.md"
printf '# nope\n\n## Status: pending\n' > "$R/.supervisor/requirements/qh/06-not-abandoned.md"
ABROW='- [x] .supervisor/requirements/qh/05-abandoned.md  # abandoned: owner dropped track 2026-09-01'
{
  printf '# run\n## Status: running\n## Queue\n'
  printf '%s\n' "$ABROW"
  printf -- '- [x] .supervisor/requirements/qh/06-not-abandoned.md  # skipped: unrelated\n'
  printf '## Progress\n'
} > "$R/.supervisor/automate/run1.md"
rs_run "$R" "$R/.supervisor/requirements/qh" --apply
if grep -qF -- "## Status: done_with_escalation — ABANDONED ($ABROW)" "$R/.supervisor/requirements/qh/05-abandoned.md" \
   && ! grep -qE '^## Status:[[:space:]]*done' "$R/.supervisor/requirements/qh/06-not-abandoned.md"; then
  ok "H4 AC-4: abandoned row stamps done_with_escalation verbatim; unmark row stamps nothing"
else
  no "H4 AC-4 wrong (ab=$(grep '^## Status' "$R/.supervisor/requirements/qh/05-abandoned.md") not=$(grep '^## Status' "$R/.supervisor/requirements/qh/06-not-abandoned.md" 2>/dev/null || echo none))"
fi
rm -rf "$R"

# H5. AC-5: never downgrades an existing done file — re-run leaves (a) byte-unchanged.
IFS=$'\t' read -r R RELB <<<"$(rs_repo)"
A="$R/.supervisor/requirements/qh/01-a-done.md"
BEFORE_A="$(cksum < "$A")"
rs_run "$R" "$R/.supervisor/requirements/qh" --apply
AFTER_A="$(cksum < "$A")"
if [ "$BEFORE_A" = "$AFTER_A" ]; then
  ok "H5 AC-5: an already-done file is byte-unchanged after a --apply pass"
else
  no "H5 AC-5: done file (a) was modified"
fi
rm -rf "$R"

# H6. brief-shipped is LISTED (info row), never promoted, on EITHER dry-run or --apply.
R="$(mktemp -d)"
mkdir -p "$R/.supervisor/requirements/qh" "$R/.supervisor/jobs/done" "$R/.supervisor/automate" "$R/bin" "$R/ghstub"
rs_stub_bin "$R/bin"
printf '# shipped\n\n## Status: brief-shipped\n\nJob done, ACs unverified.\n' > "$R/.supervisor/requirements/qh/07-shipped.md"
rs_run "$R" "$R/.supervisor/requirements/qh" --apply
if grep -qE '^info	.*07-shipped\.md	brief-shipped	' < <(printf '%s\n' "$RUN_OUT") \
   && grep -qE '^## Status:[[:space:]]*brief-shipped[[:space:]]*$' "$R/.supervisor/requirements/qh/07-shipped.md"; then
  ok "H6 brief-shipped: listed as an 'info' row, file untouched (never promoted) even under --apply"
else
  no "H6 brief-shipped wrong (out='$RUN_OUT')"
fi
rm -rf "$R"

# H7. The engine's own trail PR is never evidence (sibling defect of the
#     trail-PR-moves-main fix, run automate-2026-10-01-142337). A trail PR's
#     body lists every path it commits, so a body citation there is "committed",
#     never "shipped".
RS_TRAIL="https://github.com/acme/widgets/pull/321"
rs_trail_repo() {  # <trail headRefName> → "<repo>\t<draft rel>\t<req rel>"
  local r reld relq
  r="$(mktemp -d)"
  mkdir -p "$r/.supervisor/requirements/qh/proposed" "$r/.supervisor/jobs/done" "$r/.supervisor/automate" "$r/bin" "$r/ghstub"
  reld=".supervisor/requirements/qh/proposed/automate-2026-01-01-000000--01-a-abc123--dismissed-1b4e0236.md"
  relq=".supervisor/requirements/qh/01-a.md"
  printf '# Dismissed finding\n\n- **Decision:** follow-up\n> some finding\n' > "$r/$reld"
  printf '# a\n\n## Status: pending\n' > "$r/$relq"
  rs_stub_bin "$r/bin"
  jq -n --arg url "$RS_TRAIL" '[{url:$url}]' > "$r/ghstub/list-$(rs_key "$reld").json"
  jq -n --arg url "$RS_TRAIL" '[{url:$url}]' > "$r/ghstub/list-$(rs_key "$relq").json"
  # The diff is deliberately NOT the trail's real one (which commits the cited
  # files, all under .supervisor/): H8's diff rules would then exclude it too,
  # and the mutation control below could not isolate the branch-name rule.
  jq -n --arg d "$reld" --arg q "$relq" --arg h "$1" \
    '{state:"MERGED",mergedAt:"2026-09-30T00:00:00Z",number:321,body:("Trail paths:\n- "+$q+"\n- "+$d),mergeCommit:{oid:"6b388ae000000000"},headRefName:$h,changedFiles:1,files:[{path:"src/trail-fixture.sh"}]}' \
    > "$r/ghstub/view-$(rs_key "$RS_TRAIL").json"
  printf '%s\t%s\t%s' "$r" "$reld" "$relq"
}
IFS=$'\t' read -r R RELD RELQ <<<"$(rs_trail_repo chore/automate-2026-09-30-054439-trail-2)"
rs_run "$R" "$R/.supervisor/requirements/qh"
DRY_OUT="$RUN_OUT"
rs_run "$R" "$R/.supervisor/requirements/qh" --apply
if [ -z "$DRY_OUT" ] && [ -z "$RUN_OUT" ] && ! grep -q '^## Status' "$R/$RELD" && grep -qE '^## Status: pending$' "$R/$RELQ"; then
  ok "H7 a merged trail PR whose body cites a proposed/ draft and a Queue requirement is not evidence (no plan, no stamp)"
else
  no "H7 trail PR read as evidence (dry='$DRY_OUT' apply='$RUN_OUT')"
fi
# Mutation control: the exclusion neutered in a copy of the helper ⇒ the same fixture plans both files again.
RSM="$(mktemp -d)"; cp "$HERE"/*.sh "$HERE"/*.py "$RSM/" 2>/dev/null
sed 's/^    _rs_is_trail_branch "\$headref" && continue$/    :/' "$H" > "$RSM/automate-helpers.sh"
if cmp -s "$H" "$RSM/automate-helpers.sh"; then
  no "H7 mutation control: the exclusion line was not found (the sed no longer matches)"
else
  RS_H="$RSM/automate-helpers.sh" rs_run "$R" "$R/.supervisor/requirements/qh"
  if grep -qF "plan	$RELD	done (PR #321, merge 6b388ae)" <<<"$RUN_OUT" && grep -qF "plan	$RELQ	done (PR #321" <<<"$RUN_OUT"; then
    ok "H7 mutation control: without the trail-branch exclusion the draft and the requirement plan 'done (PR #321)' — the exclusion is load-bearing"
  else
    no "H7 mutation control: mutant did not reproduce the defect (out='$RUN_OUT') — H7 would be vacuous"
  fi
fi
rm -rf "$R" "$RSM"
# A trail candidate listed ahead of the real implementation PR is skipped, not fatal.
IFS=$'\t' read -r R RELD RELQ <<<"$(rs_trail_repo chore/automate-2026-09-30-054439-trail-2)"
jq -n --arg t "$RS_TRAIL" --arg u "$RS_URL" '[{url:$t},{url:$u}]' > "$R/ghstub/list-$(rs_key "$RELQ").json"
jq -n --arg q "$RELQ" '{state:"MERGED",mergedAt:"2026-09-01T00:00:00Z",number:42,body:("Ships "+$q),mergeCommit:{oid:"abcdef1234567890"},headRefName:"feature/a",changedFiles:1,files:[{path:"src/a.sh"}]}' \
  > "$R/ghstub/view-$(rs_key "$RS_URL").json"
rs_run "$R" "$R/.supervisor/requirements/qh"
if [ "$(printf '%s\n' "$RUN_OUT" | grep -c '^plan	')" = "1" ] && grep -qF "plan	$RELQ	done (PR #42, merge abcdef1)	PR body cites $RELQ" <<<"$RUN_OUT"; then
  ok "H7 a trail candidate ahead of the real PR is skipped; the plan names the implementation PR #42"
else
  no "H7 trail-then-real candidate order wrong (out='$RUN_OUT')"
fi
rm -rf "$R"
# The exclusion is the trail shape only: a near-miss branch name stays evidence.
IFS=$'\t' read -r R RELD RELQ <<<"$(rs_trail_repo chore/x-trail-final)"
rs_run "$R" "$R/.supervisor/requirements/qh"
grep -qF "plan	$RELQ	done (PR #321" <<<"$RUN_OUT" && ok "H7 near-miss branch chore/x-trail-final (no numeric suffix) is still evidence" || no "H7 near-miss excluded (out='$RUN_OUT')"
rm -rf "$R"

# H8. A body citation is evidence only when the PR's diff did not itself add or
#     modify the cited requirement; an all-.supervisor/ diff is never evidence;
#     an unreadable or incomplete diff is no evidence. (2026-10-03: PR #359,
#     chore/meta-scrub-cleanup, ADDED meta-sync-followups/04 as `## Status:
#     pending`, listed it in its body, and the dry run read "would stamp done
#     (PR #359)".)
RS_D="https://github.com/acme/widgets/pull/359"
RS_DREL=".supervisor/requirements/qh/04-scrub-safe-briefs.md"
rs_diff_repo() {  # <files_json_array> [changedFiles] → "<repo>"; PR #359 cites RS_DREL in its body
  local r
  r="$(mktemp -d)"
  mkdir -p "$r/.supervisor/requirements/qh" "$r/.supervisor/jobs/done" "$r/.supervisor/automate" "$r/bin" "$r/ghstub"
  printf '# scrub\n\n## Status: pending\n' > "$r/$RS_DREL"
  rs_stub_bin "$r/bin"
  jq -n --arg url "$RS_D" '[{url:$url}]' > "$r/ghstub/list-$(rs_key "$RS_DREL").json"
  jq -n --arg q "$RS_DREL" --argjson f "$1" --arg c "${2:-}" \
    '{state:"MERGED",mergedAt:"2026-10-02T00:00:00Z",number:359,body:("Queues:\n- "+$q),mergeCommit:{oid:"9a78b9c000000000"},headRefName:"chore/meta-scrub-cleanup",
      files:[$f[]|{path:.}],changedFiles:(if $c=="" then ($f|length) else ($c|tonumber) end)}' \
    > "$r/ghstub/view-$(rs_key "$RS_D").json"
  printf '%s' "$r"
}
rs_plans_359() { grep -qF "plan	$RS_DREL	done (PR #359, merge 9a78b9c)	PR body cites $RS_DREL" <<<"$RUN_OUT"; }
# rs_mutant <exact helper line> <replacement> — a copy of the helper with that ONE
# line replaced; RSM names the copy's dir. Returns 1 when the line is not found.
rs_mutant() {
  RSM="$(mktemp -d)"; cp "$HERE"/*.sh "$HERE"/*.py "$RSM/" 2>/dev/null
  OLD="$1" NEW="$2" awk '$0 == ENVIRON["OLD"] { print ENVIRON["NEW"]; next } { print }' "$H" > "$RSM/automate-helpers.sh"
  ! cmp -s "$H" "$RSM/automate-helpers.sh"
}
RS_TOUCH_LINE='    case "$body" in *"$rel"*) grep -qxF -- "$rel" <<<"$paths" || justification="PR body cites $rel" ;; esac'
RS_TOUCH_MUT='    case "$body" in *"$rel"*) justification="PR body cites $rel" ;; esac'
RS_SUP_LINE="    grep -qv '^\\.supervisor/' <<<\"\$paths\" || continue"

# H8a. The PR adds the requirement (plus a non-.supervisor file) and cites it ⇒ no plan, no stamp.
R="$(rs_diff_repo "[\"$RS_DREL\",\"docs/scrub.md\"]")"
rs_run "$R" "$R/.supervisor/requirements/qh"
DRY_OUT="$RUN_OUT"
rs_run "$R" "$R/.supervisor/requirements/qh" --apply
if [ -z "$DRY_OUT" ] && [ -z "$RUN_OUT" ] && grep -qE '^## Status: pending$' "$R/$RS_DREL"; then
  ok "H8a a PR whose diff adds the cited requirement is not evidence (no plan, no stamp under --apply)"
else
  no "H8a requirement-adding PR read as evidence (dry='$DRY_OUT' apply='$RUN_OUT')"
fi
# Mutation control: the diff-membership check removed ⇒ the same fixture plans 'done (PR #359)' again.
if rs_mutant "$RS_TOUCH_LINE" "$RS_TOUCH_MUT"; then
  RS_H="$RSM/automate-helpers.sh" rs_run "$R" "$R/.supervisor/requirements/qh"
  rs_plans_359 && ok "H8a mutation control: without the diff-membership check the requirement plans 'done (PR #359)' — the check is load-bearing" \
    || no "H8a mutation control: mutant did not reproduce the defect (out='$RUN_OUT') — H8a would be vacuous"
else
  no "H8a mutation control: the membership line was not found in the helper"
fi
rm -rf "$R" "$RSM"
# Control: the same PR without the requirement in its diff ⇒ the plan row.
R="$(rs_diff_repo '["docs/scrub.md"]')"
rs_run "$R" "$R/.supervisor/requirements/qh"
rs_plans_359 && ok "H8a control: the same citing PR without the requirement in its diff plans 'done (PR #359)'" || no "H8a control: no plan row (out='$RUN_OUT')"
rm -rf "$R"

# H8b. The real PR #359 shape (every changed file under .supervisor/, the requirement among them) ⇒ no plan.
R="$(rs_diff_repo "[\".supervisor/automate/automate-2026-09-01-232353.md\",\".supervisor/jobs/done/2026-10-02-x.md\",\"$RS_DREL\"]")"
rs_run "$R" "$R/.supervisor/requirements/qh"
[ -z "$RUN_OUT" ] && ok "H8b the PR #359 shape (all-.supervisor diff that adds the requirement) plans nothing" || no "H8b PR #359 shape planned (out='$RUN_OUT')"
rm -rf "$R"

# H8c. An all-.supervisor/ diff that does NOT touch the requirement is still not evidence.
R="$(rs_diff_repo '[".supervisor/jobs/done/2026-10-02-x.md",".supervisor/automate/run.md"]')"
rs_run "$R" "$R/.supervisor/requirements/qh"
if [ -z "$RUN_OUT" ]; then
  ok "H8c a citing PR whose changed files are all under .supervisor/ is not evidence"
else
  no "H8c all-.supervisor diff read as evidence (out='$RUN_OUT')"
fi
if rs_mutant "$RS_SUP_LINE" '    :'; then
  RS_H="$RSM/automate-helpers.sh" rs_run "$R" "$R/.supervisor/requirements/qh"
  rs_plans_359 && ok "H8c mutation control: without the all-.supervisor check the same fixture plans — the check is load-bearing" \
    || no "H8c mutation control: mutant did not reproduce (out='$RUN_OUT') — H8c would be vacuous"
else
  no "H8c mutation control: the all-.supervisor line was not found in the helper"
fi
rm -rf "$R" "$RSM"

# H8e. The all-.supervisor/ exclusion also holds on the BRANCH-SLUG path: a done/
#      brief points at the requirement and names PR #359, whose head branch ends in
#      the brief's slug and whose body does NOT cite the requirement.
rs_slug_repo() {  # <files_json_array> → "<repo>"
  local r v
  r="$(rs_diff_repo "$1")"
  v="$r/ghstub/view-$(rs_key "$RS_D").json"
  jq '.body = "no path cited here" | .headRefName = "feature/scrub-safe-briefs"' "$v" > "$r/v.json" && mv "$r/v.json" "$v"
  printf '# brief\n\n## Environment\n- **Source requirement:** %s\n\n## Outcome\n- **PR:** %s\n' "$RS_DREL" "$RS_D" \
    > "$r/.supervisor/jobs/done/2026-10-02-scrub-safe-briefs.md"
  printf '%s' "$r"
}
rs_slug_plans() { grep -qF "plan	$RS_DREL	done (PR #359, merge 9a78b9c)	head branch 'feature/scrub-safe-briefs' matches brief slug 'scrub-safe-briefs'" <<<"$RUN_OUT"; }
# Control: the same slug-matched PR with an implementation file in its diff ⇒ the plan row.
R="$(rs_slug_repo '["src/scrub.sh",".supervisor/jobs/done/2026-10-02-scrub-safe-briefs.md"]')"
rs_run "$R" "$R/.supervisor/requirements/qh"
rs_slug_plans && ok "H8e control: a slug-matched PR with an implementation file plans 'done (PR #359)' via the branch slug" || no "H8e control: no slug plan row (out='$RUN_OUT')"
rm -rf "$R"
R="$(rs_slug_repo '[".supervisor/jobs/done/2026-10-02-scrub-safe-briefs.md",".supervisor/automate/run.md"]')"
rs_run "$R" "$R/.supervisor/requirements/qh"
DRY_OUT="$RUN_OUT"
rs_run "$R" "$R/.supervisor/requirements/qh" --apply
if [ -z "$DRY_OUT" ] && [ -z "$RUN_OUT" ] && grep -qE '^## Status: pending$' "$R/$RS_DREL"; then
  ok "H8e a slug-matched PR whose changed files are all under .supervisor/ is not evidence (no plan, no stamp)"
else
  no "H8e all-.supervisor slug match read as evidence (dry='$DRY_OUT' apply='$RUN_OUT')"
fi
if rs_mutant "$RS_SUP_LINE" '    :'; then
  RS_H="$RSM/automate-helpers.sh" rs_run "$R" "$R/.supervisor/requirements/qh"
  rs_slug_plans && ok "H8e mutation control: without the all-.supervisor check the slug path plans — the check covers both paths" \
    || no "H8e mutation control: mutant did not reproduce (out='$RUN_OUT') — H8e would be vacuous"
else
  no "H8e mutation control: the all-.supervisor line was not found in the helper"
fi
rm -rf "$R" "$RSM"

# H8d. Fail closed on an unreadable or incomplete diff; a >100-file diff is re-read in full.
R="$(rs_diff_repo '["docs/scrub.md"]')"
jq 'del(.files, .changedFiles)' "$R/ghstub/view-$(rs_key "$RS_D").json" > "$R/v.json" && mv "$R/v.json" "$R/ghstub/view-$(rs_key "$RS_D").json"
rs_run "$R" "$R/.supervisor/requirements/qh"
[ -z "$RUN_OUT" ] && ok "H8d a view with no files/changedFiles is no evidence (fail closed)" || no "H8d unreadable diff read as evidence (out='$RUN_OUT')"
rm -rf "$R"
# pr view returned a 1-entry page of a 150-file diff; no REST answer ⇒ no evidence.
R="$(rs_diff_repo '["docs/scrub.md"]' 150)"
rs_run "$R" "$R/.supervisor/requirements/qh"
[ -z "$RUN_OUT" ] && ok "H8d a truncated diff whose REST re-read fails is no evidence" || no "H8d truncated diff read as evidence (out='$RUN_OUT')"
RS_API="$R/ghstub/api-$(rs_key "repos/acme/widgets/pulls/359/files").txt"
{ for i in $(seq 1 149); do printf 'src/f%s.sh\n' "$i"; done; printf '%s\n' "$RS_DREL"; } > "$RS_API"
rs_run "$R" "$R/.supervisor/requirements/qh"
[ -z "$RUN_OUT" ] && ok "H8d the requirement found on a later REST page of a 150-file diff ⇒ no evidence" || no "H8d requirement past pr view's first page missed (out='$RUN_OUT')"
{ for i in $(seq 1 150); do printf 'src/f%s.sh\n' "$i"; done; } > "$RS_API"
rs_run "$R" "$R/.supervisor/requirements/qh"
rs_plans_359 && ok "H8d a complete 150-file REST re-read without the requirement keeps the citation as evidence" || no "H8d complete REST re-read lost the evidence (out='$RUN_OUT')"
sed '$d' "$RS_API" > "$R/a.txt" && mv "$R/a.txt" "$RS_API"
rs_run "$R" "$R/.supervisor/requirements/qh"
[ -z "$RUN_OUT" ] && ok "H8d a REST re-read still short of changedFiles is no evidence" || no "H8d short REST re-read read as evidence (out='$RUN_OUT')"
rm -rf "$R"

# ---------------------------------------------------------------------------
# I. ceiling-check — PICK-time token ceiling (red-team-hardening/06)
# ---------------------------------------------------------------------------

ck_root() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/.supervisor/logs" "$d/.supervisor/automate"
  printf '%s' "$d"
}

ck_runfile() {
  # ck_runfile <root> <session_id> -> writes a minimal run file naming <session_id>,
  # returns its path on stdout.
  local d="$1" sid="$2" f="$1/.supervisor/automate/run-ck.md"
  cat > "$f" <<EOF
# Automate Run: ck
## Progress
- ts picked item1
- ts session_id $sid (item1)
EOF
  printf '%s' "$f"
}

echo "== I1. ceiling-check: under max -> OK total=<n> max=<n> =="
R="$(ck_root)"
cat > "$R/.supervisor/logs/ckA.jsonl" <<'EOF'
{"event":"token_ledger","session_id":"ckA","input_tokens":100,"output_tokens":100,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}
EOF
RF="$(ck_runfile "$R" ckA)"
OUT="$(bash "$H" ceiling-check "$RF" 1000 --root "$R" 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && grep -qE '^OK total=200 max=1000$' < <(printf '%s' "$OUT"); then
  ok "I1 under-max: $OUT"
else
  no "I1 under-max wrong: rc=$RC out='$OUT'"
fi
rm -rf "$R"

echo "== I2. ceiling-check: over max -> PARK: token_ceiling total=<n> max=<n> =="
R="$(ck_root)"
cat > "$R/.supervisor/logs/ckB.jsonl" <<'EOF'
{"event":"token_ledger","session_id":"ckB","input_tokens":700,"output_tokens":700,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}
EOF
RF="$(ck_runfile "$R" ckB)"
OUT="$(bash "$H" ceiling-check "$RF" 1000 --root "$R" 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && grep -qE '^PARK: token_ceiling total=1400 max=1000$' < <(printf '%s' "$OUT"); then
  ok "I2 over-max parks (rc still 0, PARK is a normal outcome like gate-eval): $OUT"
else
  no "I2 over-max wrong: rc=$RC out='$OUT'"
fi
rm -rf "$R"

echo "== I3. ceiling-check: exactly at max is NOT a breach (only exceeding parks) =="
R="$(ck_root)"
cat > "$R/.supervisor/logs/ckC.jsonl" <<'EOF'
{"event":"token_ledger","session_id":"ckC","input_tokens":500,"output_tokens":500,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}
EOF
RF="$(ck_runfile "$R" ckC)"
OUT="$(bash "$H" ceiling-check "$RF" 1000 --root "$R" 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && grep -qE '^OK total=1000 max=1000$' < <(printf '%s' "$OUT"); then
  ok "I3 exactly-at-max is OK, not a breach: $OUT"
else
  no "I3 exactly-at-max wrong: rc=$RC out='$OUT'"
fi
rm -rf "$R"

echo "== I4. ceiling-check: LEDGER_UNREADABLE=1 reader answer PARKs (fail CLOSED) =="
R="$(ck_root)"
# No session log file at all for the named session -> reader returns LEDGER_UNREADABLE=1.
RF="$(ck_runfile "$R" ckMissing)"
OUT="$(bash "$H" ceiling-check "$RF" 1000 --root "$R" 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && grep -qE '^PARK: ledger_unreadable$' < <(printf '%s' "$OUT"); then
  ok "I4 unreadable ledger fails CLOSED: $OUT"
else
  no "I4 unreadable ledger wrong: rc=$RC out='$OUT'"
fi
rm -rf "$R"

echo "== I5. ceiling-check: missing run file -> die (non-zero, never a silent OK) =="
R="$(ck_root)"
OUT="$(bash "$H" ceiling-check "$R/.supervisor/automate/nope.md" 1000 --root "$R" 2>&1)"; RC=$?
if [ "$RC" -ne 0 ]; then
  ok "I5 missing run file dies: rc=$RC"
else
  no "I5 missing run file should not succeed: out='$OUT'"
fi
rm -rf "$R"

echo "== I6. ceiling-check: non-integer max_tokens -> die =="
R="$(ck_root)"
RF="$(ck_runfile "$R" ckD)"
OUT="$(bash "$H" ceiling-check "$RF" notanumber --root "$R" 2>&1)"; RC=$?
if [ "$RC" -ne 0 ]; then
  ok "I6 non-integer max_tokens dies: rc=$RC"
else
  no "I6 non-integer max_tokens should not succeed: out='$OUT'"
fi
rm -rf "$R"

echo "== I7. MUTATION CONTROL (AC-mandated): a ledger reader that always reports 0 real tokens makes the breach-parks fixture wrongly print OK =="
MUTDIR="$(mktemp -d)"
cp "$HERE/read-token-ledger.sh" "$MUTDIR/read-token-ledger.sh"
cp "$H" "$MUTDIR/automate-helpers.sh"
sed -i.bak 's/def numf(x): if (x|type)=="number" then x else 0 end;/def numf(x): 0;/' "$MUTDIR/read-token-ledger.sh"
if bash -n "$MUTDIR/read-token-ledger.sh" 2>/dev/null && ! diff -q "$MUTDIR/read-token-ledger.sh" "$HERE/read-token-ledger.sh" >/dev/null 2>&1; then
  R="$(ck_root)"
  cat > "$R/.supervisor/logs/ckE.jsonl" <<'EOF'
{"event":"token_ledger","session_id":"ckE","input_tokens":900,"output_tokens":900,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}
EOF
  RF="$(ck_runfile "$R" ckE)"
  # No real-reader baseline runs inside THIS case: $MUTDIR/automate-helpers.sh
  # is a plain copy of the real script, but it is co-located in $MUTDIR with
  # the mutant read-token-ledger.sh, so `$(dirname "$0")/read-token-ledger.sh`
  # resolves to the MUTANT reader, not the real one, for this very invocation
  # -- BASE_OUT below is already the mutant's output. The expected real-reader
  # outcome for this fixture (genuinely over the 1000 ceiling -> PARK) is
  # established separately by case I2's pattern, not re-run here. The
  # assertion in THIS case only checks that the mutant instead prints OK.
  BASE_OUT="$(bash "$MUTDIR/automate-helpers.sh" ceiling-check "$RF" 1000 --root "$R" 2>&1)"
  # Mutant output (same co-located resolution as above, restated for clarity
  # at the point of use).
  MUT_OUT="$BASE_OUT"
  rm -rf "$R"
  if grep -q '^OK' < <(printf '%s' "$MUT_OUT"); then
    ok "I7 mutation control: always-0 numf() flips a genuinely-over-ceiling fixture to OK -- proves ceiling-check's breach-parks behavior is load-bearing, not vacuous (mutant='$MUT_OUT')"
  else
    no "I7 mutation control REFUTED: mutant still parked -- ceiling-check may not actually depend on the reader's real-usage sums (mutant='$MUT_OUT')"
  fi
else
  no "I7 mutation control: could not build the mutant (sed did not apply or bash -n failed) -- control inconclusive"
fi
rm -rf "$MUTDIR"

# ============================================================================
# BRANCH MODE — meta-entry (pull BEFORE the first read) + meta-push-failed (skills/automate-loop/
# SKILL.md §"Branch mode"). Hermetic: a mktemp world with a LOCAL bare origin, never GitHub.
# ============================================================================
echo "== branch mode: meta-entry / meta-push-failed =="
BM_T="$(mktemp -d)"
BM_MS="$HERE/meta-sync.sh"
BM_SM="$HERE/setup-memory.sh"
bm_env() { env HOME="$BM_T/home" GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@test.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@test.invalid "$@"; }
mkdir -p "$BM_T/home"
# bm_world <dir> <mode: on|off> — bare origin + seed (main carries .gitignore; mode on ⇒ the
# branch-mode block + an initialised loomwright-meta branch) + a clone `work`.
bm_world() {
  local w="$1" mode="$2"
  mkdir -p "$w"
  bm_env git init -q --bare "$w/origin.git"
  git --git-dir="$w/origin.git" symbolic-ref HEAD refs/heads/main
  bm_env git init -q "$w/seed"
  (
    cd "$w/seed" || exit 1
    git symbolic-ref HEAD refs/heads/main
    printf '.supervisor/\n' > .gitignore
    [ "$mode" = on ] && bm_env bash "$BM_SM" --root "$w/seed" apply --branch-mode loomwright-meta >/dev/null 2>&1
    rm -f .gitignore.backup.*
    echo code > app.txt
    bm_env git add .gitignore app.txt && bm_env git commit -qm code
    git remote add origin "$w/origin.git" && bm_env git push -q origin main
    [ "$mode" = on ] && bm_env bash "$BM_MS" init --root "$w/seed" >/dev/null 2>&1
    true
  ) >/dev/null 2>&1
  bm_env git clone -q "$w/origin.git" "$w/work" >/dev/null 2>&1
}
bm_entry() { (cd "$1" && bm_env bash "$H" meta-entry --root "$1" 2>/dev/null); }

# (bm1) mode off ⇒ `meta-entry: off`, no network needed.
bm_world "$BM_T/off" off
o="$(bm_entry "$BM_T/off/work")"
[ "$o" = "meta-entry: off" ] && ok "BM1 mode off ⇒ 'meta-entry: off'" || no "BM1 mode off ⇒ '$o'"

# (bm2) a paused run file present ONLY on the metadata branch ⇒ resume-glob is blind before the
# pull and lists it after `meta-entry: pulled`.
bm_world "$BM_T/on" on
bm_env git clone -q "$BM_T/on/origin.git" "$BM_T/on/other" >/dev/null 2>&1
mkdir -p "$BM_T/on/other/.supervisor/automate"
printf '# Automate Run: automate-2026-10-02-000000\n\n## Status: paused\n\n## Queue\n- [ ] item\n\n## Progress\n' > "$BM_T/on/other/.supervisor/automate/automate-2026-10-02-000000.md"
bm_env bash "$BM_MS" push --root "$BM_T/on/other" --branch loomwright-meta >/dev/null 2>&1
before="$(bash "$H" resume-glob "$BM_T/on/work/.supervisor/automate" 2>/dev/null)"
[ -z "$before" ] && ok "BM2 before meta-entry the clone's resume-glob is EMPTY (the silent-amnesia shape)" || no "BM2 precondition: resume-glob already listed '$before'"
o="$(bm_entry "$BM_T/on/work")"
[ "$o" = "meta-entry: pulled loomwright-meta" ] && ok "BM2 mode on + reachable ⇒ 'meta-entry: pulled loomwright-meta'" || no "BM2 meta-entry ⇒ '$o'"
after="$(bash "$H" resume-glob "$BM_T/on/work/.supervisor/automate" 2>/dev/null)"
case "$after" in *automate-2026-10-02-000000.md) ok "BM2 after the pull resume-glob lists the paused run" ;; *) no "BM2 resume-glob after pull: '$after'" ;; esac

# (bm3) unreachable remote + no run file ⇒ `failed — …`, .supervisor/automate unchanged.
bm_world "$BM_T/un" on
git -C "$BM_T/un/work" remote set-url origin "$BM_T/un/no-such-origin.git"
ls_before="$(ls -A "$BM_T/un/work/.supervisor/automate" 2>&1)"
o="$(bm_entry "$BM_T/un/work")"
ls_after="$(ls -A "$BM_T/un/work/.supervisor/automate" 2>&1)"
bm3_assert() {  # bm3_assert <meta-entry output> — the "abort, nothing created" assertion
  case "$1" in "meta-entry: failed — "*) ;; *) return 1 ;; esac
  [ "$ls_before" = "$ls_after" ]
}
bm3_assert "$o" && ok "BM3 unreachable remote ⇒ '$o' and ls .supervisor/automate unchanged" || no "BM3 unreachable remote ⇒ '$o' (ls before='$ls_before' after='$ls_after')"
# Mutation control (i): a pull stand-in that exits 0 on the fetch failure MUST turn BM3 red.
printf '#!/usr/bin/env bash\nbash "%s" "$@" >/dev/null 2>&1\nexit 0\n' "$BM_MS" > "$BM_T/lying-meta-sync.sh"
o_mut="$(cd "$BM_T/un/work" && LOOMWRIGHT_META_SYNC_BIN="$BM_T/lying-meta-sync.sh" bm_env bash "$H" meta-entry --root "$BM_T/un/work" 2>/dev/null)"
if bm3_assert "$o_mut"; then no "BM3 mutation control (i) REFUTED: a pull that lies (exit 0 on fetch failure) still passed the abort assertion ('$o_mut')"; else ok "BM3 mutation control (i): a lying pull ('$o_mut') turns the abort assertion RED — it is load-bearing"; fi

# (bm4) mode unknown ⇒ failed — mode unknown (…), no pull attempted.
bm_world "$BM_T/uk" on
awk '{print} index($0, "# loomwright-meta-branch: ") == 1 {print "# loomwright-meta-branch: other"}' "$BM_T/uk/work/.gitignore" > "$BM_T/uk/g" && mv "$BM_T/uk/g" "$BM_T/uk/work/.gitignore"
o="$(bm_entry "$BM_T/uk/work")"
case "$o" in "meta-entry: failed — mode unknown ("*) ok "BM4 two mode lines ⇒ '$o'" ;; *) no "BM4 mode unknown ⇒ '$o'" ;; esac
[ ! -e "$BM_T/uk/work/.supervisor" ] && ok "BM4 mode unknown created nothing under .supervisor/" || no "BM4 mode unknown wrote under .supervisor/"
[ "$(bm_entry "$BM_T/uk/work" | wc -l | tr -d ' ')" = 1 ] && ok "BM4 meta-entry prints exactly ONE line" || no "BM4 meta-entry printed more than one line"
(cd "$BM_T/uk/work" && bm_env bash "$H" meta-entry --root "$BM_T/uk/work" >/dev/null 2>&1); [ $? -eq 0 ] && ok "BM4 meta-entry exits 0 on failure" || no "BM4 meta-entry exited non-zero"

# (bm5) meta-push-failed: nothing without a marker; the marker's first line with one.
mkdir -p "$BM_T/mp/.supervisor/automate"; RF="$BM_T/mp/.supervisor/automate/automate-2026-10-02-000001.md"
printf '# Automate Run: automate-2026-10-02-000001\n' > "$RF"
o="$(bash "$H" meta-push-failed "$RF" 2>/dev/null)"; rc=$?
[ -z "$o" ] && [ "$rc" -eq 0 ] && ok "BM5 meta-push-failed with no marker prints nothing, exit 0" || no "BM5 no marker ⇒ '$o' rc=$rc"
printf '2026-10-02T00:00:00Z conflict .supervisor/automate/x.md\nmeta_sync: scrub a: rule\n' > "$BM_T/mp/.supervisor/automate/automate-2026-10-02-000001.meta-push-failed"
o="$(bash "$H" meta-push-failed "$RF" 2>/dev/null)"
[ "$o" = "2026-10-02T00:00:00Z conflict .supervisor/automate/x.md" ] && ok "BM5 meta-push-failed prints the marker's first line" || no "BM5 marker ⇒ '$o'"
o="$(bash "$H" resume-glob "$BM_T/mp/.supervisor/automate" 2>/dev/null)"
case "$o" in *meta-push-failed*) no "BM5 resume-glob lists the marker" ;; *) ok "BM5 resume-glob never lists the .meta-push-failed marker" ;; esac
# (bm6) a repo that NEVER opted in reads `meta-entry: off` even when its .gitignore is one the
# setup-memory WRITER would refuse to rewrite (read-only / conflict-marked) — the reader decides
# from content, so AC3 ("off — proceed exactly as today") holds for every non-opted-in repo. The
# origin is pointed at a missing path so any pull attempt would surface as `failed`.
bm_world "$BM_T/ro" off
git -C "$BM_T/ro/work" remote set-url origin "$BM_T/ro/no-such-origin.git"
chmod 444 "$BM_T/ro/work/.gitignore"
o="$(bm_entry "$BM_T/ro/work")"
[ "$o" = "meta-entry: off" ] && ok "BM6 never opted in + read-only .gitignore ⇒ 'meta-entry: off'" || no "BM6 read-only, never opted in ⇒ '$o'"
chmod 644 "$BM_T/ro/work/.gitignore"
printf '<<<<<<< HEAD\na/\n=======\nb/\n>>>>>>> other\n' >> "$BM_T/ro/work/.gitignore"
o="$(bm_entry "$BM_T/ro/work")"
[ "$o" = "meta-entry: off" ] && ok "BM6 never opted in + conflict-marked .gitignore ⇒ 'meta-entry: off'" || no "BM6 conflict-marked, never opted in ⇒ '$o'"
[ ! -e "$BM_T/ro/work/.supervisor" ] && ok "BM6 meta-entry off created nothing under .supervisor/" || no "BM6 meta-entry off wrote under .supervisor/"
# Opted in + read-only: still `on` (a reader never needs writability) ⇒ the pull runs.
bm_world "$BM_T/roon" on
chmod 444 "$BM_T/roon/work/.gitignore"
o="$(bm_entry "$BM_T/roon/work")"
[ "$o" = "meta-entry: pulled loomwright-meta" ] && ok "BM6 branch mode + read-only .gitignore ⇒ '$o'" || no "BM6 read-only branch mode ⇒ '$o'"
chmod 644 "$BM_T/roon/work/.gitignore"
# (bm7) a bare / empty / option-shaped `--root` value is a misinvocation ⇒ `failed`, never a silent
# `off` (pre-fix, `--root --x` read the mode of a non-existent checkout as off and skipped the pull
# in a branch-mode repo). Fail-safe: ONE line, exit 0.
for rv in --x -h ""; do
  o="$(cd "$BM_T/roon/work" && bm_env bash "$H" meta-entry --root "$rv" 2>/dev/null)"; rc=$?
  [ "$o" = "meta-entry: failed — --root requires a checkout path (got '$rv')" ] && [ "$rc" -eq 0 ] && ok "BM7 meta-entry --root '$rv' ⇒ '$o', exit 0" || no "BM7 meta-entry --root '$rv' ⇒ '$o' rc=$rc"
done
o="$(cd "$BM_T/roon/work" && bm_env bash "$H" meta-entry --root 2>/dev/null)"; rc=$?
[ "$o" = "meta-entry: failed — --root requires a checkout path (got '')" ] && [ "$rc" -eq 0 ] && ok "BM7 a trailing bare meta-entry --root ⇒ failed, exit 0" || no "BM7 bare --root ⇒ '$o' rc=$rc"
o="$(bash "$H" meta-push-failed -x.md 2>/dev/null)"; rc=$?
[ -z "$o" ] && [ "$rc" -eq 0 ] && ok "BM7 meta-push-failed with an option-shaped <runfile> prints nothing, exit 0" || no "BM7 meta-push-failed -x.md ⇒ '$o' rc=$rc"
# (bm8) review iteration 3 — the mode answer is FAIL-CLOSED on its SHAPE: an empty, garbage or
# `on ` (empty-branch) answer from the reader is `failed — mode unknown`, and NO pull runs; a
# near-miss mode line in a real branch-mode .gitignore reads unknown too (never `off`).
BM8="$BM_T/bm8"; mkdir -p "$BM8/bin"
cp "$H" "$BM8/bin/automate-helpers.sh"
printf '#!/bin/bash\necho pulled-by-spy >> "%s/spy.log"\nexit 0\n' "$BM8" > "$BM8/spy-meta-sync.sh"
bm8_entry() {  # <stub answer> [helpers copy] — runs meta-entry against a stub reader printing <answer>
  printf '#!/bin/bash\nprintf "%%s" %q\n' "$1" > "$BM8/bin/setup-memory.sh"
  (cd "$BM8" && LOOMWRIGHT_META_SYNC_BIN="$BM8/spy-meta-sync.sh" bash "${2:-$BM8/bin/automate-helpers.sh}" meta-entry --root "$BM8" 2>/dev/null)
}
for ans in '' 'on ' 'garbage' 'offx'; do
  rm -f "$BM8/spy.log"
  o="$(bm8_entry "$ans")"
  case "$o" in "meta-entry: failed — mode unknown ("*) ok "BM8 reader answer '$ans' ⇒ '$o'" ;; *) no "BM8 reader answer '$ans' ⇒ '$o'" ;; esac
  [ ! -e "$BM8/spy.log" ] && ok "BM8 reader answer '$ans' ran NO pull" || no "BM8 reader answer '$ans' ran a pull"
done
# Mutation control: the pre-fix `"on "*)` arm accepts `on ` (empty branch) and runs the pull.
sed 's/^    "on "?\*) branch="\${mode#on }" ;;$/    "on "*) branch="${mode#on }" ;;/' "$BM8/bin/automate-helpers.sh" > "$BM8/bin/mut-helpers.sh"
if cmp -s "$BM8/bin/automate-helpers.sh" "$BM8/bin/mut-helpers.sh"; then
  no "BM8 mutation control: the patch changed nothing — inconclusive"
else
  rm -f "$BM8/spy.log"; o="$(bm8_entry 'on ' "$BM8/bin/mut-helpers.sh")"
  case "$o" in "meta-entry: failed — "*) no "BM8 mutation control REFUTED: the pre-fix arm still fails on 'on ' ($o)" ;; *) ok "BM8 mutation control: the pre-fix arm accepts 'on ' ⇒ '$o' — the assertion is load-bearing" ;; esac
fi
# A near-miss (indented) mode line in a real branch-mode clone ⇒ unknown, through the real reader.
bm_world "$BM_T/nm" on
awk 'index($0, "# loomwright-meta-branch: ") == 1 { print "  " $0; next } { print }' "$BM_T/nm/work/.gitignore" > "$BM_T/nm/g" && mv "$BM_T/nm/g" "$BM_T/nm/work/.gitignore"
o="$(bm_entry "$BM_T/nm/work")"
case "$o" in "meta-entry: failed — mode unknown (a malformed mode line"*) ok "BM8 an indented mode line ⇒ '$o'" ;; *) no "BM8 indented mode line ⇒ '$o'" ;; esac
rm -rf "$BM_T"


# =============================================================================
echo "== W. plan-waves (parallel-automate/04: read-only wave planner; fixtures under mktemp -d, --root = fixture root) =="
W_T="$(mktemp -d)"
W_REPO="$(cd "$HERE/../.." && pwd)"
# w_item <path under W_T> <Depends body|-> <Touches body|-> [status line]  ('-' omits the section; bodies use printf %b)
w_item() {
  mkdir -p "$(dirname "$W_T/$1")"
  {
    echo "# Item $1"
    if [ -n "${4:-}" ]; then echo; echo "## Status: $4"; fi
    if [ "$2" != - ]; then echo; echo "## Depends on"; printf '%b\n' "$2"; fi
    if [ "$3" != - ]; then echo; echo "## Touches"; printf '%b\n' "$3"; fi
    echo; echo "## Notes"; echo "prose"
  } > "$W_T/$1"
}
# w_run <root> <helper> <input> <args...> — stdout in W_OUT, stderr in W_ERR, exit code in W_RC
w_run() {
  local root="$1" helper="$2" input="$3"; shift 3
  W_RC=0
  W_OUT="$(bash "$helper" plan-waves "$input" --root "$root" "$@" 2>"$W_T/err")" || W_RC=$?
  W_ERR="$(cat "$W_T/err")"
}
w_list() { printf '%s\n' "$@" > "$W_T/list"; }
w_expect() {  # <label> <expected stdout (printf %b)>
  local want; want="$(printf '%b' "$2")"
  if [ "$W_RC" -eq 0 ] && [ "$W_OUT" = "$want" ]; then ok "$1"; else no "$1 (rc=$W_RC) got: $(printf '%s' "$W_OUT" | tr '\n' '|') err: $W_ERR"; fi
}
w_fails() {  # <label> <stderr substring>
  if [ "$W_RC" -eq 1 ] && [ -z "$W_OUT" ] && grep -qF -- "$2" <<<"$W_ERR"; then ok "$1"; else no "$1 (rc=$W_RC out='$W_OUT' err='$W_ERR')"; fi
}

# W1 disjoint items share a wave; the absent companion table is announced on stderr and the plan proceeds.
rm -rf "$W_T/q"
w_item q/01-a.md none 'a/x.sh'
w_item q/02-b.md none 'b/y.sh'
w_list q/01-a.md q/02-b.md
w_run "$W_T" "$H" "$W_T/list" --max 3
w_expect "W1 disjoint items share a wave" 'wave 1: q/01-a.md q/02-b.md'
case "$W_ERR" in *"plan-waves: no $W_T/.agent/companions.json — no companion expansion"*|*"/.agent/companions.json — no companion expansion"*) ok "W1 absent companions.json ⇒ one stderr note" ;; *) no "W1 absent companions note missing: $W_ERR" ;; esac

# W2 prefix-intersecting items never share a wave (a/ vs a/b.sh; a/b vs a/b).
rm -rf "$W_T/q"
w_item q/01-a.md none 'a/'
w_item q/02-b.md none 'a/b.sh'
w_item q/03-c.md none 'z/b'
w_item q/04-d.md none 'z/b'
w_list q/01-a.md q/02-b.md q/03-c.md q/04-d.md
w_run "$W_T" "$H" "$W_T/list" --max 4
w_expect "W2 prefix/equal entries intersect (a/ vs a/b.sh; z/b vs z/b)" 'wave 1: q/01-a.md q/03-c.md\nwave 2: q/02-b.md q/04-d.md'

# W3 companion expansion separates two items editing DIFFERENT x/skills/<s>/SKILL.md (fixture table);
#    mutation control (ii): the same items under a root with NO companions.json share a wave.
W_C="$W_T/croot"; W_NC="$W_T/nocroot"
mkdir -p "$W_C/.agent" "$W_NC"
cat > "$W_C/.agent/companions.json" <<'JSON'
{"schema_version": 1, "companions": [
  {"when": "x/skills/*/SKILL.md", "add": ["x/skills/SKILLS_INDEX.md"]},
  {"when": "x/agents/*", "new": true, "add": ["x/INDEX.md"]}
]}
JSON
for r in "$W_C" "$W_NC"; do
  mkdir -p "$r/q" "$r/x/agents"; : > "$r/x/agents/old.md"
  printf '# s1\n## Depends on\nnone\n## Touches\nx/skills/s1/SKILL.md\n' > "$r/q/01-s1.md"
  printf '# s2\n## Depends on\nnone\n## Touches\nx/skills/s2/SKILL.md\n' > "$r/q/02-s2.md"
done
printf 'q/01-s1.md\nq/02-s2.md\n' > "$W_T/list"
W_SEP_WANT='wave 1: q/01-s1.md\nwave 2: q/02-s2.md'
w_run "$W_C" "$H" "$W_T/list" --max 3
w_expect "W3 companion expansion separates two different x/skills/<s>/SKILL.md items" "$W_SEP_WANT"
w_run "$W_NC" "$H" "$W_T/list" --max 3
if [ "$W_OUT" != "$(printf '%b' "$W_SEP_WANT")" ] && [ "$W_OUT" = "wave 1: q/01-s1.md q/02-s2.md" ]; then
  ok "W3 MUTATION CONTROL (ii): companion table removed ⇒ the separation assertion turns red (they share wave 1) — the table is load-bearing"
else no "W3 mutation control (ii) did not turn red: $W_OUT"; fi

# W4 a "new": true rule fires for a missing path and not for an existing one.
printf '# n\n## Depends on\nnone\n## Touches\nx/agents/new.md\n' > "$W_C/q/03-new.md"
printf '# o\n## Depends on\nnone\n## Touches\nx/agents/old.md\n' > "$W_C/q/04-old.md"
printf '# i\n## Depends on\nnone\n## Touches\nx/INDEX.md\n' > "$W_C/q/05-idx.md"
printf 'q/05-idx.md\nq/03-new.md\n' > "$W_T/list"
w_run "$W_C" "$H" "$W_T/list" --max 3
w_expect "W4 \"new\" rule fires for a missing file (x/agents/new.md drags x/INDEX.md)" 'wave 1: q/05-idx.md\nwave 2: q/03-new.md'
printf 'q/05-idx.md\nq/04-old.md\n' > "$W_T/list"
w_run "$W_C" "$H" "$W_T/list" --max 3
w_expect "W4 \"new\" rule does NOT fire for an existing file (x/agents/old.md)" 'wave 1: q/05-idx.md q/04-old.md'
# A directory entry D/ fires a rule whose literal prefix D/ covers (x/agents/ vs "x/agents/*"), new rules included.
printf '# d\n## Depends on\nnone\n## Touches\nx/agents/\n' > "$W_C/q/06-dir.md"
printf 'q/06-dir.md\nq/05-idx.md\n' > "$W_T/list"
w_run "$W_C" "$H" "$W_T/list" --max 3
w_expect "W4 directory entry x/agents/ fires the new rule ⇒ drags x/INDEX.md" 'wave 1: q/06-dir.md\nwave 2: q/05-idx.md'

# W5 dependency ordering across waves, incl. an in-set ../other/NN-x.md dependency (physical-path key).
rm -rf "$W_T/q" "$W_T/other"
w_item q/01-a.md '../other/05-y.md' 'a'
w_item q/02-b.md '1' 'b'
w_item other/05-y.md none 'y'
w_list q/01-a.md q/02-b.md other/05-y.md
w_run "$W_T" "$H" "$W_T/list" --max 3
w_expect "W5 deps order the waves (../other dep in the plan set; numeric id 1 ⇒ 01-a.md)" 'wave 1: other/05-y.md\nwave 2: q/01-a.md\nwave 3: q/02-b.md'

# W6 run-file input: plain [x] ⇒ merged-done; `# skipped:` row and an ABANDONED stamp ⇒ never landed;
#    a closed-out file (pending heading then done heading) ⇒ merged-done.
rm -rf "$W_T/q"
w_item q/01-a.md none 'a'
w_item q/02-b.md none 'b'
w_item q/03-c.md '01' 'c'
w_item q/04-d.md '02' 'd'
w_item q/05-e.md '06' 'e'
w_item q/06-f.md none 'f' 'done_with_escalation — ABANDONED (- [x] q/06-f.md  # abandoned: x)'
w_item q/07-g.md none 'g' 'pending'
printf '\n## Status: done\n' >> "$W_T/q/07-g.md"
w_item q/08-h.md '07' 'h'
cat > "$W_T/run.md" <<'RUN'
# Automate Run: automate-test
## Status: running
## Queue
- [x] q/01-a.md  # skipped: owner said so
- [x] q/02-b.md
- [ ] q/03-c.md
- [ ] q/04-d.md
- [ ] q/05-e.md
- [ ] q/08-h.md
## Current
RUN
w_run "$W_T" "$H" "$W_T/run.md" --max 3
w_expect "W6 run file: merged-done / skipped / ABANDONED / two-heading done" 'wave 1: q/04-d.md q/08-h.md\nblocked q/03-c.md: waits on 01 (skipped — never landed)\nblocked q/05-e.md: waits on 06 (abandoned — never landed)'

# W6b the owner's Queue row mark outranks the file stamp: a `# skipped:` / `# abandoned:` row over a
#     plain done / done_with_escalation stamp (Phase 4.5 writes those BEFORE any merge) never landed.
rm -rf "$W_T/q"
w_item q/01-a.md none 'a' 'done_with_escalation'
w_item q/02-b.md '01' 'b'
w_item q/03-c.md none 'c' 'done_with_escalation'
w_item q/04-d.md '03' 'd'
w_item q/05-e.md none 'e' 'done'
w_item q/06-f.md '05' 'f'
cat > "$W_T/run.md" <<'RUN'
# Automate Run: automate-test
## Status: running
## Queue
- [x] q/01-a.md  # skipped: owner said so
- [x] q/03-c.md  # abandoned: superseded
- [x] q/05-e.md  # skipped: dropped
- [ ] q/02-b.md
- [ ] q/04-d.md
- [ ] q/06-f.md
## Current
RUN
w_run "$W_T" "$H" "$W_T/run.md" --max 3
w_expect "W6b skipped/abandoned row over a done(_with_escalation) stamp ⇒ never landed (row wins)" 'blocked q/02-b.md: waits on 01 (skipped — never landed)\nblocked q/04-d.md: waits on 03 (abandoned — never landed)\nblocked q/06-f.md: waits on 05 (skipped — never landed)'

# W6c a run file whose title is a TOLERATED non-exact form (BOM + lower-case, automate-followups/19)
#     is still classified as a run file (is_run_file is plan_waves' input classifier): the plan set
#     is its unchecked Queue rows only. Read as an item list instead, the BOM line and the `- [ ]`
#     rows would be taken as item paths and the run would exit 1 ("item not found").
rm -rf "$W_T/q"
w_item q/01-a.md none 'a'
w_item q/02-b.md none 'b'
w_item q/03-c.md none 'c' 'done'
{ printf '\357\273\277# automate run: automate-test\n'
  printf '## Status: running\n## Queue\n- [x] q/03-c.md\n- [ ] q/01-a.md\n- [ ] q/02-b.md\n## Current\n'; } > "$W_T/run-tolerant.md"
w_run "$W_T" "$H" "$W_T/run-tolerant.md" --max 3
w_expect "W6c BOM + lower-case titled run file is parsed as a run file (plan set = its unchecked Queue rows)" 'wave 1: q/01-a.md q/02-b.md'

# W7 parked dependency; out-of-set pending dependency; transitive block.
rm -rf "$W_T/q"
w_item q/01-a.md '02' 'a'
w_item q/02-b.md none 'b' 'parked (waits on S1)'
w_item q/03-c.md '04' 'c'
w_item q/04-d.md none 'd' 'pending'
w_item q/05-e.md '01' 'e'
w_list q/01-a.md q/03-c.md q/05-e.md
w_run "$W_T" "$H" "$W_T/list" --max 3
w_expect "W7 parked ⇒ depends on parked; pending out-of-set ⇒ waits on; transitive ⇒ waits on its id" 'blocked q/01-a.md: depends on parked 02\nblocked q/03-c.md: waits on 04\nblocked q/05-e.md: waits on 01'

# W8 missing / unknown / malformed Touches runs ALONE (the item in the middle of three disjoint ones).
w_alone() {  # <label> <Touches body|-> [helper]
  rm -rf "$W_T/q"
  w_item q/01-a.md none 'a'
  w_item q/02-b.md none "$2"
  w_item q/03-c.md none 'c'
  w_list q/01-a.md q/02-b.md q/03-c.md
  w_run "$W_T" "${3:-$H}" "$W_T/list" --max 3
}
W_ALONE_WANT='wave 1: q/01-a.md q/03-c.md\nwave 2: q/02-b.md'
w_alone missing -; w_expect "W8 missing Touches runs alone" "$W_ALONE_WANT"
w_alone unknown 'unknown'; w_expect "W8 'unknown' Touches runs alone" "$W_ALONE_WANT"
w_alone backtick '`b/x.sh`'; w_expect "W8 backtick Touches line ⇒ unknown, runs alone" "$W_ALONE_WANT"
w_alone glob 'b/*.sh'; w_expect "W8 glob Touches line ⇒ unknown, runs alone" "$W_ALONE_WANT"
w_alone pipe 'a|b'; w_expect "W8 'a|b' Touches line ⇒ unknown, runs alone" "$W_ALONE_WANT"
w_alone prose 'b/x.sh and friends'; w_expect "W8 trailing prose ⇒ unknown, runs alone" "$W_ALONE_WANT"
w_alone bullet '- b/x.sh'; w_expect "W8 bullet ⇒ unknown, runs alone" "$W_ALONE_WANT"
w_alone mixed 'b/x.sh\nunknown'; w_expect "W8 unknown mixed with a path ⇒ unknown, runs alone" "$W_ALONE_WANT"
w_alone empty ''; w_expect "W8 empty section ⇒ unknown, runs alone" "$W_ALONE_WANT"
w_alone dotdot 'b/../x'; w_expect "W8 '..' segment ⇒ unknown, runs alone" "$W_ALONE_WANT"
w_alone dot '.'; w_expect "W8 bare '.' (whole repo) ⇒ unknown, runs alone" "$W_ALONE_WANT"
w_alone dot-dir './'; w_expect "W8 './' ⇒ unknown, runs alone" "$W_ALONE_WANT"
w_alone dot-lead './b/x.sh'; w_expect "W8 leading './' segment ⇒ unknown, runs alone" "$W_ALONE_WANT"
w_alone dot-mid 'b/./x.sh'; w_expect "W8 inner '.' segment ⇒ unknown, runs alone" "$W_ALONE_WANT"
w_alone dot-name 'b/.x.sh'; w_expect "W8 a dot-file name is NOT a '.' segment (still known)" 'wave 1: q/01-a.md q/02-b.md q/03-c.md'
w_alone duplicate 'b/x.sh\n\n## Touches\nb/y.sh'; w_expect "W8 heading twice ⇒ unknown, runs alone" "$W_ALONE_WANT"
w_alone blank-lines 'b/x.sh\n\nb/y.sh'; w_expect "W8 blank lines inside a section are ignored (still known)" 'wave 1: q/01-a.md q/02-b.md q/03-c.md'
# An unknown item first takes wave 1 alone.
rm -rf "$W_T/q"; w_item q/01-a.md none -; w_item q/02-b.md none 'b'; w_item q/03-c.md none 'c'
w_list q/01-a.md q/02-b.md q/03-c.md
w_run "$W_T" "$H" "$W_T/list" --max 3
w_expect "W8 a missing-Touches FIRST item takes its wave alone" 'wave 1: q/01-a.md\nwave 2: q/02-b.md q/03-c.md'
# MUTATION CONTROL (i): a helper copy where a MISSING Touches is an EMPTY set must turn "missing runs alone" red.
sed 's/print "unknown"; exit }   # PW_MISSING_TOUCHES/print "known"; exit }   # PW_MISSING_TOUCHES/' "$H" > "$W_T/mut-empty.sh"
if [ -s "$W_T/mut-empty.sh" ] && ! cmp -s "$H" "$W_T/mut-empty.sh" && bash -n "$W_T/mut-empty.sh"; then
  w_alone missing - "$W_T/mut-empty.sh"
  if [ "$W_OUT" != "$(printf '%b' "$W_ALONE_WANT")" ]; then
    ok "W8 MUTATION CONTROL (i): missing-Touches-as-empty-set mutant turns 'missing runs alone' red ($(printf '%s' "$W_OUT" | tr '\n' '|'))"
  else no "W8 mutation control (i) stayed green — the assertion is vacuous"; fi
  w_alone missing -; w_expect "W8 mutation control (i): the REAL helper stays green" "$W_ALONE_WANT"
else no "W8 mutation control (i) inconclusive: mutant empty, identical or not valid bash"; fi

# W9 undeclared queue ⇒ one item per wave in queue order.
rm -rf "$W_T/q"; w_item q/01-a.md - 'a'; w_item q/02-b.md - 'b'; w_item q/03-c.md - 'c'
w_run "$W_T" "$H" "$W_T/q" --max 3
w_expect "W9 undeclared queue (dir input) ⇒ one item per wave in order" "wave 1: $W_T/q/01-a.md\nwave 2: $W_T/q/02-b.md\nwave 3: $W_T/q/03-c.md"

# W10 cycles: explicit and via the implicit rule ⇒ exit 1, stdout empty, items named.
rm -rf "$W_T/q"; w_item q/01-a.md '02' 'a'; w_item q/02-b.md '01' 'b'
w_list q/01-a.md q/02-b.md; w_run "$W_T" "$H" "$W_T/list" --max 3
w_fails "W10 explicit cycle ⇒ exit 1, empty stdout" 'plan-waves: dependency cycle: q/01-a.md q/02-b.md'
rm -rf "$W_T/q"; w_item q/01-a.md '02' 'a'; w_item q/02-b.md - 'b'; w_item q/03-c.md none 'c'
w_list q/01-a.md q/02-b.md q/03-c.md; w_run "$W_T" "$H" "$W_T/list" --max 3
w_fails "W10 implicit-rule cycle (01 ⇒ 02, undeclared 02 ⇒ every earlier) ⇒ exit 1, both named, 03 not" 'plan-waves: dependency cycle: q/01-a.md q/02-b.md'
case "$W_ERR" in *03-c.md*) no "W10 implicit cycle named a non-cycle item: $W_ERR" ;; *) ok "W10 the cycle message names only the cycle's items" ;; esac

# W11 unknown dependency id: zero matches and two matches ⇒ exit 1, stdout empty.
rm -rf "$W_T/q"; w_item q/01-a.md '09' 'a'
w_list q/01-a.md; w_run "$W_T" "$H" "$W_T/list" --max 3
w_fails "W11 zero-match id ⇒ unknown dependency" 'plan-waves: unknown dependency 09 in q/01-a.md'
w_item q/01-a.md '5' 'a'; w_item q/05-x.md none 'x'; w_item q/05-y.md none 'y'
w_run "$W_T" "$H" "$W_T/list" --max 3
w_fails "W11 two-match id ⇒ unknown dependency" 'plan-waves: unknown dependency 5 in q/01-a.md'
w_item q/01-a.md '../nowhere/01-z.md' 'a'; w_run "$W_T" "$H" "$W_T/list" --max 3
w_fails "W11 a dependency path that is not an existing file ⇒ unknown dependency" 'plan-waves: unknown dependency ../nowhere/01-z.md in q/01-a.md'

# W11b a plan-set item that names no file on disk ⇒ exit 1 `item not found: <item>`, stdout empty
#      (an item-list line, and an unchecked run-file Queue row).
rm -rf "$W_T/q"; w_item q/01-a.md none 'a'
w_list q/01-a.md q/02-gone.md; w_run "$W_T" "$H" "$W_T/list" --max 3
w_fails "W11b item-list line naming a missing file ⇒ exit 1, item not found" 'plan-waves: item not found: q/02-gone.md'
printf '# Automate Run: automate-test\n## Status: running\n## Queue\n- [ ] q/01-a.md\n- [ ] q/03-gone.md\n## Current\n' > "$W_T/run-missing.md"
w_run "$W_T" "$H" "$W_T/run-missing.md" --max 3
w_fails "W11b run-file Queue row naming a missing file ⇒ exit 1, item not found" 'plan-waves: item not found: q/03-gone.md'

# W12 --max respected: three disjoint items, --max 2 ⇒ 2 + 1.
rm -rf "$W_T/q"; w_item q/01-a.md none 'a'; w_item q/02-b.md none 'b'; w_item q/03-c.md none 'c'
w_list q/01-a.md q/02-b.md q/03-c.md; w_run "$W_T" "$H" "$W_T/list" --max 2
w_expect "W12 --max 2 over three disjoint items ⇒ waves of 2 + 1" 'wave 1: q/01-a.md q/02-b.md\nwave 2: q/03-c.md'

# W13 companions.json malformed ⇒ exit 1 companions_malformed, stdout empty (every bad shape).
W_M="$W_T/mroot"; mkdir -p "$W_M/.agent"; cp -R "$W_T/q" "$W_M/q"
for bad in 'not json' '[]' '{"schema_version":2,"companions":[]}' '{"schema_version":1}' \
  '{"schema_version":1,"companions":[{"when":"a/*"}]}' '{"schema_version":1,"companions":[{"when":"a/*","add":["b"],"new":false}]}' \
  '{"schema_version":1,"companions":[{"when":"a/*","add":["b c"]}]}' '{"schema_version":1,"companions":[{"when":"a","add":["b"],"x":1}]}' \
  '{"schema_version":1,"companions":[{"when":"./a/*","add":["b"]}]}' '{"schema_version":1,"companions":[{"when":"a/./*","add":["b"]}]}' \
  '{"schema_version":1,"companions":[{"when":"a/*","add":["./b"]}]}' '{"schema_version":1,"companions":[{"when":"a/*","add":["b/../c"]}]}' \
  '{"schema_version":1,"companions":[{"when":"a/*","add":["."]}]}' '{"schema_version":1,"companions":[{"when":"a/*","add":["/b"]}]}' \
  '{"schema_version":1,"companions":[{"when":"a//*","add":["b"]}]}' \
  '{"schema_version":1,"companions":[{"when":"/a/*","add":["b"]}]}' '{"schema_version":1,"companions":[{"when":"a/../*","add":["b"]}]}'; do
  printf '%s\n' "$bad" > "$W_M/.agent/companions.json"
  w_run "$W_M" "$H" "$W_T/list" --max 2
  w_fails "W13 malformed companions.json '$bad' ⇒ exit 1" 'plan-waves: companions_malformed'
done
# Exactly ONE JSON document: a malformed first document followed by a valid one must not pass on
# the strength of the last document alone (and two valid documents are not that shape either).
printf '%s\n%s\n' '{"schema_version":2,"companions":[{"when":"a/*","add":["b"]}]}' '{"schema_version":1,"companions":[]}' > "$W_M/.agent/companions.json"
w_run "$W_M" "$H" "$W_T/list" --max 2
w_fails "W13 two documents, malformed first + valid second ⇒ exit 1" 'plan-waves: companions_malformed'
printf '%s\n%s\n' '{"schema_version":1,"companions":[]}' '{"schema_version":1,"companions":[]}' > "$W_M/.agent/companions.json"
w_run "$W_M" "$H" "$W_T/list" --max 2
w_fails "W13 two valid documents ⇒ exit 1 (exactly one document)" 'plan-waves: companions_malformed'
printf '{"schema_version":1,"companions":[]}\n' > "$W_M/.agent/companions.json"
W_RC=0; W_OUT="$(LOOMWRIGHT_JQ_BIN=/nonexistent/jq bash "$H" plan-waves "$W_T/list" --root "$W_M" --max 2 2>"$W_T/err")" || W_RC=$?; W_ERR="$(cat "$W_T/err")"
w_fails "W13 jq absent while companions.json exists ⇒ exit 1 companions_malformed" 'plan-waves: companions_malformed jq not found'

# W14 a fenced `## Touches` is ignored; a real one beside a fenced one still parses.
rm -rf "$W_T/q"
mkdir -p "$W_T/q"; printf '# a\n## Depends on\nnone\n\n## Example\n```markdown\n## Touches\na/x\n```\n' > "$W_T/q/01-a.md"
w_item q/02-b.md none 'b'
printf '# c\n## Depends on\nnone\n## Example\n```\n## Touches\nb\n```\n## Touches\nc\n' > "$W_T/q/03-c.md"
w_list q/01-a.md q/02-b.md q/03-c.md; w_run "$W_T" "$H" "$W_T/list" --max 3
w_expect "W14 fenced ## Touches ignored (01 unknown ⇒ alone); a real section after a fenced one parses (03 known)" 'wave 1: q/01-a.md\nwave 2: q/02-b.md q/03-c.md'

# W15 harness-port shape (fixture copy): 01→04→06, 02, 03 independent, 05→07 sharing skills/review-heal/SKILL.md.
rm -rf "$W_T/hp"
w_item hp/01-worker-rules.md none 'agents/worker.md\ndocs/prompt-token-budgets.json'
w_item hp/02-not-ready-stamp.md none 'scripts/automate-helpers.sh'
w_item hp/03-cited-line-premise.md none 'agents/worker.md'
w_item hp/04-not-verified-transport.md '01' 'agents/worker.md\ndocs/RESULT_SCHEMAS.md'
w_item hp/05-dismissed-findings.md none 'skills/review-heal/SKILL.md\ndocs/RESULT_SCHEMAS.md'
w_item hp/06-shared-local-services.md '04' 'agents/worker.md'
w_item hp/07-ci-trust-probe.md '05' 'skills/review-heal/SKILL.md'
w_run "$W_T" "$H" "$W_T/hp" --max 3
w_wave() { printf '%s\n' "$W_OUT" | awk -v it="$1" '/^wave / { for (i = 3; i <= NF; i++) if ($i ~ ("/" it "$")) { sub(":", "", $2); print $2 } }'; }
w5="$(w_wave 05-dismissed-findings.md)"; w7="$(w_wave 07-ci-trust-probe.md)"; w1="$(w_wave 01-worker-rules.md)"; w3="$(w_wave 03-cited-line-premise.md)"
if [ "$W_RC" -eq 0 ] && [ -n "$w5" ] && [ -n "$w7" ] && [ "$w7" -gt "$w5" ]; then ok "W15 harness-port: 07 lands strictly after 05 (waves $w5 < $w7)"; else no "W15 07 not after 05: $W_OUT"; fi
if [ -n "$w1" ] && [ -n "$w3" ] && [ "$w1" != "$w3" ]; then ok "W15 harness-port: 03 never shares a wave with 01 (both touch agents/worker.md)"; else no "W15 03 shares a wave with 01: $W_OUT"; fi
[ "$(printf '%s\n' "$W_OUT" | grep -c '^blocked')" -eq 0 ] && ok "W15 harness-port: nothing blocked" || no "W15 harness-port blocked lines: $W_OUT"

# W16 the five-item acceptance fixture (two disjoint pairs + one dependent, --max 3), byte-for-byte.
rm -rf "$W_T/q"
w_item q/01-a.md none 'p/'
w_item q/02-b.md none 'r/'
w_item q/03-c.md none 'p/x.sh'
w_item q/04-d.md none 'r/y.sh'
w_item q/05-e.md '01' 's/'
w_list q/01-a.md q/02-b.md q/03-c.md q/04-d.md q/05-e.md; w_run "$W_T" "$H" "$W_T/list" --max 3
w_expect "W16 five-item acceptance fixture, byte-for-byte" 'wave 1: q/01-a.md q/02-b.md\nwave 2: q/03-c.md q/04-d.md q/05-e.md'

# W17 usage errors ⇒ exit 1, stdout empty.
w_run "$W_T" "$H" "$W_T/list"; w_fails "W17 --max missing ⇒ usage" 'usage:'
for m in 0 x -1 ''; do w_run "$W_T" "$H" "$W_T/list" --max "$m"; w_fails "W17 --max '$m' ⇒ usage" 'usage:'; done
w_run "$W_T" "$H" "$W_T/nope" --max 2; w_fails "W17 missing input ⇒ usage" 'usage:'
w_run "$W_T" "$H" "$W_T/list" --max 2 --bogus; w_fails "W17 unknown option ⇒ usage" 'usage:'
W_RC=0; W_OUT="$(bash "$H" plan-waves "$W_T/list" --max 2 --root --x 2>"$W_T/err")" || W_RC=$?; W_ERR="$(cat "$W_T/err")"
w_fails "W17 option-shaped --root ⇒ refused" '--root requires a checkout path'

# W18 read-only: no file written in the fixture root, the only git call is rev-parse --show-toplevel, never gh.
mkdir -p "$W_T/spy"
printf '#!/bin/sh\necho "git $*" >> "%s/spy/calls"\nexit 1\n' "$W_T" > "$W_T/spy/git"
printf '#!/bin/sh\necho "gh $*" >> "%s/spy/calls"\nexit 1\n' "$W_T" > "$W_T/spy/gh"
chmod +x "$W_T/spy/git" "$W_T/spy/gh"; : > "$W_T/spy/calls"
w_before="$(cd "$W_T" && find q list -print | env LC_ALL=C sort | xargs ls -ld 2>/dev/null | awk '{ print $5, $NF }')"
W_RC=0; W_OUT="$(cd "$W_T" && PATH="$W_T/spy:$PATH" bash "$H" plan-waves list --max 3 2>/dev/null)" || W_RC=$?
w_after="$(cd "$W_T" && find q list -print | env LC_ALL=C sort | xargs ls -ld 2>/dev/null | awk '{ print $5, $NF }')"
[ "$W_RC" -eq 0 ] && [ "$(cat "$W_T/spy/calls")" = "git rev-parse --show-toplevel" ] && ok "W18 only git call is rev-parse --show-toplevel; no gh; --root fell back to \$PWD" || no "W18 calls: $(tr '\n' '|' < "$W_T/spy/calls") rc=$W_RC"
[ "$w_before" = "$w_after" ] && [ ! -e "$W_T/.agent" ] && ok "W18 fixture tree unchanged after plan-waves (writes only its mktemp -d)" || no "W18 fixture tree changed"

# W19 every `## Touches` section under the REAL .supervisor/requirements/parallel-automate/ parses (not unknown).
#     Read through a plan-waves ITEM-LIST run on a copy of each file with its `## Depends on` section dropped
#     (so the copy is first and dependency-free) paired with a disjoint probe: known ⇒ copy + probe share wave 1,
#     unknown ⇒ the copy runs alone. Gitignored, so absent in CI / fresh worktrees ⇒ SKIP.
W_PA="$W_REPO/.supervisor/requirements/parallel-automate"
if [ -d "$W_PA" ]; then
  w_n=0; mkdir -p "$W_T/pa"
  for f in "$W_PA"/*.md; do
    [ -f "$f" ] && grep -q '^## Touches$' "$f" || continue
    w_n=$((w_n+1))
    awk '/^## Depends on$/ { skip = 1; next } skip && (/^# / || /^## /) { skip = 0 } !skip' "$f" > "$W_T/pa/01-copy.md"
    printf '# probe\n## Depends on\nnone\n## Touches\nzz-plan-waves-probe-only/\n' > "$W_T/pa/02-probe.md"
    printf 'pa/01-copy.md\npa/02-probe.md\n' > "$W_T/list"
    w_run "$W_T" "$H" "$W_T/list" --max 2
    w_expect "W19 real $(basename "$f") ## Touches parses (known)" 'wave 1: pa/01-copy.md pa/02-probe.md'
  done
  [ "$w_n" -gt 0 ] && ok "W19 checked $w_n real parallel-automate Touches sections" || no "W19 no Touches section found under $W_PA"
else
  echo "  SKIP: W19 $W_PA absent (gitignored) — real-queue Touches parse not checked here"
fi

# W20 the shipped .agent/companions.json "new" rules cover EVERY surface in scripts/check-doc-currency.sh's
#     FILES array (the authority). Parse drops comments, strips quotes, resolves $PLUGIN_JSON from its own
#     assignment line, FAILS on any other unresolved $ token, and must be non-empty and contain plugin.json.
W_DC="$W_REPO/scripts/check-doc-currency.sh"; W_CJ="$W_REPO/.agent/companions.json"
w_pj="$(sed -n 's/^PLUGIN_JSON="\([^"]*\)"$/\1/p' "$W_DC" | head -n1)"
w_dc_entry() {  # one FILES entry ⇒ its path; $PLUGIN_JSON resolved; any other $ token marked UNRESOLVED
  case "$1" in
    '$PLUGIN_JSON') printf '%s\n' "$w_pj" ;;
    *'$'*) printf 'UNRESOLVED:%s\n' "$1" ;;
    *) printf '%s\n' "$1" ;;
  esac
}
w_files="$(awk '/^FILES=\(/ { p = 1; next } p && /^\)/ { exit } p' "$W_DC" \
  | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^#' | grep -v '^$' | tr -d '"' \
  | while IFS= read -r e; do w_dc_entry "$e"; done)"
if [ -z "$w_files" ] || [ -z "$w_pj" ]; then no "W20 parsed FILES set (or PLUGIN_JSON) is empty"
elif grep -q '^UNRESOLVED:' <<<"$w_files"; then no "W20 unresolved \$ token in FILES: $(printf '%s' "$w_files" | grep '^UNRESOLVED:' | tr '\n' ' ')"
elif ! grep -qxF 'loomwright/.claude-plugin/plugin.json' <<<"$w_files"; then no "W20 parsed FILES lacks loomwright/.claude-plugin/plugin.json"
else
  w_miss=""
  for pfx in 'loomwright/agents/*' 'loomwright/commands/*' 'loomwright/skills/*'; do
    w_add="$(jq -r --arg w "$pfx" '.companions[] | select(.when == $w and .new == true) | .add[]' "$W_CJ" 2>/dev/null)"
    [ -n "$w_add" ] || w_miss="$w_miss [no new rule for $pfx]"
    while IFS= read -r e; do grep -qxF -- "$e" <<<"$w_add" || w_miss="$w_miss [$pfx lacks $e]"; done <<EOF
$w_files
EOF
  done
  [ -z "$w_miss" ] && ok "W20 shipped companions.json new rules cover all $(printf '%s\n' "$w_files" | wc -l | tr -d ' ') check-doc-currency.sh FILES entries" || no "W20 companions.json drifted from check-doc-currency.sh FILES:$w_miss"
fi

# =============================================================================
echo "== X. plan-waves --explain / --lint (parallel-automate/10: read-only; one grammar with the planner) =="
# x_rc <label> <expected rc> <expected stdout (printf %b)> — exact stdout AND exit code.
x_rc() {
  local want; want="$(printf '%b' "$3")"
  if [ "$W_RC" -eq "$2" ] && [ "$W_OUT" = "$want" ]; then ok "$1"; else no "$1 (rc=$W_RC, want $2) got: $(printf '%s' "$W_OUT" | tr '\n' '|') err: $W_ERR"; fi
}
# x_has <label> <line> — W_OUT contains <line> as a whole line.
x_has() { if grep -qxF -- "$2" <<<"$W_OUT"; then ok "$1"; else no "$1 — missing line '$2' in: $(printf '%s' "$W_OUT" | tr '\n' '|')"; fi; }

# X1 every --explain reason shape, each on a fixture that produces it (AC-2), stdout byte-for-byte.
rm -rf "$W_T/q"
w_item q/01-a.md none 'a/'; w_item q/02-b.md none 'a/b.sh'
w_list q/01-a.md q/02-b.md; w_run "$W_T" "$H" "$W_T/list" --max 3 --explain
x_rc "X1 explain: declared conflict names the item and the contained path" 0 'wave 1: q/01-a.md\nwave 2: q/02-b.md\nexplain q/02-b.md (wave 2):\n  conflicts with q/01-a.md on a/b.sh (declared)'
printf 'q/01-s1.md\nq/02-s2.md\n' > "$W_T/list"
w_run "$W_C" "$H" "$W_T/list" --max 3 --explain
x_rc "X1 explain: companion conflict names the rule's when" 0 'wave 1: q/01-s1.md\nwave 2: q/02-s2.md\nexplain q/02-s2.md (wave 2):\n  conflicts with q/01-s1.md on x/skills/SKILLS_INDEX.md (companion: x/skills/*/SKILL.md)'
rm -rf "$W_T/q" "$W_T/other"
w_item q/01-a.md '../other/05-y.md' 'a'; w_item q/02-b.md '1' 'b'; w_item other/05-y.md none 'y'
w_list q/01-a.md q/02-b.md other/05-y.md; w_run "$W_T" "$H" "$W_T/list" --max 3 --explain
x_rc "X1 explain: depends on <item> (display path of the in-set dependency)" 0 'wave 1: other/05-y.md\nwave 2: q/01-a.md\nwave 3: q/02-b.md\nexplain q/01-a.md (wave 2):\n  depends on other/05-y.md\nexplain q/02-b.md (wave 3):\n  depends on q/01-a.md'
w_alone missing -; w_run "$W_T" "$H" "$W_T/list" --max 3 --explain
x_rc "X1 explain: runs alone: Touches unknown (missing)" 0 'wave 1: q/01-a.md q/03-c.md\nwave 2: q/02-b.md\nexplain q/02-b.md (wave 2):\n  runs alone: Touches unknown (missing)'
w_alone bullet '- b/x.sh'; w_run "$W_T" "$H" "$W_T/list" --max 3 --explain
x_rc "X1 explain: runs alone: Touches unknown (unparsable line <N>: \"<text>\"), N 1-based in the item file" 0 'wave 1: q/01-a.md q/03-c.md\nwave 2: q/02-b.md\nexplain q/02-b.md (wave 2):\n  runs alone: Touches unknown (unparsable line 7: "- b/x.sh")'
w_alone unknown 'unknown'; w_run "$W_T" "$H" "$W_T/list" --max 3 --explain
x_rc "X1 explain: runs alone: Touches unknown (declared unknown)" 0 'wave 1: q/01-a.md q/03-c.md\nwave 2: q/02-b.md\nexplain q/02-b.md (wave 2):\n  runs alone: Touches unknown (declared unknown)'
rm -rf "$W_T/q"; w_item q/01-a.md none 'a'; w_item q/02-b.md - 'b'
w_list q/01-a.md q/02-b.md; w_run "$W_T" "$H" "$W_T/list" --max 3 --explain
x_rc "X1 explain: runs alone: Depends on missing ⇒ depends on every earlier item" 0 'wave 1: q/01-a.md\nwave 2: q/02-b.md\nexplain q/02-b.md (wave 2):\n  runs alone: Depends on missing ⇒ depends on every earlier item'
rm -rf "$W_T/q"; w_item q/01-a.md none 'a'; w_item q/02-b.md none 'b'; w_item q/03-c.md none 'c'
w_list q/01-a.md q/02-b.md q/03-c.md; w_run "$W_T" "$H" "$W_T/list" --max 2 --explain
x_rc "X1 explain: wave <w> full (--max <N>)" 0 'wave 1: q/01-a.md q/02-b.md\nwave 2: q/03-c.md\nexplain q/03-c.md (wave 2):\n  wave 1 full (--max 2)'
rm -rf "$W_T/q"; w_item q/01-a.md none -; w_item q/02-b.md none 'b'; w_item q/03-c.md none 'c'
w_list q/01-a.md q/02-b.md q/03-c.md; w_run "$W_T" "$H" "$W_T/list" --max 3 --explain
x_rc "X1 explain: wave <w> runs <item> alone (Touches unknown)" 0 'wave 1: q/01-a.md\nwave 2: q/02-b.md q/03-c.md\nexplain q/02-b.md (wave 2):\n  wave 1 runs q/01-a.md alone (Touches unknown)\nexplain q/03-c.md (wave 2):\n  wave 1 runs q/01-a.md alone (Touches unknown)'
# Every reason of a multi-wave item, each distinct reason once (a conflict in wave 1, a dependency in wave 2).
rm -rf "$W_T/q"; w_item q/01-a.md none 'a'; w_item q/02-b.md none 'b'; w_item q/03-c.md '02' 'a/x'
w_list q/01-a.md q/02-b.md q/03-c.md; w_run "$W_T" "$H" "$W_T/list" --max 1 --explain
x_rc "X1 explain: every reason across earlier waves, each once" 0 'wave 1: q/01-a.md\nwave 2: q/02-b.md\nwave 3: q/03-c.md\nexplain q/02-b.md (wave 2):\n  wave 1 full (--max 1)\nexplain q/03-c.md (wave 3):\n  depends on q/02-b.md'

# X2 --explain leaves the wave/blocked lines and the exit codes alone (AC-1/AC-2): its stdout up to
#    the first `explain ` line equals the default run on the same input; errors stay exit 1 + empty stdout.
x_same() {  # <label> <root> <input> <max>
  local base
  w_run "$2" "$H" "$3" --max "$4"; base="$W_OUT"
  w_run "$2" "$H" "$3" --max "$4" --explain
  if [ "$W_RC" -eq 0 ] && [ "$(printf '%s\n' "$W_OUT" | awk '/^explain /{exit} {print}')" = "$base" ]; then ok "$1"; else no "$1 (rc=$W_RC) base: $(printf '%s' "$base" | tr '\n' '|') explain: $(printf '%s' "$W_OUT" | tr '\n' '|')"; fi
}
rm -rf "$W_T/q"
w_item q/01-a.md none 'p/'; w_item q/02-b.md none 'r/'; w_item q/03-c.md none 'p/x.sh'; w_item q/04-d.md none 'r/y.sh'; w_item q/05-e.md '01' 's/'
w_list q/01-a.md q/02-b.md q/03-c.md q/04-d.md q/05-e.md
x_same "X2 five-item fixture: --explain prefix == default output" "$W_T" "$W_T/list" 3
w_item q/06-f.md '07' 'f'; w_item q/07-g.md none 'g' 'parked (waits)'
w_list q/01-a.md q/02-b.md q/06-f.md q/03-c.md
x_same "X2 a blocked line is unchanged under --explain" "$W_T" "$W_T/list" 2
x_has "X2 blocked item keeps its blocked line under --explain" 'blocked q/06-f.md: depends on parked 07'
case "$W_OUT" in *"explain q/06-f.md"*) no "X2 a blocked item got an explain block" ;; *) ok "X2 a blocked item gets no explain block (its blocked line is its reason)" ;; esac
rm -rf "$W_T/q"; w_item q/01-a.md '02' 'a'; w_item q/02-b.md '01' 'b'
w_list q/01-a.md q/02-b.md; w_run "$W_T" "$H" "$W_T/list" --max 3 --explain
w_fails "X2 --explain on a cycle ⇒ exit 1, empty stdout" 'plan-waves: dependency cycle: q/01-a.md q/02-b.md'
w_run "$W_T" "$H" "$W_T/list" --explain; w_fails "X2 --explain still needs --max" 'usage:'
w_run "$W_T" "$H" "$W_T/list" --max 2 --explain --lint; w_fails "X2 --explain with --lint ⇒ usage" '--explain and --lint are separate modes'

# X2b --explain state does not leak across calls in ONE shell process: the helper's functions are
#     sourced (its trailing `main "$@"` dispatch line dropped, `main` itself untouched), plan_waves
#     runs --explain and then a default call, and the second call must equal a fresh default run
#     byte-for-byte with no `explain ` line (a global _PW_EXPLAIN set by call 1 and never reset fails it).
rm -rf "$W_T/q"; w_item q/01-a.md none 'a/'; w_item q/02-b.md none 'a/b.sh'
w_list q/01-a.md q/02-b.md
w_run "$W_T" "$H" "$W_T/list" --max 3; X2B_FRESH="$W_OUT"
mkdir -p "$W_T/x2b-tmp"
X2B_RC=0
X2B_OUT="$(TMPDIR="$W_T/x2b-tmp" bash -c '
  grep -qx "main \"\$@\"" "$1" || { echo "no trailing main dispatch line" >&2; exit 3; }
  source <(sed "/^main \"\\\$@\"\$/d" "$1")
  plan_waves "$2" --root "$3" --max 3 --explain > /dev/null
  plan_waves "$2" --root "$3" --max 3
' _ "$H" "$W_T/list" "$W_T" 2>"$W_T/err")" || X2B_RC=$?
if [ "$X2B_RC" -eq 0 ] && [ -n "$X2B_FRESH" ] && [ "$X2B_OUT" = "$X2B_FRESH" ] && ! grep -q '^explain ' <<<"$X2B_OUT"; then
  ok "X2b a default plan_waves call after an --explain call in the same shell is byte-identical to a fresh default run"
else
  no "X2b --explain leaked into a later default call (rc=$X2B_RC) got: $(printf '%s' "$X2B_OUT" | tr '\n' '|') fresh: $(printf '%s' "$X2B_FRESH" | tr '\n' '|') err: $(cat "$W_T/err")"
fi
rm -rf "$W_T/x2b-tmp"

# X3 --lint: every malformed shape flagged with its 1-based line, the exact text and the reason (AC-3/AC-4).
#    Single-item input; the w_item layout puts the Depends on body on line 4, the Touches body on line 7.
x_lint_t() {  # <label> <Touches body> <expected Touches verdict> <expected rc>
  rm -rf "$W_T/q"; w_item q/02-b.md none "$2"
  w_run "$W_T" "$H" "$W_T/q/02-b.md" --lint
  local runs="0 of 1 items will run alone: none"
  case "$3" in ok) ;; *) runs="1 of 1 items will run alone: $W_T/q/02-b.md" ;; esac
  x_rc "$1" "$4" "$W_T/q/02-b.md: Touches $3; Depends on ok\n$runs\n0 of 1 items depend on every earlier item: none"
}
x_lint_t "X3 lint: a path list is ok (exit 0)" 'b/x.sh\nb/dir/' ok 0
x_lint_t "X3 lint: a sole unknown is ok (declared unknown) and does NOT set exit 1" 'unknown' 'ok (declared unknown)' 0
x_lint_t "X3 lint: parenthetical '(only if a test exposes a defect)' flagged" '(only if a test exposes a defect)' 'line 7: "(only if a test exposes a defect)" — parenthetical/prose' 1
x_lint_t "X3 lint: '(part B)' flagged" 'b/x.sh (part B)' 'line 7: "b/x.sh (part B)" — parenthetical/prose' 1
x_lint_t "X3 lint: comma list 'a, b' flagged" 'a, b' 'line 7: "a, b" — comma list' 1
x_lint_t "X3 lint: '- ' bullet flagged" '- b/x.sh' 'line 7: "- b/x.sh" — "- " bullet' 1
x_lint_t "X3 lint: backticks flagged" '`b/x.sh`' 'line 7: "`b/x.sh`" — backticks' 1
x_lint_t "X3 lint: prose flagged" 'b/x.sh and friends' 'line 7: "b/x.sh and friends" — parenthetical/prose' 1
x_lint_t "X3 lint: leading / flagged" '/b/x.sh' 'line 7: "/b/x.sh" — leading /' 1
x_lint_t "X3 lint: '..' segment flagged" 'b/../x' 'line 7: "b/../x" — . or .. segment' 1
x_lint_t "X3 lint: './' segment flagged" './b/x.sh' 'line 7: "./b/x.sh" — . or .. segment' 1
x_lint_t "X3 lint: '//' flagged" 'b//x.sh' 'line 7: "b//x.sh" — //' 1
x_lint_t "X3 lint: a glob character flagged" 'b/*.sh' 'line 7: "b/*.sh" — character outside [A-Za-z0-9._/@+-]' 1
x_lint_t "X3 lint: trailing whitespace flagged" 'b/x.sh ' 'line 7: "b/x.sh " — leading/trailing whitespace' 1
x_lint_t "X3 lint: unknown mixed with paths flagged on the unknown line" 'b/x.sh\nunknown' 'line 8: "unknown" — unknown mixed with paths' 1
x_lint_t "X3 lint: empty section flagged on its heading" '' 'line 6: "## Touches" — empty section' 1
x_lint_t "X3 lint: duplicated section flagged on the second heading" 'b/x.sh\n\n## Touches\nb/y.sh' 'line 9: "## Touches" — duplicated section' 1
x_lint_t "X3 lint: several bad lines ⇒ the first, plus a count" '- a\n- b' 'line 7: "- a" — "- " bullet (+1 more)' 1
rm -rf "$W_T/q"; w_item q/02-b.md none -
w_run "$W_T" "$H" "$W_T/q/02-b.md" --lint
x_rc "X3 lint: missing Touches ⇒ missing section, exit 1" 1 "$W_T/q/02-b.md: Touches missing section; Depends on ok\n1 of 1 items will run alone: $W_T/q/02-b.md\n0 of 1 items depend on every earlier item: none"
x_lint_d() {  # <label> <Depends body|-> <expected Depends verdict> <expected rc>
  rm -rf "$W_T/q"; w_item q/02-b.md "$2" 'b/x.sh'
  w_run "$W_T" "$H" "$W_T/q/02-b.md" --lint
  local dep="0 of 1 items depend on every earlier item: none"
  case "$3" in ok) ;; *) dep="1 of 1 items depend on every earlier item: $W_T/q/02-b.md" ;; esac
  x_rc "$1" "$4" "$W_T/q/02-b.md: Touches ok; Depends on $3\n0 of 1 items will run alone: none\n$dep"
}
x_lint_d "X3 lint: valid Touches and NO Depends on ⇒ exit 1" - 'missing section' 1
x_lint_d "X3 lint: Depends on ids and paths are ok" '03\n../other/01-x.md' ok 0
x_lint_d "X3 lint: Depends on none mixed with ids" 'none\n03' 'line 4: "none" — none mixed with ids' 1
x_lint_d "X3 lint: Depends on none repeated" 'none\nnone' 'line 5: "none" — none repeated' 1
x_lint_d "X3 lint: Depends on prose ⇒ not an id or *.md path" 'item 03 (part B)' 'line 4: "item 03 (part B)" — not an id or *.md path' 1
x_lint_d "X3 lint: Depends on 4-digit id ⇒ not an id or *.md path" '0003' 'line 4: "0003" — not an id or *.md path' 1
x_lint_d "X3 lint: Depends on empty section" '' 'line 3: "## Depends on" — empty section' 1
x_lint_d "X3 lint: Depends on duplicated" 'none\n\n## Depends on\nnone' 'line 6: "## Depends on" — duplicated section (+1 more)' 1
# Directory input = what the folder intake would enqueue (resolve_folder: done / proposed / parked skipped).
rm -rf "$W_T/q"
w_item q/01-a.md none 'a'; w_item q/02-b.md - 'b'; w_item q/03-c.md none 'c' 'done'; w_item q/04-d.md none 'd' 'proposed'
w_run "$W_T" "$H" "$W_T/q" --lint
x_rc "X3 lint: directory input lints exactly the resolve_folder set; one line per item + two count lines; exit 1" 1 "$W_T/q/01-a.md: Touches ok; Depends on ok\n$W_T/q/02-b.md: Touches ok; Depends on missing section\n0 of 2 items will run alone: none\n1 of 2 items depend on every earlier item: $W_T/q/02-b.md"
w_run "$W_T" "$H" "$W_T/q/" --lint --max 0
[ "$W_RC" -eq 1 ] && [ -n "$W_OUT" ] && ok "X3 lint: --max is ignored (even an invalid one) — lint never needs it" || no "X3 lint with --max 0: rc=$W_RC out='$W_OUT' err=$W_ERR"
# Item-list and run-file inputs resolve the plan set exactly as the planner does.
w_list q/01-a.md
w_run "$W_T" "$H" "$W_T/list" --lint
x_rc "X3 lint: item-list input (display = the list line)" 0 'q/01-a.md: Touches ok; Depends on ok\n0 of 1 items will run alone: none\n0 of 1 items depend on every earlier item: none'
printf '# Automate Run: automate-test\n## Status: running\n## Queue\n- [x] q/03-c.md\n- [ ] q/02-b.md\n## Current\n' > "$W_T/run-lint.md"
w_run "$W_T" "$H" "$W_T/run-lint.md" --lint
x_rc "X3 lint: run-file input = its unchecked Queue rows" 1 'q/02-b.md: Touches ok; Depends on missing section\n0 of 1 items will run alone: none\n1 of 1 items depend on every earlier item: q/02-b.md'
w_list q/01-a.md q/09-gone.md; w_run "$W_T" "$H" "$W_T/list" --lint
w_fails "X3 lint: an item that names no file ⇒ exit 1, empty stdout" 'plan-waves: item not found: q/09-gone.md'
w_run "$W_T" "$H" "$W_T/nope.md" --lint; w_fails "X3 lint: missing input ⇒ usage" 'usage:'

# X4 one grammar (AC-5): on every shape, lint `ok`/`ok (declared unknown)` vs failure agrees with
#    what the planner reads — Touches known ⇔ the middle item shares wave 1 with two disjoint items;
#    Depends on parsed ⇔ the second item shares wave 1 (its dependency 03 is out of the plan set and done).
x_agree_n=0
while IFS='|' read -r x_lbl x_body; do
  [ -n "$x_lbl" ] || continue
  w_alone "$x_lbl" "$x_body"; x_plan="$W_OUT"
  w_run "$W_T" "$H" "$W_T/q/02-b.md" --lint
  x_v="$(printf '%s\n' "$W_OUT" | sed -n '1s/^.*: Touches \(.*\); Depends on .*$/\1/p')"
  if [ "$x_plan" = "wave 1: q/01-a.md q/02-b.md q/03-c.md" ]; then x_known=1; else x_known=0; fi
  if [ "$x_v" = ok ]; then x_lok=1; else x_lok=0; fi
  if [ "$x_known" -eq "$x_lok" ] && [ -n "$x_v" ]; then x_agree_n=$((x_agree_n+1)); else no "X4 Touches '$x_lbl': planner known=$x_known but lint says '$x_v'"; fi
done <<'SHAPES'
path|b/x.sh
dir|b/
two|b/x.sh\nb/y.sh
blank-lines|b/x.sh\n\nb/y.sh
dot-name|b/.x.sh
unknown|unknown
unknown-twice|unknown\nunknown
backtick|`b/x.sh`
glob|b/*.sh
pipe|a|b
prose|b/x.sh and friends
bullet|- b/x.sh
paren|(only if a test exposes a defect)
comma|a, b
mixed|b/x.sh\nunknown
empty|
dotdot|b/../x
dot|.
dot-lead|./b/x.sh
lead-slash|/b/x.sh
double-slash|b//x.sh
trailing-space|b/x.sh\0040
duplicate|b/x.sh\n\n## Touches\nb/y.sh
fence|b/x.sh\n```\nb/y.sh\n```
SHAPES
[ "$x_agree_n" -eq 24 ] && ok "X4 lint ok ⇔ planner known on all 24 Touches shapes" || no "X4 Touches agreement on $x_agree_n of 24 shapes"
x_agree_n=0
while IFS='|' read -r x_lbl x_body; do
  [ -n "$x_lbl" ] || continue
  rm -rf "$W_T/q"; w_item q/01-a.md none 'a'; w_item q/02-b.md "$x_body" 'b'; w_item q/03-c.md none 'c' 'done'
  w_list q/01-a.md q/02-b.md; w_run "$W_T" "$H" "$W_T/list" --max 3; x_plan="$W_OUT"
  w_run "$W_T" "$H" "$W_T/q/02-b.md" --lint
  x_v="$(printf '%s\n' "$W_OUT" | sed -n '1s/^.*; Depends on \(.*\)$/\1/p')"
  if [ "$x_plan" = "wave 1: q/01-a.md q/02-b.md" ]; then x_known=1; else x_known=0; fi
  if [ "$x_v" = ok ]; then x_lok=1; else x_lok=0; fi
  if [ "$x_known" -eq "$x_lok" ] && [ -n "$x_v" ]; then x_agree_n=$((x_agree_n+1)); else no "X4 Depends '$x_lbl': planner parsed=$x_known ($x_plan) but lint says '$x_v'"; fi
done <<'SHAPES'
none|none
id|03
id-1|3
path|03-c.md
rel-path|../q/03-c.md
none-mixed|none\n03
none-twice|none\nnone
prose|item 03 (part B)
four-digit|0003
bullet|- 03
empty|
fence|03\n```\n03\n```
SHAPES
rm -rf "$W_T/q"; w_item q/01-a.md none 'a'; w_item q/02-b.md - 'b'
w_list q/01-a.md q/02-b.md; w_run "$W_T" "$H" "$W_T/list" --max 3; x_plan="$W_OUT"
w_run "$W_T" "$H" "$W_T/q/02-b.md" --lint
case "$x_plan|$W_OUT" in "wave 1: q/01-a.md"*"Depends on missing section"*) x_agree_n=$((x_agree_n+1)) ;; *) no "X4 Depends 'missing': $x_plan / $W_OUT" ;; esac
[ "$x_agree_n" -eq 13 ] && ok "X4 lint ok ⇔ planner parsed on all 13 Depends on shapes" || no "X4 Depends agreement on $x_agree_n of 13 shapes"

# X5 read-only: --lint and --explain write nothing in the fixture tree; the only git call is rev-parse.
rm -rf "$W_T/q"; w_item q/01-a.md none 'a'; w_item q/02-b.md - 'b'; w_list q/01-a.md q/02-b.md
for x_mode in "--lint" "--max 3 --explain"; do
  : > "$W_T/spy/calls"
  w_before="$(cd "$W_T" && find q list -print | env LC_ALL=C sort | xargs ls -ld 2>/dev/null | awk '{ print $5, $NF }')"
  # shellcheck disable=SC2086 # word-split on purpose: the mode's flags
  W_RC=0; W_OUT="$(cd "$W_T" && PATH="$W_T/spy:$PATH" bash "$H" plan-waves list $x_mode 2>/dev/null)" || W_RC=$?
  w_after="$(cd "$W_T" && find q list -print | env LC_ALL=C sort | xargs ls -ld 2>/dev/null | awk '{ print $5, $NF }')"
  [ -n "$W_OUT" ] && [ "$(cat "$W_T/spy/calls")" = "git rev-parse --show-toplevel" ] && [ "$w_before" = "$w_after" ] \
    && ok "X5 plan-waves list $x_mode: read-only (tree unchanged, only git rev-parse, no gh)" \
    || no "X5 $x_mode: rc=$W_RC calls=$(tr '\n' '|' < "$W_T/spy/calls") out='$W_OUT'"
done

# X6 MUTATION CONTROL (AC-4): a helper copy whose ONE grammar line also accepts `(`, `)` and spaces
#    must turn X3's parenthetical assertion red — the lint verdict comes from that line, not a copy.
sed '/# PW_TOUCHES_GRAMMAR/s|!/^\[A-Za-z0-9._\\/@+-\]+\$/|!/^[A-Za-z0-9._\\/@+() -]+$/|' "$H" > "$W_T/mut-paren.sh"
if [ -s "$W_T/mut-paren.sh" ] && ! cmp -s "$H" "$W_T/mut-paren.sh" && bash -n "$W_T/mut-paren.sh"; then
  rm -rf "$W_T/q"; w_item q/02-b.md none '(only if a test exposes a defect)'
  w_run "$W_T" "$W_T/mut-paren.sh" "$W_T/q/02-b.md" --lint
  case "$W_OUT" in
    *"Touches ok; "*) ok "X6 MUTATION CONTROL: grammar-accepts-parenthetical mutant turns X3's parenthetical assertion red (lint now says ok, rc=$W_RC)" ;;
    *) no "X6 mutation control stayed green — the X3 parenthetical assertion is vacuous: $W_OUT" ;;
  esac
  w_run "$W_T" "$H" "$W_T/q/02-b.md" --lint
  x_has "X6 mutation control: the REAL helper still flags it" "$W_T/q/02-b.md: Touches line 7: \"(only if a test exposes a defect)\" — parenthetical/prose; Depends on ok"
else no "X6 mutation control inconclusive: mutant empty, identical or not valid bash"; fi

# X7 GRAMMAR DRIFT: the Touches path grammar is hand-copied in three places that share no code —
#    the PW_TOUCHES_GRAMMAR line (this helper's --lint), PATH_TOK / BAD_SEG beside touches_of in
#    automate-dismissed.sh, and vt_touches in propose-from-verify.sh. One token set, every token's file
#    created under a fixture root (so only the grammar can reject it), runs through all three; each must
#    accept/reject exactly as the expected column. Tokens stay inside the SHARED grammar: the two
#    extractors' own extra rules (needs `/` or `.`, no trailing `/`, trailing `.` stripped) are not
#    exercised. The extractor copies are run straight out of their scripts (sed-extracted), never re-typed.
X7_R="$W_T/x7"; rm -rf "$X7_R"
x7_tokens='src/a.ts|1 @scope/x.ts|1 -dash/x.ts|1 a+b/c_d.v1.md|1 /abs/x.ts|0 a//b.ts|0 ./c.ts|0 d/../c.ts|0 d/./c.ts|0 e/f~g.ts|0 e/f$g.ts|0'
for x7_p in src/a.ts @scope/x.ts -dash/x.ts a+b/c_d.v1.md abs/x.ts a/b.ts c.ts d/c.ts 'e/f~g.ts' 'e/f$g.ts'; do
  mkdir -p "$X7_R/$(dirname -- "$x7_p")"; : > "$X7_R/$x7_p"
done
X7_PY="$(sed -n '/^PATH_TOK = re.compile/,/^    return found$/p' "$HERE/automate-dismissed.sh")"
X7_SH="$(sed -n '/^vt_touches() {$/,/^}$/p' "$HERE/propose-from-verify.sh")"
if [ -z "$X7_PY" ] || ! grep -q '^def touches_of' <<<"$X7_PY" || [ -z "$X7_SH" ]; then
  no "X7 drift test could not extract the grammar copies (PATH_TOK..touches_of / vt_touches moved?)"
else
  for x7_e in $x7_tokens; do
    x7_t="${x7_e%|*}"; x7_want="${x7_e#*|}"
    rm -rf "$W_T/q"; w_item q/02-b.md none "$x7_t"
    w_run "$X7_R" "$H" "$W_T/q/02-b.md" --lint
    case "$W_OUT" in *": Touches ok; "*) x7_awk=1 ;; *) x7_awk=0 ;; esac
    x7_py="$(X7_CODE="$X7_PY" python3 -c '
import os, re, sys
repo_root = sys.argv[1]
exec(os.environ["X7_CODE"])
print(1 if sys.argv[2] in touches_of({"source": sys.argv[2], "finding": ""}) else 0)' "$X7_R" "$x7_t" 2>&1)"
    x7_sh="$(VT_ROOT="$X7_R" bash -c 'eval "$1"; grep -qxF -- "$2" < <(vt_touches "$2") && echo 1 || echo 0' _ "$X7_SH" "$x7_t" 2>&1)"
    if [ "$x7_awk$x7_py$x7_sh" = "$x7_want$x7_want$x7_want" ]; then
      ok "X7 grammar drift: '$x7_t' accepted=$x7_want by all three copies"
    else
      no "X7 grammar drift on '$x7_t' (want $x7_want): PW_TOUCHES_GRAMMAR=$x7_awk touches_of=$x7_py vt_touches=$x7_sh"
    fi
  done
fi
rm -rf "$W_T"
echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
