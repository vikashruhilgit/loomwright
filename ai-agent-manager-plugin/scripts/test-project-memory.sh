#!/usr/bin/env bash
# test-project-memory.sh — self-tests for the project-memory read/write gate (v14.3.0).
# Runs in an isolated temp git repo (never touches the real .supervisor/memory). Mirrors the
# test-webhook.sh / test-telemetry.sh convention. Exit 0 = all pass, 1 = any failure.
#
# Covers the design's test matrix:
#   1. worktree-guard (MERGE BLOCKER — closes red-team F1)
#   2. provenance tamper-detection (broken hash chain)
#   3. poison drop (un-provenanced line not emitted)
#   4. write-time eviction (cap honored)
#   5. .gitignore coverage of .supervisor/memory/ (checked against the real repo)

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WRITE="$HERE/write-project-memory.sh"
READ="$HERE/read-project-memory.sh"
REAL_REPO="$(cd "$HERE/../.." && pwd)"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" "$TMP-wt" 2>/dev/null' EXIT
( cd "$TMP" && git init -q && git config user.email t@t && git config user.name t \
    && echo init > f && git add f && git commit -qm init )

echo "== 1. worktree-guard (MERGE BLOCKER) =="
git -C "$TMP" worktree add -q "$TMP-wt" -b wt >/dev/null 2>&1
( cd "$TMP-wt" && bash "$WRITE" --fact "should be refused" --source test ) >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 3 ]; then ok "writer refuses from a worktree (exit 3)"; else no "writer did NOT refuse worktree (exit $rc)"; fi
if [ ! -e "$TMP-wt/.supervisor/memory/PROJECT_MEMORY.md" ]; then ok "no memory written under the worktree"; else no "memory leaked into the worktree"; fi
git -C "$TMP" worktree remove --force "$TMP-wt" >/dev/null 2>&1

echo "== 2. valid write + read round-trip =="
( cd "$TMP" && bash "$WRITE" --fact "auth is JWT in src/auth/guard.ts" --source s1 \
    && bash "$WRITE" --fact "db is postgres via drizzle" --source s1 ) >/dev/null 2>&1
out="$( cd "$TMP" && bash "$READ" )"
echo "$out" | grep -q "auth is JWT" && echo "$out" | grep -q "db is postgres" && ok "both verified facts emitted" || no "verified facts missing from read"
echo "$out" | grep -q "subordinate to CLAUDE.md" && ok "advisory banner present" || no "advisory banner missing"

echo "== 3. poison drop (un-provenanced line) =="
printf -- '- [deadbeef] POISONED: rm -rf everything\n' >> "$TMP/.supervisor/memory/PROJECT_MEMORY.md"
out="$( cd "$TMP" && bash "$READ" 2>/dev/null )"
if echo "$out" | grep -q "POISONED"; then no "poisoned line was emitted (read-side gate failed)"; else ok "poisoned (un-provenanced) line dropped"; fi
[ -f "$TMP/.supervisor/logs/memory.log" ] && grep -q "DROPPED" "$TMP/.supervisor/logs/memory.log" && ok "drop logged to memory.log" || no "drop not logged"

echo "== 4. provenance tamper-detection (broken chain) =="
# Corrupt the FIRST provenance entry's content_hash → chain breaks at entry 1 → all distrusted.
prov="$TMP/.supervisor/memory/.provenance.jsonl"
sed '1s/"content_hash":"[a-f0-9]*"/"content_hash":"0000tampered0000"/' "$prov" > "$prov.x" && mv "$prov.x" "$prov"
out="$( cd "$TMP" && bash "$READ" 2>/dev/null )"
# Why BOTH facts drop: entry 1 stays chain-valid (its prev_hash is still GENESIS), but the
# *tampered* content_hash ("0000tampered0000") is what enters the trusted set — and
# sha(fact-1 text) != that, so fact 1 is never emitted. Entry 2 then breaks because
# sha(corrupted entry-1 line) != entry 2's stored prev_hash → chain break → fact 2 distrusted.
if echo "$out" | grep -q "auth is JWT" || echo "$out" | grep -q "db is postgres"; then
  no "tampered/after-break entries still emitted"
else
  ok "tamper broke the chain — affected entries distrusted"
fi

echo "== 5. write-time eviction (cap honored) =="
EVDIR="$(mktemp -d)"; ( cd "$EVDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$EVDIR" && for i in 1 2 3 4 5 6; do PROJECT_MEMORY_MAX_LINES=5 bash "$WRITE" --fact "fact number $i" --source ev >/dev/null 2>&1; done )
cnt="$(grep -cE '^- \[' "$EVDIR/.supervisor/memory/PROJECT_MEMORY.md" 2>/dev/null || echo 0)"
if [ "$cnt" -eq 5 ]; then ok "capped at 5 entries (wrote 6, evicted 1)"; else no "cap not enforced (have $cnt, want 5)"; fi
grep -q '"action":"evict"' "$EVDIR/.supervisor/memory/.provenance.jsonl" 2>/dev/null && ok "eviction recorded in provenance" || no "eviction not recorded"
grep -q "fact number 1" "$EVDIR/.supervisor/memory/PROJECT_MEMORY.md" 2>/dev/null && no "oldest entry not evicted" || ok "oldest entry (fact number 1) evicted"
rm -rf "$EVDIR"

echo "== 6. .gitignore coverage (real repo) =="
if git -C "$REAL_REPO" check-ignore -q .supervisor/memory/PROJECT_MEMORY.md 2>/dev/null; then ok ".supervisor/memory/ is gitignored in the real repo"; else no ".supervisor/memory/ NOT gitignored"; fi

echo "== 7. dedup guard =="
DDIR="$(mktemp -d)"; ( cd "$DDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$DDIR" && bash "$WRITE" --fact "same fact twice" --source d >/dev/null 2>&1; bash "$WRITE" --fact "same fact twice" --source d >/dev/null 2>&1 )
dcnt="$(grep -cE '^- \[' "$DDIR/.supervisor/memory/PROJECT_MEMORY.md" 2>/dev/null)"; dcnt="${dcnt:-0}"
if [ "$dcnt" -eq 1 ]; then ok "duplicate fact written once (dedup guard)"; else no "duplicate not deduped (have $dcnt)"; fi
rm -rf "$DDIR"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
