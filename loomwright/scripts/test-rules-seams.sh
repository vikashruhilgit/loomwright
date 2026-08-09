#!/usr/bin/env bash
# test-rules-seams.sh — trust-boundary + invocation-shape self-test for the FOUR advisory house-rules
# enforcement seams wired in slice #3b-ii. Two parts, deliberately different in kind:
#
#   PART 1 (STATIC, always runs) — greps the committed seam surfaces; no network, no jq, no shell
#     execution of anything. This is what holds the WIRING: two of the four seams are agent/skill
#     MARKDOWN, so there is nothing there to execute and only a grep can assert that the prose still
#     hands the reader the right thing.
#   PART 2 (DYNAMIC, jq-gated, added with `applies_to` PATH ROUTING) — actually EXECUTES the reader
#     against a throwaway fixture rules store and asserts on real stdout. The three prose seams reduce
#     to exactly TWO distinct executable invocation shapes, and routing made the difference between
#     them behavioural rather than cosmetic, so both are now traced:
#       (i)  `bash read-rules.sh <paths…>`  — worker DO-side (agents/execute-manager.md,
#            agents/supervisor.md) AND Phase 4.5 (skills/self-heal-advisory/SKILL.md). They differ
#            only in WHICH path set they pass, not in the shape.
#       (ii) `bash read-rules.sh`  (no args) — the SessionStart nudge (scripts/session-resume.sh).
#     EXPLICIT LIMIT, stated so nobody reads more into these than they carry: a dynamic trace CANNOT
#     prove the two prose seams still pass the reader the right paths — they are markdown, not code.
#     That wiring stays covered by PART 1's greps. This is a shape-and-behaviour trace, not end-to-end
#     proof. Part 2 degrades to a clean skip when jq is unavailable (the reader no-ops without it).
#
# Runs on the plugin's Ubuntu CI like every other test-*.sh (auto-registered by ci.yml's test-*.sh
# glob). Exit 0 = all pass, 1 = any fail.
#
# Mirrors test-rules-docs.sh convention: pass/fail counters, ok()/no() helpers, a
# "RESULT: N passed, M failed" tail, exit 1 on any failure. Paths resolve from $BASH_SOURCE's
# dir so it runs from any CWD under the CI glob.
#
# The FOUR advisory seams (worker DO-side + Phase 4.5 self-heal review + SessionStart nudge):
#   - agents/supervisor.md              (Phase 4.5 self-heal review lens + worker Single-Agent-path spawn)
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

# ============================================================================
# PART 2 — DYNAMIC trace of the TWO distinct executable invocation shapes (see the header).
# ============================================================================
echo
echo "== DYNAMIC: the two executable seam shapes, run against a fixture rules store =="

READER="$PLUGIN_ROOT/scripts/read-rules.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "  skip: jq unavailable — read-rules.sh no-ops by contract, so a dynamic trace is vacuous here."
elif [ ! -r "$READER" ]; then
  no "[scripts/read-rules.sh] MISSING — cannot trace the executable seam shapes"
else
  DROOT="$(mktemp -d)"
  trap 'rm -rf "$DROOT" 2>/dev/null' EXIT
  FIXREPO="$DROOT/repo"
  mkdir -p "$FIXREPO/.agent/rules"
  ( cd "$FIXREPO" && git init -q && git config user.email t@t && git config user.name t \
      && echo init > f && git add f && git commit -qm init ) >/dev/null 2>&1
  # One scoped rule + one repo-wide rule: the minimum fixture that can tell routing apart from
  # emit-everything on BOTH shapes.
  cat > "$FIXREPO/.agent/rules/seam-fixture.json" <<'FIXTURE'
