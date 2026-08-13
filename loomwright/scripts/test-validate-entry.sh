#!/usr/bin/env bash
# test-validate-entry.sh — self-tests for the shared write-time validator.
#
# Runs entirely in temp dirs and against the repo's own read-only files. It NEVER writes to
# .supervisor/config.json, and section 12 asserts that by hashing the live config before and after
# the whole run — a fixture that moved the live allowlist would let `setup-memory.sh apply` judge
# foreign ledger records clean and publish another repo's churn analysis from this PUBLIC repo.
# Every fixture that needs a different allowlist supplies it through
# $LOOMWRIGHT_MEMORY_REPO_ALLOWLIST in the test's OWN environment, or a `--root` fixture repo.
#
# Covers:
#    1. contract + load guard — the sentinel is the LAST line, a truncated copy defines SOME
#       validators but NO sentinel, an unparseable copy returns non-zero without killing the
#       caller, and sourcing does not mutate the caller's shell options
#    2. duplicate
#    3. contradiction
#    4. provenance
#    5. dead-reference, including AC6's `jq has()` key-PRESENCE discipline (missing key != null)
#    6. cross-repo — AC3 (foreign short name REFUSED), AC4 (own repo PASSES) and the false-positive
#       guards that keep ordinary prose writable (`PR #146`, `and/or`, 3-segment paths)
#    7. cross-repo blind spot (AC4) — an unrecognised shape passes undetected, pinned by test, and
#       the refusal message says so rather than claiming complete coverage
#    8. AC4c — an allowlist that CANNOT be resolved is a refusal naming the unresolved allowlist,
#       neither a silent pass-everything nor a silent refuse-everything
#    9. delegation — the allowlist comes from `setup-memory.sh allowlist` and NOT from a second
#       parser of $LOOMWRIGHT_MEMORY_REPO_ALLOWLIST inside validate-entry.sh (proven behaviourally
#       with a stub resolver that disagrees with the env var, and statically)
#   10. one list, two consumers — moving the list once moves BOTH the resolver's output and the
#       cross-repo verdict (AC5's full form, incl. the ledger negative control, is subtask 3's)
#   11. MUTATION CONTROLS (AC4b, and R3 for every check) — each check is proven to be doing the
#       work its assertions credit it with. A guard this repo has not mutated is a guard it has
#       not tested; several shipped guards here were vacuous until someone mutated them.
#   12. no live state is touched
#   13. executable dispatch + verdict-code convention
#
# Exit 0 = all pass, 1 = any failure.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
VE="$HERE/validate-entry.sh"
PLUGIN_ROOT="$(cd "$HERE/.." && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
# Pin the plugin root for every invocation so the resolver lookup is deterministic and does not
# depend on the cwd the suite happens to run from. Section 1 separately covers the unset case.
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

# The allowlist every fixture pins, unless it is deliberately varying it. Declared in COMMITTED
# test source, never derived by calling the resolver: a gate that takes its expectation from the
# machine it runs on asserts a property of whoever runs it. `vikashruhilgit/loomwright` is the
# value that resolves on a fresh clone and in CI (the git-remote default), which is also why AC4's
# positive token is `loomwright` and never `ai-agent-manager`.
OURS="vikashruhilgit/loomwright"
# A deliberately FOREIGN slug, used only inside this suite's own environment. Never written to any
# config, never added to the live allowlist.
FOREIGN="otherco/othersvc"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

TMP="$(mktemp -d)"
trap 'chmod -R u+rwX "$TMP" 2>/dev/null; rm -rf "$TMP" 2>/dev/null' EXIT

# Snapshot the live config up front (section 12 re-checks it at the end).
LIVE_CFG="$REPO_ROOT/.supervisor/config.json"
if [ -f "$LIVE_CFG" ]; then LIVE_CFG_BEFORE="$(cksum < "$LIVE_CFG")"; else LIVE_CFG_BEFORE="ABSENT"; fi
# Same for the live curated stores, which section 11b READS. A validator suite that mutated the
# real memory it replays would be the "never write to live state" rule broken by the very test
# written to protect it.
LIVE_STORES_BEFORE="$(cksum < "$REPO_ROOT/.supervisor/memory/LESSONS.md" 2>/dev/null)|$(cksum < "$REPO_ROOT/.supervisor/memory/PROJECT_MEMORY.md" 2>/dev/null)"

# vrc <script> <check> <args...> -> prints nothing, sets VRC to the verdict code.
vrc() { local s="$1"; shift; bash "$s" "$@" >"$TMP/out.txt" 2>"$TMP/err.txt"; VRC=$?; return 0; }
# verdict <want> <desc> <script> <check> <args...>
verdict() {
  local want="$1" desc="$2"; shift 2
  vrc "$@"
  if [ "$VRC" -eq "$want" ]; then ok "$desc (rc=$VRC)"; else no "$desc — got rc=$VRC, wanted $want"; fi
}
# reason <token> <desc> — asserts the last run named <token> on stderr.
reason() {
  if grep -qF "$1" "$TMP/err.txt" 2>/dev/null; then ok "$2"; else no "$2 — '$1' not on stderr"; fi
}

# ---- the ADVISORY contract --------------------------------------------------
# dead-reference and cross-repo REPORT and never refuse (see validate-entry.sh's header for the six
# measured rounds of false refusals that bought this). That makes the exit status useless as a
# signal for those two — every run of theirs exits 0 — so this suite reads their EMISSION instead.
#
# BOTH HALVES ARE ASSERTED, ALWAYS, and that is the point rather than a nicety: a check whose body
# were deleted outright would also exit 0, so an assertion that only checks `rc == 0` stays green
# while the check it names no longer exists. That is the vacuous-guard class this branch has hit
# repeatedly; `advisory` below therefore fails when the finding is not PRINTED, and every mutation
# control in section 11 discriminates on ADV (did it report?) rather than on rc.
#
# ve_run <script> <args...> -> VRC = exit status, ADV = 1 when an `ADVISORY:` line was printed.
ve_run() {
  local s="$1"; shift
  bash "$s" "$@" >"$TMP/out.txt" 2>"$TMP/err.txt"
  VRC=$?
  if grep -qF 'ADVISORY:' "$TMP/err.txt" 2>/dev/null; then ADV=1; else ADV=0; fi
  return 0
}
# advisory <want-token> <desc> <script> <check> <args...> — exits 0 AND names <want-token> in an
# `ADVISORY:` line. Pass an empty token to assert only that something was advised.
advisory() {
  local tok="$1" desc="$2"; shift 2
  ve_run "$@"
  if [ "$VRC" -ne 0 ]; then
    no "$desc — got rc=$VRC, wanted 0: an ADVISORY check must never block a write"
  elif [ "$ADV" -ne 1 ]; then
    no "$desc — exited 0 but printed no 'ADVISORY:' line at all; a silent advisory is a deleted check"
  elif [ -n "$tok" ] && ! grep -qF "$tok" "$TMP/err.txt" 2>/dev/null; then
    no "$desc — advised, but did not name '$tok': $(tr '\n' ' ' < "$TMP/err.txt" | cut -c1-160)"
  else
    ok "$desc (rc=0 + ADVISORY $tok)"
  fi
}
# mut_run <script> <check> <args...> -> MADV = 1 when the run ADVISED, 0 when it was silent.
# The mutation controls in section 11 discriminate on THIS and not on the exit status. They have to:
# after the demotion every run of the two advisory checks exits 0, so an rc-based control would see
# "no change" for every mutant and report a row of green while testing nothing — the vacuous-control
# class this suite has already been bitten by twice. MADV maps onto the old rc exactly (a mutant
# that used to refuse now advises, 1 for 1; one that used to pass is silent, 0 for 0), so the
# expected values in those controls are unchanged and only the SOURCE of the signal moved.
mut_run() {
  local f="$1"; shift
  bash "$f" "$@" >/dev/null 2>"$TMP/err.txt"
  MRC=$?
  if grep -qF 'ADVISORY:' "$TMP/err.txt" 2>/dev/null; then MADV=1; else MADV=0; fi
  return 0
}
# quiet <desc> <script> <check> <args...> — exits 0 and advises NOTHING. The negative control that
# keeps `advisory` from passing for a check that warns about everything.
quiet() {
  local desc="$1"; shift
  ve_run "$@"
  if [ "$VRC" -ne 0 ]; then no "$desc — got rc=$VRC, wanted 0"
  elif [ "$ADV" -ne 0 ]; then no "$desc — a clean entry still produced an ADVISORY: $(tr '\n' ' ' < "$TMP/err.txt" | cut -c1-160)"
  else ok "$desc (rc=0, nothing advised)"; fi
}

echo "== 1. contract + load guard =="
verdict 0 "contract subcommand prints the sentinel value" "$VE" contract
grep -qx 'validate-entry/2' "$TMP/out.txt" && ok "contract value is validate-entry/2" \
  || no "contract value is not validate-entry/2"

# The sentinel MUST be the last line: that is the whole reason clause (iii) of the load guard can
# detect a truncated helper.
LAST="$(awk 'NF{l=$0} END{print l}' "$VE")"
[ "$LAST" = 'VALIDATE_ENTRY_CONTRACT="validate-entry/2"' ] \
  && ok "sentinel assignment is the last non-empty line of validate-entry.sh" \
  || no "sentinel is NOT the last line (found: $LAST) — a truncated helper could still match it"

# Sourcing a HEALTHY helper defines all five validators and the sentinel.
bash -c '
  set -uo pipefail
  before="$-"
  . "$1" || exit 9
  [ "${VALIDATE_ENTRY_CONTRACT:-}" = "validate-entry/2" ] || exit 10
  for f in $VALIDATE_ENTRY_FUNCTIONS; do command -v "$f" >/dev/null 2>&1 || exit 11; done
  [ "$before" = "$-" ] || exit 12
  exit 0
' _ "$VE"
case $? in
  0)  ok "sourcing defines all five validators + the sentinel and leaves shell options unchanged" ;;
  10) no "sourcing did not set VALIDATE_ENTRY_CONTRACT" ;;
  11) no "sourcing did not define all five validators" ;;
  12) no "sourcing MUTATED the caller's shell options" ;;
  *)  no "sourcing the healthy helper failed outright" ;;
esac

# TRUNCATED copy: the danger is real (some validators ARE defined) and the sentinel is absent.
# Truncating mid-function leaves an unterminated construct, so bash aborts the parse — exactly the
# state a `command -v <one function>` guard would misread as a healthy load.
TRUNC_AT="$(grep -nF 'validate_dead_reference() {' "$VE" | head -1 | cut -d: -f1)"
awk -v n="$((TRUNC_AT + 3))" 'NR <= n' "$VE" > "$TMP/truncated.sh"
bash -c '
  . "$1" 2>/dev/null
  src_rc=$?
  defined=0
  for f in validate_duplicate validate_contradiction validate_provenance; do
    command -v "$f" >/dev/null 2>&1 && defined=$((defined+1))
  done
  [ -n "${VALIDATE_ENTRY_CONTRACT:-}" ] && exit 20   # sentinel survived truncation — guard is useless
  [ "$defined" -gt 0 ] || exit 21                    # nothing partially defined — test proves nothing
  [ "$src_rc" -ne 0 ] || exit 22                     # source must report failure
  exit 0
' _ "$TMP/truncated.sh"
case $? in
  0)  ok "a truncated helper leaves SOME validators defined but NO sentinel, and source reports non-zero" ;;
  20) no "the sentinel survived truncation — clause (iii) of the load guard cannot detect it" ;;
  21) no "truncation defined nothing at all — this fixture proves nothing, move the cut point" ;;
  22) no "sourcing a truncated helper returned 0" ;;
  *)  no "the truncation fixture did not run" ;;
esac

# Sourcing an UNPARSEABLE copy must return non-zero WITHOUT killing the caller.
{ cat "$VE"; printf 'if [ then\n'; } > "$TMP/unparseable.sh"
bash -c '. "$1" 2>/dev/null; rc=$?; [ "$rc" -ne 0 ] && echo ALIVE' _ "$TMP/unparseable.sh" >"$TMP/o" 2>/dev/null
grep -qx ALIVE "$TMP/o" && ok "sourcing an unparseable helper returns non-zero and the caller survives" \
  || no "sourcing an unparseable helper killed the caller or returned 0"

# Resolver lookup falls back to a SIBLING setup-memory.sh when CLAUDE_PLUGIN_ROOT is unset.
mkdir -p "$TMP/sibling"
cp "$VE" "$TMP/sibling/validate-entry.sh"
cat > "$TMP/sibling/setup-memory.sh" <<'STUB'
#!/usr/bin/env bash
echo "siblingorg/siblingrepo"
exit 0
STUB
( unset CLAUDE_PLUGIN_ROOT VALIDATE_ENTRY_SETUP_MEMORY
  bash "$TMP/sibling/validate-entry.sh" cross-repo --entry "see siblingorg/siblingrepo" ) >/dev/null 2>&1
[ $? -eq 0 ] && ok "with CLAUDE_PLUGIN_ROOT unset the resolver falls back to a sibling setup-memory.sh" \
  || no "sibling-dir resolver fallback did not work"

echo "== 2. duplicate =="
STORE="$TMP/store.md"
printf '# Project Lessons\n\n## auth\n- [abcd1234] the token cache is refreshed on every request  <!-- last_verified=2026-01-01T00:00:00Z -->\n- [beef0001] workers run inside linked git worktrees\n' > "$STORE"
verdict 1 "AC1-class: a reworded near-identical entry is REFUSED" \
  "$VE" duplicate --entry "on every request the token cache is refreshed" --store "$STORE"
reason "REFUSE_DUPLICATE" "the duplicate refusal names its check"
verdict 0 "a genuinely new entry passes" \
  "$VE" duplicate --entry "the plan reviewer gates the brief save before it is written" --store "$STORE"
verdict 0 "an OPPOSITE-polarity entry is not reported as a duplicate (it is the contradiction check's)" \
  "$VE" duplicate --entry "the token cache is never refreshed on any request" --store "$STORE"
verdict 0 "an ABSENT store means no prior entries — a real clean verdict, not could-not-examine" \
  "$VE" duplicate --entry "some brand new fact about caching" --store "$TMP/no-such-store.md"
: > "$TMP/unreadable.md"; chmod 000 "$TMP/unreadable.md"
if [ -r "$TMP/unreadable.md" ]; then
  ok "SKIPPED unreadable-store case (running as a user that can read mode-000 files)"
else
  verdict 2 "a PRESENT but UNREADABLE store is could-not-examine (2), never clean" \
    "$VE" duplicate --entry "some brand new fact about caching" --store "$TMP/unreadable.md"
  reason "REFUSE_DUPLICATE_STORE_UNREADABLE" "the unreadable-store refusal names the reason"
fi
chmod 644 "$TMP/unreadable.md" 2>/dev/null
verdict 2 "a MISSING --store is could-not-examine (2), never clean" \
  "$VE" duplicate --entry "some brand new fact about caching"
reason "REFUSE_DUPLICATE_NO_STORE" "the missing-store refusal names the reason"

echo "== 3. contradiction =="
verdict 1 "an opposite-polarity entry about the same subject is REFUSED" \
  "$VE" contradiction --entry "the token cache is never refreshed on any request" --store "$STORE"
reason "REFUSE_CONTRADICTION" "the contradiction refusal names its check"
reason "supersede it explicitly" "the contradiction refusal proposes supersede rather than a silent append"
verdict 0 "an unrelated negative statement does not trip the contradiction check" \
  "$VE" contradiction --entry "the plan reviewer does not gate the release surface" --store "$STORE"
verdict 2 "contradiction with a MISSING --store is could-not-examine (2)" \
  "$VE" contradiction --entry "anything at all here"
# Flag, never delete: section 12 re-checks this against every refusal the suite has made.
STORE_CK="$(cksum < "$STORE")"

echo "== 3b. the INCOMMENSURABLE-SHAPE guard: a comparison that cannot discriminate is 2, never 0 =="
# THE DEFECT THIS SECTION EXISTS FOR. Both comparison checks score shared/max(|entry|,|line|), and
# shared can never exceed min(|entry|,|line|), so a pair's highest possible score is 100*min/max —
# fixed by the two SIZES before a word is read. Hand --store a document split into lines while
# --entry is that document and every ceiling sits far under 90/60: the loop cannot fire and returns
# "examined and clean" having been arithmetically unable to return anything else. Three writers had
# shipped exactly that. Measured on the live stores: an orientation memo scored 26% against ITSELF,
# a twin contract 17% against ITSELF.
#
# The fixture is built as a real document and its own fragments, not as hand-tuned token counts, so
# it cannot go green by drifting away from the shape it is supposed to represent.
DOCSTORE="$TMP/doc-store.md"
cat > "$DOCSTORE" <<'DOCEOF'
The write-time validator is loaded by every sole writer through a three-clause load guard.
Clause one requires the source itself to succeed, because a discarded status becomes a silent
unvalidated append. Clause two probes every validator function by name, since bash defines each
function above a syntax error before it aborts the parse. Clause three compares a sentinel that is
assigned on the last line of the helper, so truncation anywhere above it cannot forge a match.
A broken helper therefore degrades into a named refusal rather than into a crash.
DOCEOF
DOCENTRY="$(cat "$DOCSTORE")"

# WHAT THE GUARD MEANS, and why the two sharers DISAGREE on this very store. The guard does not ask
# "was the per-line comparison inert?" — it asks whether a REAL verdict would have existed under the
# correct shape and this shape is HIDING it. So every guard verdict below is asserted NEXT TO the
# correctly-shaped control that justifies it: feed the same content one-line-per-stored-entry and
# read what the check actually decides. A 2 is right only when that control is a refusal; when the
# control is a definite clean, nothing is hidden and the guard must stand down.
DOCCORPUS="$TMP/doc-corpus.md"
tr '\n' ' ' < "$DOCSTORE" > "$DOCCORPUS"; printf '\n' >> "$DOCCORPUS"

# --- DUPLICATE: the control REFUSES, so the fragment shape is hiding a verdict => 2 ---------------
verdict 1 "CONTROL [duplicate]: correctly shaped (one line per stored entry), the SAME document is a real REFUSAL (1)" \
  "$VE" duplicate --entry "$DOCENTRY" --store "$DOCCORPUS"
reason "REFUSE_DUPLICATE" "the corpus comparison refuses as a duplicate, i.e. it examined and decided"
verdict 2 "duplicate: a DOCUMENT compared against its own lines is could-not-examine (2), NOT clean" \
  "$VE" duplicate --entry "$DOCENTRY" --store "$DOCSTORE"
reason "REFUSE_DUPLICATE_UNCOMPARABLE_SHAPE" "the shape refusal names its own reason, not a generic 2"
reason "ONE LINE PER STORED ENTRY" "the shape refusal says how to fix the comparison"
reason "COULD NOT DECIDE" "the shape refusal says plainly that the verdict is unknown, not clean"
reason "it is the ENTRY that spans several of them" "the shape refusal also names the move for a store that ALREADY is one line per entry"

