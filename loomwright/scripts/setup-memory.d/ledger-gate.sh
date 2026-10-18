# ---- the findings-ledger gate (fails closed in the WRITE dimension, never in the exit status) --
#
# LEDGER_GATE_STATE ∈ { "" (unevaluated), pass, refuse, not-evaluated }
#   pass          — every record's `.repo` is inside the resolved allowlist (or there is no ledger)
#   refuse        — the negation may NOT be EMITTED. Two DISJOINT causes, carried in two SEPARATE
#                   channels because they justify OPPOSITE things (see the asymmetry below):
#                     $LEDGER_FOREIGN_SLUGS      — REAL, EXAMINED foreign `.repo` values
#                     $LEDGER_UNEXAMINED_REASON  — could-not-examine reasons (unreadable ledger,
#                                                  unparseable records). NOT slugs, NEVER printed
#                                                  as if they were, and NEVER remedied by
#                                                  `filter-ledger` (which on an unreadable ledger
#                                                  would truncate it to zero bytes).
#   not-evaluated — jq is absent OR non-functional, so NOTHING was probed at all
#
# THE EMIT/WITHDRAW ASYMMETRY (the whole point of the two channels).
#   EMITTING a NEW negation requires an affirmative `pass` — examined AND clean. Never publish
#   something unverified.
#   WITHDRAWING an EXISTING negation requires an affirmative `refuse` backed by REAL, EXAMINED
#   foreign slugs. A could-not-examine state PRESERVES whatever is already in the block.
# Why they differ: a withdrawal is an UNREQUESTED STATE CHANGE justified by a diagnosis we did not
# actually make. Preserving publishes nothing new — the ledger is already un-ignored and possibly
# already committed, and `.gitignore` does not untrack tracked files — whereas withdrawing emits a
# FALSE contamination message naming slugs that do not exist, and silently re-ignores a ledger the
# user deliberately un-ignored, merely because `jq` broke.
LEDGER_GATE_STATE=""
LEDGER_FOREIGN_SLUGS=""
LEDGER_UNEXAMINED_REASON=""

# ONE jq PROGRAM, TWO CALLERS (the whole-file pass and the per-line fallback) so they cannot drift.
# It prints ONE LINE PER OFFENDING RECORD — the record's `.repo`, or a placeholder for an
# unattributable one. A record whose `.repo` IS allowlisted prints nothing.
#
# jq, NEVER grep. This ledger mixes compact (`"repo":"x"`) and spaced (`"repo": "x"`) JSON, so a
# compact-form grep under-counts silently AND a foreign record appended in the spaced form evades
# it entirely — which would make this gate a guard that cannot fire. Pinned by
# test-setup-memory.sh's test_gate_blocks_foreign_spaced_form.
LEDGER_GATE_JQ='((.repo // "") | tostring) as $r
  | select(($allow | index($r)) == null)
  | (if $r == "" then "(record with no .repo field)" else $r end)'