[
  {"id":"seam-scoped","category":"a","statement":"SEAM scoped to loomwright scripts","enforcement":"advisory","check":null,"provenance":{"source":"seam-test"},"applies_to":["loomwright/scripts/*"]},
  {"id":"seam-wide","category":"b","statement":"SEAM repo wide rule","enforcement":"advisory","check":null,"provenance":{"source":"seam-test"}}
]
FIXTURE

  # ---- SHAPE (i): `bash read-rules.sh <paths…>` — worker DO-side AND Phase 4.5 -------------------
  # Trace it TWICE with different path sets, because that is the only way the two prose seams differ.
  # (i-a) a worker-style path set that INCLUDES a scripts path ⇒ both rules.
  s1a="$( cd "$FIXREPO" && bash "$READER" loomwright/scripts/read-rules.sh CHANGELOG.md 2>/dev/null )"
  if printf '%s\n' "$s1a" | grep -qF -- "- SEAM scoped to loomwright scripts" \
     && printf '%s\n' "$s1a" | grep -qF -- "- SEAM repo wide rule"; then
    ok "[shape i] \`read-rules.sh <paths…>\` with an in-scope path emits the scoped AND the repo-wide rule"
  else
    no "[shape i] in-scope path set did not emit both rules: $s1a"
  fi
  # (i-b) a Phase-4.5-style integrated-diff path set that EXCLUDES scripts ⇒ scoped rule ABSENT.
  # This is the assertion that makes the trace non-vacuous: it fails against an emit-everything reader.
  s1b="$( cd "$FIXREPO" && bash "$READER" docs/ARCHITECTURE.md README.md 2>/dev/null )"
  if printf '%s\n' "$s1b" | grep -qF -- "- SEAM repo wide rule" \
     && ! printf '%s\n' "$s1b" | grep -qF "SEAM scoped to loomwright scripts"; then
    ok "[shape i] an out-of-scope path set emits ONLY the repo-wide rule (scoped rule ABSENT from stdout)"
  else
    no "[shape i] out-of-scope path set did not route the scoped rule out: $s1b"
  fi
  # The shape's own no-hang contract: args take precedence and stdin is NEVER read, so an
  # open-but-idle pipe on stdin cannot block an agent caller.
  s1c="$( cd "$FIXREPO" && bash "$READER" loomwright/scripts/x.sh < /dev/zero 2>/dev/null )"
  printf '%s\n' "$s1c" | grep -qF -- "- SEAM scoped to loomwright scripts" \
    && ok "[shape i] args take precedence and stdin is never read (no hang on an idle//dev/zero stdin)" \
    || no "[shape i] the args-not-stdin no-hang contract regressed"

  # ---- SHAPE (ii): `bash read-rules.sh` (no args) — the SessionStart nudge -----------------------
  # session-resume.sh's rules_nudge() runs EXACTLY this and fires its "no house rules found" advisory
  # when stdout is EMPTY. So the load-bearing assertion here is NON-EMPTINESS plus completeness: a
  # repo that HAS rules must never look ruleless, even though one of its rules is path-scoped.
  s2="$( cd "$FIXREPO" && bash "$READER" 2>/dev/null )"; rc2=$?
  [ "$rc2" -eq 0 ] && ok "[shape ii] \`read-rules.sh\` with NO args exits 0" \
                   || no "[shape ii] expected exit 0 from the no-arg shape, got $rc2"
  [ -n "$s2" ] && ok "[shape ii] no-arg stdout is NON-EMPTY (rules_nudge stays quiet on a repo with rules)" \
               || no "[shape ii] no-arg stdout EMPTY — the SessionStart nudge would misfire"
  if printf '%s\n' "$s2" | grep -qF -- "- SEAM scoped to loomwright scripts" \
     && printf '%s\n' "$s2" | grep -qF -- "- SEAM repo wide rule"; then
    ok "[shape ii] the no-arg shape stays REPO-WIDE — a path-scoped rule is emitted too"
  else
    no "[shape ii] the no-arg shape dropped a scoped rule (empty path set must fail OPEN): $s2"
  fi
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