# --- CONTRADICTION on the SAME store: the control is CLEAN, so nothing is hidden => 0 -------------
# THIS ASSERTION WAS FLIPPED (it demanded 2, and that 2 was the guard's THIRD false refusal).
# It was rewritten rather than deleted, and the reason is recorded here so the change cannot be
# mistaken for an inconvenient assertion quietly dropped: the control on the line below returns a
# definite CLEAN(0). The store as a whole carries the SAME polarity as the entry, so the
# contradiction check would have SKIPPED it under ANY shape — no shape could produce a refusal here,
# the verdict is already determined, and "could not examine" was simply untrue. The catch that the
# old assertion was reaching for is real, but it belongs on an OPPOSITE-polarity store; it is
# asserted a few lines below on exactly that, where the control does refuse.
verdict 0 "CONTROL [contradiction]: correctly shaped, the same document is a definite CLEAN (0) — same polarity, never judged" \
  "$VE" contradiction --entry "$DOCENTRY" --store "$DOCCORPUS"
verdict 0 "contradiction: the same fragment store is CLEAN (0) — its control is clean, so the shape hides nothing" \
  "$VE" contradiction --entry "$DOCENTRY" --store "$DOCSTORE"

# --- CONTRADICTION's REAL intended catch: an OPPOSITE-polarity document split into lines ----------
# The store negates the entry point for point. Negation tokens are excluded from scoring, so the two
# sides still share nearly every significant token: correctly shaped this is a real REFUSAL, and
# split into fragments no single line can reach 60% — the fail-open the guard exists to close.
NEGENTRY="The write time validator is loaded by every sole writer through a three clause load guard.
Clause one requires the source itself to succeed, because a discarded status becomes a silent append.
Clause two probes every validator function by name, since bash defines each function above a syntax error."
NEGSTORE="$TMP/neg-store.md"
cat > "$NEGSTORE" <<'NEGEOF'
The write time validator is not loaded by any sole writer through a three clause load guard.
Clause one never requires the source itself to succeed, and a discarded status is not a silent append.
Clause two does not probe every validator function by name, and bash never defines each function above a syntax error.
NEGEOF
NEGCORPUS="$TMP/neg-corpus.md"
tr '\n' ' ' < "$NEGSTORE" > "$NEGCORPUS"; printf '\n' >> "$NEGCORPUS"
verdict 1 "CONTROL [contradiction]: correctly shaped, an opposite-polarity document is a real REFUSAL (1)" \
  "$VE" contradiction --entry "$NEGENTRY" --store "$NEGCORPUS"
verdict 2 "contradiction: that SAME opposite-polarity document split into lines is could-not-examine (2), NOT clean" \
  "$VE" contradiction --entry "$NEGENTRY" --store "$NEGSTORE"
reason "REFUSE_CONTRADICTION_UNCOMPARABLE_SHAPE" "the contradiction shape refusal names its own reason"
# ...and duplicate must stand DOWN on that same store, for the mirror reason: its control is clean.
verdict 0 "CONTROL [duplicate]: correctly shaped, an opposite-polarity document is a definite CLEAN (0)" \
  "$VE" duplicate --entry "$NEGENTRY" --store "$NEGCORPUS"
verdict 0 "duplicate: the same opposite-polarity fragment store is CLEAN (0) — its control is clean, so nothing is hidden" \
  "$VE" duplicate --entry "$NEGENTRY" --store "$NEGSTORE"

verdict 0 "duplicate: an unrelated document against the same corpus is CLEAN (0) — the corpus discriminates both ways" \
  "$VE" duplicate --entry "Deployment cadence is measured per regional cluster and the rollout window closes automatically.
Telemetry sampling stays at one in one hundred spans for every environment." --store "$DOCCORPUS"

# NO FALSE REFUSAL on the legitimate shapes — ASSERTED FOR EVERY CHECK THAT SHARES THE GUARD.
#
# THIS BATTERY USED TO CALL `duplicate` ONLY, and that is the root cause of the guard's second false
# refusal, not the arithmetic that produced it: `_ve_shape_incommensurable` is shared by two checks
# with DIFFERENT thresholds (90 and 60), so contradiction trips it roughly three times more easily,
# and it had no false-refusal assertion anywhere. Shared code with unshared tests. The list below is
# therefore the ONE place the sharers are named, every case runs against ALL of them, and the static
# assertion underneath fails the suite if validate-entry.sh grows a THIRD sharer that is not in it —
# a future check cannot inherit this guard without inheriting this battery.
SHAPE_SHARERS="duplicate contradiction"

# The shared property, and it is deliberately NOT "rc is 0": the two sharers legitimately reach
# DIFFERENT verdicts on the same input (one may refuse a real duplicate or contradiction where the
# other is clean). What every sharer must satisfy is that the SHAPE GUARD did not produce the
# verdict — 0 and 1 are both real answers, 2 or an *_UNCOMPARABLE_SHAPE reason is the false refusal.
# Pinning rc=0 for both would have to be relaxed the first time a case legitimately refuses, and a
# battery that gets relaxed per-case is how the coverage gap above reopens.
no_shape_refusal() {
  local desc="$1"; shift
  vrc "$VE" "$@"
  if [ "$VRC" -eq 2 ] || grep -qF "UNCOMPARABLE_SHAPE" "$TMP/err.txt" 2>/dev/null; then
    no "$desc — the shape guard FIRED (rc=$VRC), which is a false refusal on a legitimate shape"
  else
    ok "$desc (rc=$VRC — a real verdict, not a shape refusal)"
  fi
}

