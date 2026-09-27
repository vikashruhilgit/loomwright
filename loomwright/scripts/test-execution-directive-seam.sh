#!/usr/bin/env bash
# test-execution-directive-seam.sh — static wiring test for the execution-grounded review lens
# (automate-followups/02): the EXECUTION DIRECTIVE line in the Supervisor Phase 4.5 reviewer spawn
# prompt (skills/self-heal-advisory/SKILL.md Part 2 §"Review-and-fix loop"), the directive-gated
# scratch-dir repro + read-only carve-out in agents/code-reviewer.md, the static-only `execution: none`
# marker in .github/workflows/claude-code-review.yml, and its static-only consumer in
# skills/review-heal/SKILL.md.
#
# Every surface here is prompt text an agent executes — there is nothing to run, so a grep is the only
# thing that can hold the wiring. Shape follows test-brief-conformance-seam.sh: ok()/no() helpers
# DEFINED here, a "RESULT: N passed, M failed" tail, exit 1 on any failure, paths from $BASH_SOURCE so
# it runs from any CWD under ci.yml's `loomwright/scripts/test-*.sh` glob. bash 3.2 / BSD userland safe.
#
# Asserts (every one paired with a MUTATION CONTROL — a copy of the surface with the asserted text
# removed; the mutant is validated non-empty + readable + differs-from-original, and the SAME check
# must then FAIL against it, or the assertion is vacuous):
#   (a) the EXECUTION DIRECTIVE prompt line exists, is the next non-blank line after ANTI-OVERLAP (so it
#       cannot disturb the HOUSE-RULES -> BRIEF-CONFORMANCE -> DEVIATIONS adjacency), references
#       code-reviewer §5 + `mktemp -d`, and scopes itself to §5 load-bearing claims only.
#   (b) the BRIEF-CONFORMANCE line no longer says an UNSCOPED "(you execute nothing)".
#   (c) the multi-voter refute wording: ONLY the code-reviewer-lens refute carries the directive.
#   (d) agents/code-reviewer.md: `mktemp -d`, the directive gate sentence, the honest-limit note, the
#       write-inside-the-repo => `unverified` rule, and the IDENTICAL carve-out sentence in BOTH the §5
#       "Mutation guardrails" paragraph and the Critical Rules "Read-only via Bash too" bullet.
#       Plus (PR #281 review): the run-from-scratch `cd "$SCRATCH" && …` rule and the
#       `git status --porcelain --ignored` snapshot in BOTH copies, the `--ignored` overwrite blind spot,
#       and the test-integrity-guard fixture rule (rename, else `unverified`; not a PR defect).
#   (e) the workflow prompt carries the exact marker sentence on a line of its own, mandated LAST.
#   (f) skills/review-heal/SKILL.md names the CI lens `static-only` and keeps the fallback trigger.
#   (g) the standalone /review-pr surfaces (agents/review-pr.md, commands/review-pr.md) do NOT carry
#       the directive (decision 4 — a fork PR must never be told to execute repros).
#
# EXPLICIT LIMIT: this pins WIRING. It cannot prove a reviewer actually reproduces a claim, nor that a
# live claude-review comment ends with the marker — both are runtime behaviour.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HERE/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/.." && pwd)"

SKILL="$PLUGIN_ROOT/skills/self-heal-advisory/SKILL.md"
REVIEWER="$PLUGIN_ROOT/agents/code-reviewer.md"
HEAL="$PLUGIN_ROOT/skills/review-heal/SKILL.md"
WORKFLOW="$REPO_ROOT/.github/workflows/claude-code-review.yml"
RP_AGENT="$PLUGIN_ROOT/agents/review-pr.md"
RP_CMD="$PLUGIN_ROOT/commands/review-pr.md"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

