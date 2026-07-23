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

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WRITE="$HERE/write-lessons.sh"
READ="$HERE/read-lessons.sh"
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
( cd "$TMP-wt" && bash "$WRITE" --category auth --lesson "should be refused" --source test ) >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 3 ]; then ok "writer refuses from a worktree (exit 3)"; else no "writer did NOT refuse worktree (exit $rc)"; fi
if [ ! -e "$TMP-wt/$LFILE" ]; then ok "no LESSONS written under the worktree"; else no "lessons leaked into the worktree"; fi
git -C "$TMP" worktree remove --force "$TMP-wt" >/dev/null 2>&1

echo "== 2. round-trip =="
( cd "$TMP" && bash "$WRITE" --category auth --lesson "auth is JWT in src/auth/guard.ts" --source s1 ) >/dev/null 2>&1
f="$TMP/$LFILE"
if grep -q '^## auth$' "$f" 2>/dev/null && grep -q "auth is JWT in src/auth/guard.ts" "$f" 2>/dev/null; then
  ok "lesson appears under ## auth"
else
  no "lesson not found under ## auth"
fi
grep -q "bounded <=3 active per category" "$f" 2>/dev/null && ok "advisory banner present" || no "advisory banner missing"

echo "== 3. <=3/category eviction =="
BDIR="$(mktemp -d)"; ( cd "$BDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$BDIR" && for i in 1 2 3 4; do bash "$WRITE" --category build --lesson "build lesson number $i" --source ev >/dev/null 2>&1; done )
bf="$BDIR/$LFILE"
# Count `- [` entries under the ## build section only.
cnt="$(awk '/^## build$/{f=1;next} /^## /{f=0} f && /^- \[/{c++} END{print c+0}' "$bf" 2>/dev/null)"
if [ "$cnt" -eq 3 ]; then ok "capped at 3 entries under ## build (wrote 4, evicted 1)"; else no "per-category cap not enforced (have $cnt, want 3)"; fi
if grep -q "build lesson number 1" "$bf" 2>/dev/null; then no "oldest entry not evicted"; else ok "oldest entry (build lesson number 1) evicted"; fi
rm -rf "$BDIR"

echo "== 4. two categories independent =="
CDIR="$(mktemp -d)"; ( cd "$CDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$CDIR" && bash "$WRITE" --category auth --lesson "auth uses sessions" --source s \
    && bash "$WRITE" --category db --lesson "db is postgres via drizzle" --source s ) >/dev/null 2>&1
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
if git -C "$REAL_REPO" check-ignore -q .supervisor/memory/LESSONS.md 2>/dev/null; then ok ".supervisor/memory/ is gitignored in the real repo"; else no ".supervisor/memory/ NOT gitignored"; fi

echo "== 6. backslash integrity (awk ENVIRON, not -v) =="
WDIR="$(mktemp -d)"; ( cd "$WDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$WDIR" && bash "$WRITE" --category paths --lesson 'windows path C:\Users\x and a \n literal' --source s ) >/dev/null 2>&1
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
( cd "$FDIR" && bash "$WRITE" --category fresh --lesson "default freshness lesson" --source s ) >/dev/null 2>&1
ff="$FDIR/$LFILE"
if grep -qE 'default freshness lesson  <!-- last_verified=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z confidence=medium -->' "$ff" 2>/dev/null; then
  ok "default last_verified+confidence trailer appended"
else
  no "default freshness trailer missing/malformed"
fi
# Substring grep still matches despite the trailer (dedup-guard invariant)
grep -qF -- "default freshness lesson" "$ff" 2>/dev/null && ok "substring grep still matches with trailer" || no "trailer broke substring grep"
# (b) explicit --last-verified + --confidence flags honored
( cd "$FDIR" && bash "$WRITE" --category fresh2 --lesson "explicit freshness lesson" --last-verified 2020-01-01T00:00:00Z --confidence high --source s ) >/dev/null 2>&1
if grep -qF -- "explicit freshness lesson  <!-- last_verified=2020-01-01T00:00:00Z confidence=high -->" "$ff" 2>/dev/null; then
  ok "explicit --last-verified/--confidence honored"