# The static half. Derived from the SOURCE, so it tracks the code rather than this file's memory of it.
SHARERS_FOUND="$(awk '
  /^validate_[a-z_]+\(\)[[:space:]]*\{/ { fn=$0; sub(/\(\).*/,"",fn); sub(/^validate_/,"",fn); gsub(/_/,"-",fn) }
  /^[[:space:]]*if _ve_shape_incommensurable/ && fn != "" { print fn }
' "$VE" | sort -u | tr '\n' ' ')"
SHARERS_WANT="$(printf '%s\n' $SHAPE_SHARERS | sort -u | tr '\n' ' ')"
if [ -z "$SHARERS_FOUND" ]; then
  no "no check in validate-entry.sh calls _ve_shape_incommensurable — this battery would run vacuously"
elif [ "$SHARERS_FOUND" = "$SHARERS_WANT" ]; then
  ok "SHAPE_SHARERS matches the checks that actually call the guard in source ($SHARERS_WANT) — no sharer is untested"
else
  no "the guard's sharers in source are [$SHARERS_FOUND] but this suite only covers [$SHARERS_WANT] — add the new sharer to SHAPE_SHARERS so the whole battery runs against it"
fi

# Each of these satisfies the guard's arithmetic conditions (every store line smaller than the entry,
# ceiling under the threshold) and must still pass, because a store of WHOLE entries that merely
# differ in length is a store where the check's verdict is correct and complete. These are the
# measured cases that forced condition (4) to be re-derived: an earlier shape-only version refused them.
LINESTORE="$TMP/line-store.md"
printf -- '- the token cache is refreshed on every request\n- workers run inside linked git worktrees\n- the plan reviewer gates the brief save\n' > "$LINESTORE"
for chk in $SHAPE_SHARERS; do
  no_shape_refusal "no false refusal [$chk]: a LONG single-line entry against a store of short whole entries" \
    "$chk" --entry "Deployment cadence is measured per regional cluster while the rollout window closes automatically and telemetry sampling stays at one in one hundred spans across every environment including the ephemeral preview stacks that the release pipeline creates on demand" \
    --store "$LINESTORE"
  no_shape_refusal "no false refusal [$chk]: a SHORT entry against a store of longer whole entries" \
    "$chk" --entry "sampling stays at one in one hundred spans" --store "$DOCCORPUS"
  no_shape_refusal "no false refusal [$chk]: a MULTI-LINE entry unrelated to a store of short whole entries" \
    "$chk" --entry "Deployment cadence is measured per regional cluster.
The rollout window closes automatically once telemetry sampling settles." --store "$LINESTORE"
done

# THE REPRODUCED FALSE REFUSAL, as its own case. A store whose every line carries the SAME polarity
# as the entry: contradiction's judging loop skips same-polarity lines, so it judged NOTHING and a
# contradiction was arithmetically impossible — yet the guard refused, because its condition (4)
# flattened EVERY line and scored it polarity-blind, i.e. it fired on evidence of DUPLICATION to
# refuse a comparison that could only ever have been clean. Both directions are pinned: contradiction
# must stand down, and duplicate must still fire on the very same store (its control refuses).
REPROSTORE="$TMP/repro-same-polarity.md"
cat > "$REPROSTORE" <<'REPROEOF'
The write time validator is loaded by every sole writer through a three clause load guard.
Clause one requires the source itself to succeed, because a discarded status becomes a silent append.
Clause two probes every validator function by name, since bash defines each function above a syntax error.
REPROEOF
REPROENTRY="$(cat "$REPROSTORE")"
REPROCORPUS="$TMP/repro-corpus.md"
tr '\n' ' ' < "$REPROSTORE" > "$REPROCORPUS"; printf '\n' >> "$REPROCORPUS"
verdict 0 "REPRO: contradiction against an all-same-polarity fragment store is CLEAN (0), not a false shape 2" \
  "$VE" contradiction --entry "$REPROENTRY" --store "$REPROSTORE"
verdict 0 "CONTROL [contradiction]: correctly shaped, that store is a definite CLEAN (0) — so the 0 above hides nothing" \
  "$VE" contradiction --entry "$REPROENTRY" --store "$REPROCORPUS"
verdict 1 "CONTROL [duplicate]: correctly shaped, that same store is a real REFUSAL (1)" \
  "$VE" duplicate --entry "$REPROENTRY" --store "$REPROCORPUS"
verdict 2 "REPRO, other direction: duplicate DOES still fire on that store (2) — the fix stood down one sharer, not the guard" \
  "$VE" duplicate --entry "$REPROENTRY" --store "$REPROSTORE"

# THE GUARD'S STATED GAP, pinned so it cannot rot into an unstated one. Condition (4) requires
# positive evidence — the entry must reach the threshold against the store taken as a whole — so a
# document-vs-fragments comparison whose entry is genuinely NEW is still reported clean. That is
# under-coverage by choice: inferring the shape from line lengths alone is what produced a false
# refusal against a real store. If this ever starts returning 2, the guard has been widened and the
# false-refusal risk needs re-measuring, not celebrating.
verdict 0 "STATED GAP: a document-vs-fragments comparison with a genuinely NEW entry is still reported clean (0)" \
  "$VE" duplicate --entry "Deployment cadence is measured per regional cluster.
The rollout window closes automatically once telemetry sampling settles." --store "$DOCSTORE"

# ENTRY/STORE SYMMETRY. _ve_store_lines skips whole-line HTML comments on the store side, so the
# entry side drops them too — otherwise a writer's own machine stamp (written_at / head_sha) counts
# as entry-only tokens and depresses every score. Measured on add-orientation.sh's composed memo:
# the header alone pulled a byte-identical repost from 100% down to 70%, i.e. under the threshold,
# which is a duplicate laundered by metadata. Both halves are asserted: the stamped entry is still
# refused, and an entry that is ONLY a comment does not become an unexaminable one.
SYMSTORE="$TMP/sym-corpus.md"
printf 'the retry helper backs off exponentially and gives up after five attempts\n' > "$SYMSTORE"
verdict 1 "symmetry: an entry carrying a written_at/head_sha header line is still refused as a duplicate" \
  "$VE" duplicate --entry "<!-- written_at: 2026-08-11T00:00:00Z | head_sha: abc1234 | areas: loomwright/scripts -->
the retry helper backs off exponentially and gives up after five attempts" --store "$SYMSTORE"
verdict 0 "symmetry: an entry that is ONLY an HTML comment falls back to the raw text, never a manufactured 2" \
  "$VE" duplicate --entry "<!-- just a comment about caching and nothing else -->" --store "$SYMSTORE"

echo "== 4. provenance =="
verdict 1 "an entry citing nothing that motivated it is REFUSED" \
  "$VE" provenance --entry "the cache is refreshed eagerly"
reason "REFUSE_PROVENANCE" "the provenance refusal names its check"
verdict 1 "a PLACEHOLDER --source (unknown) does not satisfy provenance" \
  "$VE" provenance --entry "the cache is refreshed eagerly" --source unknown
verdict 0 "a real --source satisfies provenance" \
  "$VE" provenance --entry "the cache is refreshed eagerly" --source "pr-138"
verdict 0 "a PR/issue number in the entry text satisfies provenance" \
  "$VE" provenance --entry "the cache is refreshed eagerly, see #138"
verdict 2 "provenance with no --entry at all is could-not-examine (2)" \
  "$VE" provenance --source "pr-138"

# AC17: strictness lives HERE, so all six writers inherit it. A source qualifies only when it
# carries a real reference; "any non-placeholder string" is the option decision (f) rejected.
verdict 1 "AC17: a bare command name (--source dreaming) does NOT satisfy provenance" \
  "$VE" provenance --entry "the cache is refreshed eagerly" --source "dreaming"
reason "REFUSE_PROVENANCE" "AC17: the bare-command-name refusal names the provenance check"
verdict 0 "AC17: --source 'dreaming:<session_id>' carries a real reference and PASSES" \
  "$VE" provenance --entry "the cache is refreshed eagerly" --source "dreaming:20260810T1200"
verdict 0 "AC17: a commit sha as --source PASSES" \
  "$VE" provenance --entry "the cache is refreshed eagerly" --source "c6bfda6"
verdict 0 "AC17: a bare command-name source still passes when the ENTRY itself cites the finding" \
  "$VE" provenance --entry "the cache is refreshed eagerly, see #138" --source "dreaming"

# ONE STANDARD ON BOTH HALVES. The text-scan fallback used to accept the bare WORDS `session`,
# `finding`, `postmortem`, `review` ... anywhere in the entry — a topic, not a citation — which made
# AC17's strict --source rule bypassable: `--source dreaming` was rejected and then fell through to a
# scan that passed on any entry containing "review". Both halves now require a real reference.
verdict 1 "the bare word 'review' is a topic, not a citation, and does NOT satisfy provenance" \
  "$VE" provenance --entry "the code reviewer is advisory and never blocks a merge"
verdict 1 "the bare word 'session' does NOT satisfy provenance either" \
  "$VE" provenance --entry "state is rebuilt at session start from the ledger"
verdict 1 "AC17 back door closed: --source dreaming + a bare keyword in the text is still REFUSED" \
  "$VE" provenance --entry "the code reviewer is advisory" --source "dreaming"
reason "REFUSE_PROVENANCE" "the bare-keyword refusal names the provenance check"
# ... and the tightening did not blind the check: a keyword WITH its id still passes, by the id.
verdict 0 "a keyword carrying its id still passes — 'session #42'" \
  "$VE" provenance --entry "reproduced in session #42 on the same branch"
verdict 0 "a commit sha in the entry text still passes" \
  "$VE" provenance --entry "the guard landed in c6bfda6 last week"
verdict 0 "a URL in the entry text still passes" \
  "$VE" provenance --entry "context in https://example.com/x/y"
# Static half: the pattern must not carry the bare-keyword alternation back. A behavioural assertion
# alone would go green again the moment someone re-added a keyword this suite does not happen to test.
if grep -nE '^_VE_PROVENANCE_RE=.*(\[Ss\]ession|\[Ff\]inding|\[Rr\]eview)' "$VE" >/dev/null 2>&1; then
  no "_VE_PROVENANCE_RE carries a bare-keyword alternation again — the text scan accepts a topic as a citation"
else
  ok "_VE_PROVENANCE_RE carries no bare-keyword alternation — it matches references only"
fi

echo "== 5. dead reference (ADVISORY — reports, never refuses) =="
quiet "an entry citing a path that still resolves passes and advises nothing" \
  "$VE" dead-reference --entry "the sole writer is loomwright/scripts/write-lessons.sh" --root "$REPO_ROOT"
# The `file:N` in the next fixture is FIXTURE INPUT, not a prose citation — it exists to prove
# that a real path carrying a line suffix still resolves. The citation-drift ratchet cannot tell
# the two apart, so it is pinned like any live citation. If the anchor moves, update the fixture
# rather than dropping the pin. NOTE: the pin must sit on the citation's own line (or the one
# after it) — a pin placed ABOVE is not seen, and a comment inside a `\`-continuation silently
# breaks the argument list, which is how this fixture was broken once already.
quiet "a bare CLAUDE.md and a :N line citation both resolve" \
  "$VE" dead-reference --entry "see CLAUDE.md and loomwright/scripts/setup-memory.sh:128" --root "$REPO_ROOT"  # [pins: `robust to header edits`]
advisory "ADVISORY_DEAD_REFERENCE" "an entry citing a path that no longer resolves is ADVISED, not refused" \
  "$VE" dead-reference --entry "the guard lives in loomwright/scripts/long-gone.sh" --root "$REPO_ROOT"
# The advisory must carry the SAME detail the refusal carried — the cited path — or "advisory" has
# quietly become "we noticed something".
reason "long-gone.sh" "the dead-reference advisory still names the path it could not resolve"
if grep -qF "REFUSE_DEAD_REFERENCE" "$TMP/err.txt" 2>/dev/null; then
  no "the dead-reference advisory still carries a REFUSE_ token — a warning and a refusal must not be greppable as the same thing"
else
  ok "the dead-reference advisory carries NO REFUSE_ token — the two shapes are distinguishable by grep"
fi
quiet "a URL is not treated as a repo path" \
  "$VE" dead-reference --entry "see https://example.com/nope/missing.md" --root "$REPO_ROOT"
quiet "backticks and trailing punctuation are stripped before resolution" \
  "$VE" dead-reference --entry "read \`loomwright/scripts/read-lessons.sh\`, then stop." --root "$REPO_ROOT"
# COULD-NOT-EXAMINE IS ALSO ADVISORY NOW, and this is the assertion that says so on purpose: an
# advisory check has nothing to fail closed FOR. Decision (b) still governs the three blocking
# checks — section 2's unreadable-store case still returns 2 — and section 14 pins that contrast.
advisory "ADVISORY_DEAD_REFERENCE_ROOT_MISSING" "an unusable --root is ADVISED (rc 0), not a refusal — an advisory check has no refusal to fall back to" \
  "$VE" dead-reference --entry "loomwright/scripts/write-lessons.sh" --root "$TMP/no-such-root"

echo "== 5a. AC16: resolve against the REPO, and SKIP what is unresolvable BY SHAPE =="
# A bare filename that lives in a subdirectory is a REAL file; resolving only against the repo root
# refused nine live curated entries for citing files that exist.
quiet "AC16: a bare filename that lives under loomwright/scripts/ resolves (not just repo-root)" \
  "$VE" dead-reference --entry "a green check-doc-currency.sh is necessary but not sufficient" --root "$REPO_ROOT"
quiet "AC16: two more real-but-not-at-root filenames resolve (send-webhook.sh, test-telemetry.sh)" \
  "$VE" dead-reference --entry "the send-webhook.sh emitter and test-telemetry.sh goldens" --root "$REPO_ROOT"
advisory "ADVISORY_DEAD_REFERENCE" "a bare filename that exists NOWHERE in the repo is still REPORTED — the suffix match did not blanket-pass" \
  "$VE" dead-reference --entry "the guard lives in long-gone-nowhere.sh" --root "$REPO_ROOT"
# SKIP vs REFUSE. These name no single file, so "does it still resolve" is not a question about
# them: not examined, not a verdict. This is NOT decision (b) relaxed — an unusable --root above
# still refuses with 2.
quiet "AC16: a GLOB ('test-*.sh') is unresolvable BY SHAPE and is SKIPPED, not refused" \
  "$VE" dead-reference --entry "eleven test-*.sh suites run in CI" --root "$REPO_ROOT"
quiet "AC16: a tilde path ('~/.claude/settings.json') is unresolvable BY SHAPE and is SKIPPED" \
  "$VE" dead-reference --entry "it is set =1 in this repo's ~/.claude/settings.json" --root "$REPO_ROOT"
quiet "AC16: a <placeholder> and a \$VAR-bearing path are SKIPPED for the same reason" \
  "$VE" dead-reference --entry "see <agent-name>.md and \$HOME/never-there.sh" --root "$REPO_ROOT"

echo "== 5b. AC6: nullable-but-required field asserts key PRESENCE via jq has() =="
if command -v jq >/dev/null 2>&1; then
  advisory "ADVISORY_DEAD_REFERENCE" "a present string field citing a dead path is ADVISED" \
    "$VE" dead-reference --json '{"path":"loomwright/scripts/long-gone.sh"}' --field path --root "$REPO_ROOT"
  quiet "a present string field citing a live path passes and advises nothing" \
    "$VE" dead-reference --json '{"path":"loomwright/scripts/write-lessons.sh"}' --field path --root "$REPO_ROOT"
  quiet "an EXPLICIT null is valid — the field is nullable, so nothing is cited" \
    "$VE" dead-reference --json '{"path":null}' --field path --root "$REPO_ROOT"
  # AC6's discipline SURVIVES the demotion, and this is the pair that proves it: a missing key and
  # an explicit null still reach DIFFERENT outcomes. What changed is the consequence (a warning, not
  # a refusal); what did not change is that a malformed record is never reported as clean.
  advisory "ADVISORY_DEAD_REFERENCE_FIELD_ABSENT" "a MISSING key still does NOT pass as clean — it is advised as could-not-examine, distinct from null" \
    "$VE" dead-reference --json '{"other":"x"}' --field path --root "$REPO_ROOT"
  advisory "ADVISORY_DEAD_REFERENCE_JSON_UNPARSEABLE" "unparseable JSON is advised as could-not-examine" \
    "$VE" dead-reference --json '{oops' --field path --root "$REPO_ROOT"
  advisory "ADVISORY_DEAD_REFERENCE_JSON_NOT_OBJECT" "a non-object JSON record is advised as could-not-examine" \
    "$VE" dead-reference --json '[1,2]' --field path --root "$REPO_ROOT"
  # jq ABSENT is could-not-examine, never clean (decision (b)).
  mkdir -p "$TMP/nojq"
  for b in bash awk sed grep tr cut git printf cksum; do
    p="$(command -v "$b" 2>/dev/null)"; [ -n "$p" ] && ln -sf "$p" "$TMP/nojq/$b" 2>/dev/null
  done
  ( PATH="$TMP/nojq" bash "$VE" dead-reference --json '{"path":null}' --field path --root "$REPO_ROOT" ) \
    >/dev/null 2>"$TMP/err.txt"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    no "an absent jq gave rc=$rc, wanted 0 — an advisory check must not block"
  elif grep -qF "ADVISORY_DEAD_REFERENCE_NO_JQ" "$TMP/err.txt" 2>/dev/null; then
    ok "an ABSENT jq is ADVISED by name, never silently reported clean (rc=$rc)"
  else
    no "an absent jq exited 0 and said nothing — the could-not-examine fact was lost, not demoted"
  fi
else
  ok "SKIPPED AC6 jq cases (jq not installed on this host)"
fi

echo "== 6. cross-repo (ADVISORY): AC3 reports foreign, AC4 stays silent on our own =="
export LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS"
advisory "ADVISORY_CROSS_REPO" "AC3: 'OTHERSVC #146' is REPORTED — a repo-shaped token NOT in the allowlist" \
  "$VE" cross-repo --entry "the same defect was fixed in OTHERSVC #146 last week"
reason "othersvc" "the cross-repo advisory still names the repository it found"
if grep -qF "REFUSE_CROSS_REPO" "$TMP/err.txt" 2>/dev/null; then
  no "the cross-repo advisory still carries a REFUSE_ token — a warning and a refusal must not be greppable as the same thing"
else
  ok "the cross-repo advisory carries NO REFUSE_ token — the two shapes are distinguishable by grep"
fi
advisory "ADVISORY_CROSS_REPO" "a foreign owner/repo slug is REPORTED" \
  "$VE" cross-repo --entry "context lives in $FOREIGN"
advisory "ADVISORY_CROSS_REPO" "a github.com URL naming a foreign repo is REPORTED" \
  "$VE" cross-repo --entry "context lives in https://github.com/$FOREIGN for now"
quiet "AC4: this repo's own slug PASSES SILENTLY — an entry may freely reference its own repo" \
  "$VE" cross-repo --entry "the guard landed in $OURS"
quiet "AC4: the short name 'LOOMWRIGHT #146' PASSES SILENTLY (whole word, case-insensitive)" \
  "$VE" cross-repo --entry "the guard landed in LOOMWRIGHT #146"
# False-positive guards. A wrong refusal blocks a legitimate write, which is worse than a miss.
quiet "'PR #146' is not read as a repository called pr" \
  "$VE" cross-repo --entry "fixed in PR #146"
quiet "'fixed in #146' is not read as a repository called in" \
  "$VE" cross-repo --entry "fixed in #146"
quiet "'and/or' is not read as an owner/repo slug" \
  "$VE" cross-repo --entry "the gate is advisory and/or read-only"
quiet "a three-segment path is not read as an owner/repo slug" \
  "$VE" cross-repo --entry "the guard is in loomwright/scripts/read-rules.sh"
quiet "a docs path with one slash is not read as an owner/repo slug" \
  "$VE" cross-repo --entry "recorded in docs/PITFALLS.md"

echo "== 6b. AC16: English prose pairs are not owner/repo slugs; a MARKED slug still is =="
# The exact six pairs that refused live curated entries. Asserted individually, not as one blob, so
# a regression names which pair came back.
for pair in "tests must parse YAML/JSON rather than hit live dependencies" \
            "the dev/CI shell may set it globally" \
            "the gate never scans budget/zone numbers" \
            "any user/PR-text -> JSON in a firing path must use jq --arg" \
            "the contrib image is distroless (no shell/wget)" \
            "fixtures are WORKER_RESULT/CODE_REVIEW_RESULT payloads only"; do
  quiet "AC16: prose pair passes — \"$pair\"" "$VE" cross-repo --entry "$pair"
done
# ... and the recogniser did NOT go blind: every MARKED form of a foreign slug still refuses.
# A bare `owner/repo` is THE canonical foreign-repo citation, so the four markers below are what
# stop the false-positive fix from opening a bigger hole than it closed. Each marker gets its own
# assertion AND its own mutation control in section 11.
advisory "ADVISORY_CROSS_REPO" "a foreign slug after a cue word ('landed in otherco/othersvc') is still REPORTED" \
  "$VE" cross-repo --entry "the same defect landed in $FOREIGN last week"
advisory "ADVISORY_CROSS_REPO" "marker (2), trailing: 'the otherco/othersvc repo' is REPORTED — the cue can follow the slug" \
  "$VE" cross-repo --entry "the $FOREIGN repo has the same bug"
advisory "ADVISORY_CROSS_REPO" "marker (3): a KNOWN owner is recognised — 'vikashruhilgit/othersvc' is not in the allowlist and is REPORTED" \
  "$VE" cross-repo --entry "vikashruhilgit/othersvc has the same bug"
# STATED LOST CATCH, narrowing (vi): a hyphenated owner is NO LONGER slug-only structure. Traded for
# the live entry `ground-truth/conformance`; see the COVERAGE BOUND note in validate-entry.sh. Pinned
# as an assertion so the loss is visible in the suite rather than inferred from an absent test.
quiet "narrowing (vi) LOST CATCH: a bare hyphenated owner is no longer recognised — 'acme-corp/widget-svc' PASSES" \
  "$VE" cross-repo --entry "acme-corp/widget-svc has the same bug"
advisory "ADVISORY_CROSS_REPO" "narrowing (vi) is BARE-ONLY: the same slug after a cue word is still REPORTED" \
  "$VE" cross-repo --entry "the same defect landed in acme-corp/widget-svc last week"
quiet "narrowing (v) LOST CATCH: a version-tagged repo half is no longer recognised — 'hashicorp/terraform-aws-v2' PASSES" \
  "$VE" cross-repo --entry "hashicorp/terraform-aws-v2 has the same bug"
quiet "narrowing (vii) LOST CATCH: a leading-only capital is no longer CamelCase — 'Microsoft/vscode' PASSES" \
  "$VE" cross-repo --entry "Microsoft/vscode has the same bug"
quiet "narrowing (v): the git branch name that motivated it PASSES — 'fix/v14.23.1-combined'" \
  "$VE" cross-repo --entry "RESOLVED in PR #51 (fix/v14.23.1-combined, June 2026)"
quiet "narrowing (vi): the prose pair that motivated it PASSES — 'ground-truth/conformance'" \
  "$VE" cross-repo --entry "Probe whether ground-truth/conformance actually ran before crediting a PASS"
quiet "narrowing (vii): the sentence-opening pair that motivated it PASSES — 'Count/version'" \
  "$VE" cross-repo --entry "Count/version drift is the top late-stage failure, see #146"
advisory "ADVISORY_CROSS_REPO" "marker (4): CamelCase is slug-only structure — 'octocat/Hello-World' is REPORTED" \
  "$VE" cross-repo --entry "octocat/Hello-World has the bug"
advisory "ADVISORY_CROSS_REPO" "marker (4): a digit is slug-only structure — 'octocat/repo2' is REPORTED" \
  "$VE" cross-repo --entry "octocat/repo2 has the bug"
advisory "ADVISORY_CROSS_REPO" "a foreign 'owner/repo#123' citation is still REPORTED (structural marker, no cue needed)" \
  "$VE" cross-repo --entry "fixed by $FOREIGN#12 yesterday"
advisory "ADVISORY_CROSS_REPO" "a foreign 'owner/repo.git' clone target is still REPORTED (structural marker)" \
  "$VE" cross-repo --entry "cloned $FOREIGN.git yesterday"
quiet "AC16: the OWNER half must be a legal GitHub login — an underscore owner is never a slug" \
  "$VE" cross-repo --entry "the payloads live in worker_result/code_review_result"

# --- marker (2): a SENTENCE-FINAL PERIOD is punctuation, not part of the cue word ---------------
# The neighbour words are normalized with `tr -cd 'a-z0-9._/-'`, which strips a comma but KEEPS a
# period, so `... the acme-corp/widget-svc repo.` produced the token `repo.` and matched nothing
# while the far rarer comma form matched. Both forms are pinned, in both directions, plus a control
# proving the fix did not simply blunt the token.
advisory "ADVISORY_CROSS_REPO" "marker (2): a trailing cue ending the SENTENCE ('... repo.') is REPORTED — a final period is punctuation, not part of the cue" \
  "$VE" cross-repo --entry "The same bug is open in the acme-corp/widget-svc repo."
advisory "ADVISORY_CROSS_REPO" "marker (2): the COMMA form ('... repo,') is REPORTED, as it always was" \
  "$VE" cross-repo --entry "The same bug is open in the acme-corp/widget-svc repo, filed last week"
advisory "ADVISORY_CROSS_REPO" "marker (2): the BARE form ('... repo has') is REPORTED — the unpunctuated control" \
  "$VE" cross-repo --entry "The acme-corp/widget-svc repo has the same bug"
advisory "ADVISORY_CROSS_REPO" "marker (2): repeated trailing punctuation ('... repo...') is REPORTED too" \
  "$VE" cross-repo --entry "The same bug is open in the acme-corp/widget-svc repo..."
# CONTROL — the stripping is trailing-dots ONLY and applies ONLY to the cue comparison. A neighbour
# whose dot is INTERNAL is untouched, so it still fails to be a cue word and the bare slug is still
# a deliberate miss; and a token that was never a cue does not become one.
quiet "marker (2) control: an INTERNAL dot is not stripped — 'acme-corp/widget-svc v1.2' is still a deliberate miss" \
  "$VE" cross-repo --entry "we pinned acme-corp/widget-svc v1.2 for the fixture"
quiet "marker (2) control: stripping a trailing dot does not turn a NON-cue word into a cue — '... widget-svc branch.' still passes" \
  "$VE" cross-repo --entry "The same bug is open on the acme-corp/widget-svc branch."

# --- the FILE-EXTENSION guard covers 1-5 letters, so a `.jsonl` citation is a path, not a slug ---
quiet "the extension guard reaches 5 letters: 'postmortem/results.jsonl' is a PATH, not an owner/repo slug" \
  "$VE" cross-repo --entry "the trend line is appended to postmortem/results.jsonl"
quiet "the extension guard reaches 5 letters even with a cue word beside it — '... in postmortem/results.jsonl'" \
  "$VE" cross-repo --entry "the ledger lives in postmortem/results.jsonl today"
quiet "the extension guard covers the NAME half of a 'NAME #123' citation too — 'results.jsonl #12'" \
  "$VE" cross-repo --entry "see results.jsonl #12 for the record"
# CONTROL — it was NOT widened so far that a legitimate repo name stops being recognised. A 6-letter
# suffix is past the bound, and a cued slug with no dot at all is unaffected either way.
advisory "ADVISORY_CROSS_REPO" "extension-guard control: a cued foreign slug with NO extension is still REPORTED" \
  "$VE" cross-repo --entry "the same defect landed in $FOREIGN last week"
advisory "ADVISORY_CROSS_REPO" "extension-guard control: the bound stops at 5 — a cued 'otherco/othersvc.github' is still REPORTED" \
  "$VE" cross-repo --entry "the same defect landed in otherco/othersvc.github last week"

echo "== 6c. IN-REPO DIRECTORY PATHS are not owner/repo slugs =="
# The second false-positive class, found by review after the marker fix shipped. An extensionless
# two-segment path is character-for-character a slug, and each of these six tripped a marker: a
# hyphen or digit in the owner half, a digit anywhere, CamelCase, or a neighbouring `in`/`from`.
# Asserted individually, never as one blob, so a regression names WHICH shape came back.
# --root is passed because the IN-REPO PATH VETO reads this repo's tree; the six sole writers all
# pass one (`--root "$GITROOT"`).
for shape in "the worktrees/subtask-1 checkout diverged from main" \
             "phase-2/plan was superseded by the new brief" \
             "the docs/Spikes folder holds frozen records" \
             "review-heal/SKILL is the authority here" \
             "the guard is in agents/code-reviewer today" \
             "copied from scripts/gates last week"; do
  quiet "in-repo path passes — \"$shape\"" "$VE" cross-repo --entry "$shape" --root "$REPO_ROOT"
done
# The two shapes that were ALREADY green. Pinned so a future narrowing cannot "fix" the six above by
# breaking what worked: a three-segment path, and a trailing-slash directory.
quiet "control: an extensioned three-segment path still passes" \
  "$VE" cross-repo --entry "see loomwright/agents/product-owner.md for it" --root "$REPO_ROOT"
quiet "control: a trailing-slash directory still passes" \
  "$VE" cross-repo --entry "the docs/ folder is frozen" --root "$REPO_ROOT"
# ... and the narrowings did NOT blind the recogniser: every foreign form still refuses WITH the same
# --root in hand, so the veto is not a blanket pass on any repo that happens to have directories.
advisory "ADVISORY_CROSS_REPO" "the in-repo veto did not blind the recogniser: a cued foreign slug still REPORTS with --root" \
  "$VE" cross-repo --entry "the same defect landed in $FOREIGN last week" --root "$REPO_ROOT"
advisory "ADVISORY_CROSS_REPO" "the in-repo veto did not blind the recogniser: a structured foreign slug still REPORTS with --root" \
  "$VE" cross-repo --entry "octocat/Hello-World has the bug" --root "$REPO_ROOT"
quiet "narrowing (iii): 'phase2/SKILL' passes — an ALL-CAPS repo half is a file stem even with a structured owner" \
  "$VE" cross-repo --entry "phase2/SKILL is the authority here" --root "$REPO_ROOT"
advisory "ADVISORY_CROSS_REPO" "narrowing (ii) is ORDINALS ONLY: 'octocat/repo2' (digits fused to letters) is still REPORTED" \
  "$VE" cross-repo --entry "octocat/repo2 has the bug" --root "$REPO_ROOT"
# The veto is DELIBERATELY not applied to the structural markers: an explicit repository citation
# outranks any local directory naming. `docs` IS a directory in this tree, so this is the real test.
advisory "ADVISORY_CROSS_REPO" "the veto does not suppress a STRUCTURAL marker — 'github.com/docs/spikes' is still REPORTED" \
  "$VE" cross-repo --entry "cloned from https://github.com/docs/spikes last week" --root "$REPO_ROOT"

# Narrowings (ii) and (iii) are index-INDEPENDENT and must hold with no repo to read; narrowing (i)
# is not, and the header says so. INDEX_LESS is a real directory holding one file and none of the
# directory names these tokens use, so the veto provably cannot fire inside it.
INDEX_LESS="$TMP/index-less"
mkdir -p "$INDEX_LESS/lib"; : > "$INDEX_LESS/lib/a.txt"
# The mirror-image root for the STATED BOUND below: identical except that it DOES hold the directory
# the probe token names, so the same token is vetoed here and refused there. Two roots, one token —
# which is the only way to show the veto reads the world rather than the shape.
mkdir -p "$TMP/phase2root/phase2"; : > "$TMP/phase2root/phase2/a.txt"
quiet "narrowing (ii) holds with NO in-repo index: 'worktrees/subtask-1' passes on an unrelated root" \
  "$VE" cross-repo --entry "the worktrees/subtask-1 checkout diverged" --root "$INDEX_LESS"
quiet "narrowing (iii) holds with NO in-repo index: 'review-heal/SKILL' passes on an unrelated root" \
  "$VE" cross-repo --entry "review-heal/SKILL is the authority here" --root "$INDEX_LESS"
# THE STATED BOUND, pinned rather than left to be rediscovered: narrowing (i) needs a usable tree, so
# on a root holding no matching directory an in-repo path whose structure SURVIVES the other
# narrowings is refused again. That is the documented residual of this fix, not an accident — the
# header's "WHAT THIS DOES NOT COVER" paragraph.
# The probe is `phase2/Notes`, NOT `docs/Spikes`: after narrowing (vii) a leading-only capital is no
# longer CamelCase, so `docs/Spikes` carries no marker at all and now passes on ANY root — it stopped
# being able to demonstrate this bound. A digit-bearing owner still does. Re-aimed rather than
# deleted, because the bound itself is unchanged; only the shape that exhibits it moved.
quiet "narrowing (vii) side-effect: 'docs/Spikes' now passes even with NO tree — it lost its last marker, so the veto is no longer what saves it" \
  "$VE" cross-repo --entry "the docs/Spikes folder holds frozen records" --root "$INDEX_LESS"
advisory "ADVISORY_CROSS_REPO" "STATED BOUND: 'phase2/Notes' IS reported on a root with no such directory — the veto reads the world, and there is none here" \
  "$VE" cross-repo --entry "the phase2/Notes folder holds frozen records" --root "$INDEX_LESS"
quiet "STATED BOUND, other side: the same 'phase2/Notes' still needs a real tree to be vetoed — it passes where one exists" \
  "$VE" cross-repo --entry "the phase2/Notes folder holds frozen records" --root "$TMP/phase2root"

echo "== 7. cross-repo blind spot (AC4) — stated, not hidden =="
quiet "prose naming a repo in an unrecognised shape passes UNDETECTED ('the othersvc repository')" \
  "$VE" cross-repo --entry "the othersvc repository has the same bug"
quiet "a plain lowercase 'othersvc #146' is also unrecognised (the deliberate under-recognition)" \
  "$VE" cross-repo --entry "landed in othersvc #146"
# THE RESIDUAL BOUND, pinned so it is a stated limitation rather than an unnoticed hole: an
# all-lowercase `word/word` with no cue beside it, no known owner and no slug structure cannot be
# told apart FROM THE TEXT ALONE from an English pair — `otherco/othersvc` and `budget/zone` are the same
# shape. Refusing that shape would refuse six live curated entries, so it is a deliberate miss.
quiet "RESIDUAL BOUND: a bare all-lowercase 'otherco/othersvc' with no marker passes undetected — the same shape as 'budget/zone'" \
  "$VE" cross-repo --entry "$FOREIGN has the same bug"
quiet "RESIDUAL BOUND control: the English pair it cannot be distinguished from passes for the SAME reason" \
  "$VE" cross-repo --entry "budget/zone has the same bug"
grep -qF "RESIDUAL BOUND" "$VE" && ok "validate-entry.sh states the residual bound in its header, not just in this test" \
  || no "validate-entry.sh header does not state the residual bound"
vrc "$VE" cross-repo --entry "the same defect was fixed in OTHERSVC #146"
if grep -qF "invisible to it" "$TMP/err.txt" && grep -qF "not proof" "$TMP/err.txt"; then
  ok "the refusal message states the coverage bound instead of claiming complete coverage"
else
  no "the refusal message does not state the coverage bound"
fi
grep -qF "COVERAGE BOUND" "$VE" && ok "validate-entry.sh documents the coverage bound in its header" \
  || no "validate-entry.sh header does not document the coverage bound"

echo "== 8. AC4c: an allowlist that cannot be resolved — now ADVISED, never silent =="
FIXTURE_ROOT="$TMP/fixture-repo"        # a bare dir: no config, no git remote => empty allowlist
mkdir -p "$FIXTURE_ROOT"
# AC4c's SUBSTANCE survives the demotion; only its CONSEQUENCE changes. "Membership could not be
# examined" is still neither a silent pass nor a claim of cleanliness — it is still named on stderr,
# and it is still distinguishable from a run that found nothing. What it no longer does is stop the
# write, because an advisory check has no refusal to fall back to. Each case below therefore asserts
# rc 0 AND the named token: rc alone would now pass even if the whole branch were deleted.
( unset LOOMWRIGHT_MEMORY_REPO_ALLOWLIST
  bash "$VE" cross-repo --entry "context lives in $FOREIGN" --root "$FIXTURE_ROOT" ) >/dev/null 2>"$TMP/err.txt"
rc=$?
if [ "$rc" -ne 0 ]; then
  no "an unresolvable allowlist gave rc=$rc, wanted 0 — an advisory check must not block a write"
elif grep -qF "ADVISORY_CROSS_REPO_ALLOWLIST_UNRESOLVED" "$TMP/err.txt" 2>/dev/null; then
  ok "an unresolvable allowlist is ADVISED BY NAME — not a silent pass, and not a refusal (rc=$rc)"
else
  no "an unresolvable allowlist exited 0 and named nothing — the could-not-examine fact was LOST, not demoted"
fi
( unset LOOMWRIGHT_MEMORY_REPO_ALLOWLIST
  bash "$VE" cross-repo --entry "no repository is named anywhere in this entry" --root "$FIXTURE_ROOT" ) >/dev/null 2>"$TMP/err.txt"
rc=$?
{ [ "$rc" -eq 0 ] && ! grep -qF 'ADVISORY:' "$TMP/err.txt" 2>/dev/null; } \
  && ok "an unresolvable allowlist says NOTHING about an entry citing no repo — it warns about repos, not about every write" \
  || no "an unresolvable allowlist warned on an entry with no repo reference at all (warn-everything is the advisory form of refuse-everything)"
( unset LOOMWRIGHT_MEMORY_REPO_ALLOWLIST
  VALIDATE_ENTRY_SETUP_MEMORY="$TMP/absent-resolver.sh" CLAUDE_PLUGIN_ROOT="$TMP" \
  bash "$VE" cross-repo --entry "context lives in $FOREIGN" ) >/dev/null 2>"$TMP/err.txt"
rc=$?
{ [ "$rc" -eq 0 ] && grep -qF "ADVISORY_CROSS_REPO_ALLOWLIST_UNRESOLVED" "$TMP/err.txt" 2>/dev/null; } \
  && ok "an ABSENT allowlist resolver is ADVISED by name (rc=0)" \
  || no "an absent allowlist resolver did not advise by name (rc=$rc)"

echo "== 9. delegation: one resolver, never a second parser =="
cat > "$TMP/stub-resolver.sh" <<'STUB'
#!/usr/bin/env bash
# Stub standing in for setup-memory.sh. Prints a list that DISAGREES with the env var, so a
# validate-entry.sh that parsed $LOOMWRIGHT_MEMORY_REPO_ALLOWLIST itself would reach a different
# verdict from one that delegates.
echo "stuborg/stubrepo"
echo "# source: stub" >&2
exit 0
STUB
LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$FOREIGN" VALIDATE_ENTRY_SETUP_MEMORY="$TMP/stub-resolver.sh" \
  mut_run "$VE" cross-repo --entry "context lives in $FOREIGN"
[ "$MADV" -eq 1 ] && ok "the stub resolver's list wins over the env var — the allowlist is DELEGATED, not re-parsed (the foreign slug IS advised)" \
  || no "the env var beat the resolver — validate-entry.sh is parsing the allowlist itself"
LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$FOREIGN" VALIDATE_ENTRY_SETUP_MEMORY="$TMP/stub-resolver.sh" \
  mut_run "$VE" cross-repo --entry "context lives in stuborg/stubrepo"
[ "$MADV" -eq 0 ] && ok "a slug in the resolver's list is NOT advised (the delegation is read, not merely invoked)" \
  || no "a slug in the resolver's list was advised as foreign"
# Static half: no code position in validate-entry.sh may EXPAND the env var. (It appears in prose
# and in a refusal message; those carry no `$`.)
if grep -nE '\$\{?LOOMWRIGHT_MEMORY_REPO_ALLOWLIST' "$VE" >/dev/null 2>&1; then
  no "validate-entry.sh expands \$LOOMWRIGHT_MEMORY_REPO_ALLOWLIST — that is a second parser"
else
  ok "validate-entry.sh never expands \$LOOMWRIGHT_MEMORY_REPO_ALLOWLIST"
fi
grep -qF 'allowlist' "$VE" && grep -qE 'bash "\$sm"' "$VE" \
  && ok "validate-entry.sh invokes the resolver as \`bash <setup-memory.sh> ... allowlist\`" \
  || no "validate-entry.sh does not invoke setup-memory.sh for the allowlist"

echo "== 10. one list, two consumers (AC5's shared-list half) =="
SM="$PLUGIN_ROOT/scripts/setup-memory.sh"
L1="$(LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" bash "$SM" allowlist 2>/dev/null)"
LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" mut_run "$VE" cross-repo --entry "context lives in $FOREIGN"
V1=$MADV
L2="$(LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS,$FOREIGN" bash "$SM" allowlist 2>/dev/null)"
LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS,$FOREIGN" mut_run "$VE" cross-repo --entry "context lives in $FOREIGN"
V2=$MADV
if [ "$L1" != "$L2" ] && [ "$V1" -eq 1 ] && [ "$V2" -eq 0 ]; then
  ok "moving the list ONCE moves both the resolver's output and the cross-repo finding (advised -> silent)"
