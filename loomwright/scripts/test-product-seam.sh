#!/usr/bin/env bash
# test-product-seam.sh — STATIC grep self-test over the TWO markdown consumer seams that wire the
# product-context store into `/product-owner`:
#     agents/product-owner.md    §"Context Setup (REQUIRED FIRST)" → 5. **Load Product Context**
#     commands/product-owner.md  (the mirror of that section)
#
# WHY A GREP TEST AND NOT AN EXECUTION TEST. Precedent: test-rules-seams.sh, whose header records
# that a markdown seam "has nothing there to execute and only a grep can assert that the prose still
# hands the reader the right thing". That is exactly the situation here, and this suite adopts BOTH
# halves of that precedent deliberately:
#   - the MESSAGE half — the seam must NAME the missing store and OFFER the bootstrap; and
#   - the INVOCATION-SHAPE half — the seam must call the reader through the plugin-root runtime
#     variable, not through a developer-side repo path.
# Asserting only the message would leave the shape free to rot into something that is broken for
# every marketplace install while the test stayed green.
#
# WHY THE SHAPE HALF IS LOAD-BEARING. `loomwright/scripts/...` is the DEVELOPER-side path — it
# resolves only in a checkout of this repo. Anything invoked at RUNTIME from agent or command prose
# must go through the plugin-root variable, which resolves on both a dev checkout and a marketplace
# install. A seam that hard-codes the developer path is silently dead for every real user, and no
# other gate in this repo looks at it. So (C)/(D) below grep for the FULL invocation INCLUDING that
# prefix, and (G) asserts the developer-side form is absent.
#
# WHY THE MESSAGE HALF IS LOAD-BEARING. The reader (`read-product.sh`) is advisory and fail-safe: on
# an absent store it emits NOTHING on stdout and exits 0. That silence is correct for a reader — it
# must not break or spam its callers — but it means the SEAM is the only thing that can announce the
# absence. A read-path-only store with nobody announcing its absence is precisely how a previous
# store in this repo (`brain-context`) ended up absent, its bridge 255 commits stale, and referenced
# ZERO times across every session log. (E)/(F) are what keep that from recurring quietly.
#
# THE MUTATION CONTROL (the reason this file is not itself a claim no check backs). Every assertion
# below is a grep, and a grep suite can pass for the wrong reason — most obviously if the checks
# never actually discriminate. So PART 2 re-runs the WHOLE assertion set against MUTATED COPIES of
# the seam pair: for each seam file in turn, the absent-store message is deleted, and separately the
# runtime prefix is rewritten to the developer-side path. Each mutant MUST make the suite fail. Each
# mutant is itself gated on being non-empty AND differing from the original before its run is
# trusted — a silently-invalid mutant (an empty file, or a no-op edit) would "fail" the assertions
# for reasons that have nothing to do with the mutation, and would make this control vacuous while
# looking green.
#
# Static-only: no network, no `gh`, no Docker, no jq, and nothing here executes either seam or
# either script. Writes only into a `mktemp -d` scratch dir; the committed seam files are read, never
# modified. Exit 0 = all pass, 1 = any failure (auto-registered by ci.yml's
# `loomwright/scripts/test-*.sh` glob).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HERE/.." && pwd)"

AGENT_SEAM="$PLUGIN_ROOT/agents/product-owner.md"
CMD_SEAM="$PLUGIN_ROOT/commands/product-owner.md"

# ---------------------------------------------------------------------------
# The literals under test. Single-quoted so the plugin-root variable stays a LITERAL string here —
# this suite must compare the characters the seam file contains, never an expansion of them.
# ---------------------------------------------------------------------------
STEP_NAME='**Load Product Context**'
READER_CALL='bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-product.sh"'
BOOTSTRAP_CALL='bash "${CLAUDE_PLUGIN_ROOT}/scripts/propose-product.sh"'
ABSENT_MSG='**No product context: `.agent/product.json` is absent.**'
NEVER_QUIET='NEVER skip quietly'
DEV_READER_PATH='loomwright/scripts/read-product.sh'
DEV_BOOTSTRAP_PATH='loomwright/scripts/propose-product.sh'

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

