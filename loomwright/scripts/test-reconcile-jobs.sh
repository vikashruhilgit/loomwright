#!/usr/bin/env bash
# test-reconcile-jobs.sh — self-tests for reconcile-jobs.sh (the job-lifecycle
# reconciler) plus the two defects it ships alongside:
#
#   * automate-helpers.sh is_done() vs the format the completion tail STAMPS
#     (cases 11a-11e). Before this change the contract stamped `## Status` with
#     the value in a `- **Status:**` bullet while is_done() read only the
#     heading, so a successfully closed-out requirement stayed re-enqueueable
#     forever. It had never fired in anger (zero requirements carried the
#     sentinel), which is exactly why only an executed assertion catches it.
#   * session-resume.sh Section 1 asserting "Supervisor was mid-run" for a brief
#     whose work already shipped (cases 12-14).
#   * `--evidence <requirement_path>=<pr_url>` — engine-supplied merge evidence
#     (cases 15-25): match, SCOPED repair against a live stranded_closed decoy,
#     lexical validation with no fallback to the sweep, the no-evidence byte
#     baseline against origin/main, idempotency, ambiguity, the offline
#     invariant under a self-reporting gh stub, and two reconciler mutants.
#
# Runs everything inside ISOLATED temp dirs so the real .supervisor/ is never
# touched. Exit 0 = all pass, 1 = any failure (auto-registered by ci.yml's
# loomwright/scripts/test-*.sh glob).
#
# MUTATION CONTROLS are marked (control) — each exists so a case cannot be
# satisfied by a degenerate implementation. In particular 6 and 11e stop
# "repair everything" and "call everything done" from passing the suite.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECON="$SCRIPT_DIR/reconcile-jobs.sh"
HELPERS="$SCRIPT_DIR/automate-helpers.sh"
HOOK="$SCRIPT_DIR/session-resume.sh"

pass=0; fail=0
ok() { echo "ok   - $1"; pass=$((pass+1)); }
no() { echo "FAIL - $1"; fail=$((fail+1)); }

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT" 2>/dev/null' EXIT
mktmp() { mktemp -d "$ROOT/d.XXXXXX"; }

# A repo skeleton with one in-progress brief. $1=dir, $2=source-requirement line
# (empty ⇒ no pointer stamped at all).
new_repo() {
  local r; r="$(mktmp)"
  mkdir -p "$r/.supervisor/jobs/in-progress" "$r/.supervisor/jobs/done" \
           "$r/.supervisor/automate" "$r/.supervisor/requirements"
  {
    echo "# Supervisor Job: thing"
    echo
    echo "## Environment"
    [ -n "${1:-}" ] && echo "- **Source requirement:** $1"
  } > "$r/.supervisor/jobs/in-progress/brief.md"
  printf '%s' "$r"
}

# --- 1. stranded_merged: the real 2026-08-30 / PR #160 shape -----------------
r="$(new_repo ".supervisor/requirements/req.md")"
echo "# req" > "$r/.supervisor/requirements/req.md"
cat > "$r/.supervisor/automate/run.md" <<'EOF'
## Current
- item: .supervisor/requirements/req.md | status: merged | pr: https://github.com/o/r/pull/160 | branch: feature/x
EOF
out="$(cd "$r" && bash "$RECON" --porcelain 2>/dev/null)"
case "$out" in
  stranded_merged*) ok "1 merged run file ⇒ stranded_merged" ;;
  *) no "1 expected stranded_merged, got: $out" ;;
esac
case "$out" in
  *"pull/160"*) ok "1b evidence carries the PR URL" ;;
  *) no "1b evidence lost the PR URL: $out" ;;
esac

# --- 1c/1d. stranded_merged + an ESCALATED requirement stamp ----------------
# (PR #161 review round 2, finding 1: classify() checks the automate run file
# BEFORE is_done(), so this combination lands on stranded_merged — where the
# first escalation fix never looked, because it gated on `state`.)
r="$(new_repo ".supervisor/requirements/req.md")"
printf '# req\n\n## Status: done_with_escalation\n' > "$r/.supervisor/requirements/req.md"
cat > "$r/.supervisor/automate/run.md" <<'EOF'
## Current
- item: .supervisor/requirements/req.md | status: merged | pr: https://github.com/o/r/pull/7 | branch: b
EOF
out="$(cd "$r" && bash "$RECON" --porcelain 2>/dev/null)"
case "$out" in stranded_merged*) ok "1c merged run file still wins the classification" ;; *) no "1c expected stranded_merged, got: $out" ;; esac
(cd "$r" && bash "$RECON" --repair >/dev/null 2>&1)
b="$r/.supervisor/jobs/done/brief.md"
if grep -q '^- \*\*Status:\*\* completed_with_escalation$' "$b" 2>/dev/null; then
  ok "1c2 stranded_merged also honours an escalated requirement stamp"
else
  no "1c2 escalation dropped on the stranded_merged arm"
fi
grep -q 'heal-decision-agnostic' "$b" 2>/dev/null \
  && ok "1c3 note says the PR-merge evidence alone could not have told us" \
  || no "1c3 stranded_merged escalation note missing its distinct wording"

# (control) merged + a requirement with NO terminal stamp ⇒ plain completed.
r="$(new_repo ".supervisor/requirements/req.md")"
echo "# req" > "$r/.supervisor/requirements/req.md"
cat > "$r/.supervisor/automate/run.md" <<'EOF'
## Current
- item: .supervisor/requirements/req.md | status: merged | pr: https://github.com/o/r/pull/8 | branch: b
EOF
(cd "$r" && bash "$RECON" --repair >/dev/null 2>&1)
b="$r/.supervisor/jobs/done/brief.md"
if grep -q '^- \*\*Status:\*\* completed$' "$b" 2>/dev/null && ! grep -q 'Heal:' "$b" 2>/dev/null; then
  ok "1d (control) merged + unstamped requirement stays plain completed"
