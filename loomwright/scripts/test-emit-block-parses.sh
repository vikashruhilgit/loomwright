#!/usr/bin/env bash
# Self-test for eval-corpus/emit-block-parses/check.sh.
# Auto-run by CI's test-*.sh loop. Deterministic, no network, no repo writes
# (fixtures live in mktemp -d).
#
# WHY THIS EXISTS: the task's spec.md documents a mutation table (M0-M5). A
# documented mutation table that nothing runs is a claim no check backs — the
# exact failure class this repo has been bitten by. These are those mutations,
# executed. M4 and M5 matter as much as M1/M2: M4 pins that the oracle checks
# parseability and not house style, M5 pins that a broken extractor fails loudly
# instead of passing vacuously.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
CHECK="$REPO_ROOT/loomwright/scripts/eval-corpus/emit-block-parses/check.sh"
[ -f "$CHECK" ] || { echo "FAIL: check not found at $CHECK" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 unavailable" >&2; exit 0; }

pass=0; total=0
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT

seed() { # rebuild a pristine fixture tree
  rm -rf "$FIX/t"
  mkdir -p "$FIX/t/scripts" "$FIX/t/loomwright/agents" "$FIX/t/loomwright/scripts"
  cp "$REPO_ROOT/scripts/check-contract-parity.sh" "$FIX/t/scripts/"
  cp "$REPO_ROOT"/loomwright/agents/*.md "$FIX/t/loomwright/agents/"
  cp "$REPO_ROOT/loomwright/scripts/result_block_parser.py" "$FIX/t/loomwright/scripts/"
}

expect() { # $1 desc, $2 wanted exit (0 pass | 1 fail)
  local desc="$1" want="$2" got=0
  total=$((total+1))
  bash "$CHECK" --root "$FIX/t" >/dev/null 2>&1 || got=$?
  if { [ "$want" -eq 0 ] && [ "$got" -eq 0 ]; } || { [ "$want" -eq 1 ] && [ "$got" -ne 0 ]; }; then
    echo "ok    $desc"; pass=$((pass+1))
  else
    echo "FAIL  $desc (exit $got, wanted $want)"
  fi
}

# The block-sequence form the requires-gap template currently uses. Kept as the
# single literal both M1 and M4 rewrite, so a future re-styling of the template
# breaks this test loudly (assert_sub below) instead of silently disarming it.
BLOCK_FORM='  adjudication_options:                 # block sequence — see the wrapping note above
    - "A: Re-queue producer"
    - "B: Insert remediation subtask"
    - "C: Exit to Launch Pad"
    - "D: Update consumer brief"'

# Substitute exactly one occurrence of $2 with $3 in file $1; hard-fail if the
# anchor is absent or ambiguous (a silently-skipped mutation would make the
# assertion that follows it vacuous).
assert_sub() {
  python3 - "$1" "$2" "$3" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path).read()
n = s.count(old)
if n != 1:
    sys.stderr.write("MUTATION ANCHOR NOT UNIQUE (%d occurrences) in %s\n" % (n, path))
    sys.exit(1)
open(path, "w").write(s.replace(old, new))
PY
}

EM() { echo "$FIX/t/loomwright/agents/execute-manager.md"; }

# ── M0: unmutated tree passes ────────────────────────────────────────────────
seed
expect "M0 unmutated fixture passes" 0

# ── M1: a flow sequence wrapped onto a second line is rejected ───────────────
seed
if assert_sub "$(EM)" "$BLOCK_FORM" '  adjudication_options: ["A: Re-queue producer", "B: Insert remediation subtask",
                         "C: Exit to Launch Pad", "D: Update consumer brief"]'; then
  expect "M1 wrapped flow sequence is rejected" 1
else
  total=$((total+1)); echo "FAIL  M1 anchor missing — template restyled without updating this test"
fi

# ── M2: a block scalar (>-) is rejected ─────────────────────────────────────
seed
if assert_sub "$(EM)" \
  '  reason: "Lane collision: {subtask_id} wrote {N} path(s) inside the declared lane(s) of sibling(s) {owning_subtasks}, none reachable in either direction over the requires DAG. See colliding_lanes[] for the full set."' \
  '  reason: >-
    Lane collision: {subtask_id} wrote {N} path(s) inside the declared
    lane(s) of sibling(s) {owning_subtasks}. See colliding_lanes[].'; then
  expect "M2 block scalar (>-) is rejected" 1
else
  total=$((total+1)); echo "FAIL  M2 anchor missing — template restyled without updating this test"
fi

# ── M4: a SINGLE-LINE flow sequence is accepted (style is not the oracle) ────
seed
if assert_sub "$(EM)" "$BLOCK_FORM" '  adjudication_options: ["A: Re-queue producer", "B: Insert remediation subtask", "C: Exit to Launch Pad", "D: Update consumer brief"]'; then
  expect "M4 single-line flow sequence is accepted (not a style gate)" 0
else
  total=$((total+1)); echo "FAIL  M4 anchor missing — template restyled without updating this test"
fi

# ── M5: extraction finding nothing fails loudly, never vacuously green ───────
seed
python3 - "$FIX/t/loomwright/agents" <<'PY'
import glob, os, re, sys
blocks = ("WORKER_RESULT", "EXECUTE_RESULT", "EXECUTE_CHECKPOINT", "QA_RESULT",
          "SUPERVISOR_RESULT", "PLAN_REVIEW_RESULT", "CODE_REVIEW_RESULT")
alt = "|".join(blocks)
touched = 0
for path in glob.glob(os.path.join(sys.argv[1], "*.md")):
    s = open(path).read()
    out = re.sub(r"^(\s*)(%s):\s*$" % alt, r"\1ZZZ_\2_ZZZ:", s, flags=re.M)
    out = re.sub(r"^(#+\s+)(%s)\s*$" % alt, r"\1ZZZ_\2_ZZZ", out, flags=re.M)
    if out != s:
        touched += 1
        open(path, "w").write(out)
if touched == 0:
    sys.stderr.write("M5 renamed no anchors — the mutation did nothing\n")
    sys.exit(1)
PY
if [ $? -eq 0 ]; then
  expect "M5 no locatable template fails loudly (no vacuous pass)" 1
else
  total=$((total+1)); echo "FAIL  M5 mutation renamed nothing"
fi

echo "---"
echo "test-emit-block-parses: $pass/$total passed"
[ "$pass" -eq "$total" ] || exit 1