else
  no "shared-list move did not move both consumers (L1='$L1' L2='$L2' V1=$V1 V2=$V2)"
fi

echo "== 11. MUTATION CONTROLS =="
# Every mutant is run through the SAME code path as the real check. A guard whose mutant stays
# green is a guard that was never doing the work its assertion credits it with.
# mutated_differs <file-in-TMP> <desc> — the gate every mutant passes before it is trusted.
# THREE conditions, and all three are load-bearing. This suite's first run produced an EMPTY mutant
# (a `sed` whose `|` delimiter collided with `||` in the pattern), and the assertion that followed
# went green anyway: an empty script "reports clean" for every input, so the control claimed to
# prove the guard was real while proving nothing at all. A mutant must therefore be non-empty,
# genuinely different from the original, AND still a parseable bash program.
mutated_differs() {
  local f="$TMP/$1" desc="$2"
  if [ ! -s "$f" ]; then no "$desc — the mutant is EMPTY (the mutation command failed; vacuous control)"; return 1; fi
  if cmp -s "$VE" "$f"; then no "$desc — the mutation changed NOTHING (vacuous control)"; return 1; fi
  if ! bash -n "$f" 2>/dev/null; then no "$desc — the mutant does not parse (vacuous control)"; return 1; fi
  return 0
}

# (i) AC4b: invert the membership test (`in` <-> `not in`) => AC4 must go RED.
IN_LINE="$(grep -cF '*" ${1:-} "*) return 0 ;;' "$VE")"
if [ "$IN_LINE" -ne 1 ]; then
  no "the membership test anchor is not unique ($IN_LINE hits) — the inversion mutant cannot be aimed"
else
  L="$(grep -nF '*" ${1:-} "*) return 0 ;;' "$VE" | cut -d: -f1)"
  awk -v a="$L" -v b="$((L+2))" 'NR==a{sub(/return 0/,"return 1")} NR==b{sub(/return 1/,"return 0")} {print}' \
    "$VE" > "$TMP/mut-membership.sh"
  if mutated_differs mut-membership.sh "membership inversion"; then
    LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" mut_run "$TMP/mut-membership.sh" cross-repo \
      --entry "the guard landed in $OURS"
    r1=$MADV
    LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" mut_run "$TMP/mut-membership.sh" cross-repo \
      --entry "the guard landed in LOOMWRIGHT #146"
    r2=$MADV
    LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" mut_run "$TMP/mut-membership.sh" cross-repo \
      --entry "the same defect was fixed in OTHERSVC #146"
    r3=$MADV
    [ "$r1" -eq 1 ] && [ "$r2" -eq 1 ] \
      && ok "AC4b(i): inverting the membership test turns AC4 RED (our OWN slug and short name are both advised as foreign)" \
      || no "AC4b(i): inverting membership left AC4 GREEN (slug advised=$r1, short advised=$r2) — AC4 is not discriminating"
    [ "$r3" -eq 0 ] && ok "AC4b(i): the same inversion also silences the FOREIGN token — the direction is what is tested" \
      || no "AC4b(i): the inverted build still advised on the foreign token (advised=$r3)"
  fi
fi

# (ii) AC4b: a FIXTURE allowlist that ADDS otherco/othersvc must make AC3's entry PASS — proving the
# check reads the list rather than pattern-matching a hardcoded token. Supplied via the env var in
# this test's own environment; the live config is never touched.
LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS,$FOREIGN" mut_run "$VE" cross-repo \
  --entry "the same defect was fixed in OTHERSVC #146"
[ "$MADV" -eq 0 ] && ok "AC4b(ii): adding otherco/othersvc to a FIXTURE allowlist silences 'OTHERSVC #146' — the check reads the list" \
  || no "AC4b(ii): 'OTHERSVC #146' was still advised even with otherco/othersvc allowlisted — the token is hardcoded"

# (iii) R3: delete the unresolvable-allowlist REPORT => the condition becomes a silent pass, which
# is the advisory form of the fail-open this control has always been aimed at. The mutation target
# moved with the design: it used to flip `return 2` to `return 0`, but that branch now returns 0 by
# construction, so a status-flipping mutant would change nothing and `mutated_differs` would (
# correctly) reject it as vacuous. What is still falsifiable — and what actually matters once a
# check cannot refuse — is whether the finding is EMITTED at all.
UL="$(grep -cF 'the allowlist resolved to nothing' "$VE" 2>/dev/null)"; [ -n "$UL" ] || UL=0
if [ "$UL" -ne 1 ]; then
  no "(iii) the unresolvable-allowlist report has $UL call site(s), expected exactly 1 — the mutant cannot be aimed"
else
awk '!/the allowlist resolved to nothing/' "$VE" > "$TMP/mut-unresolved.sh"
if mutated_differs mut-unresolved.sh "unresolvable-allowlist fail-open"; then
  ( unset LOOMWRIGHT_MEMORY_REPO_ALLOWLIST
    bash "$TMP/mut-unresolved.sh" cross-repo --entry "context lives in $FOREIGN" --root "$FIXTURE_ROOT" ) \
    >/dev/null 2>"$TMP/err.txt"
  if grep -qF 'ADVISORY:' "$TMP/err.txt" 2>/dev/null; then
    no "R3: the unresolved-allowlist mutant still reported — AC4c may be passing for another reason"
  else
    ok "R3: deleting the unresolved-allowlist report makes it a SILENT pass — AC4c's assertion is real"
  fi
fi
fi

# (iv) R3: conflate UNREADABLE with ABSENT in the store guard => could-not-examine becomes clean.
: > "$TMP/unreadable-2.md"; chmod 000 "$TMP/unreadable-2.md"
if [ -r "$TMP/unreadable-2.md" ]; then
  ok "SKIPPED store-guard mutant (running as a user that can read mode-000 files)"
else
  # awk + index(), not sed: the target line contains `||` and `[`, which collide with sed's
  # delimiter and BRE metacharacters. That collision is what produced the empty mutant above.
  awk '{ if (index($0, "[ -r \"$p\" ] || return 2")) sub(/return 2/, "return 1"); print }' \
    "$VE" > "$TMP/mut-store.sh"
  if mutated_differs mut-store.sh "store absent-vs-unreadable conflation"; then
    bash "$TMP/mut-store.sh" duplicate --entry "brand new fact" --store "$TMP/unreadable-2.md" >/dev/null 2>&1
    [ $? -eq 0 ] && ok "R3: conflating unreadable with absent makes the store guard report CLEAN — the guard is real" \
      || no "R3: the store-guard mutant did not change the verdict"
  fi
fi
chmod 644 "$TMP/unreadable-2.md" 2>/dev/null

# (v) R3: raise the duplicate threshold out of reach => the duplicate refusal disappears.
sed 's/^VALIDATE_ENTRY_DUPLICATE_THRESHOLD=90$/VALIDATE_ENTRY_DUPLICATE_THRESHOLD=999/' "$VE" > "$TMP/mut-dup.sh"
if mutated_differs mut-dup.sh "duplicate threshold"; then
  bash "$TMP/mut-dup.sh" duplicate --entry "on every request the token cache is refreshed" --store "$STORE" >/dev/null 2>&1
  [ $? -eq 0 ] && ok "R3: raising the duplicate threshold clears the refusal — the comparison is what refuses" \
    || no "R3: the duplicate mutant still refused — the refusal is not coming from the comparison"
fi

# (vi) R3: same for contradiction.
sed 's/^VALIDATE_ENTRY_CONTRADICTION_THRESHOLD=60$/VALIDATE_ENTRY_CONTRADICTION_THRESHOLD=999/' "$VE" > "$TMP/mut-con.sh"
if mutated_differs mut-con.sh "contradiction threshold"; then
  bash "$TMP/mut-con.sh" contradiction --entry "the token cache is never refreshed on any request" --store "$STORE" >/dev/null 2>&1
  [ $? -eq 0 ] && ok "R3: raising the contradiction threshold clears the refusal — the comparison is what refuses" \
    || no "R3: the contradiction mutant still refused"
fi

# (vii) R3: make the provenance pattern match anything => the provenance refusal disappears.
awk '/^_VE_PROVENANCE_RE=/{print "_VE_PROVENANCE_RE=\x27.\x27"; next} {print}' "$VE" > "$TMP/mut-prov.sh"
if mutated_differs mut-prov.sh "provenance pattern"; then
  bash "$TMP/mut-prov.sh" provenance --entry "the cache is refreshed eagerly" >/dev/null 2>&1
  [ $? -eq 0 ] && ok "R3: a match-anything provenance pattern clears the refusal — the pattern is what refuses" \
    || no "R3: the provenance mutant still refused"
fi

# (viii) R3: make every path resolve => the dead-reference refusal disappears.
awk '/^_ve_path_resolves\(\) \{$/{print; print "  return 0"; next} {print}' "$VE" > "$TMP/mut-dead.sh"
if mutated_differs mut-dead.sh "path resolution"; then
  mut_run "$TMP/mut-dead.sh" dead-reference --entry "the guard lives in loomwright/scripts/long-gone.sh" --root "$REPO_ROOT"
  [ "$MADV" -eq 0 ] && ok "R3: making every path resolve clears the report — resolution is what the check reports on" \
    || no "R3: the dead-reference mutant still reported a dead path"
fi

# (ix) AC6: drop the jq has() key-presence assertion => a MISSING key passes as valid.
if command -v jq >/dev/null 2>&1; then
  sed 's/(has(\$f) | tostring)/("true")/' "$VE" > "$TMP/mut-has.sh"
  if mutated_differs mut-has.sh "jq has() presence assertion"; then
    mut_run "$TMP/mut-has.sh" dead-reference --json '{"other":"x"}' --field path --root "$REPO_ROOT"
    [ "$MADV" -eq 0 ] && ok "AC6: dropping the has() presence assertion lets a MISSING key pass SILENTLY — the assertion is real" \
      || no "AC6: the has() mutant did not change the outcome"
  fi
fi

