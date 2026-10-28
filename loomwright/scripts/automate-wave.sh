#!/usr/bin/env bash
# automate-wave.sh — the `/automate --parallel N` wave builder: the ONE writer of a wave branch.
# PROTOCOL AUTHORITY: `skills/automate-loop/SKILL.md` §14 ("The per-wave loop" step 9, "Wave close").
# Dispatched from `automate-helpers.sh` (`exec bash "$(dirname "$0")/automate-wave.sh" wave-build …`),
# so the helpers dispatcher and automate-lanes.sh stay free of any git merge / push; THIS script is the
# carve-out. It SOURCES automate-lanes.sh for the wave resolver (_lanes_wave_resolve) and the lane
# readers (_lanes_state_of, _lt_lock), so what it builds is exactly what `wave-plan` prints.
#
# Usage:
#   wave-build <parent_runfile> [--wave-branch <name>]
#       Performs the steps `automate-lanes.sh wave-plan` prints and stops at an OPEN wave PR. One
#       `wave-build: <step> — <detail>` line per step; the LAST line is the result (`opened`, `done`,
#       `STOPPED` or `refused`). It can run 15+ minutes (the local CI), so the coordinator runs it as a
#       BACKGROUND command and relays that last line.
#
# Steps, in order (owner decision 2026-10-11: the mechanical integration is the engine's; merging the
# wave PR into the base stays the owner's):
#   0. single    a parent whose `## Run Config` carries `- parallel: 1` (single-lane mode, no wave) ⇒
#                `wave-build: refused — single-lane mode (no wave PR)`, exit 1, nothing read or created.
#   1. resolve   _lanes_wave_resolve (automate-lanes.sh): the wave's lanes in planner order (`## Current`
#                `- wave: <k> | items: …`, else the lane-table order), each lane PR's head sha and state
#                (`gh pr view <pr> --json headRefOid,state`), the base (resolve-base-branch.sh;
#                unresolved ⇒ refused, nothing created)
#                and the branch (default `wave/<run_id>-w<k>`).
#   2. lock      `<primary>/.supervisor/automate/<run_id>.wave-build.lock` — the lane table's mkdir lock
#                (holder = this process's pid + start time; a dead holder is reclaimed, a live one is
#                waited on for LOOMWRIGHT_WAVE_LOCK_WAIT_S, default 6, then refused). Released on every
#                exit path (EXIT trap). It deliberately does NOT take `run-lock.sh`: the primary's run
#                lock is the coordinator's `automate-lanes:<run_id>` for the whole wave, so a different
#                owner is refused and a `--session-id` re-entry excludes nobody (two re-entrant
#                wave-builds would both get in) — and releasing it would drop the coordinator's wave lock.
#   3. done      `gh pr list --head <wave-branch> --state all`: an OPEN PR from it ⇒ `wave-build: done —
#                wave PR <url> already open`, exit 0, nothing written (the idempotent re-run); a MERGED
#                one ⇒ refused (run fleet-closeout); unreadable ⇒ refused (fail CLOSED).
#   4. refuse    (exit 1, nothing created) — no lane table / no wave lanes; a wave item with no lane, no
#                PR, an unreadable head sha, or a PR not OPEN; a lane not parked (lane-status's state
#                must read `awaiting_merge` or `ready_for_release`); the wave branch already on origin
#                (no open PR from it) or already a local branch (a STOPPED build's — remove it first);
#                `git fetch origin` failed; origin/<base> or a head sha not fetchable.
#   4b. overlap  _lanes_wave_overlap (automate-lanes.sh, wave.sh): per lane ONE `gh pr diff --name-only`
#                read + the item's declared set (`plan-waves --touches`); one `wave-build: overlap — <file>
#                changed by L1 (outside its Touches), L3 (declared)` line per file 2+ lanes of the wave
#                changed, one `wave-build: drift — …` line per lane whose other drift no lane shares, or
#                `wave-build: overlap — none — …`. WARN-ONLY (owner decision 2026-10-17): it never
#                refuses, holds or reorders a lane; an unreadable diff is one `overlap — NOT-RUN` line.
#                The shared files also go into the wave PR body ("Files changed by more than one lane"),
#                the record line (`; overlap <n> file(s) changed by 2+ lanes` | `; overlap none`) and the
#                result line (`opened — <url> (overlap: <n> file(s) …)`), so the owner sees them in the
#                one line the coordinator relays.
#   5. worktree  `git worktree add -b <wave-branch> <tmp>/wt origin/<base>` off a fresh fetch — never
#                in the primary's working tree; the primary's checked-out branch and index never change.
#   6. merge     `git merge --no-ff <sha> -m "Merge lane <L> (<item>) PR #<n>"` per lane, planner order.
#                A conflict ⇒ `git merge --abort` and STOPPED (exit 2), nothing pushed, worktree kept.
#   7. ci        `bash scripts/ci-local.sh` in the worktree when it has one (log under <tmp>/); non-zero,
#                or a worktree the run left dirty ⇒ STOPPED. Absent ⇒ `ci — skipped (…)`.
#   8. release   `bash scripts/bump-version.sh` when the worktree has it (it writes, never commits), then
#                `git add -A` + ONE commit `chore(release): v<version> — fold wave <k> fragments (<ids>)`
#                — the LAST commit. Failure ⇒ STOPPED. Absent ⇒ `release — skipped (…)`.
#   9. push      `git push -u origin <wave-branch>` — a regular push of the wave branch ONLY (never a
#                force push, never a lane branch, never the base). Failure ⇒ STOPPED, nothing on origin.
#  10. pr        `gh pr create --base <base> --head <wave-branch>` (title `Wave <k> (<run_id>): <ids>`).
#  11. record    ONE parent `## Progress` line via `automate-helpers.sh progress-append`:
#                `<ts> wave built: <wave-branch> — PR <url> (lanes: L1 PR #n, …; ci pass|skipped; release v<x>|skipped;
#                overlap none|<n> file(s) changed by 2+ lanes)`.
#  12. cleanup   the temporary worktree is removed (the branch stays: it is pushed); last line
#                `wave-build: opened — <url>` (+ ` (overlap: <n> file(s) …)` when step 4b found shared files).
# It NEVER merges any PR (the sole merge executor is automate-helpers.sh gate-eval, SKILL §11), NEVER
# merges into the base, NEVER pushes or rewrites a lane branch, NEVER force-pushes.
#
# Exit: 0 opened, or done (already open) · 1 refused (nothing created) · 2 STOPPED (a local worktree and
# branch are kept for the owner at the printed path; nothing pushed — except a failed `gh pr create`
# AFTER the push, whose STOPPED line names the pushed branch and the command to open the PR by hand).
# A correctness-bearing mutator: refusals fail CLOSED, and no STOPPED before step 9 leaves anything on
# origin. Honest limits: a re-run after a STOPPED build refuses on the kept local branch until the owner
# removes it (`git worktree remove <path>` + `git branch -D <wave-branch>`); a re-run after a failed
# `gh pr create` refuses on the pushed branch (open the PR by hand). The lane PRs read merged on GitHub
# only when the wave PR is merged with a merge commit (their heads are then ancestors of the base).
#
# Test seams: LOOMWRIGHT_GH_BIN, LOOMWRIGHT_LANES_HELPERS (the progress-append / reconcile-item
# dispatcher), LOOMWRIGHT_WAVE_LOCK_WAIT_S. bash 3.2 / BSD-userland safe.
set -uo pipefail