else
  no "explicit freshness flags not honored"
fi
# (c) content_hash MUST NOT depend on the trailer: same cat+text written twice with DIFFERENT
#     freshness must produce the SAME [id] and dedup to a single entry.
( cd "$FDIR" && bash "$WRITE" --category hashstable --lesson "hash stable lesson" --last-verified 2021-01-01T00:00:00Z --confidence low --source s ) >/dev/null 2>&1
( cd "$FDIR" && bash "$WRITE" --category hashstable --lesson "hash stable lesson" --last-verified 2099-01-01T00:00:00Z --confidence high --source s ) >/dev/null 2>&1
hc="$(awk '/^## hashstable$/{f=1;next} /^## /{f=0} f && /^- \[/{c++} END{print c+0}' "$ff" 2>/dev/null)"
[ "$hc" -eq 1 ] && ok "trailer excluded from content_hash (re-verify deduped to one entry)" || no "trailer leaked into hash (have $hc entries, want 1)"
# (d) a MALFORMED --last-verified must fall back to the write-time default (cannot distort the
#     trailer the reader anchors on, and keeps lv backslash-safe under awk -v). A value containing
#     a `-->` and a space would, if accepted verbatim, corrupt the `<!-- ... -->` trailer shape.
( cd "$FDIR" && bash "$WRITE" --category badlv --lesson "bad lv lesson" --last-verified 'x --> y' --source s ) >/dev/null 2>&1
if grep -qE 'bad lv lesson  <!-- last_verified=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z confidence=medium -->' "$ff" 2>/dev/null; then
  ok "malformed --last-verified rejected → write-time default stamped (trailer shape intact)"
else
  no "malformed --last-verified leaked into the trailer (shape not protected)"
fi
rm -rf "$FDIR"

echo "== 8. provenance write-side (.lessons-provenance.jsonl) =="
PDIR="$(mktemp -d)"; ( cd "$PDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$PDIR" && bash "$WRITE" --category prov --lesson "prov lesson one" --source s ) >/dev/null 2>&1
pj="$PDIR/.supervisor/memory/.lessons-provenance.jsonl"
# Separate chain file exists and is distinct from PROJECT_MEMORY's .provenance.jsonl
if [ -f "$pj" ]; then ok "lessons provenance chain file created"; else no "lessons provenance chain file missing"; fi
[ -e "$PDIR/.supervisor/memory/.provenance.jsonl" ] && no "PROJECT_MEMORY chain file was touched (should be lessons-specific)" || ok "PROJECT_MEMORY chain file untouched (separate chain)"
# First entry is GENESIS-rooted add
grep -q '"prev_hash":"GENESIS"' "$pj" 2>/dev/null && grep -q '"action":"add"' "$pj" 2>/dev/null && ok "genesis-rooted add provenance line present" || no "genesis add line missing"
# Eviction emits per-evicted `evict` provenance lines
( cd "$PDIR" && for i in 1 2 3 4; do bash "$WRITE" --category evcat --lesson "ev lesson $i" --source s >/dev/null 2>&1; done )
grep -q '"action":"evict"' "$pj" 2>/dev/null && ok "eviction recorded an evict provenance line" || no "evict provenance line missing"
# Dedup skip writes NO new provenance line (skip ⇒ touch nothing)
before="$(wc -l < "$pj" | tr -d ' ')"
( cd "$PDIR" && bash "$WRITE" --category prov --lesson "prov lesson one" --source s ) >/dev/null 2>&1
after="$(wc -l < "$pj" | tr -d ' ')"
[ "$before" = "$after" ] && ok "dedup skip added no provenance line" || no "dedup skip wrote provenance ($before -> $after)"
rm -rf "$PDIR"

