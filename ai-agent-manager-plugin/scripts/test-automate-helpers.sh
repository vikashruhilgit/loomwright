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
#      but gh says open ⇒ awaiting_merge.
#   E. auto-merge gate fail-CLOSED on EACH of the 5 blockers individually, AND the
#      single all-pass MERGE case fires `gh pr merge --squash` exactly once.

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

# B3. append-only Progress never loses prior lines.
bash "$H" progress-append "$RF" "t1 ran /autonomous"
bash "$H" progress-append "$RF" "t2 drain READY"
if grep -q '^- t0 picked a.md' "$RF" \
   && grep -q '^- t1 ran /autonomous' "$RF" \
   && grep -q '^- t2 drain READY' "$RF" \
   && [ "$(grep -c '^- t0 picked a.md' "$RF")" -eq 1 ]; then
  ok "append-only Progress: prior line intact, new lines appended in order"
else
  no "progress-append lost/duplicated lines:\n$(grep -n '^- t' "$RF")"
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
bash "$H" queue-checkoff "$RF" "b.md" "blocked upstream"
run_h bash "$H" remaining "$RF"
if grep -q '^- \[x\] b.md  # skipped: blocked upstream$' "$RF" && [ "$RUN_OUT" = "0" ]; then
  ok "skipped form: b.md checked off with reason, remaining now 0 (skipped excluded)"
else
  no "skipped-form wrong (remaining=$RUN_OUT, line=$(grep 'b.md' "$RF"))"
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
EOF
run_h bash "$H" resolve-backlog "$BL"
if [ "$RUN_OUT" = "reqs/01-one.md
reqs/03-three.md" ]; then
  ok "resolve-backlog: documented order, checked + ✅ excluded (01,03)"
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

# Blocker 3a — CHANGES_REQUESTED.
gate "$(pass_ctx | jq '.review_decision="CHANGES_REQUESTED"')"
if [ "$RUN_OUT" = "PARK: review_decision_blocking" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: CHANGES_REQUESTED ⇒ PARK, no merge"
else
  no "gate changes-requested wrong (out='$RUN_OUT' merges=$(merges))"
fi

# Blocker 3b — null/unreadable reviewDecision.
gate "$(pass_ctx | jq '.review_decision=null')"
if [ "$RUN_OUT" = "PARK: review_decision_null" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: null reviewDecision ⇒ PARK, no merge"
else
  no "gate null-decision wrong (out='$RUN_OUT' merges=$(merges))"
fi

# Blocker 3c — unresolved human-authored review thread.
gate "$(pass_ctx | jq '.unresolved_human_thread=true')"
if [ "$RUN_OUT" = "PARK: unresolved_human_thread" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: unresolved human thread ⇒ PARK, no merge"
else
  no "gate human-thread wrong (out='$RUN_OUT' merges=$(merges))"
fi

# Blocker bonus — drain not READY (ESCALATED).
gate "$(pass_ctx | jq '.drain_result="ESCALATED"')"
if [ "$RUN_OUT" = "PARK: drain_not_ready" ] && [ "$(merges)" -eq 0 ]; then
  ok "gate fail-closed: drain ESCALATED ⇒ PARK, no merge"
else
  no "gate drain wrong (out='$RUN_OUT' merges=$(merges))"
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

unset GH_STUB_DIR
rm -rf "$WD"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