WAVE_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
# shellcheck source=automate-lanes.sh
. "$(dirname "$WAVE_SELF")/automate-lanes.sh" || { echo "wave-build: refused — automate-lanes.sh unreadable"; exit 1; }

WB_LOCKF=""; WB_WT=""
# #618 — one opt-in script event per wave-build (docs/TELEMETRY.md "What the engine reports"): a fixed
# code token set at the site (`_wb_refuse @code …` / `_wb_stop @code …`, or WB_CODE before an exit),
# emitted from the EXIT trap. No code ⇒ no event (usage, single-lane mode, an unresolvable run file).
WB_CODE=""; WB_OUTCOME=fail; WB_ROOT=""

_wb() { echo "wave-build: $*"; }
_wb_code() { case "${1:-}" in @*) WB_CODE="${1#@}"; return 0 ;; esac; return 1; }
_wb_refuse() { _wb_code "${1:-}" && shift; _wb "refused — $*"; exit 1; }
_wb_stop() { _wb_code "${1:-}" && shift; _wb "STOPPED — $*"; exit 2; }
_wb_on_exit() {
  [ -n "$WB_LOCKF" ] && _lt_unlock "$WB_LOCKF"
  if [ -n "$WB_CODE" ] && [ -n "$WB_ROOT" ]; then
    bash "$(dirname "$WAVE_SELF")/emit-script-event.sh" --root "$WB_ROOT" automate-wave wave-build \
      "$WB_OUTCOME" "$WB_CODE" >/dev/null 2>&1 </dev/null || true
  fi
  return 0
}

