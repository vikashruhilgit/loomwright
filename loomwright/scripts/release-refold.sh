#!/usr/bin/env bash
# release-refold.sh — the release step every sequential-path push runs first (#512).
#
# usage: bash release-refold.sh [--root <dir>]     (default: the git top level of the cwd)
#
# WHY: a project with the changelog-fragment convention (scripts/bump-version.sh folding
# changelog.d/ fragments into ONE version bump — loomwright's own, decision P7 in its
# changelog.d/README.md) used to require the bump to be the PR's LAST commit. On a sequential run
# the bump lands during EXECUTE / FINALIZE, and every Phase 4.5 heal commit and every
# /review-pr drain commit lands after it, so the rule broke whenever a heal round fixed anything
# (#367), and a fix that added a fragment could not be folded without hand-editing the bump. The
# rule is now a CONTENT rule (`bump-version.sh --check`, run by CI), and THIS script is the one
# mechanical step that keeps it true at every push: a fragment added after the branch's bump is
# re-folded into that same bump here, before the push, so no later commit can leave it unfolded.
#
# WHAT IT DOES, in order:
#   1. no scripts/bump-version.sh in the project, or one without a `--refold` mode (another
#      project's script of the same name) ⇒ `release-refold: skipped — …`, exit 0. It never runs a
#      script it does not recognise.
#   2. runs `bash scripts/bump-version.sh --refold`. That is a no-op unless the branch already
#      carries a bump AND a fragment is pending, so a fragments-only branch (a parallel lane — the
#      wave release lane bumps once, later) is left exactly as it is. A refusal (the existing bump
#      is not reproducible: a hand edit) ⇒ exit 1 with its reason — do not push.
#   3. when it re-folded, commits exactly the paths it printed on its `refold-touched:` line (other
#      staged or unstaged work is never swept in): `chore(release): re-fold changelog fragments
#      into this branch's bump`.
#   4. runs `bash scripts/bump-version.sh --check`: exit 1 (the content is known to be wrong — a
#      hand-edited CHANGELOG.md or version file) ⇒ exit 1 with its findings — do not push; exit 2
#      (it cannot check here: no base ref, a shallow clone) ⇒ a NOTE, exit 0 (CI's check is the gate).
#
# Exit: 0 = nothing to do / skipped / re-folded and committed, content consistent or unverifiable
#       here; 1 = do not push (refused, check failed, or the commit failed).
# Fail-CLOSED on purpose: the callers treat exit 1 like a failed push (Phase 4.5 pauses, FINALIZE
# aborts before the push, the /review-pr drain escalates), so the hook-style `|| true` must never
# be appended to a call of it.
# Portability: bash 3.2 + BSD userland.
set -uo pipefail

root=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root) [ "$#" -ge 2 ] || { echo "release-refold: --root needs a dir" >&2; exit 1; }; root="$2"; shift ;;
    -h|--help) sed -n '2,4p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "release-refold: unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done
[ -n "$root" ] || root="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$root" ] && [ -d "$root" ] || { echo "release-refold: skipped — not inside a git work tree"; exit 0; }
cd "$root" || exit 1

BUMP="scripts/bump-version.sh"
if [ ! -f "$BUMP" ]; then
  echo "release-refold: skipped — no $BUMP in this project"
  exit 0
fi
if ! grep -q -e '--refold' "$BUMP"; then
  echo "release-refold: skipped — $BUMP has no --refold mode (not the changelog-fragment convention)"
  exit 0
fi

log="$(bash "$BUMP" --refold 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then
  printf '%s\n' "$log"
  echo "release-refold: REFUSED — $BUMP --refold exit $rc; do not push (fix the release files as it says, then re-run)"
  exit 1
fi

touched="$(printf '%s\n' "$log" | sed -n 's/^bump-version: refold-touched: //p' | tail -n 1)"
if [ -n "$touched" ]; then
  printf '%s\n' "$log"
  paths=()
  for p in $touched; do
    if [ -e "$p" ] || git ls-files --error-unmatch -- "$p" >/dev/null 2>&1; then paths[${#paths[@]}]="$p"; fi
  done
  [ "${#paths[@]}" -gt 0 ] || { echo "release-refold: FAILED — the re-fold named no committable path; do not push"; exit 1; }
  git add -A -- "${paths[@]}" || { echo "release-refold: FAILED — git add of the re-folded files failed; do not push"; exit 1; }
  if git diff --cached --quiet -- "${paths[@]}"; then
    echo "release-refold: re-fold produced no change to commit"
  else
    git commit -q -m "chore(release): re-fold changelog fragments into this branch's bump" -- "${paths[@]}" \
      || { echo "release-refold: FAILED — the re-fold commit failed; do not push"; exit 1; }
    echo "release-refold: re-folded and committed $(git rev-parse --short HEAD)"
  fi
else
  printf '%s\n' "$log" | tail -n 1
fi

chk="$(bash "$BUMP" --check 2>&1)"; rc=$?
case "$rc" in
  0) printf '%s\n' "$chk" | tail -n 1 ;;
  2) printf '%s\n' "$chk"; echo "release-refold: NOTE — the content check cannot run here; CI's check is the gate" ;;
  *) printf '%s\n' "$chk"
     echo "release-refold: CHECK FAILED — do not push; fix what the check names (changelog text goes in a changelog.d/ fragment, then re-run bash $BUMP)"
     exit 1 ;;
esac
exit 0
