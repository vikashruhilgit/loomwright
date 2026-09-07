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
# WHY THERE IS A THIRD, NEGATIVE HALF. Both of the above are PREFIX greps — they match a correct
# invocation with anything appended to it. That is how a pre-filled `--stance product` shipped in
# the offered bootstrap while every assertion here stayed green. (I) closes that hole by pinning the
# WHOLE offered line, because `stance` is the one field the design refuses to guess.
#
# WHY (I) IS NOT ENOUGH ON ITS OWN — AND WHY (H)/(J) EXIST IN THEIR CURRENT FORM. Fixing the
# pre-filled-stance defect moved the stance DECISION off the offered command line and into the PROSE
# of the same blockquote ("pick it yourself and re-run with `--stance product` or `--stance tool`").
# (I) guards the line the defect happened to live on; it says nothing about the sentence that now
# carries the decision. Two mutations proved that gap live: narrowing the prose to a single enum value
# in BOTH mirrors re-introduces exactly the original defect (a seam that hands the user a stance
# instead of naming it as their decision), and editing any non-message line of the blockquote in ONE
# mirror drifts the pair — both used to stay green. So the guard is now on the DECISION, not on the
# surface: (H) compares the ENTIRE offer blockquote byte-for-byte across the two mirrors, and (J)
# positively requires BOTH enum values to be named in it. M8/M9 in PART 2 are those two mutations.
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
# (J) — the TWO stance enum values the prose must hand back to the user as THEIR decision. Both must
# be named; naming only one is the pre-filled-stance defect wearing prose instead of an argument.
STANCE_ENUM_PRODUCT='`--stance product`'
STANCE_ENUM_TOOL='`--stance tool`'

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

