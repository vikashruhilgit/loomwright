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
#      malformed pre-existing config ABORTS (exit 2), crash-stranded backup restored.
#   B. run-file: atomic write produces a parseable file; append-only ## Progress
#      never loses prior lines; queue check-off flips the box (+ skipped form);
#      `remaining` counts ONLY "- [ ]" lines.
#   C. folder / backlog-doc resolvers (skip ## Status: done; documented order).
#   D. resume reconcile: belief pending but gh says merged ⇒ merged; belief checked
#      but gh says open ⇒ awaiting_merge; gh unreadable ⇒ awaiting_merge (fail closed);
#      gh CLOSED-unmerged ⇒ gone.
#   E. auto-merge gate fail-CLOSED on EACH of the 5 conditions individually (incl.
#      both arms of cond. 2 base/SHA, both blocking reviewDecision arms CHANGES_REQUESTED
#      and REVIEW_REQUIRED of cond. 3, and both arms of cond. 5 checks/rubric), plus
#      malformed-ctx (ctx_unreadable) and a merge-command failure (merge_command_failed);
#      AND the all-pass MERGE case fires `gh pr merge --squash` exactly once.
#   F. learning-emit (engine-native ground-truth POSTMORTEM_RESULT line): happy path
#      (fix_cycles>0 → one drain_churn entry, review_rounds==fix_cycles), the zero-rule
#      (fix_cycles==0 non-escalated → categories:[] + review_rounds:0), zero-cycle
#      ESCALATED (→ review_rounds:1 + one drain_escalation entry), idempotency skip,
#      missing-field degrade, jq-absent no-write, fetch-fail integer-0 degrade,
#      injection-safe jq args, self_heal_misses derivation, read-postmortem visibility.

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
#   pr view <url> --json ...   -> cat $GH_STUB_DIR/pr-view.json (or exit 1 if marker)
#   pr merge --squash <url>    -> append a line to $GH_STUB_DIR/merge.log, exit per marker
set -u
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "view" ]; then
  if [ -f "$GH_STUB_DIR/pr-view-fail" ]; then exit 1; fi
  cat "$GH_STUB_DIR/pr-view.json"
  exit 0
fi
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "merge" ]; then
  echo "MERGE_CALLED $*" >> "$GH_STUB_DIR/merge.log"
  if [ -f "$GH_STUB_DIR/merge-fail" ]; then exit 1; fi
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
echo "== E. auto-merge gate: fail CLOSED on EACH blocker; all-pass MERGE fires once =="

WD="$(mktemp -d)"; BIN="$WD/bin"; make_stub_bin "$BIN"
export GH_STUB_DIR="$WD/ghstub"; mkdir -p "$GH_STUB_DIR"
printf '{"state":"OPEN"}\n' > "$GH_STUB_DIR/pr-view.json"   # not used by gate, but harmless

# A fully-passing context; each blocker test mutates ONE field to its failing value.
pass_ctx() {
  cat <<EOF
{
  "drain_result": "READY",
  "ready_sha": "abc123", "head_sha": "abc123", "base": "main",
  "review_decision": "APPROVED", "unresolved_human_thread": false,
  "protection_enforceable": true, "trust_unprotected": false,
  "checks_green": true, "rubric_satisfied": "na"
}
EOF
}

gate() {  # gate <ctx-json-string> -> sets RUN_OUT/RUN_RC, isolates a fresh merge.log
  rm -f "$GH_STUB_DIR/merge.log"
  printf '%s' "$1" > "$WD/ctx.json"
  RUN_OUT="$( env PATH="$BIN:$PATH" bash "$H" gate-eval "$PR" "$WD/ctx.json" 2>/dev/null )"; RUN_RC=$?
}
merges() { [ -f "$GH_STUB_DIR/merge.log" ] && grep -c MERGE_CALLED "$GH_STUB_DIR/merge.log" || echo 0; }

