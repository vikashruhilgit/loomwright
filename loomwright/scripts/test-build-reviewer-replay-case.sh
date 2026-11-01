#!/usr/bin/env bash
# test-build-reviewer-replay-case.sh — the phase45-reviewer corpus builder, the suite's model-free selftest
# as a CI leg, the always-match grader mutant, and the no-model-in-CI rule. Model-free and network-free.
#
#   B   build-reviewer-replay-case.sh against a scratch repo laid out like this one (the builder, the suite's
#       case-template.yaml, its stager and renderer, the live self-heal-advisory SKILL.md), with fixture PR
#       merges on main: a miss, a clean control, a PR with no Phase 4.5 fix commit, a reverted control, a
#       later commit that touches only an unrelated file, a base-merge after the pre-drain head, and a
#       release commit after the pre-drain head. Asserts the --list rows and ledger note, --since, every
#       dry run (base / pre-drain head / expected printed, the tree byte-identical afterwards), every
#       refusal (nothing written), and --confirm (exactly one case dir and one corpus row, the template
#       contract, no expectation in the case dir, the written scaffold stages through lib/stage-case.sh).
#   BM  mutation control for the dry-run assertion: a builder mutant that writes without --confirm must turn
#       the byte-identical-tree check red (the mutant is checked non-empty, different and `bash -n`-clean).
#   E   loomwright/evals/phase45-reviewer/lib/selftest.sh, in ONE leg: the unmutated selftest exits 0; an
#       always-CAUGHT mutant of lib/grade.sh is non-empty, differs from the original and passes `bash -n`;
#       the selftest run through it (PHASE45_GRADE=<mutant>) exits non-zero with a `FAIL: mutation-control`
#       line. A missing selftest fails the leg closed.
#   N   no .github/workflows file and no test-*.sh runs the model-backed eval: no workflow and no test names
#       the eval CLI subcommand or the suite's run command, except a test line that runs the run command
#       under a PATH stub. The patterns are assembled at run time so this file never matches itself.
# bash 3.2 + BSD userland + git + jq + python3.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
REPO="$(cd "$PLUGIN/.." && pwd)"
BUILDER="$HERE/build-reviewer-replay-case.sh"
SUITE="$PLUGIN/evals/phase45-reviewer"

PASS=0; FAIL=0
ok() { echo "PASS: $1"; PASS=$((PASS + 1)); }
no() { echo "FAIL: $1" >&2; FAIL=$((FAIL + 1)); }
WORK="$(mktemp -d)" || { echo "FAIL: mktemp -d" >&2; exit 1; }
trap 'chmod -R u+rwx "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT
TAB="$(printf '\t')"
export HOME="$WORK/home"; mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid \
  GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid

