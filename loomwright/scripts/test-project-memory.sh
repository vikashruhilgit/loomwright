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
#  16. THE --confirm GATE (the store is COMMITTED, so a write needs an explicit yes): a
#      non-interactive add / --retract / --supersedes WITHOUT --confirm prints its plan, exits 0,
#      and leaves BOTH PROJECT_MEMORY.md and the provenance chain byte-identical — including
#      creating neither file on a virgin repo. Plus the two controls without which the section
#      proves nothing: a refusal still outranks the gate, and the same call WITH --confirm writes.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WRITE="$HERE/write-project-memory.sh"

# ---------------------------------------------------------------------------
# PROVENANCE IN FIXTURES (decision (f) / AC15 — provenance is STRICT and centralised in
# validate_provenance). An entry must cite what motivated it: a bare token like `s`, `test` or `ev`
# names nothing and is now REFUSED. These fixtures therefore pass a REAL reference. An earlier
# revision of this suite wrapped $WRITE in a shim that appended a provenanced --source to every
# call; that was deleted on review because it masked genuine refusals — a fixture whose entry was
# refused for an unrelated reason still went green. Sources are explicit and per-call now.
# ---------------------------------------------------------------------------
READ="$HERE/read-project-memory.sh"
# ---------------------------------------------------------------------------
# seed_text — DISTINCT bodies for the cap/eviction seeding loops. The write-time duplicate check
# compares SIGNIFICANT tokens and drops tokens shorter than 3 chars, so bodies shaped
# "<word> number $i" differ only in a token it discards: to the checker they were 100% identical
# and every seed after the first was CORRECTLY refused. That is the check working, not a bug — so
# these seed semantically distinct entries. Order is stable, so "oldest evicted" stays assertable.
# ---------------------------------------------------------------------------
seed_text() {
  case "$1" in
    1) echo "caching layer invalidates whenever a deploy finishes" ;;
    2) echo "database migrations always run before the app boots" ;;
    3) echo "static assets are delivered through the edge network" ;;
    4) echo "queue workers retry failures with exponential backoff" ;;
    5) echo "session cookies rotate once every single hour" ;;
    6) echo "metrics are flushed on a ten second timer" ;;
    7) echo "feature flags default to disabled until enabled" ;;
  esac
}

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
( cd "$TMP-wt" && bash "$WRITE" --fact "should be refused" --source "session:fixture-0001" ) >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 3 ]; then ok "writer refuses from a worktree (exit 3)"; else no "writer did NOT refuse worktree (exit $rc)"; fi
if [ ! -e "$TMP-wt/.supervisor/memory/PROJECT_MEMORY.md" ]; then ok "no memory written under the worktree"; else no "memory leaked into the worktree"; fi
git -C "$TMP" worktree remove --force "$TMP-wt" >/dev/null 2>&1

echo "== 2. valid write + read round-trip =="
( cd "$TMP" && bash "$WRITE" --confirm --fact "auth is handled by signed JWT bearer tokens" --source "session:fixture-0001" \
    && bash "$WRITE" --confirm --fact "db is postgres via drizzle" --source "session:fixture-0001" ) >/dev/null 2>&1
out="$( cd "$TMP" && bash "$READ" )"
echo "$out" | grep -q "auth is handled by signed JWT bearer tokens" && echo "$out" | grep -q "db is postgres" && ok "both verified facts emitted" || no "verified facts missing from read"
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
if echo "$out" | grep -q "auth is handled by signed JWT bearer tokens" || echo "$out" | grep -q "db is postgres"; then
  no "tampered/after-break entries still emitted"
else
  ok "tamper broke the chain — affected entries distrusted"
fi

echo "== 5. write-time eviction (cap honored) =="
EVDIR="$(mktemp -d)"; ( cd "$EVDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$EVDIR" && for i in 1 2 3 4 5 6; do PROJECT_MEMORY_MAX_LINES=5 bash "$WRITE" --confirm --fact "$(seed_text $i)" --source "session:fixture-0001" >/dev/null 2>&1; done )
cnt="$(grep -cE '^- \[' "$EVDIR/.supervisor/memory/PROJECT_MEMORY.md" 2>/dev/null || echo 0)"
if [ "$cnt" -eq 5 ]; then ok "capped at 5 entries (wrote 6, evicted 1)"; else no "cap not enforced (have $cnt, want 5)"; fi
grep -q '"action":"evict"' "$EVDIR/.supervisor/memory/.provenance.jsonl" 2>/dev/null && ok "eviction recorded in provenance" || no "eviction not recorded"
grep -q "$(seed_text 1)" "$EVDIR/.supervisor/memory/PROJECT_MEMORY.md" 2>/dev/null && no "oldest entry not evicted" || ok "oldest entry (fact number 1) evicted"
# Post-eviction read-back: the eviction entry's prev_hash MUST be computed the same way the
# reader walks the chain (sha of the line WITHOUT its trailing newline). If it isn't, the chain
# breaks at the first evict entry and the reader distrusts every later `add` — silently dropping
# all surviving facts once enough writes push them past the first eviction. Cap=3 with 7 writes
# guarantees every survivor (facts 5,6,7) was added AFTER the first eviction entry, so a broken
# chain emits 0 survivors. The file-count check above can't catch this — only a read-back can.
EV2DIR="$(mktemp -d)"; ( cd "$EV2DIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$EV2DIR" && for i in 1 2 3 4 5 6 7; do PROJECT_MEMORY_MAX_LINES=3 bash "$WRITE" --confirm --fact "$(seed_text $i)" --source "session:fixture-0001" >/dev/null 2>&1; done )
evout="$( cd "$EV2DIR" && bash "$READ" 2>/dev/null )"
evsurv="$(echo "$evout" | grep -cE '^- \[')"; evsurv="${evsurv:-0}"
if [ "$evsurv" -eq 3 ] && echo "$evout" | grep -q "$(seed_text 5)" && echo "$evout" | grep -q "$(seed_text 7)"; then
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
( cd "$DDIR" && bash "$WRITE" --confirm --fact "same fact twice" --source "session:fixture-0001" >/dev/null 2>&1; bash "$WRITE" --confirm --fact "same fact twice" --source "session:fixture-0001" >/dev/null 2>&1 )
dcnt="$(grep -cE '^- \[' "$DDIR/.supervisor/memory/PROJECT_MEMORY.md" 2>/dev/null)"; dcnt="${dcnt:-0}"
if [ "$dcnt" -eq 1 ]; then ok "duplicate fact written once (dedup guard)"; else no "duplicate not deduped (have $dcnt)"; fi
rm -rf "$DDIR"

echo "== 8. retract / supersede correction path =="
RDIR="$(mktemp -d)"; ( cd "$RDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$RDIR" && bash "$WRITE" --confirm --fact "the sky is green" --source "session:fixture-0001" >/dev/null 2>&1 \
               && bash "$WRITE" --confirm --fact "keep me" --source "session:fixture-0001" >/dev/null 2>&1 )
wid="$(sed -nE 's/^- \[([^]]+)\] the sky is green$/\1/p' "$RDIR/.supervisor/memory/PROJECT_MEMORY.md")"
[ -n "$wid" ] && ok "wrong fact stored as [$wid]" || no "could not resolve id of the wrong fact"

# 8a. unknown id aborts with state untouched (fail closed, never half-write)
before="$(cat "$RDIR/.supervisor/memory/.provenance.jsonl")"
( cd "$RDIR" && bash "$WRITE" --retract deadbeef --source "session:fixture-0001" ) >/dev/null 2>&1
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
( cd "$RDIR" && bash "$WRITE" --fact "orphan replacement fact" --supersedes deadbeef --source "session:fixture-0001" ) >/dev/null 2>&1
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
( cd "$RDIR" && bash "$WRITE" --retract '.*' --source "session:fixture-0001" ) >/dev/null 2>&1
[ $? -eq 2 ] && ok "non-hex retract id rejected" || no "non-hex retract id accepted"

