#!/usr/bin/env bash
# test-eval-set.sh — pins selvedge/eval/eval-set.mjs, the known-answer set's tooling: the split rule
# (recomputed here independently), split / validate, one side per group (defect_on_both_sides),
# check-leak (held_out_answer_committed, no_tracked_files, split_unreadable), the held-out manifest
# (manifest_mismatch, manifest_missing_file, manifest_extra_file, manifest_empty, manifest_invalid),
# count's answers check (held_out_answers_incomplete), real-bugs.json entries
# (real_bug_entry_incomplete), the planted-defect start folder (start_folder_not_clean), import-planted
# (planted_import_invalid: opaque group ids, variants filed by side, refusals write nothing), and each
# reason token on exactly one code line. Every arm turns red under its row of the brief's
# pin-mutation table.
#
# Hermetic: a temp HOME, SELVEDGE_EVAL_HELD_OUT always points at a temp folder (never the real
# ~/.claude/selvedge-eval/), fixture sets live in temp git repos. Needs node (>= 18) and git; a
# missing one is a FAIL, never a skip.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$TESTS_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_DIR/.." && pwd)"
MOD="$PLUGIN_DIR/eval/eval-set.mjs"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "  ok   $1"; }
ko() { fail=$((fail + 1)); echo "  FAIL $1"; }
finish() { echo "test-eval-set: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }

for tool in node git; do
  command -v "$tool" >/dev/null 2>&1 || { ko "$tool is not on PATH (test-eval-set.sh needs it)"; finish; }
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/selvedge-eval-set.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd)" # a TMPDIR ending in / gives "//"; node's paths never carry it
export HOME="$TMP/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export SELVEDGE_EVAL_HELD_OUT="$TMP/outside"
SEED="test-seed"
# import_mod <js> — an ES module with M (eval-set.mjs) imported. The path goes in through the
# environment: as an argv entry it would make eval-set.mjs think it is the main module.
import_mod() { EVAL_MOD="$MOD" node --input-type=module -e "import { pathToFileURL } from 'node:url'; const M = await import(pathToFileURL(process.env.EVAL_MOD).href); $1"; }
RULE="$(import_mod 'process.stdout.write(M.SPLIT_RULE)')"
[ -n "$RULE" ] && ok "setup: SPLIT_RULE exported" || { ko "setup: cannot import $MOD"; finish; }

# run <repo> <args…> — sets $rc, $out, $err.
run() {
  local repo="$1"; shift
  node "$MOD" --repo "$repo" "$@" >"$TMP/stdout" 2>"$TMP/stderr"; rc=$?
  out="$(cat "$TMP/stdout")"; err="$(cat "$TMP/stderr")"
}
# expect_fail <label> <token> [detail] — the last run exited 1 and named <token> (and <detail>).
expect_fail() {
  if [ "$rc" -eq 1 ] && grep -qF -- "${3:-}" < <(grep -F -- "FAIL $2" <<<"$err"); then ok "$1"; else ko "$1 (rc=$rc, want '$2${3:+ … $3}'): $err"; fi
}
expect_ok() { if [ "$rc" -eq 0 ]; then ok "$1"; else ko "$1 (rc=$rc): $err"; fi; }

# The independent split rule and fixture generator (no import of eval-set.mjs).
cat >"$TMP/indep.mjs" <<'EOF'
import { createHash } from 'node:crypto';
import { writeFileSync } from 'node:fs';
const h = (s) => createHash('sha256').update(s).digest('hex');
const v = (seed, g) => parseInt(h(`${seed}:${g}`).slice(0, 8), 16) % 100;
const [cmd, seed, ...rest] = process.argv.slice(2);
if (cmd === 'side') for (const g of rest) console.log(`${g}\t${v(seed, g) < 40 ? 'tuning' : 'held-out'}`);
if (cmd === 'pick') {
  const gs = Array.from({ length: 500 }, (_, i) => `g${i}`);
  console.log([gs.find((g) => v(seed, g) < 40), gs.find((g) => v(seed, g) >= 60), gs.find((g) => v(seed, g) >= 40 && v(seed, g) < 60)].join(' '));
}
if (cmd === 'gen') {
  const [out, bugs, T, M] = rest;
  const crit = (text) => ({ id: `c-${h(text).slice(0, 12)}`, text });
  const commit = (d) => ({ kind: 'commit', repo: 'o/r', sha: d.repeat(40) });
  const c = (case_id, group_id, source, text, d, answer) => ({ case_id, group_id, source, criterion: crit(text), target: commit(d), answer });
  writeFileSync(out, JSON.stringify({ schema_version: 1, cases: [
    c('t1-fail', T, 'real-bug', 'The total shows "12"', '1', 'FAIL'),
    c('t1-pass', T, 'real-bug', 'The total shows "12"', '2', 'PASS'),
    c('t1-nd', T, 'non-defect', 'The page title reads "Cart"', '2', 'PASS'),
    c('m1-fail', M, 'real-bug', 'Saving shows "Saved"', '3', 'FAIL'),
    c('m1-pass', M, 'real-bug', 'Saving shows "Saved"', '4', 'PASS'),
    c('m1-nd', M, 'non-defect', 'The header reads "Team"', '4', 'PASS'),
  ] }, null, 2));
  const e = (pr, p, f, status, extra) => ({ repo: 'o/r', pr, parent_sha: p.repeat(40), fix_sha: f.repeat(40), setup: ['npm ci', 'npm run dev'], status, ...extra });
  writeFileSync(bugs, JSON.stringify({ schema_version: 1, entries: [
    e(1, '1', '2', 'used'), e(2, '3', '4', 'used'), e(3, '5', '6', 'skipped', { skip_reason: 'migrations fail at the parent' }),
  ] }, null, 2));
}
EOF
read -r GT GH GM <<<"$(node "$TMP/indep.mjs" pick "$SEED")"
[ -n "$GM" ] && ok "setup: groups $GT (tuning), $GH and $GM (held-out; $GM in the 40..59 band)" || { ko "setup: no groups picked"; finish; }