# ---------------------------------------------------------------------------
# offer_block <file> — print the WHOLE offer blockquote: the maximal run of consecutive markdown
#   blockquote lines (`^[[:space:]]*>`) that contains $ABSENT_MSG. Located by CONTENT, never by line
#   number, so an insertion anywhere above it cannot silently move the assertion off its subject.
#   Prints nothing when no such run exists — callers treat empty as a FAILURE, never as a pass.
# ---------------------------------------------------------------------------
offer_block() {
  awk -v msg="$ABSENT_MSG" '
    /^[[:space:]]*>/ { buf = buf $0 "\n"; if (index($0, msg)) hit = 1; next }
    { if (hit) { printf "%s", buf; exit } buf = ""; hit = 0 }
    END { if (hit) printf "%s", buf }
  ' "$1" 2>/dev/null
}

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

    # (I) NEGATIVE — the OFFERED bootstrap command must carry NO ARGUMENTS, and above all no
    #     pre-filled `--stance <value>`.
    #
    #     WHY THIS IS NOT A STYLE RULE. `stance` is the ONE field the design refuses to guess: it
    #     decides the DEFAULT ACTION on a discovered gap (`product` => build-highest-priority,
    #     `tool` => do-not-build-by-default) and no signal in a repo distinguishes the two, so a
    #     fixed default would tell a payments app to skip its missing fraud checks. Worse, a
    #     pre-filled in-enum value SUPPRESSES THE SCRIPT'S OWN SAFEGUARD: it sets `stance_ok=1`, so
    #     propose-product.sh's dry-run `BLOCKED: --stance is REQUIRED ... and is never guessed`
    #     branch never prints, and a user who pastes the offered line is handed a decision without
    #     ever being told one was made. This repo is its own counter-example — Loomwright is a
    #     `tool`, and a seam pre-filling `product` would hand it the wrong answer here.
    #
    #     WHY (D) CANNOT CATCH IT. (D) greps the invocation as a PREFIX, so it matches just as well
    #     with any argument appended. Only an assertion on the WHOLE line discriminates, which is
    #     what this does: strip the markdown blockquote/indent prefix and require what remains to be
    #     EXACTLY $BOOTSTRAP_CALL.
    #
    #     WHY THE SET IS RESTRICTED TO FENCED COMMAND LINES. The subject of this assertion is the
    #     line the user is meant to PASTE, not every place the invocation is spelled. A legitimate
    #     prose mention inside a sentence (`See \`bash ".../propose-product.sh"\` for the bootstrap.`)
    #     is not a pre-filled stance, but an unrestricted grep hands it to the exact-match comparison
    #     and the suite then fails with the WRONG DIAGNOSIS — accusing the seam of pre-deciding
    #     stance when nothing of the kind happened. `^[[:space:]>]*bash ` keeps only lines that ARE
    #     the command (fenced, optionally blockquoted/indented) and drops prose that merely quotes it;
    #     M6/M7 below prove the restriction did not cost the assertion its discriminating power.
    local offers extra
    offers="$(grep -F "$BOOTSTRAP_CALL" "$f" 2>/dev/null | grep -E '^[[:space:]>]*bash ' | sed -E 's/^[[:space:]>]*//')"
    if [ -z "$offers" ]; then
      # (D) matched somewhere, but nowhere as a runnable command line — or (D) failed outright.
      # Either way this is a failure, not a vacuous pass over an empty set.
      _chk 1 "[$base] no FENCED bootstrap command line to check for a pre-filled --stance (the invocation is absent, or appears only inside prose — see (D))"
    else
      # `grep -v` consumes all of its input, so there is no early-close SIGPIPE to confuse the
      # status; `|| true` is safe because the emptiness of $extra IS the assertion.
      extra="$(printf '%s\n' "$offers" | grep -vxF "$BOOTSTRAP_CALL" || true)"
      if [ -n "$extra" ]; then
        _chk 1 "[$base] the offered bootstrap carries ARGUMENTS — stance must not be pre-decided for the user: $extra"
      else
        _chk 0 "[$base] offers the bootstrap bare, with no pre-filled --stance value"
      fi
    fi

    # (J) POSITIVE — the offer blockquote must name BOTH stance enum values.
    #
    #     (I) is a NEGATIVE assertion: it forbids a stance on the offered command line. Satisfying it
    #     is not the same as doing the right thing, and the fix for the original defect proved that —
    #     the decision simply moved into the prose one line below, where nothing asserted it. Deleting
    #     ` or \`--stance tool\`` from that sentence leaves (A)-(I) untouched and green while the seam
    #     goes back to handing the user ONE stance instead of naming the choice as theirs.
    #
    #     So this pins the DECISION rather than the surface it currently sits on: whatever the prose
    #     says, BOTH enum values must appear inside the offer blockquote. One without the other is a
    #     pre-decided stance no matter which line it is written on. Scoped to the blockquote (not the
    #     whole file) so the assertion's subject is the text the user is actually shown at the moment
    #     of the decision. M8 is the mutation control for this.
    local block
    block="$(offer_block "$f")"
    if [ -z "$block" ]; then
      _chk 1 "[$base] no offer blockquote containing the absent-store message — cannot check the stance enum (see (E))"
    elif printf '%s' "$block" | grep -qF -- "$STANCE_ENUM_PRODUCT" \
      && printf '%s' "$block" | grep -qF -- "$STANCE_ENUM_TOOL"; then
      _chk 0 "[$base] the offer names BOTH stance values ($STANCE_ENUM_PRODUCT and $STANCE_ENUM_TOOL) — the choice is left to the user"
    else
      _chk 1 "[$base] the offer does NOT name both stance values — one of $STANCE_ENUM_PRODUCT / $STANCE_ENUM_TOOL is missing, so a stance is being pre-decided in prose"
    fi
  done

  # (H) CROSS-FILE — agent and command must carry the SAME OFFER, byte for byte, over the WHOLE
  #     blockquote. Agent↔command mirror drift passes every other gate in this repo
  #     (check-command-sync.sh does not cover prose), so the two copies are compared directly rather
  #     than each merely "containing something about the store".
  #
  #     WHY THE WHOLE BLOCK AND NOT JUST THE MESSAGE LINE. This used to compare only the
  #     $ABSENT_MSG line. That covers the first line of a seven-line block: the offered command, the
  #     "run it bare" instruction, the explanation of what `--stance` decides and the enumeration of
  #     its two values were ALL free to drift between the mirrors with the suite green — and the
  #     stance decision now lives in exactly that unasserted remainder. Comparing the whole block
  #     means any divergence anywhere in the offer fails, whichever line it lands on.
  #
  #     Both blocks must also be NON-EMPTY: two files that each lack the offer entirely would compare
  #     equal, and an "identical absence" is not a passing mirror.
  local a_block c_block
  a_block="$(offer_block "$agent")"
  c_block="$(offer_block "$cmd")"
  if [ -z "$a_block" ] || [ -z "$c_block" ]; then
    _chk 1 "[cross-file] the offer blockquote is MISSING from at least one seam (agent empty: $([ -z "$a_block" ] && echo yes || echo no), command empty: $([ -z "$c_block" ] && echo yes || echo no))"
  elif [ "$a_block" = "$c_block" ]; then
    _chk 0 "[cross-file] the ENTIRE offer blockquote is byte-identical in both seams"
  else
    _chk 1 "[cross-file] the offer blockquote DIFFERS between agents/ and commands/ (mirror drift somewhere in the offer, not necessarily the message line)"
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

  # `both` mutates the PAIR identically — the only way to exercise an assertion whose subject is the
  # content itself rather than the agreement between the mirrors. A single-file mutation of the offer
  # prose is always caught by (H) first, which would make (J) look guarded when it is not.
  local targets origs i
  case "$which" in
    agent) targets=("$d/agent.md");               origs=("$AGENT_SEAM") ;;
    cmd)   targets=("$d/cmd.md");                 origs=("$CMD_SEAM") ;;
    both)  targets=("$d/agent.md" "$d/cmd.md");   origs=("$AGENT_SEAM" "$CMD_SEAM") ;;
    *)     no "[mutation] $label — unknown target '$which'"; return ;;
  esac

  for i in "${!targets[@]}"; do
    target="${targets[$i]}"; orig="${origs[$i]}"

    sed -E "$sed_prog" "$target" > "$target.new" 2>/dev/null || {
      no "[mutation] $label — sed failed to produce a mutant ($(basename "$target"))"; return; }
    mv -f "$target.new" "$target"

    # GATE 1 — non-empty.
    if [ ! -s "$target" ]; then
      no "[mutation] $label — INVALID MUTANT ($(basename "$target")): the mutated file is empty, so a failure would prove nothing"
      return
    fi
    # GATE 2 — actually different from the committed original.
    if cmp -s "$target" "$orig"; then
      no "[mutation] $label — INVALID MUTANT ($(basename "$target")): the mutated file is IDENTICAL to the original, so the mutation did not apply (this control would have been vacuous)"
      return
    fi
  done

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

