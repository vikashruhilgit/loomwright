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
# 8b. the ADD-half sibling of 8a: `--fact <new> --supersedes <unknown-id>`. The add half and the
#     target resolution share one path, so an unknown target must leave state COMPLETELY untouched —
#     in particular the NEW fact must NOT be written (a half-applied supersede would store the
#     replacement while the wrong fact it was meant to correct stays live).
prov_b="$(cat "$RDIR/.supervisor/memory/.provenance.jsonl")"
mem_b="$(cat "$RDIR/.supervisor/memory/PROJECT_MEMORY.md")"
( cd "$RDIR" && bash "$WRITE" --fact "orphan replacement fact" --supersedes deadbeef --source r ) >/dev/null 2>&1
rc=$?
[ "$rc" -eq 2 ] && ok "supersede with an unknown target aborts (exit 2)" || no "supersede with an unknown target did not fail closed (exit $rc)"
grep -qF -- "orphan replacement fact" "$RDIR/.supervisor/memory/PROJECT_MEMORY.md" \
  && no "aborted supersede WROTE the replacement fact (half-applied correction)" \
  || ok "aborted supersede did not write the replacement fact"
[ "$prov_b" = "$(cat "$RDIR/.supervisor/memory/.provenance.jsonl")" ] && ok "aborted supersede left provenance byte-identical" || no "aborted supersede mutated provenance"
[ "$mem_b" = "$(cat "$RDIR/.supervisor/memory/PROJECT_MEMORY.md")" ] && ok "aborted supersede left PROJECT_MEMORY.md byte-identical" || no "aborted supersede mutated PROJECT_MEMORY.md"
# The abort happens before any temp exists, so no .mtmp/.ptmp may be left behind (a stray temp would
# also mean the trap-based cleanup is the only thing standing between an abort and a partial write).
# `ls -1a`, NOT `ls -1` — the temps are DOTFILES (`.mtmp.XXXXXX`/`.ptmp.XXXXXX`), which a bare
# `ls -1` hides, making this assertion unfailable.
stray="$(ls -1a "$RDIR/.supervisor/memory/" 2>/dev/null | grep -c -e '^\.mtmp\.' -e '^\.ptmp\.')"; stray="${stray:-0}"
[ "$stray" -eq 0 ] && ok "aborted supersede left no .mtmp/.ptmp temp files" || no "aborted supersede left $stray temp file(s) behind"
aout="$( cd "$RDIR" && bash "$READ" 2>/dev/null )"
acnt2="$(echo "$aout" | grep -cE '^- \[')"; acnt2="${acnt2:-0}"
if [ "$acnt2" -eq 2 ] && echo "$aout" | grep -q "the sky is green" && echo "$aout" | grep -q "keep me" \
   && ! echo "$aout" | grep -q "orphan replacement fact"; then
  ok "reader still returns exactly the pre-existing entries after the aborted supersede"
else
  no "reader state changed by the aborted supersede (have $acnt2 verified, want the original 2)"
fi

# 8c. non-hex id is rejected before it reaches a grep/sed pattern
( cd "$RDIR" && bash "$WRITE" --retract '.*' --source r ) >/dev/null 2>&1
[ $? -eq 2 ] && ok "non-hex retract id rejected" || no "non-hex retract id accepted"

# 8d. ids are EXACTLY 8 hex chars by construction (`cut -c1-8`), so a hex-but-wrong-length id is a
#     malformed id — it must be rejected here with a precise message, not carried into the lookup
#     and reported as the misleading "no memory entry with id".
short="$( cd "$RDIR" && bash "$WRITE" --retract a --source r 2>&1 )"
rc=$?
if [ "$rc" -eq 2 ] && echo "$short" | grep -q "exactly 8 lowercase hex chars"; then
  ok "too-short retract id rejected with a length-specific message"
else
  no "too-short retract id not rejected at validation (exit $rc): $short"
