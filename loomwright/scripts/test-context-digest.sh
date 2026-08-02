#!/usr/bin/env bash
# test-context-digest.sh — seam tests for the D6 worker shared-context digest + explicit file
# lanes work (docs/RESULT_SCHEMAS.md §"CONTEXT_DIGEST" names this file as the correctness
# enforcement for: bound honored, truncation marker present, worktree-absolute pointer form,
# and same-wave lane overlap flagged vs sequentially-ordered sharing not flagged).
# Hermetic, offline, bash-3.2 safe (no mapfile, no associative arrays). Auto-registered by
# ci.yml's `loomwright/scripts/test-*.sh` glob. Exit 0 = all pass, non-zero = any failure.
#
# Three groups, matching the three assertions the brief requires:
#   A. Digest bound + truncation marker  — exercises the real build-context-digest.sh builder
#      inside a mktemp sandbox with fixture briefs (never touches the real repo).
#   B. Worktree main-checkout-absolute pointer form — greps the two committed carrier surfaces
#      (skills/async-orchestration/SKILL.md, docs/POINTER_AUDIT.md) for the exact phrase.
#   C. Same-wave lane overlap flagged / sequentially-ordered lane sharing NOT flagged — the
#      Lane Declaration Schema's reachability rule (skills/supervisor-readiness/SKILL.md
#      §"Lane Declaration Schema") is realized as Plan Reviewer Criterion 16, an LLM judgment
#      call with no deterministic implementation elsewhere in the repo. This group tests a
#      small reference implementation of that EXACT algorithm (reachability over the `requires`
#      DAG, transitive closure, direction-agnostic pairwise check) against fixtures, including
#      the specific 2-waves-apart-no-direct-edge regression this brief calls out by name (the
#      naive "no requires edge" phrasing would falsely flag it).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
BUILDER="$HERE/build-context-digest.sh"
ASYNC_SKILL="$REPO_ROOT/loomwright/skills/async-orchestration/SKILL.md"
POINTER_AUDIT="$REPO_ROOT/loomwright/docs/POINTER_AUDIT.md"

[ -f "$BUILDER" ] || { echo "FAIL: builder not found at $BUILDER" >&2; exit 1; }

PASS=0; FAIL=0
ok() { echo "PASS: $1"; PASS=$((PASS+1)); }
no() { echo "FAIL: $1" >&2; FAIL=$((FAIL+1)); }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ctxdigest-test.XXXXXX")"
trap 'rm -rf "$ROOT" 2>/dev/null' EXIT

# =============================================================================
# Group A — digest bound + truncation marker (real builder, sandboxed fixtures)
# =============================================================================

SMALL_BRIEF="$ROOT/small-brief.md"
cat > "$SMALL_BRIEF" <<'EOF'
# Supervisor Job: fixture brief

## Task
A tiny fixture brief well under any reasonable byte cap.

### Subtask Contracts
```yaml
provides:
  - {kind: "file", path: "src/a.ts"}
requires: []
lanes:
  - "src/a.ts"
```
EOF

SMALL_OUT="$ROOT/out/small.md"
bash "$BUILDER" --brief "$SMALL_BRIEF" --out "$SMALL_OUT" --max-chars 6000 >/dev/null 2>&1
RC=$?
if [ "$RC" -eq 0 ] && [ -f "$SMALL_OUT" ] && ! grep -q '^\[context-digest truncated at' "$SMALL_OUT"; then
  ok "under-cap digest: no truncation marker, exit 0"
else
  no "under-cap digest case failed (rc=$RC)"
fi

# Build an oversized brief (a big repeated File Impact Map section) to force truncation with a
# deliberately small --max-chars.
BIG_BRIEF="$ROOT/big-brief.md"
{
  echo "# Supervisor Job: oversized fixture brief"
  echo
  echo "## File Impact Map"
  echo
  i=0
  while [ "$i" -lt 400 ]; do
    echo "| src/file_${i}.ts | modify | some plausible reason text padding this row out |"
    i=$((i+1))
  done
} > "$BIG_BRIEF"

# CAP was 500 until v15.20.0's derived content floor landed. A cap that low can no longer
# produce an honest digest — overhead plus a one-line floor for all five sections needs ~1100 —
# so the builder now (correctly) REFUSES at 500, and this test's premise ("a digest is written
# and is clipped") became unsatisfiable. Raised to the smallest cap that still forces heavy
# clipping on this deliberately oversized brief while remaining fundable. The tier-3 refusal
# itself is asserted separately, in the fail-safe branch cases near the end of this file.
CAP=1200
BIG_OUT="$ROOT/out/big.md"
bash "$BUILDER" --brief "$BIG_BRIEF" --out "$BIG_OUT" --max-chars "$CAP" >/dev/null 2>&1
RC=$?
BIGSIZE="$(wc -c < "$BIG_OUT" 2>/dev/null | tr -d '[:space:]')"
# Clipping must remain VISIBLE, but assert on the CONTRACT ("a clipped digest says it was
# clipped") rather than on which of the two mechanisms fired. Asserting specifically on the
# whole-file backstop marker was wrong: per-section budgeting is the intended path and the
# backstop is documented as "expected NOT to fire in normal operation", so the old assertion
# quietly required the fallback to fire on every run.
if [ "$RC" -eq 0 ] && [ -f "$BIG_OUT" ] \
   && [ -n "$BIGSIZE" ] && [ "$BIGSIZE" -le "$CAP" ] \
   && grep -q -e '_(truncated' -e "\[context-digest truncated at ${CAP} chars\]" "$BIG_OUT"; then
  ok "oversized digest: total output <= cap ($BIGSIZE <= $CAP) and the clip is marked"