# --- the split rule: `side` equals the independent rule for 100 groups (pin: < 40 -> < 60) -------
B="$TMP/base"
mkdir -p "$B/selvedge/eval" && git -C "$B" init -q
printf '{\n  "schema_version": 1,\n  "rule": "%s",\n  "seed": "%s"\n}\n' "$RULE" "$SEED" >"$B/selvedge/eval/split.json"
groups=""; i=0; while [ "$i" -lt 100 ]; do groups="$groups g$i"; i=$((i + 1)); done
# shellcheck disable=SC2086
run "$B" side $groups
want="$(node "$TMP/indep.mjs" side "$SEED" $groups)"
[ "$rc" -eq 0 ] && [ "$out" = "$want" ] && ok "side: 100 groups follow sha256(seed:group)[0:8] mod 100 < 40 -> tuning" || ko "side: differs from the independent rule (rc=$rc)"

# --- split builds the base set ---------------------------------------------------------------------
node "$TMP/indep.mjs" gen "$SEED" "$TMP/all.json" "$B/selvedge/eval/real-bugs.json" "$GT" "$GM"
run "$B" split "$TMP/all.json"
expect_ok "split: writes the set"
node -e '
const fs = require("fs"); const [b, o, t, m] = process.argv.slice(1);
const tu = JSON.parse(fs.readFileSync(b + "/selvedge/eval/tuning/cases.json", "utf8")).cases;
const ho = JSON.parse(fs.readFileSync(b + "/selvedge/eval/held-out/cases.json", "utf8")).cases;
const an = JSON.parse(fs.readFileSync(o + "/answers.json", "utf8"));
const ok = tu.length === 3 && tu.every((c) => c.group_id === t && "answer" in c)
  && ho.length === 3 && ho.every((c) => c.group_id === m && !("answer" in c))
  && JSON.stringify(an) === JSON.stringify({ "m1-fail": "FAIL", "m1-nd": "PASS", "m1-pass": "PASS" });
process.exit(ok ? 0 : 1);' "$B" "$SELVEDGE_EVAL_HELD_OUT" "$GT" "$GM" \
  && ok "split: $GT -> tuning with answers; $GM -> held-out without answers; its answers only in the outside answers.json" \
  || ko "split: wrong sides or answers in the repo"