else
  no "1d merged + unstamped was wrongly escalated"
fi

# --- 2. an OPEN item must NOT be called stranded (control) -------------------
r="$(new_repo ".supervisor/requirements/req.md")"
echo "# req" > "$r/.supervisor/requirements/req.md"
cat > "$r/.supervisor/automate/run.md" <<'EOF'
## Current
- item: .supervisor/requirements/req.md | status: awaiting_merge | pr: https://github.com/o/r/pull/9 | branch: feature/x
EOF
out="$(cd "$r" && bash "$RECON" --porcelain 2>/dev/null)"
case "$out" in
  unknown*) ok "2 (control) awaiting_merge is NOT treated as stranded" ;;
  *) no "2 awaiting_merge misclassified: $out" ;;
esac

# --- 3. stranded_closed: requirement stamped, brief not moved ---------------
r="$(new_repo ".supervisor/requirements/req.md")"
printf '# req\n\n## Status: done\n' > "$r/.supervisor/requirements/req.md"
out="$(cd "$r" && bash "$RECON" --porcelain 2>/dev/null)"
case "$out" in
  stranded_closed*) ok "3 stamped requirement + unmoved brief ⇒ stranded_closed" ;;
  *) no "3 expected stranded_closed, got: $out" ;;
esac

# --- 3b/3c/3d. escalated close-out must NOT be flattened to a clean one -----
# (PR #161 review finding 1: repair() stamped `completed` for BOTH terminal
# values, discarding a nuance the file it had just read still carried.)
r="$(new_repo ".supervisor/requirements/req.md")"
printf '# req\n\n## Status: done_with_escalation\n' > "$r/.supervisor/requirements/req.md"
out="$(cd "$r" && bash "$RECON" --porcelain 2>/dev/null)"
case "$out" in
  *"is stamped done_with_escalation"*) ok "3b evidence names the escalated terminal value" ;;
  *) no "3b evidence lost the escalation value: $out" ;;
esac
(cd "$r" && bash "$RECON" --repair >/dev/null 2>&1)
b="$r/.supervisor/jobs/done/brief.md"
if grep -q '^- \*\*Status:\*\* completed_with_escalation$' "$b" 2>/dev/null; then
  ok "3c repair mirrors the contract's completed_with_escalation vocabulary"
else
  no "3c escalated close-out was flattened to a clean completed"
fi
grep -q '^- \*\*Heal:\*\* escalated' "$b" 2>/dev/null \
  && ok "3c2 escalation note states what is NOT recoverable" \
  || no "3c2 escalation note missing"

# (control) a PLAIN done must stay `completed` with no escalation note — stops
# 3c passing under an implementation that simply escalates everything.
r="$(new_repo ".supervisor/requirements/req.md")"
printf '# req\n\n## Status: done\n' > "$r/.supervisor/requirements/req.md"
(cd "$r" && bash "$RECON" --repair >/dev/null 2>&1)
b="$r/.supervisor/jobs/done/brief.md"
if grep -q '^- \*\*Status:\*\* completed$' "$b" 2>/dev/null && ! grep -q 'Heal:' "$b" 2>/dev/null; then
  ok "3d (control) a plain done stays completed, with no escalation note"
else
  no "3d plain done was wrongly escalated"
fi

# --- 4. no pointer ⇒ unknown ------------------------------------------------
r="$(new_repo "")"
out="$(cd "$r" && bash "$RECON" --porcelain 2>/dev/null)"
case "$out" in
  unknown*"no source requirement pointer"*) ok "4 no pointer ⇒ unknown" ;;
  *) no "4 expected unknown/no-pointer, got: $out" ;;
esac

# --- 5. traversal guard: pointer outside the requirements root ⇒ unknown ----
r="$(new_repo "../../../../etc/passwd")"
out="$(cd "$r" && bash "$RECON" --porcelain 2>/dev/null)"
case "$out" in
  unknown*"did not resolve"*) ok "5 traversal pointer refused ⇒ unknown" ;;
  *) no "5 traversal pointer not refused: $out" ;;
esac

# --- 6. (control) --repair NEVER touches an unknown brief -------------------
r="$(new_repo "")"
(cd "$r" && bash "$RECON" --repair >/dev/null 2>&1)
if [ -f "$r/.supervisor/jobs/in-progress/brief.md" ] && [ ! -e "$r/.supervisor/jobs/done/brief.md" ]; then
  ok "6 (control) --repair leaves an unknown brief where it is"
else
  no "6 --repair moved an unknown brief — repair is not evidence-gated"
fi

# --- 7. --repair moves a stranded_merged brief and writes ## Outcome --------
r="$(new_repo ".supervisor/requirements/req.md")"
echo "# req" > "$r/.supervisor/requirements/req.md"
cat > "$r/.supervisor/automate/run.md" <<'EOF'
## Current
- item: .supervisor/requirements/req.md | status: merged | pr: https://github.com/o/r/pull/160 | branch: feature/x
EOF
(cd "$r" && bash "$RECON" --repair >/dev/null 2>&1)
if [ -e "$r/.supervisor/jobs/done/brief.md" ] && [ ! -e "$r/.supervisor/jobs/in-progress/brief.md" ]; then
  ok "7 --repair completes the lifecycle move"
else
  no "7 --repair did not move the brief"