# ---- B: the scratch repo ------------------------------------------------------------------------------------
S="$WORK/src"; SS="$S/loomwright/evals/phase45-reviewer"
mkdir -p "$S/loomwright/scripts" "$SS/lib" "$S/loomwright/skills/self-heal-advisory"
cp "$BUILDER" "$HERE/resolve-base-branch.sh" "$S/loomwright/scripts/" || no "B copy the builder and its base-branch resolver"
cp "$SUITE/case-template.yaml" "$SS/" || no "B copy case-template.yaml"
for f in stage-case.sh render-prompt.sh; do cp "$SUITE/lib/$f" "$SS/lib/" || no "B copy lib/$f"; done
cp "$PLUGIN/skills/self-heal-advisory/SKILL.md" "$S/loomwright/skills/self-heal-advisory/" || no "B copy SKILL.md"
G() { git -C "$S" -c commit.gpgSign=false -c core.autocrlf=false "$@"; }
T=1767225600   # 2026-01-01T00:00:00Z; every commit gets its own later timestamp so --since and order are exact
commit() {   # commit <subject> [<file> <content>]...
  local subj="$1"; shift
  while [ "$#" -ge 2 ]; do mkdir -p "$S/$(dirname "$1")"; printf '%s\n' "$2" >> "$S/$1"; shift 2; done
  T=$((T + 3600))
  G add -A && GIT_AUTHOR_DATE="@$T" GIT_COMMITTER_DATE="@$T" G commit -q --allow-empty -m "$subj"
}
merge_pr() {   # merge_pr <n> <branch> — a GitHub-shaped merge commit onto main
  T=$((T + 3600))
  G checkout -q main && GIT_AUTHOR_DATE="@$T" GIT_COMMITTER_DATE="@$T" \
    G merge -q --no-ff --no-edit -m "Merge pull request #$1 from fixture/$2" "$2"
}
{
  G init -q && G symbolic-ref HEAD refs/heads/main
  printf 'state/\n' > "$S/.gitignore"
  commit "chore: base" a.txt one b.txt one c.txt one z.txt one
  # #101 miss: later fixes change b.txt twice and a.txt once, then a release commit
  G checkout -q -b pr101
  commit "feat: 101" a.txt two b.txt two
  commit "fix: address review feedback (iteration 1)" a.txt three
  commit "fix: drain finding one" b.txt three
  commit "fix: drain finding two" b.txt four a.txt four
  commit "chore(release): v1.0.1" VERSION 1.0.1
  merge_pr 101 pr101
  # #102 clean control: only a release commit after the pre-drain head
  G checkout -q -b pr102
  commit "feat: 102" c.txt two
  commit "fix: address review feedback (iteration 2)" c.txt three
  commit "chore(release): v1.0.2" VERSION 1.0.2
  merge_pr 102 pr102
  # #103 never went through Phase 4.5
  G checkout -q -b pr103
  commit "feat: 103" c.txt four
  merge_pr 103 pr103
  # #104 control-shaped but reverted on main
  G checkout -q -b pr104
  commit "feat: 104" d.txt one
  commit "fix: address review feedback (iteration 1)" d.txt two
  merge_pr 104 pr104
  M104="$(G rev-parse HEAD)"
  T=$((T + 3600)); GIT_AUTHOR_DATE="@$T" GIT_COMMITTER_DATE="@$T" G revert --no-edit -m 1 "$M104"
  # #105 the later commit touches only a file outside the pre-drain diff: neither a miss nor a control
  G checkout -q -b pr105
  commit "feat: 105" e.txt one
  commit "fix: address review feedback (iteration 1)" e.txt two
  commit "docs: unrelated" z.txt two
  merge_pr 105 pr105
  # #106 a base-merge after the pre-drain head: not a control (a later commit), not a miss (no fix commit)
  G checkout -q -b pr106
  commit "feat: 106" f.txt one
  commit "fix: address review feedback (iteration 1)" f.txt two
  G checkout -q main; commit "chore: main moves" g.txt one
  G checkout -q pr106; T=$((T + 3600)); GIT_AUTHOR_DATE="@$T" GIT_COMMITTER_DATE="@$T" G merge -q --no-ff --no-edit main
  merge_pr 106 pr106
  G update-ref refs/remotes/origin/main refs/heads/main
  G symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main   # what a clone has; the resolver reads it
} >/dev/null 2>&1 || no "B build the scratch repo"
PRE101="$(G log --format='%H %s' pr101 | awk '/iteration 1/ { print $1; exit }')"
BASE101="$(G rev-list --max-parents=0 main)"   # the root commit `chore: base` — #101 branched from it
PRE102="$(G log --format='%H %s' pr102 | awk '/iteration 2/ { print $1; exit }')"
mkdir -p "$S/state"; LEDGER="$S/state/results.jsonl"
printf '%s\n' '{"schema_version":1,"repo":"fixture/one","number":101,"self_heal_misses":2}' > "$LEDGER"

# snap — every byte of the working tree (git status incl. ignored + checksums of every non-.git file)
snap() {
  ( cd "$S" && git status --porcelain=v1 --untracked-files=all --ignored \
    && find . -path ./.git -prune -o -type f -print | env LC_ALL=C sort | while IFS= read -r f; do cksum "$f"; done \
    && find . -path ./.git -prune -o -type d -print | env LC_ALL=C sort )
}
BLD="$S/loomwright/scripts/build-reviewer-replay-case.sh"
run() { bash "$BLD" "$@" > "$WORK/out" 2> "$WORK/err"; }