echo "== 9. retract verb (writer tombstone + reader drop) =="
RDIR="$(mktemp -d)"; ( cd "$RDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
rf="$RDIR/$LFILE"
rj="$RDIR/$PJFILE"
rlog="$RDIR/.supervisor/logs/memory.log"
( cd "$RDIR" && bash "$WRITE" --category ret --lesson "retract me lesson" --source s \
    && bash "$WRITE" --category ret --lesson "keep me lesson" --source s ) >/dev/null 2>&1
target_line="$(grep -F -- "retract me lesson" "$rf")"

# (a) retract removes the line, appends a chain-valid retract provenance entry, reader stops emitting
( cd "$RDIR" && bash "$WRITE" retract ret "retract me lesson" --source curator ) >/dev/null 2>&1
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
( cd "$RDIR" && bash "$WRITE" retract ret "never existed lesson" --source curator ) >/dev/null 2>&1
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
( cd "$RDIR" && bash "$WRITE" --category ret --lesson "retract me lesson" --source s ) >/dev/null 2>&1
out="$( cd "$RDIR" && bash "$READ" 2>/dev/null )"
echo "$out" | grep -qF "retract me lesson" && ok "re-added lesson emitted again (last action wins)" || no "re-add after retract not re-trusted"
err="$( cd "$RDIR" && bash "$READ" 2>&1 >/dev/null )"
if echo "$err" | grep -q "chain broken"; then no "chain reported broken after retract/re-add cycle"; else ok "provenance chain valid end-to-end across retract + malformed entries + re-add"; fi

# (f) --hash form: retract by full content_hash (no text) removes the re-added lesson again
h="$(printf '%s' "ret retract me lesson" | sha)"
( cd "$RDIR" && bash "$WRITE" retract --hash "$h" --source curator ) >/dev/null 2>&1
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
( cd "$SDIR" && PATH="$SB" bash "$WRITE" --category shaless --lesson "harmless add" --source t ) >/dev/null 2>&1
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
( cd "$SDIR2" && bash "$WRITE" --category cap --lesson "cap lesson one" --source s \
    && bash "$WRITE" --category cap --lesson "cap lesson two" --source s \
    && bash "$WRITE" --category cap --lesson "cap lesson three" --source s ) >/dev/null 2>&1
s2f="$SDIR2/$LFILE"
cnt="$(awk '/^## cap$/{f=1;next} /^## /{f=0} f && /^- \[/{c++} END{print c+0}' "$s2f" 2>/dev/null)"
[ "$cnt" -eq 3 ] && ok "category full at 3 before supersede" || no "setup: category not full (have $cnt)"
( cd "$SDIR2" && bash "$WRITE" supersede cap "cap lesson two" --replacement "cap replacement two" --source curator ) >/dev/null 2>&1
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
( cd "$RDIR2" && bash "$WRITE" --category repl --lesson "needs replacement lesson" --source s ) >/dev/null 2>&1
r2f="$RDIR2/$LFILE"; r2j="$RDIR2/$PJFILE"
cp "$r2f" "$r2f.snap"; cp "$r2j" "$r2j.snap"
( cd "$RDIR2" && bash "$WRITE" supersede repl "needs replacement lesson" --source curator ) >/dev/null 2>&1
rc=$?
[ "$rc" -ne 0 ] && ok "supersede without --replacement refused (exit $rc)" || no "supersede without --replacement exited 0"
cmp -s "$r2f" "$r2f.snap" && ok "LESSONS.md unchanged when --replacement missing" || no "LESSONS.md changed despite missing --replacement"
cmp -s "$r2j" "$r2j.snap" && ok "provenance unchanged when --replacement missing" || no "provenance changed despite missing --replacement"
( cd "$RDIR2" && bash "$WRITE" retract repl "needs replacement lesson" --replacement "nope" --source curator ) >/dev/null 2>&1
rc=$?
[ "$rc" -ne 0 ] && ok "retract with --replacement is rejected (exit $rc — replacement only meaningful for supersede)" || no "retract with --replacement was accepted"
cmp -s "$r2f" "$r2f.snap" && ok "LESSONS.md unchanged after rejected retract+--replacement" || no "LESSONS.md changed after rejected retract+--replacement"
rm -f "$r2f.snap" "$r2j.snap"
rm -rf "$RDIR2"

echo "-- 11c. MANDATORY: byte-identical refusal (absent target; present-but-not-chain-trusted target) --"
TDIR="$(mktemp -d)"; ( cd "$TDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$TDIR" && bash "$WRITE" --category trust --lesson "trust me lesson" --source s ) >/dev/null 2>&1
tf="$TDIR/$LFILE"; tj="$TDIR/$PJFILE"
# (i) absent target: never written at all.
cp "$tf" "$tf.snap1"; cp "$tj" "$tj.snap1"
( cd "$TDIR" && bash "$WRITE" supersede trust "never existed lesson" --replacement "x" --source curator ) >/dev/null 2>&1
rc=$?
[ "$rc" -ne 0 ] && ok "supersede of an absent target refused (exit $rc)" || no "supersede of an absent target exited 0"
cmp -s "$tf" "$tf.snap1" && ok "LESSONS.md byte-identical after absent-target refusal" || no "LESSONS.md changed after absent-target refusal"
cmp -s "$tj" "$tj.snap1" && ok "provenance byte-identical after absent-target refusal" || no "provenance changed after absent-target refusal"
rm -f "$tf.snap1" "$tj.snap1"
# (ii) present-but-not-chain-trusted: retract the lesson (untrusts + removes the line), then
# re-append the original line out-of-band so it is PRESENT again but its hash is still untrusted.
target_line="$(grep -F -- "trust me lesson" "$tf")"
( cd "$TDIR" && bash "$WRITE" retract trust "trust me lesson" --source curator ) >/dev/null 2>&1
printf '%s\n' "$target_line" >> "$tf"
cp "$tf" "$tf.snap2"; cp "$tj" "$tj.snap2"
( cd "$TDIR" && bash "$WRITE" supersede trust "trust me lesson" --replacement "y" --source curator ) >/dev/null 2>&1
rc=$?
[ "$rc" -ne 0 ] && ok "supersede of a present-but-untrusted target refused (exit $rc)" || no "supersede of an untrusted target exited 0"
cmp -s "$tf" "$tf.snap2" && ok "LESSONS.md byte-identical after untrusted-target refusal" || no "LESSONS.md changed after untrusted-target refusal"
cmp -s "$tj" "$tj.snap2" && ok "provenance byte-identical after untrusted-target refusal" || no "provenance changed after untrusted-target refusal"
rm -f "$tf.snap2" "$tj.snap2"
rm -rf "$TDIR"

echo "-- 11e. --hash form with auto-detected category (no explicit --category given) --"
HDIR="$(mktemp -d)"; ( cd "$HDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$HDIR" && bash "$WRITE" --category hashcat --lesson "hash form target lesson" --source s ) >/dev/null 2>&1
htarget_hash="$(printf '%s' "hashcat hash form target lesson" | sha)"
( cd "$HDIR" && bash "$WRITE" supersede --hash "$htarget_hash" --replacement "hash form replacement lesson" --source curator ) >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "supersede --hash accepted" || no "supersede --hash failed (exit $rc)"
hf="$HDIR/$LFILE"
grep -qF -- "hash form replacement lesson" "$hf" 2>/dev/null && grep -q '^## hashcat$' "$hf" 2>/dev/null \
  && ok "--hash supersede auto-detected the target's category (hashcat) for the replacement" \
  || no "--hash supersede did not place the replacement under the auto-detected category"
grep -qF -- "hash form target lesson" "$hf" 2>/dev/null && no "superseded (--hash targeted) entry still present" || ok "superseded (--hash targeted) entry removed"
rm -rf "$HDIR"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
