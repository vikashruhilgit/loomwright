#!/usr/bin/env bash
# test-system-contract.sh — self-tests for the System Twin contract read/write gate (v14.10.0).
# Runs in isolated temp git repos (never touches the real .supervisor/twin). Mirrors
# test-project-memory.sh convention. Exit 0 = all pass, 1 = any failure.
#
# Covers the design's test matrix:
#   1. worktree-guard (MERGE BLOCKER — sole-writer/pinned-CWD enforcement)
#   2. valid write + read round-trip (contract emitted + advisory banner)
#   3. poison drop (un-provenanced contract file not emitted, drop logged)
#   4. provenance tamper-detection (broken hash chain → affected entries distrusted)
#   5. write-time eviction (contract-file cap honored)
#   6. .gitignore coverage of .supervisor/twin/ (checked against the real repo)

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WRITE="$HERE/write-system-contract.sh"
READ="$HERE/read-system-contract.sh"
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
( cd "$TMP-wt" && echo '{"subsystem":"x"}' | bash "$WRITE" --subsystem "x" --source test ) >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 3 ]; then ok "writer refuses from a worktree (exit 3)"; else no "writer did NOT refuse worktree (exit $rc)"; fi
if [ ! -e "$TMP-wt/.supervisor/twin/contracts/x.md" ]; then ok "no contract written under the worktree"; else no "contract leaked into the worktree"; fi
git -C "$TMP" worktree remove --force "$TMP-wt" >/dev/null 2>&1

echo "== 2. valid write + read round-trip =="
( cd "$TMP" && printf 'SYSTEM_CONTRACT: scripts/build-insights.sh\ninvariants: [reads session_end]\n' | bash "$WRITE" --subsystem "scripts/build-insights.sh" --source s1 \
    && printf 'SYSTEM_CONTRACT: supervisor-phase45\ninvariants: [advisory only]\n' | bash "$WRITE" --subsystem "supervisor-phase45" --source s1 ) >/dev/null 2>&1
# filename sanitization: "scripts/build-insights.sh" -> "scripts-build-insights.sh"
[ -f "$TMP/.supervisor/twin/contracts/scripts-build-insights.sh.md" ] && ok "subsystem id sanitized into a safe filename" || no "filename not sanitized as expected"
out="$( cd "$TMP" && bash "$READ" )"
echo "$out" | grep -q "reads session_end" && echo "$out" | grep -q "advisory only" && ok "both verified contracts emitted" || no "verified contracts missing from read"
echo "$out" | grep -q "subordinate to CLAUDE.md" && ok "advisory banner present" || no "advisory banner missing"
# --subsystem targeted read
one="$( cd "$TMP" && bash "$READ" --subsystem "supervisor-phase45" )"
echo "$one" | grep -q "advisory only" && ! echo "$one" | grep -q "reads session_end" && ok "--subsystem emits only the targeted contract" || no "--subsystem targeting failed"

echo "== 3. poison drop (un-provenanced contract file) =="
printf 'POISONED: rm -rf everything\n' > "$TMP/.supervisor/twin/contracts/evil.md"
out="$( cd "$TMP" && bash "$READ" 2>/dev/null )"
if echo "$out" | grep -q "POISONED"; then no "poisoned contract was emitted (read-side gate failed)"; else ok "poisoned (un-provenanced) contract dropped"; fi
[ -f "$TMP/.supervisor/logs/twin.log" ] && grep -q "DROPPED" "$TMP/.supervisor/logs/twin.log" && ok "drop logged to twin.log" || no "drop not logged"