else
  no "oversized digest not honored (rc=$RC size=$BIGSIZE)"
fi

# The digest is NEVER unbounded even when a smaller cap is requested again.
CAP2=1000
BIG_OUT2="$ROOT/out/big2.md"
bash "$BUILDER" --brief "$BIG_BRIEF" --out "$BIG_OUT2" --max-chars "$CAP2" >/dev/null 2>&1
BIGSIZE2="$(wc -c < "$BIG_OUT2" 2>/dev/null | tr -d '[:space:]')"
if [ -n "$BIGSIZE2" ] && [ "$BIGSIZE2" -le "$CAP2" ]; then
  ok "a second, different cap ($CAP2) is independently honored — bound is never skipped"
else
  no "second cap not honored (size=$BIGSIZE2 cap=$CAP2)"
fi

# ---------------------------------------------------------------------------
# CAP vs FIXED OVERHEAD. Size-only assertions cannot see the failure these cover: a
# digest of headings and truncation markers with ZERO section content satisfies
# "size <= cap" perfectly while carrying none of the analysis it claims to. Measured
# before the fix: --max-chars 900/1000/1500 each produced three markers and no content
# at all, including the highest-priority Cross-lane contracts section, and the builder
# reported success. The two assertions below are the ones that actually bite.
# ---------------------------------------------------------------------------
CONTRACT_BRIEF="$ROOT/contract-brief.md"
cat > "$CONTRACT_BRIEF" <<'EOF'
# Supervisor Job: contract-bearing fixture

## Subtask contracts

```yaml
subtask_1:
  provides:
    - {kind: file, path: src/alpha/one.ts}
    - {kind: file, path: src/alpha/two.ts}
    - {kind: symbol, path: src/alpha/one.ts, name: AlphaOne}
  requires: []
  lanes:
    - "src/alpha/**"
subtask_2:
  provides:
    - {kind: file, path: src/beta/three.ts}
  requires:
    - {from: "1", kind: symbol, path: src/alpha/one.ts, name: AlphaOne}
  lanes:
    - "src/beta/**"
```
EOF

TIGHT_CAP=1000
TIGHT_OUT="$ROOT/out/tight.md"
bash "$BUILDER" --brief "$CONTRACT_BRIEF" --out "$TIGHT_OUT" --max-chars "$TIGHT_CAP" >/dev/null 2>&1
TIGHTSIZE="$(wc -c < "$TIGHT_OUT" 2>/dev/null | tr -d '[:space:]')"
# Real content under the contracts heading — not a marker, not the explainer, not blank.
CONTRACT_BODY="$(sed -n '/^## Cross-lane producer\/consumer contracts/,$p' "$TIGHT_OUT" 2>/dev/null \
  | grep -c -E '^[[:space:]]*(provides|requires|lanes|subtask_[0-9]+):|^[[:space:]]+- ' || true)"
if [ -n "$TIGHTSIZE" ] && [ "$TIGHTSIZE" -le "$TIGHT_CAP" ] \
   && [ -n "$CONTRACT_BODY" ] && [ "$CONTRACT_BODY" -ge 1 ]; then
  ok "tight cap ($TIGHT_CAP): the highest-priority contracts section carries REAL content ($CONTRACT_BODY lines), not just a marker"
else
  no "tight cap produced a contentless contracts section (size=$TIGHTSIZE contract_body_lines=$CONTRACT_BODY)"
fi

# A cap below the builder's own fixed overhead writes NOTHING and still exits 0. An ABSENT
# digest is honest (every consumer already handles absence — contextDigestPointer returns
# undefined, the spawn contracts all say "proceed without it"); a contentless one claims to
# carry analysis it does not have.
TINY_OUT="$ROOT/out/tiny.md"
rm -f "$TINY_OUT"
TINY_ERR="$(bash "$BUILDER" --brief "$CONTRACT_BRIEF" --out "$TINY_OUT" --max-chars 120 2>&1 >/dev/null)"
TINY_RC=$?
if [ "$TINY_RC" -eq 0 ] && [ ! -f "$TINY_OUT" ] \
   && printf '%s' "$TINY_ERR" | grep -q "below the digest's own fixed overhead"; then
  ok "cap below the fixed overhead: nothing written, reason on stderr, still exit 0 (fail-safe)"
else
  no "sub-overhead cap not refused cleanly (rc=$TINY_RC file_exists=$([ -f "$TINY_OUT" ] && echo yes || echo no) err='$TINY_ERR')"
fi

# =============================================================================
# Group B — worktree main-checkout-absolute pointer form (committed carrier surfaces)
# =============================================================================

if [ -f "$ASYNC_SKILL" ] \
   && grep -q 'Context digest pointer' "$ASYNC_SKILL" \
   && grep -q 'MAIN-CHECKOUT ABSOLUTE path' "$ASYNC_SKILL"; then
  ok "async-orchestration/SKILL.md 'Context digest pointer' states the MAIN-CHECKOUT ABSOLUTE path rule"
else
  no "async-orchestration/SKILL.md missing the MAIN-CHECKOUT ABSOLUTE path pointer rule"
fi

if [ -f "$POINTER_AUDIT" ] \
   && grep -q '### Context digest' "$POINTER_AUDIT" \
   && grep -q 'main-checkout absolute path' "$POINTER_AUDIT"; then
  ok "POINTER_AUDIT.md '### Context digest' states the worktree-absolute pointer rule"
else
  no "POINTER_AUDIT.md missing the worktree-absolute pointer rule under '### Context digest'"
fi