# ---------------------------------------------------------------------------
# check_pair <agent_seam> <cmd_seam> <verbose 0|1>
#   Returns 0 when EVERY assertion holds over the given pair, 1 otherwise. In verbose mode it also
#   reports each assertion through ok()/no() and updates the global counters; in quiet mode it is
#   silent and touches no counter, so a mutant run cannot pollute the real tally.
#   The whole assertion set lives in this ONE function precisely so PART 2 re-runs the SAME checks
#   the committed files are held to — a separate, weaker copy for the mutants would prove nothing.
# ---------------------------------------------------------------------------
check_pair() {
  local agent="$1" cmd="$2" verbose="$3"
  local rc=0 f base

  _chk() {  # _chk <ok 0|1> <label>
    if [ "$1" -eq 0 ]; then
      [ "$verbose" -eq 1 ] && ok "$2"
    else
      [ "$verbose" -eq 1 ] && no "$2"
      rc=1
    fi
    return 0
  }

  for f in "$agent" "$cmd"; do
    base="$(basename "$(dirname "$f")")/$(basename "$f")"

    # (A) the seam surface exists and is non-empty
    if [ ! -s "$f" ]; then
      _chk 1 "[$base] MISSING or EMPTY seam surface ($f)"
      continue
    fi
    _chk 0 "[$base] seam surface exists"

    # (B) the step exists, in the numbered-bold "Product Owner-Specific Additions" convention
    grep -qF "$STEP_NAME" "$f"
    _chk $? "[$base] carries the $STEP_NAME step"

    # (C) INVOCATION SHAPE — the reader is invoked through the plugin-root RUNTIME variable
    grep -qF "$READER_CALL" "$f"
    _chk $? "[$base] invokes the reader as $READER_CALL"

    # (D) INVOCATION SHAPE — the bootstrap is OFFERED, through the same runtime variable
    grep -qF "$BOOTSTRAP_CALL" "$f"
    _chk $? "[$base] offers the bootstrap as $BOOTSTRAP_CALL"

    # (E) THE MESSAGE — the absent case is named, and it names the store by path
    grep -qF "$ABSENT_MSG" "$f"
    _chk $? "[$base] names the absent store: $ABSENT_MSG"

    # (F) THE MESSAGE — and is explicit that absence is never passed over in silence
    grep -qF "$NEVER_QUIET" "$f"
    _chk $? "[$base] states '$NEVER_QUIET' for the absent case"

    # (G) NEGATIVE — no developer-side path for either script. A `loomwright/scripts/...`
    #     invocation in runtime prose resolves only in a checkout of this repo.
    if grep -qF "$DEV_READER_PATH" "$f" || grep -qF "$DEV_BOOTSTRAP_PATH" "$f"; then
      _chk 1 "[$base] uses a DEVELOPER-SIDE path (loomwright/scripts/...) — broken for marketplace installs"
    else
      _chk 0 "[$base] uses no developer-side loomwright/scripts/... path"
    fi
  done

  # (H) CROSS-FILE — agent and command must carry the SAME message, byte for byte. Agent↔command
  #     mirror drift passes every other gate in this repo (check-command-sync.sh does not cover
  #     prose), so the two copies are compared directly rather than each merely "containing
  #     something about the store".
  local a_line c_line
  a_line="$(grep -F "$ABSENT_MSG" "$agent" 2>/dev/null | head -1)"
  c_line="$(grep -F "$ABSENT_MSG" "$cmd" 2>/dev/null | head -1)"
  if [ -n "$a_line" ] && [ "$a_line" = "$c_line" ]; then
    _chk 0 "[cross-file] the absent-store message is byte-identical in both seams"
  else
    _chk 1 "[cross-file] the absent-store message DIFFERS between agents/ and commands/ (mirror drift)"
  fi

  return "$rc"
}

echo "== PART 1: the committed seam pair =="
check_pair "$AGENT_SEAM" "$CMD_SEAM" 1
part1_rc=$?
if [ "$part1_rc" -eq 0 ]; then
  echo "  (part 1 clean)"
else
  echo "  (part 1 had failures — see above)"
fi

