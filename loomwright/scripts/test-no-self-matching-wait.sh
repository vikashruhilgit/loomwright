#!/usr/bin/env bash
# test-no-self-matching-wait.sh — every prompt that tells a spawned agent to run tests also tells it
# how to WAIT on a long run without writing a wait that never ends.
#
# WHY THIS EXISTS (measured 2026-10-08, pa/23 and pa/24 runs): a fix agent ran the project's
# pre-push suite in the foreground; it outlived the agent's tool-call timeout, so the harness moved
# it to the background, and the agent improvised
#     until ! pgrep -f "scripts/ci-local.sh" >/dev/null; do sleep 5; done
# The agent's shell tool runs the WHOLE command line as one `<shell> -c "<command>"` process, so
# that shell's own argv contains the pattern: `pgrep -f` always matches the waiter itself and the
# loop never exits. Two such waiters ran ~80 min in pa/23 and 18+ min in pa/24, with no suite
# running, until they were killed by hand.
#
# The rule each surface carries ends with the pinned phrase below. Surfaces are DERIVED, not
# hand-listed: every line in an agent or skill prompt that tells a fix worker to run tests
# ("tests locally") must carry the phrase on that line or the next 3, and the worker contract's
# test step (anchored on "pre-push command") must too. A new fix-worker prompt that says
# "tests locally" without the rule fails here.
#
# Honest limit: a prompt that asks for tests in other words ("run the suite") is not derived.
# Fail-CLOSED: zero derived anchors means the derivation broke, not that all is well.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
PHRASE='the waiter matches itself and never exits'

PASS=0
FAIL=0
ok() { echo "PASS: $1"; PASS=$((PASS + 1)); }
no() { echo "FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

# missing FILE ANCHOR_ERE — prints `<line>` for every anchor line with no PHRASE on it or the next 3.
missing() {
  awk -v anchor="$2" -v phrase="$PHRASE" '
    { line[NR] = $0 }
    $0 ~ anchor { a[++n] = NR }
    END {
      for (i = 1; i <= n; i++) {
        found = 0
        for (j = a[i]; j <= a[i] + 3 && j <= NR; j++) if (index(line[j], phrase)) found = 1
        if (!found) print a[i]
      }
    }' "$1"
}
# anchors FILE ANCHOR_ERE — how many anchor lines the file has.
anchors() { awk -v anchor="$2" '$0 ~ anchor { n++ } END { print n + 0 }' "$1"; }

TESTS_ANCHOR='tests locally'
total=0
files=()
for f in "$PLUGIN"/agents/*.md "$PLUGIN"/skills/*/SKILL.md; do
  n="$(anchors "$f" "$TESTS_ANCHOR")"
  [ "$n" -gt 0 ] || continue
  total=$((total + n)); files+=("$f")
done

# Fail closed on the derivation itself: the three known fix-worker prompts (Phase 4.5, review-heal's
# default loop, review-heal's until-mergeable drain) must still be found.
if [ "$total" -ge 3 ]; then ok "derived $total fix-worker 'tests locally' anchors in ${#files[@]} file(s)"
else no "derived only $total 'tests locally' anchors (expected >= 3) — the anchor wording changed; re-derive"; fi

for f in ${files[@]+"${files[@]}"}; do
  rel="${f#"$PLUGIN"/}"
  m="$(missing "$f" "$TESTS_ANCHOR")"
  if [ -z "$m" ]; then ok "$rel: every 'tests locally' prompt carries the no-self-matching-wait rule"
  else no "$rel: 'tests locally' at line(s) $(tr '\n' ' ' <<<"$m")has no '$PHRASE' within 3 lines"; fi
done

W="$PLUGIN/agents/worker.md"
if [ "$(anchors "$W" "pre-push command")" -ge 1 ] && [ -z "$(missing "$W" "pre-push command")" ]; then
  ok "agents/worker.md: the Step 5 test step carries the no-self-matching-wait rule"
else no "agents/worker.md: the 'pre-push command' test step has no '$PHRASE' within 3 lines"; fi

# MUTATION CONTROL: drop the phrase from one prompt of a copy — the same check must catch it.
tmp="$(mktemp -d "${TMPDIR:-/tmp}/no-self-wait.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
RH="$PLUGIN/skills/review-heal/SKILL.md"
awk -v phrase="$PHRASE" 'index($0, phrase) && !done { sub(phrase, "the loop is fine"); done = 1 } { print }' "$RH" > "$tmp/SKILL.md"
if [ -n "$(missing "$tmp/SKILL.md" "$TESTS_ANCHOR")" ]; then ok "MUTATION CONTROL: a fix prompt with the rule removed is caught"
else no "MUTATION CONTROL: removing the rule from one review-heal prompt went unnoticed"; fi

echo
echo "test-no-self-matching-wait: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