# =============================================================================
# Group C — lane-overlap reachability: reference implementation of the Lane Declaration
# Schema's algorithm (skills/supervisor-readiness/SKILL.md §"Lane Declaration Schema"),
# tested against fixtures. No deterministic implementation exists elsewhere (Criterion 16
# is LLM judgment), so this group is the mechanical proof the algorithm itself is sound.
# =============================================================================

# compute_closure <edges>
#   edges: space-separated "consumer:producer" pairs (a direct `requires` edge: consumer
#   requires producer). Returns the transitive closure as space-separated "X:Y" pairs meaning
#   "Y is reachable from X by following requires edges forward".
compute_closure() {
  local edges="$1"
  local closure="$edges"
  local changed=1 i=0
  while [ "$changed" -eq 1 ] && [ "$i" -lt 10 ]; do
    changed=0
    i=$((i+1))
    local new_pairs=""
    local e1 e2 x y y2 z pair
    for e1 in $closure; do
      x="${e1%%:*}"; y="${e1##*:}"
      for e2 in $edges; do
        y2="${e2%%:*}"; z="${e2##*:}"
        if [ "$y" = "$y2" ]; then
          pair="$x:$z"
          case " $closure $new_pairs " in
            *" $pair "*) : ;;
            *) new_pairs="$new_pairs $pair"; changed=1 ;;
          esac
        fi
      done
    done
    closure="$closure $new_pairs"
  done
  printf '%s' "$closure"
}

# reachable <from> <to> <closure> — true (0) iff <to> is reachable from <from>.
reachable() {
  case " $3 " in
    *" $1:$2 "*) return 0 ;;
    *) return 1 ;;
  esac
}

# ordered <a> <b> <closure> — true (0) iff a and b are sequentially ordered (either direction),
# i.e. they are ORDERED relative to each other, so not a collision ("same-wave" is a
# shorthand for mutual unreachability, not a computable wave index).
ordered() {
  reachable "$1" "$2" "$3" && return 0
  reachable "$2" "$1" "$3" && return 0
  return 1
}

# lane_overlap <lanes_a> <lanes_b> — true (0) iff the two space-separated path lists share a path.
lane_overlap() {
  local p q
  for p in $1; do
    for q in $2; do
      [ "$p" = "$q" ] && return 0
    done
  done
  return 1
}

# collision <a> <b> <lanes_a> <lanes_b> <closure> — true (0) iff this pair is a flaggable
# same-wave lane collision (overlapping lanes AND neither reachable from the other).
collision() {
  lane_overlap "$3" "$4" || return 1
  ordered "$1" "$2" "$5" && return 1
  return 0
}

# --- Fixture 1: directly sequential pair sharing a file — must NOT be flagged ---
CLOSURE_SEQ="$(compute_closure "2:1")"
if collision "1" "2" "shared/file.md common/a.md" "shared/file.md common/b.md" "$CLOSURE_SEQ"; then
  no "directly-sequential shared file (2 requires 1) incorrectly flagged as a collision"
else
  ok "directly-sequential shared file (2 requires 1) correctly NOT flagged"
fi

# --- Fixture 2: same-wave pair (independent, both depend on an unrelated 3rd node) sharing a
#     file — MUST be flagged. ---
CLOSURE_WAVE="$(compute_closure "4:9 5:9")"
if collision "4" "5" "conflict/file.md private/c.md" "conflict/file.md private/d.md" "$CLOSURE_WAVE"; then
  ok "same-wave overlap (4 and 5, both independent of each other) correctly flagged"
else
  no "same-wave overlap (4 and 5) NOT flagged (should have been)"
fi

# --- Fixture 3: the brief's own regression case — 2 waves apart via 1 -> 2 -> 4 (no DIRECT
#     edge between 1 and 4), sharing a file — must NOT be flagged. This is exactly the pair a
#     naive "no requires edge" check would mis-flag; the reachability (transitive closure) rule
#     must not. ---
CLOSURE_BRIEF="$(compute_closure "2:1 3:1 4:2 4:3")"
if collision "1" "4" "loomwright/skills/SKILLS_INDEX.md some/other/path.md" "loomwright/skills/SKILLS_INDEX.md agents/plan-reviewer.md" "$CLOSURE_BRIEF"; then
  no "transitive 2-wave pair (1, 4 via 1->2->4, no direct edge) incorrectly flagged — the naive direct-edge bug"
else
  ok "transitive 2-wave pair (1, 4 via 1->2->4, no direct edge) correctly NOT flagged"
fi

# --- Fixture 4: overlapping lanes but no path actually shared — never flagged regardless of
#     ordering (sanity check that lane_overlap gates the whole check). ---
CLOSURE_NONE="$(compute_closure "")"
if collision "6" "7" "a/only.md" "b/only.md" "$CLOSURE_NONE"; then
  no "disjoint lanes with zero requires edges incorrectly flagged"
else
  ok "disjoint lanes (no shared path) correctly never flagged, independent of ordering"
fi

# =============================================================================
TOTAL=$((PASS + FAIL))
# ---------------------------------------------------------------------------
# Group D — COMMITTED real-layout fixture (durable CI protection).
#
# `.supervisor/jobs/` is GITIGNORED, so a corpus-only test protects nothing in a
# fresh clone or in CI: it would skip forever and silently. This fixture is a
# trimmed real brief carrying the section shapes briefs ACTUALLY use, and it is
# the regression guard for the finding that shipped once already -- the digest
# rendered `_(none found)_` for File Impact Map and Conventions on ~every real
# brief because the extractor was written against Launch Pad's Phase 3 ANALYZE
# *printed template* rather than the assembled brief it is really fed.
# ---------------------------------------------------------------------------
FIXTURE="$REPO_ROOT/loomwright/sdk-spike/test/fixtures/brief-digest-sections.md"
if [ ! -f "$FIXTURE" ]; then
  no "committed digest fixture missing: $FIXTURE"
  TOTAL=$((TOTAL+1))
