#!/usr/bin/env bash
# test-reviewer-interaction-lens.sh — seam test for the Code Reviewer's static interaction-behaviour
# lens and the `cannot_determine` admission rule (#433).
#
# #433: a reviewer PASS filed "focus / tab order / screen-reader announcement" under runtime-only.
# A human then found, by reading the same diff, that a successful action unmounted the focused
# button with nothing restoring focus. The frontend checklist only asked what an element HAS
# (alt text, aria-label, contrast); nothing asked what happens AFTER a state change, and
# `cannot_determine` needed no reason, so anything off the checklist could be deferred.
#
# Every surface here is prompt markdown, so a static read is the only thing that can hold the
# wiring. This test pins ORDER and OUTCOMES, not mere presence:
#   (a) POSITION — in agents/code-reviewer.md the lens sits inside Review Process step 3's FRONTEND
#       block: after Context Setup's "Determine Review Scope" and step 1 (the diff is loaded), before
#       the BACKEND block, step 4, step 6 (severity) and "### Output Format".
#   (b) OUTCOME — a lens hit is an ordinary `issues[]` finding under step 6's severity-assignment
#       rule, with no new decision state; step 6's rule names the lens, so a lens hit cannot be
#       labelled MEDIUM and slip under the fix floor.
#   (c) cannot_determine — the admission rule sits inside step 5 (before 5a, which points back at
#       it), says lens questions are never admissible, requires a reason naming what would have to
#       run, and the output-format key list and the pre-review checklist both carry it.
#   (d) PARITY — the lens ids are the same, in the same order, in the agent, the command mirror
#       (commands/code-reviewer.md) and the frontend-ui skill table.
#   (m) MUTANTS — each check runs on a mutated copy that MUST fail it: the lens moved below
#       "### Output Format", an id dropped from the skill, an id reworded in the command mirror,
#       the admission rule moved after step 5c, and the lens's outcome sentence reworded to a
#       "cannot_determine" deferral.
#
# EXPLICIT LIMIT: this pins the wiring. Whether a live reviewer emits a lens finding on a real
# diff is prompt behaviour; see the PR body for the one-off live probe. The reason requirement
# itself is enforced in code by validate-code-review-result.py (v3 rule n, its own suite).
#
# Conventions: ok()/no() defined here, "RESULT: N passed, M failed" tail, exit 1 on any failure,
# paths from $BASH_SOURCE, bash 3.2 / BSD userland safe.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HERE/.." && pwd)"

AGENT="$PLUGIN_ROOT/agents/code-reviewer.md"
COMMAND="$PLUGIN_ROOT/commands/code-reviewer.md"
SKILL="$PLUGIN_ROOT/skills/frontend-ui/SKILL.md"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

for f in "$AGENT" "$COMMAND" "$SKILL"; do
  [ -f "$f" ] || no "MISSING surface: $f"
done
if [ "$fail" -ne 0 ]; then echo; echo "RESULT: $pass passed, $fail failed"; exit 1; fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

