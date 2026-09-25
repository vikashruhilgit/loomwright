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
#      `remaining` counts ONLY "- [ ]" lines.
#   C. folder / backlog-doc resolvers (skip ## Status: done; documented order).
#   D. resume reconcile: belief pending but gh says merged ⇒ merged; belief checked
#      but gh says open ⇒ awaiting_merge; gh unreadable ⇒ awaiting_merge (fail closed);
#      gh CLOSED-unmerged ⇒ gone.
#   E. auto-merge gate fail-CLOSED on EACH of the 6 conditions individually (incl.
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
#      empty-string-only changed_paths classified DEGRADED.
#   G. brief-repair (fail-SAFE evidence-positive engine seam, v15.65.0): MERGED ⇒
#      the sibling reconcile-jobs.sh --repair --evidence moves the brief (AC-1/2/3/8),
#      OPEN/CLOSED ⇒ skipped with the reconciler NOT invoked (AC-6), TEN separate
#      fail-safe groups each proving run file / ## Status / gate-eval decision /
#      merge.log / brief unchanged (AC-5) — incl. the reconciler-REFUSED branch
#      (a colliding done/ file) and the missing-argument guard with gh never
#      asked — the two SKILL §6 seam pins with per-line
#      mutants (AC-9a), and the invocation-removed helper mutant beside real siblings
#      behind a positive gate (AC-9b).
#   I. ceiling-check (red-team-hardening/06, PICK-time token ceiling; section letter
#      "I" — "H" is already used in-body by the reconcile-status H1-H6 tests above):
#      under-max
#      prints OK; over-max prints PARK: token_ceiling + non-zero total/max; a
#      LEDGER_UNREADABLE=1 reader answer PARKs as ledger_unreadable (fail CLOSED);
#      a missing run file dies (bad usage); a non-integer max_tokens dies; PLUS the
#      AC-mandated mutation control — a read-token-ledger.sh mutant whose numf()
#      always returns 0 makes the known-over-ceiling seam fixture wrongly print OK,
#      proving the breach-parks check is load-bearing, not vacuous.

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
printf '# paused-run\n## Status: paused\n' > "$AUT2/paused.md"
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
printf '# r1\n## Status: running\n' > "$AUT/r1.md"
printf '# r2\n## Status: done\n'    > "$AUT/r2.md"
run_h bash "$H" resume-glob "$AUT"
if [ "$RUN_OUT" = "$AUT/r1.md" ]; then ok "resume-glob: only not-done runs (r1; r2 done excluded)"; else no "resume-glob wrong:\n$RUN_OUT"; fi

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

WD="$(mktemp -d)"; BIN="$WD/bin"; make_stub_bin "$BIN"
export GH_STUB_DIR="$WD/ghstub"; mkdir -p "$GH_STUB_DIR"

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
  printf '{"headRefOid":"abc123","baseRefName":"main","statusCheckRollup":[{"name":"ci","conclusion":"SUCCESS"}]}\n' > "$GH_STUB_DIR/pr-view.json"
  rm -f "$GH_STUB_DIR/pr-view-fail"
  printf '{"reviewDecision":"APPROVED"}\n' > "$GH_STUB_DIR/pr-view-rd.json"
  rm -f "$GH_STUB_DIR/pr-view-rd-fail"
  printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false},"nodes":[]}}}}}\n' > "$GH_STUB_DIR/graphql.json"
  rm -f "$GH_STUB_DIR/graphql-fail"
  printf '{"required_pull_request_reviews":{"required_approving_review_count":1},"required_status_checks":{"contexts":["ci"]}}\n' > "$GH_STUB_DIR/protection.json"
  rm -f "$GH_STUB_DIR/protection-404" "$GH_STUB_DIR/protection-fail"
  printf '{"high_risk": false, "reasons": [], "changed_files": 0, "changed_lines": 0, "source": "classify-risk.sh"}\n' > "$GH_STUB_DIR/risk.json"
  rm -f "$GH_STUB_DIR/merge-fail"
}