# (x) The aggregate must actually CALL each check: delete one call and the corresponding fixture
# must go green. Without this, `validate_entry_all` could source five checks and invoke four.
sed '/^  validate_cross_repo_reference "\$@";/d' "$VE" > "$TMP/mut-all.sh"
if mutated_differs mut-all.sh "aggregate call site"; then
  # The signal moved from the aggregate's EXIT STATUS to its OUTPUT, because an advisory check can
  # no longer change the former. What is still exactly as testable: whether the aggregate INVOKES
  # the check at all. A validate_entry_all that sourced five checks and ran four would now be
  # completely silent about it, which is a stronger reason to keep this control than before.
  LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" mut_run "$TMP/mut-all.sh" all \
    --entry "the same defect was fixed in OTHERSVC #146, source pr-138" --store "$STORE" --source "pr-138" --root "$REPO_ROOT"
  m=$MADV; mrc=$MRC
  LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" mut_run "$VE" all \
    --entry "the same defect was fixed in OTHERSVC #146, source pr-138" --store "$STORE" --source "pr-138" --root "$REPO_ROOT"
  b=$MADV
  { [ "$b" -eq 1 ] && [ "$m" -eq 0 ]; } \
    && ok "deleting the cross-repo call from validate_entry_all silences its advisory — the call site is tested, not just the source line" \
    || no "aggregate call-site mutant did not discriminate (baseline advised=$b, mutant advised=$m)"
  [ "$mrc" -eq 0 ] \
    && ok "...and the aggregate exits 0 either way — an advisory check's presence or absence never moves the exit status" \
    || no "the aggregate exit status moved with the advisory call site (mutant rc=$mrc)"
fi

# (xi) AC16: drop the MARKER requirement on `owner/repo` => ordinary prose pairs are refused again.
# This is the mutant that reproduces the 12-of-21 false-refusal defect on demand.
awk '{ if (index($0, "if [ \"$structural\" != \"1\" ]; then")) { print "  if false; then"; next } print }' \
  "$VE" > "$TMP/mut-cue.sh"
if mutated_differs mut-cue.sh "cross-repo marker requirement"; then
  LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" mut_run "$TMP/mut-cue.sh" cross-repo \
    --entry "tests must parse YAML/JSON rather than hit live dependencies"
  [ "$MADV" -eq 1 ] && ok "AC16: dropping the marker requirement refuses 'YAML/JSON' again — the marker is what keeps prose writable" \
    || no "AC16: the marker mutant still passed the prose pair — the pair is passing for some other reason"
  LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" mut_run "$TMP/mut-cue.sh" cross-repo \
    --entry "context lives in $FOREIGN"
  [ "$MADV" -eq 1 ] && ok "AC16: the same mutant still refuses a genuinely foreign slug — the mutation removed only the marker rule" \
    || no "AC16: the marker mutant stopped refusing foreign slugs — it changed more than the marker rule"
fi

# (xii) AC16: drop the unresolvable-BY-SHAPE skips => a glob and a tilde path are refused again.
awk '{ if (index($0, "resolves to no single file: SKIP") || index($0, "outside any repo root: SKIP")) next; print }' \
  "$VE" > "$TMP/mut-shape.sh"
if mutated_differs mut-shape.sh "unresolvable-by-shape skip"; then
  mut_run "$TMP/mut-shape.sh" dead-reference --entry "eleven test-*.sh suites run in CI" --root "$REPO_ROOT"
  r1=$MADV
  mut_run "$TMP/mut-shape.sh" dead-reference --entry "set =1 in ~/.claude/settings.json" --root "$REPO_ROOT"
  r2=$MADV
  { [ "$r1" -eq 1 ] && [ "$r2" -eq 1 ]; } \
    && ok "AC16: dropping the by-shape skips refuses the glob and the tilde path again — the skips are what pass them" \
    || no "AC16: the by-shape mutant did not discriminate (glob rc=$r1, tilde rc=$r2)"
fi

# (xiii) AC16: disable the repo-wide suffix resolution => a real file that is not at the repo root
# is refused again. This is the other half of the 12-of-21 defect.
awk '/^_ve_index_has\(\) \{$/{print; print "  return 1"; next} {print}' "$VE" > "$TMP/mut-index.sh"
if mutated_differs mut-index.sh "repo-wide path resolution"; then
  mut_run "$TMP/mut-index.sh" dead-reference --entry "a green check-doc-currency.sh is necessary" --root "$REPO_ROOT"
  [ "$MADV" -eq 1 ] && ok "AC16: disabling the repo-wide suffix match refuses 'check-doc-currency.sh' again — the match is what resolves it" \
    || no "AC16: the index mutant did not change the verdict — the bare filename resolves some other way"
  mut_run "$TMP/mut-index.sh" dead-reference --entry "the sole writer is loomwright/scripts/write-lessons.sh" --root "$REPO_ROOT"
  [ "$MADV" -eq 0 ] && ok "AC16: the same mutant still resolves a root-relative path — the mutation removed only the suffix match" \
    || no "AC16: the index mutant broke ordinary root-relative resolution — it changed more than the suffix match"
fi

# (xiv) AC17: drop the strict-source test => a bare command name satisfies provenance again, which
# is exactly the "any non-placeholder string" option decision (f) rejected.
awk '{ if (index($0, "*[0-9]*|*:*|*/*")) { print "          *) return 0 ;;"; next } print }' "$VE" > "$TMP/mut-strict.sh"
if mutated_differs mut-strict.sh "strict --source test"; then
  bash "$TMP/mut-strict.sh" provenance --entry "the cache is refreshed eagerly" --source "dreaming" >/dev/null 2>&1
  [ $? -eq 0 ] && ok "AC17: dropping the strict-source test lets a bare command name pass — the strictness is real" \
    || no "AC17: the strict-source mutant did not change the verdict"
fi

# (xv) Marker (3), KNOWN OWNER: disable the owner test => a foreign repo under a known owner stops
# being recognised. This is the marker that reads real data rather than shape.
awk '{ if (index($0, "a KNOWN repo owner")) { print "                *\") never-a-real-owner \"*) : ;;"; next } print }' \
  "$VE" > "$TMP/mut-owner.sh"
if mutated_differs mut-owner.sh "known-owner marker"; then
  LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" mut_run "$TMP/mut-owner.sh" cross-repo \
    --entry "vikashruhilgit/othersvc has the same bug"
  [ "$MADV" -eq 0 ] && ok "marker (3): disabling the known-owner test stops 'vikashruhilgit/othersvc' being recognised — the owner set is what marks it" \
    || no "marker (3): the known-owner mutant still refused — recognition is coming from somewhere else"
fi

# (xvi) Marker (4), SLUG-ONLY STRUCTURE: make it always fail => the hyphen/CamelCase forms stop
# being recognised, and the corpus prose pairs must STILL pass (the mutation removed only structure).
awk '/^_ve_slug_structured\(\) \{$/{print; print "  return 1"; next} {print}' "$VE" > "$TMP/mut-struct.sh"
if mutated_differs mut-struct.sh "slug-only structure marker"; then
  LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" mut_run "$TMP/mut-struct.sh" cross-repo \
    --entry "octocat/repo2 has the bug"
  r1=$MADV
  LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" mut_run "$TMP/mut-struct.sh" cross-repo \
    --entry "octocat/Hello-World has the bug"
  r2=$MADV
  { [ "$r1" -eq 0 ] && [ "$r2" -eq 0 ]; } \
    && ok "marker (4): disabling slug-only structure stops the digit and CamelCase forms being recognised — structure is what marks them" \
    || no "marker (4): the structure mutant did not discriminate (digit rc=$r1, CamelCase rc=$r2)"
fi

# (xvii) Marker (2), TRAILING CUE: remove it => 'the otherco/othersvc repo' stops being recognised.
awk '{ if (index($0, "_VE_SLUG_TRAILING_CUE_WORDS=")) { print "_VE_SLUG_TRAILING_CUE_WORDS=\" \""; next } print }' \
  "$VE" > "$TMP/mut-trail.sh"
if mutated_differs mut-trail.sh "trailing cue marker"; then
  LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" mut_run "$TMP/mut-trail.sh" cross-repo \
    --entry "the $FOREIGN repo has the same bug"
  [ "$MADV" -eq 0 ] && ok "marker (2): emptying the trailing cue list stops 'the otherco/othersvc repo' being recognised" \
    || no "marker (2): the trailing-cue mutant still refused"
  LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" mut_run "$TMP/mut-trail.sh" cross-repo \
    --entry "the same defect landed in $FOREIGN last week"
  [ "$MADV" -eq 1 ] && ok "marker (2): the same mutant still refuses the LEADING-cue form — the two cue lists are independent" \
    || no "marker (2): emptying the trailing list also broke the leading cue"
fi

# (xviii) IN-REPO PATH VETO, narrowing (i): make it never fire => the shapes that depend on reading
# the tree are refused again, and the foreign slugs must STILL refuse (the mutation removed only the
# veto). `review-heal/SKILL` is deliberately NOT asserted here: narrowing (iii) also covers it, so it
# would stay green and prove nothing about this mutant.
awk '/^_ve_owner_is_repo_dir\(\) \{$/{print; print "  return 1"; next} {print}' "$VE" > "$TMP/mut-veto.sh"
if mutated_differs mut-veto.sh "in-repo path veto"; then
  LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" mut_run "$TMP/mut-veto.sh" cross-repo \
    --entry "copied from scripts/gates last week" --root "$REPO_ROOT"
  r1=$MADV
  LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" mut_run "$TMP/mut-veto.sh" cross-repo \
    --entry "the guard is in agents/code-reviewer today" --root "$REPO_ROOT"
  r2=$MADV
  { [ "$r1" -eq 1 ] && [ "$r2" -eq 1 ]; } \
    && ok "narrowing (i): disabling the in-repo veto refuses 'scripts/gates' and 'agents/code-reviewer' again — the veto is what passes them" \
    || no "narrowing (i): the veto mutant did not discriminate (from-cue rc=$r1, in-cue rc=$r2)"
  LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" mut_run "$TMP/mut-veto.sh" cross-repo \
    --entry "the same defect landed in $FOREIGN last week" --root "$REPO_ROOT"
  [ "$MADV" -eq 1 ] && ok "narrowing (i): the same mutant still refuses a foreign slug — it removed only the veto" \
    || no "narrowing (i): the veto mutant stopped refusing foreign slugs — it changed more than the veto"
fi

# (xix) ORDINAL SUFFIX, narrowing (ii): make the strip a no-op => the `-<digits>` shapes read as
# "carries a digit" again, while `octocat/repo2` must keep refusing on the same digit rule. Run
# against INDEX_LESS so this control measures the strip and not the veto.
awk '/^_ve_strip_ordinal\(\) \{$/{print; print "  printf \x27%s\x27 \"${1:-}\"; return 0"; next} {print}' \
  "$VE" > "$TMP/mut-ordinal.sh"
if mutated_differs mut-ordinal.sh "ordinal suffix strip"; then
  LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" mut_run "$TMP/mut-ordinal.sh" cross-repo \
    --entry "the worktrees/subtask-1 checkout diverged" --root "$INDEX_LESS"
  r1=$MADV
  LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" mut_run "$TMP/mut-ordinal.sh" cross-repo \
    --entry "phase-2/plan was superseded by the new brief" --root "$INDEX_LESS"
  r2=$MADV
  { [ "$r1" -eq 1 ] && [ "$r2" -eq 1 ]; } \
    && ok "narrowing (ii): a no-op ordinal strip refuses 'worktrees/subtask-1' and 'phase-2/plan' again — the strip is what passes them" \
    || no "narrowing (ii): the ordinal mutant did not discriminate (subtask rc=$r1, phase rc=$r2)"
  LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" mut_run "$TMP/mut-ordinal.sh" cross-repo \
    --entry "octocat/repo2 has the bug" --root "$INDEX_LESS"
  [ "$MADV" -eq 1 ] && ok "narrowing (ii): the same mutant still refuses 'octocat/repo2' — fused digits were never an ordinal" \
    || no "narrowing (ii): the ordinal mutant changed the fused-digit verdict too"
fi

# (xx) ALL-CAPS REPO HALF, narrowing (iii): delete the suppressor => an all-caps repo half whose
# OWNER still carries structure is refused again, on a root where the veto cannot rescue it.
# The probe is `phase2/SKILL`, NOT `review-heal/SKILL`: narrowing (vi) retired the owner-half hyphen,
# so `review-heal` no longer supplies any structure for the suppressor to suppress and that probe
# went vacuous — it passed with the mutant AND without it. A digit-bearing owner still supplies some.
# This is the standing hazard with a suppressor control: it can only be proven by a case where the
# thing it suppresses would otherwise fire.
awk '{ if (index($0, "ALL-CAPS repo half: a file stem")) next; print }' "$VE" > "$TMP/mut-allcaps.sh"
if mutated_differs mut-allcaps.sh "all-caps repo half suppressor"; then
  LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" mut_run "$TMP/mut-allcaps.sh" cross-repo \
    --entry "phase2/SKILL is the authority here" --root "$INDEX_LESS"
  [ "$MADV" -eq 1 ] && ok "narrowing (iii): deleting the all-caps suppressor refuses 'phase2/SKILL' again — the suppressor is what passes it" \
    || no "narrowing (iii): the all-caps mutant did not change the verdict"
  LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" mut_run "$TMP/mut-allcaps.sh" cross-repo \
    --entry "octocat/Hello-World has the bug" --root "$INDEX_LESS"
  [ "$MADV" -eq 1 ] && ok "narrowing (iii): the same mutant still refuses 'octocat/Hello-World' — a lowercase-bearing half was never suppressed" \
    || no "narrowing (iii): the all-caps mutant changed the CamelCase verdict too"
fi

# (v) THE SHAPE GUARD: strip EVERY call site => section 3b's could-not-examine verdicts go back to
# reporting "examined and clean", which is the exact fail-open the guard was added to close.
#
# BOTH call sites are INDENTED, inside their functions. A mutation that only rewrote column-0
# occurrences would leave them untouched, the mutant would behave like the original, and this
# control would "prove" the guard is real while having changed nothing — that self-healing mutant
# has already happened on this branch, which is why the counts below are asserted rather than the
# sed being trusted.
#
# The expected count is DERIVED from SHAPE_SHARERS, not hardcoded: registering a new sharer there
# (which is what makes the whole no-false-refusal battery run against it) is then the single edit
# that keeps this control aimed too.
GUARD_SITES="$(grep -c 'if _ve_shape_incommensurable' "$VE" 2>/dev/null || true)"; [ -n "$GUARD_SITES" ] || GUARD_SITES=0
GUARD_WANT="$(printf '%s\n' $SHAPE_SHARERS | grep -c .)"
if [ "$GUARD_SITES" -ne "$GUARD_WANT" ]; then
  no "the shape guard has $GUARD_SITES call site(s) but SHAPE_SHARERS names $GUARD_WANT ($SHAPE_SHARERS) — the mutant below cannot be aimed at all of them"
else
  sed -e 's/if _ve_shape_incommensurable [^;]*;/if false;/' "$VE" > "$TMP/mut-shape.sh"
  GUARD_LEFT="$(grep -c 'if _ve_shape_incommensurable' "$TMP/mut-shape.sh" 2>/dev/null || true)"; [ -n "$GUARD_LEFT" ] || GUARD_LEFT=0
  if [ "$GUARD_LEFT" -ne 0 ]; then
    no "the shape mutant still has $GUARD_LEFT live call site(s) — a partially-stripped mutant proves nothing (this is the column-0 trap)"
  elif mutated_differs mut-shape.sh "shape-guard strip"; then
    ok "(v) the mutation is NON-VACUOUS: 2 call sites in the real validator, 0 in the mutant"
    # EACH SHARER IS AIMED AT THE STORE WHERE ITS OWN GUARD FIRES. Both used to be aimed at DOCSTORE,
    # which is now the store where CONTRADICTION correctly stands down — a mutant that strips the
    # guard cannot change a verdict the guard never produced, so that half would have gone green
    # while proving nothing about the contradiction call site.
    bash "$TMP/mut-shape.sh" duplicate --entry "$DOCENTRY" --store "$DOCSTORE" >/dev/null 2>&1; g1=$?
    bash "$TMP/mut-shape.sh" contradiction --entry "$NEGENTRY" --store "$NEGSTORE" >/dev/null 2>&1; g2=$?
    if [ "$g1" -eq 0 ] && [ "$g2" -eq 0 ]; then
      ok "(v) CONFIRMED: without the guard, both sharers report a document-vs-its-own-fragments comparison CLEAN (0) — section 3b's 2s are the guard's doing, not a threshold accident"
    else
      no "(v) the guard-less mutant still refused the inert shape (duplicate rc=$g1, contradiction rc=$g2) — section 3b may be passing for some other reason"
    fi
    # The same mutant must leave every LEGITIMATE verdict alone: if stripping the guard also changed
    # those, the control would be measuring the guard's blast radius rather than the guard.
    bash "$TMP/mut-shape.sh" duplicate --entry "$DOCENTRY" --store "$DOCCORPUS" >/dev/null 2>&1; g3=$?
    bash "$TMP/mut-shape.sh" duplicate --entry "sampling stays at one in one hundred spans" --store "$DOCCORPUS" >/dev/null 2>&1; g4=$?
    if [ "$g3" -eq 1 ] && [ "$g4" -eq 0 ]; then
      ok "(v) the same mutant leaves the corpus verdicts UNCHANGED (duplicate still 1, clean still 0) — the guard only ever converts a would-be 0 into a 2"
    else
      no "(v) stripping the guard also moved the corpus verdicts (dup rc=$g3 want 1, clean rc=$g4 want 0) — the guard is interfering with real comparisons"
    fi
  fi
fi

# (va) CONDITION (5), THE POLARITY OF THE WHOLE — the fix for the guard's second false refusal, so
# it gets its own control rather than riding on (v)'s. Strip every line of the condition (all five
# are marked, and the count is asserted, because a partially-stripped `case` would not even parse):
# the guard reverts to polarity-blind and the reproduced FALSE REFUSAL comes straight back.
POL_LINES="$(grep -c 'POLARITY_OF_THE_WHOLE' "$VE" 2>/dev/null || true)"; [ -n "$POL_LINES" ] || POL_LINES=0
if [ "$POL_LINES" -ne 5 ]; then
  no "(va) condition (5) has $POL_LINES marked lines, expected 5 — the mutant cannot be aimed at all of it"
else
  awk '!/POLARITY_OF_THE_WHOLE/' "$VE" > "$TMP/mut-polarity.sh"
  POL_LEFT="$(grep -c 'POLARITY_OF_THE_WHOLE' "$TMP/mut-polarity.sh" 2>/dev/null || true)"; [ -n "$POL_LEFT" ] || POL_LEFT=0
  if [ "$POL_LEFT" -ne 0 ]; then
    no "(va) the polarity mutant still has $POL_LEFT marked line(s) — a partially-stripped condition proves nothing"
  elif mutated_differs mut-polarity.sh "condition (5) strip"; then
    ok "(va) the mutation is NON-VACUOUS: 5 marked lines in the real validator, 0 in the mutant"
    bash "$TMP/mut-polarity.sh" contradiction --entry "$REPROENTRY" --store "$REPROSTORE" >/dev/null 2>&1; p1=$?
    [ "$p1" -eq 2 ] \
      && ok "(va) CONFIRMED: without condition (5) the reproduced FALSE REFUSAL returns (rc=2 on a store that cannot contradict) — (5) is what stands the guard down" \
      || no "(va) the polarity-blind mutant did NOT reproduce the false refusal (rc=$p1) — the REPRO case may be passing for some other reason"
    # ...and it must not have simply disabled the guard: duplicate's catch is untouched by (5).
    bash "$TMP/mut-polarity.sh" duplicate --entry "$DOCENTRY" --store "$DOCSTORE" >/dev/null 2>&1; p2=$?
    bash "$TMP/mut-polarity.sh" duplicate --entry "$DOCENTRY" --store "$DOCCORPUS" >/dev/null 2>&1; p3=$?
    { [ "$p2" -eq 2 ] && [ "$p3" -eq 1 ]; } \
      && ok "(va) the same mutant leaves duplicate's catch and its correctly-shaped control UNCHANGED (2 and 1) — (5) only ever stands the guard DOWN" \
      || no "(va) stripping condition (5) also moved duplicate's verdicts (fragments rc=$p2 want 2, corpus rc=$p3 want 1)"
  fi