fi
if grep -q '^## Outcome$' "$r/.supervisor/jobs/done/brief.md" 2>/dev/null \
   && grep -q 'pull/160' "$r/.supervisor/jobs/done/brief.md" 2>/dev/null; then
  ok "7b moved brief carries an ## Outcome with the PR"
else
  no "7b ## Outcome missing or PR-less"
fi
if grep -q 'NOT recoverable after the fact' "$r/.supervisor/jobs/done/brief.md" 2>/dev/null; then
  ok "7c ## Outcome states which fields it could NOT recover"
else
  no "7c ## Outcome omits the honest-limits caveat"
fi

# --- 8. --repair refuses to clobber an existing destination -----------------
r="$(new_repo ".supervisor/requirements/req.md")"
echo "# req" > "$r/.supervisor/requirements/req.md"
printf '## Current\n- item: .supervisor/requirements/req.md | status: merged | pr: https://github.com/o/r/pull/1 | branch: b\n' \
  > "$r/.supervisor/automate/run.md"
echo "PRE-EXISTING" > "$r/.supervisor/jobs/done/brief.md"
(cd "$r" && bash "$RECON" --repair >/dev/null 2>&1)
if [ "$(cat "$r/.supervisor/jobs/done/brief.md")" = "PRE-EXISTING" ] \
   && [ -f "$r/.supervisor/jobs/in-progress/brief.md" ]; then
  ok "8 --repair refuses to clobber an existing done/ file"
else
  no "8 --repair clobbered the destination"
fi

# --- 8b. --repair refuses a brief that already carries an ## Outcome -------
# (PR #161 review round 2, finding 2.) The repair ORDER was also changed so this
# guard can no longer be tripped by our own half-finished write: the staged copy
# now lands in done/ before the original is removed, so a failed move can never
# leave a poisoned brief in in-progress/.
r="$(new_repo ".supervisor/requirements/req.md")"
echo "# req" > "$r/.supervisor/requirements/req.md"
printf '## Current\n- item: .supervisor/requirements/req.md | status: merged | pr: https://github.com/o/r/pull/2 | branch: b\n' \
  > "$r/.supervisor/automate/run.md"
printf '\n## Outcome\n- **Status:** completed\n' >> "$r/.supervisor/jobs/in-progress/brief.md"
(cd "$r" && bash "$RECON" --repair >/dev/null 2>&1)
if [ -f "$r/.supervisor/jobs/in-progress/brief.md" ] && [ ! -e "$r/.supervisor/jobs/done/brief.md" ]; then
  ok "8b --repair refuses a brief already carrying an ## Outcome"
else
  no "8b re-stamped or moved a brief that already had an ## Outcome"
fi

# --- 8c. a FAILED move must not poison the source brief --------------------
# The reordering in the round-2 fix is only observable when the move into done/
# fails, which the happy path cannot reach — without this case the change would
# be a claim no check backs. Force the failure by making done/ unwritable, then
# assert the brief is still repairable rather than wedged: the old order wrote
# the ## Outcome into the source FIRST, so a failure here left it carrying one,
# and the "already carries an ## Outcome" guard then refused it on every later
# run, forever.
r="$(new_repo ".supervisor/requirements/req.md")"
echo "# req" > "$r/.supervisor/requirements/req.md"
printf '## Current\n- item: .supervisor/requirements/req.md | status: merged | pr: https://github.com/o/r/pull/3 | branch: b\n' \
  > "$r/.supervisor/automate/run.md"
chmod 555 "$r/.supervisor/jobs/done"
(cd "$r" && bash "$RECON" --repair >/dev/null 2>&1)
poisoned=0
grep -qE '^## Outcome[[:space:]]*$' "$r/.supervisor/jobs/in-progress/brief.md" 2>/dev/null && poisoned=1
chmod 755 "$r/.supervisor/jobs/done"
if [ "$poisoned" -eq 0 ] && [ -f "$r/.supervisor/jobs/in-progress/brief.md" ]; then
  ok "8c a failed move leaves the source clean (still repairable, not wedged)"
else
  no "8c failed move poisoned the source brief with an ## Outcome"
fi
# ...and prove it is genuinely still repairable once the obstruction clears.
(cd "$r" && bash "$RECON" --repair >/dev/null 2>&1)
[ -e "$r/.supervisor/jobs/done/brief.md" ] \
  && ok "8c2 the same brief repairs cleanly on the next run" \
  || no "8c2 brief was left permanently unrepairable"

# --- 9. always exits 0, including on an unknown flag ------------------------
r="$(new_repo "")"
(cd "$r" && bash "$RECON" >/dev/null 2>&1); rc1=$?
(cd "$r" && bash "$RECON" --repair >/dev/null 2>&1); rc2=$?
(cd "$r" && bash "$RECON" --nonsense >/dev/null 2>&1); rc3=$?
rm -rf "$r/.supervisor"
(cd "$r" && bash "$RECON" >/dev/null 2>&1); rc4=$?
if [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ] && [ "$rc3" -eq 0 ] && [ "$rc4" -eq 0 ]; then
  ok "9 exits 0 on report / repair / bad flag / absent .supervisor"
else
  no "9 non-zero exit ($rc1/$rc2/$rc3/$rc4) — hook-unsafe"
fi

# --- 10. empty in-progress ⇒ no rows ---------------------------------------
r="$(new_repo "")"; rm -f "$r/.supervisor/jobs/in-progress/brief.md"
out="$(cd "$r" && bash "$RECON" --porcelain 2>/dev/null)"
[ -z "$out" ] && ok "10 empty in-progress ⇒ no porcelain rows" \
              || no "10 empty in-progress emitted rows: $out"