# _wb_short_id <item> — `<initials of the parent dir's hyphen words>/<leading number>` (the W2 commit
# precedent `pa/21, ch/01, tl/07`); no leading number ⇒ the basename; a one-word dir ⇒ its first 2 chars.
_wb_short_id() {
  local b d n ini
  b="$(basename "$1" .md)"; d="$(basename "$(dirname "$1")")"
  n="$(printf '%s' "$b" | sed -n 's/^\([0-9][0-9]*\).*/\1/p')"; [ -n "$n" ] || n="$b"
  case "$d" in .|''|/) printf '%s' "$n"; return 0 ;; esac
  ini="$(printf '%s' "$d" | awk -F- '{ s = ""; if (NF == 1) s = substr($1, 1, 2); else for (i = 1; i <= NF; i++) s = s substr($i, 1, 1); print s }')"
  printf '%s/%s' "$ini" "$n"
}

wave_build() {
  local rf="" wb=""
  trap _wb_on_exit EXIT
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --wave-branch) [ "$#" -ge 2 ] || _wb_refuse "--wave-branch needs a value"; wb="$2"; shift 2 ;;
      -*) _wb_refuse "unknown flag '$1'" ;;
      *) [ -z "$rf" ] || _wb_refuse "unexpected argument '$1'"; rf="$1"; shift ;;
    esac
  done
  [ -n "$rf" ] || _wb_refuse "usage: wave-build <parent_runfile> [--wave-branch <name>]"
  # 0. single-lane mode (`## Run Config` `- parallel: 1`): there is no wave — each lane parks
  # awaiting_merge on its own PR — so nothing is built and nothing is created.
  if _lanes_single_parent "$rf"; then _wb_refuse "single-lane mode (no wave PR)"; fi
  # 1. resolve — the same resolver wave-plan prints from
  _lanes_wave_resolve "$rf" "$wb" || _wb_refuse "$WV_WHY"
  local parent="$WV_PARENT" primary="$WV_PRIMARY" base="$WV_BASE" k="$WV_K" tab n=0 bad=0
  WB_ROOT="$primary"
  local kind lane path item run pr num sha st ls out rc j url
  wb="$WV_WB"; tab="$(printf '\t')"
  n="$(printf '%s' "$WV_ROWS" | grep -c . | tr -d ' ')"
  [ "$n" != 0 ] || _wb_refuse @no_wave_lanes "no wave lanes in $parent.lanes"
  # 2. lock — one wave-build per run at a time (see the header: never run-lock.sh)
  WB_LOCKF="$primary/.supervisor/automate/$parent.wave-build"
  if ! LOOMWRIGHT_LANES_LOCK_WAIT_S="${LOOMWRIGHT_WAVE_LOCK_WAIT_S:-6}" _lt_lock "$WB_LOCKF"; then
    local h; h="$(_lt_holder "$WB_LOCKF.lock")"; WB_LOCKF=""
    _wb_refuse @lock_busy "another wave-build for $parent is running (lock $primary/.supervisor/automate/$parent.wave-build.lock, holder pid ${h%% *})"
  fi
  # 3. done — an open PR from the wave branch means the build already finished
  if ! j="$(cd "$primary" && "$LANES_GH" pr list --head "$wb" --state all --json number,url,state,headRefName --limit 50 2>/dev/null </dev/null)" \
     || ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$j"; then
    _wb_refuse @gh_read_failed "cannot read the PRs from $wb (gh pr list failed) — fail closed"
  fi
  url="$(jq -r --arg b "$wb" '[.[] | select(.headRefName == $b and .state == "OPEN") | .url] | first // empty' <<<"$j" 2>/dev/null)"
  if [ -n "$url" ]; then WB_OUTCOME=pass; WB_CODE=ok; _wb "done — wave PR $url already open"; return 0; fi
  url="$(jq -r --arg b "$wb" '[.[] | select(.headRefName == $b and .state == "MERGED") | .url] | first // empty' <<<"$j" 2>/dev/null)"
  [ -z "$url" ] || _wb_refuse @already_merged "wave PR $url from $wb is already merged — run fleet-closeout"
  # 4. refusals — nothing is created before every one of them passed
  git -C "$primary" ls-remote --exit-code --heads origin "refs/heads/$wb" >/dev/null 2>&1; rc=$?
  case "$rc" in
    0) _wb_refuse @branch_exists "$wb already exists on origin with no open PR — open one by hand, or delete the branch, or pass --wave-branch" ;;
    2) ;;
    *) _wb_refuse @origin_unreadable "cannot read origin (git ls-remote exit $rc) — fail closed" ;;
  esac
  if git -C "$primary" rev-parse -q --verify "refs/heads/$wb" >/dev/null 2>&1; then
    _wb_refuse @branch_exists "local branch $wb already exists (a STOPPED build? see git worktree list) — remove it (git worktree remove <path>; git branch -D $wb) or pass --wave-branch"
  fi
  LN_TABLE="$WV_TABLE"; LN_PRIMARY="$primary"; LN_PARENT="$parent"
  while IFS="$tab" read -r kind lane path item run pr num sha st; do
    [ -n "$kind" ] || continue
    case "$kind" in
      nolane) _wb "refused — wave item $item has no lane in $parent.lanes"; bad=1; continue ;;
      nopr) _wb "refused — $lane has no PR recorded in its run file"; bad=1; continue ;;
      nohead) _wb "refused — $lane PR #$num head sha unreadable"; bad=1; continue ;;
    esac
    [ "$st" = OPEN ] || { _wb "refused — $lane PR #$num is ${st/#-/unreadable}, not OPEN"; bad=1; continue; }
    ls="$(_lanes_state_of "$lane")"
    case "$ls" in awaiting_merge|ready_for_release) ;;
      *) _wb "refused — $lane is not parked (lane-status reads $ls; needs awaiting_merge or ready_for_release)"; bad=1 ;;
    esac
  done <<EOF