# 8d. ids are EXACTLY 8 hex chars by construction (`cut -c1-8`), so a hex-but-wrong-length id is a
#     malformed id — it must be rejected here with a precise message, not carried into the lookup
#     and reported as the misleading "no memory entry with id".
short="$( cd "$RDIR" && bash "$WRITE" --retract a --source "session:fixture-0001" 2>&1 )"
rc=$?
if [ "$rc" -eq 2 ] && echo "$short" | grep -q "exactly 8 lowercase hex chars"; then
  ok "too-short retract id rejected with a length-specific message"
else
  no "too-short retract id not rejected at validation (exit $rc): $short"
fi
long="$( cd "$RDIR" && bash "$WRITE" --retract deadbeef0 --source "session:fixture-0001" 2>&1 )"
rc=$?
if [ "$rc" -eq 2 ] && echo "$long" | grep -q "exactly 8 lowercase hex chars"; then
  ok "too-long retract id rejected with a length-specific message"
else
  no "too-long retract id not rejected at validation (exit $rc): $long"
fi

# 8e. supersede: corrected fact in, wrong fact out, unrelated fact untouched — one atomic call
( cd "$RDIR" && bash "$WRITE" --confirm --fact "the sky is blue" --supersedes "$wid" --source "session:fixture-0001" ) >/dev/null 2>&1
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
( cd "$RDIR" && bash "$WRITE" --confirm --fact "the sky is green" --source "session:fixture-0001" ) >/dev/null 2>&1
rout3="$( cd "$RDIR" && bash "$READ" 2>/dev/null )"
echo "$rout3" | grep -q "the sky is green" && ok "re-adding a retracted fact re-trusts it" || no "re-add after retract did not re-trust"
rm -rf "$RDIR"

# 8h. --supersedes with NO replacement --fact is an INDISTINGUISHABLE SYNONYM for a plain retraction,
#     so it FAILS CLOSED: exit 2 at validation time with state untouched. This replaced an earlier
#     warn-and-succeed path whose stated rationale ("erroring would be a breaking change") was false
#     — --supersedes ships in this same release and has no callers — and which left this store
#     disagreeing with the sibling it mirrors: write-lessons.sh:46
#     [pins: `indistinguishable synonym for retract`] already rejects the identical
#     mistake ("a supersede without a replacement is an indistinguishable synonym for retract").
#     The two stores now agree deliberately, and the abort matches the repo-wide "correctness gates
#     fail CLOSED" invariant. --retract, the honest spelling for that same operation, is deliberately
#     unaffected: silent, exit 0, still retracts.
WDIR="$(mktemp -d)"; ( cd "$WDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
WMEM="$WDIR/.supervisor/memory/PROJECT_MEMORY.md"; WPROV="$WDIR/.supervisor/memory/.provenance.jsonl"
( cd "$WDIR" && bash "$WRITE" --confirm --fact "supersede me bare" --source "session:fixture-0001" >/dev/null 2>&1 \
               && bash "$WRITE" --confirm --fact "supersede me bare equals form" --source "session:fixture-0001" >/dev/null 2>&1 \
               && bash "$WRITE" --confirm --fact "retract me bare"  --source "session:fixture-0001" >/dev/null 2>&1 )
sid="$(sed -nE 's/^- \[([^]]+)\] supersede me bare$/\1/p' "$WMEM")"
eid="$(sed -nE 's/^- \[([^]]+)\] supersede me bare equals form$/\1/p' "$WMEM")"
tid="$(sed -nE 's/^- \[([^]]+)\] retract me bare$/\1/p' "$WMEM")"
{ [ -n "$sid" ] && [ -n "$eid" ] && [ -n "$tid" ]; } && ok "bare-flag fixture stored three entries ([$sid], [$eid], [$tid])" || no "bare-flag fixture ids unresolved"

# (a) space-separated --supersedes <id>, no --fact → exit 2, message names the missing replacement,
#     and state is COMPLETELY untouched.
w_mem_b="$(cat "$WMEM")"; w_prov_b="$(cat "$WPROV")"
werr="$( cd "$WDIR" && bash "$WRITE" --supersedes "$sid" --source "session:fixture-0001" 2>&1 >/dev/null )"
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
weq="$( cd "$WDIR" && bash "$WRITE" --supersedes="$eid" --source "session:fixture-0001" 2>&1 >/dev/null )"
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
wunk="$( cd "$WDIR" && bash "$WRITE" --supersedes deadbeef --source "session:fixture-0001" 2>&1 >/dev/null )"
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
terr="$( cd "$WDIR" && bash "$WRITE" --confirm --retract "$tid" --source "session:fixture-0001" 2>&1 >/dev/null )"
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
( cd "$WDIR" && bash "$WRITE" --confirm --fact "supersede me bare, corrected" --supersedes "$sid" --source "session:fixture-0001" ) >/dev/null 2>&1
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
( cd "$SDIR" && bash "$WRITE" --confirm --fact "sky is blue"  --source "session:fixture-0001" >/dev/null 2>&1 \
               && bash "$WRITE" --confirm --fact "sky is green" --source "session:fixture-0001" >/dev/null 2>&1 )
gid="$(sed -nE 's/^- \[([^]]+)\] sky is green$/\1/p' "$SDIR/.supervisor/memory/PROJECT_MEMORY.md")"
[ -n "$gid" ] && ok "collision fixture stored 'sky is green' as [$gid]" || no "could not resolve id of the collision fixture"
( cd "$SDIR" && bash "$WRITE" --confirm --fact "sky is blue" --supersedes "$gid" --source "session:fixture-0001" ) >/dev/null 2>&1
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
( cd "$SDIR" && bash "$WRITE" --confirm --fact "alpha fact" --source "session:fixture-0001" >/dev/null 2>&1 )
aid="$(sed -nE 's/^- \[([^]]+)\] alpha fact$/\1/p' "$SDIR/.supervisor/memory/PROJECT_MEMORY.md")"
prov_before="$(cat "$SDIR/.supervisor/memory/.provenance.jsonl")"
noop="$( cd "$SDIR" && bash "$WRITE" --fact "alpha fact" --supersedes "$aid" --source "session:fixture-0001" 2>&1 )"
rc=$?
[ "$rc" -ne 0 ] && ok "no-op supersede fails closed (exit $rc)" || no "no-op supersede exited 0 (silent mutation)"
echo "$noop" | grep -q "retracted \[" && no "no-op supersede printed a false 'retracted' message" || ok "no misleading success message on the no-op supersede"
[ "$prov_before" = "$(cat "$SDIR/.supervisor/memory/.provenance.jsonl")" ] && ok "no-op supersede left provenance untouched" || no "no-op supersede mutated provenance"
grep -qF -- "- [$aid] alpha fact" "$SDIR/.supervisor/memory/PROJECT_MEMORY.md" && ok "fact survives the no-op supersede in PROJECT_MEMORY.md" || no "no-op supersede DELETED the fact (silent data loss)"
nout="$( cd "$SDIR" && bash "$READ" 2>/dev/null )"
echo "$nout" | grep -q "alpha fact" && ok "reader still returns the fact after the no-op supersede" || no "reader no longer returns the fact after the no-op supersede"

# 9c. the bare --fact dedup short-circuit is unchanged by the above (message + exit 0 preserved).
dup="$( cd "$SDIR" && bash "$WRITE" --confirm --fact "alpha fact" --source "session:fixture-0001" 2>&1 )"
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
( cd "$IDDIR" && bash "$WRITE" --confirm --fact "victim entry" --source "session:fixture-0001" >/dev/null 2>&1 )
vid="$(sed -nE 's/^- \[([^]]+)\] victim entry$/\1/p' "$IDDIR/.supervisor/memory/PROJECT_MEMORY.md")"
rm -rf "$IDDIR"
[ -n "$vid" ] && ok "resolved the victim fact's minted id [$vid] for the collision fixtures" || no "could not mint the victim id for the collision fixtures"

# 10a. DEDUP SITE. A brand-new fact whose rendered line is a SUBSTRING of an existing entry must
#      still be written. Unanchored, the writer reported "fact already present ([id]) — skipping"
#      and exited 0 for a fact it had never stored: silent data loss on a success status.
ADIR="$(mktemp -d)"; ( cd "$ADIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$ADIR" && bash "$WRITE" --confirm --fact "docs say the format is - [$vid] victim entry and that matters" --source "session:fixture-0001" >/dev/null 2>&1 )
aout="$( cd "$ADIR" && bash "$WRITE" --confirm --fact "victim entry" --source "session:fixture-0001" 2>&1 )"
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
( cd "$CDIR" && bash "$WRITE" --confirm --fact "see - [$vid] for details" --source "session:fixture-0001" >/dev/null 2>&1 \
               && bash "$WRITE" --confirm --fact "victim entry" --source "session:fixture-0001" >/dev/null 2>&1 )
decoy_first=0
head -n2 "$CDIR/.supervisor/memory/PROJECT_MEMORY.md" | tail -n1 | grep -qF "see - [$vid] for details" && decoy_first=1
[ "$decoy_first" -eq 1 ] && ok "collision fixture ordered decoy BEFORE the real target (the -m1 hazard)" || no "collision fixture ordering wrong — 10b would not exercise the -m1 path"
( cd "$CDIR" && bash "$WRITE" --confirm --retract "$vid" --source "session:fixture-0001" ) >/dev/null 2>&1
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
( cd "$MDIR" && bash "$WRITE" --confirm --fact "mixed flag alpha" --source "session:fixture-0001" >/dev/null 2>&1 \
               && bash "$WRITE" --confirm --fact "mixed flag beta"  --source "session:fixture-0001" >/dev/null 2>&1 )
mid_a="$(sed -nE 's/^- \[([^]]+)\] mixed flag alpha$/\1/p' "$MDIR/.supervisor/memory/PROJECT_MEMORY.md")"
mid_b="$(sed -nE 's/^- \[([^]]+)\] mixed flag beta$/\1/p'  "$MDIR/.supervisor/memory/PROJECT_MEMORY.md")"
[ -n "$mid_a" ] && [ -n "$mid_b" ] && ok "mixed-flag fixture stored two entries ([$mid_a], [$mid_b])" || no "mixed-flag fixture ids unresolved"
# order 1: --supersedes then --retract → LAST spelling is --retract → silent (a bare retraction is
# the honest meaning of that spelling), and it is [$mid_b] that gets retracted.
merr="$( cd "$MDIR" && bash "$WRITE" --confirm --supersedes "$mid_a" --retract "$mid_b" --source "session:fixture-0001" 2>&1 >/dev/null )"
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
merr2="$( cd "$MDIR" && bash "$WRITE" --retract "$mid_b" --supersedes "$mid_a" --source "session:fixture-0001" 2>&1 >/dev/null )"
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
( cd "$MDIR" && bash "$WRITE" --confirm --fact "mixed flag gamma" --source "session:fixture-0001" >/dev/null 2>&1 \
               && bash "$WRITE" --confirm --fact "mixed flag delta" --source "session:fixture-0001" >/dev/null 2>&1 )
mid_c="$(sed -nE 's/^- \[([^]]+)\] mixed flag gamma$/\1/p' "$MDIR/.supervisor/memory/PROJECT_MEMORY.md")"
mid_d="$(sed -nE 's/^- \[([^]]+)\] mixed flag delta$/\1/p' "$MDIR/.supervisor/memory/PROJECT_MEMORY.md")"
merr3="$( cd "$MDIR" && bash "$WRITE" --confirm --supersedes=deadbeef --retract="$mid_c" --source "session:fixture-0001" 2>&1 >/dev/null )"
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$merr3" ]; then
  ok "--supersedes=<a> --retract=<c> equals-form succeeds silently (the --retract= arm clears the spelling)"
else
  no "equals-form --retract= did not clear the --supersedes spelling (exit $rc, stderr '$merr3')"
fi
grep -qF -- "- [$mid_c] mixed flag gamma" "$MDIR/.supervisor/memory/PROJECT_MEMORY.md" \
  && no "--supersedes=<a> --retract=<c> retracted the wrong id" \
  || ok "--supersedes=<a> --retract=<c> retracted [$mid_c] (last VALUE wins, unchanged)"
merr4="$( cd "$MDIR" && bash "$WRITE" --retract="$mid_d" --supersedes=deadbeef --source "session:fixture-0001" 2>&1 >/dev/null )"
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
( cd "$PDIR" && bash "$WRITE" --confirm --fact "exactly identical fact" --source "session:fixture-0001" >/dev/null 2>&1 )
pid="$(sed -nE 's/^- \[([^]]+)\] exactly identical fact$/\1/p' "$PDIR/.supervisor/memory/PROJECT_MEMORY.md")"
pdup="$( cd "$PDIR" && bash "$WRITE" --confirm --fact "exactly identical fact" --source "session:fixture-0001" 2>&1 )"
rc=$?
if [ "$rc" -eq 0 ] && echo "$pdup" | grep -qF "write-project-memory: fact already present ([$pid]) — skipping"; then
  ok "an actually-identical fact is still deduped with the unchanged message + exit 0"
else
  no "anchoring broke ordinary dedup (exit $rc): $pdup"
fi
pcnt="$(grep -cxF -- "- [$pid] exactly identical fact" "$PDIR/.supervisor/memory/PROJECT_MEMORY.md" 2>/dev/null)"; pcnt="${pcnt:-0}"
[ "$pcnt" -eq 1 ] && ok "identical fact still stored exactly once" || no "identical fact stored $pcnt times (want 1)"
( cd "$PDIR" && bash "$WRITE" --confirm --retract "$pid" --source "session:fixture-0001" ) >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ] && ! grep -qF -- "- [$pid] " "$PDIR/.supervisor/memory/PROJECT_MEMORY.md"; then
  ok "an ordinary (non-colliding) entry is still findable and retractable under the anchored lookup"