# --- 11. Defect C: is_done vs what the completion tail stamps ---------------
# The stamp fixtures are EXTRACTED FROM THE CONTRACT, never hand-typed. A
# hand-typed copy of the format is exactly the drift this pair exists to catch:
# it would keep passing after someone edited the skill back to a `- **Status:**`
# bullet, which is the shape that shipped broken. Editing the skill must break
# this test — that is the whole point.
SKILL="$SCRIPT_DIR/../skills/self-heal-advisory/SKILL.md"
d="$(mktmp)"
n_stamps=0
if [ -r "$SKILL" ]; then
  while IFS= read -r heading; do
    [ -n "$heading" ] || continue
    n_stamps=$((n_stamps+1))
    printf '# r\n\n<!-- loomwright:requirement-closeout -->\n%s\n- **Completed:** x\n' \
      "$heading" > "$d/a-contract-$n_stamps.md"
  done < <(grep -A1 -F '<!-- loomwright:requirement-closeout -->' "$SKILL" 2>/dev/null \
             | grep -E '^[[:space:]]*## Status' | sed 's/^[[:space:]]*//' | sort -u)
fi
printf '# r\n\n## Status: done\n' > "$d/c-handwritten.md"
printf '# r\n\n## Status: in-progress\n' > "$d/d-open.md"
printf '# r\n\n## Status: donezo\n' > "$d/e-lookalike.md"
# (control) `brief-shipped` is a DELIBERATE third value written by the sibling
# reconciler stamp-requirement-status.sh: a landed brief proves the work ran,
# NOT that every acceptance criterion was met, so promotion to `done` stays a
# human judgement. Widening is_done() must never swallow it.
printf '# r\n\n## Status: brief-shipped\n' > "$d/f-brief-shipped.md"
enq="$(bash "$HELPERS" resolve-folder "$d" 2>/dev/null | sed 's|.*/||' | tr '\n' ' ')"

# (control) the extractor itself must have found something. Without this a
# skill edit that removed the blocks entirely would leave 11a passing on zero
# fixtures — a gate satisfiable by finding nothing.
if [ "$n_stamps" -ge 2 ]; then
  ok "11a (control) extracted $n_stamps close-out stamps from the contract"
else
  no "11a extractor found $n_stamps stamps (expected >=2) — 11b would be vacuous"
fi
case "$enq" in *a-contract-*) no "11b a stamp the CONTRACT emits is still enqueueable" ;; *) ok "11b every stamp the contract emits is seen as done" ;; esac
case "$enq" in *c-handwritten*)   no "11c handwritten '## Status: done' regressed" ;; *) ok "11c handwritten '## Status: done' still seen as done" ;; esac
case "$enq" in *d-open*)          ok "11d (control) an open requirement stays enqueueable" ;; *) no "11d open requirement wrongly excluded" ;; esac
case "$enq" in *e-lookalike*)     ok "11e (control) 'donezo' is NOT matched as done" ;; *) no "11e matcher over-widened to 'donezo'" ;; esac
case "$enq" in *f-brief-shipped*) ok "11f (control) 'brief-shipped' stays enqueueable (human promotion pending)" ;; *) no "11f matcher swallowed the deliberate brief-shipped state" ;; esac

# --- 12-14. session-resume.sh Section 1 -------------------------------------
ctx() { echo '{"source":"resume"}' | (cd "$1" && bash "$HOOK" 2>/dev/null) \
        | python3 -c 'import sys,json;print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])' 2>/dev/null; }

# 12. a stranded brief must NOT be described as mid-run, and must not be
#     offered a resume.
r="$(new_repo ".supervisor/requirements/req.md")"
echo "# req" > "$r/.supervisor/requirements/req.md"
printf '## Current\n- item: .supervisor/requirements/req.md | status: merged | pr: https://github.com/o/r/pull/160 | branch: b\n' \
  > "$r/.supervisor/automate/run.md"
c="$(ctx "$r")"
case "$c" in *"Stranded briefs"*) ok "12 stranded brief reported under a Stranded heading" ;; *) no "12 no Stranded heading emitted" ;; esac
case "$c" in *"Supervisor was mid-run"*) no "12b (control) the old mid-run claim is still emitted" ;; *) ok "12b (control) the old mid-run claim is gone" ;; esac
case "$c" in *"--continue"*) no "12c a resume was offered for a stranded brief" ;; *) ok "12c no resume offered for a stranded brief" ;; esac
case "$c" in *"reconcile-jobs.sh --repair"*) ok "12d the repair command is surfaced" ;; *) no "12d no repair command surfaced" ;; esac

# 13. an unverifiable brief keeps a resume hint, but is labelled UNVERIFIED.
r="$(new_repo "")"
c="$(ctx "$r")"
case "$c" in *"UNVERIFIED"*) ok "13 unverifiable brief labelled UNVERIFIED" ;; *) no "13 UNVERIFIED label missing" ;; esac
case "$c" in *"--continue"*) ok "13b resume hint retained for an unverified brief" ;; *) no "13b resume hint wrongly suppressed" ;; esac

# 14. reconciler unavailable ⇒ neutral fallback, never the old claim.
#     The hook resolves its sibling by ABSOLUTE path, so PATH tricks cannot hide
#     it (an earlier draft of this case did exactly that and passed vacuously —
#     it was landing on the normal `unknown` arm). Copy the hook into a bin dir
#     that has no reconcile-jobs.sh beside it, which is the only way to make
#     `[ -r "$RECONCILER" ]` genuinely false.
bin="$(mktmp)"; cp "$HOOK" "$bin/session-resume.sh"
r="$(new_repo "")"
c="$(echo '{"source":"resume"}' | (cd "$r" && bash "$bin/session-resume.sh" 2>/dev/null) \
     | python3 -c 'import sys,json;print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])' 2>/dev/null)"
