#!/usr/bin/env bash
# test-rules-seams.sh — STATIC trust-boundary self-test for the FOUR advisory house-rules
# enforcement seams wired in slice #3b-ii. STATIC ONLY: greps the committed seam surfaces, no
# network, no jq, no shell execution — so it runs on the plugin's Ubuntu CI like every other
# test-*.sh (auto-registered by ci.yml's test-*.sh glob). Exit 0 = all pass, 1 = any fail.
#
# Mirrors test-rules-docs.sh convention: pass/fail counters, ok()/no() helpers, a
# "RESULT: N passed, M failed" tail, exit 1 on any failure. Paths resolve from $BASH_SOURCE's
# dir so it runs from any CWD under the CI glob.
#
# The FOUR advisory seams (worker DO-side + Phase 4.5 self-heal review + SessionStart nudge):
#   - agents/supervisor.md              (Phase 4.5 self-heal review lens + worker fast-path spawn)
#   - agents/execute-manager.md         (parallel-path worker spawn injects house rules)
#   - skills/self-heal-advisory/SKILL.md (the self-heal advisory contract)
#   - scripts/session-resume.sh         (the SessionStart nudge)
#
# Asserts, for EACH seam surface:
#   (A) it references read-rules.sh for house-rules context (the ADVISORY reader), AND
#   (B) it NEVER references rules-check.sh (the human-invoked EXECUTION path must not leak into
#       an unattended seam), AND
#   (C) it NEVER pipes / substitutes / execs read-rules.sh OUTPUT into a shell executor
#       (`| bash`, `| sh`, `eval`, exec'd `$(...)`, `source`) — the reader emits `check` as DATA
#       and no seam runs it.
#
# SCOPE NOTE: the negative assertion is scoped to (1) rules-check.sh and (2) executing
# read-rules.sh OUTPUT. It does NOT blanket-ban `bash -c`, because self-heal-advisory/SKILL.md
# legitimately mentions `bash -c` in UNRELATED ground-truth `cmd:` trust-boundary prose (a
# pre-existing line about `## Executable Acceptance` cmd: bullets, not about house rules). Seam
# prose that says the reader "never ... `bash -c`s a check" is an ASSERTION of the invariant, not
# a violation, so we do not grep for a bare `bash -c` token.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HERE/.." && pwd)"

SEAMS=(
  "$PLUGIN_ROOT/agents/supervisor.md"
  "$PLUGIN_ROOT/agents/execute-manager.md"
  "$PLUGIN_ROOT/skills/self-heal-advisory/SKILL.md"
  "$PLUGIN_ROOT/scripts/session-resume.sh"
)

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

for f in "${SEAMS[@]}"; do
  base="$(basename "$(dirname "$f")")/$(basename "$f")"

  # (0) the seam surface exists
  if [ ! -f "$f" ]; then
    no "[$base] MISSING seam surface ($f)"
    continue
  fi
  ok "[$base] seam surface exists"

  # (A) references read-rules.sh (the advisory reader is wired at this seam)
  if grep -qF 'read-rules.sh' "$f"; then
    ok "[$base] references read-rules.sh (advisory house-rules context)"
  else
    no "[$base] MISSING read-rules.sh reference"
  fi

  # (B) NEVER references rules-check.sh (the human-invoked execution path must not leak here)
  if grep -qF 'rules-check.sh' "$f"; then
    no "[$base] MUST NOT reference rules-check.sh (execution path leaked into an unattended seam)"
  else
    ok "[$base] never references rules-check.sh"
  fi

  # (C) NEVER pipes/substitutes/execs read-rules.sh OUTPUT into a shell executor.
  #     We flag any line that mentions read-rules.sh AND ALSO carries an executor sink
  #     (| bash, | sh, eval, source, or a command-substituted invocation that is exec'd).
  #     Lines that ASSERT the invariant ("never pipes/evals/sources/`bash -c`s the reader
  #     output" / "does NOT eval") are allowlisted — a negated assertion is not a violation.
  exec_leak=""
  while IFS= read -r line; do
    # only consider lines that actually mention the reader
    case "$line" in
      *read-rules.sh*) ;;
      *) continue ;;
    esac
    # allowlist ONLY lines that explicitly NEGATE execution (invariant assertions).
    # Scoped tight to `never`/`NEVER` — the exact phrasing the seams use ("NEVER
    # pipes/evals/sources/`bash -c`s the reader output"). Deliberately NOT allowlisting
    # a bare `not`/`NOT`/`# comment`: those are too broad and could mask a genuine
    # exec-leak line that merely happened to contain "not" or sit in a comment. The
    # precise positive sink match below — not this allowlist — is the real guarantee.
    case "$line" in
      *never*|*NEVER*) continue ;;
    esac
    # flag genuine executor sinks piping/substituting the reader output
    case "$line" in
      *'read-rules.sh'*'| bash'*|*'read-rules.sh'*'| sh'*|*'eval'*'read-rules.sh'*|*'source'*'read-rules.sh'*|*'$(bash'*'read-rules.sh'*')'*)
        exec_leak="$line" ;;
    esac
  done < "$f"

  if [ -z "$exec_leak" ]; then
    ok "[$base] never pipes/execs read-rules.sh OUTPUT into a shell executor"
  else
    no "[$base] read-rules.sh OUTPUT executed in a shell sink: ${exec_leak}"
  fi
done

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