_evaluate_ledger_gate() {
  local ledger="$repo/$LEDGER_INTENDED_PATH"
  LEDGER_FOREIGN_SLUGS=""
  LEDGER_UNEXAMINED_REASON=""

  # jq ABSENT **OR BROKEN** ⇒ the gate is NOT EVALUATED. It must NOT fail toward `refuse` (that
  # would permanently mis-report for every jq-less user) and must NOT fail toward emitting the
  # negation (that would publish an unchecked ledger). Nothing is probed and the pre-existing
  # verdict — and the pre-existing negation — are preserved, mirroring the seed_allowlist /
  # filter_ledger_by_allowlist skip-with-message guards.
  #
  # `command -v jq` tests PRESENCE, NOT FUNCTION, and that gap was reachable and destructive: a jq
  # on PATH that exits non-zero (wrong arch, broken install, a shim) makes the whole-file pass fail
  # AND every per-line probe fail, so a perfectly CLEAN ledger was counted entirely unparseable and
  # the gate REFUSED — reporting contamination it never observed and withdrawing a good negation.
  # So probe that jq actually WORKS, and treat a broken jq exactly like an absent one.
  if ! command -v jq >/dev/null 2>&1 || ! printf '{}' | jq -e . >/dev/null 2>&1; then
    LEDGER_GATE_STATE="not-evaluated"
    LEDGER_UNEXAMINED_REASON="jq is unavailable (absent or non-functional) — nothing was examined"
    return 0
  fi
  # Ledger ABSENT ⇒ PASS. No records ⇒ no foreign records ⇒ nothing to withhold. This is the state
  # of every fresh user repo and of every fixture in the test suites.
  if [ ! -f "$ledger" ]; then
    LEDGER_GATE_STATE="pass"
    return 0
  fi

  local entries allow_json out rc line one orc n=0 unexamined=""
  entries="$(resolve_allowlist)"
  if [ -n "$entries" ]; then
    allow_json="$(printf '%s\n' "$entries" | jq -R . | jq -s .)" || allow_json='[]'
  else
    # An EMPTY allowlist retains NOTHING (filter_ledger_by_allowlist's rule), so EVERY record is
    # outside it and the gate refuses. Fail-closed, never "nothing configured ⇒ everything is fine".
    allow_json='[]'
  fi

  out="$(jq -r --argjson allow "$allow_json" "$LEDGER_GATE_JQ" "$ledger" 2>/dev/null)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    # A malformed line aborts the whole-file pass. Fall back per line and count an UNPARSEABLE
    # record as FOREIGN: a record that cannot be parsed cannot be SHOWN to belong to this repo, and
    # the cost of publishing another repo's record is higher than the cost of withholding one.
    out=""
    # `|| [ -n "$line" ]` — a TRUNCATED final line (no trailing newline) is exactly the malformed
    # record that lands us in this fallback, and a bare `while read` DROPS it: `read` returns
    # non-zero at EOF even though it filled $line, so the body never runs for it and the record is
    # silently never examined. One interrupted `/pr-postmortem` append is enough.
    while IFS= read -r line || [ -n "$line" ]; do
      n=$((n + 1))
      [ -n "$line" ] || continue
      one="$(printf '%s' "$line" | jq -r --argjson allow "$allow_json" "$LEDGER_GATE_JQ" 2>/dev/null)"
      orc=$?
      if [ "$orc" -ne 0 ]; then
        # COULD-NOT-EXAMINE, not a slug. It blocks EMISSION (below) exactly as before, but it must
        # never masquerade as an observed foreign `.repo`: naming it as one would make the warning
        # claim contamination we never saw, and would hand the user the `filter-ledger` remedy for
        # a record that cannot be parsed.
        unexamined="${unexamined}(unparseable record at ledger line $n)
"
      elif [ -n "$one" ]; then
        out="${out}${one}
"
      fi
    done < "$ledger"
    # NOTHING WAS EXAMINED. The whole-file pass failed AND the fallback never iterated — an
    # UNREADABLE ledger (`chmod 000`: `[ -f ]` is true, jq cannot open it, and the `done < "$ledger"`
    # redirect itself fails) leaves $n at 0 with $out empty. Empty output would otherwise read as
    # "examined every record and found none foreign", which is the fail-OPEN this marker closes: a
    # record that cannot be SHOWN to belong to this repo must not be published, and one that could
    # not be read at all is the strongest case of that.
    if [ "$n" -eq 0 ]; then
      unexamined="(ledger could not be read at all — nothing was examined)
"
    fi
  fi

  LEDGER_FOREIGN_SLUGS="$(printf '%s\n' "$out" | awk 'NF && !seen[$0]++')"
  LEDGER_UNEXAMINED_REASON="$(printf '%s\n' "$unexamined" | awk 'NF && !seen[$0]++')"
  # EITHER channel blocks EMISSION — that is the fail-closed rule this gate exists for, and it is
  # unchanged. Only the FOREIGN-SLUG channel additionally licenses a WITHDRAWAL.
  if [ -n "$LEDGER_FOREIGN_SLUGS" ] || [ -n "$LEDGER_UNEXAMINED_REASON" ]; then
    LEDGER_GATE_STATE="refuse"
  else
    LEDGER_GATE_STATE="pass"
  fi
}