case "$c" in *"reconciler unavailable"*) ok "14 absent reconciler ⇒ neutral fallback heading" ;; *) no "14 fallback arm not reached (case would be vacuous)" ;; esac
case "$c" in *"Supervisor was mid-run"*) no "14b fallback regressed to the old claim" ;; *) ok "14b (control) fallback never asserts mid-run" ;; esac

# --- 15-25. --evidence: engine-supplied merge evidence (v15.65.0) -----------
# The `/automate` engine hands the reconciler the merge it witnessed as
# `--evidence <requirement_path>=<pr_url>`. These cases pin: the match (15), the
# SCOPING of --repair to the matched key with a live stranded_closed decoy that
# an unscoped --repair WOULD move (16, 17, 18), the ## Outcome fields (16c-16h),
# lexical validation + no-fallback-to-the-sweep (17), the no-evidence byte
# baseline against origin/main (18), no-match / idempotency / unknown-alongside
# / ambiguity (19-22), --help (23), the offline invariant with a gh stub that
# would prove itself called (24), and the two reconciler mutants (25).
U="https://github.com/o/r/pull/7"
K=".supervisor/requirements/r/03.md"
# ev_repo — the AC-3/AC-10 fixture: enq.md (pointer K, requirement ABSENT — the
# worktree shape) + other.md (pointer r/09.md, requirement stamped done ⇒
# stranded_closed, the DECOY an unscoped --repair would move).
ev_repo() {
  local r; r="$(new_repo "$K")"
  mv "$r/.supervisor/jobs/in-progress/brief.md" "$r/.supervisor/jobs/in-progress/enq.md"
  printf '# other\n\n- **Source requirement:** .supervisor/requirements/r/09.md\n' \
    > "$r/.supervisor/jobs/in-progress/other.md"
  mkdir -p "$r/.supervisor/requirements/r"
  printf '# r\n\n## Status: done\n' > "$r/.supervisor/requirements/r/09.md"
  printf '%s' "$r"
}

# 15. evidence match ⇒ stranded_merged carrying the engine wording and (url).
r="$(ev_repo)"
out="$(cd "$r" && bash "$RECON" --porcelain --evidence "$K=$U" 2>/dev/null | grep 'enq.md')"
case "$out" in stranded_merged*"automate engine supplied merge evidence for $K ($U)"*) ok "15 evidence match ⇒ stranded_merged with engine wording + (url)" ;; *) no "15 got: $out" ;; esac

# 16. AC-3 (reconciler level): --repair --evidence moves ONLY enq.md.
r="$(ev_repo)"
other_before="$(mktmp)/other.md"; cp "$r/.supervisor/jobs/in-progress/other.md" "$other_before"
out="$(cd "$r" && bash "$RECON" --repair --porcelain --evidence "$K=$U" 2>/dev/null)"
if [ -f "$r/.supervisor/jobs/done/enq.md" ] && [ ! -e "$r/.supervisor/jobs/in-progress/enq.md" ]; then ok "16 enqueued brief moved to done/"; else no "16 enqueued brief not moved: $out"; fi
if [ -f "$r/.supervisor/jobs/in-progress/other.md" ] && cmp -s "$other_before" "$r/.supervisor/jobs/in-progress/other.md"; then ok "16b decoy (stranded_closed) untouched under scoped --repair"; else no "16b decoy moved or changed"; fi
case "$out" in *"repaired	.supervisor/jobs/in-progress/enq.md	automate engine supplied"*) ok "16b2 porcelain reports the repaired row with the engine evidence" ;; *) no "16b2 no repaired row: $out" ;; esac
D="$r/.supervisor/jobs/done/enq.md"
grep -qF -- '- **Status:** completed' "$D" && ok "16c Outcome Status completed (requirement absent ⇒ fallback)" || no "16c Status line missing"
grep -qF -- "- **PR:** $U" "$D" && ok "16d Outcome PR line carries the url" || no "16d PR line wrong: $(grep -F 'PR:' "$D")"
grep -qF -- '- **Reconciled:** lifecycle move completed by reconcile-jobs.sh' "$D" && ok "16e Outcome Reconciled line present" || no "16e Reconciled line missing"
grep -qF -- "- **Evidence:** automate engine supplied merge evidence for $K ($U) — " "$D" && ok "16f Outcome Evidence line records the engine claim" || no "16f Evidence line wrong"
grep -qF -- '- **Caveat:**' "$D" && ok "16g Outcome Caveat line present" || no "16g Caveat line missing"
# 16h. completed_with_escalation when the requirement RESOLVES and is stamped so.
r="$(ev_repo)"
printf '# r\n\n## Status: done_with_escalation\n' > "$r/.supervisor/requirements/r/03.md"
(cd "$r" && bash "$RECON" --repair --porcelain --evidence "$K=$U" >/dev/null 2>&1)
grep -qF -- '- **Status:** completed_with_escalation' "$r/.supervisor/jobs/done/enq.md" 2>/dev/null \
  && ok "16h escalated requirement stamp ⇒ completed_with_escalation" || no "16h escalation not mirrored"