# Canonical strings — ONE copy each, used by the real check AND by the mutant builders.
CARVE='Scratch-dir exception (in addition to the agent-memory proposal write): under the EXECUTION DIRECTIVE, Bash may create, write and `rm` files ONLY inside a `mktemp -d` scratch dir the reviewer itself created outside the checkout, and every repro command runs as `cd "$SCRATCH" && …` with `HOME="$SCRATCH/home"` (`mkdir -p` it first; a scratch `git init` then needs `git -c user.name=r -c user.email=r@x …`) and `CLAUDE_PROJECT_DIR` unset or set to `$SCRATCH`, so CWD-relative and `$HOME`-default writes (e.g. `.supervisor/`, user-scope config under `$HOME`) land there; the working tree, git state and shared state remain read-only, and the `git status --porcelain --ignored` before/after check still runs against the checkout — it cannot see writes outside the checkout, so relocating `HOME` is the guard for user-scope state.'
# PR #281 review: a repro run from the checkout could overwrite gitignored live state (`.supervisor/`)
# invisibly to a plain `git status --porcelain` — these pin the run-from-scratch rule and the
# `--ignored` snapshot on their own, so a CARVE edit that drops either still turns a check red.
SCRATCH_CD='every repro command runs as `cd "$SCRATCH" && …`'
HOME_RELOC='with `HOME="$SCRATCH/home"` (`mkdir -p` it first'
IGNORED_SNAP='the `git status --porcelain --ignored` before/after check'
CAPTURE_IGNORED='capture `git status --porcelain --ignored`'
OVERWRITE_LIMIT='never an overwrite of an existing one'
COLLAPSE_LIMIT='never a new file inside an already-ignored directory'
TIG_RENAME='rename it (e.g. `fixture-hooks.json`) when the script takes a path'
TIG_NOT_DEFECT='that block is NOT a defect in the PR and NOT by itself grounds for NEEDS_HUMAN'
GATE='without the EXECUTION DIRECTIVE, do not author or run new adversarial repro scripts; the rest of §5 (type-check, the existing tests that cover the diff, `unverified`) is unchanged.'
HONEST='already runs PR-authored test code when a standalone `/review-pr` targets an untrusted fork PR'
INSIDE='A repro that would need to write INSIDE the repo is reported `unverified`'
MARKER='execution: none — static review; this reviewer cannot run code in CI, so runtime behavior is NOT verified by this review.'
DIRECTIVE_PREFIX='**EXECUTION DIRECTIVE (every iteration'
GUARD_ANCHOR='**Mutation guardrails (NON-NEGOTIABLE'
CRIT_ANCHOR='**Read-only via Bash too:**'
REFUTE_ANCHOR='2. **Second-opinion refute check'
REFUTE_SCOPE='ONLY the refute spawn sent to the **code-reviewer lens** carries the EXECUTION DIRECTIVE line'

for f in "$SKILL" "$REVIEWER" "$HEAL" "$WORKFLOW" "$RP_AGENT" "$RP_CMD"; do
  [ -f "$f" ] || no "MISSING surface: $f"
done
if [ "$fail" -ne 0 ]; then echo; echo "RESULT: $pass passed, $fail failed"; exit 1; fi

# ---- helpers ---------------------------------------------------------------------------------------
# line_with <file> <fixed-anchor> — first line containing the anchor (whitespace-insensitive prefix not
# required; a fixed-string grep keeps regex metacharacters in the anchors inert).
line_with() { grep -F -- "$2" "$1" 2>/dev/null | head -1; }
has() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }

# Mutant builders — each writes $MUT from $1. LC_ALL=C keeps awk's index/substr byte-consistent on the
# multibyte em dash / section sign.
del_lines()     { grep -vF -- "$2" "$1" > "$MUT" || true; }
strip_in_line() { LC_ALL=C awk -v a="$2" -v n="$3" '{ if (index($0, a)) { i = index($0, n); if (i) $0 = substr($0, 1, i - 1) substr($0, i + length(n)) } print }' "$1" > "$MUT"; }
append_text()   { { cat "$1"; printf '%s\n' "$2"; } > "$MUT"; }

MUT="$(mktemp)"
trap 'rm -f "$MUT" 2>/dev/null' EXIT

