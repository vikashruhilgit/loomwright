# ============================================================================
# BRANCH MODE — meta-entry (pull BEFORE the first read) + meta-push-failed + meta-publish (publish-
# on-write; skills/automate-loop/SKILL.md §"Branch mode"). Hermetic: a mktemp world with a LOCAL bare
# origin, never GitHub.
# ============================================================================
echo "== branch mode: meta-entry / meta-push-failed / meta-publish =="
BM_T="$(mktemp -d)"
BM_MS="$HERE/meta-sync.sh"
BM_SM="$HERE/setup-memory.sh"
bm_env() { env HOME="$BM_T/home" GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@test.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@test.invalid "$@"; }
mkdir -p "$BM_T/home"
# bm_world <dir> <mode: on|off> — bare origin + seed (main carries .gitignore; mode on ⇒ the
# branch-mode block + an initialised loomwright-meta branch) + a clone `work`.
bm_world() {
  local w="$1" mode="$2"
  mkdir -p "$w"
  bm_env git init -q --bare "$w/origin.git"
  git --git-dir="$w/origin.git" symbolic-ref HEAD refs/heads/main
  bm_env git init -q "$w/seed"
  (
    cd "$w/seed" || exit 1
    git symbolic-ref HEAD refs/heads/main
    printf '.supervisor/\n' > .gitignore
    [ "$mode" = on ] && bm_env bash "$BM_SM" --root "$w/seed" apply --branch-mode loomwright-meta >/dev/null 2>&1
    rm -f .gitignore.backup.*
    echo code > app.txt
    bm_env git add .gitignore app.txt && bm_env git commit -qm code
    git remote add origin "$w/origin.git" && bm_env git push -q origin main
    [ "$mode" = on ] && bm_env bash "$BM_MS" init --root "$w/seed" >/dev/null 2>&1
    true
  ) >/dev/null 2>&1
  bm_env git clone -q "$w/origin.git" "$w/work" >/dev/null 2>&1
}
bm_entry() { (cd "$1" && bm_env bash "$H" meta-entry --root "$1" 2>/dev/null); }

# (bm1) mode off ⇒ `meta-entry: off`, no network needed.
bm_world "$BM_T/off" off
o="$(bm_entry "$BM_T/off/work")"
[ "$o" = "meta-entry: off" ] && ok "BM1 mode off ⇒ 'meta-entry: off'" || no "BM1 mode off ⇒ '$o'"

# (bm2) a paused run file present ONLY on the metadata branch ⇒ resume-glob is blind before the
# pull and lists it after `meta-entry: pulled`.
bm_world "$BM_T/on" on
bm_env git clone -q "$BM_T/on/origin.git" "$BM_T/on/other" >/dev/null 2>&1
mkdir -p "$BM_T/on/other/.supervisor/automate"
printf '# Automate Run: automate-2026-10-02-000000\n\n## Status: paused\n\n## Queue\n- [ ] item\n\n## Progress\n' > "$BM_T/on/other/.supervisor/automate/automate-2026-10-02-000000.md"
bm_env bash "$BM_MS" push --root "$BM_T/on/other" --branch loomwright-meta >/dev/null 2>&1
before="$(bash "$H" resume-glob "$BM_T/on/work/.supervisor/automate" 2>/dev/null)"
[ -z "$before" ] && ok "BM2 before meta-entry the clone's resume-glob is EMPTY (the silent-amnesia shape)" || no "BM2 precondition: resume-glob already listed '$before'"
o="$(bm_entry "$BM_T/on/work")"
[ "$o" = "meta-entry: pulled loomwright-meta" ] && ok "BM2 mode on + reachable ⇒ 'meta-entry: pulled loomwright-meta'" || no "BM2 meta-entry ⇒ '$o'"
after="$(bash "$H" resume-glob "$BM_T/on/work/.supervisor/automate" 2>/dev/null)"
case "$after" in *automate-2026-10-02-000000.md) ok "BM2 after the pull resume-glob lists the paused run" ;; *) no "BM2 resume-glob after pull: '$after'" ;; esac

# (bm3) unreachable remote + no run file ⇒ `failed — …`, .supervisor/automate unchanged.
bm_world "$BM_T/un" on
git -C "$BM_T/un/work" remote set-url origin "$BM_T/un/no-such-origin.git"
ls_before="$(ls -A "$BM_T/un/work/.supervisor/automate" 2>&1)"
o="$(bm_entry "$BM_T/un/work")"
ls_after="$(ls -A "$BM_T/un/work/.supervisor/automate" 2>&1)"
bm3_assert() {  # bm3_assert <meta-entry output> — the "abort, nothing created" assertion
  case "$1" in "meta-entry: failed — "*) ;; *) return 1 ;; esac
  [ "$ls_before" = "$ls_after" ]
}
bm3_assert "$o" && ok "BM3 unreachable remote ⇒ '$o' and ls .supervisor/automate unchanged" || no "BM3 unreachable remote ⇒ '$o' (ls before='$ls_before' after='$ls_after')"
# Mutation control (i): a pull stand-in that exits 0 on the fetch failure MUST turn BM3 red.
printf '#!/usr/bin/env bash\nbash "%s" "$@" >/dev/null 2>&1\nexit 0\n' "$BM_MS" > "$BM_T/lying-meta-sync.sh"
o_mut="$(cd "$BM_T/un/work" && LOOMWRIGHT_META_SYNC_BIN="$BM_T/lying-meta-sync.sh" bm_env bash "$H" meta-entry --root "$BM_T/un/work" 2>/dev/null)"
if bm3_assert "$o_mut"; then no "BM3 mutation control (i) REFUTED: a pull that lies (exit 0 on fetch failure) still passed the abort assertion ('$o_mut')"; else ok "BM3 mutation control (i): a lying pull ('$o_mut') turns the abort assertion RED — it is load-bearing"; fi

