#!/usr/bin/env bash
# test-propose-scorecard.sh - self-tests for propose-scorecard.sh, the SCORECARD basis of
# `/propose` (`--from-scorecard`). HERMETIC: the registry, the state dir with its records and the
# checkout the basis runs in are all built under one mktemp -d tree OUTSIDE the repo root, and every
# call passes --state-dir and --registry explicitly, so no real `.supervisor/` is ever read. No
# network, no gh. Exit 0 = all pass, 1 = any failure. Registered automatically by ci.yml's
# test-*.sh glob.
#
# Cases:
#   AC4  a fixture scorecard with exactly two non-critical `review:` features (one never ran, one ran
#        without catching) ⇒ exactly two drafts `scorecard--<slug>.md`, each carrying the numbers,
#        the record paths, an Enhance and a Retire option, `## Depends on` / `## Touches` (lint-clean
#        under plan-waves --lint) and `## Status: proposed`; the run touches nothing outside
#        proposed/ (a checksum snapshot of the whole fixture tree, before vs after).
#   AC8  a `critical: true` feature that would otherwise be `review:` (the builder holds it at its
#        critical keep) gets no draft; neither does a `keep`, an `insufficient data` or a record-none
#        feature.
#        Retire surfaces are the tracked files `git grep -lF <id>` finds in the run's checkout.
#        Determinism: a second run rewrites byte-identical drafts.
#   ERR  a missing registry (scorecard status error), an all-clear scorecard and a --since later
#        than every record each write nothing - not even the output directory - say why, exit 0.
#   DUP  two ids that slugify alike: one draft, the second id named and skipped.
#   MUT  mutation controls on copies placed beside copies of their siblings (gated on non-empty,
#        differs from the original, `bash -n` clean, and an unmutated copy in the same place
#        passing): the `review:` prefix flipped to `keep` changes which features are drafted; the
#        shared guarded-write call deleted leaves no draft at all.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/propose-scorecard.sh"
BUILDER="$HERE/build-feature-scorecard.sh"
COMMON="$HERE/propose-common.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "FATAL: jq is not on PATH - the harness itself requires it"
  exit 1
fi
for f in "$SUT" "$BUILDER" "$COMMON"; do
  [ -f "$f" ] || { echo "FATAL: required script missing: $f"; exit 1; }
done

ROOT="$(mktemp -d)"
ROOT="$(cd "$ROOT" && pwd -P)"
trap 'rm -rf "$ROOT" 2>/dev/null' EXIT

# ---------------------------------------------------------------------------- fixtures
# A checkout (git repo) holding the state dir, the registry and one tracked file that names the
# never-ran feature (its Retire surface).
PROJ="$ROOT/proj"
SD="$PROJ/.supervisor"
mkdir -p "$PROJ/src" "$SD/nr" "$SD/cw" "$SD/cr" "$SD/kp" "$SD/sm"
( cd "$PROJ" && git init -q . )
printf 'wires never_fires into the pipeline\n' > "$PROJ/src/wiring.conf"
printf '.supervisor/\n' > "$PROJ/.gitignore"
git -C "$PROJ" add src/wiring.conf .gitignore >/dev/null 2>&1

for n in 1 2 3; do
  printf '{"v":"skipped"}\n' > "$SD/nr/2026-10-0$n-a.json"     # never ran
  printf '{"v":"ran"}\n'     > "$SD/cw/2026-10-0$n-a.json"     # ran, never caught
  printf '{"v":"ran"}\n'     > "$SD/cr/2026-10-0$n-a.json"     # same, but critical
  v=ran; [ "$n" = 2 ] && v=hit
  printf '{"v":"%s"}\n' "$v" > "$SD/kp/2026-10-0$n-a.json"     # caught once
done
printf '{"v":"ran"}\n' > "$SD/sm/2026-10-01-a.json"             # below min_sample