# check_with_mutant <label> <check-fn> <file> <builder> <builder-args...>
#   runs <check-fn> <file> (must pass), builds a mutant, validates it, runs <check-fn> <mutant> (must fail).
check_with_mutant() {
  label="$1"; fn="$2"; file="$3"; shift 3
  if "$fn" "$file"; then ok "$label"; else no "$label"; fi
  builder="$1"; shift
  "$builder" "$file" "$@"
  if [ -s "$MUT" ] && [ -r "$MUT" ] && ! cmp -s "$file" "$MUT"; then
    if "$fn" "$MUT"; then
      no "$label — mutation control: check still PASSES with the asserted text removed (vacuous)"
    else
      ok "$label — mutation control: check fails on a valid mutant"
    fi
  else
    no "$label — mutation control: mutant invalid (empty/unreadable/identical) — cannot be trusted"
  fi
}

# ---- (a) the EXECUTION DIRECTIVE prompt line ---------------------------------------------------------
chk_directive_line() {
  l="$(line_with "$1" "$DIRECTIVE_PREFIX")"
  [ -n "$l" ] || return 1
  has "$l" '`agents/code-reviewer.md` §5' && has "$l" '`mktemp -d`' && has "$l" 'OUTSIDE the working tree' \
    && has "$l" 'governs §5 load-bearing claims ONLY' && has "$l" 'stay diff-text-only'
}
chk_directive_after_antioverlap() {
  LC_ALL=C awk -v d="$DIRECTIVE_PREFIX" '
    { t = $0; sub(/^[[:space:]]+/, "", t) }
    after && t != "" { if (index(t, d) == 1) hit = 1; after = 0 }
    index(t, "**ANTI-OVERLAP (every iteration") == 1 { after = 1 }
    END { exit (hit ? 0 : 1) }
  ' "$1"
}
check_with_mutant "(a) EXECUTION DIRECTIVE line carries §5 ref, mktemp -d, outside-tree and §5-only scope" \
  chk_directive_line "$SKILL" del_lines "$DIRECTIVE_PREFIX"
check_with_mutant "(a) EXECUTION DIRECTIVE line is the next non-blank line after ANTI-OVERLAP" \
  chk_directive_after_antioverlap "$SKILL" del_lines "$DIRECTIVE_PREFIX"

# ---- (b) BRIEF-CONFORMANCE no longer says an unscoped "execute nothing" ------------------------------
chk_brief_scoped() {
  l="$(line_with "$1" '**BRIEF-CONFORMANCE ADVISORY (')"
  [ -n "$l" ] || return 1
  has "$l" 'you execute nothing for these verdicts' && ! has "$l" '(you execute nothing)'
}
check_with_mutant "(b) BRIEF-CONFORMANCE line scopes 'execute nothing' to its own verdicts" \
  chk_brief_scoped "$SKILL" strip_in_line '**BRIEF-CONFORMANCE ADVISORY (' ' for these verdicts — the EXECUTION DIRECTIVE above does not apply to them'

# ---- (c) refute scope: code-reviewer-lens refute only -------------------------------------------------
chk_refute_scope() {
  l="$(line_with "$1" "$REFUTE_ANCHOR")"
  [ -n "$l" ] || return 1
  has "$l" "$REFUTE_SCOPE" && has "$l" '**voter lens**' && has "$l" 'does NOT'
}
check_with_mutant "(c) multi-voter refute: only the code-reviewer-lens refute carries the directive" \
  chk_refute_scope "$SKILL" strip_in_line "$REFUTE_ANCHOR" "$REFUTE_SCOPE"

# ---- (d) agents/code-reviewer.md --------------------------------------------------------------------
chk_mktemp()  { grep -qF -- 'mktemp -d' "$1"; }
chk_gate()    { grep -qF -- "$GATE" "$1"; }
chk_honest()  { grep -qF -- "$HONEST" "$1"; }
chk_inside()  { grep -qF -- "$INSIDE" "$1"; }
chk_heredoc() { grep -qF -- 'create every repro file with Bash (heredoc)' "$1"; }
chk_carve_guard() { l="$(line_with "$1" "$GUARD_ANCHOR")"; [ -n "$l" ] && has "$l" "$CARVE"; }
chk_carve_crit()  { l="$(line_with "$1" "$CRIT_ANCHOR")"; [ -n "$l" ] && has "$l" "$CARVE"; }
check_with_mutant "(d) code-reviewer names mktemp -d" chk_mktemp "$REVIEWER" del_lines 'mktemp -d'
check_with_mutant "(d) code-reviewer carries the directive gate sentence (only NEW repro behaviour gated)" \
  chk_gate "$REVIEWER" strip_in_line '**Scratch-dir adversarial repro' "$GATE"