# Blocker 1 — unprotected/toothless branch w/o --trust-unprotected.
gate "$(pass_ctx | jq '.protection_enforceable=false')"
if [ "$RUN_OUT" = "PARK: unprotected_branch" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: unprotected branch ⇒ PARK, no merge"
else
  no "gate unprotected wrong (out='$RUN_OUT' merges=$(merges))"
fi
# ...but --trust-unprotected lets the SAME unprotected branch through (only that override).
gate "$(pass_ctx | jq '.protection_enforceable=false | .trust_unprotected=true')"
if [ "$RUN_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ]; then
  ok "gate: --trust-unprotected overrides only the protection condition (MERGE)"
else
  no "trust-unprotected override wrong (out='$RUN_OUT' merges=$(merges))"
fi

# Blocker 2 — moved head SHA.
gate "$(pass_ctx | jq '.head_sha="def456"')"
if [ "$RUN_OUT" = "PARK: head_sha_moved" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: moved head SHA ⇒ PARK, no merge"
else
  no "gate moved-sha wrong (out='$RUN_OUT' merges=$(merges))"
fi

# Blocker 2b — base != main (the other half of condition 2; SHA unchanged).
gate "$(pass_ctx | jq '.base="develop"')"
if [ "$RUN_OUT" = "PARK: base_not_main" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: base != main ⇒ PARK, no merge"
else
  no "gate base-not-main wrong (out='$RUN_OUT' merges=$(merges))"
fi

# Blocker 3a — CHANGES_REQUESTED.
gate "$(pass_ctx | jq '.review_decision="CHANGES_REQUESTED"')"
if [ "$RUN_OUT" = "PARK: review_decision_blocking" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: CHANGES_REQUESTED ⇒ PARK, no merge"
else
  no "gate changes-requested wrong (out='$RUN_OUT' merges=$(merges))"
fi

# Blocker 3a' — REVIEW_REQUIRED (distinct blocking arm from CHANGES_REQUESTED).
gate "$(pass_ctx | jq '.review_decision="REVIEW_REQUIRED"')"
if [ "$RUN_OUT" = "PARK: review_decision_blocking" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: REVIEW_REQUIRED ⇒ PARK, no merge"
else
  no "gate review-required wrong (out='$RUN_OUT' merges=$(merges))"
fi

# Blocker 3b — bare null reviewDecision ⇒ fail-CLOSED (treated as unknown; the loop
# must send the explicit "none"/"unreadable" strings, never bare null).
gate "$(pass_ctx | jq '.review_decision=null')"
if [ "$RUN_OUT" = "PARK: review_decision_unreadable" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: bare null reviewDecision ⇒ PARK (unreadable), no merge"
else
  no "gate null-decision wrong (out='$RUN_OUT' merges=$(merges))"
fi

# Blocker 3b' — explicit "unreadable" reviewDecision (the gh read failed) ⇒ fail-CLOSED.
gate "$(pass_ctx | jq '.review_decision="unreadable"')"
if [ "$RUN_OUT" = "PARK: review_decision_unreadable" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: unreadable reviewDecision ⇒ PARK, no merge"
else
  no "gate unreadable-decision wrong (out='$RUN_OUT' merges=$(merges))"
fi

# Reachability fix (regression guard for the round-6 MEDIUM) — a "none" reviewDecision
# (reviews-not-required: a successfully-read null) must DEFER to cond 4, NOT park at
# cond 3. These three were the dead paths before the fix.
# 3c — none + enforceable (checks-only) protection ⇒ MERGE.
gate "$(pass_ctx | jq '.review_decision="none"')"
if [ "$RUN_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ]; then
  ok "gate: none reviewDecision + enforceable (checks-only) protection ⇒ MERGE (cond 4 reachable)"
else
  no "gate none+protected wrong (out='$RUN_OUT' merges=$(merges))"
fi
# 3d — none + unprotected + --trust-unprotected ⇒ MERGE (the previously-DEAD flag path).
gate "$(pass_ctx | jq '.review_decision="none" | .protection_enforceable=false | .trust_unprotected=true')"
if [ "$RUN_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ]; then
  ok "gate: none reviewDecision + --trust-unprotected ⇒ MERGE (escape hatch now reachable)"
else
  no "gate none+trust wrong (out='$RUN_OUT' merges=$(merges))"
fi
# 3e — none + unprotected + NO trust ⇒ PARK: unprotected_branch (cond 4 still guards).
gate "$(pass_ctx | jq '.review_decision="none" | .protection_enforceable=false | .trust_unprotected=false')"
if [ "$RUN_OUT" = "PARK: unprotected_branch" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: none reviewDecision + unprotected + no trust ⇒ PARK"
else
  no "gate none+unprotected-no-trust wrong (out='$RUN_OUT' merges=$(merges))"
fi

# Blocker 3c — unresolved human-authored review thread.
gate "$(pass_ctx | jq '.unresolved_human_thread=true')"
if [ "$RUN_OUT" = "PARK: unresolved_human_thread" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: unresolved human thread ⇒ PARK, no merge"
else
  no "gate human-thread wrong (out='$RUN_OUT' merges=$(merges))"
fi
# Blocker 3c' — FAIL-OPEN regression guard: a MISSING/null unresolved_human_thread must
# fail CLOSED (PARK), NOT merge. (The field used `= "true"`, so a missing value merged.)
gate "$(pass_ctx | jq 'del(.unresolved_human_thread)')"
if [ "$RUN_OUT" = "PARK: unresolved_human_thread" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: MISSING unresolved_human_thread ⇒ PARK (no fail-open)"
else
  no "gate missing-human-thread FAILED OPEN (out='$RUN_OUT' merges=$(merges))"
fi
gate "$(pass_ctx | jq '.unresolved_human_thread=null')"
if [ "$RUN_OUT" = "PARK: unresolved_human_thread" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: null unresolved_human_thread ⇒ PARK (no fail-open)"
else
  no "gate null-human-thread FAILED OPEN (out='$RUN_OUT' merges=$(merges))"
fi

# Blocker bonus — drain not READY (ESCALATED).
gate "$(pass_ctx | jq '.drain_result="ESCALATED"')"
if [ "$RUN_OUT" = "PARK: drain_not_ready" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: drain ESCALATED ⇒ PARK, no merge"
else
  no "gate drain wrong (out='$RUN_OUT' merges=$(merges))"
fi

# Blocker 5 — required checks not green (the non-rubric half of condition 5).
gate "$(pass_ctx | jq '.checks_green=false')"
if [ "$RUN_OUT" = "PARK: checks_not_green" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: checks not green ⇒ PARK, no merge"
else
  no "gate checks-not-green wrong (out='$RUN_OUT' merges=$(merges))"
fi

# All-pass — MERGE fires `gh pr merge --squash` EXACTLY once.
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ] \
   && grep -q -- '--squash' "$GH_STUB_DIR/merge.log" \
   && grep -qF "$PR" "$GH_STUB_DIR/merge.log"; then
  ok "gate all-pass: MERGE fires 'gh pr merge --squash <url>' exactly once"
else
  no "gate all-pass wrong (out='$RUN_OUT' merges=$(merges) log='$(cat "$GH_STUB_DIR/merge.log" 2>/dev/null)')"
fi

# All-pass with a SATISFIED rubric (N==M, not 'na') also merges.
gate "$(pass_ctx | jq '.rubric_satisfied=true')"
if [ "$RUN_OUT" = "MERGE" ] && [ "$(merges)" -eq 1 ]; then
  ok "gate: rubric_satisfied=true (N==M) ⇒ MERGE"
else
  no "gate rubric-true wrong (out='$RUN_OUT' merges=$(merges))"
fi

# Unsatisfied rubric ⇒ PARK.
gate "$(pass_ctx | jq '.rubric_satisfied=false')"
if [ "$RUN_OUT" = "PARK: rubric_unsatisfied" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: rubric_satisfied=false ⇒ PARK, no merge"
else
  no "gate rubric-false wrong (out='$RUN_OUT' merges=$(merges))"
fi

# Null/absent rubric_satisfied ⇒ PARK (load-bearing fail-CLOSED: a JSON null/absent
# field coerces via `// "__MISSING__"` to a value that is neither "true" nor "na",
# so an absent rubric never silently merges). Explicit null AND field-omitted both park.
gate "$(pass_ctx | jq '.rubric_satisfied=null')"
if [ "$RUN_OUT" = "PARK: rubric_unsatisfied" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: rubric_satisfied=null ⇒ PARK, no merge"
else
  no "gate rubric-null wrong (out='$RUN_OUT' merges=$(merges))"
fi
gate "$(pass_ctx | jq 'del(.rubric_satisfied)')"
if [ "$RUN_OUT" = "PARK: rubric_unsatisfied" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: rubric_satisfied ABSENT ⇒ PARK, no merge"
else
  no "gate rubric-absent wrong (out='$RUN_OUT' merges=$(merges))"
fi

# Blocker — malformed (non-JSON) ctx.json ⇒ PARK: ctx_unreadable, no merge.
gate 'this is not json {'
if [ "$RUN_OUT" = "PARK: ctx_unreadable" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: malformed ctx.json ⇒ PARK: ctx_unreadable, no merge"
else
  no "gate ctx-unreadable wrong (out='$RUN_OUT' merges=$(merges))"
fi

# Blocker — all 5 pass but `gh pr merge` itself fails ⇒ PARK: merge_command_failed.
# The `merge-fail` stub marker makes the stubbed `gh pr merge` log the call THEN exit 1,
# so the gate sees the merge command fail and parks (no SUCCESSFUL merge).
touch "$GH_STUB_DIR/merge-fail"
gate "$(pass_ctx)"
if [ "$RUN_OUT" = "PARK: merge_command_failed" ]; then
  ok "gate fail-closed: gh pr merge fails ⇒ PARK: merge_command_failed (no successful merge)"
else
  no "gate merge-command-failed wrong (out='$RUN_OUT' merges=$(merges))"
fi
rm -f "$GH_STUB_DIR/merge-fail"

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

# F6. jq-absent → exit 0, NO write (point AI_AGENT_MANAGER_JQ_BIN at a nonexistent binary).
WD="$(mktemp -d)"; LED="$WD/results.jsonl"
run_h env AI_AGENT_MANAGER_JQ_BIN="$WD/no-such-jq-binary" bash "$H" learning-emit "$LED" \
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
#      read-postmortem.sh:124-126 keeps a corpus line iff (a) repo matches the reader's
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

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
