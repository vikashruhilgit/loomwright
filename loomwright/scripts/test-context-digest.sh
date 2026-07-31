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

CAP=500
BIG_OUT="$ROOT/out/big.md"
bash "$BUILDER" --brief "$BIG_BRIEF" --out "$BIG_OUT" --max-chars "$CAP" >/dev/null 2>&1
RC=$?
BIGSIZE="$(wc -c < "$BIG_OUT" 2>/dev/null | tr -d '[:space:]')"
LASTLINE="$(tail -n 1 "$BIG_OUT" 2>/dev/null)"
if [ "$RC" -eq 0 ] && [ -f "$BIG_OUT" ] \
   && [ -n "$BIGSIZE" ] && [ "$BIGSIZE" -le "$CAP" ] \
   && [ "$LASTLINE" = "[context-digest truncated at ${CAP} chars]" ]; then
  ok "oversized digest: total output <= cap ($BIGSIZE <= $CAP), exact truncation marker is the final line"
else
  no "oversized digest not honored (rc=$RC size=$BIGSIZE last='$LASTLINE')"
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

if [ "$FAIL" -eq 0 ]; then
  echo "ALL TESTS PASSED ($PASS/$TOTAL)"
  exit 0
else
  echo "TESTS FAILED ($FAIL of $TOTAL failed)" >&2
  exit 1
fi
