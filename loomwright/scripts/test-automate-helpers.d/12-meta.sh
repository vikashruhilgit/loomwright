# ============================================================================
# BRANCH MODE — meta-entry (pull BEFORE the first read) + meta-push-failed (skills/automate-loop/
# SKILL.md §"Branch mode"). Hermetic: a mktemp world with a LOCAL bare origin, never GitHub.
# ============================================================================
echo "== branch mode: meta-entry / meta-push-failed =="
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
rm -rf "$BM_T"


