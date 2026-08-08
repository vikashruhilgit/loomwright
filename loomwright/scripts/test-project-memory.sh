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
# Post-eviction read-back: the eviction entry's prev_hash MUST be computed the same way the
# reader walks the chain (sha of the line WITHOUT its trailing newline). If it isn't, the chain
# breaks at the first evict entry and the reader distrusts every later `add` — silently dropping
# all surviving facts once enough writes push them past the first eviction. Cap=3 with 7 writes
# guarantees every survivor (facts 5,6,7) was added AFTER the first eviction entry, so a broken
# chain emits 0 survivors. The file-count check above can't catch this — only a read-back can.
EV2DIR="$(mktemp -d)"; ( cd "$EV2DIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$EV2DIR" && for i in 1 2 3 4 5 6 7; do PROJECT_MEMORY_MAX_LINES=3 bash "$WRITE" --fact "fact number $i" --source ev >/dev/null 2>&1; done )
evout="$( cd "$EV2DIR" && bash "$READ" 2>/dev/null )"
evsurv="$(echo "$evout" | grep -cE '^- \[')"; evsurv="${evsurv:-0}"
if [ "$evsurv" -eq 3 ] && echo "$evout" | grep -q "fact number 5" && echo "$evout" | grep -q "fact number 7"; then
  ok "post-eviction survivors verify and read back (chain intact across evictions)"
else
  no "post-eviction survivors dropped by reader (have $evsurv verified, want 3 — eviction broke the hash chain)"
fi
rm -rf "$EVDIR" "$EV2DIR"

echo "== 6. .gitignore coverage (real repo) =="
# INVERTED ON PURPOSE (2026-08-07) — same reversal as test-lessons.sh, and for the same reason.
# `/setup memory` exists to make `.supervisor/memory/` COMMITTABLE; this repo applied the managed
# negation block, so "is gitignored" is now the failure mode, not the invariant. Ownership of the
# store's ignore status sits in test-committed-twin-scrub.sh; this is a cheap cross-check.
#
# `-q` is used ALONE — never with `--verbose`, which git rejects with exit 128, a status a bare
# `if` would silently read as "not ignored".
if git -C "$REAL_REPO" check-ignore -q .supervisor/memory/PROJECT_MEMORY.md 2>/dev/null; then
  no ".supervisor/memory/PROJECT_MEMORY.md is IGNORED in the real repo, but the applied /setup memory managed block must make it committable — the negation is not in effect (see test-committed-twin-scrub.sh)"
else
  ok ".supervisor/memory/PROJECT_MEMORY.md is committable in the real repo (managed negation block in effect)"
fi

echo "== 7. dedup guard =="
DDIR="$(mktemp -d)"; ( cd "$DDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$DDIR" && bash "$WRITE" --fact "same fact twice" --source d >/dev/null 2>&1; bash "$WRITE" --fact "same fact twice" --source d >/dev/null 2>&1 )
dcnt="$(grep -cE '^- \[' "$DDIR/.supervisor/memory/PROJECT_MEMORY.md" 2>/dev/null)"; dcnt="${dcnt:-0}"
if [ "$dcnt" -eq 1 ]; then ok "duplicate fact written once (dedup guard)"; else no "duplicate not deduped (have $dcnt)"; fi
rm -rf "$DDIR"

echo "== 8. retract / supersede correction path =="
RDIR="$(mktemp -d)"; ( cd "$RDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$RDIR" && bash "$WRITE" --fact "the sky is green" --source r >/dev/null 2>&1 \
               && bash "$WRITE" --fact "keep me" --source r >/dev/null 2>&1 )
wid="$(sed -nE 's/^- \[([^]]+)\] the sky is green$/\1/p' "$RDIR/.supervisor/memory/PROJECT_MEMORY.md")"
[ -n "$wid" ] && ok "wrong fact stored as [$wid]" || no "could not resolve id of the wrong fact"

# 8a. unknown id aborts with state untouched (fail closed, never half-write)
before="$(cat "$RDIR/.supervisor/memory/.provenance.jsonl")"
( cd "$RDIR" && bash "$WRITE" --retract deadbeef --source r ) >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ] && [ "$before" = "$(cat "$RDIR/.supervisor/memory/.provenance.jsonl")" ]; then
  ok "retract of an unknown id aborts (exit $rc) leaving provenance untouched"
else
  no "retract of an unknown id did not fail closed (exit $rc)"
fi
# 8b. non-hex id is rejected before it reaches a grep/sed pattern
( cd "$RDIR" && bash "$WRITE" --retract '.*' --source r ) >/dev/null 2>&1
[ $? -eq 2 ] && ok "non-hex retract id rejected" || no "non-hex retract id accepted"

# 8c. supersede: corrected fact in, wrong fact out, unrelated fact untouched — one atomic call
( cd "$RDIR" && bash "$WRITE" --fact "the sky is blue" --supersedes "$wid" --source r ) >/dev/null 2>&1
rout="$( cd "$RDIR" && bash "$READ" 2>/dev/null )"
echo "$rout" | grep -q "the sky is blue" && ok "superseding fact emitted" || no "superseding fact missing"
echo "$rout" | grep -q "the sky is green" && no "retracted fact still emitted" || ok "retracted fact gone"
echo "$rout" | grep -q "keep me"          && ok "unrelated fact survives supersede" || no "unrelated fact lost"
rcnt="$(echo "$rout" | grep -cE '^- \[')"; rcnt="${rcnt:-0}"
[ "$rcnt" -eq 2 ] && ok "count correct after supersede (2 verified)" || no "wrong count after supersede (have $rcnt, want 2)"

# 8d. THE READ-SIDE POINT: the original `add` lives forever in the append-only provenance log,
# so a writer-only retraction (line deletion) would leave the wrong fact's content_hash trusted
# and an out-of-band re-append would read back as VERIFIED. Only the reader's retract branch
# closes this. Without it, this assertion fails.
printf -- '- [%s] the sky is green\n' "$wid" >> "$RDIR/.supervisor/memory/PROJECT_MEMORY.md"
rout2="$( cd "$RDIR" && bash "$READ" 2>/dev/null )"
if echo "$rout2" | grep -q "the sky is green"; then
  no "re-appended RETRACTED fact was emitted as verified (read-side retract not honored)"
else
  ok "re-appended retracted fact still dropped (retract revokes trust on the read side)"
fi

# 8e. chronological semantics: a later `add` of the same text re-trusts it (retract is not a
# permanent blocklist — it revokes the trust that existed at that point in the chain).
sed -i.bak "/the sky is green/d" "$RDIR/.supervisor/memory/PROJECT_MEMORY.md" && rm -f "$RDIR/.supervisor/memory/PROJECT_MEMORY.md.bak"
( cd "$RDIR" && bash "$WRITE" --fact "the sky is green" --source r ) >/dev/null 2>&1
rout3="$( cd "$RDIR" && bash "$READ" 2>/dev/null )"
echo "$rout3" | grep -q "the sky is green" && ok "re-adding a retracted fact re-trusts it" || no "re-add after retract did not re-trust"
rm -rf "$RDIR"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