# 17. AC-10: every malformed value is IGNORED, and a rejected list never falls
#     back to the unscoped sweep (the decoy stays).
r0="$(ev_repo)"
base_row="$(cd "$r0" && bash "$RECON" --porcelain 2>/dev/null | grep 'enq.md')"
for v in "/abs/req.md=$U" ".supervisor/requirements/../x.md=$U" "docs/x.md=$U" \
         "$K=not-a-url" "$K=https://github.com/o/r/issues/7"; do
  r="$(ev_repo)"; ob="$(mktmp)/o.md"; cp "$r/.supervisor/jobs/in-progress/other.md" "$ob"
  err="$(mktmp)/err"
  out="$(cd "$r" && bash "$RECON" --repair --porcelain --evidence "$v" 2>"$err")"; rc=$?
  row="$(printf '%s\n' "$out" | grep 'enq.md')"
  if [ "$rc" -eq 0 ] && grep -q 'ignoring --evidence' "$err" && [ "$row" = "$base_row" ] \
     && [ -f "$r/.supervisor/jobs/in-progress/enq.md" ] \
     && [ -f "$r/.supervisor/jobs/in-progress/other.md" ] && cmp -s "$ob" "$r/.supervisor/jobs/in-progress/other.md"; then
    ok "17 rejected '$v': stderr ignore line, row unchanged, nothing moved (sweep did not fire)"
  else
    no "17 '$v' rc=$rc err='$(cat "$err")' row='$row' enq=$([ -f "$r/.supervisor/jobs/in-progress/enq.md" ] && echo in || echo gone) other=$([ -f "$r/.supervisor/jobs/in-progress/other.md" ] && echo in || echo gone)"
  fi
done
# 17f. (control) the decoy is LIVE: a bare --repair DOES move it.
r="$(ev_repo)"
(cd "$r" && bash "$RECON" --repair >/dev/null 2>&1)
if [ -f "$r/.supervisor/jobs/done/other.md" ]; then ok "17f (control) bare --repair moves the stranded_closed decoy"; else no "17f decoy is not live — 16b/17 would be vacuous"; fi
# 17g. an empty rejected list scopes too: --evidence with a bad value + --repair
#      leaves even a run-file stranded_merged brief in place.
r="$(new_repo ".supervisor/requirements/req.md")"
echo "# req" > "$r/.supervisor/requirements/req.md"
printf '## Current\n- item: .supervisor/requirements/req.md | status: merged | pr: https://github.com/o/r/pull/160 | branch: b\n' > "$r/.supervisor/automate/run.md"
(cd "$r" && bash "$RECON" --repair --evidence "docs/x.md=$U" >/dev/null 2>&1)
[ -f "$r/.supervisor/jobs/in-progress/brief.md" ] && ok "17g run-file stranded_merged brief NOT moved when evidence mode is on" || no "17g run-file brief moved under a rejected evidence list"

# 18. AC-4 baseline: no --evidence ⇒ porcelain byte-identical to origin/main's
#     reconciler on a 3-brief fixture (run-file merged / stamped / unknown).
r="$(new_repo ".supervisor/requirements/m.md")"
mv "$r/.supervisor/jobs/in-progress/brief.md" "$r/.supervisor/jobs/in-progress/a-merged.md"
echo "# m" > "$r/.supervisor/requirements/m.md"
printf '## Current\n- item: .supervisor/requirements/m.md | status: merged | pr: https://github.com/o/r/pull/1 | branch: b\n' > "$r/.supervisor/automate/run.md"
printf -- '- **Source requirement:** .supervisor/requirements/s.md\n' > "$r/.supervisor/jobs/in-progress/b-stamped.md"
printf '# s\n\n## Status: done\n' > "$r/.supervisor/requirements/s.md"
printf -- '- **Source requirement:** .supervisor/requirements/u.md\n' > "$r/.supervisor/jobs/in-progress/c-unknown.md"
bdir="$(mktmp)"; gerr="$(mktmp)/gerr"
# `now` is computed OUTSIDE the baseline arm: the 18b control below asserts on
# it, and on a fetch-depth-1 CI checkout the `git show origin/main:…` arm skips
# — computing `now` inside that arm made 18b red for the wrong reason (CI run
# 34591330419 on PR #210: "18b fixture rows missing" with an empty `$now`).
now="$(cd "$r" && bash "$RECON" --porcelain 2>/dev/null)"
if git -C "$SCRIPT_DIR/../.." show origin/main:loomwright/scripts/reconcile-jobs.sh > "$bdir/reconcile-jobs.sh" 2>"$gerr"; then
  cp "$SCRIPT_DIR/brief-pointer.sh" "$bdir/"
  then_="$(cd "$r" && bash "$bdir/reconcile-jobs.sh" --porcelain 2>/dev/null)"
  if [ -n "$now" ] && [ -n "$then_" ]; then
    if [ "$now" = "$then_" ]; then ok "18 no --evidence ⇒ porcelain byte-identical to origin/main (3-brief fixture)"; else no "18 baseline drift:\n$now\n--- vs ---\n$then_"; fi
  else
    no "18 an arm produced no rows (now=${#now} then=${#then_} bytes) — cmp would be vacuous"
  fi
else
  echo "skipped: origin/main unavailable ($(tr '\n' ' ' < "$gerr"))"