feat() {   # feat <id> <critical> <dir>
  printf '{"id":"%s","critical":%s,"record":{"glob":"%s/*.json","format":"json","field":"v"},"ran":{"match":"^(ran|hit)$"},"caught":{"match":"^hit$"},"cost":"none"}' "$1" "$2" "$3"
}
REG="$PROJ/registry.json"
{
  printf '{"schema_version":1,"min_sample":3,"not_features":[],"features":[\n'
  feat never_fires false nr; printf ',\n'
  feat costly-lens false cw; printf ',\n'
  feat guard_x true cr; printf ',\n'
  feat keeper false kp; printf ',\n'
  feat small_one false sm; printf ',\n'
  printf '{"id":"silent","critical":false,"record":"none"}\n]}\n'
} > "$REG"
jq -e . "$REG" >/dev/null 2>&1 || { echo "FATAL: fixture registry is not valid JSON"; exit 1; }

OUTP="$SD/requirements/proposed"

# snapshot <file> - path + checksum of every file and every directory of the fixture checkout
# (state dir, registry, records, .git) except the proposed/ tree the basis is allowed to write.
snapshot() {
  ( cd "$PROJ" && find . -path "./.supervisor/requirements" -prune -o -print | env LC_ALL=C sort \
      | while IFS= read -r p; do
          if [ -f "$p" ]; then printf '%s %s\n' "$p" "$(cksum < "$p")"; else printf '%s dir\n' "$p"; fi
        done ) > "$1"
}

# run_sut [script] [args...] - runs in the fixture checkout with the DEFAULT output dir.
run_sut() {
  rs_scr="$1"; shift
  ( cd "$PROJ" && bash "$rs_scr" "$@" ) >"$ROOT/last.out" 2>"$ROOT/last.err"
}
drafts() { find "$1" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sed 's|.*/||' | env LC_ALL=C sort | tr '\n' ' '; }

# ---------------------------------------------------------------------------- AC4 / AC8
echo "== AC4/AC8: two review: features (one critical held at keep) => exactly two drafts, nothing else changes =="
snapshot "$ROOT/before.snap"
run_sut "$SUT" --state-dir "$SD" --registry "$REG"; rc=$?
snapshot "$ROOT/after.snap"
[ "$rc" -eq 0 ] && ok "exit 0" || no "exit $rc"
got="$(drafts "$OUTP")"
[ "$got" = "scorecard--costly-lens.md scorecard--never-fires.md " ] \
  && ok "exactly two drafts: scorecard--costly-lens.md, scorecard--never-fires.md" \
  || no "draft set '$got' (stderr: $(tr '\n' '|' < "$ROOT/last.err"))"
n_all="$(find "$OUTP" -mindepth 1 2>/dev/null | awk 'END { print NR + 0 }')"
[ "$n_all" -eq 2 ] && ok "proposed/ holds only the two drafts (no temp file, no README)" \
  || no "proposed/ holds $n_all entries: $(ls -A "$OUTP" 2>/dev/null | tr '\n' ' ')"
[ ! -e "$OUTP/scorecard--guard-x.md" ] && ok "AC8: no draft for the critical feature (guard_x)" \
  || no "AC8: a draft was written for the critical feature guard_x"
for gone in keeper small-one silent; do
  [ ! -e "$OUTP/scorecard--$gone.md" ] && ok "no draft for non-review feature '$gone'" \
    || no "a draft was written for non-review feature '$gone'"
done
if cmp -s "$ROOT/before.snap" "$ROOT/after.snap"; then
  ok "AC4: nothing outside proposed/ changed (whole fixture checkout, incl. state dir, registry and .git)"
else
  no "AC4: the run changed something outside proposed/: $(diff "$ROOT/before.snap" "$ROOT/after.snap" | head -5 | tr '\n' '|')"
fi
[ -s "$ROOT/last.out" ] && no "stdout is not empty: $(head -2 "$ROOT/last.out")" || ok "stdout empty (messages go to stderr)"