# check <name> <agent> <command> <skill> — prints "ok" or the failure reasons. One python program
# for every check so the real files and every mutant go through the identical code path.
check() {
  python3 - "$@" <<'PY'
import re, sys
name, agent_p, command_p, skill_p = sys.argv[1:5]
A = open(agent_p, encoding="utf-8").read()
C = open(command_p, encoding="utf-8").read()
S = open(skill_p, encoding="utf-8").read()
bad = []

def at(text, anchor, label):
    i = text.find(anchor)
    if i < 0:
        bad.append("%s: anchor %r missing" % (label, anchor))
    return i

LENS = "**Interaction-behaviour lens (static"

def lens_block(text):
    i = text.find(LENS)
    if i < 0:
        return ""
    j = text.find("**For BACKEND code specifically", i)
    return text[i:j if j > i else i + 3000]

def ids_agent():
    return re.findall(r"^\s+- `([a-z_]+)` — ", lens_block(A), re.M)

def ids_command():
    m = re.search(r"\*\*Interaction behaviour \(static lens\):\*\*(.*?)A hit is", C, re.S)
    return re.findall(r"`([a-z_]+)`", m.group(1)) if m else []

def ids_skill():
    i = S.find("## Interaction-behaviour lens (static)")
    if i < 0:
        return []
    j = S.find("\n## ", i + 5)
    sec = S[i:j if j > i else len(S)]
    return re.findall(r"^\| `([a-z_]+)` \|", sec, re.M)

if name == "position":
    order = [
        ("4. **Determine Review Scope**", "context setup scope"),
        ("### Review Process", "review process"),
        ("1. **Understand Code Context**", "step 1 (diff loaded)"),
        ("3. **Pattern & UI Consistency Audit**", "step 3"),
        ("**For FRONTEND code specifically**", "frontend block"),
        (LENS, "the lens"),
        ("**For BACKEND code specifically", "backend block"),
        ("4. **Adversarial-Input Lens", "step 4"),
        ("6. **Flag Issues by Severity**", "step 6"),
        ("### Output Format", "output format"),
    ]
    idx = [(at(A, a, "agent"), lbl) for a, lbl in order]
    for (i1, l1), (i2, l2) in zip(idx, idx[1:]):
        if i1 >= 0 and i2 >= 0 and not i1 < i2:
            bad.append("agent: %s is not before %s" % (l1, l2))
    if A.count(LENS) != 1:
        bad.append("agent: the lens appears %d times, expected exactly once" % A.count(LENS))

elif name == "outcome":
    blk = lens_block(A)
    for need in ("`issues[]` finding", "step 6's severity-assignment rule", "No new decision state",
                 "does not apply and writes nothing"):
        if need not in blk:
            bad.append("agent lens: outcome phrase %r missing" % need)
    # The lens may only name cannot_determine / runtime to forbid them ("never …").
    if re.search(r"(?i)(?<!never `)cannot_determine|runtime-only", blk.replace('never defer it as "runtime"', "")):
        bad.append("agent lens: the lens itself offers a cannot_determine / runtime-only exit")
    i6 = at(A, "**Severity-assignment rule for `new` code-behavior findings", "agent")
    seg = A[i6:A.find("7. **Categorize Each Issue**", i6)] if i6 >= 0 else ""
    if "Interaction-behaviour lens" not in seg:
        bad.append("agent step 6: the severity-assignment rule does not name the interaction lens")

elif name == "cannot_determine":
    rule = "**`cannot_determine` — admission rule"
    i5 = at(A, "5. **Execution-Grounded Verification", "agent")
    ir = at(A, rule, "agent")
    i5a = at(A, "5a. **Brief conformance", "agent")
    if min(i5, ir, i5a) >= 0 and not (i5 < ir < i5a):
        bad.append("agent: the admission rule is not inside step 5 (before 5a)")
    para = A[ir:A.find("\n\n", ir)] if ir >= 0 else ""
    for need in ("`{item, reason}`", "what would have to run or be read", "lens question is never admissible",
                 "rendered page or a real run", "evidence outside the diff"):
        if need not in para:
            bad.append("agent admission rule: %r missing" % need)
    m = re.search(r"^\s+- `cannot_determine` — (.*)$", A[i5a:] if i5a >= 0 else "", re.M)
    if not m or "step 5's admission rule" not in m.group(1):
        bad.append("agent step 5a: cannot_determine bullet does not point at step 5's admission rule")
    if "each `cannot_determine` entry exactly `item`, `reason`" not in A:
        bad.append("agent output format: cannot_determine entry keys not listed")
    if not re.search(r"^- \[ \] Interaction-behaviour lens applied.*`cannot_determine`.*what would have to run", A, re.M):
        bad.append("agent pre-review checklist: lens / cannot_determine reason item missing")
    if "none goes in `cannot_determine`" not in S:
        bad.append("skill: does not say lens questions never go in cannot_determine")
    if "reason naming what would have to run" not in C:
        bad.append("command: cannot_determine reason requirement missing")

elif name == "parity":
    a, c, s = ids_agent(), ids_command(), ids_skill()
    if len(a) != 6:
        bad.append("agent: expected 6 lens ids, got %d %r" % (len(a), a))
    if a != c:
        bad.append("command mirror ids %r != agent %r" % (c, a))
    if a != s:
        bad.append("skill ids %r != agent %r" % (s, a))
    if "agents/code-reviewer.md" not in S[S.find("## Interaction-behaviour lens (static)"):][:800]:
        bad.append("skill: lens section does not point at the canonical agent list")

print("ok" if not bad else "; ".join(bad))
PY
}