# --list
if run --list --ledger "$LEDGER"; then
  ok "B --list exits 0"
  grep -qE "^\| miss \| 101 \| [0-9a-f]{12} \| $(printf '%s' "$BASE101" | cut -c1-12) \| $(printf '%s' "$PRE101" | cut -c1-12) \| 2 \| 2 \| \`b.txt\` \| shm=2 \|$" "$WORK/out" \
    && ok "B --list: #101 is a miss — base, pre-drain head, later 2 (release excluded), overlap 2, expected b.txt (most touched), ledger shm=2" \
    || no "B --list #101 row wrong: $(grep '| 101 |' "$WORK/out")"
  grep -qE "^\| control \| 102 \| .* \| $(printf '%s' "$PRE102" | cut -c1-12) \| 0 \| 0 \| — \| - \|$" "$WORK/out" \
    && ok "B --list: #102 is a control (a release commit after the pre-drain head is not a later commit; no ledger row ⇒ -)" \
    || no "B --list #102 row wrong: $(grep '| 102 |' "$WORK/out")"
  for n in 103 104 105 106; do
    grep -q "| $n |" "$WORK/out" && no "B --list proposes #$n: $(grep "| $n |" "$WORK/out")" \
      || ok "B --list skips #$n (no fix commit / reverted / unrelated later change / later base-merge)"
  done
  grep -qxF "candidates: miss=1 control=1 (of 6 PR merges scanned)" "$WORK/out" && ok "B --list tally" \
    || no "B --list tally: $(tail -n 1 "$WORK/out")"
else no "B --list failed: $(head -n 3 "$WORK/err")"; fi
SINCE="$(date -u -r $((1767225600 + 9 * 3600)) +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d @$((1767225600 + 9 * 3600)) +%Y-%m-%dT%H:%M:%SZ)"
if run --list --since "$SINCE" --ledger "$LEDGER" && ! grep -q '| 101 |' "$WORK/out" && grep -q '| 102 |' "$WORK/out"; then
  ok "B --list --since drops merges before the date"
else no "B --list --since: $(grep -E '^\| (miss|control)' "$WORK/out" | tr '\n' ' ') $(head -n 2 "$WORK/err")"; fi

# dry runs
BEFORE="$(snap)"
if run --pr 101; then
  grep -qxF "base: $BASE101" "$WORK/out" && grep -qxF "pre_drain_head: $PRE101" "$WORK/out" \
    && grep -qxF "expected: {file: b.txt, severity_floor: HIGH}" "$WORK/out" && grep -qxF "case: 01-miss-pr101" "$WORK/out" \
    && grep -qxF "dry run — nothing written; re-run with --confirm" "$WORK/out" \
    && ok "B --pr 101 prints base, pre_drain_head, expected {file, severity_floor HIGH}, the case id and the dry-run line" \
    || no "B --pr 101 output: $(tr '\n' '|' < "$WORK/out")"
else no "B --pr 101 failed: $(head -n 2 "$WORK/err")"; fi
[ "$(snap)" = "$BEFORE" ] && ok "B dry run: the working tree is byte-identical afterwards" || no "B dry run changed the working tree"
run --pr 101 --floor MEDIUM --file a.txt && grep -qxF "expected: {file: a.txt, severity_floor: MEDIUM}" "$WORK/out" \
  && ok "B --floor / --file override the proposal" || no "B --floor/--file: $(tr '\n' '|' < "$WORK/out") $(head -n 1 "$WORK/err")"
run --pr 102 --control && grep -qxF "expected: none (control)" "$WORK/out" && grep -qxF "case: 01-control-pr102" "$WORK/out" \
  && ok "B --pr 102 --control prints expected: none (control)" || no "B --pr 102 --control: $(tr '\n' '|' < "$WORK/out") $(head -n 1 "$WORK/err")"
[ "$(snap)" = "$BEFORE" ] && ok "B every dry run left the tree byte-identical" || no "B a dry run changed the working tree"

