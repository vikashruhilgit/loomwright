#!/usr/bin/env bash
# test-release-refold.sh — suite for release-refold.sh (#512) and the seams that run it.
#
# Part 1 drives the REAL release-refold.sh against throwaway git repos carrying the REAL root
# scripts/bump-version.sh (validators injected through its BUMP_VERSION_VALIDATORS seam), with
# refs/remotes/origin/main at the fork point so the merge base is real:
#   R1 no scripts/bump-version.sh ⇒ skipped · R2 a foreign script of that name (no --refold) is
#   never executed · R3 a fragments-only branch (a parallel lane) is left byte-identical, so the
#   wave release lane still owns the one bump · R4 a fragment a heal fix added after the bump is
#   re-folded into the ONE bump and committed, touching only the release paths (other staged and
#   unstaged work stays out of the commit) · R5 a current bump ⇒ no commit · R6 a hand-edited
#   CHANGELOG.md ⇒ exit 1 (check failed), no commit · R7 a hand-edited bump + a pending fragment ⇒
#   exit 1 (re-fold refused), nothing written · R8 no base ref ⇒ NOTE, exit 0 (CI's check is the gate).
#   Mutation controls: without the --check step R6 passes; without the commit step R4 commits nothing.
# Part 2 pins WHERE the prompts run it, in document order (a moved or dropped step must fail), with
# mutants: Phase 4.5 heal loop (after the fix worker, before write-marker, before the push),
# FINALIZE step 5.5 (after step 5's commits, before step 6's push, before write-marker), the
# Supervisor gate list, and /review-pr's fork-aware push (same-repo: the re-fold, THEN the push; both
# push_fix_to_pr() call sites); and that the parallel wave release step is still the plain bump.
#
# Portability: bash 3.2 + BSD userland; no network.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LW="$(cd "$here/.." && pwd)"
REPO="$(cd "$LW/.." && pwd)"
RR="$here/release-refold.sh"
BUMP="$REPO/scripts/bump-version.sh"
VALIDATE="$REPO/scripts/validate-version.sh"
for f in "$RR" "$BUMP" "$VALIDATE"; do [ -f "$f" ] || { echo "FAIL: missing $f" >&2; exit 1; }; done
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq required" >&2; exit 1; }

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "ok   - $1"; }
no() { fail=$((fail + 1)); echo "FAIL - $1"; }
check() { if [ "$1" -eq 0 ]; then ok "$2"; else no "$2"; fi; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/release-refold-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1 LC_ALL=C
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
export BUMP_VERSION_VALIDATORS="scripts/validate-version.sh:scripts/ok-validator.sh"
g() { local d="$1"; shift; git -C "$d" -c commit.gpgsign=false "$@"; }

PJ="loomwright/.claude-plugin/plugin.json"; MJ=".claude-plugin/marketplace.json"; CL="CHANGELOG.md"

# make_repo <dir> [bump 0|1] — base commit at 1.2.3, origin/main there, branch `feature` with fragment a.md.
make_repo() {
  local d="$1" with_bump="${2:-1}"
  mkdir -p "$d/loomwright/.claude-plugin" "$d/.claude-plugin" "$d/scripts" "$d/changelog.d"
  printf '{\n  "name": "loomwright",\n  "version": "1.2.3"\n}\n' > "$d/$PJ"
  printf '{\n  "name": "atelier",\n  "plugins": [\n    {\n      "name": "loomwright",\n      "source": "./loomwright",\n      "version": "1.2.3"\n    }\n  ]\n}\n' > "$d/$MJ"
  printf '# Changelog\n\n**v1.2.3 — previous:** body.\n' > "$d/$CL"
  printf 'Fragments live here.\n' > "$d/changelog.d/README.md"
  if [ "$with_bump" = 1 ]; then
    cp "$BUMP" "$d/scripts/bump-version.sh"; cp "$VALIDATE" "$d/scripts/validate-version.sh"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$d/scripts/ok-validator.sh"
  fi
  git init -q "$d" && g "$d" symbolic-ref HEAD refs/heads/main && g "$d" add -A && g "$d" commit -q -m base
  g "$d" update-ref refs/remotes/origin/main HEAD
  g "$d" checkout -q -b feature
  printf 'Alpha headline\nAlpha body.\n' > "$d/changelog.d/a.md"; echo code > "$d/feature.txt"
  g "$d" add -A && g "$d" commit -q -m "feature + fragment"
}
bumped() { ( cd "$1" && bash scripts/bump-version.sh >/dev/null 2>&1 ) && g "$1" add -A && g "$1" commit -q -m "chore(release): bump"; }
run_rr() { local d="$1"; shift; ( cd "$d" && bash "${RR_UNDER_TEST:-$RR}" "$@" ) > "$TMP/out" 2>&1; }
tree_sum() { ( cd "$1" && find . -path ./.git -prune -o -type f -print | sort | xargs cksum ) | cksum; }
head_of() { g "$1" rev-parse HEAD; }

echo "# release-refold.sh"
D="$TMP/r1"; make_repo "$D" 0; h="$(head_of "$D")"
run_rr "$D"; rc=$?
[ "$rc" -eq 0 ] && [ "$(head_of "$D")" = "$h" ] && grep -qF 'skipped — no scripts/bump-version.sh' "$TMP/out"; check $? "R1 no bump script ⇒ skipped, exit 0, no commit"

D="$TMP/r2"; make_repo "$D" 0
printf '#!/usr/bin/env bash\ntouch ran.marker\n' > "$D/scripts/bump-version.sh"; g "$D" add -A && g "$D" commit -q -m foreign
run_rr "$D"; rc=$?
[ "$rc" -eq 0 ] && [ ! -e "$D/ran.marker" ] && grep -qF 'has no --refold mode' "$TMP/out"; check $? "R2 a foreign scripts/bump-version.sh is never executed"

D="$TMP/r3"; make_repo "$D"; h="$(head_of "$D")"; before="$(tree_sum "$D")"
run_rr "$D"; rc=$?
[ "$rc" -eq 0 ] && [ "$(head_of "$D")" = "$h" ] && [ "$(tree_sum "$D")" = "$before" ] && [ -f "$D/changelog.d/a.md" ]
check $? "R3 a fragments-only branch (a lane) is left byte-identical — the wave release lane keeps the bump"

D="$TMP/r4"; make_repo "$D"; bumped "$D"
printf 'Late heal fragment\n' > "$D/changelog.d/b.md"; echo "heal" >> "$D/feature.txt"; g "$D" add -A && g "$D" commit -q -m "fix: heal adds a fragment"
echo "unstaged work" >> "$D/feature.txt"; echo staged > "$D/staged.txt"; g "$D" add staged.txt
h="$(head_of "$D")"
run_rr "$D"; rc=$?
[ "$rc" -eq 0 ] && grep -qF 're-folded and committed' "$TMP/out"; check $? "R4 a fragment after the bump ⇒ re-folded and committed (exit 0)"
[ "$(g "$D" rev-parse HEAD~1)" = "$h" ] && [ "$(g "$D" log -1 --format=%s)" = "chore(release): re-fold changelog fragments into this branch's bump" ]
check $? "R4 exactly one new commit, the re-fold"
[ "$(g "$D" show --name-only --format= HEAD | sort | tr '\n' ' ')" = "CHANGELOG.md changelog.d/b.md " ]
check $? "R4 the re-fold commit touches only the release paths"
[ "$(g "$D" status --porcelain | sort | tr '\n' '|')" = " M feature.txt|A  staged.txt|" ]; check $? "R4 unrelated staged and unstaged work stays out of the commit"
[ "$(jq -r .version "$D/$PJ")" = "1.2.4" ] && [ "$(grep -c '^\*\*v1\.2\.4 — Alpha headline; Late heal fragment:\*\* Alpha body\.$' "$D/$CL")" = "1" ] \
  && [ "$(grep -c '^\*\*v' "$D/$CL")" = "2" ]
check $? "R4 still ONE bump (1.2.4), its entry now folds both fragments"
( cd "$D" && bash scripts/bump-version.sh --check >/dev/null 2>&1 ); check $? "R4 the content check passes after the re-fold"
grep -qF 'check OK' "$TMP/out"; check $? "R4 the helper reports the content check"

D="$TMP/r5"; make_repo "$D"; bumped "$D"; h="$(head_of "$D")"
run_rr "$D"; rc=$?
[ "$rc" -eq 0 ] && [ "$(head_of "$D")" = "$h" ]; check $? "R5 a current bump ⇒ nothing committed, exit 0"

D="$TMP/r6"; make_repo "$D"; bumped "$D"
sed 's/Alpha body\./Alpha body, hand-edited./' "$D/$CL" > "$D/cl.tmp" && mv "$D/cl.tmp" "$D/$CL"; g "$D" commit -q -am "fix: reword the entry by hand"
h="$(head_of "$D")"; cp -R "$D" "$TMP/r6m"
run_rr "$D"; rc=$?
[ "$rc" -eq 1 ] && [ "$(head_of "$D")" = "$h" ] && grep -qF 'CHECK FAILED — do not push' "$TMP/out"; check $? "R6 a hand-edited CHANGELOG.md ⇒ exit 1 (do not push), no commit"

D="$TMP/r7"; make_repo "$D"; bumped "$D"
sed 's/Alpha body\./Alpha body, hand-edited./' "$D/$CL" > "$D/cl.tmp" && mv "$D/cl.tmp" "$D/$CL"; g "$D" commit -q -am "hand edit"
printf 'Late\n' > "$D/changelog.d/b.md"; g "$D" add -A && g "$D" commit -q -m late
h="$(head_of "$D")"; before="$(tree_sum "$D")"
run_rr "$D"; rc=$?
[ "$rc" -eq 1 ] && [ "$(head_of "$D")" = "$h" ] && [ "$(tree_sum "$D")" = "$before" ] && grep -qF 'REFUSED' "$TMP/out"
check $? "R7 a hand-edited bump + a pending fragment ⇒ re-fold refused, exit 1, nothing written"

D="$TMP/r8"; make_repo "$D"; g "$D" update-ref -d refs/remotes/origin/main; h="$(head_of "$D")"
run_rr "$D"; rc=$?
[ "$rc" -eq 0 ] && [ "$(head_of "$D")" = "$h" ] && grep -qF "NOTE — the content check cannot run here" "$TMP/out"; check $? "R8 no base ref ⇒ NOTE, exit 0 (CI's check is the gate)"

# Mutation controls on copies of the helper.
awk '/^chk="\$\(bash "\$BUMP" --check/ { print "chk=ok; rc=0"; next } { print }' "$RR" > "$TMP/rr-nocheck.sh"
RR_UNDER_TEST="$TMP/rr-nocheck.sh" run_rr "$TMP/r6m"; rc=$?
[ "$rc" -eq 0 ]; check $? "mutation control: without the --check step a hand-edited CHANGELOG.md would be pushed"
awk '/git commit -q -m "chore\(release\)/ { print "    : no commit \\"; next } { print }' "$RR" > "$TMP/rr-nocommit.sh"
D="$TMP/r4m"; make_repo "$D"; bumped "$D"; printf 'Late\n' > "$D/changelog.d/b.md"; g "$D" add -A && g "$D" commit -q -m late; h="$(head_of "$D")"
RR_UNDER_TEST="$TMP/rr-nocommit.sh" run_rr "$D"
[ "$(head_of "$D")" = "$h" ]; check $? "mutation control: without the commit step the re-fold is left uncommitted (the push would not carry it)"

# ---- Part 2: the seams, in document order ----------------------------------------------------
echo "# seams: where the prompts run the release step"
SHA="$LW/skills/self-heal-advisory/SKILL.md"
AO="$LW/skills/async-orchestration/SKILL.md"
RH="$LW/skills/review-heal/SKILL.md"
SUP="$LW/agents/supervisor.md"
REFOLD='bash "${CLAUDE_PLUGIN_ROOT}/scripts/release-refold.sh"'
line_of() { grep -nF -- "$2" "$1" | head -n 1 | cut -d: -f1; }   # first line number of a fixed string
count_of() { grep -cF -- "$2" "$1"; }

seam_heal() { # <self-heal-advisory file>: after the fix worker's result, before write-marker, before the push
  local f="$1" a b c d
  a="$(line_of "$f" '# Parse FIX_RESULT; increment heal_fixable_issues_fixed')"
  b="$(line_of "$f" "$REFOLD")"
  c="$(line_of "$f" 'guard-finalize-publish.sh" write-marker')"
  d="$(line_of "$f" 'git push  # update PR (regular push, NEVER --force)')"
  [ -n "$a" ] && [ -n "$b" ] && [ -n "$c" ] && [ -n "$d" ] && [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ] && [ "$c" -lt "$d" ] \
    && [ "$(count_of "$f" "$REFOLD")" = "1" ] \
    && grep -qF 'release-refold.sh` exits non-zero before a heal push (#512) | Same as a failed push: pause phase' "$f"
}
seam_finalize() { # <async-orchestration file>: step 5.5 between step 5 and step 6, before write-marker
  local f="$1" a b c d
  a="$(line_of "$f" '5. **Create commits**')"
  b="$(line_of "$f" '5.5. **Release re-fold (#512) — after step 5')"
  c="$(line_of "$f" 'bash scripts/release-refold.sh   # protocol form — the runtime-resolvable form is agents/supervisor.md')"
  d="$(line_of "$f" '6. **Push and create PR')"
  [ -n "$a" ] && [ -n "$b" ] && [ -n "$c" ] && [ -n "$d" ] && [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ] && [ "$c" -lt "$d" ] \
    && grep -qF 'BEFORE `write-marker` and step 6' <<<"$(sed -n "${b}p" "$f")" \
    && grep -qF 'error: "release_refold_refused"' <<<"$(sed -n "${b},${d}p" "$f")"
}
seam_supervisor() { # <supervisor.md>: the gate names the same step, order and failure
  local l; l="$(grep -F 'Release re-fold before the first push (#512)' "$1")"
  grep -qF "$REFOLD" <<<"$l" && grep -qF 'BEFORE `write-marker`' <<<"$l" && grep -qF 'release_refold_refused' <<<"$l"
}
seam_review() { # <review-heal file>: same-repo bullet runs the re-fold FIRST, then the push; both call sites say so
  local f="$1" bullet i j
  bullet="$(grep -F -- '- **Same-repo PR** (`isCrossRepository == false`):' "$f")"
  i="$(printf '%s' "$bullet" | awk -v n="$REFOLD" '{ print index($0, n) }')"
  j="$(printf '%s' "$bullet" | awk '{ print index($0, "git push origin HEAD:<head_ref>") }')"
  [ "${i:-0}" -gt 0 ] && [ "${j:-0}" -gt "$i" ] && grep -qF 'FIRST run the release re-fold' <<<"$bullet" \
    && grep -qF 'Non-zero ⇒ do NOT push; degrade to `ESCALATED`' <<<"$bullet" \
    && [ "$(grep -cF 'push_fix_to_pr()' "$f" | tr -d ' ')" -ge 2 ] \
    && [ "$(grep -F 'push_fix_to_pr() ' "$f" | grep -vcF 'same-repo ⇒ release-refold.sh, then git push origin HEAD:<head_ref>' | tr -d ' ')" = "0" ]
}

seam_heal "$SHA"; check $? "seam: Phase 4.5 runs the re-fold after the fix worker, BEFORE write-marker and the heal push"
seam_finalize "$AO"; check $? "seam: FINALIZE step 5.5 runs it after step 5's commits, before write-marker and step 6's push"
seam_supervisor "$SUP"; check $? "seam: the Supervisor gate list names the same step, order and failure value"
seam_review "$RH"; check $? "seam: /review-pr same-repo push runs the re-fold FIRST, at both push_fix_to_pr() call sites"
grep -qF '(cd "$wt" && bash scripts/bump-version.sh) > "$tmp/bump.log"' "$here/automate-wave.sh"
check $? "seam: the parallel wave release step is still the plain one-time bump (unchanged)"

# Mutants: moving or dropping the step must fail its seam assertion.
M="$TMP/mut"; mkdir -p "$M"
awk -v r="$REFOLD" 'index($0, r) { held = $0; next } /git push  # update PR/ { print; print held; next } { print }' "$SHA" > "$M/sha-moved.md"
! seam_heal "$M/sha-moved.md"; check $? "mutant: the heal re-fold moved after the push fails the seam"
awk -v r="$REFOLD" 'index($0, r) { held = $0; next } /guard-finalize-publish.sh" write-marker/ { print; print held; next } { print }' "$SHA" > "$M/sha-after-marker.md"
! seam_heal "$M/sha-after-marker.md"; check $? "mutant: the heal re-fold moved after write-marker fails the seam"
grep -vF 'bash scripts/release-refold.sh' "$AO" > "$M/ao-dropped.md"
! seam_finalize "$M/ao-dropped.md"; check $? "mutant: FINALIZE without the re-fold line fails the seam"
sed 's/FIRST run the release re-fold/run the release re-fold/' "$RH" > "$M/rh-reworded.md"
! seam_review "$M/rh-reworded.md"; check $? "mutant: a review-heal bullet that no longer says FIRST fails the seam"
awk '/push_fix_to_pr\(\)  .*release-refold.sh, then git push/ && !done { sub(/release-refold.sh, then /, ""); done = 1 } { print }' "$RH" > "$M/rh-callsite.md"
! seam_review "$M/rh-callsite.md"; check $? "mutant: a push_fix_to_pr() call site without the re-fold fails the seam"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