cp -R "$B/selvedge/eval" "$TMP/eval-after-split"
run "$B" split "$TMP/all.json"
expect_ok "split: a replay of the same input"
diff -r "$TMP/eval-after-split" "$B/selvedge/eval" >/dev/null && ok "split: a replay writes the same bytes" || ko "split: a replay changed the set"
node -e 'const fs=require("fs"); const d=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); delete d.cases[0].answer; d.cases[1].case_id="__proto__"; fs.writeFileSync(process.argv[2], JSON.stringify(d));' "$TMP/all.json" "$TMP/bad.json"
run "$B" split "$TMP/bad.json"
expect_fail "split: an input case without an answer" case_invalid "t1-fail: bad answer"
expect_fail "split: a case_id that is not a plain token" case_invalid "bad case_id"
diff -r "$TMP/eval-after-split" "$B/selvedge/eval" >/dev/null && ok "split: a refused input writes nothing" || ko "split: a refused input changed the set"
run "$B" split "$TMP/no-such.json"
expect_fail "split: a missing input file" case_invalid "does not exist"
rm -rf "$TMP/eval-after-split"
run "$B" manifest write
expect_ok "manifest write"
grep -qE '^[0-9a-f]{64}  answers\.json$' "$B/selvedge/eval/held-out/manifest.sha256" && ok "manifest: '<sha256>  answers.json' line" || ko "manifest: no answers.json line"
git -C "$B" add -A && git -C "$B" commit -qm base
run "$B" validate;   expect_ok "validate: base set"
run "$B" check-leak; expect_ok "check-leak: base set"
run "$B" manifest check; expect_ok "manifest check: base set"
run "$B" count
expect_ok "count: base set"
grep -qE '^known-FAIL +2 +floor 100 +open$' <<<"$out" \
  && grep -qE '^known-PASS +4 +floor 100 +open$' <<<"$out" \
  && grep -qE '^real-bug known-FAIL +2 +floor +30 +open$' <<<"$out" \
  && grep -qE '^held-out known-FAIL +1 +floor +60 +open$' <<<"$out" \
  && ok "count: each count beside its floor, marked open" || ko "count: unexpected output: $out"

# fresh <name> — a copy of the base repo (and of the outside folder) to break; sets $R and exports
# SELVEDGE_EVAL_HELD_OUT=$R.outside.
fresh() {
  R="$TMP/$1"; rm -rf "$R" "$R.outside"; cp -R "$B" "$R"; cp -R "$TMP/outside" "$R.outside"
  export SELVEDGE_EVAL_HELD_OUT="$R.outside"
}
jedit() { node -e 'const fs=require("fs"); const f=process.argv[1]; const d=JSON.parse(fs.readFileSync(f,"utf8")); (new Function("d", process.argv[2]))(d); fs.writeFileSync(f, JSON.stringify(d, null, 2));' "$@"; }

# --- one side per group (pin: defect_on_both_sides) ------------------------------------------------
fresh both
jedit "$R/selvedge/eval/tuning/cases.json" 'const c = JSON.parse(JSON.stringify(d.cases[0])); c.case_id = "x"; c.group_id = "'"$GM"'"; d.cases.push(c);'
run "$R" validate
expect_fail "validate: a group in both tuning/ and held-out/cases.json" defect_on_both_sides "group $GM"

# --- the recorded side (case_on_wrong_side) ---------------------------------------------------------
fresh wrong
jedit "$R/selvedge/eval/held-out/cases.json" 'd.cases = [];'
jedit "$R/selvedge/eval/tuning/cases.json" 'for (const c of d.cases) c.group_id = "'"$GH"'";'
run "$R" validate
expect_fail "validate: a case on the side its group does not get" case_on_wrong_side "group $GH"

# --- case shapes (case_invalid) ----------------------------------------------------------------------
fresh chain
jedit "$R/selvedge/eval/real-bugs.json" 'd.entries.push({ ...d.entries[0], pr: 4, parent_sha: "2".repeat(40), fix_sha: "7".repeat(40) });'
run "$R" validate
expect_fail "validate: a commit that is one entry's fix_sha and another's parent_sha, with no group link" case_invalid "t1-pass: its commit is the parent_sha"
jedit "$R/selvedge/eval/real-bugs.json" 'd.entries[0].group_id = "'"$GT"'";'
run "$R" validate
expect_ok "validate: on a shared commit, the case's own entry (group_id) gives its role"

fresh invalid
jedit "$R/selvedge/eval/tuning/cases.json" 'const by = (id) => d.cases.find((c) => c.case_id === id); by("t1-fail").criterion.id = "c-000000000000"; by("t1-pass").criterion.text = " The total  shows \"12\"";'
run "$R" validate
expect_fail "validate: criterion.id not criterionId(text)" case_invalid "t1-fail: bad criterion.id"
expect_fail "validate: criterion.text not normalized" case_invalid "t1-pass: bad criterion.text"

# --- real-bugs.json entries (pin: real_bug_entry_incomplete) ----------------------------------------
for field in repo pr parent_sha fix_sha setup status; do
  fresh "rb-$field"
  jedit "$R/selvedge/eval/real-bugs.json" "delete d.entries[2].$field;"
  run "$R" check-leak
  expect_fail "check-leak: a real-bugs.json entry without $field" real_bug_entry_incomplete "lacks $field"
done
fresh rb-skip
jedit "$R/selvedge/eval/real-bugs.json" 'd.entries[2].skip_reason = " ";'
run "$R" validate
expect_fail "validate: a skipped entry with a blank skip_reason" real_bug_entry_incomplete "(pr 3) lacks skip_reason"