fi

# (vb) THE JUDGING RULE IS REQUIRED, not defaulted. Blank out the rule both call sites pass: an
# unrecognised rule must stand the guard DOWN (never guess a polarity), so duplicate's catch goes
# quiet. This pins the `*)` arm as a real fail-toward-silence, not dead code.
sed -e 's/"\$_VE_STORE" same "\$np"/"$_VE_STORE" "" "$np"/' \
    -e 's/"\$_VE_STORE" opposite "\$np"/"$_VE_STORE" "" "$np"/' "$VE" > "$TMP/mut-rule.sh"
if mutated_differs mut-rule.sh "judging-rule blanking"; then
  RULE_LEFT="$(grep -cE 'if _ve_shape_incommensurable .*(same|opposite) ' "$TMP/mut-rule.sh" 2>/dev/null || true)"; [ -n "$RULE_LEFT" ] || RULE_LEFT=0
  if [ "$RULE_LEFT" -ne 0 ]; then
    no "(vb) $RULE_LEFT call site(s) still pass a judging rule — the mutant is partially applied"
  else
    bash "$TMP/mut-rule.sh" duplicate --entry "$DOCENTRY" --store "$DOCSTORE" >/dev/null 2>&1; q1=$?
    [ "$q1" -eq 0 ] \
      && ok "(vb) an unrecognised judging rule stands the guard DOWN (rc=0, catch lost) rather than guessing — a mis-wired future sharer cannot manufacture a false refusal" \
      || no "(vb) an unrecognised judging rule produced rc=$q1, wanted 0 — the guard is guessing a polarity it was not given"
  fi
fi

# (xxii) NUMERIC RATIO, narrowing (iv): delete the all-digits suppressor => a counting ratio reads
# as a slug again. Every one of these was a live false refusal.
quiet "narrowing (iv): a numeric ratio is not a slug — '117/117', '59/59', '85/100' pass" \
  "$VE" cross-repo --entry "the suite went 117/117 green, 59/59 suites passed, coverage 85/100 lines" --root "$REPO_ROOT"
advisory "ADVISORY_CROSS_REPO" "narrowing (iv) is BOTH-halves-only: a STRUCTURALLY marked numeric slug is still REPORTED" \
  "$VE" cross-repo --entry "cloned from github.com/117/117 yesterday" --root "$REPO_ROOT"
sed -e 's/^    \*\[!0-9\]\*) : ;;.*$/    *) : ;;/' -e 's/^    \*) return 1 ;;.*ratio.*$/    *) : ;;/' "$VE" > "$TMP/mut-ratio.sh"
if mutated_differs mut-ratio.sh "numeric-ratio suppressor"; then
  RATIO_LEFT="$(grep -c 'a ratio, never a slug' "$TMP/mut-ratio.sh" 2>/dev/null)"; [ -n "$RATIO_LEFT" ] || RATIO_LEFT=0
  if [ "$RATIO_LEFT" -ne 0 ]; then
    no "(xxii) $RATIO_LEFT suppressor arm(s) survive in the mutant — it is partially applied"
  else
    LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" mut_run "$TMP/mut-ratio.sh" cross-repo \
      --entry "the suite went 117/117 green" --root "$REPO_ROOT"
    r1=$MADV
    LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" mut_run "$TMP/mut-ratio.sh" cross-repo \
      --entry "octocat/repo2 has the bug" --root "$REPO_ROOT"
    r2=$MADV
    [ "$r1" -eq 1 ] \
      && ok "narrowing (iv): deleting the all-digits suppressor refuses '117/117' again — the suppressor is what passes it" \
      || no "narrowing (iv): the ratio mutant did not discriminate (rc=$r1, wanted 1)"
    [ "$r2" -eq 1 ] \
      && ok "narrowing (iv): the same mutant still refuses 'octocat/repo2' — it removed only the all-digits arm" \
      || no "narrowing (iv): the ratio mutant changed the fused-digit verdict too (rc=$r2)"
  fi
fi

# (xxiii) PROSE `A/B.ext` SHORTHAND: the dead-reference check's two-segment veto. Mutant = let every
# two-segment token through, i.e. the pre-fix behaviour.
quiet "prose A/B shorthand ending in an extension is SKIPPED, not refused — 'CHANGELOG/CLAUDE.md'" \
  "$VE" dead-reference --entry "CHANGELOG/CLAUDE.md both drifted; see README/AGENT_GUIDELINES.md" --root "$REPO_ROOT"
quiet "CONTROL: a two-segment path whose owner IS a repo directory is still examined and resolves" \
  "$VE" dead-reference --entry "the docs/PITFALLS.md file" --root "$REPO_ROOT"
advisory "ADVISORY_DEAD_REFERENCE" "CONTROL: a DEAD two-segment path under a real directory is still REPORTED" \
  "$VE" dead-reference --entry "see docs/NO-SUCH-FILE-HERE.md" --root "$REPO_ROOT"
sed -e 's/^    _ve_owner_is_repo_dir "\$owner" "\$root" || continue$/    :/' "$VE" > "$TMP/mut-2seg.sh"
if mutated_differs mut-2seg.sh "two-segment prose veto"; then
  SEG_LEFT="$(grep -c '_ve_owner_is_repo_dir "\$owner"' "$TMP/mut-2seg.sh" 2>/dev/null)"; [ -n "$SEG_LEFT" ] || SEG_LEFT=0
  if [ "$SEG_LEFT" -ne 0 ]; then
    no "(xxiii) $SEG_LEFT veto call site(s) survive in the mutant — it is partially applied"
  else
    mut_run "$TMP/mut-2seg.sh" dead-reference --entry "CHANGELOG/CLAUDE.md both drifted" --root "$REPO_ROOT"
    r1=$MADV
    mut_run "$TMP/mut-2seg.sh" dead-reference --entry "the docs/PITFALLS.md file" --root "$REPO_ROOT"
    r2=$MADV
    [ "$r1" -eq 1 ] \
      && ok "two-segment veto: without it 'CHANGELOG/CLAUDE.md' is refused again — the veto is what passes it" \
      || no "two-segment veto: the mutant did not discriminate (rc=$r1, wanted 1)"
    [ "$r2" -eq 0 ] \
      && ok "two-segment veto: the same mutant still RESOLVES 'docs/PITFALLS.md' — it removed only the skip, not the resolution" \
      || no "two-segment veto: the mutant broke the real-path control too (rc=$r2)"
  fi
fi

# (xxiv) THE INDEX UNION: a gitignored-but-real file must resolve. This needs its OWN fixture repo —
# the shape cannot be pinned in the committed corpus, because a file that is gitignored here is
# simply ABSENT on a fresh clone and the corpus entry would refuse in CI for a different reason.
# The fixture is a real git work tree with a TRACKED file and an UNTRACKED one: that is the only
# arrangement that discriminates, since in a NON-git root `git ls-files` is empty and the old
# fallback fired correctly. That is exactly why the bug was invisible — the fallback was dead code
# only in the case nobody built a fixture for.
# Both files sit in SUBDIRECTORIES and are cited by their BARE names, which is what the live defect
# looked like (`.supervisor/state.md` cited as `state.md`). That placement is load-bearing for the
# control, not decoration: `_ve_path_resolves` tries `[ -e "$root/$p" ]` BEFORE it consults the
# index, so a file sitting directly at the root resolves without the index being read at all and the
# mutant below cannot discriminate. Measured — the first version of this fixture put both files at
# the root and the mutant stayed green while the union was genuinely neutered.
UNIONREPO="$TMP/unionrepo"
mkdir -p "$UNIONREPO/tracked-sub" "$UNIONREPO/scratch-sub"
( cd "$UNIONREPO" && git init -q . \
    && printf 'tracked\n' > tracked-sub/tracked-note.md \
    && git add tracked-sub/tracked-note.md ) >/dev/null 2>&1
printf 'scratch\n' > "$UNIONREPO/scratch-sub/untracked-scratch.md"
UNION_TRACKED="$(git -C "$UNIONREPO" ls-files 2>/dev/null | tr '\n' ' ')"
if [ "$UNION_TRACKED" != "tracked-sub/tracked-note.md " ]; then
  no "(xxiv) the union fixture repo did not build (ls-files='$UNION_TRACKED') — this control cannot run"
else
  ok "(xxiv) the union fixture is a REAL work tree with a non-empty git index — the old find-only-when-empty fallback could never fire here"
  quiet "index union: a gitignored-but-real file resolves ('untracked-scratch.md')" \
    "$VE" dead-reference --entry "the projector writes untracked-scratch.md each phase" --root "$UNIONREPO"
  quiet "index union: the TRACKED file still resolves — the union added a source, it replaced nothing" \
    "$VE" dead-reference --entry "see tracked-note.md for the map" --root "$UNIONREPO"
  advisory "ADVISORY_DEAD_REFERENCE" "index union CONTROL: a file in NEITHER source is still REPORTED" \
    "$VE" dead-reference --entry "see never-existed-anywhere.md" --root "$UNIONREPO"
  sed -e 's/-maxdepth 8/-maxdepth 0 -name __ve_no_such_name__/' "$VE" > "$TMP/mut-union.sh"
  if mutated_differs mut-union.sh "repo-index union"; then
    UNION_LEFT="$(grep -c 'maxdepth 8' "$TMP/mut-union.sh" 2>/dev/null)"; [ -n "$UNION_LEFT" ] || UNION_LEFT=0
    if [ "$UNION_LEFT" -ne 0 ]; then
      no "(xxiv) $UNION_LEFT find call site(s) survive in the mutant — it is partially applied"
    else
      mut_run "$TMP/mut-union.sh" dead-reference --entry "the projector writes untracked-scratch.md each phase" --root "$UNIONREPO"
      r1=$MADV
      mut_run "$TMP/mut-union.sh" dead-reference --entry "see tracked-note.md for the map" --root "$UNIONREPO"
      r2=$MADV
      [ "$r1" -eq 1 ] \
        && ok "index union: with the on-disk half neutered the untracked file is refused again — the union is what resolves it" \
        || no "index union: the mutant did not discriminate (rc=$r1, wanted 1)"
      [ "$r2" -eq 0 ] \
        && ok "index union: the same mutant still resolves the TRACKED file — it removed only the on-disk half" \
        || no "index union: the mutant broke the tracked-file control too (rc=$r2)"
    fi
  fi
fi

echo "== 11b. AC16 CORPUS REGRESSION: EVERY STORE A SOLE WRITER OWNS replays with ZERO refusals =="
# THE regression guard whose absence let a 57% false-refusal rate reach a working tree. The five
# checks looked correct in isolation and were green on 87 hand-written fixtures; replayed against
# the real corpus they refused 12 of 21 legitimate entries. Hand-written fixtures are written by the
# same mind that wrote the check and inherit its blind spots — only real prose does not.
#
# THIS SECTION USED TO REPLAY TWO HAND-LISTED FILES — .supervisor/memory/{LESSONS,PROJECT_MEMORY}.md
# — and that hand-listing, not any one recogniser, is the root cause of the fifth round of false
# refusals on this branch. `grep -c 'agent-memory'` over this whole suite returned ZERO: the store
# owned by the sixth writer was the one store the replay never read, and all three of that round's
# defects lived in it and shipped green. Rounds 1-4 each closed the instances review found and the
# next review found the same CLASS somewhere the tests did not reach. A replay that covers a
# hand-picked subset of the stores measures the subset, not the validator.
#
# So the corpus is now DERIVED FROM THE WRITERS. CURATED_STORES below is the ONE place a store is
# named, every registered store runs the same zero-refusals property, and the static assertion
# underneath fails this suite BY NAME if validate-entry.sh gains a SEVENTH sole writer that is not
# in it — a new writer cannot inherit the validator without inheriting this replay.
#
# Design notes, all load-bearing:
#  · The store is deliberately ABSENT (--store points at a nonexistent file). Replaying a stored
#    entry against the store that already holds it is a duplicate BY CONSTRUCTION, so an absent
#    store is what makes duplicate/contradiction examined-and-clean and puts the prose-scanning
#    checks (provenance, dead-reference, cross-repo) under test — which is where every false
#    refusal came from.
#  · Each store is replayed in the SHAPE ITS WRITER VALIDATES, not in some uniform shape of this
#    suite's invention: write-agent-memory.sh examines `description + body`, add-orientation.sh and
#    write-system-contract.sh examine the whole composed file, add-rule.sh examines
#    `statement + reason`, and the two markdown stores examine one `- [id] text` line per entry.
#    Replaying a shape the writer never passes would test this harness, not the writer's real path.
#  · The corpora are read READ-ONLY and may legitimately change over time, so this asserts a
#    PROPERTY of them (zero refusals), never a count.
#  · ABSENT vs EMPTY vs DRIFTED are three different facts and get three different verdicts. An
#    absent store SKIPS LOUDLY (the gitignored stores are absent on a fresh clone and in CI — the
#    (e5) precedent); a present-but-entryless store SKIPS LOUDLY (a store nobody has written to yet
#    is a legitimate state); a store holding candidate files that yield NO replayable text FAILS,
#    because that is format drift and is the vacuous form of this whole section. An UNREADABLE
#    entry inside a present store is counted as a refusal, never skipped past.

# ---- THE REGISTRY -----------------------------------------------------------
# One line per SOLE WRITER: <writer-script>|<store path, relative to the repo root>|<mode>|<excluded
# basename>. The path may be a GLOB (write-agent-memory.sh owns one store DIRECTORY PER AGENT).
# Modes mirror the shape each writer hands to --entry; see the design note above.
#   bullets   one `- [id] text` line per entry in a single markdown file
#   fmentry   a directory of frontmatter entry files; entry = `description` + body
#   wholefile a directory of files that ARE the composed entry verbatim
#   rules     a directory of JSON arrays; entry = `statement` + `reason`
#
# PER-STORE, PER-CHECK SCOPING — columns 5 and 6. Column 5 is EMPTY for every store that is judged by
# all five checks, which is the DEFAULT: scoping is opt-in, so narrowing a store's checks is always a
# deliberate, visible edit to this table rather than something that can drift in. When column 5 IS
# set, column 6 must give the REASON, and it lives ON THE REGISTRY LINE rather than in a comment
# further down, because a scope whose justification sits somewhere else is a scope nobody re-reads.
#
# WHY THE CONTRACTS STORE IS SCOPED — measured, not assumed. The five checks were written for CURATED
# HUMAN ENTRIES; `.supervisor/twin/contracts/` has a different author and a different contract, and
# applying all five wholesale is a category error. Replaying the migrated store measured it exactly:
# contradiction 0/21 refused, dead-reference 8/21, provenance 20/21. The 8 all cite OPTIONAL RUNTIME
# artifacts (`.supervisor/obsidian-config.json` from `/setup obsidian`, `.supervisor/telemetry-consent.json`
# from `/telemetry enable`, `/etc/otelcol-contrib/config.yaml`, `.supervisor/twin/ground-truth.json`) —
# a contract saying "this script reads X if present" is CORRECT prose when X is absent. And provenance
# refuses 20/21 because a machine-GENERATED interface artifact cites no PR or session, nor should it.
# The two comparison checks DO fit — a duplicated or self-contradicting contract is a real defect.
CURATED_STORES="\
add-orientation.sh|.agent/orientation|wholefile|README.md||
add-rule.sh|.agent/rules|rules|||
write-agent-memory.sh|.claude/agent-memory/*|fmentry|MEMORY.md||
write-lessons.sh|.supervisor/memory/LESSONS.md|bullets|||
write-project-memory.sh|.supervisor/memory/PROJECT_MEMORY.md|bullets|||
write-system-contract.sh|.supervisor/twin/contracts|wholefile||duplicate,contradiction|a generated interface artifact cites no PR, and documents runtime inputs that may legitimately be absent"

# The check names column 5 may name — the validator's own subcommands, so a typo cannot silently
# scope a store down to a check that does not exist.
REPLAY_KNOWN_CHECKS=" duplicate contradiction provenance dead-reference cross-repo "

# ---- the replay primitives --------------------------------------------------
replay_reset() { REPLAY_N=0; REPLAY_BAD=0; REPLAY_FIRST=""; REPLAY_CAND=0; REPLAY_CHECKS=""; REPLAY_MISMODE=""; REPLAY_ADV=0; }
REPLAY_ADV=0
# The store the replay compares against. ABSENT by default and deliberately so — replaying a stored
# entry against the store that already holds it is a duplicate BY CONSTRUCTION. The seeded vacuity
# control below is the one caller that points it at a real file, because with an absent store the
# two comparison checks return "no prior entries" before they examine anything, and NO blocking
# check could then be provoked at all.
REPLAY_STORE=""

# replay_one <label> <entry-text> — the five checks over ONE entry, tallied.
# `out` and `rc` are declared bare and assigned on their OWN lines: `local out="$(...)"` returns the
# status of `local`, not of the command substitution, which is how this repo has silently lost an
# exit status before. Nothing here is chained with `||` before $? is read, for the same reason.
replay_one() {
  local label="$1" text="$2" out rc
  case "$text" in *[![:space:]]*) : ;; *) return 0 ;; esac
  REPLAY_N=$((REPLAY_N + 1))
  # An UNSCOPED store runs `all`; a scoped one runs its named checks one at a time and reports the
  # first non-zero. Running `all` and ignoring the checks a store is scoped out of would still let
  # those checks decide the exit status, which is the whole thing the scoping exists to prevent.
  # --root is $REPLAY_ROOT, which is the CLEAN-TREE EXTRACTION and deliberately not $REPO_ROOT —
  # see THE CLEAN-TREE ROOT above for the incident that moved it.
  # Advisory findings are TALLIED, never counted as refusals: the replay's property is "no live
  # entry is BLOCKED", and folding warnings into that would restore, inside the test, exactly the
  # false-refusal pressure the design change removed.
  local chk
  for chk in ${REPLAY_CHECKS:-all}; do
    out="$(LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" bash "$VE" "$chk" \
      --entry "$text" --source "corpus-replay:$label" \
      --store "${REPLAY_STORE:-$TMP/no-such-corpus-store.md}" --root "$REPLAY_ROOT" 2>&1)"
    rc=$?
    case "$out" in *"ADVISORY:"*) REPLAY_ADV=$((REPLAY_ADV + 1)) ;; esac
    if [ "$rc" -ne 0 ]; then
      REPLAY_BAD=$((REPLAY_BAD + 1))
      [ -n "$REPLAY_FIRST" ] || REPLAY_FIRST="[$label] $chk rc=$rc $(printf '%s' "$out" | sed -n '1p')"
      return 0
    fi
  done
  return 0
}

# An entry file this suite could not READ is a hole in the replay; counting it as a refusal is the
# validator's own could-not-examine discipline applied to the harness.
replay_unreadable() {
  REPLAY_BAD=$((REPLAY_BAD + 1))
  [ -n "$REPLAY_FIRST" ] || REPLAY_FIRST="[$1] the entry file exists but could not be read"
  return 0
}

# The two frontmatter readers are write-agent-memory.sh's fm_field/fm_body, deliberately: the entry
# this replays must be the entry that writer examines.
replay_fm_description() {
  awk '
    NR == 1 && $0 == "---" { inf = 1; next }
    inf && $0 == "---"     { exit }
    inf {
      i = index($0, ":")
      if (i > 0) {
        key = substr($0, 1, i - 1); val = substr($0, i + 1)
        gsub(/^[ \t]+|[ \t]+$/, "", key); gsub(/^[ \t]+|[ \t]+$/, "", val)
        if (key == "description") { print val; exit }
      }
    }
  ' "$1" 2>/dev/null
}
replay_fm_body() {
  awk '
    NR == 1 && $0 == "---" { inf = 1; next }
    inf && $0 == "---"     { inf = 0; next }
    inf                    { next }
    { print }
  ' "$1" 2>/dev/null
}

replay_mode_bullets() {
  local f="$1" line id text
  [ -f "$f" ] || return 0
  [ -r "$f" ] || { REPLAY_CAND=$((REPLAY_CAND + 1)); replay_unreadable "${f##*/}"; return 0; }
  [ -s "$f" ] && REPLAY_CAND=$((REPLAY_CAND + 1))
  while IFS= read -r line; do
    case "$line" in "- ["*) : ;; *) continue ;; esac
    id="$(printf '%s' "$line" | sed -e 's/^- \[\([0-9a-fA-F]*\)\].*$/\1/')"
    text="$(printf '%s' "$line" | sed -e 's/^- \[[0-9a-fA-F]*\][[:space:]]*//' -e 's/<!--.*-->[[:space:]]*$//')"
    replay_one "${f##*/}:$id" "$text"
  done < "$f"
  return 0
}