fi
case "$now" in *"a-merged.md"*"b-stamped.md"*"c-unknown.md"*) ok "18b (control) the 3 rows are present" ;; *) no "18b fixture rows missing: $now" ;; esac
# 18c. The CI-EFFECTIVE pin: the origin/main arm above is skipped on every
#      pull_request checkout (fetch-depth 1 has no origin/main) and compares the
#      file to itself on a push to main, so on its own it is a claim no CI check
#      backs. This frozen golden literal is what actually holds the no-`--evidence`
#      porcelain byte-for-byte, everywhere. Update it ONLY with a deliberate
#      porcelain change (and say so in the CHANGELOG).
golden="$(printf 'stranded_merged\t.supervisor/jobs/in-progress/a-merged.md\tautomate run file records .supervisor/requirements/m.md merged (https://github.com/o/r/pull/1)\nstranded_closed\t.supervisor/jobs/in-progress/b-stamped.md\tsource requirement .supervisor/requirements/s.md is stamped done\nunknown\t.supervisor/jobs/in-progress/c-unknown.md\tsource requirement pointer .supervisor/requirements/u.md did not resolve under .supervisor/requirements/')"
if [ "$now" = "$golden" ]; then ok "18c no --evidence ⇒ porcelain byte-identical to the frozen golden (runs in CI, unlike 18)"; else no "18c golden drift:\n$now\n--- vs golden ---\n$golden"; fi
# 18d. A repeated --evidence key is refused out loud (first wins), never silently
#      appended where evidence_index_for could not reach it.
r="$(ev_repo)"
err="$(mktmp)/err"
out="$(cd "$r" && bash "$RECON" --porcelain --evidence ".supervisor/requirements/r/03.md=$U" --evidence ".supervisor/requirements/r/03.md=https://github.com/o/r/pull/99" 2>"$err")"
case "$out" in *"($U)"*) k1=1 ;; *) k1=0 ;; esac
case "$out" in *"pull/99"*) k2=1 ;; *) k2=0 ;; esac
if [ "$k1" -eq 1 ] && [ "$k2" -eq 0 ] && grep -q "duplicate key" "$err"; then ok "18d duplicate --evidence key: first wins, second refused on stderr, never silently dropped"; else no "18d duplicate key handling wrong (k1=$k1 k2=$k2 err='$(cat "$err")')"; fi

# 19. evidence naming an item with NO matching brief ⇒ no move, exit 0.
r="$(ev_repo)"
out="$(cd "$r" && bash "$RECON" --repair --porcelain --evidence ".supervisor/requirements/r/99.md=$U" 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && [ -f "$r/.supervisor/jobs/in-progress/enq.md" ] && [ -f "$r/.supervisor/jobs/in-progress/other.md" ]; then ok "19 unmatched evidence ⇒ nothing moved, exit 0"; else no "19 rc=$rc out=$out"; fi

# 20. AC-8 idempotent: a second identical run ⇒ no second ## Outcome, dest unchanged.
r="$(ev_repo)"
(cd "$r" && bash "$RECON" --repair --porcelain --evidence "$K=$U" >/dev/null 2>&1)
snap="$(mktmp)/enq.md"; cp "$r/.supervisor/jobs/done/enq.md" "$snap"
(cd "$r" && bash "$RECON" --repair --porcelain --evidence "$K=$U" >/dev/null 2>&1); rc=$?
n_out="$(grep -c '^## Outcome' "$r/.supervisor/jobs/done/enq.md")"
if [ "$rc" -eq 0 ] && cmp -s "$snap" "$r/.supervisor/jobs/done/enq.md" && [ "$n_out" = "1" ] && [ ! -e "$r/.supervisor/jobs/in-progress/enq.md" ]; then ok "20 second identical run: dest cmp-identical, one ## Outcome, source absent, rc 0"; else no "20 idempotency broken (rc=$rc outcomes=$n_out)"; fi

# 21. AC-7: an unknown brief alongside stays unknown and unmoved.
r="$(ev_repo)"
printf -- '- **Source requirement:** .supervisor/requirements/r/05.md\n' > "$r/.supervisor/jobs/in-progress/u.md"
out="$(cd "$r" && bash "$RECON" --repair --porcelain --evidence "$K=$U" 2>/dev/null | grep 'u.md')"
case "$out" in unknown*) [ -f "$r/.supervisor/jobs/in-progress/u.md" ] && ok "21 unknown brief alongside: still unknown, still unmoved" || no "21 u.md moved" ;; *) no "21 u.md row not unknown: $out" ;; esac

# 22. AC-5(viii) twin: two briefs with the SAME key ⇒ both unknown/ambiguous, nothing moved.
r="$(ev_repo)"
printf -- '- **Source requirement:** %s\n' "$K" > "$r/.supervisor/jobs/in-progress/enq2.md"
out="$(cd "$r" && bash "$RECON" --repair --porcelain --evidence "$K=$U" 2>/dev/null)"
n_amb="$(printf '%s\n' "$out" | grep -c "^unknown	.*	ambiguous: 2 in-progress briefs point at $K")"
if [ "$n_amb" = "2" ] && [ -f "$r/.supervisor/jobs/in-progress/enq.md" ] && [ -f "$r/.supervisor/jobs/in-progress/enq2.md" ] && [ ! -e "$r/.supervisor/jobs/done/enq.md" ]; then ok "22 ambiguous key ⇒ two 'ambiguous: 2 …' unknown rows, nothing moved"; else no "22 ambiguity gate wrong (rows=$n_amb): $out"; fi

# 23. --help shows the whole header including the --evidence USAGE line.
h="$(bash "$RECON" --help 2>/dev/null)"
case "$h" in *"--evidence <requirement_path>=<pr_url>"*) ok "23 --help output contains the --evidence usage" ;; *) no "23 --help stops above USAGE" ;; esac