# --- check-leak (pin: held_out_answer_committed) ----------------------------------------------------
fresh leak-case
jedit "$R/selvedge/eval/held-out/cases.json" 'd.cases[0].answer = "FAIL";'
git -C "$R" commit -qam leak
run "$R" check-leak
expect_fail "check-leak: a held-out case carrying an answer" held_out_answer_committed "held-out/cases.json case m1-fail"
fresh leak-name
cp "$R.outside/answers.json" "$R/selvedge/eval/answers.json" && git -C "$R" add -A && git -C "$R" commit -qm leak
run "$R" check-leak
expect_fail "check-leak: a tracked file named answers.json" held_out_answer_committed "selvedge/eval/answers.json is named answers.json"
fresh leak-copy
mkdir -p "$R/selvedge/eval/notes" && cp "$R.outside/answers.json" "$R/selvedge/eval/notes/scratch.txt" && git -C "$R" add -A && git -C "$R" commit -qm leak
run "$R" check-leak
expect_fail "check-leak: a renamed copy of the outside answers.json (manifest sha)" held_out_answer_committed "notes/scratch.txt has the bytes of outside file answers.json"
fresh leak-variant
mkdir -p "$R/selvedge/eval/held-out/variants/$GM" && echo 'variant' >"$R/selvedge/eval/held-out/variants/$GM/app.mjs" && git -C "$R" add -A && git -C "$R" commit -qm leak
run "$R" check-leak
expect_fail "check-leak: a tracked file under a held-out variant path" held_out_answer_committed "variants path"
fresh leak-map
printf '{"m1-pass": "PASS"}\n' >"$R/selvedge/eval/notes.json" && git -C "$R" add -A && git -C "$R" commit -qm leak
run "$R" check-leak
expect_fail "check-leak: a tracked JSON mapping held-out case ids to answers" held_out_answer_committed "notes.json maps held-out case ids"
# The scan reads every tracked file by content, never by its name.
# leak_case <name> <file under selvedge/eval/> <node expr writing a held-out case with an answer to f>
leak_case() {
  fresh "$1"
  mkdir -p "$(dirname "$R/selvedge/eval/$2")"
  node -e 'const fs=require("fs"); const [src, f]=process.argv.slice(1); const c={...JSON.parse(fs.readFileSync(src,"utf8")).cases[0], answer:"FAIL"}; '"$3" "$R/selvedge/eval/held-out/cases.json" "$R/selvedge/eval/$2"
  git -C "$R" add -A && git -C "$R" commit -qm leak
  run "$R" check-leak
}
leak_case leak-backup held-out/backup.json 'fs.writeFileSync(f, JSON.stringify({schema_version:1, cases:[c]}));'
expect_fail "check-leak: a held-out case with an answer in a case list not named cases.json" held_out_answer_committed "held-out/backup.json case m1-fail"
leak_case leak-array held-out/list.json 'fs.writeFileSync(f, JSON.stringify([c]));'
expect_fail "check-leak: a held-out case with an answer in a bare array" held_out_answer_committed "held-out/list.json case m1-fail"
leak_case leak-jsonl held-out/cases.jsonl 'fs.writeFileSync(f, JSON.stringify({case_id:"x0"}) + "\n" + JSON.stringify(c) + "\n");'
expect_fail "check-leak: a held-out case with an answer on a JSON Lines line" held_out_answer_committed "held-out/cases.jsonl case m1-fail"
leak_case leak-nested nested.json 'fs.writeFileSync(f, JSON.stringify({answers:{[c.case_id]:"FAIL"}}));'
expect_fail "check-leak: a nested map of held-out case ids to answers" held_out_answer_committed "nested.json maps held-out case ids"
leak_case leak-noext notes/dump 'fs.writeFileSync(f, JSON.stringify({rows:[{case_id:c.case_id, answer:"FAIL"}]}));'
expect_fail "check-leak: a held-out case id with an answer and no group_id, in a file with no extension" held_out_answer_committed "notes/dump case m1-fail"

