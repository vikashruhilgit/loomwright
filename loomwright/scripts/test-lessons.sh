#!/usr/bin/env bash
# test-lessons.sh — self-tests for the LESSONS bounded sole-writer (v14.5.0).
# Runs in isolated temp git repos (never touches the real .supervisor/memory). Mirrors the
# test-project-memory.sh convention. Exit 0 = all pass, 1 = any failure.
#
# Covers:
#   1. worktree-guard (MERGE BLOCKER — closes red-team F1)
#   2. round-trip (lesson appears under its `## <category>` heading)
#   3. <=3/category eviction (oldest evicted)
#   4. two categories independent (both sections coexist)
#   5. .gitignore coverage of .supervisor/memory/ (checked against the real repo)
#   6. backslash integrity (awk ENVIRON, not -v)
#   7. freshness trailer (last_verified + confidence, defaults + overrides; content_hash unchanged)
#   8. provenance write-side (separate .lessons-provenance.jsonl chain; add + evict entries)
#   9. retract verb end-to-end (tombstone removal + chain-valid retract provenance + reader drop
#      with distinct RETRACTED label; nonexistent-target refusal; malformed retract entries
#      fail-safe — missing key AND explicit-empty both; re-add re-trusts; --hash form; chain
#      stays valid end-to-end)
#  10. sha-tool-absent branch (PATH sandbox): `add` stays a fail-safe no-op (exit 0, nothing
#      written) but `retract` FAILS LOUD (non-zero — a curation verb must never silently no-op)
#  11. supersede verb (PRE-CHECK -> RETRACT -> ADD, ST-3):
#      (a) MANDATORY eviction regression — supersede the MIDDLE entry of a FULL 3-entry category;
#          the other two survive (retract-first keeps the category at 3->2->3 so add-time
#          evict-oldest never fires; add-then-retract would have destroyed the oldest survivor)
#      (b) MANDATORY --replacement required (missing --replacement refused, store untouched;
#          --replacement rejected on a plain retract too)
#      (c) MANDATORY byte-identical refusal — target absent, and target present-but-not-chain-
#          trusted (a lingering out-of-band line), both fail loud (exit 4) with LESSONS.md AND
#          the provenance chain byte-identical to before
#      (d) trailer shape — supersedes=<8-char-hash> appended after confidence, last_verified
#          stays FIRST (read-lessons.sh's greedy strip still matches); reader emits the
#          replacement (hashed text unaffected by the trailer) and never emits the superseded text
#      (e) --hash form with auto-detected category (no explicit --category given)
#  12. --attest-existing (add-only heal for a line PRESENT in LESSONS.md but with no chain-valid
#      `add` backing it — the invisible-entry defect): reproduces the defect, proves a plain add
#      CANNOT fix it (dedup guard short-circuits before any provenance work), then asserts the
#      heal leaves LESSONS.md BYTE-IDENTICAL, makes the line readable, never evicts a sibling,
#      records the vouching `source`, is idempotent, refuses an absent target (exit 4, store
#      byte-identical), is rejected on retract/supersede (exit 2), and keeps the chain valid
#  13. REGRESSION (real store): count of `^- \[` lines in the repo's own LESSONS.md MUST equal the
#      count read-lessons.sh emits — i.e. no committed lesson is silently invisible to consumers

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WRITE="$HERE/write-lessons.sh"

# ---------------------------------------------------------------------------
# PROVENANCE IN FIXTURES (decision (f) / AC15 — provenance is STRICT and centralised in
# validate_provenance). An entry must cite what motivated it: a bare token like `s`, `test` or `ev`
# names nothing and is now REFUSED. These fixtures therefore pass a REAL reference. An earlier
# revision of this suite wrapped $WRITE in a shim that appended a provenanced --source to every
# call; that was deleted on review because it masked genuine refusals — a fixture whose entry was
# refused for an unrelated reason still went green. Sources are explicit and per-call now.
# ---------------------------------------------------------------------------
READ="$HERE/read-lessons.sh"
# ---------------------------------------------------------------------------
# seed_text — DISTINCT bodies for the cap/eviction seeding loops.
# The write-time duplicate check compares SIGNIFICANT tokens and excludes tokens shorter than 3
# chars, so bodies of the shape "<word> number $i" differ only in a 1-char token the checker drops:
# to it they were 100% identical, and every seed after the first was CORRECTLY refused as a
# duplicate. That is the check working, not a bug — so the fixtures seed semantically distinct
# entries instead of near-identical ones. Order is stable, so "oldest evicted" stays assertable.
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
LFILE=".supervisor/memory/LESSONS.md"
PJFILE=".supervisor/memory/.lessons-provenance.jsonl"

# sha() helper (mirrors the scripts under test) — used to hand-forge chain-valid provenance entries.
if command -v sha256sum >/dev/null 2>&1; then sha() { sha256sum | cut -d' ' -f1; }
else sha() { shasum -a 256 | cut -d' ' -f1; }; fi

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" "$TMP-wt" 2>/dev/null' EXIT
( cd "$TMP" && git init -q && git config user.email t@t && git config user.name t \
    && echo init > f && git add f && git commit -qm init )

echo "== 1. worktree-guard (MERGE BLOCKER) =="
git -C "$TMP" worktree add -q "$TMP-wt" -b wt >/dev/null 2>&1
( cd "$TMP-wt" && bash "$WRITE" --category auth --lesson "should be refused" --source "session:fixture-0001" ) >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 3 ]; then ok "writer refuses from a worktree (exit 3)"; else no "writer did NOT refuse worktree (exit $rc)"; fi
if [ ! -e "$TMP-wt/$LFILE" ]; then ok "no LESSONS written under the worktree"; else no "lessons leaked into the worktree"; fi
git -C "$TMP" worktree remove --force "$TMP-wt" >/dev/null 2>&1

echo "== 2. round-trip =="
( cd "$TMP" && bash "$WRITE" --category auth --lesson "auth is handled by signed JWT bearer tokens" --source "session:fixture-0001" ) >/dev/null 2>&1
f="$TMP/$LFILE"
if grep -q '^## auth$' "$f" 2>/dev/null && grep -q "auth is handled by signed JWT bearer tokens" "$f" 2>/dev/null; then
  ok "lesson appears under ## auth"
else
  no "lesson not found under ## auth"
fi
grep -q "bounded <=3 active per category" "$f" 2>/dev/null && ok "advisory banner present" || no "advisory banner missing"

echo "== 3. <=3/category eviction =="
BDIR="$(mktemp -d)"; ( cd "$BDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$BDIR" && for i in 1 2 3 4; do bash "$WRITE" --category build --lesson "$(seed_text $i)" --source "session:fixture-0001" >/dev/null 2>&1; done )
bf="$BDIR/$LFILE"
# Count `- [` entries under the ## build section only.
cnt="$(awk '/^## build$/{f=1;next} /^## /{f=0} f && /^- \[/{c++} END{print c+0}' "$bf" 2>/dev/null)"
if [ "$cnt" -eq 3 ]; then ok "capped at 3 entries under ## build (wrote 4, evicted 1)"; else no "per-category cap not enforced (have $cnt, want 3)"; fi
if grep -q "$(seed_text 1)" "$bf" 2>/dev/null; then no "oldest entry not evicted"; else ok "oldest entry (build lesson number 1) evicted"; fi
rm -rf "$BDIR"