# refusals: non-zero, nothing written (even with --confirm)
refuse() {   # refuse <label> <want stderr fragment> <args…>
  local label="$1" want="$2"; shift 2
  if run "$@"; then no "B refuse $label: exit 0"
  elif ! grep -qF -- "$want" "$WORK/err"; then no "B refuse $label: stderr lacks '$want': $(head -n 2 "$WORK/err")"
  elif [ "$(snap)" != "$BEFORE" ]; then no "B refuse $label: the tree changed"
  else ok "B refuses $label (non-zero, named, nothing written)"; fi
}
refuse "an unknown PR" "no merge commit" --pr 999 --confirm
refuse "a PR with no pre-drain head" "no pre-drain head" --pr 103 --confirm
refuse "a --control with later commits" "not a clean control" --pr 101 --control --confirm
refuse "a reverted --control" "carries a revert" --pr 104 --control --confirm
refuse "a miss with no overlapping later change" "not a miss candidate" --pr 105 --confirm
refuse "a --file outside the pre-drain diff" "not in the pre-drain diff" --pr 101 --file z.txt --confirm
refuse "a bad --floor" "--floor must be" --pr 101 --floor URGENT --confirm
refuse "a non-numeric --pr" "needs a PR number" --pr abc --confirm
refuse "a --file with a newline" "tab or a newline" --pr 101 --file "$(printf 'a.txt\nb.txt')" --confirm
refuse "--list and --pr together" "usage" --list --pr 101
cp "$SS/case-template.yaml" "$WORK/template.good"; grep -vxF 'tags: [CASE_KIND]' "$WORK/template.good" > "$SS/case-template.yaml"; BEFORE="$(snap)"
refuse "a template without its tags placeholder" "not present exactly once" --pr 101 --confirm
cp "$WORK/template.good" "$SS/case-template.yaml"; BEFORE="$(snap)"

# the base branch comes from resolve-base-branch.sh, never a hardcoded `main`: a configured base is honoured
# (`dev` = main as of the #102 merge, local only ⇒ read as the local branch), and an invalid or commit-less
# configured base fails closed with nothing written
M102="$(G log --first-parent --merges --format='%H %s' main | awk '/#102 from/ { print $1; exit }')"
G branch -q dev "$M102" >/dev/null 2>&1 || no "B create the dev fixture branch"
mkdir -p "$S/.supervisor"; CFG="$S/.supervisor/config.json"
printf '{"base_branch":"dev"}\n' > "$CFG"
if run --list && grep -qxF "candidates: miss=1 control=1 (of 2 PR merges scanned)" "$WORK/out" && grep -q '^candidates on dev ' "$WORK/out"; then
  ok "B a configured base branch (.supervisor/config.json base_branch: dev) is the branch scanned"
else no "B configured base not honoured: $(head -n 1 "$WORK/out") / $(tail -n 1 "$WORK/out") $(head -n 1 "$WORK/err")"; fi
printf '{"base_branch":"-bad"}\n' > "$CFG"; BEFORE="$(snap)"
refuse "an invalid configured base branch (the resolver's status token)" "base_branch_invalid:config" --pr 101 --confirm
printf '{"base_branch":"nosuch"}\n' > "$CFG"; BEFORE="$(snap)"
refuse "a base branch that resolves to no commit" "resolves to no commit" --pr 101 --confirm
rm -rf "$S/.supervisor"; G branch -q -D dev >/dev/null 2>&1; BEFORE="$(snap)"