# An unchanged start-folder base under an outside variant is public: a committed tuning variant with
# the same bytes is not a leak. The exemption is for variants/ only.
fresh base-variant
mkdir -p "$R/selvedge/tests/fixtures" "$R/selvedge/eval/tuning/variants/$GT" "$R.outside/variants/$GM"
cp "$PLUGIN_DIR/tests/fixtures/app-server.mjs" "$PLUGIN_DIR/tests/fixtures/servers.mjs" "$R/selvedge/tests/fixtures/"
cp "$PLUGIN_DIR/tests/fixtures/servers.mjs" "$R/selvedge/eval/tuning/variants/$GT/servers.mjs"
cp "$PLUGIN_DIR/tests/fixtures/servers.mjs" "$R.outside/variants/$GM/servers.mjs"
git -C "$R" add -A && git -C "$R" commit -qm base-variant
run "$R" manifest write
git -C "$R" commit -qam manifest
run "$R" check-leak
expect_ok "check-leak: a tuning variant and an outside variant both unchanged from tests/fixtures/servers.mjs"
cp "$PLUGIN_DIR/tests/fixtures/servers.mjs" "$R.outside/servers-copy.mjs"
run "$R" check-leak
expect_fail "check-leak: a fixture's bytes outside variants/ get no exemption" held_out_answer_committed "has the bytes of outside file servers-copy.mjs"
rm "$R.outside/servers-copy.mjs"
cp "$R.outside/answers.json" "$R/selvedge/eval/tuning/variants/$GT/answers-copy.mjs" && git -C "$R" add -A && git -C "$R" commit -qm leak
run "$R" check-leak
expect_fail "check-leak: a copy of the outside answers.json is still a leak beside the exemption" held_out_answer_committed "answers-copy.mjs has the bytes of outside file answers.json"

# --- check-leak fails closed (pins: no_tracked_files, split_unreadable) -----------------------------
fresh untracked
rm -rf "$R/.git" && git -C "$R" init -q
run "$R" check-leak
expect_fail "check-leak: git ls-files returns nothing" no_tracked_files
fresh notgit
rm -rf "$R/.git"
run "$R" check-leak
expect_fail "check-leak: not a git repo" no_tracked_files
fresh nosplit
git -C "$R" rm -q selvedge/eval/split.json && git -C "$R" commit -qm nosplit
run "$R" check-leak
expect_fail "check-leak: split.json missing" split_unreadable "split.json"
fresh noseed
jedit "$R/selvedge/eval/split.json" 'd.seed = "";'
run "$R" check-leak
expect_fail "check-leak: split.json names no seed" split_unreadable "names no rule"

# --- the manifest (pins: manifest_mismatch, _missing_file, _extra_file, _empty) ---------------------
fresh byte
node -e 'const fs=require("fs"); const f=process.argv[1]; const b=fs.readFileSync(f); b[b.length-2]^=1; fs.writeFileSync(f,b);' "$R.outside/answers.json"
run "$R" manifest check
expect_fail "manifest check: one changed byte names the file" manifest_mismatch "manifest_mismatch: answers.json"
cp "$TMP/outside/answers.json" "$R.outside/answers.json"
run "$R" manifest check; expect_ok "manifest check: passes again once the byte is restored"
fresh missing
rm "$R.outside/answers.json"
run "$R" manifest check
expect_fail "manifest check: a listed file that is gone" manifest_missing_file "manifest_missing_file: answers.json"
fresh nofolder
rm -rf "$R.outside"
run "$R" manifest check
expect_fail "manifest check: the outside folder is gone (fails closed, names every listed file)" manifest_missing_file "answers.json"
fresh extra
mkdir -p "$R.outside/variants/pd-x" && echo x >"$R.outside/variants/pd-x/app.mjs"
run "$R" manifest check
expect_fail "manifest check: an unlisted file that appeared" manifest_extra_file "manifest_extra_file: variants/pd-x/app.mjs"
fresh nomanifest
rm "$R/selvedge/eval/held-out/manifest.sha256" && rm -rf "$R.outside" && mkdir "$R.outside"
run "$R" manifest check
expect_fail "manifest check: manifest.sha256 missing" manifest_empty
: >"$R/selvedge/eval/held-out/manifest.sha256"
run "$R" manifest check
expect_fail "manifest check: manifest.sha256 lists no file" manifest_empty
fresh badline
echo 'not a manifest line' >>"$R/selvedge/eval/held-out/manifest.sha256"
run "$R" manifest check
expect_fail "manifest check: a malformed manifest line" manifest_invalid "line 2"
run "$R" manifest write
rm -rf "$R.outside" && mkdir "$R.outside"
run "$R" manifest write
[ "$rc" -ne 0 ] && grep -qF 'answers.json' "$R/selvedge/eval/held-out/manifest.sha256" && ok "manifest write: refuses an empty outside folder, keeps the old manifest" || ko "manifest write: wrote from an empty outside folder (rc=$rc)"