else
  no "anchoring made an ordinary entry un-findable by --retract (exit $rc)"
fi
rm -rf "$PDIR"

# =============================================================================
# AC1 / AC2 / AC10a — WRITE-TIME VALIDATION AT THIS WRITER'S CALL SITE.
#
# Wiring write-project-memory.sh to validate-entry.sh makes test-validate-entry.sh green and this
# suite green, and NEITHER proves this writer ever CALLS the validator — a writer that `source`s the
# helper and never invokes it passes both. The per-writer coverage below is what pins the call site.
#
# THREE SEPARATE ASSERTIONS PER CASE (AC2), and the separation is the point: this writer commits via
# temp file + atomic `mv`, so "byte-unchanged" is ALSO true of a crash, an arg-parse rejection and a
# `command not found`. Each case asserts (i) the refusal EXIT STATUS, (ii) a NAMED, GREPPABLE reason
# on stderr, and (iii) the store byte-unchanged — via `cmp` against a saved copy, not a digest
# (`md5 -q` is BSD-only and this suite runs on Linux CI too).
# Long-form rationale for the shared fixture design lives in test-lessons.sh's equivalent section.
# =============================================================================
echo "== AC1/AC2/AC10a: write-time validation at the write-project-memory call site =="
VETMP="$(mktemp -d)"
VEFILE="$HERE/validate-entry.sh"
VE_ERR="$VETMP/stderr"
VE_ALLOW=""
VESTORE=".supervisor/memory/PROJECT_MEMORY.md"

ve_repo() {
  local r; r="$(mktemp -d "$VETMP/r.XXXXXX")"
  ( cd "$r" && git init -q && git config user.email t@t && git config user.name t \
      && echo init > f && git add f && git commit -qm init ) >/dev/null 2>&1
  printf '%s' "$r"
}