# --confirm: exactly one case dir + one corpus row
CORP="$S/docs/evidence/phase45-reviewer-corpus.tsv"
HDR="case_id${TAB}pr${TAB}kind${TAB}expected_file${TAB}severity_floor"
if run --pr 101 --confirm; then
  ok "B --pr 101 --confirm exits 0"
  new="$(cd "$S" && git status --porcelain --untracked-files=all | tr '\n' ' ')"
  [ "$new" = "?? docs/evidence/phase45-reviewer-corpus.tsv ?? loomwright/evals/phase45-reviewer/01-miss-pr101/case.env ?? loomwright/evals/phase45-reviewer/01-miss-pr101/case.yaml ?? loomwright/evals/phase45-reviewer/01-miss-pr101/scaffold.sh " ] \
    && ok "B --confirm wrote exactly one case dir (case.env, case.yaml, scaffold.sh) and the corpus table" || no "B --confirm wrote: $new"
  [ "$(cat "$CORP")" = "$(printf '%s\n%s' "$HDR" "01-miss-pr101${TAB}101${TAB}miss${TAB}b.txt${TAB}HIGH")" ] \
    && ok "B the corpus table is created with its header and one row" || no "B corpus: $(cat "$CORP" | tr '\t\n' '>|')"
  C="$SS/01-miss-pr101"
  [ "$(cat "$C/case.env")" = "$(printf 'PR=101\nBASE_SHA=%s\nHEAD_SHA=%s' "$BASE101" "$PRE101")" ] \
    && ok "B case.env holds only PR= / BASE_SHA= / HEAD_SHA= (the pre-drain head)" || no "B case.env: $(tr '\n' '|' < "$C/case.env")"
  body() { awk '/^execution:/ { f = 1 } f' "$1"; }
  [ "$(body "$C/case.yaml")" = "$(body "$SS/case-template.yaml")" ] && ok "B case.yaml is byte-identical to the template from execution: on" \
    || no "B case.yaml differs from the template from execution: on"
  grep -qxF "name: 01-miss-pr101" "$C/case.yaml" && grep -qxF "tags: [miss]" "$C/case.yaml" && ! grep -q 'CASE_' "$C/case.yaml" \
    && ok "B case.yaml: name and tags filled in, no placeholder left" || no "B case.yaml placeholders: $(grep -nE 'name:|tags:|CASE_' "$C/case.yaml" | tr '\n' '|')"
  diff <(grep -vxE 'name: .*|tags: \[.*\]|  Miss case: .*' "$C/case.yaml") \
       <(grep -vxE 'name: CASE_ID|tags: \[CASE_KIND\]|  CASE_DESCRIPTION' "$SS/case-template.yaml") >/dev/null \
    && ok "B case.yaml differs from the template only in its name, description and tags lines" || no "B case.yaml differs beyond name/description/tags"
  grep -rqE 'b\.txt|HIGH' "$C" && no "B the case dir carries the expected file or the floor" || ok "B no expectation in the case dir"
  [ -x "$C/scaffold.sh" ] && bash -n "$C/scaffold.sh" && ok "B scaffold.sh is executable and parses" || no "B scaffold.sh not executable/parseable"
else no "B --pr 101 --confirm failed: $(head -n 2 "$WORK/err")"; fi
AFTER1="$(snap)"
if run --pr 102 --control --confirm && grep -qxF "case: 02-control-pr102" "$WORK/out"; then
  [ "$(tail -n 1 "$CORP")" = "02-control-pr102${TAB}102${TAB}control${TAB}${TAB}" ] && [ "$(wc -l < "$CORP" | tr -d ' ')" = 3 ] \
    && ok "B a --control --confirm appends one row with empty expected_file / severity_floor (next ordinal 02)" \
    || no "B control row: $(tail -n 1 "$CORP" | tr '\t' '>')"
  grep -qxF "tags: [control]" "$SS/02-control-pr102/case.yaml" && ok "B the control's case.yaml is tagged control" || no "B control tag missing"
else no "B --pr 102 --control --confirm failed: $(tr '\n' '|' < "$WORK/out") $(head -n 2 "$WORK/err")"; fi
BEFORE="$(snap)"
refuse "a PR that already has a case dir" "already exists" --pr 101 --confirm
printf 'not a header\n' > "$WORK/badcorp"; cp "$CORP" "$WORK/goodcorp"; cp "$WORK/badcorp" "$CORP"; BEFORE="$(snap)"
refuse "a corpus table with a foreign header" "not the corpus header" --pr 105 --file e.txt --confirm
cp "$WORK/goodcorp" "$CORP"

# the written scaffold stages through the suite's stager
SB="$WORK/sandbox"; mkdir -p "$SB"
if ( cd "$SB" && bash "$SS/02-control-pr102/scaffold.sh" ) > "$WORK/stage.log" 2>&1; then
  [ "$(cat "$SB/.eval/case-id")" = 02-control-pr102 ] && [ "$(git -C "$SB" diff --name-only origin/main...HEAD | tr '\n' ' ')" = "c.txt " ] \
    && ok "B the builder-written scaffold.sh stages the PR's pre-drain diff through lib/stage-case.sh" \
    || no "B staged sandbox wrong: case-id $(cat "$SB/.eval/case-id" 2>/dev/null), diff $(git -C "$SB" diff --name-only origin/main...HEAD 2>&1 | tr '\n' ' ')"
else no "B the builder-written scaffold.sh failed to stage: $(tail -n 2 "$WORK/stage.log" | tr '\n' ' ')"; fi