# --- count's answers check (pin: held_out_answers_incomplete) ---------------------------------------
fresh noanswers
jedit "$R/selvedge/eval/held-out/cases.json" 'd.cases = [];'
rm "$R.outside/answers.json" && echo keep >"$R.outside/keep.txt"
run "$R" manifest write
run "$R" count
expect_fail "count: no outside answers.json, even with no held-out cases" held_out_answers_incomplete "answers.json is missing"
fresh answerkeys
jedit "$R.outside/answers.json" 'delete d["m1-nd"]; d["zz-extra"] = "FAIL";'
run "$R" manifest write
run "$R" count
expect_fail "count: answers.json lacks a held-out case id" held_out_answers_incomplete "lacks held-out case ids: m1-nd"
expect_fail "count: answers.json has an id that is not a held-out case" held_out_answers_incomplete "not held-out cases: zz-extra"
fresh countmanifest
echo stray >"$R.outside/stray.txt"
run "$R" count
expect_fail "count: runs the manifest check first" manifest_extra_file "stray.txt"

# --- the planted-defect start folder (pin: start_folder_not_clean) ----------------------------------
export SELVEDGE_EVAL_HELD_OUT="$TMP/outside"
SF="$TMP/start"
mkdir -p "$SF" && cp "$PLUGIN_DIR/tests/fixtures/app-server.mjs" "$PLUGIN_DIR/tests/fixtures/servers.mjs" "$SF/"
run "$REPO_ROOT" check-start-folder "$SF"
expect_ok "check-start-folder: copies of app-server.mjs and servers.mjs only"
cp "$PLUGIN_DIR/prompts/planner.md" "$SF/notes.md"
run "$REPO_ROOT" check-start-folder "$SF"
expect_fail "check-start-folder: a copy of selvedge/prompts/planner.md" start_folder_not_clean "notes.md (a copy of selvedge/prompts/planner.md)"
rm "$SF/notes.md" "$SF/servers.mjs"
run "$REPO_ROOT" check-start-folder "$SF"
expect_fail "check-start-folder: servers.mjs missing" start_folder_not_clean "servers.mjs is missing"

# --- import-planted (pin: planted_import_invalid) ------------------------------------------------------
# Two slugs, one per side under the recorded seed, found by the independent rule (sha256 recomputed).
read -r PT PH <<<"$(node -e '
const h = (s) => require("crypto").createHash("sha256").update(s).digest("hex");
const side = (g) => parseInt(h(process.argv[1] + ":" + g).slice(0, 8), 16) % 100 < 40 ? "t" : "h";
const id = (s) => "pd-" + h("planted:" + s).slice(0, 10);
const c = Array.from({ length: 200 }, (_, i) => "pd-bug-" + i);
console.log(c.find((s) => side(id(s)) === "t"), c.find((s) => side(id(s)) === "h"));' "$SEED")"
pid() { node -e 'console.log("pd-" + require("crypto").createHash("sha256").update("planted:" + process.argv[1]).digest("hex").slice(0, 10))' "$1"; }
IT="$(pid "$PT")"; IH="$(pid "$PH")"
# planted_out <dir> — a session out/ folder: one variant per slug, two FAIL and one PASS criterion each.
planted_out() {
  rm -rf "$1"; mkdir -p "$1/$PT" "$1/$PH"
  local k=0 s
  for s in "$PT" "$PH"; do
    k=$((k + 1))
    printf '// %s\nexport const BUG = "%s";\n' "$s" "$s" >"$1/$s/app-server.mjs"
    cp "$PLUGIN_DIR/tests/fixtures/servers.mjs" "$1/$s/servers.mjs"
    for a in "FAIL:The total for item $k reads 18" "FAIL:  - The badge for item $k reads 3" "PASS:The title for item $k reads Shop"; do
      printf '{"group_id":"%s","criterion":"%s","answer":"%s","variant":"%s"}\n' "$s" "${a#*:}" "${a%%:*}" "$s"
    done >>"$1/cases.jsonl"
  done
  printf '%s\n' "the bug notes" >"$1/BUGS.md"
}
fresh imp
# The real repo's start-folder bases, so an unchanged servers.mjs in both a tuning and a held-out
# variant gets check-leak's exemption, as it does in the real tree.
mkdir -p "$R/selvedge/tests/fixtures" && cp "$PLUGIN_DIR/tests/fixtures/app-server.mjs" "$PLUGIN_DIR/tests/fixtures/servers.mjs" "$R/selvedge/tests/fixtures/"
O="$TMP/planted-out"; planted_out "$O"
run "$R" import-planted "$O"
expect_ok "import-planted: a well-formed out/ folder"
node -e '
const fs = require("fs"); const [r, o, it, ih] = process.argv.slice(1);
const tu = JSON.parse(fs.readFileSync(r + "/selvedge/eval/tuning/cases.json", "utf8")).cases.filter((c) => c.source === "planted");
const ho = JSON.parse(fs.readFileSync(r + "/selvedge/eval/held-out/cases.json", "utf8")).cases.filter((c) => c.source === "planted");
const an = JSON.parse(fs.readFileSync(o + "/answers.json", "utf8"));
const ok = tu.length === 3 && tu.every((c) => c.group_id === it && c.target.kind === "variant" && c.target.path === "variants/" + it && "answer" in c)
  && tu.filter((c) => c.answer === "FAIL").length === 2
  && ho.length === 3 && ho.every((c) => c.group_id === ih && c.target.path === "variants/" + ih && !("answer" in c))
  && ho.filter((c) => an[c.case_id] === "FAIL").length === 2 && ho.some((c) => c.criterion.text.startsWith("The badge"));