# ve_write <repo> <fact> <source> [validator-override] [writer-path] -> sets VE_RC, writes VE_ERR.
# An EMPTY validator-override leaves $WRITE_PROJECT_MEMORY_VALIDATOR empty, which is what makes the
# writer fall back to its own resolution — the real path, not a test-only one.
ve_write() {
  local repo="$1" txt="$2" src="$3" val="${4:-}" prog="${5:-$WRITE}"
  ( cd "$repo" \
      && if [ -n "$VE_ALLOW" ]; then export LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$VE_ALLOW"; fi \
      && WRITE_PROJECT_MEMORY_VALIDATOR="$val" bash "$prog" --confirm --fact "$txt" --source "$src" \
  ) >/dev/null 2>"$VE_ERR"
  VE_RC=$?
}

ve_refused() { # <label> <want-rc> <want-token> <store> <saved-copy>
  local label="$1" wrc="$2" tok="$3" st="$4" b4="$5"
  if [ "$VE_RC" -eq "$wrc" ]; then ok "$label (i) refused with exit $wrc"
  else no "$label (i) exit $VE_RC, want $wrc"; fi
  if grep -q "$tok" "$VE_ERR" 2>/dev/null; then ok "$label (ii) stderr names $tok"
  else no "$label (ii) stderr does NOT name $tok — got: $(tr '\n' ' ' < "$VE_ERR" | cut -c1-160)"; fi
  if cmp -s "$st" "$b4"; then ok "$label (iii) store byte-unchanged"
  else no "$label (iii) the refusal MUTATED the store"; fi
}

# ve_advised — the SAME three assertions for an ADVISORY check, each inverted exactly where the
# design inverted it. dead-reference and cross-repo REPORT and never refuse (validate-entry.sh's
# header records the six measured rounds of false refusals that bought that), so the three facts to
# assert about one become: the writer exits 0, it PRINTS the finding, and the entry IS written.
# (iii) is the load-bearing one: "the store changed" is what separates a demoted check from a check
# that still blocks, and a test asserting only rc 0 would stay green if the warning were deleted.
ve_advised() { # <label> <want-token> <store> <saved-copy>
  local label="$1" tok="$2" st="$3" b4="$4"
  if [ "$VE_RC" -eq 0 ]; then ok "$label (i) exited 0 — an ADVISORY check does not block the write"
  else no "$label (i) exit $VE_RC, want 0 — an advisory check must not refuse"; fi
  if grep -q "$tok" "$VE_ERR" 2>/dev/null; then ok "$label (ii) stderr REPORTS $tok"
  else no "$label (ii) stderr does NOT report $tok — got: $(tr '\n' ' ' < "$VE_ERR" | cut -c1-160)"; fi
  if cmp -s "$st" "$b4"; then no "$label (iii) the store is UNCHANGED, so the advisory blocked the write after all"
  else ok "$label (iii) the entry WAS written — the finding is a warning, not a refusal"; fi
}

# Each seed violates EXACTLY ONE check, because validate_entry_all returns the FIRST non-zero verdict
# in a fixed order — a seed that tripped an earlier check would assert nothing about the later one.
# VE_DUP is a REORDERING of VE_BASE, not a repeat: this writer's own idempotent dedup short-circuits
# an exact repeat at exit 0 before the validator runs (AC18), so a byte-identical seed would test
# that short-circuit instead of the duplicate check.
VE_BASE="release candidates promote through staging validation before production rollout begins across every regional cluster"
VE_DUP="across every regional cluster release candidates promote through staging validation before production rollout begins"
VE_CON="release candidates never promote through staging validation before production rollout begins across every regional cluster"
VE_PROV="the shared cache layer warms lazily on its very first read"
VE_DEAD="the retry helper now lives at loomwright/scripts/no-such-helper-xyz.sh"
VE_XREPO="the same defect was fixed in OTHERSVC #146"
VE_CLEAN="observability dashboards refresh their panels whenever a new deployment finishes rolling out"
VE_SRC="session:ve-0001"
VE_OURS="vikashruhilgit/loomwright"

# The cross-repo allowlist is supplied through this test's OWN environment; the live
# .supervisor/config.json is never touched and no foreign slug is ever added to it (R0/R8).
ve_case() { # <label> <text> <source> <want-token> [allowlist]
  local label="$1" txt="$2" src="$3" tok="$4" allow="${5:-}"
  local r st; r="$(ve_repo)"; st="$r/$VESTORE"
  ve_write "$r" "$VE_BASE" "$VE_SRC"
  if [ ! -f "$st" ]; then no "$label — SEED FAILED (no PROJECT_MEMORY.md; the fixture asserts nothing)"; return; fi
  cp "$st" "$VETMP/before"
  VE_ALLOW="$allow"; ve_write "$r" "$txt" "$src"; VE_ALLOW=""
  # An ADVISORY_* token routes to ve_advised; everything else is still a refusal. One dispatch
  # point, so a case cannot be silently asserted against the wrong contract.
  case "$tok" in
    ADVISORY_*) ve_advised "AC1 $label:" "$tok" "$st" "$VETMP/before" ;;
    *)          ve_refused "AC1 $label:" 1 "$tok" "$st" "$VETMP/before" ;;
  esac
}

ve_case "duplicate"      "$VE_DUP"   "$VE_SRC"   "REFUSE_DUPLICATE"
ve_case "contradiction"  "$VE_CON"   "$VE_SRC"   "REFUSE_CONTRADICTION"
ve_case "provenance"     "$VE_PROV"  "dreaming"  "REFUSE_PROVENANCE"
ve_case "dead-reference" "$VE_DEAD"  "$VE_SRC"   "ADVISORY_DEAD_REFERENCE"
ve_case "cross-repo"     "$VE_XREPO" "$VE_SRC"   "ADVISORY_CROSS_REPO" "$VE_OURS"

# AC2 — the degraded-helper shapes, each built from the REAL helper (so they cannot drift from it)
# and each aimed at a DIFFERENT clause of the three-clause load guard:
#   absent     -> the `[ -f ] || [ -r ]` pre-check
#   unparse    -> clause (i): a trailing syntax error makes `source` exit non-zero. Bash still
#                 defines every function above the error, so this shape has ALL five validators AND
#                 the sentinel — only the source status distinguishes it.
#   partial    -> clause (ii): cut above validate_dead_reference, so three validators are defined and
#                 validate_entry_all is not. This is the shape a one-function `command -v` probe
#                 would wave through as "examined and clean".
#   nosentinel -> clause (iii): everything defined and working, only the contract sentinel missing.
#                 Nothing but clause (iii) can catch it, which is why it is also the vehicle for the
#                 `|| true` mutation control below.
cp "$VEFILE" "$VETMP/unparse.sh"; printf '\nif [ ; then\n' >> "$VETMP/unparse.sh"
awk '/^validate_dead_reference\(\)/{exit} {print}'  "$VEFILE" > "$VETMP/partial.sh"
awk '/^VALIDATE_ENTRY_CONTRACT="/{exit} {print}'    "$VEFILE" > "$VETMP/nosentinel.sh"

if bash -n "$VETMP/partial.sh" 2>/dev/null && bash -n "$VETMP/nosentinel.sh" 2>/dev/null \
   && ! bash -n "$VETMP/unparse.sh" 2>/dev/null; then
  ok "AC2 fixtures: partial+nosentinel parse cleanly, unparse does not (each aimed at its own clause)"
else
  no "AC2 fixtures: a degraded-helper variant is not the shape it claims — the clause labels below are unreliable"
fi

ve_degraded() { # <label> <validator-path>; attempted with a CLEAN entry, so the ONLY reason to
                # refuse is the broken helper.
  local label="$1" val="$2" r st; r="$(ve_repo)"; st="$r/$VESTORE"
  ve_write "$r" "$VE_BASE" "$VE_SRC"
  if [ ! -f "$st" ]; then no "AC2 $label — SEED FAILED"; return; fi
  cp "$st" "$VETMP/before"
  ve_write "$r" "$VE_CLEAN" "$VE_SRC" "$val"
  ve_refused "AC2 $label:" 2 "REFUSE_VALIDATOR_UNAVAILABLE" "$st" "$VETMP/before"
}
ve_degraded "helper absent"        "$VETMP/no-such-validator.sh"
ve_degraded "helper unparseable"   "$VETMP/unparse.sh"
ve_degraded "helper truncated"     "$VETMP/partial.sh"
ve_degraded "helper sentinel-less" "$VETMP/nosentinel.sh"