else
  OUT_D="$(mktemp -t digestfix.XXXXXX)"
  bash "$REPO_ROOT/loomwright/scripts/build-context-digest.sh" \
    --brief "$FIXTURE" --out "$OUT_D" >/dev/null 2>&1
  # Every rendered section must carry real content -- an `_(none found)_` here is
  # precisely the regression this group exists to catch.
  EMPTY_SECTIONS="$(awk '
    /^## /   { sect=$0; getline l; while (l ~ /^[[:space:]]*$/ && (getline l) > 0) ; 
               if (l ~ /none found/) print sect }
  ' "$OUT_D")"
  TOTAL=$((TOTAL+1))
  if [ -z "$EMPTY_SECTIONS" ]; then
    ok "committed fixture: every digest section is populated (no _(none found)_ on a real-layout brief)"
  else
    no "committed fixture: these digest sections rendered empty on a real-layout brief -> $(echo "$EMPTY_SECTIONS" | tr '\n' ' ')"
  fi
  rm -f "$OUT_D"
fi

# ---------------------------------------------------------------------------
# Group E — contract-doc drift guard.
#
# build-context-digest.sh's own header names docs/RESULT_SCHEMAS.md §CONTEXT_DIGEST as
# "the artifact contract this script implements", which makes that section authoritative
# rather than narrative. It went stale inside a single PR: the Tech Stack/Architecture
# grep was deleted as dead code (0/73 briefs matched) and the doc kept describing it.
# This asserts the doc never POSITIVELY claims a source the script no longer reads.
# ---------------------------------------------------------------------------
SCHEMA_DOC="$REPO_ROOT/loomwright/docs/RESULT_SCHEMAS.md"
BUILDER_SRC="$REPO_ROOT/loomwright/scripts/build-context-digest.sh"
TOTAL=$((TOTAL+1))
if [ ! -f "$SCHEMA_DOC" ] || [ ! -f "$BUILDER_SRC" ]; then
  no "contract-doc drift guard: RESULT_SCHEMAS.md or build-context-digest.sh missing"
else
  # Live (non-comment) use of the retired bold-line grep in the builder.
  LIVE_TECHSTACK="$(grep -v '^[[:space:]]*#' "$BUILDER_SRC" | grep -c 'Tech Stack' || true)"
  # A positive doc claim = a CONTEXT_DIGEST line naming Tech Stack WITHOUT negating it.
  DOC_POSITIVE="$(awk '/^## CONTEXT_DIGEST/{f=1} f&&/^## [A-Z]/&&!/CONTEXT_DIGEST/{f=0} f' "$SCHEMA_DOC" \
    | grep 'Tech Stack' | grep -vciE '\*\*Not\*\*|never|no longer|dead code|removed' || true)"
  if [ "$LIVE_TECHSTACK" -eq 0 ] && [ "$DOC_POSITIVE" -eq 0 ]; then
    ok "contract-doc drift guard: RESULT_SCHEMAS §CONTEXT_DIGEST makes no positive claim the builder dropped"
  else
    no "contract-doc drift guard: builder live 'Tech Stack' uses=$LIVE_TECHSTACK, doc positive claims=$DOC_POSITIVE (expected 0/0)"
  fi
fi

# ---------------------------------------------------------------------------
# Group F — NUMBERED brief headings ("## 5. File Impact Map").
#
# extract_section matches with index(heading, want) == 1, a strict PREFIX test, so an
# unstripped section number made every lookup miss and produced a wholly empty digest
# -- measured on 2026-04-25-github-issues-telemetry-system.md: 660 bytes with all five
# sections `_(none found)_` despite the brief carrying every one of them. Silent and total.
# ---------------------------------------------------------------------------
NUMBRIEF="$(mktemp -t numbrief.XXXXXX)"
cat > "$NUMBRIEF" <<'EOF'
# Numbered Brief

## 1. Environment
- **Project:** /tmp/demo

## 2. Subtask Structure

| # | Title | Est. Files | Skills | Status |
|---|-------|-----------|--------|--------|
| 1 | Alpha | 1 modify | x | LAUNCHABLE |

## 3. Skill References
| Subtask | Skills |
|---|---|
| 1 | quality-checklist |
EOF
OUT_F="$(mktemp -t numout.XXXXXX)"
bash "$REPO_ROOT/loomwright/scripts/build-context-digest.sh" --brief "$NUMBRIEF" --out "$OUT_F" >/dev/null 2>&1
EMPTY_N="$(grep -c 'none found' "$OUT_F" 2>/dev/null || true)"
TOTAL=$((TOTAL+1))
# Environment, Subtask Structure and Skill References are all present under NUMBERED
# headings, so Conventions and Sibling-subtask summary must both resolve. Allow the two
# genuinely-absent sections (Interfaces, Cross-lane) to report empty.
if [ "${EMPTY_N:-9}" -le 3 ]; then
  ok "numbered headings (## N. Title) resolve — digest is not wholly empty ($EMPTY_N empty sections)"
else
  no "numbered headings did NOT resolve — $EMPTY_N of 5 sections empty (the silent-total-miss regression)"
fi
rm -f "$NUMBRIEF" "$OUT_F"