$WV_ROWS
EOF
  [ "$bad" = 0 ] || { WB_CODE=lane_not_ready; exit 1; }
  git -C "$primary" fetch -q origin </dev/null >/dev/null 2>&1 || _wb_refuse @fetch_failed "git fetch origin failed"
  local bsha; bsha="$(git -C "$primary" rev-parse -q --verify "refs/remotes/origin/$base^{commit}" 2>/dev/null)"
  [ -n "$bsha" ] || _wb_refuse @fetch_failed "origin/$base not found after the fetch"
  while IFS="$tab" read -r kind lane path item run pr num sha st; do
    [ "$kind" = ok ] || continue
    git -C "$primary" cat-file -e "$sha^{commit}" 2>/dev/null && continue
    git -C "$primary" fetch -q origin "refs/pull/$num/head" </dev/null >/dev/null 2>&1
    git -C "$primary" cat-file -e "$sha^{commit}" 2>/dev/null || { _wb "refused — $lane PR #$num head $sha not fetchable from origin"; bad=1; }
  done <<EOF
$WV_ROWS
EOF
  [ "$bad" = 0 ] || { WB_CODE=fetch_failed; exit 1; }
  # 4b. overlap — the files more than one lane of this wave changed (warn-only: printed here, carried
  # into the wave PR body, the ## Progress record and the result line; never a refusal or a hold)
  _lanes_wave_overlap
  local wo_line
  while IFS= read -r wo_line; do [ -n "$wo_line" ] && _wb "$wo_line"; done <<EOF
$WO_LINES
EOF
  # 5. worktree — off the fresh origin/<base>, never in the primary's working tree
  local tmp wt ids="" lanes_s="" lanes_t=""
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/automate-wave-$parent-w$k.XXXXXX" 2>/dev/null)" || _wb_refuse @worktree_failed "mktemp failed"
  wt="$tmp/wt"
  if ! out="$(git -C "$primary" worktree add -q --no-track -b "$wb" "$wt" "$bsha" 2>&1 </dev/null)"; then
    rm -rf "$tmp"; _wb_refuse @worktree_failed "git worktree add failed: $(printf '%s\n' "$out" | head -1)"
  fi
  WB_WT="$wt"
  _wb "worktree — $wt on $wb off origin/$base ${bsha:0:12}"
  # 6. merges, planner order, exact head shas
  local msg files
  while IFS="$tab" read -r kind lane path item run pr num sha st; do
    [ "$kind" = ok ] || continue
    msg="Merge lane $lane ($item) PR #$num"
    if ! out="$(GIT_MERGE_AUTOEDIT=no git -C "$wt" merge -q --no-ff "$sha" -m "$msg" 2>&1 </dev/null)"; then
      files="$(git -C "$wt" diff --name-only --diff-filter=U 2>/dev/null | paste -sd ',' - | sed 's/,/, /g')"
      git -C "$wt" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 && git -C "$wt" merge --abort >/dev/null 2>&1
      if [ -n "$files" ]; then
        _wb_stop @merge_conflict "conflict merging $lane (PR #$num) in $files — integrate by hand per wave-plan's conflict rules; worktree kept at $wt"
      fi
      _wb_stop @merge_failed "merging $lane (PR #$num) failed: $(printf '%s\n' "$out" | sed '/^$/d' | head -1) — worktree kept at $wt"
    fi
    _wb "merge — $lane ($item) PR #$num ${sha:0:12}"
    ids="${ids:+$ids, }$(_wb_short_id "$item")"
    lanes_s="${lanes_s:+$lanes_s, }$lane PR #$num"
    lanes_t="$lanes_t| $lane | \`$item\` | #$num | \`$sha\` |