check_with_mutant "(d) code-reviewer carries the pre-existing fork-PR honest-limit note" \
  chk_honest "$REVIEWER" strip_in_line '**Scratch-dir adversarial repro' "$HONEST"
check_with_mutant "(d) code-reviewer keeps 'needs to write inside the repo => unverified'" \
  chk_inside "$REVIEWER" strip_in_line '**Scratch-dir adversarial repro' "$INSIDE"
check_with_mutant "(d) code-reviewer says repro files are created via Bash heredoc" \
  chk_heredoc "$REVIEWER" strip_in_line '**Scratch-dir adversarial repro' 'create every repro file with Bash (heredoc)'
check_with_mutant "(d) carve-out sentence present in the §5 Mutation guardrails paragraph" \
  chk_carve_guard "$REVIEWER" strip_in_line "$GUARD_ANCHOR" "$CARVE"
check_with_mutant "(d) carve-out sentence present in the Critical Rules 'Read-only via Bash too' bullet" \
  chk_carve_crit "$REVIEWER" strip_in_line "$CRIT_ANCHOR" "$CARVE"
# Run-from-scratch + `--ignored` snapshot, asserted in BOTH carve-out copies (PR #281 review, HIGH).
chk_cd_guard()  { l="$(line_with "$1" "$GUARD_ANCHOR")"; [ -n "$l" ] && has "$l" "$SCRATCH_CD"; }
chk_cd_crit()   { l="$(line_with "$1" "$CRIT_ANCHOR")"; [ -n "$l" ] && has "$l" "$SCRATCH_CD"; }
chk_ign_guard() { l="$(line_with "$1" "$GUARD_ANCHOR")"; [ -n "$l" ] && has "$l" "$IGNORED_SNAP" && has "$l" "$CAPTURE_IGNORED"; }
chk_ign_crit()  { l="$(line_with "$1" "$CRIT_ANCHOR")"; [ -n "$l" ] && has "$l" "$IGNORED_SNAP"; }
check_with_mutant "(d) §5 guardrails: every repro runs as cd \"\$SCRATCH\" && …" \
  chk_cd_guard "$REVIEWER" strip_in_line "$GUARD_ANCHOR" "$SCRATCH_CD"
check_with_mutant "(d) Critical Rules bullet: every repro runs as cd \"\$SCRATCH\" && …" \
  chk_cd_crit "$REVIEWER" strip_in_line "$CRIT_ANCHOR" "$SCRATCH_CD"
check_with_mutant "(d) §5 guardrails: before/after snapshot is git status --porcelain --ignored" \
  chk_ign_guard "$REVIEWER" strip_in_line "$GUARD_ANCHOR" "$CAPTURE_IGNORED"
check_with_mutant "(d) Critical Rules bullet: before/after snapshot is git status --porcelain --ignored" \
  chk_ign_crit "$REVIEWER" strip_in_line "$CRIT_ANCHOR" "$IGNORED_SNAP"
# HOME relocation in BOTH carve-out copies (PR #281 review, HIGH): `--ignored` sees only the checkout,
# so a repro of a script whose default target is under $HOME (its settings file, its ui dir)
# would write real user config unseen.
chk_home_both() {
  g="$(line_with "$1" "$GUARD_ANCHOR")"; c="$(line_with "$1" "$CRIT_ANCHOR")"
  [ -n "$g" ] && [ -n "$c" ] && has "$g" "$HOME_RELOC" && has "$c" "$HOME_RELOC"
}
check_with_mutant "(d) both carve-out copies relocate HOME=\"\$SCRATCH/home\"" \
  chk_home_both "$REVIEWER" strip_in_line "$CRIT_ANCHOR" "$HOME_RELOC"