# A fully-passing ctx (the SHRUNK shape — exactly the 6 allowed keys).
pass_ctx() {
  cat <<EOF
{
  "drain_result": "READY", "termination_reason": "converged",
  "ready_sha": "abc123",
  "trust_unprotected": false,
  "review_heal_result_path": "$RHR",
  "supervisor_result_path": "$SUP_NA"
}
EOF
}

gate() {  # gate <ctx-json-string> -> sets RUN_OUT/RUN_RC, isolates a fresh merge.log
  rm -f "$GH_STUB_DIR/merge.log"
  printf '%s' "$1" > "$WD/ctx.json"
  RUN_OUT="$( env PATH="$BIN:$PATH" GH_STUB_DIR="$GH_STUB_DIR" HOME="$WD/nohome" bash "$GWD/automate-helpers.sh" gate-eval "$PR" "$WD/ctx.json" --root "$WD" 2>/dev/null )"; RUN_RC=$?
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

J_BASE='{"headRefOid":"abc123","baseRefName":"develop","statusCheckRollup":[{"name":"ci","conclusion":"SUCCESS"}]}'
printf '%s\n' "$J_BASE" > "$GH_STUB_DIR/pr-view.json"
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
RUN_OUT="$( env PATH="$BIN:$PATH" GH_STUB_DIR="$GH_STUB_DIR" HOME="$WD/trustedhome" bash "$GWD/automate-helpers.sh" gate-eval "$PR" "$WD/ctx.json" --root "$WD" 2>/dev/null )"; RUN_RC=$?
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
printf '{"headRefOid":"abc123","baseRefName":"main","statusCheckRollup":[{"name":"ci","conclusion":"FAILURE"}]}\n' > "$GH_STUB_DIR/pr-view.json"
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
  # Instrument the stub classify-risk.sh to prove (positively) whether it was called.
  printf '#!/usr/bin/env bash\necho called >> "%s/classify-risk-called.log"\necho '"'"'{"high_risk": false, "reasons": [], "source": "classify-risk.sh"}'"'"'\n' "$WD" > "$MUT/classify-risk.sh"
  chmod +x "$MUT/classify-risk.sh"
  rm -f "$WD/classify-risk-called.log"
  rm -f "$GH_STUB_DIR/merge.log"
  printf '%s' "$(pass_ctx)" > "$WD/ctx.json"
  MUT_OUT="$( env PATH="$BIN:$PATH" GH_STUB_DIR="$GH_STUB_DIR" HOME="$WD/nohome" bash "$MUT/automate-helpers.sh" gate-eval "$PR" "$WD/ctx.json" --root "$WD" 2>/dev/null )"
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
  rm -f "$WD/classify-risk-called.log" "$GH_STUB_DIR/merge.log"
  printf '%s' "$(pass_ctx)" > "$WD/ctx.json"
  CTRL_OUT="$( env PATH="$BIN:$PATH" GH_STUB_DIR="$GH_STUB_DIR" HOME="$WD/nohome" bash "$CTRL/automate-helpers.sh" gate-eval "$PR" "$WD/ctx.json" --root "$WD" 2>/dev/null )"
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
# view-<key>.json (absent list ⇒ "[]", absent view ⇒ exit 1). Dedicated to
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
    '{state:"MERGED",mergedAt:"2026-09-01T00:00:00Z",number:42,body:("Ships "+$rel),mergeCommit:{oid:"abcdef1234567890"},headRefName:"feature/b"}' \
    > "$r/ghstub/view-$(rs_key "$RS_URL").json"
  printf '[]' > "$r/ghstub/list-$(rs_key ".supervisor/requirements/qh/03-c-open.md").json"
  printf '%s\t%s' "$r" "$relb"
}
rs_run() {
  # rs_run <repo> <args...> — RUN_OUT / RUN_RC set.
  local r="$1"; shift
  RUN_OUT="$(GH_STUB_DIR="$r/ghstub" PATH="$r/bin:$PATH" LOOMWRIGHT_GH_BIN=gh bash "$H" reconcile-status "$@" 2>/dev/null)"; RUN_RC=$?
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
jq -n --arg url "$RS_URL" '{state:"MERGED",mergedAt:"2026-09-01T00:00:00Z",number:42,body:"unrelated prose, no path here",mergeCommit:{oid:"abcdef1234567890"},headRefName:"feature/b"}' \
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

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