"
  done <<EOF
$WV_ROWS
EOF
  # 7. local CI, in the worktree
  local ci=skipped civ="" dirty
  if [ -f "$wt/scripts/ci-local.sh" ]; then
    (cd "$wt" && bash scripts/ci-local.sh) > "$tmp/ci-local.log" 2>&1 </dev/null; rc=$?
    civ="$(grep '^ci-local: ' "$tmp/ci-local.log" 2>/dev/null | tail -1 | cut -c1-200)"
    [ "$rc" = 0 ] || _wb_stop @ci_failed "local CI failed (exit $rc${civ:+: $civ}) — log $tmp/ci-local.log; nothing pushed; worktree kept at $wt"
    ci=pass; _wb "ci — pass${civ:+ ($civ)}"
  else
    _wb "ci — skipped (no scripts/ci-local.sh; the wave PR's CI is the gate)"
  fi
  dirty="$(git -C "$wt" status --porcelain 2>/dev/null | head -3 | cut -c4- | paste -sd ',' - | sed 's/,/, /g')"
  [ -z "$dirty" ] || _wb_stop @worktree_dirty "the worktree is not clean before the release step ($dirty) — nothing pushed; worktree kept at $wt"
  # 8. release step — the LAST commit
  local ver="" rsha=""
  if [ -f "$wt/scripts/bump-version.sh" ]; then
    (cd "$wt" && bash scripts/bump-version.sh) > "$tmp/bump.log" 2>&1 </dev/null; rc=$?
    [ "$rc" = 0 ] || _wb_stop @release_failed "release step failed (bump-version.sh exit $rc: $(grep . "$tmp/bump.log" 2>/dev/null | tail -1 | cut -c1-200)) — log $tmp/bump.log; nothing pushed; worktree kept at $wt"
    if [ -f "$wt/loomwright/.claude-plugin/plugin.json" ]; then ver="$(jq -r '.version // empty' "$wt/loomwright/.claude-plugin/plugin.json" 2>/dev/null)"; fi
    [ -n "$ver" ] || ver="$(sed -n 's/^bump-version: bumped [^ ]* -> \([^ ]*\) .*/\1/p' "$tmp/bump.log" | tail -1)"
    ver="${ver#v}"
    [ -n "$ver" ] || _wb_stop @release_failed "release step ran but the new version is unreadable — log $tmp/bump.log; nothing pushed; worktree kept at $wt"
    [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ] || _wb_stop @release_failed "release step changed nothing — nothing pushed; worktree kept at $wt"
    if ! out="$(git -C "$wt" add -A 2>&1 && git -C "$wt" commit -q -m "chore(release): v$ver — fold wave $k fragments ($ids)" 2>&1 </dev/null)"; then
      _wb_stop @release_failed "release commit failed: $(printf '%s\n' "$out" | sed '/^$/d' | head -1) — nothing pushed; worktree kept at $wt"
    fi
    rsha="$(git -C "$wt" rev-parse HEAD)"
    _wb "release — v$ver committed ${rsha:0:12}"
  else
    _wb "release — skipped (no scripts/bump-version.sh; run this project's release step on the wave branch)"
  fi
  # 9. push — the wave branch only, a regular push
  if ! out="$(git -C "$wt" push -q -u origin "$wb" 2>&1 </dev/null)"; then
    _wb_stop @push_failed "the push of $wb failed: $(printf '%s\n' "$out" | sed '/^$/d' | head -1) — nothing pushed; worktree kept at $wt"
  fi
  _wb "push — origin/$wb at $(git -C "$wt" rev-parse --short=12 HEAD)"
  # 10. the wave PR
  local title body cil rel wo_body=""
  if [ "$WO_N" != 0 ]; then
    wo_body="