# MUTATION CONTROLS. Both mutants are COPIES in $VETMP: the writer on disk is never edited, which
# makes "this writer goes RED while the other four stay green" true by construction rather than by a
# sibling run — a temp-file copy provably cannot reach the other four writers. Each mutant is gated
# on being non-empty, actually different, and still parseable before anything is credited to it.
ve_mutant_ok() { # <file> <desc>
  if [ ! -s "$1" ];              then no "$2 — mutant is EMPTY (vacuous control)"; return 1; fi
  if cmp -s "$WRITE" "$1";       then no "$2 — mutation changed NOTHING (vacuous control)"; return 1; fi
  if ! bash -n "$1" 2>/dev/null; then no "$2 — mutant does not parse (vacuous control)"; return 1; fi
  return 0
}

# ---------------------------------------------------------------------------
# (n) THIS WRITER'S OWN CALL-SITE ADVISORY NOTICE — asserted on BOTH the path that writes and the
# path that does not, plus the mutation control that proves the pair is load-bearing.
#
# WHY THIS EXISTS AT ALL. The dead-reference and cross-repo cases above assert only that an
# `ADVISORY_*` token reaches stderr, and those tokens are printed by the check functions INSIDE
# validate_entry_all — so deleting this writer's own `validate_entry_advisory_notice` call left
# every one of them green. Measured before this block was written: the literal `THE WRITE PROCEEDED`
# appeared nowhere in this suite, so the call site had no test at all. With the two checks demoted
# to advisory, the REPORTING is the whole feature, and the notice is the half that re-states the
# finding where a human actually reads it — next to the fact that the write went ahead.
#
# HOW THE PAIR IS SHAPED FOR *THIS* WRITER, which is not the shape test-write-agent-memory.sh uses.
# That writer has a confirm gate, so its (d6a)/(d6b) pair is dry-run-vs-confirmed. This writer has
# NO dry-run: it emits the notice at its ONE terminal SUCCESS exit, after the commit has actually
# happened — so there is no not-yet-written path to compare against. So the two no-write halves
# here are the ones this writer really has —
# (n1) an ordinary CLEAN write, where the notice must stay silent because nothing was reported, and
# (n3) the idempotent dedup short-circuit, which returns before the validator runs at all and must
# never claim a write proceeded. Both are honest properties of the notice, and both are stated in
# this writer's own control flow rather than borrowed from a sibling's.
#
# WHICH HALF HAS TEETH, stated plainly rather than implied: (n1) and (n3) also pass against the
# mutant — an absent notice is absent on every path — so they pin the notice's SILENCE, not its
# existence. (n2) is the half that goes RED when the call is removed, and (n4) is what proves it.
# It is placed after ve_mutant_ok() rather than beside the advisory cases because it needs it.
# ---------------------------------------------------------------------------
echo "== the call-site advisory notice fires on the write path, and only there =="
# (n1) an ordinary CLEAN write draws no finding, so the notice must print NOTHING.
vnR1="$(ve_repo)"; vnS1="$vnR1/$VESTORE"
ve_write "$vnR1" "$VE_CLEAN" "$VE_SRC"
if [ "$VE_RC" -eq 0 ] && [ -f "$vnS1" ]; then
  ok "(n1) fixture: a clean fact is written (exit 0) — this really is the wrote-and-nothing-to-report path"
else
  no "(n1) fixture: the clean write did not land (exit $VE_RC) — the silence below would prove nothing: $(tr '\n' ' ' < "$VE_ERR" | cut -c1-160)"
fi
if grep -qF 'THE WRITE PROCEEDED' "$VE_ERR" 2>/dev/null; then
  no "(n1) an ordinary clean write printed the advisory notice — it must be silent when no check reported anything"
else
  ok "(n1) an ordinary clean write is SILENT — the notice prints nothing when there is nothing to report"
fi

# (n2) a write carrying an ADVISORY finding: the notice MUST fire, in this writer's own name, and
# its sentence must be true — the fact really is on disk.
vnR2="$(ve_repo)"; vnS2="$vnR2/$VESTORE"
ve_write "$vnR2" "$VE_DEAD" "$VE_SRC"
if [ "$VE_RC" -eq 0 ]; then ok "(n2) the advisory-carrying write exits 0"
else no "(n2) the advisory-carrying write exited $VE_RC, want 0 — $(tr '\n' ' ' < "$VE_ERR" | cut -c1-160)"; fi
if grep -qF 'ADVISORY_DEAD_REFERENCE' "$VE_ERR" 2>/dev/null; then
  ok "(n2) fixture: the check's own ADVISORY token is present, so an advisory really did fire"
else
  no "(n2) fixture: no ADVISORY_DEAD_REFERENCE — the notice assertion below would be vacuous: $(tr '\n' ' ' < "$VE_ERR" | cut -c1-160)"
fi
if grep -qF 'THE WRITE PROCEEDED' "$VE_ERR" 2>/dev/null; then
  ok "(n2) the write DOES print the call-site advisory notice — the reporting half of the ADVISORY design is present on a genuine write"
else
  no "(n2) the advisory notice is absent from a real write — the reporting half was silently deleted: $(tr '\n' ' ' < "$VE_ERR" | cut -c1-160)"
fi
if grep -qE '^write-project-memory: ADVISORY:' "$VE_ERR" 2>/dev/null; then
  ok "(n2) and it is spoken in write-project-memory's own name, not the helper's"
else
  no "(n2) the notice does not name this writer: $(tr '\n' ' ' < "$VE_ERR" | cut -c1-160)"
fi
if grep -qF 'no-such-helper-xyz' "$vnS2" 2>/dev/null; then
  ok "(n2) and the fact really was stored — the notice's claim is true on this path"
else
  no "(n2) the notice claimed the write proceeded but no fact landed in $VESTORE"
fi

# (n3) the SAME entry again: this writer's idempotent dedup short-circuit returns BEFORE the
# validator runs, so nothing is written — and a notice ending "THE WRITE PROCEEDED" would be a lie.
cp "$vnS2" "$VETMP/before-n3"
ve_write "$vnR2" "$VE_DEAD" "$VE_SRC"
if [ "$VE_RC" -eq 0 ] && cmp -s "$vnS2" "$VETMP/before-n3"; then
  ok "(n3) fixture: the repeat is the dedup short-circuit (exit 0, store byte-identical) — this really is the wrote-nothing path"
else
  no "(n3) fixture: the repeat was not a silent no-op (exit $VE_RC, store changed) — the assertion below is about a different path"
fi
if grep -qF 'THE WRITE PROCEEDED' "$VE_ERR" 2>/dev/null; then
  no "(n3) a call that wrote NOTHING still claimed 'THE WRITE PROCEEDED'"
else
  ok "(n3) the no-op repeat does NOT claim 'THE WRITE PROCEEDED' — the notice never speaks for a write that did not happen"
fi

# (n4) MUTATION CONTROL: strip the call-site notice from a COPY and (n2) must go RED. `:` replaces
# the call rather than deleting the line, so that no enclosing block is left with an empty body — a
# bash syntax error would make the control prove a parse failure instead of a missing notice. The literal is the full call INCLUDING its argument, so the mutation cannot also hit the
# VALIDATOR_REQUIRED_FUNCS list — which names the same function and must survive, or the load guard
# would refuse and the mutant would fail for the wrong reason.
echo "== MUTATION CONTROL: with the call-site notice removed, (n2) goes RED =="
VN_CALL='validate_entry_advisory_notice "write-project-memory"'
vn_orig="$(grep -cF -- "$VN_CALL" "$WRITE" 2>/dev/null || true)"; [ -n "$vn_orig" ] || vn_orig=0
sed -e "s/$VN_CALL/:/" "$WRITE" > "$VETMP/mut-notice.sh"
vn_mut="$(grep -cF -- "$VN_CALL" "$VETMP/mut-notice.sh" 2>/dev/null || true)"; [ -n "$vn_mut" ] || vn_mut=0
vn_funcs="$(grep -c 'VALIDATOR_REQUIRED_FUNCS=' "$VETMP/mut-notice.sh" 2>/dev/null || true)"; [ -n "$vn_funcs" ] || vn_funcs=0
if [ "$vn_orig" -ge 1 ] && [ "$vn_mut" -eq 0 ] && [ "$vn_funcs" -ge 1 ]; then
  ok "(n4) the mutation is NON-VACUOUS: $vn_orig call site(s) in the writer, 0 in the mutant, and the required-funcs list survived"