echo "== 4. two categories independent =="
CDIR="$(mktemp -d)"; ( cd "$CDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$CDIR" && bash "$WRITE" --category auth --lesson "auth uses sessions" --source "session:fixture-0001" \
    && bash "$WRITE" --category db --lesson "db is postgres via drizzle" --source "session:fixture-0001" ) >/dev/null 2>&1
cf="$CDIR/$LFILE"
ac="$(awk '/^## auth$/{f=1;next} /^## /{f=0} f && /^- \[/{c++} END{print c+0}' "$cf" 2>/dev/null)"
dc="$(awk '/^## db$/{f=1;next} /^## /{f=0} f && /^- \[/{c++} END{print c+0}' "$cf" 2>/dev/null)"
if grep -q '^## auth$' "$cf" && grep -q '^## db$' "$cf" && [ "$ac" -eq 1 ] && [ "$dc" -eq 1 ]; then
  ok "both categories coexist with their entries (auth=$ac, db=$dc)"
else
  no "categories not independent (auth=$ac, db=$dc)"
fi
rm -rf "$CDIR"

echo "== 5. .gitignore coverage (real repo) =="
# INVERTED ON PURPOSE (2026-08-07). This asserted `.supervisor/memory/` was IGNORED. The
# `/setup memory` capability exists to make exactly that store COMMITTABLE — the Twin's distilled
# lessons otherwise live on one machine with no recovery path, and every fresh clone, CI run and
# `git worktree` checkout starts cold. This repo applied the managed negation block, so the old
# expectation is now the failure mode, not the invariant.
#
# The store's ignore status is owned by test-committed-twin-scrub.sh (which asserts the intended
# paths ARE committable, the unintended ones are NOT, and that the committed content carries no
# foreign-repo data). Kept here as a cheap consistency cross-check, stated in the new direction.
#
# `-q` is used ALONE — never with `--verbose`, which git rejects with exit 128, a status a bare
# `if` would silently read as "not ignored".
if git -C "$REAL_REPO" check-ignore -q .supervisor/memory/LESSONS.md 2>/dev/null; then
  no ".supervisor/memory/LESSONS.md is IGNORED in the real repo, but the applied /setup memory managed block must make it committable — the negation is not in effect (see test-committed-twin-scrub.sh)"
else
  ok ".supervisor/memory/LESSONS.md is committable in the real repo (managed negation block in effect)"
fi

echo "== 6. backslash integrity (awk ENVIRON, not -v) =="
WDIR="$(mktemp -d)"; ( cd "$WDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$WDIR" && bash "$WRITE" --category paths --lesson 'windows path C:\Users\x and a \n literal' --source "session:fixture-0001" ) >/dev/null 2>&1
wf="$WDIR/$LFILE"
# A lesson containing backslashes must be stored verbatim on ONE line. The old `awk -v lesson=`
# would interpret \n -> newline (splitting the entry) and mangle \U/\x — this guards the ENVIRON fix.
if grep -qF 'C:\Users\x and a \n literal' "$wf" 2>/dev/null; then ok "backslashes stored literally (no awk -v escape corruption)"; else no "lesson backslashes corrupted"; fi
pc="$(awk '/^## paths$/{f=1;next} /^## /{f=0} f && /^- \[/{c++} END{print c+0}' "$wf" 2>/dev/null)"
[ "$pc" -eq 1 ] && ok "lesson stored as a single entry line" || no "lesson split across lines (have $pc)"
rm -rf "$WDIR"