fi
long="$( cd "$RDIR" && bash "$WRITE" --retract deadbeef0 --source r 2>&1 )"
rc=$?
if [ "$rc" -eq 2 ] && echo "$long" | grep -q "exactly 8 lowercase hex chars"; then
  ok "too-long retract id rejected with a length-specific message"
else
  no "too-long retract id not rejected at validation (exit $rc): $long"
fi

# 8e. supersede: corrected fact in, wrong fact out, unrelated fact untouched — one atomic call
( cd "$RDIR" && bash "$WRITE" --fact "the sky is blue" --supersedes "$wid" --source r ) >/dev/null 2>&1
rout="$( cd "$RDIR" && bash "$READ" 2>/dev/null )"
echo "$rout" | grep -q "the sky is blue" && ok "superseding fact emitted" || no "superseding fact missing"
echo "$rout" | grep -q "the sky is green" && no "retracted fact still emitted" || ok "retracted fact gone"
echo "$rout" | grep -q "keep me"          && ok "unrelated fact survives supersede" || no "unrelated fact lost"
rcnt="$(echo "$rout" | grep -cE '^- \[')"; rcnt="${rcnt:-0}"
[ "$rcnt" -eq 2 ] && ok "count correct after supersede (2 verified)" || no "wrong count after supersede (have $rcnt, want 2)"

# 8f. THE READ-SIDE POINT: the original `add` lives forever in the append-only provenance log,
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

# 8g. chronological semantics: a later `add` of the same text re-trusts it (retract is not a
# permanent blocklist — it revokes the trust that existed at that point in the chain).
sed -i.bak "/the sky is green/d" "$RDIR/.supervisor/memory/PROJECT_MEMORY.md" && rm -f "$RDIR/.supervisor/memory/PROJECT_MEMORY.md.bak"
( cd "$RDIR" && bash "$WRITE" --fact "the sky is green" --source r ) >/dev/null 2>&1
rout3="$( cd "$RDIR" && bash "$READ" 2>/dev/null )"
echo "$rout3" | grep -q "the sky is green" && ok "re-adding a retracted fact re-trusts it" || no "re-add after retract did not re-trust"
rm -rf "$RDIR"