NF="$OUTP/scorecard--never-fires.md"; CW="$OUTP/scorecard--costly-lens.md"
echo "== AC4: each draft carries the numbers, the record paths and both options =="
for spec in "never_fires|nr|$NF|ran: 0|ran in none of them" "costly-lens|cw|$CW|ran: 3|caught nothing"; do
  IFS='|' read -r id dir f ranline hint <<<"$spec"
  missing=""
  for want in "# Proposed: enhance or retire \`$id\` (feature scorecard)" \
              "- runs available: 3" "- $ranline" "- caught: 0" "- cost total: unknown" "- last fired:" \
              "- record: $SD/$dir/*.json" "### Enhance" "### Retire" "$hint" \
              "## Suggested acceptance" ; do
    grep -qF -- "$want" "$f" 2>/dev/null || missing="$missing [$want]"
  done
  for sec in "## Depends on" "## Touches" "## Status: proposed"; do
    grep -qxF -- "$sec" "$f" 2>/dev/null || missing="$missing [$sec]"
  done
  [ -z "$missing" ] && ok "$id draft: numbers, record path, Enhance + Retire, planner sections, status" \
    || no "$id draft is missing:$missing"
done
grep -qxF -- '- src/wiring.conf' "$NF" && ok "Retire lists the tracked file that names never_fires (git grep -lF)" \
  || no "Retire surfaces for never_fires: $(awk '/^### Retire/,/^## Suggested/' "$NF" | tr '\n' '|')"
grep -qF 'git grep -lF costly-lens` found nothing' "$CW" && ok "Retire says so when no tracked file names the feature" \
  || no "costly-lens Retire did not state that no surface was found"
! grep -qF '.supervisor' <<<"$(awk '/^### Retire/,/^## Suggested/' "$NF")" \
  && ok "Retire never lists an ignored .supervisor/ path" || no "Retire listed a .supervisor/ path"

lint="$(bash "$HERE/automate-helpers.sh" plan-waves "$NF" --lint --root "$PROJ" 2>&1)"; lrc=$?
[ "$lrc" -eq 0 ] && grep -qF 'Depends on ok' <<<"$lint" && ok "plan-waves --lint accepts the draft" \
  || no "plan-waves --lint rc=$lrc: $(printf '%s' "$lint" | head -n1)"

echo "== determinism: a second run rewrites byte-identical drafts =="
cp "$NF" "$ROOT/nf.1"; cp "$CW" "$ROOT/cw.1"
run_sut "$SUT" --state-dir "$SD" --registry "$REG"
cmp -s "$NF" "$ROOT/nf.1" && cmp -s "$CW" "$ROOT/cw.1" && [ "$(drafts "$OUTP")" = "scorecard--costly-lens.md scorecard--never-fires.md " ] \
  && ok "re-run: same two files, byte-identical" || no "re-run changed the drafts or the set"

# ---------------------------------------------------------------------------- ERR
echo "== ERR: error / all-clear / empty-window scorecards write nothing and say why =="
rm -rf "$SD/requirements"
run_sut "$SUT" --state-dir "$SD" --registry "$ROOT/no-such-registry.json"; rc=$?
[ "$rc" -eq 0 ] && [ ! -e "$SD/requirements" ] && grep -qF 'reported an error' "$ROOT/last.err" \
  && ok "missing registry: exit 0, no output dir created, the error is named" \
  || no "missing registry: rc=$rc, out exists=$([ -e "$SD/requirements" ] && echo y || echo n), stderr: $(tr '\n' '|' < "$ROOT/last.err")"

printf '{"schema_version":1,"min_sample":3,"not_features":[],"features":[%s]}\n' "$(feat keeper false kp)" > "$ROOT/allclear.json"
run_sut "$SUT" --state-dir "$SD" --registry "$ROOT/allclear.json"; rc=$?
[ "$rc" -eq 0 ] && [ ! -e "$SD/requirements" ] && grep -qF 'nothing proposed' "$ROOT/last.err" \
  && ok "all-clear scorecard: exit 0, nothing written, says why" \
  || no "all-clear: rc=$rc, stderr: $(tr '\n' '|' < "$ROOT/last.err")"

run_sut "$SUT" --state-dir "$SD" --registry "$REG" --since 2030-01-01; rc=$?
[ "$rc" -eq 0 ] && [ ! -e "$SD/requirements" ] \
  && ok "--since later than every record (all insufficient data): nothing written" \
  || no "--since 2030-01-01: rc=$rc, drafts: $(drafts "$OUTP")"