# (bm4) mode unknown ⇒ failed — mode unknown (…), no pull attempted.
bm_world "$BM_T/uk" on
awk '{print} index($0, "# loomwright-meta-branch: ") == 1 {print "# loomwright-meta-branch: other"}' "$BM_T/uk/work/.gitignore" > "$BM_T/uk/g" && mv "$BM_T/uk/g" "$BM_T/uk/work/.gitignore"
o="$(bm_entry "$BM_T/uk/work")"
case "$o" in "meta-entry: failed — mode unknown ("*) ok "BM4 two mode lines ⇒ '$o'" ;; *) no "BM4 mode unknown ⇒ '$o'" ;; esac
[ ! -e "$BM_T/uk/work/.supervisor" ] && ok "BM4 mode unknown created nothing under .supervisor/" || no "BM4 mode unknown wrote under .supervisor/"
[ "$(bm_entry "$BM_T/uk/work" | wc -l | tr -d ' ')" = 1 ] && ok "BM4 meta-entry prints exactly ONE line" || no "BM4 meta-entry printed more than one line"
(cd "$BM_T/uk/work" && bm_env bash "$H" meta-entry --root "$BM_T/uk/work" >/dev/null 2>&1); [ $? -eq 0 ] && ok "BM4 meta-entry exits 0 on failure" || no "BM4 meta-entry exited non-zero"

# (bm5) meta-push-failed: nothing without a marker; the marker's first line with one.
mkdir -p "$BM_T/mp/.supervisor/automate"; RF="$BM_T/mp/.supervisor/automate/automate-2026-10-02-000001.md"
printf '# Automate Run: automate-2026-10-02-000001\n' > "$RF"
o="$(bash "$H" meta-push-failed "$RF" 2>/dev/null)"; rc=$?
[ -z "$o" ] && [ "$rc" -eq 0 ] && ok "BM5 meta-push-failed with no marker prints nothing, exit 0" || no "BM5 no marker ⇒ '$o' rc=$rc"
printf '2026-10-02T00:00:00Z conflict .supervisor/automate/x.md\nmeta_sync: scrub a: rule\n' > "$BM_T/mp/.supervisor/automate/automate-2026-10-02-000001.meta-push-failed"
o="$(bash "$H" meta-push-failed "$RF" 2>/dev/null)"
[ "$o" = "2026-10-02T00:00:00Z conflict .supervisor/automate/x.md" ] && ok "BM5 meta-push-failed prints the marker's first line" || no "BM5 marker ⇒ '$o'"
o="$(bash "$H" resume-glob "$BM_T/mp/.supervisor/automate" 2>/dev/null)"
case "$o" in *meta-push-failed*) no "BM5 resume-glob lists the marker" ;; *) ok "BM5 resume-glob never lists the .meta-push-failed marker" ;; esac
# (bm6) a repo that NEVER opted in reads `meta-entry: off` even when its .gitignore is one the
# setup-memory WRITER would refuse to rewrite (read-only / conflict-marked) — the reader decides
# from content, so AC3 ("off — proceed exactly as today") holds for every non-opted-in repo. The
# origin is pointed at a missing path so any pull attempt would surface as `failed`.
bm_world "$BM_T/ro" off
git -C "$BM_T/ro/work" remote set-url origin "$BM_T/ro/no-such-origin.git"
chmod 444 "$BM_T/ro/work/.gitignore"
o="$(bm_entry "$BM_T/ro/work")"
[ "$o" = "meta-entry: off" ] && ok "BM6 never opted in + read-only .gitignore ⇒ 'meta-entry: off'" || no "BM6 read-only, never opted in ⇒ '$o'"
chmod 644 "$BM_T/ro/work/.gitignore"
printf '<<<<<<< HEAD\na/\n=======\nb/\n>>>>>>> other\n' >> "$BM_T/ro/work/.gitignore"
o="$(bm_entry "$BM_T/ro/work")"
[ "$o" = "meta-entry: off" ] && ok "BM6 never opted in + conflict-marked .gitignore ⇒ 'meta-entry: off'" || no "BM6 conflict-marked, never opted in ⇒ '$o'"
[ ! -e "$BM_T/ro/work/.supervisor" ] && ok "BM6 meta-entry off created nothing under .supervisor/" || no "BM6 meta-entry off wrote under .supervisor/"
# Opted in + read-only: still `on` (a reader never needs writability) ⇒ the pull runs.
bm_world "$BM_T/roon" on
chmod 444 "$BM_T/roon/work/.gitignore"
o="$(bm_entry "$BM_T/roon/work")"
[ "$o" = "meta-entry: pulled loomwright-meta" ] && ok "BM6 branch mode + read-only .gitignore ⇒ '$o'" || no "BM6 read-only branch mode ⇒ '$o'"
chmod 644 "$BM_T/roon/work/.gitignore"
# (bm7) a bare / empty / option-shaped `--root` value is a misinvocation ⇒ `failed`, never a silent
# `off` (pre-fix, `--root --x` read the mode of a non-existent checkout as off and skipped the pull
# in a branch-mode repo). Fail-safe: ONE line, exit 0.
for rv in --x -h ""; do
  o="$(cd "$BM_T/roon/work" && bm_env bash "$H" meta-entry --root "$rv" 2>/dev/null)"; rc=$?
  [ "$o" = "meta-entry: failed — --root requires a checkout path (got '$rv')" ] && [ "$rc" -eq 0 ] && ok "BM7 meta-entry --root '$rv' ⇒ '$o', exit 0" || no "BM7 meta-entry --root '$rv' ⇒ '$o' rc=$rc"