# ledger_gate_blocks_foreign_records → status 0 when the gate REFUSES (the ledger holds at least one
# record outside the allowlist, so the negation must be WITHHELD), 1 otherwise.
#
# Memoized per process. `managed_block()` is reached through TWO nested command substitutions on the
# apply path, so globals set inside them are discarded and the evaluation simply repeats there. That
# is safe ONLY because the evaluation is deterministic and side-effect-free — the result may never
# depend on call ORDER, and this function must never write anything.
ledger_gate_blocks_foreign_records() {
  [ -n "$LEDGER_GATE_STATE" ] || _evaluate_ledger_gate
  [ "$LEDGER_GATE_STATE" = "refuse" ]
}

# ledger_gate_permits_negation → status 0 when the ledger negation may be EMITTED and PROBED.
# ONLY `pass` permits it: `refuse` withholds it, and `not-evaluated` withholds it too (nothing was
# checked, so emitting would publish an unverified ledger).
ledger_gate_permits_negation() {
  [ -n "$LEDGER_GATE_STATE" ] || _evaluate_ledger_gate
  [ "$LEDGER_GATE_STATE" = "pass" ]
}

# ledger_gate_warrants_withdrawal → status 0 ONLY when the gate EXAMINED the ledger and found REAL
# foreign `.repo` values. This — not `refuse` — is what licenses REMOVING a negation that is already
# in the file, and what licenses the "these repo slugs appeared" copy. A could-not-examine refusal
# returns 1: it still blocks EMISSION, it just may not withdraw or accuse.
ledger_gate_warrants_withdrawal() {
  [ -n "$LEDGER_GATE_STATE" ] || _evaluate_ledger_gate
  [ "$LEDGER_GATE_STATE" = "refuse" ] && [ -n "$LEDGER_FOREIGN_SLUGS" ]
}

# existing_ledger_negation_present → status 0 when the .gitignore ON DISK already carries the ledger
# negation INSIDE the managed block. Whole-line compare (never a substring), and scoped to the block
# so a stray hand-added copy outside it is not mistaken for this module's own emission.
# negation_line_in_block <content> — true when the ledger negation appears as a WHOLE LINE inside the
# managed block of the given content. Anchored on purpose: the block's own comment quotes the rule
# verbatim, so a substring test cannot tell the explanation from the rule.
negation_line_in_block() {
  printf '%s\n' "$1" | awk -v b="$MB_BEGIN" -v e="$MB_END" -v n="!$LEDGER_INTENDED_PATH" '
    index($0, b) > 0 { inblk = 1; next }
    inblk && index($0, e) > 0 { inblk = 0; next }
    inblk && $0 == n { found = 1 }
    END { exit(found ? 0 : 1) }
  '
}

existing_ledger_negation_present() {
  # Delegates to negation_line_in_block — ONE implementation of "the negation is present as a whole
  # line inside the managed block". Two copies of this predicate is the exact inconsistency the
  # anchoring change existed to remove; keeping a second awk here (differing only in that it re-read
  # $GI itself) would have re-created it one level down, where a later edit could drift them apart
  # silently. This wrapper is just "the same question, asked of the file on disk".
  [ -f "$GI" ] || return 1
  negation_line_in_block "$(cat "$GI" 2>/dev/null)"
}

# ledger_negation_in_block → status 0 when the REGENERATED managed block will carry the negation.
# THE ASYMMETRY, in one place, consumed by managed_block() and by every report/headline branch so
# they cannot disagree about what was written:
#   pass                         → EMIT (examined and clean)
#   refuse WITH real slugs       → WITHDRAW (examined; we saw the contamination)
#   anything else                → PRESERVE whatever is already there (could not examine)
ledger_negation_in_block() {
  # Branch mode: the ledger lives on the metadata branch, so the block never carries its negation.
  [ -n "${EFFECTIVE_BRANCH:-}" ] && return 1
  ledger_gate_permits_negation && return 0
  ledger_gate_warrants_withdrawal && return 1
  existing_ledger_negation_present
}