replay_mode_fmentry() {
  local d="$1" excl="${2:-}" f
  for f in "$d"/*.md; do
    [ -f "$f" ] || continue                     # unmatched glob stays literal under bash 3.2
    [ -n "$excl" ] && [ "${f##*/}" = "$excl" ] && continue
    REPLAY_CAND=$((REPLAY_CAND + 1))
    [ -r "$f" ] || { replay_unreadable "${d##*/}/${f##*/}"; continue; }
    replay_one "${d##*/}/${f##*/}" "$(replay_fm_description "$f")
$(replay_fm_body "$f")"
  done
  return 0
}

replay_mode_wholefile() {
  local d="$1" excl="${2:-}" f
  for f in "$d"/*.md; do
    [ -f "$f" ] || continue
    [ -n "$excl" ] && [ "${f##*/}" = "$excl" ] && continue
    REPLAY_CAND=$((REPLAY_CAND + 1))
    [ -r "$f" ] || { replay_unreadable "${f##*/}"; continue; }
    replay_one "${f##*/}" "$(cat "$f")"
  done
  return 0
}

replay_mode_rules() {
  local d="$1" f n i st rs
  command -v jq >/dev/null 2>&1 || return 0     # no jq: nothing extracted, so the store SKIPS loudly
  for f in "$d"/*.json; do
    [ -f "$f" ] || continue
    [ -r "$f" ] || { REPLAY_CAND=$((REPLAY_CAND + 1)); replay_unreadable "${f##*/}"; continue; }
    n="$(jq 'if type == "array" then length else 0 end' "$f" 2>/dev/null)"
    case "$n" in ''|*[!0-9]*) continue ;; esac
    i=0
    while [ "$i" -lt "$n" ]; do
      REPLAY_CAND=$((REPLAY_CAND + 1))
      st="$(jq -r --argjson i "$i" '.[$i].statement // ""' "$f" 2>/dev/null)"
      rs="$(jq -r --argjson i "$i" '.[$i].reason // ""' "$f" 2>/dev/null)"
      if [ -n "$rs" ]; then
        replay_one "${f##*/}[$i]" "$st
$rs"
      else
        replay_one "${f##*/}[$i]" "$st"
      fi
      i=$((i + 1))
    done
  done
  return 0
}

# replay_store <mode> <pathspec> <excl> — $pathspec is deliberately UNQUOTED so a registry glob
# (`.claude/agent-memory/*`) expands to one store per agent. Sets REPLAY_FOUND=1 when at least one
# real store was located, which is what separates "absent" from "empty".
replay_store() {
  local mode="$1" pathspec="$2" excl="${3:-}" p
  REPLAY_FOUND=0; REPLAY_MISMODE=""
  case " bullets fmentry wholefile rules " in
    *" $mode "*) : ;;
    *) REPLAY_MISMODE="unknown mode '$mode'"; return 0 ;;
  esac
  for p in $pathspec; do
    # A registration whose MODE does not match the KIND of thing on disk used to degrade into the
    # "absent" skip and mask the store entirely — `bullets` pointed at a directory simply found no
    # file and reported the store missing. A wrong mode is a registry BUG, so it fails and names
    # itself; only a path that is genuinely not there is allowed to skip.
    if [ "$mode" = bullets ]; then
      if [ -d "$p" ]; then REPLAY_MISMODE="mode 'bullets' expects a FILE but $p is a directory"; continue; fi
      [ -f "$p" ] || continue
      REPLAY_FOUND=1; replay_mode_bullets "$p"
    else
      if [ -f "$p" ]; then REPLAY_MISMODE="mode '$mode' expects a DIRECTORY but $p is a file"; continue; fi
      [ -d "$p" ] || continue
      REPLAY_FOUND=1
      case "$mode" in
        fmentry)   replay_mode_fmentry "$p" "$excl" ;;
        wholefile) replay_mode_wholefile "$p" "$excl" ;;
        rules)     replay_mode_rules "$p" ;;
      esac
    fi
  done
  return 0
}

# replay_corpus <file>... — the bullets-mode entry point the committed shape corpus and the
# vacuity control below still use, now expressed in the primitives above so there is one replay.
replay_corpus() {
  local f
  replay_reset
  for f in "$@"; do replay_mode_bullets "$f"; done
  return 0
}

# ---- THE STATIC HALF: no writer may go unreplayed ---------------------------
# Derived from the SOURCE, so it tracks the code rather than this file's memory of it. A sole writer
# is any non-test script here that invokes the shared validator; validate-entry.sh is itself excluded
# (it DEFINES validate_entry_all, it does not own a store).
# Built in a plain loop, NOT inside a `$( ... )`: bash 3.2 (the macOS shell this repo targets)
# mis-parses a `case` pattern's `)` as the end of a command substitution.
WRITERS_FOUND=""
for f in "$HERE"/*.sh; do
  b="${f##*/}"
  case "$b" in test-*|validate-entry.sh) continue ;; esac
  if grep -q 'validate_entry_all' "$f" 2>/dev/null; then
    WRITERS_FOUND="$WRITERS_FOUND$b
"
  fi
done
WRITERS_FOUND="$(printf '%s' "$WRITERS_FOUND" | sort -u | tr '\n' ' ')"
WRITERS_WANT="$(printf '%s\n' "$CURATED_STORES" | awk -F'|' 'NF { print $1 }' | sort -u | tr '\n' ' ')"
if [ -z "$WRITERS_FOUND" ]; then
  no "AC16: no script in $HERE calls validate_entry_all — the whole store replay would run vacuously"
elif [ "$WRITERS_FOUND" = "$WRITERS_WANT" ]; then
  ok "AC16: CURATED_STORES registers exactly the sole writers that call validate_entry_all in source ($WRITERS_WANT) — no writer's store is unreplayed"
else
  no "AC16: the sole writers in source are [$WRITERS_FOUND] but CURATED_STORES registers [$WRITERS_WANT] — add the new writer's store to CURATED_STORES so the corpus replay covers it"
fi

# A registration is only worth having if it points at the store the writer actually owns. Without
# this, a seventh writer could be silenced by registering a path nothing writes to: the static check
# above would pass, the store would SKIP as absent, and the coverage hole would be back with a
# registry entry vouching for it. Each writer's own source must name its registered store path.
REG_BAD=""
while IFS='|' read -r w spath smode sexcl schecks sreason; do
  [ -n "$w" ] || continue
  case "$spath" in *"*"*) spath="${spath%/\*}" ;; esac      # compare the glob's stable prefix
  grep -qF "$spath" "$HERE/$w" 2>/dev/null || REG_BAD="$REG_BAD $w->$spath"
done <<EOF
$CURATED_STORES
EOF
[ -z "$REG_BAD" ] \
  && ok "AC16: every registered store path is named in its own writer's source — no registration points at a store nothing writes to" \
  || no "AC16: registered store path(s) never mentioned by the owning writer:$REG_BAD — the registry vouches for a store that writer does not own"

# ---- THE SCOPING GATES ------------------------------------------------------
# Three, and each closes a way a store could be quietly stopped from being judged. Scoping is the one
# mechanism here that can REMOVE coverage, so it is the one that needs the most saying-no.
SCOPE_BAD=""; SCOPE_NOREASON=""; SCOPE_EMPTY=""; SCOPE_COUNT=0
while IFS='|' read -r w spath smode sexcl schecks sreason; do
  [ -n "$w" ] || continue
  case "$schecks" in *[!\ ]*) : ;; *) continue ;; esac      # unscoped: the default, nothing to check
  SCOPE_COUNT=$((SCOPE_COUNT + 1))
  n_ok=0
  for c in $(printf '%s' "$schecks" | tr ',' ' '); do
    case "$REPLAY_KNOWN_CHECKS" in
      *" $c "*) n_ok=$((n_ok + 1)) ;;
      *) SCOPE_BAD="$SCOPE_BAD $w->$c" ;;
    esac
  done
  [ "$n_ok" -gt 0 ] || SCOPE_EMPTY="$SCOPE_EMPTY $w"
  case "$sreason" in *[!\ ]*) : ;; *) SCOPE_NOREASON="$SCOPE_NOREASON $w" ;; esac
done <<EOF
$CURATED_STORES
EOF
[ -z "$SCOPE_BAD" ] \
  && ok "AC16 scoping: every scoped check names a real validate-entry subcommand — a typo cannot scope a store down to a check that does not exist" \
  || no "AC16 scoping: unknown check name(s) in CURATED_STORES:$SCOPE_BAD — that store is scoped to a check the validator does not have"
[ -z "$SCOPE_EMPTY" ] \
  && ok "AC16 scoping: no store is scoped down to ZERO checks — a registered store is always judged by something" \
  || no "AC16 scoping: store(s) scoped to no runnable check at all:$SCOPE_EMPTY — the store is registered but judged by nothing, which is coverage removed in silence"
[ -z "$SCOPE_NOREASON" ] \
  && ok "AC16 scoping: every scoped store records WHY on its own registry line — a scope whose justification lives elsewhere is one nobody re-reads" \
  || no "AC16 scoping: scoped store(s) with no reason in column 6:$SCOPE_NOREASON"
[ "$SCOPE_COUNT" -gt 0 ] \
  && ok "AC16 scoping: $SCOPE_COUNT store(s) are scoped, so these three gates are not running vacuously" \
  || no "AC16 scoping: NO store is scoped, so the three gates above asserted nothing — remove them or the scoping mechanism is dead code"

# ---- THE CLEAN-TREE ROOT ----------------------------------------------------
# THE REPLAY RESOLVES AGAINST A `git archive HEAD` EXTRACTION, NOT AGAINST $REPO_ROOT, and this is
# the single most important line in this section. $REPO_ROOT is THE AUTHOR'S WORKING TREE — the one
# environment where every gitignored runtime artifact this system produces happens to exist. A
# replay that resolves cited paths against it is measuring the machine, not the validator.
#
# MEASURED, and this is the incident that produced the whole advisory design change: a fix that
# unioned an on-disk `find` into the path index made gitignored-but-real files resolve, which was
# correct on the machine that shipped it and wrong everywhere else. This suite reported 231 passed /
# 0 failed; the same commit extracted with `git archive HEAD` reported 229 / 1, with 3 of 28 live
# curated entries falsely refused. The flagship regression guard could not see it because it replayed
# $REPO_ROOT. CI was red while the author's tree was green.
#
# The guard is kept — and re-aimed — rather than dropped now that its two prose-scanning subjects no
# longer block. It still protects the THREE CHECKS THAT DO: duplicate, contradiction and provenance
# are what can still refuse a live curated entry, and they are exactly what this replay now gates.
# The clean-tree extraction is what keeps that gate from being an assertion about one laptop.
#
# The ENTRIES still come from the working tree (the curated stores are gitignored, so they exist
# nowhere else); only the ROOT paths resolve against is clean. Two different jobs, two different
# directories, neither borrowed from the other.
CLEAN_ROOT="$TMP/clean-tree"
mkdir -p "$CLEAN_ROOT"
CLEAN_OK=0
if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  if git -C "$REPO_ROOT" archive HEAD 2>/dev/null | tar -x -C "$CLEAN_ROOT" 2>/dev/null; then
    CLEAN_OK=1
  fi
fi
# FAILING TO BUILD IT IS A FAILURE, not a silent fall back to $REPO_ROOT. Falling back would restore
# the exact blind spot this exists to close, and it would do it invisibly.
if [ "$CLEAN_OK" -ne 1 ] || [ ! -f "$CLEAN_ROOT/loomwright/scripts/validate-entry.sh" ]; then
  no "the clean-tree extraction could not be built at $CLEAN_ROOT (git archive HEAD | tar) — the corpus replay must NOT silently fall back to the working tree, so this fails instead"
  REPLAY_ROOT="$CLEAN_ROOT"
else
  ok "the clean-tree extraction built from git archive HEAD — the replay resolves paths against a fresh checkout, not the author's working tree"
  REPLAY_ROOT="$CLEAN_ROOT"
fi

# THE EXTRACTION IS ONLY WORTH HAVING IF IT DIFFERS FROM THE WORKING TREE IN THE WAY THAT MATTERS,
# and the probe that shows it is CONSTRUCTED here rather than derived from whatever gitignored files
# happen to be lying around. That derivation was tried first and was itself machine-dependent — the
# first ignored file on one machine was `.claude/settings.local.json`, whose OWNER HALF `.claude` is
# a directory in the working tree and not in the archive, so the token was SKIPPED (never judged)
# on one root and resolved on the other, and the pair measured 0 vs 0 while claiming to measure the
# divergence. Deriving a probe from the environment, inside the guard whose entire purpose is to
# stop the environment deciding the verdict, is the same defect one level up.
#
# So the artifact is created, measured, and removed. It reproduces the LIVE defect's exact shape: a
# gitignored runtime artifact under `.supervisor/`, cited BY BARE NAME, which is how the entry that
# turned CI red cited `state.md`. A bare `NAME.md` is a path candidate unconditionally, so nothing
# in this probe depends on which directories either tree happens to contain.
PROBE_NAME="ve-probe-runtime-state.md"
PROBE_ENTRY="the projector writes $PROBE_NAME each phase, see #146"
PROBE_FILE="$CLEAN_ROOT/.supervisor/$PROBE_NAME"
PROBE_COLL="$(cd "$REPO_ROOT" && git ls-files 2>/dev/null | grep -c "/$PROBE_NAME$")"; [ -n "$PROBE_COLL" ] || PROBE_COLL=0
if [ "$PROBE_COLL" -ne 0 ]; then
  no "the probe name $PROBE_NAME collides with $PROBE_COLL tracked file(s) — it would resolve on both roots and prove nothing; rename it"