done
o="$(cd "$BM_T/roon/work" && bm_env bash "$H" meta-entry --root 2>/dev/null)"; rc=$?
[ "$o" = "meta-entry: failed — --root requires a checkout path (got '')" ] && [ "$rc" -eq 0 ] && ok "BM7 a trailing bare meta-entry --root ⇒ failed, exit 0" || no "BM7 bare --root ⇒ '$o' rc=$rc"
o="$(bash "$H" meta-push-failed -x.md 2>/dev/null)"; rc=$?
[ -z "$o" ] && [ "$rc" -eq 0 ] && ok "BM7 meta-push-failed with an option-shaped <runfile> prints nothing, exit 0" || no "BM7 meta-push-failed -x.md ⇒ '$o' rc=$rc"
# (bm8) review iteration 3 — the mode answer is FAIL-CLOSED on its SHAPE: an empty, garbage or
# `on ` (empty-branch) answer from the reader is `failed — mode unknown`, and NO pull runs; a
# near-miss mode line in a real branch-mode .gitignore reads unknown too (never `off`).
BM8="$BM_T/bm8"; mkdir -p "$BM8/bin"
cp "$H" "$BM8/bin/automate-helpers.sh"
printf '#!/bin/bash\necho pulled-by-spy >> "%s/spy.log"\nexit 0\n' "$BM8" > "$BM8/spy-meta-sync.sh"
bm8_entry() {  # <stub answer> [helpers copy] — runs meta-entry against a stub reader printing <answer>
  printf '#!/bin/bash\nprintf "%%s" %q\n' "$1" > "$BM8/bin/setup-memory.sh"
  (cd "$BM8" && LOOMWRIGHT_META_SYNC_BIN="$BM8/spy-meta-sync.sh" bash "${2:-$BM8/bin/automate-helpers.sh}" meta-entry --root "$BM8" 2>/dev/null)
}
for ans in '' 'on ' 'garbage' 'offx'; do
  rm -f "$BM8/spy.log"
  o="$(bm8_entry "$ans")"
  case "$o" in "meta-entry: failed — mode unknown ("*) ok "BM8 reader answer '$ans' ⇒ '$o'" ;; *) no "BM8 reader answer '$ans' ⇒ '$o'" ;; esac
  [ ! -e "$BM8/spy.log" ] && ok "BM8 reader answer '$ans' ran NO pull" || no "BM8 reader answer '$ans' ran a pull"
done
# Mutation control: the pre-fix `"on "*)` arm accepts `on ` (empty branch) and runs the pull.
sed 's/^    "on "?\*) branch="\${mode#on }" ;;$/    "on "*) branch="${mode#on }" ;;/' "$BM8/bin/automate-helpers.sh" > "$BM8/bin/mut-helpers.sh"
if cmp -s "$BM8/bin/automate-helpers.sh" "$BM8/bin/mut-helpers.sh"; then
  no "BM8 mutation control: the patch changed nothing — inconclusive"
else
  rm -f "$BM8/spy.log"; o="$(bm8_entry 'on ' "$BM8/bin/mut-helpers.sh")"
  case "$o" in "meta-entry: failed — "*) no "BM8 mutation control REFUTED: the pre-fix arm still fails on 'on ' ($o)" ;; *) ok "BM8 mutation control: the pre-fix arm accepts 'on ' ⇒ '$o' — the assertion is load-bearing" ;; esac