echo "== 7. freshness trailer (last_verified + confidence) =="
FDIR="$(mktemp -d)"; ( cd "$FDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
# (a) default trailer present with a plausible ISO timestamp + default confidence=medium
( cd "$FDIR" && bash "$WRITE" --category fresh --lesson "default freshness lesson" --source "session:fixture-0001" ) >/dev/null 2>&1
ff="$FDIR/$LFILE"
if grep -qE 'default freshness lesson  <!-- last_verified=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z confidence=medium -->' "$ff" 2>/dev/null; then
  ok "default last_verified+confidence trailer appended"
else
  no "default freshness trailer missing/malformed"
fi
# Substring grep still matches despite the trailer (dedup-guard invariant)
grep -qF -- "default freshness lesson" "$ff" 2>/dev/null && ok "substring grep still matches with trailer" || no "trailer broke substring grep"
# (b) explicit --last-verified + --confidence flags honored
( cd "$FDIR" && bash "$WRITE" --category fresh2 --lesson "explicit freshness lesson" --last-verified 2020-01-01T00:00:00Z --confidence high --source "session:fixture-0001" ) >/dev/null 2>&1
if grep -qF -- "explicit freshness lesson  <!-- last_verified=2020-01-01T00:00:00Z confidence=high -->" "$ff" 2>/dev/null; then
  ok "explicit --last-verified/--confidence honored"
else
  no "explicit freshness flags not honored"
fi
# (c) content_hash MUST NOT depend on the trailer: same cat+text written twice with DIFFERENT
#     freshness must produce the SAME [id] and dedup to a single entry.
( cd "$FDIR" && bash "$WRITE" --category hashstable --lesson "hash stable lesson" --last-verified 2021-01-01T00:00:00Z --confidence low --source "session:fixture-0001" ) >/dev/null 2>&1
( cd "$FDIR" && bash "$WRITE" --category hashstable --lesson "hash stable lesson" --last-verified 2099-01-01T00:00:00Z --confidence high --source "session:fixture-0001" ) >/dev/null 2>&1
hc="$(awk '/^## hashstable$/{f=1;next} /^## /{f=0} f && /^- \[/{c++} END{print c+0}' "$ff" 2>/dev/null)"
[ "$hc" -eq 1 ] && ok "trailer excluded from content_hash (re-verify deduped to one entry)" || no "trailer leaked into hash (have $hc entries, want 1)"
# (d) a MALFORMED --last-verified must fall back to the write-time default (cannot distort the
#     trailer the reader anchors on, and keeps lv backslash-safe under awk -v). A value containing
#     a `-->` and a space would, if accepted verbatim, corrupt the `<!-- ... -->` trailer shape.
( cd "$FDIR" && bash "$WRITE" --category badlv --lesson "bad lv lesson" --last-verified 'x --> y' --source "session:fixture-0001" ) >/dev/null 2>&1
if grep -qE 'bad lv lesson  <!-- last_verified=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z confidence=medium -->' "$ff" 2>/dev/null; then
  ok "malformed --last-verified rejected → write-time default stamped (trailer shape intact)"
else
  no "malformed --last-verified leaked into the trailer (shape not protected)"
fi
rm -rf "$FDIR"

echo "== 8. provenance write-side (.lessons-provenance.jsonl) =="
PDIR="$(mktemp -d)"; ( cd "$PDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$PDIR" && bash "$WRITE" --category prov --lesson "prov lesson one" --source "session:fixture-0001" ) >/dev/null 2>&1
pj="$PDIR/.supervisor/memory/.lessons-provenance.jsonl"
# Separate chain file exists and is distinct from PROJECT_MEMORY's .provenance.jsonl
if [ -f "$pj" ]; then ok "lessons provenance chain file created"; else no "lessons provenance chain file missing"; fi
[ -e "$PDIR/.supervisor/memory/.provenance.jsonl" ] && no "PROJECT_MEMORY chain file was touched (should be lessons-specific)" || ok "PROJECT_MEMORY chain file untouched (separate chain)"
# First entry is GENESIS-rooted add
grep -q '"prev_hash":"GENESIS"' "$pj" 2>/dev/null && grep -q '"action":"add"' "$pj" 2>/dev/null && ok "genesis-rooted add provenance line present" || no "genesis add line missing"
# Eviction emits per-evicted `evict` provenance lines
( cd "$PDIR" && for i in 1 2 3 4; do bash "$WRITE" --category evcat --lesson "$(seed_text $i)" --source "session:fixture-0001" >/dev/null 2>&1; done )
grep -q '"action":"evict"' "$pj" 2>/dev/null && ok "eviction recorded an evict provenance line" || no "evict provenance line missing"
# Dedup skip writes NO new provenance line (skip ⇒ touch nothing)
before="$(wc -l < "$pj" | tr -d ' ')"
( cd "$PDIR" && bash "$WRITE" --category prov --lesson "prov lesson one" --source "session:fixture-0001" ) >/dev/null 2>&1
after="$(wc -l < "$pj" | tr -d ' ')"
[ "$before" = "$after" ] && ok "dedup skip added no provenance line" || no "dedup skip wrote provenance ($before -> $after)"
rm -rf "$PDIR"

echo "== 9. retract verb (writer tombstone + reader drop) =="
RDIR="$(mktemp -d)"; ( cd "$RDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
rf="$RDIR/$LFILE"
rj="$RDIR/$PJFILE"
rlog="$RDIR/.supervisor/logs/memory.log"
( cd "$RDIR" && bash "$WRITE" --category ret --lesson "retract me lesson" --source "session:fixture-0001" \
    && bash "$WRITE" --category ret --lesson "keep me lesson" --source "session:fixture-0001" ) >/dev/null 2>&1
target_line="$(grep -F -- "retract me lesson" "$rf")"

# (a) retract removes the line, appends a chain-valid retract provenance entry, reader stops emitting
( cd "$RDIR" && bash "$WRITE" retract ret "retract me lesson" --source "session:fixture-0001" ) >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "retract exits 0 on an existing chain-trusted lesson" || no "retract failed (exit $rc)"
if grep -qF -- "retract me lesson" "$rf" 2>/dev/null; then no "retracted line still in LESSONS.md"; else ok "retracted line removed from LESSONS.md"; fi
grep -q '"action":"retract"' "$rj" 2>/dev/null && ok "retract provenance tombstone appended" || no "retract provenance entry missing"
grep -q '^## ret$' "$rf" 2>/dev/null && ok "category heading left in place after retract" || no "category heading dropped by retract"
out="$( cd "$RDIR" && bash "$READ" 2>/dev/null )"
if echo "$out" | grep -qF "retract me lesson"; then no "reader still emits the retracted lesson"; else ok "reader no longer emits the retracted lesson"; fi
echo "$out" | grep -qF "keep me lesson" && ok "untargeted lesson still emitted after retract" || no "untargeted lesson lost after retract"

# (b) retracted-but-line-lingers: re-append the original markdown line out-of-band under the same
#     category → reader drops it (does not emit) and logs it with the distinct RETRACTED label.
printf '%s\n' "$target_line" >> "$rf"
out="$( cd "$RDIR" && bash "$READ" 2>/dev/null )"
if echo "$out" | grep -qF "retract me lesson"; then no "lingering retracted line was emitted"; else ok "lingering retracted line dropped by reader"; fi
if [ -f "$rlog" ] && grep -q "RETRACTED" "$rlog" 2>/dev/null; then ok "lingering line logged with distinct RETRACTED label"; else no "RETRACTED label missing from memory.log"; fi
# Remove the lingering line again (out-of-band) so the later re-add sub-case starts clean
# (otherwise the writer's dedup guard would see it as already present and skip the re-add).
grep -vF -- "retract me lesson" "$rf" > "$rf.t" && mv "$rf.t" "$rf"

# (c) retract of a nonexistent lesson → non-zero exit, no provenance append, LESSONS.md unchanged
cp "$rf" "$rf.snap"; cp "$rj" "$rj.snap"
( cd "$RDIR" && bash "$WRITE" retract ret "never existed lesson" --source "session:fixture-0001" ) >/dev/null 2>&1
rc=$?
[ "$rc" -ne 0 ] && ok "retract of nonexistent lesson refused (exit $rc)" || no "retract of nonexistent lesson exited 0"
cmp -s "$rf" "$rf.snap" && ok "LESSONS.md unchanged after refused retract" || no "LESSONS.md changed on refused retract"
cmp -s "$rj" "$rj.snap" && ok "no provenance appended on refused retract" || no "provenance appended on refused retract"
rm -f "$rf.snap" "$rj.snap"

# (d) malformed retract provenance entries — hand-forged CHAIN-VALID (correct prev_hash) but with
#     (d1) the content_hash key MISSING entirely, and (d2) content_hash present-but-EMPTY (both
#     variants per the nullable-required presence-check discipline, PR #84). The reader must keep
#     emitting the untargeted lessons and exit 0 (fail-safe: malformed curation metadata ⇒ live).
ph="$(printf '%s' "$(tail -n1 "$rj")" | sha)"
printf '{"id":"deadbeef","prev_hash":"%s","source":"test","action":"retract","written_at":"2026-01-01T00:00:00Z"}\n' "$ph" >> "$rj"
ph="$(printf '%s' "$(tail -n1 "$rj")" | sha)"
printf '{"id":"deadbeef","prev_hash":"%s","content_hash":"","source":"test","action":"retract","written_at":"2026-01-01T00:00:00Z"}\n' "$ph" >> "$rj"
out="$( cd "$RDIR" && bash "$READ" 2>/dev/null )"; rrc=$?
[ "$rrc" -eq 0 ] && ok "reader exits 0 with malformed retract entries (fail-safe)" || no "reader exited $rrc on malformed retract entries"
echo "$out" | grep -qF "keep me lesson" && ok "untargeted lesson survives malformed retract entries (missing-key + empty-value)" || no "a malformed retract entry untrusted an unrelated lesson"

# (e) re-add after retract → emitted again (last action wins); chain stays valid end-to-end
( cd "$RDIR" && bash "$WRITE" --category ret --lesson "retract me lesson" --source "session:fixture-0001" ) >/dev/null 2>&1
out="$( cd "$RDIR" && bash "$READ" 2>/dev/null )"
echo "$out" | grep -qF "retract me lesson" && ok "re-added lesson emitted again (last action wins)" || no "re-add after retract not re-trusted"
err="$( cd "$RDIR" && bash "$READ" 2>&1 >/dev/null )"
if echo "$err" | grep -q "chain broken"; then no "chain reported broken after retract/re-add cycle"; else ok "provenance chain valid end-to-end across retract + malformed entries + re-add"; fi

# (f) --hash form: retract by full content_hash (no text) removes the re-added lesson again
h="$(printf '%s' "ret retract me lesson" | sha)"
( cd "$RDIR" && bash "$WRITE" retract --hash "$h" --source "session:fixture-0001" ) >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "retract --hash <content_hash> accepted" || no "retract --hash failed (exit $rc)"
out="$( cd "$RDIR" && bash "$READ" 2>/dev/null )"
if echo "$out" | grep -qF "retract me lesson"; then no "--hash retract did not untrust the lesson"; else ok "--hash retract removes + untrusts (add→retract→re-add→retract)"; fi
rm -rf "$RDIR"

echo "== 10. sha-tool-absent branch: add = fail-safe no-op, retract = fail LOUD =="
# PATH sandbox: a bin dir with ONLY the tools the writer needs BEFORE the sha() selection
# (bash/git/tr/sed) — sha256sum AND shasum are deliberately absent so `command -v` misses both.
SB="$(mktemp -d)"
for t in bash git tr sed; do
  p="$(command -v "$t" 2>/dev/null)" && ln -s "$p" "$SB/$t"
done
SDIR="$(mktemp -d)"; ( cd "$SDIR" && git init -q )
( cd "$SDIR" && PATH="$SB" bash "$WRITE" --category shaless --lesson "harmless add" --source "session:fixture-0001" ) >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "sha-less add is a fail-safe no-op (exit 0)" || no "sha-less add exited $rc (expected 0)"
[ ! -e "$SDIR/$LFILE" ] && ok "sha-less add wrote nothing" || no "sha-less add wrote LESSONS.md"
( cd "$SDIR" && PATH="$SB" bash "$WRITE" retract shaless "harmless add" ) >/dev/null 2>&1
rc=$?
[ "$rc" -ne 0 ] && ok "sha-less retract FAILS LOUD (exit $rc, non-zero)" || no "sha-less retract silently exited 0"
[ ! -e "$SDIR/$LFILE" ] && [ ! -e "$SDIR/$PJFILE" ] && ok "sha-less retract touched nothing" || no "sha-less retract wrote state"
rm -rf "$SB" "$SDIR"

echo "== 11. supersede verb (PRE-CHECK -> RETRACT -> ADD) =="

echo "-- 11a. MANDATORY: full 3-entry category, supersede the MIDDLE entry, other two survive --"
SDIR2="$(mktemp -d)"; ( cd "$SDIR2" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$SDIR2" && bash "$WRITE" --category cap --lesson "cap lesson one" --source "session:fixture-0001" \
    && bash "$WRITE" --category cap --lesson "cap lesson two" --source "session:fixture-0001" \
    && bash "$WRITE" --category cap --lesson "cap lesson three" --source "session:fixture-0001" ) >/dev/null 2>&1
s2f="$SDIR2/$LFILE"
cnt="$(awk '/^## cap$/{f=1;next} /^## /{f=0} f && /^- \[/{c++} END{print c+0}' "$s2f" 2>/dev/null)"
[ "$cnt" -eq 3 ] && ok "category full at 3 before supersede" || no "setup: category not full (have $cnt)"
( cd "$SDIR2" && bash "$WRITE" supersede cap "cap lesson two" --replacement "cap replacement two" --source "session:fixture-0001" ) >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "supersede of middle entry exits 0" || no "supersede of middle entry failed (exit $rc)"
cnt2="$(awk '/^## cap$/{f=1;next} /^## /{f=0} f && /^- \[/{c++} END{print c+0}' "$s2f" 2>/dev/null)"
[ "$cnt2" -eq 3 ] && ok "category still has exactly 3 entries after supersede (no eviction fired)" || no "eviction fired or entry lost (have $cnt2, want 3)"
grep -qF -- "cap lesson one" "$s2f" 2>/dev/null && ok "oldest entry (cap lesson one) SURVIVES the middle-entry supersede" || no "REGRESSION: oldest entry was destroyed by add-then-retract-shaped eviction"
grep -qF -- "cap lesson three" "$s2f" 2>/dev/null && ok "newest entry (cap lesson three) survives" || no "newest entry lost"
grep -qF -- "cap lesson two" "$s2f" 2>/dev/null && no "superseded entry (cap lesson two) still present" || ok "superseded entry (cap lesson two) removed"
grep -qF -- "cap replacement two" "$s2f" 2>/dev/null && ok "replacement entry (cap replacement two) present" || no "replacement entry missing"
old_id8="$(printf '%s' "cap cap lesson two" | sha | cut -c1-8)"
if grep -qE -- "cap replacement two  <!-- last_verified=[0-9TZ:-]+ confidence=[a-z]+ supersedes=${old_id8} -->" "$s2f" 2>/dev/null; then
  ok "replacement trailer carries supersedes=<8-char-hash-of-old-entry>, last_verified first"
else
  no "replacement trailer missing/malformed supersedes field"
fi
sp2j="$SDIR2/$PJFILE"
grep -q "\"action\":\"retract\"" "$sp2j" 2>/dev/null && ok "retract provenance entry recorded for the superseded target" || no "retract provenance missing"
grep -q "\"action\":\"add\"" "$sp2j" 2>/dev/null && ok "add provenance entry recorded for the replacement" || no "add provenance missing"
out2="$( cd "$SDIR2" && bash "$READ" 2>/dev/null )"
echo "$out2" | grep -qF "cap lesson two" && no "reader still emits the superseded lesson text" || ok "reader no longer emits the superseded lesson text"
echo "$out2" | grep -qF "cap replacement two" && ok "reader emits the replacement lesson" || no "reader does not emit the replacement lesson"
echo "$out2" | grep -qF "cap lesson one" && ok "reader still emits the surviving oldest entry" || no "reader lost the surviving oldest entry"
echo "$out2" | grep -qF "cap lesson three" && ok "reader still emits the surviving newest entry" || no "reader lost the surviving newest entry"
rm -rf "$SDIR2"

echo "-- 11b. MANDATORY: --replacement required for supersede; rejected on retract --"
RDIR2="$(mktemp -d)"; ( cd "$RDIR2" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$RDIR2" && bash "$WRITE" --category repl --lesson "needs replacement lesson" --source "session:fixture-0001" ) >/dev/null 2>&1
r2f="$RDIR2/$LFILE"; r2j="$RDIR2/$PJFILE"
cp "$r2f" "$r2f.snap"; cp "$r2j" "$r2j.snap"
( cd "$RDIR2" && bash "$WRITE" supersede repl "needs replacement lesson" --source "session:fixture-0001" ) >/dev/null 2>&1
rc=$?
[ "$rc" -ne 0 ] && ok "supersede without --replacement refused (exit $rc)" || no "supersede without --replacement exited 0"
cmp -s "$r2f" "$r2f.snap" && ok "LESSONS.md unchanged when --replacement missing" || no "LESSONS.md changed despite missing --replacement"
cmp -s "$r2j" "$r2j.snap" && ok "provenance unchanged when --replacement missing" || no "provenance changed despite missing --replacement"
( cd "$RDIR2" && bash "$WRITE" retract repl "needs replacement lesson" --replacement "nope" --source "session:fixture-0001" ) >/dev/null 2>&1
rc=$?
[ "$rc" -ne 0 ] && ok "retract with --replacement is rejected (exit $rc — replacement only meaningful for supersede)" || no "retract with --replacement was accepted"
cmp -s "$r2f" "$r2f.snap" && ok "LESSONS.md unchanged after rejected retract+--replacement" || no "LESSONS.md changed after rejected retract+--replacement"
rm -f "$r2f.snap" "$r2j.snap"
rm -rf "$RDIR2"

echo "-- 11c. MANDATORY: byte-identical refusal (absent target; present-but-not-chain-trusted target) --"
TDIR="$(mktemp -d)"; ( cd "$TDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$TDIR" && bash "$WRITE" --category trust --lesson "trust me lesson" --source "session:fixture-0001" ) >/dev/null 2>&1
tf="$TDIR/$LFILE"; tj="$TDIR/$PJFILE"
# (i) absent target: never written at all.
cp "$tf" "$tf.snap1"; cp "$tj" "$tj.snap1"
( cd "$TDIR" && bash "$WRITE" supersede trust "never existed lesson" --replacement "x" --source "session:fixture-0001" ) >/dev/null 2>&1
rc=$?
[ "$rc" -ne 0 ] && ok "supersede of an absent target refused (exit $rc)" || no "supersede of an absent target exited 0"
cmp -s "$tf" "$tf.snap1" && ok "LESSONS.md byte-identical after absent-target refusal" || no "LESSONS.md changed after absent-target refusal"
cmp -s "$tj" "$tj.snap1" && ok "provenance byte-identical after absent-target refusal" || no "provenance changed after absent-target refusal"
rm -f "$tf.snap1" "$tj.snap1"
# (ii) present-but-not-chain-trusted: retract the lesson (untrusts + removes the line), then
# re-append the original line out-of-band so it is PRESENT again but its hash is still untrusted.
target_line="$(grep -F -- "trust me lesson" "$tf")"
( cd "$TDIR" && bash "$WRITE" retract trust "trust me lesson" --source "session:fixture-0001" ) >/dev/null 2>&1
printf '%s\n' "$target_line" >> "$tf"
cp "$tf" "$tf.snap2"; cp "$tj" "$tj.snap2"
( cd "$TDIR" && bash "$WRITE" supersede trust "trust me lesson" --replacement "y" --source "session:fixture-0001" ) >/dev/null 2>&1
rc=$?
[ "$rc" -ne 0 ] && ok "supersede of a present-but-untrusted target refused (exit $rc)" || no "supersede of an untrusted target exited 0"
cmp -s "$tf" "$tf.snap2" && ok "LESSONS.md byte-identical after untrusted-target refusal" || no "LESSONS.md changed after untrusted-target refusal"
cmp -s "$tj" "$tj.snap2" && ok "provenance byte-identical after untrusted-target refusal" || no "provenance changed after untrusted-target refusal"
rm -f "$tf.snap2" "$tj.snap2"
rm -rf "$TDIR"

echo "-- 11e. --hash form with auto-detected category (no explicit --category given) --"
HDIR="$(mktemp -d)"; ( cd "$HDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$HDIR" && bash "$WRITE" --category hashcat --lesson "hash form target lesson" --source "session:fixture-0001" ) >/dev/null 2>&1
htarget_hash="$(printf '%s' "hashcat hash form target lesson" | sha)"
( cd "$HDIR" && bash "$WRITE" supersede --hash "$htarget_hash" --replacement "hash form replacement lesson" --source "session:fixture-0001" ) >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "supersede --hash accepted" || no "supersede --hash failed (exit $rc)"
hf="$HDIR/$LFILE"
grep -qF -- "hash form replacement lesson" "$hf" 2>/dev/null && grep -q '^## hashcat$' "$hf" 2>/dev/null \
  && ok "--hash supersede auto-detected the target's category (hashcat) for the replacement" \
  || no "--hash supersede did not place the replacement under the auto-detected category"
grep -qF -- "hash form target lesson" "$hf" 2>/dev/null && no "superseded (--hash targeted) entry still present" || ok "superseded (--hash targeted) entry removed"
rm -rf "$HDIR"

echo "== 12. --attest-existing (heal a present-but-unbacked line) =="
ADIR="$(mktemp -d)"; ( cd "$ADIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
af="$ADIR/$LFILE"; aj="$ADIR/$PJFILE"
# Seed one legitimately-written lesson so the store + chain exist, then append a SECOND line
# out-of-band (exactly the defect shape: present in LESSONS.md, no provenance backing it).
( cd "$ADIR" && bash "$WRITE" --category att --lesson "legit attested lesson" --source "session:fixture-0001" ) >/dev/null 2>&1
orphan_hash="$(printf '%s' "att orphan unbacked lesson" | sha)"; orphan_id="$(printf '%s' "$orphan_hash" | cut -c1-8)"
printf -- '- [%s] orphan unbacked lesson\n' "$orphan_id" >> "$af"

# Reader output is captured into a variable and matched with a case/glob rather than piped into
# `grep -q`. Under `set -o pipefail` a `producer | grep -q` pipeline can exit 141 (SIGPIPE) EVEN
# ON A MATCH, because -q closes the pipe as soon as it matches — a racy false FAIL that bit this
# very suite while it was being written.
emits() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
aread() { ( cd "$ADIR" && bash "$READ" ) 2>/dev/null; }

echo "-- 12a. baseline: the unbacked line is invisible to the reader --"
out="$(aread)"
emits "$out" "orphan unbacked lesson" \
  && no "reader emitted an unbacked line (provenance gate not enforcing)" \
  || ok "unbacked line is dropped by the reader (defect reproduced)"

echo "-- 12b. a plain add CANNOT heal it (dedup guard short-circuits) --"
cp "$aj" "$aj.snap"
( cd "$ADIR" && bash "$WRITE" --category att --lesson "orphan unbacked lesson" --source "session:fixture-0001" ) >/dev/null 2>&1
cmp -s "$aj" "$aj.snap" && ok "plain add wrote NO provenance for the present-but-unbacked line" || no "plain add unexpectedly wrote provenance"
out="$(aread)"
emits "$out" "orphan unbacked lesson" \
  && no "plain add somehow made the line readable" || ok "line still invisible after a plain add (the gap this flag closes)"

echo "-- 12c. --attest-existing heals it, leaving LESSONS.md BYTE-IDENTICAL --"
cp "$af" "$af.snap"
( cd "$ADIR" && bash "$WRITE" --category att --lesson "orphan unbacked lesson" --attest-existing --source "attest-test:pr-1" ) >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "attest exited 0" || no "attest failed (exit $rc)"
cmp -s "$af" "$af.snap" && ok "LESSONS.md byte-identical after attest (no rewrite, no trailer)" || no "attest rewrote LESSONS.md"
out="$(aread)"
emits "$out" "orphan unbacked lesson" \
  && ok "reader now emits the attested line" || no "attested line still not emitted"
# The sibling lesson must be untouched — an attest adds nothing to the category, so eviction
# must never fire (an attest that evicted a sibling would destroy data while claiming repair).
emits "$out" "legit attested lesson" \
  && ok "pre-existing sibling lesson still emitted (attest did not trigger eviction)" || no "attest evicted a sibling"
# `source` is recorded, so who vouched stays auditable.
grep -qF -- '"source":"attest-test:pr-1"' "$aj" && ok "attest provenance records the vouching source" || no "attest provenance lost the source"
grep -qF -- "\"content_hash\":\"$orphan_hash\"" "$aj" && ok "attest provenance carries the line's content_hash" || no "attest provenance has the wrong content_hash"

echo "-- 12d. attest is idempotent: a second attest is a no-op --"
cp "$aj" "$aj.snap2"
( cd "$ADIR" && bash "$WRITE" --category att --lesson "orphan unbacked lesson" --attest-existing --source "attest-test:pr-1" ) >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "re-attest of an already-trusted line exits 0" || no "re-attest exited $rc"
cmp -s "$aj" "$aj.snap2" && ok "re-attest appended NO duplicate provenance entry" || no "re-attest duplicated a provenance entry"

echo "-- 12e. attest NEVER creates: absent target fails loud (exit 4), store byte-identical --"
cp "$af" "$af.snap3"; cp "$aj" "$aj.snap3"
( cd "$ADIR" && bash "$WRITE" --category att --lesson "this line does not exist anywhere" --attest-existing --source "attest-test:pr-1" ) >/dev/null 2>&1
rc=$?
[ "$rc" -eq 4 ] && ok "attest of an absent line refused (exit 4)" || no "attest of an absent line exited $rc (expected 4)"
cmp -s "$af" "$af.snap3" && ok "LESSONS.md byte-identical after absent-target attest" || no "LESSONS.md changed after absent-target attest"
cmp -s "$aj" "$aj.snap3" && ok "provenance byte-identical after absent-target attest" || no "provenance changed after absent-target attest"

echo "-- 12f. --attest-existing is add-only (rejected on retract/supersede, exit 2) --"
for verb in retract supersede; do
  ( cd "$ADIR" && bash "$WRITE" "$verb" att "legit attested lesson" --attest-existing --replacement x --source "attest-test:pr-1" ) >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 2 ] && ok "--attest-existing rejected on $verb (exit 2)" || no "--attest-existing on $verb exited $rc (expected 2)"
done
cmp -s "$aj" "$aj.snap3" && ok "provenance byte-identical after add-only rejections" || no "provenance changed after add-only rejections"

echo "-- 12g. chain stays valid end-to-end after the attest appends --"
prev="GENESIS"; chain_ok=1; n=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  n=$((n+1))
  got="$(printf '%s' "$p" | sed -E 's/.*"prev_hash":"([^"]*)".*/\1/')"
  [ "$got" = "$prev" ] || { chain_ok=0; break; }
  prev="$(printf '%s' "$p" | sha)"
done < "$aj"
[ "$chain_ok" -eq 1 ] && [ "$n" -gt 0 ] && ok "provenance chain valid across all $n entries after attest" || no "chain broken at entry $n after attest"
rm -rf "$ADIR"

echo "== 13. REGRESSION: real store has no invisible entries (LESSONS.md count == reader count) =="
# Guards the invisible-entry class found 2026-08-08: 11 entries in LESSONS.md but only 5 emitted,
# because 6 lines had no chain-valid `add` backing them. A committed lesson the reader silently
# drops is worse than no lesson — every consumer believes it is active guidance when nothing reads
# it, and nothing else in CI compares the two counts. Compare by PREFIX-free counts: provenance
# stores the full 64-char sha256 while LESSONS.md shows the 8-char id, so a naive join on the two
# files reports either zero overlap or nothing missing depending on direction.
real_lessons="$REAL_REPO/$LFILE"
if [ -f "$real_lessons" ]; then
  # `|| true`, NOT `|| echo 0`: grep -c already PRINTS "0" before exiting 1 on no-match, so the
  # echo would append a SECOND line and make the -eq comparison below throw. (Same for the piped
  # form, which additionally needs the `|| true` because `set -o pipefail` is on.)
  file_n="$(grep -c '^- \[' "$real_lessons" 2>/dev/null || true)"
  read_n="$(cd "$REAL_REPO" && bash "$READ" 2>/dev/null | grep -c '^- \[' || true)"
  file_n="${file_n:-0}"; read_n="${read_n:-0}"
  if [ "$file_n" -eq "$read_n" ]; then
    ok "real LESSONS.md: all $file_n entries are readable (no unbacked/retracted-but-lingering lines)"
  else
    no "real LESSONS.md has $file_n entries but read-lessons.sh emits $read_n — $((file_n - read_n)) invisible; see .supervisor/logs/memory.log for the DROPPED/RETRACTED/STALE reason per line, then heal with: write-lessons.sh --category <cat> --lesson \"<text>\" --attest-existing"
  fi
else
  ok "real LESSONS.md absent — count-parity assertion vacuously satisfied"
fi

# =============================================================================
# 14. AC1 / AC2 / AC10a — WRITE-TIME VALIDATION AT THIS WRITER'S CALL SITE.
#
# WHY THIS SECTION EXISTS. Wiring write-lessons.sh to validate-entry.sh makes
# test-validate-entry.sh green and this suite green, and NEITHER of those proves this writer ever
# calls the validator: a writer that `source`s the helper and never invokes it passes both. The
# per-writer coverage — five seeded violations, three degraded-helper shapes, and the two mutation
# controls below — is the only thing that pins the CALL SITE rather than the helper.
#
# THREE SEPARATE ASSERTIONS PER CASE, and the separation is load-bearing (AC2). This writer commits
# via temp file + atomic `mv`, so "the store is byte-unchanged" is ALSO true of a plain crash, of an
# arg-parse rejection, and of a `command not found`. Byte-unchanged alone therefore does not
# discriminate a refusal from a fall-over. Each case asserts (i) the refusal EXIT STATUS, (ii) a
# NAMED, GREPPABLE reason on stderr, and (iii) the store byte-unchanged — compared with `cmp`
# against a saved copy, not a digest (exact bytes, and portable: `md5 -q` is BSD-only and this suite
# runs on Linux CI too).
# =============================================================================
echo "== 14. AC1/AC2/AC10a: write-time validation at the write-lessons call site =="
VETMP="$(mktemp -d)"
VEFILE="$HERE/validate-entry.sh"
VE_ERR="$VETMP/stderr"
VE_ALLOW=""

ve_repo() {
  local r; r="$(mktemp -d "$VETMP/r.XXXXXX")"
  ( cd "$r" && git init -q && git config user.email t@t && git config user.name t \
      && echo init > f && git add f && git commit -qm init ) >/dev/null 2>&1
  printf '%s' "$r"
}

# ve_write <repo> <lesson> <source> [validator-override] [writer-path] -> sets VE_RC, writes VE_ERR.
# An EMPTY validator-override leaves $WRITE_LESSONS_VALIDATOR empty, which is what makes the writer
# fall back to its own resolution — the real path, not a test-only one.
ve_write() {
  local repo="$1" txt="$2" src="$3" val="${4:-}" prog="${5:-$WRITE}"
  ( cd "$repo" \
      && if [ -n "$VE_ALLOW" ]; then export LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$VE_ALLOW"; fi \
      && WRITE_LESSONS_VALIDATOR="$val" bash "$prog" --category ve --lesson "$txt" --source "$src" \
  ) >/dev/null 2>"$VE_ERR"
  VE_RC=$?
}

# ve_refused <label> <want-rc> <want-token> <store> <saved-copy> — the three assertions.
ve_refused() {
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

# ---------------------------------------------------------------------------
# The seeds. Each one violates EXACTLY ONE check, because validate_entry_all returns the FIRST
# non-zero verdict in a fixed order (duplicate, contradiction, provenance, dead-reference,
# cross-repo) — a seed that tripped an earlier check would assert nothing about the later one.
#   VE_DUP    same significant-token set as VE_BASE, reordered. Reordered rather than repeated
#             because this writer's OWN dedup hashes category+text and short-circuits an exact
#             repeat at exit 0 BEFORE the validator runs (AC18); a byte-identical seed would test
#             that short-circuit, not the duplicate check.
#   VE_CON    VE_BASE with a negation token — same subject, opposite polarity.
#   VE_PROV   cites nothing (no PR/issue/session/commit token, no digit) AND is passed the bare
#             command name `dreaming` as --source, which decision (f) makes insufficient.
#   VE_DEAD   cites a path that does not resolve under the repo root.
#   VE_XREPO  cites `OTHERSVC #146` — repo-shaped and NOT in the allowlist. The allowlist is supplied
#             through this test's OWN environment; the live .supervisor/config.json is never
#             touched, and no foreign slug is ever added to it (R0/R8).
# ---------------------------------------------------------------------------
VE_BASE="release candidates promote through staging validation before production rollout begins across every regional cluster"
VE_DUP="across every regional cluster release candidates promote through staging validation before production rollout begins"
VE_CON="release candidates never promote through staging validation before production rollout begins across every regional cluster"
VE_PROV="the shared cache layer warms lazily on its very first read"
VE_DEAD="the retry helper now lives at loomwright/scripts/no-such-helper-xyz.sh"
VE_XREPO="the same defect was fixed in OTHERSVC #146"
VE_CLEAN="observability dashboards refresh their panels whenever a new deployment finishes rolling out"
VE_SRC="session:ve-0001"
VE_OURS="vikashruhilgit/loomwright"

# ve_case <label> <text> <source> <want-token> [allowlist] — seed a fresh repo with VE_BASE, snapshot
# the store, attempt the violating write, assert the three things.
ve_case() {
  local label="$1" txt="$2" src="$3" tok="$4" allow="${5:-}"
  local r st; r="$(ve_repo)"; st="$r/$LFILE"
  ve_write "$r" "$VE_BASE" "$VE_SRC"
  if [ ! -f "$st" ]; then no "$label — SEED FAILED (no LESSONS.md; the fixture asserts nothing)"; return; fi
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

# ---------------------------------------------------------------------------
# AC2 — the degraded-helper shapes. All four are built from the REAL helper so they cannot drift
# away from it, and each one is aimed at a DIFFERENT clause of the three-clause load guard:
#   absent      -> the `[ -f ] || [ -r ]` pre-check
#   unparse     -> clause (i): a trailing syntax error makes `source` exit non-zero. Bash still
#                  defines every function above the error, so this shape has ALL five validators
#                  AND the sentinel — only the source status distinguishes it.
#   partial     -> clause (ii): cut above validate_dead_reference, so three validators are defined
#                  and validate_entry_all is not. This is the shape a `command -v <one function>`
#                  probe would wave through as "examined and clean".
#   nosentinel  -> clause (iii): everything is defined and working, only the contract sentinel is
#                  missing. Nothing except clause (iii) can catch it — which is why it is also the
#                  vehicle for the `|| true` mutation control below.
# Each is attempted with a CLEAN entry, so the ONLY reason to refuse is the broken helper.
# ---------------------------------------------------------------------------
cp "$VEFILE" "$VETMP/unparse.sh"; printf '\nif [ ; then\n' >> "$VETMP/unparse.sh"
awk '/^validate_dead_reference\(\)/{exit} {print}'  "$VEFILE" > "$VETMP/partial.sh"
awk '/^VALIDATE_ENTRY_CONTRACT="/{exit} {print}'    "$VEFILE" > "$VETMP/nosentinel.sh"

# The three built variants must be the shape they claim to be, or the assertions below are vacuous:
# a `partial.sh` that failed to parse would exercise clause (i) while the label says clause (ii).
if bash -n "$VETMP/partial.sh" 2>/dev/null && bash -n "$VETMP/nosentinel.sh" 2>/dev/null \
   && ! bash -n "$VETMP/unparse.sh" 2>/dev/null; then
  ok "AC2 fixtures: partial+nosentinel parse cleanly, unparse does not (each aimed at its own clause)"
else
  no "AC2 fixtures: a degraded-helper variant is not the shape it claims — the clause labels below are unreliable"
fi

ve_degraded() { # <label> <validator-path>
  local label="$1" val="$2" r st; r="$(ve_repo)"; st="$r/$LFILE"
  ve_write "$r" "$VE_BASE" "$VE_SRC"
  if [ ! -f "$st" ]; then no "AC2 $label — SEED FAILED"; return; fi
  cp "$st" "$VETMP/before"
  ve_write "$r" "$VE_CLEAN" "$VE_SRC" "$val"
  ve_refused "AC2 $label:" 2 "REFUSE_VALIDATOR_UNAVAILABLE" "$st" "$VETMP/before"
}
ve_degraded "helper absent"      "$VETMP/no-such-validator.sh"
ve_degraded "helper unparseable" "$VETMP/unparse.sh"
ve_degraded "helper truncated"   "$VETMP/partial.sh"
ve_degraded "helper sentinel-less" "$VETMP/nosentinel.sh"

# ---------------------------------------------------------------------------
# MUTATION CONTROLS. Both mutants are COPIES in $VETMP: the writer on disk is never edited, which is
# what makes "this writer goes RED while the other four stay green" true by construction rather than
# by a sibling run — a temp-file copy provably cannot reach write-project-memory.sh, add-rule.sh,
# add-orientation.sh or write-system-contract.sh. Each mutant is gated on being non-empty, actually
# different, and still a parseable bash program before anything is credited to it (test-validate-
# entry.sh's first run produced an EMPTY mutant whose assertion went green while proving nothing).
# ---------------------------------------------------------------------------
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
# That writer has a confirm gate, so its (d6a)/(d6b) pair is dry-run-vs-confirmed. write-lessons.sh
# has NO dry-run: it emits the notice at each of its TERMINAL SUCCESS exits (the attest no-op, the
# completed attest, the completed retract, the supersede dedup-skip, and the shared add commit),
# after the operation has actually happened — so there is no not-yet-written path to compare
# against. So the two no-write halves here are the ones this writer really has —
# (n1) an ordinary CLEAN write, where the notice must stay silent because nothing was reported, and
# (n3) the idempotent dedup short-circuit, which returns before the validator runs at all and must
# never claim a write proceeded. Both are honest properties of the notice, and both are stated in
# the writer's own control flow rather than borrowed from a sibling's.
#
# WHICH HALF HAS TEETH, stated plainly rather than implied: (n1) and (n3) also pass against the
# mutant — an absent notice is absent on every path — so they pin the notice's SILENCE, not its
# existence. (n2) is the half that goes RED when the call is removed, and (n4) is what proves it.
# It is placed after ve_mutant_ok() rather than beside the advisory cases because it needs it.
# ---------------------------------------------------------------------------
echo "== 14n. the call-site advisory notice fires on the write path, and only there =="
# (n1) an ordinary CLEAN write draws no finding, so the notice must print NOTHING.
vnR1="$(ve_repo)"; vnS1="$vnR1/$LFILE"
ve_write "$vnR1" "$VE_CLEAN" "$VE_SRC"
if [ "$VE_RC" -eq 0 ] && [ -f "$vnS1" ]; then
  ok "(n1) fixture: a clean entry is written (exit 0) — this really is the wrote-and-nothing-to-report path"
else
  no "(n1) fixture: the clean write did not land (exit $VE_RC) — the silence below would prove nothing: $(tr '\n' ' ' < "$VE_ERR" | cut -c1-160)"
fi
if grep -qF 'THE WRITE PROCEEDED' "$VE_ERR" 2>/dev/null; then
  no "(n1) an ordinary clean write printed the advisory notice — it must be silent when no check reported anything"
else
  ok "(n1) an ordinary clean write is SILENT — the notice prints nothing when there is nothing to report"
fi

# (n2) a write carrying an ADVISORY finding: the notice MUST fire, in this writer's own name, and
# its sentence must be true — the entry really is on disk.
vnR2="$(ve_repo)"; vnS2="$vnR2/$LFILE"
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
if grep -qE '^write-lessons: ADVISORY:' "$VE_ERR" 2>/dev/null; then
  ok "(n2) and it is spoken in write-lessons' own name, not the helper's"
else
  no "(n2) the notice does not name this writer: $(tr '\n' ' ' < "$VE_ERR" | cut -c1-160)"
fi
if grep -qF 'no-such-helper-xyz' "$vnS2" 2>/dev/null; then
  ok "(n2) and the lesson really was stored — the notice's claim is true on this path"
else
  no "(n2) the notice claimed the write proceeded but no lesson landed in $LFILE"
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
echo "== 14n. MUTATION CONTROL: with the call-site notice removed, (n2) goes RED =="
VN_CALL='validate_entry_advisory_notice "write-lessons"'
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
  vnR4="$(ve_repo)"; vnS4="$vnR4/$LFILE"
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

# (a) AC1's mandated per-writer control: script the VALIDATOR CALL block out. The block is REPLACED
# with `:` rather than deleted because it sits inside an `if ... fi` whose body must not become
# empty (that is a bash syntax error, and a mutant that cannot run proves nothing).
awk '/---- VALIDATOR CALL BEGIN/{s=1; print "  :"; next} /---- VALIDATOR CALL END/{s=0; next} !s' \
  "$WRITE" > "$VETMP/mut-call.sh"
if ve_mutant_ok "$VETMP/mut-call.sh" "AC1 call-site mutant"; then
  r="$(ve_repo)"; st="$r/$LFILE"
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
# convention — the one line decision (a) forbids on the source. Paired with the sentinel-less helper,
# because that is the shape where the mutation is actually OBSERVABLE: with an absent or truncated
# helper the writer still fails closed by accident (validate_entry_all is undefined, so the call
# returns 127 and the writer exits 2 with no named reason), but with a sentinel-less helper every
# validator works, so dropping the guard lets an UNVERIFIED-CONTRACT write go all the way through.
# All three AC2 assertions go RED at once: exit 0, no named reason, store MUTATED.
awk '/---- LOAD GUARD BEGIN/{s=1; print "  . \"$VALIDATOR\" || true"; next} /---- LOAD GUARD END/{s=0; next} !s' \
  "$WRITE" > "$VETMP/mut-guard.sh"
if ve_mutant_ok "$VETMP/mut-guard.sh" "AC2 load-guard mutant"; then
  if grep -q '|| true' "$VETMP/mut-guard.sh"; then
    r="$(ve_repo)"; st="$r/$LFILE"
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

# ---------------------------------------------------------------------------
# AC10a — RE-VERIFICATION, with one assertion section 1 does not make. Section 1 proves the worktree
# CWD is refused with exit 3; this proves the worktree guard still runs BEFORE the validator load
# guard, i.e. wiring the validator in did not reorder them. With a deliberately absent validator the
# refusal must STILL be the worktree's exit 3, never the load guard's exit 2 — otherwise a worktree
# write would start reporting "could not examine" and the F1 refusal would be masked by AC2's.
# ---------------------------------------------------------------------------
VEWT="$(ve_repo)"
git -C "$VEWT" worktree add -q "$VEWT-wt" -b vewt >/dev/null 2>&1
if [ -d "$VEWT-wt" ]; then
  ve_write "$VEWT-wt" "$VE_CLEAN" "$VE_SRC" "$VETMP/no-such-validator.sh"
  if [ "$VE_RC" -eq 3 ] && grep -q worktree "$VE_ERR" 2>/dev/null; then
    ok "AC10a: a worktree CWD still refuses with exit 3, ahead of the validator load guard (absent helper does not mask it)"
  else
    no "AC10a: worktree refusal is exit $VE_RC (want 3) — the validator guard now precedes the worktree guard"
  fi
  [ -e "$VEWT-wt/$LFILE" ] && no "AC10a: lessons leaked into the worktree" \
    || ok "AC10a: nothing written under the worktree"
  git -C "$VEWT" worktree remove --force "$VEWT-wt" >/dev/null 2>&1
else
  no "AC10a: could not create the fixture worktree — the assertion would be vacuous"
fi
rm -rf "$VETMP" "$VEWT-wt" 2>/dev/null

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