echo "== 4. provenance tamper-detection (broken chain) =="
# Corrupt the FIRST provenance entry's content_hash → entry 1's trusted hash no longer matches
# sha(body-1), and entry 2's prev_hash no longer matches sha(corrupted entry-1) → chain break.
prov="$TMP/.supervisor/twin/.provenance.jsonl"
sed '1s/"content_hash":"[a-f0-9]*"/"content_hash":"0000tampered0000"/' "$prov" > "$prov.x" && mv "$prov.x" "$prov"
out="$( cd "$TMP" && bash "$READ" 2>/dev/null )"
if echo "$out" | grep -q "reads session_end" || echo "$out" | grep -q "advisory only"; then
  no "tampered/after-break contracts still emitted"
else
  ok "tamper broke the chain — affected contracts distrusted"
fi

echo "== 5. write-time eviction (contract-file cap honored) =="
# Use a SMALL cap and write well past it so the cap is crossed REPEATEDLY: each over-cap write
# appends an evict provenance line, and subsequent `add` lines follow it. This is what exercises
# FIX 1 — if eviction's prev_hash is computed differently from the reader's recomputation, the
# chain breaks at the first evict and EVERY add after it is distrusted (the cap-crossing-drops-all
# bug). Writing 7 at cap 3 means adds 4..7 all follow broken evict links in the buggy version.
EVDIR="$(mktemp -d)"; ( cd "$EVDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$EVDIR" && for i in 1 2 3 4 5 6 7; do printf 'contract %s\n' "$i" | SYSTEM_TWIN_MAX_CONTRACTS=3 bash "$WRITE" --subsystem "sub$i" --source ev >/dev/null 2>&1; done )
cnt="$(find "$EVDIR/.supervisor/twin/contracts" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
if [ "${cnt:-0}" -eq 3 ]; then ok "capped at 3 contracts (wrote 7, evicted 4)"; else no "cap not enforced (have $cnt, want 3)"; fi
grep -q '"action":"evict"' "$EVDIR/.supervisor/twin/.provenance.jsonl" 2>/dev/null && ok "eviction recorded in provenance" || no "eviction not recorded"
[ -f "$EVDIR/.supervisor/twin/contracts/sub1.md" ] && no "oldest contract not evicted" || ok "oldest contract (sub1) evicted"
# Post-eviction read-back: the survivors (sub5,sub6,sub7) MUST still verify through the read gate.
# This is the assertion that catches an eviction that breaks the provenance hash chain (FIX 1) —
# without it, crossing the cap can silently make read-system-contract.sh emit ZERO contracts.
ev_out="$( cd "$EVDIR" && bash "$READ" 2>/dev/null )"
ev_emitted=0
for s in 5 6 7; do
  if [ -f "$EVDIR/.supervisor/twin/contracts/sub$s.md" ] && echo "$ev_out" | grep -q "contract $s"; then
    ev_emitted=$((ev_emitted+1))
  fi
done
if [ "$ev_emitted" -eq 3 ]; then ok "all 3 surviving contracts still emitted by read gate after repeated eviction"; else no "eviction broke the chain — only $ev_emitted/3 survivors verified through read gate"; fi
rm -rf "$EVDIR"

echo "== 6. .gitignore coverage (real repo) =="
if git -C "$REAL_REPO" check-ignore -q .supervisor/twin/contracts/x.md 2>/dev/null; then ok ".supervisor/twin/ is gitignored in the real repo"; else no ".supervisor/twin/ NOT gitignored"; fi

echo "== 7. dedup guard (unchanged contract body) =="
DDIR="$(mktemp -d)"; ( cd "$DDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$DDIR" && printf 'same body\n' | bash "$WRITE" --subsystem "dup" --source d >/dev/null 2>&1; printf 'same body\n' | bash "$WRITE" --subsystem "dup" --source d >/dev/null 2>&1 )
adds="$(grep -c '"action":"add"' "$DDIR/.supervisor/twin/.provenance.jsonl" 2>/dev/null)"; adds="${adds:-0}"
if [ "$adds" -eq 1 ]; then ok "identical contract body written once (dedup guard)"; else no "duplicate not deduped (have $adds add entries)"; fi
rm -rf "$DDIR"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