process.exit(ok ? 0 : 1);' "$R" "$R.outside" "$IT" "$IH" \
  && ok "import-planted: cases under opaque ids by side, criteria normalized, held-out answers outside only" || ko "import-planted: wrong cases or answers"
cmp -s "$O/$PT/app-server.mjs" "$R/selvedge/eval/tuning/variants/$IT/app-server.mjs" && cmp -s "$O/$PH/app-server.mjs" "$R.outside/variants/$IH/app-server.mjs" \
  && [ ! -e "$R/selvedge/eval/tuning/variants/$IH" ] && [ ! -e "$R.outside/variants/$IT" ] \
  && ok "import-planted: the tuning variant under tuning/variants/<id>/, the held-out one in the outside folder only" || ko "import-planted: variants not filed by side"
! grep -qF "pd-bug-" "$R/selvedge/eval/tuning/cases.json" "$R/selvedge/eval/held-out/cases.json" "$R.outside/answers.json" && ! grep -rqF "bug notes" "$R/selvedge/eval" "$R.outside" \
  && ok "import-planted: no slug reaches the set's cases (they would name the bug), BUGS.md is never copied" || ko "import-planted: a slug or BUGS.md reached the set"
! grep -qF "reads 18" <<<"$out" && grep -qF "tuning 1 (3 case(s)), held-out 1 (3 case(s))" <<<"$out" \
  && ok "import-planted: prints counts only" || ko "import-planted: output: $out"
printf '%s\t%s\ttuning\n%s\t%s\theld-out\n' "$PT" "$IT" "$PH" "$IH" | sort >"$TMP/ids.want"
sort "$O/imported-ids.tsv" | diff -q - "$TMP/ids.want" >/dev/null && ok "import-planted: the slug-to-id list stays in the session's folder" || ko "import-planted: imported-ids.tsv: $(cat "$O/imported-ids.tsv")"
cp -R "$R/selvedge/eval" "$TMP/eval-after-import"; cp -R "$R.outside" "$TMP/outside-after-import"
run "$R" import-planted "$O"
expect_ok "import-planted: a replay"
diff -r "$TMP/eval-after-import" "$R/selvedge/eval" >/dev/null && diff -r "$TMP/outside-after-import" "$R.outside" >/dev/null \
  && ok "import-planted: a replay writes the same bytes" || ko "import-planted: a replay changed the set"