# ---------------------------------------------------------------------------
# Group G — `## Interfaces touched` must index BOTH sides of the contract.
#
# The extractor previously anchored on the literal `{kind:`, i.e. it required `kind:`
# to be the FIRST key -- so every `requires` entry (which leads with `from:`) was
# silently skipped, and the section listed only same-subtask `provides`. The bug was
# invisible because the committed fixture's requires-side symbol is ALSO provided by a
# sibling, so dedup hid it, and no test asserted section CONTENT -- only non-emptiness.
# This fixture uses a requires-only symbol that appears in no `provides` anywhere.
# ---------------------------------------------------------------------------
IFBRIEF="$(mktemp -t ifbrief.XXXXXX)"
cat > "$IFBRIEF" <<'EOF'
# Interfaces Both Sides

## Subtask Structure

| # | Title | Est. Files | Skills | Status |
|---|-------|-----------|--------|--------|
| 1 | Alpha | 1 modify | x | LAUNCHABLE |

### Subtask contracts

```yaml
subtask_1:
  provides:
    - {kind: "symbol", path: "src/mine.ts", name: "PROVIDES_SIDE_SYMBOL"}
  requires:
    - {from: "9", kind: "symbol", path: "vendor/lib.ts", name: "REQUIRES_SIDE_SYMBOL"}
  lanes: ["src/mine.ts"]
```
EOF
OUT_G="$(mktemp -t ifout.XXXXXX)"
bash "$REPO_ROOT/loomwright/scripts/build-context-digest.sh" --brief "$IFBRIEF" --out "$OUT_G" >/dev/null 2>&1
IFSEC="$(sed -n '/^## Interfaces touched/,/^## /p' "$OUT_G")"
TOTAL=$((TOTAL+1))
if printf '%s' "$IFSEC" | grep -q 'PROVIDES_SIDE_SYMBOL' \
   && printf '%s' "$IFSEC" | grep -q 'REQUIRES_SIDE_SYMBOL'; then
  ok "Interfaces touched indexes BOTH provides-side and requires-side symbols (key-order independent)"
else
  no "Interfaces touched dropped a side — provides:$(printf '%s' "$IFSEC" | grep -c 'PROVIDES_SIDE_SYMBOL') requires:$(printf '%s' "$IFSEC" | grep -c 'REQUIRES_SIDE_SYMBOL') (requires entries lead with from:, so a '{kind:'-anchored match silently skips them)"
fi
rm -f "$IFBRIEF" "$OUT_G"