# ---------------------------------------------------------------------------
# PART 2 — MUTATION CONTROL (AC6).
#
# mutate_and_expect_fail <label> <which: agent|cmd> <sed_program>
#   Copies BOTH seam files into a fresh scratch dir, applies <sed_program> to ONE of them, then:
#     GATE 1  the mutant must be NON-EMPTY      (an empty file fails every grep for free)
#     GATE 2  the mutant must DIFFER from the original (a no-op sed proves nothing)
#   and only then runs the full assertion set (quietly) over the mutated PAIR, requiring it to FAIL.
#   Both gates are hard preconditions: if either is unmet the case is reported as a FAILURE of this
#   control rather than silently counted as a pass, because an ungated mutant makes the control
#   vacuous while still printing "ok".
# ---------------------------------------------------------------------------
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH" 2>/dev/null' EXIT

mutate_and_expect_fail() {
  local label="$1" which="$2" sed_prog="$3"
  local d target orig
  d="$(mktemp -d "$SCRATCH/m.XXXXXX")" || { no "[mutation] $label — could not allocate a scratch dir"; return; }
  cp "$AGENT_SEAM" "$d/agent.md" || { no "[mutation] $label — could not copy the agent seam"; return; }
  cp "$CMD_SEAM"   "$d/cmd.md"   || { no "[mutation] $label — could not copy the command seam"; return; }

  case "$which" in
    agent) target="$d/agent.md"; orig="$AGENT_SEAM" ;;
    cmd)   target="$d/cmd.md";   orig="$CMD_SEAM" ;;
    *)     no "[mutation] $label — unknown target '$which'"; return ;;
  esac

  sed -E "$sed_prog" "$target" > "$target.new" 2>/dev/null || {
    no "[mutation] $label — sed failed to produce a mutant"; return; }
  mv -f "$target.new" "$target"

  # GATE 1 — non-empty.
  if [ ! -s "$target" ]; then
    no "[mutation] $label — INVALID MUTANT: the mutated file is empty, so a failure would prove nothing"
    return
  fi
  # GATE 2 — actually different from the committed original.
  if cmp -s "$target" "$orig"; then
    no "[mutation] $label — INVALID MUTANT: the mutated file is IDENTICAL to the original, so the mutation did not apply (this control would have been vacuous)"
    return
  fi

  if check_pair "$d/agent.md" "$d/cmd.md" 0; then
    no "[mutation] $label — the suite PASSED against the mutant; the assertions do not discriminate"
  else
    ok "[mutation] $label — the mutant is caught (suite fails, as required)"
  fi
}

echo
echo "== PART 2: mutation control — each mutant MUST make PART 1's assertions fail =="

# M1/M2 — delete the absent-store message (AC6's named mutation: "delete the message from either
# seam file and the test must fail"), once per seam file.
MSG_DELETE='/No product context: `\.agent\/product\.json` is absent\./d'
mutate_and_expect_fail "agents/product-owner.md — absent-store message deleted" agent "$MSG_DELETE"
mutate_and_expect_fail "commands/product-owner.md — absent-store message deleted" cmd "$MSG_DELETE"

# M3/M4 — rewrite the runtime plugin-root prefix to the developer-side repo path. This is the OTHER
# half of the precedent: the message can survive intact while the invocation silently becomes one
# that resolves in nobody's install but a maintainer's checkout.
SHAPE_BREAK='s|\$\{CLAUDE_PLUGIN_ROOT\}/scripts/|loomwright/scripts/|g'
mutate_and_expect_fail "agents/product-owner.md — runtime prefix replaced by a developer-side path" agent "$SHAPE_BREAK"
mutate_and_expect_fail "commands/product-owner.md — runtime prefix replaced by a developer-side path" cmd "$SHAPE_BREAK"

# M5 — drop the bootstrap OFFER while leaving the message and the reader call intact. Naming the
# missing store without saying how to create it is the half-fix this seam exists to prevent.
OFFER_DELETE='/scripts\/propose-product\.sh/d'
mutate_and_expect_fail "agents/product-owner.md — bootstrap offer deleted" agent "$OFFER_DELETE"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