printf '{"schema_version":1,"min_sample":3,"not_features":[],"features":[]}\n' > "$ROOT/empty.json"
run_sut "$SUT" --state-dir "$SD" --registry "$ROOT/empty.json"; rc=$?
[ "$rc" -eq 0 ] && [ ! -e "$SD/requirements" ] && grep -qF 'lists no features' "$ROOT/last.err" \
  && ok "empty scorecard: exit 0, nothing written, says why" \
  || no "empty scorecard: rc=$rc, stderr: $(tr '\n' '|' < "$ROOT/last.err")"

# ---------------------------------------------------------------------------- DUP
echo "== DUP: two ids that slugify alike => one draft, the second named and skipped =="
printf '{"schema_version":1,"min_sample":3,"not_features":[],"features":[%s,%s]}\n' \
  "$(feat dup_a false nr)" "$(feat dup-a false nr)" > "$ROOT/dup.json"
run_sut "$SUT" --state-dir "$SD" --registry "$ROOT/dup.json"
[ "$(drafts "$OUTP")" = "scorecard--dup-a.md " ] && grep -qF '# Proposed: enhance or retire `dup_a`' "$OUTP/scorecard--dup-a.md" \
  && grep -qF 'skipping dup-a' "$ROOT/last.err" \
  && ok "first id kept, second skipped with its reason named" \
  || no "slug collision: drafts '$(drafts "$OUTP")', stderr: $(tr '\n' '|' < "$ROOT/last.err")"
rm -rf "$SD/requirements"

# ---------------------------------------------------------------------------- MUT
echo "== MUT: mutation controls (copies beside copies of their siblings) =="
MD="$ROOT/mut"; mkdir -p "$MD"
cp "$BUILDER" "$MD/build-feature-scorecard.sh"; cp "$COMMON" "$MD/propose-common.sh"
cp "$SUT" "$MD/propose-scorecard.sh"
# Control: the unmutated copy in this location drafts the same two files, so a red mutant below is
# the mutation and not a missing sibling.
run_sut "$MD/propose-scorecard.sh" --state-dir "$SD" --registry "$REG"
[ "$(drafts "$OUTP")" = "scorecard--costly-lens.md scorecard--never-fires.md " ] \
  && ok "control: the unmutated copy drafts the same two files" \
  || no "control: unmutated copy drafted '$(drafts "$OUTP")' - the mutation results below are meaningless"
rm -rf "$SD/requirements"

# mutant_ok <mutant> - non-empty, differs from the original, bash -n clean.
mutant_ok() { [ -s "$1" ] && ! cmp -s "$1" "$SUT" && bash -n "$1" 2>/dev/null; }

sed 's/startswith("review:")/startswith("keep")/' "$SUT" > "$MD/m1.sh"
if mutant_ok "$MD/m1.sh"; then
  run_sut "$MD/m1.sh" --state-dir "$SD" --registry "$REG"
  [ "$(drafts "$OUTP")" != "scorecard--costly-lens.md scorecard--never-fires.md " ] \
    && ok "mutant (review: prefix -> keep) drafts a different set ('$(drafts "$OUTP")') - the prefix match is load-bearing" \
    || no "mutant (review: prefix -> keep) still drafted the two review: features - the AC4 assertion cannot see the filter"
else no "mutant m1 is empty, identical to the original or not bash -n clean - not trusted"; fi
rm -rf "$SD/requirements"

sed 's/pc_guarded_write//' "$SUT" > "$MD/m2.sh"
if mutant_ok "$MD/m2.sh"; then
  run_sut "$MD/m2.sh" --state-dir "$SD" --registry "$REG"; rc=$?
  [ -z "$(drafts "$OUTP")" ] && [ "$rc" -eq 0 ] \
    && ok "mutant (guarded-write call deleted) writes no draft - every draft goes through the shared guard" \
    || no "mutant (guarded-write call deleted) still wrote '$(drafts "$OUTP")' (rc=$rc) - a second write path exists"
else no "mutant m2 is empty, identical to the original or not bash -n clean - not trusted"; fi
rm -rf "$SD/requirements"

echo ""
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