# 8h. --supersedes with NO replacement --fact is an INDISTINGUISHABLE SYNONYM for a plain retraction,
#     so it FAILS CLOSED: exit 2 at validation time with state untouched. This replaced an earlier
#     warn-and-succeed path whose stated rationale ("erroring would be a breaking change") was false
#     — --supersedes ships in this same release and has no callers — and which left this store
#     disagreeing with the sibling it mirrors: write-lessons.sh:125 already rejects the identical
#     mistake ("a supersede without a replacement is an indistinguishable synonym for retract").
#     The two stores now agree deliberately, and the abort matches the repo-wide "correctness gates
#     fail CLOSED" invariant. --retract, the honest spelling for that same operation, is deliberately
#     unaffected: silent, exit 0, still retracts.
WDIR="$(mktemp -d)"; ( cd "$WDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
WMEM="$WDIR/.supervisor/memory/PROJECT_MEMORY.md"; WPROV="$WDIR/.supervisor/memory/.provenance.jsonl"
( cd "$WDIR" && bash "$WRITE" --fact "supersede me bare" --source w >/dev/null 2>&1 \
               && bash "$WRITE" --fact "supersede me bare equals form" --source w >/dev/null 2>&1 \
               && bash "$WRITE" --fact "retract me bare"  --source w >/dev/null 2>&1 )
sid="$(sed -nE 's/^- \[([^]]+)\] supersede me bare$/\1/p' "$WMEM")"
eid="$(sed -nE 's/^- \[([^]]+)\] supersede me bare equals form$/\1/p' "$WMEM")"
tid="$(sed -nE 's/^- \[([^]]+)\] retract me bare$/\1/p' "$WMEM")"
{ [ -n "$sid" ] && [ -n "$eid" ] && [ -n "$tid" ]; } && ok "bare-flag fixture stored three entries ([$sid], [$eid], [$tid])" || no "bare-flag fixture ids unresolved"

# (a) space-separated --supersedes <id>, no --fact → exit 2, message names the missing replacement,
#     and state is COMPLETELY untouched.
w_mem_b="$(cat "$WMEM")"; w_prov_b="$(cat "$WPROV")"
werr="$( cd "$WDIR" && bash "$WRITE" --supersedes "$sid" --source w 2>&1 >/dev/null )"
rc=$?
[ "$rc" -eq 2 ] && ok "--supersedes without --fact fails closed (exit 2)" || no "--supersedes without --fact did not fail closed (exit $rc)"
echo "$werr" | grep -qF -- "--supersedes [$sid] requires a replacement --fact" \
  && ok "--supersedes without --fact names the missing replacement (and the id it carried)" \
  || no "--supersedes without --fact gave the wrong error: '$werr'"
echo "$werr" | grep -qF -- "indistinguishable synonym for retract" && echo "$werr" | grep -qF -- "use --retract" \
  && ok "--supersedes abort explains the synonymy and points at --retract" \
  || no "--supersedes abort message missing the rationale/--retract pointer: '$werr'"
[ "$w_mem_b" = "$(cat "$WMEM")" ] && ok "aborted bare --supersedes left PROJECT_MEMORY.md byte-identical" || no "aborted bare --supersedes mutated PROJECT_MEMORY.md"
[ "$w_prov_b" = "$(cat "$WPROV")" ] && ok "aborted bare --supersedes left provenance byte-identical" || no "aborted bare --supersedes mutated provenance"
grep -qxF -- "- [$sid] supersede me bare" "$WMEM" \
  && ok "aborted bare --supersedes did NOT retract its target (no degraded retraction)" \
  || no "aborted bare --supersedes still retracted the target"
# The abort precedes every mktemp, so no temp may exist. `ls -1a`, NOT `ls -1` — the temps are
# DOTFILES (.mtmp.XXXXXX/.ptmp.XXXXXX), which a bare `ls -1` hides, making this unfailable.
stray="$(ls -1a "$WDIR/.supervisor/memory/" 2>/dev/null | grep -c -e '^\.mtmp\.' -e '^\.ptmp\.')"; stray="${stray:-0}"
[ "$stray" -eq 0 ] && ok "aborted bare --supersedes left no .mtmp/.ptmp temp files" || no "aborted bare --supersedes left $stray temp file(s) behind"

# (b) the --supersedes=<id> equals-form arm must follow the identical rule.
weq="$( cd "$WDIR" && bash "$WRITE" --supersedes="$eid" --source w 2>&1 >/dev/null )"
rc=$?
if [ "$rc" -eq 2 ] && echo "$weq" | grep -qF -- "--supersedes [$eid] requires a replacement --fact"; then
  ok "--supersedes=<id> equals-form without --fact fails closed the same way (exit 2)"
else
  no "--supersedes=<id> equals-form did not fail closed (exit $rc): '$weq'"
fi
grep -qxF -- "- [$eid] supersede me bare equals form" "$WMEM" \
  && ok "aborted equals-form --supersedes left its target in place" \
  || no "aborted equals-form --supersedes retracted its target"

# (e) ORDERING PIN: argument-shape errors fire BEFORE state lookups. `--supersedes <unknown-id>`
#     with no --fact must report the MISSING REPLACEMENT, never "no memory entry with id". The old
#     non-fatal warning sat at this same point, so that call printed "the retraction still runs and
#     still exits 0" and THEN aborted exit 2 at the lookup — a message false on its own path.
wunk="$( cd "$WDIR" && bash "$WRITE" --supersedes deadbeef --source w 2>&1 >/dev/null )"
rc=$?
if [ "$rc" -eq 2 ] && echo "$wunk" | grep -qF -- "--supersedes [deadbeef] requires a replacement --fact" \
   && ! echo "$wunk" | grep -qF -- "no memory entry with id"; then
  ok "--supersedes <unknown-id> without --fact reports the missing replacement, not the unknown id"
else
  no "--supersedes <unknown-id> without --fact reported the wrong error (exit $rc): '$wunk'"
fi
#     The precise contradiction: the old warning asserted "this is a plain retraction" on a call
#     that then exited 2 having retracted nothing. No surviving message on this path may claim it.
echo "$wunk" | grep -qiF -- "is a plain retraction" \
  && no "abort message still claims a plain retraction happened on a call that exits 2 having retracted nothing" \
  || ok "no message on the exit-2 path claims a retraction took place (self-contradiction gone)"

# (c) --retract with no --fact is untouched: silent on stderr, exit 0, and it still retracts.
terr="$( cd "$WDIR" && bash "$WRITE" --retract "$tid" --source w 2>&1 >/dev/null )"
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$terr" ]; then
  ok "--retract stays silent on stderr and exits 0 (unaffected by the --supersedes abort)"
else
  no "--retract regressed (exit $rc, stderr '$terr')"
fi
grep -qF -- "- [$tid] retract me bare" "$WMEM" \
  && no "--retract no longer retracts" \
  || ok "--retract still performs the retraction"

# (f) the SUPPORTED correction shape is unaffected end-to-end: a replacement --fact paired with
#     --supersedes still stores the correction and retracts the target in one call. (8e pins the
#     read-side half; this pins that the new validation gate does not intercept the happy path.)
( cd "$WDIR" && bash "$WRITE" --fact "supersede me bare, corrected" --supersedes "$sid" --source w ) >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "--fact <corrected> --supersedes <id> still exits 0 (happy path not intercepted)" || no "the supported supersede shape regressed (exit $rc)"
wout="$( cd "$WDIR" && bash "$READ" 2>/dev/null )"
if echo "$wout" | grep -qF "supersede me bare, corrected" && ! echo "$wout" | grep -qxF -- "- [$sid] supersede me bare"; then
  ok "--fact <corrected> --supersedes <id> still corrects end-to-end (replacement in, target out)"
else
  no "the supported supersede shape no longer corrects end-to-end"
fi
rm -rf "$WDIR"

echo "== 9. supersede x dedup edge cases (regression) =="
# Both branches below were live defects: the dedup guard used to be written as
# `grep -q ... && [ -z "$RETRACT_ID" ]`, which disabled the CHECK ITSELF (not just its early exit)
# on a --supersedes call, so the add half appended unconditionally. 9a caught a duplicate line;
# 9b caught outright data loss (identical text ⇒ `grep -vxF` deletes BOTH copies, and the shared
# content_hash means the retract revokes the hash the add just trusted).
SDIR="$(mktemp -d)"; ( cd "$SDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )

# 9a. supersede whose corrected text collides with a DIFFERENT existing entry: a legitimate
#     correction — the retraction must land, but no duplicate line (and no spurious `add`).
( cd "$SDIR" && bash "$WRITE" --fact "sky is blue"  --source s >/dev/null 2>&1 \
               && bash "$WRITE" --fact "sky is green" --source s >/dev/null 2>&1 )
gid="$(sed -nE 's/^- \[([^]]+)\] sky is green$/\1/p' "$SDIR/.supervisor/memory/PROJECT_MEMORY.md")"
[ -n "$gid" ] && ok "collision fixture stored 'sky is green' as [$gid]" || no "could not resolve id of the collision fixture"
( cd "$SDIR" && bash "$WRITE" --fact "sky is blue" --supersedes "$gid" --source s ) >/dev/null 2>&1
bcnt="$(grep -cF -- "sky is blue" "$SDIR/.supervisor/memory/PROJECT_MEMORY.md" 2>/dev/null)"; bcnt="${bcnt:-0}"
[ "$bcnt" -eq 1 ] && ok "supersede colliding with an existing entry writes no duplicate (1 line)" || no "supersede duplicated the colliding fact (have $bcnt, want 1)"
acnt="$(grep -c '"action":"add"' "$SDIR/.supervisor/memory/.provenance.jsonl" 2>/dev/null)"; acnt="${acnt:-0}"
[ "$acnt" -eq 2 ] && ok "no spurious 'add' provenance entry for the deduped half (2 adds)" || no "spurious/missing add provenance (have $acnt, want 2)"
sout="$( cd "$SDIR" && bash "$READ" 2>/dev/null )"
echo "$sout" | grep -q "sky is green" && no "retraction did not land on the colliding supersede" || ok "retraction still landed despite the skipped add"
# Chain must survive the skipped `add` — append_prov links off the CURRENT tail, so the retract
# entry chains to whatever preceded it. A reader that emits the survivor proves the chain is valid.
echo "$sout" | grep -q "sky is blue" && ok "survivor reads back verified (hash chain intact across a skipped add)" || no "survivor dropped by reader (skipped add broke the chain)"

# 9b. no-op supersede (replacement byte-identical to the target): must FAIL CLOSED with state
#     untouched — the fact survives in the file AND in the reader, and no false "retracted".
( cd "$SDIR" && bash "$WRITE" --fact "alpha fact" --source s >/dev/null 2>&1 )
aid="$(sed -nE 's/^- \[([^]]+)\] alpha fact$/\1/p' "$SDIR/.supervisor/memory/PROJECT_MEMORY.md")"
prov_before="$(cat "$SDIR/.supervisor/memory/.provenance.jsonl")"
noop="$( cd "$SDIR" && bash "$WRITE" --fact "alpha fact" --supersedes "$aid" --source s 2>&1 )"
rc=$?
[ "$rc" -ne 0 ] && ok "no-op supersede fails closed (exit $rc)" || no "no-op supersede exited 0 (silent mutation)"
echo "$noop" | grep -q "retracted \[" && no "no-op supersede printed a false 'retracted' message" || ok "no misleading success message on the no-op supersede"
[ "$prov_before" = "$(cat "$SDIR/.supervisor/memory/.provenance.jsonl")" ] && ok "no-op supersede left provenance untouched" || no "no-op supersede mutated provenance"
grep -qF -- "- [$aid] alpha fact" "$SDIR/.supervisor/memory/PROJECT_MEMORY.md" && ok "fact survives the no-op supersede in PROJECT_MEMORY.md" || no "no-op supersede DELETED the fact (silent data loss)"
nout="$( cd "$SDIR" && bash "$READ" 2>/dev/null )"
echo "$nout" | grep -q "alpha fact" && ok "reader still returns the fact after the no-op supersede" || no "reader no longer returns the fact after the no-op supersede"

# 9c. the bare --fact dedup short-circuit is unchanged by the above (message + exit 0 preserved).
dup="$( cd "$SDIR" && bash "$WRITE" --fact "alpha fact" --source s 2>&1 )"
rc=$?
if [ "$rc" -eq 0 ] && echo "$dup" | grep -qF "write-project-memory: fact already present ([$aid]) — skipping"; then
  ok "bare --fact dedup short-circuit intact (exit 0 + unchanged message)"
else
  no "bare --fact dedup short-circuit regressed (exit $rc): $dup"
fi
dupcnt="$(grep -cF -- "alpha fact" "$SDIR/.supervisor/memory/PROJECT_MEMORY.md" 2>/dev/null)"; dupcnt="${dupcnt:-0}"
[ "$dupcnt" -eq 1 ] && ok "bare --fact dedup still writes the fact once" || no "bare --fact dedup wrote $dupcnt copies (want 1)"
rm -rf "$SDIR"

echo "== 10. line-shape anchoring (substring-collision class) =="
# ONE root cause, two sites: both matched the structured entry shape `- [<id>] <text>` with an
# UNANCHORED `grep -F`, so a match could land in the MIDDLE of another entry's free text. Fact text
# is arbitrary human prose and this repo's own PROJECT_MEMORY.md already stores entries that quote
# bracketed ids inline, so this was reachable, not theoretical. Fixes: `-x` (whole line) on the
# dedup guard, `^`-anchored ERE on the retract lookup.
#
# The decoy has to embed the victim's EXACT rendered line, so resolve the victim's real id the same
# way the writer mints it — in a throwaway repo — rather than hard-coding a hash that would rot the
# moment the id derivation changes.
IDDIR="$(mktemp -d)"; ( cd "$IDDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$IDDIR" && bash "$WRITE" --fact "victim entry" --source x >/dev/null 2>&1 )
vid="$(sed -nE 's/^- \[([^]]+)\] victim entry$/\1/p' "$IDDIR/.supervisor/memory/PROJECT_MEMORY.md")"
rm -rf "$IDDIR"
[ -n "$vid" ] && ok "resolved the victim fact's minted id [$vid] for the collision fixtures" || no "could not mint the victim id for the collision fixtures"

# 10a. DEDUP SITE. A brand-new fact whose rendered line is a SUBSTRING of an existing entry must
#      still be written. Unanchored, the writer reported "fact already present ([id]) — skipping"
#      and exited 0 for a fact it had never stored: silent data loss on a success status.
ADIR="$(mktemp -d)"; ( cd "$ADIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$ADIR" && bash "$WRITE" --fact "docs say the format is - [$vid] victim entry and that matters" --source x >/dev/null 2>&1 )
aout="$( cd "$ADIR" && bash "$WRITE" --fact "victim entry" --source x 2>&1 )"
rc=$?
if [ "$rc" -eq 0 ] && echo "$aout" | grep -qF "stored [$vid]"; then
  ok "new fact whose line is a substring of an existing entry is stored, not deduped away"
else
  no "substring-collision fact was silently skipped (exit $rc): $aout"
fi
vcnt="$(grep -cxF -- "- [$vid] victim entry" "$ADIR/.supervisor/memory/PROJECT_MEMORY.md" 2>/dev/null)"; vcnt="${vcnt:-0}"
[ "$vcnt" -eq 1 ] && ok "substring-collision fact written exactly once" || no "substring-collision fact written $vcnt times (want 1)"
aread="$( cd "$ADIR" && bash "$READ" 2>/dev/null )"
if echo "$aread" | grep -qxF -- "- [$vid] victim entry" && echo "$aread" | grep -qF "docs say the format is"; then
  ok "reader returns BOTH the decoy and the substring-collision fact (provenance written for each)"
else
  no "reader does not return both collision entries"
fi
rm -rf "$ADIR"

# 10b. RETRACT SITE. With a decoy ordered BEFORE the real target, `grep -m1 -F` captured the DECOY
#      line, and the `grep -vxF "$retract_line"` deletion then removed the decoy while the real
#      target survived — with provenance recording the real id as retracted. State and provenance
#      disagreed, and the reader kept serving the fact the caller had just "retracted".
CDIR="$(mktemp -d)"; ( cd "$CDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$CDIR" && bash "$WRITE" --fact "see - [$vid] for details" --source x >/dev/null 2>&1 \
               && bash "$WRITE" --fact "victim entry" --source x >/dev/null 2>&1 )
decoy_first=0
head -n2 "$CDIR/.supervisor/memory/PROJECT_MEMORY.md" | tail -n1 | grep -qF "see - [$vid] for details" && decoy_first=1
[ "$decoy_first" -eq 1 ] && ok "collision fixture ordered decoy BEFORE the real target (the -m1 hazard)" || no "collision fixture ordering wrong — 10b would not exercise the -m1 path"
( cd "$CDIR" && bash "$WRITE" --retract "$vid" --source x ) >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "retract of the real id succeeds (exit 0)" || no "retract of the real id failed (exit $rc)"
grep -qxF -- "- [$vid] victim entry" "$CDIR/.supervisor/memory/PROJECT_MEMORY.md" \
  && no "retract deleted the wrong line — the REAL target survived in PROJECT_MEMORY.md" \
  || ok "retract deleted the REAL target line"
grep -qF -- "see - [$vid] for details" "$CDIR/.supervisor/memory/PROJECT_MEMORY.md" \
  && ok "the decoy entry is left intact by the retract" \
  || no "retract deleted the DECOY instead of the target (wrong line removed)"
cread="$( cd "$CDIR" && bash "$READ" 2>/dev/null )"
if echo "$cread" | grep -qF "see - [$vid] for details" && ! echo "$cread" | grep -qxF -- "- [$vid] victim entry"; then
  ok "reader agrees with the file: decoy verified, retracted target gone (state and provenance match)"
else
  no "reader disagrees with the file after the collision retract"
fi
rm -rf "$CDIR"

# 10c. --supersedes / --retract share a variable but were tracked by two variables with DIFFERENT
#      last-wins rules: the value was overwritten by every arm, the SPELLING flag was only ever set.
#      So `--supersedes <a> --retract <b>` warned "--supersedes [<b>]" — naming an id that was never
#      passed as --supersedes. Both orders are pinned so the two rules can't drift apart again.
#      Now HIGHER-STAKES than when the spelling only selected a warning: the spelling selects a
#      FAIL-CLOSED ABORT, so a stale flag would REJECT (exit 2) an honest bare `--retract`.
MDIR="$(mktemp -d)"; ( cd "$MDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$MDIR" && bash "$WRITE" --fact "mixed flag alpha" --source m >/dev/null 2>&1 \
               && bash "$WRITE" --fact "mixed flag beta"  --source m >/dev/null 2>&1 )
mid_a="$(sed -nE 's/^- \[([^]]+)\] mixed flag alpha$/\1/p' "$MDIR/.supervisor/memory/PROJECT_MEMORY.md")"
mid_b="$(sed -nE 's/^- \[([^]]+)\] mixed flag beta$/\1/p'  "$MDIR/.supervisor/memory/PROJECT_MEMORY.md")"
[ -n "$mid_a" ] && [ -n "$mid_b" ] && ok "mixed-flag fixture stored two entries ([$mid_a], [$mid_b])" || no "mixed-flag fixture ids unresolved"
# order 1: --supersedes then --retract → LAST spelling is --retract → silent (a bare retraction is
# the honest meaning of that spelling), and it is [$mid_b] that gets retracted.
merr="$( cd "$MDIR" && bash "$WRITE" --supersedes "$mid_a" --retract "$mid_b" --source m 2>&1 >/dev/null )"
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$merr" ]; then
  ok "--supersedes <a> --retract <b> is silent (last spelling wins, as the last value already did)"
else
  no "--supersedes <a> --retract <b> warned with a stale spelling (exit $rc, stderr '$merr')"
fi
grep -qF -- "- [$mid_b] mixed flag beta" "$MDIR/.supervisor/memory/PROJECT_MEMORY.md" \
  && no "--supersedes <a> --retract <b> retracted the wrong id" \
  || ok "--supersedes <a> --retract <b> retracted [$mid_b] (last VALUE wins, unchanged)"
# order 2: --retract then --supersedes → LAST spelling is --supersedes → FAIL CLOSED (exit 2),
# naming the id the --supersedes spelling actually carried, with [$mid_a] left in place.
merr2="$( cd "$MDIR" && bash "$WRITE" --retract "$mid_b" --supersedes "$mid_a" --source m 2>&1 >/dev/null )"
rc=$?
if [ "$rc" -eq 2 ] && echo "$merr2" | grep -qF -- "--supersedes [$mid_a] requires a replacement --fact"; then
  ok "--retract <b> --supersedes <a> aborts exit 2 naming [$mid_a] (the id the last spelling carried)"
else
  no "--retract <b> --supersedes <a> did not abort correctly (exit $rc): '$merr2'"
fi
grep -qF -- "- [$mid_a] mixed flag alpha" "$MDIR/.supervisor/memory/PROJECT_MEMORY.md" \
  && ok "--retract <b> --supersedes <a> retracted nothing (state untouched by the abort)" \
  || no "the aborted mixed-flag call still retracted [$mid_a]"
# equals-form arms must follow the same rule as their space-separated twins — the --retract= arm
# CLEARS the spelling (silent success), the --supersedes= arm SETS it (abort).
( cd "$MDIR" && bash "$WRITE" --fact "mixed flag gamma" --source m >/dev/null 2>&1 \
               && bash "$WRITE" --fact "mixed flag delta" --source m >/dev/null 2>&1 )
mid_c="$(sed -nE 's/^- \[([^]]+)\] mixed flag gamma$/\1/p' "$MDIR/.supervisor/memory/PROJECT_MEMORY.md")"
mid_d="$(sed -nE 's/^- \[([^]]+)\] mixed flag delta$/\1/p' "$MDIR/.supervisor/memory/PROJECT_MEMORY.md")"
merr3="$( cd "$MDIR" && bash "$WRITE" --supersedes=deadbeef --retract="$mid_c" --source m 2>&1 >/dev/null )"
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$merr3" ]; then
  ok "--supersedes=<a> --retract=<c> equals-form succeeds silently (the --retract= arm clears the spelling)"
else
  no "equals-form --retract= did not clear the --supersedes spelling (exit $rc, stderr '$merr3')"
fi
grep -qF -- "- [$mid_c] mixed flag gamma" "$MDIR/.supervisor/memory/PROJECT_MEMORY.md" \
  && no "--supersedes=<a> --retract=<c> retracted the wrong id" \
  || ok "--supersedes=<a> --retract=<c> retracted [$mid_c] (last VALUE wins, unchanged)"
merr4="$( cd "$MDIR" && bash "$WRITE" --retract="$mid_d" --supersedes=deadbeef --source m 2>&1 >/dev/null )"
rc=$?
if [ "$rc" -eq 2 ] && echo "$merr4" | grep -qF -- "--supersedes [deadbeef] requires a replacement --fact"; then
  ok "--retract=<d> --supersedes=<unknown> equals-form aborts exit 2 (the --supersedes= arm sets the spelling; shape before state)"
else
  no "equals-form --supersedes= did not set the spelling / abort (exit $rc): '$merr4'"
fi
grep -qF -- "- [$mid_d] mixed flag delta" "$MDIR/.supervisor/memory/PROJECT_MEMORY.md" \
  && ok "the aborted equals-form mixed call retracted nothing" \
  || no "the aborted equals-form mixed call still retracted [$mid_d]"
rm -rf "$MDIR"

# 10d. NO-REGRESSION PIN for the anchoring change: an ACTUALLY-identical fact must still be deduped
#      (anchoring must narrow the match, never disable it), and an existing entry must stay findable
#      by the retract lookup — entries are written with no leading whitespace and no CR, so a
#      line-start anchor cannot make a legitimate line un-findable.
PDIR="$(mktemp -d)"; ( cd "$PDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$PDIR" && bash "$WRITE" --fact "exactly identical fact" --source p >/dev/null 2>&1 )
pid="$(sed -nE 's/^- \[([^]]+)\] exactly identical fact$/\1/p' "$PDIR/.supervisor/memory/PROJECT_MEMORY.md")"
pdup="$( cd "$PDIR" && bash "$WRITE" --fact "exactly identical fact" --source p 2>&1 )"
rc=$?
if [ "$rc" -eq 0 ] && echo "$pdup" | grep -qF "write-project-memory: fact already present ([$pid]) — skipping"; then
  ok "an actually-identical fact is still deduped with the unchanged message + exit 0"
else
  no "anchoring broke ordinary dedup (exit $rc): $pdup"
fi
pcnt="$(grep -cxF -- "- [$pid] exactly identical fact" "$PDIR/.supervisor/memory/PROJECT_MEMORY.md" 2>/dev/null)"; pcnt="${pcnt:-0}"
[ "$pcnt" -eq 1 ] && ok "identical fact still stored exactly once" || no "identical fact stored $pcnt times (want 1)"
( cd "$PDIR" && bash "$WRITE" --retract "$pid" --source p ) >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ] && ! grep -qF -- "- [$pid] " "$PDIR/.supervisor/memory/PROJECT_MEMORY.md"; then
  ok "an ordinary (non-colliding) entry is still findable and retractable under the anchored lookup"
else
  no "anchoring made an ordinary entry un-findable by --retract (exit $rc)"
fi
rm -rf "$PDIR"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