else
  no "(n4) the mutation did not take as intended (call sites $vn_orig → $vn_mut, funcs list $vn_funcs) — the control below would prove nothing"
fi
if ve_mutant_ok "$VETMP/mut-notice.sh" "(n4) notice mutant"; then
  vnR4="$(ve_repo)"; vnS4="$vnR4/$VESTORE"
  ve_write "$vnR4" "$VE_DEAD" "$VE_SRC" "$VEFILE" "$VETMP/mut-notice.sh"
  if [ "$VE_RC" -eq 0 ] && grep -qF 'no-such-helper-xyz' "$vnS4" 2>/dev/null; then
    ok "(n4) the mutant still WRITES the entry — the only behavioural difference under test is the notice"
  else
    no "(n4) the mutant failed to write (exit $VE_RC) — the comparison would not be like-for-like: $(tr '\n' ' ' < "$VE_ERR" | cut -c1-160)"
  fi
  if grep -qF 'ADVISORY_DEAD_REFERENCE' "$VE_ERR" 2>/dev/null; then
    ok "(n4) and the check's OWN token is still printed by the mutant — which is exactly why the advisory cases above could not detect this deletion"
  else
    no "(n4) the mutant lost the check's own token too, so it is not the isolated mutation intended"
  fi
  if grep -qF 'THE WRITE PROCEEDED' "$VE_ERR" 2>/dev/null; then
    no "(n4) REFUTED: the notice appeared with its call site removed — (n2) is passing for some other reason and is vacuous"
  else
    ok "(n4) CONFIRMED: without the call site the notice VANISHES from a real write — (n2) goes RED without it and is load-bearing"
  fi
fi
rm -f "$VETMP/mut-notice.sh"   # a mutated writer must never outlive its own control

# (a) AC1's mandated per-writer control: script the VALIDATOR CALL block out. REPLACED with `:`
# rather than deleted because it sits inside an `if ... fi` whose body must not become empty.
awk '/---- VALIDATOR CALL BEGIN/{s=1; print "  :"; next} /---- VALIDATOR CALL END/{s=0; next} !s' \
  "$WRITE" > "$VETMP/mut-call.sh"
if ve_mutant_ok "$VETMP/mut-call.sh" "AC1 call-site mutant"; then
  r="$(ve_repo)"; st="$r/$VESTORE"
  ve_write "$r" "$VE_BASE" "$VE_SRC"
  cp "$st" "$VETMP/before"
  ve_write "$r" "$VE_CON" "$VE_SRC" "$VEFILE" "$VETMP/mut-call.sh"
  if [ "$VE_RC" -eq 0 ] && ! cmp -s "$st" "$VETMP/before"; then
    ok "AC1 mutation control: deleting the VALIDATOR CALL lets the contradiction seed through (exit 0, store grew) — the fixtures above are RED because of the call site, not the source line"
  else
    no "AC1 mutation control: the call-site mutant STILL refused (exit $VE_RC) — the AC1 fixtures may be passing for some other reason"
  fi
fi

# (b) AC2's mandated control: replace the whole load guard with the repo's pervasive `|| true`
# convention — the one line decision (a) forbids on the source. Paired with the sentinel-less helper
# because that is the shape where the mutation is OBSERVABLE: with an absent or truncated helper the
# writer still fails closed by accident (validate_entry_all is undefined, the call returns 127, the
# writer exits 2 with no named reason), but with a sentinel-less helper every validator works, so
# dropping the guard lets an UNVERIFIED-CONTRACT write go all the way through. All three AC2
# assertions go RED at once: exit 0, no named reason, store MUTATED.
awk '/---- LOAD GUARD BEGIN/{s=1; print "  . \"$VALIDATOR\" || true"; next} /---- LOAD GUARD END/{s=0; next} !s' \
  "$WRITE" > "$VETMP/mut-guard.sh"
if ve_mutant_ok "$VETMP/mut-guard.sh" "AC2 load-guard mutant"; then
  if grep -q '|| true' "$VETMP/mut-guard.sh"; then
    r="$(ve_repo)"; st="$r/$VESTORE"
    ve_write "$r" "$VE_BASE" "$VE_SRC"
    cp "$st" "$VETMP/before"
    ve_write "$r" "$VE_CLEAN" "$VE_SRC" "$VETMP/nosentinel.sh" "$VETMP/mut-guard.sh"
    if [ "$VE_RC" -eq 0 ] && ! grep -q REFUSE_VALIDATOR_UNAVAILABLE "$VE_ERR" 2>/dev/null \
       && ! cmp -s "$st" "$VETMP/before"; then
      ok "AC2 mutation control: replacing the load guard with '|| true' turns all three assertions RED (exit 0, no named reason, store mutated)"
    else
      no "AC2 mutation control: the '|| true' mutant did not go RED (exit $VE_RC) — AC2 may be passing for some other reason"
    fi
  else
    no "AC2 mutation control: the '|| true' replacement did not land in the mutant"
  fi
fi

# AC10a — RE-VERIFICATION, with one assertion section 1 does not make. Section 1 proves a worktree
# CWD is refused with exit 3; this proves the worktree guard still runs BEFORE the validator load
# guard, i.e. wiring the validator in did not reorder them. With a deliberately absent validator the
# refusal must STILL be the worktree's exit 3, never the load guard's exit 2 — otherwise the F1
# refusal would be masked by AC2's.
VEWT="$(ve_repo)"
git -C "$VEWT" worktree add -q "$VEWT-wt" -b vewt >/dev/null 2>&1
if [ -d "$VEWT-wt" ]; then
  ve_write "$VEWT-wt" "$VE_CLEAN" "$VE_SRC" "$VETMP/no-such-validator.sh"
  if [ "$VE_RC" -eq 3 ] && grep -q worktree "$VE_ERR" 2>/dev/null; then
    ok "AC10a: a worktree CWD still refuses with exit 3, ahead of the validator load guard (absent helper does not mask it)"
  else
    no "AC10a: worktree refusal is exit $VE_RC (want 3) — the validator guard now precedes the worktree guard"
  fi
  [ -e "$VEWT-wt/$VESTORE" ] && no "AC10a: memory leaked into the worktree" \
    || ok "AC10a: nothing written under the worktree"
  git -C "$VEWT" worktree remove --force "$VEWT-wt" >/dev/null 2>&1
else
  no "AC10a: could not create the fixture worktree — the assertion would be vacuous"
fi
rm -rf "$VETMP" "$VEWT-wt" 2>/dev/null

# ---------------------------------------------------------------------------
# (uf) UNRECOGNISED ARGUMENTS ARE REFUSED. A writer must be able to tell a caller it asked for
# something the writer does not implement, instead of dropping the argument and reporting success.
#
# WHY THIS EXISTS. write-project-memory.sh derives its store from the CURRENT DIRECTORY
# (`git rev-parse --show-toplevel`), never from anything the caller passes, and it takes NO
# positional arguments at all. Before the guard, `*) shift ;;` silently dropped every unmatched
# argument, so `--repo <elsewhere>` parsed, was discarded, and the write landed in whatever repo the
# caller happened to be standing in — reported as a clean success at exit 0. Not hypothetical: a
# PR #144 review run did exactly that on the sibling lessons writer, believing `--repo` isolated the
# store, and a junk entry landed in this repo's real store and its provenance chain. `--repo` and
# `--store` are REAL flags on write-agent-memory.sh and add-orientation.sh, so reaching for one here
# is muscle memory from a sibling writer, not a typo.
#
# WHICH HALF HAS TEETH. (uf1) is the pin; (uf2) is the control proving the guard did not simply make
# the writer refuse everything. (uf3) is the mutation control: it restores the old `*) shift ;;` arm
# and asserts (uf1) goes RED, with a non-vacuity check that the sed landed.
# ---------------------------------------------------------------------------
echo "== 15. unrecognised arguments are refused, named, and write nothing =="
UFTMP="$(mktemp -d)"
UF_ERR="$UFTMP/stderr"
UF_SRC="PR #144"
UF_FACT="deployment rollbacks drain their connection pools before the health check flips"
uf_repo() {
  local r; r="$(mktemp -d "$UFTMP/r.XXXXXX")"
  ( cd "$r" && git init -q && git config user.email t@t && git config user.name t \
      && echo init > f && git add f && git commit -qm init ) >/dev/null 2>&1
  printf '%s' "$r"
}
# uf_run <repo> <writer-path> [args...] -> sets UF_RC, writes UF_ERR.
# $UF_VALIDATOR mirrors ve_write's validator-override: a MUTANT copy lives in a temp dir, so its
# sibling-relative resolution of validate-entry.sh would fail and the writer would refuse with
# REFUSE_VALIDATOR_UNAVAILABLE — a refusal for the wrong reason, which would make the mutation
# control look green by accident. Left empty for the real writer, which must resolve it for itself.
UF_VALIDATOR=""
uf_run() {
  local repo="$1" prog="$2"; shift 2
  ( cd "$repo" && WRITE_PROJECT_MEMORY_VALIDATOR="$UF_VALIDATOR" bash "$prog" "$@" ) >/dev/null 2>"$UF_ERR"
  UF_RC=$?
}
uf_err() { tr '\n' ' ' < "$UF_ERR" 2>/dev/null | cut -c1-200; }

