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

echo "---------------------------------------------------------------------------"
echo "test-reconcile-jobs: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