# M6/M7 — re-add a pre-filled `--stance product` to the offered command. This is the exact defect
# (I) exists for, and the exact defect that (D)'s prefix grep waves through: the message, the shape
# and the developer-path checks all still pass, so without (I) the suite would go green on a seam
# that hands the user an unmade decision AND silences the script's own explanation of it.
STANCE_PREFILL='s|(scripts/propose-product\.sh")$|\1 --stance product|'
mutate_and_expect_fail "agents/product-owner.md — a concrete --stance value pre-filled into the offer" agent "$STANCE_PREFILL"
mutate_and_expect_fail "commands/product-owner.md — a concrete --stance value pre-filled into the offer" cmd "$STANCE_PREFILL"

# M8 — narrow the offer prose from BOTH stance values to just `--stance product`, in BOTH mirrors at
# once. This is the original pre-filled-stance defect in its post-fix disguise: the offered command
# line is still bare (so (I) is satisfied) and the mirrors still agree (so (H) is satisfied), yet the
# seam once again hands the user a stance instead of naming it as their decision. It is mutated in
# both files deliberately — a one-file version would be caught by (H) and would prove nothing about
# (J). Only (J) discriminates here.
STANCE_NARROW='s/ or `--stance tool`//'
mutate_and_expect_fail "BOTH seams — the offer prose narrowed to a single stance value" both "$STANCE_NARROW"

# M9 — drift ONE non-message line of the offer blockquote in ONE mirror. Nothing about the absent-
# store message changes, so the old message-line-only form of (H) waved this through: the offered
# command, the "run it bare" instruction and the whole stance explanation could diverge between agent
# and command with the suite green. The whole-block form of (H) is what catches it.
OFFER_LINE_DRIFT='s/Run it bare, exactly as written\./Run it bare./'
mutate_and_expect_fail "agents/product-owner.md — a non-message line of the offer drifts from the mirror" agent "$OFFER_LINE_DRIFT"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