### Files changed by more than one lane

Every lane of this wave was built on the same base without seeing the others, so these files merged cleanly (or by hand) without anyone reviewing the lanes' changes to them together. Review each one as a single change before merging:

$(printf '%s\n' "$WO_LINES" | sed -n 's/^overlap — \(.*\) changed by \(.*\)$/- `\1` — \2/p')
"
  fi
  title="Wave $k ($parent): $ids"
  if [ "$ci" = pass ]; then cil="pass${civ:+ (\`$civ\`)}"; else cil="skipped (no \`scripts/ci-local.sh\`; this PR's CI is the gate)"; fi
  if [ -n "$rsha" ]; then rel="\`${rsha:0:12}\` — v$ver (\`scripts/bump-version.sh\`), the last commit"; else rel="skipped (no \`scripts/bump-version.sh\`; run this project's release step on this branch before merging)"; fi
  body="Wave $k of \`/automate\` run \`$parent\`, built by \`wave-build\` (\`scripts/automate-wave.sh\`): each lane PR's exact head merged \`--no-ff\` in planner order onto \`origin/$base\`.

| Lane | Item | PR | Merged head |
|---|---|---|---|
$lanes_t
- Local CI: $cil
- Release commit: $rel
$wo_body
Merging this PR with a merge commit also marks each lane PR above merged on GitHub (their heads are ancestors of this branch; a squash merge would not). Then \`/automate --resume $parent\` runs \`fleet-closeout\`, which closes out and removes every lane. Nothing in the engine merges this PR — that stays the owner's.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
  if ! out="$(cd "$wt" && "$LANES_GH" pr create --base "$base" --head "$wb" --title "$title" --body "$body" 2>&1 </dev/null)"; then
    _wb_stop @pr_create_failed "gh pr create failed: $(printf '%s\n' "$out" | sed '/^$/d' | tail -1 | cut -c1-200) — $wb IS pushed; open the PR by hand: gh pr create --base $base --head $wb; worktree kept at $wt"
  fi
  url="$(printf '%s\n' "$out" | grep -E '^https?://' | tail -1)"
  [ -n "$url" ] || url="$(cd "$wt" && "$LANES_GH" pr list --head "$wb" --state open --json url --jq '.[0].url' 2>/dev/null </dev/null)"
  [ -n "$url" ] || url="(url unreadable — see gh pr list --head $wb)"
  # 11. record
  local line rel_s=skipped; [ -z "$ver" ] || rel_s="v$ver"
  local wo_s="none"; [ "$WO_N" = 0 ] || wo_s="$WO_N file(s) changed by 2+ lanes"
  line="$(date -u +%Y-%m-%dT%H:%M:%SZ) wave built: $wb — PR $url (lanes: $lanes_s; ci $ci; release $rel_s; overlap $wo_s)"
  if bash "$HELPERS" progress-append "$WV_RF" "$line" >/dev/null 2>&1; then _wb "record — $parent ## Progress: $line"
  else _wb "record — WARNING: the ## Progress line could not be appended to $parent.md: $line"; fi
  # 12. cleanup — the branch stays (it is pushed); the temporary worktree goes
  if git -C "$primary" worktree remove --force "$wt" >/dev/null 2>&1; then rm -rf "$tmp"; _wb "cleanup — worktree removed ($wb kept, pushed)"
  else _wb "cleanup — WARNING: git worktree remove refused; remove $wt by hand"; fi
  WB_OUTCOME=pass; WB_CODE=ok
  if [ "$WO_N" = 0 ]; then _wb "opened — $url"
  else _wb "opened — $url (overlap: $WO_N file(s) changed by 2+ lanes of this wave — listed in the PR body; review them before merging)"; fi
  return 0
}

wave_main() {
  local sub="${1:-}"; shift 2>/dev/null || true
  case "$sub" in
    wave-build) wave_build "$@" ;;
    -h|--help|help) awk 'NR >= 2 && /^#/ { sub(/^# ?/, ""); print; next } NR >= 2 { exit }' "$WAVE_SELF" ;;
    *) echo "wave-build: refused — unknown subcommand '$sub' (usage: automate-wave.sh wave-build <parent_runfile> [--wave-branch <name>])"; return 1 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then wave_main "$@"; exit $?; fi