run "$R" manifest write
git -C "$R" add -A && git -C "$R" commit -qm planted
run "$R" check-leak; expect_ok "import-planted then manifest write: check-leak passes on the committed tree"
run "$R" count
grep -qE '^held-out known-FAIL +3 +floor +60 +open$' <<<"$out" && ok "import-planted: count includes the planted held-out FAILs" || ko "import-planted: count: $out"
# refused inputs write nothing, each named. refuse <label> <detail> <shell edit of $O>
refuse() {
  planted_out "$O"; eval "$3"
  run "$R" import-planted "$O"
  expect_fail "import-planted refuses: $1" planted_import_invalid "$2"
  diff -r "$TMP/eval-after-import" "$R/selvedge/eval" >/dev/null && diff -r -x manifest.sha256 "$TMP/outside-after-import" "$R.outside" >/dev/null \
    && ok "import-planted: refused ($1) writes nothing" || ko "import-planted: refused ($1) changed the set"
}
cp -R "$R/selvedge/eval" "$TMP/eval-after-import.tmp"; rm -rf "$TMP/eval-after-import"; mv "$TMP/eval-after-import.tmp" "$TMP/eval-after-import"
NEWS="pd-bug-new-$$"
refuse "a group with no FAIL criterion" "plants nothing" "sed -i.bak '/\"$PT\"/s/\"FAIL\"/\"PASS\"/' \"\$O/cases.jsonl\""
refuse "a variant folder with no case" "has no case in cases.jsonl" "mkdir \"\$O/$NEWS\" && echo x >\"\$O/$NEWS/app-server.mjs\""
refuse "cases with no variant folder" "has cases but no variant folder" "rm -rf \"\$O/$PH\""
refuse "variant not its group_id" "variant is not its group_id" "sed -i.bak '1s/\"variant\":\"$PT\"/\"variant\":\"pd-other\"/' \"\$O/cases.jsonl\""
refuse "an extra field" "needs exactly the fields" "sed -i.bak '1s/}\$/,\"note\":\"x\"}/' \"\$O/cases.jsonl\""
refuse "a slug that is not pd-<slug>" "group_id is not pd-<slug>" "echo '{\"group_id\":\"Bug_1\",\"criterion\":\"x\",\"answer\":\"FAIL\",\"variant\":\"Bug_1\"}' >>\"\$O/cases.jsonl\""
refuse "a repeated criterion" "already has this criterion" "head -n 1 \"\$O/cases.jsonl\" >>\"\$O/cases.jsonl\""
refuse "a symlink in a variant" "is not a regular file" "ln -s /etc/hosts \"\$O/$PT/hosts.mjs\""
refuse "a variant without app-server.mjs" "has no app-server.mjs" "rm \"\$O/$PH/app-server.mjs\""
refuse "a changed variant over an imported one" "already holds a different variant" "echo changed >>\"\$O/$PH/app-server.mjs\""
refuse "a missing cases.jsonl" "cases.jsonl does not exist" "rm \"\$O/cases.jsonl\""
refuse "a line that is not JSON" "line 7 is not JSON" "echo '{not json' >>\"\$O/cases.jsonl\""
refuse "a criterion that normalizes to empty" "criterion is empty" "echo '{\"group_id\":\"$PT\",\"criterion\":\"  [ ]  \",\"answer\":\"FAIL\",\"variant\":\"$PT\"}' >>\"\$O/cases.jsonl\""
# split's own refusal (here an outside answers.json that is not an object) copies no variant either.
planted_out "$O"; sed -i.bak "s/$PT/$NEWS/g" "$O/cases.jsonl"; mv "$O/$PT" "$O/$NEWS"; rm -rf "$O/$PH"; grep -v "\"$PH\"" "$O/cases.jsonl" >"$O/c" && mv "$O/c" "$O/cases.jsonl"
INEW="$(pid "$NEWS")"
cp "$R.outside/answers.json" "$TMP/answers.keep" && echo '[]' >"$R.outside/answers.json"
run "$R" import-planted "$O"
expect_fail "import-planted: split's refusal is passed on" held_out_answers_incomplete "is not a JSON object"
[ ! -e "$R/selvedge/eval/tuning/variants/$INEW" ] && [ ! -e "$R.outside/variants/$INEW" ] && [ ! -e "$O/imported-ids.tsv" ] \
  && ok "import-planted: split refused, so no variant was copied and no id list written" || ko "import-planted: variant copied though split refused"
cp "$TMP/answers.keep" "$R.outside/answers.json"
rm -rf "$TMP/eval-after-import" "$TMP/outside-after-import"

# --- the default outside folder is under HOME (here the temp HOME) ----------------------------------
d="$(import_mod 'process.stdout.write(M.heldOutDir({}))')"
[ "$d" = "$HOME/.claude/selvedge-eval/held-out" ] && ok "SELVEDGE_EVAL_HELD_OUT unset: ~/.claude/selvedge-eval/held-out" || ko "default outside folder: $d"

# --- each reason token on exactly one code line; listed in the header and the README -----------------
TOKENS="split_unreadable defect_on_both_sides case_on_wrong_side case_invalid held_out_answer_committed real_bug_entry_incomplete no_tracked_files manifest_empty manifest_invalid manifest_mismatch manifest_missing_file manifest_extra_file held_out_answers_incomplete start_folder_not_clean planted_import_invalid"
for t in $TOKENS; do
  n="$(grep -vE '^[[:space:]]*//' "$MOD" | grep -cE "(^|[^a-z_])${t}([^a-z_]|$)")"
  h="$(grep -E '^//' "$MOD" | grep -cE "(^|[^a-z_])${t}([^a-z_]|$)")"
  r="$(grep -cF "\`$t\`" "$PLUGIN_DIR/eval/README.md")"
  [ "$n" -eq 1 ] && [ "$h" -ge 1 ] && [ "$r" -ge 1 ] && ok "token $t: one code line, in the header, in eval/README.md" || ko "token $t: $n code line(s), header $h, README $r"
done

# --- the real tree: check-leak passes once the set is committed --------------------------------------
present="$(git -C "$REPO_ROOT" ls-files -- selvedge/eval/split.json selvedge/eval/tuning/cases.json selvedge/eval/held-out/cases.json selvedge/eval/real-bugs.json)"
run "$REPO_ROOT" check-leak
if [ -n "$present" ]; then
  expect_ok "check-leak: the real tree"
else
  expect_fail "check-leak: the real tree has no set committed yet, so it fails closed" split_unreadable
fi

finish