# ---- BM: the dry-run assertion bites on a builder that writes without --confirm --------------------------------
MUT="$WORK/mutant-builder.sh"
sed 's/^CONFIRM=0$/CONFIRM=1/' "$BLD" > "$MUT"
if [ -s "$MUT" ] && ! cmp -s "$MUT" "$BLD" && bash -n "$MUT"; then
  cp "$BLD" "$WORK/orig-builder.sh"; cp "$MUT" "$BLD"
  B0="$(snap)"; bash "$BLD" --pr 105 --file e.txt > /dev/null 2>&1
  [ "$(snap)" != "$B0" ] && ok "BM a builder that ignores --confirm writes on a dry run — the byte-identical-tree check would go red" \
    || no "BM the mutant builder wrote nothing: the dry-run assertion cannot tell"
  cp "$WORK/orig-builder.sh" "$BLD"
else no "BM the builder mutant is empty, identical or does not parse (anchor 'CONFIRM=0' moved?)"; fi

# ---- E: the suite selftest, unmutated and through an always-CAUGHT grader --------------------------------------
ESELF="$SUITE/lib/selftest.sh"
if [ -f "$ESELF" ]; then
  eout="$(HOME="$WORK/eself-home" bash "$ESELF" 2>&1)"; erc=$?
  etally="$(printf '%s\n' "$eout" | tail -n 1)"
  if [ "$erc" -eq 0 ]; then ok "E: lib/selftest.sh — $etally"
  else no "E: lib/selftest.sh — $etally"; printf '%s\n' "$eout" | grep '^FAIL' | sed 's/^/    /' >&2; fi
  GRADE="$SUITE/lib/grade.sh"; MG="$WORK/always-caught-grade.sh"
  awk 'NR == 1 { print; print "echo \"RESULT: CAUGHT\"; exit 0   # mutant: every reply is CAUGHT"; next } { print }' "$GRADE" > "$MG" 2>/dev/null
  if [ -s "$MG" ] && ! cmp -s "$MG" "$GRADE" && bash -n "$MG"; then
    ok "E: the always-CAUGHT grade.sh mutant is non-empty, differs from the original and parses"
    mout="$(HOME="$WORK/eself-mut-home" PHASE45_GRADE="$MG" bash "$ESELF" 2>&1)"; mrc=$?
    if [ "$mrc" -ne 0 ] && grep -q '^FAIL: mutation-control' <<<"$mout"; then
      ok "E: the selftest through the always-CAUGHT grader exits $mrc with a 'FAIL: mutation-control' line"
    else no "E: the always-CAUGHT grader was not caught (rc $mrc; FAIL: mutation-control line $(printf '%s\n' "$mout" | grep -c '^FAIL: mutation-control'))"; fi
  else no "E: the grade.sh mutant is empty, identical to the original or does not parse"; fi
else no "E: $ESELF missing"; fi

# ---- N: no model-backed eval from CI ---------------------------------------------------------------------------
EVAL_ERE='plugin'' +eval'                      # the eval CLI subcommand
RUN_ERE='phase45-reviewer/lib/''run\.sh'       # the suite's one command
hits=""
for f in "$REPO"/.github/workflows/*; do
  [ -f "$f" ] || continue
  h="$(grep -nE "$EVAL_ERE|$RUN_ERE" "$f" | head -n 1)"; [ -z "$h" ] || hits="$hits ${f#"$REPO"/}:$h"
done
[ -z "$hits" ] && ok "N no .github/workflows file runs the eval CLI or the suite's command" || no "N a workflow runs the model-backed eval:$hits"
hits=""; nt=0
for f in "$REPO"/loomwright/scripts/test-*.sh "$REPO"/loomwright/scripts/adapters/*/test-*.sh "$REPO"/scripts/test-*.sh; do
  [ -f "$f" ] || continue; nt=$((nt + 1))
  h="$(grep -nE "$EVAL_ERE" "$f" | head -n 1)"; [ -z "$h" ] || hits="$hits ${f#"$REPO"/}:$h"
  h="$(grep -nE "$RUN_ERE" "$f" | grep -v 'PATH=' | head -n 1)"; [ -z "$h" ] || hits="$hits ${f#"$REPO"/}:$h"
done
[ "$nt" -gt 0 ] || no "N no test-*.sh found (the glob broke)"
[ -z "$hits" ] && ok "N no test-*.sh runs the eval CLI, nor the suite's command outside a PATH stub ($nt tests scanned)" \
  || no "N a test runs the model-backed eval:$hits"

echo "PASS: $PASS FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