run() {  # run <label> <check> <agent> <command> <skill>
  local out; out="$(check "$2" "$3" "$4" "$5")"
  if [ "$out" = "ok" ]; then ok "$1"; else no "$1 — $out"; fi
}

echo "== real surfaces =="
run "(a) lens sits in step 3 FRONTEND, after scope + diff load, before step 4/6 and Output Format" position "$AGENT" "$COMMAND" "$SKILL"
run "(b) lens hits are ordinary issues[] findings under step 6's severity rule, no new state" outcome "$AGENT" "$COMMAND" "$SKILL"
run "(c) cannot_determine admission rule in step 5, reason required, lens never admissible" cannot_determine "$AGENT" "$COMMAND" "$SKILL"
run "(d) lens ids identical and in order across agent, command mirror and skill" parity "$AGENT" "$COMMAND" "$SKILL"

# mutate <out> <src> <python expr on s> — writes a mutated copy; prints "same" when the mutation
# did not apply (so a mutant can never pass vacuously).
mutate() {
  python3 - "$1" "$2" "$3" <<'PY'
import sys
out, src, expr = sys.argv[1:4]
s = open(src, encoding="utf-8").read()
m = eval(expr)
open(out, "w", encoding="utf-8").write(m)
print("same" if (m == s or not m.strip()) else "changed")
PY
}

# expect_fail <label> <check> <agent> <command> <skill> <mutation status>
expect_fail() {
  if [ "$6" != "changed" ]; then no "$1 — INVALID mutant (did not apply)"; return; fi
  local out; out="$(check "$2" "$3" "$4" "$5")"
  if [ "$out" != "ok" ]; then ok "$1 (caught: ${out%%;*})"; else no "$1 — mutant passed the check"; fi
}

echo "== mutants (each MUST fail its check) =="
MOVE='(lambda i, j: (s[:i] + s[j:]).replace("### Output Format\n", "### Output Format\n\n" + s[i:j], 1) if 0 <= i < j else s)(s.find("   - **Interaction-behaviour lens (static"), s.find("   **For BACKEND code specifically"))'
st="$(mutate "$TMP/m1.md" "$AGENT" "$MOVE")"
expect_fail "(m1) lens moved below ### Output Format" position "$TMP/m1.md" "$COMMAND" "$SKILL" "$st"

st="$(mutate "$TMP/m2.md" "$SKILL" '"".join(l for l in s.splitlines(True) if not l.startswith("| `state_reset_on_input_change` |"))')"
expect_fail "(m2) one id dropped from the skill table" parity "$AGENT" "$COMMAND" "$TMP/m2.md" "$st"

st="$(mutate "$TMP/m3.md" "$COMMAND" 's.replace("`unsaved_exit_parity`", "`unsaved_changes`", 1)')"
expect_fail "(m3) one id reworded in the command mirror" parity "$AGENT" "$TMP/m3.md" "$SKILL" "$st"

MOVE_RULE='(lambda i: (lambda j, p: (s[:i] + s[j:]).replace("6. **Flag Issues by Severity**", p + "\n6. **Flag Issues by Severity**", 1))(s.find("\n\n", i) + 2, s[i:s.find("\n\n", i) + 2]) if i >= 0 else s)(s.find("   **`cannot_determine` — admission rule"))'
st="$(mutate "$TMP/m4.md" "$AGENT" "$MOVE_RULE")"
expect_fail "(m4) admission rule moved after step 5c" cannot_determine "$TMP/m4.md" "$COMMAND" "$SKILL" "$st"

st="$(mutate "$TMP/m5.md" "$AGENT" 's.replace("A hit is an ordinary `issues[]` finding naming its id", "A question you cannot settle goes in `cannot_determine`", 1)')"
expect_fail "(m5) lens outcome reworded into a cannot_determine deferral" outcome "$TMP/m5.md" "$COMMAND" "$SKILL" "$st"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