# (uf1) THE DEFECT: a well-formed write PLUS two arguments this writer does not implement.
UFR1="$(uf_repo)"
uf_run "$UFR1" "$WRITE" --fact "$UF_FACT" --source "$UF_SRC" \
       --repo /nonexistent/path --totally-made-up xyz
if [ "$UF_RC" -eq 2 ]; then
  ok "(uf1) an unrecognised argument is REFUSED with exit 2 — the could-not-examine convention this writer already uses for every other argument check"
else
  no "(uf1) exit $UF_RC, want 2 — the writer accepted an argument it does not implement: $(uf_err)"
fi
if grep -qF -- '--repo' "$UF_ERR" 2>/dev/null; then
  ok "(uf1) and the refusal NAMES the offending argument, so the caller learns which one was not honoured"
else
  no "(uf1) the refusal does not name '--repo' — an unnamed refusal cannot tell the caller what to fix: $(uf_err)"
fi
if grep -q '^write-project-memory: ' "$UF_ERR" 2>/dev/null; then
  ok "(uf1) and it is spoken in write-project-memory's own name"
else
  no "(uf1) the refusal does not name this writer: $(uf_err)"
fi
if [ -e "$UFR1/.supervisor" ]; then
  no "(uf1) the refusal still touched the store — a .supervisor/ tree exists after a refused write"
else
  ok "(uf1) and NOTHING was written — no .supervisor/ tree at all, so neither the store nor its provenance chain moved"
fi

# (uf2) CONTROL: the SAME invocation without the bogus arguments must still write. Without this, a
# writer that refused every invocation would pass (uf1).
UFR2="$(uf_repo)"
uf_run "$UFR2" "$WRITE" --confirm --fact "$UF_FACT" --source "$UF_SRC"
if [ "$UF_RC" -eq 0 ] && [ -f "$UFR2/$VESTORE" ]; then
  ok "(uf2) CONTROL: the identical call WITHOUT the unrecognised arguments still writes (exit 0) — the guard refuses the unknown, not the known"
else
  no "(uf2) CONTROL FAILED: the real flags no longer write (exit $UF_RC) — the guard over-refuses: $(uf_err)"
fi

# (uf3) MUTATION CONTROL: restore the pre-fix `*) shift ;;` arm and (uf1) must go RED. The line is
# REPLACED rather than deleted, because a `case` pattern with no body is a syntax error and a mutant
# that cannot parse proves a broken mutant rather than a missing guard. The control asserts the
# mutant WRITES — not merely that it exits differently — so a refusal for some unrelated reason
# cannot be mistaken for the guard still working.
echo "== 15. MUTATION CONTROL: with the guard restored to silent-drop, (uf1) goes RED =="
UFMUT="$UFTMP/mut-noguard.sh"
uf_orig="$(grep -c "unrecognised argument" "$WRITE" 2>/dev/null || true)"; [ -n "$uf_orig" ] || uf_orig=0
sed -e "/unrecognised argument/s|.*|    *) shift ;;|" "$WRITE" > "$UFMUT"
uf_mut="$(grep -c "unrecognised argument" "$UFMUT" 2>/dev/null || true)"; [ -n "$uf_mut" ] || uf_mut=0
uf_drop="$(grep -c '^    \*) shift ;;$' "$UFMUT" 2>/dev/null || true)"; [ -n "$uf_drop" ] || uf_drop=0
if [ "$uf_orig" -eq 1 ] && [ "$uf_mut" -eq 0 ] && [ "$uf_drop" -eq 1 ]; then
  ok "(uf3) the mutation is NON-VACUOUS: 1 guard line in the real writer, 0 in the mutant, and the silent-drop arm is back in its place"
else
  no "(uf3) the mutation did not land as intended (guard $uf_orig → $uf_mut, silent-drop arm $uf_drop) — the control below would prove nothing"
fi
if bash -n "$UFMUT" 2>/dev/null; then
  ok "(uf3) the mutant still parses, so a difference below is behavioural rather than a syntax error"
  UFR3="$(uf_repo)"
  UF_VALIDATOR="$VEFILE"   # the mutant is a temp copy; point it at the real validator (see uf_run)
  uf_run "$UFR3" "$UFMUT" --confirm --fact "$UF_FACT" --source "$UF_SRC" \
         --repo /nonexistent/path --totally-made-up xyz
  UF_VALIDATOR=""
  if [ "$UF_RC" -eq 0 ] && [ -f "$UFR3/$VESTORE" ]; then
    ok "(uf3) CONFIRMED: without the guard the SAME call exits 0 and writes the fact anyway — (uf1) goes RED without it and is load-bearing"
  else
    no "(uf3) REFUTED: the mutant refused too (exit $UF_RC) — (uf1) is passing for some other reason and is vacuous: $(uf_err)"
  fi
else
  no "(uf3) the mutant does not parse — it could not discriminate anything"
fi
rm -rf "$UFTMP" 2>/dev/null   # a mutated writer must never outlive its own control

# ---------------------------------------------------------------------------
# (cg) THE CONFIRM GATE. `.supervisor/memory/` is un-ignored by `.gitignore` (`!.supervisor/memory/`),
# so PROJECT_MEMORY.md and .provenance.jsonl are TRACKED, COMMITTED files — and until the gate
# landed, ONE non-interactive invocation from the repo root appended to the committed store. That
# happened during a review. The repo-wide rule: a sole writer whose store is COMMITTED requires
# --confirm.
#
# WHAT THIS SECTION PINS: a non-interactive run WITHOUT --confirm must write NOTHING and exit 0.
# Every other case in this suite now passes --confirm, so without these cases the gate could be
# deleted outright and the suite would stay green — it would be proving only that --confirm is
# ACCEPTED, never that its absence WITHHOLDS the write.
#
# BYTE-IDENTICAL on BOTH files, not "the text is absent": the commit is two atomic renames and the
# provenance chain goes FIRST, so a gate placed between them would leave PROJECT_MEMORY.md clean
# while the chain had already moved. The `>"$CG_OUT" 2>&1` redirection also makes stdout a pipe, so
# `[ -t 1 ]` is false and the prompt branch is unreachable even from a real terminal.
# ---------------------------------------------------------------------------
echo "== 16. the --confirm gate: no --confirm + no TTY = dry-run, nothing written =="
CGTMP="$(mktemp -d)"
CGDIR="$CGTMP/repo"; mkdir -p "$CGDIR"
( cd "$CGDIR" && git init -q && git config user.email t@t && git config user.name t \
    && echo init > f && git add f && git commit -qm init ) >/dev/null 2>&1