# 24. AC-4 offline invariant: a gh on PATH that would PROVE itself called.
r="$(ev_repo)"; gbin="$(mktmp)"
printf '#!/usr/bin/env bash\ntouch "%s/gh-called"\nexit 99\n' "$r" > "$gbin/gh"; chmod +x "$gbin/gh"
rows="$(cd "$r" && env -u LOOMWRIGHT_GH_BIN PATH="$gbin:$PATH" bash "$RECON" --porcelain 2>/dev/null)"
if [ ! -e "$r/gh-called" ] && [ -n "$rows" ]; then ok "24 reconcile-jobs.sh --porcelain never calls gh (rows non-empty: it ran)"; else no "24 gh-called=$([ -e "$r/gh-called" ] && echo yes || echo no) rows=${#rows}"; fi
for src in resume startup; do
  rm -f "$r/gh-called"
  hout="$(echo "{\"source\":\"$src\"}" | (cd "$r" && env -u LOOMWRIGHT_GH_BIN PATH="$gbin:$PATH" bash "$HOOK" 2>/dev/null))"
  if [ ! -e "$r/gh-called" ] && [ -n "$hout" ]; then ok "24b session-resume.sh source=$src never calls gh"; else no "24b source=$src gh-called=$([ -e "$r/gh-called" ] && echo yes || echo no)"; fi
done

# 25. AC-9(c)/(d) reconciler mutants. Post-PASS rule: each mutant sits beside an
#     UNMODIFIED real brief-pointer.sh (the reconciler sources it by dirname
#     "$0"; alone, every brief classifies unknown and the red is meaningless),
#     and an UNMUTATED copy in the same layout must FIRST keep AC-3 green.
mut_gate() {  # mut_gate <label> <original> <mutant>
  if [ -s "$3" ] && ! cmp -s "$2" "$3" && bash -n "$3" 2>/dev/null; then return 0; fi
  no "$1 mutant not gated (empty, identical, or bash -n failed)"; return 1
}
ac3_moves_enq() {  # ac3_moves_enq <reconciler> -> sets M_ENQ (1 moved) M_OTHER (1 untouched)
  local rr; rr="$(ev_repo)"; local ob; ob="$(mktmp)/o.md"; cp "$rr/.supervisor/jobs/in-progress/other.md" "$ob"
  (cd "$rr" && bash "$1" --repair --porcelain --evidence "$K=$U" >/dev/null 2>&1)
  M_ENQ=0; M_OTHER=0
  [ -f "$rr/.supervisor/jobs/done/enq.md" ] && [ ! -e "$rr/.supervisor/jobs/in-progress/enq.md" ] && M_ENQ=1
  [ -f "$rr/.supervisor/jobs/in-progress/other.md" ] && cmp -s "$ob" "$rr/.supervisor/jobs/in-progress/other.md" && M_OTHER=1
}
ac10_decoy_stays() {  # ac10_decoy_stays <reconciler> -> sets M_DECOY (1 untouched under an all-rejected list)
  local rr; rr="$(ev_repo)"
  (cd "$rr" && bash "$1" --repair --porcelain --evidence "docs/x.md=$U" >/dev/null 2>&1)
  M_DECOY=0; [ -f "$rr/.supervisor/jobs/in-progress/other.md" ] && M_DECOY=1
}
lay="$(mktmp)"; cp "$RECON" "$lay/reconcile-jobs.sh"; cp "$SCRIPT_DIR/brief-pointer.sh" "$lay/"
ac3_moves_enq "$lay/reconcile-jobs.sh"; ac10_decoy_stays "$lay/reconcile-jobs.sh"
if [ "$M_ENQ" = 1 ] && [ "$M_OTHER" = 1 ] && [ "$M_DECOY" = 1 ]; then
  ok "25 (positive gate) unmutated copy beside real brief-pointer.sh keeps AC-3 + AC-10 green"
  # (c) evidence-match arm in classify() removed.
  mc="$(mktmp)"; cp "$SCRIPT_DIR/brief-pointer.sh" "$mc/"
  awk '/^  if ei="\$\(evidence_index_for "\$raw_req"\)"; then$/{skip=1} skip && /^  fi$/{skip=0; next} !skip' "$RECON" > "$mc/reconcile-jobs.sh"
  if mut_gate "25c" "$RECON" "$mc/reconcile-jobs.sh"; then
    ac3_moves_enq "$mc/reconcile-jobs.sh"
    if [ "$M_ENQ" = 0 ] && [ "$M_OTHER" = 1 ]; then ok "25c (mutant) classify() arm removed ⇒ enq NOT moved (red), decoy still untouched (green)"; else no "25c mutant not discriminated (enq=$M_ENQ other=$M_OTHER)"; fi
  fi
  # (d) EVIDENCE_MODE=1 MOVED from the flag-parse arm into the accepted-value arm.
  md="$(mktmp)"; cp "$SCRIPT_DIR/brief-pointer.sh" "$md/"
  awk '$0=="      EVIDENCE_MODE=1"{next} index($0,"EV_KEYS[${#EV_KEYS[@]}]=\"$key\""){print "        EVIDENCE_MODE=1"} {print}' "$RECON" > "$md/reconcile-jobs.sh"
  if mut_gate "25d" "$RECON" "$md/reconcile-jobs.sh"; then
    ac3_moves_enq "$md/reconcile-jobs.sh"; ac10_decoy_stays "$md/reconcile-jobs.sh"
    if [ "$M_ENQ" = 1 ] && [ "$M_OTHER" = 1 ] && [ "$M_DECOY" = 0 ]; then ok "25d (mutant) scoping keyed on acceptance ⇒ decoy moves under a rejected list (red), AC-3 green"; else no "25d mutant not discriminated (enq=$M_ENQ other=$M_OTHER decoy=$M_DECOY)"; fi
  fi
else
  no "25 positive gate failed (enq=$M_ENQ other=$M_OTHER decoy=$M_DECOY) — mutants not run"
fi

echo "---------------------------------------------------------------------------"
echo "test-reconcile-jobs: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