fi
# A near-miss (indented) mode line in a real branch-mode clone ⇒ unknown, through the real reader.
bm_world "$BM_T/nm" on
awk 'index($0, "# loomwright-meta-branch: ") == 1 { print "  " $0; next } { print }' "$BM_T/nm/work/.gitignore" > "$BM_T/nm/g" && mv "$BM_T/nm/g" "$BM_T/nm/work/.gitignore"
o="$(bm_entry "$BM_T/nm/work")"
case "$o" in "meta-entry: failed — mode unknown (a malformed mode line"*) ok "BM8 an indented mode line ⇒ '$o'" ;; *) no "BM8 indented mode line ⇒ '$o'" ;; esac

# (bp*) meta-publish — publish-on-write for /product-owner and /orchestrator. Every leg asserts the
# ONE verdict line (a second `meta-publish:` line is a defect) and, where nothing may be pushed,
# reads the bare origin itself.
RQ=".supervisor/requirements"
bm_pub() {  # bm_pub <checkout> <list> [VAR=val…] — meta-publish from <checkout> with --root <checkout>
  local c="$1" l="$2"; shift 2
  (cd "$c" && env "$@" HOME="$BM_T/home" GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@test.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@test.invalid bash "${BP_H:-$H}" meta-publish --paths-from "$l" --root "$c" 2>/dev/null)
}
bp_one() { [ "$(printf '%s\n' "$1" | grep -c '^meta-publish: ')" = 1 ]; }   # exactly one verdict line
bp_on_origin() { git --git-dir="$1" cat-file -e "loomwright-meta:$2" 2>/dev/null; }
printf '#!/bin/bash\necho "$*" >> "%s/bp-spy.log"\nexit 0\n' "$BM_T" > "$BM_T/bp-spy.sh"

# (bp1) mode on: two stories + a plan doc ⇒ exactly those three are pushed, `git show` matches each
# local file; a local-ahead file and a locally DELETED managed file not in the list are left alone.
bm_world "$BM_T/pub" on
PO="$BM_T/pub/origin.git"; PW="$BM_T/pub/work"
bm_env git clone -q "$PO" "$BM_T/pub/other" >/dev/null 2>&1
mkdir -p "$BM_T/pub/other/$RQ"; echo "kept on the branch" > "$BM_T/pub/other/$RQ/old-d.md"
printf '%s\n' "$RQ/old-d.md" > "$BM_T/pub/list0"
bm_env bash "$BM_MS" push --root "$BM_T/pub/other" --branch loomwright-meta --paths-from "$BM_T/pub/list0" >/dev/null 2>&1
o="$(bm_entry "$PW")"
[ "$o" = "meta-entry: pulled loomwright-meta" ] && [ -f "$PW/$RQ/old-d.md" ] && ok "BP1 precondition: the clone pulled old-d.md (meta-base recorded)" || no "BP1 precondition: meta-entry ⇒ '$o'"
rm -f "$PW/$RQ/old-d.md"                                         # locally deleted, NOT in the list
echo "local-ahead, not listed" > "$PW/$RQ/ahead.md"             # unpushed, NOT in the list
echo "story one" > "$PW/$RQ/2026-11-28-a.md"; echo "story two" > "$PW/$RQ/2026-11-28-b.md"
echo "plan doc" > "$PW/$RQ/2026-11-28-plan.md"
printf '%s\n' "$RQ/2026-11-28-a.md" "$RQ/2026-11-28-b.md" "# a comment line" "" "$RQ/2026-11-28-plan.md" > "$BM_T/pub/list"
o="$(bm_pub "$PW" "$BM_T/pub/list")"; rc=$?
tip="$(git --git-dir="$PO" rev-parse loomwright-meta 2>/dev/null)"
[ "$o" = "meta-publish: pushed loomwright-meta $tip (3 path(s))" ] && [ "$rc" -eq 0 ] && ok "BP1 mode on ⇒ '$o' (the branch tip), exit 0" || no "BP1 mode on ⇒ '$o' rc=$rc (tip $tip)"
bp1=0; for p in 2026-11-28-a.md 2026-11-28-b.md 2026-11-28-plan.md; do
  [ "$(git --git-dir="$PO" show "loomwright-meta:$RQ/$p" 2>/dev/null)" = "$(cat "$PW/$RQ/$p")" ] || bp1=1