# Honest limit of `--ignored` + the test-integrity-guard fixture rule (PR #281 review, MEDIUM).
chk_overwrite() { l="$(line_with "$1" '**Scratch-dir adversarial repro')"; [ -n "$l" ] && has "$l" "$OVERWRITE_LIMIT" && has "$l" "$COLLAPSE_LIMIT"; }
chk_tig() {
  l="$(line_with "$1" '**Scratch-dir adversarial repro')"
  [ -n "$l" ] && has "$l" "$TIG_RENAME" && has "$l" 'reason `test_integrity_guard`' && has "$l" "$TIG_NOT_DEFECT"
}
check_with_mutant "(d) repro paragraph states --ignored cannot see an overwrite of an existing ignored file" \
  chk_overwrite "$REVIEWER" strip_in_line '**Scratch-dir adversarial repro' "$OVERWRITE_LIMIT"
check_with_mutant "(d) repro paragraph states --ignored cannot see a new file inside an already-ignored dir" \
  chk_overwrite "$REVIEWER" strip_in_line '**Scratch-dir adversarial repro' "$COLLAPSE_LIMIT"
check_with_mutant "(d) repro paragraph: guard-blocked fixture => rename, else unverified; not a PR defect / not NEEDS_HUMAN" \
  chk_tig "$REVIEWER" strip_in_line '**Scratch-dir adversarial repro' "$TIG_NOT_DEFECT"
# Same scope in both places: the SAME canonical literal is asserted in each, so a one-sided edit of the
# scope turns exactly one of the two checks above red. Also refuse the "Sole exception" framing (the
# reviewer already writes one agent-memory proposal file — Plan Review advisory (a)).
chk_not_sole() { ! grep -qF -- 'Sole exception' "$1"; }
check_with_mutant "(d) code-reviewer does not frame the carve-out as the 'Sole exception'" \
  chk_not_sole "$REVIEWER" append_text 'Sole exception: injected by the mutation control.'

# ---- (e) workflow marker ----------------------------------------------------------------------------
chk_marker() {
  LC_ALL=C awk -v m="$MARKER" '{ t = $0; sub(/^[[:space:]]+/, "", t); sub(/[[:space:]]+$/, "", t); if (t == m) hit = 1 } END { exit (hit ? 0 : 1) }' "$1"
}
chk_marker_last() { grep -qF -- 'The LAST line of EVERY comment you post — finding-bearing and no-findings' "$1"; }
check_with_mutant "(e) workflow prompt carries the exact execution: none marker on its own line" \
  chk_marker "$WORKFLOW" del_lines "$MARKER"
check_with_mutant "(e) workflow prompt mandates the marker as the LAST line of every comment" \
  chk_marker_last "$WORKFLOW" del_lines 'The LAST line of EVERY comment you post'

# ---- (f) review-heal static-only consumer -----------------------------------------------------------
chk_static() {
  grep -qF -- 'The CI lens is static-only (`execution: none`)' "$1" \
    && grep -qF -- '`CI review lens: static-only (execution: none)`' "$1" \
    && grep -qF -- "the trigger's DEFINITION above is unchanged" "$1"
}
check_with_mutant "(f) review-heal labels the CI lens static-only and keeps the fallback trigger unchanged" \
  chk_static "$HEAL" del_lines 'The CI lens is static-only'

# ---- (g) standalone /review-pr surfaces never carry the directive ------------------------------------
chk_no_directive() { ! grep -qiF -- 'EXECUTION DIRECTIVE' "$1"; }   # -i: a mixed-case leak counts too (Phase 4.5 review, PR #281)
check_with_mutant "(g) agents/review-pr.md does not carry the EXECUTION DIRECTIVE" \
  chk_no_directive "$RP_AGENT" append_text "$DIRECTIVE_PREFIX — injected by the mutation control)**"
check_with_mutant "(g) commands/review-pr.md does not carry the EXECUTION DIRECTIVE" \
  chk_no_directive "$RP_CMD" append_text "$DIRECTIVE_PREFIX — injected by the mutation control)**"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