else
  mkdir -p "$CLEAN_ROOT/.supervisor"
  # (a) the artifact is ABSENT — the state of every clean checkout, and of CI
  ve_run "$VE" all --entry "$PROBE_ENTRY" --store "$TMP/no-such-corpus-store.md" --source "pr-138" --root "$CLEAN_ROOT"
  ABSENT_RC="$VRC"; ABSENT_ADV="$ADV"
  # (b) the same entry, the same validator, the same root — with the artifact present, which is the
  #     state of the machine that shipped the change that turned CI red
  printf 'runtime state\n' > "$PROBE_FILE"
  ve_run "$VE" all --entry "$PROBE_ENTRY" --store "$TMP/no-such-corpus-store.md" --source "pr-138" --root "$CLEAN_ROOT"
  PRESENT_RC="$VRC"; PRESENT_ADV="$ADV"
  { [ "$ABSENT_RC" -eq 0 ] && [ "$PRESENT_RC" -eq 0 ]; } \
    && ok "MACHINE-INDEPENDENCE: an entry citing a gitignored runtime artifact gets the SAME verdict (0) whether or not the artifact exists — this is the pair that was 1 vs 0 and turned CI red" \
    || no "MACHINE-INDEPENDENCE BROKEN: the verdict moved with a file's presence (absent rc=$ABSENT_RC, present rc=$PRESENT_RC) — a write-time gate whose answer depends on which files are lying around is not a gate"
  { [ "$ABSENT_ADV" -eq 1 ] && [ "$PRESENT_ADV" -eq 0 ]; } \
    && ok "...and the ADVISORY still moves with the tree (reported when the artifact is absent, silent when it is present) — the check reads the world, so the pair above is not vacuous" \
    || no "the advisory did NOT move between the two tree states (absent advised=$ABSENT_ADV, present advised=$PRESENT_ADV) — the machine-independence assertion above is passing for some other reason"

  # THE MUTATION CONTROL FOR THE WHOLE DESIGN CHANGE: restore blocking in the dead-reference prose
  # loop and the divergence comes straight back — rc 1 on the clean tree, rc 0 where the artifact
  # exists. That is the 229/1-vs-231/0 incident, reproduced on demand in one pair, and it is what
  # makes the two assertions above evidence rather than a description of the current build.
  #
  # MEASURED AT THE CHECK, NOT AT THE AGGREGATE, and the reason is worth recording because the first
  # version of this control was aimed at `all` and came back 0-vs-0: validate_entry_all ABSORBS a
  # non-zero status from an advisory check, so the aggregate refuses to reproduce the divergence
  # even when the check itself is re-blocked. That is the absorber working (it has its own control
  # in section 12b), and it means the check is the only place the old behaviour can still be
  # exhibited — two independent guards, each measured where it acts.
  PROBE_SITES="$(grep -c '_ve_advise "ADVISORY_DEAD_REFERENCE" "the entry cites' "$VE" 2>/dev/null)"; [ -n "$PROBE_SITES" ] || PROBE_SITES=0
  if [ "$PROBE_SITES" -ne 1 ]; then
    no "the dead-reference prose report has $PROBE_SITES call site(s), expected exactly 1 — the re-blocking mutant cannot be aimed at all of it"
  else
    awk '{ if (index($0, "_ve_advise \"ADVISORY_DEAD_REFERENCE\" \"the entry cites")) { print "      _ve_refuse \"REFUSE_DEAD_REFERENCE\" \"re-blocked by mutation\"; return 1"; next } print }' \
      "$VE" > "$TMP/mut-reblock.sh"
    REBLOCK_LEFT="$(grep -c '_ve_advise "ADVISORY_DEAD_REFERENCE" "the entry cites' "$TMP/mut-reblock.sh" 2>/dev/null)"; [ -n "$REBLOCK_LEFT" ] || REBLOCK_LEFT=0
    if [ "$REBLOCK_LEFT" -ne 0 ]; then
      no "the re-blocking mutant still has $REBLOCK_LEFT advisory call site(s) — a partially-applied mutant proves nothing"
    elif mutated_differs mut-reblock.sh "dead-reference re-blocking"; then
      rm -f "$PROBE_FILE"
      bash "$TMP/mut-reblock.sh" dead-reference --entry "$PROBE_ENTRY" --root "$CLEAN_ROOT" >/dev/null 2>&1
      MB_ABSENT=$?
      printf 'runtime state\n' > "$PROBE_FILE"
      bash "$TMP/mut-reblock.sh" dead-reference --entry "$PROBE_ENTRY" --root "$CLEAN_ROOT" >/dev/null 2>&1
      MB_PRESENT=$?
      # ...and the UNMUTATED check on the same two states, so the control shows the contrast rather
      # than only the mutant's behaviour.
      rm -f "$PROBE_FILE"
      bash "$VE" dead-reference --entry "$PROBE_ENTRY" --root "$CLEAN_ROOT" >/dev/null 2>&1
      RB_REAL_ABSENT=$?
      printf 'runtime state\n' > "$PROBE_FILE"
      { [ "$MB_ABSENT" -eq 1 ] && [ "$MB_PRESENT" -eq 0 ]; } \
        && ok "RE-BLOCKING CONTROL: with dead-reference refusing again, the SAME entry is refused on a clean tree (1) and accepted where the artifact exists (0) — the demotion is what removed the machine dependence, not some other change" \
        || no "RE-BLOCKING CONTROL: the re-blocked mutant did not reproduce the divergence (absent rc=$MB_ABSENT want 1, present rc=$MB_PRESENT want 0) — the pair above may be green for another reason"
      [ "$RB_REAL_ABSENT" -eq 0 ] \
        && ok "RE-BLOCKING CONTROL, other side: the REAL check returns 0 on the very input its re-blocked twin refuses — the difference is the demotion and nothing else" \
        || no "RE-BLOCKING CONTROL: the real check returned rc=$RB_REAL_ABSENT on the clean tree, so it is still blocking"
    fi
  fi
  # The probe must not survive into the replay below, which resolves against this same root.
  rm -f "$PROBE_FILE"
  [ ! -e "$PROBE_FILE" ] \
    && ok "the probe artifact was removed from the clean-tree root — the corpus replay below sees a genuinely clean checkout" \
    || no "the probe artifact survived into the corpus replay — the replay root is no longer clean"
fi

# ---- THE REPLAY -------------------------------------------------------------
REPLAY_TOTAL=0
REPLAY_ADV_TOTAL=0
while IFS='|' read -r w spath smode sexcl schecks sreason; do
  [ -n "$w" ] || continue
  replay_reset
  REPLAY_CHECKS="$(printf '%s' "$schecks" | tr ',' ' ')"
  replay_store "$smode" "$REPO_ROOT/$spath" "$sexcl"
  SCOPE_NOTE=""
  [ -n "$REPLAY_CHECKS" ] && SCOPE_NOTE=" [scoped to:$REPLAY_CHECKS— $sreason]"
  if [ -n "$REPLAY_MISMODE" ]; then
    no "AC16 [$w]: MIS-REGISTERED MODE — $REPLAY_MISMODE. A wrong mode used to degrade into the 'absent' skip and mask the store entirely; it fails instead."
  elif [ "$REPLAY_FOUND" -ne 1 ]; then
    ok "AC16 SKIPPED [$w]: no store at $spath (gitignored, so absent on a fresh clone and in CI) — not asserted rather than asserted vacuously"
  elif [ "$REPLAY_CAND" -eq 0 ]; then
    ok "AC16 SKIPPED [$w]: the store at $spath exists but holds no entries yet — nothing to replay"
  elif [ "$REPLAY_N" -eq 0 ]; then
    no "AC16 [$w]: the store at $spath holds $REPLAY_CAND candidate entr(ies) but yielded NO replayable text — its format drifted, and this replay would pass vacuously"
  elif [ "$REPLAY_BAD" -ne 0 ]; then
    no "AC16 [$w]: $REPLAY_BAD of $REPLAY_N live entries in $spath were REFUSED$SCOPE_NOTE (resolved against the CLEAN-TREE root) — first: $REPLAY_FIRST"
  else
    ok "AC16 [$w]: all $REPLAY_N live entries in $spath replay against the clean tree with ZERO refusals$SCOPE_NOTE${REPLAY_ADV:+ [$REPLAY_ADV advisory finding(s), reported and not counted]}"
  fi
  REPLAY_TOTAL=$((REPLAY_TOTAL + REPLAY_N))
  REPLAY_ADV_TOTAL=$((REPLAY_ADV_TOTAL + REPLAY_ADV))
done <<EOF
$CURATED_STORES
EOF

# The whole-section vacuity control: if EVERY registered store skipped, this section asserted
# nothing at all and must say so rather than reporting a row of green skips as coverage.
[ "$REPLAY_TOTAL" -gt 0 ] \
  && ok "AC16: the writer-driven replay examined $REPLAY_TOTAL live curated entries against the clean-tree root — the section is not vacuous ($REPLAY_ADV_TOTAL advisory finding(s) reported across them, which block nothing)" \
  || no "AC16: NOT ONE registered store yielded an entry, so this whole section asserted nothing"

# THE COMMITTED SHAPE CORPUS. The live replay above can only exercise shapes the live corpus happens
# to contain, and it contains none of the extensionless two-segment path shapes — every path it cites
# carries an extension or a trailing slash. So the live replay stayed GREEN through six false
# refusals found by review. This file is that shape's permanent replay case: same harness, same five
# checks, same zero-refusals property, but COMMITTED, so unlike the live stores it is present on a
# fresh clone and in CI and can never SKIP. A fix without a replay case is not a fix.
SHAPE_CORPUS="$HERE/fixtures/curated-shape-corpus.md"
if [ -r "$SHAPE_CORPUS" ]; then
  replay_corpus "$SHAPE_CORPUS"
  # An exact floor, not just ">0": a silently truncated corpus is the vacuous form of this assertion,
  # and it is committed so its size is a fact this suite may depend on.
  if [ "$REPLAY_N" -lt 10 ]; then
    no "the committed shape corpus yielded only $REPLAY_N entries (expected at least 10) — it was truncated or its line format drifted"
  else
    [ "$REPLAY_BAD" -eq 0 ] \
      && ok "SHAPE CORPUS: all $REPLAY_N committed extensionless-path entries replay with ZERO refusals" \
      || no "SHAPE CORPUS: $REPLAY_BAD of $REPLAY_N committed entries were REFUSED (false positives) — first: $REPLAY_FIRST"
  fi
else
  no "the committed shape corpus is missing at $SHAPE_CORPUS — this regression case cannot run"
fi

# Vacuity control for the harness itself: the same replay path, over a SYNTHETIC corpus seeded with
# one entry that must refuse, has to report that refusal. Without this, a replay loop that silently
# ran zero validators — or swallowed the status — would report "zero refusals" forever.
mkdir -p "$TMP/corpus"
# THE SEED NOW CARRIES BOTH KINDS, and that is the point of the rewrite rather than an addition.
# It used to seed ONE entry, a dead reference, and assert one refusal — a control that the design
# change would have silently emptied, because a dead reference no longer refuses anything. Seeding
# both kinds makes this one control assert the separation in both directions AND keep its original
# job (a harness that ran zero validators, or swallowed a status, still reports "zero refusals"):
#   aaaa0001  dead reference        -> ADVISORY only: reported, NOT counted as a refusal
#   aaaa0002  ordinary entry        -> neither
#   aaaa0003  a DUPLICATE of the seeded store line -> BLOCKING -> counted
{ printf '# Synthetic store\n'
  printf -- '- [cccc0001] the projector rewrites the phase banner on every terminal transition\n'
} > "$TMP/corpus/SEEDSTORE.md"
{ printf '# Synthetic\n'
  printf -- '- [aaaa0001] the guard lives in loomwright/scripts/long-gone-nowhere.sh\n'
  printf -- '- [aaaa0002] a perfectly ordinary entry naming no path and no repo\n'
  printf -- '- [aaaa0003] the projector rewrites the phase banner on every terminal transition\n'
} > "$TMP/corpus/SEEDED.md"
REPLAY_STORE="$TMP/corpus/SEEDSTORE.md"
replay_corpus "$TMP/corpus/SEEDED.md"
REPLAY_STORE=""
{ [ "$REPLAY_N" -eq 3 ] && [ "$REPLAY_BAD" -eq 1 ]; } \
  && ok "AC16 control: the replay harness reports the BLOCKING seed and only it (3 replayed, 1 refused) — it still discriminates, and the advisory seed did not inflate the count" \
  || no "AC16 control: the seeded corpus gave N=$REPLAY_N bad=$REPLAY_BAD, wanted 3/1 — the replay harness is not discriminating"
[ "${REPLAY_ADV:-0}" -ge 1 ] \
  && ok "AC16 control: the seeded DEAD REFERENCE was reported as an advisory ($REPLAY_ADV) while refusing nothing — the harness sees warnings it does not count" \
  || no "AC16 control: the seeded dead reference produced NO advisory at all — the replay would go green over a check that had been deleted"

echo "== 12. no live state is touched =="
if [ -f "$LIVE_CFG" ]; then LIVE_CFG_AFTER="$(cksum < "$LIVE_CFG")"; else LIVE_CFG_AFTER="ABSENT"; fi
[ "$LIVE_CFG_BEFORE" = "$LIVE_CFG_AFTER" ] \
  && ok "the live .supervisor/config.json is byte-unchanged by this suite" \
  || no "this suite MODIFIED the live .supervisor/config.json"
if [ -f "$LIVE_CFG" ] && command -v jq >/dev/null 2>&1; then
  if jq -e '((.setup_memory.repo_allowlist // [])[] | select(test("^otherco/"; "i")))' "$LIVE_CFG" >/dev/null 2>&1; then
    no "a FOREIGN slug is present in the live allowlist — the publication gate is compromised"
  else
    ok "no foreign slug is present in the live allowlist"
  fi
fi
[ "$(cksum < "$STORE")" = "$STORE_CK" ] \
  && ok "the fixture store is byte-unchanged after every refusal (flag, never delete)" \
  || no "a refusal MUTATED the store"
LIVE_STORES_AFTER="$(cksum < "$REPO_ROOT/.supervisor/memory/LESSONS.md" 2>/dev/null)|$(cksum < "$REPO_ROOT/.supervisor/memory/PROJECT_MEMORY.md" 2>/dev/null)"
[ "$LIVE_STORES_BEFORE" = "$LIVE_STORES_AFTER" ] \
  && ok "the live curated stores are byte-unchanged — the corpus replay reads them, never writes" \
  || no "the corpus replay MODIFIED a live curated store"

echo "== 12b. THE SEPARATION: three checks block, two report, and validate_entry_all keeps them apart =="
# The whole design change, asserted at the aggregate — the only place a writer actually reads. Each
# case violates EXACTLY ONE check, so nothing here can pass because some earlier check fired first.
SEPSTORE="$TMP/sep-store.md"
{ printf '# store\n'
  printf -- '- [bbbb0001] release candidates promote through staging validation before production rollout begins across every regional cluster\n'
} > "$SEPSTORE"
SEP_OK="pr-138"

# --- the two ADVISORY violations: exit 0, AND the finding is printed -----------
# Both halves are asserted deliberately. `rc == 0` alone would still pass if the two checks were
# deleted from the aggregate outright, and "advisory" would then be indistinguishable from "gone".
advisory "ADVISORY_DEAD_REFERENCE" "AGGREGATE: an entry violating ONLY dead-reference exits 0 AND prints the advisory" \
  "$VE" all --entry "the retry helper now lives at loomwright/scripts/no-such-helper-xyz.sh, see #146" \
  --store "$SEPSTORE" --source "$SEP_OK" --root "$REPO_ROOT"
LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" advisory "ADVISORY_CROSS_REPO" "AGGREGATE: an entry violating ONLY cross-repo exits 0 AND prints the advisory" \
  "$VE" all --entry "the same defect was fixed in OTHERSVC #146" \
  --store "$SEPSTORE" --source "$SEP_OK" --root "$REPO_ROOT"
# ...and BOTH at once still exit 0, with both findings named. A writer must not learn about one
# advisory and lose the other because the first one returned.
ve_run "$VE" all --entry "the retry helper now lives at loomwright/scripts/no-such-helper-xyz.sh and landed in octocat/Hello-World, see #146" \
  --store "$SEPSTORE" --source "$SEP_OK" --root "$REPO_ROOT"
{ [ "$VRC" -eq 0 ] \
  && grep -qF "ADVISORY_DEAD_REFERENCE" "$TMP/err.txt" \
  && grep -qF "ADVISORY_CROSS_REPO" "$TMP/err.txt"; } \
  && ok "AGGREGATE: an entry violating BOTH advisory checks exits 0 and reports BOTH — neither finding is swallowed by the other" \
  || no "AGGREGATE: the both-advisories entry gave rc=$VRC and did not report both findings"

# --- the three BLOCKING violations: unchanged, still non-zero -----------------
verdict 1 "AGGREGATE: a DUPLICATE still refuses (1) — the structured checks are untouched" \
  "$VE" all --entry "across every regional cluster release candidates promote through staging validation before production rollout begins" \
  --store "$SEPSTORE" --source "$SEP_OK" --root "$REPO_ROOT"
reason "REFUSE_DUPLICATE" "the duplicate refusal still names itself as a REFUSE_"
verdict 1 "AGGREGATE: a CONTRADICTION still refuses (1)" \
  "$VE" all --entry "release candidates never promote through staging validation before production rollout begins across every regional cluster" \
  --store "$SEPSTORE" --source "$SEP_OK" --root "$REPO_ROOT"
verdict 1 "AGGREGATE: missing PROVENANCE still refuses (1)" \
  "$VE" all --entry "the shared cache layer warms lazily on its very first read" \
  --store "$SEPSTORE" --source "dreaming" --root "$REPO_ROOT"
# Decision (b) survives for the blocking checks: could-not-examine is still 2, still never clean.
: > "$TMP/sep-unreadable.md"; chmod 000 "$TMP/sep-unreadable.md"
if [ -r "$TMP/sep-unreadable.md" ]; then
  ok "SKIPPED the blocking could-not-examine case (running as a user that can read mode-000 files)"
else
  verdict 2 "AGGREGATE: an UNREADABLE store is still could-not-examine (2) — decision (b) is intact where it still applies" \
    "$VE" all --entry "a brand new fact about nothing in particular, see #146" \
    --store "$TMP/sep-unreadable.md" --source "$SEP_OK" --root "$REPO_ROOT"
fi
chmod 644 "$TMP/sep-unreadable.md" 2>/dev/null

# --- the STATIC half: the two advisory functions contain no blocking path ------
# Behavioural assertions cover the inputs this suite thought of. This covers the ones it did not:
# a future edit that adds a `return 1`, or calls a refusal emitter, inside either function.
for fn in validate_dead_reference validate_cross_repo_reference; do
  BODY="$(awk -v f="^$fn\\\\(\\\\) \\\\{$" '$0 ~ f {inf=1} inf {print} inf && /^}$/ {exit}' "$VE")"
  if [ -z "$BODY" ]; then
    no "STATIC: could not extract the body of $fn — this assertion cannot run"
  elif printf '%s\n' "$BODY" | grep -qE '(_ve_refuse|_ve_unexaminable|return [12])'; then
    no "STATIC: $fn contains a blocking path (_ve_refuse / _ve_unexaminable / return 1 / return 2) — it is an ADVISORY check and must return 0 on every path"
  else
    ok "STATIC: $fn contains no refusal emitter and no non-zero return — every path in it reports and returns 0"
  fi
done
# ...and the mirror image: the three blocking checks must NOT have been demoted by accident.
for fn in validate_duplicate validate_contradiction validate_provenance; do
  BODY="$(awk -v f="^$fn\\\\(\\\\) \\\\{$" '$0 ~ f {inf=1} inf {print} inf && /^}$/ {exit}' "$VE")"
  if [ -z "$BODY" ]; then
    no "STATIC: could not extract the body of $fn — this assertion cannot run"
  elif printf '%s\n' "$BODY" | grep -qE '(_ve_refuse|_ve_unexaminable)'; then
    ok "STATIC: $fn still calls a refusal emitter — it is a BLOCKING check and was not demoted with the other two"
  else
    no "STATIC: $fn no longer refuses anything — a blocking check was demoted, which is not what this change did"
  fi
done
# The absorber is not decoration: prove it. Make an advisory check return non-zero and the aggregate
# must STILL exit 0 and say why. Without this, "validate_entry_all does not propagate advisory
# findings" rests entirely on the two functions never regressing.
awk '/^validate_dead_reference\(\) \{$/{print; print "  return 1"; next} {print}' "$VE" > "$TMP/mut-absorb.sh"
if mutated_differs mut-absorb.sh "advisory status absorber"; then
  ve_run "$TMP/mut-absorb.sh" all --entry "a brand new fact about nothing in particular, see #146" \
    --store "$SEPSTORE" --source "$SEP_OK" --root "$REPO_ROOT"
  { [ "$VRC" -eq 0 ] && grep -qF "ADVISORY_INTERNAL_NONZERO" "$TMP/err.txt"; } \
    && ok "ABSORBER: an advisory check returning 1 still leaves the aggregate at 0, and the anomaly is REPORTED by name — the separation does not rest on those two functions staying correct" \
    || no "ABSORBER: a non-zero advisory check moved the aggregate to rc=$VRC (or was absorbed silently) — an advisory finding can block a write again"
fi

echo "== 13. executable dispatch + verdict-code convention =="
verdict 0 "--help prints usage and exits 0" "$VE" --help
verdict 2 "an unknown check exits 2 rather than silently succeeding" "$VE" not-a-check
grep -qE '^VALIDATE_ENTRY_RC_UNEXAMINABLE=2$' "$VE" \
  && ok "the could-not-examine verdict code is a named constant, not an anonymous 2" \
  || no "VALIDATE_ENTRY_RC_UNEXAMINABLE is not declared"
bash -n "$VE" && ok "validate-entry.sh parses cleanly under bash -n" || no "validate-entry.sh has a syntax error"

echo
echo "validate-entry: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