done
[ "$bp1" = 0 ] && ok "BP1 git show origin/loomwright-meta:<path> equals each local file" || no "BP1 a pushed path differs from the local file"
bp_on_origin "$PO" "$RQ/ahead.md" && no "BP1 the unlisted local-ahead file was pushed" || ok "BP1 the unlisted local-ahead file stays unpushed"
bp_on_origin "$PO" "$RQ/old-d.md" && ok "BP1 the unlisted locally deleted file is still on the branch" || no "BP1 the unlisted locally deleted file was deleted from the branch"
# Mutation control: a whole-set push (no --paths-from) MUST publish the unlisted paths too.
BPM="$BM_T/bpm"; mkdir -p "$BPM"; for e in "$(dirname "$H")"/*; do ln -s "$e" "$BPM/$(basename "$e")"; done
rm -f "$BPM/automate-helpers.sh"
sed 's/push --branch "$branch" --paths-from "$pf" --root "$root"/push --branch "$branch" --root "$root"/' "$H" > "$BPM/automate-helpers.sh"
if cmp -s "$H" "$BPM/automate-helpers.sh"; then no "BP1 mutation control: the patch changed nothing — inconclusive"
else
  bm_world "$BM_T/pubm" on; bm_entry "$BM_T/pubm/work" >/dev/null
  echo "unlisted" > "$BM_T/pubm/work/$RQ/ahead.md" 2>/dev/null || { mkdir -p "$BM_T/pubm/work/$RQ"; echo "unlisted" > "$BM_T/pubm/work/$RQ/ahead.md"; }
  echo "listed" > "$BM_T/pubm/work/$RQ/one.md"; printf '%s\n' "$RQ/one.md" > "$BM_T/pubm/list"
  BP_H="$BPM/automate-helpers.sh" bm_pub "$BM_T/pubm/work" "$BM_T/pubm/list" >/dev/null
  bp_on_origin "$BM_T/pubm/origin.git" "$RQ/ahead.md" && ok "BP1 mutation control: a whole-set push publishes the unlisted file — the exact-list assertion is load-bearing" || no "BP1 mutation control REFUTED: a whole-set push left the unlisted file alone"
fi

# (bp2) the same unchanged paths pushed again (meta-publish, then a trail-style raw push) ⇒ no-ops.
o="$(bm_pub "$PW" "$BM_T/pub/list")"
[ "$o" = "meta-publish: no_changes loomwright-meta" ] && ok "BP2 repeated meta-publish ⇒ '$o'" || no "BP2 repeated meta-publish ⇒ '$o'"
o="$(cd "$PW" && bm_env bash "$BM_MS" push --branch loomwright-meta --root "$PW" --paths-from "$BM_T/pub/list" 2>&1)"
case "$o" in *"meta_sync: no_changes"*) ok "BP2 the trail's later push of the same paths ⇒ meta_sync: no_changes" ;; *) no "BP2 trail push after meta-publish ⇒ '$o'" ;; esac
[ "$(git --git-dir="$PO" rev-parse loomwright-meta)" = "$tip" ] && ok "BP2 the branch tip did not move" || no "BP2 a no-op push moved the branch tip"

# (bp3) mode off ⇒ the one skipped line, meta-sync never invoked, no branch on origin.
bm_world "$BM_T/poff" off
mkdir -p "$BM_T/poff/work/$RQ"; echo s > "$BM_T/poff/work/$RQ/s.md"; printf '%s\n' "$RQ/s.md" > "$BM_T/poff/list"
rm -f "$BM_T/bp-spy.log"
o="$(bm_pub "$BM_T/poff/work" "$BM_T/poff/list" LOOMWRIGHT_META_SYNC_BIN="$BM_T/bp-spy.sh")"; rc=$?
[ "$o" = "meta-publish: skipped — branch mode off: requirement files stay in this checkout" ] && [ "$rc" -eq 0 ] && ok "BP3 mode off ⇒ '$o', exit 0" || no "BP3 mode off ⇒ '$o' rc=$rc"
[ ! -e "$BM_T/bp-spy.log" ] && ! git --git-dir="$BM_T/poff/origin.git" rev-parse -q --verify loomwright-meta >/dev/null 2>&1 && ok "BP3 mode off ran no meta-sync and created no branch" || no "BP3 mode off reached meta-sync or a branch"

# (bp4) mode unknown ⇒ skipped, the verdict carries the reader's reason, nothing invoked.
r="$(bash "$BM_SM" --root "$BM_T/uk/work" mode 2>/dev/null | head -n1)"
printf '%s\n' "$RQ/s.md" > "$BM_T/uk/list"; rm -f "$BM_T/bp-spy.log"
o="$(bm_pub "$BM_T/uk/work" "$BM_T/uk/list" LOOMWRIGHT_META_SYNC_BIN="$BM_T/bp-spy.sh")"
case "$r" in "unknown "?*) ;; *) no "BP4 precondition: the reader said '$r', not unknown <reason>" ;; esac
[ "$o" = "meta-publish: skipped — branch mode unknown (${r#unknown })" ] && [ ! -e "$BM_T/bp-spy.log" ] && ok "BP4 mode unknown ⇒ '$o', no meta-sync run" || no "BP4 mode unknown ⇒ '$o' (reader: '$r')"

# (bp5) an /automate lane checkout (lane-info exits 0) ⇒ skipped, nothing invoked or pushed.
echo "lane story" > "$PW/$RQ/bp5.md"; printf '%s\n' "$RQ/bp5.md" > "$BM_T/pub/list5"
printf '{"schema_version":1,"run_id":"automate-2026-11-28-000000"}\n' > "$PW/.supervisor/lane.json"
rm -f "$BM_T/bp-spy.log"
o="$(bm_pub "$PW" "$BM_T/pub/list5" LOOMWRIGHT_META_SYNC_BIN="$BM_T/bp-spy.sh")"
[ "$o" = "meta-publish: skipped — /automate lane: published at wave end (lane-convert-ready / lane-remove --abandon)" ] && [ ! -e "$BM_T/bp-spy.log" ] && ok "BP5 lane checkout ⇒ '$o', no meta-sync run" || no "BP5 lane checkout ⇒ '$o'"
o="$(bm_pub "$PW" "$BM_T/pub/list5")"
bp_on_origin "$PO" "$RQ/bp5.md" && no "BP5 a lane checkout pushed ('$o')" || ok "BP5 a lane checkout (real meta-sync) pushed nothing"
rm -f "$PW/.supervisor/lane.json"

# (bp6) a path outside the managed set ⇒ refused by name, nothing pushed (meta-sync alone would
# skip it silently and push the rest); a listed path absent here is named `(missing)`.
mkdir -p "$PW/notes"; echo n > "$PW/notes/bp6.txt"; echo "managed" > "$PW/$RQ/bp6.md"
printf '%s\n' "$RQ/bp6.md" "notes/bp6.txt" > "$BM_T/pub/list6"
o="$(bm_pub "$PW" "$BM_T/pub/list6")"
[ "$o" = "meta-publish: refused — not a requirement file: notes/bp6.txt" ] && ok "BP6 non-managed path ⇒ '$o'" || no "BP6 non-managed path ⇒ '$o'"
bp_on_origin "$PO" "$RQ/bp6.md" && no "BP6 the managed sibling was pushed despite the refusal" || ok "BP6 nothing pushed (the managed sibling stays local)"
printf '%s\n' "$RQ/bp6.md" "$RQ/nope.md" > "$BM_T/pub/list6b"
o="$(bm_pub "$PW" "$BM_T/pub/list6b")"
[ "$o" = "meta-publish: refused — not a requirement file: $RQ/nope.md (missing)" ] && ok "BP6 a missing listed path ⇒ '$o'" || no "BP6 missing path ⇒ '$o'"
: > "$BM_T/pub/list6c"; o="$(bm_pub "$PW" "$BM_T/pub/list6c")"
[ "$o" = "meta-publish: refused — --paths-from $BM_T/pub/list6c lists no path" ] && ok "BP6 an empty list ⇒ refused" || no "BP6 empty list ⇒ '$o'"

# (bp7) a scrub hit ⇒ blocked + the scrub-hit line(s), nothing pushed, the file kept locally.
printf 'see /%s/%s/notes\n' Users realperson > "$PW/$RQ/bp7.md"; printf '%s\n' "$RQ/bp7.md" > "$BM_T/pub/list7"
o="$(bm_pub "$PW" "$BM_T/pub/list7")"
[ "$(printf '%s\n' "$o" | head -n1)" = "meta-publish: blocked — scrub hit (nothing pushed; files kept locally)" ] && bp_one "$o" && ok "BP7 scrub hit ⇒ ONE blocked verdict line" || no "BP7 scrub hit ⇒ '$o'"
printf '%s\n' "$o" | grep -q "^meta_sync: scrub-hit $RQ/bp7.md:1: home_path" && ok "BP7 the hit is named (scrub-hit $RQ/bp7.md:1: home_path)" || no "BP7 no scrub-hit line in '$o'"
! bp_on_origin "$PO" "$RQ/bp7.md" && [ -f "$PW/$RQ/bp7.md" ] && ok "BP7 nothing pushed and the file is still in the checkout" || no "BP7 pushed, or the local file is gone"

# (bp8) a failed push (origin removed) ⇒ FAILED with the reason + the retry command, exit 0.
git -C "$PW" remote set-url origin "$BM_T/pub/no-such-origin.git"
echo "offline story" > "$PW/$RQ/bp8.md"; printf '%s\n' "$RQ/bp8.md" > "$BM_T/pub/list8"
o="$(bm_pub "$PW" "$BM_T/pub/list8")"; rc=$?
case "$o" in "meta-publish: FAILED — "*"; retry: bash "*" push --branch loomwright-meta --paths-from $BM_T/pub/list8 --root $PW") bp8=0 ;; *) bp8=1 ;; esac
[ "$bp8" = 0 ] && [ "$rc" -eq 0 ] && bp_one "$o" && [ -f "$PW/$RQ/bp8.md" ] && ok "BP8 failed push ⇒ named FAILED + retry command, exit 0, file kept" || no "BP8 failed push ⇒ '$o' rc=$rc"
git -C "$PW" remote set-url origin "$PO"

# (bp9) from a linked worktree with --root ⇒ the WORKTREE's file is the one pushed (the default
# root would be the primary checkout, which holds a different copy of the same path).
bm_env git -C "$PW" worktree add -q -b bp9 "$BM_T/pub/wt" >/dev/null 2>&1
mkdir -p "$BM_T/pub/wt/$RQ"; echo "worktree copy" > "$BM_T/pub/wt/$RQ/bp9.md"; echo "primary copy" > "$PW/$RQ/bp9.md"
printf '%s\n' "$RQ/bp9.md" > "$BM_T/pub/list9"
o="$(bm_pub "$BM_T/pub/wt" "$BM_T/pub/list9")"
case "$o" in "meta-publish: pushed loomwright-meta "*" (1 path(s))") ok "BP9 linked worktree ⇒ '$o'" ;; *) no "BP9 linked worktree ⇒ '$o'" ;; esac
[ "$(git --git-dir="$PO" show "loomwright-meta:$RQ/bp9.md" 2>/dev/null)" = "worktree copy" ] && ok "BP9 the worktree's copy is the one on the branch" || no "BP9 the branch holds '$(git --git-dir="$PO" show "loomwright-meta:$RQ/bp9.md" 2>/dev/null)'"

# (bp10) misinvocation ⇒ ONE FAILED line, exit 0.
o="$(bash "$H" meta-publish --paths-from "$BM_T/pub/list9" --root --x 2>/dev/null)"; rc=$?
[ "$o" = "meta-publish: FAILED — --root requires a value (got '--x')" ] && [ "$rc" -eq 0 ] && ok "BP10 option-shaped --root ⇒ '$o', exit 0" || no "BP10 --root --x ⇒ '$o' rc=$rc"
o="$(bash "$H" meta-publish --root "$PW" 2>/dev/null)"; rc=$?
[ "$o" = "meta-publish: FAILED — --paths-from <file> is required" ] && [ "$rc" -eq 0 ] && ok "BP10 no --paths-from ⇒ '$o', exit 0" || no "BP10 no --paths-from ⇒ '$o' rc=$rc"
o="$(bash "$H" meta-publish --paths-from "$BM_T/pub/no-such-list" --root "$PW" 2>/dev/null)"; rc=$?
[ "$o" = "meta-publish: FAILED — --paths-from '$BM_T/pub/no-such-list' is not a readable file" ] && [ "$rc" -eq 0 ] && ok "BP10 a missing list file ⇒ FAILED, exit 0" || no "BP10 missing list ⇒ '$o' rc=$rc"
# An existing but UNREADABLE list: without the -r check the scope loop's `done < <list>` redirect
# aborts the dispatcher's set -e shell (raw bash error, exit 1, no verdict). Root ignores mode 000,
# so the leg asserts the file really became unreadable first and skips by name otherwise.
printf '%s\n' "$RQ/bp9.md" > "$BM_T/pub/list10u"; chmod 000 "$BM_T/pub/list10u"
if [ -r "$BM_T/pub/list10u" ]; then
  echo "  SKIP: BP10 unreadable list — chmod 000 left the file readable (running as root?)"
else
  o="$(bash "$H" meta-publish --paths-from "$BM_T/pub/list10u" --root "$PW" 2>&1)"; rc=$?
  [ "$o" = "meta-publish: FAILED — --paths-from '$BM_T/pub/list10u' is not a readable file" ] && [ "$rc" -eq 0 ] && ok "BP10 an unreadable list file ⇒ ONE FAILED line (stderr included), exit 0" || no "BP10 unreadable list ⇒ '$o' rc=$rc"
fi
chmod 600 "$BM_T/pub/list10u"

# (bp11) meta-sync's own failures on the other arms, through the LOOMWRIGHT_META_SYNC_BIN seam (a stub
# that fails ONE subcommand and runs the real meta-sync for the rest): each is ONE named line,
# exit 0, nothing pushed.
printf '#!/bin/bash\ncase "$1:$BP_FAIL" in\n  list-managed:lm) echo "meta_sync: symlink .supervisor/x"; exit 1 ;;\n  scrub:sc) echo "meta_sync: usage: scrub broke"; exit 1 ;;\n  push:p2) echo "meta_sync: scrub .supervisor/requirements/bp11.md: email" >&2; echo "meta_sync: aborted — scrub hit(s) above" >&2; exit 2 ;;\nesac\nexec bash "%s" "$@"\n' "$BM_MS" > "$BM_T/bp-fail.sh"
echo "bp11" > "$PW/$RQ/bp11.md"; printf '%s\n' "$RQ/bp11.md" > "$BM_T/pub/list11"
for c in "lm|meta-publish: FAILED — list-managed: symlink .supervisor/x (nothing pushed)" \
         "sc|meta-publish: FAILED — scrub: usage: scrub broke (nothing pushed)" \
         "p2|meta-publish: blocked — scrub hit (nothing pushed; files kept locally)"; do
  o="$(bm_pub "$PW" "$BM_T/pub/list11" LOOMWRIGHT_META_SYNC_BIN="$BM_T/bp-fail.sh" BP_FAIL="${c%%|*}")"; rc=$?
  [ "$(printf '%s\n' "$o" | head -n1)" = "${c#*|}" ] && bp_one "$o" && [ "$rc" -eq 0 ] && ok "BP11 ${c%%|*} ⇒ '${c#*|}', exit 0" || no "BP11 ${c%%|*} ⇒ '$o' rc=$rc"
done
printf '%s\n' "$o" | grep -q '^meta_sync: scrub .supervisor/requirements/bp11.md: email' && ok "BP11 a push-time scrub hit names its path" || no "BP11 push-time scrub line missing in '$o'"
bp_on_origin "$PO" "$RQ/bp11.md" && no "BP11 a failed arm pushed bp11.md" || ok "BP11 no failed arm pushed anything"
# (bp12) scope: only requirement files travel this route. A managed run-history path outside
# .supervisor/requirements/ (a job brief, a run file — trail-pr's evidence gate owns those) and a
# learning store (consent-gated, whole-set push only) are refused by name, with consent granted
# or not; a nested requirement file is in scope and is pushed.
mkdir -p "$PW/.supervisor/jobs/done" "$PW/.supervisor/automate" "$PW/.supervisor/agent-memory-proposals" "$PW/$RQ/grp"
echo j > "$PW/.supervisor/jobs/done/fake.md"; echo r > "$PW/.supervisor/automate/automate-x.md"
echo l > "$PW/.supervisor/agent-memory-proposals/p.md"; echo "nested story" > "$PW/$RQ/grp/bp12.md"
printf '%s\n' ".supervisor/jobs/done/fake.md" ".supervisor/automate/automate-x.md" > "$BM_T/pub/list12a"
o="$(bm_pub "$PW" "$BM_T/pub/list12a")"
[ "$o" = "meta-publish: refused — not a requirement file: .supervisor/jobs/done/fake.md; .supervisor/automate/automate-x.md" ] && ok "BP12 a job brief + a run file ⇒ '$o'" || no "BP12 jobs/automate paths ⇒ '$o'"
{ bp_on_origin "$PO" ".supervisor/jobs/done/fake.md" || bp_on_origin "$PO" ".supervisor/automate/automate-x.md"; } && no "BP12 a run-history path outside requirements was pushed" || ok "BP12 neither the job brief nor the run file was pushed"
printf '%s\n' ".supervisor/agent-memory-proposals/p.md" > "$BM_T/pub/list12b"
for cs in grant decline; do
  bm_env bash "$BM_SM" --root "$PW" consent "$cs" >/dev/null 2>&1
  st="$(bm_env bash "$BM_SM" --root "$PW" consent status 2>/dev/null | head -n1)"
  [ "$st" = "${cs}ed" ] || [ "$st" = "${cs%e}ed" ] || no "BP12 precondition: consent $cs ⇒ status '$st'"
  o="$(bm_pub "$PW" "$BM_T/pub/list12b")"
  [ "$o" = "meta-publish: refused — not a requirement file: .supervisor/agent-memory-proposals/p.md" ] && ok "BP12 a learning store (consent $cs) ⇒ refused by name" || no "BP12 learning store (consent $cs) ⇒ '$o'"
done
bp_on_origin "$PO" ".supervisor/agent-memory-proposals/p.md" && no "BP12 the learning store was pushed" || ok "BP12 the learning store was not pushed"
printf '%s\n' "$RQ/grp/bp12.md" > "$BM_T/pub/list12c"
o="$(bm_pub "$PW" "$BM_T/pub/list12c")"
case "$o" in "meta-publish: pushed loomwright-meta "*" (1 path(s))") ok "BP12 a nested requirement file ⇒ '$o'" ;; *) no "BP12 nested requirement file ⇒ '$o'" ;; esac
[ "$(git --git-dir="$PO" show "loomwright-meta:$RQ/grp/bp12.md" 2>/dev/null)" = "nested story" ] && ok "BP12 the nested file is on the branch" || no "BP12 the nested file is not on the branch"

# (bp13) a FAILED retry command is shell-quoted: a world under a path with a space, origin
# unreachable ⇒ the printed retry, eval'd once origin is back, lands the file on the branch.
bm_world "$BM_T/D sp" on
SW="$BM_T/D sp/work"; SO="$BM_T/D sp/origin.git"
mkdir -p "$SW/$RQ"; echo "spaced story" > "$SW/$RQ/bp13.md"; printf '%s\n' "$RQ/bp13.md" > "$BM_T/D sp/l"
git -C "$SW" remote set-url origin "$BM_T/D sp/no-such-origin.git"
o="$(bm_pub "$SW" "$BM_T/D sp/l")"
case "$o" in "meta-publish: FAILED — "*"; retry: bash "*) ok "BP13 spaced root, origin unreachable ⇒ FAILED + retry" ;; *) no "BP13 spaced root ⇒ '$o'" ;; esac
git -C "$SW" remote set-url origin "$SO"
r="${o#*; retry: }"
(cd "$SW" && eval "bm_env $r") >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ "$(git --git-dir="$SO" show "loomwright-meta:$RQ/bp13.md" 2>/dev/null)" = "spaced story" ] && ok "BP13 the printed retry runs as-is and lands the file on the branch" || no "BP13 eval of the retry ('$r') rc=$rc did not land the file"
rm -rf "$BM_T"