# ---------------------------------------------------------------------------
# CORPUS REGRESSION GATE (v15.20.0 review round 2).
#
# Three defects shipped past the fixture suite because every fixture is small enough
# that neither the pool nor the byte/char divergence ever binds. They were only visible
# by replaying the builder over the REAL archived brief corpus, which is also this
# repo's standing lesson: an extractor over repo-authored markdown must be validated
# against `.supervisor/jobs/`, never against a fixture alone.
#
#   1. NO CONTENTLESS SECTION. Strict priority order let the first section eat the whole
#      pool; every later section rendered as a bare `_(truncated)_` with ZERO content.
#      Measured before the floor pass: 15 of 72 briefs, worst case 4 of 5 sections.
#   2. NO OVER-CAP FILE. Budgets were counted in CHARACTERS (`${#var}` under UTF-8) while
#      the cap is enforced in BYTES (`wc -c`); the assembled digest overshot MAX.
#   3. BACKSTOP MUST NOT FIRE. It clips the TAIL, i.e. deletes from `## Cross-lane
#      producer/consumer contracts` — the section the priority ordering exists to protect.
#      It is documented as "expected NOT to fire in normal operation"; assert that.
#
# Skips silently when no corpus is present (a fresh clone / a consumer's repo).
# ---------------------------------------------------------------------------
# The corpus sweep runs under a PINNED UTF-8 locale. `${#var}` is a byte count under C/POSIX
# and a CHARACTER count under UTF-8, so a suite inheriting the C locale (which is what a bare
# CI shell often has) would pass even if the byte-safe `blen()` regressed back to `${#var}` —
# the exact defect class the gate is here to pin. Falls back to whatever locale is available:
# an unsupported LC_ALL is ignored by libc, which degrades to today's behavior, never an error.
CORPUS_LOCALE="en_US.UTF-8"
CORPUS_N=0; CORPUS_STARVED=""; CORPUS_OVER=""; CORPUS_BACKSTOP=""; CORPUS_BADUTF8=""
for _cb in "$REPO_ROOT"/.supervisor/jobs/done/*.md "$REPO_ROOT"/.supervisor/jobs/pending/*.md "$REPO_ROOT"/.supervisor/jobs/failed/*.md; do
  [ -f "$_cb" ] || continue
  _co="$(mktemp -t corpusdg.XXXXXX)"
  LC_ALL="$CORPUS_LOCALE" bash "$REPO_ROOT/loomwright/scripts/build-context-digest.sh" --brief "$_cb" --out "$_co" >/dev/null 2>&1
  [ -s "$_co" ] || { rm -f "$_co"; continue; }
  CORPUS_N=$((CORPUS_N+1))
  _csz="$(wc -c < "$_co" | tr -d '[:space:]')"
  [ "$_csz" -gt 6000 ] && CORPUS_OVER="$CORPUS_OVER $(basename "$_cb")($_csz)"
  grep -q 'context-digest truncated at' "$_co" && CORPUS_BACKSTOP="$CORPUS_BACKSTOP $(basename "$_cb")"
  # A section is contentless when the line two below its `## ` heading is the marker itself.
  _cn="$(awk '/^## /{getline; getline; if ($0 ~ /^_\(truncated/) c++} END{print c+0}' "$_co")"
  [ "$_cn" -gt 0 ] && CORPUS_STARVED="$CORPUS_STARVED $(basename "$_cb")($_cn)"
  # `clip`/backstop cut with `head -c`, a RAW BYTE offset with no character-boundary awareness,
  # so a cut can land mid-sequence in a multi-byte character. Today the trailing `sed '$d'`
  # removes the partial line that byte necessarily sits on, so no malformed byte reaches the
  # digest — but that is an emergent property of the pipeline, not something either half
  # promises. Assert the OUTCOME (every digest decodes as UTF-8) rather than the mechanism, so
  # a future change to either the cut or the `sed` is caught here instead of shipping mojibake.
  python3 -c 'import sys; open(sys.argv[1], encoding="utf-8").read()' "$_co" 2>/dev/null \
    || CORPUS_BADUTF8="$CORPUS_BADUTF8 $(basename "$_cb")"
  rm -f "$_co"
done

if [ "$CORPUS_N" -eq 0 ]; then
  echo "SKIP: no archived brief corpus under .supervisor/jobs/ — corpus regression gate not run"
else
  TOTAL=$((TOTAL+1))
  if [ -z "$CORPUS_STARVED" ]; then
    ok "corpus ($CORPUS_N briefs): no digest section is a bare truncation marker with zero content"
  else
    no "corpus: contentless section(s) —$CORPUS_STARVED (the per-section floor pass in build-context-digest.sh regressed: strict priority order starves later sections to a bare marker)"
  fi

  TOTAL=$((TOTAL+1))
  if [ -z "$CORPUS_OVER" ]; then
    ok "corpus ($CORPUS_N briefs): every digest is within the 6000-byte cap"
  else
    no "corpus: digest exceeded the byte cap —$CORPUS_OVER (budgets must be measured with blen(), not \${#var}: the latter counts CHARACTERS under UTF-8 while the cap is BYTES)"
  fi

  TOTAL=$((TOTAL+1))
  if [ -z "$CORPUS_BACKSTOP" ]; then
    ok "corpus ($CORPUS_N briefs): whole-file backstop never fires (per-section budgeting holds)"
  else
    no "corpus: whole-file backstop fired on —$CORPUS_BACKSTOP (it clips the TAIL, deleting the cross-lane contracts section the priority order protects; per-section budgeting should make it unreachable)"
  fi

  TOTAL=$((TOTAL+1))
  if [ -z "$CORPUS_BADUTF8" ]; then
    ok "corpus ($CORPUS_N briefs, LC_ALL=$CORPUS_LOCALE): every digest is valid UTF-8 (no head -c cut leaks a split multi-byte character)"
  else
    no "corpus: digest contains invalid UTF-8 —$CORPUS_BADUTF8 (head -c cuts at a raw byte offset; the trailing sed '\$d' is what removes the split character's partial line — if either changed, clip on a character boundary instead)"
  fi
fi

# Multi-byte content clipped at many boundaries: brute-force every cap in a window so a cut
# lands mid-character repeatedly. The corpus gate above is data-dependent; this one is not.
MBBRIEF="$(mktemp -t mbbrief.XXXXXX)"
{
  printf '# Multi-byte Truncation — Fixture\n\n## Environment\n\n'
  i=0
  while [ "$i" -lt 60 ]; do
    printf -- '- Convention %s — uses “smart quotes”, ≤ and ≥ bounds, § refs, and an em-dash — here.\n' "$i"
    i=$(( i + 1 ))
  done
  printf '\n## Subtask Structure\n\n| # | Title | Est. Files | Skills | Status |\n|---|---|---|---|---|\n| 1 | Ä — ü | 1 | x | LAUNCHABLE |\n'
} > "$MBBRIEF"
MB_BAD=""
_cap=1400
while [ "$_cap" -le 2400 ]; do
  MBOUT="$(mktemp -t mbout.XXXXXX)"
  LC_ALL="$CORPUS_LOCALE" bash "$REPO_ROOT/loomwright/scripts/build-context-digest.sh" \
    --brief "$MBBRIEF" --out "$MBOUT" --max-chars "$_cap" >/dev/null 2>&1
  if [ -s "$MBOUT" ]; then
    _sz="$(wc -c < "$MBOUT" | tr -d '[:space:]')"
    [ "$_sz" -gt "$_cap" ] && MB_BAD="$MB_BAD cap$_cap:over($_sz)"
    python3 -c 'import sys; open(sys.argv[1], encoding="utf-8").read()' "$MBOUT" 2>/dev/null \
      || MB_BAD="$MB_BAD cap$_cap:badutf8"
  fi
  rm -f "$MBOUT"
  _cap=$(( _cap + 37 ))   # prime-ish stride so cuts land on many different byte offsets
done
TOTAL=$((TOTAL+1))
if [ -z "$MB_BAD" ]; then
  ok "multi-byte fixture: 28 caps swept (1400..2400) — every digest is valid UTF-8 and within its cap"
else
  no "multi-byte fixture failures:$MB_BAD (a truncation boundary landed inside a multi-byte character, or the byte cap was exceeded)"
fi
rm -f "$MBBRIEF"

# Decoy heading must not steal a section from the real one (word-boundary guard in
# extract_section). Without it, `## File Impact Mapping (draft)` appearing BEFORE the real
# `## File Impact Map` starts extraction on the decoy, and the `if (on) exit` at the next
# heading — which IS the real target — ships the decoy's body instead.
DECOYBRIEF="$(mktemp -t decoybrief.XXXXXX)"
cat > "$DECOYBRIEF" <<'EOF'
# Decoy Heading Fixture

## File Impact Mapping (draft, ignore)

DECOY_BODY_MUST_NOT_APPEAR

## File Impact Map

| File | Change |
|---|---|
| REAL_TARGET_BODY.ts | modify |

## Subtask Structure

| # | Title | Est. Files | Skills | Status |
|---|---|---|---|---|
| 1 | A | 1 | x | LAUNCHABLE |
EOF
DECOYOUT="$(mktemp -t decoyout.XXXXXX)"
bash "$REPO_ROOT/loomwright/scripts/build-context-digest.sh" --brief "$DECOYBRIEF" --out "$DECOYOUT" >/dev/null 2>&1
DECOYSEC="$(sed -n '/^## File Impact Map$/,/^## Interfaces/p' "$DECOYOUT")"
TOTAL=$((TOTAL+1))
if printf '%s' "$DECOYSEC" | grep -q 'REAL_TARGET_BODY' \
   && ! printf '%s' "$DECOYSEC" | grep -q 'DECOY_BODY_MUST_NOT_APPEAR'; then
  ok "prefix-decoy heading does not steal the section — 'File Impact Mapping' is not 'File Impact Map'"
else
  no "prefix-decoy heading stole the section: extract_section's index()==1 prefix test needs a word-boundary guard (matched body: $(printf '%s' "$DECOYSEC" | tr '\n' ' ' | cut -c1-160))"
fi
rm -f "$DECOYBRIEF" "$DECOYOUT"

# `--brief -` must never block on a terminal. The original stdin branch read
# `elif [ -n "$BRIEF_ARG" ] || [ ! -t 0 ]`, whose FIRST disjunct short-circuits: an explicit `-`
# entered the branch regardless of whether stdin was a pipe, so `cat` blocked forever on a tty.
# A hang is not a permitted outcome under this script's fail-safe contract ("any internal error
# => write nothing, message to stderr, exit 0").
#
# THIS ASSERTION IS STRUCTURAL, NOT BEHAVIORAL — stated plainly rather than implied. Reproducing
# the hang needs a real controlling terminal; `pty.fork()` proved unreliable in sandboxed/CI
# runners (it hung the harness rather than the subject), and a test that can hang the suite is
# worse than the bug it guards. So this greps the guard's SHAPE instead: the tty test must not
# sit behind a `[ -n "$BRIEF_ARG" ] ||` short-circuit. It would NOT catch a different rewrite
# that reintroduces the hang by another route — the two behavioral halves below (a real pipe
# still works, and `-` on a non-tty still works) are what cover the paths that ARE testable here.
TOTAL=$((TOTAL+1))
_STDIN_BRANCH="$(grep -n 'elif \[ ! -t 0 \]' "$REPO_ROOT/loomwright/scripts/build-context-digest.sh" || true)"
_STDIN_SHORTCIRCUIT="$(grep -n 'elif \[ -n "\$BRIEF_ARG" \] || \[ ! -t 0 \]' "$REPO_ROOT/loomwright/scripts/build-context-digest.sh" || true)"
if [ -n "$_STDIN_BRANCH" ] && [ -z "$_STDIN_SHORTCIRCUIT" ]; then
  ok "stdin branch gates on \`[ ! -t 0 ]\` unconditionally (structural check — \`--brief -\` cannot short-circuit past the tty test and hang)"
else
  no "stdin branch reintroduced the \`[ -n \"\$BRIEF_ARG\" ] ||\` short-circuit — \`--brief -\` with no piped input will \`cat\` a terminal and hang, violating the always-exit-0 fail-safe contract"
fi

# Behavioral half 1: a real pipe still feeds the builder (the path Launch Pad never uses but the
# docstring documents). Behavioral half 2: `--brief -` on a non-tty stdin behaves identically.
for _form in "" "-"; do
  TOTAL=$((TOTAL+1))
  PIPEOUT="$(mktemp -t pipeout.XXXXXX)"
  if [ -z "$_form" ]; then
    printf '# Piped Brief\n\n## Environment\n\nPIPED_MARKER_OK\n' | bash "$REPO_ROOT/loomwright/scripts/build-context-digest.sh" --out "$PIPEOUT" >/dev/null 2>&1
    _label="STDIN with no --brief"
  else
    printf '# Piped Brief\n\n## Environment\n\nPIPED_MARKER_OK\n' | bash "$REPO_ROOT/loomwright/scripts/build-context-digest.sh" --brief - --out "$PIPEOUT" >/dev/null 2>&1
    _label="--brief - with a pipe"
  fi
  if [ -s "$PIPEOUT" ] && grep -q 'PIPED_MARKER_OK' "$PIPEOUT"; then
    ok "$_label still reads the piped brief (the tty guard did not break the legitimate pipe path)"
  else
    no "$_label produced no digest — the unconditional \`[ ! -t 0 ]\` guard broke the legitimate piped-input path it was meant to leave alone"
  fi
  rm -f "$PIPEOUT"
done

# ---------------------------------------------------------------------------
# FAIL-SAFE ARGUMENT BRANCHES. Each of these looked correct on read but had no case, and the
# whole contract of this builder is that a bad argument degrades to "nothing written, message on
# stderr, exit 0" rather than a crash, a hang, or a junk digest. An always-exit-0 script is
# exactly the shape where an untested error branch fails SILENTLY, so assert all three signals
# together: exit status, no output file, and a non-empty stderr explanation.
# ---------------------------------------------------------------------------
_failsafe() {   # <label> <expect: none|written> <args...>
  _fs_label="$1"; _fs_expect="$2"; shift 2
  _fs_out="$(mktemp -u -t fsout.XXXXXX)"
  _fs_err="$(mktemp -t fserr.XXXXXX)"
  bash "$REPO_ROOT/loomwright/scripts/build-context-digest.sh" "$@" --out "$_fs_out" \
    >/dev/null 2>"$_fs_err" </dev/null
  _fs_rc=$?
  TOTAL=$((TOTAL+1))
  if [ "$_fs_rc" -ne 0 ]; then
    no "$_fs_label: exited $_fs_rc — the builder must ALWAYS exit 0 (fail-safe contract)"
  elif [ "$_fs_expect" = "none" ] && [ -e "$_fs_out" ]; then
    no "$_fs_label: wrote a digest when it should have written nothing"
  elif [ "$_fs_expect" = "none" ] && [ ! -s "$_fs_err" ]; then
    no "$_fs_label: wrote nothing but explained nothing on stderr — a silent no-op is indistinguishable from success"
  elif [ "$_fs_expect" = "written" ] && [ ! -s "$_fs_out" ]; then
    no "$_fs_label: expected a digest (the bad value should fall back to the default), got none"
  else
    ok "$_fs_label"
  fi
  rm -f "$_fs_out" "$_fs_err"
}

_failsafe "--brief with a nonexistent path: nothing written, reason on stderr, exit 0" none \
  --brief "$REPO_ROOT/definitely/not/a/real/brief-$$.md"
_failsafe "--max-chars non-numeric ('abc'): falls back to the 6000 default and still builds" written \
  --brief "$REPO_ROOT/loomwright/sdk-spike/test/fixtures/brief-digest-sections.md" --max-chars abc
_failsafe "--max-chars 0: falls back to the default rather than producing an empty digest" written \
  --brief "$REPO_ROOT/loomwright/sdk-spike/test/fixtures/brief-digest-sections.md" --max-chars 0
_failsafe "--max-chars negative (-5): falls back to the default" written \
  --brief "$REPO_ROOT/loomwright/sdk-spike/test/fixtures/brief-digest-sections.md" --max-chars -5
_failsafe "--max-chars 30 (below the _min_cap floor of 60): falls back to the default" written \
  --brief "$REPO_ROOT/loomwright/sdk-spike/test/fixtures/brief-digest-sections.md" --max-chars 30
# Distinct from the floor above: 700 CLEARS _min_cap (60) but cannot fund the real fixed
# overhead plus a content floor for all five sections. Tier 3 refuses rather than shipping a
# digest of headings and empty markers.
_failsafe "--max-chars 700 (clears _min_cap, below overhead + content floor): tier 3 refuses, nothing written" none \
  --brief "$REPO_ROOT/loomwright/sdk-spike/test/fixtures/brief-digest-sections.md" --max-chars 700

# ---------------------------------------------------------------------------
# TIGHT-CAP BOUNDARY SWEEP — the invariant is "written implies honest", at EVERY cap.
#
# The corpus gate above only ever exercises the 6000-byte default, so the whole tight-cap
# region went unswept. It was not clean: at 700/800/900 tier 2's overhead shrink pushed POOL
# just above zero, tier 3 (then checking only `POOL < 1`) let it through, and the result was a
# digest with 4 of 5 sections a bare marker — precisely what tier 3 exists to refuse. A second
# round then showed one section still starving wherever its first LINE exceeded the granted
# floor, because `clip` cuts on line boundaries.
#
# So assert the property directly, at every cap in the region: a digest that gets WRITTEN must
# have zero contentless sections, sit within its own cap, never need the whole-file backstop,
# and decode as UTF-8. Refusing is always an acceptable answer — an absent digest is honest.
# ---------------------------------------------------------------------------
SWEEP_BAD=""; SWEEP_WROTE=0; SWEEP_REFUSED=0
_sc=650
while [ "$_sc" -le 2600 ]; do
  SWOUT="$(mktemp -t swout.XXXXXX)"
  LC_ALL="$CORPUS_LOCALE" bash "$REPO_ROOT/loomwright/scripts/build-context-digest.sh" \
    --brief "$REPO_ROOT/loomwright/sdk-spike/test/fixtures/brief-digest-sections.md" \
    --out "$SWOUT" --max-chars "$_sc" >/dev/null 2>&1 </dev/null
  if [ -s "$SWOUT" ]; then
    SWEEP_WROTE=$((SWEEP_WROTE+1))
    _ssz="$(wc -c < "$SWOUT" | tr -d '[:space:]')"
    _sn="$(awk '/^## /{getline; getline; if ($0 ~ /^_\(truncated/) c++} END{print c+0}' "$SWOUT")"
    [ "$_sn" -gt 0 ]        && SWEEP_BAD="$SWEEP_BAD cap$_sc:contentless($_sn)"
    [ "$_ssz" -gt "$_sc" ]  && SWEEP_BAD="$SWEEP_BAD cap$_sc:over($_ssz)"
    grep -q 'context-digest truncated at' "$SWOUT" && SWEEP_BAD="$SWEEP_BAD cap$_sc:backstop"
    python3 -c 'import sys; open(sys.argv[1], encoding="utf-8").read()' "$SWOUT" 2>/dev/null \
      || SWEEP_BAD="$SWEEP_BAD cap$_sc:badutf8"
  else
    SWEEP_REFUSED=$((SWEEP_REFUSED+1))
  fi
  rm -f "$SWOUT"
  _sc=$(( _sc + 50 ))
done
TOTAL=$((TOTAL+1))
if [ -z "$SWEEP_BAD" ]; then
  ok "tight-cap sweep (650..2600, $SWEEP_WROTE written / $SWEEP_REFUSED refused): every WRITTEN digest is contentless-free, within cap, backstop-free and valid UTF-8"
else
  no "tight-cap sweep failures:$SWEEP_BAD — a written digest must be honest at every cap (refusing is fine; shipping headings with no data behind them is not)"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "ALL TESTS PASSED ($PASS/$TOTAL)"
  exit 0
else
  echo "TESTS FAILED ($FAIL of $TOTAL failed)" >&2
  exit 1
fi