CG_M="$CGDIR/$VESTORE"
CG_P="$CGDIR/.supervisor/memory/.provenance.jsonl"
CG_OUT="$CGTMP/out"
( cd "$CGDIR" && bash "$WRITE" --confirm --fact "gate seed fact stays put" --source "session:fixture-0001" ) >/dev/null 2>&1
if [ -f "$CG_M" ] && [ -f "$CG_P" ]; then
  ok "(cg) fixture: the seeded store exists, so the byte-comparisons below have something to compare"
else
  no "(cg) fixture: the --confirm seed did not create the store — every assertion below would be vacuous"
fi
cg_seed_id="$(sed -nE 's/^- \[([^]]+)\] gate seed fact stays put$/\1/p' "$CG_M" 2>/dev/null)"
cp "$CG_M" "$CGTMP/M.before"; cp "$CG_P" "$CGTMP/P.before"

# (cg1) ADD without --confirm, non-interactive.
( cd "$CGDIR" && bash "$WRITE" --fact "gate must withhold this new fact entirely" --source "session:fixture-0001" ) >"$CG_OUT" 2>&1
cg_rc=$?
[ "$cg_rc" -eq 0 ] && ok "(cg1) a non-interactive add without --confirm exits 0 (a dry-run is not an error)" \
                   || no "(cg1) exit $cg_rc, want 0 — the dry-run must not look like a failure"
grep -qF 'PLANNED WRITE (not written — pass --confirm to apply):' "$CG_OUT" \
  && ok "(cg1) and it PRINTS THE PLAN, naming --confirm as the way to apply it" \
  || no "(cg1) no PLANNED WRITE line — a silent no-op tells the caller nothing: $(tr '\n' ' ' < "$CG_OUT" | cut -c1-200)"
grep -qF -- "gate must withhold this new fact entirely" "$CG_OUT" \
  && ok "(cg1) and the plan shows the entry that WOULD have been written" \
  || no "(cg1) the plan does not show the entry content"
cmp -s "$CG_M" "$CGTMP/M.before" \
  && ok "(cg1) PROJECT_MEMORY.md is BYTE-IDENTICAL — the committed store did not move" \
  || no "(cg1) the dry-run MUTATED PROJECT_MEMORY.md — the gate does not withhold the write"
cmp -s "$CG_P" "$CGTMP/P.before" \
  && ok "(cg1) and the provenance chain is BYTE-IDENTICAL too (it is renamed FIRST, so it is the half a mis-placed gate would leak)" \
  || no "(cg1) the dry-run MUTATED the provenance chain — the gate sits after the first rename"

# (cg2) RETRACT without --confirm: the target survives, and no tombstone is chained.
( cd "$CGDIR" && bash "$WRITE" --retract "$cg_seed_id" --source "session:fixture-0001" ) >"$CG_OUT" 2>&1
cg_rc=$?
[ "$cg_rc" -eq 0 ] && ok "(cg2) a non-interactive retract without --confirm exits 0" \
                   || no "(cg2) exit $cg_rc, want 0"
grep -qF 'PLANNED RETRACT (not written — pass --confirm to apply):' "$CG_OUT" \
  && ok "(cg2) and it prints PLANNED RETRACT rather than deleting the line" \
  || no "(cg2) no PLANNED RETRACT line: $(tr '\n' ' ' < "$CG_OUT" | cut -c1-200)"
if cmp -s "$CG_M" "$CGTMP/M.before" && cmp -s "$CG_P" "$CGTMP/P.before"; then
  ok "(cg2) both files are byte-identical — the fact is still stored and no retract entry was chained"
else
  no "(cg2) the dry-run retract mutated the store or the chain"
fi

# (cg3) SUPERSEDE without --confirm — the shape where a half-applied dry-run would be worst: the
# add and the retract commit together, so a gate on only one half would delete the target for free.
( cd "$CGDIR" && bash "$WRITE" --fact "gate replacement never lands" --supersedes "$cg_seed_id" --source "session:fixture-0001" ) >"$CG_OUT" 2>&1
cg_rc=$?
[ "$cg_rc" -eq 0 ] && ok "(cg3) a non-interactive supersede without --confirm exits 0" \
                   || no "(cg3) exit $cg_rc, want 0"
grep -qF 'PLANNED SUPERSEDE (not written — pass --confirm to apply):' "$CG_OUT" \
  && ok "(cg3) and it prints PLANNED SUPERSEDE" \
  || no "(cg3) no PLANNED SUPERSEDE line: $(tr '\n' ' ' < "$CG_OUT" | cut -c1-200)"
if cmp -s "$CG_M" "$CGTMP/M.before" && cmp -s "$CG_P" "$CGTMP/P.before"; then
  ok "(cg3) both files byte-identical — neither the replacement nor the retraction slipped through"
else
  no "(cg3) the dry-run supersede half-committed"
fi

# (cg4) A REFUSAL STILL OUTRANKS THE GATE. Without this, "the gate withholds everything" would be
# indistinguishable from "validation still fails loud", and a regression turning every bad call into
# a friendly exit-0 dry-run would pass (cg1)-(cg3).
( cd "$CGDIR" && bash "$WRITE" --retract deadbeef --source "session:fixture-0001" ) >"$CG_OUT" 2>&1
cg_rc=$?
[ "$cg_rc" -eq 2 ] && ok "(cg4) an unknown --retract id still FAILS LOUD (exit 2) without --confirm — a refusal outranks the gate" \
                   || no "(cg4) exit $cg_rc, want 2 — the gate swallowed a refusal into a dry-run"
( cd "$CGDIR" && bash "$WRITE" --supersedes "$cg_seed_id" --source "session:fixture-0001" ) >"$CG_OUT" 2>&1
cg_rc=$?
[ "$cg_rc" -eq 2 ] && ok "(cg4) and a bare --supersedes with no replacement --fact still aborts exit 2, gate or no gate" \
                   || no "(cg4) exit $cg_rc, want 2 — the fail-closed --supersedes abort was demoted to a dry-run"
( cd "$CGDIR" && bash "$WRITE" --fact x --totally-made-up y --source "session:fixture-0001" ) >"$CG_OUT" 2>&1
cg_rc=$?
[ "$cg_rc" -eq 2 ] && ok "(cg4) and an unrecognised argument still refuses with exit 2" \
                   || no "(cg4) exit $cg_rc, want 2 — the unknown-argument refusal was demoted to a dry-run"

# (cg5) CONTROL: the SAME add WITH --confirm does write — the gate withholds, it does not break the
# writer. Without this a writer that refused everything would pass (cg1)-(cg3).
( cd "$CGDIR" && bash "$WRITE" --confirm --fact "gate must withhold this new fact entirely" --source "session:fixture-0001" ) >"$CG_OUT" 2>&1
cg_rc=$?
if [ "$cg_rc" -eq 0 ] && grep -qF -- "gate must withhold this new fact entirely" "$CG_M"; then
  ok "(cg5) CONTROL: the identical call WITH --confirm writes the fact"
else
  no "(cg5) CONTROL FAILED: --confirm no longer writes (exit $cg_rc): $(tr '\n' ' ' < "$CG_OUT" | cut -c1-200)"
fi

# (cg6) DRY-RUN ON A VIRGIN REPO: the gate must not even CREATE the store. The bootstrap that mints
# PROJECT_MEMORY.md + the chain runs before the write, so a gate guarding only the append would
# still leave two new files behind — in the real repo, two new entries in `git status`.
CGV="$CGTMP/virgin"; mkdir -p "$CGV"
( cd "$CGV" && git init -q && git config user.email t@t && git config user.name t \
    && echo init > f && git add f && git commit -qm init ) >/dev/null 2>&1
( cd "$CGV" && bash "$WRITE" --fact "nothing at all should be created here" --source "session:fixture-0001" ) >"$CG_OUT" 2>&1
cg_rc=$?
if [ "$cg_rc" -eq 0 ] && [ ! -e "$CGV/$VESTORE" ] && [ ! -e "$CGV/.supervisor/memory/.provenance.jsonl" ]; then
  ok "(cg6) a dry-run against a store that does not exist yet creates NEITHER file — nothing lands in git status"
else
  no "(cg6) the dry-run bootstrapped the store anyway (exit $cg_rc) — an empty committed file is still a mutation"
fi
rm -rf "$CGTMP" 2>/dev/null

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
